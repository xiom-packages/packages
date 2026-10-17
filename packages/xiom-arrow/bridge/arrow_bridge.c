/* arrow_bridge.c -- link bridge + real-library loader for xiom.arrow.
 * Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
 * SPDX-License-Identifier: MIT OR Apache-2.0
 *
 * Two legs in one file (see SPEC.md "Bridge / loader"):
 *
 * LEG 1 -- offline conformance stubs (deterministic; allocates nothing):
 *   The 16 extern "C" entry points declared in src/arrow.xi. Phase 1
 *   behavior mirrors the xiom.numpy Phase-1 bridge:
 *      0  = Arrow runtime unavailable (safe wrappers collapse <= 0 to Err)
 *     -1  = invalid argument (null pointer, negative length, n_buffers > 3,
 *           negative n_columns)
 *   Accessors return documented neutral values (0); void entry points are
 *   safe no-ops. No libarrow header or binary is needed to build or run
 *   the conformance suite (port.args.json links this file only).
 *   Phase 2 replaces the creation/accessor bodies 1:1 with Arrow C++
 *   (arrow/c/bridge.h ImportArray/ExportArray) behind the same 16 symbols.
 *
 * LEG 2 -- real-library loader + Arrow C Data Interface boundary (used
 *   only by tests/probe_real_libarrow.xi; never by the suite):
 *   xiom_arrow_lib_probe() detects and loads the real Arrow runtime --
 *   libarrow.dll / arrow.dll on Windows, libarrow.so[.NNNN] /
 *   libarrow[.NNNN].dylib on POSIX -- from XIOM_ARROW_LIB / ARROW_HOME,
 *   PATH, Python site-packages (pyarrow ships libarrow.dll), vcpkg and
 *   standard library directories. xiom_arrow_cdi_layout_check() and
 *   xiom_arrow_cdi_roundtrip() exercise the pinned Arrow C Data
 *   Interface struct boundary: a real producer-side (ArrowArray,
 *   ArrowSchema) pair is built, consumed into a plain int64 column
 *   (validity bitmap + data buffer), released, and the release contract
 *   verified (release pointer NULLed after the call, second call safe).
 *
 * C Data Interface layout provenance: struct ArrowSchema / struct
 * ArrowArray below transcribe apache/arrow cpp/src/arrow/c/abi.h
 * (Apache-2.0, stable public ABI). Sizes pinned for 64-bit targets:
 * ArrowSchema = 72 bytes, ArrowArray = 80 bytes (checked at runtime).
 *
 * ABI: XIOM Int is 64-bit; every entry point uses (long long, ...) so it
 * matches the extern "C" declarations in src/arrow.xi exactly. No non-CRT
 * link dependency is introduced (no version.lib; LoadLibraryA/dlopen only).
 */

#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

#if defined(_WIN32)
#include <windows.h>
typedef HMODULE xar_lib_t;
static xar_lib_t xar_dlopen(const char* name) { return LoadLibraryA(name); }
static void xar_dlclose(xar_lib_t h) { if (h) FreeLibrary(h); }
#else
#include <dlfcn.h>
#include <dirent.h>
typedef void* xar_lib_t;
static xar_lib_t xar_dlopen(const char* name) { return dlopen(name, RTLD_NOW | RTLD_LOCAL); }
static void xar_dlclose(xar_lib_t h) { if (h) dlclose(h); }
#endif

/* =====================================================================
 * LEG 1 -- the 16 conformance entry points (stub-safe, deterministic)
 * ===================================================================== */

long long arrow_array_create(long long length, long long n_buffers) {
  if (length < 0) return -1;
  if (n_buffers < 0 || n_buffers > 3) return -1;
  return 0; /* Phase 1: Arrow runtime unavailable. */
}

void arrow_array_free(long long arr) {
  (void)arr; /* No storage exists in Phase 1; safe no-op for any handle. */
}

long long arrow_array_get_length(long long arr) {
  (void)arr;
  return 0; /* Neutral value: no storage exists in Phase 1. */
}

long long arrow_array_get_null_count(long long arr) {
  (void)arr;
  return 0;
}

long long arrow_array_get_offset(long long arr) {
  (void)arr;
  return 0;
}

long long arrow_array_get_n_buffers(long long arr) {
  (void)arr;
  return 0;
}

