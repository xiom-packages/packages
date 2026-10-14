// XIOM -- xiom.rtxdi: NVIDIA RTXDI (ReSTIR DI integration runtime) surface.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// DECISION (BINDINGS lane 2026-10-14): the upstream was expected to be MIT;
// verification in the clone found **NOT MIT** -- the RTXDI repository at its
// latest release (v3.1.0) and the RTXDI-Library runtime revision it pins for
// Libraries/Rtxdi (f12037fa) both ship the proprietary "NVIDIA RTX SDKs
// LICENSE" (LICENSE.txt; SPDX header `LicenseRef-NvidiaProprietary`; clauses
// 4(b)/4(e) forbid source redistribution and any open-source-license
// application).  Vendoring is therefore NOT allowed and this package follows
// the NRD/FFmpeg precedent (docs/BINDINGS-LANE.md sec. 4/11; docs/
// UPSTREAM-FIRST.md sec. 2): **reference-only, dynamic loader only** --
// independent XIOM code written against the public header declarations (the
// "declaration oracle", PROVENANCE.md) plus an XIOM-side bridge
// (src/rtxdi_bridge.cpp, ours) that resolution-loads a locally built shim
// module (the licensee's own build around the pinned runtime).  No RTXDI code,
// headers, shader blobs, or binaries ship in this repository.
//
// DECLARED surface (100% of the bound DI integration API, exercised by the
// suite):
//   * runtime utilities: CalculateReservoirBufferParameters,
//     ComputePdfTextureSize, FillNeighborOffsetBuffer, JenkinsHash +
//     CheckerboardMode;
//   * ReSTIRDIContext: create/destroy, frame index, resampling mode, and the
//     parameter set (reservoir buffer params, runtime params, buffer indices,
//     initial/temporal/boiling/spatial/spatio-temporal/shading params, static
//     params) with the seven GetDefault* constructors;
//   * light/instance buffer setup: RTXDI_LightBufferParameters regions,
//     RISBufferSegmentAllocator segments, ReGIRContext (grid + onion
//     calculated parameters, dynamic parameters);
//   * top-level ImportanceSamplingContext (context creation + light buffer
//     setup + RIS segments + neighbor offsets);
//   * frame plan composition (runtime params + buffer indices + reservoir
//     buffer params) for the small deterministic scene;
//   * typed errors; typed GPU-execution classification (RTXDI_EXEC_NO_DEVICE
//     SKIP -- running the DI passes needs the application's D3D12/VK device,
//     shaders and buffers; out of scope for 0.1.0).
//
// Explicit non-goals (SPEC.md): ReSTIR GI, ReSTIR PT and ReGIR presampling
// shader-side execution; device resource binding; any RTXDI artifact
// distribution (license).
//
// v0.64.4 FFI discipline (findings B-20/B-21/B-23/B-24/B-25/B-26):
//   * handles cross as `Int` params (B-25: no pointer casts from integers);
//   * every out-param is one XIOM-owned Vec[UInt8] slot, read byte-indexed
//     (B-17/B-24); XIOM never reads shim-owned memory (B-20);
//   * parameter images are owned XIOM bytes; layouts come from the bridge's
//     offsetof tables -- one single source of ABI truth -- and the suite
//     cross-checks them against the shim's real structs;
//   * nullable C args never receive the bare `null` literal (B-23);
//   * flat outcome structs only, never `Result[Option[T]]` (B-26).

module xiom.rtxdi

use xiom.convert;

// =========================================================================
// Identity / classification
// =========================================================================

/// Pinned upstream: RTXDI repository tag v3.1.0 (a6efab96) and the runtime
/// library revision it pins for Libraries/Rtxdi (f12037fa; the library
/// itself carries no version constant -- PROVENANCE.md).
pub const RTXDI_VERSION_MAJOR: Int = 3;
pub const RTXDI_VERSION_MINOR: Int = 1;
pub const RTXDI_VERSION_PATCH: Int = 0;

/// Load classification (mirrors the FFmpeg/NRD loader model).
pub const RTXDI_LOAD_ABSENT: Int = 0; // no shim module -> SKIP
pub const RTXDI_LOAD_ABI: Int = 1;    // module loaded but entry points missing -> FAIL
pub const RTXDI_LOAD_OK: Int = 2;

/// Bridge status codes (src/rtxdi_bridge.cpp).
pub const RTXDI_ERR_NOT_LOADED: Int = 100;
pub const RTXDI_ERR_BAD_ARGS: Int = 101;
pub const RTXDI_ERR_SIZE: Int = 102;
pub const RTXDI_ERR_CAPACITY: Int = 103;

/// Execute-path classification (device owner is the application).
pub const RTXDI_EXEC_OK: Int = 0;
pub const RTXDI_EXEC_INVALID: Int = 1;
pub const RTXDI_EXEC_NO_DEVICE: Int = 2;

// =========================================================================
// Constants (RtxdiParameters.h / ReSTIRDI.h / ReGIRParameters.h)
// =========================================================================

pub const RTXDI_RESERVOIR_BLOCK_SIZE: Int = 16;
pub const RTXDI_TILE_SIZE_IN_PIXELS: Int = 16;
pub const RTXDI_ONION_MAX_LAYER_GROUPS: Int = 8;
pub const RTXDI_ONION_MAX_RINGS: Int = 52;
pub const RTXDI_NAIVE_SAMPLING_M_THRESHOLD: Int = 2;
/// RTXDI_LIGHT_COMPACT_BIT = 0x80000000 (bit 31 of lightData).
pub const RTXDI_LIGHT_COMPACT_BIT: Int = 2147483648;
pub const RTXDI_LIGHT_INDEX_MASK: Int = 2147483647;
/// RTXDI_INVALID_LIGHT_INDEX = 0xFFFFFFFF.
pub const RTXDI_INVALID_LIGHT_INDEX: Int = 4294967295;
pub const RTXDI_ENABLE_PRESAMPLING: Int = 1;
pub const RTXDI_REGIR_MODE: Int = 0;
pub const RTXDI_NUM_RESERVOIR_BUFFERS: Int = 3;

/// Pinned mirror struct sizes (present-path shim cross-checks).
pub const RTXDI_SIZE_RESERVOIR: Int = 16;
pub const RTXDI_SIZE_RUNTIME: Int = 16;
pub const RTXDI_SIZE_BUFFER_INDICES: Int = 32;
pub const RTXDI_SIZE_INITIAL: Int = 48;
pub const RTXDI_SIZE_TEMPORAL: Int = 32;
pub const RTXDI_SIZE_BOILING: Int = 16;
pub const RTXDI_SIZE_SPATIAL: Int = 48;
pub const RTXDI_SIZE_SPATIOTEMPORAL: Int = 48;
pub const RTXDI_SIZE_SHADING: Int = 32;
pub const RTXDI_SIZE_PARAMETERS: Int = 272;
pub const RTXDI_SIZE_LIGHT_BUFFER: Int = 48;
pub const RTXDI_SIZE_LIGHT_REGION: Int = 16;
pub const RTXDI_SIZE_ENV_LIGHT: Int = 16;
pub const RTXDI_SIZE_PACKED_RESERVOIR: Int = 24;
pub const RTXDI_SIZE_RIS_SEGMENT: Int = 16;
pub const RTXDI_SIZE_DI_STATIC: Int = 16;
pub const RTXDI_SIZE_REGIR_COMMON: Int = 48;
pub const RTXDI_SIZE_REGIR_GRID: Int = 16;
pub const RTXDI_SIZE_ONION_LAYER: Int = 48;
pub const RTXDI_SIZE_ONION_RING: Int = 16;
pub const RTXDI_SIZE_ONION_PARAMETERS: Int = 1232;
pub const RTXDI_SIZE_REGIR_PARAMETERS: Int = 1296;
pub const RTXDI_SLACK: Int = 64;

/// CheckerboardMode.
pub const RTXDI_CHECKERBOARD_OFF: Int = 0;
pub const RTXDI_CHECKERBOARD_BLACK: Int = 1;
pub const RTXDI_CHECKERBOARD_WHITE: Int = 2;

/// ReSTIRDI_LocalLightSamplingMode.
pub const RTXDI_LOCAL_LIGHT_UNIFORM: Int = 0;
pub const RTXDI_LOCAL_LIGHT_POWER_RIS: Int = 1;
pub const RTXDI_LOCAL_LIGHT_REGIR_RIS: Int = 2;

/// Bias-correction modes (shared encodings).
pub const RTXDI_BIAS_CORRECTION_OFF: Int = 0;
pub const RTXDI_BIAS_CORRECTION_BASIC: Int = 1;
pub const RTXDI_BIAS_CORRECTION_PAIRWISE: Int = 3;
pub const RTXDI_BIAS_CORRECTION_RAY_TRACED: Int = 2;

/// ReSTIRDI_ResamplingMode.
pub const RTXDI_RESAMPLING_NONE: Int = 0;
pub const RTXDI_RESAMPLING_TEMPORAL: Int = 1;
pub const RTXDI_RESAMPLING_SPATIAL: Int = 2;
pub const RTXDI_RESAMPLING_SPATIOTEMPORAL: Int = 3;
pub const RTXDI_RESAMPLING_FUSED_SPATIOTEMPORAL: Int = 4;

/// ReGIRMode / presampling / fallback modes.
pub const RTXDI_REGIR_DISABLED: Int = 0;
pub const RTXDI_REGIR_GRID: Int = 1;
pub const RTXDI_REGIR_ONION: Int = 2;
pub const RTXDI_REGIR_PRESAMPLING_UNIFORM: Int = 0;
pub const RTXDI_REGIR_PRESAMPLING_POWER_RIS: Int = 1;

/// Layout kinds for rtxdi_layout().
pub const RTXDI_LAYOUT_RESERVOIR: Int = 0;
pub const RTXDI_LAYOUT_RUNTIME: Int = 1;
pub const RTXDI_LAYOUT_BUFFER_INDICES: Int = 2;
pub const RTXDI_LAYOUT_INITIAL: Int = 3;
pub const RTXDI_LAYOUT_TEMPORAL: Int = 4;
pub const RTXDI_LAYOUT_BOILING: Int = 5;
pub const RTXDI_LAYOUT_SPATIAL: Int = 6;
pub const RTXDI_LAYOUT_SPATIOTEMPORAL: Int = 7;
pub const RTXDI_LAYOUT_SHADING: Int = 8;
pub const RTXDI_LAYOUT_LIGHT_REGION: Int = 9;
pub const RTXDI_LAYOUT_ENV_LIGHT: Int = 10;
pub const RTXDI_LAYOUT_LIGHT_BUFFER: Int = 11;
pub const RTXDI_LAYOUT_PACKED_RESERVOIR: Int = 12;
pub const RTXDI_LAYOUT_RIS_SEGMENT: Int = 13;
pub const RTXDI_LAYOUT_DI_STATIC: Int = 14;
pub const RTXDI_LAYOUT_REGIR_COMMON: Int = 15;
pub const RTXDI_LAYOUT_REGIR_GRID: Int = 16;
pub const RTXDI_LAYOUT_ONION_LAYER: Int = 17;
pub const RTXDI_LAYOUT_ONION_RING: Int = 18;
pub const RTXDI_LAYOUT_PARAMETERS: Int = 19;

