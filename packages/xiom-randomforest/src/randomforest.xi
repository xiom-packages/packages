// XIOM -- xiom.randomforest: deterministic CART-style random forest
// Port task: replace the xiom.randomforest placeholder with a pure-XIOM
// module (integer features and labels only: no floats, no FFI, no threads).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model (pinned in SPEC.md, exercised by tests/test_conformance.xi):
//
//   - every tree is a CART-style binary tree over integer feature vectors.
//     A split tests one feature f against an integer threshold t: samples
//     with value <= t go left, the rest go right. Candidate thresholds are
//     the distinct values of the feature inside the node.
//   - split quality is Gini impurity in integer arithmetic. For a node with
//     class counts c_k and n samples, the impurity numerator is
//     n^2 - sum_k c_k^2. For a candidate split into nL/nR samples with
//     squared-count sums A = sum l_k^2 and B = sum r_k^2, the score is
//     S = (A * 1000000) / nL + (B * 1000000) / nR with truncating integer
//     division; larger S is better. See SPEC.md for the derivation and the
//     documented tie-breaks.
//   - stopping: a node becomes a leaf when it reaches max_depth, is pure,
//     has fewer than 2 * min_samples samples, or no candidate split leaves
//     min_samples samples on both sides. The leaf label is the majority
//     class; ties go to the class with the lowest index in the first-
//     occurrence class list (deterministic, dictionary-free).
//   - bootstrap: a caller-seeded MINSTD (Park-Miller) LCG (multiplier
//     48271, modulus 2^31 - 1) draws n_rows row indices with replacement
//     per tree from one continuous stream; the same seed and shape always
//     produce the same forest on every run and platform.
//   - forest voting: every tree votes its leaf label; the class with the
//     most votes wins; ties go to the lowest class index.
//   - feature importance: raw split counts per feature and sample-weighted
//     counts (sum of the node sample counts over the split nodes).
//   - tree dump: a deterministic text rendering of one tree.
//
// Layout notes that shaped this module (compiler v0.62.1):
//   * all tree traversals are iterative with explicit stacks and a visit
//     budget -- the module contains no recursion at all (the v0.62.1
//     toolchain did not terminate on a recursive user function while this
//     package was ported).
//   * every Vec[Int] element read binds the value to a typed local before
//     use; no Str values are compared anywhere in this module.
//   * a Forest carries one flat Vec[Int] of fixed-stride nodes instead of
//     parallel vectors (no Vec[StructType], no drift between vectors).
//   * free functions only: no methods, no generics, no callbacks, no
//     indexed function-table dispatch.
//   * multiply-before-divide steps are guarded by a documented row-count
//     envelope (see SPEC.md); no silent overflow path exists.

module xiom.randomforest

use xiom.convert;

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

// Flat node layout: every node occupies _RF_NODE_STRIDE consecutive slots.
const _RF_NODE_STRIDE: Int = 8;
const _RF_NODE_FEATURE: Int = 0;    // split feature, -1 for a leaf
const _RF_NODE_THRESHOLD: Int = 1;  // left branch when value <= threshold
const _RF_NODE_LEFT: Int = 2;       // left child node index, -1 for a leaf
const _RF_NODE_RIGHT: Int = 3;      // right child node index, -1 for a leaf
const _RF_NODE_LABEL: Int = 4;      // majority label of the node
const _RF_NODE_COUNT: Int = 5;      // training samples at the node
const _RF_NODE_LEAF: Int = 6;       // 1 for a leaf, 0 for a split node
const _RF_NODE_DEPTH: Int = 7;      // root depth is 0

// MINSTD (Park-Miller) LCG: state = (state * 48271) mod (2^31 - 1).
const _RF_LCG_MULT: Int = 48271;
const _RF_LCG_MOD: Int = 2147483647;
const _RF_LCG_RANGE: Int = 2147483646;
const _RF_INT_MAX: Int = 9223372036854775807;

// Split-score scale: S is computed in millionths (truncating division).
const _RF_SCALE: Int = 1000000;

// Documented configuration envelope (see SPEC.md, section "Envelope").
const _RF_MAX_DEPTH: Int = 64;
const _RF_MAX_ROWS: Int = 1000000;
const _RF_MAX_TREES: Int = 100000;

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

/// A trained random forest.
///
/// `classes` holds the distinct training labels in first-occurrence order;
/// `tree_root[t]` is the index of tree t's root node inside `nodes`; trees
/// occupy consecutive node ranges in creation order. `nodes` is a flat
/// vector: node k occupies slots k * randomforest_node_stride() + field,
/// with the field offsets documented on the randomforest_node_* accessors.
///
/// Fields are internal implementation detail; use the accessors.
pub type Forest = {
  n_features: Int;
  n_classes: Int;
  classes: Vec[Int];
  n_trees: Int;
  tree_root: Vec[Int];
  nodes: Vec[Int];
}

