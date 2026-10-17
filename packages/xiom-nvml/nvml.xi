// XIOM -- xiom.nvml: NVIDIA Management Library (NVML) bindings.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// DESIGN: system-library path -- **nothing is vendored**.  `nvml.dll` is a
// system component shipped with the NVIDIA display driver; it is loaded at
// run time with LoadLibraryA and every entry point is resolved with
// GetProcAddress.  The module calls an integer-only C bridge
// (src/nvml_bridge.c) that runs one snapshot query per call and caches the
// results; scalar/packed returns avoid out-param slots (finding B-11 applies
// to driver-heavy calls).
//
// All `unsafe`/`extern "C"` live in this single module (G5).
//
// Classification: loader missing / driver not loaded / no device -> SKIP;
// a present driver that rejects a declared query -> FAIL.  The deterministic
// SKIP path is exercisable on any host via `nvml_system_named` with a bogus
// module name.
//
// G2 pin (SPEC.md): soname `nvml.dll` + entry-point set + struct layout
// assertions + local sample (System32 version/hash).  The declared 0.1.0
// surface is the telemetry essentials: system versions, device enumeration,
// identity, memory, utilization, temperature, power, clocks, fan, PCIe link
// and total energy, plus the optional-metric sentinel policy.
//
// Snapshot semantics: each public call re-loads the module, initializes
// NVML, queries, and shuts down; getters are read immediately after the
// call.  Calls are not reentrant (the C bridge caches one snapshot).

module xiom.nvml

use xiom.string;

extern "C" {
  fn nvb_nvml_system_run(dll: *UInt8) -> Int32;
  fn nvb_nvml_device_run(dll: *UInt8, index: Int32) -> Int32;

  fn nvb_nvml_driver_version() -> *UInt8;
  fn nvb_nvml_nvml_version() -> *UInt8;
  fn nvb_nvml_device_count() -> Int32;

  fn nvb_nvml_name() -> *UInt8;
  fn nvb_nvml_uuid() -> *UInt8;
  fn nvb_nvml_serial() -> *UInt8;
  fn nvb_nvml_bus_id() -> *UInt8;
  fn nvb_nvml_index() -> Int32;
  fn nvb_nvml_pci_domain() -> Int32;
  fn nvb_nvml_pci_bus() -> Int32;
  fn nvb_nvml_pci_device() -> Int32;
  fn nvb_nvml_pci_ids_raw() -> Int32;
  fn nvb_nvml_pci_vendor_id() -> Int32;
  fn nvb_nvml_pci_device_id() -> Int32;
  fn nvb_nvml_pci_subsystem_id() -> Int32;
  fn nvb_nvml_memory_total() -> Int64;
  fn nvb_nvml_memory_free() -> Int64;
  fn nvb_nvml_memory_used() -> Int64;
  fn nvb_nvml_utilization_gpu() -> Int32;
  fn nvb_nvml_utilization_memory() -> Int32;
  fn nvb_nvml_temperature_c() -> Int32;
  fn nvb_nvml_power_mw() -> Int32;
  fn nvb_nvml_power_limit_mw() -> Int32;
  fn nvb_nvml_enforced_power_limit_mw() -> Int32;
  fn nvb_nvml_clock_graphics_mhz() -> Int32;
  fn nvb_nvml_clock_sm_mhz() -> Int32;
  fn nvb_nvml_clock_mem_mhz() -> Int32;
  fn nvb_nvml_fan_speed_pct() -> Int32;
  fn nvb_nvml_pcie_link_gen() -> Int32;
  fn nvb_nvml_pcie_link_width() -> Int32;
  fn nvb_nvml_energy_mj() -> Int64;

  fn nvb_nvml_last_error_text() -> *UInt8;
  fn nvb_nvml_last_error_stage() -> Int32;
  fn nvb_nvml_last_error_code() -> Int32;
}

// ---- error kinds ----------------------------------------------------------

pub const NVML_LOAD_ABSENT: Int = 0;    // nvml.dll missing -> SKIP
pub const NVML_DRIVER_ABSENT: Int = 1;  // driver not loaded / NVML unavailable -> SKIP
pub const NVML_NO_DEVICE: Int = 2;      // no NVIDIA device -> SKIP
pub const NVML_BAD_INDEX: Int = 3;      // device index out of range -> FAIL
pub const NVML_ABI: Int = 4;            // required entry point missing -> FAIL
pub const NVML_API_FAILED: Int = 5;     // driver rejected a declared query -> FAIL
pub const NVML_INTERNAL: Int = 6;       // bridge/internal failure -> FAIL

pub type NvmlError = {
  kind: Int;
  stage: Int;   // bridge stage index (see src/nvml_bridge.c)
  code: Int;    // raw NVML return code where applicable
  message: Str;
}

