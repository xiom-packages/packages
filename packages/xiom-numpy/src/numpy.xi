module xiom.numpy

use xiom.openblas;
use xiom.math;

// xiom.numpy -- Phase 2a core storage (pure XIOM).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Phase 2a replaces the Phase-1 "backend unavailable" fallback for the core
// storage leg with REAL, self-contained storage: an Int handle registry over a
// flat f64 value buffer plus per-handle shape/dtype metadata. No NumPy, no
// Python, no FFI on any creation/access path -- registry consumers cannot
// assume a Python+numpy install, so native storage is the contract.
//
// Phase 2b lands the element-wise and linear-algebra leg on top of that
// storage; Phase 3d adds the acceleration dispatch seam:
//   * add/sub/mul/div are pure-XIOM element-wise loops with broadcasting and
//     a fail-closed typed Err surface; div is fail-closed on any zero divisor.
//   * dot delegates to the xiom.openblas declared surface (reference path on
//     the stub leg, cblas_ddot on the real leg).
//   * matmul dispatches on the typed `AccelLeg` marker: real OpenBLAS
//     (xiom.openblas.backend_is_real()) marshals into the pool and calls
//     cblas_dgemm via xiom.openblas.gemm; the stub/offline leg (and any build
//     without a real BLAS) runs numpy's own row-major triple loop, so the
//     conformance suite needs no FFI and stays offline-deterministic.
// The C-bridge seam (bridge/numpy_bridge.c, wired via port.args.json) is
// retained for a future PyArray_* path behind the same NDArray surface;
// nothing in this module calls it.

pub type NDArray = Int;
pub type DType = Int;

pub const DTYPE_INT32: Int = 0;
pub const DTYPE_INT64: Int = 1;
pub const DTYPE_FLOAT32: Int = 2;
pub const DTYPE_FLOAT64: Int = 3;

const ND_MAX_ELEMS: Int = 1000000;

// ---------------------------------------------------------------------------
// Phase-3d: acceleration dispatch decision seam.
// ---------------------------------------------------------------------------
// Numeric heavy ops resolve their implementation through `acceleration_leg()`.
// The marker is typed so a dispatch decision cannot be confused with an
// arbitrary Int; it is derived once from the xiom.openblas linked-leg marker:
//   * AccelLeg.OpenBlasReal -- the artifact is linked against real OpenBLAS
//     (xiom.openblas.backend_is_real() == true), so heavy ops marshal into the
//     openblas pool and call cblas_*/LAPACK.
//   * AccelLeg.SelfContained -- the documented offline/stub leg (no real BLAS
//     linked). numpy runs its own pure-XIOM loops, which keeps the conformance
//     suite offline-deterministic and needs no FFI.
// This is a fail-closed decision: only the explicit real marker selects the
// accelerated path; anything else stays self-contained.

pub enum AccelLeg {
  SelfContained,
  OpenBlasReal,
}

/// The acceleration leg this build resolves to. Derived from the linked
/// xiom.openblas leg marker, never from an environment probe.
pub fn acceleration_leg() -> AccelLeg {
  if xiom.openblas.backend_is_real() {
    return AccelLeg.OpenBlasReal;
  }
  return AccelLeg.SelfContained;
}

/// Stable label for the dispatch decision (used by diagnostics and the
/// conformance suite to pin the leg without comparing enum encodings).
pub fn acceleration_leg_name(leg: &AccelLeg) -> Str {
  match leg {
    AccelLeg.SelfContained => "self-contained",
    AccelLeg.OpenBlasReal => "openblas-real",
  }
}

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
// Phase 2b: element-wise math over the REAL storage (pure XIOM, no FFI).
// ---------------------------------------------------------------------------
// Same-shape rule: both operands must have identical ndim and identical extent
// on every axis; anything else fails closed with a typed Err. The result is a
// fresh array (same shape, same dtype as the left operand) backed by new slots
// in the value arena, so operands are never aliased or mutated.
//
// Division policy (documented, fail-closed): array_div treats a zero divisor
// element as an error, not IEEE inf/NaN. The first element where b == 0.0
// aborts the whole op with Err("numpy: array_div division by zero"); no partial
// result is committed or returned.

// Extent of slot `i` on `axis`; a negative axis is a missing leading axis and
// therefore broadcasts as extent 1.
fn _nd_dim_at(i: Int, axis: Int) -> Int {
  if axis < 0 { return 1; };
  return _nd_shape[_nd_shape_off[i] + axis];
}

// Row-major strides of `shape` appended to `out` (out[j] = product of extents
// to the right of axis j). N-D stride handling built on the flat f64 arena.
fn _nd_strides_of_shape(shape: &Vec[Int], out: &mut Vec[Int]) {
  let n = shape.len();
  var j = 0;
  while j < n {
    var s = 1;
    var t = j + 1;
    while t < n {
      s = s * shape[t];
      t = t + 1;
    };
    out.push(s);
    j = j + 1;
  };
}

