// XIOM ORBITDB -- conformance suite split: wal_txn (R2, 2026-10-18).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom_db_conformance_wal_txn

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

fn run_wal_entry_new() -> Int {
  let entry = wal_entry_new(WALOpType.InsertOp, 10, 100, 1);
  if entry.key != 10 { return 1; }
  if entry.value != 100 { return 1; }
  if entry.timestamp != 1 { return 1; }
  return 0;
}

fn test_wal_entry_new() -> TestResult {
  let rc = run_wal_entry_new();
  if rc == 0 { return assert(true, "wal: WALEntry construction fields correct"); }
  return assert(false, "wal: WALEntry construction failed");
}

fn run_wal_new_and_append() -> Int {
  var wal = wal_new();
  if !wal_is_empty(&wal) { return 1; }
  if wal_len(&wal) != 0 { return 1; }
  let e1 = wal_entry_new(InsertOp, 1, 10, 1);
  wal_append(&mut wal, e1);
  if wal_is_empty(&wal) { return 1; }
  if wal_len(&wal) != 1 { return 1; }
  let e2 = wal_entry_new(DeleteOp, 2, 0, 2);
  wal_append(&mut wal, e2);
  if wal_len(&wal) != 2 { return 1; }
  return 0;
}

fn test_wal_new_and_append() -> TestResult {
  let rc = run_wal_new_and_append();
  if rc == 0 { return assert(true, "wal: new/is_empty/len append grows"); }
  return assert(false, "wal: append/len failed");
}

fn run_wal_entry_count_filter() -> Int {
  var wal = wal_new();
  wal_append(&mut wal, wal_entry_new(InsertOp, 1, 10, 1));
  wal_append(&mut wal, wal_entry_new(InsertOp, 2, 20, 2));
  wal_append(&mut wal, wal_entry_new(DeleteOp, 3, 0, 3));
  wal_append(&mut wal, wal_entry_new(UpdateOp, 4, 40, 4));
  var inserts = wal_entry_count(&wal, WALOpType.InsertOp);
  if inserts != 2 { return 1; }
  var deletes = wal_entry_count(&wal, WALOpType.DeleteOp);
  if deletes != 1 { return 1; }
  var updates = wal_entry_count(&wal, WALOpType.UpdateOp);
  if updates != 1 { return 1; }
  return 0;
}

fn test_wal_entry_count_filter() -> TestResult {
  let rc = run_wal_entry_count_filter();
  if rc == 0 { return assert(true, "wal: entry_count by op type filter"); }
  return assert(false, "wal: entry_count filter wrong");
}

fn run_wal_clear() -> Int {
  var wal = wal_new();
  wal_append(&mut wal, wal_entry_new(InsertOp, 1, 10, 1));
  wal_append(&mut wal, wal_entry_new(InsertOp, 2, 20, 2));
  wal_clear(&mut wal);
  if !wal_is_empty(&wal) { return 1; }
  if wal_len(&wal) != 0 { return 1; }
  return 0;
}

fn test_wal_clear() -> TestResult {
  let rc = run_wal_clear();
  if rc == 0 { return assert(true, "wal: clear empties all entries"); }
  return assert(false, "wal: clear failed");
}

fn run_wal_truncate() -> Int {
  var wal = wal_new();
  wal_append(&mut wal, wal_entry_new(InsertOp, 1, 10, 1));
  wal_append(&mut wal, wal_entry_new(InsertOp, 2, 20, 5));
  wal_append(&mut wal, wal_entry_new(InsertOp, 3, 30, 10));
  wal_truncate(&mut wal, 5);
  if wal_len(&wal) != 2 { return 1; }
  wal_truncate(&mut wal, 10);
  if wal_len(&wal) != 1 { return 1; }
  return 0;
}

fn test_wal_truncate() -> TestResult {
  let rc = run_wal_truncate();
  if rc == 0 { return assert(true, "wal: truncate keeps entries >= timestamp"); }
  return assert(false, "wal: truncate failed");
}

fn run_wal_replay_insert() -> Int {
  var wal = wal_new();
  wal_append(&mut wal, wal_entry_new(InsertOp, 10, 100, 1));
  wal_append(&mut wal, wal_entry_new(InsertOp, 20, 200, 2));
  wal_append(&mut wal, wal_entry_new(InsertOp, 30, 300, 3));
  var tree = btree_new(4);
  let ok = wal_replay(&wal, &mut tree);
  if !ok { return 1; }
  let v = btree_search(&tree, 10);
  match v { None => return 1; Some(_) => {} }
  let v2 = btree_search(&tree, 20);
  match v2 { None => return 1; Some(_) => {} }
  let v3 = btree_search(&tree, 30);
  match v3 { None => return 1; Some(_) => {} }
  return 0;
}

fn test_wal_replay_insert() -> TestResult {
  let rc = run_wal_replay_insert();
  if rc == 0 { return assert(true, "wal: replay inserts into fresh BTree"); }
  return assert(false, "wal: replay insert failed");
}

