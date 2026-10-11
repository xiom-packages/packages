// XIOM -- xiom.glslang: glslang (Khronos GLSL/ESSL/HLSL compiler) bindings.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// DESIGN: dynamic loader path (sdl3 template). The package does NOT link
// against glslang at build time; `glslang_load` resolves glslang.dll and
// `glslang_load_resource_limits` resolves glslang-default-resource-limits.dll
// through `xiom.ffi.dl` at runtime, and every call is a fn-pointer cast
// inside this module -- the ONLY module in the package with `unsafe`.
//
// The glslang project historically exposed a C++ API (TShader/TProgram --
// the mangled `?parse@TShader@glslang@@...` family in the DLL), which is NOT
// an FFI surface.  Since 2019 upstream ships a C interface
// (Include/glslang_c_interface.h + SPIRV/CInterface/spirv_c_interface.cpp)
// that wraps the full compile path: shader create/preprocess/parse, program
// link, SPIR-V generation and an OWNED-BUFFER copy-out
// (`glslang_program_SPIRV_get` memcpys into a caller-owned buffer).  This
// package binds that C interface (41 entry points), the legacy extern "C"
// Sh* surface (16 entry points) and the C resource-limits helpers (4 entry
// points, shipped in glslang-default-resource-limits.dll).  See
// docs/COVERAGE.md for the oracle/bound/resolved counts and the C/C++ split.
//
// DISCIPLINE (lane B-11..B-20): out-params go into XIOM-owned Vec[UInt8]
// slots with byte-indexed readback; no ffi.ptr_write_* at offsets; no raw
// pointer arithmetic (Int address math only, and only ever stored into slots
// for C to dereference); one owned slot per out-param.  C reads OUR string
// memory for in-params (`Str.c_str()`), and the few foreign strings we read
// back (info logs, preprocessed source, StageName) are copied with
// `Str::from_c_str` -- the proven read direction (B-20 affects pointer
// round-trips, not C-string copies; see docs/COVERAGE.md).
//
// G2 pin: glslang 16.3.0 as shipped in Vulkan SDK 1.4.350.0
// (headers SHA256 set + DLL hashes in SPEC.md).  SKIP-green when absent.

module xiom.glslang

use xiom.ffi;
use xiom.ffi.dl;
use xiom.convert;

// =========================================================================
// Library identity, loader classification, pinned sizes
// =========================================================================

/// Runtime library name resolved by the core loader (Windows soname).
pub const GLSLANG_SONAME: Str = "glslang.dll";

/// Companion library for the C resource-limits helpers.
pub const GLSLANG_RESOURCE_LIMITS_SONAME: Str = "glslang-default-resource-limits.dll";

/// `glslang_load` failure kind: library absent (callers report SKIP).
pub const GLSLANG_LOAD_ABSENT: Int = 0;
/// `glslang_load` failure kind: library present, symbol missing (ABI drift).
pub const GLSLANG_LOAD_ABI: Int = 1;

/// C entry points exported by glslang.dll (oracle-verified; see
/// tools/gen_glslang.ps1 -Action verify).
pub const GLSLANG_CORE_ENTRY_POINTS: Int = 57;
/// C entry points exported by glslang-default-resource-limits.dll.
pub const GLSLANG_RESOURCE_LIMITS_ENTRY_POINTS: Int = 4;
/// Total C entry points across both libraries (the resolve gate).
pub const GLSLANG_TOTAL_C_ENTRY_POINTS: Int = 61;

/// sizeof(glslang_version_t) on x64 (3 ints + 4 pad + char*).
pub const GLSLANG_VERSION_SIZE: Int = 24;
/// sizeof(glslang_input_t) on x64 (pinned field offsets below).
pub const GLSLANG_INPUT_SIZE: Int = 96;
/// sizeof(glslang_resource_t) == sizeof(TBuiltInResource): 102 ints (408) +
/// 9 bools (9) padded to 4 -> 420.  Asserted by the static_asserts in
/// upstream glslang_c_interface.cpp.
pub const GLSLANG_RESOURCE_SIZE: Int = 420;
/// sizeof(glslang_spv_options_t): 10 bools.
pub const GLSLANG_SPV_OPTIONS_SIZE: Int = 10;
/// SPIR-V binary header word 0 (magic), little-endian on disk.
pub const GLSLANG_SPIRV_MAGIC_WORD: Int = 0x07230203;

// glslang_input_t field offsets (x64, pinned to the 1.4.350.0 headers; the
// C struct is fixed by the static_asserts against glslang::TEnvironment use).
pub const GLSLANG_INPUT_OFF_LANGUAGE: Int = 0;
pub const GLSLANG_INPUT_OFF_STAGE: Int = 4;
pub const GLSLANG_INPUT_OFF_CLIENT: Int = 8;
pub const GLSLANG_INPUT_OFF_CLIENT_VERSION: Int = 12;
pub const GLSLANG_INPUT_OFF_TARGET_LANGUAGE: Int = 16;
pub const GLSLANG_INPUT_OFF_TARGET_LANGUAGE_VERSION: Int = 20;
pub const GLSLANG_INPUT_OFF_CODE: Int = 24;
pub const GLSLANG_INPUT_OFF_DEFAULT_VERSION: Int = 32;
pub const GLSLANG_INPUT_OFF_DEFAULT_PROFILE: Int = 36;
pub const GLSLANG_INPUT_OFF_FORCE_DEFAULT: Int = 40;
pub const GLSLANG_INPUT_OFF_FORWARD_COMPATIBLE: Int = 44;
pub const GLSLANG_INPUT_OFF_MESSAGES: Int = 48;
pub const GLSLANG_INPUT_OFF_RESOURCE: Int = 56;
pub const GLSLANG_INPUT_OFF_CALLBACKS_CTX: Int = 88;

// =========================================================================
// Constants (source-generated; counts checked by tools/gen_glslang.ps1)
// =========================================================================

// // ===== BEGIN GENERATED CONSTANTS (tools/gen_glslang.ps1) =====
// Source-generated from the pinned glslang 1.4.350.0 SDK headers by
// tools/gen_glslang.ps1; re-run with -Action verify to check for drift.
// Constant count: 290

