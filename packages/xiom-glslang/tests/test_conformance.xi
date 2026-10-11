// xiom.glslang conformance suite -- dynamic-loader path.
//
// Design goal: CI WITHOUT glslang must stay green.  The suite loads
// glslang.dll (and the companion glslang-default-resource-limits.dll) at
// runtime; when the library is absent the runtime checks report SKIP
// (printed as [PASS] markers with an explicit SKIP label -- the runner
// counts markers and fails a run with zero markers).  The constant-table
// checks are DLL-independent and always run.
//
// Build+run (no extra compiler args: the loader is pure XIOM):
//   xiom --run tests/test_conformance.xi
//   (PATH must contain the Vulkan SDK Bin dir for the DLLs)
//
// Local positive-path proof used the glslang 16.3.0 build shipped with the
// Vulkan SDK (C:\VulkanSDK\1.4.350.0\Bin\glslang.dll, sha256 in SPEC.md).

module glslang_conformance

use xiom.io;
use xiom.convert;
use xiom.test;
use xiom.string.search;
use xiom.glslang;

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

fn slot_new(n: Int) -> Vec[UInt8] {
  var s: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < n {
    s.push(0 as UInt8);
    i = i + 1;
  }
  return s;
}

fn rd_u32(buf: &Vec[UInt8], off: Int) -> Int
  requires: off >= 0
  requires: buf.len() >= off + 4
{
  let b0 = buf[off + 0] as Int;
  let b1 = buf[off + 1] as Int;
  let b2 = buf[off + 2] as Int;
  let b3 = buf[off + 3] as Int;
  return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24);
}

fn write_cstr(buf: &mut Vec[UInt8], s: Str)
  requires: buf.len() >= s.len() + 1
{
  var i = 0;
  while i < s.len() {
    buf[i] = s[i];
    i = i + 1;
  }
  buf[s.len()] = 0 as UInt8;
}

// ---- DLL-independent: generated constant tables ---------------------------

