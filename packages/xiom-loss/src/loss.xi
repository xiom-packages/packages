// XIOM -- xiom.loss: fixed-point supervised loss functions on scaled integers
// Port task: replace the xiom.loss placeholder with a pure-XIOM module
// (scaled integers only: no floats, no FFI, no I/O, no Vec[Float64]).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Two scales are used throughout:
//
//   value scale  3 fraction digits (raw = value * 1000)     predictions,
//                 targets, probabilities, gradients
//   loss scale   6 fraction digits (raw = value * 1000000)  every loss return
//
// loss_value_one() is 1000 and loss_loss_one() is 1000000, so a raw `r`
// denotes r/1000 (value scale) or r/1000000 (loss scale).
//
// Rounding: XIOM integer division truncates toward zero. Every result that is
// not exact is rounded to nearest with ties away from zero through
// _div_round / _mul_div_round (see SPEC.md for the exact rules).
//
// Probabilities are scaled Int in (0, 1000]. The cross-entropy functions
// clamp them into [1, 999] before the logarithm
// (loss_probability_epsilon() is 1 raw unit, i.e. 0.001); callers who need a
// different epsilon can pre-clamp with loss_clip. loss_natural_log rejects
// arguments <= 0 and arguments above 9223372036854 raw.
//
// The natural logarithm is a range-reduced fixed-point approximation: the
// argument is normalized to [1, 2) with power-of-two scaling and
// ln((1+t)/(1-t)) is evaluated as an atanh series through t^13 in a 1e9
// working scale. Maximum observed absolute error over the probability domain
// is 0.51 units of the 1e-6 output scale (method and bounds in SPEC.md).
//
// Free functions only; every public function is `loss_*`. Ok/Err construction
// lives in the leaf helpers at the bottom of this file.

module xiom.loss

use xiom.string;
use xiom.convert;

const _LOSS_VALUE_DEC: Int = 3;
const _LOSS_LOSS_DEC: Int = 6;
const _LOSS_VALUE_ONE: Int = 1000;
const _LOSS_LOSS_ONE: Int = 1000000;
const _LOSS_MICRO: Int = 1000000000;
const _LOSS_LN2_1E9: Int = 693147181;
const _LOSS_PROB_EPS: Int = 1;
const _LOSS_INPUT_LIMIT: Int = 4000000000;
const _LOSS_SQRT_MAX: Int = 3037000499;
const _LOSS_LN_MAX_ARG: Int = 9223372036854;
const _LOSS_INT_MAX: Int = 9223372036854775807;

// ---------------------------------------------------------------------------
// Scale accessors
// ---------------------------------------------------------------------------

/// Fraction digits of values (predictions, targets, probabilities and
/// gradients): 3, so raw r denotes r/1000.
pub fn loss_value_decimals() -> Int {
  return _LOSS_VALUE_DEC;
}

/// Fraction digits of every returned loss: 6, so raw r denotes r/1000000.
pub fn loss_loss_decimals() -> Int {
  return _LOSS_LOSS_DEC;
}

/// Value-scale unit: raw 1000 denotes the real number 1.0.
pub fn loss_value_one() -> Int {
  return _LOSS_VALUE_ONE;
}

/// Loss-scale unit: raw 1000000 denotes the real number 1.0.
pub fn loss_loss_one() -> Int {
  return _LOSS_LOSS_ONE;
}

/// Clamp step of the cross-entropy probability domain: 1 raw unit (0.001).
/// Cross-entropy inputs are clamped into [eps, 1000 - eps] before the log.
pub fn loss_probability_epsilon() -> Int {
  return _LOSS_PROB_EPS;
}

// ---------------------------------------------------------------------------
// Fixed-point natural logarithm and clamping
// ---------------------------------------------------------------------------

