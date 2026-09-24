// XIOM -- xiom.rate conformance tests (19 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module rate_tests
use xiom.io; use xiom.test; use xiom.rate;

// Read-only operations are wrapped in helpers that take `&mut`, so a
// `&local` read call is never followed by a `&mut local` call in the same
// function body (advisory E001). Each helper calls the real `&`-based API.

fn bucket_tokens(b: &mut TokenBucket) -> Int {
  return rate_bucket_tokens(b);
}

fn bucket_capacity(b: &mut TokenBucket) -> Int {
  return rate_bucket_capacity(b);
}

fn bucket_retry(b: &mut TokenBucket, cost: Int) -> Int {
  return rate_bucket_retry_after_ms(b, cost);
}

fn window_count(w: &mut WindowLimit) -> Int {
  return rate_window_count(w);
}

fn window_retry(w: &mut WindowLimit, now_ms: Int) -> Int {
  return rate_window_retry_after_ms(w, now_ms);
}

fn t1() -> TestResult {
  var b = rate_bucket_new(5, 2, 1000);
  var ok = bucket_tokens(&mut b) == 5;
  if bucket_capacity(&mut b) != 5 { ok = false; }
  if !rate_bucket_allow(&mut b, 1000, 5) { ok = false; }
  if bucket_tokens(&mut b) != 0 { ok = false; }
  if rate_bucket_allow(&mut b, 1000, 1) { ok = false; }
  return assert(ok, "bucket starts full and its accessors report capacity");
}

fn t2() -> TestResult {
  var b = rate_bucket_new(3, 1, 0);
  var ok = rate_bucket_allow(&mut b, 0, 3);
  if bucket_tokens(&mut b) != 0 { ok = false; }
  rate_bucket_refill(&mut b, 999);
  if bucket_tokens(&mut b) != 0 { ok = false; }
  if rate_bucket_allow(&mut b, 999, 1) { ok = false; }
  rate_bucket_refill(&mut b, 1000);
  if bucket_tokens(&mut b) != 1 { ok = false; }
  if !rate_bucket_allow(&mut b, 1000, 1) { ok = false; }
  if bucket_tokens(&mut b) != 0 { ok = false; }
  return assert(ok, "refill grants exactly one token at 1000ms with refill 1");
}

fn t3() -> TestResult {
  var zero = rate_bucket_new(0, 5, 42);
  var ok = bucket_capacity(&mut zero) == 1;
  if bucket_tokens(&mut zero) != 1 { ok = false; }
  var neg = rate_bucket_new(-9, -4, 42);
  if bucket_capacity(&mut neg) != 1 { ok = false; }
  if bucket_tokens(&mut neg) != 1 { ok = false; }
  if bucket_retry(&mut neg, 1) != 0 { ok = false; }
  if !rate_bucket_allow(&mut neg, 42, 1) { ok = false; }
  if bucket_retry(&mut neg, 1) != -1 { ok = false; }
  var seven = rate_bucket_new(7, 0, 0);
  if bucket_capacity(&mut seven) != 7 { ok = false; }
  if bucket_tokens(&mut seven) != 7 { ok = false; }
  return assert(ok, "capacity clamps to at least 1 and refill to at least 0");
}

fn t4() -> TestResult {
  var b = rate_bucket_new(2, 1, 0);
  var ok = rate_bucket_allow(&mut b, 0, 2);
  rate_bucket_refill(&mut b, 500);
  if bucket_tokens(&mut b) != 0 { ok = false; }
  if rate_bucket_allow(&mut b, 500, 1) { ok = false; }
  if bucket_retry(&mut b, 1) != 1000 { ok = false; }
  rate_bucket_refill(&mut b, 1000);
  if bucket_tokens(&mut b) != 1 { ok = false; }
  if !rate_bucket_allow(&mut b, 1000, 1) { ok = false; }
  return assert(ok, "truncated 500ms refill is carried until a whole token is due");
}

