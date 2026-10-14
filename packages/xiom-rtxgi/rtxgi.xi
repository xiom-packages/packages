// XIOM -- xiom.rtxgi: NVIDIA RTXGI-DDGI integration surface.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// DECISION (BINDINGS lane 2026-10-14): the upstream was expected to be MIT;
// verification in the clone found **NOT MIT** -- both the RTXGI-DDGI v1.x
// repository (the DDGI SDK) and the NVIDIAGameWorks/RTXGI v2.x repository
// (NRC/SHaRC samples; it does NOT contain DDGI) ship the proprietary
// "NVIDIA RTX SDKs LICENSE" (License.txt / License.md at the pins; clauses
// 4(b)/4(e) forbid source redistribution and any open-source-license
// application).  Vendoring is therefore NOT allowed and this package follows
// the NRD/FFmpeg precedent (docs/BINDINGS-LANE.md sec. 4/11; docs/
// UPSTREAM-FIRST.md sec. 2): **reference-only, dynamic loader only** --
// independent XIOM code written against the public header declarations (the
// "declaration oracle", PROVENANCE.md) plus an XIOM-side bridge
// (src/rtxgi_bridge.cpp, ours) that resolution-loads a locally built shim
// module (the licensee's own build around the pinned SDK; see PROVENANCE.md).
// No RTXGI code, headers, shader blobs, or binaries ship in this repository.
//
// DECLARED surface (100% of the DDGI v1.3.7 public integration API, bound
// through the loader and exercised by the suite):
//   * identity/classification + ERTXGIStatus (86 values);
//   * DDGIVolumeDesc (38 fields, owned-image plumbing) + defaults;
//   * GetDDGIVolumeProbeCounts / GetDDGIVolumeTextureDimensions;
//   * GetDDGIVolumeNumRTVDescriptors / ...Tex2DArrayDescriptors /
//     ...ResourceDescriptors;
//   * ValidateShaderBytecode + SetInsertPerfMarkers/bInsertPerfMarkers;
//   * DDGIVolumeBase lifecycle: Update (RNG rotation + scrolling), SeedRNG,
//     GetRandomFloat, Set/Get origin, scroll anchor, movement type,
//     hysteresis, euler angles, Destroy;
//   * GetDescGPU / GetDescGPUPacked (packed constants) + DDGIRootConstants
//     and DDGIVolumeResourceIndices layout anchors;
//   * GetNumProbes / GetNumRaysPerProbe / GetTexture2DArraySize /
//     GetRayDispatchDimensions / GetGPUMemoryUsedInBytes;
//   * GetProbeWorldPosition / GetAxisAlignedBoundingBox / GetOrientedBoundingBox.
//
// v0.64.4 FFI discipline (findings B-20/B-21/B-23/B-24/B-25/B-26):
//   * handles cross as `Int` params (B-25: no pointer casts from integers);
//   * every out-param is one XIOM-owned Vec[UInt8] slot, read byte-indexed
//     (B-17/B-24); XIOM never reads shim-owned memory (B-20);
//   * desc/packed images are owned XIOM bytes; layout offsets come from the
//     bridge's offsetof tables -- one single source of ABI truth -- and the
//     suite cross-checks them against the shim's real structs;
//   * nullable C args never receive the bare `null` literal (B-23);
//   * flat outcome structs only, never `Result[Option[T]]` (B-26).
//
// GPU execution: the DDGI ray-trace/blend/relocate passes require the
// application's D3D12/VK device, probe textures, descriptor heaps and the
// compiled shader bytecode.  That path is out of scope for 0.1.0 and
// `rtxgi_execute` returns the typed RTXGI_EXEC_NO_DEVICE classification
// (SKIP), never a silent success.  The CPU-side surface above is fully
// exercised headlessly (no device needed).

module xiom.rtxgi

use xiom.convert;

// =========================================================================
// Identity / classification
// =========================================================================

/// Pinned upstream (PROVENANCE.md declaration oracle).
pub const RTXGI_VERSION_MAJOR: Int = 1;
pub const RTXGI_VERSION_MINOR: Int = 3;
pub const RTXGI_VERSION_REVISION: Int = 7;

/// Coordinate system constants (Defines.h); the shim is built with the SDK
/// CMake default "Right Hand, Y-Up" = 2.
pub const RTXGI_COORDINATE_SYSTEM_LEFT_Y_UP: Int = 0;
pub const RTXGI_COORDINATE_SYSTEM_LEFT_Z_UP: Int = 1;
pub const RTXGI_COORDINATE_SYSTEM_RIGHT_Y_UP: Int = 2;
pub const RTXGI_COORDINATE_SYSTEM_RIGHT_Z_UP: Int = 3;

/// Load classification (mirrors the FFmpeg/NRD loader model).
pub const RTXGI_LOAD_ABSENT: Int = 0; // no shim module -> SKIP
pub const RTXGI_LOAD_ABI: Int = 1;    // module loaded but entry points missing -> FAIL
pub const RTXGI_LOAD_OK: Int = 2;

/// Bridge status codes (src/rtxgi_bridge.cpp).
pub const RTXGI_ERR_NOT_LOADED: Int = 100;
pub const RTXGI_ERR_BAD_ARGS: Int = 101;
pub const RTXGI_ERR_SIZE: Int = 102;
pub const RTXGI_ERR_CAPACITY: Int = 103;

/// Execute-path classification (device owner is the application).
pub const RTXGI_EXEC_OK: Int = 0;
pub const RTXGI_EXEC_INVALID: Int = 1;
pub const RTXGI_EXEC_NO_DEVICE: Int = 2; // typed SKIP when no device bridge

/// Documented descriptor-heap demands of one DDGIVolume (SDK constants at
/// the pinned commit; the shim is cross-checked against them at run time).
pub const RTXGI_NUM_RTV_DESCRIPTORS: Int = 2;
pub const RTXGI_NUM_TEX2DARRAY_DESCRIPTORS: Int = 6;
pub const RTXGI_NUM_RESOURCE_DESCRIPTORS: Int = 12;

/// DDGIRootConstants layout (DDGIRootConstants.h).
pub const RTXGI_ROOT_CONSTANTS_NUM_WORDS: Int = 6;
pub const RTXGI_ROOT_CONSTANTS_SIZE: Int = 24;
pub const RTXGI_ROOT_CONSTANTS_ALIGNED_WORDS: Int = 8;
pub const RTXGI_ROOT_CONSTANTS_ALIGNED_SIZE: Int = 32;

// =========================================================================
// ERTXGIStatus (Common.h @ v1.3.7; 86 values: OK + 85 codes)
// =========================================================================

