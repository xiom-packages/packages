// XIOM -- xiom.data.order: samplers, deterministic LCG shuffle and splitting
// Port task: promote the xiom.data placeholder to a real, tested, pure-XIOM
// package. This module owns the Sampler record (sample ordering/weighting),
// the deterministic MINSTD LCG Fisher-Yates shuffle and the
// train/validation/test Split. The Dataset lives in `xiom.data`
// (src/data.xi); Batch and Loader live in `xiom.data.batch` (src/batch.xi).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Shuffle algorithm (pinned in SPEC.md section 5):
//   normalize(seed) = `s = seed % 2147483646; if s <= 0 { s = s + 2147483646 }`
//   next(s)         = `(48271 * s) mod 2147483647`   (Park-Miller MINSTD)
//   order(n, seed): order = [0 .. n-1]; state = normalize(seed);
//                   for i = n-1 down to 1:
//                     state = next(state); j = state % (i + 1);
//                     swap order[i], order[j]
//   The default seed is 12345 (shuffle_seed_default()); the same (n, seed)
//   always yields the same order. Pinned vectors are in SPEC.md / the tests.
//   Scalar RNG state is threaded through returns (no `&mut Int` parameters).
//
// Compiler-v0.62.2 notes: typed locals on every Vec[Int] read, no
// `&struct.field` argument to a reference parameter, Ok/Err only in leaf
// helpers, no generics/callbacks, bounded loops, non-negative division only.

module xiom.data.order

use xiom.convert;

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

// Documented capacity guard (mirrors xiom.data's limit).
const _ORD_MAX_SAMPLES: Int = 1000000;
// Basis-point scale for split ratios (10000 = 1.0).
const _ORD_BPS: Int = 10000;
// MINSTD LCG constants (Lehmer/Park-Miller).
const _ORD_LCG_MOD: Int = 2147483647;
const _ORD_LCG_MUL: Int = 48271;
const _ORD_LCG_NORM: Int = 2147483646;
const _ORD_LCG_SEED: Int = 12345;

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

/// A sample order: `order` is a permutation of 0 .. n-1.
pub type Sampler = {
  n: Int;
  order: Vec[Int];
}

/// A train/validation/test split of sample indices; the three vectors
/// partition some order (each index appears at most once).
pub type Split = {
  train: Vec[Int];
  val: Vec[Int];
  test: Vec[Int];
}

// ---------------------------------------------------------------------------
// Sampler: ordering and weighting
// ---------------------------------------------------------------------------

/// Sequential sampler: order 0, 1, .. n-1.
/// Error case: n < 0 or n > data_max_samples().
/// Complexity: O(n).
pub fn sampler_sequential(n: Int) -> Result[Sampler, Str] {
  if n < 0 {
    return _err_sampler("data: sample count must be non-negative");
  }
  if n > _ORD_MAX_SAMPLES {
    return _err_sampler("data: sample count exceeds the limit");
  }
  var order = Vec[Int].new();
  var i = 0;
  while i < n {
    order.push(i);
    i = i + 1;
  }
  return _ok_sampler(Sampler{ n: n; order: order; });
}

/// Sampler over an explicit permutation of 0 .. n-1 (copied).
/// Error case: n out of 0 .. data_max_samples(), a length mismatch, or a
/// vector that is not a permutation.
/// Complexity: O(n).
pub fn sampler_from_order(n: Int, order: &Vec[Int]) -> Result[Sampler, Str] {
  if n < 0 {
    return _err_sampler("data: sample count must be non-negative");
  }
  if n > _ORD_MAX_SAMPLES {
    return _err_sampler("data: sample count exceeds the limit");
  }
  if order.len() != n {
    return _err_sampler("data: order length must equal sample count");
  }
  if !_ord_is_permutation(order, n) {
    return _err_sampler("data: order must be a permutation of 0..n-1");
  }
  var copy = Vec[Int].new();
  var i = 0;
  while i < order.len() {
    let v: Int = order[i];
    copy.push(v);
    i = i + 1;
  }
  return _ok_sampler(Sampler{ n: n; order: copy; });
}

/// Shuffled sampler: the Fisher-Yates order of shuffle_order(n, seed).
/// Error case: the shuffle_order errors.
/// Complexity: O(n).
pub fn sampler_shuffled(n: Int, seed: Int) -> Result[Sampler, Str] {
  let r = shuffle_order(n, seed);
  var order = Vec[Int].new();
  match r {
    Ok(v) => { order = v; },
    Err(e) => { return _err_sampler(e); },
  }
  return _ok_sampler(Sampler{ n: n; order: order; });
}

