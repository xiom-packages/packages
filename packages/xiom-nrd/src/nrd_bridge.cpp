/* XIOM -- xiom.nrd: XIOM-side dynamic-loader bridge for the NVIDIA NRD
 * runtime.  Copyright (c) 2026 Eleftherios Notas and The XIOM Authors.
 * SPDX-License-Identifier: MIT OR Apache-2.0
 *
 * This file is OUR code, not NVIDIA code.  It copies NOTHING from the NRD
 * SDK and links NOTHING from it at build time -- the NRD integration layer
 * never ships in this repository (see PROVENANCE.md: the upstream is the
 * proprietary NVIDIA RTX SDKs License, reference-only policy, FFmpeg
 * precedent).  The bridge exists because the v0.64.4 FFI discipline
 * (findings B-20/B-21/B-23/B-24/B-25/B-26) cannot:
 *
 *   1. load a runtime module and resolve entry points -- done here with
 *      LoadLibraryA/GetProcAddress; the module handle and the NRD instance
 *      pointer cross the ABI as Int (int64_t) and are cast to pointers in
 *      C++ only (B-25);
 *
 *   2. lay out the public request/response structs (InstanceCreationDesc,
 *      CommonSettings, ReblurSettings, ..., DispatchDesc) for calls into
 *      the runtime: the ABI mirror structs below are written from the
 *      public header declarations at the pinned commit (the "declaration
 *      oracle", PROVENANCE.md) -- NRD.h, NRDDescs.h, NRDSettings.h
 *      @ v4.17.3 (792eff19).  Layout facts only, no upstream code;
 *
 *   3. copy response data (library desc, instance desc, dispatch plans,
 *      constant buffers, resource lists) out of runtime-owned memory into
 *      XIOM-owned slots: this file does that copy; XIOM reads only its own
 *      slots, byte-indexed (B-20/B-24), one owned slot per out-param;
 *
 *   4. provide aligned allocation callbacks for the runtime (Allocate /
 *      Reallocate / Free) -- implemented here with header-prefixed
 *      over-allocation.
 *
 * All bridge state is single-threaded process state (the suite is
 * single-threaded; document any parallel use as a new constraint).
 *
 * Bridge return codes (int32):
 *   0..4  = nrd::Result as returned by the runtime (see nrd.xi constants)
 *   100   = NRDB_ERR_NOT_LOADED  (no runtime loaded)
 *   101   = NRDB_ERR_BAD_ARGS
 *   102   = NRDB_ERR_SIZE        (owned image smaller than the mirror)
 *   103   = NRDB_ERR_CAPACITY    (owned out slot too small)
 *   -1    = string fetch returned null (no such enum value)
 */

#include <windows.h>

#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include <stdlib.h>

// ===========================================================================
// Bridge status codes (kept in sync with nrd.xi pub consts)
// ===========================================================================

#define NRDB_ERR_NOT_LOADED 100
#define NRDB_ERR_BAD_ARGS 101
#define NRDB_ERR_SIZE 102
#define NRDB_ERR_CAPACITY 103

#define NRDB_LOAD_ABSENT 0
#define NRDB_LOAD_ABI 1
#define NRDB_LOAD_OK 2

#define NRDB_SUMMARY_SIZE 96   // per-dispatch summary record
#define NRDB_RES_REC_SIZE 16   // per-resource record
#define NRDB_MAX_DENOISERS 64

// ===========================================================================
// ABI mirrors (declaration oracle: Include/*.h @ v4.17.3, 792eff19)
//
// Field order and types are copied from the public headers; default member
// initializers mirror the in-class defaults in NRDSettings.h so
// `*_settings_default` reproduces the documented defaults.
// ===========================================================================