// Broadcast result shape of slots ia and ib appended to `out`; false when an
// axis is incompatible (NumPy rule: extents equal, or one of them is 1).
fn _nd_broadcast_shape(ia: Int, ib: Int, out: &mut Vec[Int]) -> Bool {
  let nda = _nd_ndim[ia];
  let ndb = _nd_ndim[ib];
  var maxnd = nda;
  if ndb > maxnd { maxnd = ndb; };
  var j = 0;
  while j < maxnd {
    let da = _nd_dim_at(ia, nda - maxnd + j);
    let db = _nd_dim_at(ib, ndb - maxnd + j);
    if da != db && da != 1 && db != 1 { return false; };
    var rd = da;
    if db > rd { rd = db; };
    out.push(rd);
    j = j + 1;
  };
  return true;
}

// Stride of slot `i` (extent `ndi`) along result axis `j` of an `nd`-axis
// broadcast: 0 when the axis is stretched (missing axis or extent 1), else the
// operand's own row-major stride.
fn _nd_bc_stride(i: Int, ndi: Int, nd: Int, j: Int) -> Int {
  let a = ndi - nd + j;
  if a < 0 { return 0; };
  let d = _nd_shape[_nd_shape_off[i] + a];
  if d == 1 { return 0; };
  var s = 1;
  var t = a + 1;
  while t < ndi {
    s = s * _nd_shape[_nd_shape_off[i] + t];
    t = t + 1;
  };
  return s;
}

// kind: 0 = add, 1 = sub, 2 = mul, 3 = div (fail-closed on zero divisor).
// NumPy broadcasting: operands align from the right and stretch along axes
// where an extent is 1 (or the axis is missing). The result keeps the broadcast
// shape and the left operand's dtype; operands are never aliased or mutated.
// With identical shapes this is exactly the Phase-2b same-shape loop.
fn _nd_elementwise(ha: Int, hb: Int, kind: Int, op: Str) -> Result[NDArray, Str] {
  if !_nd_valid(ha) || !_nd_valid(hb) {
    return Err("numpy: " + op + " invalid handle");
  };
  let ia = ha - 1;
  let ib = hb - 1;
  var rshape: Vec[Int] = Vec[Int].new();
  if !_nd_broadcast_shape(ia, ib, &mut rshape) {
    return Err("numpy: " + op + " shape mismatch");
  };
  let nd = rshape.len();
  let numel = _nd_numel(&rshape);
  if numel < 0 {
    return Err("numpy: " + op + " result too large");
  };
  var rstr: Vec[Int] = Vec[Int].new();
  _nd_strides_of_shape(&rshape, &mut rstr);
  let nda = _nd_ndim[ia];
  let ndb = _nd_ndim[ib];
  var astr: Vec[Int] = Vec[Int].new();
  var bstr: Vec[Int] = Vec[Int].new();
  var j = 0;
  while j < nd {
    astr.push(_nd_bc_stride(ia, nda, nd, j));
    bstr.push(_nd_bc_stride(ib, ndb, nd, j));
    j = j + 1;
  };
  let ba = _nd_base[ia];
  let bb = _nd_base[ib];
  var out: Vec[Float64] = Vec[Float64].new();
  var p = 0;
  while p < numel {
    var rem = p;
    var ao = 0;
    var bo = 0;
    var k = 0;
    while k < nd {
      let idx = rem / rstr[k];
      rem = rem - idx * rstr[k];
      ao = ao + idx * astr[k];
      bo = bo + idx * bstr[k];
      k = k + 1;
    };
    let x = _nd_data[ba + ao];
    let y = _nd_data[bb + bo];
    if kind == 0 {
      out.push(x + y);
    } elif kind == 1 {
      out.push(x - y);
    } elif kind == 2 {
      out.push(x * y);
    } else {
      if y == 0.0 {
        return Err("numpy: array_div division by zero");
      };
      out.push(x / y);
    };
    p = p + 1;
  };
  return Ok(_nd_alloc_from(&out, &rshape, _nd_dtype[ia]));
}

pub fn array_add(a: &NDArray, b: &NDArray) -> Result[NDArray, Str]
  requires: a != 0
  requires: b != 0
{
  return _nd_elementwise(*a, *b, 0, "array_add");
}

pub fn array_sub(a: &NDArray, b: &NDArray) -> Result[NDArray, Str]
  requires: a != 0
  requires: b != 0
{
  return _nd_elementwise(*a, *b, 1, "array_sub");
}

