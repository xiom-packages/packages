// XIOM -- xiom.tensorflow.tensor: TF_Tensor lifecycle + typed data access.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// The tensor tier of the declared surface: TF_NewTensor / TF_AllocateTensor /
// TF_DeleteTensor / TF_TensorType / TF_SetShape / TF_NumDims / TF_Dim /
// TF_TensorByteSize / TF_TensorData / TF_TensorElementCount /
// TF_TensorBitcastFrom / TF_TensorIsAligned plus the Float32/Int32 data
// helpers built on them. All calls go through the resolved entry-point table
// of a loaded TfLibrary (see xiom.tensorflow.loader for the ABI seam).

module xiom.tensorflow.tensor

use xiom.tensorflow.types;
use xiom.tensorflow.loader;
use xiom.ffi;

// =========================================================================
// Raw data access (base + index is a byte offset)
// =========================================================================

/// Store a Float32 at byte offset `off` from `base`.
/// Complexity: O(1).
pub fn tf_f32_store(base: Int, off: Int, v: Float32)
  requires: base != 0
  requires: off >= 0
{
  unsafe {
    let p: *mut Float32 = (base + off) as *mut Float32;
    *p = v;
  }
}

/// Load a Float32 at byte offset `off` from `base`.
/// Complexity: O(1).
pub fn tf_f32_load(base: Int, off: Int) -> Float32
  requires: base != 0
  requires: off >= 0
{
  unsafe {
    let p: *const Float32 = (base + off) as *const Float32;
    return *p;
  }
}

/// Store an Int32 at byte offset `off` from `base`.
/// Complexity: O(1).
pub fn tf_i32_store(base: Int, off: Int, v: Int)
  requires: base != 0
  requires: off >= 0
{
  unsafe {
    ffi.ptr_write_u32_le((base + off) as *UInt8, v);
  }
}

/// Load a signed Int32 at byte offset `off` from `base`.
/// Complexity: O(1).
pub fn tf_i32_load(base: Int, off: Int) -> Int
  requires: base != 0
  requires: off >= 0
{
  var u = 0;
  unsafe {
    u = ffi.ptr_read_u32_le((base + off) as *UInt8);
  }
  if (u & 2147483648) != 0 { return u - 4294967296; }
  return u;
}

/// Product of a shape vector (1 for an empty/rank-0 shape).
/// Complexity: O(rank).
pub fn tf_shape_count(dims: &Vec[Int]) -> Int
  requires: true
{
  var n = 1;
  var i = 0;
  while i < dims.len() {
    n = n * dims[i];
    i = i + 1;
  };
  return n;
}

// =========================================================================
// Lifecycle
// =========================================================================

/// TF_AllocateTensor: TF-owned, aligned storage of `byte_len` bytes.
/// Complexity: O(1).
pub fn tf_tensor_alloc(lib: &TfLibrary, dtype: Int, dims: &Vec[Int], byte_len: Int) -> Result[Int, TfError]
  requires: dims.len() > 0
  requires: byte_len >= 0
{
  if dims.len() == 0 { return Err(TfError{ kind: types.TF_CALL_FAILED; message: "tensor_alloc: empty shape" }); }
  if byte_len < 0 { return Err(TfError{ kind: types.TF_CALL_FAILED; message: "tensor_alloc: negative byte length" }); }
  let fp = loader.tf_fn(lib, loader.TF_FN_AllocateTensor);
  if fp == 0 {
    return Err(TfError{ kind: types.TF_CALL_FAILED; message: "tensor_alloc: TF_AllocateTensor missing" });
  }
  var dptr = 0;
  unsafe {
    dptr = dims.as_mut_ptr() as Int;
  }
  unsafe {
    let f = fp as fn(Int, Int, Int32, Int) -> Int;
    let t = f(dtype, dptr, dims.len() as Int32, byte_len);
    if t == 0 {
      return Err(TfError{ kind: types.TF_CALL_FAILED; message: "tensor_alloc: TF_AllocateTensor returned null" });
    }
    return Ok(t);
  }
}

/// TF_TensorDefaultAlignment (the required alignment for the borrowed-data
/// path); 64 as the documented EIGEN_MAX_ALIGN_BYTES floor for official x64
/// CPU builds when the slot is unavailable. Complexity: O(1).
pub fn tf_tensor_default_alignment(lib: &TfLibrary) -> Int
  requires: true
{
  let fp = loader.tf_fn(lib, loader.TF_FN_TensorDefaultAlignment);
  if fp == 0 { return 64; }
  unsafe {
    let f = fp as fn() -> Int;
    let a = f();
    if a <= 0 { return 64; }
    return a;
  }
}

