// XIOM -- xiom.svm: deterministic fixed-point linear SVM
// Port task: promote the xiom.svm placeholder to a real, tested, pure-XIOM
// package (fixed-point linear support vector machine on scaled integers: no
// floats, no FFI, no Vec[Float64], no threads).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model (pinned in SPEC.md, exercised by tests/test_conformance.xi):
//
//   - every real quantity is a fixed-point Int at scale 1e-4
//     (_SVM_SCALE = 10000): features, weights, the bias and decision scores
//     all share that scale.
//   - training is hinge-loss sub-gradient descent, applied online over a
//     per-epoch Fisher-Yates shuffle of the sample order. The shuffle draws
//     from one caller-seeded MINSTD LCG stream that is continuous across
//     epochs, so the same seed always reproduces the same model.
//   - the learning rate decays per applied update t:
//     eta_t = trunc(eta0 * 10000 / (10000 + decay * t)), t starting at 0.
//   - update for sample (x, y), y in {+1, -1}, applied when
//     y * score(x) < 10000:
//       w_j += trunc(eta_t * y * x_j / 10000); b += eta_t * y.
//   - prediction: +1 when the decision score is >= 0, else -1.
//   - support-vector count: samples whose margin lies in the band
//     |margin - 10000| <= band (_SVM_SCALE is the margin of a point on the
//     canonical hyperplane).
//   - accuracy: round-half-away-from-zero(correct * 10000 / n_rows),
//     reported in basis points.
//   - model dump: a deterministic text rendering (svm_dump).
//
// Layout notes that shaped this module (compiler v0.62.2):
//   * every Vec[Int] element read binds a typed local before use.
//   * no `&struct.field` is ever passed to a reference parameter: helpers
//     that need the weights receive a local copy from svm_weights (the same
//     workaround randomforest_predict uses for its class list).
//   * free functions only: no methods, no generics, no callbacks, no indexed
//     function-table dispatch; the model holds plain flat Vecs.
//   * Ok/Err construction is confined to the leaf helpers at the bottom.
//   * no Vec[Str] is used anywhere (v0.62.2 mis-lowers Vec[Str].push into a
//     store that clang rejects), and no Str value is compared in the library.
//   * multiply-before-divide steps are guarded; division is explicitly
//     truncated toward zero through a q/r helper (see SPEC.md "Arithmetic").
//
// Out of scope for v0.1.0: kernels, multi-class decomposition (one-vs-rest,
// one-vs-one), SMO, SVR and model serialization (the registry placeholder
// reserved them; they need a much larger API surface than this first cut).

module xiom.svm

use xiom.convert;

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

// Fixed-point scale: 10000 units = 1.0 (four decimal places).
const _SVM_SCALE: Int = 10000;
// Basis-point scale of the accuracy metric (10000 bps = 1.0).
const _SVM_BPS: Int = 10000;
// MINSTD (Park-Miller) LCG: state = (state * 48271) mod (2^31 - 1).
const _SVM_LCG_MULT: Int = 48271;
const _SVM_LCG_MOD: Int = 2147483647;
const _SVM_LCG_RANGE: Int = 2147483646;
const _SVM_INT_MAX: Int = 9223372036854775807;

// Documented configuration envelope (see SPEC.md, section "Envelope").
const _SVM_MAX_FEATURE: Int = 1000000000;
const _SVM_MAX_ETA: Int = 1000000000;
const _SVM_MAX_DECAY: Int = 1000000000;
const _SVM_MAX_ROWS: Int = 1000000;
const _SVM_MAX_FEATURES: Int = 4096;
const _SVM_MAX_EPOCHS: Int = 1000;
const _SVM_MAX_STEPS: Int = 1000000000;

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

/// A trained linear SVM in fixed-point arithmetic.
///
/// `weights` holds one scale-1e-4 weight per feature (weight `j` pairs with
/// feature column `j` of the training matrix); `bias` is the scale-1e-4 bias
/// term added to every decision score. Fields are internal implementation
/// detail; use the svm_* accessors.
pub type SvmModel = {
  n_features: Int;
  n_rows: Int;
  epochs: Int;
  learning_rate: Int;
  decay: Int;
  seed: Int;
  weights: Vec[Int];
  bias: Int;
}

