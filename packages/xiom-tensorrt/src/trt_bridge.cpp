// xiom.tensorrt -- C++ bridge over the NVIDIA TensorRT runtime.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// DESIGN: system-library path -- **nothing from NVIDIA is vendored or
// compiled against**.  `nvinfer_10.dll` is resolved at runtime with
// LoadLibraryA / GetProcAddress; the bridge is built from independent
// declarations of the pinned 10.16 interface facts only (no NVIDIA header,
// import library or binary in this package).
//
// TensorRT 10.16 public interfaces are non-virtual wrappers: every wrapper
// is { vptr, apiv::V* mImpl } (16 bytes; mImpl at byte 8) and the real
// operations are pure virtual methods of the apiv::V* implementation.  The
// bridge calls those methods through the implementation vtable.  Slot
// indices are pinned to 10.16.1 in SPEC.md section 3 and are the only
// version-sensitive constants here; the loader rejects other majors.
//
// No C++ exception may escape the C ABI: every entry point is wrapped in
// try/catch (...) and reports a typed bridge error instead.
//
// Classification:
//   TRT_ERR_LOAD_ABSENT        loader module missing            -> SKIP
//   TRT_ERR_NO_DEVICE          no CUDA device                   -> SKIP
//   TRT_ERR_LOAD_ABI           module loaded, entry missing     -> FAIL
//   TRT_ERR_VERSION_UNSUPPORTED major != 10                     -> FAIL/SKIP
//   TRT_ERR_CALL_FAILED        a TensorRT call returned 0       -> typed error
//   TRT_ERR_BAD_HANDLE         stale/foreign handle             -> typed error
//   TRT_ERR_INVALID_ARG        argument rejected by the bridge  -> typed error
//   TRT_ERR_IO_FAILED          file read/write failed           -> typed error
//   TRT_ERR_CUDA_FAILED        a CUDA driver call failed        -> typed error

#define _CRT_SECURE_NO_WARNINGS
#include <windows.h>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <cstdlib>
#include <cctype>
#include <string>
#include <vector>
#include <mutex>
#include <memory>
#include <unordered_map>

// ---------------------------------------------------------------------------
// Pinned interface facts (independent declarations; no NVIDIA header)
// ---------------------------------------------------------------------------

namespace trt {

constexpr int32_t kErrNone = 0;
constexpr int32_t kErrLoadAbsent = 1;
constexpr int32_t kErrLoadAbi = 2;
constexpr int32_t kErrVersionUnsupported = 3;
constexpr int32_t kErrNoDevice = 4;
constexpr int32_t kErrCallFailed = 5;
constexpr int32_t kErrBadHandle = 6;
constexpr int32_t kErrInvalidArg = 7;
constexpr int32_t kErrIoFailed = 8;
constexpr int32_t kErrCudaFailed = 9;
constexpr int32_t kErrUnsupported = 10;

// Dims64: int32 nbDims followed by 8 int64 extents (72 bytes, align 8).
struct Dims {
  int32_t nbDims;
  int32_t pad;
  int64_t d[8];
};

// Weights: { DataType type; void const* values; int64 count; } (24 bytes).
struct Weights {
  int32_t type;
  int32_t pad;
  void const* values;
  int64_t count;
};

constexpr int32_t kDataTypeFloat = 0;
constexpr int32_t kTensorIOModeInput = 1;
constexpr int32_t kTensorIOModeOutput = 2;

// Pinned 10.16 vtable slot indices (VRoot destructor is slot 0).
namespace slot {
// VBuilder
constexpr int kBuilderPlatformFastFp16 = 1;
constexpr int kBuilderPlatformFastInt8 = 2;
constexpr int kBuilderPlatformTf32 = 12;
constexpr int kBuilderCreateConfig = 6;
constexpr int kBuilderCreateNetworkV2 = 7;
constexpr int kBuilderBuildSerialized = 13;
// VNetworkDefinition
constexpr int kNetAddInput = 1;
constexpr int kNetMarkOutput = 2;
constexpr int kNetAddElementWise = 8;
constexpr int kNetNbLayers = 11;
constexpr int kNetGetLayer = 12;
constexpr int kNetNbInputs = 13;
constexpr int kNetGetInput = 14;
constexpr int kNetNbOutputs = 15;
constexpr int kNetGetOutput = 16;
constexpr int kNetAddConstant = 22;
constexpr int kNetAddIdentity = 23;
// VBuilderConfig
constexpr int kCfgClearFlag = 9;
constexpr int kCfgSetFlag = 10;
constexpr int kCfgGetFlag = 11;
constexpr int kCfgSetTacticSources = 37;
constexpr int kCfgGetTacticSources = 38;
constexpr int kCfgSetMemoryPoolLimit = 42;
constexpr int kCfgGetMemoryPoolLimit = 43;
// VHostMemory
constexpr int kHostData = 1;
constexpr int kHostSize = 2;
constexpr int kHostType = 3;
// VRuntime
constexpr int kRuntimeDeserialize = 3;
// VCudaEngine
constexpr int kEngineCreateContext = 4;
constexpr int kEngineTensorShape = 18;
constexpr int kEngineTensorDataType = 19;
constexpr int kEngineTensorLocation = 20;
constexpr int kEngineTensorIOMode = 22;
constexpr int kEngineNbIOTensors = 29;
constexpr int kEngineIOTensorName = 30;
// VExecutionContext
constexpr int kCtxAllInputDims = 11;
constexpr int kCtxSetInputShape = 20;
constexpr int kCtxSetTensorAddress = 23;
constexpr int kCtxGetTensorAddress = 24;
constexpr int kCtxEnqueueV3 = 36;
// VTensor
constexpr int kTensorSetName = 1;
constexpr int kTensorGetName = 2;
constexpr int kTensorGetDimensions = 4;
constexpr int kTensorGetType = 6;
constexpr int kTensorIsNetworkInput = 8;
constexpr int kTensorIsNetworkOutput = 9;
// VLayer
constexpr int kLayerGetType = 1;
constexpr int kLayerGetName = 3;
} // namespace slot

} // namespace trt

// ---------------------------------------------------------------------------
// Error state and handle registry
// ---------------------------------------------------------------------------

namespace trt {

static std::mutex g_mu;
static int32_t g_err_kind = kErrNone;
static std::string g_err_msg;

static void set_error(int32_t kind, const char* msg) {
  g_err_kind = kind;
  g_err_msg = msg ? msg : "";
}

static void set_error_str(int32_t kind, const std::string& msg) {
  g_err_kind = kind;
  g_err_msg = msg;
}

static void clear_error() {
  g_err_kind = kErrNone;
  g_err_msg.clear();
}

enum Kind {
  K_NONE = 0,
  K_LOGGER,
  K_BUILDER,
  K_NETWORK,
  K_CONFIG,
  K_HOSTMEM,
  K_RUNTIME,
  K_ENGINE,
  K_CONTEXT,
  K_TENSOR,
  K_LAYER,
  K_STREAM,
  K_DEVPTR
};

struct Entry {
  int kind;
  void* ptr;
  int64_t owner;
};

static std::unordered_map<int64_t, Entry> g_reg;
static int64_t g_next_handle = 1;

static int64_t reg_add(int kind, void* ptr, int64_t owner = 0) {
  int64_t id = g_next_handle++;
  Entry e;
  e.kind = kind;
  e.ptr = ptr;
  e.owner = owner;
  g_reg[id] = e;
  return id;
}

static void* reg_get(int64_t id, int kind) {
  auto it = g_reg.find(id);
  if (it == g_reg.end() || it->second.kind != kind) {
    set_error(kErrBadHandle, "invalid or stale handle");
    return nullptr;
  }
  return it->second.ptr;
}

static bool reg_take(int64_t id, int kind, void** out) {
  auto it = g_reg.find(id);
  if (it == g_reg.end() || it->second.kind != kind) {
    set_error(kErrBadHandle, "invalid or stale handle");
    return false;
  }
  *out = it->second.ptr;
  g_reg.erase(it);
  return true;
}

static void reg_remove_borrowed(int64_t owner) {
  for (auto it = g_reg.begin(); it != g_reg.end();) {
    if (it->second.owner == owner && (it->second.kind == K_TENSOR || it->second.kind == K_LAYER)) {
      it = g_reg.erase(it);
    } else {
      ++it;
    }
  }
}

// Wrapper base: every TensorRT 10.16 public interface is polymorphic and is
// released with operator delete (documented in the pinned headers).
struct WrapperBase {
  virtual ~WrapperBase() = default;
};

static void destroy_wrapper(void* wrapper) {
  if (wrapper) {
    delete reinterpret_cast<WrapperBase*>(wrapper);
  }
}

static void* impl_of(void* wrapper) {
  // Layout: vptr at 0, apiv::V* mImpl at 8.
  return *reinterpret_cast<void**>(reinterpret_cast<char*>(wrapper) + 8);
}

template <typename Fn>
static Fn vfn(void* impl, int index) {
  void** table = *reinterpret_cast<void***>(impl);
  return reinterpret_cast<Fn>(table[index]);
}

static trt::Dims make_dims(int32_t ndim, int64_t d0, int64_t d1, int64_t d2, int64_t d3,
                           int64_t d4, int64_t d5, int64_t d6, int64_t d7) {
  trt::Dims d{};
  d.nbDims = ndim;
  int64_t src[8] = {d0, d1, d2, d3, d4, d5, d6, d7};
  for (int i = 0; i < 8; ++i) {
    d.d[i] = src[i];
  }
  return d;
}

static int64_t dims_volume(const trt::Dims& d) {
  if (d.nbDims <= 0) {
    return 1;
  }
  int64_t n = 1;
  for (int i = 0; i < d.nbDims; ++i) {
    if (d.d[i] > 0) {
      n *= d.d[i];
    }
  }
  return n;
}

// ---------------------------------------------------------------------------
// TensorRT logger plumbing (application-implemented ILogger)
// ---------------------------------------------------------------------------

class BridgeLogger {
public:
  // Slot 0 of the pinned ILogger vtable.
  virtual void log(int32_t severity, const char* msg) noexcept {
    std::lock_guard<std::mutex> lock(mu_);
    count_++;
    last_severity_ = severity;
    if (severity <= level_) {
      last_ = msg ? msg : "";
    }
  }
  // Slot 1 of the pinned ILogger vtable.
  virtual ~BridgeLogger() = default;