/// Weighted sampler: sample indices ordered by descending non-negative
/// weight, ties in ascending index order (stable). Intended for weighted
/// epoch composition; `n` is capped at 10000 because the stable selection is
/// O(n^2). A zero weight is legal (the sample sorts last).
/// Error case: n out of 0 .. 10000, weights length != n, or a negative
/// weight.
/// Complexity: O(n^2).
pub fn sampler_weighted(n: Int, weights: &Vec[Int]) -> Result[Sampler, Str] {
  if n < 0 {
    return _err_sampler("data: sample count must be non-negative");
  }
  if n > 10000 {
    return _err_sampler("data: weighted sampler sample count exceeds the limit");
  }
  if weights.len() != n {
    return _err_sampler("data: weight count must equal sample count");
  }
  var i = 0;
  while i < n {
    let w: Int = weights[i];
    if w < 0 {
      return _err_sampler("data: weight must be non-negative");
    }
    i = i + 1;
  }
  var order = Vec[Int].new();
  var k = 0;
  while k < n {
    order.push(k);
    k = k + 1;
  }
  var a = 0;
  while a < n {
    var best = a;
    var b = a + 1;
    while b < n {
      let ib: Int = order[b];
      let ibest: Int = order[best];
      let wb: Int = weights[ib];
      let wbest: Int = weights[ibest];
      if wb > wbest {
        best = b;
      }
      b = b + 1;
    }
    let tmp: Int = order[a];
    let other: Int = order[best];
    order[a] = other;
    order[best] = tmp;
    a = a + 1;
  }
  return _ok_sampler(Sampler{ n: n; order: order; });
}

/// Order entries in the sampler (equals n for well-formed samplers).
pub fn sampler_len(s: &Sampler) -> Int {
  return s.order.len();
}

/// Sample index at position `k`, or -1 when k is out of range.
/// Complexity: O(1).
pub fn sampler_get(s: &Sampler, k: Int) -> Int {
  if k < 0 || k >= s.order.len() {
    return -1;
  }
  let v: Int = s.order[k];
  return v;
}

/// Copy of the sampler's order vector. Complexity: O(n).
pub fn sampler_order(s: &Sampler) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 0;
  while i < s.order.len() {
    let v: Int = s.order[i];
    out.push(v);
    i = i + 1;
  }
  return out;
}

/// True when the order is a permutation of 0 .. n-1. Complexity: O(n).
pub fn sampler_is_permutation(s: &Sampler) -> Bool {
  if s.order.len() != s.n {
    return false;
  }
  var order = Vec[Int].new();
  var i = 0;
  while i < s.order.len() {
    let v: Int = s.order[i];
    order.push(v);
    i = i + 1;
  }
  return _ord_is_permutation(&order, s.n);
}

// ---------------------------------------------------------------------------
// Shuffle: deterministic MINSTD LCG + Fisher-Yates
// ---------------------------------------------------------------------------

/// Default shuffle seed (12345). Complexity: O(1).
pub fn shuffle_seed_default() -> Int {
  return _ORD_LCG_SEED;
}

/// LCG modulus M = 2147483647 (2^31 - 1). Complexity: O(1).
pub fn shuffle_lcg_modulus() -> Int {
  return _ORD_LCG_MOD;
}

/// LCG multiplier A = 48271. Complexity: O(1).
pub fn shuffle_lcg_multiplier() -> Int {
  return _ORD_LCG_MUL;
}

/// Normalize any Int seed into the valid LCG state range [1, 2147483646]:
/// `s = seed % 2147483646; if s <= 0 { s = s + 2147483646 }`.
/// Complexity: O(1).
pub fn shuffle_seed_normalize(seed: Int) -> Int {
  var s = seed % _ORD_LCG_NORM;
  if s <= 0 {
    s = s + _ORD_LCG_NORM;
  }
  return s;
}

/// One LCG step `s = (48271 * s) mod 2147483647`, normalizing the input
/// first so any Int state is accepted (state is threaded by return value:
/// no `&mut Int` parameter exists). Complexity: O(1).
pub fn shuffle_next(state: Int) -> Int {
  let s = shuffle_seed_normalize(state);
  return (s * _ORD_LCG_MUL) % _ORD_LCG_MOD;
}

/// LCG value in [0, bound) derived from `state` by modulo (`bound <= 0`
/// yields 0). The modulo bias is negligible for the bounds used by
/// Fisher-Yates and is documented in SPEC.md. Complexity: O(1).
pub fn shuffle_below(state: Int, bound: Int) -> Int {
  if bound <= 0 {
    return 0;
  }
  let s = shuffle_seed_normalize(state);
  return s % bound;
}

