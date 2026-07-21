#ifndef XIOM_DXC_BRIDGE_H_
#define XIOM_DXC_BRIDGE_H_

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>

// All functions return int64_t. HRESULT, BOOL, UINT32, SIZE_T, and pointer
// values are all marshalled through int64_t to match XIOM's Int type.
// Negative int64_t for error codes are the raw HRESULT values.

// =========================================================================
// GUID pointer resolvers (1 per CLSID/IID)
// =========================================================================

int64_t xiom_dxc_clsid_compiler(void);
int64_t xiom_dxc_clsid_utils(void);
int64_t xiom_dxc_clsid_library(void);
int64_t xiom_dxc_clsid_validator(void);
int64_t xiom_dxc_clsid_linker(void);
int64_t xiom_dxc_clsid_assembler(void);
int64_t xiom_dxc_clsid_container_reflection(void);
int64_t xiom_dxc_clsid_optimizer(void);
int64_t xiom_dxc_clsid_container_builder(void);
int64_t xiom_dxc_clsid_compiler_args(void);
int64_t xiom_dxc_clsid_pdb_utils(void);

int64_t xiom_dxc_iid_compiler3(void);
int64_t xiom_dxc_iid_utils(void);
int64_t xiom_dxc_iid_result(void);
int64_t xiom_dxc_iid_blob(void);
int64_t xiom_dxc_iid_blob_encoding(void);
int64_t xiom_dxc_iid_blob_utf8(void);
int64_t xiom_dxc_iid_blob_wide(void);
int64_t xiom_dxc_iid_include_handler(void);
int64_t xiom_dxc_iid_operation_result(void);
int64_t xiom_dxc_iid_validator(void);
int64_t xiom_dxc_iid_validator2(void);
int64_t xiom_dxc_iid_linker(void);
int64_t xiom_dxc_iid_assembler(void);
int64_t xiom_dxc_iid_container_reflection(void);
int64_t xiom_dxc_iid_container_builder(void);
int64_t xiom_dxc_iid_compiler_args(void);
int64_t xiom_dxc_iid_extra_outputs(void);
int64_t xiom_dxc_iid_version_info(void);
int64_t xiom_dxc_iid_version_info2(void);
int64_t xiom_dxc_iid_version_info3(void);
int64_t xiom_dxc_iid_optimizer_pass(void);
int64_t xiom_dxc_iid_optimizer(void);
int64_t xiom_dxc_iid_pdb_utils(void);
int64_t xiom_dxc_iid_pdb_utils2(void);

// =========================================================================
// DxcCreateInstance / DxcCreateInstance2 (direct DLL exports)
// =========================================================================

int64_t xiom_dxc_create_instance(int64_t clsid_ptr, int64_t iid_ptr, int64_t ppv_ptr);
int64_t xiom_dxc_create_instance2(int64_t p_malloc, int64_t clsid_ptr, int64_t iid_ptr, int64_t ppv_ptr);

// =========================================================================
// IUnknown — vtable indices 0-2 (shared by ALL COM interfaces)
// =========================================================================

int64_t xiom_unknown_QueryInterface(int64_t ptr, int64_t riid, int64_t ppv_object);
int64_t xiom_unknown_AddRef(int64_t ptr);
int64_t xiom_unknown_Release(int64_t ptr);

// =========================================================================
// IDxcBlob — vtable indices 3-4
// =========================================================================

int64_t xiom_blob_GetBufferPointer(int64_t ptr);
int64_t xiom_blob_GetBufferSize(int64_t ptr);

// =========================================================================
// IDxcBlobEncoding — vtable index 5
// =========================================================================

int64_t xiom_blob_encoding_GetEncoding(int64_t ptr, int64_t p_known, int64_t p_code_page);

// =========================================================================
// IDxcBlobUtf8 — vtable indices 6-7
// =========================================================================

int64_t xiom_blob_utf8_GetStringPointer(int64_t ptr);
int64_t xiom_blob_utf8_GetStringLength(int64_t ptr);

// =========================================================================
// IDxcBlobWide — vtable indices 6-7 (same layout as Utf8)
// =========================================================================

