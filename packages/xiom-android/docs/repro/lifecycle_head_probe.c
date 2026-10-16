/* XIOM -- xiom.android A2 lifecycle-glue head: on-device evidence driver.
 * Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
 * Licensed under the MIT or Apache-2.0 license, at your option.
 *
 * Purpose: prove, on the API-36 x86_64 emulator, the exact things the
 * package claims (W2c):
 *   1. every constant transcribed into src/lifecycle.xi and
 *      src/configuration.xi matches the pinned NDK headers
 *      (android/looper.h, android/native_activity.h,
 *      android/configuration.h, r27b) -- checked AT BUILD TIME against
 *      the real headers (static asserts below);
 *   2. the runtime bridge (src/android_bridge.c, compiled into this
 *      driver) loads libandroid.so/libnativewindow.so and resolves the
 *      declared 117-export set (0 missing);
 *   3. A1/A5 functional blocks stay green (AHardwareBuffer +
 *      ASharedMemory roundtrips);
 *   4. the ALooper works for real: prepare(ALLOW_NON_CALLBACKS) ->
 *      pipe(2) -> addFd(NULL callback, ident) -> write -> pollOnce
 *      returns the ident; addFd(C callback) -> write -> pollOnce
 *      returns ALOOPER_POLL_CALLBACK and the callback observed
 *      (fd, events, data); timeout; wake -> POLL_WAKE; removeFd;
 *      pollAll smoke; acquire/release;
 *   5. the AConfiguration value object works for real: new -> set
 *      language/country/orientation/density/screen-size/sdk -> exact
 *      read-back; diff mask vs a fresh config; copy clone -> diff 0;
 *      match; delete.
 *
 * Build+run: powershell -File build-and-run.ps1 (cross-builds for
 * x86_64-linux-android26, pushes to /data/local/tmp/xiom-spike/, runs).
 */

#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include <android/looper.h>          /* the oracle (build-time gate) */
#include <android/native_activity.h> /* the oracle (build-time gate) */
#include <android/configuration.h>   /* the oracle (build-time gate) */

/* ---- build-time constant transcription gate (module <-> header) --------
 * Each assert pairs a literal embedded in the XIOM modules with the real
 * header value.  A transcription typo fails this build. */

_Static_assert(ALOOPER_PREPARE_ALLOW_NON_CALLBACKS == 1, "looper const drift");
_Static_assert(ALOOPER_POLL_WAKE == -1, "looper const drift");
_Static_assert(ALOOPER_POLL_CALLBACK == -2, "looper const drift");
_Static_assert(ALOOPER_POLL_TIMEOUT == -3, "looper const drift");
_Static_assert(ALOOPER_POLL_ERROR == -4, "looper const drift");
_Static_assert(ALOOPER_EVENT_INPUT == 1, "looper const drift");
_Static_assert(ALOOPER_EVENT_OUTPUT == 2, "looper const drift");
_Static_assert(ALOOPER_EVENT_ERROR == 4, "looper const drift");
_Static_assert(ALOOPER_EVENT_HANGUP == 8, "looper const drift");
_Static_assert(ALOOPER_EVENT_INVALID == 16, "looper const drift");

_Static_assert(ANATIVEACTIVITY_SHOW_SOFT_INPUT_IMPLICIT == 1, "activity const drift");
_Static_assert(ANATIVEACTIVITY_SHOW_SOFT_INPUT_FORCED == 2, "activity const drift");
_Static_assert(ANATIVEACTIVITY_HIDE_SOFT_INPUT_IMPLICIT_ONLY == 1, "activity const drift");
_Static_assert(ANATIVEACTIVITY_HIDE_SOFT_INPUT_NOT_ALWAYS == 2, "activity const drift");