  void set_level(int32_t level) {
    std::lock_guard<std::mutex> lock(mu_);
    level_ = level;
  }
  int32_t level() {
    std::lock_guard<std::mutex> lock(mu_);
    return level_;
  }
  int32_t count() {
    std::lock_guard<std::mutex> lock(mu_);
    return count_;
  }
  int32_t last_severity() {
    std::lock_guard<std::mutex> lock(mu_);
    return last_severity_;
  }
  std::string last() {
    std::lock_guard<std::mutex> lock(mu_);
    return last_;
  }

private:
  std::mutex mu_;
  int32_t level_ = 2; // kWARNING
  int32_t count_ = 0;
  int32_t last_severity_ = -1;
  std::string last_;
};

struct BuilderEntry {
  void* wrapper;
  std::shared_ptr<BridgeLogger> logger;
};

struct RuntimeEntry {
  void* wrapper;
  std::shared_ptr<BridgeLogger> logger;
};

struct NetworkEntry {
  void* wrapper;
  std::vector<std::vector<float>> constants;
};

struct HostBuffer {
  void* wrapper; // IHostMemory wrapper, or nullptr for a file-backed buffer
  void* data;
  size_t size;
  bool owned;
};

// ---------------------------------------------------------------------------
// Loader state
// ---------------------------------------------------------------------------

struct Api {
  HMODULE module = nullptr;
  std::string path;
  int32_t raw_version = 0;
  int32_t major = 0;
  int32_t minor = 0;
  int32_t patch = 0;
  int32_t resolved = 0;
  int32_t required = 3;
  int32_t (*get_version)() = nullptr;
  void* (*create_builder)(void*, int32_t) = nullptr;
  void* (*create_runtime)(void*, int32_t) = nullptr;
};

static Api g_api;

static std::string dir_of_path(const std::string& path) {
  size_t p = path.find_last_of("\\/");
  if (p == std::string::npos) {
    return std::string();
  }
  return path.substr(0, p);
}

static void prepare_search_path(const std::string& dir) {
  if (dir.empty()) {
    return;
  }
  SetDefaultDllDirectories(LOAD_LIBRARY_SEARCH_DEFAULT_DIRS | LOAD_LIBRARY_SEARCH_USER_DIRS);
  SetDllDirectoryA(dir.c_str());
}

static HMODULE load_module(const std::string& spec) {
  std::string dir = dir_of_path(spec);
  prepare_search_path(dir);
  DWORD flags = LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_DEFAULT_DIRS |
                LOAD_LIBRARY_SEARCH_USER_DIRS;
  HMODULE m = LoadLibraryExA(spec.c_str(), nullptr, flags);
  if (!m) {
    m = LoadLibraryExA(spec.c_str(), nullptr, 0);
  }
  return m;
}

static bool try_load_spec(const std::string& spec, std::string* why) {
  g_api = Api();
  g_api.path = spec;
  g_api.module = load_module(spec);
  if (!g_api.module) {
    DWORD e = GetLastError();
    *why = "LoadLibrary failed for " + spec + " (win32=" + std::to_string((unsigned long)e) + ")";
    return false;
  }
  g_api.get_version = reinterpret_cast<int32_t (*)()>(
      reinterpret_cast<void*>(GetProcAddress(g_api.module, "getInferLibVersion")));
  g_api.create_builder = reinterpret_cast<void* (*)(void*, int32_t)>(
      reinterpret_cast<void*>(GetProcAddress(g_api.module, "createInferBuilder_INTERNAL")));
  g_api.create_runtime = reinterpret_cast<void* (*)(void*, int32_t)>(
      reinterpret_cast<void*>(GetProcAddress(g_api.module, "createInferRuntime_INTERNAL")));
  g_api.resolved = 0;
  if (g_api.get_version) g_api.resolved++;
  if (g_api.create_builder) g_api.resolved++;
  if (g_api.create_runtime) g_api.resolved++;
  if (g_api.resolved != g_api.required) {
    *why = "missing TensorRT entry points in " + spec;
    return false;
  }
  g_api.raw_version = g_api.get_version();
  if (g_api.raw_version <= 0) {
    *why = "getInferLibVersion returned a non-positive value";
    return false;
  }
  g_api.major = g_api.raw_version / 10000;
  g_api.minor = (g_api.raw_version / 100) % 100;
  g_api.patch = g_api.raw_version % 100;
  if (g_api.major != 10 || g_api.minor != 16) {
    *why = "TensorRT " + std::to_string(g_api.major) + "." + std::to_string(g_api.minor) +
           ".x is not supported; the pinned ABI is 10.16.x";
    return false;
  }
  return true;
}

static void destroy_registry();

static void unload_api() {
  if (g_api.module) {
    FreeLibrary(g_api.module);
  }
  g_api = Api();
}

static void reset_all() {
  destroy_registry();
  unload_api();
}

static std::string env_dir() {
  char buf[32768];
  DWORD n = GetEnvironmentVariableA("XIOM_TENSORRT_DIR", buf, (DWORD)sizeof(buf));
  if (n == 0 || n >= sizeof(buf)) {
    return std::string();
  }
  return std::string(buf);
}

static bool load_default(std::string* why) {
  std::string dir = env_dir();
  if (!dir.empty()) {
    std::string spec = dir;
    if (spec.size() >= 4) {
      std::string tail = spec.substr(spec.size() - 4);
      for (auto& c : tail) c = (char)tolower((unsigned char)c);
      if (tail != ".dll") {
        if (spec.back() != '\\' && spec.back() != '/') {
          spec += "\\";
        }
        spec += "nvinfer_10.dll";
      }
    } else {
      if (spec.back() != '\\' && spec.back() != '/') {
        spec += "\\";
      }
      spec += "nvinfer_10.dll";
    }
    if (try_load_spec(spec, why)) {
      return true;
    }
    // A user-supplied directory that does not contain the engine module is
    // not a valid runtime: report the specific failure, do not fall through
    // to a foreign DLL that happens to be on PATH.
    return false;
  }
  if (try_load_spec("nvinfer_10.dll", why)) {
    return true;
  }
  return try_load_spec("nvinfer.dll", why);
}

// ---------------------------------------------------------------------------
// CUDA driver helpers (device memory + stream; TensorRT uses the current
// context, so initialise this before creating a builder).
// ---------------------------------------------------------------------------

typedef int (*PFN_cuInit)(unsigned int);
typedef int (*PFN_cuDeviceGet)(int*, int);
typedef int (*PFN_cuDeviceGetCount)(int*);
typedef int (*PFN_cuDeviceGetName)(char*, int, int);
typedef int (*PFN_cuDevicePrimaryCtxRetain)(void**, int);
typedef int (*PFN_cuDevicePrimaryCtxRelease)(int);
typedef int (*PFN_cuCtxSetCurrent)(void*);
typedef int (*PFN_cuMemAlloc)(unsigned long long*, unsigned long long);
typedef int (*PFN_cuMemFree)(unsigned long long);
typedef int (*PFN_cuMemcpyHtoD)(unsigned long long, const void*, unsigned long long);
typedef int (*PFN_cuMemcpyDtoH)(void*, unsigned long long, unsigned long long);
typedef int (*PFN_cuStreamCreate)(void**, unsigned int);
typedef int (*PFN_cuStreamDestroy)(void*);
typedef int (*PFN_cuStreamSynchronize)(void*);

struct Cuda {
  HMODULE module = nullptr;
  void* ctx = nullptr;
  bool ready = false;
  PFN_cuInit init = nullptr;
  PFN_cuDeviceGet device_get = nullptr;
  PFN_cuDeviceGetCount device_count = nullptr;
  PFN_cuDeviceGetName device_name = nullptr;
  PFN_cuDevicePrimaryCtxRetain primary_retain = nullptr;
  PFN_cuDevicePrimaryCtxRelease primary_release = nullptr;
  PFN_cuCtxSetCurrent ctx_set_current = nullptr;
  PFN_cuMemAlloc mem_alloc = nullptr;
  PFN_cuMemFree mem_free = nullptr;
  PFN_cuMemcpyHtoD htod = nullptr;
  PFN_cuMemcpyDtoH dtoh = nullptr;
  PFN_cuStreamCreate stream_create = nullptr;
  PFN_cuStreamDestroy stream_destroy = nullptr;
  PFN_cuStreamSynchronize stream_sync = nullptr;
  std::vector<unsigned long long> allocs;
};

static Cuda g_cuda;

static bool cuda_ensure_current() {
  if (!g_cuda.ready || !g_cuda.ctx || !g_cuda.ctx_set_current) {
    set_error(kErrCudaFailed, "CUDA is not initialised; call trt_cuda_init first");
    return false;
  }
  int rc = g_cuda.ctx_set_current(g_cuda.ctx);
  if (rc != 0) {
    set_error_str(kErrCudaFailed, "cuCtxSetCurrent failed (" + std::to_string(rc) + ")");
    return false;
  }
  return true;
}

} // namespace trt

