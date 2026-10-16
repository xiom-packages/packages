module xiom.numpy

// xiom.numpy -- Phase 2a core storage (pure XIOM).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Phase 2a replaces the Phase-1 "backend unavailable" fallback for the core
// storage leg with REAL, self-contained storage: an Int handle registry over a
// flat f64 value buffer plus per-handle shape/dtype metadata. No NumPy, no
// Python, no OpenBLAS, no FFI on any creation/access path -- registry consumers
// cannot assume a Python+numpy install, so native storage is the contract.
// The C-bridge seam (bridge/numpy_bridge.c, wired via port.args.json) is kept
// for the element-wise/linear-algebra leg owned by Phase 2b, which is where a
// PyArray_* / OpenBLAS backend may be linked for acceleration.
//
// Element-wise (add/sub/mul/div) and linear-algebra (dot/matmul) are NOT part
// of Phase 2a: their wrappers still report the not-yet-implemented backend via
// the bridge, exactly as Phase 1 did.

pub type NDArray = Int;
pub type DType = Int;

pub const DTYPE_INT32: Int = 0;
pub const DTYPE_INT64: Int = 1;
pub const DTYPE_FLOAT32: Int = 2;
pub const DTYPE_FLOAT64: Int = 3;

const ND_MAX_ELEMS: Int = 1000000;

// ---------------------------------------------------------------------------
// Handle registry (module-level state)
// ---------------------------------------------------------------------------
// A handle is 1 + slot index; handle 0 is always invalid. Slots are appended
// only -- array_free marks a slot dead but never reuses it, so a stale handle
// can never silently alias a later allocation. Metadata is held in parallel
// flat arenas so no nested Vec is written at runtime.

var _nd_data: Vec[Float64] = Vec[Float64].new();
var _nd_base: Vec[Int] = Vec[Int].new();
var _nd_size: Vec[Int] = Vec[Int].new();
var _nd_dtype: Vec[Int] = Vec[Int].new();
var _nd_ndim: Vec[Int] = Vec[Int].new();
var _nd_shape_off: Vec[Int] = Vec[Int].new();
var _nd_shape: Vec[Int] = Vec[Int].new();
var _nd_live: Vec[Bool] = Vec[Bool].new();

// True when `h` refers to a live slot.
fn _nd_valid(h: Int) -> Bool {
  if h <= 0 { return false; }
  let i = h - 1;
  if i >= _nd_live.len() { return false; }
  return _nd_live[i];
}

// Row-major element count of `shape`; -1 on a negative dim or over the cap.
fn _nd_numel(shape: &Vec[Int]) -> Int {
  var n: Int = 1;
  var k = 0;
  while k < shape.len() {
    let d = shape[k];
    if d < 0 { return -1; }
    if d == 0 { return 0; }
    if n > ND_MAX_ELEMS / d { return -1; }
    n = n * d;
    k = k + 1;
  };
  return n;
}

// Append a slot with `numel` copies of `fill`; returns the new handle.
fn _nd_alloc_filled(shape: &Vec[Int], dtype: DType, numel: Int, fill: Float64) -> NDArray {
  let base = _nd_data.len();
  var j = 0;
  while j < numel {
    _nd_data.push(fill);
    j = j + 1;
  };
  let soff = _nd_shape.len();
  var k = 0;
  while k < shape.len() {
    _nd_shape.push(shape[k]);
    k = k + 1;
  };
  _nd_base.push(base);
  _nd_size.push(numel);
  _nd_dtype.push(dtype);
  _nd_ndim.push(shape.len());
  _nd_shape_off.push(soff);
  _nd_live.push(true);
  return _nd_live.len();
}

// Append a slot holding a copy of `data`; returns the new handle.
fn _nd_alloc_from(data: &Vec[Float64], shape: &Vec[Int], dtype: DType) -> NDArray {
  let base = _nd_data.len();
  var j = 0;
  while j < data.len() {
    _nd_data.push(data[j]);
    j = j + 1;
  };
  let soff = _nd_shape.len();
  var k = 0;
  while k < shape.len() {
    _nd_shape.push(shape[k]);
    k = k + 1;
  };
  _nd_base.push(base);
  _nd_size.push(data.len());
  _nd_dtype.push(dtype);
  _nd_ndim.push(shape.len());
  _nd_shape_off.push(soff);
  _nd_live.push(true);
  return _nd_live.len();
}

// Number of elements arange(start, stop, step) yields; -1 over the cap.
fn _nd_arange_count(start: Float64, stop: Float64, step: Float64) -> Int {
  var n = 0;
  var v = start;
  if step > 0.0 {
    while v < stop {
      n = n + 1;
      if n > ND_MAX_ELEMS { return -1; }
      v = v + step;
    };
  } else {
    while v > stop {
      n = n + 1;
      if n > ND_MAX_ELEMS { return -1; }
      v = v + step;
    };
  };
  return n;
}

