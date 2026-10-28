// XIOM ORBITDB -- conformance suite split: typed_mvcc (R2, 2026-10-18).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom_db_conformance_typed_mvcc

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

fn tdb_row3(a: Int, b: Int, c: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  return v;
}

fn tdb_row2(a: Int, b: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  return v;
}

fn tdb_cleanup(path: Str) {
  let _ = io.remove_file(path);
  let _ = io.remove_file(path + ".snap");
}

fn run_db_typed_roundtrip() -> Int {
  let path = "orbitdb-suite-typed.wal";
  tdb_cleanup(path);
  var db = db_file_open(path, 4);

  // Typed put: get_typed returns the payload; the int value mirrors the key.
  if !db_file_put_typed(&mut db, 7, tdb_row3(1, 2, 3)) { return 1; }
  match db_file_get_typed(&db, 7) {
    None => { return 2; }
    Some(p) => {
      if p.len() != 3 { return 3; }
      if p[0] != 1 { return 4; }
      if p[2] != 3 { return 5; }
    }
  }
  match db_file_get(&db, 7) {
    None => { return 6; }
    Some(v) => { if v != 7 { return 7; } }
  }

  // Int row coexists; get_typed on it is None.
  if !db_file_put(&mut db, 8, 800) { return 8; }
  match db_file_get_typed(&db, 8) { Some(_) => { return 9; } None => {} }

  // Typed -> int overwrite drops the payload.
  if !db_file_put(&mut db, 7, 700) { return 10; }
  match db_file_get_typed(&db, 7) { Some(_) => { return 11; } None => {} }
  match db_file_get(&db, 7) { Some(v) => { if v != 700 { return 12; } } None => { return 13; } }

  // Int -> typed overwrite installs one.
  if !db_file_put_typed(&mut db, 8, tdb_row2(9, 9)) { return 14; }
  match db_file_get_typed(&db, 8) {
    None => { return 15; }
    Some(p) => { if p.len() != 2 { return 16; } }
  }

  // Reopen WITHOUT checkpoint: WAL replay must carry the payloads.
  var db2 = db_file_open(path, 4);
  if db_file_size(&db2) != 2 { return 17; }
  match db_file_get_typed(&db2, 8) {
    None => { return 18; }
    Some(p) => { if p[0] != 9 { return 19; } }
  }
  match db_file_get_typed(&db2, 7) { Some(_) => { return 20; } None => {} }
  match db_file_get(&db2, 7) { Some(v) => { if v != 700 { return 21; } } None => { return 22; } }

  // Delete a typed row.
  if !db_file_delete(&mut db2, 8) { return 23; }
  var db3 = db_file_open(path, 4);
  if db_file_size(&db3) != 1 { return 24; }
  match db_file_get_typed(&db3, 8) { Some(_) => { return 25; } None => {} }

  tdb_cleanup(path);
  return 0;
}

fn test_db_typed_roundtrip() -> TestResult {
  let rc = run_db_typed_roundtrip();
  if rc == 0 { return assert(true, "db_file typed: put/get/overwrite/delete + WAL replay carries payloads"); }
  return assert(false, "db_file typed: roundtrip failed rc=" + int_to_str(rc));
}

fn tdb_checkpoint_body(path: Str, page_format: Int) -> Int {
  tdb_cleanup(path);
  var db = db_file_open_cfg(path, 4, page_format);
  var k = 1;
  while k <= 5 {
    if !db_file_put_typed(&mut db, k, tdb_row3(k, k * 10, 100 + k)) { return 1; }
    k = k + 1;
  }
  if !db_file_put(&mut db, 6, 6000) { return 2; }
  if db_file_checkpoint(&mut db) < 0 { return 3; }
  // Tail after the snapshot.
  if !db_file_put_typed(&mut db, 7, tdb_row3(7, 70, 107)) { return 4; }
  if !db_file_put(&mut db, 8, 8000) { return 5; }

  var db2 = db_file_open(path, 4);
  if db_file_size(&db2) != 8 { return 6; }
  k = 1;
  while k <= 5 {
    match db_file_get_typed(&db2, k) {
      None => { return 10 + k; }
      Some(p) => {
        if p.len() != 3 { return 20 + k; }
        if p[0] != k { return 30 + k; }
        if p[1] != k * 10 { return 40 + k; }
        if p[2] != 100 + k { return 50 + k; }
      }
    }
    k = k + 1;
  }
  match db_file_get(&db2, 6) {
    None => { return 60; }
    Some(v) => { if v != 6000 { return 61; } }
  }
  match db_file_get_typed(&db2, 7) {
    None => { return 62; }
    Some(p) => { if p[1] != 70 { return 63; } }
  }
  match db_file_get(&db2, 8) {
    None => { return 64; }
    Some(v) => { if v != 8000 { return 65; } }
  }

  // A second checkpoint then reopen: payloads survive generations.
  if db_file_checkpoint(&mut db2) < 0 { return 66; }
  var db3 = db_file_open(path, 4);
  if db_file_size(&db3) != 8 { return 67; }
  match db_file_get_typed(&db3, 3) {
    None => { return 68; }
    Some(p) => { if p[2] != 103 { return 69; } }
  }
  tdb_cleanup(path);
  return 0;
}

fn run_db_typed_checkpoint_v1() -> Int {
  return tdb_checkpoint_body("orbitdb-suite-typed-ck1.wal", 1);
}

fn test_db_typed_checkpoint_v1() -> TestResult {
  let rc = run_db_typed_checkpoint_v1();
  if rc == 0 { return assert(true, "db_file typed: v1 checkpoint + generations keep payloads (snapshot + tail)"); }
  return assert(false, "db_file typed: v1 checkpoint failed rc=" + int_to_str(rc));
}

fn run_db_typed_checkpoint_v2() -> Int {
  return tdb_checkpoint_body("orbitdb-suite-typed-ck2.wal", 2);
}