pub const RTXGI_STATUS_OK: Int = 0;
pub const RTXGI_STATUS_ERROR_DDGI_INVALID_PROBE_COUNTS: Int = 1;
pub const RTXGI_STATUS_ERROR_DDGI_INVALID_RESOURCE_INDICES_BUFFER: Int = 2;
pub const RTXGI_STATUS_ERROR_DDGI_INVALID_RESOURCE_INDICES_UPLOAD_BUFFER: Int = 3;
pub const RTXGI_STATUS_ERROR_DDGI_INVALID_CONSTANTS_BUFFER: Int = 4;
pub const RTXGI_STATUS_ERROR_DDGI_INVALID_CONSTANTS_UPLOAD_BUFFER: Int = 5;
pub const RTXGI_STATUS_ERROR_DDGI_INVALID_RESOURCES_DESC: Int = 6;
pub const RTXGI_STATUS_ERROR_DDGI_MAP_FAILURE_RESOURCE_INDICES_UPLOAD_BUFFER: Int = 7;
pub const RTXGI_STATUS_ERROR_DDGI_MAP_FAILURE_CONSTANTS_UPLOAD_BUFFER: Int = 8;
pub const RTXGI_STATUS_ERROR_DDGI_MAP_FAILURE_VARIABILITY_READBACK_BUFFER: Int = 9;
pub const RTXGI_STATUS_ERROR_DDGI_D3D12_INVALID_RESOURCE_DESCRIPTOR_HEAP: Int = 10;
pub const RTXGI_STATUS_ERROR_DDGI_VK_INVALID_RESOURCE_INDICES_UPLOAD_MEMORY: Int = 11;
pub const RTXGI_STATUS_ERROR_DDGI_VK_INVALID_CONSTANTS_UPLOAD_MEMORY: Int = 12;
pub const RTXGI_STATUS_ERROR_DDGI_INVALID_BYTECODE_PROBE_BLENDING_IRRADIANCE: Int = 13;
pub const RTXGI_STATUS_ERROR_DDGI_INVALID_BYTECODE_PROBE_BLENDING_DISTANCE: Int = 14;
pub const RTXGI_STATUS_ERROR_DDGI_INVALID_BYTECODE_PROBE_RELOCATION: Int = 15;
pub const RTXGI_STATUS_ERROR_DDGI_INVALID_BYTECODE_PROBE_RELOCATION_RESET: Int = 16;
pub const RTXGI_STATUS_ERROR_DDGI_INVALID_BYTECODE_PROBE_CLASSIFICATION: Int = 17;
pub const RTXGI_STATUS_ERROR_DDGI_INVALID_BYTECODE_PROBE_CLASSIFICATION_RESET: Int = 18;
pub const RTXGI_STATUS_ERROR_DDGI_INVALID_BYTECODE_PROBE_VARIABILITY_REDUCTION: Int = 19;
pub const RTXGI_STATUS_ERROR_DDGI_INVALID_BYTECODE_PROBE_VARIABILITY_EXTRA_REDUCTION: Int = 20;
pub const RTXGI_STATUS_ERROR_DDGI_ALLOCATE_FAILURE_TEXTURE_PROBE_RAY_DATA: Int = 21;
pub const RTXGI_STATUS_ERROR_DDGI_ALLOCATE_FAILURE_TEXTURE_PROBE_IRRADIANCE: Int = 22;
pub const RTXGI_STATUS_ERROR_DDGI_ALLOCATE_FAILURE_TEXTURE_PROBE_DISTANCE: Int = 23;
pub const RTXGI_STATUS_ERROR_DDGI_ALLOCATE_FAILURE_TEXTURE_PROBE_DATA: Int = 24;
pub const RTXGI_STATUS_ERROR_DDGI_ALLOCATE_FAILURE_TEXTURE_PROBE_VARIABILITY: Int = 25;
pub const RTXGI_STATUS_ERROR_DDGI_ALLOCATE_FAILURE_TEXTURE_PROBE_VARIABILITY_AVERAGE: Int = 26;
pub const RTXGI_STATUS_ERROR_DDGI_D3D12_INVALID_DEVICE: Int = 27;
pub const RTXGI_STATUS_ERROR_DDGI_D3D12_CREATE_FAILURE_PSO: Int = 28;
pub const RTXGI_STATUS_ERROR_DDGI_D3D12_CREATE_FAILURE_ROOT_SIGNATURE: Int = 29;
pub const RTXGI_STATUS_ERROR_DDGI_D3D12_CREATE_FAILURE_DESCRIPTORS: Int = 30;
pub const RTXGI_STATUS_ERROR_DDGI_VK_INVALID_DEVICE: Int = 31;
pub const RTXGI_STATUS_ERROR_DDGI_VK_INVALID_PHYSICAL_DEVICE: Int = 32;
pub const RTXGI_STATUS_ERROR_DDGI_VK_INVALID_DESCRIPTOR_POOL: Int = 33;
pub const RTXGI_STATUS_ERROR_DDGI_VK_CREATE_FAILURE_LAYOUTS: Int = 34;
pub const RTXGI_STATUS_ERROR_DDGI_VK_CREATE_FAILURE_PIPELINE: Int = 35;
pub const RTXGI_STATUS_ERROR_DDGI_VK_CREATE_FAILURE_DESCRIPTOR_SET: Int = 36;
pub const RTXGI_STATUS_ERROR_DDGI_INVALID_TEXTURE_PROBE_RAY_DATA: Int = 37;
pub const RTXGI_STATUS_ERROR_DDGI_INVALID_TEXTURE_PROBE_IRRADIANCE: Int = 38;
pub const RTXGI_STATUS_ERROR_DDGI_INVALID_TEXTURE_PROBE_DISTANCE: Int = 39;
pub const RTXGI_STATUS_ERROR_DDGI_INVALID_TEXTURE_PROBE_DATA: Int = 40;
pub const RTXGI_STATUS_ERROR_DDGI_INVALID_TEXTURE_PROBE_VARIABILITY: Int = 41;
pub const RTXGI_STATUS_ERROR_DDGI_INVALID_TEXTURE_PROBE_VARIABILITY_AVERAGE: Int = 42;
pub const RTXGI_STATUS_ERROR_DDGI_INVALID_TEXTURE_PROBE_VARIABILITY_READBACK: Int = 43;
pub const RTXGI_STATUS_ERROR_DDGI_D3D12_INVALID_ROOT_SIGNATURE: Int = 44;
pub const RTXGI_STATUS_ERROR_DDGI_D3D12_INVALID_DESCRIPTOR: Int = 45;
pub const RTXGI_STATUS_ERROR_DDGI_D3D12_INVALID_PSO_PROBE_BLENDING_IRRADIANCE: Int = 46;
pub const RTXGI_STATUS_ERROR_DDGI_D3D12_INVALID_PSO_PROBE_BLENDING_DISTANCE: Int = 47;
pub const RTXGI_STATUS_ERROR_DDGI_D3D12_INVALID_PSO_PROBE_RELOCATION: Int = 48;
pub const RTXGI_STATUS_ERROR_DDGI_D3D12_INVALID_PSO_PROBE_RELOCATION_RESET: Int = 49;
pub const RTXGI_STATUS_ERROR_DDGI_D3D12_INVALID_PSO_PROBE_CLASSIFICATION: Int = 50;
pub const RTXGI_STATUS_ERROR_DDGI_D3D12_INVALID_PSO_PROBE_CLASSIFICATION_RESET: Int = 51;
pub const RTXGI_STATUS_ERROR_DDGI_D3D12_INVALID_PSO_PROBE_REDUCTION: Int = 52;
pub const RTXGI_STATUS_ERROR_DDGI_D3D12_INVALID_PSO_PROBE_EXTRA_REDUCTION: Int = 53;
pub const RTXGI_STATUS_ERROR_DDGI_VK_INVALID_DESCRIPTOR_SET: Int = 54;
pub const RTXGI_STATUS_ERROR_DDGI_VK_INVALID_PIPELINE_LAYOUT: Int = 55;
pub const RTXGI_STATUS_ERROR_DDGI_VK_INVALID_IMAGE_MEMORY_PROBE_RAY_DATA: Int = 56;
pub const RTXGI_STATUS_ERROR_DDGI_VK_INVALID_IMAGE_MEMORY_PROBE_IRRADIANCE: Int = 57;
pub const RTXGI_STATUS_ERROR_DDGI_VK_INVALID_IMAGE_MEMORY_PROBE_DISTANCE: Int = 58;
pub const RTXGI_STATUS_ERROR_DDGI_VK_INVALID_IMAGE_MEMORY_PROBE_DATA: Int = 59;
pub const RTXGI_STATUS_ERROR_DDGI_VK_INVALID_IMAGE_MEMORY_PROBE_VARIABILITY: Int = 60;
pub const RTXGI_STATUS_ERROR_DDGI_VK_INVALID_IMAGE_MEMORY_PROBE_VARIABILITY_AVERAGE: Int = 61;
pub const RTXGI_STATUS_ERROR_DDGI_VK_INVALID_IMAGE_MEMORY_PROBE_VARIABILITY_READBACK: Int = 62;
pub const RTXGI_STATUS_ERROR_DDGI_VK_INVALID_IMAGE_VIEW_PROBE_RAY_DATA: Int = 63;
pub const RTXGI_STATUS_ERROR_DDGI_VK_INVALID_IMAGE_VIEW_PROBE_IRRADIANCE: Int = 64;
pub const RTXGI_STATUS_ERROR_DDGI_VK_INVALID_IMAGE_VIEW_PROBE_DISTANCE: Int = 65;
pub const RTXGI_STATUS_ERROR_DDGI_VK_INVALID_IMAGE_VIEW_PROBE_DATA: Int = 66;
pub const RTXGI_STATUS_ERROR_DDGI_VK_INVALID_IMAGE_VIEW_PROBE_VARIABILITY: Int = 67;
pub const RTXGI_STATUS_ERROR_DDGI_VK_INVALID_IMAGE_VIEW_PROBE_VARIABILITY_AVERAGE: Int = 68;
pub const RTXGI_STATUS_ERROR_DDGI_VK_INVALID_IMAGE_VIEW_PROBE_VARIABILITY_READBACK: Int = 69;
pub const RTXGI_STATUS_ERROR_DDGI_VK_INVALID_SHADER_MODULE_PROBE_BLENDING_IRRADIANCE: Int = 70;
pub const RTXGI_STATUS_ERROR_DDGI_VK_INVALID_SHADER_MODULE_PROBE_BLENDING_DISTANCE: Int = 71;
pub const RTXGI_STATUS_ERROR_DDGI_VK_INVALID_SHADER_MODULE_PROBE_RELOCATION: Int = 72;
pub const RTXGI_STATUS_ERROR_DDGI_VK_INVALID_SHADER_MODULE_PROBE_RELOCATION_RESET: Int = 73;
pub const RTXGI_STATUS_ERROR_DDGI_VK_INVALID_SHADER_MODULE_PROBE_CLASSIFICATION: Int = 74;
pub const RTXGI_STATUS_ERROR_DDGI_VK_INVALID_SHADER_MODULE_PROBE_CLASSIFICATION_RESET: Int = 75;
pub const RTXGI_STATUS_ERROR_DDGI_VK_INVALID_SHADER_MODULE_PROBE_VARIABILITY_REDUCTION: Int = 76;
pub const RTXGI_STATUS_ERROR_DDGI_VK_INVALID_SHADER_MODULE_PROBE_VARIABILITY_EXTRA_REDUCTION: Int = 77;
pub const RTXGI_STATUS_ERROR_DDGI_VK_INVALID_PIPELINE_PROBE_BLENDING_IRRADIANCE: Int = 78;
pub const RTXGI_STATUS_ERROR_DDGI_VK_INVALID_PIPELINE_PROBE_BLENDING_DISTANCE: Int = 79;
pub const RTXGI_STATUS_ERROR_DDGI_VK_INVALID_PIPELINE_PROBE_RELOCATION: Int = 80;
pub const RTXGI_STATUS_ERROR_DDGI_VK_INVALID_PIPELINE_PROBE_RELOCATION_RESET: Int = 81;
pub const RTXGI_STATUS_ERROR_DDGI_VK_INVALID_PIPELINE_PROBE_CLASSIFICATION: Int = 82;
pub const RTXGI_STATUS_ERROR_DDGI_VK_INVALID_PIPELINE_PROBE_CLASSIFICATION_RESET: Int = 83;
pub const RTXGI_STATUS_ERROR_DDGI_VK_INVALID_PIPELINE_PROBE_VARIABILITY_REDUCTION: Int = 84;
pub const RTXGI_STATUS_ERROR_DDGI_VK_INVALID_PIPELINE_PROBE_VARIABILITY_EXTRA_REDUCTION: Int = 85;
pub const RTXGI_STATUS_COUNT: Int = 86;

// =========================================================================
// Public enums (DDGIVolume.h @ v1.3.7)
// =========================================================================

// EDDGIVolumeTextureType
pub const RTXGI_TEXTURE_TYPE_RAY_DATA: Int = 0;
pub const RTXGI_TEXTURE_TYPE_IRRADIANCE: Int = 1;
pub const RTXGI_TEXTURE_TYPE_DISTANCE: Int = 2;
pub const RTXGI_TEXTURE_TYPE_DATA: Int = 3;
pub const RTXGI_TEXTURE_TYPE_VARIABILITY: Int = 4;
pub const RTXGI_TEXTURE_TYPE_VARIABILITY_AVERAGE: Int = 5;
pub const RTXGI_TEXTURE_TYPE_COUNT: Int = 6;

// EDDGIVolumeTextureFormat
pub const RTXGI_TEXTURE_FORMAT_U32: Int = 0;
pub const RTXGI_TEXTURE_FORMAT_F16: Int = 1;
pub const RTXGI_TEXTURE_FORMAT_F16X2: Int = 2;
pub const RTXGI_TEXTURE_FORMAT_F16X4: Int = 3;
pub const RTXGI_TEXTURE_FORMAT_F32: Int = 4;
pub const RTXGI_TEXTURE_FORMAT_F32X2: Int = 5;
pub const RTXGI_TEXTURE_FORMAT_F32X4: Int = 6;
pub const RTXGI_TEXTURE_FORMAT_COUNT: Int = 7;

// EDDGIVolumeMovementType
pub const RTXGI_MOVEMENT_DEFAULT: Int = 0;
pub const RTXGI_MOVEMENT_SCROLLING: Int = 1;
pub const RTXGI_MOVEMENT_COUNT: Int = 2;

