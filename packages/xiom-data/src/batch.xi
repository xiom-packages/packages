// XIOM -- xiom.data.batch: batch collation and the batched loader
// Port task: promote the xiom.data placeholder to a real, tested, pure-XIOM
// package. This module owns the Batch record (rows assembled from a Dataset)
// and the Loader (fixed-size batches over an explicit sample order). The
// Dataset record and its accessors live in `xiom.data` (src/data.xi); the
// samplers, LCG shuffle and split live in `xiom.data.order` (src/order.xi).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Invariants (pinned in SPEC.md):
//   - A Batch is `{ n, width, xs, ys, indices }`, every parallel vector of
//     length `n`; `xs` is flat row-major (`n * width` values), `ys` the
//     labels and `indices` the source sample index of each row. Duplicate
//     indices are allowed and preserved.
//   - A Loader walks `order` (a permutation of 0 .. n-1) in `batch_size`
//     chunks; `drop_last` is 0 or 1 and `cursor` is the next order position.
//     loader_num_batches uses floor/remainder (no negative-operand ceiling).
//   - loader_next refuses a dataset whose (n, width) does not match the one
//     the loader was built for, so parallel vectors can never drift.
//
// Compiler-v0.62.2 notes: typed locals on every Vec[Int] read, no
// `&struct.field` argument to a reference parameter, Ok/Err only in leaf
// helpers, `&mut Loader` at explicit `&mut` call sites, bounded loops.

module xiom.data.batch

use xiom.convert;
use xiom.data;

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

/// An assembled batch: `n` rows copied from a dataset in `indices` order,
/// with `xs` flat row-major (`n * width` values), `ys` labels and `indices`
/// the source sample index of each row. All parallel vectors have length `n`.
pub type Batch = {
  n: Int;
  width: Int;
  xs: Vec[Int];
  ys: Vec[Int];
  indices: Vec[Int];
}

/// A batched loader walking `order` (a permutation of 0..n-1) in
/// `batch_size` chunks. `drop_last` is 0 or 1; `cursor` is the next order
/// position to consume.
pub type Loader = {
  n: Int;
  width: Int;
  order: Vec[Int];
  batch_size: Int;
  drop_last: Int;
  cursor: Int;
}

// ---------------------------------------------------------------------------
// Batch assembly and collation
// ---------------------------------------------------------------------------

/// Assemble a batch by copying the dataset rows named by `indices`, in order.
/// Duplicate indices are allowed and preserved (a sampler may intentionally
/// repeat samples). All parallel vectors of the result have length
/// `indices.len()`.
/// Error case: Err("data: batch index out of bounds") for any index outside
/// 0 .. n-1 (checked left to right; nothing partial is returned).
/// Complexity: O(indices.len() * width).
pub fn batch_assemble(d: &Dataset, indices: &Vec[Int]) -> Result[Batch, Str] {
  var xs = Vec[Int].new();
  var ys = Vec[Int].new();
  var idx = Vec[Int].new();
  var k = 0;
  while k < indices.len() {
    let i: Int = indices[k];
    if i < 0 || i >= d.n {
      return _err_batch("data: batch index out of bounds");
    }
    let base = i * d.width;
    var j = 0;
    while j < d.width {
      let v: Int = d.xs[base + j];
      xs.push(v);
      j = j + 1;
    }
    let y: Int = d.ys[i];
    ys.push(y);
    idx.push(i);
    k = k + 1;
  }
  return _ok_batch(Batch{ n: indices.len(); width: d.width; xs: xs; ys: ys; indices: idx; });
}

/// Assemble a contiguous window of `count` samples starting at `start`.
/// Error case: Err("data: batch slice out of bounds") when start < 0,
/// count < 0 or start + count > dataset_num_samples(d).
/// Complexity: O(count * width).
pub fn batch_slice(d: &Dataset, start: Int, count: Int) -> Result[Batch, Str] {
  if start < 0 || count < 0 {
    return _err_batch("data: batch slice out of bounds");
  }
  if start > d.n || count > d.n - start {
    return _err_batch("data: batch slice out of bounds");
  }
  var idx = Vec[Int].new();
  var k = 0;
  while k < count {
    idx.push(start + k);
    k = k + 1;
  }
  return batch_assemble(d, &idx);
}

