// xiom.nvapi -- loader-only C bridge over NVIDIA NVAPI (nvapi64.dll).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// NOTHING IS VENDORED.  nvapi64.dll is a system component shipped with the
// NVIDIA display driver; this bridge resolves it at run time with
// LoadLibraryA.  NVAPI does not export its functions directly: only
// `nvapi_QueryInterface` is exported, and every entry point is fetched by its
// numeric function id.  The ids and struct layouts below are **interface
// facts** transcribed from NVIDIA's MIT-licensed public NVAPI SDK headers
// (declaration oracle: NVIDIA/nvapi nvapi.h, nvapi_interface.h,
// nvapi_lite_common.h at the pin in PROVENANCE.md).  The bridge is original
// XIOM-side code and asserts every struct offset/size it relies on.
//
// Discipline notes (v0.64.6 findings): all foreign memory is read/written in
// C only (B-20); foreign handles never cross the FFI (they stay in C);
// outcomes are flat integers (B-26); bridge locals carry the `n_` prefix
// (B-10); no allocation inside confined XIOM blocks (B-05).
//
// Return convention: 0 is success; negative values are typed loader-error
// classes consumed by nvapi.xi:
//   -100 nvapi64.dll missing                      -> SKIP
//   -101 driver / NVAPI unavailable (initialize)  -> SKIP
//   -102 required entry point missing (ABI)       -> FAIL
//   -103 no physical GPU                          -> SKIP
//   -104 initialize failed                        -> FAIL
//   -105 a declared query failed                  -> FAIL
//   -106 internal failure                         -> FAIL
//
// Optional metrics (thermal sensor, dynamic P-state utilization) return the
// documented sentinel -1 when the driver reports NVAPI_NOT_SUPPORTED.

#include <windows.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

// ---------------------------------------------------------------------------
// Interface facts: NVAPI status + function ids + struct versions
// ---------------------------------------------------------------------------

#define NVAPI_OK 0
#define NVAPI_LIBRARY_NOT_FOUND -2
#define NVAPI_NO_IMPLEMENTATION -3
#define NVAPI_NVIDIA_DEVICE_NOT_FOUND -6
#define NVAPI_NOT_SUPPORTED -104
#define NVAPI_DRIVER_NOTRUNNING -156

#define NVAPI_SHORT_STRING_MAX 64
#define NVAPI_MAX_PHYSICAL_GPUS 64
#define NVAPI_MAX_THERMAL_SENSORS_PER_GPU 3
#define NVAPI_MAX_GPU_UTILIZATIONS 8
#define NVAPI_THERMAL_TARGET_ALL 15
#define NVAPI_THERMAL_TARGET_GPU 1
#define NVAPI_GPU_UTILIZATION_DOMAIN_GPU 0

#define NVAPI_ID_INITIALIZE 0x0150E828u
#define NVAPI_ID_UNLOAD 0xD22BDD7Eu
#define NVAPI_ID_GET_ERROR_MESSAGE 0x6C2D048Cu
#define NVAPI_ID_GET_INTERFACE_VERSION 0x01053FA5u
#define NVAPI_ID_GET_DRIVER_AND_BRANCH_VERSION 0x2926AAADu
#define NVAPI_ID_ENUM_PHYSICAL_GPUS 0xE5AC921Fu
#define NVAPI_ID_GPU_GET_FULL_NAME 0xCEEE8E9Fu
#define NVAPI_ID_GPU_GET_PCI_IDENTIFIERS 0x2DDFB66Eu
#define NVAPI_ID_GPU_GET_BUS_ID 0x1BE0B8E5u
#define NVAPI_ID_GPU_GET_THERMAL_SETTINGS 0xE3640A56u
#define NVAPI_ID_GPU_GET_DYNAMIC_PSTATES 0x60DED2EDu

#define NVAPI_MAKE_VERSION(type_name, ver) ((uint32_t)(sizeof(type_name) | ((ver) << 16)))

typedef void *NvPhysicalGpuHandle;
typedef char NvAPI_ShortString[NVAPI_SHORT_STRING_MAX];

