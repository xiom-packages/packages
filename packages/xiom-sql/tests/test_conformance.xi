// XIOM -- SQL Library Conformance Tests
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.

module sql_conformance_tests
use xiom.sql;

// === Returns: 0 = all passed, N = number of failures ===

fn run_open_tests() -> Int {
  var failures: Int = 0;
  let db = sql.open("test.db");
  if db.handle != 0 { failures = failures + 1; }
  if db.path != "test.db" { failures = failures + 1; }
  let db2 = sql.open(":memory:");
  if db2.path != ":memory:" { failures = failures + 1; }
  if db2.handle != 0 { failures = failures + 1; }
  return failures;
}

fn run_execute_tests() -> Int {
  var failures: Int = 0;
  let db = sql.open("test.db");
  let r1 = sql.execute(&db, "SELECT 1");
  if r1 != 0 { failures = failures + 1; }
  let r2 = sql.execute(&db, "CREATE TABLE t(id INT)");
  if r2 != 0 { failures = failures + 1; }
  return failures;
}

fn run_close_tests() -> Int {
  var failures: Int = 0;
  let db = sql.open("test.db");
  let r1 = sql.close(&db);
  if r1 != 0 { failures = failures + 1; }
  let db2 = sql.open("test.db");
  let _ = sql.execute(&db2, "SELECT 1");
  let r2 = sql.close(&db2);
  if r2 != 0 { failures = failures + 1; }
  return failures;
}

fn run_clone_tests() -> Int {
  var failures: Int = 0;
  let db1 = sql.open("clone.db");
  let db2 = db1.clone();
  if db2.path != db1.path { failures = failures + 1; }
  if db2.handle != db1.handle { failures = failures + 1; }
  return failures;
}

fn run_contract_tests() -> Int {
  // Contract tests: verify that requires clauses don't crash
  // when valid inputs are given (path.len() > 0, sql.len() > 0, handle >= 0).
  var failures: Int = 0;
  let db = sql.open("valid.db");
  let r = sql.execute(&db, "SELECT 1");
  if r != 0 { failures = failures + 1; }
  let c = sql.close(&db);
  if c != 0 { failures = failures + 1; }
  return failures;
}

pub fn main() -> Int {
  var failures: Int = 0;
  failures = failures + run_open_tests();
  failures = failures + run_execute_tests();
  failures = failures + run_close_tests();
  failures = failures + run_clone_tests();
  failures = failures + run_contract_tests();
  return failures;
}
