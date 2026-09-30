// XIOM -- xiom.boosting: deterministic gradient boosting over integer data
// Port task: replace the xiom.boosting placeholder with a pure-XIOM module
// (fixed-point integers only: no floats, no FFI, no threads, no I/O).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model (pinned in SPEC.md, exercised by tests/test_conformance.xi):
//
//   - fixed point: every target, residual, prediction and leaf value is an
//     Int in units of 1e-4 (scale 10000). Rounding on division truncates
//     toward zero (v0.62.x Int division), documented per step in SPEC.md.
//   - base learner: a depth-limited (0..2) regression tree over integer
//     features. A split tests one feature f against an integer threshold t:
//     samples with value <= t go left, the rest go right. Candidate
//     thresholds are the distinct values of the feature inside the node.
//   - split score (regression / squared error): for a node sample with
//     residual sum, a candidate split into left (sum SL, nL samples) and
//     right (SR, nR) is scored by S = floor(SL/nL)*SL + floor(SR/nR)*SR
//     (truncating division); larger S is better (it approximates the
//     between-group squared mean, i.e. the SSE reduction). Ties keep the
//     earliest candidate: lowest feature index, then lowest threshold.
//   - leaf value: the truncated mean residual of the node sample. A leaf is
//     reached when depth == max_depth or the node holds fewer than two
//     samples.
//   - boosting: prediction starts at the truncated global mean (the base).
//     Each stage fits one tree to the current residuals and every row is
//     updated by contribution = floor(lr_bp * leaf_value / 10000), with
//     lr_bp the learning rate in basis points (10000 = 1.0, capped at
//     10000 so the shrinkage never exceeds 1.0). With lr_bp <= 10000 the
//     total squared error never increases, so staged loss is monotone.
//   - subsampling: a caller-seeded MINSTD (Park-Miller) LCG (multiplier
//     48271, modulus 2^31 - 1) drives an optional row subsample (drawn with
//     replacement) and an optional feature subsample (partial Fisher-Yates,
//     without replacement). One continuous stream spans all stages. With
//     both subsamples disabled the LCG is never consulted, so the model is
//     identical for every seed.
//   - staged predictions: predictions after each of the first k stages.
//   - loss trace: the mean squared error after 0..n_stages stages, in
//     squared fixed-point units (1e-8), truncated.
//   - feature importance: split-node counts per feature.
//   - model dump: a deterministic text rendering of the additive model.
//
// Layout notes that shaped this module (compiler v0.62.2):
//   * all traversals are iterative with explicit stacks and a node budget;
//     the module contains no recursion at all.
//   * every Vec[Int] element read binds the value to a typed local first;
//     no Str values are compared anywhere in this module.
//   * a Model carries one flat Vec[Int] of fixed-stride nodes instead of
//     parallel vectors (no Vec[StructType], no drift between vectors).
//   * free functions only: no methods, no generics, no callbacks, no
//     indexed function-table dispatch.
//   * multiply-before-add score steps are guarded by a documented row-count
//     and residual envelope (see SPEC.md); no silent overflow path exists.

module xiom.boosting

use xiom.convert;

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

// Flat node layout: every node occupies _BST_NODE_STRIDE consecutive slots.
const _BST_NODE_STRIDE: Int = 8;
const _BST_NODE_FEATURE: Int = 0;    // split feature, -1 for a leaf
const _BST_NODE_THRESHOLD: Int = 1;  // left branch when value <= threshold
const _BST_NODE_LEFT: Int = 2;       // left child node index, -1 for a leaf
const _BST_NODE_RIGHT: Int = 3;      // right child node index, -1 for a leaf
const _BST_NODE_VALUE: Int = 4;      // leaf value (fixed point); node mean otherwise
const _BST_NODE_COUNT: Int = 5;      // training samples at the node
const _BST_NODE_LEAF: Int = 6;       // 1 for a leaf, 0 for a split node
const _BST_NODE_DEPTH: Int = 7;      // root depth is 0

// Fixed-point scale: one unit is 1e-4; basis points are 1e-2.
const _BST_SCALE: Int = 10000;
const _BST_BPS: Int = 10000;

// MINSTD (Park-Miller) LCG: state = (state * 48271) mod (2^31 - 1).
const _BST_LCG_MULT: Int = 48271;
const _BST_LCG_MOD: Int = 2147483647;
const _BST_LCG_RANGE: Int = 2147483646;
const _BST_INT_MAX: Int = 9223372036854775807;

// Documented configuration envelope (see SPEC.md, section "Envelope").
const _BST_MAX_ROWS: Int = 4096;
const _BST_MAX_STAGES: Int = 64;
const _BST_MAX_DEPTH: Int = 2;
const _BST_LR_MAX: Int = 10000;
const _BST_VALUE_MAX: Int = 100000;      // |target|, in fixed-point units
const _BST_RESIDUAL_MAX: Int = 30000000; // working residual envelope
const _BST_DIFF_MAX: Int = 3000000000;   // loss-difference envelope

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

/// A trained additive model (gradient boosting with shrinkage).
///
/// `base` is the fixed-point intercept; `lr_bp` the learning rate in basis
/// points; `tree_root[t]` is the index of stage t's root node inside
/// `nodes`. Trees occupy consecutive node ranges in stage order. `nodes` is
/// a flat vector: node k occupies slots
/// k * boosting_node_stride() + field, with the field offsets documented on
/// the boosting_node_* accessors.
///
/// Fields are internal implementation detail; use the accessors.
pub type Model = {
  n_features: Int;
  n_stages: Int;
  lr_bp: Int;
  base: Int;
  tree_root: Vec[Int];
  nodes: Vec[Int];
}

// ---------------------------------------------------------------------------
// Constants and generator accessors
// ---------------------------------------------------------------------------

/// Fixed-point scale (10000 units = 1.0). Complexity: O(1).
pub fn boosting_scale() -> Int {
  return _BST_SCALE;
}