// ---------------------------------------------------------------------------
// Constants and generator accessors
// ---------------------------------------------------------------------------

/// Fixed-point scale of every real quantity in the module (10000 = 1.0).
/// Complexity: O(1).
pub fn svm_scale() -> Int {
  return _SVM_SCALE;
}

/// Multiplier of the shuffling LCG (48271). Complexity: O(1).
pub fn svm_lcg_multiplier() -> Int {
  return _SVM_LCG_MULT;
}

/// Modulus of the shuffling LCG (2147483647 = 2^31 - 1). Complexity: O(1).
pub fn svm_lcg_modulus() -> Int {
  return _SVM_LCG_MOD;
}

/// Largest accepted feature magnitude (1000000000, i.e. 100000.0 at scale).
/// Complexity: O(1).
pub fn svm_max_feature() -> Int {
  return _SVM_MAX_FEATURE;
}

/// Largest accepted training row count (1000000). Complexity: O(1).
pub fn svm_max_rows() -> Int {
  return _SVM_MAX_ROWS;
}

/// Largest accepted feature count (4096). Complexity: O(1).
pub fn svm_max_features() -> Int {
  return _SVM_MAX_FEATURES;
}

/// Largest accepted epoch count (1000). Complexity: O(1).
pub fn svm_max_epochs() -> Int {
  return _SVM_MAX_EPOCHS;
}

/// Largest accepted initial learning rate (1000000000, i.e. 100000.0 at
/// scale). Complexity: O(1).
pub fn svm_max_eta() -> Int {
  return _SVM_MAX_ETA;
}

/// Largest accepted decay coefficient (1000000000). Complexity: O(1).
pub fn svm_max_decay() -> Int {
  return _SVM_MAX_DECAY;
}

// ---------------------------------------------------------------------------
// Shuffling LCG
// ---------------------------------------------------------------------------

/// One MINSTD LCG step on a normalized state.
///
/// The state is first normalized to [1, 2147483646]; the step is
/// state' = (state * 48271) mod 2147483647, always landing back in
/// [1, 2147483646] because the modulus is prime and 48271 is a primitive
/// root. Seeds are normalized by |seed mod 2147483646| + 1, so seed 0
/// normalizes to 1 and a seed and its negation produce the same stream
/// (documented; use a non-negative seed when this matters).
/// Complexity: O(1).
pub fn svm_lcg_step(state: Int) -> Int {
  let s = _svm_norm_lcg_state(state);
  return (s * _SVM_LCG_MULT) % _SVM_LCG_MOD;
}

/// Deterministic Fisher-Yates shuffle of `0 .. n-1`.
///
/// Params: seed - any Int (normalized as documented on svm_lcg_step);
///         n - permutation size (1 .. svm_max_rows()).
/// Returns: Ok(indices), a permutation of 0 .. n-1. The walk visits
/// i = n-1 down to 1; at each step the LCG advances once and
/// j = (state - 1) mod (i + 1), then indices[i] and indices[j] are swapped.
/// One LCG stream feeds the whole shuffle, so the result is a pure function
/// of (seed, n) on every run and platform.
/// Error case: Err("svm: shuffle size must be positive") for n <= 0 and
/// Err("svm: shuffle size exceeds the limit") past svm_max_rows().
/// Complexity: O(n).
pub fn svm_shuffle_indices(seed: Int, n: Int) -> Result[Vec[Int], Str] {
  if n <= 0 {
    return _err_ints("svm: shuffle size must be positive");
  }
  if n > _SVM_MAX_ROWS {
    return _err_ints("svm: shuffle size exceeds the limit");
  }
  var order = Vec[Int].new();
  var i = 0;
  while i < n {
    order.push(i);
    i = i + 1;
  }
  let state = _svm_norm_lcg_state(seed);
  let end_state = _svm_shuffle(&mut order, state);
  if end_state <= 0 {
    return _err_ints("svm: internal shuffle state");
  }
  return _ok_ints(order);
}

// ---------------------------------------------------------------------------
// Training
// ---------------------------------------------------------------------------

