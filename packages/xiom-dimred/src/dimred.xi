// XIOM -- xiom.dimred: fixed-point PCA primitives on scaled integers
// Port task: replace the xiom.dimred placeholder with a pure-XIOM module
// (scaled integers only: no floats, no FFI, no I/O, no Vec[Float64]).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model: every real number is a scaled integer. A raw value `r` with `d`
// fraction digits denotes the real number r / 10^d. Three scales are used:
//
//   data   3 fraction digits (raw = value * 1000)      -- rows, means, scores
//   cov    3 fraction digits (raw = covariance * 1000) -- covariance entries
//   vector 6 fraction digits (raw = component * 1e6)   -- eigenvectors
//
// Components are normalized so that the largest-magnitude entry is
// 1.000000 (raw 1000000) and its sign is fixed positive, which removes the
// eigenvector sign ambiguity. The dominant eigenvalue estimate is the
// infinity norm of A*v for that normalized v (raw units of the cov scale).
//
// Arithmetic is 64-bit integer arithmetic with truncating division
// (XIOM lowers `/` to truncation; see docs/SPEC.md for the exact rounding
// rules and the safe magnitude envelope). Multiplication followed by a
// division by 1e6 goes through _mul_div1e6, which splits the first factor so
// the product cannot overflow inside the documented envelope; it truncates
// twice, so it may differ from a single truncated product by one unit.
//
// Free functions only (XIOM v0.62.0 has no methods); every public function
// is `dimred_*`. Result constructors live in the leaf helpers at the bottom
// (constructing Ok/Err inline miscompiles in some v0.62.0 code shapes).

module xiom.dimred

use xiom.string;
use xiom.convert;

const _DIMRED_DATA_DEC: Int = 3;
const _DIMRED_COV_DEC: Int = 3;
const _DIMRED_VEC_DEC: Int = 6;
const _DIMRED_DATA_ONE: Int = 1000;
const _DIMRED_VEC_ONE: Int = 1000000;
const _DIMRED_BPS: Int = 10000;
const _DIMRED_INT_MAX: Int = 9223372036854775807;

/// Dense row-major matrix of scaled integers: `data[r * cols + c]`.
///
/// Fields are internal implementation detail; use the dimred_matrix_*
/// accessors. See SPEC.md for the scale of the values each API expects and
/// produces.
pub type DimredMatrix = {
  rows: Int;
  cols: Int;
  data: Vec[Int];
}

/// Dominant-eigenpair estimate.
///
/// `value` is the eigenvalue in covariance scale (raw = value * 1000);
/// `vector` holds one entry per feature in vector scale (raw = value * 1e6),
/// max-magnitude entry 1000000 with positive sign; `iterations` is the number
/// of power iterations performed (0 when the estimate is a failure dummy).
pub type Eigenpair = {
  value: Int;
  vector: Vec[Int];
  iterations: Int;
}

/// Fitted PCA model returned by dimred_pca_fit.
///
/// `means` (data scale, n_features entries), `components` (n_components rows
/// of n_features vector-scale entries, row-major), `eigenvalues` (cov
/// scale), `explained_bps` (basis points of the total covariance trace,
/// clamped to [0, 10000]) and `iterations` (per component) are parallel:
/// entry k of the last three and row k of `components` all describe
/// component k.
pub type PcaModel = {
  means: Vec[Int];
  components: Vec[Int];
  eigenvalues: Vec[Int];
  explained_bps: Vec[Int];
  iterations: Vec[Int];
  n_features: Int;
  n_components: Int;
}

// Private power-iteration attempt. A plain struct (not a Result) so callers
// can branch with `if !att.ok` instead of a capturing match.
type _PowerAttempt = {
  ok: Bool;
  pair: Eigenpair;
  error: Str;
}

// ---------------------------------------------------------------------------
// Scale accessors
// ---------------------------------------------------------------------------

/// Fraction digits of input data, means and projected scores (3).
pub fn dimred_data_decimals() -> Int {
  return _DIMRED_DATA_DEC;
}

