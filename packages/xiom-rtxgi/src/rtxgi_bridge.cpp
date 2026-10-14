/* XIOM -- xiom.rtxgi: XIOM-side dynamic-loader bridge for the NVIDIA
 * RTXGI-DDGI v1.3.7 CPU (device-free) integration surface.
 * Copyright (c) 2026 Eleftherios Notas and The XIOM Authors.
 * SPDX-License-Identifier: MIT OR Apache-2.0
 *
 * This file is OUR code, not NVIDIA code.  It copies NOTHING from the RTXGI
 * SDK and links NOTHING from it at build time -- the RTXGI-DDGI integration
 * layer never ships in this repository (see PROVENANCE.md: the upstream is
 * the proprietary NVIDIA RTX SDKs License, reference-only policy, NRD/FFmpeg
 * precedent).  The bridge exists because the v0.64.4 FFI discipline
 * (findings B-20/B-21/B-23/B-24/B-25/B-26) cannot:
 *
 *   1. load a runtime shim module and resolve entry points -- done here with
 *      LoadLibraryA/GetProcAddress; module/volume handles cross the C ABI as
 *      int64_t and are cast to pointers only inside the shim (B-25);
 *
 *   2. lay out the public RTXGI structs (DDGIVolumeDesc, DDGIVolumeDescGPU,
 *      DDGIVolumeDescGPUPacked, DDGIVolumeResourceIndices, DDGIRootConstants)
 *      for calls into the shim: the ABI mirror structs below are written from
 *      the public header declarations at the pinned commit (the "declaration
 *      oracle", PROVENANCE.md) -- rtxgi/ddgi/DDGIVolume.h, DDGIVolumeDescGPU.h,
 *      DDGIRootConstants.h @ v1.3.7 (c233266e).  Layout facts only;
 *
 *   3. copy response data (GPU desc images, packed constants, counts, AABBs)
 *      out of shim-owned storage into XIOM-owned slots: this file does that
 *      copy; XIOM reads only its own slots, byte-indexed (B-20/B-24), one
 *      owned slot per out-param;
 *
 *   4. provide the layout tables that nrd.xi-style owned images need
 *      (offsetof/sizeof of the mirrors; single source of ABI truth), plus
 *      scalar accessors so XIOM never pointer-arithmetics (B-20/B-24).
 *
 * The shim module is the licensee's own locally built DLL around the
 * RTXGI-DDGI source (see PROVENANCE.md "Local runtime sample"); it is
 * resolution-loaded at run time and never committed.  When it is absent the
 * suite classifies RTXGI_LOAD_ABSENT (SKIP, green).
 *
 * Bridge return codes (int32):
 *   0     = success (or count/size, per entry point)
 *   100   = RTXGIB_ERR_NOT_LOADED  (no shim module loaded)
 *   101   = RTXGIB_ERR_BAD_ARGS
 *   102   = RTXGIB_ERR_SIZE        (owned image smaller than the mirror)
 *   103   = RTXGIB_ERR_CAPACITY    (owned out slot too small)
 *   -1    = bad source (null string/pointer in the shim reply)
 */

#include <windows.h>

#include <stdint.h>
#include <stddef.h>
#include <string.h>

// ===========================================================================
// Bridge status codes (kept in sync with rtxgi.xi pub consts)
// ===========================================================================

#define RTXGIB_ERR_NOT_LOADED 100
#define RTXGIB_ERR_BAD_ARGS 101
#define RTXGIB_ERR_SIZE 102
#define RTXGIB_ERR_CAPACITY 103

#define RTXGIB_LOAD_ABSENT 0
#define RTXGIB_LOAD_ABI 1
#define RTXGIB_LOAD_OK 2

// ===========================================================================
// ABI mirrors (declaration oracle: include/rtxgi/**.h @ v1.3.7, c233266e)
//
// Field order and types are copied from the public headers.  `float3`-style
// types are 3/4-float aggregates with 4-byte alignment in the SDK (Types.h),
// mirrored here as Float3M/Float4M/Int3M.
// ===========================================================================