/// GetDefault* kinds (bridge defaults + SDK comparison).
pub const RTXDI_DEFAULT_BUFFER_INDICES: Int = 0;
pub const RTXDI_DEFAULT_INITIAL: Int = 1;
pub const RTXDI_DEFAULT_TEMPORAL: Int = 2;
pub const RTXDI_DEFAULT_BOILING: Int = 3;
pub const RTXDI_DEFAULT_SPATIAL: Int = 4;
pub const RTXDI_DEFAULT_SPATIOTEMPORAL: Int = 5;
pub const RTXDI_DEFAULT_SHADING: Int = 6;

/// ReSTIRDIContext::Get* part indexes.
pub const RTXDI_PART_RESERVOIR: Int = 0;
pub const RTXDI_PART_RUNTIME: Int = 1;
pub const RTXDI_PART_BUFFER_INDICES: Int = 2;
pub const RTXDI_PART_INITIAL: Int = 3;
pub const RTXDI_PART_TEMPORAL: Int = 4;
pub const RTXDI_PART_BOILING: Int = 5;
pub const RTXDI_PART_SPATIAL: Int = 6;
pub const RTXDI_PART_SPATIOTEMPORAL: Int = 7;
pub const RTXDI_PART_SHADING: Int = 8;
pub const RTXDI_PART_DI_STATIC: Int = 9;

// Field indexes (declaration order; the bridge layout tables are the ABI truth).
pub const RTXDI_F_RESERVOIR_ROW_PITCH: Int = 0;
pub const RTXDI_F_RESERVOIR_ARRAY_PITCH: Int = 1;

pub const RTXDI_F_RUNTIME_NEIGHBOR_MASK: Int = 0;
pub const RTXDI_F_RUNTIME_CHECKERBOARD_FIELD: Int = 1;
pub const RTXDI_F_RUNTIME_FRAME_INDEX: Int = 2;

pub const RTXDI_F_INDICES_INITIAL_OUT: Int = 0;
pub const RTXDI_F_INDICES_TEMPORAL_IN: Int = 1;
pub const RTXDI_F_INDICES_TEMPORAL_OUT: Int = 2;
pub const RTXDI_F_INDICES_SPATIAL_IN: Int = 3;
pub const RTXDI_F_INDICES_SPATIAL_OUT: Int = 4;
pub const RTXDI_F_INDICES_SHADING_IN: Int = 5;

pub const RTXDI_F_INITIAL_NUM_LOCAL: Int = 0;
pub const RTXDI_F_INITIAL_NUM_INFINITE: Int = 1;
pub const RTXDI_F_INITIAL_NUM_ENV: Int = 2;
pub const RTXDI_F_INITIAL_NUM_BRDF: Int = 3;
pub const RTXDI_F_INITIAL_BRDF_CUTOFF: Int = 4;
pub const RTXDI_F_INITIAL_BRDF_RAY_MIN_T: Int = 5;
pub const RTXDI_F_INITIAL_LOCAL_LIGHT_MODE: Int = 6;
pub const RTXDI_F_INITIAL_ENABLE_VISIBILITY: Int = 7;
pub const RTXDI_F_INITIAL_ENV_MAP_IMPORTANCE: Int = 8;

pub const RTXDI_F_TEMPORAL_MAX_HISTORY: Int = 0;
pub const RTXDI_F_TEMPORAL_BIAS_MODE: Int = 1;
pub const RTXDI_F_TEMPORAL_DEPTH_THRESHOLD: Int = 2;
pub const RTXDI_F_TEMPORAL_NORMAL_THRESHOLD: Int = 3;
pub const RTXDI_F_TEMPORAL_VISIBILITY_SHORTCUT: Int = 4;
pub const RTXDI_F_TEMPORAL_PERMUTATION: Int = 5;
pub const RTXDI_F_TEMPORAL_UNIFORM_RANDOM: Int = 6;
pub const RTXDI_F_TEMPORAL_PERMUTATION_THRESHOLD: Int = 7;

pub const RTXDI_F_BOILING_ENABLE: Int = 0;
pub const RTXDI_F_BOILING_STRENGTH: Int = 1;

pub const RTXDI_F_SPATIAL_NUM_SAMPLES: Int = 0;
pub const RTXDI_F_SPATIAL_NUM_DISOC_BOOST: Int = 1;
pub const RTXDI_F_SPATIAL_SAMPLING_RADIUS: Int = 2;
pub const RTXDI_F_SPATIAL_BIAS_MODE: Int = 3;
pub const RTXDI_F_SPATIAL_DEPTH_THRESHOLD: Int = 4;
pub const RTXDI_F_SPATIAL_NORMAL_THRESHOLD: Int = 5;
pub const RTXDI_F_SPATIAL_TARGET_HISTORY: Int = 6;
pub const RTXDI_F_SPATIAL_MATERIAL_TEST: Int = 7;
pub const RTXDI_F_SPATIAL_DISCOUNT_NAIVE: Int = 8;

pub const RTXDI_F_ST_DEPTH_THRESHOLD: Int = 0;
pub const RTXDI_F_ST_NORMAL_THRESHOLD: Int = 1;
pub const RTXDI_F_ST_BIAS_MODE: Int = 2;
pub const RTXDI_F_ST_MAX_HISTORY: Int = 3;
pub const RTXDI_F_ST_PERMUTATION: Int = 4;
pub const RTXDI_F_ST_UNIFORM_RANDOM: Int = 5;
pub const RTXDI_F_ST_VISIBILITY_SHORTCUT: Int = 6;
pub const RTXDI_F_ST_NUM_SAMPLES: Int = 7;
pub const RTXDI_F_ST_NUM_DISOC_BOOST: Int = 8;
pub const RTXDI_F_ST_SAMPLING_RADIUS: Int = 9;
pub const RTXDI_F_ST_MATERIAL_TEST: Int = 10;
pub const RTXDI_F_ST_DISCOUNT_NAIVE: Int = 11;

pub const RTXDI_F_SHADING_ENABLE_FINAL_VISIBILITY: Int = 0;
pub const RTXDI_F_SHADING_REUSE_FINAL_VISIBILITY: Int = 1;
pub const RTXDI_F_SHADING_FINAL_VISIBILITY_MAX_AGE: Int = 2;
pub const RTXDI_F_SHADING_FINAL_VISIBILITY_MAX_DISTANCE: Int = 3;
pub const RTXDI_F_SHADING_DENOISER_INPUT_PACKING: Int = 4;

pub const RTXDI_F_LIGHT_REGION_FIRST: Int = 0;
pub const RTXDI_F_LIGHT_REGION_COUNT: Int = 1;
pub const RTXDI_F_ENV_LIGHT_PRESENT: Int = 0;
pub const RTXDI_F_ENV_LIGHT_INDEX: Int = 1;
pub const RTXDI_F_LIGHT_BUFFER_LOCAL: Int = 0;
pub const RTXDI_F_LIGHT_BUFFER_INFINITE: Int = 1;
pub const RTXDI_F_LIGHT_BUFFER_ENV: Int = 2;

pub const RTXDI_F_PACKED_LIGHT_DATA: Int = 0;
pub const RTXDI_F_PACKED_UV_DATA: Int = 1;
pub const RTXDI_F_PACKED_VISIBILITY: Int = 2;
pub const RTXDI_F_PACKED_DISTANCE_AGE: Int = 3;
pub const RTXDI_F_PACKED_TARGET_PDF: Int = 4;
pub const RTXDI_F_PACKED_WEIGHT: Int = 5;

pub const RTXDI_F_RIS_SEGMENT_OFFSET: Int = 0;
pub const RTXDI_F_RIS_SEGMENT_TILE_SIZE: Int = 1;
pub const RTXDI_F_RIS_SEGMENT_TILE_COUNT: Int = 2;

pub const RTXDI_F_DI_STATIC_NEIGHBOR_COUNT: Int = 0;
pub const RTXDI_F_DI_STATIC_WIDTH: Int = 1;
pub const RTXDI_F_DI_STATIC_HEIGHT: Int = 2;
pub const RTXDI_F_DI_STATIC_CHECKERBOARD: Int = 3;

pub const RTXDI_F_REGIR_COMMON_FALLBACK: Int = 0;
pub const RTXDI_F_REGIR_COMMON_CENTER_X: Int = 1;
pub const RTXDI_F_REGIR_COMMON_CENTER_Y: Int = 2;
pub const RTXDI_F_REGIR_COMMON_CENTER_Z: Int = 3;
pub const RTXDI_F_REGIR_COMMON_RIS_OFFSET: Int = 4;
pub const RTXDI_F_REGIR_COMMON_LIGHTS_PER_CELL: Int = 5;
pub const RTXDI_F_REGIR_COMMON_CELL_SIZE: Int = 6;
pub const RTXDI_F_REGIR_COMMON_JITTER: Int = 7;
pub const RTXDI_F_REGIR_COMMON_PRESAMPLING: Int = 8;
pub const RTXDI_F_REGIR_COMMON_NUM_BUILD_SAMPLES: Int = 9;

pub const RTXDI_F_REGIR_GRID_X: Int = 0;
pub const RTXDI_F_REGIR_GRID_Y: Int = 1;
pub const RTXDI_F_REGIR_GRID_Z: Int = 2;

pub const RTXDI_F_ONION_LAYER_INNER_RADIUS: Int = 0;
pub const RTXDI_F_ONION_LAYER_OUTER_RADIUS: Int = 1;
pub const RTXDI_F_ONION_LAYER_INV_LOG_SCALE: Int = 2;
pub const RTXDI_F_ONION_LAYER_LAYER_COUNT: Int = 3;
pub const RTXDI_F_ONION_LAYER_INV_EQ_CELL_ANGLE: Int = 4;
pub const RTXDI_F_ONION_LAYER_CELLS_PER_LAYER: Int = 5;
pub const RTXDI_F_ONION_LAYER_RING_OFFSET: Int = 6;
pub const RTXDI_F_ONION_LAYER_RING_COUNT: Int = 7;
pub const RTXDI_F_ONION_LAYER_EQ_CELL_ANGLE: Int = 8;
pub const RTXDI_F_ONION_LAYER_LAYER_SCALE: Int = 9;
pub const RTXDI_F_ONION_LAYER_CELL_OFFSET: Int = 10;

pub const RTXDI_F_ONION_RING_CELL_ANGLE: Int = 0;
pub const RTXDI_F_ONION_RING_INV_CELL_ANGLE: Int = 1;
pub const RTXDI_F_ONION_RING_CELL_OFFSET: Int = 2;
pub const RTXDI_F_ONION_RING_CELL_COUNT: Int = 3;

// ImportanceSamplingContext static-params image (60 bytes; bridge/shim contract).
pub const RTXDI_IS_IMAGE_SIZE: Int = 60;
pub const RTXDI_IS_IMAGE_WIDTH: Int = 0;
pub const RTXDI_IS_IMAGE_HEIGHT: Int = 4;
pub const RTXDI_IS_IMAGE_CHECKERBOARD: Int = 8;
pub const RTXDI_IS_IMAGE_NEIGHBOR_COUNT: Int = 12;
pub const RTXDI_IS_IMAGE_LOCAL_TILE_SIZE: Int = 16;
pub const RTXDI_IS_IMAGE_LOCAL_TILE_COUNT: Int = 20;
pub const RTXDI_IS_IMAGE_ENV_TILE_SIZE: Int = 24;
pub const RTXDI_IS_IMAGE_ENV_TILE_COUNT: Int = 28;
pub const RTXDI_IS_IMAGE_REGIR_MODE: Int = 32;
pub const RTXDI_IS_IMAGE_GRID_X: Int = 36;
pub const RTXDI_IS_IMAGE_GRID_Y: Int = 40;
pub const RTXDI_IS_IMAGE_GRID_Z: Int = 44;
pub const RTXDI_IS_IMAGE_LIGHTS_PER_CELL: Int = 48;
pub const RTXDI_IS_IMAGE_ONION_DETAIL: Int = 52;
pub const RTXDI_IS_IMAGE_ONION_COVERAGE: Int = 56;

