/* XIOM -- xiom.opensl: OpenSL ES + OpenMAX AL + AMidi runtime bridge.
 * Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
 * Licensed under the MIT or Apache-2.0 license, at your option.
 *
 * DESIGN: runtime loader/probe for the A6 legacy-audio tail of the
 * Android SDK100 program (docs/ANDROID-SDK100.md).  No link-time
 * dependency, no NDK headers needed to compile (all pinned ABI facts
 * below are self-declared from NDK r27b 27.1.12297006).  On Windows the
 * three libraries classify ABSENT (SKIP) via LoadLibraryA; on
 * Android/Linux they load via dlopen, the declared export sets are
 * verified (ABI stage) and the flat entry points are exercised:
 *
 *   libOpenSLES.so  -- slCreateEngine + slQueryNumSupportedEngineInterfaces
 *                      + slQuerySupportedEngineInterfaces (3 flat exports)
 *                      + the 53 SL_IID_* interface-ID GLOBALS (44 from
 *                      OpenSLES.h + 9 Android extensions).
 *   libOpenMAXAL.so -- xaCreateEngine + xaQueryNumSupportedEngineInterfaces
 *                      + xaQuerySupportedEngineInterfaces + the 41
 *                      XA_IID_* globals.
 *   libamidi.so     -- the 14 AMidi* functions of amidi/AMidi.h.
 *
 * SLES interface-table model (see SPEC.md): the flat surface is only the
 * entry trio.  Everything else is object/interface-based: the SL_IID_*
 * symbols are runtime GUIDs (addresses of 128-bit interface IDs); an
 * SLObjectItf is a handle to a vtable whose Realize/GetState/Destroy
 * slots are called THROUGH THE HANDLE.  All such calls stay inside this
 * C file -- pointers never cross the boundary (B-25 discipline); the
 * module sees only Int statuses.
 *
 * Contract (flat extern "C", called from module xiom.opensl):
 *   int         xo_load_named(const char* sl, const char* xa, const char* amidi)
 *                                                    0=ok 1=absent 2=abi
 *   int         xo_load(void)      "libOpenSLES.so"/"libOpenMAXAL.so"/"libamidi.so"
 *   const char* xo_error(void)     last error / missing summary
 *   int         xo_loaded_mask(void)         bit0 SL  bit1 XA  bit2 AMidi
 *   int         xo_sl_missing_count(void)    unresolved OpenSLES exports
 *   const char* xo_sl_missing(void)          comma-joined names
 *   int         xo_xa_missing_count(void)    unresolved OpenMAXAL exports
 *   const char* xo_xa_missing(void)          comma-joined names
 *   int         xo_amidi_missing_count(void) unresolved AMidi exports
 *   const char* xo_amidi_missing(void)       comma-joined names
 *   int         xo_sl_iid_null_values(void)  SL_IID_* globals holding NULL
 *   int         xo_sl_engine_lifecycle(void) 0=ok; -1 unresolved; -2 create;
 *                                            -3 realize; -4 state
 *                                            (Destroy always runs on the
 *                                             realized/created handle)
 *   int         xo_sl_engine_last_state(void)  last GetState value (0=none)
 *   int         xo_sl_query_num_engine_interfaces(void)  count; -1/-2 failed
 *   int         xo_sl_query_engine_interfaces_ok(void)   non-null IID count
 *   int         xo_amidi_get_device_info_present(void)   1/0
 *   int         xo_amidi_device_count_attempt(void)      -1 = API absent
 *                                            (recorded outcome); -2 = present
 *                                            but ABI unverified; >=0 count
 *   void        xo_unload(void)
 *
 * Classification (the suite maps it to markers):
 *   XO_LOAD_ABSENT (1) -> SKIP  (all three runtimes absent; CI stays green)
 *   XO_LOAD_ABI    (2) -> FAIL  (partial load / exports broken; never silent)
 */

#include <stdint.h>
#include <stdio.h>
#include <string.h>

