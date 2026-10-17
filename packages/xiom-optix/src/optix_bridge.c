/* XIOM -- xiom.optix: XIOM-side dynamic-loader bridge for the NVIDIA OptiX
 * ray-tracing runtime (nvoptix.dll).  Copyright (c) 2026 Eleftherios Notas
 * and The XIOM Authors.  SPDX-License-Identifier: MIT OR Apache-2.0
 *
 * This file is OUR code, not NVIDIA code.  It copies NOTHING from the OptiX
 * SDK and links NOTHING at build time.  The integration layer is the NVIDIA
 * driver's nvoptix.dll, loaded at run time from the user's own installation
 * (nothing is downloaded, copied, or committed).  See PROVENANCE.md for the
 * license finding (NVIDIA proprietary SDK, registration-gated download) and
 * the acquisition contract.
 *
 * ABI model (pinned by SPEC.md): OptiX 9.1 / OPTIX_ABI_VERSION 118.  The
 * only export of nvoptix.dll is optixQueryFunctionTable(); the table layout
 * below is an independent declaration of the interface facts published in
 * NVIDIA's official optix-dev header repository (tag v9.1.0, commit
 * f1f6dd803f3159992d248178f6e09421c6eb8b6d).  Only the slots the package
 * calls are named; the reserved slots keep the 60-pointer offsets exact.
 *
 * Return convention: 0 = success, -(100 + kind) = typed bridge error.  The
 * native OptixResult (if any) and a human message are available through
 * optixp_last_native() / optixp_last_error().  Handles are positive pointer
 * values; 0 is the absent/null sentinel (B-25: no integer-to-pointer casts
 * in XIOM -- all casts happen here).
 *
 * All state is single-threaded process state (documented constraint); the
 * suite is single-threaded.
 */

#define _CRT_SECURE_NO_WARNINGS

#include <windows.h>

#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* =========================================================================
 * Bridge status codes (kept in sync with optix.xi)
 * ========================================================================= */

#define OPX_E_LOADER 0
#define OPX_E_NODEV 1
#define OPX_E_ABI 2
#define OPX_E_ARG 3
#define OPX_E_CONTEXT 4
#define OPX_E_MODULE 5
#define OPX_E_PG 6
#define OPX_E_PIPELINE 7
#define OPX_E_SBT 8
#define OPX_E_PARAMS 9
#define OPX_E_LAUNCH 10
#define OPX_E_OOM 11
#define OPX_E_RUNTIME 12

#define OPX_MAGIC_CTX 0x4F505843u /* OPXC */
#define OPX_MAGIC_MOD 0x4F504D44u /* OPMD */
#define OPX_MAGIC_PG 0x4F505047u  /* OPPG */
#define OPX_MAGIC_SBT 0x4F505342u /* OPSB */
#define OPX_MAGIC_PIPE 0x4F50504Cu /* OPPL */
#define OPX_MAGIC_PARAMS 0x4F505052u /* OPPR */

/* =========================================================================
 * Pinned ABI constants (OptiX 9.1, optix_types.h @ v9.1.0)
 * ========================================================================= */

#define OPTIX_ABI_PIN 118
#define OPTIX_FN_COUNT 60

#define OPTIX_SUCCESS 0
#define OPTIX_ERROR_INVALID_VALUE 7001
#define OPTIX_ERROR_CUDA_NOT_INITIALIZED 7052
#define OPTIX_ERROR_UNSUPPORTED_ABI_VERSION 7801
#define OPTIX_ERROR_FUNCTION_TABLE_SIZE_MISMATCH 7802

#define OPTIX_DEVICE_PROPERTY_LIMIT_MAX_TRACE_DEPTH 0x2001
#define OPTIX_DEVICE_PROPERTY_RTCORE_VERSION 0x2005
#define OPTIX_TRAVERSABLE_GRAPH_FLAG_ALLOW_SINGLE_GAS 0x1u

#define OPTIX_PROGRAM_GROUP_KIND_RAYGEN 0x2421
#define OPTIX_PROGRAM_GROUP_KIND_MISS 0x2422
#define OPTIX_PROGRAM_GROUP_KIND_HITGROUP 0x2424

#define OPTIX_SBT_RECORD_HEADER_SIZE 32u
#define OPTIX_SBT_RECORD_ALIGNMENT 16u

/* Function-table slots used by this bridge.  The indices are the ABI facts
 * of optix_function_table.h @ v9.1.0; unused slots are reserved pointers. */
#define OPTF_ERR_NAME 0
#define OPTF_ERR_STRING 1
#define OPTF_CTX_CREATE 2
#define OPTF_CTX_DESTROY 3
#define OPTF_CTX_PROPERTY 4
#define OPTF_CACHE_ENABLE 6
#define OPTF_CACHE_LOCATION 7
#define OPTF_CACHE_GET_ENABLED 9
#define OPTF_MODULE_CREATE 12
#define OPTF_MODULE_DESTROY 18
#define OPTF_PG_CREATE 24
#define OPTF_PG_DESTROY 25
#define OPTF_PIPELINE_CREATE 27
#define OPTF_PIPELINE_DESTROY 28
#define OPTF_SBT_PACK 48
#define OPTF_LAUNCH 49

/* =========================================================================
 * ABI mirrors (x64 layouts, verified against the pinned headers)
 * ========================================================================= */

typedef int OptixResult;
typedef void* OptixDeviceContext;
typedef void* OptixModule;
typedef void* OptixProgramGroup;
typedef void* OptixPipeline;
typedef void* CUcontext;
typedef void* CUstream;
typedef unsigned long long CUdeviceptr;

typedef struct OptixDeviceContextOptions {
  void* logCallbackFunction;
  void* logCallbackData;
  int logCallbackLevel;
  int validationMode;
} OptixDeviceContextOptions;

typedef struct OptixModuleCompileOptions {
  int maxRegisterCount;
  int optLevel;
  int debugLevel;
  const void* boundValues;
  unsigned int numBoundValues;
  unsigned int numPayloadTypes;
  const void* payloadTypes;
  OptixModule baseModule;
} OptixModuleCompileOptions;

typedef struct OptixPipelineCompileOptions {
  int usesMotionBlur;
  unsigned int traversableGraphFlags;
  int numPayloadValues;
  int numAttributeValues;
  unsigned int exceptionFlags;
  const char* pipelineLaunchParamsVariableName;
  size_t pipelineLaunchParamsSizeInBytes;
  unsigned int usesPrimitiveTypeFlags;
  int allowOpacityMicromaps;
  int allowClusteredGeometry;
} OptixPipelineCompileOptions;

typedef struct OptixProgramGroupSingleModule {
  OptixModule module;
  const char* entryFunctionName;
} OptixProgramGroupSingleModule;

typedef struct OptixProgramGroupHitgroup {
  OptixModule moduleCH;
  const char* entryFunctionNameCH;
  OptixModule moduleAH;
  const char* entryFunctionNameAH;
  OptixModule moduleIS;
  const char* entryFunctionNameIS;
} OptixProgramGroupHitgroup;