// ReGIR onion calculated-parameters image (1240 bytes; shim/bridge contract).
pub const RTXDI_ONION_IMAGE_HEADER: Int = 24;
pub const RTXDI_ONION_IMAGE_LAYERS_OFFSET: Int = 24;
pub const RTXDI_ONION_IMAGE_RINGS_OFFSET: Int = 408;
pub const RTXDI_ONION_IMAGE_SIZE: Int = 1240;
pub const RTXDI_ONION_IMAGE_NUM_LAYERS: Int = 0;
pub const RTXDI_ONION_IMAGE_NUM_RINGS: Int = 4;
pub const RTXDI_ONION_IMAGE_CUBIC_ROOT: Int = 8;
pub const RTXDI_ONION_IMAGE_LINEAR: Int = 12;
pub const RTXDI_ONION_IMAGE_CELLS: Int = 16;
pub const RTXDI_ONION_IMAGE_LIGHT_SLOTS: Int = 20;

// ReGIR dynamic-params image (32 bytes; shim/bridge contract).
pub const RTXDI_REGIR_DYNAMIC_SIZE: Int = 32;
pub const RTXDI_REGIR_DYNAMIC_CELL_SIZE: Int = 0;
pub const RTXDI_REGIR_DYNAMIC_CENTER_X: Int = 4;
pub const RTXDI_REGIR_DYNAMIC_CENTER_Y: Int = 8;
pub const RTXDI_REGIR_DYNAMIC_CENTER_Z: Int = 12;
pub const RTXDI_REGIR_DYNAMIC_FALLBACK: Int = 16;
pub const RTXDI_REGIR_DYNAMIC_PRESAMPLING: Int = 20;
pub const RTXDI_REGIR_DYNAMIC_JITTER: Int = 24;
pub const RTXDI_REGIR_DYNAMIC_NUM_BUILD_SAMPLES: Int = 28;

// =========================================================================
// FFI: the XIOM-side bridge (src/rtxdi_bridge.cpp; ours)
// =========================================================================

extern "C" {
  fn rtxdib_try_load(path: *UInt8, len: Int32) -> Int;
  fn rtxdib_try_load_auto() -> Int;
  fn rtxdib_load_kind() -> Int32;
  fn rtxdib_close(h: Int) -> Int32;

  fn rtxdib_layout(kind: Int32, offsets: *UInt8, sizes: *UInt8, cap: Int32) -> Int32;
  fn rtxdib_layout_size(kind: Int32) -> Int32;
  fn rtxdib_param_default(kind: Int32, dst: *UInt8, cap: Int32) -> Int32;

  fn rtxdib_info(h: Int, out: *UInt8, cap: Int32) -> Int32;
  fn rtxdib_sdk_layout(h: Int, kind: Int32, out: *UInt8, cap: Int32) -> Int32;
  fn rtxdib_sdk_param_default(h: Int, kind: Int32, dst: *UInt8, cap: Int32) -> Int32;
  fn rtxdib_utils_reservoir_params(h: Int, width: UInt32, height: UInt32, checkerboard: Int32, out16: *UInt8) -> Int32;
  fn rtxdib_utils_pdf_size(h: Int, max_items: UInt32, out12: *UInt8) -> Int32;
  fn rtxdib_utils_fill_neighbor_offsets(h: Int, count: UInt32, out: *UInt8, cap: Int32) -> Int32;
  fn rtxdib_utils_jenkins_hash(h: Int, a: UInt32) -> Int;

  fn rtxdib_di_create(h: Int, width: UInt32, height: UInt32, checkerboard: Int32, neighbor_offset_count: UInt32, out8: *UInt8) -> Int32;
  fn rtxdib_di_destroy(h: Int, ctx: Int) -> Int32;
  fn rtxdib_di_get(h: Int, part: Int32, ctx: Int, out: *UInt8, cap: Int32) -> Int32;
  fn rtxdib_di_set(h: Int, part: Int32, ctx: Int, img: *UInt8, size: Int32) -> Int32;
  fn rtxdib_di_set_frame_index(h: Int, ctx: Int, frame_index: UInt32) -> Int32;
  fn rtxdib_di_get_frame_index(h: Int, ctx: Int, out4: *UInt8) -> Int32;
  fn rtxdib_di_set_resampling_mode(h: Int, ctx: Int, mode: Int32) -> Int32;
  fn rtxdib_di_get_resampling_mode(h: Int, ctx: Int) -> Int32;

  fn rtxdib_ris_create(h: Int, out8: *UInt8) -> Int32;
  fn rtxdib_ris_destroy(h: Int, ris: Int) -> Int32;
  fn rtxdib_ris_allocate(h: Int, ris: Int, size: UInt32, out4: *UInt8) -> Int32;
  fn rtxdib_ris_total(h: Int, ris: Int, out4: *UInt8) -> Int32;

  fn rtxdib_regir_create(h: Int, ris: Int, mode: Int32, gx: UInt32, gy: UInt32, gz: UInt32, lights_per_cell: UInt32, onion_detail: UInt32, onion_coverage: UInt32, out8: *UInt8) -> Int32;
  fn rtxdib_regir_destroy(h: Int, ctx: Int) -> Int32;
  fn rtxdib_regir_cell_offset(h: Int, ctx: Int, out4: *UInt8) -> Int32;
  fn rtxdib_regir_light_slots(h: Int, ctx: Int, out4: *UInt8) -> Int32;
  fn rtxdib_regir_get_grid(h: Int, ctx: Int, out16: *UInt8) -> Int32;
  fn rtxdib_regir_get_onion(h: Int, ctx: Int, out: *UInt8, cap: Int32) -> Int32;
  fn rtxdib_regir_get_dynamic(h: Int, ctx: Int, out32: *UInt8) -> Int32;
  fn rtxdib_regir_set_dynamic(h: Int, ctx: Int, img: *UInt8, size: Int32) -> Int32;
  fn rtxdib_regir_power_ris(h: Int, ctx: Int) -> Int32;

  fn rtxdib_is_create(h: Int, img: *UInt8, size: Int32, out8: *UInt8) -> Int32;
  fn rtxdib_is_destroy(h: Int, ctx: Int) -> Int32;
  fn rtxdib_is_di(h: Int, ctx: Int, out8: *UInt8) -> Int32;
  fn rtxdib_is_regir(h: Int, ctx: Int, out8: *UInt8) -> Int32;
  fn rtxdib_is_ris(h: Int, ctx: Int, out8: *UInt8) -> Int32;
  fn rtxdib_is_ris_total(h: Int, ctx: Int, out4: *UInt8) -> Int32;
  fn rtxdib_is_light_buffer(h: Int, ctx: Int, out48: *UInt8) -> Int32;
  fn rtxdib_is_set_light_buffer(h: Int, ctx: Int, img: *UInt8, size: Int32) -> Int32;
  fn rtxdib_is_local_ris(h: Int, ctx: Int, out16: *UInt8) -> Int32;
  fn rtxdib_is_env_ris(h: Int, ctx: Int, out16: *UInt8) -> Int32;
  fn rtxdib_is_neighbor_count(h: Int, ctx: Int, out4: *UInt8) -> Int32;
  fn rtxdib_is_power_ris(h: Int, ctx: Int) -> Int32;
  fn rtxdib_is_regir_enabled(h: Int, ctx: Int) -> Int32;

  fn rtxdib_img_set_u32(dst: *UInt8, cap: Int32, off: Int32, v: Int32) -> Int32;
  fn rtxdib_img_set_f32(dst: *UInt8, cap: Int32, off: Int32, v: Float32) -> Int32;
  fn rtxdib_img_get_u32(src: *UInt8, cap: Int32, off: Int32) -> Int32;
  fn rtxdib_img_get_f32(src: *UInt8, cap: Int32, off: Int32) -> Float32;
}

// =========================================================================
// Owned-slot helpers (B-17/B-24)
// =========================================================================

fn rtxdi_slot(n: Int) -> Vec[UInt8]
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

/// Unsigned 32-bit read of an owned image word (bridge returns the raw
/// little-endian word as int32; re-widen to [0, 2^32)).
fn rtxdi_rd_u32(buf: &Vec[UInt8], off: Int) -> Int
  requires: off >= 0
  requires: buf.len() >= off + 4
{
  let raw = unsafe { rtxdib_img_get_u32(buf.as_ptr(), buf.len() as Int32, off as Int32) } as Int;
  if raw < 0 { return raw + 4294967296; }
  return raw;
}

fn rtxdi_rd_i32(buf: &Vec[UInt8], off: Int) -> Int
  requires: off >= 0
  requires: buf.len() >= off + 4
{
  let raw = rtxdi_rd_u32(buf, off);
  if raw >= 2147483648 { return raw - 4294967296; }
  return raw;
}

fn rtxdi_rd_f32(buf: &Vec[UInt8], off: Int) -> Float32
  requires: off >= 0
  requires: buf.len() >= off + 4
{
  return unsafe { rtxdib_img_get_f32(buf.as_ptr(), buf.len() as Int32, off as Int32) };
}

fn rtxdi_wr_u32(dst: &mut Vec[UInt8], off: Int, v: Int) -> Result[Unit, RtxdiError]
  requires: off >= 0
  requires: dst.len() >= off + 4
{
  let rc = unsafe { rtxdib_img_set_u32(dst.as_mut_ptr(), dst.len() as Int32, off as Int32, v as Int32) } as Int;
  if rc != 0 { return Err(RtxdiError{ kind: rc; message: rtxdi_code_name(rc) }); }
  return Ok(());
}

fn rtxdi_wr_f32(dst: &mut Vec[UInt8], off: Int, v: Float32) -> Result[Unit, RtxdiError]
  requires: off >= 0
  requires: dst.len() >= off + 4
{
  let rc = unsafe { rtxdib_img_set_f32(dst.as_mut_ptr(), dst.len() as Int32, off as Int32, v) } as Int;
  if rc != 0 { return Err(RtxdiError{ kind: rc; message: rtxdi_code_name(rc) }); }
  return Ok(());
}

pub fn rtxdi_sign_i32(v: Int) -> Int
  requires: v >= 0
{
  if v >= 2147483648 { return v - 4294967296; }
  return v;
}

fn rtxdi_code_name(code: Int) -> Str
  requires: true
{
  if code == RTXDI_ERR_NOT_LOADED { return "bridge: not loaded"; }
  if code == RTXDI_ERR_BAD_ARGS { return "bridge: bad args"; }
  if code == RTXDI_ERR_SIZE { return "bridge: owned image smaller than the ABI mirror"; }
  if code == RTXDI_ERR_CAPACITY { return "bridge: out slot too small"; }
  return "code " + convert.int_to_string(code);
}

// =========================================================================
// Loader
// =========================================================================

pub type RtxdiError = {
  kind: Int;
  message: Str;
}

pub type RtxdiModule = {
  h: Int;
}

