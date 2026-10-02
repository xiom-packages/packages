// XIOM -- xiom.video.store: VideoStream builders and guarded accessors
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Owns the VideoStream record lifecycle: construction, the builder API used
// by muxers and demuxers (one mirrored push per parallel vector, trap 16)
// and the range-guarded accessors. Every accessor works off the minimum
// length across its pool so a (never expected) drift cannot read out of
// range, and every Vec element read binds a typed local (trap 1/2). Payload
// bytes live in one blob addressed by offset/size pairs; video_frame_data
// returns a copy and never interprets the bytes (no codecs).
//
// Compiler-v0.62.2 notes: free functions only, Ok/Err only in the leaf
// helpers, `&mut VideoStream` at explicit `&mut` call sites, no `&mut`
// scalars, bounded loops, no Vec[Str].

module xiom.video.store

use xiom.video;

// --------------------------------------------------
//  Result leaf constructors
// --------------------------------------------------

fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

fn _err_int(m: Str) -> Result[Int, Str] {
  return Err(m);
}

// Smaller of two Ints.
fn _min_int(a: Int, b: Int) -> Int {
  if a < b { return a; }
  return b;
}

// --------------------------------------------------
//  Constructors, builders and setters
// --------------------------------------------------

/// A fresh empty store: VIDEO_FMT_UNKNOWN, no tracks, no frames,
/// VIDEO_INDEX_NONE. Complexity O(1).
pub fn video_stream_new() -> VideoStream {
  return VideoStream{
    format: VIDEO_FMT_UNKNOWN;
    width: 0;
    height: 0;
    duration_units: 0;
    index_entries: 0;
    index_ok: VIDEO_INDEX_NONE;
    flags: 0;
    trk_kind: Vec[Int].new();
    trk_codec: Vec[Int].new();
    trk_scale: Vec[Int].new();
    trk_rate: Vec[Int].new();
    trk_length: Vec[Int].new();
    trk_width: Vec[Int].new();
    trk_height: Vec[Int].new();
    trk_channels: Vec[Int].new();
    trk_sample_rate: Vec[Int].new();
    frm_track: Vec[Int].new();
    frm_pts: Vec[Int].new();
    frm_dts: Vec[Int].new();
    frm_duration: Vec[Int].new();
    frm_key: Vec[Int].new();
    frm_codec: Vec[Int].new();
    frm_offset: Vec[Int].new();
    frm_size: Vec[Int].new();
    frm_chunk_offset: Vec[Int].new();
    frm_blob: Vec[UInt8].new();
  };
}

/// Append a track. `kind` must be VIDEO_KIND_VIDEO/AUDIO/OTHER, `scale` and
/// `rate` must be positive (one tick is scale/rate seconds), the remaining
/// fields non-negative. Returns Ok(track index) or Err("video: bad track
/// kind" / "video: bad timebase" / "video: bad codec" / "video: bad track
/// field" / "video: too many streams"). Complexity O(1).
pub fn video_add_track(s: &mut VideoStream, kind: Int, codec: Int, scale: Int, rate: Int, length: Int, width: Int, height: Int, channels: Int, sample_rate: Int) -> Result[Int, Str] {
  if kind < VIDEO_KIND_VIDEO || kind > VIDEO_KIND_OTHER {
    return _err_int("video: bad track kind");
  }
  if scale <= 0 || rate <= 0 {
    return _err_int("video: bad timebase");
  }
  if codec < 0 {
    return _err_int("video: bad codec");
  }
  if length < 0 || width < 0 || height < 0 || channels < 0 || sample_rate < 0 {
    return _err_int("video: bad track field");
  }
  if video_track_count(s) >= VIDEO_MAX_TRACKS {
    return _err_int("video: too many streams");
  }
  s.trk_kind.push(kind);
  s.trk_codec.push(codec);
  s.trk_scale.push(scale);
  s.trk_rate.push(rate);
  s.trk_length.push(length);
  s.trk_width.push(width);
  s.trk_height.push(height);
  s.trk_channels.push(channels);
  s.trk_sample_rate.push(sample_rate);
  return _ok_int(video_track_count(s) - 1);
}