/// Fraction digits of covariance entries and eigenvalues (3).
pub fn dimred_covariance_decimals() -> Int {
  return _DIMRED_COV_DEC;
}

/// Fraction digits of eigenvectors (6).
pub fn dimred_vector_decimals() -> Int {
  return _DIMRED_VEC_DEC;
}

// ---------------------------------------------------------------------------
// Matrix construction and access
// ---------------------------------------------------------------------------

/// Build a row-major matrix from a flat values vector.
/// Params: rows - number of rows (> 0); cols - number of columns (> 0);
///         values - the rows*cols scaled values, row-major.
/// Returns: Ok(matrix) with a private copy of values.
/// Error case: Err("dimred: ...") when rows or cols is not positive, when
/// rows*cols overflows, or when values.len() != rows*cols.
/// Complexity: O(rows*cols).
pub fn dimred_matrix_new(rows: Int, cols: Int, values: &Vec[Int]) -> Result[DimredMatrix, Str] {
  if rows <= 0 {
    return _err_matrix("dimred: rows must be positive");
  }
  if cols <= 0 {
    return _err_matrix("dimred: cols must be positive");
  }
  if rows > _DIMRED_INT_MAX / cols {
    return _err_matrix("dimred: rows*cols overflows");
  }
  let want = rows * cols;
  if values.len() != want {
    return _err_matrix("dimred: values length does not match rows*cols");
  }
  var copied = Vec[Int].new();
  var i = 0;
  while i < want {
    let v: Int = values[i];
    copied.push(v);
    i = i + 1;
  }
  return _ok_matrix(DimredMatrix{ rows: rows; cols: cols; data: copied; });
}

/// Row count. Complexity: O(1).
pub fn dimred_matrix_rows(m: &DimredMatrix) -> Int {
  return m.rows;
}

/// Column count. Complexity: O(1).
pub fn dimred_matrix_cols(m: &DimredMatrix) -> Int {
  return m.cols;
}

/// Scaled value at (row, col), or 0 when the index is out of range.
/// Complexity: O(1).
pub fn dimred_matrix_get(m: &DimredMatrix, row: Int, col: Int) -> Int {
  if row < 0 {
    return 0;
  }
  if col < 0 {
    return 0;
  }
  if row >= m.rows {
    return 0;
  }
  if col >= m.cols {
    return 0;
  }
  let idx = row * m.cols + col;
  if idx >= m.data.len() {
    return 0;
  }
  let got: Int = m.data[idx];
  return got;
}

/// Copy of the flat row-major data. Complexity: O(rows*cols).
pub fn dimred_matrix_data(m: &DimredMatrix) -> Vec[Int] {
  return _copy_ints(&m.data);
}

// ---------------------------------------------------------------------------
// Column means, mean-centering, covariance
// ---------------------------------------------------------------------------

/// Arithmetic mean of every column, in data scale.
/// Params: m - a matrix with rows > 0 and cols > 0.
/// Returns: Ok(means) with one entry per column, each
/// round_half_away_from_zero(column_sum / rows).
/// Error case: Err("dimred: ...") when the matrix has no rows or no columns.
/// Complexity: O(rows*cols).
pub fn dimred_column_means(m: &DimredMatrix) -> Result[Vec[Int], Str] {
  if m.rows <= 0 {
    return _err_ints("dimred: matrix has no rows");
  }
  if m.cols <= 0 {
    return _err_ints("dimred: matrix has no columns");
  }
  return _ok_ints(_column_means(m));
}

/// Subtract per-column means from every row.
/// Params: m - a matrix with rows > 0 and cols > 0; means - one data-scale
///         mean per column, normally from dimred_column_means.
/// Returns: Ok(centered matrix) with the same shape, entry = m[r, c] - means[c].
/// Error case: Err("dimred: ...") when the matrix is empty or
/// means.len() != cols.
/// Complexity: O(rows*cols).
pub fn dimred_center(m: &DimredMatrix, means: &Vec[Int]) -> Result[DimredMatrix, Str] {
  if m.rows <= 0 {
    return _err_matrix("dimred: matrix has no rows");
  }
  if m.cols <= 0 {
    return _err_matrix("dimred: matrix has no columns");
  }
  if means.len() != m.cols {
    return _err_matrix("dimred: means length mismatch");
  }
  return _ok_matrix(_center_with(m, means));
}

