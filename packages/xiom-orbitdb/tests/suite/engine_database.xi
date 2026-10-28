// XIOM ORBITDB -- conformance suite split: engine_database (R2, 2026-10-18).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom_db_conformance_engine_database

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

fn run_engine_new() -> Int {
  let eng = engine_new(4);
  if engine_size(&eng) != 0 { return 1; }
  if engine_wal_size(&eng) != 0 { return 1; }
  return 0;
}

fn test_engine_new() -> TestResult {
  let rc = run_engine_new();
  if rc == 0 { return assert(true, "engine: engine_new starts empty"); }
  return assert(false, "engine: new failed");
}

fn run_engine_insert_get() -> Int {
  var eng = engine_new(4);
  let ok = engine_insert(&mut eng, 5, 55);
  if !ok { return 1; }
  let v = engine_get(&eng, 5);
  match v { None => return 1; Some(val) => { if val != 55 { return 1; } } }
  return 0;
}

fn test_engine_insert_get() -> TestResult {
  let rc = run_engine_insert_get();
  if rc == 0 { return assert(true, "engine: insert then get returns value"); }
  return assert(false, "engine: insert/get failed");
}

fn run_engine_delete() -> Int {
  var eng = engine_new(4);
  engine_insert(&mut eng, 10, 100);
  let del = engine_delete(&mut eng, 10);
  if !del { return 1; }
  let v = engine_get(&eng, 10);
  match v { Some(_) => return 1; None => {} }
  return 0;
}

fn test_engine_delete() -> TestResult {
  let rc = run_engine_delete();
  if rc == 0 { return assert(true, "engine: delete removes existing key"); }
  return assert(false, "engine: delete failed");
}

fn run_engine_update() -> Int {
  var eng = engine_new(4);
  engine_insert(&mut eng, 1, 10);
  let up = engine_update(&mut eng, 1, 99);
  if !up { return 1; }
  let v = engine_get(&eng, 1);
  match v { None => return 1; Some(val) => { if val != 99 { return 1; } } }
  return 0;
}

fn test_engine_update() -> TestResult {
  let rc = run_engine_update();
  if rc == 0 { return assert(true, "engine: update changes existing value"); }
  return assert(false, "engine: update failed");
}

fn run_engine_recover() -> Int {
  var eng = engine_new(4);
  engine_insert(&mut eng, 1, 11);
  engine_insert(&mut eng, 2, 22);
  engine_insert(&mut eng, 3, 33);
  let ok = engine_recover(&mut eng);
  if !ok { return 1; }
  if engine_size(&eng) != 3 { return 1; }
  let v = engine_get(&eng, 2);
  match v { None => return 1; Some(val) => { if val != 22 { return 1; } } }
  return 0;
}

fn test_engine_recover() -> TestResult {
  let rc = run_engine_recover();
  if rc == 0 { return assert(true, "engine: recover replays WAL, restores state"); }
  return assert(false, "engine: recover failed");
}

fn run_engine_range_query() -> Int {
  var eng = engine_new(4);
  engine_insert(&mut eng, 5, 50);
  engine_insert(&mut eng, 15, 150);
  engine_insert(&mut eng, 25, 250);
  engine_insert(&mut eng, 35, 350);
  let results = engine_range_query(&eng, 10, 30);
  if results.len() != 2 { return 1; }
  return 0;
}

fn test_engine_range_query() -> TestResult {
  let rc = run_engine_range_query();
  if rc == 0 { return assert(true, "engine: range_query returns correct subset"); }
  return assert(false, "engine: range_query failed");
}

fn run_engine_flush_wal() -> Int {
  var eng = engine_new(4);
  engine_insert(&mut eng, 1, 10);
  engine_insert(&mut eng, 2, 20);
  engine_flush_wal(&mut eng);
  if engine_wal_size(&eng) != 0 { return 1; }
  if engine_size(&eng) != 2 { return 1; }
  return 0;
}

fn test_engine_flush_wal() -> TestResult {
  let rc = run_engine_flush_wal();
  if rc == 0 { return assert(true, "engine: flush_wal zeros WAL, data persists"); }
  return assert(false, "engine: flush_wal failed");
}

fn run_db_open_and_operations() -> Int {
  var db = db_open(4);
  if !db.open { return 1; }
  let ok = db_insert(&mut db, 1, 100);
  if !ok { return 1; }
  let v = db_get(&db, 1);
  match v { None => return 1; Some(val) => { if val != 100 { return 1; } } }
  if db_size(&db) != 1 { return 1; }
  return 0;
}

fn test_db_open_and_operations() -> TestResult {
  let rc = run_db_open_and_operations();
  if rc == 0 { return assert(true, "database: open/insert/get/size workflow"); }
  return assert(false, "database: workflow failed");
}

