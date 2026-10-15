/* xiom.android-sys -- A12 log+sync bridge, on-device driver (evidence).
 * Links the package bridge (packages/xiom-android-sys/src/android_sys_bridge.c)
 * and runs the same path the conformance suite takes on Android:
 * load -> core export-set check -> functional liblog head (write/print/
 * is_loggable verdicts) -> functional libsync typed error path (errno
 * capture on fd -1).
 *
 * Also cross-checks the transcription against the real NDK r27b headers
 * at BUILD time: _Static_assert on the log priorities/ids, the derived
 * SYNC_IOC_* values and the pinned struct offsets/sizes (this is the
 * oracle==bound proof for the constants in android_sys.xi).
 *
 * Built with the NDK clang for x86_64-linux-android26; run via adb on
 * the API-36 emulator (see run-probe.ps1).
 */
#include <android/log.h>
#include <android/sync.h>
#include <dlfcn.h>
#include <errno.h>
#include <linux/sync_file.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

/* ---- build-time oracle cross-check (compile fails on any drift) -------- */

/* android_LogPriority (android/log.h) */
_Static_assert(ANDROID_LOG_UNKNOWN == 0, "priority UNKNOWN");
_Static_assert(ANDROID_LOG_DEFAULT == 1, "priority DEFAULT");
_Static_assert(ANDROID_LOG_VERBOSE == 2, "priority VERBOSE");
_Static_assert(ANDROID_LOG_DEBUG == 3, "priority DEBUG");
_Static_assert(ANDROID_LOG_INFO == 4, "priority INFO");
_Static_assert(ANDROID_LOG_WARN == 5, "priority WARN");
_Static_assert(ANDROID_LOG_ERROR == 6, "priority ERROR");
_Static_assert(ANDROID_LOG_FATAL == 7, "priority FATAL");
_Static_assert(ANDROID_LOG_SILENT == 8, "priority SILENT");

/* log_id (android/log.h) */
_Static_assert(LOG_ID_MIN == 0, "log id MIN");
_Static_assert(LOG_ID_MAIN == 0, "log id MAIN");
_Static_assert(LOG_ID_RADIO == 1, "log id RADIO");
_Static_assert(LOG_ID_EVENTS == 2, "log id EVENTS");
_Static_assert(LOG_ID_SYSTEM == 3, "log id SYSTEM");
_Static_assert(LOG_ID_CRASH == 4, "log id CRASH");
_Static_assert(LOG_ID_STATS == 5, "log id STATS");
_Static_assert(LOG_ID_SECURITY == 6, "log id SECURITY");
_Static_assert(LOG_ID_KERNEL == 7, "log id KERNEL");
_Static_assert(LOG_ID_MAX == 8, "log id MAX");
_Static_assert(LOG_ID_DEFAULT == 0x7FFFFFFF, "log id DEFAULT");

/* linux/sync_file.h: struct shapes + the derived ioctl values */
_Static_assert(sizeof(struct sync_merge_data) == 48, "sync_merge_data size");
_Static_assert(sizeof(struct sync_file_info) == 56, "sync_file_info size");
_Static_assert(sizeof(struct sync_fence_info) == 80, "sync_fence_info size");
_Static_assert(sizeof(struct sync_set_deadline) == 16, "sync_set_deadline size");
_Static_assert(offsetof(struct sync_file_info, status) == 32, "sync_file_info.status");
_Static_assert(offsetof(struct sync_file_info, flags) == 36, "sync_file_info.flags");
_Static_assert(offsetof(struct sync_file_info, num_fences) == 40, "sync_file_info.num_fences");
_Static_assert(offsetof(struct sync_fence_info, status) == 64, "sync_fence_info.status");
_Static_assert(SYNC_IOC_MAGIC == '>', "SYNC_IOC_MAGIC");
_Static_assert(SYNC_IOC_MERGE == 0xC0303E03u, "SYNC_IOC_MERGE");
_Static_assert(SYNC_IOC_FILE_INFO == 0xC0383E04u, "SYNC_IOC_FILE_INFO");
_Static_assert(SYNC_IOC_SET_DEADLINE == 0x40103E05u, "SYNC_IOC_SET_DEADLINE");

/* errno family (asm-generic) */
_Static_assert(EBADF == 9, "EBADF");
_Static_assert(EINVAL == 22, "EINVAL");

