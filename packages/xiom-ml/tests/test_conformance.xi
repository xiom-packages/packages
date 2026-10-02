// XIOM -- xiom.ml conformance tests (20 deterministic checks)
// Port task: prove the pure-XIOM xiom.ml module against its documented
// fixed-point contract (scaled integers only, no floats, no FFI, no I/O in
// the library). No external files are read.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module ml_tests
use xiom.io; use xiom.test; use xiom.ml;
use xiom.string; use xiom.string.compare;

// All Str equality goes through str_compare (BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison).
fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// ---------------------------------------------------------------------------
// Fixtures / extractors
// ---------------------------------------------------------------------------

fn v4(a: Int, b: Int, c: Int, d: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  return v;
}

fn v1(a: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  return v;
}

fn v2(a: Int, b: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  return v;
}

fn v3(a: Int, b: Int, c: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  return v;
}

fn eq_vec(a: &Vec[Int], b: &Vec[Int]) -> Bool {
  if a.len() != b.len() {
    return false;
  }
  var i = 0;
  while i < a.len() {
    let x: Int = a[i];
    let y: Int = b[i];
    if x != y {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn lm_of(r: Result[LinearModel, Str]) -> LinearModel {
  match r {
    Ok(v) => { return v; },
    Err(_) => { return LinearModel{ n: -1; slope_scaled: 0; intercept_scaled: 0; sse: 0; r2_bps: 0; }; },
  }
  return LinearModel{ n: -1; slope_scaled: 0; intercept_scaled: 0; sse: 0; r2_bps: 0; };
}

fn mc_of(r: Result[MCMCResult, Str]) -> MCMCResult {
  match r {
    Ok(v) => { return v; },
    Err(_) => { return MCMCResult{ counts: Vec[Int].new(); n_states: -1; steps: -1; accepted: -1; mean_bps: 0; map_state: -1; }; },
  }
  return MCMCResult{ counts: Vec[Int].new(); n_states: -1; steps: -1; accepted: -1; mean_bps: 0; map_state: -1; };
}

fn be_of(r: Result[BetaPosterior, Str]) -> BetaPosterior {
  match r {
    Ok(v) => { return v; },
    Err(_) => { return BetaPosterior{ alpha: -1; beta: -1; mean_bps: 0; mode_bps: 0; lower_bps: 0; upper_bps: 0; }; },
  }
  return BetaPosterior{ alpha: -1; beta: -1; mean_bps: 0; mode_bps: 0; lower_bps: 0; upper_bps: 0; };
}

fn ks_of(r: Result[KalmanState, Str]) -> KalmanState {
  match r {
    Ok(v) => { return v; },
    Err(_) => { return KalmanState{ x: -999999; p: -999999 }; },
  }
  return KalmanState{ x: -999999; p: -999999 };
}

fn lm_err(r: Result[LinearModel, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn mc_err(r: Result[MCMCResult, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn be_err(r: Result[BetaPosterior, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn ks_err(r: Result[KalmanState, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

fn t1() -> TestResult {
  var ok = ml_scale() == 1000;
  if ml_bps() != 10000 { ok = false; }
  if ml_lcg_multiplier() != 48271 { ok = false; }
  if ml_lcg_modulus() != 2147483647 { ok = false; }
  if ml_lcg_step(1) != 48271 { ok = false; }
  if ml_lcg_seed(0) != 1 { ok = false; }
  if ml_lcg_seed(-5) != 6 { ok = false; }
  if ml_lcg_seed(2147483647) != 2 { ok = false; }
  return assert(ok, "scale, bps and pinned LCG surface");
}

fn t2() -> TestResult {
  let x = v4(0, 1000, 2000, 3000);
  let y = v4(1000, 3000, 5000, 7000);
  let m = lm_of(ml_linear_regression(&x, &y));
  var ok = ml_model_n(&m) == 4;
  if ml_model_slope_scaled(&m) != 2000 { ok = false; }
  if ml_model_intercept_scaled(&m) != 1000 { ok = false; }
  if ml_model_sse(&m) != 0 { ok = false; }
  if ml_model_r2_bps(&m) != 10000 { ok = false; }
  if ml_model_predict(&m, 2500) != 6000 { ok = false; }
  if ml_model_predict(&m, 0) != 1000 { ok = false; }
  return assert(ok, "exact line y=2x+1 fits with R2=10000");
}

fn t3() -> TestResult {
  let x = v4(0, 1000, 2000, 3000);
  let y = v4(1000, 3000, 5000, 7000);
  let m = lm_of(ml_ridge_regression(&x, &y, 20000000));
  var ok = ml_model_slope_scaled(&m) == 1000;
  if ml_model_intercept_scaled(&m) != 2500 { ok = false; }
  if ml_model_sse(&m) != 5000000 { ok = false; }
  if ml_model_r2_bps(&m) != 7500 { ok = false; }
  return assert(ok, "ridge lambda shrinks the slope and lowers R2");
}

fn t4() -> TestResult {
  let x4 = v4(0, 1000, 2000, 3000);
  let y3 = v4(1000, 3000, 5000, 7000);
  var ok = lm_err(ml_linear_regression(&x4, &v3(1, 2, 3)), "ml: regression vectors must have equal length");
  if !lm_err(ml_linear_regression(&v1(1), &v1(1)), "ml: regression needs at least two samples") { ok = false; }
  if !lm_err(ml_linear_regression(&v2(1000, 1000), &v2(1000, 2000)), "ml: regression is degenerate") { ok = false; }
  if !lm_err(ml_linear_regression(&v2(20000, 1), &v2(1, 2)), "ml: regression input out of range") { ok = false; }
  return assert(ok, "regression rejects mismatch, tiny n, degenerate and out-of-range");
}

fn t5() -> TestResult {
  let x = v2(1000, 1000);
  let y = v2(1000, 2000);
  let m = lm_of(ml_ridge_regression(&x, &y, 1000));
  var ok = ml_model_slope_scaled(&m) == 0;
  if ml_model_intercept_scaled(&m) != 1500 { ok = false; }
  if !lm_err(ml_ridge_regression(&x, &y, -1), "ml: ridge lambda must be non-negative") { ok = false; }
  return assert(ok, "ridge rescues a degenerate fit; lambda guarded");
}

fn t6() -> TestResult {
  let w = v2(1, 100);
  let r = mc_of(ml_mcmc_sample(&w, 7, 2000));
  var ok = ml_mcmc_n_states(&r) == 2;
  if ml_mcmc_steps(&r) != 2000 { ok = false; }
  if ml_mcmc_accepted(&r) < 0 { ok = false; }
  if ml_mcmc_accepted(&r) > 2000 { ok = false; }
  let c0 = ml_mcmc_count(&r, 0);
  let c1 = ml_mcmc_count(&r, 1);
  if c0 + c1 != 2000 { ok = false; }
  if ml_mcmc_map_state(&r) != 1 { ok = false; }
  if ml_mcmc_mean_bps(&r) < 5000 { ok = false; }
  if ml_mcmc_count(&r, 5) != 0 { ok = false; }
  return assert(ok, "mcmc explores a peaked 2-state target toward state 1");
}

fn t7() -> TestResult {
  let w = v4(1, 2, 4, 8);
  let a = mc_of(ml_mcmc_sample(&w, 42, 1500));
  let b = mc_of(ml_mcmc_sample(&w, 42, 1500));
  var ok = a.steps == b.steps;
  if a.accepted != b.accepted { ok = false; }
  if !eq_vec(&a.counts, &b.counts) { ok = false; }
  let c = mc_of(ml_mcmc_sample(&w, 43, 1500));
  var same = eq_vec(&a.counts, &c.counts);
  if same { ok = false; }
  return assert(ok, "mcmc is reproducible for a fixed seed and varies with another");
}

fn t8() -> TestResult {
  let w = v2(1, 1);
  var ok = mc_err(ml_mcmc_sample(&Vec[Int].new(), 1, 10), "ml: mcmc needs at least one state");
  if !mc_err(ml_mcmc_sample(&v2(0, 1), 1, 10), "ml: mcmc weights must be positive") { ok = false; }
  if !mc_err(ml_mcmc_sample(&w, 1, 0), "ml: mcmc step count must be positive") { ok = false; }
  if !mc_err(ml_mcmc_sample(&w, 1, 200000), "ml: mcmc step count too large") { ok = false; }
  return assert(ok, "mcmc input validation");
}

fn t9() -> TestResult {
  let w = v2(1, 1);
  let r = mc_of(ml_mcmc_sample(&w, 5, 500));
  var ok = ml_mcmc_mean_bps(&r) >= 0;
  if ml_mcmc_mean_bps(&r) > 10000 { ok = false; }
  let ms = ml_mcmc_map_state(&r);
  if ms != 0 { if ms != 1 { ok = false; } }
  if ml_mcmc_count(&r, 0) + ml_mcmc_count(&r, 1) != 500 { ok = false; }
  return assert(ok, "mcmc invariants hold on a uniform 2-state target");
}

fn t10() -> TestResult {
  let p = be_of(ml_beta_binomial(1, 1, 3, 1, 196));
  var ok = ml_beta_alpha(&p) == 4;
  if ml_beta_beta(&p) != 2 { ok = false; }
  if ml_beta_mean_bps(&p) != 6667 { ok = false; }
  if ml_beta_mode_bps(&p) != 7500 { ok = false; }
  return assert(ok, "beta-binomial posterior mean and mode in bps");
}

fn t11() -> TestResult {
  let p = be_of(ml_beta_binomial(1, 1, 3, 1, 196));
  var ok = ml_beta_lower_bps(&p) == 3176;
  if ml_beta_upper_bps(&p) != 10000 { ok = false; }
  return assert(ok, "beta-binomial 95% normal-approximation interval (clamped)");
}

fn t12() -> TestResult {
  let point = be_of(ml_beta_binomial(1, 1, 3, 1, 0));
  var ok = ml_beta_lower_bps(&point) == 6667;
  if ml_beta_upper_bps(&point) != 6667 { ok = false; }
  let flat = be_of(ml_beta_binomial(1, 1, 0, 0, 196));
  if ml_beta_mean_bps(&flat) != 5000 { ok = false; }
  if ml_beta_mode_bps(&flat) != 5000 { ok = false; }
  if ml_beta_lower_bps(&flat) != 0 { ok = false; }
  if ml_beta_upper_bps(&flat) != 10000 { ok = false; }
  return assert(ok, "point estimate equals mean; uniform prior is symmetric");
}

fn t13() -> TestResult {
  var ok = be_err(ml_beta_binomial(0, 1, 1, 1, 196), "ml: prior alpha must be positive");
  if !be_err(ml_beta_binomial(1, 0, 1, 1, 196), "ml: prior beta must be positive") { ok = false; }
  if !be_err(ml_beta_binomial(1, 1, -1, 1, 196), "ml: successes must be non-negative") { ok = false; }
  if !be_err(ml_beta_binomial(1, 1, 1, 1, -1), "ml: z-score must be non-negative") { ok = false; }
  if !be_err(ml_beta_binomial(1, 1, 200000, 0, 196), "ml: posterior total too large") { ok = false; }
  return assert(ok, "beta-binomial input validation");
}

fn t14() -> TestResult {
  let s0 = ml_kalman_init(0, 1000);
  var ok = ml_kalman_x(&s0) == 0;
  if ml_kalman_p(&s0) != 1000 { ok = false; }
  let s1 = ml_kalman_predict(&s0, 0);
  if ml_kalman_p(&s1) != 1000 { ok = false; }
  let s2 = ks_of(ml_kalman_update(&s1, 2000, 1000));
  if ml_kalman_x(&s2) != 1000 { ok = false; }
  if ml_kalman_p(&s2) != 500 { ok = false; }
  return assert(ok, "kalman predict then update moves x halfway to z");
}

fn t15() -> TestResult {
  let s = ml_kalman_init(0, 1000);
  let p = ml_kalman_predict(&s, 500);
  var ok = ml_kalman_p(&p) == 1500;
  let u = ks_of(ml_kalman_update(&p, 2000, 0));
  if ml_kalman_x(&u) != 2000 { ok = false; }
  if ml_kalman_p(&u) != 0 { ok = false; }
  if !ks_err(ml_kalman_update(&ml_kalman_init(0, 0), 1000, 0), "ml: kalman innovation variance must be positive") { ok = false; }
  return assert(ok, "kalman reaches a noise-free measurement and guards den<=0");
}

fn t16() -> TestResult {
  let x = v4(0, 1000, 2000, 3000);
  let yc = v4(5000, 5000, 5000, 5000);
  let m = lm_of(ml_linear_regression(&x, &yc));
  var ok = ml_model_slope_scaled(&m) == 0;
  if ml_model_intercept_scaled(&m) != 5000 { ok = false; }
  if ml_model_sse(&m) != 0 { ok = false; }
  if ml_model_r2_bps(&m) != 0 { ok = false; }
  return assert(ok, "constant target fits a flat line with R2 defined as 0");
}

fn t17() -> TestResult {
  let w = v2(3, 1);
  let r = mc_of(ml_mcmc_sample(&w, 100, 300));
  var ok = ml_mcmc_accepted(&r) > 0;
  if ml_mcmc_map_state(&r) != 0 { ok = false; }
  if ml_mcmc_mean_bps(&r) > 5000 { ok = false; }
  return assert(ok, "mcmc stays near the higher-weight state 0");
}

fn t18() -> TestResult {
  let x = v4(0, 1000, 2000, 3000);
  let y = v4(1000, 3000, 5000, 7000);
  let m = lm_of(ml_linear_regression(&x, &y));
  var ok = ml_model_predict(&m, -1000) == 0 - 1000;
  if ml_model_predict(&m, 10000) != 21000 { ok = false; }
  return assert(ok, "model predict extrapolates on both sides");
}

fn run(name: Str, t: TestResult, failed: Int) -> Int {
  if t.passed {
    io.println("  [PASS] " + name + ": " + t.name);
    return failed;
  }
  io.println("  [FAIL] " + name + ": " + t.name);
  return failed + 1;
}

fn main() -> Int {
  io.println("=== xiom.ml conformance tests ===");
  var failed: Int = 0;
  failed = run("t1", t1(), failed);
  failed = run("t2", t2(), failed);
  failed = run("t3", t3(), failed);
  failed = run("t4", t4(), failed);
  failed = run("t5", t5(), failed);
  failed = run("t6", t6(), failed);
  failed = run("t7", t7(), failed);
  failed = run("t8", t8(), failed);
  failed = run("t9", t9(), failed);
  failed = run("t10", t10(), failed);
  failed = run("t11", t11(), failed);
  failed = run("t12", t12(), failed);
  failed = run("t13", t13(), failed);
  failed = run("t14", t14(), failed);
  failed = run("t15", t15(), failed);
  failed = run("t16", t16(), failed);
  failed = run("t17", t17(), failed);
  failed = run("t18", t18(), failed);
  if failed == 0 {
    io.println("xiom.ml: all tests passed");
  } else {
    io.println("xiom.ml: tests failed");
  }
  return failed;
}
