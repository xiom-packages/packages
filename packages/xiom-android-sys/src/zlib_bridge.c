/* XIOM -- xiom.android-sys: libz (zlib) runtime bridge.
 * Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
 * Licensed under the MIT or Apache-2.0 license, at your option.
 *
 * DESIGN: self-contained runtime loader/probe for the zlib C API
 * (zlib.h of NDK r27b, ZLIB_VERSION "1.3.0.1-motley" -> libz.so).  No
 * link-time dependency, no zlib.h needed to compile: the declared
 * surface is re-declared by hand (ABI-pinned facts), loaded via
 * dlopen/LoadLibraryA at runtime and export-checked.
 *
 * Declared core set (ABI-gated, 12 symbols):
 *   zlibVersion, compress, uncompress, compressBound, crc32, adler32,
 *   deflateInit_, deflate, deflateEnd, inflateInit_, inflate, inflateEnd.
 * The z_stream struct is managed entirely on the C side (handle model,
 * calloc'd, pinned LP64 layout); only opaque Int64 handles cross.
 *
 * Functional head: one-shot compress/uncompress roundtrip, crc32/adler32
 * checksums, and streaming deflate/inflate through explicit
 * begin/set-input/step/end calls (Z_FINISH semantics; caller loops on
 * the step result with owned output slots).
 *
 * Contract (flat extern "C", called from module xiom.android_sys.zlib):
 *   int         xzl_load_named(const char* soname)   0=ok 1=absent 2=abi
 *   int         xzl_load(void)                       "libz.so"
 *   const char* xzl_error(void)
 *   int         xzl_core_missing_count(void)
 *   const char* xzl_core_missing(void)
 *   const char* xzl_version(void)                    zlibVersion()
 *   int64       xzl_compress_bound(int64 src_len)
 *   int         xzl_compress(const uint8* src, int64 src_len, uint8* dst,
 *                            int64 dst_cap, uint8* size_slot)   rc; size LE
 *   int         xzl_uncompress(const uint8* src, int64 src_len, uint8* dst,
 *                              int64 dst_cap, uint8* size_slot) rc; size LE
 *   int64       xzl_crc32(int64 init, const uint8* src, int64 len)
 *   int64       xzl_adler32(int64 init, const uint8* src, int64 len)
 *   int64       xzl_deflate_begin(int level)         handle; 0 = fail
 *   int         xzl_deflate_input(int64 h, const uint8* src, int64 len)
 *   int         xzl_deflate_step(int64 h, uint8* dst, int64 cap, int flush,
 *                                uint8* size_slot)   zlib rc; written LE
 *   int         xzl_deflate_end(int64 h)             zlib rc
 *   int64       xzl_inflate_begin(void)
 *   int         xzl_inflate_input(int64 h, const uint8* src, int64 len)
 *   int         xzl_inflate_step(int64 h, uint8* dst, int64 cap, int flush,
 *                                uint8* size_slot)
 *   int         xzl_inflate_end(int64 h)
 *   const char* xzl_rc_name(int rc)
 *   void        xzl_unload(void)
 *
 * Sentinel convention: -1000 = "symbol unresolved" (outside the zlib rc
 * range; mapped to LOAD_ABI by the module); -1 = call-time failure with
 * the reason in xzl_error().
 */

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#include <windows.h>
typedef HMODULE xzl_lib_t;
static xzl_lib_t xzl_dlopen(const char* name) { return LoadLibraryA(name); }
static void* xzl_dlsym(xzl_lib_t h, const char* name) {
    return h ? (void*)GetProcAddress(h, name) : 0;
}
static void xzl_dlclose(xzl_lib_t h) { if (h) FreeLibrary(h); }
#else
#include <dlfcn.h>
typedef void* xzl_lib_t;
static xzl_lib_t xzl_dlopen(const char* name) { return dlopen(name, RTLD_NOW | RTLD_LOCAL); }
static void* xzl_dlsym(xzl_lib_t h, const char* name) { return h ? dlsym(h, name) : 0; }
static void xzl_dlclose(xzl_lib_t h) { if (h) dlclose(h); }
#endif

/* -- re-declared ABI facts (zlib.h r27b) ------------------------------------ */

