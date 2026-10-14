// XIOM -- xiom.xess: Intel XeSS (libxess.dll / libxess_dx11.dll) bindings via
// dynamic loader.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// DECISION (BINDINGS lane, closed-SDK doctrine, 2026-10-14): **system-library
// SKIP path only** -- no Intel SDK libraries or headers are vendored (the XeSS
// SDK License forbids modification of the SDK and does not license the headers
// for redistribution; see PROVENANCE.md).  The loader resolves the Windows
// sonames `libxess.dll` (SR core: generic + D3D12 + Vulkan + debug surface)
// and, when present, the D3D11 companion `libxess_dx11.dll`; the suite reports
// SKIP when the core is absent, so CI without the runtime stays green.  A
// local runtime image may be placed on PATH for present-path proof; hashes are
// recorded in SPEC.md as optional local samples (nothing committed).
//
// The declared surface is the PUBLIC XeSS 3.0.2 header set as pinned in
// PROVENANCE.md: xess.h (18), xess_d3d12.h (5), xess_d3d12_debug.h (2),
// xess_debug.h (3), xess_vk.h (8), xess_vk_debug.h (1), xess_d3d11.h (4)
// = 41 entry points, 100% exposed here.  Undocumented non-header exports of
// libxess.dll (INTC_D3D11_Xess*, xessAIL*, xessTrinity*, context-parameter
// accessors) are explicit non-goals (SPEC.md section 3).
//
// All XIOM `unsafe`/`extern` live in this single module (G5); every call is a
// fn-pointer cast over `xiom.ffi.dl`.
//
// Classification:
//   XESS_LOAD_ABSENT -> no libxess.dll resolved              -> SKIP
//   XESS_LOAD_ABI    -> library loaded, entry points missing -> FAIL
//
// FFI discipline (v0.64.4 findings B-10/B-12/B-17/B-20/B-21/B-23/B-24/B-25/
// B-26):
//   * handles and foreign pointers cross as `Int` params in the fn-pointer
//     casts (B-25: never `Int as *UInt8`; handles stay Int end to end);
//   * out-params use one XIOM-owned slot each, read byte-indexed (B-17/B-24);
//     sized slots are push-loop built, never `Vec.with_len` (shaderc audit);
//   * no foreign-pointer reads and no pointer arithmetic (B-20/B-17);
//   * nullable C args are Int `0` (B-23: never the bare `null` literal);
//   * no fp returns through cast-calls (B-12): every call returns Int32 and
//     float data is read out of owned slots; f32 args are `Float32` scalars;
//   * no `&mut` of Result/struct-return temps (B-21); builders mutate locals;
//   * flat outcome structs everywhere (B-26: no `Result[Option[T]]`);
//   * Str equality only via `string.str_compare`.
//
// Coverage (0.1.0): 41/41 declared entries -- 37 on libxess.dll + 4 on
// libxess_dx11.dll.  See SPEC.md section 4 for the export matrix.

module xiom.xess

use xiom.ffi.dl;
use xiom.convert;
use xiom.num.float;

// =========================================================================
// Sonames, classification, coverage counts
// =========================================================================

/// XeSS Super Resolution core runtime (generic API + D3D12 + Vulkan + the
/// public debug surface).
pub const XESS_SONAME: Str = "libxess.dll";

/// D3D11 companion runtime (carries the four xess_d3d11.h entry points).
pub const XESS_DX11_SONAME: Str = "libxess_dx11.dll";

/// No candidate library resolved -> the caller reports SKIP.
pub const XESS_LOAD_ABSENT: Int = 0;

/// A library loaded but the declared entry points are missing -> FAIL
/// (a real install/SDK mismatch).
pub const XESS_LOAD_ABI: Int = 1;

/// Declared public entry-point count (all public headers at the 3.0.2 pin).
pub const XESS_ENTRY_COUNT: Int = 41;

/// Declared entries carried by `libxess.dll` (41 - the 4 D3D11 entries).
pub const XESS_CORE_ENTRY_COUNT: Int = 37;

/// Declared entries carried by `libxess_dx11.dll`.
pub const XESS_DX11_ENTRY_COUNT: Int = 4;

// =========================================================================
// xess_quality_settings_t (xess.h)
// =========================================================================

pub const XESS_QUALITY_SETTING_ULTRA_PERFORMANCE: Int = 100;
pub const XESS_QUALITY_SETTING_PERFORMANCE: Int = 101;
pub const XESS_QUALITY_SETTING_BALANCED: Int = 102;
pub const XESS_QUALITY_SETTING_QUALITY: Int = 103;
pub const XESS_QUALITY_SETTING_ULTRA_QUALITY: Int = 104;
pub const XESS_QUALITY_SETTING_ULTRA_QUALITY_PLUS: Int = 105;
pub const XESS_QUALITY_SETTING_AA: Int = 106;

// =========================================================================
// xess_init_flags_t (xess.h)
// =========================================================================

pub const XESS_INIT_FLAG_NONE: Int = 0;
pub const XESS_INIT_FLAG_HIGH_RES_MV: Int = 1;
pub const XESS_INIT_FLAG_INVERTED_DEPTH: Int = 2;
pub const XESS_INIT_FLAG_EXPOSURE_SCALE_TEXTURE: Int = 4;
pub const XESS_INIT_FLAG_RESPONSIVE_PIXEL_MASK: Int = 8;
pub const XESS_INIT_FLAG_USE_NDC_VELOCITY: Int = 16;
pub const XESS_INIT_FLAG_EXTERNAL_DESCRIPTOR_HEAP: Int = 32;
pub const XESS_INIT_FLAG_LDR_INPUT_COLOR: Int = 64;
pub const XESS_INIT_FLAG_JITTERED_MV: Int = 128;
pub const XESS_INIT_FLAG_ENABLE_AUTOEXPOSURE: Int = 256;

/// `XESS_DEBUG_ENABLE_PROFILING` (xess_debug.h): add to initFlags to enable
/// profiling-data collection.
pub const XESS_DEBUG_ENABLE_PROFILING: Int = 1073741824;

// =========================================================================
// xess_result_t (xess.h)
// =========================================================================

pub const XESS_RESULT_WARNING_NONEXISTING_FOLDER: Int = 1;
pub const XESS_RESULT_WARNING_OLD_DRIVER: Int = 2;
pub const XESS_RESULT_SUCCESS: Int = 0;
pub const XESS_RESULT_ERROR_UNSUPPORTED_DEVICE: Int = -1;
pub const XESS_RESULT_ERROR_UNSUPPORTED_DRIVER: Int = -2;
pub const XESS_RESULT_ERROR_UNINITIALIZED: Int = -3;
pub const XESS_RESULT_ERROR_INVALID_ARGUMENT: Int = -4;
pub const XESS_RESULT_ERROR_DEVICE_OUT_OF_MEMORY: Int = -5;
pub const XESS_RESULT_ERROR_DEVICE: Int = -6;
pub const XESS_RESULT_ERROR_NOT_IMPLEMENTED: Int = -7;
pub const XESS_RESULT_ERROR_INVALID_CONTEXT: Int = -8;
pub const XESS_RESULT_ERROR_OPERATION_IN_PROGRESS: Int = -9;
pub const XESS_RESULT_ERROR_UNSUPPORTED: Int = -10;
pub const XESS_RESULT_ERROR_CANT_LOAD_LIBRARY: Int = -11;
pub const XESS_RESULT_ERROR_WRONG_CALL_ORDER: Int = -12;
pub const XESS_RESULT_ERROR_UNKNOWN: Int = -1000;

// =========================================================================
// Logging levels, network models, dump bits (debug headers)
// =========================================================================

pub const XESS_LOGGING_LEVEL_DEBUG: Int = 0;
pub const XESS_LOGGING_LEVEL_INFO: Int = 1;
pub const XESS_LOGGING_LEVEL_WARNING: Int = 2;
pub const XESS_LOGGING_LEVEL_ERROR: Int = 3;

pub const XESS_NETWORK_MODEL_KPSS: Int = 0;
pub const XESS_NETWORK_MODEL_SPLAT: Int = 1;
pub const XESS_NETWORK_MODEL_3: Int = 2;
pub const XESS_NETWORK_MODEL_4: Int = 3;
pub const XESS_NETWORK_MODEL_5: Int = 4;
pub const XESS_NETWORK_MODEL_6: Int = 5;
pub const XESS_NETWORK_MODEL_UNKNOWN: Int = 2147483647;

pub const XESS_DUMP_INPUT_COLOR: Int = 1;
pub const XESS_DUMP_INPUT_VELOCITY: Int = 2;
pub const XESS_DUMP_INPUT_DEPTH: Int = 4;
pub const XESS_DUMP_INPUT_EXPOSURE_SCALE: Int = 8;
pub const XESS_DUMP_INPUT_RESPONSIVE_PIXEL_MASK: Int = 16;
pub const XESS_DUMP_OUTPUT: Int = 32;
pub const XESS_DUMP_HISTORY: Int = 64;
pub const XESS_DUMP_EXECUTION_PARAMETERS: Int = 128;
pub const XESS_DUMP_ALL_INPUTS: Int = 159;
pub const XESS_DUMP_ALL: Int = 2147483647;

// =========================================================================
// Pinned struct layouts (public headers; XESS_PACK_B = pack(8))
// =========================================================================

/// `xess_version_t`: 4 x uint16 (8 bytes).
pub type XessVersion = {
  major: Int;
  minor: Int;
  patch: Int;
  reserved: Int;
}

/// `xess_properties_t` (24 bytes): u32 @0, u64 @8, u64 @16.
pub type XessProperties = {
  required_descriptor_count: Int;
  temp_buffer_heap_size: Int;
  temp_texture_heap_size: Int;
}

/// `xess_d3d12_init_params_t` (64 bytes).
pub type XessD3D12InitParams = {
  output_width: Int;
  output_height: Int;
  quality: Int;
  init_flags: Int;
  creation_node_mask: Int;
  visible_node_mask: Int;
  temp_buffer_heap: Int;
  buffer_heap_offset: Int;
  temp_texture_heap: Int;
  texture_heap_offset: Int;
  pipeline_library: Int;
}

/// `xess_d3d12_execute_params_t` (136 bytes).
pub type XessD3D12ExecuteParams = {
  color_texture: Int;
  velocity_texture: Int;
  depth_texture: Int;
  exposure_scale_texture: Int;
  responsive_pixel_mask_texture: Int;
  output_texture: Int;
  jitter_offset_x: Float64;
  jitter_offset_y: Float64;
  exposure_scale: Float64;
  reset_history: Int;
  input_width: Int;
  input_height: Int;
  input_color_base_x: Int;
  input_color_base_y: Int;
  input_motion_vector_base_x: Int;
  input_motion_vector_base_y: Int;
  input_depth_base_x: Int;
  input_depth_base_y: Int;
  input_responsive_mask_base_x: Int;
  input_responsive_mask_base_y: Int;
  output_color_base_x: Int;
  output_color_base_y: Int;
  descriptor_heap: Int;
  descriptor_heap_offset: Int;
}

