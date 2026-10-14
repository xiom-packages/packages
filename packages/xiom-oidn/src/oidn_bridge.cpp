/* xiom.oidn bridge -- MIT OR Apache-2.0 (this file), The XIOM Authors.
 *
 * Self-contained dynamic-loader bridge over the Intel Open Image Denoise
 * v2.5.1 public C API (Apache-2.0). The vendored header set
 * (vendor/include/OpenImageDenoise/oidn.h + config.h) is included for the
 * exact ABI types: every resolved entry point is typed with
 * `decltype(&oidnX)`, so a signature drift against the pinned header is a
 * compile error. No import library, no link-time dependency; the runtime
 * DLL is resolved the first time `xo_oidn_load*` runs.
 *
 * Ownership / safety model (bindings-lane discipline on the v0.64.4 pin):
 *   - handles cross the FFI as int64; all pointer casts happen in C
 *     (B-25: `Int as *UInt8` in XIOM is not value-preserving);
 *   - out-params are XIOM-owned byte slots (unsigned char*) written by C
 *     little-endian; XIOM reads them byte-indexed (B-11/B-16/B-17/B-24);
 *   - foreign buffers are never read through a foreign pointer: image data
 *     moves in/out of OIDN buffers via xo_oidn_buffer_read/write into
 *     XIOM-owned memory (B-20); the raw data address is exposed only as an
 *     integer value for evidence (never dereferenced from XIOM);
 *   - `null` is never passed from XIOM for a nullable C argument (B-23);
 *     nullable pointers are built here (`0` literals are C-side);
 *   - one owned slot per out-param; no pointer arithmetic on XIOM pointers.
 *
 * Error model: every entry point that can fail drains the pending OIDN
 * error queue first, performs the call, then returns the OIDN error code
 * (0 = ok) and stores the message for `xo_oidn_error()`. Successful results
 * are written into the caller's owned slot. Handle-returning calls return 0
 * on failure (message retrievable the same way).
 *
 * The loader table lists the 67 functions of the public C surface exported
 * by OpenImageDenoise.dll v2.5.1; the three C++-only SYCL declarations of
 * oidn.h (oidnIsSYCLDeviceSupported, oidnNewSYCLDevice,
 * oidnExecuteSYCLFilterAsync) are NOT part of the declared surface and are
 * excluded with the rest of the GPU scope (SPEC.md section 1).
 */

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <cstring>
#include <cstdint>
#include <cstdlib>
#include <cstdio>

#include "../vendor/include/OpenImageDenoise/oidn.h"

#ifndef XO_OIDN_SONAME
#define XO_OIDN_SONAME "OpenImageDenoise.dll"
#endif

