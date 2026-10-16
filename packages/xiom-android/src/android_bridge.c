/* XIOM -- xiom.android: libandroid + libnativewindow runtime bridge.
 * Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
 * Licensed under the MIT or Apache-2.0 license, at your option.
 *
 * DESIGN: runtime loader/probe for the Android platform core (A1
 * window-core + A5 assets-storage + A2 lifecycle-glue + A3 input + A4
 * sensors heads of NDK r27b).  No link-time dependency.  On Windows
 * everything classifies as ABSENT (SKIP) via LoadLibraryA; on
 * Android/Linux the libraries load via dlopen, the declared export set
 * is verified (ABI stage) and the functional heads run:
 * AHardwareBuffer (isSupported/allocate/describe/lock/write/read/
 * unlock/release), ASharedMemory (memfd + mmap probe), the ALooper
 * (prepare/addFd/pollOnce/wake/removeFd + pipe helpers), the
 * AConfiguration value object (new/set/get/copy/diff/match), the A3
 * input surface (queue attach/detach + event read/finish + every
 * AKeyEvent/AMotionEvent accessor; float payloads cross as binary32 bit
 * patterns) and the A4 sensor surface (manager getInstance/enumerate,
 * the ASensorEventQueue lifecycle incl. getEvents into owned slots, the
 * ASensor metadata family and the direct-channel trio).
 *
 * Contract (flat extern "C", called from modules xiom.android,
 * xiom.android.lifecycle, xiom.android.configuration,
 * xiom.android.input and xiom.android.sensors):
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
 *   int32       xa_input_queue_attach(int64 queue, int64 looper, int32
 *                               ident, cb, int64 data)   0 = ok
 *   int32       xa_input_queue_detach(int64 queue)     0 = ok
 *   int32       xa_input_queue_has_events(int64 queue) 1/0/negative
 *   int64       xa_input_event_get(int64 queue)        event handle;
 *                               0 = failed (error text recorded)
 *   int32       xa_input_event_pre_dispatch(int64 queue, int64 event)
 *   int32       xa_input_event_finish(int64 queue, int64 event,
 *                               int32 handled)         0 = ok
 *   void        xa_input_event_release(int64 event)
 *   int32       xa_input_event_type/device_id/source(int64 event)
 *   int32       xa_key_event_* (8 int accessors; down/event_time int64)
 *   int32       xa_motion_event_* int accessors (action/flags/meta/
 *                               button/edge/pointer_id/tool_type/
 *                               action_button/classification; pointer
 *                               count + history size int64; times int64)
 *   int64       xa_motion_event_*_bits(...) + historical variants /
 *                               axis value: IEEE-754 binary32 bits as
 *                               0..0xFFFFFFFF; -1 = error (B-12-safe:
 *                               no fp value ever crosses the boundary)
 *   int64       xa_sensor_manager_get_instance(void)
 *   int64       xa_sensor_manager_get_instance_for_package(const char*)
 *   int32       xa_sensor_manager_get_sensor_list(int64)      count;
 *                               handles addressable via xa_sensor_list_at
 *   int32       xa_sensor_manager_get_dynamic_sensor_list(int64)
 *   int64       xa_sensor_list_at(int32 which, int32 index)  sensor
 *                               handle (which: 0=static 1=dynamic);
 *                               0 = out of range
 *   int64       xa_sensor_manager_get_default_sensor(_ex)(...)
 *   int64       xa_sensor_manager_create_event_queue(int64 manager,
 *                               int64 looper, int32 ident, cb, int64)
 *   int32       xa_sensor_manager_destroy_event_queue(int64, int64)
 *   int32       xa_sensor_manager_create_shared_memory_direct_channel(
 *                               int64 manager, int32 fd, int64 size)
 *   int32       xa_sensor_manager_create_hardware_buffer_direct_channel(
 *                               int64 manager, int64 hwb, int64 size)
 *   int32       xa_sensor_manager_destroy_direct_channel(int64, int32)
 *   int32       xa_sensor_manager_configure_direct_report(int64 manager,
 *                               int64 sensor, int32 channel_id,
 *                               int32 rate_level)
 *   int32       xa_sensor_event_queue_register_sensor(int64 queue,
 *                               int64 sensor, int32 sampling_us,
 *                               int64 max_latency_us)
 *   int32       xa_sensor_event_queue_enable/disable_sensor(int64, int64)
 *   int32       xa_sensor_event_queue_set_event_rate(int64, int64, int32)
 *   int32       xa_sensor_event_queue_has_events(int64)
 *   int32       xa_sensor_event_queue_request_additional_info_events(
 *                               int64, int32)
 *   int32       xa_sensor_event_queue_read(int64 queue, int32 max_count)
 *                               events read into bridge-owned slots;
 *                               -1 = error
 *   int32/int64 xa_sensor_event_<field>(int32 slot)  per-slot accessors
 *                               (type/sensor/version/timestamp/flags/
 *                               status/step_counter/meta_what + float
 *                               payloads as binary32 bits)
 *   int32       xa_sensor_<field>(int64 sensor)      ASensor metadata
 *                               (resolution as bits)
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
    /* A3 input head (W2d): input.h (60 exports; the 3 *_fromJava routes
     * are JNI -> A11) */
    "AInputEvent_getType",
    "AInputEvent_getDeviceId",
    "AInputEvent_getSource",
    "AInputEvent_release",
    "AInputQueue_attachLooper",
    "AInputQueue_detachLooper",
    "AInputQueue_hasEvents",
    "AInputQueue_getEvent",
    "AInputQueue_preDispatchEvent",
    "AInputQueue_finishEvent",
    "AKeyEvent_getAction",
    "AKeyEvent_getFlags",
    "AKeyEvent_getKeyCode",
    "AKeyEvent_getScanCode",
    "AKeyEvent_getMetaState",
    "AKeyEvent_getRepeatCount",
    "AKeyEvent_getDownTime",
    "AKeyEvent_getEventTime",
    "AMotionEvent_getAction",
    "AMotionEvent_getFlags",
    "AMotionEvent_getMetaState",
    "AMotionEvent_getButtonState",
    "AMotionEvent_getEdgeFlags",
    "AMotionEvent_getDownTime",
    "AMotionEvent_getEventTime",
    "AMotionEvent_getXOffset",
    "AMotionEvent_getYOffset",
    "AMotionEvent_getXPrecision",
    "AMotionEvent_getYPrecision",
    "AMotionEvent_getPointerCount",
    "AMotionEvent_getPointerId",
    "AMotionEvent_getToolType",
    "AMotionEvent_getRawX",
    "AMotionEvent_getRawY",
    "AMotionEvent_getX",
    "AMotionEvent_getY",
    "AMotionEvent_getPressure",
    "AMotionEvent_getSize",
    "AMotionEvent_getTouchMajor",
    "AMotionEvent_getTouchMinor",
    "AMotionEvent_getToolMajor",
    "AMotionEvent_getToolMinor",
    "AMotionEvent_getOrientation",
    "AMotionEvent_getAxisValue",
    "AMotionEvent_getHistorySize",
    "AMotionEvent_getHistoricalEventTime",
    "AMotionEvent_getHistoricalRawX",
    "AMotionEvent_getHistoricalRawY",
    "AMotionEvent_getHistoricalX",
    "AMotionEvent_getHistoricalY",
    "AMotionEvent_getHistoricalPressure",
    "AMotionEvent_getHistoricalSize",
    "AMotionEvent_getHistoricalTouchMajor",
    "AMotionEvent_getHistoricalTouchMinor",
    "AMotionEvent_getHistoricalToolMajor",
    "AMotionEvent_getHistoricalToolMinor",
    "AMotionEvent_getHistoricalOrientation",
    "AMotionEvent_getHistoricalAxisValue",
    "AMotionEvent_getActionButton",
    "AMotionEvent_getClassification",
    /* A4 sensors head (W2d): sensor.h (32 exports) */
    "ASensorManager_getInstance",
    "ASensorManager_getInstanceForPackage",
    "ASensorManager_getSensorList",
    "ASensorManager_getDynamicSensorList",
    "ASensorManager_getDefaultSensor",
    "ASensorManager_getDefaultSensorEx",
    "ASensorManager_createEventQueue",
    "ASensorManager_destroyEventQueue",
    "ASensorManager_createSharedMemoryDirectChannel",
    "ASensorManager_createHardwareBufferDirectChannel",
    "ASensorManager_destroyDirectChannel",
    "ASensorManager_configureDirectReport",
    "ASensorEventQueue_registerSensor",
    "ASensorEventQueue_enableSensor",
    "ASensorEventQueue_disableSensor",
    "ASensorEventQueue_setEventRate",
    "ASensorEventQueue_hasEvents",
    "ASensorEventQueue_getEvents",
    "ASensorEventQueue_requestAdditionalInfoEvents",
    "ASensor_getName",
    "ASensor_getVendor",
    "ASensor_getType",
    "ASensor_getResolution",
    "ASensor_getMinDelay",
    "ASensor_getFifoMaxEventCount",
    "ASensor_getFifoReservedEventCount",
    "ASensor_getStringType",
    "ASensor_getReportingMode",
    "ASensor_getHighestDirectReportRateLevel",
    "ASensor_getHandle",
    "ASensor_isWakeUpSensor",
    "ASensor_isDirectChannelTypeSupported",
};
#define XA_EXPORT_COUNT (sizeof(k_export_set) / sizeof(k_export_set[0]))

