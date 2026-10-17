/* xiom.cublas -- runtime bridge over the NVIDIA cuBLAS library.
 * Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
 * SPDX-License-Identifier: MIT OR Apache-2.0
 *
 * NOTHING from NVIDIA is vendored or linked at build time.  The cuBLAS
 * runtime (the user's own CUDA Toolkit / pip-wheel installation) is loaded
 * at run time with LoadLibraryA/LoadLibraryExA, and every entry point is
 * resolved with GetProcAddress.  The driver library (nvcuda.dll, a system
 * component of any NVIDIA driver) supplies the CUDA context and the device
 * memory helpers used by the test path.
 *
 * Loader search (in order):
 *   1. an explicit directory (cublas_load_from): <dir>\cublas64_13.dll,
 *      cublas64_12.dll, cublas64_11.dll, cublas64_10.dll -- no bare-name
 *      fallback, so an absent directory is classified deterministically;
 *   2. XIOM_CUBLAS_DIR when set (cublas_load);
 *   3. the OS module search (bare sonames cublas64_13/12/11/10.dll).
 *
 * The explicit-path load uses LOAD_WITH_ALTERED_SEARCH_PATH so the sibling
 * dependency cublasLt64_12.dll resolves from the same directory.
 *
 * ABI: cublasStatus_t is int; cublasHandle_t/cudaStream_t are pointers;
 * all entry points use the stable _v2 names.  Opaque pointers cross the
 * XIOM ABI as int64_t values (handles) -- XIOM never dereferences them.
 *
 * Classification (kept in sync with cublas.xi):
 *   0 CUBLAS_LOAD_ABSENT    -- cuBLAS module not found        -> SKIP
 *   1 CUBLAS_LOAD_ABI       -- module found, entry points gone -> FAIL
 *   2 CUBLAS_LOAD_NO_DEVICE -- nvcuda missing / no CUDA device -> SKIP
 *   3 CUBLAS_LOAD_RUNTIME   -- context/step failure            -> FAIL
 *
 * All bridge state is process-global and single-threaded (the suite is
 * single-threaded; document any multi-threaded use as a new constraint).
 */

#include <windows.h>
#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include <stdlib.h>

#define CUBLASB_LOAD_ABSENT 0
#define CUBLASB_LOAD_ABI 1
#define CUBLASB_LOAD_NO_DEVICE 2
#define CUBLASB_LOAD_RUNTIME 3

#define CUBLASB_CUDA_SUCCESS 0
#define CUBLASB_CUDA_ERROR_NO_DEVICE 100

typedef int cublasStatus_t;
typedef void* cublasHandle_t;

typedef cublasStatus_t (*PFN_cublasCreate_v2)(cublasHandle_t* handle);
typedef cublasStatus_t (*PFN_cublasDestroy_v2)(cublasHandle_t handle);
typedef cublasStatus_t (*PFN_cublasSetStream_v2)(cublasHandle_t handle, void* stream);
typedef cublasStatus_t (*PFN_cublasGetVersion_v2)(cublasHandle_t handle, int* version);
typedef cublasStatus_t (*PFN_cublasSgemm_v2)(cublasHandle_t, int, int, int, int, int,
                                             const float*, const float*, int,
                                             const float*, int, const float*, float*, int);
typedef cublasStatus_t (*PFN_cublasDgemm_v2)(cublasHandle_t, int, int, int, int, int,
                                             const double*, const double*, int,
                                             const double*, int, const double*, double*, int);
typedef cublasStatus_t (*PFN_cublasSaxpy_v2)(cublasHandle_t, int, const float*,
                                             const float*, int, float*, int);
typedef cublasStatus_t (*PFN_cublasDaxpy_v2)(cublasHandle_t, int, const double*,
                                             const double*, int, double*, int);
typedef cublasStatus_t (*PFN_cublasSdot_v2)(cublasHandle_t, int, const float*, int,
                                            const float*, int, float*);
typedef cublasStatus_t (*PFN_cublasDdot_v2)(cublasHandle_t, int, const double*, int,
                                            const double*, int, double*);
typedef cublasStatus_t (*PFN_cublasSscal_v2)(cublasHandle_t, int, const float*, float*, int);
typedef cublasStatus_t (*PFN_cublasDscal_v2)(cublasHandle_t, int, const double*, double*, int);
typedef cublasStatus_t (*PFN_cublasSnrm2_v2)(cublasHandle_t, int, const float*, int, float*);
typedef cublasStatus_t (*PFN_cublasDnrm2_v2)(cublasHandle_t, int, const double*, int, double*);
typedef cublasStatus_t (*PFN_cublasSgemv_v2)(cublasHandle_t, int, int, int,
                                             const float*, const float*, int,
                                             const float*, int, const float*, float*, int);