/// `xess_vk_image_view_info` (48 bytes) with the VkImageSubresourceRange
/// fields flattened (no Vulkan dependency).
pub type XessVkImageViewInfo = {
  image_view: Int;
  image: Int;
  aspect_mask: Int;
  base_mip_level: Int;
  level_count: Int;
  base_array_layer: Int;
  layer_count: Int;
  format: Int;
  width: Int;
  height: Int;
}

/// `xess_vk_init_params_t` (64 bytes).
pub type XessVkInitParams = {
  output_width: Int;
  output_height: Int;
  quality: Int;
  init_flags: Int;
  creation_node_mask: Int;
  visible_node_mask: Int;
  temp_buffer_heap: Int;
  buffer_heap_offset: Int;
  temp_texture_heap: Int;
  texture_heap_offset: Int;
  pipeline_cache: Int;
}

/// `xess_vk_execute_params_t` (360 bytes).
pub type XessVkExecuteParams = {
  color_texture: XessVkImageViewInfo;
  velocity_texture: XessVkImageViewInfo;
  depth_texture: XessVkImageViewInfo;
  exposure_scale_texture: XessVkImageViewInfo;
  responsive_pixel_mask_texture: XessVkImageViewInfo;
  output_texture: XessVkImageViewInfo;
  jitter_offset_x: Float64;
  jitter_offset_y: Float64;
  exposure_scale: Float64;
  reset_history: Int;
  input_width: Int;
  input_height: Int;
  input_color_base_x: Int;
  input_color_base_y: Int;
  input_motion_vector_base_x: Int;
  input_motion_vector_base_y: Int;
  input_depth_base_x: Int;
  input_depth_base_y: Int;
  input_responsive_mask_base_x: Int;
  input_responsive_mask_base_y: Int;
  output_color_base_x: Int;
  output_color_base_y: Int;
}

/// `xess_d3d11_init_params_t` (16 bytes).
pub type XessD3D11InitParams = {
  output_width: Int;
  output_height: Int;
  quality: Int;
  init_flags: Int;
}

/// `xess_d3d11_execute_params_t` (120 bytes).
pub type XessD3D11ExecuteParams = {
  color_texture: Int;
  velocity_texture: Int;
  depth_texture: Int;
  exposure_scale_texture: Int;
  responsive_pixel_mask_texture: Int;
  output_texture: Int;
  jitter_offset_x: Float64;
  jitter_offset_y: Float64;
  exposure_scale: Float64;
  reset_history: Int;
  input_width: Int;
  input_height: Int;
  input_color_base_x: Int;
  input_color_base_y: Int;
  input_motion_vector_base_x: Int;
  input_motion_vector_base_y: Int;
  input_depth_base_x: Int;
  input_depth_base_y: Int;
  input_responsive_mask_base_x: Int;
  input_responsive_mask_base_y: Int;
  output_color_base_x: Int;
  output_color_base_y: Int;
}

/// `xess_dump_parameters_t` (24 bytes): path ptr @0, u32 @8, u32 @12,
/// u32 mask @16.
pub type XessDumpParameters = {
  path: Str;
  frame_idx: Int;
  frame_count: Int;
  dump_elements_mask: Int;
}

// =========================================================================
// Outcome types (flat; B-26)
// =========================================================================

pub type XessLoadError = {
  kind: Int;
  message: Str;
}

/// rc-only outcome (`ok` = rc == XESS_RESULT_SUCCESS; warnings stay visible
/// in `rc`, e.g. xessIsOptimalDriver rc 2 = OLD_DRIVER).
pub type XessRcOutcome = {
  ok: Bool;
  rc: Int;
}

pub type XessVersionOutcome = {
  ok: Bool;
  rc: Int;
  version: XessVersion;
}

pub type Xess2DOutcome = {
  ok: Bool;
  rc: Int;
  x: Int;
  y: Int;
}

pub type XessOptimalOutcome = {
  ok: Bool;
  rc: Int;
  optimal_x: Int;
  optimal_y: Int;
  min_x: Int;
  min_y: Int;
  max_x: Int;
  max_y: Int;
}

pub type XessPropertiesOutcome = {
  ok: Bool;
  rc: Int;
  properties: XessProperties;
}

/// Two f32 values decoded to Float64 (non-finite decodes to 0.0).
pub type XessScaleOutcome = {
  ok: Bool;
  rc: Int;
  x: Float64;
  y: Float64;
}

/// One f32 value decoded to Float64 (non-finite decodes to 0.0).
pub type XessScalarOutcome = {
  ok: Bool;
  rc: Int;
  value: Float64;
}

pub type XessHandleOutcome = {
  ok: Bool;
  rc: Int;
  handle: Int;
}

pub type XessPtrOutcome = {
  ok: Bool;
  rc: Int;
  ptr: Int;
}

pub type XessD3D12InitParamsOutcome = {
  ok: Bool;
  rc: Int;
  params: XessD3D12InitParams;
}

pub type XessVkInitParamsOutcome = {
  ok: Bool;
  rc: Int;
  params: XessVkInitParams;
}

pub type XessD3D11InitParamsOutcome = {
  ok: Bool;
  rc: Int;
  params: XessD3D11InitParams;
}

pub type XessVkInstanceExtensionsOutcome = {
  ok: Bool;
  rc: Int;
  count: Int;
  list_ptr: Int;
  min_vk_api_version: Int;
}

pub type XessVkDeviceExtensionsOutcome = {
  ok: Bool;
  rc: Int;
  count: Int;
  list_ptr: Int;
}

// =========================================================================
// Slot helpers (owned Vec[UInt8] buffers; push-loop built -- never
// Vec.with_len, see the shaderc audit; byte-indexed reads per B-17/B-24)
// =========================================================================

/// Zeroed slot of `n` bytes.  O(n).
pub fn xess_slot(n: Int) -> Vec[UInt8]
  requires: n > 0
{
  var s: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < n {
    s.push(0 as UInt8);
    i = i + 1;
  }
  return s;
}

/// Little-endian u16 store.  O(1).
pub fn xess_wr_u16(buf: &mut Vec[UInt8], off: Int, v: Int)
  requires: off >= 0
  requires: buf.len() >= off + 2
{
  buf[off + 0] = (v & 255) as UInt8;
  buf[off + 1] = ((v >> 8) & 255) as UInt8;
}

/// Little-endian u32 store.  O(1).
pub fn xess_wr_u32(buf: &mut Vec[UInt8], off: Int, v: Int)
  requires: off >= 0
  requires: buf.len() >= off + 4
{
  buf[off + 0] = (v & 255) as UInt8;
  buf[off + 1] = ((v >> 8) & 255) as UInt8;
  buf[off + 2] = ((v >> 16) & 255) as UInt8;
  buf[off + 3] = ((v >> 24) & 255) as UInt8;
}

/// Little-endian u64 store (also used for pointers/offsets, faithful because
/// pointer -> Int is value-preserving; B-25 only breaks Int -> pointer).
/// O(1).
pub fn xess_wr_u64(buf: &mut Vec[UInt8], off: Int, v: Int)
  requires: off >= 0
  requires: buf.len() >= off + 8
{
  xess_wr_u32(buf, off, v & 4294967295);
  xess_wr_u32(buf, off + 4, (v >> 32) & 4294967295);
}

/// IEEE-754 binary32 store from a Float64 value (round-to-nearest-even,
/// pure integer math on the exact f64 bit pattern).  O(1).
pub fn xess_wr_f32(buf: &mut Vec[UInt8], off: Int, v: Float64)
  requires: off >= 0
  requires: buf.len() >= off + 4
{
  xess_wr_u32(buf, off, xess_f32_bits_from_f64(v));
}

/// Little-endian u16 read.  O(1).
pub fn xess_rd_u16(buf: &Vec[UInt8], off: Int) -> Int
  requires: off >= 0
  requires: buf.len() >= off + 2
{
  return (buf[off + 0] as Int) | ((buf[off + 1] as Int) << 8);
}

/// Little-endian u32 read.  O(1).
pub fn xess_rd_u32(buf: &Vec[UInt8], off: Int) -> Int
  requires: off >= 0
  requires: buf.len() >= off + 4
{
  return (buf[off + 0] as Int)
    | ((buf[off + 1] as Int) << 8)
    | ((buf[off + 2] as Int) << 16)
    | ((buf[off + 3] as Int) << 24);
}

/// Little-endian u64 read (also pointers/offsets).  O(1).
pub fn xess_rd_u64(buf: &Vec[UInt8], off: Int) -> Int
  requires: off >= 0
  requires: buf.len() >= off + 8
{
  let lo = xess_rd_u32(buf, off);
  let hi = xess_rd_u32(buf, off + 4);
  return lo | (hi << 32);
}

/// IEEE-754 binary32 read from a slot, decoded to Float64 by pure arithmetic
/// (B-12 discipline: no fp cast-call returns).  Non-finite decodes to 0.0
/// (documented).  O(149).
pub fn xess_rd_f32(buf: &Vec[UInt8], off: Int) -> Float64
  requires: off >= 0
  requires: buf.len() >= off + 4
{
  return xess_f32_from_bits(xess_rd_u32(buf, off));
}

// =========================================================================
// f32 codec (pure arithmetic; exact for all finite values)
// =========================================================================

/// 2^e for -1074 <= e <= 1024 by exact float arithmetic.  O(|e|).
fn xess_pow2i(e: Int) -> Float64
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

/// IEEE-754 binary32 bit pattern -> Float64 (exact: every f32 is exactly
/// representable in f64).  +Inf/-Inf/NaN decode to 0.0.  O(149).
pub fn xess_f32_from_bits(bits: Int) -> Float64
  requires: bits >= 0
  requires: bits <= 4294967295
{
  let sign = if ((bits >> 31) & 1) == 1 { -1.0 } else { 1.0 };
  let exp = (bits >> 23) & 255;
  let frac = bits & 8388607;
  if exp == 0 {
    if frac == 0 { return sign * 0.0; }
    return sign * (frac as Float64) * xess_pow2i(-149);
  }
  if exp == 255 { return 0.0; }
  return sign * (1.0 + (frac as Float64) / 8388608.0) * xess_pow2i(exp - 127);
}