/// Sample covariance of a mean-centered matrix (denominator rows - 1).
/// Params: centered - a centered matrix with rows >= 2 and cols > 0.
/// Returns: Ok(cols x cols covariance, symmetric). Entry (i, j) is
/// sum_r (centered[r,i] * centered[r,j] / 1000), rounded half away from zero
/// and divided by (rows - 1); each row term is truncated to data scale
/// before accumulation, so the accumulated error stays below one unit of
/// the covariance scale divided by the sample count.
/// Error case: Err("dimred: ...") when rows < 2 or cols <= 0.
/// Complexity: O(cols^2 * rows).
pub fn dimred_covariance(centered: &DimredMatrix) -> Result[DimredMatrix, Str] {
  if centered.rows <= 1 {
    return _err_matrix("dimred: covariance needs at least 2 samples");
  }
  if centered.cols <= 0 {
    return _err_matrix("dimred: matrix has no columns");
  }
  return _ok_matrix(_covariance(centered));
}

// ---------------------------------------------------------------------------
// Power iteration and deflation
// ---------------------------------------------------------------------------

/// Dominant eigenpair of a symmetric covariance matrix by power iteration.
/// Params: cov - square matrix in covariance scale; init - one vector-scale
///         entry per feature (not all zeros); max_iter - iteration budget
///         (>= 1); tol - convergence tolerance in vector-scale raw units
///         (>= 0), compared against the largest per-entry change of the
///         normalized iterate.
/// Returns: Ok(eigenpair) with the eigenvalue estimate (cov scale), the
/// normalized eigenvector (vector scale) and the iteration count.
/// Iteration: v(n+1) = normalize_max(cov * v(n) / 1e6); the vector is scaled
/// so its largest entry is 1000000 and that entry is positive; the
/// eigenvalue estimate is the infinity norm of cov * v(n) / 1e6 in cov
/// scale. Convergence holds when the largest entry change is <= tol.
/// Error case: Err("dimred: ...") for a non-square or empty matrix, a zero
/// or mis-sized init, max_iter < 1, tol < 0, an all-zero covariance matrix,
/// or failure to converge within max_iter iterations.
/// Complexity: O(max_iter * features^2).
pub fn dimred_power_iteration(cov: &DimredMatrix, init: &Vec[Int], max_iter: Int, tol: Int) -> Result[Eigenpair, Str] {
  if cov.rows <= 0 {
    return _err_eigen("dimred: matrix has no rows");
  }
  if cov.rows != cov.cols {
    return _err_eigen("dimred: covariance matrix must be square");
  }
  if init.len() != cov.rows {
    return _err_eigen("dimred: initial vector length mismatch");
  }
  if max_iter < 1 {
    return _err_eigen("dimred: max_iter must be at least 1");
  }
  if tol < 0 {
    return _err_eigen("dimred: tolerance must not be negative");
  }
  let m0 = _max_abs(init);
  if m0 == 0 {
    return _err_eigen("dimred: initial vector must not be all zeros");
  }
  let seed = _normalize_max(init, m0);
  let att = _power_from(cov, &seed, max_iter, tol);
  if !att.ok {
    return _err_eigen(att.error);
  }
  return _ok_eigen(att.pair);
}

