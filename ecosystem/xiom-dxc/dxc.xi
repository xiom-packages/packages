// XIOM — DirectX Shader Compiler (DXC) FFI Bindings
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Low-level FFI declarations for DXC (dxcompiler.dll / libdxcompiler.so).
// DXC uses a COM-based API. All COM vtable dispatch is handled by the
// C bridge (dxc_bridge.c). XIOM calls plain extern "C" functions only.
//
// v0.46 compiler notes:
//   - Int as *T cast: REJECTED at type checker → use C bridge for all ptr ops
//   - Int as fn(...) cast: REJECTED → use C bridge for all vtable dispatch
//   - Cross-module extern resolution: broken → duplicate extern block in safe
//
// Coverage: 129 bridge functions covering 24 COM interfaces + 34 GUID resolvers
// + 2 DxcCreateInstance exports = 165 total extern C declarations.

module xiom.dxc

// =========================================================================
// Code Page Constants
// =========================================================================

pub const DXC_CP_ACP: Int32 = 0 as Int32;
pub const DXC_CP_UTF8: Int32 = 65001 as Int32;
pub const DXC_CP_UTF16: Int32 = 1200 as Int32;
pub const DXC_CP_UTF32: Int32 = 12000 as Int32;
pub const DXC_CP_WIDE: Int32 = 1200 as Int32;

// =========================================================================
// Shader Hash Flags
// =========================================================================

pub const DXC_HASHFLAG_INCLUDES_SOURCE: Int32 = 1 as Int32;

// =========================================================================
// FOURCC Part Constants
// =========================================================================

pub const DXC_PART_PDB: Int32 = 1146246729 as Int32;
pub const DXC_PART_PDB_NAME: Int32 = 1314015561 as Int32;
pub const DXC_PART_PRIVATE_DATA: Int32 = 1447129168 as Int32;
pub const DXC_PART_ROOT_SIGNATURE: Int32 = 909262164 as Int32;
pub const DXC_PART_DXIL: Int32 = 1279994180 as Int32;
pub const DXC_PART_REFLECTION_DATA: Int32 = 1414742871 as Int32;
pub const DXC_PART_SHADER_HASH: Int32 = 1212231240 as Int32;
pub const DXC_PART_INPUT_SIGNATURE: Int32 = 827410761 as Int32;
pub const DXC_PART_OUTPUT_SIGNATURE: Int32 = 827413073 as Int32;
pub const DXC_PART_PATCH_CONSTANT_SIGNATURE: Int32 = 827413072 as Int32;

// =========================================================================
// DXC_OUT_KIND Enum
// =========================================================================

pub const DXC_OUT_NONE: Int32 = 0 as Int32;
pub const DXC_OUT_OBJECT: Int32 = 1 as Int32;
pub const DXC_OUT_ERRORS: Int32 = 2 as Int32;
pub const DXC_OUT_PDB: Int32 = 3 as Int32;
pub const DXC_OUT_SHADER_HASH: Int32 = 4 as Int32;
pub const DXC_OUT_DISASSEMBLY: Int32 = 5 as Int32;
pub const DXC_OUT_HLSL: Int32 = 6 as Int32;
pub const DXC_OUT_TEXT: Int32 = 7 as Int32;
pub const DXC_OUT_REFLECTION: Int32 = 8 as Int32;
pub const DXC_OUT_ROOT_SIGNATURE: Int32 = 9 as Int32;
pub const DXC_OUT_EXTRA_OUTPUTS: Int32 = 10 as Int32;
pub const DXC_OUT_REMARKS: Int32 = 11 as Int32;
pub const DXC_OUT_TIME_REPORT: Int32 = 12 as Int32;
pub const DXC_OUT_TIME_TRACE: Int32 = 13 as Int32;

// =========================================================================
// Validator Flags
// =========================================================================