/// Append a frame whose payload is the span [off, off + size) of `data`
/// (opaque bytes, copied into the store blob). Every parallel frame vector
/// is pushed exactly once (trap 16). Errors: "video: bad track index",
/// "video: bad timestamp" (negative pts/dts), "video: bad duration",
/// "video: bad codec", "video: bad payload span". Complexity O(size).
pub fn video_add_frame_span(s: &mut VideoStream, track: Int, pts: Int, dts: Int, duration: Int, key: Int, codec: Int, data: &Vec[UInt8], off: Int, size: Int) -> Result[Int, Str] {
  if track < 0 || track >= video_track_count(s) {
    return _err_int("video: bad track index");
  }
  if pts < 0 || dts < 0 {
    return _err_int("video: bad timestamp");
  }
  if duration < 0 {
    return _err_int("video: bad duration");
  }
  if codec < 0 {
    return _err_int("video: bad codec");
  }
  if off < 0 || size < 0 {
    return _err_int("video: bad payload span");
  }
  if off + size > data.len() {
    return _err_int("video: bad payload span");
  }
  var kf = 0;
  if key != 0 { kf = 1; }
  let blob_off: Int = s.frm_blob.len();
  s.frm_track.push(track);
  s.frm_pts.push(pts);
  s.frm_dts.push(dts);
  s.frm_duration.push(duration);
  s.frm_key.push(kf);
  s.frm_codec.push(codec);
  s.frm_offset.push(blob_off);
  s.frm_size.push(size);
  s.frm_chunk_offset.push(-1);
  var i = 0;
  while i < size {
    let b: UInt8 = data[off + i];
    s.frm_blob.push(b);
    i = i + 1;
  }
  return _ok_int(video_frame_count(s) - 1);
}

/// Append a frame whose payload is all of `data`.
pub fn video_add_frame(s: &mut VideoStream, track: Int, pts: Int, dts: Int, duration: Int, key: Int, codec: Int, data: &Vec[UInt8]) -> Result[Int, Str] {
  return video_add_frame_span(s, track, pts, dts, duration, key, codec, data, 0, data.len());
}

/// Overwrite frame `i`'s keyframe flag (0/1); out-of-range indices are
/// ignored. Complexity O(1).
pub fn video_set_frame_key(s: &mut VideoStream, i: Int, key: Int) {
  if i < 0 || i >= video_frame_count(s) {
    return;
  }
  var kf = 0;
  if key != 0 { kf = 1; }
  s.frm_key[i] = kf;
}

/// Record the source-file offset of frame `i`'s chunk; out-of-range indices
/// are ignored. Complexity O(1).
pub fn video_set_frame_chunk_offset(s: &mut VideoStream, i: Int, off: Int) {
  if i < 0 || i >= video_frame_count(s) {
    return;
  }
  s.frm_chunk_offset[i] = off;
}

/// Overwrite the container header fields. Complexity O(1).
pub fn video_set_stream_header(s: &mut VideoStream, format: Int, width: Int, height: Int, duration_units: Int, flags: Int) {
  s.format = format;
  s.width = width;
  s.height = height;
  s.duration_units = duration_units;
  s.flags = flags;
}

/// Overwrite the index summary. Complexity O(1).
pub fn video_set_index(s: &mut VideoStream, entries: Int, ok: Int) {
  s.index_entries = entries;
  s.index_ok = ok;
}

/// Overwrite the container format. Complexity O(1).
pub fn video_set_format(s: &mut VideoStream, format: Int) {
  s.format = format;
}

/// Overwrite the declared container width/height. Complexity O(1).
pub fn video_set_size(s: &mut VideoStream, width: Int, height: Int) {
  s.width = width;
  s.height = height;
}

/// Overwrite the container duration in milliseconds. Complexity O(1).
pub fn video_set_duration_ms(s: &mut VideoStream, ms: Int) {
  s.duration_units = ms;
}

/// Overwrite the container flags. Complexity O(1).
pub fn video_set_flags(s: &mut VideoStream, flags: Int) {
  s.flags = flags;
}

// --------------------------------------------------
//  Accessors: stream header
// --------------------------------------------------

/// Container format (VIDEO_FMT_*). O(1).
pub fn video_format(s: &VideoStream) -> Int {
  return s.format;
}

/// Declared container width, 0 when absent. O(1).
pub fn video_stream_width(s: &VideoStream) -> Int {
  return s.width;
}

/// Declared container height, 0 when absent. O(1).
pub fn video_stream_height(s: &VideoStream) -> Int {
  return s.height;
}

/// Container duration in milliseconds (maximum over tracks; 0 when no
/// track). O(1).
pub fn video_stream_duration_ms(s: &VideoStream) -> Int {
  return s.duration_units;
}

/// Number of parsed index entries, 0 when absent. O(1).
pub fn video_index_entries(s: &VideoStream) -> Int {
  return s.index_entries;
}