namespace rtxgim
{

struct Float3M
{
    float x, y, z;
};

struct Float4M
{
    float x, y, z, w;
};

struct Int3M
{
    int32_t x, y, z;
};

struct DDGIVolumeDescM
{
    char* name;
    uint32_t index;
    uint32_t rngSeed;
    bool showProbes;
    bool insertPerfMarkers;
    Float3M origin;
    Float3M eulerAngles;
    Float3M probeSpacing;
    Int3M probeCounts;
    int32_t probeNumRays;
    int32_t probeNumIrradianceTexels;
    int32_t probeNumIrradianceInteriorTexels;
    int32_t probeNumDistanceTexels;
    int32_t probeNumDistanceInteriorTexels;
    float probeHysteresis;
    float probeMaxRayDistance;
    float probeDistanceExponent;
    float probeIrradianceEncodingGamma;
    float probeIrradianceThreshold;
    float probeBrightnessThreshold;
    float probeRandomRayBackfaceThreshold;
    float probeFixedRayBackfaceThreshold;
    float probeViewBias;
    float probeNormalBias;
    int32_t probeRayDataFormat;
    int32_t probeIrradianceFormat;
    int32_t probeDistanceFormat;
    int32_t probeDataFormat;
    int32_t probeVariabilityFormat;
    bool probeBlendingUseScrollSharedMemory;
    bool probeRelocationEnabled;
    bool probeRelocationNeedsReset;
    float probeMinFrontfaceDistance;
    bool probeClassificationEnabled;
    bool probeClassificationNeedsReset;
    bool probeVariabilityEnabled;
    int32_t movementType;
    int32_t probeVisType;
};

struct DDGIVolumeDescGPUM
{
    Float3M origin;
    Float4M rotation;
    Float4M probeRayRotation;
    uint32_t movementType;
    Float3M probeSpacing;
    Int3M probeCounts;
    int32_t probeNumRays;
    int32_t probeNumIrradianceInteriorTexels;
    int32_t probeNumDistanceInteriorTexels;
    float probeHysteresis;
    float probeMaxRayDistance;
    float probeNormalBias;
    float probeViewBias;
    float probeDistanceExponent;
    float probeIrradianceEncodingGamma;
    float probeIrradianceThreshold;
    float probeBrightnessThreshold;
    float probeRandomRayBackfaceThreshold;
    float probeFixedRayBackfaceThreshold;
    float probeMinFrontfaceDistance;
    Int3M probeScrollOffsets;
    bool probeScrollClear[3];
    bool probeScrollDirections[3];
    uint32_t probeRayDataFormat;
    uint32_t probeIrradianceFormat;
    bool probeRelocationEnabled;
    bool probeClassificationEnabled;
    bool probeVariabilityEnabled;
};

struct DDGIVolumeDescGPUPackedM
{
    Float3M origin;
    float probeHysteresis;
    Float4M rotation;
    Float4M probeRayRotation;
    float probeMaxRayDistance;
    float probeNormalBias;
    float probeViewBias;
    float probeDistanceExponent;
    float probeIrradianceEncodingGamma;
    float probeIrradianceThreshold;
    float probeBrightnessThreshold;
    float probeMinFrontfaceDistance;
    Float3M probeSpacing;
    uint32_t packed0;
    uint32_t packed1;
    uint32_t packed2;
    uint32_t packed3;
    uint32_t packed4;
    uint32_t reserved[4];
};

struct DDGIVolumeResourceIndicesM
{
    uint32_t rayDataUAVIndex;
    uint32_t rayDataSRVIndex;
    uint32_t probeIrradianceUAVIndex;
    uint32_t probeIrradianceSRVIndex;
    uint32_t probeDistanceUAVIndex;
    uint32_t probeDistanceSRVIndex;
    uint32_t probeDataUAVIndex;
    uint32_t probeDataSRVIndex;
    uint32_t probeVariabilityUAVIndex;
    uint32_t probeVariabilitySRVIndex;
    uint32_t probeVariabilityAverageUAVIndex;
    uint32_t probeVariabilityAverageSRVIndex;
};

struct DDGIRootConstantsM
{
    uint32_t volumeIndex;
    uint32_t volumeConstantsIndex;
    uint32_t volumeResourceIndicesIndex;
    uint32_t reductionInputSizeX;
    uint32_t reductionInputSizeY;
    uint32_t reductionInputSizeZ;
};

// ---- Layout tables (single source of field offsets/sizes for rtxgi.xi) ----

#define RTXGIB_FIELD(structType, member)             \
    (uint32_t)offsetof(structType, member),          \
        (uint32_t)sizeof(((structType*)0)->member)

static const uint32_t kDescLayout[] = {
    RTXGIB_FIELD(DDGIVolumeDescM, name), RTXGIB_FIELD(DDGIVolumeDescM, index), RTXGIB_FIELD(DDGIVolumeDescM, rngSeed),
    RTXGIB_FIELD(DDGIVolumeDescM, showProbes), RTXGIB_FIELD(DDGIVolumeDescM, insertPerfMarkers),
    RTXGIB_FIELD(DDGIVolumeDescM, origin), RTXGIB_FIELD(DDGIVolumeDescM, eulerAngles), RTXGIB_FIELD(DDGIVolumeDescM, probeSpacing),
    RTXGIB_FIELD(DDGIVolumeDescM, probeCounts), RTXGIB_FIELD(DDGIVolumeDescM, probeNumRays),
    RTXGIB_FIELD(DDGIVolumeDescM, probeNumIrradianceTexels), RTXGIB_FIELD(DDGIVolumeDescM, probeNumIrradianceInteriorTexels),
    RTXGIB_FIELD(DDGIVolumeDescM, probeNumDistanceTexels), RTXGIB_FIELD(DDGIVolumeDescM, probeNumDistanceInteriorTexels),
    RTXGIB_FIELD(DDGIVolumeDescM, probeHysteresis), RTXGIB_FIELD(DDGIVolumeDescM, probeMaxRayDistance),
    RTXGIB_FIELD(DDGIVolumeDescM, probeDistanceExponent), RTXGIB_FIELD(DDGIVolumeDescM, probeIrradianceEncodingGamma),
    RTXGIB_FIELD(DDGIVolumeDescM, probeIrradianceThreshold), RTXGIB_FIELD(DDGIVolumeDescM, probeBrightnessThreshold),
    RTXGIB_FIELD(DDGIVolumeDescM, probeRandomRayBackfaceThreshold), RTXGIB_FIELD(DDGIVolumeDescM, probeFixedRayBackfaceThreshold),
    RTXGIB_FIELD(DDGIVolumeDescM, probeViewBias), RTXGIB_FIELD(DDGIVolumeDescM, probeNormalBias),
    RTXGIB_FIELD(DDGIVolumeDescM, probeRayDataFormat), RTXGIB_FIELD(DDGIVolumeDescM, probeIrradianceFormat),
    RTXGIB_FIELD(DDGIVolumeDescM, probeDistanceFormat), RTXGIB_FIELD(DDGIVolumeDescM, probeDataFormat),
    RTXGIB_FIELD(DDGIVolumeDescM, probeVariabilityFormat), RTXGIB_FIELD(DDGIVolumeDescM, probeBlendingUseScrollSharedMemory),
    RTXGIB_FIELD(DDGIVolumeDescM, probeRelocationEnabled), RTXGIB_FIELD(DDGIVolumeDescM, probeRelocationNeedsReset),
    RTXGIB_FIELD(DDGIVolumeDescM, probeMinFrontfaceDistance), RTXGIB_FIELD(DDGIVolumeDescM, probeClassificationEnabled),
    RTXGIB_FIELD(DDGIVolumeDescM, probeClassificationNeedsReset), RTXGIB_FIELD(DDGIVolumeDescM, probeVariabilityEnabled),
    RTXGIB_FIELD(DDGIVolumeDescM, movementType), RTXGIB_FIELD(DDGIVolumeDescM, probeVisType),
};

static const uint32_t kDescGPULayout[] = {
    RTXGIB_FIELD(DDGIVolumeDescGPUM, origin), RTXGIB_FIELD(DDGIVolumeDescGPUM, rotation), RTXGIB_FIELD(DDGIVolumeDescGPUM, probeRayRotation),
    RTXGIB_FIELD(DDGIVolumeDescGPUM, movementType), RTXGIB_FIELD(DDGIVolumeDescGPUM, probeSpacing),
    RTXGIB_FIELD(DDGIVolumeDescGPUM, probeCounts), RTXGIB_FIELD(DDGIVolumeDescGPUM, probeNumRays),
    RTXGIB_FIELD(DDGIVolumeDescGPUM, probeNumIrradianceInteriorTexels), RTXGIB_FIELD(DDGIVolumeDescGPUM, probeNumDistanceInteriorTexels),
    RTXGIB_FIELD(DDGIVolumeDescGPUM, probeHysteresis), RTXGIB_FIELD(DDGIVolumeDescGPUM, probeMaxRayDistance),
    RTXGIB_FIELD(DDGIVolumeDescGPUM, probeNormalBias), RTXGIB_FIELD(DDGIVolumeDescGPUM, probeViewBias),
    RTXGIB_FIELD(DDGIVolumeDescGPUM, probeDistanceExponent), RTXGIB_FIELD(DDGIVolumeDescGPUM, probeIrradianceEncodingGamma),
    RTXGIB_FIELD(DDGIVolumeDescGPUM, probeIrradianceThreshold), RTXGIB_FIELD(DDGIVolumeDescGPUM, probeBrightnessThreshold),
    RTXGIB_FIELD(DDGIVolumeDescGPUM, probeRandomRayBackfaceThreshold), RTXGIB_FIELD(DDGIVolumeDescGPUM, probeFixedRayBackfaceThreshold),
    RTXGIB_FIELD(DDGIVolumeDescGPUM, probeMinFrontfaceDistance), RTXGIB_FIELD(DDGIVolumeDescGPUM, probeScrollOffsets),
    RTXGIB_FIELD(DDGIVolumeDescGPUM, probeScrollClear), RTXGIB_FIELD(DDGIVolumeDescGPUM, probeScrollDirections),
    RTXGIB_FIELD(DDGIVolumeDescGPUM, probeRayDataFormat), RTXGIB_FIELD(DDGIVolumeDescGPUM, probeIrradianceFormat),
    RTXGIB_FIELD(DDGIVolumeDescGPUM, probeRelocationEnabled), RTXGIB_FIELD(DDGIVolumeDescGPUM, probeClassificationEnabled),
    RTXGIB_FIELD(DDGIVolumeDescGPUM, probeVariabilityEnabled),
};

static const uint32_t kPackedLayout[] = {
    RTXGIB_FIELD(DDGIVolumeDescGPUPackedM, origin), RTXGIB_FIELD(DDGIVolumeDescGPUPackedM, probeHysteresis),
    RTXGIB_FIELD(DDGIVolumeDescGPUPackedM, rotation), RTXGIB_FIELD(DDGIVolumeDescGPUPackedM, probeRayRotation),
    RTXGIB_FIELD(DDGIVolumeDescGPUPackedM, probeMaxRayDistance), RTXGIB_FIELD(DDGIVolumeDescGPUPackedM, probeNormalBias),
    RTXGIB_FIELD(DDGIVolumeDescGPUPackedM, probeViewBias), RTXGIB_FIELD(DDGIVolumeDescGPUPackedM, probeDistanceExponent),
    RTXGIB_FIELD(DDGIVolumeDescGPUPackedM, probeIrradianceEncodingGamma), RTXGIB_FIELD(DDGIVolumeDescGPUPackedM, probeIrradianceThreshold),
    RTXGIB_FIELD(DDGIVolumeDescGPUPackedM, probeBrightnessThreshold), RTXGIB_FIELD(DDGIVolumeDescGPUPackedM, probeMinFrontfaceDistance),
    RTXGIB_FIELD(DDGIVolumeDescGPUPackedM, probeSpacing), RTXGIB_FIELD(DDGIVolumeDescGPUPackedM, packed0),
    RTXGIB_FIELD(DDGIVolumeDescGPUPackedM, packed1), RTXGIB_FIELD(DDGIVolumeDescGPUPackedM, packed2),
    RTXGIB_FIELD(DDGIVolumeDescGPUPackedM, packed3), RTXGIB_FIELD(DDGIVolumeDescGPUPackedM, packed4),
    RTXGIB_FIELD(DDGIVolumeDescGPUPackedM, reserved),
};

static const uint32_t kResourceIndicesLayout[] = {
    RTXGIB_FIELD(DDGIVolumeResourceIndicesM, rayDataUAVIndex), RTXGIB_FIELD(DDGIVolumeResourceIndicesM, rayDataSRVIndex),
    RTXGIB_FIELD(DDGIVolumeResourceIndicesM, probeIrradianceUAVIndex), RTXGIB_FIELD(DDGIVolumeResourceIndicesM, probeIrradianceSRVIndex),
    RTXGIB_FIELD(DDGIVolumeResourceIndicesM, probeDistanceUAVIndex), RTXGIB_FIELD(DDGIVolumeResourceIndicesM, probeDistanceSRVIndex),
    RTXGIB_FIELD(DDGIVolumeResourceIndicesM, probeDataUAVIndex), RTXGIB_FIELD(DDGIVolumeResourceIndicesM, probeDataSRVIndex),
    RTXGIB_FIELD(DDGIVolumeResourceIndicesM, probeVariabilityUAVIndex), RTXGIB_FIELD(DDGIVolumeResourceIndicesM, probeVariabilitySRVIndex),
    RTXGIB_FIELD(DDGIVolumeResourceIndicesM, probeVariabilityAverageUAVIndex), RTXGIB_FIELD(DDGIVolumeResourceIndicesM, probeVariabilityAverageSRVIndex),
};

static const uint32_t kRootConstantsLayout[] = {
    RTXGIB_FIELD(DDGIRootConstantsM, volumeIndex), RTXGIB_FIELD(DDGIRootConstantsM, volumeConstantsIndex),
    RTXGIB_FIELD(DDGIRootConstantsM, volumeResourceIndicesIndex), RTXGIB_FIELD(DDGIRootConstantsM, reductionInputSizeX),
    RTXGIB_FIELD(DDGIRootConstantsM, reductionInputSizeY), RTXGIB_FIELD(DDGIRootConstantsM, reductionInputSizeZ),
};

#undef RTXGIB_FIELD

} // namespace rtxgim

