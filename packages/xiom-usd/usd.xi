// XIOM -- xiom.usd: OpenUSD (Pixar Universal Scene Description) bindings.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// DESIGN (bindings lane): the XIOM surface is a thin typed wrapper over a
// C ABI bridge (src/usd_bridge.cpp) compiled into the consumer binary.  The
// bridge is delay-loaded against the prebuilt usd_ms.dll from the official
// `usd-core` wheel, so the module and suite build and run without the USD
// runtime; when the runtime is absent (or ABI-gated) the loader returns a
// typed SKIP and the suite stays green.
//
// G2 pin (SPEC.md): OpenUSD v26.08 (commit ee47c679), usd-core 26.8 wheel
// (sha256 D39CEF20...578F), namespace pxrInternal_v0_26_8__pxrReserved__.
// Sonames probed: usd_ms.dll (bound), usd.dll (typed ABI gate),
// libusd.so (POSIX; not bound on the Windows lane).
//
// Declared surface (100% implemented; docs/COVERAGE.md): stage open/close +
// traversal; prim name/type/path + authored attributes; mesh points /
// face-vertex counts / indices with typed errors; material surface subset
// (binding -> outputs:surface shader -> inputs, constant + connection read);
// time-sample essentials (count/bounds/time/value/sample).
//
// Ownership: stage, prim and iterator handles are bridge-side IDs.  Release
// prims/iterators explicitly; closing a stage invalidates its prims/iterators
// (subsequent calls return USD_ERR_INVALID_HANDLE).  Strings are copied into
// XIOM-owned Str values; no C memory escapes.

module xiom.usd

use xiom.ffi;
use xiom.ffi.dl;

// =========================================================================
// Runtime / module identity
// =========================================================================

pub const USD_SONAME_PRIMARY: Str = "usd_ms.dll";
pub const USD_SONAME_ALT: Str = "usd.dll";
pub const USD_SONAME_POSIX: Str = "libusd.so";

pub const USD_LOAD_PRESENT: Int = 0;
pub const USD_LOAD_ABSENT: Int = 1;
pub const USD_LOAD_ABI: Int = 2;
pub const USD_LOAD_DEPS: Int = 3;

pub const USD_OK: Int = 0;
pub const USD_ERR_RUNTIME_ABSENT: Int = 1;
pub const USD_ERR_RUNTIME_ABI: Int = 2;
pub const USD_ERR_RUNTIME_DEPS: Int = 3;
pub const USD_ERR_OPEN: Int = 4;
pub const USD_ERR_INVALID_HANDLE: Int = 5;
pub const USD_ERR_NOT_PRIM: Int = 6;
pub const USD_ERR_NOT_MESH: Int = 7;
pub const USD_ERR_MESH_INVALID: Int = 8;
pub const USD_ERR_ATTR_MISSING: Int = 9;
pub const USD_ERR_TYPE: Int = 10;
pub const USD_ERR_RANGE: Int = 11;
pub const USD_ERR_BUFFER: Int = 12;
pub const USD_ERR_NO_SURFACE: Int = 13;
pub const USD_ERR_NO_VALUE: Int = 14;
pub const USD_ERR_INTERNAL: Int = 15;
pub const USD_ERR_NO_BINDING: Int = 16;
pub const USD_ERR_NOT_MATERIAL: Int = 17;
pub const USD_ERR_INVALID_PATH: Int = 18;
pub const USD_ERR_OVERFLOW: Int = 19;

/// Declared C-ABI surface size (checked by the conformance suite).
pub const USD_BRIDGE_SURFACE: Int = 58;

