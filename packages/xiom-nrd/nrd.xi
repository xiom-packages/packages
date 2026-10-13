// XIOM -- xiom.nrd: NVIDIA Real-time Denoisers (NRD) integration surface.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// DECISION (BINDINGS lane 2026-10-13, REL-20261013-1926-packages): the
// upstream (github.com/NVIDIA-RTX/NRD, tag v4.17.3, commit 792eff19) is
// **NOT MIT** -- it is the proprietary "NVIDIA RTX SDKs LICENSE" (LICENSE.txt
// at the pinned commit; clauses 4(b)/4(e) forbid source redistribution and
// any open-source-license application).  Vendoring is therefore NOT allowed
// and this package follows the FFmpeg precedent (docs/BINDINGS-LANE.md
// sec. 4/11; docs/UPSTREAM-FIRST.md sec. 2): **reference-only, dynamic
// loader only** -- independent XIOM code written against the public header
// declarations (the "declaration oracle", PROVENANCE.md) plus an XIOM-side
// C++ bridge (src/nrd_bridge.cpp, ours, compiled with --c-source).  No NRD
// code, headers, shader blobs, or binaries ship in this repository.
//
// Runtime model: NRD ships as NRD.dll (built locally from the clone by the
// licensee; the SDK grant covers install/use).  `nrd_load` resolves the
// module and its 9 C entry points (NRD_API extern "C", plain export names
// `CreateInstance` ... `GetDenoiserString`); when no runtime is present the
// suite classifies NRD_LOAD_ABSENT and SKIPs green.
//
// DECLARED surface (100% of the public C integration API, NRD.h v4.17.3):
//   CreateInstance / DestroyInstance / GetLibraryDesc / GetInstanceDesc /
//   SetCommonSettings / SetDenoiserSettings / GetComputeDispatches /
//   GetResourceTypeString / GetDenoiserString
// plus the request/response types they expose: InstanceCreationDesc,
// DenoiserDesc, LibraryDesc, InstanceDesc, DescriptorPoolDesc,
// DispatchDesc, ResourceDesc, ResourceRangeDesc, TextureDesc, CommonSettings,
// ReblurSettings, RelaxSettings, SigmaSettings, ReferenceSettings and their
// nested settings structs and enums (see SPEC.md for the coverage table).
//
// v0.64.4 FFI discipline (findings B-20/B-21/B-23/B-24/B-25/B-26):
//   * handles cross as `Int` params (B-25: no pointer casts from integers);
//   * every out-param is one XIOM-owned Vec[UInt8] slot, read byte-indexed
//     (B-17/B-24); XIOM never reads runtime-owned memory (B-20);
//   * settings images are owned XIOM bytes; the bridge forwards the pointer
//     (the runtime copies from it) and layout offsets come from the bridge's
//     offsetof tables -- one single source of ABI truth;
//   * nullable C args never receive the bare `null` literal (B-23);
//   * flat outcome structs only, never `Result[Option[T]]` (B-26);
//   * Str comparisons go through `string.str_compare`.
//
// GPU execution: dispatch plans are computed on the CPU (GetComputeDispatches
// needs no device).  Executing them requires an application-owned D3D12/VK
// device bridge, pipelines built from NRD shader blobs and resource binding;
// that path is out of scope for 0.1.0 and `nrd_execute` returns the typed
// NRD_EXEC_NO_DEVICE classification (SKIP), never a silent success.

module xiom.nrd

use xiom.convert;
use xiom.string;

// =========================================================================
// Identity / classification
// =========================================================================

/// Pinned upstream (PROVENANCE.md declaration oracle).
pub const NRD_VERSION_MAJOR: Int = 4;
pub const NRD_VERSION_MINOR: Int = 17;
pub const NRD_VERSION_BUILD: Int = 3;

/// Load classification (mirrors the FFmpeg loader model).
pub const NRD_LOAD_ABSENT: Int = 0; // no runtime -> SKIP
pub const NRD_LOAD_ABI: Int = 1;    // module loaded but entry points missing -> FAIL
pub const NRD_LOAD_OK: Int = 2;

/// Bridge status codes (src/nrd_bridge.cpp).
pub const NRD_ERR_NOT_LOADED: Int = 100;
pub const NRD_ERR_BAD_ARGS: Int = 101;
pub const NRD_ERR_SIZE: Int = 102;
pub const NRD_ERR_CAPACITY: Int = 103;

/// nrd::Result values.
pub const NRD_RESULT_SUCCESS: Int = 0;
pub const NRD_RESULT_FAILURE: Int = 1;
pub const NRD_RESULT_INVALID_ARGUMENT: Int = 2;
pub const NRD_RESULT_UNSUPPORTED: Int = 3;
pub const NRD_RESULT_NON_UNIQUE_IDENTIFIER: Int = 4;
pub const NRD_RESULT_MAX_NUM: Int = 5;

/// Execute-path classification (device owner is the application).
pub const NRD_EXEC_OK: Int = 0;
pub const NRD_EXEC_INVALID: Int = 1;
pub const NRD_EXEC_NO_DEVICE: Int = 2; // typed SKIP when no device bridge

// =========================================================================
// Public enums (NRDDescs.h / NRDSettings.h @ v4.17.3)
// =========================================================================

// nrd::ResourceType (32 values + MAX_NUM)
pub const NRD_RESOURCE_IN_MV: Int = 0;
pub const NRD_RESOURCE_IN_NORMAL_ROUGHNESS: Int = 1;
pub const NRD_RESOURCE_IN_VIEWZ: Int = 2;
pub const NRD_RESOURCE_IN_DIFF_CONFIDENCE: Int = 3;
pub const NRD_RESOURCE_IN_SPEC_CONFIDENCE: Int = 4;
pub const NRD_RESOURCE_IN_DISOCCLUSION_THRESHOLD_MIX: Int = 5;
pub const NRD_RESOURCE_IN_DIFF_RADIANCE_HITDIST: Int = 6;
pub const NRD_RESOURCE_IN_SPEC_RADIANCE_HITDIST: Int = 7;
pub const NRD_RESOURCE_IN_DIFF_HITDIST: Int = 8;
pub const NRD_RESOURCE_IN_SPEC_HITDIST: Int = 9;
pub const NRD_RESOURCE_IN_DIFF_DIRECTION_HITDIST: Int = 10;
pub const NRD_RESOURCE_IN_DIFF_SH0: Int = 11;
pub const NRD_RESOURCE_IN_DIFF_SH1: Int = 12;
pub const NRD_RESOURCE_IN_SPEC_SH0: Int = 13;
pub const NRD_RESOURCE_IN_SPEC_SH1: Int = 14;
pub const NRD_RESOURCE_IN_PENUMBRA: Int = 15;
pub const NRD_RESOURCE_IN_TRANSLUCENCY: Int = 16;
pub const NRD_RESOURCE_IN_SIGNAL: Int = 17;
pub const NRD_RESOURCE_OUT_DIFF_RADIANCE_HITDIST: Int = 18;
pub const NRD_RESOURCE_OUT_SPEC_RADIANCE_HITDIST: Int = 19;
pub const NRD_RESOURCE_OUT_DIFF_SH0: Int = 20;
pub const NRD_RESOURCE_OUT_DIFF_SH1: Int = 21;
pub const NRD_RESOURCE_OUT_SPEC_SH0: Int = 22;
pub const NRD_RESOURCE_OUT_SPEC_SH1: Int = 23;
pub const NRD_RESOURCE_OUT_DIFF_HITDIST: Int = 24;
pub const NRD_RESOURCE_OUT_SPEC_HITDIST: Int = 25;
pub const NRD_RESOURCE_OUT_DIFF_DIRECTION_HITDIST: Int = 26;
pub const NRD_RESOURCE_OUT_SHADOW_TRANSLUCENCY: Int = 27;
pub const NRD_RESOURCE_OUT_SIGNAL: Int = 28;
pub const NRD_RESOURCE_OUT_VALIDATION: Int = 29;
pub const NRD_RESOURCE_TRANSIENT_POOL: Int = 30;
pub const NRD_RESOURCE_PERMANENT_POOL: Int = 31;
pub const NRD_RESOURCE_TYPE_MAX_NUM: Int = 32;