fn test_db_typed_checkpoint_v2() -> TestResult {
  let rc = run_db_typed_checkpoint_v2();
  if rc == 0 { return assert(true, "db_file typed: v2 block snapshot keeps payloads (auto-detect + regen)"); }
  return assert(false, "db_file typed: v2 checkpoint failed rc=" + int_to_str(rc));
}

fn run_db_typed_budget_and_guards() -> Int {
  // Budget formula: overhead = 28 + 24*(order-1) + 8*order, room = 4056 - it.
  if db_file_typed_payload_max(2) != 0 { return 1; }
  if db_file_typed_payload_max(3) != 1978 { return 2; }
  if db_file_typed_payload_max(4) != 1308 { return 3; }
  if db_file_typed_payload_max(5) != 973 { return 4; }

  let path = "orbitdb-suite-typed-budget.wal";
  tdb_cleanup(path);
  var db = db_file_open(path, 3);
  let max = db_file_typed_payload_max(3);
  var exact = Vec[Int].new();
  var i = 0;
  while i < max {
    exact.push(i % 256);
    i = i + 1;
  }
  if !db_file_put_typed(&mut db, 1, exact) { return 5; }
  match db_file_get_typed(&db, 1) {
    None => { return 6; }
    Some(p) => { if p.len() != max { return 7; } }
  }
  // One byte over the budget: refused, and nothing is stored.
  var over = Vec[Int].new();
  i = 0;
  while i < max + 1 {
    over.push(1);
    i = i + 1;
  }
  if db_file_put_typed(&mut db, 2, over) { return 8; }
  match db_file_get_typed(&db, 2) { Some(_) => { return 9; } None => {} }
  if db_file_size(&db) != 1 { return 10; }

  // Typed writes are refused while a transaction is active.
  if !db_file_txn_begin(&mut db) { return 11; }
  if db_file_put_typed(&mut db, 3, tdb_row2(1, 2)) { return 12; }
  if !db_file_txn_abort(&mut db) { return 13; }

  // Byte-range: elements outside 0..255 are refused up front (the snapshot
  // codecs are byte-oriented; accepting them would silently lose bits).
  var wide = Vec[Int].new();
  wide.push(300);
  if db_file_put_typed(&mut db, 4, wide) { return 14; }
  var neg = Vec[Int].new();
  neg.push(-1);
  if db_file_put_typed(&mut db, 4, neg) { return 15; }
  if db_file_size(&db) != 1 { return 16; }

  tdb_cleanup(path);
  return 0;
}

fn test_db_typed_budget_and_guards() -> TestResult {
  let rc = run_db_typed_budget_and_guards();
  if rc == 0 { return assert(true, "db_file typed: payload budget (orders 3/4/5) + over-budget + txn guard"); }
  return assert(false, "db_file typed: budget/guards failed rc=" + int_to_str(rc));
}

// Crafted WAL: a typed record inside a committed txn window must replay with
// its payload (TxOp buffers it); inside an unterminated window it is
// discarded like any uncommitted write.
fn run_db_typed_txn_window_replay() -> Int {
  let path = "orbitdb-suite-typed-txn2.wal";
  tdb_cleanup(path);
  var wal = wal_file_open(path);
  let _ = wal_file_append(&mut wal, WALOpKind.BeginTxn, 0, 0);
  var tagged = Vec[Int].new();
  tagged.push(1);
  tagged.push(5);
  tagged.push(6);
  tagged.push(7);
  let _ = wal_file_append_tagged(&mut wal, WALOpKind.Update, 11, 11, tagged, 0);
  let _ = wal_file_append(&mut wal, WALOpKind.CommitTxn, 0, 0);
  let _ = wal_file_append(&mut wal, WALOpKind.BeginTxn, 0, 0);
  var tagged2 = Vec[Int].new();
  tagged2.push(1);
  tagged2.push(8);
  tagged2.push(9);
  let _ = wal_file_append_tagged(&mut wal, WALOpKind.Update, 12, 12, tagged2, 0);

  var db = db_file_open(path, 4);
  if db_file_size(&db) != 1 { return 1; }
  match db_file_get_typed(&db, 11) {
    None => { return 2; }
    Some(p) => {
      if p.len() != 3 { return 3; }
      if p[0] != 5 { return 4; }
      if p[2] != 7 { return 5; }
    }
  }
  match db_file_get_typed(&db, 12) { Some(_) => { return 6; } None => {} }
  match db_file_get(&db, 11) {
    None => { return 7; }
    Some(v) => { if v != 11 { return 8; } }
  }

  // Deeper window: int ops and typed ops mixed, then commit.
  let _ = io.remove_file(path);
  let _ = io.remove_file(path + ".snap");
  var wal2 = wal_file_open(path);
  let _ = wal_file_append(&mut wal2, WALOpKind.BeginTxn, 0, 0);
  let _ = wal_file_append(&mut wal2, WALOpKind.Update, 1, 100);
  var tagged3 = Vec[Int].new();
  tagged3.push(1);
  tagged3.push(42);
  let _ = wal_file_append_tagged(&mut wal2, WALOpKind.Update, 2, 2, tagged3, 0);
  let _ = wal_file_append(&mut wal2, WALOpKind.Delete, 1, 0);
  let _ = wal_file_append(&mut wal2, WALOpKind.CommitTxn, 0, 0);
  var db2 = db_file_open(path, 4);
  if db_file_size(&db2) != 1 { return 9; }
  match db_file_get(&db2, 1) { Some(_) => { return 10; } None => {} }
  match db_file_get_typed(&db2, 2) {
    None => { return 11; }
    Some(p) => { if p[0] != 42 { return 12; } }
  }

  tdb_cleanup(path);
  return 0;
}

fn test_db_typed_txn_window_replay() -> TestResult {
  let rc = run_db_typed_txn_window_replay();
  if rc == 0 { return assert(true, "db_file typed: committed txn window replays payloads; uncommitted discarded"); }
  return assert(false, "db_file typed: txn window replay failed rc=" + int_to_str(rc));
}

