// xiom.dlss conformance suite -- declared surface + SKIP classification.
//
// The DLSS SDK runtime is NOT shipped with this package and the suite never
// downloads one.  On a host without an NGX runtime every runtime check
// reports a typed SKIP with the loader's ABSENT classification; the surface
// checks (table completeness, key data, codes, entry points) run everywhere.
//
// Optional present path (no download): set XIOM_DLSS_DIR to a directory
// that contains an NVIDIA runtime module (e.g. a game folder or the DLSS
// SDK's lib/Windows_x86_64/rel) and the suite loads nvngx_dlss.dll from
// there, resolves the whole declared table and reports the per-group
// resolution counts instead of SKIP.
//
// Build+run:
//   scripts/port.ps1 -Package xiom.dlss

module dlss_conformance

use xiom.io;
use xiom.test;
use xiom.dlss;
use xiom.dlss.surface;
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

fn str_eq(a: Str, b: Str) -> Bool {
  return string.str_compare(a, b) == 0;
}

fn has_prefix(s: Str, p: Str) -> Bool {
  return string.str_starts_with(s, p);
}

// ---- table checks -----------------------------------------------------------

fn run_table_checks(failed: Int) -> Int {
  var out = failed;
  let es = dlss_table_entries();
  let n = es.len();
  out = out + report(n == 85, "table: 85 declared entries (" + i2s(n) + ")");

  let gc_ok = dlss_group_entry_count(DLSS_GROUP_CORE_D3D11) == 15
    && dlss_group_entry_count(DLSS_GROUP_CORE_D3D12) == 15
    && dlss_group_entry_count(DLSS_GROUP_CORE_CUDA) == 17
    && dlss_group_entry_count(DLSS_GROUP_CORE_VULKAN) == 20
    && dlss_group_entry_count(DLSS_GROUP_PARAMETER) == 16
    && dlss_group_entry_count(DLSS_GROUP_GLOBAL) == 2;
  var summed = 0;
  var g = 0;
  while g <= 5 {
    summed = summed + dlss_group_entry_count(g);
    g = g + 1;
  }
  out = out + report(gc_ok && summed == n,
    "table: group counts 15/15/17/20/16/2 sum to " + i2s(summed));

  var dups = 0;
  var i = 0;
  while i < n {
    var j = i + 1;
    while j < n {
      if str_eq(es[i].name, es[j].name) { dups = dups + 1; }
      j = j + 1;
    }
    i = i + 1;
  }
  out = out + report(dups == 0, "table: no duplicate declared names");

  var prefix_ok = true;
  var aliases = 0;
  i = 0;
  while i < n {
    let e = es[i];
    if e.group == DLSS_GROUP_CORE_D3D11 && !has_prefix(e.name, "NVSDK_NGX_D3D11_") { prefix_ok = false; }
    if e.group == DLSS_GROUP_CORE_D3D12 && !has_prefix(e.name, "NVSDK_NGX_D3D12_") { prefix_ok = false; }
    if e.group == DLSS_GROUP_CORE_CUDA && !has_prefix(e.name, "NVSDK_NGX_CUDA_") { prefix_ok = false; }
    if e.group == DLSS_GROUP_CORE_VULKAN && !has_prefix(e.name, "NVSDK_NGX_VULKAN_") { prefix_ok = false; }
    if e.group == DLSS_GROUP_PARAMETER && !has_prefix(e.name, "NVSDK_NGX_Parameter_") { prefix_ok = false; }
    if e.group == DLSS_GROUP_GLOBAL {
      if !str_eq(e.name, "NVSDK_NGX_UpdateFeature") && !str_eq(e.name, "GetNGXResultAsString") { prefix_ok = false; }
    }
    if e.runtime.len() > 0 {
      aliases = aliases + 1;
      if str_eq(e.runtime, e.name) { prefix_ok = false; }
      if !has_prefix(e.name, "NVSDK_NGX_") { prefix_ok = false; }
      if !has_prefix(e.runtime, "NVSDK_NGX_") { prefix_ok = false; }
    }
    i = i + 1;
  }
  out = out + report(prefix_ok, "table: every entry carries its group prefix");
  out = out + report(aliases == 4,
    "table: 4 runtime spelling aliases (Init_ProjectID core spellings), " + i2s(aliases));

  // Spot-check the documented anchors of each API family.
  let anchors_ok = str_eq(es[0].name, "NVSDK_NGX_D3D11_Init")
    && str_eq(es[15].name, "NVSDK_NGX_D3D12_Init")
    && str_eq(es[30].name, "NVSDK_NGX_CUDA_Init")
    && str_eq(es[47].name, "NVSDK_NGX_VULKAN_RequiredExtensions")
    && str_eq(es[67].name, "NVSDK_NGX_Parameter_SetULL")
    && str_eq(es[83].name, "NVSDK_NGX_UpdateFeature")
    && str_eq(es[84].name, "GetNGXResultAsString");
  out = out + report(anchors_ok, "table: family anchors at their pinned indices");
  return out;
}

