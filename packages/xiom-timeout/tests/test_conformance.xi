// XIOM -- xiom.timeout conformance tests (21 checks)
// Port task: prove the pure-XIOM xiom.timeout module against its SPEC.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module timeout_tests
use xiom.io; use xiom.test; use xiom.timeout;

// Every check is a named test returning TestResult from assert; main prints
// one [PASS]/[FAIL] line per test and returns the failure count. All
// functions are pure and take `&`-references only, so no borrow helpers are
// needed (there is no `&mut` call anywhere in this suite).

fn t1() -> TestResult {
  let a = timeout_new(-7, -3);
  var ok = timeout_default_ms(&a) == 0;
  if timeout_max_ms(&a) != 0 { ok = false; }
  let b = timeout_new(50, 10);
  if timeout_default_ms(&b) != 50 { ok = false; }
  if timeout_max_ms(&b) != 50 { ok = false; }
  let c = timeout_new(0, 0);
  if timeout_default_ms(&c) != 0 { ok = false; }
  if timeout_max_ms(&c) != 0 { ok = false; }
  return assert(ok, "constructor clamps default and ceiling");
}

fn t2() -> TestResult {
  let p = timeout_new(25, 250);
  var ok = timeout_default_ms(&p) == 25;
  if timeout_max_ms(&p) != 250 { ok = false; }
  return assert(ok, "accessors return the constructor values");
}

fn t3() -> TestResult {
  let p = timeout_new(100, 500);
  var ok = timeout_effective_ms(&p, -1) == 100;
  if timeout_effective_ms(&p, -999) != 100 { ok = false; }
  return assert(ok, "negative request selects the default");
}

fn t4() -> TestResult {
  let p = timeout_new(100, 500);
  var ok = timeout_effective_ms(&p, 0) == 0;
  if timeout_effective_ms(&p, 1) != 1 { ok = false; }
  if timeout_effective_ms(&p, 499) != 499 { ok = false; }
  if timeout_effective_ms(&p, 500) != 500 { ok = false; }
  if timeout_effective_ms(&p, 501) != 500 { ok = false; }
  if timeout_effective_ms(&p, 1000000) != 500 { ok = false; }
  return assert(ok, "requested budget is capped at the maximum");
}

fn t5() -> TestResult {
  let p = timeout_new(0, 0);
  var ok = timeout_effective_ms(&p, -5) == 0;
  if timeout_effective_ms(&p, 7) != 0 { ok = false; }
  return assert(ok, "zero policy collapses every request to zero");
}

fn t6() -> TestResult {
  let d = deadline_new(1000, -50);
  var ok = deadline_remaining_ms(&d, 1000) == 0;
  if !deadline_expired(&d, 1000) { ok = false; }
  let lead = deadline_new(-500, 250);
  if deadline_remaining_ms(&lead, -500) != 250 { ok = false; }
  if deadline_elapsed_ms(&lead, -500) != 0 { ok = false; }
  return assert(ok, "deadline_new clamps a negative budget to zero");
}

fn t7() -> TestResult {
  let p = timeout_new(100, 500);
  let d1 = deadline_from_policy(&p, 1000, -1);
  var ok = deadline_remaining_ms(&d1, 1000) == 100;
  if !deadline_expired(&d1, 1100) { ok = false; }
  let d2 = deadline_from_policy(&p, 1000, 200);
  if deadline_remaining_ms(&d2, 1000) != 200 { ok = false; }
  let d3 = deadline_from_policy(&p, 1000, 900);
  if deadline_remaining_ms(&d3, 1000) != 500 { ok = false; }
  return assert(ok, "from_policy uses the effective budget");
}

fn t8() -> TestResult {
  let d = deadline_new(1000, 500);
  var ok = deadline_remaining_ms(&d, 900) == 600;
  if deadline_remaining_ms(&d, 0) != 1500 { ok = false; }
  if deadline_expired(&d, 900) { ok = false; }
  return assert(ok, "remaining before the start includes the lead time");
}

fn t9() -> TestResult {
  let d = deadline_new(1000, 500);
  var ok = deadline_remaining_ms(&d, 1000) == 500;
  if deadline_remaining_ms(&d, 1200) != 300 { ok = false; }
  if deadline_remaining_ms(&d, 1499) != 1 { ok = false; }
  return assert(ok, "remaining counts down across the budget");
}

fn t10() -> TestResult {
  let d = deadline_new(1000, 500);
  var ok = deadline_remaining_ms(&d, 1500) == 0;
  if deadline_remaining_ms(&d, 1501) != 0 { ok = false; }
  if deadline_remaining_ms(&d, 100000) != 0 { ok = false; }
  return assert(ok, "remaining clamps to zero at and after expiry");
}

fn t11() -> TestResult {
  let d = deadline_new(1000, 500);
  var ok = !deadline_expired(&d, 999);
  if deadline_expired(&d, 1499) { ok = false; }
  if !deadline_expired(&d, 1500) { ok = false; }
  if !deadline_expired(&d, 1501) { ok = false; }
  return assert(ok, "expiry starts exactly at start + budget");
}