pub const DXC_VALIDATOR_FLAGS_DEFAULT: Int32 = 0 as Int32;
pub const DXC_VALIDATOR_FLAGS_IN_PLACE_EDIT: Int32 = 1 as Int32;
pub const DXC_VALIDATOR_FLAGS_ROOT_SIGNATURE_ONLY: Int32 = 2 as Int32;
pub const DXC_VALIDATOR_FLAGS_MODULE_ONLY: Int32 = 4 as Int32;
pub const DXC_VALIDATOR_FLAGS_VALID_MASK: Int32 = 7 as Int32;

// =========================================================================
// Version Info Flags
// =========================================================================

pub const DXC_VERSION_INFO_FLAGS_NONE: Int32 = 0 as Int32;
pub const DXC_VERSION_INFO_FLAGS_DEBUG: Int32 = 1 as Int32;
pub const DXC_VERSION_INFO_FLAGS_INTERNAL: Int32 = 2 as Int32;

// =========================================================================
// HRESULT Constants
// =========================================================================

pub const S_OK: Int32 = 0 as Int32;
pub const S_FALSE: Int32 = 1 as Int32;
pub const E_FAIL: Int32 = -2147467259 as Int32;
pub const E_INVALIDARG: Int32 = -2147024809 as Int32;
pub const E_OUTOFMEMORY: Int32 = -2147024882 as Int32;
pub const E_NOTIMPL: Int32 = -2147467263 as Int32;
pub const E_NOINTERFACE: Int32 = -2147467262 as Int32;
pub const E_POINTER: Int32 = -2147467261 as Int32;
pub const E_NOT_VALID_STATE: Int32 = -2147016705 as Int32;
pub const DXC_E_MISSING_PART: Int32 = -2004284416 as Int32;

// =========================================================================
// Struct Types (for documentation / safe-wrapper use)
// =========================================================================

pub type DxcBuffer = {
  ptr: Int;
  size: Int;
  encoding: Int32;
} derive[Clone]

pub type DxcDefine = {
  name: Int;
  value: Int;
} derive[Clone]

// =========================================================================
// External "C" Functions — 165 declarations across 2 DLL exports + 163 bridge
// =========================================================================