fn run_db_closed_rejects_ops() -> Int {
  var db = db_open(4);
  db_insert(&mut db, 1, 100);
  db_close(&mut db);
  let v = db_get(&db, 1);
  match v { Some(_) => return 1; None => {} }
  let ok = db_insert(&mut db, 2, 200);
  if ok { return 1; }
  return 0;
}

fn test_db_closed_rejects_ops() -> TestResult {
  let rc = run_db_closed_rejects_ops();
  if rc == 0 { return assert(true, "database: closed handle rejects get+insert"); }
  return assert(false, "database: closed rejection failed");
}

fn run_db_update_delete() -> Int {
  var db = db_open(4);
  db_insert(&mut db, 1, 10);
  let up = db_update(&mut db, 1, 99);
  if !up { return 1; }
  let v = db_get(&db, 1);
  match v { None => return 1; Some(val) => { if val != 99 { return 1; } } }
  let del = db_delete(&mut db, 1);
  if !del { return 1; }
  let v2 = db_get(&db, 1);
  match v2 { Some(_) => return 1; None => {} }
  return 0;
}

fn test_db_update_delete() -> TestResult {
  let rc = run_db_update_delete();
  if rc == 0 { return assert(true, "database: update then delete full cycle"); }
  return assert(false, "database: update/delete failed");
}

fn run_db_range() -> Int {
  var db = db_open(4);
  db_insert(&mut db, 1, 10);
  db_insert(&mut db, 3, 30);
  db_insert(&mut db, 5, 50);
  db_insert(&mut db, 7, 70);
  let results = db_range(&db, 3, 6);
  if results.len() != 2 { return 1; }
  return 0;
}

fn test_db_range() -> TestResult {
  let rc = run_db_range();
  if rc == 0 { return assert(true, "database: db_range returns correct subset"); }
  return assert(false, "database: db_range failed");
}

fn run_db_recover() -> Int {
  var db = db_open(4);
  db_insert(&mut db, 1, 10);
  db_insert(&mut db, 2, 20);
  let ok = db_recover(&mut db);
  if !ok { return 1; }
  if db_size(&db) != 2 { return 1; }
  return 0;
}

fn test_db_recover() -> TestResult {
  let rc = run_db_recover();
  if rc == 0 { return assert(true, "database: db_recover rebuilds from WAL"); }
  return assert(false, "database: db_recover failed");
}

fn run_db_query() -> Int {
  var db = db_open(4);
  db_insert(&mut db, 10, 100);
  db_insert(&mut db, 20, 200);
  db_insert(&mut db, 30, 300);
  var q = query_new();
  // Value semantics (docs/query-pipeline.md): values are [100,200,300];
  // Gte 250 must yield exactly [300] (key semantics would yield none).
  query_where(&mut q, QueryOp.Gte, 250);
  let results = db_query(&db, &q);
  if results.len() != 1 { return 1; }
  return 0;
}

fn test_db_query() -> TestResult {
  let rc = run_db_query();
  if rc == 0 { return assert(true, "database: db_query applies filter"); }
  return assert(false, "database: db_query failed");
}

// ===========================================================================
// Free space map scaffold tests
// ===========================================================================

fn main() -> Int {
  io.println("=== XIOM DB Conformance: engine_database ===");
  var failed: Int = 0;
  var total: Int = 0;
  let r74 = test_engine_new();
  total = total + 1; failed = failed + report(r74.passed, r74.name);
  let r75 = test_engine_insert_get();
  total = total + 1; failed = failed + report(r75.passed, r75.name);
  let r76 = test_engine_delete();
  total = total + 1; failed = failed + report(r76.passed, r76.name);
  let r77 = test_engine_update();
  total = total + 1; failed = failed + report(r77.passed, r77.name);
  let r78 = test_engine_recover();
  total = total + 1; failed = failed + report(r78.passed, r78.name);
  let r79 = test_engine_range_query();
  total = total + 1; failed = failed + report(r79.passed, r79.name);
  let r80 = test_engine_flush_wal();
  total = total + 1; failed = failed + report(r80.passed, r80.name);
  let r81 = test_db_open_and_operations();
  total = total + 1; failed = failed + report(r81.passed, r81.name);
  let r82 = test_db_closed_rejects_ops();
  total = total + 1; failed = failed + report(r82.passed, r82.name);
  let r83 = test_db_update_delete();
  total = total + 1; failed = failed + report(r83.passed, r83.name);
  let r84 = test_db_range();
  total = total + 1; failed = failed + report(r84.passed, r84.name);
  let r85 = test_db_recover();
  total = total + 1; failed = failed + report(r85.passed, r85.name);
  let r86 = test_db_query();
  total = total + 1; failed = failed + report(r86.passed, r86.name);
  let passed = total - failed;
  io.println("XIOM DB Conformance [engine_database]: " + int_to_str(passed) + "/" + int_to_str(total) + " passed" + (if failed > 0 { " (" + int_to_str(failed) + " FAILED)" } else { "" }));
  return failed;
}