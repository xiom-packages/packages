// xiom.nvml -- loader-only C bridge over NVIDIA NVML (nvml.dll).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// NOTHING IS VENDORED.  nvml.dll is a system component shipped with the
// NVIDIA display driver; this bridge resolves it at run time with
// LoadLibraryA/GetProcAddress.  No import library and no upstream code is
// linked into the package.
//
// The struct layouts, buffer sizes, enum values and function signatures below
// are **interface facts** transcribed from the pinned NVML public header
// (declaration oracle: NVIDIA/go-nvml gen/nvml/nvml.h, NVML 13.4.92; see
// PROVENANCE.md for the commit and hashes).  The bridge is original
// XIOM-side code: it asserts every struct offset/size it relies on at
// compile time, so a header move breaks the build loudly instead of
// corrupting a driver call.
//
// Discipline notes (v0.64.6 findings): all foreign memory is read/written in
// C only (B-20); no foreign pointers cross the FFI; every outcome is a flat
// integer (B-26); bridge locals carry the `n_` prefix (B-10); no allocation
// inside confined XIOM blocks (B-05).
//
// Return convention: 0 is success; negative values are typed loader-error
// classes consumed by nvml.xi:
//   -100 nvml.dll missing                        -> SKIP
//   -101 driver not loaded / NVML unavailable    -> SKIP
//   -102 required entry point missing (ABI)      -> FAIL
//   -103 no device                               -> SKIP
//   -104 init/shutdown failed                    -> FAIL
//   -105 a declared query failed                 -> FAIL
//   -106 device index out of range               -> FAIL
//   -107 internal reset failure                  -> FAIL
//
// Optional metrics (serial, power limits, fan, PCIe link, energy) return the
// documented sentinel -1 when the driver reports NVML_ERROR_NOT_SUPPORTED or
// the entry point predates the declared ABI pin.  Required metrics fail.

#include <windows.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

// ---------------------------------------------------------------------------
// Interface facts: NVML public ABI (nvml.h pin, NVML 13.4.92)
// ---------------------------------------------------------------------------

#define NVML_SUCCESS 0
#define NVML_ERROR_NOT_SUPPORTED 3
#define NVML_ERROR_NOT_FOUND 6
#define NVML_ERROR_DRIVER_NOT_LOADED 9
#define NVML_ERROR_LIBRARY_NOT_FOUND 12

#define NVML_TEMPERATURE_GPU 0
#define NVML_CLOCK_GRAPHICS 0
#define NVML_CLOCK_SM 1
#define NVML_CLOCK_MEM 2

#define NVML_DEVICE_PCI_BUS_ID_BUFFER_V2_SIZE 16
#define NVML_DEVICE_PCI_BUS_ID_BUFFER_SIZE 32
#define NVML_SYSTEM_DRIVER_VERSION_BUFFER_SIZE 80
#define NVML_SYSTEM_NVML_VERSION_BUFFER_SIZE 80
#define NVML_DEVICE_NAME_BUFFER_SIZE 64
#define NVML_DEVICE_UUID_BUFFER_SIZE 80
#define NVML_DEVICE_SERIAL_BUFFER_SIZE 30

typedef int nvmlReturn_t;
typedef void *nvmlDevice_t;
typedef int nvmlTemperatureSensors_t;
typedef int nvmlClockType_t;

typedef struct {
  char busIdLegacy[NVML_DEVICE_PCI_BUS_ID_BUFFER_V2_SIZE];
  unsigned int domain;
  unsigned int bus;
  unsigned int device;
  unsigned int pciDeviceId;
  unsigned int pciSubSystemId;
  char busId[NVML_DEVICE_PCI_BUS_ID_BUFFER_SIZE];
} nvmlPciInfo_t;

typedef struct {
  unsigned long long total;
  unsigned long long free;
  unsigned long long used;
} nvmlMemory_t;

typedef struct {
  unsigned int gpu;
  unsigned int memory;
} nvmlUtilization_t;