/// Float64 -> IEEE-754 binary32 bit pattern, round-to-nearest-even, exact
/// integer math on `float_bits` (an exact bitcast on v0.64.0+).  NaN ->
/// canonical quiet NaN 0x7FC00000; overflow -> +-Inf.  O(1).
pub fn xess_f32_bits_from_f64(v: Float64) -> Int
  requires: true
{
  let b = float.float_bits(v);
  let sign_bit = if b < 0 { 1 } else { 0 };
  let sgn_bits = sign_bit << 31;
  let exp = (b >> 52) & 2047;
  let frac = b & 4503599627370495;

  if exp == 2047 {
    if frac == 0 { return sgn_bits | 2139095040; }
    return sgn_bits | 2143289344;
  }
  if exp == 0 && frac == 0 { return sgn_bits; }

  // value = s * 2^e2, exact.
  var s = frac;
  var e2 = -1074;
  if exp != 0 {
    s = 4503599627370496 + frac;
    e2 = exp - 1075;
  }

  // Bit length of s.
  var l = 0;
  var t = s;
  while t > 0 {
    l = l + 1;
    t = t >> 1;
  }
  let k = (l - 1) + e2;

  if k >= -126 {
    // Normal f32: 24-bit significand, RNE over the dropped bits.
    var q = 0;
    if l > 24 {
      let drop = l - 24;
      q = s >> drop;
      let rem = s & ((1 << drop) - 1);
      let half = 1 << (drop - 1);
      if rem > half { q = q + 1; }
      elif rem == half {
        if (q & 1) == 1 { q = q + 1; }
      }
    } else {
      q = s << (24 - l);
    }
    var kk = k;
    if q >= 16777216 { q = 8388608; kk = kk + 1; }
    if kk > 127 { return sgn_bits | 2139095040; }
    return sgn_bits | ((kk + 127) << 23) | (q - 8388608);
  }

  // Subnormal f32 (or zero): m = round(s * 2^(e2 + 149)) in [0, 2^24).
  let t2 = e2 + 149;
  var m = 0;
  if t2 >= 0 {
    m = s << t2;
  } elif t2 > -54 {
    let drop = 0 - t2;
    m = s >> drop;
    let rem = s & ((1 << drop) - 1);
    let half = 1 << (drop - 1);
    if rem > half { m = m + 1; }
    elif rem == half {
      if (m & 1) == 1 { m = m + 1; }
    }
  } else {
    // |value| < 2^-150: every discarded bit is below half a subnormal unit.
    m = 0;
  }
  if m >= 8388608 { return sgn_bits | 8388608; }
  if m == 0 { return sgn_bits; }
  return sgn_bits | m;
}

// =========================================================================
// Loader
// =========================================================================

/// A loaded XeSS runtime: the core handle plus (when present) the D3D11
/// companion handle and the 41 resolved entry points.  Owned by the caller;
/// release with `xess_close`.
pub type XessLibrary = {
  h_core: Int;
  h_dx11: Int;
  has_dx11: Bool;
  name_core: Str;
  name_dx11: Str;
  p_get_version: Int;
  p_get_intel_xefx_version: Int;
  p_get_properties: Int;
  p_get_input_resolution: Int;
  p_get_optimal_input_resolution: Int;
  p_get_jitter_scale: Int;
  p_get_velocity_scale: Int;
  p_destroy_context: Int;
  p_set_jitter_scale: Int;
  p_set_velocity_scale: Int;
  p_set_exposure_multiplier: Int;
  p_get_exposure_multiplier: Int;
  p_set_max_responsive_mask_value: Int;
  p_get_max_responsive_mask_value: Int;
  p_set_logging_callback: Int;
  p_is_optimal_driver: Int;
  p_force_legacy_scale_factors: Int;
  p_get_pipeline_build_status: Int;
  p_d3d12_create_context: Int;
  p_d3d12_build_pipelines: Int;
  p_d3d12_init: Int;
  p_d3d12_get_init_params: Int;
  p_d3d12_execute: Int;
  p_d3d12_get_resources_to_dump: Int;
  p_d3d12_get_profiling_data: Int;
  p_vk_get_required_instance_extensions: Int;
  p_vk_get_required_device_extensions: Int;
  p_vk_get_required_device_features: Int;
  p_vk_create_context: Int;
  p_vk_build_pipelines: Int;
  p_vk_init: Int;
  p_vk_get_init_params: Int;
  p_vk_execute: Int;
  p_vk_get_resources_to_dump: Int;
  p_select_network_model: Int;
  p_start_dump: Int;
  p_get_profiling_data: Int;
  p_d3d11_create_context: Int;
  p_d3d11_init: Int;
  p_d3d11_get_init_params: Int;
  p_d3d11_execute: Int;
}

/// The 37 declared entry-point names carried by `libxess.dll`, in struct
/// field order.  O(37).
pub fn xess_entry_names_core() -> Vec[Str]
  requires: true
{
  var v: Vec[Str] = Vec[Str].new();
  v.push("xessGetVersion");
  v.push("xessGetIntelXeFXVersion");
  v.push("xessGetProperties");
  v.push("xessGetInputResolution");
  v.push("xessGetOptimalInputResolution");
  v.push("xessGetJitterScale");
  v.push("xessGetVelocityScale");
  v.push("xessDestroyContext");
  v.push("xessSetJitterScale");
  v.push("xessSetVelocityScale");
  v.push("xessSetExposureMultiplier");
  v.push("xessGetExposureMultiplier");
  v.push("xessSetMaxResponsiveMaskValue");
  v.push("xessGetMaxResponsiveMaskValue");
  v.push("xessSetLoggingCallback");
  v.push("xessIsOptimalDriver");
  v.push("xessForceLegacyScaleFactors");
  v.push("xessGetPipelineBuildStatus");
  v.push("xessD3D12CreateContext");
  v.push("xessD3D12BuildPipelines");
  v.push("xessD3D12Init");
  v.push("xessD3D12GetInitParams");
  v.push("xessD3D12Execute");
  v.push("xessD3D12GetResourcesToDump");
  v.push("xessD3D12GetProfilingData");
  v.push("xessVKGetRequiredInstanceExtensions");
  v.push("xessVKGetRequiredDeviceExtensions");
  v.push("xessVKGetRequiredDeviceFeatures");
  v.push("xessVKCreateContext");
  v.push("xessVKBuildPipelines");
  v.push("xessVKInit");
  v.push("xessVKGetInitParams");
  v.push("xessVKExecute");
  v.push("xessVKGetResourcesToDump");
  v.push("xessSelectNetworkModel");
  v.push("xessStartDump");
  v.push("xessGetProfilingData");
  return v;
}

/// The 4 declared entry-point names carried by `libxess_dx11.dll`.  O(4).
pub fn xess_entry_names_dx11() -> Vec[Str]
  requires: true
{
  var v: Vec[Str] = Vec[Str].new();
  v.push("xessD3D11CreateContext");
  v.push("xessD3D11Init");
  v.push("xessD3D11GetInitParams");
  v.push("xessD3D11Execute");
  return v;
}

/// Resolve one entry point or fail with a typed ABI error.  O(1).
fn xess_need(h: Int, name: Str) -> Result[Int, XessLoadError]
  requires: h != 0
  requires: name.len() > 0
{
  let s = dl.dl_sym(h, name);
  if !s.is_ok {
    return Err(XessLoadError{ kind: XESS_LOAD_ABI; message: name + ": " + s.error });
  }
  return Ok(s.value);
}

/// Close both handles (used on loader failure paths).  O(1).
fn xess_close_handles(h_core: Int, h_dx11: Int)
  requires: h_core != 0
{
  var ig1 = dl.dl_close(h_core);
  if h_dx11 != 0 {
    var ig2 = dl.dl_close(h_dx11);
  }
}

