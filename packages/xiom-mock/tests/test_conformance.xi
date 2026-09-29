// XIOM -- xiom.mock conformance tests (20 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Greenfield package: prove the pure-XIOM xiom.mock expectation, recording
// and verification semantics against the documented model in SPEC.md.
//
// Coverage: all three cardinality modes (met and unmet, both directions),
// expectation validation and non-mutation on failure, matched and unexpected
// recording, the call log order and args, accessor bounds, case sensitivity,
// reset/clear semantics and the verification messages. All Str comparisons
// go through str_compare.

module mock_tests
use xiom.io; use xiom.test; use xiom.mock;
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

// Record `n` calls of `name` with `args`.
fn record_n(m: &mut Mock, name: Str, args: Str, n: Int) {
  var i = 0;
  while i < n {
    mock_record(m, name, args);
    i = i + 1;
  }
}

fn t1() -> TestResult {
  let m = mock_new();
  var ok = mock_expectation_count(&m) == 0;
  if mock_call_total(&m) != 0 { ok = false; }
  if mock_unexpected_count(&m) != 0 { ok = false; }
  if !mock_verified(&m) { ok = false; }
  if !streq(mock_verify_message(&m), "") { ok = false; }
  return assert(ok, "a fresh mock has no expectations and verifies");
}

fn t2() -> TestResult {
  var m = mock_new();
  var ok = ok_is(mock_expect(&mut m, "get", 2), 0);
  if mock_mode(&m, "get") != 0 { ok = false; }
  if mock_expected(&m, "get") != 2 { ok = false; }
  if mock_actual(&m, "get") != 0 { ok = false; }
  mock_record(&mut m, "get", "key=1");
  mock_record(&mut m, "get", "key=2");
  if !mock_verified(&m) { ok = false; }
  if mock_actual(&m, "get") != 2 { ok = false; }
  if mock_call_count(&m, "get") != 2 { ok = false; }
  if mock_unmet_count(&m) != 0 { ok = false; }
  return assert(ok, "an exactly-N expectation is met by N matching calls");
}

fn t3() -> TestResult {
  var m = mock_new();
  mock_expect(&mut m, "get", 2);
  record_n(&mut m, "get", "", 1);
  var ok = !mock_verified(&m);
  if mock_unmet_count(&m) != 1 { ok = false; }
  if !streq(mock_verify_message(&m), "mock: unmet expectation 'get': expected exactly 2, got 1") { ok = false; }
  return assert(ok, "an exactly-N expectation reports too few calls");
}

fn t4() -> TestResult {
  var m = mock_new();
  mock_expect(&mut m, "get", 1);
  record_n(&mut m, "get", "", 3);
  var ok = !mock_verified(&m);
  if !streq(mock_verify_message(&m), "mock: unmet expectation 'get': expected exactly 1, got 3") { ok = false; }
  if mock_call_total(&m) != 3 { ok = false; }
  return assert(ok, "an exactly-N expectation reports too many calls");
}

fn t5() -> TestResult {
  var m = mock_new();
  mock_expect_at_least(&mut m, "put", 2);
  var ok = mock_mode(&m, "put") == 1;
  if mock_actual(&m, "put") != 0 { ok = false; }
  record_n(&mut m, "put", "", 2);
  if !mock_verified(&m) { ok = false; }
  record_n(&mut m, "put", "", 1);
  if !mock_verified(&m) { ok = false; }
  if mock_actual(&m, "put") != 3 { ok = false; }
  var m2 = mock_new();
  mock_expect_at_least(&mut m2, "put", 2);
  record_n(&mut m2, "put", "", 1);
  if !streq(mock_verify_message(&m2), "mock: unmet expectation 'put': expected at least 2, got 1") { ok = false; }
  return assert(ok, "an at-least-N expectation tolerates extra calls");
}

fn t6() -> TestResult {
  var m = mock_new();
  mock_expect_at_most(&mut m, "del", 2);
  var ok = mock_mode(&m, "del") == 2;
  record_n(&mut m, "del", "", 2);
  if !mock_verified(&m) { ok = false; }
  record_n(&mut m, "del", "", 1);
  if mock_verified(&m) { ok = false; }
  if !streq(mock_verify_message(&m), "mock: unmet expectation 'del': expected at most 2, got 3") { ok = false; }
  var m2 = mock_new();
  mock_expect_at_most(&mut m2, "del", 0);
  if !mock_verified(&m2) { ok = false; }
  return assert(ok, "an at-most-N expectation rejects extra calls");
}