_Static_assert(sizeof(nvmlPciInfo_t) == 68, "nvmlPciInfo_t layout drift");
_Static_assert(offsetof(nvmlPciInfo_t, domain) == 16, "nvmlPciInfo_t.domain drift");
_Static_assert(offsetof(nvmlPciInfo_t, bus) == 20, "nvmlPciInfo_t.bus drift");
_Static_assert(offsetof(nvmlPciInfo_t, device) == 24, "nvmlPciInfo_t.device drift");
_Static_assert(offsetof(nvmlPciInfo_t, pciDeviceId) == 28, "nvmlPciInfo_t.pciDeviceId drift");
_Static_assert(offsetof(nvmlPciInfo_t, pciSubSystemId) == 32,
               "nvmlPciInfo_t.pciSubSystemId drift");
_Static_assert(offsetof(nvmlPciInfo_t, busId) == 36, "nvmlPciInfo_t.busId drift");
_Static_assert(sizeof(nvmlMemory_t) == 24, "nvmlMemory_t layout drift");
_Static_assert(sizeof(nvmlUtilization_t) == 8, "nvmlUtilization_t layout drift");

typedef nvmlReturn_t (*PFN_nvmlInit_v2)(void);
typedef nvmlReturn_t (*PFN_nvmlShutdown)(void);
typedef const char *(*PFN_nvmlErrorString)(nvmlReturn_t result);
typedef nvmlReturn_t (*PFN_nvmlSystemGetDriverVersion)(char *version, unsigned int length);
typedef nvmlReturn_t (*PFN_nvmlSystemGetNVMLVersion)(char *version, unsigned int length);
typedef nvmlReturn_t (*PFN_nvmlDeviceGetCount_v2)(unsigned int *deviceCount);
typedef nvmlReturn_t (*PFN_nvmlDeviceGetHandleByIndex_v2)(unsigned int index,
                                                          nvmlDevice_t *device);
typedef nvmlReturn_t (*PFN_nvmlDeviceGetName)(nvmlDevice_t device, char *name,
                                              unsigned int length);
typedef nvmlReturn_t (*PFN_nvmlDeviceGetUUID)(nvmlDevice_t device, char *uuid,
                                              unsigned int length);
typedef nvmlReturn_t (*PFN_nvmlDeviceGetSerial)(nvmlDevice_t device, char *serial,
                                                unsigned int length);
typedef nvmlReturn_t (*PFN_nvmlDeviceGetPciInfo_v3)(nvmlDevice_t device, nvmlPciInfo_t *pci);
typedef nvmlReturn_t (*PFN_nvmlDeviceGetMemoryInfo)(nvmlDevice_t device, nvmlMemory_t *memory);
typedef nvmlReturn_t (*PFN_nvmlDeviceGetUtilizationRates)(nvmlDevice_t device,
                                                          nvmlUtilization_t *utilization);
typedef nvmlReturn_t (*PFN_nvmlDeviceGetTemperature)(nvmlDevice_t device,
                                                     nvmlTemperatureSensors_t sensorType,
                                                     unsigned int *temp);
typedef nvmlReturn_t (*PFN_nvmlDeviceGetPowerUsage)(nvmlDevice_t device, unsigned int *power);
typedef nvmlReturn_t (*PFN_nvmlDeviceGetPowerManagementLimit)(nvmlDevice_t device,
                                                              unsigned int *limit);
typedef nvmlReturn_t (*PFN_nvmlDeviceGetEnforcedPowerLimit)(nvmlDevice_t device,
                                                            unsigned int *limit);
typedef nvmlReturn_t (*PFN_nvmlDeviceGetClockInfo)(nvmlDevice_t device, nvmlClockType_t type,
                                                   unsigned int *clock);
typedef nvmlReturn_t (*PFN_nvmlDeviceGetFanSpeed)(nvmlDevice_t device, unsigned int *speed);
typedef nvmlReturn_t (*PFN_nvmlDeviceGetCurrPcieLinkGeneration)(nvmlDevice_t device,
                                                                unsigned int *currLinkGen);
typedef nvmlReturn_t (*PFN_nvmlDeviceGetCurrPcieLinkWidth)(nvmlDevice_t device,
                                                           unsigned int *currLinkWidth);
typedef nvmlReturn_t (*PFN_nvmlDeviceGetTotalEnergyConsumption)(nvmlDevice_t device,
                                                                unsigned long long *energy);