// ---- Public/ShaderLang.h ----
pub const EShLangVertex: Int = 0;
pub const EShLangTessControl: Int = 1;
pub const EShLangTessEvaluation: Int = 2;
pub const EShLangGeometry: Int = 3;
pub const EShLangFragment: Int = 4;
pub const EShLangCompute: Int = 5;
pub const EShLangRayGen: Int = 6;
pub const EShLangRayGenNV: Int = 6;
pub const EShLangIntersect: Int = 7;
pub const EShLangIntersectNV: Int = 7;
pub const EShLangAnyHit: Int = 8;
pub const EShLangAnyHitNV: Int = 8;
pub const EShLangClosestHit: Int = 9;
pub const EShLangClosestHitNV: Int = 9;
pub const EShLangMiss: Int = 10;
pub const EShLangMissNV: Int = 10;
pub const EShLangCallable: Int = 11;
pub const EShLangCallableNV: Int = 11;
pub const EShLangTask: Int = 12;
pub const EShLangTaskNV: Int = 12;
pub const EShLangMesh: Int = 13;
pub const EShLangMeshNV: Int = 13;
pub const EShLangCount: Int = 14;
pub const EShLangVertexMask: Int = 1;
pub const EShLangTessControlMask: Int = 2;
pub const EShLangTessEvaluationMask: Int = 4;
pub const EShLangGeometryMask: Int = 8;
pub const EShLangFragmentMask: Int = 16;
pub const EShLangComputeMask: Int = 32;
pub const EShLangRayGenMask: Int = 64;
pub const EShLangRayGenNVMask: Int = 64;
pub const EShLangIntersectMask: Int = 128;
pub const EShLangIntersectNVMask: Int = 128;
pub const EShLangAnyHitMask: Int = 256;
pub const EShLangAnyHitNVMask: Int = 256;
pub const EShLangClosestHitMask: Int = 512;
pub const EShLangClosestHitNVMask: Int = 512;
pub const EShLangMissMask: Int = 1024;
pub const EShLangMissNVMask: Int = 1024;
pub const EShLangCallableMask: Int = 2048;
pub const EShLangCallableNVMask: Int = 2048;
pub const EShLangTaskMask: Int = 4096;
pub const EShLangTaskNVMask: Int = 4096;
pub const EShLangMeshMask: Int = 8192;
pub const EShLangMeshNVMask: Int = 8192;
pub const EShLanguageMaskCount: Int = 8193;
pub const EShSourceNone: Int = 0;
pub const EShSourceGlsl: Int = 1;
pub const EShSourceHlsl: Int = 2;
pub const EShSourceCount: Int = 3;
pub const EShClientNone: Int = 0;
pub const EShClientVulkan: Int = 1;
pub const EShClientOpenGL: Int = 2;
pub const EShClientCount: Int = 3;
pub const EShTargetNone: Int = 0;
pub const EShTargetSpv: Int = 1;
pub const EshTargetSpv: Int = 1;
pub const EShTargetCount: Int = 2;
pub const EShTargetVulkan_1_0: Int = 4194304;
pub const EShTargetVulkan_1_1: Int = 4198400;
pub const EShTargetVulkan_1_2: Int = 4202496;
pub const EShTargetVulkan_1_3: Int = 4206592;
pub const EShTargetVulkan_1_4: Int = 4210688;
pub const EShTargetOpenGL_450: Int = 450;
pub const EShTargetClientVersionCount: Int = 6;
pub const EShTargetSpv_1_0: Int = 65536;
pub const EShTargetSpv_1_1: Int = 65792;
pub const EShTargetSpv_1_2: Int = 66048;
pub const EShTargetSpv_1_3: Int = 66304;
pub const EShTargetSpv_1_4: Int = 66560;
pub const EShTargetSpv_1_5: Int = 66816;
pub const EShTargetSpv_1_6: Int = 67072;
pub const EShTargetLanguageVersionCount: Int = 7;
pub const ElpNone: Int = 0;
pub const ElpShared: Int = 1;
pub const ElpStd140: Int = 2;
pub const ElpStd430: Int = 3;
pub const ElpPacked: Int = 4;
pub const ElpScalar: Int = 5;
pub const ElpCount: Int = 6;
pub const EShExVertexFragment: Int = 0;
pub const EShExFragment: Int = 1;
pub const EShOptNoGeneration: Int = 0;
pub const EShOptNone: Int = 1;
pub const EShOptSimple: Int = 2;
pub const EShOptFull: Int = 3;
pub const EshOptLevelCount: Int = 4;
pub const EShTexSampTransKeep: Int = 0;
pub const EShTexSampTransUpgradeTextureRemoveSampler: Int = 1;
pub const EShTexSampTransCount: Int = 2;
pub const EShMsgDefault: Int = 0;
pub const EShMsgRelaxedErrors: Int = 1;
pub const EShMsgSuppressWarnings: Int = 2;
pub const EShMsgAST: Int = 4;
pub const EShMsgSpvRules: Int = 8;
pub const EShMsgVulkanRules: Int = 16;
pub const EShMsgOnlyPreprocessor: Int = 32;
pub const EShMsgReadHlsl: Int = 64;
pub const EShMsgCascadingErrors: Int = 128;
pub const EShMsgKeepUncalled: Int = 256;
pub const EShMsgHlslOffsets: Int = 512;
pub const EShMsgDebugInfo: Int = 1024;
pub const EShMsgHlslEnable16BitTypes: Int = 2048;
pub const EShMsgHlslLegalization: Int = 4096;
pub const EShMsgHlslDX9Compatible: Int = 8192;
pub const EShMsgBuiltinSymbolTable: Int = 16384;
pub const EShMsgEnhanced: Int = 32768;
pub const EShMsgAbsolutePath: Int = 65536;
pub const EShMsgDisplayErrorColumn: Int = 131072;
pub const EShMsgLinkTimeOptimization: Int = 262144;
pub const EShMsgValidateCrossStageIO: Int = 524288;
pub const EShMsgCount: Int = 524289;
pub const EShReflectionDefault: Int = 0;
pub const EShReflectionStrictArraySuffix: Int = 1;
pub const EShReflectionBasicArraySuffix: Int = 2;
pub const EShReflectionIntermediateIO: Int = 4;
pub const EShReflectionSeparateBuffers: Int = 8;
pub const EShReflectionAllBlockVariables: Int = 16;
pub const EShReflectionUnwrapIOBlocks: Int = 32;
pub const EShReflectionAllIOVariables: Int = 64;
pub const EShReflectionSharedStd140SSBO: Int = 128;
pub const EShReflectionSharedStd140UBO: Int = 256;
pub const EShReflectionCount: Int = 257;
pub const EResSampler: Int = 0;
pub const EResTexture: Int = 1;
pub const EResImage: Int = 2;
pub const EResUbo: Int = 3;
pub const EResSsbo: Int = 4;
pub const EResUav: Int = 5;
pub const EResCombinedSampler: Int = 6;
pub const EResAs: Int = 7;
pub const EResTensor: Int = 8;
pub const EResCount: Int = 9;
pub const EbsUniform: Int = 0;
pub const EbsStorageBuffer: Int = 1;
pub const EbsPushConstant: Int = 2;
pub const EbsNone: Int = 3;
pub const EbsCount: Int = 4;
// ---- Include/glslang_c_shader_types.h ----
pub const GLSLANG_STAGE_VERTEX: Int = 0;
pub const GLSLANG_STAGE_TESSCONTROL: Int = 1;
pub const GLSLANG_STAGE_TESSEVALUATION: Int = 2;
pub const GLSLANG_STAGE_GEOMETRY: Int = 3;
pub const GLSLANG_STAGE_FRAGMENT: Int = 4;
pub const GLSLANG_STAGE_COMPUTE: Int = 5;
pub const GLSLANG_STAGE_RAYGEN: Int = 6;
pub const GLSLANG_STAGE_RAYGEN_NV: Int = 6;
pub const GLSLANG_STAGE_INTERSECT: Int = 7;
pub const GLSLANG_STAGE_INTERSECT_NV: Int = 7;
pub const GLSLANG_STAGE_ANYHIT: Int = 8;
pub const GLSLANG_STAGE_ANYHIT_NV: Int = 8;
pub const GLSLANG_STAGE_CLOSESTHIT: Int = 9;
pub const GLSLANG_STAGE_CLOSESTHIT_NV: Int = 9;
pub const GLSLANG_STAGE_MISS: Int = 10;
pub const GLSLANG_STAGE_MISS_NV: Int = 10;
pub const GLSLANG_STAGE_CALLABLE: Int = 11;
pub const GLSLANG_STAGE_CALLABLE_NV: Int = 11;
pub const GLSLANG_STAGE_TASK: Int = 12;
pub const GLSLANG_STAGE_TASK_NV: Int = 12;
pub const GLSLANG_STAGE_MESH: Int = 13;
pub const GLSLANG_STAGE_MESH_NV: Int = 13;
pub const GLSLANG_STAGE_COUNT: Int = 14;
pub const GLSLANG_STAGE_VERTEX_MASK: Int = 1;
pub const GLSLANG_STAGE_TESSCONTROL_MASK: Int = 2;
pub const GLSLANG_STAGE_TESSEVALUATION_MASK: Int = 4;
pub const GLSLANG_STAGE_GEOMETRY_MASK: Int = 8;
pub const GLSLANG_STAGE_FRAGMENT_MASK: Int = 16;
pub const GLSLANG_STAGE_COMPUTE_MASK: Int = 32;
pub const GLSLANG_STAGE_RAYGEN_MASK: Int = 64;
pub const GLSLANG_STAGE_RAYGEN_NV_MASK: Int = 64;
pub const GLSLANG_STAGE_INTERSECT_MASK: Int = 128;
pub const GLSLANG_STAGE_INTERSECT_NV_MASK: Int = 128;
pub const GLSLANG_STAGE_ANYHIT_MASK: Int = 256;
pub const GLSLANG_STAGE_ANYHIT_NV_MASK: Int = 256;
pub const GLSLANG_STAGE_CLOSESTHIT_MASK: Int = 512;
pub const GLSLANG_STAGE_CLOSESTHIT_NV_MASK: Int = 512;
pub const GLSLANG_STAGE_MISS_MASK: Int = 1024;
pub const GLSLANG_STAGE_MISS_NV_MASK: Int = 1024;
pub const GLSLANG_STAGE_CALLABLE_MASK: Int = 2048;
pub const GLSLANG_STAGE_CALLABLE_NV_MASK: Int = 2048;
pub const GLSLANG_STAGE_TASK_MASK: Int = 4096;
pub const GLSLANG_STAGE_TASK_NV_MASK: Int = 4096;
pub const GLSLANG_STAGE_MESH_MASK: Int = 8192;
pub const GLSLANG_STAGE_MESH_NV_MASK: Int = 8192;
pub const GLSLANG_STAGE_MASK_COUNT: Int = 8193;
pub const GLSLANG_SOURCE_NONE: Int = 0;
pub const GLSLANG_SOURCE_GLSL: Int = 1;
pub const GLSLANG_SOURCE_HLSL: Int = 2;
pub const GLSLANG_SOURCE_COUNT: Int = 3;
pub const GLSLANG_CLIENT_NONE: Int = 0;
pub const GLSLANG_CLIENT_VULKAN: Int = 1;
pub const GLSLANG_CLIENT_OPENGL: Int = 2;
pub const GLSLANG_CLIENT_COUNT: Int = 3;
pub const GLSLANG_TARGET_NONE: Int = 0;
pub const GLSLANG_TARGET_SPV: Int = 1;
pub const GLSLANG_TARGET_COUNT: Int = 2;
pub const GLSLANG_TARGET_VULKAN_1_0: Int = 4194304;
pub const GLSLANG_TARGET_VULKAN_1_1: Int = 4198400;
pub const GLSLANG_TARGET_VULKAN_1_2: Int = 4202496;
pub const GLSLANG_TARGET_VULKAN_1_3: Int = 4206592;
pub const GLSLANG_TARGET_VULKAN_1_4: Int = 4210688;
pub const GLSLANG_TARGET_OPENGL_450: Int = 450;
pub const GLSLANG_TARGET_CLIENT_VERSION_COUNT: Int = 6;
pub const GLSLANG_TARGET_SPV_1_0: Int = 65536;
pub const GLSLANG_TARGET_SPV_1_1: Int = 65792;
pub const GLSLANG_TARGET_SPV_1_2: Int = 66048;
pub const GLSLANG_TARGET_SPV_1_3: Int = 66304;
pub const GLSLANG_TARGET_SPV_1_4: Int = 66560;
pub const GLSLANG_TARGET_SPV_1_5: Int = 66816;
pub const GLSLANG_TARGET_SPV_1_6: Int = 67072;
pub const GLSLANG_TARGET_LANGUAGE_VERSION_COUNT: Int = 7;
pub const GLSLANG_EX_VERTEX_FRAGMENT: Int = 0;
pub const GLSLANG_EX_FRAGMENT: Int = 1;
pub const GLSLANG_OPT_NO_GENERATION: Int = 0;
pub const GLSLANG_OPT_NONE: Int = 1;
pub const GLSLANG_OPT_SIMPLE: Int = 2;
pub const GLSLANG_OPT_FULL: Int = 3;
pub const GLSLANG_OPT_LEVEL_COUNT: Int = 4;
pub const GLSLANG_TEX_SAMP_TRANS_KEEP: Int = 0;
pub const GLSLANG_TEX_SAMP_TRANS_UPGRADE_TEXTURE_REMOVE_SAMPLER: Int = 1;
pub const GLSLANG_TEX_SAMP_TRANS_COUNT: Int = 2;
pub const GLSLANG_MSG_DEFAULT_BIT: Int = 0;
pub const GLSLANG_MSG_RELAXED_ERRORS_BIT: Int = 1;
pub const GLSLANG_MSG_SUPPRESS_WARNINGS_BIT: Int = 2;
pub const GLSLANG_MSG_AST_BIT: Int = 4;
pub const GLSLANG_MSG_SPV_RULES_BIT: Int = 8;
pub const GLSLANG_MSG_VULKAN_RULES_BIT: Int = 16;
pub const GLSLANG_MSG_ONLY_PREPROCESSOR_BIT: Int = 32;
pub const GLSLANG_MSG_READ_HLSL_BIT: Int = 64;
pub const GLSLANG_MSG_CASCADING_ERRORS_BIT: Int = 128;
pub const GLSLANG_MSG_KEEP_UNCALLED_BIT: Int = 256;
pub const GLSLANG_MSG_HLSL_OFFSETS_BIT: Int = 512;
pub const GLSLANG_MSG_DEBUG_INFO_BIT: Int = 1024;
pub const GLSLANG_MSG_HLSL_ENABLE_16BIT_TYPES_BIT: Int = 2048;
pub const GLSLANG_MSG_HLSL_LEGALIZATION_BIT: Int = 4096;
pub const GLSLANG_MSG_HLSL_DX9_COMPATIBLE_BIT: Int = 8192;
pub const GLSLANG_MSG_BUILTIN_SYMBOL_TABLE_BIT: Int = 16384;
pub const GLSLANG_MSG_ENHANCED: Int = 32768;
pub const GLSLANG_MSG_ABSOLUTE_PATH: Int = 65536;
pub const GLSLANG_MSG_DISPLAY_ERROR_COLUMN: Int = 131072;
pub const GLSLANG_MSG_LINK_TIME_OPTIMIZATION_BIT: Int = 262144;
pub const GLSLANG_MSG_VALIDATE_CROSS_STAGE_IO_BIT: Int = 524288;
pub const GLSLANG_MSG_COUNT: Int = 524289;
pub const GLSLANG_REFLECTION_DEFAULT_BIT: Int = 0;
pub const GLSLANG_REFLECTION_STRICT_ARRAY_SUFFIX_BIT: Int = 1;
pub const GLSLANG_REFLECTION_BASIC_ARRAY_SUFFIX_BIT: Int = 2;
pub const GLSLANG_REFLECTION_INTERMEDIATE_IOO_BIT: Int = 4;
pub const GLSLANG_REFLECTION_SEPARATE_BUFFERS_BIT: Int = 8;
pub const GLSLANG_REFLECTION_ALL_BLOCK_VARIABLES_BIT: Int = 16;
pub const GLSLANG_REFLECTION_UNWRAP_IO_BLOCKS_BIT: Int = 32;
pub const GLSLANG_REFLECTION_ALL_IO_VARIABLES_BIT: Int = 64;
pub const GLSLANG_REFLECTION_SHARED_STD140_SSBO_BIT: Int = 128;
pub const GLSLANG_REFLECTION_SHARED_STD140_UBO_BIT: Int = 256;
pub const GLSLANG_REFLECTION_COUNT: Int = 257;
pub const GLSLANG_BAD_PROFILE: Int = 0;
pub const GLSLANG_NO_PROFILE: Int = 1;
pub const GLSLANG_CORE_PROFILE: Int = 2;
pub const GLSLANG_COMPATIBILITY_PROFILE: Int = 4;
pub const GLSLANG_ES_PROFILE: Int = 8;
pub const GLSLANG_PROFILE_COUNT: Int = 9;
pub const GLSLANG_SHADER_DEFAULT_BIT: Int = 0;
pub const GLSLANG_SHADER_AUTO_MAP_BINDINGS: Int = 1;
pub const GLSLANG_SHADER_AUTO_MAP_LOCATIONS: Int = 2;
pub const GLSLANG_SHADER_VULKAN_RULES_RELAXED: Int = 4;
pub const GLSLANG_SHADER_BINDINGS_PER_RESOURCE_TYPE: Int = 8;
pub const GLSLANG_SHADER_COUNT: Int = 9;
pub const GLSLANG_RESOURCE_TYPE_SAMPLER: Int = 0;
pub const GLSLANG_RESOURCE_TYPE_TEXTURE: Int = 1;
pub const GLSLANG_RESOURCE_TYPE_IMAGE: Int = 2;
pub const GLSLANG_RESOURCE_TYPE_UBO: Int = 3;
pub const GLSLANG_RESOURCE_TYPE_SSBO: Int = 4;
pub const GLSLANG_RESOURCE_TYPE_UAV: Int = 5;
pub const GLSLANG_RESOURCE_TYPE_COMBINED_SAMPLER: Int = 6;
pub const GLSLANG_RESOURCE_TYPE_AS: Int = 7;
pub const GLSLANG_RESOURCE_TYPE_TENSOR: Int = 8;
pub const GLSLANG_RESOURCE_TYPE_COUNT: Int = 9;
// ---- MachineIndependent/Versions.h ----
pub const EBadProfile: Int = 0;
pub const ENoProfile: Int = 1;
pub const ECoreProfile: Int = 2;
pub const ECompatibilityProfile: Int = 4;
pub const EEsProfile: Int = 8;
pub const EProfileCount: Int = 9;
pub const EBhMissing: Int = 0;
pub const EBhRequire: Int = 1;
pub const EBhEnable: Int = 2;
pub const EBhWarn: Int = 3;
pub const EBhDisable: Int = 4;
pub const EBhDisablePartial: Int = 5;
// ---- build_info.h ----
pub const GLSLANG_VERSION_MAJOR: Int = 16;
pub const GLSLANG_VERSION_MINOR: Int = 3;
pub const GLSLANG_VERSION_PATCH: Int = 0;
// ===== END GENERATED CONSTANTS =====


