// XIOM -- xiom.control Conformance Tests
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Tests: LowPassFilter, MovingAverage, KalmanFilter1D, PIDController,
//        Trajectory/Waypoint, StateMachine -- all 24 public functions
module control_tests
use xiom.io;
use xiom.test;
use xiom.control.filter;
use xiom.control.pid;
use xiom.control.trajectory;
use xiom.control.state_machine;

const EPSILON: Float64 = 1.0e-9;

fn float_eq(a: Float64, b: Float64) -> Bool {
  var d = a - b;
  if d < 0.0 { d = -d; }
  return d < EPSILON;
}

fn float_gt(a: Float64, b: Float64) -> Bool {
  return (a - b) > EPSILON;
}

fn int_to_str(n: Int) -> Str {
  if n == 0 { return "0"; }
  var num = n; var out = "";
  while num > 0 {
    let d = num % 10; var ds = "0";
    if d == 1 { ds = "1"; } elif d == 2 { ds = "2"; } elif d == 3 { ds = "3"; }
    elif d == 4 { ds = "4"; } elif d == 5 { ds = "5"; } elif d == 6 { ds = "6"; }
    elif d == 7 { ds = "7"; } elif d == 8 { ds = "8"; } elif d == 9 { ds = "9"; }
    out = ds + out; num = num / 10;
  }
  return out;
}

fn report(passed: Bool, name: Str) -> Int {
  if passed { io.println("  [PASS] " + name); return 0; }
  io.println("  [FAIL] " + name); return 1;
}

// ================================================================
// LowPassFilter tests
// ================================================================

fn test_lpf_new_valid() -> TestResult {
  var f = lpf_new(10.0, 100.0);
  var alpha_ok = f.alpha > 0.0 && f.alpha < 1.0;
  return assert(alpha_ok && !f.initialized, "filter: lpf_new alpha in (0,1), not initialized");
}

fn test_lpf_compute_first_sample() -> TestResult {
  var f = lpf_new(10.0, 100.0);
  var out = lpf_compute(&mut f, 5.0);
  var pass = float_eq(out, 5.0) && f.initialized;
  return assert(pass, "filter: lpf_compute first sample passes through");
}

fn test_lpf_compute_filtering() -> TestResult {
  var f = lpf_new(1.0, 100.0);
  lpf_compute(&mut f, 0.0);
  lpf_compute(&mut f, 1.0);
  var out = lpf_compute(&mut f, 1.0);
  return assert(out > 0.0 && out < 1.0, "filter: lpf_compute attenuates high frequencies");
}

fn test_lpf_reset() -> TestResult {
  var f = lpf_new(10.0, 100.0);
  lpf_compute(&mut f, 5.0);
  lpf_reset(&mut f);
  var pass = float_eq(f.prev_output, 0.0) && !f.initialized;
  return assert(pass, "filter: lpf_reset clears output and initialized flag");
}

// ================================================================
// MovingAverage tests
// ================================================================

fn test_ma_new_valid() -> TestResult {
  var ma = ma_new(5);
  return assert(ma.window_size == 5 && ma.count == 0, "filter: ma_new window_size=5, count=0");
}

fn test_ma_compute_partial() -> TestResult {
  var ma = ma_new(3);
  ma_compute(&mut ma, 1.0);
  ma_compute(&mut ma, 3.0);
  var out = ma_compute(&mut ma, 5.0);
  return assert(float_eq(out, 3.0), "filter: ma_compute (1+3+5)/3 = 3.0");
}

fn test_ma_compute_sliding() -> TestResult {
  var ma = ma_new(2);
  ma_compute(&mut ma, 0.0);
  ma_compute(&mut ma, 10.0);
  var out = ma_compute(&mut ma, 2.0);
  return assert(float_eq(out, 6.0), "filter: ma_compute sliding (10+2)/2 = 6.0");
}

// ================================================================
// KalmanFilter1D tests
// ================================================================

fn test_kalman_new_valid() -> TestResult {
  var kf = kalman_new(0.01, 0.1);
  var pass = float_eq(kf.q, 0.01) && float_eq(kf.r, 0.1) && float_eq(kf.p, 1.0) && !kf.initialized;
  return assert(pass, "filter: kalman_new q=0.01, r=0.1, p=1.0, not initialized");
}

fn test_kalman_compute_filtering() -> TestResult {
  var kf = kalman_new(0.01, 0.1);
  var init = kalman_compute(&mut kf, 0.0);
  var ok_init = float_eq(init, 0.0) && kf.initialized;
  var out1 = kalman_compute(&mut kf, 1.0);
  var out2 = kalman_compute(&mut kf, 1.0);
  var out3 = kalman_compute(&mut kf, 1.0);
  var converging = out3 > out1 && out3 < 1.0;
  return assert(ok_init && converging, "filter: kalman_compute converges toward measurements");
}

// ================================================================
// PIDController tests
// ================================================================

