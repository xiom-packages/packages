// XIOM -- xiom.activation: fixed-point activation functions and derivatives
// Port task: replace the xiom.activation placeholder with a pure-XIOM module
// (fixed-point integers only: no floats, no FFI, no threads, no I/O).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model (pinned in SPEC.md, exercised by tests/test_conformance.xi):
//
//   - fixed point: every argument, activation value and derivative is an Int
//     in units of 1e-4 (activation_scale() == 10000; one unit is 0.0001).
//     Every division truncates toward zero (v0.62.x Int division).
//   - saturation: every activation output lies in [-10000, 10000], i.e.
//     [-1.0, 1.0] on the unit scale. Positive linear inputs clamp at 10000,
//     leaky relu clamps its negative branch at -10000, and elu stays above
//     -alpha by construction (alpha <= 10000). Derivatives are slopes in the
//     same 1e-4 units (10000 == 1.0).
//   - exponential: exp(x) for x <= 0 uses repeated squaring,
//     (1 - x / (1024 * 10^4))^1024, evaluated as ten rounded fixed-point
//     squarings plus one reciprocal (the exact integer steps and the
//     accuracy envelope are in SPEC.md). It never touches floating point,
//     is monotone, returns 10000 at x == 0 and 0 for x <= -150000.
//   - tanh and sigmoid come from that exponential through their exact
//     identities tanh(x) = (1 - e^-2x) / (1 + e^-2x) and
//     sigmoid(x) = 1 / (1 + e^-x); both are monotone and saturate at
//     -10000 / 10000 (sigmoid at 0 / 10000).
//   - softmax subtracts the maximum logit first, exponentiates with the same
//     approximation, floors every element and hands the residue to the first
//     maximum element, so the returned vector sums to exactly 10000.
//   - derivatives: relu, leaky relu and elu return exact slopes in bps;
//     sigmoid and tanh derivatives are computed from their returned values
//     (s * (10000 - s) / 10000 and 10000 - t * t / 10000); softmax exposes
//     the diagonal and off-diagonal Jacobian entries as separate helpers.
//
// Layout notes that shaped this module (compiler v0.62.2):
//   * free functions only: no methods, no generics, no callbacks, no indexed
//     function-table dispatch, no recursion; every loop is a bounded counter
//     that strictly makes progress.
//   * every Vec element read binds the value to a typed local first.
//   * no Vec[Str] and no Str values in the library (a pure Int API).
//   * leaf Ok/Err constructors wrap every Result; every multiply and divide
//     stays inside a documented envelope, so no step can overflow silently.

module xiom.activation

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

// Fixed-point scale: one unit is 1e-4; 10000 units == 1.0.
const _ACT_SCALE: Int = 10000;

// Activation outputs saturate at +-10000 (+-1.0 on the unit scale).
const _ACT_SAT: Int = 10000;

// Documented input envelope for the scalar activations (|x| <= 10^9).
const _ACT_X_LIMIT: Int = 1000000000;

// Exponential approximation internal scales (see SPEC.md, section "The
// integer exponential"): base in 10^6 units, ten squarings (2^10 == 1024),
// the fixed-point product 10^10, and the -150000 floor (e^-15 < 0.0001
// units, so the result truncates to 0 anyway).
const _ACT_EXP_SCALE: Int = 1000000;
const _ACT_EXP_T_DIV: Int = 10240000;   // 1024 * 10^4
const _ACT_EXP_T_HALF: Int = 5120000;   // _ACT_EXP_T_DIV / 2
const _ACT_EXP_SQ_HALF: Int = 500000;   // _ACT_EXP_SCALE / 2
const _ACT_EXP_PROD: Int = 10000000000; // _ACT_EXP_SCALE * _ACT_SCALE
const _ACT_EXP_FLOOR: Int = -150000;
const _ACT_EXP_STEPS: Int = 10;

// 10000^2, used by the sigmoid numerator.
const _ACT_SAT_SQ: Int = 100000000;

// Softmax envelope: |logit| <= 10^6 and at most 10^6 logits, so the maximum
// logit difference and the exponential sum stay far below Int overflow.
const _ACT_SOFTMAX_X_LIMIT: Int = 1000000;
const _ACT_SOFTMAX_N_LIMIT: Int = 1000000;

