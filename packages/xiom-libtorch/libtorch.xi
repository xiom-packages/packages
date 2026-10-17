// XIOM -- xiom.libtorch: the declared tensor-level surface of the libtorch
// (PyTorch C++ distribution) AOTInductor C ABI + C++ anchors.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Every function here is a thin, contract-checked wrapper over
// `xiom.libtorch.loader`: the loader resolves the declared surface from a
// libtorch build found by its multi-soname candidates (typed SKIP when
// absent) and these wrappers call through the resolved fn pointers.  No
// extern "C" declarations, no link-time dependency: the suite runs green
// on hosts without libtorch.
//
// Type discipline: tensor handles are opaque Ints (AtenTensorHandle);
// nothing casts them to pointers outside a call site.  Floats cross the
// C boundary only as inputs or via 4/8-byte out-params (B-12 discipline);
// float payloads are rebuilt with loader.lt_f32_from_bits.
//
// Contract notes (SPEC.md carries the full table):
//   * a "new" result handle (create/clone/add/mul/mm/reshape/narrow/...)
//     is owning: free it with torch_tensor_free.
//   * tensor_from_data COPIES the caller's data (the returned tensor never
//     aliases XIOM memory).
//   * tensor_to_vec requires a contiguous tensor (reshape/ops keep
//     contiguity; narrow of dim 0 keeps it, other narrows may not).

module xiom.libtorch

use xiom.libtorch.loader;
use xiom.ffi;

// =========================================================================
// Loader-facing surface
// =========================================================================

/// Load the first available libtorch build (multi-soname candidates;
/// LT_LOAD_ABSENT = typed SKIP when no runtime is installed).
/// Complexity: O(candidates * surface).
pub fn torch_load() -> Result[LtLibrary, LtError]
  requires: true
{
  return loader.lt_load();
}

/// Load an explicitly named build (path or soname; bogus names exercise
/// the ABSENT/SKIP classification deterministically on any host).
/// Complexity: O(load + surface check).
pub fn torch_load_named(soname: Str) -> Result[LtLibrary, LtError]
  requires: soname.len() > 0
{
  return loader.lt_load_named(soname);
}

/// The multi-soname candidate list in probe order.
/// Complexity: O(1).
pub fn torch_load_candidates() -> Vec[Str]
  requires: true
{
  return loader.lt_load_candidates();
}

/// Version + declared-surface counts of a loaded build.
/// Complexity: O(1).
pub fn torch_probe(lib: &LtLibrary) -> LtInfo
  requires: lib.handle != 0
{
  return loader.lt_probe(lib);
}

/// Release the library handle.
/// Complexity: O(1).
pub fn torch_close(lib: &LtLibrary) -> Result[Unit, Str]
  requires: lib.handle != 0
{
  return loader.lt_close(lib);
}

/// TORCH_ABI_VERSION of the loaded build (uint64, MAJOR<<56|MINOR<<48|
/// PATCH<<40|ABI_TAG).
/// Complexity: O(1).
pub fn torch_abi_version(lib: &LtLibrary) -> Int
  requires: lib.handle != 0
{
  return lib.abi_version;
}

// =========================================================================
// Small shared helpers
// =========================================================================

fn lt_strides_row_major(shape: &Vec[Int]) -> Vec[Int]
  requires: shape.len() > 0
  requires: shape[shape.len() - 1] > 0
{
  var ndim = shape.len();
  var strides = Vec[Int].new();
  var i = 0;
  while i < ndim {
    strides.push(0);
    i = i + 1;
  };
  strides[ndim - 1] = 1;
  var d = ndim - 2;
  while d >= 0 {
    strides[d] = strides[d + 1] * shape[d + 1];
    d = d - 1;
  };
  return strides;
}

fn lt_numel(shape: &Vec[Int]) -> Int
  requires: shape.len() > 0
{
  var total = 1;
  var i = 0;
  while i < shape.len() {
    total = total * shape[i];
    i = i + 1;
  };
  return total;
}

fn slot8() -> Vec[UInt8]
  requires: true
{
  return Vec[UInt8].with_len(8);
}

fn slot4() -> Vec[UInt8]
  requires: true
{
  return Vec[UInt8].with_len(4);
}

fn rd64(s: &Vec[UInt8]) -> Int
  requires: s.len() >= 8
{
  return ffi.ptr_read_u64_le(s.as_mut_ptr());
}

fn rd32(s: &Vec[UInt8]) -> Int
  requires: s.len() >= 4
{
  return ffi.ptr_read_u32_le(s.as_mut_ptr());
}

// =========================================================================
// T 1-6 -- tensor creation / lifecycle
// =========================================================================

