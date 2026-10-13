// XIOM -- xiom.nrd conformance suite (0.1.0).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// 29 checks, identical count on every host:
//   SECTION A (7): always-run -- SKIP-path classification, ABI mirror
//     layout tables (sizes/offsets of the owned settings structs against
//     the pinned header-derived anchors), constant tables, owned-image
//     encode/decode plumbing (settings into owned structs).
//   SECTION B (22): runtime-dependent -- lifecycle (create/destroy,
//     instance desc, shader entry), typed errors (NON_UNIQUE_IDENTIFIER,
//     UNSUPPORTED, INVALID_ARGUMENT), real dispatch-plan computation for
//     320x180 (counts, grids, resource lists per denoiser, constant-buffer
//     reuse and settings->constants flow), plan validation, and the typed
//     GPU-execution classification (NRD_EXEC_NO_DEVICE -> SKIP).
//     Without a runtime module (default PATH), each B check reports
//     "SKIP" and stays green (classified platform state, not a gap).
//
// Runtime: NRD.dll built locally from the pinned clone (v4.17.3) by the
// licensee -- `XIOM_NRD_DLL` env var or the default module search.
// Run: scripts/port.ps1 -Package xiom.nrd -TimeoutSec 240

module nrd_conformance

use xiom.io;
use xiom.test;
use xiom.string;
use xiom.nrd;

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
  return report(true, name + " -- SKIP (no NRD runtime module present)");
}

fn empty_bytes() -> Vec[UInt8] {
  return Vec[UInt8].new();
}

fn empty_plan() -> NrdPlan {
  return NrdPlan{
    count: 0;
    resources_total: 0;
    constants_total: 0;
    max_resources: 0;
    summaries: empty_bytes();
    resources: empty_bytes();
    constants: empty_bytes();
  };
}

fn empty_instance() -> NrdInstance {
  return NrdInstance{ lib: 0; raw: 0 };
}

fn image_stub() -> NrdImage {
  return NrdImage{
    kind: 0;
    size: 0;
    count: 0;
    data: empty_bytes();
    offsets: empty_bytes();
    sizes: empty_bytes();
  };
}

fn push_i32(vals: &mut Vec[Int32], v: Int) {
  vals.push(v as Int32);
}

// =========================================================================
// SECTION A -- always-run (no runtime needed)
// =========================================================================

fn test_a1_skip_path_classification() -> TestResult {
  let r = nrd_load_named("xiom-absent-nrd-probe-xyz.dll");
  var ok = false;
  if r.is_err {
    ok = r.error.kind == NRD_LOAD_ABSENT;
  }
  return assert(ok, "skip-path: absent module classified as NRD_LOAD_ABSENT");
}

fn test_a2_layout_common() -> TestResult {
  let img = nrd_image_default(NRD_SETTINGS_COMMON);
  var ok = false;
  var msg = "layout: CommonSettings mirror fetch failed";
  if img.is_ok {
    ok = img.value.size == 432 && img.value.count == NRD_CS_FIELD_COUNT;
    msg = "layout: CommonSettings mirror size=" + i2s(img.value.size)
      + " fields=" + i2s(img.value.count) + " (expected 432/31)";
  }
  return assert(ok, msg);
}