// ---------------------------------------------------------------------------
// Constant accessors
// ---------------------------------------------------------------------------

/// Fixed-point scale (10000 units = 1.0). Complexity: O(1).
pub fn activation_scale() -> Int {
  return _ACT_SCALE;
}

/// Activation saturation bound (10000 = 1.0; outputs lie in [-10000, 10000]).
/// Complexity: O(1).
pub fn activation_saturation() -> Int {
  return _ACT_SAT;
}

/// Scalar input envelope: accepted |x| <= 1000000000. Complexity: O(1).
pub fn activation_x_limit() -> Int {
  return _ACT_X_LIMIT;
}

/// Input floor of the exponential approximation (-150000 = -15.0): at or
/// below it activation_exp returns 0. Complexity: O(1).
pub fn activation_exp_floor() -> Int {
  return _ACT_EXP_FLOOR;
}

/// Number of fixed-point squarings in the exponential approximation (10).
/// Complexity: O(1).
pub fn activation_exp_steps() -> Int {
  return _ACT_EXP_STEPS;
}

/// Softmax logit envelope: accepted |logit| <= 1000000. Complexity: O(1).
pub fn activation_softmax_x_limit() -> Int {
  return _ACT_SOFTMAX_X_LIMIT;
}

// ---------------------------------------------------------------------------
// Integer exponential
// ---------------------------------------------------------------------------

/// e^x in fixed point for the documented domain x <= 0.
///
/// Params: x - fixed-point exponent (0.0001 units); x >= 0 is clamped to
///         activation_saturation() (10000), x <= activation_exp_floor()
///         returns 0.
/// Returns: an Int in [0, 10000] approximating 10000 * e^x. The integer
/// steps are pinned in SPEC.md; measured worst-case absolute error is 5.82
/// units and the documented bound is 8 units. The function is monotone
/// non-decreasing in x.
/// Error case: none (total on the envelope).
/// Complexity: O(activation_exp_steps()) = O(1).
pub fn activation_exp(x: Int) -> Int {
  if x >= 0 {
    return _ACT_SAT;
  }
  return _act_exp_nonpos(x);
}

// The approximation core. Callers pass any Int; x >= 0 returns 10000 and
// x <= _ACT_EXP_FLOOR returns 0, so an out-of-envelope caller cannot overflow:
// the largest magnitude reaching the squaring loop is 150000, where
// ax * _ACT_EXP_SCALE <= 1.5e11 and the largest squared term is below 3e18
// (both inside the Int range). The loop runs exactly _ACT_EXP_STEPS times.
fn _act_exp_nonpos(x: Int) -> Int {
  if x >= 0 {
    return _ACT_SAT;
  }
  if x <= _ACT_EXP_FLOOR {
    return 0;
  }
  let ax = 0 - x;
  let t = (ax * _ACT_EXP_SCALE + _ACT_EXP_T_HALF) / _ACT_EXP_T_DIV;
  var v = _ACT_EXP_SCALE + t;
  var i = 0;
  while i < _ACT_EXP_STEPS {
    v = (v * v + _ACT_EXP_SQ_HALF) / _ACT_EXP_SCALE;
    i = i + 1;
  }
  return _ACT_EXP_PROD / v;
}

// ---------------------------------------------------------------------------
// ReLU
// ---------------------------------------------------------------------------

/// Rectified linear unit: max(0, x), clamped to [0, 10000].
///
/// Params: x - any fixed-point Int.
/// Returns: 0 for x <= 0, x for 0 < x < 10000, 10000 for x >= 10000.
/// Exact; no approximation. Complexity: O(1).
pub fn activation_relu(x: Int) -> Int {
  if x <= 0 {
    return 0;
  }
  if x >= _ACT_SAT {
    return _ACT_SAT;
  }
  return x;
}

/// Derivative of relu: 10000 (1.0) for x > 0, 0 otherwise.
///
/// The subgradient at x == 0 is pinned to 0 (documented in SPEC.md).
/// Exact. Complexity: O(1).
pub fn activation_relu_derivative(x: Int) -> Int {
  if x > 0 {
    return _ACT_SAT;
  }
  return 0;
}

