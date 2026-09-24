// XIOM -- xiom.transaction conformance tests (22 checks)
// Port task: prove the pure-XIOM xiom.transaction module against its
// documented lifecycle, savepoint semantics and error catalog.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Coverage: defaults, begin idempotence, add_op gating, commit/rollback
// success and error paths, savepoint creation/ordering/marks, duplicate
// re-anchoring, rollback_to tail discard and repeatability, unknown savepoint
// errors, savepoint destruction after the rollback target, release, begin
// resets from committed and rolled_back, the pinned 20-op long sequence and
// the exact error catalog.
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every comparison
// below is routed through streq/sp_is/err_msg_is instead of `==`.

module transaction_tests
use xiom.io; use xiom.test; use xiom.transaction;
use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// Read-only operations are wrapped in small helpers that take `&mut`, so a
// `&local` read call is never followed by a `&mut local` call in the same
// function body (advisory E001). Each helper calls the real `&`-based API.

fn state_of(t: &mut Txn) -> Int {
  return txn_state(t);
}

fn ops_of(t: &mut Txn) -> Int {
  return txn_op_count(t);
}

fn sp_count(t: &mut Txn) -> Int {
  return txn_savepoint_count(t);
}

fn sp_name(t: &mut Txn, i: Int) -> Str {
  return txn_savepoint_name(t, i);
}

fn sp_is(t: &mut Txn, i: Int, want: Str) -> Bool {
  return streq(sp_name(t, i), want);
}

fn mark_of(t: &mut Txn, name: Str) -> Int {
  return txn_mark(t, name);
}

// Result-channel helpers: exact Ok values and exact Err messages.

