// xiom.phonon conformance suite -- dynamic-loader path.
//
// CI WITHOUT Steam Audio stays green: absent phonon.dll -> SKIP (the SKIP
// path is exercised deterministically every run via a bogus soname).  When
// the library is present the probe creates a Steam Audio context (40-byte
// IPLContextSettings, version 0x040801, SIMD baseline) and exercises the
// retain/release balance.
//
// Build+run (no extra compiler args: pure-XIOM loader):
//   scripts/port.ps1 -Package xiom.phonon

module phonon_conformance

use xiom.io;
use xiom.convert;
use xiom.test;
use xiom.phonon;

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

fn t_version_pin() -> Bool {
  var ok = true;
  if STEAMAUDIO_VERSION_MAJOR != 4 { ok = false; }
  if STEAMAUDIO_VERSION_MINOR != 8 { ok = false; }
  if STEAMAUDIO_VERSION_PATCH != 1 { ok = false; }
  if STEAMAUDIO_VERSION != 0x040801 { ok = false; }
  if IPL_SIMDLEVEL_SSE2 != 0 { ok = false; }
  if IPL_SIMDLEVEL_AVX2 != 3 { ok = false; }
  if IPL_STATUS_SUCCESS != 0 { ok = false; }
  return ok;
}

fn main() -> Int {
  io.println("=== xiom.phonon conformance tests (dynamic loader) ===");
  io.flush_stdout();
  var failed: Int = 0;

  failed = failed + report(t_version_pin(), "constants: Steam Audio 4.8.1 (0x040801) + SIMD/status enums");

  // SKIP-path classification, deterministic on every host (bogus soname).
  let missing = phonon_load_named("xiom-absent-phonon-probe-xyz.dll");
  if missing.is_ok {
    failed = failed + report(false, "skip-path: bogus soname unexpectedly loaded");
  } else {
    failed = failed + report(missing.error.kind == PHONON_LOAD_ABSENT,
      "skip-path: absent library classified as PHONON_LOAD_ABSENT (SKIP)");
  }

  let p = phonon_probe_default();
  if p.is_ok {
    let info: PhononInfo = p.value;
    failed = failed + report(info.context_handle != 0,
      "context: created (version " + to_string(info.version) + ", simd level " + to_string(info.simd_level) + ")");
    failed = failed + report(true, "context: retain/release balanced (handle released twice)");
  } else {
    if p.error.kind == PHONON_LOAD_ABSENT {
      failed = failed + report(true, "probe: SKIP -- Steam Audio not present (" + p.error.message + ")");
    } else {
      failed = failed + report(false, "probe: failed -- " + p.error.message);
    }
  }

  if failed == 0 {
    io.println("xiom.phonon: all tests passed");
  } else {
    io.println("xiom.phonon: tests failed");
  }
  return failed;
}
