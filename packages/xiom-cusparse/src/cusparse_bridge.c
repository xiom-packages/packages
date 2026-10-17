/* xiom.cusparse -- runtime bridge over the NVIDIA cuSPARSE library.
 * Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
 * SPDX-License-Identifier: MIT OR Apache-2.0
 *
 * NOTHING from NVIDIA is vendored or linked at build time.  The cuSPARSE
 * runtime (the user's own CUDA Toolkit / pip-wheel installation) is loaded
 * at run time with LoadLibraryA/LoadLibraryExA, and every entry point is
 * resolved with GetProcAddress.  nvcuda.dll (a system component of any
 * NVIDIA driver) supplies the CUDA context and the device-memory helpers.
 *
 * Loader search (in order):
 *   1. an explicit directory (cusparse_load_from): <dir>\cusparse64_13.dll,
 *      cusparse64_12.dll, cusparse64_11.dll, cusparse64_10.dll -- no
 *      bare-name fallback, so an absent directory is deterministic;
 *   2. XIOM_CUSPARSE_DIR when set (cusparse_load);
 *   3. the OS module search (bare sonames cusparse64_13/12/11/10.dll).
 *
 * The explicit-path load uses LOAD_WITH_ALTERED_SEARCH_PATH so the
 * sibling dependency nvJitLink_120_0.dll resolves from the same directory.
 *
 * ABI (cusparse.h @ 12.5.10.65): all descriptor handles are pointers;
 * indices are int64_t; alpha/beta are host pointers in the default pointer
 * mode.  The bridge converts the double alpha/beta to float or double by
 * computeType (CUDA_R_32F / CUDA_R_64F only).  Opaque handles and device
 * addresses cross the XIOM ABI as int64_t values.
 *
 * Classification (kept in sync with cusparse.xi):
 *   0 CUSPARSE_LOAD_ABSENT    -- cuSPARSE module not found     -> SKIP
 *   1 CUSPARSE_LOAD_ABI       -- entry points missing          -> FAIL
 *   2 CUSPARSE_LOAD_NO_DEVICE -- nvcuda missing / no device    -> SKIP
 *   3 CUSPARSE_LOAD_RUNTIME   -- context/step failure          -> FAIL
 *
 * All bridge state is process-global and single-threaded.
 */

#include <windows.h>
#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include <stdlib.h>

#define CUSPARSEB_LOAD_ABSENT 0
#define CUSPARSEB_LOAD_ABI 1
#define CUSPARSEB_LOAD_NO_DEVICE 2
#define CUSPARSEB_LOAD_RUNTIME 3

#define CUSPARSEB_CUDA_SUCCESS 0
#define CUSPARSEB_CUDA_ERROR_NO_DEVICE 100

#define CUSPARSEB_CUDA_R_32F 0
#define CUSPARSEB_CUDA_R_64F 1

#define CUSPARSEB_STATUS_NOT_SUPPORTED 10

typedef int cusparseStatus_t;
typedef void* cusparseHandle_t;
typedef void* cusparseMatDescr_t;
typedef void* cusparseSpMatDescr_t;
typedef void* cusparseDnVecDescr_t;
typedef void* cusparseDnMatDescr_t;

typedef cusparseStatus_t (*PFN_cusparseCreate)(cusparseHandle_t* handle);
typedef cusparseStatus_t (*PFN_cusparseDestroy)(cusparseHandle_t handle);
typedef cusparseStatus_t (*PFN_cusparseGetVersion)(cusparseHandle_t handle, int* version);
typedef cusparseStatus_t (*PFN_cusparseSetStream)(cusparseHandle_t handle, void* stream);
typedef cusparseStatus_t (*PFN_cusparseCreateMatDescr)(cusparseMatDescr_t* descr);
typedef cusparseStatus_t (*PFN_cusparseDestroyMatDescr)(cusparseMatDescr_t descr);
typedef cusparseStatus_t (*PFN_cusparseSetMatType)(cusparseMatDescr_t descr, int type);
typedef cusparseStatus_t (*PFN_cusparseSetMatIndexBase)(cusparseMatDescr_t descr, int base);
typedef cusparseStatus_t (*PFN_cusparseCreateCsr)(cusparseSpMatDescr_t*, int64_t rows,
                                                  int64_t cols, int64_t nnz,
                                                  void* row_offsets, void* col_indices,
                                                  void* values, int row_off_type,
                                                  int col_ind_type, int index_base,
                                                  int value_type);