/// Fixed-point natural logarithm.
/// Params: x - value-scale raw integer with x > 0 and
///         x <= 9223372036854.
/// Returns: Ok(ln(x / 1000) in loss scale), rounded to nearest with ties
/// away from zero: raw = ln(x/1000) * 1e6.
/// Method: x is normalized to m in [1, 2) with exact (or one-step rounded)
/// power-of-two scaling, ln x = ln m + k*ln 2, and ln m is the atanh series
/// 2*(t + t^3/3 + t^5/5 + ... + t^13/13) with t = (m-1)/(m+1), evaluated in
/// a 1e9 working scale. Maximum absolute error over x in [1, 999] is below
/// one unit of the 1e-6 output scale.
/// Error case: Err("loss: ...") when x <= 0 or x exceeds the envelope.
/// Complexity: O(1) (at most 62 reduction steps).
pub fn loss_natural_log(x: Int) -> Result[Int, Str] {
  if x <= 0 {
    return _err_int("loss: logarithm argument must be positive");
  }
  if x > _LOSS_LN_MAX_ARG {
    return _err_int("loss: logarithm argument exceeds the supported envelope");
  }
  return _ok_int(_ln6(x));
}

/// Clamp one probability-like value into [lo, hi].
/// Params: p - any value-scale integer; lo and hi - value-scale bounds with
///         0 <= lo <= hi <= 1000.
/// Returns: Ok(p) when lo <= p <= hi, else Ok(lo) or Ok(hi).
/// Error case: Err("loss: ...") when lo < 0, hi > 1000 or lo > hi.
/// Complexity: O(1).
pub fn loss_clip(p: Int, lo: Int, hi: Int) -> Result[Int, Str] {
  if lo < 0 {
    return _err_int("loss: clip bounds must satisfy 0 <= lo <= hi <= 1000");
  }
  if hi > _LOSS_VALUE_ONE {
    return _err_int("loss: clip bounds must satisfy 0 <= lo <= hi <= 1000");
  }
  if lo > hi {
    return _err_int("loss: clip bounds must satisfy 0 <= lo <= hi <= 1000");
  }
  if p < lo {
    return _ok_int(lo);
  }
  if p > hi {
    return _ok_int(hi);
  }
  return _ok_int(p);
}

// ---------------------------------------------------------------------------
// Mean squared error
// ---------------------------------------------------------------------------

/// Mean squared error over parallel predictions and targets.
/// Params: predictions, targets - equal-length non-empty value-scale vectors
///         with |entry| <= 4000000000 and |prediction - target| <= 3037000499.
/// Returns: Ok(mean((prediction - target)^2) in loss scale), rounded to
/// nearest with ties away from zero. A difference of 1000 raw (1.0)
/// contributes 1000000 raw (1.0) to the mean.
/// Error case: Err("loss: ...") for an empty or mismatched pair, an entry
/// outside the envelope, or an overflowing difference/square/sum.
/// Complexity: O(n).
pub fn loss_mse(predictions: &Vec[Int], targets: &Vec[Int]) -> Result[Int, Str] {
  let err = _pair_error(predictions, targets);
  if err.len() != 0 {
    return _err_int(err);
  }
  let n = predictions.len();
  var s: Int = 0;
  var i = 0;
  while i < n {
    let p: Int = predictions[i];
    let t: Int = targets[i];
    let pe = _envelope_error(p, "prediction");
    if pe.len() != 0 {
      return _err_int(pe);
    }
    let te = _envelope_error(t, "target");
    if te.len() != 0 {
      return _err_int(te);
    }
    let d = p - t;
    if d > _LOSS_SQRT_MAX {
      return _err_int("loss: squared difference overflows");
    }
    if d < (0 - _LOSS_SQRT_MAX) {
      return _err_int("loss: squared difference overflows");
    }
    let sq = d * d;
    if s > _LOSS_INT_MAX - sq {
      return _err_int("loss: accumulation overflows");
    }
    s = s + sq;
    i = i + 1;
  }
  return _ok_int(_div_round(s, n));
}