/// Load the RTXDI shim: `XIOM_RTXDI_SHIM` env var first, then the default
/// module search.  Err(RTXDI_LOAD_ABSENT) when no module is present (the
/// classified SKIP path).  Complexity: O(1) after the load.
pub fn rtxdi_load() -> Result[RtxdiModule, RtxdiError]
  requires: true
{
  let h = unsafe { rtxdib_try_load_auto() };
  if h == 0 {
    if unsafe { rtxdib_load_kind() } as Int == RTXDI_LOAD_ABI {
      return Err(RtxdiError{ kind: RTXDI_LOAD_ABI; message: "module loaded but the RTXDI shim entry points are missing" });
    }
    return Err(RtxdiError{ kind: RTXDI_LOAD_ABSENT; message: "xiom_rtxdi_shim.dll not found (XIOM_RTXDI_SHIM / default search)" });
  }
  return Ok(RtxdiModule{ h: h });
}

/// Load one named module path (deterministic SKIP-path probe).
/// Complexity: O(1) after the load.
pub fn rtxdi_load_named(path: Str) -> Result[RtxdiModule, RtxdiError]
  requires: path.len() > 0
{
  let h = unsafe { rtxdib_try_load(path as *UInt8, path.len() as Int32) };
  if h == 0 {
    if unsafe { rtxdib_load_kind() } as Int == RTXDI_LOAD_ABI {
      return Err(RtxdiError{ kind: RTXDI_LOAD_ABI; message: path + ": entry points missing" });
    }
    return Err(RtxdiError{ kind: RTXDI_LOAD_ABSENT; message: path + ": module not found" });
  }
  return Ok(RtxdiModule{ h: h });
}

/// Unload the shim module.  Complexity: O(1).
pub fn rtxdi_close(mod: &RtxdiModule) -> Result[Unit, RtxdiError]
  requires: mod.h != 0
{
  let rc = unsafe { rtxdib_close(mod.h) } as Int;
  if rc == 0 { return Ok(()); }
  return Err(RtxdiError{ kind: rc; message: rtxdi_code_name(rc) });
}

// =========================================================================
// Shim info + layout tables + defaults
// =========================================================================

pub type RtxdiShimInfo = {
  size_reservoir: Int;
  size_runtime: Int;
  size_buffer_indices: Int;
  size_initial: Int;
  size_temporal: Int;
  size_boiling: Int;
  size_spatial: Int;
  size_spatiotemporal: Int;
  size_shading: Int;
  size_parameters: Int;
  size_light_buffer: Int;
  size_light_region: Int;
  size_env_light: Int;
  size_packed_reservoir: Int;
  size_ris_segment: Int;
  size_di_static: Int;
  block_size: Int;
  tile_size: Int;
  onion_max_groups: Int;
  onion_max_rings: Int;
  naive_threshold: Int;
  light_compact_bit: Int;
  light_index_mask: Int;
  invalid_light_index: Int;
  size_onion_layer: Int;
  size_onion_ring: Int;
  size_regir_common: Int;
  size_regir_grid: Int;
  size_regir_parameters: Int;
  regir_mode_default: Int;
  presampling: Int;
  num_reservoir_buffers: Int;
  size_onion_parameters: Int;
}

/// The shim's struct sizes + constant values (drift guard vs the pinned
/// constants in this module).  Complexity: O(1).
pub fn rtxdi_info(mod: &RtxdiModule) -> Result[RtxdiShimInfo, RtxdiError]
  requires: mod.h != 0
{
  var slot = rtxdi_slot(132);
  let rc = unsafe { rtxdib_info(mod.h, slot.as_mut_ptr(), 132) } as Int;
  if rc != 0 { return Err(RtxdiError{ kind: rc; message: rtxdi_code_name(rc) }); }
  return Ok(RtxdiShimInfo{
    size_reservoir: rtxdi_rd_u32(&slot, 0);
    size_runtime: rtxdi_rd_u32(&slot, 4);
    size_buffer_indices: rtxdi_rd_u32(&slot, 8);
    size_initial: rtxdi_rd_u32(&slot, 12);
    size_temporal: rtxdi_rd_u32(&slot, 16);
    size_boiling: rtxdi_rd_u32(&slot, 20);
    size_spatial: rtxdi_rd_u32(&slot, 24);
    size_spatiotemporal: rtxdi_rd_u32(&slot, 28);
    size_shading: rtxdi_rd_u32(&slot, 32);
    size_parameters: rtxdi_rd_u32(&slot, 36);
    size_light_buffer: rtxdi_rd_u32(&slot, 40);
    size_light_region: rtxdi_rd_u32(&slot, 44);
    size_env_light: rtxdi_rd_u32(&slot, 48);
    size_packed_reservoir: rtxdi_rd_u32(&slot, 52);
    size_ris_segment: rtxdi_rd_u32(&slot, 56);
    size_di_static: rtxdi_rd_u32(&slot, 60);
    block_size: rtxdi_rd_u32(&slot, 64);
    tile_size: rtxdi_rd_u32(&slot, 68);
    onion_max_groups: rtxdi_rd_u32(&slot, 72);
    onion_max_rings: rtxdi_rd_u32(&slot, 76);
    naive_threshold: rtxdi_rd_u32(&slot, 80);
    light_compact_bit: rtxdi_rd_u32(&slot, 84);
    light_index_mask: rtxdi_rd_u32(&slot, 88);
    invalid_light_index: rtxdi_rd_u32(&slot, 92);
    size_onion_layer: rtxdi_rd_u32(&slot, 96);
    size_onion_ring: rtxdi_rd_u32(&slot, 100);
    size_regir_common: rtxdi_rd_u32(&slot, 104);
    size_regir_grid: rtxdi_rd_u32(&slot, 108);
    size_regir_parameters: rtxdi_rd_u32(&slot, 112);
    regir_mode_default: rtxdi_rd_u32(&slot, 116);
    presampling: rtxdi_rd_u32(&slot, 120);
    num_reservoir_buffers: rtxdi_rd_u32(&slot, 124);
    size_onion_parameters: rtxdi_rd_u32(&slot, 128);
  });
}

pub type RtxdiLayout = {
  count: Int;
  offsets: Vec[UInt8];
  sizes: Vec[UInt8];
}

/// Bridge layout table for `kind` (ours; offsetof of the ABI mirrors).
pub fn rtxdi_layout(kind: Int) -> Result[RtxdiLayout, RtxdiError]
  requires: kind >= RTXDI_LAYOUT_RESERVOIR
  requires: kind <= RTXDI_LAYOUT_PARAMETERS
{
  let count = unsafe { rtxdib_layout(kind as Int32, 0 as *UInt8, 0 as *UInt8, 0) } as Int;
  if count <= 0 { return Err(RtxdiError{ kind: RTXDI_ERR_BAD_ARGS; message: "unknown layout kind" }); }
  var offsets = rtxdi_slot(count * 4);
  var sizes = rtxdi_slot(count * 4);
  let got = unsafe {
    rtxdib_layout(kind as Int32, offsets.as_mut_ptr(), sizes.as_mut_ptr(), count as Int32)
  } as Int;
  if got != count {
    return Err(RtxdiError{ kind: RTXDI_ERR_BAD_ARGS; message: "layout table fetch failed" });
  }
  return Ok(RtxdiLayout{ count: count; offsets: offsets; sizes: sizes });
}

/// SDK layout table for `kind` (the shim's real structs; drift check).
pub fn rtxdi_sdk_layout(mod: &RtxdiModule, kind: Int) -> Result[RtxdiLayout, RtxdiError]
  requires: mod.h != 0
  requires: kind >= RTXDI_LAYOUT_RESERVOIR
  requires: kind <= RTXDI_LAYOUT_PARAMETERS
{
  var raw = rtxdi_slot(4 + 16 * 8);
  let rc = unsafe { rtxdib_sdk_layout(mod.h, kind as Int32, raw.as_mut_ptr(), (4 + 16 * 8) as Int32) } as Int;
  if rc < 0 { return Err(RtxdiError{ kind: rc; message: rtxdi_code_name(rc) }); }
  let count = rtxdi_rd_u32(&raw, 0);
  if count == 0 || count > 16 {
    return Err(RtxdiError{ kind: RTXDI_ERR_BAD_ARGS; message: "unexpected SDK layout pair count" });
  }
  var offsets = rtxdi_slot(count * 4);
  var sizes = rtxdi_slot(count * 4);
  var i = 0;
  while i < count {
    let off = rtxdi_rd_u32(&raw, 4 + i * 8);
    let sz = rtxdi_rd_u32(&raw, 8 + i * 8);
    let r0 = rtxdi_wr_u32(&mut offsets, i * 4, off);
    if r0.is_err { return Err(r0.error); }
    let r1 = rtxdi_wr_u32(&mut sizes, i * 4, sz);
    if r1.is_err { return Err(r1.error); }
    i = i + 1;
  }
  return Ok(RtxdiLayout{ count: count; offsets: offsets; sizes: sizes });
}

pub fn rtxdi_layout_field_offset(layout: &RtxdiLayout, field: Int) -> Int
  requires: field >= 0
  requires: field < layout.count
{
  return rtxdi_rd_u32(&layout.offsets, field * 4);
}

pub fn rtxdi_layout_field_size(layout: &RtxdiLayout, field: Int) -> Int
  requires: field >= 0
  requires: field < layout.count
{
  return rtxdi_rd_u32(&layout.sizes, field * 4);
}

pub fn rtxdi_mirror_size(kind: Int) -> Int
  requires: kind >= RTXDI_LAYOUT_RESERVOIR
  requires: kind <= RTXDI_LAYOUT_PARAMETERS
{
  return unsafe { rtxdib_layout_size(kind as Int32) } as Int;
}

// =========================================================================
// Owned parameter images (settings plumbing)
// =========================================================================

pub type RtxdiParams = {
  kind: Int;
  size: Int;
  data: Vec[UInt8];
  offsets: Vec[UInt8];
  sizes: Vec[UInt8];
}

/// Zeroed owned image for `kind` with the bridge layout table attached.
pub fn rtxdi_params_zero(kind: Int) -> Result[RtxdiParams, RtxdiError]
  requires: kind >= RTXDI_LAYOUT_RESERVOIR
  requires: kind <= RTXDI_LAYOUT_PARAMETERS
{
  let layout = rtxdi_layout(kind);
  if layout.is_err { return Err(layout.error); }
  let mirror = rtxdi_mirror_size(kind);
  if mirror <= 0 { return Err(RtxdiError{ kind: RTXDI_ERR_BAD_ARGS; message: "bad layout kind" }); }
  var data = rtxdi_slot(mirror + RTXDI_SLACK);
  return Ok(RtxdiParams{
    kind: kind;
    size: mirror;
    data: data;
    offsets: layout.value.offsets;
    sizes: layout.value.sizes;
  });
}

/// Bridge-carried SDK default for one of the seven GetDefault* constructors.
pub fn rtxdi_param_default(kind: Int) -> Result[RtxdiParams, RtxdiError]
  requires: kind >= RTXDI_DEFAULT_BUFFER_INDICES
  requires: kind <= RTXDI_DEFAULT_SHADING
{
  let layout_kind = default_layout_kind(kind);
  let layout = rtxdi_layout(layout_kind);
  if layout.is_err { return Err(layout.error); }
  let mirror = rtxdi_mirror_size(layout_kind);
  var data = rtxdi_slot(mirror + RTXDI_SLACK);
  let rc = unsafe { rtxdib_param_default(kind as Int32, data.as_mut_ptr(), (mirror + RTXDI_SLACK) as Int32) } as Int;
  if rc <= 0 { return Err(RtxdiError{ kind: rc; message: rtxdi_code_name(rc) }); }
  return Ok(RtxdiParams{
    kind: layout_kind;
    size: mirror;
    data: data;
    offsets: layout.value.offsets;
    sizes: layout.value.sizes;
  });
}