typedef cublasStatus_t (*PFN_cublasDgemv_v2)(cublasHandle_t, int, int, int,
                                             const double*, const double*, int,
                                             const double*, int, const double*, double*, int);

typedef int (*PFN_cuInit)(unsigned int flags);
typedef int (*PFN_cuCtxCreate_v2)(void** pctx, unsigned int flags, int dev);
typedef int (*PFN_cuCtxDestroy_v2)(void* ctx);
typedef int (*PFN_cuMemAlloc_v2)(unsigned long long* dptr, unsigned long long bytesize);
typedef int (*PFN_cuMemFree_v2)(unsigned long long dptr);
typedef int (*PFN_cuMemcpyHtoD_v2)(unsigned long long dstDevice, const void* srcHost,
                                   unsigned long long byteCount);
typedef int (*PFN_cuMemcpyDtoH_v2)(void* dstHost, unsigned long long srcDevice,
                                   unsigned long long byteCount);

struct CublasApi {
  PFN_cublasCreate_v2 create;
  PFN_cublasDestroy_v2 destroy;
  PFN_cublasSetStream_v2 set_stream;
  PFN_cublasGetVersion_v2 get_version;
  PFN_cublasSgemm_v2 sgemm;
  PFN_cublasDgemm_v2 dgemm;
  PFN_cublasSaxpy_v2 saxpy;
  PFN_cublasDaxpy_v2 daxpy;
  PFN_cublasSdot_v2 sdot;
  PFN_cublasDdot_v2 ddot;
  PFN_cublasSscal_v2 sscal;
  PFN_cublasDscal_v2 dscal;
  PFN_cublasSnrm2_v2 snrm2;
  PFN_cublasDnrm2_v2 dnrm2;
  PFN_cublasSgemv_v2 sgemv;
  PFN_cublasDgemv_v2 dgemv;
};

struct CudaApi {
  PFN_cuInit init;
  PFN_cuCtxCreate_v2 ctx_create;
  PFN_cuCtxDestroy_v2 ctx_destroy;
  PFN_cuMemAlloc_v2 mem_alloc;
  PFN_cuMemFree_v2 mem_free;
  PFN_cuMemcpyHtoD_v2 memcpy_htod;
  PFN_cuMemcpyDtoH_v2 memcpy_dtoh;
};

static HMODULE g_mod;
static HMODULE g_cuda;
static void* g_ctx;
static int g_kind;
static int g_last_status;
static int g_last_driver;
static float g_last_f32;
static double g_last_f64;

static struct CublasApi g_api;
static struct CudaApi g_cu;

static const char* const k_cublas_names[] = {
    "cublas64_13.dll", "cublas64_12.dll", "cublas64_11.dll", "cublas64_10.dll"};
static const int k_cublas_name_count =
    (int)(sizeof(k_cublas_names) / sizeof(k_cublas_names[0]));

static void reset_state(void) {
  memset(&g_api, 0, sizeof(g_api));
  memset(&g_cu, 0, sizeof(g_cu));
  g_mod = NULL;
  g_cuda = NULL;
  g_ctx = NULL;
  g_kind = CUBLASB_LOAD_ABSENT;
  g_last_status = 0;
  g_last_driver = 0;
  g_last_f32 = 0.0f;
  g_last_f64 = 0.0;
}

static HMODULE load_from_dir(const char* dir) {
  char path[MAX_PATH];
  size_t dlen = strlen(dir);
  int sep;
  int i;
  if (dlen == 0 || dlen >= sizeof(path)) return NULL;
  sep = (dir[dlen - 1] == '\\' || dir[dlen - 1] == '/') ? 0 : 1;
  for (i = 0; i < k_cublas_name_count; i++) {
    size_t nlen = strlen(k_cublas_names[i]);
    if (dlen + (size_t)sep + nlen + 1 > sizeof(path)) continue;
    memcpy(path, dir, dlen);
    if (sep) path[dlen] = '\\';
    memcpy(path + dlen + (size_t)sep, k_cublas_names[i], nlen + 1);
    HMODULE m = LoadLibraryExA(path, NULL, LOAD_WITH_ALTERED_SEARCH_PATH);
    if (m != NULL) return m;
  }
  return NULL;
}