/// Train a linear SVM on a fixed-point labeled dataset.
///
/// Params: features - n_rows * n_features row-major scale-1e-4 feature
///         values (row r, feature f at r * n_features + f), read only;
///         n_rows - number of training rows (1 .. svm_max_rows());
///         n_features - features per row (1 .. svm_max_features());
///         labels - one label per row, each exactly +1 or -1;
///         epochs - number of shuffled passes (1 .. svm_max_epochs());
///         eta0 - initial learning rate at scale (1 .. svm_max_eta());
///         decay - learning-rate decay coefficient (0 .. svm_max_decay());
///         seed - LCG seed for the per-epoch shuffle.
/// Returns: Ok(SvmModel) with weights initialised to zero. For every epoch
/// the sample order is re-shuffled in place from one continuous LCG stream
/// (state seeded once) and every sample is visited in that order; the
/// update and schedule rules are documented on the module header.
/// Error case: Err("svm: ...") for any validation failure; the validation
/// order is matrix shape and magnitudes, labels, then epochs, eta0, decay.
/// Training itself can also fail closed with Err("svm: dot product
/// overflows"), Err("svm: score overflows"), Err("svm: weight update
/// overflows") or Err("svm: bias update overflows") when an intermediate
/// value leaves the documented envelope while the loop runs.
/// Complexity: O(epochs * n_rows * n_features).
pub fn svm_train(features: &Vec[Int], n_rows: Int, n_features: Int, labels: &Vec[Int], epochs: Int, eta0: Int, decay: Int, seed: Int) -> Result[SvmModel, Str] {
  let mchk = _svm_validate_matrix(features, n_rows, n_features);
  match mchk {
    Ok(_) => { },
    Err(e) => { return _err_model(e); },
  }
  let lchk = _svm_validate_labels(labels, n_rows);
  match lchk {
    Ok(_) => { },
    Err(e) => { return _err_model(e); },
  }
  if epochs <= 0 {
    return _err_model("svm: epoch count must be positive");
  }
  if epochs > _SVM_MAX_EPOCHS {
    return _err_model("svm: epoch count exceeds the limit");
  }
  if eta0 <= 0 {
    return _err_model("svm: initial learning rate must be positive");
  }
  if eta0 > _SVM_MAX_ETA {
    return _err_model("svm: initial learning rate exceeds the limit");
  }
  if decay < 0 {
    return _err_model("svm: decay must not be negative");
  }
  if decay > _SVM_MAX_DECAY {
    return _err_model("svm: decay exceeds the limit");
  }
  var weights = Vec[Int].new();
  var j = 0;
  while j < n_features {
    weights.push(0);
    j = j + 1;
  }
  var bias: Int = 0;
  var order = Vec[Int].new();
  var i = 0;
  while i < n_rows {
    order.push(i);
    i = i + 1;
  }
  var state = _svm_norm_lcg_state(seed);
  var step: Int = 0;
  var e = 0;
  while e < epochs {
    state = _svm_shuffle(&mut order, state);
    var r = 0;
    while r < n_rows {
      let si: Int = order[r];
      let scored = _svm_score_from(&weights, bias, features, si, n_features);
      var score: Int = 0;
      match scored {
        Ok(v) => { score = v; },
        Err(em) => { return _err_model(em); },
      }
      let y: Int = labels[si];
      var margin = 0;
      if y > 0 {
        margin = score;
      } else {
        margin = 0 - score;
      }
      if margin < _SVM_SCALE {
        let eta = _svm_eta_raw(eta0, decay, step);
        var jj = 0;
        while jj < n_features {
          let xj: Int = features[si * n_features + jj];
          let prod = eta * y * xj;
          let d = _svm_div_trunc(prod, _SVM_SCALE);
          let w: Int = weights[jj];
          if !_svm_add_ok(w, d) {
            return _err_model("svm: weight update overflows");
          }
          weights[jj] = w + d;
          jj = jj + 1;
        }
        let db = eta * y;
        if !_svm_add_ok(bias, db) {
          return _err_model("svm: bias update overflows");
        }
        bias = bias + db;
        step = step + 1;
      }
      r = r + 1;
    }
    e = e + 1;
  }
  return _ok_model(SvmModel{ n_features: n_features; n_rows: n_rows; epochs: epochs; learning_rate: eta0; decay: decay; seed: seed; weights: weights; bias: bias; });
}