/// Deterministic Fisher-Yates order of 0 .. n-1 from an integer seed.
///
/// Algorithm (pinned in SPEC.md section 5): `order = [0, .., n-1]`,
/// `state = shuffle_seed_normalize(seed)`, then for `i = n-1` down to 1:
/// `state = shuffle_next(state)`, `j = state % (i+1)`, swap `order[i]` and
/// `order[j]`. The same (n, seed) always yields the same order; seed 0 is
/// accepted and normalized (the default seed is shuffle_seed_default()).
/// Error case: Err("data: sample count must be non-negative") for n < 0;
/// Err("data: sample count exceeds the limit") for n > data_max_samples().
/// Complexity: O(n).
pub fn shuffle_order(n: Int, seed: Int) -> Result[Vec[Int], Str] {
  if n < 0 {
    return _err_ints("data: sample count must be non-negative");
  }
  if n > _ORD_MAX_SAMPLES {
    return _err_ints("data: sample count exceeds the limit");
  }
  var order = Vec[Int].new();
  var k = 0;
  while k < n {
    order.push(k);
    k = k + 1;
  }
  var state = shuffle_seed_normalize(seed);
  var i = n - 1;
  while i >= 1 {
    state = shuffle_next(state);
    let j: Int = state % (i + 1);
    let tmp: Int = order[i];
    let other: Int = order[j];
    order[i] = other;
    order[j] = tmp;
    i = i - 1;
  }
  return _ok_ints(order);
}

// ---------------------------------------------------------------------------
// Split: train / validation / test
// ---------------------------------------------------------------------------

/// Split-ratio scale: 10000 basis points = 1.0. Complexity: O(1).
pub fn split_bps() -> Int {
  return _ORD_BPS;
}

/// Contiguous split of 0 .. n-1 into train, validation and test index
/// vectors. Sizes are `n * train_bps / 10000` and `n * val_bps / 10000`
/// (truncated toward zero; non-negative operands), and the test vector takes
/// every remaining index. The three vectors are ascending and disjoint and
/// their union is exactly 0 .. n-1.
/// Error case: n outside 0 .. data_max_samples(); a negative ratio; or
/// train_bps + val_bps > split_bps() (10000).
/// Complexity: O(n).
pub fn split_indices(n: Int, train_bps: Int, val_bps: Int) -> Result[Split, Str] {
  let c = _ord_split_counts(n, train_bps, val_bps);
  var tn: Int = 0;
  var vn: Int = 0;
  match c {
    Ok(v) => { tn = v[0]; vn = v[1]; },
    Err(e) => { return _err_split(e); },
  }
  var train = Vec[Int].new();
  var val = Vec[Int].new();
  var test = Vec[Int].new();
  var i = 0;
  while i < n {
    if i < tn {
      train.push(i);
    } else {
      if i < tn + vn {
        val.push(i);
      } else {
        test.push(i);
      }
    }
    i = i + 1;
  }
  return _ok_split(Split{ train: train; val: val; test: test; });
}

/// Deterministic randomized split: `shuffle_order(n, seed)` is partitioned
/// by the same basis-point rule as split_indices (first `train_n` entries to
/// train, the next `val_n` to validation, the rest to test). The three
/// vectors partition the shuffled order.
/// Error case: the split_indices ratio/n errors, plus the shuffle_order
/// size errors.
/// Complexity: O(n).
pub fn split_shuffled(n: Int, train_bps: Int, val_bps: Int, seed: Int) -> Result[Split, Str] {
  let c = _ord_split_counts(n, train_bps, val_bps);
  var tn: Int = 0;
  var vn: Int = 0;
  match c {
    Ok(v) => { tn = v[0]; vn = v[1]; },
    Err(e) => { return _err_split(e); },
  }
  let r = shuffle_order(n, seed);
  var order = Vec[Int].new();
  match r {
    Ok(v) => { order = v; },
    Err(e) => { return _err_split(e); },
  }
  var train = Vec[Int].new();
  var val = Vec[Int].new();
  var test = Vec[Int].new();
  var i = 0;
  while i < n {
    let src: Int = order[i];
    if i < tn {
      train.push(src);
    } else {
      if i < tn + vn {
        val.push(src);
      } else {
        test.push(src);
      }
    }
    i = i + 1;
  }
  return _ok_split(Split{ train: train; val: val; test: test; });
}

/// Train index count. Complexity: O(1).
pub fn split_train_len(s: &Split) -> Int {
  return s.train.len();
}

/// Validation index count. Complexity: O(1).
pub fn split_val_len(s: &Split) -> Int {
  return s.val.len();
}

/// Test index count. Complexity: O(1).
pub fn split_test_len(s: &Split) -> Int {
  return s.test.len();
}

