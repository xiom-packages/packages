/* XIOM -- xiom.rtxdi: XIOM-side dynamic-loader bridge for the NVIDIA RTXDI
 * runtime CPU integration surface.
 * Copyright (c) 2026 Eleftherios Notas and The XIOM Authors.
 * SPDX-License-Identifier: MIT OR Apache-2.0
 *
 * This file is OUR code, not NVIDIA code.  It copies NOTHING from the RTXDI
 * library and links NOTHING from it at build time -- the RTXDI runtime never
 * ships in this repository (see PROVENANCE.md: the upstream is the
 * proprietary NVIDIA RTX SDKs License, reference-only policy, NRD/FFmpeg
 * precedent).  The bridge exists because the v0.64.4 FFI discipline
 * (findings B-20/B-21/B-23/B-24/B-25/B-26) cannot:
 *
 *   1. load a runtime shim module and resolve entry points -- done here with
 *      LoadLibraryA/GetProcAddress; module/context handles cross the C ABI as
 *      int64_t and are cast to pointers only inside the shim (B-25);
 *
 *   2. lay out the public RTXDI parameter structs for calls into the shim:
 *      the ABI mirror structs below are written from the public header
 *      declarations at the pinned revision (the "declaration oracle",
 *      PROVENANCE.md) -- Rtxdi/RtxdiParameters.h, Rtxdi/DI/ReSTIRDI.h,
 *      Rtxdi/DI/ReSTIRDIParameters.h, Rtxdi/LightSampling/
 *      RISBufferSegmentParameters.h, Rtxdi/ReGIR/ReGIRParameters.h @ the
 *      revision RTXDI v3.1.0 selects for Libraries/Rtxdi (f12037fa).  Layout
 *      facts only;
 *
 *   3. copy response data (parameter images, reservoir buffer parameters,
 *      calculated ReGIR onion layers/rings) out of shim-owned storage into
 *      XIOM-owned slots: this file does that copy; XIOM reads only its own
 *      slots, byte-indexed (B-20/B-24), one owned slot per out-param;
 *
 *   4. provide the layout tables that the owned images need (offsetof/sizeof
 *      of the mirrors; single source of ABI truth), plus scalar accessors so
 *      XIOM never pointer-arithmetics (B-20/B-24).
 *
 * The shim module is the licensee's own locally built DLL around the RTXDI
 * library source (see PROVENANCE.md "Local runtime sample"); it is
 * resolution-loaded at run time and never committed.  When it is absent the
 * suite classifies RTXDI_LOAD_ABSENT (SKIP, green).
 *
 * Bridge return codes (int32):
 *   0     = success (or count/size, per entry point)
 *   100   = RTXDIB_ERR_NOT_LOADED  (no shim module loaded)
 *   101   = RTXDIB_ERR_BAD_ARGS
 *   102   = RTXDIB_ERR_SIZE        (owned image smaller than the mirror)
 *   103   = RTXDIB_ERR_CAPACITY    (owned out slot too small)
 */

#include <windows.h>

#include <stdint.h>
#include <stddef.h>
#include <string.h>

// ===========================================================================
// Bridge status codes (kept in sync with rtxdi.xi pub consts)
// ===========================================================================

#define RTXDIB_ERR_NOT_LOADED 100
#define RTXDIB_ERR_BAD_ARGS 101
#define RTXDIB_ERR_SIZE 102
#define RTXDIB_ERR_CAPACITY 103

#define RTXDIB_LOAD_ABSENT 0
#define RTXDIB_LOAD_ABI 1
#define RTXDIB_LOAD_OK 2

// ===========================================================================
// ABI mirrors (declaration oracle @ f12037fa).  Every field of every bound
// RTXDI structure is a 4-byte scalar; the mirrors below reproduce the exact
// field order and (where present) padding of the headers.  The layout probe
// entries mirror the shim's field lists one-for-one.
// ===========================================================================

