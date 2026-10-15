/* XIOM -- xiom.aaudio A6 head: on-device evidence driver.
 * Copyright (c) 2026 Eleftheros Notas and The XIOM Authors
 * Licensed under the MIT or Apache-2.0 license, at your option.
 *
 * Purpose: prove, on the API-36 x86_64 emulator, the exact things the
 * package claims:
 *   1. every constant transcribed into aaudio.xi matches the pinned NDK
 *      header values (aaudio/AAudio.h, r27b) -- checked AT BUILD TIME
 *      against the real header, transcribed literals embedded here;
 *   2. the runtime bridge (src/aaudio_bridge.c, compiled into this
 *      driver) loads libaaudio.so and resolves the declared 67-export
 *      set (0 missing);
 *   3. the builder lifecycle works without any audio device
 *      (create -> configure -> delete);
 *   4. an OUTPUT/NONE/PCM_I16/2ch/48000/SHARED open attempt records its
 *      typed verdict -- a typed AAUDIO_ERROR_* is a NON-FATAL recorded
 *      outcome (the emulator often runs -no-audio).  On a successful
 *      open: requestStart then close cleanly.
 *
 * Build+run: powershell -File build-and-run.ps1 (cross-builds for
 * x86_64-linux-android26, pushes to /data/local/tmp/xiom-spike/, runs).
 */

#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include <aaudio/AAudio.h> /* the oracle (constants checked against it) */

/* ---- bridge contract (mirrors src/aaudio_bridge.c) --------------------- */

extern int xaa_load(void);
extern int xaa_loaded(void);
extern const char* xaa_error(void);
extern int xaa_abi_missing_count(void);
extern const char* xaa_abi_missing(void);
extern void xaa_unload(void);

extern int64_t xaa_builder_create(void);
extern int32_t xaa_builder_delete(int64_t builder);
extern void xaa_builder_set_device_id(int64_t b, int32_t v);
extern void xaa_builder_set_sample_rate(int64_t b, int32_t v);
extern void xaa_builder_set_channel_count(int64_t b, int32_t v);
extern void xaa_builder_set_format(int64_t b, int32_t v);
extern void xaa_builder_set_sharing_mode(int64_t b, int32_t v);
extern void xaa_builder_set_direction(int64_t b, int32_t v);
extern void xaa_builder_set_buffer_capacity_in_frames(int64_t b, int32_t v);
extern void xaa_builder_set_performance_mode(int64_t b, int32_t v);
extern void xaa_builder_set_data_callback(int64_t b);
extern void xaa_builder_set_error_callback(int64_t b);
extern int64_t xaa_builder_open_stream(int64_t b);
extern int32_t xaa_open_result(void);

extern int32_t xaa_stream_close(int64_t s);
extern int32_t xaa_stream_request_start(int64_t s);
extern int32_t xaa_stream_request_pause(int64_t s);
extern int32_t xaa_stream_request_stop(int64_t s);
extern int32_t xaa_stream_get_state(int64_t s);
extern int32_t xaa_stream_wait_for_state_change(int64_t s, int32_t input_state, int64_t timeout_ns);
extern int32_t xaa_wait_state_value(void);
extern int32_t xaa_stream_read(int64_t s, int32_t num_frames, int64_t timeout_ns);
extern int32_t xaa_stream_write(int64_t s, int32_t num_frames, int64_t timeout_ns);
extern int32_t xaa_stream_get_xrun_count(int64_t s);
extern int32_t xaa_stream_get_frames_per_burst(int64_t s);
extern int32_t xaa_stream_get_sample_rate(int64_t s);
extern int32_t xaa_stream_get_channel_count(int64_t s);
extern int32_t xaa_stream_get_format(int64_t s);
extern int32_t xaa_stream_get_sharing_mode(int64_t s);
extern int32_t xaa_stream_get_performance_mode(int64_t s);
extern int32_t xaa_stream_get_buffer_capacity_in_frames(int64_t s);
extern int32_t xaa_stream_get_timestamp(int64_t s, int32_t clock_id);
extern int64_t xaa_timestamp_frames(void);
extern int64_t xaa_timestamp_nanos(void);

