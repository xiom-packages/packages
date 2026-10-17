// XIOM -- xiom.torch.runtime: libtorch runtime tier for the tensor-level
// surface (multi-soname loader over the AOTInductor C ABI).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Same design decision as xiom.libtorch (system-library path, not
// vendored): the libtorch AOTInductor C shim -- a stable C ABI by
// construction ("This header defines a stable C API ... MUST MAINTAIN ABI
// compatibility", torch/csrc/inductor/aoti_torch/c/shim.h) -- is reached
// through the multi-soname loader.  This tier binds the declared subset
// the tensor-level surface needs to move data between a xiom.torch.Tensor
// (pure XIOM, no runtime required) and a libtorch build.  Nothing is
// compiled in, nothing is linked at build time; no candidate present ->
// TORCH_LOAD_ABSENT (typed SKIP), so CI without libtorch stays green.
//
// Module name note: this module deliberately does NOT carry the historical
// `xiom.torch.ffi` name -- a module whose last segment is `ffi` cannot
// import the stdlib `xiom.ffi` module on the pinned toolchain (B-07,
// BINDINGS-COMPILER-FINDINGS); the tier was renamed at the 0.1.0 landing.
//
// Classification:
//   TORCH_LOAD_ABSENT -> no candidate soname loaded            -> SKIP
//   TORCH_LOAD_ABI    -> candidate loaded, surface unusable    -> FAIL
//   TORCH_CALL_FAILED -> an aoti_torch_* call returned nonzero -> typed error

module xiom.torch.runtime

use xiom.torch.types;
use xiom.ffi.dl;
use xiom.ffi;
use xiom.io;

// =========================================================================
// Classification
// =========================================================================

pub const TORCH_LOAD_ABSENT: Int = 0;
pub const TORCH_LOAD_ABI: Int = 1;
pub const TORCH_CALL_FAILED: Int = 2;

/// Declared ABI floor (pinned build line; TORCH_ABI_VERSION layout
/// MAJOR<<56 | MINOR<<48 | PATCH<<40).
pub const TORCH_MIN_MAJOR: Int = 2;
pub const TORCH_MIN_MINOR: Int = 9;

// =========================================================================
// Types
// =========================================================================

/// A typed runtime failure.
pub type TorchError = {
  kind: Int;
  message: Str;
}

/// Identity + declared-surface counts of a loaded build.
pub type TorchRuntimeInfo = {
  soname: Str;
  abi_version: Int;
  major: Int;
  minor: Int;
  patch: Int;
  resolved: Int;
  required: Int;
}

/// One loaded libtorch and its resolved entry points.  Owned by the
/// caller; release with `torch_runtime_close`.
pub type TorchRuntime = {
  handle: Int;
  soname: Str;
  abi_version: Int;
  major: Int;
  minor: Int;
  patch: Int;
  resolved: Int;
  required: Int;
  f_abi_version: Int;
  f_dtype_float32: Int;
  f_device_type_cpu: Int;
  f_layout_strided: Int;
  f_empty_strided: Int;
  f_delete_tensor: Int;
  f_from_blob_v2: Int;
  f_tensor_copy: Int;
  f_get_data_ptr: Int;
  f_get_numel: Int;
  f_get_dim: Int;
  f_get_size: Int;
  f_is_contiguous: Int;
  p_cuda_available: Int;
}

// =========================================================================
// Declared surface (the coverage-table oracle)
// =========================================================================

/// The declared C entry points (13), in resolution order.  SPEC.md's
/// coverage table mirrors this list 1:1.
/// Complexity: O(n).
pub fn torch_runtime_surface_names() -> Vec[Str]
  requires: true
{
  var v: Vec[Str] = Vec[Str].new();
  v.push("aoti_torch_abi_version");
  v.push("aoti_torch_dtype_float32");
  v.push("aoti_torch_device_type_cpu");
  v.push("aoti_torch_layout_strided");
  v.push("aoti_torch_empty_strided");
  v.push("aoti_torch_delete_tensor_object");
  v.push("aoti_torch_create_tensor_from_blob_v2");
  v.push("aoti_torch_tensor_copy_");
  v.push("aoti_torch_get_data_ptr");
  v.push("aoti_torch_get_numel");
  v.push("aoti_torch_get_dim");
  v.push("aoti_torch_get_size");
  v.push("aoti_torch_is_contiguous");
  return v;
}

