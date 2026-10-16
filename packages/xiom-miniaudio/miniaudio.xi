// XIOM -- xiom.miniaudio: miniaudio bindings (vendored single header).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// DESIGN: vendored single-header path. `vendor/miniaudio.h` (0.11.25,
// Unlicense OR MIT-0) is compiled via `src/miniaudio_all.c`
// (MINIAUDIO_IMPLEMENTATION + our probe bridge) through `--c-source`; no
// system audio library at link time, no runtime DLL beyond the OS backends
// miniaudio resolves itself.
//
// G5 confinement: this is the ONE module in the package with `extern "C"`;
// every foreign call is wrapped here.
//
// G2 pin (SPEC.md): upstream tag 0.11.25 header SHA256 + license file SHA256
// + upstream archive provenance.
//
// Coverage (pilot): version, context init + device enumeration, an
// in-memory WAV decode probe (8 kHz mono s16, 16 frames) exercising
// ma_decoder_init_memory/read_pcm_frames with sample spot-checks, and
// (0.3.0) an encoder + file round trip (ma_encoder_init_file/write ->
// ma_decoder_init_file -> sample compare -> temp cleanup).
//
// 0.4.0 (A04 growth): live playback device lifecycle (open/start/mix-pull/
// stop/close with WASAPI-first negotiation, notification-based loss hooks
// and a built-in WAV decoder streamed inside the callback), live ma_engine
// (init/start/stop, memory sound + file sound), device-free node graph +
// engine mixing (attach/detach, group and per-sound volume/pitch), capture
// enumerate + open attempt (typed non-fatal outcomes), and streamed chunked
// decode of WAV/FLAC/MP3 through the decoder data-source pull path.

module xiom.miniaudio

extern "C" {
  fn xma_version(major: *UInt8, minor: *UInt8, rev: *UInt8);
  fn xma_context_probe(playback: *UInt8, capture: *UInt8) -> Int32;
  fn xma_decode_probe(frames: *UInt8, channels: *UInt8, rate: *UInt8, fmt: *UInt8) -> Int32;
  fn xma_encode_roundtrip() -> Int32;
  fn xma_encode_frames() -> Int32;
  fn xma_encode_equal() -> Int32;
  fn xma_encode_removed() -> Int32;
  fn xma_device_lifecycle() -> Int32;
  fn xma_dev_rc() -> Int32;
  fn xma_dev_wasapi_explicit() -> Int32;
  fn xma_dev_backend() -> Int32;
  fn xma_dev_requested_rate() -> Int32;
  fn xma_dev_internal_rate() -> Int32;
  fn xma_dev_channels() -> Int32;
  fn xma_dev_internal_channels() -> Int32;
  fn xma_dev_period_frames() -> Int32;
  fn xma_dev_frames() -> Int32;
  fn xma_dev_callbacks() -> Int32;
  fn xma_dev_decoded_frames() -> Int32;
  fn xma_dev_notify_started() -> Int32;
  fn xma_dev_notify_stopped() -> Int32;
  fn xma_dev_notify_rerouted() -> Int32;
  fn xma_engine_probe() -> Int32;
  fn xma_eng_rc() -> Int32;
  fn xma_eng_backend() -> Int32;
  fn xma_eng_started() -> Int32;
  fn xma_eng_playing() -> Int32;
  fn xma_eng_cursor() -> Int32;
  fn xma_eng_memory_stopped() -> Int32;
  fn xma_eng_file_ok() -> Int32;
  fn xma_eng_frames() -> Int32;
  fn xma_eng_stopped() -> Int32;
  fn xma_graph_probe() -> Int32;
  fn xma_graph_rc() -> Int32;
  fn xma_graph_standalone_read() -> Int32;
  fn xma_graph_standalone_x1000() -> Int32;
  fn xma_graph_standalone_silent() -> Int32;
  fn xma_graph_mix_x1000() -> Int32;
  fn xma_graph_mix_exact() -> Int32;
  fn xma_graph_detach_x1000() -> Int32;
  fn xma_graph_detach_exact() -> Int32;
  fn xma_graph_reattach_x1000() -> Int32;
  fn xma_graph_reattach_exact() -> Int32;
  fn xma_graph_group_volume_x1000() -> Int32;
  fn xma_graph_group_volume_exact() -> Int32;
  fn xma_graph_sound_volume_x1000() -> Int32;
  fn xma_graph_sound_volume_exact() -> Int32;
  fn xma_graph_sound_pitch_x1000() -> Int32;
  fn xma_graph_sound_pitch_exact() -> Int32;
  fn xma_graph_pitch_ratio_x1000() -> Int32;
  fn xma_capture_probe() -> Int32;
  fn xma_cap_devices() -> Int32;
  fn xma_cap_backend() -> Int32;
  fn xma_cap_opened() -> Int32;
  fn xma_cap_rc() -> Int32;
  fn xma_cap_frames() -> Int32;
  fn xma_cap_callbacks() -> Int32;
  fn xma_stream_decode(which: Int32) -> Int32;
  fn xma_stream_rc() -> Int32;
  fn xma_stream_which() -> Int32;
  fn xma_stream_frames() -> Int32;
  fn xma_stream_chunks() -> Int32;
  fn xma_stream_rate() -> Int32;
  fn xma_stream_channels() -> Int32;
  fn xma_stream_format() -> Int32;
  fn xma_stream_peak() -> Int32;
  fn xma_stream_exact() -> Int32;
  fn xma_stream_first() -> Int32;
}

