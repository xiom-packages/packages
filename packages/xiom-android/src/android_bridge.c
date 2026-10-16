/* XIOM -- xiom.android: libandroid + libnativewindow runtime bridge.
 * Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
 * Licensed under the MIT or Apache-2.0 license, at your option.
 *
 * DESIGN: runtime loader/probe for the Android platform core (A1
 * window-core + A5 assets-storage + A2 lifecycle-glue heads of NDK
 * r27b).  No link-time dependency.  On Windows everything classifies as
 * ABSENT (SKIP) via LoadLibraryA; on Android/Linux the libraries load via
 * dlopen, the declared export set is verified (ABI stage) and the
 * functional heads run: AHardwareBuffer (isSupported/allocate/describe/
 * lock/write/read/unlock/release), ASharedMemory (memfd + mmap probe),
 * the ALooper (prepare/addFd/pollOnce/wake/removeFd + pipe helpers) and
 * the AConfiguration value object (new/set/get/copy/diff/match).
 *
 * Contract (flat extern "C", called from modules xiom.android,
 * xiom.android.lifecycle and xiom.android.configuration):
 *   int         xa_load_named(const char* android_soname,
 *                             const char* nativewindow_soname)
 *                                                    0=ok 1=absent 2=abi
 *   int         xa_load(void)      "libandroid.so" + "libnativewindow.so"
 *   const char* xa_error(void)     last error / missing summary
 *   int         xa_abi_missing_count(void)  unresolved export count
 *   const char* xa_abi_missing(void)        comma-joined missing names
 *   int32       xa_export_count(void)       declared export-set size
 *   int64       xa_hwb_alloc(...)  handle; 0 = failed (see xa_error)
 *   ... HWB / SHM accessors as before ...
 *   int64       xa_looper_prepare(int32 allow_non_callbacks)  handle
 *   int64       xa_looper_for_thread(void)          handle; 0 = none
 *   void        xa_looper_acquire/release(int64 looper)
 *   int32       xa_looper_wake(int64 looper)        1=ok
 *   int32       xa_looper_add_fd(int64 looper, int32 fd, int32 ident,
 *                                int32 events,
 *                                int32 (*cb)(int32,int32,void*),
 *                                int64 data)         1=added
 *   int32       xa_looper_add_fd_ident(...)         NULL callback (needs
 *                                ALOOPER_PREPARE_ALLOW_NON_CALLBACKS)
 *   int32       xa_looper_remove_fd(int64 looper, int32 fd)  1/0/-1
 *   int32       xa_looper_poll_once/poll_all(int64 looper, int32 ms)
 *                               ident >= 0 or ALOOPER_POLL_* (-1..-4);
 *                               outFd/outEvents/outData land in the
 *                               xa_looper_last_* accessors (B-24)
 *   int64       xa_pipe_open(void)  read fd (non-blocking); write end
 *                               kept bridge-side; one probe pipe at a time
 *   int32       xa_pipe_write_byte(int32 byte)     0=ok
 *   int32       xa_pipe_read_byte(int32 fd)        byte >= 0; -1 empty,
 *                                                  -2 eof, -3 error
 *   int32       xa_pipe_close(int64 read_fd)       0=ok (closes both)
 *   int64       xa_config_new(void)                 handle; 0 = failed
 *   void        xa_config_delete(int64 config)
 *   int32       xa_config_copy/diff/match/is_better_than(...)
 *   int32       xa_config_get_<field>(int64) / xa_config_set_<field>(
 *                               int64, int32)  for the 19 scalar fields
 *   const char* xa_config_language/country(int64)   static 2-char buffer
 *   void        xa_unload(void)
 *
 * Classification (the suite maps it to markers):
 *   XA_LOAD_ABSENT (1) -> SKIP  (runtime absent; CI stays green)
 *   XA_LOAD_ABI    (2) -> FAIL  (present but exports broken; never silent)
 */

#include <stdint.h>
#include <stdio.h>
#include <string.h>

#if defined(_WIN32)
#include <windows.h>
typedef HMODULE xa_lib_t;
static xa_lib_t xa_dlopen(const char* name) { return LoadLibraryA(name); }
static void* xa_dlsym(xa_lib_t h, const char* name) {
    return h ? (void*)GetProcAddress(h, name) : 0;
}
static void xa_dlclose(xa_lib_t h) { if (h) FreeLibrary(h); }
#else
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <unistd.h>
typedef void* xa_lib_t;
static xa_lib_t xa_dlopen(const char* name) { return dlopen(name, RTLD_NOW | RTLD_LOCAL); }
static void* xa_dlsym(xa_lib_t h, const char* name) { return h ? dlsym(h, name) : 0; }
static void xa_dlclose(xa_lib_t h) { if (h) dlclose(h); }
#endif

/* -- pinned ABI facts (NDK r27b android/rect.h + android/hardware_buffer.h) */

typedef struct XA_ARect {
    int32_t left, top, right, bottom;
} XA_ARect;

typedef struct XA_HwbDesc {
    uint32_t width, height, layers, format;
    uint64_t usage;
    uint32_t stride, rfu0;
    uint64_t rfu1;
} XA_HwbDesc;

typedef void XA_AHardwareBuffer;

/* -- bridge state -------------------------------------------------------- */

static xa_lib_t g_android = 0;
static xa_lib_t g_nativewindow = 0;
static char g_error[512] = {0};
static char g_missing[1024] = {0};
static int g_missing_count = 0;

void xa_unload(void); /* defined at the bottom; used by xa_load_pair */

static void xa_set_error(const char* msg) {
    snprintf(g_error, sizeof(g_error), "%s", msg);
}

/* Every symbol is tried against both libraries (re-export layouts differ
 * across API levels; libandroid re-exports most nativewindow symbols). */
static void* xa_resolve(const char* name) {
    void* p = xa_dlsym(g_android, name);
    if (!p) p = xa_dlsym(g_nativewindow, name);
    return p;
}

/* Declared export set of the A1 window-core head (non-inline functions of
 * native_window.h + hardware_buffer.h; the three JNI-surface functions of
 * *_jni.h are an A11 exclusion, see SPEC.md). */
