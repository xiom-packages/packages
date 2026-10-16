/* XIOM -- xiom.android-sys: liblog + libsync runtime bridge.
 * Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
 * Licensed under the MIT or Apache-2.0 license, at your option.
 *
 * DESIGN: runtime loader/probe for the Android system head (A12 slice:
 * android/log.h + android/sync.h of NDK r27b).  No link-time dependency.
 * On Windows everything classifies as ABSENT (SKIP) via LoadLibraryA; on
 * Android/Linux the libraries load via dlopen, the declared core export
 * set (11 symbols) is verified (ABI stage), the API-30 liblog extension
 * set (10 symbols) is resolved and reported (informational), and the
 * functional heads run (log write/is_loggable; sync error path with
 * errno capture).
 *
 * Contract (flat extern "C", called from module xiom.android_sys):
 *   int         xs_load_named(const char* log_soname,
 *                             const char* sync_soname) 0=ok 1=absent 2=abi
 *   int         xs_load(void)      "liblog.so" + "libsync.so"
 *   const char* xs_error(void)     last error / missing summary
 *   int         xs_abi_missing_count(void)  unresolved core export count
 *   const char* xs_abi_missing(void)        comma-joined missing names
 *   int         xs_ext_count(void)          API-30 extension set size
 *   int         xs_ext_missing_count(void)  unresolved extension count
 *   const char* xs_ext_missing(void)        comma-joined missing ext names
 *   int         xs_errno(void)     errno captured by the last sync call
 *   int         xs_log_write(int32 prio, const char* tag, const char* text)
 *                                                       1=written -1=-EPERM
 *   int         xs_log_print(int32 prio, const char* tag, const char* text)
 *                                                  ("%s" formatting; same rc)
 *   int         xs_log_is_loggable(int32 prio, const char* tag,
 *                                  int32 default_prio)   1/0 (0/1/-1 unset)
 *   int         xs_log_is_loggable_len(int32 prio, const char* tag,
 *                                      int64 len, int32 default_prio)  1/0
 *   int         xs_log_buf_write(int32 buf_id, int32 prio, const char* tag,
 *                                const char* text)       same rc as write
 *   int         xs_log_minimum_priority(void)   int32; -1 when symbol absent
 *   int64       xs_sync_file_info(int32 fd)     handle; 0 = failed (errno)
 *   int32       xs_sync_file_info_status(int64 handle)
 *   int32       xs_sync_file_info_num_fences(int64 handle)
 *   const char* xs_sync_file_info_name(int64 handle)
 *   void        xs_sync_file_info_free(int64 handle)
 *   int32       xs_sync_merge(const char* name, int32 fd1, int32 fd2)
 *                                               new fd; -1 = failed (errno)
 *   void        xs_unload(void)
 *
 * Sentinel convention: -2 from a functional call = "symbol unresolved"
 * (mapped to LOAD_ABI by the module; distinct from -EPERM(-1) / errno -1).
 */

#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#if defined(_WIN32)
#include <windows.h>
typedef HMODULE xs_lib_t;
static xs_lib_t xs_dlopen(const char* name) { return LoadLibraryA(name); }
static void* xs_dlsym(xs_lib_t h, const char* name) {
    return h ? (void*)GetProcAddress(h, name) : 0;
}
static void xs_dlclose(xs_lib_t h) { if (h) FreeLibrary(h); }
#else
#include <dlfcn.h>
typedef void* xs_lib_t;
static xs_lib_t xs_dlopen(const char* name) { return dlopen(name, RTLD_NOW | RTLD_LOCAL); }
static void* xs_dlsym(xs_lib_t h, const char* name) { return h ? dlsym(h, name) : 0; }
static void xs_dlclose(xs_lib_t h) { if (h) dlclose(h); }
#endif

/* -- pinned ABI facts (NDK r27b android/log.h + linux/sync_file.h) ------- */

typedef struct XS_SyncFileInfo {
    char name[32];      /* sync_file_info.name */
    int32_t status;     /* 0 unsignaled / 1 signaled / < 0 error */
    uint32_t flags;
    uint32_t num_fences;
    uint32_t pad;
    uint64_t sync_fence_info; /* kernel pointer to fence infos (opaque) */
} XS_SyncFileInfo;