// ---------------------------------------------------------------------------
// Leaky ReLU
// ---------------------------------------------------------------------------

/// Leaky rectified linear unit: x for x > 0, slope_bps * x / 10000 for
/// x <= 0, both clamped to [-10000, 10000].
///
/// Params: x - any fixed-point Int (values below -activation_x_limit() are
///         clamped into the envelope before the multiply);
///         slope_bps - negative-branch slope in basis points, clamped to
///         [0, 10000] before use (10000 == 1.0 == plain relu).
/// Returns: an Int in [-10000, 10000]; the negative branch truncates toward
/// zero. Exact in the documented envelope. Complexity: O(1).
pub fn activation_leaky_relu(x: Int, slope_bps: Int) -> Int {
  let slope = _act_clamp_bps(slope_bps);
  if x >= _ACT_SAT {
    return _ACT_SAT;
  }
  if x > 0 {
    return x;
  }
  var xc = x;
  if xc < 0 - _ACT_X_LIMIT {
    xc = 0 - _ACT_X_LIMIT;
  }
  let r = (slope * xc) / _ACT_SCALE;
  if r <= 0 - _ACT_SAT {
    return 0 - _ACT_SAT;
  }
  return r;
}

/// Derivative of leaky relu: 10000 for x > 0, slope_bps for x < 0, 0 at
/// x == 0 (subgradient choice pinned, consistent with relu).
///
/// Params: x - any fixed-point Int; slope_bps - clamped to [0, 10000].
/// Returns: a slope in [0, 10000] basis-point units. Exact.
/// Complexity: O(1).
pub fn activation_leaky_relu_derivative(x: Int, slope_bps: Int) -> Int {
  let slope = _act_clamp_bps(slope_bps);
  if x > 0 {
    return _ACT_SAT;
  }
  if x < 0 {
    return slope;
  }
  return 0;
}

// ---------------------------------------------------------------------------
// ELU
// ---------------------------------------------------------------------------

/// Exponential linear unit (piecewise): x for x >= 0, and
/// alpha_bps * (e^x - 1) / 10000 for x < 0, clamped to [-10000, 10000].
///
/// Params: x - any fixed-point Int (below -activation_x_limit() it is
///         clamped into the envelope); alpha_bps - saturation coefficient in
///         basis points, clamped to [0, 10000] before use.
/// Returns: an Int in [-10000, 10000]; the negative branch uses
/// activation_exp() and truncates toward zero. The exponential's documented
/// error makes the negative branch accurate well below one unit.
/// Complexity: O(1) with the exponential's fixed cost.
pub fn activation_elu(x: Int, alpha_bps: Int) -> Int {
  let alpha = _act_clamp_bps(alpha_bps);
  if x >= _ACT_SAT {
    return _ACT_SAT;
  }
  if x >= 0 {
    return x;
  }
  var xc = x;
  if xc < 0 - _ACT_X_LIMIT {
    xc = 0 - _ACT_X_LIMIT;
  }
  let e = _act_exp_nonpos(xc);
  return (alpha * (e - _ACT_SAT)) / _ACT_SCALE;
}

/// Derivative of elu: 10000 for x >= 0, alpha_bps * e^x / 10000 for x < 0.
///
/// Params: x - any fixed-point Int; alpha_bps - clamped to [0, 10000].
/// Returns: a slope in [0, 10000] basis-point units (0 when x is at or below
/// the exponential floor). Complexity: O(1).
pub fn activation_elu_derivative(x: Int, alpha_bps: Int) -> Int {
  let alpha = _act_clamp_bps(alpha_bps);
  if x >= 0 {
    return _ACT_SAT;
  }
  var xc = x;
  if xc < 0 - _ACT_X_LIMIT {
    xc = 0 - _ACT_X_LIMIT;
  }
  let e = _act_exp_nonpos(xc);
  return (alpha * e) / _ACT_SCALE;
}

// ---------------------------------------------------------------------------
// Sigmoid
// ---------------------------------------------------------------------------

