// xiom.nis conformance suite -- vendored NIS v1.0.3 config surface.
//
// Everything here runs on the CPU against the real vendored SDK code
// (vendor/NIS/NIS_Config.h compiled into the test binary through
// src/nis_bridge.cpp): the checks assert the exact NVScaler/NVSharpen
// config values the upstream builders produce -- scale/norm ratios,
// viewport fallbacks, sharpness clamping, HDR constant sets, optimizer
// geometry and the coefficient tables.
//
// The GPU pixel path (NVScaler/NVSharpen compute shaders) is a TYPED SKIP:
// v1.0.3 ships no CPU/scalar pixel implementation.  The suite reports the
// typed SKIP with the descriptor from nis_gpu_path() and checks the shader
// API surface at source level (entry points declared in the vendored
// NIS_Scaler.h; the NIS_Main.hlsl/.glsl dispatch files include it).
//
// Build+run (the C++ bridge from port.args.json):
//   scripts/port.ps1 -Package xiom.nis

module nis_conformance

use xiom.io;
use xiom.test;
use xiom.nis;
use xiom.string;

fn report(ok: Bool, name: Str) -> Int {
  if ok {
    io.println("  [PASS] " + name);
    io.flush_stdout();
    return 0;
  }
  io.println("  [FAIL] " + name);
  io.flush_stdout();
  return 1;
}