// ---------------------------------------------------------------------------
// Constants and generator accessors
// ---------------------------------------------------------------------------

/// Multiplier of the bootstrap LCG (48271). Complexity: O(1).
pub fn randomforest_lcg_multiplier() -> Int {
  return _RF_LCG_MULT;
}

/// Modulus of the bootstrap LCG (2147483647 = 2^31 - 1). Complexity: O(1).
pub fn randomforest_lcg_modulus() -> Int {
  return _RF_LCG_MOD;
}

/// Largest accepted max_depth (64). Complexity: O(1).
pub fn randomforest_max_depth_limit() -> Int {
  return _RF_MAX_DEPTH;
}

/// Largest accepted training row count (1000000). Complexity: O(1).
pub fn randomforest_max_rows() -> Int {
  return _RF_MAX_ROWS;
}

/// Largest accepted tree count (100000). Complexity: O(1).
pub fn randomforest_max_trees() -> Int {
  return _RF_MAX_TREES;
}

/// Number of Int slots per node in a Forest's flat node vector (8).
/// Complexity: O(1).
pub fn randomforest_node_stride() -> Int {
  return _RF_NODE_STRIDE;
}

// ---------------------------------------------------------------------------
// Bootstrap LCG
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
pub fn randomforest_lcg_step(state: Int) -> Int {
  let s = _norm_lcg_state(state);
  return (s * _RF_LCG_MULT) % _RF_LCG_MOD;
}

/// Deterministic bootstrap sample indices with replacement.
///
/// Params: seed - any Int (normalized as documented on
///         randomforest_lcg_step);
///         dataset_size - number of rows to sample from (> 0);
///         n_samples - number of indices to draw (>= 0; 0 yields Ok(empty)).
/// Returns: Ok(indices) of length n_samples; index k (1-based) is
/// (state_k - 1) mod dataset_size, where state_0 = |seed mod 2147483646| + 1
/// and state_{k+1} = (state_k * 48271) mod 2147483647. The LCG constants are
/// exposed by randomforest_lcg_multiplier / randomforest_lcg_modulus. The
/// same seed and shape always produce the same vector, on every run and
/// platform.
/// Error case: Err("randomforest: ...") for a non-positive dataset size or a
/// negative sample count.
/// Complexity: O(n_samples).
pub fn randomforest_bootstrap_indices(seed: Int, dataset_size: Int, n_samples: Int) -> Result[Vec[Int], Str] {
  if dataset_size <= 0 {
    return _err_ints("randomforest: dataset size must be positive");
  }
  if n_samples < 0 {
    return _err_ints("randomforest: sample count must not be negative");
  }
  var state = _norm_lcg_state(seed);
  var out = Vec[Int].new();
  var i = 0;
  while i < n_samples {
    state = (state * _RF_LCG_MULT) % _RF_LCG_MOD;
    out.push((state - 1) % dataset_size);
    i = i + 1;
  }
  return _ok_ints(out);
}

// ---------------------------------------------------------------------------
// Training
// ---------------------------------------------------------------------------

/// Train a random forest on an integer feature matrix.
///
/// Params: features - n_rows * n_features row-major integer feature values
///         (row r, feature f at r * n_features + f), read only;
///         n_rows - number of training rows (> 0, <= randomforest_max_rows());
///         n_features - number of features per row (> 0);
///         labels - one integer class label per row (labels.len() == n_rows);
///         n_trees - number of trees (> 0, <= randomforest_max_trees());
///         max_depth - depth bound (0..=64; a node at depth max_depth is a
///         leaf, root depth = 0);
///         min_samples - minimum samples on each side of an accepted split
///         (>= 1; a node with fewer than 2 * min_samples samples is a leaf);
///         seed - LCG seed; the bootstrap stream is continuous across trees,
///         so tree t is trained on
///         randomforest_bootstrap_indices(seed, n_rows, n_trees * n_rows)
///         entries t * n_rows .. (t + 1) * n_rows - 1.
/// Returns: Ok(Forest) with n_trees trees sharing one flat node vector.
/// Error case: Err("randomforest: ...") for any validation failure; the
/// validation order is data shape, tree count, depth, min samples.
/// Complexity: O(n_trees * n_rows * n_features * distinct-values) per tree
/// node scan; deliberately simple, fixture-scale training.
pub fn randomforest_train(features: &Vec[Int], n_rows: Int, n_features: Int, labels: &Vec[Int], n_trees: Int, max_depth: Int, min_samples: Int, seed: Int) -> Result[Forest, Str] {
  let chk = _validate_data(features, n_rows, n_features, labels);
  match chk {
    Ok(_) => { },
    Err(e) => { return _err_forest(e); },
  }
  if n_trees <= 0 {
    return _err_forest("randomforest: tree count must be positive");
  }
  if n_trees > _RF_MAX_TREES {
    return _err_forest("randomforest: tree count exceeds the limit");
  }
  let dchk = _check_depth(max_depth);
  match dchk {
    Ok(_) => { },
    Err(e) => { return _err_forest(e); },
  }
  let mchk = _check_min_samples(min_samples);
  match mchk {
    Ok(_) => { },
    Err(e) => { return _err_forest(e); },
  }
  let classes = _classes_of(labels);
  let n_classes = classes.len();
  var nodes = Vec[Int].new();
  var roots = Vec[Int].new();
  var state = _norm_lcg_state(seed);
  var t = 0;
  while t < n_trees {
    var idx = Vec[Int].new();
    var i = 0;
    while i < n_rows {
      state = (state * _RF_LCG_MULT) % _RF_LCG_MOD;
      idx.push((state - 1) % n_rows);
      i = i + 1;
    }
    let built = _build_into(&mut nodes, features, n_features, labels, &classes, n_classes, &idx, 0, max_depth, min_samples);
    match built {
      Ok(root) => { roots.push(root); },
      Err(e) => { return _err_forest(e); },
    }
    t = t + 1;
  }
  return _ok_forest(Forest{ n_features: n_features; n_classes: n_classes; classes: classes; n_trees: n_trees; tree_root: roots; nodes: nodes; });
}