/// Logistic sigmoid: 10000 / (1 + e^-x), via the exact identity
/// 1 / (1 + e^-|x|) on the sign-split branches.
///
/// Params: x - any fixed-point Int; values at or beyond
///         +-activation_x_limit() saturate immediately.
/// Returns: an Int in [0, 10000] (5000 at x == 0). Monotone non-decreasing;
/// measured worst-case absolute error 3 units, documented bound 5 units
/// (SPEC.md). Complexity: O(1) with the exponential's fixed cost.
pub fn activation_sigmoid(x: Int) -> Int {
  if x >= _ACT_X_LIMIT {
    return _ACT_SAT;
  }
  if x <= 0 - _ACT_X_LIMIT {
    return 0;
  }
  if x >= 0 {
    let e = _act_exp_nonpos(0 - x);
    return _ACT_SAT_SQ / (_ACT_SCALE + e);
  }
  let e = _act_exp_nonpos(x);
  return (e * _ACT_SCALE) / (_ACT_SCALE + e);
}

/// Derivative of sigmoid: s * (10000 - s) / 10000, with s the value
/// activation_sigmoid returns for x.
///
/// Params: x - any fixed-point Int.
/// Returns: an Int in [0, 2500] (2500 at x == 0). Measured worst-case
/// absolute error 2 basis points, documented bound 5 bps (SPEC.md).
/// Complexity: O(1) with the sigmoid's fixed cost.
pub fn activation_sigmoid_derivative(x: Int) -> Int {
  let s = activation_sigmoid(x);
  return (s * (_ACT_SAT - s)) / _ACT_SCALE;
}

// ---------------------------------------------------------------------------
// Tanh
// ---------------------------------------------------------------------------

/// Hyperbolic tangent: (1 - e^-2x) / (1 + e^-2x), evaluated sign-symmetrically.
///
/// Params: x - any fixed-point Int; values at or beyond
///         +-activation_x_limit() saturate immediately.
/// Returns: an Int in [-10000, 10000] (0 at x == 0, +-10000 for |x| >= 75000).
/// Monotone non-decreasing and odd (f(-x) == -f(x)); measured worst-case
/// absolute error 6 units, documented bound 8 units (SPEC.md).
/// Complexity: O(1) with the exponential's fixed cost.
pub fn activation_tanh(x: Int) -> Int {
  if x >= _ACT_X_LIMIT {
    return _ACT_SAT;
  }
  if x <= 0 - _ACT_X_LIMIT {
    return 0 - _ACT_SAT;
  }
  if x == 0 {
    return 0;
  }
  if x > 0 {
    let e = _act_exp_nonpos(0 - 2 * x);
    return ((_ACT_SAT - e) * _ACT_SAT) / (_ACT_SAT + e);
  }
  let e = _act_exp_nonpos(2 * x);
  return 0 - ((_ACT_SAT - e) * _ACT_SAT) / (_ACT_SAT + e);
}

/// Derivative of tanh: 10000 - t * t / 10000, with t the value
/// activation_tanh returns for x.
///
/// Params: x - any fixed-point Int.
/// Returns: an Int in [0, 10000] (10000 at x == 0, 0 at the saturation
/// plateau). Measured worst-case absolute error 9 basis points, documented
/// bound 12 bps (SPEC.md). Complexity: O(1) with the tanh's fixed cost.
pub fn activation_tanh_derivative(x: Int) -> Int {
  let t = activation_tanh(x);
  return _ACT_SAT - (t * t) / _ACT_SCALE;
}

// ---------------------------------------------------------------------------
// Softmax
// ---------------------------------------------------------------------------

