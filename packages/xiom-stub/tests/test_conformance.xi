// XIOM -- xiom.stub conformance tests (22 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Greenfield package: prove the pure-XIOM ordered-stub semantics against the
// documented model in SPEC.md.
//
// Coverage: ordered first-accept binding, argument-tuple matching, all three
// cardinality modes (met and unmet, both directions), sequential same-matcher
// responses, canned returns, failure actions, strict vs lenient invocation,
// numbered call logs, matched/unmatched accounting, missing/extra/out-of-
// order violations with exact messages, verification precedence, the full
// structured report, validation without mutation, bounds-safe accessors and
// reset/clear semantics. All Str comparisons go through str_compare.

module stub_tests
use xiom.io; use xiom.test; use xiom.stub;
use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// True when the result fails with exactly the message `want`.
fn err_is(r: Result[Int, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// True when the result succeeds with exactly `want`.
fn ok_is(r: Result[Int, Str], want: Int) -> Bool {
  match r {
    Ok(v) => { return v == want; },
    Err(_) => { return false; },
  }
  return false;
}

fn t1() -> TestResult {
  let m = stub_new();
  var ok = stub_expectation_count(&m) == 0;
  if stub_call_total(&m) != 0 { ok = false; }
  if stub_matched_count(&m) != 0 { ok = false; }
  if stub_unmatched_count(&m) != 0 { ok = false; }
  if stub_missing_count(&m) != 0 { ok = false; }
  if stub_extra_count(&m) != 0 { ok = false; }
  if stub_out_of_order_count(&m) != 0 { ok = false; }
  if stub_violation_count(&m) != 0 { ok = false; }
  if !stub_verified(&m) { ok = false; }
  if !streq(stub_verify_message(&m), "") { ok = false; }
  if !streq(stub_report(&m), "") { ok = false; }
  if stub_is_lenient(&m) { ok = false; }
  return assert(ok, "a fresh stub is empty, strict and verified");
}

fn t2() -> TestResult {
  var m = stub_new();
  var ok = ok_is(stub_expect1(&mut m, "add", 2, 1, 5), 0);
  if !ok_is(stub_invoke1(&mut m, "add", 2), 5) { ok = false; }
  if stub_expect_actual(&m, 0) != 1 { ok = false; }
  if !stub_expect_met(&m, 0) { ok = false; }
  if stub_call_total(&m) != 1 { ok = false; }
  if stub_call_match(&m, 0) != 0 { ok = false; }
  if !stub_call_matched(&m, 0) { ok = false; }
  if stub_matched_count(&m) != 1 { ok = false; }
  if !stub_verified(&m) { ok = false; }
  return assert(ok, "an exactly-N expectation binds N calls and returns its value");
}

fn t3() -> TestResult {
  var m = stub_new();
  stub_expect1(&mut m, "get", 7, 2, 0);
  if !ok_is(stub_invoke1(&mut m, "get", 7), 0) { return assert(false, "missing-call setup"); }
  var ok = stub_missing_count(&m) == 1;
  if stub_missing_index(&m, 0) != 0 { ok = false; }
  if !streq(stub_missing_message(&m, 0), "stub: missing call 'get(7)': expected exactly 2, got 1") { ok = false; }
  if !streq(stub_verify_message(&m), "stub: missing call 'get(7)': expected exactly 2, got 1") { ok = false; }
  if stub_verified(&m) { ok = false; }
  if stub_expect_met(&m, 0) { ok = false; }
  return assert(ok, "an exactly-N expectation reports too few calls");
}

fn t4() -> TestResult {
  var m = stub_new();
  stub_expect0(&mut m, "ping", 1, 42);
  var ok = ok_is(stub_invoke0(&mut m, "ping"), 42);
  if !err_is(stub_invoke0(&mut m, "ping"), "stub: unexpected call 'ping' (call #1): matching expectation #0 is exhausted") { ok = false; }
  if !err_is(stub_invoke0(&mut m, "ping"), "stub: unexpected call 'ping' (call #2): matching expectation #0 is exhausted") { ok = false; }
  if stub_extra_count(&m) != 2 { ok = false; }
  if stub_extra_call(&m, 0) != 1 { ok = false; }
  if stub_extra_call(&m, 1) != 2 { ok = false; }
  if !streq(stub_extra_message(&m, 1), "stub: unexpected call 'ping' (call #2): matching expectation #0 is exhausted") { ok = false; }
  if stub_missing_count(&m) != 0 { ok = false; }
  if stub_unmatched_count(&m) != 2 { ok = false; }
  if stub_call_match(&m, 1) != -1 { ok = false; }
  if stub_call_matched(&m, 1) { ok = false; }
  if stub_verified(&m) { ok = false; }
  return assert(ok, "surplus calls over an exact count are unexpected but the expectation is met");
}

fn t5() -> TestResult {
  var m = stub_new();
  stub_expect_at_least1(&mut m, "log", 5, 2, 0);
  var ok = stub_expect_mode(&m, 0) == 1;
  if !ok_is(stub_invoke1(&mut m, "log", 5), 0) { ok = false; }
  if !ok_is(stub_invoke1(&mut m, "log", 5), 0) { ok = false; }
  if stub_expect_actual(&m, 0) != 2 { ok = false; }
  if !stub_expect_met(&m, 0) { ok = false; }
  if !stub_verified(&m) { ok = false; }
  if !ok_is(stub_invoke1(&mut m, "log", 5), 0) { ok = false; }
  if stub_expect_actual(&m, 0) != 3 { ok = false; }
  if stub_extra_count(&m) != 0 { ok = false; }
  if !stub_verified(&m) { ok = false; }
  return assert(ok, "an at-least-N expectation accepts extra calls");
}

fn t6() -> TestResult {
  var m = stub_new();
  stub_expect_at_least1(&mut m, "log", 5, 2, 0);
  if !ok_is(stub_invoke1(&mut m, "log", 5), 0) { return assert(false, "at-least setup"); }
  var ok = stub_missing_count(&m) == 1;
  if !streq(stub_missing_message(&m, 0), "stub: missing call 'log(5)': expected at least 2, got 1") { ok = false; }
  if !streq(stub_verify_message(&m), "stub: missing call 'log(5)': expected at least 2, got 1") { ok = false; }
  if stub_verified(&m) { ok = false; }
  return assert(ok, "an at-least-N expectation reports too few calls");
}

fn t7() -> TestResult {
  var m = stub_new();
  stub_expect_at_most1(&mut m, "flush", 3, 2, 1);
  var ok = stub_expect_mode(&m, 0) == 2;
  if !ok_is(stub_invoke1(&mut m, "flush", 3), 1) { ok = false; }
  if !ok_is(stub_invoke1(&mut m, "flush", 3), 1) { ok = false; }
  if !stub_expect_met(&m, 0) { ok = false; }
  if !stub_verified(&m) { ok = false; }
  if !err_is(stub_invoke1(&mut m, "flush", 3), "stub: unexpected call 'flush(3)' (call #2): matching expectation #0 is exhausted") { ok = false; }
  if stub_extra_count(&m) != 1 { ok = false; }
  if stub_missing_count(&m) != 0 { ok = false; }
  if stub_verified(&m) { ok = false; }
  var m2 = stub_new();
  stub_expect_at_most0(&mut m2, "noop", 0, 0);
  if !stub_expect_met(&m2, 0) { ok = false; }
  if !stub_verified(&m2) { ok = false; }
  return assert(ok, "an at-most-N expectation caps matching and never counts as missing");
}

fn t8() -> TestResult {
  var m = stub_new();
  stub_expect1(&mut m, "get", 1, 1, 10);
  stub_expect1(&mut m, "get", 1, 1, 20);
  var ok = ok_is(stub_invoke1(&mut m, "get", 1), 10);
  if !ok_is(stub_invoke1(&mut m, "get", 1), 20) { ok = false; }
  if stub_call_match(&m, 0) != 0 { ok = false; }
  if stub_call_match(&m, 1) != 1 { ok = false; }
  if stub_expect_actual(&m, 0) != 1 { ok = false; }
  if stub_expect_actual(&m, 1) != 1 { ok = false; }
  if !stub_verified(&m) { ok = false; }
  return assert(ok, "same-matcher expectations serve sequential responses in order");
}

fn t9() -> TestResult {
  var m = stub_new();
  stub_expect2(&mut m, "add", 1, 2, 1, 3);
  var ok = err_is(stub_invoke1(&mut m, "add", 1), "stub: unexpected call 'add(1)' (call #0)");
  if !ok_is(stub_invoke2(&mut m, "add", 1, 2), 3) { ok = false; }
  if !err_is(stub_invoke2(&mut m, "add", 2, 1), "stub: unexpected call 'add(2, 1)' (call #2)") { ok = false; }
  if stub_call_total(&m) != 3 { ok = false; }
  if !stub_call_matched(&m, 1) { ok = false; }
  if stub_call_matched(&m, 0) { ok = false; }
  if stub_call_arg_count(&m, 2) != 2 { ok = false; }
  if stub_call_arg(&m, 2, 0) != 2 { ok = false; }
  if stub_call_arg(&m, 2, 1) != 1 { ok = false; }
  if stub_call_arg(&m, 2, 5) != 0 { ok = false; }
  if stub_matched_count(&m) != 1 { ok = false; }
  if stub_unmatched_count(&m) != 2 { ok = false; }
  return assert(ok, "matching is by exact method and Int argument tuple");
}

fn t10() -> TestResult {
  var m = stub_new();
  stub_expect1(&mut m, "open", 1, 1, 0);
  stub_expect0(&mut m, "read", 1, 0);
  var ok = ok_is(stub_invoke0(&mut m, "read"), 0);
  if stub_call_match(&m, 0) != 1 { ok = false; }
  if stub_out_of_order_count(&m) != 1 { ok = false; }
  if stub_out_of_order_call(&m, 0) != 0 { ok = false; }
  if stub_out_of_order_expectation(&m, 0) != 0 { ok = false; }
  if !streq(stub_out_of_order_message(&m, 0), "stub: out-of-order call 'read' (call #0): expectation #0 'open(1)' is still unsatisfied") { ok = false; }
  if !ok_is(stub_invoke1(&mut m, "open", 1), 0) { ok = false; }
  if stub_missing_count(&m) != 0 { ok = false; }
  if stub_extra_count(&m) != 0 { ok = false; }
  if stub_out_of_order_count(&m) != 1 { ok = false; }
  if stub_verified(&m) { ok = false; }
  if !streq(stub_verify_message(&m), "stub: out-of-order call 'read' (call #0): expectation #0 'open(1)' is still unsatisfied") { ok = false; }
  return assert(ok, "a call that overtakes an unsatisfied earlier expectation is out of order");
}

fn t11() -> TestResult {
  var m = stub_new();
  var ok = ok_is(stub_expect_fail1(&mut m, "fetch", 9, "network down"), 0);
  if !err_is(stub_invoke1(&mut m, "fetch", 9), "network down") { ok = false; }
  if stub_expect_actual(&m, 0) != 1 { ok = false; }
  if !stub_expect_met(&m, 0) { ok = false; }
  if !stub_expect_has_failure(&m, 0) { ok = false; }
  if !streq(stub_expect_failure(&m, 0), "network down") { ok = false; }
  if !stub_verified(&m) { ok = false; }
  return assert(ok, "a failure action returns Err with its message verbatim");
}

fn t12() -> TestResult {
  var m = stub_new();
  stub_set_lenient(&mut m, true);
  var ok = stub_is_lenient(&m);
  if !ok_is(stub_invoke0(&mut m, "anything"), 0) { ok = false; }
  if stub_extra_count(&m) != 1 { ok = false; }
  if stub_verified(&m) { ok = false; }
  stub_set_lenient(&mut m, false);
  if stub_is_lenient(&m) { ok = false; }
  if !err_is(stub_invoke0(&mut m, "anything"), "stub: unexpected call 'anything' (call #1)") { ok = false; }
  if stub_extra_count(&m) != 2 { ok = false; }
  return assert(ok, "lenient returns Ok(0) for unmatched calls; strict returns Err");
}

fn t13() -> TestResult {
  var m = stub_new();
  stub_set_lenient(&mut m, true);
  var ok = ok_is(stub_invoke0(&mut m, "a"), 0);
  if !ok_is(stub_invoke2(&mut m, "b", 3, 4), 0) { ok = false; }
  if !ok_is(stub_invoke3(&mut m, "c", 5, 6, 7), 0) { ok = false; }
  if stub_call_total(&m) != 3 { ok = false; }
  if stub_call_seq(&m, 0) != 0 { ok = false; }
  if stub_call_seq(&m, 2) != 2 { ok = false; }
  if stub_call_seq(&m, 3) != -1 { ok = false; }
  if !streq(stub_call_method(&m, 1), "b") { ok = false; }
  if !streq(stub_call_method(&m, 3), "") { ok = false; }
  if stub_call_arg_count(&m, 1) != 2 { ok = false; }
  if stub_call_arg_count(&m, 0) != 0 { ok = false; }
  if stub_call_arg(&m, 1, 0) != 3 { ok = false; }
  if stub_call_arg(&m, 2, 2) != 7 { ok = false; }
  if stub_call_arg(&m, 0, 0) != 0 { ok = false; }
  if stub_call_match(&m, 0) != -1 { ok = false; }
  if stub_matched_count(&m) != 0 { ok = false; }
  if stub_unmatched_count(&m) != 3 { ok = false; }
  return assert(ok, "the call log numbers calls and stores methods, arities and args");
}

fn t14() -> TestResult {
  var m = stub_new();
  var ok = err_is(stub_expect0(&mut m, "", 1, 0), "stub: empty method");
  if !err_is(stub_expect1(&mut m, "x", 1, -3, 0), "stub: negative times -3") { ok = false; }
  if !err_is(stub_expect_fail0(&mut m, "y", ""), "stub: empty failure message") { ok = false; }
  if stub_expectation_count(&m) != 0 { ok = false; }
  if stub_call_total(&m) != 0 { ok = false; }
  if !ok_is(stub_expect0(&mut m, "ok", 0, 1), 0) { ok = false; }
  if stub_expectation_count(&m) != 1 { ok = false; }
  if !stub_expect_met(&m, 0) { ok = false; }
  if !stub_verified(&m) { ok = false; }
  return assert(ok, "expectation validation rejects bad input without mutating");
}

fn t15() -> TestResult {
  var m = stub_new();
  stub_expect0(&mut m, "ping", 1, 7);
  if !ok_is(stub_invoke0(&mut m, "ping"), 7) { return assert(false, "reset setup"); }
  var ok = stub_verified(&m);
  stub_reset(&mut m);
  if stub_call_total(&m) != 0 { ok = false; }
  if stub_matched_count(&m) != 0 { ok = false; }
  if stub_unmatched_count(&m) != 0 { ok = false; }
  if stub_extra_count(&m) != 0 { ok = false; }
  if stub_out_of_order_count(&m) != 0 { ok = false; }
  if stub_expectation_count(&m) != 1 { ok = false; }
  if stub_expect_actual(&m, 0) != 0 { ok = false; }
  if stub_expect_met(&m, 0) { ok = false; }
  if stub_missing_count(&m) != 1 { ok = false; }
  if stub_violation_count(&m) != 1 { ok = false; }
  if !streq(stub_report(&m), "stub: 1 violation(s):\nstub: missing call 'ping': expected exactly 1, got 0") { ok = false; }
  if !ok_is(stub_invoke0(&mut m, "ping"), 7) { ok = false; }
  if !stub_verified(&m) { ok = false; }
  if stub_missing_count(&m) != 0 { ok = false; }
  return assert(ok, "reset clears calls and violations but keeps expectations");
}

fn t16() -> TestResult {
  var m = stub_new();
  stub_expect0(&mut m, "ping", 1, 7);
  stub_set_lenient(&mut m, true);
  if !ok_is(stub_invoke0(&mut m, "ping"), 7) { return assert(false, "clear setup"); }
  stub_clear(&mut m);
  var ok = stub_expectation_count(&m) == 0;
  if stub_call_total(&m) != 0 { ok = false; }
  if stub_is_lenient(&m) { ok = false; }
  if !stub_verified(&m) { ok = false; }
  if !streq(stub_verify_message(&m), "") { ok = false; }
  if !err_is(stub_invoke0(&mut m, "x"), "stub: unexpected call 'x' (call #0)") { ok = false; }
  return assert(ok, "clear returns the stub to its fresh strict state");
}

fn t17() -> TestResult {
  var m = stub_new();
  stub_expect0(&mut m, "must", 1, 0);
  if !err_is(stub_invoke0(&mut m, "other"), "stub: unexpected call 'other' (call #0)") { return assert(false, "priority setup"); }
  var ok = streq(stub_verify_message(&m), "stub: missing call 'must': expected exactly 1, got 0");
  var m2 = stub_new();
  if !err_is(stub_invoke0(&mut m2, "other"), "stub: unexpected call 'other' (call #0)") { ok = false; }
  if !streq(stub_verify_message(&m2), "stub: unexpected call 'other' (call #0)") { ok = false; }
  var m3 = stub_new();
  stub_expect0(&mut m3, "a", 1, 0);
  stub_expect0(&mut m3, "b", 1, 0);
  if !ok_is(stub_invoke0(&mut m3, "b"), 0) { ok = false; }
  if !ok_is(stub_invoke0(&mut m3, "a"), 0) { ok = false; }
  if !streq(stub_verify_message(&m3), "stub: out-of-order call 'b' (call #0): expectation #0 'a' is still unsatisfied") { ok = false; }
  return assert(ok, "verify_message reports missing before extra before out-of-order");
}

fn t18() -> TestResult {
  var m = stub_new();
  stub_expect0(&mut m, "a", 1, 0);
  stub_expect0(&mut m, "b", 1, 0);
  stub_expect0(&mut m, "c", 1, 0);
  if !ok_is(stub_invoke0(&mut m, "c"), 0) { return assert(false, "report setup c"); }
  if !ok_is(stub_invoke0(&mut m, "b"), 0) { return assert(false, "report setup b"); }
  if !err_is(stub_invoke0(&mut m, "x"), "stub: unexpected call 'x' (call #2)") { return assert(false, "report setup x"); }
  var ok = stub_missing_count(&m) == 1;
  if stub_extra_count(&m) != 1 { ok = false; }
  if stub_out_of_order_count(&m) != 2 { ok = false; }
  if stub_violation_count(&m) != 4 { ok = false; }
  var want = "stub: 4 violation(s):\n"
    + "stub: missing call 'a': expected exactly 1, got 0\n"
    + "stub: unexpected call 'x' (call #2)\n"
    + "stub: out-of-order call 'c' (call #0): expectation #0 'a' is still unsatisfied\n"
    + "stub: out-of-order call 'b' (call #1): expectation #0 'a' is still unsatisfied";
  if !streq(stub_report(&m), want) { ok = false; }
  return assert(ok, "the structured report lists every violation in reporting order");
}

fn t19() -> TestResult {
  var m = stub_new();
  stub_expect1(&mut m, "hit", 1, 2, 5);
  if !ok_is(stub_invoke1(&mut m, "hit", 1), 5) { return assert(false, "accounting setup 1"); }
  if !ok_is(stub_invoke1(&mut m, "hit", 1), 5) { return assert(false, "accounting setup 2"); }
  stub_set_lenient(&mut m, true);
  if !ok_is(stub_invoke1(&mut m, "miss", 9), 0) { return assert(false, "accounting setup 3"); }
  if !ok_is(stub_invoke0(&mut m, "hit"), 0) { return assert(false, "accounting setup 4"); }
  var ok = stub_call_total(&m) == 4;
  if stub_matched_count(&m) != 2 { ok = false; }
  if stub_unmatched_count(&m) != 2 { ok = false; }
  if stub_matched_count(&m) + stub_unmatched_count(&m) != stub_call_total(&m) { ok = false; }
  return assert(ok, "matched plus unmatched accounting covers every call");
}

fn t20() -> TestResult {
  var m = stub_new();
  stub_expect_at_most2(&mut m, "put", 1, 2, 2, 9);
  var ok = streq(stub_expect_method(&m, 0), "put");
  if stub_expect_mode(&m, 0) != 2 { ok = false; }
  if stub_expect_times(&m, 0) != 2 { ok = false; }
  if stub_expect_return(&m, 0) != 9 { ok = false; }
  if stub_expect_arg_count(&m, 0) != 2 { ok = false; }
  if stub_expect_arg(&m, 0, 0) != 1 { ok = false; }
  if stub_expect_arg(&m, 0, 1) != 2 { ok = false; }
  if stub_expect_arg(&m, 0, 2) != 0 { ok = false; }
  if stub_expect_has_failure(&m, 0) { ok = false; }
  if !streq(stub_expect_failure(&m, 0), "") { ok = false; }
  if !stub_expect_met(&m, 0) { ok = false; }
  stub_expect_fail3(&mut m, "f", 4, 5, 6, "boom");
  if !streq(stub_expect_method(&m, 1), "f") { ok = false; }
  if !stub_expect_has_failure(&m, 1) { ok = false; }
  if !streq(stub_expect_failure(&m, 1), "boom") { ok = false; }
  if stub_expect_arg_count(&m, 1) != 3 { ok = false; }
  if stub_expect_arg(&m, 1, 2) != 6 { ok = false; }
  if !streq(stub_expect_method(&m, 2), "") { ok = false; }
  if stub_expect_mode(&m, 2) != -1 { ok = false; }
  if stub_expect_times(&m, 2) != -1 { ok = false; }
  if stub_expect_actual(&m, 2) != -1 { ok = false; }
  if stub_expect_return(&m, 2) != -1 { ok = false; }
  if stub_expect_has_failure(&m, 2) { ok = false; }
  if stub_expect_arg_count(&m, 2) != 0 { ok = false; }
  if stub_expect_arg(&m, 2, 0) != 0 { ok = false; }
  if stub_expect_met(&m, 2) { ok = false; }
  return assert(ok, "expectation accessors report the declaration exactly and clamp");
}

fn t21() -> TestResult {
  var m = stub_new();
  stub_expect0(&mut m, "a", 1, 0);
  stub_expect0(&mut m, "b", 1, 0);
  if !ok_is(stub_invoke0(&mut m, "b"), 0) { return assert(false, "reset violations setup 1"); }
  if !err_is(stub_invoke0(&mut m, "z"), "stub: unexpected call 'z' (call #1)") { return assert(false, "reset violations setup 2"); }
  var ok = stub_out_of_order_count(&m) == 1;
  if stub_extra_count(&m) != 1 { ok = false; }
  if stub_missing_count(&m) != 1 { ok = false; }
  stub_reset(&mut m);
  if stub_out_of_order_count(&m) != 0 { ok = false; }
  if stub_extra_count(&m) != 0 { ok = false; }
  if stub_call_total(&m) != 0 { ok = false; }
  if stub_missing_count(&m) != 2 { ok = false; }
  if stub_violation_count(&m) != 2 { ok = false; }
  if !streq(stub_report(&m), "stub: 2 violation(s):\nstub: missing call 'a': expected exactly 1, got 0\nstub: missing call 'b': expected exactly 1, got 0") { ok = false; }
  if !ok_is(stub_invoke0(&mut m, "a"), 0) { ok = false; }
  if !ok_is(stub_invoke0(&mut m, "b"), 0) { ok = false; }
  if !stub_verified(&m) { ok = false; }
  return assert(ok, "reset clears violation lists and allows a clean replay");
}

fn t22() -> TestResult {
  var m = stub_new();
  stub_expect3(&mut m, "tri", 1, 2, 3, 1, 0);
  var ok = err_is(stub_invoke3(&mut m, "tri", 1, 2, 4), "stub: unexpected call 'tri(1, 2, 4)' (call #0)");
  if !ok_is(stub_invoke3(&mut m, "tri", 1, 2, 3), 0) { ok = false; }
  if !stub_expect_met(&m, 0) { ok = false; }
  if stub_call_arg_count(&m, 0) != 3 { ok = false; }
  if stub_extra_count(&m) != 1 { ok = false; }
  if stub_verified(&m) { ok = false; }
  var m2 = stub_new();
  stub_expect3(&mut m2, "tri", 1, 2, 3, 1, 0);
  if !ok_is(stub_invoke3(&mut m2, "tri", 1, 2, 3), 0) { ok = false; }
  if !stub_verified(&m2) { ok = false; }
  return assert(ok, "three-argument tuples match element-wise and render in messages");
}

fn main() -> Int {
  io.println("=== xiom.stub conformance tests ===");
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
    io.println("xiom.stub: all tests passed");
  } else {
    io.println("xiom.stub: tests failed");
  }
  return failed;
}
