// XIOM -- xiom.libtorch.loader: multi-soname libtorch loader over xiom.ffi.dl.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// DESIGN DECISION (ML/AI sector): **system-library path, not vendored** --
// libtorch (the PyTorch C++ distribution) ships a stable C ABI for its
// AOTInductor runtime: the `aoti_torch_*` shim declared in
// torch/csrc/inductor/aoti_torch/c/shim.h ("This header defines a stable C
// API ... MUST MAINTAIN ABI compatibility"). That C surface -- tensor
// lifecycle, metadata, allocator-owned and borrowed-buffer tensors, the
// dispatcher entry point, device guard/stream helpers -- plus a small set
// of pinned C++ mangled anchors (torch::cuda::is_available,
// torch::cuda::device_count, torch::jit::load) is what this loader binds.
// Nothing is compiled into this package and nothing is linked at build
// time; the loader probes common sonames in order and the suite reports
// SKIP when none is present, so CI without libtorch stays green.
//
// The AOTI shim is *designed* for cross-version stability (no exceptions,
// only ints/floats/pointers in headers, append-only evolution via _v2
// variants), which makes it the right loader surface for a binding that
// must survive libtorch upgrades. The C++ anchors are mangled names pinned
// to the declared build line (2.9, MSVC x64); they are resolved, and the
// two trivial-ABI ones (bool / int8 returns) are called live.
//
// Call discipline (bindings compiler findings): floating-point returns
// through cast calls are miscompiled (B-12), so every entry point here
// returns int/int32/uint64 only; all float payloads cross via out-params
// (4-byte / 8-byte XIOM-owned slots) and are rebuilt with the
// f32_from_bits arithmetic pattern. Raw pointer arithmetic on owned buffers
// is avoided (B-17/B-20); foreign pointer-derived addresses use Int-typed
// address math `(addr + n) as *UInt8`, read back through the ffi helpers.
//
// Classification:
//   LT_LOAD_ABSENT -> no candidate soname loaded            -> SKIP
//   LT_LOAD_ABI    -> candidate loaded, surface unusable    -> FAIL
//   LT_CALL_FAILED -> an aoti_torch_* call returned nonzero -> typed error
//   LT_UNAVAILABLE -> a declared capability is not present on this build
//
// Declared loader surface (2 tiers; SPEC.md mirrors this 1:1):
//   C tier   (38 aoti_torch_* entry points, resolved by name)
//   C++ tier (3 pinned mangled anchors, resolved by name; 2 called live)
//
// Version probe: `aoti_torch_abi_version()` returns TORCH_ABI_VERSION =
// MAJOR<<56 | MINOR<<48 | PATCH<<40 | ABI_TAG (torch/version.h.in); the
// loader decodes and reports it, and enforces the declared floor (2.9).

module xiom.libtorch.loader

use xiom.ffi.dl;
use xiom.ffi;
use xiom.io;

// =========================================================================
// Classification and error kinds
// =========================================================================

pub const LT_LOAD_ABSENT: Int = 0;   // no candidate loaded -> SKIP
pub const LT_LOAD_ABI: Int = 1;      // candidate loaded, surface unusable -> FAIL
pub const LT_CALL_FAILED: Int = 2;   // an aoti_torch_* call returned nonzero
pub const LT_UNAVAILABLE: Int = 3;   // capability not present on this build

/// Declared ABI floor (the pinned build line the surface was transcribed
/// from; torch/version.h.in TORCH_ABI_VERSION layout).
pub const LT_MIN_MAJOR: Int = 2;
pub const LT_MIN_MINOR: Int = 9;

// =========================================================================
// Types
// =========================================================================

/// A typed loader failure: classification or operational error.
pub type LtError = {
  kind: Int;
  message: Str;
}

/// Identity + declared-surface counts of a loaded build.  `resolved` /
/// `anchors_resolved` equal the required counts on any build this loader
/// accepts (the check is fail-closed), and are carried for the probe
/// report and the suite assertions.
pub type LtInfo = {
  soname: Str;
  abi_version: Int;
  major: Int;
  minor: Int;
  patch: Int;
  resolved: Int;
  required: Int;
  anchors_resolved: Int;
  anchors_required: Int;
}