// ---- snapshot records -----------------------------------------------------

pub type NvmlSystem = {
  driver_version: Str;  // e.g. "616.92"
  nvml_version: Str;    // e.g. "13.616.92"
  device_count: Int;
}

/// One NVML device snapshot.  Optional metrics are `-1` when the driver
/// reports NVML_ERROR_NOT_SUPPORTED (documented in SPEC.md section 4):
/// `serial` is `""`, and power limits, fan speed, PCIe link and energy may
/// be `-1`.  Memory values are bytes; power values are milliwatts; clocks
/// are MHz; temperature is degrees Celsius; energy is millijoules.
pub type NvmlDevice = {
  index: Int;
  name: Str;
  uuid: Str;
  serial: Str;
  bus_id: Str;
  pci_domain: Int;
  pci_bus: Int;
  pci_device: Int;
  pci_ids_raw: Int;     // combined NVML pciDeviceId word
  pci_vendor_id: Int;   // low 16 bits (0x10DE on NVIDIA cards)
  pci_device_id: Int;   // high 16 bits (0x2482 on the RTX 3070 Ti)
  pci_subsystem_id: Int;
  memory_total: Int;
  memory_free: Int;
  memory_used: Int;
  utilization_gpu: Int;
  utilization_memory: Int;
  temperature_c: Int;
  power_mw: Int;
  power_limit_mw: Int;
  enforced_power_limit_mw: Int;
  clock_graphics_mhz: Int;
  clock_sm_mhz: Int;
  clock_mem_mhz: Int;
  fan_speed_pct: Int;
  pcie_link_gen: Int;
  pcie_link_width: Int;
  energy_mj: Int;
}

// ---- system ---------------------------------------------------------------

fn nvml_system_with(dll: Str) -> Result[NvmlSystem, NvmlError]
  requires: dll.len() > 0
{
  let rc = unsafe { nvb_nvml_system_run(dll.c_str()) as Int };
  if rc < 0 {
    return Err(nvml_error(rc));
  }
  return Ok(NvmlSystem{
    driver_version: unsafe { Str::from_c_str(nvb_nvml_driver_version()) };
    nvml_version: unsafe { Str::from_c_str(nvb_nvml_nvml_version()) };
    device_count: unsafe { nvb_nvml_device_count() as Int };
  });
}

/// System-level snapshot from the default loader (`nvml.dll`): driver
/// version, NVML version and device count.  Complexity: O(probe).
pub fn nvml_system() -> Result[NvmlSystem, NvmlError] {
  return nvml_system_with("nvml.dll");
}

/// Same snapshot against an explicitly named loader module -- the
/// deterministic SKIP path (pass a bogus name on any host).
/// Complexity: O(probe).
pub fn nvml_system_named(dll: Str) -> Result[NvmlSystem, NvmlError]
  requires: dll.len() > 0
{
  return nvml_system_with(dll);
}

// ---- device ---------------------------------------------------------------

fn nvml_device_with(dll: Str, index: Int) -> Result[NvmlDevice, NvmlError]
  requires: dll.len() > 0
  requires: index >= 0
{
  let rc = unsafe { nvb_nvml_device_run(dll.c_str(), index as Int32) as Int };
  if rc < 0 {
    return Err(nvml_error(rc));
  }
  return Ok(NvmlDevice{
    index: unsafe { nvb_nvml_index() as Int };
    name: unsafe { Str::from_c_str(nvb_nvml_name()) };
    uuid: unsafe { Str::from_c_str(nvb_nvml_uuid()) };
    serial: unsafe { Str::from_c_str(nvb_nvml_serial()) };
    bus_id: unsafe { Str::from_c_str(nvb_nvml_bus_id()) };
    pci_domain: unsafe { nvb_nvml_pci_domain() as Int };
    pci_bus: unsafe { nvb_nvml_pci_bus() as Int };
    pci_device: unsafe { nvb_nvml_pci_device() as Int };
    pci_ids_raw: unsafe { nvb_nvml_pci_ids_raw() as Int };
    pci_vendor_id: unsafe { nvb_nvml_pci_vendor_id() as Int };
    pci_device_id: unsafe { nvb_nvml_pci_device_id() as Int };
    pci_subsystem_id: unsafe { nvb_nvml_pci_subsystem_id() as Int };
    memory_total: unsafe { nvb_nvml_memory_total() as Int };
    memory_free: unsafe { nvb_nvml_memory_free() as Int };
    memory_used: unsafe { nvb_nvml_memory_used() as Int };
    utilization_gpu: unsafe { nvb_nvml_utilization_gpu() as Int };
    utilization_memory: unsafe { nvb_nvml_utilization_memory() as Int };
    temperature_c: unsafe { nvb_nvml_temperature_c() as Int };
    power_mw: unsafe { nvb_nvml_power_mw() as Int };
    power_limit_mw: unsafe { nvb_nvml_power_limit_mw() as Int };
    enforced_power_limit_mw: unsafe { nvb_nvml_enforced_power_limit_mw() as Int };
    clock_graphics_mhz: unsafe { nvb_nvml_clock_graphics_mhz() as Int };
    clock_sm_mhz: unsafe { nvb_nvml_clock_sm_mhz() as Int };
    clock_mem_mhz: unsafe { nvb_nvml_clock_mem_mhz() as Int };
    fan_speed_pct: unsafe { nvb_nvml_fan_speed_pct() as Int };
    pcie_link_gen: unsafe { nvb_nvml_pcie_link_gen() as Int };
    pcie_link_width: unsafe { nvb_nvml_pcie_link_width() as Int };
    energy_mj: unsafe { nvb_nvml_energy_mj() as Int };
  });
}

