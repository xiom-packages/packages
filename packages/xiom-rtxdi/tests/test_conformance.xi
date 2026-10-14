// XIOM -- xiom.rtxdi conformance suite (0.1.0).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// 33 checks, identical count on every host:
//   SECTION A (9): always-run -- SKIP-path classification, ABI mirror layout
//     tables (20 structs against the pinned header anchors), constant table
//     (sizes, macros, enums), bridge-carried SDK defaults + owned-image
//     roundtrip, signed/byte decode helpers, IS static-params image plumbing,
//     typed execute classification without a context.
//   SECTION B (23): runtime-dependent -- shim info, 20-kind layout drift
//     check, 7-kind defaults drift check, runtime utilities (reservoir
//     parameters, PDF texture size, JenkinsHash, neighbor offsets), ReSTIRDI
//     context lifecycle + static parameters, per-frame plan (runtime params +
//     buffer index rotation + uniform random number), parameter roundtrip
//     through the context, RIS segment allocator, ReGIR grid + onion
//     calculated parameters + dynamic parameters, top-level
//     ImportanceSamplingContext (RIS segments, light buffer set/get, child
//     handles), and the typed GPU-execution classification
//     (RTXDI_EXEC_NO_DEVICE -> SKIP).
//     Without the shim module (default PATH), each B check reports "SKIP"
//     and stays green (classified platform state, not a gap).
//
// Runtime: xiom_rtxdi_shim.dll built locally from the pinned RTXDI-Library
// revision by the licensee -- `XIOM_RTXDI_SHIM` env var or the default module
// search.  Run: scripts/port.ps1 -Package xiom.rtxdi -TimeoutSec 240

module rtxdi_conformance

use xiom.io;
use xiom.test;
use xiom.rtxdi;

// =========================================================================
// Helpers
// =========================================================================

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

fn skip(name: Str) -> Int {
  return report(true, name + " -- SKIP (no RTXDI shim module present)");
}

fn f2s(v: Float32) -> Str {
  var scaled = (v * (1000 as Float32)) as Int;
  var neg = "";
  if scaled < 0 { neg = "-"; scaled = 0 - scaled; }
  return neg + i2s(scaled / 1000) + "." + i2s(scaled % 1000);
}

fn near(a: Float32, b: Float32, tol: Float32) -> Bool {
  var d = a - b;
  if d < (0 as Float32) { d = (0 as Float32) - d; }
  return d < tol;
}

// =========================================================================
// SECTION A -- always-run (no shim needed)
// =========================================================================

fn test_a1_skip_path_classification() -> TestResult {
  let r = rtxdi_load_named("xiom-absent-rtxdi-probe-xyz.dll");
  var ok = false;
  if r.is_err {
    ok = r.error.kind == RTXDI_LOAD_ABSENT;
  }
  return assert(ok, "skip-path: absent module classified as RTXDI_LOAD_ABSENT");
}

fn test_a2_di_layouts() -> TestResult {
  let l0 = rtxdi_layout(RTXDI_LAYOUT_RESERVOIR);
  let l1 = rtxdi_layout(RTXDI_LAYOUT_RUNTIME);
  let l2 = rtxdi_layout(RTXDI_LAYOUT_BUFFER_INDICES);
  let l3 = rtxdi_layout(RTXDI_LAYOUT_INITIAL);
  let l4 = rtxdi_layout(RTXDI_LAYOUT_TEMPORAL);
  let l5 = rtxdi_layout(RTXDI_LAYOUT_BOILING);
  let l6 = rtxdi_layout(RTXDI_LAYOUT_SPATIAL);
  let l7 = rtxdi_layout(RTXDI_LAYOUT_SPATIOTEMPORAL);
  let l8 = rtxdi_layout(RTXDI_LAYOUT_SHADING);
  var ok = l0.is_ok && l1.is_ok && l2.is_ok && l3.is_ok && l4.is_ok && l5.is_ok
    && l6.is_ok && l7.is_ok && l8.is_ok;
  var msg = "layout: DI table fetch failed";
  if ok {
    ok = rtxdi_mirror_size(RTXDI_LAYOUT_RESERVOIR) == RTXDI_SIZE_RESERVOIR && l0.value.count == 2
      && rtxdi_mirror_size(RTXDI_LAYOUT_RUNTIME) == RTXDI_SIZE_RUNTIME && l1.value.count == 3
      && rtxdi_mirror_size(RTXDI_LAYOUT_BUFFER_INDICES) == RTXDI_SIZE_BUFFER_INDICES && l2.value.count == 6
      && rtxdi_mirror_size(RTXDI_LAYOUT_INITIAL) == RTXDI_SIZE_INITIAL && l3.value.count == 9
      && rtxdi_mirror_size(RTXDI_LAYOUT_TEMPORAL) == RTXDI_SIZE_TEMPORAL && l4.value.count == 8
      && rtxdi_mirror_size(RTXDI_LAYOUT_BOILING) == RTXDI_SIZE_BOILING && l5.value.count == 2
      && rtxdi_mirror_size(RTXDI_LAYOUT_SPATIAL) == RTXDI_SIZE_SPATIAL && l6.value.count == 9
      && rtxdi_mirror_size(RTXDI_LAYOUT_SPATIOTEMPORAL) == RTXDI_SIZE_SPATIOTEMPORAL && l7.value.count == 12
      && rtxdi_mirror_size(RTXDI_LAYOUT_SHADING) == RTXDI_SIZE_SHADING && l8.value.count == 5;
    ok = ok && rtxdi_layout_field_offset(&l2.value, RTXDI_F_INDICES_SHADING_IN) == 20;
    ok = ok && rtxdi_layout_field_offset(&l3.value, RTXDI_F_INITIAL_ENV_MAP_IMPORTANCE) == 32;
    ok = ok && rtxdi_layout_field_size(&l3.value, RTXDI_F_INITIAL_BRDF_CUTOFF) == 4;
    ok = ok && rtxdi_layout_field_offset(&l4.value, RTXDI_F_TEMPORAL_UNIFORM_RANDOM) == 24;
    ok = ok && rtxdi_layout_field_offset(&l6.value, RTXDI_F_SPATIAL_DISCOUNT_NAIVE) == 32;
    ok = ok && rtxdi_layout_field_offset(&l7.value, RTXDI_F_ST_SAMPLING_RADIUS) == 36;
    ok = ok && rtxdi_layout_field_offset(&l8.value, RTXDI_F_SHADING_DENOISER_INPUT_PACKING) == 16;
    msg = "layout: DI structs " + i2s(rtxdi_mirror_size(RTXDI_LAYOUT_RESERVOIR)) + "/"
      + i2s(rtxdi_mirror_size(RTXDI_LAYOUT_RUNTIME)) + "/"
      + i2s(rtxdi_mirror_size(RTXDI_LAYOUT_BUFFER_INDICES)) + "/"
      + i2s(rtxdi_mirror_size(RTXDI_LAYOUT_INITIAL)) + "/"
      + i2s(rtxdi_mirror_size(RTXDI_LAYOUT_TEMPORAL)) + "/"
      + i2s(rtxdi_mirror_size(RTXDI_LAYOUT_SPATIAL)) + "/"
      + i2s(rtxdi_mirror_size(RTXDI_LAYOUT_SPATIOTEMPORAL)) + "B + anchors";
  }
  return assert(ok, msg);
}

