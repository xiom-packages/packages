// xiom.cudnn -- C bridge over the NVIDIA cuDNN runtime (cudnn64_9.dll /
// cudnn64_8.dll), plus the CUDA driver entry points the probe needs for
// device memory and a context.
//
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// NOTHING from NVIDIA is vendored into this package.  The user supplies the
// runtime: the official `nvidia-cudnn-cu12` wheel (NVIDIA proprietary EULA)
// and the NVIDIA display driver (`nvcuda.dll`).  See PROVENANCE.md / SPEC.md.
//
// Design notes:
//   * All cuDNN function pointers are resolved with GetProcAddress at
//     runtime; the entry points carry CUDNNWINAPI (__stdcall on Windows).
//   * The classic (graph-free) API is used because it is the smallest
//     surface that covers the declared essentials: tensor/filter/conv/
//     activation/pooling descriptors plus the forward calls.  In cuDNN
//     9.27 these entry points still exist (marked deprecated upstream);
//     the probe pins them.
//   * Out-param slots live in XIOM-owned buffers (`int64_t*` slots,
//     float arrays) -- never through foreign pointers (B-20/B-11).
//   * cuDNN/loader failures are returned as small negative codes; cuDNN
//     status values are returned unchanged (positive) with the upstream
//     error text cached for the typed XIOM error.
//
// Return codes:
//    0        success
//    >0        cudnnStatus_t from the failing cuDNN call
//   -100       loader module not found (SKIP)
//   -101       required export missing (ABI failure)
//   -102       nvcuda.dll not found (SKIP: no CUDA driver)
//   -103       CUDA driver call failed (FAIL)
//   -104       no CUDA device (SKIP)
//   -105       invalid argument (programming error; FAIL)

#include <windows.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

#define CN_API __stdcall
#define CN_OK 0
#define CN_ERR_LOAD (-100)
#define CN_ERR_SYMBOL (-101)
#define CN_ERR_NO_CUDA (-102)
#define CN_ERR_CUDA (-103)
#define CN_ERR_NO_DEVICE (-104)
#define CN_ERR_ARG (-105)

typedef void* cudnn_handle;
typedef void* cudnn_tensor;
typedef void* cudnn_filter;
typedef void* cudnn_conv;
typedef void* cudnn_activation;
typedef void* cudnn_pooling;

typedef size_t (CN_API* PFN_cudnnGetVersion)(void);
typedef int (CN_API* PFN_cudnnCreate)(cudnn_handle*);
typedef int (CN_API* PFN_cudnnDestroy)(cudnn_handle);
typedef int (CN_API* PFN_cudnnCreateTensorDescriptor)(cudnn_tensor*);
typedef int (CN_API* PFN_cudnnDestroyTensorDescriptor)(cudnn_tensor);
typedef int (CN_API* PFN_cudnnSetTensor4dDescriptor)(cudnn_tensor, int, int, int, int, int, int);
typedef int (CN_API* PFN_cudnnGetTensor4dDescriptor)(cudnn_tensor, int*, int*, int*, int*, int*, int*, int*, int*, int*);
typedef int (CN_API* PFN_cudnnCreateFilterDescriptor)(cudnn_filter*);
typedef int (CN_API* PFN_cudnnDestroyFilterDescriptor)(cudnn_filter);
typedef int (CN_API* PFN_cudnnSetFilter4dDescriptor)(cudnn_filter, int, int, int, int, int, int);
typedef int (CN_API* PFN_cudnnCreateConvolutionDescriptor)(cudnn_conv*);
typedef int (CN_API* PFN_cudnnDestroyConvolutionDescriptor)(cudnn_conv);
typedef int (CN_API* PFN_cudnnSetConvolution2dDescriptor)(cudnn_conv, int, int, int, int, int, int, int, int);
typedef int (CN_API* PFN_cudnnGetConvolutionForwardWorkspaceSize)(
    cudnn_handle, cudnn_tensor, cudnn_filter, cudnn_conv, cudnn_tensor, int, size_t*);
typedef int (CN_API* PFN_cudnnConvolutionForward)(
    cudnn_handle, const void*, cudnn_tensor, const void*, cudnn_filter, const void*,
    cudnn_conv, int, void*, size_t, const void*, cudnn_tensor, void*);
typedef int (CN_API* PFN_cudnnCreateActivationDescriptor)(cudnn_activation*);
typedef int (CN_API* PFN_cudnnDestroyActivationDescriptor)(cudnn_activation);
typedef int (CN_API* PFN_cudnnSetActivationDescriptor)(cudnn_activation, int, int, double);
typedef int (CN_API* PFN_cudnnActivationForward)(
    cudnn_handle, cudnn_activation, const void*, cudnn_tensor, const void*, const void*,
    cudnn_tensor, void*);
typedef int (CN_API* PFN_cudnnCreatePoolingDescriptor)(cudnn_pooling*);
typedef int (CN_API* PFN_cudnnDestroyPoolingDescriptor)(cudnn_pooling);
typedef int (CN_API* PFN_cudnnSetPooling2dDescriptor)(cudnn_pooling, int, int, int, int, int, int, int, int);
typedef int (CN_API* PFN_cudnnPoolingForward)(
    cudnn_handle, cudnn_pooling, const void*, cudnn_tensor, const void*, const void*,
    cudnn_tensor, void*);
typedef int (CN_API* PFN_cudnnSoftmaxForward)(
    cudnn_handle, int, int, const void*, cudnn_tensor, const void*, const void*,
    cudnn_tensor, void*);
typedef const char* (CN_API* PFN_cudnnGetErrorString)(int);

typedef int (CN_API* PFN_cuInit)(unsigned int);
typedef int (CN_API* PFN_cuDeviceGet)(int*, int);
typedef int (CN_API* PFN_cuDeviceGetName)(char*, int, int);
typedef int (CN_API* PFN_cuDeviceGetAttribute)(int*, int, int);
typedef int (CN_API* PFN_cuCtxCreate_v2)(void**, unsigned int, int);
typedef int (CN_API* PFN_cuCtxDestroy_v2)(void*);
typedef int (CN_API* PFN_cuMemAlloc_v2)(unsigned long long*, unsigned long long);
typedef int (CN_API* PFN_cuMemFree_v2)(unsigned long long);
typedef int (CN_API* PFN_cuMemcpyHtoD_v2)(unsigned long long, const void*, unsigned long long);
typedef int (CN_API* PFN_cuMemcpyDtoH_v2)(void*, unsigned long long, unsigned long long);
typedef int (CN_API* PFN_cuCtxSynchronize)(void);

