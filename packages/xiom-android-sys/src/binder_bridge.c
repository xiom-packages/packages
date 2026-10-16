/* XIOM -- xiom.android-sys: libbinder_ndk runtime bridge (A12 binder head).
 * Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
 * Licensed under the MIT or Apache-2.0 license, at your option.
 *
 * DESIGN: self-contained runtime loader/probe for the NDK binder C API
 * (android/binder_ibinder.h of NDK r27b).  No link-time dependency, no
 * NDK headers needed to compile: the AIBinder surface used here is
 * re-declared by hand (ABI-pinned facts), loaded via dlopen/LoadLibraryA
 * at runtime and export-checked.
 *
 * Declared core set (API 29, ABI-gated, 12 symbols):
 *   AIBinder_Class_define, AIBinder_new, AIBinder_incStrong,
 *   AIBinder_decStrong, AIBinder_associateClass, AIBinder_isAlive,
 *   AIBinder_isRemote, AIBinder_ping, AIBinder_getClass,
 *   AIBinder_debugGetRefCount, AIBinder_getCallingUid,
 *   AIBinder_getCallingPid
 * Declared extension set (API 31/33, resolved + reported, not gated):
 *   AIBinder_Class_getDescriptor, AIBinder_Class_setOnDump,
 *   AIBinder_Class_disableInterfaceTokenHeader
 *
 * Functional head (offline, no remote service needed):
 *   define a class (xbn_class_define, cached per process), create an
 *   instance (AIBinder_new), verify class identity + associateClass +
 *   isAlive/isRemote + ping (binder_status_t) + debug ref-count
 *   transitions (1 -> inc 2 -> dec 1 -> dec 0 triggers onDestroy), then
 *   read the interface descriptor through the class (API 31+).
 *
 * Class lifetime: AIBinder_Class objects have no public delete in the
 * NDK; the defined class is cached for the process lifetime (one per
 * process), which is the documented usage pattern for
 * AIBinder_Class_define.
 *
 * Contract (flat extern "C", called from module xiom.android_sys.binder):
 *   int         xbn_load_named(const char* soname)   0=ok 1=absent 2=abi
 *   int         xbn_load(void)                        "libbinder_ndk.so"
 *   const char* xbn_error(void)
 *   int         xbn_core_missing_count(void)
 *   const char* xbn_core_missing(void)
 *   int         xbn_ext_count(void)
 *   int         xbn_ext_missing_count(void)
 *   const char* xbn_ext_missing(void)
 *   int64       xbn_class_define(const char* descriptor)  class; 0 = fail
 *   const char* xbn_class_descriptor(int64 class)
 *   int64       xbn_create(int64 class, int64 arg)    binder; 0 = fail
 *   void        xbn_inc_strong(int64 binder)
 *   void        xbn_dec_strong(int64 binder)
 *   int         xbn_associate_class(int64 binder, int64 class) 1/0, -2 unresolved
 *   int         xbn_is_alive(int64 binder)           1/0, -2 unresolved
 *   int         xbn_is_remote(int64 binder)          1/0, -2 unresolved
 *   int         xbn_ping(int64 binder)    binder_status_t; -1024 unresolved
 *   int64       xbn_get_class(int64 binder)          class; 0 = none
 *   int         xbn_debug_ref_count(int64 binder)    -2 unresolved
 *   int64       xbn_calling_uid(void)     -1 when unresolved
 *   int64       xbn_calling_pid(void)     -1 when unresolved
 *   int         xbn_destroy_count(void)   onDestroy callbacks observed
 *   int         xbn_transact_count(void)  onTransact callbacks observed
 *   const char* xbn_status_name(int status)
 *   void        xbn_unload(void)
 *
 * Sentinel convention: -2 = "symbol unresolved" (mapped to LOAD_ABI by
 * the module); -1 = call-time failure with the reason in xbn_error().
 */