fn test_a3_buffer_regir_layouts() -> TestResult {
  let l9 = rtxdi_layout(RTXDI_LAYOUT_LIGHT_REGION);
  let l10 = rtxdi_layout(RTXDI_LAYOUT_ENV_LIGHT);
  let l11 = rtxdi_layout(RTXDI_LAYOUT_LIGHT_BUFFER);
  let l12 = rtxdi_layout(RTXDI_LAYOUT_PACKED_RESERVOIR);
  let l13 = rtxdi_layout(RTXDI_LAYOUT_RIS_SEGMENT);
  let l14 = rtxdi_layout(RTXDI_LAYOUT_DI_STATIC);
  let l15 = rtxdi_layout(RTXDI_LAYOUT_REGIR_COMMON);
  let l16 = rtxdi_layout(RTXDI_LAYOUT_REGIR_GRID);
  let l17 = rtxdi_layout(RTXDI_LAYOUT_ONION_LAYER);
  let l18 = rtxdi_layout(RTXDI_LAYOUT_ONION_RING);
  let l19 = rtxdi_layout(RTXDI_LAYOUT_PARAMETERS);
  var ok = l9.is_ok && l10.is_ok && l11.is_ok && l12.is_ok && l13.is_ok && l14.is_ok
    && l15.is_ok && l16.is_ok && l17.is_ok && l18.is_ok && l19.is_ok;
  var msg = "layout: buffer/ReGIR table fetch failed";
  if ok {
    ok = rtxdi_mirror_size(RTXDI_LAYOUT_LIGHT_REGION) == RTXDI_SIZE_LIGHT_REGION
      && rtxdi_mirror_size(RTXDI_LAYOUT_ENV_LIGHT) == RTXDI_SIZE_ENV_LIGHT
      && rtxdi_mirror_size(RTXDI_LAYOUT_LIGHT_BUFFER) == RTXDI_SIZE_LIGHT_BUFFER && l11.value.count == 3
      && rtxdi_layout_field_offset(&l11.value, RTXDI_F_LIGHT_BUFFER_LOCAL) == 0
      && rtxdi_layout_field_offset(&l11.value, RTXDI_F_LIGHT_BUFFER_INFINITE) == 16
      && rtxdi_layout_field_offset(&l11.value, RTXDI_F_LIGHT_BUFFER_ENV) == 32;
    ok = ok && rtxdi_mirror_size(RTXDI_LAYOUT_PACKED_RESERVOIR) == RTXDI_SIZE_PACKED_RESERVOIR && l12.value.count == 6
      && rtxdi_layout_field_offset(&l12.value, RTXDI_F_PACKED_WEIGHT) == 20;
    ok = ok && rtxdi_mirror_size(RTXDI_LAYOUT_RIS_SEGMENT) == RTXDI_SIZE_RIS_SEGMENT && l13.value.count == 3;
    ok = ok && rtxdi_mirror_size(RTXDI_LAYOUT_DI_STATIC) == RTXDI_SIZE_DI_STATIC && l14.value.count == 4;
    ok = ok && rtxdi_mirror_size(RTXDI_LAYOUT_REGIR_COMMON) == RTXDI_SIZE_REGIR_COMMON && l15.value.count == 10
      && rtxdi_mirror_size(RTXDI_LAYOUT_REGIR_GRID) == RTXDI_SIZE_REGIR_GRID && l16.value.count == 3;
    ok = ok && rtxdi_mirror_size(RTXDI_LAYOUT_ONION_LAYER) == RTXDI_SIZE_ONION_LAYER && l17.value.count == 11
      && rtxdi_mirror_size(RTXDI_LAYOUT_ONION_RING) == RTXDI_SIZE_ONION_RING && l18.value.count == 4;
    ok = ok && rtxdi_mirror_size(RTXDI_LAYOUT_PARAMETERS) == RTXDI_SIZE_PARAMETERS && l19.value.count == 8
      && rtxdi_layout_field_offset(&l19.value, 0) == 0
      && rtxdi_layout_field_offset(&l19.value, 1) == 16
      && rtxdi_layout_field_offset(&l19.value, 2) == 48
      && rtxdi_layout_field_offset(&l19.value, 3) == 96
      && rtxdi_layout_field_offset(&l19.value, 4) == 128
      && rtxdi_layout_field_offset(&l19.value, 5) == 144
      && rtxdi_layout_field_offset(&l19.value, 6) == 192
      && rtxdi_layout_field_offset(&l19.value, 7) == 240;
    msg = "layout: light-buffer " + i2s(rtxdi_mirror_size(RTXDI_LAYOUT_LIGHT_BUFFER))
      + "B, onion layer/ring " + i2s(rtxdi_mirror_size(RTXDI_LAYOUT_ONION_LAYER)) + "/"
      + i2s(rtxdi_mirror_size(RTXDI_LAYOUT_ONION_RING)) + "B, RTXDI_Parameters "
      + i2s(rtxdi_mirror_size(RTXDI_LAYOUT_PARAMETERS)) + "B @ 0/16/48/96/128/144/192/240";
  }
  return assert(ok, msg);
}

