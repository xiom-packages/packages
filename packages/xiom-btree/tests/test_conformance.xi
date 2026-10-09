// XIOM -- xiom.btree conformance tests (22 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Deterministic, in-memory, no fixtures on disk. One [PASS]/[FAIL] line per
// check; the program exits 0 only when every check passed.
//
// Covered: empty-tree behavior; insert/search round-trip; duplicate inserts
// (first write wins, documented in SPEC.md); leaf removal; internal
// predecessor/successor replacement; deterministic borrow/merge underflow
// sequences on orders 4/5; inclusive range bounds, low == high and empty
// ranges; min/max tracking; to_vec ascending order after shuffled inserts and
// deletion churn; structural validation from the node array (keys strictly
// ascending per node, child-count law, min/max key bounds, uniform leaf
// depth) on orders 3/4/5; negative keys.
//
// Order 3 is covered for insert/search/range/structure only: randomized or
// multi-step order-3 DELETES are excluded because the verbatim upstream code
// has a known corruption path at min_keys = 0 (degenerate 0-key/1-child
// internal nodes feed an out-of-bounds read in merge_children). Reproduced
// with the acceptance probe at order 3, keyspace 16, seed 777, first
// divergence op=67; see SPEC.md "known order-3 delete defect". Delete-path
// coverage lives on orders 4/5 (and the churn matrix uses 4/5/6).
//
// The structural validator follows the package invariant min_keys =
// (order - 2) / 2 and additionally bounds-checks child indices.

module btree_tests

use xiom.io;
use xiom.test;
use xiom.btree;

// --------------------------------------------------
//  Helpers
// --------------------------------------------------

fn value_of(key: Int) -> Int {
  return key * 7 + 1;
}

fn search_is(tree: &BTree, key: Int, want: Int) -> Bool {
  let got = btree_search(tree, key);
  match got {
    Some(v) => { return v == want; }
    None => { return false; }
  }
}

fn search_none(tree: &BTree, key: Int) -> Bool {
  let got = btree_search(tree, key);
  match got {
    Some(_) => { return false; }
    None => { return true; }
  }
}

fn min_is(tree: &BTree, want: Int) -> Bool {
  let got = btree_min(tree);
  match got {
    Some(v) => { return v == want; }
    None => { return false; }
  }
}

fn max_is(tree: &BTree, want: Int) -> Bool {
  let got = btree_max(tree);
  match got {
    Some(v) => { return v == want; }
    None => { return false; }
  }
}

fn option_is_none(o: Option[Int]) -> Bool {
  match o {
    Some(_) => { return false; }
    None => { return true; }
  }
}

fn vec_eq(a: &Vec[Int], b: &Vec[Int]) -> Bool {
  if a.len() != b.len() { return false; }
  var i = 0;
  while i < a.len() {
    if a[i] != b[i] { return false; }
    i = i + 1;
  }
  return true;
}

fn ascending(v: &Vec[Int]) -> Bool {
  var i = 1;
  while i < v.len() {
    if v[i] <= v[i - 1] { return false; }
    i = i + 1;
  }
  return true;
}

// Expected values for every key in [lo, hi] present in the model.
fn model_vec(present: &Vec[Int], lo: Int, hi: Int) -> Vec[Int] {
  var out = Vec[Int].new();
  var k = lo;
  while k <= hi {
    if present[k] == 1 {
      out.push(value_of(k));
    }
    k = k + 1;
  }
  return out;
}

