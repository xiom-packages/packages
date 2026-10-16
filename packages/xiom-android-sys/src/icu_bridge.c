/* XIOM -- xiom.android-sys: libicu (ICU subset) runtime bridge.
 * Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
 * Licensed under the MIT or Apache-2.0 license, at your option.
 *
 * DESIGN: self-contained runtime loader/probe for the DECLARED ICU subset
 * (unicode/ustring.h + uchar.h + utypes.h of NDK r27b, ICU 75.1).
 * SONAME NOTE: Android ships the ICU C API as libandroidicu.so (the
 * soname the NDK -licuuc alias resolves to); libicuuc.so carries the C++
 * ICU API and does NOT export the u_* C surface -- the loader therefore
 * targets libandroidicu.so, and reports the missing names explicitly if
 * a platform exposes something else.  The subset is by design: error
 * naming + UTF-8/UTF-16 conversion + UTF-16 unit length + simple case
 * mapping -- the minimum a text engine needs to validate the platform
 * text plumbing.  The full ICU surface (collation, break iteration,
 * formatting, ...) is a documented delta.
 *
 * Declared subset (6 symbols; the NDK headers macro-map the unsuffixed
 * names through U_ICU_ENTRY_POINT_RENAME with U_LIB_SUFFIX_C_NAME=_android,
 * so the loader resolves the _android exports):
 *   required (gated on the live path, 5):
 *     u_errorName_android, u_strToUTF8_android, u_strFromUTF8_android,
 *     u_toupper_android, u_tolower_android
 *   optional (resolved + reported, 1):
 *     u_strlen_android -- the NDK header announces u_strlen
 *     __INTRODUCED_IN(31), but the API-36 platform shim
 *     (libandroidicu.so, ICU 75.1) does NOT export it (dynsym evidence in
 *     docs/repro/android-sys-probe/README.md); the module reports the gap
 *     instead of faking a length.
 * Platform gate: because the NDK marks the whole subset API 31+, a
 * pre-31 platform reports the missing names and classifies GATED (an
 * explicit SKIP with reason -- never a silent skip, never a false FAIL).
 *
 * Contract (flat extern "C", called from module xiom.android_sys.icu):
 *   int         xic_load_named(const char* soname)  0=ok 1=absent
 *   int         xic_load(void)                      "libandroidicu.so"
 *   const char* xic_error(void)
 *   int         xic_declared_total(void)            declared subset size (6)
 *   int         xic_required_missing_count(void)
 *   const char* xic_required_missing(void)
 *   int         xic_optional_missing_count(void)
 *   const char* xic_optional_missing(void)
 *   const char* xic_error_name(int code)            u_errorName
 *   int         xic_strlen(const uint8* units_le, int unit_count)
 *   int         xic_utf8_to_utf16(const uint8* text, uint8* out, int out_cap,
 *                                 uint8* size_slot)  rc; bytes LE
 *   int         xic_utf16_to_utf8(const uint8* units_le, int unit_count,
 *                                 uint8* out, int out_cap, uint8* size_slot)
 *   int         xic_toupper(int32 cp)
 *   int         xic_tolower(int32 cp)
 *   void        xic_unload(void)
 *
 * UTF-16 crossings are little-endian byte slots (one u16 per pair of
 * bytes, B-series byte-indexed discipline).  Error codes are ICU
 * UErrorCode values; -1 = call-time failure with the reason in
 * xic_error(); -2 = "symbol unresolved".
 */

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#include <windows.h>
typedef HMODULE xic_lib_t;
static xic_lib_t xic_dlopen(const char* name) { return LoadLibraryA(name); }
static void* xic_dlsym(xic_lib_t h, const char* name) {
    return h ? (void*)GetProcAddress(h, name) : 0;
}
static void xic_dlclose(xic_lib_t h) { if (h) FreeLibrary(h); }
#else
#include <dlfcn.h>
typedef void* xic_lib_t;
static xic_lib_t xic_dlopen(const char* name) { return dlopen(name, RTLD_NOW | RTLD_LOCAL); }
static void* xic_dlsym(xic_lib_t h, const char* name) { return h ? dlsym(h, name) : 0; }
static void xic_dlclose(xic_lib_t h) { if (h) dlclose(h); }
#endif

/* -- re-declared ABI facts (NDK r27b unicode headers, ICU 75.1) ------------- */

typedef uint16_t UChar;   /* UTF-16 code unit */
typedef int32_t UChar32;  /* Unicode code point */
typedef int32_t UErrorCode;

#define XIC_U_ZERO_ERROR 0
#define XIC_U_ILLEGAL_ARGUMENT_ERROR 1
#define XIC_U_INVALID_CHAR_FOUND 10
#define XIC_U_TRUNCATED_CHAR_FOUND 11
#define XIC_U_ILLEGAL_CHAR_FOUND 12
#define XIC_U_BUFFER_OVERFLOW_ERROR 15
#define XIC_U_STRING_NOT_TERMINATED (-124) /* warning, not a failure */