// =========================================================================
// Types
// =========================================================================

/// Failure modes of the loaders, distinguishing "library absent" (callers
/// report SKIP) from "library present but ABI symbols missing" (a real
/// install/SDK mismatch -- callers report FAIL).
pub type GlslangLoadError = {
  kind: Int;
  message: Str;
}

/// glslang_version_t (the `flavor` pointer is left unread; see COVERAGE).
pub type GlslangVersion = {
  major: Int;
  minor: Int;
  patch: Int;
}

/// A loaded glslang.dll.  `handle` is the dl handle; the `p_*` fields are
/// resolved symbol addresses.  Owned by the caller; release with
/// `glslang_close`.
pub type GlslangLibrary = {
  handle: Int;
  p_sh_initialize: Int;
  p_sh_finalize: Int;
  p_stage_name: Int;
  p_sh_construct_compiler: Int;
  p_sh_construct_linker: Int;
  p_sh_construct_uniform_map: Int;
  p_sh_destruct: Int;
  p_sh_compile: Int;
  p_sh_link_ext: Int;
  p_sh_set_encryption_method: Int;
  p_sh_get_info_log: Int;
  p_sh_get_executable: Int;
  p_sh_set_virtual_attribute_bindings: Int;
  p_sh_set_fixed_attribute_bindings: Int;
  p_sh_exclude_attributes: Int;
  p_sh_get_uniform_location: Int;
  p_get_version: Int;
  p_initialize_process: Int;
  p_finalize_process: Int;
  p_shader_create: Int;
  p_shader_delete: Int;
  p_shader_set_preamble: Int;
  p_shader_set_entry_point: Int;
  p_shader_set_invert_y: Int;
  p_shader_shift_binding: Int;
  p_shader_shift_binding_for_set: Int;
  p_shader_set_options: Int;
  p_shader_set_glsl_version: Int;
  p_shader_set_default_uniform_block_set_and_binding: Int;
  p_shader_set_default_uniform_block_name: Int;
  p_shader_set_resource_set_binding: Int;
  p_shader_preprocess: Int;
  p_shader_parse: Int;
  p_shader_get_preprocessed_code: Int;
  p_shader_set_preprocessed_code: Int;
  p_shader_get_info_log: Int;
  p_shader_get_info_debug_log: Int;
  p_program_create: Int;
  p_program_delete: Int;
  p_program_add_shader: Int;
  p_program_link: Int;
  p_program_add_source_text: Int;
  p_program_set_source_file: Int;
  p_program_map_io: Int;
  p_program_map_io_with_resolver_and_mapper: Int;
  p_program_spirv_generate: Int;
  p_program_spirv_generate_with_options: Int;
  p_program_spirv_get_size: Int;
  p_program_spirv_get: Int;
  p_program_spirv_get_ptr: Int;
  p_program_spirv_get_messages: Int;
  p_program_get_info_log: Int;
  p_program_get_info_debug_log: Int;
  p_glsl_mapper_create: Int;
  p_glsl_mapper_delete: Int;
  p_glsl_resolver_create: Int;
  p_glsl_resolver_delete: Int;
}

/// A loaded glslang-default-resource-limits.dll.
pub type GlslangResourceLimitsLibrary = {
  handle: Int;
  p_resource: Int;
  p_default_resource: Int;
  p_default_resource_string: Int;
  p_decode_resource_limits: Int;
}

// =========================================================================
// Owned-slot helpers (byte-indexed; the proven readback direction)
// =========================================================================

/// Zeroed owned byte slot of `n` bytes (the lane's out-param idiom).
fn glslang_slot(n: Int) -> Vec[UInt8]
  requires: n > 0
{
  var s: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < n {
    s.push(0 as UInt8);
    i = i + 1;
  }
  return s;
}

fn glslang_read_u32(buf: &Vec[UInt8], off: Int) -> Int
  requires: off >= 0
  requires: buf.len() >= off + 4
{
  let b0 = buf[off + 0] as Int;
  let b1 = buf[off + 1] as Int;
  let b2 = buf[off + 2] as Int;
  let b3 = buf[off + 3] as Int;
  return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24);
}

fn glslang_write_u32(buf: &mut Vec[UInt8], off: Int, v: Int)
  requires: off >= 0
  requires: buf.len() >= off + 4
{
  buf[off + 0] = ( v        & 0xFF) as UInt8;
  buf[off + 1] = ((v >>  8) & 0xFF) as UInt8;
  buf[off + 2] = ((v >> 16) & 0xFF) as UInt8;
  buf[off + 3] = ((v >> 24) & 0xFF) as UInt8;
}

fn glslang_write_u64(buf: &mut Vec[UInt8], off: Int, v: Int)
  requires: off >= 0
  requires: buf.len() >= off + 8
{
  glslang_write_u32(buf, off + 0, v & 0xFFFFFFFF);
  glslang_write_u32(buf, off + 4, (v >> 32) & 0xFFFFFFFF);
}

/// Raw pointer to a Str's NUL-terminated bytes (for building C structures in
/// owned slots; valid while `s` lives -- the caller must keep `s` alive for
/// as long as C may read it).
/// Complexity: O(1).
pub fn glslang_str_c_ptr(s: Str) -> Int
  requires: s.len() > 0
{
  unsafe {
    return s.c_str() as Int;
  }
}

/// C-string copy of a foreign `const char*` (NULL -> "").  The read
/// direction is safe: glslang strings are NUL-terminated and owned by the
/// shader/program/library; the copy is taken while the owner is alive.
fn glslang_cstr(p: Int) -> Str
  requires: p >= 0
{
  if p == 0 { return ""; }
  unsafe {
    return Str::from_c_str(p as *UInt8);
  }
}

// =========================================================================
// Loaders
// =========================================================================

