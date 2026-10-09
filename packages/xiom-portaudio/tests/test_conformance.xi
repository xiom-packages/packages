// xiom.portaudio conformance suite -- dynamic-loader path.
//
// CI WITHOUT PortAudio stays green: absent library -> SKIP (SKIP path
// exercised deterministically every run via a bogus soname).  When
// `portaudio_x64.dll` is present the probe reports version, device count and
// default device names.
//
// Build+run (no extra compiler args: pure-XIOM loader):
//   scripts/port.ps1 -Package xiom.portaudio

module portaudio_conformance

use xiom.io;
use xiom.convert;
use xiom.test;
use xiom.portaudio;

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
  io.println("=== xiom.portaudio conformance tests (dynamic loader) ===");
  io.flush_stdout();
  var failed: Int = 0;

  // SKIP-path classification, deterministic on every host (bogus soname).
  let missing = pa_load_named("xiom-absent-portaudio-probe-xyz.dll");
  if missing.is_ok {
    failed = failed + report(false, "skip-path: bogus soname unexpectedly loaded");
  } else {
    failed = failed + report(missing.error.kind == PA_LOAD_ABSENT,
      "skip-path: absent library classified as PA_LOAD_ABSENT (SKIP)");
  }

  let p = pa_probe_default();
  if p.is_ok {
    let info: PaInfo = p.value;
    failed = failed + report(info.version_text.len() > 0,
      "version: " + info.version_text + " (int " + to_string(info.version) + ")");
    failed = failed + report(info.device_count >= 0,
      "devices: count = " + to_string(info.device_count));
    if info.default_output >= 0 {
      failed = failed + report(info.default_output_name.len() > 0,
        "default output: " + info.default_output_name);
    } else {
      failed = failed + report(true, "default output: none (index -1)");
    }
    if info.default_input >= 0 {
      failed = failed + report(info.default_input_name.len() > 0,
        "default input: " + info.default_input_name);
    } else {
      failed = failed + report(true, "default input: none (index -1)");
    }
  } else {
    if p.error.kind == PA_LOAD_ABSENT {
      failed = failed + report(true, "probe: SKIP -- PortAudio not present (" + p.error.message + ")");
    } else if p.error.kind == PA_PROBE_FAILED {
      failed = failed + report(true, "probe: SKIP -- initialize failed (" + p.error.message + ")");
    } else {
      failed = failed + report(false, "probe: ABI failure -- " + p.error.message);
    }
  }

  if failed == 0 {
    io.println("xiom.portaudio: all tests passed");
  } else {
    io.println("xiom.portaudio: tests failed");
  }
  return failed;
}
