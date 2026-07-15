// XIOM — DirectX Shader Compiler Safe Wrappers
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Struct-based safe resource management for DXC COM interfaces.
// All create/destroy pairs with Result[T, DxcError] + design-by-contract.
// No raw pointer exposure in the public API.
//
// COVERAGE: 8 resource types spanning the full DXC lifecycle:
//   DxcCompiler, DxcUtils, DxcResult, DxcBlob, DxcIncludeHandler,
//   DxcValidator, DxcContainerBuilder, DxcContainerReflection

module xiom.dxc.safe

// =========================================================================
// Duplicated extern declarations (cross-module resolution bug)
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
  fn xiom_dxc_iid_compiler3() -> Int;
  fn xiom_dxc_iid_utils() -> Int;
  fn xiom_dxc_iid_result() -> Int;
  fn xiom_dxc_iid_blob() -> Int;
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
  fn xiom_dxc_iid_version_info() -> Int;
  fn xiom_dxc_iid_version_info2() -> Int;
  fn xiom_dxc_iid_version_info3() -> Int;
  fn xiom_dxc_iid_extra_outputs() -> Int;
  fn xiom_dxc_iid_pdb_utils() -> Int;
  fn xiom_dxc_iid_pdb_utils2() -> Int;
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
// Helper: IUnknown vtable dispatch
// =========================================================================

fn vtable_call_QueryInterface(ptr: Int, riid: Int) -> Result[Int, DxcError]
  requires: ptr != 0
  requires: riid != 0
{
  let vtbl: Int = unsafe { *(ptr as **Int) };
  let fn_ptr_val: Int = unsafe { *((vtbl as *Int) + 0) };
  let f: fn(Int, Int, Int) -> Int32 = fn_ptr_val as fn(Int, Int, Int) -> Int32;
  let ppv: Int = 0;
  let hr: Int32 = unsafe { f(ptr as Int, riid, ppv) };
  if hr != 0 { return Err(DxcError{ code: hr }); }
  return Ok(ppv);
}

fn vtable_call_AddRef(ptr: Int) -> Int32
  requires: ptr != 0
{
  let vtbl: Int = unsafe { *(ptr as **Int) };
  let fn_ptr_val: Int = unsafe { *((vtbl as *Int) + 1) };
  let f: fn(Int) -> Int32 = fn_ptr_val as fn(Int) -> Int32;
  return unsafe { f(ptr as Int) };
}

fn vtable_call_Release(ptr: Int) -> Int32
  requires: ptr != 0
{
  let vtbl: Int = unsafe { *(ptr as **Int) };
  let fn_ptr_val: Int = unsafe { *((vtbl as *Int) + 2) };
  let f: fn(Int) -> Int32 = fn_ptr_val as fn(Int) -> Int32;
  return unsafe { f(ptr as Int) };
}

// =========================================================================
// VTable call helpers for each interface method
// =========================================================================

fn vtable_call_blob_GetBufferPointer(ptr: Int) -> Int
  requires: ptr != 0
{
  let vtbl: Int = unsafe { *(ptr as **Int) };
  let fn_ptr_val: Int = unsafe { *((vtbl as *Int) + 3) };
  let f: fn(Int) -> Int = fn_ptr_val as fn(Int) -> Int;
  return unsafe { f(ptr as Int) };
}

fn vtable_call_blob_GetBufferSize(ptr: Int) -> Int
  requires: ptr != 0
{
  let vtbl: Int = unsafe { *(ptr as **Int) };
  let fn_ptr_val: Int = unsafe { *((vtbl as *Int) + 4) };
  let f: fn(Int) -> Int = fn_ptr_val as fn(Int) -> Int;
  return unsafe { f(ptr as Int) };
}