typedef struct {
  HMODULE mod;
  PFN_nvmlInit_v2 init;
  PFN_nvmlShutdown shutdown;
  PFN_nvmlErrorString error_string;
  PFN_nvmlSystemGetDriverVersion system_driver_version;
  PFN_nvmlSystemGetNVMLVersion system_nvml_version;
  PFN_nvmlDeviceGetCount_v2 device_count;
  PFN_nvmlDeviceGetHandleByIndex_v2 device_handle;
  PFN_nvmlDeviceGetName device_name;
  PFN_nvmlDeviceGetUUID device_uuid;
  PFN_nvmlDeviceGetSerial device_serial;
  PFN_nvmlDeviceGetPciInfo_v3 device_pci;
  PFN_nvmlDeviceGetMemoryInfo device_memory;
  PFN_nvmlDeviceGetUtilizationRates device_utilization;
  PFN_nvmlDeviceGetTemperature device_temperature;
  PFN_nvmlDeviceGetPowerUsage device_power;
  PFN_nvmlDeviceGetPowerManagementLimit device_power_limit;
  PFN_nvmlDeviceGetEnforcedPowerLimit device_enforced_power_limit;
  PFN_nvmlDeviceGetClockInfo device_clock;
  PFN_nvmlDeviceGetFanSpeed device_fan;
  PFN_nvmlDeviceGetCurrPcieLinkGeneration device_pcie_gen;
  PFN_nvmlDeviceGetCurrPcieLinkWidth device_pcie_width;
  PFN_nvmlDeviceGetTotalEnergyConsumption device_energy;
} NvmlApi;

static NvmlApi g_api;

static char g_driver_version[NVML_SYSTEM_DRIVER_VERSION_BUFFER_SIZE];
static char g_nvml_version[NVML_SYSTEM_NVML_VERSION_BUFFER_SIZE];
static unsigned int g_device_count;

static char g_name[NVML_DEVICE_NAME_BUFFER_SIZE];
static char g_uuid[NVML_DEVICE_UUID_BUFFER_SIZE];
static char g_serial[NVML_DEVICE_SERIAL_BUFFER_SIZE];
static char g_bus_id[NVML_DEVICE_PCI_BUS_ID_BUFFER_SIZE];
static int g_index;
static int g_pci_domain;
static int g_pci_bus;
static int g_pci_device;
static int g_pci_ids_raw;
static int g_pci_vendor_id;
static int g_pci_device_id;
static int g_pci_subsystem_id;
static long long g_memory_total;
static long long g_memory_free;
static long long g_memory_used;
static int g_utilization_gpu;
static int g_utilization_memory;
static int g_temperature_c;
static int g_power_mw;
static int g_power_limit_mw;
static int g_enforced_power_limit_mw;
static int g_clock_graphics_mhz;
static int g_clock_sm_mhz;
static int g_clock_mem_mhz;
static int g_fan_speed_pct;
static int g_pcie_link_gen;
static int g_pcie_link_width;
static long long g_energy_mj;

static int g_err_stage;
static int g_err_code;
static char g_err_text[512];

static const char *nvml_stage_name(int stage) {
  switch (stage) {
    case 0: return "load";
    case 1: return "init";
    case 2: return "driver-version";
    case 3: return "nvml-version";
    case 4: return "device-count";
    case 5: return "device-handle";
    case 6: return "name";
    case 7: return "uuid";
    case 8: return "serial";
    case 9: return "pci";
    case 10: return "memory";
    case 11: return "utilization";
    case 12: return "temperature";
    case 13: return "power";
    case 14: return "power-limit";
    case 15: return "enforced-power-limit";
    case 16: return "clocks";
    case 17: return "fan";
    case 18: return "pcie";
    case 19: return "energy";
    case 20: return "shutdown";
    default: return "unknown";
  }
}

static int nv_fail(int high_level, int stage, int code) {
  const char *n_text = 0;
  g_err_stage = stage;
  g_err_code = code;
  if (g_api.error_string != 0) {
    n_text = g_api.error_string(code);
  }
  snprintf(g_err_text, sizeof(g_err_text), "%s: %s (code=%d)", nvml_stage_name(stage),
           n_text != 0 ? n_text : "failed", code);
  return -high_level;
}

static int nv_fail_text(int high_level, int stage, const char *text) {
  g_err_stage = stage;
  g_err_code = 0;
  snprintf(g_err_text, sizeof(g_err_text), "%s: %s", nvml_stage_name(stage),
           text != 0 ? text : "failed");
  return -high_level;
}