typedef cusparseStatus_t (*PFN_cusparseCreateDnVec)(cusparseDnVecDescr_t*, int64_t size,
                                                    void* values, int value_type);
typedef cusparseStatus_t (*PFN_cusparseCreateDnMat)(cusparseDnMatDescr_t*, int64_t rows,
                                                    int64_t cols, int64_t ld, void* values,
                                                    int value_type, int order);
typedef cusparseStatus_t (*PFN_cusparseDestroySpMat)(cusparseSpMatDescr_t descr);
typedef cusparseStatus_t (*PFN_cusparseDestroyDnVec)(cusparseDnVecDescr_t descr);
typedef cusparseStatus_t (*PFN_cusparseDestroyDnMat)(cusparseDnMatDescr_t descr);
typedef cusparseStatus_t (*PFN_cusparseSpMV_bufferSize)(
    cusparseHandle_t, int opA, const void* alpha, cusparseSpMatDescr_t,
    cusparseDnVecDescr_t, const void* beta, cusparseDnVecDescr_t, int compute_type,
    int alg, size_t* buffer_size);
typedef cusparseStatus_t (*PFN_cusparseSpMV)(
    cusparseHandle_t, int opA, const void* alpha, cusparseSpMatDescr_t,
    cusparseDnVecDescr_t, const void* beta, cusparseDnVecDescr_t, int compute_type,
    int alg, void* external_buffer);
typedef cusparseStatus_t (*PFN_cusparseSpMM_bufferSize)(
    cusparseHandle_t, int opA, int opB, const void* alpha, cusparseSpMatDescr_t,
    cusparseDnMatDescr_t, const void* beta, cusparseDnMatDescr_t, int compute_type,
    int alg, size_t* buffer_size);
typedef cusparseStatus_t (*PFN_cusparseSpMM)(
    cusparseHandle_t, int opA, int opB, const void* alpha, cusparseSpMatDescr_t,
    cusparseDnMatDescr_t, const void* beta, cusparseDnMatDescr_t, int compute_type,
    int alg, void* external_buffer);

typedef int (*PFN_cuInit)(unsigned int flags);
typedef int (*PFN_cuCtxCreate_v2)(void** pctx, unsigned int flags, int dev);
typedef int (*PFN_cuCtxDestroy_v2)(void* ctx);
typedef int (*PFN_cuMemAlloc_v2)(unsigned long long* dptr, unsigned long long bytesize);
typedef int (*PFN_cuMemFree_v2)(unsigned long long dptr);
typedef int (*PFN_cuMemcpyHtoD_v2)(unsigned long long dstDevice, const void* srcHost,
                                   unsigned long long byteCount);
typedef int (*PFN_cuMemcpyDtoH_v2)(void* dstHost, unsigned long long srcDevice,
                                   unsigned long long byteCount);

