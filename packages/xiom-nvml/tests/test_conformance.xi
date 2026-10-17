// xiom.nvml conformance suite -- NVML telemetry via the runtime loader
// (nvml.dll ships with the NVIDIA display driver; nothing vendored).
//
// CI WITHOUT AN NVIDIA GPU stays green: the deterministic skip path passes a
// bogus DLL name (LOAD_ABSENT), and every live group reports SKIP when the
// driver/device is absent.  On the pinned RTX 3070 Ti host the suite reads
// the real driver/NVML versions, the device identity, memory, utilization,
// temperature, power, clocks, fan, PCIe link and total energy.
//
// Build+run (the bridge C source rides in port.args.json):
//   scripts/port.ps1 -Package xiom.nvml -TimeoutSec 180

module nvml_conformance

use xiom.io;
use xiom.test;
use xiom.nvml;

fn i2s(n: Int) -> Str {
  if n == 0 { return "0"; }
  var neg = false;
  var v = n;
  if v < 0 {
    neg = true;
    v = 0 - v;
  }
  var buf = "";
  while v > 0 {
    let digit = v % 10;
    v = v / 10;
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
  if neg { return "-" + buf; }
  return buf;
}

fn report(ok: Bool, name: Str) -> Int {
  if ok {
    io.println("  [PASS] " + name);
    io.flush_stdout();
    return 0;
  }
  io.println("  [FAIL] " + name);
  io.flush_stdout();
  return 1;
}

fn skip_or_fail(err: &NvmlError, name: Str) -> Int {
  if nvml_is_skip(err) {
    return report(true, name + ": SKIP -- " + err.message);
  }
  return report(false, name + ": " + err.message);
}

fn in_range(value: Int, low: Int, high: Int) -> Bool
  requires: low <= high
{
  return value >= low && value <= high;
}

fn main() -> Int {
  io.println("=== xiom.nvml conformance tests (telemetry, runtime loader) ===");
  io.flush_stdout();
  var failed: Int = 0;

  // 1. SKIP classifier.
  let load_err = NvmlError{ kind: NVML_LOAD_ABSENT; stage: 0; code: 0; message: "x" };
  failed = failed + report(nvml_is_skip(&load_err), "skip classifier: LOAD_ABSENT is SKIP");
  let driver_err = NvmlError{ kind: NVML_DRIVER_ABSENT; stage: 1; code: 9; message: "x" };
  failed = failed + report(nvml_is_skip(&driver_err),
    "skip classifier: DRIVER_ABSENT is SKIP");
  let no_dev_err = NvmlError{ kind: NVML_NO_DEVICE; stage: 4; code: 0; message: "x" };
  failed = failed + report(nvml_is_skip(&no_dev_err), "skip classifier: NO_DEVICE is SKIP");
  let api_err = NvmlError{ kind: NVML_API_FAILED; stage: 10; code: 3; message: "x" };
  failed = failed + report(!nvml_is_skip(&api_err),
    "skip classifier: API failure is not SKIP");
  let bad_idx_err = NvmlError{ kind: NVML_BAD_INDEX; stage: 5; code: 0; message: "x" };
  failed = failed + report(!nvml_is_skip(&bad_idx_err),
    "skip classifier: BAD_INDEX is not SKIP");

  // 2. Deterministic SKIP path (bogus module on every host).
  let missing = nvml_system_named("xiom-absent-nvml-probe-xyz.dll");
  if missing.is_ok {
    failed = failed + report(false, "skip-path: bogus loader unexpectedly succeeded");
  } else {
    failed = failed + report(missing.error.kind == NVML_LOAD_ABSENT,
      "skip-path: missing loader classified as NVML_LOAD_ABSENT (SKIP)");
  }
  let missing_dev = nvml_device_named("xiom-absent-nvml-probe-xyz.dll", 0);
  if missing_dev.is_ok {
    failed = failed + report(false, "skip-path: bogus device loader unexpectedly succeeded");
  } else {
    failed = failed + report(missing_dev.error.kind == NVML_LOAD_ABSENT,
      "skip-path: device snapshot classifies missing loader as SKIP");
  }

  // 3. Live system snapshot (or SKIP without an NVIDIA driver/GPU).
  var live = false;
  let sys = nvml_system();
  if sys.is_ok {
    live = true;
    failed = failed + report(sys.value.driver_version.len() > 0,
      "system: driver version " + sys.value.driver_version);
    failed = failed + report(sys.value.nvml_version.len() > 0,
      "system: NVML version " + sys.value.nvml_version);
    failed = failed + report(sys.value.device_count >= 1,
      "system: device count " + i2s(sys.value.device_count));
  } else {
    failed = failed + skip_or_fail(&sys.error, "system snapshot");
    if sys.error.kind == NVML_LOAD_ABSENT || sys.error.kind == NVML_DRIVER_ABSENT ||
       sys.error.kind == NVML_NO_DEVICE {
      live = false;
    }
  }

  // 4. Live device snapshot (or SKIP).
  if live {
    let dev = nvml_device(0);
    if dev.is_ok {
      let d = dev.value;
      failed = failed + report(d.name.len() > 0,
        "device: name " + d.name);
      failed = failed + report(d.name.len() >= 6, "device: name is populated");
      failed = failed + report(d.uuid.len() > 0, "device: UUID " + d.uuid);
      failed = failed + report(d.bus_id.len() > 0, "device: PCI bus id " + d.bus_id);
      failed = failed + report(d.index == 0, "device: index 0");
      failed = failed + report(d.memory_total > 0,
        "memory: total " + i2s(d.memory_total) + " bytes");
      failed = failed + report(d.memory_free >= 0 && d.memory_free <= d.memory_total,
        "memory: free " + i2s(d.memory_free));
      failed = failed + report(d.memory_used >= 0 && d.memory_used <= d.memory_total,
        "memory: used " + i2s(d.memory_used));
      failed = failed + report(d.memory_free + d.memory_used <= d.memory_total,
        "memory: free + used <= total");
      failed = failed + report(in_range(d.utilization_gpu, 0, 100),
        "utilization: gpu " + i2s(d.utilization_gpu) + "%");
      failed = failed + report(in_range(d.utilization_memory, 0, 100),
        "utilization: memory " + i2s(d.utilization_memory) + "%");
      failed = failed + report(in_range(d.temperature_c, 0, 120),
        "thermal: " + i2s(d.temperature_c) + " C");
      failed = failed + report(d.power_mw >= 0,
        "power: usage " + i2s(d.power_mw) + " mW");
      failed = failed + report(d.power_limit_mw == 0 - 1 || d.power_limit_mw > 0,
        "power: limit " + i2s(d.power_limit_mw) + " mW (optional)");
      failed = failed + report(d.enforced_power_limit_mw == 0 - 1 ||
        d.enforced_power_limit_mw > 0,
        "power: enforced limit " + i2s(d.enforced_power_limit_mw) + " mW (optional)");
      failed = failed + report(d.clock_graphics_mhz > 0,
        "clocks: graphics " + i2s(d.clock_graphics_mhz) + " MHz");
      failed = failed + report(d.clock_sm_mhz > 0,
        "clocks: SM " + i2s(d.clock_sm_mhz) + " MHz");
      failed = failed + report(d.clock_mem_mhz > 0,
        "clocks: memory " + i2s(d.clock_mem_mhz) + " MHz");
      failed = failed + report(d.fan_speed_pct == 0 - 1 || in_range(d.fan_speed_pct, 0, 100),
        "fan: " + i2s(d.fan_speed_pct) + "% (optional)");
      failed = failed + report(d.pcie_link_gen == 0 - 1 || in_range(d.pcie_link_gen, 1, 6),
        "pcie: link generation " + i2s(d.pcie_link_gen) + " (optional)");
      failed = failed + report(d.pcie_link_width == 0 - 1 || d.pcie_link_width > 0,
        "pcie: link width x" + i2s(d.pcie_link_width) + " (optional)");
      failed = failed + report(d.energy_mj >= 0 - 1,
        "energy: total " + i2s(d.energy_mj) + " mJ (optional)");
      failed = failed + report(d.pci_domain >= 0 && d.pci_bus >= 0 && d.pci_device >= 0,
        "pci: domain/bus/device " + i2s(d.pci_domain) + "/" + i2s(d.pci_bus)
          + "/" + i2s(d.pci_device));
      failed = failed + report(d.pci_vendor_id == 4318,
        "pci: vendor id " + i2s(d.pci_vendor_id) + " (0x10DE = NVIDIA)");
      failed = failed + report(d.pci_device_id > 0,
        "pci: device id " + i2s(d.pci_device_id));
      failed = failed + report(d.pci_ids_raw ==
        d.pci_device_id * 65536 + d.pci_vendor_id,
        "pci: combined id word decomposes");
      failed = failed + report(nvml_summary(&d).len() > 0,
        "summary: " + nvml_summary(&d));
    } else {
      failed = failed + skip_or_fail(&dev.error, "device snapshot");
    }
  } else {
    failed = failed + report(true, "device snapshot: SKIP -- no live NVML system");
  }

  // 5. Out-of-range index is a typed failure, not a crash (live hosts).
  if live {
    let bad = nvml_device(9999);
    if bad.is_ok {
      failed = failed + report(false, "bounds: index 9999 unexpectedly succeeded");
    } else {
      failed = failed + report(bad.error.kind == NVML_BAD_INDEX,
        "bounds: index 9999 -> NVML_BAD_INDEX (FAIL class)");
    }
  }

  // 6. Snapshot stability: a second call reports the same identity.
  if live {
    let a = nvml_device(0);
    let b = nvml_device(0);
    if a.is_ok && b.is_ok {
      failed = failed + report(a.value.name == b.value.name && a.value.uuid == b.value.uuid,
        "stability: two snapshots report the same device");
      failed = failed + report(a.value.memory_total == b.value.memory_total,
        "stability: total memory is stable");
    } else {
      failed = failed + report(false, "stability: repeated snapshot failed");
    }
  }

  if failed == 0 {
    io.println("xiom.nvml: all tests passed");
  } else {
    io.println("xiom.nvml: tests failed");
  }
  return failed;
}