// cuDNN constants (cudnn 9.27 headers; values are stable across 8/9 for this
// classic subset).
#define CUDNN_DATA_FLOAT 0
#define CUDNN_TENSOR_NCHW 0
#define CUDNN_CROSS_CORRELATION 1
#define CUDNN_CONVOLUTION_FWD_ALGO_IMPLICIT_GEMM 0
#define CUDNN_ACTIVATION_RELU 1
#define CUDNN_NOT_PROPAGATE_NAN 0
#define CUDNN_POOLING_MAX 0
#define CUDNN_SOFTMAX_ACCURATE 1
#define CUDNN_SOFTMAX_MODE_CHANNEL 1
#define CUDNN_DEVICE_ATTRIBUTE_CC_MAJOR 75
#define CUDNN_DEVICE_ATTRIBUTE_CC_MINOR 76

typedef struct {
  PFN_cudnnGetVersion get_version;
  PFN_cudnnCreate create;
  PFN_cudnnDestroy destroy;
  PFN_cudnnCreateTensorDescriptor create_tensor;
  PFN_cudnnDestroyTensorDescriptor destroy_tensor;
  PFN_cudnnSetTensor4dDescriptor set_tensor4d;
  PFN_cudnnGetTensor4dDescriptor get_tensor4d;
  PFN_cudnnCreateFilterDescriptor create_filter;
  PFN_cudnnDestroyFilterDescriptor destroy_filter;
  PFN_cudnnSetFilter4dDescriptor set_filter4d;
  PFN_cudnnCreateConvolutionDescriptor create_conv;
  PFN_cudnnDestroyConvolutionDescriptor destroy_conv;
  PFN_cudnnSetConvolution2dDescriptor set_conv2d;
  PFN_cudnnGetConvolutionForwardWorkspaceSize conv_workspace_size;
  PFN_cudnnConvolutionForward conv_forward;
  PFN_cudnnCreateActivationDescriptor create_act;
  PFN_cudnnDestroyActivationDescriptor destroy_act;
  PFN_cudnnSetActivationDescriptor set_act;
  PFN_cudnnActivationForward act_forward;
  PFN_cudnnCreatePoolingDescriptor create_pool;
  PFN_cudnnDestroyPoolingDescriptor destroy_pool;
  PFN_cudnnSetPooling2dDescriptor set_pool2d;
  PFN_cudnnPoolingForward pool_forward;
  PFN_cudnnSoftmaxForward softmax_forward;
  PFN_cudnnGetErrorString get_error_string;

  PFN_cuInit cu_init;
  PFN_cuDeviceGet cu_device_get;
  PFN_cuDeviceGetName cu_device_get_name;
  PFN_cuDeviceGetAttribute cu_device_get_attribute;
  PFN_cuCtxCreate_v2 cu_ctx_create;
  PFN_cuCtxDestroy_v2 cu_ctx_destroy;
  PFN_cuMemAlloc_v2 cu_mem_alloc;
  PFN_cuMemFree_v2 cu_mem_free;
  PFN_cuMemcpyHtoD_v2 cu_memcpy_htod;
  PFN_cuMemcpyDtoH_v2 cu_memcpy_dtoh;
  PFN_cuCtxSynchronize cu_ctx_synchronize;
} CnApi;

static CnApi g_api;
static HMODULE g_cudnn;
static HMODULE g_cuda;
static int g_loaded;
static int g_status;
static char g_error[512];
static char g_module[MAX_PATH];
static char g_device_name[256];
static int g_cc;
static void* g_cu_ctx;

static int cn_fail(int code, const char* message) {
  g_status = code;
  if (message == 0) message = "";
  snprintf(g_error, sizeof(g_error), "%s", message);
  return code;
}

static int cn_failf(int code, const char* stage, int rc) {
  g_status = code;
  snprintf(g_error, sizeof(g_error), "%s failed (code %d)", stage, rc);
  return code;
}

static int cn_api_fail(const char* stage, int status) {
  const char* text = 0;
  if (g_api.get_error_string != 0) text = g_api.get_error_string(status);
  g_status = status;
  snprintf(g_error, sizeof(g_error), "%s failed: cudnn status %d (%s)", stage, status,
           text != 0 ? text : "unknown");
  return status;
}

static void cn_clear_error(void) {
  g_status = 0;
  g_error[0] = 0;
}

static HMODULE cn_load_path(const char* path) {
  HMODULE module = LoadLibraryExA(path, 0, LOAD_WITH_ALTERED_SEARCH_PATH);
  if (module != 0) {
    snprintf(g_module, sizeof(g_module), "%s", path);
    return module;
  }
  return 0;
}

static HMODULE cn_load_dir(const char* dir, const char* name) {
  char path[1024];
  static const char* subdirs[] = {"", "bin\\", "nvidia\\cudnn\\bin\\"};
  int i;
  for (i = 0; i < 3; i++) {
    HMODULE module;
    snprintf(path, sizeof(path), "%s\\%s%s", dir, subdirs[i], name);
    module = cn_load_path(path);
    if (module != 0) return module;
  }
  return 0;
}

static int cn_has_suffix_dll(const char* path) {
  size_t n = strlen(path);
  if (n < 4) return 0;
  return (path[n - 4] == '.' && (path[n - 3] == 'd' || path[n - 3] == 'D') &&
          (path[n - 2] == 'l' || path[n - 2] == 'L') && (path[n - 1] == 'l' || path[n - 1] == 'L'));
}

static int cn_resolve_cudnn(void) {
  const char* missing = 0;
#define CN_RESOLVE(field, name)                                    \
  do {                                                             \
    g_api.field = (void*)GetProcAddress(g_cudnn, name);            \
    if (g_api.field == 0) {                                        \
      missing = name;                                              \
      goto resolve_failed;                                         \
    }                                                              \
  } while (0)
  CN_RESOLVE(get_version, "cudnnGetVersion");
  CN_RESOLVE(create, "cudnnCreate");
  CN_RESOLVE(destroy, "cudnnDestroy");
  CN_RESOLVE(create_tensor, "cudnnCreateTensorDescriptor");
  CN_RESOLVE(destroy_tensor, "cudnnDestroyTensorDescriptor");
  CN_RESOLVE(set_tensor4d, "cudnnSetTensor4dDescriptor");
  CN_RESOLVE(get_tensor4d, "cudnnGetTensor4dDescriptor");
  CN_RESOLVE(create_filter, "cudnnCreateFilterDescriptor");
  CN_RESOLVE(destroy_filter, "cudnnDestroyFilterDescriptor");
  CN_RESOLVE(set_filter4d, "cudnnSetFilter4dDescriptor");
  CN_RESOLVE(create_conv, "cudnnCreateConvolutionDescriptor");
  CN_RESOLVE(destroy_conv, "cudnnDestroyConvolutionDescriptor");
  CN_RESOLVE(set_conv2d, "cudnnSetConvolution2dDescriptor");
  CN_RESOLVE(conv_workspace_size, "cudnnGetConvolutionForwardWorkspaceSize");
  CN_RESOLVE(conv_forward, "cudnnConvolutionForward");
  CN_RESOLVE(create_act, "cudnnCreateActivationDescriptor");
  CN_RESOLVE(destroy_act, "cudnnDestroyActivationDescriptor");
  CN_RESOLVE(set_act, "cudnnSetActivationDescriptor");
  CN_RESOLVE(act_forward, "cudnnActivationForward");
  CN_RESOLVE(create_pool, "cudnnCreatePoolingDescriptor");
  CN_RESOLVE(destroy_pool, "cudnnDestroyPoolingDescriptor");
  CN_RESOLVE(set_pool2d, "cudnnSetPooling2dDescriptor");
  CN_RESOLVE(pool_forward, "cudnnPoolingForward");
  CN_RESOLVE(softmax_forward, "cudnnSoftmaxForward");
  CN_RESOLVE(get_error_string, "cudnnGetErrorString");
#undef CN_RESOLVE
  return 0;

resolve_failed:
  {
    char message[256];
    snprintf(message, sizeof(message), "%s: required export %s is missing", g_module, missing);
    return cn_fail(CN_ERR_SYMBOL, message);
  }
}