/// Index status: VIDEO_INDEX_OK/BAD/NONE. O(1).
pub fn video_index_ok(s: &VideoStream) -> Int {
  return s.index_ok;
}

/// Container flags (AVI avih dwFlags; 0 otherwise). O(1).
pub fn video_flags(s: &VideoStream) -> Int {
  return s.flags;
}

// --------------------------------------------------
//  Accessors: tracks (guarded)
// --------------------------------------------------

// Number of complete track records: minimum length across the track pools.
fn _track_count(s: &VideoStream) -> Int {
  var m = s.trk_kind.len();
  m = _min_int(m, s.trk_codec.len());
  m = _min_int(m, s.trk_scale.len());
  m = _min_int(m, s.trk_rate.len());
  m = _min_int(m, s.trk_length.len());
  m = _min_int(m, s.trk_width.len());
  m = _min_int(m, s.trk_height.len());
  m = _min_int(m, s.trk_channels.len());
  m = _min_int(m, s.trk_sample_rate.len());
  return m;
}

/// Number of tracks. O(1).
pub fn video_track_count(s: &VideoStream) -> Int {
  return _track_count(s);
}

/// Track `i`'s kind (VIDEO_KIND_*); -1 out of range. O(1).
pub fn video_track_kind(s: &VideoStream, i: Int) -> Int {
  if i < 0 || i >= _track_count(s) { return -1; }
  let v: Int = s.trk_kind[i];
  return v;
}

/// Track `i`'s opaque codec/handler tag; -1 out of range. O(1).
pub fn video_track_codec(s: &VideoStream, i: Int) -> Int {
  if i < 0 || i >= _track_count(s) { return -1; }
  let v: Int = s.trk_codec[i];
  return v;
}

/// Track `i`'s timebase numerator (scale); -1 out of range. O(1).
pub fn video_track_scale(s: &VideoStream, i: Int) -> Int {
  if i < 0 || i >= _track_count(s) { return -1; }
  let v: Int = s.trk_scale[i];
  return v;
}

/// Track `i`'s timebase denominator (rate in ticks/second); -1 out of
/// range. O(1).
pub fn video_track_rate(s: &VideoStream, i: Int) -> Int {
  if i < 0 || i >= _track_count(s) { return -1; }
  let v: Int = s.trk_rate[i];
  return v;
}

/// Track `i`'s declared length in ticks; -1 out of range. O(1).
pub fn video_track_length(s: &VideoStream, i: Int) -> Int {
  if i < 0 || i >= _track_count(s) { return -1; }
  let v: Int = s.trk_length[i];
  return v;
}

/// Track `i`'s pixel width (0 when absent); -1 out of range. O(1).
pub fn video_track_width(s: &VideoStream, i: Int) -> Int {
  if i < 0 || i >= _track_count(s) { return -1; }
  let v: Int = s.trk_width[i];
  return v;
}

/// Track `i`'s pixel height (0 when absent); -1 out of range. O(1).
pub fn video_track_height(s: &VideoStream, i: Int) -> Int {
  if i < 0 || i >= _track_count(s) { return -1; }
  let v: Int = s.trk_height[i];
  return v;
}

/// Track `i`'s channel count (0 when absent); -1 out of range. O(1).
pub fn video_track_channels(s: &VideoStream, i: Int) -> Int {
  if i < 0 || i >= _track_count(s) { return -1; }
  let v: Int = s.trk_channels[i];
  return v;
}

/// Track `i`'s sample rate in Hz (0 when absent); -1 out of range. O(1).
pub fn video_track_sample_rate(s: &VideoStream, i: Int) -> Int {
  if i < 0 || i >= _track_count(s) { return -1; }
  let v: Int = s.trk_sample_rate[i];
  return v;
}

/// Track `i`'s declared duration in milliseconds; -1 out of range. O(1).
pub fn video_track_duration_ms(s: &VideoStream, i: Int) -> Int {
  if i < 0 || i >= _track_count(s) { return -1; }
  let ts: Int = s.trk_length[i];
  let sn: Int = s.trk_scale[i];
  let sd: Int = s.trk_rate[i];
  return video_units_to_ms(ts, sn, sd);
}

// --------------------------------------------------
//  Accessors: frames (guarded)
// --------------------------------------------------

