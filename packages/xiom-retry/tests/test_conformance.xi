// XIOM -- xiom.retry conformance tests (21 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module retry_tests
use xiom.io; use xiom.test; use xiom.retry;

// Read-only operations are wrapped in small helpers that take `&mut`, so a
// `&local` read call is never followed by a `&mut local` call in the same
// function body (advisory E001). Each helper calls the real `&`-based API.

fn state_attempts(st: &mut RetryState) -> Int {
  return retry_state_attempts(st);
}

fn state_last_delay(st: &mut RetryState) -> Int {
  return retry_state_last_delay(st);
}

fn next_is(st: &mut RetryState, p: &RetryPolicy, want: Int) -> Bool {
  let got = retry_state_next(st, p);
  match got {
    Some(v) => { return v == want; },
    None => {},
  }
  return false;
}

fn next_none(st: &mut RetryState, p: &RetryPolicy) -> Bool {
  let got = retry_state_next(st, p);
  match got {
    Some(_) => { return false; },
    None => { return true; },
  }
  return true;
}

fn state_of(c: &mut CircuitBreaker) -> Int {
  return circuit_state(c);
}

fn allow_at(c: &mut CircuitBreaker, now_secs: Int) -> Bool {
  return circuit_allow(c, now_secs);
}

fn half_open_at(c: &mut CircuitBreaker, now_secs: Int) -> Bool {
  return circuit_is_half_open(c, now_secs);
}

fn failures_of(c: &mut CircuitBreaker) -> Int {
  return circuit_failures(c);
}

fn trips_of(c: &mut CircuitBreaker) -> Int {
  return circuit_trips(c);
}

fn t1() -> TestResult {
  let p = retry_new(5, 1, 2, 60);
  var ok = retry_delay_secs(&p, 1) == 1;
  if retry_delay_secs(&p, 2) != 2 { ok = false; }
  if retry_delay_secs(&p, 3) != 4 { ok = false; }
  if retry_delay_secs(&p, 4) != 8 { ok = false; }
  return assert(ok, "delay grows 1,2,4,8 with base 1 factor 2");
}

fn t2() -> TestResult {
  let p = retry_new(8, 1, 2, 10);
  var ok = retry_delay_secs(&p, 4) == 8;
  if retry_delay_secs(&p, 5) != 10 { ok = false; }
  if retry_delay_secs(&p, 6) != 10 { ok = false; }
  if retry_delay_secs(&p, 8) != 10 { ok = false; }
  return assert(ok, "delay clamps at max_delay_secs");
}

fn t3() -> TestResult {
  let p = retry_new(4, 3, 1, 9);
  var ok = retry_delay_secs(&p, 1) == 3;
  if retry_delay_secs(&p, 2) != 3 { ok = false; }
  if retry_delay_secs(&p, 4) != 3 { ok = false; }
  if retry_delay_secs(&p, 100) != 3 { ok = false; }
  return assert(ok, "factor 1 keeps the delay constant");
}

fn t4() -> TestResult {
  let p = retry_new(0, -5, 0, -9);
  var ok = retry_max_attempts(&p) == 1;
  if retry_base_delay_secs(&p) != 0 { ok = false; }
  if retry_factor(&p) != 1 { ok = false; }
  if retry_max_delay_secs(&p) != 0 { ok = false; }
  let q = retry_new(-2, 4, -3, 1);
  if retry_max_attempts(&q) != 1 { ok = false; }
  if retry_base_delay_secs(&q) != 4 { ok = false; }
  if retry_factor(&q) != 1 { ok = false; }
  if retry_max_delay_secs(&q) != 4 { ok = false; }
  return assert(ok, "constructor clamps attempts, base, factor and ceiling");
}

fn t5() -> TestResult {
  let p = retry_new(2, 3, 4, 5);
  var ok = retry_max_attempts(&p) == 2;
  if retry_base_delay_secs(&p) != 3 { ok = false; }
  if retry_factor(&p) != 4 { ok = false; }
  if retry_max_delay_secs(&p) != 5 { ok = false; }
  return assert(ok, "accessors return the constructor values");
}

fn t6() -> TestResult {
  let p = retry_new(3, 2, 3, 50);
  var ok = retry_delay_secs(&p, 1) == 2;
  if retry_delay_secs(&p, 3) != 18 { ok = false; }
  if retry_delay_secs(&p, 4) != 50 { ok = false; }
  if retry_delay_secs(&p, 10) != 50 { ok = false; }
  if retry_delay_secs(&p, 1000) != 50 { ok = false; }
  return assert(ok, "attempts beyond the budget stay clamped and formulaic");
}