/// Create a zero-initialized Float32 CPU tensor with the given shape
/// (row-major strides).  Owning handle.
/// Complexity: O(numel).
pub fn torch_tensor_new(lib: &LtLibrary, shape: &Vec[Int]) -> Result[Int, LtError]
  requires: lib.handle != 0
  requires: shape.len() > 0
{
  if shape[shape.len() - 1] <= 0 {
    return Err(LtError{ kind: loader.LT_UNAVAILABLE; message: "torch_tensor_new: last dimension must be > 0" });
  }
  let ndim = shape.len();
  let strides = lt_strides_row_major(shape);
  let f_dtype = lib.f_dtype_float32;
  let f_dev = lib.f_device_type_cpu;
  let f_new = lib.f_empty_strided;
  var slot = slot8();
  unsafe {
    let fd = f_dtype as fn() -> Int32;
    let dtype = fd() as Int;
    let fv = f_dev as fn() -> Int32;
    let dev = fv() as Int;
    let f = f_new as fn(Int, *Int, *Int, Int32, Int32, Int32, *UInt8) -> Int32;
    let rc = f(ndim, &shape[0] as *Int, &strides[0] as *Int,
               dtype as Int32, dev as Int32, 0, slot.as_mut_ptr()) as Int;
    if rc != 0 {
      return Err(loader.lt_call_error(lib, rc, "torch_tensor_new: aoti_torch_empty_strided"));
    }
    return Ok(rd64(&slot));
  }
}

/// Create a Float32 CPU tensor filled with 1.0.
/// Complexity: O(numel).
pub fn torch_tensor_ones(lib: &LtLibrary, shape: &Vec[Int]) -> Result[Int, LtError]
  requires: lib.handle != 0
  requires: shape.len() > 0
{
  let created = torch_tensor_new(lib, shape);
  if !created.is_ok { return Err(created.error); }
  let t = created.value;
  let filled = torch_tensor_fill(lib, t, 1.0);
  if !filled.is_ok {
    let ig = torch_tensor_free(lib, t);
    return Err(filled.error);
  }
  return Ok(t);
}

/// Create a zero-initialized Float32 CPU tensor (explicit zero fill over
/// torch_tensor_new; proves the in-place zero_ entry point).
/// Complexity: O(numel).
pub fn torch_tensor_zeros(lib: &LtLibrary, shape: &Vec[Int]) -> Result[Int, LtError]
  requires: lib.handle != 0
  requires: shape.len() > 0
{
  let created = torch_tensor_new(lib, shape);
  if !created.is_ok { return Err(created.error); }
  let t = created.value;
  let zeroed = torch_tensor_zero(lib, t);
  if !zeroed.is_ok {
    let ig = torch_tensor_free(lib, t);
    return Err(zeroed.error);
  }
  return Ok(t);
}

/// Create a Float32 CPU tensor copying `data` (data.len() must equal the
/// shape product).  The borrowed-buffer entry of the C shim wraps `data`
/// for the duration of the copy only; the returned tensor owns a private
/// buffer and never aliases XIOM memory.
/// Complexity: O(numel).
pub fn torch_tensor_from_data(lib: &LtLibrary, data: &Vec[Float32], shape: &Vec[Int]) -> Result[Int, LtError]
  requires: lib.handle != 0
  requires: data.len() > 0
  requires: shape.len() > 0
{
  if data.len() != lt_numel(shape) {
    return Err(LtError{ kind: loader.LT_CALL_FAILED; message: "torch_tensor_from_data: data length does not match the shape product" });
  }
  let dst_r = torch_tensor_new(lib, shape);
  if !dst_r.is_ok { return Err(dst_r.error); }
  let dst = dst_r.value;

  let ndim = shape.len();
  let strides = lt_strides_row_major(shape);
  let f_dtype = lib.f_dtype_float32;
  let f_dev = lib.f_device_type_cpu;
  let f_layout = lib.f_layout_strided;
  let f_blob = lib.f_from_blob_v2;
  let f_copy = lib.f_tensor_copy;
  let f_del = lib.f_delete_tensor;
  var src_slot = slot8();
  unsafe {
    let fd = f_dtype as fn() -> Int32;
    let dtype = fd() as Int;
    let fv = f_dev as fn() -> Int32;
    let dev = fv() as Int;
    let fl = f_layout as fn() -> Int32;
    let layout = fl() as Int;
    let fb = f_blob as fn(*Float32, Int, *Int, *Int, Int, Int32, Int32, Int32, *UInt8, Int32, *UInt8, Int) -> Int32;
    let rc = fb(&data[0] as *Float32, ndim, &shape[0] as *Int, &strides[0] as *Int,
                0, dtype as Int32, dev as Int32, 0, src_slot.as_mut_ptr(),
                layout as Int32, 0 as *UInt8, 0) as Int;
    if rc != 0 {
      let ig = torch_tensor_free(lib, dst);
      return Err(loader.lt_call_error(lib, rc, "torch_tensor_from_data: aoti_torch_create_tensor_from_blob_v2"));
    }
    let src = rd64(&src_slot);
    let fc = f_copy as fn(Int, Int) -> Int32;
    let rc2 = fc(src, dst) as Int;
    let fdel = f_del as fn(Int) -> Int32;
    let ig2 = fdel(src) as Int;
    if rc2 != 0 {
      let ig = torch_tensor_free(lib, dst);
      return Err(loader.lt_call_error(lib, rc2, "torch_tensor_from_data: aoti_torch_tensor_copy_"));
    }
    return Ok(dst);
  }
}

