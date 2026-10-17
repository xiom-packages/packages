// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom.btree

// ============================================================================
// B-TREE INDEX (from xiom.db.index.btree)
// ============================================================================

// NodeStore: the node arena behind a B-tree. `dirty[i]` marks node i as
// changed since the last successful snapshot flush; checkpoints encode only
// dirty nodes (M1.1). The store is fully resident for now -- lazy load and a
// bounded cache arrive in the next slice of the storage spine.
pub type NodeStore = {
  nodes: Vec[BTreeNode];
  dirty: Vec[Bool];
}

pub fn ns_len(store: &NodeStore) -> Int {
  return store.nodes.len();
}

// Read a node copy.
pub fn ns_get(store: &NodeStore, idx: Int) -> BTreeNode {
  return store.nodes[idx];
}

// Overwrite a node in place and mark it dirty.
pub fn ns_set(store: &mut NodeStore, idx: Int, node: BTreeNode) {
  store.nodes[idx] = node;
  store.dirty[idx] = true;
}

// Append a node (new nodes start dirty); returns its index.
pub fn ns_push(store: &mut NodeStore, node: BTreeNode) -> Int {
  store.nodes.push(node);
  store.dirty.push(true);
  return store.nodes.len() - 1;
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
  children: Vec[Int];
  is_leaf: Bool;
}

fn new_leaf_node() -> BTreeNode {
  var keys = Vec[Int].new();
  var values = Vec[Int].new();
  var children = Vec[Int].new();
  return BTreeNode{ keys: keys, values: values, children: children, is_leaf: true };
}

fn new_internal_node() -> BTreeNode {
  var keys = Vec[Int].new();
  var values = Vec[Int].new();
  var children = Vec[Int].new();
  return BTreeNode{ keys: keys, values: values, children: children, is_leaf: false };
}

pub fn btree_new(order: Int) -> BTree
  requires: order >= 3
{
  var nodes = Vec[BTreeNode].new();
  var dirty = Vec[Bool].new();
  var store = NodeStore{ nodes: nodes, dirty: dirty };
  let leaf = new_leaf_node();
  // The initial leaf must be persisted by the first checkpoint.
  let _ = ns_push(&mut store, leaf);
  return BTree{ root: 0, order: order, store: store };
}

pub fn btree_search(tree: &BTree, key: Int) -> Option[Int] {
  return search_node(tree, tree.root, key);
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
  var found = btree_search(tree, key);
  match found {
    Some(_) => return false,
    None => {}
  }
  var max_keys = tree.order - 1;
  if tree.store.nodes[tree.root].keys.len() >= max_keys {
    split_root(tree);
  }
  return insert_nonfull(tree, tree.root, key, value);
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
  new_root.children.push(left_idx);
  new_root.children.push(right_idx);

  var root_idx = ns_push(&mut tree.store, new_root);
  tree.root = root_idx;
}

fn insert_nonfull(tree: &mut BTree, node_idx: Int, key: Int, value: Int) -> Bool {
  var node = tree.store.nodes[node_idx];
  var max_keys = tree.order - 1;

  if node.is_leaf {
    var pos = 0;
    while pos < node.keys.len() && node.keys[pos] < key {
      pos = pos + 1;
    }
    insert_at_pos(tree, node_idx, pos, key, value);
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
    return insert_nonfull(tree, new_child_idx, key, value);
  }
  return false;
}

