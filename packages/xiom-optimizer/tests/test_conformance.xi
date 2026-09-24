// XIOM -- xiom.optimizer conformance tests (24 checks)
// Port task: prove the pure-XIOM xiom.optimizer engine against its SPEC.md.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Coverage: linspace semantics, grid search (ties, steps, degenerate
// inputs), hill climbing (unimodal convergence, step halving, max_steps
// bound, non-worsening), random restarts (determinism, quality, edges),
// simulated annealing (determinism, bounds, temperature decay, temperature
// clamping, start clamping) and opt_bounds_ok.
//
// Every objective is a NAMED top-level function (`fn(&Int) -> Int`): the
// compiler's function-pointer codegen rejects inline lambdas. Each check
// lives in its own small function and main only sequences them -- on
// compiler 0.61.3 a single very large function over many distinct
// function-pointer call sites miscompiles (observed access violation), so
// the suite never inlines the checks into main.

module optimizer_tests
use xiom.io; use xiom.test; use xiom.optimizer;

// --- helpers ---------------------------------------------------------------

fn test_abs(v: Int) -> Int {
  if v < 0 { return 0 - v; }
  return v;
}

fn same_ints(a: &Vec[Int], b: &Vec[Int]) -> Bool {
  if a.len() != b.len() { return false; }
  var i = 0;
  while i < a.len() {
    let av: Int = a[i];
    let bv: Int = b[i];
    if av != bv { return false; }
    i = i + 1;
  }
  return true;
}

// --- named objectives ------------------------------------------------------

fn neg_abs(x: &Int) -> Int {
  if *x < 0 { return *x; }
  return 0 - *x;
}

fn quadratic(x: &Int) -> Int {
  let d = *x - 3;
  return 1000 - d * d;
}

fn peak_7(x: &Int) -> Int {
  let d = *x - 7;
  return 1000 - d * d;
}

fn peak_10(x: &Int) -> Int {
  let d = *x - 10;
  return 1000 - d * d;
}

fn twin_peaks(x: &Int) -> Int {
  let a = test_abs(*x - 2);
  let b = test_abs(*x - 6);
  if a < b { return 100 - a; }
  return 100 - b;
}

fn linear(x: &Int) -> Int {
  return *x;
}

fn well_two(x: &Int) -> Int {
  let ax = test_abs(*x);
  if ax <= 1 { return 100; }
  if ax <= 12 { return 50 - 50 * (ax - 2); }
  if ax <= 32 { return 100 + 20 * (ax - 12); }
  return 500;
}

fn neg_quad_137(x: &Int) -> Int {
  let d = *x - 137;
  return 0 - d * d;
}

// --- linspace ---------------------------------------------------------------

fn t1() -> TestResult {
  let pts = opt_linspace_int(0, 10, 3);
  var ok = pts.len() == 3;
  let a: Int = pts[0];
  let b: Int = pts[1];
  let c: Int = pts[2];
  if a != 0 { ok = false; }
  if b != 5 { ok = false; }
  if c != 10 { ok = false; }
  return assert(ok, "linspace 0..10 n=3 is [0,5,10] with both endpoints");
}

fn t2() -> TestResult {
  let single = opt_linspace_int(7, 20, 1);
  var ok = single.len() == 1;
  if single.len() == 1 {
    let v: Int = single[0];
    if v != 7 { ok = false; }
  }
  let zero = opt_linspace_int(0, 10, 0);
  let neg = opt_linspace_int(0, 10, -3);
  if zero.len() != 0 { ok = false; }
  if neg.len() != 0 { ok = false; }
  return assert(ok, "linspace n=1 pins lo; n<1 is empty");
}

fn t3() -> TestResult {
  let a = opt_linspace_int(10, 0, 3);
  let b = opt_linspace_int(5, 4, 5);
  var ok = a.len() == 0;
  if b.len() != 0 { ok = false; }
  return assert(ok, "linspace hi < lo yields an empty vector");
}

fn t4() -> TestResult {
  let pts = opt_linspace_int(3, 3, 4);
  var ok = pts.len() == 4;
  var i = 0;
  while i < pts.len() {
    let v: Int = pts[i];
    if v != 3 { ok = false; }
    i = i + 1;
  }
  return assert(ok, "constant range repeats lo n times");
}