/// Free a tensor handle (owning references only; never a borrowed view of
/// live caller memory).
/// Complexity: O(1).
pub fn torch_tensor_free(lib: &LtLibrary, t: Int) -> Result[Unit, LtError]
  requires: lib.handle != 0
  requires: t != 0
{
  let f_del = lib.f_delete_tensor;
  unsafe {
    let f = f_del as fn(Int) -> Int32;
    let rc = f(t) as Int;
    return loader.lt_check(lib, rc, "torch_tensor_free: aoti_torch_delete_tensor_object");
  }
}

/// Read a contiguous tensor's elements as Float32 (exact round-trip for
/// Float32 data; any Float32 value is exactly representable).
/// Complexity: O(numel).
pub fn torch_tensor_to_vec(lib: &LtLibrary, t: Int) -> Result[Vec[Float32], LtError]
  requires: lib.handle != 0
  requires: t != 0
{
  let c = torch_tensor_is_contiguous(lib, t);
  if !c.is_ok { return Err(c.error); }
  if !c.value {
    return Err(LtError{ kind: loader.LT_UNAVAILABLE; message: "torch_tensor_to_vec: tensor is not contiguous" });
  }
  let n_r = torch_tensor_numel(lib, t);
  if !n_r.is_ok { return Err(n_r.error); }
  let n = n_r.value;
  let p_r = torch_tensor_data_ptr(lib, t);
  if !p_r.is_ok { return Err(p_r.error); }
  let addr = p_r.value;
  var out: Vec[Float32] = Vec[Float32].new();
  var i = 0;
  while i < n {
    let bits = ffi.ptr_read_u32_le((addr + i * 4) as *UInt8);
    out.push(loader.lt_f32_from_bits(bits) as Float32);
    i = i + 1;
  };
  return Ok(out);
}

/// The tensor's underlying (borrowed) data pointer as an Int address.
/// Complexity: O(1).
pub fn torch_tensor_data_ptr(lib: &LtLibrary, t: Int) -> Result[Int, LtError]
  requires: lib.handle != 0
  requires: t != 0
{
  let f_dp = lib.f_get_data_ptr;
  var slot = slot8();
  unsafe {
    let f = f_dp as fn(Int, *UInt8) -> Int32;
    let rc = f(t, slot.as_mut_ptr()) as Int;
    if rc != 0 {
      return Err(loader.lt_call_error(lib, rc, "torch_tensor_data_ptr: aoti_torch_get_data_ptr"));
    }
    return Ok(rd64(&slot));
  }
}

// =========================================================================
// T 7-21 -- metadata + scalars
// =========================================================================

/// Number of elements.
/// Complexity: O(1).
pub fn torch_tensor_numel(lib: &LtLibrary, t: Int) -> Result[Int, LtError]
  requires: lib.handle != 0
  requires: t != 0
{
  let f_numel = lib.f_get_numel;
  var slot = slot8();
  unsafe {
    let f = f_numel as fn(Int, *UInt8) -> Int32;
    let rc = f(t, slot.as_mut_ptr()) as Int;
    if rc != 0 {
      return Err(loader.lt_call_error(lib, rc, "torch_tensor_numel: aoti_torch_get_numel"));
    }
    return Ok(rd64(&slot));
  }
}

/// Number of dimensions.
/// Complexity: O(1).
pub fn torch_tensor_dim(lib: &LtLibrary, t: Int) -> Result[Int, LtError]
  requires: lib.handle != 0
  requires: t != 0
{
  let f_dim = lib.f_get_dim;
  var slot = slot8();
  unsafe {
    let f = f_dim as fn(Int, *UInt8) -> Int32;
    let rc = f(t, slot.as_mut_ptr()) as Int;
    if rc != 0 {
      return Err(loader.lt_call_error(lib, rc, "torch_tensor_dim: aoti_torch_get_dim"));
    }
    return Ok(rd64(&slot));
  }
}

/// Size of dimension `d`.
/// Complexity: O(1).
pub fn torch_tensor_size(lib: &LtLibrary, t: Int, d: Int) -> Result[Int, LtError]
  requires: lib.handle != 0
  requires: t != 0
  requires: d >= 0
{
  let f_size = lib.f_get_size;
  var slot = slot8();
  unsafe {
    let f = f_size as fn(Int, Int, *UInt8) -> Int32;
    let rc = f(t, d, slot.as_mut_ptr()) as Int;
    if rc != 0 {
      return Err(loader.lt_call_error(lib, rc, "torch_tensor_size: aoti_torch_get_size"));
    }
    return Ok(rd64(&slot));
  }
}

/// Stride of dimension `d`.
/// Complexity: O(1).
pub fn torch_tensor_stride(lib: &LtLibrary, t: Int, d: Int) -> Result[Int, LtError]
  requires: lib.handle != 0
  requires: t != 0
  requires: d >= 0
{
  let f_stride = lib.f_get_stride;
  var slot = slot8();
  unsafe {
    let f = f_stride as fn(Int, Int, *UInt8) -> Int32;
    let rc = f(t, d, slot.as_mut_ptr()) as Int;
    if rc != 0 {
      return Err(loader.lt_call_error(lib, rc, "torch_tensor_stride: aoti_torch_get_stride"));
    }
    return Ok(rd64(&slot));
  }
}