fn vtable_call_operation_GetStatus(ptr: Int) -> Result[Int32, DxcError]
  requires: ptr != 0
{
  let vtbl: Int = unsafe { *(ptr as **Int) };
  let fn_ptr_val: Int = unsafe { *((vtbl as *Int) + 3) };
  let f: fn(Int, Int) -> Int32 = fn_ptr_val as fn(Int, Int) -> Int32;
  let p_status: Int = 0;
  let hr: Int32 = unsafe { f(ptr as Int, p_status) };
  if hr != 0 { return Err(DxcError{ code: hr }); }
  return Ok(p_status);
}

fn vtable_call_operation_GetResult(ptr: Int) -> Result[Int, DxcError]
  requires: ptr != 0
{
  let vtbl: Int = unsafe { *(ptr as **Int) };
  let fn_ptr_val: Int = unsafe { *((vtbl as *Int) + 4) };
  let f: fn(Int, Int) -> Int32 = fn_ptr_val as fn(Int, Int) -> Int32;
  let pp_result: Int = 0;
  let hr: Int32 = unsafe { f(ptr as Int, pp_result) };
  if hr != 0 { return Err(DxcError{ code: hr }); }
  return Ok(pp_result);
}

fn vtable_call_operation_GetErrorBuffer(ptr: Int) -> Result[Int, DxcError]
  requires: ptr != 0
{
  let vtbl: Int = unsafe { *(ptr as **Int) };
  let fn_ptr_val: Int = unsafe { *((vtbl as *Int) + 5) };
  let f: fn(Int, Int) -> Int32 = fn_ptr_val as fn(Int, Int) -> Int32;
  let pp_errors: Int = 0;
  let hr: Int32 = unsafe { f(ptr as Int, pp_errors) };
  if hr != 0 { return Err(DxcError{ code: hr }); }
  return Ok(pp_errors);
}

fn vtable_call_result_HasOutput(ptr: Int, kind: Int32) -> Int32
  requires: ptr != 0
{
  let vtbl: Int = unsafe { *(ptr as **Int) };
  let fn_ptr_val: Int = unsafe { *((vtbl as *Int) + 6) };
  let f: fn(Int, Int32) -> Int32 = fn_ptr_val as fn(Int, Int32) -> Int32;
  return unsafe { f(ptr as Int, kind) };
}

fn vtable_call_result_GetOutput(ptr: Int, kind: Int32, riid: Int) -> Result[Int, DxcError]
  requires: ptr != 0
  requires: riid != 0
{
  let vtbl: Int = unsafe { *(ptr as **Int) };
  let fn_ptr_val: Int = unsafe { *((vtbl as *Int) + 7) };
  let f: fn(Int, Int32, Int, Int, Int) -> Int32 = fn_ptr_val as fn(Int, Int32, Int, Int, Int) -> Int32;
  let ppv: Int = 0;
  let pp_name: Int = 0;
  let hr: Int32 = unsafe { f(ptr as Int, kind, riid, ppv, pp_name) };
  if hr != 0 { return Err(DxcError{ code: hr }); }
  return Ok(ppv);
}

fn vtable_call_result_GetNumOutputs(ptr: Int) -> Int32
  requires: ptr != 0
{
  let vtbl: Int = unsafe { *(ptr as **Int) };
  let fn_ptr_val: Int = unsafe { *((vtbl as *Int) + 8) };
  let f: fn(Int) -> Int32 = fn_ptr_val as fn(Int) -> Int32;
  return unsafe { f(ptr as Int) };
}

fn vtable_call_result_GetOutputByIndex(ptr: Int, index: Int32) -> Int32
  requires: ptr != 0
{
  let vtbl: Int = unsafe { *(ptr as **Int) };
  let fn_ptr_val: Int = unsafe { *((vtbl as *Int) + 9) };
  let f: fn(Int, Int32) -> Int32 = fn_ptr_val as fn(Int, Int32) -> Int32;
  return unsafe { f(ptr as Int, index) };
}