typedef struct {
  int32_t controller;
  int32_t defaultMinTemp;
  int32_t defaultMaxTemp;
  int32_t currentTemp;
  int32_t target;
} NvThermalSensor;

typedef struct {
  uint32_t version;
  uint32_t count;
  NvThermalSensor sensor[NVAPI_MAX_THERMAL_SENSORS_PER_GPU];
} NvGpuThermalSettingsV2;

typedef struct {
  uint32_t bIsPresent : 1;
  uint32_t percentage;
} NvGpuUtilizationDomain;

typedef struct {
  uint32_t version;
  uint32_t flags;
  NvGpuUtilizationDomain utilization[NVAPI_MAX_GPU_UTILIZATIONS];
} NvGpuDynamicPstatesInfoEx;

_Static_assert(sizeof(NvThermalSensor) == 20, "NvThermalSensor layout drift");
_Static_assert(sizeof(NvGpuThermalSettingsV2) == 68, "NV_GPU_THERMAL_SETTINGS_V2 drift");
_Static_assert(offsetof(NvGpuThermalSettingsV2, count) == 4,
               "NV_GPU_THERMAL_SETTINGS_V2.count drift");
_Static_assert(offsetof(NvGpuThermalSettingsV2, sensor) == 8,
               "NV_GPU_THERMAL_SETTINGS_V2.sensor drift");
_Static_assert(offsetof(NvGpuThermalSettingsV2, sensor[1]) == 28,
               "NV_GPU_THERMAL_SETTINGS_V2.sensor stride drift");
_Static_assert(sizeof(NvGpuUtilizationDomain) == 8, "NV_GPU utilization domain layout drift");
_Static_assert(sizeof(NvGpuDynamicPstatesInfoEx) == 72,
               "NV_GPU_DYNAMIC_PSTATES_INFO_EX drift");
_Static_assert(offsetof(NvGpuDynamicPstatesInfoEx, utilization) == 8,
               "NV_GPU_DYNAMIC_PSTATES_INFO_EX.utilization drift");

#define NV_GPU_THERMAL_SETTINGS_VER \
  NVAPI_MAKE_VERSION(NvGpuThermalSettingsV2, 2)
#define NV_GPU_DYNAMIC_PSTATES_INFO_EX_VER \
  NVAPI_MAKE_VERSION(NvGpuDynamicPstatesInfoEx, 1)

typedef void *(__cdecl *PFN_nvapi_QueryInterface)(uint32_t function_id);
typedef int (*PFN_NvAPI_Initialize)(void);
typedef int (*PFN_NvAPI_Unload)(void);
typedef int (*PFN_NvAPI_GetErrorMessage)(int status, NvAPI_ShortString desc);
typedef int (*PFN_NvAPI_GetInterfaceVersionString)(NvAPI_ShortString desc);
typedef int (*PFN_NvAPI_SYS_GetDriverAndBranchVersion)(uint32_t *driver_version,
                                                       NvAPI_ShortString branch);
typedef int (*PFN_NvAPI_EnumPhysicalGPUs)(NvPhysicalGpuHandle handles[NVAPI_MAX_PHYSICAL_GPUS],
                                          uint32_t *count);
typedef int (*PFN_NvAPI_GPU_GetFullName)(NvPhysicalGpuHandle gpu, NvAPI_ShortString name);
typedef int (*PFN_NvAPI_GPU_GetPCIIdentifiers)(NvPhysicalGpuHandle gpu, uint32_t *device_id,
                                               uint32_t *subsystem_id, uint32_t *revision_id,
                                               uint32_t *ext_device_id);
typedef int (*PFN_NvAPI_GPU_GetBusId)(NvPhysicalGpuHandle gpu, uint32_t *bus_id);
typedef int (*PFN_NvAPI_GPU_GetThermalSettings)(NvPhysicalGpuHandle gpu,
                                                uint32_t sensor_index,
                                                NvGpuThermalSettingsV2 *settings);
