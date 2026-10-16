/* XIOM -- xiom.aaudio: libaaudio.so runtime bridge.
 * Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
 * Licensed under the MIT or Apache-2.0 license, at your option.
 *
 * DESIGN: runtime loader/probe + functional head for the A6 AAudio slice
 * (aaudio/AAudio.h of NDK r27b).  No link-time dependency.  On Windows
 * everything classifies as ABSENT (SKIP) via LoadLibraryA; on Android/
 * Linux the library loads via dlopen, the declared 67-symbol export set
 * is verified (ABI stage) and the builder/stream head runs functionally.
 *
 * Contract (flat extern "C", called from module xiom.aaudio):
 *   int         xaa_load_named(const char* soname)   0=ok 1=absent 2=abi
 *   int         xaa_load(void)                       "libaaudio.so"
 *   int         xaa_loaded(void)                     1 while a handle is held
 *   const char* xaa_error(void)                      last error summary
 *   int         xaa_abi_missing_count(void)          unresolved export count
 *   const char* xaa_abi_missing(void)                comma-joined names
 *   int64       xaa_builder_create(void)             handle; 0 = failed
 *   int32       xaa_builder_delete(int64 builder)
 *   void        xaa_builder_set_* (int64 builder, ...) 26 builder setters
 *   int64       xaa_builder_open_stream(int64 builder)  stream; 0 = failed
 *   int32       xaa_open_result(void)                last openStream code
 *   int32       xaa_stream_* (int64 stream, ...)     39 stream functions
 *   int32       xaa_stream_wait_for_state_change(int64, int32, int64)
 *   int32       xaa_wait_state_value(void)           next state from wait
 *   int32       xaa_stream_read/write(int64, int32 frames, int64 timeout)
 *   int32       xaa_stream_get_timestamp(int64, int32 clock_id)
 *   int64       xaa_timestamp_frames(void) / xaa_timestamp_nanos(void)
 *   const char* xaa_convert_result_to_text(int32)
 *   const char* xaa_convert_stream_state_to_text(int32)
 *   int32       xaa_data_callback_count(void) / xaa_error_callback_count(void)
 *   void        xaa_unload(void)
 *
 * Classification (the suite maps it to markers):
 *   XAA_LOAD_ABSENT (1) -> SKIP  (runtime absent; CI stays green)
 *   XAA_LOAD_ABI    (2) -> FAIL  (present but exports broken; never silent)
 *
 * Pointers never cross the boundary (B-25 discipline): stream/builder
 * handles are int64; the read/write data window, the waitForStateChange
 * next-state slot and the getTimestamp out-params live entirely inside
 * this file and are read back through scalar accessors.  Callbacks are
 * top-level stubs handed to AAudio directly (direct handoff).
 */

#include <stdint.h>
#include <stdio.h>
#include <string.h>

#if defined(_WIN32)
#include <windows.h>
typedef HMODULE xaa_lib_t;
static xaa_lib_t xaa_dlopen(const char* name) { return LoadLibraryA(name); }
static void* xaa_dlsym(xaa_lib_t h, const char* name) {
    return h ? (void*)GetProcAddress(h, name) : 0;
}
static void xaa_dlclose(xaa_lib_t h) { if (h) FreeLibrary(h); }
#else
#include <dlfcn.h>
typedef void* xaa_lib_t;
static xaa_lib_t xaa_dlopen(const char* name) { return dlopen(name, RTLD_NOW | RTLD_LOCAL); }
static void* xaa_dlsym(xaa_lib_t h, const char* name) { return h ? dlsym(h, name) : 0; }
static void xaa_dlclose(xaa_lib_t h) { if (h) dlclose(h); }
#endif

/* -- pinned ABI facts (aaudio/AAudio.h, NDK r27b) ------------------------ */

typedef struct XAA_Stream XAA_Stream;
typedef struct XAA_Builder XAA_Builder;

/* aaudio_result_t / aaudio_stream_state_t / aaudio_format_t are int32_t;
 * the callback prototypes are literal transcriptions of the header
 * typedefs (AAudioStream_dataCallback / AAudioStream_errorCallback). */
#define XAA_OK 0
#define XAA_E_UNIMPLEMENTED (-890)
#define XAA_E_NULL (-886)
#define XAA_E_ILLEGAL_ARGUMENT (-898)
#define XAA_E_INVALID_STATE (-895)

typedef const char* (*PFN_convert)(int32_t);
typedef int32_t (*PFN_create)(XAA_Builder**);
typedef void (*PFN_b_set_i32)(XAA_Builder*, int32_t);
typedef void (*PFN_b_set_bool)(XAA_Builder*, unsigned char); /* C bool = 1 byte */
typedef void (*PFN_b_set_str)(XAA_Builder*, const char*);
typedef int32_t (*XAA_data_cb_t)(XAA_Stream*, void*, void*, int32_t);
typedef void (*XAA_error_cb_t)(XAA_Stream*, void*, int32_t);
typedef void (*PFN_b_install_data_cb)(XAA_Builder*, XAA_data_cb_t, void*);
typedef void (*PFN_b_install_error_cb)(XAA_Builder*, XAA_error_cb_t, void*);
typedef int32_t (*PFN_b_open)(XAA_Builder*, XAA_Stream**);
typedef int32_t (*PFN_b_delete)(XAA_Builder*);
typedef int32_t (*PFN_s_noarg)(XAA_Stream*);
typedef int32_t (*PFN_s_i32)(XAA_Stream*, int32_t);
typedef int32_t (*PFN_s_wait)(XAA_Stream*, int32_t, int32_t*, int64_t);
typedef int32_t (*PFN_s_read)(XAA_Stream*, void*, int32_t, int64_t);
typedef int32_t (*PFN_s_write)(XAA_Stream*, const void*, int32_t, int64_t);
typedef int32_t (*PFN_s_ts)(XAA_Stream*, int32_t, int64_t*, int64_t*);
typedef int64_t (*PFN_s_get64)(XAA_Stream*);
typedef unsigned char (*PFN_s_getbool)(XAA_Stream*); /* C bool = 1 byte */

