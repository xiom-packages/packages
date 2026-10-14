// XIOM -- xiom.rtxgi conformance suite (0.1.0).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// 27 checks, identical count on every host:
//   SECTION A (8): always-run -- SKIP-path classification, ABI mirror
//     layout tables (desc/gpu/packed/resource-indices/root-constants against
//     the pinned header anchors), constant tables (version, enums, status
//     codes, descriptor counts), owned-image defaults + encode/decode
//     plumbing (settings into owned structs), desc_for_volume derivation,
//     packed-word decode, signed-word helpers.
//   SECTION B (19): runtime-dependent -- shim info, descriptor counts,
//     shader-bytecode validation, perf-marker global, layout drift check
//     (bridge mirrors vs the SDK's real structs), defaults drift check,
//     probe counts + texture dimensions for a small scene, volume lifecycle
//     (create/update/destroy), RNG determinism, packed constants, scrolling,
//     AABB/OBB, probe world positions, euler rotation, and the typed
//     GPU-execution classification (RTXGI_EXEC_NO_DEVICE -> SKIP).
//     Without the shim module (default PATH), each B check reports "SKIP"
//     and stays green (classified platform state, not a gap).
//
// Runtime: xiom_rtxgi_shim.dll built locally from the pinned clone
// (RTXGI-DDGI v1.3.7) by the licensee -- `XIOM_RTXGI_SHIM` env var or the
// default module search.  Run: scripts/port.ps1 -Package xiom.rtxgi -TimeoutSec 240

module rtxgi_conformance

use xiom.io;
use xiom.test;
use xiom.rtxgi;

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
  return report(true, name + " -- SKIP (no RTXGI shim module present)");
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

fn empty_desc() -> RtxgiDesc {
  return RtxgiDesc{
    size: 0;
    count: 0;
    data: Vec[UInt8].new();
    offsets: Vec[UInt8].new();
    sizes: Vec[UInt8].new();
  };
}

fn empty_volume() -> RtxgiVolume {
  return RtxgiVolume{ mod: 0; raw: 0 };
}

fn build_scene_desc() -> RtxgiDesc {
  let d = rtxgi_desc_for_volume(3, 2, 4, 256, 8, 16);
  if d.is_err { return empty_desc(); }
  var img = d.value;
  let r0 = rtxgi_desc_set_f32_at(&mut img, RTXGI_DESC_ORIGIN, 0, 1 as Float32);
  let r1 = rtxgi_desc_set_f32_at(&mut img, RTXGI_DESC_ORIGIN, 1, 2 as Float32);
  let r2 = rtxgi_desc_set_f32_at(&mut img, RTXGI_DESC_ORIGIN, 2, 3 as Float32);
  let r3 = rtxgi_desc_set_f32_at(&mut img, RTXGI_DESC_PROBE_SPACING, 0, 1 as Float32);
  let r4 = rtxgi_desc_set_f32_at(&mut img, RTXGI_DESC_PROBE_SPACING, 1, 1 as Float32);
  let r5 = rtxgi_desc_set_f32_at(&mut img, RTXGI_DESC_PROBE_SPACING, 2, 1 as Float32);
  if r0.is_err || r1.is_err || r2.is_err || r3.is_err || r4.is_err || r5.is_err {
    return empty_desc();
  }
  return img;
}

// =========================================================================
// SECTION A -- always-run (no shim needed)
// =========================================================================

fn test_a1_skip_path_classification() -> TestResult {
  let r = rtxgi_load_named("xiom-absent-rtxgi-probe-xyz.dll");
  var ok = false;
  if r.is_err {
    ok = r.error.kind == RTXGI_LOAD_ABSENT;
  }
  return assert(ok, "skip-path: absent module classified as RTXGI_LOAD_ABSENT");
}

fn test_a2_desc_layout() -> TestResult {
  let l = rtxgi_layout(RTXGI_LAYOUT_DESC);
  var ok = false;
  var msg = "layout: desc table fetch failed";
  if l.is_ok {
    let t = l.value;
    ok = t.count == RTXGI_DESC_FIELD_COUNT
      && rtxgi_mirror_size(RTXGI_LAYOUT_DESC) == RTXGI_DESC_SIZE;
    ok = ok && rtxgi_layout_field_offset(&t, RTXGI_DESC_NAME) == 0;
    ok = ok && rtxgi_layout_field_size(&t, RTXGI_DESC_NAME) == 8;
    ok = ok && rtxgi_layout_field_offset(&t, RTXGI_DESC_ORIGIN) == 20
      && rtxgi_layout_field_size(&t, RTXGI_DESC_ORIGIN) == 12;
    ok = ok && rtxgi_layout_field_offset(&t, RTXGI_DESC_PROBE_COUNTS) == 56;
    ok = ok && rtxgi_layout_field_offset(&t, RTXGI_DESC_PROBE_HYSTERESIS) == 88;
    ok = ok && rtxgi_layout_field_offset(&t, RTXGI_DESC_PROBE_RAY_DATA_FORMAT) == 128;
    ok = ok && rtxgi_layout_field_offset(&t, RTXGI_DESC_MOVEMENT_TYPE) == 160;
    ok = ok && rtxgi_layout_field_offset(&t, RTXGI_DESC_PROBE_VIS_TYPE) == 164;
    msg = "layout: desc mirror " + i2s(rtxgi_mirror_size(RTXGI_LAYOUT_DESC)) + "B/" + i2s(t.count)
      + " fields, anchors origin@20 counts@56 hysteresis@88 formats@128 movement@160 (expected 168/38)";
  }
  return assert(ok, msg);
}