#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#include <windows.h>
typedef HMODULE xbn_lib_t;
static xbn_lib_t xbn_dlopen(const char* name) { return LoadLibraryA(name); }
static void* xbn_dlsym(xbn_lib_t h, const char* name) {
    return h ? (void*)GetProcAddress(h, name) : 0;
}
static void xbn_dlclose(xbn_lib_t h) { if (h) FreeLibrary(h); }
#else
#include <dlfcn.h>
typedef void* xbn_lib_t;
static xbn_lib_t xbn_dlopen(const char* name) { return dlopen(name, RTLD_NOW | RTLD_LOCAL); }
static void* xbn_dlsym(xbn_lib_t h, const char* name) { return h ? dlsym(h, name) : 0; }
static void xbn_dlclose(xbn_lib_t h) { if (h) dlclose(h); }
#endif

/* -- re-declared NDK ABI facts (android/binder_ibinder.h r27b) ------------- */

typedef int32_t binder_status_t;
typedef uint32_t transaction_code_t;

/* Opaque stand-ins: only pointers to these ever cross the bridge. */
typedef struct XBN_AIBinder AIBinder;
typedef struct XBN_AIBinder_Class AIBinder_Class;
typedef struct XBN_AParcel AParcel;

typedef void* (*AIBinder_Class_onCreate)(void* args);
typedef void (*AIBinder_Class_onDestroy)(void* userData);
typedef binder_status_t (*AIBinder_Class_onTransact)(AIBinder* binder, transaction_code_t code,
                                                     const AParcel* in, AParcel* out);

/* binder_status_t values (android/binder_status.h r27b; enum of
 * asm-generic errno negatives, pinned as constants). */
#define XBN_STATUS_OK 0
#define XBN_STATUS_UNKNOWN_ERROR (-2147483647 - 1)
#define XBN_STATUS_NO_MEMORY (-12)          /* -ENOMEM */
#define XBN_STATUS_INVALID_OPERATION (-38)  /* -ENOSYS */
#define XBN_STATUS_BAD_VALUE (-22)          /* -EINVAL */
#define XBN_STATUS_BAD_TYPE (XBN_STATUS_UNKNOWN_ERROR + 1)
#define XBN_STATUS_NAME_NOT_FOUND (-2)      /* -ENOENT */
#define XBN_STATUS_PERMISSION_DENIED (-1)   /* -EPERM */
#define XBN_STATUS_NO_INIT (-19)            /* -ENODEV */
#define XBN_STATUS_ALREADY_EXISTS (-17)     /* -EEXIST */
#define XBN_STATUS_DEAD_OBJECT (-32)        /* -EPIPE */
#define XBN_STATUS_FAILED_TRANSACTION (XBN_STATUS_UNKNOWN_ERROR + 2)
#define XBN_STATUS_BAD_INDEX (-75)          /* -EOVERFLOW */
#define XBN_STATUS_NOT_ENOUGH_DATA (-61)    /* -ENODATA */
#define XBN_STATUS_WOULD_BLOCK (-11)        /* -EWOULDBLOCK (== EAGAIN) */
#define XBN_STATUS_TIMED_OUT (-110)         /* -ETIMEDOUT */
#define XBN_STATUS_UNKNOWN_TRANSACTION (-74) /* -EBADMSG */
#define XBN_STATUS_FDS_NOT_ALLOWED (XBN_STATUS_UNKNOWN_ERROR + 7)
#define XBN_STATUS_UNEXPECTED_NULL (XBN_STATUS_UNKNOWN_ERROR + 8)

/* -- resolved function pointers -------------------------------------------- */

typedef AIBinder_Class* (*PFN_Class_define)(const char*, AIBinder_Class_onCreate,
                                            AIBinder_Class_onDestroy, AIBinder_Class_onTransact);