// nrd::Denoiser (19 values + MAX_NUM)
pub const NRD_DENOISER_REBLUR_DIFFUSE: Int = 0;
pub const NRD_DENOISER_REBLUR_DIFFUSE_OCCLUSION: Int = 1;
pub const NRD_DENOISER_REBLUR_DIFFUSE_SH: Int = 2;
pub const NRD_DENOISER_REBLUR_SPECULAR: Int = 3;
pub const NRD_DENOISER_REBLUR_SPECULAR_OCCLUSION: Int = 4;
pub const NRD_DENOISER_REBLUR_SPECULAR_SH: Int = 5;
pub const NRD_DENOISER_REBLUR_DIFFUSE_SPECULAR: Int = 6;
pub const NRD_DENOISER_REBLUR_DIFFUSE_SPECULAR_OCCLUSION: Int = 7;
pub const NRD_DENOISER_REBLUR_DIFFUSE_SPECULAR_SH: Int = 8;
pub const NRD_DENOISER_REBLUR_DIFFUSE_DIRECTIONAL_OCCLUSION: Int = 9;
pub const NRD_DENOISER_RELAX_DIFFUSE: Int = 10;
pub const NRD_DENOISER_RELAX_DIFFUSE_SH: Int = 11;
pub const NRD_DENOISER_RELAX_SPECULAR: Int = 12;
pub const NRD_DENOISER_RELAX_SPECULAR_SH: Int = 13;
pub const NRD_DENOISER_RELAX_DIFFUSE_SPECULAR: Int = 14;
pub const NRD_DENOISER_RELAX_DIFFUSE_SPECULAR_SH: Int = 15;
pub const NRD_DENOISER_SIGMA_SHADOW: Int = 16;
pub const NRD_DENOISER_SIGMA_SHADOW_TRANSLUCENCY: Int = 17;
pub const NRD_DENOISER_REFERENCE: Int = 18;
pub const NRD_DENOISER_MAX_NUM: Int = 19;

// nrd::Format (43 values + MAX_NUM)
pub const NRD_FORMAT_R8_UNORM: Int = 0;
pub const NRD_FORMAT_R8_SNORM: Int = 1;
pub const NRD_FORMAT_R8_UINT: Int = 2;
pub const NRD_FORMAT_R8_SINT: Int = 3;
pub const NRD_FORMAT_RG8_UNORM: Int = 4;
pub const NRD_FORMAT_RG8_SNORM: Int = 5;
pub const NRD_FORMAT_RG8_UINT: Int = 6;
pub const NRD_FORMAT_RG8_SINT: Int = 7;
pub const NRD_FORMAT_RGBA8_UNORM: Int = 8;
pub const NRD_FORMAT_RGBA8_SNORM: Int = 9;
pub const NRD_FORMAT_RGBA8_UINT: Int = 10;
pub const NRD_FORMAT_RGBA8_SINT: Int = 11;
pub const NRD_FORMAT_RGBA8_SRGB: Int = 12;
pub const NRD_FORMAT_R16_UNORM: Int = 13;
pub const NRD_FORMAT_R16_SNORM: Int = 14;
pub const NRD_FORMAT_R16_UINT: Int = 15;
pub const NRD_FORMAT_R16_SINT: Int = 16;
pub const NRD_FORMAT_R16_SFLOAT: Int = 17;
pub const NRD_FORMAT_RG16_UNORM: Int = 18;
pub const NRD_FORMAT_RG16_SNORM: Int = 19;
pub const NRD_FORMAT_RG16_UINT: Int = 20;
pub const NRD_FORMAT_RG16_SINT: Int = 21;
pub const NRD_FORMAT_RG16_SFLOAT: Int = 22;
pub const NRD_FORMAT_RGBA16_UNORM: Int = 23;
pub const NRD_FORMAT_RGBA16_SNORM: Int = 24;
pub const NRD_FORMAT_RGBA16_UINT: Int = 25;
pub const NRD_FORMAT_RGBA16_SINT: Int = 26;
pub const NRD_FORMAT_RGBA16_SFLOAT: Int = 27;
pub const NRD_FORMAT_R32_UINT: Int = 28;
pub const NRD_FORMAT_R32_SINT: Int = 29;
pub const NRD_FORMAT_R32_SFLOAT: Int = 30;
pub const NRD_FORMAT_RG32_UINT: Int = 31;
pub const NRD_FORMAT_RG32_SINT: Int = 32;
pub const NRD_FORMAT_RG32_SFLOAT: Int = 33;
pub const NRD_FORMAT_RGB32_UINT: Int = 34;
pub const NRD_FORMAT_RGB32_SINT: Int = 35;
pub const NRD_FORMAT_RGB32_SFLOAT: Int = 36;
pub const NRD_FORMAT_RGBA32_UINT: Int = 37;
pub const NRD_FORMAT_RGBA32_SINT: Int = 38;
pub const NRD_FORMAT_RGBA32_SFLOAT: Int = 39;
pub const NRD_FORMAT_R10_G10_B10_A2_UNORM: Int = 40;
pub const NRD_FORMAT_R10_G10_B10_A2_UINT: Int = 41;
pub const NRD_FORMAT_R11_G11_B10_UFLOAT: Int = 42;
pub const NRD_FORMAT_R9_G9_B9_E5_UFLOAT: Int = 43;
pub const NRD_FORMAT_MAX_NUM: Int = 44;

// nrd::DescriptorType
pub const NRD_DESCRIPTOR_TEXTURE: Int = 0;
pub const NRD_DESCRIPTOR_STORAGE_TEXTURE: Int = 1;
pub const NRD_DESCRIPTOR_TYPE_MAX_NUM: Int = 2;

// nrd::Sampler
pub const NRD_SAMPLER_NEAREST_CLAMP: Int = 0;
pub const NRD_SAMPLER_LINEAR_CLAMP: Int = 1;
pub const NRD_SAMPLER_MAX_NUM: Int = 2;

// nrd::NormalEncoding
pub const NRD_NORMAL_ENCODING_RGBA8_UNORM: Int = 0;
pub const NRD_NORMAL_ENCODING_RGBA8_SNORM: Int = 1;
pub const NRD_NORMAL_ENCODING_R10_G10_B10_A2_UNORM: Int = 2;
pub const NRD_NORMAL_ENCODING_RGBA16_UNORM: Int = 3;
pub const NRD_NORMAL_ENCODING_RGBA16_SNORM: Int = 4;
pub const NRD_NORMAL_ENCODING_MAX_NUM: Int = 5;

// nrd::RoughnessEncoding
pub const NRD_ROUGHNESS_ENCODING_SQ_LINEAR: Int = 0;
pub const NRD_ROUGHNESS_ENCODING_LINEAR: Int = 1;
pub const NRD_ROUGHNESS_ENCODING_SQRT_LINEAR: Int = 2;
pub const NRD_ROUGHNESS_ENCODING_MAX_NUM: Int = 3;

// nrd::CheckerboardMode
pub const NRD_CHECKERBOARD_OFF: Int = 0;
pub const NRD_CHECKERBOARD_BLACK: Int = 1;
pub const NRD_CHECKERBOARD_WHITE: Int = 2;
pub const NRD_CHECKERBOARD_MAX_NUM: Int = 3;

// nrd::AccumulationMode
pub const NRD_ACCUMULATION_CONTINUE: Int = 0;
pub const NRD_ACCUMULATION_RESTART: Int = 1;
pub const NRD_ACCUMULATION_CLEAR_AND_RESTART: Int = 2;
pub const NRD_ACCUMULATION_MAX_NUM: Int = 3;

// nrd::HitDistanceReconstructionMode
pub const NRD_HITDIST_RECON_OFF: Int = 0;
pub const NRD_HITDIST_RECON_AREA_3X3: Int = 1;
pub const NRD_HITDIST_RECON_AREA_5X5: Int = 2;
pub const NRD_HITDIST_RECON_MAX_NUM: Int = 3;

// =========================================================================
// Settings layout kinds and field indexes (SPEC.md "settings layout tables")
// =========================================================================

pub const NRD_SETTINGS_COMMON: Int = 0;
pub const NRD_SETTINGS_REBLUR: Int = 1;
pub const NRD_SETTINGS_RELAX: Int = 2;
pub const NRD_SETTINGS_SIGMA: Int = 3;
pub const NRD_SETTINGS_REFERENCE: Int = 4;