extern "C" {
  // -- DLL exports (dxcompiler.dll) --
  fn DxcCreateInstance(rclsid: Int, riid: Int, ppv: Int) -> Int32;

  // -- GUID pointer resolvers (CLSIDs) --
  fn xiom_dxc_clsid_compiler() -> Int;
  fn xiom_dxc_clsid_utils() -> Int;
  fn xiom_dxc_clsid_library() -> Int;
  fn xiom_dxc_clsid_validator() -> Int;
  fn xiom_dxc_clsid_linker() -> Int;
  fn xiom_dxc_clsid_assembler() -> Int;
  fn xiom_dxc_clsid_container_reflection() -> Int;
  fn xiom_dxc_clsid_optimizer() -> Int;
  fn xiom_dxc_clsid_container_builder() -> Int;
  fn xiom_dxc_clsid_compiler_args() -> Int;
  fn xiom_dxc_clsid_pdb_utils() -> Int;

  // -- GUID pointer resolvers (IIDs) --
  fn xiom_dxc_iid_compiler3() -> Int;
  fn xiom_dxc_iid_utils() -> Int;
  fn xiom_dxc_iid_result() -> Int;
  fn xiom_dxc_iid_blob() -> Int;
  fn xiom_dxc_iid_blob_encoding() -> Int;
  fn xiom_dxc_iid_blob_utf8() -> Int;
  fn xiom_dxc_iid_blob_wide() -> Int;
  fn xiom_dxc_iid_include_handler() -> Int;
  fn xiom_dxc_iid_operation_result() -> Int;
  fn xiom_dxc_iid_validator() -> Int;
  fn xiom_dxc_iid_validator2() -> Int;
  fn xiom_dxc_iid_linker() -> Int;
  fn xiom_dxc_iid_assembler() -> Int;
  fn xiom_dxc_iid_container_reflection() -> Int;
  fn xiom_dxc_iid_container_builder() -> Int;
  fn xiom_dxc_iid_compiler_args() -> Int;
  fn xiom_dxc_iid_extra_outputs() -> Int;
  fn xiom_dxc_iid_version_info() -> Int;
  fn xiom_dxc_iid_version_info2() -> Int;
  fn xiom_dxc_iid_version_info3() -> Int;
  fn xiom_dxc_iid_optimizer_pass() -> Int;
  fn xiom_dxc_iid_optimizer() -> Int;
  fn xiom_dxc_iid_pdb_utils() -> Int;
  fn xiom_dxc_iid_pdb_utils2() -> Int;

  // -- IUnknown --
  fn xiom_unknown_QueryInterface(ptr: Int, riid: Int, ppv_object: Int) -> Int32;
  fn xiom_unknown_AddRef(ptr: Int) -> Int32;
  fn xiom_unknown_Release(ptr: Int) -> Int32;

  // -- IDxcBlob --
  fn xiom_blob_GetBufferPointer(ptr: Int) -> Int;
  fn xiom_blob_GetBufferSize(ptr: Int) -> Int;

  // -- IDxcBlobEncoding --
  fn xiom_blob_encoding_GetEncoding(ptr: Int, p_known: Int, p_code_page: Int) -> Int32;

  // -- IDxcBlobUtf8 --
  fn xiom_blob_utf8_GetStringPointer(ptr: Int) -> Int;
  fn xiom_blob_utf8_GetStringLength(ptr: Int) -> Int;

  // -- IDxcBlobWide --
  fn xiom_blob_wide_GetStringPointer(ptr: Int) -> Int;
  fn xiom_blob_wide_GetStringLength(ptr: Int) -> Int;

  // -- IDxcIncludeHandler --
  fn xiom_include_handler_LoadSource(ptr: Int, p_filename: Int, pp_include_source: Int) -> Int32;

  // -- IDxcOperationResult --
  fn xiom_operation_result_GetStatus(ptr: Int, p_status: Int) -> Int32;
  fn xiom_operation_result_GetResult(ptr: Int, pp_result: Int) -> Int32;
  fn xiom_operation_result_GetErrorBuffer(ptr: Int, pp_errors: Int) -> Int32;

  // -- IDxcResult --
  fn xiom_result_HasOutput(ptr: Int, dxc_out_kind: Int) -> Int32;
  fn xiom_result_GetOutput(ptr: Int, dxc_out_kind: Int, riid: Int, ppv_object: Int, pp_output_name: Int) -> Int32;
  fn xiom_result_GetNumOutputs(ptr: Int) -> Int32;
  fn xiom_result_GetOutputByIndex(ptr: Int, index: Int) -> Int32;
  fn xiom_result_PrimaryOutput(ptr: Int) -> Int32;

  // -- IDxcExtraOutputs --
  fn xiom_extra_outputs_GetOutputCount(ptr: Int) -> Int32;
  fn xiom_extra_outputs_GetOutput(ptr: Int, u_index: Int, riid: Int, ppv_object: Int, pp_output_type: Int, pp_output_name: Int) -> Int32;

  // -- IDxcCompiler3 --
  fn xiom_compiler3_Compile(ptr: Int, p_source: Int, p_arguments: Int, arg_count: Int, p_include_handler: Int, riid: Int, pp_result: Int) -> Int32;
  fn xiom_compiler3_Disassemble(ptr: Int, p_object: Int, riid: Int, pp_result: Int) -> Int32;

  // -- IDxcUtils --
  fn xiom_utils_CreateBlobFromBlob(ptr: Int, p_blob: Int, offset: Int, length: Int, pp_result: Int) -> Int32;
  fn xiom_utils_CreateBlobFromPinned(ptr: Int, p_data: Int, size: Int, code_page: Int, pp_blob_encoding: Int) -> Int32;
  fn xiom_utils_MoveToBlob(ptr: Int, p_data: Int, p_imalloc: Int, size: Int, code_page: Int, pp_blob_encoding: Int) -> Int32;
  fn xiom_utils_CreateBlob(ptr: Int, p_data: Int, size: Int, code_page: Int, pp_blob_encoding: Int) -> Int32;
  fn xiom_utils_LoadFile(ptr: Int, p_file_name: Int, p_code_page: Int, pp_blob_encoding: Int) -> Int32;
  fn xiom_utils_CreateReadOnlyStreamFromBlob(ptr: Int, p_blob: Int, pp_stream: Int) -> Int32;
  fn xiom_utils_CreateDefaultIncludeHandler(ptr: Int, pp_result: Int) -> Int32;
  fn xiom_utils_GetBlobAsUtf8(ptr: Int, p_blob: Int, pp_blob_encoding: Int) -> Int32;
  fn xiom_utils_GetBlobAsWide(ptr: Int, p_blob: Int, pp_blob_encoding: Int) -> Int32;
  fn xiom_utils_GetDxilContainerPart(ptr: Int, p_shader: Int, dxc_part: Int, pp_part_data: Int, p_part_size: Int) -> Int32;
  fn xiom_utils_CreateReflection(ptr: Int, p_data: Int, riid: Int, ppv_reflection: Int) -> Int32;
  fn xiom_utils_BuildArguments(ptr: Int, p_source_name: Int, p_entry_point: Int, p_target_profile: Int, p_arguments: Int, arg_count: Int, p_defines: Int, define_count: Int, pp_args: Int) -> Int32;
  fn xiom_utils_GetPDBContents(ptr: Int, p_pdb_blob: Int, pp_hash: Int, pp_container: Int) -> Int32;

  // -- IDxcCompilerArgs --
  fn xiom_compiler_args_GetArguments(ptr: Int) -> Int;
  fn xiom_compiler_args_GetCount(ptr: Int) -> Int32;
  fn xiom_compiler_args_AddArguments(ptr: Int, p_arguments: Int, arg_count: Int) -> Int32;
  fn xiom_compiler_args_AddArgumentsUTF8(ptr: Int, p_arguments: Int, arg_count: Int) -> Int32;
  fn xiom_compiler_args_AddDefines(ptr: Int, p_defines: Int, define_count: Int) -> Int32;

  // -- IDxcValidator --
  fn xiom_validator_Validate(ptr: Int, p_shader: Int, flags: Int, pp_result: Int) -> Int32;

  // -- IDxcValidator2 --
  fn xiom_validator2_ValidateWithDebug(ptr: Int, p_shader: Int, flags: Int, p_opt_debug_bitcode: Int, pp_result: Int) -> Int32;

  // -- IDxcContainerBuilder --
  fn xiom_container_builder_Load(ptr: Int, p_dxil_container_header: Int) -> Int32;
  fn xiom_container_builder_AddPart(ptr: Int, four_cc: Int, p_source: Int) -> Int32;
  fn xiom_container_builder_RemovePart(ptr: Int, four_cc: Int) -> Int32;
  fn xiom_container_builder_SerializeContainer(ptr: Int, pp_result: Int) -> Int32;

  // -- IDxcAssembler --
  fn xiom_assembler_AssembleToContainer(ptr: Int, p_shader: Int, pp_result: Int) -> Int32;

  // -- IDxcContainerReflection --
  fn xiom_container_reflection_Load(ptr: Int, p_container: Int) -> Int32;
  fn xiom_container_reflection_GetPartCount(ptr: Int, p_result: Int) -> Int32;
  fn xiom_container_reflection_GetPartKind(ptr: Int, idx: Int, p_result: Int) -> Int32;
  fn xiom_container_reflection_GetPartContent(ptr: Int, idx: Int, pp_result: Int) -> Int32;
  fn xiom_container_reflection_FindFirstPartKind(ptr: Int, kind: Int, p_result: Int) -> Int32;
  fn xiom_container_reflection_GetPartReflection(ptr: Int, idx: Int, riid: Int, ppv_object: Int) -> Int32;

  // -- IDxcOptimizerPass --
  fn xiom_optimizer_pass_GetOptionName(ptr: Int, pp_result: Int) -> Int32;
  fn xiom_optimizer_pass_GetDescription(ptr: Int, pp_result: Int) -> Int32;
  fn xiom_optimizer_pass_GetOptionArgCount(ptr: Int, p_count: Int) -> Int32;
  fn xiom_optimizer_pass_GetOptionArgName(ptr: Int, arg_index: Int, pp_result: Int) -> Int32;
  fn xiom_optimizer_pass_GetOptionArgDescription(ptr: Int, arg_index: Int, pp_result: Int) -> Int32;

  // -- IDxcOptimizer --
  fn xiom_optimizer_GetAvailablePassCount(ptr: Int, p_count: Int) -> Int32;
  fn xiom_optimizer_GetAvailablePass(ptr: Int, index: Int, pp_result: Int) -> Int32;
  fn xiom_optimizer_RunOptimizer(ptr: Int, p_blob: Int, pp_options: Int, option_count: Int, p_output_module: Int, pp_output_text: Int) -> Int32;

  // -- IDxcVersionInfo --
  fn xiom_version_info_GetVersion(ptr: Int, p_major: Int, p_minor: Int) -> Int32;
  fn xiom_version_info_GetFlags(ptr: Int, p_flags: Int) -> Int32;

  // -- IDxcVersionInfo2 --
  fn xiom_version_info2_GetCommitInfo(ptr: Int, p_commit_count: Int, pp_commit_hash: Int) -> Int32;

  // -- IDxcVersionInfo3 --
  fn xiom_version_info3_GetCustomVersionString(ptr: Int, pp_version_string: Int) -> Int32;

  // -- IDxcPdbUtils2 --
  fn xiom_pdb_utils2_Load(ptr: Int, p_pdb_or_dxil: Int) -> Int32;
  fn xiom_pdb_utils2_GetSourceCount(ptr: Int, p_count: Int) -> Int32;
  fn xiom_pdb_utils2_GetSource(ptr: Int, u_index: Int, pp_result: Int) -> Int32;
  fn xiom_pdb_utils2_GetSourceName(ptr: Int, u_index: Int, pp_result: Int) -> Int32;
  fn xiom_pdb_utils2_GetLibraryPDBCount(ptr: Int, p_count: Int) -> Int32;
  fn xiom_pdb_utils2_GetLibraryPDB(ptr: Int, u_index: Int, pp_out_pdb_utils: Int, pp_library_name: Int) -> Int32;
  fn xiom_pdb_utils2_GetFlagCount(ptr: Int, p_count: Int) -> Int32;
  fn xiom_pdb_utils2_GetFlag(ptr: Int, u_index: Int, pp_result: Int) -> Int32;
  fn xiom_pdb_utils2_GetArgCount(ptr: Int, p_count: Int) -> Int32;
  fn xiom_pdb_utils2_GetArg(ptr: Int, u_index: Int, pp_result: Int) -> Int32;
  fn xiom_pdb_utils2_GetArgPairCount(ptr: Int, p_count: Int) -> Int32;
  fn xiom_pdb_utils2_GetArgPair(ptr: Int, u_index: Int, pp_name: Int, pp_value: Int) -> Int32;
  fn xiom_pdb_utils2_GetDefineCount(ptr: Int, p_count: Int) -> Int32;
  fn xiom_pdb_utils2_GetDefine(ptr: Int, u_index: Int, pp_result: Int) -> Int32;
  fn xiom_pdb_utils2_GetTargetProfile(ptr: Int, pp_result: Int) -> Int32;
  fn xiom_pdb_utils2_GetEntryPoint(ptr: Int, pp_result: Int) -> Int32;
  fn xiom_pdb_utils2_GetMainFileName(ptr: Int, pp_result: Int) -> Int32;
  fn xiom_pdb_utils2_GetHash(ptr: Int, pp_result: Int) -> Int32;
  fn xiom_pdb_utils2_GetName(ptr: Int, pp_result: Int) -> Int32;
  fn xiom_pdb_utils2_GetVersionInfo(ptr: Int, pp_version_info: Int) -> Int32;
  fn xiom_pdb_utils2_GetCustomToolchainID(ptr: Int, p_id: Int) -> Int32;
  fn xiom_pdb_utils2_GetCustomToolchainData(ptr: Int, pp_blob: Int) -> Int32;
  fn xiom_pdb_utils2_GetWholeDxil(ptr: Int, pp_result: Int) -> Int32;
  fn xiom_pdb_utils2_IsFullPDB(ptr: Int) -> Int32;
  fn xiom_pdb_utils2_IsPDBRef(ptr: Int) -> Int32;

  // -- IDxcLinker --
  fn xiom_linker_RegisterLibrary(ptr: Int, p_lib_name: Int, p_lib: Int) -> Int32;
  fn xiom_linker_Link(ptr: Int, p_entry_name: Int, p_target_profile: Int, p_lib_names: Int, lib_count: Int, p_arguments: Int, arg_count: Int, pp_result: Int) -> Int32;
}