long long arrow_array_get_buffer(long long arr, long long index) {
  (void)arr;
  (void)index;
  return 0; /* Null buffer pointer: no storage exists in Phase 1. */
}

long long arrow_array_get_n_children(long long arr) {
  (void)arr;
  return 0;
}

long long arrow_array_get_child(long long arr, long long index) {
  (void)arr;
  (void)index;
  return 0; /* Null child pointer: no storage exists in Phase 1. */
}

long long arrow_schema_create(const char* format, const char* name) {
  if (format == 0 || format[0] == '\0') return -1;
  if (name == 0) return -1;
  return 0; /* Phase 1: Arrow runtime unavailable. */
}

void arrow_schema_free(long long schema) {
  (void)schema; /* Safe no-op for any handle. */
}

long long arrow_schema_get_format(long long schema) {
  (void)schema;
  return 0; /* Null pointer: no storage exists in Phase 1. */
}

long long arrow_schema_get_name(long long schema) {
  (void)schema;
  return 0;
}

long long arrow_record_batch_create(long long schema, long long n_columns, long long columns) {
  if (schema == 0) return -1;
  if (n_columns < 0) return -1;
  if (columns == 0) return -1;
  return 0; /* Phase 1: Arrow runtime unavailable. */
}

long long arrow_record_batch_get_column(long long batch, long long index) {
  (void)batch;
  (void)index;
  return 0;
}

long long arrow_record_batch_get_schema(long long batch) {
  (void)batch;
  return 0;
}

/* Additive Phase-2 surface (declared in src/arrow.xi, implemented for real
 * by bridge/arrow_real.cpp). The offline leg keeps the same validation and
 * reports the backend unavailable: 0 = no handle, -1 = invalid argument,
 * 0 = no released struct (release entry points). */

long long arrow_schema_create_struct(long long names, long long formats,
                                     long long n_columns) {
  if (names == 0 || formats == 0 || n_columns <= 0) return -1;
  return 0; /* Phase 1: Arrow runtime unavailable. */
}

long long arrow_array_from_int64(long long values, long long length) {
  if (values == 0 || length <= 0) return -1;
  return 0; /* Phase 1: Arrow runtime unavailable. */
}

long long arrow_array_from_float64(long long values, long long length) {
  if (values == 0 || length <= 0) return -1;
  return 0; /* Phase 1: Arrow runtime unavailable. */
}

long long arrow_record_batch_export(long long batch, long long out_schema,
                                    long long out_array) {
  if (batch == 0 || out_schema == 0 || out_array == 0) return -1;
  return 0; /* Phase 1: no batch storage to export. */
}

long long arrow_record_batch_import(long long schema_slot,
                                    long long array_slot) {
  if (schema_slot == 0 || array_slot == 0) return -1;
  return 0; /* Phase 1: Arrow runtime unavailable. */
}

long long arrow_schema_release(long long schema_slot) {
  if (schema_slot == 0) return -1;
  return 0; /* Phase 1: nothing was ever exported. */
}

long long arrow_array_release(long long array_slot) {
  if (array_slot == 0) return -1;
  return 0; /* Phase 1: nothing was ever exported. */
}

long long arrow_backend_available(void) {
  return 0; /* Phase 1: real Arrow C++ backend not linked. */
}

long long arrow_backend_version(void) {
  return 0; /* No version pointer: backend unavailable. */
}

/* =====================================================================
 * LEG 2 -- real-library loader
 * ===================================================================== */

static xar_lib_t g_lib = 0;
static int g_probe_state = 0;      /* 0 = not probed, 1 = loaded, 2 = absent */
static int g_candidates_tried = 0;
static char g_lib_name[256] = {0}; /* candidate name that loaded */
static char g_lib_path[1024] = {0};
static char g_lib_version[64] = {0};