static void nv_reset_system(void) {
  g_driver_version[0] = 0;
  g_nvml_version[0] = 0;
  g_device_count = 0;
}

static void nv_reset_device(void) {
  g_name[0] = 0;
  g_uuid[0] = 0;
  g_serial[0] = 0;
  g_bus_id[0] = 0;
  g_index = -1;
  g_pci_domain = -1;
  g_pci_bus = -1;
  g_pci_device = -1;
  g_pci_ids_raw = -1;
  g_pci_vendor_id = -1;
  g_pci_device_id = -1;
  g_pci_subsystem_id = -1;
  g_memory_total = -1;
  g_memory_free = -1;
  g_memory_used = -1;
  g_utilization_gpu = -1;
  g_utilization_memory = -1;
  g_temperature_c = -1;
  g_power_mw = -1;
  g_power_limit_mw = -1;
  g_enforced_power_limit_mw = -1;
  g_clock_graphics_mhz = -1;
  g_clock_sm_mhz = -1;
  g_clock_mem_mhz = -1;
  g_fan_speed_pct = -1;
  g_pcie_link_gen = -1;
  g_pcie_link_width = -1;
  g_energy_mj = -1;
}

static int nv_load_api(const char *dll_name) {
  memset(&g_api, 0, sizeof(g_api));
  g_api.mod = LoadLibraryA(dll_name);
  if (g_api.mod == 0) return -100;

  g_api.init = (PFN_nvmlInit_v2)(void *)GetProcAddress(g_api.mod, "nvmlInit_v2");
  g_api.shutdown = (PFN_nvmlShutdown)(void *)GetProcAddress(g_api.mod, "nvmlShutdown");
  g_api.error_string = (PFN_nvmlErrorString)(void *)GetProcAddress(g_api.mod, "nvmlErrorString");
  g_api.system_driver_version = (PFN_nvmlSystemGetDriverVersion)(void *)GetProcAddress(
      g_api.mod, "nvmlSystemGetDriverVersion");
  g_api.system_nvml_version = (PFN_nvmlSystemGetNVMLVersion)(void *)GetProcAddress(
      g_api.mod, "nvmlSystemGetNVMLVersion");
  g_api.device_count = (PFN_nvmlDeviceGetCount_v2)(void *)GetProcAddress(
      g_api.mod, "nvmlDeviceGetCount_v2");
  g_api.device_handle = (PFN_nvmlDeviceGetHandleByIndex_v2)(void *)GetProcAddress(
      g_api.mod, "nvmlDeviceGetHandleByIndex_v2");
  g_api.device_name = (PFN_nvmlDeviceGetName)(void *)GetProcAddress(g_api.mod,
                                                                   "nvmlDeviceGetName");
  g_api.device_uuid = (PFN_nvmlDeviceGetUUID)(void *)GetProcAddress(g_api.mod,
                                                                   "nvmlDeviceGetUUID");
  g_api.device_serial = (PFN_nvmlDeviceGetSerial)(void *)GetProcAddress(
      g_api.mod, "nvmlDeviceGetSerial");
  g_api.device_pci = (PFN_nvmlDeviceGetPciInfo_v3)(void *)GetProcAddress(
      g_api.mod, "nvmlDeviceGetPciInfo_v3");
  g_api.device_memory = (PFN_nvmlDeviceGetMemoryInfo)(void *)GetProcAddress(
      g_api.mod, "nvmlDeviceGetMemoryInfo");
  g_api.device_utilization = (PFN_nvmlDeviceGetUtilizationRates)(void *)GetProcAddress(
      g_api.mod, "nvmlDeviceGetUtilizationRates");
  g_api.device_temperature = (PFN_nvmlDeviceGetTemperature)(void *)GetProcAddress(
      g_api.mod, "nvmlDeviceGetTemperature");
  g_api.device_power = (PFN_nvmlDeviceGetPowerUsage)(void *)GetProcAddress(
      g_api.mod, "nvmlDeviceGetPowerUsage");
  g_api.device_power_limit = (PFN_nvmlDeviceGetPowerManagementLimit)(void *)GetProcAddress(
      g_api.mod, "nvmlDeviceGetPowerManagementLimit");
  g_api.device_enforced_power_limit = (PFN_nvmlDeviceGetEnforcedPowerLimit)(void *)GetProcAddress(
      g_api.mod, "nvmlDeviceGetEnforcedPowerLimit");
  g_api.device_clock = (PFN_nvmlDeviceGetClockInfo)(void *)GetProcAddress(
      g_api.mod, "nvmlDeviceGetClockInfo");
  g_api.device_fan = (PFN_nvmlDeviceGetFanSpeed)(void *)GetProcAddress(g_api.mod,
                                                                      "nvmlDeviceGetFanSpeed");
  g_api.device_pcie_gen = (PFN_nvmlDeviceGetCurrPcieLinkGeneration)(void *)GetProcAddress(
      g_api.mod, "nvmlDeviceGetCurrPcieLinkGeneration");
  g_api.device_pcie_width = (PFN_nvmlDeviceGetCurrPcieLinkWidth)(void *)GetProcAddress(
      g_api.mod, "nvmlDeviceGetCurrPcieLinkWidth");
  g_api.device_energy = (PFN_nvmlDeviceGetTotalEnergyConsumption)(void *)GetProcAddress(
      g_api.mod, "nvmlDeviceGetTotalEnergyConsumption");

  if (g_api.init == 0 || g_api.shutdown == 0 || g_api.error_string == 0 ||
      g_api.system_driver_version == 0 || g_api.system_nvml_version == 0 ||
      g_api.device_count == 0 || g_api.device_handle == 0 || g_api.device_name == 0 ||
      g_api.device_uuid == 0 || g_api.device_pci == 0 || g_api.device_memory == 0 ||
      g_api.device_utilization == 0 || g_api.device_temperature == 0 ||
      g_api.device_power == 0 || g_api.device_clock == 0) {
    return -102;
  }
  return 0;
}