// =========================================================================
// Procedural Safe Wrappers
// =========================================================================

pub fn create_instance(clsid: Int, iid: Int) -> Result[Int, Str]
  requires: clsid != 0
  requires: iid != 0
{
  let ppv: Int = 0;
  let hr: Int32 = unsafe { DxcCreateInstance(clsid, iid, ppv) };
  if hr != 0 { return Err("DxcCreateInstance failed"); }
  return Ok(ppv);
}

pub fn create_compiler() -> Result[Int, Str] {
  let clsid: Int = unsafe { xiom_dxc_clsid_compiler() };
  let iid: Int = unsafe { xiom_dxc_iid_compiler3() };
  return create_instance(clsid, iid);
}

pub fn create_utils() -> Result[Int, Str] {
  let clsid: Int = unsafe { xiom_dxc_clsid_utils() };
  let iid: Int = unsafe { xiom_dxc_iid_utils() };
  return create_instance(clsid, iid);
}

pub fn create_validator() -> Result[Int, Str] {
  let clsid: Int = unsafe { xiom_dxc_clsid_validator() };
  let iid: Int = unsafe { xiom_dxc_iid_validator() };
  return create_instance(clsid, iid);
}

pub fn create_linker() -> Result[Int, Str] {
  let clsid: Int = unsafe { xiom_dxc_clsid_linker() };
  let iid: Int = unsafe { xiom_dxc_iid_linker() };
  return create_instance(clsid, iid);
}

