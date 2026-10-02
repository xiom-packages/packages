// XIOM -- xiom.video.raw: raw elementary-stream proof mux/demux
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Proof elementary-stream container for the xiom.video package. Layout
// (little-endian, documented in SPEC.md):
//
//   "XRAW" u8 version(1) u8 track_count u16 reserved(0)
//   track_count * 36-byte track table entries:
//     kind u32, codec u32, scale u32, rate u32, length u32,
//     width u32, height u32, channels u32, sample_rate u32
//   records until EOF:
//     track u32, pts u32, dts u32, duration u32, flags u32 (bit0 key),
//     size u32, payload[size] (opaque)
//
// This is the exact round-trip vehicle: mux -> demux preserves every track
// field and every frame's track/pts/dts/duration/key plus the payload bytes
// (timestamps are container milliseconds, non-negative by construction).
//
// Compiler-v0.62.2 notes: free functions only, typed locals on every Vec
// read, `(b as Int) & 0xFF` everywhere, Ok/Err only in the leaf helpers,
// raw_demux returns the store through a leaf helper (trap 6), every loop is
// bounded and strictly advancing.

module xiom.video.raw

use xiom.video;
use xiom.video.store;

// --------------------------------------------------
//  Result leaf constructors
// --------------------------------------------------

fn _ok_int(v: Int) -> Result[Int, Str] { return Ok(v); }
fn _err_int(m: Str) -> Result[Int, Str] { return Err(m); }
fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], Str] { return Ok(v); }
fn _err_bytes(m: Str) -> Result[Vec[UInt8], Str] { return Err(m); }
fn _ok_stream(v: VideoStream) -> Result[VideoStream, Str] { return Ok(v); }
fn _err_stream(m: Str) -> Result[VideoStream, Str] { return Err(m); }

// --------------------------------------------------
//  Internal byte helpers
// --------------------------------------------------

fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

fn _u32le(data: &Vec[UInt8], pos: Int) -> Int {
  let b0: Int = _byte(data, pos);
  let b1: Int = _byte(data, pos + 1);
  let b2: Int = _byte(data, pos + 2);
  let b3: Int = _byte(data, pos + 3);
  return b0 + b1 * 256 + b2 * 65536 + b3 * 16777216;
}

fn _fcc(data: &Vec[UInt8], pos: Int) -> Int {
  let b0: Int = _byte(data, pos);
  let b1: Int = _byte(data, pos + 1);
  let b2: Int = _byte(data, pos + 2);
  let b3: Int = _byte(data, pos + 3);
  return b0 * 16777216 + b1 * 65536 + b2 * 256 + b3;
}

fn _push_fcc(out: &mut Vec[UInt8], v: Int) {
  var x = ((v % 4294967296) + 4294967296) % 4294967296;
  out.push((x / 16777216) as UInt8);
  out.push(((x / 65536) % 256) as UInt8);
  out.push(((x / 256) % 256) as UInt8);
  out.push((x % 256) as UInt8);
}

fn _push_u32le(out: &mut Vec[UInt8], v: Int) {
  var x = ((v % 4294967296) + 4294967296) % 4294967296;
  out.push((x % 256) as UInt8);
  out.push(((x / 256) % 256) as UInt8);
  out.push(((x / 65536) % 256) as UInt8);
  out.push(((x / 16777216) % 256) as UInt8);
}

fn _push_bytes(out: &mut Vec[UInt8], b: &Vec[UInt8]) {
  var i = 0;
  while i < b.len() {
    let v: UInt8 = b[i];
    out.push(v);
    i = i + 1;
  }
}

// --------------------------------------------------
//  Public API
// --------------------------------------------------