/// Train index at position `k`, or -1 out of range. Complexity: O(1).
pub fn split_train_at(s: &Split, k: Int) -> Int {
  if k < 0 || k >= s.train.len() {
    return -1;
  }
  let v: Int = s.train[k];
  return v;
}

/// Validation index at position `k`, or -1 out of range. Complexity: O(1).
pub fn split_val_at(s: &Split, k: Int) -> Int {
  if k < 0 || k >= s.val.len() {
    return -1;
  }
  let v: Int = s.val[k];
  return v;
}

/// Test index at position `k`, or -1 out of range. Complexity: O(1).
pub fn split_test_at(s: &Split, k: Int) -> Int {
  if k < 0 || k >= s.test.len() {
    return -1;
  }
  let v: Int = s.test[k];
  return v;
}

/// Copy of the train index vector. Complexity: O(n_train).
pub fn split_train_indices(s: &Split) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 0;
  while i < s.train.len() {
    let v: Int = s.train[i];
    out.push(v);
    i = i + 1;
  }
  return out;
}

/// Copy of the validation index vector. Complexity: O(n_val).
pub fn split_val_indices(s: &Split) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 0;
  while i < s.val.len() {
    let v: Int = s.val[i];
    out.push(v);
    i = i + 1;
  }
  return out;
}

/// Copy of the test index vector. Complexity: O(n_test).
pub fn split_test_indices(s: &Split) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 0;
  while i < s.test.len() {
    let v: Int = s.test[i];
    out.push(v);
    i = i + 1;
  }
  return out;
}

/// Canonical single-line rendering:
/// `split train=[...] val=[...] test=[...]`, no trailing newline.
/// Complexity: O(n_train + n_val + n_test) plus string assembly.
pub fn split_dump(s: &Split) -> Str {
  var out = "split train=[";
  var k = 0;
  while k < s.train.len() {
    if k > 0 {
      out = out + ",";
    }
    let v: Int = s.train[k];
    out = out + convert.int_to_string(v);
    k = k + 1;
  }
  out = out + "] val=[";
  var i = 0;
  while i < s.val.len() {
    if i > 0 {
      out = out + ",";
    }
    let v: Int = s.val[i];
    out = out + convert.int_to_string(v);
    i = i + 1;
  }
  out = out + "] test=[";
  var j = 0;
  while j < s.test.len() {
    if j > 0 {
      out = out + ",";
    }
    let v: Int = s.test[j];
    out = out + convert.int_to_string(v);
    j = j + 1;
  }
  out = out + "]";
  return out;
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

// Shared split validation: Ok([train_n, val_n]) after checking n, capacity
// and the basis-point ratios.
fn _ord_split_counts(n: Int, train_bps: Int, val_bps: Int) -> Result[Vec[Int], Str] {
  if n < 0 {
    return _err_ints("data: split sample count must be non-negative");
  }
  if n > _ORD_MAX_SAMPLES {
    return _err_ints("data: split sample count exceeds the limit");
  }
  if train_bps < 0 || val_bps < 0 {
    return _err_ints("data: split ratios must be non-negative");
  }
  if train_bps + val_bps > _ORD_BPS {
    return _err_ints("data: split ratios must sum to at most 10000");
  }
  var out = Vec[Int].new();
  out.push(n * train_bps / _ORD_BPS);
  out.push(n * val_bps / _ORD_BPS);
  return _ok_ints(out);
}

// Exact permutation test for a vector of length n: every value in 0 .. n-1
// appears exactly once. O(n) time and marking space.
fn _ord_is_permutation(order: &Vec[Int], n: Int) -> Bool {
  if order.len() != n {
    return false;
  }
  if n == 0 {
    return true;
  }
  var seen = Vec[Int].new();
  var i = 0;
  while i < n {
    seen.push(0);
    i = i + 1;
  }
  var k = 0;
  while k < n {
    let v: Int = order[k];
    if v < 0 || v >= n {
      return false;
    }
    let s: Int = seen[v];
    if s != 0 {
      return false;
    }
    seen[v] = 1;
    k = k + 1;
  }
  return true;
}

// ---------------------------------------------------------------------------
// Leaf Result constructors
// ---------------------------------------------------------------------------

fn _ok_sampler(s: Sampler) -> Result[Sampler, Str] {
  return Ok(s);
}

fn _err_sampler(msg: Str) -> Result[Sampler, Str] {
  return Err(msg);
}

fn _ok_split(s: Split) -> Result[Split, Str] {
  return Ok(s);
}

fn _err_split(msg: Str) -> Result[Split, Str] {
  return Err(msg);
}

fn _ok_ints(v: Vec[Int]) -> Result[Vec[Int], Str] {
  return Ok(v);
}

fn _err_ints(msg: Str) -> Result[Vec[Int], Str] {
  return Err(msg);
}