namespace rtxdim
{

struct RTXDI_ReservoirBufferParametersM
{
    uint32_t reservoirBlockRowPitch;
    uint32_t reservoirArrayPitch;
    uint32_t pad0;
    uint32_t pad1;
};

struct RTXDI_RuntimeParametersM
{
    uint32_t neighborOffsetMask;
    uint32_t activeCheckerboardField;
    uint32_t frameIndex;
    uint32_t pad0;
};

struct RTXDI_DIBufferIndicesM
{
    uint32_t initialSamplingOutputBufferIndex;
    uint32_t temporalResamplingInputBufferIndex;
    uint32_t temporalResamplingOutputBufferIndex;
    uint32_t spatialResamplingInputBufferIndex;
    uint32_t spatialResamplingOutputBufferIndex;
    uint32_t shadingInputBufferIndex;
    uint32_t pad1;
    uint32_t pad2;
};

struct RTXDI_DIInitialSamplingParametersM
{
    uint32_t numLocalLightSamples;
    uint32_t numInfiniteLightSamples;
    uint32_t numEnvironmentSamples;
    uint32_t numBrdfSamples;
    float brdfCutoff;
    float brdfRayMinT;
    uint32_t localLightSamplingMode;
    uint32_t enableInitialVisibility;
    uint32_t environmentMapImportanceSampling;
    uint32_t pad1;
    uint32_t pad2;
    uint32_t pad3;
};

struct RTXDI_DITemporalResamplingParametersM
{
    uint32_t maxHistoryLength;
    uint32_t biasCorrectionMode;
    float depthThreshold;
    float normalThreshold;
    uint32_t enableVisibilityShortcut;
    uint32_t enablePermutationSampling;
    uint32_t uniformRandomNumber;
    float permutationSamplingThreshold;
};

struct RTXDI_BoilingFilterParametersM
{
    uint32_t enableBoilingFilter;
    float boilingFilterStrength;
    uint32_t pad1;
    uint32_t pad2;
};

struct RTXDI_DISpatialResamplingParametersM
{
    uint32_t numSamples;
    uint32_t numDisocclusionBoostSamples;
    float samplingRadius;
    uint32_t biasCorrectionMode;
    float depthThreshold;
    float normalThreshold;
    uint32_t targetHistoryLength;
    uint32_t enableMaterialSimilarityTest;
    uint32_t discountNaiveSamples;
    uint32_t pad1;
    uint32_t pad2;
    uint32_t pad3;
};

struct RTXDI_DISpatioTemporalResamplingParametersM
{
    float depthThreshold;
    float normalThreshold;
    uint32_t biasCorrectionMode;
    uint32_t maxHistoryLength;
    uint32_t enablePermutationSampling;
    uint32_t uniformRandomNumber;
    uint32_t enableVisibilityShortcut;
    uint32_t numSamples;
    uint32_t numDisocclusionBoostSamples;
    float samplingRadius;
    uint32_t enableMaterialSimilarityTest;
    uint32_t discountNaiveSamples;
};

struct RTXDI_ShadingParametersM
{
    uint32_t enableFinalVisibility;
    uint32_t reuseFinalVisibility;
    uint32_t finalVisibilityMaxAge;
    float finalVisibilityMaxDistance;
    uint32_t enableDenoiserInputPacking;
    uint32_t pad1;
    uint32_t pad2;
    uint32_t pad3;
};

struct RTXDI_ParametersM
{
    RTXDI_ReservoirBufferParametersM reservoirBufferParams;
    RTXDI_DIBufferIndicesM bufferIndices;
    RTXDI_DIInitialSamplingParametersM initialSamplingParams;
    RTXDI_DITemporalResamplingParametersM temporalResamplingParams;
    RTXDI_BoilingFilterParametersM boilingFilterParams;
    RTXDI_DISpatialResamplingParametersM spatialResamplingParams;
    RTXDI_DISpatioTemporalResamplingParametersM spatioTemporalResamplingParams;
    RTXDI_ShadingParametersM shadingParams;
};

struct RTXDI_LightBufferRegionM
{
    uint32_t firstLightIndex;
    uint32_t numLights;
    uint32_t pad1;
    uint32_t pad2;
};

struct RTXDI_EnvironmentLightBufferParametersM
{
    uint32_t lightPresent;
    uint32_t lightIndex;
    uint32_t pad1;
    uint32_t pad2;
};

struct RTXDI_LightBufferParametersM
{
    RTXDI_LightBufferRegionM localLightBufferRegion;
    RTXDI_LightBufferRegionM infiniteLightBufferRegion;
    RTXDI_EnvironmentLightBufferParametersM environmentLightParams;
};

struct RTXDI_PackedDIReservoirM
{
    uint32_t lightData;
    uint32_t uvData;
    uint32_t mVisibility;
    uint32_t distanceAge;
    float targetPdf;
    float weight;
};

struct RTXDI_RISBufferSegmentParametersM
{
    uint32_t bufferOffset;
    uint32_t tileSize;
    uint32_t tileCount;
    uint32_t pad1;
};

struct ReSTIRDIStaticParametersM
{
    uint32_t NeighborOffsetCount;
    uint32_t RenderWidth;
    uint32_t RenderHeight;
    uint32_t CheckerboardSamplingMode;
};

struct ReGIR_CommonParametersM
{
    uint32_t localLightSamplingFallbackMode;
    float centerX;
    float centerY;
    float centerZ;
    uint32_t risBufferOffset;
    uint32_t lightsPerCell;
    float cellSize;
    float samplingJitter;
    uint32_t localLightPresamplingMode;
    uint32_t numRegirBuildSamples;
    uint32_t pad1;
    uint32_t pad2;
};

struct ReGIR_GridParametersM
{
    uint32_t cellsX;
    uint32_t cellsY;
    uint32_t cellsZ;
    uint32_t pad;
};

struct ReGIR_OnionLayerGroupM
{
    float innerRadius;
    float outerRadius;
    float invLogLayerScale;
    uint32_t layerCount;
    float invEquatorialCellAngle;
    int32_t cellsPerLayer;
    int32_t ringOffset;
    int32_t ringCount;
    float equatorialCellAngle;
    float layerScale;
    int32_t layerCellOffset;
    uint32_t pad1;
};

struct ReGIR_OnionRingM
{
    float cellAngle;
    float invCellAngle;
    int32_t cellOffset;
    int32_t cellCount;
};

// ---- Layout tables (single source of field offsets/sizes for rtxdi.xi) ----

#define RTXDIB_FIELD(structType, member)             \
    (uint32_t)offsetof(structType, member),          \
        (uint32_t)sizeof(((structType*)0)->member)

static const uint32_t kReservoirLayout[] = {
    RTXDIB_FIELD(RTXDI_ReservoirBufferParametersM, reservoirBlockRowPitch), RTXDIB_FIELD(RTXDI_ReservoirBufferParametersM, reservoirArrayPitch),
};
static const uint32_t kRuntimeLayout[] = {
    RTXDIB_FIELD(RTXDI_RuntimeParametersM, neighborOffsetMask), RTXDIB_FIELD(RTXDI_RuntimeParametersM, activeCheckerboardField),
    RTXDIB_FIELD(RTXDI_RuntimeParametersM, frameIndex),
};
static const uint32_t kBufferIndicesLayout[] = {
    RTXDIB_FIELD(RTXDI_DIBufferIndicesM, initialSamplingOutputBufferIndex), RTXDIB_FIELD(RTXDI_DIBufferIndicesM, temporalResamplingInputBufferIndex),
    RTXDIB_FIELD(RTXDI_DIBufferIndicesM, temporalResamplingOutputBufferIndex), RTXDIB_FIELD(RTXDI_DIBufferIndicesM, spatialResamplingInputBufferIndex),
    RTXDIB_FIELD(RTXDI_DIBufferIndicesM, spatialResamplingOutputBufferIndex), RTXDIB_FIELD(RTXDI_DIBufferIndicesM, shadingInputBufferIndex),
};
static const uint32_t kInitialLayout[] = {
    RTXDIB_FIELD(RTXDI_DIInitialSamplingParametersM, numLocalLightSamples), RTXDIB_FIELD(RTXDI_DIInitialSamplingParametersM, numInfiniteLightSamples),
    RTXDIB_FIELD(RTXDI_DIInitialSamplingParametersM, numEnvironmentSamples), RTXDIB_FIELD(RTXDI_DIInitialSamplingParametersM, numBrdfSamples),
    RTXDIB_FIELD(RTXDI_DIInitialSamplingParametersM, brdfCutoff), RTXDIB_FIELD(RTXDI_DIInitialSamplingParametersM, brdfRayMinT),
    RTXDIB_FIELD(RTXDI_DIInitialSamplingParametersM, localLightSamplingMode), RTXDIB_FIELD(RTXDI_DIInitialSamplingParametersM, enableInitialVisibility),
    RTXDIB_FIELD(RTXDI_DIInitialSamplingParametersM, environmentMapImportanceSampling),
};
static const uint32_t kTemporalLayout[] = {
    RTXDIB_FIELD(RTXDI_DITemporalResamplingParametersM, maxHistoryLength), RTXDIB_FIELD(RTXDI_DITemporalResamplingParametersM, biasCorrectionMode),
    RTXDIB_FIELD(RTXDI_DITemporalResamplingParametersM, depthThreshold), RTXDIB_FIELD(RTXDI_DITemporalResamplingParametersM, normalThreshold),
    RTXDIB_FIELD(RTXDI_DITemporalResamplingParametersM, enableVisibilityShortcut), RTXDIB_FIELD(RTXDI_DITemporalResamplingParametersM, enablePermutationSampling),
    RTXDIB_FIELD(RTXDI_DITemporalResamplingParametersM, uniformRandomNumber), RTXDIB_FIELD(RTXDI_DITemporalResamplingParametersM, permutationSamplingThreshold),
};
static const uint32_t kBoilingLayout[] = {
    RTXDIB_FIELD(RTXDI_BoilingFilterParametersM, enableBoilingFilter), RTXDIB_FIELD(RTXDI_BoilingFilterParametersM, boilingFilterStrength),
};
static const uint32_t kSpatialLayout[] = {
    RTXDIB_FIELD(RTXDI_DISpatialResamplingParametersM, numSamples), RTXDIB_FIELD(RTXDI_DISpatialResamplingParametersM, numDisocclusionBoostSamples),
    RTXDIB_FIELD(RTXDI_DISpatialResamplingParametersM, samplingRadius), RTXDIB_FIELD(RTXDI_DISpatialResamplingParametersM, biasCorrectionMode),
    RTXDIB_FIELD(RTXDI_DISpatialResamplingParametersM, depthThreshold), RTXDIB_FIELD(RTXDI_DISpatialResamplingParametersM, normalThreshold),
    RTXDIB_FIELD(RTXDI_DISpatialResamplingParametersM, targetHistoryLength), RTXDIB_FIELD(RTXDI_DISpatialResamplingParametersM, enableMaterialSimilarityTest),
    RTXDIB_FIELD(RTXDI_DISpatialResamplingParametersM, discountNaiveSamples),
};
static const uint32_t kSpatioTemporalLayout[] = {
    RTXDIB_FIELD(RTXDI_DISpatioTemporalResamplingParametersM, depthThreshold), RTXDIB_FIELD(RTXDI_DISpatioTemporalResamplingParametersM, normalThreshold),
    RTXDIB_FIELD(RTXDI_DISpatioTemporalResamplingParametersM, biasCorrectionMode), RTXDIB_FIELD(RTXDI_DISpatioTemporalResamplingParametersM, maxHistoryLength),
    RTXDIB_FIELD(RTXDI_DISpatioTemporalResamplingParametersM, enablePermutationSampling), RTXDIB_FIELD(RTXDI_DISpatioTemporalResamplingParametersM, uniformRandomNumber),
    RTXDIB_FIELD(RTXDI_DISpatioTemporalResamplingParametersM, enableVisibilityShortcut), RTXDIB_FIELD(RTXDI_DISpatioTemporalResamplingParametersM, numSamples),
    RTXDIB_FIELD(RTXDI_DISpatioTemporalResamplingParametersM, numDisocclusionBoostSamples), RTXDIB_FIELD(RTXDI_DISpatioTemporalResamplingParametersM, samplingRadius),
    RTXDIB_FIELD(RTXDI_DISpatioTemporalResamplingParametersM, enableMaterialSimilarityTest), RTXDIB_FIELD(RTXDI_DISpatioTemporalResamplingParametersM, discountNaiveSamples),
};
static const uint32_t kShadingLayout[] = {
    RTXDIB_FIELD(RTXDI_ShadingParametersM, enableFinalVisibility), RTXDIB_FIELD(RTXDI_ShadingParametersM, reuseFinalVisibility),
    RTXDIB_FIELD(RTXDI_ShadingParametersM, finalVisibilityMaxAge), RTXDIB_FIELD(RTXDI_ShadingParametersM, finalVisibilityMaxDistance),
    RTXDIB_FIELD(RTXDI_ShadingParametersM, enableDenoiserInputPacking),
};
static const uint32_t kLightRegionLayout[] = {
    RTXDIB_FIELD(RTXDI_LightBufferRegionM, firstLightIndex), RTXDIB_FIELD(RTXDI_LightBufferRegionM, numLights),
};
static const uint32_t kEnvLightLayout[] = {
    RTXDIB_FIELD(RTXDI_EnvironmentLightBufferParametersM, lightPresent), RTXDIB_FIELD(RTXDI_EnvironmentLightBufferParametersM, lightIndex),
};
static const uint32_t kLightBufferLayout[] = {
    RTXDIB_FIELD(RTXDI_LightBufferParametersM, localLightBufferRegion), RTXDIB_FIELD(RTXDI_LightBufferParametersM, infiniteLightBufferRegion),
    RTXDIB_FIELD(RTXDI_LightBufferParametersM, environmentLightParams),
};
static const uint32_t kPackedReservoirLayout[] = {
    RTXDIB_FIELD(RTXDI_PackedDIReservoirM, lightData), RTXDIB_FIELD(RTXDI_PackedDIReservoirM, uvData),
    RTXDIB_FIELD(RTXDI_PackedDIReservoirM, mVisibility), RTXDIB_FIELD(RTXDI_PackedDIReservoirM, distanceAge),
    RTXDIB_FIELD(RTXDI_PackedDIReservoirM, targetPdf), RTXDIB_FIELD(RTXDI_PackedDIReservoirM, weight),
};
static const uint32_t kRisSegmentLayout[] = {
    RTXDIB_FIELD(RTXDI_RISBufferSegmentParametersM, bufferOffset), RTXDIB_FIELD(RTXDI_RISBufferSegmentParametersM, tileSize),
    RTXDIB_FIELD(RTXDI_RISBufferSegmentParametersM, tileCount),
};
static const uint32_t kDiStaticLayout[] = {
    RTXDIB_FIELD(ReSTIRDIStaticParametersM, NeighborOffsetCount), RTXDIB_FIELD(ReSTIRDIStaticParametersM, RenderWidth),
    RTXDIB_FIELD(ReSTIRDIStaticParametersM, RenderHeight), RTXDIB_FIELD(ReSTIRDIStaticParametersM, CheckerboardSamplingMode),
};
static const uint32_t kRegirCommonLayout[] = {
    RTXDIB_FIELD(ReGIR_CommonParametersM, localLightSamplingFallbackMode), RTXDIB_FIELD(ReGIR_CommonParametersM, centerX),
    RTXDIB_FIELD(ReGIR_CommonParametersM, centerY), RTXDIB_FIELD(ReGIR_CommonParametersM, centerZ),
    RTXDIB_FIELD(ReGIR_CommonParametersM, risBufferOffset), RTXDIB_FIELD(ReGIR_CommonParametersM, lightsPerCell),
    RTXDIB_FIELD(ReGIR_CommonParametersM, cellSize), RTXDIB_FIELD(ReGIR_CommonParametersM, samplingJitter),
    RTXDIB_FIELD(ReGIR_CommonParametersM, localLightPresamplingMode), RTXDIB_FIELD(ReGIR_CommonParametersM, numRegirBuildSamples),
};
static const uint32_t kRegirGridLayout[] = {
    RTXDIB_FIELD(ReGIR_GridParametersM, cellsX), RTXDIB_FIELD(ReGIR_GridParametersM, cellsY), RTXDIB_FIELD(ReGIR_GridParametersM, cellsZ),
};
static const uint32_t kRegirLayerLayout[] = {
    RTXDIB_FIELD(ReGIR_OnionLayerGroupM, innerRadius), RTXDIB_FIELD(ReGIR_OnionLayerGroupM, outerRadius),
    RTXDIB_FIELD(ReGIR_OnionLayerGroupM, invLogLayerScale), RTXDIB_FIELD(ReGIR_OnionLayerGroupM, layerCount),
    RTXDIB_FIELD(ReGIR_OnionLayerGroupM, invEquatorialCellAngle), RTXDIB_FIELD(ReGIR_OnionLayerGroupM, cellsPerLayer),
    RTXDIB_FIELD(ReGIR_OnionLayerGroupM, ringOffset), RTXDIB_FIELD(ReGIR_OnionLayerGroupM, ringCount),
    RTXDIB_FIELD(ReGIR_OnionLayerGroupM, equatorialCellAngle), RTXDIB_FIELD(ReGIR_OnionLayerGroupM, layerScale),
    RTXDIB_FIELD(ReGIR_OnionLayerGroupM, layerCellOffset),
};
static const uint32_t kRegirRingLayout[] = {
    RTXDIB_FIELD(ReGIR_OnionRingM, cellAngle), RTXDIB_FIELD(ReGIR_OnionRingM, invCellAngle),
    RTXDIB_FIELD(ReGIR_OnionRingM, cellOffset), RTXDIB_FIELD(ReGIR_OnionRingM, cellCount),
};
static const uint32_t kDiParametersLayout[] = {
    RTXDIB_FIELD(RTXDI_ParametersM, reservoirBufferParams), RTXDIB_FIELD(RTXDI_ParametersM, bufferIndices),
    RTXDIB_FIELD(RTXDI_ParametersM, initialSamplingParams), RTXDIB_FIELD(RTXDI_ParametersM, temporalResamplingParams),
    RTXDIB_FIELD(RTXDI_ParametersM, boilingFilterParams), RTXDIB_FIELD(RTXDI_ParametersM, spatialResamplingParams),
    RTXDIB_FIELD(RTXDI_ParametersM, spatioTemporalResamplingParams), RTXDIB_FIELD(RTXDI_ParametersM, shadingParams),
};

#undef RTXDIB_FIELD

// ---- Bridge-carried defaults (SDK GetDefault* values; drift-checked) -------

static const uint32_t kDefaultBufferIndices[8] = { 0, 0, 0, 0, 0, 0, 0, 0 };
static const uint32_t kDefaultInitial[12] = { 8, 1, 1, 1, 953267991u, 981668463u, 0, 1, 1, 0, 0, 0 };
static const uint32_t kDefaultTemporal[8] = { 20, 1, 1036831949u, 1056964608u, 0, 1, 0, 0 };
static const uint32_t kDefaultBoiling[4] = { 1, 1045220557u, 0, 0 };
static const uint32_t kDefaultSpatial[12] = { 1, 8, 1107296256u, 1, 1036831949u, 1056964608u, 0, 1, 1, 0, 0, 0 };
static const uint32_t kDefaultSpatioTemporal[12] = { 1036831949u, 1056964608u, 1, 20, 1, 0, 0, 1, 8, 1107296256u, 1, 1 };
static const uint32_t kDefaultShading[8] = { 1, 1, 4, 1098907648u, 0, 0, 0, 0 };

} // namespace rtxdim

