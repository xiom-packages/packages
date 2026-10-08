// xiom.dxc conformance suite -- capability probe (dynamic loader).
//
// CI WITHOUT the DXC runtime stays green: the probe resolves
// `dxcompiler.dll` at runtime; absent compiler -> SKIP, missing entry point
// or refused COM instance -> FAIL, present-but-compile-failure -> FAIL (the
// probe shader is trivial; a failure is an ABI/SDK mismatch, not a skip).
// The SKIP path is exercised deterministically every run via a bogus soname.
//
// Build+run through the runner (compiles src/dxc_probe.c via port.args.json):
//   scripts/port.ps1 -Package xiom.dxc

module dxc_conformance

use xiom.io;
use xiom.convert;
use xiom.test;
use xiom.dxc;

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

fn main() -> Int {
  io.println("=== xiom.dxc conformance tests (capability probe) ===");
  io.flush_stdout();
  var failed: Int = 0;

  // SKIP-path classification, deterministic on every host (bogus soname).
  let missing = dxc_probe_named("xiom-absent-dxc-probe-xyz.dll");
  if missing.is_ok {
    failed = failed + report(false, "skip-path: bogus soname unexpectedly produced a compile");
  } else {
    failed = failed + report(missing.error.kind == DXC_LOAD_ABSENT,
      "skip-path: absent compiler classified as DXC_LOAD_ABSENT (SKIP)");
  }

  let p = dxc_probe();
  if p.is_ok {
    let info: DxcInfo = p.value;
    failed = failed + report(info.object_size > 0,
      "compile: ps_6_0 'main' produced a DXIL object blob (" + to_string(info.object_size) + " bytes)");
    failed = failed + report(info.object_size % 4 == 0,
      "compile: DXIL container size is 4-byte aligned");
  } else {
    if p.error.kind == DXC_LOAD_ABSENT {
      failed = failed + report(true, "probe: SKIP -- compiler not present (" + p.error.message + ")");
    } else if p.error.kind == DXC_COMPILE_FAILED {
      failed = failed + report(false, "probe: compile failed -- " + p.error.message);
    } else {
      failed = failed + report(false, "probe: ABI failure -- " + p.error.message);
    }
  }

  if failed == 0 {
    io.println("xiom.dxc: all tests passed");
  } else {
    io.println("xiom.dxc: tests failed");
  }
  return failed;
}