pub fn array_mul(a: &NDArray, b: &NDArray) -> Result[NDArray, Str]
  requires: a != 0
  requires: b != 0
{
  return _nd_elementwise(*a, *b, 2, "array_mul");
}

pub fn array_div(a: &NDArray, b: &NDArray) -> Result[NDArray, Str]
  requires: a != 0
  requires: b != 0
{
  return _nd_elementwise(*a, *b, 3, "array_div");
}

// ---------------------------------------------------------------------------
// Phase 2b: linear algebra. Delegates to the xiom.openblas declared surface
// (pure-XIOM reference paths: dot for vector inner products, gemm for 2-D
// matrix products over the pool's row-major layout). x.shape[0] * ... indexing
// matches the openblas pool's index = row * cols + col, so the layout fits.
// ---------------------------------------------------------------------------

// Copy slot `i`'s row-major values into a flat Vec (order preserved).
fn _nd_flat(i: Int) -> Vec[Float64] {
  var v: Vec[Float64] = Vec[Float64].new();
  var k = 0;
  while k < _nd_size[i] {
    v.push(_nd_data[_nd_base[i] + k]);
    k = k + 1;
  };
  return v;
}

// Self-contained 2-D x 2-D product (offline/stub leg): a row-major triple
// loop over the flat f64 arena. The accumulation order is the documented
// fallback reference order; it is what the suite pins.
fn _nd_matmul_self(ia: Int, ib: Int, m: Int, n: Int, k: Int) -> NDArray {
  let abase = _nd_base[ia];
  let bbase = _nd_base[ib];
  var out: Vec[Float64] = Vec[Float64].new();
  var i = 0;
  while i < m {
    var j = 0;
    while j < n {
      var sum: Float64 = 0.0;
      var p = 0;
      while p < k {
        sum = sum + _nd_data[abase + i * k + p] * _nd_data[bbase + p * n + j];
        p = p + 1;
      };
      out.push(sum);
      j = j + 1;
    };
    i = i + 1;
  };
  var sh: Vec[Int] = Vec[Int].new();
  sh.push(m);
  sh.push(n);
  return _nd_alloc_from(&out, &sh, DTYPE_FLOAT64);
}

// Real-leg 2-D x 2-D product: marshal both operands into the xiom.openblas
// row-major pool and call gemm (cblas_dgemm when linked against real
// OpenBLAS). Errors from the pool allocation propagate as typed Err.
fn _nd_matmul_openblas(ia: Int, ib: Int, m: Int, n: Int, k: Int) -> Result[NDArray, Str] {
  var ma = xiom.openblas.matrix_create(m, k)?;
  var mb = xiom.openblas.matrix_create(k, n)?;
  var mc = xiom.openblas.matrix_create(m, n)?;
  var i = 0;
  while i < m {
    var j = 0;
    while j < k {
      xiom.openblas.matrix_set(&mut ma, i, j, _nd_data[_nd_base[ia] + i * k + j]);
      j = j + 1;
    };
    i = i + 1;
  };
  i = 0;
  while i < k {
    var j = 0;
    while j < n {
      xiom.openblas.matrix_set(&mut mb, i, j, _nd_data[_nd_base[ib] + i * n + j]);
      j = j + 1;
    };
    i = i + 1;
  };
  xiom.openblas.gemm(false, false, m, n, k, 1.0, &ma, &mb, 0.0, &mut mc);
  var out: Vec[Float64] = Vec[Float64].new();
  i = 0;
  while i < m {
    var j = 0;
    while j < n {
      out.push(xiom.openblas.matrix_get(&mc, i, j));
      j = j + 1;
    };
    i = i + 1;
  };
  xiom.openblas.matrix_free(ma);
  xiom.openblas.matrix_free(mb);
  xiom.openblas.matrix_free(mc);
  var sh: Vec[Int] = Vec[Int].new();
  sh.push(m);
  sh.push(n);
  return Ok(_nd_alloc_from(&out, &sh, DTYPE_FLOAT64));
}

// 2-D x 2-D dispatch: real OpenBLAS when the linked leg marker says so,
// otherwise the self-contained fallback. Shape/rank validation happens here
// so both legs share the exact same fail-closed error surface.
fn _nd_matmul_2d(ia: Int, ib: Int) -> Result[NDArray, Str] {
  let sa = _nd_shape_off[ia];
  let sb = _nd_shape_off[ib];
  let arows = _nd_shape[sa + 0];
  let acols = _nd_shape[sa + 1];
  let brows = _nd_shape[sb + 0];
  let bcols = _nd_shape[sb + 1];
  if acols != brows {
    return Err("numpy: array_matmul inner dimension mismatch");
  };
  let m = arows;
  let n = bcols;
  let k = acols;
  if m <= 0 || n <= 0 || k <= 0 {
    return Err("numpy: array_matmul empty dimension");
  };
  if acceleration_leg() == AccelLeg.OpenBlasReal {
    return _nd_matmul_openblas(ia, ib, m, n, k);
  };
  return Ok(_nd_matmul_self(ia, ib, m, n, k));
}