static int cn_resolve_cuda(void) {
  const char* missing = 0;
#define CN_RESOLVE(field, name)                                    \
  do {                                                             \
    g_api.field = (void*)GetProcAddress(g_cuda, name);             \
    if (g_api.field == 0) {                                        \
      missing = name;                                              \
      goto resolve_failed;                                         \
    }                                                              \
  } while (0)
  CN_RESOLVE(cu_init, "cuInit");
  CN_RESOLVE(cu_device_get, "cuDeviceGet");
  CN_RESOLVE(cu_device_get_name, "cuDeviceGetName");
  CN_RESOLVE(cu_device_get_attribute, "cuDeviceGetAttribute");
  CN_RESOLVE(cu_ctx_create, "cuCtxCreate_v2");
  CN_RESOLVE(cu_ctx_destroy, "cuCtxDestroy_v2");
  CN_RESOLVE(cu_mem_alloc, "cuMemAlloc_v2");
  CN_RESOLVE(cu_mem_free, "cuMemFree_v2");
  CN_RESOLVE(cu_memcpy_htod, "cuMemcpyHtoD_v2");
  CN_RESOLVE(cu_memcpy_dtoh, "cuMemcpyDtoH_v2");
  CN_RESOLVE(cu_ctx_synchronize, "cuCtxSynchronize");
#undef CN_RESOLVE
  return 0;

resolve_failed:
  {
    char message[256];
    snprintf(message, sizeof(message), "nvcuda.dll: required export %s is missing", missing);
    return cn_fail(CN_ERR_SYMBOL, message);
  }
}

static void cn_release_modules(void) {
  memset(&g_api, 0, sizeof(g_api));
  if (g_cuda != 0) {
    FreeLibrary(g_cuda);
    g_cuda = 0;
  }
  if (g_cudnn != 0) {
    FreeLibrary(g_cudnn);
    g_cudnn = 0;
  }
  g_loaded = 0;
  g_module[0] = 0;
  g_device_name[0] = 0;
  g_cc = 0;
  g_cu_ctx = 0;
}

static int cn_load_internal(const char* dir) {
  char env[1024];
  const char* source = dir;
  DWORD env_len;

  if (g_loaded) return 0;
  cn_clear_error();

  if (source == 0 || source[0] == 0) {
    env_len = GetEnvironmentVariableA("XIOM_CUDNN_DIR", env, (DWORD)sizeof(env));
    if (env_len == 0 || env_len >= sizeof(env)) {
      env_len = GetEnvironmentVariableA("CUDNN_DIR", env, (DWORD)sizeof(env));
      if (env_len >= sizeof(env)) env_len = 0;
    }
    if (env_len > 0) source = env;
  }

  if (source != 0 && source[0] != 0) {
    if (cn_has_suffix_dll(source)) {
      g_cudnn = cn_load_path(source);
    } else {
      g_cudnn = cn_load_dir(source, "cudnn64_9.dll");
      if (g_cudnn == 0) g_cudnn = cn_load_dir(source, "cudnn64_8.dll");
    }
    if (g_cudnn == 0) {
      char message[1024];
      snprintf(message, sizeof(message),
               "cuDNN runtime not found under '%s' (expected cudnn64_9.dll or cudnn64_8.dll)",
               source);
      return cn_fail(CN_ERR_LOAD, message);
    }
  } else {
    g_cudnn = LoadLibraryA("cudnn64_9.dll");
    if (g_cudnn == 0) g_cudnn = LoadLibraryA("cudnn64_8.dll");
    if (g_cudnn == 0) {
      return cn_fail(CN_ERR_LOAD,
                     "cudnn64_9.dll / cudnn64_8.dll not found on PATH "
                     "(set XIOM_CUDNN_DIR or CUDNN_DIR to the runtime directory)");
    }
    snprintf(g_module, sizeof(g_module), "cudnn64_9.dll or cudnn64_8.dll (PATH)");
  }

  g_cuda = LoadLibraryA("nvcuda.dll");
  if (g_cuda == 0) {
    cn_release_modules();
    return cn_fail(CN_ERR_NO_CUDA, "nvcuda.dll not found (NVIDIA display driver required)");
  }

  {
    int rc = cn_resolve_cudnn();
    if (rc != 0) {
      cn_release_modules();
      return rc;
    }
    rc = cn_resolve_cuda();
    if (rc != 0) {
      cn_release_modules();
      return rc;
    }
  }

  g_loaded = 1;
  return 0;
}

static int cn_ensure_loaded(void) {
  if (g_loaded) return 0;
  return cn_load_internal(0);
}

static int cn_ctx_ensure(void) {
  int rc;
  int device = 0;
  void* ctx = 0;
  int major = 0;
  int minor = 0;

  if (g_cu_ctx != 0) return 0;
  rc = cn_ensure_loaded();
  if (rc != 0) return rc;

  rc = g_api.cu_init(0);
  if (rc == 100) return cn_fail(CN_ERR_NO_DEVICE, "no CUDA device (cuInit returned 100)");
  if (rc != 0) return cn_failf(CN_ERR_CUDA, "cuInit", rc);

  rc = g_api.cu_device_get(&device, 0);
  if (rc != 0) return cn_fail(CN_ERR_NO_DEVICE, "no CUDA device at ordinal 0");

  rc = g_api.cu_ctx_create(&ctx, 0, device);
  if (rc != 0) return cn_failf(CN_ERR_CUDA, "cuCtxCreate", rc);
  g_cu_ctx = ctx;

  if (g_api.cu_device_get_name(g_device_name, (int)sizeof(g_device_name), device) != 0) {
    g_device_name[0] = 0;
  }
  g_device_name[sizeof(g_device_name) - 1] = 0;

  if (g_api.cu_device_get_attribute(&major, CUDNN_DEVICE_ATTRIBUTE_CC_MAJOR, device) != 0) {
    major = 0;
  }
  if (g_api.cu_device_get_attribute(&minor, CUDNN_DEVICE_ATTRIBUTE_CC_MINOR, device) != 0) {
    minor = 0;
  }
  g_cc = major * 100 + minor;
  return 0;
}