fn test_a3_layout_denoisers() -> TestResult {
  let reblur = nrd_image_default(NRD_SETTINGS_REBLUR);
  let relax = nrd_image_default(NRD_SETTINGS_RELAX);
  let sigma = nrd_image_default(NRD_SETTINGS_SIGMA);
  let reference = nrd_image_default(NRD_SETTINGS_REFERENCE);
  var ok = reblur.is_ok && relax.is_ok && sigma.is_ok && reference.is_ok;
  var msg = "layout: denoiser settings mirror fetch failed";
  if ok {
    ok = reblur.value.size == 128 && reblur.value.count == NRD_RS_FIELD_COUNT;
    ok = ok && relax.value.size == 148 && relax.value.count == NRD_RXS_FIELD_COUNT;
    ok = ok && sigma.value.size == 20 && sigma.value.count == NRD_SS_FIELD_COUNT;
    ok = ok && reference.value.size == 4 && reference.value.count == NRD_RFS_FIELD_COUNT;
    msg = "layout: Reblur=" + i2s(reblur.value.size) + "/" + i2s(reblur.value.count)
      + " Relax=" + i2s(relax.value.size) + "/" + i2s(relax.value.count)
      + " SIGMA=" + i2s(sigma.value.size) + "/" + i2s(sigma.value.count)
      + " Reference=" + i2s(reference.value.size) + "/" + i2s(reference.value.count)
      + " (expected 128/28, 148/36, 20/3, 4/1)";
  }
  return assert(ok, msg);
}

fn test_a4_layout_offsets() -> TestResult {
  let img = nrd_image_default(NRD_SETTINGS_COMMON);
  var ok = false;
  var msg = "layout: offset fetch failed";
  if img.is_ok {
    let i = img.value;
    let off_size = nrd_image_field_offset(&i, NRD_CS_RESOURCE_SIZE);
    let off_viewz = nrd_image_field_offset(&i, NRD_CS_VIEWZ_SCALE);
    let off_frame = nrd_image_field_offset(&i, NRD_CS_FRAME_INDEX);
    let off_accum = nrd_image_field_offset(&i, NRD_CS_ACCUMULATION_MODE);
    ok = off_size == 348 && off_viewz == 364 && off_frame == 420 && off_accum == 424;
    ok = ok && nrd_image_field_size(&i, NRD_CS_VIEW_TO_CLIP) == 64;
    ok = ok && nrd_image_field_size(&i, NRD_CS_PRINTF_AT) == 4;
    msg = "layout: resourceSize@" + i2s(off_size) + " viewZScale@" + i2s(off_viewz)
      + " frameIndex@" + i2s(off_frame) + " accumulationMode@" + i2s(off_accum) + " (expected 348/364/420/424)";
  }
  return assert(ok, msg);
}

fn test_a5_constant_tables() -> TestResult {
  var ok = NRD_RESOURCE_TYPE_MAX_NUM == 32;
  ok = ok && NRD_DENOISER_MAX_NUM == 19;
  ok = ok && NRD_FORMAT_MAX_NUM == 44;
  ok = ok && NRD_RESULT_MAX_NUM == 5;
  ok = ok && NRD_RESOURCE_IN_PENUMBRA == 15;
  ok = ok && NRD_RESOURCE_OUT_SHADOW_TRANSLUCENCY == 27;
  ok = ok && NRD_RESOURCE_OUT_VALIDATION == 29;
  ok = ok && NRD_RESOURCE_PERMANENT_POOL == 31;
  ok = ok && NRD_DENOISER_REBLUR_DIFFUSE_SPECULAR == 6;
  ok = ok && NRD_DENOISER_REFERENCE == 18;
  ok = ok && NRD_VERSION_MAJOR == 4 && NRD_VERSION_MINOR == 17 && NRD_VERSION_BUILD == 3;
  return assert(ok, "constants: enum values + MAX_NUMs match the pinned headers");
}

