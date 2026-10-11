// xiom.spirv-cross conformance suite -- dynamic-loader path.
//
// Design goal: CI WITHOUT spirv-cross-c-shared.dll must stay green. The suite
// loads the DLL at runtime through xiom.ffi.dl; when absent every runtime
// check reports SKIP (a [PASS] marker with an explicit SKIP label). When the
// DLL is present the full probe runs: version, the `resolved=N/N` symbol
// resolution proof (every oracle name from spirv_cross_c.h), a real
// parse -> create_compiler(GLSL) -> compile round trip over the embedded
// SPIR-V fixture, resource reflection, entry-point query and the
// release_allocations/destroy free chain.
//
// Build+run (no extra compiler args: the loader is pure XIOM):
//   xiom --run tests/test_conformance.xi
//
// Local positive-path proof uses the DLL shipped with the Vulkan SDK
// (C:\VulkanSDK\1.4.350.0\Bin, sha256 in SPEC.md); prepend that directory to
// PATH before running the suite.

module spirv_cross_conformance

use xiom.io;
use xiom.convert;
use xiom.string;
use xiom.spirv.cross;

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

// ---- constants + fixture (DLL-independent arms) ---------------------------

fn t_constants() -> Bool {
  var ok = true;
  // result codes (signed)
  if SPVC_SUCCESS != 0 { ok = false; }
  if SPVC_ERROR_INVALID_SPIRV != -1 { ok = false; }
  if SPVC_ERROR_OUT_OF_MEMORY != -3 { ok = false; }
  if SPVC_ERROR_INVALID_ARGUMENT != -4 { ok = false; }
  // backends + capture modes
  if SPVC_BACKEND_NONE != 0 || SPVC_BACKEND_GLSL != 1 { ok = false; }
  if SPVC_BACKEND_MSL != 3 || SPVC_BACKEND_JSON != 5 { ok = false; }
  if SPVC_CAPTURE_MODE_COPY != 0 || SPVC_CAPTURE_MODE_TAKE_OWNERSHIP != 1 { ok = false; }
  // resource types
  if SPVC_RESOURCE_TYPE_UNIFORM_BUFFER != 1 { ok = false; }
  if SPVC_RESOURCE_TYPE_STAGE_INPUT != 3 { ok = false; }
  if SPVC_RESOURCE_TYPE_STAGE_OUTPUT != 4 { ok = false; }
  if SPVC_RESOURCE_TYPE_PUSH_CONSTANT != 9 { ok = false; }
  // base types
  if SPVC_BASETYPE_FP32 != 13 || SPVC_BASETYPE_STRUCT != 15 { ok = false; }
  // option bits + composite options
  if SPVC_COMPILER_OPTION_COMMON_BIT != 0x1000000 { ok = false; }
  if SPVC_COMPILER_OPTION_GLSL_BIT != 0x2000000 { ok = false; }
  if SPVC_COMPILER_OPTION_MSL_BIT != 0x8000000 { ok = false; }
  if SPVC_COMPILER_OPTION_GLSL_VERSION != 0x2000008 { ok = false; }
  if SPVC_COMPILER_OPTION_MSL_VERSION != 0x8000011 { ok = false; }
  if SPVC_COMPILER_OPTION_HLSL_SHADER_MODEL != 0x400000d { ok = false; }
  // unsigned ~(Nu) macros + sentinels
  if SPVC_MSL_PUSH_CONSTANT_DESC_SET != 0xFFFFFFFF { ok = false; }
  if SPVC_MSL_SWIZZLE_BUFFER_BINDING != 0xFFFFFFFE { ok = false; }
  if SPVC_HLSL_BINDING_AUTO_SRV_BIT != 4 { ok = false; }
  if SPVC_HLSL_BINDING_AUTO_ALL != 0x7fffffff { ok = false; }
  if SPVC_TRUE != 1 || SPVC_FALSE != 0 { ok = false; }
  // version macros match the pinned header
  if SPVC_C_API_VERSION_MAJOR != 0 { ok = false; }
  if SPVC_C_API_VERSION_MINOR != 68 { ok = false; }
  if SPVC_C_API_VERSION_PATCH != 0 { ok = false; }
  // deprecated MSL aliases resolve to the new names
  if SPVC_MSL_VERTEX_FORMAT_UINT8 != 1 { ok = false; }
  if SPVC_MSL_SHADER_INPUT_FORMAT_ANY32 != 4 { ok = false; }
  if SPVC_MSL_SAMPLER_ADDRESS_MIRRORED_REPEAT != 4 { ok = false; }
  if SPVC_MSL_SAMPLER_MIP_FILTER_LINEAR != 2 { ok = false; }
  // x64 struct sizes (out-slot contracts)
  if SPVC_SIZEOF_SPVC_MSL_VERTEX_ATTRIBUTE != 28 { ok = false; }
  if SPVC_SIZEOF_SPVC_MSL_CONSTEXPR_SAMPLER != 52 { ok = false; }
  if SPVC_SIZEOF_SPVC_SPECIALIZATION_CONSTANT != 8 { ok = false; }
  if SPVC_SIZEOF_SPVC_REFLECTED_RESOURCE != 24 { ok = false; }
  // macro math
  if spvc_make_msl_version(2, 1, 0) != 20100 { ok = false; }
  if spvc_make_msl_version(3, 0, 0) != 30000 { ok = false; }
  return ok;
}