// ===========================================================================
// Shim entry points (resolved at run time; names fixed by the shim contract)
// ===========================================================================

typedef int32_t (*PFN_shim_info)(uint8_t*, int32_t);
typedef int32_t (*PFN_shim_layout)(int32_t, uint8_t*, int32_t);
typedef int32_t (*PFN_shim_resparams)(uint32_t, uint32_t, int32_t, uint8_t*);
typedef int32_t (*PFN_shim_pdf)(uint32_t, uint8_t*);
typedef int32_t (*PFN_shim_neigh)(uint32_t, uint8_t*, int32_t);
typedef uint32_t (*PFN_shim_hash)(uint32_t);
typedef int64_t (*PFN_shim_dicreate)(uint32_t, uint32_t, int32_t, uint32_t);
typedef int32_t (*PFN_shim_i1)(int64_t);
typedef int32_t (*PFN_shim_def)(int32_t, uint8_t*, int32_t);
typedef int32_t (*PFN_shim_diget)(int32_t, int64_t, uint8_t*, int32_t);
typedef int32_t (*PFN_shim_diset)(int32_t, int64_t, const uint8_t*, int32_t);
typedef int32_t (*PFN_shim_sfi)(int64_t, uint32_t);
typedef int32_t (*PFN_shim_gfi)(int64_t, uint8_t*);
typedef int32_t (*PFN_shim_srm)(int64_t, int32_t);
typedef int32_t (*PFN_shim_grm)(int64_t);
typedef int64_t (*PFN_shim_riscreate)();
typedef int32_t (*PFN_shim_risalloc)(int64_t, uint32_t, uint8_t*);
typedef int32_t (*PFN_shim_ris4)(int64_t, uint8_t*);
typedef int64_t (*PFN_shim_regirc)(int64_t, int32_t, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t);
typedef int32_t (*PFN_shim_regir_onion)(int64_t, uint8_t*, int32_t);
typedef int32_t (*PFN_shim_regir_dyn_get)(int64_t, uint8_t*);
typedef int32_t (*PFN_shim_regir_dyn_set)(int64_t, const uint8_t*, int32_t);
typedef int32_t (*PFN_shim_regir_power)(int64_t);
typedef int64_t (*PFN_shim_iscreate)(const uint8_t*, int32_t);
typedef int64_t (*PFN_shim_ischild)(int64_t);
typedef int32_t (*PFN_shim_is_lb)(int64_t, uint8_t*);
typedef int32_t (*PFN_shim_is_set_lb)(int64_t, const uint8_t*, int32_t);
typedef int32_t (*PFN_shim_is_neigh)(int64_t, uint8_t*);
typedef int32_t (*PFN_shim_is_bool)(int64_t);

