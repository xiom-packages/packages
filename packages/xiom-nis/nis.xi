// XIOM -- xiom.nis: NVIDIA Image Scaling (NIS) SDK v1.0.3 bindings.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// UPSTREAM-FIRST: the NIS SDK core (NIS_Config.h / NIS_Scaler.h /
// NIS_Main.hlsl / NIS_Main.glsl, MIT) is vendored byte-exact under
// `vendor/NIS/`; every constant and function below is written against that
// pinned source (PROVENANCE.md; SPEC.md section 2 has the byte table).
//
// SURFACE MODEL.  NIS v1.0.3 is a *shader-only* pixel pipeline: the actual
// upscale/sharpen runs as a compute shader (NVScaler / NVSharpen in
// NIS_Scaler.h, dispatched by NIS_Main.hlsl/.glsl).  The SDK's CPU-visible
// C/C++ surface is the configuration layer in NIS_Config.h:
//
//   * `NISConfig`      -- the 28-field (112-byte payload, 256-byte struct)
//                          constant buffer the shader reads,
//   * `NVScalerUpdateConfig`  -- upscale+sharpen config builder,
//   * `NVSharpenUpdateConfig` -- sharpen-only config builder,
//   * `NISOptimizer`   -- per-architecture dispatch geometry getters,
//   * the four coefficient tables (coef_scale/coef_usm f32 + fp16).
//
// This module binds 100% of that CPU-visible surface (PROVENANCE.md
// section 5 records the count) and reports the GPU pixel path as a typed
// SKIP (`nis_gpu_path`), because v1.0.3 ships no CPU/scalar pixel
// implementation -- the suite's CPU-path checks exercise the real vendored
// config builders, and the shader surface is checked as source-level API
// (entry points declared in the vendored NIS_Scaler.h).
//
// Buffer interop: every config is an XIOM-owned `Vec[UInt8]`
// (`nis_config_new`, exactly `nis_config_size()` bytes); the bridge builds
// the config in C and copies it into that buffer -- XIOM never reads or
// writes foreign memory and never does pointer arithmetic (v0.64.4 findings
// B-20/B-22/B-24/B-25; floats cross as IEEE-754 Float32, integers as Int32).
// All `unsafe`/`extern "C"` lives in this single module (G5).

module xiom.nis

// =========================================================================
// Bridge (our code; src/nis_bridge.cpp -- the only TU including the SDK)
// =========================================================================

extern "C" {
  fn nis_bridge_config_size() -> Int32;
  fn nis_bridge_config_used_size() -> Int32;
  fn nis_bridge_scaler_update(out: *UInt8, sharpness: Float32, ivp_x: Int32, ivp_y: Int32, ivp_w: Int32, ivp_h: Int32, it_w: Int32, it_h: Int32, ovp_x: Int32, ovp_y: Int32, ovp_w: Int32, ovp_h: Int32, ot_w: Int32, ot_h: Int32, hdr_mode: Int32) -> Int32;
  fn nis_bridge_sharpen_update(out: *UInt8, sharpness: Float32, ivp_x: Int32, ivp_y: Int32, ivp_w: Int32, ivp_h: Int32, it_w: Int32, it_h: Int32, ovp_x: Int32, ovp_y: Int32, hdr_mode: Int32) -> Int32;
  fn nis_bridge_optimal_block_width(is_upscaling: Int32, arch: Int32) -> UInt32;
  fn nis_bridge_optimal_block_height(is_upscaling: Int32, arch: Int32) -> UInt32;
  fn nis_bridge_optimal_thread_group_size(is_upscaling: Int32, arch: Int32) -> UInt32;
  fn nis_bridge_copy_coefficients(table: Int32, out: *UInt8, out_cap: Int32) -> Int32;
  fn nis_bridge_config_f32(bytes: *UInt8, field: Int32) -> Float32;
  fn nis_bridge_config_u32(bytes: *UInt8, field: Int32) -> UInt32;
  fn nis_bridge_buf_f32(bytes: *UInt8, byte_offset: Int32) -> Float32;
}