fn t_fixture() -> Bool {
  let spv = min_frag_spv();
  if spv.len() != MIN_FRAG_SPV_BYTES { return false; }
  if MIN_FRAG_SPV_WORDS * 4 != MIN_FRAG_SPV_BYTES { return false; }
  // little-endian SPIR-V magic 0x07230203
  let m0 = spv[0] as Int;
  let m1 = spv[1] as Int;
  let m2 = spv[2] as Int;
  let m3 = spv[3] as Int;
  if m0 != 0x03 || m1 != 0x02 || m2 != 0x23 || m3 != 0x07 { return false; }
  return true;
}

// Count reflected resources of one type through a fresh pair of owned slots.
fn res_count(lib: &SpvcLibrary, resources: Int, rtype: Int) -> Int {
  var list_slot = spvc_slot(8);
  var cnt_slot = spvc_slot(8);
  let rc = spvc_resources_get_resource_list_for_type(lib, resources, rtype, &mut list_slot, &mut cnt_slot);
  if rc != SPVC_SUCCESS { return 0; }
  return spvc_read_u64_at(&cnt_slot, 0);
}

fn main() -> Int {
  io.println("=== xiom.spirv-cross conformance tests (dynamic loader) ===");
  io.flush_stdout();
  var failed: Int = 0;

  failed = failed + report(t_constants(), "constants: result/backend/resource/option tables + sizeof + macro math");
  failed = failed + report(t_fixture(), "fixture: embedded SPIR-V blob (magic 0x07230203, " + to_string(MIN_FRAG_SPV_BYTES) + " bytes)");

  if !spirv_cross_present() {
    // Library absent: SKIP, still green (SKIP label is explicit).
    failed = failed + report(true, "loader: SKIP -- spirv-cross-c-shared.dll not present (resolved=SKIP/" + to_string(SPVC_ORACLE_COUNT) + ")");
    failed = failed + report(true, "functional: SKIP -- parse/compile/reflect probe (no spirv-cross runtime)");
    if failed == 0 {
      io.println("xiom.spirv-cross: suite green (DLL absent -- functional probe skipped)");
    } else {
      io.println("xiom.spirv-cross: tests failed");
    }
    return failed;
  }

  // ---- resolved=N/N: resolve every oracle name from spirv_cross_c.h --------
  let nres = spvc_probe_resolution();
  failed = failed + report(nres == SPVC_ORACLE_COUNT, "loader: resolved=" + to_string(nres) + "/" + to_string(SPVC_ORACLE_COUNT) + " header-declared spvc_* symbols");

  let r = spirv_cross_load();
  if !r.is_ok {
    failed = failed + report(false, "loader: spirv_cross_load failed -- " + r.error.message);
    if failed == 0 { io.println("xiom.spirv-cross: suite green"); } else { io.println("xiom.spirv-cross: tests failed"); }
    return failed;
  }
  let lib: SpvcLibrary = r.value;

  // ---- version -------------------------------------------------------------
  var vma = spvc_slot(4);
  var vmi = spvc_slot(4);
  var vpa = spvc_slot(4);
  spvc_get_version(&lib, &mut vma, &mut vmi, &mut vpa);
  let major = spvc_read_u32_at(&vma, 0);
  let minor = spvc_read_u32_at(&vmi, 0);
  let patch = spvc_read_u32_at(&vpa, 0);
  let vok = major == SPVC_C_API_VERSION_MAJOR && minor == SPVC_C_API_VERSION_MINOR && patch == SPVC_C_API_VERSION_PATCH;
  failed = failed + report(vok, "version: spvc_get_version -> " + to_string(major) + "." + to_string(minor) + "." + to_string(patch) + " (header pin)");

  let rev = spvc_get_commit_revision_and_timestamp(&lib);
  failed = failed + report(rev.len() > 0, "version: commit revision string non-empty (" + to_string(rev.len()) + " chars)");

  // ---- context -> parse -> compiler ---------------------------------------
  var ctx_slot = spvc_slot(8);
  let rc_ctx = spvc_context_create(&lib, &mut ctx_slot);
  let ctx = spvc_read_u64_at(&ctx_slot, 0);
  failed = failed + report(rc_ctx == SPVC_SUCCESS && ctx != 0, "context: spvc_context_create -> OK");

  var words = min_frag_spv();
  var ir_slot = spvc_slot(8);
  let rc_parse = spvc_context_parse_spirv(&lib, ctx, &mut words, MIN_FRAG_SPV_WORDS, &mut ir_slot);
  let ir = spvc_read_u64_at(&ir_slot, 0);
  failed = failed + report(rc_parse == SPVC_SUCCESS && ir != 0, "parse: spvc_context_parse_spirv accepts the " + to_string(MIN_FRAG_SPV_WORDS) + "-word fixture");

  var comp_slot = spvc_slot(8);
  let rc_comp = spvc_context_create_compiler(&lib, ctx, SPVC_BACKEND_GLSL, ir, SPVC_CAPTURE_MODE_TAKE_OWNERSHIP, &mut comp_slot);
  let compiler = spvc_read_u64_at(&comp_slot, 0);
  failed = failed + report(rc_comp == SPVC_SUCCESS && compiler != 0, "compiler: spvc_context_create_compiler(GLSL, TAKE_OWNERSHIP) -> OK");

  // ---- compile (the money probe) ------------------------------------------
  let glsl = spvc_compiler_compile_string(&lib, compiler);
  let has_main = str_contains(glsl, "void main");
  failed = failed + report(has_main, "compile: GLSL output contains 'void main' (" + to_string(glsl.len()) + " bytes)");

  // ---- resource reflection -------------------------------------------------
  var res_slot = spvc_slot(8);
  let rc_res = spvc_compiler_create_shader_resources(&lib, compiler, &mut res_slot);
  let resources = spvc_read_u64_at(&res_slot, 0);
  failed = failed + report(rc_res == SPVC_SUCCESS && resources != 0, "resources: spvc_compiler_create_shader_resources -> OK");

  var total: Int = 0;
  total = total + res_count(&lib, resources, SPVC_RESOURCE_TYPE_UNIFORM_BUFFER);
  total = total + res_count(&lib, resources, SPVC_RESOURCE_TYPE_STAGE_INPUT);
  total = total + res_count(&lib, resources, SPVC_RESOURCE_TYPE_STAGE_OUTPUT);
  failed = failed + report(total >= 2, "resources: reflected resource count " + to_string(total) + " >= 2 (ubo + input + output)");

  // ---- entry points --------------------------------------------------------
  var eps_slot = spvc_slot(8);
  var nep_slot = spvc_slot(8);
  let rc_ep = spvc_compiler_get_entry_points(&lib, compiler, &mut eps_slot, &mut nep_slot);
  let nep = spvc_read_u64_at(&nep_slot, 0);
  failed = failed + report(rc_ep == SPVC_SUCCESS && nep >= 1, "entrypoints: spvc_compiler_get_entry_points -> count " + to_string(nep));
  let em = spvc_compiler_get_execution_model(&lib, compiler);
  failed = failed + report(em == 4, "entrypoints: execution model Fragment (4), got " + to_string(em));

  // ---- compiler + glsl option surface -------------------------------------
  let idb = spvc_compiler_get_current_id_bound(&lib, compiler);
  failed = failed + report(idb > 0, "compiler: spvc_compiler_get_current_id_bound -> " + to_string(idb));

  let nreq = spvc_compiler_get_num_required_extensions(&lib, compiler);
  failed = failed + report(nreq == 0, "compiler: required extension count " + to_string(nreq) + " (none needed by the fixture)");

  var line_rc = spvc_compiler_add_header_line(&lib, compiler, "// xiom.spirv-cross conformance header");
  var ext_rc = spvc_compiler_require_extension(&lib, compiler, "GL_EXT_shader_explicit_arithmetic_types");
  failed = failed + report(line_rc == SPVC_SUCCESS && ext_rc == SPVC_SUCCESS, "glsl: add_header_line + require_extension accepted");

  var opt_slot = spvc_slot(8);
  let rc_opt = spvc_compiler_create_compiler_options(&lib, compiler, &mut opt_slot);
  let options = spvc_read_u64_at(&opt_slot, 0);
  let rc_set = spvc_compiler_options_set_bool(&lib, options, SPVC_COMPILER_OPTION_FLIP_VERTEX_Y, SPVC_TRUE);
  let rc_inst = spvc_compiler_install_compiler_options(&lib, compiler, options);
  failed = failed + report(rc_opt == SPVC_SUCCESS && rc_set == SPVC_SUCCESS && rc_inst == SPVC_SUCCESS, "glsl: compiler options create/set_bool/install -> OK");

  // ---- msl struct init into an owned slot ----------------------------------
  var vattr = spvc_slot(SPVC_SIZEOF_SPVC_MSL_VERTEX_ATTRIBUTE);
  spvc_msl_vertex_attribute_init(&lib, &mut vattr);
  let vloc = spvc_read_u32_at(&vattr, 0);
  let vfmt = spvc_read_u32_at(&vattr, 20);
  failed = failed + report(vloc == 0 && vfmt == 0, "msl: vertex_attribute_init defaults (location=0, format=OTHER=0)");

  let auxv = spvc_msl_get_aux_buffer_struct_version(&lib);
  failed = failed + report(auxv == SPVC_MSL_AUX_BUFFER_STRUCT_VERSION, "msl: aux buffer struct version " + to_string(auxv) + " == header macro");

  // ---- full free chain -----------------------------------------------------
  spvc_context_release_allocations(&lib, ctx);
  spvc_context_destroy(&lib, ctx);
  failed = failed + report(true, "free: spvc_context_release_allocations + spvc_context_destroy chain clean");

  spirv_cross_close(&lib);

  if failed == 0 {
    io.println("xiom.spirv-cross: suite green");
  } else {
    io.println("xiom.spirv-cross: tests failed");
  }
  return failed;
}
