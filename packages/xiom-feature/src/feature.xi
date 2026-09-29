// XIOM -- xiom.feature: feature engineering on scaled integers
// Port task: promote the xiom.feature placeholder to a real, tested,
// pure-XIOM package (no FFI, no I/O, no floats, no Vec[Float64]).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model: every real number is a scaled integer. A raw value `r` with 3
// fraction digits denotes the real number r / 1000 (the data scale returned
// by feature_data_decimals(); feature_data_one() is 1000). All extraction,
// scaling and expansion outputs are data scale unless a function says
// otherwise. Division (`/`) truncates toward zero; rounding helpers are
// implemented explicitly (see SPEC.md for the exact rules and the safe
// magnitude envelope).
//
// Pure and deterministic: no I/O, no clock access, no global state, no FFI,
// no allocation beyond the returned vectors and matrices. Free functions
// only (XIOM v0.62.1 has no methods); every public function is `feature_*`.
// Ok/Err are constructed only in the leaf helpers at the bottom of this
// file (constructing them inline miscompiles in some v0.62.1 code shapes).

module xiom.feature

use xiom.string;
use xiom.convert;

const _FF_DECIMALS: Int = 3;
const _FF_ONE: Int = 1000;
const _FF_INT_MAX: Int = 9223372036854775807;

// 32-bit FNV-1a constants (FNV-1a specification).
const _FF_FNV_OFFSET: Int = 2166136261; // 0x811C9DC5 offset basis
const _FF_FNV_PRIME: Int = 16777619;    // 0x01000193 prime
const _FF_U32_MOD: Int = 4294967296;    // 2^32

// Divisor used to shift the 32-bit hash right by 16 bits; the sign bit of
// the signed hashing variant is digit ((h / 65536) % 2), extracted with
// divisor/modulo arithmetic because sign-bit tests are unreliable on the pin.
const _FF_SIGN_DIV: Int = 65536; // 2^16

// Largest input length accepted by the polynomial helpers: n*(n+1)/2 must
// fit in Int (n = 2^32 - 1 gives 9223372034707292160).
const _FF_POLY2_MAX_N: Int = 4294967295;

/// Dense row-major feature matrix of scaled integers: data[r * cols + c].
///
/// Sample r is row r; feature j is column j. Every entry is data scale
/// (raw = value * 1000). Fields are internal implementation detail; use the
/// feature_matrix_* accessors.
pub type FeatureMatrix = {
  rows: Int;
  cols: Int;
  data: Vec[Int];
}

/// Summary of one scaled feature vector, all in data scale (raw = value *
/// 1000): the arithmetic mean (rounded half away from zero), the sample
/// variance (denominator n - 1, truncated products), and the minimum and
/// maximum entries. Fields are internal implementation detail.
pub type FeatureStats = {
  mean: Int;
  variance: Int;
  min: Int;
  max: Int;
}

/// Variance-threshold selection result.
///
/// `indices` and `variances` are parallel vectors of equal length: entry k
/// of each describes the same selected feature. Indices are strictly
/// ascending (features are scanned in column order) and each variance is in
/// data scale. Fields are internal implementation detail.
pub type FeatureSelection = {
  indices: Vec[Int];
  variances: Vec[Int];
}

// ---------------------------------------------------------------------------
// Scale accessors
// ---------------------------------------------------------------------------

/// Fraction digits of every scaled integer in this module (3).
pub fn feature_data_decimals() -> Int {
  return _FF_DECIMALS;
}

/// Raw value of 1.0 at the data scale (1000).
pub fn feature_data_one() -> Int {
  return _FF_ONE;
}

// ---------------------------------------------------------------------------
// (a) Polynomial expansion, degree 2
// ---------------------------------------------------------------------------

/// Number of degree-2 polynomial terms for `n` inputs: n*(n+1)/2
/// (n squares plus n*(n-1)/2 pairwise products).
/// Params: n - the number of input features.
/// Returns: Ok(term count). n = 0 gives 0.
/// Error case: Err("feature: ...") when n < 0 or n > 4294967295 (the count
/// would not fit in Int).
/// Complexity: O(1).
pub fn feature_poly2_count(n: Int) -> Result[Int, Str] {
  if n < 0 {
    return _err_int("feature: input length must not be negative");
  }
  if n > _FF_POLY2_MAX_N {
    return _err_int("feature: polynomial expansion count overflows");
  }
  return _ok_int(_poly2_count_raw(n));
}

