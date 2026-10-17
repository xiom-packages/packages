/* probe_openblas_shim.c -- probe-local real-library shim for
 * tests/probe_real_openblas.xi.
 * Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
 * SPDX-License-Identifier: MIT OR Apache-2.0
 *
 * NOT part of scripts/port.ps1 (the conformance suite stays offline via
 * bridge/openblas_bridge.c). This shim is the real leg: it detects and
 * loads a system OpenBLAS at runtime and exposes plain extern "C" entry
 * points the XIOM probe calls directly.
 *
 * Why a C shim: calling a dlsym/GetProcAddress address through an XIOM
 * fn-pointer works for integer returns but corrupts Float64 returns on
 * the v0.64.5 toolchain (verified: cos via pointer != cos via extern).
 * The shim performs the real cblas_* calls in C (int32 blasint ABI) and
 * returns doubles over a direct extern call, which is reliable.
 *
 * Runtime detection order (first candidate that loads AND exports both
 * cblas_ddot and cblas_dgemm wins):
 *   1. XIOM_OPENBLAS_LIB environment variable (explicit override);
 *   2. standard install locations (see the candidate table below);
 *   3. bare sonames -- left to the OS loader search order, which covers
 *      PATH entries on Windows and ld.so paths + LD_LIBRARY_PATH on POSIX.
 *
 * openblas64_ is the ILP64 variant (64-bit blasint); this probe calls
 * cblas_* with the standard LP64 int32 ABI and a 2x2 exercise, which is
 * numerically safe there, but large-N correctness with ILP64 is out of
 * scope (documented limitation).
 *
 * Probe command (from the package directory; --c-source needs the absolute
 * path because clang links from a scratch working directory):
 *   xiom --run tests\probe_real_openblas.xi --c-source <pkg>\tests\probe_openblas_shim.c
 *
 * xiom_probe_open() returns:
 *   1 = loaded (cblas_ddot + cblas_dgemm resolved)
 *   2 = a library loaded but does not export the required cblas_ symbols
 *       (loud ABI mismatch -- not a clean skip)
 *   0 = nothing found (clean skip)
 */

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#else
#include <dlfcn.h>
#endif

typedef double (*oblas_ddot_f)(int32_t, const double*, int32_t, const double*, int32_t);
typedef void (*oblas_dgemm_f)(int32_t, int32_t, int32_t, int32_t, int32_t, int32_t,
                              double, const double*, int32_t, const double*, int32_t,
                              double, double*, int32_t);

static void* g_handle = 0;
static oblas_ddot_f g_ddot = 0;
static oblas_dgemm_f g_dgemm = 0;
static char g_path[1024];
static long long g_path_len = -1;
static int g_loaded_any = 0;

static void* oblas_load_lib(const char* path) {
#ifdef _WIN32
  return (void*)LoadLibraryA(path);
#else
  return dlopen(path, RTLD_NOW | RTLD_LOCAL);
#endif
}

static void* oblas_load_sym(void* h, const char* name) {
#ifdef _WIN32
  return (void*)(intptr_t)GetProcAddress((HMODULE)h, name);
#else
  return dlsym(h, name);
#endif
}

static void oblas_close_lib(void* h) {
#ifdef _WIN32
  FreeLibrary((HMODULE)h);
#else
  dlclose(h);
#endif
}

/* Try one candidate: open, resolve both entry points, keep on success. */
static int oblas_try(const char* path) {
  if (path == 0 || path[0] == 0) return 0;
  void* h = oblas_load_lib(path);
  if (h == 0) return 0;
  g_loaded_any = 1;
  {
    size_t plen = strlen(path);
    if (plen > sizeof(g_path) - 1) plen = sizeof(g_path) - 1;
    memcpy(g_path, path, plen);
    g_path[plen] = 0;
    g_path_len = (long long)plen;
  }
  oblas_ddot_f ddot = (oblas_ddot_f)oblas_load_sym(h, "cblas_ddot");
  oblas_dgemm_f dgemm = (oblas_dgemm_f)oblas_load_sym(h, "cblas_dgemm");
  if (ddot == 0 || dgemm == 0) {
    oblas_close_lib(h);
    return 0;
  }
  g_handle = h;
  g_ddot = ddot;
  g_dgemm = dgemm;
  return 1;
}