namespace nrdm
{

struct AllocationCallbacksM
{
    void* (__stdcall* Allocate)(void* userArg, size_t size, size_t alignment);
    void* (__stdcall* Reallocate)(void* userArg, void* memory, size_t size, size_t alignment);
    void (__stdcall* Free)(void* userArg, void* memory);
    void* userArg;
};

struct DenoiserDescM
{
    uint32_t identifier;
    uint32_t denoiser;
};

struct InstanceCreationDescM
{
    AllocationCallbacksM allocationCallbacks;
    const DenoiserDescM* denoisers;
    uint32_t denoisersNum;
};

struct SPIRVBindingOffsetsM
{
    uint32_t samplerOffset;
    uint32_t textureOffset;
    uint32_t constantBufferOffset;
    uint32_t storageTextureAndBufferOffset;
};

struct LibraryDescM
{
    SPIRVBindingOffsetsM spirvBindingOffsets;
    const uint32_t* supportedDenoisers;
    uint32_t supportedDenoisersNum;
    uint8_t versionMajor;
    uint8_t versionMinor;
    uint8_t versionBuild;
    uint8_t normalEncoding;
    uint8_t roughnessEncoding;
};

struct TextureDescM
{
    uint32_t format;
    uint16_t downsampleFactor;
};

struct ResourceDescM
{
    uint32_t descriptorType;
    uint32_t type;
    uint16_t indexInPool;
};

struct ResourceRangeDescM
{
    uint32_t descriptorType;
    uint32_t descriptorsNum;
};

struct DescriptorPoolDescM
{
    uint32_t perSetTexturesMaxNum;
    uint32_t perSetStorageTexturesMaxNum;
    uint32_t totalTexturesNum;
    uint32_t totalStorageTexturesNum;
    uint32_t setsMaxNum;
};

struct InstanceDescM
{
    uint32_t constantBufferAndSamplersSpaceIndex;
    uint32_t resourcesSpaceIndex;
    uint32_t constantBufferRegisterIndex;
    uint32_t samplersBaseRegisterIndex;
    uint32_t resourcesBaseRegisterIndex;
    uint32_t constantBufferMaxDataSize;
    const uint32_t* samplers;
    uint32_t samplersNum;
    const char* shaderEntryPoint;
    const void* pipelines;
    uint32_t pipelinesNum;
    const TextureDescM* permanentPool;
    uint32_t permanentPoolSize;
    const TextureDescM* transientPool;
    uint32_t transientPoolSize;
    DescriptorPoolDescM descriptorPoolDesc;
};

struct DispatchDescM
{
    const char* name;
    uint32_t identifier;
    const ResourceDescM* resources;
    uint32_t resourcesNum;
    const uint8_t* constantBufferData;
    uint32_t constantBufferDataSize;
    bool constantBufferDataMatchesPreviousDispatch;
    uint16_t pipelineIndex;
    uint16_t gridWidth;
    uint16_t gridHeight;
};

// ---- Settings mirrors (defaults per NRDSettings.h) ------------------------

struct CommonSettingsM
{
    float viewToClipMatrix[16] = {};
    float viewToClipMatrixPrev[16] = {};
    float worldToViewMatrix[16] = {};
    float worldToViewMatrixPrev[16] = {};
    float worldPrevToWorldMatrix[16] = {
        1.0f, 0.0f, 0.0f, 0.0f,
        0.0f, 1.0f, 0.0f, 0.0f,
        0.0f, 0.0f, 1.0f, 0.0f,
        0.0f, 0.0f, 0.0f, 1.0f
    };
    float motionVectorScale[3] = {1.0f, 1.0f, 0.0f};
    float cameraJitter[2] = {};
    float cameraJitterPrev[2] = {};
    uint16_t resourceSize[2] = {};
    uint16_t resourceSizePrev[2] = {};
    uint16_t rectSize[2] = {};
    uint16_t rectSizePrev[2] = {};
    float viewZScale = 1.0f;
    float timeDeltaBetweenFrames = 0.0f;
    float denoisingRange = 500000.0f;
    float disocclusionThreshold = 0.01f;
    float disocclusionThresholdAlternate = 0.05f;
    float cameraAttachedReflectionMaterialID = 999.0f;
    float strandMaterialID = 999.0f;
    float historyFixAlternatePixelStrideMaterialID = 999.0f;
    float strandThickness = 80e-6f;
    float splitScreen = 0.0f;
    uint16_t printfAt[2] = {9999, 9999};
    float debug = 0.0f;
    uint32_t rectOrigin[2] = {};
    uint32_t frameIndex = 0;
    uint8_t accumulationMode = 0; // AccumulationMode::CONTINUE
    bool isMotionVectorInWorldSpace = false;
    bool isHistoryConfidenceAvailable = false;
    bool isDisocclusionThresholdMixAvailable = false;
    bool enableValidation = false;
};

struct ReblurHitDistanceParametersM
{
    float A = 3.0f;
    float B = 0.1f;
    float C = 20.0f;
};

struct ReblurAntilagSettingsM
{
    float luminanceSigmaScale = 2.0f;
    float luminanceSensitivity = 3.0f;
};

struct ReblurResponsiveAccumulationSettingsM
{
    float roughnessThreshold = 0.0f;
    uint32_t minAccumulatedFrameNum = 3;
};

struct ReblurConvergenceSettingsM
{
    float s = 1.0f;
    float b = 0.2f;
    float p = 0.8f;
};

struct ReblurSettingsM
{
    ReblurHitDistanceParametersM hitDistanceParameters = {};
    ReblurAntilagSettingsM antilagSettings = {};
    ReblurResponsiveAccumulationSettingsM responsiveAccumulationSettings = {};
    ReblurConvergenceSettingsM convergenceSettings = {};
    uint32_t maxAccumulatedFrameNum = 30;
    uint32_t maxFastAccumulatedFrameNum = 6;
    uint32_t maxStabilizedFrameNum = 63; // REBLUR_MAX_HISTORY_FRAME_NUM
    uint32_t historyFixFrameNum = 3;
    uint32_t historyFixBasePixelStride = 14;
    uint32_t historyFixAlternatePixelStride = 14;
    float fastHistoryClampingSigmaScale = 2.0f;
    float diffusePrepassBlurRadius = 30.0f;
    float specularPrepassBlurRadius = 50.0f;
    float minHitDistanceWeight = 0.1f;
    float minBlurRadius = 1.0f;
    float maxBlurRadius = 30.0f;
    float lobeAngleFraction = 0.15f;
    float roughnessFraction = 0.15f;
    float planeDistanceSensitivity = 0.02f;
    float specularProbabilityThresholdsForMvModification[2] = {0.5f, 0.9f};
    float fireflySuppressorMinRelativeScale = 2.0f;
    float minMaterialForDiffuse = 4.0f;
    float minMaterialForSpecular = 4.0f;
    uint8_t checkerboardMode = 0;                  // CheckerboardMode::OFF
    uint8_t hitDistanceReconstructionMode = 0;     // OFF
    bool enableAntiFirefly = true;
    bool usePrepassOnlyForSpecularMotionEstimation = false;
    bool returnHistoryLengthInsteadOfOcclusion = false;
};

struct RelaxAntilagSettingsM
{
    float accelerationAmount = 0.3f;
    float spatialSigmaScale = 4.5f;
    float temporalSigmaScale = 0.5f;
    float resetAmount = 0.5f;
};

struct RelaxSettingsM
{
    RelaxAntilagSettingsM antilagSettings = {};
    uint32_t diffuseMaxAccumulatedFrameNum = 30;
    uint32_t specularMaxAccumulatedFrameNum = 30;
    uint32_t diffuseMaxFastAccumulatedFrameNum = 6;
    uint32_t specularMaxFastAccumulatedFrameNum = 6;
    uint32_t historyFixFrameNum = 3;
    uint32_t historyFixBasePixelStride = 14;
    uint32_t historyFixAlternatePixelStride = 14;
    float historyFixEdgeStoppingNormalPower = 8.0f;
    float fastHistoryClampingSigmaScale = 2.0f;
    float diffusePrepassBlurRadius = 30.0f;
    float specularPrepassBlurRadius = 50.0f;
    float minHitDistanceWeight = 0.1f;
    uint32_t spatialVarianceEstimationHistoryThreshold = 3;
    float diffusePhiLuminance = 2.0f;
    float specularPhiLuminance = 1.0f;
    float lobeAngleFraction = 0.5f;
    float roughnessFraction = 0.15f;
    float specularVarianceBoost = 0.0f;
    float specularLobeAngleSlack = 0.15f;
    uint32_t atrousIterationNum = 5;
    float diffuseMinLuminanceWeight = 0.0f;
    float specularMinLuminanceWeight = 0.0f;
    float depthThreshold = 0.003f;
    float confidenceDrivenRelaxationMultiplier = 0.0f;
    float confidenceDrivenLuminanceEdgeStoppingRelaxation = 0.0f;
    float confidenceDrivenNormalEdgeStoppingRelaxation = 0.0f;
    float luminanceEdgeStoppingRelaxation = 0.5f;
    float normalEdgeStoppingRelaxation = 0.3f;
    float roughnessEdgeStoppingRelaxation = 1.0f;
    uint8_t checkerboardMode = 0;              // OFF
    uint8_t hitDistanceReconstructionMode = 0; // OFF
    float minMaterialForDiffuse = 4.0f;
    float minMaterialForSpecular = 4.0f;
    bool enableAntiFirefly = false;
    bool enableRoughnessEdgeStopping = true;
};

struct SigmaSettingsM
{
    float lightDirection[3] = {0.0f, 0.0f, 0.0f};
    float planeDistanceSensitivity = 0.02f;
    uint32_t maxStabilizedFrameNum = 5;
};

struct ReferenceSettingsM
{
    uint32_t maxAccumulatedFrameNum = 120;
};

// ---- Layout tables (single source of field offsets/sizes for nrd.xi) ------

// Field index order is documented in SPEC.md ("settings layout tables") and
// rendered here via offsetof/sizeof on the mirrors above.

#define NRDB_FIELD(structType, structPtr, member)                    \
    (uint32_t)offsetof(structType, member),                          \
        (uint32_t)sizeof(((structType*)0)->member)

static const uint32_t kCommonOffsets[] = {
    NRDB_FIELD(CommonSettingsM, x, viewToClipMatrix),
    NRDB_FIELD(CommonSettingsM, x, viewToClipMatrixPrev),
    NRDB_FIELD(CommonSettingsM, x, worldToViewMatrix),
    NRDB_FIELD(CommonSettingsM, x, worldToViewMatrixPrev),
    NRDB_FIELD(CommonSettingsM, x, worldPrevToWorldMatrix),
    NRDB_FIELD(CommonSettingsM, x, motionVectorScale),
    NRDB_FIELD(CommonSettingsM, x, cameraJitter),
    NRDB_FIELD(CommonSettingsM, x, cameraJitterPrev),
    NRDB_FIELD(CommonSettingsM, x, resourceSize),
    NRDB_FIELD(CommonSettingsM, x, resourceSizePrev),
    NRDB_FIELD(CommonSettingsM, x, rectSize),
    NRDB_FIELD(CommonSettingsM, x, rectSizePrev),
    NRDB_FIELD(CommonSettingsM, x, viewZScale),
    NRDB_FIELD(CommonSettingsM, x, timeDeltaBetweenFrames),
    NRDB_FIELD(CommonSettingsM, x, denoisingRange),
    NRDB_FIELD(CommonSettingsM, x, disocclusionThreshold),
    NRDB_FIELD(CommonSettingsM, x, disocclusionThresholdAlternate),
    NRDB_FIELD(CommonSettingsM, x, cameraAttachedReflectionMaterialID),
    NRDB_FIELD(CommonSettingsM, x, strandMaterialID),
    NRDB_FIELD(CommonSettingsM, x, historyFixAlternatePixelStrideMaterialID),
    NRDB_FIELD(CommonSettingsM, x, strandThickness),
    NRDB_FIELD(CommonSettingsM, x, splitScreen),
    NRDB_FIELD(CommonSettingsM, x, printfAt),
    NRDB_FIELD(CommonSettingsM, x, debug),
    NRDB_FIELD(CommonSettingsM, x, rectOrigin),
    NRDB_FIELD(CommonSettingsM, x, frameIndex),
    NRDB_FIELD(CommonSettingsM, x, accumulationMode),
    NRDB_FIELD(CommonSettingsM, x, isMotionVectorInWorldSpace),
    NRDB_FIELD(CommonSettingsM, x, isHistoryConfidenceAvailable),
    NRDB_FIELD(CommonSettingsM, x, isDisocclusionThresholdMixAvailable),
    NRDB_FIELD(CommonSettingsM, x, enableValidation),
};
#undef NRDB_FIELD

#define NRDB_FIELD(structType, member)          \
    (uint32_t)offsetof(structType, member),     \
        (uint32_t)sizeof(((structType*)0)->member)

static const uint32_t kReblurOffsets[] = {
    NRDB_FIELD(ReblurSettingsM, hitDistanceParameters),
    NRDB_FIELD(ReblurSettingsM, antilagSettings),
    NRDB_FIELD(ReblurSettingsM, responsiveAccumulationSettings),
    NRDB_FIELD(ReblurSettingsM, convergenceSettings),
    NRDB_FIELD(ReblurSettingsM, maxAccumulatedFrameNum),
    NRDB_FIELD(ReblurSettingsM, maxFastAccumulatedFrameNum),
    NRDB_FIELD(ReblurSettingsM, maxStabilizedFrameNum),
    NRDB_FIELD(ReblurSettingsM, historyFixFrameNum),
    NRDB_FIELD(ReblurSettingsM, historyFixBasePixelStride),
    NRDB_FIELD(ReblurSettingsM, historyFixAlternatePixelStride),
    NRDB_FIELD(ReblurSettingsM, fastHistoryClampingSigmaScale),
    NRDB_FIELD(ReblurSettingsM, diffusePrepassBlurRadius),
    NRDB_FIELD(ReblurSettingsM, specularPrepassBlurRadius),
    NRDB_FIELD(ReblurSettingsM, minHitDistanceWeight),
    NRDB_FIELD(ReblurSettingsM, minBlurRadius),
    NRDB_FIELD(ReblurSettingsM, maxBlurRadius),
    NRDB_FIELD(ReblurSettingsM, lobeAngleFraction),
    NRDB_FIELD(ReblurSettingsM, roughnessFraction),
    NRDB_FIELD(ReblurSettingsM, planeDistanceSensitivity),
    NRDB_FIELD(ReblurSettingsM, specularProbabilityThresholdsForMvModification),
    NRDB_FIELD(ReblurSettingsM, fireflySuppressorMinRelativeScale),
    NRDB_FIELD(ReblurSettingsM, minMaterialForDiffuse),
    NRDB_FIELD(ReblurSettingsM, minMaterialForSpecular),
    NRDB_FIELD(ReblurSettingsM, checkerboardMode),
    NRDB_FIELD(ReblurSettingsM, hitDistanceReconstructionMode),
    NRDB_FIELD(ReblurSettingsM, enableAntiFirefly),
    NRDB_FIELD(ReblurSettingsM, usePrepassOnlyForSpecularMotionEstimation),
    NRDB_FIELD(ReblurSettingsM, returnHistoryLengthInsteadOfOcclusion),
};

static const uint32_t kRelaxOffsets[] = {
    NRDB_FIELD(RelaxSettingsM, antilagSettings),
    NRDB_FIELD(RelaxSettingsM, diffuseMaxAccumulatedFrameNum),
    NRDB_FIELD(RelaxSettingsM, specularMaxAccumulatedFrameNum),
    NRDB_FIELD(RelaxSettingsM, diffuseMaxFastAccumulatedFrameNum),
    NRDB_FIELD(RelaxSettingsM, specularMaxFastAccumulatedFrameNum),
    NRDB_FIELD(RelaxSettingsM, historyFixFrameNum),
    NRDB_FIELD(RelaxSettingsM, historyFixBasePixelStride),
    NRDB_FIELD(RelaxSettingsM, historyFixAlternatePixelStride),
    NRDB_FIELD(RelaxSettingsM, historyFixEdgeStoppingNormalPower),
    NRDB_FIELD(RelaxSettingsM, fastHistoryClampingSigmaScale),
    NRDB_FIELD(RelaxSettingsM, diffusePrepassBlurRadius),
    NRDB_FIELD(RelaxSettingsM, specularPrepassBlurRadius),
    NRDB_FIELD(RelaxSettingsM, minHitDistanceWeight),
    NRDB_FIELD(RelaxSettingsM, spatialVarianceEstimationHistoryThreshold),
    NRDB_FIELD(RelaxSettingsM, diffusePhiLuminance),
    NRDB_FIELD(RelaxSettingsM, specularPhiLuminance),
    NRDB_FIELD(RelaxSettingsM, lobeAngleFraction),
    NRDB_FIELD(RelaxSettingsM, roughnessFraction),
    NRDB_FIELD(RelaxSettingsM, specularVarianceBoost),
    NRDB_FIELD(RelaxSettingsM, specularLobeAngleSlack),
    NRDB_FIELD(RelaxSettingsM, atrousIterationNum),
    NRDB_FIELD(RelaxSettingsM, diffuseMinLuminanceWeight),
    NRDB_FIELD(RelaxSettingsM, specularMinLuminanceWeight),
    NRDB_FIELD(RelaxSettingsM, depthThreshold),
    NRDB_FIELD(RelaxSettingsM, confidenceDrivenRelaxationMultiplier),
    NRDB_FIELD(RelaxSettingsM, confidenceDrivenLuminanceEdgeStoppingRelaxation),
    NRDB_FIELD(RelaxSettingsM, confidenceDrivenNormalEdgeStoppingRelaxation),
    NRDB_FIELD(RelaxSettingsM, luminanceEdgeStoppingRelaxation),
    NRDB_FIELD(RelaxSettingsM, normalEdgeStoppingRelaxation),
    NRDB_FIELD(RelaxSettingsM, roughnessEdgeStoppingRelaxation),
    NRDB_FIELD(RelaxSettingsM, checkerboardMode),
    NRDB_FIELD(RelaxSettingsM, hitDistanceReconstructionMode),
    NRDB_FIELD(RelaxSettingsM, minMaterialForDiffuse),
    NRDB_FIELD(RelaxSettingsM, minMaterialForSpecular),
    NRDB_FIELD(RelaxSettingsM, enableAntiFirefly),
    NRDB_FIELD(RelaxSettingsM, enableRoughnessEdgeStopping),
};

static const uint32_t kSigmaOffsets[] = {
    NRDB_FIELD(SigmaSettingsM, lightDirection),
    NRDB_FIELD(SigmaSettingsM, planeDistanceSensitivity),
    NRDB_FIELD(SigmaSettingsM, maxStabilizedFrameNum),
};

static const uint32_t kReferenceOffsets[] = {
    NRDB_FIELD(ReferenceSettingsM, maxAccumulatedFrameNum),
};
#undef NRDB_FIELD

} // namespace nrdm