// CommonSettings fields (31 entries)
pub const NRD_CS_VIEW_TO_CLIP: Int = 0;
pub const NRD_CS_VIEW_TO_CLIP_PREV: Int = 1;
pub const NRD_CS_WORLD_TO_VIEW: Int = 2;
pub const NRD_CS_WORLD_TO_VIEW_PREV: Int = 3;
pub const NRD_CS_WORLD_PREV_TO_WORLD: Int = 4;
pub const NRD_CS_MOTION_VECTOR_SCALE: Int = 5;
pub const NRD_CS_CAMERA_JITTER: Int = 6;
pub const NRD_CS_CAMERA_JITTER_PREV: Int = 7;
pub const NRD_CS_RESOURCE_SIZE: Int = 8;
pub const NRD_CS_RESOURCE_SIZE_PREV: Int = 9;
pub const NRD_CS_RECT_SIZE: Int = 10;
pub const NRD_CS_RECT_SIZE_PREV: Int = 11;
pub const NRD_CS_VIEWZ_SCALE: Int = 12;
pub const NRD_CS_TIME_DELTA_BETWEEN_FRAMES: Int = 13;
pub const NRD_CS_DENOISING_RANGE: Int = 14;
pub const NRD_CS_DISOCCLUSION_THRESHOLD: Int = 15;
pub const NRD_CS_DISOCCLUSION_THRESHOLD_ALTERNATE: Int = 16;
pub const NRD_CS_CAMERA_ATTACHED_REFLECTION_MATERIAL_ID: Int = 17;
pub const NRD_CS_STRAND_MATERIAL_ID: Int = 18;
pub const NRD_CS_HISTORY_FIX_ALTERNATE_PIXEL_STRIDE_MATERIAL_ID: Int = 19;
pub const NRD_CS_STRAND_THICKNESS: Int = 20;
pub const NRD_CS_SPLIT_SCREEN: Int = 21;
pub const NRD_CS_PRINTF_AT: Int = 22;
pub const NRD_CS_DEBUG: Int = 23;
pub const NRD_CS_RECT_ORIGIN: Int = 24;
pub const NRD_CS_FRAME_INDEX: Int = 25;
pub const NRD_CS_ACCUMULATION_MODE: Int = 26;
pub const NRD_CS_IS_MOTION_VECTOR_IN_WORLD_SPACE: Int = 27;
pub const NRD_CS_IS_HISTORY_CONFIDENCE_AVAILABLE: Int = 28;
pub const NRD_CS_IS_DISOCCLUSION_THRESHOLD_MIX_AVAILABLE: Int = 29;
pub const NRD_CS_ENABLE_VALIDATION: Int = 30;
pub const NRD_CS_FIELD_COUNT: Int = 31;

// ReblurSettings fields (28 entries)
pub const NRD_RS_HIT_DISTANCE_PARAMETERS: Int = 0;
pub const NRD_RS_ANTILAG_SETTINGS: Int = 1;
pub const NRD_RS_RESPONSIVE_ACCUMULATION_SETTINGS: Int = 2;
pub const NRD_RS_CONVERGENCE_SETTINGS: Int = 3;
pub const NRD_RS_MAX_ACCUMULATED_FRAME_NUM: Int = 4;
pub const NRD_RS_MAX_FAST_ACCUMULATED_FRAME_NUM: Int = 5;
pub const NRD_RS_MAX_STABILIZED_FRAME_NUM: Int = 6;
pub const NRD_RS_HISTORY_FIX_FRAME_NUM: Int = 7;
pub const NRD_RS_HISTORY_FIX_BASE_PIXEL_STRIDE: Int = 8;
pub const NRD_RS_HISTORY_FIX_ALTERNATE_PIXEL_STRIDE: Int = 9;
pub const NRD_RS_FAST_HISTORY_CLAMPING_SIGMA_SCALE: Int = 10;
pub const NRD_RS_DIFFUSE_PREPASS_BLUR_RADIUS: Int = 11;
pub const NRD_RS_SPECULAR_PREPASS_BLUR_RADIUS: Int = 12;
pub const NRD_RS_MIN_HIT_DISTANCE_WEIGHT: Int = 13;
pub const NRD_RS_MIN_BLUR_RADIUS: Int = 14;
pub const NRD_RS_MAX_BLUR_RADIUS: Int = 15;
pub const NRD_RS_LOBE_ANGLE_FRACTION: Int = 16;
pub const NRD_RS_ROUGHNESS_FRACTION: Int = 17;
pub const NRD_RS_PLANE_DISTANCE_SENSITIVITY: Int = 18;
pub const NRD_RS_SPECULAR_PROBABILITY_THRESHOLDS: Int = 19;
pub const NRD_RS_FIREFLY_SUPPRESSOR_MIN_RELATIVE_SCALE: Int = 20;
pub const NRD_RS_MIN_MATERIAL_FOR_DIFFUSE: Int = 21;
pub const NRD_RS_MIN_MATERIAL_FOR_SPECULAR: Int = 22;
pub const NRD_RS_CHECKERBOARD_MODE: Int = 23;
pub const NRD_RS_HIT_DISTANCE_RECONSTRUCTION_MODE: Int = 24;
pub const NRD_RS_ENABLE_ANTI_FIREFLY: Int = 25;
pub const NRD_RS_USE_PREPASS_ONLY_FOR_SPECULAR_MOTION_ESTIMATION: Int = 26;
pub const NRD_RS_RETURN_HISTORY_LENGTH_INSTEAD_OF_OCCLUSION: Int = 27;
pub const NRD_RS_FIELD_COUNT: Int = 28;

// RelaxSettings fields (36 entries)
pub const NRD_RXS_ANTILAG_SETTINGS: Int = 0;
pub const NRD_RXS_DIFFUSE_MAX_ACCUMULATED_FRAME_NUM: Int = 1;
pub const NRD_RXS_SPECULAR_MAX_ACCUMULATED_FRAME_NUM: Int = 2;
pub const NRD_RXS_DIFFUSE_MAX_FAST_ACCUMULATED_FRAME_NUM: Int = 3;
pub const NRD_RXS_SPECULAR_MAX_FAST_ACCUMULATED_FRAME_NUM: Int = 4;
pub const NRD_RXS_HISTORY_FIX_FRAME_NUM: Int = 5;
pub const NRD_RXS_HISTORY_FIX_BASE_PIXEL_STRIDE: Int = 6;
pub const NRD_RXS_HISTORY_FIX_ALTERNATE_PIXEL_STRIDE: Int = 7;
pub const NRD_RXS_HISTORY_FIX_EDGE_STOPPING_NORMAL_POWER: Int = 8;
pub const NRD_RXS_FAST_HISTORY_CLAMPING_SIGMA_SCALE: Int = 9;
pub const NRD_RXS_DIFFUSE_PREPASS_BLUR_RADIUS: Int = 10;
pub const NRD_RXS_SPECULAR_PREPASS_BLUR_RADIUS: Int = 11;
pub const NRD_RXS_MIN_HIT_DISTANCE_WEIGHT: Int = 12;
pub const NRD_RXS_SPATIAL_VARIANCE_ESTIMATION_HISTORY_THRESHOLD: Int = 13;
pub const NRD_RXS_DIFFUSE_PHI_LUMINANCE: Int = 14;
pub const NRD_RXS_SPECULAR_PHI_LUMINANCE: Int = 15;
pub const NRD_RXS_LOBE_ANGLE_FRACTION: Int = 16;
pub const NRD_RXS_ROUGHNESS_FRACTION: Int = 17;
pub const NRD_RXS_SPECULAR_VARIANCE_BOOST: Int = 18;
pub const NRD_RXS_SPECULAR_LOBE_ANGLE_SLACK: Int = 19;
pub const NRD_RXS_ATROUS_ITERATION_NUM: Int = 20;
pub const NRD_RXS_DIFFUSE_MIN_LUMINANCE_WEIGHT: Int = 21;
pub const NRD_RXS_SPECULAR_MIN_LUMINANCE_WEIGHT: Int = 22;
pub const NRD_RXS_DEPTH_THRESHOLD: Int = 23;
pub const NRD_RXS_CONFIDENCE_DRIVEN_RELAXATION_MULTIPLIER: Int = 24;
pub const NRD_RXS_CONFIDENCE_DRIVEN_LUMINANCE_EDGE_STOPPING_RELAXATION: Int = 25;
pub const NRD_RXS_CONFIDENCE_DRIVEN_NORMAL_EDGE_STOPPING_RELAXATION: Int = 26;
pub const NRD_RXS_LUMINANCE_EDGE_STOPPING_RELAXATION: Int = 27;
pub const NRD_RXS_NORMAL_EDGE_STOPPING_RELAXATION: Int = 28;
pub const NRD_RXS_ROUGHNESS_EDGE_STOPPING_RELAXATION: Int = 29;
pub const NRD_RXS_CHECKERBOARD_MODE: Int = 30;
pub const NRD_RXS_HIT_DISTANCE_RECONSTRUCTION_MODE: Int = 31;
pub const NRD_RXS_MIN_MATERIAL_FOR_DIFFUSE: Int = 32;
pub const NRD_RXS_MIN_MATERIAL_FOR_SPECULAR: Int = 33;
pub const NRD_RXS_ENABLE_ANTI_FIREFLY: Int = 34;
pub const NRD_RXS_ENABLE_ROUGHNESS_EDGE_STOPPING: Int = 35;
pub const NRD_RXS_FIELD_COUNT: Int = 36;