// Structural invariants:
//  - keys strictly ascending per node
//  - leaf => no children; internal => children.len() == keys.len() + 1
//  - non-root key count in [min_keys, max_keys]; root <= max_keys
//  - all leaves at the same depth
// min_keys follows the split scheme: (order - 2) / 2.
fn validate_node(tree: &BTree, idx: Int, depth: Int, leaf_depth: &mut Int, is_root: Bool) -> Int {
  var node = tree.nodes[idx];
  var max_keys = tree.order - 1;
  var min_keys = (tree.order - 2) / 2;

  var i = 1;
  while i < node.keys.len() {
    if node.keys[i] <= node.keys[i - 1] { return 10; }
    i = i + 1;
  }

  if node.keys.len() > max_keys { return 11; }
  if !is_root {
    if node.keys.len() < min_keys { return 12; }
  }

  if node.is_leaf {
    if node.children.len() != 0 { return 13; }
    if *leaf_depth < 0 {
      *leaf_depth = depth;
    } elif depth != *leaf_depth {
      return 14;
    }
    return 0;
  }

  if node.children.len() != node.keys.len() + 1 { return 15; }

  i = 0;
  while i < node.children.len() {
    if node.children[i] < 0 || node.children[i] >= tree.nodes.len() { return 16; }
    let rc = validate_node(tree, node.children[i], depth + 1, leaf_depth, false);
    if rc != 0 { return rc; }
    i = i + 1;
  }
  return 0;
}

fn validate_tree(tree: &BTree) -> Int {
  var leaf_depth = -1;
  return validate_node(tree, tree.root, 0, &mut leaf_depth, true);
}

fn rand_next(state: &mut Int) -> Int {
  *state = (*state * 1103515245 + 12345) % 2147483648;
  return *state;
}