fn t5() -> TestResult {
  var b = rate_bucket_new(3, 0, 0);
  var ok = rate_bucket_allow(&mut b, 0, 1);
  if !rate_bucket_allow(&mut b, 1, 2) { ok = false; }
  if bucket_tokens(&mut b) != 0 { ok = false; }
  if rate_bucket_allow(&mut b, 2, 1) { ok = false; }
  if !rate_bucket_allow(&mut b, 3, 0) { ok = false; }
  if !rate_bucket_allow(&mut b, 4, -5) { ok = false; }
  if bucket_tokens(&mut b) != 0 { ok = false; }
  return assert(ok, "allow spends exactly the requested cost");
}

fn t6() -> TestResult {
  var b = rate_bucket_new(2, 1, 0);
  var ok = !rate_bucket_allow(&mut b, 0, 3);
  if bucket_tokens(&mut b) != 2 { ok = false; }
  if !rate_bucket_allow(&mut b, 0, 2) { ok = false; }
  if bucket_tokens(&mut b) != 0 { ok = false; }
  if rate_bucket_allow(&mut b, 100, 2) { ok = false; }
  if bucket_tokens(&mut b) != 0 { ok = false; }
  return assert(ok, "allow rejects a cost above capacity without spending");
}

fn t7() -> TestResult {
  var b = rate_bucket_new(5, 2, 0);
  var ok = bucket_retry(&mut b, 1) == 0;
  if bucket_retry(&mut b, 0) != 0 { ok = false; }
  if bucket_retry(&mut b, -3) != 0 { ok = false; }
  if !rate_bucket_allow(&mut b, 0, 5) { ok = false; }
  if bucket_retry(&mut b, 1) != 500 { ok = false; }
  if bucket_retry(&mut b, 2) != 1000 { ok = false; }
  if bucket_retry(&mut b, 5) != 2500 { ok = false; }
  if bucket_retry(&mut b, 6) != 3000 { ok = false; }
  rate_bucket_refill(&mut b, 1000);
  if bucket_tokens(&mut b) != 2 { ok = false; }
  if bucket_retry(&mut b, 2) != 0 { ok = false; }
  if bucket_retry(&mut b, 5) != 1500 { ok = false; }
  return assert(ok, "retry_after reports the token cost in ms with refill 2");
}

fn t8() -> TestResult {
  var b = rate_bucket_new(4, 3, 0);
  var ok = rate_bucket_allow(&mut b, 0, 4);
  if bucket_retry(&mut b, 1) != 334 { ok = false; }
  if bucket_retry(&mut b, 2) != 667 { ok = false; }
  if bucket_retry(&mut b, 3) != 1000 { ok = false; }
  if bucket_retry(&mut b, 4) != 1334 { ok = false; }
  rate_bucket_refill(&mut b, 1000);
  if bucket_tokens(&mut b) != 3 { ok = false; }
  if bucket_retry(&mut b, 4) != 334 { ok = false; }
  return assert(ok, "retry_after rounds the wait up to the next whole token");
}

fn t9() -> TestResult {
  var b = rate_bucket_new(2, 0, 10);
  var ok = bucket_retry(&mut b, 1) == 0;
  if bucket_retry(&mut b, 2) != 0 { ok = false; }
  if !rate_bucket_allow(&mut b, 10, 2) { ok = false; }
  if bucket_retry(&mut b, 1) != -1 { ok = false; }
  if bucket_retry(&mut b, 5) != -1 { ok = false; }
  if bucket_retry(&mut b, 0) != 0 { ok = false; }
  return assert(ok, "retry_after is -1 when refill is 0 and something is owed");
}

fn t10() -> TestResult {
  var w = rate_window_new(1000, 3, 0);
  var ok = rate_window_allow(&mut w, 0);
  if !rate_window_allow(&mut w, 1) { ok = false; }
  if !rate_window_allow(&mut w, 2) { ok = false; }
  if rate_window_allow(&mut w, 3) { ok = false; }
  if rate_window_allow(&mut w, 500) { ok = false; }
  if window_count(&mut w) != 3 { ok = false; }
  return assert(ok, "window admits max_count calls then blocks");
}

fn t11() -> TestResult {
  var w = rate_window_new(1000, 2, 0);
  var ok = rate_window_allow(&mut w, 0);
  if !rate_window_allow(&mut w, 999) { ok = false; }
  if rate_window_allow(&mut w, 999) { ok = false; }
  if !rate_window_allow(&mut w, 1000) { ok = false; }
  if window_count(&mut w) != 1 { ok = false; }
  if !rate_window_allow(&mut w, 1001) { ok = false; }
  if rate_window_allow(&mut w, 1002) { ok = false; }
  if window_count(&mut w) != 2 { ok = false; }
  return assert(ok, "window resets exactly at the window boundary");
}