/// Deflate a symmetric matrix by a known eigenpair: A' = A - lambda*v*v^T/(v^T v).
/// Params: cov - square matrix in covariance scale; ep - the eigenpair to
///         remove, vector in vector scale (any non-zero magnitude).
/// Returns: Ok(the deflated matrix) with the same shape; the eigenvalue
/// lambda becomes 0 and the remaining eigenvalues are unchanged (within
/// truncation error).
/// Error case: Err("dimred: ...") for a non-square or empty matrix, a
/// mis-sized eigenvector or an all-zero eigenvector.
/// Complexity: O(features^2).
pub fn dimred_deflate(cov: &DimredMatrix, ep: &Eigenpair) -> Result[DimredMatrix, Str] {
  if cov.rows <= 0 {
    return _err_matrix("dimred: matrix has no rows");
  }
  if cov.rows != cov.cols {
    return _err_matrix("dimred: covariance matrix must be square");
  }
  if ep.vector.len() != cov.rows {
    return _err_matrix("dimred: eigenvector length mismatch");
  }
  let d = _dot_self(&ep.vector);
  if d == 0 {
    return _err_matrix("dimred: eigenvector must not be all zeros");
  }
  return _ok_matrix(_deflate_with(cov, ep.value, &ep.vector, d));
}

// ---------------------------------------------------------------------------
// Projection
// ---------------------------------------------------------------------------

/// Project mean-centered samples onto one component (the PCA scores).
/// Params: centered - n x m mean-centered data in data scale; component -
///         m vector-scale entries (usually a row of PcaModel.components).
/// Returns: Ok(scores) with one data-scale score per row:
/// sum_j centered[r, j] * component[j] / 1e6.
/// Error case: Err("dimred: ...") when the matrix is empty or
/// component.len() != cols.
/// Complexity: O(rows*cols).
pub fn dimred_project(centered: &DimredMatrix, component: &Vec[Int]) -> Result[Vec[Int], Str] {
  if centered.rows <= 0 {
    return _err_ints("dimred: matrix has no rows");
  }
  if centered.cols <= 0 {
    return _err_ints("dimred: matrix has no columns");
  }
  if component.len() != centered.cols {
    return _err_ints("dimred: component length mismatch");
  }
  return _ok_ints(_project(centered, component));
}

// ---------------------------------------------------------------------------
// Explained variance
// ---------------------------------------------------------------------------

/// Share of the total variance carried by one eigenvalue, in basis points.
/// Params: eigenvalue - covariance-scale eigenvalue; cov - square covariance
///         matrix whose trace is the total variance (covariance scale).
/// Returns: Ok(basis points) = clamp(round_half_away(eigenvalue * 10000 /
/// trace), 0, 10000). The trace equals the sum of all eigenvalues, so this
/// is the classical explained-variance ratio without a full eigendecomposition.
/// Error case: Err("dimred: ...") for a non-square or empty matrix, or a
/// non-positive trace.
/// Complexity: O(features).
pub fn dimred_explained_variance_bps(eigenvalue: Int, cov: &DimredMatrix) -> Result[Int, Str] {
  if cov.rows <= 0 {
    return _err_int("dimred: matrix has no rows");
  }
  if cov.rows != cov.cols {
    return _err_int("dimred: covariance matrix must be square");
  }
  let total = _trace(cov);
  if total <= 0 {
    return _err_int("dimred: covariance trace must be positive");
  }
  return _ok_int(_explained_bps(eigenvalue, total));
}

// ---------------------------------------------------------------------------
// Convenience: fit, transform, accessors
// ---------------------------------------------------------------------------