/* -- bridge state -------------------------------------------------------- */

static xaa_lib_t g_lib = 0;
static char g_error[512] = {0};
static char g_missing[4096] = {0};
static int g_missing_count = 0;
static int32_t g_open_result = 0;
static int32_t g_wait_state = 0;
static int64_t g_ts_frames = 0;
static int64_t g_ts_nanos = 0;
static volatile int32_t g_data_cb_count = 0;
static volatile int32_t g_error_cb_count = 0;

/* Scratch window for read/write: no pointer ever crosses the boundary.
 * Worst-case frame stride covered: 8 channels * 4-byte samples = 32 B. */
#define XAA_SCRATCH_FRAMES 8192
static uint8_t g_scratch[XAA_SCRATCH_FRAMES * 32];

void xaa_unload(void); /* defined at the bottom; used by xaa_load_pair */

static void xaa_set_error(const char* msg) {
    snprintf(g_error, sizeof(g_error), "%s", msg);
}

/* -- top-level callbacks (direct handoff; no env, no registry) ----------- */

/* Output silence: the driver configures PCM_I16 stereo, i.e. 4 bytes per
 * frame.  Zero-filling fewer bytes than the buffer holds is always safe;
 * never write more than numFrames * bytesPerFrame. */
static int32_t xaa_data_callback_stub(XAA_Stream* stream, void* user_data,
                                      void* audio_data, int32_t num_frames) {
    (void)stream;
    (void)user_data;
    if (audio_data && num_frames > 0) {
        memset(audio_data, 0, (size_t)num_frames * 4u);
    }
    g_data_cb_count++;
    return 0; /* AAUDIO_CALLBACK_RESULT_CONTINUE */
}

static void xaa_error_callback_stub(XAA_Stream* stream, void* user_data, int32_t error) {
    (void)stream;
    (void)user_data;
    (void)error;
    g_error_cb_count++;
}

/* -- export set (67 AAUDIO_API declarations of aaudio/AAudio.h) ---------- */

static const char* k_export_set[] = {
    /* Audio system (3) */
    "AAudio_convertResultToText",
    "AAudio_convertStreamStateToText",
    "AAudio_createStreamBuilder",
    /* StreamBuilder (25) */
    "AAudioStreamBuilder_setDeviceId",
    "AAudioStreamBuilder_setPackageName",
    "AAudioStreamBuilder_setAttributionTag",
    "AAudioStreamBuilder_setSampleRate",
    "AAudioStreamBuilder_setChannelCount",
    "AAudioStreamBuilder_setSamplesPerFrame",
    "AAudioStreamBuilder_setFormat",
    "AAudioStreamBuilder_setSharingMode",
    "AAudioStreamBuilder_setDirection",
    "AAudioStreamBuilder_setBufferCapacityInFrames",
    "AAudioStreamBuilder_setPerformanceMode",
    "AAudioStreamBuilder_setUsage",
    "AAudioStreamBuilder_setContentType",
    "AAudioStreamBuilder_setSpatializationBehavior",
    "AAudioStreamBuilder_setIsContentSpatialized",
    "AAudioStreamBuilder_setInputPreset",
    "AAudioStreamBuilder_setAllowedCapturePolicy",
    "AAudioStreamBuilder_setSessionId",
    "AAudioStreamBuilder_setPrivacySensitive",
    "AAudioStreamBuilder_setDataCallback",
    "AAudioStreamBuilder_setFramesPerDataCallback",
    "AAudioStreamBuilder_setErrorCallback",
    "AAudioStreamBuilder_openStream",
    "AAudioStreamBuilder_delete",
    "AAudioStreamBuilder_setChannelMask",
    /* Stream (39) */
    "AAudioStream_release",
    "AAudioStream_close",
    "AAudioStream_requestStart",
    "AAudioStream_requestPause",
    "AAudioStream_requestFlush",
    "AAudioStream_requestStop",
    "AAudioStream_getState",
    "AAudioStream_waitForStateChange",
    "AAudioStream_read",
    "AAudioStream_write",
    "AAudioStream_setBufferSizeInFrames",
    "AAudioStream_getBufferSizeInFrames",
    "AAudioStream_getFramesPerBurst",
    "AAudioStream_getBufferCapacityInFrames",
    "AAudioStream_getFramesPerDataCallback",
    "AAudioStream_getXRunCount",
    "AAudioStream_getSampleRate",
    "AAudioStream_getHardwareSampleRate",
    "AAudioStream_getChannelCount",
    "AAudioStream_getHardwareChannelCount",
    "AAudioStream_getSamplesPerFrame",
    "AAudioStream_getDeviceId",
    "AAudioStream_getFormat",
    "AAudioStream_getHardwareFormat",
    "AAudioStream_getSharingMode",
    "AAudioStream_getPerformanceMode",
    "AAudioStream_getDirection",
    "AAudioStream_getFramesWritten",
    "AAudioStream_getFramesRead",
    "AAudioStream_getSessionId",
    "AAudioStream_getTimestamp",
    "AAudioStream_getUsage",
    "AAudioStream_getContentType",
    "AAudioStream_getSpatializationBehavior",
    "AAudioStream_isContentSpatialized",
    "AAudioStream_getInputPreset",
    "AAudioStream_getAllowedCapturePolicy",
    "AAudioStream_isPrivacySensitive",
    "AAudioStream_getChannelMask",
};
#define XAA_EXPORT_COUNT (sizeof(k_export_set) / sizeof(k_export_set[0]))
/* Compile-time guard: the declared surface is exactly the 67 exports
 * measured in aaudio/AAudio.h (NDK r27b). */
typedef char xaa_export_count_must_be_67[(XAA_EXPORT_COUNT == 67) ? 1 : -1];

/* -- resolved function pointers ------------------------------------------ */