/// Load glslang.dll and resolve every exported C entry point.  Err with
/// kind=GLSLANG_LOAD_ABSENT when the library is missing; kind=GLSLANG_LOAD_ABI
/// when it loads but a symbol is missing (handle closed on failure).
/// Complexity: O(symbols).
pub fn glslang_load() -> Result[GlslangLibrary, GlslangLoadError] {
  let h = dl.dl_open(GLSLANG_SONAME);
  if !h.is_ok {
    return Err(GlslangLoadError{ kind: GLSLANG_LOAD_ABSENT; message: h.error });
  }
  let handle: Int = h.value;

  let a1 = dl.dl_sym(handle, "ShInitialize");
  if !a1.is_ok { var ig = dl.dl_close(handle); return Err(GlslangLoadError{ kind: GLSLANG_LOAD_ABI; message: "ShInitialize: " + a1.error }); }
  let a2 = dl.dl_sym(handle, "ShFinalize");
  if !a2.is_ok { var ig = dl.dl_close(handle); return Err(GlslangLoadError{ kind: GLSLANG_LOAD_ABI; message: "ShFinalize: " + a2.error }); }
  let a3 = dl.dl_sym(handle, "StageName");
  if !a3.is_ok { var ig = dl.dl_close(handle); return Err(GlslangLoadError{ kind: GLSLANG_LOAD_ABI; message: "StageName: " + a3.error }); }
  let a4 = dl.dl_sym(handle, "ShConstructCompiler");
  if !a4.is_ok { var ig = dl.dl_close(handle); return Err(GlslangLoadError{ kind: GLSLANG_LOAD_ABI; message: "ShConstructCompiler: " + a4.error }); }
  let a5 = dl.dl_sym(handle, "ShConstructLinker");
  if !a5.is_ok { var ig = dl.dl_close(handle); return Err(GlslangLoadError{ kind: GLSLANG_LOAD_ABI; message: "ShConstructLinker: " + a5.error }); }
  let a6 = dl.dl_sym(handle, "ShConstructUniformMap");
  if !a6.is_ok { var ig = dl.dl_close(handle); return Err(GlslangLoadError{ kind: GLSLANG_LOAD_ABI; message: "ShConstructUniformMap: " + a6.error }); }
  let a7 = dl.dl_sym(handle, "ShDestruct");
  if !a7.is_ok { var ig = dl.dl_close(handle); return Err(GlslangLoadError{ kind: GLSLANG_LOAD_ABI; message: "ShDestruct: " + a7.error }); }
  let a8 = dl.dl_sym(handle, "ShCompile");
  if !a8.is_ok { var ig = dl.dl_close(handle); return Err(GlslangLoadError{ kind: GLSLANG_LOAD_ABI; message: "ShCompile: " + a8.error }); }
  let a9 = dl.dl_sym(handle, "ShLinkExt");
  if !a9.is_ok { var ig = dl.dl_close(handle); return Err(GlslangLoadError{ kind: GLSLANG_LOAD_ABI; message: "ShLinkExt: " + a9.error }); }
  let a10 = dl.dl_sym(handle, "ShSetEncryptionMethod");
  if !a10.is_ok { var ig = dl.dl_close(handle); return Err(GlslangLoadError{ kind: GLSLANG_LOAD_ABI; message: "ShSetEncryptionMethod: " + a10.error }); }
  let a11 = dl.dl_sym(handle, "ShGetInfoLog");
  if !a11.is_ok { var ig = dl.dl_close(handle); return Err(GlslangLoadError{ kind: GLSLANG_LOAD_ABI; message: "ShGetInfoLog: " + a11.error }); }
  let a12 = dl.dl_sym(handle, "ShGetExecutable");
  if !a12.is_ok { var ig = dl.dl_close(handle); return Err(GlslangLoadError{ kind: GLSLANG_LOAD_ABI; message: "ShGetExecutable: " + a12.error }); }
  let a13 = dl.dl_sym(handle, "ShSetVirtualAttributeBindings");
  if !a13.is_ok { var ig = dl.dl_close(handle); return Err(GlslangLoadError{ kind: GLSLANG_LOAD_ABI; message: "ShSetVirtualAttributeBindings: " + a13.error }); }
  let a14 = dl.dl_sym(handle, "ShSetFixedAttributeBindings");
  if !a14.is_ok { var ig = dl.dl_close(handle); return Err(GlslangLoadError{ kind: GLSLANG_LOAD_ABI; message: "ShSetFixedAttributeBindings: " + a14.error }); }
  let a15 = dl.dl_sym(handle, "ShExcludeAttributes");
  if !a15.is_ok { var ig = dl.dl_close(handle); return Err(GlslangLoadError{ kind: GLSLANG_LOAD_ABI; message: "ShExcludeAttributes: " + a15.error }); }
  let a16 = dl.dl_sym(handle, "ShGetUniformLocation");
  if !a16.is_ok { var ig = dl.dl_close(handle); return Err(GlslangLoadError{ kind: GLSLANG_LOAD_ABI; message: "ShGetUniformLocation: " + a16.error }); }
  let a17 = dl.dl_sym(handle, "glslang_get_version");
  if !a17.is_ok { var ig = dl.dl_close(handle); return Err(GlslangLoadError{ kind: GLSLANG_LOAD_ABI; message: "glslang_get_version: " + a17.error }); }
  let a18 = dl.dl_sym(handle, "glslang_initialize_process");
  if !a18.is_ok { var ig = dl.dl_close(handle); return Err(GlslangLoadError{ kind: GLSLANG_LOAD_ABI; message: "glslang_initialize_process: " + a18.error }); }
  let a19 = dl.dl_sym(handle, "glslang_finalize_process");
  if !a19.is_ok { var ig = dl.dl_close(handle); return Err(GlslangLoadError{ kind: GLSLANG_LOAD_ABI; message: "glslang_finalize_process: " + a19.error }); }
  let a20 = dl.dl_sym(handle, "glslang_shader_create");
  if !a20.is_ok { var ig = dl.dl_close(handle); return Err(GlslangLoadError{ kind: GLSLANG_LOAD_ABI; message: "glslang_shader_create: " + a20.error }); }
  let a21 = dl.dl_sym(handle, "glslang_shader_delete");
  if !a21.is_ok { var ig = dl.dl_close(handle); return Err(GlslangLoadError{ kind: GLSLANG_LOAD_ABI; message: "glslang_shader_delete: " + a21.error }); }
  let a22 = dl.dl_sym(handle, "glslang_shader_set_preamble");
  if !a22.is_ok { var ig = dl.dl_close(handle); return Err(GlslangLoadError{ kind: GLSLANG_LOAD_ABI; message: "glslang_shader_set_preamble: " + a22.error }); }
  let a23 = dl.dl_sym(handle, "glslang_shader_set_entry_point");
  if !a23.is_ok { var ig = dl.dl_close(handle); return Err(GlslangLoadError{ kind: GLSLANG_LOAD_ABI; message: "glslang_shader_set_entry_point: " + a23.error }); }
  let a24 = dl.dl_sym(handle, "glslang_shader_set_invert_y");
  if !a24.is_ok { var ig = dl.dl_close(handle); return Err(GlslangLoadError{ kind: GLSLANG_LOAD_ABI; message: "glslang_shader_set_invert_y: " + a24.error }); }
  let a25 = dl.dl_sym(handle, "glslang_shader_shift_binding");
  if !a25.is_ok { var ig = dl.dl_close(handle); return Err(GlslangLoadError{ kind: GLSLANG_LOAD_ABI; message: "glslang_shader_shift_binding: " + a25.error }); }
  let a26 = dl.dl_sym(handle, "glslang_shader_shift_binding_for_set");
  if !a26.is_ok { var ig = dl.dl_close(handle); return Err(GlslangLoadError{ kind: GLSLANG_LOAD_ABI; message: "glslang_shader_shift_binding_for_set: " + a26.error }); }
  let a27 = dl.dl_sym(handle, "glslang_shader_set_options");
  if !a27.is_ok { var ig = dl.dl_close(handle); return Err(GlslangLoadError{ kind: GLSLANG_LOAD_ABI; message: "glslang_shader_set_options: " + a27.error }); }
  let a28 = dl.dl_sym(handle, "glslang_shader_set_glsl_version");
  if !a28.is_ok { var ig = dl.dl_close(handle); return Err(GlslangLoadError{ kind: GLSLANG_LOAD_ABI; message: "glslang_shader_set_glsl_version: " + a28.error }); }
  let a29 = dl.dl_sym(handle, "glslang_shader_set_default_uniform_block_set_and_binding");
  if !a29.is_ok { var ig = dl.dl_close(handle); return Err(GlslangLoadError{ kind: GLSLANG_LOAD_ABI; message: "glslang_shader_set_default_uniform_block_set_and_binding: " + a29.error }); }
  let a30 = dl.dl_sym(handle, "glslang_shader_set_default_uniform_block_name");
  if !a30.is_ok { var ig = dl.dl_close(handle); return Err(GlslangLoadError{ kind: GLSLANG_LOAD_ABI; message: "glslang_shader_set_default_uniform_block_name: " + a30.error }); }
  let a31 = dl.dl_sym(handle, "glslang_shader_set_resource_set_binding");
  if !a31.is_ok { var ig = dl.dl_close(handle); return Err(GlslangLoadError{ kind: GLSLANG_LOAD_ABI; message: "glslang_shader_set_resource_set_binding: " + a31.error }); }
  let a32 = dl.dl_sym(handle, "glslang_shader_preprocess");
  if !a32.is_ok { var ig = dl.dl_close(handle); return Err(GlslangLoadError{ kind: GLSLANG_LOAD_ABI; message: "glslang_shader_preprocess: " + a32.error }); }
  let a33 = dl.dl_sym(handle, "glslang_shader_parse");
  if !a33.is_ok { var ig = dl.dl_close(handle); return Err(GlslangLoadError{ kind: GLSLANG_LOAD_ABI; message: "glslang_shader_parse: " + a33.error }); }
  let a34 = dl.dl_sym(handle, "glslang_shader_get_preprocessed_code");
  if !a34.is_ok { var ig = dl.dl_close(handle); return Err(GlslangLoadError{ kind: GLSLANG_LOAD_ABI; message: "glslang_shader_get_preprocessed_code: " + a34.error }); }
  let a35 = dl.dl_sym(handle, "glslang_shader_set_preprocessed_code");
  if !a35.is_ok { var ig = dl.dl_close(handle); return Err(GlslangLoadError{ kind: GLSLANG_LOAD_ABI; message: "glslang_shader_set_preprocessed_code: " + a35.error }); }
  let a36 = dl.dl_sym(handle, "glslang_shader_get_info_log");
  if !a36.is_ok { var ig = dl.dl_close(handle); return Err(GlslangLoadError{ kind: GLSLANG_LOAD_ABI; message: "glslang_shader_get_info_log: " + a36.error }); }
  let a37 = dl.dl_sym(handle, "glslang_shader_get_info_debug_log");
  if !a37.is_ok { var ig = dl.dl_close(handle); return Err(GlslangLoadError{ kind: GLSLANG_LOAD_ABI; message: "glslang_shader_get_info_debug_log: " + a37.error }); }
  let a38 = dl.dl_sym(handle, "glslang_program_create");
  if !a38.is_ok { var ig = dl.dl_close(handle); return Err(GlslangLoadError{ kind: GLSLANG_LOAD_ABI; message: "glslang_program_create: " + a38.error }); }
  let a39 = dl.dl_sym(handle, "glslang_program_delete");
  if !a39.is_ok { var ig = dl.dl_close(handle); return Err(GlslangLoadError{ kind: GLSLANG_LOAD_ABI; message: "glslang_program_delete: " + a39.error }); }
  let a40 = dl.dl_sym(handle, "glslang_program_add_shader");
  if !a40.is_ok { var ig = dl.dl_close(handle); return Err(GlslangLoadError{ kind: GLSLANG_LOAD_ABI; message: "glslang_program_add_shader: " + a40.error }); }
  let a41 = dl.dl_sym(handle, "glslang_program_link");
  if !a41.is_ok { var ig = dl.dl_close(handle); return Err(GlslangLoadError{ kind: GLSLANG_LOAD_ABI; message: "glslang_program_link: " + a41.error }); }
  let a42 = dl.dl_sym(handle, "glslang_program_add_source_text");
  if !a42.is_ok { var ig = dl.dl_close(handle); return Err(GlslangLoadError{ kind: GLSLANG_LOAD_ABI; message: "glslang_program_add_source_text: " + a42.error }); }
  let a43 = dl.dl_sym(handle, "glslang_program_set_source_file");
  if !a43.is_ok { var ig = dl.dl_close(handle); return Err(GlslangLoadError{ kind: GLSLANG_LOAD_ABI; message: "glslang_program_set_source_file: " + a43.error }); }
  let a44 = dl.dl_sym(handle, "glslang_program_map_io");
  if !a44.is_ok { var ig = dl.dl_close(handle); return Err(GlslangLoadError{ kind: GLSLANG_LOAD_ABI; message: "glslang_program_map_io: " + a44.error }); }
  let a45 = dl.dl_sym(handle, "glslang_program_map_io_with_resolver_and_mapper");
  if !a45.is_ok { var ig = dl.dl_close(handle); return Err(GlslangLoadError{ kind: GLSLANG_LOAD_ABI; message: "glslang_program_map_io_with_resolver_and_mapper: " + a45.error }); }
  let a46 = dl.dl_sym(handle, "glslang_program_SPIRV_generate");
  if !a46.is_ok { var ig = dl.dl_close(handle); return Err(GlslangLoadError{ kind: GLSLANG_LOAD_ABI; message: "glslang_program_SPIRV_generate: " + a46.error }); }
  let a47 = dl.dl_sym(handle, "glslang_program_SPIRV_generate_with_options");
  if !a47.is_ok { var ig = dl.dl_close(handle); return Err(GlslangLoadError{ kind: GLSLANG_LOAD_ABI; message: "glslang_program_SPIRV_generate_with_options: " + a47.error }); }
  let a48 = dl.dl_sym(handle, "glslang_program_SPIRV_get_size");
  if !a48.is_ok { var ig = dl.dl_close(handle); return Err(GlslangLoadError{ kind: GLSLANG_LOAD_ABI; message: "glslang_program_SPIRV_get_size: " + a48.error }); }
  let a49 = dl.dl_sym(handle, "glslang_program_SPIRV_get");
  if !a49.is_ok { var ig = dl.dl_close(handle); return Err(GlslangLoadError{ kind: GLSLANG_LOAD_ABI; message: "glslang_program_SPIRV_get: " + a49.error }); }
  let a50 = dl.dl_sym(handle, "glslang_program_SPIRV_get_ptr");
  if !a50.is_ok { var ig = dl.dl_close(handle); return Err(GlslangLoadError{ kind: GLSLANG_LOAD_ABI; message: "glslang_program_SPIRV_get_ptr: " + a50.error }); }
  let a51 = dl.dl_sym(handle, "glslang_program_SPIRV_get_messages");
  if !a51.is_ok { var ig = dl.dl_close(handle); return Err(GlslangLoadError{ kind: GLSLANG_LOAD_ABI; message: "glslang_program_SPIRV_get_messages: " + a51.error }); }
  let a52 = dl.dl_sym(handle, "glslang_program_get_info_log");
  if !a52.is_ok { var ig = dl.dl_close(handle); return Err(GlslangLoadError{ kind: GLSLANG_LOAD_ABI; message: "glslang_program_get_info_log: " + a52.error }); }
  let a53 = dl.dl_sym(handle, "glslang_program_get_info_debug_log");
  if !a53.is_ok { var ig = dl.dl_close(handle); return Err(GlslangLoadError{ kind: GLSLANG_LOAD_ABI; message: "glslang_program_get_info_debug_log: " + a53.error }); }
  let a54 = dl.dl_sym(handle, "glslang_glsl_mapper_create");
  if !a54.is_ok { var ig = dl.dl_close(handle); return Err(GlslangLoadError{ kind: GLSLANG_LOAD_ABI; message: "glslang_glsl_mapper_create: " + a54.error }); }
  let a55 = dl.dl_sym(handle, "glslang_glsl_mapper_delete");
  if !a55.is_ok { var ig = dl.dl_close(handle); return Err(GlslangLoadError{ kind: GLSLANG_LOAD_ABI; message: "glslang_glsl_mapper_delete: " + a55.error }); }
  let a56 = dl.dl_sym(handle, "glslang_glsl_resolver_create");
  if !a56.is_ok { var ig = dl.dl_close(handle); return Err(GlslangLoadError{ kind: GLSLANG_LOAD_ABI; message: "glslang_glsl_resolver_create: " + a56.error }); }
  let a57 = dl.dl_sym(handle, "glslang_glsl_resolver_delete");
  if !a57.is_ok { var ig = dl.dl_close(handle); return Err(GlslangLoadError{ kind: GLSLANG_LOAD_ABI; message: "glslang_glsl_resolver_delete: " + a57.error }); }

  return Ok(GlslangLibrary{
    handle: handle,
    p_sh_initialize: a1.value,
    p_sh_finalize: a2.value,
    p_stage_name: a3.value,
    p_sh_construct_compiler: a4.value,
    p_sh_construct_linker: a5.value,
    p_sh_construct_uniform_map: a6.value,
    p_sh_destruct: a7.value,
    p_sh_compile: a8.value,
    p_sh_link_ext: a9.value,
    p_sh_set_encryption_method: a10.value,
    p_sh_get_info_log: a11.value,
    p_sh_get_executable: a12.value,
    p_sh_set_virtual_attribute_bindings: a13.value,
    p_sh_set_fixed_attribute_bindings: a14.value,
    p_sh_exclude_attributes: a15.value,
    p_sh_get_uniform_location: a16.value,
    p_get_version: a17.value,
    p_initialize_process: a18.value,
    p_finalize_process: a19.value,
    p_shader_create: a20.value,
    p_shader_delete: a21.value,
    p_shader_set_preamble: a22.value,
    p_shader_set_entry_point: a23.value,
    p_shader_set_invert_y: a24.value,
    p_shader_shift_binding: a25.value,
    p_shader_shift_binding_for_set: a26.value,
    p_shader_set_options: a27.value,
    p_shader_set_glsl_version: a28.value,
    p_shader_set_default_uniform_block_set_and_binding: a29.value,
    p_shader_set_default_uniform_block_name: a30.value,
    p_shader_set_resource_set_binding: a31.value,
    p_shader_preprocess: a32.value,
    p_shader_parse: a33.value,
    p_shader_get_preprocessed_code: a34.value,
    p_shader_set_preprocessed_code: a35.value,
    p_shader_get_info_log: a36.value,
    p_shader_get_info_debug_log: a37.value,
    p_program_create: a38.value,
    p_program_delete: a39.value,
    p_program_add_shader: a40.value,
    p_program_link: a41.value,
    p_program_add_source_text: a42.value,
    p_program_set_source_file: a43.value,
    p_program_map_io: a44.value,
    p_program_map_io_with_resolver_and_mapper: a45.value,
    p_program_spirv_generate: a46.value,
    p_program_spirv_generate_with_options: a47.value,
    p_program_spirv_get_size: a48.value,
    p_program_spirv_get: a49.value,
    p_program_spirv_get_ptr: a50.value,
    p_program_spirv_get_messages: a51.value,
    p_program_get_info_log: a52.value,
    p_program_get_info_debug_log: a53.value,
    p_glsl_mapper_create: a54.value,
    p_glsl_mapper_delete: a55.value,
    p_glsl_resolver_create: a56.value,
    p_glsl_resolver_delete: a57.value,
  });
}

