// XIOM -- xiom.video.avi: minimal RIFF/AVI mux and demux
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Proof container for the xiom.video package: parses and writes the classic
// RIFF/AVI subset documented in SPEC.md --
//
//   RIFF <size> AVI
//     LIST hdrl
//       avih (56-byte main header)
//       LIST strl
//         strh (56-byte stream header: handler, codec, scale/rate/length)
//         strf (BITMAPINFOHEADER for video/text, WAVEFORMATEX for audio)
//     LIST movi
//       "<nn>dc" / "<nn>db" / "<nn>wb" / "<nn>tx" chunks, word-aligned
//     idx1 (16-byte entries: chunk id, flags, offset from the 'movi' FourCC,
//           size), cross-checked against the parsed chunks
//
// Payloads are opaque byte spans; no codec is decoded. Chunk walks are
// bounds-checked and strictly advancing (> = 8 bytes per iteration), so
// malformed sizes fail with a documented error instead of looping.
//
// Compiler-v0.62.2 notes: free functions only, typed locals on every Vec
// read, `(b as Int) & 0xFF` everywhere, Ok/Err only in the leaf helpers,
// avi_demux returns the store through a leaf helper (trap 6), no `&mut`
// scalar parameters (parse state stays in locals or the store), no
// Vec[StructType] (track/frame pools are parallel vectors, trap 10/16).

module xiom.video.avi

use xiom.video;
use xiom.video.store;

// --------------------------------------------------
//  Result leaf constructors
// --------------------------------------------------

fn _ok_int(v: Int) -> Result[Int, Str] { return Ok(v); }
fn _err_int(m: Str) -> Result[Int, Str] { return Err(m); }
fn _ok_unit() -> Result[Unit, Str] { return Ok(()); }
fn _err_unit(m: Str) -> Result[Unit, Str] { return Err(m); }
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

fn _u16le(data: &Vec[UInt8], pos: Int) -> Int {
  let b0: Int = _byte(data, pos);
  let b1: Int = _byte(data, pos + 1);
  return b0 + b1 * 256;
}

fn _u32le(data: &Vec[UInt8], pos: Int) -> Int {
  let b0: Int = _byte(data, pos);
  let b1: Int = _byte(data, pos + 1);
  let b2: Int = _byte(data, pos + 2);
  let b3: Int = _byte(data, pos + 3);
  return b0 + b1 * 256 + b2 * 65536 + b3 * 16777216;
}

