// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom.db.engine

use xiom.io;
use xiom.db.wal_file;
use xiom.db.storage.page;
use xiom.db.storage.page_file;
use xiom.db.storage.block;
use xiom.db.storage.block_store;
use xiom.db.storage.byte_io;
use xiom.db.storage.tuple;
use xiom.db.error;
use xiom.db.contracts;
use xiom.db.secondary_index;
use xiom.db.catalog.schema;

// ============================================================================
// XIOM-DB: Consolidated Engine -- B-Tree + WAL + Query + Engine + Database API
// ============================================================================
// The single-file engine merges the interdependent modules (index/btree,
// wal/wal_record, wal/wal, query/query, query/planner, engine, api/database)
// so that single-file compilation resolves all cross-module references.

// ============================================================================
// B-TREE INDEX (from xiom.db.index.btree)
// ============================================================================

// Snapshot pin (M3 minimal subset, docs/MVCC.md): a stable read view over
// the node arena. `root` indexes this handle's arena; `lsn` is the highest
// WAL LSN at capture; `generation` is the last committed snapshot generation
// (0 = none). Handle-local; live until `db_file_snapshot_end` or reopen.
pub type DBSnapshot = {
  id: Int;
  root: Int;
  lsn: Int;
  generation: Int;
}

// NodeStore: the node arena behind a B-tree. `dirty[i]` marks node i as
// changed since the last successful snapshot flush; checkpoints encode only
// dirty nodes (M1.1). M3 adds version bookkeeping: `births[i]` is the write
// epoch node i was created in and `pin_clock` counts pin creations; while
// pins exist, a node with `birth <= pin_clock` may be reachable from a pinned
// root and must be shadow-copied before any mutation (see `cow_shadow`).
// `compaction_deferred` counts checkpoint compactions skipped because a pin
// was live (docs/MVCC.md sec. 2.3). The store is fully resident for now --
// lazy load and a bounded cache arrive with the storage spine.
pub type NodeStore = {
  nodes: Vec[BTreeNode];
  dirty: Vec[Bool];
  births: Vec[Int];
  pins: Vec[DBSnapshot];
  pin_clock: Int;
  compaction_deferred: Int;
}

pub fn ns_len(store: &NodeStore) -> Int {
  return store.nodes.len();
}

// Read a node copy.
pub fn ns_get(store: &NodeStore, idx: Int) -> BTreeNode {
  return store.nodes[idx];
}

// Overwrite a node in place and mark it dirty. M3 discipline: the target MUST
// be writable for the current pin state -- i.e. it was produced by `ns_push`
// (which stamps `pin_clock + 1`) or by `cow_shadow` in the same operation.
pub fn ns_set(store: &mut NodeStore, idx: Int, node: BTreeNode) {
  store.nodes[idx] = node;
  store.dirty[idx] = true;
}

// Append a node (new nodes start dirty); returns its index. The birth epoch
// `pin_clock + 1` marks it mutable until a newer pin exists (M3).
pub fn ns_push(store: &mut NodeStore, node: BTreeNode) -> Int {
  store.nodes.push(node);
  store.dirty.push(true);
  store.births.push(store.pin_clock + 1);
  return store.nodes.len() - 1;
}

// Deep copy of a node that OWNS its storage. Struct/Vec assignment shares
// nested Vec buffers and element assignment through a copied handle writes
// through to the source buffer (C-ORBIT-09, docs/repro/vec-copy-alias/), so a
// shadow must rebuild every vector -- keys/values/children and each payload.
fn node_deep_copy(node: &BTreeNode) -> BTreeNode {
  var keys = Vec[Int].new();
  var values = Vec[Int].new();
  var children = Vec[Int].new();
  var payloads = Vec[Vec[Int]].new();
  var i = 0;
  while i < node.keys.len() {
    keys.push(node.keys[i]);
    values.push(node.values[i]);
    i = i + 1;
  }
  i = 0;
  while i < node.children.len() {
    children.push(node.children[i]);
    i = i + 1;
  }
  i = 0;
  while i < node.keys.len() {
    let src = node_payload(node, i);
    var p = Vec[Int].new();
    var k = 0;
    while k < src.len() {
      p.push(src[k]);
      k = k + 1;
    }
    payloads.push(p);
    i = i + 1;
  }
  return BTreeNode{ keys: keys, values: values, payloads: payloads,
                    children: children, is_leaf: node.is_leaf };
}

// M3 copy-on-write: return an index safe to MUTATE for `idx`. Identity while
// no snapshot is pinned (fast path) or when the node was born after the
// newest pin (`birth > pin_clock` -- it cannot be in any pinned view).
// Otherwise the node may be reachable from a pinned root: deep-copy it to a
// fresh slot and return the copy. The caller MUST store the result in the
// (already writable) parent's child pointer or in `tree.root`.
// docs/MVCC.md sec. 2.2.
fn cow_shadow(tree: &mut BTree, idx: Int) -> Int {
  if tree.store.pins.len() == 0 { return idx; }
  if idx < 0 { return idx; }
  if idx >= tree.store.nodes.len() { return idx; }
  if tree.store.births[idx] > tree.store.pin_clock { return idx; }
  let copy = node_deep_copy(&tree.store.nodes[idx]);
  return ns_push(&mut tree.store, copy);
}

// Mark every node clean after a successful snapshot commit (or after a load).
pub fn ns_mark_clean(store: &mut NodeStore) {
  var i = 0;
  while i < store.dirty.len() {
    store.dirty[i] = false;
    i = i + 1;
  }
}

pub type BTree = {
  root: Int;
  order: Int;
  store: NodeStore;
}

pub type BTreeNode = {
  keys: Vec[Int];
  values: Vec[Int];
  // M5.3 typed rows: payload[i] belongs to entry i (parallel to keys/values;
  // empty = plain int entry). For typed rows `values[i]` mirrors the key (the
  // pk), matching the WAL record. See docs/TYPED-VALUES-STORAGE.md.
  payloads: Vec[Vec[Int]];
  children: Vec[Int];
  is_leaf: Bool;
}

fn new_leaf_node() -> BTreeNode {
  var keys = Vec[Int].new();
  var values = Vec[Int].new();
  var payloads = Vec[Vec[Int]].new();
  var children = Vec[Int].new();
  return BTreeNode{ keys: keys, values: values, payloads: payloads,
                    children: children, is_leaf: true };
}

fn new_internal_node() -> BTreeNode {
  var keys = Vec[Int].new();
  var values = Vec[Int].new();
  var payloads = Vec[Vec[Int]].new();
  var children = Vec[Int].new();
  return BTreeNode{ keys: keys, values: values, payloads: payloads,
                    children: children, is_leaf: false };
}

// Defensive parallel-read: a node built before/without payload bookkeeping
// yields the empty payload (plain int entry).
fn node_payload(node: &BTreeNode, i: Int) -> Vec[Int] {
  if i < node.payloads.len() { return node.payloads[i]; }
  return Vec[Int].new();
}

pub fn btree_new(order: Int) -> BTree
  requires: order >= 3
{
  var nodes = Vec[BTreeNode].new();
  var dirty = Vec[Bool].new();
  var births = Vec[Int].new();
  var pins = Vec[DBSnapshot].new();
  var store = NodeStore{ nodes: nodes, dirty: dirty, births: births, pins: pins,
                         pin_clock: 0, compaction_deferred: 0 };
  let leaf = new_leaf_node();
  // The initial leaf must be persisted by the first checkpoint.
  let _ = ns_push(&mut store, leaf);
  return BTree{ root: 0, order: order, store: store };
}

pub fn btree_search(tree: &BTree, key: Int) -> Option[Int] {
  return search_node(tree, tree.root, key);
}

// M5.3: index-free walk that returns the entry's PAYLOAD (typed rows). None
// when the key is absent or the entry carries no payload -- plain int rows
// read through `btree_search`.
pub fn btree_search_payload(tree: &BTree, key: Int) -> Option[Vec[Int]] {
  return search_payload_node(tree, tree.root, key);
}

fn search_payload_node(tree: &BTree, node_idx: Int, key: Int) -> Option[Vec[Int]] {
  var node = tree.store.nodes[node_idx];
  var i = 0;
  while i < node.keys.len() {
    if key == node.keys[i] {
      if i < node.payloads.len() {
        let p = node.payloads[i];
        if p.len() > 0 { return Some(p); }
      }
      return None;
    }
    if key < node.keys[i] {
      if node.is_leaf { return None; }
      if i < node.children.len() {
        return search_payload_node(tree, node.children[i], key);
      }
      return None;
    }
    i = i + 1;
  }
  if node.is_leaf { return None; }
  if i < node.children.len() {
    return search_payload_node(tree, node.children[i], key);
  }
  return None;
}

fn search_node(tree: &BTree, node_idx: Int, key: Int) -> Option[Int] {
  var node = tree.store.nodes[node_idx];
  var i = 0;
  while i < node.keys.len() {
    if key == node.keys[i] {
      return Some(node.values[i]);
    }
    if key < node.keys[i] {
      if node.is_leaf { return None; }
      if i < node.children.len() {
        return search_node(tree, node.children[i], key);
      }
      return None;
    }
    i = i + 1;
  }
  if node.is_leaf { return None; }
  if i < node.children.len() {
    return search_node(tree, node.children[i], key);
  }
  return None;
}

pub fn btree_insert(tree: &mut BTree, key: Int, value: Int) -> Bool {
  var empty = Vec[Int].new();
  return btree_insert_payload(tree, key, value, empty);
}

// M5.3: insert with a typed-row payload; `value` mirrors the key for typed
// rows (the WAL record does the same). Plain inserts pass an empty payload.
pub fn btree_insert_payload(tree: &mut BTree, key: Int, value: Int,
                            payload: Vec[Int]) -> Bool {
  var found = btree_search(tree, key);
  match found {
    Some(_) => return false,
    None => {}
  }
  var max_keys = tree.order - 1;
  if tree.store.nodes[tree.root].keys.len() >= max_keys {
    // split_root only READS the old root and pushes fresh halves, so a pinned
    // root can be split safely without a shadow copy.
    split_root(tree);
  } else {
    // M3: the root about to be mutated must be writable (may be pinned).
    tree.root = cow_shadow(tree, tree.root);
  }
  return insert_nonfull(tree, tree.root, key, value, payload);
}

fn split_root(tree: &mut BTree) {
  var old_root = tree.store.nodes[tree.root];
  var new_root = new_internal_node();
  var mid = old_root.keys.len() / 2;

  var left = new_leaf_node();
  if !old_root.is_leaf { left.is_leaf = false; }
  var right = new_leaf_node();
  if !old_root.is_leaf { right.is_leaf = false; }

  var i = 0;
  while i < mid {
    left.keys.push(old_root.keys[i]);
    left.values.push(old_root.values[i]);
    left.payloads.push(node_payload(&old_root, i));
    if !old_root.is_leaf && i <= mid && i < old_root.children.len() {
      left.children.push(old_root.children[i]);
    }
    i = i + 1;
  }
  if !old_root.is_leaf && mid < old_root.children.len() {
    left.children.push(old_root.children[mid]);
  }

  i = mid + 1;
  while i < old_root.keys.len() {
    right.keys.push(old_root.keys[i]);
    right.values.push(old_root.values[i]);
    right.payloads.push(node_payload(&old_root, i));
    if !old_root.is_leaf && i < old_root.children.len() {
      right.children.push(old_root.children[i]);
    }
    i = i + 1;
  }
  if !old_root.is_leaf && old_root.keys.len() < old_root.children.len() {
    right.children.push(old_root.children[old_root.keys.len()]);
  }

  var left_idx = ns_push(&mut tree.store, left);
  var right_idx = ns_push(&mut tree.store, right);

  new_root.keys.push(old_root.keys[mid]);
  new_root.values.push(old_root.values[mid]);
  new_root.payloads.push(node_payload(&old_root, mid));
  new_root.children.push(left_idx);
  new_root.children.push(right_idx);

  var root_idx = ns_push(&mut tree.store, new_root);
  tree.root = root_idx;
}

fn insert_nonfull(tree: &mut BTree, node_idx: Int, key: Int, value: Int,
                  payload: Vec[Int]) -> Bool {
  var node = tree.store.nodes[node_idx];
  var max_keys = tree.order - 1;

  if node.is_leaf {
    var pos = 0;
    while pos < node.keys.len() && node.keys[pos] < key {
      pos = pos + 1;
    }
    insert_at_pos(tree, node_idx, pos, key, value, payload);
    return true;
  }

  var pos = 0;
  while pos < node.keys.len() && node.keys[pos] < key {
    pos = pos + 1;
  }

  if pos < node.children.len() {
    var child_idx = node.children[pos];
    if tree.store.nodes[child_idx].keys.len() >= max_keys {
      split_child(tree, node_idx, pos);
      var up_node = tree.store.nodes[node_idx];
      if pos < up_node.keys.len() && up_node.keys[pos] < key {
        pos = pos + 1;
      }
    }
    var new_child_idx = tree.store.nodes[node_idx].children[pos];
    // M3: the descended child will be mutated; make it writable first and
    // persist the shadowed index into this (already writable) parent.
    var shadowed_child = cow_shadow(tree, new_child_idx);
    if shadowed_child != new_child_idx {
      var parent = tree.store.nodes[node_idx];
      parent.children[pos] = shadowed_child;
      ns_set(&mut tree.store, node_idx, parent);
      new_child_idx = shadowed_child;
    }
    return insert_nonfull(tree, new_child_idx, key, value, payload);
  }
  return false;
}

fn split_child(tree: &mut BTree, parent_idx: Int, child_pos: Int) {
  var child_idx = tree.store.nodes[parent_idx].children[child_pos];
  // M3: the child is truncated and re-written below; shadow it first and fix
  // the (already writable) parent so both halves are fresh.
  var shadowed_child = cow_shadow(tree, child_idx);
  if shadowed_child != child_idx {
    var p = tree.store.nodes[parent_idx];
    p.children[child_pos] = shadowed_child;
    ns_set(&mut tree.store, parent_idx, p);
    child_idx = shadowed_child;
  }
  var child = tree.store.nodes[child_idx];
  var mid = child.keys.len() / 2;

  var new_child = new_leaf_node();
  if !child.is_leaf { new_child.is_leaf = false; }

  var i = mid + 1;
  while i < child.keys.len() {
    new_child.keys.push(child.keys[i]);
    new_child.values.push(child.values[i]);
    new_child.payloads.push(node_payload(&child, i));
    if !child.is_leaf && i < child.children.len() {
      new_child.children.push(child.children[i]);
    }
    i = i + 1;
  }
  if !child.is_leaf && child.keys.len() < child.children.len() {
    new_child.children.push(child.children[child.keys.len()]);
  }

  var new_child_idx = ns_push(&mut tree.store, new_child);

  var mid_key = child.keys[mid];
  var mid_val = child.values[mid];
  var mid_payload = node_payload(&child, mid);

  while child.keys.len() > mid {
    child.keys.pop();
    child.values.pop();
    child.payloads.pop();
  }
  if !child.is_leaf {
    while child.children.len() > mid + 1 {
      child.children.pop();
    }
  }

  ns_set(&mut tree.store, child_idx, child);
  ns_set(&mut tree.store, new_child_idx, new_child);

  insert_at_pos(tree, parent_idx, child_pos, mid_key, mid_val, mid_payload);

  // Insert the new sibling pointer at child_pos+1. The parent's child list
  // must be SHIFTED right first: a plain index assignment past the end is a
  // silent no-op, which orphaned the new sibling and corrupted the tree at
  // the first internal split (product defect found by probe_core_diag:
  // insert failed from key 8, size=6 of 100).
  var parent = tree.store.nodes[parent_idx];
  parent.children.push(0);
  var j = parent.children.len() - 1;
  while j > child_pos + 1 {
    parent.children[j] = parent.children[j - 1];
    j = j - 1;
  }
  parent.children[child_pos + 1] = new_child_idx;
  ns_set(&mut tree.store, parent_idx, parent);
}

