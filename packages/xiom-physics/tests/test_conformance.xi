// XIOM -- xiom.physics conformance tests (22 checks)
// Port task: prove the pure-XIOM xiom.physics module (scalar SI mechanics)
// against its SPEC.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Every expected value is a pinned decimal result of the documented formulas
// (SPEC.md section 5), compared with an absolute tolerance of 1e-9 through
// the phys_close helper (stdlib xiom.math.abs_float; the raw libm fabs is
// module-private). The tests pin the guard rules G1-G4 as well: non-positive
// time and negative radius/mass inputs return 0.0. No Str values are read
// from Vec elements, so no str_compare routing is needed; no Vec[fn]
// dispatch -- every test is called explicitly from main.

module physics_tests
use xiom.io; use xiom.test; use xiom.physics; use xiom.math;

fn phys_close(a: Float64, b: Float64) -> Bool {
  return xiom.math.abs_float(a - b) < 0.000000001;
}

// -- Kinematics --

fn t1() -> TestResult {
  var ok = phys_close(phys_velocity(100.0, 10.0), 10.0);
  if !phys_close(phys_velocity(50.0, 4.0), 12.5) { ok = false; }
  if !phys_close(phys_velocity(0.0, 5.0), 0.0) { ok = false; }
  if !phys_close(phys_velocity(-20.0, 4.0), -5.0) { ok = false; }
  return assert(ok, "velocity: 100 m / 10 s = 10 m/s; 50/4 = 12.5; signed displacement kept");
}

fn t2() -> TestResult {
  var ok = phys_close(phys_velocity(100.0, 0.0), 0.0);
  if !phys_close(phys_velocity(100.0, -10.0), 0.0) { ok = false; }
  if !phys_close(phys_velocity(0.0, 0.0), 0.0) { ok = false; }
  return assert(ok, "velocity guard G1: time <= 0 returns 0.0");
}

fn t3() -> TestResult {
  var ok = phys_close(phys_acceleration(20.0, 4.0), 5.0);
  if !phys_close(phys_acceleration(-9.8, 2.0), -4.9) { ok = false; }
  if !phys_close(phys_acceleration(0.0, 4.0), 0.0) { ok = false; }
  return assert(ok, "acceleration: 20 m/s over 4 s = 5 m/s^2; -9.8/2 = -4.9 m/s^2");
}

fn t4() -> TestResult {
  var ok = phys_close(phys_acceleration(10.0, 0.0), 0.0);
  if !phys_close(phys_acceleration(10.0, -1.0), 0.0) { ok = false; }
  if !phys_close(phys_acceleration(-10.0, 0.0), 0.0) { ok = false; }
  return assert(ok, "acceleration guard G1: delta_t <= 0 returns 0.0");
}

fn t5() -> TestResult {
  var ok = phys_close(phys_position(1.0, 2.0, 3.0, 4.0), 33.0);
  if !phys_close(phys_position(2.0, 3.0, 0.0, 4.0), 14.0) { ok = false; }
  if !phys_close(phys_position(0.0, 0.0, 9.80665, 2.0), 19.6133) { ok = false; }
  if !phys_close(phys_position(5.0, 0.0, 0.0, 3.0), 5.0) { ok = false; }
  return assert(ok, "SUVAT position: s0 + v0*t + a*t*t/2 pinned at four inputs");
}

fn t6() -> TestResult {
  var ok = phys_close(phys_position(1.0, 2.0, 3.0, 0.0), 0.0);
  if !phys_close(phys_position(1.0, 2.0, 3.0, -4.0), 0.0) { ok = false; }
  return assert(ok, "position guard G1: t <= 0 returns 0.0 (not s0)");
}

fn t7() -> TestResult {
  var ok = phys_close(phys_velocity_at(2.0, 3.0, 4.0), 14.0);
  if !phys_close(phys_velocity_at(5.0, 0.0, 3.0), 5.0) { ok = false; }
  if !phys_close(phys_velocity_at(0.0, 9.80665, 3.0), 29.41995) { ok = false; }
  if !phys_close(phys_velocity_at(10.0, -2.0, 3.0), 4.0) { ok = false; }
  return assert(ok, "SUVAT velocity: v0 + a*t pinned, including deceleration");
}