/// One loaded libtorch and its resolved entry points.  Owned by the
/// caller; release with `lt_close`.
pub type LtLibrary = {
  handle: Int;
  soname: Str;
  abi_version: Int;
  major: Int;
  minor: Int;
  patch: Int;
  resolved: Int;
  required: Int;
  anchors_resolved: Int;
  anchors_required: Int;
  // C tier -- constants / probe (6)
  f_abi_version: Int;
  f_dtype_float32: Int;
  f_dtype_element_size: Int;
  f_device_type_cpu: Int;
  f_device_type_cuda: Int;
  f_layout_strided: Int;
  // C tier -- tensor lifecycle (6)
  f_empty_strided: Int;
  f_delete_tensor: Int;
  f_from_blob_v2: Int;
  f_tensor_copy: Int;
  f_clone: Int;
  f_new_handle: Int;
  // C tier -- metadata (13)
  f_get_data_ptr: Int;
  f_get_numel: Int;
  f_get_dim: Int;
  f_get_sizes: Int;
  f_get_strides: Int;
  f_get_size: Int;
  f_get_stride: Int;
  f_get_dtype: Int;
  f_get_device_type: Int;
  f_get_device_index: Int;
  f_get_storage_offset: Int;
  f_is_contiguous: Int;
  f_is_defined: Int;
  // C tier -- scalars (2)
  f_item_f32: Int;
  f_scalar_to_tensor_f32: Int;
  // C tier -- ops (6)
  f_cpu_add: Int;
  f_cpu_mul: Int;
  f_cpu_mul_scalar: Int;
  f_cpu_mm_out: Int;
  f_cpu_reshape: Int;
  f_cpu_narrow: Int;
  // C tier -- in-place / dispatcher / grad (5)
  f_fill_scalar: Int;
  f_zero: Int;
  f_dispatcher: Int;
  f_grad_enabled: Int;
  f_grad_set: Int;
  // C++ tier -- anchors (3)
  p_cuda_available: Int;
  p_cuda_device_count: Int;
  p_jit_load: Int;
}

// =========================================================================
// Declared surface (the coverage-table oracle)
// =========================================================================

/// The declared C entry points, in resolution order (38).  SPEC.md's
/// coverage table mirrors this list 1:1.
/// Complexity: O(n).
pub fn lt_surface_names() -> Vec[Str]
  requires: true
{
  var v: Vec[Str] = Vec[Str].new();
  v.push("aoti_torch_abi_version");
  v.push("aoti_torch_dtype_float32");
  v.push("aoti_torch_dtype_element_size");
  v.push("aoti_torch_device_type_cpu");
  v.push("aoti_torch_device_type_cuda");
  v.push("aoti_torch_layout_strided");
  v.push("aoti_torch_empty_strided");
  v.push("aoti_torch_delete_tensor_object");
  v.push("aoti_torch_create_tensor_from_blob_v2");
  v.push("aoti_torch_tensor_copy_");
  v.push("aoti_torch_clone");
  v.push("aoti_torch_new_tensor_handle");
  v.push("aoti_torch_get_data_ptr");
  v.push("aoti_torch_get_numel");
  v.push("aoti_torch_get_dim");
  v.push("aoti_torch_get_sizes");
  v.push("aoti_torch_get_strides");
  v.push("aoti_torch_get_size");
  v.push("aoti_torch_get_stride");
  v.push("aoti_torch_get_dtype");
  v.push("aoti_torch_get_device_type");
  v.push("aoti_torch_get_device_index");
  v.push("aoti_torch_get_storage_offset");
  v.push("aoti_torch_is_contiguous");
  v.push("aoti_torch_is_defined");
  v.push("aoti_torch_item_float32");
  v.push("aoti_torch_scalar_to_tensor_float32");
  v.push("aoti_torch_cpu_add_Tensor");
  v.push("aoti_torch_cpu_mul_Tensor");
  v.push("aoti_torch_cpu_mul_Scalar");
  v.push("aoti_torch_cpu_mm_out");
  v.push("aoti_torch_cpu_reshape");
  v.push("aoti_torch_cpu_narrow");
  v.push("aoti_torch_aten_fill__Scalar");
  v.push("aoti_torch_zero_");
  v.push("aoti_torch_call_dispatcher");
  v.push("aoti_torch_grad_mode_is_enabled");
  v.push("aoti_torch_grad_mode_set_enabled");
  return v;
}