// SigmaSettings fields (3 entries)
pub const NRD_SS_LIGHT_DIRECTION: Int = 0;
pub const NRD_SS_PLANE_DISTANCE_SENSITIVITY: Int = 1;
pub const NRD_SS_MAX_STABILIZED_FRAME_NUM: Int = 2;
pub const NRD_SS_FIELD_COUNT: Int = 3;

// ReferenceSettings fields (1 entry)
pub const NRD_RFS_MAX_ACCUMULATED_FRAME_NUM: Int = 0;
pub const NRD_RFS_FIELD_COUNT: Int = 1;

// =========================================================================
// Dispatch-plan record layout (src/nrd_bridge.cpp, NRDB_SUMMARY_SIZE = 96)
// =========================================================================

pub const NRD_PLAN_SUMMARY_SIZE: Int = 96;
pub const NRD_PLAN_RES_REC_SIZE: Int = 16;
pub const NRD_PS_IDENTIFIER: Int = 0;
pub const NRD_PS_PIPELINE_INDEX: Int = 4;
pub const NRD_PS_GRID_WIDTH: Int = 8;
pub const NRD_PS_GRID_HEIGHT: Int = 12;
pub const NRD_PS_RESOURCES_NUM: Int = 16;
pub const NRD_PS_CB_SIZE: Int = 20;
pub const NRD_PS_CB_OFFSET: Int = 24;
pub const NRD_PS_RES_OFFSET: Int = 28;
pub const NRD_PS_FLAGS: Int = 32;
pub const NRD_PS_NAME_LEN: Int = 36;
pub const NRD_PS_NAME: Int = 40;
pub const NRD_RR_DESCRIPTOR_TYPE: Int = 0;
pub const NRD_RR_TYPE: Int = 4;
pub const NRD_RR_INDEX_IN_POOL: Int = 8;

/// Logical mirror size of an owned settings image (data has 64 bytes slack).
pub const NRD_SETTINGS_SLACK: Int = 64;

// =========================================================================
// FFI: the XIOM-side bridge (src/nrd_bridge.cpp; ours, never NRD code)
// =========================================================================

extern "C" {
  fn nrdb_try_load(path: *UInt8, len: Int32) -> Int;
  fn nrdb_try_load_auto() -> Int;
  fn nrdb_load_kind() -> Int32;
  fn nrdb_close(h: Int) -> Int32;

  fn nrdb_library_info(h: Int, out: *UInt8, cap: Int32) -> Int32;
  fn nrdb_library_denoiser(h: Int, index: Int32) -> Int32;

  fn nrdb_instance_create(h: Int, ids: *UInt8, kinds: *UInt8, count: Int32, out_inst: *UInt8) -> Int32;
  fn nrdb_instance_destroy(h: Int, inst: Int) -> Int32;
  fn nrdb_instance_info(h: Int, inst: Int, out: *UInt8, cap: Int32) -> Int32;
  fn nrdb_instance_shader_entry(h: Int, inst: Int, dst: *UInt8, cap: Int32) -> Int32;

  fn nrdb_set_common_settings(h: Int, inst: Int, settings: *UInt8, size: Int32) -> Int32;
  fn nrdb_set_denoiser_settings(h: Int, inst: Int, identifier: Int32, settings: *UInt8, size: Int32) -> Int32;

  fn nrdb_plan_counts(h: Int, inst: Int, ids: *UInt8, ids_num: Int32, out: *UInt8) -> Int32;
  fn nrdb_plan_copy(h: Int, inst: Int, ids: *UInt8, ids_num: Int32, summaries: *UInt8, summaries_cap: Int32, resources: *UInt8, resources_cap: Int32, constants: *UInt8, constants_cap: Int32, out: *UInt8) -> Int32;
  fn nrdb_plan_dispatch_name(summaries: *UInt8, cap_records: Int32, index: Int32, dst: *UInt8, dst_cap: Int32) -> Int32;

  fn nrdb_get_resource_string(h: Int, resource_type: Int32, dst: *UInt8, cap: Int32) -> Int32;
  fn nrdb_get_denoiser_string(h: Int, denoiser: Int32, dst: *UInt8, cap: Int32) -> Int32;

  fn nrdb_layout(kind: Int32, offsets: *UInt8, sizes: *UInt8, cap: Int32) -> Int32;
  fn nrdb_layout_size(kind: Int32) -> Int32;
  fn nrdb_common_settings_default(dst: *UInt8, cap: Int32) -> Int32;
  fn nrdb_denoiser_settings_default(kind: Int32, dst: *UInt8, cap: Int32) -> Int32;

  fn nrdb_img_set_u32(dst: *UInt8, cap: Int32, off: Int32, v: Int32) -> Int32;
  fn nrdb_img_set_u16(dst: *UInt8, cap: Int32, off: Int32, v: Int32) -> Int32;
  fn nrdb_img_set_u8(dst: *UInt8, cap: Int32, off: Int32, v: Int32) -> Int32;
  fn nrdb_img_set_f32(dst: *UInt8, cap: Int32, off: Int32, v: Float32) -> Int32;
  fn nrdb_img_get_u32(src: *UInt8, cap: Int32, off: Int32) -> Int32;
  fn nrdb_img_get_u16(src: *UInt8, cap: Int32, off: Int32) -> Int32;
  fn nrdb_img_get_u8(src: *UInt8, cap: Int32, off: Int32) -> Int32;
  fn nrdb_img_get_f32(src: *UInt8, cap: Int32, off: Int32) -> Float32;

  fn nrdb_execute(h: Int, inst: Int, summaries: *UInt8, count: Int32) -> Int32;
}

// =========================================================================
// Owned-slot helpers (B-17/B-24: byte-indexed reads, push-loop allocation)
// =========================================================================

/// n zero bytes in an XIOM-owned slot.  O(n).
pub fn nrd_byte_slot(n: Int) -> Vec[UInt8]
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

fn nrd_slot(n: Int) -> Vec[UInt8]
  requires: n > 0
{
  return nrd_byte_slot(n);
}

fn nrd_rd_u32(buf: &Vec[UInt8], off: Int) -> Int
  requires: off >= 0
  requires: buf.len() >= off + 4
{
  let b0 = buf[off + 0] as Int;
  let b1 = buf[off + 1] as Int;
  let b2 = buf[off + 2] as Int;
  let b3 = buf[off + 3] as Int;
  return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24);
}

fn nrd_rd_u16(buf: &Vec[UInt8], off: Int) -> Int
  requires: off >= 0
  requires: buf.len() >= off + 2
{
  return (buf[off + 0] as Int) | ((buf[off + 1] as Int) << 8);
}

fn nrd_wr_u32(buf: &mut Vec[UInt8], off: Int, v: Int)
  requires: off >= 0
  requires: buf.len() >= off + 4
{
  buf[off + 0] = (v & 255) as UInt8;
  buf[off + 1] = ((v >> 8) & 255) as UInt8;
  buf[off + 2] = ((v >> 16) & 255) as UInt8;
  buf[off + 3] = ((v >> 24) & 255) as UInt8;
}

fn nrd_result_name(code: Int) -> Str
  requires: true
{
  if code == NRD_RESULT_SUCCESS { return "SUCCESS"; }
  if code == NRD_RESULT_FAILURE { return "FAILURE"; }
  if code == NRD_RESULT_INVALID_ARGUMENT { return "INVALID_ARGUMENT"; }
  if code == NRD_RESULT_UNSUPPORTED { return "UNSUPPORTED"; }
  if code == NRD_RESULT_NON_UNIQUE_IDENTIFIER { return "NON_UNIQUE_IDENTIFIER"; }
  if code == NRD_ERR_NOT_LOADED { return "bridge: not loaded"; }
  if code == NRD_ERR_BAD_ARGS { return "bridge: bad args"; }
  if code == NRD_ERR_SIZE { return "bridge: settings image smaller than the ABI mirror"; }
  if code == NRD_ERR_CAPACITY { return "bridge: out slot too small"; }
  return "unknown code " + convert.int_to_string(code);
}