fn insert_at_pos(tree: &mut BTree, node_idx: Int, pos: Int, key: Int, value: Int,
                 payload: Vec[Int]) {
  var node = tree.store.nodes[node_idx];
  node.keys.push(0);
  node.values.push(0);
  node.payloads.push(Vec[Int].new());
  var i = node.keys.len() - 1;
  while i > pos {
    node.keys[i] = node.keys[i - 1];
    node.values[i] = node.values[i - 1];
    node.payloads[i] = node.payloads[i - 1];
    i = i - 1;
  }
  node.keys[pos] = key;
  node.values[pos] = value;
  node.payloads[pos] = payload;
  ns_set(&mut tree.store, node_idx, node);
}

pub fn btree_delete(tree: &mut BTree, key: Int) -> Bool {
  var found = btree_search(tree, key);
  match found {
    None => return false,
    Some(_) => {}
  }
  // M3: only a found key mutates the tree, so the root is shadowed here (a
  // no-op delete must not copy anything).
  tree.root = cow_shadow(tree, tree.root);
  return delete_from_node(tree, tree.root, key);
}

fn delete_from_node(tree: &mut BTree, node_idx: Int, key: Int) -> Bool {
  var node = tree.store.nodes[node_idx];
  // Split scheme: a full node has order-1 keys and splits into halves that
  // differ by one, so the true floor is (order-2)/2 (same as the old formula
  // for even orders, one lower for odd orders -- the old value left order-5
  // nodes permanently under-filled after a split).
  var min_keys = (tree.order - 2) / 2;

  var idx = 0;
  while idx < node.keys.len() && node.keys[idx] < key {
    idx = idx + 1;
  }

  if idx < node.keys.len() && node.keys[idx] == key {
    if node.is_leaf {
      remove_from_leaf(tree, node_idx, idx);
      return true;
    }
    remove_from_internal(tree, node_idx, idx, min_keys);
    return true;
  }

  if node.is_leaf { return false; }

  if idx >= node.children.len() { return false; }
  var child_idx = node.children[idx];

  if tree.store.nodes[child_idx].keys.len() <= min_keys {
    // fill_child returns the NODE INDEX of the (possibly relocated) target
    // child: a merge at child_pos-1 shifts it left. Recursing with the old
    // position instead descended an unrelated node (churn repro op=148).
    // M3: fill_child shadows the child (and any sibling it touches) itself.
    child_idx = fill_child(tree, node_idx, idx, min_keys);
  } else {
    // M3: the descent will mutate this child; shadow it and fix this
    // (already writable) parent.
    var shadowed_child = cow_shadow(tree, child_idx);
    if shadowed_child != child_idx {
      var parent = tree.store.nodes[node_idx];
      parent.children[idx] = shadowed_child;
      ns_set(&mut tree.store, node_idx, parent);
      child_idx = shadowed_child;
    }
  }

  return delete_from_node(tree, child_idx, key);
}

fn remove_from_leaf(tree: &mut BTree, node_idx: Int, pos: Int) {
  var node = tree.store.nodes[node_idx];
  var i = pos;
  while i < node.keys.len() - 1 {
    node.keys[i] = node.keys[i + 1];
    node.values[i] = node.values[i + 1];
    node.payloads[i] = node.payloads[i + 1];
    i = i + 1;
  }
  node.keys.pop();
  node.values.pop();
  node.payloads.pop();
  ns_set(&mut tree.store, node_idx, node);
}

fn remove_from_internal(tree: &mut BTree, node_idx: Int, pos: Int, min_keys: Int) {
  var node = tree.store.nodes[node_idx];
  var key = node.keys[pos];
  var left_child_idx = node.children[pos];
  var right_child_idx = node.children[pos + 1];

  // Predecessor/successor substitution only when the donor subtree can spare
  // a key (the old guard); the Option covers degenerate empty chains inside
  // the donor (order 3), falling through to the merge when neither side can
  // donate. The donor entry's payload moves up with its key/value. M3: the
  // donor read above sees identical content in the shadow copy, so the
  // predecessor is computed BEFORE the donor is shadowed for the delete
  // descent.
  if tree.store.nodes[left_child_idx].keys.len() > min_keys {
    match get_predecessor(tree, left_child_idx) {
      Some(pred) => {
        node.keys[pos] = pred.key;
        node.values[pos] = pred.value;
        node.payloads[pos] = pred.payload;
        var shadowed_left = cow_shadow(tree, left_child_idx);
        if shadowed_left != left_child_idx {
          node.children[pos] = shadowed_left;
          left_child_idx = shadowed_left;
        }
        ns_set(&mut tree.store, node_idx, node);
        delete_from_node(tree, left_child_idx, pred.key);
        return;
      }
      None => {}
    }
  }

  if tree.store.nodes[right_child_idx].keys.len() > min_keys {
    match get_successor(tree, right_child_idx) {
      Some(succ) => {
        node.keys[pos] = succ.key;
        node.values[pos] = succ.value;
        node.payloads[pos] = succ.payload;
        var shadowed_right = cow_shadow(tree, right_child_idx);
        if shadowed_right != right_child_idx {
          node.children[pos + 1] = shadowed_right;
          right_child_idx = shadowed_right;
        }
        ns_set(&mut tree.store, node_idx, node);
        delete_from_node(tree, right_child_idx, succ.key);
        return;
      }
      None => {}
    }
  }

  // Both donors are at the floor: merge the two children around the
  // separator. Safe here because this node holds at least the separator key
  // (the caller only reaches this with a key at `pos`). M3: merge_children
  // shadows the surviving (left) child and returns its fresh index.
  let merged_idx = merge_children(tree, node_idx, pos);
  delete_from_node(tree, merged_idx, key);
}

// True when the subtree rooted at node_idx holds at least one key. Keyless
// chains appear only when min_keys == 0; walking them repeatedly is fine at
// this scale (depth-bounded, and merges keep the tree shallow).
fn subtree_has_key(tree: &BTree, node_idx: Int) -> Bool {
  let node = tree.store.nodes[node_idx];
  if node.keys.len() > 0 { return true; }
  if node.is_leaf { return false; }
  var i = 0;
  while i < node.children.len() {
    if subtree_has_key(tree, node.children[i]) { return true; }
    i = i + 1;
  }
  return false;
}

// One tree entry located by a donor walk: key/value/payload travel together.
type NodeEntry = {
  key: Int;
  value: Int;
  payload: Vec[Int];
}

// In-order predecessor (max) of the subtree at node_idx, or None when the
// subtree is empty. The rightmost path may pass through keyless nodes: when
// the rightmost subtree is empty the predecessor is this node's own last
// key; an empty leaf has none. (The old rightmost-only descent read
// `keys[-1]` on an empty leaf and materialized out-of-bounds garbage -- the
// order-3 defect in xiom.btree SPEC 2.3.)
fn get_predecessor(tree: &BTree, node_idx: Int) -> Option[NodeEntry] {
  var cur = node_idx;
  var guard = 0;
  while guard < 64 {
    guard = guard + 1;
    let node = tree.store.nodes[cur];
    if node.is_leaf {
      if node.keys.len() == 0 { return None; }
      let last = node.keys.len() - 1;
      return Some(NodeEntry{ key: node.keys[last], value: node.values[last],
                             payload: node_payload(&node, last) });
    }
    let last_child = node.children[node.children.len() - 1];
    if subtree_has_key(tree, last_child) {
      cur = last_child;
    } else {
      if node.keys.len() == 0 { return None; }
      let last = node.keys.len() - 1;
      return Some(NodeEntry{ key: node.keys[last], value: node.values[last],
                             payload: node_payload(&node, last) });
    }
  }
  return None;
}

fn get_successor(tree: &BTree, node_idx: Int) -> Option[NodeEntry] {
  var cur = node_idx;
  var guard = 0;
  while guard < 64 {
    guard = guard + 1;
    let node = tree.store.nodes[cur];
    if node.is_leaf {
      if node.keys.len() == 0 { return None; }
      return Some(NodeEntry{ key: node.keys[0], value: node.values[0],
                             payload: node_payload(&node, 0) });
    }
    let first_child = node.children[0];
    if subtree_has_key(tree, first_child) {
      cur = first_child;
    } else {
      if node.keys.len() == 0 { return None; }
      return Some(NodeEntry{ key: node.keys[0], value: node.values[0],
                             payload: node_payload(&node, 0) });
    }
  }
  return None;
}

// Merge children[pos] + separator + children[pos+1] into the left child.
// M3: the left child is shadowed first (the right child is absorbed verbatim
// and stays untouched for pinned views; it becomes live-garbage). Returns the
// fresh index of the merged child so callers can descend into it.
fn merge_children(tree: &mut BTree, parent_idx: Int, pos: Int) -> Int {
  var parent = tree.store.nodes[parent_idx];
  var left_idx = parent.children[pos];
  var shadowed_left = cow_shadow(tree, left_idx);
  if shadowed_left != left_idx {
    parent.children[pos] = shadowed_left;
    left_idx = shadowed_left;
  }
  var right_idx = parent.children[pos + 1];

  var left = tree.store.nodes[left_idx];
  var right = tree.store.nodes[right_idx];

  left.keys.push(parent.keys[pos]);
  left.values.push(parent.values[pos]);
  left.payloads.push(node_payload(&parent, pos));

  var i = 0;
  while i < right.keys.len() {
    left.keys.push(right.keys[i]);
    left.values.push(right.values[i]);
    left.payloads.push(node_payload(&right, i));
    i = i + 1;
  }

  i = 0;
  while i < right.children.len() {
    left.children.push(right.children[i]);
    i = i + 1;
  }

  ns_set(&mut tree.store, left_idx, left);

  i = pos;
  while i < parent.keys.len() - 1 {
    parent.keys[i] = parent.keys[i + 1];
    parent.values[i] = parent.values[i + 1];
    parent.payloads[i] = parent.payloads[i + 1];
    i = i + 1;
  }
  parent.keys.pop();
  parent.values.pop();
  parent.payloads.pop();

  i = pos + 1;
  while i < parent.children.len() - 1 {
    parent.children[i] = parent.children[i + 1];
    i = i + 1;
  }
  parent.children.pop();

  ns_set(&mut tree.store, parent_idx, parent);

  if parent.keys.len() == 0 && parent_idx == tree.root {
    tree.root = left_idx;
  }
  return left_idx;
}

fn fill_child(tree: &mut BTree, parent_idx: Int, child_pos: Int, min_keys: Int) -> Int {
  var parent = tree.store.nodes[parent_idx];

  // A keyless parent is a pass-through node (only possible when min_keys ==
  // 0, i.e. order 3): there is no sibling arrangement to borrow from and no
  // key to merge down; merging would read `children[pos + 1]` past the end.
  // Descending straight through is correct -- the child keeps its own count.
  // M3: the pass-through child is descended into, so it must be writable.
  if parent.keys.len() == 0 {
    var through_idx = parent.children[child_pos];
    var shadowed_through = cow_shadow(tree, through_idx);
    if shadowed_through != through_idx {
      var pp = tree.store.nodes[parent_idx];
      pp.children[child_pos] = shadowed_through;
      ns_set(&mut tree.store, parent_idx, pp);
      through_idx = shadowed_through;
    }
    return through_idx;
  }

  if child_pos > 0 {
    var left_sib_idx = parent.children[child_pos - 1];
    if tree.store.nodes[left_sib_idx].keys.len() > min_keys {
      borrow_from_left(tree, parent_idx, child_pos);
      return tree.store.nodes[parent_idx].children[child_pos];
    }
  }

  if child_pos < parent.children.len() - 1 {
    var right_sib_idx = parent.children[child_pos + 1];
    if tree.store.nodes[right_sib_idx].keys.len() > min_keys {
      borrow_from_right(tree, parent_idx, child_pos);
      return tree.store.nodes[parent_idx].children[child_pos];
    }
  }

  if child_pos > 0 {
    let _ = merge_children(tree, parent_idx, child_pos - 1);
    return tree.store.nodes[parent_idx].children[child_pos - 1];
  }
  let _ = merge_children(tree, parent_idx, child_pos);
  return tree.store.nodes[parent_idx].children[child_pos];
}

fn borrow_from_left(tree: &mut BTree, parent_idx: Int, child_pos: Int) {
  var parent = tree.store.nodes[parent_idx];
  var child_idx = parent.children[child_pos];
  var left_idx = parent.children[child_pos - 1];
  // M3: both participants are re-written below; shadow them and fix the
  // (already writable) parent local, which is ns_set at the end.
  var shadowed_child = cow_shadow(tree, child_idx);
  if shadowed_child != child_idx {
    parent.children[child_pos] = shadowed_child;
    child_idx = shadowed_child;
  }
  var shadowed_left = cow_shadow(tree, left_idx);
  if shadowed_left != left_idx {
    parent.children[child_pos - 1] = shadowed_left;
    left_idx = shadowed_left;
  }
  var child = tree.store.nodes[child_idx];
  var left = tree.store.nodes[left_idx];
  var left_last = left.keys.len() - 1;

  child.keys.push(0);
  child.values.push(0);
  child.payloads.push(Vec[Int].new());

  var i = child.keys.len() - 1;
  while i > 0 {
    child.keys[i] = child.keys[i - 1];
    child.values[i] = child.values[i - 1];
    child.payloads[i] = child.payloads[i - 1];
    i = i - 1;
  }
  child.keys[0] = parent.keys[child_pos - 1];
  child.values[0] = parent.values[child_pos - 1];
  child.payloads[0] = node_payload(&parent, child_pos - 1);

  if left.children.len() > 0 {
    // Internal nodes only: carry the sibling's last child pointer across.
    // (The old code pushed the placeholder even for leaf children, leaving
    // a spurious child index on every leaf borrow.)
    child.children.push(0);
    i = child.children.len() - 1;
    while i > 0 {
      child.children[i] = child.children[i - 1];
      i = i - 1;
    }
    child.children[0] = left.children[left.children.len() - 1];
    left.children.pop();
  }

  parent.keys[child_pos - 1] = left.keys[left_last];
  parent.values[child_pos - 1] = left.values[left_last];
  parent.payloads[child_pos - 1] = node_payload(&left, left_last);
  left.keys.pop();
  left.values.pop();
  left.payloads.pop();

  ns_set(&mut tree.store, parent_idx, parent);
  ns_set(&mut tree.store, child_idx, child);
  ns_set(&mut tree.store, left_idx, left);
}

