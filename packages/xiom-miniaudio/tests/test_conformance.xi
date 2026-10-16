// xiom.miniaudio conformance suite -- vendored single-header path.
//
// Proves the real binding against the vendored miniaudio 0.11.25 compiled
// into the test binary:
//   scripts/port.ps1 -Package xiom.miniaudio
// (port.args.json passes src/miniaudio_all.c).
//
// Coverage: version pin, context init + device enumeration (SKIP-style when
// the host has no audio service), in-memory WAV decode with sample spot
// checks, the encoder + file round trip, and the 0.4.0 A04 growth: live
// playback-device lifecycle (open/start/mix-pull/stop/close + notifications),
// live playback engine (memory + file sounds), device-free node graph + mix
// math (group/per-sound volume+pitch, attach/detach), capture enumerate +
// open attempt (typed non-fatal outcomes) and streamed chunked WAV/FLAC/MP3
// decode.  There is no library-absence SKIP path (vendored); the audio
// device legs degrade to typed SKIP-style checks when the environment
// blocks audio, while still proving the call paths.

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

fn b2s(b: Bool) -> Str {
  if b { return "true"; }
  return "false";
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

  // 0.3.0: encoder + file round trip (device-free).
  let enc = ma_encode_roundtrip();
  if enc.is_ok {
    failed = failed + report(enc.value.frames == 64 && enc.value.equal,
      "encode: 64-frame s16 WAV round trip sample-exact (frames="
        + to_string(enc.value.frames) + " equal=" + b2s(enc.value.equal) + ")");
    failed = failed + report(enc.value.removed,
      "encode: temp file removed (" + b2s(enc.value.removed) + ")");
  } else {
    failed = failed + report(false, "encode: " + enc.error);
  }

  // 0.4.0: live playback-device lifecycle (SKIP-style when audio is blocked).
  let dev = ma_device_lifecycle();
  if dev.is_ok {
    let d: MaDeviceInfo = dev.value;
    failed = failed + report(d.wasapi_explicit && d.backend == 0,
      "device: WASAPI negotiated explicitly (backend=" + ma_backend_name(d.backend) + ")");
    failed = failed + report(d.internal_rate > 0 && d.internal_channels > 0 && d.period_frames > 0,
      "device: requested=" + to_string(d.requested_rate) + " internal=" + to_string(d.internal_rate)
      + " ch=" + to_string(d.internal_channels) + " period=" + to_string(d.period_frames) + "f");
    failed = failed + report(d.frames > 0 && d.callbacks > 0,
      "device: mix-pull " + to_string(d.callbacks) + " callbacks, " + to_string(d.frames) + " frames pulled");
    failed = failed + report(d.decoded_frames > 0,
      "device: built-in WAV decoder streamed inside the live callback ("
      + to_string(d.decoded_frames) + " frames)");
    failed = failed + report(d.notify_started >= 1 && d.notify_stopped >= 1,
      "device: notifications started=" + to_string(d.notify_started)
      + " stopped=" + to_string(d.notify_stopped) + " rerouted=" + to_string(d.notify_rerouted)
      + " (loss hooks wired)");
  } else {
    failed = failed + report(true, "device: SKIP -- " + dev.error);
  }

  // 0.4.0: live playback engine (SKIP-style when audio is blocked).
  let eng = ma_engine_probe();
  if eng.is_ok {
    let e: MaEngineInfo = eng.value;
    failed = failed + report(e.started && e.playing && e.memory_stopped && e.stopped,
      "engine: init/start/play/stop lifecycle (backend=" + ma_backend_name(e.backend)
      + " started=" + b2s(e.started) + " playing=" + b2s(e.playing)
      + " stopped=" + b2s(e.memory_stopped) + ")");
    failed = failed + report(e.cursor > 0,
      "engine: memory sound played (cursor=" + to_string(e.cursor) + " frames, clock="
      + to_string(e.frames) + ")");
    failed = failed + report(e.file_played,
      "engine: file sound accepted fire-and-forget (" + b2s(e.file_played) + ")");
  } else {
    failed = failed + report(true, "engine: SKIP -- " + eng.error);
  }

  // 0.4.0: node graph + engine mix math (device-free, deterministic).
  let gr = ma_graph_probe();
  if gr.is_ok {
    let g: MaGraphInfo = gr.value;
    failed = failed + report(g.standalone_read == 32 && g.standalone_x1000 == 250,
      "graph: standalone node graph attach reads the 0.25 const buffer (read="
      + to_string(g.standalone_read) + " value=" + to_string(g.standalone_x1000) + "/1000)");
    failed = failed + report(g.standalone_silent,
      "graph: standalone node graph detach -> silence (" + b2s(g.standalone_silent) + ")");
    failed = failed + report(g.mix_exact && g.mix_x1000 == 375,
      "graph: mix A(0.5 x group 0.5) + B(0.5 x 0.25) = 0.375 exact ("
      + to_string(g.mix_x1000) + "/1000)");
    failed = failed + report(g.detach_exact && g.detach_x1000 == 250,
      "graph: sound detach removes B from the mix -> 0.25 exact (" + to_string(g.detach_x1000) + "/1000)");
    failed = failed + report(g.reattach_exact && g.reattach_x1000 == 375,
      "graph: sound reattach restores the mix -> 0.375 exact (" + to_string(g.reattach_x1000) + "/1000)");
    failed = failed + report(g.group_volume_exact && g.group_volume_x1000 == 500,
      "graph: sound group volume get=0.5 (" + to_string(g.group_volume_x1000) + "/1000)");
    failed = failed + report(g.sound_volume_exact && g.sound_volume_x1000 == 250,
      "graph: sound volume get=0.25 (" + to_string(g.sound_volume_x1000) + "/1000)");
    failed = failed + report(g.sound_pitch_exact && g.sound_pitch_x1000 == 1500,
      "graph: sound pitch get=1.5 (" + to_string(g.sound_pitch_x1000) + "/1000)");
    let pitch_ok = g.pitch_ratio_x1000 >= 1800 && g.pitch_ratio_x1000 <= 2200;
    failed = failed + report(pitch_ok,
      "graph: pitch 2.0 doubles the cursor rate (" + to_string(g.pitch_ratio_x1000) + "/1000)");
  } else {
    failed = failed + report(false, "graph: " + gr.error);
  }

  // 0.4.0: capture enumerate + open attempt (typed non-fatal outcomes).
  let cap = ma_capture_probe();
  if cap.is_ok {
    let c: MaCaptureInfo = cap.value;
    if c.opened && c.frames > 0 {
      failed = failed + report(true,
        "capture: opened + " + to_string(c.frames) + " frames (" + to_string(c.callbacks)
        + " callbacks, devices=" + to_string(c.devices) + ")");
    } elif !c.opened {
      failed = failed + report(true,
        "capture: SKIP -- no capture device (devices=" + to_string(c.devices)
        + " rc=" + to_string(c.rc) + ")");
    } else {
      failed = failed + report(true,
        "capture: SKIP -- opened but no frames delivered (devices=" + to_string(c.devices) + ")");
    }
  } else {
    failed = failed + report(false, "capture: " + cap.error);
  }

  // 0.4.0: streamed chunked decode through the data-source pull path.
  let s1 = ma_stream_decode(1);
  if s1.is_ok {
    failed = failed + report(s1.value.frames == 16 && s1.value.exact && s1.value.chunks >= 2,
      "stream-wav: 16 frames sample-exact in " + to_string(s1.value.chunks) + " chunks");
  } else {
    failed = failed + report(false, "stream-wav: " + s1.error);
  }

  let s2 = ma_stream_decode(2);
  if s2.is_ok {
    failed = failed + report(s2.value.frames == 64 && s2.value.exact && s2.value.chunks >= 4,
      "stream-flac: 64 frames sample-exact in " + to_string(s2.value.chunks)
      + " chunks (" + to_string(s2.value.rate) + " Hz/" + to_string(s2.value.channels) + "ch)");
  } else {
    failed = failed + report(false, "stream-flac: " + s2.error);
  }

  let s3 = ma_stream_decode(3);
  if s3.is_ok {
    let ok3 = s3.value.rate == 8000 && s3.value.channels == 1
      && s3.value.frames >= 64 && s3.value.peak > 8000 && s3.value.peak < 26000;
    failed = failed + report(ok3,
      "stream-mp3: " + to_string(s3.value.frames) + " frames @ " + to_string(s3.value.rate)
      + " Hz/" + to_string(s3.value.channels) + "ch peak=" + to_string(s3.value.peak));
  } else {
    failed = failed + report(false, "stream-mp3: " + s3.error);
  }

  if failed == 0 {
    io.println("xiom.miniaudio: all tests passed");
  } else {
    io.println("xiom.miniaudio: tests failed");
  }
  return failed;
}