static PFN_convert p_convert_result = 0;
static PFN_convert p_convert_state = 0;
static PFN_create p_create = 0;
static PFN_b_set_i32 p_set_device_id = 0;
static PFN_b_set_str p_set_package_name = 0;
static PFN_b_set_str p_set_attribution_tag = 0;
static PFN_b_set_i32 p_set_sample_rate = 0;
static PFN_b_set_i32 p_set_channel_count = 0;
static PFN_b_set_i32 p_set_samples_per_frame = 0;
static PFN_b_set_i32 p_set_format = 0;
static PFN_b_set_i32 p_set_sharing_mode = 0;
static PFN_b_set_i32 p_set_direction = 0;
static PFN_b_set_i32 p_set_buffer_capacity = 0;
static PFN_b_set_i32 p_set_performance_mode = 0;
static PFN_b_set_i32 p_set_usage = 0;
static PFN_b_set_i32 p_set_content_type = 0;
static PFN_b_set_i32 p_set_spatialization = 0;
static PFN_b_set_bool p_set_is_spatialized = 0;
static PFN_b_set_i32 p_set_input_preset = 0;
static PFN_b_set_i32 p_set_capture_policy = 0;
static PFN_b_set_i32 p_set_session_id = 0;
static PFN_b_set_bool p_set_privacy = 0;
static PFN_b_install_data_cb p_install_data_cb = 0;
static PFN_b_set_i32 p_set_frames_per_cb = 0;
static PFN_b_install_error_cb p_install_error_cb = 0;
static PFN_b_open p_open = 0;
static PFN_b_delete p_delete = 0;
static PFN_b_set_i32 p_set_channel_mask = 0;
static PFN_s_noarg p_release = 0;
static PFN_s_noarg p_close = 0;
static PFN_s_noarg p_request_start = 0;
static PFN_s_noarg p_request_pause = 0;
static PFN_s_noarg p_request_flush = 0;
static PFN_s_noarg p_request_stop = 0;
static PFN_s_noarg p_get_state = 0;
static PFN_s_wait p_wait = 0;
static PFN_s_read p_read = 0;
static PFN_s_write p_write = 0;
static PFN_s_i32 p_set_buffer_size = 0;
static PFN_s_noarg p_get_buffer_size = 0;
static PFN_s_noarg p_get_frames_per_burst = 0;
static PFN_s_noarg p_get_buffer_capacity = 0;
static PFN_s_noarg p_get_frames_per_cb = 0;
static PFN_s_noarg p_get_xrun_count = 0;
static PFN_s_noarg p_get_sample_rate = 0;
static PFN_s_noarg p_get_hw_sample_rate = 0;
static PFN_s_noarg p_get_channel_count = 0;
static PFN_s_noarg p_get_hw_channel_count = 0;
static PFN_s_noarg p_get_samples_per_frame = 0;
static PFN_s_noarg p_get_device_id = 0;
static PFN_s_noarg p_get_format = 0;
static PFN_s_noarg p_get_hw_format = 0;
static PFN_s_noarg p_get_sharing_mode = 0;
static PFN_s_noarg p_get_performance_mode = 0;
static PFN_s_noarg p_get_direction = 0;
static PFN_s_get64 p_get_frames_written = 0;
static PFN_s_get64 p_get_frames_read = 0;
static PFN_s_noarg p_get_session_id = 0;
static PFN_s_ts p_get_timestamp = 0;
static PFN_s_noarg p_get_usage = 0;
static PFN_s_noarg p_get_content_type = 0;
static PFN_s_noarg p_get_spatialization = 0;
static PFN_s_getbool p_is_content_spatialized = 0;
static PFN_s_noarg p_get_input_preset = 0;
static PFN_s_noarg p_get_capture_policy = 0;
static PFN_s_getbool p_is_privacy_sensitive = 0;
static PFN_s_noarg p_get_channel_mask = 0;

/* -- load / classify ----------------------------------------------------- */

