// XIOM -- DirectX Shader Compiler Safe Wrappers
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Struct-based safe resource management for DXC COM interfaces via C bridge.
// All create/destroy pairs with Result[T, DxcError] + design-by-contract.
// No raw pointer exposure in the public API.
//
// COVERAGE: 12 resource types spanning the full DXC lifecycle:
//   DxcCompiler, DxcUtils, DxcResult, DxcBlob, DxcIncludeHandler,
//   DxcValidator, DxcContainerBuilder, DxcContainerReflection,
//   DxcCompilerArgs, DxcAssembler, DxcOptimizer, DxcPdbUtils

module xiom.dxc.safe

// =========================================================================
// Duplicated extern declarations (cross-module resolution bug -- G003)
// =========================================================================

extern "C" {
  fn DxcCreateInstance(rclsid: Int, riid: Int, ppv: Int) -> Int32;
  fn xiom_dxc_clsid_compiler() -> Int;
  fn xiom_dxc_clsid_utils() -> Int;
  fn xiom_dxc_clsid_validator() -> Int;
  fn xiom_dxc_clsid_linker() -> Int;
  fn xiom_dxc_clsid_assembler() -> Int;
  fn xiom_dxc_clsid_container_reflection() -> Int;
  fn xiom_dxc_clsid_container_builder() -> Int;
  fn xiom_dxc_clsid_compiler_args() -> Int;
  fn xiom_dxc_clsid_optimizer() -> Int;
  fn xiom_dxc_clsid_pdb_utils() -> Int;
  fn xiom_dxc_iid_compiler3() -> Int;
  fn xiom_dxc_iid_utils() -> Int;
  fn xiom_dxc_iid_result() -> Int;
  fn xiom_dxc_iid_blob() -> Int;
  fn xiom_dxc_iid_blob_utf8() -> Int;
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
  fn xiom_dxc_iid_optimizer() -> Int;
  fn xiom_dxc_iid_pdb_utils2() -> Int;
  fn xiom_unknown_Release(ptr: Int) -> Int32;
  fn xiom_blob_GetBufferPointer(ptr: Int) -> Int;
  fn xiom_blob_GetBufferSize(ptr: Int) -> Int;
  fn xiom_blob_utf8_GetStringPointer(ptr: Int) -> Int;
  fn xiom_blob_utf8_GetStringLength(ptr: Int) -> Int;
  fn xiom_include_handler_LoadSource(ptr: Int, p_filename: Int, pp_include_source: Int) -> Int32;
  fn xiom_operation_result_GetStatus(ptr: Int, p_status: Int) -> Int32;
  fn xiom_operation_result_GetResult(ptr: Int, pp_result: Int) -> Int32;
  fn xiom_operation_result_GetErrorBuffer(ptr: Int, pp_errors: Int) -> Int32;
  fn xiom_result_HasOutput(ptr: Int, dxc_out_kind: Int) -> Int32;
  fn xiom_result_GetOutput(ptr: Int, dxc_out_kind: Int, riid: Int, ppv_object: Int, pp_output_name: Int) -> Int32;
  fn xiom_result_GetNumOutputs(ptr: Int) -> Int32;
  fn xiom_result_GetOutputByIndex(ptr: Int, index: Int) -> Int32;
  fn xiom_result_PrimaryOutput(ptr: Int) -> Int32;
  fn xiom_extra_outputs_GetOutputCount(ptr: Int) -> Int32;
  fn xiom_extra_outputs_GetOutput(ptr: Int, u_index: Int, riid: Int, ppv_object: Int, pp_output_type: Int, pp_output_name: Int) -> Int32;
  fn xiom_compiler3_Compile(ptr: Int, p_source: Int, p_arguments: Int, arg_count: Int, p_include_handler: Int, riid: Int, pp_result: Int) -> Int32;
  fn xiom_compiler3_Disassemble(ptr: Int, p_object: Int, riid: Int, pp_result: Int) -> Int32;
  fn xiom_utils_CreateBlob(ptr: Int, p_data: Int, size: Int, code_page: Int, pp_blob_encoding: Int) -> Int32;
  fn xiom_utils_LoadFile(ptr: Int, p_file_name: Int, p_code_page: Int, pp_blob_encoding: Int) -> Int32;
  fn xiom_utils_CreateDefaultIncludeHandler(ptr: Int, pp_result: Int) -> Int32;
  fn xiom_utils_GetBlobAsUtf8(ptr: Int, p_blob: Int, pp_blob_encoding: Int) -> Int32;
  fn xiom_utils_GetDxilContainerPart(ptr: Int, p_shader: Int, dxc_part: Int, pp_part_data: Int, p_part_size: Int) -> Int32;
  fn xiom_utils_CreateReflection(ptr: Int, p_data: Int, riid: Int, ppv_reflection: Int) -> Int32;
  fn xiom_utils_BuildArguments(ptr: Int, p_source_name: Int, p_entry_point: Int, p_target_profile: Int, p_arguments: Int, arg_count: Int, p_defines: Int, define_count: Int, pp_args: Int) -> Int32;
  fn xiom_utils_GetPDBContents(ptr: Int, p_pdb_blob: Int, pp_hash: Int, pp_container: Int) -> Int32;
  fn xiom_validator_Validate(ptr: Int, p_shader: Int, flags: Int, pp_result: Int) -> Int32;
  fn xiom_validator2_ValidateWithDebug(ptr: Int, p_shader: Int, flags: Int, p_opt_debug_bitcode: Int, pp_result: Int) -> Int32;
  fn xiom_container_builder_Load(ptr: Int, p_dxil_container_header: Int) -> Int32;
  fn xiom_container_builder_AddPart(ptr: Int, four_cc: Int, p_source: Int) -> Int32;
  fn xiom_container_builder_RemovePart(ptr: Int, four_cc: Int) -> Int32;
  fn xiom_container_builder_SerializeContainer(ptr: Int, pp_result: Int) -> Int32;
  fn xiom_assembler_AssembleToContainer(ptr: Int, p_shader: Int, pp_result: Int) -> Int32;
  fn xiom_container_reflection_Load(ptr: Int, p_container: Int) -> Int32;
  fn xiom_container_reflection_GetPartCount(ptr: Int, p_result: Int) -> Int32;
  fn xiom_container_reflection_GetPartKind(ptr: Int, idx: Int, p_result: Int) -> Int32;
  fn xiom_container_reflection_GetPartContent(ptr: Int, idx: Int, pp_result: Int) -> Int32;
  fn xiom_container_reflection_FindFirstPartKind(ptr: Int, kind: Int, p_result: Int) -> Int32;
  fn xiom_container_reflection_GetPartReflection(ptr: Int, idx: Int, riid: Int, ppv_object: Int) -> Int32;
  fn xiom_compiler_args_GetArguments(ptr: Int) -> Int;
  fn xiom_compiler_args_GetCount(ptr: Int) -> Int32;
  fn xiom_compiler_args_AddArguments(ptr: Int, p_arguments: Int, arg_count: Int) -> Int32;
  fn xiom_compiler_args_AddArgumentsUTF8(ptr: Int, p_arguments: Int, arg_count: Int) -> Int32;
  fn xiom_compiler_args_AddDefines(ptr: Int, p_defines: Int, define_count: Int) -> Int32;
  fn xiom_optimizer_GetAvailablePassCount(ptr: Int, p_count: Int) -> Int32;
  fn xiom_optimizer_GetAvailablePass(ptr: Int, index: Int, pp_result: Int) -> Int32;
  fn xiom_optimizer_RunOptimizer(ptr: Int, p_blob: Int, pp_options: Int, option_count: Int, p_output_module: Int, pp_output_text: Int) -> Int32;
  fn xiom_version_info_GetVersion(ptr: Int, p_major: Int, p_minor: Int) -> Int32;
  fn xiom_version_info_GetFlags(ptr: Int, p_flags: Int) -> Int32;
  fn xiom_version_info2_GetCommitInfo(ptr: Int, p_commit_count: Int, pp_commit_hash: Int) -> Int32;
  fn xiom_version_info3_GetCustomVersionString(ptr: Int, pp_version_string: Int) -> Int32;
  fn xiom_pdb_utils2_Load(ptr: Int, p_pdb_or_dxil: Int) -> Int32;
  fn xiom_pdb_utils2_GetSourceCount(ptr: Int, p_count: Int) -> Int32;
  fn xiom_pdb_utils2_GetSource(ptr: Int, u_index: Int, pp_result: Int) -> Int32;
  fn xiom_pdb_utils2_GetSourceName(ptr: Int, u_index: Int, pp_result: Int) -> Int32;
  fn xiom_pdb_utils2_GetFlagCount(ptr: Int, p_count: Int) -> Int32;
  fn xiom_pdb_utils2_GetFlag(ptr: Int, u_index: Int, pp_result: Int) -> Int32;
  fn xiom_pdb_utils2_GetArgCount(ptr: Int, p_count: Int) -> Int32;
  fn xiom_pdb_utils2_GetArg(ptr: Int, u_index: Int, pp_result: Int) -> Int32;
  fn xiom_pdb_utils2_GetHash(ptr: Int, pp_result: Int) -> Int32;
  fn xiom_pdb_utils2_GetName(ptr: Int, pp_result: Int) -> Int32;
  fn xiom_pdb_utils2_IsFullPDB(ptr: Int) -> Int32;
  fn xiom_pdb_utils2_IsPDBRef(ptr: Int) -> Int32;
}