// miniaudio format codes (ma_format).
pub const MA_FORMAT_U8: Int = 1;
pub const MA_FORMAT_S16: Int = 2;
pub const MA_FORMAT_S24: Int = 3;
pub const MA_FORMAT_S32: Int = 4;
pub const MA_FORMAT_F32: Int = 5;

pub type MaContextInfo = {
  playback_count: Int;
  capture_count: Int;
}

pub type MaWavInfo = {
  frames: Int;
  channels: Int;
  sample_rate: Int;
  format: Int;
}

/// 0.3.0 encoder + file round-trip result.
pub type MaEncodeInfo = {
  frames: Int;
  equal: Bool;
  removed: Bool;
}

/// 0.4.0 live playback-device lifecycle (open -> start -> mix-pull -> stop ->
/// close). `internal_*` carry what the backend negotiated with the OS;
/// `notify_*` count the device notifications (the loss hooks).
pub type MaDeviceInfo = {
  backend: Int;
  wasapi_explicit: Bool;
  requested_rate: Int;
  internal_rate: Int;
  channels: Int;
  internal_channels: Int;
  period_frames: Int;
  frames: Int;
  callbacks: Int;
  decoded_frames: Int;
  notify_started: Int;
  notify_stopped: Int;
  notify_rerouted: Int;
}

/// 0.4.0 live playback-engine lifecycle (ma_engine init/start/stop; memory
/// sound play/stop; file sound fire-and-forget). `frames` is the engine
/// frame clock at stop (the mix evidence).
pub type MaEngineInfo = {
  backend: Int;
  started: Bool;
  playing: Bool;
  cursor: Int;
  memory_stopped: Bool;
  file_played: Bool;
  frames: Int;
  stopped: Bool;
}

/// 0.4.0 device-free node-graph + engine mix math (all values are scaled
/// x1000 integers; `*_exact` flags are bit-exact C-side comparisons).
pub type MaGraphInfo = {
  standalone_read: Int;
  standalone_x1000: Int;
  standalone_silent: Bool;
  mix_x1000: Int;
  mix_exact: Bool;
  detach_x1000: Int;
  detach_exact: Bool;
  reattach_x1000: Int;
  reattach_exact: Bool;
  group_volume_x1000: Int;
  group_volume_exact: Bool;
  sound_volume_x1000: Int;
  sound_volume_exact: Bool;
  sound_pitch_x1000: Int;
  sound_pitch_exact: Bool;
  pitch_ratio_x1000: Int;
}

/// 0.4.0 capture enumerate + open attempt. rc != 0 with opened=false is the
/// typed non-fatal "no capture device" outcome (ma_result code).
pub type MaCaptureInfo = {
  devices: Int;
  backend: Int;
  opened: Bool;
  frames: Int;
  callbacks: Int;
  rc: Int;
}

/// 0.4.0 streamed chunked decode through the decoder data-source pull path.
/// which: 1=in-memory WAV, 2=FLAC fixture, 3=MP3 fixture.
pub type MaStreamInfo = {
  which: Int;
  frames: Int;
  chunks: Int;
  rate: Int;
  channels: Int;
  format: Int;
  peak: Int;
  exact: Bool;
  first: Int;
}

