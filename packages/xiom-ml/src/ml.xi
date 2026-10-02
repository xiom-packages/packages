// XIOM -- xiom.ml: fixed-point statistical and Bayesian ML primitives
// Port task: replace the xiom.ml placeholder with a pure-XIOM module
// (scaled integers only: no floats, no FFI, no I/O, no Vec[Float64]).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model (pinned in SPEC.md, exercised by tests/test_conformance.xi):
//
//   - fixed-point SCALE = 1000: a real value v is stored as round(v * 1000).
//     Basis points (BPS) = 10000 are used for probabilities/ratios.
//   - regression: ordinary/ridge least squares on one feature with an
//     intercept, closed-form normal equations. slope_scaled = slope * 1000,
//     intercept_scaled = intercept * 1000. Ridge adds `lambda` to the
//     normal-equation denominator (units SCALE^2). R^2 is returned in BPS.
//   - mcmc: Metropolis-Hastings over a caller-supplied unnormalised integer
//     weight vector, driven by a pinned MINSTD (Park-Miller) LCG
//     (multiplier 48271, modulus 2^31 - 1). State is threaded through
//     return values exactly as the RNG state is (no &mut scalars).
//   - bayesian: Beta-Binomial conjugate update; posterior mean/mode in BPS
//     and an equal-tailed normal-approximation credible interval whose
//     half-width is z_bps * std_bps / 100 (z_bps = 196 for 95%).
//   - kalman: one-dimensional constant-state filter over scaled state x and
//     covariance p. predict adds process noise q; update applies the Kalman
//     gain k = p / (p + r) in scaled arithmetic.
//
// Layout notes that shaped this module (compiler v0.62.2):
//   * every Vec[Int] element read binds the value to a typed local; no Str
//     values are compared anywhere in this module (no BUG-17 exposure).
//   * struct payloads leaving a function do so only through Result leaf
//     helpers (_ok_* / _err_*) because Ok/Err inside a struct-returning
//     function miscompiles.
//   * free functions only: no methods, no generics, no callbacks, no
//     indexed function-table dispatch, no recursion.
//   * all loops are bounded by documented caps (sample count, MCMC steps,
//     Newton iterations in isqrt); no unbounded progress path exists.

module xiom.ml

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

// Fixed-point scale: 1000. A real value v is stored as round(v * 1000).
const _ML_SCALE: Int = 1000;
// Basis-point scale for probabilities and ratios: 10000.
const _ML_BPS: Int = 10000;
// Largest accepted sample count for a regression fit.
const _ML_MAX_N: Int = 1000;
// Largest accepted absolute component of a regression input (real +/-10).
const _ML_MAX_VAL: Int = 10000;
// Largest accepted MCMC step count.
const _ML_MAX_STEPS: Int = 100000;
// Largest accepted unnormalised MCMC weight.
const _ML_MAX_WEIGHT: Int = 1000000;
// Largest accepted Beta-Binomial posterior total (alpha + beta).
const _ML_MAX_POST: Int = 100000;
// MINSTD (Park-Miller) LCG: state = (state * 48271) mod (2^31 - 1).
const _ML_LCG_MULT: Int = 48271;
const _ML_LCG_MOD: Int = 2147483647;
const _ML_LCG_RANGE: Int = 2147483646;
// Floor(INT_MAX / 1000); guards a scaled multiply before division.
const _ML_SCALE_DIV_MAX: Int = 9223372036854775;

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

/// A fitted one-feature least-squares / ridge model.
///
/// `slope_scaled` and `intercept_scaled` are the real coefficients scaled by
/// 1000. `sse` is the residual sum of squares in scaled^2 units and
/// `r2_bps` the coefficient of determination in basis points (0 when the
/// target has no variance).
pub type LinearModel = {
  n: Int;
  slope_scaled: Int;
  intercept_scaled: Int;
  sse: Int;
  r2_bps: Int;
}