#if defined(_WIN32)
#include <windows.h>
typedef HMODULE xo_lib_t;
static xo_lib_t xo_dlopen(const char* name) { return LoadLibraryA(name); }
static void* xo_dlsym(xo_lib_t h, const char* name) {
    return h ? (void*)GetProcAddress(h, name) : 0;
}
static void xo_dlclose(xo_lib_t h) { if (h) FreeLibrary(h); }
#else
#include <dlfcn.h>
typedef void* xo_lib_t;
static xo_lib_t xo_dlopen(const char* name) { return dlopen(name, RTLD_NOW | RTLD_LOCAL); }
static void* xo_dlsym(xo_lib_t h, const char* name) { return h ? dlsym(h, name) : 0; }
static void xo_dlclose(xo_lib_t h) { if (h) dlclose(h); }
#endif

/* -- pinned ABI facts (NDK r27b SLES/OpenSLES.h, OMXAL/OpenMAXAL.h) ------
 * SLresult/SLboolean/SLuint32 are 32-bit; SLObjectItf is a handle to a
 * const vtable pointer; the SLObjectItf_ vtable slots used here are
 * Realize=0, GetState=2, Destroy=6 (declaration order in OpenSLES.h). */
#define XO_SL_RESULT_SUCCESS 0u
#define XO_SL_BOOLEAN_FALSE 0u
#define XO_SL_OBJECT_STATE_REALIZED 2u

struct XO_SLObjectVtbl;
typedef const struct XO_SLObjectVtbl* const* XO_SLObjectItf;

typedef struct XO_SLObjectVtbl {
    uint32_t (*Realize)(XO_SLObjectItf self, uint32_t async);
    uint32_t (*Resume)(XO_SLObjectItf self, uint32_t async);
    uint32_t (*GetState)(XO_SLObjectItf self, uint32_t* pState);
    uint32_t (*GetInterface)(XO_SLObjectItf self, const void* iid, void** pInterface);
    uint32_t (*RegisterCallback)(XO_SLObjectItf self, void* cb, void* ctx);
    void (*AbortAsyncOperation)(XO_SLObjectItf self);
    void (*Destroy)(XO_SLObjectItf self);
    uint32_t (*SetPriority)(XO_SLObjectItf self, int32_t priority, uint32_t preemptable);
    uint32_t (*GetPriority)(XO_SLObjectItf self, int32_t* pPriority, uint32_t* pPreemptable);
    uint32_t (*SetLossOfControlInterfaces)(XO_SLObjectItf self, int16_t num, void** iids, uint32_t enabled);
} XO_SLObjectVtbl;

typedef uint32_t (*PFN_slCreateEngine)(XO_SLObjectItf* pEngine, uint32_t numOptions,
                                       const void* pOptions, uint32_t numInterfaces,
                                       const void* pInterfaceIds, const void* pInterfaceRequired);
typedef uint32_t (*PFN_slQueryNumSupportedEngineInterfaces)(uint32_t* pNum);
typedef uint32_t (*PFN_slQuerySupportedEngineInterfaces)(uint32_t index, const void** pInterfaceId);

/* -- bridge state -------------------------------------------------------- */

static xo_lib_t g_sl = 0;
static xo_lib_t g_xa = 0;
static xo_lib_t g_amidi = 0;
static char g_error[1024] = {0};
static char g_missing_sl[1024] = {0};
static char g_missing_xa[1024] = {0};
static char g_missing_amidi[1024] = {0};
static int g_missing_sl_count = 0;
static int g_missing_xa_count = 0;
static int g_missing_amidi_count = 0;
static int g_sl_last_state = 0;

static PFN_slCreateEngine p_sl_create_engine = 0;
static PFN_slQueryNumSupportedEngineInterfaces p_sl_query_num = 0;
static PFN_slQuerySupportedEngineInterfaces p_sl_query_iid = 0;

void xo_unload(void); /* defined at the bottom; used by xo_load_triple */

static void xo_set_error(const char* msg) {
    snprintf(g_error, sizeof(g_error), "%s", msg);
}

/* Declared OpenSLES export set: the 3 flat exports + the 53 SL_IID_*
 * interface-ID globals (44 base + 9 Android extensions). */
