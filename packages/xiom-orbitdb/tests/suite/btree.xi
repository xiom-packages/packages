// XIOM ORBITDB -- conformance suite split: btree (R2, 2026-10-18).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom_db_conformance_btree

use xiom.io;
use xiom.convert;
use xiom.os.env;
use xiom.test;
use xiom.db.engine;
use xiom.db.wal_file;
use xiom.db.error;
use xiom.db.ids;
use xiom.db.config;
use xiom.db.contracts;
use xiom.db.storage.page;
use xiom.db.storage.page_file;
use xiom.db.storage.block;
use xiom.db.storage.fault;
use xiom.db.storage.tuple;
use xiom.db.storage.free_space_map;
use xiom.db.catalog.schema;
use xiom.db.catalog.schema_row;
use xiom.db.catalog.schema_validator;
use xiom.db.txn.transaction;
use xiom_db_suite_common;

fn run_btree_new() -> Int {
  let tree = btree_new(4);
  if btree_size(&tree) != 0 { return 1; }
  return 0;
}

fn test_btree_new() -> TestResult {
  let rc = run_btree_new();
  if rc == 0 { return assert(true, "btree: new tree has size 0"); }
  return assert(false, "btree: new failed");
}

fn run_btree_insert_search() -> Int {
  var tree = btree_new(4);
  let ins = btree_insert(&mut tree, 10, 100);
  if !ins { return 1; }
  let v = btree_search(&tree, 10);
  match v { None => return 1; Some(val) => { if val != 100 { return 1; } } }
  return 0;
}

fn test_btree_insert_search() -> TestResult {
  let rc = run_btree_insert_search();
  if rc == 0 { return assert(true, "btree: insert then search returns value"); }
  return assert(false, "btree: insert/search failed");
}

fn run_btree_delete() -> Int {
  var tree = btree_new(4);
  btree_insert(&mut tree, 10, 100);
  btree_insert(&mut tree, 20, 200);
  btree_insert(&mut tree, 30, 300);
  let del = btree_delete(&mut tree, 20);
  if !del { return 1; }
  let v = btree_search(&tree, 20);
  match v { Some(_) => return 1; None => {} }
  if btree_size(&tree) != 2 { return 1; }
  return 0;
}

fn test_btree_delete() -> TestResult {
  let rc = run_btree_delete();
  if rc == 0 { return assert(true, "btree: delete removes key, size decreases"); }
  return assert(false, "btree: delete failed");
}

fn run_btree_min_max() -> Int {
  var tree = btree_new(4);
  btree_insert(&mut tree, 50, 500);
  btree_insert(&mut tree, 10, 100);
  btree_insert(&mut tree, 99, 990);
  let mn = btree_min(&tree);
  match mn { None => return 1; Some(v) => { if v != 100 { return 1; } } }
  let mx = btree_max(&tree);
  match mx { None => return 1; Some(v) => { if v != 990 { return 1; } } }
  return 0;
}

fn test_btree_min_max() -> TestResult {
  let rc = run_btree_min_max();
  if rc == 0 { return assert(true, "btree: min/max returns correct extremes"); }
  return assert(false, "btree: min/max failed");
}

fn run_btree_range_query() -> Int {
  var tree = btree_new(4);
  btree_insert(&mut tree, 10, 100);
  btree_insert(&mut tree, 20, 200);
  btree_insert(&mut tree, 30, 300);
  btree_insert(&mut tree, 40, 400);
  btree_insert(&mut tree, 50, 500);
  let results = btree_range_query(&tree, 20, 40);
  if results.len() != 3 { return 1; }
  return 0;
}

fn test_btree_range_query() -> TestResult {
  let rc = run_btree_range_query();
  if rc == 0 { return assert(true, "btree: range_query [20,40] returns 3 values"); }
  return assert(false, "btree: range_query failed");
}

fn run_btree_to_vec() -> Int {
  var tree = btree_new(4);
  btree_insert(&mut tree, 30, 300);
  btree_insert(&mut tree, 10, 100);
  btree_insert(&mut tree, 20, 200);
  let vals = btree_to_vec(&tree);
  if vals.len() != 3 { return 1; }
  return 0;
}

fn test_btree_to_vec() -> TestResult {
  let rc = run_btree_to_vec();
  if rc == 0 { return assert(true, "btree: to_vec returns all values"); }
  return assert(false, "btree: to_vec failed");
}

fn run_btree_large_insert() -> Int {
  var tree = btree_new(5);
  var i = 0;
  while i < 100 {
    btree_insert(&mut tree, i, i * 10);
    i = i + 1;
  }
  if btree_size(&tree) != 100 { return 1; }
  let v = btree_search(&tree, 50);
  match v { None => return 1; Some(val) => { if val != 500 { return 1; } } }
  let v2 = btree_search(&tree, 99);
  match v2 { None => return 1; Some(val) => { if val != 990 { return 1; } } }
  return 0;
}

