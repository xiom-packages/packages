// xiom.libpq conformance suite -- dynamic-loader path.
//
// CI WITHOUT libpq stays green: absent client library -> SKIP (the SKIP path
// is exercised deterministically every run via a bogus soname).  When libpq
// is present the probe reports the library version and the real
// connect/status/error path against a closed local port -- no PostgreSQL
// server required.
//
// Build+run (no extra compiler args: pure-XIOM loader):
//   scripts/port.ps1 -Package xiom.libpq

module libpq_conformance

use xiom.io;
use xiom.convert;
use xiom.test;
use xiom.libpq;

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
  io.println("=== xiom.libpq conformance tests (dynamic loader) ===");
  io.flush_stdout();
  var failed: Int = 0;

  // SKIP-path classification, deterministic on every host (bogus soname).
  let missing = pq_load_named("xiom-absent-libpq-probe-xyz.dll");
  if missing.is_ok {
    failed = failed + report(false, "skip-path: bogus soname unexpectedly loaded");
  } else {
    failed = failed + report(missing.error.kind == PQ_LOAD_ABSENT,
      "skip-path: absent library classified as PQ_LOAD_ABSENT (SKIP)");
  }

  let p = pq_probe_default();
  if p.is_ok {
    let info: PqInfo = p.value;
    failed = failed + report(info.lib_version >= 90000,
      "library: PQlibVersion = " + to_string(info.lib_version));
    failed = failed + report(info.connect_status == CONNECTION_BAD,
      "connect: closed port reported CONNECTION_BAD (status " + to_string(info.connect_status) + ")");
    failed = failed + report(info.connect_error.len() > 0,
      "connect: error text = " + info.connect_error);
  } else {
    if p.error.kind == PQ_LOAD_ABSENT {
      failed = failed + report(true, "probe: SKIP -- libpq not present (" + p.error.message + ")");
    } else {
      failed = failed + report(false, "probe: failed -- " + p.error.message);
    }
  }

  if failed == 0 {
    io.println("xiom.libpq: all tests passed");
  } else {
    io.println("xiom.libpq: tests failed");
  }
  return failed;
}