static void nv_unload_api(void) {
  if (g_api.mod != 0) {
    FreeLibrary(g_api.mod);
  }
  memset(&g_api, 0, sizeof(g_api));
}

static int nv_init_library(void) {
  int n_rc = g_api.init();
  if (n_rc == NVML_ERROR_DRIVER_NOT_LOADED || n_rc == NVML_ERROR_LIBRARY_NOT_FOUND) {
    return -101;
  }
  if (n_rc != NVML_SUCCESS) {
    return nv_fail(104, 1, n_rc);
  }
  return 0;
}

static int nv_shutdown_library(void) {
  int n_rc = g_api.shutdown();
  if (n_rc != NVML_SUCCESS) {
    return nv_fail(104, 20, n_rc);
  }
  return 0;
}

static int nv_copy_string(char *dst, size_t capacity, const char *src) {
  if (dst == 0 || capacity == 0) return -107;
  if (src == 0) {
    dst[0] = 0;
    return 0;
  }
  strncpy(dst, src, capacity - 1);
  dst[capacity - 1] = 0;
  return 0;
}

// ---------------------------------------------------------------------------
// System snapshot: versions + device count
// ---------------------------------------------------------------------------

int nvb_nvml_system_run(const char *dll_name) {
  if (dll_name == 0) return nv_fail_text(107, 0, "null loader name");
  nv_reset_system();
  g_err_stage = 0;
  g_err_code = 0;
  g_err_text[0] = 0;

  int n_rc = nv_load_api(dll_name);
  if (n_rc != 0) {
    if (n_rc == -100) return nv_fail_text(100, 0, "nvml.dll not found");
    return nv_fail_text(102, 0, "required NVML entry point missing");
  }

  n_rc = nv_init_library();
  if (n_rc != 0) {
    nv_unload_api();
    if (n_rc == -101) return nv_fail_text(101, 1, "NVIDIA driver / NVML not loaded");
    return n_rc;
  }

  n_rc = g_api.system_driver_version(g_driver_version,
                                     NVML_SYSTEM_DRIVER_VERSION_BUFFER_SIZE);
  if (n_rc != NVML_SUCCESS) {
    int n_err = nv_fail(105, 2, n_rc);
    nv_unload_api();
    return n_err;
  }
  g_driver_version[NVML_SYSTEM_DRIVER_VERSION_BUFFER_SIZE - 1] = 0;

  n_rc = g_api.system_nvml_version(g_nvml_version, NVML_SYSTEM_NVML_VERSION_BUFFER_SIZE);
  if (n_rc != NVML_SUCCESS) {
    int n_err = nv_fail(105, 3, n_rc);
    nv_unload_api();
    return n_err;
  }
  g_nvml_version[NVML_SYSTEM_NVML_VERSION_BUFFER_SIZE - 1] = 0;

  n_rc = g_api.device_count(&g_device_count);
  if (n_rc != NVML_SUCCESS) {
    int n_err = nv_fail(105, 4, n_rc);
    nv_unload_api();
    return n_err;
  }

  n_rc = nv_shutdown_library();
  nv_unload_api();
  return n_rc;
}