fn test_btree_large_insert() -> TestResult {
  let rc = run_btree_large_insert();
  if rc == 0 { return assert(true, "btree: 100 inserts with splits, all searchable"); }
  return assert(false, "btree: large insert failed");
}

// ===========================================================================
// B-tree churn: randomized insert/delete/search against a reference model.
// Regression lock for the delete/underflow fixes (child-index contract of
// fill_child, borrow_from_left leaf children, min_keys for odd orders).
// Extended soak lives in tests/probes/probe_btree_churn.xi.
// ===========================================================================

fn churn_rand(state: &mut Int) -> Int {
  *state = (*state * 1103515245 + 12345) % 2147483648;
  return *state;
}

fn run_btree_churn(order: Int, ops: Int, n: Int, seed: Int) -> Int {
  var tree = btree_new(order);
  var present = Vec[Int].new();
  var values = Vec[Int].new();
  var i = 0;
  while i < n {
    present.push(0);
    values.push(0);
    i = i + 1;
  }
  var state = seed;
  var step = 0;
  while step < ops {
    let key = churn_rand(&mut state) % n;
    let action = churn_rand(&mut state) % 10;
    if action < 4 {
      let want = present[key] == 0;
      let got = btree_insert(&mut tree, key, key * 7 + 1);
      if got != want { return 1; }
      if want {
        present[key] = 1;
        values[key] = key * 7 + 1;
      }
    } elif action < 7 {
      let want = present[key] == 1;
      let got = btree_delete(&mut tree, key);
      if got != want { return 2; }
      if want { present[key] = 0; }
    } else {
      let got = btree_search(&tree, key);
      if present[key] == 1 {
        match got {
          None => { return 3; }
          Some(v) => { if v != values[key] { return 4; } }
        }
      } else {
        match got {
          Some(_) => { return 5; }
          None => {}
        }
      }
    }
    step = step + 1;
  }

  var expected = 0;
  var k = 0;
  while k < n {
    if present[k] == 1 { expected = expected + 1; }
    k = k + 1;
  }
  if btree_size(&tree) != expected { return 6; }
  let vals = btree_to_vec(&tree);
  if vals.len() != expected { return 7; }
  var idx = 0;
  k = 0;
  while k < n {
    if present[k] == 1 {
      if vals[idx] != values[k] { return 8; }
      idx = idx + 1;
    }
    k = k + 1;
  }
  return 0;
}

fn test_btree_churn_order4() -> TestResult {
  let rc = run_btree_churn(4, 400, 128, 12345);
  if rc == 0 { return assert(true, "btree: churn order 4 vs model (insert/delete/search)"); }
  return assert(false, "btree: churn order 4 failed");
}

fn test_btree_churn_order5() -> TestResult {
  let rc = run_btree_churn(5, 400, 128, 2026);
  if rc == 0 { return assert(true, "btree: churn order 5 vs model (odd-order min-keys)"); }
  return assert(false, "btree: churn order 5 failed");
}

// Order 3 is the min_keys == 0 regime (empty pass-through chains): this is
// the exact reproducer of the old out-of-bounds predecessor read (xiom.btree
// SPEC 2.3; first divergence was op 67 pre-fix).
fn test_btree_churn_order3() -> TestResult {
  let rc = run_btree_churn(3, 2000, 16, 777);
  if rc == 0 { return assert(true, "btree: churn order 3 vs model (min_keys 0 / empty chains)"); }
  return assert(false, "btree: churn order 3 failed");
}

// ===========================================================================
// Integration: Engine + Database facade
// ===========================================================================

fn main() -> Int {
  io.println("=== XIOM DB Conformance: btree ===");
  var failed: Int = 0;
  var total: Int = 0;
  let r67 = test_btree_new();
  total = total + 1; failed = failed + report(r67.passed, r67.name);
  let r68 = test_btree_insert_search();
  total = total + 1; failed = failed + report(r68.passed, r68.name);
  let r69 = test_btree_delete();
  total = total + 1; failed = failed + report(r69.passed, r69.name);
  let r70 = test_btree_min_max();
  total = total + 1; failed = failed + report(r70.passed, r70.name);
  let r71 = test_btree_range_query();
  total = total + 1; failed = failed + report(r71.passed, r71.name);
  let r72 = test_btree_to_vec();
  total = total + 1; failed = failed + report(r72.passed, r72.name);
  let r73 = test_btree_large_insert();
  total = total + 1; failed = failed + report(r73.passed, r73.name);
  let r73b = test_btree_churn_order4();
  total = total + 1; failed = failed + report(r73b.passed, r73b.name);
  let r73c = test_btree_churn_order5();
  total = total + 1; failed = failed + report(r73c.passed, r73c.name);
  let r73d = test_btree_churn_order3();
  total = total + 1; failed = failed + report(r73d.passed, r73d.name);
  let passed = total - failed;
  io.println("XIOM DB Conformance [btree]: " + int_to_str(passed) + "/" + int_to_str(total) + " passed" + (if failed > 0 { " (" + int_to_str(failed) + " FAILED)" } else { "" }));
  return failed;
}