// ===========================================================================
// Shim entry points (resolved at run time; names fixed by the shim contract)
// ===========================================================================

typedef int32_t (*PFN_shim_info)(uint8_t*, int32_t);
typedef int32_t (*PFN_shim_counts)(uint8_t*, int32_t);
typedef int32_t (*PFN_shim_i1)(int32_t);
typedef void (*PFN_shim_setbool)(int32_t);
typedef int32_t (*PFN_shim_getbool)();
typedef int32_t (*PFN_shim_desc3)(const uint8_t*, int32_t, uint8_t*, int32_t);
typedef int32_t (*PFN_shim_desc4)(const uint8_t*, int32_t, int32_t, uint8_t*, int32_t);
typedef int32_t (*PFN_shim_defdesc)(uint8_t*, int32_t);
typedef int32_t (*PFN_shim_layout)(int32_t, uint8_t*, int32_t);
typedef int64_t (*PFN_shim_vcreate)(const uint8_t*, int32_t);
typedef int32_t (*PFN_shim_v1)(int64_t);
typedef int32_t (*PFN_shim_vseed)(int64_t, int32_t);
typedef int32_t (*PFN_shim_vrandom)(int64_t, uint8_t*);
typedef int32_t (*PFN_shim_vseti)(int64_t, int32_t);
typedef int32_t (*PFN_shim_vset3)(int64_t, float, float, float);
typedef int32_t (*PFN_shim_vsetf)(int64_t, float);
typedef int32_t (*PFN_shim_vget3)(int64_t, uint8_t*);
typedef int32_t (*PFN_shim_vgetc)(int64_t, uint8_t*, int32_t);
typedef int32_t (*PFN_shim_vi)(int64_t);
typedef int32_t (*PFN_shim_vpwp)(int64_t, int32_t, uint8_t*);

