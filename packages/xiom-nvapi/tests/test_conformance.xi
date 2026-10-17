// xiom.nvapi conformance suite -- NVAPI presence/identity/telemetry via the
// runtime loader (nvapi64.dll ships with the NVIDIA display driver).
//
// CI WITHOUT AN NVIDIA GPU stays green: the deterministic skip path passes a
// bogus DLL name (LOAD_ABSENT), and the live group reports SKIP when the
// driver/GPU is absent.  On the pinned RTX 3070 Ti host the suite checks the
// interface/driver versions, GPU enumeration, GPU 0 identity, and the
// optional thermal/utilization metrics.
//
// Build+run (the bridge C source rides in port.args.json):
//   scripts/port.ps1 -Package xiom.nvapi -TimeoutSec 180

module nvapi_conformance

use xiom.io;
use xiom.test;
use xiom.nvapi;

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

fn skip_or_fail(err: &NvapiError, name: Str) -> Int {
  if nvapi_is_skip(err) {
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
  io.println("=== xiom.nvapi conformance tests (presence + identity, runtime loader) ===");
  io.flush_stdout();
  var failed: Int = 0;

  // 1. SKIP classifier.
  let load_err = NvapiError{ kind: NVAPI_LOAD_ABSENT; stage: 0; code: 0; message: "x" };
  failed = failed + report(nvapi_is_skip(&load_err), "skip classifier: LOAD_ABSENT is SKIP");
  let driver_err = NvapiError{ kind: NVAPI_DRIVER_ABSENT; stage: 2; code: 0 - 6; message: "x" };
  failed = failed + report(nvapi_is_skip(&driver_err),
    "skip classifier: DRIVER_ABSENT is SKIP");
  let no_dev_err = NvapiError{ kind: NVAPI_NO_DEVICE; stage: 5; code: 0 - 6; message: "x" };
  failed = failed + report(nvapi_is_skip(&no_dev_err), "skip classifier: NO_DEVICE is SKIP");
  let api_err = NvapiError{ kind: NVAPI_API_FAILED; stage: 7; code: 0 - 1; message: "x" };
  failed = failed + report(!nvapi_is_skip(&api_err),
    "skip classifier: API failure is not SKIP");
  let abi_err = NvapiError{ kind: NVAPI_ABI; stage: 1; code: 0; message: "x" };
  failed = failed + report(!nvapi_is_skip(&abi_err), "skip classifier: ABI is not SKIP");

  // 2. Deterministic SKIP path (bogus module on every host).
  let missing = nvapi_probe_named("xiom-absent-nvapi-probe-xyz.dll");
  if missing.is_ok {
    failed = failed + report(false, "skip-path: bogus loader unexpectedly succeeded");
  } else {
    failed = failed + report(missing.error.kind == NVAPI_LOAD_ABSENT,
      "skip-path: missing loader classified as NVAPI_LOAD_ABSENT (SKIP)");
  }

  // 3. Live probe (or SKIP without an NVIDIA driver/GPU).
  let p = nvapi_probe();
  if p.is_ok {
    let info = p.value;
    failed = failed + report(info.interface_version.len() > 0,
      "presence: interface version " + info.interface_version);
    failed = failed + report(info.driver_version_raw > 0,
      "presence: driver version raw (packed) " + i2s(info.driver_version_raw));
    failed = failed + report(in_range(info.driver_version_major, 100, 1023),
      "driver: version " + i2s(info.driver_version_major) + "."
        + i2s(info.driver_version_minor));
    failed = failed + report(info.driver_version_raw ==
      info.driver_version_major * 100 + info.driver_version_minor,
      "driver: raw word matches major*100+minor");
    failed = failed + report(info.driver_branch.len() > 0,
      "driver: branch " + info.driver_branch);
    failed = failed + report(info.gpu_count >= 1,
      "enumerate: physical GPU count " + i2s(info.gpu_count));
    failed = failed + report(info.gpu_name.len() > 0, "gpu: name " + info.gpu_name);
    failed = failed + report(info.vendor_id == 4318,
      "gpu: PCI vendor id " + i2s(info.vendor_id) + " (0x10DE = NVIDIA)");
    failed = failed + report(info.pci_device_id > 0,
      "gpu: PCI device id " + i2s(info.pci_device_id));
    failed = failed + report(info.device_id ==
      (info.pci_device_id * 65536 + info.vendor_id),
      "gpu: combined device id word decomposes");
    failed = failed + report(info.subsystem_id >= 0,
      "gpu: PCI subsystem id " + i2s(info.subsystem_id));
    failed = failed + report(info.ext_device_id >= 0,
      "gpu: PCI extended device id " + i2s(info.ext_device_id));
    failed = failed + report(info.revision_id >= 0,
      "gpu: PCI revision " + i2s(info.revision_id));
    failed = failed + report(info.bus_id >= 0, "gpu: bus id " + i2s(info.bus_id));
    failed = failed + report(info.temperature_c == 0 - 1 ||
      in_range(info.temperature_c, 0, 120),
      "thermal: " + i2s(info.temperature_c) + " C (optional)");
    failed = failed + report(info.utilization_gpu_pct == 0 - 1 ||
      in_range(info.utilization_gpu_pct, 0, 100),
      "utilization: gpu " + i2s(info.utilization_gpu_pct) + "% (optional)");
    failed = failed + report(nvapi_summary(&info).len() > 0,
      "summary: " + nvapi_summary(&info));

    // 4. Snapshot stability.
    let q = nvapi_probe();
    if q.is_ok {
      failed = failed + report(q.value.gpu_name == info.gpu_name,
        "stability: two probes report the same GPU");
      failed = failed + report(q.value.driver_version_raw == info.driver_version_raw,
        "stability: driver version is stable");
    } else {
      failed = failed + report(false, "stability: repeated probe failed");
    }
  } else {
    failed = failed + skip_or_fail(&p.error, "probe");
  }

  if failed == 0 {
    io.println("xiom.nvapi: all tests passed");
  } else {
    io.println("xiom.nvapi: tests failed");
  }
  return failed;
}