// ---------------------------------------------------------------------------
// Model accessors
// ---------------------------------------------------------------------------

/// Number of features the model was trained on. Complexity: O(1).
pub fn svm_n_features(m: &SvmModel) -> Int {
  return m.n_features;
}

/// Number of training rows. Complexity: O(1).
pub fn svm_n_rows(m: &SvmModel) -> Int {
  return m.n_rows;
}

/// Number of training epochs. Complexity: O(1).
pub fn svm_epochs(m: &SvmModel) -> Int {
  return m.epochs;
}

/// Initial learning rate the model was trained with, at scale. Complexity:
/// O(1).
pub fn svm_initial_rate(m: &SvmModel) -> Int {
  return m.learning_rate;
}

/// Decay coefficient the model was trained with. Complexity: O(1).
pub fn svm_decay(m: &SvmModel) -> Int {
  return m.decay;
}

/// Raw LCG seed the model was trained with. Complexity: O(1).
pub fn svm_seed(m: &SvmModel) -> Int {
  return m.seed;
}

/// Bias term at scale. Complexity: O(1).
pub fn svm_bias(m: &SvmModel) -> Int {
  return m.bias;
}

/// Weight of feature `j`, or 0 when `j` is out of range (use
/// svm_n_features to range-check). Complexity: O(1).
pub fn svm_weight(m: &SvmModel, j: Int) -> Int {
  if j < 0 {
    return 0;
  }
  if j >= m.weights.len() {
    return 0;
  }
  let w: Int = m.weights[j];
  return w;
}

/// Copy of the whole weight vector (length svm_n_features(m)).
/// Complexity: O(n_features).
pub fn svm_weights(m: &SvmModel) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 0;
  while i < m.weights.len() {
    let w: Int = m.weights[i];
    out.push(w);
    i = i + 1;
  }
  return out;
}

// ---------------------------------------------------------------------------
// Learning-rate schedule
// ---------------------------------------------------------------------------

/// Learning rate at applied update `step`.
///
/// Params: eta0 - initial learning rate at scale (> 0 and <= svm_max_eta());
///         decay - decay coefficient (0 .. svm_max_decay());
///         step - number of updates already applied (0 .. 1000000000).
/// Returns: Ok(eta) = trunc(eta0 * 10000 / (10000 + decay * step)), an Int
/// at scale, truncated toward zero. decay = 0 keeps eta0 forever.
/// Error case: Err("svm: ...") for a non-positive / oversized eta0, a
/// negative / oversized decay, a negative step, or a step past
/// 1000000000.
/// Complexity: O(1).
pub fn svm_eta(eta0: Int, decay: Int, step: Int) -> Result[Int, Str] {
  if eta0 <= 0 {
    return _err_int("svm: initial learning rate must be positive");
  }
  if eta0 > _SVM_MAX_ETA {
    return _err_int("svm: initial learning rate exceeds the limit");
  }
  if decay < 0 {
    return _err_int("svm: decay must not be negative");
  }
  if decay > _SVM_MAX_DECAY {
    return _err_int("svm: decay exceeds the limit");
  }
  if step < 0 {
    return _err_int("svm: step must not be negative");
  }
  if step > _SVM_MAX_STEPS {
    return _err_int("svm: step exceeds the limit");
  }
  return _ok_int(_svm_eta_raw(eta0, decay, step));
}

// ---------------------------------------------------------------------------
// Scoring and margins
// ---------------------------------------------------------------------------

