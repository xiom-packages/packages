// XIOM -- xiom.video: core video container model, sniffing and timebase math
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Format-agnostic container interface for the xiom.video package. This core
// module owns:
//   * the VideoStream record -- the flat, format-agnostic demuxed store.
//     Tracks and frames live in parallel integer vectors (no Vec[StructType],
//     trap 10) plus one opaque payload blob. The record definition and its
//     guarded accessors/builders live in xiom.video.store (src/store.xi);
//     this module owns the type itself so every other module can name it.
//   * the VideoFrame record and the VideoTimebase record with integer-only
//     rescaling (no Vec[Float64], trap 9; division rounds half away from
//     zero and is correct for negative numerators, trap 18).
//   * magic sniffing for AVI (RIFF+AVI), Matroska/WebM (EBML), MP4 (ftyp),
//     Ogg (OggS) and this package's raw proof stream (XRAW).
//   * FourCC helpers with printable-ASCII validation before any Str is built
//     (trap 15: no NUL, no invalid bytes ever reach sb_to_str).
//
// Companion modules: xiom.video.store (src/store.xi), xiom.video.avi
// (src/avi.xi), xiom.video.raw (src/raw.xi) and xiom.video.container
// (src/container.xi, the format dispatch). This module has no dependency on
// them.
//
// Compiler-v0.62.2 notes: free functions only, typed locals on every Vec
// read, `(b as Int) & 0xFF` on every byte read, Ok/Err construction only in
// the leaf helpers, bounded loops only.

module xiom.video

use xiom.string.builder;

// --------------------------------------------------
//  Formats (video_sniff result)
// --------------------------------------------------

/// Unknown or unrecognised container.
pub const VIDEO_FMT_UNKNOWN: Int = 0;
/// RIFF/AVI container ("RIFF" + "AVI ").
pub const VIDEO_FMT_AVI: Int = 1;
/// Matroska/WebM (EBML signature 0x1A45DFA3).
pub const VIDEO_FMT_MKV: Int = 2;
/// ISO base media / MP4 ("ftyp" at offset 4).
pub const VIDEO_FMT_MP4: Int = 3;
/// Ogg ("OggS").
pub const VIDEO_FMT_OGG: Int = 4;
/// This package's raw elementary-stream proof format ("XRAW").
pub const VIDEO_FMT_RAW: Int = 5;

/// Track kind: video.
pub const VIDEO_KIND_VIDEO: Int = 1;
/// Track kind: audio.
pub const VIDEO_KIND_AUDIO: Int = 2;
/// Track kind: other (subtitle, text, unknown handler).
pub const VIDEO_KIND_OTHER: Int = 3;

/// Container timebase numerator: 1/1000 second (milliseconds).
pub const VIDEO_TIME_SCALE_NUM: Int = 1;
/// Container timebase denominator.
pub const VIDEO_TIME_SCALE_DEN: Int = 1000;

/// Maximum number of tracks a VideoStream can hold.
pub const VIDEO_MAX_TRACKS: Int = 100;

/// No index was found in the container.
pub const VIDEO_INDEX_NONE: Int = -1;
/// An index was found but does not match the parsed chunks.
pub const VIDEO_INDEX_BAD: Int = 0;
/// An index was found and every entry matched a parsed chunk.
pub const VIDEO_INDEX_OK: Int = 1;

/// AVI idx1 flag bit: the entry's chunk is a keyframe.
pub const VIDEO_AVI_KEYFRAME: Int = 0x10;
/// AVI avih flag bit: the file carries an idx1 index.
pub const VIDEO_AVI_HASINDEX: Int = 0x10;