static const char* k_export_set[] = {
    /* native_window.h (15 non-inline exports) */
    "ANativeWindow_acquire",
    "ANativeWindow_release",
    "ANativeWindow_getWidth",
    "ANativeWindow_getHeight",
    "ANativeWindow_getFormat",
    "ANativeWindow_setBuffersGeometry",
    "ANativeWindow_lock",
    "ANativeWindow_unlockAndPost",
    "ANativeWindow_setBuffersTransform",
    "ANativeWindow_setBuffersDataSpace",
    "ANativeWindow_getBuffersDataSpace",
    "ANativeWindow_getBuffersDefaultDataSpace",
    "ANativeWindow_setFrameRate",
    "ANativeWindow_tryAllocateBuffers",
    "ANativeWindow_setFrameRateWithChangeStrategy",
    /* hardware_buffer.h (12 exports; fromHardwareBuffer is JNI -> A11) */
    "AHardwareBuffer_allocate",
    "AHardwareBuffer_acquire",
    "AHardwareBuffer_release",
    "AHardwareBuffer_describe",
    "AHardwareBuffer_lock",
    "AHardwareBuffer_unlock",
    "AHardwareBuffer_lockPlanes",
    "AHardwareBuffer_isSupported",
    "AHardwareBuffer_lockAndGetInfo",
    "AHardwareBuffer_getId",
    "AHardwareBuffer_sendHandleToUnixSocket",
    "AHardwareBuffer_recvHandleFromUnixSocket",
    /* A5 assets-storage head (W2b): asset_manager.h (17 non-JNI) */
    "AAssetManager_openDir",
    "AAssetManager_open",
    "AAssetDir_getNextFileName",
    "AAssetDir_rewind",
    "AAssetDir_close",
    "AAsset_read",
    "AAsset_seek",
    "AAsset_seek64",
    "AAsset_close",
    "AAsset_getBuffer",
    "AAsset_getLength",
    "AAsset_getLength64",
    "AAsset_getRemainingLength",
    "AAsset_getRemainingLength64",
    "AAsset_openFileDescriptor",
    "AAsset_openFileDescriptor64",
    "AAsset_isAllocated",
    /* storage_manager.h (6; the fromJava route is A11) */
    "AStorageManager_new",
    "AStorageManager_delete",
    "AStorageManager_mountObb",
    "AStorageManager_unmountObb",
    "AStorageManager_isObbMounted",
    "AStorageManager_getMountedObbPath",
    /* sharedmem.h (3; dupFromJava is A11) */
    "ASharedMemory_create",
    "ASharedMemory_getSize",
    "ASharedMemory_setProt",
    /* A2 lifecycle-glue head (W2c): looper.h (9 exports) */
    "ALooper_forThread",
    "ALooper_prepare",
    "ALooper_acquire",
    "ALooper_release",
    "ALooper_addFd",
    "ALooper_removeFd",
    "ALooper_pollOnce",
    "ALooper_pollAll",
    "ALooper_wake",
    /* native_activity.h (5 exports; ANativeActivity_onCreate and the 16
     * callback fields are the CONSUMER's surface -- the glue implements
     * them -- not platform exports) */
    "ANativeActivity_finish",
    "ANativeActivity_setWindowFormat",
    "ANativeActivity_setWindowFlags",
    "ANativeActivity_showSoftInput",
    "ANativeActivity_hideSoftInput",
    /* configuration.h (50 platform exports; AConfiguration_setScreenRound
     * is declared in the header but NOT exported by the platform -- absent
     * from the API-36 device lib and the API-35 stubs alike) */
    "AConfiguration_new",
    "AConfiguration_delete",
    "AConfiguration_fromAssetManager",
    "AConfiguration_copy",
    "AConfiguration_getMcc",
    "AConfiguration_setMcc",
    "AConfiguration_getMnc",
    "AConfiguration_setMnc",
    "AConfiguration_getLanguage",
    "AConfiguration_setLanguage",
    "AConfiguration_getCountry",
    "AConfiguration_setCountry",
    "AConfiguration_getOrientation",
    "AConfiguration_setOrientation",
    "AConfiguration_getTouchscreen",
    "AConfiguration_setTouchscreen",
    "AConfiguration_getDensity",
    "AConfiguration_setDensity",
    "AConfiguration_getKeyboard",
    "AConfiguration_setKeyboard",
    "AConfiguration_getNavigation",
    "AConfiguration_setNavigation",
    "AConfiguration_getKeysHidden",
    "AConfiguration_setKeysHidden",
    "AConfiguration_getNavHidden",
    "AConfiguration_setNavHidden",
    "AConfiguration_getSdkVersion",
    "AConfiguration_setSdkVersion",
    "AConfiguration_getScreenSize",
    "AConfiguration_setScreenSize",
    "AConfiguration_getScreenLong",
    "AConfiguration_setScreenLong",
    "AConfiguration_getScreenRound",
    "AConfiguration_getUiModeType",
    "AConfiguration_setUiModeType",
    "AConfiguration_getUiModeNight",
    "AConfiguration_setUiModeNight",
    "AConfiguration_getScreenWidthDp",
    "AConfiguration_setScreenWidthDp",
    "AConfiguration_getScreenHeightDp",
    "AConfiguration_setScreenHeightDp",
    "AConfiguration_getSmallestScreenWidthDp",
    "AConfiguration_setSmallestScreenWidthDp",
    "AConfiguration_getLayoutDirection",
    "AConfiguration_setLayoutDirection",
    "AConfiguration_getGrammaticalGender",
    "AConfiguration_setGrammaticalGender",
    "AConfiguration_diff",
    "AConfiguration_match",
    "AConfiguration_isBetterThan",
};
#define XA_EXPORT_COUNT (sizeof(k_export_set) / sizeof(k_export_set[0]))

/* 53 (A1+A5, W2a/W2b) + 64 (A2, W2c: looper 9 + activity 5 + config 50). */
_Static_assert(XA_EXPORT_COUNT == 117,
               "export-set drift: update the suite/SPEC counts with the set");

/* -- HWB function pointers (resolved during load) ------------------------ */

typedef int (*PFN_allocate)(const XA_HwbDesc*, XA_AHardwareBuffer**);
typedef void (*PFN_acquire)(XA_AHardwareBuffer*);
typedef void (*PFN_release)(XA_AHardwareBuffer*);
typedef void (*PFN_describe)(const XA_AHardwareBuffer*, XA_HwbDesc*);
typedef int (*PFN_lock)(XA_AHardwareBuffer*, uint64_t, int32_t, const XA_ARect*, void**);
typedef int (*PFN_unlock)(XA_AHardwareBuffer*, int32_t*);
typedef int (*PFN_is_supported)(const XA_HwbDesc*);

