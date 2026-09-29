// XIOM -- xiom.ensemble: fixed-point ensemble combination models
// Port task: replace the xiom.ensemble placeholder with a pure-XIOM module
// (scaled integers only: no floats, no FFI, no I/O, no Vec[Float64]).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model (pinned in SPEC.md, exercised by tests/test_conformance.xi):
//
//   - hard voting: every model casts one vote for a class label (Str); the
//     class with the most votes wins; ties are resolved by the documented
//     lowest-index rule (the class whose first occurrence in the input has
//     the lowest index wins); vote counts are reported per distinct class
//     in first-occurrence order.
//   - soft voting: one per-class probability vector per model (parallel
//     Vec[Int], one flat row-major vector), combined either by the
//     unweighted mean or by a weighted mean with caller-supplied integer
//     weights; every division rounds half away from zero.
//   - bootstrap resampling: a seeded MINSTD (Park-Miller) LCG with
//     multiplier 48271 and modulus 2^31 - 1 draws N sample indices with
//     replacement over a dataset size; the same seed always yields the
//     same indices on every run.
//   - bagging: averages parallel result vectors entry by entry, in order,
//     rounding half away from zero.
//   - disagreement: pairwise prediction diversity in basis points, both for
//     one model pair and pooled over all unordered pairs.
//   - weight normalization: rescales non-negative integer weights so that
//     they sum exactly to a caller scale (largest-remainder apportionment).
//
// Out of scope for v0.1.0: stacking and holdout blending (they need a
// meta-learner API that the registry placeholder reserved for this package).
//
// v0.62.1 notes that shaped this module:
//   * Str values are never compared with `==` (BUG 17 lowers `==` on Str
//     values read from Vec elements to a pointer comparison); every class
//     label comparison goes through string.str_compare with both sides
//     bound to typed locals first.
//   * every Vec[Int] / Vec[Str] element read binds the element to a typed
//     local before it is used.
//   * Ok/Err construction is confined to the leaf helpers at the bottom
//     (_ok_vote/_err_vote/_ok_ints/_err_ints/_ok_int/_err_int).
//   * free functions only: no methods, no generics, no callbacks, no
//     indexed function-table dispatch; struct fields are parallel Vecs.
//   * multiply-before-divide steps are guarded against Int overflow where
//     the operands are contractually non-negative; the exact envelope and
//     the unguarded paths are documented in SPEC.md.

module xiom.ensemble

use xiom.string;
use xiom.convert;

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

// Basis-point scale: 10000 bps = 1.0.
const _ENS_BPS: Int = 10000;
// MINSTD (Park-Miller) LCG: state = (state * 48271) mod (2^31 - 1).
const _ENS_LCG_MULT: Int = 48271;
const _ENS_LCG_MOD: Int = 2147483647;
const _ENS_LCG_RANGE: Int = 2147483646;
const _ENS_INT_MAX: Int = 9223372036854775807;

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

/// Result of a hard-vote tally.
///
/// `classes` holds the distinct class labels in first-occurrence order and
/// `counts` is parallel to it: counts[k] is the number of models that voted
/// for classes[k]. `winner` and `winner_count` repeat the winning class and
/// its count; on a tie the lowest index in `classes` (that is, the earliest
/// first occurrence in the input) wins. `n_models` is the number of ballots
/// and `n_classes` equals classes.len().
///
/// Fields are internal implementation detail; use the ensemble_vote_*
/// accessors.
pub type VoteResult = {
  winner: Str;
  winner_count: Int;
  classes: Vec[Str];
  counts: Vec[Int];
  n_models: Int;
  n_classes: Int;
}

// ---------------------------------------------------------------------------
// Scale and generator constants
// ---------------------------------------------------------------------------

/// Basis-point scale of the disagreement metrics (10000). Complexity: O(1).
pub fn ensemble_bps() -> Int {
  return _ENS_BPS;
}

/// Multiplier of the bootstrap LCG (48271). Complexity: O(1).
pub fn ensemble_lcg_multiplier() -> Int {
  return _ENS_LCG_MULT;
}

/// Modulus of the bootstrap LCG (2147483647 = 2^31 - 1). Complexity: O(1).
pub fn ensemble_lcg_modulus() -> Int {
  return _ENS_LCG_MOD;
}

// ---------------------------------------------------------------------------
// Hard voting
// ---------------------------------------------------------------------------