/// Decision score of one feature row: the model applied to `row_features`.
///
/// Params: m - a trained model; row_features - exactly svm_n_features(m)
///         scale-1e-4 values.
/// Returns: Ok(score) = trunc(sum_j w_j * x_j / 10000) + bias, at scale.
/// The inner sum is integer; the division truncates toward zero.
/// Error case: Err("svm: ...") for a row whose length or magnitude does not
/// fit the model envelope, or an overflowing dot product / score sum.
/// Complexity: O(n_features).
pub fn svm_score(m: &SvmModel, row_features: &Vec[Int]) -> Result[Int, Str] {
  if row_features.len() != m.n_features {
    return _err_int("svm: feature count does not match the model");
  }
  var j = 0;
  while j < row_features.len() {
    let x: Int = row_features[j];
    if x > _SVM_MAX_FEATURE || x < 0 - _SVM_MAX_FEATURE {
      return _err_int("svm: feature magnitude exceeds the limit");
    }
    j = j + 1;
  }
  let weights = svm_weights(m);
  let bias: Int = m.bias;
  return _svm_score_from(&weights, bias, row_features, 0, m.n_features);
}

/// Signed margin of one labeled row: label * score, at scale.
///
/// Params: m - a trained model; row_features - exactly svm_n_features(m)
///         values; label - exactly +1 or -1.
/// Returns: Ok(margin) = label * svm_score(m, row_features). A positive
/// margin means the row is on the correct side of the hyperplane; the
/// canonical hyperplane has margin 10000 (one unit at scale).
/// Error case: Err("svm: ...") for an invalid label or any score error.
/// Complexity: O(n_features).
pub fn svm_margin(m: &SvmModel, row_features: &Vec[Int], label: Int) -> Result[Int, Str] {
  if label != 1 && label != -1 {
    return _err_int("svm: label must be +1 or -1");
  }
  let scored = svm_score(m, row_features);
  var score: Int = 0;
  match scored {
    Ok(v) => { score = v; },
    Err(e) => { return _err_int(e); },
  }
  if label > 0 {
    return _ok_int(score);
  }
  return _ok_int(0 - score);
}

// ---------------------------------------------------------------------------
// Prediction, accuracy, support vectors
// ---------------------------------------------------------------------------

/// Predict one label per row: +1 when the decision score is >= 0, else -1.
///
/// Params: m - a trained model; features - n_rows * svm_n_features(m)
///         row-major values; n_rows - number of rows (1 .. svm_max_rows()).
/// Returns: Ok(predictions) with one label per row in input order.
/// Error case: Err("svm: ...") for any shape, magnitude or score error.
/// Complexity: O(n_rows * n_features).
pub fn svm_predict(m: &SvmModel, features: &Vec[Int], n_rows: Int) -> Result[Vec[Int], Str] {
  let mchk = _svm_validate_matrix(features, n_rows, m.n_features);
  match mchk {
    Ok(_) => { },
    Err(e) => { return _err_ints(e); },
  }
  let weights = svm_weights(m);
  let bias: Int = m.bias;
  var out = Vec[Int].new();
  var r = 0;
  while r < n_rows {
    let scored = _svm_score_from(&weights, bias, features, r, m.n_features);
    var score: Int = 0;
    match scored {
      Ok(v) => { score = v; },
      Err(e) => { return _err_ints(e); },
    }
    if score >= 0 {
      out.push(1);
    } else {
      out.push(-1);
    }
    r = r + 1;
  }
  return _ok_ints(out);
}

/// Signed margin of every row of a dataset, in input order.
///
/// Params: m - a trained model; features - n_rows * svm_n_features(m)
///         row-major values; n_rows (>= 1); labels - one label per row,
///         each +1 or -1.
/// Returns: Ok(margins) of length n_rows; entry r is
/// svm_margin(m, row r, labels[r]).
/// Error case: Err("svm: ...") for any shape, label, magnitude or score
/// error.
/// Complexity: O(n_rows * n_features).
pub fn svm_margins(m: &SvmModel, features: &Vec[Int], n_rows: Int, labels: &Vec[Int]) -> Result[Vec[Int], Str] {
  let mchk = _svm_validate_matrix(features, n_rows, m.n_features);
  match mchk {
    Ok(_) => { },
    Err(e) => { return _err_ints(e); },
  }
  let lchk = _svm_validate_labels(labels, n_rows);
  match lchk {
    Ok(_) => { },
    Err(e) => { return _err_ints(e); },
  }
  let weights = svm_weights(m);
  let bias: Int = m.bias;
  var out = Vec[Int].new();
  var r = 0;
  while r < n_rows {
    let y: Int = labels[r];
    let scored = _svm_score_from(&weights, bias, features, r, m.n_features);
    var score: Int = 0;
    match scored {
      Ok(v) => { score = v; },
      Err(e) => { return _err_ints(e); },
    }
    if y > 0 {
      out.push(score);
    } else {
      out.push(0 - score);
    }
    r = r + 1;
  }
  return _ok_ints(out);
}

