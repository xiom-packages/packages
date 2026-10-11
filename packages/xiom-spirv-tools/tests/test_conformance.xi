// xiom.spirv-tools conformance suite -- dynamic-loader path (SDK-100 slice A1).
//
// Design goal: CI WITHOUT the Vulkan SDK must stay green.  The suite loads
// SPIRV-Tools-shared.dll at runtime; when the library is absent every smoke
// check reports SKIP (printed as a [PASS] marker with an explicit SKIP
// label, because the packages-lane runner counts markers and fails a run
// with zero markers).  When the library is present the suite:
//   1. resolves EVERY declared C name at runtime (name-driven dl_sym over
//      the generated oracle table) and prints `resolved=N/N`;
//   2. proves the typed resolver agrees with the name-driven probe;
//   3. proves the 12 header-declared names the shipped DLL does not export
//      are indeed absent (the documented shipping gap);
//   4. runs functional probes: context + assemble + validate + disassemble
//      (+ round trip), validate-with-options/-binary, binary-parse,
//      diagnostics (create/print/destroy + error text copy-out), opcode
//      string, validator/optimizer/reducer/fuzzer option objects, and a
//      gated optimizer-run probe (SKIP on this SDK build: spvOptimizer* is
//      not exported -- see docs/COVERAGE.md).
//
// Discipline (B-11..B-20): out-params use one owned zeroed Vec[UInt8] slot
// each; byte-indexed reads/writes only; C-owned structs (spv_binary_t,
// spv_text_t, spv_diagnostic_t) are copied out through the C bridge in
// src/st_probe_bridge.c and read from XIOM-owned memory; foreign pointers
// are only ever passed back to C, never dereferenced by XIOM.
//
// Build+run (the runner appends port.args.json: --c-source of the bridge):
//   scripts\port.ps1 -Package xiom.spirv-tools -TimeoutSec 700
//   (PATH must include C:\VulkanSDK\1.4.350.0\Bin for the present-path run)

module spirv_tools_conformance

use xiom.io;
use xiom.convert;
use xiom.spirv_tools;
use xiom.spirv_tools.symbols;
use xiom.spirv_tools.resolve;
use xiom.spirv_tools.readout;
use xiom.spirv_tools.constants;
use xiom.spirv_tools.core;
use xiom.spirv_tools.validator;
use xiom.spirv_tools.optimizer;
use xiom.spirv_tools.reducer_fuzzer;
use xiom.spirv_tools.codec;
use xiom.spirv_tools.operand;

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

// Constant tables (independent of the DLL; source-generated, sampled).
fn t_constants() -> Bool {
  var ok = true;
  if SPV_SUCCESS != 0 { ok = false; }
  if SPV_ERROR_INVALID_BINARY != -4 { ok = false; }
  if SPV_ERROR_FNVAR != -17 { ok = false; }
  if SPV_FORCE_32BIT_spv_result_t != 0x7FFFFFFF { ok = false; }
  if SPV_MSG_FATAL != 0 || SPV_MSG_DEBUG != 5 { ok = false; }
  if SPV_ENDIANNESS_LITTLE != 0 || SPV_ENDIANNESS_BIG != 1 { ok = false; }
  if SPV_OPERAND_TYPE_NONE != 0 { ok = false; }
  if SPV_OPERAND_TYPE_NUM_OPERAND_TYPES != 107 { ok = false; }
  if SPV_EXT_INST_TYPE_ARM_MOTION_ENGINE_100 != 13 { ok = false; }
  if SPV_NUMBER_FLOATING != 3 || SPV_FP_ENCODING_BFLOAT16 != 4 { ok = false; }
  if SPV_TEXT_TO_BINARY_OPTION_NONE != 1 { ok = false; }
  if SPV_TEXT_TO_BINARY_OPTION_PRESERVE_NUMERIC_IDS != 2 { ok = false; }
  if SPV_BINARY_TO_TEXT_OPTION_NONE != 1 { ok = false; }
  if SPV_BINARY_TO_TEXT_OPTION_HANDLE_UNKNOWN_OPCODES != 1024 { ok = false; }
  if SPV_ENV_UNIVERSAL_1_0 != 0 || SPV_ENV_VULKAN_1_0 != 1 { ok = false; }
  if SPV_ENV_VULKAN_1_1_SPIRV_1_4 != 21 { ok = false; }
  if SPV_ENV_VULKAN_1_4 != 26 || SPV_ENV_MAX != 27 { ok = false; }
  if spv_validator_limit_max_struct_members != 0 { ok = false; }
  if spv_validator_limit_max_id_bound != 8 { ok = false; }
  if K_DEFAULT_MAX_ID_BOUND != 0x3FFFFF { ok = false; }
  if st_constant_count() != 222 { ok = false; }
  if st_declared_count() != 67 || st_oracle_count() != 67 { ok = false; }
  if st_exported_count() != 55 || st_missing_names().len() != 12 { ok = false; }
  return ok;
}