static PFN_allocate p_allocate = 0;
static PFN_acquire p_acquire = 0;
static PFN_release p_release = 0;
static PFN_describe p_describe = 0;
static PFN_lock p_lock = 0;
static PFN_unlock p_unlock = 0;
static PFN_is_supported p_is_supported = 0;

typedef int (*PFN_shm_create)(const char*, size_t);
typedef size_t (*PFN_shm_get_size)(int);
typedef int (*PFN_shm_set_prot)(int, int);

static PFN_shm_create p_shm_create = 0;
static PFN_shm_get_size p_shm_get_size = 0;
static PFN_shm_set_prot p_shm_set_prot = 0;

/* -- A2 lifecycle-glue function pointers (W2c) --------------------------- */

typedef void XA_ALooper;
typedef void XA_AConfiguration;
typedef int32_t (*XA_LooperCallback)(int32_t fd, int32_t events, void* data);

static XA_ALooper* (*p_looper_for_thread)(void) = 0;
static XA_ALooper* (*p_looper_prepare)(int) = 0;
static void (*p_looper_acquire)(XA_ALooper*) = 0;
static void (*p_looper_release)(XA_ALooper*) = 0;
static int (*p_looper_add_fd)(XA_ALooper*, int, int, int, XA_LooperCallback, void*) = 0;
static int (*p_looper_remove_fd)(XA_ALooper*, int) = 0;
static int (*p_looper_poll_once)(int, int*, int*, void**) = 0;
static int (*p_looper_poll_all)(int, int*, int*, void**) = 0;
static void (*p_looper_wake)(XA_ALooper*) = 0;

/* Last pollOnce/pollAll out-params, read back via scalar accessors (B-24
 * discipline: out-slots stay C-side). */
static int32_t g_looper_last_fd = 0;
static int32_t g_looper_last_events = 0;
static int64_t g_looper_last_data = 0;

static XA_AConfiguration* (*p_config_new)(void) = 0;
static void (*p_config_delete)(XA_AConfiguration*) = 0;
static void (*p_config_copy)(XA_AConfiguration*, XA_AConfiguration*) = 0;
static int32_t (*p_config_diff)(XA_AConfiguration*, XA_AConfiguration*) = 0;
static int32_t (*p_config_match)(XA_AConfiguration*, XA_AConfiguration*) = 0;
static int32_t (*p_config_is_better_than)(XA_AConfiguration*, XA_AConfiguration*,
                                          XA_AConfiguration*) = 0;
static void (*p_config_get_language)(XA_AConfiguration*, char*) = 0;
static void (*p_config_set_language)(XA_AConfiguration*, const char*) = 0;
static void (*p_config_get_country)(XA_AConfiguration*, char*) = 0;
static void (*p_config_set_country)(XA_AConfiguration*, const char*) = 0;
static int32_t (*p_config_get_screen_round)(XA_AConfiguration*) = 0;

/* The 19 symmetric int32 get/set pairs of configuration.h (the getter has
 * no setter sibling only for ScreenRound -- not exported -- and the
 * language/country pairs are char[2] specials). */
