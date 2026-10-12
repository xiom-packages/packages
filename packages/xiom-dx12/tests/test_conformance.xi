// xiom.dx12 conformance suite -- foundation probe (runtime d3d12.dll).
//
// The probe is capability-staged and never FAILs on a missing GPU:
//   present runtime  -> symbols + device (D3D12CreateDevice 11_0) + one
//                       vtable call (GetNodeCount) + an out-param interface
//                       roundtrip (CreateCommandAllocator) + Release
//   missing runtime  -> DX12_LOAD_ABSENT (SKIP; exercised deterministically
//                       below with a bogus soname)
//   no adapter       -> DX12_LOAD_NO_DEVICE (SKIP)
//   broken install   -> DX12_LOAD_ABI (FAIL -- never a silent SKIP)
//
// Build+run through the runner (compiles src/dx12_probe.c via port.args.json):
//   scripts/port.ps1 -Package xiom.dx12
// or directly:
//   xiom --run tests/test_conformance.xi --c-source <abs>/src/dx12_probe.c

module dx12_conformance

use xiom.io;
use xiom.convert;
use xiom.test;
use xiom.dx12;

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

fn t_constants() -> Bool {
  var ok = true;
  if D3D_FEATURE_LEVEL_11_0 != 0xB000 { ok = false; }
  if D3D_FEATURE_LEVEL_11_1 != 0xB100 { ok = false; }
  if D3D_FEATURE_LEVEL_12_0 != 0xC000 { ok = false; }
  if D3D_FEATURE_LEVEL_12_2 != 0xC200 { ok = false; }
  if D3D12_COMMAND_LIST_TYPE_DIRECT != 0 { ok = false; }
  if D3D12_COMMAND_LIST_TYPE_BUNDLE != 1 { ok = false; }
  if D3D12_COMMAND_LIST_TYPE_COMPUTE != 2 { ok = false; }
  if D3D12_COMMAND_LIST_TYPE_COPY != 3 { ok = false; }
  if DX12_SONAME != "d3d12.dll" { ok = false; }
  return ok;
}

fn main() -> Int {
  io.println("=== xiom.dx12 conformance tests (foundation probe) ===");
  io.flush_stdout();
  var failed: Int = 0;

  failed = failed + report(t_constants(), "constants: feature levels + command list types + soname");

  // SKIP-path classification, deterministic on every host (bogus soname).
  let missing = dx12_probe_named("xiom-absent-dx12-probe-xyz.dll");
  if missing.is_ok {
    failed = failed + report(false, "skip-path: bogus soname unexpectedly produced a device");
  } else {
    failed = failed + report(missing.error.kind == DX12_LOAD_ABSENT,
      "skip-path: absent runtime classified as DX12_LOAD_ABSENT (SKIP)");
  }

  // Default runtime probe.
  let p = dx12_probe();
  if p.is_ok {
    let info: Dx12DeviceInfo = p.value;
    failed = failed + report(info.node_count >= 1,
      "device: D3D12CreateDevice ok (node_count=" + to_string(info.node_count) + ")");
    failed = failed + report(info.allocator_ok,
      "device: CreateCommandAllocator out-param roundtrip + Release");
  } else {
    if p.error.kind == DX12_LOAD_ABSENT {
      failed = failed + report(true, "probe: SKIP -- d3d12 runtime not present (" + p.error.message + ")");
    } else if p.error.kind == DX12_LOAD_NO_DEVICE {
      failed = failed + report(true, "probe: SKIP -- no D3D12-capable adapter (" + p.error.message + ")");
    } else {
      failed = failed + report(false, "probe: failed -- " + p.error.message);
    }
  }

  // Unload must be safe even after a failed probe.
  dx12_unload();
  failed = failed + report(true, "loader: unload path exercised");

  if failed == 0 {
    io.println("xiom.dx12: all tests passed");
  } else {
    io.println("xiom.dx12: tests failed");
  }
  return failed;
}