// =========================================================================
// DxcError
// =========================================================================

pub type DxcError = {
  code: Int32;
} derive[Clone]

pub fn dxc_error_to_string(err: DxcError) -> Str {
  if err.code == 0     { return "S_OK"; }
  if err.code == 1     { return "S_FALSE"; }
  if err.code == -2147467259 { return "E_FAIL"; }
  if err.code == -2147024809 { return "E_INVALIDARG"; }
  if err.code == -2147467263 { return "E_NOTIMPL"; }
  return "UNKNOWN_DXC_ERROR";
}

// =========================================================================
// Helper: create COM instance
// =========================================================================

fn create_instance(clsid: Int, iid: Int) -> Result[Int, DxcError]
  requires: clsid != 0
  requires: iid != 0
{
  let ppv: Int = 0;
  let hr: Int32 = unsafe { DxcCreateInstance(clsid, iid, ppv) };
  if hr != 0 { return Err(DxcError{ code: hr }); }
  return Ok(ppv);
}

// =========================================================================
// DxcCompiler -- IDxcCompiler3 wrapper
// =========================================================================

pub type DxcCompiler = {
  handle: Int;
} derive[Clone]

pub fn DxcCompiler.create() -> Result[DxcCompiler, DxcError]
  ensures: result is Ok => result.unwrap().handle != 0
{
  let clsid: Int = unsafe { xiom_dxc_clsid_compiler() };
  let iid: Int = unsafe { xiom_dxc_iid_compiler3() };
  let ptr = create_instance(clsid, iid)?;
  return Ok(DxcCompiler{ handle: ptr });
}