/// Expand `v` to its degree-2 polynomial terms.
///
/// The output ordering is fixed and documented: for i = 0..n-1, for
/// j = i..n-1, the next term is x[i] * x[j] / 1000. So for n = 3 the terms
/// are (0,0), (0,1), (0,2), (1,1), (1,2), (2,2): all squares and pairwise
/// products, each exactly once, squares before the products that follow
/// them in row-major order.
/// Params: v - n data-scale inputs.
/// Returns: Ok(terms) with n*(n+1)/2 data-scale entries; each term is
/// x[i] * x[j] / 1000 with truncating division (toward zero).
/// Error case: Err("feature: ...") when the term count does not fit in Int
/// (n > 4294967295; unreachable for real vectors) or an intermediate
/// product overflows (see SPEC.md envelope).
/// Complexity: O(n^2).
pub fn feature_poly2_expand(v: &Vec[Int]) -> Result[Vec[Int], Str] {
  let n = v.len();
  if n > _FF_POLY2_MAX_N {
    return _err_ints("feature: polynomial expansion count overflows");
  }
  var out = Vec[Int].new();
  var i = 0;
  while i < n {
    let a: Int = v[i];
    var j = i;
    while j < n {
      let b: Int = v[j];
      out.push(a * b / _FF_ONE);
      j = j + 1;
    }
    i = i + 1;
  }
  return _ok_ints(out);
}

// ---------------------------------------------------------------------------
// (b) Feature hashing ("hashing trick")
// ---------------------------------------------------------------------------

/// 32-bit FNV-1a hash of the UTF-8 bytes of `token`.
///
/// h starts at 2166136261; for every byte b: h = ((h XOR b) * 16777619)
/// mod 2^32. Bytes are read with byte_at, widened to Int and masked with
/// 0xFF (bytes >= 128 are miscompiled without the mask on the pin). The
/// hash is deterministic across runs and machines.
/// Params: token - the feature token (any UTF-8 string, "" allowed).
/// Returns: the hash in [0, 2^32).
/// Errors: none. Complexity: O(token length).
pub fn feature_hash32(token: Str) -> Int {
  return _fnv1a32(token);
}

/// Map `token` to a feature bucket in [0, buckets).
/// Params: token - the feature token; buckets - the number of buckets.
/// Returns: Ok(bucket) = feature_hash32(token) % buckets.
/// Error case: Err("feature: buckets must be positive") when buckets <= 0.
/// Complexity: O(token length).
pub fn feature_hash_bucket(token: Str, buckets: Int) -> Result[Int, Str] {
  if buckets <= 0 {
    return _err_int("feature: buckets must be positive");
  }
  return _ok_int(_fnv1a32(token) % buckets);
}

/// Signed hashing-trick variant: `token` maps to a nonzero signed index.
///
/// The bucket is computed exactly as feature_hash_bucket. One extra hash bit
/// (digit 1 of h / 2^16, i.e. bit 16 of the 32-bit hash) selects the sign;
/// digit 0 means positive. The result is (bucket + 1) for digit 0 and
/// -(bucket + 1) for digit 1, so the sign survives even for bucket 0 and the
/// value is never 0. The magnitude is one-based: |result| - 1 is the bucket.
/// Params: token - the feature token; buckets - the number of buckets.
/// Returns: Ok(signed index) in [-(buckets), buckets], never 0.
/// Error case: Err("feature: buckets must be positive") when buckets <= 0.
/// Complexity: O(token length).
pub fn feature_hash_bucket_signed(token: Str, buckets: Int) -> Result[Int, Str] {
  if buckets <= 0 {
    return _err_int("feature: buckets must be positive");
  }
  return _ok_int(_signed_bucket(_fnv1a32(token), buckets));
}

// ---------------------------------------------------------------------------
// (c) Extraction over one scaled feature vector
// ---------------------------------------------------------------------------

/// Arithmetic mean of a data-scale vector.
/// Params: v - one or more data-scale values.
/// Returns: Ok(mean) = round_half_away_from_zero(sum / n).
/// Error case: Err("feature: empty vector") when v is empty.
/// Complexity: O(n).
pub fn feature_mean(v: &Vec[Int]) -> Result[Int, Str] {
  let n = v.len();
  if n < 1 {
    return _err_int("feature: empty vector");
  }
  return _ok_int(_mean_raw(v));
}