/// Fit PCA: means, up to `n_components` eigenpairs and explained-variance
/// basis points.
/// Params: data - n x m samples in data scale (n >= 2, m >= 1);
///         n_components - number of components to extract, 1..m;
///         max_iter - power-iteration budget per component (>= 1);
///         tol - convergence tolerance per component (>= 0).
/// Returns: Ok(PcaModel). Mean-centering uses dimred_column_means;
/// covariance uses dimred_covariance; component 0 comes from power iteration
/// on the covariance seeded with the all-ones vector; component k > 0 comes
/// from power iteration on the matrix deflated by components 0..k-1.
/// explained_bps uses the trace of the full covariance as denominator.
/// Error case: Err("dimred: ...") for n < 2, m <= 0, n_components outside
/// 1..m, max_iter < 1, tol < 0, a non-positive covariance trace (all rows
/// identical), or a power iteration that does not converge.
/// Complexity: O(n*m^2 + n_components * max_iter * m^2).
pub fn dimred_pca_fit(data: &DimredMatrix, n_components: Int, max_iter: Int, tol: Int) -> Result[PcaModel, Str] {
  if data.rows < 2 {
    return _err_model("dimred: pca needs at least 2 samples");
  }
  if data.cols <= 0 {
    return _err_model("dimred: matrix has no columns");
  }
  if n_components < 1 {
    return _err_model("dimred: number of components must be at least 1");
  }
  if n_components > data.cols {
    return _err_model("dimred: number of components exceeds feature count");
  }
  if max_iter < 1 {
    return _err_model("dimred: max_iter must be at least 1");
  }
  if tol < 0 {
    return _err_model("dimred: tolerance must not be negative");
  }

  let means = _column_means(data);
  let centered = _center_with(data, &means);
  var work = _covariance(&centered);
  let total = _trace(&work);
  if total <= 0 {
    return _err_model("dimred: covariance trace must be positive");
  }

  var comps = Vec[Int].new();
  var eigs = Vec[Int].new();
  var bps = Vec[Int].new();
  var iters = Vec[Int].new();
  var k = 0;
  while k < n_components {
    let att = _power_attempt(&work, max_iter, tol);
    if !att.ok {
      return _err_model(att.error);
    }
    let ep = att.pair;
    let ev = _copy_ints(&ep.vector);
    var j = 0;
    while j < ev.len() {
      let x: Int = ev[j];
      comps.push(x);
      j = j + 1;
    }
    eigs.push(ep.value);
    bps.push(_explained_bps(ep.value, total));
    iters.push(ep.iterations);
    if k + 1 < n_components {
      let d = _dot_self(&ev);
      let next = _deflate_with(&work, ep.value, &ev, d);
      work = next;
    }
    k = k + 1;
  }
  return _ok_model(PcaModel{ means: means; components: comps; eigenvalues: eigs; explained_bps: bps; iterations: iters; n_features: data.cols; n_components: n_components; });
}

/// Center new samples with the model means and project them onto every
/// model component.
/// Params: model - a fitted PcaModel; data - n x m samples in data scale
///         with m == model.n_features (n >= 1).
/// Returns: Ok(n x n_components score matrix in data scale), row-major;
/// score[r, k] = sum_j (data[r, j] - means[j]) * component[k, j] / 1e6.
/// Error case: Err("dimred: ...") when data has no rows, its feature count
/// differs from the model, or the model carries no components.
/// Complexity: O(n * n_components * m).
pub fn dimred_pca_transform(model: &PcaModel, data: &DimredMatrix) -> Result[DimredMatrix, Str] {
  if data.rows <= 0 {
    return _err_matrix("dimred: matrix has no rows");
  }
  if data.cols != model.n_features {
    return _err_matrix("dimred: feature count does not match the model");
  }
  if model.n_components < 1 {
    return _err_matrix("dimred: model has no components");
  }
  let need = model.n_components * model.n_features;
  if model.components.len() < need {
    return _err_matrix("dimred: model components are inconsistent");
  }
  let means = _copy_ints(&model.means);
  let centered = _center_with(data, &means);
  var out = Vec[Int].new();
  var r = 0;
  while r < centered.rows {
    var k = 0;
    while k < model.n_components {
      var s: Int = 0;
      var j = 0;
      while j < centered.cols {
        let c: Int = centered.data[r * centered.cols + j];
        let idx = k * centered.cols + j;
        if idx < model.components.len() {
          let v: Int = model.components[idx];
          s = s + _mul_div1e6(c, v);
        }
        j = j + 1;
      }
      out.push(s);
      k = k + 1;
    }
    r = r + 1;
  }
  return _ok_matrix(DimredMatrix{ rows: data.rows; cols: model.n_components; data: out; });
}

/// Feature count of a fitted model. Complexity: O(1).
pub fn dimred_pca_n_features(model: &PcaModel) -> Int {
  return model.n_features;
}

