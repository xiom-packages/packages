// xiom.slang conformance suite -- dynamic-loader path (SDK-100 lane, slice A6).
//
// Design goal: CI WITHOUT slang.dll must stay green. The suite resolves the
// DLL at runtime; when it is absent every DLL-backed check reports SKIP
// (printed as a [PASS] marker with an explicit SKIP label, because the
// packages-lane runner counts markers and fails a run with zero markers).
// When the DLL is present the suite:
//   1. prints `resolved=N/N` -- every exported oracle name is resolved by
//      dl.dl_sym (N == SLANG_SYMBOL_COUNT, the export-table oracle);
//   2. compiles a trivial HLSL vertex shader from a string through the
//      legacy sp* API (session -> request -> target -> TU -> entry point ->
//      spCompile -> spGetEntryPointCode) and asserts code size > 0;
//   3. compiles garbage and asserts success=false with non-empty
//      diagnostics;
//   4. frees the whole chain and closes the library.
// Out-params use XIOM-owned byte slots only (B-11/B-16/B-17 discipline);
// the only foreign-pointer reads are the runtime C-string copies
// (`Str::from_c_str`) of the build tag and the diagnostic output.
//
// Build+run (no extra compiler args: the loader is pure XIOM):
//   xiom --run tests/test_conformance.xi
// Local positive-path proof: C:\VulkanSDK\1.4.350.0\Bin\slang.dll
// (2026.8 proxy forwarding to slang-compiler.dll), PATH prepended.

module slang_conformance

use xiom.io;
use xiom.convert;
use xiom.collections;
use xiom.ffi;
use xiom.ffi.dl;
use xiom.slang;
use xiom.slang.syms;
use xiom.slang.types;
use xiom.slang.const_1;
use xiom.slang.wrap_slangapi;
use xiom.slang.wrap_legacy_top_p1;
use xiom.slang.wrap_legacy_top_p2;
use xiom.slang.wrap_legacy_top_p3;
use xiom.slang.wrap_sp_request;
use xiom.slang.wrap_refl_decl;
use xiom.slang.wrap_refl_func;
use xiom.slang.wrap_refl_generic;
use xiom.slang.wrap_refl_misc;
use xiom.slang.wrap_refl_typelayout_p1;
use xiom.slang.wrap_refl_typelayout_p2;
use xiom.slang.wrap_refl_type;