typedef struct XZL_Stream {
    uint8_t* next_in;
    uint32_t avail_in;
    uint32_t _pad0;
    uint64_t total_in;
    uint8_t* next_out;
    uint32_t avail_out;
    uint32_t _pad1;
    uint64_t total_out;
    char* msg;
    void* state;
    void* zalloc;
    void* zfree;
    void* opaque;
    int32_t data_type;
    uint32_t _pad2;
    uint64_t adler;
    uint64_t reserved;
} XZL_Stream;

/* zlib constants (zlib.h r27b). */
#define XZL_OK 0
#define XZL_STREAM_END 1
#define XZL_NEED_DICT 2
#define XZL_ERRNO (-1)
#define XZL_STREAM_ERROR (-2)
#define XZL_DATA_ERROR (-3)
#define XZL_MEM_ERROR (-4)
#define XZL_BUF_ERROR (-5)
#define XZL_VERSION_ERROR (-6)
#define XZL_NO_FLUSH 0
#define XZL_PARTIAL_FLUSH 1
#define XZL_SYNC_FLUSH 2
#define XZL_FULL_FLUSH 3
#define XZL_FINISH 4

#define XZL_UNRESOLVED (-1000)
#define XZL_MAX_IN (0xFFFFFFFFu)

typedef const char* (*PFN_zlibVersion)(void);
typedef int (*PFN_compress)(uint8_t*, uint64_t*, const uint8_t*, uint64_t);
typedef uint64_t (*PFN_compressBound)(uint64_t);
typedef int (*PFN_uncompress)(uint8_t*, uint64_t*, const uint8_t*, uint64_t);
typedef uint64_t (*PFN_crc32)(uint64_t, const uint8_t*, unsigned int);
typedef uint64_t (*PFN_adler32)(uint64_t, const uint8_t*, unsigned int);
typedef int (*PFN_deflateInit_)(XZL_Stream*, int, const char*, int);
typedef int (*PFN_deflate)(XZL_Stream*, int);
typedef int (*PFN_deflateEnd)(XZL_Stream*);
typedef int (*PFN_inflateInit_)(XZL_Stream*, const char*, int);
typedef int (*PFN_inflate)(XZL_Stream*, int);
typedef int (*PFN_inflateEnd)(XZL_Stream*);

/* -- bridge state ------------------------------------------------------------ */

static xzl_lib_t g_lib = 0;
static char g_error[512] = {0};
static char g_missing[512] = {0};
static int g_missing_count = 0;

static PFN_zlibVersion p_version = 0;
static PFN_compress p_compress = 0;
static PFN_compressBound p_compress_bound = 0;
static PFN_uncompress p_uncompress = 0;
static PFN_crc32 p_crc32 = 0;
static PFN_adler32 p_adler32 = 0;
static PFN_deflateInit_ p_deflate_init = 0;
static PFN_deflate p_deflate = 0;
static PFN_deflateEnd p_deflate_end = 0;
static PFN_inflateInit_ p_inflate_init = 0;
static PFN_inflate p_inflate = 0;
static PFN_inflateEnd p_inflate_end = 0;

static const char* k_core_export_set[] = {
    "zlibVersion", "compress",   "compressBound", "uncompress", "crc32",  "adler32",
    "deflateInit_", "deflate",   "deflateEnd",    "inflateInit_", "inflate", "inflateEnd",
};
#define XZL_CORE_EXPORT_COUNT (sizeof(k_core_export_set) / sizeof(k_core_export_set[0]))

static void xzl_set_error(const char* msg) {
    snprintf(g_error, sizeof(g_error), "%s", msg);
}

void xzl_unload(void); /* defined at the bottom; used by xzl_load_lib */

static void xzl_join_missing(char* buf, size_t cap, const char* name, int* count) {
    size_t used = strlen(buf);
    snprintf(buf + used, cap - used, "%s%s", used ? "," : "", name);
    *count += 1;
}

