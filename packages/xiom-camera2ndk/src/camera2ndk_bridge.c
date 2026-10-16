/* XIOM -- xiom.camera2ndk: libcamera2ndk.so runtime bridge.
 * Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
 * Licensed under the MIT or Apache-2.0 license, at your option.
 *
 * DESIGN: runtime loader/probe for the Android camera2 NDK (A8 camera
 * head of the Android SDK100 program; NDK r27b headers:
 * camera/NdkCameraManager.h, NdkCameraDevice.h, NdkCameraCaptureSession.h,
 * NdkCaptureRequest.h, NdkCameraMetadata.h, NdkCameraError.h).  No
 * link-time dependency.  On Windows everything classifies as ABSENT
 * (SKIP) via LoadLibraryA; on Android/Linux the library loads via dlopen,
 * the declared export set is verified (ABI stage) and the functional
 * manager head runs (ACameraManager create -> getCameraIdList -> owned
 * id copies -> deleteCameraIdList -> delete).
 *
 * Pointers never cross the boundary: the ACameraManager and the
 * ACameraIdList stay C-side; each camera id is copied into a
 * caller-owned byte slot on request.  Handles cross as int64.
 *
 * Contract (flat extern "C", called from module xiom.camera2ndk):
 *   int         xc_load_named(const char* soname) 0=ok 1=absent 2=abi
 *   int         xc_load(void)      "libcamera2ndk.so"
 *   const char* xc_error(void)     last error / missing summary
 *   int         xc_abi_missing_count(void)  unresolved export count
 *   const char* xc_abi_missing(void)        comma-joined missing names
 *   int         xc_declared_exports(void)   the declared export-set size
 *   int64       xc_manager_create(void)     handle; 0 = failed (see xc_error)
 *   void        xc_manager_delete(int64 handle)
 *   int32       xc_manager_get_camera_ids(int64 handle)
 *                 0 = ok; negative = camera_status_t (ACAMERA_*);
 *                 positive = bridge-internal status (see below)
 *   int32       xc_camera_id_count(void)    ids recorded by the last call
 *   int32       xc_camera_id_len(int32 idx) length in bytes (-1 = bad idx)
 *   int32       xc_camera_id_copy(int32 idx, uint8* dst, int32 cap)
 *                 copies the id + NUL; returns bytes copied (-1 = error)
 *   void        xc_unload(void)
 *
 * Bridge-internal status codes (> 0): 1 = no/foreign manager handle,
 * 2 = functional export unresolved, 3 = NULL id list, 4 = id list
 * out of range.  Negative codes pass the ACameraManager status through
 * (ACAMERA_ERROR_* from NdkCameraError.h).  A typed negative status from
 * getCameraIdList (e.g. ACAMERA_ERROR_CAMERA_SERVICE when the camera
 * service is unreachable from a shell process) is a legitimate outcome:
 * the suite/driver record it and stay green.
 *
 * Classification (the suite maps it to markers):
 *   XC_LOAD_ABSENT (1) -> SKIP  (runtime absent; CI stays green)
 *   XC_LOAD_ABI    (2) -> FAIL  (present but exports broken; never silent)
 *
 * No POSIX-only code is needed on the functional path (dlopen vs
 * LoadLibraryA is the only platform split).
 */

#include <stdint.h>
#include <stdio.h>
#include <string.h>

#if defined(_WIN32)
#include <windows.h>
typedef HMODULE xc_lib_t;
static xc_lib_t xc_dlopen(const char* name) { return LoadLibraryA(name); }
static void* xc_dlsym(xc_lib_t h, const char* name) {
    return h ? (void*)GetProcAddress(h, name) : 0;
}
static void xc_dlclose(xc_lib_t h) { if (h) FreeLibrary(h); }
#else
#include <dlfcn.h>
typedef void* xc_lib_t;
static xc_lib_t xc_dlopen(const char* name) { return dlopen(name, RTLD_NOW | RTLD_LOCAL); }
static void* xc_dlsym(xc_lib_t h, const char* name) { return h ? dlsym(h, name) : 0; }
static void xc_dlclose(xc_lib_t h) { if (h) dlclose(h); }
#endif