// numpy dot: 1-D . 1-D -> inner product (shape [1]); 2-D . 2-D -> matrix product.
pub fn array_dot(a: &NDArray, b: &NDArray) -> Result[NDArray, Str]
  requires: a != 0
  requires: b != 0
{
  let ha: Int = *a;
  let hb: Int = *b;
  if !_nd_valid(ha) || !_nd_valid(hb) {
    return Err("numpy: array_dot invalid handle");
  };
  let ia = ha - 1;
  let ib = hb - 1;
  let nda = _nd_ndim[ia];
  let ndb = _nd_ndim[ib];
  if nda == 1 && ndb == 1 {
    let n = _nd_size[ia];
    if n != _nd_size[ib] {
      return Err("numpy: array_dot shape mismatch");
    };
    if n <= 0 {
      return Err("numpy: array_dot empty vector");
    };
    let x = _nd_flat(ia);
    let y = _nd_flat(ib);
    let s = xiom.openblas.dot(&x, &y, n);
    var out: Vec[Float64] = Vec[Float64].new();
    out.push(s);
    var sh: Vec[Int] = Vec[Int].new();
    sh.push(1);
    return Ok(_nd_alloc_from(&out, &sh, DTYPE_FLOAT64));
  };
  if nda == 2 && ndb == 2 {
    return _nd_matmul_2d(ia, ib);
  };
  return Err("numpy: array_dot rank mismatch");
}

// numpy matmul: strictly 2-D x 2-D; inner dimensions must agree.
pub fn array_matmul(a: &NDArray, b: &NDArray) -> Result[NDArray, Str]
  requires: a != 0
  requires: b != 0
{
  let ha: Int = *a;
  let hb: Int = *b;
  if !_nd_valid(ha) || !_nd_valid(hb) {
    return Err("numpy: array_matmul invalid handle");
  };
  let ia = ha - 1;
  let ib = hb - 1;
  if _nd_ndim[ia] != 2 || _nd_ndim[ib] != 2 {
    return Err("numpy: array_matmul rank mismatch (requires 2-D)");
  };
  return _nd_matmul_2d(ia, ib);
}

// ---------------------------------------------------------------------------
// Phase 3a: reshape + transpose over the flat f64 arena.
// ---------------------------------------------------------------------------
// reshape copies the row-major values of `arr` into a fresh slot carrying the
// requested shape. The element count must match exactly (C-order reshape);
// anything else fails closed. transpose reverses the axis order (NumPy
// semantics) and copies values into a fresh slot, so it works for any rank and
// keeps 2-D transpose exact: [r, c] -> [c, r] with out[j, i] = in[i, j].

pub fn array_reshape(arr: &NDArray, new_shape: &Vec[Int]) -> Result[NDArray, Str]
  requires: arr != 0
  requires: new_shape.len() > 0
{
  let h: Int = *arr;
  if !_nd_valid(h) {
    return Err("numpy: array_reshape invalid handle");
  };
  let i = h - 1;
  let nnew = _nd_numel(new_shape);
  if nnew < 0 {
    return Err("numpy: array_reshape invalid shape");
  };
  if nnew != _nd_size[i] {
    return Err("numpy: array_reshape size mismatch");
  };
  let flat = _nd_flat(i);
  return Ok(_nd_alloc_from(&flat, new_shape, _nd_dtype[i]));
}

pub fn array_transpose(arr: &NDArray) -> Result[NDArray, Str]
  requires: arr != 0
{
  let h: Int = *arr;
  if !_nd_valid(h) {
    return Err("numpy: array_transpose invalid handle");
  };
  let i = h - 1;
  let nd = _nd_ndim[i];
  let so = _nd_shape_off[i];
  var sshape: Vec[Int] = Vec[Int].new();
  var rshape: Vec[Int] = Vec[Int].new();
  var j = 0;
  while j < nd {
    sshape.push(_nd_shape[so + j]);
    rshape.push(_nd_shape[so + nd - 1 - j]);
    j = j + 1;
  };
  var sstr: Vec[Int] = Vec[Int].new();
  var rstr: Vec[Int] = Vec[Int].new();
  _nd_strides_of_shape(&sshape, &mut sstr);
  _nd_strides_of_shape(&rshape, &mut rstr);
  let numel = _nd_size[i];
  var out: Vec[Float64] = Vec[Float64].new();
  var p = 0;
  while p < numel {
    var rem = p;
    var off = 0;
    var k = 0;
    while k < nd {
      let idx = rem / rstr[k];
      rem = rem - idx * rstr[k];
      off = off + idx * sstr[nd - 1 - k];
      k = k + 1;
    };
    out.push(_nd_data[_nd_base[i] + off]);
    p = p + 1;
  };
  return Ok(_nd_alloc_from(&out, &rshape, _nd_dtype[i]));
}