/// The shape as an XIOM-owned Vec[Int].
/// Complexity: O(dim).
pub fn torch_tensor_shape(lib: &LtLibrary, t: Int) -> Result[Vec[Int], LtError]
  requires: lib.handle != 0
  requires: t != 0
{
  let d_r = torch_tensor_dim(lib, t);
  if !d_r.is_ok { return Err(d_r.error); }
  let ndim = d_r.value;
  let f_sizes = lib.f_get_sizes;
  var slot = slot8();
  unsafe {
    let f = f_sizes as fn(Int, *UInt8) -> Int32;
    let rc = f(t, slot.as_mut_ptr()) as Int;
    if rc != 0 {
      return Err(loader.lt_call_error(lib, rc, "torch_tensor_shape: aoti_torch_get_sizes"));
    }
    let addr = rd64(&slot);
    var out: Vec[Int] = Vec[Int].new();
    var i = 0;
    while i < ndim {
      out.push(ffi.ptr_read_u64_le((addr + i * 8) as *UInt8));
      i = i + 1;
    };
    return Ok(out);
  }
}

/// The strides as an XIOM-owned Vec[Int].
/// Complexity: O(dim).
pub fn torch_tensor_strides(lib: &LtLibrary, t: Int) -> Result[Vec[Int], LtError]
  requires: lib.handle != 0
  requires: t != 0
{
  let d_r = torch_tensor_dim(lib, t);
  if !d_r.is_ok { return Err(d_r.error); }
  let ndim = d_r.value;
  let f_strides = lib.f_get_strides;
  var slot = slot8();
  unsafe {
    let f = f_strides as fn(Int, *UInt8) -> Int32;
    let rc = f(t, slot.as_mut_ptr()) as Int;
    if rc != 0 {
      return Err(loader.lt_call_error(lib, rc, "torch_tensor_strides: aoti_torch_get_strides"));
    }
    let addr = rd64(&slot);
    var out: Vec[Int] = Vec[Int].new();
    var i = 0;
    while i < ndim {
      out.push(ffi.ptr_read_u64_le((addr + i * 8) as *UInt8));
      i = i + 1;
    };
    return Ok(out);
  }
}

/// Is the tensor C-contiguous?
/// Complexity: O(1).
pub fn torch_tensor_is_contiguous(lib: &LtLibrary, t: Int) -> Result[Bool, LtError]
  requires: lib.handle != 0
  requires: t != 0
{
  let f_c = lib.f_is_contiguous;
  var slot = Vec[UInt8].with_len(1);
  unsafe {
    let f = f_c as fn(Int, *UInt8) -> Int32;
    let rc = f(t, slot.as_mut_ptr()) as Int;
    if rc != 0 {
      return Err(loader.lt_call_error(lib, rc, "torch_tensor_is_contiguous: aoti_torch_is_contiguous"));
    }
    return Ok(ffi.ptr_read_u8(slot.as_mut_ptr()) != 0);
  }
}

/// Is the tensor defined (no undefined placeholder)?
/// Complexity: O(1).
pub fn torch_tensor_is_defined(lib: &LtLibrary, t: Int) -> Result[Bool, LtError]
  requires: lib.handle != 0
  requires: t != 0
{
  let f_d = lib.f_is_defined;
  var slot = Vec[UInt8].with_len(1);
  unsafe {
    let f = f_d as fn(Int, *UInt8) -> Int32;
    let rc = f(t, slot.as_mut_ptr()) as Int;
    if rc != 0 {
      return Err(loader.lt_call_error(lib, rc, "torch_tensor_is_defined: aoti_torch_is_defined"));
    }
    return Ok(ffi.ptr_read_u8(slot.as_mut_ptr()) != 0);
  }
}

/// The tensor's ScalarType code (runtime-defined value; compare against
/// torch_dtype_float32 / torch_dtype_size).
/// Complexity: O(1).
pub fn torch_tensor_dtype(lib: &LtLibrary, t: Int) -> Result[Int, LtError]
  requires: lib.handle != 0
  requires: t != 0
{
  let f_dtype = lib.f_get_dtype;
  var slot = slot4();
  unsafe {
    let f = f_dtype as fn(Int, *UInt8) -> Int32;
    let rc = f(t, slot.as_mut_ptr()) as Int;
    if rc != 0 {
      return Err(loader.lt_call_error(lib, rc, "torch_tensor_dtype: aoti_torch_get_dtype"));
    }
    return Ok(rd32(&slot));
  }
}