static HMODULE g_module = 0;
static int32_t g_load_kind = RTXDIB_LOAD_ABSENT;

static PFN_shim_info g_info = 0;
static PFN_shim_layout g_sdk_layout = 0;
static PFN_shim_resparams g_resparams = 0;
static PFN_shim_pdf g_pdf = 0;
static PFN_shim_neigh g_neigh = 0;
static PFN_shim_hash g_hash = 0;
static PFN_shim_dicreate g_di_create = 0;
static PFN_shim_i1 g_di_destroy = 0;
static PFN_shim_def g_sdk_defaults = 0;
static PFN_shim_diget g_di_get = 0;
static PFN_shim_diset g_di_set = 0;
static PFN_shim_sfi g_di_set_frame = 0;
static PFN_shim_gfi g_di_get_frame = 0;
static PFN_shim_srm g_di_set_mode = 0;
static PFN_shim_grm g_di_get_mode = 0;
static PFN_shim_riscreate g_ris_create = 0;
static PFN_shim_i1 g_ris_destroy = 0;
static PFN_shim_risalloc g_ris_allocate = 0;
static PFN_shim_ris4 g_ris_total = 0;
static PFN_shim_regirc g_regir_create = 0;
static PFN_shim_i1 g_regir_destroy = 0;
static PFN_shim_ris4 g_regir_cell_offset = 0;
static PFN_shim_ris4 g_regir_light_slots = 0;
static PFN_shim_ris4 g_regir_get_grid = 0;
static PFN_shim_regir_onion g_regir_get_onion = 0;
static PFN_shim_regir_dyn_get g_regir_get_dynamic = 0;
static PFN_shim_regir_dyn_set g_regir_set_dynamic = 0;
static PFN_shim_regir_power g_regir_power = 0;
static PFN_shim_iscreate g_is_create = 0;
static PFN_shim_i1 g_is_destroy = 0;
static PFN_shim_ischild g_is_di = 0;
static PFN_shim_ischild g_is_regir = 0;
static PFN_shim_ischild g_is_ris = 0;
static PFN_shim_ris4 g_is_ris_total = 0;
static PFN_shim_is_lb g_is_lb = 0;
static PFN_shim_is_set_lb g_is_set_lb = 0;
static PFN_shim_is_lb g_is_local_ris = 0;
static PFN_shim_is_lb g_is_env_ris = 0;
static PFN_shim_is_neigh g_is_neigh = 0;
static PFN_shim_is_bool g_is_power = 0;
static PFN_shim_is_bool g_is_regir_enabled = 0;

static void rtxdib_wr_u32(uint8_t* dst, uint32_t v)
{
    dst[0] = (uint8_t)(v & 0xFF);
    dst[1] = (uint8_t)((v >> 8) & 0xFF);
    dst[2] = (uint8_t)((v >> 16) & 0xFF);
    dst[3] = (uint8_t)((v >> 24) & 0xFF);
}

static void rtxdib_reset_state()
{
    g_module = 0;
    g_load_kind = RTXDIB_LOAD_ABSENT;
    g_info = 0; g_sdk_layout = 0; g_resparams = 0; g_pdf = 0; g_neigh = 0; g_hash = 0;
    g_di_create = 0; g_di_destroy = 0; g_sdk_defaults = 0; g_di_get = 0; g_di_set = 0;
    g_di_set_frame = 0; g_di_get_frame = 0; g_di_set_mode = 0; g_di_get_mode = 0;
    g_ris_create = 0; g_ris_destroy = 0; g_ris_allocate = 0; g_ris_total = 0;
    g_regir_create = 0; g_regir_destroy = 0; g_regir_cell_offset = 0; g_regir_light_slots = 0;
    g_regir_get_grid = 0; g_regir_get_onion = 0; g_regir_get_dynamic = 0; g_regir_set_dynamic = 0; g_regir_power = 0;
    g_is_create = 0; g_is_destroy = 0; g_is_di = 0; g_is_regir = 0; g_is_ris = 0; g_is_ris_total = 0;
    g_is_lb = 0; g_is_set_lb = 0; g_is_local_ris = 0; g_is_env_ris = 0; g_is_neigh = 0; g_is_power = 0; g_is_regir_enabled = 0;
}

