// XIOM -- xiom.materials conformance tests (26 checks)
// Port task: prove the pure-XIOM xiom.materials module (fixed-point isotropic
// elasticity, Voigt Hooke's law, invariants, yield checks, temperature table)
// against its SPEC.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Every expected value is an exact integer result of the documented formulas,
// pinned independently of the module (SPEC.md sections 4-8). The primary
// fixture is E = 200000 MPa, nu = 0.25, which makes G and lambda exact; a
// second material exercises the truncating paths. No Vec[fn] dispatch -- every
// test is called explicitly from main.

module materials_tests
use xiom.io; use xiom.test; use xiom.materials;

// Fixture A: E = 200000.0000 MPa = 2000000000, nu = 0.2500 = 2500.
//   G      = 800000000   (80000.0000 MPa, exact)
//   K      = 1333333333  (133333.3333 MPa, truncated)
//   lambda = 800000000   (80000.0000 MPa, exact)

fn t1() -> TestResult {
  var ok = mat_shear_modulus(2000000000, 2500) == 800000000;
  if mat_shear_modulus(2000000000, 3000) != 769230769 { ok = false; }
  if mat_shear_modulus(700000000, 3300) != 263157894 { ok = false; }
  return assert(ok, "G = E/(2(1+nu)): exact at nu=0.25, truncated otherwise");
}

fn t2() -> TestResult {
  var ok = mat_bulk_modulus(2000000000, 2500) == 1333333333;
  if mat_bulk_modulus(2000000000, 3000) != 1666666666 { ok = false; }
  if mat_bulk_modulus(700000000, 3300) != 686274509 { ok = false; }
  return assert(ok, "K = E/(3(1-2nu)): truncated toward zero");
}

fn t3() -> TestResult {
  var ok = mat_lame_lambda(2000000000, 2500) == 800000000;
  if mat_lame_lambda(2000000000, 3000) != 1153846153 { ok = false; }
  return assert(ok, "lambda = E*nu/((1+nu)(1-2nu)): exact at nu=0.25, truncated at nu=0.3");
}

fn t4() -> TestResult {
  var ok = mat_shear_modulus(700000000, 3300) == 263157894;
  if mat_bulk_modulus(700000000, 3300) != 686274509 { ok = false; }
  if mat_shear_modulus(2000000000, 2500) * 2 != 1600000000 { ok = false; }
  return assert(ok, "moduli relations hold for a second material (E=70 GPa, nu=0.33)");
}

fn t5() -> TestResult {
  let lam = 800000000;
  let g = 800000000;
  var ok = mat_hooke_normal(lam, g, 12, 8) == 2240000;
  if mat_hooke_normal(lam, g, 12, 4) != 1600000 { ok = false; }
  if mat_hooke_normal(lam, g, 12, 0) != 960000 { ok = false; }
  return assert(ok, "Hooke normal stresses: sigma_xx=224, sigma_yy=160, sigma_zz=96 MPa");
}

fn t6() -> TestResult {
  let lam = 800000000;
  let g = 800000000;
  let sxx = mat_hooke_normal(lam, g, 12, 8);
  let syy = mat_hooke_normal(lam, g, 12, 4);
  let szz = mat_hooke_normal(lam, g, 12, 0);
  var ok = sxx - syy == 640000;
  if syy - szz != 640000 { ok = false; }
  if sxx + syy + szz != 4800000 { ok = false; }
  return assert(ok, "Hooke normal stress sum and differences are consistent (uniaxial-like state)");
}

fn t7() -> TestResult {
  var ok = mat_hooke_shear(800000000, 12) == 960000;
  if mat_hooke_shear(800000000, 0) != 0 { ok = false; }
  if mat_hooke_shear(800000000, -12) != -960000 { ok = false; }
  return assert(ok, "Hooke shear: tau = G*gamma (960 MPa at gamma=0.0012), antisymmetric");
}

fn t8() -> TestResult {
  var ok = mat_hooke_inverse_normal(2000000000, 2500, 2240000, 2560000) == 8;
  if mat_hooke_inverse_normal(2000000000, 2500, 1600000, 3200000) != 4 { ok = false; }
  if mat_hooke_inverse_normal(2000000000, 2500, 960000, 3840000) != 0 { ok = false; }
  return assert(ok, "inverse Hooke normal: recovers eps_xx=0.0008, eps_yy=0.0004, eps_zz=0");
}

fn t9() -> TestResult {
  var ok = mat_hooke_inverse_shear(800000000, 960000) == 6;
  if mat_hooke_inverse_shear(800000000, -960000) != -6 { ok = false; }
  if mat_hooke_inverse_shear(800000000, 0) != 0 { ok = false; }
  return assert(ok, "inverse Hooke shear: gamma=0.0012 maps back to eps=0.0006");
}

