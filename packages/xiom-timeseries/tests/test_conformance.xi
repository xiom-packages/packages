// Port task: xiom.timeseries conformance tests (29 checks) -- moving
// averages, EMA, deltas and range statistics over integer series.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module timeseries_tests
use xiom.io; use xiom.test; use xiom.timeseries;

// Vec[Int] element reads go through typed let bindings: untyped indexed reads
// mis-lower in v0.61.3. All tests build expected series with ivN helpers and
// compare through ints_eq so a mismatch is reported, not skipped.

fn iv0() -> Vec[Int] {
  var v = Vec[Int].new();
  return v;
}

fn iv1(a: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  return v;
}

fn iv2(a: Int, b: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  return v;
}

fn iv3(a: Int, b: Int, c: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  return v;
}

fn iv4(a: Int, b: Int, c: Int, d: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  return v;
}

fn iv5(a: Int, b: Int, c: Int, d: Int, e: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  v.push(e);
  return v;
}

fn iv6(a: Int, b: Int, c: Int, d: Int, e: Int, f: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  v.push(e);
  v.push(f);
  return v;
}

fn ints_eq(got: &Vec[Int], want: &Vec[Int]) -> Bool {
  if got.len() != want.len() {
    return false;
  }
  var i = 0;
  while i < got.len() {
    let g: Int = got[i];
    let w: Int = want[i];
    if g != w {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn t01_ma_window1_identity() -> TestResult {
  let v = iv5(3, 1, 4, 1, 5);
  let got = ts_moving_average(&v, 1);
  let want = iv5(3, 1, 4, 1, 5);
  var ok = got.len() == 5;
  if !ints_eq(&got, &want) { ok = false; }
  return assert(ok, "moving average window 1 is the identity");
}

fn t02_ma_window2_partial_prefix() -> TestResult {
  let v = iv5(1, 2, 6, 0, 4);
  let got = ts_moving_average(&v, 2);
  let want = iv5(1, 1, 4, 3, 2);
  var ok = got.len() == v.len();
  if !ints_eq(&got, &want) { ok = false; }
  return assert(ok, "moving average window 2 averages the partial prefix");
}

fn t03_ma_window3_partial_prefix() -> TestResult {
  let v = iv5(1, 2, 6, 0, 4);
  let got = ts_moving_average(&v, 3);
  let want = iv5(1, 1, 3, 2, 3);
  var ok = got.len() == v.len();
  if !ints_eq(&got, &want) { ok = false; }
  return assert(ok, "moving average window 3 averages the partial prefix");
}

fn t04_ma_floors_negative_sums() -> TestResult {
  let a = iv2(-1, -2);
  let got_a = ts_moving_average(&a, 2);
  let want_a = iv2(-1, -2);
  let b = iv3(-3, -4, -4);
  let got_b = ts_moving_average(&b, 2);
  let want_b = iv3(-3, -4, -4);
  var ok = ints_eq(&got_a, &want_a);
  if !ints_eq(&got_b, &want_b) { ok = false; }
  return assert(ok, "moving average floors negative window sums");
}

fn t05_ma_window_zero_is_empty() -> TestResult {
  let v = iv3(1, 2, 3);
  let got = ts_moving_average(&v, 0);
  return assert(got.len() == 0, "moving average window 0 returns an empty vector");
}

fn t06_ma_window_negative_is_empty() -> TestResult {
  let v = iv3(1, 2, 3);
  let got = ts_moving_average(&v, -4);
  return assert(got.len() == 0, "moving average negative window returns an empty vector");
}

fn t07_ma_empty_input() -> TestResult {
  let e = iv0();
  let got = ts_moving_average(&e, 3);
  return assert(got.len() == 0, "moving average of an empty series is empty");
}

fn t08_ema_alpha1000_identity() -> TestResult {
  let v = iv5(3, 1, 4, 1, 5);
  let got = ts_ema(&v, 1000);
  let want = iv5(3, 1, 4, 1, 5);
  var ok = got.len() == v.len();
  if !ints_eq(&got, &want) { ok = false; }
  return assert(ok, "ema alpha 1000 reproduces the input");
}

fn t09_ema_alpha0_constant() -> TestResult {
  let v = iv5(7, 9, 2, 5, 1);
  let got = ts_ema(&v, 0);
  let want = iv5(7, 7, 7, 7, 7);
  var ok = got.len() == v.len();
  if !ints_eq(&got, &want) { ok = false; }
  return assert(ok, "ema alpha 0 holds the first value constant");
}

fn t10_ema_smoothing_known() -> TestResult {
  let v = iv3(10, 20, 30);
  let got = ts_ema(&v, 500);
  let want = iv3(10, 15, 22);
  let u = iv3(100, 200, 300);
  let got_u = ts_ema(&u, 250);
  let want_u = iv3(100, 125, 168);
  var ok = ints_eq(&got, &want);
  if !ints_eq(&got_u, &want_u) { ok = false; }
  return assert(ok, "ema smoothing matches known fixed-point values");
}

fn t11_ema_clamps_alpha() -> TestResult {
  let v = iv3(1, 2, 3);
  let high = ts_ema(&v, 5000);
  let want_high = iv3(1, 2, 3);
  let u = iv4(5, 9, 9, 9);
  let low = ts_ema(&u, -7);
  let want_low = iv4(5, 5, 5, 5);
  var ok = ints_eq(&high, &want_high);
  if !ints_eq(&low, &want_low) { ok = false; }
  return assert(ok, "ema clamps alpha to the 0..1000 range");
}

fn t12_ema_floors_negative_terms() -> TestResult {
  let v = iv2(-5, -10);
  let got = ts_ema(&v, 500);
  let want = iv2(-5, -8);
  let u = iv3(3, -3, -9);
  let got_u = ts_ema(&u, 250);
  let want_u = iv3(3, 1, -2);
  var ok = ints_eq(&got, &want);
  if !ints_eq(&got_u, &want_u) { ok = false; }
  return assert(ok, "ema floors negative fixed-point terms");
}

fn t13_delta_values() -> TestResult {
  let v = iv5(3, 1, 4, 1, 5);
  let got = ts_delta(&v);
  let want = iv5(0, -2, 3, -3, 4);
  var ok = got.len() == v.len();
  if !ints_eq(&got, &want) { ok = false; }
  return assert(ok, "delta is 0 then consecutive differences");
}

fn t14_delta_empty_and_single() -> TestResult {
  let e = iv0();
  let de = ts_delta(&e);
  let s = iv1(42);
  let ds = ts_delta(&s);
  let want_s = iv1(0);
  var ok = de.len() == 0;
  if !ints_eq(&ds, &want_s) { ok = false; }
  return assert(ok, "delta of empty is empty and of a single value is 0");
}

fn t15_sum_values() -> TestResult {
  let v = iv5(1, 2, 3, 4, 5);
  let s = ts_sum(&v);
  let u = iv2(-5, 2);
  let su = ts_sum(&u);
  var ok = s == 15;
  if su != -3 { ok = false; }
  return assert(ok, "sum adds every element including negatives");
}

fn t16_sum_mean_empty() -> TestResult {
  let e = iv0();
  var ok = ts_sum(&e) == 0;
  if ts_mean(&e) != 0 { ok = false; }
  return assert(ok, "sum and mean of an empty series are 0");
}

fn t17_mean_floors() -> TestResult {
  let v = iv3(1, 2, 4);
  var ok = ts_mean(&v) == 2;
  let u = iv2(-1, -2);
  if ts_mean(&u) != -2 { ok = false; }
  let w = iv1(9);
  if ts_mean(&w) != 9 { ok = false; }
  let z = iv5(7, 7, 7, 7, 8);
  if ts_mean(&z) != 7 { ok = false; }
  return assert(ok, "mean is floored, including negative sums");
}

fn t18_min_max_values() -> TestResult {
  let v = iv5(-3, 5, -3, 2, 5);
  var ok = ts_min(&v) == -3;
  if ts_max(&v) != 5 { ok = false; }
  let flat = iv4(7, 7, 7, 7);
  if ts_min(&flat) != 7 { ok = false; }
  if ts_max(&flat) != 7 { ok = false; }
  return assert(ok, "min and max handle ties, negatives and constants");
}

fn t19_min_max_empty() -> TestResult {
  let e = iv0();
  var ok = ts_min(&e) == 0;
  if ts_max(&e) != 0 { ok = false; }
  return assert(ok, "min and max of an empty series are 0");
}

fn t20_argmin_argmax_ties() -> TestResult {
  let v = iv5(4, 2, 9, 2, 9);
  var ok = ts_argmin(&v) == 1;
  if ts_argmax(&v) != 2 { ok = false; }
  let u = iv4(-5, -1, -5, -1);
  if ts_argmin(&u) != 0 { ok = false; }
  if ts_argmax(&u) != 1 { ok = false; }
  let s = iv1(3);
  if ts_argmin(&s) != 0 { ok = false; }
  if ts_argmax(&s) != 0 { ok = false; }
  return assert(ok, "argmin and argmax return the first extremum index");
}

fn t21_argmin_argmax_empty() -> TestResult {
  let e = iv0();
  var ok = ts_argmin(&e) == -1;
  if ts_argmax(&e) != -1 { ok = false; }
  return assert(ok, "argmin and argmax of an empty series are -1");
}

fn t22_bounds() -> TestResult {
  let v = iv3(-3, 5, 2);
  let(lo, hi) = ts_bounds(&v);
  var ok = lo == -3;
  if hi != 5 { ok = false; }
  let e = iv0();
  let(elo, ehi) = ts_bounds(&e);
  if elo != 0 { ok = false; }
  if ehi != 0 { ok = false; }
  let s = iv1(9);
  let(slo, shi) = ts_bounds(&s);
  if slo != 9 { ok = false; }
  if shi != 9 { ok = false; }
  return assert(ok, "bounds returns min/max and (0, 0) for empty");
}

fn t23_normalize_range() -> TestResult {
  let v = iv3(0, 50, 100);
  let got = ts_normalize_permille(&v);
  let want = iv3(0, 500, 1000);
  let u = iv3(0, 1, 3);
  let got_u = ts_normalize_permille(&u);
  let want_u = iv3(0, 333, 1000);
  let w = iv3(0, 1, 2);
  let got_w = ts_normalize_permille(&w);
  let want_w = iv3(0, 500, 1000);
  var ok = ints_eq(&got, &want);
  if !ints_eq(&got_u, &want_u) { ok = false; }
  if !ints_eq(&got_w, &want_w) { ok = false; }
  return assert(ok, "normalize maps the range endpoints to 0 and 1000");
}

fn t24_normalize_all_equal() -> TestResult {
  let v = iv3(7, 7, 7);
  let got = ts_normalize_permille(&v);
  let want = iv3(0, 0, 0);
  let u = iv4(-2, -2, -2, -2);
  let got_u = ts_normalize_permille(&u);
  let want_u = iv4(0, 0, 0, 0);
  var ok = ints_eq(&got, &want);
  if !ints_eq(&got_u, &want_u) { ok = false; }
  return assert(ok, "normalize maps a constant series to all zeros");
}

fn t25_normalize_negative_range_and_empty() -> TestResult {
  let v = iv3(-10, 0, 10);
  let got = ts_normalize_permille(&v);
  let want = iv3(0, 500, 1000);
  let u = iv3(-2, -10, -6);
  let got_u = ts_normalize_permille(&u);
  let want_u = iv3(1000, 0, 500);
  let e = iv0();
  let got_e = ts_normalize_permille(&e);
  var ok = ints_eq(&got, &want);
  if !ints_eq(&got_u, &want_u) { ok = false; }
  if got_e.len() != 0 { ok = false; }
  return assert(ok, "normalize handles negative ranges and empty series");
}

fn t26_threshold_start_at_or_above() -> TestResult {
  let v = iv3(5, 6, 7);
  var ok = ts_threshold_crossings(&v, 5) == 1;
  let u = iv1(5);
  if ts_threshold_crossings(&u, 5) != 1 { ok = false; }
  let w = iv1(4);
  if ts_threshold_crossings(&w, 5) != 0 { ok = false; }
  let e = iv0();
  if ts_threshold_crossings(&e, 5) != 0 { ok = false; }
  return assert(ok, "a first element at or above the threshold counts once");
}

fn t27_threshold_no_crossings() -> TestResult {
  let flat = iv5(0, 0, 0, 0, 0);
  var ok = ts_threshold_crossings(&flat, 1) == 0;
  let high = iv4(9, 9, 9, 9);
  if ts_threshold_crossings(&high, 5) != 1 { ok = false; }
  let falling = iv3(4, 3, 2);
  if ts_threshold_crossings(&falling, 5) != 0 { ok = false; }
  return assert(ok, "no crossing while the series stays on one side");
}

fn t28_threshold_multiple_crossings() -> TestResult {
  let v = iv6(5, 1, 2, 7, 3, 9);
  let got = ts_threshold_crossings(&v, 5);
  let u = iv5(0, 5, 0, 5, 0);
  let got_u = ts_threshold_crossings(&u, 5);
  let w = iv3(4, 5, 4);
  let got_w = ts_threshold_crossings(&w, 5);
  var ok = got == 3;
  if got_u != 2 { ok = false; }
  if got_w != 1 { ok = false; }
  return assert(ok, "threshold crossings count each downward-to-upward move");
}

fn t29_large_values() -> TestResult {
  let v = iv3(1000000000, 2000000000, 3000000000);
  var ok = ts_sum(&v) == 6000000000;
  if ts_mean(&v) != 2000000000 { ok = false; }
  if ts_min(&v) != 1000000000 { ok = false; }
  if ts_max(&v) != 3000000000 { ok = false; }
  let d = ts_delta(&v);
  let want_d = iv3(0, 1000000000, 1000000000);
  if !ints_eq(&d, &want_d) { ok = false; }
  let ma = ts_moving_average(&v, 2);
  let want_ma = iv3(1000000000, 1500000000, 2500000000);
  if !ints_eq(&ma, &want_ma) { ok = false; }
  let nrm = ts_normalize_permille(&v);
  let want_nrm = iv3(0, 500, 1000);
  if !ints_eq(&nrm, &want_nrm) { ok = false; }
  let neg = iv3(-1000000000, 0, 1000000000);
  let(nlo, nhi) = ts_bounds(&neg);
  if nlo != -1000000000 { ok = false; }
  if nhi != 1000000000 { ok = false; }
  return assert(ok, "billion-scale values stay exact");
}

fn main() -> Int {
  io.println("=== xiom.timeseries conformance tests ===");
  var failed: Int = 0;
  let r1 = t01_ma_window1_identity();
  if r1.passed { io.println("  [PASS] " + r1.name); } else { io.println("  [FAIL] " + r1.name); failed = failed + 1; }
  let r2 = t02_ma_window2_partial_prefix();
  if r2.passed { io.println("  [PASS] " + r2.name); } else { io.println("  [FAIL] " + r2.name); failed = failed + 1; }
  let r3 = t03_ma_window3_partial_prefix();
  if r3.passed { io.println("  [PASS] " + r3.name); } else { io.println("  [FAIL] " + r3.name); failed = failed + 1; }
  let r4 = t04_ma_floors_negative_sums();
  if r4.passed { io.println("  [PASS] " + r4.name); } else { io.println("  [FAIL] " + r4.name); failed = failed + 1; }
  let r5 = t05_ma_window_zero_is_empty();
  if r5.passed { io.println("  [PASS] " + r5.name); } else { io.println("  [FAIL] " + r5.name); failed = failed + 1; }
  let r6 = t06_ma_window_negative_is_empty();
  if r6.passed { io.println("  [PASS] " + r6.name); } else { io.println("  [FAIL] " + r6.name); failed = failed + 1; }
  let r7 = t07_ma_empty_input();
  if r7.passed { io.println("  [PASS] " + r7.name); } else { io.println("  [FAIL] " + r7.name); failed = failed + 1; }
  let r8 = t08_ema_alpha1000_identity();
  if r8.passed { io.println("  [PASS] " + r8.name); } else { io.println("  [FAIL] " + r8.name); failed = failed + 1; }
  let r9 = t09_ema_alpha0_constant();
  if r9.passed { io.println("  [PASS] " + r9.name); } else { io.println("  [FAIL] " + r9.name); failed = failed + 1; }
  let r10 = t10_ema_smoothing_known();
  if r10.passed { io.println("  [PASS] " + r10.name); } else { io.println("  [FAIL] " + r10.name); failed = failed + 1; }
  let r11 = t11_ema_clamps_alpha();
  if r11.passed { io.println("  [PASS] " + r11.name); } else { io.println("  [FAIL] " + r11.name); failed = failed + 1; }
  let r12 = t12_ema_floors_negative_terms();
  if r12.passed { io.println("  [PASS] " + r12.name); } else { io.println("  [FAIL] " + r12.name); failed = failed + 1; }
  let r13 = t13_delta_values();
  if r13.passed { io.println("  [PASS] " + r13.name); } else { io.println("  [FAIL] " + r13.name); failed = failed + 1; }
  let r14 = t14_delta_empty_and_single();
  if r14.passed { io.println("  [PASS] " + r14.name); } else { io.println("  [FAIL] " + r14.name); failed = failed + 1; }
  let r15 = t15_sum_values();
  if r15.passed { io.println("  [PASS] " + r15.name); } else { io.println("  [FAIL] " + r15.name); failed = failed + 1; }
  let r16 = t16_sum_mean_empty();
  if r16.passed { io.println("  [PASS] " + r16.name); } else { io.println("  [FAIL] " + r16.name); failed = failed + 1; }
  let r17 = t17_mean_floors();
  if r17.passed { io.println("  [PASS] " + r17.name); } else { io.println("  [FAIL] " + r17.name); failed = failed + 1; }
  let r18 = t18_min_max_values();
  if r18.passed { io.println("  [PASS] " + r18.name); } else { io.println("  [FAIL] " + r18.name); failed = failed + 1; }
  let r19 = t19_min_max_empty();
  if r19.passed { io.println("  [PASS] " + r19.name); } else { io.println("  [FAIL] " + r19.name); failed = failed + 1; }
  let r20 = t20_argmin_argmax_ties();
  if r20.passed { io.println("  [PASS] " + r20.name); } else { io.println("  [FAIL] " + r20.name); failed = failed + 1; }
  let r21 = t21_argmin_argmax_empty();
  if r21.passed { io.println("  [PASS] " + r21.name); } else { io.println("  [FAIL] " + r21.name); failed = failed + 1; }
  let r22 = t22_bounds();
  if r22.passed { io.println("  [PASS] " + r22.name); } else { io.println("  [FAIL] " + r22.name); failed = failed + 1; }
  let r23 = t23_normalize_range();
  if r23.passed { io.println("  [PASS] " + r23.name); } else { io.println("  [FAIL] " + r23.name); failed = failed + 1; }
  let r24 = t24_normalize_all_equal();
  if r24.passed { io.println("  [PASS] " + r24.name); } else { io.println("  [FAIL] " + r24.name); failed = failed + 1; }
  let r25 = t25_normalize_negative_range_and_empty();
  if r25.passed { io.println("  [PASS] " + r25.name); } else { io.println("  [FAIL] " + r25.name); failed = failed + 1; }
  let r26 = t26_threshold_start_at_or_above();
  if r26.passed { io.println("  [PASS] " + r26.name); } else { io.println("  [FAIL] " + r26.name); failed = failed + 1; }
  let r27 = t27_threshold_no_crossings();
  if r27.passed { io.println("  [PASS] " + r27.name); } else { io.println("  [FAIL] " + r27.name); failed = failed + 1; }
  let r28 = t28_threshold_multiple_crossings();
  if r28.passed { io.println("  [PASS] " + r28.name); } else { io.println("  [FAIL] " + r28.name); failed = failed + 1; }
  let r29 = t29_large_values();
  if r29.passed { io.println("  [PASS] " + r29.name); } else { io.println("  [FAIL] " + r29.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.timeseries: all tests passed");
  } else {
    io.println("xiom.timeseries: tests failed");
  }
  return failed;
}