typedef const char* (*PFN_Class_getDescriptor)(const AIBinder_Class*);
typedef AIBinder* (*PFN_AIBinder_new)(const AIBinder_Class*, void*);
typedef void (*PFN_incStrong)(AIBinder*);
typedef void (*PFN_decStrong)(AIBinder*);
typedef bool (*PFN_associateClass)(AIBinder*, const AIBinder_Class*);
typedef bool (*PFN_bool_const)(const AIBinder*);
typedef binder_status_t (*PFN_ping)(AIBinder*);
typedef const AIBinder_Class* (*PFN_getClass)(AIBinder*);
typedef int32_t (*PFN_debugGetRefCount)(AIBinder*);
typedef uint32_t (*PFN_getCallingUid)(void);
typedef int32_t (*PFN_getCallingPid)(void);

/* -- bridge state ------------------------------------------------------------ */

static xbn_lib_t g_lib = 0;
static char g_error[512] = {0};
static char g_missing[512] = {0};
static char g_ext_missing[512] = {0};
static int g_missing_count = 0;
static int g_ext_missing_count = 0;
static int g_destroy_count = 0;
static int g_transact_count = 0;

/* process-lifetime class cache (AIBinder_Class has no public delete). */
static int64_t g_class = 0;
static char g_class_descriptor[256] = {0};

static PFN_Class_define p_class_define = 0;
static PFN_Class_getDescriptor p_class_descriptor = 0;
static PFN_AIBinder_new p_new = 0;
static PFN_incStrong p_inc = 0;
static PFN_decStrong p_dec = 0;
static PFN_associateClass p_associate = 0;
static PFN_bool_const p_is_alive = 0;
static PFN_bool_const p_is_remote = 0;
static PFN_ping p_ping = 0;
static PFN_getClass p_get_class = 0;
static PFN_debugGetRefCount p_ref_count = 0;
static PFN_getCallingUid p_calling_uid = 0;
static PFN_getCallingPid p_calling_pid = 0;

/* core (API 29, ABI-gated) + ext (API 31/33, reported) export sets. */
static const char* k_core_export_set[] = {
    "AIBinder_Class_define",
    "AIBinder_new",
    "AIBinder_incStrong",
    "AIBinder_decStrong",
    "AIBinder_associateClass",
    "AIBinder_isAlive",
    "AIBinder_isRemote",
    "AIBinder_ping",
    "AIBinder_getClass",
    "AIBinder_debugGetRefCount",
    "AIBinder_getCallingUid",
    "AIBinder_getCallingPid",
};
#define XBN_CORE_EXPORT_COUNT (sizeof(k_core_export_set) / sizeof(k_core_export_set[0]))

static const char* k_ext_export_set[] = {
    "AIBinder_Class_getDescriptor",
    "AIBinder_Class_setOnDump",
    "AIBinder_Class_disableInterfaceTokenHeader",
};
#define XBN_EXT_EXPORT_COUNT (sizeof(k_ext_export_set) / sizeof(k_ext_export_set[0]))

static void xbn_set_error(const char* msg) {
    snprintf(g_error, sizeof(g_error), "%s", msg);
}

void xbn_unload(void); /* defined at the bottom; used by xbn_load_lib */

static void* xbn_resolve(const char* name) { return xbn_dlsym(g_lib, name); }

/* -- class callbacks (local test class) ------------------------------------- */

typedef struct XBN_UserData {
    int64_t arg;
    uint32_t magic;
} XBN_UserData;

#define XBN_USERDATA_MAGIC 0x584E4231u /* "XNB1" */

static void* xbn_on_create(void* args) {
    XBN_UserData* ud = (XBN_UserData*)malloc(sizeof(XBN_UserData));
    if (!ud) return 0;
    ud->arg = (int64_t)(intptr_t)args;
    ud->magic = XBN_USERDATA_MAGIC;
    return ud;
}

static void xbn_on_destroy(void* userData) {
    if (userData) {
        XBN_UserData* ud = (XBN_UserData*)userData;
        if (ud->magic == XBN_USERDATA_MAGIC) {
            ud->magic = 0;
            g_destroy_count += 1;
        }
        free(ud);
    }
}

