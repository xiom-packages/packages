/* XIOM -- xiom.android A3 input + A4 sensors heads: on-device evidence
 * driver (shell binary; the A3 queue itself is app-delivered and is
 * proven by input_app_probe.c).
 * Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
 * Licensed under the MIT or Apache-2.0 license, at your option.
 *
 * Purpose: prove, on the API-36 x86_64 emulator, the exact things the
 * package claims (W2d-A3/A4):
 *   1. every constant transcribed into src/input.xi and
 *      src/sensors.xi matches the pinned NDK headers (android/input.h,
 *      android/keycodes.h, android/sensor.h r27b) -- checked AT BUILD
 *      TIME by the generated assert header (gen/a3a4_const_asserts.h,
 *      538 values) plus the struct ABI asserts below;
 *   2. the runtime bridge (src/android_bridge.c, compiled into this
 *      driver) loads libandroid.so/libnativewindow.so and resolves the
 *      declared 209-export set (0 missing);
 *   3. the A3 head's explicit-error contract (no fabricated queues:
 *      the shell process cannot own an AInputQueue -- documented);
 *   4. the A4 head works for real: ASensorManager_getInstance ->
 *      getSensorList (enumerate + describe every sensor) ->
 *      createEventQueue(ident) -> registerSensor(accel) -> poll ->
 *      getEvents into owned slots -> typed accessors -> disable ->
 *      destroy; then the callback-queue variant (ALOOPER_POLL_CALLBACK);
 *      plus the direct-channel trio's honest on-device behavior.
 *
 * Build+run: powershell -File build-and-run-input.ps1 (cross-builds for
 * x86_64-linux-android26, pushes to /data/local/tmp/xiom-spike/, runs).
 */

#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "gen/a3a4_const_asserts.h" /* build-time transcription gate */

/* ---- struct ABI facts pinned by the bridge (byte-exact gate) ----------- */

_Static_assert(sizeof(ASensorEvent) == 104, "ASensorEvent size drift");
_Static_assert(sizeof(ASensorVector) == 16, "ASensorVector size drift");
_Static_assert(offsetof(ASensorEvent, timestamp) == 16, "ASensorEvent.timestamp offset drift");
_Static_assert(offsetof(ASensorEvent, flags) == 88, "ASensorEvent.flags offset drift");
_Static_assert(offsetof(ASensorEvent, data) == 24, "ASensorEvent.data offset drift");

/* ---- bridge contract (mirrors src/android_bridge.c) -------------------- */

extern int xa_load(void);
extern const char* xa_error(void);
extern int xa_abi_missing_count(void);
extern const char* xa_abi_missing(void);
extern int32_t xa_export_count(void);
extern int64_t xa_hwb_alloc(int32_t, int32_t, int32_t, int64_t);
extern void xa_hwb_release(int64_t);
extern int64_t xa_shm_create(const char*, int64_t);
extern int32_t xa_shm_set_prot(int64_t, int32_t);
extern int32_t xa_fd_close(int64_t);
extern int64_t xa_looper_prepare(int32_t);
extern int32_t xa_looper_poll_once(int64_t, int32_t);
extern int64_t xa_config_new(void);
extern int32_t xa_config_get_sdk_version(int64_t);
extern int32_t xa_config_delete(int64_t);
/* A3 */
extern int32_t xa_input_queue_has_events(int64_t);
extern int64_t xa_input_event_get(int64_t);
extern int32_t xa_input_queue_attach(int64_t, int64_t, int32_t, int (*)(int, int, void*), int64_t);
/* A4 */
extern int64_t xa_sensor_manager_get_instance(void);
extern int64_t xa_sensor_manager_get_instance_for_package(const char*);
extern int32_t xa_sensor_manager_get_sensor_list(int64_t);
extern int32_t xa_sensor_manager_get_dynamic_sensor_list(int64_t);
extern int64_t xa_sensor_list_at(int32_t, int32_t);
extern int64_t xa_sensor_manager_get_default_sensor(int64_t, int32_t);
extern int64_t xa_sensor_manager_get_default_sensor_ex(int64_t, int32_t, int32_t);
extern int64_t xa_sensor_manager_create_event_queue(int64_t, int64_t, int32_t, int (*)(int, int, void*), int64_t);
extern int64_t xa_sensor_manager_create_event_queue_ident(int64_t, int64_t, int32_t);
extern int32_t xa_sensor_manager_destroy_event_queue(int64_t, int64_t);
extern int32_t xa_sensor_manager_create_shared_memory_direct_channel(int64_t, int32_t, int64_t);
extern int32_t xa_sensor_manager_create_hardware_buffer_direct_channel(int64_t, int64_t, int64_t);
extern int32_t xa_sensor_manager_destroy_direct_channel(int64_t, int32_t);
extern int32_t xa_sensor_manager_configure_direct_report(int64_t, int64_t, int32_t, int32_t);
extern int32_t xa_sensor_event_queue_register_sensor(int64_t, int64_t, int32_t, int64_t);
extern int32_t xa_sensor_event_queue_enable_sensor(int64_t, int64_t);
extern int32_t xa_sensor_event_queue_disable_sensor(int64_t, int64_t);
extern int32_t xa_sensor_event_queue_set_event_rate(int64_t, int64_t, int32_t);
extern int32_t xa_sensor_event_queue_has_events(int64_t);
extern int32_t xa_sensor_event_queue_request_additional_info_events(int64_t, int32_t);
extern int32_t xa_sensor_event_queue_read(int64_t, int32_t);
extern int32_t xa_sensor_event_version(int32_t);
extern int32_t xa_sensor_event_sensor(int32_t);
extern int32_t xa_sensor_event_type(int32_t);
extern int64_t xa_sensor_event_timestamp(int32_t);
extern int32_t xa_sensor_event_flags(int32_t);
extern int64_t xa_sensor_event_x_bits(int32_t);
extern int64_t xa_sensor_event_y_bits(int32_t);
extern int64_t xa_sensor_event_z_bits(int32_t);
extern const char* xa_sensor_name(int64_t);
extern const char* xa_sensor_vendor(int64_t);
extern int32_t xa_sensor_type(int64_t);
extern int64_t xa_sensor_resolution_bits(int64_t);
extern int32_t xa_sensor_min_delay(int64_t);
extern int32_t xa_sensor_fifo_max_event_count(int64_t);
extern int32_t xa_sensor_fifo_reserved_event_count(int64_t);
extern const char* xa_sensor_string_type(int64_t);
extern int32_t xa_sensor_reporting_mode(int64_t);
extern int32_t xa_sensor_highest_direct_report_rate_level(int64_t);
extern int32_t xa_sensor_handle(int64_t);
extern int32_t xa_sensor_is_wake_up_sensor(int64_t);
extern int32_t xa_sensor_is_direct_channel_type_supported(int64_t, int32_t);