typedef struct OptixProgramGroupDesc {
  int kind;
  unsigned int flags;
  union {
    OptixProgramGroupHitgroup hitgroup;
    OptixProgramGroupSingleModule raygen;
    OptixProgramGroupSingleModule miss;
    OptixProgramGroupSingleModule exception;
  };
} OptixProgramGroupDesc;

typedef struct OptixProgramGroupOptions {
  const void* payloadType;
} OptixProgramGroupOptions;

typedef struct OptixPipelineLinkOptions {
  unsigned int maxTraceDepth;
  unsigned int maxContinuationCallableDepth;
  unsigned int maxDirectCallableDepthFromState;
  unsigned int maxDirectCallableDepthFromTraversal;
  unsigned int maxTraversableGraphDepth;
} OptixPipelineLinkOptions;

typedef struct OptixShaderBindingTable {
  CUdeviceptr raygenRecord;
  CUdeviceptr exceptionRecord;
  CUdeviceptr missRecordBase;
  unsigned int missRecordStrideInBytes;
  unsigned int missRecordCount;
  CUdeviceptr hitgroupRecordBase;
  unsigned int hitgroupRecordStrideInBytes;
  unsigned int hitgroupRecordCount;
  CUdeviceptr callablesRecordBase;
  unsigned int callablesRecordStrideInBytes;
  unsigned int callablesRecordCount;
} OptixShaderBindingTable;

/* =========================================================================
 * Runtime entry-point types
 * ========================================================================= */

typedef OptixResult (*PFN_query)(int, unsigned int, void*, const void**, void*, size_t);
typedef const char* (*PFN_errname)(OptixResult);
typedef const char* (*PFN_errstr)(OptixResult);
typedef OptixResult (*PFN_ctx_create)(CUcontext, const OptixDeviceContextOptions*,
                                      OptixDeviceContext*);
typedef OptixResult (*PFN_ctx_destroy)(OptixDeviceContext);
typedef OptixResult (*PFN_ctx_property)(OptixDeviceContext, int, void*, size_t);
typedef OptixResult (*PFN_cache_enable)(OptixDeviceContext, int);
typedef OptixResult (*PFN_cache_location)(OptixDeviceContext, const char*);
typedef OptixResult (*PFN_cache_get_enabled)(OptixDeviceContext, int*);
typedef OptixResult (*PFN_module_create)(OptixDeviceContext,
                                         const OptixModuleCompileOptions*,
                                         const OptixPipelineCompileOptions*,
                                         const char*, size_t, char*, size_t*,
                                         OptixModule*);
typedef OptixResult (*PFN_module_destroy)(OptixModule);
typedef OptixResult (*PFN_pg_create)(OptixDeviceContext, const OptixProgramGroupDesc*,
                                     unsigned int, const OptixProgramGroupOptions*,
                                     char*, size_t*, OptixProgramGroup*);
typedef OptixResult (*PFN_pg_destroy)(OptixProgramGroup);
typedef OptixResult (*PFN_pipeline_create)(OptixDeviceContext,
                                           const OptixPipelineCompileOptions*,
                                           const OptixPipelineLinkOptions*,
                                           const OptixProgramGroup*, unsigned int,
                                           char*, size_t*, OptixPipeline*);
typedef OptixResult (*PFN_pipeline_destroy)(OptixPipeline);
typedef OptixResult (*PFN_sbt_pack)(OptixProgramGroup, void*);
typedef OptixResult (*PFN_launch)(OptixPipeline, CUstream, CUdeviceptr, size_t,
                                  const OptixShaderBindingTable*, unsigned int,
                                  unsigned int, unsigned int);

/* CUDA driver entry points (nvcuda.dll; no Toolkit or import library). */
typedef int (*PFN_cuInit)(unsigned int);
typedef int (*PFN_cuDeviceGetCount)(int*);
typedef int (*PFN_cuDeviceGet)(int*, int);
typedef int (*PFN_cuDeviceGetName)(char*, int, int);
typedef int (*PFN_cuCtxCreate_v2)(CUcontext*, unsigned int, int);
typedef int (*PFN_cuCtxDestroy_v2)(CUcontext);
typedef int (*PFN_cuCtxSynchronize)(void);
typedef int (*PFN_cuMemAlloc_v2)(CUdeviceptr*, size_t);
typedef int (*PFN_cuMemFree_v2)(CUdeviceptr);
typedef int (*PFN_cuMemcpyHtoD_v2)(CUdeviceptr, const void*, size_t);
typedef int (*PFN_cuMemcpyDtoH_v2)(void*, CUdeviceptr, size_t);

typedef struct CudaApi {
  HMODULE module;
  PFN_cuInit init;
  PFN_cuDeviceGetCount device_get_count;
  PFN_cuDeviceGet device_get;
  PFN_cuDeviceGetName device_get_name;
  PFN_cuCtxCreate_v2 ctx_create;
  PFN_cuCtxDestroy_v2 ctx_destroy;
  PFN_cuCtxSynchronize ctx_synchronize;
  PFN_cuMemAlloc_v2 mem_alloc;
  PFN_cuMemFree_v2 mem_free;
  PFN_cuMemcpyHtoD_v2 memcpy_htod;
  PFN_cuMemcpyDtoH_v2 memcpy_dtoh;
} CudaApi;

typedef struct OptixApi {
  HMODULE module;
  void* fn[OPTIX_FN_COUNT];
  CudaApi* cuda;
} OptixApi;

/* =========================================================================
 * Bridge state (single-threaded)
 * ========================================================================= */

static char g_error[1024];
static long long g_native;
static int g_abi;
static unsigned int g_rtcore;
static unsigned int g_max_trace_depth;
static int g_cache_enabled;
static char g_device_name[256];

static int opx_fail(int kind, const char* fmt, ...) {
  va_list ap;
  va_start(ap, fmt);
  vsnprintf(g_error, sizeof(g_error), fmt, ap);
  va_end(ap);
  g_native = 0;
  return -(100 + kind);
}

static int opx_native(int kind, OptixApi* api, OptixResult result,
                      const char* message) {
  const char* text = "unknown";
  if (api && api->fn[OPTF_ERR_STRING]) {
    text = ((PFN_errstr)api->fn[OPTF_ERR_STRING])(result);
  }
  snprintf(g_error, sizeof(g_error), "%s (optix=%d: %s)", message, (int)result,
           text ? text : "unknown");
  g_native = result;
  return -(100 + kind);
}

static int opx_native_log(int kind, OptixApi* api, OptixResult result,
                          const char* message, const char* log) {
  char tail[512];
  tail[0] = 0;
  if (log && log[0]) {
    snprintf(tail, sizeof(tail), " | %s", log);
  }
  const char* text = "unknown";
  if (api && api->fn[OPTF_ERR_STRING]) {
    text = ((PFN_errstr)api->fn[OPTF_ERR_STRING])(result);
  }
  snprintf(g_error, sizeof(g_error), "%s (optix=%d: %s)%s", message, (int)result,
           text ? text : "unknown", tail);
  g_native = result;
  return -(100 + kind);
}