/* -- pinned ABI facts (NDK r27b camera/NdkCameraDevice.h) ---------------- */

/* ACameraIdList { int numCameras; const char** cameraIds; } -- the int is
 * int32 and the pointer is 8-aligned on 64-bit targets. */
typedef struct XC_ACameraIdList {
    int32_t numCameras;
    const char** cameraIds;
} XC_ACameraIdList;

#define XC_MAX_CAMERAS 64
#define XC_ID_MAX 64

/* -- bridge state -------------------------------------------------------- */

static xc_lib_t g_lib = 0;
static char g_error[512] = {0};
static char g_missing[2048] = {0};
static int g_missing_count = 0;

static void* g_manager = 0;               /* C-side ACameraManager* */
static XC_ACameraIdList* g_id_list = 0;   /* C-side list, freed by us */
static char g_camera_ids[XC_MAX_CAMERAS][XC_ID_MAX]; /* owned copies */
static int g_camera_id_count = 0;

/* -- resolved function pointers ------------------------------------------ */

typedef void* (*PFN_manager_create)(void);
typedef void (*PFN_manager_delete)(void*);
typedef int32_t (*PFN_get_camera_id_list)(void*, XC_ACameraIdList**);
typedef void (*PFN_delete_camera_id_list)(XC_ACameraIdList*);

static PFN_manager_create p_manager_create = 0;
static PFN_manager_delete p_manager_delete = 0;
static PFN_get_camera_id_list p_get_camera_id_list = 0;
static PFN_delete_camera_id_list p_delete_camera_id_list = 0;

/* Declared export set of the A8 camera head: every non-inline,
 * non-VNDK-only function of NdkCameraManager.h (10), NdkCameraDevice.h
 * (17), NdkCameraCaptureSession.h (15), NdkCaptureRequest.h (23) and
 * NdkCameraMetadata.h (5).  Excluded by design: ACameraMetadata_
 * fromCameraMetadata (JNI route -> A11) and ACameraManager_getTagFromName
 * (VNDK-only, not part of the NDK surface). */
static const char* k_export_set[] = {
    /* NdkCameraManager.h (10) */
    "ACameraManager_create",
    "ACameraManager_delete",
    "ACameraManager_getCameraIdList",
    "ACameraManager_deleteCameraIdList",
    "ACameraManager_registerAvailabilityCallback",
    "ACameraManager_unregisterAvailabilityCallback",
    "ACameraManager_getCameraCharacteristics",
    "ACameraManager_openCamera",
    "ACameraManager_registerExtendedAvailabilityCallback",
    "ACameraManager_unregisterExtendedAvailabilityCallback",
    /* NdkCameraDevice.h (17) */
    "ACameraDevice_close",
    "ACameraDevice_getId",
    "ACameraDevice_createCaptureRequest",
    "ACaptureSessionOutputContainer_create",
    "ACaptureSessionOutputContainer_free",
    "ACaptureSessionOutput_create",
    "ACaptureSessionOutput_free",
    "ACaptureSessionOutputContainer_add",
    "ACaptureSessionOutputContainer_remove",
    "ACameraDevice_createCaptureSession",
    "ACaptureSessionSharedOutput_create",
    "ACaptureSessionSharedOutput_add",
    "ACaptureSessionSharedOutput_remove",
    "ACameraDevice_createCaptureSessionWithSessionParameters",
    "ACaptureSessionPhysicalOutput_create",
    "ACameraDevice_createCaptureRequest_withPhysicalIds",
    "ACameraDevice_isSessionConfigurationSupported",
    /* NdkCameraCaptureSession.h (15) */
    "ACameraCaptureSession_close",
    "ACameraCaptureSession_getDevice",
    "ACameraCaptureSession_capture",
    "ACameraCaptureSession_setRepeatingRequest",
    "ACameraCaptureSession_stopRepeating",
    "ACameraCaptureSession_abortCaptures",
    "ACameraCaptureSession_updateSharedOutput",
    "ACameraCaptureSession_logicalCamera_capture",
    "ACameraCaptureSession_logicalCamera_setRepeatingRequest",
    "ACameraCaptureSession_captureV2",
    "ACameraCaptureSession_setRepeatingRequestV2",
    "ACameraCaptureSession_logicalCamera_captureV2",
    "ACameraCaptureSession_logicalCamera_setRepeatingRequestV2",
    "ACameraCaptureSession_setWindowPreparedCallback",
    "ACameraCaptureSession_prepareWindow",
    /* NdkCaptureRequest.h (23) */
    "ACameraOutputTarget_create",
    "ACameraOutputTarget_free",
    "ACaptureRequest_addTarget",
    "ACaptureRequest_removeTarget",
    "ACaptureRequest_getConstEntry",
    "ACaptureRequest_getAllTags",
    "ACaptureRequest_setEntry_u8",
    "ACaptureRequest_setEntry_i32",
    "ACaptureRequest_setEntry_float",
    "ACaptureRequest_setEntry_i64",
    "ACaptureRequest_setEntry_double",
    "ACaptureRequest_setEntry_rational",
    "ACaptureRequest_free",
    "ACaptureRequest_setUserContext",
    "ACaptureRequest_getUserContext",
    "ACaptureRequest_copy",
    "ACaptureRequest_getConstEntry_physicalCamera",
    "ACaptureRequest_setEntry_physicalCamera_u8",
    "ACaptureRequest_setEntry_physicalCamera_i32",
    "ACaptureRequest_setEntry_physicalCamera_float",
    "ACaptureRequest_setEntry_physicalCamera_i64",
    "ACaptureRequest_setEntry_physicalCamera_double",
    "ACaptureRequest_setEntry_physicalCamera_rational",
    /* NdkCameraMetadata.h (5; fromCameraMetadata is the JNI route) */
    "ACameraMetadata_getConstEntry",
    "ACameraMetadata_getAllTags",
    "ACameraMetadata_copy",
    "ACameraMetadata_free",
    "ACameraMetadata_isLogicalMultiCamera",
};
#define XC_EXPORT_COUNT (sizeof(k_export_set) / sizeof(k_export_set[0]))

