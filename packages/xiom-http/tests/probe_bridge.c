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
 * HEADERDATA, CURLOPT_HTTPHEADER, ...) keep passing real pointers untouched.
 *
 * Since 0.1.8 the bridge also carries the custom-header path: a copy of the
 * xiom_http_headers_build / xiom_http_headers_free helpers (same splitting
 * code as bridge/xiom_http_shims.c) plus deterministic curl_slist stubs, so
 * http_request's header path links and runs offline. The probe copy of
 * xiom_http_headers_build additionally VALIDATES each split line ("Name: "
 * prefix required) and returns NULL on malformed input -- an offline pin of
 * the blob contract that the production shim leaves to libcurl.
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

/* --- Custom request headers (0.1.8) -------------------------------------
 * Probe copy of the shim helpers (bridge/xiom_http_shims.c). The splitter is
 * identical; additionally each split line must look like "Name: ..." or the
 * build fails (NULL) -- the offline pin described in the header comment.
 * The curl_slist stand-ins this copy calls are defined at the bottom. */

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
      if (!strstr(line, ": ")) { /* malformed blob line: fail loud */
        free(line);
        curl_slist_free_all(list);
        return NULL;
      }
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

/* --- Deterministic libcurl stub ---------------------------------------- */

/* Raw request-body capture (0.1.9 binary path). libcurl's POSTFIELDS pointer
 * is only valid until the transfer ends, so the stub copies the bytes when
 * POSTFIELDSIZE is set (libcurl reads exactly that many bytes, NUL included).
 * The raw-bytes probe reads the snapshot back through the two accessors at
 * the bottom, proving the FFI seam saw the exact caller bytes. */
static const unsigned char* stub_postfields = NULL;
static unsigned char stub_body_snapshot[4096];
static long long stub_body_len = -1;

long long xiom_probe_last_body_len(void) { return stub_body_len; }

long long xiom_probe_last_body_byte(long long off) {
  if (off < 0 || off >= stub_body_len) return -1;
  return (long long)stub_body_snapshot[off];
}

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
  /* STRINGPOINT/OBJECTPOINT sites pass real pointers; remember POSTFIELDS so
   * the adjacent POSTFIELDSIZE call can snapshot exactly `size` bytes. */
  if (option == 10015) { /* CURLOPT_POSTFIELDS */
    stub_postfields = (const unsigned char*)value;
    return 0;
  }
  /* Variadic ABI: for LONG options libcurl reads va_arg(param, long) -- the
   * register/stack slot as an integer value, NOT a dereference. */
  long v = (long)(intptr_t)value;
  if (option == 60) { /* CURLOPT_POSTFIELDSIZE */
    if (stub_postfields && v >= 0 && v <= (long)sizeof(stub_body_snapshot)) {
      memcpy(stub_body_snapshot, stub_postfields, (size_t)v);
      stub_body_len = (long long)v;
    } else {
      stub_body_len = -2; /* capture impossible: fail the probe assertion */
    }
  }
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

/* --- Deterministic curl_slist stand-ins (0.1.8 header path) ------------- */

struct curl_slist {
  struct curl_slist* next;
  char* line;
};

struct curl_slist* curl_slist_append(struct curl_slist* list, const char* s) {
  struct curl_slist* node;
  struct curl_slist* tail;
  char* copy;
  size_t n;
  if (!s) return NULL;
  node = (struct curl_slist*)malloc(sizeof(struct curl_slist));
  if (!node) return NULL;
  n = strlen(s);
  copy = (char*)malloc(n + 1);
  if (!copy) { free(node); return NULL; }
  memcpy(copy, s, n + 1);
  node->next = NULL;
  node->line = copy;
  if (!list) return node;
  tail = list;
  while (tail->next) tail = tail->next;
  tail->next = node;
  return list;
}

void curl_slist_free_all(struct curl_slist* list) {
  while (list) {
    struct curl_slist* next = list->next;
    free(list->line);
    free(list);
    list = next;
  }
}
