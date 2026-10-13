// xiom.fidelityfx conformance suite -- HEADLESS-FIRST.
//
// What runs everywhere (no GPU, no effect DLL required):
//   * declared-surface census over the 61 generated records (kinds,
//     components, signatures, 100% attribution, skips = 0);
//   * ABI conformance: every struct size/field offset computed by
//     tools/gen_fidelityfx.py is compared against the compiler-computed
//     sizeof/offsetof of the VENDORED headers;
//   * owned-buffer descriptor builders (upscale create/dispatch) with
//     byte-exact read-back through the generated offset tables;
//   * FSR1 EASU/RCAS + SPD constant setup executed on the CPU path of the
//     pinned headers, checked against golden values computed from the same
//     headers (tools/gen_golden_values.cpp);
//   * the six vendored compiled swapchain shader blobs: fetch into owned
//     buffers + SHA256 against the recorded payload registry;
//   * typed error paths (NULL/RANGE/ARG bridge codes) and version probes;
//   * loader lifecycle: bogus soname -> typed ABSENT.
//
// What needs the signed effect DLLs on PATH (present-path evidence; absent
// -> typed SKIP, suite stays green):
//   * five unified entry points resolved from amd_fidelityfx_*_dx12.dll;
//   * ffxConfigure(GLOBALDEBUG) accepted headless;
//   * unknown descriptor type -> typed NO_PROVIDER(4) / API error;
//   * upscale create without a device -> typed NO_DEVICE classification;
//   * provider version enumeration (ffxQuery GET_VERSIONS, device = null);
//   * the 50 declared host-API/inline records resolve-and-classify ABSENT on
//     the signed provider-based binaries (never a silent gap).
//
// Build+run:
//   scripts/port.ps1 -Package xiom.fidelityfx -TimeoutSec 300

module fidelityfx_conformance

use xiom.io;
use xiom.convert;
use xiom.crypto.hash;
use xiom.string;
use xiom.fidelityfx;
use xiom.fidelityfx.gen_types;
use xiom.fidelityfx.gen_structs;
use xiom.fidelityfx.gen_surface;