// ---------------------------------------------------------------------------
// Device snapshot: identity + telemetry for one index
// ---------------------------------------------------------------------------

static int nv_query_optional_u32(void *fn, nvmlDevice_t device, int stage, int *out) {
  unsigned int n_value = 0;
  int n_rc;
  *out = -1;
  if (fn == 0) return 0;
  n_rc = ((nvmlReturn_t(*)(nvmlDevice_t, unsigned int *))fn)(device, &n_value);
  if (n_rc == NVML_SUCCESS) {
    *out = (int)n_value;
    return 0;
  }
  if (n_rc == NVML_ERROR_NOT_SUPPORTED || n_rc == NVML_ERROR_NOT_FOUND) return 0;
  return nv_fail(105, stage, n_rc);
}

static int nv_query_optional_u64(void *fn, nvmlDevice_t device, int stage, long long *out) {
  unsigned long long n_value = 0;
  int n_rc;
  *out = -1;
  if (fn == 0) return 0;
  n_rc = ((nvmlReturn_t(*)(nvmlDevice_t, unsigned long long *))fn)(device, &n_value);
  if (n_rc == NVML_SUCCESS) {
    *out = (long long)n_value;
    return 0;
  }
  if (n_rc == NVML_ERROR_NOT_SUPPORTED || n_rc == NVML_ERROR_NOT_FOUND) return 0;
  return nv_fail(105, stage, n_rc);
}