/// Gradient of loss_mse with respect to each prediction.
/// Params: predictions, targets - as for loss_mse.
/// Returns: Ok(gradient) with one value-scale entry per sample:
/// round(2 * (prediction - target) / n), rounded to nearest with ties away
/// from zero. The sign is the sign of the prediction error.
/// Error case: Err("loss: ...") exactly as for loss_mse.
/// Complexity: O(n).
pub fn loss_mse_grad(predictions: &Vec[Int], targets: &Vec[Int]) -> Result[Vec[Int], Str] {
  let err = _pair_error(predictions, targets);
  if err.len() != 0 {
    return _err_ints(err);
  }
  let n = predictions.len();
  var out = Vec[Int].new();
  var i = 0;
  while i < n {
    let p: Int = predictions[i];
    let t: Int = targets[i];
    let pe = _envelope_error(p, "prediction");
    if pe.len() != 0 {
      return _err_ints(pe);
    }
    let te = _envelope_error(t, "target");
    if te.len() != 0 {
      return _err_ints(te);
    }
    let d = p - t;
    if d > _LOSS_SQRT_MAX {
      return _err_ints("loss: squared difference overflows");
    }
    if d < (0 - _LOSS_SQRT_MAX) {
      return _err_ints("loss: squared difference overflows");
    }
    out.push(_div_round(2 * d, n));
    i = i + 1;
  }
  return _ok_ints(out);
}

// ---------------------------------------------------------------------------
// Mean absolute error
// ---------------------------------------------------------------------------

/// Mean absolute error over parallel predictions and targets.
/// Params: predictions, targets - equal-length non-empty value-scale vectors
///         with |entry| <= 4000000000.
/// Returns: Ok(mean(|prediction - target|) in loss scale), rounded to nearest
/// with ties away from zero. A mean absolute difference of 1000 raw (1.0)
/// returns 1000000 raw (1.0).
/// Error case: Err("loss: ...") for an empty or mismatched pair or an entry
/// outside the envelope.
/// Complexity: O(n).
pub fn loss_mae(predictions: &Vec[Int], targets: &Vec[Int]) -> Result[Int, Str] {
  let err = _pair_error(predictions, targets);
  if err.len() != 0 {
    return _err_int(err);
  }
  let n = predictions.len();
  var s: Int = 0;
  var i = 0;
  while i < n {
    let p: Int = predictions[i];
    let t: Int = targets[i];
    let pe = _envelope_error(p, "prediction");
    if pe.len() != 0 {
      return _err_int(pe);
    }
    let te = _envelope_error(t, "target");
    if te.len() != 0 {
      return _err_int(te);
    }
    let d = p - t;
    s = s + _abs_val(d);
    i = i + 1;
  }
  return _ok_int(_mul_div_round(s, _LOSS_VALUE_ONE, n));
}

/// Gradient of loss_mae with respect to each prediction.
/// Params: predictions, targets - as for loss_mae.
/// Returns: Ok(gradient) with one value-scale entry per sample:
/// round(sign(prediction - target) * 1000 / n), rounded to nearest with ties
/// away from zero; 0 where the prediction matches the target exactly.
/// Error case: Err("loss: ...") exactly as for loss_mae.
/// Complexity: O(n).
pub fn loss_mae_grad(predictions: &Vec[Int], targets: &Vec[Int]) -> Result[Vec[Int], Str] {
  let err = _pair_error(predictions, targets);
  if err.len() != 0 {
    return _err_ints(err);
  }
  let n = predictions.len();
  var out = Vec[Int].new();
  var i = 0;
  while i < n {
    let p: Int = predictions[i];
    let t: Int = targets[i];
    let pe = _envelope_error(p, "prediction");
    if pe.len() != 0 {
      return _err_ints(pe);
    }
    let te = _envelope_error(t, "target");
    if te.len() != 0 {
      return _err_ints(te);
    }
    let d = p - t;
    var g = 0;
    if d > 0 {
      g = _div_round(_LOSS_VALUE_ONE, n);
    }
    if d < 0 {
      g = _div_round(0 - _LOSS_VALUE_ONE, n);
    }
    out.push(g);
    i = i + 1;
  }
  return _ok_ints(out);
}