namespace {

struct OidnApi {
  decltype(&::oidnGetNumPhysicalDevices) p_oidnGetNumPhysicalDevices = 0;
  decltype(&::oidnGetPhysicalDeviceBool) p_oidnGetPhysicalDeviceBool = 0;
  decltype(&::oidnGetPhysicalDeviceInt) p_oidnGetPhysicalDeviceInt = 0;
  decltype(&::oidnGetPhysicalDeviceString) p_oidnGetPhysicalDeviceString = 0;
  decltype(&::oidnGetPhysicalDeviceData) p_oidnGetPhysicalDeviceData = 0;
  decltype(&::oidnIsCPUDeviceSupported) p_oidnIsCPUDeviceSupported = 0;
  decltype(&::oidnIsCUDADeviceSupported) p_oidnIsCUDADeviceSupported = 0;
  decltype(&::oidnIsHIPDeviceSupported) p_oidnIsHIPDeviceSupported = 0;
  decltype(&::oidnIsMetalDeviceSupported) p_oidnIsMetalDeviceSupported = 0;
  decltype(&::oidnNewDevice) p_oidnNewDevice = 0;
  decltype(&::oidnNewDeviceByID) p_oidnNewDeviceByID = 0;
  decltype(&::oidnNewDeviceByUUID) p_oidnNewDeviceByUUID = 0;
  decltype(&::oidnNewDeviceByLUID) p_oidnNewDeviceByLUID = 0;
  decltype(&::oidnNewDeviceByPCIAddress) p_oidnNewDeviceByPCIAddress = 0;
  decltype(&::oidnNewCUDADevice) p_oidnNewCUDADevice = 0;
  decltype(&::oidnNewHIPDevice) p_oidnNewHIPDevice = 0;
  decltype(&::oidnNewMetalDevice) p_oidnNewMetalDevice = 0;
  decltype(&::oidnRetainDevice) p_oidnRetainDevice = 0;
  decltype(&::oidnReleaseDevice) p_oidnReleaseDevice = 0;
  decltype(&::oidnSetDeviceBool) p_oidnSetDeviceBool = 0;
  decltype(&::oidnSetDeviceInt) p_oidnSetDeviceInt = 0;
  decltype(&::oidnGetDeviceBool) p_oidnGetDeviceBool = 0;
  decltype(&::oidnGetDeviceInt) p_oidnGetDeviceInt = 0;
  decltype(&::oidnSetDeviceErrorFunction) p_oidnSetDeviceErrorFunction = 0;
  decltype(&::oidnGetDeviceError) p_oidnGetDeviceError = 0;
  decltype(&::oidnCommitDevice) p_oidnCommitDevice = 0;
  decltype(&::oidnSyncDevice) p_oidnSyncDevice = 0;
  decltype(&::oidnNewBuffer) p_oidnNewBuffer = 0;
  decltype(&::oidnNewBufferWithStorage) p_oidnNewBufferWithStorage = 0;
  decltype(&::oidnNewSharedBuffer) p_oidnNewSharedBuffer = 0;
  decltype(&::oidnNewSharedBufferFromFD) p_oidnNewSharedBufferFromFD = 0;
  decltype(&::oidnNewSharedBufferFromWin32Handle) p_oidnNewSharedBufferFromWin32Handle = 0;
  decltype(&::oidnNewSharedBufferFromMetal) p_oidnNewSharedBufferFromMetal = 0;
  decltype(&::oidnGetBufferSize) p_oidnGetBufferSize = 0;
  decltype(&::oidnGetBufferStorage) p_oidnGetBufferStorage = 0;
  decltype(&::oidnGetBufferData) p_oidnGetBufferData = 0;
  decltype(&::oidnReadBuffer) p_oidnReadBuffer = 0;
  decltype(&::oidnReadBufferAsync) p_oidnReadBufferAsync = 0;
  decltype(&::oidnWriteBuffer) p_oidnWriteBuffer = 0;
  decltype(&::oidnWriteBufferAsync) p_oidnWriteBufferAsync = 0;
  decltype(&::oidnRetainBuffer) p_oidnRetainBuffer = 0;
  decltype(&::oidnReleaseBuffer) p_oidnReleaseBuffer = 0;
  decltype(&::oidnNewSharedSemaphoreFromFD) p_oidnNewSharedSemaphoreFromFD = 0;
  decltype(&::oidnNewSharedSemaphoreFromWin32Handle) p_oidnNewSharedSemaphoreFromWin32Handle = 0;
  decltype(&::oidnSignalSemaphoresAsync) p_oidnSignalSemaphoresAsync = 0;
  decltype(&::oidnWaitSemaphoresAsync) p_oidnWaitSemaphoresAsync = 0;
  decltype(&::oidnRetainSemaphore) p_oidnRetainSemaphore = 0;
  decltype(&::oidnReleaseSemaphore) p_oidnReleaseSemaphore = 0;
  decltype(&::oidnNewFilter) p_oidnNewFilter = 0;
  decltype(&::oidnRetainFilter) p_oidnRetainFilter = 0;
  decltype(&::oidnReleaseFilter) p_oidnReleaseFilter = 0;
  decltype(&::oidnSetFilterImage) p_oidnSetFilterImage = 0;
  decltype(&::oidnSetSharedFilterImage) p_oidnSetSharedFilterImage = 0;
  decltype(&::oidnUnsetFilterImage) p_oidnUnsetFilterImage = 0;
  decltype(&::oidnSetSharedFilterData) p_oidnSetSharedFilterData = 0;
  decltype(&::oidnUpdateFilterData) p_oidnUpdateFilterData = 0;
  decltype(&::oidnUnsetFilterData) p_oidnUnsetFilterData = 0;
  decltype(&::oidnSetFilterBool) p_oidnSetFilterBool = 0;
  decltype(&::oidnGetFilterBool) p_oidnGetFilterBool = 0;
  decltype(&::oidnSetFilterInt) p_oidnSetFilterInt = 0;
  decltype(&::oidnGetFilterInt) p_oidnGetFilterInt = 0;
  decltype(&::oidnSetFilterFloat) p_oidnSetFilterFloat = 0;
  decltype(&::oidnGetFilterFloat) p_oidnGetFilterFloat = 0;
  decltype(&::oidnSetFilterProgressMonitorFunction) p_oidnSetFilterProgressMonitorFunction = 0;
  decltype(&::oidnCommitFilter) p_oidnCommitFilter = 0;
  decltype(&::oidnExecuteFilter) p_oidnExecuteFilter = 0;
  decltype(&::oidnExecuteFilterAsync) p_oidnExecuteFilterAsync = 0;
};

const char* const kRequired[] = {
  "oidnGetNumPhysicalDevices",
  "oidnGetPhysicalDeviceBool",
  "oidnGetPhysicalDeviceInt",
  "oidnGetPhysicalDeviceString",
  "oidnGetPhysicalDeviceData",
  "oidnIsCPUDeviceSupported",
  "oidnIsCUDADeviceSupported",
  "oidnIsHIPDeviceSupported",
  "oidnIsMetalDeviceSupported",
  "oidnNewDevice",
  "oidnNewDeviceByID",
  "oidnNewDeviceByUUID",
  "oidnNewDeviceByLUID",
  "oidnNewDeviceByPCIAddress",
  "oidnNewCUDADevice",
  "oidnNewHIPDevice",
  "oidnNewMetalDevice",
  "oidnRetainDevice",
  "oidnReleaseDevice",
  "oidnSetDeviceBool",
  "oidnSetDeviceInt",
  "oidnGetDeviceBool",
  "oidnGetDeviceInt",
  "oidnSetDeviceErrorFunction",
  "oidnGetDeviceError",
  "oidnCommitDevice",
  "oidnSyncDevice",
  "oidnNewBuffer",
  "oidnNewBufferWithStorage",
  "oidnNewSharedBuffer",
  "oidnNewSharedBufferFromFD",
  "oidnNewSharedBufferFromWin32Handle",
  "oidnNewSharedBufferFromMetal",
  "oidnGetBufferSize",
  "oidnGetBufferStorage",
  "oidnGetBufferData",
  "oidnReadBuffer",
  "oidnReadBufferAsync",
  "oidnWriteBuffer",
  "oidnWriteBufferAsync",
  "oidnRetainBuffer",
  "oidnReleaseBuffer",
  "oidnNewSharedSemaphoreFromFD",
  "oidnNewSharedSemaphoreFromWin32Handle",
  "oidnSignalSemaphoresAsync",
  "oidnWaitSemaphoresAsync",
  "oidnRetainSemaphore",
  "oidnReleaseSemaphore",
  "oidnNewFilter",
  "oidnRetainFilter",
  "oidnReleaseFilter",
  "oidnSetFilterImage",
  "oidnSetSharedFilterImage",
  "oidnUnsetFilterImage",
  "oidnSetSharedFilterData",
  "oidnUpdateFilterData",
  "oidnUnsetFilterData",
  "oidnSetFilterBool",
  "oidnGetFilterBool",
  "oidnSetFilterInt",
  "oidnGetFilterInt",
  "oidnSetFilterFloat",
  "oidnGetFilterFloat",
  "oidnSetFilterProgressMonitorFunction",
  "oidnCommitFilter",
  "oidnExecuteFilter",
  "oidnExecuteFilterAsync",
};

const int kRequiredCount = (int)(sizeof(kRequired) / sizeof(kRequired[0]));

HMODULE g_lib = 0;
OidnApi g_api;
int g_resolved = 0;
int g_missing = 0;
char g_missingFirst[64];
char g_lastError[512];

void xo_set_error(const char* msg) {
  if (msg == 0) { g_lastError[0] = 0; return; }
  size_t n = strlen(msg);
  if (n >= sizeof(g_lastError)) n = sizeof(g_lastError) - 1;
  memcpy(g_lastError, msg, n);
  g_lastError[n] = 0;
}

void xo_set_error_code(const char* prefix, int code) {
  char buf[96];
  snprintf(buf, sizeof(buf), "%s (code %d)", prefix, code);
  xo_set_error(buf);
}

void write_u8(unsigned char* out, unsigned char v) { if (out) out[0] = v; }

void write_i32(unsigned char* out, int v) {
  if (!out) return;
  unsigned int u = (unsigned int)v;
  out[0] = (unsigned char)(u & 0xFF);
  out[1] = (unsigned char)((u >> 8) & 0xFF);
  out[2] = (unsigned char)((u >> 16) & 0xFF);
  out[3] = (unsigned char)((u >> 24) & 0xFF);
}

void write_u64(unsigned char* out, unsigned long long v) {
  if (!out) return;
  for (int i = 0; i < 8; ++i) out[i] = (unsigned char)((v >> (8 * i)) & 0xFF);
}

void write_f32(unsigned char* out, float v) {
  unsigned int u;
  memcpy(&u, &v, 4);
  write_i32(out, (int)u);
}

unsigned long long read_u64(const unsigned char* in) {
  unsigned long long v = 0;
  if (!in) return 0;
  for (int i = 0; i < 8; ++i) v |= ((unsigned long long)in[i]) << (8 * i);
  return v;
}

OIDNDevice dev_of(long long h) { return reinterpret_cast<OIDNDevice>(h); }
OIDNBuffer buf_of(long long h) { return reinterpret_cast<OIDNBuffer>(h); }
OIDNFilter filt_of(long long h) { return reinterpret_cast<OIDNFilter>(h); }
OIDNSemaphore sem_of(long long h) { return reinterpret_cast<OIDNSemaphore>(h); }
long long handle_of(const void* p) { return (long long)(uintptr_t)p; }

// Drain the pending OIDN error queue (bounded) so the status returned by the
// next operation belongs to that operation alone.
void drain_device(OIDNDevice dev) {
  const char* msg = 0;
  int guard = 0;
  while (guard < 16 && g_api.p_oidnGetDeviceError(dev, &msg) != OIDN_ERROR_NONE) guard++;
}

void drain_global() {
  const char* msg = 0;
  int guard = 0;
  while (guard < 16 && g_api.p_oidnGetDeviceError(0, &msg) != OIDN_ERROR_NONE) guard++;
}

// Fetch the first pending error; returns the code (0 = clean) and stores the
// message in g_lastError.
int fetch_error(OIDNDevice dev) {
  const char* msg = 0;
  int code = (int)g_api.p_oidnGetDeviceError(dev, &msg);
  if (code != OIDN_ERROR_NONE) xo_set_error(msg);
  return code;
}

int fetch_error_global() {
  const char* msg = 0;
  int code = (int)g_api.p_oidnGetDeviceError(0, &msg);
  if (code != OIDN_ERROR_NONE) xo_set_error(msg);
  return code;
}

// Handle-returning entry points report failure as negative error codes so
// the XIOM wrapper can build a typed error with the real OIDN code (0 means
// failure without a captured code).
long long fail_handle(int code) { return code != 0 ? -(long long)code : 0; }

int g_progressHits = 0;
bool progress_cb(void* userPtr, double n) {
  (void)userPtr; (void)n;
  g_progressHits++;
  return true;
}

int g_errFnHits = 0;
char g_errFnLast[512];
void error_cb(void* userPtr, OIDNError code, const char* message) {
  (void)userPtr; (void)code;
  g_errFnHits++;
  xo_set_error(message);      // also visible through xo_oidn_error()
  if (message) {
    size_t n = strlen(message);
    if (n >= sizeof(g_errFnLast)) n = sizeof(g_errFnLast) - 1;
    memcpy(g_errFnLast, message, n);
    g_errFnLast[n] = 0;
  }
}

} // namespace