fn t8() -> TestResult {
  var ok = phys_close(phys_velocity_at(5.0, 5.0, 0.0), 0.0);
  if !phys_close(phys_velocity_at(5.0, 5.0, -1.0), 0.0) { ok = false; }
  return assert(ok, "velocity_at guard G1: t <= 0 returns 0.0 (not v0)");
}

fn t9() -> TestResult {
  var ok = phys_close(phys_position(0.0, 0.0, 9.80665, 3.0), 44.129925);
  if !phys_close(phys_position(0.0, 0.0, 9.80665, 1.0), 4.903325) { ok = false; }
  if !phys_close(phys_velocity_at(0.0, 9.80665, 3.0), 29.41995) { ok = false; }
  return assert(ok, "free fall from rest: s = g*t^2/2 and v = g*t with g = 9.80665");
}

// -- Energy, momentum, work, power --

fn t10() -> TestResult {
  var ok = phys_close(phys_kinetic_energy(2.0, 3.0), 9.0);
  if !phys_close(phys_kinetic_energy(4.0, 2.5), 12.5) { ok = false; }
  if !phys_close(phys_kinetic_energy(1.0, 0.0), 0.0) { ok = false; }
  if !phys_close(phys_kinetic_energy(1.0, -2.0), 2.0) { ok = false; }
  return assert(ok, "kinetic energy: 2 kg at 3 m/s = 9 J; v is squared, sign lost");
}

fn t11() -> TestResult {
  var ok = phys_close(phys_kinetic_energy(-2.0, 3.0), 0.0);
  if !phys_close(phys_kinetic_energy(-1.0, 0.0), 0.0) { ok = false; }
  if !phys_close(phys_kinetic_energy(-0.5, -2.0), 0.0) { ok = false; }
  return assert(ok, "kinetic energy guard G4: negative mass returns 0.0");
}

fn t12() -> TestResult {
  var ok = phys_close(phys_potential_energy(2.0, 1.5, 9.80665), 29.41995);
  if !phys_close(phys_potential_energy(1.0, 0.0, 9.80665), 0.0) { ok = false; }
  if !phys_close(phys_potential_energy(0.0, 5.0, 9.8), 0.0) { ok = false; }
  if !phys_close(phys_potential_energy(3.0, 2.0, 9.8), 58.8) { ok = false; }
  if !phys_close(phys_potential_energy(1.0, -2.0, 9.8), -19.6) { ok = false; }
  return assert(ok, "potential energy: m*g*h pinned, signed height accepted");
}

fn t13() -> TestResult {
  var ok = phys_close(phys_momentum(2.0, 3.0), 6.0);
  if !phys_close(phys_momentum(1.0, -4.0), -4.0) { ok = false; }
  if !phys_close(phys_momentum(0.0, 5.0), 0.0) { ok = false; }
  if !phys_close(phys_momentum(2.5, 2.0), 5.0) { ok = false; }
  return assert(ok, "momentum: 2 kg at 3 m/s = 6 kg*m/s; signed by velocity");
}

fn t14() -> TestResult {
  var ok = phys_close(phys_work(10.0, 4.0), 40.0);
  if !phys_close(phys_work(5.0, 0.0), 0.0) { ok = false; }
  if !phys_close(phys_work(2.0, -3.0), -6.0) { ok = false; }
  if !phys_close(phys_work(-4.0, 2.5), -10.0) { ok = false; }
  return assert(ok, "work: 10 N over 4 m = 40 J; opposing force gives negative work");
}

fn t15() -> TestResult {
  var ok = phys_close(phys_power(100.0, 4.0), 25.0);
  if !phys_close(phys_power(0.0, 5.0), 0.0) { ok = false; }
  if !phys_close(phys_power(-50.0, 2.0), -25.0) { ok = false; }
  return assert(ok, "power: 100 J over 4 s = 25 W; signed work kept");
}

fn t16() -> TestResult {
  var ok = phys_close(phys_power(100.0, 0.0), 0.0);
  if !phys_close(phys_power(100.0, -4.0), 0.0) { ok = false; }
  if !phys_close(phys_power(-30.0, 0.0), 0.0) { ok = false; }
  return assert(ok, "power guard G1: time <= 0 returns 0.0");
}

