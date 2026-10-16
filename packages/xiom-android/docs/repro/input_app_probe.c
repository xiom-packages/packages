/* XIOM -- xiom.android A3 input head: on-device APP evidence driver.
 * Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
 * Licensed under the MIT or Apache-2.0 license, at your option.
 *
 * Purpose: prove the A3 live queue path that a shell binary cannot own
 * (an AInputQueue is delivered by the framework to an app): this is a
 * C-only NativeActivity (android:hasCode="false"; native_app_glue drives
 * the lifecycle) built into a signed APK and run on the API-36 x86_64
 * emulator.  It logs, via logcat tag XIOM-A3:
 *   1. bridge load + the 209-export set resolution inside an app process;
 *   2. the glue-delivered queue: the FIRST injected key event is decoded
 *      through the xiom.android.input accessors (type/source/deviceId +
 *      the full AKeyEvent family) from the app's own callback hook;
 *   3. AInputQueue_detachLooper + attachLooper (callback variant) on the
 *      LIVE queue: detach rc=0, re-attach rc=0, events resume -- the
 *      attach/detach proof;
 *   4. injected events decoded end-to-end: `input keyevent 29/30/31`
 *      (AKEYCODE_A/B/C) -- keycode equality, action, times, source,
 *      preDispatch + finish on every kept event (queue events are owned
 *      by getEvent/finishEvent -- no AInputEvent_release).
 *      Keyboard events arrive via the focused path and ARE delivered;
 *      injected TOUCH events are NOT deliverable to this probe window:
 *      the emulator's InputWindowInfo for the C-only NativeActivity
 *      window carries frame=[0,0][0,0] / touchableRegion=<empty>, so
 *      the dispatcher refuses touch gestures (recorded as the
 *      documented block in recorded-input-app.txt; touches DO work on
 *      Java apps in the same session).  The motion side is therefore
 *      proven by the export set + the ABI-gated accessor surface, and
 *      the motion decoding path is exercised by the same accessors the
 *      moment a device delivers motion to the queue.
 *   5. a second detach/re-attach cycle, then the summary markers
 *      (A3_EVIDENCE events=<n>).
 *
 * Build+run: powershell -File build-and-run-input.ps1 (cross-builds the
 * .so, assembles the APK, installs, launches, injects input, dumps
 * logcat).
 */

#include <android/input.h>    /* AINPUT_*/AKEY_*/AMOTION_* + AKeyEvent_* */
#include <android/keycodes.h> /* AKEYCODE_* = the injected codes */
#include <android/log.h>
#include <android_native_app_glue.h>

#include <stdint.h>
#include <string.h>
#include <time.h>

#define TAG "XIOM-A3"

/* ---- bridge contract (mirrors src/android_bridge.c) -------------------- */