struct CusparseApi {
  PFN_cusparseCreate create;
  PFN_cusparseDestroy destroy;
  PFN_cusparseGetVersion get_version;
  PFN_cusparseSetStream set_stream;
  PFN_cusparseCreateMatDescr create_mat_descr;
  PFN_cusparseDestroyMatDescr destroy_mat_descr;
  PFN_cusparseSetMatType set_mat_type;
  PFN_cusparseSetMatIndexBase set_mat_index_base;
  PFN_cusparseCreateCsr create_csr;
  PFN_cusparseCreateDnVec create_dnvec;
  PFN_cusparseCreateDnMat create_dnmat;
  PFN_cusparseDestroySpMat destroy_spmat;
  PFN_cusparseDestroyDnVec destroy_dnvec;
  PFN_cusparseDestroyDnMat destroy_dnmat;
  PFN_cusparseSpMV_bufferSize spmv_buffer_size;
  PFN_cusparseSpMV spmv;
  PFN_cusparseSpMM_bufferSize spmm_buffer_size;
  PFN_cusparseSpMM spmm;
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

static struct CusparseApi g_api;
static struct CudaApi g_cu;

static const char* const k_cusparse_names[] = {
    "cusparse64_13.dll", "cusparse64_12.dll", "cusparse64_11.dll",
    "cusparse64_10.dll"};
static const int k_cusparse_name_count =
    (int)(sizeof(k_cusparse_names) / sizeof(k_cusparse_names[0]));

static void reset_state(void) {
  memset(&g_api, 0, sizeof(g_api));
  memset(&g_cu, 0, sizeof(g_cu));
  g_mod = NULL;
  g_cuda = NULL;
  g_ctx = NULL;
  g_kind = CUSPARSEB_LOAD_ABSENT;
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
  for (i = 0; i < k_cusparse_name_count; i++) {
    size_t nlen = strlen(k_cusparse_names[i]);
    if (dlen + (size_t)sep + nlen + 1 > sizeof(path)) continue;
    memcpy(path, dir, dlen);
    if (sep) path[dlen] = '\\';
    memcpy(path + dlen + (size_t)sep, k_cusparse_names[i], nlen + 1);
    HMODULE m = LoadLibraryExA(path, NULL, LOAD_WITH_ALTERED_SEARCH_PATH);
    if (m != NULL) return m;
  }
  return NULL;
}

static HMODULE load_bare(void) {
  int i;
  for (i = 0; i < k_cusparse_name_count; i++) {
    HMODULE m = LoadLibraryA(k_cusparse_names[i]);
    if (m != NULL) return m;
  }
  return NULL;
}

static int resolve_cusparse(void) {
  g_api.create = (PFN_cusparseCreate)(void*)GetProcAddress(g_mod, "cusparseCreate");
  g_api.destroy = (PFN_cusparseDestroy)(void*)GetProcAddress(g_mod, "cusparseDestroy");
  g_api.get_version =
      (PFN_cusparseGetVersion)(void*)GetProcAddress(g_mod, "cusparseGetVersion");
  g_api.set_stream =
      (PFN_cusparseSetStream)(void*)GetProcAddress(g_mod, "cusparseSetStream");
  g_api.create_mat_descr =
      (PFN_cusparseCreateMatDescr)(void*)GetProcAddress(g_mod, "cusparseCreateMatDescr");
  g_api.destroy_mat_descr = (PFN_cusparseDestroyMatDescr)(void*)GetProcAddress(
      g_mod, "cusparseDestroyMatDescr");
  g_api.set_mat_type =
      (PFN_cusparseSetMatType)(void*)GetProcAddress(g_mod, "cusparseSetMatType");
  g_api.set_mat_index_base = (PFN_cusparseSetMatIndexBase)(void*)GetProcAddress(
      g_mod, "cusparseSetMatIndexBase");
  g_api.create_csr =
      (PFN_cusparseCreateCsr)(void*)GetProcAddress(g_mod, "cusparseCreateCsr");
  g_api.create_dnvec =
      (PFN_cusparseCreateDnVec)(void*)GetProcAddress(g_mod, "cusparseCreateDnVec");
  g_api.create_dnmat =
      (PFN_cusparseCreateDnMat)(void*)GetProcAddress(g_mod, "cusparseCreateDnMat");
  g_api.destroy_spmat =
      (PFN_cusparseDestroySpMat)(void*)GetProcAddress(g_mod, "cusparseDestroySpMat");
  g_api.destroy_dnvec =
      (PFN_cusparseDestroyDnVec)(void*)GetProcAddress(g_mod, "cusparseDestroyDnVec");
  g_api.destroy_dnmat =
      (PFN_cusparseDestroyDnMat)(void*)GetProcAddress(g_mod, "cusparseDestroyDnMat");
  g_api.spmv_buffer_size = (PFN_cusparseSpMV_bufferSize)(void*)GetProcAddress(
      g_mod, "cusparseSpMV_bufferSize");
  g_api.spmv = (PFN_cusparseSpMV)(void*)GetProcAddress(g_mod, "cusparseSpMV");
  g_api.spmm_buffer_size = (PFN_cusparseSpMM_bufferSize)(void*)GetProcAddress(
      g_mod, "cusparseSpMM_bufferSize");
  g_api.spmm = (PFN_cusparseSpMM)(void*)GetProcAddress(g_mod, "cusparseSpMM");
  if (g_api.create == NULL || g_api.destroy == NULL || g_api.get_version == NULL ||
      g_api.set_stream == NULL || g_api.create_mat_descr == NULL ||
      g_api.destroy_mat_descr == NULL || g_api.set_mat_type == NULL ||
      g_api.set_mat_index_base == NULL || g_api.create_csr == NULL ||
      g_api.create_dnvec == NULL || g_api.create_dnmat == NULL ||
      g_api.destroy_spmat == NULL || g_api.destroy_dnvec == NULL ||
      g_api.destroy_dnmat == NULL || g_api.spmv_buffer_size == NULL ||
      g_api.spmv == NULL || g_api.spmm_buffer_size == NULL || g_api.spmm == NULL) {
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
    g_kind = CUSPARSEB_LOAD_NO_DEVICE;
    return 0;
  }
  if (!resolve_cuda()) {
    g_kind = CUSPARSEB_LOAD_ABI;
    return 0;
  }
  rc = g_cu.init(0);
  if (rc == CUSPARSEB_CUDA_ERROR_NO_DEVICE) {
    g_kind = CUSPARSEB_LOAD_NO_DEVICE;
    return 0;
  }
  if (rc != CUSPARSEB_CUDA_SUCCESS) {
    g_last_driver = rc;
    g_kind = CUSPARSEB_LOAD_RUNTIME;
    return 0;
  }
  rc = g_cu.ctx_create(&g_ctx, 0, 0);
  if (rc != CUSPARSEB_CUDA_SUCCESS) {
    g_last_driver = rc;
    g_kind = (rc == CUSPARSEB_CUDA_ERROR_NO_DEVICE) ? CUSPARSEB_LOAD_NO_DEVICE
                                                    : CUSPARSEB_LOAD_RUNTIME;
    return 0;
  }
  return 1;
}

/* Host scalar pointer for alpha/beta, selected by computeType. */
static const void* scalar_ptr(int compute_type, float* f, double* d, double value) {
  if (compute_type == CUSPARSEB_CUDA_R_32F) {
    *f = (float)value;
    return f;
  }
  if (compute_type == CUSPARSEB_CUDA_R_64F) {
    *d = value;
    return d;
  }
  return NULL;
}

int32_t cusparseb_last_kind(void) {
  return g_kind;
}

int32_t cusparseb_last_status(void) {
  return g_last_status;
}

int32_t cusparseb_last_driver(void) {
  return g_last_driver;
}

/* Returns the module handle (>0) or 0.  An explicit directory is strict. */
int64_t cusparseb_load(const char* explicit_dir) {
  HMODULE m = NULL;
  if (g_mod != NULL) return (int64_t)(intptr_t)g_mod;
  reset_state();
  if (explicit_dir != NULL && explicit_dir[0] != 0) {
    m = load_from_dir(explicit_dir);
  } else {
    const char* env = getenv("XIOM_CUSPARSE_DIR");
    if (env != NULL && env[0] != 0) m = load_from_dir(env);
    if (m == NULL) m = load_bare();
  }
  if (m == NULL) {
    g_kind = CUSPARSEB_LOAD_ABSENT;
    return 0;
  }
  g_mod = m;
  if (!resolve_cusparse()) {
    g_kind = CUSPARSEB_LOAD_ABI;
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
  g_kind = CUSPARSEB_LOAD_RUNTIME;
  return (int64_t)(intptr_t)g_mod;
}

int32_t cusparseb_unload(int64_t mod) {
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

int64_t cusparseb_create(int64_t mod) {
  cusparseHandle_t h = NULL;
  cusparseStatus_t st;
  if (g_mod == NULL || (HMODULE)(intptr_t)mod != g_mod || g_api.create == NULL) {
    g_last_status = 1;
    return 0;
  }
  st = g_api.create(&h);
  g_last_status = (int)st;
  if (st != 0 || h == NULL) return 0;
  return (int64_t)(intptr_t)h;
}

int32_t cusparseb_destroy(int64_t h) {
  cusparseStatus_t st;
  if (g_api.destroy == NULL) return 1;
  st = g_api.destroy((cusparseHandle_t)(intptr_t)h);
  g_last_status = (int)st;
  return (int32_t)st;
}

int32_t cusparseb_get_version(int64_t h) {
  int version = 0;
  cusparseStatus_t st;
  if (g_api.get_version == NULL) return -1;
  st = g_api.get_version((cusparseHandle_t)(intptr_t)h, &version);
  g_last_status = (int)st;
  if (st != 0) return -1;
  return (int32_t)version;
}

int32_t cusparseb_set_stream(int64_t h, int64_t stream) {
  cusparseStatus_t st;
  if (g_api.set_stream == NULL) return 1;
  st = g_api.set_stream((cusparseHandle_t)(intptr_t)h, (void*)(intptr_t)stream);
  g_last_status = (int)st;
  return (int32_t)st;
}

int64_t cusparseb_create_mat_descr(void) {
  cusparseMatDescr_t d = NULL;
  cusparseStatus_t st;
  if (g_api.create_mat_descr == NULL) {
    g_last_status = 1;
    return 0;
  }
  st = g_api.create_mat_descr(&d);
  g_last_status = (int)st;
  if (st != 0 || d == NULL) return 0;
  return (int64_t)(intptr_t)d;
}

int32_t cusparseb_destroy_mat_descr(int64_t d) {
  cusparseStatus_t st;
  if (g_api.destroy_mat_descr == NULL) return 1;
  st = g_api.destroy_mat_descr((cusparseMatDescr_t)(intptr_t)d);
  g_last_status = (int)st;
  return (int32_t)st;
}

int32_t cusparseb_set_mat_type(int64_t d, int32_t type) {
  cusparseStatus_t st;
  if (g_api.set_mat_type == NULL) return 1;
  st = g_api.set_mat_type((cusparseMatDescr_t)(intptr_t)d, (int)type);
  g_last_status = (int)st;
  return (int32_t)st;
}

int32_t cusparseb_set_mat_index_base(int64_t d, int32_t base) {
  cusparseStatus_t st;
  if (g_api.set_mat_index_base == NULL) return 1;
  st = g_api.set_mat_index_base((cusparseMatDescr_t)(intptr_t)d, (int)base);
  g_last_status = (int)st;
  return (int32_t)st;
}

int64_t cusparseb_create_csr(int64_t rows, int64_t cols, int64_t nnz,
                             int64_t row_offsets, int64_t col_indices,
                             int64_t values, int32_t row_off_type,
                             int32_t col_ind_type, int32_t index_base,
                             int32_t value_type) {
  cusparseSpMatDescr_t d = NULL;
  cusparseStatus_t st;
  if (g_api.create_csr == NULL) {
    g_last_status = 1;
    return 0;
  }
  st = g_api.create_csr(&d, rows, cols, nnz, (void*)(uintptr_t)row_offsets,
                        (void*)(uintptr_t)col_indices, (void*)(uintptr_t)values,
                        (int)row_off_type, (int)col_ind_type, (int)index_base,
                        (int)value_type);
  g_last_status = (int)st;
  if (st != 0 || d == NULL) return 0;
  return (int64_t)(intptr_t)d;
}

int64_t cusparseb_create_dnvec(int64_t size, int64_t values, int32_t value_type) {
  cusparseDnVecDescr_t d = NULL;
  cusparseStatus_t st;
  if (g_api.create_dnvec == NULL) {
    g_last_status = 1;
    return 0;
  }
  st = g_api.create_dnvec(&d, size, (void*)(uintptr_t)values, (int)value_type);
  g_last_status = (int)st;
  if (st != 0 || d == NULL) return 0;
  return (int64_t)(intptr_t)d;
}

int64_t cusparseb_create_dnmat(int64_t rows, int64_t cols, int64_t ld,
                               int64_t values, int32_t value_type, int32_t order) {
  cusparseDnMatDescr_t d = NULL;
  cusparseStatus_t st;
  if (g_api.create_dnmat == NULL) {
    g_last_status = 1;
    return 0;
  }
  st = g_api.create_dnmat(&d, rows, cols, ld, (void*)(uintptr_t)values,
                          (int)value_type, (int)order);
  g_last_status = (int)st;
  if (st != 0 || d == NULL) return 0;
  return (int64_t)(intptr_t)d;
}

int32_t cusparseb_destroy_spmat(int64_t d) {
  cusparseStatus_t st;
  if (g_api.destroy_spmat == NULL) return 1;
  st = g_api.destroy_spmat((cusparseSpMatDescr_t)(intptr_t)d);
  g_last_status = (int)st;
  return (int32_t)st;
}

int32_t cusparseb_destroy_dnvec(int64_t d) {
  cusparseStatus_t st;
  if (g_api.destroy_dnvec == NULL) return 1;
  st = g_api.destroy_dnvec((cusparseDnVecDescr_t)(intptr_t)d);
  g_last_status = (int)st;
  return (int32_t)st;
}

int32_t cusparseb_destroy_dnmat(int64_t d) {
  cusparseStatus_t st;
  if (g_api.destroy_dnmat == NULL) return 1;
  st = g_api.destroy_dnmat((cusparseDnMatDescr_t)(intptr_t)d);
  g_last_status = (int)st;
  return (int32_t)st;
}

int64_t cusparseb_spmv_buffer_size(int64_t h, int32_t op, double alpha,
                                   int64_t sp, int64_t x, double beta,
                                   int64_t y, int32_t compute_type, int32_t alg) {
  size_t bytes = 0;
  cusparseStatus_t st;
  float af = 0.0f;
  double ad = 0.0;
  float bf = 0.0f;
  double bd = 0.0;
  const void* pa;
  const void* pb;
  if (g_api.spmv_buffer_size == NULL) return -1;
  pa = scalar_ptr((int)compute_type, &af, &ad, alpha);
  pb = scalar_ptr((int)compute_type, &bf, &bd, beta);
  if (pa == NULL || pb == NULL) {
    g_last_status = CUSPARSEB_STATUS_NOT_SUPPORTED;
    return -1;
  }
  st = g_api.spmv_buffer_size((cusparseHandle_t)(intptr_t)h, (int)op, pa,
                              (cusparseSpMatDescr_t)(intptr_t)sp,
                              (cusparseDnVecDescr_t)(intptr_t)x, pb,
                              (cusparseDnVecDescr_t)(intptr_t)y, (int)compute_type,
                              (int)alg, &bytes);
  g_last_status = (int)st;
  if (st != 0) return -1;
  return (int64_t)bytes;
}

int32_t cusparseb_spmv(int64_t h, int32_t op, double alpha, int64_t sp,
                       int64_t x, double beta, int64_t y, int32_t compute_type,
                       int32_t alg, int64_t external_buffer) {
  cusparseStatus_t st;
  float af = 0.0f;
  double ad = 0.0;
  float bf = 0.0f;
  double bd = 0.0;
  const void* pa;
  const void* pb;
  if (g_api.spmv == NULL) return 1;
  pa = scalar_ptr((int)compute_type, &af, &ad, alpha);
  pb = scalar_ptr((int)compute_type, &bf, &bd, beta);
  if (pa == NULL || pb == NULL) {
    g_last_status = CUSPARSEB_STATUS_NOT_SUPPORTED;
    return CUSPARSEB_STATUS_NOT_SUPPORTED;
  }
  st = g_api.spmv((cusparseHandle_t)(intptr_t)h, (int)op, pa,
                  (cusparseSpMatDescr_t)(intptr_t)sp,
                  (cusparseDnVecDescr_t)(intptr_t)x, pb,
                  (cusparseDnVecDescr_t)(intptr_t)y, (int)compute_type, (int)alg,
                  (void*)(uintptr_t)external_buffer);
  g_last_status = (int)st;
  return (int32_t)st;
}

int64_t cusparseb_spmm_buffer_size(int64_t h, int32_t op_a, int32_t op_b,
                                   double alpha, int64_t sp, int64_t b,
                                   double beta, int64_t c, int32_t compute_type,
                                   int32_t alg) {
  size_t bytes = 0;
  cusparseStatus_t st;
  float af = 0.0f;
  double ad = 0.0;
  float bf = 0.0f;
  double bd = 0.0;
  const void* pa;
  const void* pb;
  if (g_api.spmm_buffer_size == NULL) return -1;
  pa = scalar_ptr((int)compute_type, &af, &ad, alpha);
  pb = scalar_ptr((int)compute_type, &bf, &bd, beta);
  if (pa == NULL || pb == NULL) {
    g_last_status = CUSPARSEB_STATUS_NOT_SUPPORTED;
    return -1;
  }
  st = g_api.spmm_buffer_size((cusparseHandle_t)(intptr_t)h, (int)op_a, (int)op_b,
                              pa, (cusparseSpMatDescr_t)(intptr_t)sp,
                              (cusparseDnMatDescr_t)(intptr_t)b, pb,
                              (cusparseDnMatDescr_t)(intptr_t)c, (int)compute_type,
                              (int)alg, &bytes);
  g_last_status = (int)st;
  if (st != 0) return -1;
  return (int64_t)bytes;
}

int32_t cusparseb_spmm(int64_t h, int32_t op_a, int32_t op_b, double alpha,
                       int64_t sp, int64_t b, double beta, int64_t c,
                       int32_t compute_type, int32_t alg, int64_t external_buffer) {
  cusparseStatus_t st;
  float af = 0.0f;
  double ad = 0.0;
  float bf = 0.0f;
  double bd = 0.0;
  const void* pa;
  const void* pb;
  if (g_api.spmm == NULL) return 1;
  pa = scalar_ptr((int)compute_type, &af, &ad, alpha);
  pb = scalar_ptr((int)compute_type, &bf, &bd, beta);
  if (pa == NULL || pb == NULL) {
    g_last_status = CUSPARSEB_STATUS_NOT_SUPPORTED;
    return CUSPARSEB_STATUS_NOT_SUPPORTED;
  }
  st = g_api.spmm((cusparseHandle_t)(intptr_t)h, (int)op_a, (int)op_b, pa,
                  (cusparseSpMatDescr_t)(intptr_t)sp,
                  (cusparseDnMatDescr_t)(intptr_t)b, pb,
                  (cusparseDnMatDescr_t)(intptr_t)c, (int)compute_type, (int)alg,
                  (void*)(uintptr_t)external_buffer);
  g_last_status = (int)st;
  return (int32_t)st;
}

/* ---- device memory helpers (driver API, user-provided driver) ---------- */

int64_t cusparseb_dev_alloc(int64_t bytes) {
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

int32_t cusparseb_dev_free(int64_t p) {
  int rc;
  if (g_cu.mem_free == NULL) return -1;
  rc = g_cu.mem_free((unsigned long long)p);
  g_last_driver = rc;
  return (int32_t)rc;
}

int32_t cusparseb_dev_upload_f32(int64_t p, const float* src, int64_t count) {
  int rc;
  if (g_cu.memcpy_htod == NULL || src == NULL || count < 0) return -1;
  rc = g_cu.memcpy_htod((unsigned long long)p, src,
                        (unsigned long long)count * 4ULL);
  g_last_driver = rc;
  return (int32_t)rc;
}

int32_t cusparseb_dev_download_f32(int64_t p, float* dst, int64_t count) {
  int rc;
  if (g_cu.memcpy_dtoh == NULL || dst == NULL || count < 0) return -1;
  rc = g_cu.memcpy_dtoh(dst, (unsigned long long)p,
                        (unsigned long long)count * 4ULL);
  g_last_driver = rc;
  return (int32_t)rc;
}

int32_t cusparseb_dev_upload_f64(int64_t p, const double* src, int64_t count) {
  int rc;
  if (g_cu.memcpy_htod == NULL || src == NULL || count < 0) return -1;
  rc = g_cu.memcpy_htod((unsigned long long)p, src,
                        (unsigned long long)count * 8ULL);
  g_last_driver = rc;
  return (int32_t)rc;
}

int32_t cusparseb_dev_download_f64(int64_t p, double* dst, int64_t count) {
  int rc;
  if (g_cu.memcpy_dtoh == NULL || dst == NULL || count < 0) return -1;
  rc = g_cu.memcpy_dtoh(dst, (unsigned long long)p,
                        (unsigned long long)count * 8ULL);
  g_last_driver = rc;
  return (int32_t)rc;
}

int32_t cusparseb_dev_upload_i32(int64_t p, const int32_t* src, int64_t count) {
  int rc;
  if (g_cu.memcpy_htod == NULL || src == NULL || count < 0) return -1;
  rc = g_cu.memcpy_htod((unsigned long long)p, src,
                        (unsigned long long)count * 4ULL);
  g_last_driver = rc;
  return (int32_t)rc;
}

int32_t cusparseb_dev_download_i32(int64_t p, int32_t* dst, int64_t count) {
  int rc;
  if (g_cu.memcpy_dtoh == NULL || dst == NULL || count < 0) return -1;
  rc = g_cu.memcpy_dtoh(dst, (unsigned long long)p,
                        (unsigned long long)count * 4ULL);
  g_last_driver = rc;
  return (int32_t)rc;
}