// ---- key / code data checks -------------------------------------------------

fn run_key_checks(failed: Int) -> Int {
  var out = failed;

  let keys = dlss_param_key_table();
  out = out + report(keys.len() == DLSS_PARAM_KEY_COUNT && DLSS_PARAM_KEY_COUNT == 435,
    "keys: parameter key table complete (" + i2s(keys.len()) + " == " + i2s(DLSS_PARAM_KEY_COUNT) + ")");

  var empty = 0;
  var dups = 0;
  var i = 0;
  while i < keys.len() {
    if keys[i].len() == 0 { empty = empty + 1; }
    var j = i + 1;
    while j < keys.len() {
      if str_eq(keys[i], keys[j]) { dups = dups + 1; }
      j = j + 1;
    }
    i = i + 1;
  }
  out = out + report(empty == 0 && dups == 0, "keys: no empty or duplicate key strings");

  let spot = str_eq(NVSDK_NGX_Parameter_Width, "Width")
    && str_eq(NVSDK_NGX_Parameter_Height, "Height")
    && str_eq(NVSDK_NGX_Parameter_OutWidth, "OutWidth")
    && str_eq(NVSDK_NGX_Parameter_OutHeight, "OutHeight")
    && str_eq(NVSDK_NGX_Parameter_Sharpness, "Sharpness")
    && str_eq(NVSDK_NGX_Parameter_PerfQualityValue, "PerfQualityValue")
    && str_eq(NVSDK_NGX_Parameter_RTXValue, "RTXValue")
    && str_eq(NVSDK_NGX_Parameter_DLSSOptimalSettingsCallback, "DLSSOptimalSettingsCallback")
    && str_eq(NVSDK_NGX_Parameter_SuperSampling_Available, "SuperSampling.Available")
    && str_eq(NVSDK_NGX_Parameter_DLSS_Feature_Create_Flags, "DLSS.Feature.Create.Flags")
    && str_eq(NVSDK_NGX_Parameter_DLSS_Denoise_Mode, "DLSS.Denoise.Mode")
    && str_eq(NVSDK_NGX_DLSSG_Parameter_Backbuffer, "DLSSG.Backbuffer");
  out = out + report(spot, "keys: spot-check values (Width/PerfQualityValue/SuperSampling.Available/DLSSG.Backbuffer)");

  let codes_ok = DLSS_EPARAM_COUNT == 74
    && NVSDK_NGX_EParameter_Width == 16
    && NVSDK_NGX_EParameter_Height == 17
    && NVSDK_NGX_EParameter_OutWidth == 18
    && NVSDK_NGX_EParameter_OutHeight == 19
    && NVSDK_NGX_EParameter_Sharpness == 20
    && NVSDK_NGX_EParameter_SuperSampling_Available == 1
    && NVSDK_NGX_EParameter_DLSSOptimalSettingsCallback == 62;
  out = out + report(codes_ok, "codes: 74 effective-key byte codes with pinned anchors");

  let k0 = dlss_eparameter_key(0);
  let k1 = dlss_eparameter_key(1);
  let k16 = dlss_eparameter_key(16);
  let kb_ok = k0.len() == 1
    && (string.byte_at(k0, 0) as Int) == 35
    && k1.len() == 2
    && (string.byte_at(k1, 0) as Int) == 35
    && (string.byte_at(k1, 1) as Int) == 1
    && k16.len() == 2
    && (string.byte_at(k16, 1) as Int) == 16;
  out = out + report(kb_ok, "codes: effective-key builder \"#\" + raw byte (0, 1, 16)");

  let enum_ok = NVSDK_NGX_FEATURE_SUPER_SAMPLING == 1
    && NVSDK_NGX_FEATURE_FRAME_GENERATION == 11
    && NVSDK_NGX_FEATURE_RAY_RECONSTRUCTION == 13
    && NVSDK_NGX_VERSION_API == 21
    && NVSDK_NGX_PERF_QUALITY_DLAA == 5
    && NVSDK_NGX_DLSS_FEATURE_FLAGS_IS_INVALID == 2147483648
    && NVSDK_NGX_DLSS_FEATURE_FLAGS_MV_JITTERED == 4
    && NVSDK_NGX_DLSSG_RESOURCE_FLAGS_OUTPUT_REAL == 33554432;
  out = out + report(enum_ok, "codes: feature ids / flags / perf-quality / meta-data pins");

  let res_ok = NVSDK_NGX_RESULT_SUCCESS == 1
    && NVSDK_NGX_RESULT_FAIL == 3132620800
    && NVSDK_NGX_RESULT_FAIL_OUT_OF_DATE == 3132620812
    && dlss_succeeded(NVSDK_NGX_RESULT_SUCCESS)
    && dlss_failed(NVSDK_NGX_RESULT_FAIL)
    && dlss_failed(NVSDK_NGX_RESULT_FAIL_FEATURE_NOT_SUPPORTED)
    && dlss_failed(NVSDK_NGX_RESULT_FAIL_NOT_IMPLEMENTED);
  out = out + report(res_ok, "codes: NVSDK_NGX_Result set + SUCCEED/FAILED semantics");
  return out;
}