static void xc_set_error(const char* msg) {
    snprintf(g_error, sizeof(g_error), "%s", msg);
}

/* -- manager/id bookkeeping ---------------------------------------------- */

static void xc_clear_cached_ids(void) {
    int i;
    for (i = 0; i < g_camera_id_count; i++) g_camera_ids[i][0] = 0;
    g_camera_id_count = 0;
    if (g_id_list) {
        if (p_delete_camera_id_list) p_delete_camera_id_list(g_id_list);
        g_id_list = 0;
    }
}

void xc_unload(void); /* defined at the bottom; used by xc_load_pair */

static int xc_finish_load(void) {
    g_missing_count = 0;
    g_missing[0] = 0;
    for (size_t i = 0; i < XC_EXPORT_COUNT; i++) {
        if (!xc_dlsym(g_lib, k_export_set[i])) {
            size_t used = strlen(g_missing);
            snprintf(g_missing + used, sizeof(g_missing) - used, "%s%s",
                     used ? "," : "", k_export_set[i]);
            g_missing_count++;
        }
    }
    p_manager_create = (PFN_manager_create)xc_dlsym(g_lib, "ACameraManager_create");
    p_manager_delete = (PFN_manager_delete)xc_dlsym(g_lib, "ACameraManager_delete");
    p_get_camera_id_list =
        (PFN_get_camera_id_list)xc_dlsym(g_lib, "ACameraManager_getCameraIdList");
    p_delete_camera_id_list =
        (PFN_delete_camera_id_list)xc_dlsym(g_lib, "ACameraManager_deleteCameraIdList");
    if (g_missing_count != 0) {
        xc_set_error(g_missing);
        return 2;
    }
    xc_set_error("");
    return 0;
}

static int xc_load_named_impl(const char* soname) {
    xc_unload();
    g_lib = xc_dlopen(soname);
    if (!g_lib) {
        snprintf(g_error, sizeof(g_error), "absent: %s", soname);
        return 1;
    }
    return xc_finish_load();
}

/* -- load / classify ----------------------------------------------------- */

int xc_load_named(const char* soname) {
    if (!soname) {
        xc_set_error("null soname");
        return 2;
    }
    return xc_load_named_impl(soname);
}