fn t12() -> TestResult {
  var w = rate_window_new(1000, 2, 0);
  var ok = window_retry(&mut w, 0) == 0;
  if !rate_window_allow(&mut w, 0) { ok = false; }
  if window_retry(&mut w, 0) != 0 { ok = false; }
  if !rate_window_allow(&mut w, 100) { ok = false; }
  if window_retry(&mut w, 100) != 900 { ok = false; }
  if window_retry(&mut w, 400) != 600 { ok = false; }
  if window_retry(&mut w, 999) != 1 { ok = false; }
  if window_retry(&mut w, 1000) != 0 { ok = false; }
  if window_retry(&mut w, 1500) != 0 { ok = false; }
  return assert(ok, "window retry_after counts down to the current span end");
}

fn t13() -> TestResult {
  var w = rate_window_new(200, 1, 0);
  var ok = rate_window_allow(&mut w, 0);
  if window_retry(&mut w, 0) != 200 { ok = false; }
  if window_retry(&mut w, 50) != 150 { ok = false; }
  rate_window_reset(&mut w, 5000);
  if window_count(&mut w) != 0 { ok = false; }
  if window_retry(&mut w, 5000) != 0 { ok = false; }
  if !rate_window_allow(&mut w, 5000) { ok = false; }
  if window_retry(&mut w, 5000) != 200 { ok = false; }
  if window_retry(&mut w, 5200) != 0 { ok = false; }
  if !rate_window_allow(&mut w, 5200) { ok = false; }
  return assert(ok, "window_reset rebases the span explicitly");
}

fn t14() -> TestResult {
  var b = rate_bucket_new(5, 1, 1000);
  var ok = rate_bucket_allow(&mut b, 1000, 5);
  rate_bucket_refill(&mut b, 500);
  if bucket_tokens(&mut b) != 0 { ok = false; }
  if bucket_retry(&mut b, 1) != 1000 { ok = false; }
  rate_bucket_refill(&mut b, 2000);
  if bucket_tokens(&mut b) != 1 { ok = false; }
  rate_bucket_refill(&mut b, 2999);
  if bucket_tokens(&mut b) != 1 { ok = false; }
  rate_bucket_refill(&mut b, 3000);
  if bucket_tokens(&mut b) != 2 { ok = false; }
  var w = rate_window_new(1000, 2, 1000);
  if !rate_window_allow(&mut w, 1000) { ok = false; }
  if !rate_window_allow(&mut w, 500) { ok = false; }
  if window_count(&mut w) != 2 { ok = false; }
  if window_retry(&mut w, 500) != 1500 { ok = false; }
  return assert(ok, "time going backwards changes neither bucket nor window");
}

fn t15() -> TestResult {
  var b = rate_bucket_new(0, -3, 7);
  var ok = bucket_capacity(&mut b) == 1;
  if bucket_tokens(&mut b) != 1 { ok = false; }
  if bucket_retry(&mut b, 1) != 0 { ok = false; }
  if rate_bucket_allow(&mut b, 7, 2) { ok = false; }
  if bucket_tokens(&mut b) != 1 { ok = false; }
  if !rate_bucket_allow(&mut b, 7, 1) { ok = false; }
  if bucket_retry(&mut b, 1) != -1 { ok = false; }
  var w = rate_window_new(-10, 0, 7);
  if !rate_window_allow(&mut w, 7) { ok = false; }
  if rate_window_allow(&mut w, 7) { ok = false; }
  if !rate_window_allow(&mut w, 8) { ok = false; }
  if window_count(&mut w) != 1 { ok = false; }
  return assert(ok, "zero and negative inputs are clamped");
}