// Packed FourCC values ('A' = 0x41, ...; big-endian).
/// "RIFF".
pub const VIDEO_FCC_RIFF: Int = 0x52494646;
/// "AVI ".
pub const VIDEO_FCC_AVI: Int = 0x41564920;
/// "LIST".
pub const VIDEO_FCC_LIST: Int = 0x4C495354;
/// "hdrl".
pub const VIDEO_FCC_HDRL: Int = 0x6864726C;
/// "avih".
pub const VIDEO_FCC_AVIH: Int = 0x61766968;
/// "strl".
pub const VIDEO_FCC_STRL: Int = 0x7374726C;
/// "strh".
pub const VIDEO_FCC_STRH: Int = 0x73747268;
/// "strf".
pub const VIDEO_FCC_STRF: Int = 0x73747266;
/// "movi".
pub const VIDEO_FCC_MOVI: Int = 0x6D6F7669;
/// "idx1".
pub const VIDEO_FCC_IDX1: Int = 0x69647831;
/// "vids" stream handler.
pub const VIDEO_FCC_VIDS: Int = 0x76696473;
/// "auds" stream handler.
pub const VIDEO_FCC_AUDS: Int = 0x61756473;
/// "txts" stream handler.
pub const VIDEO_FCC_TXTS: Int = 0x74787473;
/// "XRAW" raw stream magic.
pub const VIDEO_FCC_XRAW: Int = 0x58524157;
/// "OggS".
pub const VIDEO_FCC_OGGS: Int = 0x4F676753;
/// "ftyp".
pub const VIDEO_FCC_FTYP: Int = 0x66747970;

// --------------------------------------------------
//  Records
// --------------------------------------------------

/// A timebase: one tick is `num / den` seconds (both must be positive).
pub type VideoTimebase = {
  num: Int;
  den: Int;
}

/// Decoded frame model metadata (payload bytes stay in the VideoStream blob).
pub type VideoFrame = {
  track: Int;
  pts: Int;
  dts: Int;
  duration: Int;
  keyframe: Int;
}

/// Flat, format-agnostic demuxed container store.
///
/// Header fields (defaults for a fresh store, see video_stream_new in
/// xiom.video.store): `format` VIDEO_FMT_UNKNOWN, `width`/`height` 0,
/// `duration_units` 0 (container milliseconds), `index_entries` 0,
/// `index_ok` VIDEO_INDEX_NONE, `flags` 0.
///
/// Tracks are parallel vectors, one element per track (never drift; the
/// accessors use the minimum length): `trk_kind` (VIDEO_KIND_*), `trk_codec`
/// (packed FourCC or format tag, opaque), `trk_scale`/`trk_rate` (one tick
/// is scale/rate seconds), `trk_length` (declared length in ticks),
/// `trk_width`/`trk_height`/`trk_channels`/`trk_sample_rate` (0 when absent).
///
/// Frames are parallel vectors plus one blob: `frm_track`, `frm_pts`,
/// `frm_dts`, `frm_duration` (container milliseconds), `frm_key` (1 for a
/// keyframe), `frm_codec` (packed chunk FourCC or 0), `frm_offset`/`frm_size`
/// (a span of `frm_blob`), `frm_chunk_offset` (file offset of the source
/// chunk, -1 when not applicable).
pub type VideoStream = {
  format: Int;
  width: Int;
  height: Int;
  duration_units: Int;
  index_entries: Int;
  index_ok: Int;
  flags: Int;
  trk_kind: Vec[Int];
  trk_codec: Vec[Int];
  trk_scale: Vec[Int];
  trk_rate: Vec[Int];
  trk_length: Vec[Int];
  trk_width: Vec[Int];
  trk_height: Vec[Int];
  trk_channels: Vec[Int];
  trk_sample_rate: Vec[Int];
  frm_track: Vec[Int];
  frm_pts: Vec[Int];
  frm_dts: Vec[Int];
  frm_duration: Vec[Int];
  frm_key: Vec[Int];
  frm_codec: Vec[Int];
  frm_offset: Vec[Int];
  frm_size: Vec[Int];
  frm_chunk_offset: Vec[Int];
  frm_blob: Vec[UInt8];
}

// --------------------------------------------------
//  Result leaf constructors (trap 6)
// --------------------------------------------------

fn _ok_str(v: Str) -> Result[Str, Str] {
  return Ok(v);
}