_Static_assert(ACONFIGURATION_ORIENTATION_ANY == 0x0000, "config const drift");
_Static_assert(ACONFIGURATION_ORIENTATION_PORT == 0x0001, "config const drift");
_Static_assert(ACONFIGURATION_ORIENTATION_LAND == 0x0002, "config const drift");
_Static_assert(ACONFIGURATION_ORIENTATION_SQUARE == 0x0003, "config const drift");
_Static_assert(ACONFIGURATION_TOUCHSCREEN_ANY == 0x0000, "config const drift");
_Static_assert(ACONFIGURATION_TOUCHSCREEN_NOTOUCH == 0x0001, "config const drift");
_Static_assert(ACONFIGURATION_TOUCHSCREEN_STYLUS == 0x0002, "config const drift");
_Static_assert(ACONFIGURATION_TOUCHSCREEN_FINGER == 0x0003, "config const drift");
_Static_assert(ACONFIGURATION_DENSITY_DEFAULT == 0, "config const drift");
_Static_assert(ACONFIGURATION_DENSITY_LOW == 120, "config const drift");
_Static_assert(ACONFIGURATION_DENSITY_MEDIUM == 160, "config const drift");
_Static_assert(ACONFIGURATION_DENSITY_TV == 213, "config const drift");
_Static_assert(ACONFIGURATION_DENSITY_HIGH == 240, "config const drift");
_Static_assert(ACONFIGURATION_DENSITY_XHIGH == 320, "config const drift");
_Static_assert(ACONFIGURATION_DENSITY_XXHIGH == 480, "config const drift");
_Static_assert(ACONFIGURATION_DENSITY_XXXHIGH == 640, "config const drift");
_Static_assert(ACONFIGURATION_DENSITY_ANY == 0xfffe, "config const drift");
_Static_assert(ACONFIGURATION_DENSITY_NONE == 0xffff, "config const drift");
_Static_assert(ACONFIGURATION_KEYBOARD_ANY == 0x0000, "config const drift");
_Static_assert(ACONFIGURATION_KEYBOARD_NOKEYS == 0x0001, "config const drift");
_Static_assert(ACONFIGURATION_KEYBOARD_QWERTY == 0x0002, "config const drift");
_Static_assert(ACONFIGURATION_KEYBOARD_12KEY == 0x0003, "config const drift");
_Static_assert(ACONFIGURATION_NAVIGATION_ANY == 0x0000, "config const drift");
_Static_assert(ACONFIGURATION_NAVIGATION_NONAV == 0x0001, "config const drift");
_Static_assert(ACONFIGURATION_NAVIGATION_DPAD == 0x0002, "config const drift");
_Static_assert(ACONFIGURATION_NAVIGATION_TRACKBALL == 0x0003, "config const drift");
_Static_assert(ACONFIGURATION_NAVIGATION_WHEEL == 0x0004, "config const drift");
_Static_assert(ACONFIGURATION_KEYSHIDDEN_ANY == 0x0000, "config const drift");
_Static_assert(ACONFIGURATION_KEYSHIDDEN_NO == 0x0001, "config const drift");
_Static_assert(ACONFIGURATION_KEYSHIDDEN_YES == 0x0002, "config const drift");
_Static_assert(ACONFIGURATION_KEYSHIDDEN_SOFT == 0x0003, "config const drift");
_Static_assert(ACONFIGURATION_NAVHIDDEN_ANY == 0x0000, "config const drift");
_Static_assert(ACONFIGURATION_NAVHIDDEN_NO == 0x0001, "config const drift");
_Static_assert(ACONFIGURATION_NAVHIDDEN_YES == 0x0002, "config const drift");
_Static_assert(ACONFIGURATION_SCREENSIZE_ANY == 0x00, "config const drift");
_Static_assert(ACONFIGURATION_SCREENSIZE_SMALL == 0x01, "config const drift");
_Static_assert(ACONFIGURATION_SCREENSIZE_NORMAL == 0x02, "config const drift");
_Static_assert(ACONFIGURATION_SCREENSIZE_LARGE == 0x03, "config const drift");
_Static_assert(ACONFIGURATION_SCREENSIZE_XLARGE == 0x04, "config const drift");
_Static_assert(ACONFIGURATION_SCREENLONG_ANY == 0x00, "config const drift");
_Static_assert(ACONFIGURATION_SCREENLONG_NO == 0x1, "config const drift");
_Static_assert(ACONFIGURATION_SCREENLONG_YES == 0x2, "config const drift");
_Static_assert(ACONFIGURATION_SCREENROUND_ANY == 0x00, "config const drift");
_Static_assert(ACONFIGURATION_SCREENROUND_NO == 0x1, "config const drift");
_Static_assert(ACONFIGURATION_SCREENROUND_YES == 0x2, "config const drift");
_Static_assert(ACONFIGURATION_WIDE_COLOR_GAMUT_ANY == 0x00, "config const drift");
_Static_assert(ACONFIGURATION_WIDE_COLOR_GAMUT_NO == 0x1, "config const drift");
_Static_assert(ACONFIGURATION_WIDE_COLOR_GAMUT_YES == 0x2, "config const drift");
_Static_assert(ACONFIGURATION_HDR_ANY == 0x00, "config const drift");
_Static_assert(ACONFIGURATION_HDR_NO == 0x1, "config const drift");
_Static_assert(ACONFIGURATION_HDR_YES == 0x2, "config const drift");
_Static_assert(ACONFIGURATION_UI_MODE_TYPE_ANY == 0x00, "config const drift");
_Static_assert(ACONFIGURATION_UI_MODE_TYPE_NORMAL == 0x01, "config const drift");
_Static_assert(ACONFIGURATION_UI_MODE_TYPE_DESK == 0x02, "config const drift");
_Static_assert(ACONFIGURATION_UI_MODE_TYPE_CAR == 0x03, "config const drift");
_Static_assert(ACONFIGURATION_UI_MODE_TYPE_TELEVISION == 0x04, "config const drift");
_Static_assert(ACONFIGURATION_UI_MODE_TYPE_APPLIANCE == 0x05, "config const drift");
_Static_assert(ACONFIGURATION_UI_MODE_TYPE_WATCH == 0x06, "config const drift");
_Static_assert(ACONFIGURATION_UI_MODE_TYPE_VR_HEADSET == 0x07, "config const drift");
_Static_assert(ACONFIGURATION_UI_MODE_NIGHT_ANY == 0x00, "config const drift");
_Static_assert(ACONFIGURATION_UI_MODE_NIGHT_NO == 0x1, "config const drift");
_Static_assert(ACONFIGURATION_UI_MODE_NIGHT_YES == 0x2, "config const drift");
_Static_assert(ACONFIGURATION_SCREEN_WIDTH_DP_ANY == 0x0000, "config const drift");
_Static_assert(ACONFIGURATION_SCREEN_HEIGHT_DP_ANY == 0x0000, "config const drift");
_Static_assert(ACONFIGURATION_SMALLEST_SCREEN_WIDTH_DP_ANY == 0x0000, "config const drift");
_Static_assert(ACONFIGURATION_LAYOUTDIR_ANY == 0x00, "config const drift");
_Static_assert(ACONFIGURATION_LAYOUTDIR_LTR == 0x01, "config const drift");
_Static_assert(ACONFIGURATION_LAYOUTDIR_RTL == 0x02, "config const drift");
_Static_assert(ACONFIGURATION_MCC == 0x0001, "config const drift");
_Static_assert(ACONFIGURATION_MNC == 0x0002, "config const drift");
_Static_assert(ACONFIGURATION_LOCALE == 0x0004, "config const drift");
_Static_assert(ACONFIGURATION_TOUCHSCREEN == 0x0008, "config const drift");
_Static_assert(ACONFIGURATION_KEYBOARD == 0x0010, "config const drift");
_Static_assert(ACONFIGURATION_KEYBOARD_HIDDEN == 0x0020, "config const drift");
_Static_assert(ACONFIGURATION_NAVIGATION == 0x0040, "config const drift");
_Static_assert(ACONFIGURATION_ORIENTATION == 0x0080, "config const drift");
_Static_assert(ACONFIGURATION_DENSITY == 0x0100, "config const drift");
_Static_assert(ACONFIGURATION_SCREEN_SIZE == 0x0200, "config const drift");
_Static_assert(ACONFIGURATION_VERSION == 0x0400, "config const drift");
_Static_assert(ACONFIGURATION_SCREEN_LAYOUT == 0x0800, "config const drift");
_Static_assert(ACONFIGURATION_UI_MODE == 0x1000, "config const drift");
_Static_assert(ACONFIGURATION_SMALLEST_SCREEN_SIZE == 0x2000, "config const drift");
_Static_assert(ACONFIGURATION_LAYOUTDIR == 0x4000, "config const drift");
_Static_assert(ACONFIGURATION_SCREEN_ROUND == 0x8000, "config const drift");
_Static_assert(ACONFIGURATION_COLOR_MODE == 0x10000, "config const drift");
_Static_assert(ACONFIGURATION_GRAMMATICAL_GENDER == 0x20000, "config const drift");
_Static_assert(ACONFIGURATION_MNC_ZERO == 0xffff, "config const drift");
_Static_assert(ACONFIGURATION_GRAMMATICAL_GENDER_ANY == 0, "config const drift");
_Static_assert(ACONFIGURATION_GRAMMATICAL_GENDER_NEUTER == 1, "config const drift");
_Static_assert(ACONFIGURATION_GRAMMATICAL_GENDER_FEMININE == 2, "config const drift");
_Static_assert(ACONFIGURATION_GRAMMATICAL_GENDER_MASCULINE == 3, "config const drift");