static const char* k_sl_export_set[] = {
    "slCreateEngine",
    "slQueryNumSupportedEngineInterfaces",
    "slQuerySupportedEngineInterfaces",
    "SL_IID_NULL",
    "SL_IID_OBJECT",
    "SL_IID_AUDIOIODEVICECAPABILITIES",
    "SL_IID_LED",
    "SL_IID_VIBRA",
    "SL_IID_METADATAEXTRACTION",
    "SL_IID_METADATATRAVERSAL",
    "SL_IID_DYNAMICSOURCE",
    "SL_IID_OUTPUTMIX",
    "SL_IID_PLAY",
    "SL_IID_PREFETCHSTATUS",
    "SL_IID_PLAYBACKRATE",
    "SL_IID_SEEK",
    "SL_IID_RECORD",
    "SL_IID_EQUALIZER",
    "SL_IID_VOLUME",
    "SL_IID_DEVICEVOLUME",
    "SL_IID_BUFFERQUEUE",
    "SL_IID_PRESETREVERB",
    "SL_IID_ENVIRONMENTALREVERB",
    "SL_IID_EFFECTSEND",
    "SL_IID_3DGROUPING",
    "SL_IID_3DCOMMIT",
    "SL_IID_3DLOCATION",
    "SL_IID_3DDOPPLER",
    "SL_IID_3DSOURCE",
    "SL_IID_3DMACROSCOPIC",
    "SL_IID_MUTESOLO",
    "SL_IID_DYNAMICINTERFACEMANAGEMENT",
    "SL_IID_MIDIMESSAGE",
    "SL_IID_MIDIMUTESOLO",
    "SL_IID_MIDITEMPO",
    "SL_IID_MIDITIME",
    "SL_IID_AUDIODECODERCAPABILITIES",
    "SL_IID_AUDIOENCODERCAPABILITIES",
    "SL_IID_AUDIOENCODER",
    "SL_IID_BASSBOOST",
    "SL_IID_PITCH",
    "SL_IID_RATEPITCH",
    "SL_IID_VIRTUALIZER",
    "SL_IID_VISUALIZATION",
    "SL_IID_ENGINE",
    "SL_IID_ENGINECAPABILITIES",
    "SL_IID_THREADSYNC",
    /* OpenSLES_Android.h (9) */
    "SL_IID_ANDROIDEFFECT",
    "SL_IID_ANDROIDEFFECTSEND",
    "SL_IID_ANDROIDEFFECTCAPABILITIES",
    "SL_IID_ANDROIDCONFIGURATION",
    "SL_IID_ANDROIDSIMPLEBUFFERQUEUE",
    "SL_IID_ANDROIDBUFFERQUEUESOURCE",
    "SL_IID_ANDROIDACOUSTICECHOCANCELLATION",
    "SL_IID_ANDROIDAUTOMATICGAINCONTROL",
    "SL_IID_ANDROIDNOISESUPPRESSION",
};
#define XO_SL_EXPORT_COUNT (sizeof(k_sl_export_set) / sizeof(k_sl_export_set[0]))