fn _err_str(m: Str) -> Result[Str, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Internal byte helpers
// --------------------------------------------------

// Byte at `pos` widened to 0..255; callers guarantee the bounds.
fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// Packed big-endian FourCC of the four bytes at `pos`.
fn _fcc(data: &Vec[UInt8], pos: Int) -> Int {
  let b0: Int = _byte(data, pos);
  let b1: Int = _byte(data, pos + 1);
  let b2: Int = _byte(data, pos + 2);
  let b3: Int = _byte(data, pos + 3);
  return b0 * 16777216 + b1 * 65536 + b2 * 256 + b3;
}

// Absolute value of an Int (test-scale values; no Int::MIN special case).
fn _iabs(v: Int) -> Int {
  if v < 0 { return 0 - v; }
  return v;
}

// --------------------------------------------------
//  Sniffing
// --------------------------------------------------

/// Sniff the container format from the leading bytes; returns VIDEO_FMT_*.
/// AVI requires "RIFF" + size + "AVI "; MP4 requires "ftyp" at offset 4;
/// a lone "RIFF" (e.g. WAV) is VIDEO_FMT_UNKNOWN. Complexity: O(1).
pub fn video_sniff(data: &Vec[UInt8]) -> Int {
  if data.len() < 4 {
    return VIDEO_FMT_UNKNOWN;
  }
  if _fcc(data, 0) == VIDEO_FCC_XRAW {
    return VIDEO_FMT_RAW;
  }
  if _fcc(data, 0) == VIDEO_FCC_OGGS {
    return VIDEO_FMT_OGG;
  }
  if _fcc(data, 0) == VIDEO_FCC_RIFF && data.len() >= 12 {
    if _fcc(data, 8) == VIDEO_FCC_AVI {
      return VIDEO_FMT_AVI;
    }
    return VIDEO_FMT_UNKNOWN;
  }
  let b0: Int = _byte(data, 0);
  if b0 == 0x1A && _byte(data, 1) == 0x45 {
    if _byte(data, 2) == 0xDF && _byte(data, 3) == 0xA3 {
      return VIDEO_FMT_MKV;
    }
  }
  if data.len() >= 8 && _fcc(data, 4) == VIDEO_FCC_FTYP {
    return VIDEO_FMT_MP4;
  }
  return VIDEO_FMT_UNKNOWN;
}

/// Human-readable format name for a VIDEO_FMT_* value ("avi", "mkv", "mp4",
/// "ogg", "raw", "unknown"). Literals only; never built from bytes.
pub fn video_format_name(format: Int) -> Str {
  if format == VIDEO_FMT_AVI { return "avi"; }
  if format == VIDEO_FMT_MKV { return "mkv"; }
  if format == VIDEO_FMT_MP4 { return "mp4"; }
  if format == VIDEO_FMT_OGG { return "ogg"; }
  if format == VIDEO_FMT_RAW { return "raw"; }
  return "unknown";
}

/// Decode a packed FourCC into a Str, requiring all four bytes to be
/// printable ASCII (0x20..0x7E). Err("video: bad fourcc") otherwise -- a
/// NUL or control byte can never reach sb_to_str (trap 15). Complexity O(1).
pub fn video_fourcc_to_str(fcc: Int) -> Result[Str, Str] {
  var sb = Vec[UInt8].new();
  var x = ((fcc % 4294967296) + 4294967296) % 4294967296;
  var i = 0;
  while i < 4 {
    let b = (x / 16777216) % 256;
    if b < 0x20 || b > 0x7E {
      return _err_str("video: bad fourcc");
    }
    builder.sb_push_byte(&mut sb, b as UInt8);
    x = (x % 16777216) * 256;
    i = i + 1;
  }
  return _ok_str(builder.sb_to_str(&sb));
}

// --------------------------------------------------
//  Timebase / frame math (integer only)
// --------------------------------------------------

/// A timebase with positive numerator and denominator.
pub fn video_timebase_new(num: Int, den: Int) -> VideoTimebase {
  return VideoTimebase{ num: num; den: den; };
}

/// True when `tb` has a positive numerator and denominator. O(1).
pub fn video_timebase_valid(tb: &VideoTimebase) -> Bool {
  if tb.num <= 0 || tb.den <= 0 {
    return false;
  }
  return true;
}

/// A frame with non-negative track, pts, dts and duration; `keyframe` is
/// normalised to 0/1.
pub fn video_frame_new(track: Int, pts: Int, dts: Int, duration: Int, keyframe: Int) -> VideoFrame {
  var kf = 0;
  if keyframe != 0 { kf = 1; }
  return VideoFrame{ track: track; pts: pts; dts: dts; duration: duration; keyframe: kf; };
}

/// True when the frame's scalars are consistent (track/pts/dts/duration
/// non-negative). Complexity O(1).
pub fn video_frame_valid(f: &VideoFrame) -> Bool {
  if f.track < 0 || f.pts < 0 || f.dts < 0 || f.duration < 0 {
    return false;
  }
  return true;
}

/// Exclusive end timestamp of a frame: pts + duration. O(1).
pub fn video_frame_end(f: &VideoFrame) -> Int {
  return f.pts + f.duration;
}

/// Rescale `ts` ticks of the source timebase (sn/sd seconds per tick) into
/// ticks of the destination timebase (dn/dd seconds per tick). All four
/// timebase numbers must be positive; otherwise 0 is returned. The result
/// rounds half away from zero and is correct for negative `ts` (trap 18;
/// no `(a + b - 1) / b` idiom). Complexity O(1).
pub fn video_rescale(ts: Int, sn: Int, sd: Int, dn: Int, dd: Int) -> Int {
  if sn <= 0 || sd <= 0 || dn <= 0 || dd <= 0 {
    return 0;
  }
  let num = ts * sn * dd;
  let den = sd * dn;
  var q = num / den;
  let r = num % den;
  if _iabs(r) * 2 >= den {
    if r > 0 { q = q + 1; }
    if r < 0 { q = q - 1; }
  }
  return q;
}

/// Rescale with a VideoTimebase source.
pub fn video_timebase_rescale(ts: Int, tb: &VideoTimebase, dn: Int, dd: Int) -> Int {
  return video_rescale(ts, tb.num, tb.den, dn, dd);
}

/// Convert `ts` source-timebase ticks to container milliseconds.
pub fn video_units_to_ms(ts: Int, sn: Int, sd: Int) -> Int {
  return video_rescale(ts, sn, sd, VIDEO_TIME_SCALE_NUM, VIDEO_TIME_SCALE_DEN);
}

/// Convert milliseconds to ticks of the (dn, dd) timebase.
pub fn video_ms_to_units(ms: Int, dn: Int, dd: Int) -> Int {
  return video_rescale(ms, VIDEO_TIME_SCALE_NUM, VIDEO_TIME_SCALE_DEN, dn, dd);
}

/// Container milliseconds of one tick of the (sn, sd) timebase.
pub fn video_tick_ms(sn: Int, sd: Int) -> Int {
  return video_rescale(1, sn, sd, VIDEO_TIME_SCALE_NUM, VIDEO_TIME_SCALE_DEN);
}

/// One frame's duration in container milliseconds for a frame rate of
/// fps_num/fps_den frames per second. O(1).
pub fn video_frame_duration_ms(fps_num: Int, fps_den: Int) -> Int {
  return video_rescale(1, fps_den, fps_num, VIDEO_TIME_SCALE_NUM, VIDEO_TIME_SCALE_DEN);
}

// Append a two-digit zero-padded value (values >= 100 print in full).
fn _push_00(sb: &mut Vec[UInt8], v: Int) {
  var x = v;
  if x < 0 { x = 0; }
  if x < 10 {
    builder.sb_push_byte(sb, 0x30 as UInt8);
  }
  builder.sb_push_int(sb, x);
}

// Append a three-digit zero-padded value.
fn _push_000(sb: &mut Vec[UInt8], v: Int) {
  var x = v;
  if x < 0 { x = 0; }
  if x < 10 { builder.sb_push_byte(sb, 0x30 as UInt8); }
  if x < 100 { builder.sb_push_byte(sb, 0x30 as UInt8); }
  builder.sb_push_int(sb, x);
}

/// Format a duration as "HH:MM:SS.mmm" (container milliseconds; negative
/// input is clamped to zero; hours above 99 print in full). Complexity O(1).
pub fn video_format_time(ts: Int, sn: Int, sd: Int) -> Str {
  var ms = video_units_to_ms(ts, sn, sd);
  if ms < 0 { ms = 0; }
  let h = ms / 3600000;
  let m = (ms % 3600000) / 60000;
  let s = (ms % 60000) / 1000;
  let milli = ms % 1000;
  var sb = Vec[UInt8].new();
  _push_00(&mut sb, h);
  builder.sb_push_byte(&mut sb, 0x3A as UInt8);
  _push_00(&mut sb, m);
  builder.sb_push_byte(&mut sb, 0x3A as UInt8);
  _push_00(&mut sb, s);
  builder.sb_push_byte(&mut sb, 0x2E as UInt8);
  _push_000(&mut sb, milli);
  return builder.sb_to_str(&sb);
}