/// The declared C++ mangled anchors (3).  Pinned to the declared build
/// line (2.9, MSVC x64); verified byte-exact against the official release
/// build's export table (PROVENANCE.md).
/// Complexity: O(n).
pub fn lt_anchor_names() -> Vec[Str]
  requires: true
{
  var v: Vec[Str] = Vec[Str].new();
  v.push("?is_available@cuda@torch@@YA_NXZ");
  v.push("?device_count@cuda@torch@@YACXZ");
  v.push("?load@jit@torch@@YA?AUModule@12@AEBV?$basic_string@DU?$char_traits@D@std@@V?$allocator@D@2@@std@@V?$optional@UDevice@c10@@@5@_N@Z");
  return v;
}

// =========================================================================
// Local helpers (lane pattern: confined modules carry their own)
// =========================================================================

/// Local Int-to-Str (lane pattern, BINDINGS-COMPILER-FINDINGS: avoids
/// cross-module convert resolution traps inside confined modules).
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

/// IEEE-754 binary32 bits -> Float64 (pure arithmetic; the xiom.assimp /
/// xiom.android pattern -- avoids B-12 miscompiled fp cast-call returns).
/// Complexity: O(1).
pub fn lt_f32_from_bits(bits: Int) -> Float64
  requires: bits >= 0
  requires: bits <= 0xFFFFFFFF
{
  let sign = if ((bits >> 31) & 1) == 1 { -1.0 } else { 1.0 };
  let exp = (bits >> 23) & 0xFF;
  let frac = bits & 0x7FFFFF;
  if exp == 0 {
    if frac == 0 { return sign * 0.0; }
    return sign * (frac as Float64) * lt_pow2i(-149);
  }
  if exp == 255 { return 0.0; }
  return sign * (1.0 + (frac as Float64) / 8388608.0) * lt_pow2i(exp - 127);
}

fn lt_pow2i(e: Int) -> Float64
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
pub fn lt_call_error(lib: &LtLibrary, code: Int, context: Str) -> LtError
  requires: code != 0
  requires: context.len() > 0
{
  return LtError{
    kind: LT_CALL_FAILED;
    message: context + " [aoti rc " + int_to_str(code) + " on " + lib.soname + "]",
  };
}

/// AOTI protocol check: 0 = success; otherwise convert to a typed error.
/// Complexity: O(len).
pub fn lt_check(lib: &LtLibrary, code: Int, context: Str) -> Result[Unit, LtError]
  requires: context.len() > 0
{
  if code == 0 { return Ok(()); }
  return Err(lt_call_error(lib, code, context));
}

// =========================================================================
// Loader
// =========================================================================

fn fail_load(handle: Int, message: Str) -> Result[LtLibrary, LtError]
  requires: handle != 0
  requires: message.len() > 0
{
  var ig = dl.dl_close(handle);
  return Err(LtError{ kind: LT_LOAD_ABI; message: message });
}

fn sym_or(handle: Int, name: Str) -> Result[Int, Str]
  requires: handle != 0
  requires: name.len() > 0
{
  let a = dl.dl_sym(handle, name);
  if !a.is_ok { return Err(name + ": " + a.error); }
  return Ok(a.value);
}