/// Sample variance of a data-scale vector (denominator n - 1).
///
/// mean = round_half_away_from_zero(sum / n); each squared deviation is
/// truncated to data scale (d * d / 1000); the sum is divided by n - 1 with
/// round-half-away-from-zero. Variance is in data scale, so a real variance
/// of 2.0 is raw 2000.
/// Params: v - at least two data-scale values.
/// Returns: Ok(variance) >= 0.
/// Error case: Err("feature: variance needs at least 2 samples") when
/// v.len() < 2. Small real variances can truncate to 0.
/// Complexity: O(n).
pub fn feature_variance(v: &Vec[Int]) -> Result[Int, Str] {
  let n = v.len();
  if n < 2 {
    return _err_int("feature: variance needs at least 2 samples");
  }
  return _ok_int(_variance_raw(v));
}

/// Smallest entry of a data-scale vector (first-seen on ties).
/// Params: v - one or more data-scale values.
/// Returns: Ok(min).
/// Error case: Err("feature: empty vector") when v is empty.
/// Complexity: O(n).
pub fn feature_min(v: &Vec[Int]) -> Result[Int, Str] {
  let n = v.len();
  if n < 1 {
    return _err_int("feature: empty vector");
  }
  let first: Int = v[0];
  var best: Int = first;
  var i = 1;
  while i < n {
    let x: Int = v[i];
    if x < best {
      best = x;
    }
    i = i + 1;
  }
  return _ok_int(best);
}

/// Largest entry of a data-scale vector (first-seen on ties).
/// Params: v - one or more data-scale values.
/// Returns: Ok(max).
/// Error case: Err("feature: empty vector") when v is empty.
/// Complexity: O(n).
pub fn feature_max(v: &Vec[Int]) -> Result[Int, Str] {
  let n = v.len();
  if n < 1 {
    return _err_int("feature: empty vector");
  }
  let first: Int = v[0];
  var best: Int = first;
  var i = 1;
  while i < n {
    let x: Int = v[i];
    if x > best {
      best = x;
    }
    i = i + 1;
  }
  return _ok_int(best);
}

/// Mean, sample variance, minimum and maximum of a data-scale vector in one
/// pass over the values (the variance is the feature_variance value).
/// Params: v - at least two data-scale values.
/// Returns: Ok(FeatureStats) with all four quantities in data scale.
/// Error case: Err("feature: stats need at least 2 samples") when
/// v.len() < 2 (a single value has no variance).
/// Complexity: O(n).
pub fn feature_stats(v: &Vec[Int]) -> Result[FeatureStats, Str] {
  let n = v.len();
  if n < 2 {
    return _err_stats("feature: stats need at least 2 samples");
  }
  let mu = _mean_raw(v);
  let first: Int = v[0];
  var lo: Int = first;
  var hi: Int = first;
  var i = 1;
  while i < n {
    let x: Int = v[i];
    if x < lo {
      lo = x;
    }
    if x > hi {
      hi = x;
    }
    i = i + 1;
  }
  let va = _variance_raw(v);
  return _ok_stats(FeatureStats{ mean: mu; variance: va; min: lo; max: hi; });
}

// ---------------------------------------------------------------------------
// (d) Scaling
// ---------------------------------------------------------------------------

/// Min-max scale a data-scale vector onto the raw target range [lo, hi].
///
/// out[i] = lo + (x[i] - min) * (hi - lo) / (max - min), with truncating
/// divisions. The target values are raw integers in the caller's chosen
/// fixed-point scale: [0, 1000] maps the data-scale minimum to 0.000 and the
/// maximum to 1.000. Reversed targets (hi < lo) invert the mapping; lo == hi
/// maps every value to the constant lo.
/// Params: v - at least one data-scale value; lo, hi - raw target endpoints.
/// Returns: Ok(scaled) with v.len() entries.
/// Error case: Err("feature: ...") when v is empty or constant (max == min,
/// where the mapping is undefined).
/// Complexity: O(n).
pub fn feature_minmax_scale(v: &Vec[Int], lo: Int, hi: Int) -> Result[Vec[Int], Str] {
  let n = v.len();
  if n < 1 {
    return _err_ints("feature: empty vector");
  }
  let first: Int = v[0];
  var mn: Int = first;
  var mx: Int = first;
  var i = 1;
  while i < n {
    let x: Int = v[i];
    if x < mn {
      mn = x;
    }
    if x > mx {
      mx = x;
    }
    i = i + 1;
  }
  let range = mx - mn;
  if range == 0 {
    return _err_ints("feature: min-max scaling requires a non-constant feature");
  }
  let span = hi - lo;
  var out = Vec[Int].new();
  var k = 0;
  while k < n {
    let x: Int = v[k];
    out.push(lo + (x - mn) * span / range);
    k = k + 1;
  }
  return _ok_ints(out);
}