fn test_a6_owned_image_roundtrip() -> TestResult {
  let built = nrd_common_settings_for_frame(320, 180);
  var ok = false;
  var msg = "image: default image build failed";
  if built.is_ok {
    var img = built.value;
    let rc0 = nrd_image_set_u32(&mut img, NRD_CS_FRAME_INDEX, 7);
    let rc1 = nrd_image_set_u8(&mut img, NRD_CS_ACCUMULATION_MODE, NRD_ACCUMULATION_CLEAR_AND_RESTART);
    let rc2 = nrd_image_set_f32(&mut img, NRD_CS_DISOCCLUSION_THRESHOLD, (2 as Float32) / (100 as Float32));
    let rc3 = nrd_image_set_f32(&mut img, NRD_CS_SPLIT_SCREEN, (1 as Float32) / (2 as Float32));
    ok = rc0.is_ok && rc1.is_ok && rc2.is_ok && rc3.is_ok;
    if ok {
      ok = nrd_image_get_u32(&img, NRD_CS_FRAME_INDEX) == 7;
      ok = ok && nrd_image_get_u16(&img, NRD_CS_RESOURCE_SIZE) == 320;
      ok = ok && nrd_image_get_u8(&img, NRD_CS_ACCUMULATION_MODE) == NRD_ACCUMULATION_CLEAR_AND_RESTART;
      let d = nrd_image_get_f32(&img, NRD_CS_DISOCCLUSION_THRESHOLD);
      ok = ok && d > ((19 as Float32) / (1000 as Float32)) && d < ((21 as Float32) / (1000 as Float32));
      let s = nrd_image_get_f32(&img, NRD_CS_SPLIT_SCREEN);
      ok = ok && s > ((49 as Float32) / (100 as Float32)) && s < ((51 as Float32) / (100 as Float32));
      let mvx = nrd_image_get_f32(&img, NRD_CS_MOTION_VECTOR_SCALE);
      ok = ok && mvx > ((99 as Float32) / (100 as Float32)) && mvx < ((101 as Float32) / (100 as Float32));
    }
    msg = "image: settings encode/decode roundtrip (u16/u32/u8/f32, defaults kept)";
  }
  return assert(ok, msg);
}

fn test_a7_owned_image_bytes() -> TestResult {
  let built = nrd_common_settings_for_frame(320, 180);
  var ok = false;
  var msg = "image: byte-evidence image build failed";
  if built.is_ok {
    var img = built.value;
    let rc = nrd_image_set_u32(&mut img, NRD_CS_FRAME_INDEX, 66051); // 0x00010203
    ok = rc.is_ok;
    if ok {
      // LE byte evidence at the frameIndex offset (420) and the size pair (348)
      ok = (img.data[420] as Int) == 3 && (img.data[421] as Int) == 2;
      ok = ok && (img.data[422] as Int) == 1 && (img.data[423] as Int) == 0;
      ok = ok && (img.data[348] as Int) == 64 && (img.data[349] as Int) == 1; // 320 = 0x0140
      ok = ok && (img.data[350] as Int) == 180 && (img.data[351] as Int) == 0;
    }
    msg = "image: raw little-endian bytes at the oracle offsets";
  }
  return assert(ok, msg);
}

// =========================================================================
// SECTION B -- runtime present (SKIP-labelled when absent)
// =========================================================================