extern "C" {
  fn usdbridge_runtime_prepare(dir: *UInt8) -> Int32;
  fn usdbridge_runtime_soname(out: *UInt8, cap: Int32) -> Int32;
  fn usdbridge_bridge_version() -> Int32;
  fn usdbridge_bridge_abi() -> Int32;
  fn usdbridge_bridge_surface_count() -> Int32;
  fn usdbridge_last_error_code() -> Int32;
  fn usdbridge_last_error_message() -> *UInt8;
  fn usdbridge_error_name(code: Int32) -> *UInt8;

  fn usdbridge_stage_open(path: *UInt8) -> Int64;
  fn usdbridge_stage_release(stage: Int64) -> Int32;
  fn usdbridge_stage_default_prim(stage: Int64, out: *UInt8, cap: Int32) -> Int32;
  fn usdbridge_stage_iter(stage: Int64) -> Int64;
  fn usdbridge_prim_iter(prim: Int64) -> Int64;
  fn usdbridge_iter_next(iter: Int64) -> Int64;
  fn usdbridge_iter_release(iter: Int64) -> Int32;
  fn usdbridge_prim_at_path(stage: Int64, path: *UInt8) -> Int64;

  fn usdbridge_prim_release(prim: Int64) -> Int32;
  fn usdbridge_prim_is_valid(prim: Int64) -> Int32;
  fn usdbridge_prim_name(prim: Int64, out: *UInt8, cap: Int32) -> Int32;
  fn usdbridge_prim_type(prim: Int64, out: *UInt8, cap: Int32) -> Int32;
  fn usdbridge_prim_path(prim: Int64, out: *UInt8, cap: Int32) -> Int32;
  fn usdbridge_prim_attr_count(prim: Int64) -> Int32;
  fn usdbridge_prim_attr_name(prim: Int64, index: Int32, out: *UInt8, cap: Int32) -> Int32;
  fn usdbridge_prim_attr_type(prim: Int64, index: Int32, out: *UInt8, cap: Int32) -> Int32;
  fn usdbridge_prim_attr_index(prim: Int64, name: *UInt8) -> Int32;
  fn usdbridge_prim_attr_float(prim: Int64, index: Int32, out: *UInt8) -> Int32;
  fn usdbridge_prim_attr_double(prim: Int64, index: Int32, out: *UInt8) -> Int32;
  fn usdbridge_prim_attr_int(prim: Int64, index: Int32, out: *UInt8) -> Int32;
  fn usdbridge_prim_attr_bool(prim: Int64, index: Int32, out: *UInt8) -> Int32;
  fn usdbridge_prim_attr_vec3_component(prim: Int64, index: Int32, component: Int32, out: *UInt8) -> Int32;
  fn usdbridge_prim_attr_string(prim: Int64, index: Int32, out: *UInt8, cap: Int32) -> Int32;

  fn usdbridge_mesh_info(prim: Int64, points: *UInt8, faces: *UInt8, indices: *UInt8) -> Int32;
  fn usdbridge_mesh_point_component(prim: Int64, point_index: Int32, component: Int32, out: *UInt8) -> Int32;
  fn usdbridge_mesh_face_counts(prim: Int64, out: *UInt8, cap: Int32) -> Int32;
  fn usdbridge_mesh_indices(prim: Int64, out: *UInt8, cap: Int32) -> Int32;

  fn usdbridge_material_binding(prim: Int64, out: *UInt8, cap: Int32) -> Int32;
  fn usdbridge_material_surface_shader(prim: Int64, out: *UInt8, cap: Int32) -> Int32;
  fn usdbridge_material_surface_shader_prim(prim: Int64) -> Int64;
  fn usdbridge_material_shader_id(prim: Int64, out: *UInt8, cap: Int32) -> Int32;
  fn usdbridge_material_input_count(prim: Int64) -> Int32;
  fn usdbridge_material_input_name(prim: Int64, index: Int32, out: *UInt8, cap: Int32) -> Int32;
  fn usdbridge_material_input_type(prim: Int64, index: Int32, out: *UInt8, cap: Int32) -> Int32;
  fn usdbridge_material_input_connected(prim: Int64, index: Int32) -> Int32;
  fn usdbridge_material_input_connection(prim: Int64, index: Int32, out: *UInt8, cap: Int32) -> Int32;
  fn usdbridge_material_input_float(prim: Int64, name: *UInt8, out: *UInt8) -> Int32;
  fn usdbridge_material_input_vec3_component(prim: Int64, name: *UInt8, component: Int32, out: *UInt8) -> Int32;
  fn usdbridge_material_input_string(prim: Int64, name: *UInt8, out: *UInt8, cap: Int32) -> Int32;

  fn usdbridge_attr_time_count(prim: Int64, name: *UInt8) -> Int32;
  fn usdbridge_attr_time_at(prim: Int64, name: *UInt8, index: Int32, out: *UInt8) -> Int32;
  fn usdbridge_attr_time_bounds(prim: Int64, name: *UInt8, out_min: *UInt8, out_max: *UInt8) -> Int32;
  fn usdbridge_attr_double_at(prim: Int64, name: *UInt8, time: Float64, out: *UInt8) -> Int32;
  fn usdbridge_attr_float_at(prim: Int64, name: *UInt8, time: Float64, out: *UInt8) -> Int32;
  fn usdbridge_attr_vec3_at_component(prim: Int64, name: *UInt8, time: Float64, component: Int32, out: *UInt8) -> Int32;
  fn usdbridge_mesh_point_packed(prim: Int64, packed: Int32, out: *UInt8) -> Int32;
  fn usdbridge_prim_attr_vec3_packed(prim: Int64, packed: Int32, out: *UInt8) -> Int32;
  fn usdbridge_material_input_vec3_x(prim: Int64, name: *UInt8, out: *UInt8) -> Int32;
  fn usdbridge_material_input_vec3_y(prim: Int64, name: *UInt8, out: *UInt8) -> Int32;
  fn usdbridge_material_input_vec3_z(prim: Int64, name: *UInt8, out: *UInt8) -> Int32;
  fn usdbridge_attr_vec3_at_x(prim: Int64, name: *UInt8, time: Float64, out: *UInt8) -> Int32;
  fn usdbridge_attr_vec3_at_y(prim: Int64, name: *UInt8, time: Float64, out: *UInt8) -> Int32;
  fn usdbridge_attr_vec3_at_z(prim: Int64, name: *UInt8, time: Float64, out: *UInt8) -> Int32;
  fn usdbridge_attr_float_sample(prim: Int64, name: *UInt8, index: Int32, out: *UInt8) -> Int32;
}

// =========================================================================
// Types
// =========================================================================

pub type UsdLoadError = {
  kind: Int;
  message: Str;
}

/// A loaded USD runtime.  `handle` is the dl handle; the bridge keeps its own
/// reference to usd_ms.dll, so the runtime stays loaded for the process.
pub type UsdLibrary = {
  handle: Int;
  soname: Str;
  abi: Int;
}

pub type UsdError = {
  code: Int;
  message: Str;
}

/// Open stage handle.  Release with `usd_stage_release`.
pub type UsdStage = {
  handle: Int;
}

/// Prim handle (owned; release with `usd_prim_release`).
pub type UsdPrim = {
  handle: Int;
  stage: Int;
}

/// Traversal cursor.  Release with `usd_iter_release`.
pub type UsdIter = {
  handle: Int;
  stage: Int;
}

pub type UsdAttrInfo = {
  name: Str;
  type_name: Str;
}

pub type UsdMeshInfo = {
  point_count: Int;
  face_count: Int;
  index_count: Int;
}

pub type UsdMaterialInput = {
  name: Str;
  type_name: Str;
  connected: Bool;
  connection: Str;
}

pub type UsdTimeSamples = {
  count: Int;
  min_time: Float64;
  max_time: Float64;
}

// =========================================================================
// Small numeric / buffer helpers
// =========================================================================

fn usd_slot(n: Int) -> Vec[UInt8]
  requires: n > 0
{
  var s: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < n {
    s.push(0 as UInt8);
    i = i + 1;
  }
  return s;
}

fn usd_read_u32_vec(buf: &Vec[UInt8], off: Int) -> Int
  requires: off >= 0
  requires: buf.len() >= off + 4
{
  let b0 = buf[off + 0] as Int;
  let b1 = buf[off + 1] as Int;
  let b2 = buf[off + 2] as Int;
  let b3 = buf[off + 3] as Int;
  return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24);
}

/// Signed little-endian i32 from an owned byte slot (B-16/B-17-safe).
fn usd_read_i32_vec(buf: &Vec[UInt8], off: Int) -> Int
  requires: off >= 0
  requires: buf.len() >= off + 4
{
  let u = usd_read_u32_vec(buf, off);
  if u >= 0x80000000 { return u - 0x100000000; }
  return u;
}

fn usd_pow2i(e: Int) -> Float64
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