fn t5() -> TestResult {
  var expected = Vec[Int].new();
  expected.push(-5);
  expected.push(-3);
  expected.push(0);
  expected.push(2);
  expected.push(5);
  let pts = opt_linspace_int(-5, 5, 5);
  var ok = same_ints(&pts, &expected);
  let wide = opt_linspace_int(-7, 9, 6);
  if wide.len() != 6 { ok = false; }
  var prev: Int = -7;
  var i = 0;
  while i < wide.len() {
    let v: Int = wide[i];
    if v < prev { ok = false; }
    prev = v;
    i = i + 1;
  }
  return assert(ok, "linspace truncates toward lo and stays non-decreasing");
}

// --- grid search ------------------------------------------------------------

fn t6() -> TestResult {
  let best = opt_grid_best_int(0, 10, 1, quadratic);
  var ok = best == 3;
  if quadratic(&best) != 1000 { ok = false; }
  return assert(ok, "grid finds the unimodal quadratic peak at 3");
}

fn t7() -> TestResult {
  let a = opt_grid_best_int(0, 10, 3, quadratic);
  let b = opt_grid_best_int(0, 7, 3, neg_abs);
  let c = opt_grid_best_int(0, 1000, 7, neg_abs);
  var ok = a == 3;
  if b != 0 { ok = false; }
  if c != 0 { ok = false; }
  return assert(ok, "grid honours step size and a non-multiple hi");
}

fn t8() -> TestResult {
  let best = opt_grid_best_int(0, 8, 1, twin_peaks);
  var ok = best == 2;
  if twin_peaks(&best) != 100 { ok = false; }
  let other = 6;
  if twin_peaks(&other) != 100 { ok = false; }
  return assert(ok, "grid ties keep the smallest x");
}

fn t9() -> TestResult {
  let a = opt_grid_best_int(5, 100, 0, neg_abs);
  let b = opt_grid_best_int(5, 100, -3, neg_abs);
  let c = opt_grid_best_int(5, 0, 1, neg_abs);
  var ok = a == 5;
  if b != 5 { ok = false; }
  if c != 5 { ok = false; }
  return assert(ok, "grid returns lo for step < 1 or hi < lo");
}

// --- hill climbing ----------------------------------------------------------

fn t10() -> TestResult {
  let best = opt_hill_climb_int(0, 3, 10, peak_7);
  var ok = best == 7;
  if peak_7(&best) != 1000 { ok = false; }
  return assert(ok, "hill climb converges to the unimodal peak at 7");
}

fn t11() -> TestResult {
  let start = 6;
  let best = opt_hill_climb_int(6, 4, 10, peak_7);
  var ok = peak_7(&start) == 999;
  if best != 7 { ok = false; }
  if peak_7(&best) != 1000 { ok = false; }
  return assert(ok, "step halving escapes a stalled coarse step");
}

fn t12() -> TestResult {
  let two = opt_hill_climb_int(0, 4, 2, peak_10);
  let four = opt_hill_climb_int(0, 4, 4, peak_10);
  var ok = two == 8;
  if four != 10 { ok = false; }
  if peak_10(&two) != 996 { ok = false; }
  if peak_10(&four) != 1000 { ok = false; }
  return assert(ok, "max_steps bounds the walk: 8 after 2, 10 after 4");
}

fn t13() -> TestResult {
  let a = opt_hill_climb_int(42, 0, 100, peak_10);
  let b = opt_hill_climb_int(42, 3, 0, peak_10);
  let c = opt_hill_climb_int(42, 3, -5, peak_10);
  var ok = a == 42;
  if b != 42 { ok = false; }
  if c != 42 { ok = false; }
  return assert(ok, "hill climb returns start for step 0 or max_steps <= 0");
}

fn t14() -> TestResult {
  var ok = true;
  var start = -20;
  while start <= 20 {
    let before = start;
    let best = opt_hill_climb_int(start, 5, 20, peak_10);
    if peak_10(&best) < peak_10(&before) { ok = false; }
    start = start + 7;
  }
  return assert(ok, "hill climb never lowers the score");
}

// --- random restarts --------------------------------------------------------

fn t15() -> TestResult {
  let a = opt_random_restart_int(0, 1000, 8, 16, 2026, neg_quad_137);
  let b = opt_random_restart_int(0, 1000, 8, 16, 2026, neg_quad_137);
  var ok = a == b;
  if a != 137 { ok = false; }
  if neg_quad_137(&a) != 0 { ok = false; }
  return assert(ok, "random restarts are deterministic and reach the peak");
}