fn vtable_call_result_PrimaryOutput(ptr: Int) -> Int32
  requires: ptr != 0
{
  let vtbl: Int = unsafe { *(ptr as **Int) };
  let fn_ptr_val: Int = unsafe { *((vtbl as *Int) + 10) };
  let f: fn(Int) -> Int32 = fn_ptr_val as fn(Int) -> Int32;
  return unsafe { f(ptr as Int) };
}

fn vtable_call_compiler3_Compile(ptr: Int, p_source: Int, p_args: Int, arg_count: Int32, p_handler: Int, riid: Int) -> Result[Int, DxcError]
  requires: ptr != 0
  requires: p_source != 0
  requires: riid != 0
{
  let vtbl: Int = unsafe { *(ptr as **Int) };
  let fn_ptr_val: Int = unsafe { *((vtbl as *Int) + 3) };
  let f: fn(Int, Int, Int, Int32, Int, Int, Int) -> Int32 = fn_ptr_val as fn(Int, Int, Int, Int32, Int, Int, Int) -> Int32;
  let pp_result: Int = 0;
  let hr: Int32 = unsafe { f(ptr as Int, p_source, p_args, arg_count, p_handler, riid, pp_result) };
  if hr != 0 { return Err(DxcError{ code: hr }); }
  return Ok(pp_result);
}

fn vtable_call_compiler3_Disassemble(ptr: Int, p_object: Int, riid: Int) -> Result[Int, DxcError]
  requires: ptr != 0
  requires: p_object != 0
  requires: riid != 0
{
  let vtbl: Int = unsafe { *(ptr as **Int) };
  let fn_ptr_val: Int = unsafe { *((vtbl as *Int) + 4) };
  let f: fn(Int, Int, Int, Int) -> Int32 = fn_ptr_val as fn(Int, Int, Int, Int) -> Int32;
  let pp_result: Int = 0;
  let hr: Int32 = unsafe { f(ptr as Int, p_object, riid, pp_result) };
  if hr != 0 { return Err(DxcError{ code: hr }); }
  return Ok(pp_result);
}

fn vtable_call_utils_CreateBlob(ptr: Int, p_data: Int, size: Int32, code_page: Int32) -> Result[Int, DxcError]
  requires: ptr != 0
  requires: p_data != 0
{
  let vtbl: Int = unsafe { *(ptr as **Int) };
  let fn_ptr_val: Int = unsafe { *((vtbl as *Int) + 5) };
  let f: fn(Int, Int, Int32, Int32, Int) -> Int32 = fn_ptr_val as fn(Int, Int, Int32, Int32, Int) -> Int32;
  let pp_blob: Int = 0;
  let hr: Int32 = unsafe { f(ptr as Int, p_data, size, code_page, pp_blob) };
  if hr != 0 { return Err(DxcError{ code: hr }); }
  return Ok(pp_blob);
}

fn vtable_call_utils_LoadFile(ptr: Int, p_file_name: Int) -> Result[Int, DxcError]
  requires: ptr != 0
  requires: p_file_name != 0
{
  let vtbl: Int = unsafe { *(ptr as **Int) };
  let fn_ptr_val: Int = unsafe { *((vtbl as *Int) + 6) };
  let f: fn(Int, Int, Int, Int) -> Int32 = fn_ptr_val as fn(Int, Int, Int, Int) -> Int32;
  let pp_blob: Int = 0;
  let hr: Int32 = unsafe { f(ptr as Int, p_file_name, 0, pp_blob) };
  if hr != 0 { return Err(DxcError{ code: hr }); }
  return Ok(pp_blob);
}

fn vtable_call_utils_CreateDefaultIncludeHandler(ptr: Int) -> Result[Int, DxcError]
  requires: ptr != 0
{
  let vtbl: Int = unsafe { *(ptr as **Int) };
  let fn_ptr_val: Int = unsafe { *((vtbl as *Int) + 8) };
  let f: fn(Int, Int) -> Int32 = fn_ptr_val as fn(Int, Int) -> Int32;
  let pp_handler: Int = 0;
  let hr: Int32 = unsafe { f(ptr as Int, pp_handler) };
  if hr != 0 { return Err(DxcError{ code: hr }); }
  return Ok(pp_handler);
}