// ===========================================================================
// Typed comparisons + typed queries (M5-S4): the total order over TValue
// (Null < numeric < text < blob) and db_file_query_typed predicates.
// ===========================================================================

fn tq_blob(a: Int, b: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  return v;
}

fn tq_blob1(a: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  return v;
}

fn tq_blob3(a: Int, b: Int, c: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  return v;
}

fn run_tuple2_compare() -> Int {
  // Null is the minimum; rank order numeric < text < blob.
  if tuple2_compare(TValue.VNull, TValue.VNull) != 0 { return 1; }
  if tuple2_compare(TValue.VNull, TValue.VInt(0)) != -1 { return 2; }
  if tuple2_compare(TValue.VInt(0), TValue.VNull) != 1 { return 3; }
  if tuple2_compare(TValue.VNull, TValue.VText("")) != -1 { return 4; }
  if tuple2_compare(TValue.VText(""), TValue.VNull) != 1 { return 5; }
  // Ints exact; int/float numeric coercion.
  if tuple2_compare(TValue.VInt(-5), TValue.VInt(-4)) != -1 { return 6; }
  if tuple2_compare(TValue.VInt(7), TValue.VInt(7)) != 0 { return 7; }
  if tuple2_compare(TValue.VInt(1), TValue.VFloat(1.0)) != 0 { return 8; }
  if tuple2_compare(TValue.VInt(2), TValue.VFloat(1.5)) != 1 { return 9; }
  if tuple2_compare(TValue.VInt(1), TValue.VFloat(1.5)) != -1 { return 10; }
  // Floats: natural order, NaN first, NaN == NaN.
  if tuple2_compare(TValue.VFloat(-2.5), TValue.VFloat(0.0)) != -1 { return 11; }
  if tuple2_compare(TValue.VFloat(0.0), TValue.VFloat(2.5)) != -1 { return 12; }
  if tuple2_compare(TValue.VFloat(3.0), TValue.VFloat(3.0)) != 0 { return 13; }
  // Numeric ranks above/below across kinds.
  if tuple2_compare(TValue.VInt(999), TValue.VText("")) != -1 { return 14; }
  if tuple2_compare(TValue.VText(""), TValue.VBlob(tq_blob(0, 0))) != -1 { return 15; }
  // Text bytewise lexicographic (prefix smaller).
  if tuple2_compare(TValue.VText("a"), TValue.VText("ab")) != -1 { return 16; }
  if tuple2_compare(TValue.VText("ab"), TValue.VText("b")) != -1 { return 17; }
  if tuple2_compare(TValue.VText("apple"), TValue.VText("apple")) != 0 { return 18; }
  // Multibyte UTF-8 compares by bytes.
  if tuple2_compare(TValue.VText("z"), TValue.VText("\xC3\xA9")) != -1 { return 19; }
  // Blobs element-wise.
  if tuple2_compare(TValue.VBlob(tq_blob(1, 2)), TValue.VBlob(tq_blob(1, 3))) != -1 { return 20; }
  if tuple2_compare(TValue.VBlob(tq_blob(1, 2)), TValue.VBlob(tq_blob3(1, 2, 0))) != -1 { return 21; }
  if tuple2_compare(TValue.VBlob(tq_blob1(9)), TValue.VBlob(tq_blob(1, 9))) != 1 { return 22; }
  return 0;
}

fn test_tuple2_compare() -> TestResult {
  let rc = run_tuple2_compare();
  if rc == 0 { return assert(true, "tuple v2: total order (null < numeric < text < blob; coercion; NaN)"); }
  return assert(false, "tuple v2: comparator failed rc=" + int_to_str(rc));
}

fn tq_put_row(db: &mut DBFile, id: Int, v0: TValue, v1: TValue, v2: TValue) -> Bool {
  var vals = Vec[TValue].new();
  vals.push(v0);
  vals.push(v1);
  vals.push(v2);
  match tuple2_encode_row_checked(id, &vals) {
    Err(_) => { return false; }
    Ok(buf) => { return db_file_put_typed(db, id, buf); }
  }
}

fn tq_seed(db: &mut DBFile) -> Int {
  if !tq_put_row(db, 1, TValue.VInt(10), TValue.VText("apple"), TValue.VFloat(1.5)) { return 1; }
  if !tq_put_row(db, 2, TValue.VInt(20), TValue.VText("banana"), TValue.VFloat(-2.0)) { return 2; }
  if !tq_put_row(db, 3, TValue.VNull, TValue.VText("apple"), TValue.VFloat(0.0)) { return 3; }
  if !tq_put_row(db, 4, TValue.VInt(10), TValue.VText("apricot"), TValue.VFloat(2.5)) { return 4; }
  if !db_file_put(db, 5, 555) { return 5; }
  var raw = Vec[Int].new();
  raw.push(1);
  raw.push(2);
  raw.push(3);
  if !db_file_put_typed(db, 6, raw) { return 6; }
  return 0;
}

fn tq_expect(db: &DBFile, q: &TypedQuery, want: &Vec[Int]) -> Bool {
  let got = db_file_query_typed(db, q);
  if got.len() != want.len() { return false; }
  var i = 0;
  while i < got.len() {
    if got[i] != want[i] { return false; }
    i = i + 1;
  }
  return true;
}

fn tq_want(a: Int, b: Int, c: Int, d: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  if a >= 0 { v.push(a); }
  if b >= 0 { v.push(b); }
  if c >= 0 { v.push(c); }
  if d >= 0 { v.push(d); }
  return v;
}

