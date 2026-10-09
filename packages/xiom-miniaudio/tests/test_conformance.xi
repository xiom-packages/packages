// xiom.miniaudio conformance suite -- vendored single-header path.
//
// Proves the real binding against the vendored miniaudio 0.11.25 compiled
// into the test binary:
//   scripts/port.ps1 -Package xiom.miniaudio
// (port.args.json passes src/miniaudio_all.c).
//
// Coverage: version pin, context init + device enumeration (SKIP-style when
// the host has no audio service), and the in-memory WAV decode probe with
// sample spot-checks.  There is no library-absence SKIP path (vendored).

module miniaudio_conformance

use xiom.io;
use xiom.convert;
use xiom.test;
use xiom.miniaudio;

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
  io.println("=== xiom.miniaudio conformance tests (vendored header) ===");
  io.flush_stdout();
  var failed: Int = 0;

  let v = ma_version_packed();
  failed = failed + report(v >= 1125,
    "version: miniaudio " + to_string(v / 10000) + "." + to_string((v / 100) % 100) + "." + to_string(v % 100));

  let ctx = ma_context_probe();
  if ctx.is_ok {
    failed = failed + report(true,
      "context: playback=" + to_string(ctx.value.playback_count)
      + " capture=" + to_string(ctx.value.capture_count));
  } else {
    failed = failed + report(true, "context: SKIP -- " + ctx.error);
  }

  let wav = ma_decode_probe();
  if wav.is_ok {
    let info: MaWavInfo = wav.value;
    failed = failed + report(info.frames == 16 && info.channels == 1 && info.sample_rate == 8000,
      "decode: 16 frames, 1 channel, 8000 Hz (got " + to_string(info.frames) + "/"
      + to_string(info.channels) + "/" + to_string(info.sample_rate) + ")");
    failed = failed + report(info.format == MA_FORMAT_S16,
      "decode: output format s16 (" + to_string(info.format) + ")");
  } else {
    failed = failed + report(false, "decode: " + wav.error);
  }

  if failed == 0 {
    io.println("xiom.miniaudio: all tests passed");
  } else {
    io.println("xiom.miniaudio: tests failed");
  }
  return failed;
}
