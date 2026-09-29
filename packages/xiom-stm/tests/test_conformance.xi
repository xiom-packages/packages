// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// XIOM -- xiom.stm conformance tests (20 checks)
// Port task: prove the deterministic software-transactional-memory
// primitives against their documented semantics (SPEC.md): versioned cells,
// transaction state machine, read/write set tracking, optimistic commit
// validation, conflict aborts with reason codes and retry bookkeeping.
//
// Fixtures are built in-test: every test starts with stm_reset(), and all
// state (clock, cells, transactions, sets, statistics) is cleared, so tests
// are order-independent. Expected clock values follow the rule "every
// successful commit advances the clock by exactly one".
// Str equality goes through compare.str_compare (BUG 17 discipline).

module stm_tests
use xiom.io; use xiom.test; use xiom.stm;
use xiom.string;
use xiom.string.compare;

// --------------------------------------------------
//  Result helpers (one consumption per Result value)
// --------------------------------------------------

// True when the Result is Err with exactly the (code, txn, cell, extra)
// quad.
fn err_is(r: Result[Int, StmError], code: Int, txn: Int, cell: Int, extra: Int) -> Bool {
  if r.is_ok { return false; }
  let e: StmError = r.error;
  if e.code != code { return false; }
  if e.txn != txn { return false; }
  if e.cell != cell { return false; }
  return e.extra == extra;
}

// True when the Result is Ok with the given value.
fn ok_is(r: Result[Int, StmError], want: Int) -> Bool {
  if !r.is_ok { return false; }
  let v: Int = r.value;
  return v == want;
}

// Ok value, or -999999 on Err (keeps a broken expectation failing loudly).
fn ok_val(r: Result[Int, StmError]) -> Int {
  if !r.is_ok { return -999999; }
  let v: Int = r.value;
  return v;
}

// Byte-wise Str equality through str_compare (BUG 17 discipline).
fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// True when stm_error_message(code) equals `want` byte-wise.
fn msg_is(code: Int, want: Str) -> Bool {
  return streq(stm_error_message(code), want);
}

// True when stm_abort_reason_message(reason) equals `want` byte-wise.
fn reason_is(reason: Int, want: Str) -> Bool {
  return streq(stm_abort_reason_message(reason), want);
}

// --------------------------------------------------
//  Cells
// --------------------------------------------------

fn t1() -> TestResult {
  stm_reset();
  let c0 = ok_val(stm_cell_new(10));
  let c1 = ok_val(stm_cell_new(20));
  var ok = c0 == 0;
  if c1 != 1 { ok = false; }
  if stm_cell_count() != 2 { ok = false; }
  if !ok_is(stm_cell_value(c0), 10) { ok = false; }
  if !ok_is(stm_cell_value(c1), 20) { ok = false; }
  if !ok_is(stm_cell_version(c0), 0) { ok = false; }
  if !ok_is(stm_cell_commit_count(c0), 0) { ok = false; }
  if stm_clock() != 0 { ok = false; }
  return assert(ok, "cells are created with committed values at version 0");
}

// --------------------------------------------------
//  Transaction state machine
// --------------------------------------------------

fn t2() -> TestResult {
  stm_reset();
  let t = ok_val(stm_txn_begin());
  var ok = t == 0;
  if !ok_is(stm_txn_state(t), 1) { ok = false; }
  if !ok_is(stm_txn_start_version(t), 0) { ok = false; }
  if !ok_is(stm_txn_attempt(t), 1) { ok = false; }
  if !ok_is(stm_txn_retry_count(t), 0) { ok = false; }
  if !ok_is(stm_txn_abort_reason(t), 0) { ok = false; }
  if !ok_is(stm_txn_conflict_cell(t), -1) { ok = false; }
  if !ok_is(stm_txn_read_set_size(t), 0) { ok = false; }
  if !ok_is(stm_txn_write_set_size(t), 0) { ok = false; }
  if !ok_is(stm_commit(t), 1) { ok = false; }
  if stm_clock() != 1 { ok = false; }
  if !ok_is(stm_txn_state(t), 2) { ok = false; }
  if !err_is(stm_commit(t), 4, t, -1, 2) { ok = false; }
  if !err_is(stm_abort(t), 4, t, -1, 2) { ok = false; }
  if !err_is(stm_retry(t), 4, t, -1, 2) { ok = false; }
  return assert(ok, "state machine: begin, empty commit, terminal states reject ops");
}

