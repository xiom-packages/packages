// XIOM -- xiom.thermo conformance tests (24 checks)
// Port task: prove the pure-XIOM xiom.thermo module (integer temperature,
// pressure, energy and speed conversions) against its SPEC.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Every expected value is an exact integer result of the documented formulas,
// pinned independently of the module (SPEC.md sections 4 and 5). All
// divisions truncate toward zero; tests that pin a truncated result say so in
// the check name. No Str values are involved, so no str_compare routing is
// needed; no Vec[fn] dispatch -- every test is called explicitly from main.

module thermo_tests
use xiom.io; use xiom.test; use xiom.thermo;

// -- Temperature: Celsius <-> Fahrenheit --

fn t1() -> TestResult {
  var ok = thermo_c_to_f_milli(100000) == 212000;
  if thermo_c_to_f_milli(0) != 32000 { ok = false; }
  if thermo_c_to_f_milli(37000) != 98600 { ok = false; }
  if thermo_c_to_f_milli(-40000) != -40000 { ok = false; }
  return assert(ok, "C->F: 100C=212F, 0C=32F, 37C=98.6F, -40C=-40F");
}

fn t2() -> TestResult {
  var ok = thermo_c_to_f_milli(-100000) == -148000;
  if thermo_c_to_f_milli(5000) != 41000 { ok = false; }
  if thermo_c_to_f_milli(1000) != 33800 { ok = false; }
  return assert(ok, "C->F: -100C=-148F, 5C=41F, 1C=33.8F");
}

fn t3() -> TestResult {
  var ok = thermo_c_to_f_milli(1) == 32001;
  if thermo_c_to_f_milli(-1) != 31999 { ok = false; }
  if thermo_c_to_f_milli(2) != 32003 { ok = false; }
  if thermo_c_to_f_milli(-2) != 31997 { ok = false; }
  return assert(ok, "C->F: c*9/5 truncates toward zero before the +32000 offset");
}

fn t4() -> TestResult {
  var ok = thermo_f_to_c_milli(212000) == 100000;
  if thermo_f_to_c_milli(32000) != 0 { ok = false; }
  if thermo_f_to_c_milli(98600) != 37000 { ok = false; }
  return assert(ok, "F->C: 212F=100C, 32F=0C, 98.6F=37C");
}

fn t5() -> TestResult {
  var ok = thermo_f_to_c_milli(33000) == 555;
  if thermo_f_to_c_milli(31000) != -555 { ok = false; }
  if thermo_f_to_c_milli(31999) != 0 { ok = false; }
  if thermo_f_to_c_milli(0) != -17777 { ok = false; }
  if thermo_f_to_c_milli(1000) != -17222 { ok = false; }
  return assert(ok, "F->C: (f-32000)*5/9 truncates toward zero on both signs");
}

fn t6() -> TestResult {
  var ok = thermo_c_to_k_milli(0) == 273150;
  if thermo_c_to_k_milli(100000) != 373150 { ok = false; }
  if thermo_c_to_k_milli(-273150) != 0 { ok = false; }
  if thermo_k_to_c_milli(273150) != 0 { ok = false; }
  if thermo_k_to_c_milli(300000) != 26850 { ok = false; }
  if thermo_k_to_c_milli(373150) != 100000 { ok = false; }
  return assert(ok, "C<->K: 0C=273.15K, 100C=373.15K, 300K=26.85C exact");
}

fn t7() -> TestResult {
  var ok = thermo_k_to_c_milli(300000) == 26850;
  if thermo_k_to_c_milli(1) != -273149 { ok = false; }
  if thermo_k_to_c_milli(26850) != -246300 { ok = false; }
  if thermo_k_to_c_milli(0) != -273150 { ok = false; }
  return assert(ok, "K->C: 300K=26.850C pinned, sub-zero exact");
}

fn t8() -> TestResult {
  var ok = thermo_f_to_k_milli(32000) == 273150;
  if thermo_f_to_k_milli(212000) != 373150 { ok = false; }
  if thermo_f_to_k_milli(-40000) != 233150 { ok = false; }
  if thermo_f_to_k_milli(0) != 255373 { ok = false; }
  return assert(ok, "F->K: 32F=273.15K, 212F=373.15K, -40F=233.15K, 0F->255373 mK");
}

fn t9() -> TestResult {
  var ok = thermo_k_to_f_milli(273150) == 32000;
  if thermo_k_to_f_milli(373150) != 212000 { ok = false; }
  if thermo_k_to_f_milli(0) != -459670 { ok = false; }
  if thermo_k_to_f_milli(233150) != -40000 { ok = false; }
  return assert(ok, "K->F: 273.15K=32F, 373.15K=212F, 0K=-459.67F");
}