/// Basis-point scale (10000 bps = 1.0). Complexity: O(1).
pub fn boosting_bps() -> Int {
  return _BST_BPS;
}

/// Multiplier of the subsampling LCG (48271). Complexity: O(1).
pub fn boosting_lcg_multiplier() -> Int {
  return _BST_LCG_MULT;
}

/// Modulus of the subsampling LCG (2147483647 = 2^31 - 1). Complexity: O(1).
pub fn boosting_lcg_modulus() -> Int {
  return _BST_LCG_MOD;
}

/// Largest accepted tree depth (2). Complexity: O(1).
pub fn boosting_max_depth_limit() -> Int {
  return _BST_MAX_DEPTH;
}

/// Largest accepted training row count (4096). Complexity: O(1).
pub fn boosting_max_rows() -> Int {
  return _BST_MAX_ROWS;
}

/// Largest accepted stage count (64). Complexity: O(1).
pub fn boosting_max_stages() -> Int {
  return _BST_MAX_STAGES;
}

/// Largest accepted learning rate in basis points (10000 = 1.0). O(1).
pub fn boosting_lr_max() -> Int {
  return _BST_LR_MAX;
}

/// Largest accepted absolute target value in fixed-point units (100000 =
/// 10.0). Complexity: O(1).
pub fn boosting_value_max() -> Int {
  return _BST_VALUE_MAX;
}

/// Number of Int slots per node in a Model's flat node vector (8). O(1).
pub fn boosting_node_stride() -> Int {
  return _BST_NODE_STRIDE;
}

// ---------------------------------------------------------------------------
// Subsampling LCG
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
pub fn boosting_lcg_step(state: Int) -> Int {
  let s = _norm_lcg_state(state);
  return (s * _BST_LCG_MULT) % _BST_LCG_MOD;
}

/// Deterministic sample indices with replacement.
///
/// Params: seed - any Int (normalized as documented on boosting_lcg_step);
///         dataset_size - number of rows to sample from (> 0);
///         n_samples - number of indices to draw (>= 0; 0 yields Ok(empty)).
/// Returns: Ok(indices) of length n_samples; index k (1-based) is
/// (state_k - 1) mod dataset_size, where state_0 = |seed mod 2147483646| + 1
/// and state_{k+1} = (state_k * 48271) mod 2147483647. The same seed and
/// shape always produce the same vector, on every run and platform.
/// Error case: Err("boosting: ...") for a non-positive dataset size or a
/// negative sample count.
/// Complexity: O(n_samples).
pub fn boosting_subsample_indices(seed: Int, dataset_size: Int, n_samples: Int) -> Result[Vec[Int], Str] {
  if dataset_size <= 0 {
    return _err_ints("boosting: dataset size must be positive");
  }
  if n_samples < 0 {
    return _err_ints("boosting: sample count must not be negative");
  }
  var state = _norm_lcg_state(seed);
  var out = Vec[Int].new();
  var i = 0;
  while i < n_samples {
    state = (state * _BST_LCG_MULT) % _BST_LCG_MOD;
    out.push((state - 1) % dataset_size);
    i = i + 1;
  }
  return _ok_ints(out);
}

// ---------------------------------------------------------------------------
// Training
// ---------------------------------------------------------------------------