fn borrow_from_right(tree: &mut BTree, parent_idx: Int, child_pos: Int) {
  var parent = tree.store.nodes[parent_idx];
  var child_idx = parent.children[child_pos];
  var right_idx = parent.children[child_pos + 1];
  // M3: both participants are re-written below; shadow them and fix the
  // (already writable) parent local, which is ns_set at the end.
  var shadowed_child = cow_shadow(tree, child_idx);
  if shadowed_child != child_idx {
    parent.children[child_pos] = shadowed_child;
    child_idx = shadowed_child;
  }
  var shadowed_right = cow_shadow(tree, right_idx);
  if shadowed_right != right_idx {
    parent.children[child_pos + 1] = shadowed_right;
    right_idx = shadowed_right;
  }
  var child = tree.store.nodes[child_idx];
  var right = tree.store.nodes[right_idx];

  child.keys.push(parent.keys[child_pos]);
  child.values.push(parent.values[child_pos]);
  child.payloads.push(node_payload(&parent, child_pos));

  if right.children.len() > 0 {
    child.children.push(right.children[0]);
  }

  parent.keys[child_pos] = right.keys[0];
  parent.values[child_pos] = right.values[0];
  parent.payloads[child_pos] = node_payload(&right, 0);

  var i = 0;
  while i < right.keys.len() - 1 {
    right.keys[i] = right.keys[i + 1];
    right.values[i] = right.values[i + 1];
    right.payloads[i] = right.payloads[i + 1];
    i = i + 1;
  }
  right.keys.pop();
  right.values.pop();
  right.payloads.pop();

  if right.children.len() > 0 {
    i = 0;
    while i < right.children.len() - 1 {
      right.children[i] = right.children[i + 1];
      i = i + 1;
    }
    right.children.pop();
  }

  ns_set(&mut tree.store, parent_idx, parent);
  ns_set(&mut tree.store, child_idx, child);
  ns_set(&mut tree.store, right_idx, right);
}

pub fn btree_range_query(tree: &BTree, low: Int, high: Int) -> Vec[Int]
  requires: low <= high
{
  var results = Vec[Int].new();
  collect_range(tree, tree.root, low, high, results);
  return results;
}

fn collect_range(tree: &BTree, node_idx: Int, low: Int, high: Int, results: &mut Vec[Int]) {
  var node = tree.store.nodes[node_idx];
  if node.is_leaf {
    var i = 0;
    while i < node.keys.len() {
      if node.keys[i] >= low && node.keys[i] <= high {
        results.push(node.values[i]);
      }
      i = i + 1;
    }
    return;
  }

  var i = 0;
  while i < node.keys.len() && node.keys[i] < low {
    i = i + 1;
  }

  if i < node.children.len() {
    collect_range(tree, node.children[i], low, high, results);
  }

  while i < node.keys.len() && node.keys[i] <= high {
    results.push(node.values[i]);
    i = i + 1;
    if i < node.children.len() {
      collect_range(tree, node.children[i], low, high, results);
    }
  }
}

pub fn btree_size(tree: &BTree) -> Int {
  return count_keys(tree, tree.root);
}

fn count_keys(tree: &BTree, node_idx: Int) -> Int {
  var node = tree.store.nodes[node_idx];
  var total = node.keys.len();
  if !node.is_leaf {
    var i = 0;
    while i < node.children.len() {
      total = total + count_keys(tree, node.children[i]);
      i = i + 1;
    }
  }
  return total;
}

pub fn btree_min(tree: &BTree) -> Option[Int] {
  // Subtree min: the leftmost in-order key. Empty pass-through chains (order
  // 3) can end the leftmost path in an empty node while the min key sits at an
  // internal node -- get_successor handles both, and the old leftmost-only
  // descent returned None whenever the terminal leaf was empty.
  match get_successor(tree, tree.root) {
    Some(p) => { return Some(p.value); }
    None => { return None; }
  }
}

pub fn btree_max(tree: &BTree) -> Option[Int] {
  // See btree_min: the rightmost path can end in an empty node (order 3);
  // get_predecessor falls back to the owning internal node's last key.
  match get_predecessor(tree, tree.root) {
    Some(p) => { return Some(p.value); }
    None => { return None; }
  }
}

pub fn btree_to_vec(tree: &BTree) -> Vec[Int] {
  var results = Vec[Int].new();
  traverse_inorder(tree, tree.root, results);
  return results;
}

fn traverse_inorder(tree: &BTree, node_idx: Int, results: &mut Vec[Int]) {
  var node = tree.store.nodes[node_idx];
  if node.is_leaf {
    var i = 0;
    while i < node.keys.len() {
      results.push(node.values[i]);
      i = i + 1;
    }
    return;
  }
  var i = 0;
  while i < node.keys.len() {
    if i < node.children.len() {
      traverse_inorder(tree, node.children[i], results);
    }
    results.push(node.values[i]);
    i = i + 1;
  }
  if i < node.children.len() {
    traverse_inorder(tree, node.children[i], results);
  }
}

// ============================================================================
// WAL RECORD (from xiom.db.wal.wal_record)
// ============================================================================

pub enum WALOpType {
  InsertOp,
  UpdateOp,
  DeleteOp,
}

pub type WALEntry = {
  op: WALOpType;
  key: Int;
  value: Int;
  timestamp: Int;
}

pub fn wal_entry_new(op: WALOpType, key: Int, value: Int, timestamp: Int) -> WALEntry
  requires: timestamp >= 0
{
  return WALEntry{ op: op, key: key, value: value, timestamp: timestamp };
}

// ============================================================================
// WAL (from xiom.db.wal.wal)
// ============================================================================

pub type WAL = {
  entries: Vec[WALEntry];
}

pub fn wal_new() -> WAL {
  var entries = Vec[WALEntry].new();
  return WAL{ entries: entries };
}

pub fn wal_append(wal: &mut WAL, entry: WALEntry) {
  wal.entries.push(entry);
}

pub fn wal_replay(wal: &WAL, target: &mut BTree) -> Bool {
  var i = 0;
  var success = true;
  while i < wal.entries.len() {
    var entry = wal.entries[i];
    match entry.op {
      InsertOp => {
        var result = btree_insert(target, entry.key, entry.value);
        if !result { success = false; }
      }
      UpdateOp => {
        var found = btree_search(target, entry.key);
        match found {
          Some(_) => {
            var del = btree_delete(target, entry.key);
            if del {
              var ins = btree_insert(target, entry.key, entry.value);
              if !ins { success = false; }
            } else {
              success = false;
            }
          }
          None => { success = false; }
        }
      }
      DeleteOp => {
        var result = btree_delete(target, entry.key);
        if !result { success = false; }
      }
    }
    i = i + 1;
  }
  return success;
}

pub fn wal_clear(wal: &mut WAL) {
  var empty = Vec[WALEntry].new();
  wal.entries = empty;
}

pub fn wal_truncate(wal: &mut WAL, before_timestamp: Int)
  requires: before_timestamp >= 0
{
  var kept = Vec[WALEntry].new();
  var i = 0;
  while i < wal.entries.len() {
    if wal.entries[i].timestamp >= before_timestamp {
      kept.push(wal.entries[i]);
    }
    i = i + 1;
  }
  wal.entries = kept;
}

pub fn wal_len(wal: &WAL) -> Int {
  return wal.entries.len();
}

pub fn wal_is_empty(wal: &WAL) -> Bool {
  return wal.entries.len() == 0;
}

pub fn wal_entry_count(wal: &WAL, op_filter: WALOpType) -> Int {
  var count = 0;
  var i = 0;
  while i < wal.entries.len() {
    if wal.entries[i].op == op_filter {
      count = count + 1;
    }
    i = i + 1;
  }
  return count;
}

// ============================================================================
// QUERY (from xiom.db.query.query)
// ============================================================================

pub enum QueryOp {
  Eq,
  Neq,
  Lt,
  Lte,
  Gt,
  Gte,
}

pub type QueryCondition = {
  op: QueryOp;
  value: Int;
}

pub type Query = {
  conditions: Vec[QueryCondition];
  limit: Int;
  offset: Int;
  // Optional additive key bounds (M4.1): when has_bounds, the scan is
  // restricted to keys in [low, high] BEFORE value conditions/offset/limit.
  // Conditions still filter VALUES -- bounds are the key-range extension.
  has_bounds: Bool;
  low: Int;
  high: Int;
  // Result order (M4.2): 0 = key ascending (default; the scan order),
  // 1 = value ascending, 2 = value descending. Ties keep key order
  // (stable). offset/limit always apply AFTER ordering.
  order: Int;
}

pub fn query_new() -> Query {
  var conditions = Vec[QueryCondition].new();
  return Query{
    conditions: conditions, limit: 0, offset: 0,
    has_bounds: false, low: 0, high: 0,
    order: 0,
  };
}

// Restrict the scan to keys in [low, high] (inclusive). Additive API: the
// value-condition semantics are unchanged; this only narrows the key range
// the planner can push down (M4.1 semantics decision, docs/query-pipeline.md).
pub fn query_key_range(q: &mut Query, low: Int, high: Int)
  requires: low <= high
{
  q.has_bounds = true;
  q.low = low;
  q.high = high;
}

pub fn query_has_bounds(q: &Query) -> Bool {
  return q.has_bounds;
}

pub fn query_where(q: &mut Query, op: QueryOp, value: Int) {
  var cond = QueryCondition{ op: op, value: value };
  q.conditions.push(cond);
}

pub fn query_limit(q: &mut Query, limit: Int)
  requires: limit > 0
{
  q.limit = limit;
}

pub fn query_offset(q: &mut Query, offset: Int)
  requires: offset >= 0
{
  q.offset = offset;
}

pub fn query_execute(q: &Query, tree: &BTree) -> Vec[Int] {
  var all_values = btree_to_vec(tree);
  return apply_filter_values(&all_values, q);
}

// Value conditions -> ordering -> offset -> limit over an already-scanned
// value slice. Shared by the full scan and the key-range scan so both paths
// have identical semantics (M4.2: ordering happens before offset/limit).
fn apply_filter_values(values: &Vec[Int], q: &Query) -> Vec[Int] {
  var results = Vec[Int].new();
  var i = 0;
  while i < values.len() {
    if matches_all_conditions(values[i], q.conditions) {
      results.push(values[i]);
    }
    i = i + 1;
  }

  if q.order == 1 || q.order == 2 {
    // Stable value sort; the scan order (key ascending) breaks ties, exactly
    // like the index executor's (value, pk) order.
    var pks = Vec[Int].new();
    var j = 0;
    while j < results.len() {
      pks.push(j);
      j = j + 1;
    }
    secidx_sort_pairs(&mut results, &mut pks, q.order == 2);
  }

  var out = Vec[Int].new();
  var start = q.offset;
  var end = results.len();
  if q.limit > 0 && start + q.limit < end {
    end = start + q.limit;
  }
  var k = start;
  while k < end {
    out.push(results[k]);
    k = k + 1;
  }
  return out;
}