/// Metropolis-Hastings output over an integer state space.
///
/// `counts` has one entry per state and sums to `steps`; `accepted` counts
/// accepted proposals; `mean_bps` is round(10000 * sum_k k*counts[k] / steps)
/// and `map_state` is the most visited state (ties to the lowest index).
pub type MCMCResult = {
  counts: Vec[Int];
  n_states: Int;
  steps: Int;
  accepted: Int;
  mean_bps: Int;
  map_state: Int;
}

/// Beta-Binomial posterior summary.
///
/// Alpha/beta are the posterior shape counts; mean/mode and the credible
/// interval bounds are in basis points. The interval is the equal-tailed
/// normal approximation mean +/- z_bps * std_bps / 100, clamped to [0,10000].
pub type BetaPosterior = {
  alpha: Int;
  beta: Int;
  mean_bps: Int;
  mode_bps: Int;
  lower_bps: Int;
  upper_bps: Int;
}

/// One-dimensional Kalman state: `x` (state) and `p` (covariance), both
/// scaled by 1000.
pub type KalmanState = {
  x: Int;
  p: Int;
}

// ---------------------------------------------------------------------------
// Scale / RNG surface
// ---------------------------------------------------------------------------

/// Fixed-point scale of state-like quantities (1000). Complexity: O(1).
pub fn ml_scale() -> Int {
  return _ML_SCALE;
}

/// Basis-point scale of probabilities (10000). Complexity: O(1).
pub fn ml_bps() -> Int {
  return _ML_BPS;
}

/// Multiplier of the pinned MCMC LCG (48271). Complexity: O(1).
pub fn ml_lcg_multiplier() -> Int {
  return _ML_LCG_MULT;
}

/// Modulus of the pinned MCMC LCG (2147483647 = 2^31 - 1). Complexity: O(1).
pub fn ml_lcg_modulus() -> Int {
  return _ML_LCG_MOD;
}

/// Normalise any Int seed into [1, 2147483646]. Complexity: O(1).
pub fn ml_lcg_seed(seed: Int) -> Int {
  return _ml_lcg_norm(seed);
}

/// One LCG step: (state * 48271) mod (2^31 - 1). Complexity: O(1).
pub fn ml_lcg_step(state: Int) -> Int {
  return _ml_lcg_step(state);
}

// ---------------------------------------------------------------------------
// Regression
// ---------------------------------------------------------------------------

/// Ordinary least-squares fit of y on one feature x with an intercept.
///
/// Params: x / y - equal-length scaled vectors (SCALE=1000), 2..1000 samples,
///         each component in [-10000, 10000] (real +/-10).
/// Returns: Ok(LinearModel) with slope/intercept scaled by 1000, the residual
/// sum of squares and R^2 in basis points (0 when y has no variance).
/// Error case: Err("ml: ...") for a length mismatch, a sample-count or value
/// out of range, or a degenerate normal equation (all x equal).
/// Complexity: O(n).
pub fn ml_linear_regression(x: &Vec[Int], y: &Vec[Int]) -> Result[LinearModel, Str] {
  return _ml_fit(x, y, 0);
}

/// Ridge-regularised least-squares fit of y on one feature x.
///
/// Identical to ml_linear_regression with `lambda` added to the denominator
/// of the normal equation (units SCALE^2 = 1000000); `lambda` must be in
/// [0, 1000000000000]. A positive lambda makes an otherwise degenerate fit
/// well-posed. Complexity: O(n).
pub fn ml_ridge_regression(x: &Vec[Int], y: &Vec[Int], lambda: Int) -> Result[LinearModel, Str] {
  if lambda < 0 {
    return _err_lm("ml: ridge lambda must be non-negative");
  }
  if lambda > 1000000000000 {
    return _err_lm("ml: ridge lambda too large");
  }
  return _ml_fit(x, y, lambda);
}