/* -- bridge state -------------------------------------------------------- */

static xs_lib_t g_log = 0;
static xs_lib_t g_sync = 0;
static char g_error[512] = {0};
static char g_missing[512] = {0};
static char g_ext_missing[512] = {0};
static char g_name_buf[33] = {0};
static int g_missing_count = 0;
static int g_ext_missing_count = 0;
static int g_errno = 0;

void xs_unload(void); /* defined at the bottom; used by xs_load_pair */

static void xs_set_error(const char* msg) {
    snprintf(g_error, sizeof(g_error), "%s", msg);
}

/* Every symbol is tried against both libraries (re-export layouts differ
 * across API levels).
 */
static void* xs_resolve(const char* name) {
    void* p = xs_dlsym(g_log, name);
    if (!p) p = xs_dlsym(g_sync, name);
    return p;
}

/* Core export set -- the r27b header-declared non-macro functions that
 * the API-26 link stubs also export (verified via llvm-readelf dynsym:
 * liblog 8 + libsync 3).  This set is ABI-gated. */
static const char* k_core_export_set[] = {
    /* android/log.h (8) */
    "__android_log_write",
    "__android_log_print",
    "__android_log_vprint",
    "__android_log_assert",
    "__android_log_buf_write",
    "__android_log_buf_print",
    "__android_log_is_loggable",
    "__android_log_is_loggable_len",
    /* android/sync.h (3; sync_get_fence_info is a header inline) */
    "sync_merge",
    "sync_file_info",
    "sync_file_info_free",
};
#define XS_CORE_EXPORT_COUNT (sizeof(k_core_export_set) / sizeof(k_core_export_set[0]))

/* API-30 liblog extension set (header __INTRODUCED_IN(30); present in the
 * API-35 stub, absent from the API-26 stub).  Resolved and reported; NOT
 * ABI-gated so android26 devices are not misclassified. */
static const char* k_ext_export_set[] = {
    "__android_log_write_log_message",
    "__android_log_set_logger",
    "__android_log_logd_logger",
    "__android_log_stderr_logger",
    "__android_log_set_aborter",
    "__android_log_call_aborter",
    "__android_log_default_aborter",
    "__android_log_set_minimum_priority",
    "__android_log_get_minimum_priority",
    "__android_log_set_default_tag",
};
#define XS_EXT_EXPORT_COUNT (sizeof(k_ext_export_set) / sizeof(k_ext_export_set[0]))

/* -- functional function pointers (resolved during load) ----------------- */

typedef int (*PFN_log_write)(int, const char*, const char*);
typedef int (*PFN_log_print)(int, const char*, const char*, ...);
typedef int (*PFN_log_buf_write)(int, int, const char*, const char*);
typedef int (*PFN_log_is_loggable)(int, const char*, int);
typedef int (*PFN_log_is_loggable_len)(int, const char*, size_t, int);
typedef int32_t (*PFN_log_get_minimum_priority)(void);

static PFN_log_write p_log_write = 0;
static PFN_log_print p_log_print = 0;
static PFN_log_buf_write p_log_buf_write = 0;
static PFN_log_is_loggable p_is_loggable = 0;
static PFN_log_is_loggable_len p_is_loggable_len = 0;
static PFN_log_get_minimum_priority p_min_priority = 0;

typedef int32_t (*PFN_sync_merge)(const char*, int32_t, int32_t);
typedef struct XS_SyncFileInfo* (*PFN_sync_file_info)(int32_t);
typedef void (*PFN_sync_file_info_free)(struct XS_SyncFileInfo*);

static PFN_sync_merge p_sync_merge = 0;
static PFN_sync_file_info p_sync_file_info = 0;
static PFN_sync_file_info_free p_sync_file_info_free = 0;

/* -- load / classify ------------------------------------------------------ */

static void xs_join_missing(char* buf, size_t cap, const char* name, int* count) {
    size_t used = strlen(buf);
    snprintf(buf + used, cap - used, "%s%s", used ? "," : "", name);
    *count += 1;
}