int nvb_nvml_device_run(const char *dll_name, int index) {
  if (dll_name == 0) return nv_fail_text(107, 0, "null loader name");
  nv_reset_device();
  g_err_stage = 0;
  g_err_code = 0;
  g_err_text[0] = 0;

  int n_rc = nv_load_api(dll_name);
  if (n_rc != 0) {
    if (n_rc == -100) return nv_fail_text(100, 0, "nvml.dll not found");
    return nv_fail_text(102, 0, "required NVML entry point missing");
  }

  n_rc = nv_init_library();
  if (n_rc != 0) {
    nv_unload_api();
    if (n_rc == -101) return nv_fail_text(101, 1, "NVIDIA driver / NVML not loaded");
    return n_rc;
  }

  unsigned int n_count = 0;
  n_rc = g_api.device_count(&n_count);
  if (n_rc != NVML_SUCCESS) {
    int n_err = nv_fail(105, 4, n_rc);
    nv_unload_api();
    return n_err;
  }
  if (n_count == 0) {
    nv_unload_api();
    return nv_fail_text(103, 4, "no NVIDIA device");
  }
  if (index < 0 || (unsigned int)index >= n_count) {
    nv_unload_api();
    return nv_fail_text(106, 5, "device index out of range");
  }

  nvmlDevice_t n_device = 0;
  n_rc = g_api.device_handle((unsigned int)index, &n_device);
  if (n_rc != NVML_SUCCESS) {
    int n_err = nv_fail(105, 5, n_rc);
    nv_unload_api();
    return n_err;
  }
  g_index = index;

  n_rc = g_api.device_name(n_device, g_name, NVML_DEVICE_NAME_BUFFER_SIZE);
  if (n_rc != NVML_SUCCESS) {
    int n_err = nv_fail(105, 6, n_rc);
    nv_unload_api();
    return n_err;
  }
  g_name[NVML_DEVICE_NAME_BUFFER_SIZE - 1] = 0;

  n_rc = g_api.device_uuid(n_device, g_uuid, NVML_DEVICE_UUID_BUFFER_SIZE);
  if (n_rc != NVML_SUCCESS) {
    int n_err = nv_fail(105, 7, n_rc);
    nv_unload_api();
    return n_err;
  }
  g_uuid[NVML_DEVICE_UUID_BUFFER_SIZE - 1] = 0;

  if (g_api.device_serial != 0) {
    n_rc = g_api.device_serial(n_device, g_serial, NVML_DEVICE_SERIAL_BUFFER_SIZE);
    if (n_rc == NVML_SUCCESS) {
      g_serial[NVML_DEVICE_SERIAL_BUFFER_SIZE - 1] = 0;
    } else if (n_rc != NVML_ERROR_NOT_SUPPORTED && n_rc != NVML_ERROR_NOT_FOUND) {
      int n_err = nv_fail(105, 8, n_rc);
      nv_unload_api();
      return n_err;
    } else {
      g_serial[0] = 0;
    }
  }

  nvmlPciInfo_t n_pci;
  memset(&n_pci, 0, sizeof(n_pci));
  n_rc = g_api.device_pci(n_device, &n_pci);
  if (n_rc != NVML_SUCCESS) {
    int n_err = nv_fail(105, 9, n_rc);
    nv_unload_api();
    return n_err;
  }
  g_pci_domain = (int)n_pci.domain;
  g_pci_bus = (int)n_pci.bus;
  g_pci_device = (int)n_pci.device;
  g_pci_ids_raw = (int)n_pci.pciDeviceId;
  g_pci_vendor_id = (int)(n_pci.pciDeviceId & 0xFFFFu);
  g_pci_device_id = (int)((n_pci.pciDeviceId >> 16) & 0xFFFFu);
  g_pci_subsystem_id = (int)n_pci.pciSubSystemId;
  g_bus_id[NVML_DEVICE_PCI_BUS_ID_BUFFER_SIZE - 1] = 0;
  nv_copy_string(g_bus_id, NVML_DEVICE_PCI_BUS_ID_BUFFER_SIZE, n_pci.busId);

  nvmlMemory_t n_memory;
  memset(&n_memory, 0, sizeof(n_memory));
  n_rc = g_api.device_memory(n_device, &n_memory);
  if (n_rc != NVML_SUCCESS) {
    int n_err = nv_fail(105, 10, n_rc);
    nv_unload_api();
    return n_err;
  }
  g_memory_total = (long long)n_memory.total;
  g_memory_free = (long long)n_memory.free;
  g_memory_used = (long long)n_memory.used;

  nvmlUtilization_t n_utilization;
  memset(&n_utilization, 0, sizeof(n_utilization));
  n_rc = g_api.device_utilization(n_device, &n_utilization);
  if (n_rc != NVML_SUCCESS) {
    int n_err = nv_fail(105, 11, n_rc);
    nv_unload_api();
    return n_err;
  }
  g_utilization_gpu = (int)n_utilization.gpu;
  g_utilization_memory = (int)n_utilization.memory;

  unsigned int n_value = 0;
  n_rc = g_api.device_temperature(n_device, NVML_TEMPERATURE_GPU, &n_value);
  if (n_rc != NVML_SUCCESS) {
    int n_err = nv_fail(105, 12, n_rc);
    nv_unload_api();
    return n_err;
  }
  g_temperature_c = (int)n_value;

  n_rc = g_api.device_power(n_device, &n_value);
  if (n_rc != NVML_SUCCESS) {
    int n_err = nv_fail(105, 13, n_rc);
    nv_unload_api();
    return n_err;
  }
  g_power_mw = (int)n_value;

  n_rc = nv_query_optional_u32((void *)g_api.device_power_limit, n_device, 14,
                               &g_power_limit_mw);
  if (n_rc != 0) {
    nv_unload_api();
    return n_rc;
  }

  n_rc = nv_query_optional_u32((void *)g_api.device_enforced_power_limit, n_device, 15,
                               &g_enforced_power_limit_mw);
  if (n_rc != 0) {
    nv_unload_api();
    return n_rc;
  }

  n_rc = g_api.device_clock(n_device, NVML_CLOCK_GRAPHICS, &n_value);
  if (n_rc != NVML_SUCCESS) {
    int n_err = nv_fail(105, 16, n_rc);
    nv_unload_api();
    return n_err;
  }
  g_clock_graphics_mhz = (int)n_value;

  n_rc = g_api.device_clock(n_device, NVML_CLOCK_SM, &n_value);
  if (n_rc != NVML_SUCCESS) {
    int n_err = nv_fail(105, 16, n_rc);
    nv_unload_api();
    return n_err;
  }
  g_clock_sm_mhz = (int)n_value;

  n_rc = g_api.device_clock(n_device, NVML_CLOCK_MEM, &n_value);
  if (n_rc != NVML_SUCCESS) {
    int n_err = nv_fail(105, 16, n_rc);
    nv_unload_api();
    return n_err;
  }
  g_clock_mem_mhz = (int)n_value;

  n_rc = nv_query_optional_u32((void *)g_api.device_fan, n_device, 17, &g_fan_speed_pct);
  if (n_rc != 0) {
    nv_unload_api();
    return n_rc;
  }

  n_rc = nv_query_optional_u32((void *)g_api.device_pcie_gen, n_device, 18,
                               &g_pcie_link_gen);
  if (n_rc != 0) {
    nv_unload_api();
    return n_rc;
  }

  n_rc = nv_query_optional_u32((void *)g_api.device_pcie_width, n_device, 18,
                               &g_pcie_link_width);
  if (n_rc != 0) {
    nv_unload_api();
    return n_rc;
  }

  n_rc = nv_query_optional_u64((void *)g_api.device_energy, n_device, 19, &g_energy_mj);
  if (n_rc != 0) {
    nv_unload_api();
    return n_rc;
  }

  n_rc = nv_shutdown_library();
  nv_unload_api();
  return n_rc;
}