fn test_a4_constant_table() -> TestResult {
  var ok = RTXDI_VERSION_MAJOR == 3 && RTXDI_VERSION_MINOR == 1 && RTXDI_VERSION_PATCH == 0;
  ok = ok && RTXDI_RESERVOIR_BLOCK_SIZE == 16 && RTXDI_TILE_SIZE_IN_PIXELS == 16;
  ok = ok && RTXDI_ONION_MAX_LAYER_GROUPS == 8 && RTXDI_ONION_MAX_RINGS == 52;
  ok = ok && RTXDI_NAIVE_SAMPLING_M_THRESHOLD == 2;
  ok = ok && RTXDI_LIGHT_COMPACT_BIT == 2147483648 && RTXDI_LIGHT_INDEX_MASK == 2147483647;
  ok = ok && RTXDI_INVALID_LIGHT_INDEX == 4294967295;
  ok = ok && RTXDI_NUM_RESERVOIR_BUFFERS == 3 && RTXDI_ENABLE_PRESAMPLING == 1;
  ok = ok && RTXDI_REGIR_MODE == 0;
  ok = ok && RTXDI_CHECKERBOARD_OFF == 0 && RTXDI_CHECKERBOARD_BLACK == 1 && RTXDI_CHECKERBOARD_WHITE == 2;
  ok = ok && RTXDI_LOCAL_LIGHT_UNIFORM == 0 && RTXDI_LOCAL_LIGHT_POWER_RIS == 1 && RTXDI_LOCAL_LIGHT_REGIR_RIS == 2;
  ok = ok && RTXDI_BIAS_CORRECTION_OFF == 0 && RTXDI_BIAS_CORRECTION_BASIC == 1
    && RTXDI_BIAS_CORRECTION_RAY_TRACED == 2 && RTXDI_BIAS_CORRECTION_PAIRWISE == 3;
  ok = ok && RTXDI_RESAMPLING_NONE == 0 && RTXDI_RESAMPLING_TEMPORAL == 1 && RTXDI_RESAMPLING_SPATIAL == 2
    && RTXDI_RESAMPLING_SPATIOTEMPORAL == 3 && RTXDI_RESAMPLING_FUSED_SPATIOTEMPORAL == 4;
  ok = ok && RTXDI_REGIR_DISABLED == 0 && RTXDI_REGIR_GRID == 1 && RTXDI_REGIR_ONION == 2;
  ok = ok && RTXDI_SIZE_ONION_PARAMETERS == 1232 && RTXDI_SIZE_REGIR_PARAMETERS == 1296;
  return assert(ok, "constants: sizes, block/tile macros, onion limits, light-bit macros and enum encodings match the pinned headers");
}

fn test_a5_defaults_roundtrip() -> TestResult {
  let d = rtxdi_param_default(RTXDI_DEFAULT_TEMPORAL);
  var ok = false;
  var msg = "image: temporal default build failed";
  if d.is_ok {
    var p = d.value;
    ok = p.size == RTXDI_SIZE_TEMPORAL
      && rtxdi_params_get_u32(&p, RTXDI_F_TEMPORAL_MAX_HISTORY) == 20
      && rtxdi_params_get_u32(&p, RTXDI_F_TEMPORAL_BIAS_MODE) == 1
      && near(rtxdi_params_get_f32(&p, RTXDI_F_TEMPORAL_DEPTH_THRESHOLD), 0.1 as Float32, 0.0001 as Float32)
      && near(rtxdi_params_get_f32(&p, RTXDI_F_TEMPORAL_NORMAL_THRESHOLD), 0.5 as Float32, 0.0001 as Float32);
    let s0 = rtxdi_params_set_u32(&mut p, RTXDI_F_TEMPORAL_MAX_HISTORY, 42);
    let s1 = rtxdi_params_set_f32(&mut p, RTXDI_F_TEMPORAL_DEPTH_THRESHOLD, (3 as Float32) / (20 as Float32));
    ok = ok && s0.is_ok && s1.is_ok;
    ok = ok && rtxdi_params_get_u32(&p, RTXDI_F_TEMPORAL_MAX_HISTORY) == 42;
    ok = ok && near(rtxdi_params_get_f32(&p, RTXDI_F_TEMPORAL_DEPTH_THRESHOLD), (3 as Float32) / (20 as Float32), 0.0001 as Float32);
    // LE evidence at the oracle offset (24 for uniformRandomNumber).
    let off = rtxdi_params_field_offset(&p, RTXDI_F_TEMPORAL_UNIFORM_RANDOM);
    ok = ok && off == 24 && (p.data[off] as Int) == 0;
    msg = "image: temporal defaults (20/0.1/0.5) + roundtrip 42/0.15 through the owned image";
  }
  return assert(ok, msg);
}

fn test_a6_all_default_sizes() -> TestResult {
  var ok = true;
  let d0 = rtxdi_param_default(RTXDI_DEFAULT_BUFFER_INDICES);
  let d1 = rtxdi_param_default(RTXDI_DEFAULT_INITIAL);
  let d2 = rtxdi_param_default(RTXDI_DEFAULT_TEMPORAL);
  let d3 = rtxdi_param_default(RTXDI_DEFAULT_BOILING);
  let d4 = rtxdi_param_default(RTXDI_DEFAULT_SPATIAL);
  let d5 = rtxdi_param_default(RTXDI_DEFAULT_SPATIOTEMPORAL);
  let d6 = rtxdi_param_default(RTXDI_DEFAULT_SHADING);
  ok = d0.is_ok && d1.is_ok && d2.is_ok && d3.is_ok && d4.is_ok && d5.is_ok && d6.is_ok;
  if ok {
    ok = d0.value.size == RTXDI_SIZE_BUFFER_INDICES && d1.value.size == RTXDI_SIZE_INITIAL
      && d2.value.size == RTXDI_SIZE_TEMPORAL && d3.value.size == RTXDI_SIZE_BOILING
      && d4.value.size == RTXDI_SIZE_SPATIAL && d5.value.size == RTXDI_SIZE_SPATIOTEMPORAL
      && d6.value.size == RTXDI_SIZE_SHADING;
    ok = ok && rtxdi_params_get_u32(&d1.value, RTXDI_F_INITIAL_NUM_LOCAL) == 8
      && rtxdi_params_get_u32(&d1.value, RTXDI_F_INITIAL_NUM_INFINITE) == 1
      && near(rtxdi_params_get_f32(&d1.value, RTXDI_F_INITIAL_BRDF_CUTOFF), 0.0001 as Float32, 0.00001 as Float32);
    ok = ok && rtxdi_params_get_u32(&d3.value, RTXDI_F_BOILING_ENABLE) == 1
      && near(rtxdi_params_get_f32(&d3.value, RTXDI_F_BOILING_STRENGTH), 0.2 as Float32, 0.0001 as Float32);
    ok = ok && rtxdi_params_get_u32(&d4.value, RTXDI_F_SPATIAL_NUM_SAMPLES) == 1
      && rtxdi_params_get_u32(&d4.value, RTXDI_F_SPATIAL_NUM_DISOC_BOOST) == 8
      && near(rtxdi_params_get_f32(&d4.value, RTXDI_F_SPATIAL_SAMPLING_RADIUS), 32 as Float32, 0.0001 as Float32);
    ok = ok && near(rtxdi_params_get_f32(&d5.value, RTXDI_F_ST_SAMPLING_RADIUS), 32 as Float32, 0.0001 as Float32);
    ok = ok && rtxdi_params_get_u32(&d6.value, RTXDI_F_SHADING_FINAL_VISIBILITY_MAX_AGE) == 4
      && near(rtxdi_params_get_f32(&d6.value, RTXDI_F_SHADING_FINAL_VISIBILITY_MAX_DISTANCE), 16 as Float32, 0.0001 as Float32);
  }
  return assert(ok, "defaults: all seven GetDefault* images have the pinned sizes and spot values (8/1/1/1, boiling 0.2, spatial radius 32)");
}