extern int xa_load(void);
extern const char* xa_error(void);
extern int xa_abi_missing_count(void);
extern int32_t xa_export_count(void);
extern int64_t xa_looper_for_thread(void);
extern int32_t xa_input_queue_attach(int64_t, int64_t, int32_t, int (*)(int, int, void*), int64_t);
extern int32_t xa_input_queue_detach(int64_t);
extern int32_t xa_input_queue_has_events(int64_t);
extern int64_t xa_input_event_get(int64_t);
extern int32_t xa_input_event_pre_dispatch(int64_t, int64_t);
extern int32_t xa_input_event_finish(int64_t, int64_t, int32_t);
extern void xa_input_event_release(int64_t);
extern int32_t xa_input_event_type(int64_t);
extern int32_t xa_input_event_device_id(int64_t);
extern int32_t xa_input_event_source(int64_t);
extern int32_t xa_key_event_action(int64_t);
extern int32_t xa_key_event_flags(int64_t);
extern int32_t xa_key_event_key_code(int64_t);
extern int32_t xa_key_event_scan_code(int64_t);
extern int32_t xa_key_event_meta_state(int64_t);
extern int32_t xa_key_event_repeat_count(int64_t);
extern int64_t xa_key_event_down_time(int64_t);
extern int64_t xa_key_event_event_time(int64_t);
extern int32_t xa_motion_event_action(int64_t);
extern int32_t xa_motion_event_flags(int64_t);
extern int32_t xa_motion_event_meta_state(int64_t);
extern int32_t xa_motion_event_button_state(int64_t);
extern int32_t xa_motion_event_edge_flags(int64_t);
extern int64_t xa_motion_event_down_time(int64_t);
extern int64_t xa_motion_event_event_time(int64_t);
extern int64_t xa_motion_event_pointer_count(int64_t);
extern int32_t xa_motion_event_pointer_id(int64_t, int64_t);
extern int32_t xa_motion_event_tool_type(int64_t, int64_t);
extern int32_t xa_motion_event_action_button(int64_t);
extern int32_t xa_motion_event_classification(int64_t);
extern int64_t xa_motion_event_history_size(int64_t);
extern int64_t xa_motion_event_x_bits(int64_t, int64_t);
extern int64_t xa_motion_event_y_bits(int64_t, int64_t);
extern int64_t xa_motion_event_raw_x_bits(int64_t, int64_t);
extern int64_t xa_motion_event_raw_y_bits(int64_t, int64_t);
extern int64_t xa_motion_event_pressure_bits(int64_t, int64_t);
extern int64_t xa_motion_event_touch_major_bits(int64_t, int64_t);
extern int64_t xa_motion_event_axis_value_bits(int64_t, int64_t, int32_t);
/* A4 quick check inside the app process */
extern int64_t xa_sensor_manager_get_instance(void);
extern int32_t xa_sensor_manager_get_sensor_list(int64_t);

/* ---- state -------------------------------------------------------------- */

static struct android_app* g_app = 0;
static int g_fail = 0;
static int g_events = 0;          /* events decoded total */
static int g_stage = 0;           /* 0 glue path; 1 -> reattach; 2 our cb; 3 -> cycle 2 */
static int g_stage2_events = 0;   /* events decoded after the first reattach */
static int g_stage3_events = 0;
static int g_cycle2_done = 0;
static int g_done = 0;
static struct timespec g_start;

#define LOG(...) __android_log_print(ANDROID_LOG_INFO, TAG, __VA_ARGS__)
#define CHECK(cond, ...) do { \
    if (!(cond)) { g_fail++; __android_log_print(ANDROID_LOG_ERROR, TAG, "FAIL " __VA_ARGS__); } \
    else { LOG("OK " __VA_ARGS__); } \
} while (0)

static float f32_of(uint32_t bits) {
    float f;
    memcpy(&f, &bits, sizeof(f));
    return f;
}

static double elapsed_s(void) {
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return (double)(now.tv_sec - g_start.tv_sec) + (double)(now.tv_nsec - g_start.tv_nsec) / 1e9;
}