// =========================================================================
// Declared API surface constants (from NIS_Config.h / NIS_Scaler.h)
// =========================================================================

/// NISHDRMode values (NIS_Config.h `enum class NISHDRMode`).
pub const NIS_HDR_MODE_NONE: Int = 0;
pub const NIS_HDR_MODE_LINEAR: Int = 1;
pub const NIS_HDR_MODE_PQ: Int = 2;

/// NISGPUArchitecture values (NIS_Config.h `enum class NISGPUArchitecture`).
pub const NIS_GPU_ARCH_NVIDIA_GENERIC: Int = 0;
pub const NIS_GPU_ARCH_AMD_GENERIC: Int = 1;
pub const NIS_GPU_ARCH_INTEL_GENERIC: Int = 2;
pub const NIS_GPU_ARCH_NVIDIA_GENERIC_FP16: Int = 3;

/// Filter geometry (NIS_Config.h `kPhaseCount` / `kFilterSize`).
pub const NIS_PHASE_COUNT: Int = 64;
pub const NIS_FILTER_SIZE: Int = 8;

/// NISConfig ABI sizes (NIS_Config.h): `sizeof(NISConfig)` rounds the
/// 112-byte field payload up to the 256-byte alignment.  `nis_config_size`
/// and `nis_config_used_size` read the live values; the suite asserts they
/// match these pins.
pub const NIS_CONFIG_SIZE: Int = 256;
pub const NIS_CONFIG_USED_SIZE: Int = 112;

/// Coefficient-table selectors for `nis_copy_coefficients`.
pub const NIS_COEF_SCALE_F32: Int = 0;   // coef_scale      [64][8] float
pub const NIS_COEF_USM_F32: Int = 1;     // coef_usm        [64][8] float
pub const NIS_COEF_SCALE_FP16: Int = 2;  // coef_scale_fp16 [64][8] uint16 half bits
pub const NIS_COEF_USM_FP16: Int = 3;    // coef_usm_fp16   [64][8] uint16 half bits

/// Coefficient-table payload sizes in bytes.
pub const NIS_COEF_TABLE_BYTES_F32: Int = 2048;  // 64 * 8 * 4
pub const NIS_COEF_TABLE_BYTES_FP16: Int = 1024; // 64 * 8 * 2

// NISConfig field indices (declaration order in NIS_Config.h; each field is
// 4 bytes and there is no padding between them, so both accessors are
// index*4 byte reads).
pub const NIS_FIELD_K_DETECT_RATIO: Int = 0;
pub const NIS_FIELD_K_DETECT_THRES: Int = 1;
pub const NIS_FIELD_K_MIN_CONTRAST_RATIO: Int = 2;
pub const NIS_FIELD_K_RATIO_NORM: Int = 3;
pub const NIS_FIELD_K_CONTRAST_BOOST: Int = 4;
pub const NIS_FIELD_K_EPS: Int = 5;
pub const NIS_FIELD_K_SHARP_START_Y: Int = 6;
pub const NIS_FIELD_K_SHARP_SCALE_Y: Int = 7;
pub const NIS_FIELD_K_SHARP_STRENGTH_MIN: Int = 8;
pub const NIS_FIELD_K_SHARP_STRENGTH_SCALE: Int = 9;
pub const NIS_FIELD_K_SHARP_LIMIT_MIN: Int = 10;
pub const NIS_FIELD_K_SHARP_LIMIT_SCALE: Int = 11;
pub const NIS_FIELD_K_SCALE_X: Int = 12;
pub const NIS_FIELD_K_SCALE_Y: Int = 13;
pub const NIS_FIELD_K_DST_NORM_X: Int = 14;
pub const NIS_FIELD_K_DST_NORM_Y: Int = 15;
pub const NIS_FIELD_K_SRC_NORM_X: Int = 16;
pub const NIS_FIELD_K_SRC_NORM_Y: Int = 17;
pub const NIS_FIELD_K_INPUT_VIEWPORT_ORIGIN_X: Int = 18;
pub const NIS_FIELD_K_INPUT_VIEWPORT_ORIGIN_Y: Int = 19;
pub const NIS_FIELD_K_INPUT_VIEWPORT_WIDTH: Int = 20;
pub const NIS_FIELD_K_INPUT_VIEWPORT_HEIGHT: Int = 21;
pub const NIS_FIELD_K_OUTPUT_VIEWPORT_ORIGIN_X: Int = 22;
pub const NIS_FIELD_K_OUTPUT_VIEWPORT_ORIGIN_Y: Int = 23;
pub const NIS_FIELD_K_OUTPUT_VIEWPORT_WIDTH: Int = 24;
pub const NIS_FIELD_K_OUTPUT_VIEWPORT_HEIGHT: Int = 25;
pub const NIS_FIELD_RESERVED0: Int = 26;
pub const NIS_FIELD_RESERVED1: Int = 27;