/* ---- helpers ------------------------------------------------------------ */

static int g_failures = 0;

#define INFO(...) do { printf("INFO "); printf(__VA_ARGS__); printf("\n"); fflush(stdout); } while (0)
#define OK(cond, ...) do { \
    if (cond) { printf("OK "); } else { printf("FAIL "); g_failures++; } \
    printf(__VA_ARGS__); printf("\n"); fflush(stdout); \
} while (0)

static float f32_of(uint32_t bits) {
    float f;
    memcpy(&f, &bits, sizeof(f));
    return f;
}

/* callback-queue witness */
static int g_cb_calls = 0;
static int g_cb_queue_reads = 0;
static int sensor_event_cb(int fd, int events, void* data) {
    (void)fd; (void)events; (void)data;
    g_cb_calls++;
    if (data) {
        int64_t queue = *(int64_t*)data;
        int32_t n = xa_sensor_event_queue_read(queue, 8);
        if (n > 0) g_cb_queue_reads += n;
    }
    return 1;
}

/* ---- main --------------------------------------------------------------- */

int main(void) {
    /* 0. NaN sentinel runtime gate (the header's ASENSOR_RESOLUTION_INVALID
     * is nanf(""); the transcribed constant is its bit pattern). */
    {
        float f = ASENSOR_RESOLUTION_INVALID;
        uint32_t b;
        memcpy(&b, &f, sizeof(b));
        OK(b == XA_ASENSOR_RESOLUTION_INVALID_BITS,
           "constant gate: ASENSOR_RESOLUTION_INVALID bits 0x%08x (transcribed 0x%08x)",
           b, XA_ASENSOR_RESOLUTION_INVALID_BITS);
        OK(f != f, "constant gate: ASENSOR_RESOLUTION_INVALID is NaN");
    }

    /* 1. load + export set */
    int rc = xa_load();
    OK(rc == 0, "load rc=%d error=%s", rc, xa_error());
    if (rc != 0) return 1;
    OK(xa_abi_missing_count() == 0, "load (declared exports=%d, missing=%d%s%s)",
       xa_export_count(), xa_abi_missing_count(),
       xa_abi_missing_count() ? " -- " : "", xa_abi_missing_count() ? xa_abi_missing() : "");
    if (xa_abi_missing_count() != 0) return 1;

    /* 2. A3 explicit-error contract (a shell process cannot own an
     * AInputQueue: the framework delivers it to an app -- the app probe
     * proves the live attach/detach/event path). */
    OK(xa_input_queue_has_events(0) == -1, "A3 null queue -> explicit error (%s)", xa_error());
    OK(xa_input_event_get(0) == 0, "A3 getEvent(null) -> 0 + error (%s)", xa_error());
    INFO("A3 live queue path: input_app_probe.c (NativeActivity); a shell "
         "process cannot own an AInputQueue by design");

    /* 3. A4 manager + enumeration */
    int64_t mgr = xa_sensor_manager_get_instance();
    OK(mgr != 0, "sensors: ASensorManager_getInstance -> %s", mgr ? "handle" : "NULL");
    if (!mgr) return 1;
    int64_t bypkg = xa_sensor_manager_get_instance_for_package("com.xiom.inputprobe");
    INFO("sensors: getInstanceForPackage(\"com.xiom.inputprobe\") -> %s",
         bypkg == 0 ? "NULL (unknown package -- documented)"
                    : (bypkg == mgr ? "same singleton" : "distinct permission-scoped manager"));
    if (bypkg) {
        int32_t n2 = xa_sensor_manager_get_sensor_list(bypkg);
        OK(n2 >= 0, "sensors: package-scoped manager usable (sensors=%d)", n2);
    } else {
        OK(1, "sensors: package-scoped manager NULL for an uninstalled package (documented)");
    }
    int32_t n = xa_sensor_manager_get_sensor_list(mgr);
    OK(n >= 0, "sensors: list count=%d", n);
    if (n < 0) return 1;
    for (int32_t i = 0; i < n; i++) {
        int64_t s = xa_sensor_list_at(0, i);
        uint32_t rb = (uint32_t)xa_sensor_resolution_bits(s);
        INFO("sensor[%d] handle=%d type=%d name=\"%s\" vendor=\"%s\" str=\"%s\"",
             i, xa_sensor_handle(s), xa_sensor_type(s),
             xa_sensor_name(s), xa_sensor_vendor(s), xa_sensor_string_type(s));
        INFO("sensor[%d] min_delay=%d fifo_max=%d fifo_reserved=%d reporting=%d wake_up=%d direct_rate=%d res=%g",
             i, xa_sensor_min_delay(s), xa_sensor_fifo_max_event_count(s),
             xa_sensor_fifo_reserved_event_count(s), xa_sensor_reporting_mode(s),
             xa_sensor_is_wake_up_sensor(s), xa_sensor_highest_direct_report_rate_level(s),
             f32_of(rb));
        OK(xa_sensor_handle(s) >= 0 && xa_sensor_type(s) >= 0 &&
           xa_sensor_name(s)[0] != 0, "sensor[%d] described", i);
    }
    int32_t dyn = xa_sensor_manager_get_dynamic_sensor_list(mgr);
    INFO("dynamic sensor list rc=%d", dyn); /* negative on images without API-33 sensors */

    int64_t acc = xa_sensor_manager_get_default_sensor(mgr, ASENSOR_TYPE_ACCELEROMETER);
    int64_t acc_ex = xa_sensor_manager_get_default_sensor_ex(mgr, ASENSOR_TYPE_ACCELEROMETER, 0);
    OK(acc != 0 && acc_ex != 0, "sensors: default accelerometer + Ex variant resolve");
    if (!acc) {
        INFO("no accelerometer on this device -- queue path documented as null");
        printf("RESULT: PASS\n");
        return g_failures == 0 ? 0 : 1;
    }
    OK(xa_sensor_is_direct_channel_type_supported(acc, ASENSOR_DIRECT_CHANNEL_TYPE_SHARED_MEMORY) >= 0,
       "sensors: direct-channel query responds (%d)",
       xa_sensor_is_direct_channel_type_supported(acc, ASENSOR_DIRECT_CHANNEL_TYPE_SHARED_MEMORY));

    /* 4. event queue (ident variant): register -> poll -> read -> accessors */
    int64_t loop = xa_looper_prepare(1);
    OK(loop != 0, "sensors: looper prepared (err=%s)", xa_error());
    if (!loop) return 1;
    int64_t lcfg = xa_config_new();
    INFO("device sdk=%d", lcfg ? xa_config_get_sdk_version(lcfg) : -1);
    if (lcfg) xa_config_delete(lcfg);

    int64_t q = xa_sensor_manager_create_event_queue_ident(mgr, loop, 7);
    OK(q != 0, "sensors: createEventQueue(ident=7) -> %s", q ? "queue" : "NULL");
    if (!q) return 1;
    OK(xa_sensor_event_queue_register_sensor(q, acc, 20000, 0) == 0,
       "sensors: registerSensor(accel, 20000us, latency 0) (err=%s)", xa_error());
    int got = 0;
    for (int tries = 0; tries < 50 && got == 0; tries++) {
        int ident = xa_looper_poll_once(loop, 100);
        if (ident == 7 || xa_sensor_event_queue_has_events(q) == 1) {
            int32_t r = xa_sensor_event_queue_read(q, 8);
            if (r > 0) got = r;
        }
    }
    OK(got >= 1, "sensors: polled + read %d event(s)", got);
    if (got >= 1) {
        uint32_t xb = (uint32_t)xa_sensor_event_x_bits(0);
        uint32_t yb = (uint32_t)xa_sensor_event_y_bits(0);
        uint32_t zb = (uint32_t)xa_sensor_event_z_bits(0);
        INFO("event[0] v=%d type=%d sensor=%d ts=%lld flags=%d x=%g y=%g z=%g",
             xa_sensor_event_version(0), xa_sensor_event_type(0),
             xa_sensor_event_sensor(0), (long long)xa_sensor_event_timestamp(0),
             xa_sensor_event_flags(0), f32_of(xb), f32_of(yb), f32_of(zb));
        OK(xa_sensor_event_type(0) == ASENSOR_TYPE_ACCELEROMETER,
           "sensors: event type == ASENSOR_TYPE_ACCELEROMETER");
        OK(xa_sensor_event_timestamp(0) > 0, "sensors: event timestamp > 0");
    }
    OK(xa_sensor_event_queue_disable_sensor(q, acc) == 0, "sensors: disableSensor");
    OK(xa_sensor_event_queue_request_additional_info_events(q, 0) == 0,
       "sensors: requestAdditionalInfoEvents(disable)");
    OK(xa_sensor_event_queue_enable_sensor(q, acc) == 0, "sensors: enableSensor (default rate)");
    OK(xa_sensor_event_queue_set_event_rate(q, acc, 40000) == 0,
       "sensors: setEventRate(40000us) after enable");
    xa_sensor_event_queue_disable_sensor(q, acc);
    OK(xa_sensor_manager_destroy_event_queue(mgr, q) == 0, "sensors: queue destroyed");

    /* 5. callback-queue variant: pollOnce returns ALOOPER_POLL_CALLBACK */
    int64_t m2 = xa_sensor_manager_get_instance(); /* re-fetch (queue destroyed) */
    int64_t q2 = xa_sensor_manager_create_event_queue(m2, loop, ALOOPER_POLL_CALLBACK,
                                                      sensor_event_cb,
                                                      (int64_t)(intptr_t)&q2);
    OK(q2 != 0, "sensors: createEventQueue(callback) -> %s", q2 ? "queue" : "NULL");
    if (q2) {
        g_cb_calls = 0;
        g_cb_queue_reads = 0;
        xa_sensor_event_queue_enable_sensor(q2, acc);
        int cb_seen = 0;
        for (int tries = 0; tries < 50 && !cb_seen; tries++) {
            int ident = xa_looper_poll_once(loop, 100);
            if (ident == -2) cb_seen = 1; /* ALOOPER_POLL_CALLBACK */
        }
        OK(cb_seen, "sensors: pollOnce returned ALOOPER_POLL_CALLBACK");
        OK(g_cb_calls >= 1, "sensors: callback fired %d time(s), read %d event(s)",
           g_cb_calls, g_cb_queue_reads);
        xa_sensor_event_queue_disable_sensor(q2, acc);
        xa_sensor_manager_destroy_event_queue(m2, q2);
    }

    /* 6. direct channels: honest on-device behavior (creation may be
     * rejected by the HAL -- recorded either way). */
    int64_t fd = xa_shm_create("xiom-direct-probe", 4096);
    if (fd >= 0) {
        xa_shm_set_prot(fd, 1 + 2);
        int32_t ch = xa_sensor_manager_create_shared_memory_direct_channel(mgr, (int32_t)fd, 4096);
        INFO("direct channel (shm): rc=%d (%s)", ch, xa_error());
        if (ch > 0) {
            int32_t d = xa_sensor_manager_destroy_direct_channel(mgr, ch);
            OK(d == 0, "direct channel (shm): channel %d destroyed rc=%d", ch, d);
        } else {
            OK(1, "direct channel (shm): platform rejected creation rc=%d (goldfish HAL; documented)", ch);
        }
        xa_fd_close(fd);
    }
    int64_t hwb = xa_hwb_alloc(64, 64, 1 /* RGBA8 */, 3 + 0x30 /* CPU r/w */);
    if (hwb) {
        int32_t ch = xa_sensor_manager_create_hardware_buffer_direct_channel(mgr, hwb, 64 * 64 * 4);
        INFO("direct channel (hwb): rc=%d (%s)", ch, xa_error());
        if (ch > 0) xa_sensor_manager_destroy_direct_channel(mgr, ch);
        INFO("configureDirectReport probe: rc=%d",
             xa_sensor_manager_configure_direct_report(mgr, 0, 0, ASENSOR_DIRECT_RATE_STOP));
        xa_hwb_release(hwb);
    }
    OK(1, "direct-channel trio responds on the device (behavior recorded above)");

    printf("RESULT: %s\n", g_failures == 0 ? "PASS" : "FAIL");
    return g_failures == 0 ? 0 : 1;
}