/// TF_NewTensor with a null deallocator: wraps caller-owned storage (the
/// caller keeps the buffer alive for the tensor's lifetime).
//
// Live-verified TF behavior (AUDIT.md finding TF-A1): TF_NewTensor takes a
// copy path when `data` is not aligned to TF_TensorDefaultAlignment, and
// that path INVOKES the deallocator argument immediately -- with a null
// deallocator that is a call through NULL inside TensorFlow. The wrapper
// therefore refuses unaligned buffers with a typed error before the call:
// use TF_AllocateTensor + TF_TensorData (tf_tensor_alloc) for TF-owned
// storage, or pass storage aligned to tf_tensor_default_alignment(lib).
/// Complexity: O(1).
pub fn tf_tensor_borrow(lib: &TfLibrary, dtype: Int, dims: &Vec[Int], data: Int, byte_len: Int) -> Result[Int, TfError]
  requires: dims.len() > 0
  requires: data != 0
  requires: byte_len > 0
{
  if dims.len() == 0 { return Err(TfError{ kind: types.TF_CALL_FAILED; message: "tensor_borrow: empty shape" }); }
  if data == 0 { return Err(TfError{ kind: types.TF_CALL_FAILED; message: "tensor_borrow: null data" }); }
  let align = tf_tensor_default_alignment(lib);
  if data % align != 0 {
    return Err(TfError{
      kind: types.TF_CALL_FAILED;
      message: "tensor_borrow: data address is not " + loader.int_to_str(align) +
        "-byte aligned; TF_NewTensor would take the copy path and call the (null) deallocator -- use tf_tensor_alloc or aligned storage",
    });
  }
  let fp = loader.tf_fn(lib, loader.TF_FN_NewTensor);
  if fp == 0 {
    return Err(TfError{ kind: types.TF_CALL_FAILED; message: "tensor_borrow: TF_NewTensor missing" });
  }
  var dptr = 0;
  unsafe {
    dptr = dims.as_mut_ptr() as Int;
  }
  var t = 0;
  unsafe {
    let f = fp as fn(Int, Int, Int32, Int, Int, Int, Int) -> Int;
    t = f(dtype, dptr, dims.len() as Int32, data, byte_len, 0, 0);
  }
  if t == 0 {
    return Err(TfError{ kind: types.TF_CALL_FAILED; message: "tensor_borrow: TF_NewTensor returned null (inconsistent data/shape)" });
  }
  return Ok(t);
}

/// TF_DeleteTensor (safe on 0).
/// Complexity: O(1).
pub fn tf_tensor_delete(lib: &TfLibrary, t: Int)
  requires: true
{
  if t == 0 { return; }
  let fp = loader.tf_fn(lib, loader.TF_FN_DeleteTensor);
  if fp == 0 { return; }
  unsafe {
    let f = fp as fn(Int) -> Unit;
    f(t);
  }
}

// =========================================================================
// Queries
// =========================================================================

/// TF_TensorType. Complexity: O(1).
pub fn tf_tensor_type(lib: &TfLibrary, t: Int) -> Int
  requires: t != 0
{
  let fp = loader.tf_fn(lib, loader.TF_FN_TensorType);
  if fp == 0 { return -1; }
  unsafe {
    let f = fp as fn(Int) -> Int32;
    return f(t) as Int;
  }
}

/// TF_NumDims. Complexity: O(1).
pub fn tf_tensor_num_dims(lib: &TfLibrary, t: Int) -> Int
  requires: t != 0
{
  let fp = loader.tf_fn(lib, loader.TF_FN_NumDims);
  if fp == 0 { return -1; }
  unsafe {
    let f = fp as fn(Int) -> Int32;
    return f(t) as Int;
  }
}

/// TF_Dim for one axis. Complexity: O(1).
pub fn tf_tensor_dim(lib: &TfLibrary, t: Int, axis: Int) -> Int
  requires: t != 0
  requires: axis >= 0
{
  let fp = loader.tf_fn(lib, loader.TF_FN_Dim);
  if fp == 0 { return -1; }
  unsafe {
    let f = fp as fn(Int, Int32) -> Int;
    return f(t, axis as Int32);
  }
}

