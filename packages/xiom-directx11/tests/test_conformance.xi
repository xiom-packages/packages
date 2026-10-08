// xiom.directx11 conformance suite -- capability probe (dynamic loader).
//
// CI WITHOUT D3D11/DXGI (or without a hardware device) stays green: absent
// libraries -> SKIP, D3D11CreateDevice(HARDWARE) failure -> SKIP, missing
// entry points -> FAIL. The SKIP path is exercised deterministically every
// run via bogus sonames.
//
// Build+run through the runner (compiles src/d3d11_probe.c via port.args.json):
//   scripts/port.ps1 -Package xiom.directx11

module d3d11_conformance

use xiom.io;
use xiom.convert;
use xiom.test;
use xiom.string.compare;
use xiom.directx11;

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

fn name_is(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn t_feature_level_names() -> Bool {
  var ok = true;
  if !name_is(d3d11_feature_level_name(0xb100), "11_1") { ok = false; }
  if !name_is(d3d11_feature_level_name(0xb000), "11_0") { ok = false; }
  if !name_is(d3d11_feature_level_name(0xa000), "10_0") { ok = false; }
  if !name_is(d3d11_feature_level_name(0x1234), "unknown") { ok = false; }
  return ok;
}

fn main() -> Int {
  io.println("=== xiom.directx11 conformance tests (capability probe) ===");
  io.flush_stdout();
  var failed: Int = 0;

  failed = failed + report(t_feature_level_names(), "feature-level names: 11_1/11_0/10_0/unknown");

  // SKIP-path classification, deterministic on every host (bogus sonames).
  let missing = d3d11_probe_named("xiom-absent-d3d11-xyz.dll", "xiom-absent-dxgi-xyz.dll");
  if missing.is_ok {
    failed = failed + report(false, "skip-path: bogus sonames unexpectedly produced a device");
  } else {
    failed = failed + report(missing.error.kind == D3D11_LOAD_ABSENT,
      "skip-path: absent libraries classified as D3D11_LOAD_ABSENT (SKIP)");
  }

  let p = d3d11_probe();
  if p.is_ok {
    let info: D3d11Info = p.value;
    failed = failed + report(info.feature_level >= D3D_FEATURE_LEVEL_11_0,
      "device: hardware device at feature level " + d3d11_feature_level_name(info.feature_level)
      + " (" + to_string(info.feature_level) + ")");
    failed = failed + report(info.adapter_count >= 1,
      "adapter: count = " + to_string(info.adapter_count));
    failed = failed + report(info.adapter_name.len() > 0,
      "adapter: " + info.adapter_name
      + " (vendor_id " + to_string(info.vendor_id) + ", device_id " + to_string(info.device_id) + ")");
  } else {
    if p.error.kind == D3D11_LOAD_ABSENT {
      failed = failed + report(true, "probe: SKIP -- D3D11/DXGI not present (" + p.error.message + ")");
    } else if p.error.kind == D3D11_LOAD_NO_DEVICE {
      failed = failed + report(true, "probe: SKIP -- no hardware D3D11 device (" + p.error.message + ")");
    } else {
      failed = failed + report(false, "probe: ABI failure -- " + p.error.message);
    }
  }

  if failed == 0 {
    io.println("xiom.directx11: all tests passed");
  } else {
    io.println("xiom.directx11: tests failed");
  }
  return failed;
}