fn t7() -> TestResult {
  var m = mock_new();
  mock_expect(&mut m, "get", 1);
  var ok = err_is(mock_expect(&mut m, "", 1), "mock: empty name");
  if !err_is(mock_expect(&mut m, "get", 1), "mock: duplicate expectation 'get'") { ok = false; }
  if !err_is(mock_expect(&mut m, "post", -2), "mock: negative times -2") { ok = false; }
  if mock_expectation_count(&m) != 1 { ok = false; }
  if mock_mode(&m, "post") != -1 { ok = false; }
  return assert(ok, "expectation validation rejects bad input without mutating");
}

fn t8() -> TestResult {
  var m = mock_new();
  mock_expect(&mut m, "get", 1);
  mock_record(&mut m, "get", "k");
  mock_record(&mut m, "set", "v");
  var ok = mock_call_total(&m) == 2;
  if mock_unexpected_count(&m) != 1 { ok = false; }
  if !streq(mock_unexpected_name(&m, 0), "set") { ok = false; }
  if !streq(mock_unexpected_message(&m), "mock: unexpected call 'set'") { ok = false; }
  if !mock_verified(&m) { ok = false; }
  return assert(ok, "calls matching no expectation are recorded as unexpected");
}

fn t9() -> TestResult {
  var m = mock_new();
  mock_expect(&mut m, "get", 1);
  record_n(&mut m, "get", "", 2);
  mock_record(&mut m, "other", "x");
  var ok = mock_call_count(&m, "get") == 2;
  if mock_actual(&m, "get") != 2 { ok = false; }
  if mock_call_count(&m, "other") != 1 { ok = false; }
  if mock_call_total(&m) != 3 { ok = false; }
  if mock_unexpected_count(&m) != 1 { ok = false; }
  if !streq(mock_unexpected_args(&m, 0), "x") { ok = false; }
  return assert(ok, "call_count counts every call; actual counts matches only");
}

fn t10() -> TestResult {
  var m = mock_new();
  mock_expect(&mut m, "get", 1);
  mock_record(&mut m, "get", "a");
  var ok = mock_verified(&m);
  mock_reset(&mut m);
  if mock_call_total(&m) != 0 { ok = false; }
  if mock_unexpected_count(&m) != 0 { ok = false; }
  if mock_expectation_count(&m) != 1 { ok = false; }
  if mock_actual(&m, "get") != 0 { ok = false; }
  if mock_verified(&m) { ok = false; }
  if !streq(mock_verify_message(&m), "mock: unmet expectation 'get': expected exactly 1, got 0") { ok = false; }
  return assert(ok, "reset clears calls but keeps expectations");
}

fn t11() -> TestResult {
  var m = mock_new();
  mock_expect(&mut m, "get", 1);
  mock_record(&mut m, "get", "a");
  mock_clear(&mut m);
  var ok = mock_expectation_count(&m) == 0;
  if mock_call_total(&m) != 0 { ok = false; }
  if mock_mode(&m, "get") != -1 { ok = false; }
  if !mock_verified(&m) { ok = false; }
  return assert(ok, "clear drops expectations and calls alike");
}

fn t12() -> TestResult {
  var m = mock_new();
  mock_record(&mut m, "a", "1");
  mock_record(&mut m, "b", "2");
  mock_record(&mut m, "a", "3");
  var ok = mock_call_total(&m) == 3;
  if !streq(mock_call_name(&m, 0), "a") { ok = false; }
  if !streq(mock_call_args(&m, 0), "1") { ok = false; }
  if !streq(mock_call_name(&m, 1), "b") { ok = false; }
  if !streq(mock_call_args(&m, 2), "3") { ok = false; }
  if !streq(mock_call_name(&m, 3), "") { ok = false; }
  if !streq(mock_call_args(&m, -1), "") { ok = false; }
  return assert(ok, "the call log preserves order and argument text");
}