/// Z-score scale a data-scale vector: out[i] = (x[i] - mean) / stddev,
/// returned in data scale (raw = z * 1000).
///
/// mean = feature_mean(v). variance = feature_variance(v) (sample variance).
/// sigma_raw = integer_sqrt(variance * 1000) (data scale); the integer
/// square root floors, so sigma_raw is the truncated standard deviation.
/// out[i] = (x[i] - mean) * 1000 / sigma_raw, truncated toward zero. For
/// [1000, 2000, 3000] the result is [-1000, 0, 1000] (z = -1, 0, +1).
/// Params: v - at least two data-scale values.
/// Returns: Ok(z-scores) with v.len() entries in data scale.
/// Error case: Err("feature: ...") when v.len() < 2, or when the truncated
/// variance is 0 (a constant feature; the division is undefined).
/// Complexity: O(n).
pub fn feature_zscore_scale(v: &Vec[Int]) -> Result[Vec[Int], Str] {
  let n = v.len();
  if n < 2 {
    return _err_ints("feature: z-score scaling needs at least 2 samples");
  }
  let va = _variance_raw(v);
  if va == 0 {
    return _err_ints("feature: z-score scaling requires a non-constant feature");
  }
  let sigma = _isqrt(va * _FF_ONE);
  let mu = _mean_raw(v);
  var out = Vec[Int].new();
  var i = 0;
  while i < n {
    let x: Int = v[i];
    out.push((x - mu) * _FF_ONE / sigma);
    i = i + 1;
  }
  return _ok_ints(out);
}

// ---------------------------------------------------------------------------
// Feature matrix
// ---------------------------------------------------------------------------

/// Build a row-major matrix from a flat values vector.
/// Params: rows - number of samples (> 0); cols - number of features (> 0);
///         values - the rows*cols data-scale values, row-major.
/// Returns: Ok(matrix) with a private copy of values.
/// Error case: Err("feature: ...") when rows or cols is not positive, when
/// rows*cols overflows, or when values.len() != rows*cols.
/// Complexity: O(rows*cols).
pub fn feature_matrix_new(rows: Int, cols: Int, values: &Vec[Int]) -> Result[FeatureMatrix, Str] {
  if rows <= 0 {
    return _err_matrix("feature: matrix rows must be positive");
  }
  if cols <= 0 {
    return _err_matrix("feature: matrix cols must be positive");
  }
  if rows > _FF_INT_MAX / cols {
    return _err_matrix("feature: matrix rows*cols overflows");
  }
  let want = rows * cols;
  if values.len() != want {
    return _err_matrix("feature: matrix values length does not match rows*cols");
  }
  var copied = Vec[Int].new();
  var i = 0;
  while i < want {
    let x: Int = values[i];
    copied.push(x);
    i = i + 1;
  }
  return _ok_matrix(FeatureMatrix{ rows: rows; cols: cols; data: copied; });
}

/// Sample count (rows). Complexity: O(1).
pub fn feature_matrix_rows(m: &FeatureMatrix) -> Int {
  return m.rows;
}

/// Feature count (columns). Complexity: O(1).
pub fn feature_matrix_cols(m: &FeatureMatrix) -> Int {
  return m.cols;
}