typedef int (*PFN_NvAPI_GPU_GetDynamicPstatesInfoEx)(NvPhysicalGpuHandle gpu,
                                                     NvGpuDynamicPstatesInfoEx *info);

typedef struct {
  HMODULE mod;
  PFN_nvapi_QueryInterface query;
  PFN_NvAPI_Initialize initialize;
  PFN_NvAPI_Unload unload;
  PFN_NvAPI_GetErrorMessage get_error_message;
  PFN_NvAPI_GetInterfaceVersionString get_interface_version;
  PFN_NvAPI_SYS_GetDriverAndBranchVersion get_driver_and_branch;
  PFN_NvAPI_EnumPhysicalGPUs enum_physical_gpus;
  PFN_NvAPI_GPU_GetFullName get_full_name;
  PFN_NvAPI_GPU_GetPCIIdentifiers get_pci_identifiers;
  PFN_NvAPI_GPU_GetBusId get_bus_id;
  PFN_NvAPI_GPU_GetThermalSettings get_thermal_settings;
  PFN_NvAPI_GPU_GetDynamicPstatesInfoEx get_dynamic_pstates;
} NvapiApi;

static NvapiApi g_api;

static char g_interface_version[NVAPI_SHORT_STRING_MAX];
static char g_driver_branch[NVAPI_SHORT_STRING_MAX];
static char g_gpu_name[NVAPI_SHORT_STRING_MAX];
static int g_driver_version_raw;
static int g_driver_version_major;
static int g_driver_version_minor;
static int g_device_id;
static int g_vendor_id;
static int g_pci_device_id;
static int g_subsystem_id;
static int g_revision_id;
static int g_ext_device_id;
static int g_gpu_count;
static int g_bus_id;
static int g_temperature_c;
static int g_utilization_gpu_pct;

static int g_err_stage;
static int g_err_code;
static char g_err_text[512];

static const char *nvapi_stage_name(int stage) {
  switch (stage) {
    case 0: return "load";
    case 1: return "query-interface";
    case 2: return "initialize";
    case 3: return "interface-version";
    case 4: return "driver-version";
    case 5: return "enumerate";
    case 6: return "name";
    case 7: return "pci-identifiers";
    case 8: return "bus-id";
    case 9: return "thermal";
    case 10: return "utilization";
    case 11: return "unload";
    default: return "unknown";
  }
}

static int nv_fail(int high_level, int stage, int code) {
  const char *n_text = 0;
  char n_buf[NVAPI_SHORT_STRING_MAX];
  g_err_stage = stage;
  g_err_code = code;
  n_buf[0] = 0;
  if (g_api.get_error_message != 0) {
    g_api.get_error_message(code, n_buf);
    n_buf[NVAPI_SHORT_STRING_MAX - 1] = 0;
    if (n_buf[0] != 0) n_text = n_buf;
  }
  snprintf(g_err_text, sizeof(g_err_text), "%s: %s (code=%d)", nvapi_stage_name(stage),
           n_text != 0 ? n_text : "failed", code);
  return -high_level;
}

static int nv_fail_text(int high_level, int stage, const char *text) {
  g_err_stage = stage;
  g_err_code = 0;
  snprintf(g_err_text, sizeof(g_err_text), "%s: %s", nvapi_stage_name(stage),
           text != 0 ? text : "failed");
  return -high_level;
}

static int nv_is_unavailable_status(int status) {
  if (status == NVAPI_LIBRARY_NOT_FOUND) return 1;
  if (status == NVAPI_NO_IMPLEMENTATION) return 1;
  if (status == NVAPI_NVIDIA_DEVICE_NOT_FOUND) return 1;
  if (status == NVAPI_DRIVER_NOTRUNNING) return 1;
  return 0;
}