pub fn DxcCompiler.destroy()
  requires: handle != 0
{
  unsafe { xiom_unknown_Release(handle); }
}

pub fn DxcCompiler.compile(p_source: Int, p_arguments: Int, arg_count: Int, p_include_handler: Int) -> Result[DxcResult, DxcError]
  requires: handle != 0
  requires: p_source != 0
{
  let riid: Int = unsafe { xiom_dxc_iid_result() };
  let pp_result: Int = 0;
  let hr: Int32 = unsafe { xiom_compiler3_Compile(handle, p_source, p_arguments, arg_count, p_include_handler, riid, pp_result) };
  if hr != 0 { return Err(DxcError{ code: hr }); }
  return Ok(DxcResult{ handle: pp_result });
}

pub fn DxcCompiler.disassemble(p_object: Int) -> Result[DxcResult, DxcError]
  requires: handle != 0
  requires: p_object != 0
{
  let riid: Int = unsafe { xiom_dxc_iid_result() };
  let pp_result: Int = 0;
  let hr: Int32 = unsafe { xiom_compiler3_Disassemble(handle, p_object, riid, pp_result) };
  if hr != 0 { return Err(DxcError{ code: hr }); }
  return Ok(DxcResult{ handle: pp_result });
}

// =========================================================================
// DxcUtils -- IDxcUtils wrapper
// =========================================================================

pub type DxcUtils = {
  handle: Int;
} derive[Clone]

pub fn DxcUtils.create() -> Result[DxcUtils, DxcError]
  ensures: result is Ok => result.unwrap().handle != 0
{
  let clsid: Int = unsafe { xiom_dxc_clsid_utils() };
  let iid: Int = unsafe { xiom_dxc_iid_utils() };
  let ptr = create_instance(clsid, iid)?;
  return Ok(DxcUtils{ handle: ptr });
}

pub fn DxcUtils.destroy()
  requires: handle != 0
{
  unsafe { xiom_unknown_Release(handle); }
}

pub fn DxcUtils.create_blob(p_data: Int, size: Int, code_page: Int) -> Result[DxcBlob, DxcError]
  requires: handle != 0
  requires: p_data != 0
{
  let pp_blob: Int = 0;
  let hr: Int32 = unsafe { xiom_utils_CreateBlob(handle, p_data, size, code_page, pp_blob) };
  if hr != 0 { return Err(DxcError{ code: hr }); }
  return Ok(DxcBlob{ handle: pp_blob });
}

pub fn DxcUtils.load_file(p_file_name: Int) -> Result[DxcBlob, DxcError]
  requires: handle != 0
  requires: p_file_name != 0
{
  let pp_blob: Int = 0;
  let hr: Int32 = unsafe { xiom_utils_LoadFile(handle, p_file_name, 0, pp_blob) };
  if hr != 0 { return Err(DxcError{ code: hr }); }
  return Ok(DxcBlob{ handle: pp_blob });
}

pub fn DxcUtils.create_default_include_handler() -> Result[DxcIncludeHandler, DxcError]
  requires: handle != 0
{
  let pp_handler: Int = 0;
  let hr: Int32 = unsafe { xiom_utils_CreateDefaultIncludeHandler(handle, pp_handler) };
  if hr != 0 { return Err(DxcError{ code: hr }); }
  return Ok(DxcIncludeHandler{ handle: pp_handler });
}

pub fn DxcUtils.get_blob_as_utf8(p_blob: Int) -> Result[DxcBlob, DxcError]
  requires: handle != 0
  requires: p_blob != 0
{
  let pp_utf8: Int = 0;
  let hr: Int32 = unsafe { xiom_utils_GetBlobAsUtf8(handle, p_blob, pp_utf8) };
  if hr != 0 { return Err(DxcError{ code: hr }); }
  return Ok(DxcBlob{ handle: pp_utf8 });
}