fn t7() -> TestResult {
  let p = retry_new(3, 1, 2, 8);
  var ok = retry_should_retry(&p, 0);
  if !retry_should_retry(&p, 2) { ok = false; }
  if retry_should_retry(&p, 3) { ok = false; }
  if retry_should_retry(&p, 4) { ok = false; }
  let q = retry_new(0, 1, 2, 8);
  if !retry_should_retry(&q, 0) { ok = false; }
  if retry_should_retry(&q, 1) { ok = false; }
  return assert(ok, "should_retry stops exactly at the attempt budget");
}

fn t8() -> TestResult {
  let p = retry_new(3, 1, 2, 5);
  var st = retry_state_new();
  var ok = state_attempts(&mut st) == 0;
  if state_last_delay(&mut st) != 0 { ok = false; }
  if !next_is(&mut st, &p, 1) { ok = false; }
  if state_attempts(&mut st) != 1 { ok = false; }
  if state_last_delay(&mut st) != 1 { ok = false; }
  if !next_is(&mut st, &p, 2) { ok = false; }
  if !next_is(&mut st, &p, 4) { ok = false; }
  if !next_none(&mut st, &p) { ok = false; }
  if state_attempts(&mut st) != 3 { ok = false; }
  if state_last_delay(&mut st) != 4 { ok = false; }
  return assert(ok, "state yields Some(1), Some(2), Some(4) then None");
}

fn t9() -> TestResult {
  let p = retry_new(1, 5, 1, 5);
  var st = retry_state_new();
  var ok = next_is(&mut st, &p, 5);
  if !next_none(&mut st, &p) { ok = false; }
  if state_attempts(&mut st) != 1 { ok = false; }
  retry_state_reset(&mut st);
  if state_attempts(&mut st) != 0 { ok = false; }
  if state_last_delay(&mut st) != 0 { ok = false; }
  if !next_is(&mut st, &p, 5) { ok = false; }
  if state_attempts(&mut st) != 1 { ok = false; }
  return assert(ok, "state reset restores a fresh counter");
}

fn t10() -> TestResult {
  let p = retry_new(4, 2, 2, 100);
  var st = retry_state_new();
  var ok = next_is(&mut st, &p, 2);
  if state_last_delay(&mut st) != 2 { ok = false; }
  if !next_is(&mut st, &p, 4) { ok = false; }
  if state_last_delay(&mut st) != 4 { ok = false; }
  if !next_is(&mut st, &p, 8) { ok = false; }
  if !next_is(&mut st, &p, 16) { ok = false; }
  if !next_none(&mut st, &p) { ok = false; }
  if state_last_delay(&mut st) != 16 { ok = false; }
  return assert(ok, "last_delay tracks the most recent computed delay");
}

fn t11() -> TestResult {
  let p = retry_new(6, 4, 2, 100);
  var ok = true;
  var attempt = 1;
  while attempt <= 4 {
    let delay = retry_delay_secs(&p, attempt);
    var seed = 0;
    while seed <= 4 {
      let j = retry_jittered_delay(&p, attempt, seed);
      if j < delay / 2 { ok = false; }
      if j > delay { ok = false; }
      seed = seed + 1;
    }
    attempt = attempt + 1;
  }
  return assert(ok, "jittered delay stays inside [delay/2, delay]");
}

fn t12() -> TestResult {
  let p = retry_new(6, 4, 2, 100);
  let a = retry_jittered_delay(&p, 3, 42);
  let b = retry_jittered_delay(&p, 3, 42);
  let c = retry_jittered_delay(&p, 4, 7);
  let d = retry_jittered_delay(&p, 4, 7);
  var ok = a == b;
  if c != d { ok = false; }
  if a < 8 { ok = false; }
  if a > 16 { ok = false; }
  return assert(ok, "same seed and attempt give the same jitter");
}

fn t13() -> TestResult {
  var cb = circuit_new(3, 10);
  var ok = state_of(&mut cb) == 0;
  if !allow_at(&mut cb, 0) { ok = false; }
  if !allow_at(&mut cb, 999) { ok = false; }
  if half_open_at(&mut cb, 999) { ok = false; }
  if failures_of(&mut cb) != 0 { ok = false; }
  if trips_of(&mut cb) != 0 { ok = false; }
  return assert(ok, "closed breaker allows calls");
}