fn usd_f32_from_bits(bits: Int) -> Float64
  requires: bits >= 0
  requires: bits <= 0xFFFFFFFF
{
  let sign = if ((bits >> 31) & 1) == 1 { -1.0 } else { 1.0 };
  let exp = (bits >> 23) & 0xFF;
  let frac = bits & 0x7FFFFF;
  if exp == 0 {
    if frac == 0 { return sign * 0.0; }
    return sign * (frac as Float64) * usd_pow2i(-149);
  }
  if exp == 255 { return 0.0; }
  return sign * (1.0 + (frac as Float64) / 8388608.0) * usd_pow2i(exp - 127);
}

fn usd_f64_from_bits(bits: Int) -> Float64
  requires: true
{
  let sign = if ((bits >> 63) & 1) == 1 { -1.0 } else { 1.0 };
  let exp = (bits >> 52) & 0x7FF;
  let frac = bits & 0xFFFFFFFFFFFFF;
  if exp == 0 {
    if frac == 0 { return sign * 0.0; }
    return sign * (frac as Float64) * usd_pow2i(-1074);
  }
  if exp == 2047 { return 0.0; }
  return sign * (1.0 + (frac as Float64) / 4503599627370496.0) * usd_pow2i(exp - 1023);
}

fn usd_last_error() -> UsdError
  requires: true
{
  unsafe {
    let code = usdbridge_last_error_code() as Int;
    let p = usdbridge_last_error_message();
    var msg = "";
    if (p as Int) != 0 { msg = Str::from_c_str(p); }
    return UsdError{ code: code, message: msg };
  }
}

fn usd_copy_string(rc: Int, slot: &Vec[UInt8]) -> Result[Str, UsdError]
  requires: true
{
  if rc < 0 { return Err(usd_last_error()); }
  unsafe {
    return Ok(Str::from_c_str(slot.as_mut_ptr()));
  }
}

fn usd_error_name_internal(code: Int) -> Str
  requires: true
{
  unsafe {
    let p = usdbridge_error_name(code as Int32);
    if (p as Int) != 0 { return Str::from_c_str(p); }
    return "UNKNOWN";
  }
}

fn usd_i2s(n: Int) -> Str
  requires: true
{
  if n == 0 { return "0"; }
  var neg = false;
  var val = n;
  if val < 0 { neg = true; val = 0 - val; }
  var buf = "";
  while val > 0 {
    let digit = val % 10;
    val = val / 10;
    if digit == 0 { buf = "0" + buf; }
    elif digit == 1 { buf = "1" + buf; }
    elif digit == 2 { buf = "2" + buf; }
    elif digit == 3 { buf = "3" + buf; }
    elif digit == 4 { buf = "4" + buf; }
    elif digit == 5 { buf = "5" + buf; }
    elif digit == 6 { buf = "6" + buf; }
    elif digit == 7 { buf = "7" + buf; }
    elif digit == 8 { buf = "8" + buf; }
    elif digit == 9 { buf = "9" + buf; }
  }
  if neg { return "-" + buf; }
  return buf;
}

// =========================================================================
// Runtime loader
// =========================================================================

/// Load the USD runtime.  `runtime_dir` is the directory containing
/// `usd_ms.dll` (the wheel's `pxr` directory); an empty string uses the
/// platform search path.  Err(kind=ABSENT/DEPS/ABI) is the typed SKIP signal.
/// Complexity: O(1) + LoadLibrary.
pub fn usd_load(runtime_dir: Str) -> Result[UsdLibrary, UsdLoadError]
  requires: true
{
  var rc = 0;
  unsafe {
    rc = usdbridge_runtime_prepare(runtime_dir.c_str()) as Int;
  }
  if rc != 0 {
    var kind = USD_LOAD_ABI;
    if rc == -USD_ERR_RUNTIME_ABSENT { kind = USD_LOAD_ABSENT; }
    elif rc == -USD_ERR_RUNTIME_DEPS { kind = USD_LOAD_DEPS; }
    elif rc == -USD_ERR_RUNTIME_ABI { kind = USD_LOAD_ABI; }
    let err = usd_last_error();
    return Err(UsdLoadError{ kind: kind, message: err.message });
  }
  let h = dl.dl_open(USD_SONAME_PRIMARY);
  if !h.is_ok {
    return Err(UsdLoadError{ kind: USD_LOAD_ABI; message: h.error });
  }
  var slot = usd_slot(64);
  unsafe {
    let n = usdbridge_runtime_soname(slot.as_mut_ptr(), 64 as Int32);
    if n < 0 {
      let err = usd_last_error();
      var ig = dl.dl_close(h.value);
      return Err(UsdLoadError{ kind: USD_LOAD_ABI; message: err.message });
    }
  }
  var soname = "";
  unsafe { soname = Str::from_c_str(slot.as_mut_ptr()); }
  var abi = 0;
  unsafe { abi = usdbridge_bridge_abi() as Int; }
  return Ok(UsdLibrary{ handle: h.value, soname: soname, abi: abi });
}

/// Release the loader reference (the bridge's own reference keeps the DLL
/// loaded for the process).  Complexity: O(1).
pub fn usd_close(lib: &UsdLibrary)
  requires: lib.handle != 0
{
  unsafe {
    var ig = dl.dl_close(lib.handle);
  }
}

/// OpenUSD version encoded by the bridge (26.08 -> 2608).
/// Complexity: O(1).
pub fn usd_bridge_abi() -> Int
  requires: true
{
  unsafe { return usdbridge_bridge_abi() as Int; }
}

/// Bridge API version (0.1.0 -> 100).  Complexity: O(1).
pub fn usd_bridge_version() -> Int
  requires: true
{
  unsafe { return usdbridge_bridge_version() as Int; }
}

/// Number of declared C-ABI functions (coverage gate).  Complexity: O(1).
pub fn usd_bridge_surface_count() -> Int
  requires: true
{
  unsafe { return usdbridge_bridge_surface_count() as Int; }
}

/// Human-readable name of an error code.  Complexity: O(1).
pub fn usd_error_name(code: Int) -> Str
  requires: true
{
  return usd_error_name_internal(code);
}

/// Last bridge error as a typed record.  Complexity: O(1).
pub fn usd_error() -> UsdError
  requires: true
{
  return usd_last_error();
}

// =========================================================================
// Stage / traversal
// =========================================================================