/// The tensor's device type code (runtime-defined; compare against
/// torch_device_type_cpu / torch_device_type_cuda).
/// Complexity: O(1).
pub fn torch_tensor_device_type(lib: &LtLibrary, t: Int) -> Result[Int, LtError]
  requires: lib.handle != 0
  requires: t != 0
{
  let f_dt = lib.f_get_device_type;
  var slot = slot4();
  unsafe {
    let f = f_dt as fn(Int, *UInt8) -> Int32;
    let rc = f(t, slot.as_mut_ptr()) as Int;
    if rc != 0 {
      return Err(loader.lt_call_error(lib, rc, "torch_tensor_device_type: aoti_torch_get_device_type"));
    }
    return Ok(rd32(&slot));
  }
}

/// The tensor's device index (sign-extended; CPU tensors report -1).
/// Complexity: O(1).
pub fn torch_tensor_device_index(lib: &LtLibrary, t: Int) -> Result[Int, LtError]
  requires: lib.handle != 0
  requires: t != 0
{
  let f_di = lib.f_get_device_index;
  var slot = slot4();
  unsafe {
    let f = f_di as fn(Int, *UInt8) -> Int32;
    let rc = f(t, slot.as_mut_ptr()) as Int;
    if rc != 0 {
      return Err(loader.lt_call_error(lib, rc, "torch_tensor_device_index: aoti_torch_get_device_index"));
    }
    var v = rd32(&slot);
    if v >= 2147483648 { v = v - 4294967296; }
    return Ok(v);
  }
}

/// The tensor's storage offset.
/// Complexity: O(1).
pub fn torch_tensor_storage_offset(lib: &LtLibrary, t: Int) -> Result[Int, LtError]
  requires: lib.handle != 0
  requires: t != 0
{
  let f_so = lib.f_get_storage_offset;
  var slot = slot8();
  unsafe {
    let f = f_so as fn(Int, *UInt8) -> Int32;
    let rc = f(t, slot.as_mut_ptr()) as Int;
    if rc != 0 {
      return Err(loader.lt_call_error(lib, rc, "torch_tensor_storage_offset: aoti_torch_get_storage_offset"));
    }
    return Ok(rd64(&slot));
  }
}

/// Extract the value of a single-element tensor.
/// Complexity: O(1).
pub fn torch_tensor_item_float32(lib: &LtLibrary, t: Int) -> Result[Float32, LtError]
  requires: lib.handle != 0
  requires: t != 0
{
  let f_item = lib.f_item_f32;
  var slot = slot4();
  unsafe {
    let f = f_item as fn(Int, *UInt8) -> Int32;
    let rc = f(t, slot.as_mut_ptr()) as Int;
    if rc != 0 {
      return Err(loader.lt_call_error(lib, rc, "torch_tensor_item_float32: aoti_torch_item_float32"));
    }
    return Ok(loader.lt_f32_from_bits(rd32(&slot)) as Float32);
  }
}

/// Wrap a scalar as a new single-element Float32 tensor.
/// Complexity: O(1).
pub fn torch_tensor_scalar(lib: &LtLibrary, v: Float32) -> Result[Int, LtError]
  requires: lib.handle != 0
{
  let f_sc = lib.f_scalar_to_tensor_f32;
  var slot = slot8();
  unsafe {
    let f = f_sc as fn(Float32, *UInt8) -> Int32;
    let rc = f(v, slot.as_mut_ptr()) as Int;
    if rc != 0 {
      return Err(loader.lt_call_error(lib, rc, "torch_tensor_scalar: aoti_torch_scalar_to_tensor_float32"));
    }
    return Ok(rd64(&slot));
  }
}

/// Runtime element size of a ScalarType code (e.g. 4 for Float32).
/// Complexity: O(1).
pub fn torch_dtype_size(lib: &LtLibrary, dtype: Int) -> Result[Int, LtError]
  requires: lib.handle != 0
{
  let f_sz = lib.f_dtype_element_size;
  unsafe {
    let f = f_sz as fn(Int32) -> Int;
    return Ok(f(dtype as Int32));
  }
}

/// The runtime Float32 ScalarType code of this build.
/// Complexity: O(1).
pub fn torch_dtype_float32(lib: &LtLibrary) -> Result[Int, LtError]
  requires: lib.handle != 0
{
  let f_d = lib.f_dtype_float32;
  unsafe {
    let f = f_d as fn() -> Int32;
    return Ok(f() as Int);
  }
}

/// The runtime CPU device-type code of this build.
/// Complexity: O(1).
pub fn torch_device_type_cpu(lib: &LtLibrary) -> Result[Int, LtError]
  requires: lib.handle != 0
{
  let f_d = lib.f_device_type_cpu;
  unsafe {
    let f = f_d as fn() -> Int32;
    return Ok(f() as Int);
  }
}

/// The runtime CUDA device-type code of this build (defined even on CPU
/// builds; availability is a separate query).
/// Complexity: O(1).
pub fn torch_device_type_cuda(lib: &LtLibrary) -> Result[Int, LtError]
  requires: lib.handle != 0
{
  let f_d = lib.f_device_type_cuda;
  unsafe {
    let f = f_d as fn() -> Int32;
    return Ok(f() as Int);
  }
}

// =========================================================================
// T 22-25 -- derived tensors
// =========================================================================