fn i2s(n: Int) -> Str {
  if n == 0 { return "0"; }
  if n < 0 { return "-" + i2s(0 - n); }
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

fn f32_approx(a: Float32, b: Float32, eps: Float32) -> Bool {
  var diff = a - b;
  if diff < 0.0 { diff = -diff; }
  return diff < eps;
}

fn f32_4(a: Float32, b: Float32) -> Bool {
  return f32_approx(a, b, 0.0001);
}

fn f32_6(a: Float32, b: Float32) -> Bool {
  return f32_approx(a, b, 0.000001);
}

// ---- byte-level text search over a vendored source file --------------------

fn contains_text(hay: &Vec[UInt8], needle: Str) -> Bool {
  let n = needle.len();
  if n == 0 { return true; }
  if hay.len() < n { return false; }
  var i = 0;
  var found = false;
  while i + n <= hay.len() {
    var j = 0;
    var matched = true;
    while j < n {
      if (hay[i + j] as Int) != (string.byte_at(needle, j) as Int) { matched = false; }
      j = j + 1;
    }
    if matched {
      found = true;
      i = hay.len();
    } else {
      i = i + 1;
    }
  }
  return found;
}

fn read_text(rel: Str) -> Vec[UInt8] {
  let r1 = io.read_file_bytes(rel);
  if r1.is_ok { return r1.value; }
  let r2 = io.read_file_bytes("packages/xiom-nis/" + rel);
  if r2.is_ok { return r2.value; }
  return Vec[UInt8].new();
}

fn u16_le(b: &Vec[UInt8], off: Int) -> Int
  requires: b.len() >= off + 2
{
  return (b[off] as Int) | ((b[off + 1] as Int) << 8);
}

// ---- scaler / sharpen checks ------------------------------------------------

fn mk_scaler(sharp: Float32, iw: Int, ih: Int, ow: Int, oh: Int, hdr: Int) -> NisScalerParams {
  return NisScalerParams{
    sharpness: sharp;
    input_viewport_origin_x: 0; input_viewport_origin_y: 0;
    input_viewport_width: 0; input_viewport_height: 0;
    input_texture_width: iw; input_texture_height: ih;
    output_viewport_origin_x: 0; output_viewport_origin_y: 0;
    output_viewport_width: 0; output_viewport_height: 0;
    output_texture_width: ow; output_texture_height: oh;
    hdr_mode: hdr;
  };
}

fn run_scaler_checks(failed: Int) -> Int {
  var out = failed;

  // 1920x1080 -> 2560x1440 @ 0.5 (the canonical 0.75-scale case).
  var cfg = nis_config_new();
  let p = mk_scaler(0.5, 1920, 1080, 2560, 1440, NIS_HDR_MODE_NONE);
  let ok075 = nis_scaler_update_config(&mut cfg, &p);
  out = out + report(ok075, "scaler: 1920x1080 -> 2560x1440 @0.5 accepted");
  out = out + report(
    f32_4(nis_config_field_f32(&cfg, NIS_FIELD_K_SCALE_X), 0.75)
      && f32_4(nis_config_field_f32(&cfg, NIS_FIELD_K_SCALE_Y), 0.75),
    "scaler: kScaleX/kScaleY = 0.75 (input/output viewport ratio)");
  out = out + report(
    f32_6(nis_config_field_f32(&cfg, NIS_FIELD_K_SRC_NORM_X), 0.000520833)
      && f32_6(nis_config_field_f32(&cfg, NIS_FIELD_K_DST_NORM_X), 0.000390625),
    "scaler: kSrcNormX=1/1920, kDstNormX=1/2560");
  out = out + report(
    nis_config_field_u32(&cfg, NIS_FIELD_K_INPUT_VIEWPORT_WIDTH) == 1920
      && nis_config_field_u32(&cfg, NIS_FIELD_K_INPUT_VIEWPORT_HEIGHT) == 1080
      && nis_config_field_u32(&cfg, NIS_FIELD_K_OUTPUT_VIEWPORT_WIDTH) == 2560
      && nis_config_field_u32(&cfg, NIS_FIELD_K_OUTPUT_VIEWPORT_HEIGHT) == 1440
      && nis_config_field_u32(&cfg, NIS_FIELD_K_INPUT_VIEWPORT_ORIGIN_X) == 0,
    "scaler: zero viewports fall back to texture dims (origins 0)");
  out = out + report(
    f32_4(nis_config_field_f32(&cfg, NIS_FIELD_K_DETECT_RATIO), 2.2011719)
      && f32_4(nis_config_field_f32(&cfg, NIS_FIELD_K_DETECT_THRES), 0.0625)
      && f32_4(nis_config_field_f32(&cfg, NIS_FIELD_K_MIN_CONTRAST_RATIO), 2.0)
      && f32_4(nis_config_field_f32(&cfg, NIS_FIELD_K_RATIO_NORM), 0.125)
      && f32_4(nis_config_field_f32(&cfg, NIS_FIELD_K_CONTRAST_BOOST), 1.0)
      && f32_6(nis_config_field_f32(&cfg, NIS_FIELD_K_EPS), 0.003921569),
    "scaler: SDR constant set (detect 2.20117/0.0625, contrast 2.0, norm 0.125, eps 1/255)");
  out = out + report(
    f32_4(nis_config_field_f32(&cfg, NIS_FIELD_K_SHARP_START_Y), 0.45)
      && f32_4(nis_config_field_f32(&cfg, NIS_FIELD_K_SHARP_SCALE_Y), 2.2222222)
      && f32_4(nis_config_field_f32(&cfg, NIS_FIELD_K_SHARP_STRENGTH_MIN), 0.4)
      && f32_4(nis_config_field_f32(&cfg, NIS_FIELD_K_SHARP_STRENGTH_SCALE), 1.2)
      && f32_4(nis_config_field_f32(&cfg, NIS_FIELD_K_SHARP_LIMIT_MIN), 0.14)
      && f32_4(nis_config_field_f32(&cfg, NIS_FIELD_K_SHARP_LIMIT_SCALE), 0.36),
    "scaler: sharpness 0.5 -> strength 0.4+1.2, limit 0.14+0.36, startY 0.45");
  out = out + report(
    nis_buf_f32(&cfg, 48) == nis_config_field_f32(&cfg, NIS_FIELD_K_SCALE_X),
    "scaler: byte-offset f32 read (48 = kScaleX) == field accessor");

  // Viewport subset: 1280x720 region of a 1920x1080 texture -> 2560x1440
  // (exactly the 0.5 boundary, accepted by upstream's [0.5, 1.0] check).
  var cfg2 = nis_config_new();
  var p2 = mk_scaler(0.5, 1920, 1080, 2560, 1440, NIS_HDR_MODE_NONE);
  p2.input_viewport_width = 1280;
  p2.input_viewport_height = 720;
  p2.input_viewport_origin_x = 100;
  p2.input_viewport_origin_y = 50;
  let ok05 = nis_scaler_update_config(&mut cfg2, &p2);
  out = out + report(
    ok05
      && f32_4(nis_config_field_f32(&cfg2, NIS_FIELD_K_SCALE_X), 0.5)
      && nis_config_field_u32(&cfg2, NIS_FIELD_K_INPUT_VIEWPORT_WIDTH) == 1280
      && nis_config_field_u32(&cfg2, NIS_FIELD_K_INPUT_VIEWPORT_ORIGIN_X) == 100
      && nis_config_field_u32(&cfg2, NIS_FIELD_K_INPUT_VIEWPORT_ORIGIN_Y) == 50,
    "scaler: viewport subset 1280x720+origin(100,50) -> scale 0.5 accepted");

  // Scale below 0.5: rejected, scale written.
  var cfg3 = nis_config_new();
  let p3 = mk_scaler(0.5, 640, 360, 2560, 1440, NIS_HDR_MODE_NONE);
  let ok025 = nis_scaler_update_config(&mut cfg3, &p3);
  out = out + report(
    !ok025 && f32_4(nis_config_field_f32(&cfg3, NIS_FIELD_K_SCALE_X), 0.25),
    "scaler: scale 0.25 rejected (kScaleX 0.25 written)");

  // Downscale (scale > 1.0): rejected.
  var cfg4 = nis_config_new();
  let p4 = mk_scaler(0.5, 3840, 2160, 1920, 1080, NIS_HDR_MODE_NONE);
  let ok20 = nis_scaler_update_config(&mut cfg4, &p4);
  out = out + report(!ok20, "scaler: scale 2.0 (downscale) rejected");

  // Zero texture: rejected by the zero-viewport guard.
  var cfg5 = nis_config_new();
  let p5 = mk_scaler(0.5, 0, 0, 0, 0, NIS_HDR_MODE_NONE);
  let ok00 = nis_scaler_update_config(&mut cfg5, &p5);
  out = out + report(!ok00, "scaler: zero texture/viewport rejected");

  // Sharpness clamp high: 2.0 -> 1.0 (slider 0.5).
  var cfgh = nis_config_new();
  let ph = mk_scaler(2.0, 1920, 1080, 2560, 1440, NIS_HDR_MODE_NONE);
  let okh = nis_scaler_update_config(&mut cfgh, &ph);
  out = out + report(
    okh
      && f32_4(nis_config_field_f32(&cfgh, NIS_FIELD_K_SHARP_STRENGTH_MIN), 1.15)
      && f32_4(nis_config_field_f32(&cfgh, NIS_FIELD_K_SHARP_STRENGTH_SCALE), 1.575)
      && f32_4(nis_config_field_f32(&cfgh, NIS_FIELD_K_SHARP_LIMIT_MIN), 0.34)
      && f32_4(nis_config_field_f32(&cfgh, NIS_FIELD_K_SHARP_LIMIT_SCALE), 0.535),
    "scaler: sharpness 2.0 clamped to 1.0 (strength 1.15+1.575, limit 0.34+0.535)");

  // Sharpness clamp low: -1.0 -> 0.0 (slider -0.5).
  var cfgl = nis_config_new();
  let pl = mk_scaler(-1.0, 1920, 1080, 2560, 1440, NIS_HDR_MODE_NONE);
  let okl = nis_scaler_update_config(&mut cfgl, &pl);
  out = out + report(
    okl
      && f32_4(nis_config_field_f32(&cfgl, NIS_FIELD_K_SHARP_STRENGTH_MIN), 0.0)
      && f32_4(nis_config_field_f32(&cfgl, NIS_FIELD_K_SHARP_STRENGTH_SCALE), 0.025)
      && f32_4(nis_config_field_f32(&cfgl, NIS_FIELD_K_SHARP_LIMIT_MIN), 0.1)
      && f32_4(nis_config_field_f32(&cfgl, NIS_FIELD_K_SHARP_LIMIT_SCALE), 0.1),
    "scaler: sharpness -1.0 clamped to 0.0 (strength 0+0.025, limit 0.1+0.1)");

  // HDR Linear constant set.
  var cfgin = nis_config_new();
  let pin = mk_scaler(0.5, 1920, 1080, 2560, 1440, NIS_HDR_MODE_LINEAR);
  let okin = nis_scaler_update_config(&mut cfgin, &pin);
  out = out + report(
    okin
      && f32_4(nis_config_field_f32(&cfgin, NIS_FIELD_K_DETECT_THRES), 0.03125)
      && f32_4(nis_config_field_f32(&cfgin, NIS_FIELD_K_MIN_CONTRAST_RATIO), 1.5)
      && f32_4(nis_config_field_f32(&cfgin, NIS_FIELD_K_RATIO_NORM), 0.2857143)
      && f32_4(nis_config_field_f32(&cfgin, NIS_FIELD_K_SHARP_START_Y), 0.3)
      && f32_4(nis_config_field_f32(&cfgin, NIS_FIELD_K_SHARP_SCALE_Y), 5.0)
      && f32_4(nis_config_field_f32(&cfgin, NIS_FIELD_K_SHARP_STRENGTH_SCALE), 1.8),
    "scaler: HDR Linear constants (thres 0.03125, startY 0.3, scaleY 5.0)");

  // HDR PQ constant set.
  var cfgpq = nis_config_new();
  let ppq = mk_scaler(0.5, 1920, 1080, 2560, 1440, NIS_HDR_MODE_PQ);
  let okpq = nis_scaler_update_config(&mut cfgpq, &ppq);
  out = out + report(
    okpq
      && f32_4(nis_config_field_f32(&cfgpq, NIS_FIELD_K_SHARP_START_Y), 0.35)
      && f32_4(nis_config_field_f32(&cfgpq, NIS_FIELD_K_SHARP_SCALE_Y), 5.0)
      && f32_4(nis_config_field_f32(&cfgpq, NIS_FIELD_K_DETECT_THRES), 0.03125),
    "scaler: HDR PQ constants (startY 0.35, scaleY 5.0)");

  return out;
}

fn run_sharpen_checks(failed: Int) -> Int {
  var out = failed;
  var cfg = nis_config_new();
  let p = NisSharpenParams{
    sharpness: 0.5;
    input_viewport_origin_x: 0; input_viewport_origin_y: 0;
    input_viewport_width: 0; input_viewport_height: 0;
    input_texture_width: 1920; input_texture_height: 1080;
    output_viewport_origin_x: 100; output_viewport_origin_y: 50;
    hdr_mode: NIS_HDR_MODE_NONE;
  };
  let ok = nis_sharpen_update_config(&mut cfg, &p);
  out = out + report(
    ok
      && f32_4(nis_config_field_f32(&cfg, NIS_FIELD_K_SCALE_X), 1.0)
      && f32_4(nis_config_field_f32(&cfg, NIS_FIELD_K_SCALE_Y), 1.0)
      && nis_config_field_u32(&cfg, NIS_FIELD_K_OUTPUT_VIEWPORT_WIDTH) == 1920
      && nis_config_field_u32(&cfg, NIS_FIELD_K_OUTPUT_VIEWPORT_HEIGHT) == 1080
      && nis_config_field_u32(&cfg, NIS_FIELD_K_OUTPUT_VIEWPORT_ORIGIN_X) == 100
      && nis_config_field_u32(&cfg, NIS_FIELD_K_OUTPUT_VIEWPORT_ORIGIN_Y) == 50,
    "sharpen: scale 1.0, output viewport = input, out origin (100,50) propagated");
  return out;
}

fn run_optimizer_checks(failed: Int) -> Int {
  var out = failed;
  let w_ok = nis_optimal_block_width(true, NIS_GPU_ARCH_NVIDIA_GENERIC) == 32
    && nis_optimal_block_width(false, NIS_GPU_ARCH_NVIDIA_GENERIC) == 32
    && nis_optimal_block_width(true, NIS_GPU_ARCH_AMD_GENERIC) == 32
    && nis_optimal_block_width(true, NIS_GPU_ARCH_INTEL_GENERIC) == 32
    && nis_optimal_block_width(true, NIS_GPU_ARCH_NVIDIA_GENERIC_FP16) == 32;
  out = out + report(w_ok, "optimizer: block width 32 on all four architectures");
  let h_ok = nis_optimal_block_height(true, NIS_GPU_ARCH_NVIDIA_GENERIC) == 24
    && nis_optimal_block_height(false, NIS_GPU_ARCH_NVIDIA_GENERIC) == 32
    && nis_optimal_block_height(true, NIS_GPU_ARCH_NVIDIA_GENERIC_FP16) == 32
    && nis_optimal_block_height(false, NIS_GPU_ARCH_NVIDIA_GENERIC_FP16) == 32
    && nis_optimal_block_height(true, NIS_GPU_ARCH_AMD_GENERIC) == 24
    && nis_optimal_block_height(false, NIS_GPU_ARCH_AMD_GENERIC) == 32
    && nis_optimal_block_height(true, NIS_GPU_ARCH_INTEL_GENERIC) == 24;
  out = out + report(h_ok, "optimizer: block height 24 upscale / 32 sharpen (fp16 32/32)");
  let t_ok = nis_optimal_thread_group_size(true, NIS_GPU_ARCH_NVIDIA_GENERIC) == 128
    && nis_optimal_thread_group_size(true, NIS_GPU_ARCH_NVIDIA_GENERIC_FP16) == 128
    && nis_optimal_thread_group_size(true, NIS_GPU_ARCH_AMD_GENERIC) == 256
    && nis_optimal_thread_group_size(false, NIS_GPU_ARCH_INTEL_GENERIC) == 256;
  out = out + report(t_ok, "optimizer: thread groups 128 (NV, fp16) / 256 (AMD, Intel)");
  return out;
}

fn run_coefficient_checks(failed: Int) -> Int {
  var out = failed;

  let rs = nis_copy_coefficients(NIS_COEF_SCALE_F32);
  if !rs.is_ok {
    return out + report(false, "coef: scale f32 copy failed -- " + rs.error);
  }
  let scale: Vec[UInt8] = rs.value;
  out = out + report(scale.len() == NIS_COEF_TABLE_BYTES_F32,
    "coef: coef_scale f32 is " + i2s(scale.len()) + " bytes (64 phases x 8 taps x 4)");
  let row0_ok = f32_6(nis_buf_f32(&scale, 0), 0.0)
    && f32_6(nis_buf_f32(&scale, 4), 0.0)
    && f32_6(nis_buf_f32(&scale, 8), 1.0)
    && f32_6(nis_buf_f32(&scale, 12), 0.0);
  let row32 = 32 * 32;
  let pal_ok = f32_4(nis_buf_f32(&scale, row32), 0.0244)
    && f32_4(nis_buf_f32(&scale, row32 + 4), -0.1357)
    && f32_4(nis_buf_f32(&scale, row32 + 8), 0.6113)
    && f32_4(nis_buf_f32(&scale, row32 + 12), 0.6113)
    && f32_4(nis_buf_f32(&scale, row32 + 16), -0.1357)
    && f32_4(nis_buf_f32(&scale, row32 + 20), 0.0244)
    && f32_4(nis_buf_f32(&scale, row32 + 24), 0.0);
  out = out + report(row0_ok && pal_ok,
    "coef: scale row0 {0,0,1,0} and center phase 32 palindromic");

  let ru = nis_copy_coefficients(NIS_COEF_USM_F32);
  if !ru.is_ok {
    return out + report(false, "coef: usm f32 copy failed -- " + ru.error);
  }
  let usm: Vec[UInt8] = ru.value;
  out = out + report(
    usm.len() == NIS_COEF_TABLE_BYTES_F32
      && f32_6(nis_buf_f32(&usm, 0), 0.0)
      && f32_4(nis_buf_f32(&usm, 4), -0.6001)
      && f32_4(nis_buf_f32(&usm, 8), 1.2002)
      && f32_4(nis_buf_f32(&usm, 12), -0.6001),
    "coef: coef_usm f32 row0 {0,-0.6001,1.2002,-0.6001}");

  let rf = nis_copy_coefficients(NIS_COEF_SCALE_FP16);
  if !rf.is_ok {
    return out + report(false, "coef: scale fp16 copy failed -- " + rf.error);
  }
  let half: Vec[UInt8] = rf.value;
  out = out + report(
    half.len() == NIS_COEF_TABLE_BYTES_FP16
      && u16_le(&half, 0) == 0
      && u16_le(&half, 2) == 0
      && u16_le(&half, 4) == 15360
      && u16_le(&half, 6) == 0,
    "coef: coef_scale_fp16 is " + i2s(half.len()) + " bytes; row0 half bits {0,0,15360(1.0),0}");
  return out;
}

fn run_gpu_path_checks(failed: Int) -> Int {
  var out = failed;

  let gp = nis_gpu_path();
  out = out + report(
    gp.kind == NIS_GPU_PATH_SHADER_ONLY && !gp.cpu_pixel_path
      && gp.entry_points == "NVScaler,NVSharpen",
    "gpu: SKIP -- typed shader-only path (" + gp.reason + ")");

  let scaler_src = read_text("vendor/NIS/NIS_Scaler.h");
  let main_hlsl = read_text("vendor/NIS/NIS_Main.hlsl");
  let main_glsl = read_text("vendor/NIS/NIS_Main.glsl");
  if scaler_src.len() == 0 || main_hlsl.len() == 0 || main_glsl.len() == 0 {
    out = out + report(false, "gpu: vendored shader sources missing");
    return out;
  }
  let entries_ok = contains_text(&scaler_src, "void NVScaler(NVU2 blockIdx, NVU threadIdx)")
    && contains_text(&scaler_src, "void NVSharpen(NVU2 blockIdx, NVU threadIdx)");
  let dispatch_ok = contains_text(&main_hlsl, "#include \"NIS_Scaler.h\"")
    && contains_text(&main_hlsl, "NVScaler(blockIdx.xy, threadIdx.x)")
    && contains_text(&main_glsl, "#include \"NIS_Scaler.h\"");
  out = out + report(true, "gpu: SKIP -- pixel processing runs in the NVScaler/NVSharpen compute shaders only");
  out = out + report(entries_ok && dispatch_ok,
    "gpu: shader API surface present (NIS_Scaler.h entry points + NIS_Main dispatch includes)");
  return out;
}

fn main() -> Int {
  io.println("=== xiom.nis conformance tests (vendored NIS v1.0.3 config surface) ===");
  io.flush_stdout();
  var failed: Int = 0;

  var out: Int = report(nis_config_size() == NIS_CONFIG_SIZE && nis_config_used_size() == NIS_CONFIG_USED_SIZE,
    "abi: NISConfig sizeof " + i2s(nis_config_size()) + " (pin " + i2s(NIS_CONFIG_SIZE)
      + "), field payload " + i2s(nis_config_used_size()) + " (pin " + i2s(NIS_CONFIG_USED_SIZE) + ")");
  out = report(NIS_PHASE_COUNT == 64 && NIS_FILTER_SIZE == 8
    && NIS_COEF_TABLE_BYTES_F32 == NIS_PHASE_COUNT * NIS_FILTER_SIZE * 4
    && NIS_COEF_TABLE_BYTES_FP16 == NIS_PHASE_COUNT * NIS_FILTER_SIZE * 2,
    "abi: filter geometry pins (64 phases x 8 taps, f32 2048 B / fp16 1024 B)");

  out = run_scaler_checks(out);
  out = run_sharpen_checks(out);
  out = run_optimizer_checks(out);
  out = run_coefficient_checks(out);
  out = run_gpu_path_checks(out);

  if out == 0 {
    io.println("xiom.nis: all tests passed");
  } else {
    io.println("xiom.nis: tests failed");
  }
  return out;
}