fn test_a3_gpu_layouts() -> TestResult {
  let g = rtxgi_layout(RTXGI_LAYOUT_GPU_DESC);
  let p = rtxgi_layout(RTXGI_LAYOUT_PACKED);
  let r = rtxgi_layout(RTXGI_LAYOUT_RESOURCE_INDICES);
  let k = rtxgi_layout(RTXGI_LAYOUT_ROOT_CONSTANTS);
  var ok = g.is_ok && p.is_ok && r.is_ok && k.is_ok;
  var msg = "layout: gpu/packed/resource/root tables fetch failed";
  if ok {
    let gt = g.value;
    let pt = p.value;
    ok = ok && gt.count == RTXGI_GPU_FIELD_COUNT
      && rtxgi_layout_field_offset(&gt, RTXGI_GPU_ROTATION) == 12
      && rtxgi_layout_field_size(&gt, RTXGI_GPU_ROTATION) == 16
      && rtxgi_layout_field_offset(&gt, RTXGI_GPU_PROBE_SCROLL_OFFSETS) == 128
      && rtxgi_layout_field_size(&gt, RTXGI_GPU_PROBE_SCROLL_OFFSETS) == 12;
    ok = ok && pt.count == RTXGI_PACKED_FIELD_COUNT
      && rtxgi_layout_field_offset(&pt, RTXGI_PACKED_WORD0) == 92
      && rtxgi_layout_field_size(&pt, RTXGI_PACKED_RESERVED) == 16;
    ok = ok && rtxgi_mirror_size(RTXGI_LAYOUT_GPU_DESC) == RTXGI_GPU_DESC_SIZE;
    ok = ok && rtxgi_mirror_size(RTXGI_LAYOUT_PACKED) == RTXGI_PACKED_SIZE;
    ok = ok && rtxgi_mirror_size(RTXGI_LAYOUT_RESOURCE_INDICES) == RTXGI_RESOURCE_INDICES_SIZE
      && r.is_ok && r.value.count == 12;
    ok = ok && rtxgi_mirror_size(RTXGI_LAYOUT_ROOT_CONSTANTS) == RTXGI_ROOT_CONSTANTS_SIZE
      && k.is_ok && k.value.count == RTXGI_ROOT_CONSTANTS_NUM_WORDS
      && rtxgi_layout_field_offset(&k.value, 3) == 12;
    msg = "layout: gpu " + i2s(rtxgi_mirror_size(RTXGI_LAYOUT_GPU_DESC)) + "B packed "
      + i2s(rtxgi_mirror_size(RTXGI_LAYOUT_PACKED)) + "B resource-indices "
      + i2s(rtxgi_mirror_size(RTXGI_LAYOUT_RESOURCE_INDICES)) + "B root-constants "
      + i2s(rtxgi_mirror_size(RTXGI_LAYOUT_ROOT_CONSTANTS)) + "B (expected 160/128/48/24)";
  }
  return assert(ok, msg);
}

fn test_a4_constant_tables() -> TestResult {
  var ok = RTXGI_VERSION_MAJOR == 1 && RTXGI_VERSION_MINOR == 3 && RTXGI_VERSION_REVISION == 7;
  ok = ok && RTXGI_TEXTURE_TYPE_COUNT == 6 && RTXGI_TEXTURE_FORMAT_COUNT == 7;
  ok = ok && RTXGI_MOVEMENT_COUNT == 2 && RTXGI_PROBE_VIS_COUNT == 2;
  ok = ok && RTXGI_STATUS_OK == 0 && RTXGI_STATUS_COUNT == 86;
  ok = ok && RTXGI_STATUS_ERROR_DDGI_INVALID_PROBE_COUNTS == 1;
  ok = ok && RTXGI_STATUS_ERROR_DDGI_INVALID_RESOURCES_DESC == 6;
  ok = ok && RTXGI_STATUS_ERROR_DDGI_INVALID_BYTECODE_PROBE_BLENDING_IRRADIANCE == 13;
  ok = ok && RTXGI_STATUS_ERROR_DDGI_VK_INVALID_PIPELINE_PROBE_VARIABILITY_EXTRA_REDUCTION == 85;
  ok = ok && RTXGI_COORDINATE_SYSTEM_RIGHT_Y_UP == 2;
  ok = ok && RTXGI_NUM_RTV_DESCRIPTORS == 2 && RTXGI_NUM_TEX2DARRAY_DESCRIPTORS == 6
    && RTXGI_NUM_RESOURCE_DESCRIPTORS == 12;
  ok = ok && RTXGI_ROOT_CONSTANTS_SIZE == 24 && RTXGI_ROOT_CONSTANTS_ALIGNED_SIZE == 32
    && RTXGI_ROOT_CONSTANTS_ALIGNED_WORDS == 8;
  ok = ok && RTXGI_PACKED0_COUNT_MASK == 1023 && RTXGI_PACKED0_COUNT_Y_SHIFT == 10
    && RTXGI_PACKED0_COUNT_Z_SHIFT == 20 && RTXGI_PACKED_THRESHOLD_SCALE == 65535
    && RTXGI_PACKED_SCROLL_MASK == 32767;
  return assert(ok, "constants: version, enums, status codes, descriptor counts and packed bits match the pinned headers");
}