// EDDGIVolumeProbeVisType
pub const RTXGI_PROBE_VIS_DEFAULT: Int = 0;
pub const RTXGI_PROBE_VIS_HIDE_INACTIVE: Int = 1;
pub const RTXGI_PROBE_VIS_COUNT: Int = 2;

// =========================================================================
// DDGIVolumeDesc field indexes (38 entries; declaration order from the
// header, mirrored by the bridge's offsetof table -- single ABI truth)
// =========================================================================

pub const RTXGI_DESC_NAME: Int = 0;
pub const RTXGI_DESC_INDEX: Int = 1;
pub const RTXGI_DESC_RNG_SEED: Int = 2;
pub const RTXGI_DESC_SHOW_PROBES: Int = 3;
pub const RTXGI_DESC_INSERT_PERF_MARKERS: Int = 4;
pub const RTXGI_DESC_ORIGIN: Int = 5;
pub const RTXGI_DESC_EULER_ANGLES: Int = 6;
pub const RTXGI_DESC_PROBE_SPACING: Int = 7;
pub const RTXGI_DESC_PROBE_COUNTS: Int = 8;
pub const RTXGI_DESC_PROBE_NUM_RAYS: Int = 9;
pub const RTXGI_DESC_PROBE_NUM_IRRADIANCE_TEXELS: Int = 10;
pub const RTXGI_DESC_PROBE_NUM_IRRADIANCE_INTERIOR_TEXELS: Int = 11;
pub const RTXGI_DESC_PROBE_NUM_DISTANCE_TEXELS: Int = 12;
pub const RTXGI_DESC_PROBE_NUM_DISTANCE_INTERIOR_TEXELS: Int = 13;
pub const RTXGI_DESC_PROBE_HYSTERESIS: Int = 14;
pub const RTXGI_DESC_PROBE_MAX_RAY_DISTANCE: Int = 15;
pub const RTXGI_DESC_PROBE_DISTANCE_EXPONENT: Int = 16;
pub const RTXGI_DESC_PROBE_IRRADIANCE_ENCODING_GAMMA: Int = 17;
pub const RTXGI_DESC_PROBE_IRRADIANCE_THRESHOLD: Int = 18;
pub const RTXGI_DESC_PROBE_BRIGHTNESS_THRESHOLD: Int = 19;
pub const RTXGI_DESC_PROBE_RANDOM_RAY_BACKFACE_THRESHOLD: Int = 20;
pub const RTXGI_DESC_PROBE_FIXED_RAY_BACKFACE_THRESHOLD: Int = 21;
pub const RTXGI_DESC_PROBE_VIEW_BIAS: Int = 22;
pub const RTXGI_DESC_PROBE_NORMAL_BIAS: Int = 23;
pub const RTXGI_DESC_PROBE_RAY_DATA_FORMAT: Int = 24;
pub const RTXGI_DESC_PROBE_IRRADIANCE_FORMAT: Int = 25;
pub const RTXGI_DESC_PROBE_DISTANCE_FORMAT: Int = 26;
pub const RTXGI_DESC_PROBE_DATA_FORMAT: Int = 27;
pub const RTXGI_DESC_PROBE_VARIABILITY_FORMAT: Int = 28;
pub const RTXGI_DESC_PROBE_BLENDING_USE_SCROLL_SHARED_MEMORY: Int = 29;
pub const RTXGI_DESC_PROBE_RELOCATION_ENABLED: Int = 30;
pub const RTXGI_DESC_PROBE_RELOCATION_NEEDS_RESET: Int = 31;
pub const RTXGI_DESC_PROBE_MIN_FRONTFACE_DISTANCE: Int = 32;
pub const RTXGI_DESC_PROBE_CLASSIFICATION_ENABLED: Int = 33;
pub const RTXGI_DESC_PROBE_CLASSIFICATION_NEEDS_RESET: Int = 34;
pub const RTXGI_DESC_PROBE_VARIABILITY_ENABLED: Int = 35;
pub const RTXGI_DESC_MOVEMENT_TYPE: Int = 36;
pub const RTXGI_DESC_PROBE_VIS_TYPE: Int = 37;
pub const RTXGI_DESC_FIELD_COUNT: Int = 38;

// =========================================================================
// DDGIVolumeDescGPU field indexes (28 entries; bridge offsetof table)
// =========================================================================

pub const RTXGI_GPU_ORIGIN: Int = 0;
pub const RTXGI_GPU_ROTATION: Int = 1;
pub const RTXGI_GPU_PROBE_RAY_ROTATION: Int = 2;
pub const RTXGI_GPU_MOVEMENT_TYPE: Int = 3;
pub const RTXGI_GPU_PROBE_SPACING: Int = 4;
pub const RTXGI_GPU_PROBE_COUNTS: Int = 5;
pub const RTXGI_GPU_PROBE_NUM_RAYS: Int = 6;
pub const RTXGI_GPU_PROBE_NUM_IRRADIANCE_INTERIOR_TEXELS: Int = 7;
pub const RTXGI_GPU_PROBE_NUM_DISTANCE_INTERIOR_TEXELS: Int = 8;
pub const RTXGI_GPU_PROBE_HYSTERESIS: Int = 9;
pub const RTXGI_GPU_PROBE_MAX_RAY_DISTANCE: Int = 10;
pub const RTXGI_GPU_PROBE_NORMAL_BIAS: Int = 11;
pub const RTXGI_GPU_PROBE_VIEW_BIAS: Int = 12;
pub const RTXGI_GPU_PROBE_DISTANCE_EXPONENT: Int = 13;
pub const RTXGI_GPU_PROBE_IRRADIANCE_ENCODING_GAMMA: Int = 14;
pub const RTXGI_GPU_PROBE_IRRADIANCE_THRESHOLD: Int = 15;
pub const RTXGI_GPU_PROBE_BRIGHTNESS_THRESHOLD: Int = 16;
pub const RTXGI_GPU_PROBE_RANDOM_RAY_BACKFACE_THRESHOLD: Int = 17;
pub const RTXGI_GPU_PROBE_FIXED_RAY_BACKFACE_THRESHOLD: Int = 18;
pub const RTXGI_GPU_PROBE_MIN_FRONTFACE_DISTANCE: Int = 19;
pub const RTXGI_GPU_PROBE_SCROLL_OFFSETS: Int = 20;
pub const RTXGI_GPU_PROBE_SCROLL_CLEAR: Int = 21;
pub const RTXGI_GPU_PROBE_SCROLL_DIRECTIONS: Int = 22;
pub const RTXGI_GPU_PROBE_RAY_DATA_FORMAT: Int = 23;
pub const RTXGI_GPU_PROBE_IRRADIANCE_FORMAT: Int = 24;
pub const RTXGI_GPU_PROBE_RELOCATION_ENABLED: Int = 25;
pub const RTXGI_GPU_PROBE_CLASSIFICATION_ENABLED: Int = 26;
pub const RTXGI_GPU_PROBE_VARIABILITY_ENABLED: Int = 27;
pub const RTXGI_GPU_FIELD_COUNT: Int = 28;

// =========================================================================
// DDGIVolumeDescGPUPacked field indexes (19 entries; bridge offsetof table)
// =========================================================================

pub const RTXGI_PACKED_ORIGIN: Int = 0;
pub const RTXGI_PACKED_PROBE_HYSTERESIS: Int = 1;
pub const RTXGI_PACKED_ROTATION: Int = 2;
pub const RTXGI_PACKED_PROBE_RAY_ROTATION: Int = 3;
pub const RTXGI_PACKED_PROBE_MAX_RAY_DISTANCE: Int = 4;
pub const RTXGI_PACKED_PROBE_NORMAL_BIAS: Int = 5;
pub const RTXGI_PACKED_PROBE_VIEW_BIAS: Int = 6;
pub const RTXGI_PACKED_PROBE_DISTANCE_EXPONENT: Int = 7;
pub const RTXGI_PACKED_PROBE_IRRADIANCE_ENCODING_GAMMA: Int = 8;
pub const RTXGI_PACKED_PROBE_IRRADIANCE_THRESHOLD: Int = 9;
pub const RTXGI_PACKED_PROBE_BRIGHTNESS_THRESHOLD: Int = 10;
pub const RTXGI_PACKED_PROBE_MIN_FRONTFACE_DISTANCE: Int = 11;
pub const RTXGI_PACKED_PROBE_SPACING: Int = 12;
pub const RTXGI_PACKED_WORD0: Int = 13;
pub const RTXGI_PACKED_WORD1: Int = 14;
pub const RTXGI_PACKED_WORD2: Int = 15;
pub const RTXGI_PACKED_WORD3: Int = 16;
pub const RTXGI_PACKED_WORD4: Int = 17;
pub const RTXGI_PACKED_RESERVED: Int = 18;
pub const RTXGI_PACKED_FIELD_COUNT: Int = 19;

/// Packed-word bit layouts (DDGIVolumeDescGPU.h PackDDGIVolumeDescGPU).
pub const RTXGI_PACKED0_COUNT_BITS: Int = 10;
pub const RTXGI_PACKED0_COUNT_MASK: Int = 1023;
pub const RTXGI_PACKED0_COUNT_Y_SHIFT: Int = 10;
pub const RTXGI_PACKED0_COUNT_Z_SHIFT: Int = 20;
pub const RTXGI_PACKED_SCROLL_MASK: Int = 32767;
pub const RTXGI_PACKED_SCROLL_SIGN_X: Int = 15;
pub const RTXGI_PACKED_SCROLL_SIGN_Y: Int = 31;
pub const RTXGI_PACKED_SCROLL_SIGN_Z: Int = 15;
pub const RTXGI_PACKED_THRESHOLD_SCALE: Int = 65535;
pub const RTXGI_PACKED4_MOVEMENT_SHIFT: Int = 16;
pub const RTXGI_PACKED4_RAY_DATA_FORMAT_SHIFT: Int = 17;
pub const RTXGI_PACKED4_IRRADIANCE_FORMAT_SHIFT: Int = 20;
pub const RTXGI_PACKED4_RELOCATION_SHIFT: Int = 23;
pub const RTXGI_PACKED4_CLASSIFICATION_SHIFT: Int = 24;
pub const RTXGI_PACKED4_VARIABILITY_SHIFT: Int = 25;
pub const RTXGI_PACKED4_SCROLL_CLEAR_SHIFT: Int = 26;
pub const RTXGI_PACKED4_SCROLL_DIR_SHIFT: Int = 29;