// ---- loader / classification ------------------------------------------------

fn run_loader_checks(failed: Int) -> Int {
  var out = failed;

  let bogus = dlss_load_from("xiom-dlss-absent-a.dll", "xiom-dlss-absent-b.dll", "", "");
  out = out + report(
    !bogus.is_ok && bogus.error.kind == DLSS_LOAD_ABSENT && bogus.error.message.len() > 0,
    "loader: bogus explicit paths classify ABSENT (typed SKIP)");

  out = out + report(dlss_entry_index("NVSDK_NGX_D3D12_Init") == 15
    && dlss_entry_index("GetNGXResultAsString") == 84
    && dlss_entry_index("NVSDK_NGX_NoSuchEntry") == -1,
    "loader: entry index lookup (D3D12 Init = 15, global tail, unknown = -1)");

  let wp = dlss_wide_path("ab");
  out = out + report(
    wp.len() == 6
      && (wp[0] as Int) == 97 && (wp[1] as Int) == 0
      && (wp[2] as Int) == 98 && (wp[3] as Int) == 0
      && (wp[4] as Int) == 0 && (wp[5] as Int) == 0,
    "loader: UTF-16LE path helper (dlss_wide_path)");

  // Common-location probe: typed SKIP unless the host has a runtime.
  let pres = dlss_probe_present_path();
  if !pres.found {
    out = out + report(true,
      "runtime: SKIP -- no NGX runtime in common locations (" + pres.searched + ")");
  } else {
    out = out + report(true,
      "runtime: PRESENT -- " + pres.dlss_path + " / " + pres.core_path);
  }

  // Default loader: Ok = present host, ABSENT = the documented SKIP state.
  let l = dlss_load();
  if !l.is_ok {
    out = out + report(l.error.kind == DLSS_LOAD_ABSENT,
      "runtime: default loader SKIP classification (" + l.error.message + ")");
  } else {
    let lib: DlssLibrary = l.value;
    let n = dlss_entry_count(&lib);
    let r_all = dlss_resolved_count(&lib);
    let r_d3d12 = dlss_resolved_in_group(&lib, DLSS_GROUP_CORE_D3D12);
    let r_param = dlss_resolved_in_group(&lib, DLSS_GROUP_PARAMETER);
    out = out + report(n == 85 && r_d3d12 >= 1,
      "runtime: PRESENT -- " + dlss_module_summary(&lib) + "; resolved " + i2s(r_all) + "/" + i2s(n)
        + " (D3D12 " + i2s(r_d3d12) + "/15, param " + i2s(r_param) + "/16)");
    let cl = dlss_close(&lib);
    out = out + report(cl.is_ok, "runtime: library closed cleanly");
  }

  // Optional present path for development hosts (no download performed):
  // XIOM_DLSS_DIR points at a directory holding a runtime module.
  let dir = io.env_var("XIOM_DLSS_DIR");
  if dir.is_some {
    let path = io.join_paths(dir.value, "nvngx_dlss.dll");
    if io.file_exists(path) {
      let lp = dlss_load_from(path, "", "", "");
      if lp.is_ok {
        let lib: DlssLibrary = lp.value;
        let total = dlss_resolved_count(&lib);
        let d12 = dlss_resolved_in_group(&lib, DLSS_GROUP_CORE_D3D12);
        let vulkan = dlss_resolved_in_group(&lib, DLSS_GROUP_CORE_VULKAN);
        let a1 = dlss_entry_resolved(&lib, "NVSDK_NGX_D3D12_CreateFeature");
        let a2 = dlss_entry_resolved_as(&lib, "NVSDK_NGX_D3D12_Init");
        out = out + report(a1 && a2.len() > 0 && d12 >= 9 && total >= 38,
          "runtime: XIOM_DLSS_DIR present path -- nvngx_dlss.dll resolved " + i2s(total) + "/85 (D3D12 "
            + i2s(d12) + "/15, VULKAN " + i2s(vulkan) + "/20; D3D12 Init via '" + a2 + "')");
        let cl = dlss_close(&lib);
        out = out + report(cl.is_ok, "runtime: XIOM_DLSS_DIR library closed cleanly");
      } else {
        out = out + report(false, "runtime: XIOM_DLSS_DIR load failed -- " + lp.error.message);
      }
    } else {
      out = out + report(true, "runtime: XIOM_DLSS_DIR set but has no nvngx_dlss.dll -- SKIP");
    }
  } else {
    out = out + report(true, "runtime: XIOM_DLSS_DIR not set -- SKIP (optional present path)");
  }
  return out;
}

fn run_scope_checks(failed: Int) -> Int {
  var out = failed;
  out = out + report(!DLSS_REFLEX_COVERED,
    "scope: SKIP -- Reflex (PCL stats/markers) not declared: the pinned public headers do not describe it");
  out = out + report(true,
    "scope: DLSS-FG / DLSS-RR entry points are the per-API core entries with feature ids 11/13 (create/evaluate/release via the same resolved table)");
  return out;
}

fn main() -> Int {
  io.println("=== xiom.dlss conformance tests (declared surface + SKIP classification) ===");
  io.flush_stdout();
  var out: Int = 0;

  out = run_table_checks(out);
  out = run_key_checks(out);
  out = run_loader_checks(out);
  out = run_scope_checks(out);

  if out == 0 {
    io.println("xiom.dlss: all tests passed");
  } else {
    io.println("xiom.dlss: tests failed");
  }
  return out;
}