int64_t xiom_blob_wide_GetStringPointer(int64_t ptr);
int64_t xiom_blob_wide_GetStringLength(int64_t ptr);

// =========================================================================
// IDxcIncludeHandler — vtable index 3
// =========================================================================

int64_t xiom_include_handler_LoadSource(int64_t ptr, int64_t p_filename, int64_t pp_include_source);

// =========================================================================
// IDxcOperationResult — vtable indices 3-5
// =========================================================================

int64_t xiom_operation_result_GetStatus(int64_t ptr, int64_t p_status);
int64_t xiom_operation_result_GetResult(int64_t ptr, int64_t pp_result);
int64_t xiom_operation_result_GetErrorBuffer(int64_t ptr, int64_t pp_errors);

// =========================================================================
// IDxcResult — vtable indices 6-10
// =========================================================================

int64_t xiom_result_HasOutput(int64_t ptr, int64_t dxc_out_kind);
int64_t xiom_result_GetOutput(int64_t ptr, int64_t dxc_out_kind, int64_t riid, int64_t ppv_object, int64_t pp_output_name);
int64_t xiom_result_GetNumOutputs(int64_t ptr);
int64_t xiom_result_GetOutputByIndex(int64_t ptr, int64_t index);
int64_t xiom_result_PrimaryOutput(int64_t ptr);

// =========================================================================
// IDxcExtraOutputs — vtable indices 3-4
// =========================================================================

int64_t xiom_extra_outputs_GetOutputCount(int64_t ptr);
int64_t xiom_extra_outputs_GetOutput(int64_t ptr, int64_t u_index, int64_t riid, int64_t ppv_object, int64_t pp_output_type, int64_t pp_output_name);

// =========================================================================
// IDxcCompiler3 — vtable indices 3-4
// =========================================================================

int64_t xiom_compiler3_Compile(int64_t ptr, int64_t p_source, int64_t p_arguments, int64_t arg_count, int64_t p_include_handler, int64_t riid, int64_t pp_result);
int64_t xiom_compiler3_Disassemble(int64_t ptr, int64_t p_object, int64_t riid, int64_t pp_result);

// =========================================================================
// IDxcUtils — vtable indices 3-15
// =========================================================================

int64_t xiom_utils_CreateBlobFromBlob(int64_t ptr, int64_t p_blob, int64_t offset, int64_t length, int64_t pp_result);
int64_t xiom_utils_CreateBlobFromPinned(int64_t ptr, int64_t p_data, int64_t size, int64_t code_page, int64_t pp_blob_encoding);
int64_t xiom_utils_MoveToBlob(int64_t ptr, int64_t p_data, int64_t p_imalloc, int64_t size, int64_t code_page, int64_t pp_blob_encoding);
int64_t xiom_utils_CreateBlob(int64_t ptr, int64_t p_data, int64_t size, int64_t code_page, int64_t pp_blob_encoding);
int64_t xiom_utils_LoadFile(int64_t ptr, int64_t p_file_name, int64_t p_code_page, int64_t pp_blob_encoding);
int64_t xiom_utils_CreateReadOnlyStreamFromBlob(int64_t ptr, int64_t p_blob, int64_t pp_stream);
int64_t xiom_utils_CreateDefaultIncludeHandler(int64_t ptr, int64_t pp_result);
int64_t xiom_utils_GetBlobAsUtf8(int64_t ptr, int64_t p_blob, int64_t pp_blob_encoding);
int64_t xiom_utils_GetBlobAsWide(int64_t ptr, int64_t p_blob, int64_t pp_blob_encoding);
int64_t xiom_utils_GetDxilContainerPart(int64_t ptr, int64_t p_shader, int64_t dxc_part, int64_t pp_part_data, int64_t p_part_size);
int64_t xiom_utils_CreateReflection(int64_t ptr, int64_t p_data, int64_t riid, int64_t ppv_reflection);
int64_t xiom_utils_BuildArguments(int64_t ptr, int64_t p_source_name, int64_t p_entry_point, int64_t p_target_profile, int64_t p_arguments, int64_t arg_count, int64_t p_defines, int64_t define_count, int64_t pp_args);
int64_t xiom_utils_GetPDBContents(int64_t ptr, int64_t p_pdb_blob, int64_t pp_hash, int64_t pp_container);