fn t3() -> TestResult {
  stm_reset();
  let c0 = ok_val(stm_cell_new(5));
  let c1 = ok_val(stm_cell_new(7));
  let t = ok_val(stm_txn_begin());
  var ok = ok_val(stm_read(t, c0)) == 5;
  if ok_val(stm_read(t, c0)) != 5 { ok = false; }
  if !ok_is(stm_txn_read_set_size(t), 1) { ok = false; }
  if ok_val(stm_read(t, c1)) != 7 { ok = false; }
  if !ok_is(stm_txn_read_set_size(t), 2) { ok = false; }
  if !ok_is(stm_txn_write_set_size(t), 0) { ok = false; }
  if !ok_is(stm_commit(t), 1) { ok = false; }
  if stm_reads() != 3 { ok = false; }
  return assert(ok, "first read records the version; re-reads dedupe");
}

fn t4() -> TestResult {
  stm_reset();
  let c0 = ok_val(stm_cell_new(5));
  let t = ok_val(stm_txn_begin());
  var ok = ok_is(stm_write(t, c0, 99), 1);
  if ok_val(stm_read(t, c0)) != 99 { ok = false; }
  if !ok_is(stm_txn_read_set_size(t), 0) { ok = false; }
  if !ok_is(stm_write(t, c0, 100), 1) { ok = false; }
  if ok_val(stm_read(t, c0)) != 100 { ok = false; }
  if !ok_is(stm_txn_write_set_size(t), 1) { ok = false; }
  if !ok_is(stm_commit(t), 1) { ok = false; }
  if !ok_is(stm_cell_value(c0), 100) { ok = false; }
  if !ok_is(stm_cell_version(c0), 1) { ok = false; }
  if !ok_is(stm_cell_commit_count(c0), 1) { ok = false; }
  return assert(ok, "write buffering with read-your-writes");
}

fn t5() -> TestResult {
  stm_reset();
  let c0 = ok_val(stm_cell_new(1));
  let c1 = ok_val(stm_cell_new(2));
  let t = ok_val(stm_txn_begin());
  var ok = ok_is(stm_write(t, c0, 11), 1);
  if !ok_is(stm_write(t, c1, 22), 2) { ok = false; }
  if !ok_is(stm_commit(t), 1) { ok = false; }
  if !ok_is(stm_cell_value(c0), 11) { ok = false; }
  if !ok_is(stm_cell_value(c1), 22) { ok = false; }
  if !ok_is(stm_cell_version(c0), 1) { ok = false; }
  if !ok_is(stm_cell_version(c1), 1) { ok = false; }
  let t2 = ok_val(stm_txn_begin());
  if !ok_is(stm_write(t2, c0, 12), 1) { ok = false; }
  if !ok_is(stm_commit(t2), 2) { ok = false; }
  if !ok_is(stm_cell_version(c0), 2) { ok = false; }
  if !ok_is(stm_cell_version(c1), 1) { ok = false; }
  if stm_commits() != 2 { ok = false; }
  return assert(ok, "one commit version applies to every buffered write");
}

// --------------------------------------------------
//  Conflict detection and aborts
// --------------------------------------------------

fn t6() -> TestResult {
  stm_reset();
  let c0 = ok_val(stm_cell_new(5));
  let c1 = ok_val(stm_cell_new(6));
  let ta = ok_val(stm_txn_begin());
  let tb = ok_val(stm_txn_begin());
  var ok = ok_val(stm_read(ta, c0)) == 5;
  if !ok_is(stm_write(tb, c0, 50), 1) { ok = false; }
  if !ok_is(stm_commit(tb), 1) { ok = false; }
  if !ok_is(stm_write(ta, c1, 77), 1) { ok = false; }
  if !err_is(stm_commit(ta), 7, ta, c0, 1) { ok = false; }
  if !ok_is(stm_txn_state(ta), 3) { ok = false; }
  if !ok_is(stm_txn_abort_reason(ta), 1) { ok = false; }
  if !ok_is(stm_txn_conflict_cell(ta), c0) { ok = false; }
  if !ok_is(stm_cell_value(c0), 50) { ok = false; }
  if !ok_is(stm_cell_value(c1), 6) { ok = false; }
  if !ok_is(stm_cell_version(c1), 0) { ok = false; }
  if !ok_is(stm_cell_commit_count(c1), 0) { ok = false; }
  if stm_clock() != 1 { ok = false; }
  if stm_conflicts() != 1 { ok = false; }
  if stm_aborts() != 1 { ok = false; }
  return assert(ok, "read conflict aborts commit and applies nothing");
}