extern "C" {

const char* xo_oidn_soname(void) { return XO_OIDN_SONAME; }

int xo_oidn_loaded(void) { return g_lib != 0; }

int xo_oidn_export_count(void) { return kRequiredCount; }

int xo_oidn_resolved_count(void) { return g_resolved; }

int xo_oidn_missing_count(void) { return g_missing; }

const char* xo_oidn_error(void) { return g_lastError; }

int xo_oidn_missing_name(int idx, unsigned char* dst, int cap) {
  if (g_missing == 0) return -1;
  if (idx != 0) return -1;
  int n = (int)strlen(g_missingFirst);
  if (cap <= 0 || dst == 0) return -1;
  int copy = (n < cap - 1) ? n : cap - 1;
  memcpy(dst, g_missingFirst, (size_t)copy);
  dst[copy] = 0;
  return copy;
}

int xo_oidn_load_named(const char* soname) {
  if (soname == 0 || soname[0] == 0) {
    xo_set_error("oidn: empty library name");
    return 2;
  }
  if (g_lib) { g_resolved = kRequiredCount; g_missing = 0; return 0; }

  g_lib = LoadLibraryA(soname);
  if (g_lib == 0) {
    xo_set_error_code("oidn: library not found", (int)GetLastError());
    return 1;
  }

  g_resolved = 0;
  g_missing = 0;
  g_missingFirst[0] = 0;

#define XO_RESOLVE(name)                                                        \
  g_api.p_##name = reinterpret_cast<decltype(&::name)>(GetProcAddress(g_lib, #name)); \
  if (g_api.p_##name != 0) { g_resolved++; }                                    \
  else { g_missing++; if (g_missingFirst[0] == 0) {                             \
    size_t n = strlen(#name); if (n >= sizeof(g_missingFirst)) n = sizeof(g_missingFirst) - 1; \
    memcpy(g_missingFirst, #name, n); g_missingFirst[n] = 0; } }

  XO_RESOLVE(oidnGetNumPhysicalDevices)
  XO_RESOLVE(oidnGetPhysicalDeviceBool)
  XO_RESOLVE(oidnGetPhysicalDeviceInt)
  XO_RESOLVE(oidnGetPhysicalDeviceString)
  XO_RESOLVE(oidnGetPhysicalDeviceData)
  XO_RESOLVE(oidnIsCPUDeviceSupported)
  XO_RESOLVE(oidnIsCUDADeviceSupported)
  XO_RESOLVE(oidnIsHIPDeviceSupported)
  XO_RESOLVE(oidnIsMetalDeviceSupported)
  XO_RESOLVE(oidnNewDevice)
  XO_RESOLVE(oidnNewDeviceByID)
  XO_RESOLVE(oidnNewDeviceByUUID)
  XO_RESOLVE(oidnNewDeviceByLUID)
  XO_RESOLVE(oidnNewDeviceByPCIAddress)
  XO_RESOLVE(oidnNewCUDADevice)
  XO_RESOLVE(oidnNewHIPDevice)
  XO_RESOLVE(oidnNewMetalDevice)
  XO_RESOLVE(oidnRetainDevice)
  XO_RESOLVE(oidnReleaseDevice)
  XO_RESOLVE(oidnSetDeviceBool)
  XO_RESOLVE(oidnSetDeviceInt)
  XO_RESOLVE(oidnGetDeviceBool)
  XO_RESOLVE(oidnGetDeviceInt)
  XO_RESOLVE(oidnSetDeviceErrorFunction)
  XO_RESOLVE(oidnGetDeviceError)
  XO_RESOLVE(oidnCommitDevice)
  XO_RESOLVE(oidnSyncDevice)
  XO_RESOLVE(oidnNewBuffer)
  XO_RESOLVE(oidnNewBufferWithStorage)
  XO_RESOLVE(oidnNewSharedBuffer)
  XO_RESOLVE(oidnNewSharedBufferFromFD)
  XO_RESOLVE(oidnNewSharedBufferFromWin32Handle)
  XO_RESOLVE(oidnNewSharedBufferFromMetal)
  XO_RESOLVE(oidnGetBufferSize)
  XO_RESOLVE(oidnGetBufferStorage)
  XO_RESOLVE(oidnGetBufferData)
  XO_RESOLVE(oidnReadBuffer)
  XO_RESOLVE(oidnReadBufferAsync)
  XO_RESOLVE(oidnWriteBuffer)
  XO_RESOLVE(oidnWriteBufferAsync)
  XO_RESOLVE(oidnRetainBuffer)
  XO_RESOLVE(oidnReleaseBuffer)
  XO_RESOLVE(oidnNewSharedSemaphoreFromFD)
  XO_RESOLVE(oidnNewSharedSemaphoreFromWin32Handle)
  XO_RESOLVE(oidnSignalSemaphoresAsync)
  XO_RESOLVE(oidnWaitSemaphoresAsync)
  XO_RESOLVE(oidnRetainSemaphore)
  XO_RESOLVE(oidnReleaseSemaphore)
  XO_RESOLVE(oidnNewFilter)
  XO_RESOLVE(oidnRetainFilter)
  XO_RESOLVE(oidnReleaseFilter)
  XO_RESOLVE(oidnSetFilterImage)
  XO_RESOLVE(oidnSetSharedFilterImage)
  XO_RESOLVE(oidnUnsetFilterImage)
  XO_RESOLVE(oidnSetSharedFilterData)
  XO_RESOLVE(oidnUpdateFilterData)
  XO_RESOLVE(oidnUnsetFilterData)
  XO_RESOLVE(oidnSetFilterBool)
  XO_RESOLVE(oidnGetFilterBool)
  XO_RESOLVE(oidnSetFilterInt)
  XO_RESOLVE(oidnGetFilterInt)
  XO_RESOLVE(oidnSetFilterFloat)
  XO_RESOLVE(oidnGetFilterFloat)
  XO_RESOLVE(oidnSetFilterProgressMonitorFunction)
  XO_RESOLVE(oidnCommitFilter)
  XO_RESOLVE(oidnExecuteFilter)
  XO_RESOLVE(oidnExecuteFilterAsync)
#undef XO_RESOLVE

  if (g_missing != 0) {
    xo_set_error("oidn: library is missing required exports");
    return 2;
  }
  xo_set_error("");
  return 0;
}

int xo_oidn_load(void) { return xo_oidn_load_named(XO_OIDN_SONAME); }

void xo_oidn_unload(void) {
  if (g_lib) { FreeLibrary(g_lib); g_lib = 0; }
  g_resolved = 0;
  g_missing = 0;
  g_missingFirst[0] = 0;
  xo_set_error("");
}

/* ------------------------------------------------------------------ */
/* Physical devices + device support flags (global error channel)      */
/* ------------------------------------------------------------------ */

int xo_oidn_num_physical_devices(unsigned char* out4) {
  if (!g_lib) { xo_set_error("oidn: not loaded"); return -1; }
  drain_global();
  int n = g_api.p_oidnGetNumPhysicalDevices();
  int code = fetch_error_global();
  if (code != 0) return code;
  write_i32(out4, n);
  return 0;
}

int xo_oidn_physical_device_get_bool(int id, const char* name, unsigned char* out1) {
  if (!g_lib) { xo_set_error("oidn: not loaded"); return -1; }
  drain_global();
  bool v = g_api.p_oidnGetPhysicalDeviceBool(id, name);
  int code = fetch_error_global();
  if (code != 0) return code;
  write_u8(out1, v ? 1 : 0);
  return 0;
}

int xo_oidn_physical_device_get_int(int id, const char* name, unsigned char* out4) {
  if (!g_lib) { xo_set_error("oidn: not loaded"); return -1; }
  drain_global();
  int v = g_api.p_oidnGetPhysicalDeviceInt(id, name);
  int code = fetch_error_global();
  if (code != 0) return code;
  write_i32(out4, v);
  return 0;
}

int xo_oidn_physical_device_get_string(int id, const char* name, unsigned char* dst, int cap, unsigned char* out4len) {
  if (!g_lib) { xo_set_error("oidn: not loaded"); return -1; }
  drain_global();
  const char* s = g_api.p_oidnGetPhysicalDeviceString(id, name);
  int code = fetch_error_global();
  if (code != 0) return code;
  if (s == 0) { write_i32(out4len, 0); return 0; }
  size_t n = strlen(s);
  int copy = (cap > 0 && (int)n > cap - 1) ? cap - 1 : (int)n;
  if (copy < 0) copy = 0;
  if (dst != 0 && cap > 0) {
    memcpy(dst, s, (size_t)copy);
    dst[copy] = 0;
  }
  write_i32(out4len, copy);
  return 0;
}

int xo_oidn_physical_device_get_data(int id, const char* name, unsigned char* dst, int cap, unsigned char* out4len) {
  if (!g_lib) { xo_set_error("oidn: not loaded"); return -1; }
  drain_global();
  size_t byteSize = 0;
  const void* data = g_api.p_oidnGetPhysicalDeviceData(id, name, &byteSize);
  int code = fetch_error_global();
  if (code != 0) return code;
  if (data == 0) { write_i32(out4len, 0); return 0; }
  int copy = ((int)byteSize < cap) ? (int)byteSize : cap;
  if (copy < 0) copy = 0;
  if (dst != 0 && copy > 0) memcpy(dst, data, (size_t)copy);
  write_i32(out4len, copy);
  return 0;
}

int xo_oidn_is_cpu_device_supported(unsigned char* out1) {
  if (!g_lib) { xo_set_error("oidn: not loaded"); return -1; }
  drain_global();
  bool v = g_api.p_oidnIsCPUDeviceSupported();
  int code = fetch_error_global();
  if (code != 0) return code;
  write_u8(out1, v ? 1 : 0);
  return 0;
}

int xo_oidn_is_cuda_device_supported(int deviceId, unsigned char* out1) {
  if (!g_lib) { xo_set_error("oidn: not loaded"); return -1; }
  drain_global();
  bool v = g_api.p_oidnIsCUDADeviceSupported(deviceId);
  int code = fetch_error_global();
  if (code != 0) return code;
  write_u8(out1, v ? 1 : 0);
  return 0;
}

int xo_oidn_is_hip_device_supported(int deviceId, unsigned char* out1) {
  if (!g_lib) { xo_set_error("oidn: not loaded"); return -1; }
  drain_global();
  bool v = g_api.p_oidnIsHIPDeviceSupported(deviceId);
  int code = fetch_error_global();
  if (code != 0) return code;
  write_u8(out1, v ? 1 : 0);
  return 0;
}

int xo_oidn_is_metal_device_supported(long long device, unsigned char* out1) {
  if (!g_lib) { xo_set_error("oidn: not loaded"); return -1; }
  drain_global();
  bool v = g_api.p_oidnIsMetalDeviceSupported(reinterpret_cast<MTLDevice_id>(device));
  int code = fetch_error_global();
  if (code != 0) return code;
  write_u8(out1, v ? 1 : 0);
  return 0;
}

/* ------------------------------------------------------------------ */
/* Device lifecycle                                                    */
/* ------------------------------------------------------------------ */

long long xo_oidn_device_new(int type) {
  if (!g_lib) { xo_set_error("oidn: not loaded"); return 0; }
  drain_global();
  OIDNDevice dev = g_api.p_oidnNewDevice((OIDNDeviceType)type);
  if (dev == 0) { return fail_handle(fetch_error_global()); }
  return handle_of(dev);
}

long long xo_oidn_device_new_default(void) { return xo_oidn_device_new(OIDN_DEVICE_TYPE_DEFAULT); }

long long xo_oidn_device_new_cpu(void) { return xo_oidn_device_new(OIDN_DEVICE_TYPE_CPU); }

long long xo_oidn_device_new_by_id(int physicalDeviceID) {
  if (!g_lib) { xo_set_error("oidn: not loaded"); return 0; }
  drain_global();
  OIDNDevice dev = g_api.p_oidnNewDeviceByID(physicalDeviceID);
  if (dev == 0) { return fail_handle(fetch_error_global()); }
  return handle_of(dev);
}

long long xo_oidn_device_new_by_uuid(const unsigned char* uuid16) {
  if (!g_lib) { xo_set_error("oidn: not loaded"); return 0; }
  drain_global();
  OIDNDevice dev = g_api.p_oidnNewDeviceByUUID((const void*)uuid16);
  if (dev == 0) { return fail_handle(fetch_error_global()); }
  return handle_of(dev);
}

long long xo_oidn_device_new_by_luid(const unsigned char* luid8) {
  if (!g_lib) { xo_set_error("oidn: not loaded"); return 0; }
  drain_global();
  OIDNDevice dev = g_api.p_oidnNewDeviceByLUID((const void*)luid8);
  if (dev == 0) { return fail_handle(fetch_error_global()); }
  return handle_of(dev);
}

long long xo_oidn_device_new_by_pci_address(int pciDomain, int pciBus, int pciDevice, int pciFunction) {
  if (!g_lib) { xo_set_error("oidn: not loaded"); return 0; }
  drain_global();
  OIDNDevice dev = g_api.p_oidnNewDeviceByPCIAddress(pciDomain, pciBus, pciDevice, pciFunction);
  if (dev == 0) { return fail_handle(fetch_error_global()); }
  return handle_of(dev);
}

long long xo_oidn_device_new_cuda(int deviceID) {
  if (!g_lib) { xo_set_error("oidn: not loaded"); return 0; }
  drain_global();
  int ids[1];
  int* streams[1];
  ids[0] = deviceID;
  streams[0] = 0;
  OIDNDevice dev = g_api.p_oidnNewCUDADevice(ids, (const cudaStream_t*)streams, 1);
  if (dev == 0) { return fail_handle(fetch_error_global()); }
  return handle_of(dev);
}

long long xo_oidn_device_new_hip(int deviceID) {
  if (!g_lib) { xo_set_error("oidn: not loaded"); return 0; }
  drain_global();
  int ids[1];
  int* streams[1];
  ids[0] = deviceID;
  streams[0] = 0;
  OIDNDevice dev = g_api.p_oidnNewHIPDevice(ids, (const hipStream_t*)streams, 1);
  if (dev == 0) { return fail_handle(fetch_error_global()); }
  return handle_of(dev);
}

long long xo_oidn_device_new_metal(long long commandQueue) {
  if (!g_lib) { xo_set_error("oidn: not loaded"); return 0; }
  drain_global();
  MTLCommandQueue_id queues[1];
  queues[0] = reinterpret_cast<MTLCommandQueue_id>(commandQueue);
  OIDNDevice dev = g_api.p_oidnNewMetalDevice((const MTLCommandQueue_id*)queues, 1);
  if (dev == 0) { return fail_handle(fetch_error_global()); }
  return handle_of(dev);
}

int xo_oidn_device_retain(long long device) {
  if (!g_lib) { xo_set_error("oidn: not loaded"); return -1; }
  if (device == 0) { xo_set_error("oidn: null device handle"); return -1; }
  g_api.p_oidnRetainDevice(dev_of(device));
  return 0;
}

int xo_oidn_device_release(long long device) {
  if (!g_lib) { xo_set_error("oidn: not loaded"); return -1; }
  if (device == 0) { xo_set_error("oidn: null device handle"); return -1; }
  // Release invalidates the handle: no error-queue access after the call.
  g_api.p_oidnReleaseDevice(dev_of(device));
  return 0;
}

int xo_oidn_device_clear_errors(long long device) {
  if (!g_lib) { xo_set_error("oidn: not loaded"); return -1; }
  drain_device(dev_of(device));
  return 0;
}

int xo_oidn_device_get_error(long long device, unsigned char* msg, int cap, unsigned char* out4code) {
  if (!g_lib) { xo_set_error("oidn: not loaded"); return -1; }
  const char* m = 0;
  int code = (int)g_api.p_oidnGetDeviceError(device == 0 ? 0 : dev_of(device), &m);
  if (m != 0 && msg != 0 && cap > 0) {
    size_t n = strlen(m);
    int copy = ((int)n < cap - 1) ? (int)n : cap - 1;
    memcpy(msg, m, (size_t)copy);
    msg[copy] = 0;
  }
  write_i32(out4code, code);
  return 0;
}

int xo_oidn_device_commit(long long device) {
  if (!g_lib) { xo_set_error("oidn: not loaded"); return -1; }
  OIDNDevice dev = dev_of(device);
  drain_device(dev);
  g_api.p_oidnCommitDevice(dev);
  return fetch_error(dev);
}

int xo_oidn_device_sync(long long device) {
  if (!g_lib) { xo_set_error("oidn: not loaded"); return -1; }
  OIDNDevice dev = dev_of(device);
  drain_device(dev);
  g_api.p_oidnSyncDevice(dev);
  return fetch_error(dev);
}

int xo_oidn_device_get_bool(long long device, const char* name, unsigned char* out1) {
  if (!g_lib) { xo_set_error("oidn: not loaded"); return -1; }
  OIDNDevice dev = dev_of(device);
  drain_device(dev);
  bool v = g_api.p_oidnGetDeviceBool(dev, name);
  int code = fetch_error(dev);
  if (code != 0) return code;
  write_u8(out1, v ? 1 : 0);
  return 0;
}

int xo_oidn_device_get_int(long long device, const char* name, unsigned char* out4) {
  if (!g_lib) { xo_set_error("oidn: not loaded"); return -1; }
  OIDNDevice dev = dev_of(device);
  drain_device(dev);
  int v = g_api.p_oidnGetDeviceInt(dev, name);
  int code = fetch_error(dev);
  if (code != 0) return code;
  write_i32(out4, v);
  return 0;
}

int xo_oidn_device_set_bool(long long device, const char* name, int value) {
  if (!g_lib) { xo_set_error("oidn: not loaded"); return -1; }
  OIDNDevice dev = dev_of(device);
  drain_device(dev);
  g_api.p_oidnSetDeviceBool(dev, name, value != 0);
  return fetch_error(dev);
}

int xo_oidn_device_set_int(long long device, const char* name, int value) {
  if (!g_lib) { xo_set_error("oidn: not loaded"); return -1; }
  OIDNDevice dev = dev_of(device);
  drain_device(dev);
  g_api.p_oidnSetDeviceInt(dev, name, value);
  return fetch_error(dev);
}

/* Bridge-owned error function: covers oidnSetDeviceErrorFunction without
 * crossing an XIOM fn value into C (B-13/B-18/B-22 family). */
int xo_oidn_device_set_error_function(long long device, int enable) {
  if (!g_lib) { xo_set_error("oidn: not loaded"); return -1; }
  OIDNDevice dev = dev_of(device);
  g_api.p_oidnSetDeviceErrorFunction(dev, enable ? error_cb : (OIDNErrorFunction)0, 0);
  return 0;
}

int xo_oidn_device_error_function_hits(unsigned char* out4) {
  write_i32(out4, g_errFnHits);
  return 0;
}

int xo_oidn_device_error_function_last(unsigned char* dst, int cap, unsigned char* out4len) {
  int n = (int)strlen(g_errFnLast);
  int copy = (n < cap - 1) ? n : cap - 1;
  if (copy < 0) copy = 0;
  if (dst != 0 && cap > 0) {
    memcpy(dst, g_errFnLast, (size_t)copy);
    dst[copy] = 0;
  }
  write_i32(out4len, copy);
  return 0;
}

/* ------------------------------------------------------------------ */
/* Buffers                                                             */
/* ------------------------------------------------------------------ */

long long xo_oidn_buffer_new(long long device, long long byteSize) {
  if (!g_lib) { xo_set_error("oidn: not loaded"); return 0; }
  OIDNDevice dev = dev_of(device);
  drain_device(dev);
  OIDNBuffer buf = g_api.p_oidnNewBuffer(dev, (size_t)byteSize);
  if (buf == 0) { return fail_handle(fetch_error(dev)); }
  return handle_of(buf);
}

long long xo_oidn_buffer_new_with_storage(long long device, long long byteSize, int storage) {
  if (!g_lib) { xo_set_error("oidn: not loaded"); return 0; }
  OIDNDevice dev = dev_of(device);
  drain_device(dev);
  OIDNBuffer buf = g_api.p_oidnNewBufferWithStorage(dev, (size_t)byteSize, (OIDNStorage)storage);
  if (buf == 0) { return fail_handle(fetch_error(dev)); }
  return handle_of(buf);
}

long long xo_oidn_buffer_new_shared(long long device, unsigned char* ptr, long long byteSize) {
  if (!g_lib) { xo_set_error("oidn: not loaded"); return 0; }
  OIDNDevice dev = dev_of(device);
  drain_device(dev);
  OIDNBuffer buf = g_api.p_oidnNewSharedBuffer(dev, (void*)ptr, (size_t)byteSize);
  if (buf == 0) { return fail_handle(fetch_error(dev)); }
  return handle_of(buf);
}

long long xo_oidn_buffer_new_shared_fd(long long device, int flags, int fd, long long byteSize) {
  if (!g_lib) { xo_set_error("oidn: not loaded"); return 0; }
  OIDNDevice dev = dev_of(device);
  drain_device(dev);
  OIDNBuffer buf = g_api.p_oidnNewSharedBufferFromFD(dev, (OIDNExternalMemoryTypeFlags)flags, fd, (size_t)byteSize);
  if (buf == 0) { return fail_handle(fetch_error(dev)); }
  return handle_of(buf);
}

long long xo_oidn_buffer_new_shared_win32(long long device, int flags, long long handle, long long name, long long byteSize) {
  if (!g_lib) { xo_set_error("oidn: not loaded"); return 0; }
  OIDNDevice dev = dev_of(device);
  drain_device(dev);
  OIDNBuffer buf = g_api.p_oidnNewSharedBufferFromWin32Handle(
      dev, (OIDNExternalMemoryTypeFlags)flags,
      reinterpret_cast<void*>(handle),
      reinterpret_cast<const void*>(name),
      (size_t)byteSize);
  if (buf == 0) { return fail_handle(fetch_error(dev)); }
  return handle_of(buf);
}

long long xo_oidn_buffer_new_shared_metal(long long device, long long metalBuffer) {
  if (!g_lib) { xo_set_error("oidn: not loaded"); return 0; }
  OIDNDevice dev = dev_of(device);
  drain_device(dev);
  OIDNBuffer buf = g_api.p_oidnNewSharedBufferFromMetal(dev, reinterpret_cast<MTLBuffer_id>(metalBuffer));
  if (buf == 0) { return fail_handle(fetch_error(dev)); }
  return handle_of(buf);
}

int xo_oidn_buffer_retain(long long buffer) {
  if (!g_lib) { xo_set_error("oidn: not loaded"); return -1; }
  if (buffer == 0) { xo_set_error("oidn: null buffer handle"); return -1; }
  g_api.p_oidnRetainBuffer(buf_of(buffer));
  return 0;
}

int xo_oidn_buffer_release(long long buffer) {
  if (!g_lib) { xo_set_error("oidn: not loaded"); return -1; }
  if (buffer == 0) { xo_set_error("oidn: null buffer handle"); return -1; }
  g_api.p_oidnReleaseBuffer(buf_of(buffer));
  return 0;
}

int xo_oidn_buffer_size(long long device, long long buffer, unsigned char* out8) {
  if (!g_lib) { xo_set_error("oidn: not loaded"); return -1; }
  OIDNDevice dev = dev_of(device);
  drain_device(dev);
  size_t v = g_api.p_oidnGetBufferSize(buf_of(buffer));
  int code = fetch_error(dev);
  if (code != 0) return code;
  write_u64(out8, (unsigned long long)v);
  return 0;
}

int xo_oidn_buffer_storage(long long device, long long buffer, unsigned char* out4) {
  if (!g_lib) { xo_set_error("oidn: not loaded"); return -1; }
  OIDNDevice dev = dev_of(device);
  drain_device(dev);
  int v = (int)g_api.p_oidnGetBufferStorage(buf_of(buffer));
  int code = fetch_error(dev);
  if (code != 0) return code;
  write_i32(out4, v);
  return 0;
}

int xo_oidn_buffer_data_addr(long long device, long long buffer, unsigned char* out8) {
  if (!g_lib) { xo_set_error("oidn: not loaded"); return -1; }
  OIDNDevice dev = dev_of(device);
  drain_device(dev);
  void* p = g_api.p_oidnGetBufferData(buf_of(buffer));
  int code = fetch_error(dev);
  if (code != 0) return code;
  write_u64(out8, (unsigned long long)(uintptr_t)p);
  return 0;
}

int xo_oidn_buffer_read(long long device, long long buffer, long long offset, long long size, unsigned char* dst) {
  if (!g_lib) { xo_set_error("oidn: not loaded"); return -1; }
  OIDNDevice dev = dev_of(device);
  drain_device(dev);
  g_api.p_oidnReadBuffer(buf_of(buffer), (size_t)offset, (size_t)size, (void*)dst);
  return fetch_error(dev);
}

int xo_oidn_buffer_read_async(long long device, long long buffer, long long offset, long long size, unsigned char* dst) {
  if (!g_lib) { xo_set_error("oidn: not loaded"); return -1; }
  OIDNDevice dev = dev_of(device);
  drain_device(dev);
  g_api.p_oidnReadBufferAsync(buf_of(buffer), (size_t)offset, (size_t)size, (void*)dst);
  return fetch_error(dev);
}

int xo_oidn_buffer_write(long long device, long long buffer, long long offset, long long size, const unsigned char* src) {
  if (!g_lib) { xo_set_error("oidn: not loaded"); return -1; }
  OIDNDevice dev = dev_of(device);
  drain_device(dev);
  g_api.p_oidnWriteBuffer(buf_of(buffer), (size_t)offset, (size_t)size, (const void*)src);
  return fetch_error(dev);
}

int xo_oidn_buffer_write_async(long long device, long long buffer, long long offset, long long size, const unsigned char* src) {
  if (!g_lib) { xo_set_error("oidn: not loaded"); return -1; }
  OIDNDevice dev = dev_of(device);
  drain_device(dev);
  g_api.p_oidnWriteBufferAsync(buf_of(buffer), (size_t)offset, (size_t)size, (const void*)src);
  return fetch_error(dev);
}

/* ------------------------------------------------------------------ */
/* Semaphores (bound; the CPU device reports no external semaphore     */
/* types, so creation paths fail typed on the declared CPU scope)      */
/* ------------------------------------------------------------------ */

long long xo_oidn_semaphore_new_shared_fd(long long device, int flags, int fd) {
  if (!g_lib) { xo_set_error("oidn: not loaded"); return 0; }
  OIDNDevice dev = dev_of(device);
  drain_device(dev);
  OIDNSemaphore sem = g_api.p_oidnNewSharedSemaphoreFromFD(dev, (OIDNExternalSemaphoreTypeFlags)flags, fd);
  if (sem == 0) { return fail_handle(fetch_error(dev)); }
  return handle_of(sem);
}

long long xo_oidn_semaphore_new_shared_win32(long long device, int flags, long long handle, long long name) {
  if (!g_lib) { xo_set_error("oidn: not loaded"); return 0; }
  OIDNDevice dev = dev_of(device);
  drain_device(dev);
  OIDNSemaphore sem = g_api.p_oidnNewSharedSemaphoreFromWin32Handle(
      dev, (OIDNExternalSemaphoreTypeFlags)flags,
      reinterpret_cast<void*>(handle),
      reinterpret_cast<const void*>(name));
  if (sem == 0) { return fail_handle(fetch_error(dev)); }
  return handle_of(sem);
}

int xo_oidn_semaphore_signal(long long device, const unsigned char* handles8, const unsigned char* values8, int count) {
  if (!g_lib) { xo_set_error("oidn: not loaded"); return -1; }
  OIDNDevice dev = dev_of(device);
  drain_device(dev);
  if (count < 0) { xo_set_error("oidn: negative semaphore count"); return -1; }
  OIDNSemaphore sems[8];
  uint64_t vals[8];
  const OIDNSemaphore* semsPtr = 0;
  const uint64_t* valsPtr = 0;
  if (count > 8) { xo_set_error("oidn: semaphore batch exceeds the 8-entry bridge limit"); return -1; }
  if (count > 0) {
    if (handles8 == 0) { xo_set_error("oidn: null semaphore handle array"); return -1; }
    for (int i = 0; i < count; ++i) sems[i] = sem_of((long long)read_u64(handles8 + 8 * i));
    if (values8 != 0) for (int i = 0; i < count; ++i) vals[i] = (uint64_t)read_u64(values8 + 8 * i);
    semsPtr = sems;
    valsPtr = (values8 != 0) ? vals : 0;
  }
  g_api.p_oidnSignalSemaphoresAsync(dev, semsPtr, valsPtr, count);
  return fetch_error(dev);
}

int xo_oidn_semaphore_wait(long long device, const unsigned char* handles8, const unsigned char* values8, const unsigned char* timeouts4, int count) {
  if (!g_lib) { xo_set_error("oidn: not loaded"); return -1; }
  OIDNDevice dev = dev_of(device);
  drain_device(dev);
  if (count < 0) { xo_set_error("oidn: negative semaphore count"); return -1; }
  OIDNSemaphore sems[8];
  uint64_t vals[8];
  uint32_t tos[8];
  const OIDNSemaphore* semsPtr = 0;
  const uint64_t* valsPtr = 0;
  const uint32_t* tosPtr = 0;
  if (count > 8) { xo_set_error("oidn: semaphore batch exceeds the 8-entry bridge limit"); return -1; }
  if (count > 0) {
    if (handles8 == 0) { xo_set_error("oidn: null semaphore handle array"); return -1; }
    for (int i = 0; i < count; ++i) sems[i] = sem_of((long long)read_u64(handles8 + 8 * i));
    if (values8 != 0) for (int i = 0; i < count; ++i) vals[i] = (uint64_t)read_u64(values8 + 8 * i);
    if (timeouts4 != 0) for (int i = 0; i < count; ++i)
      tos[i] = (uint32_t)(timeouts4[4 * i] | (timeouts4[4 * i + 1] << 8) | (timeouts4[4 * i + 2] << 16) | (timeouts4[4 * i + 3] << 24));
    semsPtr = sems;
    valsPtr = (values8 != 0) ? vals : 0;
    tosPtr = (timeouts4 != 0) ? tos : 0;
  }
  g_api.p_oidnWaitSemaphoresAsync(dev, semsPtr, valsPtr, tosPtr, count);
  return fetch_error(dev);
}

int xo_oidn_semaphore_retain(long long semaphore) {
  if (!g_lib) { xo_set_error("oidn: not loaded"); return -1; }
  if (semaphore == 0) { xo_set_error("oidn: null semaphore handle"); return -1; }
  g_api.p_oidnRetainSemaphore(sem_of(semaphore));
  return 0;
}

int xo_oidn_semaphore_release(long long semaphore) {
  if (!g_lib) { xo_set_error("oidn: not loaded"); return -1; }
  if (semaphore == 0) { xo_set_error("oidn: null semaphore handle"); return -1; }
  g_api.p_oidnReleaseSemaphore(sem_of(semaphore));
  return 0;
}

/* ------------------------------------------------------------------ */
/* Filters                                                             */
/* ------------------------------------------------------------------ */

long long xo_oidn_filter_new(long long device, const char* type) {
  if (!g_lib) { xo_set_error("oidn: not loaded"); return 0; }
  OIDNDevice dev = dev_of(device);
  drain_device(dev);
  OIDNFilter f = g_api.p_oidnNewFilter(dev, type);
  if (f == 0) { return fail_handle(fetch_error(dev)); }
  return handle_of(f);
}

int xo_oidn_filter_retain(long long filter) {
  if (!g_lib) { xo_set_error("oidn: not loaded"); return -1; }
  if (filter == 0) { xo_set_error("oidn: null filter handle"); return -1; }
  g_api.p_oidnRetainFilter(filt_of(filter));
  return 0;
}

int xo_oidn_filter_release(long long filter) {
  if (!g_lib) { xo_set_error("oidn: not loaded"); return -1; }
  if (filter == 0) { xo_set_error("oidn: null filter handle"); return -1; }
  g_api.p_oidnReleaseFilter(filt_of(filter));
  return 0;
}

int xo_oidn_filter_set_image(long long device, long long filter, const char* name,
                             long long buffer, int format, long long width, long long height,
                             long long byteOffset, long long pixelByteStride, long long rowByteStride) {
  if (!g_lib) { xo_set_error("oidn: not loaded"); return -1; }
  OIDNDevice dev = dev_of(device);
  drain_device(dev);
  g_api.p_oidnSetFilterImage(filt_of(filter), name, buf_of(buffer), (OIDNFormat)format,
                             (size_t)width, (size_t)height, (size_t)byteOffset,
                             (size_t)pixelByteStride, (size_t)rowByteStride);
  return fetch_error(dev);
}

int xo_oidn_filter_set_shared_image(long long device, long long filter, const char* name,
                                    unsigned char* ptr, int format, long long width, long long height,
                                    long long byteOffset, long long pixelByteStride, long long rowByteStride) {
  if (!g_lib) { xo_set_error("oidn: not loaded"); return -1; }
  OIDNDevice dev = dev_of(device);
  drain_device(dev);
  g_api.p_oidnSetSharedFilterImage(filt_of(filter), name, (void*)ptr, (OIDNFormat)format,
                                   (size_t)width, (size_t)height, (size_t)byteOffset,
                                   (size_t)pixelByteStride, (size_t)rowByteStride);
  return fetch_error(dev);
}

int xo_oidn_filter_unset_image(long long device, long long filter, const char* name) {
  if (!g_lib) { xo_set_error("oidn: not loaded"); return -1; }
  OIDNDevice dev = dev_of(device);
  drain_device(dev);
  g_api.p_oidnUnsetFilterImage(filt_of(filter), name);
  return fetch_error(dev);
}

int xo_oidn_filter_set_data(long long device, long long filter, const char* name,
                            unsigned char* ptr, long long byteSize) {
  if (!g_lib) { xo_set_error("oidn: not loaded"); return -1; }
  OIDNDevice dev = dev_of(device);
  drain_device(dev);
  g_api.p_oidnSetSharedFilterData(filt_of(filter), name, (void*)ptr, (size_t)byteSize);
  return fetch_error(dev);
}

int xo_oidn_filter_update_data(long long device, long long filter, const char* name) {
  if (!g_lib) { xo_set_error("oidn: not loaded"); return -1; }
  OIDNDevice dev = dev_of(device);
  drain_device(dev);
  g_api.p_oidnUpdateFilterData(filt_of(filter), name);
  return fetch_error(dev);
}

int xo_oidn_filter_unset_data(long long device, long long filter, const char* name) {
  if (!g_lib) { xo_set_error("oidn: not loaded"); return -1; }
  OIDNDevice dev = dev_of(device);
  drain_device(dev);
  g_api.p_oidnUnsetFilterData(filt_of(filter), name);
  return fetch_error(dev);
}

int xo_oidn_filter_set_bool(long long device, long long filter, const char* name, int value) {
  if (!g_lib) { xo_set_error("oidn: not loaded"); return -1; }
  OIDNDevice dev = dev_of(device);
  drain_device(dev);
  g_api.p_oidnSetFilterBool(filt_of(filter), name, value != 0);
  return fetch_error(dev);
}

int xo_oidn_filter_get_bool(long long device, long long filter, const char* name, unsigned char* out1) {
  if (!g_lib) { xo_set_error("oidn: not loaded"); return -1; }
  OIDNDevice dev = dev_of(device);
  drain_device(dev);
  bool v = g_api.p_oidnGetFilterBool(filt_of(filter), name);
  int code = fetch_error(dev);
  if (code != 0) return code;
  write_u8(out1, v ? 1 : 0);
  return 0;
}

int xo_oidn_filter_set_int(long long device, long long filter, const char* name, int value) {
  if (!g_lib) { xo_set_error("oidn: not loaded"); return -1; }
  OIDNDevice dev = dev_of(device);
  drain_device(dev);
  g_api.p_oidnSetFilterInt(filt_of(filter), name, value);
  return fetch_error(dev);
}

int xo_oidn_filter_get_int(long long device, long long filter, const char* name, unsigned char* out4) {
  if (!g_lib) { xo_set_error("oidn: not loaded"); return -1; }
  OIDNDevice dev = dev_of(device);
  drain_device(dev);
  int v = g_api.p_oidnGetFilterInt(filt_of(filter), name);
  int code = fetch_error(dev);
  if (code != 0) return code;
  write_i32(out4, v);
  return 0;
}

int xo_oidn_filter_set_float(long long device, long long filter, const char* name, float value) {
  if (!g_lib) { xo_set_error("oidn: not loaded"); return -1; }
  OIDNDevice dev = dev_of(device);
  drain_device(dev);
  g_api.p_oidnSetFilterFloat(filt_of(filter), name, value);
  return fetch_error(dev);
}

int xo_oidn_filter_get_float(long long device, long long filter, const char* name, unsigned char* out4) {
  if (!g_lib) { xo_set_error("oidn: not loaded"); return -1; }
  OIDNDevice dev = dev_of(device);
  drain_device(dev);
  float v = g_api.p_oidnGetFilterFloat(filt_of(filter), name);
  int code = fetch_error(dev);
  if (code != 0) return code;
  write_f32(out4, v);
  return 0;
}

/* Bridge-owned progress monitor: covers
 * oidnSetFilterProgressMonitorFunction without crossing an XIOM fn value. */
int xo_oidn_filter_set_progress_monitor(long long device, long long filter, int enable) {
  if (!g_lib) { xo_set_error("oidn: not loaded"); return -1; }
  OIDNDevice dev = dev_of(device);
  drain_device(dev);
  g_api.p_oidnSetFilterProgressMonitorFunction(filt_of(filter), enable ? progress_cb : (OIDNProgressMonitorFunction)0, 0);
  return fetch_error(dev);
}

int xo_oidn_filter_progress_hits(unsigned char* out4) {
  write_i32(out4, g_progressHits);
  return 0;
}

int xo_oidn_filter_progress_reset(void) {
  g_progressHits = 0;
  return 0;
}

int xo_oidn_filter_commit(long long device, long long filter) {
  if (!g_lib) { xo_set_error("oidn: not loaded"); return -1; }
  OIDNDevice dev = dev_of(device);
  drain_device(dev);
  g_api.p_oidnCommitFilter(filt_of(filter));
  return fetch_error(dev);
}

int xo_oidn_filter_execute(long long device, long long filter) {
  if (!g_lib) { xo_set_error("oidn: not loaded"); return -1; }
  OIDNDevice dev = dev_of(device);
  drain_device(dev);
  g_api.p_oidnExecuteFilter(filt_of(filter));
  return fetch_error(dev);
}

int xo_oidn_filter_execute_async(long long device, long long filter) {
  if (!g_lib) { xo_set_error("oidn: not loaded"); return -1; }
  OIDNDevice dev = dev_of(device);
  drain_device(dev);
  g_api.p_oidnExecuteFilterAsync(filt_of(filter));
  return fetch_error(dev);
}

/* ------------------------------------------------------------------ */
/* Test-support analysis (owned buffers only; C reads XIOM-owned bytes */
/* and writes XIOM-owned result slots)                                 */
/* ------------------------------------------------------------------ */

/* Summarize a float32 output buffer against its input:
 * out_slots = [finite, changed, min_milli, max_milli, mean_milli] (5 x i32).
 * `changed` counts values differing from the input by more than epsMilli
 * (1e-6 default when epsMilli <= 0). Finite counts IEEE-finite values. */
int xo_oidn_f32_analyze(const unsigned char* input, const unsigned char* output, int floatCount, int epsMilli, unsigned char* out_slots) {
  if (output == 0 || out_slots == 0 || floatCount < 0) { xo_set_error("oidn: bad analyze arguments"); return -1; }
  int finite = 0;
  int changed = 0;
  float minV = 0.0f;
  float maxV = 0.0f;
  double sum = 0.0;
  float eps = (epsMilli <= 0) ? 0.000001f : (float)epsMilli / 1000000.0f;
  for (int i = 0; i < floatCount; ++i) {
    float v;
    memcpy(&v, output + 4 * (size_t)i, 4);
    if (v == v && v <= 3.4028234663852886e38f && v >= -3.4028234663852886e38f) finite++;
    if (i == 0) { minV = v; maxV = v; }
    else { if (v < minV) minV = v; if (v > maxV) maxV = v; }
    sum += (double)v;
    if (input != 0) {
      float u;
      memcpy(&u, input + 4 * (size_t)i, 4);
      float d = v - u;
      if (d < 0) d = -d;
      if (d > eps) changed++;
    }
  }
  write_i32(out_slots + 0, finite);
  write_i32(out_slots + 4, changed);
  write_i32(out_slots + 8, (int)(minV * 1000.0f + (minV >= 0 ? 0.5f : -0.5f)));
  write_i32(out_slots + 12, (int)(maxV * 1000.0f + (maxV >= 0 ? 0.5f : -0.5f)));
  write_i32(out_slots + 16, (floatCount > 0) ? (int)((sum / (double)floatCount) * 1000.0 + 0.5) : 0);
  return 0;
}

/* Count bytes that differ between two XIOM-owned buffers. */
int xo_oidn_byte_diff(const unsigned char* a, const unsigned char* b, int byteCount, unsigned char* out4) {
  if (a == 0 || b == 0 || out4 == 0 || byteCount < 0) { xo_set_error("oidn: bad diff arguments"); return -1; }
  int diff = 0;
  for (int i = 0; i < byteCount; ++i) if (a[i] != b[i]) diff++;
  write_i32(out4, diff);
  return 0;
}

/* Bit-exact equality of two XIOM-owned buffers (1/0). */
int xo_oidn_byte_equal(const unsigned char* a, const unsigned char* b, int byteCount, unsigned char* out1) {
  if (a == 0 || b == 0 || out1 == 0 || byteCount < 0) { xo_set_error("oidn: bad equal arguments"); return -1; }
  int eq = memcmp(a, b, (size_t)byteCount) == 0 ? 1 : 0;
  write_u8(out1, (unsigned char)eq);
  return 0;
}

} // extern "C"