/// Build a u32 little-endian image from XIOM ints (identifiers, enums).
/// Complexity: O(n).
pub fn nrd_u32_image(values: &Vec[Int32]) -> Vec[UInt8]
  requires: true
{
  let n = values.len();
  var out = nrd_slot(n * 4);
  var i: Int = 0;
  while i < n {
    nrd_wr_u32(&mut out, i * 4, values[i] as Int);
    i = i + 1;
  }
  return out;
}

// =========================================================================
// Loader
// =========================================================================

pub type NrdError = {
  kind: Int;
  message: Str;
}

/// A loaded NRD runtime module.
pub type NrdLibrary = {
  h: Int;
}

/// Load NRD.dll: `XIOM_NRD_DLL` env var first, then the default module
/// search (cwd, PATH).  Err(NRD_LOAD_ABSENT) when no runtime is present
/// (the classified SKIP path).  Complexity: O(1) after the load.
pub fn nrd_load() -> Result[NrdLibrary, NrdError]
  requires: true
{
  let h = unsafe { nrdb_try_load_auto() };
  if h == 0 {
    var msg = "NRD.dll not found (XIOM_NRD_DLL / default search)";
    if unsafe { nrdb_load_kind() } as Int == NRD_LOAD_ABI {
      return Err(NrdError{ kind: NRD_LOAD_ABI; message: "NRD.dll loaded but the NRD C entry points are missing" });
    }
    return Err(NrdError{ kind: NRD_LOAD_ABSENT; message: msg });
  }
  return Ok(NrdLibrary{ h: h });
}

/// Load one named module path.  Err(NRD_LOAD_ABSENT) when the module or
/// entry points cannot be resolved (deterministic SKIP-path probe).
/// Complexity: O(1) after the load.
pub fn nrd_load_named(path: Str) -> Result[NrdLibrary, NrdError]
  requires: path.len() > 0
{
  let h = unsafe { nrdb_try_load(path as *UInt8, path.len() as Int32) };
  if h == 0 {
    if unsafe { nrdb_load_kind() } as Int == NRD_LOAD_ABI {
      return Err(NrdError{ kind: NRD_LOAD_ABI; message: path + ": entry points missing" });
    }
    return Err(NrdError{ kind: NRD_LOAD_ABSENT; message: path + ": module not found" });
  }
  return Ok(NrdLibrary{ h: h });
}

/// Unload the runtime module.  Complexity: O(1).
pub fn nrd_close(lib: &NrdLibrary) -> Result[Unit, NrdError]
  requires: lib.h != 0
{
  let rc = unsafe { nrdb_close(lib.h) } as Int;
  if rc == 0 { return Ok(()); }
  return Err(NrdError{ kind: rc; message: nrd_result_name(rc) });
}

// =========================================================================
// Library and instance descriptions
// =========================================================================

pub type NrdLibraryInfo = {
  version_major: Int;
  version_minor: Int;
  version_build: Int;
  normal_encoding: Int;
  roughness_encoding: Int;
  denoisers_num: Int;
  sampler_offset: Int;
  texture_offset: Int;
  constant_buffer_offset: Int;
  storage_texture_offset: Int;
}

pub fn nrd_library_info(lib: &NrdLibrary) -> Result[NrdLibraryInfo, NrdError]
  requires: lib.h != 0
{
  var slot = nrd_slot(48);
  let rc = unsafe { nrdb_library_info(lib.h, slot.as_mut_ptr(), 48) } as Int;
  if rc != 0 { return Err(NrdError{ kind: rc; message: nrd_result_name(rc) }); }
  return Ok(NrdLibraryInfo{
    version_major: nrd_rd_u32(&slot, 0);
    version_minor: nrd_rd_u32(&slot, 4);
    version_build: nrd_rd_u32(&slot, 8);
    normal_encoding: nrd_rd_u32(&slot, 12);
    roughness_encoding: nrd_rd_u32(&slot, 16);
    denoisers_num: nrd_rd_u32(&slot, 20);
    sampler_offset: nrd_rd_u32(&slot, 24);
    texture_offset: nrd_rd_u32(&slot, 28);
    constant_buffer_offset: nrd_rd_u32(&slot, 32);
    storage_texture_offset: nrd_rd_u32(&slot, 36);
  });
}

/// The denoiser kind at library-support index `index` (or -1).
/// Complexity: O(1).
pub fn nrd_library_denoiser(lib: &NrdLibrary, index: Int) -> Int
  requires: lib.h != 0
  requires: index >= 0
{
  return unsafe { nrdb_library_denoiser(lib.h, index as Int32) } as Int;
}

pub type NrdInstanceInfo = {
  cb_and_samplers_space: Int;
  resources_space: Int;
  cb_register: Int;
  samplers_base_register: Int;
  resources_base_register: Int;
  cb_max_data_size: Int;
  samplers_num: Int;
  pipelines_num: Int;
  permanent_pool_size: Int;
  transient_pool_size: Int;
  per_set_textures_max: Int;
  per_set_storage_max: Int;
  total_textures: Int;
  total_storage_textures: Int;
  sets_max: Int;
}

/// GPU-side requirements of a created instance (Register/space indices,
/// pool sizes, descriptor-pool limits).  Complexity: O(1).
pub fn nrd_instance_info(inst: &NrdInstance) -> Result[NrdInstanceInfo, NrdError]
  requires: inst.raw != 0
{
  var slot = nrd_slot(64);
  let rc = unsafe { nrdb_instance_info(inst.lib, inst.raw, slot.as_mut_ptr(), 64) } as Int;
  if rc != 0 { return Err(NrdError{ kind: rc; message: nrd_result_name(rc) }); }
  return Ok(NrdInstanceInfo{
    cb_and_samplers_space: nrd_rd_u32(&slot, 0);
    resources_space: nrd_rd_u32(&slot, 4);
    cb_register: nrd_rd_u32(&slot, 8);
    samplers_base_register: nrd_rd_u32(&slot, 12);
    resources_base_register: nrd_rd_u32(&slot, 16);
    cb_max_data_size: nrd_rd_u32(&slot, 20);
    samplers_num: nrd_rd_u32(&slot, 24);
    pipelines_num: nrd_rd_u32(&slot, 28);
    permanent_pool_size: nrd_rd_u32(&slot, 32);
    transient_pool_size: nrd_rd_u32(&slot, 36);
    per_set_textures_max: nrd_rd_u32(&slot, 40);
    per_set_storage_max: nrd_rd_u32(&slot, 44);
    total_textures: nrd_rd_u32(&slot, 48);
    total_storage_textures: nrd_rd_u32(&slot, 52);
    sets_max: nrd_rd_u32(&slot, 56);
  });
}

/// The compute shader entry point name (the pinned build: "NRD_CS_MAIN").
/// Complexity: O(1).
pub fn nrd_instance_shader_entry(inst: &NrdInstance) -> Str
  requires: inst.raw != 0
{
  unsafe {
    var slot = nrd_slot(64);
    let rc = nrdb_instance_shader_entry(inst.lib, inst.raw, slot.as_mut_ptr(), 64) as Int;
    if rc <= 0 { return ""; }
    return Str::from_c_str(slot.as_ptr());
  }
}

// =========================================================================
// Instance lifecycle
// =========================================================================

/// An NRD instance: `raw` is the runtime-owned Instance pointer (opaque
/// Int; never dereferenced on the XIOM side -- B-20).  Destroy with
/// `nrd_destroy_instance`.
pub type NrdInstance = {
  lib: Int;
  raw: Int;
}

/// Create an instance with the requested denoisers.  `ids` and `kinds` are
/// u32 little-endian images (`nrd_u32_image`), same length, one entry per
/// denoiser.  Typed errors: NRD_RESULT_UNSUPPORTED (unknown denoiser kind),
/// NRD_RESULT_NON_UNIQUE_IDENTIFIER (duplicate identifier).
/// Complexity: O(denoisers).
pub fn nrd_create_instance(lib: &NrdLibrary, ids: &Vec[UInt8], kinds: &Vec[UInt8]) -> Result[NrdInstance, NrdError]
  requires: lib.h != 0
  requires: ids.len() > 0
  requires: ids.len() == kinds.len()
{
  var slot = nrd_slot(8);
  let rc = unsafe {
    nrdb_instance_create(lib.h, ids.as_ptr(), kinds.as_ptr(), (ids.len() / 4) as Int32, slot.as_mut_ptr())
  } as Int;
  if rc != 0 { return Err(NrdError{ kind: rc; message: nrd_result_name(rc) }); }
  let lo = nrd_rd_u32(&slot, 0) as Int;
  let hi = nrd_rd_u32(&slot, 4) as Int;
  let raw = lo | (hi << 32);
  if raw == 0 { return Err(NrdError{ kind: NRD_RESULT_FAILURE; message: "CreateInstance returned a null instance" }); }
  return Ok(NrdInstance{ lib: lib.h; raw: raw });
}