/// Train an additive gradient-boosting model on integer data.
///
/// Params: features - n_rows * n_features row-major integer feature values
///         (row r, feature f at r * n_features + f), read only;
///         n_rows - number of training rows (> 0, <= boosting_max_rows());
///         n_features - number of features per row (> 0);
///         targets - one fixed-point target per row (targets.len() ==
///         n_rows; each in [-boosting_value_max(), boosting_value_max()]);
///         n_stages - number of boosting stages (1..=64);
///         max_depth - tree depth bound (0..=2; a node at depth max_depth is
///         a leaf, root depth = 0);
///         lr_bp - learning rate in basis points (1..=10000; 10000 = 1.0);
///         row_subsample - rows drawn per stage with replacement: 0 uses all
///         rows in order, otherwise 1..=n_rows;
///         feature_subsample - features considered per stage (partial
///         Fisher-Yates without replacement): 0 uses all features in order,
///         otherwise 1..=n_features;
///         seed - LCG seed; the row and feature subsampling share one
///         continuous stream across stages, so the model is reproducible.
/// Returns: Ok(Model) with n_stages trees sharing one flat node vector. When
/// both subsamples are 0 the LCG is never consulted and the result is
/// independent of the seed.
/// Error case: Err("boosting: ...") for any validation failure; the
/// validation order is data shape (including target range), stage count,
/// depth, learning rate, row subsample, feature subsample.
/// Complexity: O(n_stages * build) with build
/// O(n_rows * selected_features * distinct-values) per node.
pub fn boosting_train(features: &Vec[Int], n_rows: Int, n_features: Int, targets: &Vec[Int], n_stages: Int, max_depth: Int, lr_bp: Int, row_subsample: Int, feature_subsample: Int, seed: Int) -> Result[Model, Str] {
  let chk = _validate_data(features, n_rows, n_features, targets);
  match chk {
    Ok(_) => { },
    Err(e) => { return _err_model(e); },
  }
  if n_stages <= 0 {
    return _err_model("boosting: stage count must be positive");
  }
  if n_stages > _BST_MAX_STAGES {
    return _err_model("boosting: stage count exceeds the limit");
  }
  if max_depth < 0 {
    return _err_model("boosting: max depth must not be negative");
  }
  if max_depth > _BST_MAX_DEPTH {
    return _err_model("boosting: max depth exceeds the limit");
  }
  if lr_bp < 1 {
    return _err_model("boosting: learning rate must be positive");
  }
  if lr_bp > _BST_LR_MAX {
    return _err_model("boosting: learning rate exceeds the limit");
  }
  if row_subsample < 0 {
    return _err_model("boosting: row subsample must not be negative");
  }
  if row_subsample > n_rows {
    return _err_model("boosting: row subsample exceeds the row count");
  }
  if feature_subsample < 0 {
    return _err_model("boosting: feature subsample must not be negative");
  }
  if feature_subsample > n_features {
    return _err_model("boosting: feature subsample exceeds the feature count");
  }
  // Intercept: the truncated global mean (rounding toward zero).
  var total: Int = 0;
  var i = 0;
  while i < n_rows {
    let t: Int = targets[i];
    total = total + t;
    i = i + 1;
  }
  let base = total / n_rows;
  var pred = Vec[Int].new();
  var residual = Vec[Int].new();
  i = 0;
  while i < n_rows {
    let t: Int = targets[i];
    pred.push(base);
    residual.push(t - base);
    i = i + 1;
  }
  var nodes = Vec[Int].new();
  var roots = Vec[Int].new();
  var state = _norm_lcg_state(seed);
  var s = 0;
  while s < n_stages {
    // Row subsample.
    var row_idx = Vec[Int].new();
    if row_subsample == 0 {
      var r2 = 0;
      while r2 < n_rows {
        row_idx.push(r2);
        r2 = r2 + 1;
      }
    } else {
      var r2 = 0;
      while r2 < row_subsample {
        state = (state * _BST_LCG_MULT) % _BST_LCG_MOD;
        row_idx.push((state - 1) % n_rows);
        r2 = r2 + 1;
      }
    }
    // Feature subsample (partial Fisher-Yates, without replacement).
    var feat_idx = Vec[Int].new();
    if feature_subsample == 0 {
      var f2 = 0;
      while f2 < n_features {
        feat_idx.push(f2);
        f2 = f2 + 1;
      }
    } else {
      var pool = Vec[Int].new();
      var f2 = 0;
      while f2 < n_features {
        pool.push(f2);
        f2 = f2 + 1;
      }
      var k2 = 0;
      while k2 < feature_subsample {
        state = (state * _BST_LCG_MULT) % _BST_LCG_MOD;
        let j = k2 + (state % (n_features - k2));
        let a: Int = pool[k2];
        let b: Int = pool[j];
        pool[k2] = b;
        pool[j] = a;
        k2 = k2 + 1;
      }
      f2 = 0;
      while f2 < feature_subsample {
        let x: Int = pool[f2];
        feat_idx.push(x);
        f2 = f2 + 1;
      }
    }
    let built = _build_stage_into(&mut nodes, features, n_features, &residual, &row_idx, &feat_idx, max_depth);
    var root: Int = -1;
    match built {
      Ok(x) => { root = x; },
      Err(e) => { return _err_model(e); },
    }
    roots.push(root);
    // Apply the stage: shrink the leaf value and refresh residuals.
    var rr = 0;
    while rr < n_rows {
      let leaf_value = _tree_leaf_value_nodes(&nodes, root, features, rr, n_features);
      let contrib = (lr_bp * leaf_value) / _BST_BPS;
      let p: Int = pred[rr];
      let updated = p + contrib;
      pred[rr] = updated;
      let tgt: Int = targets[rr];
      let new_res = tgt - updated;
      if new_res > _BST_RESIDUAL_MAX {
        return _err_model("boosting: residual overflow");
      }
      if new_res < 0 - _BST_RESIDUAL_MAX {
        return _err_model("boosting: residual overflow");
      }
      residual[rr] = new_res;
      rr = rr + 1;
    }
    s = s + 1;
  }
  return _ok_model(Model{ n_features: n_features; n_stages: n_stages; lr_bp: lr_bp; base: base; tree_root: roots; nodes: nodes; });
}

// ---------------------------------------------------------------------------
// Model accessors
// ---------------------------------------------------------------------------

/// Number of boosting stages (trees). Complexity: O(1).
pub fn boosting_n_stages(m: &Model) -> Int {
  return m.n_stages;
}

/// Number of features the model was trained on. Complexity: O(1).
pub fn boosting_n_features(m: &Model) -> Int {
  return m.n_features;
}

/// Learning rate in basis points. Complexity: O(1).
pub fn boosting_lr_bp(m: &Model) -> Int {
  return m.lr_bp;
}

/// Fixed-point intercept (truncated global mean). Complexity: O(1).
pub fn boosting_base(m: &Model) -> Int {
  return m.base;
}

/// Number of nodes across all stages. Complexity: O(1).
pub fn boosting_n_nodes(m: &Model) -> Int {
  return m.nodes.len() / _BST_NODE_STRIDE;
}

/// Root node index of stage t, or -1 when t is out of range. O(1).
pub fn boosting_tree_root(m: &Model, t: Int) -> Int {
  if t < 0 {
    return -1;
  }
  if t >= m.tree_root.len() {
    return -1;
  }
  let x: Int = m.tree_root[t];
  return x;
}

/// Number of nodes in stage t's tree, or 0 when t is out of range. O(1).
pub fn boosting_tree_n_nodes(m: &Model, t: Int) -> Int {
  if t < 0 || t >= m.n_stages {
    return 0;
  }
  let start: Int = m.tree_root[t];
  var end = m.nodes.len() / _BST_NODE_STRIDE;
  if t + 1 < m.n_stages {
    let e: Int = m.tree_root[t + 1];
    end = e;
  }
  return end - start;
}

/// Maximum node depth of stage t's tree (root depth 0), or -1 when t is out
/// of range. Complexity: O(nodes of stage t).
pub fn boosting_tree_depth(m: &Model, t: Int) -> Int {
  if t < 0 || t >= m.n_stages {
    return -1;
  }
  let start: Int = m.tree_root[t];
  let count = boosting_tree_n_nodes(m, t);
  var deepest = -1;
  var i = 0;
  while i < count {
    let base: Int = (start + i) * _BST_NODE_STRIDE;
    let d: Int = m.nodes[base + _BST_NODE_DEPTH];
    if d > deepest {
      deepest = d;
    }
    i = i + 1;
  }
  return deepest;
}

