// XIOM -- xiom.fidelityfx golden-value maintenance aid.
//
// Prints the FSR1 EASU/RCAS constant values and the SPD dispatch-setup values
// produced by the vendored pinned headers on the CPU path, plus the SDK and
// component version probes. The conformance suite embeds the printed values
// as golden data; re-run this after a re-pin and update the suite.
//
//   clang++ -std=c++20 tools/gen_golden_values.cpp -o golden.exe && golden.exe
//
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#define _WINDOWS 1
#include "../vendor/fidelityfx/api/include/ffx_api.h"
#include "../vendor/fidelityfx/upscalers/include/ffx_upscale.h"
#include "../vendor/fidelityfx/upscalers/fsr3/include/ffx_fsr2.h"
#include "../vendor/fidelityfx/upscalers/fsr3/include/ffx_fsr3upscaler.h"
#include "../vendor/fidelityfx/upscalers/fsr3/include/ffx_spd.h"
#include "../vendor/fidelityfx/framegeneration/include/ffx_framegeneration.h"
#include "../vendor/fidelityfx/framegeneration/fsr3/include/ffx_frameinterpolation.h"
#include "../vendor/fidelityfx/api/internal/gpu/ffx_core.h"
#include "../vendor/fidelityfx/upscalers/fsr3/include/gpu/fsr1/ffx_fsr1.h"
#include "../vendor/fidelityfx/upscalers/fsr3/include/gpu/spd/ffx_spd.h"

static void dump(const char* what, const uint32_t* c, int n)
{
    printf("%s:", what);
    for (int i = 0; i < n; ++i) { printf(" 0x%08X", c[i]); }
    printf("\n");
}

int main()
{
    // FSR1 EASU constants: 2560x1440 viewport/input -> 3840x2160 output
    uint32_t c0[4], c1[4], c2[4], c3[4];
    ffxFsrPopulateEasuConstants(c0, c1, c2, c3,
        2560.0f, 1440.0f, 2560.0f, 1440.0f, 3840.0f, 2160.0f);
    dump("easu_c0", c0, 4); dump("easu_c1", c1, 4);
    dump("easu_c2", c2, 4); dump("easu_c3", c3, 4);

    ffxFsrPopulateEasuConstantsOffset(c0, c1, c2, c3,
        2560.0f, 1440.0f, 3840.0f, 2160.0f, 3840.0f, 2160.0f, 128.0f, 64.0f);
    dump("easuoff_c0", c0, 4);

    uint32_t con[4];
    FsrRcasCon(con, 0.0f);  dump("rcas_0", con, 4);
    FsrRcasCon(con, 2.0f);  dump("rcas_2", con, 4);

    // SPD setup
    uint32_t dtg[2], wgo[2], nwm[2], rect[4] = {0, 0, 2560, 1440};
    ffxSpdSetup(dtg, wgo, nwm, rect);
    printf("spd_2560x1440: dtg=(%u,%u) wgo=(%u,%u) nwm=(%u,%u)\n", dtg[0], dtg[1], wgo[0], wgo[1], nwm[0], nwm[1]);
    uint32_t rect2[4] = {128, 64, 2560, 1440};
    ffxSpdSetup(dtg, wgo, nwm, rect2);
    printf("spd_off: dtg=(%u,%u) wgo=(%u,%u) nwm=(%u,%u)\n", dtg[0], dtg[1], wgo[0], wgo[1], nwm[0], nwm[1]);
    ffxSpdSetup(dtg, wgo, nwm, rect, 4);
    printf("spd_mips4: nwm=(%u,%u)\n", nwm[0], nwm[1]);

    printf("versions: sdk=%d fsr2=%d fsr3upscaler=%d fi=%d spd=%d upscale_api=%u fg_api=%u\n",
        (FFX_SDK_VERSION_MAJOR << 16) | (FFX_SDK_VERSION_MINOR << 8) | FFX_SDK_VERSION_PATCH,
        (FFX_FSR2_VERSION_MAJOR << 16) | (FFX_FSR2_VERSION_MINOR << 8) | FFX_FSR2_VERSION_PATCH,
        (FFX_FSR3UPSCALER_VERSION_MAJOR << 16) | (FFX_FSR3UPSCALER_VERSION_MINOR << 8) | FFX_FSR3UPSCALER_VERSION_PATCH,
        (FFX_FRAMEINTERPOLATION_VERSION_MAJOR << 16) | (FFX_FRAMEINTERPOLATION_VERSION_MINOR << 8) | FFX_FRAMEINTERPOLATION_VERSION_PATCH,
        (FFX_SPD_VERSION_MAJOR << 16) | (FFX_SPD_VERSION_MINOR << 8) | FFX_SPD_VERSION_PATCH,
        (unsigned)FFX_UPSCALER_VERSION, (unsigned)FFX_FRAMEGENERATION_VERSION);
    printf("fsr2ctx=%zu\n", sizeof(FfxFsr2Context));
    return 0;
}