fn test_pid_new_valid() -> TestResult {
  var ctrl = pid_new(1.0, 0.1, 0.05);
  var ok_gains = float_eq(ctrl.kp, 1.0) && float_eq(ctrl.ki, 0.1) && float_eq(ctrl.kd, 0.05);
  var ok_defaults = float_eq(ctrl.setpoint, 0.0) && float_eq(ctrl.integral, 0.0)
    && float_eq(ctrl.integral_limit, 1000.0);
  return assert(ok_gains && ok_defaults, "pid: pid_new stores gains, default limits");
}

fn test_pid_set_limits() -> TestResult {
  var ctrl = pid_new(1.0, 0.0, 0.0);
  pid_set_limits(&mut ctrl, -5.0, 5.0);
  return assert(ctrl.output_min == -5.0 && ctrl.output_max == 5.0,
    "pid: pid_set_limits sets output_min/max");
}

fn test_pid_set_integral_limit() -> TestResult {
  var ctrl = pid_new(1.0, 0.0, 0.0);
  pid_set_integral_limit(&mut ctrl, 50.0);
  return assert(float_eq(ctrl.integral_limit, 50.0),
    "pid: pid_set_integral_limit sets integral_limit=50");
}

fn test_pid_set_setpoint() -> TestResult {
  var ctrl = pid_new(1.0, 0.0, 0.0);
  pid_set_setpoint(&mut ctrl, 42.0);
  return assert(float_eq(ctrl.setpoint, 42.0),
    "pid: pid_set_setpoint sets setpoint=42");
}

fn test_pid_compute_proportional() -> TestResult {
  var ctrl = pid_new(2.0, 0.0, 0.0);
  pid_set_setpoint(&mut ctrl, 10.0);
  var out = pid_compute(&mut ctrl, 5.0, 0.1);
  return assert(float_eq(out, 10.0), "pid: pid_compute P-only kp=2, error=5 => 10.0");
}

fn test_pid_integral_windup() -> TestResult {
  var ctrl = pid_new(1.0, 1.0, 0.0);
  pid_set_integral_limit(&mut ctrl, 2.0);
  pid_set_setpoint(&mut ctrl, 100.0);
  var i = 0;
  while i < 100 {
    pid_compute(&mut ctrl, 0.0, 1.0);
    i = i + 1;
  }
  var integral_clamped = ctrl.integral <= ctrl.integral_limit
    && ctrl.integral >= -ctrl.integral_limit;
  return assert(integral_clamped, "pid: integral clamped by integral_limit");
}

fn test_pid_reset() -> TestResult {
  var ctrl = pid_new(1.0, 0.5, 0.1);
  pid_set_setpoint(&mut ctrl, 10.0);
  pid_compute(&mut ctrl, 0.0, 0.1);
  pid_reset(&mut ctrl);
  return assert(float_eq(ctrl.integral, 0.0) && float_eq(ctrl.prev_error, 0.0),
    "pid: pid_reset clears integral and prev_error");
}

fn test_pid_get_error() -> TestResult {
  var ctrl = pid_new(1.0, 0.0, 0.0);
  pid_set_setpoint(&mut ctrl, 10.0);
  pid_compute(&mut ctrl, 7.0, 0.1);
  var err = pid_get_error(&ctrl);
  return assert(float_eq(err, 7.0),
    "pid: pid_get_error setpoint=10, last_meas=7 => 7.0");
}

// ================================================================
// Trajectory / Waypoint tests
// ================================================================

fn test_trajectory_new_empty() -> TestResult {
  var traj = trajectory_new();
  var empty = float_eq(traj.duration, 0.0);
  return assert(empty, "trajectory: trajectory_new duration=0");
}

fn test_trajectory_add_waypoint() -> TestResult {
  var traj = trajectory_new();
  var wp1 = Waypoint{ x: 0.0, y: 0.0, z: 0.0, time: 0.0 };
  var wp2 = Waypoint{ x: 10.0, y: 5.0, z: 2.0, time: 3.5 };
  trajectory_add_waypoint(&mut traj, wp1);
  trajectory_add_waypoint(&mut traj, wp2);
  var dur_ok = float_eq(trajectory_duration(&traj), 3.5);
  return assert(dur_ok, "trajectory: add_waypoint + duration = 3.5");
}

fn test_trajectory_interpolate_empty() -> TestResult {
  var traj = trajectory_new();
  var (x, y, z) = trajectory_interpolate(&traj, 1.0);
  return assert(float_eq(x, 0.0) && float_eq(y, 0.0) && float_eq(z, 0.0),
    "trajectory: interpolate empty => (0,0,0)");
}

