// XIOM -- xiom.data: dataset container and iterators (core module)
// Port task: promote the xiom.data placeholder to a real, tested, pure-XIOM
// package. This core module owns the Dataset record, its iterators, the
// documented limits and the dataset_* API. Companion modules:
//   xiom.data.batch (src/batch.xi) -- Batch collation and the batched Loader
//   xiom.data.order (src/order.xi) -- samplers, deterministic LCG shuffle,
//                                     train/validation/test splitting
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model (pinned in SPEC.md, exercised by tests/test_conformance.xi):
//
//   - A Dataset is `{ n, width, xs, ys }`: `n` samples of `width` integer
//     features each, `xs` the flat row-major feature buffer of exactly
//     `n * width` values, `ys` the parallel label vector of exactly `n`
//     labels. `width` may be 0 (label-only dataset).
//   - Parallel Vecs never drift: lengths are validated at construction,
//     guarded at every access, and no Vec[StructType] is used (trap 10/16).
//   - All values are Int; there is no Float64 path and no file I/O.
//
// Compiler-v0.62.2 notes shaping this module: every Vec[Int] element read
// binds a typed local; no `&struct.field` is passed to a reference parameter;
// Ok/Err construction lives only in the leaf helpers; every loop is bounded
// by a validated length; every function is free (no methods, no lambdas).

module xiom.data

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

// Documented capacity guard (well under the runtime Vec cap).
const _DATA_MAX_SAMPLES: Int = 1000000;
// Documented flat-value capacity guard.
const _DATA_MAX_VALUES: Int = 1000000;
// Symmetric integer envelope for overflow guards.
const _DATA_INT_MAX: Int = 9223372036854775807;

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

/// A dataset of `n` samples with `width` integer features each: `xs` is the
/// flat row-major buffer of `n * width` values, `ys` the parallel label
/// vector of `n` labels. Fields are implementation detail; use the
/// dataset_* accessors.
pub type Dataset = {
  n: Int;
  width: Int;
  xs: Vec[Int];
  ys: Vec[Int];
}

/// Forward iterator over sample indices 0 .. n-1 (see dataset_iter_next).
pub type DatasetIter = {
  pos: Int;
  n: Int;
}

// ---------------------------------------------------------------------------
// Limits
// ---------------------------------------------------------------------------

/// Largest supported sample count per dataset (1000000).
pub fn data_max_samples() -> Int {
  return _DATA_MAX_SAMPLES;
}

/// Largest supported flat value count per dataset (1000000).
pub fn data_max_values() -> Int {
  return _DATA_MAX_VALUES;
}

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

/// Build a dataset from a flat row-major feature buffer and labels.
///
/// Params: width - features per sample (>= 0; 0 means label-only);
///         xs - exactly `ys.len() * width` row-major values, read only;
///         ys - the label vector, read only.
/// Returns: Ok(Dataset) holding copies of both vectors; later mutation of the
/// caller's vectors is not visible through the dataset.
/// Error case: width < 0, sample count > data_max_samples(), a flat length
/// that does not equal `ys.len() * width` (including multiplication
/// overflow), or a flat length > data_max_values().
/// Complexity: O(n * width).
pub fn dataset_from_flat(width: Int, xs: &Vec[Int], ys: &Vec[Int]) -> Result[Dataset, Str] {
  if width < 0 {
    return _err_dataset("data: width must be non-negative");
  }
  if ys.len() > _DATA_MAX_SAMPLES {
    return _err_dataset("data: sample count exceeds the limit");
  }
  var expected: Int = 0;
  if width > 0 {
    if ys.len() > _DATA_INT_MAX / width {
      return _err_dataset("data: flat length overflows");
    }
    expected = ys.len() * width;
  }
  if xs.len() != expected {
    return _err_dataset("data: flat length does not match sample count");
  }
  if xs.len() > _DATA_MAX_VALUES {
    return _err_dataset("data: value count exceeds the limit");
  }
  var xcopy = Vec[Int].new();
  var i = 0;
  while i < xs.len() {
    let v: Int = xs[i];
    xcopy.push(v);
    i = i + 1;
  }
  var ycopy = Vec[Int].new();
  var k = 0;
  while k < ys.len() {
    let y: Int = ys[k];
    ycopy.push(y);
    k = k + 1;
  }
  return _ok_dataset(Dataset{ n: ys.len(); width: width; xs: xcopy; ys: ycopy; });
}