/// Mirror struct sizes at the pinned build (present-path shim cross-checks).
pub const RTXGI_DESC_SIZE: Int = 168;
pub const RTXGI_GPU_DESC_SIZE: Int = 160;
pub const RTXGI_PACKED_SIZE: Int = 128;
pub const RTXGI_RESOURCE_INDICES_SIZE: Int = 48;
pub const RTXGI_SLACK: Int = 64;

/// Layout kinds for rtxgi_layout().
pub const RTXGI_LAYOUT_DESC: Int = 0;
pub const RTXGI_LAYOUT_GPU_DESC: Int = 1;
pub const RTXGI_LAYOUT_PACKED: Int = 2;
pub const RTXGI_LAYOUT_RESOURCE_INDICES: Int = 3;
pub const RTXGI_LAYOUT_ROOT_CONSTANTS: Int = 4;

// =========================================================================
// FFI: the XIOM-side bridge (src/rtxgi_bridge.cpp; ours)
// =========================================================================

extern "C" {
  fn rtxgib_try_load(path: *UInt8, len: Int32) -> Int;
  fn rtxgib_try_load_auto() -> Int;
  fn rtxgib_load_kind() -> Int32;
  fn rtxgib_close(h: Int) -> Int32;

  fn rtxgib_layout(kind: Int32, offsets: *UInt8, sizes: *UInt8, cap: Int32) -> Int32;
  fn rtxgib_layout_size(kind: Int32) -> Int32;
  fn rtxgib_desc_default(dst: *UInt8, cap: Int32) -> Int32;

  fn rtxgib_info(h: Int, out: *UInt8, cap: Int32) -> Int32;
  fn rtxgib_sdk_layout(h: Int, kind: Int32, out: *UInt8, cap: Int32) -> Int32;
  fn rtxgib_sdk_default_desc(h: Int, dst: *UInt8, cap: Int32) -> Int32;
  fn rtxgib_descriptor_counts(h: Int, out: *UInt8, cap: Int32) -> Int32;
  fn rtxgib_validate_shader_bytecode(h: Int, size: Int32) -> Int32;
  fn rtxgib_set_insert_perf_markers(h: Int, v: Int32) -> Int32;
  fn rtxgib_get_insert_perf_markers(h: Int) -> Int32;

  fn rtxgib_probe_counts(h: Int, desc: *UInt8, size: Int32, out: *UInt8, cap: Int32) -> Int32;
  fn rtxgib_texture_dimensions(h: Int, desc: *UInt8, size: Int32, texture_type: Int32, out: *UInt8, cap: Int32) -> Int32;

  fn rtxgib_volume_create(h: Int, desc: *UInt8, size: Int32, out: *UInt8) -> Int32;
  fn rtxgib_volume_destroy(h: Int, volume: Int) -> Int32;
  fn rtxgib_volume_update(h: Int, volume: Int) -> Int32;
  fn rtxgib_volume_seed_rng(h: Int, volume: Int, seed: Int32) -> Int32;
  fn rtxgib_volume_get_random(h: Int, volume: Int, out: *UInt8) -> Int32;
  fn rtxgib_volume_set_movement_type(h: Int, volume: Int, v: Int32) -> Int32;
  fn rtxgib_volume_set_origin(h: Int, volume: Int, x: Float32, y: Float32, z: Float32) -> Int32;
  fn rtxgib_volume_set_scroll_anchor(h: Int, volume: Int, x: Float32, y: Float32, z: Float32) -> Int32;
  fn rtxgib_volume_set_probe_hysteresis(h: Int, volume: Int, v: Float32) -> Int32;
  fn rtxgib_volume_set_euler_angles(h: Int, volume: Int, x: Float32, y: Float32, z: Float32) -> Int32;
  fn rtxgib_volume_get_origin(h: Int, volume: Int, out: *UInt8) -> Int32;
  fn rtxgib_volume_get_gpu_desc(h: Int, volume: Int, out: *UInt8, cap: Int32) -> Int32;
  fn rtxgib_volume_get_gpu_desc_packed(h: Int, volume: Int, out: *UInt8, cap: Int32) -> Int32;
  fn rtxgib_volume_num_probes(h: Int, volume: Int) -> Int32;
  fn rtxgib_volume_num_rays(h: Int, volume: Int) -> Int32;
  fn rtxgib_volume_tex2darray_size(h: Int, volume: Int) -> Int32;
  fn rtxgib_volume_ray_dispatch(h: Int, volume: Int, out: *UInt8) -> Int32;
  fn rtxgib_volume_gpu_memory(h: Int, volume: Int) -> Int32;
  fn rtxgib_volume_aabb(h: Int, volume: Int, out: *UInt8) -> Int32;
  fn rtxgib_volume_obb(h: Int, volume: Int, out: *UInt8) -> Int32;
  fn rtxgib_volume_probe_world_pos(h: Int, volume: Int, index: Int32, out: *UInt8) -> Int32;

  fn rtxgib_execute(h: Int, volume: Int) -> Int32;

  fn rtxgib_img_set_u32(dst: *UInt8, cap: Int32, off: Int32, v: Int32) -> Int32;
  fn rtxgib_img_set_u16(dst: *UInt8, cap: Int32, off: Int32, v: Int32) -> Int32;
  fn rtxgib_img_set_u8(dst: *UInt8, cap: Int32, off: Int32, v: Int32) -> Int32;
  fn rtxgib_img_set_f32(dst: *UInt8, cap: Int32, off: Int32, v: Float32) -> Int32;
  fn rtxgib_img_get_u32(src: *UInt8, cap: Int32, off: Int32) -> Int32;
  fn rtxgib_img_get_i32(src: *UInt8, cap: Int32, off: Int32) -> Int32;
  fn rtxgib_img_get_u16(src: *UInt8, cap: Int32, off: Int32) -> Int32;
  fn rtxgib_img_get_u8(src: *UInt8, cap: Int32, off: Int32) -> Int32;
  fn rtxgib_img_get_f32(src: *UInt8, cap: Int32, off: Int32) -> Float32;
}

// =========================================================================
// Owned-slot helpers (B-17/B-24: byte-indexed reads, push-loop allocation)
// =========================================================================

pub fn rtxgi_byte_slot(n: Int) -> Vec[UInt8]
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

fn rtxgi_slot(n: Int) -> Vec[UInt8]
  requires: n > 0
{
  return rtxgi_byte_slot(n);
}

fn rtxgi_rd_u32(buf: &Vec[UInt8], off: Int) -> Int
  requires: off >= 0
  requires: buf.len() >= off + 4
{
  let b0 = buf[off + 0] as Int;
  let b1 = buf[off + 1] as Int;
  let b2 = buf[off + 2] as Int;
  let b3 = buf[off + 3] as Int;
  return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24);
}

fn rtxgi_rd_f32(buf: &Vec[UInt8], off: Int) -> Float32
  requires: off >= 0
  requires: buf.len() >= off + 4
{
  return unsafe { rtxgib_img_get_f32(buf.as_ptr(), buf.len() as Int32, off as Int32) };
}

fn rtxgi_rd_u8(buf: &Vec[UInt8], off: Int) -> Int
  requires: off >= 0
  requires: buf.len() >= off + 1
{
  return buf[off] as Int;
}

/// Signed 32-bit read of an owned image word (bridge-side interpretation).
fn rtxgi_rd_i32(buf: &Vec[UInt8], off: Int) -> Int
  requires: off >= 0
  requires: buf.len() >= off + 4
{
  let raw = unsafe { rtxgib_img_get_i32(buf.as_ptr(), buf.len() as Int32, off as Int32) } as Int;
  return raw;
}

/// Interpret an unsigned 32-bit slot word as a signed int32 value.
/// Precondition avoids the 2^32 literal (Int32-range contract literals).
pub fn rtxgi_sign_i32(v: Int) -> Int
  requires: v >= 0
{
  if v >= 2147483648 { return v - 4294967296; }
  return v;
}

fn rtxgi_code_name(code: Int) -> Str
  requires: true
{
  if code == RTXGI_STATUS_OK { return "OK"; }
  if code == RTXGI_STATUS_ERROR_DDGI_INVALID_PROBE_COUNTS { return "ERROR_DDGI_INVALID_PROBE_COUNTS"; }
  if code == RTXGI_STATUS_ERROR_DDGI_INVALID_RESOURCES_DESC { return "ERROR_DDGI_INVALID_RESOURCES_DESC"; }
  if code == RTXGI_ERR_NOT_LOADED { return "bridge: not loaded"; }
  if code == RTXGI_ERR_BAD_ARGS { return "bridge: bad args"; }
  if code == RTXGI_ERR_SIZE { return "bridge: owned image smaller than the ABI mirror"; }
  if code == RTXGI_ERR_CAPACITY { return "bridge: out slot too small"; }
  return "code " + convert.int_to_string(code);
}

// =========================================================================
// Loader
// =========================================================================

pub type RtxgiError = {
  kind: Int;
  message: Str;
}

/// A loaded RTXGI shim module.
pub type RtxgiModule = {
  h: Int;
}

/// Load the RTXGI shim: `XIOM_RTXGI_SHIM` env var first, then the default
/// module search (cwd, PATH).  Err(RTXGI_LOAD_ABSENT) when no module is
/// present (the classified SKIP path).  Complexity: O(1) after the load.
pub fn rtxgi_load() -> Result[RtxgiModule, RtxgiError]
  requires: true
{
  let h = unsafe { rtxgib_try_load_auto() };
  if h == 0 {
    if unsafe { rtxgib_load_kind() } as Int == RTXGI_LOAD_ABI {
      return Err(RtxgiError{ kind: RTXGI_LOAD_ABI; message: "module loaded but the RTXGI shim entry points are missing" });
    }
    return Err(RtxgiError{ kind: RTXGI_LOAD_ABSENT; message: "xiom_rtxgi_shim.dll not found (XIOM_RTXGI_SHIM / default search)" });
  }
  return Ok(RtxgiModule{ h: h });
}

/// Load one named module path (deterministic SKIP-path probe).
/// Complexity: O(1) after the load.
pub fn rtxgi_load_named(path: Str) -> Result[RtxgiModule, RtxgiError]
  requires: path.len() > 0
{
  let h = unsafe { rtxgib_try_load(path as *UInt8, path.len() as Int32) };
  if h == 0 {
    if unsafe { rtxgib_load_kind() } as Int == RTXGI_LOAD_ABI {
      return Err(RtxgiError{ kind: RTXGI_LOAD_ABI; message: path + ": entry points missing" });
    }
    return Err(RtxgiError{ kind: RTXGI_LOAD_ABSENT; message: path + ": module not found" });
  }
  return Ok(RtxgiModule{ h: h });
}

