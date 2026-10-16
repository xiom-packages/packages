/* xiom_http_shims.c -- consumer-side xiom_* FFI bridge for the xiom.http client.
 * Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
 * SPDX-License-Identifier: MIT OR Apache-2.0
 *
 * The pinned v0.64.2 toolchain runtime ships only xiom_alloc, while http.xi
 * declares the remaining xiom_* bridge symbols in its extern "C" block. Link
 * any consumer of the xiom.http client with:
 *
 *   xiom --run <app>.xi `
 *       --c-source <installed>\bridge\xiom_http_shims.c `
 *       --link curl --link-path <dir-with-curl.lib>
 *
 * This file deliberately contains NO libcurl stubs: the real libcurl import
 * library (curl.lib, i.e. curl-for-win's libcurl.dll.a copied to that name
 * because lld-link searches for curl.lib) is linked in place of the offline
 * stub used by the package test harness (tests/probe_bridge.c). Do not add
 * curl_easy_* definitions here -- they would shadow real libcurl symbols.
 *
 * Helpers (all free-standing malloc/memcpy based; no runtime state):
 *   xiom_free_ptr      real libc free() for buffers returned by xiom_alloc
 *   xiom_write_byte    bounds-free single-byte store into a C buffer
 *   xiom_read_byte     single-byte load from a C buffer (0 on null pointer)
 *   xiom_str_to_cstr   NUL-terminated malloc'd copy of (buf, len) bytes
 *   xiom_free_cstr     real libc free() for xiom_str_to_cstr buffers
 *   xiom_copy_from_vec copies count bytes into c_buf at offset, clamped to
 *                      (vec_len - offset); vec_cap is accepted and ignored
 *   xiom_http_headers_build  curl_slist* from a CRLF-separated header blob
 *                            (0.1.8: the CURLOPT_HTTPHEADER path; calls the
 *                            real curl_slist_append, declared below)
 *   xiom_http_headers_free   releases a list from xiom_http_headers_build
 *                            (real curl_slist_free_all)
 *
 * In production these live in %LOCALAPPDATA%\xiom\packages\xiom-http-<ver>\
 * bridge\xiom_http_shims.c; the tests bridge (tests/probe_bridge.c) keeps
 * its own copy plus the offline libcurl stubs and stays suite-only.
 */
#include <stdlib.h>
#include <string.h>

void xiom_free_ptr(void* p) { free(p); }

void xiom_write_byte(unsigned char* p, long long off, long long v) {
  if (p) p[off] = (unsigned char)v;
}

long long xiom_read_byte(const unsigned char* p, long long off) {
  if (!p) return 0;
  return (long long)p[off];
}

unsigned char* xiom_str_to_cstr(const unsigned char* s, long long len) {
  unsigned char* out = (unsigned char*)malloc((size_t)len + 1);
  if (!out) return NULL;
  if (s && len > 0) memcpy(out, s, (size_t)len);
  out[len] = 0;
  return out;
}

void xiom_free_cstr(unsigned char* s) { free(s); }

void xiom_copy_from_vec(unsigned char* c_buf, const unsigned char* vec_data,
                        long long vec_len, long long vec_cap, long long offset,
                        long long count) {
  (void)vec_cap;
  long long n = count;
  if (!c_buf) return;
  if (n > vec_len - offset) n = vec_len - offset;
  if (n <= 0) return;
  memcpy(c_buf + offset, vec_data, (size_t)n);
}

/* --- Custom request headers (0.1.8) --------------------------------------
 * curl_slist is forward-declared as an opaque struct plus the two entry
 * points used, so this file still needs no libcurl headers on the include
 * path (the consumer links the real import library via --link curl, which
 * provides curl_slist_append / curl_slist_free_all). Do NOT define these
 * two functions here -- only call them (the "no libcurl stubs" rule above).
 *
 * xiom_http_headers_build splits the CRLF-separated blob produced by the
 * XIOM-side builder (xiom.http.headers.http_headers_blob) into a curl_slist:
 * every "\r\n"-terminated segment becomes one list node with the separator
 * stripped; a trailing segment without CRLF is accepted as the last line.
 * Empty segments are skipped. curl_slist_append copies each line, so the
 * scratch buffer is freed immediately after the append.
 *
 * Returns NULL for a NULL/empty blob (meaning "no custom headers") and also
 * on allocation failure. The caller distinguishes the two cases by the blob:
 * a non-empty blob that yields NULL is a build failure. On failure the
 * partially built list is released before returning (no leak).
 *
 * Ownership: the returned list must be passed to curl_easy_setopt as
 * CURLOPT_HTTPHEADER (10023), and must stay alive until AFTER
 * curl_easy_cleanup(handle) -- libcurl keeps referencing it until then --
 * and is then released with xiom_http_headers_free. */

struct curl_slist;

extern struct curl_slist* curl_slist_append(struct curl_slist* list, const char* s);
extern void curl_slist_free_all(struct curl_slist* list);

void* xiom_http_headers_build(const unsigned char* blob) {
  struct curl_slist* list = NULL;
  const char* p;
  if (!blob || !blob[0]) return NULL;
  p = (const char*)blob;
  for (;;) {
    const char* eol = strstr(p, "\r\n");
    size_t n = eol ? (size_t)(eol - p) : strlen(p);
    if (n > 0) {
      char* line = (char*)malloc(n + 1);
      struct curl_slist* next;
      if (!line) { curl_slist_free_all(list); return NULL; }
      memcpy(line, p, n);
      line[n] = 0;
      next = curl_slist_append(list, line);
      free(line);
      if (!next) { curl_slist_free_all(list); return NULL; }
      list = next;
    }
    if (!eol) break;
    p = eol + 2;
  }
  return (void*)list;
}

void xiom_http_headers_free(void* list) {
  if (list) curl_slist_free_all((struct curl_slist*)list);
}