/// Train exactly one tree on an explicit row-index list (no bootstrap).
///
/// Params: features / n_rows / n_features / labels - as in
///         randomforest_train;
///         indices - the row indices the tree is trained on (> 0 entries,
///         every entry in [0, n_rows); entries may repeat);
///         max_depth / min_samples - as in randomforest_train.
/// Returns: Ok(Forest) with n_trees == 1 and tree_root[0] == 0. This is the
/// function randomforest_train uses internally for every tree, exposed so
/// callers can train on a chosen subsample and so the bootstrap stream can
/// be pinned in tests (see SPEC.md).
/// Error case: Err("randomforest: ...") for any validation failure; the
/// validation order is data shape, sample indices (emptiness then range),
/// depth, min samples.
/// Complexity: as randomforest_train for a single tree.
pub fn randomforest_build_tree(features: &Vec[Int], n_rows: Int, n_features: Int, labels: &Vec[Int], indices: &Vec[Int], max_depth: Int, min_samples: Int) -> Result[Forest, Str] {
  let chk = _validate_data(features, n_rows, n_features, labels);
  match chk {
    Ok(_) => { },
    Err(e) => { return _err_forest(e); },
  }
  if indices.len() <= 0 {
    return _err_forest("randomforest: sample indices must not be empty");
  }
  var i = 0;
  while i < indices.len() {
    let si: Int = indices[i];
    if si < 0 || si >= n_rows {
      return _err_forest("randomforest: sample index out of range");
    }
    i = i + 1;
  }
  let dchk = _check_depth(max_depth);
  match dchk {
    Ok(_) => { },
    Err(e) => { return _err_forest(e); },
  }
  let mchk = _check_min_samples(min_samples);
  match mchk {
    Ok(_) => { },
    Err(e) => { return _err_forest(e); },
  }
  let classes = _classes_of(labels);
  let n_classes = classes.len();
  var nodes = Vec[Int].new();
  let built = _build_into(&mut nodes, features, n_features, labels, &classes, n_classes, indices, 0, max_depth, min_samples);
  var root: Int = -1;
  match built {
    Ok(x) => { root = x; },
    Err(e) => { return _err_forest(e); },
  }
  var roots = Vec[Int].new();
  roots.push(root);
  return _ok_forest(Forest{ n_features: n_features; n_classes: n_classes; classes: classes; n_trees: 1; tree_root: roots; nodes: nodes; });
}

// ---------------------------------------------------------------------------
// Forest accessors
// ---------------------------------------------------------------------------

/// Number of trees. Complexity: O(1).
pub fn randomforest_n_trees(f: &Forest) -> Int {
  return f.n_trees;
}

/// Number of features the forest was trained on. Complexity: O(1).
pub fn randomforest_n_features(f: &Forest) -> Int {
  return f.n_features;
}

/// Number of distinct training classes. Complexity: O(1).
pub fn randomforest_n_classes(f: &Forest) -> Int {
  return f.n_classes;
}

/// Number of nodes across all trees. Complexity: O(1).
pub fn randomforest_n_nodes(f: &Forest) -> Int {
  return f.nodes.len() / _RF_NODE_STRIDE;
}

/// Class label at first-occurrence index k, or 0 when k is out of range
/// (use randomforest_n_classes to range-check). Complexity: O(1).
pub fn randomforest_class(f: &Forest, k: Int) -> Int {
  if k < 0 {
    return 0;
  }
  if k >= f.classes.len() {
    return 0;
  }
  let x: Int = f.classes[k];
  return x;
}

