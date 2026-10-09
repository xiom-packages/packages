/* probe_bridge.c -- probe-side FFI bridge for tests/probe_root_module.xi.
 * Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
 * SPDX-License-Identifier: MIT OR Apache-2.0
 *
 * The v0.64.2 toolchain ships only xiom_alloc in its runtime; the remaining
 * xiom_* FFI bridge symbols declared by packages/xiom-http/http.xi are not
 * provided anywhere, so this harness bridge supplies them. xiom_free_ptr and
 * xiom_free_cstr are REAL libc frees, not no-ops, so an allocation freed more
 * than once (the setup_common_options p1 double-free removed in the 0.1.3
 * pass) is not silently tolerated at runtime.
 *
 * libcurl is stubbed deterministically (the probe stays offline), but the stub
 * is FAITHFUL to libcurl's variadic setopt ABI since the 0.1.4 fix pass: for
 * CURLOPTTYPE_LONG options the third argument is the long VALUE itself, read
 * from the register -- never dereferenced. The stub reads it that way and
 * rejects implausible values with CURLE_BAD_FUNCTION_ARGUMENT (43). The old
 * make_ptr_value bug (an 8-byte heap pointer where libcurl reads a `long`)
 * therefore fails this probe: the value is a heap address, so TIMEOUT etc.
 * do not match and setup_common_options returns an error. STRINGPOINT and
 * OBJECTPOINT options (URL, USERAGENT, POSTFIELDS, CUSTOMREQUEST, WRITEDATA,
 * HEADERDATA, ...) keep passing real pointers untouched.
 */
#include <stdint.h>
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

/* Expected values pinned by http.xi (SPEC documents 30s/10s/64 KiB timeouts
 * and buffer). A heap pointer fed in as the "long" cannot match these. */
static int stub_long_option_ok(long long option, long long value) {
  switch (option) {
    case 52: return value == 1;      /* CURLOPT_FOLLOWLOCATION */
    case 13: return value == 30;     /* CURLOPT_TIMEOUT */
    case 78: return value == 10;     /* CURLOPT_CONNECTTIMEOUT */
    case 99: return value == 1;      /* CURLOPT_NOSIGNAL */
    case 98: return value == 65536;  /* CURLOPT_BUFFERSIZE */
    case 47: return value == 1;      /* CURLOPT_POST */
    case 60: return value >= 0;      /* CURLOPT_POSTFIELDSIZE (any non-negative length) */
    default: return 1;               /* not one of the stubbed LONG options */
  }
}

void* curl_easy_init(void) { return malloc(16); }

int curl_easy_setopt(void* h, long long option, const void* value) {
  (void)h;
  /* Variadic ABI: for LONG options libcurl reads va_arg(param, long) -- the
   * register/stack slot as an integer value, NOT a dereference. */
  long v = (long)(intptr_t)value;
  if (!stub_long_option_ok(option, (long long)v)) {
    return 43; /* CURLE_BAD_FUNCTION_ARGUMENT */
  }
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