/// Majority vote over per-model class labels.
///
/// Params: labels - one class label per model (read only); must not be empty.
/// Returns: Ok(VoteResult) with the distinct labels in first-occurrence
/// order, their vote counts, the winner and its count.
/// Tie rule: when two or more classes share the maximum count, the class
/// with the lowest index in `classes` wins (the earliest first occurrence in
/// `labels`), so the result is deterministic and independent of any
/// dictionary order.
/// Error case: Err("ensemble: labels must not be empty") for an empty input.
/// Complexity: O(n^2) comparisons in the number of ballots.
pub fn ensemble_hard_vote(labels: &Vec[Str]) -> Result[VoteResult, Str] {
  let n = labels.len();
  if n <= 0 {
    return _err_vote("ensemble: labels must not be empty");
  }
  var classes = Vec[Str].new();
  var counts = Vec[Int].new();
  var i = 0;
  while i < n {
    let label: Str = labels[i];
    var found = -1;
    var k = 0;
    while k < classes.len() {
      let known: Str = classes[k];
      if string.str_compare(known, label) == 0 {
        found = k;
      }
      k = k + 1;
    }
    if found < 0 {
      classes.push(label);
      counts.push(1);
    } else {
      let old: Int = counts[found];
      counts[found] = old + 1;
    }
    i = i + 1;
  }
  var best = 0;
  var t = 1;
  while t < counts.len() {
    let c: Int = counts[t];
    let b: Int = counts[best];
    if c > b {
      best = t;
    }
    t = t + 1;
  }
  let winner: Str = classes[best];
  let winner_count: Int = counts[best];
  let n_classes = classes.len();
  return _ok_vote(VoteResult{ winner: winner; winner_count: winner_count; classes: classes; counts: counts; n_models: n; n_classes: n_classes; });
}

/// Winning class label. Complexity: O(1).
pub fn ensemble_vote_winner(result: &VoteResult) -> Str {
  let w: Str = result.winner;
  return w;
}

/// Vote count of the winning class. Complexity: O(1).
pub fn ensemble_vote_winner_count(result: &VoteResult) -> Int {
  return result.winner_count;
}

/// Number of ballots tallied. Complexity: O(1).
pub fn ensemble_vote_n_models(result: &VoteResult) -> Int {
  return result.n_models;
}

/// Number of distinct classes seen. Complexity: O(1).
pub fn ensemble_vote_n_classes(result: &VoteResult) -> Int {
  return result.n_classes;
}

/// Class label at position `k` in first-occurrence order, or "" when `k` is
/// out of range. Complexity: O(1).
pub fn ensemble_vote_class(result: &VoteResult, k: Int) -> Str {
  if k < 0 {
    return "";
  }
  if k >= result.classes.len() {
    return "";
  }
  let s: Str = result.classes[k];
  return s;
}

/// Vote count at position `k`, or 0 when `k` is out of range.
/// Complexity: O(1).
pub fn ensemble_vote_count(result: &VoteResult, k: Int) -> Int {
  if k < 0 {
    return 0;
  }
  if k >= result.counts.len() {
    return 0;
  }
  let c: Int = result.counts[k];
  return c;
}