static int xar_try(const char* candidate) {
  xar_lib_t h;
  if (candidate == 0 || candidate[0] == '\0') return 0;
  g_candidates_tried += 1;
  if (g_candidates_tried > 512) return 0; /* bounded scan */
  h = xar_dlopen(candidate);
  if (h == 0) return 0;
  g_lib = h;
  snprintf(g_lib_name, sizeof(g_lib_name), "%s", candidate);
#if defined(_WIN32)
  {
    char mod[1024];
    DWORD n = GetModuleFileNameA(h, mod, (DWORD)sizeof(mod));
    if (n > 0 && n < sizeof(mod)) {
      snprintf(g_lib_path, sizeof(g_lib_path), "%s", mod);
      /* pyarrow wheel layout: <site-packages>\pyarrow\libarrow.dll */
      if (strstr(mod, "site-packages") != 0 && strstr(mod, "pyarrow") != 0) {
        snprintf(g_lib_version, sizeof(g_lib_version), "pyarrow-bundled");
      }
    }
  }
#else
  snprintf(g_lib_path, sizeof(g_lib_path), "%s", candidate);
  {
    /* libarrow.so.2100 -> 21.0.0 (soname suffix is major*100+minor). */
    const char* dot = strrchr(candidate, '.');
    if (dot != 0) {
      long v = atol(dot + 1);
      if (v >= 100) snprintf(g_lib_version, sizeof(g_lib_version), "%ld.0.0", v / 100);
    }
  }
#endif
  return 1;
}

#if defined(_WIN32)
static int xar_try_dir(const char* dir, const char* names[], int n_names) {
  int i;
  if (dir == 0 || dir[0] == '\0') return 0;
  for (i = 0; i < n_names; i++) {
    char buf[1024];
    snprintf(buf, sizeof(buf), "%s\\%s", dir, names[i]);
    if (xar_try(buf)) return 1;
  }
  return 0;
}

static int xar_try_glob(const char* pattern) {
  /* FindFirstFileA supports wildcards in any path component, which is how
   * the Python site-packages layouts ("Python*\Lib\site-packages\...")
   * are discovered without hard-coding interpreter versions. */
  WIN32_FIND_DATAA fd;
  HANDLE h = FindFirstFileA(pattern, &fd);
  int found = 0;
  if (h == INVALID_HANDLE_VALUE) return 0;
  do {
    if ((fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) == 0) {
      char buf[1024];
      const char* slash = strrchr(pattern, '\\');
      size_t dirlen = slash ? (size_t)(slash - pattern) : 0;
      snprintf(buf, sizeof(buf), "%.*s\\%s", (int)dirlen, pattern, fd.cFileName);
      if (xar_try(buf)) { found = 1; break; }
    }
  } while (FindNextFileA(h, &fd));
  FindClose(h);
  return found;
}

static int xar_scan(void) {
  static const char* names[] = { "libarrow.dll", "arrow.dll" };
  const char* env;
  char buf[1024];
  DWORD len;

  env = getenv("XIOM_ARROW_LIB");
  if (env != 0 && env[0] != '\0') {
    if (xar_try(env)) return 1;
    if (xar_try_dir(env, names, 2)) return 1;
  }
  env = getenv("ARROW_HOME");
  if (env != 0 && env[0] != '\0') {
    snprintf(buf, sizeof(buf), "%s\\bin", env);
    if (xar_try_dir(buf, names, 2)) return 1;
  }
  /* Bare names: Windows loader search order (app dir, System32, Windows,
   * cwd, PATH) covers PATH without string surgery. */
  if (xar_try("libarrow.dll")) return 1;
  if (xar_try("arrow.dll")) return 1;

  len = GetEnvironmentVariableA("SystemRoot", buf, sizeof(buf));
  if (len > 0 && len < sizeof(buf)) {
    snprintf(buf + len, sizeof(buf) - len, "\\System32");
    if (xar_try_dir(buf, names, 2)) return 1;
  }
  env = getenv("LOCALAPPDATA");
  if (env != 0 && env[0] != '\0') {
    snprintf(buf, sizeof(buf), "%s\\Programs\\Python\\*\\Lib\\site-packages\\pyarrow\\libarrow.dll", env);
    if (xar_try_glob(buf)) return 1;
    snprintf(buf, sizeof(buf), "%s\\Programs\\Python\\*\\Lib\\site-packages\\pyarrow\\arrow.dll", env);
    if (xar_try_glob(buf)) return 1;
  }
  if (xar_try_glob("C:\\Program Files\\Python*\\Lib\\site-packages\\pyarrow\\libarrow.dll")) return 1;
  env = getenv("VCPKG_ROOT");
  if (env != 0 && env[0] != '\0') {
    snprintf(buf, sizeof(buf), "%s\\installed\\x64-windows\\bin", env);
    if (xar_try_dir(buf, names, 2)) return 1;
  }
  if (xar_try_dir("C:\\vcpkg\\installed\\x64-windows\\bin", names, 2)) return 1;
  return 0;
}
#else
static int xar_try_dir(const char* dir, const char* names[], int n_names) {
  int i;
  if (dir == 0 || dir[0] == '\0') return 0;
  for (i = 0; i < n_names; i++) {
    char buf[1024];
    snprintf(buf, sizeof(buf), "%s/%s", dir, names[i]);
    if (xar_try(buf)) return 1;
  }
  return 0;
}