// ---------------------------------------------------------------------------
// Hinge loss
// ---------------------------------------------------------------------------

/// Hinge loss over parallel predictions and +1/-1 targets.
/// Params: predictions - value-scale vector with |entry| <= 4000000000;
///         targets - same length, every entry exactly +1000 or -1000;
///         margin - value-scale non-negative margin (<= 4000000000).
/// Returns: Ok(mean(max(0, margin - target * prediction)) in loss scale),
/// rounded to nearest with ties away from zero. The product
/// target * prediction is value scale, so the residual is exact.
/// Error case: Err("loss: ...") for an empty or mismatched pair, a target
/// other than +1000/-1000, a negative or oversized margin, an entry outside
/// the envelope, or an overflowing sum.
/// Complexity: O(n).
pub fn loss_hinge(predictions: &Vec[Int], targets: &Vec[Int], margin: Int) -> Result[Int, Str] {
  let err = _hinge_error(predictions, targets, margin);
  if err.len() != 0 {
    return _err_int(err);
  }
  let n = predictions.len();
  var s: Int = 0;
  var i = 0;
  while i < n {
    let t: Int = targets[i];
    let p: Int = predictions[i];
    let pe = _envelope_error(p, "prediction");
    if pe.len() != 0 {
      return _err_int(pe);
    }
    let z = t * p / _LOSS_VALUE_ONE;
    if margin > z {
      let h = (margin - z) * _LOSS_VALUE_ONE;
      if s > _LOSS_INT_MAX - h {
        return _err_int("loss: accumulation overflows");
      }
      s = s + h;
    }
    i = i + 1;
  }
  return _ok_int(_div_round(s, n));
}

/// Gradient of loss_hinge with respect to each prediction.
/// Params: predictions, targets, margin - as for loss_hinge.
/// Returns: Ok(gradient) with one value-scale entry per sample:
/// round(-target / n), rounded to nearest with ties away from zero, for
/// samples with margin - target * prediction > 0, and 0 otherwise.
/// Error case: Err("loss: ...") exactly as for loss_hinge.
/// Complexity: O(n).
pub fn loss_hinge_grad(predictions: &Vec[Int], targets: &Vec[Int], margin: Int) -> Result[Vec[Int], Str] {
  let err = _hinge_error(predictions, targets, margin);
  if err.len() != 0 {
    return _err_ints(err);
  }
  let n = predictions.len();
  var out = Vec[Int].new();
  var i = 0;
  while i < n {
    let t: Int = targets[i];
    let p: Int = predictions[i];
    let pe = _envelope_error(p, "prediction");
    if pe.len() != 0 {
      return _err_ints(pe);
    }
    let z = t * p / _LOSS_VALUE_ONE;
    if margin > z {
      out.push(_div_round(0 - t, n));
    } else {
      out.push(0);
    }
    i = i + 1;
  }
  return _ok_ints(out);
}

// ---------------------------------------------------------------------------
// Binary cross-entropy
// ---------------------------------------------------------------------------

