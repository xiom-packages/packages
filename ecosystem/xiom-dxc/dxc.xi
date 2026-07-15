// XIOM — DirectX Shader Compiler (DXC) Bindings
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Low-level FFI declarations for DXC (dxcompiler.dll / libdxcompiler.so).
// DXC uses a COM-based API with IUnknown-derived interfaces.
// Only DxcCreateInstance and DxcCreateInstance2 are true extern "C" exports.
// COM interface methods are called via vtable dispatch.
//
// All COM interface pointers map to Int. HRESULT → Int32. UINT32 → Int32.
// SIZE_T → Int. BOOL → Int32. LPCWSTR/LPCSTR → Int (opaque pointer).

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
// Part Constants (FOURCC)
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
pub const DXC_OUT_LAST: Int32 = 13 as Int32;

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

// =========================================================================
// DXC Error Codes (dxcapi.h / dxcerrors.h)
// =========================================================================

pub const DXC_E_MISSING_PART: Int32 = -2004284416 as Int32;

// =========================================================================
// COM VTable Layout
// =========================================================================
// Every COM interface inherits from IUnknown (3 methods):
//   [0] QueryInterface(REFIID, void**)
//   [1] AddRef()
//   [2] Release()
// Interface-specific methods start at vtable index 3.
//
// VTable dispatch pattern:
//   let vtbl = unsafe { *(pObj as **Int) };
//   let fn_ptr_val = unsafe { *((vtbl as *Int) + INDEX) };
//   let f: fn(...) -> Ret = fn_ptr_val as fn(...) -> Ret;
//   let result = unsafe { f(pObj as Int, ...) };

// =========================================================================
// Struct Types
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

pub type DxcShaderHash = {
  flags: Int32;
  hash_digest_0: Int32;
  hash_digest_1: Int32;
  hash_digest_2: Int32;
  hash_digest_3: Int32;
} derive[Clone]

// =========================================================================
// GUID type (16 bytes, matches C GUID / IID / CLSID layout)
// =========================================================================

pub type Guid = {
  data1: Int32;
  data2_3: Int32;
  data4_lo: Int32;
  data4_hi: Int32;
} derive[Clone]

// =========================================================================
// External "C" Functions — dxcompiler.dll exports
// =========================================================================

extern "C" {
  fn DxcCreateInstance(rclsid: Int, riid: Int, ppv: Int) -> Int32;
  fn DxcCreateInstance2(pMalloc: Int, rclsid: Int, riid: Int, ppv: Int) -> Int32;
}

// =========================================================================
// GUID constants — pointers resolved at link time via C bridge
// =========================================================================

extern "C" {
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
}

// =========================================================================
// IUnknown VTable Methods (indices 0-2, common to all COM interfaces)
// =========================================================================

pub fn iunknown_query_interface(ptr: Int, riid: Int) -> Result[Int, Str]
  requires: ptr != 0
  requires: riid != 0
{
  let vtbl: Int = unsafe { *(ptr as **Int) };
  let fn_ptr_val: Int = unsafe { *((vtbl as *Int) + 0) };
  let f: fn(Int, Int, Int) -> Int32 = fn_ptr_val as fn(Int, Int, Int) -> Int32;
  let ppv: Int = 0;
  let hr: Int32 = unsafe { f(ptr as Int, riid, ppv) };
  if hr != 0 { return Err("QueryInterface failed"); }
  return Ok(ppv);
}

pub fn iunknown_add_ref(ptr: Int) -> Int32
  requires: ptr != 0
{
  let vtbl: Int = unsafe { *(ptr as **Int) };
  let fn_ptr_val: Int = unsafe { *((vtbl as *Int) + 1) };
  let f: fn(Int) -> Int32 = fn_ptr_val as fn(Int) -> Int32;
  return unsafe { f(ptr as Int) };
}

pub fn iunknown_release(ptr: Int) -> Int32
  requires: ptr != 0
{
  let vtbl: Int = unsafe { *(ptr as **Int) };
  let fn_ptr_val: Int = unsafe { *((vtbl as *Int) + 2) };
  let f: fn(Int) -> Int32 = fn_ptr_val as fn(Int) -> Int32;
  return unsafe { f(ptr as Int) };
}

// =========================================================================
// IDxcBlob VTable Methods (indices 3-4)
// =========================================================================