fn t14() -> TestResult {
  var cb = circuit_new(3, 10);
  circuit_record_failure(&mut cb, 100);
  var ok = state_of(&mut cb) == 0;
  if failures_of(&mut cb) != 1 { ok = false; }
  circuit_record_failure(&mut cb, 101);
  if state_of(&mut cb) != 0 { ok = false; }
  if failures_of(&mut cb) != 2 { ok = false; }
  if trips_of(&mut cb) != 0 { ok = false; }
  circuit_record_failure(&mut cb, 102);
  if state_of(&mut cb) != 1 { ok = false; }
  if failures_of(&mut cb) != 3 { ok = false; }
  if trips_of(&mut cb) != 1 { ok = false; }
  if allow_at(&mut cb, 103) { ok = false; }
  return assert(ok, "failures trip the breaker at the threshold");
}

fn t15() -> TestResult {
  var cb = circuit_new(1, 10);
  circuit_record_failure(&mut cb, 100);
  var ok = state_of(&mut cb) == 1;
  if allow_at(&mut cb, 100) { ok = false; }
  if allow_at(&mut cb, 105) { ok = false; }
  if allow_at(&mut cb, 109) { ok = false; }
  if half_open_at(&mut cb, 109) { ok = false; }
  if trips_of(&mut cb) != 1 { ok = false; }
  return assert(ok, "open breaker blocks calls before the reset window");
}

fn t16() -> TestResult {
  var cb = circuit_new(1, 10);
  circuit_record_failure(&mut cb, 100);
  var ok = allow_at(&mut cb, 110);
  if !allow_at(&mut cb, 111) { ok = false; }
  if !allow_at(&mut cb, 200) { ok = false; }
  return assert(ok, "allow resumes at opened_at + reset_after_secs");
}

fn t17() -> TestResult {
  var cb = circuit_new(1, 10);
  circuit_record_failure(&mut cb, 100);
  var ok = state_of(&mut cb) == 1;
  if half_open_at(&mut cb, 100) { ok = false; }
  if half_open_at(&mut cb, 109) { ok = false; }
  if !half_open_at(&mut cb, 110) { ok = false; }
  return assert(ok, "half-open starts exactly at the probe window");
}

fn t18() -> TestResult {
  var cb = circuit_new(2, 10);
  circuit_record_failure(&mut cb, 100);
  circuit_record_failure(&mut cb, 101);
  var ok = state_of(&mut cb) == 1;
  if trips_of(&mut cb) != 1 { ok = false; }
  circuit_record_success(&mut cb, 120);
  if state_of(&mut cb) != 0 { ok = false; }
  if failures_of(&mut cb) != 0 { ok = false; }
  if trips_of(&mut cb) != 1 { ok = false; }
  if !allow_at(&mut cb, 120) { ok = false; }
  if half_open_at(&mut cb, 120) { ok = false; }
  return assert(ok, "successful probe closes the breaker and clears failures");
}

fn t19() -> TestResult {
  var cb = circuit_new(2, 10);
  circuit_record_failure(&mut cb, 100);
  circuit_record_failure(&mut cb, 101);
  circuit_record_failure(&mut cb, 105);
  var ok = trips_of(&mut cb) == 1;
  if state_of(&mut cb) != 1 { ok = false; }
  if failures_of(&mut cb) != 2 { ok = false; }
  if allow_at(&mut cb, 106) { ok = false; }
  circuit_record_failure(&mut cb, 111);
  if trips_of(&mut cb) != 2 { ok = false; }
  if state_of(&mut cb) != 1 { ok = false; }
  if allow_at(&mut cb, 115) { ok = false; }
  if !allow_at(&mut cb, 121) { ok = false; }
  return assert(ok, "failed probe re-opens the window and bumps trips");
}

fn t20() -> TestResult {
  var cb = circuit_new(1, 10);
  circuit_record_failure(&mut cb, 5);
  var ok = state_of(&mut cb) == 1;
  circuit_reset(&mut cb);
  if state_of(&mut cb) != 0 { ok = false; }
  if failures_of(&mut cb) != 0 { ok = false; }
  if trips_of(&mut cb) != 0 { ok = false; }
  if !allow_at(&mut cb, 0) { ok = false; }
  if half_open_at(&mut cb, 0) { ok = false; }
  return assert(ok, "circuit_reset restores the closed breaker");
}

fn t21() -> TestResult {
  var cb = circuit_new(0, -7);
  circuit_record_failure(&mut cb, 50);
  var ok = state_of(&mut cb) == 1;
  if trips_of(&mut cb) != 1 { ok = false; }
  if !allow_at(&mut cb, 50) { ok = false; }
  if !half_open_at(&mut cb, 50) { ok = false; }
  return assert(ok, "circuit_new clamps threshold to 1 and window to 0");
}

fn main() -> Int {
  io.println("=== xiom.retry conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.retry: all tests passed");
  } else {
    io.println("xiom.retry: tests failed");
  }
  return failed;
}
