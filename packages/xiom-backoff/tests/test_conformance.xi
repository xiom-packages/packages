// XIOM -- xiom.backoff conformance tests (22 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Greenfield package: prove the pure-XIOM xiom.backoff policies and retry
// state machine against the documented integer arithmetic, jitter rules,
// cap order, saturation bound and error catalog.
//
// Every expected delay is a hand-computed integer; nothing here depends on a
// clock, a random source or the platform. Str comparisons go through
// str_compare.

module backoff_tests
use xiom.io; use xiom.test; use xiom.backoff;
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

// True when backoff_delay yields exactly `want`.
fn delay_is(p: &BackoffPolicy, attempt: Int, unit: Int, want: Int) -> Bool {
  let r = backoff_delay(p, attempt, unit);
  match r {
    Ok(v) => { return v == want; },
    Err(_) => { return false; },
  }
  return false;
}

// True when backoff_raw_delay yields exactly `want`.
fn raw_is(p: &BackoffPolicy, attempt: Int, want: Int) -> Bool {
  let r = backoff_raw_delay(p, attempt);
  match r {
    Ok(v) => { return v == want; },
    Err(_) => { return false; },
  }
  return false;
}

// True when the next retry delay is exactly `want`.
fn next_is(s: &mut RetryState, unit: Int, want: Int) -> Bool {
  let r = retry_next(s, unit);
  match r {
    Ok(v) => { return v == want; },
    Err(_) => { return false; },
  }
  return false;
}

// A hand-built policy for out-of-range field tests.
fn policy_with(kind: Int, base: Int, step: Int, fnum: Int, fden: Int, cap: Int, jitter: Int) -> BackoffPolicy {
  return BackoffPolicy{
    kind: kind;
    base_ms: base;
    step_ms: step;
    factor_num: fnum;
    factor_den: fden;
    cap_ms: cap;
    jitter: jitter;
  };
}

fn t1() -> TestResult {
  let p = backoff_constant(500);
  var ok = backoff_kind(&p) == 0;
  if backoff_base(&p) != 500 { ok = false; }
  if !delay_is(&p, 1, 0, 500) { ok = false; }
  if !delay_is(&p, 7, 9999, 500) { ok = false; }
  if !raw_is(&p, 3, 500) { ok = false; }
  return assert(ok, "constant policies wait the same delay for every attempt");
}

fn t2() -> TestResult {
  let p = backoff_linear(100, 50, -1);
  var ok = backoff_kind(&p) == 1;
  if !delay_is(&p, 1, 0, 100) { ok = false; }
  if !delay_is(&p, 2, 0, 150) { ok = false; }
  if !delay_is(&p, 3, 0, 200) { ok = false; }
  if !delay_is(&p, 5, 0, 300) { ok = false; }
  return assert(ok, "linear policies add one step per attempt");
}

fn t3() -> TestResult {
  let p = backoff_linear(100, 50, 200);
  var ok = backoff_cap_ms(&p) == 200;
  if !delay_is(&p, 3, 0, 200) { ok = false; }
  if !delay_is(&p, 9, 0, 200) { ok = false; }
  if !raw_is(&p, 9, 500) { ok = false; }
  let uncapped = backoff_linear(1, 1, -3);
  if backoff_cap_ms(&uncapped) != -3 { ok = false; }
  return assert(ok, "the cap bounds the delay but not the raw growth");
}

fn t4() -> TestResult {
  let p = backoff_exponential(100, 2, 1, -1);
  var ok = backoff_kind(&p) == 2;
  if backoff_factor_num(&p) != 2 { ok = false; }
  if backoff_factor_den(&p) != 1 { ok = false; }
  if !delay_is(&p, 1, 0, 100) { ok = false; }
  if !delay_is(&p, 2, 0, 200) { ok = false; }
  if !delay_is(&p, 4, 0, 800) { ok = false; }
  return assert(ok, "exponential policies double per attempt");
}

fn t5() -> TestResult {
  let p = backoff_exponential(100, 3, 2, -1);
  var ok = delay_is(&p, 1, 0, 100);
  if !delay_is(&p, 2, 0, 150) { ok = false; }
  if !delay_is(&p, 3, 0, 225) { ok = false; }
  if !delay_is(&p, 4, 0, 337) { ok = false; }
  return assert(ok, "fractional growth truncates after every multiply");
}