fn t12() -> TestResult {
  let d = deadline_new(1000, 500);
  var ok = deadline_elapsed_ms(&d, 900) == 0;
  if deadline_elapsed_ms(&d, 1000) != 0 { ok = false; }
  if deadline_elapsed_ms(&d, 1001) != 1 { ok = false; }
  if deadline_elapsed_ms(&d, 2000) != 1000 { ok = false; }
  return assert(ok, "elapsed is clamped below the start and grows past expiry");
}

fn t13() -> TestResult {
  let d = deadline_new(1000, 500);
  let e = deadline_extend(&d, 250);
  var ok = deadline_remaining_ms(&e, 1000) == 750;
  if deadline_remaining_ms(&e, 1250) != 500 { ok = false; }
  if deadline_expired(&e, 1250) { ok = false; }
  if deadline_remaining_ms(&d, 1000) != 500 { ok = false; }
  return assert(ok, "extend returns a longer deadline and leaves the original");
}

fn t14() -> TestResult {
  let d = deadline_new(1000, 500);
  let shrink = deadline_extend(&d, -100);
  var ok = deadline_remaining_ms(&shrink, 1000) == 400;
  let to_zero = deadline_extend(&d, -500);
  if deadline_remaining_ms(&to_zero, 1000) != 0 { ok = false; }
  if !deadline_expired(&to_zero, 1000) { ok = false; }
  let below = deadline_extend(&d, -1000);
  if deadline_remaining_ms(&below, 1000) != 0 { ok = false; }
  if deadline_remaining_ms(&below, 0) != 1000 { ok = false; }
  return assert(ok, "extend clamps a negative extension at zero");
}

fn t15() -> TestResult {
  let d = deadline_new(0, 100);
  let r = deadline_reset(&d, 5000, 200);
  var ok = deadline_remaining_ms(&r, 5000) == 200;
  if deadline_remaining_ms(&r, 5100) != 100 { ok = false; }
  if !deadline_expired(&r, 5200) { ok = false; }
  if deadline_elapsed_ms(&r, 5000) != 0 { ok = false; }
  if deadline_remaining_ms(&d, 50) != 50 { ok = false; }
  return assert(ok, "reset rebases the deadline at a new start and budget");
}

fn t16() -> TestResult {
  let d = deadline_new(0, 100);
  let r = deadline_reset(&d, 2000, -10);
  var ok = deadline_remaining_ms(&r, 2000) == 0;
  if !deadline_expired(&r, 2000) { ok = false; }
  if deadline_elapsed_ms(&r, 2000) != 0 { ok = false; }
  if deadline_remaining_ms(&r, 3000) != 0 { ok = false; }
  return assert(ok, "reset clamps a negative budget to zero");
}

fn t17() -> TestResult {
  let d = deadline_new(1000, 400);
  var ok = deadline_progress_permille(&d, 1000) == 0;
  if deadline_progress_permille(&d, 900) != 0 { ok = false; }
  return assert(ok, "progress is zero at and before the start");
}

fn t18() -> TestResult {
  let d = deadline_new(1000, 400);
  var ok = deadline_progress_permille(&d, 1200) == 500;
  let third = deadline_new(0, 3);
  if deadline_progress_permille(&third, 1) != 333 { ok = false; }
  if deadline_progress_permille(&third, 2) != 666 { ok = false; }
  if deadline_progress_permille(&third, 3) != 1000 { ok = false; }
  return assert(ok, "progress reports elapsed permille at the midpoint");
}

fn t19() -> TestResult {
  let d = deadline_new(1000, 400);
  var ok = deadline_progress_permille(&d, 1400) == 1000;
  if deadline_progress_permille(&d, 9999) != 1000 { ok = false; }
  if deadline_progress_permille(&d, 1399) != 997 { ok = false; }
  return assert(ok, "progress clamps to 1000 after expiry");
}

fn t20() -> TestResult {
  let d = deadline_new(1000, 0);
  var ok = deadline_remaining_ms(&d, 999) == 1;
  if deadline_expired(&d, 999) { ok = false; }
  if deadline_remaining_ms(&d, 1000) != 0 { ok = false; }
  if !deadline_expired(&d, 1000) { ok = false; }
  if deadline_progress_permille(&d, 1000) != 1000 { ok = false; }
  if deadline_progress_permille(&d, 999) != 0 { ok = false; }
  return assert(ok, "zero budget expires exactly at the start instant");
}

fn t21() -> TestResult {
  let start = 1000000000000;
  let d = deadline_new(start, 3600000000000);
  var ok = deadline_remaining_ms(&d, start + 1800000000000) == 1800000000000;
  if deadline_progress_permille(&d, start + 1800000000000) != 500 { ok = false; }
  if !deadline_expired(&d, start + 3600000000000) { ok = false; }
  if deadline_remaining_ms(&d, start + 3599999999999) != 1 { ok = false; }
  if deadline_elapsed_ms(&d, start + 3600000000000) != 3600000000000 { ok = false; }
  return assert(ok, "large millisecond values stay exact");
}

fn main() -> Int {
  io.println("=== xiom.timeout conformance tests ===");
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
    io.println("xiom.timeout: all tests passed");
  } else {
    io.println("xiom.timeout: tests failed");
  }
  return failed;
}
