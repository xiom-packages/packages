/* xiom.cufft -- runtime bridge over the NVIDIA cuFFT library.
 * Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
 * SPDX-License-Identifier: MIT OR Apache-2.0
 *
 * NOTHING from NVIDIA is vendored or linked at build time.  The cuFFT
 * runtime (the user's own CUDA Toolkit / pip-wheel installation) is loaded
 * at run time with LoadLibraryA/LoadLibraryExA, and every entry point is
 * resolved with GetProcAddress.  nvcuda.dll (a system component of any
 * NVIDIA driver) supplies the CUDA context and the device-memory helpers.
 *
 * Loader search (in order):
 *   1. an explicit directory (cufft_load_from): <dir>\cufft64_12.dll,
 *      cufft64_11.dll, cufft64_10.dll -- no bare-name fallback, so an
 *      absent directory is classified deterministically;
 *   2. XIOM_CUFFT_DIR when set (cufft_load);
 *   3. the OS module search (bare sonames cufft64_12/11/10.dll).
 *
 * The explicit-path load uses LOAD_WITH_ALTERED_SEARCH_PATH.
 *
 * ABI: cufftHandle is int; cufftResult is int; plans are created through
 * cufftPlan1d/cufftPlan2d.  Opaque handles and device addresses cross the
 * XIOM ABI as int64_t values; XIOM never dereferences them.
 *
 * Classification (kept in sync with cufft.xi):
 *   0 CUFFT_LOAD_ABSENT    -- cuFFT module not found       -> SKIP
 *   1 CUFFT_LOAD_ABI       -- entry points missing         -> FAIL
 *   2 CUFFT_LOAD_NO_DEVICE -- nvcuda missing / no device   -> SKIP
 *   3 CUFFT_LOAD_RUNTIME   -- context/step failure         -> FAIL
 *
 * All bridge state is process-global and single-threaded.
 */

#include <windows.h>
#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include <stdlib.h>

#define CUFFTB_LOAD_ABSENT 0
#define CUFFTB_LOAD_ABI 1
#define CUFFTB_LOAD_NO_DEVICE 2
#define CUFFTB_LOAD_RUNTIME 3

#define CUFFTB_CUDA_SUCCESS 0
#define CUFFTB_CUDA_ERROR_NO_DEVICE 100

typedef int cufftResult;
typedef int cufftHandle;

typedef cufftResult (*PFN_cufftPlan1d)(cufftHandle*, int, int, int);
typedef cufftResult (*PFN_cufftPlan2d)(cufftHandle*, int, int, int);
typedef cufftResult (*PFN_cufftDestroy)(cufftHandle);
typedef cufftResult (*PFN_cufftSetStream)(cufftHandle, void*);
typedef cufftResult (*PFN_cufftGetVersion)(int*);
typedef cufftResult (*PFN_cufftEstimate1d)(int, int, int, size_t*);
typedef cufftResult (*PFN_cufftEstimate2d)(int, int, int, size_t*);
typedef cufftResult (*PFN_cufftExecR2C)(cufftHandle, float*, void*);
typedef cufftResult (*PFN_cufftExecC2R)(cufftHandle, void*, float*);
typedef cufftResult (*PFN_cufftExecZ2Z)(cufftHandle, void*, void*, int);
typedef cufftResult (*PFN_cufftExecD2Z)(cufftHandle, double*, void*);
typedef cufftResult (*PFN_cufftExecZ2D)(cufftHandle, void*, double*);

typedef int (*PFN_cuInit)(unsigned int flags);
typedef int (*PFN_cuCtxCreate_v2)(void** pctx, unsigned int flags, int dev);
typedef int (*PFN_cuCtxDestroy_v2)(void* ctx);
typedef int (*PFN_cuMemAlloc_v2)(unsigned long long* dptr, unsigned long long bytesize);
typedef int (*PFN_cuMemFree_v2)(unsigned long long dptr);
typedef int (*PFN_cuMemcpyHtoD_v2)(unsigned long long dstDevice, const void* srcHost,
                                   unsigned long long byteCount);
typedef int (*PFN_cuMemcpyDtoH_v2)(void* dstHost, unsigned long long srcDevice,
                                   unsigned long long byteCount);

