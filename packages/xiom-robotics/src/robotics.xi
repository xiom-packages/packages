// XIOM -- xiom.robotics: planar robot helpers (2-link forward kinematics,
// reach checks, differential drive), pure XIOM, no FFI.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// The geometry functions take angles in radians and lengths in metres; the
// differential-drive helpers take integer millimetres and milliradians (see
// each signature). All scalar math is IEEE-754 Float64; the Int helpers use
// integer arithmetic and truncate toward zero.
//
// Guard rules (module-wide, documented per function below and pinned by
// tests/test_conformance.xi):
//   * G1 magnitudes: robot_end_distance folds negative link lengths to their
//     magnitudes with abs_float, so |l1| and |l2| are used.
//   * G2 reachability: robot_reach_ok returns false when any argument is
//     negative; there is no magnitude folding there.
//   * G3 normalization: robot_clamp_angle_rad folds a finite angle into
//     [-pi, pi] with a while loop over 2*pi (no modulo); inputs are expected
//     to be finite.
//   * G4 drive base: robot_diff_drive_omega_mrad_s returns 0 when
//     wheel_base_mm <= 0 (the division would otherwise be undefined).
//
// Nothing here panics; every function is total.

module xiom.robotics

use xiom.math;

/// A planar pose or end-effector point: x and y in metres, base frame at the
/// origin, +x to the right and +y up.
pub type RoboPose2 = { x: Float64; y: Float64; }

// --- Forward kinematics -----------------------------------------------------

/// Forward kinematics of a planar 2-link arm with its base at the origin.
/// Params: l1_m, l2_m - link lengths in metres; theta1_rad - absolute angle
/// of link 1 from the +x axis in radians; theta2_rad - relative angle of
/// link 2 from link 1 in radians.
/// Returns: the end-effector pose with x = l1*cos(t1) + l2*cos(t1+t2) and
/// y = l1*sin(t1) + l2*sin(t1+t2), in metres.
/// Errors: none (total; a zero-length link simply contributes nothing).
/// Complexity: O(1).
pub fn robot_fk2(l1_m: Float64, l2_m: Float64, theta1_rad: Float64, theta2_rad: Float64) -> RoboPose2 {
  let x: Float64 = l1_m * xiom.math.cos(theta1_rad) + l2_m * xiom.math.cos(theta1_rad + theta2_rad);
  let y: Float64 = l1_m * xiom.math.sin(theta1_rad) + l2_m * xiom.math.sin(theta1_rad + theta2_rad);
  return RoboPose2 { x: x, y: y };
}

/// Forward kinematics of a planar 2-link arm with a translated base.
/// Params: base_x, base_y - base position in metres; l1_m, l2_m - link
/// lengths in metres; theta1_rad - absolute angle of link 1 from the +x axis
/// in radians; theta2_rad - relative angle of link 2 from link 1 in radians.
/// Returns: robot_fk2(l1_m, l2_m, theta1_rad, theta2_rad) translated by
/// (base_x, base_y), in metres.
/// Errors: none (total).
/// Complexity: O(1).
pub fn robot_fk2_at(base_x: Float64, base_y: Float64, l1_m: Float64, l2_m: Float64, theta1_rad: Float64, theta2_rad: Float64) -> RoboPose2 {
  let x: Float64 = base_x + l1_m * xiom.math.cos(theta1_rad) + l2_m * xiom.math.cos(theta1_rad + theta2_rad);
  let y: Float64 = base_y + l1_m * xiom.math.sin(theta1_rad) + l2_m * xiom.math.sin(theta1_rad + theta2_rad);
  return RoboPose2 { x: x, y: y };
}

// --- Reach helpers ----------------------------------------------------------

/// Distance from the base to the end effector of a planar 2-link arm.
/// Params: l1_m, l2_m - link lengths in metres, used as magnitudes (negative
/// values are folded with abs_float, guard G1); theta2_rad - relative angle
/// of link 2 from link 1 in radians.
/// Returns: sqrt(l1^2 + l2^2 + 2*l1*l2*cos(theta2)) in metres, the law-of-
/// cosines distance; 0.0 when both links are zero.
/// Errors: none (total).
/// Complexity: O(1).
pub fn robot_end_distance(l1_m: Float64, l2_m: Float64, theta2_rad: Float64) -> Float64 {
  let a1: Float64 = xiom.math.abs_float(l1_m);
  let a2: Float64 = xiom.math.abs_float(l2_m);
  return xiom.math.sqrt(a1 * a1 + a2 * a2 + 2.0 * a1 * a2 * xiom.math.cos(theta2_rad));
}