/// Destroy an instance.  Complexity: O(1).
pub fn nrd_destroy_instance(inst: &NrdInstance) -> Result[Unit, NrdError]
  requires: inst.raw != 0
{
  let rc = unsafe { nrdb_instance_destroy(inst.lib, inst.raw) } as Int;
  if rc == 0 { return Ok(()); }
  return Err(NrdError{ kind: rc; message: nrd_result_name(rc) });
}

// =========================================================================
// Settings images (owned structs)
// =========================================================================

/// An owned settings image: `data` is the ABI mirror (plus slack), filled
/// with the documented defaults for `kind`; offsets/sizes come from the
/// bridge's offsetof tables (single source of ABI truth).
pub type NrdImage = {
  kind: Int;
  size: Int;
  count: Int;
  data: Vec[UInt8];
  offsets: Vec[UInt8];
  sizes: Vec[UInt8];
}

/// Allocate a default-filled settings image for `kind`
/// (NRD_SETTINGS_COMMON..NRD_SETTINGS_REFERENCE).  Complexity: O(size).
pub fn nrd_image_default(kind: Int) -> Result[NrdImage, NrdError]
  requires: kind >= NRD_SETTINGS_COMMON
  requires: kind <= NRD_SETTINGS_REFERENCE
{
  let mirror = unsafe { nrdb_layout_size(kind as Int32) } as Int;
  if mirror <= 0 {
    return Err(NrdError{ kind: NRD_ERR_BAD_ARGS; message: "unknown settings kind" });
  }
  let fields = unsafe { nrdb_layout(kind as Int32, 0 as *UInt8, 0 as *UInt8, 0) } as Int;
  if fields < 0 {
    return Err(NrdError{ kind: NRD_ERR_BAD_ARGS; message: "unknown settings kind" });
  }
  var offsets = nrd_slot(fields * 4);
  var sizes = nrd_slot(fields * 4);
  let got = unsafe {
    nrdb_layout(kind as Int32, offsets.as_mut_ptr(), sizes.as_mut_ptr(), fields as Int32)
  } as Int;
  if got != fields {
    return Err(NrdError{ kind: NRD_ERR_BAD_ARGS; message: "layout table fetch failed" });
  }

  let total = mirror + NRD_SETTINGS_SLACK;
  var data = nrd_slot(total);
  var rc: Int = 0;
  if kind == NRD_SETTINGS_COMMON {
    rc = unsafe { nrdb_common_settings_default(data.as_mut_ptr(), total as Int32) } as Int;
  } else {
    rc = unsafe { nrdb_denoiser_settings_default(kind as Int32, data.as_mut_ptr(), total as Int32) } as Int;
  }
  if rc != 0 {
    return Err(NrdError{ kind: rc; message: nrd_result_name(rc) });
  }
  return Ok(NrdImage{ kind: kind; size: mirror; count: fields; data: data; offsets: offsets; sizes: sizes });
}

pub fn nrd_image_field_offset(img: &NrdImage, field: Int) -> Int
  requires: field >= 0
  requires: field < img.count
{
  return nrd_rd_u32(&img.offsets, field * 4);
}

pub fn nrd_image_field_size(img: &NrdImage, field: Int) -> Int
  requires: field >= 0
  requires: field < img.count
{
  return nrd_rd_u32(&img.sizes, field * 4);
}

pub fn nrd_image_set_u32(img: &mut NrdImage, field: Int, v: Int) -> Result[Unit, NrdError]
  requires: field >= 0
  requires: field < img.count
{
  let off = nrd_image_field_offset(img, field);
  let rc = unsafe { nrdb_img_set_u32(img.data.as_mut_ptr(), img.data.len() as Int32, off as Int32, v as Int32) } as Int;
  if rc != 0 { return Err(NrdError{ kind: rc; message: nrd_result_name(rc) }); }
  return Ok(());
}

pub fn nrd_image_set_u16(img: &mut NrdImage, field: Int, v: Int) -> Result[Unit, NrdError]
  requires: field >= 0
  requires: field < img.count
{
  let off = nrd_image_field_offset(img, field);
  let rc = unsafe { nrdb_img_set_u16(img.data.as_mut_ptr(), img.data.len() as Int32, off as Int32, v as Int32) } as Int;
  if rc != 0 { return Err(NrdError{ kind: rc; message: nrd_result_name(rc) }); }
  return Ok(());
}

pub fn nrd_image_set_u8(img: &mut NrdImage, field: Int, v: Int) -> Result[Unit, NrdError]
  requires: field >= 0
  requires: field < img.count
{
  let off = nrd_image_field_offset(img, field);
  let rc = unsafe { nrdb_img_set_u8(img.data.as_mut_ptr(), img.data.len() as Int32, off as Int32, v as Int32) } as Int;
  if rc != 0 { return Err(NrdError{ kind: rc; message: nrd_result_name(rc) }); }
  return Ok(());
}

pub fn nrd_image_set_f32(img: &mut NrdImage, field: Int, v: Float32) -> Result[Unit, NrdError]
  requires: field >= 0
  requires: field < img.count
{
  let off = nrd_image_field_offset(img, field);
  let rc = unsafe { nrdb_img_set_f32(img.data.as_mut_ptr(), img.data.len() as Int32, off as Int32, v) } as Int;
  if rc != 0 { return Err(NrdError{ kind: rc; message: nrd_result_name(rc) }); }
  return Ok(());
}

/// Set the i-th element of a scalar array field (f32).
pub fn nrd_image_set_f32_at(img: &mut NrdImage, field: Int, index: Int, v: Float32) -> Result[Unit, NrdError]
  requires: field >= 0
  requires: field < img.count
  requires: index >= 0
{
  let off = nrd_image_field_offset(img, field) + index * 4;
  let rc = unsafe { nrdb_img_set_f32(img.data.as_mut_ptr(), img.data.len() as Int32, off as Int32, v) } as Int;
  if rc != 0 { return Err(NrdError{ kind: rc; message: nrd_result_name(rc) }); }
  return Ok(());
}

pub fn nrd_image_set_u16_at(img: &mut NrdImage, field: Int, index: Int, v: Int) -> Result[Unit, NrdError]
  requires: field >= 0
  requires: field < img.count
  requires: index >= 0
{
  let off = nrd_image_field_offset(img, field) + index * 2;
  let rc = unsafe { nrdb_img_set_u16(img.data.as_mut_ptr(), img.data.len() as Int32, off as Int32, v as Int32) } as Int;
  if rc != 0 { return Err(NrdError{ kind: rc; message: nrd_result_name(rc) }); }
  return Ok(());
}

pub fn nrd_image_set_u32_at(img: &mut NrdImage, field: Int, index: Int, v: Int) -> Result[Unit, NrdError]
  requires: field >= 0
  requires: field < img.count
  requires: index >= 0
{
  let off = nrd_image_field_offset(img, field) + index * 4;
  let rc = unsafe { nrdb_img_set_u32(img.data.as_mut_ptr(), img.data.len() as Int32, off as Int32, v as Int32) } as Int;
  if rc != 0 { return Err(NrdError{ kind: rc; message: nrd_result_name(rc) }); }
  return Ok(());
}

pub fn nrd_image_get_u32(img: &NrdImage, field: Int) -> Int
  requires: field >= 0
  requires: field < img.count
{
  let off = nrd_image_field_offset(img, field);
  return unsafe { nrdb_img_get_u32(img.data.as_ptr(), img.data.len() as Int32, off as Int32) } as Int;
}

pub fn nrd_image_get_u16(img: &NrdImage, field: Int) -> Int
  requires: field >= 0
  requires: field < img.count
{
  let off = nrd_image_field_offset(img, field);
  return unsafe { nrdb_img_get_u16(img.data.as_ptr(), img.data.len() as Int32, off as Int32) } as Int;
}

pub fn nrd_image_get_u8(img: &NrdImage, field: Int) -> Int
  requires: field >= 0
  requires: field < img.count
{
  let off = nrd_image_field_offset(img, field);
  return unsafe { nrdb_img_get_u8(img.data.as_ptr(), img.data.len() as Int32, off as Int32) } as Int;
}

pub fn nrd_image_get_f32(img: &NrdImage, field: Int) -> Float32
  requires: field >= 0
  requires: field < img.count
{
  let off = nrd_image_field_offset(img, field);
  return unsafe { nrdb_img_get_f32(img.data.as_ptr(), img.data.len() as Int32, off as Int32) };
}