pub fn create_assembler() -> Result[Int, Str] {
  let clsid: Int = unsafe { xiom_dxc_clsid_assembler() };
  let iid: Int = unsafe { xiom_dxc_iid_assembler() };
  return create_instance(clsid, iid);
}

pub fn create_container_reflection() -> Result[Int, Str] {
  let clsid: Int = unsafe { xiom_dxc_clsid_container_reflection() };
  let iid: Int = unsafe { xiom_dxc_iid_container_reflection() };
  return create_instance(clsid, iid);
}

pub fn create_container_builder() -> Result[Int, Str] {
  let clsid: Int = unsafe { xiom_dxc_clsid_container_builder() };
  let iid: Int = unsafe { xiom_dxc_iid_container_builder() };
  return create_instance(clsid, iid);
}

pub fn create_compiler_args() -> Result[Int, Str] {
  let clsid: Int = unsafe { xiom_dxc_clsid_compiler_args() };
  let iid: Int = unsafe { xiom_dxc_iid_compiler_args() };
  return create_instance(clsid, iid);
}

pub fn create_optimizer() -> Result[Int, Str] {
  let clsid: Int = unsafe { xiom_dxc_clsid_optimizer() };
  let iid: Int = unsafe { xiom_dxc_iid_optimizer() };
  return create_instance(clsid, iid);
}