fn test_a7_word_helpers() -> TestResult {
  var ok = rtxdi_sign_i32(4294967295) == -1;
  ok = ok && rtxdi_sign_i32(2147483648) == -2147483648;
  ok = ok && rtxdi_sign_i32(7) == 7;
  // Neighbor-offset byte-pair decode: bytes (254, 3) -> x=-2, y=3.
  var s: Vec[UInt8] = Vec[UInt8].new();
  s.push(254 as UInt8);
  s.push(3 as UInt8);
  let n = rtxdi_neighbor_offset(&s, 0);
  ok = ok && n.x == -2 && n.y == 3;
  return assert(ok, "words: signed-int32 and signed-byte neighbor-offset decode");
}

fn test_a8_is_static_image() -> TestResult {
  let img = rtxdi_is_static_image(320, 180, RTXDI_CHECKERBOARD_OFF, 8192, 128, 1024, 128, 1024,
    RTXDI_REGIR_ONION, 16, 16, 16, 512, 5, 10);
  var ok = false;
  var msg = "settings: IS static image build failed";
  if img.is_ok {
    let d = img.value;
    ok = d.len() == RTXDI_IS_IMAGE_SIZE;
    // LE evidence: width 320 = 0x140 at offset 0, regir mode 2 at offset 32.
    ok = ok && (d[0] as Int) == 64 && (d[1] as Int) == 1 && (d[2] as Int) == 0 && (d[3] as Int) == 0;
    ok = ok && (d[RTXDI_IS_IMAGE_REGIR_MODE] as Int) == RTXDI_REGIR_ONION;
    ok = ok && (d[RTXDI_IS_IMAGE_ONION_DETAIL] as Int) == 5 && (d[RTXDI_IS_IMAGE_ONION_COVERAGE] as Int) == 10;
    msg = "settings: 60B IS static image (320x180, onion 16^3/512, detail 5, coverage 10), LE evidence at oracle offsets";
  }
  return assert(ok, msg);
}

fn test_a9_execute_invalid() -> TestResult {
  let empty = RtxdiContext{ mod: 0; raw: 0 };
  let r = rtxdi_execute_di(&empty);
  return assert(r == RTXDI_EXEC_INVALID, "execute: empty context -> RTXDI_EXEC_INVALID (never silent success)");
}

// =========================================================================
// SECTION B -- shim present (SKIP-labelled when absent)
// =========================================================================