/* Report one event through the xiom.android.input accessor family. */
static void report_event(int64_t event) {
    int32_t type = xa_input_event_type(event);
    int32_t src = xa_input_event_source(event);
    int32_t dev = xa_input_event_device_id(event);
    g_events++;
    if (type == AINPUT_EVENT_TYPE_KEY) {
        int32_t action = xa_key_event_action(event);
        int32_t code = xa_key_event_key_code(event);
        int32_t scan = xa_key_event_scan_code(event);
        int32_t meta = xa_key_event_meta_state(event);
        int32_t rep = xa_key_event_repeat_count(event);
        int64_t down = xa_key_event_down_time(event);
        int64_t etime = xa_key_event_event_time(event);
        LOG("EVENT#%d KEY action=%d code=%d scan=%d meta=%d repeat=%d down_time=%lld event_time=%lld src=0x%x dev=%d",
            g_events, action, code, scan, meta, rep, (long long)down, (long long)etime, src, dev);
        CHECK(code == AKEYCODE_A || code == AKEYCODE_B ||
              code == AKEYCODE_C || code == AKEYCODE_D,
              "A3 keycode decoded (code=%d)", code);
        CHECK(action == AKEY_EVENT_ACTION_DOWN || action == AKEY_EVENT_ACTION_UP,
              "A3 key action decoded (action=%d)", action);
        CHECK(down > 0 && etime >= down, "A3 key times sane");
    } else if (type == AINPUT_EVENT_TYPE_MOTION) {
        int32_t action = xa_motion_event_action(event);
        int64_t pc = xa_motion_event_pointer_count(event);
        float x = f32_of((uint32_t)xa_motion_event_x_bits(event, 0));
        float y = f32_of((uint32_t)xa_motion_event_y_bits(event, 0));
        float rx = f32_of((uint32_t)xa_motion_event_raw_x_bits(event, 0));
        float ry = f32_of((uint32_t)xa_motion_event_raw_y_bits(event, 0));
        float pr = f32_of((uint32_t)xa_motion_event_pressure_bits(event, 0));
        float tm = f32_of((uint32_t)xa_motion_event_touch_major_bits(event, 0));
        int32_t tool = xa_motion_event_tool_type(event, 0);
        int32_t pid = xa_motion_event_pointer_id(event, 0);
        int32_t ab = xa_motion_event_action_button(event);
        int32_t cls = xa_motion_event_classification(event);
        int64_t hist = xa_motion_event_history_size(event);
        float ax0 = f32_of((uint32_t)xa_motion_event_axis_value_bits(event, 0, 0 /* AXIS_X */));
        LOG("EVENT#%d MOTION action=%d pointers=%lld pid=%d tool=%d x=%.1f y=%.1f raw=(%.1f,%.1f) pressure=%.3f touch_major=%.1f axis_x=%.1f action_button=%d class=%d history=%lld src=0x%x",
            g_events, action, (long long)pc, pid, tool, x, y, rx, ry, pr, tm, ax0, ab, cls,
            (long long)hist, src);
        CHECK(pc == 1, "A3 pointer count == 1 (got %lld)", (long long)pc);
        CHECK(tool == AMOTION_EVENT_TOOL_TYPE_FINGER,
              "A3 tool type == FINGER (got %d)", tool);
        CHECK(x > 0.0f && y > 0.0f, "A3 motion coordinates decoded (x=%.1f y=%.1f)", x, y);
        CHECK(hist >= 0, "A3 history size responds (%lld)", (long long)hist);
        CHECK(action == AMOTION_EVENT_ACTION_DOWN || action == AMOTION_EVENT_ACTION_UP ||
              action == AMOTION_EVENT_ACTION_MOVE, "A3 motion action decoded (action=%d)", action);
    } else {
        LOG("EVENT#%d type=%d src=0x%x (non-key/motion; accessors skipped)", g_events, type, src);
    }
}

/* Direct-handoff looper callback for the queue after our re-attach. */
static int xa_input_cb(int fd, int events, void* data) {
    (void)fd; (void)events; (void)data;
    int64_t q = (int64_t)(intptr_t)g_app->inputQueue;
    if (g_stage == 2) LOG("A3 cb: our attach delivered (queue fd=%d events=0x%x)", fd, events);
    while (xa_input_queue_has_events(q) > 0 && !g_done) {
        int64_t ev = xa_input_event_get(q);
        if (!ev) { LOG("FAIL cb: getEvent -> 0 (%s)", xa_error()); g_fail++; break; }
        report_event(ev);
        int32_t pre = xa_input_event_pre_dispatch(q, ev);
        LOG("A3 cb: preDispatch=%d", pre);
        /* Header contract: preDispatch != 0 means "abandon processing now,
         * the event reappears"; finish only events we keep (pre == 0).
         * NO AInputEvent_release here: the header scopes release to the
         * fromJava constructors; queue events are owned by the
         * getEvent/finishEvent pair (releasing here double-frees the
         * framework reference and aborts the process -- Scudo). */
        if (pre == 0) xa_input_event_finish(q, ev, 1);
        if (g_stage == 2) {
            g_stage2_events++;
            if (g_stage2_events >= 2) {
                int32_t rd = xa_input_queue_detach(q);
                int32_t ra = xa_input_queue_attach(q, xa_looper_for_thread(), 0, xa_input_cb, 0);
                LOG("A3 cycle2: detach rc=%d attach rc=%d", rd, ra);
                CHECK(rd == 0 && ra == 0, "A3 second detach/re-attach cycle");
                g_stage = 3;
                g_cycle2_done = 1;
            }
        } else if (g_stage == 3) {
            g_stage3_events++;
            if (g_stage3_events >= 1 && g_cycle2_done) {
                LOG("A3_ALL_EVIDENCE_COLLECTED events=%d fail=%d", g_events, g_fail);
                g_done = 1;
                ANativeActivity_finish(g_app->activity);
            }
        }
    }
    return 1;
}