static int64_t rtxdib_finish_load(HMODULE module)
{
    g_info = (PFN_shim_info)(void*)GetProcAddress(module, "rtxdishim_info");
    g_sdk_layout = (PFN_shim_layout)(void*)GetProcAddress(module, "rtxdishim_layout");
    g_resparams = (PFN_shim_resparams)(void*)GetProcAddress(module, "rtxdishim_utils_reservoir_params");
    g_pdf = (PFN_shim_pdf)(void*)GetProcAddress(module, "rtxdishim_utils_pdf_size");
    g_neigh = (PFN_shim_neigh)(void*)GetProcAddress(module, "rtxdishim_utils_fill_neighbor_offsets");
    g_hash = (PFN_shim_hash)(void*)GetProcAddress(module, "rtxdishim_utils_jenkins_hash");
    g_di_create = (PFN_shim_dicreate)(void*)GetProcAddress(module, "rtxdishim_di_create");
    g_di_destroy = (PFN_shim_i1)(void*)GetProcAddress(module, "rtxdishim_di_destroy");
    g_sdk_defaults = (PFN_shim_def)(void*)GetProcAddress(module, "rtxdishim_di_defaults");
    g_di_get = (PFN_shim_diget)(void*)GetProcAddress(module, "rtxdishim_di_get");
    g_di_set = (PFN_shim_diset)(void*)GetProcAddress(module, "rtxdishim_di_set");
    g_di_set_frame = (PFN_shim_sfi)(void*)GetProcAddress(module, "rtxdishim_di_set_frame_index");
    g_di_get_frame = (PFN_shim_gfi)(void*)GetProcAddress(module, "rtxdishim_di_get_frame_index");
    g_di_set_mode = (PFN_shim_srm)(void*)GetProcAddress(module, "rtxdishim_di_set_resampling_mode");
    g_di_get_mode = (PFN_shim_grm)(void*)GetProcAddress(module, "rtxdishim_di_get_resampling_mode");
    g_ris_create = (PFN_shim_riscreate)(void*)GetProcAddress(module, "rtxdishim_ris_create");
    g_ris_destroy = (PFN_shim_i1)(void*)GetProcAddress(module, "rtxdishim_ris_destroy");
    g_ris_allocate = (PFN_shim_risalloc)(void*)GetProcAddress(module, "rtxdishim_ris_allocate");
    g_ris_total = (PFN_shim_ris4)(void*)GetProcAddress(module, "rtxdishim_ris_total");
    g_regir_create = (PFN_shim_regirc)(void*)GetProcAddress(module, "rtxdishim_regir_create");
    g_regir_destroy = (PFN_shim_i1)(void*)GetProcAddress(module, "rtxdishim_regir_destroy");
    g_regir_cell_offset = (PFN_shim_ris4)(void*)GetProcAddress(module, "rtxdishim_regir_cell_offset");
    g_regir_light_slots = (PFN_shim_ris4)(void*)GetProcAddress(module, "rtxdishim_regir_light_slots");
    g_regir_get_grid = (PFN_shim_ris4)(void*)GetProcAddress(module, "rtxdishim_regir_get_grid");
    g_regir_get_onion = (PFN_shim_regir_onion)(void*)GetProcAddress(module, "rtxdishim_regir_get_onion");
    g_regir_get_dynamic = (PFN_shim_regir_dyn_get)(void*)GetProcAddress(module, "rtxdishim_regir_get_dynamic");
    g_regir_set_dynamic = (PFN_shim_regir_dyn_set)(void*)GetProcAddress(module, "rtxdishim_regir_set_dynamic");
    g_regir_power = (PFN_shim_regir_power)(void*)GetProcAddress(module, "rtxdishim_regir_power_ris");
    g_is_create = (PFN_shim_iscreate)(void*)GetProcAddress(module, "rtxdishim_is_create");
    g_is_destroy = (PFN_shim_i1)(void*)GetProcAddress(module, "rtxdishim_is_destroy");
    g_is_di = (PFN_shim_ischild)(void*)GetProcAddress(module, "rtxdishim_is_di");
    g_is_regir = (PFN_shim_ischild)(void*)GetProcAddress(module, "rtxdishim_is_regir");
    g_is_ris = (PFN_shim_ischild)(void*)GetProcAddress(module, "rtxdishim_is_ris");
    g_is_ris_total = (PFN_shim_ris4)(void*)GetProcAddress(module, "rtxdishim_is_ris_total");
    g_is_lb = (PFN_shim_is_lb)(void*)GetProcAddress(module, "rtxdishim_is_light_buffer");
    g_is_set_lb = (PFN_shim_is_set_lb)(void*)GetProcAddress(module, "rtxdishim_is_set_light_buffer");
    g_is_local_ris = (PFN_shim_is_lb)(void*)GetProcAddress(module, "rtxdishim_is_local_ris");
    g_is_env_ris = (PFN_shim_is_lb)(void*)GetProcAddress(module, "rtxdishim_is_env_ris");
    g_is_neigh = (PFN_shim_is_neigh)(void*)GetProcAddress(module, "rtxdishim_is_neighbor_count");
    g_is_power = (PFN_shim_is_bool)(void*)GetProcAddress(module, "rtxdishim_is_power_ris");
    g_is_regir_enabled = (PFN_shim_is_bool)(void*)GetProcAddress(module, "rtxdishim_is_regir_enabled");

    if (!g_info || !g_sdk_layout || !g_resparams || !g_pdf || !g_neigh || !g_hash ||
        !g_di_create || !g_di_destroy || !g_sdk_defaults || !g_di_get || !g_di_set ||
        !g_di_set_frame || !g_di_get_frame || !g_di_set_mode || !g_di_get_mode ||
        !g_ris_create || !g_ris_destroy || !g_ris_allocate || !g_ris_total ||
        !g_regir_create || !g_regir_destroy || !g_regir_cell_offset || !g_regir_light_slots ||
        !g_regir_get_grid || !g_regir_get_onion || !g_regir_get_dynamic || !g_regir_set_dynamic || !g_regir_power ||
        !g_is_create || !g_is_destroy || !g_is_di || !g_is_regir || !g_is_ris || !g_is_ris_total ||
        !g_is_lb || !g_is_set_lb || !g_is_local_ris || !g_is_env_ris || !g_is_neigh || !g_is_power || !g_is_regir_enabled)
    {
        FreeLibrary(module);
        rtxdib_reset_state();
        g_load_kind = RTXDIB_LOAD_ABI;
        return 0;
    }

    g_module = module;
    g_load_kind = RTXDIB_LOAD_OK;
    return (int64_t)(intptr_t)module;
}

static int32_t rtxdib_check(int64_t handle)
{
    if (handle == 0) return RTXDIB_ERR_BAD_ARGS;
    if (g_module == 0 || (HMODULE)(intptr_t)handle != g_module) return RTXDIB_ERR_NOT_LOADED;
    return 0;
}

// ===========================================================================
// extern "C" surface
// ===========================================================================

extern "C" {

// ---- Loader ---------------------------------------------------------------

int64_t rtxdib_try_load(const uint8_t* path, int32_t len)
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
        g_load_kind = RTXDIB_LOAD_ABSENT;
        return 0;
    }
    return rtxdib_finish_load(module);
}

int64_t rtxdib_try_load_auto()
{
    char buffer[1024 + 1];
    DWORD n;
    HMODULE module;

    if (g_module != 0) return (int64_t)(intptr_t)g_module;

    n = GetEnvironmentVariableA("XIOM_RTXDI_SHIM", buffer, 1024);
    if (n > 0 && n < 1024)
    {
        module = LoadLibraryA(buffer);
        if (module != 0) return rtxdib_finish_load(module);
    }

    module = LoadLibraryA("xiom_rtxdi_shim.dll");
    if (module == 0)
    {
        g_load_kind = RTXDIB_LOAD_ABSENT;
        return 0;
    }
    return rtxdib_finish_load(module);
}

int32_t rtxdib_load_kind() { return g_load_kind; }

int32_t rtxdib_close(int64_t handle)
{
    HMODULE module;

    if (handle == 0) return 0;
    if (g_module != (HMODULE)(intptr_t)handle) return RTXDIB_ERR_BAD_ARGS;
    module = g_module;
    rtxdib_reset_state();
    FreeLibrary(module);
    return 0;
}

// ---- Layout tables (ours; no shim needed) ----------------------------------