fn run_typed_query_ops() -> Int {
  let path = "orbitdb-suite-tquery.wal";
  tdb_cleanup(path);
  var db = db_file_open(path, 4);
  let seed = tq_seed(&mut db);
  if seed != 0 { return seed; }

  var q = typed_query_new();
  // Eq int -> [1,4]
  typed_query_where(&mut q, 0, QueryOp.Eq, TValue.VInt(10));
  if !tq_expect(&db, &q, &tq_want(1, 4, -1, -1)) { return 10; }
  // Gt int -> [2]
  q = typed_query_new();
  typed_query_where(&mut q, 0, QueryOp.Gt, TValue.VInt(10));
  if !tq_expect(&db, &q, &tq_want(2, -1, -1, -1)) { return 11; }
  // Lte includes the null (null < numeric) -> [1,3,4]
  q = typed_query_new();
  typed_query_where(&mut q, 0, QueryOp.Lte, TValue.VInt(10));
  if !tq_expect(&db, &q, &tq_want(1, 3, 4, -1)) { return 12; }
  // Lt -> only the null -> [3]
  q = typed_query_new();
  typed_query_where(&mut q, 0, QueryOp.Lt, TValue.VInt(10));
  if !tq_expect(&db, &q, &tq_want(3, -1, -1, -1)) { return 13; }
  // Neq null excludes null rows -> [1,2,4]
  q = typed_query_new();
  typed_query_where(&mut q, 0, QueryOp.Neq, TValue.VNull);
  if !tq_expect(&db, &q, &tq_want(1, 2, 4, -1)) { return 14; }
  // Gte null -> everything typed -> [1,2,3,4]
  q = typed_query_new();
  typed_query_where(&mut q, 0, QueryOp.Gte, TValue.VNull);
  if !tq_expect(&db, &q, &tq_want(1, 2, 3, 4)) { return 15; }
  // Text equality -> [1,3]
  q = typed_query_new();
  typed_query_where(&mut q, 1, QueryOp.Eq, TValue.VText("apple"));
  if !tq_expect(&db, &q, &tq_want(1, 3, -1, -1)) { return 16; }
  // Text Gt -> [2,4]
  q = typed_query_new();
  typed_query_where(&mut q, 1, QueryOp.Gt, TValue.VText("apple"));
  if !tq_expect(&db, &q, &tq_want(2, 4, -1, -1)) { return 17; }
  // Float vs int literal across kinds (numeric): Eq 2.5 -> [4]
  q = typed_query_new();
  typed_query_where(&mut q, 2, QueryOp.Eq, TValue.VFloat(2.5));
  if !tq_expect(&db, &q, &tq_want(4, -1, -1, -1)) { return 18; }
  // Column -1 addresses the row id.
  q = typed_query_new();
  typed_query_where(&mut q, -1, QueryOp.Eq, TValue.VInt(3));
  if !tq_expect(&db, &q, &tq_want(3, -1, -1, -1)) { return 19; }
  // Out-of-range column never matches.
  q = typed_query_new();
  typed_query_where(&mut q, 9, QueryOp.Eq, TValue.VInt(1));
  if !tq_expect(&db, &q, &tq_want(-1, -1, -1, -1)) { return 20; }
  // No conditions: every decodable typed row (int row 5 and malformed 6 out).
  q = typed_query_new();
  if !tq_expect(&db, &q, &tq_want(1, 2, 3, 4)) { return 21; }
  // AND of two conditions: [1]
  q = typed_query_new();
  typed_query_where(&mut q, 0, QueryOp.Eq, TValue.VInt(10));
  typed_query_where(&mut q, 1, QueryOp.Eq, TValue.VText("apple"));
  if !tq_expect(&db, &q, &tq_want(1, -1, -1, -1)) { return 22; }
  // Limit/offset on matches.
  q = typed_query_new();
  typed_query_where(&mut q, 0, QueryOp.Eq, TValue.VInt(10));
  typed_query_limit(&mut q, 1);
  if !tq_expect(&db, &q, &tq_want(1, -1, -1, -1)) { return 23; }
  q = typed_query_new();
  typed_query_where(&mut q, 0, QueryOp.Eq, TValue.VInt(10));
  typed_query_offset(&mut q, 1);
  if !tq_expect(&db, &q, &tq_want(4, -1, -1, -1)) { return 24; }
  q = typed_query_new();
  typed_query_where(&mut q, 0, QueryOp.Eq, TValue.VInt(10));
  typed_query_limit(&mut q, 1);
  typed_query_offset(&mut q, 1);
  if !tq_expect(&db, &q, &tq_want(4, -1, -1, -1)) { return 25; }

  tdb_cleanup(path);
  return 0;
}

fn test_typed_query_ops() -> TestResult {
  let rc = run_typed_query_ops();
  if rc == 0 { return assert(true, "typed query: ops over int/text/float/null + id column + limit/offset"); }
  return assert(false, "typed query: ops failed rc=" + int_to_str(rc));
}

fn run_typed_query_persistence() -> Int {
  let path = "orbitdb-suite-tquery2.wal";
  tdb_cleanup(path);
  var db = db_file_open(path, 4);
  let seed = tq_seed(&mut db);
  if seed != 0 { return 1; }
  if db_file_checkpoint(&mut db) < 0 { return 2; }
  // Tail after the snapshot.
  if !tq_put_row(&mut db, 7, TValue.VInt(10), TValue.VText("avocado"), TValue.VFloat(3.5)) { return 3; }

  var db2 = db_file_open(path, 4);
  var q = typed_query_new();
  typed_query_where(&mut q, 0, QueryOp.Eq, TValue.VInt(10));
  if !tq_expect(&db2, &q, &tq_want(1, 4, 7, -1)) { return 4; }
  q = typed_query_new();
  typed_query_where(&mut q, 1, QueryOp.Gte, TValue.VText("apricot"));
  if !tq_expect(&db2, &q, &tq_want(2, 4, 7, -1)) { return 5; }

  // Mutation visibility: delete 4, add 8 -> queries reflect both.
  if !db_file_delete(&mut db2, 4) { return 6; }
  if !tq_put_row(&mut db2, 8, TValue.VInt(10), TValue.VText(" almond"), TValue.VFloat(0.5)) { return 7; }
  q = typed_query_new();
  typed_query_where(&mut q, 0, QueryOp.Eq, TValue.VInt(10));
  if !tq_expect(&db2, &q, &tq_want(1, 7, 8, -1)) { return 8; }
  // Text range: space-leading " almond" sorts before letters.
  q = typed_query_new();
  typed_query_where(&mut q, 1, QueryOp.Lt, TValue.VText("a"));
  if !tq_expect(&db2, &q, &tq_want(8, -1, -1, -1)) { return 9; }

  tdb_cleanup(path);
  return 0;
}