/// Clone a tensor (new owning handle; independent storage).
/// Complexity: O(numel).
pub fn torch_tensor_clone(lib: &LtLibrary, t: Int) -> Result[Int, LtError]
  requires: lib.handle != 0
  requires: t != 0
{
  let f_cl = lib.f_clone;
  var slot = slot8();
  unsafe {
    let f = f_cl as fn(Int, *UInt8) -> Int32;
    let rc = f(t, slot.as_mut_ptr()) as Int;
    if rc != 0 {
      return Err(loader.lt_call_error(lib, rc, "torch_tensor_clone: aoti_torch_clone"));
    }
    return Ok(rd64(&slot));
  }
}

/// Copy `src`'s contents into `dst` (dst must be shape-compatible; same
/// shape for an exact copy).
/// Complexity: O(numel).
pub fn torch_tensor_copy_into(lib: &LtLibrary, dst: Int, src: Int) -> Result[Unit, LtError]
  requires: lib.handle != 0
  requires: dst != 0
  requires: src != 0
{
  let f_cp = lib.f_tensor_copy;
  unsafe {
    let f = f_cp as fn(Int, Int) -> Int32;
    let rc = f(src, dst) as Int;
    return loader.lt_check(lib, rc, "torch_tensor_copy_into: aoti_torch_tensor_copy_");
  }
}

/// Reshape to a new shape (same element count).  Returns an owning handle
/// (may share storage, like ATen reshape; free it independently).
/// Complexity: O(1) when view-compatible, O(numel) otherwise.
pub fn torch_tensor_reshape(lib: &LtLibrary, t: Int, shape: &Vec[Int]) -> Result[Int, LtError]
  requires: lib.handle != 0
  requires: t != 0
  requires: shape.len() > 0
{
  let total = lt_numel(shape);
  let n_r = torch_tensor_numel(lib, t);
  if !n_r.is_ok { return Err(n_r.error); }
  if n_r.value != total {
    return Err(LtError{ kind: loader.LT_CALL_FAILED; message: "torch_tensor_reshape: element count mismatch" });
  }
  let f_rs = lib.f_cpu_reshape;
  var slot = slot8();
  unsafe {
    let f = f_rs as fn(Int, *Int, Int, *UInt8) -> Int32;
    let rc = f(t, &shape[0] as *Int, shape.len(), slot.as_mut_ptr()) as Int;
    if rc != 0 {
      return Err(loader.lt_call_error(lib, rc, "torch_tensor_reshape: aoti_torch_cpu_reshape"));
    }
    return Ok(rd64(&slot));
  }
}

/// Narrow dimension `dim` to the `[start, start+len)` slice (view; owning
/// handle per the AOTI contract).
/// Complexity: O(1).
pub fn torch_tensor_narrow(lib: &LtLibrary, t: Int, dim: Int, start: Int, len: Int) -> Result[Int, LtError]
  requires: lib.handle != 0
  requires: t != 0
  requires: dim >= 0
  requires: start >= 0
  requires: len > 0
{
  let f_nr = lib.f_cpu_narrow;
  var slot = slot8();
  unsafe {
    let f = f_nr as fn(Int, Int, Int, Int, *UInt8) -> Int32;
    let rc = f(t, dim, start, len, slot.as_mut_ptr()) as Int;
    if rc != 0 {
      return Err(loader.lt_call_error(lib, rc, "torch_tensor_narrow: aoti_torch_cpu_narrow"));
    }
    return Ok(rd64(&slot));
  }
}

// =========================================================================
// T 26-33 -- ops
// =========================================================================

/// Element-wise a + b (Float32; broadcasting per ATen).
/// Complexity: O(numel).
pub fn torch_tensor_add(lib: &LtLibrary, a: Int, b: Int) -> Result[Int, LtError]
  requires: lib.handle != 0
  requires: a != 0
  requires: b != 0
{
  let f_add = lib.f_cpu_add;
  var slot = slot8();
  unsafe {
    let f = f_add as fn(Int, Int, Float64, *UInt8) -> Int32;
    let rc = f(a, b, 1.0, slot.as_mut_ptr()) as Int;
    if rc != 0 {
      return Err(loader.lt_call_error(lib, rc, "torch_tensor_add: aoti_torch_cpu_add_Tensor"));
    }
    return Ok(rd64(&slot));
  }
}

/// Element-wise a * b.
/// Complexity: O(numel).
pub fn torch_tensor_mul(lib: &LtLibrary, a: Int, b: Int) -> Result[Int, LtError]
  requires: lib.handle != 0
  requires: a != 0
  requires: b != 0
{
  let f_mul = lib.f_cpu_mul;
  var slot = slot8();
  unsafe {
    let f = f_mul as fn(Int, Int, *UInt8) -> Int32;
    let rc = f(a, b, slot.as_mut_ptr()) as Int;
    if rc != 0 {
      return Err(loader.lt_call_error(lib, rc, "torch_tensor_mul: aoti_torch_cpu_mul_Tensor"));
    }
    return Ok(rd64(&slot));
  }
}