struct CufftApi {
  PFN_cufftPlan1d plan1d;
  PFN_cufftPlan2d plan2d;
  PFN_cufftDestroy destroy;
  PFN_cufftSetStream set_stream;
  PFN_cufftGetVersion get_version;
  PFN_cufftEstimate1d estimate1d;
  PFN_cufftEstimate2d estimate2d;
  PFN_cufftExecR2C exec_r2c;
  PFN_cufftExecC2R exec_c2r;
  PFN_cufftExecZ2Z exec_z2z;
  PFN_cufftExecD2Z exec_d2z;
  PFN_cufftExecZ2D exec_z2d;
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

static struct CufftApi g_api;
static struct CudaApi g_cu;

static const char* const k_cufft_names[] = {
    "cufft64_12.dll", "cufft64_11.dll", "cufft64_10.dll"};
static const int k_cufft_name_count =
    (int)(sizeof(k_cufft_names) / sizeof(k_cufft_names[0]));

static void reset_state(void) {
  memset(&g_api, 0, sizeof(g_api));
  memset(&g_cu, 0, sizeof(g_cu));
  g_mod = NULL;
  g_cuda = NULL;
  g_ctx = NULL;
  g_kind = CUFFTB_LOAD_ABSENT;
  g_last_status = 0;
  g_last_driver = 0;
}

static HMODULE load_from_dir(const char* dir) {
  char path[MAX_PATH];
  size_t dlen = strlen(dir);
  int sep;
  int i;
  if (dlen == 0 || dlen >= sizeof(path)) return NULL;
  sep = (dir[dlen - 1] == '\\' || dir[dlen - 1] == '/') ? 0 : 1;
  for (i = 0; i < k_cufft_name_count; i++) {
    size_t nlen = strlen(k_cufft_names[i]);
    if (dlen + (size_t)sep + nlen + 1 > sizeof(path)) continue;
    memcpy(path, dir, dlen);
    if (sep) path[dlen] = '\\';
    memcpy(path + dlen + (size_t)sep, k_cufft_names[i], nlen + 1);
    HMODULE m = LoadLibraryExA(path, NULL, LOAD_WITH_ALTERED_SEARCH_PATH);
    if (m != NULL) return m;
  }
  return NULL;
}

static HMODULE load_bare(void) {
  int i;
  for (i = 0; i < k_cufft_name_count; i++) {
    HMODULE m = LoadLibraryA(k_cufft_names[i]);
    if (m != NULL) return m;
  }
  return NULL;
}

static int resolve_cufft(void) {
  g_api.plan1d = (PFN_cufftPlan1d)(void*)GetProcAddress(g_mod, "cufftPlan1d");
  g_api.plan2d = (PFN_cufftPlan2d)(void*)GetProcAddress(g_mod, "cufftPlan2d");
  g_api.destroy = (PFN_cufftDestroy)(void*)GetProcAddress(g_mod, "cufftDestroy");
  g_api.set_stream = (PFN_cufftSetStream)(void*)GetProcAddress(g_mod, "cufftSetStream");
  g_api.get_version = (PFN_cufftGetVersion)(void*)GetProcAddress(g_mod, "cufftGetVersion");
  g_api.estimate1d = (PFN_cufftEstimate1d)(void*)GetProcAddress(g_mod, "cufftEstimate1d");
  g_api.estimate2d = (PFN_cufftEstimate2d)(void*)GetProcAddress(g_mod, "cufftEstimate2d");
  g_api.exec_r2c = (PFN_cufftExecR2C)(void*)GetProcAddress(g_mod, "cufftExecR2C");
  g_api.exec_c2r = (PFN_cufftExecC2R)(void*)GetProcAddress(g_mod, "cufftExecC2R");
  g_api.exec_z2z = (PFN_cufftExecZ2Z)(void*)GetProcAddress(g_mod, "cufftExecZ2Z");
  g_api.exec_d2z = (PFN_cufftExecD2Z)(void*)GetProcAddress(g_mod, "cufftExecD2Z");
  g_api.exec_z2d = (PFN_cufftExecZ2D)(void*)GetProcAddress(g_mod, "cufftExecZ2D");
  if (g_api.plan1d == NULL || g_api.plan2d == NULL || g_api.destroy == NULL ||
      g_api.set_stream == NULL || g_api.estimate1d == NULL ||
      g_api.estimate2d == NULL || g_api.exec_r2c == NULL ||
      g_api.exec_c2r == NULL || g_api.exec_z2z == NULL ||
      g_api.exec_d2z == NULL || g_api.exec_z2d == NULL) {
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
    g_kind = CUFFTB_LOAD_NO_DEVICE;
    return 0;
  }
  if (!resolve_cuda()) {
    g_kind = CUFFTB_LOAD_ABI;
    return 0;
  }
  rc = g_cu.init(0);
  if (rc == CUFFTB_CUDA_ERROR_NO_DEVICE) {
    g_kind = CUFFTB_LOAD_NO_DEVICE;
    return 0;
  }
  if (rc != CUFFTB_CUDA_SUCCESS) {
    g_last_driver = rc;
    g_kind = CUFFTB_LOAD_RUNTIME;
    return 0;
  }
  rc = g_cu.ctx_create(&g_ctx, 0, 0);
  if (rc != CUFFTB_CUDA_SUCCESS) {
    g_last_driver = rc;
    g_kind = (rc == CUFFTB_CUDA_ERROR_NO_DEVICE) ? CUFFTB_LOAD_NO_DEVICE
                                                 : CUFFTB_LOAD_RUNTIME;
    return 0;
  }
  return 1;
}

int32_t cufftb_last_kind(void) {
  return g_kind;
}

int32_t cufftb_last_status(void) {
  return g_last_status;
}

int32_t cufftb_last_driver(void) {
  return g_last_driver;
}

/* Returns the module handle (>0) or 0.  An explicit directory is strict. */
int64_t cufftb_load(const char* explicit_dir) {
  HMODULE m = NULL;
  if (g_mod != NULL) return (int64_t)(intptr_t)g_mod;
  reset_state();
  if (explicit_dir != NULL && explicit_dir[0] != 0) {
    m = load_from_dir(explicit_dir);
  } else {
    const char* env = getenv("XIOM_CUFFT_DIR");
    if (env != NULL && env[0] != 0) m = load_from_dir(env);
    if (m == NULL) m = load_bare();
  }
  if (m == NULL) {
    g_kind = CUFFTB_LOAD_ABSENT;
    return 0;
  }
  g_mod = m;
  if (!resolve_cufft()) {
    g_kind = CUFFTB_LOAD_ABI;
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
  g_kind = CUFFTB_LOAD_RUNTIME;
  return (int64_t)(intptr_t)g_mod;
}

int32_t cufftb_unload(int64_t mod) {
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

int64_t cufftb_plan1d(int64_t mod, int32_t nx, int32_t type, int32_t batch) {
  cufftHandle plan = 0;
  cufftResult st;
  if (g_mod == NULL || (HMODULE)(intptr_t)mod != g_mod || g_api.plan1d == NULL) {
    g_last_status = 1;
    return -1;
  }
  st = g_api.plan1d(&plan, (int)nx, (int)type, (int)batch);
  g_last_status = (int)st;
  if (st != 0) return -1;
  return (int64_t)plan;
}

int64_t cufftb_plan2d(int64_t mod, int32_t nx, int32_t ny, int32_t type) {
  cufftHandle plan = 0;
  cufftResult st;
  if (g_mod == NULL || (HMODULE)(intptr_t)mod != g_mod || g_api.plan2d == NULL) {
    g_last_status = 1;
    return -1;
  }
  st = g_api.plan2d(&plan, (int)nx, (int)ny, (int)type);
  g_last_status = (int)st;
  if (st != 0) return -1;
  return (int64_t)plan;
}

int32_t cufftb_destroy(int64_t plan) {
  cufftResult st;
  if (g_api.destroy == NULL) return 1;
  st = g_api.destroy((cufftHandle)plan);
  g_last_status = (int)st;
  return (int32_t)st;
}

int32_t cufftb_set_stream(int64_t plan, int64_t stream) {
  cufftResult st;
  if (g_api.set_stream == NULL) return 1;
  st = g_api.set_stream((cufftHandle)plan, (void*)(intptr_t)stream);
  g_last_status = (int)st;
  return (int32_t)st;
}

int32_t cufftb_get_version(void) {
  int version = 0;
  cufftResult st;
  if (g_api.get_version == NULL) return -1;
  st = g_api.get_version(&version);
  g_last_status = (int)st;
  if (st != 0) return -1;
  return (int32_t)version;
}

int64_t cufftb_estimate1d(int32_t nx, int32_t type, int32_t batch) {
  size_t bytes = 0;
  cufftResult st;
  if (g_api.estimate1d == NULL) return -1;
  st = g_api.estimate1d((int)nx, (int)type, (int)batch, &bytes);
  g_last_status = (int)st;
  if (st != 0) return -1;
  return (int64_t)bytes;
}

int64_t cufftb_estimate2d(int32_t nx, int32_t ny, int32_t type) {
  size_t bytes = 0;
  cufftResult st;
  if (g_api.estimate2d == NULL) return -1;
  st = g_api.estimate2d((int)nx, (int)ny, (int)type, &bytes);
  g_last_status = (int)st;
  if (st != 0) return -1;
  return (int64_t)bytes;
}

int32_t cufftb_exec_r2c(int64_t plan, int64_t idata, int64_t odata) {
  cufftResult st;
  if (g_api.exec_r2c == NULL) return 1;
  st = g_api.exec_r2c((cufftHandle)plan, (float*)(uintptr_t)idata,
                      (void*)(uintptr_t)odata);
  g_last_status = (int)st;
  return (int32_t)st;
}

int32_t cufftb_exec_c2r(int64_t plan, int64_t idata, int64_t odata) {
  cufftResult st;
  if (g_api.exec_c2r == NULL) return 1;
  st = g_api.exec_c2r((cufftHandle)plan, (void*)(uintptr_t)idata,
                      (float*)(uintptr_t)odata);
  g_last_status = (int)st;
  return (int32_t)st;
}

int32_t cufftb_exec_z2z(int64_t plan, int64_t idata, int64_t odata, int32_t direction) {
  cufftResult st;
  if (g_api.exec_z2z == NULL) return 1;
  st = g_api.exec_z2z((cufftHandle)plan, (void*)(uintptr_t)idata,
                      (void*)(uintptr_t)odata, (int)direction);
  g_last_status = (int)st;
  return (int32_t)st;
}

int32_t cufftb_exec_d2z(int64_t plan, int64_t idata, int64_t odata) {
  cufftResult st;
  if (g_api.exec_d2z == NULL) return 1;
  st = g_api.exec_d2z((cufftHandle)plan, (double*)(uintptr_t)idata,
                      (void*)(uintptr_t)odata);
  g_last_status = (int)st;
  return (int32_t)st;
}

int32_t cufftb_exec_z2d(int64_t plan, int64_t idata, int64_t odata) {
  cufftResult st;
  if (g_api.exec_z2d == NULL) return 1;
  st = g_api.exec_z2d((cufftHandle)plan, (void*)(uintptr_t)idata,
                      (double*)(uintptr_t)odata);
  g_last_status = (int)st;
  return (int32_t)st;
}

/* ---- device memory helpers (driver API, user-provided driver) ---------- */

int64_t cufftb_dev_alloc(int64_t bytes) {
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

int32_t cufftb_dev_free(int64_t p) {
  int rc;
  if (g_cu.mem_free == NULL) return -1;
  rc = g_cu.mem_free((unsigned long long)p);
  g_last_driver = rc;
  return (int32_t)rc;
}

int32_t cufftb_dev_upload_f32(int64_t p, const float* src, int64_t count) {
  int rc;
  if (g_cu.memcpy_htod == NULL || src == NULL || count < 0) return -1;
  rc = g_cu.memcpy_htod((unsigned long long)p, src,
                        (unsigned long long)count * 4ULL);
  g_last_driver = rc;
  return (int32_t)rc;
}

int32_t cufftb_dev_download_f32(int64_t p, float* dst, int64_t count) {
  int rc;
  if (g_cu.memcpy_dtoh == NULL || dst == NULL || count < 0) return -1;
  rc = g_cu.memcpy_dtoh(dst, (unsigned long long)p,
                        (unsigned long long)count * 4ULL);
  g_last_driver = rc;
  return (int32_t)rc;
}

int32_t cufftb_dev_upload_f64(int64_t p, const double* src, int64_t count) {
  int rc;
  if (g_cu.memcpy_htod == NULL || src == NULL || count < 0) return -1;
  rc = g_cu.memcpy_htod((unsigned long long)p, src,
                        (unsigned long long)count * 8ULL);
  g_last_driver = rc;
  return (int32_t)rc;
}

int32_t cufftb_dev_download_f64(int64_t p, double* dst, int64_t count) {
  int rc;
  if (g_cu.memcpy_dtoh == NULL || dst == NULL || count < 0) return -1;
  rc = g_cu.memcpy_dtoh(dst, (unsigned long long)p,
                        (unsigned long long)count * 8ULL);
  g_last_driver = rc;
  return (int32_t)rc;
}