pub fn blob_get_buffer_pointer(ptr: Int) -> Int
  requires: ptr != 0
{
  let vtbl: Int = unsafe { *(ptr as **Int) };
  let fn_ptr_val: Int = unsafe { *((vtbl as *Int) + 3) };
  let f: fn(Int) -> Int = fn_ptr_val as fn(Int) -> Int;
  return unsafe { f(ptr as Int) };
}

pub fn blob_get_buffer_size(ptr: Int) -> Int
  requires: ptr != 0
{
  let vtbl: Int = unsafe { *(ptr as **Int) };
  let fn_ptr_val: Int = unsafe { *((vtbl as *Int) + 4) };
  let f: fn(Int) -> Int = fn_ptr_val as fn(Int) -> Int;
  return unsafe { f(ptr as Int) };
}

// =========================================================================
// IDxcBlobEncoding VTable Methods (index 5)
// =========================================================================

pub fn blob_encoding_get_encoding(ptr: Int) -> Result[Int32, Str]
  requires: ptr != 0
{
  let vtbl: Int = unsafe { *(ptr as **Int) };
  let fn_ptr_val: Int = unsafe { *((vtbl as *Int) + 5) };
  let f: fn(Int, Int, Int) -> Int32 = fn_ptr_val as fn(Int, Int, Int) -> Int32;
  let known: Int32 = 0 as Int32;
  let code_page: Int32 = 0 as Int32;
  let hr: Int32 = unsafe { f(ptr as Int, known, code_page) };
  if hr != 0 { return Err("GetEncoding failed"); }
  return Ok(code_page);
}

// =========================================================================
// IDxcBlobUtf8 VTable Methods (indices 6-7)
// =========================================================================

pub fn blob_utf8_get_string_pointer(ptr: Int) -> Int
  requires: ptr != 0
{
  let vtbl: Int = unsafe { *(ptr as **Int) };
  let fn_ptr_val: Int = unsafe { *((vtbl as *Int) + 6) };
  let f: fn(Int) -> Int = fn_ptr_val as fn(Int) -> Int;
  return unsafe { f(ptr as Int) };
}

pub fn blob_utf8_get_string_length(ptr: Int) -> Int
  requires: ptr != 0
{
  let vtbl: Int = unsafe { *(ptr as **Int) };
  let fn_ptr_val: Int = unsafe { *((vtbl as *Int) + 7) };
  let f: fn(Int) -> Int = fn_ptr_val as fn(Int) -> Int;
  return unsafe { f(ptr as Int) };
}

// =========================================================================
// IDxcBlobWide VTable Methods (indices 6-7, same as IDxcBlobUtf8)
// =========================================================================
// NOTE: These share the same indices as IDxcBlobUtf8 since
// IDxcBlobWide and IDxcBlobUtf8 both inherit from IDxcBlobEncoding
// and add 2 methods each. The methods differ in return type semantics.
// The return type is always Int (pointer-size integer), so the
// signatures are ABI-compatible.

pub fn blob_wide_get_string_pointer(ptr: Int) -> Int
  requires: ptr != 0
{
  let vtbl: Int = unsafe { *(ptr as **Int) };
  let fn_ptr_val: Int = unsafe { *((vtbl as *Int) + 6) };
  let f: fn(Int) -> Int = fn_ptr_val as fn(Int) -> Int;
  return unsafe { f(ptr as Int) };
}

pub fn blob_wide_get_string_length(ptr: Int) -> Int
  requires: ptr != 0
{
  let vtbl: Int = unsafe { *(ptr as **Int) };
  let fn_ptr_val: Int = unsafe { *((vtbl as *Int) + 7) };
  let f: fn(Int) -> Int = fn_ptr_val as fn(Int) -> Int;
  return unsafe { f(ptr as Int) };
}

// =========================================================================
// IDxcIncludeHandler VTable Methods (index 3)
// =========================================================================

pub fn include_handler_load_source(ptr: Int, p_filename: Int) -> Result[Int, Str]
  requires: ptr != 0
  requires: p_filename != 0
{
  let vtbl: Int = unsafe { *(ptr as **Int) };
  let fn_ptr_val: Int = unsafe { *((vtbl as *Int) + 3) };
  let f: fn(Int, Int, Int) -> Int32 = fn_ptr_val as fn(Int, Int, Int) -> Int32;
  let pp_include_source: Int = 0;
  let hr: Int32 = unsafe { f(ptr as Int, p_filename, pp_include_source) };
  if hr != 0 { return Err("LoadSource failed"); }
  return Ok(pp_include_source);
}