/* Declared OpenMAXAL export set: 3 flat exports + 41 XA_IID_* globals. */
static const char* k_xa_export_set[] = {
    "xaCreateEngine",
    "xaQueryNumSupportedEngineInterfaces",
    "xaQuerySupportedEngineInterfaces",
    "XA_IID_NULL",
    "XA_IID_OBJECT",
    "XA_IID_AUDIOIODEVICECAPABILITIES",
    "XA_IID_LED",
    "XA_IID_VIBRA",
    "XA_IID_METADATAEXTRACTION",
    "XA_IID_METADATAINSERTION",
    "XA_IID_METADATATRAVERSAL",
    "XA_IID_DYNAMICSOURCE",
    "XA_IID_ENGINE",
    "XA_IID_OUTPUTMIX",
    "XA_IID_PLAY",
    "XA_IID_PREFETCHSTATUS",
    "XA_IID_PLAYBACKRATE",
    "XA_IID_SEEK",
    "XA_IID_RECORD",
    "XA_IID_EQUALIZER",
    "XA_IID_VOLUME",
    "XA_IID_DEVICEVOLUME",
    "XA_IID_DYNAMICINTERFACEMANAGEMENT",
    "XA_IID_CAMERA",
    "XA_IID_CAMERACAPABILITIES",
    "XA_IID_IMAGECONTROLS",
    "XA_IID_IMAGEDECODERCAPABILITIES",
    "XA_IID_IMAGEEFFECTS",
    "XA_IID_IMAGEENCODER",
    "XA_IID_IMAGEENCODERCAPABILITIES",
    "XA_IID_CONFIGEXTENSION",
    "XA_IID_SNAPSHOT",
    "XA_IID_RADIO",
    "XA_IID_RDS",
    "XA_IID_STREAMINFORMATION",
    "XA_IID_THREADSYNC",
    "XA_IID_AUDIODECODERCAPABILITIES",
    "XA_IID_AUDIOENCODER",
    "XA_IID_AUDIOENCODERCAPABILITIES",
    "XA_IID_VIDEODECODERCAPABILITIES",
    "XA_IID_VIDEOENCODER",
    "XA_IID_VIDEOENCODERCAPABILITIES",
    "XA_IID_VIDEOPOSTPROCESSING",
    "XA_IID_ANDROIDBUFFERQUEUESOURCE",
};
#define XO_XA_EXPORT_COUNT (sizeof(k_xa_export_set) / sizeof(k_xa_export_set[0]))

/* Declared AMidi export set: the 14 functions of amidi/AMidi.h (r27b). */
static const char* k_amidi_export_set[] = {
    "AMidiDevice_fromJava",
    "AMidiDevice_release",
    "AMidiDevice_getType",
    "AMidiDevice_getNumInputPorts",
    "AMidiDevice_getNumOutputPorts",
    "AMidiDevice_getDefaultProtocol",
    "AMidiOutputPort_open",
    "AMidiOutputPort_close",
    "AMidiOutputPort_receive",
    "AMidiInputPort_open",
    "AMidiInputPort_send",
    "AMidiInputPort_sendWithTimestamp",
    "AMidiInputPort_sendFlush",
    "AMidiInputPort_close",
};
#define XO_AMIDI_EXPORT_COUNT (sizeof(k_amidi_export_set) / sizeof(k_amidi_export_set[0]))

/* -- export-set verification --------------------------------------------- */

static int xo_check_set(xo_lib_t lib, const char* const* names, size_t count,
                        char* missing, size_t missing_size) {
    size_t used = 0;
    int missing_count = 0;
    missing[0] = 0;
    for (size_t i = 0; i < count; i++) {
        if (!xo_dlsym(lib, names[i])) {
            used = strlen(missing);
            snprintf(missing + used, missing_size - used, "%s%s",
                     used ? "," : "", names[i]);
            missing_count++;
        }
    }
    return missing_count;
}

static int xo_finish_load(void) {
    g_missing_sl_count = 0;
    g_missing_xa_count = 0;
    g_missing_amidi_count = 0;
    g_missing_sl[0] = 0;
    g_missing_xa[0] = 0;
    g_missing_amidi[0] = 0;
    if (g_sl) {
        g_missing_sl_count = xo_check_set(g_sl, k_sl_export_set, XO_SL_EXPORT_COUNT,
                                          g_missing_sl, sizeof(g_missing_sl));
    } else {
        g_missing_sl_count = -1;
    }
    if (g_xa) {
        g_missing_xa_count = xo_check_set(g_xa, k_xa_export_set, XO_XA_EXPORT_COUNT,
                                          g_missing_xa, sizeof(g_missing_xa));
    } else {
        g_missing_xa_count = -1;
    }
    if (g_amidi) {
        g_missing_amidi_count = xo_check_set(g_amidi, k_amidi_export_set, XO_AMIDI_EXPORT_COUNT,
                                             g_missing_amidi, sizeof(g_missing_amidi));
    } else {
        g_missing_amidi_count = -1;
    }

    p_sl_create_engine = (PFN_slCreateEngine)xo_dlsym(g_sl, "slCreateEngine");
    p_sl_query_num = (PFN_slQueryNumSupportedEngineInterfaces)xo_dlsym(
        g_sl, "slQueryNumSupportedEngineInterfaces");
    p_sl_query_iid = (PFN_slQuerySupportedEngineInterfaces)xo_dlsym(
        g_sl, "slQuerySupportedEngineInterfaces");

    if (g_missing_sl_count != 0 || g_missing_xa_count != 0 || g_missing_amidi_count != 0) {
        snprintf(g_error, sizeof(g_error), "sl[%s] xa[%s] amidi[%s]",
                 g_sl ? g_missing_sl : "lib-absent",
                 g_xa ? g_missing_xa : "lib-absent",
                 g_amidi ? g_missing_amidi : "lib-absent");
        return 2;
    }
    xo_set_error("");
    return 0;
}