static HMODULE g_module = 0;
static int32_t g_load_kind = RTXGIB_LOAD_ABSENT;

static PFN_shim_info g_info = 0;
static PFN_shim_counts g_descriptor_counts = 0;
static PFN_shim_i1 g_validate_bytecode = 0;
static PFN_shim_setbool g_set_perf_markers = 0;
static PFN_shim_getbool g_get_perf_markers = 0;
static PFN_shim_desc3 g_probe_counts = 0;
static PFN_shim_desc4 g_texture_dimensions = 0;
static PFN_shim_defdesc g_sdk_default_desc = 0;
static PFN_shim_layout g_sdk_layout = 0;
static PFN_shim_vcreate g_volume_create = 0;
static PFN_shim_v1 g_volume_destroy = 0;
static PFN_shim_v1 g_volume_update = 0;
static PFN_shim_vseed g_volume_seed_rng = 0;
static PFN_shim_vrandom g_volume_get_random = 0;
static PFN_shim_vseti g_volume_set_movement_type = 0;
static PFN_shim_vset3 g_volume_set_origin = 0;
static PFN_shim_vset3 g_volume_set_scroll_anchor = 0;
static PFN_shim_vsetf g_volume_set_probe_hysteresis = 0;
static PFN_shim_vset3 g_volume_set_euler_angles = 0;
static PFN_shim_vget3 g_volume_get_origin = 0;
static PFN_shim_vgetc g_volume_get_gpu_desc = 0;
static PFN_shim_vgetc g_volume_get_gpu_desc_packed = 0;
static PFN_shim_vi g_volume_num_probes = 0;
static PFN_shim_vi g_volume_num_rays = 0;
static PFN_shim_vi g_volume_tex2darray_size = 0;
static PFN_shim_vget3 g_volume_ray_dispatch = 0;
static PFN_shim_vi g_volume_gpu_memory = 0;
static PFN_shim_vget3 g_volume_aabb = 0;
static PFN_shim_vget3 g_volume_obb = 0;
static PFN_shim_vpwp g_volume_probe_world_pos = 0;

// ===========================================================================
// Small helpers
// ===========================================================================

static void rtxgib_wr_u32(uint8_t* dst, uint32_t v)
{
    dst[0] = (uint8_t)(v & 0xFF);
    dst[1] = (uint8_t)((v >> 8) & 0xFF);
    dst[2] = (uint8_t)((v >> 16) & 0xFF);
    dst[3] = (uint8_t)((v >> 24) & 0xFF);
}

static void rtxgib_reset_state()
{
    g_module = 0;
    g_load_kind = RTXGIB_LOAD_ABSENT;
    g_info = 0;
    g_descriptor_counts = 0;
    g_validate_bytecode = 0;
    g_set_perf_markers = 0;
    g_get_perf_markers = 0;
    g_probe_counts = 0;
    g_texture_dimensions = 0;
    g_sdk_default_desc = 0;
    g_sdk_layout = 0;
    g_volume_create = 0;
    g_volume_destroy = 0;
    g_volume_update = 0;
    g_volume_seed_rng = 0;
    g_volume_get_random = 0;
    g_volume_set_movement_type = 0;
    g_volume_set_origin = 0;
    g_volume_set_scroll_anchor = 0;
    g_volume_set_probe_hysteresis = 0;
    g_volume_set_euler_angles = 0;
    g_volume_get_origin = 0;
    g_volume_get_gpu_desc = 0;
    g_volume_get_gpu_desc_packed = 0;
    g_volume_num_probes = 0;
    g_volume_num_rays = 0;
    g_volume_tex2darray_size = 0;
    g_volume_ray_dispatch = 0;
    g_volume_gpu_memory = 0;
    g_volume_aabb = 0;
    g_volume_obb = 0;
    g_volume_probe_world_pos = 0;
}