static binder_status_t xbn_on_transact(AIBinder* binder, transaction_code_t code,
                                       const AParcel* in, AParcel* out) {
    (void)binder;
    (void)code;
    (void)in;
    (void)out;
    g_transact_count += 1;
    return XBN_STATUS_UNKNOWN_TRANSACTION;
}

/* -- load / classify --------------------------------------------------------- */

static void xbn_join_missing(char* buf, size_t cap, const char* name, int* count) {
    size_t used = strlen(buf);
    snprintf(buf + used, cap - used, "%s%s", used ? "," : "", name);
    *count += 1;
}

static int xbn_finish_load(void) {
    g_missing_count = 0;
    g_missing[0] = 0;
    g_ext_missing_count = 0;
    g_ext_missing[0] = 0;
    for (size_t i = 0; i < XBN_CORE_EXPORT_COUNT; i++) {
        if (!xbn_resolve(k_core_export_set[i])) {
            xbn_join_missing(g_missing, sizeof(g_missing), k_core_export_set[i], &g_missing_count);
        }
    }
    for (size_t i = 0; i < XBN_EXT_EXPORT_COUNT; i++) {
        if (!xbn_resolve(k_ext_export_set[i])) {
            xbn_join_missing(g_ext_missing, sizeof(g_ext_missing), k_ext_export_set[i],
                             &g_ext_missing_count);
        }
    }
    p_class_define = (PFN_Class_define)xbn_resolve("AIBinder_Class_define");
    p_class_descriptor = (PFN_Class_getDescriptor)xbn_resolve("AIBinder_Class_getDescriptor");
    p_new = (PFN_AIBinder_new)xbn_resolve("AIBinder_new");
    p_inc = (PFN_incStrong)xbn_resolve("AIBinder_incStrong");
    p_dec = (PFN_decStrong)xbn_resolve("AIBinder_decStrong");
    p_associate = (PFN_associateClass)xbn_resolve("AIBinder_associateClass");
    p_is_alive = (PFN_bool_const)xbn_resolve("AIBinder_isAlive");
    p_is_remote = (PFN_bool_const)xbn_resolve("AIBinder_isRemote");
    p_ping = (PFN_ping)xbn_resolve("AIBinder_ping");
    p_get_class = (PFN_getClass)xbn_resolve("AIBinder_getClass");
    p_ref_count = (PFN_debugGetRefCount)xbn_resolve("AIBinder_debugGetRefCount");
    p_calling_uid = (PFN_getCallingUid)xbn_resolve("AIBinder_getCallingUid");
    p_calling_pid = (PFN_getCallingPid)xbn_resolve("AIBinder_getCallingPid");
    if (g_missing_count != 0) {
        xbn_set_error(g_missing);
        return 2;
    }
    xbn_set_error("");
    return 0;
}

static int xbn_load_lib(const char* soname) {
    xbn_unload();
    g_lib = xbn_dlopen(soname);
    if (!g_lib) {
        snprintf(g_error, sizeof(g_error), "absent: %s", soname);
        return 1;
    }
    return xbn_finish_load();
}

int xbn_load_named(const char* soname) {
    if (!soname) {
        xbn_set_error("null soname");
        return 2;
    }
    return xbn_load_lib(soname);
}

int xbn_load(void) { return xbn_load_lib("libbinder_ndk.so"); }

const char* xbn_error(void) { return g_error; }

int xbn_core_missing_count(void) { return g_missing_count; }

const char* xbn_core_missing(void) { return g_missing; }

int xbn_ext_count(void) { return (int)XBN_EXT_EXPORT_COUNT; }

int xbn_ext_missing_count(void) { return g_ext_missing_count; }

const char* xbn_ext_missing(void) { return g_ext_missing; }

/* -- functional head --------------------------------------------------------- */