static int cn_require(void) {
  int rc = cn_ensure_loaded();
  if (rc != 0) return rc;
  return cn_ctx_ensure();
}

// -------------------------------------------------------------------------
// public C bridge surface
// -------------------------------------------------------------------------

int cn_load(const char* dir) {
  return cn_load_internal(dir);
}

int64_t cn_version(void) {
  int rc = cn_ensure_loaded();
  if (rc != 0) return (int64_t)rc;
  return (int64_t)g_api.get_version();
}

const char* cn_module(void) {
  return g_module;
}

const char* cn_device_name(void) {
  return g_device_name;
}

int cn_device_cc(void) {
  return g_cc;
}

int cn_last_status(void) {
  return g_status;
}

const char* cn_last_error(void) {
  return g_error;
}

const char* cn_status_string(int status) {
  if (status == 0) return "CUDNN_STATUS_SUCCESS";
  if (g_api.get_error_string != 0) return g_api.get_error_string(status);
  return "cuDNN status (runtime not loaded)";
}

void cn_shutdown(void) {
  if (g_cu_ctx != 0 && g_api.cu_ctx_destroy != 0) {
    g_api.cu_ctx_destroy(g_cu_ctx);
    g_cu_ctx = 0;
  }
  cn_release_modules();
  cn_clear_error();
}

int64_t cn_handle_create(void) {
  cudnn_handle handle = 0;
  int rc = cn_require();
  int status;
  if (rc != 0) return 0;
  status = g_api.create(&handle);
  if (status != 0) {
    cn_api_fail("cudnnCreate", status);
    return 0;
  }
  return (int64_t)(intptr_t)handle;
}

int cn_handle_destroy(int64_t handle) {
  int status;
  if (handle == 0) return cn_fail(CN_ERR_ARG, "cudnnDestroy: null handle");
  status = g_api.destroy((cudnn_handle)(intptr_t)handle);
  if (status != 0) return cn_api_fail("cudnnDestroy", status);
  return 0;
}

int64_t cn_tensor_create(void) {
  cudnn_tensor desc = 0;
  int rc = cn_require();
  int status;
  if (rc != 0) return 0;
  status = g_api.create_tensor(&desc);
  if (status != 0) {
    cn_api_fail("cudnnCreateTensorDescriptor", status);
    return 0;
  }
  return (int64_t)(intptr_t)desc;
}

int cn_tensor_destroy(int64_t desc) {
  int status;
  if (desc == 0) return cn_fail(CN_ERR_ARG, "cudnnDestroyTensorDescriptor: null descriptor");
  status = g_api.destroy_tensor((cudnn_tensor)(intptr_t)desc);
  if (status != 0) return cn_api_fail("cudnnDestroyTensorDescriptor", status);
  return 0;
}

int cn_tensor_set4d(int64_t desc, int format, int data_type, int n, int c, int h, int w) {
  int status;
  if (desc == 0) return cn_fail(CN_ERR_ARG, "cudnnSetTensor4dDescriptor: null descriptor");
  status = g_api.set_tensor4d((cudnn_tensor)(intptr_t)desc, format, data_type, n, c, h, w);
  if (status != 0) return cn_api_fail("cudnnSetTensor4dDescriptor", status);
  return 0;
}

int cn_tensor_get4d(int64_t desc, int64_t* out) {
  int data_type = 0;
  int n = 0, c = 0, h = 0, w = 0;
  int ns = 0, cs = 0, hs = 0, ws = 0;
  int status;
  if (desc == 0 || out == 0) return cn_fail(CN_ERR_ARG, "cudnnGetTensor4dDescriptor: null argument");
  status = g_api.get_tensor4d((cudnn_tensor)(intptr_t)desc, &data_type, &n, &c, &h, &w, &ns, &cs, &hs, &ws);
  if (status != 0) return cn_api_fail("cudnnGetTensor4dDescriptor", status);
  out[0] = data_type;
  out[1] = n;
  out[2] = c;
  out[3] = h;
  out[4] = w;
  out[5] = ns;
  out[6] = cs;
  out[7] = hs;
  out[8] = ws;
  return 0;
}

int64_t cn_filter_create(void) {
  cudnn_filter desc = 0;
  int rc = cn_require();
  int status;
  if (rc != 0) return 0;
  status = g_api.create_filter(&desc);
  if (status != 0) {
    cn_api_fail("cudnnCreateFilterDescriptor", status);
    return 0;
  }
  return (int64_t)(intptr_t)desc;
}

int cn_filter_destroy(int64_t desc) {
  int status;
  if (desc == 0) return cn_fail(CN_ERR_ARG, "cudnnDestroyFilterDescriptor: null descriptor");
  status = g_api.destroy_filter((cudnn_filter)(intptr_t)desc);
  if (status != 0) return cn_api_fail("cudnnDestroyFilterDescriptor", status);
  return 0;
}

int cn_filter_set4d(int64_t desc, int data_type, int format, int k, int c, int h, int w) {
  int status;
  if (desc == 0) return cn_fail(CN_ERR_ARG, "cudnnSetFilter4dDescriptor: null descriptor");
  status = g_api.set_filter4d((cudnn_filter)(intptr_t)desc, data_type, format, k, c, h, w);
  if (status != 0) return cn_api_fail("cudnnSetFilter4dDescriptor", status);
  return 0;
}

int64_t cn_conv_create(void) {
  cudnn_conv desc = 0;
  int rc = cn_require();
  int status;
  if (rc != 0) return 0;
  status = g_api.create_conv(&desc);
  if (status != 0) {
    cn_api_fail("cudnnCreateConvolutionDescriptor", status);
    return 0;
  }
  return (int64_t)(intptr_t)desc;
}

int cn_conv_destroy(int64_t desc) {
  int status;
  if (desc == 0) return cn_fail(CN_ERR_ARG, "cudnnDestroyConvolutionDescriptor: null descriptor");
  status = g_api.destroy_conv((cudnn_conv)(intptr_t)desc);
  if (status != 0) return cn_api_fail("cudnnDestroyConvolutionDescriptor", status);
  return 0;
}