/// Serialise the store into the XRAW proof stream. Errors: "video: too many
/// streams". Complexity O(total payload bytes).
pub fn raw_mux(s: &VideoStream) -> Result[Vec[UInt8], Str] {
  let ntrk = video_track_count(s);
  if ntrk > VIDEO_MAX_TRACKS {
    return _err_bytes("video: too many streams");
  }
  var out = Vec[UInt8].new();
  _push_fcc(&mut out, VIDEO_FCC_XRAW);
  out.push(1 as UInt8);
  out.push(ntrk as UInt8);
  out.push(0 as UInt8);
  out.push(0 as UInt8);
  var t = 0;
  while t < ntrk {
    _push_u32le(&mut out, video_track_kind(s, t));
    _push_u32le(&mut out, video_track_codec(s, t));
    _push_u32le(&mut out, video_track_scale(s, t));
    _push_u32le(&mut out, video_track_rate(s, t));
    _push_u32le(&mut out, video_track_length(s, t));
    _push_u32le(&mut out, video_track_width(s, t));
    _push_u32le(&mut out, video_track_height(s, t));
    _push_u32le(&mut out, video_track_channels(s, t));
    _push_u32le(&mut out, video_track_sample_rate(s, t));
    t = t + 1;
  }
  var f = 0;
  while f < video_frame_count(s) {
    let payload = video_frame_data(s, f);
    _push_u32le(&mut out, video_frame_track(s, f));
    _push_u32le(&mut out, video_frame_pts(s, f));
    _push_u32le(&mut out, video_frame_dts(s, f));
    _push_u32le(&mut out, video_frame_duration(s, f));
    _push_u32le(&mut out, video_frame_is_key(s, f));
    _push_u32le(&mut out, payload.len());
    _push_bytes(&mut out, &payload);
    f = f + 1;
  }
  return _ok_bytes(out);
}

/// Parse an XRAW stream into a fresh VideoStream. Errors (all prefixed
/// "video: "): truncated header (short buffer, short track table, or a
/// trailing partial record), not a raw stream, bad raw version, too many
/// streams, bad track index, plus the track/frame validity errors from the
/// core builders. The container duration is the maximum of the per-track
/// declared durations and the last frame's end. Complexity O(data.len()).
pub fn raw_demux(data: &Vec[UInt8]) -> Result[VideoStream, Str] {
  if data.len() < 8 {
    return _err_stream("video: truncated header");
  }
  if _fcc(data, 0) != VIDEO_FCC_XRAW {
    return _err_stream("video: not a raw stream");
  }
  let version: Int = _byte(data, 4);
  if version != 1 {
    return _err_stream("video: bad raw version");
  }
  let ntrk: Int = _byte(data, 5);
  if ntrk > VIDEO_MAX_TRACKS {
    return _err_stream("video: too many streams");
  }
  let table_end = 8 + ntrk * 36;
  if table_end > data.len() {
    return _err_stream("video: truncated header");
  }
  var s = video_stream_new();
  video_set_format(&mut s, VIDEO_FMT_RAW);
  var p = 8;
  var t = 0;
  while t < ntrk {
    let kind = _u32le(data, p);
    let codec = _u32le(data, p + 4);
    let scale = _u32le(data, p + 8);
    let rate = _u32le(data, p + 12);
    let length = _u32le(data, p + 16);
    let w = _u32le(data, p + 20);
    let h = _u32le(data, p + 24);
    let ch = _u32le(data, p + 28);
    let sr = _u32le(data, p + 32);
    let r = video_add_track(&mut s, kind, codec, scale, rate, length, w, h, ch, sr);
    if !r.is_ok { return _err_stream(r.error); }
    p = p + 36;
    t = t + 1;
  }
  while p + 24 <= data.len() {
    let track = _u32le(data, p);
    let pts = _u32le(data, p + 4);
    let dts = _u32le(data, p + 8);
    let dur = _u32le(data, p + 12);
    let flags = _u32le(data, p + 16);
    let size = _u32le(data, p + 20);
    let dstart = p + 24;
    let dend = dstart + size;
    if dend > data.len() {
      return _err_stream("video: truncated record");
    }
    if track >= ntrk {
      return _err_stream("video: bad track index");
    }
    let r = video_add_frame_span(&mut s, track, pts, dts, dur, flags, 0, data, dstart, size);
    if !r.is_ok { return _err_stream(r.error); }
    p = dend;
  }
  if p != data.len() {
    return _err_stream("video: truncated record");
  }
  var dmax = 0;
  var q = 0;
  while q < video_track_count(&s) {
    let dm = video_track_duration_ms(&s, q);
    if dm > dmax { dmax = dm; }
    q = q + 1;
  }
  if video_frame_count(&s) > 0 {
    let last = video_frame_count(&s) - 1;
    let end_ms = video_frame_pts(&s, last) + video_frame_duration(&s, last);
    if end_ms > dmax { dmax = end_ms; }
  }
  video_set_duration_ms(&mut s, dmax);
  return _ok_stream(s);
}