/// Open a stage from disk (usda/usdc/usdz as supported by the runtime).
/// Complexity: O(stage).
pub fn usd_stage_open(lib: &UsdLibrary, path: Str) -> Result[UsdStage, UsdError]
  requires: path.len() > 0
  requires: lib.handle != 0
{
  unsafe {
    let h = usdbridge_stage_open(path.c_str()) as Int;
    if h == 0 { return Err(usd_last_error()); }
    return Ok(UsdStage{ handle: h });
  }
}

/// Close a stage; all of its prim/iterator handles become invalid.
/// Complexity: O(handles).
pub fn usd_stage_release(stage: &UsdStage)
  requires: stage.handle != 0
{
  unsafe {
    var rc = usdbridge_stage_release(stage.handle as Int64);
  }
}

/// Stage defaultPrim name ("" when the stage declares none).
/// Complexity: O(1).
pub fn usd_stage_default_prim(stage: &UsdStage) -> Result[Str, UsdError]
  requires: stage.handle != 0
{
  var slot = usd_slot(2048);
  var rc = 0;
  unsafe {
    rc = usdbridge_stage_default_prim(stage.handle as Int64, slot.as_mut_ptr(), 2048 as Int32) as Int;
  }
  return usd_copy_string(rc, &slot);
}

/// Depth-first pre-order traversal of the whole stage (root prims down).
/// Complexity: O(prim count) for the full walk.
pub fn usd_stage_iter(stage: &UsdStage) -> Result[UsdIter, UsdError]
  requires: stage.handle != 0
{
  unsafe {
    let h = usdbridge_stage_iter(stage.handle as Int64) as Int;
    if h == 0 { return Err(usd_last_error()); }
    return Ok(UsdIter{ handle: h, stage: stage.handle });
  }
}

/// Traversal rooted at a prim (the prim itself is the first item).
/// Complexity: O(subtree).
pub fn usd_prim_iter(prim: &UsdPrim) -> Result[UsdIter, UsdError]
  requires: prim.handle != 0
{
  unsafe {
    let h = usdbridge_prim_iter(prim.handle as Int64) as Int;
    if h == 0 { return Err(usd_last_error()); }
    return Ok(UsdIter{ handle: h, stage: prim.stage });
  }
}

/// Advance the cursor.  Returns a handle with `handle == 0` at end of range.
/// Complexity: O(1) per step.
pub fn usd_iter_next(iter: &UsdIter) -> UsdPrim
  requires: iter.handle != 0
{
  unsafe {
    let h = usdbridge_iter_next(iter.handle as Int64) as Int;
    return UsdPrim{ handle: h, stage: iter.stage };
  }
}

/// Release the cursor.  Complexity: O(1).
pub fn usd_iter_release(iter: &UsdIter)
  requires: iter.handle != 0
{
  unsafe {
    var rc = usdbridge_iter_release(iter.handle as Int64);
  }
}

/// Look up a prim by absolute path.  Complexity: O(path).
pub fn usd_prim_at_path(stage: &UsdStage, path: Str) -> Result[UsdPrim, UsdError]
  requires: stage.handle != 0
  requires: path.len() > 0
{
  unsafe {
    let h = usdbridge_prim_at_path(stage.handle as Int64, path.c_str()) as Int;
    if h == 0 { return Err(usd_last_error()); }
    return Ok(UsdPrim{ handle: h, stage: stage.handle });
  }
}

/// Release a prim handle (no-op for an end-of-range handle).
/// Complexity: O(1).
pub fn usd_prim_release(prim: &UsdPrim)
  requires: true
{
  if prim.handle != 0 {
    unsafe {
      var rc = usdbridge_prim_release(prim.handle as Int64);
    }
  }
}

/// True when the handle is live and the prim is usable.  Complexity: O(1).
pub fn usd_prim_is_valid(prim: &UsdPrim) -> Bool
  requires: true
{
  if prim.handle == 0 { return false; }
  unsafe { return (usdbridge_prim_is_valid(prim.handle as Int64) as Int) != 0; }
}

// =========================================================================
// Prim read
// =========================================================================

pub fn usd_prim_name(prim: &UsdPrim) -> Result[Str, UsdError]
  requires: prim.handle != 0
{
  var slot = usd_slot(2048);
  var rc = 0;
  unsafe {
    rc = usdbridge_prim_name(prim.handle as Int64, slot.as_mut_ptr(), 2048 as Int32) as Int;
  }
  return usd_copy_string(rc, &slot);
}

pub fn usd_prim_type(prim: &UsdPrim) -> Result[Str, UsdError]
  requires: prim.handle != 0
{
  var slot = usd_slot(2048);
  var rc = 0;
  unsafe {
    rc = usdbridge_prim_type(prim.handle as Int64, slot.as_mut_ptr(), 2048 as Int32) as Int;
  }
  return usd_copy_string(rc, &slot);
}

pub fn usd_prim_path(prim: &UsdPrim) -> Result[Str, UsdError]
  requires: prim.handle != 0
{
  var slot = usd_slot(4096);
  var rc = 0;
  unsafe {
    rc = usdbridge_prim_path(prim.handle as Int64, slot.as_mut_ptr(), 4096 as Int32) as Int;
  }
  return usd_copy_string(rc, &slot);
}

/// Number of authored attributes on the prim.  Complexity: O(1).
pub fn usd_prim_attr_count(prim: &UsdPrim) -> Result[Int, UsdError]
  requires: prim.handle != 0
{
  unsafe {
    let rc = usdbridge_prim_attr_count(prim.handle as Int64) as Int;
    if rc < 0 { return Err(usd_last_error()); }
    return Ok(rc);
  }
}

/// Attribute info by authored-attribute index.  Complexity: O(1).
pub fn usd_prim_attr(prim: &UsdPrim, index: Int) -> Result[UsdAttrInfo, UsdError]
  requires: prim.handle != 0
  requires: index >= 0
{
  var name_slot = usd_slot(2048);
  var type_slot = usd_slot(2048);
  unsafe {
    let nrc = usdbridge_prim_attr_name(prim.handle as Int64, index as Int32,
                                 name_slot.as_mut_ptr(), 2048 as Int32) as Int;
    if nrc < 0 { return Err(usd_last_error()); }
    let trc = usdbridge_prim_attr_type(prim.handle as Int64, index as Int32,
                                 type_slot.as_mut_ptr(), 2048 as Int32) as Int;
    if trc < 0 { return Err(usd_last_error()); }
    return Ok(UsdAttrInfo{
      name: Str::from_c_str(name_slot.as_mut_ptr()),
      type_name: Str::from_c_str(type_slot.as_mut_ptr()),
    });
  }
}