fn test_a5_desc_defaults_roundtrip() -> TestResult {
  let d = rtxgi_desc_default();
  var ok = false;
  var msg = "image: desc default build failed";
  if d.is_ok {
    var img = d.value;
    ok = img.size == RTXGI_DESC_SIZE && img.count == RTXGI_DESC_FIELD_COUNT;
    ok = ok && rtxgi_desc_get_i32_at(&img, RTXGI_DESC_PROBE_COUNTS, 0) == -1;
    ok = ok && rtxgi_desc_get_i32(&img, RTXGI_DESC_PROBE_NUM_RAYS) == 256;
    ok = ok && near(rtxgi_desc_get_f32(&img, RTXGI_DESC_PROBE_HYSTERESIS), 0.97 as Float32, 0.0001 as Float32);
    ok = ok && rtxgi_desc_get_f32(&img, RTXGI_DESC_PROBE_MAX_RAY_DISTANCE) > (1e26 as Float32);
    ok = ok && rtxgi_desc_get_i32(&img, RTXGI_DESC_MOVEMENT_TYPE) == 0;
    ok = ok && rtxgi_desc_get_i32(&img, RTXGI_DESC_PROBE_RAY_DATA_FORMAT) == 0;
    ok = ok && near(rtxgi_desc_get_f32(&img, RTXGI_DESC_PROBE_MIN_FRONTFACE_DISTANCE), 1 as Float32, 0.0001 as Float32);
    let s0 = rtxgi_desc_set_f32_at(&mut img, RTXGI_DESC_ORIGIN, 0, (3 as Float32) / (2 as Float32));
    let s1 = rtxgi_desc_set_f32(&mut img, RTXGI_DESC_PROBE_HYSTERESIS, (9 as Float32) / (10 as Float32));
    let s2 = rtxgi_desc_set_i32(&mut img, RTXGI_DESC_PROBE_RAY_DATA_FORMAT, RTXGI_TEXTURE_FORMAT_F32X2);
    ok = ok && s0.is_ok && s1.is_ok && s2.is_ok;
    ok = ok && near(rtxgi_desc_get_f32_at(&img, RTXGI_DESC_ORIGIN, 0), (3 as Float32) / (2 as Float32), 0.0001 as Float32);
    ok = ok && near(rtxgi_desc_get_f32(&img, RTXGI_DESC_PROBE_HYSTERESIS), (9 as Float32) / (10 as Float32), 0.0001 as Float32);
    ok = ok && rtxgi_desc_get_i32(&img, RTXGI_DESC_PROBE_RAY_DATA_FORMAT) == RTXGI_TEXTURE_FORMAT_F32X2;
    // Raw LE evidence at the probeCounts offset (56): -1 = 0xFFFFFFFF.
    let off = rtxgi_desc_field_offset(&img, RTXGI_DESC_PROBE_COUNTS);
    ok = ok && (img.data[off + 0] as Int) == 255 && (img.data[off + 1] as Int) == 255
      && (img.data[off + 2] as Int) == 255 && (img.data[off + 3] as Int) == 255;
    msg = "image: desc defaults + encode/decode roundtrip (counts -1, rays 256, hysteresis 0.97)";
  }
  return assert(ok, msg);
}

fn test_a6_desc_for_volume() -> TestResult {
  let img = build_scene_desc();
  var ok = img.size == RTXGI_DESC_SIZE;
  var msg = "settings: desc_for_volume build failed";
  if ok {
    ok = rtxgi_desc_get_i32_at(&img, RTXGI_DESC_PROBE_COUNTS, 0) == 3;
    ok = ok && rtxgi_desc_get_i32_at(&img, RTXGI_DESC_PROBE_COUNTS, 1) == 2;
    ok = ok && rtxgi_desc_get_i32_at(&img, RTXGI_DESC_PROBE_COUNTS, 2) == 4;
    ok = ok && rtxgi_desc_get_i32(&img, RTXGI_DESC_PROBE_NUM_RAYS) == 256;
    ok = ok && rtxgi_desc_get_i32(&img, RTXGI_DESC_PROBE_NUM_IRRADIANCE_INTERIOR_TEXELS) == 8;
    ok = ok && rtxgi_desc_get_i32(&img, RTXGI_DESC_PROBE_NUM_IRRADIANCE_TEXELS) == 10;
    ok = ok && rtxgi_desc_get_i32(&img, RTXGI_DESC_PROBE_NUM_DISTANCE_INTERIOR_TEXELS) == 16;
    ok = ok && rtxgi_desc_get_i32(&img, RTXGI_DESC_PROBE_NUM_DISTANCE_TEXELS) == 18;
    // Raw LE evidence at the irradiance-texels offset.
    let off = rtxgi_desc_field_offset(&img, RTXGI_DESC_PROBE_NUM_IRRADIANCE_TEXELS);
    ok = ok && (img.data[off + 0] as Int) == 10 && (img.data[off + 1] as Int) == 0;
    msg = "settings: 3x2x4 probes, 256 rays, interior 8/16 -> texels 10/18, LE evidence at oracle offsets";
  }
  return assert(ok, msg);
}

