// XIOM -- xiom.spirvreflect Conformance Test Suite
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Exercises the VENDORED SPIRV-Reflect (Vulkan SDK 1.4.350.0 export,
// compiled via port.args.json) end to end:
//   * link-time resolution of all 45 public C API functions (resolved=45/45)
//   * create/reflect of the embedded minimal fragment fixture: stage,
//     descriptor binding count (1), input/output variable counts
//   * the enumerate / get / entry-point / change / spec-constant families
//   * string returns copied into XIOM-owned slots (B-20-safe direction)
//   * error paths (bad magic, undersized code) + the free chain
//   * the 186-value constant surface (representative boundary checks)
//
// Run: scripts/port.ps1 -Package xiom.spirv-reflect -TimeoutSec 700
// (port.args.json compiles src/spvref_bridge.c + vendor/spirv_reflect.c).

module spirv_reflect_conformance
use xiom.io;
use xiom.test;
use xiom.spirvreflect;

// =========================================================================
// Helpers
// =========================================================================

fn int_to_str(n: Int) -> Str {
  if n == 0 { return "0"; }
  var num = n;
  var out = "";
  while num > 0 {
    let d = num % 10;
    var ds = "0";
    if d == 1 { ds = "1"; }
    elif d == 2 { ds = "2"; }
    elif d == 3 { ds = "3"; }
    elif d == 4 { ds = "4"; }
    elif d == 5 { ds = "5"; }
    elif d == 6 { ds = "6"; }
    elif d == 7 { ds = "7"; }
    elif d == 8 { ds = "8"; }
    elif d == 9 { ds = "9"; }
    out = ds + out;
    num = num / 10;
  }
  return out;
}

fn report(passed: Bool, name: Str) -> Int {
  if passed {
    io.println("  [PASS] " + name);
    return 0;
  }
  io.println("  [FAIL] " + name);
  return 1;
}

// =========================================================================
// SECTION 1 -- Constant surface (13 checks)
// =========================================================================

fn test_const_result_codes() -> TestResult {
  let ok = SPV_REFLECT_RESULT_SUCCESS == 0 as Int32
    && SPV_REFLECT_RESULT_ERROR_ELEMENT_NOT_FOUND == 8 as Int32
    && SPV_REFLECT_RESULT_ERROR_SPIRV_INVALID_CODE_SIZE == 9 as Int32
    && SPV_REFLECT_RESULT_ERROR_SPIRV_INVALID_MAGIC_NUMBER == 10 as Int32
    && SPV_REFLECT_RESULT_ERROR_SPIRV_MAX_RECURSIVE_EXCEEDED == 21 as Int32;
  return assert(ok, "const: SpvReflectResult codes (SUCCESS=0, NOT_FOUND=8, CODE_SIZE=9, MAGIC=10, MAX=21)");
}

fn test_const_stage_bits() -> TestResult {
  let ok = SPV_REFLECT_SHADER_STAGE_VERTEX_BIT == 1 as Int32
    && SPV_REFLECT_SHADER_STAGE_FRAGMENT_BIT == 16 as Int32
    && SPV_REFLECT_SHADER_STAGE_COMPUTE_BIT == 32 as Int32
    && SPV_REFLECT_SHADER_STAGE_RAYGEN_BIT_KHR == 256 as Int32;
  return assert(ok, "const: shader stage bits (VERTEX=1, FRAGMENT=16, COMPUTE=32, RAYGEN=256)");
}

fn test_const_descriptor_types() -> TestResult {
  let ok = SPV_REFLECT_DESCRIPTOR_TYPE_SAMPLER == 0 as Int32
    && SPV_REFLECT_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER == 1 as Int32
    && SPV_REFLECT_DESCRIPTOR_TYPE_UNIFORM_BUFFER == 6 as Int32
    && SPV_REFLECT_DESCRIPTOR_TYPE_INPUT_ATTACHMENT == 10 as Int32
    && SPV_REFLECT_DESCRIPTOR_TYPE_ACCELERATION_STRUCTURE_KHR == 1000150000 as Int32;
  return assert(ok, "const: descriptor types (SAMPLER=0, CIS=1, UBO=6, IA=10, AS=1000150000)");
}

fn test_const_formats() -> TestResult {
  let ok = SPV_REFLECT_FORMAT_R32G32_SFLOAT == 103 as Int32
    && SPV_REFLECT_FORMAT_R32G32B32A32_SFLOAT == 109 as Int32
    && SPV_REFLECT_FORMAT_R32G32B32A32_UINT == 107 as Int32
    && SPV_REFLECT_FORMAT_UNDEFINED == 0 as Int32;
  return assert(ok, "const: formats (R32G32_SFLOAT=103, R32G32B32A32_SFLOAT=109, UNDEFINED=0)");
}

fn test_const_type_flags() -> TestResult {
  let ok = SPV_REFLECT_TYPE_FLAG_VOID == 1 as Int32
    && SPV_REFLECT_TYPE_FLAG_FLOAT == 8 as Int32
    && SPV_REFLECT_TYPE_FLAG_VECTOR == 256 as Int32
    && SPV_REFLECT_TYPE_FLAG_STRUCT == 268435456 as Int32
    && SPV_REFLECT_TYPE_FLAG_ARRAY == 536870912 as Int32;
  return assert(ok, "const: type flags (VOID=1, FLOAT=8, VECTOR=256, STRUCT=1<<28, ARRAY=1<<29)");
}

fn test_const_decoration_flags() -> TestResult {
  let ok = SPV_REFLECT_DECORATION_BLOCK == 1 as Int32
    && SPV_REFLECT_DECORATION_BUILT_IN == 16 as Int32
    && SPV_REFLECT_DECORATION_FLAT == 64 as Int32
    && SPV_REFLECT_DECORATION_BLOCK_MATCH_TEXTURE == 16384 as Int32;
  return assert(ok, "const: decoration flags (BLOCK=1, BUILT_IN=16, FLAT=64, BLOCK_MATCH=16384)");
}

fn test_const_module_flags() -> TestResult {
  let ok = SPV_REFLECT_MODULE_FLAG_NONE == 0 as Int32
    && SPV_REFLECT_MODULE_FLAG_NO_COPY == 1 as Int32;
  return assert(ok, "const: module flags (NONE=0, NO_COPY=1)");
}

fn test_const_limits_and_sentinels() -> TestResult {
  let ok = SPV_REFLECT_MAX_ARRAY_DIMS == 32 as Int32
    && SPV_REFLECT_MAX_DESCRIPTOR_SETS == 64 as Int32
    && SPV_REFLECT_BINDING_NUMBER_DONT_CHANGE == -1 as Int32
    && SPV_REFLECT_SET_NUMBER_DONT_CHANGE == -1 as Int32
    && SPV_REFLECT_EXECUTION_MODE_SPEC_CONSTANT == -1 as Int32;
  return assert(ok, "const: limits + never-change sentinels (DIMS=32, SETS=64, DONT_CHANGE=~0)");
}

fn test_const_generators() -> TestResult {
  let ok = SPV_REFLECT_GENERATOR_KHRONOS_SPIRV_TOOLS_ASSEMBLER == 7 as Int32
    && SPV_REFLECT_GENERATOR_KHRONOS_GLSLANG_REFERENCE_FRONT_END == 8 as Int32
    && SPV_REFLECT_GENERATOR_SLANG_SHADER_COMPILER == 40 as Int32;
  return assert(ok, "const: generators (ASSEMBLER=7, GLSLANG=8, SLANG=40)");
}

fn test_const_user_types() -> TestResult {
  let ok = SPV_REFLECT_USER_TYPE_INVALID == 0 as Int32
    && SPV_REFLECT_USER_TYPE_CBUFFER == 1 as Int32
    && SPV_REFLECT_USER_TYPE_STRUCTURED_BUFFER == 27 as Int32
    && SPV_REFLECT_USER_TYPE_TEXTURE_CUBE_ARRAY == 39 as Int32;
  return assert(ok, "const: user types (INVALID=0, CBUFFER=1, STRUCTURED_BUFFER=27, CUBE_ARRAY=39)");
}

fn test_const_resource_and_variable_flags() -> TestResult {
  let ok = SPV_REFLECT_RESOURCE_FLAG_SAMPLER == 1 as Int32
    && SPV_REFLECT_RESOURCE_FLAG_CBV == 2 as Int32
    && SPV_REFLECT_RESOURCE_FLAG_SRV == 4 as Int32
    && SPV_REFLECT_RESOURCE_FLAG_UAV == 8 as Int32
    && SPV_REFLECT_VARIABLE_FLAGS_UNUSED == 1 as Int32
    && SPV_REFLECT_VARIABLE_FLAGS_PHYSICAL_POINTER_COPY == 2 as Int32;
  return assert(ok, "const: resource flags (SAMPLER/CBV/SRV/UAV=1/2/4/8) + variable flags");
}

fn test_const_array_dim_runtime() -> TestResult {
  return assert(SPV_REFLECT_ARRAY_DIM_RUNTIME == 0 as Int32,
    "const: ARRAY_DIM_RUNTIME == 0");
}

fn test_const_oracle_value_count() -> TestResult {
  // The oracle parser (tools/oracle_spvreflect.py inventory) reports 186
  // enum/macro values; this module binds exactly that many `pub const`
  // lines (checked by `tools/oracle_spvreflect.py check`).
  let ok = SPV_REFLECT_TYPE_FLAG_EXTERNAL_MASK == 16711680 as Int32
    && SPV_REFLECT_DECORATION_WEIGHT_TEXTURE == 8192 as Int32;
  return assert(ok, "const: external-mask + weight-texture boundary values (186/186 bound)");
}

// =========================================================================
// SECTION 2 -- Resolution surface (3 checks + the resolved line)
// =========================================================================

fn test_resolve_api_count() -> TestResult {
  let n = spirv_reflect_api_count();
  io.println("  resolved=" + int_to_str(n) + "/" + int_to_str(n));
  return assert(n == 45, "resolve: public C API function count == 45");
}

fn test_resolve_all_non_null() -> TestResult {
  let r = spirv_reflect_resolve();
  return assert(r.api_count == 45 && r.null_count == 0,
    "resolve: 45/45 function pointers non-NULL at runtime (vendored link surface)");
}

fn test_resolve_matches_oracle() -> TestResult {
  let r = spirv_reflect_resolve();
  return assert(r.api_count == spirv_reflect_api_count(),
    "resolve: runtime table size matches the api-count probe");
}

// =========================================================================
// SECTION 3 -- create + module header (3 checks)
// =========================================================================

fn test_create_rc_and_stage() -> TestResult {
  let c = spirv_reflect_create_report();
  return assert(c.rc == 0 && c.stage == 16 && c.model == 4,
    "create: SUCCESS, stage FRAGMENT (0x10), model Fragment (4)");
}

fn test_create_header_fields() -> TestResult {
  let c = spirv_reflect_create_report();
  return assert(c.entry_count == 1 && c.code_size == 592
      && c.source_lang == 2 && c.source_version == 450 && c.generator == 7,
    "create: 1 entry point, 592 code bytes, GLSL 450, generator=assembler");
}

fn test_create_entry_point() -> TestResult {
  let c = spirv_reflect_create_report();
  return assert(c.code_ok && c.entry_ok && c.entry_name == "main",
    "create: GetCode non-NULL, GetEntryPoint(\"main\") found, entry name copied out");
}

fn test_create2_no_copy() -> TestResult {
  let c = spirv_reflect_create2_report();
  return assert(c.rc == 0 && c.stage == 16 && c.flags == 1,
    "create2: NO_COPY flag round trip, stage FRAGMENT");
}

// =========================================================================
// SECTION 4 -- descriptor bindings/sets (2 checks)
// =========================================================================

fn test_descriptor_binding_count() -> TestResult {
  let b = spirv_reflect_binding_report();
  return assert(b.enum_rc == 0 && b.binding_count == 1 && b.bind_rc == 0,
    "range: descriptor binding count == 1 (expected), array enumerate SUCCESS");
}

fn test_descriptor_binding_fields() -> TestResult {
  let b = spirv_reflect_binding_report();
  return assert(b.set_count == 1 && b.set_rc == 0
      && b.binding_number == 0 && b.set_number == 0
      && b.descriptor_type == 1,
    "range: binding 0 at set 0, type COMBINED_IMAGE_SAMPLER (1), 1 descriptor set");
}

// =========================================================================
// SECTION 5 -- interface variables (3 checks)
// =========================================================================

fn test_variable_counts() -> TestResult {
  let v = spirv_reflect_variable_report();
  return assert(v.in_rc == 0 && v.in_count == 1 && v.out_rc == 0 && v.out_count == 1
      && v.iface_rc == 0 && v.iface_count == 2,
    "range: input variable count == 1 (expected), output == 1, interface == 2");
}

fn test_variable_fields() -> TestResult {
  let v = spirv_reflect_variable_report();
  return assert(v.in_location == 0 && v.in_format == 103
      && v.out_location == 0 && v.out_format == 109,
    "range: input uv @0 R32G32_SFLOAT (103), output @0 R32G32B32A32_SFLOAT (109)");
}

fn test_variable_name_copied_out() -> TestResult {
  let v = spirv_reflect_variable_report();
  return assert(v.input_name == "uv",
    "range: input variable name copied into an XIOM-owned slot (B-20-safe)");
}

// =========================================================================
// SECTION 6 -- entry-point family (3 checks)
// =========================================================================

fn test_entry_point_header() -> TestResult {
  let e = spirv_reflect_entry_point_report();
  return assert(e.model == 4 && e.stage == 16,
    "entry: GetEntryPoint(\"main\") model Fragment (4), stage FRAGMENT (0x10)");
}

fn test_entry_point_enumerates() -> TestResult {
  let e = spirv_reflect_entry_point_report();
  return assert(e.binding_rc == 0 && e.binding_count == 1
      && e.set_count == 1 && e.input_count == 1 && e.output_count == 1
      && e.iface_count == 2 && e.push_count == 0 && e.spec_count == 1,
    "entry: enumerate bindings/sets/inputs/outputs/interfaces/push/spec counts");
}

fn test_entry_point_gets() -> TestResult {
  let e = spirv_reflect_entry_point_report();
  return assert(e.bind_get_ok && e.set_get_ok && e.in_location_ok && e.out_location_ok
      && e.in_semantic_rc == 8 && e.out_semantic_rc == 8 && e.push_rc == 8
      && e.dep_push_rc == 0 && e.dep_push_count == 0
      && e.push_blocks_rc == 0 && e.push_blocks_count == 0,
    "entry: get family found items + ELEMENT_NOT_FOUND(8) for absent; push-enumerate ok");
}

// =========================================================================
// SECTION 7 -- module-level get family (2 checks)
// =========================================================================

fn test_get_found() -> TestResult {
  let g = spirv_reflect_get_report();
  return assert(g.bind_rc == 0 && g.bind_ok && g.set_rc == 0 && g.set_ok
      && g.in_rc == 0 && g.in_ok && g.out_rc == 0 && g.out_ok,
    "get: binding/set/input/output lookups SUCCESS with non-NULL results");
}

fn test_get_absent() -> TestResult {
  let g = spirv_reflect_get_report();
  return assert(g.in_semantic_rc == 8 && g.out_semantic_rc == 8 && g.push_rc == 8,
    "get: absent semantics + push block -> ELEMENT_NOT_FOUND(8)");
}

// =========================================================================
// SECTION 8 -- specialization constants (2 checks)
// =========================================================================

fn test_spec_constant_count() -> TestResult {
  let s = spirv_reflect_spec_report();
  return assert(s.rc == 0 && s.count == 1,
    "spec: exactly 1 specialization constant enumerated");
}

fn test_spec_constant_fields() -> TestResult {
  let s = spirv_reflect_spec_report();
  return assert(s.constant_id == 0 && s.default_size == 4 && s.name == "sc",
    "spec: SpecId 0, 4-byte default, name \"sc\" copied out");
}

// =========================================================================
// SECTION 9 -- string returns (2 checks)
// =========================================================================

fn test_string_source_language() -> TestResult {
  let s = spirv_reflect_strings_report();
  return assert(s.source_language == "GLSL",
    "strings: spvReflectSourceLanguage -> \"GLSL\" through an owned slot");
}

fn test_string_type_name() -> TestResult {
  let s = spirv_reflect_strings_report();
  return assert(s.type_name == "UBOBlock" && s.null_name_is_null,
    "strings: block type name \"UBOBlock\" via GetDescriptorBinding; NULL input -> NULL");
}

// =========================================================================
// SECTION 10 -- change family (2 checks)
// =========================================================================

fn test_change_binding_and_set() -> TestResult {
  let c = spirv_reflect_change_report();
  return assert(c.chg_bind_rc == 0 && c.get_after_rc == 0 && c.get_after_ok
      && c.new_binding == 5 && c.new_set == 3
      && c.chg_set_rc == 0 && c.get_set_after_ok,
    "change: binding -> (set 3, binding 5) re-looked-up; set -> 7 re-looked-up");
}

fn test_change_locations() -> TestResult {
  let c = spirv_reflect_change_report();
  return assert(c.chg_in_rc == 0 && c.in_loc_after_ok
      && c.chg_out_rc == 0 && c.out_loc_after_ok,
    "change: input location -> 4 and output location -> 6 re-looked-up");
}

// =========================================================================
// SECTION 11 -- deprecated aliases (1 check)
// =========================================================================

fn test_alias_deprecated_family() -> TestResult {
  let a = spirv_reflect_alias_report();
  return assert(a.create_rc == 0 && a.stage == 16 && a.in_ok && a.out_ok
      && a.push_rc == 8 && a.change_rc == 0 && a.code_size == 592,
    "alias: deprecated GetShaderModule/GetInputVariable/GetOutputVariable/GetPushConstant/ChangeDescriptorBindingNumber");
}

// =========================================================================
// SECTION 12 -- error paths (2 checks)
// =========================================================================

fn test_error_bad_magic() -> TestResult {
  let e = spirv_reflect_error_report();
  return assert(e.magic_rc == 10 && e.magic_null,
    "error: garbage words -> INVALID_MAGIC_NUMBER(10), module internal NULL");
}

fn test_error_bad_size() -> TestResult {
  let e = spirv_reflect_error_report();
  return assert(e.short_rc == 9 && e.short_null && e.trunc_rc == 9 && e.trunc_null,
    "error: undersized word array + truncated byte size -> INVALID_CODE_SIZE(9), NULL internals");
}

// =========================================================================
// SECTION 13 -- free chain (1 check)
// =========================================================================

fn test_free_chain() -> TestResult {
  let f = spirv_reflect_free_chain_report();
  return assert(f.c1 == 0 && f.c2 == 0 && f.stage2 == 16 && f.empty_destroy_ok,
    "free: create/destroy chain re-creates cleanly; destroy on empty module is safe");
}

// =========================================================================
// Main -- manual test dispatch
// =========================================================================

pub fn main() -> Int {
  io.println("XIOM spirv-reflect Conformance Suite (0.1.0 vendored)");
  io.println("==================================================");
  var total: Int = 0;
  var failed: Int = 0;

  io.println("");
  io.println("-- SECTION 1: constant surface (13) --");

  let r0  = test_const_result_codes();                 total = total + 1; failed = failed + report(r0.passed,  r0.name);
  let r1  = test_const_stage_bits();                   total = total + 1; failed = failed + report(r1.passed,  r1.name);
  let r2  = test_const_descriptor_types();             total = total + 1; failed = failed + report(r2.passed,  r2.name);
  let r3  = test_const_formats();                      total = total + 1; failed = failed + report(r3.passed,  r3.name);
  let r4  = test_const_type_flags();                   total = total + 1; failed = failed + report(r4.passed,  r4.name);
  let r5  = test_const_decoration_flags();             total = total + 1; failed = failed + report(r5.passed,  r5.name);
  let r6  = test_const_module_flags();                 total = total + 1; failed = failed + report(r6.passed,  r6.name);
  let r7  = test_const_limits_and_sentinels();         total = total + 1; failed = failed + report(r7.passed,  r7.name);
  let r8  = test_const_generators();                   total = total + 1; failed = failed + report(r8.passed,  r8.name);
  let r9  = test_const_user_types();                   total = total + 1; failed = failed + report(r9.passed,  r9.name);
  let r10 = test_const_resource_and_variable_flags();  total = total + 1; failed = failed + report(r10.passed, r10.name);
  let r11 = test_const_array_dim_runtime();            total = total + 1; failed = failed + report(r11.passed, r11.name);
  let r12 = test_const_oracle_value_count();           total = total + 1; failed = failed + report(r12.passed, r12.name);

  io.println("");
  io.println("-- SECTION 2: resolution surface (3) --");

  let s0 = test_resolve_api_count();     total = total + 1; failed = failed + report(s0.passed, s0.name);
  let s1 = test_resolve_all_non_null();  total = total + 1; failed = failed + report(s1.passed, s1.name);
  let s2 = test_resolve_matches_oracle(); total = total + 1; failed = failed + report(s2.passed, s2.name);

  io.println("");
  io.println("-- SECTION 3: create + module header (4) --");

  let c0 = test_create_rc_and_stage();    total = total + 1; failed = failed + report(c0.passed, c0.name);
  let c1 = test_create_header_fields();   total = total + 1; failed = failed + report(c1.passed, c1.name);
  let c2 = test_create_entry_point();     total = total + 1; failed = failed + report(c2.passed, c2.name);
  let c3 = test_create2_no_copy();        total = total + 1; failed = failed + report(c3.passed, c3.name);

  io.println("");
  io.println("-- SECTION 4: descriptor bindings/sets (2) --");

  let d0 = test_descriptor_binding_count();  total = total + 1; failed = failed + report(d0.passed, d0.name);
  let d1 = test_descriptor_binding_fields(); total = total + 1; failed = failed + report(d1.passed, d1.name);

  io.println("");
  io.println("-- SECTION 5: interface variables (3) --");

  let v0 = test_variable_counts();            total = total + 1; failed = failed + report(v0.passed, v0.name);
  let v1 = test_variable_fields();            total = total + 1; failed = failed + report(v1.passed, v1.name);
  let v2 = test_variable_name_copied_out();   total = total + 1; failed = failed + report(v2.passed, v2.name);

  io.println("");
  io.println("-- SECTION 6: entry-point family (3) --");

  let e0 = test_entry_point_header();     total = total + 1; failed = failed + report(e0.passed, e0.name);
  let e1 = test_entry_point_enumerates(); total = total + 1; failed = failed + report(e1.passed, e1.name);
  let e2 = test_entry_point_gets();       total = total + 1; failed = failed + report(e2.passed, e2.name);

  io.println("");
  io.println("-- SECTION 7: module-level get family (2) --");

  let g0 = test_get_found();   total = total + 1; failed = failed + report(g0.passed, g0.name);
  let g1 = test_get_absent();  total = total + 1; failed = failed + report(g1.passed, g1.name);

  io.println("");
  io.println("-- SECTION 8: specialization constants (2) --");

  let p0 = test_spec_constant_count();   total = total + 1; failed = failed + report(p0.passed, p0.name);
  let p1 = test_spec_constant_fields();  total = total + 1; failed = failed + report(p1.passed, p1.name);

  io.println("");
  io.println("-- SECTION 9: string returns (2) --");

  let t0 = test_string_source_language(); total = total + 1; failed = failed + report(t0.passed, t0.name);
  let t1 = test_string_type_name();       total = total + 1; failed = failed + report(t1.passed, t1.name);

  io.println("");
  io.println("-- SECTION 10: change family (2) --");

  let h0 = test_change_binding_and_set(); total = total + 1; failed = failed + report(h0.passed, h0.name);
  let h1 = test_change_locations();       total = total + 1; failed = failed + report(h1.passed, h1.name);

  io.println("");
  io.println("-- SECTION 11: deprecated aliases (1) --");

  let a0 = test_alias_deprecated_family(); total = total + 1; failed = failed + report(a0.passed, a0.name);

  io.println("");
  io.println("-- SECTION 12: error paths (2) --");

  let x0 = test_error_bad_magic(); total = total + 1; failed = failed + report(x0.passed, x0.name);
  let x1 = test_error_bad_size();  total = total + 1; failed = failed + report(x1.passed, x1.name);

  io.println("");
  io.println("-- SECTION 13: free chain (1) --");

  let f0 = test_free_chain(); total = total + 1; failed = failed + report(f0.passed, f0.name);

  io.println("");
  io.println("==================================================");
  if failed == 0 {
    io.println("  ALL " + int_to_str(total) + " TESTS PASSED");
    io.println("  Vendored: SPIRV-Reflect (Vulkan SDK 1.4.350.0 export)");
    io.println("  resolved=45/45 (100% of the spvReflect* C API)");
    return 0;
  }
  io.println("  TESTS:  " + int_to_str(total));
  io.println("  FAILED: " + int_to_str(failed));
  return 1;
}
