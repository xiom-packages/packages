// XIOM -- xiom.nvapi: NVIDIA NVAPI loader + presence/identity/telemetry
// bindings.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// DESIGN: system-library path -- **nothing is vendored**.  `nvapi64.dll`
// ships with the NVIDIA display driver.  NVAPI exports only
// `nvapi_QueryInterface`; the bridge resolves each declared entry point by
// its numeric function id and keeps every foreign handle in C
// (src-less layout: nvapi_bridge.c sits beside this module).
//
// Classification: loader missing / driver unavailable / no physical GPU ->
// SKIP; a present driver that rejects a declared query -> FAIL.  The
// deterministic SKIP path is exercisable on any host via
// `nvapi_probe_named` with a bogus module name.
//
// G2 pin (SPEC.md): soname `nvapi64.dll` + function-id set + struct layout
// assertions + local sample (System32 version/hash), declaration oracle =
// NVIDIA/nvapi at the pin in PROVENANCE.md.
//
// Declared 0.1.0 subset (deliberately small, see SPEC.md section 4):
// initialize/unload, interface version, driver version + branch, physical
// GPU enumeration (count), GPU 0 identity (full name, PCI ids, bus id),
// GPU-die temperature and graphics-engine utilization.  Optional metrics are
// `-1` when the driver reports NVAPI_NOT_SUPPORTED.

module xiom.nvapi

use xiom.string;

extern "C" {
  fn nvb_nvapi_probe_run(dll: *UInt8) -> Int32;

  fn nvb_nvapi_interface_version() -> *UInt8;
  fn nvb_nvapi_driver_branch() -> *UInt8;
  fn nvb_nvapi_gpu_name() -> *UInt8;
  fn nvb_nvapi_driver_version_raw() -> Int32;
  fn nvb_nvapi_driver_version_major() -> Int32;
  fn nvb_nvapi_driver_version_minor() -> Int32;
  fn nvb_nvapi_gpu_count() -> Int32;
  fn nvb_nvapi_device_id() -> Int32;
  fn nvb_nvapi_vendor_id() -> Int32;
  fn nvb_nvapi_pci_device_id() -> Int32;
  fn nvb_nvapi_subsystem_id() -> Int32;
  fn nvb_nvapi_revision_id() -> Int32;
  fn nvb_nvapi_ext_device_id() -> Int32;
  fn nvb_nvapi_bus_id() -> Int32;
  fn nvb_nvapi_temperature_c() -> Int32;
  fn nvb_nvapi_utilization_gpu_pct() -> Int32;

  fn nvb_nvapi_last_error_text() -> *UInt8;
  fn nvb_nvapi_last_error_stage() -> Int32;
  fn nvb_nvapi_last_error_code() -> Int32;
}

// ---- error kinds ----------------------------------------------------------

pub const NVAPI_LOAD_ABSENT: Int = 0;    // nvapi64.dll missing -> SKIP
pub const NVAPI_DRIVER_ABSENT: Int = 1;  // driver / NVAPI unavailable -> SKIP
pub const NVAPI_NO_DEVICE: Int = 2;      // no physical GPU -> SKIP
pub const NVAPI_ABI: Int = 3;            // required interface id missing -> FAIL
pub const NVAPI_API_FAILED: Int = 4;     // driver rejected a declared query -> FAIL
pub const NVAPI_INTERNAL: Int = 5;       // bridge/internal failure -> FAIL

pub type NvapiError = {
  kind: Int;
  stage: Int;   // bridge stage index (see nvapi_bridge.c)
  code: Int;    // raw NVAPI status where applicable
  message: Str;
}

/// Presence + identity + telemetry snapshot.  `driver_version_*` is the
/// decoded NVAPI driver version (major.minor.build on this host, e.g.
/// 616.92); `driver_version_raw` keeps the driver's packed word.
/// `temperature_c` / `utilization_gpu_pct` are `-1` when the driver reports
/// NVAPI_NOT_SUPPORTED (optional metrics).
pub type NvapiInfo = {
  interface_version: Str;
  driver_version_raw: Int;
  driver_version_major: Int;
  driver_version_minor: Int;
  driver_branch: Str;
  gpu_count: Int;
  gpu_name: Str;
  device_id: Int;      // combined NVAPI word: (pci_device_id << 16) | vendor_id
  vendor_id: Int;      // PCI vendor id (0x10DE on NVIDIA cards)
  pci_device_id: Int;  // PCI device id (0x2482 on the RTX 3070 Ti)
  subsystem_id: Int;
  revision_id: Int;
  ext_device_id: Int;
  bus_id: Int;
  temperature_c: Int;
  utilization_gpu_pct: Int;
}

