/* XIOM -- xiom.fidelityfx bridge (C++20).
 *
 * Compiled at suite link time from port.args.json (--c-source, --cxx-standard
 * c++20; the vendored FidelityFX headers need <bit> through ffx_util.h).
 *
 * What this bridge provides:
 *   - the CPU constant/config helpers of the pinned headers (FSR1 EASU/RCAS
 *     constant setup, SPD dispatch setup) with typed argument validation;
 *   - the SDK's own ffxLoadFunctions loader helper bound over the vendored
 *     header (fills five pointers into a caller-owned slot);
 *   - the vendored compiled shader blobs as a read-only registry (byte
 *     payloads copied into caller-owned slots -- XIOM never reads through a
 *     foreign pointer);
 *   - SDK/effect version probes compiled from the pinned headers.
 *
 * Discipline (B-20/B-23/B-24): every out-param is written into an owned slot
 * passed by the XIOM caller; no foreign memory is read; nullable pointers are
 * never fabricated on the XIOM side.
 *
 * Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
 * SPDX-License-Identifier: MIT OR Apache-2.0
 */

#include <stdint.h>
#include <stddef.h>
#include <string.h>

#define _WINDOWS 1

/* Host surface first: it defines FFX_CPU / FFX_API / the SDK version. */
#include "../vendor/fidelityfx/api/include/ffx_api.h"
#include "../vendor/fidelityfx/api/include/ffx_api_loader.h"
#include "../vendor/fidelityfx/upscalers/include/ffx_upscale.h"
#include "../vendor/fidelityfx/upscalers/fsr3/include/ffx_fsr2.h"
#include "../vendor/fidelityfx/upscalers/fsr3/include/ffx_fsr3upscaler.h"
#include "../vendor/fidelityfx/upscalers/fsr3/include/ffx_spd.h"
#include "../vendor/fidelityfx/framegeneration/include/ffx_framegeneration.h"
#include "../vendor/fidelityfx/framegeneration/include/ffx_framegeneration_api_types.h"
#include "../vendor/fidelityfx/framegeneration/fsr3/include/ffx_frameinterpolation.h"
#include "../vendor/fidelityfx/framegeneration/fsr3/include/ffx_opticalflow.h"

/* CPU compile of the GPU headers: constant/config setup helpers only. */
#include "../vendor/fidelityfx/api/internal/gpu/ffx_core.h"
#include "../vendor/fidelityfx/upscalers/fsr3/include/gpu/fsr1/ffx_fsr1.h"
#include "../vendor/fidelityfx/upscalers/fsr3/include/gpu/spd/ffx_spd.h"

/* ---- vendored compiled shader blobs (MIT-listed; vendored as-is) ---------
 * Each header defines `const unsigned char g_mainPS[]` or `g_mainVS[]`, so the
 * symbols are renamed per include to keep them distinct in one TU. */

#define g_mainPS g_ffxB_swapchain_debug_pacing_ps
#include "../vendor/fidelityfx/framegeneration/fsr3/dx12/FrameInterpolationSwapchainDebugPacingPS.h"
#undef g_mainPS

#define g_mainVS g_ffxB_swapchain_debug_pacing_vs
#include "../vendor/fidelityfx/framegeneration/fsr3/dx12/FrameInterpolationSwapchainDebugPacingVS.h"
#undef g_mainVS

#define g_mainPS g_ffxB_swapchain_ui_composition_ps
#include "../vendor/fidelityfx/framegeneration/fsr3/dx12/FrameInterpolationSwapchainUiCompositionPS.h"
#undef g_mainPS

#define g_mainVS g_ffxB_swapchain_ui_composition_vs
#include "../vendor/fidelityfx/framegeneration/fsr3/dx12/FrameInterpolationSwapchainUiCompositionVS.h"
#undef g_mainVS

#define g_mainPS g_ffxB_swapchain_ui_composition_premul_ps
#include "../vendor/fidelityfx/framegeneration/fsr3/dx12/FrameInterpolationSwapchainUiCompositionPremulPS.h"
#undef g_mainPS

#define g_mainVS g_ffxB_swapchain_ui_composition_premul_vs
#include "../vendor/fidelityfx/framegeneration/fsr3/dx12/FrameInterpolationSwapchainUiCompositionPremulVS.h"
#undef g_mainVS

