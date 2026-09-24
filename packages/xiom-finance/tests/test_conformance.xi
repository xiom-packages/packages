// Port task: xiom.finance conformance tests (31 checks) -- prove the pure-XIOM
// integer time-value-of-money module: simple and compound interest, APY,
// annuity payments, total interest, NPV and doubling time.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// All money is in cents and all rates are in permille (1% = 10). Every
// division in the module under test truncates toward zero; the expectations
// below are the exact integers produced by the documented recurrences.
// Vec[Int] element reads go through typed let bindings: untyped indexed
// reads mis-lower in v0.61.3.

module finance_tests
use xiom.io; use xiom.test; use xiom.finance;

fn fv0() -> Vec[Int] {
  var v = Vec[Int].new();
  return v;
}

fn fv1(a: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  return v;
}

fn fv2(a: Int, b: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  return v;
}

fn fv3(a: Int, b: Int, c: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  return v;
}

fn t01_simple_known() -> TestResult {
  let got = finance_simple_interest_cents(100000, 50, 2);
  return assert(got == 10000, "simple interest of 100000 cents at 50 permille for 2 periods is 10000 cents");
}

fn t02_simple_zero() -> TestResult {
  var ok = finance_simple_interest_cents(100000, 0, 5) == 0;
  if finance_simple_interest_cents(0, 50, 10) != 0 { ok = false; }
  return assert(ok, "simple interest is 0 when the rate or the principal is 0");
}

fn t03_simple_negative_rate() -> TestResult {
  var ok = finance_simple_interest_cents(100000, -50, 2) == -10000;
  if finance_simple_interest_cents(100000, -3, 7) != -2100 { ok = false; }
  return assert(ok, "negative simple rates are allowed and stay signed");
}

fn t04_simple_truncation() -> TestResult {
  var ok = finance_simple_interest_cents(101, 10, 1) == 1;
  if finance_simple_interest_cents(-101, 10, 1) != -1 { ok = false; }
  if finance_simple_interest_cents(199, 10, 1) != 1 { ok = false; }
  return assert(ok, "simple interest truncates toward zero (1010/1000 -> 1, -1010/1000 -> -1)");
}

fn t05_compound_known() -> TestResult {
  let got = finance_compound_cents(10000, 50, 2);
  return assert(got == 11025, "compound 10000 cents at 50 permille for 2 periods is 11025 cents");
}

fn t06_compound_single_step_truncation() -> TestResult {
  var ok = finance_compound_cents(101, 10, 1) == 102;
  if finance_compound_cents(9999, 10, 1) != 10098 { ok = false; }
  return assert(ok, "one compound step truncates toward zero (102.01 -> 102, 10098.99 -> 10098)");
}

fn t07_compound_truncation_compounds() -> TestResult {
  var ok = finance_compound_cents(333, 50, 1) == 349;
  if finance_compound_cents(333, 50, 2) != 366 { ok = false; }
  return assert(ok, "333 at 50 permille is 349 (349.65) then 366 (366.45): truncation compounds");
}

fn t08_compound_zero_and_nonpositive_periods() -> TestResult {
  var ok = finance_compound_cents(10000, 0, 10) == 10000;
  if finance_compound_cents(12345, 50, 0) != 12345 { ok = false; }
  if finance_compound_cents(12345, 50, -3) != 12345 { ok = false; }
  return assert(ok, "zero rate keeps the balance and periods <= 0 returns the principal");
}

fn t09_compound_negative_rate() -> TestResult {
  var ok = finance_compound_cents(10000, -50, 2) == 9025;
  if finance_compound_cents(-10000, 50, 2) != -11025 { ok = false; }
  return assert(ok, "compound handles negative rates and negative principals");
}

fn t10_apy_zero() -> TestResult {
  var ok = finance_apy_permille(0, 12) == 0;
  if finance_apy_permille(0, 1) != 0 { ok = false; }
  if finance_apy_permille(0, -5) != 0 { ok = false; }
  return assert(ok, "a 0 nominal rate gives a 0 APY at any compounding frequency");
}

fn t11_apy_monthly_known() -> TestResult {
  let got = finance_apy_permille(100, 12);
  return assert(got == 104, "10% nominal compounded monthly gives 104 permille APY (104.713 exact)");
}