fn matches_all_conditions(value: Int, conditions: &Vec[QueryCondition]) -> Bool {
  var i = 0;
  while i < conditions.len() {
    if !test_condition(value, conditions[i].op, conditions[i].value) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn test_condition(value: Int, op: QueryOp, target: Int) -> Bool {
  match op {
    Eq => value == target,
    Neq => value != target,
    Lt => value < target,
    Lte => value <= target,
    Gt => value > target,
    Gte => value >= target,
  }
}

pub fn query_condition_count(q: &Query) -> Int {
  return q.conditions.len();
}

pub fn query_has_limit(q: &Query) -> Bool {
  return q.limit > 0;
}

pub fn query_has_offset(q: &Query) -> Bool {
  return q.offset > 0;
}

// ============================================================================
// TYPED QUERIES (M5-S4): predicates over decoded row columns
// ============================================================================

// One condition: `value_at(row, column) OP literal`. `column` indexes the
// decoded row's values; column -1 addresses the row id (pk). Comparisons
// use the codec's total order (tuple2_compare): Null < numeric (Int/Float,
// numeric) < Text (bytewise) < Blob (bytewise). No SQL three-valued logic:
// every condition is true or false against that order.
pub type TypedCond = {
  column: Int;
  op: QueryOp;
  value: TValue;
}

pub type TypedQuery = {
  conditions: Vec[TypedCond];
  limit: Int;
  offset: Int;
}

pub fn typed_query_new() -> TypedQuery {
  var conditions = Vec[TypedCond].new();
  return TypedQuery{ conditions: conditions, limit: 0, offset: 0 };
}

pub fn typed_query_where(q: &mut TypedQuery, column: Int, op: QueryOp, value: TValue) {
  var cond = TypedCond{ column: column, op: op, value: value };
  q.conditions.push(cond);
}

pub fn typed_query_limit(q: &mut TypedQuery, limit: Int)
  requires: limit > 0
{
  q.limit = limit;
}

pub fn typed_query_offset(q: &mut TypedQuery, offset: Int)
  requires: offset >= 0
{
  q.offset = offset;
}

fn typed_op_matches(cmp: Int, op: QueryOp) -> Bool {
  match op {
    Eq => cmp == 0,
    Neq => cmp != 0,
    Lt => cmp < 0,
    Lte => cmp <= 0,
    Gt => cmp > 0,
    Gte => cmp >= 0,
  }
}

fn typed_row_matches(row: &TypedRow, conditions: &Vec[TypedCond]) -> Bool {
  var i = 0;
  while i < conditions.len() {
    let c = conditions[i];
    var v = TValue.VNull;
    if c.column == -1 {
      v = TValue.VInt(row.id);
    } else {
      if c.column < 0 { return false; }
      if c.column >= row.values.len() { return false; }
      v = row.values[c.column];
    }
    if !typed_op_matches(tuple2_compare(v, c.value), c.op) { return false; }
    i = i + 1;
  }
  return true;
}

// In-order walk collecting (key, payload) pairs of payload-bearing entries.
fn collect_typed_inorder(tree: &BTree, node_idx: Int,
                         keys: &mut Vec[Int], pays: &mut Vec[Vec[Int]]) {
  var node = tree.store.nodes[node_idx];
  if node.is_leaf {
    var i = 0;
    while i < node.keys.len() {
      let p = node_payload(&node, i);
      if p.len() > 0 {
        keys.push(node.keys[i]);
        pays.push(p);
      }
      i = i + 1;
    }
    return;
  }
  var i = 0;
  while i < node.keys.len() {
    if i < node.children.len() {
      collect_typed_inorder(tree, node.children[i], keys, pays);
    }
    let p = node_payload(&node, i);
    if p.len() > 0 {
      keys.push(node.keys[i]);
      pays.push(p);
    }
    i = i + 1;
  }
  if i < node.children.len() {
    collect_typed_inorder(tree, node.children[i], keys, pays);
  }
}

// Matching primary keys in key order (conditions ANDed; offset/limit apply
// to the matches). Plain int rows and undecodable payloads never match:
// typed predicates apply to typed rows.
pub fn db_file_query_typed(db: &DBFile, q: &TypedQuery) -> Vec[Int] {
  var keys = Vec[Int].new();
  var pays = Vec[Vec[Int]].new();
  collect_typed_inorder(&db.tree, db.tree.root, &mut keys, &mut pays);

  var hits = Vec[Int].new();
  var i = 0;
  while i < keys.len() {
    let p = pays[i];
    match tuple2_decode_row(&p) {
      Err(_) => {}
      Ok(row) => {
        let r: TypedRow = row;
        if typed_row_matches(&r, q.conditions) { hits.push(keys[i]); }
      }
    }
    i = i + 1;
  }

  var out = Vec[Int].new();
  var start = q.offset;
  var end = hits.len();
  if q.limit > 0 && start + q.limit < end {
    end = start + q.limit;
  }
  var k = start;
  while k < end {
    out.push(hits[k]);
    k = k + 1;
  }
  return out;
}

pub fn query_reset(q: &mut Query) {
  var empty = Vec[QueryCondition].new();
  q.conditions = empty;
  q.limit = 0;
  q.offset = 0;
  q.has_bounds = false;
  q.low = 0;
  q.high = 0;
  q.order = 0;
}

// Result ordering (M4.2): 0 = key ascending (default), 1 = value ascending,
// 2 = value descending. Ties keep key order; offset/limit apply after.
pub fn query_order(q: &mut Query, order: Int)
  requires: order == 0 || order == 1 || order == 2
{
  q.order = order;
}

pub fn query_order_kind(q: &Query) -> Int {
  return q.order;
}

// ============================================================================
// QUERY PLANNER (from xiom.db.query.planner)
// ============================================================================

pub enum PlanKind {
  FullScan,
  IndexRange,
  PointLookup,
  IndexValue,
}

pub type QueryPlan = {
  kind: PlanKind;
  low: Int;
  high: Int;
  has_bounds: Bool;
  estimated_rows: Int;
}

pub fn query_plan_full_scan() -> QueryPlan {
  return QueryPlan{
    kind: PlanKind.FullScan,
    low: 0, high: 0, has_bounds: false,
    estimated_rows: 0,
  };
}

// Bounds-aware planning (M4.1): key bounds choose an index plan -- a point
// lookup when low == high, a key-range scan otherwise -- and the estimate is
// the clamped range width; without bounds it is a full scan estimated at the
// tree size. The executor applies the value conditions after the key scan.
pub fn plan_query(q: &Query, tree: &BTree) -> QueryPlan {
  return plan_query_with_index(q, tree, false);
}

fn min_i64() -> Int {
  return -9223372036854775807 - 1;
}

fn max_i64() -> Int {
  return 9223372036854775807;
}

// Index-aware planning (M4.2): with a secondary index available and no key
// bounds, the first usable VALUE condition (anything but Neq) becomes an
// IndexValue plan over [low, high] (saturated; an empty range still yields
// an empty result). `low`/`high` mean value bounds under IndexValue and key
// bounds under IndexRange/PointLookup. Key bounds keep precedence.
pub fn plan_query_with_index(q: &Query, tree: &BTree, has_index: Bool) -> QueryPlan {
  var plan = query_plan_full_scan();
  let size = btree_size(tree);
  plan.estimated_rows = size;
  if q.has_bounds {
    plan.low = q.low;
    plan.high = q.high;
    plan.has_bounds = true;
    var width = q.high - q.low + 1;
    if width < 0 { width = 0; } // extreme-bound overflow guard
    var est = width;
    if est > size { est = size; }
    plan.estimated_rows = est;
    if q.low == q.high {
      plan.kind = PlanKind.PointLookup;
    } else {
      plan.kind = PlanKind.IndexRange;
    }
    return plan;
  }

  if has_index {
    var i = 0;
    while i < q.conditions.len() {
      let c = q.conditions[i];
      var lo = 0;
      var hi = 0;
      var usable = true;
      match c.op {
        Eq => {
          lo = c.value;
          hi = c.value;
        }
        Lt => {
          if c.value == min_i64() { usable = false; }
          lo = min_i64();
          hi = c.value - 1;
        }
        Lte => {
          lo = min_i64();
          hi = c.value;
        }
        Gt => {
          if c.value == max_i64() { usable = false; }
          lo = c.value + 1;
          hi = max_i64();
        }
        Gte => {
          lo = c.value;
          hi = max_i64();
        }
        Neq => { usable = false; }
      }
      if usable {
        plan.kind = PlanKind.IndexValue;
        plan.low = lo;
        plan.high = hi;
        plan.has_bounds = false;
        plan.estimated_rows = size;
        if c.op == QueryOp.Eq {
          plan.estimated_rows = 1;
          if size < 1 { plan.estimated_rows = 0; }
        }
        return plan;
      }
      i = i + 1;
    }
  }
  return plan;
}

// IndexValue executor: candidates from the (value, pk) entries in
// [plan.low, plan.high], re-filtered by ALL conditions (the plan only used
// the first usable one to bound the probe), then ordered and sliced exactly
// like the scan path.
fn execute_index_value(idx: &SecondaryIndex, plan: &QueryPlan, q: &Query) -> Vec[Int] {
  var vals = Vec[Int].new();
  var pks = Vec[Int].new();
  if plan.low <= plan.high {
    var pos = secidx_lower_bound(idx, plan.low);
    while pos < idx.vals.len() && idx.vals[pos] <= plan.high {
      if matches_all_conditions(idx.vals[pos], q.conditions) {
        vals.push(idx.vals[pos]);
        pks.push(idx.pks[pos]);
      }
      pos = pos + 1;
    }
  }

  if q.order == 0 {
    secidx_sort_pairs_by_pk(&mut vals, &mut pks);
  } else if q.order == 2 {
    secidx_sort_pairs(&mut vals, &mut pks, true);
  }
  // order 1: (value asc, pk asc) is already the index order.

  var out = Vec[Int].new();
  var start = q.offset;
  var end = vals.len();
  if q.limit > 0 && start + q.limit < end {
    end = start + q.limit;
  }
  var k = start;
  while k < end {
    out.push(vals[k]);
    k = k + 1;
  }
  return out;
}

pub fn execute_plan(plan: &QueryPlan, q: &Query, tree: &BTree) -> Vec[Int] {
  match plan.kind {
    FullScan => query_execute(q, tree)
    IndexRange => {
      let values = btree_range_query(tree, plan.low, plan.high);
      apply_filter_values(&values, q)
    }
    PointLookup => {
      let values = btree_range_query(tree, plan.low, plan.low);
      apply_filter_values(&values, q)
    }
    // The file layer routes IndexValue through execute_index_value (it owns
    // the index); when called without one, degrade to the full scan -- the
    // result set is identical, only the probe is missing.
    IndexValue => query_execute(q, tree)
  }
}

// ============================================================================
// ENGINE (from xiom.db.engine)
// ============================================================================

pub type Engine = {
  tree: BTree;
  wal: WAL;
  timestamp_counter: Int;
}

pub fn engine_new(order: Int) -> Engine
  requires: order >= 3
{
  var tree = btree_new(order);
  var wal = wal_new();
  return Engine{ tree: tree, wal: wal, timestamp_counter: 0 };
}

fn next_timestamp(eng: &mut Engine) -> Int {
  eng.timestamp_counter = eng.timestamp_counter + 1;
  return eng.timestamp_counter;
}

pub fn engine_insert(eng: &mut Engine, key: Int, value: Int) -> Bool {
  var ts = next_timestamp(eng);
  var entry = WALEntry{
    op: WALOpType.InsertOp, key: key, value: value, timestamp: ts,
  };
  wal_append(&mut eng.wal, entry);

  return btree_insert(&mut eng.tree, key, value);
}

pub fn engine_get(eng: &Engine, key: Int) -> Option[Int] {
  return btree_search(&eng.tree, key);
}

pub fn engine_delete(eng: &mut Engine, key: Int) -> Bool {
  var found = btree_search(&eng.tree, key);
  match found {
    None => return false,
    Some(v) => {}
  }

  var ts = next_timestamp(eng);
  var entry = WALEntry{
    op: WALOpType.DeleteOp, key: key, value: 0, timestamp: ts,
  };
  wal_append(&mut eng.wal, entry);

  return btree_delete(&mut eng.tree, key);
}

pub fn engine_update(eng: &mut Engine, key: Int, value: Int) -> Bool {
  var found = btree_search(&eng.tree, key);
  match found {
    None => return false,
    Some(_) => {}
  }

  var ts = next_timestamp(eng);
  var entry = WALEntry{
    op: WALOpType.UpdateOp, key: key, value: value, timestamp: ts,
  };
  wal_append(&mut eng.wal, entry);

  var del = btree_delete(&mut eng.tree, key);
  if !del { return false; }
  return btree_insert(&mut eng.tree, key, value);
}

pub fn engine_query(eng: &Engine, query: &Query) -> Vec[Int] {
  return query_execute(query, &eng.tree);
}

pub fn engine_recover(eng: &mut Engine) -> Bool {
  var fresh = btree_new(eng.tree.order);
  eng.tree = fresh;
  eng.timestamp_counter = 0;
  return wal_replay(&eng.wal, &mut eng.tree);
}

pub fn engine_range_query(eng: &Engine, low: Int, high: Int) -> Vec[Int]
  requires: low <= high
{
  return btree_range_query(&eng.tree, low, high);
}

pub fn engine_size(eng: &Engine) -> Int {
  return btree_size(&eng.tree);
}

pub fn engine_wal_size(eng: &Engine) -> Int {
  return wal_len(&eng.wal);
}

pub fn engine_flush_wal(eng: &mut Engine) {
  wal_clear(&mut eng.wal);
}

pub fn engine_truncate_wal(eng: &mut Engine, before_timestamp: Int)
  requires: before_timestamp >= 0
{
  wal_truncate(&mut eng.wal, before_timestamp);
}

// ============================================================================
// DATABASE API (from xiom.db.api.database)
// ============================================================================

pub type DatabaseConfig = {
  page_size: Int;
  buffer_pool_capacity: Int;
  wal_enabled: Bool;
  btree_order: Int;
}

pub type Database = {
  engine: Engine;
  open: Bool;
}

pub fn db_open(order: Int) -> Database
  requires: order >= 3
{
  var engine = engine_new(order);
  return Database{ engine: engine, open: true };
}

pub fn db_open_with(config: &DatabaseConfig) -> Database
  requires: config.btree_order >= 3
{
  var engine = engine_new(config.btree_order);
  return Database{ engine: engine, open: true };
}

pub fn db_insert(db: &mut Database, key: Int, value: Int) -> Bool {
  if !db.open { return false; }
  return engine_insert(&mut db.engine, key, value);
}

pub fn db_get(db: &Database, key: Int) -> Option[Int] {
  if !db.open { return None; }
  return engine_get(&db.engine, key);
}

pub fn db_update(db: &mut Database, key: Int, value: Int) -> Bool {
  if !db.open { return false; }
  return engine_update(&mut db.engine, key, value);
}

pub fn db_delete(db: &mut Database, key: Int) -> Bool {
  if !db.open { return false; }
  return engine_delete(&mut db.engine, key);
}

pub fn db_query(db: &Database, query: &Query) -> Vec[Int] {
  if !db.open { return Vec[Int].new(); }
  return engine_query(&db.engine, query);
}

pub fn db_range(db: &Database, low: Int, high: Int) -> Vec[Int]
  requires: low <= high
{
  if !db.open { return Vec[Int].new(); }
  return engine_range_query(&db.engine, low, high);
}

pub fn db_size(db: &Database) -> Int {
  if !db.open { return 0; }
  return engine_size(&db.engine);
}

pub fn db_recover(db: &mut Database) -> Bool {
  if !db.open { return false; }
  return engine_recover(&mut db.engine);
}

pub fn db_close(db: &mut Database) {
  if !db.open { return; }
  engine_flush_wal(&mut db.engine);
  db.open = false;
}

// ===========================================================================
// File-backed database facade (Phase 1/B4): WAL-before-ack on a real segment
// ===========================================================================

// A database whose log is the durable WAL segment (src/wal_file.xi). Every
// mutating call appends the record FIRST and only then applies it to the
// in-memory B-tree; `db_file_open` rebuilds the tree by replaying the segment
// (torn tail skipped). Data pages still rebuild from the log on open; the
// durable page file (storage/page_file.xi) takes over persistence next.
//
// Durability honesty (M2.1 second half, M1.2 S4 2026-10-13): `db_file_flush`
// is the wal_file flush seam and is now a REAL fsync (sync_io.sync_fd). With
// durability mode 1 (default) + two_phase, commits and checkpoint publishes
// are power-loss honest up to the synced seams. Until the next compiler pin
// re-vendors stdlib/runtime, run with XIOM_RUNTIME_DIR=<stdlib>/runtime
// (scripts/dev-env.* sets it).

// Transaction record codes (wal_file WALOpKind BeginTxn/CommitTxn/AbortTxn);
// Int codes keep replay dispatch aligned with `db_file_apply_record`.
const TXN_BEGIN_CODE: Int = 8;
const TXN_COMMIT_CODE: Int = 9;
const TXN_ABORT_CODE: Int = 10;

// One buffered transaction operation: code 2 = upsert (delete+insert, the
// same code the WAL uses for writes), code 3 = delete. `payload` carries the
// tagged WAL payload verbatim (empty for plain int ops); M5.3 buffer them so
// a typed record inside a txn window replays with its row bytes.
type TxOp = {
  code: Int;
  key: Int;
  value: Int;
  payload: Vec[Int];
}

pub type DBFile = {
  path: Str;
  order: Int;
  tree: BTree;
  wal: WALFile;
  records_since_ckpt: Int;
  txn_active: Bool;
  txn_ops: Vec[TxOp];
  wal_bytes: Int;
  page_format: Int;
  // Secondary indexes over VALUES (M4.2); handle-scoped, rebuilt on open via
  // `db_file_create_index`. Maintained by put/delete/txn-commit.
  indexes: Vec[SecondaryIndex];
  // Durability (M2.1): 0 = normal (ack without a flush; sync at
  // checkpoint only), 1 = immediate (REAL fsync at every commit ack since
  // M1.2 S4; stdlib wave 115). `two_phase` (immediate only) flushes the WAL
  // before a checkpoint publishes its snapshot. A failed flush latches
  // `failed`: writers refuse until the handle is reopened.
  durability: Int;
  two_phase: Bool;
  failed: Bool;
  // Last committed snapshot generation (0 = none), for `DBSnapshot`.
  snap_generation: Int;
  // M3 savepoint (single level): active marker + buffer length at capture.
  sp_active: Bool;
  sp_marker: Int;
  // Held append handle for the transaction window (BENCH-1 perf slice
  // 2026-10-16): one open per TRANSACTION instead of one per record; -1 when
  // no transaction holds it. Owned here, closed by commit/abort; a leaked fd
  // at process exit is harmless (segment appends are appended atomically).
  wal_fd: Int;
}

// Apply one replayed record. Maps by op code so cross-module enum patterns
// stay out of this module (1 Insert, 2 Update, 3 Delete). Tagged payloads
// with subtype 1 are typed rows (tuple codec v2 bytes); any other non-empty
// subtype is an unknown future format and the record is SKIPPED (fail closed
// -- applying the int value alone would resurrect wrong data).
fn db_file_apply_record(tree: &mut BTree, rec: WALRecord) {
  let code = wal_op_code(rec.op);
  if code == 2 { let _ = btree_delete(tree, rec.key); }
  if code == 3 {
    let _ = btree_delete(tree, rec.key);
    return;
  }
  if code == 1 || code == 2 {
    if rec.payload.len() > 0 {
      if rec.payload[0] != 1 { return; }
      var row = Vec[Int].new();
      var i = 1;
      while i < rec.payload.len() {
        if rec.payload[i] < 0 { return; }   // byte convention: fail closed
        if rec.payload[i] > 255 { return; }
        row.push(rec.payload[i]);
        i = i + 1;
      }
      let _ = btree_insert_payload(tree, rec.key, rec.value, row);
      return;
    }
    let _ = btree_insert(tree, rec.key, rec.value);
  }
}

// Apply one buffered transaction op (see TxOp).
fn db_file_apply_txop(tree: &mut BTree, op: TxOp) {
  if op.code == 3 {
    let _ = btree_delete(tree, op.key);
    return;
  }
  let _ = btree_delete(tree, op.key);
  if op.payload.len() > 0 {
    if op.payload[0] != 1 { return; }
    var row = Vec[Int].new();
    var i = 1;
    while i < op.payload.len() {
      if op.payload[i] < 0 { return; }
      if op.payload[i] > 255 { return; }
      row.push(op.payload[i]);
      i = i + 1;
    }
    let _ = btree_insert_payload(tree, op.key, op.value, row);
    return;
  }
  let _ = btree_insert(tree, op.key, op.value);
}

// Open (or create) a file-backed database. Recovery: load the checkpoint
// snapshot when present, then replay ONLY records newer than its
// checkpoint_lsn; without a snapshot, replay the whole segment (Phase 1/B
// behavior). The torn tail is healed once by `wal_file_open`. **The v2
// byte-block container is the DEFAULT since M1.2 S4** (2026-10-13); v1
// (text page log) stays fully supported for reads (auto-detected on the
// on-disk format) and for writes via `db_file_open_cfg(path, order, 1)`.
// The handle's format decides how the next checkpoint writes, migrating a
// v1 file to v2 on its first write (migration-on-write).
pub fn db_file_open(path: Str, order: Int) -> DBFile {
  return db_file_open_cfg(path, order, 2);
}

pub fn db_file_open_cfg(path: Str, order: Int, page_format: Int) -> DBFile {
  var tree = btree_new(order);
  var snap_lsn = 0;
  var snap_gen = 0;
  let snap_path = path + ".snap";
  // Snapshot reads auto-detect the on-disk format: 'O' (0x4F) first byte =
  // v2 block store; anything else = v1 text page log (healed on open).
  let loaded = snap_load_auto(snap_path);
  match loaded {
    None => {}
    Some(s) => {
      let snap: Snapshot = s;
      tree = snap.tree;
      snap_lsn = snap.checkpoint_lsn;
      snap_gen = snap.generation;
    }
  }

  // Transaction-aware replay: writes between BeginTxn and CommitTxn are
  // buffered and applied only at the commit record; an unterminated trailing
  // transaction (crash before commit) is discarded -- committed/uncommitted
  // classification without a physical undo pass.
  let records = wal_file_replay(path);
  var pending = Vec[TxOp].new();
  var in_txn = false;
  var i = 0;
  while i < records.len() {
    let rec = records[i];
    if rec.lsn > snap_lsn {
      let code = wal_op_code(rec.op);
      if code == TXN_BEGIN_CODE {
        in_txn = true;
        pending = Vec[TxOp].new();
      } else if code == TXN_COMMIT_CODE {
        if in_txn {
          var p = 0;
          while p < pending.len() {
            let op = pending[p];
            db_file_apply_txop(&mut tree, op);
            p = p + 1;
          }
        }
        in_txn = false;
        pending = Vec[TxOp].new();
      } else if code == TXN_ABORT_CODE {
        in_txn = false;
        pending = Vec[TxOp].new();
      } else if code == 1 || code == 2 || code == 3 {
        if in_txn {
          pending.push(TxOp{ code: code, key: rec.key, value: rec.value,
                             payload: rec.payload });
        } else {
          db_file_apply_record(&mut tree, rec);
        }
      }
    }
    i = i + 1;
  }
  var wal = wal_file_open(path);
  if in_txn {
    // A dangling transaction window (crash before Commit/Abort) is finalized
    // with an explicit Abort record: without it, writes made after this open
    // would be replayed inside the stale window and silently discarded.
    let _ = wal_file_append(&mut wal, WALOpKind.AbortTxn, 0, 0);
  }
  var ops = Vec[TxOp].new();
  let wal_bytes = db_wal_size(path);
  var indexes = Vec[SecondaryIndex].new();
  return DBFile{ path: path, order: tree.order, tree: tree, wal: wal,
                 records_since_ckpt: 0, txn_active: false, txn_ops: ops,
                 wal_bytes: wal_bytes, page_format: page_format,
                 indexes: indexes, durability: 1, two_phase: false,
                 failed: false, snap_generation: snap_gen, sp_active: false,
                 sp_marker: 0, wal_fd: -1 };
}

// ---------------------------------------------------------------------------
// Input validation (H2): a path is a filename, not data -- reject empty,
// overlong, and line-terminator-carrying paths before creating a handle (the
// codecs are line-oriented, so CR/LF would corrupt diagnostics and tooling).
// ---------------------------------------------------------------------------

pub fn db_path_valid(path: Str) -> Bool {
  if str_len(path) == 0 { return false; }
  if str_len(path) > 4096 { return false; }
  if str_contains(path, "\n") { return false; }
  if str_contains(path, "\r") { return false; }
  return true;
}

// Validated open: Err(ConstraintViolation) for an invalid path or a btree
// order below 3; otherwise Ok with a handle from `db_file_open` (which is kept
// unchanged for existing callers).
pub fn db_file_open_checked(path: Str, order: Int) -> Result[DBFile, DbError] {
  if !db_path_valid(path) {
    return Err(DbError.ConstraintViolation);
  }
  if !valid_btree_order(order) {
    return Err(DbError.ConstraintViolation);
  }
  return Ok(db_file_open(path, order));
}

// Validated open with an explicit snapshot container format (1 = v1 text
// page log, 2 = v2 byte blocks). Reads always auto-detect the on-disk
// format; page_format only steers the next checkpoint's write.
pub fn db_file_open_checked_cfg(path: Str, order: Int, page_format: Int) -> Result[DBFile, DbError] {
  if !db_path_valid(path) {
    return Err(DbError.ConstraintViolation);
  }
  if !valid_btree_order(order) {
    return Err(DbError.ConstraintViolation);
  }
  if page_format != 1 && page_format != 2 {
    return Err(DbError.ConstraintViolation);
  }
  return Ok(db_file_open_cfg(path, order, page_format));
}

// Stale-handle guard (multi-handle safety): every handle remembers the WAL
// segment size at its last own write. Another handle appending changes the
// size, so this handle's next write is refused instead of interleaving LSNs
// and corrupting the segment. Optimistic and stateless -- no lock files, so a
// crash cannot leave a stale lock. See docs/ISOLATION.md for the single-writer
// model this enforces.
fn db_wal_size(path: Str) -> Int {
  let r = io.file_size(path);
  match r {
    None => { return 0; }
    Some(n) => {
      let size: Int = n;
      return size;
    }
  }
}

fn db_file_guard(db: &DBFile) -> Bool {
  return db_wal_size(db.path) == db.wal_bytes;
}

// Upsert with WAL-before-ack: append (Insert for new keys, Update for
// existing), then apply. Returns false when the log write fails.
pub fn db_file_put(db: &mut DBFile, key: Int, value: Int) -> Bool {
  // Auto-commit writes are rejected while a transaction is open.
  if db.txn_active { return false; }
  // Stale handle: another writer appended since our last write.
  if !db_file_guard(db) { return false; }
  // Latched after a failed flush/commit: refuse until reopen.
  if db.failed { return false; }
  // Qualified: this module imports wal_file but a program may also contain
  // txn's same-named WALOp variants; m225 scopes UNQUALIFIED resolution to the
  // declaring module, not to the importing consumer (see COMPILER-FINDINGS).
  var op = WALOpKind.Insert;
  var is_update = false;
  let existing = btree_search(&db.tree, key);
  match existing {
    None => {}
    Some(_) => {
      op = WALOpKind.Update;
      is_update = true;
    }
  }
  // Combined durable append (BENCH-1 perf slice 2026-10-16): ONE held
  // handle does write + (immediate mode) the gated sync, halving the
  // Windows open/close pairs per record. -1 write failure; -2 written but
  // sync failed -- the state updates below still run so the in-memory view
  // matches the old append-then-commit_sync ordering, and the handle latches
  // at the end.
  let lsn = wal_file_append_sync(&mut db.wal, op, key, value, db.durability == 1);
  if lsn == -1 { return false; }
  let sync_failed = lsn == -2;
  db.wal_bytes = db_wal_size(db.path);
  db.records_since_ckpt = db.records_since_ckpt + 1;
  if is_update { let _ = btree_delete(&mut db.tree, key); }
  let inserted = btree_insert(&mut db.tree, key, value);
  if inserted { db_file_note_value_change(db, key, existing, value, true); }
  if !inserted { return false; }
  if sync_failed { db.failed = true; return false; }
  return true;
}

// Max typed-row payload bytes for a btree order: the largest node page
// (order-1 entries, order children; 28-byte node header + 16 bytes per
// key/value + 8 bytes payload framing + the payload itself) must fit the
// smaller snapshot container budget (v2 block payload capacity). A
// `db_file_put_typed` above this is refused up front -- a checkpoint could
// otherwise fail only at snapshot time.
pub fn db_file_typed_payload_max(order: Int) -> Int {
  if order < 3 { return 0; }
  let keys = order - 1;
  let overhead = SNAP_NODE_HEADER_BYTES + 24 * keys + 8 * order;
  let room = block.block_payload_capacity() - overhead;
  if room <= 0 { return 0; }
  let per = room / keys;
  if per <= 0 { return 0; }
  return per;
}

// Typed-row upsert (M5.3): the payload is opaque row bytes (tuple codec v2
// rows or any caller encoding); the WAL record carries subtype 1 + the row
// bytes and its `value` mirrors the key (the pk). Same guards as
// `db_file_put`; typed writes are non-transactional in S3 (txn paths refuse
// while a transaction is active). Indexes hold int values only: any stale
// entry for the key is dropped, none is added (typed-column indexes = S4).
pub fn db_file_put_typed(db: &mut DBFile, key: Int, payload: Vec[Int]) -> Bool {
  if db.txn_active { return false; }
  if !db_file_guard(db) { return false; }
  if db.failed { return false; }
  if payload.len() > db_file_typed_payload_max(db.order) { return false; }
  // Payload bytes are 0..255 (the storage byte convention; the snapshot
  // codecs mask to a byte). Refuse anything else instead of losing bits.
  var v = 0;
  while v < payload.len() {
    if payload[v] < 0 { return false; }
    if payload[v] > 255 { return false; }
    v = v + 1;
  }
  var op = WALOpKind.Insert;
  var is_update = false;
  let existing = btree_search(&db.tree, key);
  match existing {
    None => {}
    Some(_) => {
      op = WALOpKind.Update;
      is_update = true;
    }
  }
  var tagged = Vec[Int].new();
  tagged.push(1); // subtype: typed row (tuple v2 bytes)
  var i = 0;
  while i < payload.len() {
    tagged.push(payload[i]);
    i = i + 1;
  }
  let lsn = wal_file_append_tagged_sync(&mut db.wal, op, key, key, tagged, 0, db.durability == 1);
  if lsn == -1 { return false; }
  let sync_failed = lsn == -2;
  db.wal_bytes = db_wal_size(db.path);
  db.records_since_ckpt = db.records_since_ckpt + 1;
  if is_update { let _ = btree_delete(&mut db.tree, key); }
  let inserted = btree_insert_payload(&mut db.tree, key, key, payload);
  if inserted { db_file_note_value_change(db, key, existing, 0, false); }
  if !inserted { return false; }
  if sync_failed { db.failed = true; return false; }
  return true;
}

pub fn db_file_delete(db: &mut DBFile, key: Int) -> Bool {
  // Auto-commit writes are rejected while a transaction is open.
  if db.txn_active { return false; }
  // Stale handle: another writer appended since our last write.
  if !db_file_guard(db) { return false; }
  if db.failed { return false; }
  let existing = btree_search(&db.tree, key);
  match existing {
    None => { return false; }
    Some(_) => {}
  }
  let lsn = wal_file_append_sync(&mut db.wal, WALOpKind.Delete, key, 0, db.durability == 1);
  if lsn == -1 { return false; }
  let sync_failed = lsn == -2;
  db.wal_bytes = db_wal_size(db.path);
  db.records_since_ckpt = db.records_since_ckpt + 1;
  let removed = btree_delete(&mut db.tree, key);
  if removed { db_file_note_value_change(db, key, existing, 0, false); }
  if !removed { return false; }
  if sync_failed { db.failed = true; return false; }
  return true;
}

pub fn db_file_get(db: &DBFile, key: Int) -> Option[Int] {
  return btree_search(&db.tree, key);
}

// M5.3: read a typed row's payload (None when the key is absent or the entry
// is a plain int row). Int rows keep reading through `db_file_get`.
pub fn db_file_get_typed(db: &DBFile, key: Int) -> Option[Vec[Int]] {
  return btree_search_payload(&db.tree, key);
}

// Key-range access on the live/recovered tree: values for keys in [low, high]
// inclusive, in key order. Mirrors `db_range`; same contract as
// `btree_range_query`.
pub fn db_file_range(db: &DBFile, low: Int, high: Int) -> Vec[Int]
  requires: low <= high
{
  return btree_range_query(&db.tree, low, high);
}

// Value-filter query on the live/recovered tree, planned and executed:
// conditions filter VALUES (not keys), key bounds (query_key_range) restrict
// the scanned key range first, a secondary index (M4.2) narrows value
// probes when present, `order` (default 0 = key ascending) sorts before
// `offset` skips matching values and `limit` truncates.
pub fn db_file_query(db: &DBFile, query: &Query) -> Vec[Int] {
  let plan = plan_query_with_index(query, &db.tree, db.indexes.len() > 0);
  if plan.kind == PlanKind.IndexValue && db.indexes.len() > 0 {
    let idx = db.indexes[0];
    return execute_index_value(&idx, &plan, query);
  }
  return execute_plan(&plan, query, &db.tree);
}

// ===========================================================================
// SECONDARY INDEXES (M4.2): value-ordered (value, pk) entries maintained by
// put/delete/txn-commit; handle-scoped, rebuilt on open. See
// src/secondary_index.xi for the structure.
// ===========================================================================

// In-order (key, value) pair collection for index builds.
fn btree_collect_pairs(tree: &BTree, node_idx: Int, keys: &mut Vec[Int], vals: &mut Vec[Int]) {
  var node = tree.store.nodes[node_idx];
  if node.is_leaf {
    var i = 0;
    while i < node.keys.len() {
      keys.push(node.keys[i]);
      vals.push(node.values[i]);
      i = i + 1;
    }
    return;
  }
  var i = 0;
  while i < node.keys.len() {
    btree_collect_pairs(tree, node.children[i], keys, vals);
    keys.push(node.keys[i]);
    vals.push(node.values[i]);
    i = i + 1;
  }
  btree_collect_pairs(tree, node.children[node.keys.len()], keys, vals);
}

// Mirror one logical value change (old -> new, has_new=false for a delete)
// into every index. Write-back via element assignment per C-ORBIT-03.
fn db_file_note_value_change(db: &mut DBFile, key: Int, old: Option[Int], new_value: Int, has_new: Bool) {
  var i = 0;
  while i < db.indexes.len() {
    var idx = db.indexes[i];
    match old {
      Some(v) => { let _ = secidx_remove(&mut idx, v, key); }
      None => {}
    }
    if has_new { secidx_add(&mut idx, new_value, key); }
    db.indexes[i] = idx;
    i = i + 1;
  }
}

// Build a secondary index over the current tree; false for an empty name or
// a name already present.
pub fn db_file_create_index(db: &mut DBFile, name: Str) -> Bool {
  if str_len(name) == 0 { return false; }
  var i = 0;
  while i < db.indexes.len() {
    if db.indexes[i].name == name { return false; }
    i = i + 1;
  }
  var idx = secidx_new(name);
  var keys = Vec[Int].new();
  var vals = Vec[Int].new();
  btree_collect_pairs(&db.tree, db.tree.root, &mut keys, &mut vals);
  var j = 0;
  while j < keys.len() {
    secidx_add(&mut idx, vals[j], keys[j]);
    j = j + 1;
  }
  db.indexes.push(idx);
  return true;
}

pub fn db_file_drop_index(db: &mut DBFile, name: Str) -> Bool {
  var i = 0;
  while i < db.indexes.len() {
    if db.indexes[i].name == name {
      var j = i;
      while j < db.indexes.len() - 1 {
        db.indexes[j] = db.indexes[j + 1];
        j = j + 1;
      }
      db.indexes.pop();
      return true;
    }
    i = i + 1;
  }
  return false;
}

pub fn db_file_index_count(db: &DBFile) -> Int {
  return db.indexes.len();
}

pub fn db_file_index_name(db: &DBFile, at: Int) -> Str {
  if at < 0 || at >= db.indexes.len() { return ""; }
  return db.indexes[at].name;
}

// Direct probe for tests/tools: primary keys whose values fall in [lo, hi],
// in (value, pk) order.
pub fn db_file_index_range(db: &DBFile, name: Str, lo: Int, hi: Int) -> Vec[Int] {
  var i = 0;
  while i < db.indexes.len() {
    if db.indexes[i].name == name {
      let idx = db.indexes[i];
      return secidx_range_pks(&idx, lo, hi);
    }
    i = i + 1;
  }
  var empty = Vec[Int].new();
  return empty;
}

// Catalog tie-in: a flat-store index is over the value column (0) and
// non-unique; unique enforcement and multi-column indexes are later slices.
pub fn db_file_create_index_from_def(db: &mut DBFile, def: &IndexDef) -> Bool {
  if def.column != 0 { return false; }
  if def.unique { return false; }
  return db_file_create_index(db, def.name);
}

pub fn db_file_size(db: &DBFile) -> Int {
  return btree_size(&db.tree);
}

pub fn db_file_last_lsn(db: &DBFile) -> Int {
  return wal_file_next_lsn(&db.wal) - 1;
}

pub fn db_file_flush(db: &mut DBFile) -> Bool {
  if db.failed { return false; }
  let ok = byteio_sync(db.path);
  if !ok { db.failed = true; }
  return ok;
}

// --- durability API (M2.1 first half) --------------------------------------

// 0 = normal (ack without a flush), 1 = immediate (flush at every commit
// ack); invalid modes are rejected.
pub fn db_file_set_durability(db: &mut DBFile, mode: Int) -> Bool {
  if mode != 0 && mode != 1 { return false; }
  db.durability = mode;
  return true;
}

// Two-phase checkpoints flush the WAL before the snapshot publishes its
// header; only meaningful in immediate mode.
pub fn db_file_set_two_phase(db: &mut DBFile, enabled: Bool) -> Bool {
  if enabled && db.durability != 1 { return false; }
  db.two_phase = enabled;
  return true;
}

pub fn db_file_durability(db: &DBFile) -> Int { return db.durability; }

pub fn db_file_two_phase(db: &DBFile) -> Bool { return db.two_phase; }

pub fn db_file_failed(db: &DBFile) -> Bool { return db.failed; }

// (db_file_commit_sync was retired in the BENCH-1 perf slice 2026-10-16:
// auto-commit paths now sync inside `wal_file_append_sync` and the txn path
// syncs its held fd once at commit -- both through the same fault-gated
// byte_io sync seam, with the same latch-on-failure semantics.)

// ===========================================================================
// CHECKPOINT / SNAPSHOT (Phase 1/C): persist the B-tree node set into the
// durable page file; recovery loads the snapshot and replays only the tail.
// ===========================================================================
// Snapshot layout (append-only page log, storage/page_file.xi):
//   page 0                  header: root, order, node_count, lsn, generation
//   page g*STRIDE + i + 1   B-tree node i as of generation g
// A checkpoint appends new versions of ONLY the nodes that changed since the
// last committed generation, then appends the header page LAST: its generation
// commits the snapshot (every page of that generation is already in the log).
// Readers resolve, per node, the newest generation <= the committed header
// generation -- pages from an uncommitted later generation are ignored, so a
// crash mid-checkpoint leaves the previous snapshot fully valid. When the log
// grows past node_count + 64 entries, compaction rewrites one version of every
// page through page_file_write_batch (single atomic rename).
//
// Crash ordering (each step leaves a recoverable state):
//   1. node appends (generation g)       -> crash: g uncommitted, old header
//   2. header append (generation g)      -> snapshot committed at g
//   3. WAL anchor append + truncate      -> anchor kept, next_lsn resumes
//
// Durability honesty (M2.1 second half, M1.2 S4): the snapshot rides on
// byteio_sync/byteio_sync_dir (REAL fsync since stdlib waves 115/118): a
// checkpoint syncs the WAL (two_phase pre-sync), writes the generation,
// publishes the anchor, and syncs the file + directory -- power-loss honest
// up to those seams.

const SNAP_MAGIC: Int = 0x4F;       // 'O' -- snapshot page codec
const SNAP_VERSION: Int = 1;        // header page version (unchanged)
const SNAP_NODE_VERSION: Int = 2;   // node pages: + payload section (M5.3)
const SNAP_KIND_HEADER: Int = 0x48; // 'H'
const SNAP_KIND_NODE: Int = 0x4E;   // 'N'
const SNAP_HEADER_BYTES: Int = 44;
const SNAP_NODE_HEADER_BYTES: Int = 28;
const SNAP_PAGE_MAX_BYTES: Int = 4096;
// 2^32: page id = generation*STRIDE + node_idx + 1. The stride bounds a
// generation's node ids; ids never collide across generations, so older
// generations stay valid until a compaction rewrites the file atomically.
pub const SNAP_PAGE_STRIDE: Int = 4294967296;
// Compact once the raw log grows past node_count + this slack.
const SNAP_COMPACT_SLACK: Int = 64;

fn snap_page_id_for(gen: Int, node_idx: Int) -> Int {
  return gen * SNAP_PAGE_STRIDE + node_idx + 1;
}

type SnapshotMeta = {
  root: Int;
  order: Int;
  node_count: Int;
  checkpoint_lsn: Int;
  generation: Int;
}

type Snapshot = {
  tree: BTree;
  checkpoint_lsn: Int;
  generation: Int;
}

fn snap_header_page_bytes(root: Int, order: Int, node_count: Int,
                          checkpoint_lsn: Int, generation: Int) -> Vec[Int] {
  var out = Vec[Int].new();
  out.push(SNAP_MAGIC);
  out.push(SNAP_VERSION);
  out.push(SNAP_KIND_HEADER);
  out.push(0);
  tuple_push_int_le(&mut out, root);
  tuple_push_int_le(&mut out, order);
  tuple_push_int_le(&mut out, node_count);
  tuple_push_int_le(&mut out, checkpoint_lsn);
  tuple_push_int_le(&mut out, generation);
  return out;
}

fn snap_node_page_bytes(node: &BTreeNode) -> Vec[Int] {
  var out = Vec[Int].new();
  out.push(SNAP_MAGIC);
  out.push(SNAP_NODE_VERSION);
  out.push(SNAP_KIND_NODE);
  var leaf = 0;
  if node.is_leaf { leaf = 1; }
  out.push(leaf);
  tuple_push_int_le(&mut out, node.keys.len());
  tuple_push_int_le(&mut out, node.children.len());
  tuple_push_int_le(&mut out, 0); // reserved
  var i = 0;
  while i < node.keys.len() {
    tuple_push_int_le(&mut out, node.keys[i]);
    i = i + 1;
  }
  i = 0;
  while i < node.values.len() {
    tuple_push_int_le(&mut out, node.values[i]);
    i = i + 1;
  }
  i = 0;
  while i < node.children.len() {
    tuple_push_int_le(&mut out, node.children[i]);
    i = i + 1;
  }
  // Payload section (node version 2): u64 LE count + per entry u64 LE length
  // + bytes (the node-page family's integer width). Parallel to keys; empty
  // = plain int entry.
  tuple_push_int_le(&mut out, node.keys.len());
  i = 0;
  while i < node.keys.len() {
    let p = node_payload(node, i);
    tuple_push_int_le(&mut out, p.len());
    var k = 0;
    while k < p.len() {
      out.push(p[k] & 0xFF);
      k = k + 1;
    }
    i = i + 1;
  }
  return out;
}

// Strict decode: magic/version/kind, exact length, sane flags and counts.
// Accepts node version 1 (legacy: no payload section -> empty payloads) and
// version 2 (payload section). Returns None on any violation -- a snapshot
// either restores whole or not.
fn snap_decode_node(data: &Vec[Int]) -> Option[BTreeNode] {
  if data.len() < SNAP_NODE_HEADER_BYTES { return None; }
  if data[0] != SNAP_MAGIC { return None; }
  let version = data[1];
  if version != SNAP_VERSION && version != SNAP_NODE_VERSION { return None; }
  if data[2] != SNAP_KIND_NODE { return None; }
  let key_count = tuple_read_int_le(data, 4);
  let child_count = tuple_read_int_le(data, 12);
  if key_count < 0 { return None; }
  if child_count < 0 { return None; }

  let base = SNAP_NODE_HEADER_BYTES + 16 * key_count + 8 * child_count;
  if version == SNAP_NODE_VERSION {
    if data.len() < base + 8 { return None; }
    let pcount = tuple_read_int_le(data, base);
    if pcount != key_count { return None; }
    var at = base + 8;
    var j = 0;
    while j < pcount {
      if at + 8 > data.len() { return None; }
      let plen = tuple_read_int_le(data, at);
      if plen < 0 { return None; }
      at = at + 8 + plen;
      if at > data.len() { return None; }
      j = j + 1;
    }
    if at != data.len() { return None; }
  } else {
    if data.len() != base { return None; }
  }

  var keys = Vec[Int].new();
  var values = Vec[Int].new();
  var children = Vec[Int].new();
  var at = SNAP_NODE_HEADER_BYTES;
  var i = 0;
  while i < key_count {
    keys.push(tuple_read_int_le(data, at));
    at = at + 8;
    i = i + 1;
  }
  i = 0;
  while i < key_count {
    values.push(tuple_read_int_le(data, at));
    at = at + 8;
    i = i + 1;
  }
  i = 0;
  while i < child_count {
    children.push(tuple_read_int_le(data, at));
    at = at + 8;
    i = i + 1;
  }

  var payloads = Vec[Vec[Int]].new();
  if version == SNAP_NODE_VERSION {
    var at2 = base + 8;
    var j2 = 0;
    while j2 < key_count {
      let plen2 = tuple_read_int_le(data, at2);
      at2 = at2 + 8;
      var p = Vec[Int].new();
      var k2 = 0;
      while k2 < plen2 {
        p.push(data[at2 + k2] & 0xFF);
        k2 = k2 + 1;
      }
      payloads.push(p);
      at2 = at2 + plen2;
      j2 = j2 + 1;
    }
  } else {
    var j3 = 0;
    while j3 < key_count {
      payloads.push(Vec[Int].new());
      j3 = j3 + 1;
    }
  }

  let leaf = data[3] == 1;
  if leaf && child_count != 0 { return None; }
  if !leaf && child_count == 0 { return None; }
  return Some(BTreeNode{ keys: keys, values: values, payloads: payloads,
                         children: children, is_leaf: leaf });
}

fn snap_decode_header(data: &Vec[Int]) -> Option[SnapshotMeta] {
  if data.len() < SNAP_HEADER_BYTES { return None; }
  if data[0] != SNAP_MAGIC { return None; }
  if data[1] != SNAP_VERSION { return None; }
  if data[2] != SNAP_KIND_HEADER { return None; }
  return Some(SnapshotMeta{
    root: tuple_read_int_le(data, 4),
    order: tuple_read_int_le(data, 12),
    node_count: tuple_read_int_le(data, 20),
    checkpoint_lsn: tuple_read_int_le(data, 28),
    generation: tuple_read_int_le(data, 36),
  });
}

// Header selection: a committed checkpoint appends its header page LAST, so
// among valid header pages (id 0) the highest generation is the active one.
fn snap_read_meta(pages: &Vec[Page]) -> Option[SnapshotMeta] {
  var best = SnapshotMeta{ root: 0, order: 3, node_count: 0, checkpoint_lsn: 0, generation: -1 };
  var found = false;
  var i = 0;
  while i < pages.len() {
    let pg = pages[i];
    if pg.id == 0 {
      let dec = snap_decode_header(&pg.data);
      match dec {
        None => {}
        Some(m) => {
          let mm: SnapshotMeta = m;
          if mm.generation > best.generation {
            best = mm;
            found = true;
          }
        }
      }
    }
    i = i + 1;
  }
  if !found { return None; }
  return Some(best);
}

// One committed page per node: the newest generation <= active_gen. Returns
// None when any node has no committed page (the snapshot is then unusable).
fn snap_resolve_pages(pages: &Vec[Page], node_count: Int,
                       active_gen: Int) -> Option[Vec[Page]] {
  var best_gen = Vec[Int].new();
  var best = Vec[Page].new();
  var i = 0;
  while i < node_count {
    var empty = Vec[Int].new();
    best_gen.push(-1);
    best.push(Page.new(0, empty, 0));
    i = i + 1;
  }

  var p = 0;
  while p < pages.len() {
    let pg = pages[p];
    if pg.id > 0 {
      let zero = pg.id - 1;
      let idx = zero % SNAP_PAGE_STRIDE;
      let gen = zero / SNAP_PAGE_STRIDE;
      if idx < node_count && gen <= active_gen {
        if gen > best_gen[idx] {
          best_gen[idx] = gen;
          best[idx] = pg;
        }
      }
    }
    p = p + 1;
  }

  i = 0;
  while i < node_count {
    if best_gen[i] < 0 { return None; }
    i = i + 1;
  }
  return Some(best);
}

// Atomic compaction: one page per node + the header at generation `gen`,
// installed through page_file_write_batch (single rename). Used when the log
// has grown past node_count + slack.
fn snap_compact(path: Str, tree: &mut BTree, checkpoint_lsn: Int, gen: Int) -> Bool {
  var pages = Vec[Page].new();
  var i = 0;
  while i < tree.store.nodes.len() {
    let node = tree.store.nodes[i];
    let data = snap_node_page_bytes(&node);
    if data.len() > SNAP_PAGE_MAX_BYTES { return false; }
    pages.push(Page.new(snap_page_id_for(gen, i), data, page_compute_checksum(&data)));
    i = i + 1;
  }
  let hdr = snap_header_page_bytes(tree.root, tree.order, tree.store.nodes.len(),
                                   checkpoint_lsn, gen);
  if hdr.len() > SNAP_PAGE_MAX_BYTES { return false; }
  pages.push(Page.new(0, hdr, page_compute_checksum(&hdr)));
  let pf = page_file_open(path);
  let wrote = page_file_write_batch(&pf, pages);
  if wrote { ns_mark_clean(&mut tree.store); }
  return wrote;
}

// Commit a checkpoint incrementally: append new versions of only the DIRTY
// nodes (tracked by the NodeStore), then append the header page (id 0,
// generation = prior + 1) LAST as the commit point. Forces a full write when
// there is no valid prior snapshot or when pages of an uncommitted crashed
// generation linger (they must never become the only version of a node).
// Returns the committed generation, or -1 when nothing was committed; the
// previous snapshot stays valid in every failure mode. `allow_compact` is
// false while a snapshot pin is live (M3): the compaction branch is deferred
// (counted) and the incremental append continues.
fn snap_flush(path: Str, tree: &mut BTree, checkpoint_lsn: Int, allow_compact: Bool) -> Int {
  let pf = page_file_open(path);
  let pages = page_log_read_all(&pf);
  let meta_found = snap_read_meta(&pages);
  var prior_gen = 0;
  var have_prior = false;
  match meta_found {
    None => {}
    Some(m) => {
      let mm: SnapshotMeta = m;
      prior_gen = mm.generation;
      have_prior = true;
    }
  }

  var has_uncommitted = false;
  var q = 0;
  while q < pages.len() {
    let pg2 = pages[q];
    if pg2.id > 0 {
      let z = pg2.id - 1;
      let g2 = z / SNAP_PAGE_STRIDE;
      if g2 == prior_gen + 1 { has_uncommitted = true; }
    }
    q = q + 1;
  }
  let write_all = !have_prior || has_uncommitted;

  let gen = prior_gen + 1;
  let entries = page_log_len(&pf);
  if entries > tree.store.nodes.len() + SNAP_COMPACT_SLACK {
    if !allow_compact {
      // M3: compaction would rewrite one version per node, dropping the older
      // generations a live pin may still need. Defer; the next checkpoint
      // after the pin is released compacts.
      tree.store.compaction_deferred = tree.store.compaction_deferred + 1;
    } else {
      if snap_compact(path, tree, checkpoint_lsn, gen) { return gen; }
      return -1;
    }
  }

  var i = 0;
  while i < tree.store.nodes.len() {
    var should_write = write_all;
    if !should_write { should_write = tree.store.dirty[i]; }
    if should_write {
      let node = tree.store.nodes[i];
      let data = snap_node_page_bytes(&node);
      if data.len() > SNAP_PAGE_MAX_BYTES { return -1; }
      let pg = Page.new(snap_page_id_for(gen, i), data, page_compute_checksum(&data));
      if !page_log_append(&pf, pg) { return -1; }
    }
    i = i + 1;
  }

  let hdr = snap_header_page_bytes(tree.root, tree.order, tree.store.nodes.len(),
                                   checkpoint_lsn, gen);
  if hdr.len() > SNAP_PAGE_MAX_BYTES { return -1; }
  let hp = Page.new(0, hdr, page_compute_checksum(&hdr));
  if page_log_append(&pf, hp) {
    ns_mark_clean(&mut tree.store);
    return gen;
  }
  return -1;
}

// Load a snapshot; None when absent or invalid at ANY level (page checksum,
// header, node codec, node count, child-pointer range). The caller then
// falls back to full WAL replay.
fn snap_load(path: Str) -> Option[Snapshot] {
  let pf = page_file_open(path);
  let pages = page_log_read_all(&pf);
  let meta_found = snap_read_meta(&pages);
  var meta = SnapshotMeta{ root: 0, order: 3, node_count: 0, checkpoint_lsn: 0, generation: -1 };
  match meta_found {
    None => { return None; }
    Some(m) => {
      let mm: SnapshotMeta = m;
      meta = mm;
    }
  }
  if meta.order < 3 { return None; }
  if meta.node_count < 1 { return None; }
  if meta.node_count >= SNAP_PAGE_STRIDE { return None; }
  if meta.root < 0 { return None; }
  if meta.root >= meta.node_count { return None; }

  let resolved = snap_resolve_pages(&pages, meta.node_count, meta.generation);
  var best = Vec[Page].new();
  match resolved {
    None => { return None; }
    Some(v) => {
      let vv: Vec[Page] = v;
      best = vv;
    }
  }

  var nodes = Vec[BTreeNode].new();
  var i = 0;
  while i < meta.node_count {
    let pg = best[i];
    let dec = snap_decode_node(&pg.data);
    match dec {
      None => { return None; }
      Some(n) => {
        let nd: BTreeNode = n;
        nodes.push(nd);
      }
    }
    i = i + 1;
  }

  // Child pointers must address loaded nodes: a CRC-valid but semantically
  // corrupt snapshot must not reach search/traverse as a dangling pointer.
  var j = 0;
  while j < nodes.len() {
    let nd = nodes[j];
    var c = 0;
    while c < nd.children.len() {
      if nd.children[c] < 0 { return None; }
      if nd.children[c] >= meta.node_count { return None; }
      c = c + 1;
    }
    j = j + 1;
  }

  // Loaded nodes are clean: their pages are already committed.
  var dirty = Vec[Bool].new();
  var births = Vec[Int].new();
  var di = 0;
  while di < nodes.len() {
    dirty.push(false);
    births.push(0);
    di = di + 1;
  }
  var pins = Vec[DBSnapshot].new();
  var store = NodeStore{ nodes: nodes, dirty: dirty, births: births, pins: pins,
                         pin_clock: 0, compaction_deferred: 0 };
  var tree = BTree{ root: meta.root, order: meta.order, store: store };
  return Some(Snapshot{ tree: tree, checkpoint_lsn: meta.checkpoint_lsn, generation: meta.generation });
}

// --- v2 snapshot container (byte blocks; M1.2 S3) --------------------------
// The node payload codec is unchanged (`snap_node_page_bytes`); only the
// container changes: node index = block page_id, snapshot generation = block
// generation, and the block store's header slot carries the meta (root,
// order, node_count, checkpoint_lsn). Reads auto-detect by first byte.

fn snap_format_v2(path: Str) -> Bool {
  match byteio_read_at(path, 0, 1) {
    Some(b) => {
      if b.len() == 1 && b[0] == 0x4F { return true; }
      return false;
    }
    None => { return false; }
  }
}

fn snap_load_auto(path: Str) -> Option[Snapshot] {
  if snap_format_v2(path) { return snap_load_v2(path); }
  let pf = page_file_open(path);
  let _ = page_log_heal_tail(&pf);
  return snap_load(path);
}

// Read a v2 snapshot through the block store: the committed header carries
// the meta, one committed block per node index carries the node payload.
// Same strictness as v1: any gap/codec/range violation is None.
fn snap_load_v2(path: Str) -> Option[Snapshot] {
  let bs = block_store_open(path);
  if !bs.committed { return None; }
  let node_count = bs.header.node_count;
  let order = bs.header.order;
  let root = bs.header.root;
  if order < 3 { return None; }
  if node_count < 1 { return None; }
  if node_count >= SNAP_PAGE_STRIDE { return None; }
  if root < 0 { return None; }
  if root >= node_count { return None; }

  var nodes = Vec[BTreeNode].new();
  var i = 0;
  while i < node_count {
    match block_store_read(&bs, i) {
      Some(p) => {
        match snap_decode_node(&p.payload) {
          Some(nd) => { nodes.push(nd); }
          None => { return None; }
        }
      }
      None => { return None; }
    }
    i = i + 1;
  }

  var j = 0;
  while j < nodes.len() {
    let nd = nodes[j];
    var c = 0;
    while c < nd.children.len() {
      if nd.children[c] < 0 { return None; }
      if nd.children[c] >= node_count { return None; }
      c = c + 1;
    }
    j = j + 1;
  }

  var dirty = Vec[Bool].new();
  var births = Vec[Int].new();
  var di = 0;
  while di < nodes.len() {
    dirty.push(false);
    births.push(0);
    di = di + 1;
  }
  var pins = Vec[DBSnapshot].new();
  var store = NodeStore{ nodes: nodes, dirty: dirty, births: births, pins: pins,
                         pin_clock: 0, compaction_deferred: 0 };
  var tree = BTree{ root: root, order: order, store: store };
  return Some(Snapshot{ tree: tree, checkpoint_lsn: bs.header.checkpoint_lsn,
                        generation: bs.header.committed_generation });
}

// Full v2 write from the TREE (all nodes + header commit) into a temp file,
// then one atomic rename. Used for migration (v1 -> v2), format flips, and
// compaction. The original file is untouched until the rename succeeds.
fn v2_rewrite_all(path: Str, tree: &mut BTree, gen: Int, checkpoint_lsn: Int) -> Bool {
  let tmp = path + ".rw";
  match io.remove_file(tmp) { Ok(_) => {} Err(_) => {} }
  var bs = block_store_open(tmp);
  var i = 0;
  while i < tree.store.nodes.len() {
    let node = tree.store.nodes[i];
    let data = snap_node_page_bytes(&node);
    if block_store_put(&mut bs, gen, i, &data) < 0 { return false; }
    i = i + 1;
  }
  let h = BlockHeader{
    root: tree.root,
    order: tree.order,
    node_count: tree.store.nodes.len(),
    checkpoint_lsn: checkpoint_lsn,
    committed_generation: gen,
    block_count: bs.block_count,
    next_page_id: 0,
  };
  if !block_store_commit(&mut bs, &h) { return false; }
  match io.rename(tmp, path) {
    Ok(_) => {}
    Err(_) => { return false; }
  }
  return true;
}

// v2 incremental flush: append new versions of only the DIRTY nodes at
// gen = committed + 1, then commit the header slot. A v1 (or absent) file is
// rewritten whole (migration-on-write). Crashed partial generations are
// overwritten by the same-gen rewrites on the next attempt, so they can
// never become the only version of a node. `allow_compact` is false while a
// snapshot pin is live (M3): the block-count rewrite (compaction) is deferred
// (counted) and the incremental append continues. Returns the committed
// generation, or -1 (the previous snapshot stays valid in every failure
// mode).
fn snap_flush_v2(path: Str, tree: &mut BTree, checkpoint_lsn: Int, allow_compact: Bool) -> Int {
  let is_v2 = snap_format_v2(path);
  if !is_v2 {
    let gen = 1;
    if v2_rewrite_all(path, tree, gen, checkpoint_lsn) {
      ns_mark_clean(&mut tree.store);
      return gen;
    }
    return -1;
  }

  var bs = block_store_open(path);
  var prior_gen = 0;
  var have_prior = false;
  if bs.committed {
    prior_gen = bs.header.committed_generation;
    have_prior = true;
  }
  let gen = prior_gen + 1;

  if !have_prior || bs.block_count > tree.store.nodes.len() + SNAP_COMPACT_SLACK {
    if have_prior && !allow_compact {
      // M3: the whole-file rewrite drops older block generations a live pin
      // may still need. Defer; append incrementally instead.
      tree.store.compaction_deferred = tree.store.compaction_deferred + 1;
    } else {
      if v2_rewrite_all(path, tree, gen, checkpoint_lsn) {
        ns_mark_clean(&mut tree.store);
        return gen;
      }
      return -1;
    }
  }

  var i = 0;
  while i < tree.store.nodes.len() {
    if tree.store.dirty[i] {
      let node = tree.store.nodes[i];
      let data = snap_node_page_bytes(&node);
      if block_store_put(&mut bs, gen, i, &data) < 0 { return -1; }
    }
    i = i + 1;
  }
  let h = BlockHeader{
    root: tree.root,
    order: tree.order,
    node_count: tree.store.nodes.len(),
    checkpoint_lsn: checkpoint_lsn,
    committed_generation: gen,
    block_count: bs.block_count,
    next_page_id: 0,
  };
  if !block_store_commit(&mut bs, &h) { return -1; }
  ns_mark_clean(&mut tree.store);
  return gen;
}

// Migrate an existing v1 text snapshot to v2 in place (idempotent; absent
// or already-v2 snapshots are a no-op success). Reads through the same
// auto-detect loader, writes a fresh v2 store via temp+rename.
pub fn db_file_migrate_snapshot(path: Str) -> Bool {
  let snap_path = path + ".snap";
  if snap_format_v2(snap_path) { return true; }
  match snap_load(snap_path) {
    None => { return true; }
    Some(s) => {
      let snap: Snapshot = s;
      var tree = snap.tree;
      return v2_rewrite_all(snap_path, &mut tree, snap.generation + 1, snap.checkpoint_lsn);
    }
  }
}

// Checkpoint: commit an incremental snapshot of the current tree (only the
// nodes that changed since the last committed generation are appended; the
// header page commits the generation), append the Checkpoint anchor record,
// then truncate the segment to keep the anchor and everything after it.
// Returns the anchor LSN, or -1 when the snapshot could not be committed (the
// WAL is untouched in that case).
pub fn db_file_checkpoint(db: &mut DBFile) -> Int {
  // A pending transaction's records must not be truncated: truncation keeps
  // records >= the anchor, and the checkpoint_lsn gate would skip a later
  // commit record's ops. Reject while a transaction is active.
  if db.txn_active { return -1; }
  // A stale handle must not snapshot its older tree over a newer WAL.
  if !db_file_guard(db) { return -1; }
  if db.failed { return -1; }
  let snap_path = db.path + ".snap";
  let snap_lsn = wal_file_next_lsn(&db.wal) - 1;
  // Two-phase (immediate mode): the WAL must be durable BEFORE the snapshot
  // publishes its header, so a crash can never leave a snapshot that runs
  // ahead of the log (docs/REFERENCE-STUDY.md; redb 2PC).
  if db.durability == 1 && db.two_phase {
    if !byteio_sync(db.path) {
      db.failed = true;
      return -1;
    }
  }
  var gen = -1;
  // M3: while a snapshot pin is live the compaction branch defers (counted);
  // incremental appends, the anchor and the WAL truncate are unaffected.
  let allow_compact = db.tree.store.pins.len() == 0;
  if db.page_format == 2 {
    gen = snap_flush_v2(snap_path, &mut db.tree, snap_lsn, allow_compact);
  } else if snap_format_v2(snap_path) {
    // Handle writes v1 while the file is v2: rewrite whole via the batch
    // path (single rename), keeping the format on-disk authoritative. That
    // rewrite is compaction-class: defer the checkpoint while pinned.
    if !allow_compact {
      db.tree.store.compaction_deferred = db.tree.store.compaction_deferred + 1;
      return -1;
    }
    var pgen = 0;
    let bs = block_store_open(snap_path);
    if bs.committed { pgen = bs.header.committed_generation; }
    if snap_compact(snap_path, &mut db.tree, snap_lsn, pgen + 1) { gen = pgen + 1; }
  } else {
    let pf = page_file_open(snap_path);
    // A torn trailing append must not merge with this checkpoint's entries.
    let _ = page_log_heal_tail(&pf);
    gen = snap_flush(snap_path, &mut db.tree, snap_lsn, allow_compact);
  }
  if gen < 0 { return -1; }
  db.snap_generation = gen;

  var payload = Vec[Int].new();
  payload.push(gen);
  payload.push(db.tree.store.nodes.len());
  payload.push(db.tree.order);
  let anchor = wal_file_append_tagged(&mut db.wal, WALOpKind.Checkpoint,
                                      snap_lsn, db.tree.root, payload, 0);
  if anchor < 0 { return -1; }

  // Best-effort compaction: keeping lsn >= anchor retains the anchor itself,
  // so next_lsn still resumes correctly. A failed truncate leaves older
  // records that `db_file_open` skips via the snapshot's checkpoint_lsn gate.
  let _ = wal_file_truncate(db.path, anchor);
  db.wal_bytes = db_wal_size(db.path);
  db.records_since_ckpt = 0;
  // Post-commit flush (immediate mode): a failure latches the handle; the
  // checkpoint itself may still have committed (the caller can inspect
  // db_file_failed). WAL first, then the snapshot.
  if db.durability == 1 {
    if !byteio_sync(db.path) {
      db.failed = true;
      return -1;
    }
    if !byteio_sync(snap_path) {
      db.failed = true;
      return -1;
    }
  }
  return anchor;
}

// Policy hook: checkpoint when at least `limit` records were logged since the
// last checkpoint. Returns the anchor LSN when a checkpoint ran, or -1 when
// the threshold is not reached (or the checkpoint failed).
pub fn db_file_maybe_checkpoint(db: &mut DBFile, limit: Int) -> Int
  requires: limit >= 1
{
  if db.records_since_ckpt < limit { return -1; }
  return db_file_checkpoint(db);
}

// ===========================================================================
// DURABLE TRANSACTIONS (D2): single-active-transaction API. Operations are
// logged as they happen (WAL-before-ack) but applied to the tree only at
// commit; abort -- or a crash before the commit record -- discards them.
// Recovery classifies committed vs uncommitted at the Begin/Commit records
// (see db_file_open), so no physical undo pass is needed.
// ===========================================================================

pub fn db_file_txn_active(db: &DBFile) -> Bool {
  return db.txn_active;
}

// Lazy held append handle for the transaction window (BENCH-1 perf slice
// 2026-10-16): opened on first use, reused by every txn append, closed by
// commit/abort. One open/close pair per TRANSACTION instead of one per
// record (docs/BENCH-1.md finding #1). WAL appends stay ungated; the sync
// seam still fires the kind-1 gate exactly once per durable commit.
fn db_txn_fd(db: &mut DBFile) -> Int {
  if db.wal_fd >= 0 { return db.wal_fd; }
  match byteio_open_append(db.path) {
    None => { return -1; }
    Some(fd) => {
      db.wal_fd = fd;
      return fd;
    }
  }
}

// Close the held transaction handle (if any). Best-effort; the fd owner is
// the handle itself, so commit/abort must call this on every exit path.
fn db_txn_close_fd(db: &mut DBFile) {
  if db.wal_fd >= 0 {
    let _ = byteio_close_append(db.wal_fd);
    db.wal_fd = -1;
  }
}

pub fn db_file_txn_begin(db: &mut DBFile) -> Bool {
  if db.txn_active { return false; }
  if !db_file_guard(db) { return false; }
  if db.failed { return false; }
  let fd = db_txn_fd(db);
  if fd < 0 { return false; }
  let lsn = wal_file_append_fd(&mut db.wal, fd, WALOpKind.BeginTxn, 0, 0);
  if lsn < 0 {
    db_txn_close_fd(db);
    return false;
  }
  db.wal_bytes = db_wal_size(db.path);
  db.records_since_ckpt = db.records_since_ckpt + 1;
  db.txn_active = true;
  db.txn_ops = Vec[TxOp].new();
  db.sp_active = false;
  db.sp_marker = 0;
  return true;
}

// Buffered upsert (applied as delete+insert on commit/replay; idempotent).
pub fn db_file_txn_put(db: &mut DBFile, key: Int, value: Int) -> Bool {
  if !db.txn_active { return false; }
  if !db_file_guard(db) { return false; }
  if db.failed { return false; }
  let fd = db_txn_fd(db);
  if fd < 0 { return false; }
  let lsn = wal_file_append_fd(&mut db.wal, fd, WALOpKind.Update, key, value);
  if lsn < 0 { return false; }
  db.wal_bytes = db_wal_size(db.path);
  db.records_since_ckpt = db.records_since_ckpt + 1;
  db.txn_ops.push(TxOp{ code: 2, key: key, value: value,
                        payload: Vec[Int].new() });
  return true;
}

// Buffered delete (idempotent: deleting a missing key is a no-op on apply).
pub fn db_file_txn_delete(db: &mut DBFile, key: Int) -> Bool {
  if !db.txn_active { return false; }
  if !db_file_guard(db) { return false; }
  if db.failed { return false; }
  let fd = db_txn_fd(db);
  if fd < 0 { return false; }
  let lsn = wal_file_append_fd(&mut db.wal, fd, WALOpKind.Delete, key, 0);
  if lsn < 0 { return false; }
  db.wal_bytes = db_wal_size(db.path);
  db.records_since_ckpt = db.records_since_ckpt + 1;
  db.txn_ops.push(TxOp{ code: 3, key: key, value: 0,
                        payload: Vec[Int].new() });
  return true;
}

// Commit: append the CommitTxn record FIRST (durability), then apply the
// buffered ops to the in-memory tree. The whole window (Begin + ops +
// Commit) rides ONE held handle; immediate mode fsyncs it once, through the
// same gated sync seam as before, and a failed sync latches the handle.
pub fn db_file_txn_commit(db: &mut DBFile) -> Bool {
  if !db.txn_active { return false; }
  if !db_file_guard(db) { return false; }
  if db.failed { return false; }
  let fd = db_txn_fd(db);
  if fd < 0 { return false; }
  let lsn = wal_file_append_fd(&mut db.wal, fd, WALOpKind.CommitTxn, 0, 0);
  if lsn < 0 { return false; }
  db.wal_bytes = db_wal_size(db.path);
  db.records_since_ckpt = db.records_since_ckpt + 1;
  var k = 0;
  while k < db.txn_ops.len() {
    let op = db.txn_ops[k];
    let old = btree_search(&db.tree, op.key);
    db_file_apply_txop(&mut db.tree, op);
    if op.code == 3 {
      db_file_note_value_change(db, op.key, old, 0, false);
    } else {
      db_file_note_value_change(db, op.key, old, op.value, true);
    }
    k = k + 1;
  }
  db.txn_active = false;
  db.txn_ops = Vec[TxOp].new();
  db.sp_active = false;
  db.sp_marker = 0;
  var sync_failed = false;
  if db.durability == 1 {
    if !byteio_sync_fd(fd) { sync_failed = true; }
  }
  db_txn_close_fd(db);
  if sync_failed { db.failed = true; return false; }
  return true;
}

// Abort: append the AbortTxn marker (audit trail) and discard the buffer.
pub fn db_file_txn_abort(db: &mut DBFile) -> Bool {
  if !db.txn_active { return false; }
  if !db_file_guard(db) { return false; }
  if db.failed { return false; }
  let fd = db_txn_fd(db);
  if fd < 0 { return false; }
  let lsn = wal_file_append_fd(&mut db.wal, fd, WALOpKind.AbortTxn, 0, 0);
  if lsn < 0 { return false; }
  db.wal_bytes = db_wal_size(db.path);
  db.records_since_ckpt = db.records_since_ckpt + 1;
  db.txn_active = false;
  db.txn_ops = Vec[TxOp].new();
  db.sp_active = false;
  db.sp_marker = 0;
  db_txn_close_fd(db);
  return true;
}

// ===========================================================================
// M3 MINIMAL SUBSET: SNAPSHOT PINS + SAVEPOINTS (docs/MVCC.md)
// ===========================================================================
// A snapshot pin captures {root, lsn, generation} and makes it stable: while
// pins exist, every write path copy-on-writes the nodes it touches
// (`cow_shadow`), so a pinned root keeps reading the exact state at capture.
// No per-page version chains: old versions stay in the arena reachable only
// from pins. Pins are handle-local; a reopen starts with none.
// Savepoints are txn-scoped rollback markers: restore trims the buffered ops
// and splices the WAL window (Abort + Begin + re-log of the kept ops) so
// replay reconstructs exactly the surviving set after any crash.

fn db_file_pin_index(db: &DBFile, id: Int) -> Int {
  var i = 0;
  while i < db.tree.store.pins.len() {
    if db.tree.store.pins[i].id == id { return i; }
    i = i + 1;
  }
  return -1;
}

// Capture the current committed state as a stable read view (id 0 would mean
// failure; ids are monotone and never reused). Buffered transaction ops are
// NOT visible in the pinned view (read-committed).
pub fn db_file_snapshot_begin(db: &mut DBFile) -> DBSnapshot {
  db.tree.store.pin_clock = db.tree.store.pin_clock + 1;
  var pin = DBSnapshot{ id: db.tree.store.pin_clock, root: db.tree.root,
                        lsn: wal_file_next_lsn(&db.wal) - 1,
                        generation: db.snap_generation };
  db.tree.store.pins.push(pin);
  return pin;
}

// Release a pin (false for an unknown id). Writes may then mutate its
// versions in place again; the arena keeps the old nodes as garbage until the
// M1.1b free list exists.
pub fn db_file_snapshot_end(db: &mut DBFile, id: Int) -> Bool {
  let at = db_file_pin_index(db, id);
  if at < 0 { return false; }
  var i = at;
  while i < db.tree.store.pins.len() - 1 {
    db.tree.store.pins[i] = db.tree.store.pins[i + 1];
    i = i + 1;
  }
  db.tree.store.pins.pop();
  return true;
}

pub fn db_file_snapshot_pins(db: &DBFile) -> Int {
  return db.tree.store.pins.len();
}

// Oldest pinned WAL LSN, or -1 when none. Deferred-free hook for the M1.1b
// pager: once a free list exists, pages are allocatable only below this LSN.
pub fn db_file_min_pinned_lsn(db: &DBFile) -> Int {
  if db.tree.store.pins.len() == 0 { return -1; }
  var best = db.tree.store.pins[0].lsn;
  var i = 1;
  while i < db.tree.store.pins.len() {
    if db.tree.store.pins[i].lsn < best { best = db.tree.store.pins[i].lsn; }
    i = i + 1;
  }
  return best;
}

// Snapshot reads: exactly the state at `db_file_snapshot_begin`. None /
// empty / -1 for an id that is not a live pin.
pub fn db_file_snapshot_get(db: &DBFile, id: Int, key: Int) -> Option[Int] {
  let at = db_file_pin_index(db, id);
  if at < 0 { return None; }
  return search_node(&db.tree, db.tree.store.pins[at].root, key);
}

pub fn db_file_snapshot_get_typed(db: &DBFile, id: Int, key: Int) -> Option[Vec[Int]] {
  let at = db_file_pin_index(db, id);
  if at < 0 { return None; }
  return search_payload_node(&db.tree, db.tree.store.pins[at].root, key);
}

pub fn db_file_snapshot_range(db: &DBFile, id: Int, low: Int, high: Int) -> Vec[Int] {
  var results = Vec[Int].new();
  let at = db_file_pin_index(db, id);
  if at < 0 { return results; }
  if low > high { return results; }
  collect_range(&db.tree, db.tree.store.pins[at].root, low, high, &mut results);
  return results;
}

pub fn db_file_snapshot_count(db: &DBFile, id: Int) -> Int {
  let at = db_file_pin_index(db, id);
  if at < 0 { return -1; }
  return count_keys(&db.tree, db.tree.store.pins[at].root);
}

// Last committed snapshot generation for this handle (0 = none), set on open
// and after every committed checkpoint.
pub fn db_file_snap_generation(db: &DBFile) -> Int {
  return db.snap_generation;
}

// Checkpoints that would have compacted but were deferred because a snapshot
// pin was live.
pub fn db_file_compaction_deferrals(db: &DBFile) -> Int {
  return db.tree.store.compaction_deferred;
}

// --- savepoints (txn-scoped) ----------------------------------------------

pub fn db_file_txn_savepoint_active(db: &DBFile) -> Bool {
  return db.sp_active;
}

// Record a rollback marker at the current buffer length (single level; false
// without an active transaction or when a savepoint is already active).
pub fn db_file_txn_savepoint(db: &mut DBFile) -> Bool {
  if !db.txn_active { return false; }
  if db.sp_active { return false; }
  if !db_file_guard(db) { return false; }
  if db.failed { return false; }
  db.sp_marker = db.txn_ops.len();
  db.sp_active = true;
  return true;
}

// Restore to the savepoint: trim the buffered ops, then splice the WAL window
// so recovery agrees with the buffer -- AbortTxn closes the current window
// (replay discards it), BeginTxn opens a fresh one, and the kept ops are
// re-logged verbatim. The savepoint stays active (SQL ROLLBACK TO SAVEPOINT
// semantics); commit/abort release it.
pub fn db_file_txn_savepoint_restore(db: &mut DBFile) -> Bool {
  if !db.txn_active { return false; }
  if !db.sp_active { return false; }
  if !db_file_guard(db) { return false; }
  if db.failed { return false; }
  while db.txn_ops.len() > db.sp_marker {
    db.txn_ops.pop();
  }
  let fd = db_txn_fd(db);
  if fd < 0 { return false; }
  var lsn = wal_file_append_fd(&mut db.wal, fd, WALOpKind.AbortTxn, 0, 0);
  if lsn < 0 { return false; }
  lsn = wal_file_append_fd(&mut db.wal, fd, WALOpKind.BeginTxn, 0, 0);
  if lsn < 0 { return false; }
  var appended = 2;
  var i = 0;
  while i < db.txn_ops.len() {
    let op = db.txn_ops[i];
    if op.code == 3 {
      lsn = wal_file_append_fd(&mut db.wal, fd, WALOpKind.Delete, op.key, 0);
    } else {
      lsn = wal_file_append_fd(&mut db.wal, fd, WALOpKind.Update, op.key, op.value);
    }
    if lsn < 0 { return false; }
    appended = appended + 1;
    i = i + 1;
  }
  db.wal_bytes = db_wal_size(db.path);
  db.records_since_ckpt = db.records_since_ckpt + appended;
  return true;
}

// Drop the savepoint marker (false without an active transaction/marker).
pub fn db_file_txn_savepoint_release(db: &mut DBFile) -> Bool {
  if !db.txn_active { return false; }
  if !db.sp_active { return false; }
  db.sp_active = false;
  db.sp_marker = 0;
  return true;
}