pub fn usd_prim_attr_name(prim: &UsdPrim, index: Int) -> Result[Str, UsdError]
  requires: prim.handle != 0
  requires: index >= 0
{
  var slot = usd_slot(2048);
  var rc = 0;
  unsafe {
    rc = usdbridge_prim_attr_name(prim.handle as Int64, index as Int32,
                            slot.as_mut_ptr(), 2048 as Int32) as Int;
  }
  return usd_copy_string(rc, &slot);
}

pub fn usd_prim_attr_type(prim: &UsdPrim, index: Int) -> Result[Str, UsdError]
  requires: prim.handle != 0
  requires: index >= 0
{
  var slot = usd_slot(2048);
  var rc = 0;
  unsafe {
    rc = usdbridge_prim_attr_type(prim.handle as Int64, index as Int32,
                            slot.as_mut_ptr(), 2048 as Int32) as Int;
  }
  return usd_copy_string(rc, &slot);
}

/// Authored-attribute index by name (-1 when absent).  Complexity: O(attrs).
pub fn usd_prim_attr_index(prim: &UsdPrim, name: Str) -> Int
  requires: prim.handle != 0
  requires: name.len() > 0
{
  unsafe {
    return usdbridge_prim_attr_index(prim.handle as Int64, name.c_str()) as Int;
  }
}

pub fn usd_prim_attr_float(prim: &UsdPrim, index: Int) -> Result[Float64, UsdError]
  requires: prim.handle != 0
  requires: index >= 0
{
  var slot = usd_slot(4);
  unsafe {
    let rc = usdbridge_prim_attr_float(prim.handle as Int64, index as Int32, slot.as_mut_ptr()) as Int;
    if rc < 0 { return Err(usd_last_error()); }
    return Ok(usd_f32_from_bits(usd_read_u32_vec(&slot, 0)));
  }
}

pub fn usd_prim_attr_double(prim: &UsdPrim, index: Int) -> Result[Float64, UsdError]
  requires: prim.handle != 0
  requires: index >= 0
{
  var slot = usd_slot(8);
  unsafe {
    let rc = usdbridge_prim_attr_double(prim.handle as Int64, index as Int32, slot.as_mut_ptr()) as Int;
    if rc < 0 { return Err(usd_last_error()); }
    return Ok(usd_f64_from_bits(ffi.ptr_read_u64_le(slot.as_mut_ptr())));
  }
}

pub fn usd_prim_attr_int(prim: &UsdPrim, index: Int) -> Result[Int, UsdError]
  requires: prim.handle != 0
  requires: index >= 0
{
  var slot = usd_slot(4);
  unsafe {
    let rc = usdbridge_prim_attr_int(prim.handle as Int64, index as Int32, slot.as_mut_ptr()) as Int;
    if rc < 0 { return Err(usd_last_error()); }
    return Ok(usd_read_i32_vec(&slot, 0));
  }
}

pub fn usd_prim_attr_bool(prim: &UsdPrim, index: Int) -> Result[Bool, UsdError]
  requires: prim.handle != 0
  requires: index >= 0
{
  var slot = usd_slot(4);
  unsafe {
    let rc = usdbridge_prim_attr_bool(prim.handle as Int64, index as Int32, slot.as_mut_ptr()) as Int;
    if rc < 0 { return Err(usd_last_error()); }
    return Ok(usd_read_i32_vec(&slot, 0) != 0);
  }
}

/// float3 / color3f / normal3f / point3f / vector3f -> 3-element Vec.
pub fn usd_prim_attr_vec3(prim: &UsdPrim, index: Int) -> Vec[Float64]
  requires: prim.handle != 0
  requires: index >= 0
{
  var out: Vec[Float64] = Vec[Float64].new();
  var c = 0;
  while c < 3 {
    var slot = usd_slot(8);
    unsafe {
      let packed = index * 3 + c;
      let rc = usdbridge_prim_attr_vec3_packed(prim.handle as Int64, packed as Int32,
                                               slot.as_mut_ptr()) as Int;
      if rc < 0 { return Vec[Float64].new(); }
      out.push(usd_f64_from_bits(ffi.ptr_read_u64_le(slot.as_mut_ptr())));
    }
    c = c + 1;
  }
  return out;
}

pub fn usd_prim_attr_string(prim: &UsdPrim, index: Int) -> Result[Str, UsdError]
  requires: prim.handle != 0
  requires: index >= 0
{
  var slot = usd_slot(4096);
  var rc = 0;
  unsafe {
    rc = usdbridge_prim_attr_string(prim.handle as Int64, index as Int32,
                              slot.as_mut_ptr(), 4096 as Int32) as Int;
  }
  return usd_copy_string(rc, &slot);
}

/// Scalar float by attribute name.  Complexity: O(attrs).
pub fn usd_prim_attr_float_by_name(prim: &UsdPrim, name: Str) -> Result[Float64, UsdError]
  requires: prim.handle != 0
  requires: name.len() > 0
{
  let i = usd_prim_attr_index(prim, name);
  if i < 0 {
    return Err(UsdError{ code: USD_ERR_ATTR_MISSING; message: "attribute missing: " + name });
  }
  return usd_prim_attr_float(prim, i);
}

/// Vec3 by attribute name.  Complexity: O(attrs).
pub fn usd_prim_attr_vec3_by_name(prim: &UsdPrim, name: Str) -> Vec[Float64]
  requires: prim.handle != 0
  requires: name.len() > 0
{
  let i = usd_prim_attr_index(prim, name);
  if i < 0 {
    return Vec[Float64].new();
  }
  return usd_prim_attr_vec3(prim, i);
}

// =========================================================================
// Mesh extraction
// =========================================================================