// ---------------------------------------------------------------------------
// Phase 3b: reductions over the flat f64 arena (sum/mean/max/min).
// ---------------------------------------------------------------------------
// axis == -1 reduces over ALL axes and yields shape [1] (the full-array
// reduction, i.e. the "axis omitted" convention of the SPEC surface). axis in
// [0, ndim) reduces that axis only, dropping it from the result shape (a 1-D
// input reduced on axis 0 yields shape [1]). Any other axis is a typed Err.
// An empty input fails closed with a typed Err for every reducer. Row-major
// input/output strides come from `_nd_strides_of_shape`, so this honors the
// same N-D stride helpers as the Phase-3a element-wise path; the result is a
// fresh array in new slots (operands are never aliased or mutated).

fn _nd_abs(x: Float64) -> Float64 {
  if x < 0.0 { return -x; };
  return x;
}

// kind: 0 = sum, 1 = mean, 2 = max, 3 = min.
fn _nd_reduce(ha: Int, axis: Int, kind: Int, op: Str) -> Result[NDArray, Str] {
  if !_nd_valid(ha) {
    return Err("numpy: " + op + " invalid handle");
  };
  let i = ha - 1;
  let nd = _nd_ndim[i];
  var full = false;
  if axis == -1 {
    full = true;
  } elif axis < 0 || axis >= nd {
    return Err("numpy: " + op + " axis out of range");
  };
  let isize = _nd_size[i];
  if isize <= 0 {
    return Err("numpy: " + op + " empty array");
  };
  var ishape: Vec[Int] = Vec[Int].new();
  let so = _nd_shape_off[i];
  var j = 0;
  while j < nd {
    ishape.push(_nd_shape[so + j]);
    j = j + 1;
  };
  var istr: Vec[Int] = Vec[Int].new();
  _nd_strides_of_shape(&ishape, &mut istr);
  // Output shape plus the input-axis -> output-axis map (-1 == reduced axis).
  var oshape: Vec[Int] = Vec[Int].new();
  var omap: Vec[Int] = Vec[Int].new();
  if full {
    oshape.push(1);
    j = 0;
    while j < nd {
      omap.push(-1);
      j = j + 1;
    };
  } else {
    j = 0;
    while j < nd {
      if j == axis {
        omap.push(-1);
      } else {
        omap.push(oshape.len());
        oshape.push(ishape[j]);
      };
      j = j + 1;
    };
    if oshape.len() == 0 {
      oshape.push(1);
    };
  };
  var ostr: Vec[Int] = Vec[Int].new();
  _nd_strides_of_shape(&oshape, &mut ostr);
  let osize = _nd_numel(&oshape);
  var out: Vec[Float64] = Vec[Float64].new();
  var q = 0;
  while q < osize {
    if kind == 2 {
      out.push(-1.0e308);
    } elif kind == 3 {
      out.push(1.0e308);
    } else {
      out.push(0.0);
    };
    q = q + 1;
  };
  let base = _nd_base[i];
  var p = 0;
  while p < isize {
    var rem = p;
    var ooff = 0;
    var k = 0;
    while k < nd {
      let idx = rem / istr[k];
      rem = rem - idx * istr[k];
      if omap[k] >= 0 {
        ooff = ooff + idx * ostr[omap[k]];
      };
      k = k + 1;
    };
    let x = _nd_data[base + p];
    if kind == 0 || kind == 1 {
      out[ooff] = out[ooff] + x;
    } elif kind == 2 {
      if x > out[ooff] { out[ooff] = x; };
    } else {
      if x < out[ooff] { out[ooff] = x; };
    };
    p = p + 1;
  };
  if kind == 1 {
    var count = isize;
    if !full {
      count = ishape[axis];
    };
    if count <= 0 {
      return Err("numpy: " + op + " empty reduction axis");
    };
    q = 0;
    while q < osize {
      out[q] = out[q] / (count as Float64);
      q = q + 1;
    };
  };
  return Ok(_nd_alloc_from(&out, &oshape, _nd_dtype[i]));
}

pub fn array_sum(arr: &NDArray, axis: Int) -> Result[NDArray, Str]
  requires: arr != 0
{
  return _nd_reduce(*arr, axis, 0, "array_sum");
}