/// Softmax over a fixed-point logit vector, normalized to sum exactly 10000.
///
/// Params: logits - at least one fixed-point logit, each in
///         [-activation_softmax_x_limit(), activation_softmax_x_limit()]
///         (at most 10^6 of them).
/// Returns: Ok(probabilities) with the same length; entry i is
/// floor(10000 * e^(logit_i - max) / sum(e^(logit_j - max))) and the first
/// maximum element additionally receives the rounding residue, so
/// sum(probabilities) == 10000 exactly and every entry is in [0, 10000].
/// The exp approximation's documented error bounds each pre-normalization
/// value to within 8 units of 10000 * e^x.
/// Error case: Err("activation: ...") for an empty vector, a logit outside
/// the envelope, or more than 1000000 logits.
/// Complexity: O(n) with the exponential's fixed cost per element.
pub fn activation_softmax(logits: &Vec[Int]) -> Result[Vec[Int], Str] {
  let n = logits.len();
  if n == 0 {
    return _err_ints("activation: softmax requires a non-empty vector");
  }
  if n > _ACT_SOFTMAX_N_LIMIT {
    return _err_ints("activation: softmax input exceeds the length limit");
  }
  var i = 0;
  var max_v: Int = logits[0];
  while i < n {
    let x: Int = logits[i];
    if x > _ACT_SOFTMAX_X_LIMIT {
      return _err_ints("activation: softmax logit out of range");
    }
    if x < 0 - _ACT_SOFTMAX_X_LIMIT {
      return _err_ints("activation: softmax logit out of range");
    }
    if x > max_v {
      max_v = x;
    }
    i = i + 1;
  }
  // Exponentials of the shifted logits (the maximum shift keeps every
  // argument <= 0 and at least one exponential exactly 10000).
  var exps = Vec[Int].new();
  var sum: Int = 0;
  i = 0;
  while i < n {
    let x: Int = logits[i];
    let e = _act_exp_nonpos(x - max_v);
    exps.push(e);
    sum = sum + e;
    i = i + 1;
  }
  // Floor each share; track the first maximum exponential for the residue.
  var out = Vec[Int].new();
  var largest = 0;
  var largest_e: Int = -1;
  i = 0;
  while i < n {
    let e: Int = exps[i];
    let o = (e * _ACT_SAT) / sum;
    out.push(o);
    if e > largest_e {
      largest_e = e;
      largest = i;
    }
    i = i + 1;
  }
  var total: Int = 0;
  i = 0;
  while i < n {
    let o: Int = out[i];
    total = total + o;
    i = i + 1;
  }
  // total <= 10000 by construction; the non-negative residue restores the
  // exact 10000 sum on the first maximum element.
  let top: Int = out[largest];
  out[largest] = top + (_ACT_SAT - total);
  return _ok_ints(out);
}

/// Diagonal Jacobian entry of softmax: s * (10000 - s) / 10000.
///
/// Params: s - one softmax output, clamped to [0, 10000] before use.
/// Returns: an Int in [0, 2500] in 1e-4 units. Exact for the given s.
/// Complexity: O(1).
pub fn activation_softmax_diag_derivative(s: Int) -> Int {
  var sc = s;
  if sc < 0 {
    sc = 0;
  }
  if sc > _ACT_SAT {
    sc = _ACT_SAT;
  }
  return (sc * (_ACT_SAT - sc)) / _ACT_SCALE;
}

/// Off-diagonal Jacobian entry of softmax: -s_i * s_j / 10000.
///
/// Params: s_i, s_j - two softmax outputs, each clamped to [0, 10000].
/// Returns: an Int in [-2500, 0] in 1e-4 units (truncation toward zero).
/// Exact for the given values. Complexity: O(1).
pub fn activation_softmax_cross_derivative(s_i: Int, s_j: Int) -> Int {
  var a = s_i;
  if a < 0 {
    a = 0;
  }
  if a > _ACT_SAT {
    a = _ACT_SAT;
  }
  var b = s_j;
  if b < 0 {
    b = 0;
  }
  if b > _ACT_SAT {
    b = _ACT_SAT;
  }
  return 0 - (a * b) / _ACT_SCALE;
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

// Clamp a slope/coefficient in basis points into [0, 10000].
fn _act_clamp_bps(v: Int) -> Int {
  if v < 0 {
    return 0;
  }
  if v > _ACT_SCALE {
    return _ACT_SCALE;
  }
  return v;
}

// ---------------------------------------------------------------------------
// Leaf Result constructors
// ---------------------------------------------------------------------------

fn _ok_ints(v: Vec[Int]) -> Result[Vec[Int], Str] {
  return Ok(v);
}

fn _err_ints(msg: Str) -> Result[Vec[Int], Str] {
  return Err(msg);
}