/// Mesh counts after validation (sum(counts)==len(indices), indices in range).
/// Complexity: O(faces + indices).
pub fn usd_mesh_info(prim: &UsdPrim) -> Result[UsdMeshInfo, UsdError]
  requires: prim.handle != 0
{
  var ps = usd_slot(4);
  var fs = usd_slot(4);
  var inds = usd_slot(4);
  unsafe {
    let rc = usdbridge_mesh_info(prim.handle as Int64, ps.as_mut_ptr(), fs.as_mut_ptr(),
                           inds.as_mut_ptr()) as Int;
    if rc < 0 { return Err(usd_last_error()); }
    return Ok(UsdMeshInfo{
      point_count: usd_read_i32_vec(&ps, 0),
      face_count: usd_read_i32_vec(&fs, 0),
      index_count: usd_read_i32_vec(&inds, 0),
    });
  }
}

/// Object-space points as xyz Float64 triples.  Complexity: O(points).
pub fn usd_mesh_points(prim: &UsdPrim) -> Vec[Float64]
  requires: prim.handle != 0
{
  let info = usd_mesh_info(prim);
  var out: Vec[Float64] = Vec[Float64].new();
  if !info.is_ok { return out; }
  let n = info.value.point_count;
  var pi = 0;
  while pi < n {
    var c = 0;
    while c < 3 {
      var slot = usd_slot(8);
      unsafe {
        let packed = pi * 3 + c;
        let rc = usdbridge_mesh_point_packed(prim.handle as Int64, packed as Int32,
                                             slot.as_mut_ptr()) as Int;
        if rc < 0 { return Vec[Float64].new(); }
        out.push(usd_f64_from_bits(ffi.ptr_read_u64_le(slot.as_mut_ptr())));
      }
      c = c + 1;
    }
    pi = pi + 1;
  }
  return out;
}

pub fn usd_mesh_face_counts(prim: &UsdPrim) -> Result[Vec[Int], UsdError]
  requires: prim.handle != 0
{
  let info = usd_mesh_info(prim);
  if !info.is_ok { return Err(info.error); }
  let n = info.value.face_count;
  var out: Vec[Int] = Vec[Int].new();
  if n == 0 { return Ok(out); }
  var raw = usd_slot(n * 4);
  unsafe {
    let rc = usdbridge_mesh_face_counts(prim.handle as Int64, raw.as_mut_ptr(), n as Int32) as Int;
    if rc < 0 { return Err(usd_last_error()); }
  }
  var i = 0;
  while i < n {
    out.push(usd_read_i32_vec(&raw, i * 4));
    i = i + 1;
  }
  return Ok(out);
}

/// Flattened face-vertex indices.  Complexity: O(indices).
pub fn usd_mesh_indices(prim: &UsdPrim) -> Result[Vec[Int], UsdError]
  requires: prim.handle != 0
{
  let info = usd_mesh_info(prim);
  if !info.is_ok { return Err(info.error); }
  let n = info.value.index_count;
  var out: Vec[Int] = Vec[Int].new();
  if n == 0 { return Ok(out); }
  var raw = usd_slot(n * 4);
  unsafe {
    let rc = usdbridge_mesh_indices(prim.handle as Int64, raw.as_mut_ptr(), n as Int32) as Int;
    if rc < 0 { return Err(usd_last_error()); }
  }
  var i = 0;
  while i < n {
    out.push(usd_read_i32_vec(&raw, i * 4));
    i = i + 1;
  }
  return Ok(out);
}

// =========================================================================
// Material surface subset
// =========================================================================

/// First `material:binding` target path.  Complexity: O(targets).
pub fn usd_material_binding(prim: &UsdPrim) -> Result[Str, UsdError]
  requires: prim.handle != 0
{
  var slot = usd_slot(4096);
  var rc = 0;
  unsafe {
    rc = usdbridge_material_binding(prim.handle as Int64, slot.as_mut_ptr(), 4096 as Int32) as Int;
  }
  return usd_copy_string(rc, &slot);
}

/// Connected `outputs:surface` shader prim path.  Complexity: O(connections).
pub fn usd_material_surface_shader_path(prim: &UsdPrim) -> Result[Str, UsdError]
  requires: prim.handle != 0
{
  var slot = usd_slot(4096);
  var rc = 0;
  unsafe {
    rc = usdbridge_material_surface_shader(prim.handle as Int64, slot.as_mut_ptr(), 4096 as Int32) as Int;
  }
  return usd_copy_string(rc, &slot);
}

/// Connected `outputs:surface` shader prim handle (owned).  Complexity: O(1).
pub fn usd_material_surface_shader_prim(prim: &UsdPrim) -> Result[UsdPrim, UsdError]
  requires: prim.handle != 0
{
  unsafe {
    let h = usdbridge_material_surface_shader_prim(prim.handle as Int64) as Int;
    if h == 0 { return Err(usd_last_error()); }
    return Ok(UsdPrim{ handle: h, stage: prim.stage });
  }
}

/// Shader `info:id` token (e.g. "UsdPreviewSurface").  Complexity: O(1).
pub fn usd_material_shader_id(shader: &UsdPrim) -> Result[Str, UsdError]
  requires: shader.handle != 0
{
  var slot = usd_slot(2048);
  var rc = 0;
  unsafe {
    rc = usdbridge_material_shader_id(shader.handle as Int64, slot.as_mut_ptr(), 2048 as Int32) as Int;
  }
  return usd_copy_string(rc, &slot);
}

/// Number of authored `inputs:*` attributes.  Complexity: O(attrs).
pub fn usd_material_input_count(shader: &UsdPrim) -> Result[Int, UsdError]
  requires: shader.handle != 0
{
  unsafe {
    let rc = usdbridge_material_input_count(shader.handle as Int64) as Int;
    if rc < 0 { return Err(usd_last_error()); }
    return Ok(rc);
  }
}

/// Input metadata (full name, Sdf type, connection state/path).
/// Complexity: O(attrs).
pub fn usd_material_input(shader: &UsdPrim, index: Int) -> Result[UsdMaterialInput, UsdError]
  requires: shader.handle != 0
  requires: index >= 0
{
  var name_slot = usd_slot(2048);
  var type_slot = usd_slot(2048);
  var conn_slot = usd_slot(4096);
  unsafe {
    let nrc = usdbridge_material_input_name(shader.handle as Int64, index as Int32,
                                      name_slot.as_mut_ptr(), 2048 as Int32) as Int;
    if nrc < 0 { return Err(usd_last_error()); }
    let trc = usdbridge_material_input_type(shader.handle as Int64, index as Int32,
                                      type_slot.as_mut_ptr(), 2048 as Int32) as Int;
    if trc < 0 { return Err(usd_last_error()); }
    let crc = usdbridge_material_input_connection(shader.handle as Int64, index as Int32,
                                            conn_slot.as_mut_ptr(), 4096 as Int32) as Int;
    if crc < 0 { return Err(usd_last_error()); }
    let connected = (usdbridge_material_input_connected(shader.handle as Int64, index as Int32) as Int) != 0;
    return Ok(UsdMaterialInput{
      name: Str::from_c_str(name_slot.as_mut_ptr()),
      type_name: Str::from_c_str(type_slot.as_mut_ptr()),
      connected: connected,
      connection: Str::from_c_str(conn_slot.as_mut_ptr()),
    });
  }
}