/* ---- bridge contract (packages/xiom-android-sys/src/android_sys_bridge.c) */

int xs_load(void);
const char* xs_error(void);
int xs_abi_missing_count(void);
const char* xs_abi_missing(void);
int xs_ext_count(void);
int xs_ext_missing_count(void);
const char* xs_ext_missing(void);
int xs_errno(void);
int xs_log_write(int32_t, const char*, const char*);
int xs_log_print(int32_t, const char*, const char*);
int xs_log_is_loggable(int32_t, const char*, int32_t);
int xs_log_is_loggable_len(int32_t, const char*, int64_t, int32_t);
int xs_log_buf_write(int32_t, int32_t, const char*, const char*);
int xs_log_minimum_priority(void);
int64_t xs_sync_file_info(int32_t);
int32_t xs_sync_file_info_status(int64_t);
int32_t xs_sync_file_info_num_fences(int64_t);
const char* xs_sync_file_info_name(int64_t);
void xs_sync_file_info_free(int64_t);
int32_t xs_sync_merge(const char*, int32_t, int32_t);
void xs_unload(void);

/* ---- independent dlsym export scan (not via the bridge) ---------------- */

static const char* k_core[] = {
    "__android_log_write", "__android_log_print", "__android_log_vprint",
    "__android_log_assert", "__android_log_buf_write", "__android_log_buf_print",
    "__android_log_is_loggable", "__android_log_is_loggable_len",
    "sync_merge", "sync_file_info", "sync_file_info_free",
};
static const char* k_ext[] = {
    "__android_log_write_log_message", "__android_log_set_logger",
    "__android_log_logd_logger", "__android_log_stderr_logger",
    "__android_log_set_aborter", "__android_log_call_aborter",
    "__android_log_default_aborter", "__android_log_set_minimum_priority",
    "__android_log_get_minimum_priority", "__android_log_set_default_tag",
};
static const char* k_private[] = {
    "sync_wait", "sync_file_info_is_signaled", "sync_get_fence_info",
    "sync_set_deadline",
};

static void scan_exports(void* log_lib, void* sync_lib, const char* const* names,
                         int count, const char* label, int* fails) {
    int missing = 0;
    for (int i = 0; i < count; i++) {
        void* p = dlsym(log_lib, names[i]);
        if (!p) p = dlsym(sync_lib, names[i]);
        if (!p) {
            missing++;
            printf("INFO %s missing: %s\n", label, names[i]);
        }
    }
    printf("INFO %s exports resolved: %d/%d\n", label, count - missing, count);
    if (missing != 0) (*fails)++;
}