fn test_a7_packed_decode() -> TestResult {
  let word0 = 3 | (2 << 10) | (4 << 20);
  let c = rtxgi_packed_counts_from_word(word0);
  var ok = c.x == 3 && c.y == 2 && c.z == 4;
  let c2 = rtxgi_packed_counts_from_word(1023 | (1023 << 10) | (1023 << 20));
  ok = ok && c2.x == 1023 && c2.y == 1023 && c2.z == 1023;
  return assert(ok, "packed: packed0 word decodes counts (3,2,4) and (1023,1023,1023)");
}

fn test_a8_signed_words() -> TestResult {
  var ok = rtxgi_sign_i32(4294967295) == -1;
  ok = ok && rtxgi_sign_i32(2147483648) == -2147483648;
  ok = ok && rtxgi_sign_i32(2147483647) == 2147483647;
  ok = ok && rtxgi_sign_i32(3) == 3;
  return assert(ok, "words: signed-int32 interpretation of unsigned slot words");
}

// =========================================================================
// SECTION B -- shim present (SKIP-labelled when absent)
// =========================================================================

fn run_present(mod: &RtxgiModule) -> Int {
  var failed = 0;

  // B1: shim info / pin identity.
  let info_r = rtxgi_info(mod);
  var info_ok = false;
  if info_r.is_ok {
    let info = info_r.value;
    info_ok = info.coordinate_system == RTXGI_COORDINATE_SYSTEM_RIGHT_Y_UP
      && info.resource_management == 0
      && info.version_major == RTXGI_VERSION_MAJOR
      && info.version_minor == RTXGI_VERSION_MINOR
      && info.version_revision == RTXGI_VERSION_REVISION
      && info.size_desc == RTXGI_DESC_SIZE
      && info.size_gpu_desc == RTXGI_GPU_DESC_SIZE
      && info.size_packed == RTXGI_PACKED_SIZE;
    failed = failed + report(info_ok,
      "shim: right-handed y-up, unmanaged, v" + i2s(info.version_major) + "." + i2s(info.version_minor)
        + "." + i2s(info.version_revision) + ", sizes " + i2s(info.size_desc) + "/"
        + i2s(info.size_gpu_desc) + "/" + i2s(info.size_packed));
  } else {
    failed = failed + report(false, "shim: info failed -- " + info_r.error.message);
  }

  // B2: descriptor counts.
  let dc = rtxgi_descriptor_counts(mod);
  var dc_ok = false;
  if dc.is_ok {
    dc_ok = dc.value.rtv == RTXGI_NUM_RTV_DESCRIPTORS
      && dc.value.tex2darray == RTXGI_NUM_TEX2DARRAY_DESCRIPTORS
      && dc.value.resource == RTXGI_NUM_RESOURCE_DESCRIPTORS;
    failed = failed + report(dc_ok, "descriptors: RTV=" + i2s(dc.value.rtv) + " Tex2DArray="
      + i2s(dc.value.tex2darray) + " Resource=" + i2s(dc.value.resource));
  } else {
    failed = failed + report(false, "descriptors: fetch failed -- " + dc.error.message);
  }

  // B3: shader bytecode validation.
  let vb_empty = rtxgi_validate_shader_bytecode(mod, 0);
  let vb_size = rtxgi_validate_shader_bytecode(mod, 8);
  var vb_ok = vb_empty.is_ok && vb_size.is_ok && !vb_empty.value && vb_size.value;
  failed = failed + report(vb_ok, "bytecode: empty blob invalid, non-empty blob valid");

  // B4: perf-marker global.
  let pm0 = rtxgi_get_insert_perf_markers(mod);
  var pm_ok = pm0.is_ok && pm0.value;
  let pm_set0 = rtxgi_set_insert_perf_markers(mod, false);
  let pm1 = rtxgi_get_insert_perf_markers(mod);
  pm_ok = pm_ok && pm_set0.is_ok && pm1.is_ok && !pm1.value;
  let pm_set1 = rtxgi_set_insert_perf_markers(mod, true);
  let pm2 = rtxgi_get_insert_perf_markers(mod);
  pm_ok = pm_ok && pm_set1.is_ok && pm2.is_ok && pm2.value;
  failed = failed + report(pm_ok, "perf-markers: default true, set false/true roundtrip through the SDK global");

  // B5: layout drift -- bridge mirrors vs the SDK's real structs.
  var drift_ok = true;
  var kind = 0;
  while kind <= RTXGI_LAYOUT_ROOT_CONSTANTS {
    let b = rtxgi_layout(kind);
    let s = rtxgi_sdk_layout(mod, kind);
    if b.is_err || s.is_err {
      drift_ok = false;
    } else {
      if b.value.count != s.value.count { drift_ok = false; }
      var i = 0;
      while i < b.value.count {
        if rtxgi_layout_field_offset(&b.value, i) != rtxgi_layout_field_offset(&s.value, i) { drift_ok = false; }
        if rtxgi_layout_field_size(&b.value, i) != rtxgi_layout_field_size(&s.value, i) { drift_ok = false; }
        i = i + 1;
      }
    }
    kind = kind + 1;
  }
  failed = failed + report(drift_ok, "drift: bridge ABI mirrors match the SDK struct layouts (5 tables, offsets+sizes)");

  // B6: defaults drift -- bridge defaults vs the SDK value-initialized desc.
  let bd = rtxgi_desc_default();
  let sd = rtxgi_sdk_desc_default(mod);
  var def_ok = bd.is_ok && sd.is_ok;
  if def_ok {
    var i = 0;
    while i < RTXGI_DESC_SIZE {
      if bd.value.data[i] != sd.value.data[i] { def_ok = false; }
      i = i + 1;
    }
  }
  failed = failed + report(def_ok, "drift: bridge desc defaults are byte-identical to the SDK's (168 bytes)");

  // Scene desc for the remaining checks.
  let scene = build_scene_desc();
  if scene.size != RTXGI_DESC_SIZE {
    failed = failed + report(false, "scene: desc build failed (rest of section B unavailable)");
    return failed;
  }

  // B7: probe counts (coordinate-system swap).
  let pc = rtxgi_probe_counts(mod, &scene);
  var pc_ok = false;
  if pc.is_ok {
    pc_ok = pc.value.x == 3 && pc.value.y == 4 && pc.value.z == 2;
    failed = failed + report(pc_ok, "probes: counts (3,2,4) -> texture counts ("
      + i2s(pc.value.x) + "," + i2s(pc.value.y) + "," + i2s(pc.value.z) + ") y/z swap");
  } else {
    failed = failed + report(false, "probes: count fetch failed -- " + pc.error.message);
  }

  // B8: texture dimensions for the small scene.
  let t_ray = rtxgi_texture_dimensions(mod, &scene, RTXGI_TEXTURE_TYPE_RAY_DATA);
  let t_irr = rtxgi_texture_dimensions(mod, &scene, RTXGI_TEXTURE_TYPE_IRRADIANCE);
  let t_dist = rtxgi_texture_dimensions(mod, &scene, RTXGI_TEXTURE_TYPE_DISTANCE);
  let t_data = rtxgi_texture_dimensions(mod, &scene, RTXGI_TEXTURE_TYPE_DATA);
  let t_var = rtxgi_texture_dimensions(mod, &scene, RTXGI_TEXTURE_TYPE_VARIABILITY);
  let t_vavg = rtxgi_texture_dimensions(mod, &scene, RTXGI_TEXTURE_TYPE_VARIABILITY_AVERAGE);
  var dims_ok = t_ray.is_ok && t_irr.is_ok && t_dist.is_ok && t_data.is_ok && t_var.is_ok && t_vavg.is_ok;
  if dims_ok {
    dims_ok = t_ray.value.x == 256 && t_ray.value.y == 12 && t_ray.value.z == 2;
    dims_ok = dims_ok && t_irr.value.x == 30 && t_irr.value.y == 40 && t_irr.value.z == 2;
    dims_ok = dims_ok && t_dist.value.x == 54 && t_dist.value.y == 72 && t_dist.value.z == 2;
    dims_ok = dims_ok && t_data.value.x == 3 && t_data.value.y == 4 && t_data.value.z == 2;
    dims_ok = dims_ok && t_var.value.x == 24 && t_var.value.y == 32 && t_var.value.z == 2;
    dims_ok = dims_ok && t_vavg.value.x == 2 && t_vavg.value.y == 2 && t_vavg.value.z == 1;
    failed = failed + report(dims_ok,
      "textures: ray(256,12,2) irr(30,40,2) dist(54,72,2) data(3,4,2) var(24,32,2) vavg(2,2,1)");
  } else {
    failed = failed + report(false, "textures: dimension fetch failed");
  }

  // B9: volume lifecycle + sizes.
  var vol = empty_volume();
  let created = rtxgi_volume_create(mod, &scene);
  var create_ok = false;
  if created.is_ok {
    vol = created.value;
    create_ok = vol.raw != 0;
  }
  if create_ok {
    let np = rtxgi_volume_num_probes(&vol);
    let nr = rtxgi_volume_num_rays(&vol);
    let ts = rtxgi_volume_tex2darray_size(&vol);
    let rd = rtxgi_volume_ray_dispatch(&vol);
    let gm = rtxgi_volume_gpu_memory(&vol);
    var life_ok = np.is_ok && nr.is_ok && ts.is_ok && rd.is_ok && gm.is_ok;
    if life_ok {
      life_ok = np.value == 24 && nr.value == 256 && ts.value == 2
        && rd.value.x == 256 && rd.value.y == 12 && rd.value.z == 2
        && gm.value == 9760;
      failed = failed + report(life_ok,
        "lifecycle: probes=" + i2s(np.value) + " rays=" + i2s(nr.value) + " array=" + i2s(ts.value)
          + " dispatch=(" + i2s(rd.value.x) + "," + i2s(rd.value.y) + "," + i2s(rd.value.z)
          + ") gpuBytes=" + i2s(gm.value));
    } else {
      failed = failed + report(false, "lifecycle: size queries failed");
    }
  } else {
    var m = "lifecycle: create failed";
    if created.is_err { m = "lifecycle: create failed -- " + created.error.message; }
    failed = failed + report(false, m);
  }

  // B10: GPU desc after create.
  if vol.raw != 0 {
    let gd = rtxgi_volume_gpu_desc(&vol);
    var g_ok = false;
    if gd.is_ok {
      let g = gd.value;
      g_ok = g.count_x == 3 && g.count_y == 2 && g.count_z == 4;
      g_ok = g_ok && near(g.origin.x, 1 as Float32, 0.0001 as Float32)
        && near(g.origin.y, 2 as Float32, 0.0001 as Float32)
        && near(g.origin.z, 3 as Float32, 0.0001 as Float32);
      g_ok = g_ok && near(g.probe_spacing.x, 1 as Float32, 0.0001 as Float32);
      g_ok = g_ok && near(g.rotation.x, 0 as Float32, 0.0001 as Float32)
        && near(g.rotation.w, 1 as Float32, 0.0001 as Float32);
      g_ok = g_ok && g.movement_type == 0;
      g_ok = g_ok && near(g.probe_hysteresis, 0.97 as Float32, 0.0001 as Float32);
      g_ok = g_ok && g.probe_num_rays == 256 && g.irradiance_interior_texels == 8
        && g.distance_interior_texels == 16;
    }
    failed = failed + report(g_ok, "gpu-desc: counts (3,2,4), origin (1,2,3), identity rotation, 256 rays, interior 8/16");
  } else {
    failed = failed + report(false, "gpu-desc: unavailable (no volume)");
  }

  // B11: RNG determinism (same seed -> same ray rotation; different seed -> different).
  var rng_ok = false;
  if vol.raw != 0 {
    let s1 = rtxgi_volume_seed_rng(&vol, 4242);
    let u1 = rtxgi_volume_update(&vol);
    let q1r = rtxgi_volume_gpu_desc(&vol);
    let s2 = rtxgi_volume_seed_rng(&vol, 4242);
    let u2 = rtxgi_volume_update(&vol);
    let q2r = rtxgi_volume_gpu_desc(&vol);
    let s3 = rtxgi_volume_seed_rng(&vol, 777);
    let u3 = rtxgi_volume_update(&vol);
    let q3r = rtxgi_volume_gpu_desc(&vol);
    let rnd1 = rtxgi_volume_get_random(&vol);
    let rnd2 = rtxgi_volume_get_random(&vol);
    if s1.is_ok && u1.is_ok && q1r.is_ok && s2.is_ok && u2.is_ok && q2r.is_ok && s3.is_ok && u3.is_ok && q3r.is_ok {
      let q1 = q1r.value.probe_ray_rotation;
      let q2 = q2r.value.probe_ray_rotation;
      let q3 = q3r.value.probe_ray_rotation;
      let same = q1.x == q2.x && q1.y == q2.y && q1.z == q2.z && q1.w == q2.w;
      var diff = false;
      if q1.x != q3.x || q1.y != q3.y || q1.z != q3.z { diff = true; }
      let len = q1.x * q1.x + q1.y * q1.y + q1.z * q1.z + q1.w * q1.w;
      rng_ok = same && diff && near(len, 1 as Float32, 0.001 as Float32);
      rng_ok = rng_ok && near(q1.x, 0.9537 as Float32, 0.01 as Float32)
        && near(q1.w, 0.2081 as Float32, 0.01 as Float32);
      if rnd1.is_ok && rnd2.is_ok { rng_ok = rng_ok && rnd1.value != rnd2.value; }
      else { rng_ok = false; }
      failed = failed + report(rng_ok,
        "rng: seed 4242 -> q=(" + f2s(q1.x) + "," + f2s(q1.y) + "," + f2s(q1.z) + "," + f2s(q1.w)
          + ") reproducible; seed 777 differs; unit length");
    } else {
      failed = failed + report(false, "rng: update/seed failed");
    }
  } else {
    failed = failed + report(false, "rng: unavailable (no volume)");
  }

  // B12: packed constants.
  if vol.raw != 0 {
    let pk = rtxgi_volume_gpu_desc_packed(&vol);
    var pk_ok = false;
    if pk.is_ok {
      let p = pk.value;
      pk_ok = p.size == RTXGI_PACKED_SIZE;
      pk_ok = pk_ok && rtxgi_packed_word(&p, 0) == 4196355;
      pk_ok = pk_ok && rtxgi_packed_word(&p, 1) == 1073682841;
      pk_ok = pk_ok && rtxgi_packed_word(&p, 2) == 268960000;
      pk_ok = pk_ok && rtxgi_packed_word(&p, 3) == 0;
      pk_ok = pk_ok && rtxgi_packed_word(&p, 4) == 0;
      let c = rtxgi_packed_counts(&p);
      pk_ok = pk_ok && c.x == 3 && c.y == 2 && c.z == 4;
      pk_ok = pk_ok && near(rtxgi_packed_f32(&p, RTXGI_PACKED_PROBE_HYSTERESIS), 0.97 as Float32, 0.0001 as Float32);
      failed = failed + report(pk_ok,
        "packed: word0=" + i2s(rtxgi_packed_word(&p, 0)) + " word1=" + i2s(rtxgi_packed_word(&p, 1))
          + " word2=" + i2s(rtxgi_packed_word(&p, 2)) + " decode counts (3,2,4)");
    } else {
      failed = failed + report(false, "packed: fetch failed -- " + pk.error.message);
    }
  } else {
    failed = failed + report(false, "packed: unavailable (no volume)");
  }

  // B13: scrolling.
  var scroll_ok = false;
  let v2r = rtxgi_volume_create(mod, &scene);
  if v2r.is_ok {
    var v2 = v2r.value;
    let mv = rtxgi_volume_set_movement_type(&v2, RTXGI_MOVEMENT_SCROLLING);
    let an = rtxgi_volume_set_scroll_anchor(&v2, 4.2 as Float32, 2 as Float32, 3 as Float32);
    let u1 = rtxgi_volume_update(&v2);
    let g1 = rtxgi_volume_gpu_desc(&v2);
    let o1 = rtxgi_volume_get_origin(&v2);
    var u1_ok = mv.is_ok && an.is_ok && u1.is_ok && g1.is_ok && o1.is_ok;
    if u1_ok {
      u1_ok = g1.value.scroll_x == 3 && g1.value.scroll_clear_0 == 1
        && near(o1.value.x, 4 as Float32, 0.0001 as Float32);
    }
    let u2 = rtxgi_volume_update(&v2);
    let g2 = rtxgi_volume_gpu_desc(&v2);
    let o2 = rtxgi_volume_get_origin(&v2);
    var u2_ok = u2.is_ok && g2.is_ok && o2.is_ok;
    if u2_ok {
      // offset 3 % counts.x 3 == 0 -> ScrollReset folds the offset into origin.
      u2_ok = g2.value.scroll_x == 0 && g2.value.scroll_clear_0 == 0
        && near(o2.value.x, 4 as Float32, 0.0001 as Float32);
    }
    scroll_ok = u1_ok && u2_ok;
    let destroyed = rtxgi_volume_destroy(&v2);
    scroll_ok = scroll_ok && destroyed.is_ok;
    failed = failed + report(scroll_ok, "scroll: anchor +3.2 cells -> offset 3/clear, next update folds into origin (4,2,3)");
  } else {
    failed = failed + report(false, "scroll: second volume create failed");
  }

  // B14: AABB + OBB (unrotated).
  if vol.raw != 0 {
    let ab = rtxgi_volume_aabb(&vol);
    let ob = rtxgi_volume_obb(&vol);
    var bo_ok = ab.is_ok && ob.is_ok;
    if bo_ok {
      bo_ok = near(ab.value.min.x, 0 as Float32, 0.0001 as Float32)
        && near(ab.value.min.y, (3 as Float32) / (2 as Float32), 0.0001 as Float32)
        && near(ab.value.min.z, (3 as Float32) / (2 as Float32), 0.0001 as Float32);
      bo_ok = bo_ok && near(ab.value.max.x, 2 as Float32, 0.0001 as Float32)
        && near(ab.value.max.y, (5 as Float32) / (2 as Float32), 0.0001 as Float32)
        && near(ab.value.max.z, (9 as Float32) / (2 as Float32), 0.0001 as Float32);
      bo_ok = bo_ok && near(ob.value.origin.x, 1 as Float32, 0.0001 as Float32)
        && near(ob.value.rotation.w, 1 as Float32, 0.0001 as Float32)
        && near(ob.value.extent.x, 1 as Float32, 0.0001 as Float32)
        && near(ob.value.extent.y, (1 as Float32) / (2 as Float32), 0.0001 as Float32)
        && near(ob.value.extent.z, (3 as Float32) / (2 as Float32), 0.0001 as Float32);
      failed = failed + report(bo_ok, "bounds: AABB (0,1.5,1.5)-(2,2.5,4.5), OBB extent (1,0.5,1.5) @ origin (1,2,3)");
    } else {
      failed = failed + report(false, "bounds: AABB/OBB fetch failed");
    }
  } else {
    failed = failed + report(false, "bounds: unavailable (no volume)");
  }

  // B15: probe world positions.
  if vol.raw != 0 {
    let p0 = rtxgi_volume_probe_world_pos(&vol, 0);
    let p3 = rtxgi_volume_probe_world_pos(&vol, 3);
    let p13 = rtxgi_volume_probe_world_pos(&vol, 13);
    var pw_ok = p0.is_ok && p3.is_ok && p13.is_ok;
    if pw_ok {
      pw_ok = near(p0.value.x, 0 as Float32, 0.0001 as Float32)
        && near(p0.value.y, (3 as Float32) / (2 as Float32), 0.0001 as Float32)
        && near(p0.value.z, (3 as Float32) / (2 as Float32), 0.0001 as Float32);
      pw_ok = pw_ok && near(p3.value.z, (5 as Float32) / (2 as Float32), 0.0001 as Float32);
      pw_ok = pw_ok && near(p13.value.x, 1 as Float32, 0.0001 as Float32)
        && near(p13.value.y, (5 as Float32) / (2 as Float32), 0.0001 as Float32);
      failed = failed + report(pw_ok, "probes: world positions 0->(0,1.5,1.5), 3->z 2.5, 13->(1,2.5,1.5)");
    } else {
      failed = failed + report(false, "probes: world position fetch failed");
    }
  } else {
    failed = failed + report(false, "probes: unavailable (no volume)");
  }

  // B16: euler rotation.
  if vol.raw != 0 {
    let ea = rtxgi_volume_set_euler_angles(&vol, 0 as Float32, 1.5707963 as Float32, 0 as Float32);
    let gr = rtxgi_volume_gpu_desc(&vol);
    let ar = rtxgi_volume_aabb(&vol);
    var eu_ok = ea.is_ok && gr.is_ok && ar.is_ok;
    if eu_ok {
      let q = gr.value.rotation;
      eu_ok = near(q.x, 0 as Float32, 0.001 as Float32) && near(q.z, 0 as Float32, 0.001 as Float32);
      var qy = q.y;
      if qy < (0 as Float32) { qy = (0 as Float32) - qy; }
      var qw = q.w;
      if qw < (0 as Float32) { qw = (0 as Float32) - qw; }
      eu_ok = eu_ok && near(qy, 0.7071067 as Float32, 0.001 as Float32)
        && near(qw, 0.7071067 as Float32, 0.001 as Float32);
      eu_ok = eu_ok && near(ar.value.min.x, (3 as Float32) / (2 as Float32), 0.001 as Float32)
        && near(ar.value.max.x, (9 as Float32) / (2 as Float32), 0.001 as Float32)
        && near(ar.value.min.z, (0 as Float32) - (2 as Float32), 0.001 as Float32)
        && near(ar.value.max.z, 0 as Float32, 0.001 as Float32);
      failed = failed + report(eu_ok, "rotation: euler y=90deg -> quaternion (0,0.7071,0,0.7071), rotated AABB recomputed");
    } else {
      failed = failed + report(false, "rotation: set/fetch failed");
    }
  } else {
    failed = failed + report(false, "rotation: unavailable (no volume)");
  }

  // B17: typed GPU-execution classification.
  if vol.raw != 0 {
    let ex = rtxgi_execute(&vol);
    if ex == RTXGI_EXEC_NO_DEVICE {
      failed = failed + report(true, "execute: SKIP -- RTXGI_EXEC_NO_DEVICE (no application device bridge in 0.1.0)");
    } else {
      failed = failed + report(false, "execute: expected RTXGI_EXEC_NO_DEVICE, got " + i2s(ex));
    }
    let dead = rtxgi_volume_destroy(&vol);
    failed = failed + report(dead.is_ok, "lifecycle: Destroy volume");
  } else {
    failed = failed + report(false, "execute: unavailable (no volume)");
    failed = failed + report(false, "lifecycle: Destroy unavailable (no volume)");
  }

  // B18: close + post-close guard.
  let closed = rtxgi_close(mod);
  var close_ok = closed.is_ok;
  if close_ok {
    let after = rtxgi_info(mod);
    close_ok = after.is_err && after.error.kind == RTXGI_ERR_NOT_LOADED;
  }
  failed = failed + report(close_ok, "loader: close unloads the shim and post-close calls are typed NOT_LOADED");

  return failed;
}