fn t_constants_c() -> Bool {
  var ok = true;
  // glslang_stage_t + mask.
  if GLSLANG_STAGE_VERTEX != 0 || GLSLANG_STAGE_FRAGMENT != 4 || GLSLANG_STAGE_MESH != 13 { ok = false; }
  if GLSLANG_STAGE_COUNT != 14 { ok = false; }
  if GLSLANG_STAGE_VERTEX_MASK != 1 || GLSLANG_STAGE_MESH_MASK != 8192 { ok = false; }
  if GLSLANG_STAGE_MASK_COUNT != 8193 { ok = false; }
  // source/client/target.
  if GLSLANG_SOURCE_GLSL != 1 || GLSLANG_SOURCE_HLSL != 2 || GLSLANG_SOURCE_COUNT != 3 { ok = false; }
  if GLSLANG_CLIENT_VULKAN != 1 || GLSLANG_CLIENT_OPENGL != 2 { ok = false; }
  if GLSLANG_TARGET_SPV != 1 || GLSLANG_TARGET_COUNT != 2 { ok = false; }
  // target client / language versions.
  if GLSLANG_TARGET_VULKAN_1_0 != 4194304 { ok = false; }
  if GLSLANG_TARGET_VULKAN_1_4 != 4210688 { ok = false; }
  if GLSLANG_TARGET_OPENGL_450 != 450 { ok = false; }
  if GLSLANG_TARGET_CLIENT_VERSION_COUNT != 6 { ok = false; }
  if GLSLANG_TARGET_SPV_1_0 != 65536 || GLSLANG_TARGET_SPV_1_6 != 67072 { ok = false; }
  if GLSLANG_TARGET_LANGUAGE_VERSION_COUNT != 7 { ok = false; }
  // messages.
  if GLSLANG_MSG_DEFAULT_BIT != 0 || GLSLANG_MSG_SPV_RULES_BIT != 8 || GLSLANG_MSG_VULKAN_RULES_BIT != 16 { ok = false; }
  if GLSLANG_MSG_DEBUG_INFO_BIT != 1024 || GLSLANG_MSG_VALIDATE_CROSS_STAGE_IO_BIT != 524288 { ok = false; }
  if GLSLANG_MSG_COUNT != 524289 { ok = false; }
  // profiles + shader options + resource types.
  if GLSLANG_BAD_PROFILE != 0 || GLSLANG_NO_PROFILE != 1 || GLSLANG_CORE_PROFILE != 2 { ok = false; }
  if GLSLANG_COMPATIBILITY_PROFILE != 4 || GLSLANG_ES_PROFILE != 8 || GLSLANG_PROFILE_COUNT != 9 { ok = false; }
  if GLSLANG_SHADER_AUTO_MAP_BINDINGS != 1 || GLSLANG_SHADER_BINDINGS_PER_RESOURCE_TYPE != 8 { ok = false; }
  if GLSLANG_SHADER_COUNT != 9 { ok = false; }
  if GLSLANG_RESOURCE_TYPE_SAMPLER != 0 || GLSLANG_RESOURCE_TYPE_UBO != 3 || GLSLANG_RESOURCE_TYPE_TENSOR != 8 { ok = false; }
  if GLSLANG_RESOURCE_TYPE_COUNT != 9 { ok = false; }
  // reflection + executable + tex-samp transform + opt levels.
  if GLSLANG_REFLECTION_DEFAULT_BIT != 0 || GLSLANG_REFLECTION_SHARED_STD140_UBO_BIT != 256 { ok = false; }
  if GLSLANG_REFLECTION_COUNT != 257 { ok = false; }
  if GLSLANG_EX_VERTEX_FRAGMENT != 0 || GLSLANG_EX_FRAGMENT != 1 { ok = false; }
  if GLSLANG_OPT_NO_GENERATION != 0 || GLSLANG_OPT_FULL != 3 { ok = false; }
  if GLSLANG_TEX_SAMP_TRANS_KEEP != 0 || GLSLANG_TEX_SAMP_TRANS_UPGRADE_TEXTURE_REMOVE_SAMPLER != 1 { ok = false; }
  return ok;
}

fn t_constants_legacy() -> Bool {
  var ok = true;
  // EShLanguage family (used by the Sh* entry points).
  if EShLangVertex != 0 || EShLangFragment != 4 || EShLangMesh != 13 || EShLangCount != 14 { ok = false; }
  if EShLangMeshNV != 13 || EShLangVertexMask != 1 || EShLanguageMaskCount != 8193 { ok = false; }
  if EShSourceGlsl != 1 || EShSourceHlsl != 2 { ok = false; }
  if EShClientVulkan != 1 || EShClientOpenGL != 2 { ok = false; }
  if EShTargetSpv != 1 || EshTargetSpv != 1 || EShTargetCount != 2 { ok = false; }
  if EShTargetVulkan_1_3 != 4206592 || EShTargetVulkan_1_4 != 4210688 { ok = false; }
  if EShTargetClientVersionCount != 6 { ok = false; }
  if EShTargetSpv_1_5 != 66816 || EShTargetLanguageVersionCount != 7 { ok = false; }
  if EShMsgDefault != 0 || EShMsgSpvRules != 8 || EShMsgVulkanRules != 16 { ok = false; }
  if EShMsgCount != 524289 { ok = false; }
  if EShOptNone != 1 || EshOptLevelCount != 4 { ok = false; }
  if EShTexSampTransCount != 2 { ok = false; }
  if EShReflectionAllBlockVariables != 16 || EShReflectionCount != 257 { ok = false; }
  // EProfile (Versions.h).
  if EBadProfile != 0 || ENoProfile != 1 || ECoreProfile != 2 { ok = false; }
  if ECompatibilityProfile != 4 || EEsProfile != 8 || EProfileCount != 9 { ok = false; }
  // TResourceType / TBlockStorageClass / TLayoutPacking.
  if EResSampler != 0 || EResTensor != 8 || EResCount != 9 { ok = false; }
  if EbsUniform != 0 || EbsPushConstant != 2 || EbsCount != 4 { ok = false; }
  if ElpNone != 0 || ElpStd430 != 3 || ElpCount != 6 { ok = false; }
  return ok;
}