// ===========================================================================
// Runtime function pointers
// ===========================================================================

typedef uint32_t(__stdcall* PFN_CreateInstance)(const nrdm::InstanceCreationDescM*, void**);
typedef void(__stdcall* PFN_DestroyInstance)(void*);
typedef const nrdm::LibraryDescM*(__stdcall* PFN_GetLibraryDesc)();
typedef const nrdm::InstanceDescM*(__stdcall* PFN_GetInstanceDesc)(const void*);
typedef uint32_t(__stdcall* PFN_SetCommonSettings)(void*, const nrdm::CommonSettingsM*);
typedef uint32_t(__stdcall* PFN_SetDenoiserSettings)(void*, uint32_t, const void*);
typedef uint32_t(__stdcall* PFN_GetComputeDispatches)(void*, const uint32_t*, uint32_t, const nrdm::DispatchDescM**, uint32_t*);
typedef const char*(__stdcall* PFN_GetNameString)(uint32_t);

static HMODULE g_module = 0;
static int32_t g_load_kind = NRDB_LOAD_ABSENT;
static PFN_CreateInstance g_createInstance = 0;
static PFN_DestroyInstance g_destroyInstance = 0;
static PFN_GetLibraryDesc g_getLibraryDesc = 0;
static PFN_GetInstanceDesc g_getInstanceDesc = 0;
static PFN_SetCommonSettings g_setCommonSettings = 0;
static PFN_SetDenoiserSettings g_setDenoiserSettings = 0;
static PFN_GetComputeDispatches g_getComputeDispatches = 0;
static PFN_GetNameString g_getResourceTypeString = 0;
static PFN_GetNameString g_getDenoiserString = 0;

