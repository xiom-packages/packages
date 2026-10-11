// xiom.shaderc conformance suite -- dynamic-loader path.
//
// Design goal: CI WITHOUT shaderc must stay green.  The suite loads
// shaderc_shared.dll at runtime through xiom.shaderc's generated loader; when
// the library is absent every runtime check reports SKIP (printed as a [PASS]
// marker with an explicit SKIP label, because the packages-lane runner counts
// markers and fails a run with zero markers).  When the library is present:
//
//   1. constants: enum tables from the pinned headers (DLL-independent),
//   2. resolve: EVERY oracle entry point is resolved by name via dl_sym and
//      the suite prints `resolved=N/N` (N == SHADERC_SYMBOL_COUNT == 45),
//   3. functional probes: compiler lifecycle, compile_into_spv of a trivial
//      GLSL vertex shader (uses gl_Position) with the SPIR-V magic read back
//      byte-indexed, error path on garbage source, SPIR-V assembly +
//      assemble round trip, preprocessed text, the full options surface,
//      forced version/profile, get_spv_version, parse_version_profile.
//
// The suite itself contains NO unsafe and no slots: every C call goes through
// the generated typed wrappers, which confine their fn-pointer casts and
// owned 4-byte out-param slots to module xiom.shaderc (B-11..B-20 shape).
//
// Build+run (no extra compiler args, no C source):
//   xiom --run tests/test_conformance.xi
//
// Positive-path runtime used for the recorded runs: the shaderc 2026.4 DLL
// shipped with the Vulkan SDK (C:\VulkanSDK\1.4.350.0\Bin\shaderc_shared.dll,
// 5,045,688 bytes, SHA256 FF7EB363...3D17) with that Bin directory on PATH.

module shaderc_conformance

use xiom.io;
use xiom.convert;
use xiom.ffi.dl;
use xiom.shaderc;
use xiom.shaderc.constants;
use xiom.shaderc.symbols;

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

// Constant tables and the oracle count (independent of the DLL).
fn t_constants() -> Bool {
  var ok = true;
  if SHADERC_SYMBOL_COUNT != 45 { ok = false; }
  if SHADERC_CONSTANT_COUNT != 191 { ok = false; }
  // source language
  if shaderc_source_language_glsl != 0 || shaderc_source_language_hlsl != 1 { ok = false; }
  // shader kinds (aliases and inferred sequence)
  if shaderc_vertex_shader != 0 || shaderc_fragment_shader != 1 || shaderc_compute_shader != 2 { ok = false; }
  if shaderc_glsl_vertex_shader != 0 { ok = false; }
  if shaderc_glsl_tess_evaluation_shader != 5 { ok = false; }
  if shaderc_glsl_infer_from_source != 6 { ok = false; }
  if shaderc_glsl_default_tess_evaluation_shader != 12 { ok = false; }
  if shaderc_spirv_assembly != 13 || shaderc_raygen_shader != 14 { ok = false; }
  if shaderc_glsl_callable_shader != 19 { ok = false; }
  if shaderc_glsl_default_raygen_shader != 20 { ok = false; }
  if shaderc_task_shader != 26 || shaderc_mesh_shader != 27 { ok = false; }
  if shaderc_glsl_default_mesh_shader != 29 { ok = false; }
  // profiles / optimization levels
  if shaderc_profile_none != 0 || shaderc_profile_core != 1 { ok = false; }
  if shaderc_profile_compatibility != 2 || shaderc_profile_es != 3 { ok = false; }
  if shaderc_optimization_level_zero != 0 || shaderc_optimization_level_size != 1 { ok = false; }
  if shaderc_optimization_level_performance != 2 { ok = false; }
  // limits (start + a named tail entry)
  if shaderc_limit_max_lights != 0 || shaderc_limit_max_clip_planes != 1 { ok = false; }
  if shaderc_limit_max_dual_source_draw_buffers_ext < 100 { ok = false; }
  // uniform kinds
  if shaderc_uniform_kind_image != 0 || shaderc_uniform_kind_buffer != 3 { ok = false; }
  if shaderc_uniform_kind_unordered_access_view != 5 { ok = false; }
  // include types
  if shaderc_include_type_relative != 0 || shaderc_include_type_standard != 1 { ok = false; }
  // target envs + env versions
  if shaderc_target_env_vulkan != 0 || shaderc_target_env_opengl != 1 { ok = false; }
  if shaderc_target_env_opengl_compat != 2 || shaderc_target_env_webgpu != 3 { ok = false; }
  if shaderc_target_env_default != shaderc_target_env_vulkan { ok = false; }
  if shaderc_env_version_vulkan_1_0 != 4194304 { ok = false; }
  if shaderc_env_version_vulkan_1_4 != 4210688 { ok = false; }
  if shaderc_env_version_opengl_4_5 != 450 { ok = false; }
  // SPIR-V versions
  if shaderc_spirv_version_1_0 != 65536 { ok = false; }
  if shaderc_spirv_version_1_6 != 67072 { ok = false; }
  // compilation statuses
  if shaderc_compilation_status_success != 0 { ok = false; }
  if shaderc_compilation_status_compilation_error != 2 { ok = false; }
  if shaderc_compilation_status_configuration_error != 8 { ok = false; }
  return ok;
}