int64_t xbn_class_define(const char* descriptor) {
    if (!p_class_define) { xbn_set_error("AIBinder_Class_define unresolved"); return 0; }
    if (!descriptor || !descriptor[0]) { xbn_set_error("null/empty descriptor"); return 0; }
    if (g_class != 0) {
        if (strcmp(g_class_descriptor, descriptor) == 0) return g_class;
        /* A different descriptor: the previous class has no public delete
         * (NDK design); define the new one and drop the reference. */
        xbn_set_error("replacing a previously defined class");
    }
    AIBinder_Class* clazz =
        p_class_define(descriptor, xbn_on_create, xbn_on_destroy, xbn_on_transact);
    if (!clazz) {
        xbn_set_error("AIBinder_Class_define returned null");
        return 0;
    }
    snprintf(g_class_descriptor, sizeof(g_class_descriptor), "%s", descriptor);
    g_class = (int64_t)(intptr_t)clazz;
    return g_class;
}

const char* xbn_class_descriptor(int64_t clazz) {
    if (!clazz) { xbn_set_error("null class handle"); return ""; }
    if (!p_class_descriptor) {
        /* API 31+ extension symbol; fall back to the cached definition. */
        if (g_class == clazz && g_class_descriptor[0]) return g_class_descriptor;
        xbn_set_error("AIBinder_Class_getDescriptor unresolved (API 31+)");
        return "";
    }
    const char* d = p_class_descriptor((const AIBinder_Class*)(intptr_t)clazz);
    return d ? d : "";
}

int64_t xbn_create(int64_t clazz, int64_t arg) {
    if (!p_new) { xbn_set_error("AIBinder_new unresolved"); return 0; }
    if (!clazz) { xbn_set_error("null class handle"); return 0; }
    AIBinder* b = p_new((const AIBinder_Class*)(intptr_t)clazz, (void*)(intptr_t)arg);
    if (!b) {
        xbn_set_error("AIBinder_new returned null");
        return 0;
    }
    return (int64_t)(intptr_t)b;
}

void xbn_inc_strong(int64_t binder) {
    if (p_inc && binder) p_inc((AIBinder*)(intptr_t)binder);
}

void xbn_dec_strong(int64_t binder) {
    if (p_dec && binder) p_dec((AIBinder*)(intptr_t)binder);
}

int xbn_associate_class(int64_t binder, int64_t clazz) {
    if (!p_associate) { xbn_set_error("AIBinder_associateClass unresolved"); return -2; }
    if (!binder || !clazz) { xbn_set_error("null binder/class handle"); return -1; }
    return p_associate((AIBinder*)(intptr_t)binder, (const AIBinder_Class*)(intptr_t)clazz) ? 1 : 0;
}

int xbn_is_alive(int64_t binder) {
    if (!p_is_alive) { xbn_set_error("AIBinder_isAlive unresolved"); return -2; }
    if (!binder) { xbn_set_error("null binder handle"); return -1; }
    return p_is_alive((const AIBinder*)(intptr_t)binder) ? 1 : 0;
}

int xbn_is_remote(int64_t binder) {
    if (!p_is_remote) { xbn_set_error("AIBinder_isRemote unresolved"); return -2; }
    if (!binder) { xbn_set_error("null binder handle"); return -1; }
    return p_is_remote((const AIBinder*)(intptr_t)binder) ? 1 : 0;
}

int xbn_ping(int64_t binder) {
    /* ping returns a real binder_status_t (0 or negative): -2 is a valid
     * status (NAME_NOT_FOUND), so the unresolved sentinel here is -1024
     * (outside the binder_status_t value set). */
    if (!p_ping) { xbn_set_error("AIBinder_ping unresolved"); return -1024; }
    if (!binder) { xbn_set_error("null binder handle"); return -1024; }
    return (int)p_ping((AIBinder*)(intptr_t)binder);
}