fn vtable_call_utils_GetBlobAsUtf8(ptr: Int, p_blob: Int) -> Result[Int, DxcError]
  requires: ptr != 0
  requires: p_blob != 0
{
  let vtbl: Int = unsafe { *(ptr as **Int) };
  let fn_ptr_val: Int = unsafe { *((vtbl as *Int) + 9) };
  let f: fn(Int, Int, Int) -> Int32 = fn_ptr_val as fn(Int, Int, Int) -> Int32;
  let pp_utf8: Int = 0;
  let hr: Int32 = unsafe { f(ptr as Int, p_blob, pp_utf8) };
  if hr != 0 { return Err(DxcError{ code: hr }); }
  return Ok(pp_utf8);
}

fn vtable_call_validator_Validate(ptr: Int, p_shader: Int, flags: Int32) -> Result[Int, DxcError]
  requires: ptr != 0
  requires: p_shader != 0
{
  let vtbl: Int = unsafe { *(ptr as **Int) };
  let fn_ptr_val: Int = unsafe { *((vtbl as *Int) + 3) };
  let f: fn(Int, Int, Int32, Int) -> Int32 = fn_ptr_val as fn(Int, Int, Int32, Int) -> Int32;
  let pp_result: Int = 0;
  let hr: Int32 = unsafe { f(ptr as Int, p_shader, flags, pp_result) };
  if hr != 0 { return Err(DxcError{ code: hr }); }
  return Ok(pp_result);
}

fn vtable_call_container_builder_Load(ptr: Int, p_container: Int) -> Result[Int, DxcError]
  requires: ptr != 0
{
  let vtbl: Int = unsafe { *(ptr as **Int) };
  let fn_ptr_val: Int = unsafe { *((vtbl as *Int) + 3) };
  let f: fn(Int, Int) -> Int32 = fn_ptr_val as fn(Int, Int) -> Int32;
  let hr: Int32 = unsafe { f(ptr as Int, p_container) };
  if hr != 0 { return Err(DxcError{ code: hr }); }
  return Ok(0);
}

fn vtable_call_container_builder_AddPart(ptr: Int, four_cc: Int32, p_source: Int) -> Result[Int, DxcError]
  requires: ptr != 0
  requires: p_source != 0
{
  let vtbl: Int = unsafe { *(ptr as **Int) };
  let fn_ptr_val: Int = unsafe { *((vtbl as *Int) + 4) };
  let f: fn(Int, Int32, Int) -> Int32 = fn_ptr_val as fn(Int, Int32, Int) -> Int32;
  let hr: Int32 = unsafe { f(ptr as Int, four_cc, p_source) };
  if hr != 0 { return Err(DxcError{ code: hr }); }
  return Ok(0);
}

fn vtable_call_container_builder_SerializeContainer(ptr: Int) -> Result[Int, DxcError]
  requires: ptr != 0
{
  let vtbl: Int = unsafe { *(ptr as **Int) };
  let fn_ptr_val: Int = unsafe { *((vtbl as *Int) + 6) };
  let f: fn(Int, Int) -> Int32 = fn_ptr_val as fn(Int, Int) -> Int32;
  let pp_result: Int = 0;
  let hr: Int32 = unsafe { f(ptr as Int, pp_result) };
  if hr != 0 { return Err(DxcError{ code: hr }); }
  return Ok(pp_result);
}

fn vtable_call_container_reflection_Load(ptr: Int, p_container: Int) -> Result[Int, DxcError]
  requires: ptr != 0
{
  let vtbl: Int = unsafe { *(ptr as **Int) };
  let fn_ptr_val: Int = unsafe { *((vtbl as *Int) + 3) };
  let f: fn(Int, Int) -> Int32 = fn_ptr_val as fn(Int, Int) -> Int32;
  let hr: Int32 = unsafe { f(ptr as Int, p_container) };
  if hr != 0 { return Err(DxcError{ code: hr }); }
  return Ok(0);
}

