// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom.db.index.btree

use xiom.db.storage.block_store;
use xiom.db.index.node_page;

// Flat-array B-tree: node arena (`NodeStore`) with dirty tracking and M3
// snapshot pins (copy-on-write shadowing), plus the canonical structural
// operations (search/insert/delete/range/min/max/to_vec). Extracted
// move-only from engine.xi (R1 split, 2026-10-18).

// Snapshot pin (M3 minimal subset, docs/MVCC.md): a stable read view over
// the node arena. `root` indexes this handle's arena; `lsn` is the highest
// WAL LSN at capture; `generation` is the last committed snapshot generation
// (0 = none). Handle-local; live until `db_file_snapshot_end` or reopen.
pub type DBSnapshot = {
  id: Int;
  root: Int;
  lsn: Int;
  generation: Int;
  pin_epoch: Int;
}

// NodeStore: the node arena behind a B-tree. `dirty[i]` marks node i as
// changed since the last successful snapshot flush; checkpoints encode only
// dirty nodes (M1.1). M3 adds version bookkeeping: `births[i]` is the write
// epoch node i was created in and `pin_clock` counts pin creations; while
// pins exist, a node with `birth <= pin_clock` may be reachable from a pinned
// root and must be shadow-copied before any mutation (see `cow_shadow`).
// `compaction_deferred` counts checkpoint compactions skipped because a pin
// was live (docs/MVCC.md sec. 2.3).
//
// M1.1b: two modes.
//  - resident (`paged=false`): v1 snapshots. `nodes[i]` holds every node.
//  - paged (`paged=true`): v2 snapshots. Node ids are block page ids; the
//    node STRUCTS live in a bounded clock cache (`frames`) reached through
//    `slots[id]`. Reads load on miss from the owned `bs` block store; dirty
//    frames spill at `write_gen` (committed+1) before eviction. Metadata
//    (`dirty`/`births`/`live`) stays O(n); node bodies are bounded by
//    `capacity`. XIOM references are shallow, so cache mutation through
//    `&NodeStore` is legal (verified 2026-10-19); callers keep the read API.
pub type NodeStore = {
  nodes: Vec[BTreeNode];
  dirty: Vec[Bool];
  births: Vec[Int];
  live: Vec[Bool];
  pending_free: Vec[Int];
  pending_epoch: Vec[Int];
  pins: Vec[DBSnapshot];
  pin_clock: Int;
  compaction_deferred: Int;
  paged: Bool;
  bs: BlockStore;
  write_gen: Int;
  count: Int;
  slots: Vec[Int];
  frames: Vec[BTreeNode];
  frame_ids: Vec[Int];
  frame_dirty: Vec[Bool];
  frame_ref: Vec[Bool];
  hand: Int;
  capacity: Int;
  // [hits, misses, evictions, spills, corrupt, io_errors]
  stats: Vec[Int];
}

fn ns_empty_stats() -> Vec[Int] {
  var st = Vec[Int].new();
  var i = 0;
  while i < 6 {
    st.push(0);
    i = i + 1;
  }
  return st;
}

// Resident store for v1 snapshots and fresh in-memory trees.
pub fn ns_new_resident(nodes: Vec[BTreeNode], dirty: Vec[Bool],
                       births: Vec[Int]) -> NodeStore {
  var live = Vec[Bool].new();
  var i = 0;
  while i < nodes.len() {
    live.push(true);
    i = i + 1;
  }
  var empty_pending = Vec[Int].new();
  var empty_slots = Vec[Int].new();
  var empty_frames = Vec[BTreeNode].new();
  var empty_ids = Vec[Int].new();
  var empty_flags = Vec[Bool].new();
  return NodeStore{
    nodes: nodes, dirty: dirty, births: births, live: live,
    pending_free: empty_pending, pending_epoch: Vec[Int].new(),
    pins: Vec[DBSnapshot].new(), pin_clock: 0, compaction_deferred: 0,
    paged: false, bs: block_store_empty(), write_gen: 0, count: nodes.len(),
    slots: empty_slots, frames: empty_frames, frame_ids: empty_ids,
    frame_dirty: empty_flags, frame_ref: Vec[Bool].new(), hand: 0,
    capacity: 0, stats: ns_empty_stats(),
  };
}