fn t7() -> TestResult {
  stm_reset();
  let c0 = ok_val(stm_cell_new(5));
  let ta = ok_val(stm_txn_begin());
  let tb = ok_val(stm_txn_begin());
  var ok = ok_is(stm_write(ta, c0, 11), 1);
  if !ok_is(stm_write(tb, c0, 22), 1) { ok = false; }
  if !ok_is(stm_commit(tb), 1) { ok = false; }
  if !err_is(stm_commit(ta), 7, ta, c0, 2) { ok = false; }
  if !ok_is(stm_txn_abort_reason(ta), 2) { ok = false; }
  if !ok_is(stm_txn_conflict_cell(ta), c0) { ok = false; }
  if !ok_is(stm_cell_value(c0), 22) { ok = false; }
  if !ok_is(stm_cell_version(c0), 1) { ok = false; }
  if stm_user_aborts() != 0 { ok = false; }
  return assert(ok, "blind-write conflicts are detected at commit (write-write)");
}

fn t8() -> TestResult {
  stm_reset();
  let c0 = ok_val(stm_cell_new(9));
  let t = ok_val(stm_txn_begin());
  var ok = ok_val(stm_read(t, c0)) == 9;
  if !ok_is(stm_commit(t), 1) { ok = false; }
  if stm_clock() != 1 { ok = false; }
  if !ok_is(stm_cell_version(c0), 0) { ok = false; }
  if !ok_is(stm_cell_commit_count(c0), 0) { ok = false; }
  if stm_commits() != 1 { ok = false; }
  return assert(ok, "read-only commits advance the clock but write no cell");
}

// --------------------------------------------------
//  Retry bookkeeping
// --------------------------------------------------

fn t9() -> TestResult {
  stm_reset();
  let c0 = ok_val(stm_cell_new(5));
  let t = ok_val(stm_txn_begin());
  var ok = ok_val(stm_read(t, c0)) == 5;
  if !ok_is(stm_txn_read_set_size(t), 1) { ok = false; }
  if !ok_is(stm_abort(t), 3) { ok = false; }
  if !ok_is(stm_txn_state(t), 3) { ok = false; }
  if !ok_is(stm_txn_abort_reason(t), 3) { ok = false; }
  if !ok_is(stm_retry(t), 2) { ok = false; }
  if !ok_is(stm_txn_state(t), 1) { ok = false; }
  if !ok_is(stm_txn_attempt(t), 2) { ok = false; }
  if !ok_is(stm_txn_retry_count(t), 1) { ok = false; }
  if !ok_is(stm_txn_read_set_size(t), 0) { ok = false; }
  if !ok_is(stm_txn_abort_reason(t), 0) { ok = false; }
  if !ok_is(stm_abort(t), 3) { ok = false; }
  if !ok_is(stm_retry(t), 3) { ok = false; }
  if !ok_is(stm_abort(t), 3) { ok = false; }
  if !ok_is(stm_retry(t), 4) { ok = false; }
  if !ok_is(stm_abort(t), 3) { ok = false; }
  if !ok_is(stm_retry(t), 5) { ok = false; }
  if !ok_is(stm_abort(t), 3) { ok = false; }
  if !err_is(stm_retry(t), 8, t, -1, 4) { ok = false; }
  if !ok_is(stm_txn_state(t), 3) { ok = false; }
  if !ok_is(stm_txn_retry_count(t), 4) { ok = false; }
  if !ok_is(stm_txn_attempt(t), 5) { ok = false; }
  if stm_retries() != 4 { ok = false; }
  if stm_user_aborts() != 5 { ok = false; }
  return assert(ok, "explicit abort and the deterministic retry budget");
}

