/* probe_bridge.c -- probe-side FFI bridge for tests/probe_root_module.xi.
 * Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
 * SPDX-License-Identifier: MIT OR Apache-2.0
 *
 * The v0.64.1 toolchain ships only xiom_alloc in its runtime; the remaining
 * xiom_* FFI bridge symbols declared by packages/xiom-http/http.xi are not
 * provided anywhere, so this harness bridge supplies them. xiom_free_ptr and
 * xiom_free_cstr are REAL libc frees, not no-ops, so an allocation freed more
 * than once (the setup_common_options p1 double-free removed in this pass)
 * is not silently tolerated at runtime.
 *
 * libcurl is stubbed deterministically: driving the real library through this
 * module is not possible on Win64 -- make_ptr_value passes an 8-byte heap
 * pointer where libcurl reads a `long` option value, so CURLOPT_TIMEOUT
 * rejects the garbage low 32 bits (measured: 500/500 nonzero returns on the
 * vcpkg libcurl build). The stub keeps the package's own helper chain
 * (perform -> getinfo -> error string) deterministic and offline; the closed
 * port URL is kept as the http_get argument.
 */
#include <stdlib.h>
#include <string.h>

/* xiom_alloc is provided by the XIOM runtime (malloc-backed); do not define
 * it here (duplicate symbol). */

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

/* --- Deterministic libcurl stub ---------------------------------------- */

void* curl_easy_init(void) { return malloc(16); }

int curl_easy_setopt(void* h, long long option, const void* value) {
  (void)h; (void)option; (void)value;
  return 0;
}

int curl_easy_perform(void* h) {
  (void)h;
  return 7; /* CURLE_COULDNT_CONNECT */
}

int curl_easy_getinfo(void* h, long long info, void* arg) {
  (void)h; (void)info;
  if (arg) *(long long*)arg = 0; /* HTTP response code 0 on a failed transfer */
  return 0;
}

void curl_easy_cleanup(void* h) { free(h); }

const char* curl_easy_strerror(long long code) {
  (void)code;
  return "Couldn't connect to server";
}
