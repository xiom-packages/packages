module xiom.numpy

use xiom.openblas;

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
// Phase 2b (this pass) lands the element-wise and linear-algebra leg on top of
// that storage, still with no FFI on the compute path:
//   * add/sub/mul/div are pure-XIOM element-wise loops with a same-shape rule
//     (identical ndim + extents) that fails closed with a typed Err; div is
//     fail-closed on any zero divisor element.
//   * dot/matmul delegate to the xiom.openblas declared surface (pure-XIOM
//     reference paths: dot for 1-D inner products, gemm for 2-D products over
//     the pool's row-major layout, which matches this arena's layout).
// The C-bridge seam (bridge/numpy_bridge.c, wired via port.args.json) is
// retained for a future PyArray_* / real-BLAS acceleration behind the same
// NDArray surface; nothing in this module calls it.

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

// 2-D x 2-D matrix product via xiom.openblas.gemm (row-major pool layout).
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