/* 53 (A1+A5, W2a/W2b) + 64 (A2, W2c) + 60 (A3, W2d) + 32 (A4, W2d). */
_Static_assert(XA_EXPORT_COUNT == 209,
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

/* -- A3 input head function pointers + state (W2d) ------------------------ */

typedef void XA_AInputQueue;
typedef void XA_AInputEvent;
typedef const void* XA_ASensorRef;

static void (*p_input_queue_attach)(XA_AInputQueue*, XA_ALooper*, int,
                                    XA_LooperCallback, void*) = 0;
static void (*p_input_queue_detach)(XA_AInputQueue*) = 0;
static int32_t (*p_input_queue_has_events)(XA_AInputQueue*) = 0;
static int32_t (*p_input_event_get)(XA_AInputQueue*, XA_AInputEvent**) = 0;
static int32_t (*p_input_event_pre_dispatch)(XA_AInputQueue*, XA_AInputEvent*) = 0;
static void (*p_input_event_finish)(XA_AInputQueue*, XA_AInputEvent*, int) = 0;
static void (*p_input_event_release)(const XA_AInputEvent*) = 0;
static int32_t (*p_ie_get_type)(const XA_AInputEvent*) = 0;
static int32_t (*p_ie_get_device_id)(const XA_AInputEvent*) = 0;
static int32_t (*p_ie_get_source)(const XA_AInputEvent*) = 0;
static int32_t (*p_ke_get_action)(const XA_AInputEvent*) = 0;
static int32_t (*p_ke_get_flags)(const XA_AInputEvent*) = 0;
static int32_t (*p_ke_get_key_code)(const XA_AInputEvent*) = 0;
static int32_t (*p_ke_get_scan_code)(const XA_AInputEvent*) = 0;
static int32_t (*p_ke_get_meta_state)(const XA_AInputEvent*) = 0;
static int32_t (*p_ke_get_repeat_count)(const XA_AInputEvent*) = 0;
static int64_t (*p_ke_get_down_time)(const XA_AInputEvent*) = 0;
static int64_t (*p_ke_get_event_time)(const XA_AInputEvent*) = 0;
static int32_t (*p_me_get_action)(const XA_AInputEvent*) = 0;
static int32_t (*p_me_get_flags)(const XA_AInputEvent*) = 0;
static int32_t (*p_me_get_meta_state)(const XA_AInputEvent*) = 0;
static int32_t (*p_me_get_button_state)(const XA_AInputEvent*) = 0;
static int32_t (*p_me_get_edge_flags)(const XA_AInputEvent*) = 0;
static int64_t (*p_me_get_down_time)(const XA_AInputEvent*) = 0;
static int64_t (*p_me_get_event_time)(const XA_AInputEvent*) = 0;
static float (*p_me_get_x_offset)(const XA_AInputEvent*) = 0;
static float (*p_me_get_y_offset)(const XA_AInputEvent*) = 0;
static float (*p_me_get_x_precision)(const XA_AInputEvent*) = 0;
static float (*p_me_get_y_precision)(const XA_AInputEvent*) = 0;
static size_t (*p_me_get_pointer_count)(const XA_AInputEvent*) = 0;
static int32_t (*p_me_get_pointer_id)(const XA_AInputEvent*, size_t) = 0;
static int32_t (*p_me_get_tool_type)(const XA_AInputEvent*, size_t) = 0;
static float (*p_me_get_raw_x)(const XA_AInputEvent*, size_t) = 0;
static float (*p_me_get_raw_y)(const XA_AInputEvent*, size_t) = 0;
static float (*p_me_get_x)(const XA_AInputEvent*, size_t) = 0;
static float (*p_me_get_y)(const XA_AInputEvent*, size_t) = 0;
static float (*p_me_get_pressure)(const XA_AInputEvent*, size_t) = 0;
static float (*p_me_get_size)(const XA_AInputEvent*, size_t) = 0;
static float (*p_me_get_touch_major)(const XA_AInputEvent*, size_t) = 0;
static float (*p_me_get_touch_minor)(const XA_AInputEvent*, size_t) = 0;
static float (*p_me_get_tool_major)(const XA_AInputEvent*, size_t) = 0;
static float (*p_me_get_tool_minor)(const XA_AInputEvent*, size_t) = 0;
static float (*p_me_get_orientation)(const XA_AInputEvent*, size_t) = 0;
static float (*p_me_get_axis_value)(const XA_AInputEvent*, size_t, int32_t) = 0;
static size_t (*p_me_get_history_size)(const XA_AInputEvent*) = 0;
static int64_t (*p_me_get_hist_event_time)(const XA_AInputEvent*, size_t, size_t) = 0;
static float (*p_me_get_hist_raw_x)(const XA_AInputEvent*, size_t, size_t) = 0;
static float (*p_me_get_hist_raw_y)(const XA_AInputEvent*, size_t, size_t) = 0;
static float (*p_me_get_hist_x)(const XA_AInputEvent*, size_t, size_t) = 0;
static float (*p_me_get_hist_y)(const XA_AInputEvent*, size_t, size_t) = 0;
static float (*p_me_get_hist_pressure)(const XA_AInputEvent*, size_t, size_t) = 0;
static float (*p_me_get_hist_size)(const XA_AInputEvent*, size_t, size_t) = 0;
static float (*p_me_get_hist_touch_major)(const XA_AInputEvent*, size_t, size_t) = 0;
static float (*p_me_get_hist_touch_minor)(const XA_AInputEvent*, size_t, size_t) = 0;
static float (*p_me_get_hist_tool_major)(const XA_AInputEvent*, size_t, size_t) = 0;
static float (*p_me_get_hist_tool_minor)(const XA_AInputEvent*, size_t, size_t) = 0;
static float (*p_me_get_hist_orientation)(const XA_AInputEvent*, size_t, size_t) = 0;
static float (*p_me_get_hist_axis_value)(const XA_AInputEvent*, size_t, size_t,
                                         int32_t) = 0;
static int32_t (*p_me_get_action_button)(const XA_AInputEvent*) = 0;
static int32_t (*p_me_get_classification)(const XA_AInputEvent*) = 0;

/* -- A4 sensors head function pointers + state (W2d) ---------------------- */

typedef void XA_ASensorManager;
typedef void XA_ASensor;
typedef void XA_ASensorEventQueue;

/* Pinned ASensorEvent ABI (NDK r27b): 104 bytes, timestamp @16,
 * data @24, flags @88 -- sizeof/offsetof are gated on-device by the
 * probe (_Static_asserts).  Bridge-owned slots hold the last getEvents
 * batch; no event pointer ever crosses the boundary. */
typedef struct XA_ASensorEvent {
    int32_t version;
    int32_t sensor;
    int32_t type;
    int32_t reserved0;
    int64_t timestamp;
    union {
        float data[16];
        uint64_t u64[8];
    } u;
    uint32_t flags;
    int32_t reserved1[3];
} XA_ASensorEvent;

#define XA_SENSOR_EVENT_SLOTS 32
static XA_ASensorEvent g_sensor_events[XA_SENSOR_EVENT_SLOTS];
static int32_t g_sensor_event_count = 0;
/* The platform owns the sensor list; the out pointer is stable between
 * calls (header contract).  Handles are indexed through it. */
static XA_ASensorRef const* g_sensor_list = 0;
static int32_t g_sensor_list_count = 0;
static XA_ASensorRef const* g_sensor_dyn_list = 0;
static int32_t g_sensor_dyn_list_count = 0;

static XA_ASensorManager* (*p_sensor_manager_get)(void) = 0;
static XA_ASensorManager* (*p_sensor_manager_get_for_package)(const char*) = 0;
static int32_t (*p_sensor_get_list)(XA_ASensorManager*, XA_ASensorRef const**) = 0;
static int64_t (*p_sensor_get_dyn_list)(XA_ASensorManager*, XA_ASensorRef const**) = 0;
static const XA_ASensor* (*p_sensor_get_default)(XA_ASensorManager*, int) = 0;
static const XA_ASensor* (*p_sensor_get_default_ex)(XA_ASensorManager*, int, int) = 0;
static XA_ASensorEventQueue* (*p_sensor_create_queue)(XA_ASensorManager*, XA_ALooper*,
                                                      int, XA_LooperCallback, void*) = 0;
static int32_t (*p_sensor_destroy_queue)(XA_ASensorManager*, XA_ASensorEventQueue*) = 0;
static int32_t (*p_sensor_create_shm_channel)(XA_ASensorManager*, int, size_t) = 0;
static int32_t (*p_sensor_create_hwb_channel)(XA_ASensorManager*, const void*, size_t) = 0;
static int32_t (*p_sensor_destroy_channel)(XA_ASensorManager*, int) = 0;
static int32_t (*p_sensor_configure_direct)(XA_ASensorManager*, const XA_ASensor*,
                                            int, int) = 0;
static int32_t (*p_sensor_queue_register)(XA_ASensorEventQueue*, const XA_ASensor*,
                                          int32_t, int64_t) = 0;
static int32_t (*p_sensor_queue_enable)(XA_ASensorEventQueue*, const XA_ASensor*) = 0;
static int32_t (*p_sensor_queue_disable)(XA_ASensorEventQueue*, const XA_ASensor*) = 0;
static int32_t (*p_sensor_queue_set_rate)(XA_ASensorEventQueue*, const XA_ASensor*,
                                          int32_t) = 0;
static int32_t (*p_sensor_queue_has_events)(XA_ASensorEventQueue*) = 0;
static int64_t (*p_sensor_queue_get_events)(XA_ASensorEventQueue*, XA_ASensorEvent*,
                                            size_t) = 0;
static int32_t (*p_sensor_queue_request_info)(XA_ASensorEventQueue*, int) = 0;
static const char* (*p_sensor_get_name)(const XA_ASensor*) = 0;
static const char* (*p_sensor_get_vendor)(const XA_ASensor*) = 0;
static int32_t (*p_sensor_get_type)(const XA_ASensor*) = 0;
static float (*p_sensor_get_resolution)(const XA_ASensor*) = 0;
static int32_t (*p_sensor_get_min_delay)(const XA_ASensor*) = 0;
static int32_t (*p_sensor_get_fifo_max)(const XA_ASensor*) = 0;
static int32_t (*p_sensor_get_fifo_reserved)(const XA_ASensor*) = 0;
static const char* (*p_sensor_get_string_type)(const XA_ASensor*) = 0;
static int32_t (*p_sensor_get_reporting_mode)(const XA_ASensor*) = 0;
static int32_t (*p_sensor_get_highest_direct_rate)(const XA_ASensor*) = 0;
static int32_t (*p_sensor_get_handle)(const XA_ASensor*) = 0;
static int32_t (*p_sensor_is_wake_up)(const XA_ASensor*) = 0;
static int32_t (*p_sensor_is_direct_channel_supported)(const XA_ASensor*, int) = 0;

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
    /* A3 input head (W2d) */
    p_input_queue_attach = (void (*)(XA_AInputQueue*, XA_ALooper*, int,
                                     XA_LooperCallback, void*))
        xa_resolve("AInputQueue_attachLooper");
    p_input_queue_detach = (void (*)(XA_AInputQueue*))xa_resolve("AInputQueue_detachLooper");
    p_input_queue_has_events = (int32_t (*)(XA_AInputQueue*))
        xa_resolve("AInputQueue_hasEvents");
    p_input_event_get = (int32_t (*)(XA_AInputQueue*, XA_AInputEvent**))
        xa_resolve("AInputQueue_getEvent");
    p_input_event_pre_dispatch = (int32_t (*)(XA_AInputQueue*, XA_AInputEvent*))
        xa_resolve("AInputQueue_preDispatchEvent");
    p_input_event_finish = (void (*)(XA_AInputQueue*, XA_AInputEvent*, int))
        xa_resolve("AInputQueue_finishEvent");
    p_input_event_release = (void (*)(const XA_AInputEvent*))
        xa_resolve("AInputEvent_release");
    p_ie_get_type = (int32_t (*)(const XA_AInputEvent*))xa_resolve("AInputEvent_getType");
    p_ie_get_device_id = (int32_t (*)(const XA_AInputEvent*))
        xa_resolve("AInputEvent_getDeviceId");
    p_ie_get_source = (int32_t (*)(const XA_AInputEvent*))xa_resolve("AInputEvent_getSource");
    p_ke_get_action = (int32_t (*)(const XA_AInputEvent*))xa_resolve("AKeyEvent_getAction");
    p_ke_get_flags = (int32_t (*)(const XA_AInputEvent*))xa_resolve("AKeyEvent_getFlags");
    p_ke_get_key_code = (int32_t (*)(const XA_AInputEvent*))xa_resolve("AKeyEvent_getKeyCode");
    p_ke_get_scan_code = (int32_t (*)(const XA_AInputEvent*))xa_resolve("AKeyEvent_getScanCode");
    p_ke_get_meta_state = (int32_t (*)(const XA_AInputEvent*))
        xa_resolve("AKeyEvent_getMetaState");
    p_ke_get_repeat_count = (int32_t (*)(const XA_AInputEvent*))
        xa_resolve("AKeyEvent_getRepeatCount");
    p_ke_get_down_time = (int64_t (*)(const XA_AInputEvent*))
        xa_resolve("AKeyEvent_getDownTime");
    p_ke_get_event_time = (int64_t (*)(const XA_AInputEvent*))
        xa_resolve("AKeyEvent_getEventTime");
    p_me_get_action = (int32_t (*)(const XA_AInputEvent*))
        xa_resolve("AMotionEvent_getAction");
    p_me_get_flags = (int32_t (*)(const XA_AInputEvent*))xa_resolve("AMotionEvent_getFlags");
    p_me_get_meta_state = (int32_t (*)(const XA_AInputEvent*))
        xa_resolve("AMotionEvent_getMetaState");
    p_me_get_button_state = (int32_t (*)(const XA_AInputEvent*))
        xa_resolve("AMotionEvent_getButtonState");
    p_me_get_edge_flags = (int32_t (*)(const XA_AInputEvent*))
        xa_resolve("AMotionEvent_getEdgeFlags");
    p_me_get_down_time = (int64_t (*)(const XA_AInputEvent*))
        xa_resolve("AMotionEvent_getDownTime");
    p_me_get_event_time = (int64_t (*)(const XA_AInputEvent*))
        xa_resolve("AMotionEvent_getEventTime");
    p_me_get_x_offset = (float (*)(const XA_AInputEvent*))
        xa_resolve("AMotionEvent_getXOffset");
    p_me_get_y_offset = (float (*)(const XA_AInputEvent*))
        xa_resolve("AMotionEvent_getYOffset");
    p_me_get_x_precision = (float (*)(const XA_AInputEvent*))
        xa_resolve("AMotionEvent_getXPrecision");
    p_me_get_y_precision = (float (*)(const XA_AInputEvent*))
        xa_resolve("AMotionEvent_getYPrecision");
    p_me_get_pointer_count = (size_t (*)(const XA_AInputEvent*))
        xa_resolve("AMotionEvent_getPointerCount");
    p_me_get_pointer_id = (int32_t (*)(const XA_AInputEvent*, size_t))
        xa_resolve("AMotionEvent_getPointerId");
    p_me_get_tool_type = (int32_t (*)(const XA_AInputEvent*, size_t))
        xa_resolve("AMotionEvent_getToolType");
    p_me_get_raw_x = (float (*)(const XA_AInputEvent*, size_t))
        xa_resolve("AMotionEvent_getRawX");
    p_me_get_raw_y = (float (*)(const XA_AInputEvent*, size_t))
        xa_resolve("AMotionEvent_getRawY");
    p_me_get_x = (float (*)(const XA_AInputEvent*, size_t))xa_resolve("AMotionEvent_getX");
    p_me_get_y = (float (*)(const XA_AInputEvent*, size_t))xa_resolve("AMotionEvent_getY");
    p_me_get_pressure = (float (*)(const XA_AInputEvent*, size_t))
        xa_resolve("AMotionEvent_getPressure");
    p_me_get_size = (float (*)(const XA_AInputEvent*, size_t))
        xa_resolve("AMotionEvent_getSize");
    p_me_get_touch_major = (float (*)(const XA_AInputEvent*, size_t))
        xa_resolve("AMotionEvent_getTouchMajor");
    p_me_get_touch_minor = (float (*)(const XA_AInputEvent*, size_t))
        xa_resolve("AMotionEvent_getTouchMinor");
    p_me_get_tool_major = (float (*)(const XA_AInputEvent*, size_t))
        xa_resolve("AMotionEvent_getToolMajor");
    p_me_get_tool_minor = (float (*)(const XA_AInputEvent*, size_t))
        xa_resolve("AMotionEvent_getToolMinor");
    p_me_get_orientation = (float (*)(const XA_AInputEvent*, size_t))
        xa_resolve("AMotionEvent_getOrientation");
    p_me_get_axis_value = (float (*)(const XA_AInputEvent*, size_t, int32_t))
        xa_resolve("AMotionEvent_getAxisValue");
    p_me_get_history_size = (size_t (*)(const XA_AInputEvent*))
        xa_resolve("AMotionEvent_getHistorySize");
    p_me_get_hist_event_time = (int64_t (*)(const XA_AInputEvent*, size_t, size_t))
        xa_resolve("AMotionEvent_getHistoricalEventTime");
    p_me_get_hist_raw_x = (float (*)(const XA_AInputEvent*, size_t, size_t))
        xa_resolve("AMotionEvent_getHistoricalRawX");
    p_me_get_hist_raw_y = (float (*)(const XA_AInputEvent*, size_t, size_t))
        xa_resolve("AMotionEvent_getHistoricalRawY");
    p_me_get_hist_x = (float (*)(const XA_AInputEvent*, size_t, size_t))
        xa_resolve("AMotionEvent_getHistoricalX");
    p_me_get_hist_y = (float (*)(const XA_AInputEvent*, size_t, size_t))
        xa_resolve("AMotionEvent_getHistoricalY");
    p_me_get_hist_pressure = (float (*)(const XA_AInputEvent*, size_t, size_t))
        xa_resolve("AMotionEvent_getHistoricalPressure");
    p_me_get_hist_size = (float (*)(const XA_AInputEvent*, size_t, size_t))
        xa_resolve("AMotionEvent_getHistoricalSize");
    p_me_get_hist_touch_major = (float (*)(const XA_AInputEvent*, size_t, size_t))
        xa_resolve("AMotionEvent_getHistoricalTouchMajor");
    p_me_get_hist_touch_minor = (float (*)(const XA_AInputEvent*, size_t, size_t))
        xa_resolve("AMotionEvent_getHistoricalTouchMinor");
    p_me_get_hist_tool_major = (float (*)(const XA_AInputEvent*, size_t, size_t))
        xa_resolve("AMotionEvent_getHistoricalToolMajor");
    p_me_get_hist_tool_minor = (float (*)(const XA_AInputEvent*, size_t, size_t))
        xa_resolve("AMotionEvent_getHistoricalToolMinor");
    p_me_get_hist_orientation = (float (*)(const XA_AInputEvent*, size_t, size_t))
        xa_resolve("AMotionEvent_getHistoricalOrientation");
    p_me_get_hist_axis_value = (float (*)(const XA_AInputEvent*, size_t, size_t, int32_t))
        xa_resolve("AMotionEvent_getHistoricalAxisValue");
    p_me_get_action_button = (int32_t (*)(const XA_AInputEvent*))
        xa_resolve("AMotionEvent_getActionButton");
    p_me_get_classification = (int32_t (*)(const XA_AInputEvent*))
        xa_resolve("AMotionEvent_getClassification");
    /* A4 sensors head (W2d) */
    p_sensor_manager_get = (XA_ASensorManager* (*)(void))
        xa_resolve("ASensorManager_getInstance");
    p_sensor_manager_get_for_package = (XA_ASensorManager* (*)(const char*))
        xa_resolve("ASensorManager_getInstanceForPackage");
    p_sensor_get_list = (int32_t (*)(XA_ASensorManager*, XA_ASensorRef const**))
        xa_resolve("ASensorManager_getSensorList");
    p_sensor_get_dyn_list = (int64_t (*)(XA_ASensorManager*, XA_ASensorRef const**))
        xa_resolve("ASensorManager_getDynamicSensorList");
    p_sensor_get_default = (const XA_ASensor* (*)(XA_ASensorManager*, int))
        xa_resolve("ASensorManager_getDefaultSensor");
    p_sensor_get_default_ex = (const XA_ASensor* (*)(XA_ASensorManager*, int, int))
        xa_resolve("ASensorManager_getDefaultSensorEx");
    p_sensor_create_queue = (XA_ASensorEventQueue* (*)(XA_ASensorManager*, XA_ALooper*,
                                                       int, XA_LooperCallback, void*))
        xa_resolve("ASensorManager_createEventQueue");
    p_sensor_destroy_queue = (int32_t (*)(XA_ASensorManager*, XA_ASensorEventQueue*))
        xa_resolve("ASensorManager_destroyEventQueue");
    p_sensor_create_shm_channel = (int32_t (*)(XA_ASensorManager*, int, size_t))
        xa_resolve("ASensorManager_createSharedMemoryDirectChannel");
    p_sensor_create_hwb_channel = (int32_t (*)(XA_ASensorManager*, const void*, size_t))
        xa_resolve("ASensorManager_createHardwareBufferDirectChannel");
    p_sensor_destroy_channel = (int32_t (*)(XA_ASensorManager*, int))
        xa_resolve("ASensorManager_destroyDirectChannel");
    p_sensor_configure_direct = (int32_t (*)(XA_ASensorManager*, const XA_ASensor*, int, int))
        xa_resolve("ASensorManager_configureDirectReport");
    p_sensor_queue_register = (int32_t (*)(XA_ASensorEventQueue*, const XA_ASensor*,
                                           int32_t, int64_t))
        xa_resolve("ASensorEventQueue_registerSensor");
    p_sensor_queue_enable = (int32_t (*)(XA_ASensorEventQueue*, const XA_ASensor*))
        xa_resolve("ASensorEventQueue_enableSensor");
    p_sensor_queue_disable = (int32_t (*)(XA_ASensorEventQueue*, const XA_ASensor*))
        xa_resolve("ASensorEventQueue_disableSensor");
    p_sensor_queue_set_rate = (int32_t (*)(XA_ASensorEventQueue*, const XA_ASensor*, int32_t))
        xa_resolve("ASensorEventQueue_setEventRate");
    p_sensor_queue_has_events = (int32_t (*)(XA_ASensorEventQueue*))
        xa_resolve("ASensorEventQueue_hasEvents");
    p_sensor_queue_get_events = (int64_t (*)(XA_ASensorEventQueue*, XA_ASensorEvent*, size_t))
        xa_resolve("ASensorEventQueue_getEvents");
    p_sensor_queue_request_info = (int32_t (*)(XA_ASensorEventQueue*, int))
        xa_resolve("ASensorEventQueue_requestAdditionalInfoEvents");
    p_sensor_get_name = (const char* (*)(const XA_ASensor*))xa_resolve("ASensor_getName");
    p_sensor_get_vendor = (const char* (*)(const XA_ASensor*))xa_resolve("ASensor_getVendor");
    p_sensor_get_type = (int32_t (*)(const XA_ASensor*))xa_resolve("ASensor_getType");
    p_sensor_get_resolution = (float (*)(const XA_ASensor*))
        xa_resolve("ASensor_getResolution");
    p_sensor_get_min_delay = (int32_t (*)(const XA_ASensor*))
        xa_resolve("ASensor_getMinDelay");
    p_sensor_get_fifo_max = (int32_t (*)(const XA_ASensor*))
        xa_resolve("ASensor_getFifoMaxEventCount");
    p_sensor_get_fifo_reserved = (int32_t (*)(const XA_ASensor*))
        xa_resolve("ASensor_getFifoReservedEventCount");
    p_sensor_get_string_type = (const char* (*)(const XA_ASensor*))
        xa_resolve("ASensor_getStringType");
    p_sensor_get_reporting_mode = (int32_t (*)(const XA_ASensor*))
        xa_resolve("ASensor_getReportingMode");
    p_sensor_get_highest_direct_rate = (int32_t (*)(const XA_ASensor*))
        xa_resolve("ASensor_getHighestDirectReportRateLevel");
    p_sensor_get_handle = (int32_t (*)(const XA_ASensor*))xa_resolve("ASensor_getHandle");
    p_sensor_is_wake_up = (int32_t (*)(const XA_ASensor*))
        xa_resolve("ASensor_isWakeUpSensor");
    p_sensor_is_direct_channel_supported = (int32_t (*)(const XA_ASensor*, int))
        xa_resolve("ASensor_isDirectChannelTypeSupported");
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

/* -- functional A3 input surface (W2d, A3 input head) ---------------------
 *
 * The queue is delivered by the framework to an app (native_app_glue's
 * inputQueueCreated); this bridge never fabricates one.  Every call
 * without a loaded runtime / handle errors explicitly (never a silent
 * zero).  Float-valued accessors return the IEEE-754 binary32 bits
 * (0..0xFFFFFFFF) or -1 on error (B-12: no fp value crosses the ABI).
 */

static XA_AInputQueue* xa_input_queue_from_handle(int64_t handle) {
    return (XA_AInputQueue*)(intptr_t)handle;
}

static XA_AInputEvent* xa_input_event_from_handle(int64_t handle) {
    return (XA_AInputEvent*)(intptr_t)handle;
}

static int64_t xa_f32_bits(float f) {
    uint32_t b;
    memcpy(&b, &f, sizeof(b));
    return (int64_t)b;
}

#define XA_EV_GUARD(p) \
    do { \
        if (!(p)) { xa_set_error("input accessor unresolved (runtime not loaded)"); return -1; } \
        if (!event) { xa_set_error("null input event handle"); return -1; } \
    } while (0)

int32_t xa_input_queue_attach(int64_t queue, int64_t looper, int32_t ident,
                              XA_LooperCallback cb, int64_t data) {
    if (!p_input_queue_attach) {
        xa_set_error("AInputQueue_attachLooper unresolved (runtime not loaded)");
        return -1;
    }
    if (!queue) { xa_set_error("null input queue handle"); return -1; }
    if (!looper) { xa_set_error("null looper handle"); return -1; }
    p_input_queue_attach(xa_input_queue_from_handle(queue),
                         xa_looper_from_handle(looper), (int)ident, cb,
                         (void*)(intptr_t)data);
    return 0;
}

int32_t xa_input_queue_attach_ident(int64_t queue, int64_t looper, int32_t ident) {
    if (!p_input_queue_attach) {
        xa_set_error("AInputQueue_attachLooper unresolved (runtime not loaded)");
        return -1;
    }
    if (!queue) { xa_set_error("null input queue handle"); return -1; }
    if (!looper) { xa_set_error("null looper handle"); return -1; }
    p_input_queue_attach(xa_input_queue_from_handle(queue),
                         xa_looper_from_handle(looper), (int)ident, 0, 0);
    return 0;
}

int32_t xa_input_queue_detach(int64_t queue) {
    if (!p_input_queue_detach) {
        xa_set_error("AInputQueue_detachLooper unresolved (runtime not loaded)");
        return -1;
    }
    if (!queue) { xa_set_error("null input queue handle"); return -1; }
    p_input_queue_detach(xa_input_queue_from_handle(queue));
    return 0;
}

int32_t xa_input_queue_has_events(int64_t queue) {
    if (!p_input_queue_has_events) {
        xa_set_error("AInputQueue_hasEvents unresolved (runtime not loaded)");
        return -1;
    }
    if (!queue) { xa_set_error("null input queue handle"); return -1; }
    return (int32_t)p_input_queue_has_events(xa_input_queue_from_handle(queue));
}

int64_t xa_input_event_get(int64_t queue) {
    if (!p_input_event_get) {
        xa_set_error("AInputQueue_getEvent unresolved (runtime not loaded)");
        return 0;
    }
    if (!queue) { xa_set_error("null input queue handle"); return 0; }
    XA_AInputEvent* ev = 0;
    int32_t rc = p_input_event_get(xa_input_queue_from_handle(queue), &ev);
    if (rc != 0 || !ev) {
        snprintf(g_error, sizeof(g_error), "AInputQueue_getEvent rc=%d", rc);
        return 0;
    }
    return (int64_t)(intptr_t)ev;
}

int32_t xa_input_event_pre_dispatch(int64_t queue, int64_t event) {
    if (!p_input_event_pre_dispatch) {
        xa_set_error("AInputQueue_preDispatchEvent unresolved (runtime not loaded)");
        return -1;
    }
    if (!queue) { xa_set_error("null input queue handle"); return -1; }
    if (!event) { xa_set_error("null input event handle"); return -1; }
    return (int32_t)p_input_event_pre_dispatch(xa_input_queue_from_handle(queue),
                                               xa_input_event_from_handle(event));
}

int32_t xa_input_event_finish(int64_t queue, int64_t event, int32_t handled) {
    if (!p_input_event_finish) {
        xa_set_error("AInputQueue_finishEvent unresolved (runtime not loaded)");
        return -1;
    }
    if (!queue) { xa_set_error("null input queue handle"); return -1; }
    if (!event) { xa_set_error("null input event handle"); return -1; }
    p_input_event_finish(xa_input_queue_from_handle(queue),
                         xa_input_event_from_handle(event), (int)handled);
    return 0;
}

void xa_input_event_release(int64_t event) {
    if (p_input_event_release && event) {
        p_input_event_release(xa_input_event_from_handle(event));
    } else if (!p_input_event_release && event) {
        xa_set_error("AInputEvent_release unresolved (needs API 31+)");
    }
}

int32_t xa_input_event_type(int64_t event) {
    XA_EV_GUARD(p_ie_get_type);
    return (int32_t)p_ie_get_type(xa_input_event_from_handle(event));
}

int32_t xa_input_event_device_id(int64_t event) {
    XA_EV_GUARD(p_ie_get_device_id);
    return (int32_t)p_ie_get_device_id(xa_input_event_from_handle(event));
}

int32_t xa_input_event_source(int64_t event) {
    XA_EV_GUARD(p_ie_get_source);
    return (int32_t)p_ie_get_source(xa_input_event_from_handle(event));
}

int32_t xa_key_event_action(int64_t event) {
    XA_EV_GUARD(p_ke_get_action);
    return (int32_t)p_ke_get_action(xa_input_event_from_handle(event));
}

int32_t xa_key_event_flags(int64_t event) {
    XA_EV_GUARD(p_ke_get_flags);
    return (int32_t)p_ke_get_flags(xa_input_event_from_handle(event));
}

int32_t xa_key_event_key_code(int64_t event) {
    XA_EV_GUARD(p_ke_get_key_code);
    return (int32_t)p_ke_get_key_code(xa_input_event_from_handle(event));
}

int32_t xa_key_event_scan_code(int64_t event) {
    XA_EV_GUARD(p_ke_get_scan_code);
    return (int32_t)p_ke_get_scan_code(xa_input_event_from_handle(event));
}

int32_t xa_key_event_meta_state(int64_t event) {
    XA_EV_GUARD(p_ke_get_meta_state);
    return (int32_t)p_ke_get_meta_state(xa_input_event_from_handle(event));
}

int32_t xa_key_event_repeat_count(int64_t event) {
    XA_EV_GUARD(p_ke_get_repeat_count);
    return (int32_t)p_ke_get_repeat_count(xa_input_event_from_handle(event));
}

int64_t xa_key_event_down_time(int64_t event) {
    XA_EV_GUARD(p_ke_get_down_time);
    return (int64_t)p_ke_get_down_time(xa_input_event_from_handle(event));
}

int64_t xa_key_event_event_time(int64_t event) {
    XA_EV_GUARD(p_ke_get_event_time);
    return (int64_t)p_ke_get_event_time(xa_input_event_from_handle(event));
}

/* Motion event: int-valued accessors. */

#define XA_ME_GUARD(p) \
    do { \
        if (!(p)) { xa_set_error("motion accessor unresolved (runtime not loaded)"); return -1; } \
        if (!event) { xa_set_error("null input event handle"); return -1; } \
    } while (0)

int32_t xa_motion_event_action(int64_t event) {
    XA_ME_GUARD(p_me_get_action);
    return (int32_t)p_me_get_action(xa_input_event_from_handle(event));
}

int32_t xa_motion_event_flags(int64_t event) {
    XA_ME_GUARD(p_me_get_flags);
    return (int32_t)p_me_get_flags(xa_input_event_from_handle(event));
}

int32_t xa_motion_event_meta_state(int64_t event) {
    XA_ME_GUARD(p_me_get_meta_state);
    return (int32_t)p_me_get_meta_state(xa_input_event_from_handle(event));
}

int32_t xa_motion_event_button_state(int64_t event) {
    XA_ME_GUARD(p_me_get_button_state);
    return (int32_t)p_me_get_button_state(xa_input_event_from_handle(event));
}

int32_t xa_motion_event_edge_flags(int64_t event) {
    XA_ME_GUARD(p_me_get_edge_flags);
    return (int32_t)p_me_get_edge_flags(xa_input_event_from_handle(event));
}

int64_t xa_motion_event_down_time(int64_t event) {
    XA_ME_GUARD(p_me_get_down_time);
    return (int64_t)p_me_get_down_time(xa_input_event_from_handle(event));
}

int64_t xa_motion_event_event_time(int64_t event) {
    XA_ME_GUARD(p_me_get_event_time);
    return (int64_t)p_me_get_event_time(xa_input_event_from_handle(event));
}

int64_t xa_motion_event_pointer_count(int64_t event) {
    XA_ME_GUARD(p_me_get_pointer_count);
    return (int64_t)p_me_get_pointer_count(xa_input_event_from_handle(event));
}

int64_t xa_motion_event_history_size(int64_t event) {
    XA_ME_GUARD(p_me_get_history_size);
    return (int64_t)p_me_get_history_size(xa_input_event_from_handle(event));
}

int32_t xa_motion_event_pointer_id(int64_t event, int64_t index) {
    XA_ME_GUARD(p_me_get_pointer_id);
    if (index < 0) { xa_set_error("negative pointer index"); return -1; }
    return (int32_t)p_me_get_pointer_id(xa_input_event_from_handle(event), (size_t)index);
}

int32_t xa_motion_event_tool_type(int64_t event, int64_t index) {
    XA_ME_GUARD(p_me_get_tool_type);
    if (index < 0) { xa_set_error("negative pointer index"); return -1; }
    return (int32_t)p_me_get_tool_type(xa_input_event_from_handle(event), (size_t)index);
}

int32_t xa_motion_event_action_button(int64_t event) {
    XA_ME_GUARD(p_me_get_action_button);
    return (int32_t)p_me_get_action_button(xa_input_event_from_handle(event));
}

int32_t xa_motion_event_classification(int64_t event) {
    XA_ME_GUARD(p_me_get_classification);
    return (int32_t)p_me_get_classification(xa_input_event_from_handle(event));
}

/* Motion event: float-valued accessors as binary32 bits. */

int64_t xa_motion_event_x_offset_bits(int64_t event) {
    XA_ME_GUARD(p_me_get_x_offset);
    return xa_f32_bits(p_me_get_x_offset(xa_input_event_from_handle(event)));
}

int64_t xa_motion_event_y_offset_bits(int64_t event) {
    XA_ME_GUARD(p_me_get_y_offset);
    return xa_f32_bits(p_me_get_y_offset(xa_input_event_from_handle(event)));
}

int64_t xa_motion_event_x_precision_bits(int64_t event) {
    XA_ME_GUARD(p_me_get_x_precision);
    return xa_f32_bits(p_me_get_x_precision(xa_input_event_from_handle(event)));
}

int64_t xa_motion_event_y_precision_bits(int64_t event) {
    XA_ME_GUARD(p_me_get_y_precision);
    return xa_f32_bits(p_me_get_y_precision(xa_input_event_from_handle(event)));
}

#define XA_ME_BITS_FN(name, field) \
int64_t xa_motion_event_##name##_bits(int64_t event, int64_t index) { \
    if (!p_me_get_##field) { xa_set_error("motion accessor unresolved (runtime not loaded)"); return -1; } \
    if (!event) { xa_set_error("null input event handle"); return -1; } \
    if (index < 0) { xa_set_error("negative pointer index"); return -1; } \
    return xa_f32_bits(p_me_get_##field(xa_input_event_from_handle(event), (size_t)index)); \
}

XA_ME_BITS_FN(raw_x, raw_x)
XA_ME_BITS_FN(raw_y, raw_y)
XA_ME_BITS_FN(x, x)
XA_ME_BITS_FN(y, y)
XA_ME_BITS_FN(pressure, pressure)
XA_ME_BITS_FN(size, size)
XA_ME_BITS_FN(touch_major, touch_major)
XA_ME_BITS_FN(touch_minor, touch_minor)
XA_ME_BITS_FN(tool_major, tool_major)
XA_ME_BITS_FN(tool_minor, tool_minor)
XA_ME_BITS_FN(orientation, orientation)
#undef XA_ME_BITS_FN

int64_t xa_motion_event_axis_value_bits(int64_t event, int64_t index, int32_t axis) {
    if (!p_me_get_axis_value) { xa_set_error("motion accessor unresolved (runtime not loaded)"); return -1; }
    if (!event) { xa_set_error("null input event handle"); return -1; }
    if (index < 0) { xa_set_error("negative pointer index"); return -1; }
    return xa_f32_bits(p_me_get_axis_value(xa_input_event_from_handle(event),
                                           (size_t)index, axis));
}

int64_t xa_motion_event_historical_event_time(int64_t event, int64_t index,
                                              int64_t history_index) {
    if (!p_me_get_hist_event_time) { xa_set_error("motion accessor unresolved (runtime not loaded)"); return -1; }
    if (!event) { xa_set_error("null input event handle"); return -1; }
    if (index < 0 || history_index < 0) { xa_set_error("negative pointer/history index"); return -1; }
    return (int64_t)p_me_get_hist_event_time(xa_input_event_from_handle(event),
                                             (size_t)index, (size_t)history_index);
}

#define XA_ME_HIST_BITS_FN(name, field) \
int64_t xa_motion_event_historical_##name##_bits(int64_t event, int64_t index, \
                                                 int64_t history_index) { \
    if (!p_me_get_hist_##field) { xa_set_error("motion accessor unresolved (runtime not loaded)"); return -1; } \
    if (!event) { xa_set_error("null input event handle"); return -1; } \
    if (index < 0 || history_index < 0) { xa_set_error("negative pointer/history index"); return -1; } \
    return xa_f32_bits(p_me_get_hist_##field(xa_input_event_from_handle(event), \
                                             (size_t)index, (size_t)history_index)); \
}

XA_ME_HIST_BITS_FN(raw_x, raw_x)
XA_ME_HIST_BITS_FN(raw_y, raw_y)
XA_ME_HIST_BITS_FN(x, x)
XA_ME_HIST_BITS_FN(y, y)
XA_ME_HIST_BITS_FN(pressure, pressure)
XA_ME_HIST_BITS_FN(size, size)
XA_ME_HIST_BITS_FN(touch_major, touch_major)
XA_ME_HIST_BITS_FN(touch_minor, touch_minor)
XA_ME_HIST_BITS_FN(tool_major, tool_major)
XA_ME_HIST_BITS_FN(tool_minor, tool_minor)
XA_ME_HIST_BITS_FN(orientation, orientation)
#undef XA_ME_HIST_BITS_FN

int64_t xa_motion_event_historical_axis_value_bits(int64_t event, int64_t index,
                                                   int64_t history_index,
                                                   int32_t axis) {
    if (!p_me_get_hist_axis_value) { xa_set_error("motion accessor unresolved (runtime not loaded)"); return -1; }
    if (!event) { xa_set_error("null input event handle"); return -1; }
    if (index < 0 || history_index < 0) { xa_set_error("negative pointer/history index"); return -1; }
    return xa_f32_bits(p_me_get_hist_axis_value(xa_input_event_from_handle(event),
                                                (size_t)index, (size_t)history_index, axis));
}

#undef XA_ME_GUARD
#undef XA_EV_GUARD

/* -- functional A4 sensors surface (W2d, A4 sensors head) ----------------- */

static XA_ASensorManager* xa_sensor_manager_from_handle(int64_t handle) {
    return (XA_ASensorManager*)(intptr_t)handle;
}

static const XA_ASensor* xa_sensor_from_handle(int64_t handle) {
    return (const XA_ASensor*)(intptr_t)handle;
}

static XA_ASensorEventQueue* xa_sensor_queue_from_handle(int64_t handle) {
    return (XA_ASensorEventQueue*)(intptr_t)handle;
}

int64_t xa_sensor_manager_get_instance(void) {
    if (!p_sensor_manager_get) {
        xa_set_error("ASensorManager_getInstance unresolved (runtime not loaded)");
        return 0;
    }
    XA_ASensorManager* m = p_sensor_manager_get();
    if (!m) { xa_set_error("ASensorManager_getInstance returned null"); return 0; }
    return (int64_t)(intptr_t)m;
}

int64_t xa_sensor_manager_get_instance_for_package(const char* package_name) {
    if (!p_sensor_manager_get_for_package) {
        xa_set_error("ASensorManager_getInstanceForPackage unresolved (needs API 26+)");
        return 0;
    }
    if (!package_name) { xa_set_error("null package name"); return 0; }
    XA_ASensorManager* m = p_sensor_manager_get_for_package(package_name);
    if (!m) {
        snprintf(g_error, sizeof(g_error), "no sensor manager for package %s", package_name);
        return 0;
    }
    return (int64_t)(intptr_t)m;
}

int32_t xa_sensor_manager_get_sensor_list(int64_t manager) {
    if (!p_sensor_get_list) {
        xa_set_error("ASensorManager_getSensorList unresolved (runtime not loaded)");
        return -1;
    }
    if (!manager) { xa_set_error("null sensor manager handle"); return -1; }
    XA_ASensorRef const* list = 0;
    int32_t n = p_sensor_get_list(xa_sensor_manager_from_handle(manager), &list);
    if (n < 0) { snprintf(g_error, sizeof(g_error), "ASensorManager_getSensorList rc=%d", n); return -1; }
    g_sensor_list = list;
    g_sensor_list_count = n;
    return n;
}

int32_t xa_sensor_manager_get_dynamic_sensor_list(int64_t manager) {
    if (!p_sensor_get_dyn_list) {
        xa_set_error("ASensorManager_getDynamicSensorList unresolved (needs API 33+)");
        return -1;
    }
    if (!manager) { xa_set_error("null sensor manager handle"); return -1; }
    XA_ASensorRef const* list = 0;
    int64_t n = p_sensor_get_dyn_list(xa_sensor_manager_from_handle(manager), &list);
    if (n < 0) { snprintf(g_error, sizeof(g_error), "ASensorManager_getDynamicSensorList rc=%lld", (long long)n); return -1; }
    g_sensor_dyn_list = list;
    g_sensor_dyn_list_count = (int32_t)n;
    return (int32_t)n;
}

int64_t xa_sensor_list_at(int32_t which, int32_t index) {
    XA_ASensorRef const* list = which == 1 ? g_sensor_dyn_list : g_sensor_list;
    int32_t count = which == 1 ? g_sensor_dyn_list_count : g_sensor_list_count;
    if (!list) { xa_set_error("sensor list not enumerated yet"); return 0; }
    if (index < 0 || index >= count) { xa_set_error("sensor list index out of range"); return 0; }
    return (int64_t)(intptr_t)list[index];
}

int64_t xa_sensor_manager_get_default_sensor(int64_t manager, int32_t sensor_type) {
    if (!p_sensor_get_default) {
        xa_set_error("ASensorManager_getDefaultSensor unresolved (runtime not loaded)");
        return 0;
    }
    if (!manager) { xa_set_error("null sensor manager handle"); return 0; }
    const XA_ASensor* s = p_sensor_get_default(xa_sensor_manager_from_handle(manager),
                                               (int)sensor_type);
    return (int64_t)(intptr_t)s; /* 0 = no sensor of this type (not an error) */
}

int64_t xa_sensor_manager_get_default_sensor_ex(int64_t manager, int32_t sensor_type,
                                                int32_t wake_up) {
    if (!p_sensor_get_default_ex) {
        xa_set_error("ASensorManager_getDefaultSensorEx unresolved (needs API 21+)");
        return 0;
    }
    if (!manager) { xa_set_error("null sensor manager handle"); return 0; }
    const XA_ASensor* s = p_sensor_get_default_ex(xa_sensor_manager_from_handle(manager),
                                                  (int)sensor_type, wake_up ? 1 : 0);
    return (int64_t)(intptr_t)s;
}

int64_t xa_sensor_manager_create_event_queue(int64_t manager, int64_t looper, int32_t ident,
                                             XA_LooperCallback cb, int64_t data) {
    if (!p_sensor_create_queue) {
        xa_set_error("ASensorManager_createEventQueue unresolved (runtime not loaded)");
        return 0;
    }
    if (!manager) { xa_set_error("null sensor manager handle"); return 0; }
    if (!looper) { xa_set_error("null looper handle"); return 0; }
    XA_ASensorEventQueue* q = p_sensor_create_queue(xa_sensor_manager_from_handle(manager),
                                                    xa_looper_from_handle(looper),
                                                    (int)ident, cb, (void*)(intptr_t)data);
    if (!q) { xa_set_error("ASensorManager_createEventQueue returned null"); return 0; }
    return (int64_t)(intptr_t)q;
}

int64_t xa_sensor_manager_create_event_queue_ident(int64_t manager, int64_t looper,
                                                   int32_t ident) {
    if (!p_sensor_create_queue) {
        xa_set_error("ASensorManager_createEventQueue unresolved (runtime not loaded)");
        return 0;
    }
    if (!manager) { xa_set_error("null sensor manager handle"); return 0; }
    if (!looper) { xa_set_error("null looper handle"); return 0; }
    XA_ASensorEventQueue* q = p_sensor_create_queue(xa_sensor_manager_from_handle(manager),
                                                    xa_looper_from_handle(looper),
                                                    (int)ident, 0, 0);
    if (!q) { xa_set_error("ASensorManager_createEventQueue returned null"); return 0; }
    return (int64_t)(intptr_t)q;
}

int32_t xa_sensor_manager_destroy_event_queue(int64_t manager, int64_t queue) {
    if (!p_sensor_destroy_queue) {
        xa_set_error("ASensorManager_destroyEventQueue unresolved (runtime not loaded)");
        return -1;
    }
    if (!manager || !queue) { xa_set_error("null sensor manager/queue handle"); return -1; }
    int32_t rc = p_sensor_destroy_queue(xa_sensor_manager_from_handle(manager),
                                        xa_sensor_queue_from_handle(queue));
    if (rc < 0) { snprintf(g_error, sizeof(g_error), "ASensorManager_destroyEventQueue rc=%d", rc); }
    return rc;
}

int32_t xa_sensor_manager_create_shared_memory_direct_channel(int64_t manager, int32_t fd,
                                                              int64_t size) {
    if (!p_sensor_create_shm_channel) {
        xa_set_error("ASensorManager_createSharedMemoryDirectChannel unresolved (needs API 26+)");
        return -1;
    }
    if (!manager) { xa_set_error("null sensor manager handle"); return -1; }
    if (fd < 0) { xa_set_error("null shm fd"); return -1; }
    if (size <= 0) { xa_set_error("channel size must be > 0"); return -1; }
    int32_t rc = p_sensor_create_shm_channel(xa_sensor_manager_from_handle(manager),
                                             (int)fd, (size_t)size);
    if (rc <= 0) { snprintf(g_error, sizeof(g_error), "ASensorManager_createSharedMemoryDirectChannel rc=%d", rc); }
    return rc;
}

int32_t xa_sensor_manager_create_hardware_buffer_direct_channel(int64_t manager, int64_t hwb,
                                                                int64_t size) {
    if (!p_sensor_create_hwb_channel) {
        xa_set_error("ASensorManager_createHardwareBufferDirectChannel unresolved (needs API 26+)");
        return -1;
    }
    if (!manager) { xa_set_error("null sensor manager handle"); return -1; }
    if (!hwb) { xa_set_error("null hwb handle"); return -1; }
    if (size <= 0) { xa_set_error("channel size must be > 0"); return -1; }
    int32_t rc = p_sensor_create_hwb_channel(xa_sensor_manager_from_handle(manager),
                                             (const void*)(intptr_t)hwb, (size_t)size);
    if (rc <= 0) { snprintf(g_error, sizeof(g_error), "ASensorManager_createHardwareBufferDirectChannel rc=%d", rc); }
    return rc;
}

int32_t xa_sensor_manager_destroy_direct_channel(int64_t manager, int32_t channel_id) {
    if (!p_sensor_destroy_channel) {
        xa_set_error("ASensorManager_destroyDirectChannel unresolved (needs API 26+)");
        return -1;
    }
    if (!manager) { xa_set_error("null sensor manager handle"); return -1; }
    p_sensor_destroy_channel(xa_sensor_manager_from_handle(manager), (int)channel_id);
    return 0;
}

int32_t xa_sensor_manager_configure_direct_report(int64_t manager, int64_t sensor,
                                                  int32_t channel_id, int32_t rate_level) {
    if (!p_sensor_configure_direct) {
        xa_set_error("ASensorManager_configureDirectReport unresolved (needs API 26+)");
        return -1;
    }
    if (!manager) { xa_set_error("null sensor manager handle"); return -1; }
    int32_t rc = p_sensor_configure_direct(xa_sensor_manager_from_handle(manager),
                                           sensor ? xa_sensor_from_handle(sensor) : 0,
                                           (int)channel_id, (int)rate_level);
    if (rc < 0) { snprintf(g_error, sizeof(g_error), "ASensorManager_configureDirectReport rc=%d", rc); }
    return rc;
}

int32_t xa_sensor_event_queue_register_sensor(int64_t queue, int64_t sensor,
                                              int32_t sampling_period_us,
                                              int64_t max_report_latency_us) {
    if (!p_sensor_queue_register) {
        xa_set_error("ASensorEventQueue_registerSensor unresolved (runtime not loaded)");
        return -1;
    }
    if (!queue || !sensor) { xa_set_error("null sensor queue/sensor handle"); return -1; }
    int32_t rc = p_sensor_queue_register(xa_sensor_queue_from_handle(queue),
                                         xa_sensor_from_handle(sensor),
                                         sampling_period_us, max_report_latency_us);
    if (rc < 0) { snprintf(g_error, sizeof(g_error), "ASensorEventQueue_registerSensor rc=%d", rc); }
    return rc;
}

int32_t xa_sensor_event_queue_enable_sensor(int64_t queue, int64_t sensor) {
    if (!p_sensor_queue_enable) {
        xa_set_error("ASensorEventQueue_enableSensor unresolved (runtime not loaded)");
        return -1;
    }
    if (!queue || !sensor) { xa_set_error("null sensor queue/sensor handle"); return -1; }
    int32_t rc = p_sensor_queue_enable(xa_sensor_queue_from_handle(queue),
                                       xa_sensor_from_handle(sensor));
    if (rc < 0) { snprintf(g_error, sizeof(g_error), "ASensorEventQueue_enableSensor rc=%d", rc); }
    return rc;
}

int32_t xa_sensor_event_queue_disable_sensor(int64_t queue, int64_t sensor) {
    if (!p_sensor_queue_disable) {
        xa_set_error("ASensorEventQueue_disableSensor unresolved (runtime not loaded)");
        return -1;
    }
    if (!queue || !sensor) { xa_set_error("null sensor queue/sensor handle"); return -1; }
    int32_t rc = p_sensor_queue_disable(xa_sensor_queue_from_handle(queue),
                                        xa_sensor_from_handle(sensor));
    if (rc < 0) { snprintf(g_error, sizeof(g_error), "ASensorEventQueue_disableSensor rc=%d", rc); }
    return rc;
}

int32_t xa_sensor_event_queue_set_event_rate(int64_t queue, int64_t sensor, int32_t usec) {
    if (!p_sensor_queue_set_rate) {
        xa_set_error("ASensorEventQueue_setEventRate unresolved (runtime not loaded)");
        return -1;
    }
    if (!queue || !sensor) { xa_set_error("null sensor queue/sensor handle"); return -1; }
    int32_t rc = p_sensor_queue_set_rate(xa_sensor_queue_from_handle(queue),
                                         xa_sensor_from_handle(sensor), usec);
    if (rc < 0) { snprintf(g_error, sizeof(g_error), "ASensorEventQueue_setEventRate rc=%d", rc); }
    return rc;
}

int32_t xa_sensor_event_queue_has_events(int64_t queue) {
    if (!p_sensor_queue_has_events) {
        xa_set_error("ASensorEventQueue_hasEvents unresolved (runtime not loaded)");
        return -1;
    }
    if (!queue) { xa_set_error("null sensor queue handle"); return -1; }
    return (int32_t)p_sensor_queue_has_events(xa_sensor_queue_from_handle(queue));
}

int32_t xa_sensor_event_queue_request_additional_info_events(int64_t queue, int32_t enable) {
    if (!p_sensor_queue_request_info) {
        xa_set_error("ASensorEventQueue_requestAdditionalInfoEvents unresolved (needs API 29+)");
        return -1;
    }
    if (!queue) { xa_set_error("null sensor queue handle"); return -1; }
    int32_t rc = p_sensor_queue_request_info(xa_sensor_queue_from_handle(queue),
                                             enable ? 1 : 0);
    if (rc < 0) { snprintf(g_error, sizeof(g_error), "ASensorEventQueue_requestAdditionalInfoEvents rc=%d", rc); }
    return rc;
}

int32_t xa_sensor_event_queue_read(int64_t queue, int32_t max_count) {
    if (!p_sensor_queue_get_events) {
        xa_set_error("ASensorEventQueue_getEvents unresolved (runtime not loaded)");
        return -1;
    }
    if (!queue) { xa_set_error("null sensor queue handle"); return -1; }
    if (max_count <= 0) { xa_set_error("max_count must be > 0"); return -1; }
    if (max_count > XA_SENSOR_EVENT_SLOTS) max_count = XA_SENSOR_EVENT_SLOTS;
    g_sensor_event_count = 0;
    int64_t n = p_sensor_queue_get_events(xa_sensor_queue_from_handle(queue),
                                          g_sensor_events, (size_t)max_count);
    if (n < 0) { snprintf(g_error, sizeof(g_error), "ASensorEventQueue_getEvents rc=%lld", (long long)n); return -1; }
    if (n > max_count) n = max_count;
    g_sensor_event_count = (int32_t)n;
    return (int32_t)n;
}

/* Slot accessors; every one bounds-checks against the last read. */
static const XA_ASensorEvent* xa_sensor_event_slot(int32_t index) {
    if (index < 0 || index >= g_sensor_event_count) {
        xa_set_error("sensor event slot out of range (read more events first)");
        return 0;
    }
    return &g_sensor_events[index];
}

int32_t xa_sensor_event_version(int32_t index) {
    const XA_ASensorEvent* e = xa_sensor_event_slot(index);
    return e ? (int32_t)e->version : -1;
}

int32_t xa_sensor_event_sensor(int32_t index) {
    const XA_ASensorEvent* e = xa_sensor_event_slot(index);
    return e ? (int32_t)e->sensor : -1;
}

int32_t xa_sensor_event_type(int32_t index) {
    const XA_ASensorEvent* e = xa_sensor_event_slot(index);
    return e ? (int32_t)e->type : -1;
}

int64_t xa_sensor_event_timestamp(int32_t index) {
    const XA_ASensorEvent* e = xa_sensor_event_slot(index);
    return e ? (int64_t)e->timestamp : -1;
}

int32_t xa_sensor_event_flags(int32_t index) {
    const XA_ASensorEvent* e = xa_sensor_event_slot(index);
    return e ? (int32_t)e->flags : -1;
}

int64_t xa_sensor_event_x_bits(int32_t index) {
    const XA_ASensorEvent* e = xa_sensor_event_slot(index);
    return e ? xa_f32_bits(e->u.data[0]) : -1;
}

int64_t xa_sensor_event_y_bits(int32_t index) {
    const XA_ASensorEvent* e = xa_sensor_event_slot(index);
    return e ? xa_f32_bits(e->u.data[1]) : -1;
}

int64_t xa_sensor_event_z_bits(int32_t index) {
    const XA_ASensorEvent* e = xa_sensor_event_slot(index);
    return e ? xa_f32_bits(e->u.data[2]) : -1;
}

int64_t xa_sensor_event_scalar_bits(int32_t index) {
    const XA_ASensorEvent* e = xa_sensor_event_slot(index);
    return e ? xa_f32_bits(e->u.data[0]) : -1;
}

int32_t xa_sensor_event_status(int32_t index) {
    const XA_ASensorEvent* e = xa_sensor_event_slot(index);
    if (!e) return -2; /* -2 = slot error (status -1 is a legal value) */
    /* ASensorVector: 3 f32 + int8 status at byte offset 12. */
    return (int32_t)((const int8_t*)&e->u.data[3])[0];
}

int64_t xa_sensor_event_step_counter(int32_t index) {
    const XA_ASensorEvent* e = xa_sensor_event_slot(index);
    return e ? (int64_t)e->u.u64[0] : -1;
}

int32_t xa_sensor_event_meta_what(int32_t index) {
    const XA_ASensorEvent* e = xa_sensor_event_slot(index);
    if (!e) return -1;
    /* AMetaDataEvent: { int32 what; int32 sensor; } over the union. */
    int32_t what;
    memcpy(&what, &e->u.data[0], sizeof(what));
    return what;
}

int64_t xa_sensor_event_heart_rate_bpm_bits(int32_t index) {
    const XA_ASensorEvent* e = xa_sensor_event_slot(index);
    return e ? xa_f32_bits(e->u.data[0]) : -1;
}

/* ASensor metadata accessors. */

static const char* xa_sensor_str(const char* (*p)(const XA_ASensor*), int64_t sensor) {
    if (!p) { xa_set_error("ASensor accessor unresolved (runtime not loaded)"); return ""; }
    if (!sensor) { xa_set_error("null sensor handle"); return ""; }
    const char* s = p(xa_sensor_from_handle(sensor));
    return s ? s : "";
}

const char* xa_sensor_name(int64_t sensor) {
    return xa_sensor_str(p_sensor_get_name, sensor);
}

const char* xa_sensor_vendor(int64_t sensor) {
    return xa_sensor_str(p_sensor_get_vendor, sensor);
}

const char* xa_sensor_string_type(int64_t sensor) {
    return xa_sensor_str(p_sensor_get_string_type, sensor);
}

#define XA_SENSOR_INT_FN(name, field) \
int32_t xa_sensor_##name(int64_t sensor) { \
    if (!p_sensor_##field) { xa_set_error("ASensor accessor unresolved (runtime not loaded)"); return -1; } \
    if (!sensor) { xa_set_error("null sensor handle"); return -1; } \
    return (int32_t)p_sensor_##field(xa_sensor_from_handle(sensor)); \
}

XA_SENSOR_INT_FN(type, get_type)
XA_SENSOR_INT_FN(min_delay, get_min_delay)
XA_SENSOR_INT_FN(fifo_max_event_count, get_fifo_max)
XA_SENSOR_INT_FN(fifo_reserved_event_count, get_fifo_reserved)
XA_SENSOR_INT_FN(reporting_mode, get_reporting_mode)
XA_SENSOR_INT_FN(highest_direct_report_rate_level, get_highest_direct_rate)
XA_SENSOR_INT_FN(handle, get_handle)
XA_SENSOR_INT_FN(is_wake_up_sensor, is_wake_up)
#undef XA_SENSOR_INT_FN

int64_t xa_sensor_resolution_bits(int64_t sensor) {
    if (!p_sensor_get_resolution) {
        xa_set_error("ASensor accessor unresolved (runtime not loaded)");
        return -1;
    }
    if (!sensor) { xa_set_error("null sensor handle"); return -1; }
    return xa_f32_bits(p_sensor_get_resolution(xa_sensor_from_handle(sensor)));
}

int32_t xa_sensor_is_direct_channel_type_supported(int64_t sensor, int32_t channel_type) {
    if (!p_sensor_is_direct_channel_supported) {
        xa_set_error("ASensor_isDirectChannelTypeSupported unresolved (needs API 26+)");
        return 0;
    }
    if (!sensor) { xa_set_error("null sensor handle"); return 0; }
    return (int32_t)p_sensor_is_direct_channel_supported(xa_sensor_from_handle(sensor),
                                                         (int)channel_type);
}

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
    /* A3 input head (W2d) */
    p_input_queue_attach = 0; p_input_queue_detach = 0;
    p_input_queue_has_events = 0; p_input_event_get = 0;
    p_input_event_pre_dispatch = 0; p_input_event_finish = 0;
    p_input_event_release = 0;
    p_ie_get_type = 0; p_ie_get_device_id = 0; p_ie_get_source = 0;
    p_ke_get_action = 0; p_ke_get_flags = 0; p_ke_get_key_code = 0;
    p_ke_get_scan_code = 0; p_ke_get_meta_state = 0; p_ke_get_repeat_count = 0;
    p_ke_get_down_time = 0; p_ke_get_event_time = 0;
    p_me_get_action = 0; p_me_get_flags = 0; p_me_get_meta_state = 0;
    p_me_get_button_state = 0; p_me_get_edge_flags = 0;
    p_me_get_down_time = 0; p_me_get_event_time = 0;
    p_me_get_x_offset = 0; p_me_get_y_offset = 0;
    p_me_get_x_precision = 0; p_me_get_y_precision = 0;
    p_me_get_pointer_count = 0; p_me_get_pointer_id = 0; p_me_get_tool_type = 0;
    p_me_get_raw_x = 0; p_me_get_raw_y = 0; p_me_get_x = 0; p_me_get_y = 0;
    p_me_get_pressure = 0; p_me_get_size = 0;
    p_me_get_touch_major = 0; p_me_get_touch_minor = 0;
    p_me_get_tool_major = 0; p_me_get_tool_minor = 0;
    p_me_get_orientation = 0; p_me_get_axis_value = 0;
    p_me_get_history_size = 0; p_me_get_hist_event_time = 0;
    p_me_get_hist_raw_x = 0; p_me_get_hist_raw_y = 0;
    p_me_get_hist_x = 0; p_me_get_hist_y = 0;
    p_me_get_hist_pressure = 0; p_me_get_hist_size = 0;
    p_me_get_hist_touch_major = 0; p_me_get_hist_touch_minor = 0;
    p_me_get_hist_tool_major = 0; p_me_get_hist_tool_minor = 0;
    p_me_get_hist_orientation = 0; p_me_get_hist_axis_value = 0;
    p_me_get_action_button = 0; p_me_get_classification = 0;
    /* A4 sensors head (W2d) */
    p_sensor_manager_get = 0; p_sensor_manager_get_for_package = 0;
    p_sensor_get_list = 0; p_sensor_get_dyn_list = 0;
    p_sensor_get_default = 0; p_sensor_get_default_ex = 0;
    p_sensor_create_queue = 0; p_sensor_destroy_queue = 0;
    p_sensor_create_shm_channel = 0; p_sensor_create_hwb_channel = 0;
    p_sensor_destroy_channel = 0; p_sensor_configure_direct = 0;
    p_sensor_queue_register = 0; p_sensor_queue_enable = 0;
    p_sensor_queue_disable = 0; p_sensor_queue_set_rate = 0;
    p_sensor_queue_has_events = 0; p_sensor_queue_get_events = 0;
    p_sensor_queue_request_info = 0;
    p_sensor_get_name = 0; p_sensor_get_vendor = 0; p_sensor_get_type = 0;
    p_sensor_get_resolution = 0; p_sensor_get_min_delay = 0;
    p_sensor_get_fifo_max = 0; p_sensor_get_fifo_reserved = 0;
    p_sensor_get_string_type = 0; p_sensor_get_reporting_mode = 0;
    p_sensor_get_highest_direct_rate = 0; p_sensor_get_handle = 0;
    p_sensor_is_wake_up = 0; p_sensor_is_direct_channel_supported = 0;
    g_sensor_list = 0; g_sensor_list_count = 0;
    g_sensor_dyn_list = 0; g_sensor_dyn_list_count = 0;
    g_sensor_event_count = 0;
    g_missing_count = 0;
    g_missing[0] = 0;
}