int xc_load(void) {
    return xc_load_named_impl("libcamera2ndk.so");
}

const char* xc_error(void) { return g_error; }

int xc_abi_missing_count(void) { return g_missing_count; }

const char* xc_abi_missing(void) { return g_missing; }

int xc_declared_exports(void) { return (int)XC_EXPORT_COUNT; }

/* -- functional ACameraManager head -------------------------------------- */

int64_t xc_manager_create(void) {
    if (!p_manager_create) {
        xc_set_error("ACameraManager_create unresolved");
        return 0;
    }
    if (g_manager) {
        xc_set_error("manager already created (one at a time)");
        return 0;
    }
    void* mgr = p_manager_create();
    if (!mgr) {
        xc_set_error("ACameraManager_create returned NULL");
        return 0;
    }
    g_manager = mgr;
    xc_set_error("");
    return (int64_t)(intptr_t)mgr;
}

int32_t xc_manager_get_camera_ids(int64_t handle) {
    if (!handle || !g_manager || (void*)(intptr_t)handle != g_manager) {
        xc_set_error("no matching manager handle");
        return 1;
    }
    if (!p_get_camera_id_list || !p_delete_camera_id_list) {
        xc_set_error("getCameraIdList/deleteCameraIdList unresolved");
        return 2;
    }
    xc_clear_cached_ids();
    XC_ACameraIdList* list = 0;
    int32_t rc = p_get_camera_id_list(g_manager, &list);
    if (rc != 0) {
        snprintf(g_error, sizeof(g_error), "ACameraManager_getCameraIdList rc=%d", (int)rc);
        return rc; /* negative ACAMERA_* passes through */
    }
    if (!list) {
        xc_set_error("getCameraIdList returned NULL list");
        return 3;
    }
    int32_t n = list->numCameras;
    if (n < 0 || n > XC_MAX_CAMERAS) {
        snprintf(g_error, sizeof(g_error), "camera count out of range (%d)", (int)n);
        p_delete_camera_id_list(list);
        return 4;
    }
    g_id_list = list;
    for (int32_t i = 0; i < n; i++) {
        const char* id = list->cameraIds ? list->cameraIds[i] : 0;
        if (!id) {
            snprintf(g_error, sizeof(g_error), "camera id %d is NULL", (int)i);
            xc_clear_cached_ids();
            return 4;
        }
        snprintf(g_camera_ids[i], XC_ID_MAX, "%s", id);
    }
    g_camera_id_count = (int)n;
    xc_set_error("");
    return 0;
}

int32_t xc_camera_id_count(void) { return (int32_t)g_camera_id_count; }

int32_t xc_camera_id_len(int32_t index) {
    if (index < 0 || index >= g_camera_id_count) {
        xc_set_error("camera id index out of range");
        return -1;
    }
    return (int32_t)strlen(g_camera_ids[index]);
}

int32_t xc_camera_id_copy(int32_t index, uint8_t* dst, int32_t cap) {
    if (index < 0 || index >= g_camera_id_count) {
        xc_set_error("camera id index out of range");
        return -1;
    }
    if (!dst || cap <= 0) {
        xc_set_error("null/invalid id slot");
        return -1;
    }
    int32_t len = (int32_t)strlen(g_camera_ids[index]);
    if (cap < len + 1) {
        xc_set_error("id slot too small");
        return -1;
    }
    memcpy(dst, g_camera_ids[index], (size_t)len + 1);
    return len;
}

void xc_manager_delete(int64_t handle) {
    xc_clear_cached_ids();
    if (!handle) return;
    if (p_manager_delete) p_manager_delete((void*)(intptr_t)handle);
    if ((void*)(intptr_t)handle == g_manager) g_manager = 0;
}

/* -- teardown ------------------------------------------------------------ */

void xc_unload(void) {
    xc_clear_cached_ids();
    if (g_manager && p_manager_delete) p_manager_delete(g_manager);
    g_manager = 0;
    if (g_lib) { xc_dlclose(g_lib); g_lib = 0; }
    p_manager_create = 0;
    p_manager_delete = 0;
    p_get_camera_id_list = 0;
    p_delete_camera_id_list = 0;
    g_missing_count = 0;
    g_missing[0] = 0;
}