// ===========================================================================
// Aligned allocation callbacks handed to the runtime
// ===========================================================================

struct AlignedHeaderM
{
    void* raw;
    size_t size;
};

static void* __stdcall nrdb_aligned_alloc(void* /*userArg*/, size_t size, size_t alignment)
{
    uintptr_t aligned;
    void* raw;
    AlignedHeaderM header;

    if (alignment < sizeof(void*)) alignment = sizeof(void*);
    raw = malloc(size + alignment - 1 + sizeof(AlignedHeaderM));
    if (raw == 0) return 0;

    aligned = ((uintptr_t)raw + sizeof(AlignedHeaderM) + (alignment - 1)) & ~(uintptr_t)(alignment - 1);
    header.raw = raw;
    header.size = size;
    memcpy((void*)(aligned - sizeof(AlignedHeaderM)), &header, sizeof(header));
    return (void*)aligned;
}

static void* __stdcall nrdb_aligned_realloc(void* userArg, void* memory, size_t size, size_t alignment)
{
    AlignedHeaderM header;
    void* fresh;

    if (memory == 0) return nrdb_aligned_alloc(userArg, size, alignment);

    memcpy(&header, (void*)((uintptr_t)memory - sizeof(AlignedHeaderM)), sizeof(header));
    fresh = nrdb_aligned_alloc(userArg, size, alignment);
    if (fresh == 0) return 0;

    memcpy(fresh, memory, header.size < size ? header.size : size);
    free(header.raw);
    return fresh;
}

static void __stdcall nrdb_aligned_free(void* /*userArg*/, void* memory)
{
    AlignedHeaderM header;

    if (memory == 0) return;
    memcpy(&header, (void*)((uintptr_t)memory - sizeof(AlignedHeaderM)), sizeof(header));
    free(header.raw);
}

// ===========================================================================
// Small helpers
// ===========================================================================

static void nrdb_wr_u32(uint8_t* dst, uint32_t v)
{
    dst[0] = (uint8_t)(v & 0xFF);
    dst[1] = (uint8_t)((v >> 8) & 0xFF);
    dst[2] = (uint8_t)((v >> 16) & 0xFF);
    dst[3] = (uint8_t)((v >> 24) & 0xFF);
}

static uint32_t nrdb_rd_u32(const uint8_t* src)
{
    return (uint32_t)src[0] | ((uint32_t)src[1] << 8) | ((uint32_t)src[2] << 16) | ((uint32_t)src[3] << 24);
}