/// Number of rows in the batch. Complexity: O(1).
pub fn batch_size(b: &Batch) -> Int {
  return b.n;
}

/// Features per row in the batch. Complexity: O(1).
pub fn batch_width(b: &Batch) -> Int {
  return b.width;
}

/// Feature `j` of row `i`; errors as dataset_get. Complexity: O(1).
pub fn batch_get(b: &Batch, i: Int, j: Int) -> Result[Int, Str] {
  if i < 0 || i >= b.n {
    return _err_int("data: sample index out of bounds");
  }
  if j < 0 || j >= b.width {
    return _err_int("data: feature index out of bounds");
  }
  let v: Int = b.xs[i * b.width + j];
  return _ok_int(v);
}

/// Label of row `i`; Err("data: sample index out of bounds") out of range.
/// Complexity: O(1).
pub fn batch_label(b: &Batch, i: Int) -> Result[Int, Str] {
  if i < 0 || i >= b.n {
    return _err_int("data: sample index out of bounds");
  }
  let v: Int = b.ys[i];
  return _ok_int(v);
}

/// Source sample index of row `i`; same range error as batch_label.
/// Complexity: O(1).
pub fn batch_index(b: &Batch, i: Int) -> Result[Int, Str] {
  if i < 0 || i >= b.n {
    return _err_int("data: sample index out of bounds");
  }
  let v: Int = b.indices[i];
  return _ok_int(v);
}

/// Copy of row `i` (length `width`); same range error as batch_label.
/// Complexity: O(width).
pub fn batch_row(b: &Batch, i: Int) -> Result[Vec[Int], Str] {
  if i < 0 || i >= b.n {
    return _err_ints("data: sample index out of bounds");
  }
  var row = Vec[Int].new();
  let base = i * b.width;
  var j = 0;
  while j < b.width {
    let v: Int = b.xs[base + j];
    row.push(v);
    j = j + 1;
  }
  return _ok_ints(row);
}

/// Copy of the batch's label vector (length n). Complexity: O(n).
pub fn batch_labels(b: &Batch) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 0;
  while i < b.ys.len() {
    let v: Int = b.ys[i];
    out.push(v);
    i = i + 1;
  }
  return out;
}

/// Copy of the batch's source index vector (length n). Complexity: O(n).
pub fn batch_indices(b: &Batch) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 0;
  while i < b.indices.len() {
    let v: Int = b.indices[i];
    out.push(v);
    i = i + 1;
  }
  return out;
}

/// Canonical single-line rendering:
/// `batch n=N width=W indices=[...] labels=[...] data=[...]`, no trailing
/// newline. Complexity: O(n * width) plus string assembly.
pub fn batch_dump(b: &Batch) -> Str {
  var out = "batch n=" + convert.int_to_string(b.n) + " width=" + convert.int_to_string(b.width);
  out = out + " indices=[";
  var k = 0;
  while k < b.indices.len() {
    if k > 0 {
      out = out + ",";
    }
    let v: Int = b.indices[k];
    out = out + convert.int_to_string(v);
    k = k + 1;
  }
  out = out + "] labels=[";
  var i = 0;
  while i < b.ys.len() {
    if i > 0 {
      out = out + ",";
    }
    let y: Int = b.ys[i];
    out = out + convert.int_to_string(y);
    i = i + 1;
  }
  out = out + "] data=[";
  var j = 0;
  while j < b.xs.len() {
    if j > 0 {
      out = out + ",";
    }
    let x: Int = b.xs[j];
    out = out + convert.int_to_string(x);
    j = j + 1;
  }
  out = out + "]";
  return out;
}

// ---------------------------------------------------------------------------
// Loader
// ---------------------------------------------------------------------------

/// Loader over the identity order 0 .. n-1 (see loader_from_order).
/// Error case: the loader_from_order errors.
/// Complexity: O(n).
pub fn loader_new(d: &Dataset, batch_size: Int, drop_last: Int) -> Result[Loader, Str] {
  var order = Vec[Int].new();
  var i = 0;
  while i < d.n {
    order.push(i);
    i = i + 1;
  }
  return loader_from_order(d, &order, batch_size, drop_last);
}