// ---------------------------------------------------------------------------
// Snapshot getters (all values are cached by the run call above)
// ---------------------------------------------------------------------------

const char *nvb_nvml_driver_version(void) { return g_driver_version; }
const char *nvb_nvml_nvml_version(void) { return g_nvml_version; }
int nvb_nvml_device_count(void) { return (int)g_device_count; }

const char *nvb_nvml_name(void) { return g_name; }
const char *nvb_nvml_uuid(void) { return g_uuid; }
const char *nvb_nvml_serial(void) { return g_serial; }
const char *nvb_nvml_bus_id(void) { return g_bus_id; }
int nvb_nvml_index(void) { return g_index; }
int nvb_nvml_pci_domain(void) { return g_pci_domain; }
int nvb_nvml_pci_bus(void) { return g_pci_bus; }
int nvb_nvml_pci_device(void) { return g_pci_device; }
int nvb_nvml_pci_ids_raw(void) { return g_pci_ids_raw; }
int nvb_nvml_pci_vendor_id(void) { return g_pci_vendor_id; }
int nvb_nvml_pci_device_id(void) { return g_pci_device_id; }
int nvb_nvml_pci_subsystem_id(void) { return g_pci_subsystem_id; }
long long nvb_nvml_memory_total(void) { return g_memory_total; }
long long nvb_nvml_memory_free(void) { return g_memory_free; }
long long nvb_nvml_memory_used(void) { return g_memory_used; }
int nvb_nvml_utilization_gpu(void) { return g_utilization_gpu; }
int nvb_nvml_utilization_memory(void) { return g_utilization_memory; }
int nvb_nvml_temperature_c(void) { return g_temperature_c; }
int nvb_nvml_power_mw(void) { return g_power_mw; }
int nvb_nvml_power_limit_mw(void) { return g_power_limit_mw; }
int nvb_nvml_enforced_power_limit_mw(void) { return g_enforced_power_limit_mw; }
int nvb_nvml_clock_graphics_mhz(void) { return g_clock_graphics_mhz; }
int nvb_nvml_clock_sm_mhz(void) { return g_clock_sm_mhz; }
int nvb_nvml_clock_mem_mhz(void) { return g_clock_mem_mhz; }
int nvb_nvml_fan_speed_pct(void) { return g_fan_speed_pct; }
int nvb_nvml_pcie_link_gen(void) { return g_pcie_link_gen; }
int nvb_nvml_pcie_link_width(void) { return g_pcie_link_width; }
long long nvb_nvml_energy_mj(void) { return g_energy_mj; }

const char *nvb_nvml_last_error_text(void) { return g_err_text; }
int nvb_nvml_last_error_stage(void) { return g_err_stage; }
int nvb_nvml_last_error_code(void) { return g_err_code; }