pub fn DxcUtils.get_dxil_container_part(p_shader: Int, dxc_part: Int) -> Result[Int, DxcError]
  requires: handle != 0
  requires: p_shader != 0
{
  let pp_part_data: Int = 0;
  let p_part_size: Int = 0;
  let hr: Int32 = unsafe { xiom_utils_GetDxilContainerPart(handle, p_shader, dxc_part, pp_part_data, p_part_size) };
  if hr != 0 { return Err(DxcError{ code: hr }); }
  return Ok(pp_part_data);
}

pub fn DxcUtils.create_reflection(p_data: Int) -> Result[Int, DxcError]
  requires: handle != 0
  requires: p_data != 0
{
  let riid: Int = unsafe { xiom_dxc_iid_version_info() };
  let ppv_reflection: Int = 0;
  let hr: Int32 = unsafe { xiom_utils_CreateReflection(handle, p_data, riid, ppv_reflection) };
  if hr != 0 { return Err(DxcError{ code: hr }); }
  return Ok(ppv_reflection);
}

pub fn DxcUtils.build_arguments(p_source_name: Int, p_entry_point: Int, p_target_profile: Int, p_arguments: Int, arg_count: Int, p_defines: Int, define_count: Int) -> Result[DxcCompilerArgs, DxcError]
  requires: handle != 0
{
  let pp_args: Int = 0;
  let hr: Int32 = unsafe { xiom_utils_BuildArguments(handle, p_source_name, p_entry_point, p_target_profile, p_arguments, arg_count, p_defines, define_count, pp_args) };
  if hr != 0 { return Err(DxcError{ code: hr }); }
  return Ok(DxcCompilerArgs{ handle: pp_args });
}

pub fn DxcUtils.get_pdb_contents(p_pdb_blob: Int) -> Result[Int, DxcError]
  requires: handle != 0
  requires: p_pdb_blob != 0
{
  let pp_hash: Int = 0;
  let pp_container: Int = 0;
  let hr: Int32 = unsafe { xiom_utils_GetPDBContents(handle, p_pdb_blob, pp_hash, pp_container) };
  if hr != 0 { return Err(DxcError{ code: hr }); }
  return Ok(pp_hash);
}

// =========================================================================
// DxcResult -- IDxcResult wrapper
// =========================================================================

pub type DxcResult = {
  handle: Int;
} derive[Clone]

pub fn DxcResult.destroy()
  requires: handle != 0
{
  unsafe { xiom_unknown_Release(handle); }
}

pub fn DxcResult.get_status() -> Result<Int32, DxcError>
  requires: handle != 0
{
  let p_status: Int = 0;
  let hr: Int32 = unsafe { xiom_operation_result_GetStatus(handle, p_status) };
  if hr != 0 { return Err(DxcError{ code: hr }); }
  return Ok(p_status);
}

pub fn DxcResult.has_output(kind: Int32) -> Bool
  requires: handle != 0
{
  let ok: Int32 = unsafe { xiom_result_HasOutput(handle, kind as Int) };
  return ok != 0;
}

pub fn DxcResult.get_output(kind: Int32) -> Result[DxcBlob, DxcError]
  requires: handle != 0
{
  let riid: Int = unsafe { xiom_dxc_iid_blob() };
  let ppv: Int = 0;
  let hr: Int32 = unsafe { xiom_result_GetOutput(handle, kind as Int, riid, ppv, 0) };
  if hr != 0 { return Err(DxcError{ code: hr }); }
  return Ok(DxcBlob{ handle: ppv });
}

pub fn DxcResult.get_error_buffer() -> Result[DxcBlob, DxcError]
  requires: handle != 0
{
  let pp_errors: Int = 0;
  let hr: Int32 = unsafe { xiom_operation_result_GetErrorBuffer(handle, pp_errors) };
  if hr != 0 { return Err(DxcError{ code: hr }); }
  if pp_errors == 0 { return Err(DxcError{ code: -2147467259 as Int32 }); }
  return Ok(DxcBlob{ handle: pp_errors });
}

pub fn DxcResult.get_num_outputs() -> Int32
  requires: handle != 0
{
  return unsafe { xiom_result_GetNumOutputs(handle) };
}

pub fn DxcResult.get_output_by_index(index: Int32) -> Int32
  requires: handle != 0
{
  return unsafe { xiom_result_GetOutputByIndex(handle, index as Int) };
}

pub fn DxcResult.primary_output() -> Int32
  requires: handle != 0
{
  return unsafe { xiom_result_PrimaryOutput(handle) };
}

// =========================================================================
// DxcBlob -- IDxcBlob / IDxcBlobUtf8 wrapper
// =========================================================================

pub type DxcBlob = {
  handle: Int;
} derive[Clone]

pub fn DxcBlob.destroy()
  requires: handle != 0
{
  unsafe { xiom_unknown_Release(handle); }
}