/// Build a label-only dataset (width 0) from a label vector (copied).
/// Error case: the dataset_from_flat errors.
/// Complexity: O(n).
pub fn dataset_from_labels(ys: &Vec[Int]) -> Result[Dataset, Str] {
  var empty = Vec[Int].new();
  return dataset_from_flat(0, &empty, ys);
}

// ---------------------------------------------------------------------------
// Accessors
// ---------------------------------------------------------------------------

/// Number of samples. Complexity: O(1).
pub fn dataset_num_samples(d: &Dataset) -> Int {
  return d.n;
}

/// Features per sample (0 for a label-only dataset). Complexity: O(1).
pub fn dataset_width(d: &Dataset) -> Int {
  return d.width;
}

/// Total flat feature value count, `n * width`. Complexity: O(1).
pub fn dataset_num_values(d: &Dataset) -> Int {
  return d.xs.len();
}

/// Value of feature `j` of sample `i`.
/// Error case: Err("data: sample index out of bounds") when i is outside
/// 0 .. n-1; Err("data: feature index out of bounds") when j is outside
/// 0 .. width-1. Complexity: O(1).
pub fn dataset_get(d: &Dataset, i: Int, j: Int) -> Result[Int, Str] {
  if i < 0 || i >= d.n {
    return _err_int("data: sample index out of bounds");
  }
  if j < 0 || j >= d.width {
    return _err_int("data: feature index out of bounds");
  }
  let v: Int = d.xs[i * d.width + j];
  return _ok_int(v);
}

/// Label of sample `i`; same errors as dataset_get (only the sample check).
/// Complexity: O(1).
pub fn dataset_label(d: &Dataset, i: Int) -> Result[Int, Str] {
  if i < 0 || i >= d.n {
    return _err_int("data: sample index out of bounds");
  }
  let v: Int = d.ys[i];
  return _ok_int(v);
}

/// Copy of the row of sample `i` (length `width`).
/// Error case: Err("data: sample index out of bounds").
/// Complexity: O(width).
pub fn dataset_row(d: &Dataset, i: Int) -> Result[Vec[Int], Str] {
  if i < 0 || i >= d.n {
    return _err_ints("data: sample index out of bounds");
  }
  var row = Vec[Int].new();
  let base = i * d.width;
  var j = 0;
  while j < d.width {
    let v: Int = d.xs[base + j];
    row.push(v);
    j = j + 1;
  }
  return _ok_ints(row);
}

/// Copy of the label vector (length n); independent of the dataset's buffer.
/// Complexity: O(n).
pub fn dataset_labels(d: &Dataset) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 0;
  while i < d.ys.len() {
    let v: Int = d.ys[i];
    out.push(v);
    i = i + 1;
  }
  return out;
}

/// Copy of the flat feature buffer (length n * width).
/// Complexity: O(n * width).
pub fn dataset_values(d: &Dataset) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 0;
  while i < d.xs.len() {
    let v: Int = d.xs[i];
    out.push(v);
    i = i + 1;
  }
  return out;
}

// ---------------------------------------------------------------------------
// Iterators
// ---------------------------------------------------------------------------

/// Fresh iterator over sample indices 0 .. n-1. Complexity: O(1).
pub fn dataset_iter(d: &Dataset) -> DatasetIter {
  return DatasetIter{ pos: 0; n: d.n; };
}

/// Next sample index from the iterator, or -1 when exhausted. Mutates the
/// iterator in place (pass `&mut it`). Complexity: O(1).
pub fn dataset_iter_next(it: &mut DatasetIter) -> Int {
  if it.pos >= it.n {
    return -1;
  }
  let k = it.pos;
  it.pos = it.pos + 1;
  return k;
}

/// Rewind an iterator to the first sample. Complexity: O(1).
pub fn dataset_iter_reset(it: &mut DatasetIter) {
  it.pos = 0;
}

/// Number of samples not yet returned by the iterator. Complexity: O(1).
pub fn dataset_iter_remaining(it: &DatasetIter) -> Int {
  return it.n - it.pos;
}

// ---------------------------------------------------------------------------
// Leaf Result constructors (Ok/Err never appear in a struct-returning body)
// ---------------------------------------------------------------------------

fn _ok_dataset(d: Dataset) -> Result[Dataset, Str] {
  return Ok(d);
}

fn _err_dataset(msg: Str) -> Result[Dataset, Str] {
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