int cn_conv_set2d(int64_t desc, int pad_h, int pad_w, int stride_h, int stride_w,
                  int dilation_h, int dilation_w, int mode, int compute_type) {
  int status;
  if (desc == 0) return cn_fail(CN_ERR_ARG, "cudnnSetConvolution2dDescriptor: null descriptor");
  status = g_api.set_conv2d((cudnn_conv)(intptr_t)desc, pad_h, pad_w, stride_h, stride_w,
                            dilation_h, dilation_w, mode, compute_type);
  if (status != 0) return cn_api_fail("cudnnSetConvolution2dDescriptor", status);
  return 0;
}

int64_t cn_conv_workspace_size(int64_t handle, int64_t x_desc, int64_t w_desc, int64_t conv_desc,
                               int64_t y_desc, int algo) {
  size_t size = 0;
  int status;
  if (handle == 0 || x_desc == 0 || w_desc == 0 || conv_desc == 0 || y_desc == 0) {
    cn_fail(CN_ERR_ARG, "cudnnGetConvolutionForwardWorkspaceSize: null descriptor");
    return -1;
  }
  status = g_api.conv_workspace_size((cudnn_handle)(intptr_t)handle, (cudnn_tensor)(intptr_t)x_desc,
                                     (cudnn_filter)(intptr_t)w_desc, (cudnn_conv)(intptr_t)conv_desc,
                                     (cudnn_tensor)(intptr_t)y_desc, algo, &size);
  if (status != 0) {
    cn_api_fail("cudnnGetConvolutionForwardWorkspaceSize", status);
    return -1;
  }
  return (int64_t)size;
}

int cn_conv_forward(int64_t handle, int64_t x_desc, int64_t x, int64_t w_desc, int64_t w,
                    int64_t conv_desc, int algo, int64_t workspace, int64_t workspace_bytes,
                    float alpha, float beta, int64_t y_desc, int64_t y) {
  int status;
  if (handle == 0 || x_desc == 0 || w_desc == 0 || conv_desc == 0 || y_desc == 0) {
    return cn_fail(CN_ERR_ARG, "cudnnConvolutionForward: null descriptor");
  }
  status = g_api.conv_forward((cudnn_handle)(intptr_t)handle, &alpha, (cudnn_tensor)(intptr_t)x_desc,
                              (const void*)(intptr_t)x, (cudnn_filter)(intptr_t)w_desc,
                              (const void*)(intptr_t)w, (cudnn_conv)(intptr_t)conv_desc, algo,
                              (void*)(intptr_t)workspace, (size_t)workspace_bytes, &beta,
                              (cudnn_tensor)(intptr_t)y_desc, (void*)(intptr_t)y);
  if (status != 0) return cn_api_fail("cudnnConvolutionForward", status);
  return 0;
}

int64_t cn_act_create(void) {
  cudnn_activation desc = 0;
  int rc = cn_require();
  int status;
  if (rc != 0) return 0;
  status = g_api.create_act(&desc);
  if (status != 0) {
    cn_api_fail("cudnnCreateActivationDescriptor", status);
    return 0;
  }
  return (int64_t)(intptr_t)desc;
}

int cn_act_destroy(int64_t desc) {
  int status;
  if (desc == 0) return cn_fail(CN_ERR_ARG, "cudnnDestroyActivationDescriptor: null descriptor");
  status = g_api.destroy_act((cudnn_activation)(intptr_t)desc);
  if (status != 0) return cn_api_fail("cudnnDestroyActivationDescriptor", status);
  return 0;
}

int cn_act_set(int64_t desc, int mode, int nan_opt, double coef) {
  int status;
  if (desc == 0) return cn_fail(CN_ERR_ARG, "cudnnSetActivationDescriptor: null descriptor");
  status = g_api.set_act((cudnn_activation)(intptr_t)desc, mode, nan_opt, coef);
  if (status != 0) return cn_api_fail("cudnnSetActivationDescriptor", status);
  return 0;
}

int cn_act_forward(int64_t handle, int64_t act_desc, float alpha, int64_t x_desc, int64_t x,
                   float beta, int64_t y_desc, int64_t y) {
  int status;
  if (handle == 0 || act_desc == 0 || x_desc == 0 || y_desc == 0) {
    return cn_fail(CN_ERR_ARG, "cudnnActivationForward: null descriptor");
  }
  status = g_api.act_forward((cudnn_handle)(intptr_t)handle, (cudnn_activation)(intptr_t)act_desc,
                             &alpha, (cudnn_tensor)(intptr_t)x_desc, (const void*)(intptr_t)x, &beta,
                             (cudnn_tensor)(intptr_t)y_desc, (void*)(intptr_t)y);
  if (status != 0) return cn_api_fail("cudnnActivationForward", status);
  return 0;
}

int64_t cn_pool_create(void) {
  cudnn_pooling desc = 0;
  int rc = cn_require();
  int status;
  if (rc != 0) return 0;
  status = g_api.create_pool(&desc);
  if (status != 0) {
    cn_api_fail("cudnnCreatePoolingDescriptor", status);
    return 0;
  }
  return (int64_t)(intptr_t)desc;
}

int cn_pool_destroy(int64_t desc) {
  int status;
  if (desc == 0) return cn_fail(CN_ERR_ARG, "cudnnDestroyPoolingDescriptor: null descriptor");
  status = g_api.destroy_pool((cudnn_pooling)(intptr_t)desc);
  if (status != 0) return cn_api_fail("cudnnDestroyPoolingDescriptor", status);
  return 0;
}

int cn_pool_set2d(int64_t desc, int mode, int nan_opt, int window_h, int window_w,
                  int pad_h, int pad_w, int stride_h, int stride_w) {
  int status;
  if (desc == 0) return cn_fail(CN_ERR_ARG, "cudnnSetPooling2dDescriptor: null descriptor");
  status = g_api.set_pool2d((cudnn_pooling)(intptr_t)desc, mode, nan_opt, window_h, window_w,
                            pad_h, pad_w, stride_h, stride_w);
  if (status != 0) return cn_api_fail("cudnnSetPooling2dDescriptor", status);
  return 0;
}

int cn_pool_forward(int64_t handle, int64_t pool_desc, float alpha, int64_t x_desc, int64_t x,
                    float beta, int64_t y_desc, int64_t y) {
  int status;
  if (handle == 0 || pool_desc == 0 || x_desc == 0 || y_desc == 0) {
    return cn_fail(CN_ERR_ARG, "cudnnPoolingForward: null descriptor");
  }
  status = g_api.pool_forward((cudnn_handle)(intptr_t)handle, (cudnn_pooling)(intptr_t)pool_desc,
                              &alpha, (cudnn_tensor)(intptr_t)x_desc, (const void*)(intptr_t)x, &beta,
                              (cudnn_tensor)(intptr_t)y_desc, (void*)(intptr_t)y);
  if (status != 0) return cn_api_fail("cudnnPoolingForward", status);
  return 0;
}