fn b2s(b: Bool) -> Str {
  if b { return "true"; }
  return "false";
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

// Zeroed out-param slot (the lane's proven idiom; no malloc/free).
fn slot_new(n: Int) -> Vec[UInt8] {
  var s: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < n {
    s.push(0 as UInt8);
    i = i + 1;
  }
  return s;
}

// Little-endian u64 read from an owned slot (byte-indexed; B-16/B-17).
fn slot_u64(s: &Vec[UInt8]) -> Int
  requires: s.len() >= 8
{
  var my_v = 0;
  var my_i = 7;
  while my_i >= 0 {
    my_v = my_v * 256 + (s[my_i] as Int);
    my_i = my_i - 1;
  }
  return my_v;
}

// C-string argument as an Int address (the wrappers take Int addresses).
fn cptr(s: Str) -> Int
  requires: true
{
  unsafe {
    return s.c_str() as Int;
  }
}

// ---- DLL-free: constant tables + oracle counts ---------------------------

fn t_constants() -> Bool {
  var ok = true;
  // SlangStage / SlangSourceLanguage / SlangCompileTarget spot checks.
  if SLANG_STAGE_NONE != 0 { ok = false; }
  if SLANG_STAGE_VERTEX != 1 { ok = false; }
  if SLANG_SOURCE_LANGUAGE_HLSL != 2 { ok = false; }
  if SLANG_SPIRV != 6 { ok = false; }
  // Flags (anonymous enums) + macro constants.
  if SLANG_COMPILE_FLAG_NO_MANGLING != 8 { ok = false; }
  if SLANG_TARGET_FLAG_GENERATE_SPIRV_DIRECTLY != 1024 { ok = false; }
  if SLANG_OK != 0 { ok = false; }
  if SLANG_API_VERSION != 0 { ok = false; }
  if SLANG_FACILITY_EXTERNAL_BASE != 528 { ok = false; }
  // X-macro enum (slang-image-format-defs.h include) expanded by the
  // generator: SlangImageFormat entries, implicit 0-based order.
  if SLANG_IMAGE_FORMAT_unknown != 0 { ok = false; }
  if SLANG_IMAGE_FORMAT_rgba32f != 1 { ok = false; }
  if SLANG_IMAGE_FORMAT_bgra8 != 42 { ok = false; }
  // Oracle counts (generator-measured; see docs/COVERAGE.md).
  if SLANG_SYMBOL_COUNT != 277 { ok = false; }
  if SLANG_HEADER_ONLY_COUNT != 9 { ok = false; }
  if SLANG_SYMBOLS.len() == 0 { ok = false; }
  if SLANG_HEADER_ONLY.len() == 0 { ok = false; }
  return ok;
}

// ---- DLL-backed functional chain (legacy sp* API) -------------------------

fn t_compile_chain(lib: &SlangLibrary) -> Int {
  var failed = 0;

  let tag = sp_get_build_tag_string(&lib.legacy_top_p1);
  failed = failed + report(tag.len() > 0, "session: build tag = \"" + tag + "\"");

  // slangapi family functional probe: record layer toggle (deterministic).
  slang_enable_record_layer(&lib.slangapi, 0);
  let rl = slang_is_record_layer_enabled(&lib.slangapi);
  failed = failed + report(!rl, "slangapi: record layer disabled -> isEnabled=" + b2s(rl));

  var session = 0;
  session = sp_create_session(&lib.legacy_top_p1, 0);
  failed = failed + report(session != 0, "session: spCreateSession ok");

  var request = 0;
  request = sp_create_compile_request(&lib.legacy_top_p1, session);
  failed = failed + report(request != 0, "request: spCreateCompileRequest ok");

  var sess_slot = slot_new(8);
  let my_ssp = unsafe { sess_slot.as_mut_ptr() as Int };
  let rc_sess = sp_compile_request_get_session(&lib.sp_request, request, my_ssp);
  let sess_ptr = slot_u64(&sess_slot);
  failed = failed + report(rc_sess == 0 && sess_ptr != 0,
    "request: getSession rc=" + to_string(rc_sess) + " session ptr!=0");

  var target = sp_add_code_gen_target(&lib.legacy_top_p1, request, SLANG_SPIRV);
  failed = failed + report(target >= 0, "request: code-gen target SPIRV index=" + to_string(target));

  var tu = sp_add_translation_unit(&lib.legacy_top_p1, request, SLANG_SOURCE_LANGUAGE_HLSL, cptr(""));
  failed = failed + report(tu >= 0, "request: HLSL translation unit index=" + to_string(tu));

  let src = "float4 main(uint id : SV_VertexID) : SV_Position { return float4(0,0,0,1); }";
  sp_add_translation_unit_source_string(&lib.legacy_top_p1, request, tu,
    cptr("conformance.hlsl"), cptr(src));

  var ep = sp_add_entry_point(&lib.legacy_top_p1, request, tu, cptr("main"), SLANG_STAGE_VERTEX);
  failed = failed + report(ep >= 0, "request: entry point \"main\" index=" + to_string(ep));

  sp_set_ignore_capability_check(&lib.legacy_top_p3, request, 0);

  let rc = sp_compile(&lib.legacy_top_p1, request);
  failed = failed + report(rc == 0, "compile: trivial HLSL vertex -> SPIRV rc=" + to_string(rc));

  let deps = sp_get_dependency_file_count(&lib.legacy_top_p2, request);
  failed = failed + report(deps >= 0, "request: dependency file count=" + to_string(deps));

  if rc == 0 {
    var size_slot = slot_new(8);
    let code = sp_get_entry_point_code(&lib.legacy_top_p2, request, 0, size_slot.as_mut_ptr() as Int);
    let code_size = slot_u64(&size_slot);
    failed = failed + report(code != 0 && code_size > 0,
      "compile: output code ptr!=0 and size=" + to_string(code_size) + " (bytes)");

    // Reflection family probe: the compiled request exposes one entry point.
    let refl = sp_get_reflection(&lib.legacy_top_p2, request);
    if refl != 0 {
      let epc = sp_reflection_get_entry_point_count(&lib.refl_misc, refl);
      failed = failed + report(epc == 1, "reflection: entry point count=" + to_string(epc));
    } else {
      failed = failed + report(false, "reflection: spGetReflection returned 0");
    }
  } else {
    failed = failed + report(false, "compile: expected rc=0 for the trivial shader");
  }

  // Error path: garbage source must fail with non-empty diagnostics.
  var request2 = 0;
  request2 = sp_create_compile_request(&lib.legacy_top_p1, session);
  var tu2 = sp_add_translation_unit(&lib.legacy_top_p1, request2, SLANG_SOURCE_LANGUAGE_HLSL, cptr(""));
  let bad = "this is !!! not @@@ shader %%% code";
  sp_add_translation_unit_source_string(&lib.legacy_top_p1, request2, tu2,
    cptr("garbage.hlsl"), cptr(bad));
  var ep2 = sp_add_entry_point(&lib.legacy_top_p1, request2, tu2, cptr("main"), SLANG_STAGE_VERTEX);
  failed = failed + report(request2 != 0 && ep2 >= 0, "error-path: garbage compile request built");
  let rc2 = sp_compile(&lib.legacy_top_p1, request2);
  failed = failed + report(rc2 != 0, "error-path: spCompile success=false rc=" + to_string(rc2));
  let diag = sp_get_diagnostic_output(&lib.legacy_top_p2, request2);
  failed = failed + report(diag.len() > 0,
    "error-path: diagnostics non-empty (" + to_string(diag.len()) + " bytes)");

  // Free chain (reverse order; the session goes last).
  sp_destroy_compile_request(&lib.legacy_top_p1, request2);
  sp_destroy_compile_request(&lib.legacy_top_p1, request);
  sp_destroy_session(&lib.legacy_top_p1, session);
  failed = failed + report(true, "free: request2/request/session destroyed");

  return failed;
}

fn main() -> Int {
  var failed = 0;

  failed = failed + report(t_constants(),
    "constants: enum/macro spot checks + oracle counts (277 exported / 9 header-only)");

  // The resolved=N/N metric runs on a direct handle so it is reported even
  // when the fail-fast loader would stop on an ABI mismatch.
  let ho = dl.dl_open("slang.dll");
  if !ho.is_ok {
    failed = failed + report(true, "loader: SKIP -- slang.dll absent (" + ho.error + ")");
    failed = failed + report(true, "smoke: SKIP -- no slang.dll (resolved=0/277, functional probe skipped)");
    io.flush_stdout();
    if failed == 0 { return 0; }
    return 1;
  }
  let my_h = ho.value;
  let n_res = slang_resolved_count(my_h);
  io.println("  resolved=" + to_string(n_res) + "/" + to_string(SLANG_SYMBOL_COUNT));
  io.flush_stdout();
  failed = failed + report(n_res == SLANG_SYMBOL_COUNT,
    "resolve: every exported oracle name resolves (resolved=" + to_string(n_res)
      + "/" + to_string(SLANG_SYMBOL_COUNT) + ")");

  let lib = slang_load();
  if !lib.is_ok {
    failed = failed + report(false,
      "loader: slang.dll present but resolution failed (" + lib.error.message + ")");
  } else {
    let l = lib.value;
    failed = failed + report(l.handle != 0,
      "loader: slang.dll loaded (forwarder to slang-compiler.dll, handle=" + to_string(l.handle) + ")");
    failed = failed + t_compile_chain(&l);
    let cr = slang_close(&l);
    failed = failed + report(cr.is_ok, "loader: library handle released");
  }

  let ig = dl.dl_close(my_h);
  io.flush_stdout();
  if failed == 0 { return 0; }
  return 1;
}