// =========================================================================
// Types
// =========================================================================

/// NVScalerUpdateConfig inputs (NIS_Config.h): upscale+sharpen.  Viewport
/// width/height 0 means "use the texture size" (upstream fallback).
pub type NisScalerParams = {
  sharpness: Float32;               // clamped to [0, 1] upstream
  input_viewport_origin_x: Int;
  input_viewport_origin_y: Int;
  input_viewport_width: Int;
  input_viewport_height: Int;
  input_texture_width: Int;
  input_texture_height: Int;
  output_viewport_origin_x: Int;
  output_viewport_origin_y: Int;
  output_viewport_width: Int;
  output_viewport_height: Int;
  output_texture_width: Int;
  output_texture_height: Int;
  hdr_mode: Int;                    // NIS_HDR_MODE_*
}

/// NVSharpenUpdateConfig inputs (NIS_Config.h): sharpen-only (scale 1.0).
pub type NisSharpenParams = {
  sharpness: Float32;
  input_viewport_origin_x: Int;
  input_viewport_origin_y: Int;
  input_viewport_width: Int;
  input_viewport_height: Int;
  input_texture_width: Int;
  input_texture_height: Int;
  output_viewport_origin_x: Int;
  output_viewport_origin_y: Int;
  hdr_mode: Int;
}

/// GPU pixel-path classification (`nis_gpu_path`).
pub const NIS_GPU_PATH_SHADER_ONLY: Int = 1;

/// Typed GPU-path report: v1.0.3 processes pixels only in the NVScaler /
/// NVSharpen compute shaders, so `cpu_pixel_path` is false and the suite
/// reports SKIP for pixel processing (config building is CPU-testable).
pub type NisGpuPath = {
  kind: Int;              // NIS_GPU_PATH_SHADER_ONLY
  cpu_pixel_path: Bool;   // false on v1.0.3
  entry_points: Str;      // "NVScaler,NVSharpen" (NIS_Scaler.h)
  reason: Str;
}

// =========================================================================
// Config lifecycle
// =========================================================================

/// sizeof(NISConfig) as the SDK defines it: 112 bytes of fields rounded to
/// the 256-byte struct alignment (the upstream samples use this value for
/// the GPU constant-buffer size).
/// Complexity: O(1).
pub fn nis_config_size() -> Int
  requires: true
{
  return unsafe { nis_bridge_config_size() as Int };
}

/// Bytes actually written by the update functions (the 28 fields).
/// Complexity: O(1).
pub fn nis_config_used_size() -> Int
  requires: true
{
  return unsafe { nis_bridge_config_used_size() as Int };
}

/// A zeroed config buffer of exactly `nis_config_size()` bytes, owned by the
/// caller.  Pass it to the update functions, then upload its bytes as the
/// shader constant buffer.
/// Complexity: O(size).
pub fn nis_config_new() -> Vec[UInt8]
  requires: true
{
  var cfg: Vec[UInt8] = Vec[UInt8].new();
  let n = nis_config_size();
  var i = 0;
  while i < n {
    cfg.push(0 as UInt8);
    i = i + 1;
  }
  return cfg;
}