int cn_softmax_forward(int64_t handle, int algo, int mode, float alpha, int64_t x_desc, int64_t x,
                       float beta, int64_t y_desc, int64_t y) {
  int status;
  if (handle == 0 || x_desc == 0 || y_desc == 0) {
    return cn_fail(CN_ERR_ARG, "cudnnSoftmaxForward: null descriptor");
  }
  status = g_api.softmax_forward((cudnn_handle)(intptr_t)handle, algo, mode, &alpha,
                                 (cudnn_tensor)(intptr_t)x_desc, (const void*)(intptr_t)x, &beta,
                                 (cudnn_tensor)(intptr_t)y_desc, (void*)(intptr_t)y);
  if (status != 0) return cn_api_fail("cudnnSoftmaxForward", status);
  return 0;
}

int64_t cn_dev_alloc(int64_t bytes) {
  unsigned long long ptr = 0;
  int rc;
  if (bytes <= 0) {
    cn_fail(CN_ERR_ARG, "cudnn_device_alloc: byte count must be positive");
    return 0;
  }
  rc = cn_ctx_ensure();
  if (rc != 0) return 0;
  rc = g_api.cu_mem_alloc(&ptr, (unsigned long long)bytes);
  if (rc != 0) {
    cn_failf(CN_ERR_CUDA, "cuMemAlloc", rc);
    return 0;
  }
  return (int64_t)ptr;
}

int cn_dev_free(int64_t ptr) {
  int rc;
  if (ptr == 0) return 0;
  rc = cn_ctx_ensure();
  if (rc != 0) return rc;
  rc = g_api.cu_mem_free((unsigned long long)ptr);
  if (rc != 0) return cn_failf(CN_ERR_CUDA, "cuMemFree", rc);
  return 0;
}

int cn_dev_upload(int64_t dst, int64_t src, int64_t count) {
  int rc;
  if (dst == 0 || src == 0 || count <= 0) {
    return cn_fail(CN_ERR_ARG, "cudnn_device_upload: invalid buffer");
  }
  rc = cn_ctx_ensure();
  if (rc != 0) return rc;
  rc = g_api.cu_memcpy_htod((unsigned long long)dst, (const void*)(intptr_t)src,
                            (unsigned long long)count * 4ULL);
  if (rc != 0) return cn_failf(CN_ERR_CUDA, "cuMemcpyHtoD", rc);
  return 0;
}

int cn_dev_download(int64_t src, int64_t dst, int64_t count) {
  int rc;
  if (src == 0 || dst == 0 || count <= 0) {
    return cn_fail(CN_ERR_ARG, "cudnn_device_download: invalid buffer");
  }
  rc = cn_ctx_ensure();
  if (rc != 0) return rc;
  rc = g_api.cu_memcpy_dtoh((void*)(intptr_t)dst, (unsigned long long)src,
                            (unsigned long long)count * 4ULL);
  if (rc != 0) return cn_failf(CN_ERR_CUDA, "cuMemcpyDtoH", rc);
  return 0;
}

int cn_dev_sync(void) {
  int rc = cn_ctx_ensure();
  if (rc != 0) return rc;
  rc = g_api.cu_ctx_synchronize();
  if (rc != 0) return cn_failf(CN_ERR_CUDA, "cuCtxSynchronize", rc);
  return 0;
}