/// Component count of a fitted model. Complexity: O(1).
pub fn dimred_pca_n_components(model: &PcaModel) -> Int {
  return model.n_components;
}

/// Data-scale mean of `feature`, or 0 when out of range. Complexity: O(1).
pub fn dimred_pca_mean(model: &PcaModel, feature: Int) -> Int {
  if feature < 0 {
    return 0;
  }
  if feature >= model.means.len() {
    return 0;
  }
  let got: Int = model.means[feature];
  return got;
}

/// Copy of component `comp` (vector scale, features entries); empty when
/// `comp` is out of range. Complexity: O(features).
pub fn dimred_pca_component(model: &PcaModel, comp: Int) -> Vec[Int] {
  var out = Vec[Int].new();
  if comp < 0 {
    return out;
  }
  if comp >= model.n_components {
    return out;
  }
  let base = comp * model.n_features;
  var j = 0;
  while j < model.n_features {
    let idx = base + j;
    if idx >= model.components.len() {
      return out;
    }
    let x: Int = model.components[idx];
    out.push(x);
    j = j + 1;
  }
  return out;
}

/// Covariance-scale eigenvalue of component `comp`, or 0 when out of range.
/// Complexity: O(1).
pub fn dimred_pca_eigenvalue(model: &PcaModel, comp: Int) -> Int {
  if comp < 0 {
    return 0;
  }
  if comp >= model.eigenvalues.len() {
    return 0;
  }
  let got: Int = model.eigenvalues[comp];
  return got;
}

/// Explained-variance basis points of component `comp`, or 0 when out of
/// range. Complexity: O(1).
pub fn dimred_pca_explained_bps(model: &PcaModel, comp: Int) -> Int {
  if comp < 0 {
    return 0;
  }
  if comp >= model.explained_bps.len() {
    return 0;
  }
  let got: Int = model.explained_bps[comp];
  return got;
}

/// Power iterations spent on component `comp`, or 0 when out of range.
/// Complexity: O(1).
pub fn dimred_pca_iterations(model: &PcaModel, comp: Int) -> Int {
  if comp < 0 {
    return 0;
  }
  if comp >= model.iterations.len() {
    return 0;
  }
  let got: Int = model.iterations[comp];
  return got;
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

// Truncating division helper: a / b with halves rounded away from zero.
// b > 0; a and b are small enough that 2*|a % b| cannot overflow.
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

// (a * b) / 1000000 without overflowing the intermediate product inside the
// documented envelope: a is split into a high part (a/1000) and a remainder,
// each multiplied by b separately. Truncates twice, so the result can be one
// unit below the single-step truncation (exact when b == 1000000).
fn _mul_div1e6(a: Int, b: Int) -> Int {
  let ah = a / 1000;
  let ar = a % 1000;
  let hi = (ah * b) / 1000;
  let lo = ((ar * b) / 1000) / 1000;
  return hi + lo;
}

fn _copy_ints(v: &Vec[Int]) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 0;
  while i < v.len() {
    let x: Int = v[i];
    out.push(x);
    i = i + 1;
  }
  return out;
}

fn _negate_ints(v: &Vec[Int]) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 0;
  while i < v.len() {
    let x: Int = v[i];
    out.push(0 - x);
    i = i + 1;
  }
  return out;
}

fn _max_abs(v: &Vec[Int]) -> Int {
  var best: Int = 0;
  var i = 0;
  while i < v.len() {
    var x: Int = v[i];
    if x < 0 {
      x = 0 - x;
    }
    if x > best {
      best = x;
    }
    i = i + 1;
  }
  return best;
}

fn _max_abs_index(v: &Vec[Int]) -> Int {
  var best: Int = 0;
  var idx: Int = 0;
  var i = 0;
  while i < v.len() {
    var x: Int = v[i];
    if x < 0 {
      x = 0 - x;
    }
    if x > best {
      best = x;
      idx = i;
    }
    i = i + 1;
  }
  return idx;
}

