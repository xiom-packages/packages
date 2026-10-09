// xiom.ffmpeg conformance suite -- dynamic-loader path (system FFmpeg DLLs).
//
// CI WITHOUT FFmpeg stays green: no candidate generation resolves -> SKIP
// (the SKIP classification is exercised deterministically every run via
// bogus sonames).  With an LGPL shared build on PATH the probe reports
// av_version_info plus the four library versions and the build's license
// evidence -- 4 checks.
//
// Build+run (no extra compiler args: pure-XIOM loader):
//   scripts/port.ps1 -Package xiom.ffmpeg

module ffmpeg_conformance

use xiom.io;
use xiom.test;
use xiom.ffmpeg;

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
  io.println("=== xiom.ffmpeg conformance tests (dynamic loader) ===");
  io.flush_stdout();
  var failed: Int = 0;

  // SKIP-path classification, deterministic on every host (bogus sonames).
  let missing = ffmpeg_load_named(
    "xiom-absent-avcodec-probe-xyz.dll",
    "xiom-absent-avformat-probe-xyz.dll",
    "xiom-absent-avutil-probe-xyz.dll",
    "xiom-absent-swresample-probe-xyz.dll");
  if missing.is_ok {
    failed = failed + report(false, "skip-path: bogus sonames unexpectedly loaded");
  } else {
    failed = failed + report(missing.error.kind == FFMPEG_LOAD_ABSENT,
      "skip-path: absent libraries classified as FFMPEG_LOAD_ABSENT (SKIP)");
  }

  let p = ffmpeg_probe_default();
  if p.is_ok {
    let info: FfmpegInfo = p.value;
    failed = failed + report(info.version_info.len() > 0,
      "version: FFmpeg " + info.version_info);
    failed = failed + report(
      info.avcodec_version > 0 && info.avformat_version > 0
        && info.avutil_version > 0 && info.swresample_version > 0,
      "set: avcodec " + ffmpeg_version_str(info.avcodec_version)
        + " / avformat " + ffmpeg_version_str(info.avformat_version)
        + " / avutil " + ffmpeg_version_str(info.avutil_version)
        + " / swresample " + ffmpeg_version_str(info.swresample_version));
    failed = failed + report(ffmpeg_lgpl_build(&info) != info.gpl_enabled,
      "license: " + info.license + " (gpl-configured " + b2s(info.gpl_enabled) + ")");
  } else {
    if p.error.kind == FFMPEG_LOAD_ABSENT {
      failed = failed + report(true, "probe: SKIP -- no FFmpeg shared-library generation present (" + p.error.message + ")");
    } else {
      failed = failed + report(false, "probe: failed -- " + p.error.message);
    }
  }

  if failed == 0 {
    io.println("xiom.ffmpeg: all tests passed");
  } else {
    io.println("xiom.ffmpeg: tests failed");
  }
  return failed;
}