pub fn create_pdb_utils() -> Result[Int, Str] {
  let clsid: Int = unsafe { xiom_dxc_clsid_pdb_utils() };
  let iid: Int = unsafe { xiom_dxc_iid_pdb_utils2() };
  return create_instance(clsid, iid);
}

// =========================================================================
// Safe helpers for common operations
// =========================================================================

pub fn release(ptr: Int)
  requires: ptr != 0
{
  let _ref_count: Int32 = unsafe { xiom_unknown_Release(ptr) };
  return ();
}

pub fn add_ref(ptr: Int) -> Int32
  requires: ptr != 0
{
  return unsafe { xiom_unknown_AddRef(ptr) };
}

pub fn compiler_compile(compiler: Int, p_source: Int, p_arguments: Int, arg_count: Int, p_include_handler: Int) -> Result[Int, Str]
  requires: compiler != 0
  requires: p_source != 0
{
  let riid: Int = unsafe { xiom_dxc_iid_result() };
  let pp_result: Int = 0;
  let hr: Int32 = unsafe { xiom_compiler3_Compile(compiler, p_source, p_arguments, arg_count, p_include_handler, riid, pp_result) };
  if hr != 0 { return Err("Compile failed"); }
  return Ok(pp_result);
}

pub fn compiler_disassemble(compiler: Int, p_object: Int) -> Result[Int, Str]
  requires: compiler != 0
  requires: p_object != 0
{
  let riid: Int = unsafe { xiom_dxc_iid_result() };
  let pp_result: Int = 0;
  let hr: Int32 = unsafe { xiom_compiler3_Disassemble(compiler, p_object, riid, pp_result) };
  if hr != 0 { return Err("Disassemble failed"); }
  return Ok(pp_result);
}