// =========================================================================
// IDxcOperationResult VTable Methods (indices 3-5)
// =========================================================================

pub fn operation_result_get_status(ptr: Int) -> Result[Int32, Str]
  requires: ptr != 0
{
  let vtbl: Int = unsafe { *(ptr as **Int) };
  let fn_ptr_val: Int = unsafe { *((vtbl as *Int) + 3) };
  let f: fn(Int, Int) -> Int32 = fn_ptr_val as fn(Int, Int) -> Int32;
  let p_status: Int = 0;
  let hr: Int32 = unsafe { f(ptr as Int, p_status) };
  if hr != 0 { return Err("GetStatus failed"); }
  return Ok(p_status);
}

pub fn operation_result_get_result(ptr: Int) -> Result[Int, Str]
  requires: ptr != 0
{
  let vtbl: Int = unsafe { *(ptr as **Int) };
  let fn_ptr_val: Int = unsafe { *((vtbl as *Int) + 4) };
  let f: fn(Int, Int) -> Int32 = fn_ptr_val as fn(Int, Int) -> Int32;
  let pp_result: Int = 0;
  let hr: Int32 = unsafe { f(ptr as Int, pp_result) };
  if hr != 0 { return Err("GetResult failed"); }
  return Ok(pp_result);
}

pub fn operation_result_get_error_buffer(ptr: Int) -> Result[Int, Str]
  requires: ptr != 0
{
  let vtbl: Int = unsafe { *(ptr as **Int) };
  let fn_ptr_val: Int = unsafe { *((vtbl as *Int) + 5) };
  let f: fn(Int, Int) -> Int32 = fn_ptr_val as fn(Int, Int) -> Int32;
  let pp_errors: Int = 0;
  let hr: Int32 = unsafe { f(ptr as Int, pp_errors) };
  if hr != 0 { return Err("GetErrorBuffer failed"); }
  return Ok(pp_errors);
}

// =========================================================================
// IDxcResult VTable Methods (indices 6-10)
// =========================================================================

pub fn result_has_output(ptr: Int, dxc_out_kind: Int32) -> Int32
  requires: ptr != 0
{
  let vtbl: Int = unsafe { *(ptr as **Int) };
  let fn_ptr_val: Int = unsafe { *((vtbl as *Int) + 6) };
  let f: fn(Int, Int32) -> Int32 = fn_ptr_val as fn(Int, Int32) -> Int32;
  return unsafe { f(ptr as Int, dxc_out_kind) };
}

pub fn result_get_output(ptr: Int, dxc_out_kind: Int32, riid: Int) -> Result[Int, Str]
  requires: ptr != 0
  requires: riid != 0
{
  let vtbl: Int = unsafe { *(ptr as **Int) };
  let fn_ptr_val: Int = unsafe { *((vtbl as *Int) + 7) };
  let f: fn(Int, Int32, Int, Int, Int) -> Int32 = fn_ptr_val as fn(Int, Int32, Int, Int, Int) -> Int32;
  let ppv: Int = 0;
  let pp_name: Int = 0;
  let hr: Int32 = unsafe { f(ptr as Int, dxc_out_kind, riid, ppv, pp_name) };
  if hr != 0 { return Err("GetOutput failed"); }
  return Ok(ppv);
}

pub fn result_get_num_outputs(ptr: Int) -> Int32
  requires: ptr != 0
{
  let vtbl: Int = unsafe { *(ptr as **Int) };
  let fn_ptr_val: Int = unsafe { *((vtbl as *Int) + 8) };
  let f: fn(Int) -> Int32 = fn_ptr_val as fn(Int) -> Int32;
  return unsafe { f(ptr as Int) };
}

pub fn result_get_output_by_index(ptr: Int, index: Int32) -> Int32
  requires: ptr != 0
{
  let vtbl: Int = unsafe { *(ptr as **Int) };
  let fn_ptr_val: Int = unsafe { *((vtbl as *Int) + 9) };
  let f: fn(Int, Int32) -> Int32 = fn_ptr_val as fn(Int, Int32) -> Int32;
  return unsafe { f(ptr as Int, index) };
}