fn test_trajectory_interpolate() -> TestResult {
  var traj = trajectory_new();
  var wp1 = Waypoint{ x: 0.0, y: 0.0, z: 0.0, time: 0.0 };
  var wp2 = Waypoint{ x: 10.0, y: 20.0, z: 30.0, time: 2.0 };
  trajectory_add_waypoint(&mut traj, wp1);
  trajectory_add_waypoint(&mut traj, wp2);
  var (x, y, z) = trajectory_interpolate(&traj, 1.0);
  return assert(float_eq(x, 5.0) && float_eq(y, 10.0) && float_eq(z, 15.0),
    "trajectory: interpolate t=1.0 => (5,10,15) midpoint");
}

fn test_trajectory_interpolate_boundary() -> TestResult {
  var traj = trajectory_new();
  var wp1 = Waypoint{ x: 1.0, y: 2.0, z: 3.0, time: 1.0 };
  var wp2 = Waypoint{ x: 4.0, y: 5.0, z: 6.0, time: 4.0 };
  trajectory_add_waypoint(&mut traj, wp1);
  trajectory_add_waypoint(&mut traj, wp2);
  var (x_before, y_before, z_before) = trajectory_interpolate(&traj, 0.0);
  var clip_start = float_eq(x_before, 1.0) && float_eq(y_before, 2.0);
  var (x_after, y_after, z_after) = trajectory_interpolate(&traj, 5.0);
  var clip_end = float_eq(x_after, 4.0) && float_eq(y_after, 5.0);
  return assert(clip_start && clip_end,
    "trajectory: interpolate clamps before-first and after-last waypoint");
}

// ================================================================
// StateMachine tests
// ================================================================

fn test_sm_new_empty() -> TestResult {
  var sm = sm_new();
  return assert(sm.current == 0, "statemachine: sm_new current=0");
}

fn test_sm_add_state() -> TestResult {
  var sm = sm_new();
  var idle_id = sm_add_state(&mut sm, "Idle");
  var run_id = sm_add_state(&mut sm, "Running");
  var stop_id = sm_add_state(&mut sm, "Stopped");
  return assert(idle_id == 0 && run_id == 1 && stop_id == 2,
    "statemachine: sm_add_state returns sequential IDs 0,1,2");
}

fn test_sm_add_transition_and_can() -> TestResult {
  var sm = sm_new();
  sm_add_state(&mut sm, "Idle");
  sm_add_state(&mut sm, "Running");
  sm_add_transition(&mut sm, 0, 1, 100);
  var can_ok = sm_can_transition(&sm, 100);
  var can_fail = sm_can_transition(&sm, 200);
  return assert(can_ok && !can_fail,
    "statemachine: can_transition matches from+condition, rejects unknown");
}

fn test_sm_transition_valid() -> TestResult {
  var sm = sm_new();
  sm_add_state(&mut sm, "Idle");
  sm_add_state(&mut sm, "Running");
  sm_add_transition(&mut sm, 0, 1, 100);
  var ok = sm_transition(&mut sm, 100);
  return assert(ok && sm_current(&sm) == 1,
    "statemachine: sm_transition Idle->Running succeeds, current=1");
}

fn test_sm_transition_invalid() -> TestResult {
  var sm = sm_new();
  sm_add_state(&mut sm, "Idle");
  sm_add_state(&mut sm, "Running");
  sm_add_transition(&mut sm, 0, 1, 100);
  var ok = sm_transition(&mut sm, 999);
  return assert(!ok && sm_current(&sm) == 0,
    "statemachine: sm_transition invalid condition rejected, current stays 0");
}

// ================================================================
// Main
// ================================================================

fn main() -> Int {
  io.println("=== XIOM Control Conformance Tests ===");
  var failed: Int = 0; var total: Int = 0;

  var tests = [
    test_lpf_new_valid,
    test_lpf_compute_first_sample,
    test_lpf_compute_filtering,
    test_lpf_reset,
    test_ma_new_valid,
    test_ma_compute_partial,
    test_ma_compute_sliding,
    test_kalman_new_valid,
    test_kalman_compute_filtering,
    test_pid_new_valid,
    test_pid_set_limits,
    test_pid_set_integral_limit,
    test_pid_set_setpoint,
    test_pid_compute_proportional,
    test_pid_integral_windup,
    test_pid_reset,
    test_pid_get_error,
    test_trajectory_new_empty,
    test_trajectory_add_waypoint,
    test_trajectory_interpolate_empty,
    test_trajectory_interpolate,
    test_trajectory_interpolate_boundary,
    test_sm_new_empty,
    test_sm_add_state,
    test_sm_add_transition_and_can,
    test_sm_transition_valid,
    test_sm_transition_invalid,
  ];

  var i = 0;
  while i < tests.len() {
    total = total + 1;
    failed = failed + report(tests[i]().passed, tests[i]().name);
    i = i + 1;
  }

  let passed = total - failed;
  io.println("");
  io.println("XIOM Control Conformance: " + int_to_str(passed) +
             "/" + int_to_str(total) + " passed" +
             (if failed > 0 { " (" + int_to_str(failed) + " FAILED)" } else { "" }));
  return failed;
}