/// Load an explicitly named runtime pair.  `name_core` must resolve and carry
/// all 37 core entries; `name_dx11` is an optional companion (an empty name
/// or a failed open leaves `has_dx11 = false` -- it is not an error).  Bogus
/// names exercise the ABSENT/ABI classification deterministically.  O(41).
pub fn xess_load_named(name_core: Str, name_dx11: Str) -> Result[XessLibrary, XessLoadError]
  requires: name_core.len() > 0
{
  let r_core = dl.dl_open(name_core);
  if !r_core.is_ok {
    return Err(XessLoadError{ kind: XESS_LOAD_ABSENT; message: name_core + ": " + r_core.error });
  }
  let h_core: Int = r_core.value;

  var h_dx11: Int = 0;
  var has_dx11: Bool = false;
  if name_dx11.len() > 0 {
    let r_dx11 = dl.dl_open(name_dx11);
    if r_dx11.is_ok {
      h_dx11 = r_dx11.value;
      has_dx11 = true;
    }
  }

  let a1 = xess_need(h_core, "xessGetVersion");
  if !a1.is_ok { xess_close_handles(h_core, h_dx11); return Err(a1.error); }
  let a2 = xess_need(h_core, "xessGetIntelXeFXVersion");
  if !a2.is_ok { xess_close_handles(h_core, h_dx11); return Err(a2.error); }
  let a3 = xess_need(h_core, "xessGetProperties");
  if !a3.is_ok { xess_close_handles(h_core, h_dx11); return Err(a3.error); }
  let a4 = xess_need(h_core, "xessGetInputResolution");
  if !a4.is_ok { xess_close_handles(h_core, h_dx11); return Err(a4.error); }
  let a5 = xess_need(h_core, "xessGetOptimalInputResolution");
  if !a5.is_ok { xess_close_handles(h_core, h_dx11); return Err(a5.error); }
  let a6 = xess_need(h_core, "xessGetJitterScale");
  if !a6.is_ok { xess_close_handles(h_core, h_dx11); return Err(a6.error); }
  let a7 = xess_need(h_core, "xessGetVelocityScale");
  if !a7.is_ok { xess_close_handles(h_core, h_dx11); return Err(a7.error); }
  let a8 = xess_need(h_core, "xessDestroyContext");
  if !a8.is_ok { xess_close_handles(h_core, h_dx11); return Err(a8.error); }
  let a9 = xess_need(h_core, "xessSetJitterScale");
  if !a9.is_ok { xess_close_handles(h_core, h_dx11); return Err(a9.error); }
  let a10 = xess_need(h_core, "xessSetVelocityScale");
  if !a10.is_ok { xess_close_handles(h_core, h_dx11); return Err(a10.error); }
  let a11 = xess_need(h_core, "xessSetExposureMultiplier");
  if !a11.is_ok { xess_close_handles(h_core, h_dx11); return Err(a11.error); }
  let a12 = xess_need(h_core, "xessGetExposureMultiplier");
  if !a12.is_ok { xess_close_handles(h_core, h_dx11); return Err(a12.error); }
  let a13 = xess_need(h_core, "xessSetMaxResponsiveMaskValue");
  if !a13.is_ok { xess_close_handles(h_core, h_dx11); return Err(a13.error); }
  let a14 = xess_need(h_core, "xessGetMaxResponsiveMaskValue");
  if !a14.is_ok { xess_close_handles(h_core, h_dx11); return Err(a14.error); }
  let a15 = xess_need(h_core, "xessSetLoggingCallback");
  if !a15.is_ok { xess_close_handles(h_core, h_dx11); return Err(a15.error); }
  let a16 = xess_need(h_core, "xessIsOptimalDriver");
  if !a16.is_ok { xess_close_handles(h_core, h_dx11); return Err(a16.error); }
  let a17 = xess_need(h_core, "xessForceLegacyScaleFactors");
  if !a17.is_ok { xess_close_handles(h_core, h_dx11); return Err(a17.error); }
  let a18 = xess_need(h_core, "xessGetPipelineBuildStatus");
  if !a18.is_ok { xess_close_handles(h_core, h_dx11); return Err(a18.error); }
  let a19 = xess_need(h_core, "xessD3D12CreateContext");
  if !a19.is_ok { xess_close_handles(h_core, h_dx11); return Err(a19.error); }
  let a20 = xess_need(h_core, "xessD3D12BuildPipelines");
  if !a20.is_ok { xess_close_handles(h_core, h_dx11); return Err(a20.error); }
  let a21 = xess_need(h_core, "xessD3D12Init");
  if !a21.is_ok { xess_close_handles(h_core, h_dx11); return Err(a21.error); }
  let a22 = xess_need(h_core, "xessD3D12GetInitParams");
  if !a22.is_ok { xess_close_handles(h_core, h_dx11); return Err(a22.error); }
  let a23 = xess_need(h_core, "xessD3D12Execute");
  if !a23.is_ok { xess_close_handles(h_core, h_dx11); return Err(a23.error); }
  let a24 = xess_need(h_core, "xessD3D12GetResourcesToDump");
  if !a24.is_ok { xess_close_handles(h_core, h_dx11); return Err(a24.error); }
  let a25 = xess_need(h_core, "xessD3D12GetProfilingData");
  if !a25.is_ok { xess_close_handles(h_core, h_dx11); return Err(a25.error); }
  let a26 = xess_need(h_core, "xessVKGetRequiredInstanceExtensions");
  if !a26.is_ok { xess_close_handles(h_core, h_dx11); return Err(a26.error); }
  let a27 = xess_need(h_core, "xessVKGetRequiredDeviceExtensions");
  if !a27.is_ok { xess_close_handles(h_core, h_dx11); return Err(a27.error); }
  let a28 = xess_need(h_core, "xessVKGetRequiredDeviceFeatures");
  if !a28.is_ok { xess_close_handles(h_core, h_dx11); return Err(a28.error); }
  let a29 = xess_need(h_core, "xessVKCreateContext");
  if !a29.is_ok { xess_close_handles(h_core, h_dx11); return Err(a29.error); }
  let a30 = xess_need(h_core, "xessVKBuildPipelines");
  if !a30.is_ok { xess_close_handles(h_core, h_dx11); return Err(a30.error); }
  let a31 = xess_need(h_core, "xessVKInit");
  if !a31.is_ok { xess_close_handles(h_core, h_dx11); return Err(a31.error); }
  let a32 = xess_need(h_core, "xessVKGetInitParams");
  if !a32.is_ok { xess_close_handles(h_core, h_dx11); return Err(a32.error); }
  let a33 = xess_need(h_core, "xessVKExecute");
  if !a33.is_ok { xess_close_handles(h_core, h_dx11); return Err(a33.error); }
  let a34 = xess_need(h_core, "xessVKGetResourcesToDump");
  if !a34.is_ok { xess_close_handles(h_core, h_dx11); return Err(a34.error); }
  let a35 = xess_need(h_core, "xessSelectNetworkModel");
  if !a35.is_ok { xess_close_handles(h_core, h_dx11); return Err(a35.error); }
  let a36 = xess_need(h_core, "xessStartDump");
  if !a36.is_ok { xess_close_handles(h_core, h_dx11); return Err(a36.error); }
  let a37 = xess_need(h_core, "xessGetProfilingData");
  if !a37.is_ok { xess_close_handles(h_core, h_dx11); return Err(a37.error); }

  var d1: Int = 0;
  var d2: Int = 0;
  var d3: Int = 0;
  var d4: Int = 0;
  if has_dx11 {
    let b1 = xess_need(h_dx11, "xessD3D11CreateContext");
    if !b1.is_ok { xess_close_handles(h_core, h_dx11); return Err(b1.error); }
    d1 = b1.value;
    let b2 = xess_need(h_dx11, "xessD3D11Init");
    if !b2.is_ok { xess_close_handles(h_core, h_dx11); return Err(b2.error); }
    d2 = b2.value;
    let b3 = xess_need(h_dx11, "xessD3D11GetInitParams");
    if !b3.is_ok { xess_close_handles(h_core, h_dx11); return Err(b3.error); }
    d3 = b3.value;
    let b4 = xess_need(h_dx11, "xessD3D11Execute");
    if !b4.is_ok { xess_close_handles(h_core, h_dx11); return Err(b4.error); }
    d4 = b4.value;
  }

  return Ok(XessLibrary{
    h_core: h_core;
    h_dx11: h_dx11;
    has_dx11: has_dx11;
    name_core: name_core;
    name_dx11: name_dx11;
    p_get_version: a1.value;
    p_get_intel_xefx_version: a2.value;
    p_get_properties: a3.value;
    p_get_input_resolution: a4.value;
    p_get_optimal_input_resolution: a5.value;
    p_get_jitter_scale: a6.value;
    p_get_velocity_scale: a7.value;
    p_destroy_context: a8.value;
    p_set_jitter_scale: a9.value;
    p_set_velocity_scale: a10.value;
    p_set_exposure_multiplier: a11.value;
    p_get_exposure_multiplier: a12.value;
    p_set_max_responsive_mask_value: a13.value;
    p_get_max_responsive_mask_value: a14.value;
    p_set_logging_callback: a15.value;
    p_is_optimal_driver: a16.value;
    p_force_legacy_scale_factors: a17.value;
    p_get_pipeline_build_status: a18.value;
    p_d3d12_create_context: a19.value;
    p_d3d12_build_pipelines: a20.value;
    p_d3d12_init: a21.value;
    p_d3d12_get_init_params: a22.value;
    p_d3d12_execute: a23.value;
    p_d3d12_get_resources_to_dump: a24.value;
    p_d3d12_get_profiling_data: a25.value;
    p_vk_get_required_instance_extensions: a26.value;
    p_vk_get_required_device_extensions: a27.value;
    p_vk_get_required_device_features: a28.value;
    p_vk_create_context: a29.value;
    p_vk_build_pipelines: a30.value;
    p_vk_init: a31.value;
    p_vk_get_init_params: a32.value;
    p_vk_execute: a33.value;
    p_vk_get_resources_to_dump: a34.value;
    p_select_network_model: a35.value;
    p_start_dump: a36.value;
    p_get_profiling_data: a37.value;
    p_d3d11_create_context: d1;
    p_d3d11_init: d2;
    p_d3d11_get_init_params: d3;
    p_d3d11_execute: d4;
  });
}

/// Load the first available runtime: `libxess.dll` from the OS search path
/// plus the `libxess_dx11.dll` companion when present.  Err(ABSENT) when the
/// core library cannot be loaded (the caller reports SKIP); Err(ABI) when a
/// loaded library lacks declared entry points (FAIL).  O(41).
pub fn xess_load() -> Result[XessLibrary, XessLoadError]
  requires: true
{
  return xess_load_named(XESS_SONAME, XESS_DX11_SONAME);
}

/// Release both handles.  O(1).
pub fn xess_close(lib: &XessLibrary) -> Result[Unit, Str]
  requires: lib.h_core != 0
{
  var first_err = "";
  let r1 = dl.dl_close(lib.h_core);
  if !r1.is_ok { first_err = r1.error; }
  if lib.h_dx11 != 0 {
    let r2 = dl.dl_close(lib.h_dx11);
    if !r2.is_ok {
      if first_err.len() == 0 { first_err = r2.error; }
    }
  }
  if first_err.len() > 0 { return Err(first_err); }
  return Ok(());
}

/// Load, query `xessGetVersion`, close.  Err(ABSENT) -> SKIP.  O(41).
pub fn xess_probe_default() -> Result[XessVersion, XessLoadError]
  requires: true
{
  let l = xess_load();
  if !l.is_ok {
    return Err(l.error);
  }
  let lib: XessLibrary = l.value;
  let v = xess_get_version(&lib);
  let c = xess_close(&lib);
  if !v.ok {
    return Err(XessLoadError{
      kind: XESS_LOAD_ABI;
      message: "xessGetVersion rc=" + convert.int_to_string(v.rc),
    });
  }
  if !c.is_ok {
    return Err(XessLoadError{ kind: XESS_LOAD_ABI; message: c.error });
  }
  return Ok(v.version);
}

// =========================================================================
// Generic surface (xess.h; 18 entries)
// =========================================================================

/// `xessGetVersion`: the XeSS SDK version (baked into the release).  O(1).
pub fn xess_get_version(lib: &XessLibrary) -> XessVersionOutcome
  requires: lib.p_get_version != 0
{
  var ver = xess_slot(8);
  var rc: Int = 0;
  unsafe {
    let f = lib.p_get_version as fn(*UInt8) -> Int32;
    rc = f(ver.as_mut_ptr()) as Int;
  }
  return XessVersionOutcome{
    ok: rc == XESS_RESULT_SUCCESS;
    rc: rc;
    version: XessVersion{
      major: xess_rd_u16(&ver, 0);
      minor: xess_rd_u16(&ver, 2);
      patch: xess_rd_u16(&ver, 4);
      reserved: xess_rd_u16(&ver, 6);
    };
  };
}

/// `xessGetIntelXeFXVersion`: the loaded Intel XeFX library version
/// (0.0.0 on non-Intel platforms).  O(1).
pub fn xess_get_intel_xefx_version(lib: &XessLibrary, h_context: Int) -> XessVersionOutcome
  requires: lib.p_get_intel_xefx_version != 0
  requires: h_context != 0
{
  var ver = xess_slot(8);
  var rc: Int = 0;
  unsafe {
    let f = lib.p_get_intel_xefx_version as fn(Int, *UInt8) -> Int32;
    rc = f(h_context, ver.as_mut_ptr()) as Int;
  }
  return XessVersionOutcome{
    ok: rc == XESS_RESULT_SUCCESS;
    rc: rc;
    version: XessVersion{
      major: xess_rd_u16(&ver, 0);
      minor: xess_rd_u16(&ver, 2);
      patch: xess_rd_u16(&ver, 4);
      reserved: xess_rd_u16(&ver, 6);
    };
  };
}