/// Snapshot of one device from the default loader (`nvml.dll`).  `index`
/// selects the NVML device (0 is the first GPU); an out-of-range index is
/// `NVML_BAD_INDEX` (FAIL), while a host with no device is
/// `NVML_NO_DEVICE` (SKIP).  Complexity: O(probe).
pub fn nvml_device(index: Int) -> Result[NvmlDevice, NvmlError]
  requires: index >= 0
{
  return nvml_device_with("nvml.dll", index);
}

/// Same snapshot against an explicitly named loader module -- the
/// deterministic SKIP path.
/// Complexity: O(probe).
pub fn nvml_device_named(dll: Str, index: Int) -> Result[NvmlDevice, NvmlError]
  requires: dll.len() > 0
  requires: index >= 0
{
  return nvml_device_with(dll, index);
}

/// Whether `err` is a SKIP-classification (loader/driver/device absent).
/// Complexity: O(1).
pub fn nvml_is_skip(err: &NvmlError) -> Bool {
  if err.kind == NVML_LOAD_ABSENT { return true; }
  if err.kind == NVML_DRIVER_ABSENT { return true; }
  if err.kind == NVML_NO_DEVICE { return true; }
  return false;
}

/// One-line human-readable telemetry summary for logs and reports.
/// Complexity: O(1).
pub fn nvml_summary(dev: &NvmlDevice) -> Str {
  return dev.name + " [" + dev.bus_id + "] "
    + nvml_i2s(dev.temperature_c) + "C, "
    + nvml_i2s(dev.power_mw / 1000) + "W, gpu " + nvml_i2s(dev.utilization_gpu) + "%, "
    + "mem " + nvml_i2s(dev.memory_used / (1024 * 1024)) + "/"
    + nvml_i2s(dev.memory_total / (1024 * 1024)) + " MiB";
}

// ---- internals ------------------------------------------------------------

fn nvml_kind_code(neg: Int) -> Int
  requires: neg < 0
{
  if neg == -100 { return NVML_LOAD_ABSENT; }
  if neg == -101 { return NVML_DRIVER_ABSENT; }
  if neg == -102 { return NVML_ABI; }
  if neg == -103 { return NVML_NO_DEVICE; }
  if neg == -106 { return NVML_BAD_INDEX; }
  if neg == -107 { return NVML_INTERNAL; }
  return NVML_API_FAILED;
}

fn nvml_error(neg: Int) -> NvmlError
  requires: neg < 0
{
  var msg = "";
  unsafe {
    let p = nvb_nvml_last_error_text();
    if (p as Int) != 0 {
      msg = Str::from_c_str(p);
    }
  }
  return NvmlError{
    kind: nvml_kind_code(neg);
    stage: unsafe { nvb_nvml_last_error_stage() as Int };
    code: unsafe { nvb_nvml_last_error_code() as Int };
    message: msg;
  };
}

fn nvml_i2s(n: Int) -> Str
  requires: n >= 0
{
  if n == 0 { return "0"; }
  var val = n;
  var buf = "";
  while val > 0 {
    let digit = val % 10;
    val = val / 10;
    if digit == 0 { buf = "0" + buf; }
    elif digit == 1 { buf = "1" + buf; }
    elif digit == 2 { buf = "2" + buf; }
    elif digit == 3 { buf = "3" + buf; }
    elif digit == 4 { buf = "4" + buf; }
    elif digit == 5 { buf = "5" + buf; }
    elif digit == 6 { buf = "6" + buf; }
    elif digit == 7 { buf = "7" + buf; }
    elif digit == 8 { buf = "8" + buf; }
    elif digit == 9 { buf = "9" + buf; }
  }
  return buf;
}
