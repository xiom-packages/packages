// xiom.odbc conformance suite -- dynamic-loader path.
//
// odbc32.dll is a Windows system component (always present), so the probe
// runs for real here; the SKIP path is exercised deterministically every run
// via a bogus soname.  There is no connection stage (driver-manager info is
// connection-free).
//
// Build+run (no extra compiler args: pure-XIOM loader):
//   scripts/port.ps1 -Package xiom.odbc

module odbc_conformance

use xiom.io;
use xiom.convert;
use xiom.test;
use xiom.odbc;

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
  io.println("=== xiom.odbc conformance tests (dynamic loader) ===");
  io.flush_stdout();
  var failed: Int = 0;

  // SKIP-path classification, deterministic on every host (bogus soname).
  let missing = odbc_probe_named("xiom-absent-odbc-probe-xyz.dll");
  if missing.is_ok {
    failed = failed + report(false, "skip-path: bogus soname unexpectedly produced driver info");
  } else {
    failed = failed + report(missing.error.kind == ODBC_LOAD_ABSENT,
      "skip-path: absent manager classified as ODBC_LOAD_ABSENT (SKIP)");
  }

  let p = odbc_probe_default();
  if p.is_ok {
    let info: OdbcInfo = p.value;
    failed = failed + report(info.version.len() > 0,
      "manager: ODBC version = " + info.version);
    failed = failed + report(info.driver_count >= 1,
      "drivers: count = " + to_string(info.driver_count));
    failed = failed + report(info.driver_head.len() > 0,
      "drivers: head = " + info.driver_head);
    failed = failed + report(info.dsn_count >= 0,
      "dsn: configured user/system DSN count = " + to_string(info.dsn_count));
  } else {
    if p.error.kind == ODBC_LOAD_ABSENT {
      failed = failed + report(true, "probe: SKIP -- ODBC driver manager not present (" + p.error.message + ")");
    } else {
      failed = failed + report(false, "probe: failed -- " + p.error.message);
    }
  }

  if failed == 0 {
    io.println("xiom.odbc: all tests passed");
  } else {
    io.println("xiom.odbc: tests failed");
  }
  return failed;
}