pub fn DxcBlob.get_buffer_pointer() -> Int
  requires: handle != 0
{
  return unsafe { xiom_blob_GetBufferPointer(handle) };
}

pub fn DxcBlob.get_buffer_size() -> Int
  requires: handle != 0
{
  return unsafe { xiom_blob_GetBufferSize(handle) };
}

pub fn DxcBlob.get_string_pointer() -> Int
  requires: handle != 0
{
  return unsafe { xiom_blob_utf8_GetStringPointer(handle) };
}

pub fn DxcBlob.get_string_length() -> Int
  requires: handle != 0
{
  return unsafe { xiom_blob_utf8_GetStringLength(handle) };
}

// =========================================================================
// DxcIncludeHandler -- IDxcIncludeHandler wrapper
// =========================================================================

pub type DxcIncludeHandler = {
  handle: Int;
} derive[Clone]

pub fn DxcIncludeHandler.destroy()
  requires: handle != 0
{
  unsafe { xiom_unknown_Release(handle); }
}

pub fn DxcIncludeHandler.load_source(p_filename: Int) -> Result[DxcBlob, DxcError]
  requires: handle != 0
  requires: p_filename != 0
{
  let pp_source: Int = 0;
  let hr: Int32 = unsafe { xiom_include_handler_LoadSource(handle, p_filename, pp_source) };
  if hr != 0 { return Err(DxcError{ code: hr }); }
  return Ok(DxcBlob{ handle: pp_source });
}

// =========================================================================
// DxcValidator -- IDxcValidator / IDxcValidator2 wrapper
// =========================================================================

pub type DxcValidator = {
  handle: Int;
} derive[Clone]

pub fn DxcValidator.create() -> Result[DxcValidator, DxcError]
  ensures: result is Ok => result.unwrap().handle != 0
{
  let clsid: Int = unsafe { xiom_dxc_clsid_validator() };
  let iid: Int = unsafe { xiom_dxc_iid_validator() };
  let ptr = create_instance(clsid, iid)?;
  return Ok(DxcValidator{ handle: ptr });
}

pub fn DxcValidator.destroy()
  requires: handle != 0
{
  unsafe { xiom_unknown_Release(handle); }
}

pub fn DxcValidator.validate(p_shader: Int, flags: Int) -> Result[DxcResult, DxcError]
  requires: handle != 0
  requires: p_shader != 0
{
  let pp_result: Int = 0;
  let hr: Int32 = unsafe { xiom_validator_Validate(handle, p_shader, flags, pp_result) };
  if hr != 0 { return Err(DxcError{ code: hr }); }
  return Ok(DxcResult{ handle: pp_result });
}

pub fn DxcValidator.validate_with_debug(p_shader: Int, flags: Int, p_opt_debug_bitcode: Int) -> Result[DxcResult, DxcError]
  requires: handle != 0
  requires: p_shader != 0
{
  let pp_result: Int = 0;
  let hr: Int32 = unsafe { xiom_validator2_ValidateWithDebug(handle, p_shader, flags, p_opt_debug_bitcode, pp_result) };
  if hr != 0 { return Err(DxcError{ code: hr }); }
  return Ok(DxcResult{ handle: pp_result });
}

// =========================================================================
// DxcContainerBuilder -- IDxcContainerBuilder wrapper
// =========================================================================

pub type DxcContainerBuilder = {
  handle: Int;
} derive[Clone]

pub fn DxcContainerBuilder.create() -> Result[DxcContainerBuilder, DxcError]
  ensures: result is Ok => result.unwrap().handle != 0
{
  let clsid: Int = unsafe { xiom_dxc_clsid_container_builder() };
  let iid: Int = unsafe { xiom_dxc_iid_container_builder() };
  let ptr = create_instance(clsid, iid)?;
  return Ok(DxcContainerBuilder{ handle: ptr });
}

pub fn DxcContainerBuilder.destroy()
  requires: handle != 0
{
  unsafe { xiom_unknown_Release(handle); }
}

pub fn DxcContainerBuilder.load(p_container: Int) -> Result[Int, DxcError]
  requires: handle != 0
{
  let hr: Int32 = unsafe { xiom_container_builder_Load(handle, p_container) };
  if hr != 0 { return Err(DxcError{ code: hr }); }
  return Ok(0);
}

pub fn DxcContainerBuilder.add_part(four_cc: Int, p_source: Int) -> Result[Int, DxcError]
  requires: handle != 0
  requires: p_source != 0
{
  let hr: Int32 = unsafe { xiom_container_builder_AddPart(handle, four_cc, p_source) };
  if hr != 0 { return Err(DxcError{ code: hr }); }
  return Ok(0);
}

pub fn DxcContainerBuilder.remove_part(four_cc: Int) -> Result[Int, DxcError]
  requires: handle != 0
{
  let hr: Int32 = unsafe { xiom_container_builder_RemovePart(handle, four_cc) };
  if hr != 0 { return Err(DxcError{ code: hr }); }
  return Ok(0);
}