/// Release a loaded glslang.dll handle.
/// Complexity: O(1).
pub fn glslang_close(lib: &GlslangLibrary) -> Result[Unit, Str]
  requires: lib.handle != 0
{
  return dl.dl_close(lib.handle);
}

/// Load glslang-default-resource-limits.dll (the C resource-limits helpers:
/// glslang_resource / glslang_default_resource / glslang_default_resource_string
/// / glslang_decode_resource_limits).  Same SKIP/ABI classification as
/// `glslang_load`.
/// Complexity: O(symbols).
pub fn glslang_load_resource_limits() -> Result[GlslangResourceLimitsLibrary, GlslangLoadError] {
  let h = dl.dl_open(GLSLANG_RESOURCE_LIMITS_SONAME);
  if !h.is_ok {
    return Err(GlslangLoadError{ kind: GLSLANG_LOAD_ABSENT; message: h.error });
  }
  let lim_handle: Int = h.value;

  let b1 = dl.dl_sym(lim_handle, "glslang_resource");
  if !b1.is_ok { var ig = dl.dl_close(lim_handle); return Err(GlslangLoadError{ kind: GLSLANG_LOAD_ABI; message: "glslang_resource: " + b1.error }); }
  let b2 = dl.dl_sym(lim_handle, "glslang_default_resource");
  if !b2.is_ok { var ig = dl.dl_close(lim_handle); return Err(GlslangLoadError{ kind: GLSLANG_LOAD_ABI; message: "glslang_default_resource: " + b2.error }); }
  let b3 = dl.dl_sym(lim_handle, "glslang_default_resource_string");
  if !b3.is_ok { var ig = dl.dl_close(lim_handle); return Err(GlslangLoadError{ kind: GLSLANG_LOAD_ABI; message: "glslang_default_resource_string: " + b3.error }); }
  let b4 = dl.dl_sym(lim_handle, "glslang_decode_resource_limits");
  if !b4.is_ok { var ig = dl.dl_close(lim_handle); return Err(GlslangLoadError{ kind: GLSLANG_LOAD_ABI; message: "glslang_decode_resource_limits: " + b4.error }); }

  return Ok(GlslangResourceLimitsLibrary{
    handle: lim_handle,
    p_resource: b1.value,
    p_default_resource: b2.value,
    p_default_resource_string: b3.value,
    p_decode_resource_limits: b4.value,
  });
}

/// Release a loaded glslang-default-resource-limits.dll handle.
/// Complexity: O(1).
pub fn glslang_resource_limits_close(lim: &GlslangResourceLimitsLibrary) -> Result[Unit, Str]
  requires: lim.handle != 0
{
  return dl.dl_close(lim.handle);
}

// =========================================================================
// C interface wrappers: version + process lifetime
// =========================================================================

/// glslang_get_version(version*): version struct written into an owned slot.
/// Complexity: O(1).
pub fn glslang_get_version(lib: &GlslangLibrary) -> GlslangVersion
  requires: lib.handle != 0
{
  unsafe {
    var slot = glslang_slot(GLSLANG_VERSION_SIZE);
    let f = lib.p_get_version as fn(*UInt8);
    f(slot.as_mut_ptr());
    return GlslangVersion{
      major: glslang_read_u32(&slot, 0),
      minor: glslang_read_u32(&slot, 4),
      patch: glslang_read_u32(&slot, 8),
    };
  }
}

/// glslang_initialize_process() -> bool.  Call once per process before any
/// other compiler operation.
/// Complexity: O(1).
pub fn glslang_initialize_process(lib: &GlslangLibrary) -> Bool
  requires: lib.handle != 0
{
  unsafe {
    let f = lib.p_initialize_process as fn() -> Int32;
    return (f() as Int) != 0;
  }
}

/// glslang_finalize_process(): tear down process state (after all shaders
/// and programs are deleted).
/// Complexity: O(1).
pub fn glslang_finalize_process(lib: &GlslangLibrary)
  requires: lib.handle != 0
{
  unsafe {
    let f = lib.p_finalize_process as fn();
    f();
  }
}

// =========================================================================
// C interface wrappers: shader
// =========================================================================

/// glslang_shader_create(input*) -> shader handle (0 on failure).  The input
/// slot must stay alive (and unchanged) until `glslang_shader_parse`, and
/// the Str whose pointer is stored at offset 24 must outlive both calls.
/// Complexity: O(1).
pub fn glslang_shader_create(lib: &GlslangLibrary, input: &mut Vec[UInt8]) -> Int
  requires: lib.handle != 0
  requires: input.len() >= GLSLANG_INPUT_SIZE
{
  unsafe {
    let f = lib.p_shader_create as fn(*UInt8) -> Int;
    return f(input.as_mut_ptr());
  }
}

/// glslang_shader_delete(shader) (NULL-safe).
/// Complexity: O(1).
pub fn glslang_shader_delete(lib: &GlslangLibrary, shader: Int)
  requires: lib.handle != 0
{
  if shader == 0 { return; }
  unsafe {
    let f = lib.p_shader_delete as fn(Int);
    f(shader);
  }
}

/// glslang_shader_set_preamble(shader, s).
/// Complexity: O(len).
pub fn glslang_shader_set_preamble(lib: &GlslangLibrary, shader: Int, s: Str)
  requires: lib.handle != 0
  requires: shader != 0
  requires: s.len() > 0
{
  unsafe {
    let f = lib.p_shader_set_preamble as fn(Int, *UInt8);
    f(shader, s.c_str());
  }
}