static int xaa_finish_load(void) {
    g_missing_count = 0;
    g_missing[0] = 0;
    for (size_t i = 0; i < XAA_EXPORT_COUNT; i++) {
        if (!xaa_dlsym(g_lib, k_export_set[i])) {
            size_t used = strlen(g_missing);
            snprintf(g_missing + used, sizeof(g_missing) - used, "%s%s",
                     used ? "," : "", k_export_set[i]);
            g_missing_count++;
        }
    }
    p_convert_result = (PFN_convert)xaa_dlsym(g_lib, "AAudio_convertResultToText");
    p_convert_state = (PFN_convert)xaa_dlsym(g_lib, "AAudio_convertStreamStateToText");
    p_create = (PFN_create)xaa_dlsym(g_lib, "AAudio_createStreamBuilder");
    p_set_device_id = (PFN_b_set_i32)xaa_dlsym(g_lib, "AAudioStreamBuilder_setDeviceId");
    p_set_package_name = (PFN_b_set_str)xaa_dlsym(g_lib, "AAudioStreamBuilder_setPackageName");
    p_set_attribution_tag = (PFN_b_set_str)xaa_dlsym(g_lib, "AAudioStreamBuilder_setAttributionTag");
    p_set_sample_rate = (PFN_b_set_i32)xaa_dlsym(g_lib, "AAudioStreamBuilder_setSampleRate");
    p_set_channel_count = (PFN_b_set_i32)xaa_dlsym(g_lib, "AAudioStreamBuilder_setChannelCount");
    p_set_samples_per_frame = (PFN_b_set_i32)xaa_dlsym(g_lib, "AAudioStreamBuilder_setSamplesPerFrame");
    p_set_format = (PFN_b_set_i32)xaa_dlsym(g_lib, "AAudioStreamBuilder_setFormat");
    p_set_sharing_mode = (PFN_b_set_i32)xaa_dlsym(g_lib, "AAudioStreamBuilder_setSharingMode");
    p_set_direction = (PFN_b_set_i32)xaa_dlsym(g_lib, "AAudioStreamBuilder_setDirection");
    p_set_buffer_capacity = (PFN_b_set_i32)xaa_dlsym(g_lib, "AAudioStreamBuilder_setBufferCapacityInFrames");
    p_set_performance_mode = (PFN_b_set_i32)xaa_dlsym(g_lib, "AAudioStreamBuilder_setPerformanceMode");
    p_set_usage = (PFN_b_set_i32)xaa_dlsym(g_lib, "AAudioStreamBuilder_setUsage");
    p_set_content_type = (PFN_b_set_i32)xaa_dlsym(g_lib, "AAudioStreamBuilder_setContentType");
    p_set_spatialization = (PFN_b_set_i32)xaa_dlsym(g_lib, "AAudioStreamBuilder_setSpatializationBehavior");
    p_set_is_spatialized = (PFN_b_set_bool)xaa_dlsym(g_lib, "AAudioStreamBuilder_setIsContentSpatialized");
    p_set_input_preset = (PFN_b_set_i32)xaa_dlsym(g_lib, "AAudioStreamBuilder_setInputPreset");
    p_set_capture_policy = (PFN_b_set_i32)xaa_dlsym(g_lib, "AAudioStreamBuilder_setAllowedCapturePolicy");
    p_set_session_id = (PFN_b_set_i32)xaa_dlsym(g_lib, "AAudioStreamBuilder_setSessionId");
    p_set_privacy = (PFN_b_set_bool)xaa_dlsym(g_lib, "AAudioStreamBuilder_setPrivacySensitive");
    p_install_data_cb = (PFN_b_install_data_cb)xaa_dlsym(g_lib, "AAudioStreamBuilder_setDataCallback");
    p_set_frames_per_cb = (PFN_b_set_i32)xaa_dlsym(g_lib, "AAudioStreamBuilder_setFramesPerDataCallback");
    p_install_error_cb = (PFN_b_install_error_cb)xaa_dlsym(g_lib, "AAudioStreamBuilder_setErrorCallback");
    p_open = (PFN_b_open)xaa_dlsym(g_lib, "AAudioStreamBuilder_openStream");
    p_delete = (PFN_b_delete)xaa_dlsym(g_lib, "AAudioStreamBuilder_delete");
    p_set_channel_mask = (PFN_b_set_i32)xaa_dlsym(g_lib, "AAudioStreamBuilder_setChannelMask");
    p_release = (PFN_s_noarg)xaa_dlsym(g_lib, "AAudioStream_release");
    p_close = (PFN_s_noarg)xaa_dlsym(g_lib, "AAudioStream_close");
    p_request_start = (PFN_s_noarg)xaa_dlsym(g_lib, "AAudioStream_requestStart");
    p_request_pause = (PFN_s_noarg)xaa_dlsym(g_lib, "AAudioStream_requestPause");
    p_request_flush = (PFN_s_noarg)xaa_dlsym(g_lib, "AAudioStream_requestFlush");
    p_request_stop = (PFN_s_noarg)xaa_dlsym(g_lib, "AAudioStream_requestStop");
    p_get_state = (PFN_s_noarg)xaa_dlsym(g_lib, "AAudioStream_getState");
    p_wait = (PFN_s_wait)xaa_dlsym(g_lib, "AAudioStream_waitForStateChange");
    p_read = (PFN_s_read)xaa_dlsym(g_lib, "AAudioStream_read");
    p_write = (PFN_s_write)xaa_dlsym(g_lib, "AAudioStream_write");
    p_set_buffer_size = (PFN_s_i32)xaa_dlsym(g_lib, "AAudioStream_setBufferSizeInFrames");
    p_get_buffer_size = (PFN_s_noarg)xaa_dlsym(g_lib, "AAudioStream_getBufferSizeInFrames");
    p_get_frames_per_burst = (PFN_s_noarg)xaa_dlsym(g_lib, "AAudioStream_getFramesPerBurst");
    p_get_buffer_capacity = (PFN_s_noarg)xaa_dlsym(g_lib, "AAudioStream_getBufferCapacityInFrames");
    p_get_frames_per_cb = (PFN_s_noarg)xaa_dlsym(g_lib, "AAudioStream_getFramesPerDataCallback");
    p_get_xrun_count = (PFN_s_noarg)xaa_dlsym(g_lib, "AAudioStream_getXRunCount");
    p_get_sample_rate = (PFN_s_noarg)xaa_dlsym(g_lib, "AAudioStream_getSampleRate");
    p_get_hw_sample_rate = (PFN_s_noarg)xaa_dlsym(g_lib, "AAudioStream_getHardwareSampleRate");
    p_get_channel_count = (PFN_s_noarg)xaa_dlsym(g_lib, "AAudioStream_getChannelCount");
    p_get_hw_channel_count = (PFN_s_noarg)xaa_dlsym(g_lib, "AAudioStream_getHardwareChannelCount");
    p_get_samples_per_frame = (PFN_s_noarg)xaa_dlsym(g_lib, "AAudioStream_getSamplesPerFrame");
    p_get_device_id = (PFN_s_noarg)xaa_dlsym(g_lib, "AAudioStream_getDeviceId");
    p_get_format = (PFN_s_noarg)xaa_dlsym(g_lib, "AAudioStream_getFormat");
    p_get_hw_format = (PFN_s_noarg)xaa_dlsym(g_lib, "AAudioStream_getHardwareFormat");
    p_get_sharing_mode = (PFN_s_noarg)xaa_dlsym(g_lib, "AAudioStream_getSharingMode");
    p_get_performance_mode = (PFN_s_noarg)xaa_dlsym(g_lib, "AAudioStream_getPerformanceMode");
    p_get_direction = (PFN_s_noarg)xaa_dlsym(g_lib, "AAudioStream_getDirection");
    p_get_frames_written = (PFN_s_get64)xaa_dlsym(g_lib, "AAudioStream_getFramesWritten");
    p_get_frames_read = (PFN_s_get64)xaa_dlsym(g_lib, "AAudioStream_getFramesRead");
    p_get_session_id = (PFN_s_noarg)xaa_dlsym(g_lib, "AAudioStream_getSessionId");
    p_get_timestamp = (PFN_s_ts)xaa_dlsym(g_lib, "AAudioStream_getTimestamp");
    p_get_usage = (PFN_s_noarg)xaa_dlsym(g_lib, "AAudioStream_getUsage");
    p_get_content_type = (PFN_s_noarg)xaa_dlsym(g_lib, "AAudioStream_getContentType");
    p_get_spatialization = (PFN_s_noarg)xaa_dlsym(g_lib, "AAudioStream_getSpatializationBehavior");
    p_is_content_spatialized = (PFN_s_getbool)xaa_dlsym(g_lib, "AAudioStream_isContentSpatialized");
    p_get_input_preset = (PFN_s_noarg)xaa_dlsym(g_lib, "AAudioStream_getInputPreset");
    p_get_capture_policy = (PFN_s_noarg)xaa_dlsym(g_lib, "AAudioStream_getAllowedCapturePolicy");
    p_is_privacy_sensitive = (PFN_s_getbool)xaa_dlsym(g_lib, "AAudioStream_isPrivacySensitive");
    p_get_channel_mask = (PFN_s_noarg)xaa_dlsym(g_lib, "AAudioStream_getChannelMask");
    if (g_missing_count != 0) {
        xaa_set_error(g_missing);
        return 2;
    }
    xaa_set_error("");
    return 0;
}