fn t12_apy_exact_cases() -> TestResult {
  var ok = finance_apy_permille(200, 2) == 210;
  if finance_apy_permille(100, 1) != 100 { ok = false; }
  return assert(ok, "20% compounded twice is exactly 210 permille; annual compounding is the nominal rate");
}

fn t13_apy_clamps_periods() -> TestResult {
  var ok = finance_apy_permille(75, 0) == 75;
  if finance_apy_permille(75, -4) != 75 { ok = false; }
  if finance_apy_permille(-100, 1) != -100 { ok = false; }
  return assert(ok, "periods_per_year below 1 is clamped to 1 (APY == nominal)");
}

fn t14_apy_total_loss_clamp() -> TestResult {
  var ok = finance_apy_permille(-2000, 1) == -1000;
  if finance_apy_permille(-1000, 1) != -1000 { ok = false; }
  return assert(ok, "a nominal rate at or below -100% per period clamps to -1000 permille");
}

fn t15_payment_zero_rate_ceil() -> TestResult {
  var ok = finance_payment_cents(100000, 0, 3) == 33334;
  if finance_payment_cents(100000, 0, 4) != 25000 { ok = false; }
  if finance_payment_cents(7, 0, 2) != 4 { ok = false; }
  if finance_payment_cents(-7, 0, 2) != -3 { ok = false; }
  return assert(ok, "zero-rate payment is ceil(principal / periods), truncation-toward-zero for negatives");
}

fn t16_payment_known_annuity() -> TestResult {
  let got = finance_payment_cents(100000, 50, 2);
  // Exact rational payment is 53780.48... cents; the scaled millionths
  // annuity-factor iteration truncates to 53780.
  return assert(got == 53780, "known annuity: 100000 cents at 50 permille over 2 periods pays 53780 cents");
}

fn t17_payment_known_twelve_periods() -> TestResult {
  let got = finance_payment_cents(100000, 10, 12);
  // Exact rational payment is 8884.88... cents; the iteration gives 8884.
  return assert(got == 8884, "known annuity: 100000 cents at 10 permille over 12 periods pays 8884 cents");
}

fn t18_payment_periods_nonpositive() -> TestResult {
  var ok = finance_payment_cents(100000, 50, 0) == 0;
  if finance_payment_cents(100000, 50, -2) != 0 { ok = false; }
  return assert(ok, "payment is 0 when periods <= 0");
}

fn t19_payment_negative_rate() -> TestResult {
  let got = finance_payment_cents(100000, -50, 2);
  return assert(got == 46282, "negative rate annuity: 100000 cents at -50 permille over 2 periods pays 46282 cents");
}

fn t20_payment_rate_below_minus_1000() -> TestResult {
  var ok = finance_payment_cents(100000, -1000, 2) == 0;
  if finance_payment_cents(100000, -5000, 2) != 0 { ok = false; }
  return assert(ok, "payment is 0 at or beyond -100% per period (annuity factor diverges)");
}

fn t21_total_interest_zero_rate() -> TestResult {
  var ok = finance_total_interest_cents(100000, 0, 4) == 0;
  if finance_total_interest_cents(100000, 0, 3) != 2 { ok = false; }
  return assert(ok, "zero-rate total interest is the payment-rounding excess (0 when it divides exactly)");
}

fn t22_total_interest_positive() -> TestResult {
  let got = finance_total_interest_cents(100000, 50, 2);
  return assert(got == 7560, "100000 cents at 50 permille over 2 periods pays 7560 cents of interest");
}

fn t23_total_interest_clamped() -> TestResult {
  var ok = finance_total_interest_cents(100000, -50, 2) == 0;
  if finance_total_interest_cents(100000, 50, 0) != 0 { ok = false; }
  return assert(ok, "negative-rate total interest (raw -7436) clamps to 0");
}

fn t24_npv_zero_rate_sum() -> TestResult {
  let flows = fv3(100, -20, 5);
  var ok = finance_npv_cents(0, &flows) == 85;
  let single = fv1(777);
  if finance_npv_cents(0, &single) != 777 { ok = false; }
  return assert(ok, "NPV at rate 0 is exactly the sum of the flows");
}