fn _ml_fit(x: &Vec[Int], y: &Vec[Int], lambda: Int) -> Result[LinearModel, Str] {
  let n = x.len();
  if y.len() != n {
    return _err_lm("ml: regression vectors must have equal length");
  }
  if n < 2 {
    return _err_lm("ml: regression needs at least two samples");
  }
  if n > _ML_MAX_N {
    return _err_lm("ml: regression sample count too large");
  }
  var sx: Int = 0;
  var sy: Int = 0;
  var sxx: Int = 0;
  var sxy: Int = 0;
  var i = 0;
  while i < n {
    let xi: Int = x[i];
    let yi: Int = y[i];
    if xi > _ML_MAX_VAL {
      return _err_lm("ml: regression input out of range");
    }
    if xi < 0 - _ML_MAX_VAL {
      return _err_lm("ml: regression input out of range");
    }
    if yi > _ML_MAX_VAL {
      return _err_lm("ml: regression input out of range");
    }
    if yi < 0 - _ML_MAX_VAL {
      return _err_lm("ml: regression input out of range");
    }
    sx = sx + xi;
    sy = sy + yi;
    sxx = sxx + xi * xi;
    sxy = sxy + xi * yi;
    i = i + 1;
  }
  let num = n * sxy - sx * sy;
  let den = n * sxx - sx * sx + lambda;
  if den <= 0 {
    return _err_lm("ml: regression is degenerate");
  }
  if num > _ML_SCALE_DIV_MAX {
    return _err_lm("ml: regression scale overflows");
  }
  if num < 0 - _ML_SCALE_DIV_MAX {
    return _err_lm("ml: regression scale overflows");
  }
  let slope = _div_round(num * _ML_SCALE, den);
  let mean_y = _div_round(sy, n);
  let mean_x = _div_round(sx, n);
  let intercept = mean_y - _div_round(slope * mean_x, _ML_SCALE);
  var sse: Int = 0;
  var sst: Int = 0;
  i = 0;
  while i < n {
    let xi: Int = x[i];
    let yi: Int = y[i];
    let pred = intercept + _div_round(slope * xi, _ML_SCALE);
    let res = yi - pred;
    let dev = yi - mean_y;
    sse = sse + res * res;
    sst = sst + dev * dev;
    i = i + 1;
  }
  var r2: Int = 0;
  if sst > 0 {
    r2 = _div_round((sst - sse) * _ML_BPS, sst);
  }
  return _ok_lm(LinearModel{ n: n; slope_scaled: slope; intercept_scaled: intercept; sse: sse; r2_bps: r2; });
}

/// Number of samples in a fit. Complexity: O(1).
pub fn ml_model_n(m: &LinearModel) -> Int {
  return m.n;
}

/// Slope scaled by 1000. Complexity: O(1).
pub fn ml_model_slope_scaled(m: &LinearModel) -> Int {
  return m.slope_scaled;
}

/// Intercept scaled by 1000. Complexity: O(1).
pub fn ml_model_intercept_scaled(m: &LinearModel) -> Int {
  return m.intercept_scaled;
}

/// Residual sum of squares (scaled^2). Complexity: O(1).
pub fn ml_model_sse(m: &LinearModel) -> Int {
  return m.sse;
}

/// Coefficient of determination in basis points. Complexity: O(1).
pub fn ml_model_r2_bps(m: &LinearModel) -> Int {
  return m.r2_bps;
}

/// Predict the scaled response at scaled `x` from a fit. Complexity: O(1).
pub fn ml_model_predict(m: &LinearModel, x: Int) -> Int {
  return m.intercept_scaled + _div_round(m.slope_scaled * x, _ML_SCALE);
}

// ---------------------------------------------------------------------------
// MCMC
// ---------------------------------------------------------------------------