// ---------------------------------------------------------------------------
// Node accessors
// ---------------------------------------------------------------------------

/// True when node k is a leaf, false for a split node and out-of-range
/// indices. Complexity: O(1).
pub fn boosting_is_leaf(m: &Model, k: Int) -> Bool {
  if k < 0 {
    return false;
  }
  if k >= m.nodes.len() / _BST_NODE_STRIDE {
    return false;
  }
  let l: Int = m.nodes[k * _BST_NODE_STRIDE + _BST_NODE_LEAF];
  if l == 1 {
    return true;
  }
  return false;
}

/// Split feature of node k; -1 for a leaf, -2 when k is out of range. O(1).
pub fn boosting_node_feature(m: &Model, k: Int) -> Int {
  if k < 0 {
    return -2;
  }
  if k >= m.nodes.len() / _BST_NODE_STRIDE {
    return -2;
  }
  return _model_field(m, k, _BST_NODE_FEATURE);
}

/// Split threshold of node k (left branch when value <= threshold); 0 for a
/// leaf and out-of-range indices. Complexity: O(1).
pub fn boosting_node_threshold(m: &Model, k: Int) -> Int {
  if k < 0 {
    return 0;
  }
  if k >= m.nodes.len() / _BST_NODE_STRIDE {
    return 0;
  }
  return _model_field(m, k, _BST_NODE_THRESHOLD);
}

/// Left child of node k, or -1 for a leaf and out-of-range indices. O(1).
pub fn boosting_node_left(m: &Model, k: Int) -> Int {
  if k < 0 {
    return -1;
  }
  if k >= m.nodes.len() / _BST_NODE_STRIDE {
    return -1;
  }
  return _model_field(m, k, _BST_NODE_LEFT);
}

/// Right child of node k, or -1 for a leaf and out-of-range indices. O(1).
pub fn boosting_node_right(m: &Model, k: Int) -> Int {
  if k < 0 {
    return -1;
  }
  if k >= m.nodes.len() / _BST_NODE_STRIDE {
    return -1;
  }
  return _model_field(m, k, _BST_NODE_RIGHT);
}

/// Fixed-point value of node k (leaf value; node mean for a split node), or
/// 0 when k is out of range. Complexity: O(1).
pub fn boosting_node_value(m: &Model, k: Int) -> Int {
  if k < 0 {
    return 0;
  }
  if k >= m.nodes.len() / _BST_NODE_STRIDE {
    return 0;
  }
  return _model_field(m, k, _BST_NODE_VALUE);
}

/// Training sample count of node k, or 0 when k is out of range. O(1).
pub fn boosting_node_count(m: &Model, k: Int) -> Int {
  if k < 0 {
    return 0;
  }
  if k >= m.nodes.len() / _BST_NODE_STRIDE {
    return 0;
  }
  return _model_field(m, k, _BST_NODE_COUNT);
}

/// Depth of node k (root depth 0), or -1 when k is out of range. O(1).
pub fn boosting_node_depth(m: &Model, k: Int) -> Int {
  if k < 0 {
    return -1;
  }
  if k >= m.nodes.len() / _BST_NODE_STRIDE {
    return -1;
  }
  return _model_field(m, k, _BST_NODE_DEPTH);
}

// ---------------------------------------------------------------------------
// Prediction
// ---------------------------------------------------------------------------

/// Predict one row with the full additive model.
///
/// Params: m - a model; row_features - exactly m.n_features feature values.
/// Returns: Ok(value) = base + sum over all stages t of
/// floor(m.lr_bp * leaf_value(t, row) / 10000), in fixed-point units.
/// Error case: Err("boosting: ...") for a row whose feature count does not
/// match the model.
/// Complexity: O(n_stages * tree depth).
pub fn boosting_predict_row(m: &Model, row_features: &Vec[Int]) -> Result[Int, Str] {
  if row_features.len() != m.n_features {
    return _err_int("boosting: feature count does not match the model");
  }
  var acc = m.base;
  var t = 0;
  while t < m.n_stages {
    let leaf_value = _tree_leaf_value_model(m, t, row_features);
    acc = acc + (m.lr_bp * leaf_value) / _BST_BPS;
    t = t + 1;
  }
  return _ok_int(acc);
}

/// Predict n_rows rows with the full additive model.
///
/// Params: m - a model; features - n_rows * m.n_features row-major feature
///         values; n_rows - number of rows (> 0).
/// Returns: Ok(predictions) with one fixed-point value per row.
/// Error case: Err("boosting: ...") for a non-positive row count, a model
/// with no features, a dimensions overflow, or a length mismatch.
/// Complexity: O(n_rows * n_stages * tree depth).
pub fn boosting_predict(m: &Model, features: &Vec[Int], n_rows: Int) -> Result[Vec[Int], Str] {
  if n_rows <= 0 {
    return _err_ints("boosting: row count must be positive");
  }
  if m.n_features <= 0 {
    return _err_ints("boosting: model has no features");
  }
  if n_rows > _BST_INT_MAX / m.n_features {
    return _err_ints("boosting: dimensions overflow");
  }
  if features.len() != n_rows * m.n_features {
    return _err_ints("boosting: features length does not match the shape");
  }
  var out = Vec[Int].new();
  var r = 0;
  while r < n_rows {
    var acc = m.base;
    var t = 0;
    while t < m.n_stages {
      let leaf_value = _tree_leaf_value_model_row(m, t, features, r);
      acc = acc + (m.lr_bp * leaf_value) / _BST_BPS;
      t = t + 1;
    }
    out.push(acc);
    r = r + 1;
  }
  return _ok_ints(out);
}