fn default_layout_kind(default_kind: Int) -> Int
  requires: default_kind >= RTXDI_DEFAULT_BUFFER_INDICES
  requires: default_kind <= RTXDI_DEFAULT_SHADING
{
  if default_kind == RTXDI_DEFAULT_BUFFER_INDICES { return RTXDI_LAYOUT_BUFFER_INDICES; }
  if default_kind == RTXDI_DEFAULT_INITIAL { return RTXDI_LAYOUT_INITIAL; }
  if default_kind == RTXDI_DEFAULT_TEMPORAL { return RTXDI_LAYOUT_TEMPORAL; }
  if default_kind == RTXDI_DEFAULT_BOILING { return RTXDI_LAYOUT_BOILING; }
  if default_kind == RTXDI_DEFAULT_SPATIAL { return RTXDI_LAYOUT_SPATIAL; }
  if default_kind == RTXDI_DEFAULT_SPATIOTEMPORAL { return RTXDI_LAYOUT_SPATIOTEMPORAL; }
  return RTXDI_LAYOUT_SHADING;
}

/// The shim's GetDefault* image (drift check against rtxdi_param_default).
pub fn rtxdi_sdk_param_default(mod: &RtxdiModule, kind: Int) -> Result[RtxdiParams, RtxdiError]
  requires: mod.h != 0
  requires: kind >= RTXDI_DEFAULT_BUFFER_INDICES
  requires: kind <= RTXDI_DEFAULT_SHADING
{
  let layout_kind = default_layout_kind(kind);
  let layout = rtxdi_layout(layout_kind);
  if layout.is_err { return Err(layout.error); }
  let mirror = rtxdi_mirror_size(layout_kind);
  var data = rtxdi_slot(mirror + RTXDI_SLACK);
  let rc = unsafe { rtxdib_sdk_param_default(mod.h, kind as Int32, data.as_mut_ptr(), (mirror + RTXDI_SLACK) as Int32) } as Int;
  if rc <= 0 { return Err(RtxdiError{ kind: rc; message: rtxdi_code_name(rc) }); }
  return Ok(RtxdiParams{
    kind: layout_kind;
    size: mirror;
    data: data;
    offsets: layout.value.offsets;
    sizes: layout.value.sizes;
  });
}

pub fn rtxdi_params_field_offset(params: &RtxdiParams, field: Int) -> Int
  requires: field >= 0
  requires: field < params.offsets.len() / 4
{
  return rtxdi_rd_u32(&params.offsets, field * 4);
}

pub fn rtxdi_params_field_size(params: &RtxdiParams, field: Int) -> Int
  requires: field >= 0
  requires: field < params.sizes.len() / 4
{
  return rtxdi_rd_u32(&params.sizes, field * 4);
}

pub fn rtxdi_params_get_u32(params: &RtxdiParams, field: Int) -> Int
  requires: field >= 0
  requires: field < params.offsets.len() / 4
{
  return rtxdi_rd_u32(&params.data, rtxdi_params_field_offset(params, field));
}

pub fn rtxdi_params_get_i32(params: &RtxdiParams, field: Int) -> Int
  requires: field >= 0
  requires: field < params.offsets.len() / 4
{
  return rtxdi_rd_i32(&params.data, rtxdi_params_field_offset(params, field));
}

pub fn rtxdi_params_get_f32(params: &RtxdiParams, field: Int) -> Float32
  requires: field >= 0
  requires: field < params.offsets.len() / 4
{
  return rtxdi_rd_f32(&params.data, rtxdi_params_field_offset(params, field));
}

pub fn rtxdi_params_set_u32(params: &mut RtxdiParams, field: Int, v: Int) -> Result[Unit, RtxdiError]
  requires: field >= 0
  requires: field < params.offsets.len() / 4
{
  let off = rtxdi_params_field_offset(params, field);
  return rtxdi_wr_u32(&mut params.data, off, v);
}

pub fn rtxdi_params_set_f32(params: &mut RtxdiParams, field: Int, v: Float32) -> Result[Unit, RtxdiError]
  requires: field >= 0
  requires: field < params.offsets.len() / 4
{
  let off = rtxdi_params_field_offset(params, field);
  return rtxdi_wr_f32(&mut params.data, off, v);
}

/// Byte-offset write into the owned image (for nested sub-structs such as the
/// light-buffer regions: local/infinite region fields live at +0/+4 inside
/// their 16-byte field, the environment block at +32).
pub fn rtxdi_params_set_u32_at(params: &mut RtxdiParams, field: Int, byte_delta: Int, v: Int) -> Result[Unit, RtxdiError]
  requires: field >= 0
  requires: field < params.offsets.len() / 4
  requires: byte_delta >= 0
  requires: byte_delta + 4 <= rtxdi_params_field_size(params, field) + RTXDI_SLACK
{
  let off = rtxdi_params_field_offset(params, field) + byte_delta;
  return rtxdi_wr_u32(&mut params.data, off, v);
}

pub fn rtxdi_params_get_u32_at(params: &RtxdiParams, field: Int, byte_delta: Int) -> Int
  requires: field >= 0
  requires: field < params.offsets.len() / 4
  requires: byte_delta >= 0
{
  let off = rtxdi_params_field_offset(params, field) + byte_delta;
  return rtxdi_rd_u32(&params.data, off);
}

// =========================================================================
// Runtime utilities
// =========================================================================

pub type RtxdiI2 = {
  x: Int;
  y: Int;
}

pub type RtxdiI3 = {
  x: Int;
  y: Int;
  z: Int;
}

/// CalculateReservoirBufferParameters -> (blockRowPitch, arrayPitch).
/// Complexity: O(1).
pub fn rtxdi_utils_reservoir_params(mod: &RtxdiModule, width: Int, height: Int, checkerboard: Int) -> Result[RtxdiI2, RtxdiError]
  requires: mod.h != 0
  requires: width > 0
  requires: height > 0
  requires: checkerboard >= RTXDI_CHECKERBOARD_OFF
  requires: checkerboard <= RTXDI_CHECKERBOARD_WHITE
{
  var slot = rtxdi_slot(16);
  let rc = unsafe {
    rtxdib_utils_reservoir_params(mod.h, width as UInt32, height as UInt32, checkerboard as Int32, slot.as_mut_ptr())
  } as Int;
  if rc != 0 { return Err(RtxdiError{ kind: rc; message: rtxdi_code_name(rc) }); }
  return Ok(RtxdiI2{ x: rtxdi_rd_u32(&slot, 0); y: rtxdi_rd_u32(&slot, 4); });
}

/// ComputePdfTextureSize -> (width, height, mipLevels).
/// Complexity: O(1).
pub fn rtxdi_utils_pdf_size(mod: &RtxdiModule, max_items: Int) -> Result[RtxdiI3, RtxdiError]
  requires: mod.h != 0
  requires: max_items > 0
{
  var slot = rtxdi_slot(12);
  let rc = unsafe { rtxdib_utils_pdf_size(mod.h, max_items as UInt32, slot.as_mut_ptr()) } as Int;
  if rc != 0 { return Err(RtxdiError{ kind: rc; message: rtxdi_code_name(rc) }); }
  return Ok(RtxdiI3{ x: rtxdi_rd_u32(&slot, 0); y: rtxdi_rd_u32(&slot, 4); z: rtxdi_rd_u32(&slot, 8); });
}

/// FillNeighborOffsetBuffer -> owned `count * 2` byte image of u16 pairs.
/// Complexity: O(count).
pub fn rtxdi_utils_fill_neighbor_offsets(mod: &RtxdiModule, count: Int) -> Result[Vec[UInt8], RtxdiError]
  requires: mod.h != 0
  requires: count > 0
  requires: count <= 65536
{
  var slot = rtxdi_slot(count * 2);
  let rc = unsafe {
    rtxdib_utils_fill_neighbor_offsets(mod.h, count as UInt32, slot.as_mut_ptr(), (count * 2) as Int32)
  } as Int;
  if rc < 0 { return Err(RtxdiError{ kind: rc; message: rtxdi_code_name(rc) }); }
  if rc != count * 2 {
    return Err(RtxdiError{ kind: RTXDI_ERR_BAD_ARGS; message: "neighbor offset byte count mismatch" });
  }
  return Ok(slot);
}

/// JenkinsHash (unsigned 32-bit result widened to Int).
/// Complexity: O(1).
pub fn rtxdi_utils_jenkins_hash(mod: &RtxdiModule, a: Int) -> Result[Int, RtxdiError]
  requires: mod.h != 0
  requires: a >= 0
{
  let rc = unsafe { rtxdib_utils_jenkins_hash(mod.h, a as UInt32) };
  return Ok(rc);
}

fn rtxdi_sign8(v: Int) -> Int
  requires: v >= 0
{
  if v >= 128 { return v - 256; }
  return v;
}

/// One (x, y) neighbor offset: the SDK writes uint8 pairs (the R2 sequence
/// scaled by radius 250 and truncated, wrapped for negatives), consumed as
/// signed bytes; 2 bytes per offset.  Complexity: O(1).
pub fn rtxdi_neighbor_offset(offsets: &Vec[UInt8], index: Int) -> RtxdiI2
  requires: index >= 0
  requires: offsets.len() >= index * 2 + 2
{
  let b0 = offsets[index * 2] as Int;
  let b1 = offsets[index * 2 + 1] as Int;
  return RtxdiI2{ x: rtxdi_sign8(b0); y: rtxdi_sign8(b1); };
}

// =========================================================================
// ReSTIRDIContext
// =========================================================================

pub type RtxdiContext = {
  mod: Int;
  raw: Int;
}

/// Create a standalone ReSTIRDIContext (static parameters: width, height,
/// checkerboard mode, neighbor-offset count -- a nonzero power of two).
/// NOTE (pinned runtime): the constructor leaves the runtime `frameIndex`
/// indeterminate; the application owns the frame counter and should call
/// rtxdi_di_set_frame_index before reading the frame plan each frame (the
/// upstream sample does exactly this).
/// Complexity: O(1) + O(neighbor count) for the SDK-side table.
pub fn rtxdi_di_create(mod: &RtxdiModule, width: Int, height: Int, checkerboard: Int, neighbor_offset_count: Int) -> Result[RtxdiContext, RtxdiError]
  requires: mod.h != 0
  requires: width > 0
  requires: height > 0
  requires: checkerboard >= RTXDI_CHECKERBOARD_OFF
  requires: checkerboard <= RTXDI_CHECKERBOARD_WHITE
  requires: neighbor_offset_count > 0
{
  var slot = rtxdi_slot(8);
  let rc = unsafe {
    rtxdib_di_create(mod.h, width as UInt32, height as UInt32, checkerboard as Int32, neighbor_offset_count as UInt32, slot.as_mut_ptr())
  } as Int;
  if rc != 0 { return Err(RtxdiError{ kind: rc; message: rtxdi_code_name(rc) }); }
  let lo = rtxdi_rd_u32(&slot, 0);
  let hi = rtxdi_rd_u32(&slot, 4);
  let raw = lo | (hi << 32);
  if raw == 0 { return Err(RtxdiError{ kind: RTXDI_ERR_BAD_ARGS; message: "context creation returned null" }); }
  return Ok(RtxdiContext{ mod: mod.h; raw: raw });
}

pub fn rtxdi_di_destroy(ctx: &RtxdiContext) -> Result[Unit, RtxdiError]
  requires: ctx.raw != 0
{
  let rc = unsafe { rtxdib_di_destroy(ctx.mod, ctx.raw) } as Int;
  if rc == 0 { return Ok(()); }
  return Err(RtxdiError{ kind: rc; message: rtxdi_code_name(rc) });
}