int32_t rtxdib_layout(int32_t kind, uint8_t* offsets, uint8_t* sizes, int32_t cap)
{
    const uint32_t* table = 0;
    uint32_t count = 0;
    uint32_t i;

    switch (kind)
    {
    case 0: table = rtxdim::kReservoirLayout; count = (uint32_t)(sizeof(rtxdim::kReservoirLayout) / sizeof(uint32_t)) / 2; break;
    case 1: table = rtxdim::kRuntimeLayout; count = (uint32_t)(sizeof(rtxdim::kRuntimeLayout) / sizeof(uint32_t)) / 2; break;
    case 2: table = rtxdim::kBufferIndicesLayout; count = (uint32_t)(sizeof(rtxdim::kBufferIndicesLayout) / sizeof(uint32_t)) / 2; break;
    case 3: table = rtxdim::kInitialLayout; count = (uint32_t)(sizeof(rtxdim::kInitialLayout) / sizeof(uint32_t)) / 2; break;
    case 4: table = rtxdim::kTemporalLayout; count = (uint32_t)(sizeof(rtxdim::kTemporalLayout) / sizeof(uint32_t)) / 2; break;
    case 5: table = rtxdim::kBoilingLayout; count = (uint32_t)(sizeof(rtxdim::kBoilingLayout) / sizeof(uint32_t)) / 2; break;
    case 6: table = rtxdim::kSpatialLayout; count = (uint32_t)(sizeof(rtxdim::kSpatialLayout) / sizeof(uint32_t)) / 2; break;
    case 7: table = rtxdim::kSpatioTemporalLayout; count = (uint32_t)(sizeof(rtxdim::kSpatioTemporalLayout) / sizeof(uint32_t)) / 2; break;
    case 8: table = rtxdim::kShadingLayout; count = (uint32_t)(sizeof(rtxdim::kShadingLayout) / sizeof(uint32_t)) / 2; break;
    case 9: table = rtxdim::kLightRegionLayout; count = 2; break;
    case 10: table = rtxdim::kEnvLightLayout; count = 2; break;
    case 11: table = rtxdim::kLightBufferLayout; count = 3; break;
    case 12: table = rtxdim::kPackedReservoirLayout; count = 6; break;
    case 13: table = rtxdim::kRisSegmentLayout; count = 3; break;
    case 14: table = rtxdim::kDiStaticLayout; count = 4; break;
    case 15: table = rtxdim::kRegirCommonLayout; count = 10; break;
    case 16: table = rtxdim::kRegirGridLayout; count = 3; break;
    case 17: table = rtxdim::kRegirLayerLayout; count = 11; break;
    case 18: table = rtxdim::kRegirRingLayout; count = 4; break;
    case 19: table = rtxdim::kDiParametersLayout; count = 8; break;
    default: return RTXDIB_ERR_BAD_ARGS;
    }

    if (offsets == 0 || sizes == 0) return (int32_t)count; // count probe
    if ((int32_t)count > cap) return RTXDIB_ERR_CAPACITY;

    for (i = 0; i < count; i++)
    {
        rtxdib_wr_u32(offsets + (size_t)i * 4, table[i * 2 + 0]);
        rtxdib_wr_u32(sizes + (size_t)i * 4, table[i * 2 + 1]);
    }
    return (int32_t)count;
}

int32_t rtxdib_layout_size(int32_t kind)
{
    switch (kind)
    {
    case 0: return (int32_t)sizeof(rtxdim::RTXDI_ReservoirBufferParametersM);
    case 1: return (int32_t)sizeof(rtxdim::RTXDI_RuntimeParametersM);
    case 2: return (int32_t)sizeof(rtxdim::RTXDI_DIBufferIndicesM);
    case 3: return (int32_t)sizeof(rtxdim::RTXDI_DIInitialSamplingParametersM);
    case 4: return (int32_t)sizeof(rtxdim::RTXDI_DITemporalResamplingParametersM);
    case 5: return (int32_t)sizeof(rtxdim::RTXDI_BoilingFilterParametersM);
    case 6: return (int32_t)sizeof(rtxdim::RTXDI_DISpatialResamplingParametersM);
    case 7: return (int32_t)sizeof(rtxdim::RTXDI_DISpatioTemporalResamplingParametersM);
    case 8: return (int32_t)sizeof(rtxdim::RTXDI_ShadingParametersM);
    case 9: return (int32_t)sizeof(rtxdim::RTXDI_LightBufferRegionM);
    case 10: return (int32_t)sizeof(rtxdim::RTXDI_EnvironmentLightBufferParametersM);
    case 11: return (int32_t)sizeof(rtxdim::RTXDI_LightBufferParametersM);
    case 12: return (int32_t)sizeof(rtxdim::RTXDI_PackedDIReservoirM);
    case 13: return (int32_t)sizeof(rtxdim::RTXDI_RISBufferSegmentParametersM);
    case 14: return (int32_t)sizeof(rtxdim::ReSTIRDIStaticParametersM);
    case 15: return (int32_t)sizeof(rtxdim::ReGIR_CommonParametersM);
    case 16: return (int32_t)sizeof(rtxdim::ReGIR_GridParametersM);
    case 17: return (int32_t)sizeof(rtxdim::ReGIR_OnionLayerGroupM);
    case 18: return (int32_t)sizeof(rtxdim::ReGIR_OnionRingM);
    case 19: return (int32_t)sizeof(rtxdim::RTXDI_ParametersM);
    default: return -1;
    }
}

// Bridge-carried SDK defaults by kind: 0 BufferIndices, 1 Initial,
// 2 Temporal, 3 Boiling, 4 Spatial, 5 SpatioTemporal, 6 Shading.
int32_t rtxdib_param_default(int32_t kind, uint8_t* dst, int32_t cap)
{
    const uint32_t* src = 0;
    int32_t words = 0;

    switch (kind)
    {
    case 0: src = rtxdim::kDefaultBufferIndices; words = 8; break;
    case 1: src = rtxdim::kDefaultInitial; words = 12; break;
    case 2: src = rtxdim::kDefaultTemporal; words = 8; break;
    case 3: src = rtxdim::kDefaultBoiling; words = 4; break;
    case 4: src = rtxdim::kDefaultSpatial; words = 12; break;
    case 5: src = rtxdim::kDefaultSpatioTemporal; words = 12; break;
    case 6: src = rtxdim::kDefaultShading; words = 8; break;
    default: return RTXDIB_ERR_BAD_ARGS;
    }

    if (dst == 0) return words * 4;
    if (cap < words * 4) return RTXDIB_ERR_SIZE;
    for (int32_t i = 0; i < words; i++) rtxdib_wr_u32(dst + (size_t)i * 4, src[i]);
    return words * 4;
}

// ---- Forwarded surface ------------------------------------------------------

int32_t rtxdib_info(int64_t handle, uint8_t* out, int32_t cap)
{
    int32_t rc = rtxdib_check(handle);
    if (rc != 0) return rc;
    if (out == 0 || cap < 132) return RTXDIB_ERR_BAD_ARGS;
    return g_info(out, cap);
}

int32_t rtxdib_sdk_layout(int64_t handle, int32_t kind, uint8_t* out, int32_t cap)
{
    int32_t rc = rtxdib_check(handle);
    if (rc != 0) return rc;
    if (out == 0) return RTXDIB_ERR_BAD_ARGS;
    return g_sdk_layout(kind, out, cap);
}

int32_t rtxdib_sdk_param_default(int64_t handle, int32_t kind, uint8_t* dst, int32_t cap)
{
    int32_t rc = rtxdib_check(handle);
    if (rc != 0) return rc;
    if (dst == 0) return RTXDIB_ERR_BAD_ARGS;
    return g_sdk_defaults(kind, dst, cap);
}

int32_t rtxdib_utils_reservoir_params(int64_t handle, uint32_t width, uint32_t height, int32_t checkerboard, uint8_t* out16)
{
    int32_t rc = rtxdib_check(handle);
    if (rc != 0) return rc;
    if (out16 == 0) return RTXDIB_ERR_BAD_ARGS;
    return g_resparams(width, height, checkerboard, out16);
}