/// Data-scale value at (row, col), or 0 when the index is out of range.
/// Complexity: O(1).
pub fn feature_matrix_get(m: &FeatureMatrix, row: Int, col: Int) -> Int {
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
pub fn feature_matrix_data(m: &FeatureMatrix) -> Vec[Int] {
  return _copy_ints(&m.data);
}

/// Copy of column `col` (one data-scale value per sample, in row order);
/// empty when `col` is out of range. Complexity: O(rows).
pub fn feature_matrix_column(m: &FeatureMatrix, col: Int) -> Vec[Int] {
  var out = Vec[Int].new();
  if col < 0 {
    return out;
  }
  if col >= m.cols {
    return out;
  }
  var r = 0;
  while r < m.rows {
    let idx = r * m.cols + col;
    if idx >= m.data.len() {
      return out;
    }
    let x: Int = m.data[idx];
    out.push(x);
    r = r + 1;
  }
  return out;
}

// ---------------------------------------------------------------------------
// (e) Variance-threshold selection
// ---------------------------------------------------------------------------

/// Select the feature columns whose sample variance exceeds `threshold`.
///
/// Columns are scanned left to right; a column is selected when
/// feature_variance(column) > threshold (sklearn VarianceThreshold
/// semantics: the threshold is the largest variance that is still
/// discarded). The default threshold 0 keeps exactly the non-constant
/// columns. Every selected column contributes one entry to `indices` and
/// one parallel entry to `variances` (same position), so the two vectors
/// always have equal length and the indices are strictly ascending.
/// Params: m - a matrix with at least 2 rows and at least 1 column;
///         threshold - the variance cutoff in data scale (>= 0).
/// Returns: Ok(FeatureSelection).
/// Error case: Err("feature: ...") when m.rows < 2, when m.cols <= 0, or
/// when threshold < 0.
/// Complexity: O(rows*cols).
pub fn feature_variance_selector(m: &FeatureMatrix, threshold: Int) -> Result[FeatureSelection, Str] {
  if m.rows < 2 {
    return _err_selection("feature: selector needs at least 2 samples");
  }
  if m.cols <= 0 {
    return _err_selection("feature: matrix has no columns");
  }
  if threshold < 0 {
    return _err_selection("feature: variance threshold must not be negative");
  }
  var indices = Vec[Int].new();
  var variances = Vec[Int].new();
  var j = 0;
  while j < m.cols {
    let col = feature_matrix_column(m, j);
    let va = _variance_raw(&col);
    if va > threshold {
      indices.push(j);
      variances.push(va);
    }
    j = j + 1;
  }
  return _ok_selection(FeatureSelection{ indices: indices; variances: variances; });
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

// n*(n+1)/2 without overflowing the intermediate product: the even factor
// is halved first. n in [0, 4294967295] is the caller's contract.
fn _poly2_count_raw(n: Int) -> Int {
  if n % 2 == 0 {
    return (n / 2) * (n + 1);
  }
  return n * ((n + 1) / 2);
}

// FNV-1a 32-bit over the UTF-8 bytes of `token`. Each byte is widened to Int
// and masked with 0xFF before use (the documented pin hazard for byte_at
// values >= 128); the 32-bit multiply cannot overflow Int because both
// factors are below 2^32.
fn _fnv1a32(token: Str) -> Int {
  var h = _FF_FNV_OFFSET;
  let n = token.len();
  var i = 0;
  while i < n {
    let b: Int = (byte_at(token, i) as Int) & 255;
    h = (h ^ b) % _FF_U32_MOD;
    h = (h * _FF_FNV_PRIME) % _FF_U32_MOD;
    i = i + 1;
  }
  return h;
}

// Signed hashing-trick index: magnitude bucket + 1, sign from digit
// ((h / 65536) % 2) -- one extra hash bit extracted arithmetically.
fn _signed_bucket(h: Int, buckets: Int) -> Int {
  let bucket = h % buckets;
  let bit = (h / _FF_SIGN_DIV) % 2;
  if bit == 0 {
    return bucket + 1;
  }
  return 0 - (bucket + 1);
}

// Arithmetic mean with round-half-away-from-zero. v.len() >= 1 assumed.
fn _mean_raw(v: &Vec[Int]) -> Int {
  let n = v.len();
  var sum: Int = 0;
  var i = 0;
  while i < n {
    let x: Int = v[i];
    sum = sum + x;
    i = i + 1;
  }
  return _div_round(sum, n);
}

// Sample variance in data scale. v.len() >= 2 assumed. Each squared
// deviation is truncated to data scale before accumulation, then the sum is
// divided by n - 1 with round-half-away-from-zero.
fn _variance_raw(v: &Vec[Int]) -> Int {
  let n = v.len();
  let mu = _mean_raw(v);
  var s: Int = 0;
  var i = 0;
  while i < n {
    let x: Int = v[i];
    let d = x - mu;
    s = s + d * d / _FF_ONE;
    i = i + 1;
  }
  return _div_round(s, n - 1);
}

// Integer square root (floor) of n >= 0 by Newton iteration. The initial
// guess x = n keeps every intermediate within Int for the documented
// envelope (variance_raw * 1000 <= Int::MAX - 1).
fn _isqrt(n: Int) -> Int {
  if n <= 0 {
    return 0;
  }
  var x = n;
  var y = (x + 1) / 2;
  while y < x {
    x = y;
    y = (x + n / x) / 2;
  }
  return x;
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

fn _ok_matrix(m: FeatureMatrix) -> Result[FeatureMatrix, Str] {
  return Ok(m);
}

fn _err_matrix(msg: Str) -> Result[FeatureMatrix, Str] {
  return Err(msg);
}

fn _ok_stats(s: FeatureStats) -> Result[FeatureStats, Str] {
  return Ok(s);
}

fn _err_stats(msg: Str) -> Result[FeatureStats, Str] {
  return Err(msg);
}

fn _ok_selection(s: FeatureSelection) -> Result[FeatureSelection, Str] {
  return Ok(s);
}

fn _err_selection(msg: Str) -> Result[FeatureSelection, Str] {
  return Err(msg);
}