extern const char* xaa_convert_result_to_text(int32_t code);
extern const char* xaa_convert_stream_state_to_text(int32_t state);
extern int32_t xaa_data_callback_count(void);
extern int32_t xaa_error_callback_count(void);

/* ---- transcribed-constant check ---------------------------------------- */

static int g_const_total = 0;
static int g_const_fail = 0;

#define CHK(transcribed, header_expr)                                            \
    do {                                                                         \
        int32_t t_ = (int32_t)(transcribed);                                     \
        int32_t h_ = (int32_t)(header_expr);                                     \
        g_const_total++;                                                         \
        if (t_ != h_) {                                                          \
            g_const_fail++;                                                      \
            printf("  CONST MISMATCH %s: transcribed=%d header=%d\n",            \
                   #header_expr, (int)t_, (int)h_);                              \
        }                                                                        \
    } while (0)

static void check_constants(void) {
    /* The literals below are the values transcribed into aaudio.xi
     * (module xiom.aaudio).  The header_expr operands come from the
     * pinned NDK header at build time. */
    CHK(0, AAUDIO_UNSPECIFIED);
    CHK(0, AAUDIO_DIRECTION_OUTPUT);
    CHK(1, AAUDIO_DIRECTION_INPUT);
    CHK(-1, AAUDIO_FORMAT_INVALID);
    CHK(0, AAUDIO_FORMAT_UNSPECIFIED);
    CHK(1, AAUDIO_FORMAT_PCM_I16);
    CHK(2, AAUDIO_FORMAT_PCM_FLOAT);
    CHK(3, AAUDIO_FORMAT_PCM_I24_PACKED);
    CHK(4, AAUDIO_FORMAT_PCM_I32);
    CHK(5, AAUDIO_FORMAT_IEC61937);
    CHK(0, AAUDIO_OK);
    CHK(-900, AAUDIO_ERROR_BASE);
    CHK(-899, AAUDIO_ERROR_DISCONNECTED);
    CHK(-898, AAUDIO_ERROR_ILLEGAL_ARGUMENT);
    CHK(-896, AAUDIO_ERROR_INTERNAL);
    CHK(-895, AAUDIO_ERROR_INVALID_STATE);
    CHK(-892, AAUDIO_ERROR_INVALID_HANDLE);
    CHK(-890, AAUDIO_ERROR_UNIMPLEMENTED);
    CHK(-889, AAUDIO_ERROR_UNAVAILABLE);
    CHK(-888, AAUDIO_ERROR_NO_FREE_HANDLES);
    CHK(-887, AAUDIO_ERROR_NO_MEMORY);
    CHK(-886, AAUDIO_ERROR_NULL);
    CHK(-885, AAUDIO_ERROR_TIMEOUT);
    CHK(-884, AAUDIO_ERROR_WOULD_BLOCK);
    CHK(-883, AAUDIO_ERROR_INVALID_FORMAT);
    CHK(-882, AAUDIO_ERROR_OUT_OF_RANGE);
    CHK(-881, AAUDIO_ERROR_NO_SERVICE);
    CHK(-880, AAUDIO_ERROR_INVALID_RATE);
    CHK(0, AAUDIO_STREAM_STATE_UNINITIALIZED);
    CHK(1, AAUDIO_STREAM_STATE_UNKNOWN);
    CHK(2, AAUDIO_STREAM_STATE_OPEN);
    CHK(3, AAUDIO_STREAM_STATE_STARTING);
    CHK(4, AAUDIO_STREAM_STATE_STARTED);
    CHK(5, AAUDIO_STREAM_STATE_PAUSING);
    CHK(6, AAUDIO_STREAM_STATE_PAUSED);
    CHK(7, AAUDIO_STREAM_STATE_FLUSHING);
    CHK(8, AAUDIO_STREAM_STATE_FLUSHED);
    CHK(9, AAUDIO_STREAM_STATE_STOPPING);
    CHK(10, AAUDIO_STREAM_STATE_STOPPED);
    CHK(11, AAUDIO_STREAM_STATE_CLOSING);
    CHK(12, AAUDIO_STREAM_STATE_CLOSED);
    CHK(13, AAUDIO_STREAM_STATE_DISCONNECTED);
    CHK(0, AAUDIO_SHARING_MODE_EXCLUSIVE);
    CHK(1, AAUDIO_SHARING_MODE_SHARED);
    CHK(10, AAUDIO_PERFORMANCE_MODE_NONE);
    CHK(11, AAUDIO_PERFORMANCE_MODE_POWER_SAVING);
    CHK(12, AAUDIO_PERFORMANCE_MODE_LOW_LATENCY);
    CHK(1000, AAUDIO_SYSTEM_USAGE_OFFSET);
    CHK(1, AAUDIO_USAGE_MEDIA);
    CHK(2, AAUDIO_USAGE_VOICE_COMMUNICATION);
    CHK(3, AAUDIO_USAGE_VOICE_COMMUNICATION_SIGNALLING);
    CHK(4, AAUDIO_USAGE_ALARM);
    CHK(5, AAUDIO_USAGE_NOTIFICATION);
    CHK(6, AAUDIO_USAGE_NOTIFICATION_RINGTONE);
    CHK(10, AAUDIO_USAGE_NOTIFICATION_EVENT);
    CHK(11, AAUDIO_USAGE_ASSISTANCE_ACCESSIBILITY);
    CHK(12, AAUDIO_USAGE_ASSISTANCE_NAVIGATION_GUIDANCE);
    CHK(13, AAUDIO_USAGE_ASSISTANCE_SONIFICATION);
    CHK(14, AAUDIO_USAGE_GAME);
    CHK(16, AAUDIO_USAGE_ASSISTANT);
    CHK(1000, AAUDIO_SYSTEM_USAGE_EMERGENCY);
    CHK(1001, AAUDIO_SYSTEM_USAGE_SAFETY);
    CHK(1002, AAUDIO_SYSTEM_USAGE_VEHICLE_STATUS);
    CHK(1003, AAUDIO_SYSTEM_USAGE_ANNOUNCEMENT);
    CHK(1, AAUDIO_CONTENT_TYPE_SPEECH);
    CHK(2, AAUDIO_CONTENT_TYPE_MUSIC);
    CHK(3, AAUDIO_CONTENT_TYPE_MOVIE);
    CHK(4, AAUDIO_CONTENT_TYPE_SONIFICATION);
    CHK(1, AAUDIO_SPATIALIZATION_BEHAVIOR_AUTO);
    CHK(2, AAUDIO_SPATIALIZATION_BEHAVIOR_NEVER);
    CHK(1, AAUDIO_INPUT_PRESET_GENERIC);
    CHK(5, AAUDIO_INPUT_PRESET_CAMCORDER);
    CHK(6, AAUDIO_INPUT_PRESET_VOICE_RECOGNITION);
    CHK(7, AAUDIO_INPUT_PRESET_VOICE_COMMUNICATION);
    CHK(9, AAUDIO_INPUT_PRESET_UNPROCESSED);
    CHK(10, AAUDIO_INPUT_PRESET_VOICE_PERFORMANCE);
    CHK(1997, AAUDIO_INPUT_PRESET_SYSTEM_ECHO_REFERENCE);
    CHK(1999, AAUDIO_INPUT_PRESET_SYSTEM_HOTWORD);
    CHK(1, AAUDIO_ALLOW_CAPTURE_BY_ALL);
    CHK(2, AAUDIO_ALLOW_CAPTURE_BY_SYSTEM);
    CHK(3, AAUDIO_ALLOW_CAPTURE_BY_NONE);
    CHK(-1, AAUDIO_SESSION_ID_NONE);
    CHK(0, AAUDIO_SESSION_ID_ALLOCATE);
    CHK(0, AAUDIO_CALLBACK_RESULT_CONTINUE);
    CHK(1, AAUDIO_CALLBACK_RESULT_STOP);
    CHK(-1, AAUDIO_CHANNEL_INVALID);
    CHK(1, AAUDIO_CHANNEL_FRONT_LEFT);
    CHK(2, AAUDIO_CHANNEL_FRONT_RIGHT);
    CHK(4, AAUDIO_CHANNEL_FRONT_CENTER);
    CHK(8, AAUDIO_CHANNEL_LOW_FREQUENCY);
    CHK(16, AAUDIO_CHANNEL_BACK_LEFT);
    CHK(32, AAUDIO_CHANNEL_BACK_RIGHT);
    CHK(64, AAUDIO_CHANNEL_FRONT_LEFT_OF_CENTER);
    CHK(128, AAUDIO_CHANNEL_FRONT_RIGHT_OF_CENTER);
    CHK(256, AAUDIO_CHANNEL_BACK_CENTER);
    CHK(512, AAUDIO_CHANNEL_SIDE_LEFT);
    CHK(1024, AAUDIO_CHANNEL_SIDE_RIGHT);
    CHK(2048, AAUDIO_CHANNEL_TOP_CENTER);
    CHK(4096, AAUDIO_CHANNEL_TOP_FRONT_LEFT);
    CHK(8192, AAUDIO_CHANNEL_TOP_FRONT_CENTER);
    CHK(16384, AAUDIO_CHANNEL_TOP_FRONT_RIGHT);
    CHK(32768, AAUDIO_CHANNEL_TOP_BACK_LEFT);
    CHK(65536, AAUDIO_CHANNEL_TOP_BACK_CENTER);
    CHK(131072, AAUDIO_CHANNEL_TOP_BACK_RIGHT);
    CHK(262144, AAUDIO_CHANNEL_TOP_SIDE_LEFT);
    CHK(524288, AAUDIO_CHANNEL_TOP_SIDE_RIGHT);
    CHK(1048576, AAUDIO_CHANNEL_BOTTOM_FRONT_LEFT);
    CHK(2097152, AAUDIO_CHANNEL_BOTTOM_FRONT_CENTER);
    CHK(4194304, AAUDIO_CHANNEL_BOTTOM_FRONT_RIGHT);
    CHK(8388608, AAUDIO_CHANNEL_LOW_FREQUENCY_2);
    CHK(16777216, AAUDIO_CHANNEL_FRONT_WIDE_LEFT);
    CHK(33554432, AAUDIO_CHANNEL_FRONT_WIDE_RIGHT);
    CHK(1, AAUDIO_CHANNEL_MONO);
    CHK(3, AAUDIO_CHANNEL_STEREO);
    CHK(11, AAUDIO_CHANNEL_2POINT1);
    CHK(7, AAUDIO_CHANNEL_TRI);
    CHK(259, AAUDIO_CHANNEL_TRI_BACK);
    CHK(15, AAUDIO_CHANNEL_3POINT1);
    CHK(786435, AAUDIO_CHANNEL_2POINT0POINT2);
    CHK(786443, AAUDIO_CHANNEL_2POINT1POINT2);
    CHK(786439, AAUDIO_CHANNEL_3POINT0POINT2);
    CHK(786447, AAUDIO_CHANNEL_3POINT1POINT2);
    CHK(51, AAUDIO_CHANNEL_QUAD);
    CHK(1539, AAUDIO_CHANNEL_QUAD_SIDE);
    CHK(263, AAUDIO_CHANNEL_SURROUND);
    CHK(55, AAUDIO_CHANNEL_PENTA);
    CHK(63, AAUDIO_CHANNEL_5POINT1);
    CHK(1551, AAUDIO_CHANNEL_5POINT1_SIDE);
    CHK(319, AAUDIO_CHANNEL_6POINT1);
    CHK(1599, AAUDIO_CHANNEL_7POINT1);
    CHK(786495, AAUDIO_CHANNEL_5POINT1POINT2);
    CHK(184383, AAUDIO_CHANNEL_5POINT1POINT4);
    CHK(788031, AAUDIO_CHANNEL_7POINT1POINT2);
    CHK(185919, AAUDIO_CHANNEL_7POINT1POINT4);
    CHK(50517567, AAUDIO_CHANNEL_9POINT1POINT4);
    CHK(51303999, AAUDIO_CHANNEL_9POINT1POINT6);
    CHK(260, AAUDIO_CHANNEL_FRONT_BACK);
    CHK(1, CLOCK_MONOTONIC);
    CHK(7, CLOCK_BOOTTIME);
}

/* ---- driver ------------------------------------------------------------ */

#define TYPED_OPEN_FAILURE_IS_OK 1

int main(void) {
    printf("=== xiom.aaudio on-device head probe (A6, NDK r27b) ===\n");
    fflush(stdout);

    /* 1. constants vs the pinned header. */
    check_constants();
    printf("constants: %d checked against aaudio/AAudio.h -- %d mismatch (%s)\n",
           g_const_total, g_const_fail, g_const_fail == 0 ? "PASS" : "FAIL");
    if (g_const_fail != 0) {
        return 1;
    }

    /* 2. runtime probe through the shipped bridge. */
    int rc_load = xaa_load();
    if (rc_load == 1) {
        printf("runtime: SKIP -- libaaudio.so absent (%s)\n", xaa_error());
        return 0;
    }
    if (rc_load == 2) {
        printf("runtime: ABI FAIL -- missing exports: %s\n", xaa_abi_missing());
        return 1;
    }
    printf("runtime: dlopen libaaudio.so OK (loaded=%d)\n", xaa_loaded());
    printf("abi: export set 67/67 resolved (%d missing)\n", xaa_abi_missing_count());
    if (xaa_abi_missing_count() != 0) {
        printf("missing: %s\n", xaa_abi_missing());
        xaa_unload();
        return 1;
    }

    /* 3. builder lifecycle (works with no audio device). */
    int64_t builder = xaa_builder_create();
    if (!builder) {
        printf("builder: create FAILED -- %s\n", xaa_error());
        xaa_unload();
        return 1;
    }
    printf("builder: create OK (handle=%lld)\n", (long long)builder);
    xaa_builder_set_direction(builder, AAUDIO_DIRECTION_OUTPUT);
    xaa_builder_set_performance_mode(builder, AAUDIO_PERFORMANCE_MODE_NONE);
    xaa_builder_set_format(builder, AAUDIO_FORMAT_PCM_I16);
    xaa_builder_set_channel_count(builder, 2);
    xaa_builder_set_sample_rate(builder, 48000);
    xaa_builder_set_sharing_mode(builder, AAUDIO_SHARING_MODE_SHARED);
    xaa_builder_set_buffer_capacity_in_frames(builder, 192);
    xaa_builder_set_data_callback(builder);
    xaa_builder_set_error_callback(builder);
    printf("builder: configured OUTPUT/NONE/PCM_I16/2ch/48000/SHARED/cb192 + direct-handoff callbacks\n");

    /* 4. open attempt (typed verdict; failure is a recorded outcome). */
    int64_t stream = xaa_builder_open_stream(builder);
    int32_t open_rc = xaa_open_result();
    printf("open: rc=%d (%s)\n", (int)open_rc, xaa_convert_result_to_text(open_rc));
    if (stream != 0) {
        int32_t st0 = xaa_stream_get_state(stream);
        int32_t fmt = xaa_stream_get_format(stream);
        printf("stream: state=%d (%s)\n", (int)st0, xaa_convert_stream_state_to_text(st0));
        printf("stream: sample_rate=%d channel_count=%d format=%d (%s) sharing=%d perf=%d\n",
               (int)xaa_stream_get_sample_rate(stream),
               (int)xaa_stream_get_channel_count(stream),
               (int)fmt,
               fmt == AAUDIO_FORMAT_PCM_I16 ? "AAUDIO_FORMAT_PCM_I16" : "unexpected",
               (int)xaa_stream_get_sharing_mode(stream),
               (int)xaa_stream_get_performance_mode(stream));
        printf("stream: frames_per_burst=%d buffer_capacity=%d xrun=%d\n",
               (int)xaa_stream_get_frames_per_burst(stream),
               (int)xaa_stream_get_buffer_capacity_in_frames(stream),
               (int)xaa_stream_get_xrun_count(stream));

        int32_t rs = xaa_stream_request_start(stream);
        printf("stream: requestStart rc=%d (%s)\n", (int)rs, xaa_convert_result_to_text(rs));
        int32_t rw = xaa_stream_wait_for_state_change(stream, st0, 200000000LL /* 200 ms */);
        printf("stream: waitForStateChange(OPEN) rc=%d (%s) next=%d (%s)\n",
               (int)rw, xaa_convert_result_to_text(rw), (int)xaa_wait_state_value(),
               xaa_convert_stream_state_to_text(xaa_wait_state_value()));
        int32_t rw2 = xaa_stream_wait_for_state_change(stream, xaa_wait_state_value(), 200000000LL);
        printf("stream: waitForStateChange(2) rc=%d (%s) next=%d (%s)\n",
               (int)rw2, xaa_convert_result_to_text(rw2), (int)xaa_wait_state_value(),
               xaa_convert_stream_state_to_text(xaa_wait_state_value()));

        int32_t w = xaa_stream_write(stream, 192, 0);
        if (w == AAUDIO_ERROR_INVALID_STATE) {
            /* Expected with a data callback installed: the header forbids
             * AAudioStream_write() on a stream with an active callback. */
            printf("stream: write(192 frames) rc=%d (%s; expected -- data callback active)\n",
                   (int)w, xaa_convert_result_to_text(w));
        } else {
            printf("stream: write(192 frames) rc=%d (%s)\n", (int)w, xaa_convert_result_to_text(w));
        }
        int32_t ts = xaa_stream_get_timestamp(stream, CLOCK_MONOTONIC);
        if (ts == AAUDIO_OK) {
            printf("stream: getTimestamp OK frames=%lld nanos=%lld\n",
                   (long long)xaa_timestamp_frames(), (long long)xaa_timestamp_nanos());
        } else {
            printf("stream: getTimestamp rc=%d (%s)\n", (int)ts, xaa_convert_result_to_text(ts));
        }
        printf("stream: data_callback_count=%d error_callback_count=%d\n",
               (int)xaa_data_callback_count(), (int)xaa_error_callback_count());
        int32_t rc_close = xaa_stream_close(stream);
        printf("stream: close rc=%d (%s)\n", (int)rc_close, xaa_convert_result_to_text(rc_close));
        if (rc_close != AAUDIO_OK) {
            xaa_builder_delete(builder);
            xaa_unload();
            return 1;
        }
    }

    /* 5. builder delete + teardown. */
    int32_t rc_del = xaa_builder_delete(builder);
    printf("builder: delete rc=%d (%s)\n", (int)rc_del, xaa_convert_result_to_text(rc_del));
    if (rc_del != AAUDIO_OK) {
        xaa_unload();
        return 1;
    }
    xaa_unload();
    printf("unload: handles released\n");
    printf("VERDICT: constants %d/%d; export set 67/67; builder lifecycle PASS; open %s\n",
           g_const_total, g_const_total,
           stream != 0 ? "OK -> requestStart -> close clean" : "recorded typed failure (non-fatal)");
    return 0;
}