int32_t rtxdib_utils_pdf_size(int64_t handle, uint32_t max_items, uint8_t* out12)
{
    int32_t rc = rtxdib_check(handle);
    if (rc != 0) return rc;
    if (out12 == 0) return RTXDIB_ERR_BAD_ARGS;
    return g_pdf(max_items, out12);
}

int32_t rtxdib_utils_fill_neighbor_offsets(int64_t handle, uint32_t count, uint8_t* out, int32_t cap)
{
    int32_t rc = rtxdib_check(handle);
    if (rc != 0) return rc;
    if (out == 0) return RTXDIB_ERR_BAD_ARGS;
    return g_neigh(count, out, cap);
}

int64_t rtxdib_utils_jenkins_hash(int64_t handle, uint32_t a)
{
    int32_t rc = rtxdib_check(handle);
    if (rc != 0) return rc;
    return (int64_t)(uint64_t)g_hash(a);
}

// ---- DI context -------------------------------------------------------------

int32_t rtxdib_di_create(int64_t handle, uint32_t width, uint32_t height, int32_t checkerboard, uint32_t neighbor_offset_count, uint8_t* out8)
{
    int32_t rc = rtxdib_check(handle);
    int64_t ctx;
    int i;

    if (rc != 0) return rc;
    if (out8 == 0) return RTXDIB_ERR_BAD_ARGS;

    ctx = g_di_create(width, height, checkerboard, neighbor_offset_count);
    if (ctx == 0) return 1; // SDK-side rejection (bad args)
    for (i = 0; i < 8; i++) out8[i] = (uint8_t)(((uint64_t)ctx >> (8 * i)) & 0xFF);
    return 0;
}

int32_t rtxdib_di_destroy(int64_t handle, int64_t ctx)
{
    int32_t rc = rtxdib_check(handle);
    if (rc != 0) return rc;
    if (ctx == 0) return RTXDIB_ERR_BAD_ARGS;
    return g_di_destroy(ctx);
}

int32_t rtxdib_di_get(int64_t handle, int32_t part, int64_t ctx, uint8_t* out, int32_t cap)
{
    int32_t rc = rtxdib_check(handle);
    if (rc != 0) return rc;
    if (ctx == 0 || out == 0) return RTXDIB_ERR_BAD_ARGS;
    return g_di_get(part, ctx, out, cap);
}

int32_t rtxdib_di_set(int64_t handle, int32_t part, int64_t ctx, const uint8_t* img, int32_t size)
{
    int32_t rc = rtxdib_check(handle);
    if (rc != 0) return rc;
    if (ctx == 0 || img == 0) return RTXDIB_ERR_BAD_ARGS;
    return g_di_set(part, ctx, img, size);
}

int32_t rtxdib_di_set_frame_index(int64_t handle, int64_t ctx, uint32_t frame_index)
{
    int32_t rc = rtxdib_check(handle);
    if (rc != 0) return rc;
    if (ctx == 0) return RTXDIB_ERR_BAD_ARGS;
    return g_di_set_frame(ctx, frame_index);
}

int32_t rtxdib_di_get_frame_index(int64_t handle, int64_t ctx, uint8_t* out4)
{
    int32_t rc = rtxdib_check(handle);
    if (rc != 0) return rc;
    if (ctx == 0 || out4 == 0) return RTXDIB_ERR_BAD_ARGS;
    return g_di_get_frame(ctx, out4);
}

int32_t rtxdib_di_set_resampling_mode(int64_t handle, int64_t ctx, int32_t mode)
{
    int32_t rc = rtxdib_check(handle);
    if (rc != 0) return rc;
    if (ctx == 0) return RTXDIB_ERR_BAD_ARGS;
    return g_di_set_mode(ctx, mode);
}

int32_t rtxdib_di_get_resampling_mode(int64_t handle, int64_t ctx)
{
    int32_t rc = rtxdib_check(handle);
    if (rc != 0) return rc;
    if (ctx == 0) return RTXDIB_ERR_BAD_ARGS;
    return g_di_get_mode(ctx);
}

// ---- RIS buffer segment allocator -------------------------------------------

int32_t rtxdib_ris_create(int64_t handle, uint8_t* out8)
{
    int32_t rc = rtxdib_check(handle);
    int64_t ris;
    int i;

    if (rc != 0) return rc;
    if (out8 == 0) return RTXDIB_ERR_BAD_ARGS;

    ris = g_ris_create();
    if (ris == 0) return 1;
    for (i = 0; i < 8; i++) out8[i] = (uint8_t)(((uint64_t)ris >> (8 * i)) & 0xFF);
    return 0;
}

int32_t rtxdib_ris_destroy(int64_t handle, int64_t ris)
{
    int32_t rc = rtxdib_check(handle);
    if (rc != 0) return rc;
    if (ris == 0) return RTXDIB_ERR_BAD_ARGS;
    return g_ris_destroy(ris);
}

int32_t rtxdib_ris_allocate(int64_t handle, int64_t ris, uint32_t size, uint8_t* out4)
{
    int32_t rc = rtxdib_check(handle);
    if (rc != 0) return rc;
    if (ris == 0 || out4 == 0) return RTXDIB_ERR_BAD_ARGS;
    return g_ris_allocate(ris, size, out4);
}

int32_t rtxdib_ris_total(int64_t handle, int64_t ris, uint8_t* out4)
{
    int32_t rc = rtxdib_check(handle);
    if (rc != 0) return rc;
    if (ris == 0 || out4 == 0) return RTXDIB_ERR_BAD_ARGS;
    return g_ris_total(ris, out4);
}

// ---- ReGIR context ----------------------------------------------------------

int32_t rtxdib_regir_create(int64_t handle, int64_t ris, int32_t mode, uint32_t gx, uint32_t gy, uint32_t gz,
                            uint32_t lights_per_cell, uint32_t onion_detail, uint32_t onion_coverage, uint8_t* out8)
{
    int32_t rc = rtxdib_check(handle);
    int64_t ctx;
    int i;

    if (rc != 0) return rc;
    if (ris == 0 || out8 == 0) return RTXDIB_ERR_BAD_ARGS;

    ctx = g_regir_create(ris, mode, gx, gy, gz, lights_per_cell, onion_detail, onion_coverage);
    if (ctx == 0) return 1;
    for (i = 0; i < 8; i++) out8[i] = (uint8_t)(((uint64_t)ctx >> (8 * i)) & 0xFF);
    return 0;
}

int32_t rtxdib_regir_destroy(int64_t handle, int64_t ctx)
{
    int32_t rc = rtxdib_check(handle);
    if (rc != 0) return rc;
    if (ctx == 0) return RTXDIB_ERR_BAD_ARGS;
    return g_regir_destroy(ctx);
}

int32_t rtxdib_regir_cell_offset(int64_t handle, int64_t ctx, uint8_t* out4)
{
    int32_t rc = rtxdib_check(handle);
    if (rc != 0) return rc;
    if (ctx == 0 || out4 == 0) return RTXDIB_ERR_BAD_ARGS;
    return g_regir_cell_offset(ctx, out4);
}

int32_t rtxdib_regir_light_slots(int64_t handle, int64_t ctx, uint8_t* out4)
{
    int32_t rc = rtxdib_check(handle);
    if (rc != 0) return rc;
    if (ctx == 0 || out4 == 0) return RTXDIB_ERR_BAD_ARGS;
    return g_regir_light_slots(ctx, out4);
}

int32_t rtxdib_regir_get_grid(int64_t handle, int64_t ctx, uint8_t* out16)
{
    int32_t rc = rtxdib_check(handle);
    if (rc != 0) return rc;
    if (ctx == 0 || out16 == 0) return RTXDIB_ERR_BAD_ARGS;
    return g_regir_get_grid(ctx, out16);
}