/// Accuracy of the model over a labeled dataset, in basis points.
///
/// Params: m - a trained model; features - n_rows * svm_n_features(m)
///         row-major values; n_rows (>= 1); labels - one label per row,
///         each +1 or -1.
/// Returns: Ok(bps) = round_half_away_from_zero(correct * 10000 / n_rows),
/// where a row is correct when the predicted sign (+1 for score >= 0 else
/// -1) equals its label. 10000 means every row is correct.
/// Error case: Err("svm: ...") for any shape, label, magnitude or score
/// error.
/// Complexity: O(n_rows * n_features).
pub fn svm_accuracy(m: &SvmModel, features: &Vec[Int], n_rows: Int, labels: &Vec[Int]) -> Result[Int, Str] {
  let mchk = _svm_validate_matrix(features, n_rows, m.n_features);
  match mchk {
    Ok(_) => { },
    Err(e) => { return _err_int(e); },
  }
  let lchk = _svm_validate_labels(labels, n_rows);
  match lchk {
    Ok(_) => { },
    Err(e) => { return _err_int(e); },
  }
  let weights = svm_weights(m);
  let bias: Int = m.bias;
  var correct: Int = 0;
  var r = 0;
  while r < n_rows {
    let scored = _svm_score_from(&weights, bias, features, r, m.n_features);
    var score: Int = 0;
    match scored {
      Ok(v) => { score = v; },
      Err(e) => { return _err_int(e); },
    }
    var pred: Int = -1;
    if score >= 0 {
      pred = 1;
    }
    let y: Int = labels[r];
    if pred == y {
      correct = correct + 1;
    }
    r = r + 1;
  }
  return _ok_int(_svm_div_round(correct * _SVM_BPS, n_rows));
}

/// Number of support vectors: rows whose margin lies in the margin band.
///
/// Params: m - a trained model; features - n_rows * svm_n_features(m)
///         row-major values; n_rows (>= 1); labels - one label per row,
///         each +1 or -1; band - non-negative half-width at scale (0 ..
///         INT_MAX - 10000).
/// Returns: Ok(count) of rows with |margin - 10000| <= band, i.e. rows
/// within `band` scale units of the canonical margin. band = 0 counts only
/// the rows exactly on the canonical hyperplane; a very large band counts
/// every row.
/// Error case: Err("svm: ...") for any shape, label, magnitude or score
/// error, a negative band, or a band past the limit.
/// Complexity: O(n_rows * n_features).
pub fn svm_support_vector_count(m: &SvmModel, features: &Vec[Int], n_rows: Int, labels: &Vec[Int], band: Int) -> Result[Int, Str] {
  let mchk = _svm_validate_matrix(features, n_rows, m.n_features);
  match mchk {
    Ok(_) => { },
    Err(e) => { return _err_int(e); },
  }
  let lchk = _svm_validate_labels(labels, n_rows);
  match lchk {
    Ok(_) => { },
    Err(e) => { return _err_int(e); },
  }
  if band < 0 {
    return _err_int("svm: band must not be negative");
  }
  if band > _SVM_INT_MAX - _SVM_SCALE {
    return _err_int("svm: band exceeds the limit");
  }
  let lo = _SVM_SCALE - band;
  let hi = _SVM_SCALE + band;
  let weights = svm_weights(m);
  let bias: Int = m.bias;
  var count: Int = 0;
  var r = 0;
  while r < n_rows {
    let y: Int = labels[r];
    let scored = _svm_score_from(&weights, bias, features, r, m.n_features);
    var score: Int = 0;
    match scored {
      Ok(v) => { score = v; },
      Err(e) => { return _err_int(e); },
    }
    var margin = 0;
    if y > 0 {
      margin = score;
    } else {
      margin = 0 - score;
    }
    if margin >= lo && margin <= hi {
      count = count + 1;
    }
    r = r + 1;
  }
  return _ok_int(count);
}