/// `xessGetProperties`: internal-resource requirements for an output
/// resolution.  O(1).
pub fn xess_get_properties(lib: &XessLibrary, h_context: Int, output_width: Int, output_height: Int) -> XessPropertiesOutcome
  requires: lib.p_get_properties != 0
  requires: h_context != 0
  requires: output_width >= 0
  requires: output_height >= 0
{
  var res = xess_slot(8);
  xess_wr_u32(&mut res, 0, output_width);
  xess_wr_u32(&mut res, 4, output_height);
  var props = xess_slot(24);
  var rc: Int = 0;
  unsafe {
    let f = lib.p_get_properties as fn(Int, *UInt8, *UInt8) -> Int32;
    rc = f(h_context, res.as_mut_ptr(), props.as_mut_ptr()) as Int;
  }
  return XessPropertiesOutcome{
    ok: rc == XESS_RESULT_SUCCESS;
    rc: rc;
    properties: XessProperties{
      required_descriptor_count: xess_rd_u32(&props, 0);
      temp_buffer_heap_size: xess_rd_u64(&props, 8);
      temp_texture_heap_size: xess_rd_u64(&props, 16);
    };
  };
}

/// `xessGetInputResolution`: required input resolution for an output
/// resolution + quality.  O(1).
pub fn xess_get_input_resolution(lib: &XessLibrary, h_context: Int, output_width: Int, output_height: Int, quality: Int) -> Xess2DOutcome
  requires: lib.p_get_input_resolution != 0
  requires: h_context != 0
  requires: output_width >= 0
  requires: output_height >= 0
{
  var res = xess_slot(8);
  xess_wr_u32(&mut res, 0, output_width);
  xess_wr_u32(&mut res, 4, output_height);
  var out = xess_slot(8);
  var rc: Int = 0;
  unsafe {
    let f = lib.p_get_input_resolution as fn(Int, *UInt8, Int32, *UInt8) -> Int32;
    rc = f(h_context, res.as_mut_ptr(), quality as Int32, out.as_mut_ptr()) as Int;
  }
  return Xess2DOutcome{
    ok: rc == XESS_RESULT_SUCCESS;
    rc: rc;
    x: xess_rd_u32(&out, 0);
    y: xess_rd_u32(&out, 4);
  };
}

/// `xessGetOptimalInputResolution`: optimal input resolution plus the
/// allowed min/max range for a quality.  O(1).
pub fn xess_get_optimal_input_resolution(lib: &XessLibrary, h_context: Int, output_width: Int, output_height: Int, quality: Int) -> XessOptimalOutcome
  requires: lib.p_get_optimal_input_resolution != 0
  requires: h_context != 0
  requires: output_width >= 0
  requires: output_height >= 0
{
  var res = xess_slot(8);
  xess_wr_u32(&mut res, 0, output_width);
  xess_wr_u32(&mut res, 4, output_height);
  var opt = xess_slot(8);
  var vmin = xess_slot(8);
  var vmax = xess_slot(8);
  var rc: Int = 0;
  unsafe {
    let f = lib.p_get_optimal_input_resolution as fn(Int, *UInt8, Int32, *UInt8, *UInt8, *UInt8) -> Int32;
    rc = f(h_context, res.as_mut_ptr(), quality as Int32, opt.as_mut_ptr(), vmin.as_mut_ptr(), vmax.as_mut_ptr()) as Int;
  }
  return XessOptimalOutcome{
    ok: rc == XESS_RESULT_SUCCESS;
    rc: rc;
    optimal_x: xess_rd_u32(&opt, 0);
    optimal_y: xess_rd_u32(&opt, 4);
    min_x: xess_rd_u32(&vmin, 0);
    min_y: xess_rd_u32(&vmin, 4);
    max_x: xess_rd_u32(&vmax, 0);
    max_y: xess_rd_u32(&vmax, 4);
  };
}

/// `xessGetJitterScale`: jitter scale (f32 x/y out-params).  O(1).
pub fn xess_get_jitter_scale(lib: &XessLibrary, h_context: Int) -> XessScaleOutcome
  requires: lib.p_get_jitter_scale != 0
  requires: h_context != 0
{
  var px = xess_slot(4);
  var py = xess_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.p_get_jitter_scale as fn(Int, *UInt8, *UInt8) -> Int32;
    rc = f(h_context, px.as_mut_ptr(), py.as_mut_ptr()) as Int;
  }
  return XessScaleOutcome{
    ok: rc == XESS_RESULT_SUCCESS;
    rc: rc;
    x: xess_rd_f32(&px, 0);
    y: xess_rd_f32(&py, 0);
  };
}

/// `xessGetVelocityScale`: velocity scale (f32 x/y out-params).  O(1).
pub fn xess_get_velocity_scale(lib: &XessLibrary, h_context: Int) -> XessScaleOutcome
  requires: lib.p_get_velocity_scale != 0
  requires: h_context != 0
{
  var px = xess_slot(4);
  var py = xess_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.p_get_velocity_scale as fn(Int, *UInt8, *UInt8) -> Int32;
    rc = f(h_context, px.as_mut_ptr(), py.as_mut_ptr()) as Int;
  }
  return XessScaleOutcome{
    ok: rc == XESS_RESULT_SUCCESS;
    rc: rc;
    x: xess_rd_f32(&px, 0);
    y: xess_rd_f32(&py, 0);
  };
}

/// `xessDestroyContext`.  O(1).
pub fn xess_destroy_context(lib: &XessLibrary, h_context: Int) -> XessRcOutcome
  requires: lib.p_destroy_context != 0
  requires: h_context != 0
{
  var rc: Int = 0;
  unsafe {
    let f = lib.p_destroy_context as fn(Int) -> Int32;
    rc = f(h_context) as Int;
  }
  return XessRcOutcome{ ok: rc == XESS_RESULT_SUCCESS; rc: rc };
}

/// `xessSetJitterScale` (f32 args).  O(1).
pub fn xess_set_jitter_scale(lib: &XessLibrary, h_context: Int, x: Float64, y: Float64) -> XessRcOutcome
  requires: lib.p_set_jitter_scale != 0
  requires: h_context != 0
{
  var rc: Int = 0;
  unsafe {
    let f = lib.p_set_jitter_scale as fn(Int, Float32, Float32) -> Int32;
    rc = f(h_context, x as Float32, y as Float32) as Int;
  }
  return XessRcOutcome{ ok: rc == XESS_RESULT_SUCCESS; rc: rc };
}

/// `xessSetVelocityScale` (f32 args).  O(1).
pub fn xess_set_velocity_scale(lib: &XessLibrary, h_context: Int, x: Float64, y: Float64) -> XessRcOutcome
  requires: lib.p_set_velocity_scale != 0
  requires: h_context != 0
{
  var rc: Int = 0;
  unsafe {
    let f = lib.p_set_velocity_scale as fn(Int, Float32, Float32) -> Int32;
    rc = f(h_context, x as Float32, y as Float32) as Int;
  }
  return XessRcOutcome{ ok: rc == XESS_RESULT_SUCCESS; rc: rc };
}

/// `xessSetExposureMultiplier` (f32 arg).  O(1).
pub fn xess_set_exposure_multiplier(lib: &XessLibrary, h_context: Int, scale: Float64) -> XessRcOutcome
  requires: lib.p_set_exposure_multiplier != 0
  requires: h_context != 0
{
  var rc: Int = 0;
  unsafe {
    let f = lib.p_set_exposure_multiplier as fn(Int, Float32) -> Int32;
    rc = f(h_context, scale as Float32) as Int;
  }
  return XessRcOutcome{ ok: rc == XESS_RESULT_SUCCESS; rc: rc };
}

/// `xessGetExposureMultiplier` (f32 out-param).  O(1).
pub fn xess_get_exposure_multiplier(lib: &XessLibrary, h_context: Int) -> XessScalarOutcome
  requires: lib.p_get_exposure_multiplier != 0
  requires: h_context != 0
{
  var p = xess_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.p_get_exposure_multiplier as fn(Int, *UInt8) -> Int32;
    rc = f(h_context, p.as_mut_ptr()) as Int;
  }
  return XessScalarOutcome{ ok: rc == XESS_RESULT_SUCCESS; rc: rc; value: xess_rd_f32(&p, 0) };
}

/// `xessSetMaxResponsiveMaskValue` (f32 arg, [0.0; 1.0]).  O(1).
pub fn xess_set_max_responsive_mask_value(lib: &XessLibrary, h_context: Int, value: Float64) -> XessRcOutcome
  requires: lib.p_set_max_responsive_mask_value != 0
  requires: h_context != 0
{
  var rc: Int = 0;
  unsafe {
    let f = lib.p_set_max_responsive_mask_value as fn(Int, Float32) -> Int32;
    rc = f(h_context, value as Float32) as Int;
  }
  return XessRcOutcome{ ok: rc == XESS_RESULT_SUCCESS; rc: rc };
}

/// `xessGetMaxResponsiveMaskValue` (f32 out-param).  O(1).
pub fn xess_get_max_responsive_mask_value(lib: &XessLibrary, h_context: Int) -> XessScalarOutcome
  requires: lib.p_get_max_responsive_mask_value != 0
  requires: h_context != 0
{
  var p = xess_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.p_get_max_responsive_mask_value as fn(Int, *UInt8) -> Int32;
    rc = f(h_context, p.as_mut_ptr()) as Int;
  }
  return XessScalarOutcome{ ok: rc == XESS_RESULT_SUCCESS; rc: rc; value: xess_rd_f32(&p, 0) };
}

/// `xessSetLoggingCallback`: the callback crosses as a C-ABI address (`Int`,
/// 0 = none) -- fn-typed values cannot cross the C boundary on v0.64.4
/// (findings B-13/B-18/B-22); route user handlers through a top-level
/// dispatcher per the sdl3 precedent.  O(1).
pub fn xess_set_logging_callback(lib: &XessLibrary, h_context: Int, level: Int, callback: Int) -> XessRcOutcome
  requires: lib.p_set_logging_callback != 0
  requires: h_context != 0
  requires: callback >= 0
{
  var rc: Int = 0;
  unsafe {
    let f = lib.p_set_logging_callback as fn(Int, Int32, Int) -> Int32;
    rc = f(h_context, level as Int32, callback) as Int;
  }
  return XessRcOutcome{ ok: rc == XESS_RESULT_SUCCESS; rc: rc };
}

/// `xessIsOptimalDriver`: rc 0 = optimal, 2 = OLD_DRIVER warning.  O(1).
pub fn xess_is_optimal_driver(lib: &XessLibrary, h_context: Int) -> XessRcOutcome
  requires: lib.p_is_optimal_driver != 0
  requires: h_context != 0
{
  var rc: Int = 0;
  unsafe {
    let f = lib.p_is_optimal_driver as fn(Int) -> Int32;
    rc = f(h_context) as Int;
  }
  return XessRcOutcome{ ok: rc == XESS_RESULT_SUCCESS; rc: rc };
}