fn _max_diff(a: &Vec[Int], b: &Vec[Int]) -> Int {
  var best: Int = 0;
  var i = 0;
  while i < a.len() {
    if i < b.len() {
      let x: Int = a[i];
      let y: Int = b[i];
      var d: Int = x - y;
      if d < 0 {
        d = 0 - d;
      }
      if d > best {
        best = d;
      }
    }
    i = i + 1;
  }
  return best;
}

// Divide every entry by `scale` after scaling by 1e6 (scale > 0).
// Callers guarantee scale is the max magnitude, so the product fits the
// documented envelope and entries land in [-1000000, 1000000].
fn _normalize_max(v: &Vec[Int], scale: Int) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 0;
  while i < v.len() {
    let x: Int = v[i];
    out.push(x * _DIMRED_VEC_ONE / scale);
    i = i + 1;
  }
  return out;
}

fn _dot_self(v: &Vec[Int]) -> Int {
  var s: Int = 0;
  var i = 0;
  while i < v.len() {
    let x: Int = v[i];
    s = s + _mul_div1e6(x, x);
    i = i + 1;
  }
  return s;
}

fn _matvec(a: &DimredMatrix, v: &Vec[Int]) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 0;
  while i < a.rows {
    var s: Int = 0;
    var j = 0;
    while j < a.cols {
      let aij: Int = a.data[i * a.cols + j];
      let vj: Int = v[j];
      s = s + _mul_div1e6(aij, vj);
      j = j + 1;
    }
    out.push(s);
    i = i + 1;
  }
  return out;
}

fn _zero_pair(n: Int) -> Eigenpair {
  var z = Vec[Int].new();
  var i = 0;
  while i < n {
    z.push(0);
    i = i + 1;
  }
  return Eigenpair{ value: 0; vector: z; iterations: 0; };
}

// Power iteration with an already max-normalized seed (max magnitude 1e6).
fn _power_from(cov: &DimredMatrix, seed: &Vec[Int], max_iter: Int, tol: Int) -> _PowerAttempt {
  var vv = _copy_ints(seed);
  var iter = 0;
  var lambda: Int = 0;
  var converged = false;
  var collapsed = false;
  while iter < max_iter {
    let w = _matvec(cov, &vv);
    let sc = _max_abs(&w);
    if sc == 0 {
      collapsed = true;
      break;
    }
    let cand = _normalize_max(&w, sc);
    let k = _max_abs_index(&w);
    var signed = cand;
    let pivot: Int = signed[k];
    if pivot < 0 {
      signed = _negate_ints(&signed);
    }
    lambda = sc;
    iter = iter + 1;
    let diff = _max_diff(&vv, &signed);
    vv = signed;
    if diff <= tol {
      converged = true;
      break;
    }
  }
  if collapsed {
    let zero_cov = _max_abs(&cov.data) == 0;
    if zero_cov {
      return _PowerAttempt{ ok: false; pair: _zero_pair(cov.rows); error: "dimred: covariance matrix is zero"; };
    }
    return _PowerAttempt{ ok: false; pair: _zero_pair(cov.rows); error: "dimred: initial vector is in the null space"; };
  }
  if !converged {
    return _PowerAttempt{ ok: false; pair: _zero_pair(cov.rows); error: "dimred: power iteration did not converge"; };
  }
  return _PowerAttempt{ ok: true; pair: Eigenpair{ value: lambda; vector: vv; iterations: iter; }; error: ""; };
}

// Deterministic all-ones seed at vector scale.
fn _ones_seed(n: Int) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 0;
  while i < n {
    out.push(_DIMRED_VEC_ONE);
    i = i + 1;
  }
  return out;
}

fn _power_attempt(cov: &DimredMatrix, max_iter: Int, tol: Int) -> _PowerAttempt {
  let seed = _ones_seed(cov.rows);
  return _power_from(cov, &seed, max_iter, tol);
}

