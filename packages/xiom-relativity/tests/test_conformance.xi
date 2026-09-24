// XIOM -- xiom.relativity conformance tests (20 checks)
// Port task: prove the pure-XIOM xiom.relativity module against its SPEC.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// The API is numeric-only (Int and Float64), so no Str comparison and no
// str_compare are needed anywhere in this suite; the only Str values are the
// assert() test names.
//
// `approx(a, b)` is the absolute check |a - b| < 1e-6 (libm fabs via
// xiom.math.abs_float). It is applied directly to O(1)-sized quantities;
// c^2-scale results are divided by a c^2 reference computed inside the test
// first, or compared through ratios, so the same absolute tolerance stays
// meaningful without weakening any assertion (SPEC.md section 6).
//
// Expected values are pinned from the closed-form formulas of SPEC.md and
// recomputed in IEEE-754 double precision (see section 5 for the tolerances).

module relativity_tests
use xiom.io; use xiom.test; use xiom.relativity;
use xiom.math;

// Absolute approximate equality: |a - b| < 1e-6.
fn approx(a: Float64, b: Float64) -> Bool {
  return xiom.math.abs_float(a - b) < 0.000001;
}

// The tests' own literal for the speed of light in m/s (the module documents
// the same exact SI value).
fn c_m_per_s() -> Float64 {
  return 299792458.0;
}

fn t01_lorentz_beta0() -> TestResult {
  var ok = approx(rel_lorentz_permille(0), 1.0);
  if !approx(rel_lorentz_permille(1), 1.0) { ok = false; }
  if !approx(rel_lorentz_permille(-1), 1.0) { ok = false; }
  return assert(ok, "lorentz(0) is 1 and +-1 permille stays within 1e-6");
}

fn t02_lorentz_600_exact() -> TestResult {
  var ok = approx(rel_lorentz_permille(600), 1.25);
  if !approx(rel_lorentz_permille(600), 5.0 / 4.0) { ok = false; }
  return assert(ok, "lorentz(600) is 1.25 = 5/4");
}

fn t03_lorentz_800() -> TestResult {
  var ok = approx(rel_lorentz_permille(800), 1.6666667);
  if !approx(rel_lorentz_permille(800), 5.0 / 3.0) { ok = false; }
  return assert(ok, "lorentz(800) is 5/3 = 1.6666667 (pinned approx)");
}

fn t04_lorentz_999_large() -> TestResult {
  var ok = approx(rel_lorentz_permille(999), 22.3662720421294);
  if !(rel_lorentz_permille(999) > 22.0) { ok = false; }
  if !(rel_lorentz_permille(999) < 23.0) { ok = false; }
  return assert(ok, "lorentz(999) is 22.3662720421294 (large, pinned approx)");
}

fn t05_lorentz_symmetry() -> TestResult {
  var ok = approx(rel_lorentz_permille(-999), rel_lorentz_permille(999));
  if !approx(rel_lorentz_permille(-600), 1.25) { ok = false; }
  if !approx(rel_lorentz_permille(-800), 1.6666667) { ok = false; }
  return assert(ok, "lorentz is even in beta: gamma(-b) == gamma(+b)");
}

fn t06_lorentz_invalid() -> TestResult {
  var ok = approx(rel_lorentz_permille(1000), 0.0);
  if !approx(rel_lorentz_permille(-1000), 0.0) { ok = false; }
  if !approx(rel_lorentz_permille(5000), 0.0) { ok = false; }
  if !approx(rel_lorentz_permille(-5000), 0.0) { ok = false; }
  if !approx(rel_lorentz_permille(1000000), 0.0) { ok = false; }
  if !(rel_lorentz_permille(999) > 1.0) { ok = false; }
  if !(rel_lorentz_permille(-999) > 1.0) { ok = false; }
  return assert(ok, "lorentz invalid beta (|beta| >= 1000 permille) is 0.0");
}