fn test_typed_query_persistence() -> TestResult {
  let rc = run_typed_query_persistence();
  if rc == 0 { return assert(true, "typed query: survives checkpoint/reopen; mutations visible"); }
  return assert(false, "typed query: persistence failed rc=" + int_to_str(rc));
}

// ===========================================================================
// M3 minimal subset: snapshot pins + savepoints (docs/MVCC.md)
// ===========================================================================

fn mvcc_copy(v: &Vec[Int]) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 0;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
  return out;
}

// Model lookup table: slot k holds key k's value, or -1 when absent.
fn mvcc_model_new(n: Int) -> Vec[Int] {
  var m = Vec[Int].new();
  var i = 0;
  while i <= n {
    m.push(-1);
    i = i + 1;
  }
  return m;
}

// Expected VALUES for keys [1, n] in key order, from a model table.
fn mvcc_expected(m: &Vec[Int]) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 1;
  while i < m.len() {
    if m[i] >= 0 { out.push(m[i]); }
    i = i + 1;
  }
  return out;
}

fn mvcc_vec_eq(a: &Vec[Int], b: &Vec[Int]) -> Bool {
  if a.len() != b.len() { return false; }
  var i = 0;
  while i < a.len() {
    if a[i] != b[i] { return false; }
    i = i + 1;
  }
  return true;
}

fn run_db_snapshot_isolation() -> Int {
  let path = "orbitdb-suite-mvcc1.wal";
  tdb_cleanup(path);
  var db = db_file_open(path, 4);
  if !db_file_put(&mut db, 1, 100) { return 1; }
  if !db_file_put(&mut db, 2, 200) { return 2; }
  let s1 = db_file_snapshot_begin(&mut db);
  if s1.id <= 0 { return 3; }
  if db_file_snapshot_pins(&db) != 1 { return 4; }
  // Mutate: update 1, delete 2, add 3.
  if !db_file_put(&mut db, 1, 111) { return 5; }
  if !db_file_delete(&mut db, 2) { return 6; }
  if !db_file_put(&mut db, 3, 300) { return 7; }
  // The live view moves on.
  match db_file_get(&db, 1) { None => { return 8; } Some(v) => { if v != 111 { return 9; } } }
  // The pinned view is frozen at capture.
  match db_file_snapshot_get(&db, s1.id, 1) { None => { return 10; } Some(v) => { if v != 100 { return 11; } } }
  match db_file_snapshot_get(&db, s1.id, 2) { None => { return 12; } Some(v) => { if v != 200 { return 13; } } }
  match db_file_snapshot_get(&db, s1.id, 3) { None => {} Some(_) => { return 14; } }
  if db_file_snapshot_count(&db, s1.id) != 2 { return 15; }
  let r1 = db_file_snapshot_range(&db, s1.id, 1, 3);
  if r1.len() != 2 { return 16; }
  if r1[0] != 100 { return 17; }
  if r1[1] != 200 { return 18; }
  // A second pin at the newer version.
  let s2 = db_file_snapshot_begin(&mut db);
  if db_file_snapshot_pins(&db) != 2 { return 19; }
  if db_file_snapshot_count(&db, s2.id) != 2 { return 20; }
  match db_file_snapshot_get(&db, s2.id, 2) { None => {} Some(_) => { return 21; } }
  // Release s1: its reads refuse; s2 is unaffected.
  if !db_file_snapshot_end(&mut db, s1.id) { return 23; }
  match db_file_snapshot_get(&db, s1.id, 1) { None => {} Some(_) => { return 24; } }
  if db_file_snapshot_count(&db, s1.id) != -1 { return 25; }
  let r2 = db_file_snapshot_range(&db, s1.id, 1, 3);
  if r2.len() != 0 { return 26; }
  if db_file_snapshot_end(&mut db, s1.id) { return 27; }
  match db_file_snapshot_get(&db, s2.id, 3) { None => { return 28; } Some(v) => { if v != 300 { return 29; } } }
  if !db_file_snapshot_end(&mut db, s2.id) { return 30; }
  if db_file_snapshot_pins(&db) != 0 { return 31; }
  if db_file_min_pinned_lsn(&db) != -1 { return 32; }
  if s1.lsn < 0 { return 33; }
  tdb_cleanup(path);
  return 0;
}

fn test_db_snapshot_isolation() -> TestResult {
  let rc = run_db_snapshot_isolation();
  if rc == 0 { return assert(true, "db_file snapshot: frozen pin views, live moves on, id guards"); }
  return assert(false, "db_file snapshot: isolation failed rc=" + int_to_str(rc));
}

