// xiom-dxc bridge: thin COM vtable wrappers for XIOM FFI
// Every COM method is wrapped as a plain C function taking int64_t.
// The XIOM compiler cannot do Int→Ptr or Int→fn casts, so the C
// bridge handles all vtable dispatch internally.
//
// Compile with:
//   clang -c dxc_bridge.c -I"%VULKAN_SDK%\Include\dxc" -o dxc_bridge.o
// Then link with dxcompiler.lib/libdxcompiler.so

#ifdef __cplusplus
extern "C" {
#endif

#include "dxc_bridge.h"

#ifdef _WIN32
#define DXC_API_IMPORT __declspec(dllimport)
#endif

#include "dxcapi.h"
#include <stdint.h>
#include <stddef.h>

// -- helpers ----------------------------------------------------------------

#define PTR(p)   ((void*)(intptr_t)(p))
#define IPTR(p)  ((int64_t)(intptr_t)(p))
#define HR(r)    ((int64_t)(int32_t)(r))

// -- vtcall macros ----------------------------------------------------------

// 0 args, returns void* / SIZE_T
#define VTCALL_0_RET_INT(name, idx) \
  int64_t name(int64_t ptr) { \
    void*** vtbl = *(void****)PTR(ptr); \
    int64_t (*fn)(void*) = (int64_t(*)(void*))vtbl[idx]; \
    return fn(PTR(ptr)); \
  }

// 0 args, returns UINT32 / DXC_OUT_KIND / BOOL
#define VTCALL_0_RET_I32(name, idx) \
  int64_t name(int64_t ptr) { \
    void*** vtbl = *(void****)PTR(ptr); \
    int32_t (*fn)(void*) = (int32_t(*)(void*))vtbl[idx]; \
    return (int64_t)fn(PTR(ptr)); \
  }

// 1 arg (int64_t), returns int32 / HRESULT
#define VTCALL_1_RET_I32(name, idx, a1, T1) \
  int64_t name(int64_t ptr, int64_t a1) { \
    void*** vtbl = *(void****)PTR(ptr); \
    int32_t (*fn)(void*, T1) = (int32_t(*)(void*, T1))vtbl[idx]; \
    return (int64_t)fn(PTR(ptr), (T1)PTR(a1)); \
  }

// 1 arg (by-val int32_t), returns HRESULT
#define VTCALL_1I32_RET_I32(name, idx, a1) \
  int64_t name(int64_t ptr, int64_t a1) { \
    void*** vtbl = *(void****)PTR(ptr); \
    int32_t (*fn)(void*, uint32_t) = (int32_t(*)(void*, uint32_t))vtbl[idx]; \
    return (int64_t)fn(PTR(ptr), (uint32_t)(a1)); \
  }

// 2 arg (both int64_t as ptr), returns HRESULT
#define VTCALL_2P_RET_I32(name, idx, a1, a2) \
  int64_t name(int64_t ptr, int64_t a1, int64_t a2) { \
    void*** vtbl = *(void****)PTR(ptr); \
    int32_t (*fn)(void*, void*, void*) = (int32_t(*)(void*, void*, void*))vtbl[idx]; \
    return (int64_t)fn(PTR(ptr), (void*)PTR(a1), (void*)PTR(a2)); \
  }

// 3 arg (all int64_t as ptr), returns HRESULT
#define VTCALL_3P_RET_I32(name, idx, a1, a2, a3) \
  int64_t name(int64_t ptr, int64_t a1, int64_t a2, int64_t a3) { \
    void*** vtbl = *(void****)PTR(ptr); \
    int32_t (*fn)(void*, void*, void*, void*) = (int32_t(*)(void*, void*, void*, void*))vtbl[idx]; \
    return (int64_t)fn(PTR(ptr), (void*)PTR(a1), (void*)PTR(a2), (void*)PTR(a3)); \
  }

// 4 arg (all int64_t as ptr), returns HRESULT
#define VTCALL_4P_RET_I32(name, idx, a1, a2, a3, a4) \
  int64_t name(int64_t ptr, int64_t a1, int64_t a2, int64_t a3, int64_t a4) { \
    void*** vtbl = *(void****)PTR(ptr); \
    int32_t (*fn)(void*, void*, void*, void*, void*) = (int32_t(*)(void*, void*, void*, void*, void*))vtbl[idx]; \
    return (int64_t)fn(PTR(ptr), (void*)PTR(a1), (void*)PTR(a2), (void*)PTR(a3), (void*)PTR(a4)); \
  }

// 2 ptr + 2 uint32_t, returns HRESULT (for CreateBlobFromBlob etc.)
#define VTCALL_2P2I32_RET_I32(name, idx, a1, a2, a3, a4) \
  int64_t name(int64_t ptr, int64_t a1, int64_t a2, int64_t a3, int64_t a4) { \
    void*** vtbl = *(void****)PTR(ptr); \
    int32_t (*fn)(void*, void*, uint32_t, uint32_t, void*) = (int32_t(*)(void*, void*, uint32_t, uint32_t, void*))vtbl[idx]; \
    return (int64_t)fn(PTR(ptr), (void*)PTR(a1), (uint32_t)(a2), (uint32_t)(a3), (void*)PTR(a4)); \
  }

// 5 ptr args, returns HRESULT
#define VTCALL_5P_RET_I32(name, idx, a1, a2, a3, a4, a5) \
  int64_t name(int64_t ptr, int64_t a1, int64_t a2, int64_t a3, int64_t a4, int64_t a5) { \
    void*** vtbl = *(void****)PTR(ptr); \
    int32_t (*fn)(void*, void*, void*, void*, void*, void*) = (int32_t(*)(void*, void*, void*, void*, void*, void*))vtbl[idx]; \
    return (int64_t)fn(PTR(ptr), (void*)PTR(a1), (void*)PTR(a2), (void*)PTR(a3), (void*)PTR(a4), (void*)PTR(a5)); \
  }

// 6 ptr args, returns HRESULT
#define VTCALL_6P_RET_I32(name, idx, a1, a2, a3, a4, a5, a6) \
  int64_t name(int64_t ptr, int64_t a1, int64_t a2, int64_t a3, int64_t a4, int64_t a5, int64_t a6) { \
    void*** vtbl = *(void****)PTR(ptr); \
    int32_t (*fn)(void*, void*, void*, void*, void*, void*, void*) = (int32_t(*)(void*, void*, void*, void*, void*, void*, void*))vtbl[idx]; \
    return (int64_t)fn(PTR(ptr), (void*)PTR(a1), (void*)PTR(a2), (void*)PTR(a3), (void*)PTR(a4), (void*)PTR(a5), (void*)PTR(a6)); \
  }

// 8 ptr args, returns HRESULT (for BuildArguments)
#define VTCALL_8P_RET_I32(name, idx, a1, a2, a3, a4, a5, a6, a7, a8) \
  int64_t name(int64_t ptr, int64_t a1, int64_t a2, int64_t a3, int64_t a4, int64_t a5, int64_t a6, int64_t a7, int64_t a8) { \
    void*** vtbl = *(void****)PTR(ptr); \
    int32_t (*fn)(void*, void*, void*, void*, void*, uint32_t, void*, uint32_t, void*) = (int32_t(*)(void*, void*, void*, void*, void*, uint32_t, void*, uint32_t, void*))vtbl[idx]; \
    return (int64_t)fn(PTR(ptr), (void*)PTR(a1), (void*)PTR(a2), (void*)PTR(a3), (void*)PTR(a4), (uint32_t)(a5), (void*)PTR(a6), (uint32_t)(a7), (void*)PTR(a8)); \
  }

// =========================================================================
// GUID pointer resolvers
// =========================================================================

#define XIOM_GUID_PTR(name, guid_var) \
  int64_t xiom_dxc_##name(void) { return IPTR(&guid_var); }

XIOM_GUID_PTR(clsid_compiler, CLSID_DxcCompiler)
XIOM_GUID_PTR(clsid_utils, CLSID_DxcUtils)
XIOM_GUID_PTR(clsid_library, CLSID_DxcLibrary)
XIOM_GUID_PTR(clsid_validator, CLSID_DxcValidator)
XIOM_GUID_PTR(clsid_linker, CLSID_DxcLinker)
XIOM_GUID_PTR(clsid_assembler, CLSID_DxcAssembler)
XIOM_GUID_PTR(clsid_container_reflection, CLSID_DxcContainerReflection)
XIOM_GUID_PTR(clsid_optimizer, CLSID_DxcOptimizer)
XIOM_GUID_PTR(clsid_container_builder, CLSID_DxcContainerBuilder)
XIOM_GUID_PTR(clsid_compiler_args, CLSID_DxcCompilerArgs)
XIOM_GUID_PTR(clsid_pdb_utils, CLSID_DxcPdbUtils)

#ifndef __cplusplus
#error "DXC bridge requires C++ compilation for __uuidof"
#endif

XIOM_GUID_PTR(iid_compiler3, __uuidof(IDxcCompiler3))
XIOM_GUID_PTR(iid_utils, __uuidof(IDxcUtils))
XIOM_GUID_PTR(iid_result, __uuidof(IDxcResult))
XIOM_GUID_PTR(iid_blob, __uuidof(IDxcBlob))
XIOM_GUID_PTR(iid_blob_encoding, __uuidof(IDxcBlobEncoding))
XIOM_GUID_PTR(iid_blob_utf8, __uuidof(IDxcBlobUtf8))
XIOM_GUID_PTR(iid_blob_wide, __uuidof(IDxcBlobWide))
XIOM_GUID_PTR(iid_include_handler, __uuidof(IDxcIncludeHandler))
XIOM_GUID_PTR(iid_operation_result, __uuidof(IDxcOperationResult))
XIOM_GUID_PTR(iid_validator, __uuidof(IDxcValidator))
XIOM_GUID_PTR(iid_validator2, __uuidof(IDxcValidator2))
XIOM_GUID_PTR(iid_linker, __uuidof(IDxcLinker))
XIOM_GUID_PTR(iid_assembler, __uuidof(IDxcAssembler))
XIOM_GUID_PTR(iid_container_reflection, __uuidof(IDxcContainerReflection))
XIOM_GUID_PTR(iid_container_builder, __uuidof(IDxcContainerBuilder))
XIOM_GUID_PTR(iid_compiler_args, __uuidof(IDxcCompilerArgs))
XIOM_GUID_PTR(iid_extra_outputs, __uuidof(IDxcExtraOutputs))
XIOM_GUID_PTR(iid_version_info, __uuidof(IDxcVersionInfo))
XIOM_GUID_PTR(iid_version_info2, __uuidof(IDxcVersionInfo2))
XIOM_GUID_PTR(iid_version_info3, __uuidof(IDxcVersionInfo3))
XIOM_GUID_PTR(iid_optimizer_pass, __uuidof(IDxcOptimizerPass))
XIOM_GUID_PTR(iid_optimizer, __uuidof(IDxcOptimizer))
XIOM_GUID_PTR(iid_pdb_utils, __uuidof(IDxcPdbUtils))
XIOM_GUID_PTR(iid_pdb_utils2, __uuidof(IDxcPdbUtils2))

// =========================================================================
// DxcCreateInstance / DxcCreateInstance2
// =========================================================================

int64_t xiom_dxc_create_instance(int64_t clsid_ptr, int64_t iid_ptr, int64_t ppv_ptr) {
    return HR(DxcCreateInstance(
        *(const GUID*)PTR(clsid_ptr),
        *(const GUID*)PTR(iid_ptr),
        (void**)PTR(ppv_ptr)));
}

int64_t xiom_dxc_create_instance2(int64_t p_malloc, int64_t clsid_ptr, int64_t iid_ptr, int64_t ppv_ptr) {
    return HR(DxcCreateInstance2(
        (IMalloc*)PTR(p_malloc),
        *(const GUID*)PTR(clsid_ptr),
        *(const GUID*)PTR(iid_ptr),
        (void**)PTR(ppv_ptr)));
}

// =========================================================================
// IUnknown
// =========================================================================

int64_t xiom_unknown_QueryInterface(int64_t ptr, int64_t riid, int64_t ppv_object) {
    void*** vtbl = *(void****)PTR(ptr);
    int32_t (*fn)(void*, const GUID*, void**) = (int32_t(*)(void*, const GUID*, void**))vtbl[0];
    return (int64_t)fn(PTR(ptr), (const GUID*)PTR(riid), (void**)PTR(ppv_object));
}

VTCALL_0_RET_I32(xiom_unknown_AddRef, 1)
VTCALL_0_RET_I32(xiom_unknown_Release, 2)

// =========================================================================
// IDxcBlob
// =========================================================================

VTCALL_0_RET_INT(xiom_blob_GetBufferPointer, 3)
VTCALL_0_RET_INT(xiom_blob_GetBufferSize, 4)

// =========================================================================
// IDxcBlobEncoding
// =========================================================================

VTCALL_2P_RET_I32(xiom_blob_encoding_GetEncoding, 5, p_known, p_code_page)

// =========================================================================
// IDxcBlobUtf8
// =========================================================================

VTCALL_0_RET_INT(xiom_blob_utf8_GetStringPointer, 6)
VTCALL_0_RET_INT(xiom_blob_utf8_GetStringLength, 7)

// =========================================================================
// IDxcBlobWide
// =========================================================================

VTCALL_0_RET_INT(xiom_blob_wide_GetStringPointer, 6)
VTCALL_0_RET_INT(xiom_blob_wide_GetStringLength, 7)

// =========================================================================
// IDxcIncludeHandler
// =========================================================================

VTCALL_2P_RET_I32(xiom_include_handler_LoadSource, 3, p_filename, pp_include_source)

// =========================================================================
// IDxcOperationResult
// =========================================================================

VTCALL_1_RET_I32(xiom_operation_result_GetStatus, 3, p_status, void*)

int64_t xiom_operation_result_GetResult(int64_t ptr, int64_t pp_result) {
    void*** vtbl = *(void****)PTR(ptr);
    int32_t (*fn)(void*, IDxcBlob**) = (int32_t(*)(void*, IDxcBlob**))vtbl[4];
    return (int64_t)fn(PTR(ptr), (IDxcBlob**)PTR(pp_result));
}

int64_t xiom_operation_result_GetErrorBuffer(int64_t ptr, int64_t pp_errors) {
    void*** vtbl = *(void****)PTR(ptr);
    int32_t (*fn)(void*, IDxcBlobEncoding**) = (int32_t(*)(void*, IDxcBlobEncoding**))vtbl[5];
    return (int64_t)fn(PTR(ptr), (IDxcBlobEncoding**)PTR(pp_errors));
}

// =========================================================================
// IDxcResult
// =========================================================================

int64_t xiom_result_HasOutput(int64_t ptr, int64_t dxc_out_kind) {
    void*** vtbl = *(void****)PTR(ptr);
    int32_t (*fn)(void*, DXC_OUT_KIND) = (int32_t(*)(void*, DXC_OUT_KIND))vtbl[6];
    return (int64_t)fn(PTR(ptr), (DXC_OUT_KIND)dxc_out_kind);
}

VTCALL_5P_RET_I32(xiom_result_GetOutput, 7, dxc_out_kind, riid, ppv_object, pp_output_name)

VTCALL_0_RET_I32(xiom_result_GetNumOutputs, 8)

int64_t xiom_result_GetOutputByIndex(int64_t ptr, int64_t index) {
    void*** vtbl = *(void****)PTR(ptr);
    uint32_t (*fn)(void*, uint32_t) = (uint32_t(*)(void*, uint32_t))vtbl[9];
    return (int64_t)fn(PTR(ptr), (uint32_t)index);
}

int64_t xiom_result_PrimaryOutput(int64_t ptr) {
    void*** vtbl = *(void****)PTR(ptr);
    uint32_t (*fn)(void*) = (uint32_t(*)(void*))vtbl[10];
    return (int64_t)fn(PTR(ptr));
}

// =========================================================================
// IDxcExtraOutputs
// =========================================================================

VTCALL_0_RET_I32(xiom_extra_outputs_GetOutputCount, 3)
VTCALL_6P_RET_I32(xiom_extra_outputs_GetOutput, 4, u_index, riid, ppv_object, pp_output_type, pp_output_name)

// =========================================================================
// IDxcCompiler3
// =========================================================================

int64_t xiom_compiler3_Compile(int64_t ptr, int64_t p_source, int64_t p_arguments, int64_t arg_count, int64_t p_include_handler, int64_t riid, int64_t pp_result) {
    void*** vtbl = *(void****)PTR(ptr);
    int32_t (*fn)(void*, const DxcBuffer*, const WCHAR**, uint32_t, IDxcIncludeHandler*, REFIID, void**) =
        (int32_t(*)(void*, const DxcBuffer*, const WCHAR**, uint32_t, IDxcIncludeHandler*, REFIID, void**))vtbl[3];
    return (int64_t)fn(PTR(ptr),
        (const DxcBuffer*)PTR(p_source),
        (const WCHAR**)PTR(p_arguments),
        (uint32_t)arg_count,
        (IDxcIncludeHandler*)PTR(p_include_handler),
        *(const GUID*)PTR(riid),
        (void**)PTR(pp_result));
}

int64_t xiom_compiler3_Disassemble(int64_t ptr, int64_t p_object, int64_t riid, int64_t pp_result) {
    void*** vtbl = *(void****)PTR(ptr);
    int32_t (*fn)(void*, const DxcBuffer*, REFIID, void**) =
        (int32_t(*)(void*, const DxcBuffer*, REFIID, void**))vtbl[4];
    return (int64_t)fn(PTR(ptr),
        (const DxcBuffer*)PTR(p_object),
        *(const GUID*)PTR(riid),
        (void**)PTR(pp_result));
}

// =========================================================================
// IDxcUtils
// =========================================================================

VTCALL_2P2I32_RET_I32(xiom_utils_CreateBlobFromBlob, 3, p_blob, offset, length, pp_result)
VTCALL_2P2I32_RET_I32(xiom_utils_CreateBlobFromPinned, 4, p_data, size, code_page, pp_blob_encoding)

int64_t xiom_utils_MoveToBlob(int64_t ptr, int64_t p_data, int64_t p_imalloc, int64_t size, int64_t code_page, int64_t pp_blob_encoding) {
    void*** vtbl = *(void****)PTR(ptr);
    int32_t (*fn)(void*, const void*, IMalloc*, uint32_t, uint32_t, IDxcBlobEncoding**) =
        (int32_t(*)(void*, const void*, IMalloc*, uint32_t, uint32_t, IDxcBlobEncoding**))vtbl[5];
    return (int64_t)fn(PTR(ptr), (const void*)PTR(p_data), (IMalloc*)PTR(p_imalloc), (uint32_t)size, (uint32_t)code_page, (IDxcBlobEncoding**)PTR(pp_blob_encoding));
}

VTCALL_2P2I32_RET_I32(xiom_utils_CreateBlob, 6, p_data, size, code_page, pp_blob_encoding)

int64_t xiom_utils_LoadFile(int64_t ptr, int64_t p_file_name, int64_t p_code_page, int64_t pp_blob_encoding) {
    void*** vtbl = *(void****)PTR(ptr);
    int32_t (*fn)(void*, const WCHAR*, uint32_t*, IDxcBlobEncoding**) =
        (int32_t(*)(void*, const WCHAR*, uint32_t*, IDxcBlobEncoding**))vtbl[7];
    return (int64_t)fn(PTR(ptr), (const WCHAR*)PTR(p_file_name), (uint32_t*)PTR(p_code_page), (IDxcBlobEncoding**)PTR(pp_blob_encoding));
}

VTCALL_2P_RET_I32(xiom_utils_CreateReadOnlyStreamFromBlob, 8, p_blob, pp_stream)
VTCALL_1_RET_I32(xiom_utils_CreateDefaultIncludeHandler, 9, pp_result, void*)

int64_t xiom_utils_GetBlobAsUtf8(int64_t ptr, int64_t p_blob, int64_t pp_blob_encoding) {
    void*** vtbl = *(void****)PTR(ptr);
    int32_t (*fn)(void*, IDxcBlob*, IDxcBlobUtf8**) =
        (int32_t(*)(void*, IDxcBlob*, IDxcBlobUtf8**))vtbl[10];
    return (int64_t)fn(PTR(ptr), (IDxcBlob*)PTR(p_blob), (IDxcBlobUtf8**)PTR(pp_blob_encoding));
}

int64_t xiom_utils_GetBlobAsWide(int64_t ptr, int64_t p_blob, int64_t pp_blob_encoding) {
    void*** vtbl = *(void****)PTR(ptr);
    int32_t (*fn)(void*, IDxcBlob*, IDxcBlobWide**) =
        (int32_t(*)(void*, IDxcBlob*, IDxcBlobWide**))vtbl[11];
    return (int64_t)fn(PTR(ptr), (IDxcBlob*)PTR(p_blob), (IDxcBlobWide**)PTR(pp_blob_encoding));
}

int64_t xiom_utils_GetDxilContainerPart(int64_t ptr, int64_t p_shader, int64_t dxc_part, int64_t pp_part_data, int64_t p_part_size) {
    void*** vtbl = *(void****)PTR(ptr);
    int32_t (*fn)(void*, const DxcBuffer*, uint32_t, void**, uint32_t*) =
        (int32_t(*)(void*, const DxcBuffer*, uint32_t, void**, uint32_t*))vtbl[12];
    return (int64_t)fn(PTR(ptr), (const DxcBuffer*)PTR(p_shader), (uint32_t)dxc_part, (void**)PTR(pp_part_data), (uint32_t*)PTR(p_part_size));
}

int64_t xiom_utils_CreateReflection(int64_t ptr, int64_t p_data, int64_t riid, int64_t ppv_reflection) {
    void*** vtbl = *(void****)PTR(ptr);
    int32_t (*fn)(void*, const DxcBuffer*, REFIID, void**) =
        (int32_t(*)(void*, const DxcBuffer*, REFIID, void**))vtbl[13];
    return (int64_t)fn(PTR(ptr), (const DxcBuffer*)PTR(p_data), *(const GUID*)PTR(riid), (void**)PTR(ppv_reflection));
}

VTCALL_8P_RET_I32(xiom_utils_BuildArguments, 14, p_source_name, p_entry_point, p_target_profile, p_arguments, arg_count, p_defines, define_count, pp_args)

VTCALL_3P_RET_I32(xiom_utils_GetPDBContents, 15, p_pdb_blob, pp_hash, pp_container)

// =========================================================================
// IDxcCompilerArgs
// =========================================================================

VTCALL_0_RET_INT(xiom_compiler_args_GetArguments, 3)
VTCALL_0_RET_I32(xiom_compiler_args_GetCount, 4)

int64_t xiom_compiler_args_AddArguments(int64_t ptr, int64_t p_arguments, int64_t arg_count) {
    void*** vtbl = *(void****)PTR(ptr);
    int32_t (*fn)(void*, const WCHAR**, uint32_t) =
        (int32_t(*)(void*, const WCHAR**, uint32_t))vtbl[5];
    return (int64_t)fn(PTR(ptr), (const WCHAR**)PTR(p_arguments), (uint32_t)arg_count);
}

int64_t xiom_compiler_args_AddArgumentsUTF8(int64_t ptr, int64_t p_arguments, int64_t arg_count) {
    void*** vtbl = *(void****)PTR(ptr);
    int32_t (*fn)(void*, const char**, uint32_t) =
        (int32_t(*)(void*, const char**, uint32_t))vtbl[6];
    return (int64_t)fn(PTR(ptr), (const char**)PTR(p_arguments), (uint32_t)arg_count);
}

int64_t xiom_compiler_args_AddDefines(int64_t ptr, int64_t p_defines, int64_t define_count) {
    void*** vtbl = *(void****)PTR(ptr);
    int32_t (*fn)(void*, const DxcDefine*, uint32_t) =
        (int32_t(*)(void*, const DxcDefine*, uint32_t))vtbl[7];
    return (int64_t)fn(PTR(ptr), (const DxcDefine*)PTR(p_defines), (uint32_t)define_count);
}

// =========================================================================
// IDxcValidator
// =========================================================================

int64_t xiom_validator_Validate(int64_t ptr, int64_t p_shader, int64_t flags, int64_t pp_result) {
    void*** vtbl = *(void****)PTR(ptr);
    int32_t (*fn)(void*, IDxcBlob*, uint32_t, IDxcOperationResult**) =
        (int32_t(*)(void*, IDxcBlob*, uint32_t, IDxcOperationResult**))vtbl[3];
    return (int64_t)fn(PTR(ptr), (IDxcBlob*)PTR(p_shader), (uint32_t)flags, (IDxcOperationResult**)PTR(pp_result));
}

// =========================================================================
// IDxcValidator2
// =========================================================================

int64_t xiom_validator2_ValidateWithDebug(int64_t ptr, int64_t p_shader, int64_t flags, int64_t p_opt_debug_bitcode, int64_t pp_result) {
    void*** vtbl = *(void****)PTR(ptr);
    int32_t (*fn)(void*, IDxcBlob*, uint32_t, DxcBuffer*, IDxcOperationResult**) =
        (int32_t(*)(void*, IDxcBlob*, uint32_t, DxcBuffer*, IDxcOperationResult**))vtbl[4];
    return (int64_t)fn(PTR(ptr), (IDxcBlob*)PTR(p_shader), (uint32_t)flags, (DxcBuffer*)PTR(p_opt_debug_bitcode), (IDxcOperationResult**)PTR(pp_result));
}

// =========================================================================
// IDxcContainerBuilder
// =========================================================================

VTCALL_1_RET_I32(xiom_container_builder_Load, 3, p_dxil_container_header, void*)

int64_t xiom_container_builder_AddPart(int64_t ptr, int64_t four_cc, int64_t p_source) {
    void*** vtbl = *(void****)PTR(ptr);
    int32_t (*fn)(void*, uint32_t, IDxcBlob*) =
        (int32_t(*)(void*, uint32_t, IDxcBlob*))vtbl[4];
    return (int64_t)fn(PTR(ptr), (uint32_t)four_cc, (IDxcBlob*)PTR(p_source));
}

VTCALL_1I32_RET_I32(xiom_container_builder_RemovePart, 5, four_cc)

VTCALL_1_RET_I32(xiom_container_builder_SerializeContainer, 6, pp_result, void*)

// =========================================================================
// IDxcAssembler
// =========================================================================

int64_t xiom_assembler_AssembleToContainer(int64_t ptr, int64_t p_shader, int64_t pp_result) {
    void*** vtbl = *(void****)PTR(ptr);
    int32_t (*fn)(void*, IDxcBlob*, IDxcOperationResult**) =
        (int32_t(*)(void*, IDxcBlob*, IDxcOperationResult**))vtbl[3];
    return (int64_t)fn(PTR(ptr), (IDxcBlob*)PTR(p_shader), (IDxcOperationResult**)PTR(pp_result));
}

// =========================================================================
// IDxcContainerReflection
// =========================================================================

VTCALL_1_RET_I32(xiom_container_reflection_Load, 3, p_container, void*)
VTCALL_1_RET_I32(xiom_container_reflection_GetPartCount, 4, p_result, void*)

int64_t xiom_container_reflection_GetPartKind(int64_t ptr, int64_t idx, int64_t p_result) {
    void*** vtbl = *(void****)PTR(ptr);
    int32_t (*fn)(void*, uint32_t, uint32_t*) =
        (int32_t(*)(void*, uint32_t, uint32_t*))vtbl[5];
    return (int64_t)fn(PTR(ptr), (uint32_t)idx, (uint32_t*)PTR(p_result));
}

VTCALL_2P_RET_I32(xiom_container_reflection_GetPartContent, 6, idx, pp_result)

int64_t xiom_container_reflection_FindFirstPartKind(int64_t ptr, int64_t kind, int64_t p_result) {
    void*** vtbl = *(void****)PTR(ptr);
    int32_t (*fn)(void*, uint32_t, uint32_t*) =
        (int32_t(*)(void*, uint32_t, uint32_t*))vtbl[7];
    return (int64_t)fn(PTR(ptr), (uint32_t)kind, (uint32_t*)PTR(p_result));
}

int64_t xiom_container_reflection_GetPartReflection(int64_t ptr, int64_t idx, int64_t riid, int64_t ppv_object) {
    void*** vtbl = *(void****)PTR(ptr);
    int32_t (*fn)(void*, uint32_t, REFIID, void**) =
        (int32_t(*)(void*, uint32_t, REFIID, void**))vtbl[8];
    return (int64_t)fn(PTR(ptr), (uint32_t)idx, *(const GUID*)PTR(riid), (void**)PTR(ppv_object));
}

// =========================================================================
// IDxcOptimizerPass
// =========================================================================

VTCALL_1_RET_I32(xiom_optimizer_pass_GetOptionName, 3, pp_result, void*)
VTCALL_1_RET_I32(xiom_optimizer_pass_GetDescription, 4, pp_result, void*)
VTCALL_1_RET_I32(xiom_optimizer_pass_GetOptionArgCount, 5, p_count, void*)

int64_t xiom_optimizer_pass_GetOptionArgName(int64_t ptr, int64_t arg_index, int64_t pp_result) {
    void*** vtbl = *(void****)PTR(ptr);
    int32_t (*fn)(void*, uint32_t, wchar_t**) =
        (int32_t(*)(void*, uint32_t, wchar_t**))vtbl[6];
    return (int64_t)fn(PTR(ptr), (uint32_t)arg_index, (wchar_t**)PTR(pp_result));
}

int64_t xiom_optimizer_pass_GetOptionArgDescription(int64_t ptr, int64_t arg_index, int64_t pp_result) {
    void*** vtbl = *(void****)PTR(ptr);
    int32_t (*fn)(void*, uint32_t, wchar_t**) =
        (int32_t(*)(void*, uint32_t, wchar_t**))vtbl[7];
    return (int64_t)fn(PTR(ptr), (uint32_t)arg_index, (wchar_t**)PTR(pp_result));
}

// =========================================================================
// IDxcOptimizer
// =========================================================================

VTCALL_1_RET_I32(xiom_optimizer_GetAvailablePassCount, 3, p_count, void*)
VTCALL_2P_RET_I32(xiom_optimizer_GetAvailablePass, 4, index, pp_result)

int64_t xiom_optimizer_RunOptimizer(int64_t ptr, int64_t p_blob, int64_t pp_options, int64_t option_count, int64_t p_output_module, int64_t pp_output_text) {
    void*** vtbl = *(void****)PTR(ptr);
    int32_t (*fn)(void*, IDxcBlob*, const wchar_t**, uint32_t, IDxcBlob**, IDxcBlobEncoding**) =
        (int32_t(*)(void*, IDxcBlob*, const wchar_t**, uint32_t, IDxcBlob**, IDxcBlobEncoding**))vtbl[5];
    return (int64_t)fn(PTR(ptr), (IDxcBlob*)PTR(p_blob), (const wchar_t**)PTR(pp_options),
        (uint32_t)option_count, (IDxcBlob**)PTR(p_output_module), (IDxcBlobEncoding**)PTR(pp_output_text));
}

// =========================================================================
// IDxcVersionInfo
// =========================================================================

VTCALL_2P_RET_I32(xiom_version_info_GetVersion, 3, p_major, p_minor)
VTCALL_1_RET_I32(xiom_version_info_GetFlags, 4, p_flags, void*)

// =========================================================================
// IDxcVersionInfo2
// =========================================================================

VTCALL_2P_RET_I32(xiom_version_info2_GetCommitInfo, 5, p_commit_count, pp_commit_hash)

// =========================================================================
// IDxcVersionInfo3
// =========================================================================

VTCALL_1_RET_I32(xiom_version_info3_GetCustomVersionString, 3, pp_version_string, void*)

// =========================================================================
// IDxcPdbUtils2
// =========================================================================

VTCALL_1_RET_I32(xiom_pdb_utils2_Load, 3, p_pdb_or_dxil, void*)
VTCALL_1_RET_I32(xiom_pdb_utils2_GetSourceCount, 4, p_count, void*)
VTCALL_2P_RET_I32(xiom_pdb_utils2_GetSource, 5, u_index, pp_result)
VTCALL_2P_RET_I32(xiom_pdb_utils2_GetSourceName, 6, u_index, pp_result)
VTCALL_1_RET_I32(xiom_pdb_utils2_GetLibraryPDBCount, 7, p_count, void*)
VTCALL_3P_RET_I32(xiom_pdb_utils2_GetLibraryPDB, 8, u_index, pp_out_pdb_utils, pp_library_name)
VTCALL_1_RET_I32(xiom_pdb_utils2_GetFlagCount, 9, p_count, void*)
VTCALL_2P_RET_I32(xiom_pdb_utils2_GetFlag, 10, u_index, pp_result)
VTCALL_1_RET_I32(xiom_pdb_utils2_GetArgCount, 11, p_count, void*)
VTCALL_2P_RET_I32(xiom_pdb_utils2_GetArg, 12, u_index, pp_result)
VTCALL_1_RET_I32(xiom_pdb_utils2_GetArgPairCount, 13, p_count, void*)
VTCALL_3P_RET_I32(xiom_pdb_utils2_GetArgPair, 14, u_index, pp_name, pp_value)
VTCALL_1_RET_I32(xiom_pdb_utils2_GetDefineCount, 15, p_count, void*)
VTCALL_2P_RET_I32(xiom_pdb_utils2_GetDefine, 16, u_index, pp_result)
VTCALL_1_RET_I32(xiom_pdb_utils2_GetTargetProfile, 17, pp_result, void*)
VTCALL_1_RET_I32(xiom_pdb_utils2_GetEntryPoint, 18, pp_result, void*)
VTCALL_1_RET_I32(xiom_pdb_utils2_GetMainFileName, 19, pp_result, void*)
VTCALL_1_RET_I32(xiom_pdb_utils2_GetHash, 20, pp_result, void*)
VTCALL_1_RET_I32(xiom_pdb_utils2_GetName, 21, pp_result, void*)
VTCALL_1_RET_I32(xiom_pdb_utils2_GetVersionInfo, 22, pp_version_info, void*)
VTCALL_1_RET_I32(xiom_pdb_utils2_GetCustomToolchainID, 23, p_id, void*)
VTCALL_1_RET_I32(xiom_pdb_utils2_GetCustomToolchainData, 24, pp_blob, void*)
VTCALL_1_RET_I32(xiom_pdb_utils2_GetWholeDxil, 25, pp_result, void*)
VTCALL_0_RET_I32(xiom_pdb_utils2_IsFullPDB, 26)
VTCALL_0_RET_I32(xiom_pdb_utils2_IsPDBRef, 27)

// =========================================================================
// IDxcLinker
// =========================================================================

VTCALL_2P_RET_I32(xiom_linker_RegisterLibrary, 3, p_lib_name, p_lib)

int64_t xiom_linker_Link(int64_t ptr, int64_t p_entry_name, int64_t p_target_profile, int64_t p_lib_names, int64_t lib_count, int64_t p_arguments, int64_t arg_count, int64_t pp_result) {
    void*** vtbl = *(void****)PTR(ptr);
    int32_t (*fn)(void*, const wchar_t*, const wchar_t*, const wchar_t**, uint32_t, const wchar_t**, uint32_t, IDxcOperationResult**) =
        (int32_t(*)(void*, const wchar_t*, const wchar_t*, const wchar_t**, uint32_t, const wchar_t**, uint32_t, IDxcOperationResult**))vtbl[4];
    return (int64_t)fn(PTR(ptr),
        (const wchar_t*)PTR(p_entry_name), (const wchar_t*)PTR(p_target_profile),
        (const wchar_t**)PTR(p_lib_names), (uint32_t)lib_count,
        (const wchar_t**)PTR(p_arguments), (uint32_t)arg_count,
        (IDxcOperationResult**)PTR(pp_result));
}

#ifdef __cplusplus
}
#endif
