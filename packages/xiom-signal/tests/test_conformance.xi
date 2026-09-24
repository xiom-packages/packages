// Port task: xiom.signal conformance tests (27 checks) -- window functions,
// convolution, moving extrema and zero crossings over integer signals.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module signal_tests
use xiom.io; use xiom.test; use xiom.signal;

// Vec[Int] element reads go through typed let bindings: untyped indexed
// reads mis-lower in v0.61.3. All tests build expected series with ivN
// helpers and compare through ints_eq so a mismatch is reported, not
// skipped.

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

fn iv8(a: Int, b: Int, c: Int, d: Int, e: Int, f: Int, g: Int, h: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  v.push(e);
  v.push(f);
  v.push(g);
  v.push(h);
  return v;
}

fn iv9(a: Int, b: Int, c: Int, d: Int, e: Int, f: Int, g: Int, h: Int, i: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  v.push(e);
  v.push(f);
  v.push(g);
  v.push(h);
  v.push(i);
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

fn t01_rect_length_and_values() -> TestResult {
  let one = signal_rect_permille(1);
  let want_one = iv1(1000);
  let four = signal_rect_permille(4);
  let want_four = iv4(1000, 1000, 1000, 1000);
  var ok = one.len() == 1;
  if !ints_eq(&one, &want_one) { ok = false; }
  if four.len() != 4 { ok = false; }
  if !ints_eq(&four, &want_four) { ok = false; }
  return assert(ok, "rect repeats 1000 once per sample");
}

fn t02_rect_empty_for_n_lt_1() -> TestResult {
  let zero = signal_rect_permille(0);
  let neg = signal_rect_permille(-3);
  var ok = zero.len() == 0;
  if neg.len() != 0 { ok = false; }
  return assert(ok, "rect n < 1 is empty");
}

fn t03_hann_values_n5() -> TestResult {
  let got = signal_hann_permille(5);
  let want = iv5(0, 500, 1000, 500, 0);
  var ok = got.len() == 5;
  if !ints_eq(&got, &want) { ok = false; }
  return assert(ok, "hann n=5 pins endpoints 0 and center 1000");
}

fn t04_hann_symmetry_n9() -> TestResult {
  let got = signal_hann_permille(9);
  let want = iv9(0, 146, 500, 854, 1000, 854, 500, 146, 0);
  var ok = got.len() == 9;
  if !ints_eq(&got, &want) { ok = false; }
  return assert(ok, "hann n=9 is symmetric around 1000");
}

fn t05_hann_n1_and_n2() -> TestResult {
  let one = signal_hann_permille(1);
  let want_one = iv1(1000);
  let two = signal_hann_permille(2);
  let want_two = iv2(0, 0);
  var ok = ints_eq(&one, &want_one);
  if !ints_eq(&two, &want_two) { ok = false; }
  return assert(ok, "hann n=1 is [1000] and n=2 is [0, 0]");
}

fn t06_hann_symmetry_property_n17() -> TestResult {
  let got = signal_hann_permille(17);
  let n = got.len();
  var ok = n == 17;
  var i = 0;
  while i < n {
    let a: Int = got[i];
    let b: Int = got[n - 1 - i];
    if a != b { ok = false; }
    i = i + 1;
  }
  let first: Int = got[0];
  let last: Int = got[n - 1];
  let mid: Int = got[n / 2];
  if first != 0 { ok = false; }
  if last != 0 { ok = false; }
  if mid != 1000 { ok = false; }
  return assert(ok, "hann n=17 is point-symmetric with 0 endpoints and center 1000");
}

fn t07_hamming_values_n5() -> TestResult {
  let got = signal_hamming_permille(5);
  let want = iv5(80, 540, 1000, 540, 80);
  var ok = got.len() == 5;
  if !ints_eq(&got, &want) { ok = false; }
  return assert(ok, "hamming n=5 pins endpoints 80 and center 1000");
}

fn t08_hamming_rounding_n9() -> TestResult {
  let got = signal_hamming_permille(9);
  let want = iv9(80, 215, 540, 865, 1000, 865, 540, 215, 80);
  var ok = got.len() == 9;
  if !ints_eq(&got, &want) { ok = false; }
  return assert(ok, "hamming n=9 rounds the shoulders to 215 and 865");
}

fn t09_hamming_n1() -> TestResult {
  let one = signal_hamming_permille(1);
  let want = iv1(1000);
  var ok = ints_eq(&one, &want);
  return assert(ok, "hamming n=1 is [1000]");
}

fn t10_cosine_windows_empty_for_n_lt_1() -> TestResult {
  let h0 = signal_hann_permille(0);
  let hneg = signal_hann_permille(-4);
  let g0 = signal_hamming_permille(0);
  let gneg = signal_hamming_permille(-4);
  var ok = h0.len() == 0;
  if hneg.len() != 0 { ok = false; }
  if g0.len() != 0 { ok = false; }
  if gneg.len() != 0 { ok = false; }
  return assert(ok, "hann and hamming n < 1 are empty");
}

fn t11_apply_permille_basic() -> TestResult {
  let v = iv3(1000, 2000, -3000);
  let w = iv3(500, 250, 1000);
  let got = signal_apply_permille(&v, &w);
  let want = iv3(500, 500, -3000);
  var ok = got.len() == 3;
  if !ints_eq(&got, &want) { ok = false; }
  return assert(ok, "apply scales each value by its permille weight");
}

fn t12_apply_truncates_toward_zero() -> TestResult {
  let v = iv6(1, -1, -1500, 1500, 999, -999);
  let w = iv6(1000, 1000, 1, 1, 1, 1);
  let got = signal_apply_permille(&v, &w);
  let want = iv6(1, -1, -1, 1, 0, 0);
  var ok = got.len() == 6;
  if !ints_eq(&got, &want) { ok = false; }
  return assert(ok, "apply truncates fractional products toward zero");
}

fn t13_apply_stops_at_shorter_length() -> TestResult {
  let long_v = iv5(1, 2, 3, 4, 5);
  let short_w = iv2(1000, 500);
  let got = signal_apply_permille(&long_v, &short_w);
  let want = iv2(1, 1);
  let short_v = iv2(10, 20);
  let long_w = iv5(1000, 1000, 1000, 1000, 1000);
  let got2 = signal_apply_permille(&short_v, &long_w);
  let want2 = iv2(10, 20);
  var ok = got.len() == 2;
  if !ints_eq(&got, &want) { ok = false; }
  if !ints_eq(&got2, &want2) { ok = false; }
  return assert(ok, "apply stops at the shorter input length");
}

fn t14_apply_empty_either_side() -> TestResult {
  let e = iv0();
  let v = iv3(1, 2, 3);
  let w = iv3(1000, 1000, 1000);
  let a = signal_apply_permille(&e, &w);
  let b = signal_apply_permille(&v, &e);
  let c = signal_apply_permille(&e, &e);
  var ok = a.len() == 0;
  if b.len() != 0 { ok = false; }
  if c.len() != 0 { ok = false; }
  return assert(ok, "apply is empty when either input is empty");
}

fn t15_convolve_identity_kernel() -> TestResult {
  let v = iv5(3, 1, 4, 1, 5);
  let k = iv1(1);
  let got = signal_convolve(&v, &k);
  var ok = got.len() == 5;
  if !ints_eq(&got, &v) { ok = false; }
  return assert(ok, "kernel [1] reproduces the signal");
}

fn t16_convolve_impulse_response() -> TestResult {
  let v = iv6(0, 0, 0, 5, 0, 0);
  let k = iv3(1, 2, 3);
  let got = signal_convolve(&v, &k);
  let want = iv6(0, 0, 0, 5, 10, 15);
  var ok = got.len() == 6;
  if !ints_eq(&got, &want) { ok = false; }
  return assert(ok, "an impulse repeats the kernel at the impulse position");
}

fn t17_convolve_moving_average_ramp() -> TestResult {
  let v = iv5(0, 1, 2, 3, 4);
  let k = iv3(1, 1, 1);
  let got = signal_convolve(&v, &k);
  let want = iv5(0, 1, 3, 6, 9);
  var ok = got.len() == 5;
  if !ints_eq(&got, &want) { ok = false; }
  return assert(ok, "kernel [1,1,1] sums the trailing three samples");
}

fn t18_convolve_asymmetric_kernel() -> TestResult {
  let v = iv4(1, 0, 0, 0);
  let k = iv2(1, 2);
  let got = signal_convolve(&v, &k);
  let want = iv4(1, 2, 0, 0);
  let u = iv3(1, 2, 3);
  let k3 = iv3(1, 2, 3);
  let got_u = signal_convolve(&u, &k3);
  let want_u = iv3(1, 4, 10);
  var ok = got.len() == 4;
  if !ints_eq(&got, &want) { ok = false; }
  if !ints_eq(&got_u, &want_u) { ok = false; }
  return assert(ok, "the kernel is applied flipped: later taps read older samples");
}

fn t19_convolve_empty_inputs() -> TestResult {
  let v = iv3(1, 2, 3);
  let e = iv0();
  let k = iv2(1, 2);
  let z = signal_convolve(&v, &e);
  let want_z = iv3(0, 0, 0);
  let a = signal_convolve(&e, &k);
  let b = signal_convolve(&e, &e);
  var ok = z.len() == 3;
  if !ints_eq(&z, &want_z) { ok = false; }
  if a.len() != 0 { ok = false; }
  if b.len() != 0 { ok = false; }
  return assert(ok, "an empty kernel zero-fills and an empty signal stays empty");
}

fn t20_moving_max_identity_and_window2() -> TestResult {
  let v = iv5(3, 1, 4, 1, 5);
  let one = signal_moving_max(&v, 1);
  let w2 = signal_moving_max(&v, 2);
  let want2 = iv5(3, 3, 4, 4, 5);
  var ok = ints_eq(&one, &v);
  if !ints_eq(&w2, &want2) { ok = false; }
  return assert(ok, "moving max window 1 is the identity and window 2 trails the peak");
}

fn t21_moving_max_negative_and_ties() -> TestResult {
  let neg = iv4(-5, -1, -9, -3);
  let got = signal_moving_max(&neg, 2);
  let want = iv4(-5, -1, -1, -3);
  let ties = iv4(2, 5, 5, 1);
  let got_t = signal_moving_max(&ties, 3);
  let want_t = iv4(2, 5, 5, 5);
  var ok = ints_eq(&got, &want);
  if !ints_eq(&got_t, &want_t) { ok = false; }
  return assert(ok, "moving max handles negatives and ties");
}

fn t22_moving_min_known_series() -> TestResult {
  let v = iv5(3, 1, 4, 1, 5);
  let got = signal_moving_min(&v, 2);
  let want = iv5(3, 1, 1, 1, 1);
  let neg = iv4(-5, -1, -9, -3);
  let got_neg = signal_moving_min(&neg, 2);
  let want_neg = iv4(-5, -5, -9, -9);
  let ties = iv4(2, 5, 5, 1);
  let got_t = signal_moving_min(&ties, 3);
  let want_t = iv4(2, 2, 2, 1);
  var ok = ints_eq(&got, &want);
  if !ints_eq(&got_neg, &want_neg) { ok = false; }
  if !ints_eq(&got_t, &want_t) { ok = false; }
  return assert(ok, "moving min trails the trough on known series");
}

fn t23_moving_extrema_partial_window() -> TestResult {
  let v = iv3(3, 1, 4);
  let max5 = signal_moving_max(&v, 5);
  let want_max = iv3(3, 3, 4);
  let min5 = signal_moving_min(&v, 5);
  let want_min = iv3(3, 1, 1);
  let max3 = signal_moving_max(&v, 3);
  var ok = ints_eq(&max5, &want_max);
  if !ints_eq(&min5, &want_min) { ok = false; }
  if !ints_eq(&max3, &want_max) { ok = false; }
  return assert(ok, "a window wider than the input uses every available value");
}

fn t24_moving_extrema_invalid_window_and_empty() -> TestResult {
  let v = iv3(1, 2, 3);
  let e = iv0();
  let mmax0 = signal_moving_max(&v, 0);
  let mmin0 = signal_moving_min(&v, 0);
  let mmaxn = signal_moving_max(&v, -2);
  let mminn = signal_moving_min(&v, -2);
  let emax = signal_moving_max(&e, 3);
  let emin = signal_moving_min(&e, 3);
  var ok = mmax0.len() == 0;
  if mmin0.len() != 0 { ok = false; }
  if mmaxn.len() != 0 { ok = false; }
  if mminn.len() != 0 { ok = false; }
  if emax.len() != 0 { ok = false; }
  if emin.len() != 0 { ok = false; }
  return assert(ok, "window < 1 and empty input yield empty extrema");
}

fn t25_zero_crossings_basic() -> TestResult {
  let v = iv4(1, -1, 2, -3);
  var ok = signal_zero_crossings(&v) == 3;
  let u = iv5(-1, 2, -3, 4, -5);
  if signal_zero_crossings(&u) != 4 { ok = false; }
  return assert(ok, "zero crossings count every sign flip");
}

fn t26_zero_crossings_ignores_zeros() -> TestResult {
  let v = iv8(1, 0, -1, 0, 2, 0, 0, -2);
  var ok = signal_zero_crossings(&v) == 3;
  let u = iv4(1, 0, 0, 1);
  if signal_zero_crossings(&u) != 0 { ok = false; }
  let lead = iv2(0, -1);
  if signal_zero_crossings(&lead) != 0 { ok = false; }
  let trail = iv2(-1, 0);
  if signal_zero_crossings(&trail) != 0 { ok = false; }
  return assert(ok, "zeros never create or absorb a crossing");
}

fn t27_zero_crossings_constant_and_empty() -> TestResult {
  let pos = iv3(5, 5, 5);
  var ok = signal_zero_crossings(&pos) == 0;
  let neg = iv3(-2, -2, -2);
  if signal_zero_crossings(&neg) != 0 { ok = false; }
  let zero = iv3(0, 0, 0);
  if signal_zero_crossings(&zero) != 0 { ok = false; }
  let e = iv0();
  if signal_zero_crossings(&e) != 0 { ok = false; }
  let one = iv1(7);
  if signal_zero_crossings(&one) != 0 { ok = false; }
  let neg_one = iv1(-7);
  if signal_zero_crossings(&neg_one) != 0 { ok = false; }
  return assert(ok, "constant, all-zero, single and empty signals have no crossings");
}

fn main() -> Int {
  io.println("=== xiom.signal conformance tests ===");
  var failed: Int = 0;
  let r1 = t01_rect_length_and_values();
  if r1.passed { io.println("  [PASS] " + r1.name); } else { io.println("  [FAIL] " + r1.name); failed = failed + 1; }
  let r2 = t02_rect_empty_for_n_lt_1();
  if r2.passed { io.println("  [PASS] " + r2.name); } else { io.println("  [FAIL] " + r2.name); failed = failed + 1; }
  let r3 = t03_hann_values_n5();
  if r3.passed { io.println("  [PASS] " + r3.name); } else { io.println("  [FAIL] " + r3.name); failed = failed + 1; }
  let r4 = t04_hann_symmetry_n9();
  if r4.passed { io.println("  [PASS] " + r4.name); } else { io.println("  [FAIL] " + r4.name); failed = failed + 1; }
  let r5 = t05_hann_n1_and_n2();
  if r5.passed { io.println("  [PASS] " + r5.name); } else { io.println("  [FAIL] " + r5.name); failed = failed + 1; }
  let r6 = t06_hann_symmetry_property_n17();
  if r6.passed { io.println("  [PASS] " + r6.name); } else { io.println("  [FAIL] " + r6.name); failed = failed + 1; }
  let r7 = t07_hamming_values_n5();
  if r7.passed { io.println("  [PASS] " + r7.name); } else { io.println("  [FAIL] " + r7.name); failed = failed + 1; }
  let r8 = t08_hamming_rounding_n9();
  if r8.passed { io.println("  [PASS] " + r8.name); } else { io.println("  [FAIL] " + r8.name); failed = failed + 1; }
  let r9 = t09_hamming_n1();
  if r9.passed { io.println("  [PASS] " + r9.name); } else { io.println("  [FAIL] " + r9.name); failed = failed + 1; }
  let r10 = t10_cosine_windows_empty_for_n_lt_1();
  if r10.passed { io.println("  [PASS] " + r10.name); } else { io.println("  [FAIL] " + r10.name); failed = failed + 1; }
  let r11 = t11_apply_permille_basic();
  if r11.passed { io.println("  [PASS] " + r11.name); } else { io.println("  [FAIL] " + r11.name); failed = failed + 1; }
  let r12 = t12_apply_truncates_toward_zero();
  if r12.passed { io.println("  [PASS] " + r12.name); } else { io.println("  [FAIL] " + r12.name); failed = failed + 1; }
  let r13 = t13_apply_stops_at_shorter_length();
  if r13.passed { io.println("  [PASS] " + r13.name); } else { io.println("  [FAIL] " + r13.name); failed = failed + 1; }
  let r14 = t14_apply_empty_either_side();
  if r14.passed { io.println("  [PASS] " + r14.name); } else { io.println("  [FAIL] " + r14.name); failed = failed + 1; }
  let r15 = t15_convolve_identity_kernel();
  if r15.passed { io.println("  [PASS] " + r15.name); } else { io.println("  [FAIL] " + r15.name); failed = failed + 1; }
  let r16 = t16_convolve_impulse_response();
  if r16.passed { io.println("  [PASS] " + r16.name); } else { io.println("  [FAIL] " + r16.name); failed = failed + 1; }
  let r17 = t17_convolve_moving_average_ramp();
  if r17.passed { io.println("  [PASS] " + r17.name); } else { io.println("  [FAIL] " + r17.name); failed = failed + 1; }
  let r18 = t18_convolve_asymmetric_kernel();
  if r18.passed { io.println("  [PASS] " + r18.name); } else { io.println("  [FAIL] " + r18.name); failed = failed + 1; }
  let r19 = t19_convolve_empty_inputs();
  if r19.passed { io.println("  [PASS] " + r19.name); } else { io.println("  [FAIL] " + r19.name); failed = failed + 1; }
  let r20 = t20_moving_max_identity_and_window2();
  if r20.passed { io.println("  [PASS] " + r20.name); } else { io.println("  [FAIL] " + r20.name); failed = failed + 1; }
  let r21 = t21_moving_max_negative_and_ties();
  if r21.passed { io.println("  [PASS] " + r21.name); } else { io.println("  [FAIL] " + r21.name); failed = failed + 1; }
  let r22 = t22_moving_min_known_series();
  if r22.passed { io.println("  [PASS] " + r22.name); } else { io.println("  [FAIL] " + r22.name); failed = failed + 1; }
  let r23 = t23_moving_extrema_partial_window();
  if r23.passed { io.println("  [PASS] " + r23.name); } else { io.println("  [FAIL] " + r23.name); failed = failed + 1; }
  let r24 = t24_moving_extrema_invalid_window_and_empty();
  if r24.passed { io.println("  [PASS] " + r24.name); } else { io.println("  [FAIL] " + r24.name); failed = failed + 1; }
  let r25 = t25_zero_crossings_basic();
  if r25.passed { io.println("  [PASS] " + r25.name); } else { io.println("  [FAIL] " + r25.name); failed = failed + 1; }
  let r26 = t26_zero_crossings_ignores_zeros();
  if r26.passed { io.println("  [PASS] " + r26.name); } else { io.println("  [FAIL] " + r26.name); failed = failed + 1; }
  let r27 = t27_zero_crossings_constant_and_empty();
  if r27.passed { io.println("  [PASS] " + r27.name); } else { io.println("  [FAIL] " + r27.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.signal: all tests passed");
  } else {
    io.println("xiom.signal: tests failed");
  }
  return failed;
}