static int xaa_load_pair(const char* soname) {
    xaa_unload();
    g_lib = xaa_dlopen(soname);
    if (!g_lib) {
        snprintf(g_error, sizeof(g_error), "absent: %s", soname);
        return 1;
    }
    return xaa_finish_load();
}

int xaa_load_named(const char* soname) {
    if (!soname) {
        xaa_set_error("null soname");
        return 2;
    }
    return xaa_load_pair(soname);
}

int xaa_load(void) {
    return xaa_load_pair("libaaudio.so");
}

int xaa_loaded(void) { return g_lib ? 1 : 0; }

const char* xaa_error(void) { return g_error; }

int xaa_abi_missing_count(void) { return g_missing_count; }

const char* xaa_abi_missing(void) { return g_missing; }

/* -- convert helpers ----------------------------------------------------- */

static const char* xaa_result_text(int32_t code) {
    if (!p_convert_result) return "aaudio runtime not loaded";
    return p_convert_result(code);
}

const char* xaa_convert_result_to_text(int32_t code) {
    return xaa_result_text(code);
}

const char* xaa_convert_stream_state_to_text(int32_t state) {
    if (!p_convert_state) return "aaudio runtime not loaded";
    return p_convert_state(state);
}

int32_t xaa_open_result(void) { return g_open_result; }

int32_t xaa_wait_state_value(void) { return g_wait_state; }

int64_t xaa_timestamp_frames(void) { return g_ts_frames; }

int64_t xaa_timestamp_nanos(void) { return g_ts_nanos; }

int32_t xaa_data_callback_count(void) { return g_data_cb_count; }

int32_t xaa_error_callback_count(void) { return g_error_cb_count; }

/* -- builder lifecycle --------------------------------------------------- */

static XAA_Builder* xaa_builder_from_handle(int64_t handle) {
    return (XAA_Builder*)(intptr_t)handle;
}

static XAA_Stream* xaa_stream_from_handle(int64_t handle) {
    return (XAA_Stream*)(intptr_t)handle;
}

int64_t xaa_builder_create(void) {
    if (!p_create) { xaa_set_error("aaudio runtime not loaded (call xaa_load first)"); return 0; }
    XAA_Builder* builder = 0;
    int32_t rc = p_create(&builder);
    if (rc != XAA_OK || !builder) {
        snprintf(g_error, sizeof(g_error), "createStreamBuilder rc=%d (%s)",
                 (int)rc, xaa_result_text(rc));
        return 0;
    }
    xaa_set_error("");
    return (int64_t)(intptr_t)builder;
}

int32_t xaa_builder_delete(int64_t builder) {
    if (!p_delete) { xaa_set_error("delete unresolved"); return XAA_E_UNIMPLEMENTED; }
    if (!builder) { xaa_set_error("null builder handle"); return XAA_E_NULL; }
    int32_t rc = p_delete(xaa_builder_from_handle(builder));
    if (rc != XAA_OK) {
        snprintf(g_error, sizeof(g_error), "builder delete rc=%d (%s)", (int)rc, xaa_result_text(rc));
    }
    return rc;
}

int64_t xaa_builder_open_stream(int64_t builder) {
    g_open_result = 0;
    if (!p_open) { xaa_set_error("openStream unresolved"); g_open_result = XAA_E_UNIMPLEMENTED; return 0; }
    if (!builder) { xaa_set_error("null builder handle"); g_open_result = XAA_E_NULL; return 0; }
    XAA_Stream* stream = 0;
    int32_t rc = p_open(xaa_builder_from_handle(builder), &stream);
    g_open_result = rc;
    if (rc != XAA_OK || !stream) {
        snprintf(g_error, sizeof(g_error), "openStream rc=%d (%s)", (int)rc, xaa_result_text(rc));
        return 0;
    }
    xaa_set_error("");
    return (int64_t)(intptr_t)stream;
}

/* -- builder setters (26) ------------------------------------------------ */

#define XAA_NEED_B(setter, fn) \
    if (!(setter)) { xaa_set_error(fn " unresolved"); return; }