fn t6() -> TestResult {
  let p = backoff_exponential(100, 2, 1, 500);
  var ok = delay_is(&p, 3, 0, 400);
  if !delay_is(&p, 4, 0, 500) { ok = false; }
  if !delay_is(&p, 8, 0, 500) { ok = false; }
  return assert(ok, "exponential growth saturates at the cap");
}

fn t7() -> TestResult {
  let flat = backoff_constant(-5);
  var ok = backoff_base(&flat) == 0;
  let lin = backoff_linear(-1, -2, -1);
  if backoff_base(&lin) != 0 { ok = false; }
  if backoff_step(&lin) != 0 { ok = false; }
  let exp = backoff_exponential(10, 0, 0, -1);
  if backoff_factor_num(&exp) != 1 { ok = false; }
  if backoff_factor_den(&exp) != 1 { ok = false; }
  let odd = backoff_with_jitter(&exp, 7);
  if backoff_jitter_mode(&odd) != 0 { ok = false; }
  let equal = backoff_with_jitter(&exp, 2);
  if backoff_jitter_mode(&equal) != 2 { ok = false; }
  let capped = backoff_with_cap(&exp, 12);
  if backoff_cap_ms(&capped) != 12 { ok = false; }
  return assert(ok, "constructors clamp base, step and factors");
}

fn t8() -> TestResult {
  let p = backoff_with_jitter(&backoff_constant(100), 1);
  var ok = delay_is(&p, 1, 0, 0);
  if !delay_is(&p, 1, 5000, 50) { ok = false; }
  if !delay_is(&p, 1, 9999, 99) { ok = false; }
  return assert(ok, "full jitter scales the delay by the unit");
}

fn t9() -> TestResult {
  let p = backoff_with_jitter(&backoff_constant(100), 2);
  var ok = delay_is(&p, 1, 0, 50);
  if !delay_is(&p, 1, 5000, 75) { ok = false; }
  if !delay_is(&p, 1, 9999, 99) { ok = false; }
  return assert(ok, "equal jitter keeps half the delay and spreads the rest");
}

fn t10() -> TestResult {
  let p = backoff_with_jitter(&backoff_linear(1000, 0, 400), 1);
  var ok = delay_is(&p, 1, 9999, 399);
  if !delay_is(&p, 1, 0, 0) { ok = false; }
  return assert(ok, "the cap is applied before jitter");
}

fn t11() -> TestResult {
  let p = backoff_constant(100);
  var ok = err_is(backoff_delay(&p, 0, 0), "backoff: bad attempt 0");
  if !err_is(backoff_delay(&p, -3, 0), "backoff: bad attempt -3") { ok = false; }
  if !err_is(backoff_raw_delay(&p, 0), "backoff: bad attempt 0") { ok = false; }
  return assert(ok, "attempt numbers below 1 are Err");
}

fn t12() -> TestResult {
  let p = backoff_with_jitter(&backoff_constant(100), 1);
  var ok = err_is(backoff_delay(&p, 1, -1), "backoff: bad jitter unit -1");
  if !err_is(backoff_delay(&p, 1, 10000), "backoff: bad jitter unit 10000") { ok = false; }
  return assert(ok, "jitter units must lie in [0, 10000)");
}

fn t13() -> TestResult {
  let bad = policy_with(0, 100, 0, 1, 1, -1, 3);
  var ok = err_is(backoff_delay(&bad, 1, 0), "backoff: bad jitter mode 3");
  let low = policy_with(0, 100, 0, 1, 1, -1, -1);
  if !err_is(backoff_delay(&low, 1, 0), "backoff: bad jitter mode -1") { ok = false; }
  return assert(ok, "a hand-built out-of-range jitter mode is Err");
}

fn t14() -> TestResult {
  let p = backoff_exponential(1, 10, 1, -1);
  var ok = backoff_max_delay() == 1000000000000;
  if !delay_is(&p, 20, 0, 1000000000000) { ok = false; }
  if !raw_is(&p, 13, 1000000000000) { ok = false; }
  if !delay_is(&p, 12, 0, 100000000000) { ok = false; }
  return assert(ok, "exponential growth saturates at the documented bound");
}