/* =========================================================================
 * Loader
 * ========================================================================= */

static HMODULE opx_find_driverstore(void) {
  wchar_t windir[MAX_PATH];
  if (!GetWindowsDirectoryW(windir, MAX_PATH)) return 0;

  wchar_t repo[MAX_PATH * 2];
  _snwprintf(repo, MAX_PATH * 2, L"%s\\System32\\DriverStore\\FileRepository",
             windir);
  repo[MAX_PATH * 2 - 1] = 0;

  wchar_t pattern[MAX_PATH * 2 + 64];
  _snwprintf(pattern, MAX_PATH * 2 + 64, L"%s\\nv_dispi.inf_amd64_*", repo);
  pattern[MAX_PATH * 2 + 63] = 0;

  WIN32_FIND_DATAW data;
  HANDLE handle = FindFirstFileW(pattern, &data);
  if (handle == INVALID_HANDLE_VALUE) return 0;

  wchar_t best[MAX_PATH * 4];
  best[0] = 0;
  FILETIME best_time;
  memset(&best_time, 0, sizeof(best_time));
  int scanned = 0;

  do {
    if (!(data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)) continue;
    if (scanned++ > 1024) break;

    wchar_t candidate[MAX_PATH * 4];
    _snwprintf(candidate, MAX_PATH * 4, L"%s\\%s\\nvoptix.dll", repo,
               data.cFileName);
    candidate[MAX_PATH * 4 - 1] = 0;
    if (GetFileAttributesW(candidate) == INVALID_FILE_ATTRIBUTES) continue;

    if (CompareFileTime(&data.ftLastWriteTime, &best_time) >= 0) {
      best_time = data.ftLastWriteTime;
      lstrcpynW(best, candidate, MAX_PATH * 4);
    }
  } while (FindNextFileW(handle, &data));
  FindClose(handle);

  if (!best[0]) return 0;
  return LoadLibraryW(best);
}

static HMODULE opx_find_optix(const char* explicit_path) {
  if (explicit_path && explicit_path[0]) {
    return LoadLibraryA(explicit_path);
  }

  /* Test/diagnostic switch: prove the deterministic SKIP path on a host that
   * does have a driver runtime.  Explicit paths still work. */
  const char* no_auto = getenv("XIOM_OPTIX_NO_AUTO");
  if (no_auto && no_auto[0]) return 0;

  const char* env = getenv("XIOM_OPTIX_DLL");
  if (env && env[0]) {
    HMODULE h = LoadLibraryA(env);
    if (h) return h;
  }

  HMODULE h = LoadLibraryA("nvoptix.dll");
  if (h) return h;

  const char* roots[2];
  roots[0] = getenv("ProgramFiles");
  roots[1] = getenv("ProgramW6432");
  for (int i = 0; i < 2; i++) {
    if (!roots[i] || !roots[i][0]) continue;
    char path[1024];
    snprintf(path, sizeof(path), "%s\\NVIDIA Corporation\\OptiX\\bin\\nvoptix.dll",
             roots[i]);
    h = LoadLibraryA(path);
    if (h) return h;
  }

  const char* sysroot = getenv("SystemRoot");
  if (sysroot && sysroot[0]) {
    char path[1024];
    snprintf(path, sizeof(path), "%s\\System32\\nvoptix.dll", sysroot);
    h = LoadLibraryA(path);
    if (h) return h;
  }

  return opx_find_driverstore();
}

static int opx_api_load(OptixApi* api, const char* explicit_path, int need_cuda) {
  memset(api, 0, sizeof(*api));
  g_abi = OPTIX_ABI_PIN;
  g_rtcore = 0;
  g_max_trace_depth = 0;
  g_cache_enabled = 0;
  g_device_name[0] = 0;

  HMODULE module = opx_find_optix(explicit_path);
  if (!module) {
    return opx_fail(OPX_E_LOADER,
                    "nvoptix.dll not found (user-supplied NVIDIA driver runtime; "
                    "set XIOM_OPTIX_DLL or install an R590+ display driver)");
  }
  api->module = module;

  PFN_query query =
      (PFN_query)(void*)GetProcAddress(module, "optixQueryFunctionTable");
  if (!query) {
    FreeLibrary(module);
    api->module = 0;
    return opx_fail(OPX_E_ABI, "nvoptix.dll does not export optixQueryFunctionTable");
  }

  OptixResult result =
      query(OPTIX_ABI_PIN, 0, 0, 0, api->fn, sizeof(api->fn));
  if (result != OPTIX_SUCCESS) {
    FreeLibrary(module);
    api->module = 0;
    if (result == OPTIX_ERROR_UNSUPPORTED_ABI_VERSION ||
        result == OPTIX_ERROR_FUNCTION_TABLE_SIZE_MISMATCH) {
      return opx_fail(OPX_E_ABI,
                      "OptiX ABI mismatch (need ABI %d; update the display driver)",
                      OPTIX_ABI_PIN);
    }
    return opx_fail(OPX_E_ABI, "optixQueryFunctionTable failed with OptiX code %d",
                    (int)result);
  }

  if (!need_cuda) return 0;

  CudaApi* cuda = (CudaApi*)calloc(1, sizeof(CudaApi));
  if (!cuda) {
    FreeLibrary(module);
    api->module = 0;
    return opx_fail(OPX_E_OOM, "out of memory");
  }
  cuda->module = LoadLibraryA("nvcuda.dll");
  if (!cuda->module) {
    free(cuda);
    FreeLibrary(module);
    api->module = 0;
    return opx_fail(OPX_E_LOADER,
                    "nvcuda.dll not found (NVIDIA display driver required)");
  }
  cuda->init = (PFN_cuInit)(void*)GetProcAddress(cuda->module, "cuInit");
  cuda->device_get_count =
      (PFN_cuDeviceGetCount)(void*)GetProcAddress(cuda->module, "cuDeviceGetCount");
  cuda->device_get =
      (PFN_cuDeviceGet)(void*)GetProcAddress(cuda->module, "cuDeviceGet");
  cuda->device_get_name =
      (PFN_cuDeviceGetName)(void*)GetProcAddress(cuda->module, "cuDeviceGetName");
  cuda->ctx_create =
      (PFN_cuCtxCreate_v2)(void*)GetProcAddress(cuda->module, "cuCtxCreate_v2");
  cuda->ctx_destroy =
      (PFN_cuCtxDestroy_v2)(void*)GetProcAddress(cuda->module, "cuCtxDestroy_v2");
  cuda->ctx_synchronize =
      (PFN_cuCtxSynchronize)(void*)GetProcAddress(cuda->module, "cuCtxSynchronize");
  cuda->mem_alloc =
      (PFN_cuMemAlloc_v2)(void*)GetProcAddress(cuda->module, "cuMemAlloc_v2");
  cuda->mem_free =
      (PFN_cuMemFree_v2)(void*)GetProcAddress(cuda->module, "cuMemFree_v2");
  cuda->memcpy_htod =
      (PFN_cuMemcpyHtoD_v2)(void*)GetProcAddress(cuda->module, "cuMemcpyHtoD_v2");
  cuda->memcpy_dtoh =
      (PFN_cuMemcpyDtoH_v2)(void*)GetProcAddress(cuda->module, "cuMemcpyDtoH_v2");

  int complete = cuda->init && cuda->device_get_count && cuda->device_get &&
                 cuda->device_get_name && cuda->ctx_create &&
                 cuda->ctx_destroy && cuda->ctx_synchronize &&
                 cuda->mem_alloc && cuda->mem_free && cuda->memcpy_htod &&
                 cuda->memcpy_dtoh;
  if (!complete) {
    FreeLibrary(cuda->module);
    free(cuda);
    FreeLibrary(module);
    api->module = 0;
    return opx_fail(OPX_E_ABI, "nvcuda.dll is missing required driver entry points");
  }

  api->cuda = cuda;
  return 0;
}