// =========================================================================
// CPU config builders (100% of the NVScaler/NVSharpen CPU surface)
// =========================================================================

/// Fill `cfg` with an NVScaler (upscale+sharpen) configuration.
/// Returns false when the SDK rejects the parameters (zero viewport, scale
/// outside [0.5, 1.0], or an invalid HDR mode) -- the buffer then holds the
/// partially written config, mirroring upstream.
/// Complexity: O(1).
pub fn nis_scaler_update_config(cfg: &mut Vec[UInt8], p: &NisScalerParams) -> Bool
  requires: cfg.len() >= NIS_CONFIG_SIZE
  requires: p.hdr_mode >= 0
  requires: p.hdr_mode <= 2
{
  let rc = unsafe {
    nis_bridge_scaler_update(cfg.as_mut_ptr(), p.sharpness,
      p.input_viewport_origin_x as Int32, p.input_viewport_origin_y as Int32,
      p.input_viewport_width as Int32, p.input_viewport_height as Int32,
      p.input_texture_width as Int32, p.input_texture_height as Int32,
      p.output_viewport_origin_x as Int32, p.output_viewport_origin_y as Int32,
      p.output_viewport_width as Int32, p.output_viewport_height as Int32,
      p.output_texture_width as Int32, p.output_texture_height as Int32,
      p.hdr_mode as Int32) as Int
  };
  return rc == 1;
}

/// Fill `cfg` with an NVSharpen (sharpen-only) configuration: the output
/// viewport equals the input viewport (scale 1.0), per upstream.
/// Returns false on zero viewport / invalid HDR mode / invalid range.
/// Complexity: O(1).
pub fn nis_sharpen_update_config(cfg: &mut Vec[UInt8], p: &NisSharpenParams) -> Bool
  requires: cfg.len() >= NIS_CONFIG_SIZE
  requires: p.hdr_mode >= 0
  requires: p.hdr_mode <= 2
{
  let rc = unsafe {
    nis_bridge_sharpen_update(cfg.as_mut_ptr(), p.sharpness,
      p.input_viewport_origin_x as Int32, p.input_viewport_origin_y as Int32,
      p.input_viewport_width as Int32, p.input_viewport_height as Int32,
      p.input_texture_width as Int32, p.input_texture_height as Int32,
      p.output_viewport_origin_x as Int32, p.output_viewport_origin_y as Int32,
      p.hdr_mode as Int32) as Int
  };
  return rc == 1;
}

// =========================================================================
// Config field access (owned-buffer reads, byte-indexed)
// =========================================================================

/// Read float field `field` (NIS_FIELD_K_*; 0..17 and 26..27) of a config
/// buffer built by this package.  Integer fields read as 0.0.
/// Complexity: O(1).
pub fn nis_config_field_f32(cfg: &Vec[UInt8], field: Int) -> Float32
  requires: cfg.len() >= NIS_CONFIG_USED_SIZE
  requires: field >= 0
  requires: field < 28
{
  return unsafe { nis_bridge_config_f32(cfg.as_mut_ptr(), field as Int32) };
}

/// Read integer field `field` (18..25) of a config buffer.  Float fields
/// read as 0.
/// Complexity: O(1).
pub fn nis_config_field_u32(cfg: &Vec[UInt8], field: Int) -> Int
  requires: cfg.len() >= NIS_CONFIG_USED_SIZE
  requires: field >= 0
  requires: field < 28
{
  return unsafe { nis_bridge_config_u32(cfg.as_mut_ptr(), field as Int32) as Int };
}

// =========================================================================
// Dispatch geometry (NISOptimizer)
// =========================================================================

