/* XIOM -- xiom.android: libandroid + libnativewindow runtime bridge.
 * Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
 * Licensed under the MIT or Apache-2.0 license, at your option.
 *
 * DESIGN: runtime loader/probe for the Android platform core (A1
 * window-core head: native_window.h + hardware_buffer.h of NDK r27b).
 * No link-time dependency.  On Windows everything classifies as ABSENT
 * (SKIP) via LoadLibraryA; on Android/Linux the libraries load via
 * dlopen, the declared export set is verified (ABI stage) and a
 * functional AHardwareBuffer roundtrip runs (isSupported/allocate/
 * describe/lock/write/read/unlock/release).
 *
 * Contract (flat extern "C", called from module xiom.android):
 *   int         xa_load_named(const char* android_soname,
 *                             const char* nativewindow_soname)
 *                                                    0=ok 1=absent 2=abi
 *   int         xa_load(void)      "libandroid.so" + "libnativewindow.so"
 *   const char* xa_error(void)     last error / missing summary
 *   int         xa_abi_missing_count(void)  unresolved export count
 *   const char* xa_abi_missing(void)        comma-joined missing names
 *   int         xa_hwb_is_supported(int32 w, int32 h, int32 format,
 *                                   int64 usage)
 *   int64       xa_hwb_alloc(...)  handle; 0 = failed (see xa_error)
 *   int32       xa_hwb_width/height/format/stride/layers(int64 handle)
 *   int32       xa_hwb_write_pixel(int64 handle, int32 x, int32 y,
 *                                  int32 rgba)          0=ok
 *   int64       xa_hwb_read_pixel(int64 handle, int32 x, int32 y)
 *                                  pixel; negative = failed (see xa_error)
 *   void        xa_hwb_acquire(int64 handle)
 *   void        xa_hwb_release(int64 handle)
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
};
#define XA_EXPORT_COUNT (sizeof(k_export_set) / sizeof(k_export_set[0]))

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

/* -- teardown ------------------------------------------------------------ */

void xa_unload(void) {
    if (g_android) { xa_dlclose(g_android); g_android = 0; }
    if (g_nativewindow) { xa_dlclose(g_nativewindow); g_nativewindow = 0; }
    p_allocate = 0; p_acquire = 0; p_release = 0; p_describe = 0;
    p_lock = 0; p_unlock = 0; p_is_supported = 0;
    p_shm_create = 0; p_shm_get_size = 0; p_shm_set_prot = 0;
    g_missing_count = 0;
    g_missing[0] = 0;
}