static int32_t nrdb_copy_string(const char* src, uint8_t* dst, int32_t cap)
{
    int32_t len = 0;

    if (src == 0) return -1;
    if (dst == 0 || cap <= 0) return NRDB_ERR_BAD_ARGS;

    while (src[len] != 0 && len < cap - 1) len++;
    memcpy(dst, src, (size_t)len);
    dst[len] = 0;
    return len;
}

static void nrdb_reset_state()
{
    g_module = 0;
    g_load_kind = NRDB_LOAD_ABSENT;
    g_createInstance = 0;
    g_destroyInstance = 0;
    g_getLibraryDesc = 0;
    g_getInstanceDesc = 0;
    g_setCommonSettings = 0;
    g_setDenoiserSettings = 0;
    g_getComputeDispatches = 0;
    g_getResourceTypeString = 0;
    g_getDenoiserString = 0;
}

static int64_t nrdb_finish_load(HMODULE module)
{
    g_createInstance = (PFN_CreateInstance)(void*)GetProcAddress(module, "CreateInstance");
    g_destroyInstance = (PFN_DestroyInstance)(void*)GetProcAddress(module, "DestroyInstance");
    g_getLibraryDesc = (PFN_GetLibraryDesc)(void*)GetProcAddress(module, "GetLibraryDesc");
    g_getInstanceDesc = (PFN_GetInstanceDesc)(void*)GetProcAddress(module, "GetInstanceDesc");
    g_setCommonSettings = (PFN_SetCommonSettings)(void*)GetProcAddress(module, "SetCommonSettings");
    g_setDenoiserSettings = (PFN_SetDenoiserSettings)(void*)GetProcAddress(module, "SetDenoiserSettings");
    g_getComputeDispatches = (PFN_GetComputeDispatches)(void*)GetProcAddress(module, "GetComputeDispatches");
    g_getResourceTypeString = (PFN_GetNameString)(void*)GetProcAddress(module, "GetResourceTypeString");
    g_getDenoiserString = (PFN_GetNameString)(void*)GetProcAddress(module, "GetDenoiserString");

    if (!g_createInstance || !g_destroyInstance || !g_getLibraryDesc || !g_getInstanceDesc ||
        !g_setCommonSettings || !g_setDenoiserSettings || !g_getComputeDispatches ||
        !g_getResourceTypeString || !g_getDenoiserString)
    {
        FreeLibrary(module);
        nrdb_reset_state();
        g_load_kind = NRDB_LOAD_ABI;
        return 0;
    }

    g_module = module;
    g_load_kind = NRDB_LOAD_OK;
    return (int64_t)(intptr_t)module;
}

// ===========================================================================
// extern "C" surface
// ===========================================================================

extern "C" {

// ---- Loader ---------------------------------------------------------------

int64_t nrdb_try_load(const uint8_t* path, int32_t len)
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
        g_load_kind = NRDB_LOAD_ABSENT;
        return 0;
    }
    return nrdb_finish_load(module);
}

int64_t nrdb_try_load_auto()
{
    char buffer[1024 + 1];
    DWORD n;
    HMODULE module;

    if (g_module != 0) return (int64_t)(intptr_t)g_module;

    n = GetEnvironmentVariableA("XIOM_NRD_DLL", buffer, 1024);
    if (n > 0 && n < 1024)
    {
        module = LoadLibraryA(buffer);
        if (module != 0) return nrdb_finish_load(module);
    }

    module = LoadLibraryA("NRD.dll");
    if (module == 0)
    {
        g_load_kind = NRDB_LOAD_ABSENT;
        return 0;
    }
    return nrdb_finish_load(module);
}

int32_t nrdb_load_kind()
{
    return g_load_kind;
}

int32_t nrdb_close(int64_t handle)
{
    HMODULE module;

    if (handle == 0) return 0;
    if (g_module != (HMODULE)(intptr_t)handle) return NRDB_ERR_BAD_ARGS;
    module = g_module;
    nrdb_reset_state();
    FreeLibrary(module);
    return 0;
}

// ---- Library / instance description ---------------------------------------

int32_t nrdb_library_info(int64_t handle, uint8_t* out, int32_t cap)
{
    const nrdm::LibraryDescM* desc;

    if (handle == 0 || out == 0 || cap < 48) return NRDB_ERR_BAD_ARGS;
    if (g_module == 0 || (HMODULE)(intptr_t)handle != g_module) return NRDB_ERR_NOT_LOADED;

    desc = g_getLibraryDesc();
    if (desc == 0) return NRDB_ERR_BAD_ARGS;

    nrdb_wr_u32(out + 0, desc->versionMajor);
    nrdb_wr_u32(out + 4, desc->versionMinor);
    nrdb_wr_u32(out + 8, desc->versionBuild);
    nrdb_wr_u32(out + 12, desc->normalEncoding);
    nrdb_wr_u32(out + 16, desc->roughnessEncoding);
    nrdb_wr_u32(out + 20, desc->supportedDenoisersNum);
    nrdb_wr_u32(out + 24, desc->spirvBindingOffsets.samplerOffset);
    nrdb_wr_u32(out + 28, desc->spirvBindingOffsets.textureOffset);
    nrdb_wr_u32(out + 32, desc->spirvBindingOffsets.constantBufferOffset);
    nrdb_wr_u32(out + 36, desc->spirvBindingOffsets.storageTextureAndBufferOffset);
    nrdb_wr_u32(out + 40, 0);
    nrdb_wr_u32(out + 44, 0);
    return 0;
}

int32_t nrdb_library_denoiser(int64_t handle, int32_t index)
{
    const nrdm::LibraryDescM* desc;

    if (handle == 0 || index < 0) return -1;
    if (g_module == 0 || (HMODULE)(intptr_t)handle != g_module) return -1;

    desc = g_getLibraryDesc();
    if (desc == 0 || desc->supportedDenoisers == 0) return -1;
    if ((uint32_t)index >= desc->supportedDenoisersNum) return -1;
    return (int32_t)desc->supportedDenoisers[index];
}

// ---- Instance lifecycle ----------------------------------------------------