/// Unload the shim module.  Complexity: O(1).
pub fn rtxgi_close(mod: &RtxgiModule) -> Result[Unit, RtxgiError]
  requires: mod.h != 0
{
  let rc = unsafe { rtxgib_close(mod.h) } as Int;
  if rc == 0 { return Ok(()); }
  return Err(RtxgiError{ kind: rc; message: rtxgi_code_name(rc) });
}

// =========================================================================
// Shim info, layout tables, defaults
// =========================================================================

pub type RtxgiShimInfo = {
  coordinate_system: Int;
  resource_management: Int;
  version_major: Int;
  version_minor: Int;
  version_revision: Int;
  size_desc: Int;
  size_gpu_desc: Int;
  size_packed: Int;
}

pub fn rtxgi_info(mod: &RtxgiModule) -> Result[RtxgiShimInfo, RtxgiError]
  requires: mod.h != 0
{
  var slot = rtxgi_slot(32);
  let rc = unsafe { rtxgib_info(mod.h, slot.as_mut_ptr(), 32) } as Int;
  if rc != 0 { return Err(RtxgiError{ kind: rc; message: rtxgi_code_name(rc) }); }
  return Ok(RtxgiShimInfo{
    coordinate_system: rtxgi_rd_u32(&slot, 0);
    resource_management: rtxgi_rd_u32(&slot, 4);
    version_major: rtxgi_rd_u32(&slot, 8);
    version_minor: rtxgi_rd_u32(&slot, 12);
    version_revision: rtxgi_rd_u32(&slot, 16);
    size_desc: rtxgi_rd_u32(&slot, 20);
    size_gpu_desc: rtxgi_rd_u32(&slot, 24);
    size_packed: rtxgi_rd_u32(&slot, 28);
  });
}

/// A fetched layout table: `count` (offset,size) pairs.
pub type RtxgiLayout = {
  count: Int;
  offsets: Vec[UInt8];
  sizes: Vec[UInt8];
}

/// Bridge layout table for `kind` (ours; offsetof of the ABI mirrors).
pub fn rtxgi_layout(kind: Int) -> Result[RtxgiLayout, RtxgiError]
  requires: kind >= RTXGI_LAYOUT_DESC
  requires: kind <= RTXGI_LAYOUT_ROOT_CONSTANTS
{
  let count = unsafe { rtxgib_layout(kind as Int32, 0 as *UInt8, 0 as *UInt8, 0) } as Int;
  if count <= 0 { return Err(RtxgiError{ kind: RTXGI_ERR_BAD_ARGS; message: "unknown layout kind" }); }
  var offsets = rtxgi_slot(count * 4);
  var sizes = rtxgi_slot(count * 4);
  let got = unsafe {
    rtxgib_layout(kind as Int32, offsets.as_mut_ptr(), sizes.as_mut_ptr(), count as Int32)
  } as Int;
  if got != count {
    return Err(RtxgiError{ kind: RTXGI_ERR_BAD_ARGS; message: "layout table fetch failed" });
  }
  return Ok(RtxgiLayout{ count: count; offsets: offsets; sizes: sizes });
}

fn rtxgi_wr_u32(buf: &mut Vec[UInt8], off: Int, v: Int)
  requires: off >= 0
  requires: buf.len() >= off + 4
{
  buf[off + 0] = (v & 255) as UInt8;
  buf[off + 1] = ((v >> 8) & 255) as UInt8;
  buf[off + 2] = ((v >> 16) & 255) as UInt8;
  buf[off + 3] = ((v >> 24) & 255) as UInt8;
}

/// SDK layout table for `kind` (the shim's real structs; drift check).
pub fn rtxgi_sdk_layout(mod: &RtxgiModule, kind: Int) -> Result[RtxgiLayout, RtxgiError]
  requires: mod.h != 0
  requires: kind >= RTXGI_LAYOUT_DESC
  requires: kind <= RTXGI_LAYOUT_ROOT_CONSTANTS
{
  var raw = rtxgi_slot(4 + 64 * 8);
  let rc = unsafe { rtxgib_sdk_layout(mod.h, kind as Int32, raw.as_mut_ptr(), (4 + 64 * 8) as Int32) } as Int;
  if rc < 0 { return Err(RtxgiError{ kind: rc; message: rtxgi_code_name(rc) }); }
  let count = rtxgi_rd_u32(&raw, 0);
  if count == 0 || count > 64 {
    return Err(RtxgiError{ kind: RTXGI_ERR_BAD_ARGS; message: "unexpected SDK layout pair count" });
  }
  var offsets = rtxgi_slot(count * 4);
  var sizes = rtxgi_slot(count * 4);
  var i = 0;
  while i < count {
    let off = rtxgi_rd_u32(&raw, 4 + i * 8);
    let sz = rtxgi_rd_u32(&raw, 8 + i * 8);
    rtxgi_wr_u32(&mut offsets, i * 4, off);
    rtxgi_wr_u32(&mut sizes, i * 4, sz);
    i = i + 1;
  }
  return Ok(RtxgiLayout{ count: count; offsets: offsets; sizes: sizes });
}

pub fn rtxgi_layout_field_offset(layout: &RtxgiLayout, field: Int) -> Int
  requires: field >= 0
  requires: field < layout.count
{
  return rtxgi_rd_u32(&layout.offsets, field * 4);
}

pub fn rtxgi_layout_field_size(layout: &RtxgiLayout, field: Int) -> Int
  requires: field >= 0
  requires: field < layout.count
{
  return rtxgi_rd_u32(&layout.sizes, field * 4);
}

pub fn rtxgi_mirror_size(kind: Int) -> Int
  requires: kind >= RTXGI_LAYOUT_DESC
  requires: kind <= RTXGI_LAYOUT_ROOT_CONSTANTS
{
  return unsafe { rtxgib_layout_size(kind as Int32) } as Int;
}

// =========================================================================
// DDGIVolumeDesc owned image (settings plumbing)
// =========================================================================

pub type RtxgiDesc = {
  size: Int;
  count: Int;
  data: Vec[UInt8];
  offsets: Vec[UInt8];
  sizes: Vec[UInt8];
}

/// Default-filled desc image from the bridge (header defaults; formats = U32).
/// Complexity: O(size).
pub fn rtxgi_desc_default() -> Result[RtxgiDesc, RtxgiError]
  requires: true
{
  let mirror = rtxgi_mirror_size(RTXGI_LAYOUT_DESC);
  if mirror != RTXGI_DESC_SIZE {
    return Err(RtxgiError{ kind: RTXGI_ERR_SIZE; message: "desc mirror size drifted from the pinned anchor" });
  }
  let layout = rtxgi_layout(RTXGI_LAYOUT_DESC);
  if layout.is_err { return Err(layout.error); }
  let total = mirror + RTXGI_SLACK;
  var data = rtxgi_slot(total);
  let rc = unsafe { rtxgib_desc_default(data.as_mut_ptr(), total as Int32) } as Int;
  if rc != 0 { return Err(RtxgiError{ kind: rc; message: rtxgi_code_name(rc) }); }
  return Ok(RtxgiDesc{
    size: mirror;
    count: layout.value.count;
    data: data;
    offsets: layout.value.offsets;
    sizes: layout.value.sizes;
  });
}

/// Default-filled desc image from the SDK shim (value-initialized struct).
/// Complexity: O(size).
pub fn rtxgi_sdk_desc_default(mod: &RtxgiModule) -> Result[RtxgiDesc, RtxgiError]
  requires: mod.h != 0
{
  let layout = rtxgi_layout(RTXGI_LAYOUT_DESC);
  if layout.is_err { return Err(layout.error); }
  let total = RTXGI_DESC_SIZE + RTXGI_SLACK;
  var data = rtxgi_slot(total);
  let rc = unsafe { rtxgib_sdk_default_desc(mod.h, data.as_mut_ptr(), total as Int32) } as Int;
  if rc != 0 { return Err(RtxgiError{ kind: rc; message: rtxgi_code_name(rc) }); }
  return Ok(RtxgiDesc{
    size: RTXGI_DESC_SIZE;
    count: layout.value.count;
    data: data;
    offsets: layout.value.offsets;
    sizes: layout.value.sizes;
  });
}

pub fn rtxgi_desc_field_offset(desc: &RtxgiDesc, field: Int) -> Int
  requires: field >= 0
  requires: field < desc.count
{
  return rtxgi_rd_u32(&desc.offsets, field * 4);
}

pub fn rtxgi_desc_field_size(desc: &RtxgiDesc, field: Int) -> Int
  requires: field >= 0
  requires: field < desc.count
{
  return rtxgi_rd_u32(&desc.sizes, field * 4);
}

pub fn rtxgi_desc_set_i32(desc: &mut RtxgiDesc, field: Int, v: Int) -> Result[Unit, RtxgiError]
  requires: field >= 0
  requires: field < desc.count
{
  let off = rtxgi_desc_field_offset(desc, field);
  let rc = unsafe { rtxgib_img_set_u32(desc.data.as_mut_ptr(), desc.data.len() as Int32, off as Int32, v as Int32) } as Int;
  if rc != 0 { return Err(RtxgiError{ kind: rc; message: rtxgi_code_name(rc) }); }
  return Ok(());
}

pub fn rtxgi_desc_get_i32(desc: &RtxgiDesc, field: Int) -> Int
  requires: field >= 0
  requires: field < desc.count
{
  let off = rtxgi_desc_field_offset(desc, field);
  return rtxgi_rd_i32(&desc.data, off);
}

pub fn rtxgi_desc_set_f32(desc: &mut RtxgiDesc, field: Int, v: Float32) -> Result[Unit, RtxgiError]
  requires: field >= 0
  requires: field < desc.count
{
  let off = rtxgi_desc_field_offset(desc, field);
  let rc = unsafe { rtxgib_img_set_f32(desc.data.as_mut_ptr(), desc.data.len() as Int32, off as Int32, v) } as Int;
  if rc != 0 { return Err(RtxgiError{ kind: rc; message: rtxgi_code_name(rc) }); }
  return Ok(());
}

pub fn rtxgi_desc_get_f32(desc: &RtxgiDesc, field: Int) -> Float32
  requires: field >= 0
  requires: field < desc.count
{
  let off = rtxgi_desc_field_offset(desc, field);
  return unsafe { rtxgib_img_get_f32(desc.data.as_ptr(), desc.data.len() as Int32, off as Int32) };
}