fn slot4() -> Vec[UInt8]
  requires: true
{
  var s: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < 4 {
    s.push(0 as UInt8);
    i = i + 1;
  }
  return s;
}

fn read_u32_le(buf: &Vec[UInt8]) -> Int
  requires: buf.len() >= 4
{
  let b0 = buf[0] as Int;
  let b1 = buf[1] as Int;
  let b2 = buf[2] as Int;
  let b3 = buf[3] as Int;
  return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24);
}

/// Packed version: major*10000 + minor*100 + revision (0.11.25 -> 1125).
/// Complexity: O(1).
pub fn ma_version_packed() -> Int
  requires: true
{
  unsafe {
    var sm = slot4();
    var sn = slot4();
    var sr = slot4();
    xma_version(sm.as_mut_ptr(), sn.as_mut_ptr(), sr.as_mut_ptr());
    let major = read_u32_le(&sm);
    let minor = read_u32_le(&sn);
    let rev = read_u32_le(&sr);
    return major * 10000 + minor * 100 + rev;
  }
}

/// Initialize an audio context and enumerate playback/capture devices.
/// Ok(counts) on success; Err carries the miniaudio result code (a headless
/// or serviceless host can legitimately fail -- callers treat that as SKIP).
/// Complexity: O(backends + devices).
pub fn ma_context_probe() -> Result[MaContextInfo, Str]
  requires: true
{
  unsafe {
    var sp = slot4();
    var sc = slot4();
    let rc = xma_context_probe(sp.as_mut_ptr(), sc.as_mut_ptr()) as Int;
    if rc != 0 {
      return Err("miniaudio: ma_context_init/get_devices rc=" + int_to_str(rc));
    }
    return Ok(MaContextInfo{
      playback_count: read_u32_le(&sp),
      capture_count: read_u32_le(&sc),
    });
  }
}

/// Decode a 16-frame 8 kHz mono s16 WAV constructed in the compile unit and
/// verify frames/channels/rate/format plus sample spot-checks.
/// Complexity: O(1).
pub fn ma_decode_probe() -> Result[MaWavInfo, Str]
  requires: true
{
  unsafe {
    var sf = slot4();
    var sc = slot4();
    var sr = slot4();
    var sm = slot4();
    let rc = xma_decode_probe(sf.as_mut_ptr(), sc.as_mut_ptr(), sr.as_mut_ptr(), sm.as_mut_ptr()) as Int;
    if rc != 0 {
      return Err("miniaudio: WAV decode probe mismatch (rc=" + int_to_str(rc) + ")");
    }
    return Ok(MaWavInfo{
      frames: read_u32_le(&sf),
      channels: read_u32_le(&sc),
      sample_rate: read_u32_le(&sr),
      format: read_u32_le(&sm),
    });
  }
}

/// 0.3.0: encode a 64-frame 8 kHz mono s16 tone to a temp WAV with
/// ma_encoder, re-decode it with ma_decoder_init_file, compare every sample
/// and remove the temp file (device-free, deterministic).
/// Complexity: O(1).
pub fn ma_encode_roundtrip() -> Result[MaEncodeInfo, Str]
  requires: true
{
  unsafe {
    let rc = xma_encode_roundtrip() as Int;
    if rc != 0 {
      return Err("miniaudio: encode round trip rc=" + int_to_str(rc));
    }
    return Ok(MaEncodeInfo{
      frames: xma_encode_frames() as Int,
      equal: (xma_encode_equal() as Int) != 0,
      removed: (xma_encode_removed() as Int) != 0,
    });
  }
}