fn t16() -> TestResult {
  let best = opt_random_restart_int(0, 1000, 4, 32, 99, neg_quad_137);
  let more = opt_random_restart_int(0, 1000, 16, 24, 31337, neg_quad_137);
  var ok = best == 137;
  if more != 137 { ok = false; }
  let start = 0;
  if neg_quad_137(&best) <= neg_quad_137(&start) { ok = false; }
  return assert(ok, "random restarts improve on the start point");
}

fn t17() -> TestResult {
  let none = opt_random_restart_int(0, 1000, 0, 16, 2026, neg_quad_137);
  let neg = opt_random_restart_int(0, 1000, -2, 16, 2026, neg_quad_137);
  let empty = opt_random_restart_int(10, 0, 4, 16, 2026, neg_quad_137);
  var ok = none == 0;
  if neg != 0 { ok = false; }
  if empty != 10 { ok = false; }
  return assert(ok, "no restarts or an empty range return lo");
}

// --- simulated annealing ----------------------------------------------------

fn t18() -> TestResult {
  let a = opt_anneal_int(0, 0, 300, 400, 12345, 200, neg_quad_137);
  let b = opt_anneal_int(0, 0, 300, 400, 12345, 200, neg_quad_137);
  var ok = a == b;
  if a != 137 { ok = false; }
  if neg_quad_137(&a) != 0 { ok = false; }
  if !opt_bounds_ok(a, 0, 300) { ok = false; }
  return assert(ok, "annealing is deterministic and reaches the peak");
}

fn t19() -> TestResult {
  let best = opt_anneal_int(0, 0, 100, 300, 7, 1, linear);
  var ok = best == 100;
  if linear(&best) != 100 { ok = false; }
  if !opt_bounds_ok(best, 0, 100) { ok = false; }
  return assert(ok, "temp 1 accepts only improvements and climbs to hi");
}

fn t20() -> TestResult {
  let low = opt_anneal_int(0, -100, 100, 400, 20260924, 1, well_two);
  let high = opt_anneal_int(0, -100, 100, 400, 20260924, 100000, well_two);
  var ok = well_two(&low) == 100;
  if low != 0 { ok = false; }
  if well_two(&high) != 500 { ok = false; }
  if high != -37 { ok = false; }
  if low == high { ok = false; }
  if !opt_bounds_ok(high, -100, 100) { ok = false; }
  return assert(ok, "hot annealing escapes the local plateau, temp 1 stays");
}

fn t21() -> TestResult {
  let frozen = opt_anneal_int(0, -100, 100, 400, 20260924, 1, well_two);
  let neg = opt_anneal_int(0, -100, 100, 400, 20260924, -5, well_two);
  let zero = opt_anneal_int(0, -100, 100, 400, 20260924, 0, well_two);
  var ok = neg == frozen;
  if zero != frozen { ok = false; }
  if well_two(&neg) != 100 { ok = false; }
  return assert(ok, "temp_start below 1 clamps to a greedy temp of 1");
}

fn t22() -> TestResult {
  let clamped = opt_anneal_int(500, 0, 100, 0, 7, 10, well_two);
  let empty = opt_anneal_int(7, 10, 0, 50, 7, 10, well_two);
  var ok = clamped == 100;
  if empty != 7 { ok = false; }
  return assert(ok, "start clamps into bounds; empty range returns start");
}

fn t23() -> TestResult {
  let best = opt_anneal_int(500, 0, 100, 400, 4242, 100000, linear);
  var ok = opt_bounds_ok(best, 0, 100);
  if best != 100 { ok = false; }
  return assert(ok, "annealing respects bounds from an out-of-range start");
}

fn t24() -> TestResult {
  var ok = opt_bounds_ok(5, 0, 10);
  if !opt_bounds_ok(0, 0, 10) { ok = false; }
  if !opt_bounds_ok(10, 0, 10) { ok = false; }
  if !opt_bounds_ok(0, 0, 0) { ok = false; }
  if opt_bounds_ok(-1, 0, 10) { ok = false; }
  if opt_bounds_ok(11, 0, 10) { ok = false; }
  if opt_bounds_ok(5, 10, 0) { ok = false; }
  return assert(ok, "opt_bounds_ok is inclusive and rejects empty ranges");
}

fn main() -> Int {
  io.println("=== xiom.optimizer conformance tests ===");
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
    io.println("xiom.optimizer: all tests passed");
  } else {
    io.println("xiom.optimizer: tests failed");
  }
  return failed;
}