fn run_present(mod: &RtxdiModule) -> Int {
  var failed = 0;

  // B1: shim info / pinned constants.
  let info_r = rtxdi_info(mod);
  if info_r.is_err {
    failed = failed + report(false, "shim: info failed -- " + info_r.error.message);
  } else {
    let i = info_r.value;
    var info_ok = i.size_reservoir == RTXDI_SIZE_RESERVOIR && i.size_runtime == RTXDI_SIZE_RUNTIME
      && i.size_buffer_indices == RTXDI_SIZE_BUFFER_INDICES && i.size_initial == RTXDI_SIZE_INITIAL
      && i.size_temporal == RTXDI_SIZE_TEMPORAL && i.size_boiling == RTXDI_SIZE_BOILING
      && i.size_spatial == RTXDI_SIZE_SPATIAL && i.size_spatiotemporal == RTXDI_SIZE_SPATIOTEMPORAL
      && i.size_shading == RTXDI_SIZE_SHADING && i.size_parameters == RTXDI_SIZE_PARAMETERS
      && i.size_light_buffer == RTXDI_SIZE_LIGHT_BUFFER && i.size_packed_reservoir == RTXDI_SIZE_PACKED_RESERVOIR
      && i.size_ris_segment == RTXDI_SIZE_RIS_SEGMENT && i.size_di_static == RTXDI_SIZE_DI_STATIC;
    info_ok = info_ok && i.block_size == RTXDI_RESERVOIR_BLOCK_SIZE && i.tile_size == RTXDI_TILE_SIZE_IN_PIXELS
      && i.onion_max_groups == RTXDI_ONION_MAX_LAYER_GROUPS && i.onion_max_rings == RTXDI_ONION_MAX_RINGS
      && i.naive_threshold == RTXDI_NAIVE_SAMPLING_M_THRESHOLD
      && i.light_compact_bit == RTXDI_LIGHT_COMPACT_BIT && i.light_index_mask == RTXDI_LIGHT_INDEX_MASK
      && i.invalid_light_index == RTXDI_INVALID_LIGHT_INDEX
      && i.num_reservoir_buffers == RTXDI_NUM_RESERVOIR_BUFFERS && i.presampling == RTXDI_ENABLE_PRESAMPLING
      && i.size_onion_parameters == RTXDI_SIZE_ONION_PARAMETERS && i.size_regir_parameters == RTXDI_SIZE_REGIR_PARAMETERS;
    failed = failed + report(info_ok,
      "shim: struct sizes + constants (block 16, onion 8/52, light bit 0x80000000, 3 buffers) match the pinned headers");
  }

  // B2: layout drift -- bridge mirrors vs the SDK's real structs (20 kinds).
  var drift_ok = true;
  var kind = 0;
  while kind <= RTXDI_LAYOUT_PARAMETERS {
    let b = rtxdi_layout(kind);
    let s = rtxdi_sdk_layout(mod, kind);
    if b.is_err || s.is_err {
      drift_ok = false;
    } else {
      if b.value.count != s.value.count { drift_ok = false; }
      var i = 0;
      while i < b.value.count {
        if rtxdi_layout_field_offset(&b.value, i) != rtxdi_layout_field_offset(&s.value, i) { drift_ok = false; }
        if rtxdi_layout_field_size(&b.value, i) != rtxdi_layout_field_size(&s.value, i) { drift_ok = false; }
        i = i + 1;
      }
    }
    kind = kind + 1;
  }
  failed = failed + report(drift_ok, "drift: bridge ABI mirrors match the SDK struct layouts (20 tables, offsets+sizes)");

  // B3: defaults drift -- bridge defaults vs the SDK's GetDefault* images.
  var def_ok = true;
  var dk = 0;
  while dk <= RTXDI_DEFAULT_SHADING {
    let b = rtxdi_param_default(dk);
    let s = rtxdi_sdk_param_default(mod, dk);
    if b.is_err || s.is_err {
      def_ok = false;
    } else {
      if b.value.size != s.value.size { def_ok = false; }
      var i = 0;
      while i < b.value.size {
        if b.value.data[i] != s.value.data[i] { def_ok = false; }
        i = i + 1;
      }
    }
    dk = dk + 1;
  }
  failed = failed + report(def_ok, "drift: bridge-carried defaults are byte-identical to the SDK's seven GetDefault* images");

  // B4: reservoir buffer parameters for the small scene.
  let r_off = rtxdi_utils_reservoir_params(mod, 320, 180, RTXDI_CHECKERBOARD_OFF);
  let r_blk = rtxdi_utils_reservoir_params(mod, 320, 180, RTXDI_CHECKERBOARD_BLACK);
  var rb_ok = r_off.is_ok && r_blk.is_ok;
  if rb_ok {
    rb_ok = r_off.value.x == 5120 && r_off.value.y == 61440
      && r_blk.value.x == 2560 && r_blk.value.y == 30720;
    failed = failed + report(rb_ok,
      "plan: reservoir buffer pitches 320x180 row/array = " + i2s(r_off.value.x) + "/" + i2s(r_off.value.y)
        + ", checkerboard black " + i2s(r_blk.value.x) + "/" + i2s(r_blk.value.y));
  } else {
    failed = failed + report(false, "plan: reservoir param fetch failed");
  }

  // B5: PDF texture size.
  let pdf_big = rtxdi_utils_pdf_size(mod, 1000);
  let pdf_one = rtxdi_utils_pdf_size(mod, 1);
  var pdf_ok = pdf_big.is_ok && pdf_one.is_ok;
  if pdf_ok {
    pdf_ok = pdf_big.value.x == 32 && pdf_big.value.y == 32 && pdf_big.value.z == 6
      && pdf_one.value.x == 1 && pdf_one.value.y == 1 && pdf_one.value.z == 1;
    failed = failed + report(pdf_ok, "utils: PDF texture 1000 items -> 32x32 mips 6, 1 item -> 1x1 mips 1");
  } else {
    failed = failed + report(false, "utils: PDF size fetch failed");
  }

  // B6: JenkinsHash + neighbor offsets.
  let h0 = rtxdi_utils_jenkins_hash(mod, 0);
  let h1 = rtxdi_utils_jenkins_hash(mod, 1);
  let h7 = rtxdi_utils_jenkins_hash(mod, 7);
  let nb = rtxdi_utils_fill_neighbor_offsets(mod, 4);
  var h_ok = h0.is_ok && h1.is_ok && h7.is_ok && nb.is_ok;
  if h_ok {
    h_ok = h0.value == 1800329511 && h1.value == 3028713910 && h7.value == 4090419040;
    h_ok = h_ok && nb.value.len() == 8;
    h_ok = h_ok && (nb.value[0] as Int) == 195 && (nb.value[1] as Int) == 149
      && (nb.value[2] as Int) == 66 && (nb.value[3] as Int) == 184
      && (nb.value[4] as Int) == 4 && (nb.value[5] as Int) == 69
      && (nb.value[6] as Int) == 200 && (nb.value[7] as Int) == 219;
    let n0 = rtxdi_neighbor_offset(&nb.value, 0);
    let n1 = rtxdi_neighbor_offset(&nb.value, 1);
    h_ok = h_ok && n0.x == -61 && n0.y == -107 && n1.x == 66 && n1.y == -72;
    failed = failed + report(h_ok,
      "utils: JenkinsHash 0->1800329511 1->3028713910; neighbor offsets byte-exact, decode (-61,-107),(66,-72)");
  } else {
    failed = failed + report(false, "utils: hash/neighbor fetch failed");
  }

  // B7: standalone DI context + static parameters.
  var di_ok = false;
  let dcr = rtxdi_di_create(mod, 320, 180, RTXDI_CHECKERBOARD_OFF, 8192);
  if dcr.is_err {
    failed = failed + report(false, "di: context create failed -- " + dcr.error.message);
  } else {
    var di = dcr.value;
    // The pinned runtime leaves frameIndex indeterminate in the constructor:
    // the application owns the frame counter and calls SetFrameIndex each
    // frame (PROVENANCE "pinned-build observations").  Frame 0 first.
    let setf0 = rtxdi_di_set_frame_index(&di, 0);
    let st = rtxdi_di_params(&di, RTXDI_PART_DI_STATIC);
    let fill = rtxdi_di_params(&di, RTXDI_PART_INITIAL);
    if setf0.is_ok && st.is_ok && fill.is_ok {
      di_ok = rtxdi_params_get_u32(&st.value, RTXDI_F_DI_STATIC_NEIGHBOR_COUNT) == 8192
        && rtxdi_params_get_u32(&st.value, RTXDI_F_DI_STATIC_WIDTH) == 320
        && rtxdi_params_get_u32(&st.value, RTXDI_F_DI_STATIC_HEIGHT) == 180
        && rtxdi_params_get_u32(&st.value, RTXDI_F_DI_STATIC_CHECKERBOARD) == RTXDI_CHECKERBOARD_OFF;
      di_ok = di_ok && rtxdi_params_get_u32(&fill.value, RTXDI_F_INITIAL_NUM_LOCAL) == 8
        && rtxdi_params_get_u32(&fill.value, RTXDI_F_INITIAL_NUM_INFINITE) == 1
        && rtxdi_params_get_u32(&fill.value, RTXDI_F_INITIAL_ENABLE_VISIBILITY) == 1
        && rtxdi_params_get_u32(&fill.value, RTXDI_F_INITIAL_ENV_MAP_IMPORTANCE) == 1;
      failed = failed + report(di_ok, "di: context static params (320x180, neighbor 8192) + defaults (8 local / 1 infinite / visibility)");
    } else {
      failed = failed + report(false, "di: static parameter fetch failed");
    }

    // B8: frame plan at frame 0 (buffer index rotation).
    let par = rtxdi_di_params(&di, RTXDI_PART_BUFFER_INDICES);
    let rut = rtxdi_di_params(&di, RTXDI_PART_RUNTIME);
    if par.is_ok && rut.is_ok {
      // Frame 0 on the application-driven sequence create -> Set(0):
      // constructor leaves last=0/current=2, so frame 0 reads last=2.
      let plan_ok = rtxdi_params_get_u32(&par.value, RTXDI_F_INDICES_INITIAL_OUT) == 0
        && rtxdi_params_get_u32(&par.value, RTXDI_F_INDICES_TEMPORAL_IN) == 2
        && rtxdi_params_get_u32(&par.value, RTXDI_F_INDICES_TEMPORAL_OUT) == 0
        && rtxdi_params_get_u32(&par.value, RTXDI_F_INDICES_SPATIAL_IN) == 0
        && rtxdi_params_get_u32(&par.value, RTXDI_F_INDICES_SPATIAL_OUT) == 1
        && rtxdi_params_get_u32(&par.value, RTXDI_F_INDICES_SHADING_IN) == 1
        && rtxdi_params_get_u32(&rut.value, RTXDI_F_RUNTIME_FRAME_INDEX) == 0
        && rtxdi_params_get_u32(&rut.value, RTXDI_F_RUNTIME_NEIGHBOR_MASK) == 8191;
      failed = failed + report(plan_ok, "plan: frame 0 buffer indices (0,2->0,0->1,1) + runtime mask 8191, field 0");
    } else {
      failed = failed + report(false, "plan: frame 0 fetch failed");
    }

    // B9: frame 1 -> rotation + uniform random == JenkinsHash(1).
    let sf = rtxdi_di_set_frame_index(&di, 1);
    let par1 = rtxdi_di_params(&di, RTXDI_PART_BUFFER_INDICES);
    let rut1 = rtxdi_di_params(&di, RTXDI_PART_RUNTIME);
    let tmp1 = rtxdi_di_params(&di, RTXDI_PART_TEMPORAL);
    var f1_ok = sf.is_ok && par1.is_ok && rut1.is_ok && tmp1.is_ok;
    if f1_ok {
      f1_ok = rtxdi_params_get_u32(&par1.value, RTXDI_F_INDICES_INITIAL_OUT) == 2
        && rtxdi_params_get_u32(&par1.value, RTXDI_F_INDICES_TEMPORAL_IN) == 1
        && rtxdi_params_get_u32(&par1.value, RTXDI_F_INDICES_SPATIAL_OUT) == 0
        && rtxdi_params_get_u32(&par1.value, RTXDI_F_INDICES_SHADING_IN) == 0;
      f1_ok = f1_ok && rtxdi_params_get_u32(&rut1.value, RTXDI_F_RUNTIME_FRAME_INDEX) == 1;
      let urn = rtxdi_params_get_u32(&tmp1.value, RTXDI_F_TEMPORAL_UNIFORM_RANDOM);
      f1_ok = f1_ok && urn == 3028713910;
      failed = failed + report(f1_ok,
        "plan: frame 1 indices rotate (2,1->2,2->0,0) and uniformRandomNumber = JenkinsHash(1) = " + i2s(urn));
    } else {
      failed = failed + report(false, "plan: frame 1 fetch failed");
    }

    // B10: resampling mode + frame index getters.
    let sm0 = rtxdi_di_set_resampling_mode(&di, RTXDI_RESAMPLING_NONE);
    let gm0 = rtxdi_di_resampling_mode(&di);
    let sm1 = rtxdi_di_set_resampling_mode(&di, RTXDI_RESAMPLING_FUSED_SPATIOTEMPORAL);
    let gm1 = rtxdi_di_resampling_mode(&di);
    let gf = rtxdi_di_frame_index(&di);
    let mode_ok = sm0.is_ok && gm0.is_ok && gm0.value == RTXDI_RESAMPLING_NONE
      && sm1.is_ok && gm1.is_ok && gm1.value == RTXDI_RESAMPLING_FUSED_SPATIOTEMPORAL
      && gf.is_ok && gf.value == 1;
    failed = failed + report(mode_ok, "di: resampling mode none->0 fused->4, frame index getter 1");

    // B11: parameter roundtrip through the context.
    let tp = rtxdi_di_params(&di, RTXDI_PART_TEMPORAL);
    var rt_ok = false;
    if tp.is_ok {
      var t = tp.value;
      let s0 = rtxdi_params_set_u32(&mut t, RTXDI_F_TEMPORAL_MAX_HISTORY, 42);
      let s1 = rtxdi_params_set_f32(&mut t, RTXDI_F_TEMPORAL_DEPTH_THRESHOLD, (3 as Float32) / (20 as Float32));
      let push = rtxdi_di_set_params(&di, RTXDI_PART_TEMPORAL, &t);
      let back = rtxdi_di_params(&di, RTXDI_PART_TEMPORAL);
      rt_ok = s0.is_ok && s1.is_ok && push.is_ok && back.is_ok;
      if rt_ok {
        rt_ok = rtxdi_params_get_u32(&back.value, RTXDI_F_TEMPORAL_MAX_HISTORY) == 42
          && near(rtxdi_params_get_f32(&back.value, RTXDI_F_TEMPORAL_DEPTH_THRESHOLD), (3 as Float32) / (20 as Float32), 0.0001 as Float32);
      }
      failed = failed + report(rt_ok, "di: SetTemporalResamplingParameters roundtrip (42 / 0.15) through the SDK context");
    } else {
      failed = failed + report(false, "di: temporal fetch failed");
    }
    let dead = rtxdi_di_destroy(&di);
    failed = failed + report(dead.is_ok, "di: Destroy standalone context");
  }

  // B12: RIS buffer segment allocator.
  var ris_ok = false;
  let rcr = rtxdi_ris_create(mod);
  if rcr.is_err {
    failed = failed + report(false, "ris: allocator create failed -- " + rcr.error.message);
  } else {
    var ris = rcr.value;
    let a0 = rtxdi_ris_allocate(&ris, 1024 * 128);
    let a1 = rtxdi_ris_allocate(&ris, 1024 * 128);
    let tot = rtxdi_ris_total(&ris);
    ris_ok = a0.is_ok && a1.is_ok && tot.is_ok && a0.value == 0 && a1.value == 131072 && tot.value == 262144;
    failed = failed + report(ris_ok, "ris: segments local@0 env@131072 total=262144 elements");

    // B13: ReGIR grid mode.
    let rgr = rtxdi_regir_create(mod, &ris, RTXDI_REGIR_GRID, 4, 6, 8, 16, 5, 10);
    if rgr.is_ok {
      var rg = rgr.value;
      let slots = rtxdi_regir_light_slots(&rg);
      let off = rtxdi_regir_cell_offset(&rg);
      var grid_ok = slots.is_ok && off.is_ok && slots.value == 3072 && off.value == 262144;
      let d = rtxdi_regir_destroy(&rg);
      grid_ok = grid_ok && d.is_ok;
      failed = failed + report(grid_ok, "regir: grid 4x6x8x16 slots=3072 at element offset 262144");
    } else {
      failed = failed + report(false, "regir: grid create failed");
    }

    // B14: ReGIR onion mode -- calculated layers/rings.
    let ror = rtxdi_regir_create(mod, &ris, RTXDI_REGIR_ONION, 16, 16, 16, 512, 5, 10);
    if ror.is_ok {
      var ro = ror.value;
      let on = rtxdi_regir_onion_params(&ro);
      let slots2 = rtxdi_regir_light_slots(&ro);
      var onion_ok = on.is_ok && slots2.is_ok;
      if onion_ok {
        onion_ok = on.value.num_layers == 5 && on.value.num_rings == 25
          && on.value.cells == 2229 && on.value.light_slot_count == 1141248
          && slots2.value == 1141248;
        onion_ok = onion_ok && near(on.value.cubic_root_factor, 1.7768 as Float32, 0.001 as Float32)
          && near(on.value.linear_factor, 0.3854 as Float32, 0.001 as Float32);
        onion_ok = onion_ok && near(rtxdi_onion_layer_f32(&on.value, 0, RTXDI_F_ONION_LAYER_INNER_RADIUS), 1 as Float32, 0.0001 as Float32)
          && near(rtxdi_onion_layer_f32(&on.value, 0, RTXDI_F_ONION_LAYER_OUTER_RADIUS), 2.2933 as Float32, 0.001 as Float32)
          && rtxdi_onion_ring_i32(&on.value, 0, RTXDI_F_ONION_RING_CELL_COUNT) == 8
          && rtxdi_onion_ring_i32(&on.value, 1, RTXDI_F_ONION_RING_CELL_COUNT) == 5
          && rtxdi_onion_ring_i32(&on.value, 2, RTXDI_F_ONION_RING_CELL_COUNT) == 1;
        failed = failed + report(onion_ok,
          "regir: onion 5 layers / 25 rings / 2229 cells / 1141248 slots, cubicRoot "
            + f2s(on.value.cubic_root_factor) + ", ring counts 8/5/1");
      } else {
        failed = failed + report(false, "regir: onion parameter fetch failed");
      }

      // B15: ReGIR dynamic parameters.
      let dy0 = rtxdi_regir_dynamic(&ro);
      let setd = rtxdi_regir_set_dynamic(&ro, (1 as Float32) / (2 as Float32), 1 as Float32, 2 as Float32, 3 as Float32,
        RTXDI_REGIR_PRESAMPLING_POWER_RIS, RTXDI_REGIR_PRESAMPLING_POWER_RIS, 1 as Float32, 64);
      let dy1 = rtxdi_regir_dynamic(&ro);
      let pw = rtxdi_regir_power_ris(&ro);
      var dyn_ok = dy0.is_ok && setd.is_ok && dy1.is_ok && pw.is_ok;
      if dyn_ok {
        dyn_ok = near(dy1.value.cell_size, (1 as Float32) / (2 as Float32), 0.0001 as Float32)
          && near(dy1.value.center_x, 1 as Float32, 0.0001 as Float32)
          && dy1.value.presampling_mode == RTXDI_REGIR_PRESAMPLING_POWER_RIS
          && dy1.value.num_build_samples == 64 && pw.value;
        failed = failed + report(dyn_ok, "regir: dynamic params roundtrip (cell 0.5, center (1,2,3), build samples 64) + power-RIS query");
      } else {
        failed = failed + report(false, "regir: dynamic parameter fetch failed");
      }
      let dd = rtxdi_regir_destroy(&ro);
      failed = failed + report(dd.is_ok, "regir: Destroy onion context");
    } else {
      failed = failed + report(false, "regir: onion create failed");
      failed = failed + report(false, "regir: dynamic params unavailable");
      failed = failed + report(false, "regir: onion destroy unavailable");
    }
    let rd = rtxdi_ris_destroy(&ris);
    failed = failed + report(rd.is_ok, "ris: Destroy allocator");
  }

  // B16: ImportanceSamplingContext -- setup.
  let imgr = rtxdi_is_static_image(320, 180, RTXDI_CHECKERBOARD_OFF, 8192, 128, 1024, 128, 1024,
    RTXDI_REGIR_ONION, 16, 16, 16, 512, 5, 10);
  var is_ok = false;
  if imgr.is_err {
    failed = failed + report(false, "is: static image build failed");
  } else {
    let icr = rtxdi_is_create(mod, &imgr.value);
    if icr.is_err {
      failed = failed + report(false, "is: context create failed -- " + icr.error.message);
    } else {
      var isctx = icr.value;
      let lris = rtxdi_is_local_ris(&isctx);
      let eris = rtxdi_is_env_ris(&isctx);
      let tot = rtxdi_is_ris_total(&isctx);
      let n = rtxdi_is_neighbor_count(&isctx);
      let power = rtxdi_is_power_ris(&isctx);
      let regir = rtxdi_is_regir_enabled(&isctx);
      var setup_ok = lris.is_ok && eris.is_ok && tot.is_ok && n.is_ok && power.is_ok && regir.is_ok;
      if setup_ok {
        setup_ok = rtxdi_params_get_u32(&lris.value, RTXDI_F_RIS_SEGMENT_OFFSET) == 0
          && rtxdi_params_get_u32(&lris.value, RTXDI_F_RIS_SEGMENT_TILE_SIZE) == 128
          && rtxdi_params_get_u32(&lris.value, RTXDI_F_RIS_SEGMENT_TILE_COUNT) == 1024
          && rtxdi_params_get_u32(&eris.value, RTXDI_F_RIS_SEGMENT_OFFSET) == 131072
          && tot.value == 1403392 && n.value == 8192 && !power.value && !regir.value;
        failed = failed + report(setup_ok,
          "is: RIS segments local@0 env@131072 total=1403392, neighbor 8192, power-RIS off, ReGIR flag off");
      } else {
        failed = failed + report(false, "is: setup query failed");
      }

      // B17: light buffer parameters set/get.
      let lb0 = rtxdi_is_light_buffer(&isctx);
      var lb_ok = lb0.is_ok;
      if lb_ok {
        lb_ok = rtxdi_params_get_u32(&lb0.value, RTXDI_F_LIGHT_BUFFER_LOCAL) == 0
          && rtxdi_params_get_u32_at(&lb0.value, RTXDI_F_LIGHT_BUFFER_LOCAL, 4) == 0;
      }
      let lbnew = rtxdi_params_zero(RTXDI_LAYOUT_LIGHT_BUFFER);
      if lbnew.is_ok && lb_ok {
        var lb = lbnew.value;
        let s0 = rtxdi_params_set_u32_at(&mut lb, RTXDI_F_LIGHT_BUFFER_LOCAL, 0, 0);
        let s1 = rtxdi_params_set_u32_at(&mut lb, RTXDI_F_LIGHT_BUFFER_LOCAL, 4, 100);
        let s2 = rtxdi_params_set_u32_at(&mut lb, RTXDI_F_LIGHT_BUFFER_INFINITE, 0, 1000);
        let s3 = rtxdi_params_set_u32_at(&mut lb, RTXDI_F_LIGHT_BUFFER_INFINITE, 4, 10);
        let s4 = rtxdi_params_set_u32_at(&mut lb, RTXDI_F_LIGHT_BUFFER_ENV, 0, 1);
        let s5 = rtxdi_params_set_u32_at(&mut lb, RTXDI_F_LIGHT_BUFFER_ENV, 4, 2000);
        let push = rtxdi_is_set_light_buffer(&isctx, &lb);
        let back = rtxdi_is_light_buffer(&isctx);
        lb_ok = s0.is_ok && s1.is_ok && s2.is_ok && s3.is_ok && s4.is_ok && s5.is_ok && push.is_ok && back.is_ok;
        if lb_ok {
          lb_ok = rtxdi_params_get_u32_at(&back.value, RTXDI_F_LIGHT_BUFFER_LOCAL, 4) == 100
            && rtxdi_params_get_u32_at(&back.value, RTXDI_F_LIGHT_BUFFER_INFINITE, 0) == 1000
            && rtxdi_params_get_u32_at(&back.value, RTXDI_F_LIGHT_BUFFER_INFINITE, 4) == 10
            && rtxdi_params_get_u32_at(&back.value, RTXDI_F_LIGHT_BUFFER_ENV, 0) == 1
            && rtxdi_params_get_u32_at(&back.value, RTXDI_F_LIGHT_BUFFER_ENV, 4) == 2000;
        }
        failed = failed + report(lb_ok,
          "is: light buffer set/get roundtrip (local 100 @0, infinite 10 @1000, environment idx 2000)");
      } else {
        failed = failed + report(false, "is: light buffer image unavailable");
      }

      // B18: child DI handle -> frame plan; typed execute classification.
      let child = rtxdi_is_di(&isctx);
      var child_ok = false;
      var exec_ok = false;
      if child.is_ok {
        let plan = rtxdi_frame_plan(&child.value);
        if plan.is_ok {
          let sf3 = rtxdi_di_set_frame_index(&child.value, 3);
          let plan3 = rtxdi_frame_plan(&child.value);
          child_ok = sf3.is_ok && plan3.is_ok;
          if child_ok {
            child_ok = rtxdi_params_get_u32(&plan.value.indices, RTXDI_F_INDICES_INITIAL_OUT) == 1
              && rtxdi_params_get_u32(&plan3.value.indices, RTXDI_F_INDICES_INITIAL_OUT) == 0
              && rtxdi_params_get_u32(&plan3.value.indices, RTXDI_F_INDICES_TEMPORAL_IN) == 2
              && rtxdi_params_get_u32(&plan3.value.runtime, RTXDI_F_RUNTIME_FRAME_INDEX) == 3;
          }
        }
        exec_ok = rtxdi_execute_di(&child.value) == RTXDI_EXEC_NO_DEVICE;
      }
      failed = failed + report(child_ok && exec_ok,
        "is: child DI frame plan rotates at frame 3; execute -> RTXDI_EXEC_NO_DEVICE (typed SKIP)");

      let d = rtxdi_is_destroy(&isctx);
      failed = failed + report(d.is_ok, "is: Destroy top-level context");
    }
  }

  // B19: close + post-close guard.
  let closed = rtxdi_close(mod);
  var close_ok = closed.is_ok;
  if close_ok {
    let after = rtxdi_info(mod);
    close_ok = after.is_err && after.error.kind == RTXDI_ERR_NOT_LOADED;
  }
  failed = failed + report(close_ok, "loader: close unloads the shim and post-close calls are typed NOT_LOADED");

  return failed;
}