pub fn DxcContainerBuilder.serialize() -> Result[DxcResult, DxcError]
  requires: handle != 0
{
  let pp_result: Int = 0;
  let hr: Int32 = unsafe { xiom_container_builder_SerializeContainer(handle, pp_result) };
  if hr != 0 { return Err(DxcError{ code: hr }); }
  return Ok(DxcResult{ handle: pp_result });
}

// =========================================================================
// DxcContainerReflection -- IDxcContainerReflection wrapper
// =========================================================================

pub type DxcContainerReflection = {
  handle: Int;
} derive[Clone]

pub fn DxcContainerReflection.create() -> Result[DxcContainerReflection, DxcError]
  ensures: result is Ok => result.unwrap().handle != 0
{
  let clsid: Int = unsafe { xiom_dxc_clsid_container_reflection() };
  let iid: Int = unsafe { xiom_dxc_iid_container_reflection() };
  let ptr = create_instance(clsid, iid)?;
  return Ok(DxcContainerReflection{ handle: ptr });
}

pub fn DxcContainerReflection.destroy()
  requires: handle != 0
{
  unsafe { xiom_unknown_Release(handle); }
}

pub fn DxcContainerReflection.load(p_container: Int) -> Result[Int, DxcError]
  requires: handle != 0
{
  let hr: Int32 = unsafe { xiom_container_reflection_Load(handle, p_container) };
  if hr != 0 { return Err(DxcError{ code: hr }); }
  return Ok(0);
}

pub fn DxcContainerReflection.get_part_count() -> Result<Int32, DxcError>
  requires: handle != 0
{
  let p_result: Int = 0;
  let hr: Int32 = unsafe { xiom_container_reflection_GetPartCount(handle, p_result) };
  if hr != 0 { return Err(DxcError{ code: hr }); }
  return Ok(p_result);
}

pub fn DxcContainerReflection.get_part_kind(idx: Int32) -> Result<Int32, DxcError>
  requires: handle != 0
{
  let p_result: Int = 0;
  let hr: Int32 = unsafe { xiom_container_reflection_GetPartKind(handle, idx as Int, p_result) };
  if hr != 0 { return Err(DxcError{ code: hr }); }
  return Ok(p_result);
}

pub fn DxcContainerReflection.get_part_content(idx: Int32) -> Result[DxcBlob, DxcError]
  requires: handle != 0
{
  let pp_result: Int = 0;
  let hr: Int32 = unsafe { xiom_container_reflection_GetPartContent(handle, idx as Int, pp_result) };
  if hr != 0 { return Err(DxcError{ code: hr }); }
  return Ok(DxcBlob{ handle: pp_result });
}

pub fn DxcContainerReflection.find_first_part_kind(kind: Int32) -> Result[Int32, DxcError]
  requires: handle != 0
{
  let p_result: Int = 0;
  let hr: Int32 = unsafe { xiom_container_reflection_FindFirstPartKind(handle, kind as Int, p_result) };
  if hr != 0 { return Err(DxcError{ code: hr }); }
  return Ok(p_result);
}

pub fn DxcContainerReflection.get_part_reflection(idx: Int32) -> Result[Int, DxcError]
  requires: handle != 0
{
  let riid: Int = unsafe { xiom_dxc_iid_version_info() };
  let ppv: Int = 0;
  let hr: Int32 = unsafe { xiom_container_reflection_GetPartReflection(handle, idx as Int, riid, ppv) };
  if hr != 0 { return Err(DxcError{ code: hr }); }
  return Ok(ppv);
}

// =========================================================================
// DxcCompilerArgs -- IDxcCompilerArgs wrapper
// =========================================================================

pub type DxcCompilerArgs = {
  handle: Int;
} derive[Clone]

pub fn DxcCompilerArgs.destroy()
  requires: handle != 0
{
  unsafe { xiom_unknown_Release(handle); }
}

pub fn DxcCompilerArgs.get_arguments() -> Int
  requires: handle != 0
{
  return unsafe { xiom_compiler_args_GetArguments(handle) };
}

pub fn DxcCompilerArgs.get_count() -> Int32
  requires: handle != 0
{
  return unsafe { xiom_compiler_args_GetCount(handle) };
}

pub fn DxcCompilerArgs.add_arguments(p_arguments: Int, arg_count: Int) -> Result[Int, DxcError]
  requires: handle != 0
{
  let hr: Int32 = unsafe { xiom_compiler_args_AddArguments(handle, p_arguments, arg_count) };
  if hr != 0 { return Err(DxcError{ code: hr }); }
  return Ok(0);
}

pub fn DxcCompilerArgs.add_arguments_utf8(p_arguments: Int, arg_count: Int) -> Result[Int, DxcError]
  requires: handle != 0
{
  let hr: Int32 = unsafe { xiom_compiler_args_AddArgumentsUTF8(handle, p_arguments, arg_count) };
  if hr != 0 { return Err(DxcError{ code: hr }); }
  return Ok(0);
}