void xaa_builder_set_device_id(int64_t b, int32_t v) { XAA_NEED_B(p_set_device_id, "setDeviceId") p_set_device_id(xaa_builder_from_handle(b), v); }
void xaa_builder_set_package_name(int64_t b, const char* name) { XAA_NEED_B(p_set_package_name, "setPackageName") p_set_package_name(xaa_builder_from_handle(b), name ? name : "xiom.aaudio"); }
void xaa_builder_set_attribution_tag(int64_t b, const char* tag) { XAA_NEED_B(p_set_attribution_tag, "setAttributionTag") p_set_attribution_tag(xaa_builder_from_handle(b), tag ? tag : "xiom"); }
void xaa_builder_set_sample_rate(int64_t b, int32_t v) { XAA_NEED_B(p_set_sample_rate, "setSampleRate") p_set_sample_rate(xaa_builder_from_handle(b), v); }
void xaa_builder_set_channel_count(int64_t b, int32_t v) { XAA_NEED_B(p_set_channel_count, "setChannelCount") p_set_channel_count(xaa_builder_from_handle(b), v); }
void xaa_builder_set_samples_per_frame(int64_t b, int32_t v) { XAA_NEED_B(p_set_samples_per_frame, "setSamplesPerFrame") p_set_samples_per_frame(xaa_builder_from_handle(b), v); }
void xaa_builder_set_format(int64_t b, int32_t v) { XAA_NEED_B(p_set_format, "setFormat") p_set_format(xaa_builder_from_handle(b), v); }
void xaa_builder_set_sharing_mode(int64_t b, int32_t v) { XAA_NEED_B(p_set_sharing_mode, "setSharingMode") p_set_sharing_mode(xaa_builder_from_handle(b), v); }
void xaa_builder_set_direction(int64_t b, int32_t v) { XAA_NEED_B(p_set_direction, "setDirection") p_set_direction(xaa_builder_from_handle(b), v); }
void xaa_builder_set_buffer_capacity_in_frames(int64_t b, int32_t v) { XAA_NEED_B(p_set_buffer_capacity, "setBufferCapacityInFrames") p_set_buffer_capacity(xaa_builder_from_handle(b), v); }
void xaa_builder_set_performance_mode(int64_t b, int32_t v) { XAA_NEED_B(p_set_performance_mode, "setPerformanceMode") p_set_performance_mode(xaa_builder_from_handle(b), v); }
void xaa_builder_set_usage(int64_t b, int32_t v) { XAA_NEED_B(p_set_usage, "setUsage") p_set_usage(xaa_builder_from_handle(b), v); }
void xaa_builder_set_content_type(int64_t b, int32_t v) { XAA_NEED_B(p_set_content_type, "setContentType") p_set_content_type(xaa_builder_from_handle(b), v); }
void xaa_builder_set_spatialization_behavior(int64_t b, int32_t v) { XAA_NEED_B(p_set_spatialization, "setSpatializationBehavior") p_set_spatialization(xaa_builder_from_handle(b), v); }
void xaa_builder_set_is_content_spatialized(int64_t b, int32_t v) { XAA_NEED_B(p_set_is_spatialized, "setIsContentSpatialized") p_set_is_spatialized(xaa_builder_from_handle(b), v ? 1 : 0); }
void xaa_builder_set_input_preset(int64_t b, int32_t v) { XAA_NEED_B(p_set_input_preset, "setInputPreset") p_set_input_preset(xaa_builder_from_handle(b), v); }
void xaa_builder_set_allowed_capture_policy(int64_t b, int32_t v) { XAA_NEED_B(p_set_capture_policy, "setAllowedCapturePolicy") p_set_capture_policy(xaa_builder_from_handle(b), v); }
void xaa_builder_set_session_id(int64_t b, int32_t v) { XAA_NEED_B(p_set_session_id, "setSessionId") p_set_session_id(xaa_builder_from_handle(b), v); }
void xaa_builder_set_privacy_sensitive(int64_t b, int32_t v) { XAA_NEED_B(p_set_privacy, "setPrivacySensitive") p_set_privacy(xaa_builder_from_handle(b), v ? 1 : 0); }
void xaa_builder_set_frames_per_data_callback(int64_t b, int32_t v) { XAA_NEED_B(p_set_frames_per_cb, "setFramesPerDataCallback") p_set_frames_per_cb(xaa_builder_from_handle(b), v); }
void xaa_builder_set_channel_mask(int64_t b, int32_t v) { XAA_NEED_B(p_set_channel_mask, "setChannelMask") p_set_channel_mask(xaa_builder_from_handle(b), v); }

void xaa_builder_set_data_callback(int64_t b) {
    XAA_NEED_B(p_install_data_cb, "setDataCallback")
    p_install_data_cb(xaa_builder_from_handle(b), xaa_data_callback_stub, 0);
}

void xaa_builder_set_error_callback(int64_t b) {
    XAA_NEED_B(p_install_error_cb, "setErrorCallback")
    p_install_error_cb(xaa_builder_from_handle(b), xaa_error_callback_stub, 0);
}

/* -- stream control / I/O ------------------------------------------------ */

#define XAA_NEED_S(ptr, fn, fallback) \
    if (!(ptr)) { xaa_set_error(fn " unresolved"); return (fallback); }

int32_t xaa_stream_release(int64_t s) { XAA_NEED_S(p_release, "release", XAA_E_UNIMPLEMENTED) return p_release(xaa_stream_from_handle(s)); }
int32_t xaa_stream_close(int64_t s) { XAA_NEED_S(p_close, "close", XAA_E_UNIMPLEMENTED) return p_close(xaa_stream_from_handle(s)); }
int32_t xaa_stream_request_start(int64_t s) { XAA_NEED_S(p_request_start, "requestStart", XAA_E_UNIMPLEMENTED) return p_request_start(xaa_stream_from_handle(s)); }
int32_t xaa_stream_request_pause(int64_t s) { XAA_NEED_S(p_request_pause, "requestPause", XAA_E_UNIMPLEMENTED) return p_request_pause(xaa_stream_from_handle(s)); }
int32_t xaa_stream_request_flush(int64_t s) { XAA_NEED_S(p_request_flush, "requestFlush", XAA_E_UNIMPLEMENTED) return p_request_flush(xaa_stream_from_handle(s)); }
int32_t xaa_stream_request_stop(int64_t s) { XAA_NEED_S(p_request_stop, "requestStop", XAA_E_UNIMPLEMENTED) return p_request_stop(xaa_stream_from_handle(s)); }
int32_t xaa_stream_get_state(int64_t s) { XAA_NEED_S(p_get_state, "getState", XAA_E_UNIMPLEMENTED) return p_get_state(xaa_stream_from_handle(s)); }