static int xzl_finish_load(void) {
    g_missing_count = 0;
    g_missing[0] = 0;
    for (size_t i = 0; i < XZL_CORE_EXPORT_COUNT; i++) {
        if (!xzl_dlsym(g_lib, k_core_export_set[i])) {
            xzl_join_missing(g_missing, sizeof(g_missing), k_core_export_set[i], &g_missing_count);
        }
    }
    p_version = (PFN_zlibVersion)xzl_dlsym(g_lib, "zlibVersion");
    p_compress = (PFN_compress)xzl_dlsym(g_lib, "compress");
    p_compress_bound = (PFN_compressBound)xzl_dlsym(g_lib, "compressBound");
    p_uncompress = (PFN_uncompress)xzl_dlsym(g_lib, "uncompress");
    p_crc32 = (PFN_crc32)xzl_dlsym(g_lib, "crc32");
    p_adler32 = (PFN_adler32)xzl_dlsym(g_lib, "adler32");
    p_deflate_init = (PFN_deflateInit_)xzl_dlsym(g_lib, "deflateInit_");
    p_deflate = (PFN_deflate)xzl_dlsym(g_lib, "deflate");
    p_deflate_end = (PFN_deflateEnd)xzl_dlsym(g_lib, "deflateEnd");
    p_inflate_init = (PFN_inflateInit_)xzl_dlsym(g_lib, "inflateInit_");
    p_inflate = (PFN_inflate)xzl_dlsym(g_lib, "inflate");
    p_inflate_end = (PFN_inflateEnd)xzl_dlsym(g_lib, "inflateEnd");
    if (g_missing_count != 0) {
        xzl_set_error(g_missing);
        return 2;
    }
    xzl_set_error("");
    return 0;
}

static int xzl_load_lib(const char* soname) {
    xzl_unload();
    g_lib = xzl_dlopen(soname);
    if (!g_lib) {
        snprintf(g_error, sizeof(g_error), "absent: %s", soname);
        return 1;
    }
    return xzl_finish_load();
}

int xzl_load_named(const char* soname) {
    if (!soname) {
        xzl_set_error("null soname");
        return 2;
    }
    return xzl_load_lib(soname);
}

int xzl_load(void) { return xzl_load_lib("libz.so"); }

const char* xzl_error(void) { return g_error; }

int xzl_core_missing_count(void) { return g_missing_count; }

const char* xzl_core_missing(void) { return g_missing; }

const char* xzl_version(void) { return p_version ? p_version() : ""; }

/* -- one-shot helpers -------------------------------------------------------- */

static void xzl_write_u64_le(uint8_t* slot, uint64_t v) {
    slot[0] = (uint8_t)(v & 0xFF);
    slot[1] = (uint8_t)((v >> 8) & 0xFF);
    slot[2] = (uint8_t)((v >> 16) & 0xFF);
    slot[3] = (uint8_t)((v >> 24) & 0xFF);
    slot[4] = (uint8_t)((v >> 32) & 0xFF);
    slot[5] = (uint8_t)((v >> 40) & 0xFF);
    slot[6] = (uint8_t)((v >> 48) & 0xFF);
    slot[7] = (uint8_t)((v >> 56) & 0xFF);
}

int64_t xzl_compress_bound(int64_t src_len) {
    if (!p_compress_bound) { xzl_set_error("compressBound unresolved"); return XZL_UNRESOLVED; }
    if (src_len < 0) { xzl_set_error("negative length"); return -1; }
    return (int64_t)p_compress_bound((uint64_t)src_len);
}

int xzl_compress(const uint8_t* src, int64_t src_len, uint8_t* dst, int64_t dst_cap,
                 uint8_t* size_slot) {
    if (!p_compress) { xzl_set_error("compress unresolved"); return XZL_UNRESOLVED; }
    if (!src || !dst || !size_slot) { xzl_set_error("null buffer/slot"); return -1; }
    if (src_len < 0 || dst_cap < 0) { xzl_set_error("negative length"); return -1; }
    uint64_t out_len = (uint64_t)dst_cap;
    int rc = p_compress(dst, &out_len, src, (uint64_t)src_len);
    if (rc != XZL_OK) {
        snprintf(g_error, sizeof(g_error), "compress rc=%d", rc);
    }
    xzl_write_u64_le(size_slot, out_len);
    return rc;
}