int32_t rtxdib_regir_get_onion(int64_t handle, int64_t ctx, uint8_t* out, int32_t cap)
{
    int32_t rc = rtxdib_check(handle);
    if (rc != 0) return rc;
    if (ctx == 0 || out == 0) return RTXDIB_ERR_BAD_ARGS;
    return g_regir_get_onion(ctx, out, cap);
}

int32_t rtxdib_regir_get_dynamic(int64_t handle, int64_t ctx, uint8_t* out32)
{
    int32_t rc = rtxdib_check(handle);
    if (rc != 0) return rc;
    if (ctx == 0 || out32 == 0) return RTXDIB_ERR_BAD_ARGS;
    return g_regir_get_dynamic(ctx, out32);
}

int32_t rtxdib_regir_set_dynamic(int64_t handle, int64_t ctx, const uint8_t* img, int32_t size)
{
    int32_t rc = rtxdib_check(handle);
    if (rc != 0) return rc;
    if (ctx == 0 || img == 0) return RTXDIB_ERR_BAD_ARGS;
    return g_regir_set_dynamic(ctx, img, size);
}

int32_t rtxdib_regir_power_ris(int64_t handle, int64_t ctx)
{
    int32_t rc = rtxdib_check(handle);
    if (rc != 0) return rc;
    if (ctx == 0) return RTXDIB_ERR_BAD_ARGS;
    return g_regir_power(ctx);
}

// ---- ImportanceSamplingContext ----------------------------------------------

int32_t rtxdib_is_create(int64_t handle, const uint8_t* img, int32_t size, uint8_t* out8)
{
    int32_t rc = rtxdib_check(handle);
    int64_t ctx;
    int i;

    if (rc != 0) return rc;
    if (img == 0 || out8 == 0) return RTXDIB_ERR_BAD_ARGS;
    if (size < 60) return RTXDIB_ERR_SIZE;

    ctx = g_is_create(img, size);
    if (ctx == 0) return 1;
    for (i = 0; i < 8; i++) out8[i] = (uint8_t)(((uint64_t)ctx >> (8 * i)) & 0xFF);
    return 0;
}

int32_t rtxdib_is_destroy(int64_t handle, int64_t ctx)
{
    int32_t rc = rtxdib_check(handle);
    if (rc != 0) return rc;
    if (ctx == 0) return RTXDIB_ERR_BAD_ARGS;
    return g_is_destroy(ctx);
}

int32_t rtxdib_is_di(int64_t handle, int64_t ctx, uint8_t* out8)
{
    int32_t rc = rtxdib_check(handle);
    int64_t child;
    int i;

    if (rc != 0) return rc;
    if (ctx == 0 || out8 == 0) return RTXDIB_ERR_BAD_ARGS;
    child = g_is_di(ctx);
    for (i = 0; i < 8; i++) out8[i] = (uint8_t)(((uint64_t)child >> (8 * i)) & 0xFF);
    return 0;
}

int32_t rtxdib_is_regir(int64_t handle, int64_t ctx, uint8_t* out8)
{
    int32_t rc = rtxdib_check(handle);
    int64_t child;
    int i;

    if (rc != 0) return rc;
    if (ctx == 0 || out8 == 0) return RTXDIB_ERR_BAD_ARGS;
    child = g_is_regir(ctx);
    for (i = 0; i < 8; i++) out8[i] = (uint8_t)(((uint64_t)child >> (8 * i)) & 0xFF);
    return 0;
}

int32_t rtxdib_is_ris(int64_t handle, int64_t ctx, uint8_t* out8)
{
    int32_t rc = rtxdib_check(handle);
    int64_t child;
    int i;

    if (rc != 0) return rc;
    if (ctx == 0 || out8 == 0) return RTXDIB_ERR_BAD_ARGS;
    child = g_is_ris(ctx);
    for (i = 0; i < 8; i++) out8[i] = (uint8_t)(((uint64_t)child >> (8 * i)) & 0xFF);
    return 0;
}

int32_t rtxdib_is_ris_total(int64_t handle, int64_t ctx, uint8_t* out4)
{
    int32_t rc = rtxdib_check(handle);
    if (rc != 0) return rc;
    if (ctx == 0 || out4 == 0) return RTXDIB_ERR_BAD_ARGS;
    return g_is_ris_total(ctx, out4);
}

int32_t rtxdib_is_light_buffer(int64_t handle, int64_t ctx, uint8_t* out48)
{
    int32_t rc = rtxdib_check(handle);
    if (rc != 0) return rc;
    if (ctx == 0 || out48 == 0) return RTXDIB_ERR_BAD_ARGS;
    return g_is_lb(ctx, out48);
}

int32_t rtxdib_is_set_light_buffer(int64_t handle, int64_t ctx, const uint8_t* img, int32_t size)
{
    int32_t rc = rtxdib_check(handle);
    if (rc != 0) return rc;
    if (ctx == 0 || img == 0) return RTXDIB_ERR_BAD_ARGS;
    if (size < 48) return RTXDIB_ERR_SIZE;
    return g_is_set_lb(ctx, img, size);
}

int32_t rtxdib_is_local_ris(int64_t handle, int64_t ctx, uint8_t* out16)
{
    int32_t rc = rtxdib_check(handle);
    if (rc != 0) return rc;
    if (ctx == 0 || out16 == 0) return RTXDIB_ERR_BAD_ARGS;
    return g_is_local_ris(ctx, out16);
}

int32_t rtxdib_is_env_ris(int64_t handle, int64_t ctx, uint8_t* out16)
{
    int32_t rc = rtxdib_check(handle);
    if (rc != 0) return rc;
    if (ctx == 0 || out16 == 0) return RTXDIB_ERR_BAD_ARGS;
    return g_is_env_ris(ctx, out16);
}

int32_t rtxdib_is_neighbor_count(int64_t handle, int64_t ctx, uint8_t* out4)
{
    int32_t rc = rtxdib_check(handle);
    if (rc != 0) return rc;
    if (ctx == 0 || out4 == 0) return RTXDIB_ERR_BAD_ARGS;
    return g_is_neigh(ctx, out4);
}

int32_t rtxdib_is_power_ris(int64_t handle, int64_t ctx)
{
    int32_t rc = rtxdib_check(handle);
    if (rc != 0) return rc;
    if (ctx == 0) return RTXDIB_ERR_BAD_ARGS;
    return g_is_power(ctx);
}

int32_t rtxdib_is_regir_enabled(int64_t handle, int64_t ctx)
{
    int32_t rc = rtxdib_check(handle);
    if (rc != 0) return rc;
    if (ctx == 0) return RTXDIB_ERR_BAD_ARGS;
    return g_is_regir_enabled(ctx);
}

// ---- Owned-image scalar accessors (XIOM-owned slots; B-17/B-24) -------------

int32_t rtxdib_img_set_u32(uint8_t* dst, int32_t cap, int32_t off, int32_t v)
{
    if (dst == 0 || off < 0 || cap < off + 4) return RTXDIB_ERR_BAD_ARGS;
    rtxdib_wr_u32(dst + off, (uint32_t)v);
    return 0;
}

int32_t rtxdib_img_set_f32(uint8_t* dst, int32_t cap, int32_t off, float v)
{
    if (dst == 0 || off < 0 || cap < off + 4) return RTXDIB_ERR_BAD_ARGS;
    memcpy(dst + off, &v, 4);
    return 0;
}

int32_t rtxdib_img_get_u32(const uint8_t* src, int32_t cap, int32_t off)
{
    if (src == 0 || off < 0 || cap < off + 4) return -1;
    return (int32_t)((uint32_t)src[off] | ((uint32_t)src[off + 1] << 8) | ((uint32_t)src[off + 2] << 16) | ((uint32_t)src[off + 3] << 24));
}

float rtxdib_img_get_f32(const uint8_t* src, int32_t cap, int32_t off)
{
    float v = 0.0f;
    if (src == 0 || off < 0 || cap < off + 4) return 0.0f;
    memcpy(&v, src + off, 4);
    return v;
}

} // extern "C"