pub fn result_primary_output(ptr: Int) -> Int32
  requires: ptr != 0
{
  let vtbl: Int = unsafe { *(ptr as **Int) };
  let fn_ptr_val: Int = unsafe { *((vtbl as *Int) + 10) };
  let f: fn(Int) -> Int32 = fn_ptr_val as fn(Int) -> Int32;
  return unsafe { f(ptr as Int) };
}

// =========================================================================
// IDxcCompiler3 VTable Methods (indices 3-4)
// =========================================================================

pub fn compiler3_compile(ptr: Int, p_source: Int, p_arguments: Int, arg_count: Int32, p_include_handler: Int, riid: Int) -> Result[Int, Str]
  requires: ptr != 0
  requires: p_source != 0
  requires: riid != 0
{
  let vtbl: Int = unsafe { *(ptr as **Int) };
  let fn_ptr_val: Int = unsafe { *((vtbl as *Int) + 3) };
  let f: fn(Int, Int, Int, Int32, Int, Int, Int) -> Int32 = fn_ptr_val as fn(Int, Int, Int, Int32, Int, Int, Int) -> Int32;
  let pp_result: Int = 0;
  let hr: Int32 = unsafe { f(ptr as Int, p_source, p_arguments, arg_count, p_include_handler, riid, pp_result) };
  if hr != 0 { return Err("Compile failed"); }
  return Ok(pp_result);
}

pub fn compiler3_disassemble(ptr: Int, p_object: Int, riid: Int) -> Result[Int, Str]
  requires: ptr != 0
  requires: p_object != 0
  requires: riid != 0
{
  let vtbl: Int = unsafe { *(ptr as **Int) };
  let fn_ptr_val: Int = unsafe { *((vtbl as *Int) + 4) };
  let f: fn(Int, Int, Int, Int) -> Int32 = fn_ptr_val as fn(Int, Int, Int, Int) -> Int32;
  let pp_result: Int = 0;
  let hr: Int32 = unsafe { f(ptr as Int, p_object, riid, pp_result) };
  if hr != 0 { return Err("Disassemble failed"); }
  return Ok(pp_result);
}

// =========================================================================
// IDxcUtils VTable Methods (indices 3-15)
// =========================================================================

pub fn utils_create_blob_from_blob(ptr: Int, p_blob: Int, offset: Int32, length: Int32) -> Result[Int, Str]
  requires: ptr != 0
  requires: p_blob != 0
{
  let vtbl: Int = unsafe { *(ptr as **Int) };
  let fn_ptr_val: Int = unsafe { *((vtbl as *Int) + 3) };
  let f: fn(Int, Int, Int32, Int32, Int) -> Int32 = fn_ptr_val as fn(Int, Int, Int32, Int32, Int) -> Int32;
  let pp_result: Int = 0;
  let hr: Int32 = unsafe { f(ptr as Int, p_blob, offset, length, pp_result) };
  if hr != 0 { return Err("CreateBlobFromBlob failed"); }
  return Ok(pp_result);
}

pub fn utils_create_blob(ptr: Int, p_data: Int, size: Int32, code_page: Int32) -> Result[Int, Str]
  requires: ptr != 0
  requires: p_data != 0
{
  let vtbl: Int = unsafe { *(ptr as **Int) };
  let fn_ptr_val: Int = unsafe { *((vtbl as *Int) + 5) };
  let f: fn(Int, Int, Int32, Int32, Int) -> Int32 = fn_ptr_val as fn(Int, Int, Int32, Int32, Int) -> Int32;
  let pp_blob_encoding: Int = 0;
  let hr: Int32 = unsafe { f(ptr as Int, p_data, size, code_page, pp_blob_encoding) };
  if hr != 0 { return Err("CreateBlob failed"); }
  return Ok(pp_blob_encoding);
}

pub fn utils_load_file(ptr: Int, p_file_name: Int) -> Result[Int, Str]
  requires: ptr != 0
  requires: p_file_name != 0
{
  let vtbl: Int = unsafe { *(ptr as **Int) };
  let fn_ptr_val: Int = unsafe { *((vtbl as *Int) + 6) };
  let f: fn(Int, Int, Int, Int) -> Int32 = fn_ptr_val as fn(Int, Int, Int, Int) -> Int32;
  let pp_blob_encoding: Int = 0;
  let hr: Int32 = unsafe { f(ptr as Int, p_file_name, 0, pp_blob_encoding) };
  if hr != 0 { return Err("LoadFile failed"); }
  return Ok(pp_blob_encoding);
}