/// Metropolis-Hastings sampling over a discrete unnormalised target.
///
/// Params: weights - positive unnormalised weights (1..10000 states, each
///         <= 1000000); seed - any Int; steps - 1..100000.
/// Returns: Ok(MCMCResult). The chain starts at state 0; each step proposes
/// state-1 or state+1 (reflected at the ends) using the first LCG draw, then
/// accepts with probability min(1, w_prop / w_cur) using the second draw. The
/// same (weights, seed, steps) always yields the same result.
/// Error case: Err("ml: ...") for an empty/oversized weight vector, a
/// non-positive weight or one above the cap, or a step count out of range.
/// Complexity: O(steps + n).
pub fn ml_mcmc_sample(weights: &Vec[Int], seed: Int, steps: Int) -> Result[MCMCResult, Str] {
  let n = weights.len();
  if n <= 0 {
    return _err_mcmc("ml: mcmc needs at least one state");
  }
  if n > _ML_BPS {
    return _err_mcmc("ml: mcmc state count too large");
  }
  if steps <= 0 {
    return _err_mcmc("ml: mcmc step count must be positive");
  }
  if steps > _ML_MAX_STEPS {
    return _err_mcmc("ml: mcmc step count too large");
  }
  var v = 0;
  while v < n {
    let w: Int = weights[v];
    if w <= 0 {
      return _err_mcmc("ml: mcmc weights must be positive");
    }
    if w > _ML_MAX_WEIGHT {
      return _err_mcmc("ml: mcmc weight too large");
    }
    v = v + 1;
  }
  var counts = Vec[Int].new();
  v = 0;
  while v < n {
    counts.push(0);
    v = v + 1;
  }
  var state = _ml_lcg_norm(seed);
  var cur: Int = 0;
  var accepted: Int = 0;
  var s = 0;
  while s < steps {
    state = _ml_lcg_step(state);
    let u = state;
    var cand: Int = 0;
    if n > 1 {
      let dir = u % 2;
      if dir == 0 {
        cand = cur + 1;
        if cand >= n {
          cand = n - 2;
        }
      } else {
        cand = cur - 1;
        if cand < 0 {
          cand = 1;
        }
      }
    }
    state = _ml_lcg_step(state);
    let u2 = state;
    let wc: Int = weights[cur];
    let wp: Int = weights[cand];
    var accept = false;
    if wp >= wc {
      accept = true;
    } else {
      if u2 * wc < wp * _ML_LCG_MOD {
        accept = true;
      }
    }
    if accept {
      cur = cand;
      accepted = accepted + 1;
    }
    let c: Int = counts[cur];
    counts[cur] = c + 1;
    s = s + 1;
  }
  var weighted: Int = 0;
  var best: Int = 0;
  var bestc: Int = 0;
  v = 0;
  while v < n {
    let cv: Int = counts[v];
    weighted = weighted + v * cv;
    if cv > bestc {
      bestc = cv;
      best = v;
    }
    v = v + 1;
  }
  let mean_bps = _div_round(weighted * _ML_BPS, steps);
  return _ok_mcmc(MCMCResult{ counts: counts; n_states: n; steps: steps; accepted: accepted; mean_bps: mean_bps; map_state: best; });
}

/// Number of states. Complexity: O(1).
pub fn ml_mcmc_n_states(r: &MCMCResult) -> Int {
  return r.n_states;
}

/// Number of MCMC steps taken. Complexity: O(1).
pub fn ml_mcmc_steps(r: &MCMCResult) -> Int {
  return r.steps;
}

/// Number of accepted proposals. Complexity: O(1).
pub fn ml_mcmc_accepted(r: &MCMCResult) -> Int {
  return r.accepted;
}

/// Estimated mean state in basis points of the state index. Complexity: O(1).
pub fn ml_mcmc_mean_bps(r: &MCMCResult) -> Int {
  return r.mean_bps;
}

/// Most visited state (ties to the lowest index). Complexity: O(1).
pub fn ml_mcmc_map_state(r: &MCMCResult) -> Int {
  return r.map_state;
}

/// Visit count of state `i`, or 0 when out of range. Complexity: O(1).
pub fn ml_mcmc_count(r: &MCMCResult, i: Int) -> Int {
  if i < 0 {
    return 0;
  }
  if i >= r.counts.len() {
    return 0;
  }
  let c: Int = r.counts[i];
  return c;
}

// ---------------------------------------------------------------------------
// Bayesian inference
// ---------------------------------------------------------------------------