fn run_wal_replay_delete() -> Int {
  var tree = btree_new(4);
  btree_insert(&mut tree, 10, 100);
  btree_insert(&mut tree, 20, 200);
  var wal = wal_new();
  wal_append(&mut wal, wal_entry_new(DeleteOp, 10, 0, 1));
  let ok = wal_replay(&wal, &mut tree);
  if !ok { return 1; }
  let v = btree_search(&tree, 10);
  match v { Some(_) => return 1; None => {} }
  let v2 = btree_search(&tree, 20);
  match v2 { None => return 1; Some(_) => {} }
  return 0;
}

fn test_wal_replay_delete() -> TestResult {
  let rc = run_wal_replay_delete();
  if rc == 0 { return assert(true, "wal: replay deletes existing key"); }
  return assert(false, "wal: replay delete failed");
}

// ===========================================================================
// 9. Transaction state machine transitions
// ===========================================================================

fn run_txn_new_is_active() -> Int {
  let txn = Transaction.new(1);
  if !txn.is_active() { return 1; }
  return 0;
}

fn test_txn_new_is_active() -> TestResult {
  let rc = run_txn_new_is_active();
  if rc == 0 { return assert(true, "txn: new transaction is Active"); }
  return assert(false, "txn: new not active");
}

fn run_txn_commit() -> Int {
  let txn = Transaction.new(1);
  let committed = txn.commit();
  if committed.is_active() { return 1; }
  return 0;
}

fn test_txn_commit() -> TestResult {
  let rc = run_txn_commit();
  if rc == 0 { return assert(true, "txn: commit moves to Committed (not active)"); }
  return assert(false, "txn: commit failed");
}

fn run_txn_abort() -> Int {
  let txn = Transaction.new(1);
  let aborted = txn.abort();
  if aborted.is_active() { return 1; }
  return 0;
}

fn test_txn_abort() -> TestResult {
  let rc = run_txn_abort();
  if rc == 0 { return assert(true, "txn: abort moves to Aborted (not active)"); }
  return assert(false, "txn: abort failed");
}

fn run_txn_add_op() -> Int {
  let txn = Transaction.new(1);
  let with_op = txn.add_op(WALOp.Insert);
  if !with_op.is_active() { return 1; }
  return 0;
}

fn test_txn_add_op() -> TestResult {
  let rc = run_txn_add_op();
  if rc == 0 { return assert(true, "txn: add_op on active transaction succeeds"); }
  return assert(false, "txn: add_op failed");
}

fn run_txn_full_lifecycle() -> Int {
  let txn1 = Transaction.new(1);
  let txn2 = txn1.add_op(WALOp.Insert);
  let txn3 = txn2.add_op(WALOp.Update);
  let txn4 = txn3.commit();
  if txn4.is_active() { return 1; }
  return 0;
}

fn test_txn_full_lifecycle() -> TestResult {
  let rc = run_txn_full_lifecycle();
  if rc == 0 { return assert(true, "txn: active->add->add->commit lifecycle"); }
  return assert(false, "txn: lifecycle failed");
}

fn run_txn_abort_lifecycle() -> Int {
  let txn1 = Transaction.new(2);
  let txn2 = txn1.add_op(WALOp.Delete);
  let txn3 = txn2.abort();
  if txn3.is_active() { return 1; }
  return 0;
}

fn test_txn_abort_lifecycle() -> TestResult {
  let rc = run_txn_abort_lifecycle();
  if rc == 0 { return assert(true, "txn: active->add->abort lifecycle"); }
  return assert(false, "txn: abort lifecycle failed");
}

// ===========================================================================
// 10. Schema validation stubs
// ===========================================================================

fn main() -> Int {
  io.println("=== XIOM DB Conformance: wal_txn ===");
  var failed: Int = 0;
  var total: Int = 0;
  let r37 = test_wal_entry_new();
  total = total + 1; failed = failed + report(r37.passed, r37.name);
  let r38 = test_wal_new_and_append();
  total = total + 1; failed = failed + report(r38.passed, r38.name);
  let r39 = test_wal_entry_count_filter();
  total = total + 1; failed = failed + report(r39.passed, r39.name);
  let r40 = test_wal_clear();
  total = total + 1; failed = failed + report(r40.passed, r40.name);
  let r41 = test_wal_truncate();
  total = total + 1; failed = failed + report(r41.passed, r41.name);
  let r42 = test_wal_replay_insert();
  total = total + 1; failed = failed + report(r42.passed, r42.name);
  let r43 = test_wal_replay_delete();
  total = total + 1; failed = failed + report(r43.passed, r43.name);
  let r44 = test_txn_new_is_active();
  total = total + 1; failed = failed + report(r44.passed, r44.name);
  let r45 = test_txn_commit();
  total = total + 1; failed = failed + report(r45.passed, r45.name);
  let r46 = test_txn_abort();
  total = total + 1; failed = failed + report(r46.passed, r46.name);
  let r47 = test_txn_add_op();
  total = total + 1; failed = failed + report(r47.passed, r47.name);
  let r48 = test_txn_full_lifecycle();
  total = total + 1; failed = failed + report(r48.passed, r48.name);
  let r49 = test_txn_abort_lifecycle();
  total = total + 1; failed = failed + report(r49.passed, r49.name);
  let passed = total - failed;
  io.println("XIOM DB Conformance [wal_txn]: " + int_to_str(passed) + "/" + int_to_str(total) + " passed" + (if failed > 0 { " (" + int_to_str(failed) + " FAILED)" } else { "" }));
  return failed;
}