pub fn rtxgi_desc_set_i32_at(desc: &mut RtxgiDesc, field: Int, index: Int, v: Int) -> Result[Unit, RtxgiError]
  requires: field >= 0
  requires: field < desc.count
  requires: index >= 0
  requires: index < 4
{
  let off = rtxgi_desc_field_offset(desc, field) + index * 4;
  let rc = unsafe { rtxgib_img_set_u32(desc.data.as_mut_ptr(), desc.data.len() as Int32, off as Int32, v as Int32) } as Int;
  if rc != 0 { return Err(RtxgiError{ kind: rc; message: rtxgi_code_name(rc) }); }
  return Ok(());
}

pub fn rtxgi_desc_get_i32_at(desc: &RtxgiDesc, field: Int, index: Int) -> Int
  requires: field >= 0
  requires: field < desc.count
  requires: index >= 0
  requires: index < 4
{
  let off = rtxgi_desc_field_offset(desc, field) + index * 4;
  return rtxgi_rd_i32(&desc.data, off);
}

pub fn rtxgi_desc_set_f32_at(desc: &mut RtxgiDesc, field: Int, index: Int, v: Float32) -> Result[Unit, RtxgiError]
  requires: field >= 0
  requires: field < desc.count
  requires: index >= 0
  requires: index < 4
{
  let off = rtxgi_desc_field_offset(desc, field) + index * 4;
  let rc = unsafe { rtxgib_img_set_f32(desc.data.as_mut_ptr(), desc.data.len() as Int32, off as Int32, v) } as Int;
  if rc != 0 { return Err(RtxgiError{ kind: rc; message: rtxgi_code_name(rc) }); }
  return Ok(());
}

pub fn rtxgi_desc_get_f32_at(desc: &RtxgiDesc, field: Int, index: Int) -> Float32
  requires: field >= 0
  requires: field < desc.count
  requires: index >= 0
  requires: index < 4
{
  let off = rtxgi_desc_field_offset(desc, field) + index * 4;
  return unsafe { rtxgib_img_get_f32(desc.data.as_ptr(), desc.data.len() as Int32, off as Int32) };
}

pub fn rtxgi_desc_set_bool(desc: &mut RtxgiDesc, field: Int, v: Bool) -> Result[Unit, RtxgiError]
  requires: field >= 0
  requires: field < desc.count
{
  let off = rtxgi_desc_field_offset(desc, field);
  var b = 0;
  if v { b = 1; }
  let rc = unsafe { rtxgib_img_set_u8(desc.data.as_mut_ptr(), desc.data.len() as Int32, off as Int32, b as Int32) } as Int;
  if rc != 0 { return Err(RtxgiError{ kind: rc; message: rtxgi_code_name(rc) }); }
  return Ok(());
}

pub fn rtxgi_desc_get_bool(desc: &RtxgiDesc, field: Int) -> Bool
  requires: field >= 0
  requires: field < desc.count
{
  let off = rtxgi_desc_field_offset(desc, field);
  let raw = unsafe { rtxgib_img_get_u8(desc.data.as_ptr(), desc.data.len() as Int32, off as Int32) } as Int;
  return raw != 0;
}

/// Convenience: a default desc configured for a `cx`x`cy`x`cz` probe grid
/// with `rays` rays per probe and the given interior texel counts (the
/// border-inclusive texel counts are derived as interior + 2, matching the
/// SDK sample convention).  Complexity: O(size).
pub fn rtxgi_desc_for_volume(cx: Int, cy: Int, cz: Int, rays: Int, irradiance_interior_texels: Int, distance_interior_texels: Int) -> Result[RtxgiDesc, RtxgiError]
  requires: cx > 0 && cx <= RTXGI_PACKED0_COUNT_MASK
  requires: cy > 0 && cy <= RTXGI_PACKED0_COUNT_MASK
  requires: cz > 0 && cz <= RTXGI_PACKED0_COUNT_MASK
  requires: rays > 0 && rays <= 65535
  requires: irradiance_interior_texels > 0 && irradiance_interior_texels <= 253
  requires: distance_interior_texels > 0 && distance_interior_texels <= 253
{
  var d = rtxgi_desc_default();
  if d.is_err { return Err(d.error); }
  var img = d.value;
  let rc0 = rtxgi_desc_set_i32_at(&mut img, RTXGI_DESC_PROBE_COUNTS, 0, cx);
  if rc0.is_err { return Err(rc0.error); }
  let rc1 = rtxgi_desc_set_i32_at(&mut img, RTXGI_DESC_PROBE_COUNTS, 1, cy);
  if rc1.is_err { return Err(rc1.error); }
  let rc2 = rtxgi_desc_set_i32_at(&mut img, RTXGI_DESC_PROBE_COUNTS, 2, cz);
  if rc2.is_err { return Err(rc2.error); }
  let rc3 = rtxgi_desc_set_i32(&mut img, RTXGI_DESC_PROBE_NUM_RAYS, rays);
  if rc3.is_err { return Err(rc3.error); }
  let rc4 = rtxgi_desc_set_i32(&mut img, RTXGI_DESC_PROBE_NUM_IRRADIANCE_INTERIOR_TEXELS, irradiance_interior_texels);
  if rc4.is_err { return Err(rc4.error); }
  let rc5 = rtxgi_desc_set_i32(&mut img, RTXGI_DESC_PROBE_NUM_DISTANCE_INTERIOR_TEXELS, distance_interior_texels);
  if rc5.is_err { return Err(rc5.error); }
  let rc6 = rtxgi_desc_set_i32(&mut img, RTXGI_DESC_PROBE_NUM_IRRADIANCE_TEXELS, irradiance_interior_texels + 2);
  if rc6.is_err { return Err(rc6.error); }
  let rc7 = rtxgi_desc_set_i32(&mut img, RTXGI_DESC_PROBE_NUM_DISTANCE_TEXELS, distance_interior_texels + 2);
  if rc7.is_err { return Err(rc7.error); }
  return Ok(img);
}

// =========================================================================
// Probe counts / texture dimensions / descriptor counts
// =========================================================================

pub type RtxgiI3 = {
  x: Int;
  y: Int;
  z: Int;
}

/// GetDDGIVolumeProbeCounts (coordinate-system aware; the pinned build swaps
/// the y/z axes for the default right-handed, y-up system).
/// Complexity: O(1).
pub fn rtxgi_probe_counts(mod: &RtxgiModule, desc: &RtxgiDesc) -> Result[RtxgiI3, RtxgiError]
  requires: mod.h != 0
{
  var slot = rtxgi_slot(12);
  let rc = unsafe {
    rtxgib_probe_counts(mod.h, desc.data.as_ptr(), desc.size as Int32, slot.as_mut_ptr(), 12)
  } as Int;
  if rc != 0 { return Err(RtxgiError{ kind: rc; message: rtxgi_code_name(rc) }); }
  return Ok(RtxgiI3{ x: rtxgi_rd_u32(&slot, 0); y: rtxgi_rd_u32(&slot, 4); z: rtxgi_rd_u32(&slot, 8); });
}

/// GetDDGIVolumeTextureDimensions -> (width, height, arraySize).
/// Complexity: O(1).
pub fn rtxgi_texture_dimensions(mod: &RtxgiModule, desc: &RtxgiDesc, texture_type: Int) -> Result[RtxgiI3, RtxgiError]
  requires: mod.h != 0
  requires: texture_type >= 0
  requires: texture_type < RTXGI_TEXTURE_TYPE_COUNT
{
  var slot = rtxgi_slot(12);
  let rc = unsafe {
    rtxgib_texture_dimensions(mod.h, desc.data.as_ptr(), desc.size as Int32, texture_type as Int32, slot.as_mut_ptr(), 12)
  } as Int;
  if rc != 0 { return Err(RtxgiError{ kind: rc; message: rtxgi_code_name(rc) }); }
  return Ok(RtxgiI3{ x: rtxgi_rd_u32(&slot, 0); y: rtxgi_rd_u32(&slot, 4); z: rtxgi_rd_u32(&slot, 8); });
}

pub type RtxgiDescriptorCounts = {
  rtv: Int;
  tex2darray: Int;
  resource: Int;
}

/// GetDDGIVolumeNum{RTV,Tex2DArray,Resource}Descriptors from the shim.
/// Complexity: O(1).
pub fn rtxgi_descriptor_counts(mod: &RtxgiModule) -> Result[RtxgiDescriptorCounts, RtxgiError]
  requires: mod.h != 0
{
  var slot = rtxgi_slot(12);
  let rc = unsafe { rtxgib_descriptor_counts(mod.h, slot.as_mut_ptr(), 12) } as Int;
  if rc != 0 { return Err(RtxgiError{ kind: rc; message: rtxgi_code_name(rc) }); }
  return Ok(RtxgiDescriptorCounts{
    rtv: rtxgi_rd_u32(&slot, 0);
    tex2darray: rtxgi_rd_u32(&slot, 4);
    resource: rtxgi_rd_u32(&slot, 8);
  });
}

/// ValidateShaderBytecode: false for an empty blob, true otherwise.
/// Complexity: O(1).
pub fn rtxgi_validate_shader_bytecode(mod: &RtxgiModule, size: Int) -> Result[Bool, RtxgiError]
  requires: mod.h != 0
  requires: size >= 0
{
  let rc = unsafe { rtxgib_validate_shader_bytecode(mod.h, size as Int32) } as Int;
  if rc < 0 { return Err(RtxgiError{ kind: rc; message: rtxgi_code_name(rc) }); }
  return Ok(rc == 1);
}

/// SetInsertPerfMarkers (global SDK flag).  Complexity: O(1).
pub fn rtxgi_set_insert_perf_markers(mod: &RtxgiModule, value: Bool) -> Result[Unit, RtxgiError]
  requires: mod.h != 0
{
  var v = 0;
  if value { v = 1; }
  let rc = unsafe { rtxgib_set_insert_perf_markers(mod.h, v as Int32) } as Int;
  if rc != 0 { return Err(RtxgiError{ kind: rc; message: rtxgi_code_name(rc) }); }
  return Ok(());
}

/// bInsertPerfMarkers (global SDK flag).  Complexity: O(1).
pub fn rtxgi_get_insert_perf_markers(mod: &RtxgiModule) -> Result[Bool, RtxgiError]
  requires: mod.h != 0
{
  let rc = unsafe { rtxgib_get_insert_perf_markers(mod.h) } as Int;
  if rc < 0 { return Err(RtxgiError{ kind: rc; message: rtxgi_code_name(rc) }); }
  return Ok(rc == 1);
}

// =========================================================================
// DDGIVolume lifecycle + CPU surface
// =========================================================================

/// A DDGIVolume (CPU model instance owned by the shim).  Destroy with
/// `rtxgi_volume_destroy`.
pub type RtxgiVolume = {
  mod: Int;
  raw: Int;
}