fn t10() -> TestResult {
  stm_reset();
  let c0 = ok_val(stm_cell_new(5));
  let ta = ok_val(stm_txn_begin());
  let tb = ok_val(stm_txn_begin());
  var ok = ok_val(stm_read(ta, c0)) == 5;
  if !ok_is(stm_write(tb, c0, 50), 1) { ok = false; }
  if !ok_is(stm_commit(tb), 1) { ok = false; }
  if !err_is(stm_commit(ta), 7, ta, c0, 1) { ok = false; }
  if !ok_is(stm_retry(ta), 2) { ok = false; }
  if ok_val(stm_read(ta, c0)) != 50 { ok = false; }
  if !ok_is(stm_write(ta, c0, 60), 1) { ok = false; }
  if !ok_is(stm_commit(ta), 2) { ok = false; }
  if !ok_is(stm_cell_value(c0), 60) { ok = false; }
  if !ok_is(stm_cell_version(c0), 2) { ok = false; }
  if stm_commits() != 2 { ok = false; }
  if stm_conflicts() != 1 { ok = false; }
  if stm_retries() != 1 { ok = false; }
  return assert(ok, "retry after a conflict re-reads fresh state and commits");
}

// --------------------------------------------------
//  Validation, limits and dumps
// --------------------------------------------------

fn t11() -> TestResult {
  stm_reset();
  let c0 = ok_val(stm_cell_new(1));
  let t = ok_val(stm_txn_begin());
  var ok = err_is(stm_read(5, c0), 3, 5, c0, -1);
  if !err_is(stm_read(t, 5), 2, t, 5, -1) { ok = false; }
  if !err_is(stm_read(t, -1), 2, t, -1, -1) { ok = false; }
  if !err_is(stm_write(t, 99, 1), 2, t, 99, -1) { ok = false; }
  if !err_is(stm_write(-1, c0, 1), 3, -1, c0, -1) { ok = false; }
  if !err_is(stm_commit(7), 3, 7, -1, -1) { ok = false; }
  if !err_is(stm_txn_state(-1), 3, -1, -1, -1) { ok = false; }
  if !err_is(stm_retry(3), 3, 3, -1, -1) { ok = false; }
  if !err_is(stm_cell_value(-1), 2, -1, -1, -1) { ok = false; }
  if !err_is(stm_cell_version(1), 2, -1, 1, -1) { ok = false; }
  if !ok_is(stm_txn_state(t), 1) { ok = false; }
  return assert(ok, "invalid cell and transaction handles are rejected");
}

fn t12() -> TestResult {
  stm_reset();
  var ok = true;
  var i = 0;
  while i < 65 {
    let cr = stm_cell_new(i * 3);
    if !cr.is_ok { ok = false; }
    i = i + 1;
  }
  let t = ok_val(stm_txn_begin());
  i = 0;
  while i < 64 {
    let r = stm_read(t, i);
    if !r.is_ok { ok = false; }
    i = i + 1;
  }
  if !ok_is(stm_txn_read_set_size(t), 64) { ok = false; }
  if !err_is(stm_read(t, 64), 5, t, 64, 64) { ok = false; }
  if !ok_is(stm_commit(t), 1) { ok = false; }
  if !ok_is(stm_txn_read_set_size(t), 64) { ok = false; }
  return assert(ok, "read set capacity is enforced per transaction");
}

fn t13() -> TestResult {
  stm_reset();
  var ok = true;
  var i = 0;
  while i < 65 {
    let cr = stm_cell_new(0);
    if !cr.is_ok { ok = false; }
    i = i + 1;
  }
  let t = ok_val(stm_txn_begin());
  i = 0;
  while i < 64 {
    let w = stm_write(t, i, i + 1);
    if !w.is_ok { ok = false; }
    i = i + 1;
  }
  if !ok_is(stm_txn_write_set_size(t), 64) { ok = false; }
  if !err_is(stm_write(t, 64, 1), 6, t, 64, 64) { ok = false; }
  if !ok_is(stm_commit(t), 1) { ok = false; }
  if !ok_is(stm_cell_value(0), 1) { ok = false; }
  if !ok_is(stm_cell_value(63), 64) { ok = false; }
  if !ok_is(stm_cell_value(64), 0) { ok = false; }
  return assert(ok, "write set capacity is enforced and applied in order");
}