static int64_t rtxgib_finish_load(HMODULE module)
{
    g_info = (PFN_shim_info)(void*)GetProcAddress(module, "rtxgishim_info");
    g_descriptor_counts = (PFN_shim_counts)(void*)GetProcAddress(module, "rtxgishim_descriptor_counts");
    g_validate_bytecode = (PFN_shim_i1)(void*)GetProcAddress(module, "rtxgishim_validate_shader_bytecode");
    g_set_perf_markers = (PFN_shim_setbool)(void*)GetProcAddress(module, "rtxgishim_set_insert_perf_markers");
    g_get_perf_markers = (PFN_shim_getbool)(void*)GetProcAddress(module, "rtxgishim_get_insert_perf_markers");
    g_probe_counts = (PFN_shim_desc3)(void*)GetProcAddress(module, "rtxgishim_probe_counts");
    g_texture_dimensions = (PFN_shim_desc4)(void*)GetProcAddress(module, "rtxgishim_texture_dimensions");
    g_sdk_default_desc = (PFN_shim_defdesc)(void*)GetProcAddress(module, "rtxgishim_default_desc");
    g_sdk_layout = (PFN_shim_layout)(void*)GetProcAddress(module, "rtxgishim_layout");
    g_volume_create = (PFN_shim_vcreate)(void*)GetProcAddress(module, "rtxgishim_volume_create");
    g_volume_destroy = (PFN_shim_v1)(void*)GetProcAddress(module, "rtxgishim_volume_destroy");
    g_volume_update = (PFN_shim_v1)(void*)GetProcAddress(module, "rtxgishim_volume_update");
    g_volume_seed_rng = (PFN_shim_vseed)(void*)GetProcAddress(module, "rtxgishim_volume_seed_rng");
    g_volume_get_random = (PFN_shim_vrandom)(void*)GetProcAddress(module, "rtxgishim_volume_get_random");
    g_volume_set_movement_type = (PFN_shim_vseti)(void*)GetProcAddress(module, "rtxgishim_volume_set_movement_type");
    g_volume_set_origin = (PFN_shim_vset3)(void*)GetProcAddress(module, "rtxgishim_volume_set_origin");
    g_volume_set_scroll_anchor = (PFN_shim_vset3)(void*)GetProcAddress(module, "rtxgishim_volume_set_scroll_anchor");
    g_volume_set_probe_hysteresis = (PFN_shim_vsetf)(void*)GetProcAddress(module, "rtxgishim_volume_set_probe_hysteresis");
    g_volume_set_euler_angles = (PFN_shim_vset3)(void*)GetProcAddress(module, "rtxgishim_volume_set_euler_angles");
    g_volume_get_origin = (PFN_shim_vget3)(void*)GetProcAddress(module, "rtxgishim_volume_get_origin");
    g_volume_get_gpu_desc = (PFN_shim_vgetc)(void*)GetProcAddress(module, "rtxgishim_volume_get_gpu_desc");
    g_volume_get_gpu_desc_packed = (PFN_shim_vgetc)(void*)GetProcAddress(module, "rtxgishim_volume_get_gpu_desc_packed");
    g_volume_num_probes = (PFN_shim_vi)(void*)GetProcAddress(module, "rtxgishim_volume_num_probes");
    g_volume_num_rays = (PFN_shim_vi)(void*)GetProcAddress(module, "rtxgishim_volume_num_rays");
    g_volume_tex2darray_size = (PFN_shim_vi)(void*)GetProcAddress(module, "rtxgishim_volume_tex2darray_size");
    g_volume_ray_dispatch = (PFN_shim_vget3)(void*)GetProcAddress(module, "rtxgishim_volume_ray_dispatch");
    g_volume_gpu_memory = (PFN_shim_vi)(void*)GetProcAddress(module, "rtxgishim_volume_gpu_memory");
    g_volume_aabb = (PFN_shim_vget3)(void*)GetProcAddress(module, "rtxgishim_volume_aabb");
    g_volume_obb = (PFN_shim_vget3)(void*)GetProcAddress(module, "rtxgishim_volume_obb");
    g_volume_probe_world_pos = (PFN_shim_vpwp)(void*)GetProcAddress(module, "rtxgishim_volume_probe_world_pos");

    if (!g_info || !g_descriptor_counts || !g_validate_bytecode || !g_set_perf_markers || !g_get_perf_markers ||
        !g_probe_counts || !g_texture_dimensions || !g_sdk_default_desc || !g_sdk_layout ||
        !g_volume_create || !g_volume_destroy || !g_volume_update || !g_volume_seed_rng || !g_volume_get_random ||
        !g_volume_set_movement_type || !g_volume_set_origin || !g_volume_set_scroll_anchor ||
        !g_volume_set_probe_hysteresis || !g_volume_set_euler_angles || !g_volume_get_origin ||
        !g_volume_get_gpu_desc || !g_volume_get_gpu_desc_packed || !g_volume_num_probes ||
        !g_volume_num_rays || !g_volume_tex2darray_size || !g_volume_ray_dispatch || !g_volume_gpu_memory ||
        !g_volume_aabb || !g_volume_obb || !g_volume_probe_world_pos)
    {
        FreeLibrary(module);
        rtxgib_reset_state();
        g_load_kind = RTXGIB_LOAD_ABI;
        return 0;
    }

    g_module = module;
    g_load_kind = RTXGIB_LOAD_OK;
    return (int64_t)(intptr_t)module;
}

static int32_t rtxgib_check(int64_t handle)
{
    if (handle == 0) return RTXGIB_ERR_BAD_ARGS;
    if (g_module == 0 || (HMODULE)(intptr_t)handle != g_module) return RTXGIB_ERR_NOT_LOADED;
    return 0;
}

// ===========================================================================
// extern "C" surface
// ===========================================================================