pub fn utils_create_default_include_handler(ptr: Int) -> Result[Int, Str]
  requires: ptr != 0
{
  let vtbl: Int = unsafe { *(ptr as **Int) };
  let fn_ptr_val: Int = unsafe { *((vtbl as *Int) + 8) };
  let f: fn(Int, Int) -> Int32 = fn_ptr_val as fn(Int, Int) -> Int32;
  let pp_result: Int = 0;
  let hr: Int32 = unsafe { f(ptr as Int, pp_result) };
  if hr != 0 { return Err("CreateDefaultIncludeHandler failed"); }
  return Ok(pp_result);
}

pub fn utils_get_blob_as_utf8(ptr: Int, p_blob: Int) -> Result[Int, Str]
  requires: ptr != 0
  requires: p_blob != 0
{
  let vtbl: Int = unsafe { *(ptr as **Int) };
  let fn_ptr_val: Int = unsafe { *((vtbl as *Int) + 9) };
  let f: fn(Int, Int, Int) -> Int32 = fn_ptr_val as fn(Int, Int, Int) -> Int32;
  let pp_blob_encoding: Int = 0;
  let hr: Int32 = unsafe { f(ptr as Int, p_blob, pp_blob_encoding) };
  if hr != 0 { return Err("GetBlobAsUtf8 failed"); }
  return Ok(pp_blob_encoding);
}

pub fn utils_get_dxil_container_part(ptr: Int, p_shader: Int, dxc_part: Int32) -> Result[Int, Str]
  requires: ptr != 0
  requires: p_shader != 0
{
  let vtbl: Int = unsafe { *(ptr as **Int) };
  let fn_ptr_val: Int = unsafe { *((vtbl as *Int) + 11) };
  let f: fn(Int, Int, Int32, Int, Int) -> Int32 = fn_ptr_val as fn(Int, Int, Int32, Int, Int) -> Int32;
  let pp_part_data: Int = 0;
  let p_part_size: Int = 0;
  let hr: Int32 = unsafe { f(ptr as Int, p_shader, dxc_part, pp_part_data, p_part_size) };
  if hr != 0 { return Err("GetDxilContainerPart failed"); }
  return Ok(pp_part_data);
}

pub fn utils_create_reflection(ptr: Int, p_data: Int, riid: Int) -> Result[Int, Str]
  requires: ptr != 0
  requires: p_data != 0
  requires: riid != 0
{
  let vtbl: Int = unsafe { *(ptr as **Int) };
  let fn_ptr_val: Int = unsafe { *((vtbl as *Int) + 12) };
  let f: fn(Int, Int, Int, Int) -> Int32 = fn_ptr_val as fn(Int, Int, Int, Int) -> Int32;
  let ppv_reflection: Int = 0;
  let hr: Int32 = unsafe { f(ptr as Int, p_data, riid, ppv_reflection) };
  if hr != 0 { return Err("CreateReflection failed"); }
  return Ok(ppv_reflection);
}

pub fn utils_get_pdb_contents(ptr: Int, p_pdb_blob: Int) -> Result[Int, Str]
  requires: ptr != 0
  requires: p_pdb_blob != 0
{
  let vtbl: Int = unsafe { *(ptr as **Int) };
  let fn_ptr_val: Int = unsafe { *((vtbl as *Int) + 14) };
  let f: fn(Int, Int, Int, Int) -> Int32 = fn_ptr_val as fn(Int, Int, Int, Int) -> Int32;
  let pp_hash: Int = 0;
  let pp_container: Int = 0;
  let hr: Int32 = unsafe { f(ptr as Int, p_pdb_blob, pp_hash, pp_container) };
  if hr != 0 { return Err("GetPDBContents failed"); }
  return Ok(pp_hash);
}

// =========================================================================
// IDxcCompilerArgs VTable Methods (indices 3-5)
// =========================================================================

pub fn compiler_args_get_arguments(ptr: Int) -> Int
  requires: ptr != 0
{
  let vtbl: Int = unsafe { *(ptr as **Int) };
  let fn_ptr_val: Int = unsafe { *((vtbl as *Int) + 3) };
  let f: fn(Int) -> Int = fn_ptr_val as fn(Int) -> Int;
  return unsafe { f(ptr as Int) };
}