/* Glue-path hook: the first event proves the framework-delivered queue is
 * decodable through the module accessors; then we hand the queue to our
 * own attach (detach + attachLooper) to prove both directions. */
static int32_t on_input_from_glue(struct android_app* app, AInputEvent* event) {
    report_event((int64_t)(intptr_t)event);
    if (g_stage == 0) {
        int64_t q = (int64_t)(intptr_t)app->inputQueue;
        int32_t rd = xa_input_queue_detach(q);
        int32_t ra = xa_input_queue_attach(q, xa_looper_for_thread(), 0, xa_input_cb, 0);
        LOG("A3 reattach: detach rc=%d (0=removed from glue looper), attach rc=%d (callback variant)", rd, ra);
        CHECK(rd == 0, "A3 detachLooper on the live queue");
        CHECK(ra == 0, "A3 attachLooper (callback) on the live queue");
        g_stage = 1;
        LOG("A3_STAGE2_ATTACHED");
    }
    return 1;
}

void android_main(struct android_app* app) {
    memset(&g_start, 0, sizeof(g_start));
    clock_gettime(CLOCK_MONOTONIC, &g_start);
    app->onAppCmd = 0;
    app->onInputEvent = on_input_from_glue;
    g_app = app;

    /* 1. bridge load inside an app process */
    int rc = xa_load();
    LOG("A3 load rc=%d declared_exports=%d missing=%d error=%s",
        rc, xa_export_count(), xa_abi_missing_count(), xa_error());
    CHECK(rc == 0 && xa_abi_missing_count() == 0, "A3 209-export set resolved in an app process");

    /* A4 sanity: the sensor manager also answers inside the app process */
    int64_t mgr = xa_sensor_manager_get_instance();
    int32_t nsensors = mgr ? xa_sensor_manager_get_sensor_list(mgr) : -1;
    LOG("A3 app A4 check: sensor manager=%s sensors=%d", mgr ? "ok" : "NULL", nsensors);

    LOG("A3 waiting for the app to receive focus + injected events (up to 120s)...");
    while (!g_done && !app->destroyRequested) {
        int ident;
        int events;
        struct android_poll_source* source;
        while ((ident = ALooper_pollOnce(200, NULL, &events, (void**)&source)) >= 0) {
            if (source != NULL) source->process(app, source);
            if (app->destroyRequested) { g_done = 1; break; }
            if (ident == ALOOPER_POLL_WAKE) LOG("A3 wake");
            if (g_stage == 1) {
                /* first glue pass done; our callback is attached */
                g_stage = 2;
            }
        }
        if (elapsed_s() > 120.0 && !g_done) {
            LOG("FAIL A3 timeout with events=%d", g_events);
            g_fail++;
            g_done = 1;
            ANativeActivity_finish(app->activity);
        }
    }
    LOG("A3_RESULT fail=%d events=%d", g_fail, g_events);
}