// Paged store for v2 snapshots: no node is decoded until first access.
pub fn ns_new_paged(bs: BlockStore, count: Int, capacity: Int) -> NodeStore
  requires: count >= 1
  requires: capacity >= 1
{
  var slots = Vec[Int].new();
  var dirty = Vec[Bool].new();
  var births = Vec[Int].new();
  var live = Vec[Bool].new();
  var i = 0;
  while i < count {
    slots.push(-1);
    dirty.push(false);
    births.push(0);
    live.push(true);
    i = i + 1;
  }
  var frames = Vec[BTreeNode].new();
  var frame_ids = Vec[Int].new();
  var frame_dirty = Vec[Bool].new();
  var frame_ref = Vec[Bool].new();
  var f = 0;
  while f < capacity {
    frames.push(new_leaf_node());
    frame_ids.push(-1);
    frame_dirty.push(false);
    frame_ref.push(false);
    f = f + 1;
  }
  return NodeStore{
    nodes: Vec[BTreeNode].new(), dirty: dirty, births: births, live: live,
    pending_free: Vec[Int].new(), pending_epoch: Vec[Int].new(),
    pins: Vec[DBSnapshot].new(), pin_clock: 0, compaction_deferred: 0,
    paged: true, bs: bs, write_gen: bs.header.committed_generation + 1,
    count: count, slots: slots, frames: frames, frame_ids: frame_ids,
    frame_dirty: frame_dirty, frame_ref: frame_ref, hand: 0,
    capacity: capacity, stats: ns_empty_stats(),
  };
}

pub fn ns_len(store: &NodeStore) -> Int {
  return store.count;
}

pub fn ns_pager_stats(store: &NodeStore) -> Vec[Int] {
  return store.stats;
}

pub fn ns_is_dirty(store: &NodeStore, idx: Int) -> Bool {
  return store.dirty[idx];
}

pub fn ns_pager_resident(store: &NodeStore, idx: Int) -> Bool {
  if !store.paged { return true; }
  if idx < 0 { return false; }
  if idx >= store.count { return false; }
  return store.slots[idx] >= 0;
}

// Reserve a cache frame and install `node`. Free frames first; otherwise a
// clock sweep skipping referenced frames. A dirty victim spills at the
// uncommitted write generation (own-writes-visible; a reopen ignores it);
// a failed spill skips that victim and is counted. Returns false when every
// frame stayed unreleasable -- the caller then serves/keeps the node without
// caching (reads) or grows the cache (writes).
fn ns_place(store: &NodeStore, id: Int, node: BTreeNode) -> Bool {
  var f = -1;
  var i = 0;
  while i < store.capacity {
    if store.frame_ids[i] < 0 {
      f = i;
      i = store.capacity;
    } else {
      i = i + 1;
    }
  }
  if f < 0 {
    var steps = 0;
    var done = false;
    while steps < 2 * store.capacity && !done {
      let c = store.hand;
      store.hand = (c + 1) % store.capacity;
      if store.frame_ref[c] {
        store.frame_ref[c] = false;
      } else {
        var spill_ok = true;
        if store.frame_dirty[c] {
          let victim_id = store.frame_ids[c];
          let bytes = node_page_bytes(&store.frames[c]);
          let at = block_store_put(&mut store.bs, store.write_gen, victim_id, &bytes);
          if at < 0 {
            store.stats[5] = store.stats[5] + 1;
            spill_ok = false;
          } else {
            store.stats[3] = store.stats[3] + 1;
          }
        }
        if spill_ok {
          f = c;
          done = true;
        }
      }
      steps = steps + 1;
    }
  }
  if f < 0 { return false; }
  // The reused frame may still be indexed by its previous node id; clear that
  // slot or the old id would resolve to the new node (and vice versa).
  if store.frame_ids[f] >= 0 {
    store.slots[store.frame_ids[f]] = -1;
  }
  store.frames[f] = node;
  store.frame_ids[f] = id;
  store.frame_dirty[f] = store.dirty[id];
  store.frame_ref[f] = true;
  store.slots[id] = f;
  store.stats[2] = store.stats[2] + 1;
  return true;
}