fn t15() -> TestResult {
  let p = backoff_linear(1, 1000000000000, -1);
  var ok = raw_is(&p, 2, 1000000000000);
  if !delay_is(&p, 3, 0, 1000000000000) { ok = false; }
  return assert(ok, "linear growth saturates at the documented bound");
}

fn t16() -> TestResult {
  let p = backoff_exponential(100, 2, 1, -1);
  var s = retry_new(&p, 3);
  var ok = retry_used(&s) == 0;
  if retry_remaining(&s) != 3 { ok = false; }
  if retry_exhausted(&s) { ok = false; }
  if !next_is(&mut s, 0, 100) { ok = false; }
  if !next_is(&mut s, 0, 200) { ok = false; }
  if !next_is(&mut s, 0, 400) { ok = false; }
  if retry_used(&s) != 3 { ok = false; }
  if !retry_exhausted(&s) { ok = false; }
  if !err_is(retry_next(&mut s, 0), "backoff: attempts exhausted") { ok = false; }
  if retry_used(&s) != 3 { ok = false; }
  return assert(ok, "retry_next walks the policy and stops at the budget");
}

fn t17() -> TestResult {
  let p = backoff_linear(10, 10, -1);
  var s = retry_new(&p, 2);
  var ok = next_is(&mut s, 0, 10);
  if !next_is(&mut s, 0, 20) { ok = false; }
  if !retry_exhausted(&s) { ok = false; }
  retry_reset(&mut s);
  if retry_used(&s) != 0 { ok = false; }
  if retry_remaining(&s) != 2 { ok = false; }
  if !next_is(&mut s, 0, 10) { ok = false; }
  return assert(ok, "retry_reset restores the full budget");
}

fn t18() -> TestResult {
  let p = backoff_constant(5);
  var zero = retry_new(&p, 0);
  var ok = retry_exhausted(&zero);
  if retry_remaining(&zero) != 0 { ok = false; }
  if !err_is(retry_next(&mut zero, 0), "backoff: attempts exhausted") { ok = false; }
  var neg = retry_new(&p, -4);
  if !retry_exhausted(&neg) { ok = false; }
  return assert(ok, "zero and negative budgets are exhausted immediately");
}

fn t19() -> TestResult {
  let p = backoff_with_jitter(&backoff_constant(100), 1);
  var s = retry_new(&p, 2);
  var ok = retry_max_attempts(&s) == 2;
  if !next_is(&mut s, 5000, 50) { ok = false; }
  if !next_is(&mut s, 9999, 99) { ok = false; }
  return assert(ok, "retry_next applies jitter like backoff_delay");
}

fn t20() -> TestResult {
  var p = backoff_constant(10);
  var s = retry_new(&p, 2);
  p.base_ms = 99;
  var ok = !next_is(&mut s, 0, 99);
  if !next_is(&mut s, 0, 10) { ok = false; }
  if backoff_base(&p) != 99 { ok = false; }
  return assert(ok, "retry states snapshot the policy at construction");
}

fn t21() -> TestResult {
  let p = backoff_constant(100);
  var s = retry_new(&p, 2);
  var ok = err_is(retry_next(&mut s, 10000), "backoff: bad jitter unit 10000");
  if retry_used(&s) != 0 { ok = false; }
  if !next_is(&mut s, 0, 100) { ok = false; }
  if retry_used(&s) != 1 { ok = false; }
  return assert(ok, "a failed retry_next does not consume an attempt");
}

fn t22() -> TestResult {
  let p = backoff_constant(1);
  var s = retry_new(&p, 3);
  var ok = retry_max_attempts(&s) == 3;
  if retry_remaining(&s) != 3 { ok = false; }
  if !next_is(&mut s, 0, 1) { ok = false; }
  if retry_remaining(&s) != 2 { ok = false; }
  if retry_exhausted(&s) { ok = false; }
  if retry_used(&s) != 1 { ok = false; }
  return assert(ok, "retry accessors report the budget state");
}

fn main() -> Int {
  io.println("=== xiom.backoff conformance tests ===");
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
    io.println("xiom.backoff: all tests passed");
  } else {
    io.println("xiom.backoff: tests failed");
  }
  return failed;
}