pub fn array_mean(arr: &NDArray, axis: Int) -> Result[NDArray, Str]
  requires: arr != 0
{
  return _nd_reduce(*arr, axis, 1, "array_mean");
}

pub fn array_max(arr: &NDArray, axis: Int) -> Result[NDArray, Str]
  requires: arr != 0
{
  return _nd_reduce(*arr, axis, 2, "array_max");
}

pub fn array_min(arr: &NDArray, axis: Int) -> Result[NDArray, Str]
  requires: arr != 0
{
  return _nd_reduce(*arr, axis, 3, "array_min");
}

// ---------------------------------------------------------------------------
// Phase 3b: square-matrix inverse (Gauss-Jordan, partial pivoting).
// ---------------------------------------------------------------------------
// Self-contained over the flat f64 arena. Phase-3d deliberately leaves inv on
// this path on BOTH legs: xiom.openblas exposes `solve`, not `inv`, so a real
// leg would need n unit-vector dgesv_ solves and a different singular /
// near-singular contract than the pivot-epsilon policy below. The LAPACK path
// remains the documented acceleration target behind the same NDArray surface.
// Fail-closed: a non-2-D operand, a non-square matrix, a matrix whose augmented
// buffer would exceed the element cap, or a singular matrix (no pivot above the
// tolerance while eliminating a column) all return a typed Err; no partial
// result is returned.

const ND_INV_PIVOT_EPS: Float64 = 0.000000000001;

pub fn array_inv(arr: &NDArray) -> Result[NDArray, Str]
  requires: arr != 0
{
  let h: Int = *arr;
  if !_nd_valid(h) {
    return Err("numpy: array_inv invalid handle");
  };
  let i = h - 1;
  if _nd_ndim[i] != 2 {
    return Err("numpy: array_inv requires 2-D");
  };
  let so = _nd_shape_off[i];
  let n = _nd_shape[so + 0];
  let cols = _nd_shape[so + 1];
  if n != cols {
    return Err("numpy: array_inv requires square matrix");
  };
  if n <= 0 {
    return Err("numpy: array_inv empty matrix");
  };
  let w = 2 * n;
  if n > ND_MAX_ELEMS / w {
    return Err("numpy: array_inv matrix too large");
  };
  // Augmented [A | I] as a flat row-major n x (2n) buffer.
  var aug: Vec[Float64] = Vec[Float64].new();
  let base = _nd_base[i];
  var r = 0;
  while r < n {
    var c = 0;
    while c < n {
      aug.push(_nd_data[base + r * n + c]);
      c = c + 1;
    };
    c = 0;
    while c < n {
      if c == r {
        aug.push(1.0);
      } else {
        aug.push(0.0);
      };
      c = c + 1;
    };
    r = r + 1;
  };
  // Gauss-Jordan elimination with partial pivoting.
  var col = 0;
  while col < n {
    var piv = col;
    var best = _nd_abs(aug[piv * w + col]);
    r = col + 1;
    while r < n {
      let v = _nd_abs(aug[r * w + col]);
      if v > best {
        best = v;
        piv = r;
      };
      r = r + 1;
    };
    if best < ND_INV_PIVOT_EPS {
      return Err("numpy: array_inv singular matrix");
    };
    if piv != col {
      var cc = 0;
      while cc < w {
        let t = aug[col * w + cc];
        aug[col * w + cc] = aug[piv * w + cc];
        aug[piv * w + cc] = t;
        cc = cc + 1;
      };
    };
    let d = aug[col * w + col];
    var cc2 = 0;
    while cc2 < w {
      aug[col * w + cc2] = aug[col * w + cc2] / d;
      cc2 = cc2 + 1;
    };
    var r2 = 0;
    while r2 < n {
      if r2 != col {
        let f = aug[r2 * w + col];
        if f != 0.0 {
          var c2 = 0;
          while c2 < w {
            aug[r2 * w + c2] = aug[r2 * w + c2] - f * aug[col * w + c2];
            c2 = c2 + 1;
          };
        };
      };
      r2 = r2 + 1;
    };
    col = col + 1;
  };
  var out: Vec[Float64] = Vec[Float64].new();
  var rr = 0;
  while rr < n {
    var cc3 = 0;
    while cc3 < n {
      out.push(aug[rr * w + n + cc3]);
      cc3 = cc3 + 1;
    };
    rr = rr + 1;
  };
  var sh: Vec[Int] = Vec[Int].new();
  sh.push(n);
  sh.push(n);
  return Ok(_nd_alloc_from(&out, &sh, _nd_dtype[i]));
}