// =========================================================================
// IDxcCompilerArgs — vtable indices 3-7
// =========================================================================

int64_t xiom_compiler_args_GetArguments(int64_t ptr);
int64_t xiom_compiler_args_GetCount(int64_t ptr);
int64_t xiom_compiler_args_AddArguments(int64_t ptr, int64_t p_arguments, int64_t arg_count);
int64_t xiom_compiler_args_AddArgumentsUTF8(int64_t ptr, int64_t p_arguments, int64_t arg_count);
int64_t xiom_compiler_args_AddDefines(int64_t ptr, int64_t p_defines, int64_t define_count);

// =========================================================================
// IDxcValidator — vtable index 3
// =========================================================================

int64_t xiom_validator_Validate(int64_t ptr, int64_t p_shader, int64_t flags, int64_t pp_result);

// =========================================================================
// IDxcValidator2 — vtable index 4
// =========================================================================

int64_t xiom_validator2_ValidateWithDebug(int64_t ptr, int64_t p_shader, int64_t flags, int64_t p_opt_debug_bitcode, int64_t pp_result);

// =========================================================================
// IDxcContainerBuilder — vtable indices 3-6
// =========================================================================

int64_t xiom_container_builder_Load(int64_t ptr, int64_t p_dxil_container_header);
int64_t xiom_container_builder_AddPart(int64_t ptr, int64_t four_cc, int64_t p_source);
int64_t xiom_container_builder_RemovePart(int64_t ptr, int64_t four_cc);
int64_t xiom_container_builder_SerializeContainer(int64_t ptr, int64_t pp_result);

// =========================================================================
// IDxcAssembler — vtable index 3
// =========================================================================

int64_t xiom_assembler_AssembleToContainer(int64_t ptr, int64_t p_shader, int64_t pp_result);

// =========================================================================
// IDxcContainerReflection — vtable indices 3-8
// =========================================================================

int64_t xiom_container_reflection_Load(int64_t ptr, int64_t p_container);
int64_t xiom_container_reflection_GetPartCount(int64_t ptr, int64_t p_result);
int64_t xiom_container_reflection_GetPartKind(int64_t ptr, int64_t idx, int64_t p_result);
int64_t xiom_container_reflection_GetPartContent(int64_t ptr, int64_t idx, int64_t pp_result);
int64_t xiom_container_reflection_FindFirstPartKind(int64_t ptr, int64_t kind, int64_t p_result);
int64_t xiom_container_reflection_GetPartReflection(int64_t ptr, int64_t idx, int64_t riid, int64_t ppv_object);

// =========================================================================
// IDxcOptimizerPass — vtable indices 3-7
// =========================================================================

int64_t xiom_optimizer_pass_GetOptionName(int64_t ptr, int64_t pp_result);
int64_t xiom_optimizer_pass_GetDescription(int64_t ptr, int64_t pp_result);
int64_t xiom_optimizer_pass_GetOptionArgCount(int64_t ptr, int64_t p_count);
int64_t xiom_optimizer_pass_GetOptionArgName(int64_t ptr, int64_t arg_index, int64_t pp_result);
int64_t xiom_optimizer_pass_GetOptionArgDescription(int64_t ptr, int64_t arg_index, int64_t pp_result);

// =========================================================================
// IDxcOptimizer — vtable indices 3-5
// =========================================================================

int64_t xiom_optimizer_GetAvailablePassCount(int64_t ptr, int64_t p_count);
int64_t xiom_optimizer_GetAvailablePass(int64_t ptr, int64_t index, int64_t pp_result);
int64_t xiom_optimizer_RunOptimizer(int64_t ptr, int64_t p_blob, int64_t pp_options, int64_t option_count, int64_t p_output_module, int64_t pp_output_text);

// =========================================================================
// IDxcVersionInfo — vtable indices 3-4
// =========================================================================