fn run_absent_skips() -> Int {
  var failed = 0;
  failed = failed + skip("shim: info");
  failed = failed + skip("drift: ABI mirrors vs SDK structs");
  failed = failed + skip("drift: defaults");
  failed = failed + skip("plan: reservoir buffer parameters");
  failed = failed + skip("utils: PDF texture size");
  failed = failed + skip("utils: hash + neighbor offsets");
  failed = failed + skip("di: context + static parameters");
  failed = failed + skip("plan: frame 0 buffer indices");
  failed = failed + skip("plan: frame 1 rotation + uniform random");
  failed = failed + skip("di: resampling mode + frame index");
  failed = failed + skip("di: temporal roundtrip");
  failed = failed + skip("di: Destroy standalone context");
  failed = failed + skip("ris: allocator segments");
  failed = failed + skip("regir: grid mode");
  failed = failed + skip("regir: onion calculated parameters");
  failed = failed + skip("regir: dynamic parameters + power-RIS");
  failed = failed + skip("regir: Destroy onion context");
  failed = failed + skip("ris: Destroy allocator");
  failed = failed + skip("is: context setup");
  failed = failed + skip("is: light buffer set/get");
  failed = failed + skip("is: child frame plan + execute classification");
  failed = failed + skip("is: Destroy top-level context");
  failed = failed + skip("loader: close + post-close guard");
  return failed;
}