/// Create a volume from an owned desc image.
/// Complexity: O(1).
pub fn rtxgi_volume_create(mod: &RtxgiModule, desc: &RtxgiDesc) -> Result[RtxgiVolume, RtxgiError]
  requires: mod.h != 0
  requires: desc.size == RTXGI_DESC_SIZE
{
  var slot = rtxgi_slot(8);
  let rc = unsafe {
    rtxgib_volume_create(mod.h, desc.data.as_ptr(), desc.size as Int32, slot.as_mut_ptr())
  } as Int;
  if rc != 0 { return Err(RtxgiError{ kind: rc; message: rtxgi_code_name(rc) }); }
  let lo = rtxgi_rd_u32(&slot, 0);
  let hi = rtxgi_rd_u32(&slot, 4);
  let raw = lo | (hi << 32);
  if raw == 0 { return Err(RtxgiError{ kind: RTXGI_STATUS_ERROR_DDGI_INVALID_PROBE_COUNTS; message: "volume creation returned null" }); }
  return Ok(RtxgiVolume{ mod: mod.h; raw: raw });
}

/// Destroy a volume.  Complexity: O(1).
pub fn rtxgi_volume_destroy(vol: &RtxgiVolume) -> Result[Unit, RtxgiError]
  requires: vol.raw != 0
{
  let rc = unsafe { rtxgib_volume_destroy(vol.mod, vol.raw) } as Int;
  if rc == 0 { return Ok(()); }
  return Err(RtxgiError{ kind: rc; message: rtxgi_code_name(rc) });
}

/// Update(): random probe-ray rotation (+ scrolling when enabled).
/// Complexity: O(1).
pub fn rtxgi_volume_update(vol: &RtxgiVolume) -> Result[Unit, RtxgiError]
  requires: vol.raw != 0
{
  let rc = unsafe { rtxgib_volume_update(vol.mod, vol.raw) } as Int;
  if rc == 0 { return Ok(()); }
  return Err(RtxgiError{ kind: rc; message: rtxgi_code_name(rc) });
}

/// SeedRNG (SDK-global RNG).  Complexity: O(1).
pub fn rtxgi_volume_seed_rng(vol: &RtxgiVolume, seed: Int) -> Result[Unit, RtxgiError]
  requires: vol.raw != 0
{
  let rc = unsafe { rtxgib_volume_seed_rng(vol.mod, vol.raw, seed as Int32) } as Int;
  if rc == 0 { return Ok(()); }
  return Err(RtxgiError{ kind: rc; message: rtxgi_code_name(rc) });
}

/// GetRandomFloat.  Complexity: O(1).
pub fn rtxgi_volume_get_random(vol: &RtxgiVolume) -> Result[Float32, RtxgiError]
  requires: vol.raw != 0
{
  var slot = rtxgi_slot(4);
  let rc = unsafe { rtxgib_volume_get_random(vol.mod, vol.raw, slot.as_mut_ptr()) } as Int;
  if rc != 0 { return Err(RtxgiError{ kind: rc; message: rtxgi_code_name(rc) }); }
  return Ok(rtxgi_rd_f32(&slot, 0));
}

pub fn rtxgi_volume_set_movement_type(vol: &RtxgiVolume, movement_type: Int) -> Result[Unit, RtxgiError]
  requires: vol.raw != 0
  requires: movement_type >= 0
  requires: movement_type < RTXGI_MOVEMENT_COUNT
{
  let rc = unsafe { rtxgib_volume_set_movement_type(vol.mod, vol.raw, movement_type as Int32) } as Int;
  if rc == 0 { return Ok(()); }
  return Err(RtxgiError{ kind: rc; message: rtxgi_code_name(rc) });
}

pub fn rtxgi_volume_set_origin(vol: &RtxgiVolume, x: Float32, y: Float32, z: Float32) -> Result[Unit, RtxgiError]
  requires: vol.raw != 0
{
  let rc = unsafe { rtxgib_volume_set_origin(vol.mod, vol.raw, x, y, z) } as Int;
  if rc == 0 { return Ok(()); }
  return Err(RtxgiError{ kind: rc; message: rtxgi_code_name(rc) });
}

pub fn rtxgi_volume_set_scroll_anchor(vol: &RtxgiVolume, x: Float32, y: Float32, z: Float32) -> Result[Unit, RtxgiError]
  requires: vol.raw != 0
{
  let rc = unsafe { rtxgib_volume_set_scroll_anchor(vol.mod, vol.raw, x, y, z) } as Int;
  if rc == 0 { return Ok(()); }
  return Err(RtxgiError{ kind: rc; message: rtxgi_code_name(rc) });
}

pub fn rtxgi_volume_set_probe_hysteresis(vol: &RtxgiVolume, value: Float32) -> Result[Unit, RtxgiError]
  requires: vol.raw != 0
{
  let rc = unsafe { rtxgib_volume_set_probe_hysteresis(vol.mod, vol.raw, value) } as Int;
  if rc == 0 { return Ok(()); }
  return Err(RtxgiError{ kind: rc; message: rtxgi_code_name(rc) });
}

pub fn rtxgi_volume_set_euler_angles(vol: &RtxgiVolume, x: Float32, y: Float32, z: Float32) -> Result[Unit, RtxgiError]
  requires: vol.raw != 0
{
  let rc = unsafe { rtxgib_volume_set_euler_angles(vol.mod, vol.raw, x, y, z) } as Int;
  if rc == 0 { return Ok(()); }
  return Err(RtxgiError{ kind: rc; message: rtxgi_code_name(rc) });
}

pub type RtxgiF3 = {
  x: Float32;
  y: Float32;
  z: Float32;
}

pub type RtxgiF4 = {
  x: Float32;
  y: Float32;
  z: Float32;
  w: Float32;
}

/// GetOrigin (scrolling-aware effective origin).  Complexity: O(1).
pub fn rtxgi_volume_get_origin(vol: &RtxgiVolume) -> Result[RtxgiF3, RtxgiError]
  requires: vol.raw != 0
{
  var slot = rtxgi_slot(12);
  let rc = unsafe { rtxgib_volume_get_origin(vol.mod, vol.raw, slot.as_mut_ptr()) } as Int;
  if rc != 0 { return Err(RtxgiError{ kind: rc; message: rtxgi_code_name(rc) }); }
  return Ok(RtxgiF3{ x: rtxgi_rd_f32(&slot, 0); y: rtxgi_rd_f32(&slot, 4); z: rtxgi_rd_f32(&slot, 8); });
}

/// GetDescGPU parsed into typed fields.  Complexity: O(1).
pub fn rtxgi_volume_gpu_desc(vol: &RtxgiVolume) -> Result[RtxgiGpuDesc, RtxgiError]
  requires: vol.raw != 0
{
  var slot = rtxgi_slot(RTXGI_GPU_DESC_SIZE);
  let rc = unsafe { rtxgib_volume_get_gpu_desc(vol.mod, vol.raw, slot.as_mut_ptr(), RTXGI_GPU_DESC_SIZE as Int32) } as Int;
  if rc != 0 { return Err(RtxgiError{ kind: rc; message: rtxgi_code_name(rc) }); }
  return Ok(rtxgi_parse_gpu_desc(&slot));
}

fn rtxgi_parse_gpu_desc(slot: &Vec[UInt8]) -> RtxgiGpuDesc
  requires: slot.len() >= RTXGI_GPU_DESC_SIZE
{
  return RtxgiGpuDesc{
    origin: RtxgiF3{ x: rtxgi_rd_f32(slot, 0); y: rtxgi_rd_f32(slot, 4); z: rtxgi_rd_f32(slot, 8); };
    rotation: RtxgiF4{ x: rtxgi_rd_f32(slot, 12); y: rtxgi_rd_f32(slot, 16); z: rtxgi_rd_f32(slot, 20); w: rtxgi_rd_f32(slot, 24); };
    probe_ray_rotation: RtxgiF4{ x: rtxgi_rd_f32(slot, 28); y: rtxgi_rd_f32(slot, 32); z: rtxgi_rd_f32(slot, 36); w: rtxgi_rd_f32(slot, 40); };
    movement_type: rtxgi_rd_u32(slot, 44);
    probe_spacing: RtxgiF3{ x: rtxgi_rd_f32(slot, 48); y: rtxgi_rd_f32(slot, 52); z: rtxgi_rd_f32(slot, 56); };
    count_x: rtxgi_rd_i32(slot, 60);
    count_y: rtxgi_rd_i32(slot, 64);
    count_z: rtxgi_rd_i32(slot, 68);
    probe_num_rays: rtxgi_rd_u32(slot, 72);
    irradiance_interior_texels: rtxgi_rd_u32(slot, 76);
    distance_interior_texels: rtxgi_rd_u32(slot, 80);
    probe_hysteresis: rtxgi_rd_f32(slot, 84);
    probe_max_ray_distance: rtxgi_rd_f32(slot, 88);
    probe_normal_bias: rtxgi_rd_f32(slot, 92);
    probe_view_bias: rtxgi_rd_f32(slot, 96);
    probe_distance_exponent: rtxgi_rd_f32(slot, 100);
    probe_irradiance_encoding_gamma: rtxgi_rd_f32(slot, 104);
    probe_irradiance_threshold: rtxgi_rd_f32(slot, 108);
    probe_brightness_threshold: rtxgi_rd_f32(slot, 112);
    probe_random_ray_backface_threshold: rtxgi_rd_f32(slot, 116);
    probe_fixed_ray_backface_threshold: rtxgi_rd_f32(slot, 120);
    probe_min_frontface_distance: rtxgi_rd_f32(slot, 124);
    scroll_x: rtxgi_rd_i32(slot, 128);
    scroll_y: rtxgi_rd_i32(slot, 132);
    scroll_z: rtxgi_rd_i32(slot, 136);
    scroll_clear_0: rtxgi_rd_u8(slot, 140);
    ray_data_format: rtxgi_rd_u32(slot, 148);
    irradiance_format: rtxgi_rd_u32(slot, 152);
    flags: rtxgi_rd_u32(slot, 156);
  };
}

pub type RtxgiGpuDesc = {
  origin: RtxgiF3;
  rotation: RtxgiF4;
  probe_ray_rotation: RtxgiF4;
  movement_type: Int;
  probe_spacing: RtxgiF3;
  count_x: Int;
  count_y: Int;
  count_z: Int;
  probe_num_rays: Int;
  irradiance_interior_texels: Int;
  distance_interior_texels: Int;
  probe_hysteresis: Float32;
  probe_max_ray_distance: Float32;
  probe_normal_bias: Float32;
  probe_view_bias: Float32;
  probe_distance_exponent: Float32;
  probe_irradiance_encoding_gamma: Float32;
  probe_irradiance_threshold: Float32;
  probe_brightness_threshold: Float32;
  probe_random_ray_backface_threshold: Float32;
  probe_fixed_ray_backface_threshold: Float32;
  probe_min_frontface_distance: Float32;
  scroll_x: Int;
  scroll_y: Int;
  scroll_z: Int;
  scroll_clear_0: Int;
  ray_data_format: Int;
  irradiance_format: Int;
  flags: Int;
}