extern "C" {

// ---- Loader ---------------------------------------------------------------

int64_t rtxgib_try_load(const uint8_t* path, int32_t len)
{
    char buffer[1024 + 1];
    HMODULE module;

    if (g_module != 0) return (int64_t)(intptr_t)g_module;
    if (path == 0 || len <= 0 || len > 1024) return 0;

    memcpy(buffer, path, (size_t)len);
    buffer[len] = 0;

    module = LoadLibraryA(buffer);
    if (module == 0)
    {
        g_load_kind = RTXGIB_LOAD_ABSENT;
        return 0;
    }
    return rtxgib_finish_load(module);
}

int64_t rtxgib_try_load_auto()
{
    char buffer[1024 + 1];
    DWORD n;
    HMODULE module;

    if (g_module != 0) return (int64_t)(intptr_t)g_module;

    n = GetEnvironmentVariableA("XIOM_RTXGI_SHIM", buffer, 1024);
    if (n > 0 && n < 1024)
    {
        module = LoadLibraryA(buffer);
        if (module != 0) return rtxgib_finish_load(module);
    }

    module = LoadLibraryA("xiom_rtxgi_shim.dll");
    if (module == 0)
    {
        g_load_kind = RTXGIB_LOAD_ABSENT;
        return 0;
    }
    return rtxgib_finish_load(module);
}

int32_t rtxgib_load_kind() { return g_load_kind; }

int32_t rtxgib_close(int64_t handle)
{
    HMODULE module;

    if (handle == 0) return 0;
    if (g_module != (HMODULE)(intptr_t)handle) return RTXGIB_ERR_BAD_ARGS;
    module = g_module;
    rtxgib_reset_state();
    FreeLibrary(module);
    return 0;
}

// ---- Layout tables + defaults (ours; no shim needed) -----------------------

int32_t rtxgib_layout(int32_t kind, uint8_t* offsets, uint8_t* sizes, int32_t cap)
{
    const uint32_t* table = 0;
    uint32_t count = 0;
    uint32_t i;

    switch (kind)
    {
    case 0: table = rtxgim::kDescLayout; count = (uint32_t)(sizeof(rtxgim::kDescLayout) / sizeof(uint32_t)) / 2; break;
    case 1: table = rtxgim::kDescGPULayout; count = (uint32_t)(sizeof(rtxgim::kDescGPULayout) / sizeof(uint32_t)) / 2; break;
    case 2: table = rtxgim::kPackedLayout; count = (uint32_t)(sizeof(rtxgim::kPackedLayout) / sizeof(uint32_t)) / 2; break;
    case 3: table = rtxgim::kResourceIndicesLayout; count = (uint32_t)(sizeof(rtxgim::kResourceIndicesLayout) / sizeof(uint32_t)) / 2; break;
    case 4: table = rtxgim::kRootConstantsLayout; count = (uint32_t)(sizeof(rtxgim::kRootConstantsLayout) / sizeof(uint32_t)) / 2; break;
    default: return RTXGIB_ERR_BAD_ARGS;
    }

    if (offsets == 0 || sizes == 0) return (int32_t)count; // count probe
    if ((int32_t)count > cap) return RTXGIB_ERR_CAPACITY;

    for (i = 0; i < count; i++)
    {
        rtxgib_wr_u32(offsets + (size_t)i * 4, table[i * 2 + 0]);
        rtxgib_wr_u32(sizes + (size_t)i * 4, table[i * 2 + 1]);
    }
    return (int32_t)count;
}

int32_t rtxgib_layout_size(int32_t kind)
{
    switch (kind)
    {
    case 0: return (int32_t)sizeof(rtxgim::DDGIVolumeDescM);
    case 1: return (int32_t)sizeof(rtxgim::DDGIVolumeDescGPUM);
    case 2: return (int32_t)sizeof(rtxgim::DDGIVolumeDescGPUPackedM);
    case 3: return (int32_t)sizeof(rtxgim::DDGIVolumeResourceIndicesM);
    case 4: return (int32_t)sizeof(rtxgim::DDGIRootConstantsM);
    default: return -1;
    }
}

int32_t rtxgib_desc_default(uint8_t* dst, int32_t cap)
{
    rtxgim::DDGIVolumeDescM defaults;
    memset(&defaults, 0, sizeof(defaults));
    defaults.name = 0;
    defaults.index = 0;
    defaults.rngSeed = 0;
    defaults.showProbes = false;
    defaults.insertPerfMarkers = false;
    defaults.probeCounts.x = -1;
    defaults.probeCounts.y = -1;
    defaults.probeCounts.z = -1;
    defaults.probeNumRays = 256;
    defaults.probeNumIrradianceTexels = -1;
    defaults.probeNumIrradianceInteriorTexels = -1;
    defaults.probeNumDistanceTexels = -1;
    defaults.probeNumDistanceInteriorTexels = -1;
    defaults.probeHysteresis = 0.97f;
    defaults.probeMaxRayDistance = 1e27f;
    defaults.probeDistanceExponent = 50.f;
    defaults.probeIrradianceEncodingGamma = 5.f;
    defaults.probeIrradianceThreshold = 0.25f;
    defaults.probeBrightnessThreshold = 0.10f;
    defaults.probeRandomRayBackfaceThreshold = 0.1f;
    defaults.probeFixedRayBackfaceThreshold = 0.25f;
    defaults.probeViewBias = 0.1f;
    defaults.probeNormalBias = 0.1f;
    defaults.probeRayDataFormat = 0;   // EDDGIVolumeTextureFormat::U32
    defaults.probeIrradianceFormat = 0;
    defaults.probeDistanceFormat = 0;
    defaults.probeDataFormat = 0;
    defaults.probeVariabilityFormat = 0;
    defaults.probeBlendingUseScrollSharedMemory = false;
    defaults.probeRelocationEnabled = false;
    defaults.probeRelocationNeedsReset = false;
    defaults.probeMinFrontfaceDistance = 1.f;
    defaults.probeClassificationEnabled = false;
    defaults.probeClassificationNeedsReset = false;
    defaults.probeVariabilityEnabled = false;
    defaults.movementType = 0; // EDDGIVolumeMovementType::Default
    defaults.probeVisType = 0; // EDDGIVolumeProbeVisType::Default

    if (dst == 0) return RTXGIB_ERR_BAD_ARGS;
    if (cap < (int32_t)sizeof(defaults)) return RTXGIB_ERR_SIZE;
    memcpy(dst, &defaults, sizeof(defaults));
    return 0;
}

// ---- Forwarded surface ------------------------------------------------------

int32_t rtxgib_info(int64_t handle, uint8_t* out, int32_t cap)
{
    int32_t rc = rtxgib_check(handle);
    if (rc != 0) return rc;
    if (out == 0 || cap < 32) return RTXGIB_ERR_BAD_ARGS;
    return g_info(out, cap);
}

int32_t rtxgib_sdk_layout(int64_t handle, int32_t kind, uint8_t* out, int32_t cap)
{
    int32_t rc = rtxgib_check(handle);
    if (rc != 0) return rc;
    if (out == 0) return RTXGIB_ERR_BAD_ARGS;
    return g_sdk_layout(kind, out, cap);
}

int32_t rtxgib_sdk_default_desc(int64_t handle, uint8_t* dst, int32_t cap)
{
    int32_t rc = rtxgib_check(handle);
    if (rc != 0) return rc;
    if (dst == 0) return RTXGIB_ERR_BAD_ARGS;
    return g_sdk_default_desc(dst, cap);
}

int32_t rtxgib_descriptor_counts(int64_t handle, uint8_t* out, int32_t cap)
{
    int32_t rc = rtxgib_check(handle);
    if (rc != 0) return rc;
    if (out == 0 || cap < 12) return RTXGIB_ERR_BAD_ARGS;
    return g_descriptor_counts(out, cap);
}

int32_t rtxgib_validate_shader_bytecode(int64_t handle, int32_t size)
{
    int32_t rc = rtxgib_check(handle);
    if (rc != 0) return rc;
    return g_validate_bytecode(size);
}

int32_t rtxgib_set_insert_perf_markers(int64_t handle, int32_t v)
{
    int32_t rc = rtxgib_check(handle);
    if (rc != 0) return rc;
    g_set_perf_markers(v);
    return 0;
}

int32_t rtxgib_get_insert_perf_markers(int64_t handle)
{
    int32_t rc = rtxgib_check(handle);
    if (rc != 0) return rc;
    return g_get_perf_markers();
}

int32_t rtxgib_probe_counts(int64_t handle, const uint8_t* desc, int32_t size, uint8_t* out, int32_t cap)
{
    int32_t rc = rtxgib_check(handle);
    if (rc != 0) return rc;
    if (desc == 0 || out == 0 || cap < 12) return RTXGIB_ERR_BAD_ARGS;
    if (size < (int32_t)sizeof(rtxgim::DDGIVolumeDescM)) return RTXGIB_ERR_SIZE;
    return g_probe_counts(desc, size, out, cap);
}

int32_t rtxgib_texture_dimensions(int64_t handle, const uint8_t* desc, int32_t size, int32_t type, uint8_t* out, int32_t cap)
{
    int32_t rc = rtxgib_check(handle);
    if (rc != 0) return rc;
    if (desc == 0 || out == 0 || cap < 12) return RTXGIB_ERR_BAD_ARGS;
    if (size < (int32_t)sizeof(rtxgim::DDGIVolumeDescM)) return RTXGIB_ERR_SIZE;
    return g_texture_dimensions(desc, size, type, out, cap);
}

// ---- Volume lifecycle + surface ---------------------------------------------

int32_t rtxgib_volume_create(int64_t handle, const uint8_t* desc, int32_t size, uint8_t* out)
{
    int32_t rc = rtxgib_check(handle);
    int64_t v;
    int i;

    if (rc != 0) return rc;
    if (desc == 0 || out == 0) return RTXGIB_ERR_BAD_ARGS;
    if (size < (int32_t)sizeof(rtxgim::DDGIVolumeDescM)) return RTXGIB_ERR_SIZE;

    v = g_volume_create(desc, size);
    if (v == 0) return 1; // creation failed (SDK-side)
    for (i = 0; i < 8; i++) out[i] = (uint8_t)(((uint64_t)v >> (8 * i)) & 0xFF);
    return 0;
}

int32_t rtxgib_volume_destroy(int64_t handle, int64_t volume)
{
    int32_t rc = rtxgib_check(handle);
    if (rc != 0) return rc;
    if (volume == 0) return RTXGIB_ERR_BAD_ARGS;
    return g_volume_destroy(volume);
}

int32_t rtxgib_volume_update(int64_t handle, int64_t volume)
{
    int32_t rc = rtxgib_check(handle);
    if (rc != 0) return rc;
    if (volume == 0) return RTXGIB_ERR_BAD_ARGS;
    return g_volume_update(volume);
}

int32_t rtxgib_volume_seed_rng(int64_t handle, int64_t volume, int32_t seed)
{
    int32_t rc = rtxgib_check(handle);
    if (rc != 0) return rc;
    if (volume == 0) return RTXGIB_ERR_BAD_ARGS;
    return g_volume_seed_rng(volume, seed);
}

int32_t rtxgib_volume_get_random(int64_t handle, int64_t volume, uint8_t* out)
{
    int32_t rc = rtxgib_check(handle);
    if (rc != 0) return rc;
    if (volume == 0 || out == 0) return RTXGIB_ERR_BAD_ARGS;
    return g_volume_get_random(volume, out);
}

int32_t rtxgib_volume_set_movement_type(int64_t handle, int64_t volume, int32_t v)
{
    int32_t rc = rtxgib_check(handle);
    if (rc != 0) return rc;
    if (volume == 0) return RTXGIB_ERR_BAD_ARGS;
    return g_volume_set_movement_type(volume, v);
}

int32_t rtxgib_volume_set_origin(int64_t handle, int64_t volume, float x, float y, float z)
{
    int32_t rc = rtxgib_check(handle);
    if (rc != 0) return rc;
    if (volume == 0) return RTXGIB_ERR_BAD_ARGS;
    return g_volume_set_origin(volume, x, y, z);
}

int32_t rtxgib_volume_set_scroll_anchor(int64_t handle, int64_t volume, float x, float y, float z)
{
    int32_t rc = rtxgib_check(handle);
    if (rc != 0) return rc;
    if (volume == 0) return RTXGIB_ERR_BAD_ARGS;
    return g_volume_set_scroll_anchor(volume, x, y, z);
}

int32_t rtxgib_volume_set_probe_hysteresis(int64_t handle, int64_t volume, float v)
{
    int32_t rc = rtxgib_check(handle);
    if (rc != 0) return rc;
    if (volume == 0) return RTXGIB_ERR_BAD_ARGS;
    return g_volume_set_probe_hysteresis(volume, v);
}

int32_t rtxgib_volume_set_euler_angles(int64_t handle, int64_t volume, float x, float y, float z)
{
    int32_t rc = rtxgib_check(handle);
    if (rc != 0) return rc;
    if (volume == 0) return RTXGIB_ERR_BAD_ARGS;
    return g_volume_set_euler_angles(volume, x, y, z);
}

int32_t rtxgib_volume_get_origin(int64_t handle, int64_t volume, uint8_t* out)
{
    int32_t rc = rtxgib_check(handle);
    if (rc != 0) return rc;
    if (volume == 0 || out == 0) return RTXGIB_ERR_BAD_ARGS;
    return g_volume_get_origin(volume, out);
}

int32_t rtxgib_volume_get_gpu_desc(int64_t handle, int64_t volume, uint8_t* out, int32_t cap)
{
    int32_t rc = rtxgib_check(handle);
    if (rc != 0) return rc;
    if (volume == 0 || out == 0) return RTXGIB_ERR_BAD_ARGS;
    return g_volume_get_gpu_desc(volume, out, cap);
}

int32_t rtxgib_volume_get_gpu_desc_packed(int64_t handle, int64_t volume, uint8_t* out, int32_t cap)
{
    int32_t rc = rtxgib_check(handle);
    if (rc != 0) return rc;
    if (volume == 0 || out == 0) return RTXGIB_ERR_BAD_ARGS;
    return g_volume_get_gpu_desc_packed(volume, out, cap);
}

int32_t rtxgib_volume_num_probes(int64_t handle, int64_t volume)
{
    int32_t rc = rtxgib_check(handle);
    if (rc != 0) return rc;
    if (volume == 0) return RTXGIB_ERR_BAD_ARGS;
    return g_volume_num_probes(volume);
}

int32_t rtxgib_volume_num_rays(int64_t handle, int64_t volume)
{
    int32_t rc = rtxgib_check(handle);
    if (rc != 0) return rc;
    if (volume == 0) return RTXGIB_ERR_BAD_ARGS;
    return g_volume_num_rays(volume);
}

int32_t rtxgib_volume_tex2darray_size(int64_t handle, int64_t volume)
{
    int32_t rc = rtxgib_check(handle);
    if (rc != 0) return rc;
    if (volume == 0) return RTXGIB_ERR_BAD_ARGS;
    return g_volume_tex2darray_size(volume);
}

int32_t rtxgib_volume_ray_dispatch(int64_t handle, int64_t volume, uint8_t* out)
{
    int32_t rc = rtxgib_check(handle);
    if (rc != 0) return rc;
    if (volume == 0 || out == 0) return RTXGIB_ERR_BAD_ARGS;
    return g_volume_ray_dispatch(volume, out);
}

int32_t rtxgib_volume_gpu_memory(int64_t handle, int64_t volume)
{
    int32_t rc = rtxgib_check(handle);
    if (rc != 0) return rc;
    if (volume == 0) return RTXGIB_ERR_BAD_ARGS;
    return g_volume_gpu_memory(volume);
}

int32_t rtxgib_volume_aabb(int64_t handle, int64_t volume, uint8_t* out)
{
    int32_t rc = rtxgib_check(handle);
    if (rc != 0) return rc;
    if (volume == 0 || out == 0) return RTXGIB_ERR_BAD_ARGS;
    return g_volume_aabb(volume, out);
}

int32_t rtxgib_volume_obb(int64_t handle, int64_t volume, uint8_t* out)
{
    int32_t rc = rtxgib_check(handle);
    if (rc != 0) return rc;
    if (volume == 0 || out == 0) return RTXGIB_ERR_BAD_ARGS;
    return g_volume_obb(volume, out);
}

int32_t rtxgib_volume_probe_world_pos(int64_t handle, int64_t volume, int32_t index, uint8_t* out)
{
    int32_t rc = rtxgib_check(handle);
    if (rc != 0) return rc;
    if (volume == 0 || out == 0 || index < 0) return RTXGIB_ERR_BAD_ARGS;
    return g_volume_probe_world_pos(volume, index, out);
}

// ---- Execute (typed device requirement) -------------------------------------

int32_t rtxgib_execute(int64_t handle, int64_t volume)
{
    // No GPU device bridge ships in this wave (PROVENANCE.md / SPEC.md):
    // executing DDGI passes requires the application's D3D12/VK device, the
    // probe textures/descriptor heaps and the compiled shaders.  The CPU-side
    // model is validated by the caller; the device path is a typed SKIP state
    // (RTXGI_EXEC_NO_DEVICE = 2), never a silent success.
    int32_t rc = rtxgib_check(handle);
    if (rc != 0) return 1; // RTXGI_EXEC_INVALID
    if (volume == 0) return 1;
    return 2; // RTXGI_EXEC_NO_DEVICE
}

// ---- Owned-image scalar accessors (XIOM-owned slots; B-17/B-24) -------------

int32_t rtxgib_img_set_u32(uint8_t* dst, int32_t cap, int32_t off, int32_t v)
{
    if (dst == 0 || off < 0 || cap < off + 4) return RTXGIB_ERR_BAD_ARGS;
    rtxgib_wr_u32(dst + off, (uint32_t)v);
    return 0;
}

int32_t rtxgib_img_set_u16(uint8_t* dst, int32_t cap, int32_t off, int32_t v)
{
    if (dst == 0 || off < 0 || cap < off + 2) return RTXGIB_ERR_BAD_ARGS;
    dst[off + 0] = (uint8_t)(v & 0xFF);
    dst[off + 1] = (uint8_t)((v >> 8) & 0xFF);
    return 0;
}

int32_t rtxgib_img_set_u8(uint8_t* dst, int32_t cap, int32_t off, int32_t v)
{
    if (dst == 0 || off < 0 || cap < off + 1) return RTXGIB_ERR_BAD_ARGS;
    dst[off] = (uint8_t)(v & 0xFF);
    return 0;
}

int32_t rtxgib_img_set_f32(uint8_t* dst, int32_t cap, int32_t off, float v)
{
    if (dst == 0 || off < 0 || cap < off + 4) return RTXGIB_ERR_BAD_ARGS;
    memcpy(dst + off, &v, 4);
    return 0;
}

int32_t rtxgib_img_get_u32(const uint8_t* src, int32_t cap, int32_t off)
{
    if (src == 0 || off < 0 || cap < off + 4) return -1;
    return (int32_t)((uint32_t)src[off] | ((uint32_t)src[off + 1] << 8) | ((uint32_t)src[off + 2] << 16) | ((uint32_t)src[off + 3] << 24));
}

int32_t rtxgib_img_get_i32(const uint8_t* src, int32_t cap, int32_t off)
{
    int32_t v = 0;
    if (src == 0 || off < 0 || cap < off + 4) return 0;
    memcpy(&v, src + off, 4);
    return v;
}

int32_t rtxgib_img_get_u16(const uint8_t* src, int32_t cap, int32_t off)
{
    if (src == 0 || off < 0 || cap < off + 2) return -1;
    return (int32_t)((uint32_t)src[off] | ((uint32_t)src[off + 1] << 8));
}

int32_t rtxgib_img_get_u8(const uint8_t* src, int32_t cap, int32_t off)
{
    if (src == 0 || off < 0 || cap < off + 1) return -1;
    return (int32_t)src[off];
}

float rtxgib_img_get_f32(const uint8_t* src, int32_t cap, int32_t off)
{
    float v = 0.0f;
    if (src == 0 || off < 0 || cap < off + 4) return 0.0f;
    memcpy(&v, src + off, 4);
    return v;
}

} // extern "C"