fn t14() -> TestResult {
  stm_reset();
  var ok = true;
  var i = 0;
  while i < 1024 {
    let cr = stm_cell_new(i);
    if !cr.is_ok { ok = false; }
    i = i + 1;
  }
  if !err_is(stm_cell_new(1), 1, -1, -1, 1024) { ok = false; }
  if stm_cell_count() != 1024 { ok = false; }
  i = 0;
  while i < 1024 {
    let tr = stm_txn_begin();
    if !tr.is_ok { ok = false; }
    i = i + 1;
  }
  if !err_is(stm_txn_begin(), 9, -1, -1, 1024) { ok = false; }
  if stm_txn_count() != 1024 { ok = false; }
  if stm_max_cells() != 1024 { ok = false; }
  if stm_max_txns() != 1024 { ok = false; }
  if stm_max_retries() != 4 { ok = false; }
  if stm_max_read_set_entries() != 64 { ok = false; }
  if stm_max_write_set_entries() != 64 { ok = false; }
  return assert(ok, "cell and transaction capacity limits");
}

fn t15() -> TestResult {
  stm_reset();
  let c0 = ok_val(stm_cell_new(5));
  let c1 = ok_val(stm_cell_new(6));
  let ta = ok_val(stm_txn_begin());
  let tb = ok_val(stm_txn_begin());
  var ok = ok_val(stm_read(ta, c0)) == 5;
  if !ok_is(stm_write(ta, c1, 77), 1) { ok = false; }
  if !ok_is(stm_write(tb, c0, 50), 1) { ok = false; }
  if !ok_is(stm_commit(tb), 1) { ok = false; }
  if !err_is(stm_commit(ta), 7, ta, c0, 1) { ok = false; }
  if !err_is(stm_read(ta, c0), 4, ta, c0, 3) { ok = false; }
  if !err_is(stm_write(ta, c0, 1), 4, ta, c0, 3) { ok = false; }
  if !err_is(stm_abort(ta), 4, ta, -1, 3) { ok = false; }
  if !err_is(stm_commit(ta), 4, ta, -1, 3) { ok = false; }
  if !ok_is(stm_txn_read_set_size(ta), 1) { ok = false; }
  if !ok_is(stm_txn_write_set_size(ta), 1) { ok = false; }
  if !ok_is(stm_retry(ta), 2) { ok = false; }
  if !ok_is(stm_txn_abort_reason(ta), 0) { ok = false; }
  if !ok_is(stm_commit(ta), 2) { ok = false; }
  return assert(ok, "aborted transactions reject reads, writes and commits");
}

fn t16() -> TestResult {
  stm_reset();
  let c0 = ok_val(stm_cell_new(5));
  let c1 = ok_val(stm_cell_new(6));
  let t = ok_val(stm_txn_begin());
  var ok = ok_val(stm_read(t, c0)) == 5;
  if !ok_is(stm_write(t, c1, 66), 1) { ok = false; }
  let cd = stm_cell_dump();
  if !str_contains(cd, "n=2") { ok = false; }
  if !str_contains(cd, "clock=0") { ok = false; }
  if !str_contains(cd, "c0[v=5 ver=0 commits=0]") { ok = false; }
  if !str_contains(cd, "c1[v=6 ver=0 commits=0]") { ok = false; }
  let td = stm_txn_dump(t);
  if !str_contains(td, "state=1") { ok = false; }
  if !str_contains(td, "attempt=1") { ok = false; }
  if !str_contains(td, "retries=0") { ok = false; }
  if !str_contains(td, "start=0") { ok = false; }
  if !str_contains(td, "rs=1") { ok = false; }
  if !str_contains(td, "ws=1") { ok = false; }
  if !str_contains(td, "abort=0") { ok = false; }
  if !str_contains(td, "conflict=-1") { ok = false; }
  let sd = stm_stats_dump();
  if !str_contains(sd, "commits=0") { ok = false; }
  if !str_contains(sd, "reads=1") { ok = false; }
  if !str_contains(sd, "writes=1") { ok = false; }
  if !str_contains(sd, "user_aborts=0") { ok = false; }
  let d = stm_dump();
  if !str_contains(d, "cells[") { ok = false; }
  if !str_contains(d, "stats[") { ok = false; }
  if !streq(stm_txn_dump(9), "txn[invalid]") { ok = false; }
  return assert(ok, "state dumps pin structure and counters");
}