// ---------------------------------------------------------------------------
// Phase 3c: singular value decomposition (one-sided Jacobi, self-contained).
// ---------------------------------------------------------------------------
// Self-contained over the flat f64 arena -- no BLAS/LAPACK on either leg, so
// it stays deterministic offline. Phase-3d accelerates matmul only; the
// openblas/LAPACK SVD remains the documented acceleration target. The
// one-sided Jacobi method rotates each column
// pair (p, q) of a working copy W of A until the columns of W are mutually
// orthogonal; the accumulated rotations build V, and the converged column
// norms are the singular values, so A = U * S * V^T with V orthogonal. The
// singular values are sorted descending (with U and V permuted the same way).
//
// Returned shapes: U is m x n (thin), S is the n x n diagonal matrix of
// singular values (descending), Vt is n x n with A = U * S * Vt. This S-as-a-
// diagonal-matrix convention matches the xiom.openblas.svd seam and keeps the
// whole reconstruction on the existing 2-D `array_matmul` path. It is a
// documented deviation from NumPy's 1-D `s` (see SPEC.md).
//
// Scope: 2-D with m >= n (tall or square). Fail-closed typed Err on a non-2-D
// operand, an empty matrix, m < n (wide), a freed/invalid handle, or failure
// to converge within the sweep cap. Rank-deficient inputs are supported: a
// singular value at or below a relative threshold is treated as zero and its
// U column is completed to an orthonormal vector by Gram-Schmidt, so U stays
// orthogonal even when A is rank-deficient.

const ND_SVD_MAX_SWEEPS: Int = 100;
const ND_SVD_TOL: Float64 = 1.0e-14;
const ND_SVD_ZERO_REL: Float64 = 1.0e-12;