/// Binary cross-entropy over parallel probabilities and 0/1 targets.
/// Params: predictions - value-scale probabilities, clamped into [1, 999]
///         (any raw value is accepted and clamped);
///         targets - same length, every entry exactly 0 or 1000.
/// Returns: Ok(mean(-[y*ln(p) + (1-y)*ln(1-p)]) in loss scale), with each
/// rounded ln term and the mean rounded to nearest with ties away from zero.
/// The clamp keeps p = 0 and p = 1000 finite: they evaluate as p = 1 and
/// p = 999 respectively (loss 6907755 and 1001 raw for the matching target).
/// Error case: Err("loss: ...") for an empty or mismatched pair or a target
/// other than 0/1000.
/// Complexity: O(n).
pub fn loss_binary_cross_entropy(predictions: &Vec[Int], targets: &Vec[Int]) -> Result[Int, Str] {
  let err = _binary_error(predictions, targets);
  if err.len() != 0 {
    return _err_int(err);
  }
  let n = predictions.len();
  var s: Int = 0;
  var i = 0;
  while i < n {
    let t: Int = targets[i];
    let p: Int = _clip_prob(predictions[i]);
    var term = 0;
    if t == _LOSS_VALUE_ONE {
      term = 0 - _ln6(p);
    } else {
      term = 0 - _ln6(_LOSS_VALUE_ONE - p);
    }
    if s > _LOSS_INT_MAX - term {
      return _err_int("loss: accumulation overflows");
    }
    s = s + term;
    i = i + 1;
  }
  return _ok_int(_div_round(s, n));
}

/// Gradient of loss_binary_cross_entropy with respect to each probability.
/// Params: predictions, targets - as for loss_binary_cross_entropy.
/// Returns: Ok(gradient) with one value-scale entry per sample:
/// round(round((-y/p_raw + (1-y)/(1000-p_raw)) * 1e6) / n), i.e. the
/// value-scale gradient of the mean loss. Probabilities are clamped into
/// [1, 999] first, exactly as in the loss.
/// Error case: Err("loss: ...") exactly as for loss_binary_cross_entropy.
/// Complexity: O(n).
pub fn loss_binary_cross_entropy_grad(predictions: &Vec[Int], targets: &Vec[Int]) -> Result[Vec[Int], Str] {
  let err = _binary_error(predictions, targets);
  if err.len() != 0 {
    return _err_ints(err);
  }
  let n = predictions.len();
  var out = Vec[Int].new();
  var i = 0;
  while i < n {
    let t: Int = targets[i];
    let p: Int = _clip_prob(predictions[i]);
    var g = 0;
    if t == _LOSS_VALUE_ONE {
      g = _div_round(0 - _LOSS_LOSS_ONE, p);
    } else {
      g = _div_round(_LOSS_LOSS_ONE, _LOSS_VALUE_ONE - p);
    }
    out.push(_div_round(g, n));
    i = i + 1;
  }
  return _ok_ints(out);
}

// ---------------------------------------------------------------------------
// Categorical cross-entropy
// ---------------------------------------------------------------------------

/// Categorical cross-entropy of one class-probability vector.
/// Params: predictions - value-scale class probabilities, clamped into
///         [1, 999];
///         targets - same length, value-scale distribution: every entry in
///         [0, 1000] and the entries sum to exactly 1000 (one-hot is the
///         common case).
/// Returns: Ok(-sum(y * ln(p)) in loss scale) with each rounded ln term
/// accumulated and the sum rounded to nearest with ties away from zero.
/// error case: Err("loss: ...") for an empty or mismatched pair, a target
/// outside [0, 1000], or targets that do not sum to 1000.
/// Complexity: O(n).
pub fn loss_categorical_cross_entropy(predictions: &Vec[Int], targets: &Vec[Int]) -> Result[Int, Str] {
  let err = _categories_error(predictions, targets);
  if err.len() != 0 {
    return _err_int(err);
  }
  let n = predictions.len();
  var acc: Int = 0;
  var i = 0;
  while i < n {
    let y: Int = targets[i];
    let p: Int = _clip_prob(predictions[i]);
    let lg = _ln6(p);
    acc = acc + y * lg;
    i = i + 1;
  }
  return _ok_int(_div_round(0 - acc, _LOSS_VALUE_ONE));
}