/// glslang_shader_set_entry_point(shader, s).
/// Complexity: O(len).
pub fn glslang_shader_set_entry_point(lib: &GlslangLibrary, shader: Int, s: Str)
  requires: lib.handle != 0
  requires: shader != 0
  requires: s.len() > 0
{
  unsafe {
    let f = lib.p_shader_set_entry_point as fn(Int, *UInt8);
    f(shader, s.c_str());
  }
}

/// glslang_shader_set_invert_y(shader, y).
/// Complexity: O(1).
pub fn glslang_shader_set_invert_y(lib: &GlslangLibrary, shader: Int, y: Bool)
  requires: lib.handle != 0
  requires: shader != 0
{
  unsafe {
    let f = lib.p_shader_set_invert_y as fn(Int, UInt8);
    let v: UInt8 = if y { 1 as UInt8 } else { 0 as UInt8 };
    f(shader, v);
  }
}

/// glslang_shader_shift_binding(shader, res, base) -- res is a
/// GLSLANG_RESOURCE_TYPE_* value.
/// Complexity: O(1).
pub fn glslang_shader_shift_binding(lib: &GlslangLibrary, shader: Int, res: Int, base: Int)
  requires: lib.handle != 0
  requires: shader != 0
  requires: res >= 0
  requires: base >= 0
{
  unsafe {
    let f = lib.p_shader_shift_binding as fn(Int, Int, Int);
    f(shader, res, base);
  }
}

/// glslang_shader_shift_binding_for_set(shader, res, base, set).
/// Complexity: O(1).
pub fn glslang_shader_shift_binding_for_set(lib: &GlslangLibrary, shader: Int, res: Int, base: Int, set: Int)
  requires: lib.handle != 0
  requires: shader != 0
  requires: res >= 0
  requires: base >= 0
  requires: set >= 0
{
  unsafe {
    let f = lib.p_shader_shift_binding_for_set as fn(Int, Int, Int, Int);
    f(shader, res, base, set);
  }
}

/// glslang_shader_set_options(shader, options) -- options is a bitmask of
/// GLSLANG_SHADER_* values.
/// Complexity: O(1).
pub fn glslang_shader_set_options(lib: &GlslangLibrary, shader: Int, options: Int)
  requires: lib.handle != 0
  requires: shader != 0
  requires: options >= 0
{
  unsafe {
    let f = lib.p_shader_set_options as fn(Int, Int);
    f(shader, options);
  }
}

/// glslang_shader_set_glsl_version(shader, version) -- overrides #version.
/// Complexity: O(1).
pub fn glslang_shader_set_glsl_version(lib: &GlslangLibrary, shader: Int, version: Int)
  requires: lib.handle != 0
  requires: shader != 0
  requires: version > 0
{
  unsafe {
    let f = lib.p_shader_set_glsl_version as fn(Int, Int);
    f(shader, version);
  }
}

/// glslang_shader_set_default_uniform_block_set_and_binding(shader, set, binding).
/// Complexity: O(1).
pub fn glslang_shader_set_default_uniform_block_set_and_binding(lib: &GlslangLibrary, shader: Int, set: Int, binding: Int)
  requires: lib.handle != 0
  requires: shader != 0
  requires: set >= 0
  requires: binding >= 0
{
  unsafe {
    let f = lib.p_shader_set_default_uniform_block_set_and_binding as fn(Int, Int, Int);
    f(shader, set, binding);
  }
}

/// glslang_shader_set_default_uniform_block_name(shader, name).
/// Complexity: O(len).
pub fn glslang_shader_set_default_uniform_block_name(lib: &GlslangLibrary, shader: Int, name: Str)
  requires: lib.handle != 0
  requires: shader != 0
  requires: name.len() > 0
{
  unsafe {
    let f = lib.p_shader_set_default_uniform_block_name as fn(Int, *UInt8);
    f(shader, name.c_str());
  }
}

/// glslang_shader_set_resource_set_binding(shader, bindings, num_bindings):
/// `bindings` is an owned slot holding `num_bindings` char* entries (8 bytes
/// each, written with byte-indexed u64 stores); the Str pointers stored in
/// it must outlive the parse.
/// Complexity: O(num_bindings).
pub fn glslang_shader_set_resource_set_binding(lib: &GlslangLibrary, shader: Int, bindings: &Vec[UInt8], num_bindings: Int)
  requires: lib.handle != 0
  requires: shader != 0
  requires: num_bindings > 0
  requires: bindings.len() >= num_bindings * 8
{
  unsafe {
    let f = lib.p_shader_set_resource_set_binding as fn(Int, *UInt8, Int);
    f(shader, bindings.as_mut_ptr(), num_bindings);
  }
}

/// glslang_shader_get_preprocessed_code(shader) -> copied string ("" when
/// empty).  Valid after glslang_shader_preprocess.
/// Complexity: O(len).
pub fn glslang_shader_get_preprocessed_code(lib: &GlslangLibrary, shader: Int) -> Str
  requires: lib.handle != 0
  requires: shader != 0
{
  unsafe {
    let f = lib.p_shader_get_preprocessed_code as fn(Int) -> *UInt8;
    return glslang_cstr(f(shader) as Int);
  }
}

/// glslang_shader_set_preprocessed_code(shader, code): seed the shader's
/// preprocessed string (used by the preprocess -> parse flow).
/// Complexity: O(len).
pub fn glslang_shader_set_preprocessed_code(lib: &GlslangLibrary, shader: Int, code: Str)
  requires: lib.handle != 0
  requires: shader != 0
  requires: code.len() > 0
{
  unsafe {
    let f = lib.p_shader_set_preprocessed_code as fn(Int, *UInt8);
    f(shader, code.c_str());
  }
}

/// glslang_shader_preprocess(shader, input*) -> bool.  Runs the preprocessor
/// and stores the result in the shader (required before parse on this
/// interface); input.resource must be a valid glslang_resource_t pointer.
/// Complexity: O(source).
pub fn glslang_shader_preprocess(lib: &GlslangLibrary, shader: Int, input: &mut Vec[UInt8]) -> Bool
  requires: lib.handle != 0
  requires: shader != 0
  requires: input.len() >= GLSLANG_INPUT_SIZE
{
  unsafe {
    let f = lib.p_shader_preprocess as fn(Int, *UInt8) -> Int32;
    return (f(shader, input.as_mut_ptr()) as Int) != 0;
  }
}

/// glslang_shader_parse(shader, input*) -> bool.  Parses the preprocessed
/// string (call glslang_shader_preprocess first); input.resource must be
/// valid.
/// Complexity: O(source).
pub fn glslang_shader_parse(lib: &GlslangLibrary, shader: Int, input: &mut Vec[UInt8]) -> Bool
  requires: lib.handle != 0
  requires: shader != 0
  requires: input.len() >= GLSLANG_INPUT_SIZE
{
  unsafe {
    let f = lib.p_shader_parse as fn(Int, *UInt8) -> Int32;
    return (f(shader, input.as_mut_ptr()) as Int) != 0;
  }
}

/// glslang_shader_get_info_log(shader) -> copied info-log string.
/// Complexity: O(len).
pub fn glslang_shader_get_info_log(lib: &GlslangLibrary, shader: Int) -> Str
  requires: lib.handle != 0
  requires: shader != 0
{
  unsafe {
    let f = lib.p_shader_get_info_log as fn(Int) -> *UInt8;
    return glslang_cstr(f(shader) as Int);
  }
}

/// glslang_shader_get_info_debug_log(shader) -> copied debug-log string.
/// Complexity: O(len).
pub fn glslang_shader_get_info_debug_log(lib: &GlslangLibrary, shader: Int) -> Str
  requires: lib.handle != 0
  requires: shader != 0
{
  unsafe {
    let f = lib.p_shader_get_info_debug_log as fn(Int) -> *UInt8;
    return glslang_cstr(f(shader) as Int);
  }
}

// =========================================================================
// C interface wrappers: program + SPIR-V
// =========================================================================

/// glslang_program_create() -> program handle (0 on failure).
/// Complexity: O(1).
pub fn glslang_program_create(lib: &GlslangLibrary) -> Int
  requires: lib.handle != 0
{
  unsafe {
    let f = lib.p_program_create as fn() -> Int;
    return f();
  }
}

/// glslang_program_delete(program) (NULL-safe; delete programs BEFORE the
/// shaders linked into them).
/// Complexity: O(1).
pub fn glslang_program_delete(lib: &GlslangLibrary, program: Int)
  requires: lib.handle != 0
{
  if program == 0 { return; }
  unsafe {
    let f = lib.p_program_delete as fn(Int);
    f(program);
  }
}

/// glslang_program_add_shader(program, shader).
/// Complexity: O(1).
pub fn glslang_program_add_shader(lib: &GlslangLibrary, program: Int, shader: Int)
  requires: lib.handle != 0
  requires: program != 0
  requires: shader != 0
{
  unsafe {
    let f = lib.p_program_add_shader as fn(Int, Int);
    f(program, shader);
  }
}

/// glslang_program_link(program, messages) -> bool.  messages is the raw
/// EShMessages bitmask (GLSLANG_MSG_* values).
/// Complexity: O(program).
pub fn glslang_program_link(lib: &GlslangLibrary, program: Int, messages: Int) -> Bool
  requires: lib.handle != 0
  requires: program != 0
  requires: messages >= 0
{
  unsafe {
    let f = lib.p_program_link as fn(Int, Int) -> Int32;
    return (f(program, messages) as Int) != 0;
  }
}

/// glslang_program_add_source_text(program, stage, text, len): attach source
/// text for diagnostics (copied by glslang).
/// Complexity: O(len).
pub fn glslang_program_add_source_text(lib: &GlslangLibrary, program: Int, stage: Int, text: Str)
  requires: lib.handle != 0
  requires: program != 0
  requires: text.len() > 0
{
  unsafe {
    let f = lib.p_program_add_source_text as fn(Int, Int, *UInt8, Int);
    f(program, stage, text.c_str(), text.len());
  }
}

/// glslang_program_set_source_file(program, stage, file).
/// Complexity: O(len).
pub fn glslang_program_set_source_file(lib: &GlslangLibrary, program: Int, stage: Int, file: Str)
  requires: lib.handle != 0
  requires: program != 0
  requires: file.len() > 0
{
  unsafe {
    let f = lib.p_program_set_source_file as fn(Int, Int, *UInt8);
    f(program, stage, file.c_str());
  }
}

/// glslang_program_map_io(program) -> bool.
/// Complexity: O(program).
pub fn glslang_program_map_io(lib: &GlslangLibrary, program: Int) -> Bool
  requires: lib.handle != 0
  requires: program != 0
{
  unsafe {
    let f = lib.p_program_map_io as fn(Int) -> Int32;
    return (f(program) as Int) != 0;
  }
}

/// glslang_program_map_io_with_resolver_and_mapper(program, resolver, mapper)
/// -> bool.  resolver/mapper are handles from glslang_glsl_resolver_create /
/// glslang_glsl_mapper_create.
/// Complexity: O(program).
pub fn glslang_program_map_io_with_resolver_and_mapper(lib: &GlslangLibrary, program: Int, resolver: Int, mapper: Int) -> Bool
  requires: lib.handle != 0
  requires: program != 0
  requires: resolver != 0
  requires: mapper != 0
{
  unsafe {
    let f = lib.p_program_map_io_with_resolver_and_mapper as fn(Int, Int, Int) -> Int32;
    return (f(program, resolver, mapper) as Int) != 0;
  }
}