fn t25_npv_positive_rate() -> TestResult {
  let two = fv2(10000, 10000);
  var ok = finance_npv_cents(50, &two) == 19520;
  let three = fv3(10000, 10000, 10000);
  if finance_npv_cents(50, &three) != 28580 { ok = false; }
  return assert(ok, "NPV at 50 permille discounts 10000+10000 to 19520 (factor 1000 then 952)");
}

fn t26_npv_negative_rate() -> TestResult {
  let flows = fv2(10000, 10000);
  let got = finance_npv_cents(-50, &flows);
  return assert(got == 20520, "NPV at -50 permille inflates 10000+10000 to 20520 (factor 1052)");
}

fn t27_npv_empty_and_zero_flows() -> TestResult {
  let empty = fv0();
  var ok = finance_npv_cents(50, &empty) == 0;
  let zeros = fv3(0, 0, 0);
  if finance_npv_cents(50, &zeros) != 0 { ok = false; }
  return assert(ok, "NPV of an empty series and of all-zero flows is 0");
}

fn t28_rule72_known() -> TestResult {
  var ok = finance_rule_of_72_periods(100) == 720;
  if finance_rule_of_72_periods(90) != 800 { ok = false; }
  if finance_rule_of_72_periods(200) != 360 { ok = false; }
  return assert(ok, "rule of 72: 100 permille -> 720, 90 -> 800, 200 -> 360 periods");
}

fn t29_rule72_ceiling() -> TestResult {
  let got = finance_rule_of_72_periods(70);
  return assert(got == 1029, "72000/70 = 1028.57... rounds up to 1029 periods");
}

fn t30_rule72_nonpositive() -> TestResult {
  var ok = finance_rule_of_72_periods(0) == -1;
  if finance_rule_of_72_periods(-50) != -1 { ok = false; }
  return assert(ok, "rule of 72 returns -1 for a non-positive rate");
}

fn t31_large_values_exact() -> TestResult {
  var ok = finance_simple_interest_cents(1000000000000, 25, 4) == 100000000000;
  if finance_compound_cents(1000000000000, 10, 2) != 1020100000000 { ok = false; }
  let flows = fv3(1000000000000, 1000000000000, 1000000000000);
  if finance_npv_cents(0, &flows) != 3000000000000 { ok = false; }
  if finance_payment_cents(1000000000000, 0, 8) != 125000000000 { ok = false; }
  if finance_rule_of_72_periods(1) != 72000 { ok = false; }
  return assert(ok, "trillion-cent values stay exact through interest, compounding, NPV and payment");
}