int32_t xaa_stream_wait_for_state_change(int64_t s, int32_t input_state, int64_t timeout_ns) {
    XAA_NEED_S(p_wait, "waitForStateChange", XAA_E_UNIMPLEMENTED)
    if (timeout_ns < 0) { xaa_set_error("negative timeout"); return XAA_E_ILLEGAL_ARGUMENT; }
    int32_t next = input_state;
    int32_t rc = p_wait(xaa_stream_from_handle(s), input_state, &next, timeout_ns);
    g_wait_state = next;
    return rc;
}

int32_t xaa_stream_read(int64_t s, int32_t num_frames, int64_t timeout_ns) {
    XAA_NEED_S(p_read, "read", XAA_E_UNIMPLEMENTED)
    if (num_frames <= 0 || num_frames > XAA_SCRATCH_FRAMES || timeout_ns < 0) {
        xaa_set_error("read argument out of range");
        return XAA_E_ILLEGAL_ARGUMENT;
    }
    return p_read(xaa_stream_from_handle(s), g_scratch, num_frames, timeout_ns);
}

int32_t xaa_stream_write(int64_t s, int32_t num_frames, int64_t timeout_ns) {
    XAA_NEED_S(p_write, "write", XAA_E_UNIMPLEMENTED)
    if (num_frames <= 0 || num_frames > XAA_SCRATCH_FRAMES || timeout_ns < 0) {
        xaa_set_error("write argument out of range");
        return XAA_E_ILLEGAL_ARGUMENT;
    }
    /* PCM_I16 stereo = 4 bytes/frame; zero-fill exactly that (silence). */
    memset(g_scratch, 0, (size_t)num_frames * 4u);
    return p_write(xaa_stream_from_handle(s), g_scratch, num_frames, timeout_ns);
}

int32_t xaa_stream_set_buffer_size_in_frames(int64_t s, int32_t num_frames) {
    XAA_NEED_S(p_set_buffer_size, "setBufferSizeInFrames", XAA_E_UNIMPLEMENTED)
    if (num_frames <= 0) { xaa_set_error("buffer size must be > 0"); return XAA_E_ILLEGAL_ARGUMENT; }
    return p_set_buffer_size(xaa_stream_from_handle(s), num_frames);
}

int32_t xaa_stream_get_timestamp(int64_t s, int32_t clock_id) {
    XAA_NEED_S(p_get_timestamp, "getTimestamp", XAA_E_UNIMPLEMENTED)
    int64_t frames = 0;
    int64_t nanos = 0;
    int32_t rc = p_get_timestamp(xaa_stream_from_handle(s), clock_id, &frames, &nanos);
    if (rc == XAA_OK) {
        g_ts_frames = frames;
        g_ts_nanos = nanos;
    }
    return rc;
}

/* -- stream queries ------------------------------------------------------ */