int32_t nrdb_instance_create(int64_t handle, const uint8_t* ids, const uint8_t* kinds, int32_t count, uint8_t* out_inst)
{
    nrdm::DenoiserDescM denoisers[NRDB_MAX_DENOISERS];
    nrdm::InstanceCreationDescM desc;
    void* instance = 0;
    uint32_t result;
    int32_t i;

    if (handle == 0 || ids == 0 || kinds == 0 || out_inst == 0) return NRDB_ERR_BAD_ARGS;
    if (count <= 0 || count > NRDB_MAX_DENOISERS) return NRDB_ERR_BAD_ARGS;
    if (g_module == 0 || (HMODULE)(intptr_t)handle != g_module) return NRDB_ERR_NOT_LOADED;

    for (i = 0; i < count; i++)
    {
        denoisers[i].identifier = nrdb_rd_u32(ids + (size_t)i * 4);
        denoisers[i].denoiser = nrdb_rd_u32(kinds + (size_t)i * 4);
    }

    desc.allocationCallbacks.Allocate = nrdb_aligned_alloc;
    desc.allocationCallbacks.Reallocate = nrdb_aligned_realloc;
    desc.allocationCallbacks.Free = nrdb_aligned_free;
    desc.allocationCallbacks.userArg = 0;
    desc.denoisers = denoisers;
    desc.denoisersNum = (uint32_t)count;

    result = g_createInstance(&desc, &instance);
    if (result == 0)
    {
        uint64_t p = (uint64_t)(uintptr_t)instance;
        for (i = 0; i < 8; i++) out_inst[i] = (uint8_t)((p >> (8 * i)) & 0xFF);
    }
    else
    {
        for (i = 0; i < 8; i++) out_inst[i] = 0;
    }
    return (int32_t)result;
}

int32_t nrdb_instance_destroy(int64_t handle, int64_t instance)
{
    if (handle == 0) return NRDB_ERR_BAD_ARGS;
    if (g_module == 0 || (HMODULE)(intptr_t)handle != g_module) return NRDB_ERR_NOT_LOADED;
    if (instance != 0) g_destroyInstance((void*)(intptr_t)instance);
    return 0;
}

int32_t nrdb_instance_info(int64_t handle, int64_t instance, uint8_t* out, int32_t cap)
{
    const nrdm::InstanceDescM* desc;

    if (handle == 0 || instance == 0 || out == 0 || cap < 64) return NRDB_ERR_BAD_ARGS;
    if (g_module == 0 || (HMODULE)(intptr_t)handle != g_module) return NRDB_ERR_NOT_LOADED;

    desc = g_getInstanceDesc((const void*)(intptr_t)instance);
    if (desc == 0) return NRDB_ERR_BAD_ARGS;

    nrdb_wr_u32(out + 0, desc->constantBufferAndSamplersSpaceIndex);
    nrdb_wr_u32(out + 4, desc->resourcesSpaceIndex);
    nrdb_wr_u32(out + 8, desc->constantBufferRegisterIndex);
    nrdb_wr_u32(out + 12, desc->samplersBaseRegisterIndex);
    nrdb_wr_u32(out + 16, desc->resourcesBaseRegisterIndex);
    nrdb_wr_u32(out + 20, desc->constantBufferMaxDataSize);
    nrdb_wr_u32(out + 24, desc->samplersNum);
    nrdb_wr_u32(out + 28, desc->pipelinesNum);
    nrdb_wr_u32(out + 32, desc->permanentPoolSize);
    nrdb_wr_u32(out + 36, desc->transientPoolSize);
    nrdb_wr_u32(out + 40, desc->descriptorPoolDesc.perSetTexturesMaxNum);
    nrdb_wr_u32(out + 44, desc->descriptorPoolDesc.perSetStorageTexturesMaxNum);
    nrdb_wr_u32(out + 48, desc->descriptorPoolDesc.totalTexturesNum);
    nrdb_wr_u32(out + 52, desc->descriptorPoolDesc.totalStorageTexturesNum);
    nrdb_wr_u32(out + 56, desc->descriptorPoolDesc.setsMaxNum);
    nrdb_wr_u32(out + 60, 0);
    return 0;
}

int32_t nrdb_instance_shader_entry(int64_t handle, int64_t instance, uint8_t* dst, int32_t cap)
{
    const nrdm::InstanceDescM* desc;

    if (handle == 0 || instance == 0 || dst == 0 || cap <= 0) return NRDB_ERR_BAD_ARGS;
    if (g_module == 0 || (HMODULE)(intptr_t)handle != g_module) return NRDB_ERR_NOT_LOADED;

    desc = g_getInstanceDesc((const void*)(intptr_t)instance);
    if (desc == 0 || desc->shaderEntryPoint == 0) return -1;
    return nrdb_copy_string(desc->shaderEntryPoint, dst, cap);
}

// ---- Settings ---------------------------------------------------------------

int32_t nrdb_set_common_settings(int64_t handle, int64_t instance, const uint8_t* settings, int32_t size)
{
    if (handle == 0 || instance == 0 || settings == 0) return NRDB_ERR_BAD_ARGS;
    if (size < (int32_t)sizeof(nrdm::CommonSettingsM)) return NRDB_ERR_SIZE;
    if (g_module == 0 || (HMODULE)(intptr_t)handle != g_module) return NRDB_ERR_NOT_LOADED;

    return (int32_t)g_setCommonSettings((void*)(intptr_t)instance, (const nrdm::CommonSettingsM*)settings);
}

int32_t nrdb_set_denoiser_settings(int64_t handle, int64_t instance, int32_t identifier, const uint8_t* settings, int32_t size)
{
    if (handle == 0 || instance == 0 || settings == 0) return NRDB_ERR_BAD_ARGS;
    if (size < 16) return NRDB_ERR_SIZE; // the module always passes full images
    if (g_module == 0 || (HMODULE)(intptr_t)handle != g_module) return NRDB_ERR_NOT_LOADED;

    return (int32_t)g_setDenoiserSettings((void*)(intptr_t)instance, (uint32_t)identifier, settings);
}

// ---- Dispatch plan ----------------------------------------------------------

static int32_t nrdb_plan_scan(int64_t handle, int64_t instance, const uint8_t* ids, int32_t ids_num,
                              const nrdm::DispatchDescM** descs, uint32_t* descs_num)
{
    uint32_t i;
    uint32_t descriptors[NRDB_MAX_DENOISERS];

    if (ids_num <= 0 || ids_num > NRDB_MAX_DENOISERS) return NRDB_ERR_BAD_ARGS;
    for (i = 0; i < (uint32_t)ids_num; i++) descriptors[i] = nrdb_rd_u32(ids + (size_t)i * 4);

    return (int32_t)g_getComputeDispatches((void*)(intptr_t)instance, descriptors, (uint32_t)ids_num, descs, descs_num);
}

int32_t nrdb_plan_counts(int64_t handle, int64_t instance, const uint8_t* ids, int32_t ids_num, uint8_t* out)
{
    const nrdm::DispatchDescM* descs = 0;
    uint32_t count = 0;
    uint32_t res_total = 0;
    uint32_t cb_total = 0;
    uint32_t max_res = 0;
    uint32_t i;
    int32_t rc;

    if (handle == 0 || instance == 0 || ids == 0 || out == 0) return NRDB_ERR_BAD_ARGS;
    if (g_module == 0 || (HMODULE)(intptr_t)handle != g_module) return NRDB_ERR_NOT_LOADED;

    rc = nrdb_plan_scan(handle, instance, ids, ids_num, &descs, &count);
    if (rc != 0) return rc;

    for (i = 0; i < count; i++)
    {
        res_total += descs[i].resourcesNum;
        cb_total += descs[i].constantBufferDataSize;
        if (descs[i].resourcesNum > max_res) max_res = descs[i].resourcesNum;
    }

    nrdb_wr_u32(out + 0, count);
    nrdb_wr_u32(out + 4, res_total);
    nrdb_wr_u32(out + 8, cb_total);
    nrdb_wr_u32(out + 12, max_res);
    return 0;
}