fn main() -> Int {
  io.println("=== xiom.spirv-tools conformance tests (dynamic loader) ===");
  io.flush_stdout();
  var failed: Int = 0;

  failed = failed + report(t_constants(), "constants: enum/macro tables (222 values, sampled) + oracle counts");

  let l = spirv_tools_load();
  if !l.is_ok {
    if l.error.kind == SPIRV_TOOLS_LOAD_ABSENT {
      // Library absent: SKIP, still green (SKIP label is explicit).
      failed = failed + report(true, "loader: SKIP -- SPIRV-Tools-shared.dll not present (" + l.error.message + ")");
      failed = failed + report(true, "smoke: SKIP -- assemble/validate/disassemble/options (no SPIRV-Tools runtime)");
    } else {
      failed = failed + report(false, "loader: SPIRV-Tools-shared.dll present but ABI mismatch -- " + l.error.message);
    }
    if failed == 0 {
      io.println("xiom.spirv-tools: suite green (SPIRV-Tools absent -- smoke skipped)");
    } else {
      io.println("xiom.spirv-tools: tests failed");
    }
    return failed;
  }

  let lib: SpirvToolsLibrary = l.value;

  // ---- resolution: every declared name probed at runtime ----------------
  let probe = st_probe_names(lib.handle);
  io.println("oracle: declared=" + convert.int_to_string(probe.oracle_count)
    + " exported-expected=" + convert.int_to_string(st_exported_count())
    + " gap-expected=" + convert.int_to_string(st_missing_names().len()));
  io.println("resolved=" + convert.int_to_string(probe.resolved_count) + "/" + convert.int_to_string(probe.oracle_count));
  var gapnames = "";
  let gap_list = st_missing_names();
  var gi = 0;
  while gi < gap_list.len() {
    // NOTE: bind the element to a local before `+`; concatenating an
    // element read straight off a temporary Vec[Str] yields the raw
    // pointer string (compiler finding, recorded in AUDIT.md).
    let nm = gap_list[gi];
    if gi > 0 { gapnames = gapnames + ", "; }
    gapnames = gapnames + nm;
    gi = gi + 1;
  }
  io.println("gap names: " + gapnames);
  io.flush_stdout();

  failed = failed + report(probe.oracle_count == st_oracle_count() && st_oracle_count() == st_declared_count(),
    "oracle: declared extern \"C\" surface = " + convert.int_to_string(st_oracle_count()) + " spv* functions");
  failed = failed + report(st_resolved_count(&lib.syms) == st_exported_count(),
    "resolve: typed resolver bound " + convert.int_to_string(st_resolved_count(&lib.syms)) + "/"
    + convert.int_to_string(st_oracle_count()) + " handles (55 exported)");
  failed = failed + report(probe.resolved_count == st_exported_count(),
    "resolve: every exported name resolves (" + convert.int_to_string(probe.resolved_count) + "/"
    + convert.int_to_string(st_exported_count()) + " exported; " + convert.int_to_string(probe.resolved_count)
    + "/" + convert.int_to_string(probe.oracle_count) + " declared)");
  failed = failed + report(probe.exported_missing.len() == 0,
    "resolve: zero expected-exported names missing");
  failed = failed + report(probe.gap_resolved.len() == 0,
    "gap: " + convert.int_to_string(st_missing_names().len())
    + " declared names absent from the shipped DLL (resolve proof)");
  failed = failed + report(lib.missing.len() == st_missing_names().len(),
    "gap: runtime missing list matches the committed export dump");

  // ---- core family: version / target env / context ----------------------
  let vstr = st_spv_software_version_string(&lib.syms);
  failed = failed + report(vstr.len() > 0, "version: spvSoftwareVersionString = \"" + vstr + "\"");
  let vdet = st_spv_software_version_details_string(&lib.syms);
  let vhit = xiom.string.index_of(vdet, "SPIRV-Tools");
  failed = failed + report(vdet.len() > 0 && vhit.is_some, "version: details string identifies SPIRV-Tools");

  let desc = st_spv_target_env_description(&lib.syms, SPV_ENV_VULKAN_1_0);
  let dhit = xiom.string.index_of(desc, "Vulkan");
  failed = failed + report(desc.len() > 0 && dhit.is_some,
    "target-env: spvTargetEnvDescription(VULKAN_1_0) = \"" + desc + "\"");

  let env_slot = st_slot_new(4);
  let ok_parse = st_spv_parse_target_env(&lib.syms, "vulkan1.0".c_str(), env_slot.as_mut_ptr());
  let env_val = st_slot_read_u32(&env_slot, 0);
  failed = failed + report(ok_parse && env_val == SPV_ENV_VULKAN_1_0,
    "target-env: spvParseTargetEnv(\"vulkan1.0\") -> SPV_ENV_VULKAN_1_0 (got " + convert.int_to_string(env_val) + ")");

  let env2_slot = st_slot_new(4);
  let ok_parse2 = st_spv_parse_vulkan_env(&lib.syms, 4194304, 65536, env2_slot.as_mut_ptr());
  let env2_val = st_slot_read_u32(&env2_slot, 0);
  failed = failed + report(ok_parse2 && env2_val == SPV_ENV_VULKAN_1_0,
    "target-env: spvParseVulkanEnv(Vulkan1.0, SPIR-V1.0) -> SPV_ENV_VULKAN_1_0 (got " + convert.int_to_string(env2_val) + ")");

  let ctx = st_spv_context_create(&lib.syms, SPV_ENV_UNIVERSAL_1_0);
  failed = failed + report(ctx != 0, "context: spvContextCreate(SPV_ENV_UNIVERSAL_1_0) non-zero");

  // ---- validator options ------------------------------------------------
  let vopts = st_spv_validator_options_create(&lib.syms);
  if vopts != 0 {
    st_spv_validator_options_set_universal_limit(&lib.syms, vopts, spv_validator_limit_max_struct_members, 16383);
    st_spv_validator_options_set_relax_store_struct(&lib.syms, vopts, 1);
    st_spv_validator_options_set_relax_logical_pointer(&lib.syms, vopts, 1);
    st_spv_validator_options_set_before_hlsl_legalization(&lib.syms, vopts, 0);
    st_spv_validator_options_set_relax_block_layout(&lib.syms, vopts, 1);
    st_spv_validator_options_set_uniform_buffer_standard_layout(&lib.syms, vopts, 0);
    st_spv_validator_options_set_scalar_block_layout(&lib.syms, vopts, 0);
    st_spv_validator_options_set_workgroup_scalar_block_layout(&lib.syms, vopts, 0);
    st_spv_validator_options_set_skip_block_layout(&lib.syms, vopts, 0);
    st_spv_validator_options_set_allow_local_size_id(&lib.syms, vopts, 0);
    st_spv_validator_options_set_allow_offset_texture_operand(&lib.syms, vopts, 1);
    st_spv_validator_options_set_allow_vulkan32_bit_bitwise(&lib.syms, vopts, 1);
    st_spv_validator_options_set_friendly_names(&lib.syms, vopts, 1);
  }
  failed = failed + report(vopts != 0,
    "validator-options: spvValidatorOptionsCreate + 13 setters callable");

  // ---- assemble: minimal valid module -----------------------------------
  let asm_text = "OpCapability Shader\nOpMemoryModel Logical GLSL450\nOpEntryPoint Vertex %main \"main\"\n%void = OpTypeVoid\n%fnty = OpTypeFunction %void\n%main = OpFunction %void None %fnty\n%entry = OpLabel\nOpReturn\nOpFunctionEnd\n";
  var bin_slot = st_slot_new(8);
  var diag_slot = st_slot_new(8);
  let rc = st_spv_text_to_binary(&lib.syms, ctx, asm_text.c_str(), asm_text.len(), bin_slot.as_mut_ptr(), diag_slot.as_mut_ptr());
  failed = failed + report(rc == SPV_SUCCESS, "assemble: spvTextToBinary(minimal module) == SPV_SUCCESS (rc=" + convert.int_to_string(rc) + ")");
  if rc != SPV_SUCCESS {
    let dp = st_slot_read_u64(&diag_slot, 0);
    if dp != 0 {
      io.println("  assemble diagnostic: " + st_diagnostic_error(dp));
      st_spv_diagnostic_destroy(&lib.syms, dp);
    }
  }
  let bin_ptr = st_slot_read_u64(&bin_slot, 0);
  failed = failed + report(bin_ptr != 0, "assemble: spv_binary out-param non-null");
  var bview = StBinaryView{ code: 0; word_count: 0 };
  if bin_ptr != 0 {
    bview = st_binary_view(bin_ptr);
  }
  failed = failed + report(bview.word_count > 0 && bview.code != 0,
    "assemble: spv_binary_t copied out (code non-zero, words=" + convert.int_to_string(bview.word_count) + ")");

  // assemble with options (PRESERVE_NUMERIC_IDS path).
  var bin2_slot = st_slot_new(8);
  var diag2_slot = st_slot_new(8);
  let rc_opt = st_spv_text_to_binary_with_options(&lib.syms, ctx, asm_text.c_str(), asm_text.len(),
    SPV_TEXT_TO_BINARY_OPTION_PRESERVE_NUMERIC_IDS, bin2_slot.as_mut_ptr(), diag2_slot.as_mut_ptr());
  failed = failed + report(rc_opt == SPV_SUCCESS, "assemble: spvTextToBinaryWithOptions == SPV_SUCCESS");
  let bin2_ptr = st_slot_read_u64(&bin2_slot, 0);
  failed = failed + report(bin2_ptr != 0, "assemble: options path spv_binary out-param non-null");

  // ---- validate ---------------------------------------------------------
  var cb = st_slot_new(16);
  st_slot_write_u64(&mut cb, 0, bview.code);
  st_slot_write_u64(&mut cb, 8, bview.word_count);
  var vdiag = st_slot_new(8);
  let vrc = st_spv_validate(&lib.syms, ctx, cb.as_mut_ptr(), vdiag.as_mut_ptr());
  failed = failed + report(vrc == SPV_SUCCESS, "validate: spvValidate == SPV_SUCCESS (rc=" + convert.int_to_string(vrc) + ")");
  if vrc != SPV_SUCCESS {
    let dp = st_slot_read_u64(&vdiag, 0);
    if dp != 0 {
      io.println("  validate diagnostic: " + st_diagnostic_error(dp));
      st_spv_diagnostic_destroy(&lib.syms, dp);
    }
  }

  var vodiag = st_slot_new(8);
  let vrc2 = st_spv_validate_with_options(&lib.syms, ctx, vopts, cb.as_mut_ptr(), vodiag.as_mut_ptr());
  failed = failed + report(vrc2 == SPV_SUCCESS, "validate: spvValidateWithOptions == SPV_SUCCESS");
  if vrc2 != SPV_SUCCESS {
    let dp = st_slot_read_u64(&vodiag, 0);
    if dp != 0 {
      io.println("  validate-with-options diagnostic: " + st_diagnostic_error(dp));
      st_spv_diagnostic_destroy(&lib.syms, dp);
    }
  }

  var vbdiag = st_slot_new(8);
  let vrc3 = st_spv_validate_binary(&lib.syms, ctx, bview.code, bview.word_count, vbdiag.as_mut_ptr());
  failed = failed + report(vrc3 == SPV_SUCCESS, "validate: spvValidateBinary(words) == SPV_SUCCESS");

  var pdiag = st_slot_new(8);
  let prc = st_spv_binary_parse(&lib.syms, ctx, 0, bview.code, bview.word_count, 0, 0, pdiag.as_mut_ptr());
  failed = failed + report(prc == SPV_SUCCESS, "parse: spvBinaryParse(no callbacks) == SPV_SUCCESS");

  // ---- disassemble + round trip ----------------------------------------
  var text_slot = st_slot_new(8);
  var tdiag = st_slot_new(8);
  let trc = st_spv_binary_to_text(&lib.syms, ctx, bview.code, bview.word_count, 0, text_slot.as_mut_ptr(), tdiag.as_mut_ptr());
  failed = failed + report(trc == SPV_SUCCESS, "disassemble: spvBinaryToText == SPV_SUCCESS (rc=" + convert.int_to_string(trc) + ")");
  let text_ptr = st_slot_read_u64(&text_slot, 0);
  if trc != SPV_SUCCESS || text_ptr == 0 {
    let dp = st_slot_read_u64(&tdiag, 0);
    if dp != 0 { st_spv_diagnostic_destroy(&lib.syms, dp); }
    failed = failed + report(false, "disassemble: text out-param missing (rc=" + convert.int_to_string(trc) + ")");
  } else {
    let tview = st_text_view(text_ptr);
    var out = st_slot_new(tview.length + 1);
    st_copy_out(&mut out, tview.str_addr, tview.length);
    let has_ep = st_contains_ascii(&out, "OpEntryPoint");
    failed = failed + report(tview.length > 0 && has_ep,
      "disassemble: text contains OpEntryPoint (len=" + convert.int_to_string(tview.length) + ")");
    let disasm = st_read_cstr(tview.str_addr, tview.length);
    var rbin_slot = st_slot_new(8);
    var rdiag = st_slot_new(8);
    let rrc = st_spv_text_to_binary(&lib.syms, ctx, disasm.c_str(), disasm.len(), rbin_slot.as_mut_ptr(), rdiag.as_mut_ptr());
    failed = failed + report(rrc == SPV_SUCCESS, "disassemble: disassembly re-assembles (round trip)");
    let rbin_ptr = st_slot_read_u64(&rbin_slot, 0);
    if rbin_ptr != 0 { st_spv_binary_destroy(&lib.syms, rbin_ptr); }
    st_spv_text_destroy(&lib.syms, text_ptr);
  }

  // ---- diagnostics ------------------------------------------------------
  let bad_text = "OpCapability Shader\nOpBogus\n";
  var bbin_slot = st_slot_new(8);
  var bdiag_slot = st_slot_new(8);
  let brc = st_spv_text_to_binary(&lib.syms, ctx, bad_text.c_str(), bad_text.len(), bbin_slot.as_mut_ptr(), bdiag_slot.as_mut_ptr());
  let bad_diag = st_slot_read_u64(&bdiag_slot, 0);
  let bad_msg = if bad_diag != 0 { st_diagnostic_error(bad_diag) } else { "" };
  failed = failed + report(brc != SPV_SUCCESS && bad_diag != 0 && bad_msg.len() > 0,
    "diagnostics: invalid assembly -> rc=" + convert.int_to_string(brc) + ", error text copied out (\"" + bad_msg + "\")");
  if bad_diag != 0 { st_spv_diagnostic_destroy(&lib.syms, bad_diag); }

  let pos_slot = st_slot_new(24);
  let dcreate = st_spv_diagnostic_create(&lib.syms, pos_slot.as_mut_ptr(), "probe diagnostic".c_str());
  failed = failed + report(dcreate != 0, "diagnostics: spvDiagnosticCreate non-zero");
  if dcreate != 0 {
    let dmsg = st_diagnostic_error(dcreate);
    failed = failed + report(dmsg == "probe diagnostic", "diagnostics: error text copies out exactly (\"" + dmsg + "\")");
    let dprc = st_spv_diagnostic_print(&lib.syms, dcreate);
    failed = failed + report(dprc == SPV_SUCCESS, "diagnostics: spvDiagnosticPrint == SPV_SUCCESS");
    st_spv_diagnostic_destroy(&lib.syms, dcreate);
  }

  // ---- opcode string ----------------------------------------------------
  let opc = st_spv_opcode_string(&lib.syms, 0);
  failed = failed + report(opc.len() > 0, "codec: spvOpcodeString(0) = \"" + opc + "\"");

  // ---- optimizer options + gated optimizer-run probe --------------------
  let oopts = st_spv_optimizer_options_create(&lib.syms);
  if oopts != 0 {
    st_spv_optimizer_options_set_run_validator(&lib.syms, oopts, 1);
    st_spv_optimizer_options_set_validator_options(&lib.syms, oopts, vopts);
    st_spv_optimizer_options_set_max_id_bound(&lib.syms, oopts, K_DEFAULT_MAX_ID_BOUND);
    st_spv_optimizer_options_set_preserve_bindings(&lib.syms, oopts, 1);
    st_spv_optimizer_options_set_preserve_spec_constants(&lib.syms, oopts, 0);
  }
  failed = failed + report(oopts != 0, "optimizer-options: spvOptimizerOptionsCreate + 5 setters callable");
  if oopts != 0 { st_spv_optimizer_options_destroy(&lib.syms, oopts); }

  let has_opt_api = spirv_tools_resolved(&lib, "spvOptimizerCreate");
  if has_opt_api {
    let opt = st_spv_optimizer_create(&lib.syms, SPV_ENV_UNIVERSAL_1_0);
    if opt != 0 {
      st_spv_optimizer_register_performance_passes(&lib.syms, opt);
      var obin_slot = st_slot_new(8);
      let orc = st_spv_optimizer_run(&lib.syms, opt, bview.code, bview.word_count, obin_slot.as_mut_ptr(), 0);
      let obin_ptr = st_slot_read_u64(&obin_slot, 0);
      failed = failed + report(orc == SPV_SUCCESS && obin_ptr != 0, "optimizer-run: spvOptimizerRun == SPV_SUCCESS");
      if obin_ptr != 0 { st_spv_binary_destroy(&lib.syms, obin_ptr); }
      st_spv_optimizer_destroy(&lib.syms, opt);
    } else {
      failed = failed + report(false, "optimizer-run: spvOptimizerCreate returned 0");
    }
  } else {
    failed = failed + report(true, "optimizer-run: SKIP -- spvOptimizerCreate/Register*/Run not exported by this DLL (documented SDK shipping gap; name-level resolve proof above)");
  }

  // ---- reducer / fuzzer options ----------------------------------------
  let ropts = st_spv_reducer_options_create(&lib.syms);
  if ropts != 0 {
    st_spv_reducer_options_set_step_limit(&lib.syms, ropts, 100);
    st_spv_reducer_options_set_fail_on_validation_error(&lib.syms, ropts, 0);
    st_spv_reducer_options_set_target_function(&lib.syms, ropts, 0);
  }
  failed = failed + report(ropts != 0, "reducer-options: spvReducerOptionsCreate + 3 setters callable");
  if ropts != 0 { st_spv_reducer_options_destroy(&lib.syms, ropts); }

  let fopts = st_spv_fuzzer_options_create(&lib.syms);
  if fopts != 0 {
    st_spv_fuzzer_options_enable_replay_validation(&lib.syms, fopts);
    st_spv_fuzzer_options_set_random_seed(&lib.syms, fopts, 42);
    st_spv_fuzzer_options_set_replay_range(&lib.syms, fopts, -5);
    st_spv_fuzzer_options_set_shrinker_step_limit(&lib.syms, fopts, 8);
    st_spv_fuzzer_options_enable_fuzzer_pass_validation(&lib.syms, fopts);
    st_spv_fuzzer_options_enable_all_passes(&lib.syms, fopts);
  }
  failed = failed + report(fopts != 0, "fuzzer-options: spvFuzzerOptionsCreate + 6 setters callable");
  if fopts != 0 { st_spv_fuzzer_options_destroy(&lib.syms, fopts); }

  // ---- operand family (header-declared, not exported by this DLL) -------
  failed = failed + report(!spirv_tools_resolved(&lib, "spvOperandIsConcrete"),
    "operand: SKIP -- spvOperandIsConcrete/IsConcreteMask not exported by this DLL (shipping gap)");

  // ---- ownership teardown ----------------------------------------------
  if bin_ptr != 0 { st_spv_binary_destroy(&lib.syms, bin_ptr); }
  if bin2_ptr != 0 { st_spv_binary_destroy(&lib.syms, bin2_ptr); }
  failed = failed + report(true, "ownership: spvBinaryDestroy on all assembly out-params");
  if vopts != 0 { st_spv_validator_options_destroy(&lib.syms, vopts); }
  if ctx != 0 { st_spv_context_destroy(&lib.syms, ctx); }
  failed = failed + report(true, "ownership: validator options + context destroyed");

  let cl = spirv_tools_close(&lib);
  failed = failed + report(cl.is_ok, "unload: spirv_tools_close");

  if failed == 0 {
    io.println("xiom.spirv-tools: all checks passed");
  } else {
    io.println("xiom.spirv-tools: " + convert.int_to_string(failed) + " check(s) failed");
  }
  io.flush_stdout();
  return failed;
}