pub fn compiler_args_get_count(ptr: Int) -> Int32
  requires: ptr != 0
{
  let vtbl: Int = unsafe { *(ptr as **Int) };
  let fn_ptr_val: Int = unsafe { *((vtbl as *Int) + 4) };
  let f: fn(Int) -> Int32 = fn_ptr_val as fn(Int) -> Int32;
  return unsafe { f(ptr as Int) };
}

// =========================================================================
// IDxcValidator VTable Methods (index 3)
// =========================================================================

pub fn validator_validate(ptr: Int, p_shader: Int, flags: Int32) -> Result[Int, Str]
  requires: ptr != 0
  requires: p_shader != 0
{
  let vtbl: Int = unsafe { *(ptr as **Int) };
  let fn_ptr_val: Int = unsafe { *((vtbl as *Int) + 3) };
  let f: fn(Int, Int, Int32, Int) -> Int32 = fn_ptr_val as fn(Int, Int, Int32, Int) -> Int32;
  let pp_result: Int = 0;
  let hr: Int32 = unsafe { f(ptr as Int, p_shader, flags, pp_result) };
  if hr != 0 { return Err("Validate failed"); }
  return Ok(pp_result);
}

// =========================================================================
// IDxcContainerBuilder VTable Methods (indices 3-5)
// =========================================================================

pub fn container_builder_load(ptr: Int, p_dxil_container_header: Int) -> Result[Int32, Str]
  requires: ptr != 0
  requires: p_dxil_container_header != 0
{
  let vtbl: Int = unsafe { *(ptr as **Int) };
  let fn_ptr_val: Int = unsafe { *((vtbl as *Int) + 3) };
  let f: fn(Int, Int) -> Int32 = fn_ptr_val as fn(Int, Int) -> Int32;
  return unsafe { f(ptr as Int, p_dxil_container_header) };
}

pub fn container_builder_add_part(ptr: Int, four_cc: Int32, p_source: Int) -> Result[Int32, Str]
  requires: ptr != 0
  requires: p_source != 0
{
  let vtbl: Int = unsafe { *(ptr as **Int) };
  let fn_ptr_val: Int = unsafe { *((vtbl as *Int) + 4) };
  let f: fn(Int, Int32, Int) -> Int32 = fn_ptr_val as fn(Int, Int32, Int) -> Int32;
  return unsafe { f(ptr as Int, four_cc, p_source) };
}

pub fn container_builder_serialize_container(ptr: Int) -> Result[Int, Str]
  requires: ptr != 0
{
  let vtbl: Int = unsafe { *(ptr as **Int) };
  let fn_ptr_val: Int = unsafe { *((vtbl as *Int) + 6) };
  let f: fn(Int, Int) -> Int32 = fn_ptr_val as fn(Int, Int) -> Int32;
  let pp_result: Int = 0;
  let hr: Int32 = unsafe { f(ptr as Int, pp_result) };
  if hr != 0 { return Err("SerializeContainer failed"); }
  return Ok(pp_result);
}

// =========================================================================
// IDxcAssembler VTable Methods (index 3)
// =========================================================================

pub fn assembler_assemble_to_container(ptr: Int, p_shader: Int) -> Result[Int, Str]
  requires: ptr != 0
  requires: p_shader != 0
{
  let vtbl: Int = unsafe { *(ptr as **Int) };
  let fn_ptr_val: Int = unsafe { *((vtbl as *Int) + 3) };
  let f: fn(Int, Int, Int) -> Int32 = fn_ptr_val as fn(Int, Int, Int) -> Int32;
  let pp_result: Int = 0;
  let hr: Int32 = unsafe { f(ptr as Int, p_shader, pp_result) };
  if hr != 0 { return Err("AssembleToContainer failed"); }
  return Ok(pp_result);
}

// =========================================================================
// IDxcContainerReflection VTable Methods (indices 3-7)
// =========================================================================

pub fn container_reflection_load(ptr: Int, p_container: Int) -> Result[Int32, Str]
  requires: ptr != 0
{
  let vtbl: Int = unsafe { *(ptr as **Int) };
  let fn_ptr_val: Int = unsafe { *((vtbl as *Int) + 3) };
  let f: fn(Int, Int) -> Int32 = fn_ptr_val as fn(Int, Int) -> Int32;
  return unsafe { f(ptr as Int, p_container) };
}