fn t17() -> TestResult {
  var ok = msg_is(1, "stm: cell capacity exceeded");
  if !msg_is(2, "stm: invalid cell id") { ok = false; }
  if !msg_is(3, "stm: invalid transaction id") { ok = false; }
  if !msg_is(4, "stm: transaction is not active") { ok = false; }
  if !msg_is(5, "stm: read set is full") { ok = false; }
  if !msg_is(6, "stm: write set is full") { ok = false; }
  if !msg_is(7, "stm: transaction conflict") { ok = false; }
  if !msg_is(8, "stm: retry limit reached") { ok = false; }
  if !msg_is(9, "stm: transaction capacity exceeded") { ok = false; }
  if !msg_is(0, "stm: unknown error") { ok = false; }
  if !msg_is(99, "stm: unknown error") { ok = false; }
  if !reason_is(0, "stm: no abort") { ok = false; }
  if !reason_is(1, "stm: read conflict") { ok = false; }
  if !reason_is(2, "stm: write conflict") { ok = false; }
  if !reason_is(3, "stm: user abort") { ok = false; }
  if !reason_is(42, "stm: unknown abort reason") { ok = false; }
  return assert(ok, "error and abort reason catalogs are pinned");
}

fn t18() -> TestResult {
  stm_reset();
  let c0 = ok_val(stm_cell_new(5));
  let t1 = ok_val(stm_txn_begin());
  var ok = ok_val(stm_read(t1, c0)) == 5;
  if !ok_is(stm_write(t1, c0, 6), 1) { ok = false; }
  if !ok_is(stm_commit(t1), 1) { ok = false; }
  let t2 = ok_val(stm_txn_begin());
  let t3 = ok_val(stm_txn_begin());
  if ok_val(stm_read(t2, c0)) != 6 { ok = false; }
  if !ok_is(stm_write(t3, c0, 7), 1) { ok = false; }
  if !ok_is(stm_commit(t3), 2) { ok = false; }
  if !ok_is(stm_write(t2, c0, 8), 1) { ok = false; }
  if !err_is(stm_commit(t2), 7, t2, c0, 1) { ok = false; }
  if !ok_is(stm_retry(t2), 2) { ok = false; }
  if ok_val(stm_read(t2, c0)) != 7 { ok = false; }
  if !ok_is(stm_write(t2, c0, 9), 1) { ok = false; }
  if !ok_is(stm_commit(t2), 3) { ok = false; }
  if stm_commits() != 3 { ok = false; }
  if stm_aborts() != 1 { ok = false; }
  if stm_conflicts() != 1 { ok = false; }
  if stm_retries() != 1 { ok = false; }
  if stm_reads() != 3 { ok = false; }
  if stm_writes() != 4 { ok = false; }
  if stm_user_aborts() != 0 { ok = false; }
  if !ok_is(stm_cell_value(c0), 9) { ok = false; }
  if !ok_is(stm_cell_version(c0), 3) { ok = false; }
  return assert(ok, "statistics accumulate deterministically");
}

fn t19() -> TestResult {
  stm_reset();
  let c0 = ok_val(stm_cell_new(10));
  let tx = ok_val(stm_txn_begin());
  let ty = ok_val(stm_txn_begin());
  var ok = ok_val(stm_read(tx, c0)) == 10;
  if ok_val(stm_read(ty, c0)) != 10 { ok = false; }
  if !ok_is(stm_write(ty, c0, 20), 1) { ok = false; }
  if !ok_is(stm_commit(ty), 1) { ok = false; }
  if ok_val(stm_read(tx, c0)) != 20 { ok = false; }
  if !err_is(stm_commit(tx), 7, tx, c0, 1) { ok = false; }
  if !ok_is(stm_cell_value(c0), 20) { ok = false; }
  if stm_commits() != 1 { ok = false; }
  if stm_conflicts() != 1 { ok = false; }
  return assert(ok, "interleaved transactions observe latest committed values");
}

fn t20() -> TestResult {
  stm_reset();
  let c0 = ok_val(stm_cell_new(0));
  var ok = true;
  var k = 0;
  while k < 40 {
    let ta = ok_val(stm_txn_begin());
    let tb = ok_val(stm_txn_begin());
    if ok_val(stm_read(ta, c0)) != k { ok = false; }
    if !ok_is(stm_write(tb, c0, k + 1), 1) { ok = false; }
    if !ok_is(stm_commit(tb), 2 * k + 1) { ok = false; }
    if !err_is(stm_commit(ta), 7, ta, c0, 1) { ok = false; }
    if !ok_is(stm_retry(ta), 2) { ok = false; }
    if ok_val(stm_read(ta, c0)) != k + 1 { ok = false; }
    if !ok_is(stm_commit(ta), 2 * k + 2) { ok = false; }
    k = k + 1;
  }
  if !ok_is(stm_cell_value(c0), 40) { ok = false; }
  if stm_clock() != 80 { ok = false; }
  if stm_commits() != 80 { ok = false; }
  if stm_aborts() != 40 { ok = false; }
  if stm_conflicts() != 40 { ok = false; }
  if stm_retries() != 40 { ok = false; }
  if stm_reads() != 80 { ok = false; }
  if stm_writes() != 40 { ok = false; }
  if !ok_is(stm_cell_version(c0), 79) { ok = false; }
  if !ok_is(stm_cell_commit_count(c0), 40) { ok = false; }
  return assert(ok, "stress: 40 conflict/retry/commit cycles stay consistent");
}