int32_t xaa_stream_get_buffer_size_in_frames(int64_t s) { XAA_NEED_S(p_get_buffer_size, "getBufferSizeInFrames", XAA_E_UNIMPLEMENTED) return p_get_buffer_size(xaa_stream_from_handle(s)); }
int32_t xaa_stream_get_frames_per_burst(int64_t s) { XAA_NEED_S(p_get_frames_per_burst, "getFramesPerBurst", XAA_E_UNIMPLEMENTED) return p_get_frames_per_burst(xaa_stream_from_handle(s)); }
int32_t xaa_stream_get_buffer_capacity_in_frames(int64_t s) { XAA_NEED_S(p_get_buffer_capacity, "getBufferCapacityInFrames", XAA_E_UNIMPLEMENTED) return p_get_buffer_capacity(xaa_stream_from_handle(s)); }
int32_t xaa_stream_get_frames_per_data_callback(int64_t s) { XAA_NEED_S(p_get_frames_per_cb, "getFramesPerDataCallback", XAA_E_UNIMPLEMENTED) return p_get_frames_per_cb(xaa_stream_from_handle(s)); }
int32_t xaa_stream_get_xrun_count(int64_t s) { XAA_NEED_S(p_get_xrun_count, "getXRunCount", XAA_E_UNIMPLEMENTED) return p_get_xrun_count(xaa_stream_from_handle(s)); }
int32_t xaa_stream_get_sample_rate(int64_t s) { XAA_NEED_S(p_get_sample_rate, "getSampleRate", XAA_E_UNIMPLEMENTED) return p_get_sample_rate(xaa_stream_from_handle(s)); }
int32_t xaa_stream_get_hardware_sample_rate(int64_t s) { XAA_NEED_S(p_get_hw_sample_rate, "getHardwareSampleRate", XAA_E_UNIMPLEMENTED) return p_get_hw_sample_rate(xaa_stream_from_handle(s)); }
int32_t xaa_stream_get_channel_count(int64_t s) { XAA_NEED_S(p_get_channel_count, "getChannelCount", XAA_E_UNIMPLEMENTED) return p_get_channel_count(xaa_stream_from_handle(s)); }
int32_t xaa_stream_get_hardware_channel_count(int64_t s) { XAA_NEED_S(p_get_hw_channel_count, "getHardwareChannelCount", XAA_E_UNIMPLEMENTED) return p_get_hw_channel_count(xaa_stream_from_handle(s)); }
int32_t xaa_stream_get_samples_per_frame(int64_t s) { XAA_NEED_S(p_get_samples_per_frame, "getSamplesPerFrame", XAA_E_UNIMPLEMENTED) return p_get_samples_per_frame(xaa_stream_from_handle(s)); }
int32_t xaa_stream_get_device_id(int64_t s) { XAA_NEED_S(p_get_device_id, "getDeviceId", XAA_E_UNIMPLEMENTED) return p_get_device_id(xaa_stream_from_handle(s)); }
int32_t xaa_stream_get_format(int64_t s) { XAA_NEED_S(p_get_format, "getFormat", XAA_E_UNIMPLEMENTED) return p_get_format(xaa_stream_from_handle(s)); }
int32_t xaa_stream_get_hardware_format(int64_t s) { XAA_NEED_S(p_get_hw_format, "getHardwareFormat", XAA_E_UNIMPLEMENTED) return p_get_hw_format(xaa_stream_from_handle(s)); }
int32_t xaa_stream_get_sharing_mode(int64_t s) { XAA_NEED_S(p_get_sharing_mode, "getSharingMode", XAA_E_UNIMPLEMENTED) return p_get_sharing_mode(xaa_stream_from_handle(s)); }
int32_t xaa_stream_get_performance_mode(int64_t s) { XAA_NEED_S(p_get_performance_mode, "getPerformanceMode", XAA_E_UNIMPLEMENTED) return p_get_performance_mode(xaa_stream_from_handle(s)); }
int32_t xaa_stream_get_direction(int64_t s) { XAA_NEED_S(p_get_direction, "getDirection", XAA_E_UNIMPLEMENTED) return p_get_direction(xaa_stream_from_handle(s)); }
int64_t xaa_stream_get_frames_written(int64_t s) { if (!p_get_frames_written) { xaa_set_error("getFramesWritten unresolved"); return 0; } return p_get_frames_written(xaa_stream_from_handle(s)); }
int64_t xaa_stream_get_frames_read(int64_t s) { if (!p_get_frames_read) { xaa_set_error("getFramesRead unresolved"); return 0; } return p_get_frames_read(xaa_stream_from_handle(s)); }
int32_t xaa_stream_get_session_id(int64_t s) { XAA_NEED_S(p_get_session_id, "getSessionId", XAA_E_UNIMPLEMENTED) return p_get_session_id(xaa_stream_from_handle(s)); }
int32_t xaa_stream_get_usage(int64_t s) { XAA_NEED_S(p_get_usage, "getUsage", XAA_E_UNIMPLEMENTED) return p_get_usage(xaa_stream_from_handle(s)); }
int32_t xaa_stream_get_content_type(int64_t s) { XAA_NEED_S(p_get_content_type, "getContentType", XAA_E_UNIMPLEMENTED) return p_get_content_type(xaa_stream_from_handle(s)); }
int32_t xaa_stream_get_spatialization_behavior(int64_t s) { XAA_NEED_S(p_get_spatialization, "getSpatializationBehavior", XAA_E_UNIMPLEMENTED) return p_get_spatialization(xaa_stream_from_handle(s)); }
int32_t xaa_stream_is_content_spatialized(int64_t s) { if (!p_is_content_spatialized) { xaa_set_error("isContentSpatialized unresolved"); return 0; } return p_is_content_spatialized(xaa_stream_from_handle(s)) ? 1 : 0; }
int32_t xaa_stream_get_input_preset(int64_t s) { XAA_NEED_S(p_get_input_preset, "getInputPreset", XAA_E_UNIMPLEMENTED) return p_get_input_preset(xaa_stream_from_handle(s)); }
int32_t xaa_stream_get_allowed_capture_policy(int64_t s) { XAA_NEED_S(p_get_capture_policy, "getAllowedCapturePolicy", XAA_E_UNIMPLEMENTED) return p_get_capture_policy(xaa_stream_from_handle(s)); }
int32_t xaa_stream_is_privacy_sensitive(int64_t s) { if (!p_is_privacy_sensitive) { xaa_set_error("isPrivacySensitive unresolved"); return 0; } return p_is_privacy_sensitive(xaa_stream_from_handle(s)) ? 1 : 0; }
int32_t xaa_stream_get_channel_mask(int64_t s) { XAA_NEED_S(p_get_channel_mask, "getChannelMask", XAA_E_UNIMPLEMENTED) return p_get_channel_mask(xaa_stream_from_handle(s)); }

/* -- teardown ------------------------------------------------------------ */

void xaa_unload(void) {
    if (g_lib) { xaa_dlclose(g_lib); g_lib = 0; }
    p_convert_result = 0; p_convert_state = 0; p_create = 0;
    p_set_device_id = 0; p_set_package_name = 0; p_set_attribution_tag = 0;
    p_set_sample_rate = 0; p_set_channel_count = 0; p_set_samples_per_frame = 0;
    p_set_format = 0; p_set_sharing_mode = 0; p_set_direction = 0;
    p_set_buffer_capacity = 0; p_set_performance_mode = 0; p_set_usage = 0;
    p_set_content_type = 0; p_set_spatialization = 0; p_set_is_spatialized = 0;
    p_set_input_preset = 0; p_set_capture_policy = 0; p_set_session_id = 0;
    p_set_privacy = 0; p_install_data_cb = 0; p_set_frames_per_cb = 0;
    p_install_error_cb = 0; p_open = 0; p_delete = 0; p_set_channel_mask = 0;
    p_release = 0; p_close = 0; p_request_start = 0; p_request_pause = 0;
    p_request_flush = 0; p_request_stop = 0; p_get_state = 0; p_wait = 0;
    p_read = 0; p_write = 0; p_set_buffer_size = 0; p_get_buffer_size = 0;
    p_get_frames_per_burst = 0; p_get_buffer_capacity = 0; p_get_frames_per_cb = 0;
    p_get_xrun_count = 0; p_get_sample_rate = 0; p_get_hw_sample_rate = 0;
    p_get_channel_count = 0; p_get_hw_channel_count = 0; p_get_samples_per_frame = 0;
    p_get_device_id = 0; p_get_format = 0; p_get_hw_format = 0;
    p_get_sharing_mode = 0; p_get_performance_mode = 0; p_get_direction = 0;
    p_get_frames_written = 0; p_get_frames_read = 0; p_get_session_id = 0;
    p_get_timestamp = 0; p_get_usage = 0; p_get_content_type = 0;
    p_get_spatialization = 0; p_is_content_spatialized = 0;
    p_get_input_preset = 0; p_get_capture_policy = 0;
    p_is_privacy_sensitive = 0; p_get_channel_mask = 0;
    g_missing_count = 0;
    g_missing[0] = 0;
}