fn nvapi_probe_with(dll: Str) -> Result[NvapiInfo, NvapiError]
  requires: dll.len() > 0
{
  let rc = unsafe { nvb_nvapi_probe_run(dll.c_str()) as Int };
  if rc < 0 {
    return Err(nvapi_error(rc));
  }
  return Ok(NvapiInfo{
    interface_version: unsafe { Str::from_c_str(nvb_nvapi_interface_version()) };
    driver_version_raw: unsafe { nvb_nvapi_driver_version_raw() as Int };
    driver_version_major: unsafe { nvb_nvapi_driver_version_major() as Int };
    driver_version_minor: unsafe { nvb_nvapi_driver_version_minor() as Int };
    driver_branch: unsafe { Str::from_c_str(nvb_nvapi_driver_branch()) };
    gpu_count: unsafe { nvb_nvapi_gpu_count() as Int };
    gpu_name: unsafe { Str::from_c_str(nvb_nvapi_gpu_name()) };
    device_id: unsafe { nvb_nvapi_device_id() as Int };
    vendor_id: unsafe { nvb_nvapi_vendor_id() as Int };
    pci_device_id: unsafe { nvb_nvapi_pci_device_id() as Int };
    subsystem_id: unsafe { nvb_nvapi_subsystem_id() as Int };
    revision_id: unsafe { nvb_nvapi_revision_id() as Int };
    ext_device_id: unsafe { nvb_nvapi_ext_device_id() as Int };
    bus_id: unsafe { nvb_nvapi_bus_id() as Int };
    temperature_c: unsafe { nvb_nvapi_temperature_c() as Int };
    utilization_gpu_pct: unsafe { nvb_nvapi_utilization_gpu_pct() as Int };
  });
}

/// Probe the default loader (`nvapi64.dll`): initialize NVAPI, read the
/// interface and driver versions, enumerate physical GPUs, and query GPU 0
/// identity, temperature and graphics utilization.  Complexity: O(probe).
pub fn nvapi_probe() -> Result[NvapiInfo, NvapiError] {
  return nvapi_probe_with("nvapi64.dll");
}

/// Same probe against an explicitly named loader module -- the
/// deterministic SKIP path (pass a bogus name on any host).
/// Complexity: O(probe).
pub fn nvapi_probe_named(dll: Str) -> Result[NvapiInfo, NvapiError]
  requires: dll.len() > 0
{
  return nvapi_probe_with(dll);
}

/// Whether `err` is a SKIP-classification (loader/driver/device absent).
/// Complexity: O(1).
pub fn nvapi_is_skip(err: &NvapiError) -> Bool {
  if err.kind == NVAPI_LOAD_ABSENT { return true; }
  if err.kind == NVAPI_DRIVER_ABSENT { return true; }
  if err.kind == NVAPI_NO_DEVICE { return true; }
  return false;
}

/// One-line human-readable summary for logs and reports.
/// Complexity: O(1).
pub fn nvapi_summary(info: &NvapiInfo) -> Str {
  return info.gpu_name + " (driver " + nvapi_i2s(info.driver_version_major) + "."
    + nvapi_i2s(info.driver_version_minor) + ", " + info.interface_version + "), "
    + nvapi_i2s(info.temperature_c) + "C, gpu "
    + nvapi_i2s(info.utilization_gpu_pct) + "%";
}

// ---- internals ------------------------------------------------------------

fn nvapi_kind_code(neg: Int) -> Int
  requires: neg < 0
{
  if neg == -100 { return NVAPI_LOAD_ABSENT; }
  if neg == -101 { return NVAPI_DRIVER_ABSENT; }
  if neg == -102 { return NVAPI_ABI; }
  if neg == -103 { return NVAPI_NO_DEVICE; }
  if neg == -106 { return NVAPI_INTERNAL; }
  return NVAPI_API_FAILED;
}

fn nvapi_error(neg: Int) -> NvapiError
  requires: neg < 0
{
  var msg = "";
  unsafe {
    let p = nvb_nvapi_last_error_text();
    if (p as Int) != 0 {
      msg = Str::from_c_str(p);
    }
  }
  return NvapiError{
    kind: nvapi_kind_code(neg);
    stage: unsafe { nvb_nvapi_last_error_stage() as Int };
    code: unsafe { nvb_nvapi_last_error_code() as Int };
    message: msg;
  };
}

fn nvapi_i2s(n: Int) -> Str
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
