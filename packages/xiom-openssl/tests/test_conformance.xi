// xiom.openssl conformance suite -- dynamic-loader path (system libcrypto).
//
// CI WITHOUT OpenSSL stays green: no candidate soname -> SKIP (the SKIP path
// is exercised deterministically every run via a bogus soname).  When a
// libcrypto build is available the probe reports the version and proves real
// functionality: SHA-256("abc") against the published digest plus a
// RAND_bytes liveness call.
//
// Build+run (no extra compiler args: pure-XIOM loader):
//   scripts/port.ps1 -Package xiom.openssl

module openssl_conformance

use xiom.io;
use xiom.convert;
use xiom.test;
use xiom.openssl;

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

fn b2s(b: Bool) -> Str {
  if b { return "true"; }
  return "false";
}

fn main() -> Int {
  io.println("=== xiom.openssl conformance tests (dynamic loader) ===");
  io.flush_stdout();
  var failed: Int = 0;

  // SKIP-path classification, deterministic on every host (bogus soname).
  let missing = ossl_load_named("xiom-absent-libcrypto-probe-xyz.dll");
  if missing.is_ok {
    failed = failed + report(false, "skip-path: bogus soname unexpectedly loaded");
  } else {
    failed = failed + report(missing.error.kind == OSSL_LOAD_ABSENT,
      "skip-path: absent library classified as OSSL_LOAD_ABSENT (SKIP)");
  }

  let p = ossl_probe_default();
  if p.is_ok {
    let info: OsslInfo = p.value;
    failed = failed + report(info.version.len() > 0,
      "version: " + info.version + " (num " + to_string(info.version_num) + ")");
    failed = failed + report(info.sha256_ok,
      "sha256: SHA-256(\"abc\") matches the published digest");
    failed = failed + report(info.rand_ok,
      "rand: RAND_bytes(16) succeeded");
  } else {
    if p.error.kind == OSSL_LOAD_ABSENT {
      failed = failed + report(true, "probe: SKIP -- no libcrypto candidate present (" + p.error.message + ")");
    } else {
      failed = failed + report(false, "probe: failed -- " + p.error.message);
    }
  }

  if failed == 0 {
    io.println("xiom.openssl: all tests passed");
  } else {
    io.println("xiom.openssl: tests failed");
  }
  return failed;
}