/// The declared C++ anchor (1): torch::cuda::is_available.
/// Complexity: O(n).
pub fn torch_runtime_anchor_names() -> Vec[Str]
  requires: true
{
  var v: Vec[Str] = Vec[Str].new();
  v.push("?is_available@cuda@torch@@YA_NXZ");
  return v;
}

// =========================================================================
// Local helpers (lane pattern: confined modules carry their own)
// =========================================================================

/// Local Int-to-Str (lane pattern; avoids cross-module convert traps).
/// Complexity: O(digits).
pub fn int_to_str(n: Int) -> Str
  requires: true
{
  if n == 0 { return "0"; }
  var num = n;
  var neg = false;
  if num < 0 { neg = true; num = 0 - num; }
  var out = "";
  while num > 0 {
    let d = num % 10;
    var ds = "0";
    if d == 1 { ds = "1"; }
    elif d == 2 { ds = "2"; }
    elif d == 3 { ds = "3"; }
    elif d == 4 { ds = "4"; }
    elif d == 5 { ds = "5"; }
    elif d == 6 { ds = "6"; }
    elif d == 7 { ds = "7"; }
    elif d == 8 { ds = "8"; }
    elif d == 9 { ds = "9"; }
    out = ds + out;
    num = num / 10;
  }
  if neg { return "-" + out; }
  return out;
}

/// IEEE-754 binary32 bits -> Float64 (pure arithmetic; B-12-safe).
/// Complexity: O(1).
pub fn torch_f32_from_bits(bits: Int) -> Float64
  requires: bits >= 0
  requires: bits <= 0xFFFFFFFF
{
  let sign = if ((bits >> 31) & 1) == 1 { -1.0 } else { 1.0 };
  let exp = (bits >> 23) & 0xFF;
  let frac = bits & 0x7FFFFF;
  if exp == 0 {
    if frac == 0 { return sign * 0.0; }
    return sign * (frac as Float64) * torch_pow2i(-149);
  }
  if exp == 255 { return 0.0; }
  return sign * (1.0 + (frac as Float64) / 8388608.0) * torch_pow2i(exp - 127);
}

fn torch_pow2i(e: Int) -> Float64
  requires: e >= -1074
  requires: e <= 1024
{
  var r = 1.0;
  var i = e;
  while i > 0 {
    r = r * 2.0;
    i = i - 1;
  }
  while i < 0 {
    r = r / 2.0;
    i = i + 1;
  }
  return r;
}

/// Typed call failure carrying the aoti error code (nonzero).
/// Complexity: O(len).
pub fn torch_call_error(rt: &TorchRuntime, code: Int, context: Str) -> TorchError
  requires: code != 0
  requires: context.len() > 0
{
  return TorchError{
    kind: TORCH_CALL_FAILED;
    message: context + " [aoti rc " + int_to_str(code) + " on " + rt.soname + "]",
  };
}

// =========================================================================
// Loader
// =========================================================================

fn fail_load(handle: Int, message: Str) -> Result[TorchRuntime, TorchError]
  requires: handle != 0
  requires: message.len() > 0
{
  var ig = dl.dl_close(handle);
  return Err(TorchError{ kind: TORCH_LOAD_ABI; message: message });
}

fn sym_or(handle: Int, name: Str) -> Result[Int, Str]
  requires: handle != 0
  requires: name.len() > 0
{
  let a = dl.dl_sym(handle, name);
  if !a.is_ok { return Err(name + ": " + a.error); }
  return Ok(a.value);
}