int32_t nrdb_plan_copy(int64_t handle, int64_t instance, const uint8_t* ids, int32_t ids_num,
                       uint8_t* summaries, int32_t summaries_cap,
                       uint8_t* resources, int32_t resources_cap,
                       uint8_t* constants, int32_t constants_cap,
                       uint8_t* out)
{
    const nrdm::DispatchDescM* descs = 0;
    uint32_t count = 0;
    uint32_t res_total = 0;
    uint32_t cb_total = 0;
    uint32_t max_res = 0;
    uint32_t res_cursor = 0;
    uint32_t cb_cursor = 0;
    uint32_t i;
    uint32_t j;
    int32_t rc;

    if (handle == 0 || instance == 0 || ids == 0 || summaries == 0 || resources == 0 || constants == 0 || out == 0)
        return NRDB_ERR_BAD_ARGS;
    if (g_module == 0 || (HMODULE)(intptr_t)handle != g_module) return NRDB_ERR_NOT_LOADED;

    rc = nrdb_plan_scan(handle, instance, ids, ids_num, &descs, &count);
    if (rc != 0) return rc;

    for (i = 0; i < count; i++)
    {
        res_total += descs[i].resourcesNum;
        cb_total += descs[i].constantBufferDataSize;
        if (descs[i].resourcesNum > max_res) max_res = descs[i].resourcesNum;
    }

    nrdb_wr_u32(out + 0, count);
    nrdb_wr_u32(out + 4, res_total);
    nrdb_wr_u32(out + 8, cb_total);
    nrdb_wr_u32(out + 12, max_res);

    if ((int32_t)count > summaries_cap || (int32_t)res_total > resources_cap || (int32_t)cb_total > constants_cap)
        return NRDB_ERR_CAPACITY;

    for (i = 0; i < count; i++)
    {
        const nrdm::DispatchDescM& d = descs[i];
        uint8_t* rec = summaries + (size_t)i * NRDB_SUMMARY_SIZE;
        int32_t name_len = 0;

        memset(rec, 0, NRDB_SUMMARY_SIZE);
        nrdb_wr_u32(rec + 0, d.identifier);
        nrdb_wr_u32(rec + 4, d.pipelineIndex);
        nrdb_wr_u32(rec + 8, d.gridWidth);
        nrdb_wr_u32(rec + 12, d.gridHeight);
        nrdb_wr_u32(rec + 16, d.resourcesNum);
        nrdb_wr_u32(rec + 20, d.constantBufferDataSize);
        nrdb_wr_u32(rec + 24, cb_cursor);
        nrdb_wr_u32(rec + 28, res_cursor);
        nrdb_wr_u32(rec + 32, d.constantBufferDataMatchesPreviousDispatch ? 1 : 0);

        // Layout consumed by nrd.xi (NRDB_SUMMARY_SIZE = 96):
        //   +0  identifier        +20 cbSize
        //   +4  pipelineIndex     +24 cbOffset
        //   +8  gridWidth         +28 resOffset
        //   +12 gridHeight        +32 flags (bit0 = matchesPrevious)
        //   +16 resourcesNum      +36 nameLen   +40..96 name bytes (56 max)
        if (d.name != 0) name_len = nrdb_copy_string(d.name, rec + 40, 56);
        if (name_len < 0) name_len = 0;
        nrdb_wr_u32(rec + 36, (uint32_t)name_len);

        for (j = 0; j < d.resourcesNum; j++)
        {
            uint8_t* rr = resources + (size_t)(res_cursor + j) * NRDB_RES_REC_SIZE;
            nrdb_wr_u32(rr + 0, d.resources[j].descriptorType);
            nrdb_wr_u32(rr + 4, d.resources[j].type);
            nrdb_wr_u32(rr + 8, d.resources[j].indexInPool);
            nrdb_wr_u32(rr + 12, 0);
        }
        res_cursor += d.resourcesNum;

        if (d.constantBufferDataSize > 0 && d.constantBufferData != 0)
        {
            memcpy(constants + cb_cursor, d.constantBufferData, d.constantBufferDataSize);
            cb_cursor += d.constantBufferDataSize;
        }
    }

    return 0;
}

int32_t nrdb_plan_dispatch_name(const uint8_t* summaries, int32_t cap_records, int32_t index, uint8_t* dst, int32_t dst_cap)
{
    const uint8_t* rec;
    uint32_t name_len;

    if (summaries == 0 || dst == 0 || dst_cap <= 0 || index < 0 || index >= cap_records) return NRDB_ERR_BAD_ARGS;
    rec = summaries + (size_t)index * NRDB_SUMMARY_SIZE;
    name_len = nrdb_rd_u32(rec + 36);
    if (name_len >= 56) name_len = 55;
    if (name_len >= (uint32_t)dst_cap) name_len = (uint32_t)dst_cap - 1;
    memcpy(dst, rec + 40, name_len);
    dst[name_len] = 0;
    return (int32_t)name_len;
}

// ---- Name tables ------------------------------------------------------------

int32_t nrdb_get_resource_string(int64_t handle, int32_t type, uint8_t* dst, int32_t cap)
{
    if (handle == 0 || dst == 0 || cap <= 0) return NRDB_ERR_BAD_ARGS;
    if (g_module == 0 || (HMODULE)(intptr_t)handle != g_module) return NRDB_ERR_NOT_LOADED;
    return nrdb_copy_string(g_getResourceTypeString((uint32_t)type), dst, cap);
}

int32_t nrdb_get_denoiser_string(int64_t handle, int32_t denoiser, uint8_t* dst, int32_t cap)
{
    if (handle == 0 || dst == 0 || cap <= 0) return NRDB_ERR_BAD_ARGS;
    if (g_module == 0 || (HMODULE)(intptr_t)handle != g_module) return NRDB_ERR_NOT_LOADED;
    return nrdb_copy_string(g_getDenoiserString((uint32_t)denoiser), dst, cap);
}

// ---- Layout tables / defaults -------------------------------------------------