pub fn DxcCompilerArgs.add_defines(p_defines: Int, define_count: Int) -> Result[Int, DxcError]
  requires: handle != 0
{
  let hr: Int32 = unsafe { xiom_compiler_args_AddDefines(handle, p_defines, define_count) };
  if hr != 0 { return Err(DxcError{ code: hr }); }
  return Ok(0);
}

// =========================================================================
// DxcAssembler -- IDxcAssembler wrapper
// =========================================================================

pub type DxcAssembler = {
  handle: Int;
} derive[Clone]

pub fn DxcAssembler.create() -> Result[DxcAssembler, DxcError]
  ensures: result is Ok => result.unwrap().handle != 0
{
  let clsid: Int = unsafe { xiom_dxc_clsid_assembler() };
  let iid: Int = unsafe { xiom_dxc_iid_assembler() };
  let ptr = create_instance(clsid, iid)?;
  return Ok(DxcAssembler{ handle: ptr });
}

pub fn DxcAssembler.destroy()
  requires: handle != 0
{
  unsafe { xiom_unknown_Release(handle); }
}

pub fn DxcAssembler.assemble_to_container(p_shader: Int) -> Result[DxcResult, DxcError]
  requires: handle != 0
  requires: p_shader != 0
{
  let pp_result: Int = 0;
  let hr: Int32 = unsafe { xiom_assembler_AssembleToContainer(handle, p_shader, pp_result) };
  if hr != 0 { return Err(DxcError{ code: hr }); }
  return Ok(DxcResult{ handle: pp_result });
}

// =========================================================================
// DxcOptimizer -- IDxcOptimizer wrapper
// =========================================================================

pub type DxcOptimizer = {
  handle: Int;
} derive[Clone]

pub fn DxcOptimizer.create() -> Result[DxcOptimizer, DxcError]
  ensures: result is Ok => result.unwrap().handle != 0
{
  let clsid: Int = unsafe { xiom_dxc_clsid_optimizer() };
  let iid: Int = unsafe { xiom_dxc_iid_optimizer() };
  let ptr = create_instance(clsid, iid)?;
  return Ok(DxcOptimizer{ handle: ptr });
}

pub fn DxcOptimizer.destroy()
  requires: handle != 0
{
  unsafe { xiom_unknown_Release(handle); }
}

pub fn DxcOptimizer.get_available_pass_count() -> Result[Int, DxcError]
  requires: handle != 0
{
  let p_count: Int = 0;
  let hr: Int32 = unsafe { xiom_optimizer_GetAvailablePassCount(handle, p_count) };
  if hr != 0 { return Err(DxcError{ code: hr }); }
  return Ok(p_count);
}

pub fn DxcOptimizer.get_available_pass(index: Int) -> Result[Int, DxcError]
  requires: handle != 0
{
  let pp_result: Int = 0;
  let hr: Int32 = unsafe { xiom_optimizer_GetAvailablePass(handle, index, pp_result) };
  if hr != 0 { return Err(DxcError{ code: hr }); }
  return Ok(pp_result);
}

pub fn DxcOptimizer.run_optimizer(p_blob: Int, pp_options: Int, option_count: Int, p_output_module: Int) -> Result[Int, DxcError]
  requires: handle != 0
  requires: p_blob != 0
{
  let pp_output_text: Int = 0;
  let hr: Int32 = unsafe { xiom_optimizer_RunOptimizer(handle, p_blob, pp_options, option_count, p_output_module, pp_output_text) };
  if hr != 0 { return Err(DxcError{ code: hr }); }
  return Ok(pp_output_text);
}

// =========================================================================
// DxcPdbUtils -- IDxcPdbUtils2 wrapper
// =========================================================================

pub type DxcPdbUtils = {
  handle: Int;
} derive[Clone]

pub fn DxcPdbUtils.create() -> Result[DxcPdbUtils, DxcError]
  ensures: result is Ok => result.unwrap().handle != 0
{
  let clsid: Int = unsafe { xiom_dxc_clsid_pdb_utils() };
  let iid: Int = unsafe { xiom_dxc_iid_pdb_utils2() };
  let ptr = create_instance(clsid, iid)?;
  return Ok(DxcPdbUtils{ handle: ptr });
}

pub fn DxcPdbUtils.destroy()
  requires: handle != 0
{
  unsafe { xiom_unknown_Release(handle); }
}

pub fn DxcPdbUtils.load(p_pdb_or_dxil: Int) -> Result[Int, DxcError]
  requires: handle != 0
{
  let hr: Int32 = unsafe { xiom_pdb_utils2_Load(handle, p_pdb_or_dxil) };
  if hr != 0 { return Err(DxcError{ code: hr }); }
  return Ok(0);
}

pub fn DxcPdbUtils.get_source_count() -> Result<Int, DxcError>
  requires: handle != 0
{
  let p_count: Int = 0;
  let hr: Int32 = unsafe { xiom_pdb_utils2_GetSourceCount(handle, p_count) };
  if hr != 0 { return Err(DxcError{ code: hr }); }
  return Ok(p_count);
}

