module xiom.db.engine

// ============================================================================
// XIOM-DB: Consolidated Engine — B-Tree + WAL + Query + Engine + Database API
// ============================================================================
// The single-file engine merges the interdependent modules (index/btree,
// wal/wal_record, wal/wal, query/query, query/planner, engine, api/database)
// so that single-file compilation resolves all cross-module references.

// ============================================================================
// B-TREE INDEX (from xiom.db.index.btree)
// ============================================================================

pub type BTree = {
  root: Int;
  order: Int;
  nodes: Vec[BTreeNode];
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
  var leaf = new_leaf_node();
  nodes.push(leaf);
  return BTree{ root: 0, order: order, nodes: nodes };
}

pub fn btree_search(tree: &BTree, key: Int) -> Option[Int] {
  return search_node(tree, tree.root, key);
}

fn search_node(tree: &BTree, node_idx: Int, key: Int) -> Option[Int] {
  var node = tree.nodes[node_idx];
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
  if tree.nodes[tree.root].keys.len() >= max_keys {
    split_root(tree);
  }
  return insert_nonfull(tree, tree.root, key, value);
}

fn split_root(tree: &mut BTree) {
  var old_root = tree.nodes[tree.root];
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

  var left_idx = tree.nodes.len();
  tree.nodes.push(left);
  var right_idx = tree.nodes.len();
  tree.nodes.push(right);

  new_root.keys.push(old_root.keys[mid]);
  new_root.values.push(old_root.values[mid]);
  new_root.children.push(left_idx);
  new_root.children.push(right_idx);

  var root_idx = tree.nodes.len();
  tree.nodes.push(new_root);
  tree.root = root_idx;
}

fn insert_nonfull(tree: &mut BTree, node_idx: Int, key: Int, value: Int) -> Bool {
  var node = tree.nodes[node_idx];
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
    if tree.nodes[child_idx].keys.len() >= max_keys {
      split_child(tree, node_idx, pos);
      var up_node = tree.nodes[node_idx];
      if pos < up_node.keys.len() && up_node.keys[pos] < key {
        pos = pos + 1;
      }
    }
    var new_child_idx = tree.nodes[node_idx].children[pos];
    return insert_nonfull(tree, new_child_idx, key, value);
  }
  return false;
}

fn split_child(tree: &mut BTree, parent_idx: Int, child_pos: Int) {
  var child_idx = tree.nodes[parent_idx].children[child_pos];
  var child = tree.nodes[child_idx];
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

  var new_child_idx = tree.nodes.len();
  tree.nodes.push(new_child);

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

  tree.nodes[child_idx] = child;
  tree.nodes[new_child_idx] = new_child;

  insert_at_pos(tree, parent_idx, child_pos, mid_key, mid_val);

  tree.nodes[parent_idx].children[child_pos + 1] = new_child_idx;
}

fn insert_at_pos(tree: &mut BTree, node_idx: Int, pos: Int, key: Int, value: Int) {
  var node = tree.nodes[node_idx];
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
  tree.nodes[node_idx] = node;
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
  var node = tree.nodes[node_idx];
  var min_keys = (tree.order + 1) / 2 - 1;

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

  if tree.nodes[child_idx].keys.len() <= min_keys {
    fill_child(tree, node_idx, idx, min_keys);
  }

  var new_idx = idx;
  if new_idx > tree.nodes[node_idx].keys.len() {
    new_idx = tree.nodes[node_idx].keys.len();
  }
  var clean_child_idx = tree.nodes[node_idx].children[new_idx];
  return delete_from_node(tree, clean_child_idx, key);
}

fn remove_from_leaf(tree: &mut BTree, node_idx: Int, pos: Int) {
  var node = tree.nodes[node_idx];
  var i = pos;
  while i < node.keys.len() - 1 {
    node.keys[i] = node.keys[i + 1];
    node.values[i] = node.values[i + 1];
    i = i + 1;
  }
  node.keys.pop();
  node.values.pop();
  tree.nodes[node_idx] = node;
}