static HMODULE load_bare(void) {
  int i;
  for (i = 0; i < k_cublas_name_count; i++) {
    HMODULE m = LoadLibraryA(k_cublas_names[i]);
    if (m != NULL) return m;
  }
  return NULL;
}

static int resolve_cublas(void) {
  g_api.create = (PFN_cublasCreate_v2)(void*)GetProcAddress(g_mod, "cublasCreate_v2");
  g_api.destroy = (PFN_cublasDestroy_v2)(void*)GetProcAddress(g_mod, "cublasDestroy_v2");
  g_api.set_stream = (PFN_cublasSetStream_v2)(void*)GetProcAddress(g_mod, "cublasSetStream_v2");
  g_api.get_version = (PFN_cublasGetVersion_v2)(void*)GetProcAddress(g_mod, "cublasGetVersion_v2");
  g_api.sgemm = (PFN_cublasSgemm_v2)(void*)GetProcAddress(g_mod, "cublasSgemm_v2");
  g_api.dgemm = (PFN_cublasDgemm_v2)(void*)GetProcAddress(g_mod, "cublasDgemm_v2");
  g_api.saxpy = (PFN_cublasSaxpy_v2)(void*)GetProcAddress(g_mod, "cublasSaxpy_v2");
  g_api.daxpy = (PFN_cublasDaxpy_v2)(void*)GetProcAddress(g_mod, "cublasDaxpy_v2");
  g_api.sdot = (PFN_cublasSdot_v2)(void*)GetProcAddress(g_mod, "cublasSdot_v2");
  g_api.ddot = (PFN_cublasDdot_v2)(void*)GetProcAddress(g_mod, "cublasDdot_v2");
  g_api.sscal = (PFN_cublasSscal_v2)(void*)GetProcAddress(g_mod, "cublasSscal_v2");
  g_api.dscal = (PFN_cublasDscal_v2)(void*)GetProcAddress(g_mod, "cublasDscal_v2");
  g_api.snrm2 = (PFN_cublasSnrm2_v2)(void*)GetProcAddress(g_mod, "cublasSnrm2_v2");
  g_api.dnrm2 = (PFN_cublasDnrm2_v2)(void*)GetProcAddress(g_mod, "cublasDnrm2_v2");
  g_api.sgemv = (PFN_cublasSgemv_v2)(void*)GetProcAddress(g_mod, "cublasSgemv_v2");
  g_api.dgemv = (PFN_cublasDgemv_v2)(void*)GetProcAddress(g_mod, "cublasDgemv_v2");
  if (g_api.create == NULL || g_api.destroy == NULL || g_api.set_stream == NULL ||
      g_api.get_version == NULL || g_api.sgemm == NULL || g_api.dgemm == NULL ||
      g_api.saxpy == NULL || g_api.daxpy == NULL || g_api.sdot == NULL ||
      g_api.ddot == NULL || g_api.sscal == NULL || g_api.dscal == NULL ||
      g_api.snrm2 == NULL || g_api.dnrm2 == NULL || g_api.sgemv == NULL ||
      g_api.dgemv == NULL) {
    return 0;
  }
  return 1;
}

static int resolve_cuda(void) {
  g_cu.init = (PFN_cuInit)(void*)GetProcAddress(g_cuda, "cuInit");
  g_cu.ctx_create = (PFN_cuCtxCreate_v2)(void*)GetProcAddress(g_cuda, "cuCtxCreate_v2");
  g_cu.ctx_destroy = (PFN_cuCtxDestroy_v2)(void*)GetProcAddress(g_cuda, "cuCtxDestroy_v2");
  g_cu.mem_alloc = (PFN_cuMemAlloc_v2)(void*)GetProcAddress(g_cuda, "cuMemAlloc_v2");
  g_cu.mem_free = (PFN_cuMemFree_v2)(void*)GetProcAddress(g_cuda, "cuMemFree_v2");
  g_cu.memcpy_htod = (PFN_cuMemcpyHtoD_v2)(void*)GetProcAddress(g_cuda, "cuMemcpyHtoD_v2");
  g_cu.memcpy_dtoh = (PFN_cuMemcpyDtoH_v2)(void*)GetProcAddress(g_cuda, "cuMemcpyDtoH_v2");
  if (g_cu.init == NULL || g_cu.ctx_create == NULL || g_cu.ctx_destroy == NULL ||
      g_cu.mem_alloc == NULL || g_cu.mem_free == NULL || g_cu.memcpy_htod == NULL ||
      g_cu.memcpy_dtoh == NULL) {
    return 0;
  }
  return 1;
}