/// Index of `label` in the tally's first-occurrence order, or -1 when the
/// label was not seen. Comparison uses string.str_compare.
/// Complexity: O(classes).
pub fn ensemble_vote_class_index(result: &VoteResult, label: Str) -> Int {
  var i = 0;
  while i < result.classes.len() {
    let known: Str = result.classes[i];
    if string.str_compare(known, label) == 0 {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// ---------------------------------------------------------------------------
// Soft voting
// ---------------------------------------------------------------------------

/// Unweighted soft vote: per-class mean of the per-model probability vectors.
///
/// Params: probs - n_models rows of n_classes per-class probabilities,
///         row-major (model i, class j at i * n_classes + j), each >= 0 and
///         expressed in any common integer scale (basis points recommended);
///         n_models - number of models (> 0);
///         n_classes - number of classes per model (> 0).
/// Returns: Ok(combined) with one entry per class; entry j is
/// round_half_away_from_zero(sum_i probs[i, j] / n_models).
/// Validation order: dimensions, then length.
/// Error case: Err("ensemble: ...") for a non-positive model or class count,
/// a dimensions overflow, a length mismatch, a negative probability, or a
/// probability sum that overflows Int.
/// Complexity: O(n_models * n_classes).
pub fn ensemble_soft_vote(probs: &Vec[Int], n_models: Int, n_classes: Int) -> Result[Vec[Int], Str] {
  if n_models <= 0 {
    return _err_ints("ensemble: model count must be positive");
  }
  if n_classes <= 0 {
    return _err_ints("ensemble: class count must be positive");
  }
  if n_models > _ENS_INT_MAX / n_classes {
    return _err_ints("ensemble: dimensions overflow");
  }
  if probs.len() != n_models * n_classes {
    return _err_ints("ensemble: probability length does not match the shape");
  }
  var out = Vec[Int].new();
  var j = 0;
  while j < n_classes {
    var s: Int = 0;
    var i = 0;
    while i < n_models {
      let p: Int = probs[i * n_classes + j];
      if p < 0 {
        return _err_ints("ensemble: probabilities must not be negative");
      }
      if p > _ENS_INT_MAX - s {
        return _err_ints("ensemble: probability sum overflows");
      }
      s = s + p;
      i = i + 1;
    }
    out.push(_div_round(s, n_models));
    j = j + 1;
  }
  return _ok_ints(out);
}

/// Weighted soft vote: per-class weighted mean of the probability vectors.
///
/// Params: probs - n_models rows of n_classes probabilities, row-major,
///         each >= 0; weights - one non-negative integer weight per model,
///         with a positive total; n_models / n_classes - shape (> 0).
/// Returns: Ok(combined) with entry j =
/// round_half_away_from_zero(sum_i (probs[i, j] * weights[i]) / sum_i
/// weights[i]).
/// Validation order: dimensions, probabilities length, weights length,
/// weights (non-negative, positive sum), probabilities (non-negative),
/// weighted products (overflow), weighted sums (overflow).
/// Error case: Err("ensemble: ...") for a non-positive count, a dimensions
/// overflow, a length mismatch, a negative weight, a non-positive weight
/// sum, a negative probability, or a weighted product / sum that overflows
/// Int.
/// Complexity: O(n_models * n_classes).
pub fn ensemble_soft_vote_weighted(probs: &Vec[Int], weights: &Vec[Int], n_models: Int, n_classes: Int) -> Result[Vec[Int], Str] {
  if n_models <= 0 {
    return _err_ints("ensemble: model count must be positive");
  }
  if n_classes <= 0 {
    return _err_ints("ensemble: class count must be positive");
  }
  if n_models > _ENS_INT_MAX / n_classes {
    return _err_ints("ensemble: dimensions overflow");
  }
  if probs.len() != n_models * n_classes {
    return _err_ints("ensemble: probability length does not match the shape");
  }
  if weights.len() != n_models {
    return _err_ints("ensemble: weight count does not match model count");
  }
  var total: Int = 0;
  var i = 0;
  while i < n_models {
    let w: Int = weights[i];
    if w < 0 {
      return _err_ints("ensemble: weights must not be negative");
    }
    if w > _ENS_INT_MAX - total {
      return _err_ints("ensemble: weight sum overflows");
    }
    total = total + w;
    i = i + 1;
  }
  if total <= 0 {
    return _err_ints("ensemble: weight sum must be positive");
  }
  var out = Vec[Int].new();
  var j = 0;
  while j < n_classes {
    var s: Int = 0;
    var k = 0;
    while k < n_models {
      let p: Int = probs[k * n_classes + j];
      if p < 0 {
        return _err_ints("ensemble: probabilities must not be negative");
      }
      let w: Int = weights[k];
      if w > 0 {
        if p > _ENS_INT_MAX / w {
          return _err_ints("ensemble: weighted product overflows");
        }
      }
      let term = p * w;
      if term > _ENS_INT_MAX - s {
        return _err_ints("ensemble: weighted sum overflows");
      }
      s = s + term;
      k = k + 1;
    }
    out.push(_div_round(s, total));
    j = j + 1;
  }
  return _ok_ints(out);
}

// ---------------------------------------------------------------------------
// Bootstrap resampling
// ---------------------------------------------------------------------------

/// One MINSTD LCG step on a normalized state.
///
/// The state is first normalized to [1, 2147483646]; the step is
/// state' = (state * 48271) mod 2147483647, always landing back in
/// [1, 2147483646] because the modulus is prime and 48271 is a primitive
/// root. Seeds are normalized by |seed mod 2147483646| + 1, so 0 maps to 1
/// and a seed and its negation produce the same stream (documented; use a
/// non-negative seed when this matters).
/// Complexity: O(1).
pub fn ensemble_lcg_step(state: Int) -> Int {
  let s = _norm_lcg_state(state);
  return (s * _ENS_LCG_MULT) % _ENS_LCG_MOD;
}

/// Deterministic bootstrap sample indices with replacement.
///
/// Params: seed - any Int (normalized as documented on ensemble_lcg_step);
///         dataset_size - number of rows to sample from (> 0);
///         n_samples - number of indices to draw (>= 0; 0 yields Ok(empty)).
/// Returns: Ok(indices) of length n_samples; index k is
/// (state_k - 1) mod dataset_size, where state_0 = |seed mod 2147483646| + 1
/// and state_{k+1} = (state_k * 48271) mod 2147483647. The LCG constants are
/// exposed by ensemble_lcg_multiplier / ensemble_lcg_modulus. The same seed
/// and shape always produce the same vector, on every run and platform.
/// Error case: Err("ensemble: ...") for a non-positive dataset size or a
/// negative sample count.
/// Complexity: O(n_samples).
pub fn ensemble_bootstrap_indices(seed: Int, dataset_size: Int, n_samples: Int) -> Result[Vec[Int], Str] {
  if dataset_size <= 0 {
    return _err_ints("ensemble: dataset size must be positive");
  }
  if n_samples < 0 {
    return _err_ints("ensemble: sample count must not be negative");
  }
  var state = _norm_lcg_state(seed);
  var out = Vec[Int].new();
  var i = 0;
  while i < n_samples {
    state = (state * _ENS_LCG_MULT) % _ENS_LCG_MOD;
    out.push((state - 1) % dataset_size);
    i = i + 1;
  }
  return _ok_ints(out);
}

// ---------------------------------------------------------------------------
// Bagging
// ---------------------------------------------------------------------------

/// Bagging combine: entry-wise mean of parallel result vectors.
///
/// Params: vectors - n_vectors result vectors of per_vector entries each,
///         laid out row-major (vector i, entry j at i * per_vector + j);
///         n_vectors - number of vectors (> 0); per_vector - entries per
///         vector (> 0).
/// Returns: Ok(combined) of length per_vector; entry j is
/// round_half_away_from_zero(sum_i vectors[i, j] / n_vectors). Entries are
/// signed and no overflow is detected: keep n_vectors times the entry
/// magnitude inside Int (see SPEC.md for the envelope).
/// Error case: Err("ensemble: ...") for a non-positive count, a dimensions
/// overflow, or a length mismatch.
/// Complexity: O(n_vectors * per_vector).
pub fn ensemble_bagging_combine(vectors: &Vec[Int], n_vectors: Int, per_vector: Int) -> Result[Vec[Int], Str] {
  if n_vectors <= 0 {
    return _err_ints("ensemble: vector count must be positive");
  }
  if per_vector <= 0 {
    return _err_ints("ensemble: vector length must be positive");
  }
  if n_vectors > _ENS_INT_MAX / per_vector {
    return _err_ints("ensemble: dimensions overflow");
  }
  if vectors.len() != n_vectors * per_vector {
    return _err_ints("ensemble: vectors length does not match the shape");
  }
  var out = Vec[Int].new();
  var j = 0;
  while j < per_vector {
    var s: Int = 0;
    var i = 0;
    while i < n_vectors {
      let v: Int = vectors[i * per_vector + j];
      s = s + v;
      i = i + 1;
    }
    out.push(_div_round(s, n_vectors));
    j = j + 1;
  }
  return _ok_ints(out);
}

// ---------------------------------------------------------------------------
// Disagreement / diversity
// ---------------------------------------------------------------------------

/// Pairwise disagreement of two models, in basis points.
///
/// Params: predictions - n_models rows of n_samples integer class ids,
///         row-major (model i, sample s at i * n_samples + s); n_models /
///         n_samples - shape (> 0); i / j - two distinct model indices in
///         [0, n_models).
/// Returns: Ok(bps) = round_half_away_from_zero(count * 10000 / n_samples),
/// where count is the number of sample positions at which models i and j
/// predict different ids. 0 means identical, 10000 means fully different.
/// Validation order: shape, prediction length, index range, index
/// distinctness, scale overflow.
/// Error case: Err("ensemble: ...") for a non-positive count, a dimensions
/// overflow, a length mismatch, an out-of-range index, equal indices, or a
/// sample count too large for the basis-point scaling.
/// Complexity: O(n_samples).
pub fn ensemble_pair_disagreement_bps(predictions: &Vec[Int], n_models: Int, n_samples: Int, i: Int, j: Int) -> Result[Int, Str] {
  if n_models <= 0 {
    return _err_int("ensemble: model count must be positive");
  }
  if n_samples <= 0 {
    return _err_int("ensemble: sample count must be positive");
  }
  if n_models > _ENS_INT_MAX / n_samples {
    return _err_int("ensemble: dimensions overflow");
  }
  if predictions.len() != n_models * n_samples {
    return _err_int("ensemble: predictions length does not match the shape");
  }
  if i < 0 || i >= n_models {
    return _err_int("ensemble: model index out of range");
  }
  if j < 0 || j >= n_models {
    return _err_int("ensemble: model index out of range");
  }
  if i == j {
    return _err_int("ensemble: model indices must be distinct");
  }
  if n_samples > _ENS_INT_MAX / _ENS_BPS {
    return _err_int("ensemble: disagreement scale overflows");
  }
  let count = _pair_disagree_count(predictions, n_samples, i, j);
  return _ok_int(_div_round(count * _ENS_BPS, n_samples));
}

/// Mean pairwise disagreement over all unordered model pairs, in basis
/// points (the diversity metric of the ensemble).
///
/// Params: predictions - n_models rows of n_samples integer class ids,
///         row-major; n_models (>= 2) and n_samples (> 0).
/// Returns: Ok(bps) = round_half_away_from_zero(D * 10000 / (P * n_samples))
/// where P = n_models * (n_models - 1) / 2 pairs and D is the total number
/// of disagreeing (model, sample) counts over all pairs. This pools every
/// pair and sample before a single rounding, so it is not the mean of the
/// per-pair rounded values.
/// Error case: Err("ensemble: ...") for fewer than 2 models, a non-positive
/// sample count, a dimensions / count overflow, or a length mismatch.
/// Complexity: O(n_models^2 * n_samples).
pub fn ensemble_disagreement_bps(predictions: &Vec[Int], n_models: Int, n_samples: Int) -> Result[Int, Str] {
  if n_models < 2 {
    return _err_int("ensemble: need at least 2 models");
  }
  if n_samples <= 0 {
    return _err_int("ensemble: sample count must be positive");
  }
  if n_models > _ENS_INT_MAX / n_samples {
    return _err_int("ensemble: dimensions overflow");
  }
  if predictions.len() != n_models * n_samples {
    return _err_int("ensemble: predictions length does not match the shape");
  }
  if n_models - 1 > _ENS_INT_MAX / n_models {
    return _err_int("ensemble: dimensions overflow");
  }
  let pairs = n_models * (n_models - 1) / 2;
  if pairs > _ENS_INT_MAX / n_samples {
    return _err_int("ensemble: dimensions overflow");
  }
  var total: Int = 0;
  var i = 0;
  while i < n_models {
    var j = i + 1;
    while j < n_models {
      let c = _pair_disagree_count(predictions, n_samples, i, j);
      if c > _ENS_INT_MAX - total {
        return _err_int("ensemble: disagreement count overflows");
      }
      total = total + c;
      j = j + 1;
    }
    i = i + 1;
  }
  let denom = pairs * n_samples;
  if total > _ENS_INT_MAX / _ENS_BPS {
    return _err_int("ensemble: disagreement scale overflows");
  }
  return _ok_int(_div_round(total * _ENS_BPS, denom));
}

// ---------------------------------------------------------------------------
// Weight helpers
// ---------------------------------------------------------------------------

/// Plain arithmetic sum of `weights` (no validation, no overflow detection:
/// see SPEC.md for the envelope). Empty input yields 0. Complexity: O(n).
pub fn ensemble_weight_sum(weights: &Vec[Int]) -> Int {
  var total: Int = 0;
  var i = 0;
  while i < weights.len() {
    let w: Int = weights[i];
    total = total + w;
    i = i + 1;
  }
  return total;
}

/// Normalize non-negative weights so that they sum exactly to `scale`.
///
/// Params: weights - non-negative integer weights, at least one positive;
///         scale - target sum (> 0).
/// Returns: Ok(normalized) with normalized.len() == weights.len() and
/// sum(normalized) == scale exactly. Apportionment: base_i = floor(w_i *
/// scale / total), then the residual (scale - sum(base)) units, an integer
/// in [0, n - 1], go one each to the entries with the largest remainders
/// (w_i * scale mod total); equal remainders favor the lowest index. This
/// is the largest-remainder (Hamilton) apportionment; a zero weight always
/// normalizes to zero.
/// Validation order: emptiness, scale positivity, per-weight non-negativity
/// and sum overflow, zero sum, per-weight product overflow.
/// Error case: Err("ensemble: ...") for an empty input, a non-positive
/// scale, a negative weight, a weight-sum or weight*scale overflow, or a
/// zero weight sum.
/// Complexity: O(n * residual) <= O(n^2).
pub fn ensemble_normalize_weights(weights: &Vec[Int], scale: Int) -> Result[Vec[Int], Str] {
  let n = weights.len();
  if n <= 0 {
    return _err_ints("ensemble: weights must not be empty");
  }
  if scale <= 0 {
    return _err_ints("ensemble: scale must be positive");
  }
  var total: Int = 0;
  var i = 0;
  while i < n {
    let w: Int = weights[i];
    if w < 0 {
      return _err_ints("ensemble: weights must not be negative");
    }
    if w > _ENS_INT_MAX - total {
      return _err_ints("ensemble: weight sum overflows");
    }
    total = total + w;
    i = i + 1;
  }
  if total <= 0 {
    return _err_ints("ensemble: weight sum must be positive");
  }
  var base = Vec[Int].new();
  var rem = Vec[Int].new();
  var assigned: Int = 0;
  i = 0;
  while i < n {
    let w: Int = weights[i];
    if w > 0 {
      if scale > _ENS_INT_MAX / w {
        return _err_ints("ensemble: weight scale overflows");
      }
    }
    let raw = w * scale;
    let q = raw / total;
    let r = raw % total;
    base.push(q);
    rem.push(r);
    assigned = assigned + q;
    i = i + 1;
  }
  let need = scale - assigned;
  var used = Vec[Int].new();
  i = 0;
  while i < n {
    used.push(0);
    i = i + 1;
  }
  var k = 0;
  while k < need {
    var best = -1;
    var best_rem: Int = -1;
    var t = 0;
    while t < n {
      let flag: Int = used[t];
      if flag == 0 {
        let rr: Int = rem[t];
        if rr > best_rem {
          best_rem = rr;
          best = t;
        }
      }
      t = t + 1;
    }
    if best < 0 {
      return _err_ints("ensemble: weight normalization failed");
    }
    let b: Int = base[best];
    base[best] = b + 1;
    used[best] = 1;
    k = k + 1;
  }
  return _ok_ints(base);
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

// Truncating division with halves rounded away from zero (b > 0). The
// doubled remainder cannot overflow for the small denominators used here
// (n_models, n_vectors, weight totals, n_samples); see SPEC.md.
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

// Normalize any Int seed into [1, 2147483646]: |seed mod 2147483646| + 1.
// Using the range one below the modulus keeps the result in [1, modulus-1]
// for every input, including 0 and negative seeds.
fn _norm_lcg_state(seed: Int) -> Int {
  var s = seed % _ENS_LCG_RANGE;
  if s < 0 {
    s = 0 - s;
  }
  return s + 1;
}

// Number of sample positions at which models i and j differ (0 <= count <=
// n_samples). Callers validate the shape and the indices.
fn _pair_disagree_count(predictions: &Vec[Int], n_samples: Int, i: Int, j: Int) -> Int {
  let base_i = i * n_samples;
  let base_j = j * n_samples;
  var count: Int = 0;
  var s = 0;
  while s < n_samples {
    let x: Int = predictions[base_i + s];
    let y: Int = predictions[base_j + s];
    if x != y {
      count = count + 1;
    }
    s = s + 1;
  }
  return count;
}

// ---------------------------------------------------------------------------
// Leaf Result constructors
// ---------------------------------------------------------------------------

fn _ok_vote(v: VoteResult) -> Result[VoteResult, Str] {
  return Ok(v);
}

fn _err_vote(msg: Str) -> Result[VoteResult, Str] {
  return Err(msg);
}

fn _ok_ints(v: Vec[Int]) -> Result[Vec[Int], Str] {
  return Ok(v);
}

fn _err_ints(msg: Str) -> Result[Vec[Int], Str] {
  return Err(msg);
}

fn _ok_int(x: Int) -> Result[Int, Str] {
  return Ok(x);
}

fn _err_int(msg: Str) -> Result[Int, Str] {
  return Err(msg);
}
