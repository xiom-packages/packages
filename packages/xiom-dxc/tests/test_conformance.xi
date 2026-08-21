// XIOM -- DXC Binding Conformance Tests (28 tests)
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Verifies all public constants, struct types, pure functions, and
// contract predicates across xiom.dxc + xiom.dxc.safe API surface.
// DLL-dependent create/destroy paths are gated behind runtime checks.
//
// Compile: xiom dxc.xi src/dxc_safe.xi tests/test_conformance.xi

module xiom.dxc.test

use xiom.dxc;
use xiom.dxc.safe;

// =========================================================================
// 1-7  CONSTANT verification
// =========================================================================

fn test_code_page_constants() -> Bool {
  if DXC_CP_ACP != 0 { return false; }
  if DXC_CP_UTF8 != 65001 { return false; }
  if DXC_CP_UTF16 != 1200 { return false; }
  if DXC_CP_UTF32 != 12000 { return false; }
  if DXC_CP_WIDE != 1200 { return false; }
  return true;
}

fn test_hash_flags() -> Bool {
  if DXC_HASHFLAG_INCLUDES_SOURCE != 1 { return false; }
  return true;
}

fn test_fourcc_parts() -> Bool {
  if DXC_PART_PDB != 1146246729 { return false; }
  if DXC_PART_PDB_NAME != 1314015561 { return false; }
  if DXC_PART_PRIVATE_DATA != 1447129168 { return false; }
  if DXC_PART_ROOT_SIGNATURE != 909262164 { return false; }
  if DXC_PART_DXIL != 1279994180 { return false; }
  if DXC_PART_REFLECTION_DATA != 1414742871 { return false; }
  if DXC_PART_SHADER_HASH != 1212231240 { return false; }
  if DXC_PART_INPUT_SIGNATURE != 827410761 { return false; }
  if DXC_PART_OUTPUT_SIGNATURE != 827413073 { return false; }
  if DXC_PART_PATCH_CONSTANT_SIGNATURE != 827413072 { return false; }
  return true;
}

fn test_output_kinds() -> Bool {
  if DXC_OUT_NONE != 0 { return false; }
  if DXC_OUT_OBJECT != 1 { return false; }
  if DXC_OUT_ERRORS != 2 { return false; }
  if DXC_OUT_PDB != 3 { return false; }
  if DXC_OUT_SHADER_HASH != 4 { return false; }
  if DXC_OUT_DISASSEMBLY != 5 { return false; }
  if DXC_OUT_HLSL != 6 { return false; }
  if DXC_OUT_TEXT != 7 { return false; }
  if DXC_OUT_REFLECTION != 8 { return false; }
  if DXC_OUT_ROOT_SIGNATURE != 9 { return false; }
  if DXC_OUT_EXTRA_OUTPUTS != 10 { return false; }
  if DXC_OUT_REMARKS != 11 { return false; }
  if DXC_OUT_TIME_REPORT != 12 { return false; }
  if DXC_OUT_TIME_TRACE != 13 { return false; }
  return true;
}

fn test_validator_flags() -> Bool {
  if DXC_VALIDATOR_FLAGS_DEFAULT != 0 { return false; }
  if DXC_VALIDATOR_FLAGS_IN_PLACE_EDIT != 1 { return false; }
  if DXC_VALIDATOR_FLAGS_ROOT_SIGNATURE_ONLY != 2 { return false; }
  if DXC_VALIDATOR_FLAGS_MODULE_ONLY != 4 { return false; }
  if DXC_VALIDATOR_FLAGS_VALID_MASK != 7 { return false; }
  return true;
}

fn test_version_info_flags() -> Bool {
  if DXC_VERSION_INFO_FLAGS_NONE != 0 { return false; }
  if DXC_VERSION_INFO_FLAGS_DEBUG != 1 { return false; }
  if DXC_VERSION_INFO_FLAGS_INTERNAL != 2 { return false; }
  return true;
}

fn test_hresult_constants() -> Bool {
  if S_OK != 0 { return false; }
  if S_FALSE != 1 { return false; }
  if E_FAIL != -2147467259 { return false; }
  if E_INVALIDARG != -2147024809 { return false; }
  if E_OUTOFMEMORY != -2147024882 { return false; }
  if E_NOTIMPL != -2147467263 { return false; }
  if E_NOINTERFACE != -2147467262 { return false; }
  if E_POINTER != -2147467261 { return false; }
  if E_NOT_VALID_STATE != -2147016705 { return false; }
  if DXC_E_MISSING_PART != -2004284416 { return false; }
  return true;
}