/* ---- bridge contract (mirrors packages/xiom-android/src/android_bridge.c) */

extern int xa_load(void);
extern const char* xa_error(void);
extern int xa_abi_missing_count(void);
extern const char* xa_abi_missing(void);
extern int32_t xa_export_count(void);
extern int32_t xa_hwb_is_supported(int32_t, int32_t, int32_t, int64_t);
extern int64_t xa_hwb_alloc(int32_t, int32_t, int32_t, int64_t);
extern int32_t xa_hwb_width(int64_t);
extern int32_t xa_hwb_height(int64_t);
extern int32_t xa_hwb_format(int64_t);
extern int32_t xa_hwb_stride(int64_t);
extern int32_t xa_hwb_layers(int64_t);
extern int32_t xa_hwb_write_pixel(int64_t, int32_t, int32_t, int32_t);
extern int64_t xa_hwb_read_pixel(int64_t, int32_t, int32_t);
extern void xa_hwb_release(int64_t);
extern int64_t xa_shm_create(const char*, int64_t);
extern int64_t xa_shm_get_size(int64_t);
extern int32_t xa_shm_set_prot(int64_t, int32_t);
extern int32_t xa_shm_write_probe(int64_t, int32_t);
extern int64_t xa_shm_read_probe(int64_t);
extern int32_t xa_fd_close(int64_t);
extern int64_t xa_looper_prepare(int32_t);
extern int64_t xa_looper_for_thread(void);
extern void xa_looper_acquire(int64_t);
extern void xa_looper_release(int64_t);
extern int32_t xa_looper_wake(int64_t);
extern int32_t xa_looper_add_fd(int64_t, int32_t, int32_t, int32_t, ALooper_callbackFunc, int64_t);
extern int32_t xa_looper_add_fd_ident(int64_t, int32_t, int32_t, int32_t);
extern int32_t xa_looper_remove_fd(int64_t, int32_t);
extern int32_t xa_looper_poll_once(int64_t, int32_t);
extern int32_t xa_looper_poll_all(int64_t, int32_t);
extern int32_t xa_looper_last_fd(void);
extern int32_t xa_looper_last_events(void);
extern int64_t xa_looper_last_data(void);
extern int64_t xa_pipe_open(void);
extern int32_t xa_pipe_write_byte(int32_t);
extern int32_t xa_pipe_read_byte(int32_t);
extern int32_t xa_pipe_close(int64_t);
extern int64_t xa_config_new(void);
extern int32_t xa_config_delete(int64_t);
extern int32_t xa_config_copy(int64_t, int64_t);
extern int32_t xa_config_diff(int64_t, int64_t);
extern int32_t xa_config_match(int64_t, int64_t);
extern int32_t xa_config_is_better_than(int64_t, int64_t, int64_t);
extern int32_t xa_config_get_screen_round(int64_t);
extern const char* xa_config_get_language(int64_t);
extern int32_t xa_config_set_language(int64_t, const char*);
extern const char* xa_config_get_country(int64_t);
extern int32_t xa_config_set_country(int64_t, const char*);
extern int32_t xa_config_get_orientation(int64_t);
extern int32_t xa_config_set_orientation(int64_t, int32_t);
extern int32_t xa_config_get_density(int64_t);
extern int32_t xa_config_set_density(int64_t, int32_t);
extern int32_t xa_config_get_screen_size(int64_t);
extern int32_t xa_config_set_screen_size(int64_t, int32_t);
extern int32_t xa_config_get_sdk_version(int64_t);
extern int32_t xa_config_set_sdk_version(int64_t, int32_t);
extern void xa_unload(void);

