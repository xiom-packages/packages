// xiom.cuda -- C bridge over the NVIDIA CUDA driver API (nvcuda.dll).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// The driver API library is loaded at runtime (no CUDA Toolkit, no import
// library, nothing vendored).  One call runs the whole probe and caches the
// results; scalar/packed returns avoid out-param slots (finding B-11
// applies to driver-heavy calls).
//
// `cuprobe_run` return value: >= 0 is the packed success result
// `(driver_version << 8) | device_count`; negative is `-code`:
//   100 = loader module missing                     -> SKIP
//   101 = no device (cuInit CUDA_ERROR_NO_DEVICE)   -> SKIP
//   1   = required symbol missing (ABI)             -> FAIL
//   2..4 = version/name/attribute calls failed      -> FAIL
//   5   = cuCtxCreate failed                        -> FAIL
//   6   = cuMemAlloc failed                         -> FAIL
//   7   = cuMemcpyHtoD failed                       -> FAIL
//   8   = cuMemcpyDtoH failed                       -> FAIL
//   9   = host/device round-trip pattern mismatch   -> FAIL

#include <windows.h>
#include <string.h>

#define CUDA_SUCCESS 0
#define CUDA_ERROR_NO_DEVICE 100
#define CU_DEVICE_ATTRIBUTE_COMPUTE_CAPABILITY_MAJOR 75
#define CU_DEVICE_ATTRIBUTE_COMPUTE_CAPABILITY_MINOR 76

typedef int (*PFN_cuInit)(unsigned int flags);
typedef int (*PFN_cuDriverGetVersion)(int* driverVersion);
typedef int (*PFN_cuDeviceGetCount)(int* count);
typedef int (*PFN_cuDeviceGetName)(char* name, int len, int dev);
typedef int (*PFN_cuDeviceGetAttribute)(int* value, int attrib, int dev);
typedef int (*PFN_cuCtxCreate_v2)(void** pctx, unsigned int flags, int dev);
typedef int (*PFN_cuCtxDestroy_v2)(void* ctx);
typedef int (*PFN_cuMemAlloc_v2)(unsigned long long* dptr, unsigned long long bytesize);
typedef int (*PFN_cuMemFree_v2)(unsigned long long dptr);
typedef int (*PFN_cuMemcpyHtoD_v2)(unsigned long long dstDevice, const void* srcHost,
                                   unsigned long long byteCount);
typedef int (*PFN_cuMemcpyDtoH_v2)(void* dstHost, unsigned long long srcDevice,
                                   unsigned long long byteCount);

struct CudaApi {
  HMODULE mod;
  PFN_cuInit init;
  PFN_cuDriverGetVersion driver_get_version;
  PFN_cuDeviceGetCount device_get_count;
  PFN_cuDeviceGetName device_get_name;
  PFN_cuDeviceGetAttribute device_get_attribute;
  PFN_cuCtxCreate_v2 ctx_create;
  PFN_cuCtxDestroy_v2 ctx_destroy;
  PFN_cuMemAlloc_v2 mem_alloc;
  PFN_cuMemFree_v2 mem_free;
  PFN_cuMemcpyHtoD_v2 memcpy_htod;
  PFN_cuMemcpyDtoH_v2 memcpy_dtoh;
};

static struct CudaApi g_api;
static char g_name[256];
static int g_cc;
static int g_memtest_ok;