// Pathological fallback (IO failure / all frames unplaceable): grow the
// cache by one so a write is never lost. Healthy workloads never take this.
fn ns_force_place(store: &NodeStore, id: Int, node: BTreeNode) {
  store.frames.push(node);
  store.frame_ids.push(id);
  store.frame_dirty.push(store.dirty[id]);
  store.frame_ref.push(true);
  store.capacity = store.capacity + 1;
  store.slots[id] = store.capacity - 1;
  store.stats[2] = store.stats[2] + 1;
}

// Read a node copy. Paged mode loads on miss; a corrupt/missing page counts
// and yields an empty leaf (the checkpoint refuses to write a corrupt store).
pub fn ns_get(store: &NodeStore, idx: Int) -> BTreeNode {
  if !store.paged {
    return store.nodes[idx];
  }
  if idx < 0 || idx >= store.count {
    store.stats[4] = store.stats[4] + 1;
    return new_leaf_node();
  }
  let f = store.slots[idx];
  if f >= 0 {
    store.frame_ref[f] = true;
    store.stats[0] = store.stats[0] + 1;
    return store.frames[f];
  }
  store.stats[1] = store.stats[1] + 1;
  match block_store_read(&store.bs, idx) {
    Some(p) => {
      match node_page_decode(&p.payload) {
        Some(nd) => {
          if ns_place(store, idx, nd) {
            return store.frames[store.slots[idx]];
          }
          return nd;
        }
        None => {
          store.stats[4] = store.stats[4] + 1;
          return new_leaf_node();
        }
      }
    }
    None => {
      store.stats[4] = store.stats[4] + 1;
      return new_leaf_node();
    }
  }
}

// Overwrite a node in place and mark it dirty. M3 discipline: the target MUST
// be writable for the current pin state -- i.e. it was produced by `ns_push`
// (which stamps `pin_clock + 1`) or by `cow_shadow` in the same operation.
pub fn ns_set(store: &mut NodeStore, idx: Int, node: BTreeNode) {
  if store.paged {
    var f = store.slots[idx];
    if f < 0 {
      if ns_place(store, idx, node) {
        f = store.slots[idx];
      } else {
        ns_force_place(store, idx, node);
        f = store.slots[idx];
      }
    }
    store.frames[f] = node;
    store.frame_dirty[f] = true;
    store.frame_ref[f] = true;
    store.dirty[idx] = true;
    return;
  }
  store.nodes[idx] = node;
  store.dirty[idx] = true;
}

// Append a node (new nodes start dirty); returns its index. The birth epoch
// `pin_clock + 1` marks it mutable until a newer pin exists (M3).
pub fn ns_push(store: &mut NodeStore, node: BTreeNode) -> Int {
  let id = store.count;
  store.count = store.count + 1;
  store.dirty.push(true);
  store.births.push(store.pin_clock + 1);
  store.live.push(true);
  if store.paged {
    store.slots.push(-1);
    if !ns_place(store, id, node) {
      ns_force_place(store, id, node);
    }
  } else {
    store.nodes.push(node);
  }
  return id;
}

// M1.1b deferred free. A retired id is no longer referenced by the LIVE tree
// (COW shadow replaced it, a split_root/merge_children abandoned it). It may
// still be reachable from a pin, so compaction only drops it once every pin
// with `pin_epoch <= pending_epoch` has ended. `live=false` immediately keeps
// dead nodes out of flushes; the id is never reused (no ABA).
pub fn ns_retire(store: &mut NodeStore, idx: Int) {
  if idx < 0 { return; }
  if idx >= store.count { return; }
  if !store.live[idx] { return; }
  store.live[idx] = false;
  // Do NOT clear dirty: a conservatively retired id may still be reachable;
  // flushing it keeps its page valid until the reachability-based GC runs.
  store.pending_free.push(idx);
  store.pending_epoch.push(store.pin_clock);
}