/// Whether a target radius is reachable by a planar 2-link arm.
/// Params: l1_m, l2_m - link lengths in metres; r_m - target distance from
/// the base in metres.
/// Returns: true when |l1 - l2| <= r_m <= l1 + l2 (the arm's annulus of
/// reach, boundaries included); false when any argument is negative (guard
/// G2: negative lengths and radii are rejected rather than folded).
/// Errors: none (total).
/// Complexity: O(1).
pub fn robot_reach_ok(l1_m: Float64, l2_m: Float64, r_m: Float64) -> Bool {
  if l1_m < 0.0 { return false; }
  if l2_m < 0.0 { return false; }
  if r_m < 0.0 { return false; }
  if r_m < xiom.math.abs_float(l1_m - l2_m) { return false; }
  if r_m > l1_m + l2_m { return false; }
  return true;
}

// --- Angle helpers ----------------------------------------------------------

/// Normalize an angle into [-pi, pi].
/// Params: a - an angle in radians (expected finite).
/// Returns: a folded into the closed interval [-pi, pi] by repeatedly adding
/// or subtracting 2*pi in a while loop (guard G3: no modulo, no rounding;
/// +pi and -pi are kept as-is). The loop runs |a|/(2*pi) times rounded up,
/// so the cost grows with the magnitude of the input.
/// Errors: none for finite inputs; a non-finite input would not terminate.
/// Complexity: O(|a| / (2*pi)) time, O(1) memory.
pub fn robot_clamp_angle_rad(a: Float64) -> Float64 {
  let two_pi: Float64 = 2.0 * xiom.math.PI;
  var r: Float64 = a;
  while r > xiom.math.PI {
    r = r - two_pi;
  }
  while r < -xiom.math.PI {
    r = r + two_pi;
  }
  return r;
}

// --- Differential drive -----------------------------------------------------

/// Forward linear speed of a differential-drive robot.
/// Params: v_left_mm_s, v_right_mm_s - wheel surface speeds in mm/s.
/// Returns: (v_left + v_right) / 2 in mm/s, with integer division truncating
/// toward zero (so (-3 + 0) / 2 = -1). Wheel base is not needed.
/// Errors: none (total).
/// Complexity: O(1).
pub fn robot_diff_drive_v_mm_s(v_left_mm_s: Int, v_right_mm_s: Int) -> Int {
  return (v_left_mm_s + v_right_mm_s) / 2;
}

/// Yaw rate of a differential-drive robot.
/// Params: v_left_mm_s, v_right_mm_s - wheel surface speeds in mm/s;
/// wheel_base_mm - distance between the wheel contact points in mm.
/// Returns: (v_right - v_left) * 1000 / wheel_base_mm in milliradians per
/// second, with integer arithmetic truncating toward zero; 0 when
/// wheel_base_mm <= 0 (guard G4).
/// Errors: none (total).
/// Complexity: O(1).
pub fn robot_diff_drive_omega_mrad_s(v_left_mm_s: Int, v_right_mm_s: Int, wheel_base_mm: Int) -> Int {
  if wheel_base_mm <= 0 { return 0; }
  return (v_right_mm_s - v_left_mm_s) * 1000 / wheel_base_mm;
}

/// Inverse of the differential-drive model: wheel speeds for a commanded
/// linear speed and yaw rate.
/// Params: v_mm_s - forward speed in mm/s; omega_mrad_s - yaw rate in
/// milliradians per second; wheel_base_mm - wheel base in mm.
/// Returns: the (left, right) wheel surface speeds in mm/s with
/// delta = omega_mrad_s * wheel_base_mm / 2000 (integer division truncating
/// toward zero), left = v_mm_s - delta and right = v_mm_s + delta. For
/// moderate magnitudes this round-trips through robot_diff_drive_v_mm_s and
/// robot_diff_drive_omega_mrad_s up to the truncation of delta.
/// Errors: none (total); a non-positive wheel_base_mm simply makes both
/// results equal to v_mm_s (delta is 0 only when omega is 0; otherwise the
/// product is computed -- pass wheel_base_mm > 0 for a meaningful split).
/// Complexity: O(1).
pub fn robot_wheel_speeds_mm_s(v_mm_s: Int, omega_mrad_s: Int, wheel_base_mm: Int) -> (Int, Int) {
  let delta: Int = omega_mrad_s * wheel_base_mm / 2000;
  return (v_mm_s - delta, v_mm_s + delta);
}