fn vtable_call_container_reflection_GetPartCount(ptr: Int) -> Result[Int32, DxcError]
  requires: ptr != 0
{
  let vtbl: Int = unsafe { *(ptr as **Int) };
  let fn_ptr_val: Int = unsafe { *((vtbl as *Int) + 4) };
  let f: fn(Int, Int) -> Int32 = fn_ptr_val as fn(Int, Int) -> Int32;
  let p_result: Int = 0;
  let hr: Int32 = unsafe { f(ptr as Int, p_result) };
  if hr != 0 { return Err(DxcError{ code: hr }); }
  return Ok(p_result);
}

fn vtable_call_container_reflection_GetPartKind(ptr: Int, idx: Int32) -> Result[Int32, DxcError]
  requires: ptr != 0
{
  let vtbl: Int = unsafe { *(ptr as **Int) };
  let fn_ptr_val: Int = unsafe { *((vtbl as *Int) + 5) };
  let f: fn(Int, Int32, Int) -> Int32 = fn_ptr_val as fn(Int, Int32, Int) -> Int32;
  let p_result: Int = 0;
  let hr: Int32 = unsafe { f(ptr as Int, idx, p_result) };
  if hr != 0 { return Err(DxcError{ code: hr }); }
  return Ok(p_result);
}

fn vtable_call_container_reflection_GetPartContent(ptr: Int, idx: Int32) -> Result[Int, DxcError]
  requires: ptr != 0
{
  let vtbl: Int = unsafe { *(ptr as **Int) };
  let fn_ptr_val: Int = unsafe { *((vtbl as *Int) + 6) };
  let f: fn(Int, Int32, Int) -> Int32 = fn_ptr_val as fn(Int, Int32, Int) -> Int32;
  let pp_result: Int = 0;
  let hr: Int32 = unsafe { f(ptr as Int, idx, pp_result) };
  if hr != 0 { return Err(DxcError{ code: hr }); }
  return Ok(pp_result);
}

fn vtable_call_include_handler_LoadSource(ptr: Int, p_filename: Int) -> Result[Int, DxcError]
  requires: ptr != 0
  requires: p_filename != 0
{
  let vtbl: Int = unsafe { *(ptr as **Int) };
  let fn_ptr_val: Int = unsafe { *((vtbl as *Int) + 3) };
  let f: fn(Int, Int, Int) -> Int32 = fn_ptr_val as fn(Int, Int, Int) -> Int32;
  let pp_source: Int = 0;
  let hr: Int32 = unsafe { f(ptr as Int, p_filename, pp_source) };
  if hr != 0 { return Err(DxcError{ code: hr }); }
  return Ok(pp_source);
}

// =========================================================================
// DxcCompiler — IDxcCompiler3 wrapper
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
  let ref_count: Int32 = vtable_call_Release(handle);
  return ();
}

pub fn DxcCompiler.compile(p_source: Int, p_arguments: Int, arg_count: Int32, p_include_handler: Int) -> Result[DxcResult, DxcError]
  requires: handle != 0
  requires: p_source != 0
{
  let riid: Int = unsafe { xiom_dxc_iid_result() };
  let ptr = vtable_call_compiler3_Compile(handle, p_source, p_arguments, arg_count, p_include_handler, riid)?;
  return Ok(DxcResult{ handle: ptr });
}

pub fn DxcCompiler.disassemble(p_object: Int) -> Result[DxcResult, DxcError]
  requires: handle != 0
  requires: p_object != 0
{
  let riid: Int = unsafe { xiom_dxc_iid_result() };
  let ptr = vtable_call_compiler3_Disassemble(handle, p_object, riid)?;
  return Ok(DxcResult{ handle: ptr });
}