pub fn usd_material_input_name(shader: &UsdPrim, index: Int) -> Result[Str, UsdError]
  requires: shader.handle != 0
  requires: index >= 0
{
  var slot = usd_slot(2048);
  var rc = 0;
  unsafe {
    rc = usdbridge_material_input_name(shader.handle as Int64, index as Int32,
                                 slot.as_mut_ptr(), 2048 as Int32) as Int;
  }
  return usd_copy_string(rc, &slot);
}

pub fn usd_material_input_type(shader: &UsdPrim, index: Int) -> Result[Str, UsdError]
  requires: shader.handle != 0
  requires: index >= 0
{
  var slot = usd_slot(2048);
  var rc = 0;
  unsafe {
    rc = usdbridge_material_input_type(shader.handle as Int64, index as Int32,
                                 slot.as_mut_ptr(), 2048 as Int32) as Int;
  }
  return usd_copy_string(rc, &slot);
}

pub fn usd_material_input_connected(shader: &UsdPrim, index: Int) -> Result[Bool, UsdError]
  requires: shader.handle != 0
  requires: index >= 0
{
  unsafe {
    let rc = usdbridge_material_input_connected(shader.handle as Int64, index as Int32) as Int;
    if rc < 0 { return Err(usd_last_error()); }
    return Ok(rc != 0);
  }
}

pub fn usd_material_input_connection(shader: &UsdPrim, index: Int) -> Result[Str, UsdError]
  requires: shader.handle != 0
  requires: index >= 0
{
  var slot = usd_slot(4096);
  var rc = 0;
  unsafe {
    rc = usdbridge_material_input_connection(shader.handle as Int64, index as Int32,
                                       slot.as_mut_ptr(), 4096 as Int32) as Int;
  }
  return usd_copy_string(rc, &slot);
}

pub fn usd_material_input_float(shader: &UsdPrim, name: Str) -> Result[Float64, UsdError]
  requires: shader.handle != 0
  requires: name.len() > 0
{
  var slot = usd_slot(4);
  unsafe {
    let rc = usdbridge_material_input_float(shader.handle as Int64, name.c_str(),
                                      slot.as_mut_ptr()) as Int;
    if rc < 0 { return Err(usd_last_error()); }
    return Ok(usd_f32_from_bits(usd_read_u32_vec(&slot, 0)));
  }
}

pub fn usd_material_input_vec3(shader: &UsdPrim, name: Str) -> Vec[Float64]
  requires: shader.handle != 0
  requires: name.len() > 0
{
  var out: Vec[Float64] = Vec[Float64].new();
  var s0 = usd_slot(8);
  unsafe {
    let rc = usdbridge_material_input_vec3_x(shader.handle as Int64, name.c_str(),
                                             s0.as_mut_ptr()) as Int;
    if rc < 0 { return Vec[Float64].new(); }
    out.push(usd_f64_from_bits(ffi.ptr_read_u64_le(s0.as_mut_ptr())));
  }
  var s1 = usd_slot(8);
  unsafe {
    let rc = usdbridge_material_input_vec3_y(shader.handle as Int64, name.c_str(),
                                             s1.as_mut_ptr()) as Int;
    if rc < 0 { return Vec[Float64].new(); }
    out.push(usd_f64_from_bits(ffi.ptr_read_u64_le(s1.as_mut_ptr())));
  }
  var s2 = usd_slot(8);
  unsafe {
    let rc = usdbridge_material_input_vec3_z(shader.handle as Int64, name.c_str(),
                                             s2.as_mut_ptr()) as Int;
    if rc < 0 { return Vec[Float64].new(); }
    out.push(usd_f64_from_bits(ffi.ptr_read_u64_le(s2.as_mut_ptr())));
  }
  return out;
}

pub fn usd_material_input_string(shader: &UsdPrim, name: Str) -> Result[Str, UsdError]
  requires: shader.handle != 0
  requires: name.len() > 0
{
  var slot = usd_slot(4096);
  var rc = 0;
  unsafe {
    rc = usdbridge_material_input_string(shader.handle as Int64, name.c_str(),
                                   slot.as_mut_ptr(), 4096 as Int32) as Int;
  }
  return usd_copy_string(rc, &slot);
}

/// UsdPreviewSurface convenience: inputs:diffuseColor.  Complexity: O(attrs).
pub fn usd_material_diffuse_color(shader: &UsdPrim) -> Vec[Float64]
  requires: shader.handle != 0
{
  return usd_material_input_vec3(shader, "diffuseColor");
}

/// UsdPreviewSurface convenience: inputs:emissiveColor.  Complexity: O(attrs).
pub fn usd_material_emissive_color(shader: &UsdPrim) -> Vec[Float64]
  requires: shader.handle != 0
{
  return usd_material_input_vec3(shader, "emissiveColor");
}

/// UsdPreviewSurface convenience: inputs:metallic.  Complexity: O(attrs).
pub fn usd_material_metallic(shader: &UsdPrim) -> Result[Float64, UsdError]
  requires: shader.handle != 0
{
  return usd_material_input_float(shader, "metallic");
}

/// UsdPreviewSurface convenience: inputs:roughness.  Complexity: O(attrs).
pub fn usd_material_roughness(shader: &UsdPrim) -> Result[Float64, UsdError]
  requires: shader.handle != 0
{
  return usd_material_input_float(shader, "roughness");
}

/// UsdPreviewSurface convenience: inputs:opacity.  Complexity: O(attrs).
pub fn usd_material_opacity(shader: &UsdPrim) -> Result[Float64, UsdError]
  requires: shader.handle != 0
{
  return usd_material_input_float(shader, "opacity");
}

