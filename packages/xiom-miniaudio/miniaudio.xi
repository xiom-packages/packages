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
// Coverage (pilot): version, context init + device enumeration, and an
// in-memory WAV decode probe (8 kHz mono s16, 16 frames) exercising
// ma_decoder_init_memory/read_pcm_frames with sample spot-checks.  Playback
// engines, mixing, capture and file I/O are Phase 2 (ROADMAP.md).

module xiom.miniaudio

extern "C" {
  fn xma_version(major: *UInt8, minor: *UInt8, rev: *UInt8);
  fn xma_context_probe(playback: *UInt8, capture: *UInt8) -> Int32;
  fn xma_decode_probe(frames: *UInt8, channels: *UInt8, rate: *UInt8, fmt: *UInt8) -> Int32;
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