/// Loader over an explicit order (a permutation of 0 .. n-1), copied.
///
/// Params: d - the dataset the batches will be assembled from;
///         order - the permutation, read only;
///         batch_size - rows per batch (> 0);
///         drop_last - 1 to drop the final partial batch, 0 to keep it.
/// Returns: Ok(Loader) positioned at the first order entry.
/// Error case: Err("data: batch size must be positive");
/// Err("data: drop_last must be 0 or 1");
/// Err("data: order length must equal sample count");
/// Err("data: order must be a permutation of 0..n-1").
/// Complexity: O(n).
pub fn loader_from_order(d: &Dataset, order: &Vec[Int], batch_size: Int, drop_last: Int) -> Result[Loader, Str] {
  if batch_size <= 0 {
    return _err_loader("data: batch size must be positive");
  }
  if drop_last != 0 && drop_last != 1 {
    return _err_loader("data: drop_last must be 0 or 1");
  }
  if order.len() != d.n {
    return _err_loader("data: order length must equal sample count");
  }
  if !_bat_is_permutation(order, d.n) {
    return _err_loader("data: order must be a permutation of 0..n-1");
  }
  var copy = Vec[Int].new();
  var i = 0;
  while i < order.len() {
    let v: Int = order[i];
    copy.push(v);
    i = i + 1;
  }
  return _ok_loader(Loader{ n: d.n; width: d.width; order: copy; batch_size: batch_size; drop_last: drop_last; cursor: 0; });
}

/// Samples per batch. Complexity: O(1).
pub fn loader_batch_size(l: &Loader) -> Int {
  return l.batch_size;
}

/// Number of batches in one full pass: floor(n / batch_size), plus one when
/// the remainder is non-zero and drop_last is 0. Complexity: O(1).
pub fn loader_num_batches(l: &Loader) -> Int {
  let q = l.n / l.batch_size;
  let r = l.n % l.batch_size;
  if r > 0 && l.drop_last == 0 {
    return q + 1;
  }
  return q;
}

/// Order entries already consumed. Complexity: O(1).
pub fn loader_position(l: &Loader) -> Int {
  return l.cursor;
}

/// True when loader_next would return another batch. Complexity: O(1).
pub fn loader_has_next(l: &Loader) -> Bool {
  let rem = l.order.len() - l.cursor;
  if rem <= 0 {
    return false;
  }
  if rem >= l.batch_size {
    return true;
  }
  if l.drop_last == 1 {
    return false;
  }
  return true;
}

/// Assemble the next batch from the dataset and advance the loader.
/// Returns: Ok(Batch) of up to batch_size rows in order (the final batch may
/// be partial when drop_last is 0).
/// Error case: Err("data: dataset does not match loader") when `d` differs
/// from the dataset the loader was built for; Err("data: loader is
/// exhausted") when the pass is complete.
/// Complexity: O(batch_size * width).
pub fn loader_next(d: &Dataset, l: &mut Loader) -> Result[Batch, Str] {
  if d.n != l.n || d.width != l.width {
    return _err_batch("data: dataset does not match loader");
  }
  var rem = l.order.len() - l.cursor;
  if rem <= 0 {
    return _err_batch("data: loader is exhausted");
  }
  if rem < l.batch_size && l.drop_last == 1 {
    return _err_batch("data: loader is exhausted");
  }
  var count = l.batch_size;
  if rem < count {
    count = rem;
  }
  var idx = Vec[Int].new();
  var k = 0;
  while k < count {
    let v: Int = l.order[l.cursor + k];
    idx.push(v);
    k = k + 1;
  }
  let result = batch_assemble(d, &idx);
  l.cursor = l.cursor + count;
  return result;
}

/// Rewind the loader to the first order entry. Complexity: O(1).
pub fn loader_reset(l: &mut Loader) {
  l.cursor = 0;
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

// Exact permutation test for a vector of length n: every value in 0 .. n-1
// appears exactly once. O(n) time and marking space.
fn _bat_is_permutation(order: &Vec[Int], n: Int) -> Bool {
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

fn _ok_batch(b: Batch) -> Result[Batch, Str] {
  return Ok(b);
}

fn _err_batch(msg: Str) -> Result[Batch, Str] {
  return Err(msg);
}

fn _ok_loader(l: Loader) -> Result[Loader, Str] {
  return Ok(l);
}

fn _err_loader(msg: Str) -> Result[Loader, Str] {
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