// Drop pending entries that no live pin can reference. Released ids stay
// `live=false`; their pages are reclaimed by the next GC compaction.
pub fn ns_release_pending(store: &mut NodeStore) {
  if store.pending_free.len() == 0 { return; }
  var min_ep = store.pin_clock + 1;
  var p = 0;
  while p < store.pins.len() {
    if store.pins[p].pin_epoch < min_ep { min_ep = store.pins[p].pin_epoch; }
    p = p + 1;
  }
  var kept_free = Vec[Int].new();
  var kept_ep = Vec[Int].new();
  var i = 0;
  while i < store.pending_free.len() {
    let ep = store.pending_epoch[i];
    if store.pins.len() > 0 && ep >= min_ep {
      kept_free.push(store.pending_free[i]);
      kept_ep.push(ep);
    }
    i = i + 1;
  }
  store.pending_free = kept_free;
  store.pending_epoch = kept_ep;
}

pub fn ns_live_count(store: &NodeStore) -> Int {
  var n = 0;
  var i = 0;
  while i < store.count {
    if store.live[i] { n = n + 1; }
    i = i + 1;
  }
  return n;
}

pub fn ns_pending_count(store: &NodeStore) -> Int {
  return store.pending_free.len();
}

pub fn ns_reset_paged(store: &mut NodeStore, bs: BlockStore, count: Int) {
  store.bs = bs;
  store.count = count;
  store.write_gen = bs.header.committed_generation + 1;
  var slots = Vec[Int].new();
  var dirty = Vec[Bool].new();
  var births = Vec[Int].new();
  var live = Vec[Bool].new();
  var i = 0;
  while i < count {
    slots.push(-1);
    dirty.push(false);
    births.push(0);
    live.push(true);
    i = i + 1;
  }
  store.slots = slots;
  store.dirty = dirty;
  store.births = births;
  store.live = live;
  store.pending_free = Vec[Int].new();
  store.pending_epoch = Vec[Int].new();
  var f = 0;
  while f < store.capacity {
    store.frames[f] = new_leaf_node();
    store.frame_ids[f] = -1;
    store.frame_dirty[f] = false;
    store.frame_ref[f] = false;
    f = f + 1;
  }
  store.hand = 0;
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
  if idx >= tree.store.count { return idx; }
  if tree.store.births[idx] > tree.store.pin_clock { return idx; }
  let base = ns_get(&tree.store, idx);
  let copy = node_deep_copy(&base);
  let shadow_idx = ns_push(&mut tree.store, copy);
  ns_retire(&mut tree.store, idx);
  return shadow_idx;
}

