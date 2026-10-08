// xiom.directx12 conformance suite -- capability probe (dynamic loader).
//
// CI WITHOUT D3D12/DXGI (or without a D3D12 device) stays green: absent
// libraries -> SKIP, D3D12CreateDevice refusal at every level -> SKIP,
// missing entry points -> FAIL. The SKIP path is exercised deterministically
// every run via bogus sonames.
//
// Build+run through the runner (compiles src/d3d12_probe.c via port.args.json):
//   scripts/port.ps1 -Package xiom.directx12

module d3d12_conformance

use xiom.io;
use xiom.convert;
use xiom.test;
use xiom.string.compare;
use xiom.directx12;

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
  if !name_is(d3d12_feature_level_name(0xc200), "12_2") { ok = false; }
  if !name_is(d3d12_feature_level_name(0xc100), "12_1") { ok = false; }
  if !name_is(d3d12_feature_level_name(0xc000), "12_0") { ok = false; }
  if !name_is(d3d12_feature_level_name(0x1234), "unknown") { ok = false; }
  return ok;
}

fn main() -> Int {
  io.println("=== xiom.directx12 conformance tests (capability probe) ===");
  io.flush_stdout();
  var failed: Int = 0;

  failed = failed + report(t_feature_level_names(), "feature-level names: 12_2/12_1/12_0/unknown");

  // SKIP-path classification, deterministic on every host (bogus sonames).
  let missing = d3d12_probe_named("xiom-absent-d3d12-xyz.dll", "xiom-absent-dxgi-xyz.dll");
  if missing.is_ok {
    failed = failed + report(false, "skip-path: bogus sonames unexpectedly produced a device");
  } else {
    failed = failed + report(missing.error.kind == D3D12_LOAD_ABSENT,
      "skip-path: absent libraries classified as D3D12_LOAD_ABSENT (SKIP)");
  }

  let p = d3d12_probe();
  if p.is_ok {
    let info: D3d12Info = p.value;
    failed = failed + report(info.feature_level >= D3D_FEATURE_LEVEL_11_0,
      "device: highest accepted feature level " + d3d12_feature_level_name(info.feature_level)
      + " (" + to_string(info.feature_level) + ")");
    failed = failed + report(info.adapter_count >= 1,
      "adapter: count = " + to_string(info.adapter_count));
    failed = failed + report(info.adapter_name.len() > 0,
      "adapter: " + info.adapter_name
      + " (vendor_id " + to_string(info.vendor_id) + ", device_id " + to_string(info.device_id) + ")");
  } else {
    if p.error.kind == D3D12_LOAD_ABSENT {
      failed = failed + report(true, "probe: SKIP -- D3D12/DXGI not present (" + p.error.message + ")");
    } else if p.error.kind == D3D12_LOAD_NO_DEVICE {
      failed = failed + report(true, "probe: SKIP -- no D3D12 device (" + p.error.message + ")");
    } else {
      failed = failed + report(false, "probe: ABI failure -- " + p.error.message);
    }
  }

  if failed == 0 {
    io.println("xiom.directx12: all tests passed");
  } else {
    io.println("xiom.directx12: tests failed");
  }
  return failed;
}