int32_t nrdb_layout(int32_t kind, uint8_t* offsets, uint8_t* sizes, int32_t cap)
{
    const uint32_t* table = 0;
    uint32_t count = 0;
    uint32_t i;

    // tables store offset/size pairs; entries = pair count
    switch (kind)
    {
    case 0: table = nrdm::kCommonOffsets; count = (uint32_t)(sizeof(nrdm::kCommonOffsets) / sizeof(uint32_t)) / 2; break;
    case 1: table = nrdm::kReblurOffsets; count = (uint32_t)(sizeof(nrdm::kReblurOffsets) / sizeof(uint32_t)) / 2; break;
    case 2: table = nrdm::kRelaxOffsets; count = (uint32_t)(sizeof(nrdm::kRelaxOffsets) / sizeof(uint32_t)) / 2; break;
    case 3: table = nrdm::kSigmaOffsets; count = (uint32_t)(sizeof(nrdm::kSigmaOffsets) / sizeof(uint32_t)) / 2; break;
    case 4: table = nrdm::kReferenceOffsets; count = (uint32_t)(sizeof(nrdm::kReferenceOffsets) / sizeof(uint32_t)) / 2; break;
    default: return NRDB_ERR_BAD_ARGS;
    }

    if (offsets == 0 || sizes == 0) return (int32_t)count; // count probe
    if ((int32_t)count > cap) return NRDB_ERR_CAPACITY;

    for (i = 0; i < count; i++)
    {
        nrdb_wr_u32(offsets + (size_t)i * 4, table[i * 2 + 0]);
        nrdb_wr_u32(sizes + (size_t)i * 4, table[i * 2 + 1]);
    }
    return (int32_t)count;
}

int32_t nrdb_layout_size(int32_t kind)
{
    switch (kind)
    {
    case 0: return (int32_t)sizeof(nrdm::CommonSettingsM);
    case 1: return (int32_t)sizeof(nrdm::ReblurSettingsM);
    case 2: return (int32_t)sizeof(nrdm::RelaxSettingsM);
    case 3: return (int32_t)sizeof(nrdm::SigmaSettingsM);
    case 4: return (int32_t)sizeof(nrdm::ReferenceSettingsM);
    default: return -1;
    }
}

int32_t nrdb_common_settings_default(uint8_t* dst, int32_t cap)
{
    nrdm::CommonSettingsM defaults{};

    if (dst == 0) return NRDB_ERR_BAD_ARGS;
    if (cap < (int32_t)sizeof(defaults)) return NRDB_ERR_SIZE;
    memcpy(dst, &defaults, sizeof(defaults));
    return 0;
}

int32_t nrdb_denoiser_settings_default(int32_t kind, uint8_t* dst, int32_t cap)
{
    if (dst == 0) return NRDB_ERR_BAD_ARGS;

    switch (kind)
    {
    case 1:
    {
        nrdm::ReblurSettingsM defaults{};
        if (cap < (int32_t)sizeof(defaults)) return NRDB_ERR_SIZE;
        memcpy(dst, &defaults, sizeof(defaults));
        return 0;
    }
    case 2:
    {
        nrdm::RelaxSettingsM defaults{};
        if (cap < (int32_t)sizeof(defaults)) return NRDB_ERR_SIZE;
        memcpy(dst, &defaults, sizeof(defaults));
        return 0;
    }
    case 3:
    {
        nrdm::SigmaSettingsM defaults{};
        if (cap < (int32_t)sizeof(defaults)) return NRDB_ERR_SIZE;
        memcpy(dst, &defaults, sizeof(defaults));
        return 0;
    }
    case 4:
    {
        nrdm::ReferenceSettingsM defaults{};
        if (cap < (int32_t)sizeof(defaults)) return NRDB_ERR_SIZE;
        memcpy(dst, &defaults, sizeof(defaults));
        return 0;
    }
    default:
        return NRDB_ERR_BAD_ARGS;
    }
}

// ---- Owned-image scalar accessors (XIOM-owned slots; B-17/B-24) ------------

int32_t nrdb_img_set_u32(uint8_t* dst, int32_t cap, int32_t off, int32_t v)
{
    if (dst == 0 || off < 0 || cap < off + 4) return NRDB_ERR_BAD_ARGS;
    nrdb_wr_u32(dst + off, (uint32_t)v);
    return 0;
}

int32_t nrdb_img_set_u16(uint8_t* dst, int32_t cap, int32_t off, int32_t v)
{
    if (dst == 0 || off < 0 || cap < off + 2) return NRDB_ERR_BAD_ARGS;
    dst[off + 0] = (uint8_t)(v & 0xFF);
    dst[off + 1] = (uint8_t)((v >> 8) & 0xFF);
    return 0;
}

int32_t nrdb_img_set_u8(uint8_t* dst, int32_t cap, int32_t off, int32_t v)
{
    if (dst == 0 || off < 0 || cap < off + 1) return NRDB_ERR_BAD_ARGS;
    dst[off] = (uint8_t)(v & 0xFF);
    return 0;
}

int32_t nrdb_img_set_f32(uint8_t* dst, int32_t cap, int32_t off, float v)
{
    if (dst == 0 || off < 0 || cap < off + 4) return NRDB_ERR_BAD_ARGS;
    memcpy(dst + off, &v, 4);
    return 0;
}

int32_t nrdb_img_get_u32(const uint8_t* src, int32_t cap, int32_t off)
{
    if (src == 0 || off < 0 || cap < off + 4) return -1;
    return (int32_t)nrdb_rd_u32(src + off);
}

int32_t nrdb_img_get_u16(const uint8_t* src, int32_t cap, int32_t off)
{
    if (src == 0 || off < 0 || cap < off + 2) return -1;
    return (int32_t)((uint32_t)src[off] | ((uint32_t)src[off + 1] << 8));
}

int32_t nrdb_img_get_u8(const uint8_t* src, int32_t cap, int32_t off)
{
    if (src == 0 || off < 0 || cap < off + 1) return -1;
    return (int32_t)src[off];
}

float nrdb_img_get_f32(const uint8_t* src, int32_t cap, int32_t off)
{
    float v = 0.0f;
    if (src == 0 || off < 0 || cap < off + 4) return 0.0f;
    memcpy(&v, src + off, 4);
    return v;
}

// ---- Execute (typed device requirement) -------------------------------------

int32_t nrdb_execute(int64_t handle, int64_t instance, const uint8_t* summaries, int32_t count)
{
    // No GPU device bridge ships in this wave (PROVENANCE.md / SPEC.md):
    // executing dispatches requires the application's D3D12/VK device,
    // pipeline creation from NRD shader blobs and resource binding.  The
    // CPU-side plan is validated by the caller; the device path is a typed
    // SKIP state (NRD_EXEC_NO_DEVICE = 2), never a silent success.
    if (handle == 0 || instance == 0 || summaries == 0 || count <= 0) return 1; // NRD_EXEC_INVALID
    return 2; // NRD_EXEC_NO_DEVICE
}

} // extern "C"