/// TF_TensorByteSize. Complexity: O(1).
pub fn tf_tensor_byte_size(lib: &TfLibrary, t: Int) -> Int
  requires: t != 0
{
  let fp = loader.tf_fn(lib, loader.TF_FN_TensorByteSize);
  if fp == 0 { return -1; }
  unsafe {
    let f = fp as fn(Int) -> Int;
    return f(t);
  }
}

/// TF_TensorElementCount. Complexity: O(1).
pub fn tf_tensor_element_count(lib: &TfLibrary, t: Int) -> Int
  requires: t != 0
{
  let fp = loader.tf_fn(lib, loader.TF_FN_TensorElementCount);
  if fp == 0 { return -1; }
  unsafe {
    let f = fp as fn(Int) -> Int;
    return f(t);
  }
}

/// TF_TensorData (the underlying storage address). Complexity: O(1).
pub fn tf_tensor_data(lib: &TfLibrary, t: Int) -> Int
  requires: t != 0
{
  let fp = loader.tf_fn(lib, loader.TF_FN_TensorData);
  if fp == 0 { return 0; }
  unsafe {
    let f = fp as fn(Int) -> Int;
    return f(t);
  }
}

/// TF_TensorIsAligned (bool return read as one byte). Complexity: O(1).
pub fn tf_tensor_is_aligned(lib: &TfLibrary, t: Int) -> Bool
  requires: t != 0
{
  let fp = loader.tf_fn(lib, loader.TF_FN_TensorIsAligned);
  if fp == 0 { return false; }
  unsafe {
    let f = fp as fn(Int) -> Int;
    return (f(t) & 255) != 0;
  }
}

/// TF_SetShape. Complexity: O(rank).
pub fn tf_tensor_set_shape(lib: &TfLibrary, t: Int, dims: &Vec[Int])
  requires: t != 0
  requires: dims.len() > 0
{
  let fp = loader.tf_fn(lib, loader.TF_FN_SetShape);
  if fp == 0 { return; }
  var dptr = 0;
  unsafe {
    dptr = dims.as_mut_ptr() as Int;
  }
  unsafe {
    let f = fp as fn(Int, Int, Int32) -> Unit;
    f(t, dptr, dims.len() as Int32);
  }
}

/// TF_TensorBitcastFrom: reinterpret `from` as `dtype`/`new_dims` into `to`
/// (both tensors share storage; byte sizes must match).
/// Complexity: O(1).
pub fn tf_tensor_bitcast(lib: &TfLibrary, from: Int, dtype: Int, to: Int, new_dims: &Vec[Int]) -> Result[Unit, TfError]
  requires: from != 0
  requires: to != 0
{
  let fp = loader.tf_fn(lib, loader.TF_FN_TensorBitcastFrom);
  if fp == 0 {
    return Err(TfError{ kind: types.TF_CALL_FAILED; message: "tensor_bitcast: TF_TensorBitcastFrom missing" });
  }
  let sp = loader.tf_fn(lib, loader.TF_FN_NewStatus);
  if sp == 0 {
    return Err(TfError{ kind: types.TF_CALL_FAILED; message: "tensor_bitcast: TF_NewStatus missing" });
  }
  unsafe {
    let mk = sp as fn() -> Int;
    let st = mk();
    var dptr = 0;
    if new_dims.len() > 0 {
      dptr = new_dims.as_mut_ptr() as Int;
    }
    let f = fp as fn(Int, Int, Int, Int, Int32, Int) -> Unit;
    f(from, dtype, to, dptr, new_dims.len() as Int32, st);
    return loader.tf_check(lib, st, "TensorBitcastFrom");
  }
}

/// Shape + dtype + size summary of a tensor (Shape: -1 = unknown rank).
/// Complexity: O(rank).
pub fn tf_tensor_info(lib: &TfLibrary, t: Int) -> TfTensorInfo
  requires: t != 0
{
  let dtype = tf_tensor_type(lib, t);
  let nd = tf_tensor_num_dims(lib, t);
  var dims: Vec[Int] = Vec[Int].new();
  if nd > 0 {
    var i = 0;
    while i < nd {
      dims.push(tf_tensor_dim(lib, t, i));
      i = i + 1;
    };
  }
  return TfTensorInfo{
    dtype: dtype;
    dims: dims;
    bytes: tf_tensor_byte_size(lib, t);
    elements: tf_tensor_element_count(lib, t);
  };
}