/// `xessForceLegacyScaleFactors` (C bool crosses as UInt8).  O(1).
pub fn xess_force_legacy_scale_factors(lib: &XessLibrary, h_context: Int, force: Bool) -> XessRcOutcome
  requires: lib.p_force_legacy_scale_factors != 0
  requires: h_context != 0
{
  let flag: UInt8 = if force { 1 as UInt8 } else { 0 as UInt8 };
  var rc: Int = 0;
  unsafe {
    let f = lib.p_force_legacy_scale_factors as fn(Int, UInt8) -> Int32;
    rc = f(h_context, flag) as Int;
  }
  return XessRcOutcome{ ok: rc == XESS_RESULT_SUCCESS; rc: rc };
}

/// `xessGetPipelineBuildStatus`: 0 = built, -9 = in progress, -12 = wrong
/// call order.  O(1).
pub fn xess_get_pipeline_build_status(lib: &XessLibrary, h_context: Int) -> XessRcOutcome
  requires: lib.p_get_pipeline_build_status != 0
  requires: h_context != 0
{
  var rc: Int = 0;
  unsafe {
    let f = lib.p_get_pipeline_build_status as fn(Int) -> Int32;
    rc = f(h_context) as Int;
  }
  return XessRcOutcome{ ok: rc == XESS_RESULT_SUCCESS; rc: rc };
}

// =========================================================================
// D3D12 surface (xess_d3d12.h; 5 entries)
// =========================================================================

/// Serialize `XessD3D12InitParams` into its 64-byte pinned layout.  O(1).
pub fn xess_d3d12_init_params_build(p: &XessD3D12InitParams) -> Vec[UInt8]
  requires: true
{
  var s = xess_slot(64);
  xess_wr_u32(&mut s, 0, p.output_width);
  xess_wr_u32(&mut s, 4, p.output_height);
  xess_wr_u32(&mut s, 8, p.quality);
  xess_wr_u32(&mut s, 12, p.init_flags);
  xess_wr_u32(&mut s, 16, p.creation_node_mask);
  xess_wr_u32(&mut s, 20, p.visible_node_mask);
  xess_wr_u64(&mut s, 24, p.temp_buffer_heap);
  xess_wr_u64(&mut s, 32, p.buffer_heap_offset);
  xess_wr_u64(&mut s, 40, p.temp_texture_heap);
  xess_wr_u64(&mut s, 48, p.texture_heap_offset);
  xess_wr_u64(&mut s, 56, p.pipeline_library);
  return s;
}

/// Parse the 64-byte `xess_d3d12_init_params_t` layout.  O(1).
pub fn xess_d3d12_init_params_read(buf: &Vec[UInt8]) -> XessD3D12InitParams
  requires: buf.len() >= 64
{
  return XessD3D12InitParams{
    output_width: xess_rd_u32(buf, 0);
    output_height: xess_rd_u32(buf, 4);
    quality: xess_rd_u32(buf, 8);
    init_flags: xess_rd_u32(buf, 12);
    creation_node_mask: xess_rd_u32(buf, 16);
    visible_node_mask: xess_rd_u32(buf, 20);
    temp_buffer_heap: xess_rd_u64(buf, 24);
    buffer_heap_offset: xess_rd_u64(buf, 32);
    temp_texture_heap: xess_rd_u64(buf, 40);
    texture_heap_offset: xess_rd_u64(buf, 48);
    pipeline_library: xess_rd_u64(buf, 56);
  };
}

/// Serialize `XessD3D12ExecuteParams` into its 136-byte pinned layout.  O(1).
pub fn xess_d3d12_execute_params_build(p: &XessD3D12ExecuteParams) -> Vec[UInt8]
  requires: true
{
  var s = xess_slot(136);
  xess_wr_u64(&mut s, 0, p.color_texture);
  xess_wr_u64(&mut s, 8, p.velocity_texture);
  xess_wr_u64(&mut s, 16, p.depth_texture);
  xess_wr_u64(&mut s, 24, p.exposure_scale_texture);
  xess_wr_u64(&mut s, 32, p.responsive_pixel_mask_texture);
  xess_wr_u64(&mut s, 40, p.output_texture);
  xess_wr_f32(&mut s, 48, p.jitter_offset_x);
  xess_wr_f32(&mut s, 52, p.jitter_offset_y);
  xess_wr_f32(&mut s, 56, p.exposure_scale);
  xess_wr_u32(&mut s, 60, p.reset_history);
  xess_wr_u32(&mut s, 64, p.input_width);
  xess_wr_u32(&mut s, 68, p.input_height);
  xess_wr_u32(&mut s, 72, p.input_color_base_x);
  xess_wr_u32(&mut s, 76, p.input_color_base_y);
  xess_wr_u32(&mut s, 80, p.input_motion_vector_base_x);
  xess_wr_u32(&mut s, 84, p.input_motion_vector_base_y);
  xess_wr_u32(&mut s, 88, p.input_depth_base_x);
  xess_wr_u32(&mut s, 92, p.input_depth_base_y);
  xess_wr_u32(&mut s, 96, p.input_responsive_mask_base_x);
  xess_wr_u32(&mut s, 100, p.input_responsive_mask_base_y);
  xess_wr_u32(&mut s, 104, 0);
  xess_wr_u32(&mut s, 108, 0);
  xess_wr_u32(&mut s, 112, p.output_color_base_x);
  xess_wr_u32(&mut s, 116, p.output_color_base_y);
  xess_wr_u64(&mut s, 120, p.descriptor_heap);
  xess_wr_u32(&mut s, 128, p.descriptor_heap_offset);
  return s;
}

/// `xessD3D12CreateContext`.  O(1).
pub fn xess_d3d12_create_context(lib: &XessLibrary, device: Int) -> XessHandleOutcome
  requires: lib.p_d3d12_create_context != 0
  requires: device != 0
{
  var ph = xess_slot(8);
  var rc: Int = 0;
  unsafe {
    let f = lib.p_d3d12_create_context as fn(Int, *UInt8) -> Int32;
    rc = f(device, ph.as_mut_ptr()) as Int;
  }
  return XessHandleOutcome{ ok: rc == XESS_RESULT_SUCCESS; rc: rc; handle: xess_rd_u64(&ph, 0) };
}

/// `xessD3D12BuildPipelines` (C bool crosses as UInt8).  O(1).
pub fn xess_d3d12_build_pipelines(lib: &XessLibrary, h_context: Int, pipeline_library: Int, blocking: Bool, init_flags: Int) -> XessRcOutcome
  requires: lib.p_d3d12_build_pipelines != 0
  requires: h_context != 0
  requires: init_flags >= 0
{
  let flag: UInt8 = if blocking { 1 as UInt8 } else { 0 as UInt8 };
  var rc: Int = 0;
  unsafe {
    let f = lib.p_d3d12_build_pipelines as fn(Int, Int, UInt8, Int32) -> Int32;
    rc = f(h_context, pipeline_library, flag, init_flags as Int32) as Int;
  }
  return XessRcOutcome{ ok: rc == XESS_RESULT_SUCCESS; rc: rc };
}

/// `xessD3D12Init`.  O(1).
pub fn xess_d3d12_init(lib: &XessLibrary, h_context: Int, params: &XessD3D12InitParams) -> XessRcOutcome
  requires: lib.p_d3d12_init != 0
  requires: h_context != 0
{
  var s = xess_d3d12_init_params_build(params);
  var rc: Int = 0;
  unsafe {
    let f = lib.p_d3d12_init as fn(Int, *UInt8) -> Int32;
    rc = f(h_context, s.as_mut_ptr()) as Int;
  }
  return XessRcOutcome{ ok: rc == XESS_RESULT_SUCCESS; rc: rc };
}

/// `xessD3D12GetInitParams` (reads the returned 64-byte params).  O(1).
pub fn xess_d3d12_get_init_params(lib: &XessLibrary, h_context: Int) -> XessD3D12InitParamsOutcome
  requires: lib.p_d3d12_get_init_params != 0
  requires: h_context != 0
{
  var s = xess_slot(64);
  var rc: Int = 0;
  unsafe {
    let f = lib.p_d3d12_get_init_params as fn(Int, *UInt8) -> Int32;
    rc = f(h_context, s.as_mut_ptr()) as Int;
  }
  return XessD3D12InitParamsOutcome{
    ok: rc == XESS_RESULT_SUCCESS;
    rc: rc;
    params: xess_d3d12_init_params_read(&s);
  };
}

/// `xessD3D12Execute`: records upscaling commands into the command list.
/// O(1).
pub fn xess_d3d12_execute(lib: &XessLibrary, h_context: Int, command_list: Int, params: &XessD3D12ExecuteParams) -> XessRcOutcome
  requires: lib.p_d3d12_execute != 0
  requires: h_context != 0
  requires: command_list != 0
{
  var s = xess_d3d12_execute_params_build(params);
  var rc: Int = 0;
  unsafe {
    let f = lib.p_d3d12_execute as fn(Int, Int, *UInt8) -> Int32;
    rc = f(h_context, command_list, s.as_mut_ptr()) as Int;
  }
  return XessRcOutcome{ ok: rc == XESS_RESULT_SUCCESS; rc: rc };
}

// =========================================================================
// D3D12 debug surface (xess_d3d12_debug.h; 2 entries)
// =========================================================================

/// `xessD3D12GetResourcesToDump` (deprecated D3D12 naming; returns the
/// internal `xess_resources_to_dump_t*` as an owned pointer value).  O(1).
pub fn xess_d3d12_get_resources_to_dump(lib: &XessLibrary, h_context: Int) -> XessPtrOutcome
  requires: lib.p_d3d12_get_resources_to_dump != 0
  requires: h_context != 0
{
  var s = xess_slot(8);
  var rc: Int = 0;
  unsafe {
    let f = lib.p_d3d12_get_resources_to_dump as fn(Int, *UInt8) -> Int32;
    rc = f(h_context, s.as_mut_ptr()) as Int;
  }
  return XessPtrOutcome{ ok: rc == XESS_RESULT_SUCCESS; rc: rc; ptr: xess_rd_u64(&s, 0) };
}

/// `xessD3D12GetProfilingData` (deprecated alias of xessGetProfilingData).
/// O(1).
pub fn xess_d3d12_get_profiling_data(lib: &XessLibrary, h_context: Int) -> XessPtrOutcome
  requires: lib.p_d3d12_get_profiling_data != 0
  requires: h_context != 0
{
  var s = xess_slot(8);
  var rc: Int = 0;
  unsafe {
    let f = lib.p_d3d12_get_profiling_data as fn(Int, *UInt8) -> Int32;
    rc = f(h_context, s.as_mut_ptr()) as Int;
  }
  return XessPtrOutcome{ ok: rc == XESS_RESULT_SUCCESS; rc: rc; ptr: xess_rd_u64(&s, 0) };
}