fn run_absent_skips() -> Int {
  var failed = 0;
  failed = failed + skip("shim: info");
  failed = failed + skip("descriptors: counts");
  failed = failed + skip("bytecode: validation");
  failed = failed + skip("perf-markers: global roundtrip");
  failed = failed + skip("drift: ABI mirrors vs SDK structs");
  failed = failed + skip("drift: desc defaults");
  failed = failed + skip("probes: counts");
  failed = failed + skip("textures: dimensions");
  failed = failed + skip("lifecycle: volume sizes");
  failed = failed + skip("gpu-desc: initial state");
  failed = failed + skip("rng: determinism");
  failed = failed + skip("packed: constants");
  failed = failed + skip("scroll: offsets + reset");
  failed = failed + skip("bounds: AABB/OBB");
  failed = failed + skip("probes: world positions");
  failed = failed + skip("rotation: euler");
  failed = failed + skip("execute: typed device classification");
  failed = failed + skip("lifecycle: Destroy volume");
  failed = failed + skip("loader: close + post-close guard");
  return failed;
}

// =========================================================================
// Main
// =========================================================================

pub fn main() -> Int {
  io.println("=== xiom.rtxgi conformance suite (0.1.0, upstream pin v1.3.7, reference-only) ===");
  io.flush_stdout();
  var failed: Int = 0;

  io.println("");
  io.println("-- SECTION A: classification + owned-struct plumbing (8) --");
  let a1 = test_a1_skip_path_classification(); failed = failed + report(a1.passed, a1.name);
  let a2 = test_a2_desc_layout();             failed = failed + report(a2.passed, a2.name);
  let a3 = test_a3_gpu_layouts();             failed = failed + report(a3.passed, a3.name);
  let a4 = test_a4_constant_tables();         failed = failed + report(a4.passed, a4.name);
  let a5 = test_a5_desc_defaults_roundtrip(); failed = failed + report(a5.passed, a5.name);
  let a6 = test_a6_desc_for_volume();         failed = failed + report(a6.passed, a6.name);
  let a7 = test_a7_packed_decode();           failed = failed + report(a7.passed, a7.name);
  let a8 = test_a8_signed_words();            failed = failed + report(a8.passed, a8.name);

  io.println("");
  io.println("-- SECTION B: shim surface (19; SKIP without xiom_rtxgi_shim.dll) --");
  let load = rtxgi_load();
  if load.is_ok {
    let mod: RtxgiModule = load.value;
    failed = failed + report(true, "load: RTXGI shim module resolved");
    failed = failed + run_present(&mod);
  } else {
    if load.error.kind == RTXGI_LOAD_ABSENT {
      failed = failed + report(true, "load: SKIP -- " + load.error.message);
    } else {
      failed = failed + report(false, "load: ABI failure -- " + load.error.message);
    }
    failed = failed + run_absent_skips();
  }

  io.println("");
  if failed == 0 {
    io.println("  ALL 27 CHECKS PASSED (SKIP-labelled checks are classified platform states)");
    return 0;
  }
  io.println("  FAILED: " + i2s(failed));
  return 1;
}