// Number of complete frame records: minimum length across the frame pools.
fn _frame_count(s: &VideoStream) -> Int {
  var m = s.frm_track.len();
  m = _min_int(m, s.frm_pts.len());
  m = _min_int(m, s.frm_dts.len());
  m = _min_int(m, s.frm_duration.len());
  m = _min_int(m, s.frm_key.len());
  m = _min_int(m, s.frm_codec.len());
  m = _min_int(m, s.frm_offset.len());
  m = _min_int(m, s.frm_size.len());
  m = _min_int(m, s.frm_chunk_offset.len());
  return m;
}

/// Number of frames. O(1).
pub fn video_frame_count(s: &VideoStream) -> Int {
  return _frame_count(s);
}

/// Frame `i`'s track index; -1 out of range. O(1).
pub fn video_frame_track(s: &VideoStream, i: Int) -> Int {
  if i < 0 || i >= _frame_count(s) { return -1; }
  let v: Int = s.frm_track[i];
  return v;
}

/// Frame `i`'s presentation timestamp in container milliseconds; -1 out of
/// range. O(1).
pub fn video_frame_pts(s: &VideoStream, i: Int) -> Int {
  if i < 0 || i >= _frame_count(s) { return -1; }
  let v: Int = s.frm_pts[i];
  return v;
}

/// Frame `i`'s decode timestamp in container milliseconds; -1 out of range.
pub fn video_frame_dts(s: &VideoStream, i: Int) -> Int {
  if i < 0 || i >= _frame_count(s) { return -1; }
  let v: Int = s.frm_dts[i];
  return v;
}

/// Frame `i`'s duration in container milliseconds; -1 out of range. O(1).
pub fn video_frame_duration(s: &VideoStream, i: Int) -> Int {
  if i < 0 || i >= _frame_count(s) { return -1; }
  let v: Int = s.frm_duration[i];
  return v;
}

/// Frame `i`'s keyframe flag (0/1); -1 out of range. O(1).
pub fn video_frame_is_key(s: &VideoStream, i: Int) -> Int {
  if i < 0 || i >= _frame_count(s) { return -1; }
  let v: Int = s.frm_key[i];
  return v;
}

/// Frame `i`'s chunk FourCC tag (0 when not applicable); -1 out of range.
pub fn video_frame_codec(s: &VideoStream, i: Int) -> Int {
  if i < 0 || i >= _frame_count(s) { return -1; }
  let v: Int = s.frm_codec[i];
  return v;
}

/// Frame `i`'s payload size in bytes; -1 out of range. O(1).
pub fn video_frame_size(s: &VideoStream, i: Int) -> Int {
  if i < 0 || i >= _frame_count(s) { return -1; }
  let v: Int = s.frm_size[i];
  return v;
}

/// Source-file offset of frame `i`'s chunk (-1 when not applicable or out
/// of range). O(1).
pub fn video_frame_chunk_offset(s: &VideoStream, i: Int) -> Int {
  if i < 0 || i >= _frame_count(s) { return -1; }
  let v: Int = s.frm_chunk_offset[i];
  return v;
}

/// Copy of frame `i`'s opaque payload; empty when `i` is out of range or
/// the recorded span is inconsistent. Complexity O(size).
pub fn video_frame_data(s: &VideoStream, i: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  if i < 0 || i >= _frame_count(s) { return out; }
  let off: Int = s.frm_offset[i];
  let size: Int = s.frm_size[i];
  if off < 0 || size < 0 { return out; }
  if off + size > s.frm_blob.len() { return out; }
  var k = 0;
  while k < size {
    let b: UInt8 = s.frm_blob[off + k];
    out.push(b);
    k = k + 1;
  }
  return out;
}

/// Frame model of frame `i` (track/pts/dts/duration/keyframe); the fields
/// are -1 when `i` is out of range. O(1).
pub fn video_frame_at(s: &VideoStream, i: Int) -> VideoFrame {
  if i < 0 || i >= _frame_count(s) {
    return video_frame_new(-1, -1, -1, -1, 0);
  }
  let t: Int = s.frm_track[i];
  let p: Int = s.frm_pts[i];
  let d: Int = s.frm_dts[i];
  let du: Int = s.frm_duration[i];
  let k: Int = s.frm_key[i];
  return video_frame_new(t, p, d, du, k);
}

/// Number of frames stored on track `t`; 0 when `t` is out of range.
/// Complexity O(frame count).
pub fn video_track_frame_count(s: &VideoStream, t: Int) -> Int {
  if t < 0 || t >= _track_count(s) { return 0; }
  var n = 0;
  var i = 0;
  while i < _frame_count(s) {
    let ft: Int = s.frm_track[i];
    if ft == t { n = n + 1; }
    i = i + 1;
  }
  return n;
}