fn split_child(tree: &mut BTree, parent_idx: Int, child_pos: Int) {
  var child_idx = tree.store.nodes[parent_idx].children[child_pos];
  var child = tree.store.nodes[child_idx];
  var mid = child.keys.len() / 2;

  var new_child = new_leaf_node();
  if !child.is_leaf { new_child.is_leaf = false; }

  var i = mid + 1;
  while i < child.keys.len() {
    new_child.keys.push(child.keys[i]);
    new_child.values.push(child.values[i]);
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

  while child.keys.len() > mid {
    child.keys.pop();
    child.values.pop();
  }
  if !child.is_leaf {
    while child.children.len() > mid + 1 {
      child.children.pop();
    }
  }

  ns_set(&mut tree.store, child_idx, child);
  ns_set(&mut tree.store, new_child_idx, new_child);

  insert_at_pos(tree, parent_idx, child_pos, mid_key, mid_val);

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

fn insert_at_pos(tree: &mut BTree, node_idx: Int, pos: Int, key: Int, value: Int) {
  var node = tree.store.nodes[node_idx];
  node.keys.push(0);
  node.values.push(0);
  var i = node.keys.len() - 1;
  while i > pos {
    node.keys[i] = node.keys[i - 1];
    node.values[i] = node.values[i - 1];
    i = i - 1;
  }
  node.keys[pos] = key;
  node.values[pos] = value;
  ns_set(&mut tree.store, node_idx, node);
}

pub fn btree_delete(tree: &mut BTree, key: Int) -> Bool {
  var found = btree_search(tree, key);
  match found {
    None => return false,
    Some(_) => {}
  }
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
    child_idx = fill_child(tree, node_idx, idx, min_keys);
  }

  return delete_from_node(tree, child_idx, key);
}

fn remove_from_leaf(tree: &mut BTree, node_idx: Int, pos: Int) {
  var node = tree.store.nodes[node_idx];
  var i = pos;
  while i < node.keys.len() - 1 {
    node.keys[i] = node.keys[i + 1];
    node.values[i] = node.values[i + 1];
    i = i + 1;
  }
  node.keys.pop();
  node.values.pop();
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
  // donate.
  if tree.store.nodes[left_child_idx].keys.len() > min_keys {
    match get_predecessor(tree, left_child_idx) {
      Some(pred) => {
        node.keys[pos] = pred.0;
        node.values[pos] = pred.1;
        ns_set(&mut tree.store, node_idx, node);
        delete_from_node(tree, left_child_idx, pred.0);
        return;
      }
      None => {}
    }
  }

  if tree.store.nodes[right_child_idx].keys.len() > min_keys {
    match get_successor(tree, right_child_idx) {
      Some(succ) => {
        node.keys[pos] = succ.0;
        node.values[pos] = succ.1;
        ns_set(&mut tree.store, node_idx, node);
        delete_from_node(tree, right_child_idx, succ.0);
        return;
      }
      None => {}
    }
  }

  // Both donors are at the floor: merge the two children around the
  // separator. Safe here because this node holds at least the separator key
  // (the caller only reaches this with a key at `pos`).
  merge_children(tree, node_idx, pos);
  delete_from_node(tree, left_child_idx, key);
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

// In-order predecessor (max) of the subtree at node_idx, or None when the
// subtree is empty. The rightmost path may pass through keyless nodes: when
// the rightmost subtree is empty the predecessor is this node's own last
// key; an empty leaf has none. (The old rightmost-only descent read
// `keys[-1]` on an empty leaf and materialized out-of-bounds garbage -- the
// order-3 defect in xiom.btree SPEC 2.3.)
fn get_predecessor(tree: &BTree, node_idx: Int) -> Option[(Int, Int)] {
  var cur = node_idx;
  var guard = 0;
  while guard < 64 {
    guard = guard + 1;
    let node = tree.store.nodes[cur];
    if node.is_leaf {
      if node.keys.len() == 0 { return None; }
      let last = node.keys.len() - 1;
      return Some((node.keys[last], node.values[last]));
    }
    let last_child = node.children[node.children.len() - 1];
    if subtree_has_key(tree, last_child) {
      cur = last_child;
    } else {
      if node.keys.len() == 0 { return None; }
      let last = node.keys.len() - 1;
      return Some((node.keys[last], node.values[last]));
    }
  }
  return None;
}

fn get_successor(tree: &BTree, node_idx: Int) -> Option[(Int, Int)] {
  var cur = node_idx;
  var guard = 0;
  while guard < 64 {
    guard = guard + 1;
    let node = tree.store.nodes[cur];
    if node.is_leaf {
      if node.keys.len() == 0 { return None; }
      return Some((node.keys[0], node.values[0]));
    }
    let first_child = node.children[0];
    if subtree_has_key(tree, first_child) {
      cur = first_child;
    } else {
      if node.keys.len() == 0 { return None; }
      return Some((node.keys[0], node.values[0]));
    }
  }
  return None;
}

fn merge_children(tree: &mut BTree, parent_idx: Int, pos: Int) {
  var parent = tree.store.nodes[parent_idx];
  var left_idx = parent.children[pos];
  var right_idx = parent.children[pos + 1];

  var left = tree.store.nodes[left_idx];
  var right = tree.store.nodes[right_idx];

  left.keys.push(parent.keys[pos]);
  left.values.push(parent.values[pos]);

  var i = 0;
  while i < right.keys.len() {
    left.keys.push(right.keys[i]);
    left.values.push(right.values[i]);
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
    i = i + 1;
  }
  parent.keys.pop();
  parent.values.pop();

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
}

fn fill_child(tree: &mut BTree, parent_idx: Int, child_pos: Int, min_keys: Int) -> Int {
  var parent = tree.store.nodes[parent_idx];

  // A keyless parent is a pass-through node (only possible when min_keys ==
  // 0, i.e. order 3): there is no sibling arrangement to borrow from and no
  // key to merge down; merging would read `children[pos + 1]` past the end.
  // Descending straight through is correct -- the child keeps its own count.
  if parent.keys.len() == 0 {
    return parent.children[child_pos];
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
    merge_children(tree, parent_idx, child_pos - 1);
    return tree.store.nodes[parent_idx].children[child_pos - 1];
  }
  merge_children(tree, parent_idx, child_pos);
  return tree.store.nodes[parent_idx].children[child_pos];
}

fn borrow_from_left(tree: &mut BTree, parent_idx: Int, child_pos: Int) {
  var parent = tree.store.nodes[parent_idx];
  var child_idx = parent.children[child_pos];
  var left_idx = parent.children[child_pos - 1];
  var child = tree.store.nodes[child_idx];
  var left = tree.store.nodes[left_idx];
  var left_last = left.keys.len() - 1;

  child.keys.push(0);
  child.values.push(0);

  var i = child.keys.len() - 1;
  while i > 0 {
    child.keys[i] = child.keys[i - 1];
    child.values[i] = child.values[i - 1];
    i = i - 1;
  }
  child.keys[0] = parent.keys[child_pos - 1];
  child.values[0] = parent.values[child_pos - 1];

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
  left.keys.pop();
  left.values.pop();

  ns_set(&mut tree.store, parent_idx, parent);
  ns_set(&mut tree.store, child_idx, child);
  ns_set(&mut tree.store, left_idx, left);
}

fn borrow_from_right(tree: &mut BTree, parent_idx: Int, child_pos: Int) {
  var parent = tree.store.nodes[parent_idx];
  var child_idx = parent.children[child_pos];
  var right_idx = parent.children[child_pos + 1];
  var child = tree.store.nodes[child_idx];
  var right = tree.store.nodes[right_idx];

  child.keys.push(parent.keys[child_pos]);
  child.values.push(parent.values[child_pos]);

  if right.children.len() > 0 {
    child.children.push(right.children[0]);
  }

  parent.keys[child_pos] = right.keys[0];
  parent.values[child_pos] = right.values[0];

  var i = 0;
  while i < right.keys.len() - 1 {
    right.keys[i] = right.keys[i + 1];
    right.values[i] = right.values[i + 1];
    i = i + 1;
  }
  right.keys.pop();
  right.values.pop();

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
    Some(p) => { return Some(p.1); }
    None => { return None; }
  }
}

pub fn btree_max(tree: &BTree) -> Option[Int] {
  // See btree_min: the rightmost path can end in an empty node (order 3);
  // get_predecessor falls back to the owning internal node's last key.
  match get_predecessor(tree, tree.root) {
    Some(p) => { return Some(p.1); }
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