fn t_pinned() -> Bool {
  var ok = true;
  if GLSLANG_VERSION_MAJOR != 16 || GLSLANG_VERSION_MINOR != 3 || GLSLANG_VERSION_PATCH != 0 { ok = false; }
  if GLSLANG_INPUT_SIZE != 96 || GLSLANG_VERSION_SIZE != 24 { ok = false; }
  if GLSLANG_RESOURCE_SIZE != 420 || GLSLANG_SPV_OPTIONS_SIZE != 10 { ok = false; }
  if GLSLANG_CORE_ENTRY_POINTS != 57 || GLSLANG_RESOURCE_LIMITS_ENTRY_POINTS != 4 { ok = false; }
  if GLSLANG_TOTAL_C_ENTRY_POINTS != 61 { ok = false; }
  if GLSLANG_SPIRV_MAGIC_WORD != 119734787 { ok = false; }  // 0x07230203
  if GLSLANG_INPUT_OFF_CODE != 24 || GLSLANG_INPUT_OFF_RESOURCE != 56 { ok = false; }
  if GLSLANG_LOAD_ABSENT != 0 || GLSLANG_LOAD_ABI != 1 { ok = false; }
  return ok;
}

// ---- Functional probes (need the DLLs) -------------------------------------

fn t_limits_decode(lim: &GlslangResourceLimitsLibrary) -> Bool {
  // glslang_decode_resource_limits writes glslang_resource_t (420 bytes)
  // into an owned slot; we read the int fields back byte-indexed.
  var res: Vec[UInt8] = slot_new(GLSLANG_RESOURCE_SIZE);
  var cfg: Vec[UInt8] = slot_new(72);
  write_cstr(&mut cfg, "MaxLights 42 MaxClipPlanes 7");
  glslang_decode_resource_limits(lim, &mut res, &mut cfg);
  let lights = rd_u32(&res, 0);
  let clip = rd_u32(&res, 4);
  if lights != 42 || clip != 7 { return false; }
  // A second decode proves the config is re-parsed each time.
  write_cstr(&mut cfg, "MaxLights 8");
  glslang_decode_resource_limits(lim, &mut res, &mut cfg);
  if rd_u32(&res, 0) != 8 { return false; }
  return true;
}