fn t10() -> TestResult {
  var ok = thermo_k_to_f_milli(thermo_f_to_k_milli(32000)) == 32000;
  if thermo_k_to_f_milli(thermo_f_to_k_milli(212000)) != 212000 { ok = false; }
  if thermo_k_to_f_milli(thermo_f_to_k_milli(98600)) != 98600 { ok = false; }
  if thermo_k_to_f_milli(thermo_f_to_k_milli(-40000)) != -40000 { ok = false; }
  if thermo_f_to_k_milli(thermo_k_to_f_milli(273150)) != 273150 { ok = false; }
  if thermo_f_to_k_milli(thermo_k_to_f_milli(373150)) != 373150 { ok = false; }
  if thermo_f_to_k_milli(thermo_k_to_f_milli(310150)) != 310150 { ok = false; }
  if thermo_f_to_k_milli(thermo_k_to_f_milli(233150)) != 233150 { ok = false; }
  return assert(ok, "F<->K round-trips are exact for the pinned temperatures");
}

fn t22() -> TestResult {
  var ok = thermo_above_absolute_zero_k_milli(0);
  if !thermo_above_absolute_zero_k_milli(1) { ok = false; }
  if !thermo_above_absolute_zero_k_milli(273150) { ok = false; }
  if !thermo_above_absolute_zero_k_milli(373150) { ok = false; }
  if !thermo_above_absolute_zero_k_milli(1000000000) { ok = false; }
  if thermo_above_absolute_zero_k_milli(-1) { ok = false; }
  if thermo_above_absolute_zero_k_milli(-2) { ok = false; }
  if thermo_above_absolute_zero_k_milli(-273150) { ok = false; }
  if thermo_above_absolute_zero_k_milli(-1000000000) { ok = false; }
  return assert(ok, "above absolute zero: k >= 0 true, negative k false");
}

// -- Pressure --

fn t11() -> TestResult {
  var ok = thermo_pa_to_hpa(101325) == 1013;
  if thermo_pa_to_hpa(100000) != 1000 { ok = false; }
  if thermo_pa_to_hpa(99999) != 999 { ok = false; }
  if thermo_pa_to_hpa(100) != 1 { ok = false; }
  if thermo_pa_to_hpa(99) != 0 { ok = false; }
  if thermo_pa_to_hpa(1) != 0 { ok = false; }
  if thermo_pa_to_hpa(0) != 0 { ok = false; }
  return assert(ok, "Pa->hPa: pa/100 truncates toward zero (101325 Pa=1013 hPa)");
}

fn t12() -> TestResult {
  var ok = thermo_pa_to_hpa(-150) == -1;
  if thermo_pa_to_hpa(-99) != 0 { ok = false; }
  if thermo_pa_to_hpa(-100) != -1 { ok = false; }
  if thermo_pa_to_hpa(-101325) != -1013 { ok = false; }
  if thermo_pa_to_hpa(-1) != 0 { ok = false; }
  return assert(ok, "Pa->hPa: negative inputs truncate toward zero too");
}

fn t13() -> TestResult {
  var ok = thermo_pa_to_bar_micro(101325) == 1013250;
  if thermo_pa_to_bar_micro(100000) != 1000000 { ok = false; }
  if thermo_pa_to_bar_micro(1) != 10 { ok = false; }
  if thermo_pa_to_bar_micro(0) != 0 { ok = false; }
  if thermo_pa_to_bar_micro(-101325) != -1013250 { ok = false; }
  if thermo_pa_to_bar_micro(123456789) != 1234567890 { ok = false; }
  return assert(ok, "Pa->microbar: pa*10 exact (100000 Pa = 1 bar = 1000000 ubar)");
}

fn t14() -> TestResult {
  var ok = thermo_pa_to_atm_micro(101325) == 1000000;
  if thermo_pa_to_atm_micro(1013250) != 10000000 { ok = false; }
  if thermo_pa_to_atm_micro(0) != 0 { ok = false; }
  if thermo_pa_to_atm_micro(-101325) != -1000000 { ok = false; }
  if thermo_pa_to_atm_micro(-202650) != -2000000 { ok = false; }
  return assert(ok, "Pa->micro-atm: 101325 Pa = 1000000 uatm exactly");
}

fn t15() -> TestResult {
  var ok = thermo_pa_to_atm_micro(1) == 9;
  if thermo_pa_to_atm_micro(-1) != -9 { ok = false; }
  if thermo_pa_to_atm_micro(200000) != 1973846 { ok = false; }
  if thermo_pa_to_atm_micro(101324) != 999990 { ok = false; }
  return assert(ok, "Pa->micro-atm: pa*1000000/101325 truncates toward zero");
}

// -- Energy --

fn t16() -> TestResult {
  var ok = thermo_j_to_cal_milli(4184000) == 1000000;
  if thermo_j_to_cal_milli(4184) != 1000 { ok = false; }
  if thermo_j_to_cal_milli(8368000) != 2000000 { ok = false; }
  if thermo_j_to_cal_milli(0) != 0 { ok = false; }
  if thermo_j_to_cal_milli(-4184000) != -1000000 { ok = false; }
  if thermo_j_to_cal_milli(-8368000) != -2000000 { ok = false; }
  return assert(ok, "J->mcal: 4184 J = 1000000 mcal exactly, both signs");
}