fn remove_from_internal(tree: &mut BTree, node_idx: Int, pos: Int, min_keys: Int) {
  var node = tree.nodes[node_idx];
  var key = node.keys[pos];
  var left_child_idx = node.children[pos];
  var right_child_idx = node.children[pos + 1];

  if tree.nodes[left_child_idx].keys.len() > min_keys {
    var pred = get_predecessor(tree, left_child_idx);
    node.keys[pos] = pred.0;
    node.values[pos] = pred.1;
    tree.nodes[node_idx] = node;
    delete_from_node(tree, left_child_idx, pred.0);
    return;
  }

  if tree.nodes[right_child_idx].keys.len() > min_keys {
    var succ = get_successor(tree, right_child_idx);
    node.keys[pos] = succ.0;
    node.values[pos] = succ.1;
    tree.nodes[node_idx] = node;
    delete_from_node(tree, right_child_idx, succ.0);
    return;
  }

  merge_children(tree, node_idx, pos);
  delete_from_node(tree, left_child_idx, key);
}

fn get_predecessor(tree: &BTree, node_idx: Int) -> (Int, Int) {
  var node = tree.nodes[node_idx];
  if node.is_leaf {
    var last = node.keys.len() - 1;
    return (node.keys[last], node.values[last]);
  }
  var last_child = node.children[node.children.len() - 1];
  return get_predecessor(tree, last_child);
}

fn get_successor(tree: &BTree, node_idx: Int) -> (Int, Int) {
  var node = tree.nodes[node_idx];
  if node.is_leaf {
    return (node.keys[0], node.values[0]);
  }
  var first_child = node.children[0];
  return get_successor(tree, first_child);
}

fn merge_children(tree: &mut BTree, parent_idx: Int, pos: Int) {
  var parent = tree.nodes[parent_idx];
  var left_idx = parent.children[pos];
  var right_idx = parent.children[pos + 1];

  var left = tree.nodes[left_idx];
  var right = tree.nodes[right_idx];

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

  tree.nodes[left_idx] = left;

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

  tree.nodes[parent_idx] = parent;

  if parent.keys.len() == 0 && parent_idx == tree.root {
    tree.root = left_idx;
  }
}

fn fill_child(tree: &mut BTree, parent_idx: Int, child_pos: Int, min_keys: Int) {
  var parent = tree.nodes[parent_idx];

  if child_pos > 0 {
    var left_sib_idx = parent.children[child_pos - 1];
    if tree.nodes[left_sib_idx].keys.len() > min_keys {
      borrow_from_left(tree, parent_idx, child_pos);
      return;
    }
  }

  if child_pos < parent.children.len() - 1 {
    var right_sib_idx = parent.children[child_pos + 1];
    if tree.nodes[right_sib_idx].keys.len() > min_keys {
      borrow_from_right(tree, parent_idx, child_pos);
      return;
    }
  }

  if child_pos > 0 {
    merge_children(tree, parent_idx, child_pos - 1);
  } elif child_pos < parent.children.len() - 1 {
    merge_children(tree, parent_idx, child_pos);
  }
}