/// Optimal block width for the target GPU architecture (always 32 in
/// v1.0.3; kept data-driven so a re-pin picks up upstream changes).
/// Complexity: O(1).
pub fn nis_optimal_block_width(is_upscaling: Bool, arch: Int) -> Int
  requires: arch >= 0
  requires: arch <= 3
{
  var up: Int32 = 0;
  if is_upscaling { up = 1; }
  return unsafe { nis_bridge_optimal_block_width(up, arch as Int32) as Int };
}

/// Optimal block height for the target GPU architecture.
/// Complexity: O(1).
pub fn nis_optimal_block_height(is_upscaling: Bool, arch: Int) -> Int
  requires: arch >= 0
  requires: arch <= 3
{
  var up: Int32 = 0;
  if is_upscaling { up = 1; }
  return unsafe { nis_bridge_optimal_block_height(up, arch as Int32) as Int };
}

/// Optimal thread-group size for the target GPU architecture.
/// Complexity: O(1).
pub fn nis_optimal_thread_group_size(is_upscaling: Bool, arch: Int) -> Int
  requires: arch >= 0
  requires: arch <= 3
{
  var up: Int32 = 0;
  if is_upscaling { up = 1; }
  return unsafe { nis_bridge_optimal_thread_group_size(up, arch as Int32) as Int };
}

// =========================================================================
// Coefficient tables (owned copies for GPU upload)
// =========================================================================

/// Copy one coefficient table (NIS_COEF_*) into a new owned buffer of
/// NIS_COEF_TABLE_BYTES_F32 (f32 tables) or NIS_COEF_TABLE_BYTES_FP16
/// (fp16 tables) bytes.  Err on an unknown selector.
/// Complexity: O(table).
pub fn nis_copy_coefficients(table: Int) -> Result[Vec[UInt8], Str]
  requires: table >= 0
  requires: table <= 3
{
  var bytes = NIS_COEF_TABLE_BYTES_F32;
  if table == NIS_COEF_SCALE_FP16 || table == NIS_COEF_USM_FP16 {
    bytes = NIS_COEF_TABLE_BYTES_FP16;
  }
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < bytes {
    out.push(0 as UInt8);
    i = i + 1;
  }
  let rc = unsafe { nis_bridge_copy_coefficients(table as Int32, out.as_mut_ptr(), bytes as Int32) as Int };
  if rc != bytes {
    return Err("nis.coefficients: copy failed (selector " + fi_str(table) + ")");
  }
  return Ok(out);
}

/// Read the f32 at `byte_offset` of an owned byte buffer (e.g. a
/// coefficient table); offset must be 4-byte aligned.
/// Complexity: O(1).
pub fn nis_buf_f32(data: &Vec[UInt8], byte_offset: Int) -> Float32
  requires: byte_offset >= 0
  requires: byte_offset + 4 <= data.len()
  requires: (byte_offset % 4) == 0
{
  return unsafe { nis_bridge_buf_f32(data.as_mut_ptr(), byte_offset as Int32) };
}

// =========================================================================
// GPU pixel path (typed SKIP)
// =========================================================================

/// The GPU (compute-shader) pixel path descriptor.  v1.0.3 has no
/// CPU/scalar pixel implementation, so this reports
/// NIS_GPU_PATH_SHADER_ONLY with `cpu_pixel_path == false`; consumers
/// dispatch NVScaler/NVSharpen in their rendering pipeline, and CPU-only
/// hosts report SKIP.
/// Complexity: O(1).
pub fn nis_gpu_path() -> NisGpuPath
  requires: true
{
  return NisGpuPath{
    kind: NIS_GPU_PATH_SHADER_ONLY;
    cpu_pixel_path: false;
    entry_points: "NVScaler,NVSharpen";
    reason: "NIS v1.0.3 pixel processing is compute-shader-only (NIS_Scaler.h HLSL/GLSL); no CPU/scalar path exists -- GPU dispatch is SKIP on CPU-only hosts";
  };
}

// =========================================================================
// Internals
// =========================================================================

fn fi_str(n: Int) -> Str
  requires: n >= 0
{
  if n == 0 { return "0"; }
  var val = n;
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
  return buf;
}