pub fn container_reflection_get_part_count(ptr: Int) -> Result[Int32, Str]
  requires: ptr != 0
{
  let vtbl: Int = unsafe { *(ptr as **Int) };
  let fn_ptr_val: Int = unsafe { *((vtbl as *Int) + 4) };
  let f: fn(Int, Int) -> Int32 = fn_ptr_val as fn(Int, Int) -> Int32;
  let p_result: Int = 0;
  let hr: Int32 = unsafe { f(ptr as Int, p_result) };
  if hr != 0 { return Err("GetPartCount failed"); }
  return Ok(p_result);
}

pub fn container_reflection_get_part_kind(ptr: Int, idx: Int32) -> Result[Int32, Str]
  requires: ptr != 0
{
  let vtbl: Int = unsafe { *(ptr as **Int) };
  let fn_ptr_val: Int = unsafe { *((vtbl as *Int) + 5) };
  let f: fn(Int, Int32, Int) -> Int32 = fn_ptr_val as fn(Int, Int32, Int) -> Int32;
  let p_result: Int = 0;
  let hr: Int32 = unsafe { f(ptr as Int, idx, p_result) };
  if hr != 0 { return Err("GetPartKind failed"); }
  return Ok(p_result);
}

pub fn container_reflection_get_part_content(ptr: Int, idx: Int32) -> Result[Int, Str]
  requires: ptr != 0
{
  let vtbl: Int = unsafe { *(ptr as **Int) };
  let fn_ptr_val: Int = unsafe { *((vtbl as *Int) + 6) };
  let f: fn(Int, Int32, Int) -> Int32 = fn_ptr_val as fn(Int, Int32, Int) -> Int32;
  let pp_result: Int = 0;
  let hr: Int32 = unsafe { f(ptr as Int, idx, pp_result) };
  if hr != 0 { return Err("GetPartContent failed"); }
  return Ok(pp_result);
}

pub fn container_reflection_find_first_part_kind(ptr: Int, kind: Int32) -> Result[Int32, Str]
  requires: ptr != 0
{
  let vtbl: Int = unsafe { *(ptr as **Int) };
  let fn_ptr_val: Int = unsafe { *((vtbl as *Int) + 7) };
  let f: fn(Int, Int32, Int) -> Int32 = fn_ptr_val as fn(Int, Int32, Int) -> Int32;
  let p_result: Int = 0;
  let hr: Int32 = unsafe { f(ptr as Int, kind, p_result) };
  if hr != 0 { return Err("FindFirstPartKind failed"); }
  return Ok(p_result);
}

// =========================================================================
// IDxcVersionInfo VTable Methods (indices 3-4)
// =========================================================================

pub fn version_info_get_version(ptr: Int) -> Result[Int, Str]
  requires: ptr != 0
{
  let vtbl: Int = unsafe { *(ptr as **Int) };
  let fn_ptr_val: Int = unsafe { *((vtbl as *Int) + 3) };
  let f: fn(Int, Int, Int) -> Int32 = fn_ptr_val as fn(Int, Int, Int) -> Int32;
  let major: Int = 0;
  let minor: Int = 0;
  let hr: Int32 = unsafe { f(ptr as Int, major, minor) };
  if hr != 0 { return Err("GetVersion failed"); }
  return Ok(major);
}

pub fn version_info_get_flags(ptr: Int) -> Result[Int, Str]
  requires: ptr != 0
{
  let vtbl: Int = unsafe { *(ptr as **Int) };
  let fn_ptr_val: Int = unsafe { *((vtbl as *Int) + 4) };
  let f: fn(Int, Int) -> Int32 = fn_ptr_val as fn(Int, Int) -> Int32;
  let p_flags: Int = 0;
  let hr: Int32 = unsafe { f(ptr as Int, p_flags) };
  if hr != 0 { return Err("GetFlags failed"); }
  return Ok(p_flags);
}

// =========================================================================
// Helpers: create COM instances via DxcCreateInstance
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

// =========================================================================
// Procedural Safe Wrappers (following xiom.vma pattern)
// =========================================================================

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

// =========================================================================
// Helpers: release COM interface (IUnknown::Release pattern)
// =========================================================================

pub fn release(ptr: Int)
  requires: ptr != 0
{
  let ref_count: Int32 = iunknown_release(ptr);
  return ();
}

// =========================================================================
// HRESULT → human-readable string
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