/// glslang_program_SPIRV_generate(program, stage): generate SPIR-V for the
/// linked program's `stage` intermediate (default options: optimizer off,
/// validation on).
/// Complexity: O(program).
pub fn glslang_program_spirv_generate(lib: &GlslangLibrary, program: Int, stage: Int)
  requires: lib.handle != 0
  requires: program != 0
{
  unsafe {
    let f = lib.p_program_spirv_generate as fn(Int, Int);
    f(program, stage);
  }
}

/// glslang_program_SPIRV_generate_with_options(program, stage, options*):
/// options is an owned GLSLANG_SPV_OPTIONS_SIZE-byte slot (10 C bools).
/// Complexity: O(program).
pub fn glslang_program_spirv_generate_with_options(lib: &GlslangLibrary, program: Int, stage: Int, options: &mut Vec[UInt8])
  requires: lib.handle != 0
  requires: program != 0
  requires: options.len() >= GLSLANG_SPV_OPTIONS_SIZE
{
  unsafe {
    let f = lib.p_program_spirv_generate_with_options as fn(Int, Int, *UInt8);
    f(program, stage, options.as_mut_ptr());
  }
}

/// glslang_program_SPIRV_get_size(program) -> word count (0 when no SPIR-V
/// was generated).
/// Complexity: O(1).
pub fn glslang_program_spirv_get_size(lib: &GlslangLibrary, program: Int) -> Int
  requires: lib.handle != 0
  requires: program != 0
{
  unsafe {
    let f = lib.p_program_spirv_get_size as fn(Int) -> Int;
    return f(program);
  }
}

/// glslang_program_SPIRV_get(program, out): C memcpys the SPIR-V words into
/// the owned buffer (size it with `glslang_program_spirv_get_size` first;
/// the wrapper requires at least one word).
/// Complexity: O(size).
pub fn glslang_program_spirv_get(lib: &GlslangLibrary, program: Int, out: &mut Vec[UInt8])
  requires: lib.handle != 0
  requires: program != 0
  requires: out.len() >= 4
{
  unsafe {
    let f = lib.p_program_spirv_get as fn(Int, *UInt8);
    f(program, out.as_mut_ptr());
  }
}

/// glslang_program_SPIRV_get_ptr(program) -> raw pointer to glslang's
/// internal word buffer (do NOT size or read it through XIOM pointer math;
/// prefer `glslang_program_spirv_words`).  Non-zero when SPIR-V exists.
/// Complexity: O(1).
pub fn glslang_program_spirv_get_ptr(lib: &GlslangLibrary, program: Int) -> Int
  requires: lib.handle != 0
  requires: program != 0
{
  unsafe {
    let f = lib.p_program_spirv_get_ptr as fn(Int) -> Int;
    return f(program);
  }
}

/// glslang_program_SPIRV_get_messages(program) -> copied generator messages
/// ("" when none).
/// Complexity: O(len).
pub fn glslang_program_spirv_get_messages(lib: &GlslangLibrary, program: Int) -> Str
  requires: lib.handle != 0
  requires: program != 0
{
  unsafe {
    let f = lib.p_program_spirv_get_messages as fn(Int) -> *UInt8;
    return glslang_cstr(f(program) as Int);
  }
}

/// glslang_program_get_info_log(program) -> copied info-log string.
/// Complexity: O(len).
pub fn glslang_program_get_info_log(lib: &GlslangLibrary, program: Int) -> Str
  requires: lib.handle != 0
  requires: program != 0
{
  unsafe {
    let f = lib.p_program_get_info_log as fn(Int) -> *UInt8;
    return glslang_cstr(f(program) as Int);
  }
}

/// glslang_program_get_info_debug_log(program) -> copied debug-log string.
/// Complexity: O(len).
pub fn glslang_program_get_info_debug_log(lib: &GlslangLibrary, program: Int) -> Str
  requires: lib.handle != 0
  requires: program != 0
{
  unsafe {
    let f = lib.p_program_get_info_debug_log as fn(Int) -> *UInt8;
    return glslang_cstr(f(program) as Int);
  }
}

/// glslang_glsl_mapper_create() -> mapper handle (0 on failure).
/// Complexity: O(1).
pub fn glslang_glsl_mapper_create(lib: &GlslangLibrary) -> Int
  requires: lib.handle != 0
{
  unsafe {
    let f = lib.p_glsl_mapper_create as fn() -> Int;
    return f();
  }
}

/// glslang_glsl_mapper_delete(mapper) (NULL-safe).
/// Complexity: O(1).
pub fn glslang_glsl_mapper_delete(lib: &GlslangLibrary, mapper: Int)
  requires: lib.handle != 0
{
  if mapper == 0 { return; }
  unsafe {
    let f = lib.p_glsl_mapper_delete as fn(Int);
    f(mapper);
  }
}

/// glslang_glsl_resolver_create(program, stage) -> resolver handle
/// (0 on failure).
/// Complexity: O(1).
pub fn glslang_glsl_resolver_create(lib: &GlslangLibrary, program: Int, stage: Int) -> Int
  requires: lib.handle != 0
  requires: program != 0
{
  unsafe {
    let f = lib.p_glsl_resolver_create as fn(Int, Int) -> Int;
    return f(program, stage);
  }
}

/// glslang_glsl_resolver_delete(resolver) (NULL-safe).
/// Complexity: O(1).
pub fn glslang_glsl_resolver_delete(lib: &GlslangLibrary, resolver: Int)
  requires: lib.handle != 0
{
  if resolver == 0 { return; }
  unsafe {
    let f = lib.p_glsl_resolver_delete as fn(Int);
    f(resolver);
  }
}

// =========================================================================
// Legacy extern "C" Sh* surface (ShaderLang.h)
// =========================================================================

/// ShInitialize() -> bool (legacy process init; separate from
/// glslang_initialize_process).
/// Complexity: O(1).
pub fn glslang_sh_initialize(lib: &GlslangLibrary) -> Bool
  requires: lib.handle != 0
{
  unsafe {
    let f = lib.p_sh_initialize as fn() -> Int32;
    return (f() as Int) != 0;
  }
}

/// ShFinalize() -> bool.
/// Complexity: O(1).
pub fn glslang_sh_finalize(lib: &GlslangLibrary) -> Bool
  requires: lib.handle != 0
{
  unsafe {
    let f = lib.p_sh_finalize as fn() -> Int32;
    return (f() as Int) != 0;
  }
}

/// StageName(stage) -> copied lowercase stage name ("vertex", ...).
/// Complexity: O(len).
pub fn glslang_stage_name(lib: &GlslangLibrary, stage: Int) -> Str
  requires: lib.handle != 0
  requires: stage >= 0
{
  unsafe {
    let f = lib.p_stage_name as fn(Int) -> *UInt8;
    return glslang_cstr(f(stage) as Int);
  }
}

/// ShConstructCompiler(language, debugOptions) -> compiler handle (0 on
/// failure).  language is an EShLang* value.
/// Complexity: O(1).
pub fn glslang_sh_construct_compiler(lib: &GlslangLibrary, language: Int, debug_options: Int) -> Int
  requires: lib.handle != 0
  requires: language >= 0
{
  unsafe {
    let f = lib.p_sh_construct_compiler as fn(Int, Int) -> Int;
    return f(language, debug_options);
  }
}

/// ShConstructLinker(executable, debugOptions) -> linker handle (0 on
/// failure).  executable is GLSLANG_EX_VERTEX_FRAGMENT / GLSLANG_EX_FRAGMENT.
/// Complexity: O(1).
pub fn glslang_sh_construct_linker(lib: &GlslangLibrary, executable: Int, debug_options: Int) -> Int
  requires: lib.handle != 0
  requires: executable >= 0
{
  unsafe {
    let f = lib.p_sh_construct_linker as fn(Int, Int) -> Int;
    return f(executable, debug_options);
  }
}

/// ShConstructUniformMap() -> uniform-map handle (0 on failure).
/// Complexity: O(1).
pub fn glslang_sh_construct_uniform_map(lib: &GlslangLibrary) -> Int
  requires: lib.handle != 0
{
  unsafe {
    let f = lib.p_sh_construct_uniform_map as fn() -> Int;
    return f();
  }
}

/// ShDestruct(handle) (any Sh* handle; NULL-safe at the caller).
/// Complexity: O(1).
pub fn glslang_sh_destruct(lib: &GlslangLibrary, handle: Int)
  requires: lib.handle != 0
{
  if handle == 0 { return; }
  unsafe {
    let f = lib.p_sh_destruct as fn(Int);
    f(handle);
  }
}

/// ShCompile(handle, strings, numStrings, lengths, optLevel, resources,
/// debugOptions, defaultVersion, forwardCompatible, messages, fileName) ->
/// bool.  `strings` is an owned slot holding `num_strings` char* entries
/// (the Str pointers must outlive the call); pass lengths_ptr=0 for
/// NUL-terminated sources.
/// Complexity: O(source).
pub fn glslang_sh_compile(lib: &GlslangLibrary, handle: Int, strings: &Vec[UInt8], num_strings: Int,
    lengths_ptr: Int, opt_level: Int, resources_ptr: Int, debug_options: Int,
    default_version: Int, forward_compatible: Bool, messages: Int, file_name: Str) -> Bool
  requires: lib.handle != 0
  requires: handle != 0
  requires: num_strings > 0
  requires: strings.len() >= num_strings * 8
  requires: resources_ptr != 0
  requires: default_version > 0
{
  unsafe {
    let f = lib.p_sh_compile as fn(Int, *UInt8, Int, Int, Int, Int, Int, Int, UInt8, Int, *UInt8) -> Int32;
    let fc: UInt8 = if forward_compatible { 1 as UInt8 } else { 0 as UInt8 };
    let rc = f(handle, strings.as_mut_ptr(), num_strings, lengths_ptr, opt_level,
      resources_ptr, debug_options, default_version, fc, messages, file_name.c_str());
    return (rc as Int) != 0;
  }
}

/// ShLinkExt(linker, handles, numHandles) -> bool.  `handles_ptr` addresses
/// an array of `num_handles` compiler handles (caller-owned slot).
/// Complexity: O(num_handles).
pub fn glslang_sh_link_ext(lib: &GlslangLibrary, handle: Int, handles_ptr: Int, num_handles: Int) -> Bool
  requires: lib.handle != 0
  requires: handle != 0
  requires: handles_ptr != 0
  requires: num_handles > 0
{
  unsafe {
    let f = lib.p_sh_link_ext as fn(Int, Int, Int) -> Int32;
    return (f(handle, handles_ptr, num_handles) as Int) != 0;
  }
}

/// ShSetEncryptionMethod(handle) (placeholder upstream).
/// Complexity: O(1).
pub fn glslang_sh_set_encryption_method(lib: &GlslangLibrary, handle: Int)
  requires: lib.handle != 0
  requires: handle != 0
{
  unsafe {
    let f = lib.p_sh_set_encryption_method as fn(Int);
    f(handle);
  }
}