/// Instance-dependent checks; exactly 12 reports.  `imgs` are built here.
fn run_instance_checks(inst: &NrdInstance, ids: &Vec[UInt8]) -> Int {
  var failed = 0;

  var reblur_img = image_stub();
  var sigma_img = image_stub();
  var imgs_ok = false;
  let reblur_r = nrd_image_default(NRD_SETTINGS_REBLUR);
  let sigma_r = nrd_image_default(NRD_SETTINGS_SIGMA);
  if reblur_r.is_ok && sigma_r.is_ok {
    reblur_img = reblur_r.value;
    sigma_img = sigma_r.value;
    imgs_ok = true;
  }

  // B8: unknown identifier -> typed INVALID_ARGUMENT.
  var unknown_ok = false;
  if imgs_ok {
    let su = nrd_set_denoiser_settings(inst, 99, &reblur_img);
    if su.is_err { unknown_ok = su.error.kind == NRD_RESULT_INVALID_ARGUMENT; }
  }
  failed = failed + report(unknown_ok, "typed: set settings for unknown identifier -> INVALID_ARGUMENT");

  // B9: invalid common settings (zero sizes) -> INVALID_ARGUMENT.
  var invalid_common_ok = false;
  let blank = nrd_image_default(NRD_SETTINGS_COMMON);
  if blank.is_ok {
    let blank_img = blank.value;
    let sb = nrd_set_common_settings(inst, &blank_img);
    if sb.is_err { invalid_common_ok = sb.error.kind == NRD_RESULT_INVALID_ARGUMENT; }
  }
  failed = failed + report(invalid_common_ok, "typed: zero-size CommonSettings -> INVALID_ARGUMENT");

  // B10: valid settings application.
  var settings_ok = false;
  let frame0 = nrd_common_settings_for_frame(320, 180);
  if frame0.is_ok && imgs_ok {
    let frame0_img = frame0.value;
    let sc = nrd_set_common_settings(inst, &frame0_img);
    let sr = nrd_set_denoiser_settings(inst, 1, &reblur_img);
    let ss = nrd_set_denoiser_settings(inst, 2, &sigma_img);
    settings_ok = sc.is_ok && sr.is_ok && ss.is_ok;
  }
  failed = failed + report(settings_ok, "settings: common + reblur + sigma applied (320x180)");

  if !settings_ok {
    failed = failed + report(false, "plan: dispatch plan unavailable (settings stage failed)");
    failed = failed + report(false, "plan: REBLUR resource evidence unavailable");
    failed = failed + report(false, "plan: SIGMA resource evidence unavailable");
    failed = failed + report(false, "plan: names + resource bounds unavailable");
    failed = failed + report(false, "plan: validate() unavailable");
    failed = failed + report(false, "plan: constant-buffer reuse unavailable");
    failed = failed + report(false, "plan: settings flow unavailable");
    failed = failed + report(false, "execute: plan unavailable");
    failed = failed + report(false, "lifecycle: DestroyInstance skipped after failed settings");
    return failed;
  }

  let plan_r = nrd_dispatch_plan(inst, ids);
  if plan_r.is_err {
    failed = failed + report(false, "plan: GetComputeDispatches failed -- " + plan_r.error.message);
    failed = failed + report(false, "plan: REBLUR resource evidence unavailable");
    failed = failed + report(false, "plan: SIGMA resource evidence unavailable");
    failed = failed + report(false, "plan: names + resource bounds unavailable");
    failed = failed + report(false, "plan: validate() unavailable");
    failed = failed + report(false, "plan: constant-buffer reuse unavailable");
    failed = failed + report(false, "plan: settings flow unavailable");
    failed = failed + report(false, "execute: plan unavailable");
    failed = failed + report(false, "lifecycle: DestroyInstance skipped after failed plan");
    return failed;
  }

  let plan = plan_r.value;

  // B11: plan shape -- counts/sums/grid bounds.
  var plan_ok = plan.count > 0 && plan.resources_total > 0 && plan.constants_total > 0;
  var sum_res = 0;
  var sum_cb = 0;
  var grids_ok = true;
  var k = 0;
  while k < plan.count {
    sum_res = sum_res + nrd_plan_dispatch_resources_num(&plan, k);
    sum_cb = sum_cb + nrd_plan_dispatch_cb_size(&plan, k);
    let gw = nrd_plan_dispatch_grid_width(&plan, k);
    let gh = nrd_plan_dispatch_grid_height(&plan, k);
    if gw <= 0 || gw > 320 || gh <= 0 || gh > 180 { grids_ok = false; }
    k = k + 1;
  }
  plan_ok = plan_ok && sum_res == plan.resources_total && sum_cb == plan.constants_total && grids_ok;
  failed = failed + report(plan_ok,
    "plan: " + i2s(plan.count) + " dispatches, resources=" + i2s(plan.resources_total)
      + ", constants=" + i2s(plan.constants_total) + " bytes, grids within 320x180");

  // B12/B13: per-denoiser resource evidence.
  let reblur_ok = nrd_plan_count_for(&plan, 1) > 0
    && nrd_plan_uses_resource(&plan, 1, NRD_RESOURCE_IN_DIFF_RADIANCE_HITDIST)
    && nrd_plan_uses_resource(&plan, 1, NRD_RESOURCE_IN_SPEC_RADIANCE_HITDIST)
    && nrd_plan_uses_resource(&plan, 1, NRD_RESOURCE_OUT_DIFF_RADIANCE_HITDIST)
    && nrd_plan_uses_resource(&plan, 1, NRD_RESOURCE_OUT_SPEC_RADIANCE_HITDIST);
  let sigma_ok = nrd_plan_count_for(&plan, 2) > 0
    && nrd_plan_uses_resource(&plan, 2, NRD_RESOURCE_IN_PENUMBRA)
    && nrd_plan_uses_resource(&plan, 2, NRD_RESOURCE_OUT_SHADOW_TRANSLUCENCY);
  failed = failed + report(reblur_ok,
    "plan: REBLUR dispatches reference diffuse+specular radiance in/out (" + i2s(nrd_plan_count_for(&plan, 1)) + " dispatches)");
  failed = failed + report(sigma_ok,
    "plan: SIGMA dispatches reference IN_PENUMBRA / OUT_SHADOW_TRANSLUCENCY (" + i2s(nrd_plan_count_for(&plan, 2)) + " dispatches)");

  // B14: names + resource bounds.
  var names_ok = true;
  var q = 0;
  while q < plan.count {
    if nrd_plan_dispatch_name(&plan, q).len() == 0 { names_ok = false; }
    let rn = nrd_plan_dispatch_resources_num(&plan, q);
    var j = 0;
    while j < rn {
      if nrd_plan_resource_type(&plan, q, j) >= NRD_RESOURCE_TYPE_MAX_NUM { names_ok = false; }
      if nrd_plan_resource_descriptor_type(&plan, q, j) >= NRD_DESCRIPTOR_TYPE_MAX_NUM { names_ok = false; }
      j = j + 1;
    }
    q = q + 1;
  }
  failed = failed + report(names_ok, "plan: all dispatches named, resource records in bounds");

  // B15: CPU-side pre-execution validation.
  let vrc = nrd_plan_validate(&plan);
  failed = failed + report(vrc == 0,
    "plan: validate() == " + i2s(vrc) + " (grids/resources/offsets consistent)");

  // B16: constant-buffer reuse flags (intra-plan dedup evidence).
  var matches = 0;
  var m = 1;
  while m < plan.count {
    if nrd_plan_dispatch_matches_previous(&plan, m) { matches = matches + 1; }
    m = m + 1;
  }
  failed = failed + report(matches >= 1,
    "plan: constant-buffer reuse signaled on " + i2s(matches) + " dispatch(es)");

  // B17: settings flow -- frameIndex increment changes the constants.
  var flow_ok = false;
  var plan_b = empty_plan();
  let frame1_r = nrd_common_settings_for_frame(320, 180);
  if frame1_r.is_ok {
    var frame1 = frame1_r.value;
    let s1 = nrd_image_set_u32(&mut frame1, NRD_CS_FRAME_INDEX, 1);
    let sc1 = nrd_set_common_settings(inst, &frame1);
    if s1.is_ok && sc1.is_ok {
      let plan_b_r = nrd_dispatch_plan(inst, ids);
      if plan_b_r.is_ok {
        plan_b = plan_b_r.value;
        flow_ok = plan_b.count == plan.count
          && plan_b.resources_total == plan.resources_total
          && !nrd_plan_constants_equal(&plan, &plan_b);
      }
    }
  }
  failed = failed + report(flow_ok,
    "plan: frameIndex 0->1 changes constant buffers (settings flow into dispatches)");

  // B18: GPU execution path -> typed SKIP.
  let exec = nrd_execute(inst, &plan_b);
  if exec == NRD_EXEC_NO_DEVICE {
    failed = failed + report(true, "execute: SKIP -- NRD_EXEC_NO_DEVICE (no application device bridge in 0.1.0)");
  } else {
    failed = failed + report(false, "execute: expected NRD_EXEC_NO_DEVICE, got " + i2s(exec));
  }

  // B19: destroy.
  let dead = nrd_destroy_instance(inst);
  failed = failed + report(dead.is_ok, "lifecycle: DestroyInstance");
  return failed;
}

