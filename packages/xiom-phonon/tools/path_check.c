// XIOM -- xiom.phonon tools/path_check.c
//
// C ground-truth harness for the present-path DSP flows the XIOM suite
// exercises. Compiled against the pinned public phonon.h and linked to the
// same phonon.dll at runtime (or used as a source-level oracle when no C
// toolchain is available on the box). Not part of the package surface.
//
// Build+run:
//   clang -I <sdk>/unity/include/phonon tools/path_check.c -o path_check.exe
//   path_check.exe <path-to-phonon.dll>
//
// Prints one line per flow: binaural / amb-encode / amb-decode / panning /
// direct / path(spatialize) / path(nospatial) with the output energy.

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <windows.h>
#include "phonon.h"

typedef IPLerror(IPLCALL *fn_context_create)(IPLContextSettings*, IPLContext*);
typedef IPLAudioEffectState(IPLCALL *fn_binaural_apply)(IPLBinauralEffect, IPLBinauralEffectParams*, IPLAudioBuffer*, IPLAudioBuffer*);
typedef IPLerror(IPLCALL *fn_binaural_create)(IPLContext, IPLAudioSettings*, IPLBinauralEffectSettings*, IPLBinauralEffect*);
typedef IPLerror(IPLCALL *fn_hrtf_create)(IPLContext, IPLAudioSettings*, IPLHRTFSettings*, IPLHRTF*);
typedef IPLerror(IPLCALL *fn_ab_alloc)(IPLContext, IPLint32, IPLint32, IPLAudioBuffer*);
typedef void(IPLCALL *fn_ab_free)(IPLContext, IPLAudioBuffer*);
typedef void(IPLCALL *fn_ab_interleave)(IPLContext, IPLAudioBuffer*, IPLfloat32*);
typedef void(IPLCALL *fn_ab_deinterleave)(IPLContext, IPLfloat32*, IPLAudioBuffer*);
typedef IPLerror(IPLCALL *fn_ee_create)(IPLContext, IPLAudioSettings*, IPLAmbisonicsEncodeEffectSettings*, IPLAmbisonicsEncodeEffect*);
typedef IPLAudioEffectState(IPLCALL *fn_ee_apply)(IPLAmbisonicsEncodeEffect, IPLAmbisonicsEncodeEffectParams*, IPLAudioBuffer*, IPLAudioBuffer*);
typedef IPLerror(IPLCALL *fn_ed_create)(IPLContext, IPLAudioSettings*, IPLAmbisonicsDecodeEffectSettings*, IPLAmbisonicsDecodeEffect*);
typedef IPLAudioEffectState(IPLCALL *fn_ed_apply)(IPLAmbisonicsDecodeEffect, IPLAmbisonicsDecodeEffectParams*, IPLAudioBuffer*, IPLAudioBuffer*);
typedef IPLerror(IPLCALL *fn_pn_create)(IPLContext, IPLAudioSettings*, IPLPanningEffectSettings*, IPLPanningEffect*);
typedef IPLAudioEffectState(IPLCALL *fn_pn_apply)(IPLPanningEffect, IPLPanningEffectParams*, IPLAudioBuffer*, IPLAudioBuffer*);
typedef IPLerror(IPLCALL *fn_de_create)(IPLContext, IPLAudioSettings*, IPLDirectEffectSettings*, IPLDirectEffect*);
typedef IPLAudioEffectState(IPLCALL *fn_de_apply)(IPLDirectEffect, IPLDirectEffectParams*, IPLAudioBuffer*, IPLAudioBuffer*);
typedef IPLerror(IPLCALL *fn_pe_create)(IPLContext, IPLAudioSettings*, IPLPathEffectSettings*, IPLPathEffect*);
typedef IPLAudioEffectState(IPLCALL *fn_pe_apply)(IPLPathEffect, IPLPathEffectParams*, IPLAudioBuffer*, IPLAudioBuffer*);

static double energy(const IPLfloat32* v, int n) {
    double s = 0.0;
    for (int i = 0; i < n; ++i) s += (double)v[i] * (double)v[i];
    return s;
}