static int xs_finish_load(void) {
    g_missing_count = 0;
    g_missing[0] = 0;
    g_ext_missing_count = 0;
    g_ext_missing[0] = 0;
    g_errno = 0;
    for (size_t i = 0; i < XS_CORE_EXPORT_COUNT; i++) {
        if (!xs_resolve(k_core_export_set[i])) {
            xs_join_missing(g_missing, sizeof(g_missing), k_core_export_set[i], &g_missing_count);
        }
    }
    for (size_t i = 0; i < XS_EXT_EXPORT_COUNT; i++) {
        if (!xs_resolve(k_ext_export_set[i])) {
            xs_join_missing(g_ext_missing, sizeof(g_ext_missing), k_ext_export_set[i],
                            &g_ext_missing_count);
        }
    }
    p_log_write = (PFN_log_write)xs_resolve("__android_log_write");
    p_log_print = (PFN_log_print)xs_resolve("__android_log_print");
    p_log_buf_write = (PFN_log_buf_write)xs_resolve("__android_log_buf_write");
    p_is_loggable = (PFN_log_is_loggable)xs_resolve("__android_log_is_loggable");
    p_is_loggable_len = (PFN_log_is_loggable_len)xs_resolve("__android_log_is_loggable_len");
    p_min_priority =
        (PFN_log_get_minimum_priority)xs_resolve("__android_log_get_minimum_priority");
    p_sync_merge = (PFN_sync_merge)xs_resolve("sync_merge");
    p_sync_file_info = (PFN_sync_file_info)xs_resolve("sync_file_info");
    p_sync_file_info_free = (PFN_sync_file_info_free)xs_resolve("sync_file_info_free");
    if (g_missing_count != 0) {
        xs_set_error(g_missing);
        return 2;
    }
    xs_set_error("");
    return 0;
}

static int xs_load_pair(const char* log_soname, const char* sync_soname) {
    xs_unload();
    g_log = xs_dlopen(log_soname);
    g_sync = xs_dlopen(sync_soname);
    if (!g_log && !g_sync) {
        snprintf(g_error, sizeof(g_error), "absent: %s / %s", log_soname, sync_soname);
        return 1;
    }
    return xs_finish_load();
}

int xs_load_named(const char* log_soname, const char* sync_soname) {
    if (!log_soname || !sync_soname) {
        xs_set_error("null soname");
        return 2;
    }
    return xs_load_pair(log_soname, sync_soname);
}

int xs_load(void) {
    return xs_load_pair("liblog.so", "libsync.so");
}

const char* xs_error(void) { return g_error; }

int xs_abi_missing_count(void) { return g_missing_count; }

const char* xs_abi_missing(void) { return g_missing; }

int xs_ext_count(void) { return (int)XS_EXT_EXPORT_COUNT; }

int xs_ext_missing_count(void) { return g_ext_missing_count; }

const char* xs_ext_missing(void) { return g_ext_missing; }

int xs_errno(void) { return g_errno; }

/* -- functional liblog surface -------------------------------------------- */

int xs_log_write(int32_t prio, const char* tag, const char* text) {
    g_errno = 0;
    if (!p_log_write) { xs_set_error("__android_log_write unresolved"); return -2; }
    if (!tag || !text) { xs_set_error("null tag/text"); return -2; }
    int rc = p_log_write((int)prio, tag, text);
    if (rc != 1) {
        snprintf(g_error, sizeof(g_error), "__android_log_write rc=%d", rc);
    }
    return rc;
}

int xs_log_print(int32_t prio, const char* tag, const char* text) {
    g_errno = 0;
    if (!p_log_print) { xs_set_error("__android_log_print unresolved"); return -2; }
    if (!tag || !text) { xs_set_error("null tag/text"); return -2; }
    /* Fixed "%s" format: the message is data, never a format string. */
    int rc = p_log_print((int)prio, tag, "%s", text);
    if (rc != 1) {
        snprintf(g_error, sizeof(g_error), "__android_log_print rc=%d", rc);
    }
    return rc;
}

int xs_log_is_loggable(int32_t prio, const char* tag, int32_t default_prio) {
    g_errno = 0;
    if (!p_is_loggable) { xs_set_error("__android_log_is_loggable unresolved"); return -1; }
    if (!tag) { xs_set_error("null tag"); return -1; }
    return p_is_loggable((int)prio, tag, (int)default_prio);
}