pub fn result_get_output_blob(result: Int, kind: Int32) -> Result[Int, Str]
  requires: result != 0
{
  let riid: Int = unsafe { xiom_dxc_iid_blob() };
  let ppv: Int = 0;
  let hr: Int32 = unsafe { xiom_result_GetOutput(result, kind as Int, riid, ppv, 0) };
  if hr != 0 { return Err("GetOutput failed"); }
  return Ok(ppv);
}

pub fn result_has_output(result: Int, kind: Int32) -> Bool
  requires: result != 0
{
  let ok: Int32 = unsafe { xiom_result_HasOutput(result, kind as Int) };
  return ok != 0;
}

pub fn get_errors_as_utf8(result: Int) -> Result[Int, Str]
  requires: result != 0
{
  let pp_errors: Int = 0;
  let hr: Int32 = unsafe { xiom_operation_result_GetErrorBuffer(result, pp_errors) };
  if hr != 0 { return Err("GetErrorBuffer failed"); }
  if pp_errors == 0 { return Err("No error buffer"); }
  return Ok(pp_errors);
}

// =========================================================================
// HRESULT -> human-readable string
// =========================================================================

pub fn result_to_string(code: Int32) -> Str {
  if code == 0     { return "S_OK"; }
  if code == 1     { return "S_FALSE"; }
  if code == -2147467259 { return "E_FAIL"; }
  if code == -2147024809 { return "E_INVALIDARG"; }
  if code == -2147024882 { return "E_OUTOFMEMORY"; }
  if code == -2147467263 { return "E_NOTIMPL"; }
  if code == -2147467262 { return "E_NOINTERFACE"; }
  if code == -2147467261 { return "E_POINTER"; }
  if code == -2004284416 { return "DXC_E_MISSING_PART"; }
  return "UNKNOWN_HRESULT";
}