static int xar_try_scan_dir(const char* dir) {
  /* PATH entries and standard dirs: match libarrow.so* / libarrow*.dylib. */
  DIR* d;
  struct dirent* e;
  if (dir == 0 || dir[0] == '\0') return 0;
  d = opendir(dir);
  if (d == 0) return 0;
  while ((e = readdir(d)) != 0) {
    if (strncmp(e->d_name, "libarrow", 8) != 0) continue;
    if (strstr(e->d_name, ".so") == 0 && strstr(e->d_name, ".dylib") == 0) continue;
    {
      char buf[1024];
      snprintf(buf, sizeof(buf), "%s/%s", dir, e->d_name);
      if (xar_try(buf)) { closedir(d); return 1; }
    }
  }
  closedir(d);
  return 0;
}

static int xar_scan(void) {
  static const char* names[] = { "libarrow.so", "libarrow.dylib" };
  static const char* dirs[] = {
    "/usr/lib", "/usr/lib/x86_64-linux-gnu", "/usr/lib/aarch64-linux-gnu",
    "/usr/local/lib", "/opt/homebrew/lib", "/usr/local/opt/arrow/lib", 0 };
  const char* env;
  const char* path;
  char buf[1024];
  int i;

  env = getenv("XIOM_ARROW_LIB");
  if (env != 0 && env[0] != '\0') {
    if (xar_try(env)) return 1;
    if (xar_try_dir(env, names, 2)) return 1;
    if (xar_try_scan_dir(env)) return 1;
  }
  env = getenv("ARROW_HOME");
  if (env != 0 && env[0] != '\0') {
    snprintf(buf, sizeof(buf), "%s/lib", env);
    if (xar_try_dir(buf, names, 2)) return 1;
  }
  if (xar_try("libarrow.so")) return 1;
  if (xar_try("libarrow.dylib")) return 1;
  /* Versioned sonames without a dev symlink: libarrow.so.800..2100. */
  for (i = 2100; i >= 800; i -= 100) {
    snprintf(buf, sizeof(buf), "libarrow.so.%d", i);
    if (xar_try(buf)) return 1;
    snprintf(buf, sizeof(buf), "libarrow.%d.dylib", i);
    if (xar_try(buf)) return 1;
  }
  path = getenv("PATH");
  if (path != 0) {
    char scan[4096];
    snprintf(scan, sizeof(scan), "%s", path);
    {
      char* tok = strtok(scan, ":");
      int guard = 0;
      while (tok != 0 && guard < 64) {
        if (xar_try_scan_dir(tok)) return 1;
        tok = strtok(0, ":");
        guard += 1;
      }
    }
  }
  for (i = 0; dirs[i] != 0; i++) {
    if (xar_try_dir(dirs[i], names, 2)) return 1;
    if (xar_try_scan_dir(dirs[i])) return 1;
  }
  return 0;
}
#endif

long long xiom_arrow_lib_probe(void) {
  if (g_probe_state == 0) {
    if (xar_scan()) {
      g_probe_state = 1;
    } else {
      g_probe_state = 2;
    }
  }
  return g_probe_state == 1 ? 1 : 0;
}

long long xiom_arrow_lib_candidates(void) {
  return (long long)g_candidates_tried;
}

const char* xiom_arrow_lib_name(void) {
  return g_lib_name;
}

const char* xiom_arrow_lib_path(void) {
  return g_lib_path;
}

const char* xiom_arrow_lib_version(void) {
  return g_lib_version;
}

long long xiom_arrow_lib_unload(void) {
  if (g_lib != 0) {
    xar_dlclose(g_lib);
    g_lib = 0;
    g_probe_state = 0;
  }
  return 0;
}

/* =====================================================================
 * LEG 2 -- Arrow C Data Interface struct boundary
 * =====================================================================
 * struct ArrowSchema / struct ArrowArray transcribe the stable golden
 * C Data Interface ABI (arrow/c/abi.h). Layout pinned to 64-bit:
 *   ArrowSchema: 6 pointers + 3 int64 + 1 fn pointer = 72 bytes
 *   ArrowArray : 5 int64 + 4 pointers + 1 fn pointer = 80 bytes
 */