/// Scalar multiplication t * s.
/// Complexity: O(numel).
pub fn torch_tensor_scale(lib: &LtLibrary, t: Int, s: Float32) -> Result[Int, LtError]
  requires: lib.handle != 0
  requires: t != 0
{
  let f_ms = lib.f_cpu_mul_scalar;
  var slot = slot8();
  unsafe {
    let f = f_ms as fn(Int, Float64, *UInt8) -> Int32;
    let rc = f(t, s as Float64, slot.as_mut_ptr()) as Int;
    if rc != 0 {
      return Err(loader.lt_call_error(lib, rc, "torch_tensor_scale: aoti_torch_cpu_mul_Scalar"));
    }
    return Ok(rd64(&slot));
  }
}

/// 2-D matrix multiplication (a[M,K] @ b[K,N] -> [M,N]).
/// Complexity: O(M*K*N).
pub fn torch_tensor_matmul(lib: &LtLibrary, a: Int, b: Int) -> Result[Int, LtError]
  requires: lib.handle != 0
  requires: a != 0
  requires: b != 0
{
  let da_r = torch_tensor_dim(lib, a);
  if !da_r.is_ok { return Err(da_r.error); }
  let db_r = torch_tensor_dim(lib, b);
  if !db_r.is_ok { return Err(db_r.error); }
  if da_r.value != 2 || db_r.value != 2 {
    return Err(LtError{ kind: loader.LT_UNAVAILABLE; message: "torch_tensor_matmul: declared for 2-D tensors" });
  }
  let m_r = torch_tensor_size(lib, a, 0);
  if !m_r.is_ok { return Err(m_r.error); }
  let k_r = torch_tensor_size(lib, a, 1);
  if !k_r.is_ok { return Err(k_r.error); }
  let kb_r = torch_tensor_size(lib, b, 0);
  if !kb_r.is_ok { return Err(kb_r.error); }
  let n_r = torch_tensor_size(lib, b, 1);
  if !n_r.is_ok { return Err(n_r.error); }
  if k_r.value != kb_r.value {
    return Err(LtError{ kind: loader.LT_CALL_FAILED; message: "torch_tensor_matmul: inner dimensions do not match" });
  }
  var out_shape: Vec[Int] = Vec[Int].new();
  out_shape.push(m_r.value);
  out_shape.push(n_r.value);
  let out_r = torch_tensor_new(lib, &out_shape);
  if !out_r.is_ok { return Err(out_r.error); }
  let out = out_r.value;
  let f_mm = lib.f_cpu_mm_out;
  unsafe {
    let f = f_mm as fn(Int, Int, Int) -> Int32;
    let rc = f(out, a, b) as Int;
    if rc != 0 {
      let ig = torch_tensor_free(lib, out);
      return Err(loader.lt_call_error(lib, rc, "torch_tensor_matmul: aoti_torch_cpu_mm_out"));
    }
    return Ok(out);
  }
}

/// Element-wise ReLU through the boxed dispatcher (`aten::relu`).
///
/// Dispatcher handle semantics (verified against the pinned shim source):
/// `aoti_torch_call_dispatcher` converts each Tensor argument through
/// `to_ivalue`, which wraps the incoming handle in an
/// `RAIIAtenTensorHandle` -- the dispatcher CONSUMES (deletes) every input
/// handle it is given.  This wrapper therefore clones the input and
/// dispatches on the clone, so the caller's handle stays valid.  The
/// returned handle is a fresh owning reference (free with
/// torch_tensor_free).
/// Complexity: O(numel).
pub fn torch_tensor_relu(lib: &LtLibrary, t: Int) -> Result[Int, LtError]
  requires: lib.handle != 0
  requires: t != 0
{
  let c_r = torch_tensor_clone(lib, t);
  if !c_r.is_ok { return Err(c_r.error); }
  // From here on the clone belongs to the dispatcher (consumed on both the
  // success and the failure path: argument conversion runs first).
  let f_dp = lib.f_dispatcher;
  var stack: Vec[Int] = Vec[Int].new();
  stack.push(c_r.value);
  unsafe {
    let f = f_dp as fn(*UInt8, *UInt8, *Int) -> Int32;
    let rc = f("aten::relu".c_str(), "".c_str(), &stack[0] as *Int) as Int;
    if rc != 0 {
      return Err(loader.lt_call_error(lib, rc, "torch_tensor_relu: aoti_torch_call_dispatcher(aten::relu)"));
    }
    return Ok(stack[0]);
  }
}

/// Softmax along `dim` through the boxed dispatcher (`aten::softmax.int`;
/// the optional dtype argument crosses as the None sentinel 0, which is
/// `from(std::nullopt)` == `from(nullptr)` in the StableIValue encoding).
/// Dispatch runs on an internal clone -- see torch_tensor_relu for the
/// dispatcher-consumes-inputs semantics.
/// Complexity: O(numel).
pub fn torch_tensor_softmax(lib: &LtLibrary, t: Int, dim: Int) -> Result[Int, LtError]
  requires: lib.handle != 0
  requires: t != 0
  requires: dim >= 0
{
  let c_r = torch_tensor_clone(lib, t);
  if !c_r.is_ok { return Err(c_r.error); }
  let f_dp = lib.f_dispatcher;
  var stack: Vec[Int] = Vec[Int].new();
  stack.push(c_r.value);
  stack.push(dim);
  stack.push(0);
  unsafe {
    let f = f_dp as fn(*UInt8, *UInt8, *Int) -> Int32;
    let rc = f("aten::softmax".c_str(), "int".c_str(), &stack[0] as *Int) as Int;
    if rc != 0 {
      return Err(loader.lt_call_error(lib, rc, "torch_tensor_softmax: aoti_torch_call_dispatcher(aten::softmax)"));
    }
    return Ok(stack[0]);
  }
}