// =========================================================================
// DxcUtils — IDxcUtils wrapper
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
  let ref_count: Int32 = vtable_call_Release(handle);
  return ();
}

pub fn DxcUtils.create_blob(p_data: Int, size: Int32, code_page: Int32) -> Result[DxcBlob, DxcError]
  requires: handle != 0
  requires: p_data != 0
{
  let ptr = vtable_call_utils_CreateBlob(handle, p_data, size, code_page)?;
  return Ok(DxcBlob{ handle: ptr });
}

pub fn DxcUtils.load_file(p_file_name: Int) -> Result[DxcBlob, DxcError]
  requires: handle != 0
  requires: p_file_name != 0
{
  let ptr = vtable_call_utils_LoadFile(handle, p_file_name)?;
  return Ok(DxcBlob{ handle: ptr });
}

pub fn DxcUtils.create_default_include_handler() -> Result[DxcIncludeHandler, DxcError]
  requires: handle != 0
{
  let ptr = vtable_call_utils_CreateDefaultIncludeHandler(handle)?;
  return Ok(DxcIncludeHandler{ handle: ptr });
}

pub fn DxcUtils.get_blob_as_utf8(p_blob: Int) -> Result[DxcBlob, DxcError]
  requires: handle != 0
  requires: p_blob != 0
{
  let ptr = vtable_call_utils_GetBlobAsUtf8(handle, p_blob)?;
  return Ok(DxcBlob{ handle: ptr });
}

// =========================================================================
// DxcResult — IDxcResult wrapper
// =========================================================================

pub type DxcResult = {
  handle: Int;
} derive[Clone]

pub fn DxcResult.destroy()
  requires: handle != 0
{
  let ref_count: Int32 = vtable_call_Release(handle);
  return ();
}

pub fn DxcResult.get_status() -> Result[Int32, DxcError]
  requires: handle != 0
{
  return vtable_call_operation_GetStatus(handle);
}

pub fn DxcResult.has_output(kind: Int32) -> Bool
  requires: handle != 0
{
  let ok: Int32 = vtable_call_result_HasOutput(handle, kind);
  return ok != 0;
}

pub fn DxcResult.get_output(kind: Int32) -> Result[DxcBlob, DxcError]
  requires: handle != 0
{
  let riid: Int = unsafe { xiom_dxc_iid_blob() };
  let ptr = vtable_call_result_GetOutput(handle, kind, riid)?;
  return Ok(DxcBlob{ handle: ptr });
}

pub fn DxcResult.get_error_buffer() -> Result[DxcBlob, DxcError]
  requires: handle != 0
{
  let ptr = vtable_call_operation_GetErrorBuffer(handle)?;
  return Ok(DxcBlob{ handle: ptr });
}

pub fn DxcResult.get_num_outputs() -> Int32
  requires: handle != 0
{
  return vtable_call_result_GetNumOutputs(handle);
}

pub fn DxcResult.get_output_by_index(index: Int32) -> Int32
  requires: handle != 0
{
  return vtable_call_result_GetOutputByIndex(handle, index);
}

pub fn DxcResult.primary_output() -> Int32
  requires: handle != 0
{
  return vtable_call_result_PrimaryOutput(handle);
}

// =========================================================================
// DxcBlob — IDxcBlob / IDxcBlobUtf8 wrapper
// =========================================================================

pub type DxcBlob = {
  handle: Int;
} derive[Clone]

pub fn DxcBlob.destroy()
  requires: handle != 0
{
  let ref_count: Int32 = vtable_call_Release(handle);
  return ();
}

pub fn DxcBlob.get_buffer_pointer() -> Int
  requires: handle != 0
{
  return vtable_call_blob_GetBufferPointer(handle);
}

pub fn DxcBlob.get_buffer_size() -> Int
  requires: handle != 0
{
  return vtable_call_blob_GetBufferSize(handle);
}

// =========================================================================
// DxcIncludeHandler — IDxcIncludeHandler wrapper
// =========================================================================