fn t07_time_dilation() -> TestResult {
  var ok = approx(rel_time_dilation_s(1.0, 600), 1.25);
  if !approx(rel_time_dilation_s(2.5, 0), 2.5) { ok = false; }
  if !approx(rel_time_dilation_s(10.0, 800), 50.0 / 3.0) { ok = false; }
  if !approx(rel_time_dilation_s(0.0, 600), 0.0) { ok = false; }
  return assert(ok, "dilation: 1 s at 0.6c is 1.25 s; b=0 is identity");
}

fn t08_length_contraction() -> TestResult {
  var ok = approx(rel_length_contraction_m(1.0, 600), 0.8);
  if !approx(rel_length_contraction_m(2.5, 0), 2.5) { ok = false; }
  if !approx(rel_length_contraction_m(3.0, 600) * rel_lorentz_permille(600), 3.0) {
    ok = false;
  }
  return assert(ok, "contraction: 1 m at 0.6c is 0.8 m; L*gamma = L0");
}

fn t09_dilation_contraction_invalid() -> TestResult {
  var ok = approx(rel_time_dilation_s(1.0, 1000), 0.0);
  if !approx(rel_time_dilation_s(1.0, -1000), 0.0) { ok = false; }
  if !approx(rel_time_dilation_s(1.0, 5000), 0.0) { ok = false; }
  if !approx(rel_length_contraction_m(1.0, 1000), 0.0) { ok = false; }
  if !approx(rel_length_contraction_m(1.0, -1000), 0.0) { ok = false; }
  if !approx(rel_length_contraction_m(2.0, -5000), 0.0) { ok = false; }
  return assert(ok, "dilation/contraction invalid beta yields 0.0");
}

fn t10_velocity_add_basic() -> TestResult {
  var ok = rel_velocity_add_permille(500, 500) == 800;
  if rel_velocity_add_permille(600, 600) != 882 { ok = false; }
  if rel_velocity_add_permille(0, 600) != 600 { ok = false; }
  return assert(ok, "velocity add: 500+500=800, 600+600=882, 0+600=600");
}

fn t11_velocity_add_zero() -> TestResult {
  var ok = rel_velocity_add_permille(0, 0) == 0;
  if rel_velocity_add_permille(500, 0) != 500 { ok = false; }
  if rel_velocity_add_permille(0, -500) != -500 { ok = false; }
  if rel_velocity_add_permille(999, 0) != 999 { ok = false; }
  if rel_velocity_add_permille(0, -999) != -999 { ok = false; }
  return assert(ok, "velocity add: zero is an identity, 0+0=0");
}

fn t12_velocity_add_negatives() -> TestResult {
  var ok = rel_velocity_add_permille(-500, -500) == -800;
  if rel_velocity_add_permille(-500, 500) != 0 { ok = false; }
  if rel_velocity_add_permille(500, -500) != 0 { ok = false; }
  if rel_velocity_add_permille(-800, 500) != -500 { ok = false; }
  return assert(ok, "velocity add: negatives mirror, -500+500=0");
}

fn t13_velocity_add_truncation() -> TestResult {
  var ok = rel_velocity_add_permille(300, 700) == 826;
  if rel_velocity_add_permille(700, 300) != 826 { ok = false; }
  if rel_velocity_add_permille(999, 999) != 1000 { ok = false; }
  return assert(ok, "velocity add truncates toward zero; 999+999 hits the 1000 edge");
}

fn t14_beta_clamp() -> TestResult {
  var ok = rel_beta_from_bits(0) == 0;
  if rel_beta_from_bits(500) != 500 { ok = false; }
  if rel_beta_from_bits(999) != 999 { ok = false; }
  if rel_beta_from_bits(-999) != -999 { ok = false; }
  if rel_beta_from_bits(1000) != 999 { ok = false; }
  if rel_beta_from_bits(-1000) != -999 { ok = false; }
  if rel_beta_from_bits(12345) != 999 { ok = false; }
  if rel_beta_from_bits(-12345) != -999 { ok = false; }
  return assert(ok, "beta clamp: in-range passes, out-of-range clamps to +-999");
}