static int xo_load_triple(const char* sl_name, const char* xa_name, const char* amidi_name) {
    xo_unload();
    g_sl = xo_dlopen(sl_name);
    g_xa = xo_dlopen(xa_name);
    g_amidi = xo_dlopen(amidi_name);
    if (!g_sl && !g_xa && !g_amidi) {
        snprintf(g_error, sizeof(g_error), "absent: %s / %s / %s", sl_name, xa_name, amidi_name);
        return 1;
    }
    return xo_finish_load();
}

int xo_load_named(const char* sl_name, const char* xa_name, const char* amidi_name) {
    if (!sl_name || !xa_name || !amidi_name) {
        xo_set_error("null soname");
        return 2;
    }
    return xo_load_triple(sl_name, xa_name, amidi_name);
}

int xo_load(void) {
    return xo_load_triple("libOpenSLES.so", "libOpenMAXAL.so", "libamidi.so");
}

const char* xo_error(void) { return g_error; }

int xo_loaded_mask(void) {
    int mask = 0;
    if (g_sl) mask |= 1;
    if (g_xa) mask |= 2;
    if (g_amidi) mask |= 4;
    return mask;
}

int xo_sl_missing_count(void) { return g_missing_sl_count; }
const char* xo_sl_missing(void) { return g_missing_sl; }
int xo_xa_missing_count(void) { return g_missing_xa_count; }
const char* xo_xa_missing(void) { return g_missing_xa; }
int xo_amidi_missing_count(void) { return g_missing_amidi_count; }
const char* xo_amidi_missing(void) { return g_missing_amidi; }

/* Count SL_IID_* globals whose stored interface-ID pointer is NULL.  The
 * symbols are 8-byte data slots holding the runtime GUID address; a
 * non-null slot is the ABI liveness proof for the interface table. */
int xo_sl_iid_null_values(void) {
    if (!g_sl) { xo_set_error("libOpenSLES.so not loaded"); return -1; }
    int nulls = 0;
    for (size_t i = 0; i < XO_SL_EXPORT_COUNT; i++) {
        const char* name = k_sl_export_set[i];
        if (strncmp(name, "SL_IID_", 7) != 0) continue;
        void* slot = xo_dlsym(g_sl, name);
        if (!slot) { nulls++; continue; } /* unresolved == dead */
        if (!*(void**)slot) nulls++;
    }
    return nulls;
}

/* -- OpenSL ES engine lifecycle (all vtable calls stay C-side) ----------- */

int xo_sl_engine_lifecycle(void) {
    g_sl_last_state = 0;
    if (!g_sl) { xo_set_error("libOpenSLES.so not loaded"); return -1; }
    if (!p_sl_create_engine) { xo_set_error("slCreateEngine unresolved"); return -1; }
    XO_SLObjectItf engine = 0;
    uint32_t rc = p_sl_create_engine(&engine, 0, 0, 0, 0, 0);
    if (rc != XO_SL_RESULT_SUCCESS || !engine) {
        snprintf(g_error, sizeof(g_error), "slCreateEngine rc=0x%08x engine=%s",
                 (unsigned)rc, engine ? "non-null" : "null");
        return -2;
    }
    rc = (*engine)->Realize(engine, XO_SL_BOOLEAN_FALSE);
    if (rc != XO_SL_RESULT_SUCCESS) {
        snprintf(g_error, sizeof(g_error), "Realize rc=0x%08x", (unsigned)rc);
        (*engine)->Destroy(engine);
        return -3;
    }
    uint32_t state = 0;
    uint32_t src = (*engine)->GetState(engine, &state);
    if (src == XO_SL_RESULT_SUCCESS) g_sl_last_state = (int)state;
    (*engine)->Destroy(engine);
    if (src != XO_SL_RESULT_SUCCESS) {
        snprintf(g_error, sizeof(g_error), "GetState rc=0x%08x", (unsigned)src);
        return -4;
    }
    if (state != XO_SL_OBJECT_STATE_REALIZED) {
        snprintf(g_error, sizeof(g_error), "state=%u after Realize (want %u)",
                 (unsigned)state, (unsigned)XO_SL_OBJECT_STATE_REALIZED);
        return -4;
    }
    xo_set_error("");
    return 0;
}