fn t10() -> TestResult {
  let lam = 800000000;
  let g = 800000000;
  let sxx = mat_hooke_normal(lam, g, 12, 8);
  let syy = mat_hooke_normal(lam, g, 12, 4);
  let szz = mat_hooke_normal(lam, g, 12, 0);
  let exx = mat_hooke_inverse_normal(2000000000, 2500, sxx, syy + szz);
  let eyy = mat_hooke_inverse_normal(2000000000, 2500, syy, sxx + szz);
  let ezz = mat_hooke_inverse_normal(2000000000, 2500, szz, sxx + syy);
  var ok = exx == 8 && eyy == 4 && ezz == 0;
  let trace = exx + eyy + ezz;
  if mat_hooke_normal(lam, g, trace, exx) != sxx { ok = false; }
  if mat_hooke_normal(lam, g, trace, eyy) != syy { ok = false; }
  if mat_hooke_normal(lam, g, trace, ezz) != szz { ok = false; }
  return assert(ok, "strain->stress->strain round trip is exact on the exact fixture");
}

fn t11() -> TestResult {
  var ok = mat_invariant_i1(3, 4, 5) == 12;
  if mat_invariant_i1(-3, 4, 5) != 6 { ok = false; }
  if mat_invariant_i1(0, 0, 0) != 0 { ok = false; }
  if mat_invariant_i1(2500000, 1000000, -500000) != 3000000 { ok = false; }
  return assert(ok, "I1 = sigma_xx + sigma_yy + sigma_zz, signs preserved");
}

fn t12() -> TestResult {
  var ok = mat_von_mises(2500000, 0, 0, 0, 0, 0) == 2500000;
  if mat_von_mises(0, 0, 0, 0, 0, 0) != 0 { ok = false; }
  if mat_von_mises(1000000, 1000000, 1000000, 0, 0, 0) != 0 { ok = false; }
  return assert(ok, "von Mises: uniaxial equals the axial stress; hydrostatic is zero");
}

fn t13() -> TestResult {
  var ok = mat_von_mises(0, 0, 0, 1000000, 0, 0) == 1732050;
  if mat_von_mises(0, 0, 0, 0, 1000000, 0) != 1732050 { ok = false; }
  if mat_von_mises(0, 0, 0, 0, 0, 1000000) != 1732050 { ok = false; }
  return assert(ok, "von Mises pure shear: sqrt(3)*tau floored = 173.2050 MPa");
}

fn t14() -> TestResult {
  var ok = mat_von_mises(1000000, 500000, 0, 0, 0, 250000) == 968245;
  if mat_von_mises_sq(1000000, 500000, 0, 0, 0, 250000) != 1875000000000 { ok = false; }
  return assert(ok, "von Mises mixed state pinned (D2=1.875e12, vm=96.8245 MPa)");
}

fn t15() -> TestResult {
  var ok = mat_isqrt(0) == 0;
  if mat_isqrt(1) != 1 { ok = false; }
  if mat_isqrt(15) != 3 { ok = false; }
  if mat_isqrt(16) != 4 { ok = false; }
  if mat_isqrt(17) != 4 { ok = false; }
  if mat_isqrt(144) != 12 { ok = false; }
  if mat_isqrt(1000000000000) != 1000000 { ok = false; }
  return assert(ok, "integer square root floors correctly (0,1,15,16,17,144,1e12)");
}

fn t16() -> TestResult {
  var ok = mat_principal_max_shear(3000000, 1000000, -1000000) == 2000000;
  if mat_principal_max_shear(1000000, 1000000, 1000000) != 0 { ok = false; }
  if mat_principal_max_shear(-1000000, -2000000, -4000000) != 1500000 { ok = false; }
  return assert(ok, "principal max shear = (max-min)/2 from sorted/unsorted triples");
}

fn t17() -> TestResult {
  var ok = mat_principal_von_mises(3000000, 1000000, -1000000) == 3464101;
  if mat_principal_von_mises(1000000, 1000000, 1000000) != 0 { ok = false; }
  return assert(ok, "principal von Mises: (300,100,-100) MPa -> 346.4101 MPa; hydrostatic zero");
}

fn t18() -> TestResult {
  var ok = mat_safety_factor_x1e4(2500000, 2000000) == 12500;
  if mat_safety_factor_x1e4(2500000, 2500000) != 10000 { ok = false; }
  if mat_safety_factor_x1e4(2500000, 5000000) != 5000 { ok = false; }
  if mat_safety_factor_x1e4(2500000, 0) != -1 { ok = false; }
  if mat_safety_factor_x1e4(2500000, -1) != -1 { ok = false; }
  return assert(ok, "safety factor x1e4: yield/vm, undefined stress returns -1");
}