typedef struct ArrowSchema {
  const char* format;
  const char* name;
  const char* metadata;
  int64_t flags;
  int64_t n_children;
  struct ArrowSchema** children;
  struct ArrowSchema* dictionary;
  void (*release)(struct ArrowSchema*);
  void* private_data;
} ArrowSchema;

typedef struct ArrowArray {
  int64_t length;
  int64_t null_count;
  int64_t offset;
  int64_t n_buffers;
  int64_t n_children;
  const void** buffers;
  struct ArrowArray** children;
  struct ArrowArray* dictionary;
  void (*release)(struct ArrowArray*);
  void* private_data;
} ArrowArray;

#define XAR_FLAG_NULLABLE 2

static char g_cdi_detail[512] = {0};

static void xar_cdi_note(const char* msg) {
  snprintf(g_cdi_detail, sizeof(g_cdi_detail), "%s", msg);
}

long long xiom_arrow_cdi_layout_check(void) {
  if (sizeof(void*) != 8) {
    xar_cdi_note("64-bit layout check skipped: pointer size is not 8");
    return 2;
  }
  if (sizeof(ArrowSchema) != 72) {
    snprintf(g_cdi_detail, sizeof(g_cdi_detail),
             "ArrowSchema size %u != 72", (unsigned)sizeof(ArrowSchema));
    return 1;
  }
  if (sizeof(ArrowArray) != 80) {
    snprintf(g_cdi_detail, sizeof(g_cdi_detail),
             "ArrowArray size %u != 80", (unsigned)sizeof(ArrowArray));
    return 1;
  }
  if (offsetof(ArrowArray, buffers) != 40) {
    xar_cdi_note("ArrowArray.buffers offset != 40");
    return 1;
  }
  if (offsetof(ArrowSchema, release) != 56) {
    xar_cdi_note("ArrowSchema.release offset != 56");
    return 1;
  }
  xar_cdi_note("ArrowSchema=72 ArrowArray=80, field offsets pinned");
  return 0;
}

/* Round-trip fixture state: the producer allocates the structs and their
 * storage; the release callbacks mirror the C Data Interface contract
 * (free owned buffers, NULL the release pointer so a second call is a
 * documented no-op). The harness keeps the struct memory so it can verify
 * the post-release state, which is exactly what consumers (pyarrow)
 * depend on when they take ownership of the release call. */

typedef struct XarFixture {
  int magic;
  int array_released;
  int schema_released;
  int release_nulled;
  int64_t* values;
  uint8_t* validity;
  const void** buffers;
} XarFixture;

#define XAR_FIXTURE_MAGIC 0x58415231

static void xar_array_release(struct ArrowArray* arr) {
  XarFixture* fx;
  if (arr == 0) return;
  fx = (XarFixture*)arr->private_data;
  if (fx != 0 && fx->magic == XAR_FIXTURE_MAGIC) {
    fx->array_released = 1;
    free(fx->values);
    free(fx->validity);
    free(fx->buffers);
    fx->values = 0;
    fx->validity = 0;
    fx->buffers = 0;
  }
  arr->release = 0;
  if (fx != 0 && fx->magic == XAR_FIXTURE_MAGIC && fx->schema_released) {
    fx->release_nulled = 1;
    fx->magic = 0;
  }
}

static void xar_schema_release(struct ArrowSchema* sch) {
  XarFixture* fx;
  if (sch == 0) return;
  fx = (XarFixture*)sch->private_data;
  if (fx != 0 && fx->magic == XAR_FIXTURE_MAGIC) {
    fx->schema_released = 1;
  }
  sch->release = 0;
  if (fx != 0 && fx->magic == XAR_FIXTURE_MAGIC && fx->array_released) {
    fx->release_nulled = 1;
    fx->magic = 0;
  }
}

/* Build a real producer-side pair: one int64 column "x" of 5 values
 * [42, -7, null, 123456789, -1]; validity bitmap 0b11111011. */