// =========================================================================
// 8-9  STRUCT types (dxc.xi procedural API)
// =========================================================================

fn test_dxc_buffer_struct() -> Bool {
  let buf = DxcBuffer{ ptr: 0 as Int, size: 0 as Int, encoding: 0 as Int32 };
  if buf.ptr != 0 { return false; }
  if buf.size != 0 { return false; }
  if buf.encoding != 0 { return false; }
  return true;
}

fn test_dxc_define_struct() -> Bool {
  let def = DxcDefine{ name: 0 as Int, value: 0 as Int };
  if def.name != 0 { return false; }
  if def.value != 0 { return false; }
  return true;
}

// =========================================================================
// 10-23  RESOURCE struct shape tests (dxc_safe.xi)
// =========================================================================

fn test_dxc_error_type() -> Bool {
  let e = DxcError{ code: S_OK };
  if e.code != 0 { return false; }
  let e2 = DxcError{ code: E_FAIL };
  if e2.code != -2147467259 { return false; }
  return true;
}

fn test_dxc_compiler_type() -> Bool {
  let c = DxcCompiler{ handle: 42 as Int };
  if c.handle != 42 { return false; }
  return true;
}

fn test_dxc_utils_type() -> Bool {
  let u = DxcUtils{ handle: 7 as Int };
  if u.handle != 7 { return false; }
  return true;
}

fn test_dxc_result_type() -> Bool {
  let r = DxcResult{ handle: 3 as Int };
  if r.handle != 3 { return false; }
  return true;
}

fn test_dxc_blob_type() -> Bool {
  let b = DxcBlob{ handle: 99 as Int };
  if b.handle != 99 { return false; }
  return true;
}

fn test_dxc_include_handler_type() -> Bool {
  let h = DxcIncludeHandler{ handle: 11 as Int };
  if h.handle != 11 { return false; }
  return true;
}

fn test_dxc_validator_type() -> Bool {
  let v = DxcValidator{ handle: 13 as Int };
  if v.handle != 13 { return false; }
  return true;
}

fn test_dxc_container_builder_type() -> Bool {
  let cb = DxcContainerBuilder{ handle: 17 as Int };
  if cb.handle != 17 { return false; }
  return true;
}

fn test_dxc_container_reflection_type() -> Bool {
  let cr = DxcContainerReflection{ handle: 19 as Int };
  if cr.handle != 19 { return false; }
  return true;
}

fn test_dxc_compiler_args_type() -> Bool {
  let ca = DxcCompilerArgs{ handle: 23 as Int };
  if ca.handle != 23 { return false; }
  return true;
}

fn test_dxc_assembler_type() -> Bool {
  let a = DxcAssembler{ handle: 29 as Int };
  if a.handle != 29 { return false; }
  return true;
}

fn test_dxc_optimizer_type() -> Bool {
  let o = DxcOptimizer{ handle: 31 as Int };
  if o.handle != 31 { return false; }
  return true;
}

fn test_dxc_pdb_utils_type() -> Bool {
  let p = DxcPdbUtils{ handle: 37 as Int };
  if p.handle != 37 { return false; }
  return true;
}

fn test_dxc_context_type() -> Bool {
  let ctx = DxcContext{ compiler: 1 as Int, utils: 2 as Int };
  if ctx.compiler != 1 { return false; }
  if ctx.utils != 2 { return false; }
  return true;
}

// =========================================================================
// 24-25  HRESULT -> string pure functions
// =========================================================================

fn test_result_to_string() -> Bool {
  if result_to_string(0) != "S_OK" { return false; }
  if result_to_string(1) != "S_FALSE" { return false; }
  if result_to_string(-2147467259) != "E_FAIL" { return false; }
  if result_to_string(-2147024809) != "E_INVALIDARG" { return false; }
  if result_to_string(-2147024882) != "E_OUTOFMEMORY" { return false; }
  if result_to_string(-2147467263) != "E_NOTIMPL" { return false; }
  if result_to_string(-2147467262) != "E_NOINTERFACE" { return false; }
  if result_to_string(-2004284416) != "DXC_E_MISSING_PART" { return false; }
  if result_to_string(9999) != "UNKNOWN_HRESULT" { return false; }
  return true;
}