// COW correctness under the heaviest rebalancing (order 3): two interleaved
// pins vs models captured at their begin, plus live-tree and reopen checks.
fn run_db_snapshot_cow_churn() -> Int {
  let path = "orbitdb-suite-mvcc2.wal";
  tdb_cleanup(path);
  var db = db_file_open(path, 3);
  var model = mvcc_model_new(60);
  var i = 1;
  while i <= 40 {
    if !db_file_put(&mut db, i, i * 10) { return 1; }
    model[i] = i * 10;
    i = i + 1;
  }
  let s1 = db_file_snapshot_begin(&mut db);
  var model1 = mvcc_copy(&model);
  let want1 = mvcc_expected(&model1);
  let got1 = db_file_snapshot_range(&db, s1.id, 1, 60);
  if !mvcc_vec_eq(&got1, &want1) { return 2; }
  var s2_id = 0;
  var model2 = mvcc_model_new(60);
  var have2 = false;
  var r = 777;
  var op = 0;
  while op < 400 {
    r = (r * 1103515245 + 12345) % 2147483648;
    let key = (r % 60) + 1;
    let roll = (r / 60) % 4;
    if roll == 0 {
      let _ = db_file_delete(&mut db, key);
      model[key] = -1;
    } else {
      let v = r % 1000;
      if !db_file_put(&mut db, key, v) { return 3; }
      model[key] = v;
    }
    if op == 200 {
      let s2 = db_file_snapshot_begin(&mut db);
      s2_id = s2.id;
      model2 = mvcc_copy(&model);
      have2 = true;
    }
    op = op + 1;
  }
  // Both pinned views are exact after 400 mutations.
  let want1b = mvcc_expected(&model1);
  let got1b = db_file_snapshot_range(&db, s1.id, 1, 60);
  if !mvcc_vec_eq(&got1b, &want1b) { return 4; }
  if db_file_snapshot_count(&db, s1.id) != want1b.len() { return 5; }
  if !have2 { return 6; }
  let want2 = mvcc_expected(&model2);
  let got2 = db_file_snapshot_range(&db, s2_id, 1, 60);
  if !mvcc_vec_eq(&got2, &want2) { return 7; }
  if db_file_snapshot_count(&db, s2_id) != want2.len() { return 8; }
  if !db_file_snapshot_end(&mut db, s2_id) { return 9; }
  // Live tree matches the live model; s1 still exact after releasing s2.
  let live_want = mvcc_expected(&model);
  let live_got = db_file_range(&db, 1, 60);
  if !mvcc_vec_eq(&live_got, &live_want) { return 10; }
  let got1c = db_file_snapshot_range(&db, s1.id, 1, 60);
  if !mvcc_vec_eq(&got1c, &want1b) { return 11; }
  if !db_file_snapshot_end(&mut db, s1.id) { return 12; }
  // Persist and reopen: same committed state; pins vanish with the handle.
  if db_file_checkpoint(&mut db) < 0 { return 13; }
  var db2 = db_file_open(path, 3);
  let got_after = db_file_range(&db2, 1, 60);
  if !mvcc_vec_eq(&got_after, &live_want) { return 14; }
  if db_file_snapshot_pins(&db2) != 0 { return 15; }
  tdb_cleanup(path);
  return 0;
}

fn test_db_snapshot_cow_churn() -> TestResult {
  let rc = run_db_snapshot_cow_churn();
  if rc == 0 { return assert(true, "db_file snapshot: COW under order-3 churn, two pins exact, reopen clean"); }
  return assert(false, "db_file snapshot: COW churn failed rc=" + int_to_str(rc));
}

fn run_db_snapshot_checkpoint() -> Int {
  let path = "orbitdb-suite-mvcc3.wal";
  tdb_cleanup(path);
  var db = db_file_open(path, 4);
  var i = 1;
  while i <= 20 {
    if !db_file_put(&mut db, i, i * 10) { return 1; }
    i = i + 1;
  }
  if db_file_snap_generation(&db) != 0 { return 2; }
  if db_file_checkpoint(&mut db) < 0 { return 3; }
  if db_file_snap_generation(&db) != 1 { return 4; }
  let s1 = db_file_snapshot_begin(&mut db);
  if s1.generation != 1 { return 5; }
  if db_file_compaction_deferrals(&db) != 0 { return 6; }
  i = 21;
  while i <= 30 {
    if !db_file_put(&mut db, i, i * 10) { return 7; }
    i = i + 1;
  }
  if !db_file_put(&mut db, 1, 999) { return 8; }
  if db_file_checkpoint(&mut db) < 0 { return 9; }
  if db_file_snap_generation(&db) != 2 { return 10; }
  // The pinned view is still the generation-1 content.
  match db_file_snapshot_get(&db, s1.id, 1) { None => { return 11; } Some(v) => { if v != 10 { return 12; } } }
  match db_file_snapshot_get(&db, s1.id, 25) { None => {} Some(_) => { return 13; } }
  if db_file_snapshot_count(&db, s1.id) != 20 { return 14; }
  // The live view has everything.
  if db_file_size(&db) != 30 { return 15; }
  match db_file_get(&db, 1) { None => { return 16; } Some(v) => { if v != 999 { return 17; } } }
  if db_file_min_pinned_lsn(&db) < 0 { return 18; }
  if !db_file_snapshot_end(&mut db, s1.id) { return 19; }
  if db_file_min_pinned_lsn(&db) != -1 { return 20; }
  // Reopen: pins are handle-local; the committed state is intact.
  var db2 = db_file_open(path, 4);
  if db_file_size(&db2) != 30 { return 21; }
  if db_file_snap_generation(&db2) != 2 { return 22; }
  match db_file_get(&db2, 25) { None => { return 23; } Some(v) => { if v != 250 { return 24; } } }
  tdb_cleanup(path);
  return 0;
}

fn test_db_snapshot_checkpoint() -> TestResult {
  let rc = run_db_snapshot_checkpoint();
  if rc == 0 { return assert(true, "db_file snapshot: stable across checkpoints; generation tracked"); }
  return assert(false, "db_file snapshot: checkpoint failed rc=" + int_to_str(rc));
}