typedef const char* (*PFN_u_errorName)(UErrorCode);
typedef int32_t (*PFN_u_strlen)(const UChar*);
typedef char* (*PFN_u_strToUTF8)(char*, int32_t, int32_t*, const UChar*, int32_t, UErrorCode*);
typedef UChar* (*PFN_u_strFromUTF8)(UChar*, int32_t, int32_t*, const char*, int32_t, UErrorCode*);
typedef UChar32 (*PFN_u_case)(UChar32);

/* -- bridge state ------------------------------------------------------------ */

static xic_lib_t g_lib = 0;
static char g_error[512] = {0};
static char g_req_missing[512] = {0};
static char g_opt_missing[512] = {0};
static int g_req_missing_count = 0;
static int g_opt_missing_count = 0;

static PFN_u_errorName p_error_name = 0;
static PFN_u_strlen p_strlen = 0;
static PFN_u_strToUTF8 p_to_utf8 = 0;
static PFN_u_strFromUTF8 p_from_utf8 = 0;
static PFN_u_case p_toupper = 0;
static PFN_u_case p_tolower = 0;

static const char* k_required_set[] = {
    "u_errorName_android", "u_strToUTF8_android", "u_strFromUTF8_android",
    "u_toupper_android", "u_tolower_android",
};
#define XIC_REQUIRED_COUNT (sizeof(k_required_set) / sizeof(k_required_set[0]))

static const char* k_optional_set[] = {
    "u_strlen_android",
};
#define XIC_OPTIONAL_COUNT (sizeof(k_optional_set) / sizeof(k_optional_set[0]))

#define XIC_DECLARED_COUNT (XIC_REQUIRED_COUNT + XIC_OPTIONAL_COUNT)

static void xic_set_error(const char* msg) {
    snprintf(g_error, sizeof(g_error), "%s", msg);
}

void xic_unload(void); /* defined at the bottom; used by xic_load_lib */

static void xic_join_missing(char* buf, size_t cap, const char* name, int* count) {
    size_t used = strlen(buf);
    snprintf(buf + used, cap - used, "%s%s", used ? "," : "", name);
    *count += 1;
}

static int xic_finish_load(void) {
    g_req_missing_count = 0;
    g_req_missing[0] = 0;
    g_opt_missing_count = 0;
    g_opt_missing[0] = 0;
    for (size_t i = 0; i < XIC_REQUIRED_COUNT; i++) {
        if (!xic_dlsym(g_lib, k_required_set[i])) {
            xic_join_missing(g_req_missing, sizeof(g_req_missing), k_required_set[i],
                             &g_req_missing_count);
        }
    }
    for (size_t i = 0; i < XIC_OPTIONAL_COUNT; i++) {
        if (!xic_dlsym(g_lib, k_optional_set[i])) {
            xic_join_missing(g_opt_missing, sizeof(g_opt_missing), k_optional_set[i],
                             &g_opt_missing_count);
        }
    }
    p_error_name = (PFN_u_errorName)xic_dlsym(g_lib, "u_errorName_android");
    p_strlen = (PFN_u_strlen)xic_dlsym(g_lib, "u_strlen_android");
    p_to_utf8 = (PFN_u_strToUTF8)xic_dlsym(g_lib, "u_strToUTF8_android");
    p_from_utf8 = (PFN_u_strFromUTF8)xic_dlsym(g_lib, "u_strFromUTF8_android");
    p_toupper = (PFN_u_case)xic_dlsym(g_lib, "u_toupper_android");
    p_tolower = (PFN_u_case)xic_dlsym(g_lib, "u_tolower_android");
    xic_set_error("");
    return 0;
}

static int xic_load_lib(const char* soname) {
    xic_unload();
    g_lib = xic_dlopen(soname);
    if (!g_lib) {
        snprintf(g_error, sizeof(g_error), "absent: %s", soname);
        return 1;
    }
    return xic_finish_load();
}

int xic_load_named(const char* soname) {
    if (!soname) {
        xic_set_error("null soname");
        return 2;
    }
    return xic_load_lib(soname);
}

int xic_load(void) { return xic_load_lib("libandroidicu.so"); }

const char* xic_error(void) { return g_error; }

int xic_declared_total(void) { return (int)XIC_DECLARED_COUNT; }

int xic_required_missing_count(void) { return g_req_missing_count; }

const char* xic_required_missing(void) { return g_req_missing; }

int xic_optional_missing_count(void) { return g_opt_missing_count; }

const char* xic_optional_missing(void) { return g_opt_missing; }

static void xic_write_u64_le(uint8_t* slot, uint64_t v) {
    slot[0] = (uint8_t)(v & 0xFF);
    slot[1] = (uint8_t)((v >> 8) & 0xFF);
    slot[2] = (uint8_t)((v >> 16) & 0xFF);
    slot[3] = (uint8_t)((v >> 24) & 0xFF);
    slot[4] = (uint8_t)((v >> 32) & 0xFF);
    slot[5] = (uint8_t)((v >> 40) & 0xFF);
    slot[6] = (uint8_t)((v >> 48) & 0xFF);
    slot[7] = (uint8_t)((v >> 56) & 0xFF);
}