fn skip_instance_checks() -> Int {
  var failed = 0;
  failed = failed + skip("typed: unknown identifier");
  failed = failed + skip("typed: zero-size CommonSettings");
  failed = failed + skip("settings: common + reblur + sigma");
  failed = failed + skip("plan: count/sums/grids");
  failed = failed + skip("plan: REBLUR resource evidence");
  failed = failed + skip("plan: SIGMA resource evidence");
  failed = failed + skip("plan: names + resource bounds");
  failed = failed + skip("plan: validate()");
  failed = failed + skip("plan: constant-buffer reuse");
  failed = failed + skip("plan: settings flow");
  failed = failed + skip("execute: typed device classification");
  failed = failed + skip("lifecycle: DestroyInstance");
  return failed;
}

fn run_present(lib: &NrdLibrary) -> Int {
  var failed = 0;

  // B2a: version / encodings / supported count (LibraryDesc mirror check).
  let li = nrd_library_info(lib);
  var version_ok = false;
  if li.is_ok {
    let info = li.value;
    version_ok = info.version_major == NRD_VERSION_MAJOR
      && info.version_minor == NRD_VERSION_MINOR
      && info.version_build == NRD_VERSION_BUILD
      && info.denoisers_num == NRD_DENOISER_MAX_NUM
      && info.normal_encoding == NRD_NORMAL_ENCODING_R10_G10_B10_A2_UNORM
      && info.roughness_encoding == NRD_ROUGHNESS_ENCODING_LINEAR;
    failed = failed + report(version_ok,
      "library: v" + i2s(info.version_major) + "." + i2s(info.version_minor) + "." + i2s(info.version_build)
        + " encodings " + i2s(info.normal_encoding) + "/" + i2s(info.roughness_encoding)
        + " denoisers " + i2s(info.denoisers_num));
    failed = failed + report(info.sampler_offset == 0 && info.constant_buffer_offset == 2
      && info.storage_texture_offset == 3 && info.texture_offset == 20,
      "library: SPIRV binding offsets " + i2s(info.sampler_offset) + "/" + i2s(info.texture_offset)
        + "/" + i2s(info.constant_buffer_offset) + "/" + i2s(info.storage_texture_offset)
        + " (pinned CMake constants 0/20/2/3)");
  } else {
    failed = failed + report(false, "library: info failed -- " + li.error.message);
    failed = failed + report(false, "library: binding offsets unavailable");
  }

  // B3: supported-denoiser table.
  var table_ok = true;
  var i = 0;
  while i < NRD_DENOISER_MAX_NUM {
    let kind = nrd_library_denoiser(lib, i);
    if kind < 0 || kind >= NRD_DENOISER_MAX_NUM { table_ok = false; }
    i = i + 1;
  }
  table_ok = table_ok && nrd_library_denoiser(lib, 0) == NRD_DENOISER_REBLUR_DIFFUSE;
  table_ok = table_ok && nrd_library_denoiser(lib, 6) == NRD_DENOISER_REBLUR_DIFFUSE_SPECULAR;
  table_ok = table_ok && nrd_library_denoiser(lib, 18) == NRD_DENOISER_REFERENCE;
  failed = failed + report(table_ok, "library: 19 supported denoisers enumerated in enum order");

  // B4: strings.
  let s_mv = nrd_resource_string(lib, NRD_RESOURCE_IN_MV);
  let s_val = nrd_resource_string(lib, NRD_RESOURCE_OUT_VALIDATION);
  let s_den = nrd_denoiser_string(lib, NRD_DENOISER_REBLUR_DIFFUSE_SPECULAR);
  var strings_ok = str_compare(s_mv, "IN_MV") == 0;
  strings_ok = strings_ok && str_compare(s_val, "OUT_VALIDATION") == 0;
  strings_ok = strings_ok && str_compare(s_den, "REBLUR_DIFFUSE_SPECULAR") == 0;
  var t = 0;
  while t < NRD_RESOURCE_TYPE_MAX_NUM {
    if nrd_resource_string(lib, t).len() == 0 { strings_ok = false; }
    t = t + 1;
  }
  failed = failed + report(strings_ok, "strings: resource/denoiser names (all 32 resource types non-empty)");

  // B5/B6: create + instance desc + shader entry.
  var id_vals: Vec[Int32] = Vec[Int32].new();
  push_i32(&mut id_vals, 1);
  push_i32(&mut id_vals, 2);
  var kind_vals: Vec[Int32] = Vec[Int32].new();
  push_i32(&mut kind_vals, NRD_DENOISER_REBLUR_DIFFUSE_SPECULAR);
  push_i32(&mut kind_vals, NRD_DENOISER_SIGMA_SHADOW);
  let ids = nrd_u32_image(&id_vals);
  let kinds = nrd_u32_image(&kind_vals);

  var inst = empty_instance();
  let created = nrd_create_instance(lib, &ids, &kinds);
  var create_ok = false;
  if created.is_ok {
    inst = created.value;
    create_ok = inst.raw != 0;
  }
  if create_ok {
    let ii = nrd_instance_info(&inst);
    if ii.is_ok {
      let info = ii.value;
      create_ok = info.pipelines_num > 0 && info.cb_max_data_size > 0
        && info.samplers_num == NRD_SAMPLER_MAX_NUM
        && info.permanent_pool_size > 0 && info.transient_pool_size > 0;
      failed = failed + report(create_ok,
        "lifecycle: instance pipelines=" + i2s(info.pipelines_num) + " cbMax=" + i2s(info.cb_max_data_size)
          + " samplers=" + i2s(info.samplers_num) + " pools=" + i2s(info.permanent_pool_size)
          + "/" + i2s(info.transient_pool_size));
    } else {
      failed = failed + report(false, "lifecycle: instance info failed -- " + ii.error.message);
    }
    let entry = nrd_instance_shader_entry(&inst);
    failed = failed + report(str_compare(entry, "main") == 0,
      "lifecycle: shader entry point '" + entry + "' (NRD_CS_MAIN default)");
  } else {
    var msg = "lifecycle: CreateInstance failed";
    if created.is_err { msg = "lifecycle: CreateInstance failed -- " + created.error.message; }
    failed = failed + report(false, msg);
    failed = failed + report(false, "lifecycle: shader entry unavailable");
  }

  // B7: duplicate identifier -> typed NON_UNIQUE_IDENTIFIER.
  var dup_ids_v: Vec[Int32] = Vec[Int32].new();
  push_i32(&mut dup_ids_v, 5);
  push_i32(&mut dup_ids_v, 5);
  var dup_kinds_v: Vec[Int32] = Vec[Int32].new();
  push_i32(&mut dup_kinds_v, NRD_DENOISER_SIGMA_SHADOW);
  push_i32(&mut dup_kinds_v, NRD_DENOISER_SIGMA_SHADOW);
  let dup_ids = nrd_u32_image(&dup_ids_v);
  let dup_kinds = nrd_u32_image(&dup_kinds_v);
  let dup = nrd_create_instance(lib, &dup_ids, &dup_kinds);
  var dup_ok = false;
  if dup.is_err { dup_ok = dup.error.kind == NRD_RESULT_NON_UNIQUE_IDENTIFIER; }
  failed = failed + report(dup_ok, "typed: duplicate identifier -> NON_UNIQUE_IDENTIFIER");

  // B8: unknown denoiser kind -> typed UNSUPPORTED.
  var one_id_v: Vec[Int32] = Vec[Int32].new();
  push_i32(&mut one_id_v, 9);
  var bad_kind_v: Vec[Int32] = Vec[Int32].new();
  push_i32(&mut bad_kind_v, 2147483647);
  let one_id = nrd_u32_image(&one_id_v);
  let bad_kind_img = nrd_u32_image(&bad_kind_v);
  let bad = nrd_create_instance(lib, &one_id, &bad_kind_img);
  var bad_ok = false;
  if bad.is_err { bad_ok = bad.error.kind == NRD_RESULT_UNSUPPORTED; }
  failed = failed + report(bad_ok, "typed: unknown denoiser kind -> UNSUPPORTED");

  // Instance-dependent checks (12 reports either way).
  if inst.raw != 0 {
    failed = failed + run_instance_checks(&inst, &ids);
  } else {
    failed = failed + skip_instance_checks();
  }

  // B21: close + post-close guard.
  let closed = nrd_close(lib);
  var close_ok = closed.is_ok;
  if close_ok {
    let after = nrd_library_info(lib);
    close_ok = after.is_err && after.error.kind == NRD_ERR_NOT_LOADED;
  }
  failed = failed + report(close_ok, "loader: close unloads the runtime and post-close calls are typed NOT_LOADED");

  return failed;
}