fn err_msg_is(r: Result[Int, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn commit_is(t: &mut Txn, want: Int) -> Bool {
  let r = txn_commit(t);
  match r {
    Ok(v) => { return v == want; },
    Err(_) => { return false; },
  }
  return false;
}

fn commit_err_is(t: &mut Txn, want: Str) -> Bool {
  return err_msg_is(txn_commit(t), want);
}

fn rollback_is(t: &mut Txn, want: Int) -> Bool {
  let r = txn_rollback(t);
  match r {
    Ok(v) => { return v == want; },
    Err(_) => { return false; },
  }
  return false;
}

fn rollback_err_is(t: &mut Txn, want: Str) -> Bool {
  return err_msg_is(txn_rollback(t), want);
}

fn rollback_to_is(t: &mut Txn, name: Str, want: Int) -> Bool {
  let r = txn_rollback_to(t, name);
  match r {
    Ok(v) => { return v == want; },
    Err(_) => { return false; },
  }
  return false;
}

fn rollback_to_err_is(t: &mut Txn, name: Str, want: Str) -> Bool {
  return err_msg_is(txn_rollback_to(t, name), want);
}

fn t1() -> TestResult {
  var t = txn_new();
  var ok = state_of(&mut t) == 0;
  if ops_of(&mut t) != 0 { ok = false; }
  if sp_count(&mut t) != 0 { ok = false; }
  if mark_of(&mut t, "nope") != -1 { ok = false; }
  if !streq(sp_name(&mut t, 0), "") { ok = false; }
  return assert(ok, "txn_new starts idle with zero ops and no savepoints");
}

fn t2() -> TestResult {
  var t = txn_new();
  var ok = txn_begin(&mut t);
  if state_of(&mut t) != 1 { ok = false; }
  if ops_of(&mut t) != 0 { ok = false; }
  if sp_count(&mut t) != 0 { ok = false; }
  return assert(ok, "begin moves idle to active");
}

fn t3() -> TestResult {
  var t = txn_new();
  txn_begin(&mut t);
  txn_add_op(&mut t);
  txn_add_op(&mut t);
  txn_savepoint(&mut t, "sp");
  var ok = !txn_begin(&mut t);
  if state_of(&mut t) != 1 { ok = false; }
  if ops_of(&mut t) != 2 { ok = false; }
  if sp_count(&mut t) != 1 { ok = false; }
  if mark_of(&mut t, "sp") != 2 { ok = false; }
  return assert(ok, "begin while active returns false and changes nothing");
}

fn t4() -> TestResult {
  var t = txn_new();
  var ok = !txn_add_op(&mut t);
  if ops_of(&mut t) != 0 { ok = false; }
  txn_begin(&mut t);
  if !txn_add_op(&mut t) { ok = false; }
  if !txn_add_op(&mut t) { ok = false; }
  if ops_of(&mut t) != 2 { ok = false; }
  if !commit_is(&mut t, 2) { ok = false; }
  if txn_add_op(&mut t) { ok = false; }
  if ops_of(&mut t) != 2 { ok = false; }
  txn_begin(&mut t);
  if !txn_add_op(&mut t) { ok = false; }
  if !rollback_is(&mut t, 1) { ok = false; }
  if txn_add_op(&mut t) { ok = false; }
  if ops_of(&mut t) != 0 { ok = false; }
  return assert(ok, "add_op increments only while active");
}

fn t5() -> TestResult {
  var t = txn_new();
  txn_begin(&mut t);
  txn_add_op(&mut t);
  txn_add_op(&mut t);
  txn_add_op(&mut t);
  var ok = commit_is(&mut t, 3);
  if state_of(&mut t) != 2 { ok = false; }
  if ops_of(&mut t) != 3 { ok = false; }
  return assert(ok, "commit returns the op count, keeps it, and enters committed");
}

fn t6() -> TestResult {
  var t = txn_new();
  var ok = commit_err_is(&mut t, "transaction: commit requires an active transaction");
  if state_of(&mut t) != 0 { ok = false; }
  txn_begin(&mut t);
  txn_add_op(&mut t);
  if !commit_is(&mut t, 1) { ok = false; }
  if !commit_err_is(&mut t, "transaction: commit requires an active transaction") { ok = false; }
  if state_of(&mut t) != 2 { ok = false; }
  if ops_of(&mut t) != 1 { ok = false; }
  if !txn_begin(&mut t) { ok = false; }
  txn_add_op(&mut t);
  if !rollback_is(&mut t, 1) { ok = false; }
  if !commit_err_is(&mut t, "transaction: commit requires an active transaction") { ok = false; }
  if state_of(&mut t) != 3 { ok = false; }
  return assert(ok, "commit errors on idle, committed and rolled-back states");
}

fn t7() -> TestResult {
  var t = txn_new();
  txn_begin(&mut t);
  txn_add_op(&mut t);
  txn_add_op(&mut t);
  txn_savepoint(&mut t, "keep");
  txn_add_op(&mut t);
  var ok = rollback_is(&mut t, 3);
  if state_of(&mut t) != 3 { ok = false; }
  if ops_of(&mut t) != 0 { ok = false; }
  if sp_count(&mut t) != 1 { ok = false; }
  return assert(ok, "rollback returns the discarded count and resets ops");
}

fn t8() -> TestResult {
  var t = txn_new();
  var ok = rollback_err_is(&mut t, "transaction: rollback requires an active transaction");
  if state_of(&mut t) != 0 { ok = false; }
  txn_begin(&mut t);
  txn_add_op(&mut t);
  txn_add_op(&mut t);
  if !commit_is(&mut t, 2) { ok = false; }
  if !rollback_err_is(&mut t, "transaction: rollback requires an active transaction") { ok = false; }
  if state_of(&mut t) != 2 { ok = false; }
  if ops_of(&mut t) != 2 { ok = false; }
  if !txn_begin(&mut t) { ok = false; }
  if !rollback_is(&mut t, 0) { ok = false; }
  if !rollback_err_is(&mut t, "transaction: rollback requires an active transaction") { ok = false; }
  if state_of(&mut t) != 3 { ok = false; }
  return assert(ok, "rollback errors on idle, committed and rolled-back states");
}

fn t9() -> TestResult {
  var t = txn_new();
  var ok = !txn_savepoint(&mut t, "sp");
  if sp_count(&mut t) != 0 { ok = false; }
  txn_begin(&mut t);
  if !commit_is(&mut t, 0) { ok = false; }
  if txn_savepoint(&mut t, "sp") { ok = false; }
  if sp_count(&mut t) != 0 { ok = false; }
  txn_begin(&mut t);
  if !rollback_is(&mut t, 0) { ok = false; }
  if txn_savepoint(&mut t, "sp") { ok = false; }
  if sp_count(&mut t) != 0 { ok = false; }
  return assert(ok, "savepoint requires an active transaction");
}

fn t10() -> TestResult {
  var t = txn_new();
  txn_begin(&mut t);
  txn_add_op(&mut t);
  var ok = !txn_savepoint(&mut t, "");
  if sp_count(&mut t) != 0 { ok = false; }
  if mark_of(&mut t, "") != -1 { ok = false; }
  if !txn_savepoint(&mut t, "ok") { ok = false; }
  if sp_count(&mut t) != 1 { ok = false; }
  if mark_of(&mut t, "ok") != 1 { ok = false; }
  return assert(ok, "empty savepoint name is rejected");
}

fn t11() -> TestResult {
  var t = txn_new();
  txn_begin(&mut t);
  txn_add_op(&mut t);
  txn_savepoint(&mut t, "a");
  txn_add_op(&mut t);
  txn_add_op(&mut t);
  txn_savepoint(&mut t, "b");
  var ok = sp_count(&mut t) == 2;
  if !sp_is(&mut t, 0, "a") { ok = false; }
  if !sp_is(&mut t, 1, "b") { ok = false; }
  if mark_of(&mut t, "a") != 1 { ok = false; }
  if mark_of(&mut t, "b") != 3 { ok = false; }
  if !streq(sp_name(&mut t, 2), "") { ok = false; }
  if !streq(sp_name(&mut t, -1), "") { ok = false; }
  if mark_of(&mut t, "missing") != -1 { ok = false; }
  return assert(ok, "savepoint_count, names and marks are indexed in order");
}

fn t12() -> TestResult {
  var t = txn_new();
  txn_begin(&mut t);
  txn_add_op(&mut t);
  txn_savepoint(&mut t, "a");
  txn_add_op(&mut t);
  txn_savepoint(&mut t, "b");
  txn_add_op(&mut t);
  var ok = txn_savepoint(&mut t, "a");
  if sp_count(&mut t) != 2 { ok = false; }
  if !sp_is(&mut t, 0, "b") { ok = false; }
  if !sp_is(&mut t, 1, "a") { ok = false; }
  if mark_of(&mut t, "a") != 3 { ok = false; }
  if !rollback_to_is(&mut t, "b", 2) { ok = false; }
  if ops_of(&mut t) != 2 { ok = false; }
  if sp_count(&mut t) != 1 { ok = false; }
  if mark_of(&mut t, "a") != -1 { ok = false; }
  if !sp_is(&mut t, 0, "b") { ok = false; }
  return assert(ok, "duplicate savepoint re-anchors at the current op count");
}

fn t13() -> TestResult {
  var t = txn_new();
  txn_begin(&mut t);
  txn_add_op(&mut t);
  txn_add_op(&mut t);
  txn_savepoint(&mut t, "mark2");
  txn_add_op(&mut t);
  txn_add_op(&mut t);
  txn_add_op(&mut t);
  var ok = rollback_to_is(&mut t, "mark2", 2);
  if ops_of(&mut t) != 2 { ok = false; }
  if state_of(&mut t) != 1 { ok = false; }
  if sp_count(&mut t) != 1 { ok = false; }
  if mark_of(&mut t, "mark2") != 2 { ok = false; }
  if !txn_add_op(&mut t) { ok = false; }
  if ops_of(&mut t) != 3 { ok = false; }
  if !txn_savepoint(&mut t, "after") { ok = false; }
  if mark_of(&mut t, "after") != 3 { ok = false; }
  return assert(ok, "rollback_to discards later ops, keeps the savepoint, stays active");
}

fn t14() -> TestResult {
  var t = txn_new();
  txn_begin(&mut t);
  txn_add_op(&mut t);
  txn_savepoint(&mut t, "sp");
  txn_add_op(&mut t);
  txn_add_op(&mut t);
  var ok = rollback_to_is(&mut t, "sp", 1);
  if !rollback_to_is(&mut t, "sp", 1) { ok = false; }
  if ops_of(&mut t) != 1 { ok = false; }
  if mark_of(&mut t, "sp") != 1 { ok = false; }
  if !rollback_to_is(&mut t, "sp", 1) { ok = false; }
  if ops_of(&mut t) != 1 { ok = false; }
  if sp_count(&mut t) != 1 { ok = false; }
  return assert(ok, "rollback_to is repeatable and idempotent");
}

fn t15() -> TestResult {
  var t = txn_new();
  var ok = rollback_to_err_is(&mut t, "ghost", "transaction: rollback_to requires an active transaction");
  if state_of(&mut t) != 0 { ok = false; }
  txn_begin(&mut t);
  txn_add_op(&mut t);
  txn_add_op(&mut t);
  txn_savepoint(&mut t, "real");
  if !rollback_to_err_is(&mut t, "ghost", "transaction: unknown savepoint: ghost") { ok = false; }
  if ops_of(&mut t) != 2 { ok = false; }
  if state_of(&mut t) != 1 { ok = false; }
  if sp_count(&mut t) != 1 { ok = false; }
  if !rollback_to_is(&mut t, "real", 2) { ok = false; }
  return assert(ok, "rollback_to rejects unknown savepoints without side effects");
}

fn t16() -> TestResult {
  var t = txn_new();
  txn_begin(&mut t);
  txn_add_op(&mut t);
  txn_savepoint(&mut t, "early");
  txn_add_op(&mut t);
  txn_savepoint(&mut t, "late");
  txn_add_op(&mut t);
  var ok = sp_count(&mut t) == 2;
  if !rollback_to_is(&mut t, "early", 1) { ok = false; }
  if ops_of(&mut t) != 1 { ok = false; }
  if sp_count(&mut t) != 1 { ok = false; }
  if mark_of(&mut t, "late") != -1 { ok = false; }
  if !rollback_to_is(&mut t, "early", 1) { ok = false; }
  if mark_of(&mut t, "early") != 1 { ok = false; }
  if !txn_savepoint(&mut t, "late") { ok = false; }
  if sp_count(&mut t) != 2 { ok = false; }
  if mark_of(&mut t, "late") != 1 { ok = false; }
  return assert(ok, "rollback_to destroys savepoints created after the target");
}

fn t17() -> TestResult {
  var t = txn_new();
  txn_begin(&mut t);
  txn_add_op(&mut t);
  txn_savepoint(&mut t, "a");
  txn_add_op(&mut t);
  txn_savepoint(&mut t, "b");
  txn_add_op(&mut t);
  txn_add_op(&mut t);
  var ok = txn_release(&mut t, "a");
  if ops_of(&mut t) != 4 { ok = false; }
  if sp_count(&mut t) != 1 { ok = false; }
  if !sp_is(&mut t, 0, "b") { ok = false; }
  if mark_of(&mut t, "b") != 2 { ok = false; }
  if !txn_release(&mut t, "b") { ok = false; }
  if sp_count(&mut t) != 0 { ok = false; }
  if ops_of(&mut t) != 4 { ok = false; }
  return assert(ok, "release removes a savepoint and keeps the op count");
}

fn t18() -> TestResult {
  var t = txn_new();
  var ok = !txn_release(&mut t, "a");
  txn_begin(&mut t);
  txn_savepoint(&mut t, "a");
  if txn_release(&mut t, "b") { ok = false; }
  if sp_count(&mut t) != 1 { ok = false; }
  if !commit_is(&mut t, 0) { ok = false; }
  if txn_release(&mut t, "a") { ok = false; }
  if sp_count(&mut t) != 1 { ok = false; }
  return assert(ok, "release returns false when inactive or unknown");
}

fn t19() -> TestResult {
  var t = txn_new();
  txn_begin(&mut t);
  txn_add_op(&mut t);
  txn_add_op(&mut t);
  txn_savepoint(&mut t, "a");
  txn_add_op(&mut t);
  txn_savepoint(&mut t, "b");
  var ok = commit_is(&mut t, 3);
  if sp_count(&mut t) != 2 { ok = false; }
  if !txn_begin(&mut t) { ok = false; }
  if state_of(&mut t) != 1 { ok = false; }
  if ops_of(&mut t) != 0 { ok = false; }
  if sp_count(&mut t) != 0 { ok = false; }
  if mark_of(&mut t, "a") != -1 { ok = false; }
  if !streq(sp_name(&mut t, 0), "") { ok = false; }
  return assert(ok, "begin after commit resets counters and savepoints");
}

fn t20() -> TestResult {
  var t = txn_new();
  txn_begin(&mut t);
  txn_add_op(&mut t);
  txn_savepoint(&mut t, "x");
  txn_add_op(&mut t);
  var ok = rollback_is(&mut t, 2);
  if sp_count(&mut t) != 1 { ok = false; }
  if !txn_begin(&mut t) { ok = false; }
  if state_of(&mut t) != 1 { ok = false; }
  if ops_of(&mut t) != 0 { ok = false; }
  if sp_count(&mut t) != 0 { ok = false; }
  if !txn_add_op(&mut t) { ok = false; }
  if !txn_savepoint(&mut t, "y") { ok = false; }
  if mark_of(&mut t, "y") != 1 { ok = false; }
  return assert(ok, "begin after rollback starts a clean active transaction");
}

fn t21() -> TestResult {
  var t = txn_new();
  var ok = txn_begin(&mut t);
  var i = 0;
  while i < 5 {
    if !txn_add_op(&mut t) { ok = false; }
    i = i + 1;
  }
  if !txn_savepoint(&mut t, "s1") { ok = false; }
  if mark_of(&mut t, "s1") != 5 { ok = false; }
  while i < 10 {
    if !txn_add_op(&mut t) { ok = false; }
    i = i + 1;
  }
  if !txn_savepoint(&mut t, "s2") { ok = false; }
  if mark_of(&mut t, "s2") != 10 { ok = false; }
  while i < 15 {
    if !txn_add_op(&mut t) { ok = false; }
    i = i + 1;
  }
  if !txn_savepoint(&mut t, "s3") { ok = false; }
  if mark_of(&mut t, "s3") != 15 { ok = false; }
  while i < 20 {
    if !txn_add_op(&mut t) { ok = false; }
    i = i + 1;
  }
  if ops_of(&mut t) != 20 { ok = false; }
  if sp_count(&mut t) != 3 { ok = false; }
  if !sp_is(&mut t, 0, "s1") { ok = false; }
  if !sp_is(&mut t, 1, "s2") { ok = false; }
  if !sp_is(&mut t, 2, "s3") { ok = false; }
  if !rollback_to_is(&mut t, "s2", 10) { ok = false; }
  if ops_of(&mut t) != 10 { ok = false; }
  if sp_count(&mut t) != 2 { ok = false; }
  if mark_of(&mut t, "s3") != -1 { ok = false; }
  if !rollback_to_is(&mut t, "s2", 10) { ok = false; }
  if ops_of(&mut t) != 10 { ok = false; }
  if !txn_add_op(&mut t) { ok = false; }
  if !txn_add_op(&mut t) { ok = false; }
  if ops_of(&mut t) != 12 { ok = false; }
  if !commit_is(&mut t, 12) { ok = false; }
  if state_of(&mut t) != 2 { ok = false; }
  if ops_of(&mut t) != 12 { ok = false; }
  if txn_add_op(&mut t) { ok = false; }
  if sp_count(&mut t) != 2 { ok = false; }
  return assert(ok, "20 ops, 3 savepoints, rollback_to s2 at 10, commit at 12");
}

fn t22() -> TestResult {
  var t = txn_new();
  var ok = commit_err_is(&mut t, "transaction: commit requires an active transaction");
  if !rollback_err_is(&mut t, "transaction: rollback requires an active transaction") { ok = false; }
  if !rollback_to_err_is(&mut t, "sp", "transaction: rollback_to requires an active transaction") { ok = false; }
  if state_of(&mut t) != 0 { ok = false; }
  txn_begin(&mut t);
  if !commit_is(&mut t, 0) { ok = false; }
  if !commit_err_is(&mut t, "transaction: commit requires an active transaction") { ok = false; }
  if !rollback_err_is(&mut t, "transaction: rollback requires an active transaction") { ok = false; }
  if !rollback_to_err_is(&mut t, "sp", "transaction: rollback_to requires an active transaction") { ok = false; }
  if state_of(&mut t) != 2 { ok = false; }
  if ops_of(&mut t) != 0 { ok = false; }
  return assert(ok, "the error catalog pins every wrong-state message");
}

fn main() -> Int {
  io.println("=== xiom.transaction conformance tests ===");
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
  let r21 = t21();
  if r21.passed { io.println("  [PASS] " + r21.name); } else { io.println("  [FAIL] " + r21.name); failed = failed + 1; }
  let r22 = t22();
  if r22.passed { io.println("  [PASS] " + r22.name); } else { io.println("  [FAIL] " + r22.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.transaction: all tests passed");
  } else {
    io.println("xiom.transaction: tests failed");
  }
  return failed;
}
