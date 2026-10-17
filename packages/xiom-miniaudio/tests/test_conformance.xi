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
use xiom.ffi;
use xiom.miniaudio;

// =========================================================================
// 0.5.0 handle battery: render callbacks (env-free top-level fns -- the
// direct-handoff shape). Each writes the two marker bytes the C trampoline
// checks (buf[0]=0x5A, buf[16]=0xA5) and counts its own invocations.
// =========================================================================

var hcb_a_calls: Int = 0;
var hcb_a_frames: Int = 0;
var hcb_b_calls: Int = 0;

fn hcb_render_a(out: *UInt8, frames: Int32) -> Unit {
  hcb_a_calls = hcb_a_calls + 1;
  hcb_a_frames = hcb_a_frames + (frames as Int);
  unsafe {
    ffi.ptr_write_u8(out, 90);
    ffi.ptr_write_u8((out as Int + 16) as *UInt8, 165);
  }
}

fn hcb_render_b(out: *UInt8, frames: Int32) -> Unit {
  hcb_b_calls = hcb_b_calls + 1;
  unsafe {
    ffi.ptr_write_u8(out, 90);
    ffi.ptr_write_u8((out as Int + 16) as *UInt8, 165);
  }
}

// All seven typed BAD_HANDLE paths for a handle value.
fn hbad_all(handle: Int) -> Bool {
  var ok = true;
  let m1 = ma_device_handle_set_render(handle, hcb_render_a);
  if m1.is_ok { ok = false; }
  elif m1.error.kind != MA_HANDLE_ERR_BAD_HANDLE { ok = false; }
  let m2 = ma_device_handle_clear_render(handle);
  if m2.is_ok { ok = false; }
  elif m2.error.kind != MA_HANDLE_ERR_BAD_HANDLE { ok = false; }
  let m3 = ma_device_handle_start(handle);
  if m3.is_ok { ok = false; }
  elif m3.error.kind != MA_HANDLE_ERR_BAD_HANDLE { ok = false; }
  let m4 = ma_device_handle_stop(handle);
  if m4.is_ok { ok = false; }
  elif m4.error.kind != MA_HANDLE_ERR_BAD_HANDLE { ok = false; }
  let m5 = ma_device_handle_wait(handle, 1, 10);
  if m5.is_ok { ok = false; }
  elif m5.error.kind != MA_HANDLE_ERR_BAD_HANDLE { ok = false; }
  let m6 = ma_device_handle_info(handle);
  if m6.is_ok { ok = false; }
  elif m6.error.kind != MA_HANDLE_ERR_BAD_HANDLE { ok = false; }
  let m7 = ma_device_handle_close(handle);
  if m7.is_ok { ok = false; }
  elif m7.error.kind != MA_HANDLE_ERR_BAD_HANDLE { ok = false; }
  return ok;
}

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

  // ========================================================================
  // 0.5.0: long-lived device handles -- null-device battery (deterministic
  // on any host: the null backend always opens, is paced at real time
  // (480-frame periods at 48 kHz -> ~10 ms per render callback) and needs
  // no audio service).
  // ========================================================================

  let hb = ma_device_handle_open_backend(MA_HANDLE_BACKEND_NULL);
  if hb.is_ok {
    let h1 = hb.value;
    failed = failed + report(h1 > 0,
      "handle: null device opened once (handle=" + to_string(h1) + ")");

    let i0 = ma_device_handle_info(h1);
    if i0.is_ok {
      let hi0: MaHandleInfo = i0.value;
      failed = failed + report(hi0.backend == MA_HANDLE_BACKEND_NULL && hi0.rate == 48000
        && hi0.channels == 2 && hi0.period_frames > 0 && !hi0.started && !hi0.render_set,
        "handle: fresh info -- backend=" + ma_backend_name(hi0.backend) + " "
        + to_string(hi0.rate) + " Hz/" + to_string(hi0.channels) + "ch period="
        + to_string(hi0.period_frames) + "f, idle, no render");
    } else {
      failed = failed + report(false, "handle: fresh info -- " + i0.error.message);
    }

    // Register once -> start -> replace -> clear, all while the stream runs.
    let r_set = ma_device_handle_set_render(h1, hcb_render_a);
    let st_start = ma_device_handle_start(h1);
    failed = failed + report(r_set.is_ok && st_start.is_ok,
      "handle: render callback registered + stream started");

    let st_twice = ma_device_handle_start(h1);
    var state_flag = false;
    if !st_twice.is_ok { if st_twice.error.kind == MA_HANDLE_ERR_STATE { state_flag = true; } }
    failed = failed + report(state_flag,
      "handle: start while started -> typed STATE error");

    let w1 = ma_device_handle_wait(h1, 5, 2000);
    let i1 = ma_device_handle_info(h1);
    if w1.is_ok && i1.is_ok {
      let hi1: MaHandleInfo = i1.value;
      failed = failed + report(hi1.started && hi1.starts == 1 && hi1.render_set
        && hi1.callbacks >= 5 && hi1.frames > 0 && hi1.marked >= 1 && hcb_a_calls >= 5
        && hcb_a_frames > 0,
        "handle: stream running -- " + to_string(hi1.callbacks) + " callbacks, "
        + to_string(hi1.frames) + " frames pulled, " + to_string(hi1.marked)
        + " buffers marked by the XIOM render (" + to_string(hcb_a_calls)
        + " XIOM calls, " + to_string(hcb_a_frames) + " frames seen)");
    } else {
      failed = failed + report(false, "handle: stream running -- " + i1.error.message);
    }

    // Replace the render while running: B takes over, A freezes (at most one
    // in-flight callback still observes A).
    let a_at_swap = hcb_a_calls;
    let r_swap = ma_device_handle_set_render(h1, hcb_render_b);
    let w2 = ma_device_handle_wait(h1, a_at_swap + 8, 3000);
    let i2 = ma_device_handle_info(h1);
    var cb_running = 0;
    if r_swap.is_ok && w2.is_ok && i2.is_ok {
      let hi2: MaHandleInfo = i2.value;
      cb_running = hi2.callbacks;
      failed = failed + report(hcb_b_calls >= 5 && hcb_a_calls >= a_at_swap
        && hcb_a_calls <= a_at_swap + 1 && hi2.callbacks >= a_at_swap + 8 && hi2.render_set,
        "handle: render replaced while running -- B took over (" + to_string(hcb_b_calls)
        + " calls), A frozen at " + to_string(hcb_a_calls) + " (was "
        + to_string(a_at_swap) + ")");
    } else {
      failed = failed + report(false, "handle: render replace -- " + i2.error.message);
    }

    // Clear the render while running: the callback path keeps running, the
    // registered render freezes (at most one in-flight).
    let b_at_clear = hcb_b_calls;
    let r_clear = ma_device_handle_clear_render(h1);
    let w3 = ma_device_handle_wait(h1, cb_running + 8, 3000);
    let i3 = ma_device_handle_info(h1);
    var cb_cleared = cb_running;
    if r_clear.is_ok && w3.is_ok && i3.is_ok {
      let hi3: MaHandleInfo = i3.value;
      cb_cleared = hi3.callbacks;
      failed = failed + report(!hi3.render_set && hcb_b_calls <= b_at_clear + 1
        && hi3.callbacks >= cb_running + 8,
        "handle: render cleared while running -- callbacks continue ("
        + to_string(hi3.callbacks) + "), B frozen at " + to_string(hcb_b_calls)
        + " (was " + to_string(b_at_clear) + ")");
    } else {
      failed = failed + report(false, "handle: render clear -- " + i3.error.message);
    }

    // Stop: the stream halts; after a 100 ms drain the counters are frozen
    // and marked == the two renders' call counts exactly.
    let st_stop = ma_device_handle_stop(h1);
    let i4 = ma_device_handle_info(h1);
    var cb_frozen = 0;
    var frozen_ok = false;
    if st_stop.is_ok && i4.is_ok {
      let w4 = ma_device_handle_wait(h1, i4.value.callbacks + 3, 100);   // unreachable: drain
      let i4b = ma_device_handle_info(h1);
      var cb_b = 0;
      if i4b.is_ok { cb_b = i4b.value.callbacks; }
      let w5 = ma_device_handle_wait(h1, cb_b + 3, 100);                 // second drain
      let i4c = ma_device_handle_info(h1);
      if i4b.is_ok && i4c.is_ok {
        let hi4c: MaHandleInfo = i4c.value;
        cb_frozen = hi4c.callbacks;
        let a_final = hcb_a_calls;
        let b_final = hcb_b_calls;
        if !hi4c.started && hi4c.stops == 1 && hi4c.callbacks == cb_b
          && hi4c.marked == a_final + b_final {
          frozen_ok = true;
        }
      }
      failed = failed + report(frozen_ok && w4.is_ok && w5.is_ok,
        "handle: stop halts the stream -- frozen at " + to_string(cb_frozen)
        + " callbacks; marked == XIOM renders");
    } else {
      failed = failed + report(false, "handle: stop -- " + i4.error.message);
    }

    let st_idle = ma_device_handle_stop(h1);
    var idle_flag = false;
    if !st_idle.is_ok { if st_idle.error.kind == MA_HANDLE_ERR_STATE { idle_flag = true; } }
    failed = failed + report(idle_flag,
      "handle: stop while idle -> typed STATE error");

    // Second start/stop cycle over time (no render registered: silence).
    let st2 = ma_device_handle_start(h1);
    let w6 = ma_device_handle_wait(h1, cb_frozen + 5, 2000);
    let st2b = ma_device_handle_stop(h1);
    let i5 = ma_device_handle_info(h1);
    if st2.is_ok && w6.is_ok && st2b.is_ok && i5.is_ok {
      let hi5: MaHandleInfo = i5.value;
      failed = failed + report(hi5.starts == 2 && hi5.stops == 2 && !hi5.started
        && !hi5.render_set && hi5.callbacks >= cb_frozen + 5,
        "handle: second start/stop cycle over time (starts=" + to_string(hi5.starts)
        + " stops=" + to_string(hi5.stops) + ", callbacks=" + to_string(hi5.callbacks) + ")");
    } else {
      failed = failed + report(false, "handle: second cycle -- " + i5.error.message);
    }

    // Re-register, run, then close while running: clean teardown; every op on
    // the closed handle is the typed BAD_HANDLE (double close included).
    let r_re = ma_device_handle_set_render(h1, hcb_render_a);
    let st3 = ma_device_handle_start(h1);
    let w7 = ma_device_handle_wait(h1, cb_frozen + 5, 1000);
    let cl1 = ma_device_handle_close(h1);
    let closed_typed = hbad_all(h1);
    failed = failed + report(r_re.is_ok && st3.is_ok && w7.is_ok && cl1.is_ok && closed_typed,
      "handle: close while running tears down cleanly; closed handle stays typed BAD_HANDLE");
  } else {
    failed = failed + report(false, "handle: null device open failed -- " + hb.error.message);
  }

  // Ops on a handle that was never opened: every function is typed BAD_HANDLE.
  failed = failed + report(hbad_all(999999),
    "handle: all 7 operations on an unknown handle -> typed BAD_HANDLE");

  // Registry stress: 4 live handles max; closing releases the slots.
  let e1 = ma_device_handle_open_backend(MA_HANDLE_BACKEND_NULL);
  let e2 = ma_device_handle_open_backend(MA_HANDLE_BACKEND_NULL);
  let e3 = ma_device_handle_open_backend(MA_HANDLE_BACKEND_NULL);
  let e4 = ma_device_handle_open_backend(MA_HANDLE_BACKEND_NULL);
  let e5 = ma_device_handle_open_backend(MA_HANDLE_BACKEND_NULL);
  var reg_ok = e1.is_ok && e2.is_ok && e3.is_ok && e4.is_ok;
  var exh_ok = false;
  if !e5.is_ok { if e5.error.kind == MA_HANDLE_ERR_EXHAUSTED { exh_ok = true; } }
  failed = failed + report(reg_ok && exh_ok,
    "handle: registry holds 4 live handles; the 5th open -> typed EXHAUSTED");
  var released = false;
  if reg_ok {
    let c1 = ma_device_handle_close(e1.value);
    let c2 = ma_device_handle_close(e2.value);
    let c3 = ma_device_handle_close(e3.value);
    let c4 = ma_device_handle_close(e4.value);
    let e6 = ma_device_handle_open_backend(MA_HANDLE_BACKEND_NULL);
    if c1.is_ok && c2.is_ok && c3.is_ok && c4.is_ok && e6.is_ok {
      let c6 = ma_device_handle_close(e6.value);
      if c6.is_ok { released = true; }
    }
  }
  failed = failed + report(released,
    "handle: closing releases the slots (reopen after 4 closes succeeds)");

  // A bogus backend id: typed NO_CONTEXT with the miniaudio result in rc.
  let bog = ma_device_handle_open_backend(99);
  var bog_ok = false;
  if !bog.is_ok {
    if bog.error.kind == MA_HANDLE_ERR_NO_CONTEXT && bog.error.rc != 0 { bog_ok = true; }
  }
  failed = failed + report(bog_ok,
    "handle: bogus backend 99 -> typed NO_CONTEXT (rc=" + to_string(bog.error.rc) + ")");

  // Auto open (default priority list) and the explicit WASAPI leg: live when
  // the host has audio, SKIP-typed otherwise (the null battery above always
  // runs). Open/info/close once -- no start (the 0.4.0 lifecycle leg owns the
  // live start path).
  let hauto = ma_device_handle_open();
  if hauto.is_ok {
    let ia = ma_device_handle_info(hauto.value);
    var a_name = "?";
    if ia.is_ok { a_name = ma_backend_name(ia.value.backend); }
    let ca = ma_device_handle_close(hauto.value);
    failed = failed + report(ia.is_ok && ca.is_ok,
      "handle: auto open once -> " + a_name + " device (info + close)");
  } elif hauto.error.kind == MA_HANDLE_ERR_NO_CONTEXT || hauto.error.kind == MA_HANDLE_ERR_NO_DEVICE {
    failed = failed + report(true, "handle: auto open SKIP -- " + hauto.error.message);
  } else {
    failed = failed + report(false, "handle: auto open -- " + hauto.error.message);
  }

  let hwas = ma_device_handle_open_backend(MA_HANDLE_BACKEND_WASAPI);
  if hwas.is_ok {
    let iw = ma_device_handle_info(hwas.value);
    var w_ok = false;
    if iw.is_ok { if iw.value.backend == MA_HANDLE_BACKEND_WASAPI { w_ok = true; } }
    let cw = ma_device_handle_close(hwas.value);
    failed = failed + report(w_ok && cw.is_ok,
      "handle: explicit WASAPI open once -> wasapi device (info + close)");
  } elif hwas.error.kind == MA_HANDLE_ERR_NO_CONTEXT || hwas.error.kind == MA_HANDLE_ERR_NO_DEVICE {
    failed = failed + report(true, "handle: explicit WASAPI SKIP -- " + hwas.error.message);
  } else {
    failed = failed + report(false, "handle: explicit WASAPI -- " + hwas.error.message);
  }

  if failed == 0 {
    io.println("xiom.miniaudio: all tests passed");
  } else {
    io.println("xiom.miniaudio: tests failed");
  }
  return failed;
}