/// Convenience: a default-filled common-settings image with the mandatory
/// size fields set for `width`x`height` (resourceSize/rectSize = size,
/// their Prev copies = size, frameIndex = 0, accumulation = CLEAR_AND_RESTART).
/// Complexity: O(size).
pub fn nrd_common_settings_for_frame(width: Int, height: Int) -> Result[NrdImage, NrdError]
  requires: width > 0 && width <= 65535
  requires: height > 0 && height <= 65535
{
  var img = nrd_image_default(NRD_SETTINGS_COMMON);
  if img.is_err { return Err(img.error); }
  var i = img.value;
  let rc0 = nrd_image_set_u16_at(&mut i, NRD_CS_RESOURCE_SIZE, 0, width);
  if rc0.is_err { return Err(rc0.error); }
  let rc1 = nrd_image_set_u16_at(&mut i, NRD_CS_RESOURCE_SIZE, 1, height);
  if rc1.is_err { return Err(rc1.error); }
  let rc2 = nrd_image_set_u16_at(&mut i, NRD_CS_RESOURCE_SIZE_PREV, 0, width);
  if rc2.is_err { return Err(rc2.error); }
  let rc3 = nrd_image_set_u16_at(&mut i, NRD_CS_RESOURCE_SIZE_PREV, 1, height);
  if rc3.is_err { return Err(rc3.error); }
  let rc4 = nrd_image_set_u16_at(&mut i, NRD_CS_RECT_SIZE, 0, width);
  if rc4.is_err { return Err(rc4.error); }
  let rc5 = nrd_image_set_u16_at(&mut i, NRD_CS_RECT_SIZE, 1, height);
  if rc5.is_err { return Err(rc5.error); }
  let rc6 = nrd_image_set_u16_at(&mut i, NRD_CS_RECT_SIZE_PREV, 0, width);
  if rc6.is_err { return Err(rc6.error); }
  let rc7 = nrd_image_set_u16_at(&mut i, NRD_CS_RECT_SIZE_PREV, 1, height);
  if rc7.is_err { return Err(rc7.error); }
  let rc8 = nrd_image_set_u32(&mut i, NRD_CS_FRAME_INDEX, 0);
  if rc8.is_err { return Err(rc8.error); }
  let rc9 = nrd_image_set_u8(&mut i, NRD_CS_ACCUMULATION_MODE, NRD_ACCUMULATION_CLEAR_AND_RESTART);
  if rc9.is_err { return Err(rc9.error); }
  return Ok(i);
}

// =========================================================================
// Settings plumbing
// =========================================================================

/// Apply CommonSettings to the instance.  The runtime copies from the owned
/// image.  Typed error NRD_RESULT_INVALID_ARGUMENT on invalid settings
/// (e.g. zero sizes, out-of-range jitter).
/// Complexity: O(1).
pub fn nrd_set_common_settings(inst: &NrdInstance, img: &NrdImage) -> Result[Unit, NrdError]
  requires: inst.raw != 0
  requires: img.kind == NRD_SETTINGS_COMMON
{
  let rc = unsafe {
    nrdb_set_common_settings(inst.lib, inst.raw, img.data.as_ptr(), img.size as Int32)
  } as Int;
  if rc != 0 { return Err(NrdError{ kind: rc; message: nrd_result_name(rc) }); }
  return Ok(());
}

/// Apply per-denoiser settings.  Typed error NRD_RESULT_INVALID_ARGUMENT
/// when `identifier` does not belong to the instance.
/// Complexity: O(1).
pub fn nrd_set_denoiser_settings(inst: &NrdInstance, identifier: Int, img: &NrdImage) -> Result[Unit, NrdError]
  requires: inst.raw != 0
  requires: img.kind != NRD_SETTINGS_COMMON
{
  let rc = unsafe {
    nrdb_set_denoiser_settings(inst.lib, inst.raw, identifier as Int32, img.data.as_ptr(), img.size as Int32)
  } as Int;
  if rc != 0 { return Err(NrdError{ kind: rc; message: nrd_result_name(rc) }); }
  return Ok(());
}

// =========================================================================
// Dispatch plan (GetComputeDispatches)
// =========================================================================

/// The computed dispatch plan for a set of identifiers: every dispatch's
/// scalars, its resource list and its constant buffer, copied into owned
/// slots (the runtime's memory is overwritten by its next call).
pub type NrdPlan = {
  count: Int;
  resources_total: Int;
  constants_total: Int;
  max_resources: Int;
  summaries: Vec[UInt8];
  resources: Vec[UInt8];
  constants: Vec[UInt8];
}

/// Compute the dispatch plan for `ids` (u32 LE image of identifiers).
/// Complexity: O(dispatches) plus the copy.
pub fn nrd_dispatch_plan(inst: &NrdInstance, ids: &Vec[UInt8]) -> Result[NrdPlan, NrdError]
  requires: inst.raw != 0
  requires: ids.len() > 0
{
  var counts = nrd_slot(16);
  let rc = unsafe {
    nrdb_plan_counts(inst.lib, inst.raw, ids.as_ptr(), (ids.len() / 4) as Int32, counts.as_mut_ptr())
  } as Int;
  if rc != 0 { return Err(NrdError{ kind: rc; message: nrd_result_name(rc) }); }

  let count = nrd_rd_u32(&counts, 0);
  let res_total = nrd_rd_u32(&counts, 4);
  let cb_total = nrd_rd_u32(&counts, 8);
  let max_res = nrd_rd_u32(&counts, 12);
  if count == 0 { return Err(NrdError{ kind: NRD_RESULT_INVALID_ARGUMENT; message: "plan has no dispatches" }); }

  var summaries = nrd_slot(count * NRD_PLAN_SUMMARY_SIZE);
  var resources = nrd_slot(1 + res_total * NRD_PLAN_RES_REC_SIZE);
  var constants = nrd_slot(1 + cb_total);
  let rc2 = unsafe {
    nrdb_plan_copy(
      inst.lib, inst.raw, ids.as_ptr(), (ids.len() / 4) as Int32,
      summaries.as_mut_ptr(), (count) as Int32,
      resources.as_mut_ptr(), (res_total) as Int32,
      constants.as_mut_ptr(), (cb_total) as Int32,
      counts.as_mut_ptr())
  } as Int;
  if rc2 != 0 { return Err(NrdError{ kind: rc2; message: nrd_result_name(rc2) }); }

  return Ok(NrdPlan{
    count: count;
    resources_total: res_total;
    constants_total: cb_total;
    max_resources: max_res;
    summaries: summaries;
    resources: resources;
    constants: constants;
  });
}

pub fn nrd_plan_dispatch_identifier(plan: &NrdPlan, i: Int) -> Int
  requires: i >= 0
  requires: i < plan.count
{
  return nrd_rd_u32(&plan.summaries, i * NRD_PLAN_SUMMARY_SIZE + NRD_PS_IDENTIFIER);
}

pub fn nrd_plan_dispatch_pipeline(plan: &NrdPlan, i: Int) -> Int
  requires: i >= 0
  requires: i < plan.count
{
  return nrd_rd_u32(&plan.summaries, i * NRD_PLAN_SUMMARY_SIZE + NRD_PS_PIPELINE_INDEX);
}

pub fn nrd_plan_dispatch_grid_width(plan: &NrdPlan, i: Int) -> Int
  requires: i >= 0
  requires: i < plan.count
{
  return nrd_rd_u32(&plan.summaries, i * NRD_PLAN_SUMMARY_SIZE + NRD_PS_GRID_WIDTH);
}

pub fn nrd_plan_dispatch_grid_height(plan: &NrdPlan, i: Int) -> Int
  requires: i >= 0
  requires: i < plan.count
{
  return nrd_rd_u32(&plan.summaries, i * NRD_PLAN_SUMMARY_SIZE + NRD_PS_GRID_HEIGHT);
}

pub fn nrd_plan_dispatch_resources_num(plan: &NrdPlan, i: Int) -> Int
  requires: i >= 0
  requires: i < plan.count
{
  return nrd_rd_u32(&plan.summaries, i * NRD_PLAN_SUMMARY_SIZE + NRD_PS_RESOURCES_NUM);
}

pub fn nrd_plan_dispatch_cb_size(plan: &NrdPlan, i: Int) -> Int
  requires: i >= 0
  requires: i < plan.count
{
  return nrd_rd_u32(&plan.summaries, i * NRD_PLAN_SUMMARY_SIZE + NRD_PS_CB_SIZE);
}