// =========================================================================
// Main
// =========================================================================

pub fn main() -> Int {
  io.println("=== xiom.rtxdi conformance suite (0.1.0, upstream pin v3.1.0 + library f12037fa, reference-only) ===");
  io.flush_stdout();
  var failed: Int = 0;

  io.println("");
  io.println("-- SECTION A: classification + owned-struct plumbing (9) --");
  let a1 = test_a1_skip_path_classification(); failed = failed + report(a1.passed, a1.name);
  let a2 = test_a2_di_layouts();               failed = failed + report(a2.passed, a2.name);
  let a3 = test_a3_buffer_regir_layouts();     failed = failed + report(a3.passed, a3.name);
  let a4 = test_a4_constant_table();           failed = failed + report(a4.passed, a4.name);
  let a5 = test_a5_defaults_roundtrip();       failed = failed + report(a5.passed, a5.name);
  let a6 = test_a6_all_default_sizes();        failed = failed + report(a6.passed, a6.name);
  let a7 = test_a7_word_helpers();             failed = failed + report(a7.passed, a7.name);
  let a8 = test_a8_is_static_image();          failed = failed + report(a8.passed, a8.name);
  let a9 = test_a9_execute_invalid();          failed = failed + report(a9.passed, a9.name);

  io.println("");
  io.println("-- SECTION B: shim surface (23; SKIP without xiom_rtxdi_shim.dll) --");
  let load = rtxdi_load();
  if load.is_ok {
    let mod: RtxdiModule = load.value;
    failed = failed + report(true, "load: RTXDI shim module resolved");
    failed = failed + run_present(&mod);
  } else {
    if load.error.kind == RTXDI_LOAD_ABSENT {
      failed = failed + report(true, "load: SKIP -- " + load.error.message);
    } else {
      failed = failed + report(false, "load: ABI failure -- " + load.error.message);
    }
    failed = failed + run_absent_skips();
  }

  io.println("");
  if failed == 0 {
    io.println("  ALL 33 CHECKS PASSED (SKIP-labelled checks are classified platform states)");
    return 0;
  }
  io.println("  FAILED: " + i2s(failed));
  return 1;
}