fn t17() -> TestResult {
  var ok = thermo_j_to_cal_milli(1000) == 239;
  if thermo_j_to_cal_milli(1000000) != 239005 { ok = false; }
  if thermo_j_to_cal_milli(-1000) != -239 { ok = false; }
  if thermo_j_to_cal_milli(-1000000) != -239005 { ok = false; }
  if thermo_j_to_cal_milli(1) != 0 { ok = false; }
  if thermo_j_to_cal_milli(-1) != 0 { ok = false; }
  return assert(ok, "J->mcal: 1 J=239 mcal, 1000 J=239005 mcal, truncated both signs");
}

fn t18() -> TestResult {
  var ok = thermo_cal_to_j_milli(1000) == 4184;
  if thermo_cal_to_j_milli(1) != 4 { ok = false; }
  if thermo_cal_to_j_milli(-1) != -4 { ok = false; }
  if thermo_cal_to_j_milli(0) != 0 { ok = false; }
  if thermo_cal_to_j_milli(1000000) != 4184000 { ok = false; }
  if thermo_cal_to_j_milli(239005) != 999996 { ok = false; }
  return assert(ok, "mcal->J: cal*4184/1000; 1000 J round-trip lands on 999996 mJ");
}

// -- Speed --

fn t19() -> TestResult {
  var ok = thermo_kmh_to_ms_milli(36000) == 10000;
  if thermo_kmh_to_ms_milli(72000) != 20000 { ok = false; }
  if thermo_kmh_to_ms_milli(3600) != 1000 { ok = false; }
  if thermo_kmh_to_ms_milli(0) != 0 { ok = false; }
  return assert(ok, "km/h->m/s: 36 km/h=10 m/s, 72 km/h=20 m/s, 3.6 km/h=1 m/s");
}

fn t20() -> TestResult {
  var ok = thermo_kmh_to_ms_milli(10000) == 2777;
  if thermo_kmh_to_ms_milli(-10000) != -2777 { ok = false; }
  if thermo_kmh_to_ms_milli(1000) != 277 { ok = false; }
  if thermo_kmh_to_ms_milli(-1000) != -277 { ok = false; }
  if thermo_kmh_to_ms_milli(1) != 0 { ok = false; }
  if thermo_kmh_to_ms_milli(-1) != 0 { ok = false; }
  return assert(ok, "km/h->m/s: kmh*1000/3600 truncates toward zero both signs");
}

fn t21() -> TestResult {
  var ok = thermo_ms_to_kmh_milli(1000) == 3600;
  if thermo_ms_to_kmh_milli(10000) != 36000 { ok = false; }
  if thermo_ms_to_kmh_milli(1000000) != 3600000 { ok = false; }
  if thermo_ms_to_kmh_milli(0) != 0 { ok = false; }
  if thermo_ms_to_kmh_milli(-1000) != -3600 { ok = false; }
  if thermo_ms_to_kmh_milli(1) != 3 { ok = false; }
  if thermo_ms_to_kmh_milli(-1) != -3 { ok = false; }
  return assert(ok, "m/s->km/h: 1 m/s=3600 mkm/h, 1 mm/s=3 mkm/h truncated");
}

// -- Edge cases --

fn t23() -> TestResult {
  var ok = thermo_c_to_f_milli(1000000000) == 1800032000;
  if thermo_c_to_k_milli(1000000000) != 1000273150 { ok = false; }
  if thermo_k_to_c_milli(1000000000000) != 999999726850 { ok = false; }
  if thermo_pa_to_bar_micro(123456789) != 1234567890 { ok = false; }
  if thermo_pa_to_atm_micro(1000000000) != 9869232667 { ok = false; }
  if thermo_cal_to_j_milli(1000000000) != 4184000000 { ok = false; }
  if thermo_j_to_cal_milli(4184000000) != 1000000000 { ok = false; }
  if thermo_ms_to_kmh_milli(1000000) != 3600000 { ok = false; }
  return assert(ok, "large values stay exact in 64-bit integer math");
}

fn t24() -> TestResult {
  var ok = thermo_c_to_f_milli(0) == 32000;
  if thermo_f_to_c_milli(32000) != 0 { ok = false; }
  if thermo_c_to_k_milli(0) != 273150 { ok = false; }
  if thermo_k_to_c_milli(273150) != 0 { ok = false; }
  if thermo_f_to_k_milli(32000) != 273150 { ok = false; }
  if thermo_k_to_f_milli(273150) != 32000 { ok = false; }
  if thermo_pa_to_hpa(0) != 0 { ok = false; }
  if thermo_pa_to_bar_micro(0) != 0 { ok = false; }
  if thermo_pa_to_atm_micro(0) != 0 { ok = false; }
  if thermo_j_to_cal_milli(0) != 0 { ok = false; }
  if thermo_cal_to_j_milli(0) != 0 { ok = false; }
  if thermo_kmh_to_ms_milli(0) != 0 { ok = false; }
  if thermo_ms_to_kmh_milli(0) != 0 { ok = false; }
  if !thermo_above_absolute_zero_k_milli(0) { ok = false; }
  return assert(ok, "zero inputs map to the exact zero points of every scale");
}

fn main() -> Int {
  io.println("=== xiom.thermo conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.thermo: all tests passed");
  } else {
    io.println("xiom.thermo: tests failed");
  }
  return failed;
}