fn t15_velocity_add_clamped() -> TestResult {
  var ok = rel_velocity_add_permille(5000, 0) == 999;
  if rel_velocity_add_permille(-5000, 0) != -999 { ok = false; }
  if rel_velocity_add_permille(5000, 5000) != 1000 { ok = false; }
  if rel_velocity_add_permille(5000, -5000) != 0 { ok = false; }
  if rel_velocity_add_permille(1000, 0) != 999 { ok = false; }
  return assert(ok, "velocity add clamps both inputs to [-999, 999]");
}

fn t16_energy_rest() -> TestResult {
  let c: Float64 = c_m_per_s();
  let c2: Float64 = c * c;
  var ok = approx(rel_energy_j(1.0), c2);
  if !approx(rel_energy_j(1.0) / 8.987551787368176e16, 1.0) { ok = false; }
  if !approx(rel_energy_j(2.0) / rel_energy_j(1.0), 2.0) { ok = false; }
  if !approx(rel_energy_j(0.0), 0.0) { ok = false; }
  return assert(ok, "energy: 1 kg is c^2 = 8.987551787368176e16 J, linear in mass");
}

fn t17_kinetic_zero_and_invalid() -> TestResult {
  var ok = approx(rel_kinetic_energy_j(1.0, 0), 0.0);
  if !approx(rel_kinetic_energy_j(0.0, 600), 0.0) { ok = false; }
  if !approx(rel_kinetic_energy_j(1.0, 1000), 0.0) { ok = false; }
  if !approx(rel_kinetic_energy_j(1.0, -1000), 0.0) { ok = false; }
  if !approx(rel_kinetic_energy_j(1.0, -5000), 0.0) { ok = false; }
  return assert(ok, "kinetic: beta 0 and invalid beta give 0.0");
}

fn t18_kinetic_0_6c() -> TestResult {
  let c: Float64 = c_m_per_s();
  let c2: Float64 = c * c;
  var ok = approx(rel_kinetic_energy_j(1.0, 600) / c2, 0.25);
  if !approx(rel_kinetic_energy_j(1.0, 600), 0.25 * c2) { ok = false; }
  if !approx(rel_kinetic_energy_j(1.0, -600), rel_kinetic_energy_j(1.0, 600)) {
    ok = false;
  }
  return assert(ok, "kinetic: 1 kg at 0.6c is 0.25 * c^2 (gamma-1 = 0.25)");
}

fn t19_momentum_zero_and_invalid() -> TestResult {
  var ok = approx(rel_momentum_ns(1.0, 0), 0.0);
  if !approx(rel_momentum_ns(0.0, 600), 0.0) { ok = false; }
  if !approx(rel_momentum_ns(1.0, 1000), 0.0) { ok = false; }
  if !approx(rel_momentum_ns(1.0, -1000), 0.0) { ok = false; }
  if !approx(rel_momentum_ns(1.0, 5000), 0.0) { ok = false; }
  return assert(ok, "momentum: beta 0 and invalid beta give 0.0");
}

fn t20_momentum_0_6c() -> TestResult {
  var ok = approx(rel_momentum_ns(1.0, 600), 224844343.5);
  if !approx(rel_momentum_ns(1.0, -600), -224844343.5) { ok = false; }
  if !approx(rel_momentum_ns(2.0, 600) / rel_momentum_ns(1.0, 600), 2.0) {
    ok = false;
  }
  return assert(ok, "momentum: 1 kg at 0.6c is 224844343.5 kg*m/s, odd in beta");
}