/// 0.4.0: live playback device -- open, start, pull frames through the mix
/// callback (which streams a built-in WAV decoder), stop, close; WASAPI is
/// requested explicitly first with the automatic priority list as fallback.
/// Err carries a step code + the miniaudio result; callers treat an
/// environment block (no device / no pull) as SKIP.
/// Complexity: O(1) driver work + ~100 ms of streamed audio.
pub fn ma_device_lifecycle() -> Result[MaDeviceInfo, Str]
  requires: true
{
  unsafe {
    let rc = xma_device_lifecycle() as Int;
    if rc != 0 {
      return Err("miniaudio: device lifecycle step rc=" + int_to_str(rc)
        + " (ma rc=" + int_to_str(xma_dev_rc() as Int) + ")");
    }
    return Ok(MaDeviceInfo{
      backend: xma_dev_backend() as Int,
      wasapi_explicit: (xma_dev_wasapi_explicit() as Int) != 0,
      requested_rate: xma_dev_requested_rate() as Int,
      internal_rate: xma_dev_internal_rate() as Int,
      channels: xma_dev_channels() as Int,
      internal_channels: xma_dev_internal_channels() as Int,
      period_frames: xma_dev_period_frames() as Int,
      frames: xma_dev_frames() as Int,
      callbacks: xma_dev_callbacks() as Int,
      decoded_frames: xma_dev_decoded_frames() as Int,
      notify_started: xma_dev_notify_started() as Int,
      notify_stopped: xma_dev_notify_stopped() as Int,
      notify_rerouted: xma_dev_notify_rerouted() as Int,
    });
  }
}

/// 0.4.0: live playback engine -- ma_engine init with explicit start, a
/// sound loaded from memory (built-in WAV decoder as the data source,
/// looping) started/stopped, a file sound through ma_engine_play_sound
/// (fire-and-forget), then explicit stop + uninit.
/// Err carries a step code + the miniaudio result (SKIP-style when the
/// environment has no playback device).
/// Complexity: O(1) driver work + ~200 ms of streamed audio.
pub fn ma_engine_probe() -> Result[MaEngineInfo, Str]
  requires: true
{
  unsafe {
    let rc = xma_engine_probe() as Int;
    if rc != 0 {
      return Err("miniaudio: engine probe step rc=" + int_to_str(rc)
        + " (ma rc=" + int_to_str(xma_eng_rc() as Int) + ")");
    }
    return Ok(MaEngineInfo{
      backend: xma_eng_backend() as Int,
      started: (xma_eng_started() as Int) != 0,
      playing: (xma_eng_playing() as Int) != 0,
      cursor: xma_eng_cursor() as Int,
      memory_stopped: (xma_eng_memory_stopped() as Int) != 0,
      file_played: (xma_eng_file_ok() as Int) != 0,
      frames: xma_eng_frames() as Int,
      stopped: (xma_eng_stopped() as Int) != 0,
    });
  }
}

/// 0.4.0: device-free node-graph + engine mixing proof -- standalone node
/// graph attach/detach, exact engine mix math through a sound group and
/// per-sound volumes, sound detach/reattach, and the pitch rate effect.
/// Deterministic (no device); Err only on an internal step failure.
/// Complexity: O(1).
pub fn ma_graph_probe() -> Result[MaGraphInfo, Str]
  requires: true
{
  unsafe {
    let rc = xma_graph_probe() as Int;
    if rc != 0 {
      return Err("miniaudio: graph probe step rc=" + int_to_str(rc));
    }
    return Ok(MaGraphInfo{
      standalone_read: xma_graph_standalone_read() as Int,
      standalone_x1000: xma_graph_standalone_x1000() as Int,
      standalone_silent: (xma_graph_standalone_silent() as Int) != 0,
      mix_x1000: xma_graph_mix_x1000() as Int,
      mix_exact: (xma_graph_mix_exact() as Int) != 0,
      detach_x1000: xma_graph_detach_x1000() as Int,
      detach_exact: (xma_graph_detach_exact() as Int) != 0,
      reattach_x1000: xma_graph_reattach_x1000() as Int,
      reattach_exact: (xma_graph_reattach_exact() as Int) != 0,
      group_volume_x1000: xma_graph_group_volume_x1000() as Int,
      group_volume_exact: (xma_graph_group_volume_exact() as Int) != 0,
      sound_volume_x1000: xma_graph_sound_volume_x1000() as Int,
      sound_volume_exact: (xma_graph_sound_volume_exact() as Int) != 0,
      sound_pitch_x1000: xma_graph_sound_pitch_x1000() as Int,
      sound_pitch_exact: (xma_graph_sound_pitch_exact() as Int) != 0,
      pitch_ratio_x1000: xma_graph_pitch_ratio_x1000() as Int,
    });
  }
}