// ---------------------------------------------------------------------------
// Array creation (REAL; no FFI)
// ---------------------------------------------------------------------------

pub fn array_new(shape: &Vec[Int], dtype: DType) -> Result[NDArray, Str]
  requires: shape.len() > 0
{
  if !is_valid_dtype(dtype) {
    return Err("numpy: array_new invalid dtype");
  };
  let numel = _nd_numel(shape);
  if numel < 0 {
    return Err("numpy: array_new invalid shape");
  };
  return Ok(_nd_alloc_filled(shape, dtype, numel, 0.0));
}

pub fn array_zeros(shape: &Vec[Int], dtype: DType) -> Result[NDArray, Str]
  requires: shape.len() > 0
{
  if !is_valid_dtype(dtype) {
    return Err("numpy: array_zeros invalid dtype");
  };
  let numel = _nd_numel(shape);
  if numel < 0 {
    return Err("numpy: array_zeros invalid shape");
  };
  return Ok(_nd_alloc_filled(shape, dtype, numel, 0.0));
}

pub fn array_ones(shape: &Vec[Int], dtype: DType) -> Result[NDArray, Str]
  requires: shape.len() > 0
{
  if !is_valid_dtype(dtype) {
    return Err("numpy: array_ones invalid dtype");
  };
  let numel = _nd_numel(shape);
  if numel < 0 {
    return Err("numpy: array_ones invalid shape");
  };
  return Ok(_nd_alloc_filled(shape, dtype, numel, 1.0));
}

pub fn array_arange(start: Float64, stop: Float64, step: Float64) -> Result[NDArray, Str]
  requires: step != 0.0
{
  let count = _nd_arange_count(start, stop, step);
  if count < 0 {
    return Err("numpy: array_arange too many elements");
  };
  let base = _nd_data.len();
  var i = 0;
  while i < count {
    _nd_data.push(start + (i as Float64) * step);
    i = i + 1;
  };
  let soff = _nd_shape.len();
  _nd_shape.push(count);
  _nd_base.push(base);
  _nd_size.push(count);
  _nd_dtype.push(DTYPE_FLOAT64);
  _nd_ndim.push(1);
  _nd_shape_off.push(soff);
  _nd_live.push(true);
  return Ok(_nd_live.len());
}

pub fn array_from_data(data: &Vec[Float64], shape: &Vec[Int]) -> Result[NDArray, Str]
  requires: data.len() > 0
  requires: shape.len() > 0
{
  let numel = _nd_numel(shape);
  if numel < 0 {
    return Err("numpy: array_from_data invalid shape");
  };
  if numel != data.len() {
    return Err("numpy: array_from_data shape/data size mismatch");
  };
  return Ok(_nd_alloc_from(data, shape, DTYPE_FLOAT64));
}

// ---------------------------------------------------------------------------
// Properties
// ---------------------------------------------------------------------------

pub fn array_ndim(arr: &NDArray) -> Int
  requires: arr != 0
{
  let h: Int = *arr;
  if !_nd_valid(h) { return 0; }
  return _nd_ndim[h - 1];
}

pub fn array_shape(arr: &NDArray) -> Vec[Int]
  requires: arr != 0
{
  var out = Vec[Int].new();
  let h: Int = *arr;
  if !_nd_valid(h) { return out; }
  let i = h - 1;
  let ndim = _nd_ndim[i];
  let soff = _nd_shape_off[i];
  var k = 0;
  while k < ndim {
    out.push(_nd_shape[soff + k]);
    k = k + 1;
  };
  return out;
}

pub fn array_size(arr: &NDArray) -> Int
  requires: arr != 0
{
  let h: Int = *arr;
  if !_nd_valid(h) { return 0; }
  return _nd_size[h - 1];
}

pub fn array_dtype(arr: &NDArray) -> DType
  requires: arr != 0
{
  let h: Int = *arr;
  if !_nd_valid(h) { return -1; }
  return _nd_dtype[h - 1];
}

// ---------------------------------------------------------------------------
// Indexing (REAL; typed Err on invalid handle / rank / bounds)
// ---------------------------------------------------------------------------

pub fn array_get(arr: &NDArray, indices: &Vec[Int]) -> Result[Float64, Str]
  requires: arr != 0
  requires: indices.len() > 0
{
  let h: Int = *arr;
  if !_nd_valid(h) {
    return Err("numpy: array_get invalid handle");
  };
  let i = h - 1;
  let ndim = _nd_ndim[i];
  if indices.len() != ndim {
    return Err("numpy: array_get index rank mismatch");
  };
  let soff = _nd_shape_off[i];
  var off = 0;
  var k = 0;
  while k < ndim {
    let dim = _nd_shape[soff + k];
    let idx = indices[k];
    if idx < 0 || idx >= dim {
      return Err("numpy: array_get index out of bounds");
    };
    off = off * dim + idx;
    k = k + 1;
  };
  return Ok(_nd_data[_nd_base[i] + off]);
}