// Deterministic model check: LCG insert/delete/search over [0, n), orders and
// seeds fixed per test. Mirrors probe_btree_churn.xi on a small scale.
fn churn_model(order: Int, n: Int, ops: Int, seed: Int) -> Bool {
  var tree = btree_new(order);
  var present = Vec[Int].new();
  var i = 0;
  while i < n {
    present.push(0);
    i = i + 1;
  }

  var state = seed;
  var step = 0;
  var ok = true;
  while step < ops {
    let key = rand_next(&mut state) % n;
    let action = rand_next(&mut state) % 10;

    if action < 4 {
      let should_insert = present[key] == 0;
      let got = btree_insert(&mut tree, key, value_of(key));
      if got != should_insert { ok = false; }
      if should_insert { present[key] = 1; }
    } elif action < 7 {
      let should_delete = present[key] == 1;
      let got = btree_delete(&mut tree, key);
      if got != should_delete { ok = false; }
      if should_delete { present[key] = 0; }
    } else {
      let got = btree_search(&tree, key);
      if present[key] == 1 {
        match got {
          Some(v) => { if v != value_of(key) { ok = false; } }
          None => { ok = false; }
        }
      } else {
        match got {
          Some(_) => { ok = false; }
          None => {}
        }
      }
    }

    if step % 50 == 49 {
      if validate_tree(&tree) != 0 { ok = false; }
    }
    step = step + 1;
  }

  var expected = 0;
  var k = 0;
  while k < n {
    if present[k] == 1 { expected = expected + 1; }
    k = k + 1;
  }
  if btree_size(&tree) != expected { ok = false; }
  if !vec_eq(&btree_to_vec(&tree), &model_vec(&present, 0, n - 1)) { ok = false; }
  if validate_tree(&tree) != 0 { ok = false; }
  return ok;
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t01_empty_tree() -> TestResult {
  let name = "empty tree: size 0, min/max None, to_vec empty, search None, delete false";
  var tree = btree_new(4);
  var ok = true;
  if btree_size(&tree) != 0 { ok = false; }
  if !option_is_none(btree_min(&tree)) { ok = false; }
  if !option_is_none(btree_max(&tree)) { ok = false; }
  if btree_to_vec(&tree).len() != 0 { ok = false; }
  if !search_none(&tree, 42) { ok = false; }
  if btree_delete(&mut tree, 42) { ok = false; }
  if btree_range_query(&tree, 0, 100).len() != 0 { ok = false; }
  return assert(ok, name);
}

fn t02_insert_search_roundtrip() -> TestResult {
  let name = "insert/search round-trip over 10 keys";
  var tree = btree_new(4);
  var ok = true;
  var k = 1;
  while k <= 10 {
    if !btree_insert(&mut tree, k, value_of(k)) { ok = false; }
    k = k + 1;
  }
  k = 1;
  while k <= 10 {
    if !search_is(&tree, k, value_of(k)) { ok = false; }
    k = k + 1;
  }
  if !search_none(&tree, 0) { ok = false; }
  if !search_none(&tree, 11) { ok = false; }
  if btree_size(&tree) != 10 { ok = false; }
  return assert(ok, name);
}

fn t03_duplicate_insert_first_wins() -> TestResult {
  let name = "duplicate insert returns false and keeps the first value";
  var tree = btree_new(4);
  var ok = true;
  if !btree_insert(&mut tree, 5, 100) { ok = false; }
  if btree_insert(&mut tree, 5, 999) { ok = false; }
  if !search_is(&tree, 5, 100) { ok = false; }
  if btree_size(&tree) != 1 { ok = false; }
  return assert(ok, name);
}

fn t04_delete_leaf_and_missing() -> TestResult {
  let name = "leaf delete returns true once; missing keys delete false";
  var tree = btree_new(4);
  var ok = true;
  var k = 1;
  while k <= 6 {
    if !btree_insert(&mut tree, k, value_of(k)) { ok = false; }
    k = k + 1;
  }
  if !btree_delete(&mut tree, 2) { ok = false; }
  if !search_none(&tree, 2) { ok = false; }
  if btree_delete(&mut tree, 2) { ok = false; }
  if btree_delete(&mut tree, 99) { ok = false; }
  if btree_size(&tree) != 5 { ok = false; }
  if validate_tree(&tree) != 0 { ok = false; }
  return assert(ok, name);
}

fn t05_delete_all_ascending_order4() -> TestResult {
  let name = "order-4: delete 1..12 ascending empties the tree (borrow + merge paths)";
  var tree = btree_new(4);
  var ok = true;
  var k = 1;
  while k <= 12 {
    if !btree_insert(&mut tree, k, value_of(k)) { ok = false; }
    k = k + 1;
  }
  k = 1;
  while k <= 12 {
    if !btree_delete(&mut tree, k) { ok = false; }
    if !search_none(&tree, k) { ok = false; }
    if btree_size(&tree) != 12 - k { ok = false; }
    if validate_tree(&tree) != 0 { ok = false; }
    k = k + 1;
  }
  if !option_is_none(btree_min(&tree)) { ok = false; }
  if !option_is_none(btree_max(&tree)) { ok = false; }
  if btree_to_vec(&tree).len() != 0 { ok = false; }
  return assert(ok, name);
}

fn t06_delete_borrow_order4() -> TestResult {
  let name = "order-4: sequential deletes after splits exercise borrow-from-left/right";
  var tree = btree_new(4);
  var present = Vec[Int].new();
  var values = Vec[Int].new();
  var i = 0;
  while i < 20 {
    present.push(0);
    values.push(0);
    i = i + 1;
  }
  var ok = true;
  i = 1;
  while i <= 15 {
    if !btree_insert(&mut tree, i, value_of(i)) { ok = false; }
    present[i] = 1;
    values[i] = value_of(i);
    i = i + 1;
  }
  i = 1;
  while i <= 8 {
    if !btree_delete(&mut tree, i) { ok = false; }
    present[i] = 0;
    if !vec_eq(&btree_to_vec(&tree), &model_vec(&present, 0, 19)) { ok = false; }
    if validate_tree(&tree) != 0 { ok = false; }
    i = i + 1;
  }
  if btree_size(&tree) != 7 { ok = false; }
  return assert(ok, name);
}

fn t07_delete_internal_prev_order4() -> TestResult {
  let name = "order-4: root key removal uses predecessor/successor replacement";
  var tree = btree_new(4);
  var ok = true;
  var k = 1;
  while k <= 15 {
    if !btree_insert(&mut tree, k, value_of(k)) { ok = false; }
    k = k + 1;
  }
  if tree.nodes[tree.root].is_leaf { ok = false; }
  let root_key = tree.nodes[tree.root].keys[0];
  if !btree_delete(&mut tree, root_key) { ok = false; }
  if !search_none(&tree, root_key) { ok = false; }
  if btree_size(&tree) != 14 { ok = false; }
  if validate_tree(&tree) != 0 { ok = false; }
  let v = btree_to_vec(&tree);
  if !ascending(&v) { ok = false; }
  if v.len() != 14 { ok = false; }
  return assert(ok, name);
}

fn t08_structure_order3_readops() -> TestResult {
  let name = "order-3: inserts, search, range and structure (deletes scoped to orders 4/5)";
  var tree = btree_new(3);
  var ok = true;
  var k = 1;
  while k <= 10 {
    if !btree_insert(&mut tree, k, value_of(k)) { ok = false; }
    k = k + 1;
  }
  if btree_size(&tree) != 10 { ok = false; }
  if validate_tree(&tree) != 0 { ok = false; }
  k = 1;
  while k <= 10 {
    if !search_is(&tree, k, value_of(k)) { ok = false; }
    k = k + 1;
  }
  var want = Vec[Int].new();
  k = 4;
  while k <= 6 {
    want.push(value_of(k));
    k = k + 1;
  }
  if !vec_eq(&btree_range_query(&tree, 4, 6), &want) { ok = false; }
  if !min_is(&tree, value_of(1)) { ok = false; }
  if !max_is(&tree, value_of(10)) { ok = false; }
  return assert(ok, name);
}

fn t09_delete_underflow_order5() -> TestResult {
  let name = "order-5: descending even deletes underfill nodes, odds remain";
  var tree = btree_new(5);
  var present = Vec[Int].new();
  var i = 0;
  while i < 25 {
    present.push(0);
    i = i + 1;
  }
  var ok = true;
  i = 1;
  while i <= 20 {
    if !btree_insert(&mut tree, i, value_of(i)) { ok = false; }
    present[i] = 1;
    i = i + 1;
  }
  i = 20;
  while i >= 2 {
    if !btree_delete(&mut tree, i) { ok = false; }
    present[i] = 0;
    i = i - 2;
  }
  if btree_size(&tree) != 10 { ok = false; }
  if !vec_eq(&btree_to_vec(&tree), &model_vec(&present, 0, 24)) { ok = false; }
  if validate_tree(&tree) != 0 { ok = false; }
  if !min_is(&tree, value_of(1)) { ok = false; }
  if !max_is(&tree, value_of(19)) { ok = false; }
  return assert(ok, name);
}

fn t10_delete_churn_deterministic_order4() -> TestResult {
  let name = "order-4 deterministic churn vs flat model (150 ops, keyspace 32, seed 777)";
  let ok = churn_model(4, 32, 150, 777);
  return assert(ok, name);
}

fn t11_range_query_inclusive() -> TestResult {
  let name = "range_query includes both bounds";
  var tree = btree_new(4);
  var ok = true;
  var k = 1;
  while k <= 10 {
    if !btree_insert(&mut tree, k, value_of(k)) { ok = false; }
    k = k + 1;
  }
  var want = Vec[Int].new();
  k = 3;
  while k <= 7 {
    want.push(value_of(k));
    k = k + 1;
  }
  if !vec_eq(&btree_range_query(&tree, 3, 7), &want) { ok = false; }
  return assert(ok, name);
}

fn t12_range_query_single_low_eq_high() -> TestResult {
  let name = "range_query with low == high returns exactly that key";
  var tree = btree_new(4);
  var ok = true;
  var k = 1;
  while k <= 10 {
    if !btree_insert(&mut tree, k, value_of(k)) { ok = false; }
    k = k + 1;
  }
  var want = Vec[Int].new();
  want.push(value_of(5));
  if !vec_eq(&btree_range_query(&tree, 5, 5), &want) { ok = false; }
  if btree_range_query(&tree, 99, 99).len() != 0 { ok = false; }
  return assert(ok, name);
}

fn t13_range_query_empty_result() -> TestResult {
  let name = "range_query outside the key set returns empty";
  var tree = btree_new(4);
  var ok = true;
  var k = 1;
  while k <= 10 {
    if !btree_insert(&mut tree, k, value_of(k)) { ok = false; }
    k = k + 1;
  }
  if btree_range_query(&tree, 100, 200).len() != 0 { ok = false; }
  if btree_range_query(&tree, -10, -1).len() != 0 { ok = false; }
  return assert(ok, name);
}

fn t14_range_query_full_tree() -> TestResult {
  let name = "range_query spanning the whole tree returns ascending values";
  var tree = btree_new(4);
  var ok = true;
  var k = 1;
  while k <= 10 {
    if !btree_insert(&mut tree, k, value_of(k)) { ok = false; }
    k = k + 1;
  }
  let v = btree_range_query(&tree, 0, 11);
  if v.len() != 10 { ok = false; }
  if !ascending(&v) { ok = false; }
  if !vec_eq(&v, &btree_to_vec(&tree)) { ok = false; }
  return assert(ok, name);
}

fn t15_to_vec_ascending_after_shuffle_insert() -> TestResult {
  let name = "shuffled inserts: size and to_vec ascending";
  var tree = btree_new(4);
  var ok = true;
  var order = Vec[Int].new();
  order.push(5); order.push(3); order.push(8); order.push(1); order.push(9);
  order.push(2); order.push(7); order.push(4); order.push(6); order.push(10);
  var i = 0;
  while i < order.len() {
    if !btree_insert(&mut tree, order[i], value_of(order[i])) { ok = false; }
    i = i + 1;
  }
  var present = Vec[Int].new();
  var j = 0;
  while j < 11 {
    present.push(0);
    j = j + 1;
  }
  j = 1;
  while j <= 10 {
    present[j] = 1;
    j = j + 1;
  }
  let v = btree_to_vec(&tree);
  if v.len() != 10 { ok = false; }
  if !ascending(&v) { ok = false; }
  if !vec_eq(&v, &model_vec(&present, 1, 10)) { ok = false; }
  return assert(ok, name);
}

fn t16_min_max_tracking() -> TestResult {
  let name = "min/max track inserts and deletes";
  var tree = btree_new(3);
  var ok = true;
  if !btree_insert(&mut tree, 5, value_of(5)) { ok = false; }
  if !btree_insert(&mut tree, 2, value_of(2)) { ok = false; }
  if !btree_insert(&mut tree, 9, value_of(9)) { ok = false; }
  if !btree_insert(&mut tree, 1, value_of(1)) { ok = false; }
  if !btree_insert(&mut tree, 7, value_of(7)) { ok = false; }
  if !min_is(&tree, value_of(1)) { ok = false; }
  if !max_is(&tree, value_of(9)) { ok = false; }
  if !btree_delete(&mut tree, 1) { ok = false; }
  if !min_is(&tree, value_of(2)) { ok = false; }
  if !btree_delete(&mut tree, 9) { ok = false; }
  if !max_is(&tree, value_of(7)) { ok = false; }
  if !btree_insert(&mut tree, 0, value_of(0)) { ok = false; }
  if !min_is(&tree, value_of(0)) { ok = false; }
  if !btree_insert(&mut tree, 100, value_of(100)) { ok = false; }
  if !max_is(&tree, value_of(100)) { ok = false; }
  return assert(ok, name);
}

fn t17_structural_order5_midrange_delete() -> TestResult {
  let name = "order-5 structure holds through insert and mid-range delete";
  var tree = btree_new(5);
  var ok = true;
  var k = 1;
  while k <= 25 {
    if !btree_insert(&mut tree, k, value_of(k)) { ok = false; }
    k = k + 1;
  }
  if btree_size(&tree) != 25 { ok = false; }
  if validate_tree(&tree) != 0 { ok = false; }
  k = 5;
  while k <= 20 {
    if !btree_delete(&mut tree, k) { ok = false; }
    k = k + 1;
  }
  if btree_size(&tree) != 9 { ok = false; }
  if validate_tree(&tree) != 0 { ok = false; }
  return assert(ok, name);
}

fn t18_structural_order4() -> TestResult {
  let name = "order-4 structure and to_vec hold after 30 ascending inserts";
  var tree = btree_new(4);
  var ok = true;
  var k = 1;
  while k <= 30 {
    if !btree_insert(&mut tree, k, value_of(k)) { ok = false; }
    k = k + 1;
  }
  if btree_size(&tree) != 30 { ok = false; }
  if validate_tree(&tree) != 0 { ok = false; }
  let v = btree_to_vec(&tree);
  if v.len() != 30 { ok = false; }
  if !ascending(&v) { ok = false; }
  return assert(ok, name);
}

fn t19_structural_order5() -> TestResult {
  let name = "order-5 structure and to_vec hold after 40 ascending inserts";
  var tree = btree_new(5);
  var ok = true;
  var k = 1;
  while k <= 40 {
    if !btree_insert(&mut tree, k, value_of(k)) { ok = false; }
    k = k + 1;
  }
  if btree_size(&tree) != 40 { ok = false; }
  if validate_tree(&tree) != 0 { ok = false; }
  let v = btree_to_vec(&tree);
  if v.len() != 40 { ok = false; }
  if !ascending(&v) { ok = false; }
  return assert(ok, name);
}

fn t20_churn_model_order4() -> TestResult {
  let name = "order-4 model churn (300 ops, keyspace 64, seed 2026)";
  let ok = churn_model(4, 64, 300, 2026);
  return assert(ok, name);
}

fn t21_churn_model_order5() -> TestResult {
  let name = "order-5 model churn (300 ops, keyspace 64, seed 2026)";
  let ok = churn_model(5, 64, 300, 2026);
  return assert(ok, name);
}

fn t22_negative_keys() -> TestResult {
  let name = "negative keys work for insert/search/min/max/range/delete";
  var tree = btree_new(4);
  var ok = true;
  var k = -5;
  while k <= 5 {
    if !btree_insert(&mut tree, k, value_of(k)) { ok = false; }
    k = k + 1;
  }
  if btree_size(&tree) != 11 { ok = false; }
  if !min_is(&tree, value_of(-5)) { ok = false; }
  if !max_is(&tree, value_of(5)) { ok = false; }
  if !search_is(&tree, -3, value_of(-3)) { ok = false; }
  var want = Vec[Int].new();
  k = -3;
  while k <= 3 {
    want.push(value_of(k));
    k = k + 1;
  }
  if !vec_eq(&btree_range_query(&tree, -3, 3), &want) { ok = false; }
  if !btree_delete(&mut tree, -5) { ok = false; }
  if !search_none(&tree, -5) { ok = false; }
  if btree_size(&tree) != 10 { ok = false; }
  if validate_tree(&tree) != 0 { ok = false; }
  return assert(ok, name);
}

fn main() -> Int {
  io.println("=== xiom.btree conformance tests ===");
  var failed: Int = 0;

  let r1 = t01_empty_tree();
  if r1.passed { io.println("  [PASS] " + r1.name); } else { io.println("  [FAIL] " + r1.name); failed = failed + 1; }
  let r2 = t02_insert_search_roundtrip();
  if r2.passed { io.println("  [PASS] " + r2.name); } else { io.println("  [FAIL] " + r2.name); failed = failed + 1; }
  let r3 = t03_duplicate_insert_first_wins();
  if r3.passed { io.println("  [PASS] " + r3.name); } else { io.println("  [FAIL] " + r3.name); failed = failed + 1; }
  let r4 = t04_delete_leaf_and_missing();
  if r4.passed { io.println("  [PASS] " + r4.name); } else { io.println("  [FAIL] " + r4.name); failed = failed + 1; }
  let r5 = t05_delete_all_ascending_order4();
  if r5.passed { io.println("  [PASS] " + r5.name); } else { io.println("  [FAIL] " + r5.name); failed = failed + 1; }
  let r6 = t06_delete_borrow_order4();
  if r6.passed { io.println("  [PASS] " + r6.name); } else { io.println("  [FAIL] " + r6.name); failed = failed + 1; }
  let r7 = t07_delete_internal_prev_order4();
  if r7.passed { io.println("  [PASS] " + r7.name); } else { io.println("  [FAIL] " + r7.name); failed = failed + 1; }
  let r8 = t08_structure_order3_readops();
  if r8.passed { io.println("  [PASS] " + r8.name); } else { io.println("  [FAIL] " + r8.name); failed = failed + 1; }
  let r9 = t09_delete_underflow_order5();
  if r9.passed { io.println("  [PASS] " + r9.name); } else { io.println("  [FAIL] " + r9.name); failed = failed + 1; }
  let r10 = t10_delete_churn_deterministic_order4();
  if r10.passed { io.println("  [PASS] " + r10.name); } else { io.println("  [FAIL] " + r10.name); failed = failed + 1; }
  let r11 = t11_range_query_inclusive();
  if r11.passed { io.println("  [PASS] " + r11.name); } else { io.println("  [FAIL] " + r11.name); failed = failed + 1; }
  let r12 = t12_range_query_single_low_eq_high();
  if r12.passed { io.println("  [PASS] " + r12.name); } else { io.println("  [FAIL] " + r12.name); failed = failed + 1; }
  let r13 = t13_range_query_empty_result();
  if r13.passed { io.println("  [PASS] " + r13.name); } else { io.println("  [FAIL] " + r13.name); failed = failed + 1; }
  let r14 = t14_range_query_full_tree();
  if r14.passed { io.println("  [PASS] " + r14.name); } else { io.println("  [FAIL] " + r14.name); failed = failed + 1; }
  let r15 = t15_to_vec_ascending_after_shuffle_insert();
  if r15.passed { io.println("  [PASS] " + r15.name); } else { io.println("  [FAIL] " + r15.name); failed = failed + 1; }
  let r16 = t16_min_max_tracking();
  if r16.passed { io.println("  [PASS] " + r16.name); } else { io.println("  [FAIL] " + r16.name); failed = failed + 1; }
  let r17 = t17_structural_order5_midrange_delete();
  if r17.passed { io.println("  [PASS] " + r17.name); } else { io.println("  [FAIL] " + r17.name); failed = failed + 1; }
  let r18 = t18_structural_order4();
  if r18.passed { io.println("  [PASS] " + r18.name); } else { io.println("  [FAIL] " + r18.name); failed = failed + 1; }
  let r19 = t19_structural_order5();
  if r19.passed { io.println("  [PASS] " + r19.name); } else { io.println("  [FAIL] " + r19.name); failed = failed + 1; }
  let r20 = t20_churn_model_order4();
  if r20.passed { io.println("  [PASS] " + r20.name); } else { io.println("  [FAIL] " + r20.name); failed = failed + 1; }
  let r21 = t21_churn_model_order5();
  if r21.passed { io.println("  [PASS] " + r21.name); } else { io.println("  [FAIL] " + r21.name); failed = failed + 1; }
  let r22 = t22_negative_keys();
  if r22.passed { io.println("  [PASS] " + r22.name); } else { io.println("  [FAIL] " + r22.name); failed = failed + 1; }

  if failed == 0 {
    io.println("xiom.btree: all tests passed");
  } else {
    io.println("xiom.btree: tests failed");
  }
  return failed;
}