// Mark every node clean after a successful snapshot commit (or after a load).
pub fn ns_mark_clean(store: &mut NodeStore) {
  var i = 0;
  while i < store.count {
    store.dirty[i] = false;
    i = i + 1;
  }
  if store.paged {
    var f = 0;
    while f < store.capacity {
      store.frame_dirty[f] = false;
      store.frame_ref[f] = false;
      f = f + 1;
    }
    store.write_gen = store.bs.header.committed_generation + 1;
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
// yields the empty payload (plain int entry). Public for the snapshot codec
// and typed-row readers in sibling modules (R1 split).
pub fn node_payload(node: &BTreeNode, i: Int) -> Vec[Int] {
  if i < node.payloads.len() { return node.payloads[i]; }
  return Vec[Int].new();
}

pub fn btree_new(order: Int) -> BTree
  requires: order >= 3
{
  var nodes = Vec[BTreeNode].new();
  var dirty = Vec[Bool].new();
  var births = Vec[Int].new();
  var store = ns_new_resident(nodes, dirty, births);
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

pub fn search_payload_node(tree: &BTree, node_idx: Int, key: Int) -> Option[Vec[Int]] {
  var node = ns_get(&tree.store, node_idx);
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

pub fn search_node(tree: &BTree, node_idx: Int, key: Int) -> Option[Int] {
  var node = ns_get(&tree.store, node_idx);
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
  if ns_get(&tree.store, tree.root).keys.len() >= max_keys {
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
  let old_root_idx = tree.root;
  var old_root = ns_get(&tree.store, tree.root);
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
  ns_retire(&mut tree.store, old_root_idx);
}

fn insert_nonfull(tree: &mut BTree, node_idx: Int, key: Int, value: Int,
                  payload: Vec[Int]) -> Bool {
  var node = ns_get(&tree.store, node_idx);
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
    if ns_get(&tree.store, child_idx).keys.len() >= max_keys {
      split_child(tree, node_idx, pos);
      var up_node = ns_get(&tree.store, node_idx);
      if pos < up_node.keys.len() && up_node.keys[pos] < key {
        pos = pos + 1;
      }
    }
    var new_child_idx = ns_get(&tree.store, node_idx).children[pos];
    // M3: the descended child will be mutated; make it writable first and
    // persist the shadowed index into this (already writable) parent.
    var shadowed_child = cow_shadow(tree, new_child_idx);
    if shadowed_child != new_child_idx {
      var parent = ns_get(&tree.store, node_idx);
      parent.children[pos] = shadowed_child;
      ns_set(&mut tree.store, node_idx, parent);
      new_child_idx = shadowed_child;
    }
    return insert_nonfull(tree, new_child_idx, key, value, payload);
  }
  return false;
}

fn split_child(tree: &mut BTree, parent_idx: Int, child_pos: Int) {
  var child_idx = ns_get(&tree.store, parent_idx).children[child_pos];
  // M3: the child is truncated and re-written below; shadow it first and fix
  // the (already writable) parent so both halves are fresh.
  var shadowed_child = cow_shadow(tree, child_idx);
  if shadowed_child != child_idx {
    var p = ns_get(&tree.store, parent_idx);
    p.children[child_pos] = shadowed_child;
    ns_set(&mut tree.store, parent_idx, p);
    child_idx = shadowed_child;
  }
  var child = ns_get(&tree.store, child_idx);
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
  var parent = ns_get(&tree.store, parent_idx);
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
  var node = ns_get(&tree.store, node_idx);
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
  var node = ns_get(&tree.store, node_idx);
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

  if ns_get(&tree.store, child_idx).keys.len() <= min_keys {
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
      var parent = ns_get(&tree.store, node_idx);
      parent.children[idx] = shadowed_child;
      ns_set(&mut tree.store, node_idx, parent);
      child_idx = shadowed_child;
    }
  }

  return delete_from_node(tree, child_idx, key);
}

fn remove_from_leaf(tree: &mut BTree, node_idx: Int, pos: Int) {
  var node = ns_get(&tree.store, node_idx);
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
  var node = ns_get(&tree.store, node_idx);
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
  if ns_get(&tree.store, left_child_idx).keys.len() > min_keys {
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

  if ns_get(&tree.store, right_child_idx).keys.len() > min_keys {
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
  let node = ns_get(&tree.store, node_idx);
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
    let node = ns_get(&tree.store, cur);
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
    let node = ns_get(&tree.store, cur);
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
  var parent = ns_get(&tree.store, parent_idx);
  var left_idx = parent.children[pos];
  var shadowed_left = cow_shadow(tree, left_idx);
  if shadowed_left != left_idx {
    parent.children[pos] = shadowed_left;
    left_idx = shadowed_left;
  }
  var right_idx = parent.children[pos + 1];

  var left = ns_get(&tree.store, left_idx);
  var right = ns_get(&tree.store, right_idx);

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

  // The right child is folded into the left; the old root (when it collapses)
  // is abandoned too. Both may still be visible to pins until release.
  ns_retire(&mut tree.store, right_idx);

  if parent.keys.len() == 0 && parent_idx == tree.root {
    tree.root = left_idx;
    ns_retire(&mut tree.store, parent_idx);
  }
  return left_idx;
}

fn fill_child(tree: &mut BTree, parent_idx: Int, child_pos: Int, min_keys: Int) -> Int {
  var parent = ns_get(&tree.store, parent_idx);

  // A keyless parent is a pass-through node (only possible when min_keys ==
  // 0, i.e. order 3): there is no sibling arrangement to borrow from and no
  // key to merge down; merging would read `children[pos + 1]` past the end.
  // Descending straight through is correct -- the child keeps its own count.
  // M3: the pass-through child is descended into, so it must be writable.
  if parent.keys.len() == 0 {
    var through_idx = parent.children[child_pos];
    var shadowed_through = cow_shadow(tree, through_idx);
    if shadowed_through != through_idx {
      var pp = ns_get(&tree.store, parent_idx);
      pp.children[child_pos] = shadowed_through;
      ns_set(&mut tree.store, parent_idx, pp);
      through_idx = shadowed_through;
    }
    return through_idx;
  }

  if child_pos > 0 {
    var left_sib_idx = parent.children[child_pos - 1];
    if ns_get(&tree.store, left_sib_idx).keys.len() > min_keys {
      borrow_from_left(tree, parent_idx, child_pos);
      return ns_get(&tree.store, parent_idx).children[child_pos];
    }
  }

  if child_pos < parent.children.len() - 1 {
    var right_sib_idx = parent.children[child_pos + 1];
    if ns_get(&tree.store, right_sib_idx).keys.len() > min_keys {
      borrow_from_right(tree, parent_idx, child_pos);
      return ns_get(&tree.store, parent_idx).children[child_pos];
    }
  }

  if child_pos > 0 {
    let _ = merge_children(tree, parent_idx, child_pos - 1);
    return ns_get(&tree.store, parent_idx).children[child_pos - 1];
  }
  let _ = merge_children(tree, parent_idx, child_pos);
  return ns_get(&tree.store, parent_idx).children[child_pos];
}

fn borrow_from_left(tree: &mut BTree, parent_idx: Int, child_pos: Int) {
  var parent = ns_get(&tree.store, parent_idx);
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
  var child = ns_get(&tree.store, child_idx);
  var left = ns_get(&tree.store, left_idx);
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
  var parent = ns_get(&tree.store, parent_idx);
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
  var child = ns_get(&tree.store, child_idx);
  var right = ns_get(&tree.store, right_idx);

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

pub fn collect_range(tree: &BTree, node_idx: Int, low: Int, high: Int, results: &mut Vec[Int]) {
  var node = ns_get(&tree.store, node_idx);
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

// Key/value pairs in [low, high], key order. The int-only range API returns
// values alone; the admin/Station range viewer needs the keys too.
pub fn btree_range_pairs(tree: &BTree, low: Int, high: Int) -> Vec[(Int, Int)] {
  var results = Vec[(Int, Int)].new();
  collect_range_pairs(tree, tree.root, low, high, results);
  return results;
}

pub fn collect_range_pairs(tree: &BTree, node_idx: Int, low: Int, high: Int,
                           results: &mut Vec[(Int, Int)]) {
  var node = ns_get(&tree.store, node_idx);
  if node.is_leaf {
    var i = 0;
    while i < node.keys.len() {
      if node.keys[i] >= low && node.keys[i] <= high {
        results.push((node.keys[i], node.values[i]));
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
    collect_range_pairs(tree, node.children[i], low, high, results);
  }
  while i < node.keys.len() && node.keys[i] <= high {
    results.push((node.keys[i], node.values[i]));
    i = i + 1;
    if i < node.children.len() {
      collect_range_pairs(tree, node.children[i], low, high, results);
    }
  }
}

pub fn btree_size(tree: &BTree) -> Int {
  return count_keys(tree, tree.root);
}

pub fn count_keys(tree: &BTree, node_idx: Int) -> Int {
  var node = ns_get(&tree.store, node_idx);
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
  var node = ns_get(&tree.store, node_idx);
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