long long xiom_probe_open(void) {
  if (g_handle != 0) return 1;

  const char* env = getenv("XIOM_OPENBLAS_LIB");
  if (oblas_try(env)) return 1;

#ifdef _WIN32
  static const char* kCandidates[] = {
    "C:\\OpenBLAS\\lib\\libopenblas.dll",
    "C:\\OpenBLAS\\bin\\libopenblas.dll",
    "C:\\OpenBLAS\\libopenblas.dll",
    "C:\\Program Files\\OpenBLAS\\lib\\libopenblas.dll",
    "C:\\Program Files\\OpenBLAS\\bin\\libopenblas.dll",
    "C:\\msys64\\mingw64\\bin\\libopenblas.dll",
    "C:\\tools\\msys64\\mingw64\\bin\\libopenblas.dll",
    "C:\\ProgramData\\chocolatey\\bin\\libopenblas.dll",
    /* bare names: OS loader search order (application dir, system dirs, PATH) */
    "libopenblas.dll",
    "openblas64_.dll",
    "openblas.dll",
  };
#else
  static const char* kCandidates[] = {
    "/usr/local/lib/libopenblas.so",
    "/usr/lib/libopenblas.so",
    "/usr/lib/x86_64-linux-gnu/libopenblas.so",
    "/opt/OpenBLAS/lib/libopenblas.so",
    /* bare sonames: ld.so cache + LD_LIBRARY_PATH search order */
    "libopenblas.so",
    "libopenblas.so.0",
  };
#endif

  {
    size_t n = sizeof(kCandidates) / sizeof(kCandidates[0]);
    size_t i = 0;
    for (i = 0; i < n; i = i + 1) {
      if (oblas_try(kCandidates[i])) return 1;
    }
  }

  if (g_loaded_any) return 2;
  return 0;
}

/* Copy the found library path into the caller's buffer; returns the full
 * path length (bytes, no NUL) or -1 when nothing was loaded. */
long long xiom_probe_path(unsigned char* dst, long long cap) {
  if (g_path_len < 0) return -1;
  if (dst == 0 || cap <= 0) return g_path_len;
  {
    long long n = g_path_len;
    if (n > cap) n = cap;
    memcpy(dst, g_path, (size_t)n);
  }
  return g_path_len;
}

/* Real cblas_ddot over the loaded library (incx = incy = 1). */
double xiom_probe_ddot(long long n, const double* x, const double* y) {
  if (g_ddot == 0 || x == 0 || y == 0) return 0.0;
  if (n <= 0 || n > 2147483647LL) return 0.0;
  return g_ddot((int32_t)n, x, 1, y, 1);
}

/* Real row-major C = A(m x k) * B(k x n) via cblas_dgemm.
 * Returns 0 on success, -1 not loaded, -2 bad argument, -3 dimension out
 * of int32 range. */
long long xiom_probe_dgemm(long long m, long long k, long long n,
                           const double* a, const double* b, double* c) {
  if (g_dgemm == 0) return -1;
  if (a == 0 || b == 0 || c == 0) return -2;
  if (m <= 0 || k <= 0 || n <= 0) return -2;
  if (m > 2147483647LL || k > 2147483647LL || n > 2147483647LL) return -3;
  /* CblasRowMajor = 101, CblasNoTrans = 111. Row-major leading dims:
   * lda = k, ldb = n, ldc = n. */
  g_dgemm(101, 111, 111, (int32_t)m, (int32_t)n, (int32_t)k,
          1.0, a, (int32_t)k, b, (int32_t)n, 0.0, c, (int32_t)n);
  return 0;
}