fn t16() -> TestResult {
  let t0 = 4000000000000;
  var b = rate_bucket_new(1000000, 1000, t0);
  var ok = bucket_capacity(&mut b) == 1000000;
  if bucket_tokens(&mut b) != 1000000 { ok = false; }
  if !rate_bucket_allow(&mut b, t0, 1000000) { ok = false; }
  rate_bucket_refill(&mut b, t0 + 500000);
  if bucket_tokens(&mut b) != 500000 { ok = false; }
  if bucket_retry(&mut b, 1000000) != 500000 { ok = false; }
  rate_bucket_refill(&mut b, t0 + 1000000);
  if bucket_tokens(&mut b) != 1000000 { ok = false; }
  if bucket_retry(&mut b, 1000000) != 0 { ok = false; }
  var w = rate_window_new(100000, 2, t0);
  if !rate_window_allow(&mut w, t0) { ok = false; }
  if !rate_window_allow(&mut w, t0 + 99999) { ok = false; }
  if rate_window_allow(&mut w, t0 + 99999) { ok = false; }
  if window_retry(&mut w, t0 + 99999) != 1 { ok = false; }
  if !rate_window_allow(&mut w, t0 + 100000) { ok = false; }
  return assert(ok, "large millisecond values stay exact");
}

fn t17() -> TestResult {
  var a = rate_bucket_new(10, 3, 0);
  var b = rate_bucket_new(10, 3, 0);
  let a1 = rate_bucket_allow(&mut a, 0, 4);
  let b1 = rate_bucket_allow(&mut b, 0, 4);
  var ok = a1 == b1;
  if !a1 { ok = false; }
  let a2 = rate_bucket_allow(&mut a, 1000, 7);
  let b2 = rate_bucket_allow(&mut b, 1000, 7);
  if a2 != b2 { ok = false; }
  rate_bucket_refill(&mut a, 1500);
  rate_bucket_refill(&mut b, 1500);
  let a3 = rate_bucket_allow(&mut a, 2500, 9);
  let b3 = rate_bucket_allow(&mut b, 2500, 9);
  if a3 != b3 { ok = false; }
  if bucket_tokens(&mut a) != bucket_tokens(&mut b) { ok = false; }
  if bucket_retry(&mut a, 10) != bucket_retry(&mut b, 10) { ok = false; }
  if bucket_tokens(&mut a) != 6 { ok = false; }
  var wa = rate_window_new(500, 2, 0);
  var wb = rate_window_new(500, 2, 0);
  let wa1 = rate_window_allow(&mut wa, 0);
  let wb1 = rate_window_allow(&mut wb, 0);
  if wa1 != wb1 { ok = false; }
  if !rate_window_allow(&mut wa, 100) { ok = false; }
  if !rate_window_allow(&mut wb, 100) { ok = false; }
  if window_count(&mut wa) != window_count(&mut wb) { ok = false; }
  if window_retry(&mut wa, 400) != window_retry(&mut wb, 400) { ok = false; }
  if window_retry(&mut wa, 400) != 100 { ok = false; }
  return assert(ok, "identical inputs and call sequences stay deterministic");
}

fn t18() -> TestResult {
  var b = rate_bucket_new(3, 10, 0);
  var ok = rate_bucket_allow(&mut b, 0, 3);
  rate_bucket_refill(&mut b, 100);
  if bucket_tokens(&mut b) != 1 { ok = false; }
  rate_bucket_refill(&mut b, 10000);
  if bucket_tokens(&mut b) != 3 { ok = false; }
  rate_bucket_refill(&mut b, 20000);
  if bucket_tokens(&mut b) != 3 { ok = false; }
  if !rate_bucket_allow(&mut b, 20000, 3) { ok = false; }
  if bucket_tokens(&mut b) != 0 { ok = false; }
  return assert(ok, "bucket never accrues past capacity");
}

fn t19() -> TestResult {
  var b = rate_bucket_new(2, 1, 0);
  var ok = rate_bucket_allow(&mut b, 0, 2);
  if !rate_bucket_allow(&mut b, 1000, 1) { ok = false; }
  if bucket_tokens(&mut b) != 0 { ok = false; }
  if rate_bucket_allow(&mut b, 1001, 1) { ok = false; }
  return assert(ok, "allow refills before it spends");
}

fn main() -> Int {
  io.println("=== xiom.rate conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.rate: all tests passed");
  } else {
    io.println("xiom.rate: tests failed");
  }
  return failed;
}