/// Beta-Binomial conjugate update.
///
/// Params: prior_alpha / prior_beta - positive prior pseudo-counts;
///         successes / failures - non-negative observed counts;
///         z_bps - z-score in basis points (196 for a 95% interval, 0 for a
///         point estimate).
/// Returns: Ok(BetaPosterior) with posterior alpha/beta, the mean and mode in
/// BPS, and the equal-tailed normal-approximation interval
/// mean +/- z_bps * std_bps / 100 clamped to [0, 10000]. The mode falls back
/// to the mean when either posterior shape is <= 1.
/// Error case: Err("ml: ...") for non-positive priors, negative counts, a
/// negative z, or a posterior total above 100000.
/// Complexity: O(1).
pub fn ml_beta_binomial(prior_alpha: Int, prior_beta: Int, successes: Int, failures: Int, z_bps: Int) -> Result[BetaPosterior, Str] {
  if prior_alpha <= 0 {
    return _err_beta("ml: prior alpha must be positive");
  }
  if prior_beta <= 0 {
    return _err_beta("ml: prior beta must be positive");
  }
  if successes < 0 {
    return _err_beta("ml: successes must be non-negative");
  }
  if failures < 0 {
    return _err_beta("ml: failures must be non-negative");
  }
  if z_bps < 0 {
    return _err_beta("ml: z-score must be non-negative");
  }
  let a = prior_alpha + successes;
  let b = prior_beta + failures;
  let tot = a + b;
  if tot > _ML_MAX_POST {
    return _err_beta("ml: posterior total too large");
  }
  let mean = _div_round(a * _ML_BPS, tot);
  var mode: Int = mean;
  if a > 1 {
    if b > 1 {
      mode = _div_round((a - 1) * _ML_BPS, a + b - 2);
    }
  }
  let num = _ML_BPS * _ML_BPS * a * b;
  let den = tot * tot * (tot + 1);
  let var_bps = _div_round(num, den);
  let std_bps = _ml_isqrt(var_bps);
  let half = _div_round(z_bps * std_bps, 100);
  var lower = mean - half;
  if lower < 0 {
    lower = 0;
  }
  var upper = mean + half;
  if upper > _ML_BPS {
    upper = _ML_BPS;
  }
  return _ok_beta(BetaPosterior{ alpha: a; beta: b; mean_bps: mean; mode_bps: mode; lower_bps: lower; upper_bps: upper; });
}

/// Posterior alpha shape. Complexity: O(1).
pub fn ml_beta_alpha(p: &BetaPosterior) -> Int {
  return p.alpha;
}

/// Posterior beta shape. Complexity: O(1).
pub fn ml_beta_beta(p: &BetaPosterior) -> Int {
  return p.beta;
}

/// Posterior mean in basis points. Complexity: O(1).
pub fn ml_beta_mean_bps(p: &BetaPosterior) -> Int {
  return p.mean_bps;
}

/// Posterior mode in basis points. Complexity: O(1).
pub fn ml_beta_mode_bps(p: &BetaPosterior) -> Int {
  return p.mode_bps;
}

/// Lower credible-interval bound in basis points. Complexity: O(1).
pub fn ml_beta_lower_bps(p: &BetaPosterior) -> Int {
  return p.lower_bps;
}

/// Upper credible-interval bound in basis points. Complexity: O(1).
pub fn ml_beta_upper_bps(p: &BetaPosterior) -> Int {
  return p.upper_bps;
}

// ---------------------------------------------------------------------------
// Kalman filter
// ---------------------------------------------------------------------------

/// Initialise a 1-D Kalman state. Complexity: O(1).
pub fn ml_kalman_init(x: Int, p: Int) -> KalmanState {
  return KalmanState{ x: x; p: p; };
}

/// Predict step: state unchanged, covariance gains process noise `q`.
/// Complexity: O(1).
pub fn ml_kalman_predict(s: &KalmanState, q: Int) -> KalmanState {
  return KalmanState{ x: s.x; p: s.p + q; };
}