// --------------------------------------------------
//  Harness
// --------------------------------------------------

fn main() -> Int {
  io.println("=== xiom.stm conformance tests ===");
  var failed: Int = 0;
  let r1 = t1();
  if r1.passed { io.println("  [PASS] " + r1.name); } else { io.println("  [FAIL] " + r1.name); failed = failed + 1; }
  let r2 = t2();
  if r2.passed { io.println("  [PASS] " + r2.name); } else { io.println("  [FAIL] " + r2.name); failed = failed + 1; }
  let r3 = t3();
  if r3.passed { io.println("  [PASS] " + r3.name); } else { io.println("  [FAIL] " + r3.name); failed = failed + 1; }
  let r4 = t4();
  if r4.passed { io.println("  [PASS] " + r4.name); } else { io.println("  [FAIL] " + r4.name); failed = failed + 1; }
  let r5 = t5();
  if r5.passed { io.println("  [PASS] " + r5.name); } else { io.println("  [FAIL] " + r5.name); failed = failed + 1; }
  let r6 = t6();
  if r6.passed { io.println("  [PASS] " + r6.name); } else { io.println("  [FAIL] " + r6.name); failed = failed + 1; }
  let r7 = t7();
  if r7.passed { io.println("  [PASS] " + r7.name); } else { io.println("  [FAIL] " + r7.name); failed = failed + 1; }
  let r8 = t8();
  if r8.passed { io.println("  [PASS] " + r8.name); } else { io.println("  [FAIL] " + r8.name); failed = failed + 1; }
  let r9 = t9();
  if r9.passed { io.println("  [PASS] " + r9.name); } else { io.println("  [FAIL] " + r9.name); failed = failed + 1; }
  let r10 = t10();
  if r10.passed { io.println("  [PASS] " + r10.name); } else { io.println("  [FAIL] " + r10.name); failed = failed + 1; }
  let r11 = t11();
  if r11.passed { io.println("  [PASS] " + r11.name); } else { io.println("  [FAIL] " + r11.name); failed = failed + 1; }
  let r12 = t12();
  if r12.passed { io.println("  [PASS] " + r12.name); } else { io.println("  [FAIL] " + r12.name); failed = failed + 1; }
  let r13 = t13();
  if r13.passed { io.println("  [PASS] " + r13.name); } else { io.println("  [FAIL] " + r13.name); failed = failed + 1; }
  let r14 = t14();
  if r14.passed { io.println("  [PASS] " + r14.name); } else { io.println("  [FAIL] " + r14.name); failed = failed + 1; }
  let r15 = t15();
  if r15.passed { io.println("  [PASS] " + r15.name); } else { io.println("  [FAIL] " + r15.name); failed = failed + 1; }
  let r16 = t16();
  if r16.passed { io.println("  [PASS] " + r16.name); } else { io.println("  [FAIL] " + r16.name); failed = failed + 1; }
  let r17 = t17();
  if r17.passed { io.println("  [PASS] " + r17.name); } else { io.println("  [FAIL] " + r17.name); failed = failed + 1; }
  let r18 = t18();
  if r18.passed { io.println("  [PASS] " + r18.name); } else { io.println("  [FAIL] " + r18.name); failed = failed + 1; }
  let r19 = t19();
  if r19.passed { io.println("  [PASS] " + r19.name); } else { io.println("  [FAIL] " + r19.name); failed = failed + 1; }
  let r20 = t20();
  if r20.passed { io.println("  [PASS] " + r20.name); } else { io.println("  [FAIL] " + r20.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.stm: all tests passed");
  } else {
    io.println("xiom.stm: tests failed");
  }
  return failed;
}
