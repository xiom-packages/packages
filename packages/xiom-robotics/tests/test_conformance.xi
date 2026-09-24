// XIOM -- xiom.robotics conformance tests (19 checks)
// Port task: prove the pure-XIOM xiom.robotics module (planar 2-link forward
// kinematics, reach checks, differential drive) against its SPEC.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Float comparisons use robo_close(a, b) = abs_float(a - b) < 1e-9 with
// xiom.math.abs_float (the raw libm fabs is module-private in the stdlib).
// The pinned decimals are the documented formulas evaluated by hand; no
// assertion recomputes the expression it checks with the same code path.
// Integer expectations are exact. No Vec is used, no Str element is read, no
// Vec[fn] dispatch: every test is called explicitly from main.

module robotics_tests
use xiom.io; use xiom.test; use xiom.robotics; use xiom.math;

fn robo_close(a: Float64, b: Float64) -> Bool {
  return xiom.math.abs_float(a - b) < 0.000000001;
}

// -- Forward kinematics --

fn t1() -> TestResult {
  let p1 = robot_fk2(1.5, 2.5, 0.0, 0.0);
  var ok = robo_close(p1.x, 4.0);
  if !robo_close(p1.y, 0.0) { ok = false; }
  let p2 = robot_fk2(2.0, 3.0, 0.0, 0.0);
  if !robo_close(p2.x, 5.0) { ok = false; }
  if !robo_close(p2.y, 0.0) { ok = false; }
  return assert(ok, "fk2 straight extended: t1 = t2 = 0 gives x = l1 + l2, y = 0");
}

fn t2() -> TestResult {
  let p = robot_fk2(1.0, 1.0, 0.0, 1.5707963267948966);
  var ok = robo_close(p.x, 1.0);
  if !robo_close(p.y, 1.0) { ok = false; }
  let q = robot_fk2(2.0, 0.0, 0.0, 1.5707963267948966);
  if !robo_close(q.x, 2.0) { ok = false; }
  if !robo_close(q.y, 0.0) { ok = false; }
  return assert(ok, "fk2 90-degree elbow: l1 = l2 = 1, t1 = 0, t2 = pi/2 gives (1, 1)");
}

fn t3() -> TestResult {
  let p = robot_fk2(2.0, 1.0, 1.5707963267948966, -1.5707963267948966);
  var ok = robo_close(p.x, 1.0);
  if !robo_close(p.y, 2.0) { ok = false; }
  let q = robot_fk2(1.5, 1.5, 1.5707963267948966, 1.5707963267948966);
  if !robo_close(q.x, -1.5) { ok = false; }
  if !robo_close(q.y, 1.5) { ok = false; }
  return assert(ok, "fk2 general angles pinned: (2, 1, pi/2, -pi/2) = (1, 2); (1.5, 1.5, pi/2, pi/2) = (-1.5, 1.5)");
}

fn t4() -> TestResult {
  let p = robot_fk2_at(10.0, -5.0, 1.0, 1.0, 0.0, 0.0);
  var ok = robo_close(p.x, 12.0);
  if !robo_close(p.y, -5.0) { ok = false; }
  let q = robot_fk2_at(1.0, 1.0, 2.0, 3.0, 0.0, 3.141592653589793);
  if !robo_close(q.x, 0.0) { ok = false; }
  if !robo_close(q.y, 1.0) { ok = false; }
  let s = robot_fk2_at(0.5, -0.5, 1.0, 1.0, 0.0, 1.5707963267948966);
  if !robo_close(s.x, 1.5) { ok = false; }
  if !robo_close(s.y, 0.5) { ok = false; }
  return assert(ok, "fk2_at translates the origin pose by the base offset");
}

// -- End-effector distance --

fn t5() -> TestResult {
  var ok = robo_close(robot_end_distance(3.0, 4.0, 0.0), 7.0);
  if !robo_close(robot_end_distance(2.0, 5.0, 0.0), 7.0) { ok = false; }
  if !robo_close(robot_end_distance(0.0, 4.0, 0.0), 4.0) { ok = false; }
  return assert(ok, "end_distance theta2 = 0: fully extended, l1 + l2");
}

fn t6() -> TestResult {
  var ok = robo_close(robot_end_distance(5.0, 2.0, 3.141592653589793), 3.0);
  if !robo_close(robot_end_distance(4.0, 4.0, 3.141592653589793), 0.0) { ok = false; }
  if !robo_close(robot_end_distance(0.5, 0.25, 3.141592653589793), 0.25) { ok = false; }
  return assert(ok, "end_distance theta2 = pi: folded back, |l1 - l2|");
}