int main(void) {
    int fails = 0;

    printf("=== xiom.android-sys on-device driver (A12 log+sync head, NDK r27b oracle) ===\n");
    printf("INFO header cross-check: priorities/ids + SYNC_IOC_* + struct sizes _Static_assert PASS\n");
    printf("INFO ioctl: merge=0x%08X file_info=0x%08X set_deadline=0x%08X magic=0x%02X\n",
           (unsigned)SYNC_IOC_MERGE, (unsigned)SYNC_IOC_FILE_INFO,
           (unsigned)SYNC_IOC_SET_DEADLINE, (unsigned)SYNC_IOC_MAGIC);

    /* Independent export scan on the device libraries. */
    void* log_lib = dlopen("liblog.so", RTLD_NOW | RTLD_LOCAL);
    void* sync_lib = dlopen("libsync.so", RTLD_NOW | RTLD_LOCAL);
    printf("INFO dlopen: liblog.so=%s libsync.so=%s\n",
           log_lib ? "ok" : dlerror(), sync_lib ? "ok" : dlerror());
    if (!log_lib || !sync_lib) {
        printf("RESULT: SKIP (runtime absent)\n");
        return 2;
    }
    scan_exports(log_lib, sync_lib, k_core, (int)(sizeof(k_core) / sizeof(k_core[0])), "core (API 26)", &fails);
    scan_exports(log_lib, sync_lib, k_ext, (int)(sizeof(k_ext) / sizeof(k_ext[0])), "ext (API 30)", &fails);
    for (size_t i = 0; i < sizeof(k_private) / sizeof(k_private[0]); i++) {
        void* p = dlsym(log_lib, k_private[i]);
        if (!p) p = dlsym(sync_lib, k_private[i]);
        printf("INFO private (NDK-undeclared) %s: %s\n", k_private[i], p ? "present" : "absent");
    }

    /* Bridge path (the shipped code under test). */
    int rc = xs_load();
    printf("INFO bridge load rc=%d error=%s\n", rc, xs_error());
    if (rc == 1) {
        printf("RESULT: SKIP (runtime absent)\n");
        return 2;
    }
    if (rc != 0) {
        printf("FAIL bridge load rc=%d (%s)\n", rc, xs_error());
        return 10;
    }
    int missing = xs_abi_missing_count();
    printf("OK bridge core export set resolved (missing=%d%s%s)\n",
           missing, missing ? ": " : "", xs_abi_missing());
    if (missing != 0) fails++;
    int ext_total = xs_ext_count();
    int ext_missing = xs_ext_missing_count();
    printf("INFO bridge ext (API 30+): %d/%d present%s%s\n",
           ext_total - ext_missing, ext_total,
           ext_missing ? " missing: " : "", xs_ext_missing());

    /* Functional liblog head. */
    int w = xs_log_write(ANDROID_LOG_INFO, "xiom-android-sys",
                         "xiom.android-sys probe: __android_log_write ok");
    printf("INFO log: __android_log_write rc=%d (1=written)\n", w);
    if (w != 1) fails++;
    int lpr = xs_log_print(ANDROID_LOG_INFO, "xiom-android-sys",
                           "xiom.android-sys probe: __android_log_print ok");
    printf("INFO log: __android_log_print rc=%d\n", lpr);
    if (lpr != 1) fails++;
    int lg_info = xs_log_is_loggable(ANDROID_LOG_INFO, "xiom-android-sys", ANDROID_LOG_INFO);
    printf("INFO log: is_loggable(INFO, default INFO)=%d (expect 1)\n", lg_info);
    if (lg_info != 1) fails++;
    int lg_verbose = xs_log_is_loggable(ANDROID_LOG_VERBOSE, "xiom-android-sys", ANDROID_LOG_INFO);
    printf("INFO log: is_loggable(VERBOSE, default INFO)=%d (expect 0 off-list; informational)\n", lg_verbose);
    int lg_len = xs_log_is_loggable_len(ANDROID_LOG_INFO, "xiom-android-sys", 16, ANDROID_LOG_INFO);
    printf("INFO log: is_loggable_len(INFO, len=16, default INFO)=%d (expect 1)\n", lg_len);
    if (lg_len != 1) fails++;
    int bw = xs_log_buf_write(LOG_ID_MAIN, ANDROID_LOG_INFO, "xiom-android-sys",
                              "xiom.android-sys probe: __android_log_buf_write ok");
    printf("INFO log: __android_log_buf_write rc=%d\n", bw);
    if (bw != 1) fails++;
    int mp = xs_log_minimum_priority();
    printf("INFO log: minimum_priority=%d (-1 = API-30 ext absent)\n", mp);

    /* Functional libsync typed error path (no fence synthesis this wave). */
    int64_t h = xs_sync_file_info(-1);
    int e1 = xs_errno();
    printf("INFO sync: sync_file_info(-1) handle=%lld errno=%d (%s)\n",
           (long long)h, e1, e1 == EBADF ? "EBADF" : (e1 == EINVAL ? "EINVAL" : "?"));
    if (h != 0 || !(e1 == EBADF || e1 == EINVAL)) fails++;
    int32_t m = xs_sync_merge("xiom-sys-probe", -1, -1);
    int e2 = xs_errno();
    printf("INFO sync: sync_merge(name,-1,-1) rc=%d errno=%d (%s)\n",
           (int)m, e2, e2 == EBADF ? "EBADF" : (e2 == EINVAL ? "EINVAL" : "?"));
    if (m != -1 || !(e2 == EBADF || e2 == EINVAL)) fails++;
    xs_sync_file_info_free(0); /* null-safe free path */

    xs_unload();
    printf("INFO bridge unloaded\n");

    if (fails) {
        printf("RESULT: FAIL (%d)\n", fails);
        return 11;
    }
    printf("RESULT: PASS\n");
    return 0;
}