fn main() -> Int {
  io.println("=== xiom.relativity conformance tests ===");
  var failed: Int = 0;
  let r1 = t01_lorentz_beta0();
  if r1.passed { io.println("  [PASS] " + r1.name); } else { io.println("  [FAIL] " + r1.name); failed = failed + 1; }
  let r2 = t02_lorentz_600_exact();
  if r2.passed { io.println("  [PASS] " + r2.name); } else { io.println("  [FAIL] " + r2.name); failed = failed + 1; }
  let r3 = t03_lorentz_800();
  if r3.passed { io.println("  [PASS] " + r3.name); } else { io.println("  [FAIL] " + r3.name); failed = failed + 1; }
  let r4 = t04_lorentz_999_large();
  if r4.passed { io.println("  [PASS] " + r4.name); } else { io.println("  [FAIL] " + r4.name); failed = failed + 1; }
  let r5 = t05_lorentz_symmetry();
  if r5.passed { io.println("  [PASS] " + r5.name); } else { io.println("  [FAIL] " + r5.name); failed = failed + 1; }
  let r6 = t06_lorentz_invalid();
  if r6.passed { io.println("  [PASS] " + r6.name); } else { io.println("  [FAIL] " + r6.name); failed = failed + 1; }
  let r7 = t07_time_dilation();
  if r7.passed { io.println("  [PASS] " + r7.name); } else { io.println("  [FAIL] " + r7.name); failed = failed + 1; }
  let r8 = t08_length_contraction();
  if r8.passed { io.println("  [PASS] " + r8.name); } else { io.println("  [FAIL] " + r8.name); failed = failed + 1; }
  let r9 = t09_dilation_contraction_invalid();
  if r9.passed { io.println("  [PASS] " + r9.name); } else { io.println("  [FAIL] " + r9.name); failed = failed + 1; }
  let r10 = t10_velocity_add_basic();
  if r10.passed { io.println("  [PASS] " + r10.name); } else { io.println("  [FAIL] " + r10.name); failed = failed + 1; }
  let r11 = t11_velocity_add_zero();
  if r11.passed { io.println("  [PASS] " + r11.name); } else { io.println("  [FAIL] " + r11.name); failed = failed + 1; }
  let r12 = t12_velocity_add_negatives();
  if r12.passed { io.println("  [PASS] " + r12.name); } else { io.println("  [FAIL] " + r12.name); failed = failed + 1; }
  let r13 = t13_velocity_add_truncation();
  if r13.passed { io.println("  [PASS] " + r13.name); } else { io.println("  [FAIL] " + r13.name); failed = failed + 1; }
  let r14 = t14_beta_clamp();
  if r14.passed { io.println("  [PASS] " + r14.name); } else { io.println("  [FAIL] " + r14.name); failed = failed + 1; }
  let r15 = t15_velocity_add_clamped();
  if r15.passed { io.println("  [PASS] " + r15.name); } else { io.println("  [FAIL] " + r15.name); failed = failed + 1; }
  let r16 = t16_energy_rest();
  if r16.passed { io.println("  [PASS] " + r16.name); } else { io.println("  [FAIL] " + r16.name); failed = failed + 1; }
  let r17 = t17_kinetic_zero_and_invalid();
  if r17.passed { io.println("  [PASS] " + r17.name); } else { io.println("  [FAIL] " + r17.name); failed = failed + 1; }
  let r18 = t18_kinetic_0_6c();
  if r18.passed { io.println("  [PASS] " + r18.name); } else { io.println("  [FAIL] " + r18.name); failed = failed + 1; }
  let r19 = t19_momentum_zero_and_invalid();
  if r19.passed { io.println("  [PASS] " + r19.name); } else { io.println("  [FAIL] " + r19.name); failed = failed + 1; }
  let r20 = t20_momentum_0_6c();
  if r20.passed { io.println("  [PASS] " + r20.name); } else { io.println("  [FAIL] " + r20.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.relativity: all tests passed");
  } else {
    io.println("xiom.relativity: tests failed");
  }
  return failed;
}