int64_t xiom_version_info_GetVersion(int64_t ptr, int64_t p_major, int64_t p_minor);
int64_t xiom_version_info_GetFlags(int64_t ptr, int64_t p_flags);

// =========================================================================
// IDxcVersionInfo2 — vtable index 5
// =========================================================================

int64_t xiom_version_info2_GetCommitInfo(int64_t ptr, int64_t p_commit_count, int64_t pp_commit_hash);

// =========================================================================
// IDxcVersionInfo3 — vtable index 3
// =========================================================================

int64_t xiom_version_info3_GetCustomVersionString(int64_t ptr, int64_t pp_version_string);

// =========================================================================
// IDxcPdbUtils2 — vtable indices 3-22 (modern interface, prefer over IDxcPdbUtils)
// =========================================================================

int64_t xiom_pdb_utils2_Load(int64_t ptr, int64_t p_pdb_or_dxil);
int64_t xiom_pdb_utils2_GetSourceCount(int64_t ptr, int64_t p_count);
int64_t xiom_pdb_utils2_GetSource(int64_t ptr, int64_t u_index, int64_t pp_result);
int64_t xiom_pdb_utils2_GetSourceName(int64_t ptr, int64_t u_index, int64_t pp_result);
int64_t xiom_pdb_utils2_GetLibraryPDBCount(int64_t ptr, int64_t p_count);
int64_t xiom_pdb_utils2_GetLibraryPDB(int64_t ptr, int64_t u_index, int64_t pp_out_pdb_utils, int64_t pp_library_name);
int64_t xiom_pdb_utils2_GetFlagCount(int64_t ptr, int64_t p_count);
int64_t xiom_pdb_utils2_GetFlag(int64_t ptr, int64_t u_index, int64_t pp_result);
int64_t xiom_pdb_utils2_GetArgCount(int64_t ptr, int64_t p_count);
int64_t xiom_pdb_utils2_GetArg(int64_t ptr, int64_t u_index, int64_t pp_result);
int64_t xiom_pdb_utils2_GetArgPairCount(int64_t ptr, int64_t p_count);
int64_t xiom_pdb_utils2_GetArgPair(int64_t ptr, int64_t u_index, int64_t pp_name, int64_t pp_value);
int64_t xiom_pdb_utils2_GetDefineCount(int64_t ptr, int64_t p_count);
int64_t xiom_pdb_utils2_GetDefine(int64_t ptr, int64_t u_index, int64_t pp_result);
int64_t xiom_pdb_utils2_GetTargetProfile(int64_t ptr, int64_t pp_result);
int64_t xiom_pdb_utils2_GetEntryPoint(int64_t ptr, int64_t pp_result);
int64_t xiom_pdb_utils2_GetMainFileName(int64_t ptr, int64_t pp_result);
int64_t xiom_pdb_utils2_GetHash(int64_t ptr, int64_t pp_result);
int64_t xiom_pdb_utils2_GetName(int64_t ptr, int64_t pp_result);
int64_t xiom_pdb_utils2_GetVersionInfo(int64_t ptr, int64_t pp_version_info);
int64_t xiom_pdb_utils2_GetCustomToolchainID(int64_t ptr, int64_t p_id);
int64_t xiom_pdb_utils2_GetCustomToolchainData(int64_t ptr, int64_t pp_blob);
int64_t xiom_pdb_utils2_GetWholeDxil(int64_t ptr, int64_t pp_result);
int64_t xiom_pdb_utils2_IsFullPDB(int64_t ptr);
int64_t xiom_pdb_utils2_IsPDBRef(int64_t ptr);

// =========================================================================
// IDxcLinker — vtable indices 3-4 (legacy but still in use)
// =========================================================================

int64_t xiom_linker_RegisterLibrary(int64_t ptr, int64_t p_lib_name, int64_t p_lib);
int64_t xiom_linker_Link(int64_t ptr, int64_t p_entry_name, int64_t p_target_profile, int64_t p_lib_names, int64_t lib_count, int64_t p_arguments, int64_t arg_count, int64_t pp_result);

#ifdef __cplusplus
}
#endif

#endif