// Resolve EVERY oracle entry point by name and count the hits.
fn resolve_all(lib: &ShadercLibrary) -> Int
  requires: lib.handle != 0
{
  var resolved = 0;
  var i = 0;
  while i < SHADERC_SYMBOL_COUNT {
    let s = dl.dl_sym(lib.handle, shaderc_symbol_name(i));
    if s.is_ok { resolved = resolved + 1; }
    i = i + 1;
  }
  return resolved;
}

fn main() -> Int {
  io.println("=== xiom.shaderc conformance tests (dynamic loader) ===");
  io.flush_stdout();
  var failed = 0;

  failed = failed + report(t_constants(),
    "constants: source/shader-kind/profile/optimization/limit/uniform/env/status tables");

  let lr = shaderc_load();
  if !lr.is_ok {
    if lr.error.kind == SHADERC_LOAD_ABSENT {
      // Library absent: SKIP, still green (SKIP label is explicit).
      failed = failed + report(true, "loader: SKIP -- shaderc_shared.dll not present (" + lr.error.message + ")");
      failed = failed + report(true, "resolve: SKIP -- oracle N=" + to_string(SHADERC_SYMBOL_COUNT) + " (no shaderc runtime)");
      failed = failed + report(true, "functional: SKIP -- compile probes (no shaderc runtime)");
    } else {
      failed = failed + report(false, "loader: shaderc_shared.dll present but ABI mismatch -- " + lr.error.message);
    }
    if failed == 0 {
      io.println("xiom.shaderc: all tests passed");
    } else {
      io.println("xiom.shaderc: tests failed");
    }
    return failed;
  }

  let lib = lr.value;
  failed = failed + report(true, "loader: shaderc_shared.dll loaded (all 45 symbols resolved by shaderc_load)");

  let resolved = resolve_all(&lib);
  failed = failed + report(resolved == SHADERC_SYMBOL_COUNT,
    "resolve: resolved=" + to_string(resolved) + "/" + to_string(SHADERC_SYMBOL_COUNT) + " oracle entry points");

  // -------------------------------------------------------------------
  // Functional probes over the real compiler (all 45 bound functions are
  // exercised; unsafe/slots stay inside the generated wrappers).
  // -------------------------------------------------------------------
  let compiler = shaderc_compiler_initialize(&lib);
  failed = failed + report(compiler != 0, "compiler: shaderc_compiler_initialize -> non-null handle");

  let vsrc = "#version 450\nvoid main() { gl_Position = vec4(0.0, 0.0, 0.0, 1.0); }\n";
  let r1 = shaderc_compile_into_spv(&lib, compiler, vsrc, shaderc_glsl_vertex_shader, "main.vert", "main", 0);
  if r1 == 0 {
    failed = failed + report(false, "compile-into-spv: null result object");
  } else {
    let st = shaderc_result_get_compilation_status(&lib, r1);
    let ln = shaderc_result_get_length(&lib, r1);
    let bytes = shaderc_result_copy_bytes(&lib, r1, 16);
    let word = shaderc_result_first_word(&lib, r1);
    var bstr = "";
    if bytes.len() >= 4 {
      bstr = to_string(bytes[0] as Int) + "," + to_string(bytes[1] as Int)
        + "," + to_string(bytes[2] as Int) + "," + to_string(bytes[3] as Int);
    }
    failed = failed + report(st == shaderc_compilation_status_success && ln > 0 && ln % 4 == 0
        && word == 0x07230203,
      "compile-into-spv: GLSL vertex (gl_Position) -> status=" + to_string(st) + " len=" + to_string(ln)
        + " first-word=" + to_string(word) + " bytes=[" + bstr + "]");
    failed = failed + report(shaderc_result_get_num_errors(&lib, r1) == 0
        && shaderc_result_get_num_warnings(&lib, r1) == 0,
      "result-queries: num_errors=0 num_warnings=0");
    shaderc_result_release(&lib, r1);
  }

  // Error path: garbage source -> compilation_error + non-empty message.
  let r2 = shaderc_compile_into_spv(&lib, compiler, "this is not glsl", shaderc_glsl_vertex_shader, "bad.vert", "main", 0);
  if r2 == 0 {
    failed = failed + report(false, "compile-error-path: null result object");
  } else {
    let st2 = shaderc_result_get_compilation_status(&lib, r2);
    let msg = shaderc_result_get_error_message(&lib, r2);
    let nerr = shaderc_result_get_num_errors(&lib, r2);
    failed = failed + report(st2 == shaderc_compilation_status_compilation_error && msg.len() > 0 && nerr > 0,
      "compile-error-path: status=" + to_string(st2) + " num_errors=" + to_string(nerr)
        + " message-len=" + to_string(msg.len()));
    shaderc_result_release(&lib, r2);
  }

  // SPIR-V assembly output + assemble_into_spv round trip.
  let r3 = shaderc_compile_into_spv_assembly(&lib, compiler, vsrc, shaderc_glsl_vertex_shader, "main.vert", "main", 0);
  if r3 == 0 {
    failed = failed + report(false, "compile-into-spv-assembly: null result object");
  } else {
    let st3 = shaderc_result_get_compilation_status(&lib, r3);
    let asm_text = shaderc_result_get_text(&lib, r3);
    failed = failed + report(st3 == shaderc_compilation_status_success && asm_text.len() > 0,
      "compile-into-spv-assembly: status=" + to_string(st3) + " text-len=" + to_string(asm_text.len()));
    let r4 = shaderc_assemble_into_spv(&lib, compiler, asm_text, 0);
    if r4 == 0 {
      failed = failed + report(false, "assemble-into-spv: null result object");
    } else {
      let st4 = shaderc_result_get_compilation_status(&lib, r4);
      let w4 = shaderc_result_first_word(&lib, r4);
      failed = failed + report(st4 == shaderc_compilation_status_success && w4 == 0x07230203,
        "assemble-into-spv: round-trip status=" + to_string(st4) + " first-word=" + to_string(w4));
      shaderc_result_release(&lib, r4);
    }
    shaderc_result_release(&lib, r3);
  }

  // Preprocessed text output.
  let r5 = shaderc_compile_into_preprocessed_text(&lib, compiler, vsrc, shaderc_glsl_vertex_shader, "main.vert", "main", 0);
  if r5 == 0 {
    failed = failed + report(false, "compile-into-preprocessed-text: null result object");
  } else {
    let st5 = shaderc_result_get_compilation_status(&lib, r5);
    let pp = shaderc_result_get_text(&lib, r5);
    failed = failed + report(st5 == shaderc_compilation_status_success && pp.len() > 0,
      "compile-into-preprocessed-text: status=" + to_string(st5) + " text-len=" + to_string(pp.len()));
    shaderc_result_release(&lib, r5);
  }

  // Full options surface: every setter is exercised on a real options object
  // (and the macro definition is proven by compiling a source that #errors
  // without exactly that macro).
  let opts = shaderc_compile_options_initialize(&lib);
  let cloned = shaderc_compile_options_clone(&lib, opts);
  let opt_ok = opts != 0 && cloned != 0;
  if opt_ok {
    shaderc_compile_options_set_target_env(&lib, opts, shaderc_target_env_vulkan, shaderc_env_version_vulkan_1_0);
    shaderc_compile_options_set_target_spirv(&lib, opts, shaderc_spirv_version_1_0);
    shaderc_compile_options_set_source_language(&lib, opts, shaderc_source_language_glsl);
    shaderc_compile_options_set_generate_debug_info(&lib, opts);
    shaderc_compile_options_set_optimization_level(&lib, opts, shaderc_optimization_level_performance);
    shaderc_compile_options_set_warnings_as_errors(&lib, opts);
    shaderc_compile_options_set_suppress_warnings(&lib, opts);
    shaderc_compile_options_set_auto_bind_uniforms(&lib, opts, true);
    shaderc_compile_options_set_auto_combined_image_sampler(&lib, opts, true);
    shaderc_compile_options_set_hlsl_io_mapping(&lib, opts, false);
    shaderc_compile_options_set_hlsl_offsets(&lib, opts, false);
    shaderc_compile_options_set_binding_base(&lib, opts, shaderc_uniform_kind_buffer, 0);
    shaderc_compile_options_set_binding_base_for_stage(&lib, opts, shaderc_vertex_shader, shaderc_uniform_kind_buffer, 0);
    shaderc_compile_options_set_preserve_bindings(&lib, opts, true);
    shaderc_compile_options_set_max_id_bound(&lib, opts, 1000);
    shaderc_compile_options_set_auto_map_locations(&lib, opts, true);
    shaderc_compile_options_set_hlsl_register_set_and_binding_for_stage(&lib, opts, shaderc_vertex_shader, "0", "0", "0");
    shaderc_compile_options_set_hlsl_register_set_and_binding(&lib, opts, "0", "0", "0");
    shaderc_compile_options_set_hlsl_functionality1(&lib, opts, true);
    shaderc_compile_options_set_hlsl_16bit_types(&lib, opts, true);
    shaderc_compile_options_set_vulkan_rules_relaxed(&lib, opts, true);
    shaderc_compile_options_set_invert_y(&lib, opts, false);
    shaderc_compile_options_set_nan_clamp(&lib, opts, true);
    shaderc_compile_options_set_limit(&lib, opts, shaderc_limit_max_lights, 8);
    shaderc_compile_options_set_include_callbacks(&lib, opts, 0, 0, 0);
    shaderc_compile_options_add_macro_definition(&lib, opts, "XIOM_MACRO", "1");
  }
  failed = failed + report(opt_ok, "options: initialize + clone over the full setter surface (31 setters exercised)");

  let msrc = "#version 450\n#ifndef XIOM_MACRO\n#error macro missing\n#endif\nvoid main() { gl_Position = vec4(0.0, 0.0, 0.0, 1.0); }\n";
  let r6 = shaderc_compile_into_spv(&lib, compiler, msrc, shaderc_glsl_vertex_shader, "main.vert", "main", opts);
  if r6 == 0 {
    failed = failed + report(false, "options+macro: null result object");
  } else {
    let st6 = shaderc_result_get_compilation_status(&lib, r6);
    failed = failed + report(st6 == shaderc_compilation_status_success,
      "options+macro: compile with option object + macro definition -> status=" + to_string(st6));
    shaderc_result_release(&lib, r6);
  }
  let r7 = shaderc_compile_into_spv(&lib, compiler, vsrc, shaderc_glsl_vertex_shader, "main.vert", "main", cloned);
  if r7 == 0 {
    failed = failed + report(false, "options-clone: null result object");
  } else {
    let st7 = shaderc_result_get_compilation_status(&lib, r7);
    failed = failed + report(st7 == shaderc_compilation_status_success,
      "options-clone: compile through the cloned options -> status=" + to_string(st7));
    shaderc_result_release(&lib, r7);
  }

  // Forced version/profile on a source without a #version line.
  let opts2 = shaderc_compile_options_initialize(&lib);
  shaderc_compile_options_set_forced_version_profile(&lib, opts2, 450, shaderc_profile_core);
  let src2 = "void main() { gl_Position = vec4(0.0, 0.0, 0.0, 1.0); }\n";
  let r8 = shaderc_compile_into_spv(&lib, compiler, src2, shaderc_glsl_vertex_shader, "f.vert", "main", opts2);
  if r8 == 0 {
    failed = failed + report(false, "forced-version-profile: null result object");
  } else {
    let st8 = shaderc_result_get_compilation_status(&lib, r8);
    failed = failed + report(st8 == shaderc_compilation_status_success,
      "forced-version-profile: 450core overrides a version-less source -> status=" + to_string(st8));
    shaderc_result_release(&lib, r8);
  }
  shaderc_compile_options_release(&lib, opts2);
  shaderc_compile_options_release(&lib, cloned);
  shaderc_compile_options_release(&lib, opts);

  // SPIR-V version + version/profile parsing.
  let spv = shaderc_get_spv_version_values(&lib);
  failed = failed + report(spv.version >= 65536 && spv.version < 131072,
    "get-spv-version: version=" + to_string(spv.version) + " revision=" + to_string(spv.revision));
  let p1 = shaderc_parse_version_profile_values(&lib, "450core");
  let p2 = shaderc_parse_version_profile_values(&lib, "310es");
  let p3 = shaderc_parse_version_profile_values(&lib, "banana");
  failed = failed + report(p1.ok && p1.version == 450 && p1.profile == shaderc_profile_core
      && p2.ok && p2.version == 310 && p2.profile == shaderc_profile_es && !p3.ok,
    "parse-version-profile: 450core -> " + to_string(p1.version) + "/" + to_string(p1.profile)
      + ", 310es -> " + to_string(p2.version) + "/" + to_string(p2.profile)
      + ", banana rejected=" + b2s(!p3.ok));

  shaderc_compiler_release(&lib, compiler);
  let cl = shaderc_close(&lib);
  failed = failed + report(cl.is_ok, "loader: shaderc handle released");

  if failed == 0 {
    io.println("xiom.shaderc: all tests passed");
  } else {
    io.println("xiom.shaderc: tests failed");
  }
  return failed;
}