// ---------------------------------------------------------------------------
// Model dump
// ---------------------------------------------------------------------------

/// Render a model as deterministic text.
///
/// Format (one trailing newline per line):
///
///   svm model: scale=S features=F epochs=E lr=L decay=D seed=Z rows=R
///   w0=...
///   w1=...
///   bias=B
///
/// Params: m - a trained model.
/// Returns: the text above; pure function of the model fields, so two
/// models trained with the same seed and shape dump identical text.
/// Complexity: O(n_features) plus string assembly.
pub fn svm_dump(m: &SvmModel) -> Str {
  var out = "svm model: scale=" + convert.int_to_string(_SVM_SCALE)
    + " features=" + convert.int_to_string(m.n_features)
    + " epochs=" + convert.int_to_string(m.epochs)
    + " lr=" + convert.int_to_string(m.learning_rate)
    + " decay=" + convert.int_to_string(m.decay)
    + " seed=" + convert.int_to_string(m.seed)
    + " rows=" + convert.int_to_string(m.n_rows)
    + "\n";
  var i = 0;
  while i < m.weights.len() {
    let w: Int = m.weights[i];
    out = out + "w" + convert.int_to_string(i) + "=" + convert.int_to_string(w) + "\n";
    i = i + 1;
  }
  out = out + "bias=" + convert.int_to_string(m.bias) + "\n";
  return out;
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

// Shared matrix validation: Ok(0) on success, Err(message) otherwise.
// Order: row count, feature count, row limit, dimensions, length, then the
// per-feature magnitude bound.
fn _svm_validate_matrix(features: &Vec[Int], n_rows: Int, n_features: Int) -> Result[Int, Str] {
  if n_rows <= 0 {
    return _err_int("svm: row count must be positive");
  }
  if n_features <= 0 {
    return _err_int("svm: feature count must be positive");
  }
  if n_rows > _SVM_MAX_ROWS {
    return _err_int("svm: dataset too large");
  }
  if n_features > _SVM_MAX_FEATURES {
    return _err_int("svm: feature count exceeds the limit");
  }
  if n_rows > _SVM_INT_MAX / n_features {
    return _err_int("svm: dimensions overflow");
  }
  if features.len() != n_rows * n_features {
    return _err_int("svm: features length does not match the shape");
  }
  var i = 0;
  while i < features.len() {
    let x: Int = features[i];
    if x > _SVM_MAX_FEATURE || x < 0 - _SVM_MAX_FEATURE {
      return _err_int("svm: feature magnitude exceeds the limit");
    }
    i = i + 1;
  }
  return _ok_int(0);
}

// Label validation: length then values (+1 / -1 only).
fn _svm_validate_labels(labels: &Vec[Int], n_rows: Int) -> Result[Int, Str] {
  if labels.len() != n_rows {
    return _err_int("svm: label count does not match row count");
  }
  var i = 0;
  while i < labels.len() {
    let y: Int = labels[i];
    if y != 1 && y != -1 {
      return _err_int("svm: labels must be +1 or -1");
    }
    i = i + 1;
  }
  return _ok_int(0);
}

// One LCG step on an already-normalized state, returning the new state.
// The state is threaded through return values (never a `&mut Int`
// parameter: v0.62.2 mis-lowered that into a value copy, which silently
// ignored the seed).
fn _svm_lcg_next(state: Int) -> Int {
  return (state * _SVM_LCG_MULT) % _SVM_LCG_MOD;
}

// Fisher-Yates shuffle of `order` in place; the LCG state is threaded
// through the return value so the caller owns the continuous stream.
// Progress: i strictly decreases from order.len() - 1 to 1.
fn _svm_shuffle(order: &mut Vec[Int], state0: Int) -> Int {
  var state = state0;
  var i = order.len() - 1;
  while i > 0 {
    state = _svm_lcg_next(state);
    let j = (state - 1) % (i + 1);
    let a: Int = order[i];
    let b: Int = order[j];
    order[i] = b;
    order[j] = a;
    i = i - 1;
  }
  return state;
}

// Decision score from a local weight vector and a bias. The weight vector is
// passed in (never `&m.weights`) because v0.62.2 mis-lowers a borrow of a
// struct field. Returns Ok(trunc(dot / scale) + bias).
fn _svm_score_from(weights: &Vec[Int], bias: Int, features: &Vec[Int], row: Int, n_features: Int) -> Result[Int, Str] {
  let dot = _svm_dot_weights(weights, features, row, n_features);
  var q: Int = 0;
  match dot {
    Ok(v) => { q = v; },
    Err(e) => { return _err_int(e); },
  }
  if !_svm_add_ok(q, bias) {
    return _err_int("svm: score overflows");
  }
  return _ok_int(q + bias);
}

// trunc(sum_j w_j * x_j / 10000) with per-term and accumulator overflow
// guards. Callers validate the matrix and its magnitudes.
fn _svm_dot_weights(weights: &Vec[Int], features: &Vec[Int], row: Int, n_features: Int) -> Result[Int, Str] {
  let base = row * n_features;
  var s: Int = 0;
  var j = 0;
  while j < n_features {
    let w: Int = weights[j];
    let x: Int = features[base + j];
    if x != 0 {
      let xa = _svm_abs(x);
      if _svm_abs(w) > _SVM_INT_MAX / xa {
        return _err_int("svm: dot product overflows");
      }
    }
    let term = w * x;
    if !_svm_add_ok(s, term) {
      return _err_int("svm: dot product overflows");
    }
    s = s + term;
    j = j + 1;
  }
  return _ok_int(_svm_div_trunc(s, _SVM_SCALE));
}

// Learning-rate schedule without validation. Callers guarantee
// 1 <= eta0 <= max_eta, 0 <= decay <= max_decay, 0 <= step <= max_steps.
fn _svm_eta_raw(eta0: Int, decay: Int, step: Int) -> Int {
  let num = eta0 * _SVM_SCALE;
  let den = _SVM_SCALE + decay * step;
  return _svm_div_trunc(num, den);
}

// Normalize any Int seed into [1, 2147483646]: |seed mod 2147483646| + 1.
fn _svm_norm_lcg_state(seed: Int) -> Int {
  var s = seed % _SVM_LCG_RANGE;
  if s < 0 {
    s = 0 - s;
  }
  return s + 1;
}

// Magnitude of a value known to be != INT_MIN (all callers are inside the
// documented envelope).
fn _svm_abs(x: Int) -> Int {
  if x < 0 {
    return 0 - x;
  }
  return x;
}

// True when a + b stays inside the symmetric envelope [-INT_MAX, INT_MAX].
fn _svm_add_ok(a: Int, b: Int) -> Bool {
  if b > 0 {
    if a > _SVM_INT_MAX - b {
      return false;
    }
    return true;
  }
  if b < 0 {
    if a < (0 - _SVM_INT_MAX) - b {
      return false;
    }
    return true;
  }
  return true;
}

// Division truncated toward zero, written in q/r form so the result is the
// same whichever convention the compiler's `/` and `%` use: if the
// remainder follows the dividend the quotient is already truncated; if it
// follows the divisor (floor convention) the quotient moves one step back
// toward zero. b must be non-zero.
fn _svm_div_trunc(a: Int, b: Int) -> Int {
  let q = a / b;
  let r = a % b;
  if r == 0 {
    return q;
  }
  let r_neg = r < 0;
  let a_neg = a < 0;
  if r_neg == a_neg {
    return q;
  }
  return q + 1;
}

// Division rounded half away from zero (b > 0). Same q/r shape as
// _svm_div_trunc; the doubling of |r| cannot overflow for the small
// numerators used here (accuracy: correct * 10000 <= 10^10).
fn _svm_div_round(a: Int, b: Int) -> Int {
  let q = _svm_div_trunc(a, b);
  let r = a - q * b;
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

// ---------------------------------------------------------------------------
// Leaf Result constructors
// ---------------------------------------------------------------------------

fn _ok_model(m: SvmModel) -> Result[SvmModel, Str] {
  return Ok(m);
}

fn _err_model(msg: Str) -> Result[SvmModel, Str] {
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