static void opx_api_unload(OptixApi* api) {
  if (api->cuda) {
    if (api->cuda->module) FreeLibrary(api->cuda->module);
    free(api->cuda);
  }
  if (api->module) FreeLibrary(api->module);
  memset(api, 0, sizeof(*api));
}

static CudaApi* opx_cuda(OptixApi* api) { return api->cuda; }

/* =========================================================================
 * Handles
 * ========================================================================= */

typedef struct OpCtx {
  uint32_t magic;
  OptixApi api;
  CudaApi* cuda;
  CUcontext cuda_context;
  OptixDeviceContext context;
  int cache_enabled;
  int device_index;
  char device_name[256];
} OpCtx;

typedef struct OpModule {
  uint32_t magic;
  OpCtx* owner;
  OptixModule module;
} OpModule;

typedef struct OpPg {
  uint32_t magic;
  OpCtx* owner;
  OptixProgramGroup group;
  int kind;
} OpPg;

typedef struct OpSbt {
  uint32_t magic;
  OpCtx* owner;
  CUdeviceptr device_records;
  size_t total_size;
  unsigned int record_size;
  unsigned int raygen_count;
  unsigned int miss_count;
  unsigned int hitgroup_count;
  OptixShaderBindingTable table;
} OpSbt;

typedef struct OpPipeline {
  uint32_t magic;
  OpCtx* owner;
  OptixPipeline pipeline;
} OpPipeline;

typedef struct OpParams {
  uint32_t magic;
  OpCtx* owner;
  CUdeviceptr device_ptr;
  size_t size;
} OpParams;

static OpCtx* opx_ctx(long long handle) {
  OpCtx* ctx = (OpCtx*)(intptr_t)handle;
  if (!ctx || ctx->magic != OPX_MAGIC_CTX) return 0;
  return ctx;
}

static OpModule* opx_module(long long handle) {
  OpModule* module = (OpModule*)(intptr_t)handle;
  if (!module || module->magic != OPX_MAGIC_MOD) return 0;
  return module;
}

static OpPg* opx_pg(long long handle) {
  OpPg* pg = (OpPg*)(intptr_t)handle;
  if (!pg || pg->magic != OPX_MAGIC_PG) return 0;
  return pg;
}

static OpSbt* opx_sbt(long long handle) {
  OpSbt* sbt = (OpSbt*)(intptr_t)handle;
  if (!sbt || sbt->magic != OPX_MAGIC_SBT) return 0;
  return sbt;
}

static OpPipeline* opx_pipeline(long long handle) {
  OpPipeline* pipeline = (OpPipeline*)(intptr_t)handle;
  if (!pipeline || pipeline->magic != OPX_MAGIC_PIPE) return 0;
  return pipeline;
}

static OpParams* opx_params(long long handle) {
  OpParams* params = (OpParams*)(intptr_t)handle;
  if (!params || params->magic != OPX_MAGIC_PARAMS) return 0;
  return params;
}

/* =========================================================================
 * Context
 * ========================================================================= */

static long long opx_ctx_create_impl(const char* dll_path, int validation_mode,
                                     int log_level, int cache_enabled,
                                     const char* cache_location) {
  if (log_level < 0 || log_level > 4) {
    return opx_fail(OPX_E_ARG, "log level must be in [0, 4]");
  }

  OpCtx* ctx = (OpCtx*)calloc(1, sizeof(OpCtx));
  if (!ctx) return opx_fail(OPX_E_OOM, "out of memory");

  int rc = opx_api_load(&ctx->api, dll_path, 1);
  if (rc != 0) {
    free(ctx);
    return rc;
  }
  ctx->cuda = opx_cuda(&ctx->api);

  if (ctx->cuda->init(0) != 0) {
    opx_api_unload(&ctx->api);
    free(ctx);
    return opx_fail(OPX_E_NODEV, "cuInit failed (no usable NVIDIA GPU)");
  }
  int count = 0;
  if (ctx->cuda->device_get_count(&count) != 0 || count < 1) {
    opx_api_unload(&ctx->api);
    free(ctx);
    return opx_fail(OPX_E_NODEV, "no CUDA device");
  }
  if (ctx->cuda->device_get(&ctx->device_index, 0) != 0) {
    opx_api_unload(&ctx->api);
    free(ctx);
    return opx_fail(OPX_E_NODEV, "cuDeviceGet(0) failed");
  }
  if (ctx->cuda->ctx_create(&ctx->cuda_context, 0, ctx->device_index) != 0) {
    opx_api_unload(&ctx->api);
    free(ctx);
    return opx_fail(OPX_E_CONTEXT, "cuCtxCreate failed");
  }

  OptixDeviceContextOptions options;
  memset(&options, 0, sizeof(options));
  options.logCallbackFunction = 0;
  options.logCallbackData = 0;
  options.logCallbackLevel = log_level;
  options.validationMode = validation_mode ? 0xFFFFFFFF : 0;

  OptixResult result = ((PFN_ctx_create)ctx->api.fn[OPTF_CTX_CREATE])(
      ctx->cuda_context, &options, &ctx->context);
  if (result != OPTIX_SUCCESS) {
    ctx->cuda->ctx_destroy(ctx->cuda_context);
    int kind = (result == OPTIX_ERROR_CUDA_NOT_INITIALIZED) ? OPX_E_NODEV
                                                            : OPX_E_CONTEXT;
    rc = opx_native(kind, &ctx->api, result, "optixDeviceContextCreate failed");
    opx_api_unload(&ctx->api);
    free(ctx);
    return rc;
  }

  if (cache_location && cache_location[0]) {
    result = ((PFN_cache_location)ctx->api.fn[OPTF_CACHE_LOCATION])(
        ctx->context, cache_location);
    if (result != OPTIX_SUCCESS) {
      ((PFN_ctx_destroy)ctx->api.fn[OPTF_CTX_DESTROY])(ctx->context);
      ctx->cuda->ctx_destroy(ctx->cuda_context);
      rc = opx_native(OPX_E_CONTEXT, &ctx->api, result,
                      "optixDeviceContextSetCacheLocation failed");
      opx_api_unload(&ctx->api);
      free(ctx);
      return rc;
    }
  }

  ((PFN_cache_enable)ctx->api.fn[OPTF_CACHE_ENABLE])(ctx->context,
                                                    cache_enabled ? 1 : 0);
  int enabled = 0;
  ((PFN_cache_get_enabled)ctx->api.fn[OPTF_CACHE_GET_ENABLED])(ctx->context,
                                                              &enabled);
  ctx->cache_enabled = enabled;

  if (ctx->cuda->device_get_name(ctx->device_name, (int)sizeof(ctx->device_name),
                                 ctx->device_index) == 0) {
    ctx->device_name[sizeof(ctx->device_name) - 1] = 0;
  }

  ctx->magic = OPX_MAGIC_CTX;
  g_abi = OPTIX_ABI_PIN;
  g_cache_enabled = ctx->cache_enabled;
  lstrcpynA(g_device_name, ctx->device_name, (int)sizeof(g_device_name));
  return (long long)(intptr_t)ctx;
}