int xo_sl_engine_last_state(void) { return g_sl_last_state; }

int xo_sl_query_num_engine_interfaces(void) {
    if (!g_sl) { xo_set_error("libOpenSLES.so not loaded"); return -1; }
    if (!p_sl_query_num) { xo_set_error("slQueryNumSupportedEngineInterfaces unresolved"); return -1; }
    uint32_t n = 0;
    uint32_t rc = p_sl_query_num(&n);
    if (rc != XO_SL_RESULT_SUCCESS) {
        snprintf(g_error, sizeof(g_error), "slQueryNumSupportedEngineInterfaces rc=0x%08x",
                 (unsigned)rc);
        return -2;
    }
    return (int)n;
}

int xo_sl_query_engine_interfaces_ok(void) {
    if (!g_sl) { xo_set_error("libOpenSLES.so not loaded"); return -1; }
    if (!p_sl_query_iid) { xo_set_error("slQuerySupportedEngineInterfaces unresolved"); return -1; }
    int n = xo_sl_query_num_engine_interfaces();
    if (n < 0) return n;
    int ok = 0;
    for (int i = 0; i < n; i++) {
        const void* iid = 0;
        uint32_t rc = p_sl_query_iid((uint32_t)i, &iid);
        if (rc == XO_SL_RESULT_SUCCESS && iid) ok++;
    }
    if (ok != n) {
        snprintf(g_error, sizeof(g_error), "engine interface query: %d/%d non-null", ok, n);
    } else {
        xo_set_error("");
    }
    return ok;
}

/* -- AMidi ---------------------------------------------------------------
 * The r27b oracle declares 14 core functions and NO native device
 * enumeration: device objects arrive only through the JNI route
 * (AMidiDevice_fromJava).  The device-count attempt resolves the newer
 * `AMidi_getDeviceInfo` extension symbol if a future platform exports
 * it; absent is a RECORDED outcome (-1), not an error. */
int xo_amidi_get_device_info_present(void) {
    if (!g_amidi) return 0;
    return xo_dlsym(g_amidi, "AMidi_getDeviceInfo") ? 1 : 0;
}

int xo_amidi_device_count_attempt(void) {
    if (!g_amidi) { xo_set_error("libamidi.so not loaded"); return -3; }
    if (!xo_dlsym(g_amidi, "AMidi_getDeviceInfo")) {
        xo_set_error("AMidi_getDeviceInfo absent: r27b oracle declares 14 core fns; "
                     "device objects arrive only via AMidiDevice_fromJava (JNI)");
        return -1;
    }
    xo_set_error("AMidi_getDeviceInfo present but ABI unverified (beyond the r27b oracle)");
    return -2;
}

/* -- teardown ------------------------------------------------------------ */

void xo_unload(void) {
    if (g_sl) { xo_dlclose(g_sl); g_sl = 0; }
    if (g_xa) { xo_dlclose(g_xa); g_xa = 0; }
    if (g_amidi) { xo_dlclose(g_amidi); g_amidi = 0; }
    p_sl_create_engine = 0;
    p_sl_query_num = 0;
    p_sl_query_iid = 0;
    g_missing_sl_count = 0;
    g_missing_xa_count = 0;
    g_missing_amidi_count = 0;
    g_missing_sl[0] = 0;
    g_missing_xa[0] = 0;
    g_missing_amidi[0] = 0;
    g_sl_last_state = 0;
}