/// Staged predictions: the running prediction after each stage.
///
/// Params: m - a model; features - n_rows * m.n_features row-major feature
///         values; n_rows - number of rows (> 0); n_stages - number of
///         stages to run (1..=m.n_stages).
/// Returns: Ok(staged) of length n_rows * n_stages, laid out stage-major:
/// entry s * n_rows + r is the prediction for row r after s + 1 stages
/// (stage 0's entry already includes the base). With n_stages ==
/// m.n_stages and n_rows rows, the last block equals boosting_predict.
/// Error case: Err("boosting: ...") for a non-positive row count, a model
/// with no features, a stage count outside 1..=m.n_stages, a dimensions
/// overflow, or a length mismatch.
/// Complexity: O(n_stages * n_rows * tree depth).
pub fn boosting_predict_staged(m: &Model, features: &Vec[Int], n_rows: Int, n_stages: Int) -> Result[Vec[Int], Str] {
  if n_rows <= 0 {
    return _err_ints("boosting: row count must be positive");
  }
  if m.n_features <= 0 {
    return _err_ints("boosting: model has no features");
  }
  if n_stages <= 0 {
    return _err_ints("boosting: stage count must be positive");
  }
  if n_stages > m.n_stages {
    return _err_ints("boosting: stage count exceeds the model");
  }
  if n_rows > _BST_INT_MAX / m.n_features {
    return _err_ints("boosting: dimensions overflow");
  }
  if features.len() != n_rows * m.n_features {
    return _err_ints("boosting: features length does not match the shape");
  }
  var preds = Vec[Int].new();
  var r = 0;
  while r < n_rows {
    preds.push(m.base);
    r = r + 1;
  }
  var out = Vec[Int].new();
  var s = 0;
  while s < n_stages {
    r = 0;
    while r < n_rows {
      let leaf_value = _tree_leaf_value_model_row(m, s, features, r);
      let cur: Int = preds[r];
      preds[r] = cur + (m.lr_bp * leaf_value) / _BST_BPS;
      r = r + 1;
    }
    r = 0;
    while r < n_rows {
      let p: Int = preds[r];
      out.push(p);
      r = r + 1;
    }
    s = s + 1;
  }
  return _ok_ints(out);
}

/// Per-stage loss trace: mean squared error after 0..n_stages stages.
///
/// Params: m - a model; features - n_rows * m.n_features row-major feature
///         values; n_rows - number of rows (> 0, each target in
///         [-boosting_value_max(), boosting_value_max()]);
///         targets - one fixed-point target per row (targets.len() ==
///         n_rows).
/// Returns: Ok(trace) of length m.n_stages + 1; trace[0] is the MSE of the
/// intercept alone and trace[s] the MSE after s stages. The loss is the sum
/// of squared residuals divided by n_rows (truncated), in squared fixed-point
/// units (1e-8). With lr_bp <= 10000 the sequence is non-increasing.
/// Error case: Err("boosting: ...") for a non-positive row count, a model
/// with no features, a dimensions overflow, a length mismatch, a target out
/// of range, or a squared-error sum that would overflow Int.
/// Complexity: O(n_stages * n_rows * tree depth).
pub fn boosting_loss_trace(m: &Model, features: &Vec[Int], n_rows: Int, targets: &Vec[Int]) -> Result[Vec[Int], Str] {
  if n_rows <= 0 {
    return _err_ints("boosting: row count must be positive");
  }
  if m.n_features <= 0 {
    return _err_ints("boosting: model has no features");
  }
  if n_rows > _BST_INT_MAX / m.n_features {
    return _err_ints("boosting: dimensions overflow");
  }
  if features.len() != n_rows * m.n_features {
    return _err_ints("boosting: features length does not match the shape");
  }
  if targets.len() != n_rows {
    return _err_ints("boosting: target count does not match row count");
  }
  var i = 0;
  while i < n_rows {
    let t: Int = targets[i];
    if t > _BST_VALUE_MAX {
      return _err_ints("boosting: target out of range");
    }
    if t < 0 - _BST_VALUE_MAX {
      return _err_ints("boosting: target out of range");
    }
    i = i + 1;
  }
  var preds = Vec[Int].new();
  var r = 0;
  while r < n_rows {
    preds.push(m.base);
    r = r + 1;
  }
  var out = Vec[Int].new();
  let l0 = _mse_res(&preds, targets, n_rows);
  match l0 {
    Ok(x) => { out.push(x); },
    Err(e) => { return _err_ints(e); },
  }
  var s = 0;
  while s < m.n_stages {
    r = 0;
    while r < n_rows {
      let leaf_value = _tree_leaf_value_model_row(m, s, features, r);
      let cur: Int = preds[r];
      preds[r] = cur + (m.lr_bp * leaf_value) / _BST_BPS;
      r = r + 1;
    }
    let ls = _mse_res(&preds, targets, n_rows);
    match ls {
      Ok(x) => { out.push(x); },
      Err(e) => { return _err_ints(e); },
    }
    s = s + 1;
  }
  return _ok_ints(out);
}

// ---------------------------------------------------------------------------
// Feature importance
// ---------------------------------------------------------------------------

/// Raw feature importance: the number of split nodes that use each feature.
///
/// Returns: a vector of length m.n_features; entry j is the number of split
/// nodes (across all stages) whose split feature is j. Leaves contribute
/// nothing. Stable under retraining with the same seed.
/// Complexity: O(n_nodes).
pub fn boosting_feature_importance(m: &Model) -> Vec[Int] {
  var out = Vec[Int].new();
  var c = 0;
  while c < m.n_features {
    out.push(0);
    c = c + 1;
  }
  let n_nodes = m.nodes.len() / _BST_NODE_STRIDE;
  var i = 0;
  while i < n_nodes {
    let base: Int = i * _BST_NODE_STRIDE;
    let feat: Int = m.nodes[base + _BST_NODE_FEATURE];
    if feat >= 0 {
      let cur: Int = out[feat];
      out[feat] = cur + 1;
    }
    i = i + 1;
  }
  return out;
}