/// GetDescGPUPacked: owned 128-byte image of the packed constants.
/// Complexity: O(1).
pub type RtxgiPacked = {
  size: Int;
  data: Vec[UInt8];
}

pub fn rtxgi_volume_gpu_desc_packed(vol: &RtxgiVolume) -> Result[RtxgiPacked, RtxgiError]
  requires: vol.raw != 0
{
  var slot = rtxgi_slot(RTXGI_PACKED_SIZE);
  let rc = unsafe { rtxgib_volume_get_gpu_desc_packed(vol.mod, vol.raw, slot.as_mut_ptr(), RTXGI_PACKED_SIZE as Int32) } as Int;
  if rc != 0 { return Err(RtxgiError{ kind: rc; message: rtxgi_code_name(rc) }); }
  return Ok(RtxgiPacked{ size: RTXGI_PACKED_SIZE; data: slot });
}

/// One u32 word of the packed image: `word_index` 0..4 selects packed0..packed4
/// (offsets 92, 96, 100, 104, 108 in the 128-byte image).  Complexity: O(1).
pub fn rtxgi_packed_word(packed: &RtxgiPacked, word_index: Int) -> Int
  requires: word_index >= 0
  requires: word_index < 5
  requires: packed.size == RTXGI_PACKED_SIZE
{
  return rtxgi_rd_u32(&packed.data, 92 + word_index * 4);
}

pub fn rtxgi_packed_f32(packed: &RtxgiPacked, packed_field: Int) -> Float32
  requires: packed_field >= 0
  requires: packed_field < RTXGI_PACKED_FIELD_COUNT
{
  // floats live at fixed offsets: 0 origin, 12 hysteresis, 16/32 quats,
  // 48..76 scalars, 80 spacing.
  if packed_field == RTXGI_PACKED_PROBE_HYSTERESIS { return rtxgi_rd_f32(&packed.data, 12); }
  if packed_field == RTXGI_PACKED_PROBE_MAX_RAY_DISTANCE { return rtxgi_rd_f32(&packed.data, 48); }
  if packed_field == RTXGI_PACKED_PROBE_NORMAL_BIAS { return rtxgi_rd_f32(&packed.data, 52); }
  if packed_field == RTXGI_PACKED_PROBE_VIEW_BIAS { return rtxgi_rd_f32(&packed.data, 56); }
  if packed_field == RTXGI_PACKED_PROBE_DISTANCE_EXPONENT { return rtxgi_rd_f32(&packed.data, 60); }
  if packed_field == RTXGI_PACKED_PROBE_IRRADIANCE_ENCODING_GAMMA { return rtxgi_rd_f32(&packed.data, 64); }
  if packed_field == RTXGI_PACKED_PROBE_IRRADIANCE_THRESHOLD { return rtxgi_rd_f32(&packed.data, 68); }
  if packed_field == RTXGI_PACKED_PROBE_BRIGHTNESS_THRESHOLD { return rtxgi_rd_f32(&packed.data, 72); }
  if packed_field == RTXGI_PACKED_PROBE_MIN_FRONTFACE_DISTANCE { return rtxgi_rd_f32(&packed.data, 76); }
  return 0 as Float32;
}

/// Probe counts decoded from a packed0 word (10/10/10 bits, LE bit order).
/// Complexity: O(1).
pub fn rtxgi_packed_counts_from_word(word0: Int) -> RtxgiI3
  requires: word0 >= 0
{
  return RtxgiI3{
    x: word0 & RTXGI_PACKED0_COUNT_MASK;
    y: (word0 >> RTXGI_PACKED0_COUNT_Y_SHIFT) & RTXGI_PACKED0_COUNT_MASK;
    z: (word0 >> RTXGI_PACKED0_COUNT_Z_SHIFT) & RTXGI_PACKED0_COUNT_MASK;
  };
}

/// Probe counts decoded from packed0 of an owned packed image.
/// Complexity: O(1).
pub fn rtxgi_packed_counts(packed: &RtxgiPacked) -> RtxgiI3
  requires: packed.size == RTXGI_PACKED_SIZE
{
  return rtxgi_packed_counts_from_word(rtxgi_rd_u32(&packed.data, 92));
}

pub fn rtxgi_volume_num_probes(vol: &RtxgiVolume) -> Result[Int, RtxgiError]
  requires: vol.raw != 0
{
  let rc = unsafe { rtxgib_volume_num_probes(vol.mod, vol.raw) } as Int;
  if rc < 0 { return Err(RtxgiError{ kind: rc; message: rtxgi_code_name(rc) }); }
  return Ok(rc);
}

pub fn rtxgi_volume_num_rays(vol: &RtxgiVolume) -> Result[Int, RtxgiError]
  requires: vol.raw != 0
{
  let rc = unsafe { rtxgib_volume_num_rays(vol.mod, vol.raw) } as Int;
  if rc < 0 { return Err(RtxgiError{ kind: rc; message: rtxgi_code_name(rc) }); }
  return Ok(rc);
}

pub fn rtxgi_volume_tex2darray_size(vol: &RtxgiVolume) -> Result[Int, RtxgiError]
  requires: vol.raw != 0
{
  let rc = unsafe { rtxgib_volume_tex2darray_size(vol.mod, vol.raw) } as Int;
  if rc < 0 { return Err(RtxgiError{ kind: rc; message: rtxgi_code_name(rc) }); }
  return Ok(rc);
}

pub fn rtxgi_volume_ray_dispatch(vol: &RtxgiVolume) -> Result[RtxgiI3, RtxgiError]
  requires: vol.raw != 0
{
  var slot = rtxgi_slot(12);
  let rc = unsafe { rtxgib_volume_ray_dispatch(vol.mod, vol.raw, slot.as_mut_ptr()) } as Int;
  if rc != 0 { return Err(RtxgiError{ kind: rc; message: rtxgi_code_name(rc) }); }
  return Ok(RtxgiI3{ x: rtxgi_rd_u32(&slot, 0); y: rtxgi_rd_u32(&slot, 4); z: rtxgi_rd_u32(&slot, 8); });
}

pub fn rtxgi_volume_gpu_memory(vol: &RtxgiVolume) -> Result[Int, RtxgiError]
  requires: vol.raw != 0
{
  let rc = unsafe { rtxgib_volume_gpu_memory(vol.mod, vol.raw) } as Int;
  if rc < 0 { return Err(RtxgiError{ kind: rc; message: rtxgi_code_name(rc) }); }
  return Ok(rc);
}

pub type RtxgiAabb = {
  min: RtxgiF3;
  max: RtxgiF3;
}

pub fn rtxgi_volume_aabb(vol: &RtxgiVolume) -> Result[RtxgiAabb, RtxgiError]
  requires: vol.raw != 0
{
  var slot = rtxgi_slot(24);
  let rc = unsafe { rtxgib_volume_aabb(vol.mod, vol.raw, slot.as_mut_ptr()) } as Int;
  if rc != 0 { return Err(RtxgiError{ kind: rc; message: rtxgi_code_name(rc) }); }
  return Ok(RtxgiAabb{
    min: RtxgiF3{ x: rtxgi_rd_f32(&slot, 0); y: rtxgi_rd_f32(&slot, 4); z: rtxgi_rd_f32(&slot, 8); };
    max: RtxgiF3{ x: rtxgi_rd_f32(&slot, 12); y: rtxgi_rd_f32(&slot, 16); z: rtxgi_rd_f32(&slot, 20); };
  });
}

pub type RtxgiObb = {
  origin: RtxgiF3;
  rotation: RtxgiF4;
  extent: RtxgiF3;
}

pub fn rtxgi_volume_obb(vol: &RtxgiVolume) -> Result[RtxgiObb, RtxgiError]
  requires: vol.raw != 0
{
  var slot = rtxgi_slot(40);
  let rc = unsafe { rtxgib_volume_obb(vol.mod, vol.raw, slot.as_mut_ptr()) } as Int;
  if rc != 0 { return Err(RtxgiError{ kind: rc; message: rtxgi_code_name(rc) }); }
  return Ok(RtxgiObb{
    origin: RtxgiF3{ x: rtxgi_rd_f32(&slot, 0); y: rtxgi_rd_f32(&slot, 4); z: rtxgi_rd_f32(&slot, 8); };
    rotation: RtxgiF4{ x: rtxgi_rd_f32(&slot, 12); y: rtxgi_rd_f32(&slot, 16); z: rtxgi_rd_f32(&slot, 20); w: rtxgi_rd_f32(&slot, 24); };
    extent: RtxgiF3{ x: rtxgi_rd_f32(&slot, 28); y: rtxgi_rd_f32(&slot, 32); z: rtxgi_rd_f32(&slot, 36); };
  });
}

pub fn rtxgi_volume_probe_world_pos(vol: &RtxgiVolume, probe_index: Int) -> Result[RtxgiF3, RtxgiError]
  requires: vol.raw != 0
  requires: probe_index >= 0
{
  var slot = rtxgi_slot(12);
  let rc = unsafe { rtxgib_volume_probe_world_pos(vol.mod, vol.raw, probe_index as Int32, slot.as_mut_ptr()) } as Int;
  if rc != 0 { return Err(RtxgiError{ kind: rc; message: rtxgi_code_name(rc) }); }
  return Ok(RtxgiF3{ x: rtxgi_rd_f32(&slot, 0); y: rtxgi_rd_f32(&slot, 4); z: rtxgi_rd_f32(&slot, 8); });
}

/// Execute the DDGI passes for a volume.  Requires an application-owned GPU
/// device bridge (D3D12/VK), probe resources and compiled shaders: out of
/// scope for 0.1.0, so this returns RTXGI_EXEC_NO_DEVICE (typed SKIP) for a
/// valid volume and RTXGI_EXEC_INVALID for bad arguments -- never a silent
/// success.  Complexity: O(1).
pub fn rtxgi_execute(vol: &RtxgiVolume) -> Int
  requires: true
{
  if vol.raw == 0 { return RTXGI_EXEC_INVALID; }
  return unsafe { rtxgib_execute(vol.mod, vol.raw) } as Int;
}