static int create_cuda_context(void) {
  int rc;
  g_cuda = LoadLibraryA("nvcuda.dll");
  if (g_cuda == NULL) {
    g_kind = CUBLASB_LOAD_NO_DEVICE;
    return 0;
  }
  if (!resolve_cuda()) {
    g_kind = CUBLASB_LOAD_ABI;
    return 0;
  }
  rc = g_cu.init(0);
  if (rc == CUBLASB_CUDA_ERROR_NO_DEVICE) {
    g_kind = CUBLASB_LOAD_NO_DEVICE;
    return 0;
  }
  if (rc != CUBLASB_CUDA_SUCCESS) {
    g_last_driver = rc;
    g_kind = CUBLASB_LOAD_RUNTIME;
    return 0;
  }
  rc = g_cu.ctx_create(&g_ctx, 0, 0);
  if (rc != CUBLASB_CUDA_SUCCESS) {
    g_last_driver = rc;
    g_kind = (rc == CUBLASB_CUDA_ERROR_NO_DEVICE) ? CUBLASB_LOAD_NO_DEVICE
                                                  : CUBLASB_LOAD_RUNTIME;
    return 0;
  }
  return 1;
}

int32_t cublasb_last_kind(void) {
  return g_kind;
}

int32_t cublasb_last_status(void) {
  return g_last_status;
}

int32_t cublasb_last_driver(void) {
  return g_last_driver;
}

float cublasb_last_f32(void) {
  return g_last_f32;
}

double cublasb_last_f64(void) {
  return g_last_f64;
}

/* Returns the module handle (>0) or 0.  An explicit directory is strict:
 * a missing file there never falls back to the OS search. */
int64_t cublasb_load(const char* explicit_dir) {
  HMODULE m = NULL;
  if (g_mod != NULL) return (int64_t)(intptr_t)g_mod;
  reset_state();
  if (explicit_dir != NULL && explicit_dir[0] != 0) {
    m = load_from_dir(explicit_dir);
  } else {
    const char* env = getenv("XIOM_CUBLAS_DIR");
    if (env != NULL && env[0] != 0) m = load_from_dir(env);
    if (m == NULL) m = load_bare();
  }
  if (m == NULL) {
    g_kind = CUBLASB_LOAD_ABSENT;
    return 0;
  }
  g_mod = m;
  if (!resolve_cublas()) {
    g_kind = CUBLASB_LOAD_ABI;
    FreeLibrary(g_mod);
    g_mod = NULL;
    return 0;
  }
  if (!create_cuda_context()) {
    FreeLibrary(g_mod);
    g_mod = NULL;
    if (g_cuda != NULL) {
      FreeLibrary(g_cuda);
      g_cuda = NULL;
    }
    return 0;
  }
  g_kind = CUBLASB_LOAD_RUNTIME;
  return (int64_t)(intptr_t)g_mod;
}

int32_t cublasb_unload(int64_t mod) {
  if (g_mod == NULL || (HMODULE)(intptr_t)mod != g_mod) return 1;
  FreeLibrary(g_mod);
  g_mod = NULL;
  if (g_ctx != NULL && g_cu.ctx_destroy != NULL) {
    g_cu.ctx_destroy(g_ctx);
    g_ctx = NULL;
  }
  if (g_cuda != NULL) {
    FreeLibrary(g_cuda);
    g_cuda = NULL;
  }
  memset(&g_api, 0, sizeof(g_api));
  memset(&g_cu, 0, sizeof(g_cu));
  return 0;
}

int64_t cublasb_create(int64_t mod) {
  cublasHandle_t h = NULL;
  cublasStatus_t st;
  if (g_mod == NULL || (HMODULE)(intptr_t)mod != g_mod || g_api.create == NULL) {
    g_last_status = 1;
    return 0;
  }
  st = g_api.create(&h);
  g_last_status = (int)st;
  if (st != 0) return 0;
  return (int64_t)(intptr_t)h;
}

int32_t cublasb_destroy(int64_t h) {
  cublasStatus_t st;
  if (g_api.destroy == NULL) return 1;
  st = g_api.destroy((cublasHandle_t)(intptr_t)h);
  g_last_status = (int)st;
  return (int32_t)st;
}