fn try_load(soname: Str) -> Result[TorchRuntime, TorchError]
  requires: soname.len() > 0
{
  let h = dl.dl_open(soname);
  if !h.is_ok {
    return Err(TorchError{ kind: TORCH_LOAD_ABSENT; message: soname + ": " + h.error });
  }
  let handle: Int = h.value;

  let s01 = sym_or(handle, "aoti_torch_abi_version");
  if !s01.is_ok { return fail_load(handle, soname + ": " + s01.error); }
  let s02 = sym_or(handle, "aoti_torch_dtype_float32");
  if !s02.is_ok { return fail_load(handle, soname + ": " + s02.error); }
  let s03 = sym_or(handle, "aoti_torch_device_type_cpu");
  if !s03.is_ok { return fail_load(handle, soname + ": " + s03.error); }
  let s04 = sym_or(handle, "aoti_torch_layout_strided");
  if !s04.is_ok { return fail_load(handle, soname + ": " + s04.error); }
  let s05 = sym_or(handle, "aoti_torch_empty_strided");
  if !s05.is_ok { return fail_load(handle, soname + ": " + s05.error); }
  let s06 = sym_or(handle, "aoti_torch_delete_tensor_object");
  if !s06.is_ok { return fail_load(handle, soname + ": " + s06.error); }
  let s07 = sym_or(handle, "aoti_torch_create_tensor_from_blob_v2");
  if !s07.is_ok { return fail_load(handle, soname + ": " + s07.error); }
  let s08 = sym_or(handle, "aoti_torch_tensor_copy_");
  if !s08.is_ok { return fail_load(handle, soname + ": " + s08.error); }
  let s09 = sym_or(handle, "aoti_torch_get_data_ptr");
  if !s09.is_ok { return fail_load(handle, soname + ": " + s09.error); }
  let s10 = sym_or(handle, "aoti_torch_get_numel");
  if !s10.is_ok { return fail_load(handle, soname + ": " + s10.error); }
  let s11 = sym_or(handle, "aoti_torch_get_dim");
  if !s11.is_ok { return fail_load(handle, soname + ": " + s11.error); }
  let s12 = sym_or(handle, "aoti_torch_get_size");
  if !s12.is_ok { return fail_load(handle, soname + ": " + s12.error); }
  let s13 = sym_or(handle, "aoti_torch_is_contiguous");
  if !s13.is_ok { return fail_load(handle, soname + ": " + s13.error); }

  // C++ anchor: torch::cuda::is_available (trivial bool ABI).
  let a1 = sym_or(handle, "?is_available@cuda@torch@@YA_NXZ");
  if !a1.is_ok { return fail_load(handle, soname + ": " + a1.error); }

  // Version probe (TORCH_ABI_VERSION decode + declared floor).
  let av_fp = s01.value;
  let av = unsafe { av_fp as fn() -> Int };
  let abi = av();
  let major = (abi >> 56) & 255;
  let minor = (abi >> 48) & 255;
  let patch = (abi >> 40) & 255;
  if abi == 0 {
    return fail_load(handle, soname + ": aoti_torch_abi_version returned 0");
  }
  if major < TORCH_MIN_MAJOR {
    return fail_load(handle, soname + ": libtorch " + int_to_str(major) + "." + int_to_str(minor) +
      " is older than the declared " + int_to_str(TORCH_MIN_MAJOR) + "." + int_to_str(TORCH_MIN_MINOR) + " ABI floor");
  }
  if major == TORCH_MIN_MAJOR && minor < TORCH_MIN_MINOR {
    return fail_load(handle, soname + ": libtorch " + int_to_str(major) + "." + int_to_str(minor) +
      " is older than the declared " + int_to_str(TORCH_MIN_MAJOR) + "." + int_to_str(TORCH_MIN_MINOR) + " ABI floor");
  }

  return Ok(TorchRuntime{
    handle: handle;
    soname: soname;
    abi_version: abi;
    major: major;
    minor: minor;
    patch: patch;
    resolved: 13;
    required: 13;
    f_abi_version: s01.value;
    f_dtype_float32: s02.value;
    f_device_type_cpu: s03.value;
    f_layout_strided: s04.value;
    f_empty_strided: s05.value;
    f_delete_tensor: s06.value;
    f_from_blob_v2: s07.value;
    f_tensor_copy: s08.value;
    f_get_data_ptr: s09.value;
    f_get_numel: s10.value;
    f_get_dim: s11.value;
    f_get_size: s12.value;
    f_is_contiguous: s13.value;
    p_cuda_available: a1.value;
  });
}