pub fn array_set(arr: &mut NDArray, indices: &Vec[Int], val: Float64) -> Result[(), Str]
  requires: arr != 0
  requires: indices.len() > 0
{
  let h: Int = *arr;
  if !_nd_valid(h) {
    return Err("numpy: array_set invalid handle");
  };
  let i = h - 1;
  let ndim = _nd_ndim[i];
  if indices.len() != ndim {
    return Err("numpy: array_set index rank mismatch");
  };
  let soff = _nd_shape_off[i];
  var off = 0;
  var k = 0;
  while k < ndim {
    let dim = _nd_shape[soff + k];
    let idx = indices[k];
    if idx < 0 || idx >= dim {
      return Err("numpy: array_set index out of bounds");
    };
    off = off * dim + idx;
    k = k + 1;
  };
  _nd_data[_nd_base[i] + off] = val;
  return Ok(());
}

pub fn array_free(arr: NDArray)
  requires: arr != 0
{
  let h: Int = arr;
  if _nd_valid(h) {
    _nd_live[h - 1] = false;
  };
}

pub fn dtype_to_str(dtype: DType) -> Str {
  if dtype == DTYPE_INT32 {
    return "int32";
  };
  if dtype == DTYPE_INT64 {
    return "int64";
  };
  if dtype == DTYPE_FLOAT32 {
    return "float32";
  };
  if dtype == DTYPE_FLOAT64 {
    return "float64";
  };
  return "unknown";
}

pub fn is_valid_dtype(dtype: DType) -> Bool {
  return dtype == DTYPE_INT32 || dtype == DTYPE_INT64 || dtype == DTYPE_FLOAT32 || dtype == DTYPE_FLOAT64;
}

// ---------------------------------------------------------------------------
// Phase 2b seam: element-wise and linear algebra still report the pending
// backend through the package-local bridge (bridge/numpy_bridge.c).
// ---------------------------------------------------------------------------

extern "C" {
  fn numpy_c_array_add(a: Int, b: Int) -> Int;
  fn numpy_c_array_sub(a: Int, b: Int) -> Int;
  fn numpy_c_array_mul(a: Int, b: Int) -> Int;
  fn numpy_c_array_div(a: Int, b: Int) -> Int;
  fn numpy_c_array_dot(a: Int, b: Int) -> Int;
  fn numpy_c_array_matmul(a: Int, b: Int) -> Int;
}

pub fn array_add(a: &NDArray, b: &NDArray) -> Result[NDArray, Str]
  requires: a != 0
  requires: b != 0
{
  let handle: Int = unsafe { numpy_c_array_add(*a, *b) };
  if handle <= 0 {
    return Err("numpy_c_array_add: FFI bridge not linked or shape mismatch");
  };
  return Ok(handle);
}

pub fn array_sub(a: &NDArray, b: &NDArray) -> Result[NDArray, Str]
  requires: a != 0
  requires: b != 0
{
  let handle: Int = unsafe { numpy_c_array_sub(*a, *b) };
  if handle <= 0 {
    return Err("numpy_c_array_sub: FFI bridge not linked or shape mismatch");
  };
  return Ok(handle);
}

pub fn array_mul(a: &NDArray, b: &NDArray) -> Result[NDArray, Str]
  requires: a != 0
  requires: b != 0
{
  let handle: Int = unsafe { numpy_c_array_mul(*a, *b) };
  if handle <= 0 {
    return Err("numpy_c_array_mul: FFI bridge not linked or shape mismatch");
  };
  return Ok(handle);
}

pub fn array_div(a: &NDArray, b: &NDArray) -> Result[NDArray, Str]
  requires: a != 0
  requires: b != 0
{
  let handle: Int = unsafe { numpy_c_array_div(*a, *b) };
  if handle <= 0 {
    return Err("numpy_c_array_div: FFI bridge not linked or shape mismatch");
  };
  return Ok(handle);
}

pub fn array_dot(a: &NDArray, b: &NDArray) -> Result[NDArray, Str]
  requires: a != 0
  requires: b != 0
{
  let handle: Int = unsafe { numpy_c_array_dot(*a, *b) };
  if handle <= 0 {
    return Err("numpy_c_array_dot: FFI bridge not linked or dimension mismatch");
  };
  return Ok(handle);
}

pub fn array_matmul(a: &NDArray, b: &NDArray) -> Result[NDArray, Str]
  requires: a != 0
  requires: b != 0
{
  let handle: Int = unsafe { numpy_c_array_matmul(*a, *b) };
  if handle <= 0 {
    return Err("numpy_c_array_matmul: FFI bridge not linked or dimension mismatch");
  };
  return Ok(handle);
}