static void nv_reset(void) {
  g_interface_version[0] = 0;
  g_driver_branch[0] = 0;
  g_gpu_name[0] = 0;
  g_driver_version_raw = -1;
  g_driver_version_major = -1;
  g_driver_version_minor = -1;
  g_device_id = -1;
  g_vendor_id = -1;
  g_pci_device_id = -1;
  g_subsystem_id = -1;
  g_revision_id = -1;
  g_ext_device_id = -1;
  g_gpu_count = 0;
  g_bus_id = -1;
  g_temperature_c = -1;
  g_utilization_gpu_pct = -1;
  g_err_stage = 0;
  g_err_code = 0;
  g_err_text[0] = 0;
}

static void *nv_query(uint32_t function_id) {
  if (g_api.query == 0) return 0;
  return g_api.query(function_id);
}

static int nv_resolve(void) {
  g_api.initialize = (PFN_NvAPI_Initialize)nv_query(NVAPI_ID_INITIALIZE);
  g_api.unload = (PFN_NvAPI_Unload)nv_query(NVAPI_ID_UNLOAD);
  g_api.get_error_message =
      (PFN_NvAPI_GetErrorMessage)nv_query(NVAPI_ID_GET_ERROR_MESSAGE);
  g_api.get_interface_version =
      (PFN_NvAPI_GetInterfaceVersionString)nv_query(NVAPI_ID_GET_INTERFACE_VERSION);
  g_api.get_driver_and_branch =
      (PFN_NvAPI_SYS_GetDriverAndBranchVersion)nv_query(
          NVAPI_ID_GET_DRIVER_AND_BRANCH_VERSION);
  g_api.enum_physical_gpus =
      (PFN_NvAPI_EnumPhysicalGPUs)nv_query(NVAPI_ID_ENUM_PHYSICAL_GPUS);
  g_api.get_full_name =
      (PFN_NvAPI_GPU_GetFullName)nv_query(NVAPI_ID_GPU_GET_FULL_NAME);
  g_api.get_pci_identifiers =
      (PFN_NvAPI_GPU_GetPCIIdentifiers)nv_query(NVAPI_ID_GPU_GET_PCI_IDENTIFIERS);
  g_api.get_bus_id = (PFN_NvAPI_GPU_GetBusId)nv_query(NVAPI_ID_GPU_GET_BUS_ID);
  g_api.get_thermal_settings = (PFN_NvAPI_GPU_GetThermalSettings)nv_query(
      NVAPI_ID_GPU_GET_THERMAL_SETTINGS);
  g_api.get_dynamic_pstates = (PFN_NvAPI_GPU_GetDynamicPstatesInfoEx)nv_query(
      NVAPI_ID_GPU_GET_DYNAMIC_PSTATES);

  if (g_api.initialize == 0 || g_api.unload == 0 || g_api.get_error_message == 0 ||
      g_api.get_interface_version == 0 || g_api.get_driver_and_branch == 0 ||
      g_api.enum_physical_gpus == 0 || g_api.get_full_name == 0 ||
      g_api.get_pci_identifiers == 0 || g_api.get_bus_id == 0 ||
      g_api.get_thermal_settings == 0 || g_api.get_dynamic_pstates == 0) {
    return -1;
  }
  return 0;
}