fn t13() -> TestResult {
  let m = mock_new();
  var ok = mock_expectation_index(&m, "nope") == -1;
  if mock_mode(&m, "nope") != -1 { ok = false; }
  if mock_expected(&m, "nope") != -1 { ok = false; }
  if mock_actual(&m, "nope") != -1 { ok = false; }
  if mock_unmet_count(&m) != 0 { ok = false; }
  return assert(ok, "expectation accessors report -1 for unknown names");
}

fn t14() -> TestResult {
  var m = mock_new();
  mock_expect(&mut m, "GET", 1);
  mock_expect(&mut m, "get", 1);
  mock_record(&mut m, "get", "");
  var ok = mock_expectation_count(&m) == 2;
  if mock_actual(&m, "GET") != 0 { ok = false; }
  if mock_actual(&m, "get") != 1 { ok = false; }
  mock_record(&mut m, "GET", "");
  if mock_actual(&m, "GET") != 1 { ok = false; }
  if !mock_verified(&m) { ok = false; }
  return assert(ok, "expectation names are case-sensitive");
}

fn t15() -> TestResult {
  var m = mock_new();
  mock_expect(&mut m, "a", 1);
  mock_expect(&mut m, "b", 2);
  record_n(&mut m, "b", "", 2);
  var ok = mock_unmet_count(&m) == 1;
  if !streq(mock_verify_message(&m), "mock: unmet expectation 'a': expected exactly 1, got 0") { ok = false; }
  if mock_verified(&m) { ok = false; }
  return assert(ok, "verification reports the first unmet expectation in order");
}

fn t16() -> TestResult {
  var m = mock_new();
  mock_record(&mut m, "boom", "why");
  var ok = mock_unexpected_count(&m) == 1;
  if !streq(mock_unexpected_args(&m, 0), "why") { ok = false; }
  if !streq(mock_unexpected_name(&m, 1), "") { ok = false; }
  if !streq(mock_unexpected_args(&m, -1), "") { ok = false; }
  if !streq(mock_unexpected_message(&m), "mock: unexpected call 'boom'") { ok = false; }
  return assert(ok, "unexpected-call accessors are bounds-safe");
}

fn t17() -> TestResult {
  var m = mock_new();
  mock_expect(&mut m, "exact", 1);
  mock_expect_at_least(&mut m, "least", 1);
  mock_expect_at_most(&mut m, "most", 1);
  mock_record(&mut m, "exact", "");
  mock_record(&mut m, "least", "");
  mock_record(&mut m, "least", "");
  var ok = mock_verified(&m);
  if mock_unmet_count(&m) != 0 { ok = false; }
  if !streq(mock_verify_message(&m), "") { ok = false; }
  return assert(ok, "all three modes can be satisfied in one mock");
}

fn t18() -> TestResult {
  var m = mock_new();
  mock_expect(&mut m, "ping", 1);
  mock_record(&mut m, "ping", "x");
  mock_reset(&mut m);
  record_n(&mut m, "ping", "", 1);
  var ok = mock_verified(&m);
  if mock_call_total(&m) != 1 { ok = false; }
  if mock_unexpected_count(&m) != 0 { ok = false; }
  return assert(ok, "a reset mock can be replayed");
}

fn t19() -> TestResult {
  var m = mock_new();
  mock_record(&mut m, "one", "");
  mock_record(&mut m, "two", "");
  var ok = mock_verified(&m);
  if mock_unexpected_count(&m) != 2 { ok = false; }
  if !streq(mock_call_name(&m, 1), "two") { ok = false; }
  return assert(ok, "a mock without expectations verifies but lists unexpected calls");
}

fn t20() -> TestResult {
  var m = mock_new();
  mock_expect(&mut m, "a", 1);
  mock_expect_at_least(&mut m, "b", 1);
  mock_expect_at_most(&mut m, "c", 1);
  var ok = mock_mode(&m, "a") == 0;
  if mock_mode(&m, "b") != 1 { ok = false; }
  if mock_mode(&m, "c") != 2 { ok = false; }
  if mock_expectation_index(&m, "b") != 1 { ok = false; }
  if mock_expectation_index(&m, "c") != 2 { ok = false; }
  return assert(ok, "modes and declaration indexes are reported exactly");
}

fn main() -> Int {
  io.println("=== xiom.mock conformance tests ===");
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
    io.println("xiom.mock: all tests passed");
  } else {
    io.println("xiom.mock: tests failed");
  }
  return failed;
}