long long optixp_ctx_create(int validation_mode, int log_level,
                            int cache_enabled, const char* cache_location) {
  return opx_ctx_create_impl(0, validation_mode, log_level, cache_enabled,
                             cache_location);
}

int optixp_ctx_validate(long long handle) {
  OpCtx* ctx = opx_ctx(handle);
  if (!ctx) return opx_fail(OPX_E_ARG, "invalid OptixContext handle");

  unsigned int value = 0;
  OptixResult result = ((PFN_ctx_property)ctx->api.fn[OPTF_CTX_PROPERTY])(
      ctx->context, OPTIX_DEVICE_PROPERTY_RTCORE_VERSION, &value, sizeof(value));
  if (result != OPTIX_SUCCESS) {
    return opx_native(OPX_E_CONTEXT, &ctx->api, result,
                      "optixDeviceContextGetProperty(RTCORE_VERSION) failed");
  }
  g_rtcore = value;

  value = 0;
  result = ((PFN_ctx_property)ctx->api.fn[OPTF_CTX_PROPERTY])(
      ctx->context, OPTIX_DEVICE_PROPERTY_LIMIT_MAX_TRACE_DEPTH, &value,
      sizeof(value));
  if (result != OPTIX_SUCCESS) {
    return opx_native(OPX_E_CONTEXT, &ctx->api, result,
                      "optixDeviceContextGetProperty(MAX_TRACE_DEPTH) failed");
  }
  g_max_trace_depth = value;

  int enabled = 0;
  if (((PFN_cache_get_enabled)ctx->api.fn[OPTF_CACHE_GET_ENABLED])(
          ctx->context, &enabled) == OPTIX_SUCCESS) {
    g_cache_enabled = enabled;
  } else {
    g_cache_enabled = ctx->cache_enabled;
  }
  g_abi = OPTIX_ABI_PIN;
  lstrcpynA(g_device_name, ctx->device_name, (int)sizeof(g_device_name));
  return 0;
}

int optixp_ctx_destroy(long long handle) {
  OpCtx* ctx = opx_ctx(handle);
  if (!ctx) return opx_fail(OPX_E_ARG, "invalid OptixContext handle");

  OptixResult result = ((PFN_ctx_destroy)ctx->api.fn[OPTF_CTX_DESTROY])(
      ctx->context);
  int rc = 0;
  if (result != OPTIX_SUCCESS) {
    rc = opx_native(OPX_E_CONTEXT, &ctx->api, result,
                    "optixDeviceContextDestroy failed");
  }
  if (ctx->cuda_context) ctx->cuda->ctx_destroy(ctx->cuda_context);
  ctx->magic = 0;
  opx_api_unload(&ctx->api);
  free(ctx);
  return rc;
}

/* =========================================================================
 * Module
 * ========================================================================= */

long long optixp_module_load(long long ctx_handle, const char* ptx,
                             long long ptx_size, const char* params_name,
                             long long params_size) {
  OpCtx* ctx = opx_ctx(ctx_handle);
  if (!ctx) return opx_fail(OPX_E_ARG, "invalid OptixContext handle");
  if (!ptx || ptx_size <= 0) return opx_fail(OPX_E_ARG, "PTX input is empty");
  if (params_size < 0 || params_size > (long long)(1u << 30)) {
    return opx_fail(OPX_E_ARG, "launch params size out of range");
  }
  if (params_size > 0 && (!params_name || !params_name[0])) {
    return opx_fail(OPX_E_ARG, "launch params name is required when size > 0");
  }

  OptixModuleCompileOptions module_options;
  memset(&module_options, 0, sizeof(module_options));

  OptixPipelineCompileOptions pipeline_options;
  memset(&pipeline_options, 0, sizeof(pipeline_options));
  pipeline_options.traversableGraphFlags =
      OPTIX_TRAVERSABLE_GRAPH_FLAG_ALLOW_SINGLE_GAS;
  pipeline_options.numPayloadValues = 2;
  pipeline_options.numAttributeValues = 2;
  pipeline_options.pipelineLaunchParamsVariableName =
      params_size > 0 ? params_name : 0;
  pipeline_options.pipelineLaunchParamsSizeInBytes = (size_t)params_size;

  char log[4096];
  log[0] = 0;
  size_t log_size = sizeof(log);
  OptixModule module = 0;
  OptixResult result = ((PFN_module_create)ctx->api.fn[OPTF_MODULE_CREATE])(
      ctx->context, &module_options, &pipeline_options, ptx, (size_t)ptx_size,
      log, &log_size, &module);
  if (result != OPTIX_SUCCESS) {
    return opx_native_log(OPX_E_MODULE, &ctx->api, result,
                          "optixModuleCreate failed", log);
  }

  OpModule* handle = (OpModule*)calloc(1, sizeof(OpModule));
  if (!handle) {
    ((PFN_module_destroy)ctx->api.fn[OPTF_MODULE_DESTROY])(module);
    return opx_fail(OPX_E_OOM, "out of memory");
  }
  handle->magic = OPX_MAGIC_MOD;
  handle->owner = ctx;
  handle->module = module;
  return (long long)(intptr_t)handle;
}

int optixp_module_destroy(long long handle) {
  OpModule* module = opx_module(handle);
  if (!module) return opx_fail(OPX_E_ARG, "invalid OptixModule handle");
  OptixResult result =
      ((PFN_module_destroy)module->owner->api.fn[OPTF_MODULE_DESTROY])(
          module->module);
  module->magic = 0;
  free(module);
  if (result != OPTIX_SUCCESS) {
    return opx_fail(OPX_E_RUNTIME, "optixModuleDestroy failed with code %d",
                    (int)result);
  }
  return 0;
}