fn main() -> Int {
  io.println("=== xiom.finance conformance tests ===");
  var failed: Int = 0;
  let r1 = t01_simple_known();
  if r1.passed { io.println("  [PASS] " + r1.name); } else { io.println("  [FAIL] " + r1.name); failed = failed + 1; }
  let r2 = t02_simple_zero();
  if r2.passed { io.println("  [PASS] " + r2.name); } else { io.println("  [FAIL] " + r2.name); failed = failed + 1; }
  let r3 = t03_simple_negative_rate();
  if r3.passed { io.println("  [PASS] " + r3.name); } else { io.println("  [FAIL] " + r3.name); failed = failed + 1; }
  let r4 = t04_simple_truncation();
  if r4.passed { io.println("  [PASS] " + r4.name); } else { io.println("  [FAIL] " + r4.name); failed = failed + 1; }
  let r5 = t05_compound_known();
  if r5.passed { io.println("  [PASS] " + r5.name); } else { io.println("  [FAIL] " + r5.name); failed = failed + 1; }
  let r6 = t06_compound_single_step_truncation();
  if r6.passed { io.println("  [PASS] " + r6.name); } else { io.println("  [FAIL] " + r6.name); failed = failed + 1; }
  let r7 = t07_compound_truncation_compounds();
  if r7.passed { io.println("  [PASS] " + r7.name); } else { io.println("  [FAIL] " + r7.name); failed = failed + 1; }
  let r8 = t08_compound_zero_and_nonpositive_periods();
  if r8.passed { io.println("  [PASS] " + r8.name); } else { io.println("  [FAIL] " + r8.name); failed = failed + 1; }
  let r9 = t09_compound_negative_rate();
  if r9.passed { io.println("  [PASS] " + r9.name); } else { io.println("  [FAIL] " + r9.name); failed = failed + 1; }
  let r10 = t10_apy_zero();
  if r10.passed { io.println("  [PASS] " + r10.name); } else { io.println("  [FAIL] " + r10.name); failed = failed + 1; }
  let r11 = t11_apy_monthly_known();
  if r11.passed { io.println("  [PASS] " + r11.name); } else { io.println("  [FAIL] " + r11.name); failed = failed + 1; }
  let r12 = t12_apy_exact_cases();
  if r12.passed { io.println("  [PASS] " + r12.name); } else { io.println("  [FAIL] " + r12.name); failed = failed + 1; }
  let r13 = t13_apy_clamps_periods();
  if r13.passed { io.println("  [PASS] " + r13.name); } else { io.println("  [FAIL] " + r13.name); failed = failed + 1; }
  let r14 = t14_apy_total_loss_clamp();
  if r14.passed { io.println("  [PASS] " + r14.name); } else { io.println("  [FAIL] " + r14.name); failed = failed + 1; }
  let r15 = t15_payment_zero_rate_ceil();
  if r15.passed { io.println("  [PASS] " + r15.name); } else { io.println("  [FAIL] " + r15.name); failed = failed + 1; }
  let r16 = t16_payment_known_annuity();
  if r16.passed { io.println("  [PASS] " + r16.name); } else { io.println("  [FAIL] " + r16.name); failed = failed + 1; }
  let r17 = t17_payment_known_twelve_periods();
  if r17.passed { io.println("  [PASS] " + r17.name); } else { io.println("  [FAIL] " + r17.name); failed = failed + 1; }
  let r18 = t18_payment_periods_nonpositive();
  if r18.passed { io.println("  [PASS] " + r18.name); } else { io.println("  [FAIL] " + r18.name); failed = failed + 1; }
  let r19 = t19_payment_negative_rate();
  if r19.passed { io.println("  [PASS] " + r19.name); } else { io.println("  [FAIL] " + r19.name); failed = failed + 1; }
  let r20 = t20_payment_rate_below_minus_1000();
  if r20.passed { io.println("  [PASS] " + r20.name); } else { io.println("  [FAIL] " + r20.name); failed = failed + 1; }
  let r21 = t21_total_interest_zero_rate();
  if r21.passed { io.println("  [PASS] " + r21.name); } else { io.println("  [FAIL] " + r21.name); failed = failed + 1; }
  let r22 = t22_total_interest_positive();
  if r22.passed { io.println("  [PASS] " + r22.name); } else { io.println("  [FAIL] " + r22.name); failed = failed + 1; }
  let r23 = t23_total_interest_clamped();
  if r23.passed { io.println("  [PASS] " + r23.name); } else { io.println("  [FAIL] " + r23.name); failed = failed + 1; }
  let r24 = t24_npv_zero_rate_sum();
  if r24.passed { io.println("  [PASS] " + r24.name); } else { io.println("  [FAIL] " + r24.name); failed = failed + 1; }
  let r25 = t25_npv_positive_rate();
  if r25.passed { io.println("  [PASS] " + r25.name); } else { io.println("  [FAIL] " + r25.name); failed = failed + 1; }
  let r26 = t26_npv_negative_rate();
  if r26.passed { io.println("  [PASS] " + r26.name); } else { io.println("  [FAIL] " + r26.name); failed = failed + 1; }
  let r27 = t27_npv_empty_and_zero_flows();
  if r27.passed { io.println("  [PASS] " + r27.name); } else { io.println("  [FAIL] " + r27.name); failed = failed + 1; }
  let r28 = t28_rule72_known();
  if r28.passed { io.println("  [PASS] " + r28.name); } else { io.println("  [FAIL] " + r28.name); failed = failed + 1; }
  let r29 = t29_rule72_ceiling();
  if r29.passed { io.println("  [PASS] " + r29.name); } else { io.println("  [FAIL] " + r29.name); failed = failed + 1; }
  let r30 = t30_rule72_nonpositive();
  if r30.passed { io.println("  [PASS] " + r30.name); } else { io.println("  [FAIL] " + r30.name); failed = failed + 1; }
  let r31 = t31_large_values_exact();
  if r31.passed { io.println("  [PASS] " + r31.name); } else { io.println("  [FAIL] " + r31.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.finance: all tests passed");
  } else {
    io.println("xiom.finance: tests failed");
  }
  return failed;
}