/// Update step against a scaled measurement `z` with noise `r`.
///
/// The gain is k = round(1000 * p / (p + r)) clamped to [0, 1000];
/// x' = x + round(k * (z - x) / 1000); p' = round((1000 - k) * p / 1000).
/// Error case: Err("ml: kalman innovation variance must be positive") when
/// p + r <= 0.
/// Complexity: O(1).
pub fn ml_kalman_update(s: &KalmanState, z: Int, r: Int) -> Result[KalmanState, Str] {
  let den = s.p + r;
  if den <= 0 {
    return _err_kal("ml: kalman innovation variance must be positive");
  }
  var k = _div_round(s.p * _ML_SCALE, den);
  if k < 0 {
    k = 0;
  }
  if k > _ML_SCALE {
    k = _ML_SCALE;
  }
  let nx = s.x + _div_round(k * (z - s.x), _ML_SCALE);
  let np = _div_round((_ML_SCALE - k) * s.p, _ML_SCALE);
  return _ok_kal(KalmanState{ x: nx; p: np; });
}

/// Scaled state of a Kalman state. Complexity: O(1).
pub fn ml_kalman_x(s: &KalmanState) -> Int {
  return s.x;
}

/// Scaled covariance of a Kalman state. Complexity: O(1).
pub fn ml_kalman_p(s: &KalmanState) -> Int {
  return s.p;
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

// Truncating division with halves rounded away from zero (b > 0). The doubled
// remainder is safe for the denominators used here (counts <= 100000, scale
// 1000, posterior totals <= 100000).
fn _div_round(a: Int, b: Int) -> Int {
  let q = a / b;
  let rr = a % b;
  var mag = rr;
  if mag < 0 {
    mag = 0 - mag;
  }
  if mag * 2 >= b {
    if a < 0 {
      return q - 1;
    }
    return q + 1;
  }
  return q;
}

// Integer square root of a non-negative Int by Newton iteration (bounded at
// 100 rounds; converges in well under that for the values used here).
fn _ml_isqrt(n: Int) -> Int {
  if n <= 0 {
    return 0;
  }
  var x = n;
  var y = (x + 1) / 2;
  var it = 0;
  while y < x {
    if it >= 100 {
      return x;
    }
    x = y;
    y = (x + n / x) / 2;
    it = it + 1;
  }
  return x;
}

// Normalise any Int seed into [1, 2147483646].
fn _ml_lcg_norm(seed: Int) -> Int {
  var s = seed % _ML_LCG_RANGE;
  if s < 0 {
    s = 0 - s;
  }
  return s + 1;
}

// One MINSTD step. State stays in [1, 2147483646].
fn _ml_lcg_step(state: Int) -> Int {
  var s = state % _ML_LCG_MOD;
  if s < 0 {
    s = 0 - s;
  }
  if s == 0 {
    s = 1;
  }
  return (s * _ML_LCG_MULT) % _ML_LCG_MOD;
}

// ---------------------------------------------------------------------------
// Leaf Result constructors
// ---------------------------------------------------------------------------

fn _ok_lm(v: LinearModel) -> Result[LinearModel, Str] {
  return Ok(v);
}

fn _err_lm(msg: Str) -> Result[LinearModel, Str] {
  return Err(msg);
}

fn _ok_mcmc(v: MCMCResult) -> Result[MCMCResult, Str] {
  return Ok(v);
}

fn _err_mcmc(msg: Str) -> Result[MCMCResult, Str] {
  return Err(msg);
}

fn _ok_beta(v: BetaPosterior) -> Result[BetaPosterior, Str] {
  return Ok(v);
}

fn _err_beta(msg: Str) -> Result[BetaPosterior, Str] {
  return Err(msg);
}

fn _ok_kal(v: KalmanState) -> Result[KalmanState, Str] {
  return Ok(v);
}

fn _err_kal(msg: Str) -> Result[KalmanState, Str] {
  return Err(msg);
}