static int load_api(const char* dll_name) {
  memset(&g_api, 0, sizeof(g_api));
  g_api.mod = LoadLibraryA(dll_name);
  if (g_api.mod == 0) return 100;
  g_api.init = (PFN_cuInit)(void*)GetProcAddress(g_api.mod, "cuInit");
  g_api.driver_get_version =
      (PFN_cuDriverGetVersion)(void*)GetProcAddress(g_api.mod, "cuDriverGetVersion");
  g_api.device_get_count = (PFN_cuDeviceGetCount)(void*)GetProcAddress(g_api.mod, "cuDeviceGetCount");
  g_api.device_get_name = (PFN_cuDeviceGetName)(void*)GetProcAddress(g_api.mod, "cuDeviceGetName");
  g_api.device_get_attribute =
      (PFN_cuDeviceGetAttribute)(void*)GetProcAddress(g_api.mod, "cuDeviceGetAttribute");
  g_api.ctx_create = (PFN_cuCtxCreate_v2)(void*)GetProcAddress(g_api.mod, "cuCtxCreate_v2");
  g_api.ctx_destroy = (PFN_cuCtxDestroy_v2)(void*)GetProcAddress(g_api.mod, "cuCtxDestroy_v2");
  g_api.mem_alloc = (PFN_cuMemAlloc_v2)(void*)GetProcAddress(g_api.mod, "cuMemAlloc_v2");
  g_api.mem_free = (PFN_cuMemFree_v2)(void*)GetProcAddress(g_api.mod, "cuMemFree_v2");
  g_api.memcpy_htod = (PFN_cuMemcpyHtoD_v2)(void*)GetProcAddress(g_api.mod, "cuMemcpyHtoD_v2");
  g_api.memcpy_dtoh = (PFN_cuMemcpyDtoH_v2)(void*)GetProcAddress(g_api.mod, "cuMemcpyDtoH_v2");
  if (g_api.init == 0 || g_api.driver_get_version == 0 || g_api.device_get_count == 0 ||
      g_api.device_get_name == 0 || g_api.device_get_attribute == 0 || g_api.ctx_create == 0 ||
      g_api.ctx_destroy == 0 || g_api.mem_alloc == 0 || g_api.mem_free == 0 ||
      g_api.memcpy_htod == 0 || g_api.memcpy_dtoh == 0) {
    return 1;
  }
  return 0;
}

int cuprobe_run(const char* dll_name) {
  if (dll_name == 0) return -1;
  g_name[0] = 0;
  g_cc = -1;
  g_memtest_ok = 0;

  int rc = load_api(dll_name);
  if (rc != 0) return -rc;

  int driver_version = 0;
  if (g_api.driver_get_version(&driver_version) != CUDA_SUCCESS) return -2;

  int init_result = g_api.init(0);
  if (init_result == CUDA_ERROR_NO_DEVICE) return -101;
  if (init_result != CUDA_SUCCESS) return -4;

  int count = 0;
  if (g_api.device_get_count(&count) != CUDA_SUCCESS) return -2;
  if (count <= 0) return -101;

  if (g_api.device_get_name(g_name, (int)sizeof(g_name), 0) != CUDA_SUCCESS) return -3;
  g_name[sizeof(g_name) - 1] = 0;

  int major = 0;
  int minor = 0;
  if (g_api.device_get_attribute(&major, CU_DEVICE_ATTRIBUTE_COMPUTE_CAPABILITY_MAJOR, 0) !=
          CUDA_SUCCESS ||
      g_api.device_get_attribute(&minor, CU_DEVICE_ATTRIBUTE_COMPUTE_CAPABILITY_MINOR, 0) !=
          CUDA_SUCCESS) {
    return -4;
  }
  g_cc = major * 100 + minor;

  // Real device memory round trip on a fresh context.
  void* ctx = 0;
  if (g_api.ctx_create(&ctx, 0, 0) != CUDA_SUCCESS) return -5;

  unsigned long long dptr = 0;
  if (g_api.mem_alloc(&dptr, 65536) != CUDA_SUCCESS) {
    g_api.ctx_destroy(ctx);
    return -6;
  }

  unsigned char host_out[4096];
  unsigned char host_in[4096];
  for (int i = 0; i < 4096; i++) host_in[i] = (unsigned char)(i & 0xFF);

  if (g_api.memcpy_htod(dptr, host_in, 4096) != CUDA_SUCCESS) {
    g_api.mem_free(dptr);
    g_api.ctx_destroy(ctx);
    return -7;
  }
  if (g_api.memcpy_dtoh(host_out, dptr, 4096) != CUDA_SUCCESS) {
    g_api.mem_free(dptr);
    g_api.ctx_destroy(ctx);
    return -8;
  }

  int match = 1;
  for (int i = 0; i < 4096; i++) {
    if (host_out[i] != host_in[i]) {
      match = 0;
      break;
    }
  }
  g_memtest_ok = match;

  g_api.mem_free(dptr);
  g_api.ctx_destroy(ctx);
  if (!match) return -9;

  if (driver_version < 0) driver_version = 0;
  return (driver_version << 8) | (count & 0xFF);
}

const char* cuprobe_device_name(void) {
  return g_name;
}

int cuprobe_compute_capability(void) {
  return g_cc;
}

int cuprobe_memtest_ok(void) {
  return g_memtest_ok;
}