/* =========================================================================
 * Program group
 * ========================================================================= */

long long optixp_pg_create(long long ctx_handle, long long module_handle,
                           const char* entry, int kind) {
  OpCtx* ctx = opx_ctx(ctx_handle);
  if (!ctx) return opx_fail(OPX_E_ARG, "invalid OptixContext handle");

  OpModule* module = 0;
  if (module_handle != 0) {
    module = opx_module(module_handle);
    if (!module) return opx_fail(OPX_E_ARG, "invalid OptixModule handle");
    if (module->owner != ctx) {
      return opx_fail(OPX_E_ARG, "module belongs to a different context");
    }
  }

  if (!entry) entry = "";
  OptixProgramGroupDesc desc;
  memset(&desc, 0, sizeof(desc));

  if (kind == 0) {
    if (!module || !entry[0]) {
      return opx_fail(OPX_E_ARG, "raygen needs a module and an entry point");
    }
    desc.kind = OPTIX_PROGRAM_GROUP_KIND_RAYGEN;
    desc.raygen.module = module->module;
    desc.raygen.entryFunctionName = entry;
  } else if (kind == 1) {
    desc.kind = OPTIX_PROGRAM_GROUP_KIND_MISS;
    if (module) {
      if (!entry[0]) {
        return opx_fail(OPX_E_ARG,
                        "miss group with a module needs an entry point");
      }
      desc.miss.module = module->module;
      desc.miss.entryFunctionName = entry;
    }
  } else if (kind == 2) {
    if (!module || !entry[0]) {
      return opx_fail(OPX_E_ARG, "hitgroup needs a module and a CH entry point");
    }
    desc.kind = OPTIX_PROGRAM_GROUP_KIND_HITGROUP;
    desc.hitgroup.moduleCH = module->module;
    desc.hitgroup.entryFunctionNameCH = entry;
  } else {
    return opx_fail(OPX_E_ARG, "program group kind must be 0 (raygen), 1 (miss), or 2 (hitgroup)");
  }

  OptixProgramGroupOptions options;
  memset(&options, 0, sizeof(options));
  char log[4096];
  log[0] = 0;
  size_t log_size = sizeof(log);
  OptixProgramGroup group = 0;
  OptixResult result = ((PFN_pg_create)ctx->api.fn[OPTF_PG_CREATE])(
      ctx->context, &desc, 1, &options, log, &log_size, &group);
  if (result != OPTIX_SUCCESS) {
    return opx_native_log(OPX_E_PG, &ctx->api, result,
                          "optixProgramGroupCreate failed", log);
  }

  OpPg* handle = (OpPg*)calloc(1, sizeof(OpPg));
  if (!handle) {
    ((PFN_pg_destroy)ctx->api.fn[OPTF_PG_DESTROY])(group);
    return opx_fail(OPX_E_OOM, "out of memory");
  }
  handle->magic = OPX_MAGIC_PG;
  handle->owner = ctx;
  handle->group = group;
  handle->kind = kind;
  return (long long)(intptr_t)handle;
}

int optixp_pg_destroy(long long handle) {
  OpPg* pg = opx_pg(handle);
  if (!pg) return opx_fail(OPX_E_ARG, "invalid OptixProgramGroup handle");
  OptixResult result = ((PFN_pg_destroy)pg->owner->api.fn[OPTF_PG_DESTROY])(
      pg->group);
  pg->magic = 0;
  free(pg);
  if (result != OPTIX_SUCCESS) {
    return opx_fail(OPX_E_RUNTIME, "optixProgramGroupDestroy failed with code %d",
                    (int)result);
  }
  return 0;
}

/* =========================================================================
 * Shader binding table
 * ========================================================================= */

long long optixp_sbt_build(long long ctx_handle, long long raygen_handle,
                           long long miss_handle, long long hit_handle,
                           int requested_record_size) {
  OpCtx* ctx = opx_ctx(ctx_handle);
  if (!ctx) return opx_fail(OPX_E_ARG, "invalid OptixContext handle");
  if (requested_record_size <= 0 || requested_record_size > (1 << 20)) {
    return opx_fail(OPX_E_ARG, "SBT record size out of range");
  }

  OpPg* raygen = 0;
  OpPg* miss = 0;
  OpPg* hit = 0;
  if (raygen_handle) {
    raygen = opx_pg(raygen_handle);
    if (!raygen) return opx_fail(OPX_E_ARG, "invalid raygen program group");
    if (raygen->owner != ctx || raygen->kind != 0) {
      return opx_fail(OPX_E_ARG, "raygen group belongs to a different context");
    }
  }
  if (miss_handle) {
    miss = opx_pg(miss_handle);
    if (!miss) return opx_fail(OPX_E_ARG, "invalid miss program group");
    if (miss->owner != ctx || miss->kind != 1) {
      return opx_fail(OPX_E_ARG, "miss group belongs to a different context");
    }
  }
  if (hit_handle) {
    hit = opx_pg(hit_handle);
    if (!hit) return opx_fail(OPX_E_ARG, "invalid hitgroup");
    if (hit->owner != ctx || hit->kind != 2) {
      return opx_fail(OPX_E_ARG, "hitgroup belongs to a different context");
    }
  }

  unsigned int raygen_count = raygen ? 1u : 0u;
  unsigned int miss_count = miss ? 1u : 0u;
  unsigned int hit_count = hit ? 1u : 0u;
  unsigned int total_records = raygen_count + miss_count + hit_count;
  if (total_records == 0) {
    return opx_fail(OPX_E_ARG, "SBT needs at least one program group");
  }

  unsigned int record_size = (unsigned int)requested_record_size;
  if (record_size < OPTIX_SBT_RECORD_HEADER_SIZE) {
    record_size = OPTIX_SBT_RECORD_HEADER_SIZE;
  }
  record_size =
      (record_size + OPTIX_SBT_RECORD_ALIGNMENT - 1) & ~(OPTIX_SBT_RECORD_ALIGNMENT - 1);

  size_t total_size = (size_t)record_size * total_records;
  unsigned char* host = (unsigned char*)calloc(total_size, 1);
  if (!host) return opx_fail(OPX_E_OOM, "out of memory");

  unsigned int offset = 0;
  OptixResult result = OPTIX_SUCCESS;
  if (raygen) {
    result = ((PFN_sbt_pack)ctx->api.fn[OPTF_SBT_PACK])(raygen->group,
                                                        host + offset);
    offset += record_size;
  }
  if (result == OPTIX_SUCCESS && miss) {
    result = ((PFN_sbt_pack)ctx->api.fn[OPTF_SBT_PACK])(miss->group,
                                                        host + offset);
    offset += record_size;
  }
  if (result == OPTIX_SUCCESS && hit) {
    result = ((PFN_sbt_pack)ctx->api.fn[OPTF_SBT_PACK])(hit->group,
                                                        host + offset);
  }
  if (result != OPTIX_SUCCESS) {
    free(host);
    return opx_native(OPX_E_SBT, &ctx->api, result,
                      "optixSbtRecordPackHeader failed");
  }

  CUdeviceptr device = 0;
  if (ctx->cuda->mem_alloc(&device, total_size) != 0) {
    free(host);
    return opx_fail(OPX_E_OOM, "cuMemAlloc failed for the SBT");
  }
  if (ctx->cuda->memcpy_htod(device, host, total_size) != 0) {
    ctx->cuda->mem_free(device);
    free(host);
    return opx_fail(OPX_E_SBT, "cuMemcpyHtoD failed for the SBT");
  }
  free(host);

  OpSbt* handle = (OpSbt*)calloc(1, sizeof(OpSbt));
  if (!handle) {
    ctx->cuda->mem_free(device);
    return opx_fail(OPX_E_OOM, "out of memory");
  }
  handle->magic = OPX_MAGIC_SBT;
  handle->owner = ctx;
  handle->device_records = device;
  handle->total_size = total_size;
  handle->record_size = record_size;
  handle->raygen_count = raygen_count;
  handle->miss_count = miss_count;
  handle->hitgroup_count = hit_count;

  handle->table.raygenRecord = raygen ? device : 0;
  handle->table.exceptionRecord = 0;
  if (miss) {
    handle->table.missRecordBase = device + (CUdeviceptr)(raygen_count * record_size);
    handle->table.missRecordStrideInBytes = record_size;
    handle->table.missRecordCount = miss_count;
  }
  if (hit) {
    handle->table.hitgroupRecordBase =
        device + (CUdeviceptr)((raygen_count + miss_count) * record_size);
    handle->table.hitgroupRecordStrideInBytes = record_size;
    handle->table.hitgroupRecordCount = hit_count;
  }
  return (long long)(intptr_t)handle;
}