extern "C" {
  fn ffx_gen_size_count() -> Int64;
  fn ffx_gen_size_value(i: Int64) -> Int64;
  fn ffx_gen_off_count() -> Int64;
  fn ffx_gen_off_value(i: Int64) -> Int64;
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

fn i2s(n: Int) -> Str {
  return convert.int_to_string(n);
}

// ---------------------------------------------------------------------------
// 1. Declared-surface census
// ---------------------------------------------------------------------------

fn check_surface() -> Int {
  var failed = 0;
  io.println("-- surface census --");
  let s = surface_summary();
  failed = failed + report(s.ok, "surface: 61 records, none malformed");
  failed = failed + report(s.total == 61, "surface: total records == 61 (got " + i2s(s.total) + ")");
  failed = failed + report(s.callable == 11, "surface: 11 callable records (got " + i2s(s.callable) + ")");
  failed = failed + report(s.metadata == 50, "surface: 50 metadata records (got " + i2s(s.metadata) + ")");
  failed = failed + report(s.runtime_exports == 5, "surface: 5 runtime-exported unified entry points");
  failed = failed + report(component_count() == 7, "surface: 7 components (got " + i2s(component_count()) + ")");

  var comp_ok = true;
  var ci = 0;
  while ci < component_count() {
    let cn = component_name(ci);
    let cd = component_declared(ci);
    let cc = component_callable(ci);
    let cm = component_metadata(ci);
    if cd != cc + cm { comp_ok = false; }
    if str_compare(cn, "core") == 0 && !(cd == 10 && cc == 6 && cm == 4) { comp_ok = false; }
    if str_compare(cn, "fsr2") == 0 && !(cd == 13 && cc == 0 && cm == 13) { comp_ok = false; }
    if str_compare(cn, "fsr3upscaler") == 0 && !(cd == 14 && cc == 0 && cm == 14) { comp_ok = false; }
    if str_compare(cn, "spd") == 0 && !(cd == 6 && cc == 2 && cm == 4) { comp_ok = false; }
    if str_compare(cn, "fsr1") == 0 && !(cd == 3 && cc == 3 && cm == 0) { comp_ok = false; }
    if str_compare(cn, "frameinterpolation") == 0 && !(cd == 9 && cc == 0 && cm == 9) { comp_ok = false; }
    if str_compare(cn, "opticalflow") == 0 && !(cd == 6 && cc == 0 && cm == 6) { comp_ok = false; }
    ci = ci + 1;
  }
  failed = failed + report(comp_ok, "surface: per-component declared/callable/metadata split");

  var kind_unified = 0;
  var kind_loader = 0;
  var kind_cpu = 0;
  var kind_host = 0;
  var kind_inline = 0;
  var si = 0;
  while si < surface_count() {
    let k = surface_kind(si);
    if str_compare(k, "unified") == 0 { kind_unified = kind_unified + 1; }
    elif str_compare(k, "loader") == 0 { kind_loader = kind_loader + 1; }
    elif str_compare(k, "cpu") == 0 { kind_cpu = kind_cpu + 1; }
    elif str_compare(k, "hostapi") == 0 { kind_host = kind_host + 1; }
    elif str_compare(k, "inline") == 0 { kind_inline = kind_inline + 1; }
    si = si + 1;
  }
  failed = failed + report(
    kind_unified == 5 && kind_loader == 1 && kind_cpu == 5 && kind_host == 48 && kind_inline == 2,
    "surface: kind census 5 unified / 1 loader / 5 cpu / 48 hostapi / 2 inline (got "
      + i2s(kind_unified) + "/" + i2s(kind_loader) + "/" + i2s(kind_cpu) + "/" + i2s(kind_host) + "/" + i2s(kind_inline) + ")");
  return failed;
}

// ---------------------------------------------------------------------------
// 2. Parsed constants (spot checks, upstream semantics)
// ---------------------------------------------------------------------------

fn check_constants() -> Int {
  var failed = 0;
  io.println("-- parsed constants --");
  var c_ok = true;
  if FFX_API_RETURN_OK != 0 { c_ok = false; }
  if FFX_API_RETURN_NO_PROVIDER != 4 { c_ok = false; }
  if FFX_API_RETURN_ERROR_PARAMETER != 6 { c_ok = false; }
  if FFX_API_QUERY_DESC_TYPE_GET_VERSIONS != 4 { c_ok = false; }
  if FFX_API_CREATE_CONTEXT_DESC_TYPE_UPSCALE != 65536 { c_ok = false; }
  if FFX_API_DISPATCH_DESC_TYPE_UPSCALE != 65537 { c_ok = false; }
  if FFX_API_CONFIGURE_DESC_TYPE_GLOBALDEBUG != 7 { c_ok = false; }
  if FFX_API_CREATE_CONTEXT_DESC_TYPE_FRAMEGENERATION != 131073 { c_ok = false; }
  if FFX_API_EFFECT_MASK != 16711680 { c_ok = false; }
  if FFX_FSR2_CONTEXT_SIZE != 131072 { c_ok = false; }
  failed = failed + report(c_ok, "types: desc-type/return-code/context-size constants");
  return failed;
}

// ---------------------------------------------------------------------------
// 3. ABI conformance against the compiler (vendored headers, C++20)
// ---------------------------------------------------------------------------

fn check_abi() -> Int {
  var failed = 0;
  io.println("-- ABI conformance --");
  let sn = gen_size_count();
  let cn = unsafe { ffx_gen_size_count() as Int };
  var size_bad = 0;
  var s_i = 0;
  while s_i < sn {
    if gen_size_value(s_i) != (unsafe { ffx_gen_size_value(s_i as Int64) } as Int) { size_bad = size_bad + 1; }
    s_i = s_i + 1;
  }
  failed = failed + report(cn == sn, "abi: probe struct count matches (gen " + i2s(sn) + " == compiler " + i2s(cn) + ")");
  failed = failed + report(size_bad == 0, "abi: all " + i2s(sn) + " struct sizes match compiler sizeof (" + i2s(size_bad) + " mismatches)");

  let on = gen_off_count();
  let con = unsafe { ffx_gen_off_count() as Int };
  var off_bad = 0;
  var o_i = 0;
  while o_i < on {
    if gen_off_value(o_i) != (unsafe { ffx_gen_off_value(o_i as Int64) } as Int) { off_bad = off_bad + 1; }
    o_i = o_i + 1;
  }
  failed = failed + report(con == on, "abi: probe field count matches (gen " + i2s(on) + " == compiler " + i2s(con) + ")");
  failed = failed + report(off_bad == 0, "abi: all " + i2s(on) + " field offsets match compiler offsetof (" + i2s(off_bad) + " mismatches)");
  return failed;
}

// ---------------------------------------------------------------------------
// 4. Owned-buffer descriptor builders
// ---------------------------------------------------------------------------

fn check_descriptors() -> Int {
  var failed = 0;
  io.println("-- descriptor builders (owned buffers) --");
  let cd = desc_upscale_create(1, 2560, 1440, 3840, 2160);
  var d_ok = cd.len() == FFX_SIZEOF_ffxCreateContextDescUpscale;
  if FFX_SIZEOF_ffxCreateContextDescUpscale != 48 { d_ok = false; }
  if desc_get_u64(&cd, 0) != FFX_API_CREATE_CONTEXT_DESC_TYPE_UPSCALE { d_ok = false; }
  if desc_get_u64(&cd, 8) != 0 { d_ok = false; }
  if desc_get_u32(&cd, FFX_OFFSET_ffxCreateContextDescUpscale_flags) != 1 { d_ok = false; }
  if desc_get_u32(&cd, FFX_OFFSET_ffxCreateContextDescUpscale_maxRenderSize) != 2560 { d_ok = false; }
  if desc_get_u32(&cd, FFX_OFFSET_ffxCreateContextDescUpscale_maxRenderSize + 4) != 1440 { d_ok = false; }
  if desc_get_u32(&cd, FFX_OFFSET_ffxCreateContextDescUpscale_maxUpscaleSize) != 3840 { d_ok = false; }
  if desc_get_u32(&cd, FFX_OFFSET_ffxCreateContextDescUpscale_maxUpscaleSize + 4) != 2160 { d_ok = false; }
  failed = failed + report(d_ok, "desc: ffxCreateContextDescUpscale built in owned buffer (48 bytes, byte-exact read-back)");

  let dd = desc_upscale_dispatch(1280, 720, 1920, 1080, 0.5, -0.25, 1.0, 1.0, 0.2, 16.5, true);
  var dd_ok = dd.len() == FFX_SIZEOF_ffxDispatchDescUpscale;
  if desc_get_u64(&dd, 0) != FFX_API_DISPATCH_DESC_TYPE_UPSCALE { dd_ok = false; }
  if desc_get_u32(&dd, FFX_OFFSET_ffxDispatchDescUpscale_renderSize) != 1280 { dd_ok = false; }
  if desc_get_u32(&dd, FFX_OFFSET_ffxDispatchDescUpscale_renderSize + 4) != 720 { dd_ok = false; }
  if desc_get_u32(&dd, FFX_OFFSET_ffxDispatchDescUpscale_upscaleSize) != 1920 { dd_ok = false; }
  if desc_get_u32(&dd, FFX_OFFSET_ffxDispatchDescUpscale_upscaleSize + 4) != 1080 { dd_ok = false; }
  if desc_get_u32(&dd, FFX_OFFSET_ffxDispatchDescUpscale_jitterOffset) != 0x3F000000 { dd_ok = false; }
  if desc_get_u32(&dd, FFX_OFFSET_ffxDispatchDescUpscale_jitterOffset + 4) != 0xBE800000 { dd_ok = false; }
  if desc_get_u32(&dd, FFX_OFFSET_ffxDispatchDescUpscale_motionVectorScale) != 0x3F800000 { dd_ok = false; }
  if desc_get_u32(&dd, FFX_OFFSET_ffxDispatchDescUpscale_sharpness) != 0x3E4CCCCD { dd_ok = false; }
  if desc_get_u32(&dd, FFX_OFFSET_ffxDispatchDescUpscale_frameTimeDelta) != 0x41840000 { dd_ok = false; }
  if desc_get_u32(&dd, FFX_OFFSET_ffxDispatchDescUpscale_reset) != 1 { dd_ok = false; }
  failed = failed + report(dd_ok, "desc: ffxDispatchDescUpscale scalar fields upload + read-back (jitter/mv-scale/sharpness/frame-time/reset)");
  return failed;
}

// ---------------------------------------------------------------------------
// 5. FSR1 EASU/RCAS + SPD CPU constant helpers (golden from the pin)
// ---------------------------------------------------------------------------

fn check_helpers() -> Int {
  var failed = 0;
  io.println("-- cpu constant/config helpers --");

  var easu = owned_bytes(64);
  let e1 = fsr1_easu_constants(&easu, 2560.0, 1440.0, 2560.0, 1440.0, 3840.0, 2160.0);
  var e_ok = e1.ok;
  if desc_get_u32(&easu, 0) != 0x3F2AAAAB { e_ok = false; }
  if desc_get_u32(&easu, 4) != 0x3F2AAAAA { e_ok = false; }
  if desc_get_u32(&easu, 8) != 0xBE2AAAAA { e_ok = false; }
  if desc_get_u32(&easu, 12) != 0xBE2AAAAC { e_ok = false; }
  if desc_get_u32(&easu, 16) != 0x39CCCCCD { e_ok = false; }
  if desc_get_u32(&easu, 32) != 0xB9CCCCCD { e_ok = false; }
  if desc_get_u32(&easu, 48) != 0x00000000 { e_ok = false; }
  if desc_get_u32(&easu, 52) != 0x3B360B61 { e_ok = false; }
  failed = failed + report(e_ok, "fsr1: EASU constants 2560x1440 -> 3840x2160 match pinned-header golden");

  var easu2 = owned_bytes(64);
  let e2 = fsr1_easu_constants_offset(&easu2, 2560.0, 1440.0, 3840.0, 2160.0, 3840.0, 2160.0, 128.0, 64.0);
  var e2_ok = e2.ok;
  if desc_get_u32(&easu2, 0) != 0x3F2AAAAB { e2_ok = false; }
  if desc_get_u32(&easu2, 8) != 0x42FFAAAB { e2_ok = false; }
  if desc_get_u32(&easu2, 12) != 0x427F5555 { e2_ok = false; }
  failed = failed + report(e2_ok, "fsr1: EASU constants with dynamic-resolution offset match golden");

  var rcas0 = owned_bytes(16);
  let r0 = fsr1_rcas_constants(&rcas0, 0.0);
  var r_ok = r0.ok;
  if desc_get_u32(&rcas0, 0) != 0x3F800000 { r_ok = false; }
  if desc_get_u32(&rcas0, 4) != 0x3C003C00 { r_ok = false; }
  if desc_get_u32(&rcas0, 8) != 0x00000000 { r_ok = false; }
  if desc_get_u32(&rcas0, 12) != 0x00000000 { r_ok = false; }
  var rcas2 = owned_bytes(16);
  let r2 = fsr1_rcas_constants(&rcas2, 2.0);
  if !r2.ok { r_ok = false; }
  if desc_get_u32(&rcas2, 0) != 0x3E800000 { r_ok = false; }
  if desc_get_u32(&rcas2, 4) != 0x34003400 { r_ok = false; }
  failed = failed + report(r_ok, "fsr1: RCAS constants sharpness 0.0 and 2.0 match golden");

  var spd = owned_bytes(24);
  let p1 = spd_setup(&spd, 0, 0, 2560, 1440, -1);
  var p_ok = p1.ok;
  if desc_get_u32(&spd, 0) != 40 { p_ok = false; }
  if desc_get_u32(&spd, 4) != 23 { p_ok = false; }
  if desc_get_u32(&spd, 8) != 0 { p_ok = false; }
  if desc_get_u32(&spd, 12) != 0 { p_ok = false; }
  if desc_get_u32(&spd, 16) != 920 { p_ok = false; }
  if desc_get_u32(&spd, 20) != 11 { p_ok = false; }
  failed = failed + report(p_ok, "spd: ffxSpdSetup 2560x1440 -> dtg(40,23) wgo(0,0) nwm(920,11)");

  let p2 = spd_setup(&spd, 128, 64, 2560, 1440, -1);
  var p2_ok = p2.ok;
  if desc_get_u32(&spd, 0) != 40 { p2_ok = false; }
  if desc_get_u32(&spd, 8) != 2 { p2_ok = false; }
  if desc_get_u32(&spd, 12) != 1 { p2_ok = false; }
  failed = failed + report(p2_ok, "spd: ffxSpdSetup with (left,top) offset -> wgo(2,1)");

  let p3 = spd_setup(&spd, 0, 0, 2560, 1440, 4);
  var p3_ok = p3.ok;
  if desc_get_u32(&spd, 16) != 920 { p3_ok = false; }
  if desc_get_u32(&spd, 20) != 4 { p3_ok = false; }
  failed = failed + report(p3_ok, "spd: ffxSpdSetup explicit mips=4 propagates");

  var bad = owned_bytes(64);
  let be = fsr1_easu_constants(&bad, 0.0, 1440.0, 2560.0, 1440.0, 3840.0, 2160.0);
  failed = failed + report(!be.ok && be.code == FFX_BRIDGE_RANGE, "fsr1: zero viewport -> typed OUT_OF_RANGE (" + i2s(be.code) + ")");
  var bad_rcas = owned_bytes(16);
  let br = fsr1_rcas_constants(&bad_rcas, 3.0);
  failed = failed + report(!br.ok && br.code == FFX_BRIDGE_RANGE, "fsr1: sharpness out of documented range -> typed OUT_OF_RANGE (" + i2s(br.code) + ")");
  var bad_spd = owned_bytes(24);
  let bs = spd_setup(&bad_spd, 0, 0, 0, 1440, -1);
  failed = failed + report(!bs.ok && bs.code == FFX_BRIDGE_RANGE, "spd: zero width -> typed OUT_OF_RANGE (" + i2s(bs.code) + ")");
  return failed;
}

// ---------------------------------------------------------------------------
// 6. Vendored compiled shader blobs: fetch + hashes
// ---------------------------------------------------------------------------

fn blob_expected_name(b: Int) -> Str {
  if b == 0 { return FFX_BLOB_0_NAME; }
  if b == 1 { return FFX_BLOB_1_NAME; }
  if b == 2 { return FFX_BLOB_2_NAME; }
  if b == 3 { return FFX_BLOB_3_NAME; }
  if b == 4 { return FFX_BLOB_4_NAME; }
  if b == 5 { return FFX_BLOB_5_NAME; }
  return "";
}

fn blob_expected_kind(b: Int) -> Str {
  if b == 0 { return FFX_BLOB_0_KIND; }
  if b == 1 { return FFX_BLOB_1_KIND; }
  if b == 2 { return FFX_BLOB_2_KIND; }
  if b == 3 { return FFX_BLOB_3_KIND; }
  if b == 4 { return FFX_BLOB_4_KIND; }
  if b == 5 { return FFX_BLOB_5_KIND; }
  return "";
}

fn blob_expected_size(b: Int) -> Int {
  if b == 0 { return FFX_BLOB_0_SIZE; }
  if b == 1 { return FFX_BLOB_1_SIZE; }
  if b == 2 { return FFX_BLOB_2_SIZE; }
  if b == 3 { return FFX_BLOB_3_SIZE; }
  if b == 4 { return FFX_BLOB_4_SIZE; }
  if b == 5 { return FFX_BLOB_5_SIZE; }
  return 0;
}

fn blob_expected_sha(b: Int) -> Str {
  if b == 0 { return FFX_BLOB_0_SHA256; }
  if b == 1 { return FFX_BLOB_1_SHA256; }
  if b == 2 { return FFX_BLOB_2_SHA256; }
  if b == 3 { return FFX_BLOB_3_SHA256; }
  if b == 4 { return FFX_BLOB_4_SHA256; }
  if b == 5 { return FFX_BLOB_5_SHA256; }
  return "";
}

fn check_blobs() -> Int {
  var failed = 0;
  io.println("-- vendored compiled shader blobs --");
  failed = failed + report(ffx_blob_count() == 6, "blobs: 6 vendored compiled blob headers (got " + i2s(ffx_blob_count()) + ")");

  var blob_ok = true;
  var b = 0;
  while b < ffx_blob_count() {
    if str_compare(ffx_blob_name(b), blob_expected_name(b)) != 0 { blob_ok = false; }
    if str_compare(ffx_blob_kind(b), blob_expected_kind(b)) != 0 { blob_ok = false; }
    let sz = ffx_blob_size(b);
    if sz != blob_expected_size(b) { blob_ok = false; }
    var payload = owned_bytes(sz);
    let rc = ffx_blob_read(b, &payload);
    if rc != sz { blob_ok = false; }
    let h = hash.crypto_hash_sha256_hex(&payload);
    if str_compare(h, blob_expected_sha(b)) != 0 { blob_ok = false; }
    b = b + 1;
  }
  failed = failed + report(blob_ok, "blobs: names/kinds/sizes + SHA256 payload hashes all match the pinned payload registry");

  var small = owned_bytes(16);
  let small_rc = ffx_blob_read(0, &small);
  failed = failed + report(small_rc == FFX_BRIDGE_RANGE, "blobs: undersized slot -> typed OUT_OF_RANGE (" + i2s(small_rc) + ")");
  var full = owned_bytes(4096);
  let idx_rc = ffx_blob_read(99, &full);
  failed = failed + report(idx_rc == FFX_BRIDGE_ARG, "blobs: bad index -> typed BAD_ARGUMENT (" + i2s(idx_rc) + ")");
  return failed;
}

// ---------------------------------------------------------------------------
// 7. Version probes + loader helper size
// ---------------------------------------------------------------------------

fn check_versions() -> Int {
  var failed = 0;
  io.println("-- version probes --");
  failed = failed + report(ffx_sdk_version() == 131840, "version: FX SDK 2.3.0 packed 0x020300 (got " + i2s(ffx_sdk_version()) + ")");
  var v_ok = true;
  if ffx_component_version(0) != ((FFX_FSR2_VERSION_MAJOR << 16) | (FFX_FSR2_VERSION_MINOR << 8) | FFX_FSR2_VERSION_PATCH) { v_ok = false; }
  if ffx_component_version(1) != ((FFX_FSR3UPSCALER_VERSION_MAJOR << 16) | (FFX_FSR3UPSCALER_VERSION_MINOR << 8) | FFX_FSR3UPSCALER_VERSION_PATCH) { v_ok = false; }
  if ffx_component_version(2) != ((FFX_FRAMEINTERPOLATION_VERSION_MAJOR << 16) | (FFX_FRAMEINTERPOLATION_VERSION_MINOR << 8) | FFX_FRAMEINTERPOLATION_VERSION_PATCH) { v_ok = false; }
  if ffx_component_version(4) != FFX_UPSCALER_VERSION { v_ok = false; }
  if ffx_component_version(5) != FFX_FRAMEGENERATION_VERSION { v_ok = false; }
  if ffx_component_version(99) != -1 { v_ok = false; }
  failed = failed + report(v_ok, "version: component probes (fsr2 2.3.4 / fsr3upscaler 3.1.5 / fi 3.1.6 / upscale-api 4.1.1 / fg-api 4.0.1)");
  failed = failed + report(ffx_functions_size() == 40, "version: ffxFunctions table is 5 pointers (40 bytes, got " + i2s(ffx_functions_size()) + ")");
  return failed;
}

// ---------------------------------------------------------------------------
// 8. CPU-side staging lifecycle (app-owned context blobs)
// ---------------------------------------------------------------------------

fn check_staging() -> Int {
  var failed = 0;
  io.println("-- staging lifecycle --");
  var fsr2_ctx = owned_bytes(FFX_SIZEOF_FfxFsr2Context);
  var fsr3_ctx = owned_bytes(FFX_SIZEOF_FfxFsr3UpscalerContext);
  var fi_ctx = owned_bytes(FFX_SIZEOF_FfxFrameInterpolationContext);
  var of_ctx = owned_bytes(FFX_SIZEOF_FfxOpticalflowContext);
  var spd_ctx = owned_bytes(FFX_SIZEOF_FfxSpdContext);
  var ctx_ok = true;
  if fsr2_ctx.len() != 524288 { ctx_ok = false; }
  if fsr3_ctx.len() != FFX_SIZEOF_FfxFsr3UpscalerContext { ctx_ok = false; }
  if fi_ctx.len() != FFX_SIZEOF_FfxFrameInterpolationContext { ctx_ok = false; }
  if of_ctx.len() != FFX_SIZEOF_FfxOpticalflowContext { ctx_ok = false; }
  if spd_ctx.len() != 37200 { ctx_ok = false; }
  if (fsr2_ctx[0] as Int) != 0 { ctx_ok = false; }
  if (fsr2_ctx[524287] as Int) != 0 { ctx_ok = false; }
  if (spd_ctx[37199] as Int) != 0 { ctx_ok = false; }
  failed = failed + report(ctx_ok, "lifecycle: five app-owned context staging buffers sized + zeroed from the pin constants");
  var rel = owned_bytes(8);
  failed = failed + report(rel.len() == 8, "lifecycle: staging scratch allocation/release");
  return failed;
}

// ---------------------------------------------------------------------------
// 9. Runtime: present-path checks when an effect DLL is on PATH,
//    typed SKIP otherwise (CI without the SDK stays green).
// ---------------------------------------------------------------------------

fn check_runtime() -> Int {
  var failed = 0;
  io.println("-- runtime (effect DLL present?) --");
  let load = ffx_engine_load();
  if load.is_ok {
    let eng: FfxEngine = load.value;
    failed = failed + report(eng.fns_mask == 31, "runtime: engine load resolved five unified entry points (" + eng.soname + ")");

    let cfg = ffx_configure_global_debug(&eng, 3);
    // signed effect modules accept the global-debug configure headless (code 0);
    // the 2.3.0 loader DLL answers with its typed UNKNOWN_DESCTYPE (2) instead.
    failed = failed + report(cfg.ok || cfg.code == FFX_API_RETURN_ERROR_UNKNOWN_DESCTYPE,
      "runtime: ffxConfigure(GLOBALDEBUG) -> typed code " + i2s(cfg.code) + " on " + eng.soname);

    var fns40 = owned_bytes(40);
    let mask = ffx_load_functions(&fns40, eng.handle);
    failed = failed + report(mask == 31, "runtime: vendored ffxLoadFunctions binder filled all five pointers (mask " + i2s(mask) + ")");

    let bogus = desc_new(16);
    desc_set_header(&bogus, 0xDEADBEEF);
    let cre = ffx_create_context(&eng, &bogus);
    // typed: NO_PROVIDER(4) on effect DLLs / UNKNOWN_DESCTYPE(2) on the loader
    failed = failed + report(!cre.ok && cre.class == FFX_CLASS_API_ERROR
        && (cre.code == FFX_API_RETURN_NO_PROVIDER || cre.code == FFX_API_RETURN_ERROR_UNKNOWN_DESCTYPE),
      "runtime: unknown descriptor type -> typed code " + i2s(cre.code) + " class " + i2s(cre.class));

    let up = desc_upscale_create(0, 1280, 720, 1920, 1080);
    let cre2 = ffx_create_context(&eng, &up);
    // typed: ERROR(1) from a provider rejecting a device-less create, or
    // NO_PROVIDER(4) when the module carries no upscale provider at all
    failed = failed + report(!cre2.ok && cre2.class == FFX_CLASS_NO_DEVICE && cre2.handle == 0
        && (cre2.code == FFX_API_RETURN_ERROR || cre2.code == FFX_API_RETURN_NO_PROVIDER),
      "runtime: upscale create without a device -> typed NO_DEVICE (code " + i2s(cre2.code) + ")");

    let vers = ffx_query_versions(&eng, FFX_API_CREATE_CONTEXT_DESC_TYPE_UPSCALE, 0);
    if vers.ok && vers.count >= 1 {
      failed = failed + report(vers.first_name.len() > 0,
        "runtime: versions(UPSCALE, no device) -> " + i2s(vers.count) + " provider(s), first '" + vers.first_name + "'");
    } else {
      failed = failed + report(vers.ok,
        "runtime: versions(UPSCALE, no device) -> typed empty (count " + i2s(vers.count) + ", code " + i2s(vers.code) + ")");
    }

    let hr = host_api_resolve_report(&eng);
    failed = failed + report(hr.attempted == 50, "runtime: host-surface resolve sweep attempts all 50 records");
    failed = failed + report(hr.resolved == 0 && hr.absent == 50,
      "runtime: signed provider binaries export unified API only -- 50/50 host records typed ABSENT (resolved " + i2s(hr.resolved) + ")");

    let cl = ffx_engine_close(&eng);
    failed = failed + report(cl.is_ok, "runtime: engine closed");
  } else {
    failed = failed + report(load.error.kind == FFX_CLASS_ABSENT,
      "runtime: SKIP -- no effect module on PATH (" + load.error.message + ")");
  }

  let badm = ffx_engine_load_named("xiom-definitely-absent-ffx-module.dll");
  failed = failed + report(!badm.is_ok && badm.error.kind == FFX_CLASS_ABSENT,
    "runtime: bogus soname -> typed ABSENT classification");
  return failed;
}

fn main() -> Int {
  var failed = 0;
  failed = failed + check_surface();
  failed = failed + check_constants();
  failed = failed + check_abi();
  failed = failed + check_descriptors();
  failed = failed + check_helpers();
  failed = failed + check_blobs();
  failed = failed + check_versions();
  failed = failed + check_staging();
  failed = failed + check_runtime();

  if failed == 0 {
    io.println("xiom.fidelityfx: all tests passed");
  } else {
    io.println("xiom.fidelityfx: tests failed (" + i2s(failed) + ")");
  }
  return failed;
}