int xzl_uncompress(const uint8_t* src, int64_t src_len, uint8_t* dst, int64_t dst_cap,
                   uint8_t* size_slot) {
    if (!p_uncompress) { xzl_set_error("uncompress unresolved"); return XZL_UNRESOLVED; }
    if (!src || !dst || !size_slot) { xzl_set_error("null buffer/slot"); return -1; }
    if (src_len < 0 || dst_cap < 0) { xzl_set_error("negative length"); return -1; }
    uint64_t out_len = (uint64_t)dst_cap;
    int rc = p_uncompress(dst, &out_len, src, (uint64_t)src_len);
    if (rc != XZL_OK) {
        snprintf(g_error, sizeof(g_error), "uncompress rc=%d", rc);
    }
    xzl_write_u64_le(size_slot, out_len);
    return rc;
}

int64_t xzl_crc32(int64_t init, const uint8_t* src, int64_t len) {
    if (!p_crc32) { xzl_set_error("crc32 unresolved"); return XZL_UNRESOLVED; }
    if (len < 0) { xzl_set_error("negative length"); return -1; }
    if (len > 0 && !src) { xzl_set_error("null buffer"); return -1; }
    return (int64_t)p_crc32((uint64_t)init, src, (unsigned int)len);
}

int64_t xzl_adler32(int64_t init, const uint8_t* src, int64_t len) {
    if (!p_adler32) { xzl_set_error("adler32 unresolved"); return XZL_UNRESOLVED; }
    if (len < 0) { xzl_set_error("negative length"); return -1; }
    if (len > 0 && !src) { xzl_set_error("null buffer"); return -1; }
    return (int64_t)p_adler32((uint64_t)init, src, (unsigned int)len);
}

/* -- streaming basics (z_stream held C-side; opaque Int64 handle) ------------- */

int64_t xzl_deflate_begin(int level) {
    if (!p_deflate_init) { xzl_set_error("deflateInit_ unresolved"); return 0; }
    XZL_Stream* s = (XZL_Stream*)calloc(1, sizeof(XZL_Stream));
    if (!s) { xzl_set_error("calloc failed"); return 0; }
    int rc = p_deflate_init(s, level, xzl_version(), (int)sizeof(XZL_Stream));
    if (rc != XZL_OK) {
        snprintf(g_error, sizeof(g_error), "deflateInit_ rc=%d", rc);
        free(s);
        return 0;
    }
    return (int64_t)(intptr_t)s;
}

int xzl_deflate_input(int64_t h, const uint8_t* src, int64_t len) {
    if (!h) { xzl_set_error("null deflate handle"); return -1; }
    if (len < 0 || (uint64_t)len > XZL_MAX_IN) { xzl_set_error("input length out of range"); return -1; }
    if (len > 0 && !src) { xzl_set_error("null input buffer"); return -1; }
    XZL_Stream* s = (XZL_Stream*)(intptr_t)h;
    s->next_in = (uint8_t*)src;
    s->avail_in = (uint32_t)len;
    return 0;
}

int xzl_deflate_step(int64_t h, uint8_t* dst, int64_t cap, int flush, uint8_t* size_slot) {
    if (!p_deflate) { xzl_set_error("deflate unresolved"); return XZL_UNRESOLVED; }
    if (!h || !dst || !size_slot) { xzl_set_error("null handle/buffer/slot"); return -1; }
    if (cap < 0 || (uint64_t)cap > XZL_MAX_IN) { xzl_set_error("output cap out of range"); return -1; }
    XZL_Stream* s = (XZL_Stream*)(intptr_t)h;
    s->next_out = dst;
    s->avail_out = (uint32_t)cap;
    int rc = p_deflate(s, flush);
    uint64_t written = (uint64_t)cap - (uint64_t)s->avail_out;
    xzl_write_u64_le(size_slot, written);
    if (rc < 0 && rc != XZL_STREAM_END) {
        snprintf(g_error, sizeof(g_error), "deflate rc=%d", rc);
    }
    return rc;
}

int xzl_deflate_end(int64_t h) {
    if (!p_deflate_end) { xzl_set_error("deflateEnd unresolved"); return XZL_UNRESOLVED; }
    if (!h) { xzl_set_error("null deflate handle"); return -1; }
    XZL_Stream* s = (XZL_Stream*)(intptr_t)h;
    int rc = p_deflate_end(s);
    free(s);
    return rc;
}