/// First-occurrence index of a class label, or -1 when the label is not a
/// training class. Complexity: O(n_classes).
pub fn randomforest_class_index(f: &Forest, label: Int) -> Int {
  var i = 0;
  while i < f.classes.len() {
    let c: Int = f.classes[i];
    if c == label {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

/// Root node index of tree t, or -1 when t is out of range. Complexity: O(1).
pub fn randomforest_tree_root(f: &Forest, t: Int) -> Int {
  if t < 0 {
    return -1;
  }
  if t >= f.tree_root.len() {
    return -1;
  }
  let x: Int = f.tree_root[t];
  return x;
}

/// Number of nodes in tree t (its nodes form a contiguous range that starts
/// at the root), or 0 when t is out of range. Complexity: O(1).
pub fn randomforest_tree_n_nodes(f: &Forest, t: Int) -> Int {
  if t < 0 || t >= f.n_trees {
    return 0;
  }
  let start: Int = f.tree_root[t];
  var end = f.nodes.len() / _RF_NODE_STRIDE;
  if t + 1 < f.n_trees {
    let e: Int = f.tree_root[t + 1];
    end = e;
  }
  return end - start;
}

/// Maximum node depth of tree t (root depth 0), or -1 when t is out of
/// range. Complexity: O(nodes of tree t).
pub fn randomforest_tree_depth(f: &Forest, t: Int) -> Int {
  if t < 0 || t >= f.n_trees {
    return -1;
  }
  let start: Int = f.tree_root[t];
  let count = randomforest_tree_n_nodes(f, t);
  var deepest = -1;
  var i = 0;
  while i < count {
    let base: Int = (start + i) * _RF_NODE_STRIDE;
    let d: Int = f.nodes[base + _RF_NODE_DEPTH];
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

/// True when node k is a leaf, false for a split node and for out-of-range
/// indices. Complexity: O(1).
pub fn randomforest_is_leaf(f: &Forest, k: Int) -> Bool {
  if k < 0 {
    return false;
  }
  if k >= f.nodes.len() / _RF_NODE_STRIDE {
    return false;
  }
  let l: Int = f.nodes[k * _RF_NODE_STRIDE + _RF_NODE_LEAF];
  if l == 1 {
    return true;
  }
  return false;
}

/// Split feature of node k; -1 for a leaf, -2 when k is out of range.
/// Complexity: O(1).
pub fn randomforest_node_feature(f: &Forest, k: Int) -> Int {
  if k < 0 {
    return -2;
  }
  if k >= f.nodes.len() / _RF_NODE_STRIDE {
    return -2;
  }
  return _forest_field(f, k, _RF_NODE_FEATURE);
}

/// Split threshold of node k (left branch when value <= threshold); 0 for a
/// leaf and for out-of-range indices. Complexity: O(1).
pub fn randomforest_node_threshold(f: &Forest, k: Int) -> Int {
  if k < 0 {
    return 0;
  }
  if k >= f.nodes.len() / _RF_NODE_STRIDE {
    return 0;
  }
  return _forest_field(f, k, _RF_NODE_THRESHOLD);
}

/// Left child of node k, or -1 for a leaf and out-of-range indices.
/// Complexity: O(1).
pub fn randomforest_node_left(f: &Forest, k: Int) -> Int {
  if k < 0 {
    return -1;
  }
  if k >= f.nodes.len() / _RF_NODE_STRIDE {
    return -1;
  }
  return _forest_field(f, k, _RF_NODE_LEFT);
}

/// Right child of node k, or -1 for a leaf and out-of-range indices.
/// Complexity: O(1).
pub fn randomforest_node_right(f: &Forest, k: Int) -> Int {
  if k < 0 {
    return -1;
  }
  if k >= f.nodes.len() / _RF_NODE_STRIDE {
    return -1;
  }
  return _forest_field(f, k, _RF_NODE_RIGHT);
}

/// Majority label of node k, or 0 when k is out of range. Complexity: O(1).
pub fn randomforest_node_label(f: &Forest, k: Int) -> Int {
  if k < 0 {
    return 0;
  }
  if k >= f.nodes.len() / _RF_NODE_STRIDE {
    return 0;
  }
  return _forest_field(f, k, _RF_NODE_LABEL);
}

/// Training sample count of node k (bootstrap duplicates included), or 0
/// when k is out of range. Complexity: O(1).
pub fn randomforest_node_count(f: &Forest, k: Int) -> Int {
  if k < 0 {
    return 0;
  }
  if k >= f.nodes.len() / _RF_NODE_STRIDE {
    return 0;
  }
  return _forest_field(f, k, _RF_NODE_COUNT);
}

/// Depth of node k (root depth 0), or -1 when k is out of range.
/// Complexity: O(1).
pub fn randomforest_node_depth(f: &Forest, k: Int) -> Int {
  if k < 0 {
    return -1;
  }
  if k >= f.nodes.len() / _RF_NODE_STRIDE {
    return -1;
  }
  return _forest_field(f, k, _RF_NODE_DEPTH);
}

// ---------------------------------------------------------------------------
// Prediction
// ---------------------------------------------------------------------------

/// Predict one row with one tree.
///
/// Params: f - a forest; t - tree index in [0, n_trees);
///         row_features - exactly f.n_features feature values.
/// Returns: Ok(label) where label is the leaf label reached by walking the
/// tree: at a split node with feature fd and threshold th, the walk goes
/// left when row_features[fd] <= th and right otherwise.
/// Error case: Err("randomforest: ...") for an out-of-range tree index or a
/// row whose feature count does not match the forest.
/// Complexity: O(tree depth).
pub fn randomforest_predict_tree_row(f: &Forest, t: Int, row_features: &Vec[Int]) -> Result[Int, Str] {
  if t < 0 || t >= f.n_trees {
    return _err_int("randomforest: tree index out of range");
  }
  if row_features.len() != f.n_features {
    return _err_int("randomforest: feature count does not match the forest");
  }
  return _ok_int(_tree_vote(f, t, row_features));
}

/// Predict integer labels for n_rows rows, one vote per tree.
///
/// Params: f - a forest; features - n_rows * f.n_features row-major feature
///         values; n_rows - number of rows (> 0).
/// Returns: Ok(predictions) with one training class label per row. Each
/// tree votes its leaf label; the class with the most votes wins; ties go
/// to the class with the lowest first-occurrence index.
/// Error case: Err("randomforest: ...") for a non-positive row count, a
/// dimensions overflow, or a features length mismatch.
/// Complexity: O(n_rows * n_trees * tree depth).
pub fn randomforest_predict(f: &Forest, features: &Vec[Int], n_rows: Int) -> Result[Vec[Int], Str] {
  if n_rows <= 0 {
    return _err_ints("randomforest: row count must be positive");
  }
  if f.n_features <= 0 {
    return _err_ints("randomforest: forest has no features");
  }
  if n_rows > _RF_INT_MAX / f.n_features {
    return _err_ints("randomforest: dimensions overflow");
  }
  if features.len() != n_rows * f.n_features {
    return _err_ints("randomforest: features length does not match the shape");
  }
  // Local copy of the class list: predicates here never pass struct fields
  // by reference (v0.62.1 field-borrow lowering note in SPEC.md).
  var cls = Vec[Int].new();
  var ci = 0;
  while ci < f.n_classes {
    let c: Int = f.classes[ci];
    cls.push(c);
    ci = ci + 1;
  }
  var out = Vec[Int].new();
  var r = 0;
  while r < n_rows {
    var row = Vec[Int].new();
    var j = 0;
    while j < f.n_features {
      let x: Int = features[r * f.n_features + j];
      row.push(x);
      j = j + 1;
    }
    var votes = Vec[Int].new();
    var c2 = 0;
    while c2 < f.n_classes {
      votes.push(0);
      c2 = c2 + 1;
    }
    var t = 0;
    while t < f.n_trees {
      let label = _tree_vote(f, t, &row);
      let idx: Int = _class_index(&cls, label);
      if idx < 0 {
        return _err_ints("randomforest: leaf label missing from the class list");
      }
      let h: Int = votes[idx];
      votes[idx] = h + 1;
      t = t + 1;
    }
    var best = 0;
    var best_count: Int = votes[0];
    var k = 1;
    while k < f.n_classes {
      let h2: Int = votes[k];
      if h2 > best_count {
        best_count = h2;
        best = k;
      }
      k = k + 1;
    }
    let winner: Int = cls[best];
    out.push(winner);
    r = r + 1;
  }
  return _ok_ints(out);
}

// ---------------------------------------------------------------------------
// Feature importance
// ---------------------------------------------------------------------------

/// Raw feature importance: the number of split nodes that use each feature.
///
/// Returns: a vector of length f.n_features; entry j is the number of split
/// nodes (across all trees) whose split feature is j. Leaves contribute
/// nothing. Stable under retraining with the same seed.
/// Complexity: O(n_nodes).
pub fn randomforest_feature_importance(f: &Forest) -> Vec[Int] {
  var out = Vec[Int].new();
  var c = 0;
  while c < f.n_features {
    out.push(0);
    c = c + 1;
  }
  let n_nodes = f.nodes.len() / _RF_NODE_STRIDE;
  var i = 0;
  while i < n_nodes {
    let base: Int = i * _RF_NODE_STRIDE;
    let feat: Int = f.nodes[base + _RF_NODE_FEATURE];
    if feat >= 0 {
      let cur: Int = out[feat];
      out[feat] = cur + 1;
    }
    i = i + 1;
  }
  return out;
}

/// Sample-weighted feature importance: for every split node, its training
/// sample count is credited to its split feature.
///
/// Returns: a vector of length f.n_features; entry j is the sum of
/// randomforest_node_count over all split nodes that use feature j. Since a
/// split node keeps at least min_samples samples, this is >= the raw
/// count. Complexity: O(n_nodes).
pub fn randomforest_feature_importance_weighted(f: &Forest) -> Vec[Int] {
  var out = Vec[Int].new();
  var c = 0;
  while c < f.n_features {
    out.push(0);
    c = c + 1;
  }
  let n_nodes = f.nodes.len() / _RF_NODE_STRIDE;
  var i = 0;
  while i < n_nodes {
    let base: Int = i * _RF_NODE_STRIDE;
    let feat: Int = f.nodes[base + _RF_NODE_FEATURE];
    if feat >= 0 {
      let cnt: Int = f.nodes[base + _RF_NODE_COUNT];
      let cur: Int = out[feat];
      out[feat] = cur + cnt;
    }
    i = i + 1;
  }
  return out;
}

// ---------------------------------------------------------------------------
// Tree dump
// ---------------------------------------------------------------------------

/// Render tree t as deterministic text.
///
/// Format (one trailing newline per line, node lines in pre-order with the
/// left child first; two spaces of indentation per depth level):
///
///   tree T: nodes=N depth=D
///   [k] fF <= TH (n=C, label=L)
///     [k] leaf label=L (n=C)
///
/// Params: f - a forest; t - tree index in [0, n_trees).
/// Returns: Ok(text) as described above. The walk is iterative and bounded
/// by the tree's node count, so a corrupt forest cannot loop.
/// Error case: Err("randomforest: ...") for an out-of-range tree index.
/// Complexity: O(nodes of tree t) plus string assembly.
pub fn randomforest_dump_tree(f: &Forest, t: Int) -> Result[Str, Str] {
  if t < 0 || t >= f.n_trees {
    return _err_str("randomforest: tree index out of range");
  }
  let root: Int = f.tree_root[t];
  let n_tree = randomforest_tree_n_nodes(f, t);
  let depth_tree = randomforest_tree_depth(f, t);
  var out = "tree " + convert.int_to_string(t) + ": nodes=" + convert.int_to_string(n_tree) + " depth=" + convert.int_to_string(depth_tree) + "\n";
  var stack_node = Vec[Int].new();
  var stack_indent = Vec[Int].new();
  stack_node.push(root);
  stack_indent.push(0);
  var budget = n_tree + 1;
  while stack_node.len() > 0 {
    if budget <= 0 {
      return _err_str("randomforest: dump budget exceeded");
    }
    budget = budget - 1;
    let pk = stack_node.pop();
    var k: Int = -1;
    match pk {
      Some(x) => { k = x; },
      None => { return _err_str("randomforest: internal stack underflow"); },
    }
    let pi = stack_indent.pop();
    var indent: Int = 0;
    match pi {
      Some(x) => { indent = x; },
      None => { return _err_str("randomforest: internal stack underflow"); },
    }
    out = out + _dump_line(f, k, indent);
    let leaf: Bool = randomforest_is_leaf(f, k);
    if !leaf {
      let l: Int = randomforest_node_left(f, k);
      let r: Int = randomforest_node_right(f, k);
      stack_node.push(r);
      stack_indent.push(indent + 1);
      stack_node.push(l);
      stack_indent.push(indent + 1);
    }
  }
  return _ok_str(out);
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

// Render one node line (see randomforest_dump_tree for the format).
fn _dump_line(f: &Forest, k: Int, indent: Int) -> Str {
  var pad = "";
  var i = 0;
  while i < indent {
    pad = pad + "  ";
    i = i + 1;
  }
  let feat: Int = randomforest_node_feature(f, k);
  let label: Int = randomforest_node_label(f, k);
  let count: Int = randomforest_node_count(f, k);
  var line = pad + "[" + convert.int_to_string(k) + "] ";
  if feat < 0 {
    return line + "leaf label=" + convert.int_to_string(label) + " (n=" + convert.int_to_string(count) + ")\n";
  }
  let thr: Int = randomforest_node_threshold(f, k);
  return line + "f" + convert.int_to_string(feat) + " <= " + convert.int_to_string(thr) + " (n=" + convert.int_to_string(count) + ", label=" + convert.int_to_string(label) + ")\n";
}

// Walk tree t for one row and return its leaf label. Callers validate the
// tree index and the row width. The walk is bounded by the node count so a
// corrupt forest cannot loop.
fn _tree_vote(f: &Forest, t: Int, row_features: &Vec[Int]) -> Int {
  let root: Int = f.tree_root[t];
  var k = root;
  var guard = f.nodes.len() / _RF_NODE_STRIDE + 1;
  while guard > 0 {
    guard = guard - 1;
    let base: Int = k * _RF_NODE_STRIDE;
    let leaf: Int = f.nodes[base + _RF_NODE_LEAF];
    if leaf == 1 {
      return f.nodes[base + _RF_NODE_LABEL];
    }
    let feat: Int = f.nodes[base + _RF_NODE_FEATURE];
    let thr: Int = f.nodes[base + _RF_NODE_THRESHOLD];
    let x: Int = row_features[feat];
    if x <= thr {
      k = f.nodes[base + _RF_NODE_LEFT];
    } else {
      k = f.nodes[base + _RF_NODE_RIGHT];
    }
  }
  return f.nodes[k * _RF_NODE_STRIDE + _RF_NODE_LABEL];
}

// Read one field of node k. The caller range-checks k.
fn _forest_field(f: &Forest, k: Int, field: Int) -> Int {
  return f.nodes[k * _RF_NODE_STRIDE + field];
}

// Shared data-shape validation: Ok(0) on success, Err(message) otherwise.
fn _validate_data(features: &Vec[Int], n_rows: Int, n_features: Int, labels: &Vec[Int]) -> Result[Int, Str] {
  if n_rows <= 0 {
    return _err_int("randomforest: row count must be positive");
  }
  if n_features <= 0 {
    return _err_int("randomforest: feature count must be positive");
  }
  if n_rows > _RF_MAX_ROWS {
    return _err_int("randomforest: dataset too large");
  }
  if n_rows > _RF_INT_MAX / n_features {
    return _err_int("randomforest: dimensions overflow");
  }
  if features.len() != n_rows * n_features {
    return _err_int("randomforest: features length does not match the shape");
  }
  if labels.len() != n_rows {
    return _err_int("randomforest: label count does not match row count");
  }
  return _ok_int(0);
}

// Depth validation.
fn _check_depth(max_depth: Int) -> Result[Int, Str] {
  if max_depth < 0 {
    return _err_int("randomforest: max depth must not be negative");
  }
  if max_depth > _RF_MAX_DEPTH {
    return _err_int("randomforest: max depth exceeds the limit");
  }
  return _ok_int(max_depth);
}

// Min-samples validation.
fn _check_min_samples(min_samples: Int) -> Result[Int, Str] {
  if min_samples < 1 {
    return _err_int("randomforest: min samples must be positive");
  }
  return _ok_int(min_samples);
}

// Distinct labels in first-occurrence order.
fn _classes_of(labels: &Vec[Int]) -> Vec[Int] {
  var classes = Vec[Int].new();
  var i = 0;
  while i < labels.len() {
    let l: Int = labels[i];
    let found: Int = _class_index(&classes, l);
    if found < 0 {
      classes.push(l);
    }
    i = i + 1;
  }
  return classes;
}

// Index of `label` in `classes`, or -1 when absent.
fn _class_index(classes: &Vec[Int], label: Int) -> Int {
  var i = 0;
  while i < classes.len() {
    let c: Int = classes[i];
    if c == label {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Sum of squared class counts.
fn _sum_sq(v: &Vec[Int]) -> Int {
  var s: Int = 0;
  var i = 0;
  while i < v.len() {
    let x: Int = v[i];
    s = s + x * x;
    i = i + 1;
  }
  return s;
}

// Append a blank node and return its index.
fn _node_append(nodes: &mut Vec[Int]) -> Int {
  let k = nodes.len() / _RF_NODE_STRIDE;
  var i = 0;
  while i < _RF_NODE_STRIDE {
    nodes.push(0);
    i = i + 1;
  }
  return k;
}

// Write one field of node k.
fn _node_set(nodes: &mut Vec[Int], k: Int, field: Int, v: Int) {
  nodes[k * _RF_NODE_STRIDE + field] = v;
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

// Normalize any Int seed into [1, 2147483646]: |seed mod 2147483646| + 1.
fn _norm_lcg_state(seed: Int) -> Int {
  var s = seed % _RF_LCG_RANGE;
  if s < 0 {
    s = 0 - s;
  }
  return s + 1;
}

// Build one tree iteratively and append its nodes to `nodes`.
//
// `sample_idx` lists the training row indices of the root node (entries may
// repeat). The explicit LIFO stack holds one frame per pending node:
// [depth, parent node index (-1 for the root), side (0 left / 1 right),
// row indices...]. One frame is consumed per loop iteration and a frame is
// pushed only for a split, so the loop performs at most 2 * n + 1
// iterations for n root samples (a binary tree with non-empty children has
// at most n leaves); the budget makes the bound explicit. Every node read
// and write goes through typed locals, and a parent's child slot is patched
// when its child frame is consumed.
//
// Returns Ok(root node index) or Err(message).
fn _build_into(nodes: &mut Vec[Int], features: &Vec[Int], n_features: Int, labels: &Vec[Int], classes: &Vec[Int], n_classes: Int, sample_idx: &Vec[Int], depth0: Int, max_depth: Int, min_samples: Int) -> Result[Int, Str] {
  let root_index = nodes.len() / _RF_NODE_STRIDE;
  var stack = Vec[Vec[Int]].new();
  var root_frame = Vec[Int].new();
  root_frame.push(depth0);
  root_frame.push(-1);
  root_frame.push(-1);
  var r0 = 0;
  while r0 < sample_idx.len() {
    let si0: Int = sample_idx[r0];
    root_frame.push(si0);
    r0 = r0 + 1;
  }
  stack.push(root_frame);
  var budget = 2 * sample_idx.len() + 2;
  while stack.len() > 0 {
    if budget <= 0 {
      return _err_int("randomforest: node budget exceeded");
    }
    budget = budget - 1;
    let popped = stack.pop();
    var frame = Vec[Int].new();
    match popped {
      Some(fr) => { frame = fr; },
      None => { return _err_int("randomforest: internal stack underflow"); },
    }
    let depth: Int = frame[0];
    let parent: Int = frame[1];
    let side: Int = frame[2];
    let n: Int = frame.len() - 3;
    // Class histogram of the node sample.
    var hist = Vec[Int].new();
    var c = 0;
    while c < n_classes {
      hist.push(0);
      c = c + 1;
    }
    var i = 3;
    while i < frame.len() {
      let si: Int = frame[i];
      let lbl: Int = labels[si];
      let ci: Int = _class_index(classes, lbl);
      if ci < 0 {
        return _err_int("randomforest: label missing from the class list");
      }
      let h: Int = hist[ci];
      hist[ci] = h + 1;
      i = i + 1;
    }
    // Majority label (ties: lowest class index) and present-class count.
    var best = 0;
    var best_count: Int = hist[0];
    var present = 0;
    c = 0;
    while c < n_classes {
      let h2: Int = hist[c];
      if h2 > 0 {
        present = present + 1;
        if h2 > best_count {
          best_count = h2;
          best = c;
        }
      }
      c = c + 1;
    }
    let best_label: Int = classes[best];
    // Append the node (leaf by default) and link it to its parent.
    let k = _node_append(nodes);
    _node_set(nodes, k, _RF_NODE_FEATURE, -1);
    _node_set(nodes, k, _RF_NODE_THRESHOLD, 0);
    _node_set(nodes, k, _RF_NODE_LEFT, -1);
    _node_set(nodes, k, _RF_NODE_RIGHT, -1);
    _node_set(nodes, k, _RF_NODE_LABEL, best_label);
    _node_set(nodes, k, _RF_NODE_COUNT, n);
    _node_set(nodes, k, _RF_NODE_LEAF, 1);
    _node_set(nodes, k, _RF_NODE_DEPTH, depth);
    if parent >= 0 {
      if side == 0 {
        _node_set(nodes, parent, _RF_NODE_LEFT, k);
      } else {
        _node_set(nodes, parent, _RF_NODE_RIGHT, k);
      }
    }
    // Stopping rules.
    var can_split = 1;
    if depth >= max_depth {
      can_split = 0;
    }
    if present <= 1 {
      can_split = 0;
    }
    if n < 2 * min_samples {
      can_split = 0;
    }
    if can_split == 1 {
      // Best split search: features ascending, thresholds ascending; a
      // strictly better score replaces the incumbent, so score ties keep
      // the earliest candidate (documented tie-break).
      var best_feature = -1;
      var best_threshold = 0;
      var best_score: Int = -1;
      var f = 0;
      while f < n_features {
        let vals: Vec[Int] = _distinct_values(features, n_features, &frame, f);
        var vi = 0;
        while vi < vals.len() {
          let v: Int = vals[vi];
          var lh = Vec[Int].new();
          var c2 = 0;
          while c2 < n_classes {
            lh.push(0);
            c2 = c2 + 1;
          }
          var rh = Vec[Int].new();
          c2 = 0;
          while c2 < n_classes {
            rh.push(0);
            c2 = c2 + 1;
          }
          var nL: Int = 0;
          var nR: Int = 0;
          i = 3;
          while i < frame.len() {
            let si: Int = frame[i];
            let xv: Int = features[si * n_features + f];
            let lbl: Int = labels[si];
            let ci: Int = _class_index(classes, lbl);
            if xv <= v {
              let hl: Int = lh[ci];
              lh[ci] = hl + 1;
              nL = nL + 1;
            } else {
              let hr: Int = rh[ci];
              rh[ci] = hr + 1;
              nR = nR + 1;
            }
            i = i + 1;
          }
          if nL >= min_samples && nR >= min_samples {
            let a = _sum_sq(&lh);
            let b = _sum_sq(&rh);
            let score = (a * _RF_SCALE) / nL + (b * _RF_SCALE) / nR;
            if score > best_score {
              best_score = score;
              best_feature = f;
              best_threshold = v;
            }
          }
          vi = vi + 1;
        }
        f = f + 1;
      }
      if best_feature >= 0 {
        _node_set(nodes, k, _RF_NODE_FEATURE, best_feature);
        _node_set(nodes, k, _RF_NODE_THRESHOLD, best_threshold);
        _node_set(nodes, k, _RF_NODE_LEAF, 0);
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

// ---------------------------------------------------------------------------
// Leaf Result constructors
// ---------------------------------------------------------------------------

fn _ok_forest(f: Forest) -> Result[Forest, Str] {
  return Ok(f);
}

fn _err_forest(msg: Str) -> Result[Forest, Str] {
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