// One self-contained live probe: 1x1x4x4 input, 1x1x3x3 all-ones filter,
// valid 3x3 convolution -> 1x1x2x2 [54, 63, 90, 99]; ReLU (identity on the
// positive conv output, plus a -1/2/-3/4 tensor proving the clamp); 2x2 max
// pooling -> 99; channel softmax over [1,2,3,4] -> sum 1.  Tensor descriptor
// dims/strides are round-tripped through cudnnGetTensor4dDescriptor.
//
// out_ints (12 slots):  0 version, 1 n, 2 c, 3 h, 4 w,
//                       5..8 strides, 9 workspace bytes, 10 compute capability,
//                       11 device index (0)
// out_floats (16 slots): 0..3 conv, 4..7 relu(conv), 8..9 relu(-1,2,-3,4),
//                        10 pool max, 11..14 softmax, 15 softmax sum
int cn_probe(const char* dir, int64_t* out_ints, float* out_floats) {
  int rc = 0;
  int status = 0;
  cudnn_handle handle = 0;
  cudnn_tensor xd = 0, wd = 0, yd = 0, sd = 0, poutd = 0;
  cudnn_filter fd = 0;
  cudnn_conv cd = 0;
  cudnn_activation ad = 0;
  cudnn_pooling pod = 0;
  unsigned long long dx = 0, dw = 0, dy = 0, dy2 = 0, dneg = 0, dnegout = 0;
  unsigned long long dpool = 0, dsm = 0, dsmout = 0, dwork = 0;
  size_t workspace = 0;
  float alpha = 1.0f;
  float beta = 0.0f;
  float x_host[16];
  float w_host[9];
  float neg_host[4];
  float sm_host[4];
  float conv_out[4];
  float relu_out[4];
  float neg_out[4];
  float pool_out[1];
  float sm_out[4];
  int i;

  if (out_ints == 0 || out_floats == 0) return cn_fail(CN_ERR_ARG, "cudnn_probe: null output buffer");
  for (i = 0; i < 12; i++) out_ints[i] = 0;
  for (i = 0; i < 16; i++) out_floats[i] = 0.0f;

  rc = cn_load_internal(dir);
  if (rc != 0) return rc;
  rc = cn_ctx_ensure();
  if (rc != 0) return rc;

  status = g_api.create(&handle);
  if (status != 0) { rc = cn_api_fail("cudnnCreate", status); goto cleanup; }

  status = g_api.create_tensor(&xd);
  if (status != 0) { rc = cn_api_fail("cudnnCreateTensorDescriptor(x)", status); goto cleanup; }
  status = g_api.create_tensor(&wd);
  if (status != 0) { rc = cn_api_fail("cudnnCreateTensorDescriptor(w)", status); goto cleanup; }
  status = g_api.create_tensor(&yd);
  if (status != 0) { rc = cn_api_fail("cudnnCreateTensorDescriptor(y)", status); goto cleanup; }
  status = g_api.create_tensor(&poutd);
  if (status != 0) { rc = cn_api_fail("cudnnCreateTensorDescriptor(pool-out)", status); goto cleanup; }

  status = g_api.set_tensor4d(xd, CUDNN_TENSOR_NCHW, CUDNN_DATA_FLOAT, 1, 1, 4, 4);
  if (status != 0) { rc = cn_api_fail("cudnnSetTensor4dDescriptor(x)", status); goto cleanup; }
  status = g_api.set_tensor4d(wd, CUDNN_TENSOR_NCHW, CUDNN_DATA_FLOAT, 1, 1, 3, 3);
  if (status != 0) { rc = cn_api_fail("cudnnSetTensor4dDescriptor(w)", status); goto cleanup; }
  status = g_api.set_tensor4d(yd, CUDNN_TENSOR_NCHW, CUDNN_DATA_FLOAT, 1, 1, 2, 2);
  if (status != 0) { rc = cn_api_fail("cudnnSetTensor4dDescriptor(y)", status); goto cleanup; }
  status = g_api.set_tensor4d(poutd, CUDNN_TENSOR_NCHW, CUDNN_DATA_FLOAT, 1, 1, 1, 1);
  if (status != 0) { rc = cn_api_fail("cudnnSetTensor4dDescriptor(pool-out)", status); goto cleanup; }

  {
    int data_type = 0, n = 0, c = 0, h = 0, w = 0;
    int ns = 0, cs = 0, hs = 0, ws = 0;
    status = g_api.get_tensor4d(xd, &data_type, &n, &c, &h, &w, &ns, &cs, &hs, &ws);
    if (status != 0) { rc = cn_api_fail("cudnnGetTensor4dDescriptor(x)", status); goto cleanup; }
    out_ints[1] = n;
    out_ints[2] = c;
    out_ints[3] = h;
    out_ints[4] = w;
    out_ints[5] = ns;
    out_ints[6] = cs;
    out_ints[7] = hs;
    out_ints[8] = ws;
  }

  status = g_api.create_filter(&fd);
  if (status != 0) { rc = cn_api_fail("cudnnCreateFilterDescriptor", status); goto cleanup; }
  status = g_api.set_filter4d(fd, CUDNN_DATA_FLOAT, CUDNN_TENSOR_NCHW, 1, 1, 3, 3);
  if (status != 0) { rc = cn_api_fail("cudnnSetFilter4dDescriptor", status); goto cleanup; }

  status = g_api.create_conv(&cd);
  if (status != 0) { rc = cn_api_fail("cudnnCreateConvolutionDescriptor", status); goto cleanup; }
  status = g_api.set_conv2d(cd, 0, 0, 1, 1, 1, 1, CUDNN_CROSS_CORRELATION, CUDNN_DATA_FLOAT);
  if (status != 0) { rc = cn_api_fail("cudnnSetConvolution2dDescriptor", status); goto cleanup; }

  status = g_api.create_act(&ad);
  if (status != 0) { rc = cn_api_fail("cudnnCreateActivationDescriptor", status); goto cleanup; }
  status = g_api.set_act(ad, CUDNN_ACTIVATION_RELU, CUDNN_NOT_PROPAGATE_NAN, 0.0);
  if (status != 0) { rc = cn_api_fail("cudnnSetActivationDescriptor", status); goto cleanup; }

  status = g_api.create_pool(&pod);
  if (status != 0) { rc = cn_api_fail("cudnnCreatePoolingDescriptor", status); goto cleanup; }
  status = g_api.set_pool2d(pod, CUDNN_POOLING_MAX, CUDNN_NOT_PROPAGATE_NAN, 2, 2, 0, 0, 2, 2);
  if (status != 0) { rc = cn_api_fail("cudnnSetPooling2dDescriptor", status); goto cleanup; }

  status = g_api.conv_workspace_size(handle, xd, fd, cd, yd,
                                     CUDNN_CONVOLUTION_FWD_ALGO_IMPLICIT_GEMM, &workspace);
  if (status != 0) { rc = cn_api_fail("cudnnGetConvolutionForwardWorkspaceSize", status); goto cleanup; }
  out_ints[9] = (int64_t)workspace;

  // Allocations use the resolved driver entry points directly so the primary
  // error status is preserved.
  {
    int cr;
    cr = g_api.cu_mem_alloc(&dx, (unsigned long long)sizeof(x_host));
    if (cr != 0) { rc = cn_failf(CN_ERR_CUDA, "cuMemAlloc(x)", cr); goto cleanup; }
    cr = g_api.cu_mem_alloc(&dw, (unsigned long long)sizeof(w_host));
    if (cr != 0) { rc = cn_failf(CN_ERR_CUDA, "cuMemAlloc(w)", cr); goto cleanup; }
    cr = g_api.cu_mem_alloc(&dy, 4ULL * sizeof(float));
    if (cr != 0) { rc = cn_failf(CN_ERR_CUDA, "cuMemAlloc(y)", cr); goto cleanup; }
    cr = g_api.cu_mem_alloc(&dy2, 4ULL * sizeof(float));
    if (cr != 0) { rc = cn_failf(CN_ERR_CUDA, "cuMemAlloc(y2)", cr); goto cleanup; }
    cr = g_api.cu_mem_alloc(&dneg, 4ULL * sizeof(float));
    if (cr != 0) { rc = cn_failf(CN_ERR_CUDA, "cuMemAlloc(neg)", cr); goto cleanup; }
    cr = g_api.cu_mem_alloc(&dnegout, 4ULL * sizeof(float));
    if (cr != 0) { rc = cn_failf(CN_ERR_CUDA, "cuMemAlloc(neg-out)", cr); goto cleanup; }
    cr = g_api.cu_mem_alloc(&dpool, (unsigned long long)sizeof(float));
    if (cr != 0) { rc = cn_failf(CN_ERR_CUDA, "cuMemAlloc(pool)", cr); goto cleanup; }
    cr = g_api.cu_mem_alloc(&dsm, 4ULL * sizeof(float));
    if (cr != 0) { rc = cn_failf(CN_ERR_CUDA, "cuMemAlloc(softmax)", cr); goto cleanup; }
    cr = g_api.cu_mem_alloc(&dsmout, 4ULL * sizeof(float));
    if (cr != 0) { rc = cn_failf(CN_ERR_CUDA, "cuMemAlloc(softmax-out)", cr); goto cleanup; }
    if (workspace > 0) {
      cr = g_api.cu_mem_alloc(&dwork, (unsigned long long)workspace);
      if (cr != 0) { rc = cn_failf(CN_ERR_CUDA, "cuMemAlloc(workspace)", cr); goto cleanup; }
    }
  }

  for (i = 0; i < 16; i++) x_host[i] = (float)(i + 1);
  for (i = 0; i < 9; i++) w_host[i] = 1.0f;
  neg_host[0] = -1.0f; neg_host[1] = 2.0f; neg_host[2] = -3.0f; neg_host[3] = 4.0f;
  sm_host[0] = 1.0f; sm_host[1] = 2.0f; sm_host[2] = 3.0f; sm_host[3] = 4.0f;

  {
    int cr;
    cr = g_api.cu_memcpy_htod(dx, x_host, (unsigned long long)sizeof(x_host));
    if (cr != 0) { rc = cn_failf(CN_ERR_CUDA, "cuMemcpyHtoD(x)", cr); goto cleanup; }
    cr = g_api.cu_memcpy_htod(dw, w_host, (unsigned long long)sizeof(w_host));
    if (cr != 0) { rc = cn_failf(CN_ERR_CUDA, "cuMemcpyHtoD(w)", cr); goto cleanup; }
    cr = g_api.cu_memcpy_htod(dneg, neg_host, (unsigned long long)sizeof(neg_host));
    if (cr != 0) { rc = cn_failf(CN_ERR_CUDA, "cuMemcpyHtoD(neg)", cr); goto cleanup; }
    cr = g_api.cu_memcpy_htod(dsm, sm_host, (unsigned long long)sizeof(sm_host));
    if (cr != 0) { rc = cn_failf(CN_ERR_CUDA, "cuMemcpyHtoD(softmax)", cr); goto cleanup; }
  }

  status = g_api.conv_forward(handle, &alpha, xd, (const void*)dx, fd, (const void*)dw, cd,
                              CUDNN_CONVOLUTION_FWD_ALGO_IMPLICIT_GEMM,
                              (void*)dwork, workspace, &beta, yd, (void*)dy);
  if (status != 0) { rc = cn_api_fail("cudnnConvolutionForward", status); goto cleanup; }

  status = g_api.act_forward(handle, ad, &alpha, yd, (const void*)dy, &beta, yd, (void*)dy2);
  if (status != 0) { rc = cn_api_fail("cudnnActivationForward(conv)", status); goto cleanup; }

  status = g_api.act_forward(handle, ad, &alpha, yd, (const void*)dneg, &beta, yd, (void*)dnegout);
  if (status != 0) { rc = cn_api_fail("cudnnActivationForward(negative)", status); goto cleanup; }

  status = g_api.pool_forward(handle, pod, &alpha, yd, (const void*)dy2, &beta, poutd, (void*)dpool);
  if (status != 0) { rc = cn_api_fail("cudnnPoolingForward", status); goto cleanup; }

  status = g_api.create_tensor(&sd);
  if (status != 0) { rc = cn_api_fail("cudnnCreateTensorDescriptor(softmax)", status); goto cleanup; }
  status = g_api.set_tensor4d(sd, CUDNN_TENSOR_NCHW, CUDNN_DATA_FLOAT, 1, 4, 1, 1);
  if (status != 0) { rc = cn_api_fail("cudnnSetTensor4dDescriptor(softmax)", status); goto cleanup; }
  status = g_api.softmax_forward(handle, CUDNN_SOFTMAX_ACCURATE, CUDNN_SOFTMAX_MODE_CHANNEL, &alpha,
                                 sd, (const void*)dsm, &beta, sd, (void*)dsmout);
  if (status != 0) { rc = cn_api_fail("cudnnSoftmaxForward", status); goto cleanup; }

  {
    int cr;
    cr = g_api.cu_ctx_synchronize();
    if (cr != 0) { rc = cn_failf(CN_ERR_CUDA, "cuCtxSynchronize", cr); goto cleanup; }
    cr = g_api.cu_memcpy_dtoh(conv_out, dy, 4ULL * sizeof(float));
    if (cr != 0) { rc = cn_failf(CN_ERR_CUDA, "cuMemcpyDtoH(conv)", cr); goto cleanup; }
    cr = g_api.cu_memcpy_dtoh(relu_out, dy2, 4ULL * sizeof(float));
    if (cr != 0) { rc = cn_failf(CN_ERR_CUDA, "cuMemcpyDtoH(relu)", cr); goto cleanup; }
    cr = g_api.cu_memcpy_dtoh(neg_out, dnegout, 4ULL * sizeof(float));
    if (cr != 0) { rc = cn_failf(CN_ERR_CUDA, "cuMemcpyDtoH(relu-negative)", cr); goto cleanup; }
    cr = g_api.cu_memcpy_dtoh(pool_out, dpool, (unsigned long long)sizeof(float));
    if (cr != 0) { rc = cn_failf(CN_ERR_CUDA, "cuMemcpyDtoH(pool)", cr); goto cleanup; }
    cr = g_api.cu_memcpy_dtoh(sm_out, dsmout, 4ULL * sizeof(float));
    if (cr != 0) { rc = cn_failf(CN_ERR_CUDA, "cuMemcpyDtoH(softmax)", cr); goto cleanup; }
  }

  out_ints[0] = (int64_t)g_api.get_version();
  out_ints[10] = g_cc;
  out_ints[11] = 0;
  for (i = 0; i < 4; i++) out_floats[i] = conv_out[i];
  for (i = 0; i < 4; i++) out_floats[4 + i] = relu_out[i];
  out_floats[8] = neg_out[0];
  out_floats[9] = neg_out[1];
  out_floats[10] = pool_out[0];
  for (i = 0; i < 4; i++) out_floats[11 + i] = sm_out[i];
  out_floats[15] = sm_out[0] + sm_out[1] + sm_out[2] + sm_out[3];

cleanup:
  if (sd != 0) g_api.destroy_tensor(sd);
  if (poutd != 0) g_api.destroy_tensor(poutd);
  if (yd != 0) g_api.destroy_tensor(yd);
  if (wd != 0) g_api.destroy_tensor(wd);
  if (xd != 0) g_api.destroy_tensor(xd);
  if (pod != 0) g_api.destroy_pool(pod);
  if (ad != 0) g_api.destroy_act(ad);
  if (cd != 0) g_api.destroy_conv(cd);
  if (fd != 0) g_api.destroy_filter(fd);
  if (handle != 0) g_api.destroy(handle);
  if (dwork != 0) g_api.cu_mem_free(dwork);
  if (dsmout != 0) g_api.cu_mem_free(dsmout);
  if (dsm != 0) g_api.cu_mem_free(dsm);
  if (dpool != 0) g_api.cu_mem_free(dpool);
  if (dnegout != 0) g_api.cu_mem_free(dnegout);
  if (dneg != 0) g_api.cu_mem_free(dneg);
  if (dy2 != 0) g_api.cu_mem_free(dy2);
  if (dy != 0) g_api.cu_mem_free(dy);
  if (dw != 0) g_api.cu_mem_free(dw);
  if (dx != 0) g_api.cu_mem_free(dx);
  return rc;
}