/// Gradient of loss_categorical_cross_entropy with respect to each
/// class probability.
/// Params: predictions, targets - as for loss_categorical_cross_entropy.
/// Returns: Ok(gradient) with one value-scale entry per class:
/// round(-y * 1000 / p_raw), i.e. -y/p in value scale; probabilities are
/// clamped into [1, 999] first, exactly as in the loss.
/// Error case: Err("loss: ...") exactly as for
/// loss_categorical_cross_entropy.
/// Complexity: O(n).
pub fn loss_categorical_cross_entropy_grad(predictions: &Vec[Int], targets: &Vec[Int]) -> Result[Vec[Int], Str] {
  let err = _categories_error(predictions, targets);
  if err.len() != 0 {
    return _err_ints(err);
  }
  let n = predictions.len();
  var out = Vec[Int].new();
  var i = 0;
  while i < n {
    let y: Int = targets[i];
    let p: Int = _clip_prob(predictions[i]);
    out.push(_div_round(0 - _LOSS_VALUE_ONE * y, p));
    i = i + 1;
  }
  return _ok_ints(out);
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

// Shape validation shared by every pair-based function.
fn _pair_error(predictions: &Vec[Int], targets: &Vec[Int]) -> Str {
  if predictions.len() <= 0 {
    return "loss: predictions and targets must not be empty";
  }
  if targets.len() != predictions.len() {
    return "loss: predictions and targets length mismatch";
  }
  return "";
}

// Shape + 0/1 target validation for binary cross-entropy.
fn _binary_error(predictions: &Vec[Int], targets: &Vec[Int]) -> Str {
  let e = _pair_error(predictions, targets);
  if e.len() != 0 {
    return e;
  }
  var i = 0;
  while i < targets.len() {
    let y: Int = targets[i];
    if y != 0 {
      if y != _LOSS_VALUE_ONE {
        return "loss: binary target must be 0 or 1000";
      }
    }
    i = i + 1;
  }
  return "";
}

// Shape + distribution validation for categorical cross-entropy: every
// target in [0, 1000] and the vector sums to 1000.
fn _categories_error(predictions: &Vec[Int], targets: &Vec[Int]) -> Str {
  let e = _pair_error(predictions, targets);
  if e.len() != 0 {
    return e;
  }
  var sum: Int = 0;
  var i = 0;
  while i < targets.len() {
    let y: Int = targets[i];
    if y < 0 {
      return "loss: categorical target must be in [0, 1000]";
    }
    if y > _LOSS_VALUE_ONE {
      return "loss: categorical target must be in [0, 1000]";
    }
    sum = sum + y;
    i = i + 1;
  }
  if sum != _LOSS_VALUE_ONE {
    return "loss: categorical targets must sum to 1000";
  }
  return "";
}

// Shape + margin + +1/-1 target validation for the hinge loss.
fn _hinge_error(predictions: &Vec[Int], targets: &Vec[Int], margin: Int) -> Str {
  let e = _pair_error(predictions, targets);
  if e.len() != 0 {
    return e;
  }
  if margin < 0 {
    return "loss: margin must not be negative";
  }
  let me = _envelope_error(margin, "margin");
  if me.len() != 0 {
    return me;
  }
  var i = 0;
  while i < targets.len() {
    let y: Int = targets[i];
    if y != _LOSS_VALUE_ONE {
      if y != (0 - _LOSS_VALUE_ONE) {
        return "loss: hinge target must be +1000 or -1000";
      }
    }
    i = i + 1;
  }
  return "";
}

// Magnitude envelope check: keeps differences and products inside Int64 and
// pins the documented input domain.
fn _envelope_error(x: Int, what: Str) -> Str {
  if x > _LOSS_INPUT_LIMIT {
    return "loss: " + what + " magnitude exceeds the supported envelope";
  }
  if x < (0 - _LOSS_INPUT_LIMIT) {
    return "loss: " + what + " magnitude exceeds the supported envelope";
  }
  return "";
}

// Clamp any raw value into the cross-entropy probability domain [1, 999].
fn _clip_prob(p: Int) -> Int {
  if p < _LOSS_PROB_EPS {
    return _LOSS_PROB_EPS;
  }
  if p > _LOSS_VALUE_ONE - _LOSS_PROB_EPS {
    return _LOSS_VALUE_ONE - _LOSS_PROB_EPS;
  }
  return p;
}

fn _abs_val(x: Int) -> Int {
  if x < 0 {
    return 0 - x;
  }
  return x;
}

// a / b for b > 0, rounded to nearest with ties away from zero. b is small
// enough that 2*|a % b| cannot overflow.
fn _div_round(a: Int, b: Int) -> Int {
  let q = a / b;
  let r = a % b;
  var mag = r;
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

// round(a * m / b) for b > 0 without overflow of the intermediate product:
// a = q*b + r, so a*m/b = q*m + r*m/b; |r| < b keeps r*m bounded, and the
// final half-away adjustment uses the remainder of r*m/b.
fn _mul_div_round(a: Int, m: Int, b: Int) -> Int {
  let q = a / b;
  let r = a % b;
  var out = q * m;
  let num = r * m;
  out = out + num / b;
  let rem = num % b;
  var mag = rem;
  if mag < 0 {
    mag = 0 - mag;
  }
  if mag * 2 >= b {
    if a < 0 {
      return out - 1;
    }
    return out + 1;
  }
  return out;
}

// ln(x/1000) in loss scale for x in [1, _LOSS_LN_MAX_ARG].
// Range reduction: X = x * 1e6 (1e9 working scale), normalized into
// [1e9, 2e9) by rounded halving (up) or exact doubling (down), tracking the
// power of two as k. Then t = (m-1)/(m+1) and
// ln m = 2*(t + t^3/3 + t^5/5 + t^7/7 + t^9/9 + t^11/11 + t^13/13),
// all in the 1e9 scale, plus k * round(ln 2 * 1e9); the total is rounded to
// the 1e6 output scale.
fn _ln6(x: Int) -> Int {
  var xs: Int = x * _LOSS_LOSS_ONE;
  var k: Int = 0;
  while xs >= 2 * _LOSS_MICRO {
    let half = xs / 2;
    let odd = xs % 2;
    xs = half + odd;
    k = k + 1;
  }
  while xs < _LOSS_MICRO {
    xs = xs + xs;
    k = k - 1;
  }
  let num = (xs - _LOSS_MICRO) * _LOSS_MICRO;
  let den = xs + _LOSS_MICRO;
  let t = num / den;
  let t2 = t * t / _LOSS_MICRO;
  let t3 = t2 * t / _LOSS_MICRO;
  let t5 = t3 * t2 / _LOSS_MICRO;
  let t7 = t5 * t2 / _LOSS_MICRO;
  let t9 = t7 * t2 / _LOSS_MICRO;
  let t11 = t9 * t2 / _LOSS_MICRO;
  let t13 = t11 * t2 / _LOSS_MICRO;
  var series = t;
  series = series + t3 / 3;
  series = series + t5 / 5;
  series = series + t7 / 7;
  series = series + t9 / 9;
  series = series + t11 / 11;
  series = series + t13 / 13;
  let ln_m = series + series;
  let total = ln_m + k * _LOSS_LN2_1E9;
  return _div_round(total, _LOSS_VALUE_ONE);
}

// ---------------------------------------------------------------------------
// Leaf Result constructors
// ---------------------------------------------------------------------------

fn _ok_int(x: Int) -> Result[Int, Str] {
  return Ok(x);
}

fn _err_int(msg: Str) -> Result[Int, Str] {
  return Err(msg);
}

fn _ok_ints(v: Vec[Int]) -> Result[Vec[Int], Str] {
  return Ok(v);
}

fn _err_ints(msg: Str) -> Result[Vec[Int], Str] {
  return Err(msg);
}