/// The multi-soname candidate list, in probe order (`XIOM_LIBTORCH_RUNTIME`
/// override first, then the Windows/Linux/macOS sonames).
/// Complexity: O(1).
pub fn torch_runtime_candidates() -> Vec[Str]
  requires: true
{
  var v: Vec[Str] = Vec[Str].new();
  let override = io.env_var("XIOM_LIBTORCH_RUNTIME");
  if override.is_some {
    if override.value.len() > 0 {
      v.push(override.value);
    }
  }
  v.push("torch_cpu.dll");
  v.push("libtorch_cpu.dll");
  v.push("libtorch.dll");
  v.push("torch.dll");
  v.push("libtorch_cpu.so");
  v.push("libtorch.so");
  v.push("libtorch_cpu.so.2");
  v.push("libtorch.so.2");
  v.push("libtorch_cpu.dylib");
  v.push("libtorch.dylib");
  return v;
}

/// Open the first usable candidate.  No candidate present ->
/// TORCH_LOAD_ABSENT (typed SKIP); a candidate that loads but fails the
/// surface/version check keeps its ABI error while later candidates are
/// tried.
/// Complexity: O(candidates * surface).
pub fn torch_runtime_open() -> Result[TorchRuntime, TorchError]
  requires: true
{
  let cands = torch_runtime_candidates();
  var abi: TorchError = TorchError{ kind: TORCH_LOAD_ABSENT; message: "" };
  var i = 0;
  while i < cands.len() {
    let r = try_load(cands[i]);
    if r.is_ok {
      return Ok(r.value);
    }
    if r.error.kind == TORCH_LOAD_ABI {
      abi = r.error;
    }
    i = i + 1;
  };
  if abi.message.len() > 0 {
    return Err(abi);
  }
  return Err(TorchError{
    kind: TORCH_LOAD_ABSENT;
    message: "torch: no runtime candidate loaded (tried " + int_to_str(cands.len()) +
      " candidates: XIOM_LIBTORCH_RUNTIME, torch_cpu.dll, libtorch_cpu.dll, libtorch.dll, torch.dll, libtorch_cpu.so, libtorch.so, libtorch_cpu.so.2, libtorch.so.2, libtorch_cpu.dylib, libtorch.dylib)",
  });
}

/// Open an explicitly named build (path or soname; bogus names exercise
/// the ABSENT/SKIP classification deterministically on any host).
/// Complexity: O(load + surface check).
pub fn torch_runtime_open_named(soname: Str) -> Result[TorchRuntime, TorchError]
  requires: soname.len() > 0
{
  return try_load(soname);
}

/// Version + declared-surface counts of a loaded build.
/// Complexity: O(1).
pub fn torch_runtime_info(rt: &TorchRuntime) -> TorchRuntimeInfo
  requires: rt.handle != 0
{
  return TorchRuntimeInfo{
    soname: rt.soname;
    abi_version: rt.abi_version;
    major: rt.major;
    minor: rt.minor;
    patch: rt.patch;
    resolved: rt.resolved;
    required: rt.required;
  };
}

/// Release the runtime handle.
/// Complexity: O(1).
pub fn torch_runtime_close(rt: &TorchRuntime) -> Result[Unit, Str]
  requires: rt.handle != 0
{
  return dl.dl_close(rt.handle);
}

/// torch::cuda::is_available() through the pinned C++ anchor.
/// Complexity: O(1).
pub fn torch_cuda_available(rt: &TorchRuntime) -> Result[Bool, TorchError]
  requires: rt.handle != 0
  requires: rt.p_cuda_available != 0
{
  let p = rt.p_cuda_available;
  unsafe {
    let f = p as fn() -> UInt8;
    return Ok((f() as Int) != 0);
  }
}

// =========================================================================
// Tensor bridge (xiom.torch.Tensor <-> libtorch AtenTensorHandle)
// =========================================================================