/* ---- callback observation ---------------------------------------------- */

static int g_cb_calls = 0;
static int g_cb_fd = -1;
static int g_cb_events = 0;
static intptr_t g_cb_data = 0;

static int on_looper_input(int fd, int events, void* data) {
    g_cb_calls++;
    g_cb_fd = fd;
    g_cb_events = events;
    g_cb_data = (intptr_t)data;
    return 1;
}

int main(void) {
    int fails = 0;
    printf("INFO build-time constant gate: PASS (static asserts vs NDK r27b headers)\n");

    int rc = xa_load();
    printf("INFO load rc=%d error=%s\n", rc, xa_error());
    if (rc == 1) {
        printf("RESULT: SKIP (runtime absent)\n");
        return 2;
    }
    if (rc != 0) {
        printf("FAIL load rc=%d (%s)\n", rc, xa_error());
        return 10;
    }
    printf("OK load (declared exports=%d, missing=%d)\n",
           xa_export_count(), xa_abi_missing_count());
    if (xa_export_count() != 117) {
        printf("FAIL export count != 117\n");
        fails++;
    }
    if (xa_abi_missing_count() != 0) {
        printf("FAIL missing exports: %s\n", xa_abi_missing());
        fails++;
    }

    /* ---- A1: AHardwareBuffer roundtrip ---------------------------------- */
    int64_t usage = 3 + 0x30;
    int sup = (int)xa_hwb_is_supported(64, 64, 1, usage);
    printf("INFO hwb is_supported=%d\n", sup);
    if (sup != 1) { printf("FAIL isSupported != 1\n"); fails++; }
    int64_t h = xa_hwb_alloc(64, 64, 1, usage);
    if (!h) { printf("FAIL hwb alloc: %s\n", xa_error()); return 11; }
    printf("INFO hwb w=%d h=%d fmt=%d stride=%d layers=%d\n",
           xa_hwb_width(h), xa_hwb_height(h), xa_hwb_format(h),
           xa_hwb_stride(h), xa_hwb_layers(h));
    if (xa_hwb_width(h) != 64 || xa_hwb_height(h) != 64 ||
        xa_hwb_format(h) != 1 || xa_hwb_layers(h) != 1 ||
        xa_hwb_stride(h) < 64) { printf("FAIL hwb describe\n"); fails++; }
    if (xa_hwb_write_pixel(h, 7, 5, 0x11223344) != 0) {
        printf("FAIL hwb write: %s\n", xa_error()); fails++;
    }
    int64_t got = xa_hwb_read_pixel(h, 7, 5);
    printf("INFO hwb read=%lld\n", (long long)got);
    if (got != 0x11223344) { printf("FAIL hwb pixel roundtrip\n"); fails++; }
    xa_hwb_release(h);

    /* ---- A5: ASharedMemory roundtrip ------------------------------------ */
    int64_t fd = xa_shm_create("xiom-core-probe", 4096);
    printf("INFO shm fd=%lld\n", (long long)fd);
    if (fd < 0) {
        printf("FAIL shm create: %s\n", xa_error()); fails++;
    } else {
        int64_t sz = xa_shm_get_size(fd);
        printf("INFO shm size=%lld\n", (long long)sz);
        if (sz != 4096) { printf("FAIL shm size\n"); fails++; }
        if (xa_shm_set_prot(fd, 3) != 0) { printf("FAIL shm setProt: %s\n", xa_error()); fails++; }
        if (xa_shm_write_probe(fd, 0x11223344) != 0) {
            printf("FAIL shm write: %s\n", xa_error()); fails++;
        }
        int64_t got2 = xa_shm_read_probe(fd);
        printf("INFO shm read=%lld\n", (long long)got2);
        if (got2 != 0x11223344) { printf("FAIL shm roundtrip\n"); fails++; }
        xa_fd_close(fd);
    }

    /* ---- A2: ALooper functional head ------------------------------------ */
    int64_t lp = xa_looper_prepare(1 /* ALOOPER_PREPARE_ALLOW_NON_CALLBACKS */);
    printf("INFO looper prepare=%lld (err=%s)\n", (long long)lp, xa_error());
    if (!lp) { printf("FAIL looper prepare\n"); fails++; }
    int64_t self = xa_looper_for_thread();
    printf("INFO looper forThread=%lld\n", (long long)self);
    if (self != lp) { printf("FAIL forThread != prepared looper\n"); fails++; }

    int64_t rfd = xa_pipe_open();
    printf("INFO pipe read fd=%lld\n", (long long)rfd);
    if (rfd < 0) { printf("FAIL pipe open: %s\n", xa_error()); fails++; }

    if (lp && rfd >= 0) {
        /* ident variant: NULL callback, ALLOW_NON_CALLBACKS. */
        int add = xa_looper_add_fd_ident(lp, (int32_t)rfd, 42, ALOOPER_EVENT_INPUT);
        printf("INFO addFd(ident=42, NULL cb)=%d\n", add);
        if (add != 1) { printf("FAIL addFd ident\n"); fails++; }
        if (xa_pipe_write_byte(0x5a) != 0) { printf("FAIL pipe write: %s\n", xa_error()); fails++; }
        int ident = xa_looper_poll_once(lp, 1000);
        printf("INFO pollOnce(ident path)=%d last_fd=%d last_events=%d\n",
               ident, xa_looper_last_fd(), xa_looper_last_events());
        if (ident != 42) { printf("FAIL pollOnce ident\n"); fails++; }
        if (xa_looper_last_fd() != (int32_t)rfd) { printf("FAIL last_fd\n"); fails++; }
        if (xa_looper_last_events() != ALOOPER_EVENT_INPUT) { printf("FAIL last_events\n"); fails++; }
        int b = xa_pipe_read_byte((int32_t)rfd);
        printf("INFO pipe drained=%d\n", b);
        if (b != 0x5a) { printf("FAIL pipe drain\n"); fails++; }
        int rem = xa_looper_remove_fd(lp, (int32_t)rfd);
        printf("INFO removeFd=%d\n", rem);
        if (rem != 1) { printf("FAIL removeFd\n"); fails++; }

        /* callback variant: C callback through the bridge (same shape the
         * X->XIOM direct handoff passes). */
        g_cb_calls = 0;
        int datatoken = 0x77;
        int add2 = xa_looper_add_fd(lp, (int32_t)rfd, ALOOPER_POLL_CALLBACK,
                                    ALOOPER_EVENT_INPUT, on_looper_input, (int64_t)datatoken);
        printf("INFO addFd(callback)=%d\n", add2);
        if (add2 != 1) { printf("FAIL addFd callback\n"); fails++; }
        if (xa_pipe_write_byte(0x33) != 0) { printf("FAIL pipe write 2: %s\n", xa_error()); fails++; }
        int cb_rc = xa_looper_poll_once(lp, 1000);
        printf("INFO pollOnce(cb)=%d calls=%d cb_fd=%d cb_events=%d data=0x%llx\n",
               cb_rc, g_cb_calls, g_cb_fd, g_cb_events, (unsigned long long)g_cb_data);
        if (cb_rc != ALOOPER_POLL_CALLBACK) { printf("FAIL pollOnce callback rc\n"); fails++; }
        if (g_cb_calls != 1 || g_cb_fd != (int)rfd ||
            g_cb_events != ALOOPER_EVENT_INPUT || g_cb_data != (intptr_t)datatoken) {
            printf("FAIL callback observation\n"); fails++;
        }
        int b2 = xa_pipe_read_byte((int32_t)rfd);
        printf("INFO pipe drained2=%d\n", b2);
        if (b2 != 0x33) { printf("FAIL pipe drain 2\n"); fails++; }
        if (xa_looper_remove_fd(lp, (int32_t)rfd) != 1) { printf("FAIL removeFd 2\n"); fails++; }

        /* timeout + wake + pollAll + acquire/release */
        int to = xa_looper_poll_once(lp, 20);
        printf("INFO pollOnce(empty timeout)=%d\n", to);
        if (to != ALOOPER_POLL_TIMEOUT) { printf("FAIL timeout\n"); fails++; }
        if (xa_looper_wake(lp) != 1) { printf("FAIL wake rc\n"); fails++; }
        int woken = xa_looper_poll_once(lp, 0);
        printf("INFO pollOnce(after wake)=%d\n", woken);
        if (woken != ALOOPER_POLL_WAKE) { printf("FAIL wake observation\n"); fails++; }
        int pa = xa_looper_poll_all(lp, 0);
        printf("INFO pollAll(0)=%d\n", pa);
        if (pa != ALOOPER_POLL_TIMEOUT) { printf("FAIL pollAll smoke\n"); fails++; }
        xa_looper_acquire(lp);
        xa_looper_release(lp);
        printf("OK looper acquire/release\n");
    }

    /* ---- A2: AConfiguration functional head ----------------------------- */
    int64_t cfg = xa_config_new();
    printf("INFO config new=%lld (err=%s)\n", (long long)cfg, xa_error());
    if (!cfg) {
        printf("FAIL config new\n"); fails++;
    } else {
        int sr = xa_config_get_screen_round(cfg);
        printf("INFO screenRound=%d\n", sr);
        if (sr < 0) { printf("FAIL screenRound getter\n"); fails++; }
        printf("INFO setLang=%d setCountry=%d\n",
               xa_config_set_language(cfg, "de"), xa_config_set_country(cfg, "DE"));
        /* Both getters return one shared static buffer; copy before printing. */
        char langbuf[4];
        char countrybuf[4];
        snprintf(langbuf, sizeof(langbuf), "%s", xa_config_get_language(cfg));
        snprintf(countrybuf, sizeof(countrybuf), "%s", xa_config_get_country(cfg));
        printf("INFO lang=%s country=%s\n", langbuf, countrybuf);
        if (strcmp(langbuf, "de") != 0 || strcmp(countrybuf, "DE") != 0) {
            printf("FAIL locale roundtrip\n"); fails++;
        }
        xa_config_set_orientation(cfg, ACONFIGURATION_ORIENTATION_LAND);
        xa_config_set_density(cfg, ACONFIGURATION_DENSITY_HIGH);
        xa_config_set_screen_size(cfg, ACONFIGURATION_SCREENSIZE_NORMAL);
        xa_config_set_sdk_version(cfg, 36);
        printf("INFO orientation=%d density=%d screenSize=%d sdk=%d\n",
               xa_config_get_orientation(cfg), xa_config_get_density(cfg),
               xa_config_get_screen_size(cfg), xa_config_get_sdk_version(cfg));
        if (xa_config_get_orientation(cfg) != ACONFIGURATION_ORIENTATION_LAND ||
            xa_config_get_density(cfg) != ACONFIGURATION_DENSITY_HIGH ||
            xa_config_get_screen_size(cfg) != ACONFIGURATION_SCREENSIZE_NORMAL ||
            xa_config_get_sdk_version(cfg) != 36) {
            printf("FAIL config scalar roundtrips\n"); fails++;
        }

        int64_t fresh = xa_config_new();
        if (!fresh) {
            printf("FAIL config new (fresh)\n"); fails++;
        } else {
            int mask = xa_config_diff(cfg, fresh);
            /* API-36 maps AConfiguration_setScreenSize into the
             * SCREENLAYOUT_SIZE bits (the legacy screenSize member stays
             * derived); observed mask = LOCALE|ORIENTATION|DENSITY|
             * SCREEN_LAYOUT|VERSION = 0xd84. */
            int expected = ACONFIGURATION_LOCALE | ACONFIGURATION_ORIENTATION |
                           ACONFIGURATION_DENSITY | ACONFIGURATION_SCREEN_LAYOUT |
                           ACONFIGURATION_VERSION;
            printf("INFO diff mask=0x%x expected=0x%x\n", mask, expected);
            if (mask != expected) { printf("FAIL diff mask\n"); fails++; }

            int64_t copy = xa_config_new();
            if (!copy) {
                printf("FAIL config new (copy)\n"); fails++;
            } else {
                if (xa_config_copy(copy, cfg) != 0) { printf("FAIL config copy\n"); fails++; }
                int d2 = xa_config_diff(copy, cfg);
                printf("INFO clone diff=%d\n", d2);
                if (d2 != 0) { printf("FAIL clone diff != 0\n"); fails++; }
                /* match(base, requested): 0 when a value in `base`
                 * conflicts with `requested` (NDK doc); a populated base
                 * vs an all-unset requested reports 0 on API-36. */
                int m_cc = xa_config_match(copy, copy);
                int m_cf = xa_config_match(copy, fresh);
                int m_fc = xa_config_match(fresh, copy);
                int m_ff = xa_config_match(fresh, fresh);
                printf("INFO match matrix: (copy,copy)=%d (copy,fresh)=%d (fresh,copy)=%d (fresh,fresh)=%d\n",
                       m_cc, m_cf, m_fc, m_ff);
                if (m_cc != 1 || m_ff != 1) { printf("FAIL match self\n"); fails++; }
                if (m_fc != 1) { printf("FAIL match (fresh base, populated requested)\n"); fails++; }
                if (m_cf != 0) { printf("FAIL match (populated base, unset requested)\n"); fails++; }
                int bt = xa_config_is_better_than(fresh, copy, fresh);
                printf("INFO isBetterThan(fresh, clone, fresh)=%d\n", bt);
                if (bt == 0) { printf("FAIL isBetterThan (clone should be better than fresh)\n"); fails++; }
                if (xa_config_delete(copy) != 0) { printf("FAIL delete copy\n"); fails++; }
            }
            if (xa_config_delete(fresh) != 0) { printf("FAIL delete fresh\n"); fails++; }
        }
        if (xa_config_delete(cfg) != 0) { printf("FAIL delete cfg\n"); fails++; }
    }

    if (lp && rfd >= 0) {
        if (xa_pipe_close(rfd) != 0) { printf("FAIL pipe close\n"); fails++; }
    }

    xa_unload();

    if (fails) {
        printf("RESULT: FAIL (%d)\n", fails);
    } else {
        printf("RESULT: PASS\n");
    }
    return fails ? 10 : 0;
}