pub fn rtxdi_di_set_frame_index(ctx: &RtxdiContext, frame_index: Int) -> Result[Unit, RtxdiError]
  requires: ctx.raw != 0
  requires: frame_index >= 0
{
  let rc = unsafe { rtxdib_di_set_frame_index(ctx.mod, ctx.raw, frame_index as UInt32) } as Int;
  if rc == 0 { return Ok(()); }
  return Err(RtxdiError{ kind: rc; message: rtxdi_code_name(rc) });
}

pub fn rtxdi_di_frame_index(ctx: &RtxdiContext) -> Result[Int, RtxdiError]
  requires: ctx.raw != 0
{
  var slot = rtxdi_slot(4);
  let rc = unsafe { rtxdib_di_get_frame_index(ctx.mod, ctx.raw, slot.as_mut_ptr()) } as Int;
  if rc != 0 { return Err(RtxdiError{ kind: rc; message: rtxdi_code_name(rc) }); }
  return Ok(rtxdi_rd_u32(&slot, 0));
}

pub fn rtxdi_di_set_resampling_mode(ctx: &RtxdiContext, mode: Int) -> Result[Unit, RtxdiError]
  requires: ctx.raw != 0
  requires: mode >= RTXDI_RESAMPLING_NONE
  requires: mode <= RTXDI_RESAMPLING_FUSED_SPATIOTEMPORAL
{
  let rc = unsafe { rtxdib_di_set_resampling_mode(ctx.mod, ctx.raw, mode as Int32) } as Int;
  if rc == 0 { return Ok(()); }
  return Err(RtxdiError{ kind: rc; message: rtxdi_code_name(rc) });
}

pub fn rtxdi_di_resampling_mode(ctx: &RtxdiContext) -> Result[Int, RtxdiError]
  requires: ctx.raw != 0
{
  let rc = unsafe { rtxdib_di_get_resampling_mode(ctx.mod, ctx.raw) } as Int;
  if rc < 0 { return Err(RtxdiError{ kind: rc; message: rtxdi_code_name(rc) }); }
  return Ok(rc);
}

/// Fetch one parameter block from the context (RTXDI_PART_*), into an owned
/// image with its layout table.  Complexity: O(size).
pub fn rtxdi_di_params(ctx: &RtxdiContext, part: Int) -> Result[RtxdiParams, RtxdiError]
  requires: ctx.raw != 0
  requires: part >= RTXDI_PART_RESERVOIR
  requires: part <= RTXDI_PART_DI_STATIC
{
  let layout_kind = part_layout_kind(part);
  let layout = rtxdi_layout(layout_kind);
  if layout.is_err { return Err(layout.error); }
  let mirror = rtxdi_mirror_size(layout_kind);
  var data = rtxdi_slot(mirror + RTXDI_SLACK);
  let rc = unsafe { rtxdib_di_get(ctx.mod, part as Int32, ctx.raw, data.as_mut_ptr(), (mirror + RTXDI_SLACK) as Int32) } as Int;
  if rc < 0 { return Err(RtxdiError{ kind: rc; message: rtxdi_code_name(rc) }); }
  return Ok(RtxdiParams{
    kind: layout_kind;
    size: mirror;
    data: data;
    offsets: layout.value.offsets;
    sizes: layout.value.sizes;
  });
}

/// Push one owned parameter image into the context.  `part` must match the
/// image kind (RTXDI_PART_INITIAL .. RTXDI_PART_SHADING are settable).
pub fn rtxdi_di_set_params(ctx: &RtxdiContext, part: Int, params: &RtxdiParams) -> Result[Unit, RtxdiError]
  requires: ctx.raw != 0
  requires: part >= RTXDI_PART_INITIAL
  requires: part <= RTXDI_PART_SHADING
  requires: params.size > 0
{
  let rc = unsafe {
    rtxdib_di_set(ctx.mod, part as Int32, ctx.raw, params.data.as_ptr(), params.size as Int32)
  } as Int;
  if rc == 0 { return Ok(()); }
  return Err(RtxdiError{ kind: rc; message: rtxdi_code_name(rc) });
}

fn part_layout_kind(part: Int) -> Int
  requires: part >= RTXDI_PART_RESERVOIR
  requires: part <= RTXDI_PART_DI_STATIC
{
  if part == RTXDI_PART_RESERVOIR { return RTXDI_LAYOUT_RESERVOIR; }
  if part == RTXDI_PART_RUNTIME { return RTXDI_LAYOUT_RUNTIME; }
  if part == RTXDI_PART_BUFFER_INDICES { return RTXDI_LAYOUT_BUFFER_INDICES; }
  if part == RTXDI_PART_INITIAL { return RTXDI_LAYOUT_INITIAL; }
  if part == RTXDI_PART_TEMPORAL { return RTXDI_LAYOUT_TEMPORAL; }
  if part == RTXDI_PART_BOILING { return RTXDI_LAYOUT_BOILING; }
  if part == RTXDI_PART_SPATIAL { return RTXDI_LAYOUT_SPATIAL; }
  if part == RTXDI_PART_SPATIOTEMPORAL { return RTXDI_LAYOUT_SPATIOTEMPORAL; }
  if part == RTXDI_PART_SHADING { return RTXDI_LAYOUT_SHADING; }
  return RTXDI_LAYOUT_DI_STATIC;
}

// =========================================================================
// Frame plan (dispatch/constant computation for a small scene)
// =========================================================================

pub type RtxdiFramePlan = {
  runtime: RtxdiParams;
  indices: RtxdiParams;
  reservoir: RtxdiParams;
}

/// Compose the per-frame DI plan (runtime params, buffer indices, reservoir
/// buffer parameters) from the context -- the "resource binding + dispatch
/// planning" values an application copies into its constant buffers each
/// frame.  Call rtxdi_di_set_frame_index first: the frame counter is
/// application-driven in the pinned runtime.  Complexity: O(size).
pub fn rtxdi_frame_plan(ctx: &RtxdiContext) -> Result[RtxdiFramePlan, RtxdiError]
  requires: ctx.raw != 0
{
  let rt = rtxdi_di_params(ctx, RTXDI_PART_RUNTIME);
  if rt.is_err { return Err(rt.error); }
  let bi = rtxdi_di_params(ctx, RTXDI_PART_BUFFER_INDICES);
  if bi.is_err { return Err(bi.error); }
  let rb = rtxdi_di_params(ctx, RTXDI_PART_RESERVOIR);
  if rb.is_err { return Err(rb.error); }
  return Ok(RtxdiFramePlan{ runtime: rt.value; indices: bi.value; reservoir: rb.value; });
}

// =========================================================================
// RIS buffer segment allocator
// =========================================================================

pub type RtxdiRisAllocator = {
  mod: Int;
  raw: Int;
}

/// Create a standalone RISBufferSegmentAllocator.  Complexity: O(1).
pub fn rtxdi_ris_create(mod: &RtxdiModule) -> Result[RtxdiRisAllocator, RtxdiError]
  requires: mod.h != 0
{
  var slot = rtxdi_slot(8);
  let rc = unsafe { rtxdib_ris_create(mod.h, slot.as_mut_ptr()) } as Int;
  if rc != 0 { return Err(RtxdiError{ kind: rc; message: rtxdi_code_name(rc) }); }
  let lo = rtxdi_rd_u32(&slot, 0);
  let hi = rtxdi_rd_u32(&slot, 4);
  let raw = lo | (hi << 32);
  if raw == 0 { return Err(RtxdiError{ kind: RTXDI_ERR_BAD_ARGS; message: "allocator creation returned null" }); }
  return Ok(RtxdiRisAllocator{ mod: mod.h; raw: raw });
}

pub fn rtxdi_ris_destroy(ris: &RtxdiRisAllocator) -> Result[Unit, RtxdiError]
  requires: ris.raw != 0
{
  let rc = unsafe { rtxdib_ris_destroy(ris.mod, ris.raw) } as Int;
  if rc == 0 { return Ok(()); }
  return Err(RtxdiError{ kind: rc; message: rtxdi_code_name(rc) });
}

/// AllocateSegment -> element offset of the new segment.  Complexity: O(1).
pub fn rtxdi_ris_allocate(ris: &RtxdiRisAllocator, size: Int) -> Result[Int, RtxdiError]
  requires: ris.raw != 0
  requires: size > 0
{
  var slot = rtxdi_slot(4);
  let rc = unsafe { rtxdib_ris_allocate(ris.mod, ris.raw, size as UInt32, slot.as_mut_ptr()) } as Int;
  if rc != 0 { return Err(RtxdiError{ kind: rc; message: rtxdi_code_name(rc) }); }
  return Ok(rtxdi_rd_u32(&slot, 0));
}

pub fn rtxdi_ris_total(ris: &RtxdiRisAllocator) -> Result[Int, RtxdiError]
  requires: ris.raw != 0
{
  var slot = rtxdi_slot(4);
  let rc = unsafe { rtxdib_ris_total(ris.mod, ris.raw, slot.as_mut_ptr()) } as Int;
  if rc != 0 { return Err(RtxdiError{ kind: rc; message: rtxdi_code_name(rc) }); }
  return Ok(rtxdi_rd_u32(&slot, 0));
}

// =========================================================================
// ReGIR context
// =========================================================================

pub type RtxdiRegirContext = {
  mod: Int;
  raw: Int;
}

/// Create a ReGIRContext against an allocator (grid or onion mode).
/// Complexity: O(onion cells).
pub fn rtxdi_regir_create(mod: &RtxdiModule, ris: &RtxdiRisAllocator, mode: Int, grid_x: Int, grid_y: Int, grid_z: Int, lights_per_cell: Int, onion_detail: Int, onion_coverage: Int) -> Result[RtxdiRegirContext, RtxdiError]
  requires: mod.h != 0
  requires: ris.raw != 0
  requires: mode >= RTXDI_REGIR_DISABLED
  requires: mode <= RTXDI_REGIR_ONION
  requires: grid_x > 0 && grid_y > 0 && grid_z > 0
  requires: lights_per_cell > 0
  requires: onion_detail >= 1
  requires: onion_detail <= RTXDI_ONION_MAX_LAYER_GROUPS
{
  var slot = rtxdi_slot(8);
  let rc = unsafe {
    rtxdib_regir_create(mod.h, ris.raw, mode as Int32, grid_x as UInt32, grid_y as UInt32, grid_z as UInt32,
      lights_per_cell as UInt32, onion_detail as UInt32, onion_coverage as UInt32, slot.as_mut_ptr())
  } as Int;
  if rc != 0 { return Err(RtxdiError{ kind: rc; message: rtxdi_code_name(rc) }); }
  let lo = rtxdi_rd_u32(&slot, 0);
  let hi = rtxdi_rd_u32(&slot, 4);
  let raw = lo | (hi << 32);
  if raw == 0 { return Err(RtxdiError{ kind: RTXDI_ERR_BAD_ARGS; message: "ReGIR creation returned null" }); }
  return Ok(RtxdiRegirContext{ mod: mod.h; raw: raw });
}

pub fn rtxdi_regir_destroy(ctx: &RtxdiRegirContext) -> Result[Unit, RtxdiError]
  requires: ctx.raw != 0
{
  let rc = unsafe { rtxdib_regir_destroy(ctx.mod, ctx.raw) } as Int;
  if rc == 0 { return Ok(()); }
  return Err(RtxdiError{ kind: rc; message: rtxdi_code_name(rc) });
}