/* -- declared subset --------------------------------------------------------- */

const char* xic_error_name(int code) {
    if (!p_error_name) { xic_set_error("u_errorName unresolved"); return ""; }
    return p_error_name((UErrorCode)code);
}

int xic_strlen(const uint8_t* units_le, int unit_count) {
    if (!p_strlen) {
        xic_set_error("u_strlen_android not exported by this platform shim (optional subset symbol)");
        return -2;
    }
    if (!units_le || unit_count < 0) { xic_set_error("null units / negative count"); return -1; }
    UChar* scratch = (UChar*)malloc(((size_t)unit_count + 1u) * sizeof(UChar));
    if (!scratch) { xic_set_error("malloc failed"); return -1; }
    for (int i = 0; i < unit_count; i++) {
        const uint8_t* b = units_le + (size_t)i * 2u;
        scratch[i] = (UChar)((uint16_t)b[0] | ((uint16_t)b[1] << 8));
    }
    scratch[unit_count] = 0;
    int32_t n = p_strlen(scratch);
    free(scratch);
    return (int)n;
}

int xic_utf8_to_utf16(const uint8_t* text, uint8_t* out, int out_cap, uint8_t* size_slot) {
    if (!p_from_utf8) { xic_set_error("u_strFromUTF8 unresolved"); return -2; }
    if (!text || !out || !size_slot) { xic_set_error("null buffer/slot"); return -1; }
    if (out_cap < 2 || out_cap % 2 != 0) { xic_set_error("out_cap must be a positive multiple of 2"); return -1; }
    if (!size_slot) { xic_set_error("null size slot"); return -1; }
    UErrorCode ec = XIC_U_ZERO_ERROR;
    int32_t dest_len = 0;
    int32_t src_len = (int32_t)strlen((const char*)text);
    p_from_utf8((UChar*)out, (int32_t)(out_cap / 2), &dest_len, (const char*)text, src_len, &ec);
    xic_write_u64_le(size_slot, (uint64_t)dest_len * 2u);
    if (ec != XIC_U_ZERO_ERROR && ec != XIC_U_STRING_NOT_TERMINATED) {
        snprintf(g_error, sizeof(g_error), "u_strFromUTF8 UErrorCode=%d (%s)", (int)ec,
                 p_error_name ? p_error_name(ec) : "?");
        return -1;
    }
    return 0;
}

int xic_utf16_to_utf8(const uint8_t* units_le, int unit_count, uint8_t* out, int out_cap,
                      uint8_t* size_slot) {
    if (!p_to_utf8) { xic_set_error("u_strToUTF8 unresolved"); return -2; }
    if (!units_le || !out || !size_slot) { xic_set_error("null buffer/slot"); return -1; }
    if (unit_count < 0) { xic_set_error("negative unit count"); return -1; }
    if (out_cap < 1) { xic_set_error("out_cap must be positive"); return -1; }
    UChar* scratch = (UChar*)malloc(((size_t)unit_count + 1u) * sizeof(UChar));
    if (!scratch) { xic_set_error("malloc failed"); return -1; }
    for (int i = 0; i < unit_count; i++) {
        const uint8_t* b = units_le + (size_t)i * 2u;
        scratch[i] = (UChar)((uint16_t)b[0] | ((uint16_t)b[1] << 8));
    }
    scratch[unit_count] = 0;
    UErrorCode ec = XIC_U_ZERO_ERROR;
    int32_t dest_len = 0;
    p_to_utf8((char*)out, (int32_t)out_cap, &dest_len, scratch, unit_count, &ec);
    free(scratch);
    xic_write_u64_le(size_slot, (uint64_t)dest_len);
    if (ec != XIC_U_ZERO_ERROR && ec != XIC_U_STRING_NOT_TERMINATED) {
        snprintf(g_error, sizeof(g_error), "u_strToUTF8 UErrorCode=%d (%s)", (int)ec,
                 p_error_name ? p_error_name(ec) : "?");
        return -1;
    }
    return 0;
}

int xic_toupper(int32_t cp) {
    if (!p_toupper) { xic_set_error("u_toupper unresolved"); return -2; }
    return (int)p_toupper((UChar32)cp);
}

int xic_tolower(int32_t cp) {
    if (!p_tolower) { xic_set_error("u_tolower unresolved"); return -2; }
    return (int)p_tolower((UChar32)cp);
}

/* -- teardown ---------------------------------------------------------------- */

void xic_unload(void) {
    if (g_lib) { xic_dlclose(g_lib); g_lib = 0; }
    p_error_name = 0; p_strlen = 0; p_to_utf8 = 0; p_from_utf8 = 0;
    p_toupper = 0; p_tolower = 0;
    g_req_missing_count = 0;
    g_req_missing[0] = 0;
    g_opt_missing_count = 0;
    g_opt_missing[0] = 0;
}