int optixp_sbt_destroy(long long handle) {
  OpSbt* sbt = opx_sbt(handle);
  if (!sbt) return opx_fail(OPX_E_ARG, "invalid OptixSbt handle");
  sbt->owner->cuda->mem_free(sbt->device_records);
  sbt->magic = 0;
  free(sbt);
  return 0;
}

int optixp_sbt_record_size(long long handle) {
  OpSbt* sbt = opx_sbt(handle);
  if (!sbt) return opx_fail(OPX_E_ARG, "invalid OptixSbt handle");
  return (int)sbt->record_size;
}

int optixp_sbt_record_count(long long handle) {
  OpSbt* sbt = opx_sbt(handle);
  if (!sbt) return opx_fail(OPX_E_ARG, "invalid OptixSbt handle");
  return (int)(sbt->raygen_count + sbt->miss_count + sbt->hitgroup_count);
}

int optixp_sbt_read_record(long long handle, int index, char* out,
                           long long out_size) {
  OpSbt* sbt = opx_sbt(handle);
  if (!sbt) return opx_fail(OPX_E_ARG, "invalid OptixSbt handle");
  int count = (int)(sbt->raygen_count + sbt->miss_count + sbt->hitgroup_count);
  if (!out || out_size <= 0 || index < 0 || index >= count ||
      (size_t)out_size > sbt->record_size) {
    return opx_fail(OPX_E_ARG, "SBT record read out of range");
  }
  if (sbt->owner->cuda->memcpy_dtoh(out, sbt->device_records +
                                            (CUdeviceptr)(index * sbt->record_size),
                                    (size_t)out_size) != 0) {
    return opx_fail(OPX_E_SBT, "cuMemcpyDtoH failed for the SBT");
  }
  return 0;
}

/* =========================================================================
 * Pipeline
 * ========================================================================= */

long long optixp_pipeline_create(long long ctx_handle, long long raygen_handle,
                                 long long miss_handle, long long hit_handle,
                                 const char* params_name, long long params_size,
                                 int max_trace_depth) {
  OpCtx* ctx = opx_ctx(ctx_handle);
  if (!ctx) return opx_fail(OPX_E_ARG, "invalid OptixContext handle");
  if (params_size < 0 || params_size > (long long)(1u << 30)) {
    return opx_fail(OPX_E_ARG, "launch params size out of range");
  }
  if (params_size > 0 && (!params_name || !params_name[0])) {
    return opx_fail(OPX_E_ARG, "launch params name is required when size > 0");
  }
  if (max_trace_depth < 0 || max_trace_depth > 31) {
    return opx_fail(OPX_E_ARG, "max trace depth must be in [0, 31]");
  }

  OpPg* groups[3] = {0, 0, 0};
  long long handles[3] = {raygen_handle, miss_handle, hit_handle};
  int expected_kind[3] = {0, 1, 2};
  const char* names[3] = {"raygen", "miss", "hitgroup"};
  int count = 0;
  for (int i = 0; i < 3; i++) {
    if (!handles[i]) continue;
    OpPg* pg = opx_pg(handles[i]);
    if (!pg) return opx_fail(OPX_E_ARG, "invalid program group handle");
    if (pg->owner != ctx || pg->kind != expected_kind[i]) {
      return opx_fail(OPX_E_ARG, "program group kind/context mismatch for %s",
                      names[i]);
    }
    groups[count++] = pg;
  }
  if (count == 0) {
    return opx_fail(OPX_E_ARG, "pipeline needs at least one program group");
  }

  OptixProgramGroup raw[3];
  for (int i = 0; i < count; i++) raw[i] = groups[i]->group;

  OptixPipelineCompileOptions pipeline_options;
  memset(&pipeline_options, 0, sizeof(pipeline_options));
  pipeline_options.traversableGraphFlags =
      OPTIX_TRAVERSABLE_GRAPH_FLAG_ALLOW_SINGLE_GAS;
  pipeline_options.numPayloadValues = 2;
  pipeline_options.numAttributeValues = 2;
  pipeline_options.pipelineLaunchParamsVariableName =
      params_size > 0 ? params_name : 0;
  pipeline_options.pipelineLaunchParamsSizeInBytes = (size_t)params_size;

  OptixPipelineLinkOptions link_options;
  memset(&link_options, 0, sizeof(link_options));
  link_options.maxTraceDepth = (unsigned int)max_trace_depth;
  link_options.maxTraversableGraphDepth = 1;

  char log[4096];
  log[0] = 0;
  size_t log_size = sizeof(log);
  OptixPipeline pipeline = 0;
  OptixResult result = ((PFN_pipeline_create)ctx->api.fn[OPTF_PIPELINE_CREATE])(
      ctx->context, &pipeline_options, &link_options, raw, (unsigned int)count,
      log, &log_size, &pipeline);
  if (result != OPTIX_SUCCESS) {
    return opx_native_log(OPX_E_PIPELINE, &ctx->api, result,
                          "optixPipelineCreate failed", log);
  }

  OpPipeline* handle = (OpPipeline*)calloc(1, sizeof(OpPipeline));
  if (!handle) {
    ((PFN_pipeline_destroy)ctx->api.fn[OPTF_PIPELINE_DESTROY])(pipeline);
    return opx_fail(OPX_E_OOM, "out of memory");
  }
  handle->magic = OPX_MAGIC_PIPE;
  handle->owner = ctx;
  handle->pipeline = pipeline;
  return (long long)(intptr_t)handle;
}