extern "C" {

/* ---- typed bridge errors (mirrored in the XIOM root module) ---- */
#define FFXB_OK         0
#define FFXB_ERR_NULL  -1
#define FFXB_ERR_RANGE -2
#define FFXB_ERR_ARG   -3

int32_t ffx_bridge_sdk_version(void)
{
    return (FFX_SDK_VERSION_MAJOR << 16) | (FFX_SDK_VERSION_MINOR << 8) | FFX_SDK_VERSION_PATCH;
}

/* 0 fsr2 / 1 fsr3upscaler / 2 frameinterpolation / 3 spd / 4 upscaler-api /
 * 5 framegeneration-api; -1 unknown. Packed major<<16 | minor<<8 | patch. */
int32_t ffx_bridge_effect_version(int32_t id)
{
    switch (id) {
    case 0: return (FFX_FSR2_VERSION_MAJOR << 16) | (FFX_FSR2_VERSION_MINOR << 8) | FFX_FSR2_VERSION_PATCH;
    case 1: return (FFX_FSR3UPSCALER_VERSION_MAJOR << 16) | (FFX_FSR3UPSCALER_VERSION_MINOR << 8) | FFX_FSR3UPSCALER_VERSION_PATCH;
    case 2: return (FFX_FRAMEINTERPOLATION_VERSION_MAJOR << 16) | (FFX_FRAMEINTERPOLATION_VERSION_MINOR << 8) | FFX_FRAMEINTERPOLATION_VERSION_PATCH;
    case 3: return (FFX_SPD_VERSION_MAJOR << 16) | (FFX_SPD_VERSION_MINOR << 8) | FFX_SPD_VERSION_PATCH;
    case 4: return (int32_t)FFX_UPSCALER_VERSION;
    case 5: return (int32_t)FFX_FRAMEGENERATION_VERSION;
    default: return -1;
    }
}

int32_t ffx_bridge_functions_size(void)
{
    return (int32_t)sizeof(ffxFunctions);
}

/* Binds the SDK's own loader helper: fills the ffxFunctions table (5
 * pointers) into the caller-owned `out_slot`. Returns a bitmask of the
 * pointers that resolved (bit0 CreateContext .. bit4 Dispatch); 0 when the
 * module exposes none. */
int32_t ffx_bridge_load_functions(int64_t out_slot, int64_t module)
{
    if (out_slot == 0) { return FFXB_ERR_NULL; }
    ffxFunctions* fns = (ffxFunctions*)(intptr_t)out_slot;
    memset(fns, 0, sizeof(ffxFunctions));
    ffxLoadFunctions(fns, (void*)(intptr_t)module);
    int32_t mask = 0;
    if (fns->CreateContext)  { mask |= 1 << 0; }
    if (fns->DestroyContext) { mask |= 1 << 1; }
    if (fns->Configure)      { mask |= 1 << 2; }
    if (fns->Query)          { mask |= 1 << 3; }
    if (fns->Dispatch)       { mask |= 1 << 4; }
    return mask;
}

const char* ffx_bridge_return_code_name(int32_t code)
{
    switch (code) {
    case FFX_API_RETURN_OK: return "FFX_API_RETURN_OK";
    case FFX_API_RETURN_ERROR: return "FFX_API_RETURN_ERROR";
    case FFX_API_RETURN_ERROR_UNKNOWN_DESCTYPE: return "FFX_API_RETURN_ERROR_UNKNOWN_DESCTYPE";
    case FFX_API_RETURN_ERROR_RUNTIME_ERROR: return "FFX_API_RETURN_ERROR_RUNTIME_ERROR";
    case FFX_API_RETURN_NO_PROVIDER: return "FFX_API_RETURN_NO_PROVIDER";
    case FFX_API_RETURN_ERROR_MEMORY: return "FFX_API_RETURN_ERROR_MEMORY";
    case FFX_API_RETURN_ERROR_PARAMETER: return "FFX_API_RETURN_ERROR_PARAMETER";
    case FFX_API_RETURN_PROVIDER_NO_SUPPORT_NEW_DESCTYPE: return "FFX_API_RETURN_PROVIDER_NO_SUPPORT_NEW_DESCTYPE";
    default: return "FFX_API_RETURN_UNKNOWN";
    }
}

const char* ffx_bridge_bridge_error_name(int32_t code)
{
    switch (code) {
    case FFXB_OK: return "OK";
    case FFXB_ERR_NULL: return "NULL_ARGUMENT";
    case FFXB_ERR_RANGE: return "OUT_OF_RANGE";
    case FFXB_ERR_ARG: return "BAD_ARGUMENT";
    default: return "BRIDGE_UNKNOWN";
    }
}

/* ---- FSR1 (EASU/RCAS) CPU constant setup --------------------------------
 * ffxFsrPopulateEasuConstants / ffxFsrPopulateEasuConstantsOffset /
 * FsrRcasCon from the pinned gpu/fsr1/ffx_fsr1.h, called on the CPU path.
 * Every con is 4 x uint32_t written into a caller-owned 16-byte slot. */

static int32_t ffxb_fsr1_validate_dims(float a, float b, float c, float d)
{
    if (!(a > 0.0f) || !(b > 0.0f) || !(c > 0.0f) || !(d > 0.0f)) { return FFXB_ERR_RANGE; }
    return FFXB_OK;
}

/* `out64` is a caller-owned 64-byte slot: con0..con3 are written at +0/+16/
 * +32/+48. No pointer arithmetic happens on the XIOM side. */
int32_t ffx_bridge_fsr1_easu_constants(uint8_t* out64,
                                       float inputViewportX, float inputViewportY,
                                       float inputSizeX, float inputSizeY,
                                       float outputSizeX, float outputSizeY)
{
    if (!out64) { return FFXB_ERR_NULL; }
    int32_t v = ffxb_fsr1_validate_dims(inputViewportX, inputViewportY, inputSizeX, inputSizeY);
    if (v != FFXB_OK) { return v; }
    v = ffxb_fsr1_validate_dims(outputSizeX, outputSizeY, 1.0f, 1.0f);
    if (v != FFXB_OK) { return v; }
    uint32_t C0[4], C1[4], C2[4], C3[4];
    ffxFsrPopulateEasuConstants(C0, C1, C2, C3,
                                inputViewportX, inputViewportY,
                                inputSizeX, inputSizeY,
                                outputSizeX, outputSizeY);
    memcpy(out64 + 0, C0, 16); memcpy(out64 + 16, C1, 16);
    memcpy(out64 + 32, C2, 16); memcpy(out64 + 48, C3, 16);
    return FFXB_OK;
}

int32_t ffx_bridge_fsr1_easu_constants_offset(uint8_t* out64,
                                              float inputViewportX, float inputViewportY,
                                              float inputSizeX, float inputSizeY,
                                              float outputSizeX, float outputSizeY,
                                              float inputOffsetX, float inputOffsetY)
{
    if (!out64) { return FFXB_ERR_NULL; }
    int32_t v = ffxb_fsr1_validate_dims(inputViewportX, inputViewportY, inputSizeX, inputSizeY);
    if (v != FFXB_OK) { return v; }
    v = ffxb_fsr1_validate_dims(outputSizeX, outputSizeY, 1.0f, 1.0f);
    if (v != FFXB_OK) { return v; }
    uint32_t C0[4], C1[4], C2[4], C3[4];
    ffxFsrPopulateEasuConstantsOffset(C0, C1, C2, C3,
                                      inputViewportX, inputViewportY,
                                      inputSizeX, inputSizeY,
                                      outputSizeX, outputSizeY,
                                      inputOffsetX, inputOffsetY);
    memcpy(out64 + 0, C0, 16); memcpy(out64 + 16, C1, 16);
    memcpy(out64 + 32, C2, 16); memcpy(out64 + 48, C3, 16);
    return FFXB_OK;
}

int32_t ffx_bridge_fsr1_rcas_constants(uint8_t* con, float sharpness)
{
    if (!con) { return FFXB_ERR_NULL; }
    if (!(sharpness >= 0.0f) || sharpness > 2.0f) { return FFXB_ERR_RANGE; }
    uint32_t C[4];
    FsrRcasCon(C, sharpness);
    memcpy(con, C, 16);
    return FFXB_OK;
}

/* ---- SPD dispatch setup (CPU path of the pinned gpu/spd header) --------- */

/* `out24` is a caller-owned 24-byte slot: dispatchThreadGroupCountXY at +0,
 * workGroupOffset at +8, numWorkGroupsAndMips at +16. */
int32_t ffx_bridge_spd_setup(uint8_t* out24,
                             uint32_t left, uint32_t top, uint32_t width, uint32_t height,
                             int32_t mips)
{
    if (!out24) { return FFXB_ERR_NULL; }
    if (width == 0 || height == 0 || mips < -1) { return FFXB_ERR_RANGE; }
    uint32_t dtgv[2] = { 0, 0 };
    uint32_t wgov[2] = { 0, 0 };
    uint32_t nwmv[2] = { 0, 0 };
    uint32_t rect[4] = { left, top, width, height };
    if (mips < 0) {
        ffxSpdSetup(dtgv, wgov, nwmv, rect);
    } else {
        ffxSpdSetup(dtgv, wgov, nwmv, rect, (FfxInt32)mips);
    }
    memcpy(out24 + 0, dtgv, 8);
    memcpy(out24 + 8, wgov, 8);
    memcpy(out24 + 16, nwmv, 8);
    return FFXB_OK;
}

/* ---- vendored compiled shader blobs ------------------------------------- */

typedef struct FfxBlobEntry {
    const char* name;
    const char* kind;
    const char* file;
    const uint8_t* data;
    int64_t size;
} FfxBlobEntry;

static const FfxBlobEntry g_ffxB_blobs[] = {
    { "fsr3_swapchain_debug_pacing_ps", "ps",
      "FrameInterpolationSwapchainDebugPacingPS.h",
      g_ffxB_swapchain_debug_pacing_ps, (int64_t)sizeof(g_ffxB_swapchain_debug_pacing_ps) },
    { "fsr3_swapchain_debug_pacing_vs", "vs",
      "FrameInterpolationSwapchainDebugPacingVS.h",
      g_ffxB_swapchain_debug_pacing_vs, (int64_t)sizeof(g_ffxB_swapchain_debug_pacing_vs) },
    { "fsr3_swapchain_ui_composition_ps", "ps",
      "FrameInterpolationSwapchainUiCompositionPS.h",
      g_ffxB_swapchain_ui_composition_ps, (int64_t)sizeof(g_ffxB_swapchain_ui_composition_ps) },
    { "fsr3_swapchain_ui_composition_vs", "vs",
      "FrameInterpolationSwapchainUiCompositionVS.h",
      g_ffxB_swapchain_ui_composition_vs, (int64_t)sizeof(g_ffxB_swapchain_ui_composition_vs) },
    { "fsr3_swapchain_ui_composition_premul_ps", "ps",
      "FrameInterpolationSwapchainUiCompositionPremulPS.h",
      g_ffxB_swapchain_ui_composition_premul_ps, (int64_t)sizeof(g_ffxB_swapchain_ui_composition_premul_ps) },
    { "fsr3_swapchain_ui_composition_premul_vs", "vs",
      "FrameInterpolationSwapchainUiCompositionPremulVS.h",
      g_ffxB_swapchain_ui_composition_premul_vs, (int64_t)sizeof(g_ffxB_swapchain_ui_composition_premul_vs) },
};

#define FFXB_BLOB_COUNT ((int32_t)(sizeof(g_ffxB_blobs) / sizeof(g_ffxB_blobs[0])))

int32_t ffx_bridge_blob_count(void)
{
    return FFXB_BLOB_COUNT;
}

int64_t ffx_bridge_blob_size(int32_t i)
{
    if (i < 0 || i >= FFXB_BLOB_COUNT) { return -1; }
    return g_ffxB_blobs[i].size;
}

const char* ffx_bridge_blob_name(int32_t i)
{
    if (i < 0 || i >= FFXB_BLOB_COUNT) { return ""; }
    return g_ffxB_blobs[i].name;
}

const char* ffx_bridge_blob_kind(int32_t i)
{
    if (i < 0 || i >= FFXB_BLOB_COUNT) { return ""; }
    return g_ffxB_blobs[i].kind;
}

const char* ffx_bridge_blob_file(int32_t i)
{
    if (i < 0 || i >= FFXB_BLOB_COUNT) { return ""; }
    return g_ffxB_blobs[i].file;
}

/* Copy blob `i`'s payload into the caller-owned slot. Returns the payload
 * size, FFXB_ERR_NULL for a null slot, FFXB_ERR_ARG for a bad index,
 * FFXB_ERR_RANGE when cap < size (nothing copied). */
int32_t ffx_bridge_blob_read(int32_t i, uint8_t* out, int64_t cap)
{
    if (!out) { return FFXB_ERR_NULL; }
    if (i < 0 || i >= FFXB_BLOB_COUNT) { return FFXB_ERR_ARG; }
    if (cap < g_ffxB_blobs[i].size) { return FFXB_ERR_RANGE; }
    memcpy(out, g_ffxB_blobs[i].data, (size_t)g_ffxB_blobs[i].size);
    return (int32_t)g_ffxB_blobs[i].size;
}

} /* extern "C" */