int nvb_nvapi_probe_run(const char *dll_name) {
  if (dll_name == 0) return nv_fail_text(106, 0, "null loader name");
  nv_reset();
  memset(&g_api, 0, sizeof(g_api));

  g_api.mod = LoadLibraryA(dll_name);
  if (g_api.mod == 0) return nv_fail_text(100, 0, "nvapi64.dll not found");

  g_api.query = (PFN_nvapi_QueryInterface)(void *)GetProcAddress(g_api.mod,
                                                               "nvapi_QueryInterface");
  if (g_api.query == 0) {
    FreeLibrary(g_api.mod);
    memset(&g_api, 0, sizeof(g_api));
    return nv_fail_text(102, 1, "nvapi_QueryInterface export missing");
  }

  // Resolve GetErrorMessage first so every later failure can name its status.
  g_api.get_error_message =
      (PFN_NvAPI_GetErrorMessage)nv_query(NVAPI_ID_GET_ERROR_MESSAGE);

  if (nv_resolve() != 0) {
    FreeLibrary(g_api.mod);
    memset(&g_api, 0, sizeof(g_api));
    return nv_fail_text(102, 1, "required NVAPI interface id missing");
  }

  int n_status = g_api.initialize();
  if (n_status != NVAPI_OK) {
    int n_err;
    if (nv_is_unavailable_status(n_status)) {
      n_err = nv_fail_text(101, 2, "NVIDIA driver / NVAPI unavailable");
    } else {
      n_err = nv_fail(104, 2, n_status);
    }
    FreeLibrary(g_api.mod);
    memset(&g_api, 0, sizeof(g_api));
    return n_err;
  }

  n_status = g_api.get_interface_version(g_interface_version);
  if (n_status != NVAPI_OK) {
    int n_err = nv_fail(105, 3, n_status);
    g_api.unload();
    FreeLibrary(g_api.mod);
    memset(&g_api, 0, sizeof(g_api));
    return n_err;
  }
  g_interface_version[NVAPI_SHORT_STRING_MAX - 1] = 0;

  uint32_t n_driver_version = 0;
  n_status = g_api.get_driver_and_branch(&n_driver_version, g_driver_branch);
  if (n_status != NVAPI_OK) {
    int n_err = nv_fail(105, 4, n_status);
    g_api.unload();
    FreeLibrary(g_api.mod);
    memset(&g_api, 0, sizeof(g_api));
    return n_err;
  }
  // NVAPI reports the display driver version as major*100 + minor (61692 -> 616.92).
  g_driver_version_raw = (int)n_driver_version;
  g_driver_version_major = (int)(n_driver_version / 100u);
  g_driver_version_minor = (int)(n_driver_version % 100u);

  NvPhysicalGpuHandle n_handles[NVAPI_MAX_PHYSICAL_GPUS];
  uint32_t n_count = 0;
  memset(n_handles, 0, sizeof(n_handles));
  n_status = g_api.enum_physical_gpus(n_handles, &n_count);
  if (n_status != NVAPI_OK) {
    int n_err = nv_fail(105, 5, n_status);
    g_api.unload();
    FreeLibrary(g_api.mod);
    memset(&g_api, 0, sizeof(g_api));
    return n_err;
  }
  if (n_count == 0) {
    g_api.unload();
    FreeLibrary(g_api.mod);
    memset(&g_api, 0, sizeof(g_api));
    return nv_fail_text(103, 5, "no NVIDIA physical GPU");
  }
  g_gpu_count = (int)n_count;

  NvPhysicalGpuHandle n_gpu = n_handles[0];
  n_status = g_api.get_full_name(n_gpu, g_gpu_name);
  if (n_status != NVAPI_OK) {
    int n_err = nv_fail(105, 6, n_status);
    g_api.unload();
    FreeLibrary(g_api.mod);
    memset(&g_api, 0, sizeof(g_api));
    return n_err;
  }
  g_gpu_name[NVAPI_SHORT_STRING_MAX - 1] = 0;

  uint32_t n_device_id = 0;
  uint32_t n_subsystem_id = 0;
  uint32_t n_revision_id = 0;
  uint32_t n_ext_device_id = 0;
  n_status = g_api.get_pci_identifiers(n_gpu, &n_device_id, &n_subsystem_id, &n_revision_id,
                                       &n_ext_device_id);
  if (n_status != NVAPI_OK) {
    int n_err = nv_fail(105, 7, n_status);
    g_api.unload();
    FreeLibrary(g_api.mod);
    memset(&g_api, 0, sizeof(g_api));
    return n_err;
  }
  g_device_id = (int)n_device_id;
  g_vendor_id = (int)(n_device_id & 0xFFFFu);
  g_pci_device_id = (int)((n_device_id >> 16) & 0xFFFFu);
  g_subsystem_id = (int)n_subsystem_id;
  g_revision_id = (int)n_revision_id;
  g_ext_device_id = (int)n_ext_device_id;

  uint32_t n_bus_id = 0;
  n_status = g_api.get_bus_id(n_gpu, &n_bus_id);
  if (n_status != NVAPI_OK) {
    int n_err = nv_fail(105, 8, n_status);
    g_api.unload();
    FreeLibrary(g_api.mod);
    memset(&g_api, 0, sizeof(g_api));
    return n_err;
  }
  g_bus_id = (int)n_bus_id;

  // Thermal: ask for all sensors and pick the GPU-die target.
  NvGpuThermalSettingsV2 n_thermal;
  memset(&n_thermal, 0, sizeof(n_thermal));
  n_thermal.version = NV_GPU_THERMAL_SETTINGS_VER;
  n_status = g_api.get_thermal_settings(n_gpu, NVAPI_THERMAL_TARGET_ALL, &n_thermal);
  if (n_status == NVAPI_OK) {
    uint32_t n_i;
    for (n_i = 0; n_i < n_thermal.count && n_i < NVAPI_MAX_THERMAL_SENSORS_PER_GPU; n_i++) {
      if (n_thermal.sensor[n_i].target == NVAPI_THERMAL_TARGET_GPU) {
        g_temperature_c = (int)n_thermal.sensor[n_i].currentTemp;
        break;
      }
    }
  } else if (n_status != NVAPI_NOT_SUPPORTED) {
    int n_err = nv_fail(105, 9, n_status);
    g_api.unload();
    FreeLibrary(g_api.mod);
    memset(&g_api, 0, sizeof(g_api));
    return n_err;
  }

  // Utilization: domain 0 is the graphics/GPU engine in the documented order.
  NvGpuDynamicPstatesInfoEx n_pstates;
  memset(&n_pstates, 0, sizeof(n_pstates));
  n_pstates.version = NV_GPU_DYNAMIC_PSTATES_INFO_EX_VER;
  n_status = g_api.get_dynamic_pstates(n_gpu, &n_pstates);
  if (n_status == NVAPI_OK) {
    if (n_pstates.utilization[NVAPI_GPU_UTILIZATION_DOMAIN_GPU].bIsPresent != 0) {
      g_utilization_gpu_pct =
          (int)n_pstates.utilization[NVAPI_GPU_UTILIZATION_DOMAIN_GPU].percentage;
    }
  } else if (n_status != NVAPI_NOT_SUPPORTED) {
    int n_err = nv_fail(105, 10, n_status);
    g_api.unload();
    FreeLibrary(g_api.mod);
    memset(&g_api, 0, sizeof(g_api));
    return n_err;
  }

  // Best-effort unload; the snapshot is already complete.
  g_api.unload();
  FreeLibrary(g_api.mod);
  memset(&g_api, 0, sizeof(g_api));
  return 0;
}