// ---------------------------------------------------------------------------
// Public C ABI
// ---------------------------------------------------------------------------

using namespace trt;

#define TRT_TRY try {
#define TRT_CATCH(ret) \
  } catch (...) { set_error(kErrCallFailed, "C++ exception in the TensorRT bridge"); return ret; }

extern "C" {

// ---- error state ----------------------------------------------------------

int32_t trt_c_last_error_kind() {
  return g_err_kind;
}

const char* trt_c_last_error_message() {
  return g_err_msg.c_str();
}

// ---- loader ---------------------------------------------------------------

int32_t trt_c_probe() {
  TRT_TRY
  clear_error();
  if (g_api.module && g_api.raw_version > 0) {
    return g_api.raw_version;
  }
  std::string why;
  if (!load_default(&why)) {
    int kind = kErrLoadAbsent;
    if (g_api.module) {
      if (g_api.raw_version > 0 && (g_api.major != 10 || g_api.minor != 16)) kind = kErrVersionUnsupported;
      else if (g_api.resolved != g_api.required) kind = kErrLoadAbi;
      unload_api();
    }
    set_error_str(kind, why);
    return 0;
  }
  return g_api.raw_version;
  TRT_CATCH(0)
}

int32_t trt_c_probe_named(const char* module) {
  TRT_TRY
  clear_error();
  if (!module || !*module) {
    set_error(kErrInvalidArg, "module name is empty");
    return 0;
  }
  reset_all();
  std::string why;
  if (!try_load_spec(module, &why)) {
    int kind = kErrLoadAbsent;
    if (g_api.module) {
      if (g_api.raw_version > 0 && (g_api.major != 10 || g_api.minor != 16)) kind = kErrVersionUnsupported;
      else if (g_api.resolved != g_api.required) kind = kErrLoadAbi;
      unload_api();
    }
    set_error_str(kind, why);
    return 0;
  }
  return g_api.raw_version;
  TRT_CATCH(0)
}

int32_t trt_c_close() {
  TRT_TRY
  clear_error();
  reset_all();
  return 1;
  TRT_CATCH(0)
}

int32_t trt_c_loaded() {
  TRT_TRY
  clear_error();
  return (g_api.module && g_api.raw_version > 0) ? 1 : 0;
  TRT_CATCH(0)
}

int32_t trt_c_version_raw() {
  clear_error();
  return g_api.raw_version;
}

int32_t trt_c_version_major() {
  clear_error();
  return g_api.major;
}

int32_t trt_c_version_minor() {
  clear_error();
  return g_api.minor;
}

int32_t trt_c_version_patch() {
  clear_error();
  return g_api.patch;
}

const char* trt_c_loaded_module() {
  clear_error();
  return g_api.path.c_str();
}

int32_t trt_c_symbols_resolved() {
  clear_error();
  return g_api.resolved;
}

int32_t trt_c_symbols_required() {
  clear_error();
  return g_api.required;
}

const char* trt_c_enqueue_mode() {
  clear_error();
  return g_api.major == 10 ? "v3" : "unsupported";
}

// ---- logger ---------------------------------------------------------------

int64_t trt_c_logger_create(int32_t severity) {
  TRT_TRY
  clear_error();
  if (severity < 0 || severity > 4) {
    set_error(kErrInvalidArg, "logger severity must be 0..4");
    return 0;
  }
  auto logger = std::make_shared<BridgeLogger>();
  logger->set_level(severity);
  return reg_add(K_LOGGER, new std::shared_ptr<BridgeLogger>(logger));
  TRT_CATCH(0)
}

int32_t trt_c_logger_destroy(int64_t id) {
  TRT_TRY
  clear_error();
  void* p = nullptr;
  if (!reg_take(id, K_LOGGER, &p)) {
    return 0;
  }
  delete reinterpret_cast<std::shared_ptr<BridgeLogger>*>(p);
  return 1;
  TRT_CATCH(0)
}

static std::shared_ptr<BridgeLogger>* logger_entry(int64_t id) {
  void* p = reg_get(id, K_LOGGER);
  if (!p) {
    return nullptr;
  }
  return reinterpret_cast<std::shared_ptr<BridgeLogger>*>(p);
}

int32_t trt_c_logger_set_severity(int64_t id, int32_t severity) {
  TRT_TRY
  clear_error();
  if (severity < 0 || severity > 4) {
    set_error(kErrInvalidArg, "logger severity must be 0..4");
    return 0;
  }
  auto* e = logger_entry(id);
  if (!e) return 0;
  (*e)->set_level(severity);
  return 1;
  TRT_CATCH(0)
}

int32_t trt_c_logger_severity(int64_t id) {
  TRT_TRY
  clear_error();
  auto* e = logger_entry(id);
  if (!e) return -1;
  return (*e)->level();
  TRT_CATCH(-1)
}

int32_t trt_c_logger_message_count(int64_t id) {
  TRT_TRY
  clear_error();
  auto* e = logger_entry(id);
  if (!e) return -1;
  return (*e)->count();
  TRT_CATCH(-1)
}

const char* trt_c_logger_last_message(int64_t id) {
  TRT_TRY
  clear_error();
  auto* e = logger_entry(id);
  if (!e) return "";
  static std::string out;
  out = (*e)->last();
  return out.c_str();
  TRT_CATCH("")
}

int32_t trt_c_logger_last_severity(int64_t id) {
  TRT_TRY
  clear_error();
  auto* e = logger_entry(id);
  if (!e) return -1;
  return (*e)->last_severity();
  TRT_CATCH(-1)
}

// ---- builder --------------------------------------------------------------

int64_t trt_c_builder_create(int64_t logger_id) {
  TRT_TRY
  clear_error();
  if (!g_api.create_builder) {
    set_error(kErrLoadAbsent, "TensorRT is not loaded");
    return 0;
  }
  auto* le = logger_entry(logger_id);
  if (!le) return 0;
  if (g_cuda.ready && !cuda_ensure_current()) {
    return 0;
  }
  void* wrapper = g_api.create_builder((*le).get(), g_api.raw_version);
  if (!wrapper) {
    set_error(kErrCallFailed, "createInferBuilder_INTERNAL returned null");
    return 0;
  }
  auto* e = new BuilderEntry();
  e->wrapper = wrapper;
  e->logger = *le;
  return reg_add(K_BUILDER, e);
  TRT_CATCH(0)
}

static BuilderEntry* builder_entry(int64_t id) {
  return reinterpret_cast<BuilderEntry*>(reg_get(id, K_BUILDER));
}

int32_t trt_c_builder_destroy(int64_t id) {
  TRT_TRY
  clear_error();
  void* p = nullptr;
  if (!reg_take(id, K_BUILDER, &p)) return 0;
  auto* e = reinterpret_cast<BuilderEntry*>(p);
  destroy_wrapper(e->wrapper);
  delete e;
  return 1;
  TRT_CATCH(0)
}

static int32_t builder_bool(int64_t id, int slot_index) {
  BuilderEntry* e = builder_entry(id);
  if (!e) return -1;
  void* impl = impl_of(e->wrapper);
  typedef bool (*Fn)(void*);
  Fn fn = vfn<Fn>(impl, slot_index);
  return fn(impl) ? 1 : 0;
}

int32_t trt_c_builder_platform_has_fp16(int64_t id) {
  TRT_TRY
  clear_error();
  return builder_bool(id, slot::kBuilderPlatformFastFp16);
  TRT_CATCH(-1)
}

int32_t trt_c_builder_platform_has_int8(int64_t id) {
  TRT_TRY
  clear_error();
  return builder_bool(id, slot::kBuilderPlatformFastInt8);
  TRT_CATCH(-1)
}

int32_t trt_c_builder_platform_has_tf32(int64_t id) {
  TRT_TRY
  clear_error();
  return builder_bool(id, slot::kBuilderPlatformTf32);
  TRT_CATCH(-1)
}

int64_t trt_c_builder_create_network(int64_t id) {
  TRT_TRY
  clear_error();
  BuilderEntry* e = builder_entry(id);
  if (!e) return 0;
  void* impl = impl_of(e->wrapper);
  typedef void* (*Fn)(void*, uint32_t);
  Fn fn = vfn<Fn>(impl, slot::kBuilderCreateNetworkV2);
  void* net = fn(impl, 0u);
  if (!net) {
    set_error(kErrCallFailed, "IBuilder::createNetworkV2 returned null");
    return 0;
  }
  auto* ne = new NetworkEntry();
  ne->wrapper = net;
  return reg_add(K_NETWORK, ne);
  TRT_CATCH(0)
}

int64_t trt_c_builder_create_config(int64_t id) {
  TRT_TRY
  clear_error();
  BuilderEntry* e = builder_entry(id);
  if (!e) return 0;
  void* impl = impl_of(e->wrapper);
  typedef void* (*Fn)(void*);
  Fn fn = vfn<Fn>(impl, slot::kBuilderCreateConfig);
  void* cfg = fn(impl);
  if (!cfg) {
    set_error(kErrCallFailed, "IBuilder::createBuilderConfig returned null");
    return 0;
  }
  return reg_add(K_CONFIG, cfg);
  TRT_CATCH(0)
}

int64_t trt_c_builder_build_serialized(int64_t builder_id, int64_t network_id, int64_t config_id) {
  TRT_TRY
  clear_error();
  BuilderEntry* b = builder_entry(builder_id);
  NetworkEntry* n = reinterpret_cast<NetworkEntry*>(reg_get(network_id, K_NETWORK));
  void* cfg = reg_get(config_id, K_CONFIG);
  if (!b || !n || !cfg) return 0;
  if (g_cuda.ready && !cuda_ensure_current()) {
    return 0;
  }
  void* impl = impl_of(b->wrapper);
  typedef void* (*Fn)(void*, void*, void*);
  Fn fn = vfn<Fn>(impl, slot::kBuilderBuildSerialized);
  void* host = fn(impl, n->wrapper, cfg);
  if (!host) {
    set_error(kErrCallFailed, "IBuilder::buildSerializedNetwork returned null");
    return 0;
  }
  void* himpl = impl_of(host);
  typedef void* (*FnData)(void*);
  typedef size_t (*FnSize)(void*);
  void* data = vfn<FnData>(himpl, slot::kHostData)(himpl);
  size_t size = vfn<FnSize>(himpl, slot::kHostSize)(himpl);
  auto* hb = new HostBuffer();
  hb->wrapper = host;
  hb->data = data;
  hb->size = size;
  hb->owned = false;
  return reg_add(K_HOSTMEM, hb);
  TRT_CATCH(0)
}

// ---- network --------------------------------------------------------------

static NetworkEntry* network_entry(int64_t id) {
  return reinterpret_cast<NetworkEntry*>(reg_get(id, K_NETWORK));
}

static int64_t network_tensor(int64_t network_id, void* tensor, int kind) {
  if (!tensor) {
    set_error(kErrCallFailed, "TensorRT returned a null tensor");
    return 0;
  }
  return reg_add(kind, tensor, network_id);
}

int64_t trt_c_network_add_input(int64_t net_id, const char* name, int32_t dtype, int64_t d0,
                              int64_t d1, int64_t d2, int64_t d3, int64_t d4, int64_t d5,
                              int64_t d6, int64_t d7, int32_t ndim) {
  TRT_TRY
  clear_error();
  if (!name || !*name) {
    set_error(kErrInvalidArg, "input name is empty");
    return 0;
  }
  if (ndim < 0 || ndim > 8) {
    set_error(kErrInvalidArg, "ndim must be 0..8");
    return 0;
  }
  NetworkEntry* n = network_entry(net_id);
  if (!n) return 0;
  Dims dims = make_dims(ndim, d0, d1, d2, d3, d4, d5, d6, d7);
  void* impl = impl_of(n->wrapper);
  typedef void* (*Fn)(void*, const char*, int32_t, const Dims*);
  Fn fn = vfn<Fn>(impl, slot::kNetAddInput);
  void* t = fn(impl, name, dtype, &dims);
  return network_tensor(net_id, t, K_TENSOR);
  TRT_CATCH(0)
}

int64_t trt_c_network_add_identity(int64_t net_id, int64_t input_id) {
  TRT_TRY
  clear_error();
  NetworkEntry* n = network_entry(net_id);
  void* input = reg_get(input_id, K_TENSOR);
  if (!n || !input) return 0;
  void* impl = impl_of(n->wrapper);
  typedef void* (*Fn)(void*, void*);
  Fn fn = vfn<Fn>(impl, slot::kNetAddIdentity);
  void* layer = fn(impl, input);
  if (!layer) {
    set_error(kErrCallFailed, "INetworkDefinition::addIdentity returned null");
    return 0;
  }
  typedef void* (*FnOut)(void*, int32_t);
  void* limpl = impl_of(layer);
  void* out = vfn<FnOut>(limpl, 7)(limpl, 0);
  return network_tensor(net_id, out, K_TENSOR);
  TRT_CATCH(0)
}

int64_t trt_c_network_add_constant_f32(int64_t net_id, float value, int64_t d0, int64_t d1,
                                     int64_t d2, int64_t d3, int64_t d4, int64_t d5,
                                     int64_t d6, int64_t d7, int32_t ndim) {
  TRT_TRY
  clear_error();
  if (ndim < 0 || ndim > 8) {
    set_error(kErrInvalidArg, "ndim must be 0..8");
    return 0;
  }
  NetworkEntry* n = network_entry(net_id);
  if (!n) return 0;
  Dims dims = make_dims(ndim, d0, d1, d2, d3, d4, d5, d6, d7);
  int64_t count = dims_volume(dims);
  if (count < 1 || count > (1LL << 28)) {
    set_error(kErrInvalidArg, "constant tensor volume is out of range");
    return 0;
  }
  // TensorRT holds the weights by reference until the engine is built, so
  // the backing store must outlive this call.  The inner vector's heap
  // buffer stays valid across outer-vector growth (move, not realloc).
  n->constants.emplace_back((size_t)count, value);
  std::vector<float>& stored = n->constants.back();
  Weights w;
  w.type = kDataTypeFloat;
  w.pad = 0;
  w.values = stored.data();
  w.count = count;
  void* impl = impl_of(n->wrapper);
  typedef void* (*Fn)(void*, const Dims*, Weights);
  Fn fn = vfn<Fn>(impl, slot::kNetAddConstant);
  void* layer = fn(impl, &dims, w);
  if (!layer) {
    set_error(kErrCallFailed, "INetworkDefinition::addConstant returned null");
    return 0;
  }
  typedef void* (*FnOut)(void*, int32_t);
  void* limpl = impl_of(layer);
  void* out = vfn<FnOut>(limpl, 7)(limpl, 0);
  return network_tensor(net_id, out, K_TENSOR);
  TRT_CATCH(0)
}

int64_t trt_c_network_add_elementwise(int64_t net_id, int32_t op, int64_t a_id, int64_t b_id) {
  TRT_TRY
  clear_error();
  NetworkEntry* n = network_entry(net_id);
  void* a = reg_get(a_id, K_TENSOR);
  void* b = reg_get(b_id, K_TENSOR);
  if (!n || !a || !b) return 0;
  void* impl = impl_of(n->wrapper);
  typedef void* (*Fn)(void*, void*, void*, int32_t);
  Fn fn = vfn<Fn>(impl, slot::kNetAddElementWise);
  void* layer = fn(impl, a, b, op);
  if (!layer) {
    set_error(kErrCallFailed, "INetworkDefinition::addElementWise returned null");
    return 0;
  }
  typedef void* (*FnOut)(void*, int32_t);
  void* limpl = impl_of(layer);
  void* out = vfn<FnOut>(limpl, 7)(limpl, 0);
  return network_tensor(net_id, out, K_TENSOR);
  TRT_CATCH(0)
}

int32_t trt_c_network_mark_output(int64_t net_id, int64_t tensor_id) {
  TRT_TRY
  clear_error();
  NetworkEntry* n = network_entry(net_id);
  void* t = reg_get(tensor_id, K_TENSOR);
  if (!n || !t) return 0;
  void* impl = impl_of(n->wrapper);
  typedef void (*Fn)(void*, void*);
  Fn fn = vfn<Fn>(impl, slot::kNetMarkOutput);
  fn(impl, t);
  return 1;
  TRT_CATCH(0)
}

int32_t trt_c_network_nb_layers(int64_t net_id) {
  TRT_TRY
  clear_error();
  NetworkEntry* n = network_entry(net_id);
  if (!n) return -1;
  void* impl = impl_of(n->wrapper);
  typedef int32_t (*Fn)(void*);
  return vfn<Fn>(impl, slot::kNetNbLayers)(impl);
  TRT_CATCH(-1)
}

int32_t trt_c_network_nb_inputs(int64_t net_id) {
  TRT_TRY
  clear_error();
  NetworkEntry* n = network_entry(net_id);
  if (!n) return -1;
  void* impl = impl_of(n->wrapper);
  typedef int32_t (*Fn)(void*);
  return vfn<Fn>(impl, slot::kNetNbInputs)(impl);
  TRT_CATCH(-1)
}

int32_t trt_c_network_nb_outputs(int64_t net_id) {
  TRT_TRY
  clear_error();
  NetworkEntry* n = network_entry(net_id);
  if (!n) return -1;
  void* impl = impl_of(n->wrapper);
  typedef int32_t (*Fn)(void*);
  return vfn<Fn>(impl, slot::kNetNbOutputs)(impl);
  TRT_CATCH(-1)
}

int64_t trt_c_network_input(int64_t net_id, int32_t index) {
  TRT_TRY
  clear_error();
  NetworkEntry* n = network_entry(net_id);
  if (!n) return 0;
  void* impl = impl_of(n->wrapper);
  typedef void* (*Fn)(void*, int32_t);
  void* t = vfn<Fn>(impl, slot::kNetGetInput)(impl, index);
  return network_tensor(net_id, t, K_TENSOR);
  TRT_CATCH(0)
}

int64_t trt_c_network_output(int64_t net_id, int32_t index) {
  TRT_TRY
  clear_error();
  NetworkEntry* n = network_entry(net_id);
  if (!n) return 0;
  void* impl = impl_of(n->wrapper);
  typedef void* (*Fn)(void*, int32_t);
  void* t = vfn<Fn>(impl, slot::kNetGetOutput)(impl, index);
  return network_tensor(net_id, t, K_TENSOR);
  TRT_CATCH(0)
}

int64_t trt_c_network_layer(int64_t net_id, int32_t index) {
  TRT_TRY
  clear_error();
  NetworkEntry* n = network_entry(net_id);
  if (!n) return 0;
  void* impl = impl_of(n->wrapper);
  typedef void* (*Fn)(void*, int32_t);
  void* layer = vfn<Fn>(impl, slot::kNetGetLayer)(impl, index);
  return network_tensor(net_id, layer, K_LAYER);
  TRT_CATCH(0)
}

int32_t trt_c_network_destroy(int64_t net_id) {
  TRT_TRY
  clear_error();
  void* p = nullptr;
  if (!reg_take(net_id, K_NETWORK, &p)) return 0;
  auto* n = reinterpret_cast<NetworkEntry*>(p);
  reg_remove_borrowed(net_id);
  destroy_wrapper(n->wrapper);
  delete n;
  return 1;
  TRT_CATCH(0)
}

// ---- tensor ---------------------------------------------------------------

static void* tensor_entry(int64_t id) {
  return reg_get(id, K_TENSOR);
}

int32_t trt_c_tensor_set_name(int64_t id, const char* name) {
  TRT_TRY
  clear_error();
  if (!name || !*name) {
    set_error(kErrInvalidArg, "tensor name is empty");
    return 0;
  }
  void* t = tensor_entry(id);
  if (!t) return 0;
  void* impl = impl_of(t);
  typedef void (*Fn)(void*, const char*);
  vfn<Fn>(impl, slot::kTensorSetName)(impl, name);
  return 1;
  TRT_CATCH(0)
}

const char* trt_c_tensor_name(int64_t id) {
  TRT_TRY
  clear_error();
  void* t = tensor_entry(id);
  if (!t) return "";
  void* impl = impl_of(t);
  typedef const char* (*Fn)(void*);
  const char* s = vfn<Fn>(impl, slot::kTensorGetName)(impl);
  return s ? s : "";
  TRT_CATCH("")
}

int32_t trt_c_tensor_dtype(int64_t id) {
  TRT_TRY
  clear_error();
  void* t = tensor_entry(id);
  if (!t) return -1;
  void* impl = impl_of(t);
  typedef int32_t (*Fn)(void*);
  return vfn<Fn>(impl, slot::kTensorGetType)(impl);
  TRT_CATCH(-1)
}

static bool tensor_dims(int64_t id, Dims* out) {
  void* t = tensor_entry(id);
  if (!t) return false;
  void* impl = impl_of(t);
  // Member functions returning Dims (72 B) use RCX=this, RDX=sret in the
  // MSVC x64 ABI; declare the call as a free function with the sret slot
  // second so the register assignment matches.
  typedef void (*Fn)(void*, Dims*);
  *out = Dims{};
  vfn<Fn>(impl, slot::kTensorGetDimensions)(impl, out);
  return true;
}

int32_t trt_c_tensor_ndim(int64_t id) {
  TRT_TRY
  clear_error();
  Dims d{};
  if (!tensor_dims(id, &d)) return -1;
  return d.nbDims;
  TRT_CATCH(-1)
}

int64_t trt_c_tensor_dim(int64_t id, int32_t index) {
  TRT_TRY
  clear_error();
  Dims d{};
  if (!tensor_dims(id, &d)) return 0;
  if (index < 0 || index >= d.nbDims) {
    set_error(kErrInvalidArg, "tensor dimension index out of range");
    return 0;
  }
  return d.d[index];
  TRT_CATCH(0)
}

int32_t trt_c_tensor_is_input(int64_t id) {
  TRT_TRY
  clear_error();
  void* t = tensor_entry(id);
  if (!t) return -1;
  void* impl = impl_of(t);
  typedef bool (*Fn)(void*);
  return vfn<Fn>(impl, slot::kTensorIsNetworkInput)(impl) ? 1 : 0;
  TRT_CATCH(-1)
}

int32_t trt_c_tensor_is_output(int64_t id) {
  TRT_TRY
  clear_error();
  void* t = tensor_entry(id);
  if (!t) return -1;
  void* impl = impl_of(t);
  typedef bool (*Fn)(void*);
  return vfn<Fn>(impl, slot::kTensorIsNetworkOutput)(impl) ? 1 : 0;
  TRT_CATCH(-1)
}

// ---- layer ----------------------------------------------------------------

int32_t trt_c_layer_type(int64_t id) {
  TRT_TRY
  clear_error();
  void* l = reg_get(id, K_LAYER);
  if (!l) return -1;
  void* impl = impl_of(l);
  typedef int32_t (*Fn)(void*);
  return vfn<Fn>(impl, slot::kLayerGetType)(impl);
  TRT_CATCH(-1)
}

const char* trt_c_layer_name(int64_t id) {
  TRT_TRY
  clear_error();
  void* l = reg_get(id, K_LAYER);
  if (!l) return "";
  void* impl = impl_of(l);
  typedef const char* (*Fn)(void*);
  const char* s = vfn<Fn>(impl, slot::kLayerGetName)(impl);
  return s ? s : "";
  TRT_CATCH("")
}

// ---- builder config -------------------------------------------------------

static int32_t config_set_flag(int64_t id, int32_t flag, int32_t value) {
  void* cfg = reg_get(id, K_CONFIG);
  if (!cfg) return -1;
  void* impl = impl_of(cfg);
  // 10.16 exposes setFlag(flag)/clearFlag(flag) as separate void methods;
  // the boolean choice is the caller's, not a parameter of either method.
  typedef void (*Fn)(void*, int32_t);
  if (value != 0) {
    vfn<Fn>(impl, slot::kCfgSetFlag)(impl, flag);
  } else {
    vfn<Fn>(impl, slot::kCfgClearFlag)(impl, flag);
  }
  return 1;
}

int32_t trt_c_config_set_flag(int64_t id, int32_t flag, int32_t value) {
  TRT_TRY
  clear_error();
  return config_set_flag(id, flag, value);
  TRT_CATCH(-1)
}

int32_t trt_c_config_get_flag(int64_t id, int32_t flag) {
  TRT_TRY
  clear_error();
  void* cfg = reg_get(id, K_CONFIG);
  if (!cfg) return -1;
  void* impl = impl_of(cfg);
  typedef bool (*Fn)(void*, int32_t);
  return vfn<Fn>(impl, slot::kCfgGetFlag)(impl, flag) ? 1 : 0;
  TRT_CATCH(-1)
}

int32_t trt_c_config_set_memory_pool_limit(int64_t id, int32_t pool, int64_t bytes) {
  TRT_TRY
  clear_error();
  if (bytes < 0) {
    set_error(kErrInvalidArg, "memory pool limit must be non-negative");
    return 0;
  }
  void* cfg = reg_get(id, K_CONFIG);
  if (!cfg) return 0;
  void* impl = impl_of(cfg);
  typedef void (*Fn)(void*, int32_t, size_t);
  vfn<Fn>(impl, slot::kCfgSetMemoryPoolLimit)(impl, pool, (size_t)bytes);
  return 1;
  TRT_CATCH(0)
}

int64_t trt_c_config_memory_pool_limit(int64_t id, int32_t pool) {
  TRT_TRY
  clear_error();
  void* cfg = reg_get(id, K_CONFIG);
  if (!cfg) return -1;
  void* impl = impl_of(cfg);
  typedef size_t (*Fn)(void*, int32_t);
  return (int64_t)vfn<Fn>(impl, slot::kCfgGetMemoryPoolLimit)(impl, pool);
  TRT_CATCH(-1)
}

int32_t trt_c_config_set_tactic_sources(int64_t id, int64_t mask) {
  TRT_TRY
  clear_error();
  void* cfg = reg_get(id, K_CONFIG);
  if (!cfg) return 0;
  void* impl = impl_of(cfg);
  typedef bool (*Fn)(void*, uint64_t);
  return vfn<Fn>(impl, slot::kCfgSetTacticSources)(impl, (uint64_t)mask) ? 1 : 0;
  TRT_CATCH(0)
}

int64_t trt_c_config_tactic_sources(int64_t id) {
  TRT_TRY
  clear_error();
  void* cfg = reg_get(id, K_CONFIG);
  if (!cfg) return -1;
  void* impl = impl_of(cfg);
  typedef uint64_t (*Fn)(void*);
  return (int64_t)vfn<Fn>(impl, slot::kCfgGetTacticSources)(impl);
  TRT_CATCH(-1)
}

int32_t trt_c_config_destroy(int64_t id) {
  TRT_TRY
  clear_error();
  void* cfg = nullptr;
  if (!reg_take(id, K_CONFIG, &cfg)) return 0;
  destroy_wrapper(cfg);
  return 1;
  TRT_CATCH(0)
}

// ---- host memory ----------------------------------------------------------

static HostBuffer* host_entry(int64_t id) {
  return reinterpret_cast<HostBuffer*>(reg_get(id, K_HOSTMEM));
}

int64_t trt_c_host_memory_size(int64_t id) {
  TRT_TRY
  clear_error();
  HostBuffer* hb = host_entry(id);
  if (!hb) return -1;
  return (int64_t)hb->size;
  TRT_CATCH(-1)
}

int64_t trt_c_host_memory_data(int64_t id) {
  TRT_TRY
  clear_error();
  HostBuffer* hb = host_entry(id);
  if (!hb) return 0;
  return (int64_t)(uintptr_t)hb->data;
  TRT_CATCH(0)
}

int32_t trt_c_host_memory_save(int64_t id, const char* path) {
  TRT_TRY
  clear_error();
  if (!path || !*path) {
    set_error(kErrInvalidArg, "path is empty");
    return 0;
  }
  HostBuffer* hb = host_entry(id);
  if (!hb) return 0;
  FILE* f = fopen(path, "wb");
  if (!f) {
    set_error(kErrIoFailed, "could not open the output plan file");
    return 0;
  }
  size_t written = fwrite(hb->data, 1, hb->size, f);
  fclose(f);
  if (written != hb->size) {
    set_error(kErrIoFailed, "short write of the serialized plan");
    return 0;
  }
  return 1;
  TRT_CATCH(0)
}

int64_t trt_c_host_memory_load(const char* path) {
  TRT_TRY
  clear_error();
  if (!path || !*path) {
    set_error(kErrInvalidArg, "path is empty");
    return 0;
  }
  FILE* f = fopen(path, "rb");
  if (!f) {
    set_error(kErrIoFailed, "could not open the plan file");
    return 0;
  }
  fseek(f, 0, SEEK_END);
  long n = ftell(f);
  fseek(f, 0, SEEK_SET);
  if (n <= 0) {
    fclose(f);
    set_error(kErrIoFailed, "plan file is empty");
    return 0;
  }
  void* data = malloc((size_t)n);
  if (!data) {
    fclose(f);
    set_error(kErrCallFailed, "out of memory reading the plan");
    return 0;
  }
  size_t got = fread(data, 1, (size_t)n, f);
  fclose(f);
  if (got != (size_t)n) {
    free(data);
    set_error(kErrIoFailed, "short read of the plan file");
    return 0;
  }
  auto* hb = new HostBuffer();
  hb->wrapper = nullptr;
  hb->data = data;
  hb->size = (size_t)n;
  hb->owned = true;
  return reg_add(K_HOSTMEM, hb);
  TRT_CATCH(0)
}

int32_t trt_c_host_memory_destroy(int64_t id) {
  TRT_TRY
  clear_error();
  void* p = nullptr;
  if (!reg_take(id, K_HOSTMEM, &p)) return 0;
  auto* hb = reinterpret_cast<HostBuffer*>(p);
  if (hb->wrapper) {
    destroy_wrapper(hb->wrapper);
  } else if (hb->owned) {
    free(hb->data);
  }
  delete hb;
  return 1;
  TRT_CATCH(0)
}

// ---- runtime --------------------------------------------------------------

int64_t trt_c_runtime_create(int64_t logger_id) {
  TRT_TRY
  clear_error();
  if (!g_api.create_runtime) {
    set_error(kErrLoadAbsent, "TensorRT is not loaded");
    return 0;
  }
  auto* le = logger_entry(logger_id);
  if (!le) return 0;
  if (g_cuda.ready && !cuda_ensure_current()) {
    return 0;
  }
  void* wrapper = g_api.create_runtime((*le).get(), g_api.raw_version);
  if (!wrapper) {
    set_error(kErrCallFailed, "createInferRuntime_INTERNAL returned null");
    return 0;
  }
  auto* e = new RuntimeEntry();
  e->wrapper = wrapper;
  e->logger = *le;
  return reg_add(K_RUNTIME, e);
  TRT_CATCH(0)
}

static RuntimeEntry* runtime_entry(int64_t id) {
  return reinterpret_cast<RuntimeEntry*>(reg_get(id, K_RUNTIME));
}

int32_t trt_c_runtime_destroy(int64_t id) {
  TRT_TRY
  clear_error();
  void* p = nullptr;
  if (!reg_take(id, K_RUNTIME, &p)) return 0;
  auto* e = reinterpret_cast<RuntimeEntry*>(p);
  destroy_wrapper(e->wrapper);
  delete e;
  return 1;
  TRT_CATCH(0)
}

int64_t trt_c_runtime_deserialize(int64_t runtime_id, int64_t data_addr, int64_t size) {
  TRT_TRY
  clear_error();
  if (data_addr <= 0 || size <= 0) {
    set_error(kErrInvalidArg, "plan address/size is invalid");
    return 0;
  }
  RuntimeEntry* e = runtime_entry(runtime_id);
  if (!e) return 0;
  if (g_cuda.ready && !cuda_ensure_current()) return 0;
  void* impl = impl_of(e->wrapper);
  typedef void* (*Fn)(void*, const void*, size_t);
  Fn fn = vfn<Fn>(impl, slot::kRuntimeDeserialize);
  void* engine = fn(impl, (const void*)(uintptr_t)data_addr, (size_t)size);
  if (!engine) {
    set_error(kErrCallFailed, "IRuntime::deserializeCudaEngine returned null");
    return 0;
  }
  return reg_add(K_ENGINE, engine);
  TRT_CATCH(0)
}

int64_t trt_c_runtime_deserialize_memory(int64_t runtime_id, int64_t host_id) {
  TRT_TRY
  clear_error();
  HostBuffer* hb = host_entry(host_id);
  if (!hb) return 0;
  return trt_c_runtime_deserialize(runtime_id, (int64_t)(uintptr_t)hb->data, (int64_t)hb->size);
  TRT_CATCH(0)
}

// ---- engine ---------------------------------------------------------------

static void* engine_entry(int64_t id) {
  return reg_get(id, K_ENGINE);
}

int32_t trt_c_engine_destroy(int64_t id) {
  TRT_TRY
  clear_error();
  void* e = nullptr;
  if (!reg_take(id, K_ENGINE, &e)) return 0;
  destroy_wrapper(e);
  return 1;
  TRT_CATCH(0)
}

int32_t trt_c_engine_nb_io_tensors(int64_t id) {
  TRT_TRY
  clear_error();
  void* e = engine_entry(id);
  if (!e) return -1;
  void* impl = impl_of(e);
  typedef int32_t (*Fn)(void*);
  return vfn<Fn>(impl, slot::kEngineNbIOTensors)(impl);
  TRT_CATCH(-1)
}

const char* trt_c_engine_io_tensor_name(int64_t id, int32_t index) {
  TRT_TRY
  clear_error();
  void* e = engine_entry(id);
  if (!e) return "";
  void* impl = impl_of(e);
  typedef const char* (*Fn)(void*, int32_t);
  const char* s = vfn<Fn>(impl, slot::kEngineIOTensorName)(impl, index);
  return s ? s : "";
  TRT_CATCH("")
}

int32_t trt_c_engine_tensor_dtype(int64_t id, const char* name) {
  TRT_TRY
  clear_error();
  void* e = engine_entry(id);
  if (!e) return -1;
  void* impl = impl_of(e);
  typedef int32_t (*Fn)(void*, const char*);
  return vfn<Fn>(impl, slot::kEngineTensorDataType)(impl, name);
  TRT_CATCH(-1)
}

int32_t trt_c_engine_tensor_location(int64_t id, const char* name) {
  TRT_TRY
  clear_error();
  void* e = engine_entry(id);
  if (!e) return -1;
  void* impl = impl_of(e);
  typedef int32_t (*Fn)(void*, const char*);
  return vfn<Fn>(impl, slot::kEngineTensorLocation)(impl, name);
  TRT_CATCH(-1)
}

int32_t trt_c_engine_tensor_io_mode(int64_t id, const char* name) {
  TRT_TRY
  clear_error();
  void* e = engine_entry(id);
  if (!e) return -1;
  void* impl = impl_of(e);
  typedef int32_t (*Fn)(void*, const char*);
  return vfn<Fn>(impl, slot::kEngineTensorIOMode)(impl, name);
  TRT_CATCH(-1)
}

static bool engine_tensor_dims(int64_t id, const char* name, Dims* out) {
  void* e = engine_entry(id);
  if (!e) return false;
  void* impl = impl_of(e);
  // Same sret-as-second-slot convention as tensor_dims().
  typedef void (*Fn)(void*, Dims*, const char*);
  *out = Dims{};
  vfn<Fn>(impl, slot::kEngineTensorShape)(impl, out, name);
  return true;
}

int32_t trt_c_engine_tensor_ndim(int64_t id, const char* name) {
  TRT_TRY
  clear_error();
  Dims d{};
  if (!engine_tensor_dims(id, name, &d)) return -1;
  return d.nbDims;
  TRT_CATCH(-1)
}

int64_t trt_c_engine_tensor_dim(int64_t id, const char* name, int32_t index) {
  TRT_TRY
  clear_error();
  Dims d{};
  if (!engine_tensor_dims(id, name, &d)) return 0;
  if (index < 0 || index >= d.nbDims) {
    set_error(kErrInvalidArg, "engine tensor dimension index out of range");
    return 0;
  }
  return d.d[index];
  TRT_CATCH(0)
}

int64_t trt_c_engine_create_context(int64_t id) {
  TRT_TRY
  clear_error();
  void* e = engine_entry(id);
  if (!e) return 0;
  if (g_cuda.ready && !cuda_ensure_current()) return 0;
  void* impl = impl_of(e);
  typedef void* (*Fn)(void*);
  void* ctx = vfn<Fn>(impl, slot::kEngineCreateContext)(impl);
  if (!ctx) {
    set_error(kErrCallFailed, "ICudaEngine::createExecutionContext returned null");
    return 0;
  }
  return reg_add(K_CONTEXT, ctx);
  TRT_CATCH(0)
}

// ---- execution context ----------------------------------------------------

static void* context_entry(int64_t id) {
  return reg_get(id, K_CONTEXT);
}

int32_t trt_c_context_destroy(int64_t id) {
  TRT_TRY
  clear_error();
  void* c = nullptr;
  if (!reg_take(id, K_CONTEXT, &c)) return 0;
  destroy_wrapper(c);
  return 1;
  TRT_CATCH(0)
}

int32_t trt_c_context_set_input_shape(int64_t ctx_id, const char* name, int64_t d0, int64_t d1,
                                    int64_t d2, int64_t d3, int64_t d4, int64_t d5,
                                    int64_t d6, int64_t d7, int32_t ndim) {
  TRT_TRY
  clear_error();
  if (!name || !*name) {
    set_error(kErrInvalidArg, "tensor name is empty");
    return 0;
  }
  if (ndim < 0 || ndim > 8) {
    set_error(kErrInvalidArg, "ndim must be 0..8");
    return 0;
  }
  void* c = context_entry(ctx_id);
  if (!c) return 0;
  Dims d = make_dims(ndim, d0, d1, d2, d3, d4, d5, d6, d7);
  void* impl = impl_of(c);
  typedef bool (*Fn)(void*, const char*, const Dims*);
  return vfn<Fn>(impl, slot::kCtxSetInputShape)(impl, name, &d) ? 1 : 0;
  TRT_CATCH(0)
}

int32_t trt_c_context_set_tensor_address(int64_t ctx_id, const char* name, int64_t addr) {
  TRT_TRY
  clear_error();
  if (!name || !*name) {
    set_error(kErrInvalidArg, "tensor name is empty");
    return 0;
  }
  void* c = context_entry(ctx_id);
  if (!c) return 0;
  void* impl = impl_of(c);
  typedef bool (*Fn)(void*, const char*, void*);
  return vfn<Fn>(impl, slot::kCtxSetTensorAddress)(impl, name, (void*)(uintptr_t)addr) ? 1 : 0;
  TRT_CATCH(0)
}

int64_t trt_c_context_tensor_address(int64_t ctx_id, const char* name) {
  TRT_TRY
  clear_error();
  void* c = context_entry(ctx_id);
  if (!c) return -1;
  void* impl = impl_of(c);
  typedef void* (*Fn)(void*, const char*);
  void* p = vfn<Fn>(impl, slot::kCtxGetTensorAddress)(impl, name);
  return (int64_t)(uintptr_t)p;
  TRT_CATCH(-1)
}

int32_t trt_c_context_all_input_dims_specified(int64_t ctx_id) {
  TRT_TRY
  clear_error();
  void* c = context_entry(ctx_id);
  if (!c) return -1;
  void* impl = impl_of(c);
  typedef bool (*Fn)(void*);
  return vfn<Fn>(impl, slot::kCtxAllInputDims)(impl) ? 1 : 0;
  TRT_CATCH(-1)
}

int32_t trt_c_context_enqueue(int64_t ctx_id, int64_t stream_id) {
  TRT_TRY
  clear_error();
  void* c = context_entry(ctx_id);
  void* s = reg_get(stream_id, K_STREAM);
  if (!c || !s) return 0;
  if (g_cuda.ready && !cuda_ensure_current()) return 0;
  void* impl = impl_of(c);
  typedef bool (*Fn)(void*, void*);
  return vfn<Fn>(impl, slot::kCtxEnqueueV3)(impl, s) ? 1 : 0;
  TRT_CATCH(0)
}

// ---- CUDA driver helpers --------------------------------------------------

int32_t trt_c_cuda_init() {
  TRT_TRY
  clear_error();
  if (g_cuda.ready) {
    return 1;
  }
  g_cuda = Cuda();
  g_cuda.module = LoadLibraryA("nvcuda.dll");
  if (!g_cuda.module) {
    set_error(kErrCudaFailed, "nvcuda.dll could not be loaded");
    return 0;
  }
  g_cuda.init = (PFN_cuInit)(void*)GetProcAddress(g_cuda.module, "cuInit");
  g_cuda.device_get = (PFN_cuDeviceGet)(void*)GetProcAddress(g_cuda.module, "cuDeviceGet");
  g_cuda.device_count = (PFN_cuDeviceGetCount)(void*)GetProcAddress(g_cuda.module, "cuDeviceGetCount");
  g_cuda.device_name = (PFN_cuDeviceGetName)(void*)GetProcAddress(g_cuda.module, "cuDeviceGetName");
  g_cuda.primary_retain =
      (PFN_cuDevicePrimaryCtxRetain)(void*)GetProcAddress(g_cuda.module, "cuDevicePrimaryCtxRetain");
  g_cuda.primary_release =
      (PFN_cuDevicePrimaryCtxRelease)(void*)GetProcAddress(g_cuda.module, "cuDevicePrimaryCtxRelease_v2");
  g_cuda.ctx_set_current =
      (PFN_cuCtxSetCurrent)(void*)GetProcAddress(g_cuda.module, "cuCtxSetCurrent");
  g_cuda.mem_alloc = (PFN_cuMemAlloc)(void*)GetProcAddress(g_cuda.module, "cuMemAlloc_v2");
  g_cuda.mem_free = (PFN_cuMemFree)(void*)GetProcAddress(g_cuda.module, "cuMemFree_v2");
  g_cuda.htod = (PFN_cuMemcpyHtoD)(void*)GetProcAddress(g_cuda.module, "cuMemcpyHtoD_v2");
  g_cuda.dtoh = (PFN_cuMemcpyDtoH)(void*)GetProcAddress(g_cuda.module, "cuMemcpyDtoH_v2");
  g_cuda.stream_create = (PFN_cuStreamCreate)(void*)GetProcAddress(g_cuda.module, "cuStreamCreate");
  g_cuda.stream_destroy =
      (PFN_cuStreamDestroy)(void*)GetProcAddress(g_cuda.module, "cuStreamDestroy_v2");
  g_cuda.stream_sync =
      (PFN_cuStreamSynchronize)(void*)GetProcAddress(g_cuda.module, "cuStreamSynchronize");
  if (!g_cuda.init || !g_cuda.device_get || !g_cuda.primary_retain || !g_cuda.ctx_set_current ||
      !g_cuda.mem_alloc || !g_cuda.mem_free || !g_cuda.htod || !g_cuda.dtoh ||
      !g_cuda.stream_create || !g_cuda.stream_destroy || !g_cuda.stream_sync) {
    set_error(kErrCudaFailed, "one or more CUDA driver entry points are missing");
    FreeLibrary(g_cuda.module);
    g_cuda = Cuda();
    return 0;
  }
  int rc = g_cuda.init(0);
  if (rc == 100) {
    set_error(kErrNoDevice, "no CUDA device (cuInit CUDA_ERROR_NO_DEVICE)");
    return 0;
  }
  if (rc != 0) {
    set_error_str(kErrCudaFailed, "cuInit failed (" + std::to_string(rc) + ")");
    return 0;
  }
  int dev = 0;
  rc = g_cuda.device_get(&dev, 0);
  if (rc != 0) {
    set_error_str(kErrCudaFailed, "cuDeviceGet failed (" + std::to_string(rc) + ")");
    return 0;
  }
  rc = g_cuda.primary_retain(&g_cuda.ctx, dev);
  if (rc != 0 || !g_cuda.ctx) {
    set_error_str(kErrCudaFailed, "cuDevicePrimaryCtxRetain failed (" + std::to_string(rc) + ")");
    return 0;
  }
  rc = g_cuda.ctx_set_current(g_cuda.ctx);
  if (rc != 0) {
    set_error_str(kErrCudaFailed, "cuCtxSetCurrent failed (" + std::to_string(rc) + ")");
    return 0;
  }
  g_cuda.ready = true;
  return 1;
  TRT_CATCH(0)
}

int32_t trt_c_cuda_shutdown() {
  TRT_TRY
  clear_error();
  if (g_cuda.ready) {
    for (unsigned long long p : g_cuda.allocs) {
      g_cuda.mem_free(p);
    }
    g_cuda.allocs.clear();
    if (g_cuda.ctx && g_cuda.primary_release) {
      int dev = 0;
      if (g_cuda.device_get) g_cuda.device_get(&dev, 0);
      g_cuda.primary_release(dev);
    }
  }
  if (g_cuda.module) {
    FreeLibrary(g_cuda.module);
  }
  g_cuda = Cuda();
  return 1;
  TRT_CATCH(0)
}

int64_t trt_c_cuda_alloc(int64_t bytes) {
  TRT_TRY
  clear_error();
  if (!g_cuda.ready) {
    set_error(kErrCudaFailed, "CUDA is not initialised; call trt_cuda_init first");
    return 0;
  }
  if (bytes <= 0) {
    set_error(kErrInvalidArg, "allocation size must be positive");
    return 0;
  }
  unsigned long long p = 0;
  int rc = g_cuda.mem_alloc(&p, (unsigned long long)bytes);
  if (rc != 0 || p == 0) {
    set_error_str(kErrCudaFailed, "cuMemAlloc failed (" + std::to_string(rc) + ")");
    return 0;
  }
  g_cuda.allocs.push_back(p);
  return (int64_t)p;
  TRT_CATCH(0)
}

int32_t trt_c_cuda_free(int64_t ptr) {
  TRT_TRY
  clear_error();
  if (!g_cuda.ready) {
    set_error(kErrCudaFailed, "CUDA is not initialised");
    return 0;
  }
  int rc = g_cuda.mem_free((unsigned long long)ptr);
  for (auto it = g_cuda.allocs.begin(); it != g_cuda.allocs.end(); ++it) {
    if (*it == (unsigned long long)ptr) {
      g_cuda.allocs.erase(it);
      break;
    }
  }
  if (rc != 0) {
    set_error_str(kErrCudaFailed, "cuMemFree failed (" + std::to_string(rc) + ")");
    return 0;
  }
  return 1;
  TRT_CATCH(0)
}

int32_t trt_c_cuda_upload(int64_t dev, int64_t src, int64_t bytes) {
  TRT_TRY
  clear_error();
  if (!g_cuda.ready) {
    set_error(kErrCudaFailed, "CUDA is not initialised");
    return 0;
  }
  if (dev <= 0 || src <= 0 || bytes <= 0) {
    set_error(kErrInvalidArg, "upload address/size is invalid");
    return 0;
  }
  int rc = g_cuda.htod((unsigned long long)dev, (const void*)(uintptr_t)src,
                       (unsigned long long)bytes);
  if (rc != 0) {
    set_error_str(kErrCudaFailed, "cuMemcpyHtoD failed (" + std::to_string(rc) + ")");
    return 0;
  }
  return 1;
  TRT_CATCH(0)
}

int32_t trt_c_cuda_download(int64_t dst, int64_t dev, int64_t bytes) {
  TRT_TRY
  clear_error();
  if (!g_cuda.ready) {
    set_error(kErrCudaFailed, "CUDA is not initialised");
    return 0;
  }
  if (dst <= 0 || dev <= 0 || bytes <= 0) {
    set_error(kErrInvalidArg, "download address/size is invalid");
    return 0;
  }
  int rc = g_cuda.dtoh((void*)(uintptr_t)dst, (unsigned long long)dev,
                       (unsigned long long)bytes);
  if (rc != 0) {
    set_error_str(kErrCudaFailed, "cuMemcpyDtoH failed (" + std::to_string(rc) + ")");
    return 0;
  }
  return 1;
  TRT_CATCH(0)
}

int64_t trt_c_cuda_stream_create() {
  TRT_TRY
  clear_error();
  if (!g_cuda.ready) {
    set_error(kErrCudaFailed, "CUDA is not initialised");
    return 0;
  }
  void* s = nullptr;
  int rc = g_cuda.stream_create(&s, 0);
  if (rc != 0 || !s) {
    set_error_str(kErrCudaFailed, "cuStreamCreate failed (" + std::to_string(rc) + ")");
    return 0;
  }
  return reg_add(K_STREAM, s);
  TRT_CATCH(0)
}

int32_t trt_c_cuda_stream_destroy(int64_t id) {
  TRT_TRY
  clear_error();
  void* s = nullptr;
  if (!reg_take(id, K_STREAM, &s)) return 0;
  int rc = g_cuda.stream_destroy(s);
  if (rc != 0) {
    set_error_str(kErrCudaFailed, "cuStreamDestroy failed (" + std::to_string(rc) + ")");
    return 0;
  }
  return 1;
  TRT_CATCH(0)
}

int32_t trt_c_cuda_stream_sync(int64_t id) {
  TRT_TRY
  clear_error();
  void* s = reg_get(id, K_STREAM);
  if (!s) return 0;
  int rc = g_cuda.stream_sync(s);
  if (rc != 0) {
    set_error_str(kErrCudaFailed, "cuStreamSynchronize failed (" + std::to_string(rc) + ")");
    return 0;
  }
  return 1;
  TRT_CATCH(0)
}

const char* trt_c_cuda_device_name() {
  TRT_TRY
  clear_error();
  static char name[256];
  name[0] = 0;
  if (!g_cuda.ready || !g_cuda.device_name) {
    set_error(kErrCudaFailed, "CUDA is not initialised");
    return "";
  }
  int dev = 0;
  if (g_cuda.device_get && g_cuda.device_get(&dev, 0) != 0) {
    set_error(kErrCudaFailed, "cuDeviceGet failed");
    return "";
  }
  if (g_cuda.device_name(name, (int)sizeof(name), dev) != 0) {
    set_error(kErrCudaFailed, "cuDeviceGetName failed");
    return "";
  }
  name[sizeof(name) - 1] = 0;
  return name;
  TRT_CATCH("")
}

int32_t trt_c_cuda_device_count() {
  TRT_TRY
  clear_error();
  if (!g_cuda.ready || !g_cuda.device_count) {
    set_error(kErrCudaFailed, "CUDA is not initialised");
    return -1;
  }
  int n = 0;
  int rc = g_cuda.device_count(&n);
  if (rc != 0) {
    set_error_str(kErrCudaFailed, "cuDeviceGetCount failed (" + std::to_string(rc) + ")");
    return -1;
  }
  return n;
  TRT_CATCH(-1)
}

} // extern "C"