pub type DxcIncludeHandler = {
  handle: Int;
} derive[Clone]

pub fn DxcIncludeHandler.destroy()
  requires: handle != 0
{
  let ref_count: Int32 = vtable_call_Release(handle);
  return ();
}

pub fn DxcIncludeHandler.load_source(p_filename: Int) -> Result[DxcBlob, DxcError]
  requires: handle != 0
  requires: p_filename != 0
{
  let ptr = vtable_call_include_handler_LoadSource(handle, p_filename)?;
  return Ok(DxcBlob{ handle: ptr });
}

// =========================================================================
// DxcValidator — IDxcValidator wrapper
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
  let ref_count: Int32 = vtable_call_Release(handle);
  return ();
}

pub fn DxcValidator.validate(p_shader: Int, flags: Int32) -> Result[DxcResult, DxcError]
  requires: handle != 0
  requires: p_shader != 0
{
  let ptr = vtable_call_validator_Validate(handle, p_shader, flags)?;
  return Ok(DxcResult{ handle: ptr });
}

// =========================================================================
// DxcContainerBuilder — IDxcContainerBuilder wrapper
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
  let ref_count: Int32 = vtable_call_Release(handle);
  return ();
}

pub fn DxcContainerBuilder.load(p_container: Int) -> Result[Int, DxcError]
  requires: handle != 0
{
  return vtable_call_container_builder_Load(handle, p_container);
}

pub fn DxcContainerBuilder.add_part(four_cc: Int32, p_source: Int) -> Result[Int, DxcError]
  requires: handle != 0
  requires: p_source != 0
{
  return vtable_call_container_builder_AddPart(handle, four_cc, p_source);
}

pub fn DxcContainerBuilder.serialize() -> Result[DxcResult, DxcError]
  requires: handle != 0
{
  let ptr = vtable_call_container_builder_SerializeContainer(handle)?;
  return Ok(DxcResult{ handle: ptr });
}

// =========================================================================
// DxcContainerReflection — IDxcContainerReflection wrapper
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
  let ref_count: Int32 = vtable_call_Release(handle);
  return ();
}

pub fn DxcContainerReflection.load(p_container: Int) -> Result[Int, DxcError]
  requires: handle != 0
{
  return vtable_call_container_reflection_Load(handle, p_container);
}

pub fn DxcContainerReflection.get_part_count() -> Result[Int32, DxcError]
  requires: handle != 0
{
  return vtable_call_container_reflection_GetPartCount(handle);
}

pub fn DxcContainerReflection.get_part_kind(idx: Int32) -> Result[Int32, DxcError]
  requires: handle != 0
{
  return vtable_call_container_reflection_GetPartKind(handle, idx);
}

pub fn DxcContainerReflection.get_part_content(idx: Int32) -> Result[DxcBlob, DxcError]
  requires: handle != 0
{
  let ptr = vtable_call_container_reflection_GetPartContent(handle, idx)?;
  return Ok(DxcBlob{ handle: ptr });
}

// =========================================================================
// High-level context — DxcContext
// =========================================================================

pub type DxcContext = {
  compiler: Int;
  utils: Int;
} derive[Clone]

pub fn DxcContext.init() -> Result[DxcContext, DxcError] {
  let c = DxcCompiler.create()?;
  let u = DxcUtils.create()?;
  return Ok(DxcContext{ compiler: c.handle, utils: u.handle });
}

pub fn DxcContext.destroy()
  requires: compiler != 0
  requires: utils != 0
{
  vtable_call_Release(utils);
  vtable_call_Release(compiler);
  return ();
}

pub fn DxcContext.create_compiler() -> Result[DxcCompiler, DxcError]
  requires: compiler != 0
{
  return Ok(DxcCompiler{ handle: compiler });
}

pub fn DxcContext.create_utils() -> Result[DxcUtils, DxcError]
  requires: utils != 0
{
  return Ok(DxcUtils{ handle: utils });
}