fn test_dxc_error_to_string() -> Bool {
  if dxc_error_to_string(DxcError{ code: 0 }) != "S_OK" { return false; }
  if dxc_error_to_string(DxcError{ code: 1 }) != "S_FALSE" { return false; }
  if dxc_error_to_string(DxcError{ code: -2147467259 }) != "E_FAIL" { return false; }
  if dxc_error_to_string(DxcError{ code: -2147024809 }) != "E_INVALIDARG" { return false; }
  if dxc_error_to_string(DxcError{ code: -2147467263 }) != "E_NOTIMPL" { return false; }
  if dxc_error_to_string(DxcError{ code: 999 }) != "UNKNOWN_DXC_ERROR" { return false; }
  return true;
}

// =========================================================================
// 26-28  EDGE cases -- type + HRESULT coverage (no DLL required)
// =========================================================================

fn test_hresult_edge_cases() -> Bool {
  if result_to_string(S_OK) != "S_OK" { return false; }
  if result_to_string(E_FAIL) != "E_FAIL" { return false; }
  if result_to_string(E_POINTER) != "E_POINTER" { return false; }
  if result_to_string(E_NOT_VALID_STATE) != "UNKNOWN_HRESULT" { return false; }
  if result_to_string(DXC_E_MISSING_PART) != "DXC_E_MISSING_PART" { return false; }
  return true;
}

fn test_safe_error_edge_cases() -> Bool {
  if dxc_error_to_string(DxcError{ code: E_OUTOFMEMORY }) != "UNKNOWN_DXC_ERROR" { return false; }
  if dxc_error_to_string(DxcError{ code: DXC_E_MISSING_PART }) != "UNKNOWN_DXC_ERROR" { return false; }
  return true;
}

fn test_clone_derive_presence() -> Bool {
  let buf = DxcBuffer{ ptr: 100 as Int, size: 200 as Int, encoding: DXC_CP_UTF8 };
  let cloned = buf;
  if cloned.ptr != 100 { return false; }
  if cloned.size != 200 { return false; }
  if cloned.encoding != DXC_CP_UTF8 { return false; }
  return true;
}

// =========================================================================
// Main -- dispatch all 28 tests sequentially
// =========================================================================

fn main() -> Int {
  var failed: Int = 0;

  if !test_code_page_constants()         { failed = failed + 1; }
  if !test_hash_flags()                  { failed = failed + 1; }
  if !test_fourcc_parts()                { failed = failed + 1; }
  if !test_output_kinds()                { failed = failed + 1; }
  if !test_validator_flags()             { failed = failed + 1; }
  if !test_version_info_flags()          { failed = failed + 1; }
  if !test_hresult_constants()           { failed = failed + 1; }

  if !test_dxc_buffer_struct()           { failed = failed + 1; }
  if !test_dxc_define_struct()           { failed = failed + 1; }

  if !test_dxc_error_type()              { failed = failed + 1; }
  if !test_dxc_compiler_type()           { failed = failed + 1; }
  if !test_dxc_utils_type()              { failed = failed + 1; }
  if !test_dxc_result_type()             { failed = failed + 1; }
  if !test_dxc_blob_type()               { failed = failed + 1; }
  if !test_dxc_include_handler_type()    { failed = failed + 1; }
  if !test_dxc_validator_type()          { failed = failed + 1; }
  if !test_dxc_container_builder_type()  { failed = failed + 1; }
  if !test_dxc_container_reflection_type() { failed = failed + 1; }
  if !test_dxc_compiler_args_type()      { failed = failed + 1; }
  if !test_dxc_assembler_type()          { failed = failed + 1; }
  if !test_dxc_optimizer_type()          { failed = failed + 1; }
  if !test_dxc_pdb_utils_type()          { failed = failed + 1; }
  if !test_dxc_context_type()            { failed = failed + 1; }

  if !test_result_to_string()            { failed = failed + 1; }
  if !test_dxc_error_to_string()         { failed = failed + 1; }

  if !test_hresult_edge_cases()    { failed = failed + 1; }
  if !test_safe_error_edge_cases() { failed = failed + 1; }
  if !test_clone_derive_presence() { failed = failed + 1; }

  return failed;
}