int optixp_pipeline_destroy(long long handle) {
  OpPipeline* pipeline = opx_pipeline(handle);
  if (!pipeline) return opx_fail(OPX_E_ARG, "invalid OptixPipeline handle");
  OptixResult result =
      ((PFN_pipeline_destroy)pipeline->owner->api.fn[OPTF_PIPELINE_DESTROY])(
          pipeline->pipeline);
  pipeline->magic = 0;
  free(pipeline);
  if (result != OPTIX_SUCCESS) {
    return opx_fail(OPX_E_RUNTIME, "optixPipelineDestroy failed with code %d",
                    (int)result);
  }
  return 0;
}

/* =========================================================================
 * Launch params buffer
 * ========================================================================= */

long long optixp_params_create(long long ctx_handle, long long size) {
  OpCtx* ctx = opx_ctx(ctx_handle);
  if (!ctx) return opx_fail(OPX_E_ARG, "invalid OptixContext handle");
  if (size <= 0 || size > (long long)(1u << 30)) {
    return opx_fail(OPX_E_ARG, "launch params size out of range");
  }

  OpParams* params = (OpParams*)calloc(1, sizeof(OpParams));
  if (!params) return opx_fail(OPX_E_OOM, "out of memory");
  if (ctx->cuda->mem_alloc(&params->device_ptr, (size_t)size) != 0) {
    free(params);
    return opx_fail(OPX_E_OOM, "cuMemAlloc failed for launch params");
  }
  params->magic = OPX_MAGIC_PARAMS;
  params->owner = ctx;
  params->size = (size_t)size;
  return (long long)(intptr_t)params;
}

int optixp_params_write(long long handle, const char* data, long long size) {
  OpParams* params = opx_params(handle);
  if (!params) return opx_fail(OPX_E_ARG, "invalid OptixParams handle");
  if (!data || size <= 0 || (size_t)size > params->size) {
    return opx_fail(OPX_E_ARG, "launch params write out of range");
  }
  if (params->owner->cuda->memcpy_htod(params->device_ptr, data, (size_t)size) != 0) {
    return opx_fail(OPX_E_PARAMS, "cuMemcpyHtoD failed for launch params");
  }
  return 0;
}

int optixp_params_read(long long handle, char* out, long long size) {
  OpParams* params = opx_params(handle);
  if (!params) return opx_fail(OPX_E_ARG, "invalid OptixParams handle");
  if (!out || size <= 0 || (size_t)size > params->size) {
    return opx_fail(OPX_E_ARG, "launch params read out of range");
  }
  if (params->owner->cuda->memcpy_dtoh(out, params->device_ptr, (size_t)size) != 0) {
    return opx_fail(OPX_E_PARAMS, "cuMemcpyDtoH failed for launch params");
  }
  return 0;
}

int optixp_params_destroy(long long handle) {
  OpParams* params = opx_params(handle);
  if (!params) return opx_fail(OPX_E_ARG, "invalid OptixParams handle");
  params->owner->cuda->mem_free(params->device_ptr);
  params->magic = 0;
  free(params);
  return 0;
}

/* =========================================================================
 * Launch
 * ========================================================================= */

int optixp_launch(long long pipeline_handle, long long params_handle,
                  long long sbt_handle, int width, int height, int depth) {
  OpPipeline* pipeline = opx_pipeline(pipeline_handle);
  if (!pipeline) return opx_fail(OPX_E_ARG, "invalid OptixPipeline handle");
  OpParams* params = opx_params(params_handle);
  if (!params) return opx_fail(OPX_E_ARG, "invalid OptixParams handle");
  OpSbt* sbt = opx_sbt(sbt_handle);
  if (!sbt) return opx_fail(OPX_E_ARG, "invalid OptixSbt handle");
  if (pipeline->owner != params->owner || pipeline->owner != sbt->owner) {
    return opx_fail(OPX_E_ARG, "pipeline/params/SBT context mismatch");
  }
  if (width <= 0 || height <= 0 || depth <= 0) {
    return opx_fail(OPX_E_ARG, "launch dimensions must be positive");
  }

  OptixResult result = ((PFN_launch)pipeline->owner->api.fn[OPTF_LAUNCH])(
      pipeline->pipeline, 0, params->device_ptr, params->size, &sbt->table,
      (unsigned int)width, (unsigned int)height, (unsigned int)depth);
  if (result != OPTIX_SUCCESS) {
    return opx_native(OPX_E_LAUNCH, &pipeline->owner->api, result,
                      "optixLaunch failed");
  }
  if (pipeline->owner->cuda->ctx_synchronize() != 0) {
    return opx_fail(OPX_E_LAUNCH, "cuCtxSynchronize failed after optixLaunch");
  }
  return 0;
}

/* =========================================================================
 * Probe + shared getters
 * ========================================================================= */

static long long opx_probe_load_only(const char* dll_path) {
  OptixApi api;
  int rc = opx_api_load(&api, dll_path, 0);
  if (rc != 0) return rc;
  g_abi = OPTIX_ABI_PIN;
  opx_api_unload(&api);
  return 0;
}

long long optixp_probe_named(const char* dll_path, int live) {
  if (!dll_path || !dll_path[0]) {
    return opx_fail(OPX_E_ARG, "probe path is empty");
  }
  if (!live) return opx_probe_load_only(dll_path);

  long long handle = opx_ctx_create_impl(dll_path, 0, 0, 1, "");
  if (handle < 0) return handle;
  int rc = optixp_ctx_validate(handle);
  optixp_ctx_destroy(handle);
  return rc;
}

long long optixp_probe(void) {
  long long handle = opx_ctx_create_impl(0, 0, 0, 1, "");
  if (handle < 0) return handle;
  int rc = optixp_ctx_validate(handle);
  optixp_ctx_destroy(handle);
  return rc;
}

const char* optixp_last_error(void) { return g_error; }

long long optixp_last_native(void) { return g_native; }

int optixp_abi_version(void) { return g_abi; }

int optixp_rtcore_version(void) { return (int)g_rtcore; }

int optixp_max_trace_depth(void) { return (int)g_max_trace_depth; }

int optixp_cache_enabled(void) { return g_cache_enabled; }

const char* optixp_device_name(void) { return g_device_name; }

int optixp_abi_pin(void) { return OPTIX_ABI_PIN; }