int64_t xbn_get_class(int64_t binder) {
    if (!p_get_class) { xbn_set_error("AIBinder_getClass unresolved"); return 0; }
    if (!binder) { xbn_set_error("null binder handle"); return 0; }
    return (int64_t)(intptr_t)p_get_class((AIBinder*)(intptr_t)binder);
}

int xbn_debug_ref_count(int64_t binder) {
    if (!p_ref_count) { xbn_set_error("AIBinder_debugGetRefCount unresolved"); return -2; }
    if (!binder) { xbn_set_error("null binder handle"); return -1; }
    return (int)p_ref_count((AIBinder*)(intptr_t)binder);
}

int64_t xbn_calling_uid(void) {
    if (!p_calling_uid) { xbn_set_error("AIBinder_getCallingUid unresolved"); return -1; }
    return (int64_t)p_calling_uid();
}

int64_t xbn_calling_pid(void) {
    if (!p_calling_pid) { xbn_set_error("AIBinder_getCallingPid unresolved"); return -1; }
    return (int64_t)p_calling_pid();
}

int xbn_destroy_count(void) { return g_destroy_count; }

int xbn_transact_count(void) { return g_transact_count; }

const char* xbn_status_name(int status) {
    switch (status) {
    case XBN_STATUS_OK: return "OK";
    case XBN_STATUS_UNKNOWN_ERROR: return "UNKNOWN_ERROR";
    case XBN_STATUS_NO_MEMORY: return "NO_MEMORY";
    case XBN_STATUS_INVALID_OPERATION: return "INVALID_OPERATION";
    case XBN_STATUS_BAD_VALUE: return "BAD_VALUE";
    case XBN_STATUS_BAD_TYPE: return "BAD_TYPE";
    case XBN_STATUS_NAME_NOT_FOUND: return "NAME_NOT_FOUND";
    case XBN_STATUS_PERMISSION_DENIED: return "PERMISSION_DENIED";
    case XBN_STATUS_NO_INIT: return "NO_INIT";
    case XBN_STATUS_ALREADY_EXISTS: return "ALREADY_EXISTS";
    case XBN_STATUS_DEAD_OBJECT: return "DEAD_OBJECT";
    case XBN_STATUS_FAILED_TRANSACTION: return "FAILED_TRANSACTION";
    case XBN_STATUS_BAD_INDEX: return "BAD_INDEX";
    case XBN_STATUS_NOT_ENOUGH_DATA: return "NOT_ENOUGH_DATA";
    case XBN_STATUS_WOULD_BLOCK: return "WOULD_BLOCK";
    case XBN_STATUS_TIMED_OUT: return "TIMED_OUT";
    case XBN_STATUS_UNKNOWN_TRANSACTION: return "UNKNOWN_TRANSACTION";
    case XBN_STATUS_FDS_NOT_ALLOWED: return "FDS_NOT_ALLOWED";
    case XBN_STATUS_UNEXPECTED_NULL: return "UNEXPECTED_NULL";
    default: {
        static char buf[48];
        snprintf(buf, sizeof(buf), "UNRECOGNIZED(%d)", status);
        return buf;
    }
    }
}

/* -- teardown ---------------------------------------------------------------- */

void xbn_unload(void) {
    if (g_lib) { xbn_dlclose(g_lib); g_lib = 0; }
    p_class_define = 0;
    p_class_descriptor = 0;
    p_new = 0;
    p_inc = 0;
    p_dec = 0;
    p_associate = 0;
    p_is_alive = 0;
    p_is_remote = 0;
    p_ping = 0;
    p_get_class = 0;
    p_ref_count = 0;
    p_calling_uid = 0;
    p_calling_pid = 0;
    g_missing_count = 0;
    g_missing[0] = 0;
    g_ext_missing_count = 0;
    g_ext_missing[0] = 0;
    /* g_class / g_class_descriptor stay: class objects are
     * process-lifetime (no public delete in the NDK). */
}