/// 0.4.0: capture -- enumerate capture devices and attempt to open the
/// default capture endpoint (typed outcomes: opened=false with rc = ma
/// result is a non-fatal "no capture device"; opened=true with frames=0 is
/// "opened but silent"). Err is reserved for unexpected internal failures.
/// Complexity: O(backends + ~50 ms capture).
pub fn ma_capture_probe() -> Result[MaCaptureInfo, Str]
  requires: true
{
  unsafe {
    let rc = xma_capture_probe() as Int;
    if rc == 2 {
      return Ok(MaCaptureInfo{
        devices: xma_cap_devices() as Int,
        backend: xma_cap_backend() as Int,
        opened: false,
        frames: 0,
        callbacks: 0,
        rc: xma_cap_rc() as Int,
      });
    }
    if rc == 3 {
      return Ok(MaCaptureInfo{
        devices: xma_cap_devices() as Int,
        backend: xma_cap_backend() as Int,
        opened: true,
        frames: 0,
        callbacks: xma_cap_callbacks() as Int,
        rc: 0,
      });
    }
    if rc != 0 {
      return Err("miniaudio: capture probe step rc=" + int_to_str(rc)
        + " (ma rc=" + int_to_str(xma_cap_rc() as Int) + ")");
    }
    return Ok(MaCaptureInfo{
      devices: xma_cap_devices() as Int,
      backend: xma_cap_backend() as Int,
      opened: (xma_cap_opened() as Int) != 0,
      frames: xma_cap_frames() as Int,
      callbacks: xma_cap_callbacks() as Int,
      rc: 0,
    });
  }
}

/// 0.4.0: streamed chunked decode of a built-in decoder through the
/// data-source pull path (13-frame reads). which: 1 = in-memory WAV
/// (sample-exact), 2 = FLAC fixture (lossless, sample-exact), 3 = MP3
/// fixture (lossy: check frames/rate/energy).
/// Complexity: O(frames).
pub fn ma_stream_decode(which: Int) -> Result[MaStreamInfo, Str]
  requires: true
{
  unsafe {
    let rc = xma_stream_decode(which as Int32) as Int;
    if rc != 0 {
      return Err("miniaudio: stream decode (which=" + int_to_str(which)
        + ") step rc=" + int_to_str(rc) + " (ma rc=" + int_to_str(xma_stream_rc() as Int) + ")");
    }
    return Ok(MaStreamInfo{
      which: xma_stream_which() as Int,
      frames: xma_stream_frames() as Int,
      chunks: xma_stream_chunks() as Int,
      rate: xma_stream_rate() as Int,
      channels: xma_stream_channels() as Int,
      format: xma_stream_format() as Int,
      peak: xma_stream_peak() as Int,
      exact: (xma_stream_exact() as Int) != 0,
      first: xma_stream_first() as Int,
    });
  }
}

/// miniaudio backend id -> name (ma_backend enum order at 0.11.25).
/// Complexity: O(1).
pub fn ma_backend_name(id: Int) -> Str {
  if id == 0 { return "wasapi"; }
  if id == 1 { return "dsound"; }
  if id == 2 { return "winmm"; }
  if id == 3 { return "coreaudio"; }
  if id == 4 { return "sndio"; }
  if id == 5 { return "audio4"; }
  if id == 6 { return "oss"; }
  if id == 7 { return "pulseaudio"; }
  if id == 8 { return "alsa"; }
  if id == 9 { return "jack"; }
  if id == 10 { return "aaudio"; }
  if id == 11 { return "opensl"; }
  if id == 12 { return "webaudio"; }
  if id == 13 { return "custom"; }
  if id == 14 { return "null"; }
  return "unknown(" + int_to_str(id) + ")";
}

// Local integer-to-string (stdlib convert must not be called inside the
// confined block; same rule as the sqlite/zstd/odbc modules).
fn int_to_str(n: Int) -> Str {
  if n == 0 { return "0"; }
  var num = n;
  var neg = false;
  if num < 0 { neg = true; num = 0 - num; }
  var out = "";
  while num > 0 {
    let d = num % 10;
    var ds = "0";
    if d == 1 { ds = "1"; }
    elif d == 2 { ds = "2"; }
    elif d == 3 { ds = "3"; }
    elif d == 4 { ds = "4"; }
    elif d == 5 { ds = "5"; }
    elif d == 6 { ds = "6"; }
    elif d == 7 { ds = "7"; }
    elif d == 8 { ds = "8"; }
    elif d == 9 { ds = "9"; }
    out = ds + out;
    num = num / 10;
  }
  if neg { return "-" + out; }
  return out;
}