// =========================================================================
// Vulkan surface (xess_vk.h; 8 entries)
// =========================================================================

/// Serialize `XessVkInitParams` into its 64-byte pinned layout.  O(1).
pub fn xess_vk_init_params_build(p: &XessVkInitParams) -> Vec[UInt8]
  requires: true
{
  var s = xess_slot(64);
  xess_wr_u32(&mut s, 0, p.output_width);
  xess_wr_u32(&mut s, 4, p.output_height);
  xess_wr_u32(&mut s, 8, p.quality);
  xess_wr_u32(&mut s, 12, p.init_flags);
  xess_wr_u32(&mut s, 16, p.creation_node_mask);
  xess_wr_u32(&mut s, 20, p.visible_node_mask);
  xess_wr_u64(&mut s, 24, p.temp_buffer_heap);
  xess_wr_u64(&mut s, 32, p.buffer_heap_offset);
  xess_wr_u64(&mut s, 40, p.temp_texture_heap);
  xess_wr_u64(&mut s, 48, p.texture_heap_offset);
  xess_wr_u64(&mut s, 56, p.pipeline_cache);
  return s;
}

/// Parse the 64-byte `xess_vk_init_params_t` layout.  O(1).
pub fn xess_vk_init_params_read(buf: &Vec[UInt8]) -> XessVkInitParams
  requires: buf.len() >= 64
{
  return XessVkInitParams{
    output_width: xess_rd_u32(buf, 0);
    output_height: xess_rd_u32(buf, 4);
    quality: xess_rd_u32(buf, 8);
    init_flags: xess_rd_u32(buf, 12);
    creation_node_mask: xess_rd_u32(buf, 16);
    visible_node_mask: xess_rd_u32(buf, 20);
    temp_buffer_heap: xess_rd_u64(buf, 24);
    buffer_heap_offset: xess_rd_u64(buf, 32);
    temp_texture_heap: xess_rd_u64(buf, 40);
    texture_heap_offset: xess_rd_u64(buf, 48);
    pipeline_cache: xess_rd_u64(buf, 56);
  };
}

/// Write one 48-byte `xess_vk_image_view_info` at `off`.  O(1).
fn xess_vk_image_info_write(s: &mut Vec[UInt8], off: Int, info: &XessVkImageViewInfo)
  requires: off >= 0
  requires: s.len() >= off + 48
{
  xess_wr_u64(s, off + 0, info.image_view);
  xess_wr_u64(s, off + 8, info.image);
  xess_wr_u32(s, off + 16, info.aspect_mask);
  xess_wr_u32(s, off + 20, info.base_mip_level);
  xess_wr_u32(s, off + 24, info.level_count);
  xess_wr_u32(s, off + 28, info.base_array_layer);
  xess_wr_u32(s, off + 32, info.layer_count);
  xess_wr_u32(s, off + 36, info.format);
  xess_wr_u32(s, off + 40, info.width);
  xess_wr_u32(s, off + 44, info.height);
}

/// Serialize `XessVkExecuteParams` into its 360-byte pinned layout.  O(1).
pub fn xess_vk_execute_params_build(p: &XessVkExecuteParams) -> Vec[UInt8]
  requires: true
{
  var s = xess_slot(360);
  xess_vk_image_info_write(&mut s, 0, &p.color_texture);
  xess_vk_image_info_write(&mut s, 48, &p.velocity_texture);
  xess_vk_image_info_write(&mut s, 96, &p.depth_texture);
  xess_vk_image_info_write(&mut s, 144, &p.exposure_scale_texture);
  xess_vk_image_info_write(&mut s, 192, &p.responsive_pixel_mask_texture);
  xess_vk_image_info_write(&mut s, 240, &p.output_texture);
  xess_wr_f32(&mut s, 288, p.jitter_offset_x);
  xess_wr_f32(&mut s, 292, p.jitter_offset_y);
  xess_wr_f32(&mut s, 296, p.exposure_scale);
  xess_wr_u32(&mut s, 300, p.reset_history);
  xess_wr_u32(&mut s, 304, p.input_width);
  xess_wr_u32(&mut s, 308, p.input_height);
  xess_wr_u32(&mut s, 312, p.input_color_base_x);
  xess_wr_u32(&mut s, 316, p.input_color_base_y);
  xess_wr_u32(&mut s, 320, p.input_motion_vector_base_x);
  xess_wr_u32(&mut s, 324, p.input_motion_vector_base_y);
  xess_wr_u32(&mut s, 328, p.input_depth_base_x);
  xess_wr_u32(&mut s, 332, p.input_depth_base_y);
  xess_wr_u32(&mut s, 336, p.input_responsive_mask_base_x);
  xess_wr_u32(&mut s, 340, p.input_responsive_mask_base_y);
  xess_wr_u32(&mut s, 344, 0);
  xess_wr_u32(&mut s, 348, 0);
  xess_wr_u32(&mut s, 352, p.output_color_base_x);
  xess_wr_u32(&mut s, 356, p.output_color_base_y);
  return s;
}

/// `xessVKGetRequiredInstanceExtensions`: required instance extension count,
/// name-array pointer (library-owned) and minimum VkApiVersion.  O(1).
pub fn xess_vk_get_required_instance_extensions(lib: &XessLibrary) -> XessVkInstanceExtensionsOutcome
  requires: lib.p_vk_get_required_instance_extensions != 0
{
  var count = xess_slot(4);
  var list = xess_slot(8);
  var minver = xess_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.p_vk_get_required_instance_extensions as fn(*UInt8, *UInt8, *UInt8) -> Int32;
    rc = f(count.as_mut_ptr(), list.as_mut_ptr(), minver.as_mut_ptr()) as Int;
  }
  return XessVkInstanceExtensionsOutcome{
    ok: rc == XESS_RESULT_SUCCESS;
    rc: rc;
    count: xess_rd_u32(&count, 0);
    list_ptr: xess_rd_u64(&list, 0);
    min_vk_api_version: xess_rd_u32(&minver, 0);
  };
}

/// `xessVKGetRequiredDeviceExtensions`.  O(1).
pub fn xess_vk_get_required_device_extensions(lib: &XessLibrary, instance: Int, physical_device: Int) -> XessVkDeviceExtensionsOutcome
  requires: lib.p_vk_get_required_device_extensions != 0
  requires: instance != 0
  requires: physical_device != 0
{
  var count = xess_slot(4);
  var list = xess_slot(8);
  var rc: Int = 0;
  unsafe {
    let f = lib.p_vk_get_required_device_extensions as fn(Int, Int, *UInt8, *UInt8) -> Int32;
    rc = f(instance, physical_device, count.as_mut_ptr(), list.as_mut_ptr()) as Int;
  }
  return XessVkDeviceExtensionsOutcome{
    ok: rc == XESS_RESULT_SUCCESS;
    rc: rc;
    count: xess_rd_u32(&count, 0);
    list_ptr: xess_rd_u64(&list, 0);
  };
}

/// `xessVKGetRequiredDeviceFeatures`: returns the (library-owned) feature
/// chain pointer to pass as VkDeviceCreateInfo::pNext.  O(1).
pub fn xess_vk_get_required_device_features(lib: &XessLibrary, instance: Int, physical_device: Int) -> XessPtrOutcome
  requires: lib.p_vk_get_required_device_features != 0
  requires: instance != 0
  requires: physical_device != 0
{
  var s = xess_slot(8);
  var rc: Int = 0;
  unsafe {
    let f = lib.p_vk_get_required_device_features as fn(Int, Int, *UInt8) -> Int32;
    rc = f(instance, physical_device, s.as_mut_ptr()) as Int;
  }
  return XessPtrOutcome{ ok: rc == XESS_RESULT_SUCCESS; rc: rc; ptr: xess_rd_u64(&s, 0) };
}

/// `xessVKCreateContext`.  O(1).
pub fn xess_vk_create_context(lib: &XessLibrary, instance: Int, physical_device: Int, device: Int) -> XessHandleOutcome
  requires: lib.p_vk_create_context != 0
  requires: instance != 0
  requires: physical_device != 0
  requires: device != 0
{
  var ph = xess_slot(8);
  var rc: Int = 0;
  unsafe {
    let f = lib.p_vk_create_context as fn(Int, Int, Int, *UInt8) -> Int32;
    rc = f(instance, physical_device, device, ph.as_mut_ptr()) as Int;
  }
  return XessHandleOutcome{ ok: rc == XESS_RESULT_SUCCESS; rc: rc; handle: xess_rd_u64(&ph, 0) };
}

/// `xessVKBuildPipelines` (C bool crosses as UInt8).  O(1).
pub fn xess_vk_build_pipelines(lib: &XessLibrary, h_context: Int, pipeline_cache: Int, blocking: Bool, init_flags: Int) -> XessRcOutcome
  requires: lib.p_vk_build_pipelines != 0
  requires: h_context != 0
  requires: init_flags >= 0
{
  let flag: UInt8 = if blocking { 1 as UInt8 } else { 0 as UInt8 };
  var rc: Int = 0;
  unsafe {
    let f = lib.p_vk_build_pipelines as fn(Int, Int, UInt8, Int32) -> Int32;
    rc = f(h_context, pipeline_cache, flag, init_flags as Int32) as Int;
  }
  return XessRcOutcome{ ok: rc == XESS_RESULT_SUCCESS; rc: rc };
}

/// `xessVKInit`.  O(1).
pub fn xess_vk_init(lib: &XessLibrary, h_context: Int, params: &XessVkInitParams) -> XessRcOutcome
  requires: lib.p_vk_init != 0
  requires: h_context != 0
{
  var s = xess_vk_init_params_build(params);
  var rc: Int = 0;
  unsafe {
    let f = lib.p_vk_init as fn(Int, *UInt8) -> Int32;
    rc = f(h_context, s.as_mut_ptr()) as Int;
  }
  return XessRcOutcome{ ok: rc == XESS_RESULT_SUCCESS; rc: rc };
}

/// `xessVKGetInitParams` (reads the returned 64-byte params).  O(1).
pub fn xess_vk_get_init_params(lib: &XessLibrary, h_context: Int) -> XessVkInitParamsOutcome
  requires: lib.p_vk_get_init_params != 0
  requires: h_context != 0
{
  var s = xess_slot(64);
  var rc: Int = 0;
  unsafe {
    let f = lib.p_vk_get_init_params as fn(Int, *UInt8) -> Int32;
    rc = f(h_context, s.as_mut_ptr()) as Int;
  }
  return XessVkInitParamsOutcome{
    ok: rc == XESS_RESULT_SUCCESS;
    rc: rc;
    params: xess_vk_init_params_read(&s);
  };
}