pub fn array_svd(arr: &NDArray) -> Result[(NDArray, NDArray, NDArray), Str]
  requires: arr != 0
{
  let h: Int = *arr;
  if !_nd_valid(h) {
    return Err("numpy: array_svd invalid handle");
  };
  let i = h - 1;
  if _nd_ndim[i] != 2 {
    return Err("numpy: array_svd requires 2-D");
  };
  let so = _nd_shape_off[i];
  let m = _nd_shape[so + 0];
  let n = _nd_shape[so + 1];
  if m <= 0 || n <= 0 {
    return Err("numpy: array_svd empty matrix");
  };
  if m < n {
    return Err("numpy: array_svd requires m >= n");
  };
  let base = _nd_base[i];
  // Working copy W (m x n, row-major); V (n x n) starts as the identity.
  var w: Vec[Float64] = Vec[Float64].new();
  var r = 0;
  while r < m {
    var c = 0;
    while c < n {
      w.push(_nd_data[base + r * n + c]);
      c = c + 1;
    };
    r = r + 1;
  };
  var v: Vec[Float64] = Vec[Float64].new();
  r = 0;
  while r < n {
    var c = 0;
    while c < n {
      if c == r { v.push(1.0); } else { v.push(0.0); };
      c = c + 1;
    };
    r = r + 1;
  };
  // One-sided Jacobi sweeps: rotate column pairs (p, q) of W and V so the
  // columns of W become mutually orthogonal; repeat until every pair is below
  // ND_SVD_TOL (relative) or the sweep cap is reached.
  var sweep = 0;
  var converged = false;
  while sweep < ND_SVD_MAX_SWEEPS && !converged {
    converged = true;
    var p = 0;
    while p < n - 1 {
      var q = p + 1;
      while q < n {
        var alpha = 0.0;
        var beta = 0.0;
        var gamma = 0.0;
        var rr = 0;
        while rr < m {
          let wp = w[rr * n + p];
          let wq = w[rr * n + q];
          alpha = alpha + wp * wp;
          beta = beta + wq * wq;
          gamma = gamma + wp * wq;
          rr = rr + 1;
        };
        if alpha > 0.0 && beta > 0.0 {
          if _nd_abs(gamma) > ND_SVD_TOL * math.sqrt(alpha * beta) {
            converged = false;
            let zeta = (beta - alpha) / (2.0 * gamma);
            var sz = 1.0;
            if zeta < 0.0 { sz = -1.0; };
            let t = sz / (_nd_abs(zeta) + math.sqrt(1.0 + zeta * zeta));
            let cs = 1.0 / math.sqrt(1.0 + t * t);
            let sn = cs * t;
            rr = 0;
            while rr < m {
              let wp = w[rr * n + p];
              let wq = w[rr * n + q];
              w[rr * n + p] = cs * wp - sn * wq;
              w[rr * n + q] = sn * wp + cs * wq;
              rr = rr + 1;
            };
            rr = 0;
            while rr < n {
              let vp = v[rr * n + p];
              let vq = v[rr * n + q];
              v[rr * n + p] = cs * vp - sn * vq;
              v[rr * n + q] = sn * vp + cs * vq;
              rr = rr + 1;
            };
          };
        };
        q = q + 1;
      };
      p = p + 1;
    };
    sweep = sweep + 1;
  };
  if !converged {
    return Err("numpy: array_svd did not converge");
  };
  // Singular values = converged column norms; U columns = normalized W columns.
  var sigma: Vec[Float64] = Vec[Float64].new();
  var maxs = 0.0;
  var j = 0;
  while j < n {
    var nrm = 0.0;
    var rr = 0;
    while rr < m {
      let x = w[rr * n + j];
      nrm = nrm + x * x;
      rr = rr + 1;
    };
    nrm = math.sqrt(nrm);
    sigma.push(nrm);
    if nrm > maxs { maxs = nrm; };
    j = j + 1;
  };
  let thresh = maxs * ND_SVD_ZERO_REL;
  var u: Vec[Float64] = Vec[Float64].new();
  var z = 0;
  while z < m * n {
    u.push(0.0);
    z = z + 1;
  };
  j = 0;
  while j < n {
    if sigma[j] > thresh {
      var rr = 0;
      while rr < m {
        u[rr * n + j] = w[rr * n + j] / sigma[j];
        rr = rr + 1;
      };
    };
    j = j + 1;
  };
  // Sort singular values descending; permute U and V columns identically.
  j = 0;
  while j < n {
    var besti = j;
    var k = j + 1;
    while k < n {
      if sigma[k] > sigma[besti] { besti = k; };
      k = k + 1;
    };
    if besti != j {
      let ts = sigma[j];
      sigma[j] = sigma[besti];
      sigma[besti] = ts;
      var rr = 0;
      while rr < m {
        let tu = u[rr * n + j];
        u[rr * n + j] = u[rr * n + besti];
        u[rr * n + besti] = tu;
        rr = rr + 1;
      };
      rr = 0;
      while rr < n {
        let tv = v[rr * n + j];
        v[rr * n + j] = v[rr * n + besti];
        v[rr * n + besti] = tv;
        rr = rr + 1;
      };
    };
    j = j + 1;
  };
  // Complete zero-singular-value U columns to an orthonormal vector by
  // Gram-Schmidt against every other U column (standard basis candidates).
  j = 0;
  while j < n {
    if sigma[j] <= thresh {
      var done = false;
      var trial = 0;
      while trial < m && !done {
        var cand: Vec[Float64] = Vec[Float64].new();
        var rr = 0;
        while rr < m {
          if rr == trial { cand.push(1.0); } else { cand.push(0.0); };
          rr = rr + 1;
        };
        var k = 0;
        while k < n {
          if k != j {
            var d = 0.0;
            rr = 0;
            while rr < m {
              d = d + cand[rr] * u[rr * n + k];
              rr = rr + 1;
            };
            rr = 0;
            while rr < m {
              cand[rr] = cand[rr] - d * u[rr * n + k];
              rr = rr + 1;
            };
          };
          k = k + 1;
        };
        var nrm = 0.0;
        rr = 0;
        while rr < m {
          nrm = nrm + cand[rr] * cand[rr];
          rr = rr + 1;
        };
        nrm = math.sqrt(nrm);
        if nrm > 1.0e-12 {
          rr = 0;
          while rr < m {
            u[rr * n + j] = cand[rr] / nrm;
            rr = rr + 1;
          };
          done = true;
        };
        trial = trial + 1;
      };
      if !done {
        return Err("numpy: array_svd orthogonal completion failed");
      };
    };
    j = j + 1;
  };
  // Pack S (n x n diagonal) and Vt = V^T (n x n).
  var sdata: Vec[Float64] = Vec[Float64].new();
  var rr2 = 0;
  while rr2 < n {
    var c2 = 0;
    while c2 < n {
      if c2 == rr2 { sdata.push(sigma[rr2]); } else { sdata.push(0.0); };
      c2 = c2 + 1;
    };
    rr2 = rr2 + 1;
  };
  var vt: Vec[Float64] = Vec[Float64].new();
  rr2 = 0;
  while rr2 < n {
    var c2 = 0;
    while c2 < n {
      vt.push(v[c2 * n + rr2]);
      c2 = c2 + 1;
    };
    rr2 = rr2 + 1;
  };
  var ush: Vec[Int] = Vec[Int].new();
  ush.push(m);
  ush.push(n);
  var ssh: Vec[Int] = Vec[Int].new();
  ssh.push(n);
  ssh.push(n);
  let uh = _nd_alloc_from(&u, &ush, DTYPE_FLOAT64);
  let sh = _nd_alloc_from(&sdata, &ssh, DTYPE_FLOAT64);
  let vth = _nd_alloc_from(&vt, &ssh, DTYPE_FLOAT64);
  return Ok((uh, sh, vth));
}