long long xiom_arrow_cdi_roundtrip(void) {
  XarFixture* fx = (XarFixture*)calloc(1, sizeof(XarFixture));
  ArrowArray* arr;
  ArrowSchema* sch;
  static const int64_t expected[5] = { 42, -7, 0, 123456789, -1 };
  int i;
  long long rc = 0;

  if (fx == 0) { xar_cdi_note("fixture allocation failed"); return 20; }
  fx->magic = XAR_FIXTURE_MAGIC;

  fx->values = (int64_t*)malloc(sizeof(int64_t) * 5);
  fx->validity = (uint8_t*)calloc(1, 1);
  fx->buffers = (const void**)calloc(2, sizeof(void*));
  arr = (ArrowArray*)calloc(1, sizeof(ArrowArray));
  sch = (ArrowSchema*)calloc(1, sizeof(ArrowSchema));
  if (fx->values == 0 || fx->validity == 0 || fx->buffers == 0 || arr == 0 || sch == 0) {
    xar_cdi_note("buffer allocation failed");
    free(fx->values); free(fx->validity); free(fx->buffers);
    free(arr); free(sch); free(fx);
    return 20;
  }

  for (i = 0; i < 5; i++) fx->values[i] = expected[i];
  fx->validity[0] = 0xFB; /* bits 0,1,3,4 valid; bit 2 null */

  fx->buffers[0] = fx->validity;
  fx->buffers[1] = fx->values;

  arr->length = 5;
  arr->null_count = 1;
  arr->offset = 0;
  arr->n_buffers = 2;
  arr->n_children = 0;
  arr->buffers = fx->buffers;
  arr->children = 0;
  arr->dictionary = 0;
  arr->release = xar_array_release;
  arr->private_data = fx;

  sch->format = "l"; /* C Data Interface format string: signed int64 */
  sch->name = "x";
  sch->metadata = 0;
  sch->flags = XAR_FLAG_NULLABLE;
  sch->n_children = 0;
  sch->children = 0;
  sch->dictionary = 0;
  sch->release = xar_schema_release;
  sch->private_data = fx;

  /* Consumer-side checks (the exact facts a pandas/pyarrow consumer
   * reads off the structs). */
  if (arr->length != 5 || arr->null_count != 1 || arr->offset != 0 || arr->n_buffers != 2) {
    xar_cdi_note("array header fields wrong");
    rc = 3;
  } else if (arr->buffers[0] == 0 || arr->buffers[1] == 0) {
    xar_cdi_note("buffer pointers null");
    rc = 4;
  } else if (strcmp(sch->format, "l") != 0 || strcmp(sch->name, "x") != 0 || sch->flags != XAR_FLAG_NULLABLE) {
    xar_cdi_note("schema format/name/flags wrong");
    rc = 5;
  } else {
    int64_t* vals = (int64_t*)arr->buffers[1];
    uint8_t* valid = (uint8_t*)arr->buffers[0];
    for (i = 0; i < 5; i++) {
      if (vals[i] != expected[i]) { xar_cdi_note("data value mismatch"); rc = 6; break; }
      {
        int bit = (valid[i / 8] >> (i % 8)) & 1;
        if (i == 2 && bit != 0) { xar_cdi_note("null bitmap bit 2 should be 0"); rc = 6; break; }
        if (i != 2 && bit != 1) { xar_cdi_note("validity bitmap wrong"); rc = 6; break; }
      }
    }
  }

  /* Release contract: first call releases storage and NULLs the pointer;
   * a second call after the NULL check is a documented no-op. */
  arr->release(arr);
  if (rc == 0 && arr->release != 0) { xar_cdi_note("array release pointer not NULLed"); rc = 7; }
  if (rc == 0 && !fx->array_released) { xar_cdi_note("array release callback not fired"); rc = 7; }
  sch->release(sch);
  if (rc == 0 && sch->release != 0) { xar_cdi_note("schema release pointer not NULLed"); rc = 7; }
  if (rc == 0 && !fx->schema_released) { xar_cdi_note("schema release callback not fired"); rc = 7; }
  if (rc == 0 && !fx->release_nulled) { xar_cdi_note("release-nulling completion flag missing"); rc = 7; }
  if (rc == 0 && (fx->values != 0 || fx->validity != 0 || fx->buffers != 0)) {
    xar_cdi_note("release callbacks did not free owned buffers");
    rc = 8;
  }

  free(arr);
  free(sch);
  free(fx);
  if (rc == 0) xar_cdi_note("int64 column x[5] null@2 produced, consumed, released");
  return rc;
}

const char* xiom_arrow_cdi_detail(void) {
  return g_cdi_detail;
}