// -- Gravitation and geometry --

fn t17() -> TestResult {
  var ok = phys_close(phys_gravitational_force(5.972e24, 1.0, 6.371e6), 9.819532032816);
  if !phys_close(phys_gravitational_force(1.0, 1.0, 1.0), 6.674e-11) { ok = false; }
  if !phys_close(phys_gravitational_force(1.0e11, 1.0e11, 1.0e6), 0.6674) { ok = false; }
  return assert(ok, "gravitational force: Earth-like mass pulls 1 kg at 9.82 N; G pinned");
}

fn t18() -> TestResult {
  var ok = phys_close(phys_gravitational_force(1.0, 1.0, 0.0), 0.0);
  if !phys_close(phys_gravitational_force(1.0, 1.0, -5.0), 0.0) { ok = false; }
  if !phys_close(phys_gravitational_force(0.0, 5.972e24, 1.0e7), 0.0) { ok = false; }
  if !phys_close(phys_gravitational_force(5.972e24, 0.0, 1.0e7), 0.0) { ok = false; }
  return assert(ok, "gravity guard G3: r <= 0 returns 0.0; a zero mass gives zero force");
}

fn t19() -> TestResult {
  var ok = phys_close(phys_circle_area(2.0), 12.566370614);
  if !phys_close(phys_circle_area(1.0), 3.1415926535898) { ok = false; }
  if !phys_close(phys_circle_area(0.5), 0.7853981633974) { ok = false; }
  if !phys_close(phys_circle_area(0.0), 0.0) { ok = false; }
  return assert(ok, "circle area: pi*r^2; r = 2 -> 12.566370614 m^2; r = 0 -> 0");
}

fn t20() -> TestResult {
  var ok = phys_close(phys_sphere_volume(1.0), 4.188790205);
  if !phys_close(phys_sphere_volume(2.0), 33.51032163829) { ok = false; }
  if !phys_close(phys_sphere_volume(0.5), 0.5235987756) { ok = false; }
  if !phys_close(phys_sphere_volume(0.0), 0.0) { ok = false; }
  return assert(ok, "sphere volume: 4*pi*r^3/3; r = 1 -> 4.188790205 m^3; r = 0 -> 0");
}

fn t21() -> TestResult {
  var ok = phys_close(phys_circle_area(-1.0), 0.0);
  if !phys_close(phys_circle_area(-0.5), 0.0) { ok = false; }
  if !phys_close(phys_sphere_volume(-1.0), 0.0) { ok = false; }
  if !phys_close(phys_sphere_volume(-2.5), 0.0) { ok = false; }
  return assert(ok, "geometry guard G2: negative radius returns 0.0");
}

fn t22() -> TestResult {
  var ok = phys_close(phys_velocity(0.0, 5.0), 0.0);
  if !phys_close(phys_acceleration(0.0, 5.0), 0.0) { ok = false; }
  if !phys_close(phys_position(0.0, 0.0, 0.0, 5.0), 0.0) { ok = false; }
  if !phys_close(phys_velocity_at(0.0, 0.0, 5.0), 0.0) { ok = false; }
  if !phys_close(phys_kinetic_energy(0.0, 3.0), 0.0) { ok = false; }
  if !phys_close(phys_potential_energy(0.0, 2.0, 9.8), 0.0) { ok = false; }
  if !phys_close(phys_momentum(0.0, 3.0), 0.0) { ok = false; }
  if !phys_close(phys_work(0.0, 4.0), 0.0) { ok = false; }
  if !phys_close(phys_power(0.0, 4.0), 0.0) { ok = false; }
  if !phys_close(phys_gravitational_force(0.0, 0.0, 1.0), 0.0) { ok = false; }
  if !phys_close(phys_circle_area(0.0), 0.0) { ok = false; }
  if !phys_close(phys_sphere_volume(0.0), 0.0) { ok = false; }
  return assert(ok, "zero inputs map to 0.0 across every function");
}

fn main() -> Int {
  io.println("=== xiom.physics conformance tests ===");
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
    io.println("xiom.physics: all tests passed");
  } else {
    io.println("xiom.physics: tests failed");
  }
  return failed;
}