const char *nvb_nvapi_interface_version(void) { return g_interface_version; }
const char *nvb_nvapi_driver_branch(void) { return g_driver_branch; }
const char *nvb_nvapi_gpu_name(void) { return g_gpu_name; }
int nvb_nvapi_driver_version_raw(void) { return g_driver_version_raw; }
int nvb_nvapi_driver_version_major(void) { return g_driver_version_major; }
int nvb_nvapi_driver_version_minor(void) { return g_driver_version_minor; }
int nvb_nvapi_gpu_count(void) { return g_gpu_count; }
int nvb_nvapi_device_id(void) { return g_device_id; }
int nvb_nvapi_vendor_id(void) { return g_vendor_id; }
int nvb_nvapi_pci_device_id(void) { return g_pci_device_id; }
int nvb_nvapi_subsystem_id(void) { return g_subsystem_id; }
int nvb_nvapi_revision_id(void) { return g_revision_id; }
int nvb_nvapi_ext_device_id(void) { return g_ext_device_id; }
int nvb_nvapi_bus_id(void) { return g_bus_id; }
int nvb_nvapi_temperature_c(void) { return g_temperature_c; }
int nvb_nvapi_utilization_gpu_pct(void) { return g_utilization_gpu_pct; }

const char *nvb_nvapi_last_error_text(void) { return g_err_text; }
int nvb_nvapi_last_error_stage(void) { return g_err_stage; }
int nvb_nvapi_last_error_code(void) { return g_err_code; }