fn try_load(soname: Str) -> Result[LtLibrary, LtError]
  requires: soname.len() > 0
{
  let h = dl.dl_open(soname);
  if !h.is_ok {
    // Not this candidate: report ABSENT so the caller can try the next one.
    return Err(LtError{ kind: LT_LOAD_ABSENT; message: soname + ": " + h.error });
  }
  let handle: Int = h.value;

  // C tier -- constants / probe
  let s01 = sym_or(handle, "aoti_torch_abi_version");
  if !s01.is_ok { return fail_load(handle, soname + ": " + s01.error); }
  let s02 = sym_or(handle, "aoti_torch_dtype_float32");
  if !s02.is_ok { return fail_load(handle, soname + ": " + s02.error); }
  let s03 = sym_or(handle, "aoti_torch_dtype_element_size");
  if !s03.is_ok { return fail_load(handle, soname + ": " + s03.error); }
  let s04 = sym_or(handle, "aoti_torch_device_type_cpu");
  if !s04.is_ok { return fail_load(handle, soname + ": " + s04.error); }
  let s05 = sym_or(handle, "aoti_torch_device_type_cuda");
  if !s05.is_ok { return fail_load(handle, soname + ": " + s05.error); }
  let s06 = sym_or(handle, "aoti_torch_layout_strided");
  if !s06.is_ok { return fail_load(handle, soname + ": " + s06.error); }
  // C tier -- tensor lifecycle
  let s07 = sym_or(handle, "aoti_torch_empty_strided");
  if !s07.is_ok { return fail_load(handle, soname + ": " + s07.error); }
  let s08 = sym_or(handle, "aoti_torch_delete_tensor_object");
  if !s08.is_ok { return fail_load(handle, soname + ": " + s08.error); }
  let s09 = sym_or(handle, "aoti_torch_create_tensor_from_blob_v2");
  if !s09.is_ok { return fail_load(handle, soname + ": " + s09.error); }
  let s10 = sym_or(handle, "aoti_torch_tensor_copy_");
  if !s10.is_ok { return fail_load(handle, soname + ": " + s10.error); }
  let s11 = sym_or(handle, "aoti_torch_clone");
  if !s11.is_ok { return fail_load(handle, soname + ": " + s11.error); }
  let s12 = sym_or(handle, "aoti_torch_new_tensor_handle");
  if !s12.is_ok { return fail_load(handle, soname + ": " + s12.error); }
  // C tier -- metadata
  let s13 = sym_or(handle, "aoti_torch_get_data_ptr");
  if !s13.is_ok { return fail_load(handle, soname + ": " + s13.error); }
  let s14 = sym_or(handle, "aoti_torch_get_numel");
  if !s14.is_ok { return fail_load(handle, soname + ": " + s14.error); }
  let s15 = sym_or(handle, "aoti_torch_get_dim");
  if !s15.is_ok { return fail_load(handle, soname + ": " + s15.error); }
  let s16 = sym_or(handle, "aoti_torch_get_sizes");
  if !s16.is_ok { return fail_load(handle, soname + ": " + s16.error); }
  let s17 = sym_or(handle, "aoti_torch_get_strides");
  if !s17.is_ok { return fail_load(handle, soname + ": " + s17.error); }
  let s18 = sym_or(handle, "aoti_torch_get_size");
  if !s18.is_ok { return fail_load(handle, soname + ": " + s18.error); }
  let s19 = sym_or(handle, "aoti_torch_get_stride");
  if !s19.is_ok { return fail_load(handle, soname + ": " + s19.error); }
  let s20 = sym_or(handle, "aoti_torch_get_dtype");
  if !s20.is_ok { return fail_load(handle, soname + ": " + s20.error); }
  let s21 = sym_or(handle, "aoti_torch_get_device_type");
  if !s21.is_ok { return fail_load(handle, soname + ": " + s21.error); }
  let s22 = sym_or(handle, "aoti_torch_get_device_index");
  if !s22.is_ok { return fail_load(handle, soname + ": " + s22.error); }
  let s23 = sym_or(handle, "aoti_torch_get_storage_offset");
  if !s23.is_ok { return fail_load(handle, soname + ": " + s23.error); }
  let s24 = sym_or(handle, "aoti_torch_is_contiguous");
  if !s24.is_ok { return fail_load(handle, soname + ": " + s24.error); }
  let s25 = sym_or(handle, "aoti_torch_is_defined");
  if !s25.is_ok { return fail_load(handle, soname + ": " + s25.error); }
  // C tier -- scalars
  let s26 = sym_or(handle, "aoti_torch_item_float32");
  if !s26.is_ok { return fail_load(handle, soname + ": " + s26.error); }
  let s27 = sym_or(handle, "aoti_torch_scalar_to_tensor_float32");
  if !s27.is_ok { return fail_load(handle, soname + ": " + s27.error); }
  // C tier -- ops
  let s28 = sym_or(handle, "aoti_torch_cpu_add_Tensor");
  if !s28.is_ok { return fail_load(handle, soname + ": " + s28.error); }
  let s29 = sym_or(handle, "aoti_torch_cpu_mul_Tensor");
  if !s29.is_ok { return fail_load(handle, soname + ": " + s29.error); }
  let s30 = sym_or(handle, "aoti_torch_cpu_mul_Scalar");
  if !s30.is_ok { return fail_load(handle, soname + ": " + s30.error); }
  let s31 = sym_or(handle, "aoti_torch_cpu_mm_out");
  if !s31.is_ok { return fail_load(handle, soname + ": " + s31.error); }
  let s32 = sym_or(handle, "aoti_torch_cpu_reshape");
  if !s32.is_ok { return fail_load(handle, soname + ": " + s32.error); }
  let s33 = sym_or(handle, "aoti_torch_cpu_narrow");
  if !s33.is_ok { return fail_load(handle, soname + ": " + s33.error); }
  // C tier -- in-place / dispatcher / grad
  let s34 = sym_or(handle, "aoti_torch_aten_fill__Scalar");
  if !s34.is_ok { return fail_load(handle, soname + ": " + s34.error); }
  let s35 = sym_or(handle, "aoti_torch_zero_");
  if !s35.is_ok { return fail_load(handle, soname + ": " + s35.error); }
  let s36 = sym_or(handle, "aoti_torch_call_dispatcher");
  if !s36.is_ok { return fail_load(handle, soname + ": " + s36.error); }
  let s37 = sym_or(handle, "aoti_torch_grad_mode_is_enabled");
  if !s37.is_ok { return fail_load(handle, soname + ": " + s37.error); }
  let s38 = sym_or(handle, "aoti_torch_grad_mode_set_enabled");
  if !s38.is_ok { return fail_load(handle, soname + ": " + s38.error); }

  // C++ tier -- pinned mangled anchors (resolved; the two trivial-ABI ones
  // are called live).
  let a1 = sym_or(handle, "?is_available@cuda@torch@@YA_NXZ");
  if !a1.is_ok { return fail_load(handle, soname + ": " + a1.error); }
  let a2 = sym_or(handle, "?device_count@cuda@torch@@YACXZ");
  if !a2.is_ok { return fail_load(handle, soname + ": " + a2.error); }
  let a3 = sym_or(handle, "?load@jit@torch@@YA?AUModule@12@AEBV?$basic_string@DU?$char_traits@D@std@@V?$allocator@D@2@@std@@V?$optional@UDevice@c10@@@5@_N@Z");
  if !a3.is_ok { return fail_load(handle, soname + ": " + a3.error); }

  // Version probe: TORCH_ABI_VERSION decode (MAJOR<<56|MINOR<<48|PATCH<<40).
  let av_fp = s01.value;
  let av = unsafe { av_fp as fn() -> Int };
  let abi = av();
  let major = (abi >> 56) & 255;
  let minor = (abi >> 48) & 255;
  let patch = (abi >> 40) & 255;
  if abi == 0 {
    return fail_load(handle, soname + ": aoti_torch_abi_version returned 0");
  }
  if major < LT_MIN_MAJOR {
    return fail_load(handle, soname + ": libtorch " + int_to_str(major) + "." +
      int_to_str(minor) + " is older than the declared " + int_to_str(LT_MIN_MAJOR) +
      "." + int_to_str(LT_MIN_MINOR) + " ABI floor");
  }
  if major == LT_MIN_MAJOR && minor < LT_MIN_MINOR {
    return fail_load(handle, soname + ": libtorch " + int_to_str(major) + "." +
      int_to_str(minor) + " is older than the declared " + int_to_str(LT_MIN_MAJOR) +
      "." + int_to_str(LT_MIN_MINOR) + " ABI floor");
  }

  return Ok(LtLibrary{
    handle: handle;
    soname: soname;
    abi_version: abi;
    major: major;
    minor: minor;
    patch: patch;
    resolved: 38;
    required: 38;
    anchors_resolved: 3;
    anchors_required: 3;
    f_abi_version: s01.value;
    f_dtype_float32: s02.value;
    f_dtype_element_size: s03.value;
    f_device_type_cpu: s04.value;
    f_device_type_cuda: s05.value;
    f_layout_strided: s06.value;
    f_empty_strided: s07.value;
    f_delete_tensor: s08.value;
    f_from_blob_v2: s09.value;
    f_tensor_copy: s10.value;
    f_clone: s11.value;
    f_new_handle: s12.value;
    f_get_data_ptr: s13.value;
    f_get_numel: s14.value;
    f_get_dim: s15.value;
    f_get_sizes: s16.value;
    f_get_strides: s17.value;
    f_get_size: s18.value;
    f_get_stride: s19.value;
    f_get_dtype: s20.value;
    f_get_device_type: s21.value;
    f_get_device_index: s22.value;
    f_get_storage_offset: s23.value;
    f_is_contiguous: s24.value;
    f_is_defined: s25.value;
    f_item_f32: s26.value;
    f_scalar_to_tensor_f32: s27.value;
    f_cpu_add: s28.value;
    f_cpu_mul: s29.value;
    f_cpu_mul_scalar: s30.value;
    f_cpu_mm_out: s31.value;
    f_cpu_reshape: s32.value;
    f_cpu_narrow: s33.value;
    f_fill_scalar: s34.value;
    f_zero: s35.value;
    f_dispatcher: s36.value;
    f_grad_enabled: s37.value;
    f_grad_set: s38.value;
    p_cuda_available: a1.value;
    p_cuda_device_count: a2.value;
    p_jit_load: a3.value;
  });
}