/// ShGetInfoLog(handle) -> copied info-log string ("" when none).
/// Complexity: O(len).
pub fn glslang_sh_get_info_log(lib: &GlslangLibrary, handle: Int) -> Str
  requires: lib.handle != 0
  requires: handle != 0
{
  unsafe {
    let f = lib.p_sh_get_info_log as fn(Int) -> *UInt8;
    return glslang_cstr(f(handle) as Int);
  }
}

/// ShGetExecutable(handle) -> raw executable pointer as Int (0 when none).
/// Complexity: O(1).
pub fn glslang_sh_get_executable(lib: &GlslangLibrary, handle: Int) -> Int
  requires: lib.handle != 0
  requires: handle != 0
{
  unsafe {
    let f = lib.p_sh_get_executable as fn(Int) -> Int;
    return f(handle);
  }
}

/// ShSetVirtualAttributeBindings(handle, table*) -> bool.  table_ptr is a
/// caller-owned ShBindingTable ({ int numBindings; ShBinding* bindings; }).
/// Complexity: O(1).
pub fn glslang_sh_set_virtual_attribute_bindings(lib: &GlslangLibrary, handle: Int, table_ptr: Int) -> Bool
  requires: lib.handle != 0
  requires: handle != 0
  requires: table_ptr != 0
{
  unsafe {
    let f = lib.p_sh_set_virtual_attribute_bindings as fn(Int, Int) -> Int32;
    return (f(handle, table_ptr) as Int) != 0;
  }
}

/// ShSetFixedAttributeBindings(handle, table*) -> bool.
/// Complexity: O(1).
pub fn glslang_sh_set_fixed_attribute_bindings(lib: &GlslangLibrary, handle: Int, table_ptr: Int) -> Bool
  requires: lib.handle != 0
  requires: handle != 0
  requires: table_ptr != 0
{
  unsafe {
    let f = lib.p_sh_set_fixed_attribute_bindings as fn(Int, Int) -> Int32;
    return (f(handle, table_ptr) as Int) != 0;
  }
}

/// ShExcludeAttributes(handle, attributes, count) -> bool.  attributes_ptr
/// addresses `count` ints (caller-owned slot).
/// Complexity: O(count).
pub fn glslang_sh_exclude_attributes(lib: &GlslangLibrary, handle: Int, attributes_ptr: Int, count: Int) -> Bool
  requires: lib.handle != 0
  requires: handle != 0
  requires: attributes_ptr != 0
  requires: count > 0
{
  unsafe {
    let f = lib.p_sh_exclude_attributes as fn(Int, Int, Int) -> Int32;
    return (f(handle, attributes_ptr, count) as Int) != 0;
  }
}

/// ShGetUniformLocation(uniformMap, name) -> location.  Upstream declares
/// -1 for "not found"; the shipped 16.3.0 build returns 0 for a name absent
/// from an empty map (probe 2026-10-11) -- callers should treat values <= 0
/// as "no such uniform".
/// Complexity: O(len).
pub fn glslang_sh_get_uniform_location(lib: &GlslangLibrary, uniform_map: Int, name: Str) -> Int
  requires: lib.handle != 0
  requires: uniform_map != 0
  requires: name.len() > 0
{
  unsafe {
    let f = lib.p_sh_get_uniform_location as fn(Int, *UInt8) -> Int32;
    return f(uniform_map, name.c_str()) as Int;
  }
}

// =========================================================================
// C resource-limits helpers (glslang-default-resource-limits.dll)
// =========================================================================

/// glslang_resource() -> pointer to a writable glslang_resource_t (0 on
/// failure).  The pointer is library-owned; pass it to shader input slots.
/// Complexity: O(1).
pub fn glslang_resource(lim: &GlslangResourceLimitsLibrary) -> Int
  requires: lim.handle != 0
{
  unsafe {
    let f = lim.p_resource as fn() -> Int;
    return f();
  }
}

/// glslang_default_resource() -> pointer to the default glslang_resource_t
/// (0 on failure).  Required by the shader parse/preprocess path.
/// Complexity: O(1).
pub fn glslang_default_resource(lim: &GlslangResourceLimitsLibrary) -> Int
  requires: lim.handle != 0
{
  unsafe {
    let f = lim.p_default_resource as fn() -> Int;
    return f();
  }
}

/// glslang_default_resource_string() -> pointer to a malloc'd human-readable
/// default-resource string (0 on failure).  Upstream wart: the returned
/// string is never freed by this package (no matching free convention in the
/// C surface); callers that must not leak should not call it.
/// Complexity: O(1).
pub fn glslang_default_resource_string(lim: &GlslangResourceLimitsLibrary) -> Int
  requires: lim.handle != 0
{
  unsafe {
    let f = lim.p_default_resource_string as fn() -> Int;
    return f();
  }
}

/// glslang_decode_resource_limits(resources*, config*): decode `config`
/// ("Name value Name value ...", strtok-separated) into the owned
/// GLSLANG_RESOURCE_SIZE-byte slot `resources`.  C reads our config buffer
/// (and tokenizes it in place) and writes the struct into our slot; the
/// caller reads it back byte-indexed with the field layout pinned in
/// SPEC.md.
/// Complexity: O(len).
pub fn glslang_decode_resource_limits(lim: &GlslangResourceLimitsLibrary, resources: &mut Vec[UInt8], config: &mut Vec[UInt8])
  requires: lim.handle != 0
  requires: resources.len() >= GLSLANG_RESOURCE_SIZE
  requires: config.len() >= 2
{
  unsafe {
    let f = lim.p_decode_resource_limits as fn(*UInt8, *UInt8);
    f(resources.as_mut_ptr(), config.as_mut_ptr());
  }
}

// =========================================================================
// High-level helpers (owned-buffer compile path)
// =========================================================================

/// Build a glslang_input_t (owned 96-byte slot) for a single GLSL source
/// string targeting Vulkan-flavoured SPIR-V.  The `code` Str must outlive
/// every call that takes this slot; `resource_ptr` must be a valid
/// glslang_resource_t* from glslang_default_resource (or a decoded custom
/// resource).  messages is the GLSLANG_MSG_* bitmask.
/// Complexity: O(code).
pub fn glslang_input_glsl(code: Str, stage: Int, client_version: Int, messages: Int,
    resource_ptr: Int, default_version: Int) -> Vec[UInt8]
  requires: code.len() > 0
  requires: stage >= 0
  requires: resource_ptr != 0
  requires: default_version > 0
{
  var inp = glslang_slot(GLSLANG_INPUT_SIZE);
  let code_ptr = glslang_str_c_ptr(code);
  glslang_write_u32(&mut inp, GLSLANG_INPUT_OFF_LANGUAGE, GLSLANG_SOURCE_GLSL);
  glslang_write_u32(&mut inp, GLSLANG_INPUT_OFF_STAGE, stage);
  glslang_write_u32(&mut inp, GLSLANG_INPUT_OFF_CLIENT, GLSLANG_CLIENT_VULKAN);
  glslang_write_u32(&mut inp, GLSLANG_INPUT_OFF_CLIENT_VERSION, client_version);
  glslang_write_u32(&mut inp, GLSLANG_INPUT_OFF_TARGET_LANGUAGE, GLSLANG_TARGET_SPV);
  glslang_write_u32(&mut inp, GLSLANG_INPUT_OFF_TARGET_LANGUAGE_VERSION, GLSLANG_TARGET_SPV_1_0);
  glslang_write_u64(&mut inp, GLSLANG_INPUT_OFF_CODE, code_ptr);
  glslang_write_u32(&mut inp, GLSLANG_INPUT_OFF_DEFAULT_VERSION, default_version);
  glslang_write_u32(&mut inp, GLSLANG_INPUT_OFF_DEFAULT_PROFILE, GLSLANG_NO_PROFILE);
  glslang_write_u32(&mut inp, GLSLANG_INPUT_OFF_FORCE_DEFAULT, 0);
  glslang_write_u32(&mut inp, GLSLANG_INPUT_OFF_FORWARD_COMPATIBLE, 0);
  glslang_write_u32(&mut inp, GLSLANG_INPUT_OFF_MESSAGES, messages);
  glslang_write_u64(&mut inp, GLSLANG_INPUT_OFF_RESOURCE, resource_ptr);
  return inp;
}

/// Copy the program's generated SPIR-V into a fresh owned byte buffer
/// (4 bytes per word; empty when nothing was generated).  This is the C
/// copy-out direction: glslang memcpys into OUR buffer.
/// Complexity: O(size).
pub fn glslang_program_spirv_words(lib: &GlslangLibrary, program: Int) -> Vec[UInt8]
  requires: lib.handle != 0
  requires: program != 0
{
  let n = glslang_program_spirv_get_size(lib, program);
  if n <= 0 {
    var empty: Vec[UInt8] = Vec[UInt8].new();
    return empty;
  }
  var out: Vec[UInt8] = glslang_slot(n * 4);
  glslang_program_spirv_get(lib, program, &mut out);
  return out;
}

/// Full GLSL -> SPIR-V compile through the C interface: shader create,
/// preprocess, parse, program link, SPIR-V generate, owned-buffer copy.
/// Returns Err with the shader/program info log on failure.  Requires
/// glslang_initialize_process to have run; the `code` Str must outlive the
/// call (it does: it is a parameter).
/// Complexity: O(compile).
pub fn glslang_compile_glsl_to_spirv(lib: &GlslangLibrary, code: Str, stage: Int,
    client_version: Int, messages: Int, resource_ptr: Int, default_version: Int) -> Result[Vec[UInt8], Str]
  requires: lib.handle != 0
  requires: code.len() > 0
  requires: stage >= 0
  requires: resource_ptr != 0
  requires: default_version > 0
{
  var inp = glslang_input_glsl(code, stage, client_version, messages, resource_ptr, default_version);
  let sh = glslang_shader_create(lib, &mut inp);
  if sh == 0 {
    return Err("glslang: shader_create failed (stage " + convert.int_to_string(stage) + ")");
  }
  if !glslang_shader_preprocess(lib, sh, &mut inp) {
    let log = glslang_shader_get_info_log(lib, sh);
    glslang_shader_delete(lib, sh);
    return Err("glslang: preprocess failed: " + log);
  }
  if !glslang_shader_parse(lib, sh, &mut inp) {
    let log = glslang_shader_get_info_log(lib, sh);
    glslang_shader_delete(lib, sh);
    return Err("glslang: parse failed: " + log);
  }
  let prog = glslang_program_create(lib);
  if prog == 0 {
    glslang_shader_delete(lib, sh);
    return Err("glslang: program_create failed");
  }
  glslang_program_add_shader(lib, prog, sh);
  if !glslang_program_link(lib, prog, messages) {
    let log = glslang_program_get_info_log(lib, prog);
    glslang_program_delete(lib, prog);
    glslang_shader_delete(lib, sh);
    return Err("glslang: link failed: " + log);
  }
  glslang_program_spirv_generate(lib, prog, stage);
  let size = glslang_program_spirv_get_size(lib, prog);
  if size <= 0 {
    let msg = glslang_program_spirv_get_messages(lib, prog);
    glslang_program_delete(lib, prog);
    glslang_shader_delete(lib, sh);
    return Err("glslang: SPIR-V generation produced no words: " + msg);
  }
  var out: Vec[UInt8] = glslang_slot(size * 4);
  glslang_program_spirv_get(lib, prog, &mut out);
  glslang_program_delete(lib, prog);
  glslang_shader_delete(lib, sh);
  return Ok(out);
}