fn t19() -> TestResult {
  var ok = mat_within_yield(2500000, 2000000);
  if !mat_within_yield(2500000, 2500000) { ok = false; }
  if mat_within_yield(2500000, 2500001) { ok = false; }
  if !mat_within_yield(2500000, 0) { ok = false; }
  return assert(ok, "within-yield is inclusive at the yield strength");
}

fn t20() -> TestResult {
  var ok = mat_yield_flag(2500000, 2000000) == 0;
  if mat_yield_flag(2500000, 2500000) != 0 { ok = false; }
  if mat_yield_flag(2500000, 2500001) != 1 { ok = false; }
  if mat_yield_flag(2500000, 5000000) != 1 { ok = false; }
  return assert(ok, "yield flag: 1 above yield strength, 0 at or below");
}

fn t21() -> TestResult {
  var ok = mat_scale() == 10000;
  if mat_stress_unit_code() != 1 { ok = false; }
  if !mat_unit_consistent(10000) { ok = false; }
  if mat_unit_consistent(1000) { ok = false; }
  if mat_unit_consistent(0) { ok = false; }
  return assert(ok, "unit-consistency metadata: scale 1e-4, code 1, guard matches");
}

fn t22() -> TestResult {
  var temps = Vec[Int].new();
  temps.push(200000);
  temps.push(400000);
  var factors = Vec[Int].new();
  factors.push(10000);
  factors.push(9500);
  var ok = mat_scale_at_temp(2000000000, &temps, &factors, 200000) == 2000000000;
  if mat_scale_at_temp(2000000000, &temps, &factors, 400000) != 1900000000 { ok = false; }
  if mat_scale_at_temp(2000000000, &temps, &factors, 300000) != 1950000000 { ok = false; }
  return assert(ok, "temperature table: endpoints exact, midpoint interpolates to 0.975");
}

fn t23() -> TestResult {
  var temps = Vec[Int].new();
  temps.push(200000);
  temps.push(400000);
  var factors = Vec[Int].new();
  factors.push(10000);
  factors.push(9500);
  var ok = mat_scale_at_temp(2000000000, &temps, &factors, 100000) == 2000000000;
  if mat_scale_at_temp(2000000000, &temps, &factors, 500000) != 1900000000 { ok = false; }
  return assert(ok, "temperature table clamps outside the supplied range");
}

fn t24() -> TestResult {
  var values = Vec[Int].new();
  var temps = Vec[Int].new();
  var factors = Vec[Int].new();
  var ok = mat_scale_at_temp(1234567, &temps, &factors, 300000) == 1234567;
  if values.len() != 0 { ok = false; }
  return assert(ok, "empty temperature table returns the value unchanged");
}

fn t25() -> TestResult {
  var ok = mat_mul_overflows(3, 4) == false;
  if mat_mul_overflows(4000000000, 4000000000) == false { ok = false; }
  if mat_mul_overflows(0, 4000000000) { ok = false; }
  if mat_mul_overflows(-4000000000, 4000000000) == false { ok = false; }
  return assert(ok, "overflow guard flags wide products, allows small/zero ones");
}

fn t26() -> TestResult {
  let g = mat_shear_modulus(2000000000, 2500);
  let lam = mat_lame_lambda(2000000000, 2500);
  let nu = 2500;
  let e = 2000000000;
  var ok = e == 2 * g * (10000 + nu) / 10000;
  if lam * (10000 + nu) * (10000 - 2 * nu) / 10000 != e * nu { ok = false; }
  return assert(ok, "moduli and lambda satisfy their defining algebraic relations");
}

fn main() -> Int {
  io.println("=== xiom.materials conformance tests ===");
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
  let r23 = t23();
  if r23.passed { io.println("  [PASS] " + r23.name); } else { io.println("  [FAIL] " + r23.name); failed = failed + 1; }
  let r24 = t24();
  if r24.passed { io.println("  [PASS] " + r24.name); } else { io.println("  [FAIL] " + r24.name); failed = failed + 1; }
  let r25 = t25();
  if r25.passed { io.println("  [PASS] " + r25.name); } else { io.println("  [FAIL] " + r25.name); failed = failed + 1; }
  let r26 = t26();
  if r26.passed { io.println("  [PASS] " + r26.name); } else { io.println("  [FAIL] " + r26.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.materials: all tests passed");
  } else {
    io.println("xiom.materials: tests failed");
  }
  return failed;
}