int32_t cublasb_get_version(int64_t h) {
  cublasStatus_t st;
  int version = 0;
  if (g_api.get_version == NULL) return -1;
  st = g_api.get_version((cublasHandle_t)(intptr_t)h, &version);
  g_last_status = (int)st;
  if (st != 0) return -1;
  return (int32_t)version;
}

int32_t cublasb_set_stream(int64_t h, int64_t stream) {
  cublasStatus_t st;
  if (g_api.set_stream == NULL) return 1;
  st = g_api.set_stream((cublasHandle_t)(intptr_t)h, (void*)(intptr_t)stream);
  g_last_status = (int)st;
  return (int32_t)st;
}

int32_t cublasb_sgemm(int64_t h, int transa, int transb, int m, int n, int k,
                      float alpha, int64_t a, int lda, int64_t b, int ldb,
                      float beta, int64_t c, int ldc) {
  cublasStatus_t st;
  if (g_api.sgemm == NULL) return 1;
  st = g_api.sgemm((cublasHandle_t)(intptr_t)h, transa, transb, m, n, k, &alpha,
                   (const float*)(uintptr_t)a, lda, (const float*)(uintptr_t)b,
                   ldb, &beta, (float*)(uintptr_t)c, ldc);
  g_last_status = (int)st;
  return (int32_t)st;
}

int32_t cublasb_dgemm(int64_t h, int transa, int transb, int m, int n, int k,
                      double alpha, int64_t a, int lda, int64_t b, int ldb,
                      double beta, int64_t c, int ldc) {
  cublasStatus_t st;
  if (g_api.dgemm == NULL) return 1;
  st = g_api.dgemm((cublasHandle_t)(intptr_t)h, transa, transb, m, n, k, &alpha,
                   (const double*)(uintptr_t)a, lda, (const double*)(uintptr_t)b,
                   ldb, &beta, (double*)(uintptr_t)c, ldc);
  g_last_status = (int)st;
  return (int32_t)st;
}

int32_t cublasb_saxpy(int64_t h, int n, float alpha, int64_t x, int incx,
                      int64_t y, int incy) {
  cublasStatus_t st;
  if (g_api.saxpy == NULL) return 1;
  st = g_api.saxpy((cublasHandle_t)(intptr_t)h, n, &alpha,
                   (const float*)(uintptr_t)x, incx, (float*)(uintptr_t)y, incy);
  g_last_status = (int)st;
  return (int32_t)st;
}

int32_t cublasb_daxpy(int64_t h, int n, double alpha, int64_t x, int incx,
                      int64_t y, int incy) {
  cublasStatus_t st;
  if (g_api.daxpy == NULL) return 1;
  st = g_api.daxpy((cublasHandle_t)(intptr_t)h, n, &alpha,
                   (const double*)(uintptr_t)x, incx, (double*)(uintptr_t)y, incy);
  g_last_status = (int)st;
  return (int32_t)st;
}

int32_t cublasb_sdot(int64_t h, int n, int64_t x, int incx, int64_t y, int incy) {
  cublasStatus_t st;
  if (g_api.sdot == NULL) return 1;
  st = g_api.sdot((cublasHandle_t)(intptr_t)h, n, (const float*)(uintptr_t)x, incx,
                  (const float*)(uintptr_t)y, incy, &g_last_f32);
  g_last_status = (int)st;
  return (int32_t)st;
}

int32_t cublasb_ddot(int64_t h, int n, int64_t x, int incx, int64_t y, int incy) {
  cublasStatus_t st;
  if (g_api.ddot == NULL) return 1;
  st = g_api.ddot((cublasHandle_t)(intptr_t)h, n, (const double*)(uintptr_t)x, incx,
                  (const double*)(uintptr_t)y, incy, &g_last_f64);
  g_last_status = (int)st;
  return (int32_t)st;
}

int32_t cublasb_sscal(int64_t h, int n, float alpha, int64_t x, int incx) {
  cublasStatus_t st;
  if (g_api.sscal == NULL) return 1;
  st = g_api.sscal((cublasHandle_t)(intptr_t)h, n, &alpha,
                   (float*)(uintptr_t)x, incx);
  g_last_status = (int)st;
  return (int32_t)st;
}

int32_t cublasb_dscal(int64_t h, int n, double alpha, int64_t x, int incx) {
  cublasStatus_t st;
  if (g_api.dscal == NULL) return 1;
  st = g_api.dscal((cublasHandle_t)(intptr_t)h, n, &alpha,
                   (double*)(uintptr_t)x, incx);
  g_last_status = (int)st;
  return (int32_t)st;
}