/// In-place fill with a scalar.
/// Complexity: O(numel).
pub fn torch_tensor_fill(lib: &LtLibrary, t: Int, v: Float32) -> Result[Unit, LtError]
  requires: lib.handle != 0
  requires: t != 0
{
  let f_fill = lib.f_fill_scalar;
  unsafe {
    let f = f_fill as fn(Int, Float64) -> Int32;
    let rc = f(t, v as Float64) as Int;
    return loader.lt_check(lib, rc, "torch_tensor_fill: aoti_torch_aten_fill__Scalar");
  }
}

/// In-place zero.
/// Complexity: O(numel).
pub fn torch_tensor_zero(lib: &LtLibrary, t: Int) -> Result[Unit, LtError]
  requires: lib.handle != 0
  requires: t != 0
{
  let f_zero = lib.f_zero;
  unsafe {
    let f = f_zero as fn(Int) -> Int32;
    let rc = f(t) as Int;
    return loader.lt_check(lib, rc, "torch_tensor_zero: aoti_torch_zero_");
  }
}

// =========================================================================
// T 34-36 -- training surface
// =========================================================================

/// One SGD step over a parameter tensor: returns `param + (-lr)*grad` as a
/// NEW owning handle (the caller keeps or frees the old param / grad).
/// Functional form: no hidden aliasing, no caller-handle invalidation.
/// Complexity: O(numel).
pub fn torch_sgd_step(lib: &LtLibrary, param: Int, grad: Int, lr: Float32) -> Result[Int, LtError]
  requires: lib.handle != 0
  requires: param != 0
  requires: grad != 0
  requires: lr > 0.0
{
  let scaled_r = torch_tensor_scale(lib, grad, 0.0 - lr);
  if !scaled_r.is_ok { return Err(scaled_r.error); }
  let scaled = scaled_r.value;
  let updated_r = torch_tensor_add(lib, param, scaled);
  let ig = torch_tensor_free(lib, scaled);
  if !updated_r.is_ok { return Err(updated_r.error); }
  return Ok(updated_r.value);
}

/// Is grad mode (autograd recording) enabled in the runtime?
/// Complexity: O(1).
pub fn torch_grad_mode_enabled(lib: &LtLibrary) -> Result[Bool, LtError]
  requires: lib.handle != 0
{
  let f_g = lib.f_grad_enabled;
  unsafe {
    let f = f_g as fn() -> UInt8;
    return Ok((f() as Int) != 0);
  }
}

/// Set grad mode (autograd recording) in the runtime.
/// Complexity: O(1).
pub fn torch_set_grad_mode(lib: &LtLibrary, enabled: Bool) -> Result[Unit, LtError]
  requires: lib.handle != 0
{
  let f_s = lib.f_grad_set;
  unsafe {
    let f = f_s as fn(Int) -> Unit;
    if enabled {
      f(1);
    } else {
      f(0);
    }
    return Ok(());
  }
}

// =========================================================================
// T 37-40 -- GPU + C++ anchors
// =========================================================================

/// torch::cuda::is_available() through the pinned C++ anchor (bool return
/// -- a trivial-ABI anchor; live-proven false on the CPU build).
/// Complexity: O(1).
pub fn torch_cuda_is_available(lib: &LtLibrary) -> Result[Bool, LtError]
  requires: lib.handle != 0
  requires: lib.p_cuda_available != 0
{
  let p = lib.p_cuda_available;
  unsafe {
    let f = p as fn() -> UInt8;
    return Ok((f() as Int) != 0);
  }
}

/// torch::cuda::device_count() through the pinned C++ anchor (int8
/// return; 0 on a CPU build).
/// Complexity: O(1).
pub fn torch_cuda_device_count(lib: &LtLibrary) -> Result[Int, LtError]
  requires: lib.handle != 0
  requires: lib.p_cuda_device_count != 0
{
  let p = lib.p_cuda_device_count;
  unsafe {
    let f = p as fn() -> UInt8;
    return Ok(f() as Int);
  }
}

/// Is the pinned torch::jit::load C++ anchor present in this build?  (The
/// anchor is resolved by the loader; calling it needs a TorchScript
/// artifact + the std::string/optional ABI shim -- ROADMAP phase 2.)
/// Complexity: O(1).
pub fn torch_jit_anchor_present(lib: &LtLibrary) -> Bool
  requires: lib.handle != 0
{
  return lib.p_jit_load != 0;
}