fn row_major_strides(shape: &Vec[Int]) -> Vec[Int]
  requires: shape.len() > 0
{
  var ndim = shape.len();
  var strides: Vec[Int] = Vec[Int].new();
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

/// Upload a xiom.torch.Tensor into the runtime (a new owning libtorch
/// tensor handle; the data is copied, the XIOM tensor is never aliased).
/// Only Float32 CPU tensors are uploadable at 0.1.0.
/// Complexity: O(numel).
pub fn torch_upload(rt: &TorchRuntime, t: &Tensor) -> Result[Int, TorchError]
  requires: rt.handle != 0
  requires: t.shape.len() > 0
  requires: t.data.len() > 0
{
  if t.dtype != DType.Float32 {
    return Err(TorchError{ kind: TORCH_LOAD_ABI; message: "torch_upload: declared for Float32 tensors" });
  }
  if t.data.len() != torch_numel(&t.shape) {
    return Err(TorchError{ kind: TORCH_CALL_FAILED; message: "torch_upload: data length does not match the shape product" });
  }
  let ndim = t.shape.len();
  let strides = row_major_strides(&t.shape);
  let f_dtype = rt.f_dtype_float32;
  let f_dev = rt.f_device_type_cpu;
  let f_layout = rt.f_layout_strided;
  let f_new = rt.f_empty_strided;
  let f_blob = rt.f_from_blob_v2;
  let f_copy = rt.f_tensor_copy;
  let f_del = rt.f_delete_tensor;
  var dst_slot = Vec[UInt8].with_len(8);
  var src_slot = Vec[UInt8].with_len(8);
  unsafe {
    let fd = f_dtype as fn() -> Int32;
    let dtype = fd() as Int;
    let fv = f_dev as fn() -> Int32;
    let dev = fv() as Int;
    let fl = f_layout as fn() -> Int32;
    let layout = fl() as Int;
    let fnew = f_new as fn(Int, *Int, *Int, Int32, Int32, Int32, *UInt8) -> Int32;
    let rc = fnew(ndim, &t.shape[0] as *Int, &strides[0] as *Int,
                  dtype as Int32, dev as Int32, 0, dst_slot.as_mut_ptr()) as Int;
    if rc != 0 {
      return Err(torch_call_error(rt, rc, "torch_upload: aoti_torch_empty_strided"));
    }
    let dst = ffi.ptr_read_u64_le(dst_slot.as_mut_ptr());
    let fb = f_blob as fn(*Float32, Int, *Int, *Int, Int, Int32, Int32, Int32, *UInt8, Int32, *UInt8, Int) -> Int32;
    let rc2 = fb(&t.data[0] as *Float32, ndim, &t.shape[0] as *Int, &strides[0] as *Int,
                 0, dtype as Int32, dev as Int32, 0, src_slot.as_mut_ptr(),
                 layout as Int32, 0 as *UInt8, 0) as Int;
    if rc2 != 0 {
      let fdel0 = f_del as fn(Int) -> Int32;
      let ig = fdel0(dst) as Int;
      return Err(torch_call_error(rt, rc2, "torch_upload: aoti_torch_create_tensor_from_blob_v2"));
    }
    let src = ffi.ptr_read_u64_le(src_slot.as_mut_ptr());
    let fc = f_copy as fn(Int, Int) -> Int32;
    let rc3 = fc(src, dst) as Int;
    let fdel = f_del as fn(Int) -> Int32;
    let ig2 = fdel(src) as Int;
    if rc3 != 0 {
      let ig3 = fdel(dst) as Int;
      return Err(torch_call_error(rt, rc3, "torch_upload: aoti_torch_tensor_copy_"));
    }
    return Ok(dst);
  }
}

fn torch_numel(shape: &Vec[Int]) -> Int
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

/// Download a runtime tensor into an owned xiom.torch.Tensor (Float32
/// CPU; requires a contiguous tensor).  The runtime handle stays valid.
/// Complexity: O(numel).
pub fn torch_download(rt: &TorchRuntime, handle: Int, name: Str) -> Result[Tensor, TorchError]
  requires: rt.handle != 0
  requires: handle != 0
{
  let f_cont = rt.f_is_contiguous;
  var cont_slot = Vec[UInt8].with_len(1);
  unsafe {
    let fc = f_cont as fn(Int, *UInt8) -> Int32;
    let rcc = fc(handle, cont_slot.as_mut_ptr()) as Int;
    if rcc != 0 {
      return Err(torch_call_error(rt, rcc, "torch_download: aoti_torch_is_contiguous"));
    }
    if ffi.ptr_read_u8(cont_slot.as_mut_ptr()) == 0 {
      return Err(TorchError{ kind: TORCH_CALL_FAILED; message: "torch_download: tensor is not contiguous" });
    }
  }
  let f_n = rt.f_get_numel;
  var n_slot = Vec[UInt8].with_len(8);
  let f_d = rt.f_get_dim;
  var d_slot = Vec[UInt8].with_len(8);
  var n = 0;
  var ndim = 0;
  unsafe {
    let fn1 = f_n as fn(Int, *UInt8) -> Int32;
    let rc1 = fn1(handle, n_slot.as_mut_ptr()) as Int;
    if rc1 != 0 {
      return Err(torch_call_error(rt, rc1, "torch_download: aoti_torch_get_numel"));
    }
    n = ffi.ptr_read_u64_le(n_slot.as_mut_ptr());
    let fd = f_d as fn(Int, *UInt8) -> Int32;
    let rc2 = fd(handle, d_slot.as_mut_ptr()) as Int;
    if rc2 != 0 {
      return Err(torch_call_error(rt, rc2, "torch_download: aoti_torch_get_dim"));
    }
    ndim = ffi.ptr_read_u64_le(d_slot.as_mut_ptr());
  }
  var shape: Vec[Int] = Vec[Int].new();
  var i = 0;
  while i < ndim {
    let sz_r = torch_tensor_size_of(rt, handle, i);
    if !sz_r.is_ok { return Err(sz_r.error); }
    shape.push(sz_r.value);
    i = i + 1;
  };
  let f_p = rt.f_get_data_ptr;
  var p_slot = Vec[UInt8].with_len(8);
  var addr = 0;
  unsafe {
    let fp = f_p as fn(Int, *UInt8) -> Int32;
    let rc3 = fp(handle, p_slot.as_mut_ptr()) as Int;
    if rc3 != 0 {
      return Err(torch_call_error(rt, rc3, "torch_download: aoti_torch_get_data_ptr"));
    }
    addr = ffi.ptr_read_u64_le(p_slot.as_mut_ptr());
  }
  var data: Vec[Float32] = Vec[Float32].new();
  unsafe {
    var j = 0;
    while j < n {
      let bits = ffi.ptr_read_u32_le((addr + j * 4) as *UInt8);
      data.push(torch_f32_from_bits(bits) as Float32);
      j = j + 1;
    };
  };
  return Ok(Tensor{
    data: data;
    shape: shape;
    strides: row_major_strides(&shape);
    device: Device.CPU;
    dtype: DType.Float32;
  });
}

fn torch_tensor_size_of(rt: &TorchRuntime, handle: Int, d: Int) -> Result[Int, TorchError]
  requires: rt.handle != 0
  requires: handle != 0
  requires: d >= 0
{
  let f_s = rt.f_get_size;
  var slot = Vec[UInt8].with_len(8);
  unsafe {
    let f = f_s as fn(Int, Int, *UInt8) -> Int32;
    let rc = f(handle, d, slot.as_mut_ptr()) as Int;
    if rc != 0 {
      return Err(torch_call_error(rt, rc, "torch_download: aoti_torch_get_size"));
    }
    return Ok(ffi.ptr_read_u64_le(slot.as_mut_ptr()));
  }
}

/// Release a runtime tensor handle created by `torch_upload`.
/// Complexity: O(1).
pub fn torch_release(rt: &TorchRuntime, handle: Int) -> Result[Unit, TorchError]
  requires: rt.handle != 0
  requires: handle != 0
{
  let f_del = rt.f_delete_tensor;
  unsafe {
    let f = f_del as fn(Int) -> Int32;
    let rc = f(handle) as Int;
    if rc != 0 {
      return Err(torch_call_error(rt, rc, "torch_release: aoti_torch_delete_tensor_object"));
    }
    return Ok(());
  }
}