int main(int argc, char** argv) {
    if (argc < 2) { fprintf(stderr, "usage: path_check <phonon.dll>\n"); return 2; }
    HMODULE lib = LoadLibraryA(argv[1]);
    if (!lib) { fprintf(stderr, "load failed (%lu)\n", GetLastError()); return 2; }
#define SYM(fnvar, symname) fnvar = (void*)GetProcAddress(lib, "ipl" #symname); if (!fnvar) { fprintf(stderr, "missing " #symname "\n"); return 2; }
    fn_context_create fn_context_create = NULL;
    fn_hrtf_create fn_hrtf_create = NULL;
    fn_ab_alloc fn_ab_alloc = NULL;
    fn_ab_free fn_ab_free = NULL;
    fn_ab_interleave fn_ab_interleave = NULL;
    fn_ab_deinterleave fn_ab_deinterleave = NULL;
    fn_binaural_create fn_binaural_create = NULL;
    fn_binaural_apply fn_binaural_apply = NULL;
    fn_ee_create fn_ee_create = NULL;
    fn_ee_apply fn_ee_apply = NULL;
    fn_ed_create fn_ed_create = NULL;
    fn_ed_apply fn_ed_apply = NULL;
    fn_pn_create fn_pn_create = NULL;
    fn_pn_apply fn_pn_apply = NULL;
    fn_de_create fn_de_create = NULL;
    fn_de_apply fn_de_apply = NULL;
    fn_pe_create fn_pe_create = NULL;
    fn_pe_apply fn_pe_apply = NULL;
    SYM(fn_context_create, ContextCreate);
    SYM(fn_hrtf_create, HRTFCreate);
    SYM(fn_ab_alloc, AudioBufferAllocate);
    SYM(fn_ab_free, AudioBufferFree);
    SYM(fn_ab_interleave, AudioBufferInterleave);
    SYM(fn_ab_deinterleave, AudioBufferDeinterleave);
    SYM(fn_binaural_create, BinauralEffectCreate);
    SYM(fn_binaural_apply, BinauralEffectApply);
    SYM(fn_ee_create, AmbisonicsEncodeEffectCreate);
    SYM(fn_ee_apply, AmbisonicsEncodeEffectApply);
    SYM(fn_ed_create, AmbisonicsDecodeEffectCreate);
    SYM(fn_ed_apply, AmbisonicsDecodeEffectApply);
    SYM(fn_pn_create, PanningEffectCreate);
    SYM(fn_pn_apply, PanningEffectApply);
    SYM(fn_de_create, DirectEffectCreate);
    SYM(fn_de_apply, DirectEffectApply);
    SYM(fn_pe_create, PathEffectCreate);
    SYM(fn_pe_apply, PathEffectApply);

    IPLContextSettings cs = {0};
    cs.version = STEAMAUDIO_VERSION;
    cs.simdLevel = IPL_SIMDLEVEL_SSE2;
    IPLContext ctx = NULL;
    if (fn_context_create(&cs, &ctx) != IPL_STATUS_SUCCESS) { fprintf(stderr, "ctx failed\n"); return 2; }

    IPLAudioSettings as = { 48000, 256 };
    IPLHRTFSettings hs = {0};
    hs.type = IPL_HRTFTYPE_DEFAULT;
    hs.volume = 1.0f;
    hs.normType = IPL_HRTFNORMTYPE_NONE;
    IPLHRTF hrtf = NULL;
    if (fn_hrtf_create(ctx, &as, &hs, &hrtf) != IPL_STATUS_SUCCESS) { fprintf(stderr, "hrtf failed\n"); return 2; }

    IPLAudioBuffer in; memset(&in, 0, sizeof(in));
    IPLAudioBuffer out2; memset(&out2, 0, sizeof(out2));
    IPLAudioBuffer out4; memset(&out4, 0, sizeof(out4));
    fn_ab_alloc(ctx, 1, 256, &in);
    fn_ab_alloc(ctx, 2, 256, &out2);
    fn_ab_alloc(ctx, 4, 256, &out4);

    IPLfloat32 mono[256]; memset(mono, 0, sizeof(mono)); mono[0] = 1.0f;
    fn_ab_deinterleave(ctx, mono, &in);

    IPLfloat32 acc[1024];
    IPLVector3 dir = { 1.0f, 0.0f, 0.0f };

    // binaural
    IPLBinauralEffectSettings bs = { hrtf };
    IPLBinauralEffect be = NULL;
    printf("binaural create=%d\n", fn_binaural_create(ctx, &as, &bs, &be));
    IPLBinauralEffectParams bp = {0};
    bp.direction = dir;
    bp.interpolation = IPL_HRTFINTERPOLATION_NEAREST;
    bp.spatialBlend = 1.0f;
    bp.hrtf = hrtf;
    printf("binaural apply=%d\n", fn_binaural_apply(be, &bp, &in, &out2));
    memset(acc, 0, sizeof(acc));
    fn_ab_interleave(ctx, &out2, acc);
    printf("binaural energy=%.9g first=%.9g\n", energy(acc, 512), (double)acc[0]);

    // amb encode
    IPLAmbisonicsEncodeEffectSettings ees = { 1 };
    IPLAmbisonicsEncodeEffect ee = NULL;
    printf("amb-encode create=%d\n", fn_ee_create(ctx, &as, &ees, &ee));
    IPLAmbisonicsEncodeEffectParams eep = {0};
    eep.direction = dir;
    eep.order = 1;
    printf("amb-encode apply=%d\n", fn_ee_apply(ee, &eep, &in, &out4));
    fn_ab_interleave(ctx, &out4, acc);
    printf("amb-encode energy=%.9g first=%.9g\n", energy(acc, 1024), (double)acc[0]);

    // amb decode binaural
    IPLAmbisonicsDecodeEffectSettings eds = {0};
    eds.speakerLayout.type = IPL_SPEAKERLAYOUTTYPE_STEREO;
    eds.hrtf = hrtf;
    eds.maxOrder = 1;
    IPLAmbisonicsDecodeEffect ed = NULL;
    printf("amb-decode create=%d\n", fn_ed_create(ctx, &as, &eds, &ed));
    IPLAmbisonicsDecodeEffectParams edp = {0};
    edp.order = 1;
    edp.hrtf = hrtf;
    edp.orientation.right = (IPLVector3){1,0,0};
    edp.orientation.up = (IPLVector3){0,1,0};
    edp.orientation.ahead = (IPLVector3){0,0,-1};
    edp.binaural = IPL_TRUE;
    printf("amb-decode apply=%d\n", fn_ed_apply(ed, &edp, &out4, &out2));
    fn_ab_interleave(ctx, &out2, acc);
    printf("amb-decode energy=%.9g first=%.9g\n", energy(acc, 512), (double)acc[0]);

    // panning
    IPLPanningEffectSettings ps = {0};
    ps.speakerLayout.type = IPL_SPEAKERLAYOUTTYPE_STEREO;
    IPLPanningEffect pe = NULL;
    printf("panning create=%d\n", fn_pn_create(ctx, &as, &ps, &pe));
    IPLPanningEffectParams pp = { dir };
    printf("panning apply=%d\n", fn_pn_apply(pe, &pp, &in, &out2));
    fn_ab_interleave(ctx, &out2, acc);
    printf("panning energy=%.9g first=%.9g\n", energy(acc, 512), (double)acc[0]);

    // direct (in place)
    IPLDirectEffectSettings des = { 1 };
    IPLDirectEffect de = NULL;
    printf("direct create=%d\n", fn_de_create(ctx, &as, &des, &de));
    IPLAudioBuffer din; memset(&din, 0, sizeof(din));
    fn_ab_alloc(ctx, 1, 256, &din);
    fn_ab_deinterleave(ctx, mono, &din);
    IPLDirectEffectParams dep = {0};
    dep.flags = IPL_DIRECTEFFECTFLAGS_APPLYDISTANCEATTENUATION;
    dep.distanceAttenuation = 0.5f;
    dep.airAbsorption[0] = dep.airAbsorption[1] = dep.airAbsorption[2] = 1.0f;
    dep.directivity = 1.0f;
    dep.occlusion = 1.0f;
    dep.transmission[0] = dep.transmission[1] = dep.transmission[2] = 1.0f;
    printf("direct apply=%d\n", fn_de_apply(de, &dep, &din, &din));
    {
        IPLfloat32 dacc[256]; memset(dacc, 0, sizeof(dacc));
        fn_ab_interleave(ctx, &din, dacc);
        printf("direct energy=%.9g first=%.9g\n", energy(dacc, 256), (double)dacc[0]);
    }

    // path effect: spatialize + stereo panning
    IPLPathEffectSettings pes = {0};
    pes.maxOrder = 1;
    pes.spatialize = IPL_TRUE;
    pes.speakerLayout.type = IPL_SPEAKERLAYOUTTYPE_STEREO;
    pes.hrtf = hrtf;
    IPLPathEffect pa = NULL;
    printf("path create=%d\n", fn_pe_create(ctx, &as, &pes, &pa));
    IPLfloat32 sh[4] = { 1.0f, 0.5f, 0.25f, 0.125f };
    IPLPathEffectParams pap = {0};
    pap.eqCoeffs[0] = pap.eqCoeffs[1] = pap.eqCoeffs[2] = 1.0f;
    pap.shCoeffs = sh;
    pap.order = 1;
    pap.binaural = IPL_FALSE;
    pap.hrtf = hrtf;
    pap.listener.right = (IPLVector3){1,0,0};
    pap.listener.up = (IPLVector3){0,1,0};
    pap.listener.ahead = (IPLVector3){0,0,-1};
    pap.normalizeEQ = IPL_FALSE;
    printf("path apply=%d\n", fn_pe_apply(pa, &pap, &in, &out2));
    fn_ab_interleave(ctx, &out2, acc);
    printf("path energy=%.9g first=%.9g\n", energy(acc, 512), (double)acc[0]);

    // path effect: ambisonic (nospatial)
    IPLPathEffectSettings pes2 = {0};
    pes2.maxOrder = 1;
    pes2.spatialize = IPL_FALSE;
    IPLPathEffect pa2 = NULL;
    printf("path-nospatial create=%d\n", fn_pe_create(ctx, &as, &pes2, &pa2));
    printf("path-nospatial apply=%d\n", fn_pe_apply(pa2, &pap, &in, &out4));
    fn_ab_interleave(ctx, &out4, acc);
    printf("path-nospatial energy=%.9g first=%.9g\n", energy(acc, 1024), (double)acc[0]);

    return 0;
}