// ---------------------------------------------------------------------------
// Model dump
// ---------------------------------------------------------------------------

/// Render the additive model as deterministic text.
///
/// Format (one trailing newline per line; node lines in pre-order with the
/// left child first; two spaces of indentation per depth level):
///
///   model: stages=S features=F lr_bp=L base=B
///   tree T: nodes=N depth=D
///   [k] fF <= TH (n=C, value=V)
///     [k] leaf value=V (n=C)
///
/// Returns: Ok(text) as described above. Each tree walk is iterative and
/// bounded by its node count, so a corrupt model cannot loop.
/// Error case: Err("boosting: ...") when a walk exceeds its visit budget.
/// Complexity: O(n_nodes) plus string assembly.
pub fn boosting_dump(m: &Model) -> Result[Str, Str] {
  var out = "model: stages=" + convert.int_to_string(m.n_stages) + " features=" + convert.int_to_string(m.n_features) + " lr_bp=" + convert.int_to_string(m.lr_bp) + " base=" + convert.int_to_string(m.base) + "\n";
  var t = 0;
  while t < m.n_stages {
    let root: Int = m.tree_root[t];
    let n_tree = boosting_tree_n_nodes(m, t);
    let depth_tree = boosting_tree_depth(m, t);
    out = out + "tree " + convert.int_to_string(t) + ": nodes=" + convert.int_to_string(n_tree) + " depth=" + convert.int_to_string(depth_tree) + "\n";
    var stack_node = Vec[Int].new();
    var stack_indent = Vec[Int].new();
    stack_node.push(root);
    stack_indent.push(0);
    var budget = n_tree + 1;
    while stack_node.len() > 0 {
      if budget <= 0 {
        return _err_str("boosting: dump budget exceeded");
      }
      budget = budget - 1;
      let pk = stack_node.pop();
      var k: Int = -1;
      match pk {
        Some(x) => { k = x; },
        None => { return _err_str("boosting: internal stack underflow"); },
      }
      let pi = stack_indent.pop();
      var indent: Int = 0;
      match pi {
        Some(x) => { indent = x; },
        None => { return _err_str("boosting: internal stack underflow"); },
      }
      out = out + _dump_line(m, k, indent);
      let leaf: Bool = boosting_is_leaf(m, k);
      if !leaf {
        let l: Int = boosting_node_left(m, k);
        let rr: Int = boosting_node_right(m, k);
        stack_node.push(rr);
        stack_indent.push(indent + 1);
        stack_node.push(l);
        stack_indent.push(indent + 1);
      }
    }
    t = t + 1;
  }
  return _ok_str(out);
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

// Render one node line (see boosting_dump for the format).
fn _dump_line(m: &Model, k: Int, indent: Int) -> Str {
  var pad = "";
  var i = 0;
  while i < indent {
    pad = pad + "  ";
    i = i + 1;
  }
  let feat: Int = boosting_node_feature(m, k);
  let value: Int = boosting_node_value(m, k);
  let count: Int = boosting_node_count(m, k);
  var line = pad + "[" + convert.int_to_string(k) + "] ";
  if feat < 0 {
    return line + "leaf value=" + convert.int_to_string(value) + " (n=" + convert.int_to_string(count) + ")\n";
  }
  let thr: Int = boosting_node_threshold(m, k);
  return line + "f" + convert.int_to_string(feat) + " <= " + convert.int_to_string(thr) + " (n=" + convert.int_to_string(count) + ", value=" + convert.int_to_string(value) + ")\n";
}

// Read one field of node k. The caller range-checks k.
fn _model_field(m: &Model, k: Int, field: Int) -> Int {
  return m.nodes[k * _BST_NODE_STRIDE + field];
}

// Walk stage t's tree for row r of a row-major feature matrix and return the
// reached leaf value. Callers validate the shapes. The walk is bounded by
// the node count so a corrupt model cannot loop.
fn _tree_leaf_value_model_row(m: &Model, t: Int, features: &Vec[Int], r: Int) -> Int {
  let base_row = r * m.n_features;
  let root: Int = m.tree_root[t];
  var k = root;
  var guard = m.nodes.len() / _BST_NODE_STRIDE + 1;
  while guard > 0 {
    guard = guard - 1;
    let base: Int = k * _BST_NODE_STRIDE;
    let leaf: Int = m.nodes[base + _BST_NODE_LEAF];
    if leaf == 1 {
      return m.nodes[base + _BST_NODE_VALUE];
    }
    let feat: Int = m.nodes[base + _BST_NODE_FEATURE];
    let thr: Int = m.nodes[base + _BST_NODE_THRESHOLD];
    let x: Int = features[base_row + feat];
    if x <= thr {
      k = m.nodes[base + _BST_NODE_LEFT];
    } else {
      k = m.nodes[base + _BST_NODE_RIGHT];
    }
  }
  return m.nodes[k * _BST_NODE_STRIDE + _BST_NODE_VALUE];
}

// Walk stage t's tree for one explicit row vector and return the leaf value.
fn _tree_leaf_value_model(m: &Model, t: Int, row_features: &Vec[Int]) -> Int {
  let root: Int = m.tree_root[t];
  var k = root;
  var guard = m.nodes.len() / _BST_NODE_STRIDE + 1;
  while guard > 0 {
    guard = guard - 1;
    let base: Int = k * _BST_NODE_STRIDE;
    let leaf: Int = m.nodes[base + _BST_NODE_LEAF];
    if leaf == 1 {
      return m.nodes[base + _BST_NODE_VALUE];
    }
    let feat: Int = m.nodes[base + _BST_NODE_FEATURE];
    let thr: Int = m.nodes[base + _BST_NODE_THRESHOLD];
    let x: Int = row_features[feat];
    if x <= thr {
      k = m.nodes[base + _BST_NODE_LEFT];
    } else {
      k = m.nodes[base + _BST_NODE_RIGHT];
    }
  }
  return m.nodes[k * _BST_NODE_STRIDE + _BST_NODE_VALUE];
}

// Walk a freshly built tree in the local `nodes` vector (training time).
fn _tree_leaf_value_nodes(nodes: &Vec[Int], root: Int, features: &Vec[Int], r: Int, n_features: Int) -> Int {
  let base_row = r * n_features;
  var k = root;
  var guard = nodes.len() / _BST_NODE_STRIDE + 1;
  while guard > 0 {
    guard = guard - 1;
    let base: Int = k * _BST_NODE_STRIDE;
    let leaf: Int = nodes[base + _BST_NODE_LEAF];
    if leaf == 1 {
      return nodes[base + _BST_NODE_VALUE];
    }
    let feat: Int = nodes[base + _BST_NODE_FEATURE];
    let thr: Int = nodes[base + _BST_NODE_THRESHOLD];
    let x: Int = features[base_row + feat];
    if x <= thr {
      k = nodes[base + _BST_NODE_LEFT];
    } else {
      k = nodes[base + _BST_NODE_RIGHT];
    }
  }
  return nodes[k * _BST_NODE_STRIDE + _BST_NODE_VALUE];
}

// Mean squared error of two equal-length fixed-point vectors, divided by
// n_rows (truncated). Returns Err when a difference or the squared-error sum
// would leave the documented envelope (see SPEC.md).
fn _mse_res(preds: &Vec[Int], targets: &Vec[Int], n_rows: Int) -> Result[Int, Str] {
  var sum: Int = 0;
  var i = 0;
  while i < n_rows {
    let p: Int = preds[i];
    let t: Int = targets[i];
    let d = p - t;
    if d > _BST_DIFF_MAX {
      return _err_int("boosting: loss overflow");
    }
    if d < 0 - _BST_DIFF_MAX {
      return _err_int("boosting: loss overflow");
    }
    let sq = d * d;
    if sq > _BST_INT_MAX - sum {
      return _err_int("boosting: loss overflow");
    }
    sum = sum + sq;
    i = i + 1;
  }
  return _ok_int(sum / n_rows);
}

// Build one regression tree iteratively and append its nodes to `nodes`.
//
// `row_idx` lists the training row indices of the root node (entries may
// repeat); `feat_idx` lists the feature indices considered at every node.
// The explicit LIFO stack holds one frame per pending node:
// [depth, parent node index (-1 for the root), side (0 left / 1 right),
// row indices...]. One frame is consumed per loop iteration and a frame is
// pushed only for a split, so the loop performs at most 2 * n + 1 iterations
// for n root samples (a binary tree with non-empty children has at most n
// leaves); the budget makes the bound explicit. Every node read and write
// goes through typed locals, and a parent's child slot is patched when its
// child frame is consumed.
//
// Returns Ok(root node index) or Err(message).
fn _build_stage_into(nodes: &mut Vec[Int], features: &Vec[Int], n_features: Int, residuals: &Vec[Int], row_idx: &Vec[Int], feat_idx: &Vec[Int], max_depth: Int) -> Result[Int, Str] {
  let root_index = nodes.len() / _BST_NODE_STRIDE;
  var stack = Vec[Vec[Int]].new();
  var root_frame = Vec[Int].new();
  root_frame.push(0);
  root_frame.push(-1);
  root_frame.push(-1);
  var r0 = 0;
  while r0 < row_idx.len() {
    let si0: Int = row_idx[r0];
    root_frame.push(si0);
    r0 = r0 + 1;
  }
  stack.push(root_frame);
  var budget = 2 * row_idx.len() + 2;
  while stack.len() > 0 {
    if budget <= 0 {
      return _err_int("boosting: node budget exceeded");
    }
    budget = budget - 1;
    let popped = stack.pop();
    var frame = Vec[Int].new();
    match popped {
      Some(fr) => { frame = fr; },
      None => { return _err_int("boosting: internal stack underflow"); },
    }
    let depth: Int = frame[0];
    let parent: Int = frame[1];
    let side: Int = frame[2];
    let n: Int = frame.len() - 3;
    // Node residual sum and truncated mean.
    var sum: Int = 0;
    var i = 3;
    while i < frame.len() {
      let si: Int = frame[i];
      let rv: Int = residuals[si];
      sum = sum + rv;
      i = i + 1;
    }
    let mean = sum / n;
    // Append the node (leaf by default) and link it to its parent.
    let k = _node_append(nodes);
    _node_set(nodes, k, _BST_NODE_FEATURE, -1);
    _node_set(nodes, k, _BST_NODE_THRESHOLD, 0);
    _node_set(nodes, k, _BST_NODE_LEFT, -1);
    _node_set(nodes, k, _BST_NODE_RIGHT, -1);
    _node_set(nodes, k, _BST_NODE_VALUE, mean);
    _node_set(nodes, k, _BST_NODE_COUNT, n);
    _node_set(nodes, k, _BST_NODE_LEAF, 1);
    _node_set(nodes, k, _BST_NODE_DEPTH, depth);
    if parent >= 0 {
      if side == 0 {
        _node_set(nodes, parent, _BST_NODE_LEFT, k);
      } else {
        _node_set(nodes, parent, _BST_NODE_RIGHT, k);
      }
    }
    // Stopping rules: depth bound or too few samples for two non-empty
    // sides (minimum leaf size is 1).
    var can_split = 1;
    if depth >= max_depth {
      can_split = 0;
    }
    if n < 2 {
      can_split = 0;
    }
    if can_split == 1 {
      // Best split search: features in the selected order, thresholds
      // ascending; a strictly better score replaces the incumbent, so score
      // ties keep the earliest candidate (documented tie-break).
      var best_feature = -1;
      var best_threshold = 0;
      var best_score: Int = 0;
      var have = 0;
      var fi = 0;
      while fi < feat_idx.len() {
        let f: Int = feat_idx[fi];
        let vals: Vec[Int] = _distinct_values(features, n_features, &frame, f);
        var vi = 0;
        while vi < vals.len() {
          let v: Int = vals[vi];
          var ls: Int = 0;
          var rs: Int = 0;
          var nL: Int = 0;
          var nR: Int = 0;
          i = 3;
          while i < frame.len() {
            let si: Int = frame[i];
            let xv: Int = features[si * n_features + f];
            let rv: Int = residuals[si];
            if xv <= v {
              ls = ls + rv;
              nL = nL + 1;
            } else {
              rs = rs + rv;
              nR = nR + 1;
            }
            i = i + 1;
          }
          if nL >= 1 && nR >= 1 {
            let ql = ls / nL;
            let qr = rs / nR;
            let score = ql * ls + qr * rs;
            if have == 0 {
              have = 1;
              best_score = score;
              best_feature = f;
              best_threshold = v;
            } else {
              if score > best_score {
                best_score = score;
                best_feature = f;
                best_threshold = v;
              }
            }
          }
          vi = vi + 1;
        }
        fi = fi + 1;
      }
      if best_feature >= 0 {
        _node_set(nodes, k, _BST_NODE_FEATURE, best_feature);
        _node_set(nodes, k, _BST_NODE_THRESHOLD, best_threshold);
        _node_set(nodes, k, _BST_NODE_LEAF, 0);
        var lframe = Vec[Int].new();
        lframe.push(depth + 1);
        lframe.push(k);
        lframe.push(0);
        var rframe = Vec[Int].new();
        rframe.push(depth + 1);
        rframe.push(k);
        rframe.push(1);
        i = 3;
        while i < frame.len() {
          let si: Int = frame[i];
          let xv2: Int = features[si * n_features + best_feature];
          if xv2 <= best_threshold {
            lframe.push(si);
          } else {
            rframe.push(si);
          }
          i = i + 1;
        }
        stack.push(rframe);
        stack.push(lframe);
      }
    }
  }
  return _ok_int(root_index);
}

// Distinct feature values of `frame`'s sample rows for feature f, ascending.
// `frame` encodes a build frame: [depth, parent, side, row indices...].
fn _distinct_values(features: &Vec[Int], n_features: Int, frame: &Vec[Int], f: Int) -> Vec[Int] {
  var vals = Vec[Int].new();
  var i = 3;
  while i < frame.len() {
    let si: Int = frame[i];
    let v: Int = features[si * n_features + f];
    var seen = 0;
    var k = 0;
    while k < vals.len() {
      let w: Int = vals[k];
      if w == v {
        seen = 1;
      }
      k = k + 1;
    }
    if seen == 0 {
      vals.push(v);
    }
    i = i + 1;
  }
  _sort_ints(&mut vals);
  return vals;
}

// Insertion sort of an Int vector (ascending); small candidate lists only.
fn _sort_ints(v: &mut Vec[Int]) {
  var i = 1;
  while i < v.len() {
    var j = i;
    while j > 0 && v[j - 1] > v[j] {
      var temp = v[j - 1];
      v[j - 1] = v[j];
      v[j] = temp;
      j = j - 1;
    }
    i = i + 1;
  }
}

// Append a blank node and return its index.
fn _node_append(nodes: &mut Vec[Int]) -> Int {
  let k = nodes.len() / _BST_NODE_STRIDE;
  var i = 0;
  while i < _BST_NODE_STRIDE {
    nodes.push(0);
    i = i + 1;
  }
  return k;
}

// Write one field of node k.
fn _node_set(nodes: &mut Vec[Int], k: Int, field: Int, v: Int) {
  nodes[k * _BST_NODE_STRIDE + field] = v;
}

// Shared data-shape validation: Ok(0) on success, Err(message) otherwise.
fn _validate_data(features: &Vec[Int], n_rows: Int, n_features: Int, targets: &Vec[Int]) -> Result[Int, Str] {
  if n_rows <= 0 {
    return _err_int("boosting: row count must be positive");
  }
  if n_features <= 0 {
    return _err_int("boosting: feature count must be positive");
  }
  if n_rows > _BST_MAX_ROWS {
    return _err_int("boosting: dataset too large");
  }
  if n_rows > _BST_INT_MAX / n_features {
    return _err_int("boosting: dimensions overflow");
  }
  if features.len() != n_rows * n_features {
    return _err_int("boosting: features length does not match the shape");
  }
  if targets.len() != n_rows {
    return _err_int("boosting: target count does not match row count");
  }
  var i = 0;
  while i < n_rows {
    let t: Int = targets[i];
    if t > _BST_VALUE_MAX {
      return _err_int("boosting: target out of range");
    }
    if t < 0 - _BST_VALUE_MAX {
      return _err_int("boosting: target out of range");
    }
    i = i + 1;
  }
  return _ok_int(0);
}

// Normalize any Int seed into [1, 2147483646]: |seed mod 2147483646| + 1.
fn _norm_lcg_state(seed: Int) -> Int {
  var s = seed % _BST_LCG_RANGE;
  if s < 0 {
    s = 0 - s;
  }
  return s + 1;
}

// ---------------------------------------------------------------------------
// Leaf Result constructors
// ---------------------------------------------------------------------------

fn _ok_model(m: Model) -> Result[Model, Str] {
  return Ok(m);
}

fn _err_model(msg: Str) -> Result[Model, Str] {
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

fn _ok_str(s: Str) -> Result[Str, Str] {
  return Ok(s);
}

fn _err_str(msg: Str) -> Result[Str, Str] {
  return Err(msg);
}