pub fn nrd_plan_dispatch_matches_previous(plan: &NrdPlan, i: Int) -> Bool
  requires: i >= 0
  requires: i < plan.count
{
  return (nrd_rd_u32(&plan.summaries, i * NRD_PLAN_SUMMARY_SIZE + NRD_PS_FLAGS) & 1) != 0;
}

/// Dispatch name (e.g. "Clear", "REBLUR_TemporalAccumulation"); empty when
/// the runtime left it null.  Complexity: O(name).
pub fn nrd_plan_dispatch_name(plan: &NrdPlan, i: Int) -> Str
  requires: i >= 0
  requires: i < plan.count
{
  unsafe {
    var slot = nrd_slot(64);
    let rc = nrdb_plan_dispatch_name(plan.summaries.as_ptr(), plan.count as Int32, i as Int32, slot.as_mut_ptr(), 64) as Int;
    if rc <= 0 { return ""; }
    return Str::from_c_str(slot.as_ptr());
  }
}

fn nrd_plan_dispatch_res_offset(plan: &NrdPlan, i: Int) -> Int
  requires: i >= 0
  requires: i < plan.count
{
  return nrd_rd_u32(&plan.summaries, i * NRD_PLAN_SUMMARY_SIZE + NRD_PS_RES_OFFSET);
}

fn nrd_plan_dispatch_cb_offset(plan: &NrdPlan, i: Int) -> Int
  requires: i >= 0
  requires: i < plan.count
{
  return nrd_rd_u32(&plan.summaries, i * NRD_PLAN_SUMMARY_SIZE + NRD_PS_CB_OFFSET);
}

/// Resource record fields of dispatch `i`, resource `j`.
/// Complexity: O(1).
pub fn nrd_plan_resource_descriptor_type(plan: &NrdPlan, i: Int, j: Int) -> Int
  requires: i >= 0
  requires: i < plan.count
  requires: j >= 0
  requires: j < nrd_plan_dispatch_resources_num(plan, i)
{
  let rec = nrd_plan_dispatch_res_offset(plan, i) + j;
  return nrd_rd_u32(&plan.resources, rec * NRD_PLAN_RES_REC_SIZE + NRD_RR_DESCRIPTOR_TYPE);
}

pub fn nrd_plan_resource_type(plan: &NrdPlan, i: Int, j: Int) -> Int
  requires: i >= 0
  requires: i < plan.count
  requires: j >= 0
  requires: j < nrd_plan_dispatch_resources_num(plan, i)
{
  let rec = nrd_plan_dispatch_res_offset(plan, i) + j;
  return nrd_rd_u32(&plan.resources, rec * NRD_PLAN_RES_REC_SIZE + NRD_RR_TYPE);
}

pub fn nrd_plan_resource_index_in_pool(plan: &NrdPlan, i: Int, j: Int) -> Int
  requires: i >= 0
  requires: i < plan.count
  requires: j >= 0
  requires: j < nrd_plan_dispatch_resources_num(plan, i)
{
  let rec = nrd_plan_dispatch_res_offset(plan, i) + j;
  return nrd_rd_u32(&plan.resources, rec * NRD_PLAN_RES_REC_SIZE + NRD_RR_INDEX_IN_POOL);
}

/// Number of dispatches belonging to one identifier.  Complexity: O(count).
pub fn nrd_plan_count_for(plan: &NrdPlan, identifier: Int) -> Int
  requires: identifier >= 0
{
  var n = 0;
  var i = 0;
  while i < plan.count {
    if nrd_plan_dispatch_identifier(plan, i) == identifier { n = n + 1; }
    i = i + 1;
  }
  return n;
}

/// Does any dispatch of `identifier` reference `resource_type`?
/// Complexity: O(count * resources).
pub fn nrd_plan_uses_resource(plan: &NrdPlan, identifier: Int, resource_type: Int) -> Bool
  requires: identifier >= 0
  requires: resource_type >= 0
{
  var i = 0;
  while i < plan.count {
    if nrd_plan_dispatch_identifier(plan, i) == identifier {
      let rn = nrd_plan_dispatch_resources_num(plan, i);
      var j = 0;
      while j < rn {
        if nrd_plan_resource_type(plan, i, j) == resource_type { return true; }
        j = j + 1;
      }
    }
    i = i + 1;
  }
  return false;
}

/// Byte-exact comparison of two plans' constant-buffer blobs.
/// Complexity: O(constants).
pub fn nrd_plan_constants_equal(a: &NrdPlan, b: &NrdPlan) -> Bool
  requires: true
{
  if a.constants_total != b.constants_total { return false; }
  var i = 0;
  while i < a.constants_total {
    if a.constants[i] != b.constants[i] { return false; }
    i = i + 1;
  }
  return true;
}

/// CPU-side pre-execution validation of a plan (the app-side "execute"
/// precheck): result 0 = valid, otherwise the first failing code.
/// Complexity: O(dispatches * resources).
pub fn nrd_plan_validate(plan: &NrdPlan) -> Int
  requires: true
{
  if plan.count <= 0 { return 1; }
  if plan.summaries.len() < plan.count * NRD_PLAN_SUMMARY_SIZE { return 2; }
  if plan.resources.len() < plan.resources_total * NRD_PLAN_RES_REC_SIZE { return 3; }
  if plan.constants.len() < plan.constants_total { return 4; }

  var i = 0;
  while i < plan.count {
    if nrd_plan_dispatch_grid_width(plan, i) <= 0 { return 5; }
    if nrd_plan_dispatch_grid_height(plan, i) <= 0 { return 6; }
    let rn = nrd_plan_dispatch_resources_num(plan, i);
    if rn <= 0 { return 7; }
    if nrd_plan_dispatch_res_offset(plan, i) + rn > plan.resources_total { return 8; }
    if nrd_plan_dispatch_cb_offset(plan, i) + nrd_plan_dispatch_cb_size(plan, i) > plan.constants_total { return 9; }
    var j = 0;
    while j < rn {
      if nrd_plan_resource_descriptor_type(plan, i, j) >= NRD_DESCRIPTOR_TYPE_MAX_NUM { return 10; }
      if nrd_plan_resource_type(plan, i, j) >= NRD_RESOURCE_TYPE_MAX_NUM { return 11; }
      // NOTE: pool entries (TRANSIENT_POOL/PERMANENT_POOL) may be referenced
      // as TEXTURE (SRV reads of history) or STORAGE_TEXTURE (UAV writes);
      // both are legitimate in runtime plans (observed on the pinned build),
      // so the descriptor type only has to be in range here.
      j = j + 1;
    }
    i = i + 1;
  }
  return 0;
}

// =========================================================================
// Name tables and execution classification
// =========================================================================

/// GetResourceTypeString as the runtime reports it (owned slot copy).
/// Empty string when the runtime returns null.  Complexity: O(name).
pub fn nrd_resource_string(lib: &NrdLibrary, resource_type: Int) -> Str
  requires: lib.h != 0
  requires: resource_type >= 0
{
  unsafe {
    var slot = nrd_slot(64);
    let rc = nrdb_get_resource_string(lib.h, resource_type as Int32, slot.as_mut_ptr(), 64) as Int;
    if rc <= 0 { return ""; }
    return Str::from_c_str(slot.as_ptr());
  }
}

/// GetDenoiserString as the runtime reports it (owned slot copy).
/// Empty string when the runtime returns null.  Complexity: O(name).
pub fn nrd_denoiser_string(lib: &NrdLibrary, denoiser: Int) -> Str
  requires: lib.h != 0
  requires: denoiser >= 0
{
  unsafe {
    var slot = nrd_slot(64);
    let rc = nrdb_get_denoiser_string(lib.h, denoiser as Int32, slot.as_mut_ptr(), 64) as Int;
    if rc <= 0 { return ""; }
    return Str::from_c_str(slot.as_ptr());
  }
}

/// Execute a validated plan.  Requires an application-owned GPU device
/// bridge (D3D12/VK): out of scope for 0.1.0, so this returns
/// NRD_EXEC_NO_DEVICE (typed SKIP) for a valid plan and NRD_EXEC_INVALID
/// for bad arguments -- never a silent success.  Complexity: O(1).
pub fn nrd_execute(inst: &NrdInstance, plan: &NrdPlan) -> Int
  requires: true
{
  if inst.raw == 0 || plan.count <= 0 || plan.summaries.len() == 0 { return NRD_EXEC_INVALID; }
  return unsafe { nrdb_execute(inst.lib, inst.raw, plan.summaries.as_ptr(), plan.count as Int32) } as Int;
}