pub fn rtxdi_regir_cell_offset(ctx: &RtxdiRegirContext) -> Result[Int, RtxdiError]
  requires: ctx.raw != 0
{
  var slot = rtxdi_slot(4);
  let rc = unsafe { rtxdib_regir_cell_offset(ctx.mod, ctx.raw, slot.as_mut_ptr()) } as Int;
  if rc != 0 { return Err(RtxdiError{ kind: rc; message: rtxdi_code_name(rc) }); }
  return Ok(rtxdi_rd_u32(&slot, 0));
}

pub fn rtxdi_regir_light_slots(ctx: &RtxdiRegirContext) -> Result[Int, RtxdiError]
  requires: ctx.raw != 0
{
  var slot = rtxdi_slot(4);
  let rc = unsafe { rtxdib_regir_light_slots(ctx.mod, ctx.raw, slot.as_mut_ptr()) } as Int;
  if rc != 0 { return Err(RtxdiError{ kind: rc; message: rtxdi_code_name(rc) }); }
  return Ok(rtxdi_rd_u32(&slot, 0));
}

pub fn rtxdi_regir_grid_params(ctx: &RtxdiRegirContext) -> Result[RtxdiParams, RtxdiError]
  requires: ctx.raw != 0
{
  let layout = rtxdi_layout(RTXDI_LAYOUT_REGIR_GRID);
  if layout.is_err { return Err(layout.error); }
  var data = rtxdi_slot(16);
  let rc = unsafe { rtxdib_regir_get_grid(ctx.mod, ctx.raw, data.as_mut_ptr()) } as Int;
  if rc != 0 { return Err(RtxdiError{ kind: rc; message: rtxdi_code_name(rc) }); }
  return Ok(RtxdiParams{ kind: RTXDI_LAYOUT_REGIR_GRID; size: 16; data: data; offsets: layout.value.offsets; sizes: layout.value.sizes; });
}

pub type RtxdiOnionParams = {
  num_layers: Int;
  num_rings: Int;
  cubic_root_factor: Float32;
  linear_factor: Float32;
  cells: Int;
  light_slot_count: Int;
  data: Vec[UInt8];
}

/// ReGIR onion calculated parameters (headers + fixed 8x48B layers + 52x16B
/// rings, zero-padded; layout documented in the module constants).
/// Complexity: O(1) after the SDK computed them.
pub fn rtxdi_regir_onion_params(ctx: &RtxdiRegirContext) -> Result[RtxdiOnionParams, RtxdiError]
  requires: ctx.raw != 0
{
  var slot = rtxdi_slot(RTXDI_ONION_IMAGE_SIZE);
  let rc = unsafe { rtxdib_regir_get_onion(ctx.mod, ctx.raw, slot.as_mut_ptr(), RTXDI_ONION_IMAGE_SIZE as Int32) } as Int;
  if rc != RTXDI_ONION_IMAGE_SIZE {
    return Err(RtxdiError{ kind: RTXDI_ERR_SIZE; message: "onion image fetch failed" });
  }
  return Ok(RtxdiOnionParams{
    num_layers: rtxdi_rd_u32(&slot, RTXDI_ONION_IMAGE_NUM_LAYERS);
    num_rings: rtxdi_rd_u32(&slot, RTXDI_ONION_IMAGE_NUM_RINGS);
    cubic_root_factor: rtxdi_rd_f32(&slot, RTXDI_ONION_IMAGE_CUBIC_ROOT);
    linear_factor: rtxdi_rd_f32(&slot, RTXDI_ONION_IMAGE_LINEAR);
    cells: rtxdi_rd_u32(&slot, RTXDI_ONION_IMAGE_CELLS);
    light_slot_count: rtxdi_rd_u32(&slot, RTXDI_ONION_IMAGE_LIGHT_SLOTS);
    data: slot;
  });
}

/// One f32 field of onion layer `layer` (RTXDI_F_ONION_LAYER_*).
pub fn rtxdi_onion_layer_f32(onion: &RtxdiOnionParams, layer: Int, field: Int) -> Float32
  requires: layer >= 0
  requires: layer < onion.num_layers
  requires: field >= 0
  requires: field < 11
{
  return rtxdi_rd_f32(&onion.data, RTXDI_ONION_IMAGE_LAYERS_OFFSET + layer * RTXDI_SIZE_ONION_LAYER + field * 4);
}

/// One i32 field of onion ring `ring` (RTXDI_F_ONION_RING_*).
pub fn rtxdi_onion_ring_i32(onion: &RtxdiOnionParams, ring: Int, field: Int) -> Int
  requires: ring >= 0
  requires: ring < onion.num_rings
  requires: field >= 0
  requires: field < 4
{
  return rtxdi_rd_i32(&onion.data, RTXDI_ONION_IMAGE_RINGS_OFFSET + ring * RTXDI_SIZE_ONION_RING + field * 4);
}

pub type RtxdiRegirDynamic = {
  cell_size: Float32;
  center_x: Float32;
  center_y: Float32;
  center_z: Float32;
  fallback_mode: Int;
  presampling_mode: Int;
  jitter: Float32;
  num_build_samples: Int;
}

pub fn rtxdi_regir_dynamic(ctx: &RtxdiRegirContext) -> Result[RtxdiRegirDynamic, RtxdiError]
  requires: ctx.raw != 0
{
  var slot = rtxdi_slot(RTXDI_REGIR_DYNAMIC_SIZE);
  let rc = unsafe { rtxdib_regir_get_dynamic(ctx.mod, ctx.raw, slot.as_mut_ptr()) } as Int;
  if rc != 0 { return Err(RtxdiError{ kind: rc; message: rtxdi_code_name(rc) }); }
  return Ok(RtxdiRegirDynamic{
    cell_size: rtxdi_rd_f32(&slot, RTXDI_REGIR_DYNAMIC_CELL_SIZE);
    center_x: rtxdi_rd_f32(&slot, RTXDI_REGIR_DYNAMIC_CENTER_X);
    center_y: rtxdi_rd_f32(&slot, RTXDI_REGIR_DYNAMIC_CENTER_Y);
    center_z: rtxdi_rd_f32(&slot, RTXDI_REGIR_DYNAMIC_CENTER_Z);
    fallback_mode: rtxdi_rd_u32(&slot, RTXDI_REGIR_DYNAMIC_FALLBACK);
    presampling_mode: rtxdi_rd_u32(&slot, RTXDI_REGIR_DYNAMIC_PRESAMPLING);
    jitter: rtxdi_rd_f32(&slot, RTXDI_REGIR_DYNAMIC_JITTER);
    num_build_samples: rtxdi_rd_u32(&slot, RTXDI_REGIR_DYNAMIC_NUM_BUILD_SAMPLES);
  });
}

pub fn rtxdi_regir_set_dynamic(ctx: &RtxdiRegirContext, cell_size: Float32, cx: Float32, cy: Float32, cz: Float32, fallback_mode: Int, presampling_mode: Int, jitter: Float32, num_build_samples: Int) -> Result[Unit, RtxdiError]
  requires: ctx.raw != 0
  requires: fallback_mode >= 0 && fallback_mode <= 1
  requires: presampling_mode >= 0 && presampling_mode <= 1
  requires: num_build_samples >= 0
{
  var slot = rtxdi_slot(RTXDI_REGIR_DYNAMIC_SIZE);
  let r0 = rtxdi_wr_f32(&mut slot, RTXDI_REGIR_DYNAMIC_CELL_SIZE, cell_size);
  if r0.is_err { return Err(r0.error); }
  let r1 = rtxdi_wr_f32(&mut slot, RTXDI_REGIR_DYNAMIC_CENTER_X, cx);
  if r1.is_err { return Err(r1.error); }
  let r2 = rtxdi_wr_f32(&mut slot, RTXDI_REGIR_DYNAMIC_CENTER_Y, cy);
  if r2.is_err { return Err(r2.error); }
  let r3 = rtxdi_wr_f32(&mut slot, RTXDI_REGIR_DYNAMIC_CENTER_Z, cz);
  if r3.is_err { return Err(r3.error); }
  let r4 = rtxdi_wr_u32(&mut slot, RTXDI_REGIR_DYNAMIC_FALLBACK, fallback_mode);
  if r4.is_err { return Err(r4.error); }
  let r5 = rtxdi_wr_u32(&mut slot, RTXDI_REGIR_DYNAMIC_PRESAMPLING, presampling_mode);
  if r5.is_err { return Err(r5.error); }
  let r6 = rtxdi_wr_f32(&mut slot, RTXDI_REGIR_DYNAMIC_JITTER, jitter);
  if r6.is_err { return Err(r6.error); }
  let r7 = rtxdi_wr_u32(&mut slot, RTXDI_REGIR_DYNAMIC_NUM_BUILD_SAMPLES, num_build_samples);
  if r7.is_err { return Err(r7.error); }
  let rc = unsafe { rtxdib_regir_set_dynamic(ctx.mod, ctx.raw, slot.as_mut_ptr(), RTXDI_REGIR_DYNAMIC_SIZE as Int32) } as Int;
  if rc == 0 { return Ok(()); }
  return Err(RtxdiError{ kind: rc; message: rtxdi_code_name(rc) });
}

pub fn rtxdi_regir_power_ris(ctx: &RtxdiRegirContext) -> Result[Bool, RtxdiError]
  requires: ctx.raw != 0
{
  let rc = unsafe { rtxdib_regir_power_ris(ctx.mod, ctx.raw) } as Int;
  if rc < 0 { return Err(RtxdiError{ kind: rc; message: rtxdi_code_name(rc) }); }
  return Ok(rc == 1);
}

// =========================================================================
// ImportanceSamplingContext (top-level context + light buffer setup)
// =========================================================================

pub type RtxdiIsContext = {
  mod: Int;
  raw: Int;
}