int32_t cublasb_snrm2(int64_t h, int n, int64_t x, int incx) {
  cublasStatus_t st;
  if (g_api.snrm2 == NULL) return 1;
  st = g_api.snrm2((cublasHandle_t)(intptr_t)h, n, (const float*)(uintptr_t)x,
                   incx, &g_last_f32);
  g_last_status = (int)st;
  return (int32_t)st;
}

int32_t cublasb_dnrm2(int64_t h, int n, int64_t x, int incx) {
  cublasStatus_t st;
  if (g_api.dnrm2 == NULL) return 1;
  st = g_api.dnrm2((cublasHandle_t)(intptr_t)h, n, (const double*)(uintptr_t)x,
                   incx, &g_last_f64);
  g_last_status = (int)st;
  return (int32_t)st;
}

int32_t cublasb_sgemv(int64_t h, int trans, int m, int n, float alpha, int64_t a,
                      int lda, int64_t x, int incx, float beta, int64_t y, int incy) {
  cublasStatus_t st;
  if (g_api.sgemv == NULL) return 1;
  st = g_api.sgemv((cublasHandle_t)(intptr_t)h, trans, m, n, &alpha,
                   (const float*)(uintptr_t)a, lda, (const float*)(uintptr_t)x,
                   incx, &beta, (float*)(uintptr_t)y, incy);
  g_last_status = (int)st;
  return (int32_t)st;
}

int32_t cublasb_dgemv(int64_t h, int trans, int m, int n, double alpha, int64_t a,
                      int lda, int64_t x, int incx, double beta, int64_t y, int incy) {
  cublasStatus_t st;
  if (g_api.dgemv == NULL) return 1;
  st = g_api.dgemv((cublasHandle_t)(intptr_t)h, trans, m, n, &alpha,
                   (const double*)(uintptr_t)a, lda, (const double*)(uintptr_t)x,
                   incx, &beta, (double*)(uintptr_t)y, incy);
  g_last_status = (int)st;
  return (int32_t)st;
}

/* ---- device memory helpers (driver API, user-provided driver) ---------- */

int64_t cublasb_dev_alloc(int64_t bytes) {
  unsigned long long p = 0;
  int rc;
  if (g_ctx == NULL || g_cu.mem_alloc == NULL || bytes <= 0) {
    g_last_driver = -1;
    return 0;
  }
  rc = g_cu.mem_alloc(&p, (unsigned long long)bytes);
  if (rc != 0) {
    g_last_driver = rc;
    return 0;
  }
  return (int64_t)p;
}

int32_t cublasb_dev_free(int64_t p) {
  int rc;
  if (g_cu.mem_free == NULL) return -1;
  rc = g_cu.mem_free((unsigned long long)p);
  g_last_driver = rc;
  return (int32_t)rc;
}

int32_t cublasb_dev_upload_f32(int64_t p, const float* src, int64_t count) {
  int rc;
  if (g_cu.memcpy_htod == NULL || src == NULL || count < 0) return -1;
  rc = g_cu.memcpy_htod((unsigned long long)p, src,
                        (unsigned long long)count * 4ULL);
  g_last_driver = rc;
  return (int32_t)rc;
}

int32_t cublasb_dev_download_f32(int64_t p, float* dst, int64_t count) {
  int rc;
  if (g_cu.memcpy_dtoh == NULL || dst == NULL || count < 0) return -1;
  rc = g_cu.memcpy_dtoh(dst, (unsigned long long)p,
                        (unsigned long long)count * 4ULL);
  g_last_driver = rc;
  return (int32_t)rc;
}

int32_t cublasb_dev_upload_f64(int64_t p, const double* src, int64_t count) {
  int rc;
  if (g_cu.memcpy_htod == NULL || src == NULL || count < 0) return -1;
  rc = g_cu.memcpy_htod((unsigned long long)p, src,
                        (unsigned long long)count * 8ULL);
  g_last_driver = rc;
  return (int32_t)rc;
}

int32_t cublasb_dev_download_f64(int64_t p, double* dst, int64_t count) {
  int rc;
  if (g_cu.memcpy_dtoh == NULL || dst == NULL || count < 0) return -1;
  rc = g_cu.memcpy_dtoh(dst, (unsigned long long)p,
                        (unsigned long long)count * 8ULL);
  g_last_driver = rc;
  return (int32_t)rc;
}