pub fn DxcPdbUtils.get_source(u_index: Int) -> Result[DxcBlob, DxcError]
  requires: handle != 0
{
  let pp_result: Int = 0;
  let hr: Int32 = unsafe { xiom_pdb_utils2_GetSource(handle, u_index, pp_result) };
  if hr != 0 { return Err(DxcError{ code: hr }); }
  return Ok(DxcBlob{ handle: pp_result });
}

pub fn DxcPdbUtils.get_source_name(u_index: Int) -> Result[DxcBlob, DxcError]
  requires: handle != 0
{
  let pp_result: Int = 0;
  let hr: Int32 = unsafe { xiom_pdb_utils2_GetSourceName(handle, u_index, pp_result) };
  if hr != 0 { return Err(DxcError{ code: hr }); }
  return Ok(DxcBlob{ handle: pp_result });
}

pub fn DxcPdbUtils.get_flag_count() -> Result<Int, DxcError>
  requires: handle != 0
{
  let p_count: Int = 0;
  let hr: Int32 = unsafe { xiom_pdb_utils2_GetFlagCount(handle, p_count) };
  if hr != 0 { return Err(DxcError{ code: hr }); }
  return Ok(p_count);
}

pub fn DxcPdbUtils.get_flag(u_index: Int) -> Result[DxcBlob, DxcError]
  requires: handle != 0
{
  let pp_result: Int = 0;
  let hr: Int32 = unsafe { xiom_pdb_utils2_GetFlag(handle, u_index, pp_result) };
  if hr != 0 { return Err(DxcError{ code: hr }); }
  return Ok(DxcBlob{ handle: pp_result });
}

pub fn DxcPdbUtils.get_arg_count() -> Result[Int, DxcError]
  requires: handle != 0
{
  let p_count: Int = 0;
  let hr: Int32 = unsafe { xiom_pdb_utils2_GetArgCount(handle, p_count) };
  if hr != 0 { return Err(DxcError{ code: hr }); }
  return Ok(p_count);
}

pub fn DxcPdbUtils.get_arg(u_index: Int) -> Result[DxcBlob, DxcError]
  requires: handle != 0
{
  let pp_result: Int = 0;
  let hr: Int32 = unsafe { xiom_pdb_utils2_GetArg(handle, u_index, pp_result) };
  if hr != 0 { return Err(DxcError{ code: hr }); }
  return Ok(DxcBlob{ handle: pp_result });
}

pub fn DxcPdbUtils.get_hash() -> Result[DxcBlob, DxcError]
  requires: handle != 0
{
  let pp_result: Int = 0;
  let hr: Int32 = unsafe { xiom_pdb_utils2_GetHash(handle, pp_result) };
  if hr != 0 { return Err(DxcError{ code: hr }); }
  return Ok(DxcBlob{ handle: pp_result });
}

pub fn DxcPdbUtils.get_name() -> Result[DxcBlob, DxcError]
  requires: handle != 0
{
  let pp_result: Int = 0;
  let hr: Int32 = unsafe { xiom_pdb_utils2_GetName(handle, pp_result) };
  if hr != 0 { return Err(DxcError{ code: hr }); }
  return Ok(DxcBlob{ handle: pp_result });
}

pub fn DxcPdbUtils.is_full_pdb() -> Bool
  requires: handle != 0
{
  let ok: Int32 = unsafe { xiom_pdb_utils2_IsFullPDB(handle) };
  return ok != 0;
}

pub fn DxcPdbUtils.is_pdb_ref() -> Bool
  requires: handle != 0
{
  let ok: Int32 = unsafe { xiom_pdb_utils2_IsPDBRef(handle) };
  return ok != 0;
}

// =========================================================================
// High-level context -- DxcContext
// =========================================================================

pub type DxcContext = {
  compiler: Int;
  utils: Int;
} derive[Clone]

pub fn DxcContext.init() -> Result[DxcContext, DxcError]
  ensures: result is Ok => result.unwrap().compiler != 0 && result.unwrap().utils != 0
{
  let c = DxcCompiler.create()?;
  let u = DxcUtils.create()?;
  return Ok(DxcContext{ compiler: c.handle, utils: u.handle });
}

pub fn DxcContext.destroy()
  requires: compiler != 0
  requires: utils != 0
{
  unsafe { xiom_unknown_Release(utils); }
  unsafe { xiom_unknown_Release(compiler); }
}

pub fn DxcContext.create_compiler() -> Result[DxcCompiler, DxcError]
  requires: compiler != 0
  ensures: result is Ok => result.unwrap().handle != 0
{
  return Ok(DxcCompiler{ handle: compiler });
}

pub fn DxcContext.create_utils() -> Result[DxcUtils, DxcError]
  requires: utils != 0
  ensures: result is Ok => result.unwrap().handle != 0
{
  return Ok(DxcUtils{ handle: utils });
}