/// Build the 60-byte static-params image for the IS context (bridge ABI).
pub fn rtxdi_is_static_image(width: Int, height: Int, checkerboard: Int, neighbor_offset_count: Int, local_tile_size: Int, local_tile_count: Int, env_tile_size: Int, env_tile_count: Int, regir_mode: Int, grid_x: Int, grid_y: Int, grid_z: Int, lights_per_cell: Int, onion_detail: Int, onion_coverage: Int) -> Result[Vec[UInt8], RtxdiError]
  requires: width > 0
  requires: height > 0
  requires: checkerboard >= RTXDI_CHECKERBOARD_OFF
  requires: checkerboard <= RTXDI_CHECKERBOARD_WHITE
  requires: neighbor_offset_count > 0
  requires: local_tile_size > 0 && local_tile_count > 0
  requires: env_tile_size > 0 && env_tile_count > 0
  requires: regir_mode >= RTXDI_REGIR_DISABLED
  requires: regir_mode <= RTXDI_REGIR_ONION
  requires: grid_x > 0 && grid_y > 0 && grid_z > 0
  requires: lights_per_cell > 0
  requires: onion_detail >= 1
  requires: onion_detail <= RTXDI_ONION_MAX_LAYER_GROUPS
{
  var slot = rtxdi_slot(RTXDI_IS_IMAGE_SIZE);
  let r0 = rtxdi_wr_u32(&mut slot, RTXDI_IS_IMAGE_WIDTH, width);
  if r0.is_err { return Err(r0.error); }
  let r1 = rtxdi_wr_u32(&mut slot, RTXDI_IS_IMAGE_HEIGHT, height);
  if r1.is_err { return Err(r1.error); }
  let r2 = rtxdi_wr_u32(&mut slot, RTXDI_IS_IMAGE_CHECKERBOARD, checkerboard);
  if r2.is_err { return Err(r2.error); }
  let r3 = rtxdi_wr_u32(&mut slot, RTXDI_IS_IMAGE_NEIGHBOR_COUNT, neighbor_offset_count);
  if r3.is_err { return Err(r3.error); }
  let r4 = rtxdi_wr_u32(&mut slot, RTXDI_IS_IMAGE_LOCAL_TILE_SIZE, local_tile_size);
  if r4.is_err { return Err(r4.error); }
  let r5 = rtxdi_wr_u32(&mut slot, RTXDI_IS_IMAGE_LOCAL_TILE_COUNT, local_tile_count);
  if r5.is_err { return Err(r5.error); }
  let r6 = rtxdi_wr_u32(&mut slot, RTXDI_IS_IMAGE_ENV_TILE_SIZE, env_tile_size);
  if r6.is_err { return Err(r6.error); }
  let r7 = rtxdi_wr_u32(&mut slot, RTXDI_IS_IMAGE_ENV_TILE_COUNT, env_tile_count);
  if r7.is_err { return Err(r7.error); }
  let r8 = rtxdi_wr_u32(&mut slot, RTXDI_IS_IMAGE_REGIR_MODE, regir_mode);
  if r8.is_err { return Err(r8.error); }
  let r9 = rtxdi_wr_u32(&mut slot, RTXDI_IS_IMAGE_GRID_X, grid_x);
  if r9.is_err { return Err(r9.error); }
  let r10 = rtxdi_wr_u32(&mut slot, RTXDI_IS_IMAGE_GRID_Y, grid_y);
  if r10.is_err { return Err(r10.error); }
  let r11 = rtxdi_wr_u32(&mut slot, RTXDI_IS_IMAGE_GRID_Z, grid_z);
  if r11.is_err { return Err(r11.error); }
  let r12 = rtxdi_wr_u32(&mut slot, RTXDI_IS_IMAGE_LIGHTS_PER_CELL, lights_per_cell);
  if r12.is_err { return Err(r12.error); }
  let r13 = rtxdi_wr_u32(&mut slot, RTXDI_IS_IMAGE_ONION_DETAIL, onion_detail);
  if r13.is_err { return Err(r13.error); }
  let r14 = rtxdi_wr_u32(&mut slot, RTXDI_IS_IMAGE_ONION_COVERAGE, onion_coverage);
  if r14.is_err { return Err(r14.error); }
  return Ok(slot);
}

/// Create the top-level ImportanceSamplingContext (DI + ReGIR + RIS
/// allocator).  Complexity: O(render area planning).
pub fn rtxdi_is_create(mod: &RtxdiModule, image: &Vec[UInt8]) -> Result[RtxdiIsContext, RtxdiError]
  requires: mod.h != 0
  requires: image.len() >= RTXDI_IS_IMAGE_SIZE
{
  var slot = rtxdi_slot(8);
  let rc = unsafe { rtxdib_is_create(mod.h, image.as_ptr(), RTXDI_IS_IMAGE_SIZE as Int32, slot.as_mut_ptr()) } as Int;
  if rc != 0 { return Err(RtxdiError{ kind: rc; message: rtxdi_code_name(rc) }); }
  let lo = rtxdi_rd_u32(&slot, 0);
  let hi = rtxdi_rd_u32(&slot, 4);
  let raw = lo | (hi << 32);
  if raw == 0 { return Err(RtxdiError{ kind: RTXDI_ERR_BAD_ARGS; message: "IS context creation returned null" }); }
  return Ok(RtxdiIsContext{ mod: mod.h; raw: raw });
}

pub fn rtxdi_is_destroy(ctx: &RtxdiIsContext) -> Result[Unit, RtxdiError]
  requires: ctx.raw != 0
{
  let rc = unsafe { rtxdib_is_destroy(ctx.mod, ctx.raw) } as Int;
  if rc == 0 { return Ok(()); }
  return Err(RtxdiError{ kind: rc; message: rtxdi_code_name(rc) });
}

/// Borrowed child handles (owned by the IS context; never destroy these).
pub fn rtxdi_is_di(ctx: &RtxdiIsContext) -> Result[RtxdiContext, RtxdiError]
  requires: ctx.raw != 0
{
  var slot = rtxdi_slot(8);
  let rc = unsafe { rtxdib_is_di(ctx.mod, ctx.raw, slot.as_mut_ptr()) } as Int;
  if rc != 0 { return Err(RtxdiError{ kind: rc; message: rtxdi_code_name(rc) }); }
  let lo = rtxdi_rd_u32(&slot, 0);
  let hi = rtxdi_rd_u32(&slot, 4);
  return Ok(RtxdiContext{ mod: ctx.mod; raw: lo | (hi << 32) });
}

pub fn rtxdi_is_regir(ctx: &RtxdiIsContext) -> Result[RtxdiRegirContext, RtxdiError]
  requires: ctx.raw != 0
{
  var slot = rtxdi_slot(8);
  let rc = unsafe { rtxdib_is_regir(ctx.mod, ctx.raw, slot.as_mut_ptr()) } as Int;
  if rc != 0 { return Err(RtxdiError{ kind: rc; message: rtxdi_code_name(rc) }); }
  let lo = rtxdi_rd_u32(&slot, 0);
  let hi = rtxdi_rd_u32(&slot, 4);
  return Ok(RtxdiRegirContext{ mod: ctx.mod; raw: lo | (hi << 32) });
}

pub fn rtxdi_is_ris_total(ctx: &RtxdiIsContext) -> Result[Int, RtxdiError]
  requires: ctx.raw != 0
{
  var slot = rtxdi_slot(4);
  let rc = unsafe { rtxdib_is_ris_total(ctx.mod, ctx.raw, slot.as_mut_ptr()) } as Int;
  if rc != 0 { return Err(RtxdiError{ kind: rc; message: rtxdi_code_name(rc) }); }
  return Ok(rtxdi_rd_u32(&slot, 0));
}

/// RTXDI_LightBufferParameters (48B owned image; set via SetLightBufferParams).
pub fn rtxdi_is_light_buffer(ctx: &RtxdiIsContext) -> Result[RtxdiParams, RtxdiError]
  requires: ctx.raw != 0
{
  let layout = rtxdi_layout(RTXDI_LAYOUT_LIGHT_BUFFER);
  if layout.is_err { return Err(layout.error); }
  var data = rtxdi_slot(RTXDI_SIZE_LIGHT_BUFFER + RTXDI_SLACK);
  let rc = unsafe { rtxdib_is_light_buffer(ctx.mod, ctx.raw, data.as_mut_ptr()) } as Int;
  if rc != 0 { return Err(RtxdiError{ kind: rc; message: rtxdi_code_name(rc) }); }
  return Ok(RtxdiParams{
    kind: RTXDI_LAYOUT_LIGHT_BUFFER;
    size: RTXDI_SIZE_LIGHT_BUFFER;
    data: data;
    offsets: layout.value.offsets;
    sizes: layout.value.sizes;
  });
}

pub fn rtxdi_is_set_light_buffer(ctx: &RtxdiIsContext, params: &RtxdiParams) -> Result[Unit, RtxdiError]
  requires: ctx.raw != 0
  requires: params.size == RTXDI_SIZE_LIGHT_BUFFER
{
  let rc = unsafe { rtxdib_is_set_light_buffer(ctx.mod, ctx.raw, params.data.as_ptr(), RTXDI_SIZE_LIGHT_BUFFER as Int32) } as Int;
  if rc == 0 { return Ok(()); }
  return Err(RtxdiError{ kind: rc; message: rtxdi_code_name(rc) });
}

pub fn rtxdi_is_local_ris(ctx: &RtxdiIsContext) -> Result[RtxdiParams, RtxdiError]
  requires: ctx.raw != 0
{
  let layout = rtxdi_layout(RTXDI_LAYOUT_RIS_SEGMENT);
  if layout.is_err { return Err(layout.error); }
  var data = rtxdi_slot(RTXDI_SIZE_RIS_SEGMENT);
  let rc = unsafe { rtxdib_is_local_ris(ctx.mod, ctx.raw, data.as_mut_ptr()) } as Int;
  if rc != 0 { return Err(RtxdiError{ kind: rc; message: rtxdi_code_name(rc) }); }
  return Ok(RtxdiParams{
    kind: RTXDI_LAYOUT_RIS_SEGMENT;
    size: RTXDI_SIZE_RIS_SEGMENT;
    data: data;
    offsets: layout.value.offsets;
    sizes: layout.value.sizes;
  });
}

pub fn rtxdi_is_env_ris(ctx: &RtxdiIsContext) -> Result[RtxdiParams, RtxdiError]
  requires: ctx.raw != 0
{
  let layout = rtxdi_layout(RTXDI_LAYOUT_RIS_SEGMENT);
  if layout.is_err { return Err(layout.error); }
  var data = rtxdi_slot(RTXDI_SIZE_RIS_SEGMENT);
  let rc = unsafe { rtxdib_is_env_ris(ctx.mod, ctx.raw, data.as_mut_ptr()) } as Int;
  if rc != 0 { return Err(RtxdiError{ kind: rc; message: rtxdi_code_name(rc) }); }
  return Ok(RtxdiParams{
    kind: RTXDI_LAYOUT_RIS_SEGMENT;
    size: RTXDI_SIZE_RIS_SEGMENT;
    data: data;
    offsets: layout.value.offsets;
    sizes: layout.value.sizes;
  });
}

pub fn rtxdi_is_neighbor_count(ctx: &RtxdiIsContext) -> Result[Int, RtxdiError]
  requires: ctx.raw != 0
{
  var slot = rtxdi_slot(4);
  let rc = unsafe { rtxdib_is_neighbor_count(ctx.mod, ctx.raw, slot.as_mut_ptr()) } as Int;
  if rc != 0 { return Err(RtxdiError{ kind: rc; message: rtxdi_code_name(rc) }); }
  return Ok(rtxdi_rd_u32(&slot, 0));
}

pub fn rtxdi_is_power_ris(ctx: &RtxdiIsContext) -> Result[Bool, RtxdiError]
  requires: ctx.raw != 0
{
  let rc = unsafe { rtxdib_is_power_ris(ctx.mod, ctx.raw) } as Int;
  if rc < 0 { return Err(RtxdiError{ kind: rc; message: rtxdi_code_name(rc) }); }
  return Ok(rc == 1);
}

pub fn rtxdi_is_regir_enabled(ctx: &RtxdiIsContext) -> Result[Bool, RtxdiError]
  requires: ctx.raw != 0
{
  let rc = unsafe { rtxdib_is_regir_enabled(ctx.mod, ctx.raw) } as Int;
  if rc < 0 { return Err(RtxdiError{ kind: rc; message: rtxdi_code_name(rc) }); }
  return Ok(rc == 1);
}

// =========================================================================
// Execute (typed device requirement)
// =========================================================================

/// Execute the ReSTIR DI passes for a frame.  Requires an application-owned
/// GPU device bridge (D3D12/VK), the reservoir/RIS/light buffers and the
/// compiled shaders: out of scope for 0.1.0, so this returns
/// RTXDI_EXEC_NO_DEVICE (typed SKIP) for a valid context and
/// RTXDI_EXEC_INVALID for bad arguments -- never a silent success.
/// Complexity: O(1).
pub fn rtxdi_execute_di(ctx: &RtxdiContext) -> Int
  requires: true
{
  if ctx.raw == 0 { return RTXDI_EXEC_INVALID; }
  return RTXDI_EXEC_NO_DEVICE;
}