#define XA_CFG_PAIR(lower) \
    static void (*p_cfg_set_##lower)(XA_AConfiguration*, int32_t) = 0; \
    static int32_t (*p_cfg_get_##lower)(XA_AConfiguration*) = 0;

XA_CFG_PAIR(mcc)
XA_CFG_PAIR(mnc)
XA_CFG_PAIR(orientation)
XA_CFG_PAIR(touchscreen)
XA_CFG_PAIR(density)
XA_CFG_PAIR(keyboard)
XA_CFG_PAIR(navigation)
XA_CFG_PAIR(keys_hidden)
XA_CFG_PAIR(nav_hidden)
XA_CFG_PAIR(sdk_version)
XA_CFG_PAIR(screen_size)
XA_CFG_PAIR(screen_long)
XA_CFG_PAIR(ui_mode_type)
XA_CFG_PAIR(ui_mode_night)
XA_CFG_PAIR(screen_width_dp)
XA_CFG_PAIR(screen_height_dp)
XA_CFG_PAIR(smallest_screen_width_dp)
XA_CFG_PAIR(layout_direction)
XA_CFG_PAIR(grammatical_gender)

/* -- load / classify ----------------------------------------------------- */

static int xa_finish_load(void) {
    g_missing_count = 0;
    g_missing[0] = 0;
    for (size_t i = 0; i < XA_EXPORT_COUNT; i++) {
        if (!xa_resolve(k_export_set[i])) {
            size_t used = strlen(g_missing);
            snprintf(g_missing + used, sizeof(g_missing) - used, "%s%s",
                     used ? "," : "", k_export_set[i]);
            g_missing_count++;
        }
    }
    p_allocate = (PFN_allocate)xa_resolve("AHardwareBuffer_allocate");
    p_acquire = (PFN_acquire)xa_resolve("AHardwareBuffer_acquire");
    p_release = (PFN_release)xa_resolve("AHardwareBuffer_release");
    p_describe = (PFN_describe)xa_resolve("AHardwareBuffer_describe");
    p_lock = (PFN_lock)xa_resolve("AHardwareBuffer_lock");
    p_unlock = (PFN_unlock)xa_resolve("AHardwareBuffer_unlock");
    p_is_supported = (PFN_is_supported)xa_resolve("AHardwareBuffer_isSupported");
    p_shm_create = (PFN_shm_create)xa_resolve("ASharedMemory_create");
    p_shm_get_size = (PFN_shm_get_size)xa_resolve("ASharedMemory_getSize");
    p_shm_set_prot = (PFN_shm_set_prot)xa_resolve("ASharedMemory_setProt");
    /* A2 lifecycle-glue (W2c) */
    p_looper_for_thread = (XA_ALooper* (*)(void))xa_resolve("ALooper_forThread");
    p_looper_prepare = (XA_ALooper* (*)(int))xa_resolve("ALooper_prepare");
    p_looper_acquire = (void (*)(XA_ALooper*))xa_resolve("ALooper_acquire");
    p_looper_release = (void (*)(XA_ALooper*))xa_resolve("ALooper_release");
    p_looper_add_fd = (int (*)(XA_ALooper*, int, int, int, XA_LooperCallback, void*))
        xa_resolve("ALooper_addFd");
    p_looper_remove_fd = (int (*)(XA_ALooper*, int))xa_resolve("ALooper_removeFd");
    p_looper_poll_once = (int (*)(int, int*, int*, void**))xa_resolve("ALooper_pollOnce");
    p_looper_poll_all = (int (*)(int, int*, int*, void**))xa_resolve("ALooper_pollAll");
    p_looper_wake = (void (*)(XA_ALooper*))xa_resolve("ALooper_wake");
    p_config_new = (XA_AConfiguration* (*)(void))xa_resolve("AConfiguration_new");
    p_config_delete = (void (*)(XA_AConfiguration*))xa_resolve("AConfiguration_delete");
    p_config_copy = (void (*)(XA_AConfiguration*, XA_AConfiguration*))
        xa_resolve("AConfiguration_copy");
    p_config_diff = (int32_t (*)(XA_AConfiguration*, XA_AConfiguration*))
        xa_resolve("AConfiguration_diff");
    p_config_match = (int32_t (*)(XA_AConfiguration*, XA_AConfiguration*))
        xa_resolve("AConfiguration_match");
    p_config_is_better_than = (int32_t (*)(XA_AConfiguration*, XA_AConfiguration*,
                                           XA_AConfiguration*))
        xa_resolve("AConfiguration_isBetterThan");
    p_config_get_language = (void (*)(XA_AConfiguration*, char*))
        xa_resolve("AConfiguration_getLanguage");
    p_config_set_language = (void (*)(XA_AConfiguration*, const char*))
        xa_resolve("AConfiguration_setLanguage");
    p_config_get_country = (void (*)(XA_AConfiguration*, char*))
        xa_resolve("AConfiguration_getCountry");
    p_config_set_country = (void (*)(XA_AConfiguration*, const char*))
        xa_resolve("AConfiguration_setCountry");
    p_config_get_screen_round = (int32_t (*)(XA_AConfiguration*))
        xa_resolve("AConfiguration_getScreenRound");
#define XA_CFG_RESOLVE(lower, Suffix) \
    p_cfg_set_##lower = (void (*)(XA_AConfiguration*, int32_t)) \
        xa_resolve("AConfiguration_set" #Suffix); \
    p_cfg_get_##lower = (int32_t (*)(XA_AConfiguration*)) \
        xa_resolve("AConfiguration_get" #Suffix);
    XA_CFG_RESOLVE(mcc, Mcc)
    XA_CFG_RESOLVE(mnc, Mnc)
    XA_CFG_RESOLVE(orientation, Orientation)
    XA_CFG_RESOLVE(touchscreen, Touchscreen)
    XA_CFG_RESOLVE(density, Density)
    XA_CFG_RESOLVE(keyboard, Keyboard)
    XA_CFG_RESOLVE(navigation, Navigation)
    XA_CFG_RESOLVE(keys_hidden, KeysHidden)
    XA_CFG_RESOLVE(nav_hidden, NavHidden)
    XA_CFG_RESOLVE(sdk_version, SdkVersion)
    XA_CFG_RESOLVE(screen_size, ScreenSize)
    XA_CFG_RESOLVE(screen_long, ScreenLong)
    XA_CFG_RESOLVE(ui_mode_type, UiModeType)
    XA_CFG_RESOLVE(ui_mode_night, UiModeNight)
    XA_CFG_RESOLVE(screen_width_dp, ScreenWidthDp)
    XA_CFG_RESOLVE(screen_height_dp, ScreenHeightDp)
    XA_CFG_RESOLVE(smallest_screen_width_dp, SmallestScreenWidthDp)
    XA_CFG_RESOLVE(layout_direction, LayoutDirection)
    XA_CFG_RESOLVE(grammatical_gender, GrammaticalGender)
#undef XA_CFG_RESOLVE
    if (g_missing_count != 0) {
        xa_set_error(g_missing);
        return 2;
    }
    xa_set_error("");
    return 0;
}

static int xa_load_pair(const char* android_soname, const char* nativewindow_soname) {
    xa_unload();
    g_android = xa_dlopen(android_soname);
    g_nativewindow = xa_dlopen(nativewindow_soname);
    if (!g_android && !g_nativewindow) {
        snprintf(g_error, sizeof(g_error), "absent: %s / %s", android_soname, nativewindow_soname);
        return 1;
    }
    return xa_finish_load();
}

int xa_load_named(const char* android_soname, const char* nativewindow_soname) {
    if (!android_soname || !nativewindow_soname) {
        xa_set_error("null soname");
        return 2;
    }
    return xa_load_pair(android_soname, nativewindow_soname);
}

int xa_load(void) {
    return xa_load_pair("libandroid.so", "libnativewindow.so");
}

const char* xa_error(void) { return g_error; }

int xa_abi_missing_count(void) { return g_missing_count; }

const char* xa_abi_missing(void) { return g_missing; }

int32_t xa_export_count(void) { return (int32_t)XA_EXPORT_COUNT; }

/* -- functional AHardwareBuffer surface ---------------------------------- */

static XA_AHardwareBuffer* xa_hwb_from_handle(int64_t handle) {
    return (XA_AHardwareBuffer*)(intptr_t)handle;
}

int xa_hwb_is_supported(int32_t width, int32_t height, int32_t format, int64_t usage) {
    if (!p_is_supported) { xa_set_error("isSupported unresolved"); return -1; }
    XA_HwbDesc d;
    memset(&d, 0, sizeof(d));
    d.width = (uint32_t)width;
    d.height = (uint32_t)height;
    d.layers = 1;
    d.format = (uint32_t)format;
    d.usage = (uint64_t)usage;
    return p_is_supported(&d);
}

int64_t xa_hwb_alloc(int32_t width, int32_t height, int32_t format, int64_t usage) {
    if (!p_allocate) { xa_set_error("allocate unresolved"); return 0; }
    XA_HwbDesc d;
    memset(&d, 0, sizeof(d));
    d.width = (uint32_t)width;
    d.height = (uint32_t)height;
    d.layers = 1;
    d.format = (uint32_t)format;
    d.usage = (uint64_t)usage;
    XA_AHardwareBuffer* buf = 0;
    int rc = p_allocate(&d, &buf);
    if (rc != 0 || !buf) {
        snprintf(g_error, sizeof(g_error), "AHardwareBuffer_allocate rc=%d", rc);
        return 0;
    }
    return (int64_t)(intptr_t)buf;
}

static int xa_hwb_describe_into(int64_t handle, XA_HwbDesc* out) {
    if (!p_describe) { xa_set_error("describe unresolved"); return -1; }
    if (!handle) { xa_set_error("null hwb handle"); return -1; }
    memset(out, 0, sizeof(*out));
    p_describe(xa_hwb_from_handle(handle), out);
    return 0;
}

int32_t xa_hwb_width(int64_t handle) {
    XA_HwbDesc d;
    if (xa_hwb_describe_into(handle, &d) != 0) return -1;
    return (int32_t)d.width;
}

int32_t xa_hwb_height(int64_t handle) {
    XA_HwbDesc d;
    if (xa_hwb_describe_into(handle, &d) != 0) return -1;
    return (int32_t)d.height;
}

int32_t xa_hwb_format(int64_t handle) {
    XA_HwbDesc d;
    if (xa_hwb_describe_into(handle, &d) != 0) return -1;
    return (int32_t)d.format;
}

int32_t xa_hwb_stride(int64_t handle) {
    XA_HwbDesc d;
    if (xa_hwb_describe_into(handle, &d) != 0) return -1;
    return (int32_t)d.stride;
}

int32_t xa_hwb_layers(int64_t handle) {
    XA_HwbDesc d;
    if (xa_hwb_describe_into(handle, &d) != 0) return -1;
    return (int32_t)d.layers;
}

/* Roundtrip helpers: lock/unlock stay entirely inside C; no pointer ever
 * crosses the boundary (B-25 discipline). */
#define XA_HWB_USAGE_CPU_READ_OFTEN 3ULL
#define XA_HWB_USAGE_CPU_WRITE_OFTEN (3ULL << 4)

int32_t xa_hwb_write_pixel(int64_t handle, int32_t x, int32_t y, int32_t rgba) {
    if (!p_lock || !p_unlock) { xa_set_error("lock/unlock unresolved"); return -1; }
    if (!handle) { xa_set_error("null hwb handle"); return -1; }
    XA_HwbDesc d;
    if (xa_hwb_describe_into(handle, &d) != 0) return -1;
    if (x < 0 || y < 0 || (uint32_t)x >= d.width || (uint32_t)y >= d.height) {
        xa_set_error("pixel out of range");
        return -1;
    }
    void* base = 0;
    int rc = p_lock(xa_hwb_from_handle(handle), XA_HWB_USAGE_CPU_WRITE_OFTEN, -1, 0, &base);
    if (rc != 0 || !base) {
        snprintf(g_error, sizeof(g_error), "AHardwareBuffer_lock(write) rc=%d", rc);
        return -1;
    }
    uint32_t* row = (uint32_t*)base + (size_t)y * d.stride;
    memcpy(&row[x], &rgba, sizeof(uint32_t));
    int rc2 = p_unlock(xa_hwb_from_handle(handle), 0);
    if (rc2 != 0) {
        snprintf(g_error, sizeof(g_error), "AHardwareBuffer_unlock rc=%d", rc2);
        return -1;
    }
    return 0;
}

int64_t xa_hwb_read_pixel(int64_t handle, int32_t x, int32_t y) {
    if (!p_lock || !p_unlock) { xa_set_error("lock/unlock unresolved"); return -1; }
    if (!handle) { xa_set_error("null hwb handle"); return -1; }
    XA_HwbDesc d;
    if (xa_hwb_describe_into(handle, &d) != 0) return -1;
    if (x < 0 || y < 0 || (uint32_t)x >= d.width || (uint32_t)y >= d.height) {
        xa_set_error("pixel out of range");
        return -1;
    }
    void* base = 0;
    int rc = p_lock(xa_hwb_from_handle(handle), XA_HWB_USAGE_CPU_READ_OFTEN, -1, 0, &base);
    if (rc != 0 || !base) {
        snprintf(g_error, sizeof(g_error), "AHardwareBuffer_lock(read) rc=%d", rc);
        return -1;
    }
    uint32_t* row = (uint32_t*)base + (size_t)y * d.stride;
    uint32_t v = 0;
    memcpy(&v, &row[x], sizeof(uint32_t));
    int rc2 = p_unlock(xa_hwb_from_handle(handle), 0);
    if (rc2 != 0) {
        snprintf(g_error, sizeof(g_error), "AHardwareBuffer_unlock rc=%d", rc2);
        return -1;
    }
    return (int64_t)v;
}

void xa_hwb_acquire(int64_t handle) {
    if (p_acquire && handle) p_acquire(xa_hwb_from_handle(handle));
}

void xa_hwb_release(int64_t handle) {
    if (p_release && handle) p_release(xa_hwb_from_handle(handle));
}

/* -- functional ASharedMemory surface (POSIX hosts only) ------------------ */

#if !defined(_WIN32)
int64_t xa_shm_create(const char* name, int64_t size) {
    if (!p_shm_create) { xa_set_error("shm create unresolved"); return -1; }
    if (size <= 0) { xa_set_error("shm size must be > 0"); return -1; }
    int fd = p_shm_create(name ? name : "xiom-shm", (size_t)size);
    if (fd < 0) { snprintf(g_error, sizeof(g_error), "ASharedMemory_create rc=%d", fd); return -1; }
    return (int64_t)fd;
}

int64_t xa_shm_get_size(int64_t fd) {
    if (!p_shm_get_size) { xa_set_error("shm getSize unresolved"); return -1; }
    if (fd < 0) { xa_set_error("null shm fd"); return -1; }
    return (int64_t)p_shm_get_size((int)fd);
}

int32_t xa_shm_set_prot(int64_t fd, int32_t prot) {
    if (!p_shm_set_prot) { xa_set_error("shm setProt unresolved"); return -1; }
    if (fd < 0) { xa_set_error("null shm fd"); return -1; }
    int rc = p_shm_set_prot((int)fd, (int)prot);
    if (rc != 0) { snprintf(g_error, sizeof(g_error), "ASharedMemory_setProt rc=%d", rc); }
    return (int32_t)rc;
}

int32_t xa_shm_write_probe(int64_t fd, int32_t value) {
    if (fd < 0) { xa_set_error("null shm fd"); return -1; }
    void* p = mmap(0, 4, PROT_READ | PROT_WRITE, MAP_SHARED, (int)fd, 0);
    if (p == MAP_FAILED) { xa_set_error("shm write mmap failed"); return -1; }
    uint32_t v = (uint32_t)value;
    memcpy(p, &v, 4);
    msync(p, 4, MS_SYNC);
    munmap(p, 4);
    return 0;
}

int64_t xa_shm_read_probe(int64_t fd) {
    if (fd < 0) { xa_set_error("null shm fd"); return -1; }
    void* p = mmap(0, 4, PROT_READ, MAP_SHARED, (int)fd, 0);
    if (p == MAP_FAILED) { xa_set_error("shm read mmap failed"); return -1; }
    uint32_t v = 0;
    memcpy(&v, p, 4);
    munmap(p, 4);
    return (int64_t)v;
}

int32_t xa_fd_close(int64_t fd) {
    if (fd < 0) { xa_set_error("null fd"); return -1; }
    return (int32_t)close((int)fd);
}
#else /* _WIN32: POSIX-only surface (the Android libs never load here) */
int64_t xa_shm_create(const char* name, int64_t size) { (void)name; (void)size; xa_set_error("posix-only"); return -1; }
int64_t xa_shm_get_size(int64_t fd) { (void)fd; xa_set_error("posix-only"); return -1; }
int32_t xa_shm_set_prot(int64_t fd, int32_t prot) { (void)fd; (void)prot; xa_set_error("posix-only"); return -1; }
int32_t xa_shm_write_probe(int64_t fd, int32_t value) { (void)fd; (void)value; xa_set_error("posix-only"); return -1; }
int64_t xa_shm_read_probe(int64_t fd) { (void)fd; xa_set_error("posix-only"); return -1; }
int32_t xa_fd_close(int64_t fd) { (void)fd; xa_set_error("posix-only"); return -1; }
#endif

/* -- functional ALooper surface (W2c, A2 lifecycle-glue) ------------------ */

static XA_ALooper* xa_looper_from_handle(int64_t handle) {
    return (XA_ALooper*)(intptr_t)handle;
}

int64_t xa_looper_prepare(int32_t allow_non_callbacks) {
    if (!p_looper_prepare) { xa_set_error("ALooper_prepare unresolved (runtime not loaded)"); return 0; }
    XA_ALooper* l = p_looper_prepare(allow_non_callbacks ? 1 : 0);
    if (!l) { xa_set_error("ALooper_prepare returned null"); return 0; }
    return (int64_t)(intptr_t)l;
}

int64_t xa_looper_for_thread(void) {
    if (!p_looper_for_thread) { xa_set_error("ALooper_forThread unresolved (runtime not loaded)"); return 0; }
    return (int64_t)(intptr_t)p_looper_for_thread();
}

void xa_looper_acquire(int64_t looper) {
    if (p_looper_acquire && looper) p_looper_acquire(xa_looper_from_handle(looper));
}

void xa_looper_release(int64_t looper) {
    if (p_looper_release && looper) p_looper_release(xa_looper_from_handle(looper));
}

int32_t xa_looper_wake(int64_t looper) {
    if (!p_looper_wake) { xa_set_error("ALooper_wake unresolved (runtime not loaded)"); return 0; }
    if (!looper) { xa_set_error("null looper handle"); return 0; }
    p_looper_wake(xa_looper_from_handle(looper));
    return 1;
}

int32_t xa_looper_add_fd(int64_t looper, int32_t fd, int32_t ident, int32_t events,
                         XA_LooperCallback cb, int64_t data) {
    if (!p_looper_add_fd) { xa_set_error("ALooper_addFd unresolved (runtime not loaded)"); return -1; }
    if (!looper) { xa_set_error("null looper handle"); return -1; }
    int rc = p_looper_add_fd(xa_looper_from_handle(looper), (int)fd, (int)ident,
                             (int)events, cb, (void*)(intptr_t)data);
    if (rc != 1) { snprintf(g_error, sizeof(g_error), "ALooper_addFd rc=%d", rc); }
    return (int32_t)rc;
}

int32_t xa_looper_add_fd_ident(int64_t looper, int32_t fd, int32_t ident, int32_t events) {
    if (!p_looper_add_fd) { xa_set_error("ALooper_addFd unresolved (runtime not loaded)"); return -1; }
    if (!looper) { xa_set_error("null looper handle"); return -1; }
    int rc = p_looper_add_fd(xa_looper_from_handle(looper), (int)fd, (int)ident,
                             (int)events, 0, 0);
    if (rc != 1) { snprintf(g_error, sizeof(g_error), "ALooper_addFd(NULL) rc=%d", rc); }
    return (int32_t)rc;
}

int32_t xa_looper_remove_fd(int64_t looper, int32_t fd) {
    if (!p_looper_remove_fd) { xa_set_error("ALooper_removeFd unresolved (runtime not loaded)"); return -1; }
    if (!looper) { xa_set_error("null looper handle"); return -1; }
    int rc = p_looper_remove_fd(xa_looper_from_handle(looper), (int)fd);
    if (rc < 0) { snprintf(g_error, sizeof(g_error), "ALooper_removeFd rc=%d", rc); }
    return (int32_t)rc;
}

/* ALooper_pollOnce/pollAll poll the CALLING thread's looper; the handle is
 * validated against ALooper_forThread so a foreign looper can never be
 * polled by mistake (ALOOPER_POLL_ERROR = -4 on mismatch). */
static int32_t xa_looper_poll_common(int (*poll)(int, int*, int*, void**),
                                     int64_t looper, int32_t timeout_ms,
                                     const char* name) {
    if (!poll) { xa_set_error(name); return -4; }
    if (!looper) { xa_set_error("null looper handle"); return -4; }
    if (!p_looper_for_thread || p_looper_for_thread() != xa_looper_from_handle(looper)) {
        xa_set_error("looper is not associated with the calling thread");
        return -4;
    }
    g_looper_last_fd = 0;
    g_looper_last_events = 0;
    g_looper_last_data = 0;
    int out_fd = 0, out_events = 0;
    void* out_data = 0;
    int rc = poll((int)timeout_ms, &out_fd, &out_events, &out_data);
    g_looper_last_fd = (int32_t)out_fd;
    g_looper_last_events = (int32_t)out_events;
    g_looper_last_data = (int64_t)(intptr_t)out_data;
    return (int32_t)rc;
}

int32_t xa_looper_poll_once(int64_t looper, int32_t timeout_ms) {
    return xa_looper_poll_common(p_looper_poll_once, looper, timeout_ms,
                                 "ALooper_pollOnce unresolved (runtime not loaded)");
}

int32_t xa_looper_poll_all(int64_t looper, int32_t timeout_ms) {
    return xa_looper_poll_common(p_looper_poll_all, looper, timeout_ms,
                                 "ALooper_pollAll unresolved (runtime not loaded)");
}

int32_t xa_looper_last_fd(void) { return g_looper_last_fd; }
int32_t xa_looper_last_events(void) { return g_looper_last_events; }
int64_t xa_looper_last_data(void) { return g_looper_last_data; }

/* -- probe pipe helpers (POSIX hosts only; keep one pair at a time) ------- */

#if !defined(_WIN32)
static int g_pipe_read = -1;
static int g_pipe_write = -1;

int64_t xa_pipe_open(void) {
    if (g_pipe_read >= 0) { close(g_pipe_read); close(g_pipe_write); }
    g_pipe_read = -1;
    g_pipe_write = -1;
    int fds[2];
    if (pipe(fds) != 0) { xa_set_error("pipe() failed"); return -1; }
    int fl = fcntl(fds[0], F_GETFL, 0);
    if (fl >= 0) fcntl(fds[0], F_SETFL, fl | O_NONBLOCK);
    g_pipe_read = fds[0];
    g_pipe_write = fds[1];
    return (int64_t)fds[0];
}

int32_t xa_pipe_write_byte(int32_t byte) {
    if (g_pipe_write < 0) { xa_set_error("no open probe pipe"); return -1; }
    uint8_t v = (uint8_t)byte;
    ssize_t n = write(g_pipe_write, &v, 1);
    if (n != 1) { xa_set_error("pipe write failed"); return -1; }
    return 0;
}

int32_t xa_pipe_read_byte(int32_t fd) {
    if (fd < 0) { xa_set_error("null pipe fd"); return -3; }
    uint8_t v = 0;
    ssize_t n = read((int)fd, &v, 1);
    if (n == 1) return (int32_t)v;
    if (n == 0) return -2; /* write end closed (eof) */
    if (errno == EAGAIN || errno == EWOULDBLOCK) return -1; /* empty */
    xa_set_error("pipe read failed");
    return -3;
}

int32_t xa_pipe_close(int64_t read_fd) {
    if (g_pipe_read >= 0 && read_fd == (int64_t)g_pipe_read) {
        close(g_pipe_read);
        close(g_pipe_write);
        g_pipe_read = -1;
        g_pipe_write = -1;
        return 0;
    }
    if (read_fd >= 0) {
        close((int)read_fd);
        return 0;
    }
    xa_set_error("null pipe fd");
    return -1;
}
#else /* _WIN32: POSIX-only surface (the Android libs never load here) */
static int g_pipe_read = -1;
static int g_pipe_write = -1;

int64_t xa_pipe_open(void) { xa_set_error("posix-only"); return -1; }
int32_t xa_pipe_write_byte(int32_t byte) { (void)byte; xa_set_error("posix-only"); return -1; }
int32_t xa_pipe_read_byte(int32_t fd) { (void)fd; xa_set_error("posix-only"); return -3; }
int32_t xa_pipe_close(int64_t read_fd) { (void)read_fd; xa_set_error("posix-only"); return -1; }
#endif

/* -- functional AConfiguration surface (W2c, A2 lifecycle-glue) ------------ */

static XA_AConfiguration* xa_cfg_from_handle(int64_t handle) {
    return (XA_AConfiguration*)(intptr_t)handle;
}

int64_t xa_config_new(void) {
    if (!p_config_new) { xa_set_error("AConfiguration_new unresolved (runtime not loaded)"); return 0; }
    XA_AConfiguration* c = p_config_new();
    if (!c) { xa_set_error("AConfiguration_new returned null"); return 0; }
    return (int64_t)(intptr_t)c;
}

int32_t xa_config_delete(int64_t config) {
    if (!p_config_delete) { xa_set_error("AConfiguration_delete unresolved (runtime not loaded)"); return -1; }
    if (!config) { xa_set_error("null config handle"); return -1; }
    p_config_delete(xa_cfg_from_handle(config));
    return 0;
}

int32_t xa_config_copy(int64_t dest, int64_t src) {
    if (!p_config_copy) { xa_set_error("AConfiguration_copy unresolved (runtime not loaded)"); return -1; }
    if (!dest || !src) { xa_set_error("null config handle"); return -1; }
    p_config_copy(xa_cfg_from_handle(dest), xa_cfg_from_handle(src));
    return 0;
}

int32_t xa_config_diff(int64_t a, int64_t b) {
    if (!p_config_diff) { xa_set_error("AConfiguration_diff unresolved (runtime not loaded)"); return -1; }
    if (!a || !b) { xa_set_error("null config handle"); return -1; }
    return (int32_t)p_config_diff(xa_cfg_from_handle(a), xa_cfg_from_handle(b));
}

int32_t xa_config_match(int64_t base, int64_t requested) {
    if (!p_config_match) { xa_set_error("AConfiguration_match unresolved (runtime not loaded)"); return -1; }
    if (!base || !requested) { xa_set_error("null config handle"); return -1; }
    return (int32_t)p_config_match(xa_cfg_from_handle(base), xa_cfg_from_handle(requested));
}

int32_t xa_config_is_better_than(int64_t base, int64_t test, int64_t requested) {
    if (!p_config_is_better_than) {
        xa_set_error("AConfiguration_isBetterThan unresolved (runtime not loaded)");
        return -1;
    }
    if (!base || !test) { xa_set_error("null config handle"); return -1; }
    return (int32_t)p_config_is_better_than(xa_cfg_from_handle(base), xa_cfg_from_handle(test),
                                            requested ? xa_cfg_from_handle(requested) : 0);
}

int32_t xa_config_get_screen_round(int64_t config) {
    if (!p_config_get_screen_round) {
        xa_set_error("AConfiguration_getScreenRound unresolved (runtime not loaded)");
        return -1;
    }
    if (!config) { xa_set_error("null config handle"); return -1; }
    return (int32_t)p_config_get_screen_round(xa_cfg_from_handle(config));
}

/* Language/country read back into a static, NUL-terminated buffer (the
 * header's out param is a 2-char non-terminated array). */
static char g_cfg_chars[3] = {0, 0, 0};

const char* xa_config_get_language(int64_t config) {
    if (!p_config_get_language) {
        xa_set_error("AConfiguration_getLanguage unresolved (runtime not loaded)");
        return 0;
    }
    if (!config) { xa_set_error("null config handle"); return 0; }
    g_cfg_chars[0] = 0;
    g_cfg_chars[1] = 0;
    p_config_get_language(xa_cfg_from_handle(config), g_cfg_chars);
    g_cfg_chars[2] = 0;
    return g_cfg_chars;
}

int32_t xa_config_set_language(int64_t config, const char* language) {
    if (!p_config_set_language) {
        xa_set_error("AConfiguration_setLanguage unresolved (runtime not loaded)");
        return -1;
    }
    if (!config) { xa_set_error("null config handle"); return -1; }
    p_config_set_language(xa_cfg_from_handle(config), language ? language : "");
    return 0;
}

const char* xa_config_get_country(int64_t config) {
    if (!p_config_get_country) {
        xa_set_error("AConfiguration_getCountry unresolved (runtime not loaded)");
        return 0;
    }
    if (!config) { xa_set_error("null config handle"); return 0; }
    g_cfg_chars[0] = 0;
    g_cfg_chars[1] = 0;
    p_config_get_country(xa_cfg_from_handle(config), g_cfg_chars);
    g_cfg_chars[2] = 0;
    return g_cfg_chars;
}

int32_t xa_config_set_country(int64_t config, const char* country) {
    if (!p_config_set_country) {
        xa_set_error("AConfiguration_setCountry unresolved (runtime not loaded)");
        return -1;
    }
    if (!config) { xa_set_error("null config handle"); return -1; }
    p_config_set_country(xa_cfg_from_handle(config), country ? country : "");
    return 0;
}

#define XA_CFG_WRAP(lower) \
int32_t xa_config_get_##lower(int64_t config) { \
    if (!p_cfg_get_##lower) { xa_set_error("AConfiguration getter unresolved (runtime not loaded)"); return -1; } \
    if (!config) { xa_set_error("null config handle"); return -1; } \
    return (int32_t)p_cfg_get_##lower(xa_cfg_from_handle(config)); \
} \
int32_t xa_config_set_##lower(int64_t config, int32_t value) { \
    if (!p_cfg_set_##lower) { xa_set_error("AConfiguration setter unresolved (runtime not loaded)"); return -1; } \
    if (!config) { xa_set_error("null config handle"); return -1; } \
    p_cfg_set_##lower(xa_cfg_from_handle(config), (int32_t)value); \
    return 0; \
}

XA_CFG_WRAP(mcc)
XA_CFG_WRAP(mnc)
XA_CFG_WRAP(orientation)
XA_CFG_WRAP(touchscreen)
XA_CFG_WRAP(density)
XA_CFG_WRAP(keyboard)
XA_CFG_WRAP(navigation)
XA_CFG_WRAP(keys_hidden)
XA_CFG_WRAP(nav_hidden)
XA_CFG_WRAP(sdk_version)
XA_CFG_WRAP(screen_size)
XA_CFG_WRAP(screen_long)
XA_CFG_WRAP(ui_mode_type)
XA_CFG_WRAP(ui_mode_night)
XA_CFG_WRAP(screen_width_dp)
XA_CFG_WRAP(screen_height_dp)
XA_CFG_WRAP(smallest_screen_width_dp)
XA_CFG_WRAP(layout_direction)
XA_CFG_WRAP(grammatical_gender)
#undef XA_CFG_WRAP

/* -- teardown ------------------------------------------------------------ */

void xa_unload(void) {
    if (g_android) { xa_dlclose(g_android); g_android = 0; }
    if (g_nativewindow) { xa_dlclose(g_nativewindow); g_nativewindow = 0; }
    p_allocate = 0; p_acquire = 0; p_release = 0; p_describe = 0;
    p_lock = 0; p_unlock = 0; p_is_supported = 0;
    p_shm_create = 0; p_shm_get_size = 0; p_shm_set_prot = 0;
    p_looper_for_thread = 0; p_looper_prepare = 0; p_looper_acquire = 0;
    p_looper_release = 0; p_looper_add_fd = 0; p_looper_remove_fd = 0;
    p_looper_poll_once = 0; p_looper_poll_all = 0; p_looper_wake = 0;
    p_config_new = 0; p_config_delete = 0; p_config_copy = 0;
    p_config_diff = 0; p_config_match = 0; p_config_is_better_than = 0;
    p_config_get_language = 0; p_config_set_language = 0;
    p_config_get_country = 0; p_config_set_country = 0;
    p_config_get_screen_round = 0;
#define XA_CFG_ZERO(lower) p_cfg_set_##lower = 0; p_cfg_get_##lower = 0;
    XA_CFG_ZERO(mcc)
    XA_CFG_ZERO(mnc)
    XA_CFG_ZERO(orientation)
    XA_CFG_ZERO(touchscreen)
    XA_CFG_ZERO(density)
    XA_CFG_ZERO(keyboard)
    XA_CFG_ZERO(navigation)
    XA_CFG_ZERO(keys_hidden)
    XA_CFG_ZERO(nav_hidden)
    XA_CFG_ZERO(sdk_version)
    XA_CFG_ZERO(screen_size)
    XA_CFG_ZERO(screen_long)
    XA_CFG_ZERO(ui_mode_type)
    XA_CFG_ZERO(ui_mode_night)
    XA_CFG_ZERO(screen_width_dp)
    XA_CFG_ZERO(screen_height_dp)
    XA_CFG_ZERO(smallest_screen_width_dp)
    XA_CFG_ZERO(layout_direction)
    XA_CFG_ZERO(grammatical_gender)
#undef XA_CFG_ZERO
    g_missing_count = 0;
    g_missing[0] = 0;
}