// =========================================================================
// Typed creation + reads
// =========================================================================

/// Create a TF_FLOAT tensor from values (shape product must equal the value
/// count). Complexity: O(elements).
pub fn tf_tensor_create_f32(lib: &TfLibrary, dims: &Vec[Int], values: &Vec[Float32]) -> Result[Int, TfError]
  requires: dims.len() > 0
  requires: values.len() > 0
{
  let n = tf_shape_count(dims);
  if n != values.len() {
    return Err(TfError{
      kind: types.TF_CALL_FAILED;
      message: "tensor_create_f32: shape " + loader.int_to_str(n) + " != values " + loader.int_to_str(values.len()),
    });
  }
  let tr = tf_tensor_alloc(lib, types.TF_FLOAT, dims, n * 4);
  if !tr.is_ok { return Err(tr.error); }
  let t = tr.value;
  let base = tf_tensor_data(lib, t);
  if base == 0 {
    tf_tensor_delete(lib, t);
    return Err(TfError{ kind: types.TF_CALL_FAILED; message: "tensor_create_f32: TF_TensorData null" });
  }
  var i = 0;
  while i < n {
    tf_f32_store(base, i * 4, values[i]);
    i = i + 1;
  };
  return Ok(t);
}

/// Create a TF_INT32 tensor from values. Complexity: O(elements).
pub fn tf_tensor_create_i32(lib: &TfLibrary, dims: &Vec[Int], values: &Vec[Int]) -> Result[Int, TfError]
  requires: dims.len() > 0
  requires: values.len() > 0
{
  let n = tf_shape_count(dims);
  if n != values.len() {
    return Err(TfError{
      kind: types.TF_CALL_FAILED;
      message: "tensor_create_i32: shape " + loader.int_to_str(n) + " != values " + loader.int_to_str(values.len()),
    });
  }
  let tr = tf_tensor_alloc(lib, types.TF_INT32, dims, n * 4);
  if !tr.is_ok { return Err(tr.error); }
  let t = tr.value;
  let base = tf_tensor_data(lib, t);
  if base == 0 {
    tf_tensor_delete(lib, t);
    return Err(TfError{ kind: types.TF_CALL_FAILED; message: "tensor_create_i32: TF_TensorData null" });
  }
  var i = 0;
  while i < n {
    tf_i32_store(base, i * 4, values[i]);
    i = i + 1;
  };
  return Ok(t);
}

/// Read `count` Float32 elements out of a tensor's storage.
/// Complexity: O(count).
pub fn tf_tensor_read_f32(lib: &TfLibrary, t: Int, count: Int) -> Result[TfF32List, TfError]
  requires: t != 0
  requires: count >= 0
{
  let base = tf_tensor_data(lib, t);
  if base == 0 {
    return Err(TfError{ kind: types.TF_CALL_FAILED; message: "tensor_read_f32: TF_TensorData null" });
  }
  let have = tf_tensor_element_count(lib, t);
  if count > have {
    return Err(TfError{
      kind: types.TF_CALL_FAILED;
      message: "tensor_read_f32: requested " + loader.int_to_str(count) + " > elements " + loader.int_to_str(have),
    });
  }
  var items: Vec[Float32] = Vec[Float32].new();
  var i = 0;
  while i < count {
    items.push(tf_f32_load(base, i * 4));
    i = i + 1;
  };
  return Ok(TfF32List{ items: items });
}

/// Read `count` Int32 elements out of a tensor's storage.
/// Complexity: O(count).
pub fn tf_tensor_read_i32(lib: &TfLibrary, t: Int, count: Int) -> Result[TfIntList, TfError]
  requires: t != 0
  requires: count >= 0
{
  let base = tf_tensor_data(lib, t);
  if base == 0 {
    return Err(TfError{ kind: types.TF_CALL_FAILED; message: "tensor_read_i32: TF_TensorData null" });
  }
  let have = tf_tensor_element_count(lib, t);
  if count > have {
    return Err(TfError{
      kind: types.TF_CALL_FAILED;
      message: "tensor_read_i32: requested " + loader.int_to_str(count) + " > elements " + loader.int_to_str(have),
    });
  }
  var items: Vec[Int] = Vec[Int].new();
  var i = 0;
  while i < count {
    items.push(tf_i32_load(base, i * 4));
    i = i + 1;
  };
  return Ok(TfIntList{ items: items });
}