int xs_log_is_loggable_len(int32_t prio, const char* tag, int64_t len, int32_t default_prio) {
    g_errno = 0;
    if (!p_is_loggable_len) { xs_set_error("__android_log_is_loggable_len unresolved"); return -1; }
    if (!tag) { xs_set_error("null tag"); return -1; }
    if (len <= 0) { xs_set_error("tag len must be > 0"); return -1; }
    return p_is_loggable_len((int)prio, tag, (size_t)len, (int)default_prio);
}

int xs_log_buf_write(int32_t buf_id, int32_t prio, const char* tag, const char* text) {
    g_errno = 0;
    if (!p_log_buf_write) { xs_set_error("__android_log_buf_write unresolved"); return -2; }
    if (!tag || !text) { xs_set_error("null tag/text"); return -2; }
    int rc = p_log_buf_write((int)buf_id, (int)prio, tag, text);
    if (rc != 1) {
        snprintf(g_error, sizeof(g_error), "__android_log_buf_write rc=%d", rc);
    }
    return rc;
}

int xs_log_minimum_priority(void) {
    g_errno = 0;
    if (!p_min_priority) {
        xs_set_error("__android_log_get_minimum_priority unresolved (API 30+)");
        return -1;
    }
    return (int)p_min_priority();
}

/* -- functional libsync surface ------------------------------------------- */

int64_t xs_sync_file_info(int32_t fd) {
    g_errno = 0;
    if (!p_sync_file_info) { xs_set_error("sync_file_info unresolved"); return 0; }
    errno = 0;
    XS_SyncFileInfo* info = p_sync_file_info(fd);
    if (!info) {
        g_errno = errno ? errno : 0;
        snprintf(g_error, sizeof(g_error), "sync_file_info(fd=%d) failed, errno=%d",
                 (int)fd, g_errno);
        return 0;
    }
    return (int64_t)(intptr_t)info;
}

int32_t xs_sync_file_info_status(int64_t handle) {
    if (!handle) { xs_set_error("null sync_file_info handle"); return -1; }
    return ((XS_SyncFileInfo*)(intptr_t)handle)->status;
}

int32_t xs_sync_file_info_num_fences(int64_t handle) {
    if (!handle) { xs_set_error("null sync_file_info handle"); return -1; }
    return (int32_t)((XS_SyncFileInfo*)(intptr_t)handle)->num_fences;
}

const char* xs_sync_file_info_name(int64_t handle) {
    if (!handle) { xs_set_error("null sync_file_info handle"); return ""; }
    XS_SyncFileInfo* info = (XS_SyncFileInfo*)(intptr_t)handle;
    memcpy(g_name_buf, info->name, 32);
    g_name_buf[32] = 0;
    return g_name_buf;
}

void xs_sync_file_info_free(int64_t handle) {
    if (p_sync_file_info_free) p_sync_file_info_free((XS_SyncFileInfo*)(intptr_t)handle);
}

int32_t xs_sync_merge(const char* name, int32_t fd1, int32_t fd2) {
    g_errno = 0;
    if (!p_sync_merge) { xs_set_error("sync_merge unresolved"); return -2; }
    if (!name) { xs_set_error("null merge name"); return -2; }
    errno = 0;
    int32_t rc = p_sync_merge(name, fd1, fd2);
    if (rc < 0) {
        g_errno = errno ? errno : 0;
        snprintf(g_error, sizeof(g_error), "sync_merge(fd=%d,fd=%d) failed, errno=%d",
                 (int)fd1, (int)fd2, g_errno);
    }
    return rc;
}

/* -- teardown -------------------------------------------------------------- */

void xs_unload(void) {
    if (g_log) { xs_dlclose(g_log); g_log = 0; }
    if (g_sync) { xs_dlclose(g_sync); g_sync = 0; }
    p_log_write = 0; p_log_print = 0; p_log_buf_write = 0; p_is_loggable = 0;
    p_is_loggable_len = 0; p_min_priority = 0;
    p_sync_merge = 0; p_sync_file_info = 0; p_sync_file_info_free = 0;
    g_missing_count = 0;
    g_missing[0] = 0;
    g_ext_missing_count = 0;
    g_ext_missing[0] = 0;
    g_errno = 0;
}