/// The multi-soname candidate list, in probe order: the optional
/// `XIOM_LIBTORCH_RUNTIME` override (explicit path, used by the live leg),
/// then the Windows, Linux and macOS sonames.  The Windows official builds
/// ship `torch_cpu.dll` (the AOTI C shim lives there); `libtorch_cpu` /
/// `libtorch` cover the redistributions that use those names.
/// Complexity: O(1).
pub fn lt_load_candidates() -> Vec[Str]
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

/// Load an explicitly named build (path or soname). A bogus name yields the
/// deterministic ABSENT classification on any host (the SKIP probe).
/// Complexity: O(load + surface check).
pub fn lt_load_named(soname: Str) -> Result[LtLibrary, LtError]
  requires: soname.len() > 0
{
  return try_load(soname);
}

/// Load the first usable candidate from `lt_load_candidates()`. No
/// candidate present -> LT_LOAD_ABSENT (the typed SKIP state); a candidate
/// that loads but fails the surface/version check -> its ABI error is kept
/// while later candidates are still tried (fail-closed, never a silent
/// fallback).
/// Complexity: O(candidates * surface).
pub fn lt_load() -> Result[LtLibrary, LtError]
  requires: true
{
  let cands = lt_load_candidates();
  var abi: LtError = LtError{ kind: LT_LOAD_ABSENT; message: "" };
  var i = 0;
  while i < cands.len() {
    let r = try_load(cands[i]);
    if r.is_ok {
      return Ok(r.value);
    }
    if r.error.kind == LT_LOAD_ABI {
      abi = r.error;
    }
    i = i + 1;
  };
  if abi.message.len() > 0 {
    return Err(abi);
  }
  return Err(LtError{
    kind: LT_LOAD_ABSENT;
    message: "libtorch: no runtime candidate loaded (tried " + int_to_str(cands.len()) +
      " candidates: XIOM_LIBTORCH_RUNTIME, torch_cpu.dll, libtorch_cpu.dll, libtorch.dll, torch.dll, libtorch_cpu.so, libtorch.so, libtorch_cpu.so.2, libtorch.so.2, libtorch_cpu.dylib, libtorch.dylib)",
  });
}

/// Release the library handle.
/// Complexity: O(1).
pub fn lt_close(lib: &LtLibrary) -> Result[Unit, Str]
  requires: lib.handle != 0
{
  return dl.dl_close(lib.handle);
}

/// Version + declared-surface counts of a loaded build (the live-leg
/// probe).
/// Complexity: O(1).
pub fn lt_probe(lib: &LtLibrary) -> LtInfo
  requires: lib.handle != 0
{
  return LtInfo{
    soname: lib.soname;
    abi_version: lib.abi_version;
    major: lib.major;
    minor: lib.minor;
    patch: lib.patch;
    resolved: lib.resolved;
    required: lib.required;
    anchors_resolved: lib.anchors_resolved;
    anchors_required: lib.anchors_required;
  };
}