fn run_db_savepoint_basic() -> Int {
  let path = "orbitdb-suite-mvcc4.wal";
  tdb_cleanup(path);
  var db = db_file_open(path, 4);
  if !db_file_put(&mut db, 1, 10) { return 1; }
  if !db_file_txn_begin(&mut db) { return 2; }
  if !db_file_txn_put(&mut db, 2, 20) { return 3; }
  if !db_file_txn_put(&mut db, 3, 30) { return 4; }
  if !db_file_txn_savepoint(&mut db) { return 5; }
  if !db_file_txn_savepoint_active(&db) { return 6; }
  if !db_file_txn_put(&mut db, 4, 40) { return 7; }
  if !db_file_txn_delete(&mut db, 2) { return 8; }
  if !db_file_txn_savepoint_restore(&mut db) { return 9; }
  if !db_file_txn_savepoint_active(&db) { return 10; }
  if !db_file_txn_put(&mut db, 5, 50) { return 11; }
  if !db_file_txn_commit(&mut db) { return 12; }
  if db_file_txn_savepoint_active(&db) { return 13; }
  if db_file_size(&db) != 4 { return 14; }
  match db_file_get(&db, 2) { None => { return 15; } Some(v) => { if v != 20 { return 16; } } }
  match db_file_get(&db, 3) { None => { return 17; } Some(v) => { if v != 30 { return 18; } } }
  match db_file_get(&db, 4) { None => {} Some(_) => { return 19; } }
  match db_file_get(&db, 5) { None => { return 20; } Some(v) => { if v != 50 { return 21; } } }
  // Reopen == replay of the spliced window must agree with the buffer.
  var db2 = db_file_open(path, 4);
  if db_file_size(&db2) != 4 { return 22; }
  match db_file_get(&db2, 4) { None => {} Some(_) => { return 23; } }
  // Release path: ops after release survive.
  if !db_file_txn_begin(&mut db2) { return 24; }
  if !db_file_txn_put(&mut db2, 6, 60) { return 25; }
  if !db_file_txn_savepoint(&mut db2) { return 26; }
  if !db_file_txn_put(&mut db2, 7, 70) { return 27; }
  if !db_file_txn_savepoint_release(&mut db2) { return 28; }
  if db_file_txn_savepoint_active(&db2) { return 29; }
  if !db_file_txn_put(&mut db2, 8, 80) { return 30; }
  if !db_file_txn_commit(&mut db2) { return 31; }
  if db_file_size(&db2) != 7 { return 32; }
  match db_file_get(&db2, 7) { None => { return 33; } Some(v) => { if v != 70 { return 34; } } }
  tdb_cleanup(path);
  return 0;
}

fn test_db_savepoint_basic() -> TestResult {
  let rc = run_db_savepoint_basic();
  if rc == 0 { return assert(true, "db_file savepoint: restore trims post-marker ops; commit/reopen exact"); }
  return assert(false, "db_file savepoint: basic failed rc=" + int_to_str(rc));
}

fn run_db_savepoint_guards() -> Int {
  let path = "orbitdb-suite-mvcc5.wal";
  tdb_cleanup(path);
  var db = db_file_open(path, 4);
  if db_file_txn_savepoint(&mut db) { return 1; }
  if db_file_txn_savepoint_restore(&mut db) { return 2; }
  if db_file_txn_savepoint_release(&mut db) { return 3; }
  if db_file_txn_savepoint_active(&db) { return 4; }
  if !db_file_txn_begin(&mut db) { return 5; }
  if db_file_txn_savepoint_restore(&mut db) { return 6; }
  if !db_file_txn_savepoint(&mut db) { return 7; }
  if db_file_txn_savepoint(&mut db) { return 8; }
  if !db_file_txn_savepoint_restore(&mut db) { return 9; }
  if !db_file_txn_savepoint_active(&db) { return 10; }
  if !db_file_txn_savepoint_release(&mut db) { return 11; }
  if db_file_txn_savepoint_release(&mut db) { return 12; }
  if db_file_txn_savepoint_restore(&mut db) { return 13; }
  if !db_file_txn_commit(&mut db) { return 14; }
  if db_file_txn_savepoint_active(&db) { return 15; }
  if db_file_txn_savepoint_restore(&mut db) { return 16; }
  tdb_cleanup(path);
  return 0;
}

fn test_db_savepoint_guards() -> TestResult {
  let rc = run_db_savepoint_guards();
  if rc == 0 { return assert(true, "db_file savepoint: guard matrix (no txn, double begin, release, post-commit)"); }
  return assert(false, "db_file savepoint: guards failed rc=" + int_to_str(rc));
}

fn run_db_savepoint_crash_windows() -> Int {
  let path = "orbitdb-suite-mvcc6.wal";
  tdb_cleanup(path);
  var db = db_file_open(path, 4);
  if !db_file_put(&mut db, 1, 10) { return 1; }
  if !db_file_txn_begin(&mut db) { return 2; }
  if !db_file_txn_put(&mut db, 2, 20) { return 3; }
  if !db_file_txn_savepoint(&mut db) { return 4; }
  if !db_file_txn_put(&mut db, 3, 30) { return 5; }
  if !db_file_txn_delete(&mut db, 1) { return 6; }
  if !db_file_txn_savepoint_restore(&mut db) { return 7; }
  // Crash before commit: the abandoned handle's window is uncommitted, so a
  // fresh open recovers exactly key 1 (restore or not makes no difference).
  var db2 = db_file_open(path, 4);
  if db_file_size(&db2) != 1 { return 8; }
  match db_file_get(&db2, 1) { None => { return 9; } Some(v) => { if v != 10 { return 10; } } }
  match db_file_get(&db2, 2) { None => {} Some(_) => { return 11; } }
  // Commit after a restore applies exactly the kept ops.
  if !db_file_txn_begin(&mut db2) { return 12; }
  if !db_file_txn_put(&mut db2, 2, 20) { return 13; }
  if !db_file_txn_savepoint(&mut db2) { return 14; }
  if !db_file_txn_put(&mut db2, 3, 30) { return 15; }
  if !db_file_txn_savepoint_restore(&mut db2) { return 16; }
  if !db_file_txn_commit(&mut db2) { return 17; }
  var db3 = db_file_open(path, 4);
  if db_file_size(&db3) != 2 { return 18; }
  match db_file_get(&db3, 2) { None => { return 19; } Some(v) => { if v != 20 { return 20; } } }
  match db_file_get(&db3, 3) { None => {} Some(_) => { return 21; } }
  // Two restores then more ops: the final marker set is what commits.
  if !db_file_txn_begin(&mut db3) { return 22; }
  if !db_file_txn_put(&mut db3, 5, 50) { return 23; }
  if !db_file_txn_savepoint(&mut db3) { return 24; }
  if !db_file_txn_put(&mut db3, 6, 60) { return 25; }
  if !db_file_txn_savepoint_restore(&mut db3) { return 26; }
  if !db_file_txn_put(&mut db3, 7, 70) { return 27; }
  if !db_file_txn_savepoint_restore(&mut db3) { return 28; }
  if !db_file_txn_put(&mut db3, 8, 80) { return 29; }
  if !db_file_txn_commit(&mut db3) { return 30; }
  var db4 = db_file_open(path, 4);
  if db_file_size(&db4) != 4 { return 31; }
  match db_file_get(&db4, 5) { None => { return 32; } Some(v) => { if v != 50 { return 33; } } }
  match db_file_get(&db4, 6) { None => {} Some(_) => { return 34; } }
  match db_file_get(&db4, 7) { None => {} Some(_) => { return 35; } }
  match db_file_get(&db4, 8) { None => { return 36; } Some(v) => { if v != 80 { return 37; } } }
  tdb_cleanup(path);
  return 0;
}