// A' = A - lambda * v * v^T / d with d = v^T v already scaled (1e6) for v.
fn _deflate_with(cov: &DimredMatrix, lambda: Int, v: &Vec[Int], d: Int) -> DimredMatrix {
  let md = cov.rows;
  var out = Vec[Int].new();
  var i = 0;
  while i < md {
    var j = 0;
    while j < md {
      let a: Int = cov.data[i * md + j];
      let vi: Int = v[i];
      let vj: Int = v[j];
      let t = vi * vj / d;
      let corr = _mul_div1e6(lambda, t);
      out.push(a - corr);
      j = j + 1;
    }
    i = i + 1;
  }
  return DimredMatrix{ rows: md; cols: md; data: out; };
}

fn _project(x: &DimredMatrix, v: &Vec[Int]) -> Vec[Int] {
  var out = Vec[Int].new();
  var r = 0;
  while r < x.rows {
    var s: Int = 0;
    var j = 0;
    while j < x.cols {
      let c: Int = x.data[r * x.cols + j];
      let vj: Int = v[j];
      s = s + _mul_div1e6(c, vj);
      j = j + 1;
    }
    out.push(s);
    r = r + 1;
  }
  return out;
}

fn _column_means(m: &DimredMatrix) -> Vec[Int] {
  var out = Vec[Int].new();
  var j = 0;
  while j < m.cols {
    var s: Int = 0;
    var i = 0;
    while i < m.rows {
      let v: Int = m.data[i * m.cols + j];
      s = s + v;
      i = i + 1;
    }
    out.push(_div_round(s, m.rows));
    j = j + 1;
  }
  return out;
}

fn _center_with(m: &DimredMatrix, means: &Vec[Int]) -> DimredMatrix {
  var out = Vec[Int].new();
  var i = 0;
  while i < m.rows {
    var j = 0;
    while j < m.cols {
      let v: Int = m.data[i * m.cols + j];
      let mu: Int = means[j];
      out.push(v - mu);
      j = j + 1;
    }
    i = i + 1;
  }
  return DimredMatrix{ rows: m.rows; cols: m.cols; data: out; };
}

// Full symmetric covariance: entry (i, j) = sum_r (x[r,i]*x[r,j]/1000) / (n-1).
fn _covariance(x: &DimredMatrix) -> DimredMatrix {
  let n = x.rows;
  let md = x.cols;
  let denom = n - 1;
  var out = Vec[Int].new();
  var i = 0;
  while i < md {
    var j = 0;
    while j < md {
      var s: Int = 0;
      var r = 0;
      while r < n {
        let a: Int = x.data[r * md + i];
        let b: Int = x.data[r * md + j];
        s = s + a * b / _DIMRED_DATA_ONE;
        r = r + 1;
      }
      out.push(_div_round(s, denom));
      j = j + 1;
    }
    i = i + 1;
  }
  return DimredMatrix{ rows: md; cols: md; data: out; };
}

fn _trace(m: &DimredMatrix) -> Int {
  var s: Int = 0;
  var i = 0;
  while i < m.rows {
    if i < m.cols {
      let v: Int = m.data[i * m.cols + i];
      s = s + v;
    }
    i = i + 1;
  }
  return s;
}

fn _explained_bps(lambda: Int, total: Int) -> Int {
  var v = _div_round(lambda * _DIMRED_BPS, total);
  if v < 0 {
    v = 0;
  }
  if v > _DIMRED_BPS {
    v = _DIMRED_BPS;
  }
  return v;
}

// ---------------------------------------------------------------------------
// Leaf Result constructors
// ---------------------------------------------------------------------------

fn _ok_matrix(m: DimredMatrix) -> Result[DimredMatrix, Str] {
  return Ok(m);
}

fn _err_matrix(msg: Str) -> Result[DimredMatrix, Str] {
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

fn _ok_eigen(ep: Eigenpair) -> Result[Eigenpair, Str] {
  return Ok(ep);
}

fn _err_eigen(msg: Str) -> Result[Eigenpair, Str] {
  return Err(msg);
}

fn _ok_model(m: PcaModel) -> Result[PcaModel, Str] {
  return Ok(m);
}

fn _err_model(msg: Str) -> Result[PcaModel, Str] {
  return Err(msg);
}