// ---------------------------------------------------------------------------
// Registry teardown
// ---------------------------------------------------------------------------

namespace trt {

static void destroy_entry(int64_t id) {
  auto it = g_reg.find(id);
  if (it == g_reg.end()) return;
  Entry e = it->second;
  g_reg.erase(it);
  switch (e.kind) {
    case K_LOGGER:
      delete reinterpret_cast<std::shared_ptr<BridgeLogger>*>(e.ptr);
      break;
    case K_BUILDER: {
      auto* b = reinterpret_cast<BuilderEntry*>(e.ptr);
      destroy_wrapper(b->wrapper);
      delete b;
      break;
    }
    case K_NETWORK: {
      auto* n = reinterpret_cast<NetworkEntry*>(e.ptr);
      destroy_wrapper(n->wrapper);
      delete n;
      break;
    }
    case K_CONFIG:
    case K_RUNTIME:
      // RuntimeEntry is resolved below by kind.
      if (e.kind == K_RUNTIME) {
        auto* r = reinterpret_cast<RuntimeEntry*>(e.ptr);
        destroy_wrapper(r->wrapper);
        delete r;
      } else {
        destroy_wrapper(e.ptr);
      }
      break;
    case K_HOSTMEM: {
      auto* hb = reinterpret_cast<HostBuffer*>(e.ptr);
      if (hb->wrapper) {
        destroy_wrapper(hb->wrapper);
      } else if (hb->owned) {
        free(hb->data);
      }
      delete hb;
      break;
    }
    case K_ENGINE:
    case K_CONTEXT:
      destroy_wrapper(e.ptr);
      break;
    case K_STREAM:
      if (g_cuda.stream_destroy) {
        g_cuda.stream_destroy(e.ptr);
      }
      break;
    default:
      break;
  }
}

static void destroy_kind(int kind) {
  std::vector<int64_t> ids;
  ids.reserve(g_reg.size());
  for (auto& kv : g_reg) {
    if (kv.second.kind == kind) {
      ids.push_back(kv.first);
    }
  }
  for (int64_t id : ids) {
    destroy_entry(id);
  }
}

static void destroy_registry() {
  // Dependency order: execution contexts -> engines -> host buffers ->
  // configs -> networks -> builders -> runtimes -> loggers -> streams.
  destroy_kind(K_CONTEXT);
  destroy_kind(K_ENGINE);
  destroy_kind(K_HOSTMEM);
  destroy_kind(K_CONFIG);
  destroy_kind(K_NETWORK);
  destroy_kind(K_BUILDER);
  destroy_kind(K_RUNTIME);
  destroy_kind(K_LOGGER);
  destroy_kind(K_STREAM);
  g_reg.clear();
}

} // namespace trt