fn t7() -> TestResult {
  var ok = robo_close(robot_end_distance(3.0, 4.0, 1.5707963267948966), 5.0);
  if !robo_close(robot_end_distance(5.0, 12.0, 1.5707963267948966), 13.0) { ok = false; }
  if !robo_close(robot_end_distance(0.0, 0.0, 1.5707963267948966), 0.0) { ok = false; }
  return assert(ok, "end_distance theta2 = pi/2: Pythagorean sqrt(l1^2 + l2^2)");
}

fn t8() -> TestResult {
  var ok = robo_close(robot_end_distance(-3.0, -4.0, 0.0), 7.0);
  if !robo_close(robot_end_distance(-3.0, 4.0, 3.141592653589793), 1.0) { ok = false; }
  if !robo_close(robot_end_distance(-1.0, -1.0, 3.141592653589793), 0.0) { ok = false; }
  if !robo_close(robot_end_distance(3.0, -4.0, 1.5707963267948966), 5.0) { ok = false; }
  return assert(ok, "end_distance guard G1: negative lengths folded to magnitudes");
}

// -- Reachability --

fn t9() -> TestResult {
  var ok = robot_reach_ok(1.0, 1.0, 2.0);
  if !robot_reach_ok(1.0, 1.0, 0.0) { ok = false; }
  if !robot_reach_ok(1.0, 2.0, 1.0) { ok = false; }
  if !robot_reach_ok(1.0, 2.0, 3.0) { ok = false; }
  if !robot_reach_ok(2.0, 1.0, 1.0) { ok = false; }
  if !robot_reach_ok(0.5, 0.25, 0.25) { ok = false; }
  return assert(ok, "reach_ok boundaries: |l1 - l2| <= r <= l1 + l2 inclusive");
}

fn t10() -> TestResult {
  var ok = !robot_reach_ok(1.0, 1.0, 2.0001);
  if robot_reach_ok(1.0, 1.0, -0.0001) { ok = false; }
  if robot_reach_ok(1.0, 2.0, 0.9999) { ok = false; }
  if robot_reach_ok(1.0, 2.0, 3.0001) { ok = false; }
  if robot_reach_ok(0.0, 0.0, 0.0001) { ok = false; }
  return assert(ok, "reach_ok rejects radii outside the annulus and negative radii");
}

fn t11() -> TestResult {
  var ok = !robot_reach_ok(-1.0, 1.0, 1.0);
  if robot_reach_ok(1.0, -1.0, 1.0) { ok = false; }
  if robot_reach_ok(1.0, 1.0, -1.0) { ok = false; }
  if robot_reach_ok(-1.0, -1.0, -1.0) { ok = false; }
  if !robot_reach_ok(0.0, 0.0, 0.0) { ok = false; }
  return assert(ok, "reach_ok guard G2: any negative argument is false; (0, 0, 0) is true");
}

// -- Angle clamping --

fn t12() -> TestResult {
  var ok = robo_close(robot_clamp_angle_rad(0.0), 0.0);
  if !robo_close(robot_clamp_angle_rad(0.5), 0.5) { ok = false; }
  if !robo_close(robot_clamp_angle_rad(-0.5), -0.5) { ok = false; }
  if !robo_close(robot_clamp_angle_rad(3.141592653589793), 3.141592653589793) { ok = false; }
  if !robo_close(robot_clamp_angle_rad(-3.141592653589793), -3.141592653589793) { ok = false; }
  return assert(ok, "clamp_angle is the identity on [-pi, pi]");
}

fn t13() -> TestResult {
  var ok = robo_close(robot_clamp_angle_rad(4.71238898038469), -1.5707963267948966);
  if !robo_close(robot_clamp_angle_rad(-4.71238898038469), 1.5707963267948966) { ok = false; }
  if !robo_close(robot_clamp_angle_rad(15.707963267948966), 3.141592653589793) { ok = false; }
  if !robo_close(robot_clamp_angle_rad(-6.283185307179586), 0.0) { ok = false; }
  return assert(ok, "clamp_angle folds: 3pi/2 -> -pi/2, -3pi/2 -> pi/2, 5pi -> pi, -2pi -> 0");
}

fn t14() -> TestResult {
  var ok = robo_close(robot_clamp_angle_rad(-15.707963267948966), -3.141592653589793);
  if !robo_close(robot_clamp_angle_rad(10.995574287564276), -1.5707963267948966) { ok = false; }
  if !robo_close(robot_clamp_angle_rad(6.283185307179586), 0.0) { ok = false; }
  if !robo_close(robot_clamp_angle_rad(10.0), -2.566370614359172) { ok = false; }
  if !robo_close(robot_clamp_angle_rad(0.000000000001), 0.000000000001) { ok = false; }
  return assert(ok, "clamp_angle multi-turn folds, -5pi -> -pi, 7pi/2 -> -pi/2, 10 -> 10 - 4pi");
}

// -- Differential drive --