int64_t xzl_inflate_begin(void) {
    if (!p_inflate_init) { xzl_set_error("inflateInit_ unresolved"); return 0; }
    XZL_Stream* s = (XZL_Stream*)calloc(1, sizeof(XZL_Stream));
    if (!s) { xzl_set_error("calloc failed"); return 0; }
    int rc = p_inflate_init(s, xzl_version(), (int)sizeof(XZL_Stream));
    if (rc != XZL_OK) {
        snprintf(g_error, sizeof(g_error), "inflateInit_ rc=%d", rc);
        free(s);
        return 0;
    }
    return (int64_t)(intptr_t)s;
}

int xzl_inflate_input(int64_t h, const uint8_t* src, int64_t len) {
    if (!h) { xzl_set_error("null inflate handle"); return -1; }
    if (len < 0 || (uint64_t)len > XZL_MAX_IN) { xzl_set_error("input length out of range"); return -1; }
    if (len > 0 && !src) { xzl_set_error("null input buffer"); return -1; }
    XZL_Stream* s = (XZL_Stream*)(intptr_t)h;
    s->next_in = (uint8_t*)src;
    s->avail_in = (uint32_t)len;
    return 0;
}

int xzl_inflate_step(int64_t h, uint8_t* dst, int64_t cap, int flush, uint8_t* size_slot) {
    if (!p_inflate) { xzl_set_error("inflate unresolved"); return XZL_UNRESOLVED; }
    if (!h || !dst || !size_slot) { xzl_set_error("null handle/buffer/slot"); return -1; }
    if (cap < 0 || (uint64_t)cap > XZL_MAX_IN) { xzl_set_error("output cap out of range"); return -1; }
    XZL_Stream* s = (XZL_Stream*)(intptr_t)h;
    s->next_out = dst;
    s->avail_out = (uint32_t)cap;
    int rc = p_inflate(s, flush);
    uint64_t written = (uint64_t)cap - (uint64_t)s->avail_out;
    xzl_write_u64_le(size_slot, written);
    if (rc < 0 && rc != XZL_STREAM_END) {
        snprintf(g_error, sizeof(g_error), "inflate rc=%d", rc);
    }
    return rc;
}

int xzl_inflate_end(int64_t h) {
    if (!p_inflate_end) { xzl_set_error("inflateEnd unresolved"); return XZL_UNRESOLVED; }
    if (!h) { xzl_set_error("null inflate handle"); return -1; }
    XZL_Stream* s = (XZL_Stream*)(intptr_t)h;
    int rc = p_inflate_end(s);
    free(s);
    return rc;
}

/* -- rc names ---------------------------------------------------------------- */

const char* xzl_rc_name(int rc) {
    switch (rc) {
    case XZL_OK: return "Z_OK";
    case XZL_STREAM_END: return "Z_STREAM_END";
    case XZL_NEED_DICT: return "Z_NEED_DICT";
    case XZL_ERRNO: return "Z_ERRNO";
    case XZL_STREAM_ERROR: return "Z_STREAM_ERROR";
    case XZL_DATA_ERROR: return "Z_DATA_ERROR";
    case XZL_MEM_ERROR: return "Z_MEM_ERROR";
    case XZL_BUF_ERROR: return "Z_BUF_ERROR";
    case XZL_VERSION_ERROR: return "Z_VERSION_ERROR";
    default: {
        static char buf[48];
        snprintf(buf, sizeof(buf), "UNRECOGNIZED(%d)", rc);
        return buf;
    }
    }
}

/* -- teardown ---------------------------------------------------------------- */

void xzl_unload(void) {
    if (g_lib) { xzl_dlclose(g_lib); g_lib = 0; }
    p_version = 0; p_compress = 0; p_compress_bound = 0; p_uncompress = 0;
    p_crc32 = 0; p_adler32 = 0;
    p_deflate_init = 0; p_deflate = 0; p_deflate_end = 0;
    p_inflate_init = 0; p_inflate = 0; p_inflate_end = 0;
    g_missing_count = 0;
    g_missing[0] = 0;
}