fn _i32le(data: &Vec[UInt8], pos: Int) -> Int {
  let v = _u32le(data, pos);
  if v >= 2147483648 { return v - 4294967296; }
  return v;
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

fn _push_u16le(out: &mut Vec[UInt8], v: Int) {
  var x = ((v % 65536) + 65536) % 65536;
  out.push((x % 256) as UInt8);
  out.push(((x / 256) % 256) as UInt8);
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

// One RIFF chunk: id + u32 size + body + pad byte when the body is odd.
fn _push_chunk(out: &mut Vec[UInt8], ckid: Int, body: &Vec[UInt8]) {
  _push_fcc(out, ckid);
  _push_u32le(out, body.len());
  _push_bytes(out, body);
  if body.len() % 2 == 1 {
    out.push(0 as UInt8);
  }
}

// One LIST chunk: "LIST" + u32 (4 + body) + list type + body.
fn _push_list(out: &mut Vec[UInt8], list_type: Int, body: &Vec[UInt8]) {
  _push_fcc(out, VIDEO_FCC_LIST);
  _push_u32le(out, body.len() + 4);
  _push_fcc(out, list_type);
  _push_bytes(out, body);
}

// --------------------------------------------------
//  Internal parse records
// --------------------------------------------------

// strh fields this module consumes.
type AviStrh = {
  kind: Int;
  codec: Int;
  scale: Int;
  rate: Int;
  length: Int;
}

// strf fields this module consumes (video/text: width/height/compression;
// audio: channels/sample rate/format tag).
type AviStrf = {
  width: Int;
  height: Int;
  channels: Int;
  sample_rate: Int;
  codec: Int;
}

fn _ok_strh(v: AviStrh) -> Result[AviStrh, Str] { return Ok(v); }
fn _err_strh(m: Str) -> Result[AviStrh, Str] { return Err(m); }
fn _ok_strf(v: AviStrf) -> Result[AviStrf, Str] { return Ok(v); }
fn _err_strf(m: Str) -> Result[AviStrf, Str] { return Err(m); }

// --------------------------------------------------
//  Parsing
// --------------------------------------------------

// strh: handler + codec + scale/rate/length. Requires the fixed 56 bytes.
fn _parse_strh(data: &Vec[UInt8], start: Int, end: Int) -> Result[AviStrh, Str] {
  if end - start < 56 {
    return _err_strh("video: truncated stream header");
  }
  let handler = _fcc(data, start);
  var kind = VIDEO_KIND_OTHER;
  if handler == VIDEO_FCC_VIDS { kind = VIDEO_KIND_VIDEO; }
  if handler == VIDEO_FCC_AUDS { kind = VIDEO_KIND_AUDIO; }
  let codec = _u32le(data, start + 4);
  let scale = _u32le(data, start + 20);
  let rate = _u32le(data, start + 24);
  let length = _u32le(data, start + 32);
  return _ok_strh(AviStrh{ kind: kind; codec: codec; scale: scale; rate: rate; length: length; });
}

// strf: BITMAPINFOHEADER (video/text, >= 40 bytes) or WAVEFORMATEX (audio,
// >= 16 bytes). The strh kind selects the layout.
fn _parse_strf(data: &Vec[UInt8], start: Int, end: Int, kind: Int) -> Result[AviStrf, Str] {
  if kind == VIDEO_KIND_AUDIO {
    if end - start < 16 {
      return _err_strf("video: truncated stream format");
    }
    let tag = _u16le(data, start);
    let channels = _u16le(data, start + 2);
    let sample_rate = _u32le(data, start + 4);
    return _ok_strf(AviStrf{ width: 0; height: 0; channels: channels; sample_rate: sample_rate; codec: tag; });
  }
  if end - start < 40 {
    return _err_strf("video: truncated stream format");
  }
  let width = _i32le(data, start + 4);
  let height = _i32le(data, start + 8);
  let compression = _u32le(data, start + 16);
  return _ok_strf(AviStrf{ width: width; height: height; channels: 0; sample_rate: 0; codec: compression; });
}

// avih: validates the 56-byte main header, records width/height/flags and
// returns the declared stream count.
fn _parse_avih(data: &Vec[UInt8], start: Int, end: Int, s: &mut VideoStream) -> Result[Int, Str] {
  if end - start < 40 {
    return _err_int("video: truncated main header");
  }
  let flags = _u32le(data, start + 12);
  let streams = _u32le(data, start + 24);
  let width = _u32le(data, start + 32);
  let height = _u32le(data, start + 36);
  video_set_size(s, width, height);
  video_set_flags(s, flags);
  return _ok_int(streams);
}

// One LIST strl: strh then strf (order enforced). Appends one track.
fn _parse_strl(data: &Vec[UInt8], start: Int, end: Int, s: &mut VideoStream) -> Result[Unit, Str] {
  var saw_h = false;
  var saw_f = false;
  var h_kind = 0;
  var h_codec = 0;
  var h_scale = 0;
  var h_rate = 0;
  var h_length = 0;
  var f_width = 0;
  var f_height = 0;
  var f_channels = 0;
  var f_sr = 0;
  var f_codec = 0;
  var pos = start;
  while pos + 8 <= end {
    let ckid = _fcc(data, pos);
    let size = _u32le(data, pos + 4);
    let dstart = pos + 8;
    let dend = dstart + size;
    if dend > end {
      return _err_unit("video: truncated chunk");
    }
    if ckid == VIDEO_FCC_STRH {
      let r = _parse_strh(data, dstart, dend);
      if !r.is_ok { return _err_unit(r.error); }
      let h = r.value;
      h_kind = h.kind;
      h_codec = h.codec;
      h_scale = h.scale;
      h_rate = h.rate;
      h_length = h.length;
      saw_h = true;
    } else if ckid == VIDEO_FCC_STRF {
      if !saw_h {
        return _err_unit("video: bad stream order");
      }
      let r = _parse_strf(data, dstart, dend, h_kind);
      if !r.is_ok { return _err_unit(r.error); }
      let f = r.value;
      f_width = f.width;
      f_height = f.height;
      f_channels = f.channels;
      f_sr = f.sample_rate;
      f_codec = f.codec;
      saw_f = true;
    }
    pos = dend;
    if size % 2 == 1 { pos = pos + 1; }
  }
  if !saw_h { return _err_unit("video: missing stream header"); }
  if !saw_f { return _err_unit("video: missing stream format"); }
  var codec = h_codec;
  if codec == 0 { codec = f_codec; }
  let r = video_add_track(s, h_kind, codec, h_scale, h_rate, h_length, f_width, f_height, f_channels, f_sr);
  if !r.is_ok { return _err_unit(r.error); }
  return _ok_unit();
}

// LIST hdrl: one avih plus one LIST strl per stream. The declared dwStreams
// (when nonzero) must match the number of parsed streams.
fn _parse_hdrl(data: &Vec[UInt8], start: Int, end: Int, s: &mut VideoStream) -> Result[Unit, Str] {
  var saw_avih = false;
  var saw_strl = false;
  var declared = -1;
  var pos = start;
  while pos + 8 <= end {
    let ckid = _fcc(data, pos);
    let size = _u32le(data, pos + 4);
    let dstart = pos + 8;
    let dend = dstart + size;
    if dend > end {
      return _err_unit("video: truncated chunk");
    }
    if ckid == VIDEO_FCC_LIST && size >= 4 {
      let ltype = _fcc(data, dstart);
      if ltype == VIDEO_FCC_STRL {
        let r = _parse_strl(data, dstart + 4, dend, s);
        if !r.is_ok { return _err_unit(r.error); }
        saw_strl = true;
      }
    } else if ckid == VIDEO_FCC_AVIH {
      let r = _parse_avih(data, dstart, dend, s);
      if !r.is_ok { return _err_unit(r.error); }
      declared = r.value;
      saw_avih = true;
    }
    pos = dend;
    if size % 2 == 1 { pos = pos + 1; }
  }
  if !saw_avih { return _err_unit("video: missing main header"); }
  if !saw_strl { return _err_unit("video: missing stream header"); }
  if declared > 0 && declared != video_track_count(s) {
    return _err_unit("video: bad stream count");
  }
  return _ok_unit();
}

// LIST movi: walks data chunks, records one frame per recognised chunk
// ("nn" stream number + dc/db/wb/tx type). A chunk with an out-of-range
// stream number is Err("video: bad stream number"); payloads are copied
// verbatim. pts/duration are derived from the per-stream timebase.
fn _parse_movi(data: &Vec[UInt8], start: Int, end: Int, s: &mut VideoStream) -> Result[Unit, Str] {
  let ntrk = video_track_count(s);
  var counts = Vec[Int].new();
  var t = 0;
  while t < ntrk {
    counts.push(0);
    t = t + 1;
  }
  var pos = start;
  while pos + 8 <= end {
    let size = _u32le(data, pos + 4);
    let dstart = pos + 8;
    let dend = dstart + size;
    if dend > end {
      return _err_unit("video: truncated chunk");
    }
    let b0: Int = _byte(data, pos);
    let b1: Int = _byte(data, pos + 1);
    let b2: Int = _byte(data, pos + 2);
    let b3: Int = _byte(data, pos + 3);
    var recognized = false;
    if b0 >= 0x30 && b0 <= 0x39 && b1 >= 0x30 && b1 <= 0x39 {
      if b2 == 0x64 && (b3 == 0x63 || b3 == 0x62) { recognized = true; }
      if b2 == 0x77 && b3 == 0x62 { recognized = true; }
      if b2 == 0x74 && b3 == 0x78 { recognized = true; }
    }
    if recognized {
      let track = (b0 - 0x30) * 10 + (b1 - 0x30);
      if track >= ntrk {
        return _err_unit("video: bad stream number");
      }
      let c: Int = counts[track];
      let sn = video_track_scale(s, track);
      let sd = video_track_rate(s, track);
      let dur = video_tick_ms(sn, sd);
      let pts = video_units_to_ms(c, sn, sd);
      let ckid = b0 * 16777216 + b1 * 65536 + b2 * 256 + b3;
      let r = video_add_frame_span(s, track, pts, pts, dur, 0, ckid, data, dstart, size);
      if !r.is_ok { return _err_unit(r.error); }
      let fi: Int = r.value;
      video_set_frame_chunk_offset(s, fi, pos);
      counts[track] = c + 1;
    }
    pos = dend;
    if size % 2 == 1 { pos = pos + 1; }
  }
  return _ok_unit();
}

// idx1: every entry must match a parsed chunk by (movi-relative offset);
// the entry also supplies the keyframe flag. Sets the index summary.
fn _check_index(data: &Vec[UInt8], idx_start: Int, idx_end: Int, movi_pos: Int, s: &mut VideoStream) -> Result[Unit, Str] {
  if (idx_end - idx_start) % 16 != 0 {
    return _err_unit("video: bad index size");
  }
  let count = (idx_end - idx_start) / 16;
  var ok = VIDEO_INDEX_OK;
  if count != video_frame_count(s) {
    ok = VIDEO_INDEX_BAD;
  }
  var e = 0;
  while e < count {
    let p = idx_start + e * 16;
    let ckid = _fcc(data, p);
    let flags = _u32le(data, p + 4);
    let off = _u32le(data, p + 8);
    let size = _u32le(data, p + 12);
    var found = -1;
    var j = 0;
    while j < video_frame_count(s) {
      if found < 0 {
        let coff = video_frame_chunk_offset(s, j);
        if coff >= 0 && movi_pos >= 0 && coff - movi_pos == off {
          found = j;
        }
      }
      j = j + 1;
    }
    if found < 0 {
      ok = VIDEO_INDEX_BAD;
    } else {
      if video_frame_codec(s, found) != ckid { ok = VIDEO_INDEX_BAD; }
      if video_frame_size(s, found) != size { ok = VIDEO_INDEX_BAD; }
      let is_key = (flags / VIDEO_AVI_KEYFRAME) % 2;
      video_set_frame_key(s, found, is_key);
    }
    e = e + 1;
  }
  video_set_index(s, count, ok);
  return _ok_unit();
}

/// Parse a RIFF/AVI buffer into a fresh VideoStream. Errors (all prefixed
/// "video: "): truncated header, not avi, bad riff size, truncated chunk,
/// missing header list, missing main header, missing stream header, missing
/// stream format, bad stream order, bad stream count, truncated main
/// header, truncated stream header, truncated stream format, bad stream
/// number, no streams, bad index size. Complexity O(data.len()) plus the
/// O(frames * entries) index cross-check.
pub fn avi_demux(data: &Vec[UInt8]) -> Result[VideoStream, Str] {
  if data.len() < 12 {
    return _err_stream("video: truncated header");
  }
  if _fcc(data, 0) != VIDEO_FCC_RIFF || _fcc(data, 8) != VIDEO_FCC_AVI {
    return _err_stream("video: not avi");
  }
  let declared = _u32le(data, 4);
  if declared < 4 || declared + 8 > data.len() {
    return _err_stream("video: bad riff size");
  }
  let end = declared + 8;
  var s = video_stream_new();
  video_set_format(&mut s, VIDEO_FMT_AVI);
  var pos = 12;
  var movi_pos = -1;
  var idx_start = -1;
  var idx_end = -1;
  var saw_hdrl = false;
  while pos + 8 <= end {
    let ckid = _fcc(data, pos);
    let size = _u32le(data, pos + 4);
    let dstart = pos + 8;
    let dend = dstart + size;
    if dend > end {
      return _err_stream("video: truncated chunk");
    }
    if ckid == VIDEO_FCC_LIST && size >= 4 {
      let ltype = _fcc(data, dstart);
      if ltype == VIDEO_FCC_HDRL {
        let r = _parse_hdrl(data, dstart + 4, dend, &mut s);
        if !r.is_ok { return _err_stream(r.error); }
        saw_hdrl = true;
      } else if ltype == VIDEO_FCC_MOVI {
        movi_pos = dstart;
        let r = _parse_movi(data, dstart + 4, dend, &mut s);
        if !r.is_ok { return _err_stream(r.error); }
      }
    } else if ckid == VIDEO_FCC_IDX1 {
      idx_start = dstart;
      idx_end = dend;
    }
    pos = dend;
    if size % 2 == 1 { pos = pos + 1; }
  }
  if !saw_hdrl { return _err_stream("video: missing header list"); }
  if video_track_count(&s) == 0 { return _err_stream("video: no streams"); }
  if idx_start >= 0 {
    let r = _check_index(data, idx_start, idx_end, movi_pos, &mut s);
    if !r.is_ok { return _err_stream(r.error); }
  }
  var dmax = 0;
  var t = 0;
  while t < video_track_count(&s) {
    let dm = video_track_duration_ms(&s, t);
    if dm > dmax { dmax = dm; }
    t = t + 1;
  }
  video_set_duration_ms(&mut s, dmax);
  return _ok_stream(s);
}

// --------------------------------------------------
//  Muxing
// --------------------------------------------------

// 'vids' / 'auds' / 'txts' for a track kind.
fn _handler_for_kind(kind: Int) -> Int {
  if kind == VIDEO_KIND_VIDEO { return VIDEO_FCC_VIDS; }
  if kind == VIDEO_KIND_AUDIO { return VIDEO_FCC_AUDS; }
  return VIDEO_FCC_TXTS;
}

// "<nn>dc" (video), "<nn>wb" (audio) or "<nn>tx" (other); nn is decimal.
fn _chunk_id_for(track: Int, kind: Int) -> Int {
  var t = track;
  if t < 0 { t = 0; }
  if t > 99 { t = 99; }
  let d0 = 0x30 + (t / 10) % 10;
  let d1 = 0x30 + t % 10;
  var c2 = 0x64;
  var c3 = 0x63;
  if kind == VIDEO_KIND_AUDIO {
    c2 = 0x77;
    c3 = 0x62;
  }
  if kind == VIDEO_KIND_OTHER {
    c2 = 0x74;
    c3 = 0x78;
  }
  return d0 * 16777216 + d1 * 65536 + c2 * 256 + c3;
}

// Largest frame payload on track `t`.
fn _track_max_frame(s: &VideoStream, t: Int) -> Int {
  var m = 0;
  var i = 0;
  while i < video_frame_count(s) {
    if video_frame_track(s, i) == t {
      let sz = video_frame_size(s, i);
      if sz > m { m = sz; }
    }
    i = i + 1;
  }
  return m;
}

/// Build a minimal RIFF/AVI container from the store: hdrl with avih and one
/// strl per track, a movi list with one word-aligned chunk per frame and an
/// idx1 index (AVIF_HASINDEX). Frame payloads stay opaque. Errors: "video:
/// no streams" (empty store), "video: bad frame track" (inconsistent
/// frame), "video: too many streams". Complexity O(total payload bytes).
pub fn avi_mux(s: &VideoStream) -> Result[Vec[UInt8], Str] {
  let ntrk = video_track_count(s);
  if ntrk <= 0 { return _err_bytes("video: no streams"); }
  if ntrk > VIDEO_MAX_TRACKS { return _err_bytes("video: too many streams"); }
  let nframes = video_frame_count(s);

  // Main header: micros/frame and total length come from the tracks.
  var avih = Vec[UInt8].new();
  var micros = 0;
  var max_len = 0;
  var w = video_stream_width(s);
  var h = video_stream_height(s);
  var have_video = false;
  var t = 0;
  while t < ntrk {
    let len = video_track_length(s, t);
    if len > max_len { max_len = len; }
    if !have_video && video_track_kind(s, t) == VIDEO_KIND_VIDEO {
      let sc = video_track_scale(s, t);
      let rt = video_track_rate(s, t);
      micros = video_rescale(1, sc, rt, 1, 1000000);
      if w == 0 { w = video_track_width(s, t); }
      if h == 0 { h = video_track_height(s, t); }
      have_video = true;
    }
    t = t + 1;
  }
  _push_u32le(&mut avih, micros);
  _push_u32le(&mut avih, 0);
  _push_u32le(&mut avih, 0);
  _push_u32le(&mut avih, VIDEO_AVI_HASINDEX);
  _push_u32le(&mut avih, max_len);
  _push_u32le(&mut avih, 0);
  _push_u32le(&mut avih, ntrk);
  _push_u32le(&mut avih, 0);
  _push_u32le(&mut avih, w);
  _push_u32le(&mut avih, h);
  _push_u32le(&mut avih, 0);
  _push_u32le(&mut avih, 0);
  _push_u32le(&mut avih, 0);
  _push_u32le(&mut avih, 0);

  var hdrl = Vec[UInt8].new();
  _push_chunk(&mut hdrl, VIDEO_FCC_AVIH, &avih);
  t = 0;
  while t < ntrk {
    let kind = video_track_kind(s, t);
    var strh = Vec[UInt8].new();
    _push_fcc(&mut strh, _handler_for_kind(kind));
    _push_u32le(&mut strh, video_track_codec(s, t));
    _push_u32le(&mut strh, 0);
    _push_u16le(&mut strh, 0);
    _push_u16le(&mut strh, 0);
    _push_u32le(&mut strh, 0);
    _push_u32le(&mut strh, video_track_scale(s, t));
    _push_u32le(&mut strh, video_track_rate(s, t));
    _push_u32le(&mut strh, 0);
    _push_u32le(&mut strh, video_track_length(s, t));
    _push_u32le(&mut strh, _track_max_frame(s, t));
    _push_u32le(&mut strh, 0);
    _push_u32le(&mut strh, 0);
    _push_u16le(&mut strh, 0);
    _push_u16le(&mut strh, 0);
    var rc_w = video_track_width(s, t);
    var rc_h = video_track_height(s, t);
    if rc_w < 0 { rc_w = 0; }
    if rc_h < 0 { rc_h = 0; }
    if rc_w > 65535 { rc_w = 65535; }
    if rc_h > 65535 { rc_h = 65535; }
    _push_u16le(&mut strh, rc_w);
    _push_u16le(&mut strh, rc_h);

    var strf = Vec[UInt8].new();
    if kind == VIDEO_KIND_AUDIO {
      let codec = video_track_codec(s, t);
      var ch = video_track_channels(s, t);
      if ch <= 0 { ch = 1; }
      let sr = video_track_sample_rate(s, t);
      _push_u16le(&mut strf, codec);
      _push_u16le(&mut strf, ch);
      _push_u32le(&mut strf, sr);
      _push_u32le(&mut strf, sr * ch * 2);
      _push_u16le(&mut strf, ch * 2);
      _push_u16le(&mut strf, 16);
      _push_u16le(&mut strf, 0);
    } else {
      var bw = video_track_width(s, t);
      var bh = video_track_height(s, t);
      if bw < 0 { bw = 0; }
      if bh < 0 { bh = 0; }
      _push_u32le(&mut strf, 40);
      _push_u32le(&mut strf, bw);
      _push_u32le(&mut strf, bh);
      _push_u16le(&mut strf, 1);
      _push_u16le(&mut strf, 24);
      _push_u32le(&mut strf, video_track_codec(s, t));
      _push_u32le(&mut strf, 0);
      _push_u32le(&mut strf, 0);
      _push_u32le(&mut strf, 0);
      _push_u32le(&mut strf, 0);
      _push_u32le(&mut strf, 0);
    }
    var strl = Vec[UInt8].new();
    _push_chunk(&mut strl, VIDEO_FCC_STRH, &strh);
    _push_chunk(&mut strl, VIDEO_FCC_STRF, &strf);
    _push_list(&mut hdrl, VIDEO_FCC_STRL, &strl);
    t = t + 1;
  }

  // movi chunks plus the idx1 entries (dwOffset is relative to the 'movi'
  // FourCC, so the first chunk after the 'movi' type field is 4).
  var movi = Vec[UInt8].new();
  var idx = Vec[UInt8].new();
  var f = 0;
  while f < nframes {
    let tr = video_frame_track(s, f);
    if tr < 0 { return _err_bytes("video: bad frame track"); }
    let payload = video_frame_data(s, f);
    let ckid = _chunk_id_for(tr, video_track_kind(s, tr));
    let dw_off = movi.len() + 4;
    _push_chunk(&mut movi, ckid, &payload);
    _push_fcc(&mut idx, ckid);
    var fl = 0;
    if video_frame_is_key(s, f) == 1 { fl = VIDEO_AVI_KEYFRAME; }
    _push_u32le(&mut idx, fl);
    _push_u32le(&mut idx, dw_off);
    _push_u32le(&mut idx, payload.len());
    f = f + 1;
  }

  var body = Vec[UInt8].new();
  _push_fcc(&mut body, VIDEO_FCC_AVI);
  _push_list(&mut body, VIDEO_FCC_HDRL, &hdrl);
  _push_list(&mut body, VIDEO_FCC_MOVI, &movi);
  _push_chunk(&mut body, VIDEO_FCC_IDX1, &idx);
  var out = Vec[UInt8].new();
  _push_fcc(&mut out, VIDEO_FCC_RIFF);
  _push_u32le(&mut out, body.len());
  _push_bytes(&mut out, &body);
  return _ok_bytes(out);
}