fn t15() -> TestResult {
  if robot_diff_drive_v_mm_s(300, 300) != 300 { return assert(false, "diff drive v: straight 300/300"); }
  if robot_diff_drive_v_mm_s(-100, -100) != -100 { return assert(false, "diff drive v: straight -100/-100"); }
  if robot_diff_drive_v_mm_s(100, 300) != 200 { return assert(false, "diff drive v: (100+300)/2"); }
  if robot_diff_drive_v_mm_s(1, 2) != 1 { return assert(false, "diff drive v: truncation 3/2 -> 1"); }
  if robot_diff_drive_v_mm_s(-3, 0) != -1 { return assert(false, "diff drive v: truncation -3/2 -> -1 toward zero"); }
  return assert(true, "diff drive v: straight, turn and truncation toward zero pinned");
}

fn t16() -> TestResult {
  if robot_diff_drive_omega_mrad_s(100, 300, 400) != 500 { return assert(false, "omega: (300-100)*1000/400 = 500"); }
  if robot_diff_drive_omega_mrad_s(-200, 200, 400) != 1000 { return assert(false, "omega: spin in place 400 mrad/s pair -> 1000"); }
  if robot_diff_drive_omega_mrad_s(0, 0, 400) != 0 { return assert(false, "omega: zero wheels -> 0"); }
  if robot_diff_drive_omega_mrad_s(300, 100, 1000) != -200 { return assert(false, "omega: negative turn -200"); }
  if robot_diff_drive_omega_mrad_s(0, 100, 3000) != 33 { return assert(false, "omega: truncation 100000/3000 -> 33"); }
  if robot_diff_drive_omega_mrad_s(0, -100, 3000) != -33 { return assert(false, "omega: truncation -100000/3000 -> -33 toward zero"); }
  return assert(true, "diff drive omega: straight, spin and truncation toward zero pinned");
}

fn t17() -> TestResult {
  if robot_diff_drive_omega_mrad_s(100, 300, 0) != 0 { return assert(false, "omega guard G4: wheel_base 0 -> 0"); }
  if robot_diff_drive_omega_mrad_s(100, 300, -400) != 0 { return assert(false, "omega guard G4: negative wheel_base -> 0"); }
  if robot_diff_drive_omega_mrad_s(-100, 100, -1) != 0 { return assert(false, "omega guard G4: wheel_base -1 -> 0"); }
  return assert(true, "diff drive omega guard G4: wheel_base <= 0 returns 0");
}

fn t18() -> TestResult {
  let w1 = robot_wheel_speeds_mm_s(500, 1000, 500);
  var ok = w1.0 == 250;
  if w1.1 != 750 { ok = false; }
  if robot_diff_drive_v_mm_s(w1.0, w1.1) != 500 { ok = false; }
  if robot_diff_drive_omega_mrad_s(w1.0, w1.1, 500) != 1000 { ok = false; }
  let w2 = robot_wheel_speeds_mm_s(-100, -250, 400);
  if w2.0 != -50 { ok = false; }
  if w2.1 != -150 { ok = false; }
  if robot_diff_drive_v_mm_s(w2.0, w2.1) != -100 { ok = false; }
  if robot_diff_drive_omega_mrad_s(w2.0, w2.1, 400) != -250 { ok = false; }
  return assert(ok, "wheel_speeds round-trips v and omega through the forward model");
}

fn t19() -> TestResult {
  let w3 = robot_wheel_speeds_mm_s(10, 333, 1000);
  var ok = w3.0 == -156;
  if w3.1 != 176 { ok = false; }
  let big = robot_fk2(1000000.0, 2000000.0, 0.0, 0.0);
  if !robo_close(big.x, 3000000.0) { ok = false; }
  if !robo_close(big.y, 0.0) { ok = false; }
  let big2 = robot_fk2_at(1000000000.0, -1000000000.0, 1000000.0, 2000000.0, 0.0, 0.0);
  if !robo_close(big2.x, 1003000000.0) { ok = false; }
  if !robo_close(big2.y, -1000000000.0) { ok = false; }
  if !robo_close(robot_end_distance(3000000.0, 4000000.0, 1.5707963267948966), 5000000.0) { ok = false; }
  let small = robot_fk2(0.000001, 0.000002, 0.0, 0.0);
  if !robo_close(small.x, 0.000003) { ok = false; }
  if !robo_close(robot_end_distance(0.000003, 0.000004, 1.5707963267948966), 0.000005) { ok = false; }
  if robot_diff_drive_omega_mrad_s(0, 1000000, 1000) != 1000000 { ok = false; }
  if robot_diff_drive_v_mm_s(1000000, -1000000) != 0 { ok = false; }
  return assert(ok, "large and small magnitudes: mm/s truncation and Float64 pins");
}

fn main() -> Int {
  io.println("=== xiom.robotics conformance tests ===");
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
    io.println("xiom.robotics: all tests passed");
  } else {
    io.println("xiom.robotics: tests failed");
  }
  return failed;
}