/// UsdPreviewSurface convenience: inputs:ior.  Complexity: O(attrs).
pub fn usd_material_ior(shader: &UsdPrim) -> Result[Float64, UsdError]
  requires: shader.handle != 0
{
  return usd_material_input_float(shader, "ior");
}

/// UsdPreviewSurface convenience: inputs:useSpecularWorkflow (0/1).
/// Complexity: O(attrs).
pub fn usd_material_use_specular_workflow(shader: &UsdPrim) -> Result[Bool, UsdError]
  requires: shader.handle != 0
{
  let i = usd_prim_attr_index(shader, "inputs:useSpecularWorkflow");
  if i < 0 {
    return Err(UsdError{ code: USD_ERR_ATTR_MISSING;
                         message: "material input missing: useSpecularWorkflow" });
  }
  let v = usd_prim_attr_int(shader, i);
  if !v.is_ok { return Err(v.error); }
  return Ok(v.value != 0);
}

pub fn usd_attr_time_count(prim: &UsdPrim, name: Str) -> Result[Int, UsdError]
  requires: prim.handle != 0
  requires: name.len() > 0
{
  unsafe {
    let rc = usdbridge_attr_time_count(prim.handle as Int64, name.c_str()) as Int;
    if rc < 0 { return Err(usd_last_error()); }
    return Ok(rc);
  }
}

/// Time of the i-th sample.  Complexity: O(samples).
pub fn usd_attr_time_at(prim: &UsdPrim, name: Str, index: Int) -> Result[Float64, UsdError]
  requires: prim.handle != 0
  requires: name.len() > 0
  requires: index >= 0
{
  var slot = usd_slot(8);
  unsafe {
    let rc = usdbridge_attr_time_at(prim.handle as Int64, name.c_str(), index as Int32,
                              slot.as_mut_ptr()) as Int;
    if rc < 0 { return Err(usd_last_error()); }
    return Ok(usd_f64_from_bits(ffi.ptr_read_u64_le(slot.as_mut_ptr())));
  }
}

/// Time range + count for a named attribute.  Complexity: O(samples).
pub fn usd_attr_time_samples(prim: &UsdPrim, name: Str) -> Result[UsdTimeSamples, UsdError]
  requires: prim.handle != 0
  requires: name.len() > 0
{
  let count = usd_attr_time_count(prim, name);
  if !count.is_ok { return Err(count.error); }
  var mins = usd_slot(8);
  var maxs = usd_slot(8);
  unsafe {
    let rc = usdbridge_attr_time_bounds(prim.handle as Int64, name.c_str(),
                                  mins.as_mut_ptr(), maxs.as_mut_ptr()) as Int;
    if rc < 0 { return Err(usd_last_error()); }
  }
  return Ok(UsdTimeSamples{
    count: count.value,
    min_time: usd_f64_from_bits(ffi.ptr_read_u64_le(mins.as_mut_ptr())),
    max_time: usd_f64_from_bits(ffi.ptr_read_u64_le(maxs.as_mut_ptr())),
  });
}

/// double/float value at a time.  Complexity: O(samples).
pub fn usd_attr_double_at(prim: &UsdPrim, name: Str, time: Float64) -> Result[Float64, UsdError]
  requires: prim.handle != 0
  requires: name.len() > 0
{
  var slot = usd_slot(8);
  unsafe {
    let rc = usdbridge_attr_double_at(prim.handle as Int64, name.c_str(), time,
                                slot.as_mut_ptr()) as Int;
    if rc < 0 { return Err(usd_last_error()); }
    return Ok(usd_f64_from_bits(ffi.ptr_read_u64_le(slot.as_mut_ptr())));
  }
}

/// float/double value at a time (narrowed to Float64).  Complexity: O(samples).
pub fn usd_attr_float_at(prim: &UsdPrim, name: Str, time: Float64) -> Result[Float64, UsdError]
  requires: prim.handle != 0
  requires: name.len() > 0
{
  var slot = usd_slot(4);
  unsafe {
    let rc = usdbridge_attr_float_at(prim.handle as Int64, name.c_str(), time,
                               slot.as_mut_ptr()) as Int;
    if rc < 0 { return Err(usd_last_error()); }
    return Ok(usd_f32_from_bits(usd_read_u32_vec(&slot, 0)));
  }
}

/// Vec3 value at a time.  Complexity: O(samples).
pub fn usd_attr_vec3_at(prim: &UsdPrim, name: Str, time: Float64) -> Vec[Float64]
  requires: prim.handle != 0
  requires: name.len() > 0
{
  var out: Vec[Float64] = Vec[Float64].new();
  var s0 = usd_slot(8);
  unsafe {
    let rc = usdbridge_attr_vec3_at_x(prim.handle as Int64, name.c_str(), time,
                                      s0.as_mut_ptr()) as Int;
    if rc < 0 { return Vec[Float64].new(); }
    out.push(usd_f64_from_bits(ffi.ptr_read_u64_le(s0.as_mut_ptr())));
  }
  var s1 = usd_slot(8);
  unsafe {
    let rc = usdbridge_attr_vec3_at_y(prim.handle as Int64, name.c_str(), time,
                                      s1.as_mut_ptr()) as Int;
    if rc < 0 { return Vec[Float64].new(); }
    out.push(usd_f64_from_bits(ffi.ptr_read_u64_le(s1.as_mut_ptr())));
  }
  var s2 = usd_slot(8);
  unsafe {
    let rc = usdbridge_attr_vec3_at_z(prim.handle as Int64, name.c_str(), time,
                                      s2.as_mut_ptr()) as Int;
    if rc < 0 { return Vec[Float64].new(); }
    out.push(usd_f64_from_bits(ffi.ptr_read_u64_le(s2.as_mut_ptr())));
  }
  return out;
}

pub fn usd_attr_float_sample(prim: &UsdPrim, name: Str, index: Int) -> Result[Float64, UsdError]
  requires: prim.handle != 0
  requires: name.len() > 0
  requires: index >= 0
{
  var slot = usd_slot(4);
  unsafe {
    let rc = usdbridge_attr_float_sample(prim.handle as Int64, name.c_str(), index as Int32,
                                   slot.as_mut_ptr()) as Int;
    if rc < 0 { return Err(usd_last_error()); }
    return Ok(usd_f32_from_bits(usd_read_u32_vec(&slot, 0)));
  }
}

