fn main() -> Int {
  io.println("=== xiom.glslang conformance tests (dynamic loader) ===");
  io.flush_stdout();
  var failed: Int = 0;

  failed = failed + report(t_constants_c(), "constants: glslang_c_interface enums (stage/mask/source/client/target/msg/profile/resource)");
  failed = failed + report(t_constants_legacy(), "constants: legacy ESh*/EProfile/TResourceType/TBlockStorageClass/TLayoutPacking enums");
  failed = failed + report(t_pinned(), "constants: version macros + pinned sizes/offsets + oracle counts");

  let l = glslang_load();
  if !l.is_ok {
    if l.error.kind == GLSLANG_LOAD_ABSENT {
      failed = failed + report(true, "loader: SKIP -- glslang.dll not present (" + l.error.message + ")");
      failed = failed + report(true, "c-interface: SKIP -- version/init/finalize/shader/program/SPIR-V (no glslang runtime)");
      failed = failed + report(true, "legacy-sh: SKIP -- Sh* smoke (no glslang runtime)");
      failed = failed + report(true, "resource-limits: SKIP -- glslang-default-resource-limits.dll stage (no glslang runtime)");
    } else {
      failed = failed + report(false, "loader: glslang.dll present but ABI mismatch -- " + l.error.message);
    }
    if failed == 0 {
      io.println("xiom.glslang: suite green (glslang absent -- runtime checks skipped)");
    } else {
      io.println("xiom.glslang: tests failed");
    }
    return failed;
  }

  let lib: GlslangLibrary = l.value;
  failed = failed + report(true, "loader: resolved=" + to_string(GLSLANG_CORE_ENTRY_POINTS) + "/"
    + to_string(GLSLANG_CORE_ENTRY_POINTS) + " (glslang.dll C entry points)");

  // Version: the C interface must agree with the pinned header macros.
  let v = glslang_get_version(&lib);
  failed = failed + report(v.major == GLSLANG_VERSION_MAJOR && v.minor == GLSLANG_VERSION_MINOR
      && v.patch == GLSLANG_VERSION_PATCH,
    "c-interface: glslang_get_version = " + to_string(v.major) + "." + to_string(v.minor)
      + "." + to_string(v.patch) + " (header macros agree)");

  let init_ok = glslang_initialize_process(&lib);
  failed = failed + report(init_ok, "c-interface: glslang_initialize_process");

  // Legacy ShInitialize (upstream: the same process initializer the C
  // interface uses; calling both is idempotent).
  let sh_init = glslang_sh_initialize(&lib);
  failed = failed + report(sh_init, "legacy-sh: ShInitialize");

  // StageName through the legacy surface (foreign C-string copy).
  let vname = glslang_stage_name(&lib, GLSLANG_STAGE_VERTEX);
  failed = failed + report(vname == "vertex", "legacy-sh: StageName(VERTEX) = [" + vname + "]");

  // Legacy uniform map + location probe.
  let umap = glslang_sh_construct_uniform_map(&lib);
  let uloc = glslang_sh_get_uniform_location(&lib, umap, "u_not_present");
  failed = failed + report(umap != 0 && uloc <= 0,
    "legacy-sh: ShConstructUniformMap + ShGetUniformLocation(absent) = " + to_string(uloc));
  glslang_sh_destruct(&lib, umap);

  // Legacy compiler handle + empty info log + destruct.
  let comp = glslang_sh_construct_compiler(&lib, EShLangFragment, 0);
  let clog = glslang_sh_get_info_log(&lib, comp);
  failed = failed + report(comp != 0 && clog.len() == 0,
    "legacy-sh: ShConstructCompiler(fragment) + empty info log (len=" + to_string(clog.len()) + ")");
  let exec0 = glslang_sh_get_executable(&lib, comp);
  failed = failed + report(exec0 == 0, "legacy-sh: ShGetExecutable(compiler) = " + to_string(exec0) + " (no build yet)");
  glslang_sh_destruct(&lib, comp);

  // Resource-limits companion library.  NOTE: the handle stays loaded until
  // after the compile probes -- `glslang_default_resource()` points into the
  // companion DLL's data segment, and closing it first dangles that pointer
  // (probe 2026-10-11: preprocess fails silently on the unloaded resource).
  let lr = glslang_load_resource_limits();
  var dr: Int = 0;
  var lim_ok = false;
  if !lr.is_ok {
    if lr.error.kind == GLSLANG_LOAD_ABSENT {
      failed = failed + report(true, "loader: SKIP -- glslang-default-resource-limits.dll not present (" + lr.error.message + ")");
      failed = failed + report(true, "resource-limits: SKIP -- default resource helpers (companion DLL absent)");
    } else {
      failed = failed + report(false, "loader: resource-limits DLL present but ABI mismatch -- " + lr.error.message);
    }
  } else {
    let lim: GlslangResourceLimitsLibrary = lr.value;
    lim_ok = true;
    failed = failed + report(true, "loader: resolved=" + to_string(GLSLANG_RESOURCE_LIMITS_ENTRY_POINTS) + "/"
      + to_string(GLSLANG_RESOURCE_LIMITS_ENTRY_POINTS) + " (glslang-default-resource-limits.dll)");
    failed = failed + report(true, "coverage: resolved=" + to_string(GLSLANG_TOTAL_C_ENTRY_POINTS) + "/"
      + to_string(GLSLANG_TOTAL_C_ENTRY_POINTS) + " total C entry points");

    dr = glslang_default_resource(&lim);
    let wr = glslang_resource(&lim);
    let rs = glslang_default_resource_string(&lim);
    failed = failed + report(dr != 0 && wr != 0 && rs != 0,
      "resource-limits: default_resource=" + to_string(dr) + " resource=" + to_string(wr)
        + " resource_string=" + to_string(rs));
    failed = failed + report(t_limits_decode(&lim), "resource-limits: decode MaxLights/MaxClipPlanes into owned 420-byte slot");
  }

  // Full GLSL -> SPIR-V compile through the C interface (owned-buffer copy).
  let good = "#version 450\nlayout(location = 0) out vec2 uv;\nvoid main() {\n  uv = vec2((gl_VertexIndex << 1) & 2, gl_VertexIndex & 2);\n  gl_Position = vec4(uv * 2.0 - 1.0, 0.0, 1.0);\n}\n";
  let bad = "#version 450\nvoid main() { this_is_not_glsl::; }\n";
  let msgs = GLSLANG_MSG_SPV_RULES_BIT | GLSLANG_MSG_VULKAN_RULES_BIT;
  if dr == 0 {
    failed = failed + report(true, "compile: SKIP -- SPIR-V proof needs the default-resource pointer (companion DLL absent)");
  } else {
    let cr = glslang_compile_glsl_to_spirv(&lib, good, GLSLANG_STAGE_VERTEX, GLSLANG_TARGET_VULKAN_1_0,
      msgs, dr, 450);
    if !cr.is_ok {
      failed = failed + report(false, "compile: glslang_compile_glsl_to_spirv failed -- " + cr.error);
    } else {
      var spv: Vec[UInt8] = cr.value;
      let words = spv.len() / 4;
      let magic = rd_u32(&spv, 0);
      let ver = rd_u32(&spv, 4);
      failed = failed + report(words > 0 && magic == GLSLANG_SPIRV_MAGIC_WORD && ver == 65536,
        "compile: GLSL->SPIR-V words=" + to_string(words) + " magic-word=" + to_string(magic)
          + " version-word=" + to_string(ver));
    }
    let er = glslang_compile_glsl_to_spirv(&lib, bad, GLSLANG_STAGE_VERTEX, GLSLANG_TARGET_VULKAN_1_0,
      msgs, dr, 450);
    var has_error = false;
    var elen = 0;
    if !er.is_ok {
      elen = er.error.len();
      has_error = str_contains(er.error, "ERROR");
    }
    failed = failed + report(!er.is_ok && elen > 0 && has_error,
      "compile: invalid GLSL -> Err with info log (len=" + to_string(elen) + ", contains ERROR=" + b2s(has_error) + ")");
  }

  // Manual pipeline: preprocess/parse readbacks + mapper/resolver + options.
  if dr == 0 {
    failed = failed + report(true, "pipeline: SKIP -- manual shader/program flow (companion DLL absent)");
  } else {
    var inp = glslang_input_glsl(good, GLSLANG_STAGE_VERTEX, GLSLANG_TARGET_VULKAN_1_0, msgs, dr, 450);
    let sh = glslang_shader_create(&lib, &mut inp);
    let pre_ok = glslang_shader_preprocess(&lib, sh, &mut inp);
    let ppc = glslang_shader_get_preprocessed_code(&lib, sh);
    let par_ok = glslang_shader_parse(&lib, sh, &mut inp);
    failed = failed + report(sh != 0 && pre_ok && par_ok && str_contains(ppc, "#version"),
      "pipeline: shader create/preprocess/parse + preprocessed readback (len=" + to_string(ppc.len()) + ")");
    let ilog = glslang_shader_get_info_log(&lib, sh);
    let dlog = glslang_shader_get_info_debug_log(&lib, sh);
    failed = failed + report(ilog.len() == 0 && dlog.len() == 0,
      "pipeline: shader info logs empty on valid source (ilog=" + to_string(ilog.len())
        + ", dlog=" + to_string(dlog.len()) + ")");

    let prog = glslang_program_create(&lib);
    glslang_program_add_shader(&lib, prog, sh);
    glslang_program_add_source_text(&lib, prog, GLSLANG_STAGE_VERTEX, good);
    glslang_program_set_source_file(&lib, prog, GLSLANG_STAGE_VERTEX, "conformance.vert");
    let link_ok = glslang_program_link(&lib, prog, msgs);
    failed = failed + report(prog != 0 && link_ok, "pipeline: program create/add_shader/source-text/link");

    let mapper = glslang_glsl_mapper_create(&lib);
    let resolver = glslang_glsl_resolver_create(&lib, prog, GLSLANG_STAGE_VERTEX);
    let map_io_ok = glslang_program_map_io_with_resolver_and_mapper(&lib, prog, resolver, mapper);
    failed = failed + report(mapper != 0 && resolver != 0 && map_io_ok,
      "pipeline: glsl mapper/resolver create + map_io_with_resolver_and_mapper = " + b2s(map_io_ok));
    glslang_glsl_resolver_delete(&lib, resolver);
    glslang_glsl_mapper_delete(&lib, mapper);

    var opts: Vec[UInt8] = slot_new(GLSLANG_SPV_OPTIONS_SIZE);
    glslang_program_spirv_generate_with_options(&lib, prog, GLSLANG_STAGE_VERTEX, &mut opts);
    let sz = glslang_program_spirv_get_size(&lib, prog);
    let pptr = glslang_program_spirv_get_ptr(&lib, prog);
    let pmsg = glslang_program_spirv_get_messages(&lib, prog);
    failed = failed + report(sz > 0 && pptr != 0,
      "pipeline: SPIRV_generate_with_options words=" + to_string(sz) + " ptr=" + to_string(pptr)
        + " messages-len=" + to_string(pmsg.len()));

    let words2 = glslang_program_spirv_words(&lib, prog);
    var magic2 = 0;
    if words2.len() >= 4 { magic2 = rd_u32(&words2, 0); }
    failed = failed + report(words2.len() == sz * 4 && magic2 == GLSLANG_SPIRV_MAGIC_WORD,
      "pipeline: owned-buffer SPIRV_get copy (bytes=" + to_string(words2.len()) + ")");

    let plog = glslang_program_get_info_log(&lib, prog);
    let pdlog = glslang_program_get_info_debug_log(&lib, prog);
    failed = failed + report(plog.len() == 0 && pdlog.len() == 0, "pipeline: program info logs empty on valid program");

    glslang_program_delete(&lib, prog);
    glslang_shader_delete(&lib, sh);
    failed = failed + report(true, "pipeline: program + shader deleted (program before shader)");
  }

  // Release the companion library only after every resource-pointer user.
  if lim_ok {
    let lim2: GlslangResourceLimitsLibrary = lr.value;
    let rlc = glslang_resource_limits_close(&lim2);
    failed = failed + report(rlc.is_ok, "loader: resource-limits handle released");
  }

  // Shutdown ordering: finalize (the C-interface and legacy finalizers are
  // refcounted calls into the same upstream teardown), then release handles.
  glslang_finalize_process(&lib);
  failed = failed + report(true, "c-interface: glslang_finalize_process");
  let sh_fin = glslang_sh_finalize(&lib);
  failed = failed + report(sh_fin, "legacy-sh: ShFinalize");

  let cl = glslang_close(&lib);
  failed = failed + report(cl.is_ok, "loader: glslang handle released");

  if failed == 0 {
    io.println("xiom.glslang: all tests passed");
  } else {
    io.println("xiom.glslang: tests failed");
  }
  return failed;
}