fn borrow_from_left(tree: &mut BTree, parent_idx: Int, child_pos: Int) {
  var parent = tree.nodes[parent_idx];
  var child_idx = parent.children[child_pos];
  var left_idx = parent.children[child_pos - 1];
  var child = tree.nodes[child_idx];
  var left = tree.nodes[left_idx];
  var left_last = left.keys.len() - 1;

  child.keys.push(0);
  child.values.push(0);
  child.children.push(0);

  var i = child.keys.len() - 1;
  while i > 0 {
    child.keys[i] = child.keys[i - 1];
    child.values[i] = child.values[i - 1];
    i = i - 1;
  }
  child.keys[0] = parent.keys[child_pos - 1];
  child.values[0] = parent.values[child_pos - 1];

  if left.children.len() > 0 {
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

  tree.nodes[parent_idx] = parent;
  tree.nodes[child_idx] = child;
  tree.nodes[left_idx] = left;
}

fn borrow_from_right(tree: &mut BTree, parent_idx: Int, child_pos: Int) {
  var parent = tree.nodes[parent_idx];
  var child_idx = parent.children[child_pos];
  var right_idx = parent.children[child_pos + 1];
  var child = tree.nodes[child_idx];
  var right = tree.nodes[right_idx];

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

  tree.nodes[parent_idx] = parent;
  tree.nodes[child_idx] = child;
  tree.nodes[right_idx] = right;
}

pub fn btree_range_query(tree: &BTree, low: Int, high: Int) -> Vec[Int]
  requires: low <= high
{
  var results = Vec[Int].new();
  collect_range(tree, tree.root, low, high, results);
  return results;
}

fn collect_range(tree: &BTree, node_idx: Int, low: Int, high: Int, results: &mut Vec[Int]) {
  var node = tree.nodes[node_idx];
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
  var node = tree.nodes[node_idx];
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
  var node_idx = tree.root;
  var node = tree.nodes[node_idx];
  while !node.is_leaf {
    if node.children.len() == 0 { return None; }
    node_idx = node.children[0];
    node = tree.nodes[node_idx];
  }
  if node.keys.len() == 0 { return None; }
  return Some(node.values[0]);
}

pub fn btree_max(tree: &BTree) -> Option[Int] {
  var node_idx = tree.root;
  var node = tree.nodes[node_idx];
  while !node.is_leaf {
    if node.children.len() == 0 { return None; }
    node_idx = node.children[node.children.len() - 1];
    node = tree.nodes[node_idx];
  }
  if node.keys.len() == 0 { return None; }
  return Some(node.values[node.keys.len() - 1]);
}

pub fn btree_to_vec(tree: &BTree) -> Vec[Int] {
  var results = Vec[Int].new();
  traverse_inorder(tree, tree.root, results);
  return results;
}

fn traverse_inorder(tree: &BTree, node_idx: Int, results: &mut Vec[Int]) {
  var node = tree.nodes[node_idx];
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
}

pub fn query_new() -> Query {
  var conditions = Vec[QueryCondition].new();
  return Query{ conditions: conditions, limit: 0, offset: 0 };
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
  var results = Vec[Int].new();

  var start_idx = q.offset;
  var count = 0;

  var i = 0;
  while i < all_values.len() {
    if matches_all_conditions(all_values[i], q.conditions) {
      if count >= start_idx {
        results.push(all_values[i]);
      }
      count = count + 1;
    }
    i = i + 1;
  }

  if q.limit > 0 && results.len() > q.limit {
    var limited = Vec[Int].new();
    var j = 0;
    while j < q.limit {
      limited.push(results[j]);
      j = j + 1;
    }
    return limited;
  }
  return results;
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

pub fn query_reset(q: &mut Query) {
  var empty = Vec[QueryCondition].new();
  q.conditions = empty;
  q.limit = 0;
  q.offset = 0;
}

// ============================================================================
// QUERY PLANNER (from xiom.db.query.planner)
// ============================================================================

pub enum PlanKind {
  FullScan,
  IndexRange,
  PointLookup,
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

pub fn plan_query(q: &Query, tree: &BTree) -> QueryPlan {
  var plan = query_plan_full_scan();
  plan.estimated_rows = btree_size(tree);
  return plan;
}

pub fn execute_plan(plan: &QueryPlan, q: &Query, tree: &BTree) -> Vec[Int] {
  match plan.kind {
    FullScan => query_execute(q, tree)
    IndexRange => {
      query_execute(q, tree)
    }
    PointLookup => {
      query_execute(q, tree)
    }
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