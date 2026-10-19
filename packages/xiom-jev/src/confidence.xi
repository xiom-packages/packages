// XIOM -- xiom.jev.confidence: S6 confidence formulas and composite scoring
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure, transport-free statistics over the package's micro-unit core.
//
// S6 confidence (SPEC.md section 19.1):
//
//   * Choice: confidence = (p_max - 1/n) / (1 - 1/n), clamped to [0,1].
//     Only the top probability counts.
//   * Score:  confidence = max(0, 1 - spread / MAD_unif) where
//     spread = sum_i p_i * |i - m|, m is the maximum-probability index
//     (lowest index on a tie), and
//     MAD_unif = (1/n) * sum_i |i - (n-1)/2|.
//     n == 1 is certain (1.0) and divides by nothing.
//   * The formulas run in Float64; the result is clamped and rounded
//     half-up to micro ONCE at the end.
//
// Inputs are probability distributions in micro units (1.0 = 1000000),
// matching the package's parsed answers.
//
// Composite scoring (SPEC.md section 19.3):
//
//   result = round_half_up( sum_i s_i * w_i / sum_i w_i )
//
// with integer scores s_i in [0, MICRO] and integer weights w_i >= 0.
// Products and sums are widened to Float64 so Int overflow cannot occur.
// Validation failures are typed BadRequest errors.
//
// All helpers are pure: no I/O, no transport, no hidden state.

module xiom.jev.confidence

use xiom.jev.errors;
use xiom.jev.types;
use xiom.math;

// --------------------------------------------------
//  S6 confidence
// --------------------------------------------------

/// confidence_choice_micro is the Choice confidence for a micro-unit
/// probability distribution: (p_max - 1/n) / (1 - 1/n), clamped to [0,1]
/// and rounded half-up to micro once at the end. Only the top probability
/// counts. An empty distribution returns 0; a single option is certain.
/// Complexity: O(n). Pure.
pub fn confidence_choice_micro(probabilities: &Vec[Int]) -> Int {
  let n: Int = probabilities.len();
  if n <= 0 { return 0; }
  if n == 1 { return types.MICRO; }
  var pmax: Int = probabilities[0];
  var i: Int = 1;
  while i < n {
    if probabilities[i] > pmax { pmax = probabilities[i]; }
    i = i + 1;
  }
  let nf: Float64 = n as Float64;
  let p: Float64 = (pmax as Float64) / 1000000.0;
  let even: Float64 = 1.0 / nf;
  var c: Float64 = (p - even) / (1.0 - even);
  if c < 0.0 { c = 0.0; }
  if c > 1.0 { c = 1.0; }
  return math.round(c * 1000000.0);
}

/// confidence_score_micro is the Score confidence for a micro-unit
/// probability distribution: max(0, 1 - spread / MAD_unif) with
/// m = the maximum-probability index (lowest index on a tie),
/// spread = sum_i p_i * |i - m|, and
/// MAD_unif = (1/n) * sum_i |i - (n-1)/2|.
/// The result is clamped to [0,1] and rounded half-up to micro once at the
/// end. n == 1 returns 1.0; an empty distribution returns 0.
/// Complexity: O(n). Pure.
pub fn confidence_score_micro(probabilities: &Vec[Int]) -> Int {
  let n: Int = probabilities.len();
  if n <= 0 { return 0; }
  if n == 1 { return types.MICRO; }

  // m = argmax, lowest index on a tie (strict > keeps the first).
  var m: Int = 0;
  var i: Int = 1;
  while i < n {
    if probabilities[i] > probabilities[m] { m = i; }
    i = i + 1;
  }

  let nf: Float64 = n as Float64;
  let center: Float64 = (nf - 1.0) / 2.0;
  var spread: Float64 = 0.0;
  var mad_sum: Float64 = 0.0;
  i = 0;
  while i < n {
    let p: Float64 = (probabilities[i] as Float64) / 1000000.0;
    var d: Float64 = (i as Float64) - (m as Float64);
    if d < 0.0 { d = -d; }
    spread = spread + p * d;
    var e: Float64 = (i as Float64) - center;
    if e < 0.0 { e = -e; }
    mad_sum = mad_sum + e;
    i = i + 1;
  }

  let mad_unif: Float64 = mad_sum / nf;
  if mad_unif <= 0.0 { return types.MICRO; }
  var c: Float64 = 1.0 - spread / mad_unif;
  if c < 0.0 { c = 0.0; }
  if c > 1.0 { c = 1.0; }
  return math.round(c * 1000000.0);
}

// --------------------------------------------------
//  Composite scoring
// --------------------------------------------------

/// composite_weights_valid is true when `weights` is non-empty, every weight
/// is >= 0, and the sum of the weights is greater than zero.
/// Complexity: O(n). Pure.
pub fn composite_weights_valid(weights: &Vec[Int]) -> Bool {
  let n: Int = weights.len();
  if n == 0 { return false; }
  var total: Float64 = 0.0;
  var i: Int = 0;
  while i < n {
    let w: Int = weights[i];
    if w < 0 { return false; }
    total = total + (w as Float64);
    i = i + 1;
  }
  if total <= 0.0 { return false; }
  return true;
}

/// composite_score_micro combines micro-unit scores with integer weights:
/// round_half_up( sum_i s_i * w_i / sum_i w_i ), clamped to [0, MICRO] and
/// rounded once at the end. Products and sums are widened to Float64.
///
/// Typed BadRequest guards (checked in this order):
///   scores or weights empty       -> "composite: no scores"
///   lengths differ                -> "composite: length mismatch"
///   score outside [0, MICRO]      -> "composite: score out of range"
///   negative weight               -> "composite: negative weight"
///   sum of weights == 0           -> "composite: all weights are zero"
///
/// Complexity: O(n). Pure.
pub fn composite_score_micro(scores: &Vec[Int], weights: &Vec[Int]) -> Result[Int, JevError] {
  let n: Int = scores.len();
  if n == 0 || weights.len() == 0 {
    return Err(JevError.BadRequest("composite: no scores"));
  }
  if n != weights.len() {
    return Err(JevError.BadRequest("composite: length mismatch"));
  }
  var weighted: Float64 = 0.0;
  var total: Float64 = 0.0;
  var i: Int = 0;
  while i < n {
    let s: Int = scores[i];
    if s < 0 || s > types.MICRO {
      return Err(JevError.BadRequest("composite: score out of range"));
    }
    let w: Int = weights[i];
    if w < 0 {
      return Err(JevError.BadRequest("composite: negative weight"));
    }
    weighted = weighted + (s as Float64) * (w as Float64);
    total = total + (w as Float64);
    i = i + 1;
  }
  if total <= 0.0 {
    return Err(JevError.BadRequest("composite: all weights are zero"));
  }
  var c: Float64 = weighted / total;
  if c < 0.0 { c = 0.0; }
  if c > (types.MICRO as Float64) { c = types.MICRO as Float64; }
  return Ok(math.round(c));
}