/// `xessVKExecute`: records upscaling commands into the command buffer.
/// O(1).
pub fn xess_vk_execute(lib: &XessLibrary, h_context: Int, command_buffer: Int, params: &XessVkExecuteParams) -> XessRcOutcome
  requires: lib.p_vk_execute != 0
  requires: h_context != 0
  requires: command_buffer != 0
{
  var s = xess_vk_execute_params_build(params);
  var rc: Int = 0;
  unsafe {
    let f = lib.p_vk_execute as fn(Int, Int, *UInt8) -> Int32;
    rc = f(h_context, command_buffer, s.as_mut_ptr()) as Int;
  }
  return XessRcOutcome{ ok: rc == XESS_RESULT_SUCCESS; rc: rc };
}

/// `xessVKGetResourcesToDump`.  O(1).
pub fn xess_vk_get_resources_to_dump(lib: &XessLibrary, h_context: Int) -> XessPtrOutcome
  requires: lib.p_vk_get_resources_to_dump != 0
  requires: h_context != 0
{
  var s = xess_slot(8);
  var rc: Int = 0;
  unsafe {
    let f = lib.p_vk_get_resources_to_dump as fn(Int, *UInt8) -> Int32;
    rc = f(h_context, s.as_mut_ptr()) as Int;
  }
  return XessPtrOutcome{ ok: rc == XESS_RESULT_SUCCESS; rc: rc; ptr: xess_rd_u64(&s, 0) };
}

// =========================================================================
// Debug surface (xess_debug.h; 3 entries)
// =========================================================================

/// `xessSelectNetworkModel`: select the network model; the matching init
/// call must follow.  O(1).
pub fn xess_select_network_model(lib: &XessLibrary, h_context: Int, network: Int) -> XessRcOutcome
  requires: lib.p_select_network_model != 0
  requires: h_context != 0
{
  var rc: Int = 0;
  unsafe {
    let f = lib.p_select_network_model as fn(Int, Int32) -> Int32;
    rc = f(h_context, network as Int32) as Int;
  }
  return XessRcOutcome{ ok: rc == XESS_RESULT_SUCCESS; rc: rc };
}

/// Serialize `XessDumpParameters` into its 24-byte pinned layout.  O(len).
pub fn xess_dump_parameters_build(p: &XessDumpParameters) -> Vec[UInt8]
  requires: true
{
  var s = xess_slot(24);
  var path_ptr: Int = 0;
  unsafe {
    path_ptr = p.path.c_str() as Int;
  }
  xess_wr_u64(&mut s, 0, path_ptr);
  xess_wr_u32(&mut s, 8, p.frame_idx);
  xess_wr_u32(&mut s, 12, p.frame_count);
  xess_wr_u32(&mut s, 16, p.dump_elements_mask);
  return s;
}

/// `xessStartDump`.  O(len(path)).
pub fn xess_start_dump(lib: &XessLibrary, h_context: Int, params: &XessDumpParameters) -> XessRcOutcome
  requires: lib.p_start_dump != 0
  requires: h_context != 0
  requires: params.path.len() > 0
{
  var s = xess_dump_parameters_build(params);
  var rc: Int = 0;
  unsafe {
    let f = lib.p_start_dump as fn(Int, *UInt8) -> Int32;
    rc = f(h_context, s.as_mut_ptr()) as Int;
  }
  return XessRcOutcome{ ok: rc == XESS_RESULT_SUCCESS; rc: rc };
}

/// `xessGetProfilingData`: returns the (context-owned) profiling-data
/// pointer.  O(1).
pub fn xess_get_profiling_data(lib: &XessLibrary, h_context: Int) -> XessPtrOutcome
  requires: lib.p_get_profiling_data != 0
  requires: h_context != 0
{
  var s = xess_slot(8);
  var rc: Int = 0;
  unsafe {
    let f = lib.p_get_profiling_data as fn(Int, *UInt8) -> Int32;
    rc = f(h_context, s.as_mut_ptr()) as Int;
  }
  return XessPtrOutcome{ ok: rc == XESS_RESULT_SUCCESS; rc: rc; ptr: xess_rd_u64(&s, 0) };
}

// =========================================================================
// D3D11 surface (xess_d3d11.h; 4 entries, libxess_dx11.dll companion)
// =========================================================================

/// Serialize `XessD3D11InitParams` into its 16-byte pinned layout.  O(1).
pub fn xess_d3d11_init_params_build(p: &XessD3D11InitParams) -> Vec[UInt8]
  requires: true
{
  var s = xess_slot(16);
  xess_wr_u32(&mut s, 0, p.output_width);
  xess_wr_u32(&mut s, 4, p.output_height);
  xess_wr_u32(&mut s, 8, p.quality);
  xess_wr_u32(&mut s, 12, p.init_flags);
  return s;
}

/// Parse the 16-byte `xess_d3d11_init_params_t` layout.  O(1).
pub fn xess_d3d11_init_params_read(buf: &Vec[UInt8]) -> XessD3D11InitParams
  requires: buf.len() >= 16
{
  return XessD3D11InitParams{
    output_width: xess_rd_u32(buf, 0);
    output_height: xess_rd_u32(buf, 4);
    quality: xess_rd_u32(buf, 8);
    init_flags: xess_rd_u32(buf, 12);
  };
}

/// Serialize `XessD3D11ExecuteParams` into its 120-byte pinned layout.  O(1).
pub fn xess_d3d11_execute_params_build(p: &XessD3D11ExecuteParams) -> Vec[UInt8]
  requires: true
{
  var s = xess_slot(120);
  xess_wr_u64(&mut s, 0, p.color_texture);
  xess_wr_u64(&mut s, 8, p.velocity_texture);
  xess_wr_u64(&mut s, 16, p.depth_texture);
  xess_wr_u64(&mut s, 24, p.exposure_scale_texture);
  xess_wr_u64(&mut s, 32, p.responsive_pixel_mask_texture);
  xess_wr_u64(&mut s, 40, p.output_texture);
  xess_wr_f32(&mut s, 48, p.jitter_offset_x);
  xess_wr_f32(&mut s, 52, p.jitter_offset_y);
  xess_wr_f32(&mut s, 56, p.exposure_scale);
  xess_wr_u32(&mut s, 60, p.reset_history);
  xess_wr_u32(&mut s, 64, p.input_width);
  xess_wr_u32(&mut s, 68, p.input_height);
  xess_wr_u32(&mut s, 72, p.input_color_base_x);
  xess_wr_u32(&mut s, 76, p.input_color_base_y);
  xess_wr_u32(&mut s, 80, p.input_motion_vector_base_x);
  xess_wr_u32(&mut s, 84, p.input_motion_vector_base_y);
  xess_wr_u32(&mut s, 88, p.input_depth_base_x);
  xess_wr_u32(&mut s, 92, p.input_depth_base_y);
  xess_wr_u32(&mut s, 96, p.input_responsive_mask_base_x);
  xess_wr_u32(&mut s, 100, p.input_responsive_mask_base_y);
  xess_wr_u32(&mut s, 104, 0);
  xess_wr_u32(&mut s, 108, 0);
  xess_wr_u32(&mut s, 112, p.output_color_base_x);
  xess_wr_u32(&mut s, 116, p.output_color_base_y);
  return s;
}

/// `xessD3D11CreateContext` (requires the libxess_dx11.dll companion; a typed
/// CANT_LOAD_LIBRARY outcome when it is absent).  O(1).
pub fn xess_d3d11_create_context(lib: &XessLibrary, device: Int) -> XessHandleOutcome
  requires: true
{
  if !lib.has_dx11 {
    return XessHandleOutcome{ ok: false; rc: XESS_RESULT_ERROR_CANT_LOAD_LIBRARY; handle: 0 };
  }
  var ph = xess_slot(8);
  var rc: Int = 0;
  unsafe {
    let f = lib.p_d3d11_create_context as fn(Int, *UInt8) -> Int32;
    rc = f(device, ph.as_mut_ptr()) as Int;
  }
  return XessHandleOutcome{ ok: rc == XESS_RESULT_SUCCESS; rc: rc; handle: xess_rd_u64(&ph, 0) };
}

/// `xessD3D11Init` (companion required; typed outcome when absent).  O(1).
pub fn xess_d3d11_init(lib: &XessLibrary, h_context: Int, params: &XessD3D11InitParams) -> XessRcOutcome
  requires: true
{
  if !lib.has_dx11 {
    return XessRcOutcome{ ok: false; rc: XESS_RESULT_ERROR_CANT_LOAD_LIBRARY };
  }
  var s = xess_d3d11_init_params_build(params);
  var rc: Int = 0;
  unsafe {
    let f = lib.p_d3d11_init as fn(Int, *UInt8) -> Int32;
    rc = f(h_context, s.as_mut_ptr()) as Int;
  }
  return XessRcOutcome{ ok: rc == XESS_RESULT_SUCCESS; rc: rc };
}

/// `xessD3D11GetInitParams` (companion required; typed outcome when absent).
/// O(1).
pub fn xess_d3d11_get_init_params(lib: &XessLibrary, h_context: Int) -> XessD3D11InitParamsOutcome
  requires: true
{
  if !lib.has_dx11 {
    return XessD3D11InitParamsOutcome{
      ok: false;
      rc: XESS_RESULT_ERROR_CANT_LOAD_LIBRARY;
      params: XessD3D11InitParams{ output_width: 0; output_height: 0; quality: 0; init_flags: 0 };
    };
  }
  var s = xess_slot(16);
  var rc: Int = 0;
  unsafe {
    let f = lib.p_d3d11_get_init_params as fn(Int, *UInt8) -> Int32;
    rc = f(h_context, s.as_mut_ptr()) as Int;
  }
  return XessD3D11InitParamsOutcome{
    ok: rc == XESS_RESULT_SUCCESS;
    rc: rc;
    params: xess_d3d11_init_params_read(&s);
  };
}

/// `xessD3D11Execute` (companion required; typed outcome when absent).  O(1).
pub fn xess_d3d11_execute(lib: &XessLibrary, h_context: Int, params: &XessD3D11ExecuteParams) -> XessRcOutcome
  requires: true
{
  if !lib.has_dx11 {
    return XessRcOutcome{ ok: false; rc: XESS_RESULT_ERROR_CANT_LOAD_LIBRARY };
  }
  var s = xess_d3d11_execute_params_build(params);
  var rc: Int = 0;
  unsafe {
    let f = lib.p_d3d11_execute as fn(Int, *UInt8) -> Int32;
    rc = f(h_context, s.as_mut_ptr()) as Int;
  }
  return XessRcOutcome{ ok: rc == XESS_RESULT_SUCCESS; rc: rc };
}