fn test_db_savepoint_crash_windows() -> TestResult {
  let rc = run_db_savepoint_crash_windows();
  if rc == 0 { return assert(true, "db_file savepoint: crash windows (uncommitted discarded; restored commit exact)"); }
  return assert(false, "db_file savepoint: crash windows failed rc=" + int_to_str(rc));
}

fn run_db_snapshot_typed() -> Int {
  let path = "orbitdb-suite-mvcc7.wal";
  tdb_cleanup(path);
  var db = db_file_open(path, 4);
  if !db_file_put_typed(&mut db, 7, tdb_row3(1, 2, 3)) { return 1; }
  let s1 = db_file_snapshot_begin(&mut db);
  if !db_file_put_typed(&mut db, 7, tdb_row3(9, 9, 9)) { return 2; }
  if !db_file_put_typed(&mut db, 8, tdb_row3(4, 5, 6)) { return 3; }
  match db_file_snapshot_get_typed(&db, s1.id, 7) {
    None => { return 4; }
    Some(p) => { if p.len() != 3 { return 5; } if p[0] != 1 { return 6; } if p[2] != 3 { return 7; } }
  }
  match db_file_get_typed(&db, 7) {
    None => { return 8; }
    Some(p) => { if p.len() != 3 { return 9; } if p[0] != 9 { return 10; } }
  }
  match db_file_snapshot_get_typed(&db, s1.id, 8) { None => {} Some(_) => { return 11; } }
  if db_file_snapshot_count(&db, s1.id) != 1 { return 12; }
  if db_file_size(&db) != 2 { return 13; }
  if !db_file_snapshot_end(&mut db, s1.id) { return 14; }
  // A pinned payload view also survives a checkpoint while pinned.
  let s2 = db_file_snapshot_begin(&mut db);
  if db_file_checkpoint(&mut db) < 0 { return 15; }
  match db_file_snapshot_get_typed(&db, s2.id, 8) {
    None => { return 16; }
    Some(p) => { if p.len() != 3 { return 17; } if p[0] != 4 { return 18; } }
  }
  tdb_cleanup(path);
  return 0;
}

fn test_db_snapshot_typed() -> TestResult {
  let rc = run_db_snapshot_typed();
  if rc == 0 { return assert(true, "db_file snapshot: typed payloads pinned; survive checkpoint while pinned"); }
  return assert(false, "db_file snapshot: typed failed rc=" + int_to_str(rc));
}

// M1.2 S4 default flip: db_file_open now writes the v2 byte container; a v1
// file opened by default migrates on its next checkpoint; readers keep

fn main() -> Int {
  io.println("=== XIOM DB Conformance: typed_mvcc ===");
  var failed: Int = 0;
  var total: Int = 0;
  let r119 = test_db_typed_roundtrip();
  total = total + 1; failed = failed + report(r119.passed, r119.name);
  let r120 = test_db_typed_checkpoint_v1();
  total = total + 1; failed = failed + report(r120.passed, r120.name);
  let r121 = test_db_typed_checkpoint_v2();
  total = total + 1; failed = failed + report(r121.passed, r121.name);
  let r122 = test_db_typed_budget_and_guards();
  total = total + 1; failed = failed + report(r122.passed, r122.name);
  let r123 = test_db_typed_txn_window_replay();
  total = total + 1; failed = failed + report(r123.passed, r123.name);
  let r124 = test_tuple2_compare();
  total = total + 1; failed = failed + report(r124.passed, r124.name);
  let r125 = test_typed_query_ops();
  total = total + 1; failed = failed + report(r125.passed, r125.name);
  let r126 = test_typed_query_persistence();
  total = total + 1; failed = failed + report(r126.passed, r126.name);
  let r127 = test_db_snapshot_isolation();
  total = total + 1; failed = failed + report(r127.passed, r127.name);
  let r128 = test_db_snapshot_cow_churn();
  total = total + 1; failed = failed + report(r128.passed, r128.name);
  let r129 = test_db_snapshot_checkpoint();
  total = total + 1; failed = failed + report(r129.passed, r129.name);
  let r130 = test_db_savepoint_basic();
  total = total + 1; failed = failed + report(r130.passed, r130.name);
  let r131 = test_db_savepoint_guards();
  total = total + 1; failed = failed + report(r131.passed, r131.name);
  let r132 = test_db_savepoint_crash_windows();
  total = total + 1; failed = failed + report(r132.passed, r132.name);
  let r133 = test_db_snapshot_typed();
  total = total + 1; failed = failed + report(r133.passed, r133.name);
  let passed = total - failed;
  io.println("XIOM DB Conformance [typed_mvcc]: " + int_to_str(passed) + "/" + int_to_str(total) + " passed" + (if failed > 0 { " (" + int_to_str(failed) + " FAILED)" } else { "" }));
  return failed;
}