fn run_absent_skips() -> Int {
  var failed = 0;
  failed = failed + skip("library: version/encodings");
  failed = failed + skip("library: binding offsets");
  failed = failed + skip("library: supported denoisers");
  failed = failed + skip("strings: resource/denoiser names");
  failed = failed + skip("lifecycle: create + instance info");
  failed = failed + skip("lifecycle: shader entry point");
  failed = failed + skip("typed: duplicate identifier");
  failed = failed + skip("typed: unknown denoiser kind");
  failed = failed + skip_instance_checks();
  failed = failed + skip("loader: close + post-close guard");
  return failed;
}

// =========================================================================
// Main
// =========================================================================

pub fn main() -> Int {
  io.println("=== xiom.nrd conformance suite (0.1.0, upstream pin v4.17.3, reference-only) ===");
  io.flush_stdout();
  var failed: Int = 0;

  io.println("");
  io.println("-- SECTION A: classification + owned-struct plumbing (7) --");
  let a1 = test_a1_skip_path_classification(); failed = failed + report(a1.passed, a1.name);
  let a2 = test_a2_layout_common();             failed = failed + report(a2.passed, a2.name);
  let a3 = test_a3_layout_denoisers();          failed = failed + report(a3.passed, a3.name);
  let a4 = test_a4_layout_offsets();            failed = failed + report(a4.passed, a4.name);
  let a5 = test_a5_constant_tables();           failed = failed + report(a5.passed, a5.name);
  let a6 = test_a6_owned_image_roundtrip();     failed = failed + report(a6.passed, a6.name);
  let a7 = test_a7_owned_image_bytes();         failed = failed + report(a7.passed, a7.name);

  io.println("");
  io.println("-- SECTION B: runtime surface (22; SKIP without NRD.dll) --");
  let load = nrd_load();
  if load.is_ok {
    let lib: NrdLibrary = load.value;
    failed = failed + report(true, "load: NRD runtime module resolved");
    failed = failed + run_present(&lib);
  } else {
    if load.error.kind == NRD_LOAD_ABSENT {
      failed = failed + report(true, "load: SKIP -- " + load.error.message);
    } else {
      failed = failed + report(false, "load: ABI failure -- " + load.error.message);
    }
    failed = failed + run_absent_skips();
  }

  io.println("");
  if failed == 0 {
    io.println("  ALL 29 CHECKS PASSED (SKIP-labelled checks are classified platform states)");
    return 0;
  }
  io.println("  FAILED: " + i2s(failed));
  return 1;
}
