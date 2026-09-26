// XIOM -- xiom.mkv: Matroska/WebM (EBML) container reader
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Scope: parse (never write, never mux) the Matroska/WebM EBML container
// layout down to the EBML header, the Segment's Info and Tracks elements and
// the spans of the Segment's top-level Clusters. EBML element IDs and sizes
// are variable-length integers (VINTs): an ID keeps its marker bits (the
// classic table value, e.g. Segment 0x18538067), while a size strips them.
// A size whose data bits are all ones is the EBML "unknown size" sentinel and
// is reported as -1. VINTs wider than 8 bytes (first byte 0x00) and IDs whose
// data bits are all zero (the reserved encoding of every width) are rejected.
//
// The parsed file is a flat store (MkvFile) built from parallel vectors:
// header fields, the first Segment's offset/size, Info fields, one entry per
// TrackEntry and one span per top-level Cluster. Cluster payloads (frames)
// are never decoded: a sized Cluster is skipped by its declared size, and an
// unknown-size Cluster is skipped to the next recognised Segment-level
// element ID whose own size vint validates (a bounded heuristic documented in
// SPEC.md), falling back to the end of the Segment or buffer.
//
// v0.61.3 notes that shaped this module:
//   * free functions only, no self methods; no Vec[StructType] anywhere --
//     every pool is a parallel Vec field and accessors guard the lengths.
//   * Ok/Err construction is confined to the tiny leaf helpers below
//     (including the small internal MkvElem cursor struct).
//   * every byte read is widened with `(data[pos] as Int) & 0xFF`; UInt8
//     values are never compared against Int constants without widening.
//   * Vec reads are bound to typed locals before use; Str values are never
//     compared with `==` (xiom.string.compare.str_compare instead).
//   * EBML Float values are decoded with integer arithmetic into milli-units
//     (value * 1000, rounded half away from zero); no Float64 is stored and
//     no Vec[Float64] exists.
//   * text fields are validated as UTF-8 with xiom.utf8 before
//     xiom.string.builder.sb_to_str is called, and NUL bytes are rejected, so
//     the builder never sees a byte range that can abort.
// See SPEC.md for the byte layouts, validation policies, error catalog and
// test plan.

module xiom.mkv

use xiom.string.builder;
use xiom.string.compare;
use xiom.utf8;

// --------------------------------------------------
//  Element IDs (marker bits kept, as stored)
// --------------------------------------------------

/// EBML Header element ID (0x1A45DFA3).
pub const MKV_EBML_ID: Int = 0x1A45DFA3;
/// Segment element ID (0x18538067).
pub const MKV_SEGMENT_ID: Int = 0x18538067;
/// SeekHead element ID (0x114D9B74).
pub const MKV_SEEKHEAD_ID: Int = 0x114D9B74;
/// Info element ID (0x1549A966).
pub const MKV_INFO_ID: Int = 0x1549A966;
/// Tracks element ID (0x1654AE6B).
pub const MKV_TRACKS_ID: Int = 0x1654AE6B;
/// Cues element ID (0x1C53BB6B).
pub const MKV_CUES_ID: Int = 0x1C53BB6B;
/// Attachments element ID (0x1941A469).
pub const MKV_ATTACHMENTS_ID: Int = 0x1941A469;
/// Chapters element ID (0x1043A770).
pub const MKV_CHAPTERS_ID: Int = 0x1043A770;
/// Tags element ID (0x1254C367).
pub const MKV_TAGS_ID: Int = 0x1254C367;
/// Cluster element ID (0x1F43B675).
pub const MKV_CLUSTER_ID: Int = 0x1F43B675;
/// Void element ID (0xEC).
pub const MKV_VOID_ID: Int = 0xEC;
/// CRC-32 element ID (0xBF).
pub const MKV_CRC32_ID: Int = 0xBF;

/// TrackEntry element ID (0xAE).
pub const MKV_TRACK_ENTRY_ID: Int = 0xAE;
/// Video element ID (0xE0).
pub const MKV_VIDEO_ID: Int = 0xE0;
/// Audio element ID (0xE1).
pub const MKV_AUDIO_ID: Int = 0xE1;

/// EBMLVersion element ID (0x4286).
pub const MKV_EBML_VERSION_ID: Int = 0x4286;
/// EBMLReadVersion element ID (0x42F7).
pub const MKV_EBML_READ_VERSION_ID: Int = 0x42F7;
/// EBMLMaxIDLength element ID (0x42F2).
pub const MKV_EBML_MAX_ID_LENGTH_ID: Int = 0x42F2;
/// EBMLMaxSizeLength element ID (0x42F3).
pub const MKV_EBML_MAX_SIZE_LENGTH_ID: Int = 0x42F3;
/// DocType element ID (0x4282).
pub const MKV_DOCTYPE_ID: Int = 0x4282;
/// DocTypeVersion element ID (0x4287).
pub const MKV_DOCTYPE_VERSION_ID: Int = 0x4287;
/// DocTypeReadVersion element ID (0x4288).
pub const MKV_DOCTYPE_READ_VERSION_ID: Int = 0x4288;

/// TimestampScale element ID (0x2AD7B1).
pub const MKV_TIMESTAMP_SCALE_ID: Int = 0x2AD7B1;
/// Duration element ID (0x4489).
pub const MKV_DURATION_ID: Int = 0x4489;
/// MuxingApp element ID (0x4D80).
pub const MKV_MUXING_APP_ID: Int = 0x4D80;
/// WritingApp element ID (0x5741).
pub const MKV_WRITING_APP_ID: Int = 0x5741;
/// Title element ID (0x7BA9).
pub const MKV_TITLE_ID: Int = 0x7BA9;

/// TrackNumber element ID (0xD7).
pub const MKV_TRACK_NUMBER_ID: Int = 0xD7;
/// TrackUID element ID (0x73C5).
pub const MKV_TRACK_UID_ID: Int = 0x73C5;
/// TrackType element ID (0x83).
pub const MKV_TRACK_TYPE_ID: Int = 0x83;
/// CodecID element ID (0x86).
pub const MKV_CODEC_ID_ID: Int = 0x86;
/// Name element ID (0x536E).
pub const MKV_TRACK_NAME_ID: Int = 0x536E;
/// Language element ID (0x22B59C).
pub const MKV_LANGUAGE_ID: Int = 0x22B59C;
/// LanguageIETF element ID (0x22B59D).
pub const MKV_LANGUAGE_IETF_ID: Int = 0x22B59D;
/// Video PixelWidth element ID (0xB0).
pub const MKV_PIXEL_WIDTH_ID: Int = 0xB0;
/// Video PixelHeight element ID (0xBA).
pub const MKV_PIXEL_HEIGHT_ID: Int = 0xBA;
/// Audio SamplingFrequency element ID (0xB5).
pub const MKV_SAMPLING_FREQUENCY_ID: Int = 0xB5;
/// Audio Channels element ID (0x9F).
pub const MKV_CHANNELS_ID: Int = 0x9F;

/// TrackType 1: video.
pub const MKV_TRACK_TYPE_VIDEO: Int = 1;
/// TrackType 2: audio.
pub const MKV_TRACK_TYPE_AUDIO: Int = 2;
/// TrackType 3: complex (e.g. a muxed or subtitled stream).
pub const MKV_TRACK_TYPE_COMPLEX: Int = 3;
/// TrackType 17: subtitle.
pub const MKV_TRACK_TYPE_SUBTITLE: Int = 17;

/// Value reported for an EBML element whose size is the all-ones
/// "unknown size" encoding.
pub const MKV_SIZE_UNKNOWN: Int = -1;

// --------------------------------------------------
//  Parsed file store
// --------------------------------------------------

/// Flat Matroska/WebM store. Header, Segment and Info fields are scalars (all
/// -1 / "" defaults when the element is absent; TimestampScale defaults to
/// 1000000). Track and Cluster entries are held in parallel vectors, one
/// entry per item in document order (no Vec[StructType]):
///   * track: `trk_offsets` (offset of the TrackEntry element ID),
///     `trk_numbers`, `trk_uids`, `trk_types`, `trk_codec_ids`, `trk_names`,
///     `trk_languages`, `trk_language_ietfs`, `trk_video_widths`,
///     `trk_video_heights`, `trk_audio_sampling_millihz` (SamplingFrequency
///     times 1000, rounded half away from zero; 0 when absent) and
///     `trk_audio_channels`.
///   * cluster: `cls_offsets` (offset of the Cluster element ID),
///     `cls_data_offsets`, `cls_sizes` (declared size, -1 unknown),
///     `cls_end_offsets` (exclusive end of the Cluster) and `cls_unknown`
///     (1 when the declared size was the unknown-size encoding).
/// Fields are implementation details; callers must go through the free
/// functions below.
pub type MkvFile = {
  segment_offset: Int;
  segment_size: Int;
  ebml_version: Int;
  ebml_read_version: Int;
  ebml_max_id_length: Int;
  ebml_max_size_length: Int;
  doctype: Str;
  doctype_version: Int;
  doctype_read_version: Int;
  info_offset: Int;
  timestamp_scale: Int;
  duration_units_milli: Int;
  muxing_app: Str;
  writing_app: Str;
  title: Str;
  trk_offsets: Vec[Int];
  trk_numbers: Vec[Int];
  trk_uids: Vec[Int];
  trk_types: Vec[Int];
  trk_codec_ids: Vec[Str];
  trk_names: Vec[Str];
  trk_languages: Vec[Str];
  trk_language_ietfs: Vec[Str];
  trk_video_widths: Vec[Int];
  trk_video_heights: Vec[Int];
  trk_audio_sampling_millihz: Vec[Int];
  trk_audio_channels: Vec[Int];
  cls_offsets: Vec[Int];
  cls_data_offsets: Vec[Int];
  cls_sizes: Vec[Int];
  cls_end_offsets: Vec[Int];
  cls_unknown: Vec[Int];
}

// --------------------------------------------------
//  Result leaf constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[MkvFile, Str].
fn _ok_file(v: MkvFile) -> Result[MkvFile, Str] {
  return Ok(v);
}

// Err(m) for Result[MkvFile, Str].
fn _err_file(m: Str) -> Result[MkvFile, Str] {
  return Err(m);
}

// Ok(v) for Result[Int, Str].
fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

// Err(m) for Result[Int, Str].
fn _err_int(m: Str) -> Result[Int, Str] {
  return Err(m);
}

// Ok(v) for Result[Str, Str].
fn _ok_str(v: Str) -> Result[Str, Str] {
  return Ok(v);
}

// Err(m) for Result[Str, Str].
fn _err_str(m: Str) -> Result[Str, Str] {
  return Err(m);
}

// Ok(()) for Result[Unit, Str].
fn _ok_unit() -> Result[Unit, Str] {
  return Ok(());
}

// Err(m) for Result[Unit, Str].
fn _err_unit(m: Str) -> Result[Unit, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Internal byte helpers
// --------------------------------------------------

// Byte at `pos` widened to an Int (0..255); callers guarantee the bounds.
fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// Unsigned big-endian Int of the `width` bytes at `pos` (width 0..8; width 0
// yields 0). The caller guarantees pos + width <= data.len(). Values with bit
// 63 set wrap to the same two's-complement bit pattern.
fn _read_be(data: &Vec[UInt8], pos: Int, width: Int) -> Int {
  var v: Int = 0;
  var i = 0;
  while i < width {
    let b: UInt8 = data[pos + i];
    v = v * 256 + ((b as Int) & 0xFF);
    i = i + 1;
  }
  return v;
}

// --------------------------------------------------
//  EBML VINTs
// --------------------------------------------------

// Width in bytes of the VINT whose first byte is `b` (1..8); 0 when `b` is
// 0x00, i.e. an encoding wider than 8 bytes, which EBML forbids.
fn _vint_width_of(b: Int) -> Int {
  if b == 0 { return 0; }
  if b >= 128 { return 1; }
  if b >= 64 { return 2; }
  if b >= 32 { return 3; }
  if b >= 16 { return 4; }
  if b >= 8 { return 5; }
  if b >= 4 { return 6; }
  if b >= 2 { return 7; }
  return 8;
}

// Numeric value of the marker bit alone for a VINT of `width` bytes:
// 2^(7 * width). Widths above 8 are never passed.
fn _marker_value(width: Int) -> Int {
  var m = 1;
  var i = 0;
  while i < 7 * width {
    m = m * 2;
    i = i + 1;
  }
  return m;
}

/// Byte width of the VINT at `pos` (1..8); 0 when `pos` is out of range or the
/// first byte is 0x00 (an encoding wider than 8 bytes). Complexity: O(1).
pub fn mkv_vint_width(data: &Vec[UInt8], pos: Int) -> Int {
  if pos < 0 || pos >= data.len() {
    return 0;
  }
  return _vint_width_of(_byte(data, pos));
}

/// Decode the element ID VINT at `pos`. The result keeps the marker bits
/// (the classic table value, e.g. 0x1A45DFA3 for the EBML header).
/// Err("mkv: truncated vint") when `pos` is out of range or the VINT runs
/// past the buffer; Err("mkv: invalid vint") for a first byte of 0x00 (more
/// than 8 bytes) or for the reserved encoding whose data bits are all zero
/// (0x80, 0x4000, 0x200000, ...). Complexity: O(1).
pub fn mkv_vint_id(data: &Vec[UInt8], pos: Int) -> Result[Int, Str] {
  if pos < 0 || pos >= data.len() {
    return _err_int("mkv: truncated vint");
  }
  let w = _vint_width_of(_byte(data, pos));
  if w == 0 {
    return _err_int("mkv: invalid vint");
  }
  if pos + w > data.len() {
    return _err_int("mkv: truncated vint");
  }
  let v = _read_be(data, pos, w);
  if v == _marker_value(w) {
    return _err_int("mkv: invalid vint");
  }
  return _ok_int(v);
}

/// Byte width of the element ID VINT at `pos`, validating the ID the same way
/// mkv_vint_id does. Err("mkv: truncated vint") /
/// Err("mkv: invalid vint") as for mkv_vint_id. Complexity: O(1).
pub fn mkv_vint_id_width(data: &Vec[UInt8], pos: Int) -> Result[Int, Str] {
  let r = mkv_vint_id(data, pos);
  if !r.is_ok {
    return _err_int(r.error);
  }
  return _ok_int(_vint_width_of(_byte(data, pos)));
}

/// Decode the element size VINT at `pos`. The marker bits are stripped; the
/// EBML unknown-size sentinel (all data bits one) is reported as
/// MKV_SIZE_UNKNOWN (-1). Err("mkv: truncated vint") when `pos` is out of
/// range or the VINT runs past the buffer; Err("mkv: invalid vint") for a
/// first byte of 0x00. Complexity: O(1).
pub fn mkv_vint_size(data: &Vec[UInt8], pos: Int) -> Result[Int, Str] {
  if pos < 0 || pos >= data.len() {
    return _err_int("mkv: truncated vint");
  }
  let w = _vint_width_of(_byte(data, pos));
  if w == 0 {
    return _err_int("mkv: invalid vint");
  }
  if pos + w > data.len() {
    return _err_int("mkv: truncated vint");
  }
  let marker = _marker_value(w);
  let bits = _read_be(data, pos, w) - marker;
  if bits == marker - 1 {
    return _ok_int(MKV_SIZE_UNKNOWN);
  }
  return _ok_int(bits);
}

/// Byte width of the element size VINT at `pos`, validating it the same way
/// mkv_vint_size does (an unknown-size VINT has a valid width).
/// Err("mkv: truncated vint") / Err("mkv: invalid vint") as for
/// mkv_vint_size. Complexity: O(1).
pub fn mkv_vint_size_width(data: &Vec[UInt8], pos: Int) -> Result[Int, Str] {
  let r = mkv_vint_size(data, pos);
  if !r.is_ok {
    return _err_int(r.error);
  }
  return _ok_int(_vint_width_of(_byte(data, pos)));
}

// --------------------------------------------------
//  Element cursor
// --------------------------------------------------

// One decoded element header. Private: callers use the public API.
type MkvElem = {
  id: Int;
  id_width: Int;
  size: Int;
  size_width: Int;
  data_off: Int;
}

// Ok(v) for Result[MkvElem, Str].
fn _ok_elem(v: MkvElem) -> Result[MkvElem, Str] {
  return Ok(v);
}

// Err(m) for Result[MkvElem, Str].
fn _err_elem(m: Str) -> Result[MkvElem, Str] {
  return Err(m);
}

// Decode the element header at `pos` inside the container [.., limit):
// `limit` is the exclusive end of the enclosing element or buffer. `size` is
// the declared size with the unknown-size sentinel preserved as -1.
// Err("mkv: truncated element") when the ID or size VINT would cross `limit`;
// VINT errors are propagated. Complexity: O(1).
fn _element(data: &Vec[UInt8], pos: Int, limit: Int) -> Result[MkvElem, Str] {
  if pos < 0 || pos >= limit {
    return _err_elem("mkv: truncated element");
  }
  let idr = mkv_vint_id(data, pos);
  if !idr.is_ok {
    return _err_elem(idr.error);
  }
  let id: Int = idr.value;
  let idwr = mkv_vint_id_width(data, pos);
  if !idwr.is_ok {
    return _err_elem(idwr.error);
  }
  let idw: Int = idwr.value;
  if pos + idw > limit {
    return _err_elem("mkv: truncated element");
  }
  let sr = mkv_vint_size(data, pos + idw);
  if !sr.is_ok {
    return _err_elem(sr.error);
  }
  let size: Int = sr.value;
  let swr = mkv_vint_size_width(data, pos + idw);
  if !swr.is_ok {
    return _err_elem(swr.error);
  }
  let sw: Int = swr.value;
  if pos + idw + sw > limit {
    return _err_elem("mkv: truncated element");
  }
  let e = MkvElem{
    id: id;
    id_width: idw;
    size: size;
    size_width: sw;
    data_off: pos + idw + sw;
  };
  return _ok_elem(e);
}

// --------------------------------------------------
//  Element value readers
// --------------------------------------------------

// Unsigned integer element value of `size` bytes (0..8; 0 yields 0).
// Err("mkv: bad integer width") when `size` is negative or above 8.
fn _uint_field(data: &Vec[UInt8], off: Int, size: Int) -> Result[Int, Str] {
  if size < 0 || size > 8 {
    return _err_int("mkv: bad integer width");
  }
  return _ok_int(_read_be(data, off, size));
}

// A value of `sig * 2^e` scaled to milli-units (times 1000), rounded half
// away from zero. `sig` is a positive significand; `e` is a negative or
// positive power of two. Magnitudes below 0.0005 decode to 0.
// Err("mkv: float overflow") when scaling would leave the signed Int range.
fn _scale_milli(sig: Int, e: Int) -> Result[Int, Str] {
  var n = sig * 1000;
  var k = e;
  if k >= 0 {
    while k > 0 {
      if n > 4611686018427387903 {
        return _err_int("mkv: float overflow");
      }
      n = n * 2;
      k = k - 1;
    }
    return _ok_int(n);
  }
  let s = 0 - k;
  if s >= 63 {
    return _ok_int(0);
  }
  var d = 1;
  var i = 0;
  while i < s {
    d = d * 2;
    i = i + 1;
  }
  let q = n / d;
  let r = n % d;
  if r * 2 >= d {
    return _ok_int(q + 1);
  }
  return _ok_int(q);
}

// Decode an EBML Float element of `size` bytes (0, 4 or 8) at `off` into
// milli-units (value * 1000, rounded half away from zero). A zero-length
// Float is 0. Denormals and values below 0.0005 are 0; an all-ones exponent
// (infinity or NaN) is Err("mkv: bad float"); any other width is
// Err("mkv: bad float") as well.
fn _float_milli(data: &Vec[UInt8], off: Int, size: Int) -> Result[Int, Str] {
  if size == 0 {
    return _ok_int(0);
  }
  if size == 4 {
    let b0 = _byte(data, off);
    let b1 = _byte(data, off + 1);
    let b2 = _byte(data, off + 2);
    let b3 = _byte(data, off + 3);
    let exp = (b0 % 128) * 2 + b1 / 128;
    let mant = (b1 % 128) * 65536 + b2 * 256 + b3;
    if exp == 255 {
      return _err_int("mkv: bad float");
    }
    if exp == 0 {
      return _ok_int(0);
    }
    let mr = _scale_milli(8388608 + mant, exp - 127 - 23);
    if !mr.is_ok {
      return _err_int(mr.error);
    }
    let mag: Int = mr.value;
    if b0 >= 128 {
      return _ok_int(0 - mag);
    }
    return _ok_int(mag);
  }
  if size == 8 {
    let b0 = _byte(data, off);
    let b1 = _byte(data, off + 1);
    let exp = (b0 % 128) * 16 + b1 / 16;
    var mant = b1 % 16;
    var i = 2;
    while i < 8 {
      mant = mant * 256 + _byte(data, off + i);
      i = i + 1;
    }
    if exp == 2047 {
      return _err_int("mkv: bad float");
    }
    if exp == 0 {
      return _ok_int(0);
    }
    let mr = _scale_milli(4503599627370496 + mant, exp - 1023 - 52);
    if !mr.is_ok {
      return _err_int(mr.error);
    }
    let mag: Int = mr.value;
    if b0 >= 128 {
      return _ok_int(0 - mag);
    }
    return _ok_int(mag);
  }
  return _err_int("mkv: bad float");
}

// Copy data[off, off + len) into a fresh Str after validating it: the span
// must be in bounds, contain no 0x00 byte (sb_to_str aborts on NUL) and be
// well-formed UTF-8 (xiom.utf8.utf8_validate). Err("mkv: truncated element")
// when the span is out of bounds; Err("mkv: bad text field") when the span
// holds a NUL or invalid UTF-8. Complexity: O(len).
fn _text(data: &Vec[UInt8], off: Int, len: Int) -> Result[Str, Str] {
  if off < 0 || len < 0 || off + len > data.len() {
    return _err_str("mkv: truncated element");
  }
  var bytes = Vec[UInt8].new();
  var i = 0;
  while i < len {
    let b: Int = _byte(data, off + i);
    if b == 0 {
      return _err_str("mkv: bad text field");
    }
    bytes.push(b as UInt8);
    i = i + 1;
  }
  if !utf8.utf8_validate(&bytes) {
    return _err_str("mkv: bad text field");
  }
  let s = builder.sb_to_str(&bytes);
  return _ok_str(s);
}

// --------------------------------------------------
//  Unknown-size Cluster boundary heuristic
// --------------------------------------------------

// True when `id` is an element this module recognises at Segment level. Used
// only to find the end of an unknown-size Cluster.
fn _is_top_level_id(id: Int) -> Bool {
  if id == MKV_SEEKHEAD_ID { return true; }
  if id == MKV_INFO_ID { return true; }
  if id == MKV_TRACKS_ID { return true; }
  if id == MKV_CLUSTER_ID { return true; }
  if id == MKV_CUES_ID { return true; }
  if id == MKV_ATTACHMENTS_ID { return true; }
  if id == MKV_CHAPTERS_ID { return true; }
  if id == MKV_TAGS_ID { return true; }
  if id == MKV_VOID_ID { return true; }
  if id == MKV_CRC32_ID { return true; }
  return false;
}

// Scan [from, limit) for the next recognised Segment-level element ID whose
// ID and size VINTs parse and whose declared size fits the remaining region
// (an unknown-size candidate is accepted as-is). Returns the offset or -1
// when none is found. This is the documented heuristic for ending an
// unknown-size Cluster: a false positive inside frame bytes can truncate the
// reported Cluster span early. Complexity: O(limit - from).
fn _scan_next_top_level(data: &Vec[UInt8], from: Int, limit: Int) -> Int {
  var p = from;
  while p < limit {
    let b: Int = _byte(data, p);
    if b != 0 {
      let idr = mkv_vint_id(data, p);
      if idr.is_ok {
        let id: Int = idr.value;
        if _is_top_level_id(id) {
          let wr = mkv_vint_id_width(data, p);
          if wr.is_ok {
            let idw: Int = wr.value;
            if p + idw < limit {
              let sr = mkv_vint_size(data, p + idw);
              if sr.is_ok {
                let sz: Int = sr.value;
                let swr = mkv_vint_size_width(data, p + idw);
                if swr.is_ok {
                  let sw: Int = swr.value;
                  if p + idw + sw <= limit {
                    if sz < 0 {
                      return p;
                    }
                    if p + idw + sw + sz <= limit {
                      return p;
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
    p = p + 1;
  }
  return -1;
}

// --------------------------------------------------
//  TrackEntry parsing
// --------------------------------------------------

// Parse one TrackEntry body [start, end) and append one entry to every track
// pool (all pushes happen together at the end, so parallel vectors cannot
// drift on error). Unknown child elements are skipped by size; Video and
// Audio are containers walked one level deep for PixelWidth/PixelHeight and
// SamplingFrequency/Channels. A TrackNumber of 0 (absent or zero) is
// Err("mkv: bad track number"). Err("mkv: unknown-size element") for any
// unknown-size child, Err("mkv: truncated element") for a child that crosses
// `end`, and reader errors as documented on the readers.
fn _parse_track_entry(data: &Vec[UInt8], entry_offset: Int, start: Int, end: Int,
                      trk_offsets: &mut Vec[Int], trk_numbers: &mut Vec[Int],
                      trk_uids: &mut Vec[Int], trk_types: &mut Vec[Int],
                      trk_codec_ids: &mut Vec[Str], trk_names: &mut Vec[Str],
                      trk_languages: &mut Vec[Str], trk_language_ietfs: &mut Vec[Str],
                      trk_video_widths: &mut Vec[Int], trk_video_heights: &mut Vec[Int],
                      trk_audio_sampling_millihz: &mut Vec[Int],
                      trk_audio_channels: &mut Vec[Int]) -> Result[Unit, Str] {
  var number = 0;
  var uid = 0;
  var ttype = 0;
  var codec = "";
  var name = "";
  var language = "";
  var language_ietf = "";
  var vwidth = 0;
  var vheight = 0;
  var sampling = 0;
  var channels = 0;
  var pos = start;
  while pos < end {
    let er = _element(data, pos, end);
    if !er.is_ok { return _err_unit(er.error); }
    let e = er.value;
    let id: Int = e.id;
    let size: Int = e.size;
    let dstart: Int = e.data_off;
    if size < 0 { return _err_unit("mkv: unknown-size element"); }
    let dend = dstart + size;
    if dend > end { return _err_unit("mkv: truncated element"); }
    if id == MKV_TRACK_NUMBER_ID {
      let r = _uint_field(data, dstart, size);
      if !r.is_ok { return _err_unit(r.error); }
      number = r.value;
    } elif id == MKV_TRACK_UID_ID {
      let r = _uint_field(data, dstart, size);
      if !r.is_ok { return _err_unit(r.error); }
      uid = r.value;
    } elif id == MKV_TRACK_TYPE_ID {
      let r = _uint_field(data, dstart, size);
      if !r.is_ok { return _err_unit(r.error); }
      ttype = r.value;
    } elif id == MKV_CODEC_ID_ID {
      let r = _text(data, dstart, size);
      if !r.is_ok { return _err_unit(r.error); }
      codec = r.value;
    } elif id == MKV_TRACK_NAME_ID {
      let r = _text(data, dstart, size);
      if !r.is_ok { return _err_unit(r.error); }
      name = r.value;
    } elif id == MKV_LANGUAGE_ID {
      let r = _text(data, dstart, size);
      if !r.is_ok { return _err_unit(r.error); }
      language = r.value;
    } elif id == MKV_LANGUAGE_IETF_ID {
      let r = _text(data, dstart, size);
      if !r.is_ok { return _err_unit(r.error); }
      language_ietf = r.value;
    } elif id == MKV_VIDEO_ID {
      var vpos = dstart;
      while vpos < dend {
        let ve = _element(data, vpos, dend);
        if !ve.is_ok { return _err_unit(ve.error); }
        let v = ve.value;
        let vid: Int = v.id;
        let vsize: Int = v.size;
        let vstart: Int = v.data_off;
        if vsize < 0 { return _err_unit("mkv: unknown-size element"); }
        let vend = vstart + vsize;
        if vend > dend { return _err_unit("mkv: truncated element"); }
        if vid == MKV_PIXEL_WIDTH_ID {
          let r = _uint_field(data, vstart, vsize);
          if !r.is_ok { return _err_unit(r.error); }
          vwidth = r.value;
        } elif vid == MKV_PIXEL_HEIGHT_ID {
          let r = _uint_field(data, vstart, vsize);
          if !r.is_ok { return _err_unit(r.error); }
          vheight = r.value;
        }
        vpos = vend;
      }
    } elif id == MKV_AUDIO_ID {
      var apos = dstart;
      while apos < dend {
        let ae = _element(data, apos, dend);
        if !ae.is_ok { return _err_unit(ae.error); }
        let a = ae.value;
        let aid: Int = a.id;
        let asize: Int = a.size;
        let astart: Int = a.data_off;
        if asize < 0 { return _err_unit("mkv: unknown-size element"); }
        let aend = astart + asize;
        if aend > dend { return _err_unit("mkv: truncated element"); }
        if aid == MKV_SAMPLING_FREQUENCY_ID {
          let r = _float_milli(data, astart, asize);
          if !r.is_ok { return _err_unit(r.error); }
          sampling = r.value;
        } elif aid == MKV_CHANNELS_ID {
          let r = _uint_field(data, astart, asize);
          if !r.is_ok { return _err_unit(r.error); }
          channels = r.value;
        }
        apos = aend;
      }
    }
    pos = dend;
  }
  if number <= 0 {
    return _err_unit("mkv: bad track number");
  }
  trk_offsets.push(entry_offset);
  trk_numbers.push(number);
  trk_uids.push(uid);
  trk_types.push(ttype);
  trk_codec_ids.push(codec);
  trk_names.push(name);
  trk_languages.push(language);
  trk_language_ietfs.push(language_ietf);
  trk_video_widths.push(vwidth);
  trk_video_heights.push(vheight);
  trk_audio_sampling_millihz.push(sampling);
  trk_audio_channels.push(channels);
  return _ok_unit();
}

// --------------------------------------------------
//  Public API: sniff and parse
// --------------------------------------------------

/// True when `data` starts with the EBML header ID 0x1A45DFA3 (4 bytes) and
/// has at least one more byte. Only the ID is inspected; malformed bodies are
/// not detected here. Complexity: O(1).
pub fn mkv_is_file(data: &Vec[UInt8]) -> Bool {
  if data.len() < 5 {
    return false;
  }
  let r = mkv_vint_id(data, 0);
  if !r.is_ok {
    return false;
  }
  let id: Int = r.value;
  if id != MKV_EBML_ID {
    return false;
  }
  return true;
}

/// Parse a Matroska/WebM byte stream.
///
/// Layout walked: the EBML header (ID 0x1A45DFA3; its declared size must be
/// known and non-zero) with EBMLVersion, EBMLReadVersion, EBMLMaxIDLength,
/// EBMLMaxSizeLength, DocType, DocTypeVersion and DocTypeReadVersion; then
/// top-level Void elements followed by the Segment (ID 0x18538067, size may
/// be unknown). Inside the Segment, Info and Tracks are parsed, top-level
/// Cluster elements are recorded and skipped (never decoded), and all other
/// Segment-level elements (SeekHead, Cues, Attachments, Chapters, Tags, Void,
/// CRC-32 and unknown IDs) are skipped by declared size. Parsing stops after
/// the first Segment; trailing bytes are ignored.
///
/// Documented validation: DocType must be "matroska" or "webm"
/// (Err("mkv: bad doctype")); EBMLReadVersion must be 1
/// (Err("mkv: unsupported ebml version")); EBMLMaxIDLength must be 1..4 and
/// EBMLMaxSizeLength 1..8, both versions >= 1 and DocTypeVersion >=
/// DocTypeReadVersion (Err("mkv: bad ebml header")); an Info TimestampScale
/// of 0 is Err("mkv: bad timestamp scale"). A Segment-level element that runs
/// past the buffer, Segment or parent is Err("mkv: truncated element"); an
/// unknown-size VINT on anything but Segment or Cluster is
/// Err("mkv: unknown-size element"). The whole call is Err with one of the
/// documented messages and no partial store on any failure.
///
/// Complexity: O(data.len()) plus the unknown-size Cluster boundary scans.
pub fn mkv_parse(data: &Vec[UInt8]) -> Result[MkvFile, Str] {
  let n = data.len();

  // --- EBML header ---
  let hdr = _element(data, 0, n);
  if !hdr.is_ok { return _err_file(hdr.error); }
  let h = hdr.value;
  let head_id: Int = h.id;
  if head_id != MKV_EBML_ID {
    return _err_file("mkv: not an ebml stream");
  }
  let head_size: Int = h.size;
  let head_data: Int = h.data_off;
  if head_size <= 0 {
    return _err_file("mkv: bad ebml header size");
  }
  let head_end = head_data + head_size;
  if head_end > n {
    return _err_file("mkv: truncated element");
  }
  var ebml_version = 1;
  var ebml_read_version = 1;
  var ebml_max_id_length = 4;
  var ebml_max_size_length = 8;
  var doctype = "";
  var doctype_version = 1;
  var doctype_read_version = 1;
  var hpos = head_data;
  while hpos < head_end {
    let er = _element(data, hpos, head_end);
    if !er.is_ok { return _err_file(er.error); }
    let e = er.value;
    let id: Int = e.id;
    let size: Int = e.size;
    let dstart: Int = e.data_off;
    if size < 0 { return _err_file("mkv: unknown-size element"); }
    let dend = dstart + size;
    if dend > head_end { return _err_file("mkv: truncated element"); }
    if id == MKV_EBML_VERSION_ID {
      let r = _uint_field(data, dstart, size);
      if !r.is_ok { return _err_file(r.error); }
      ebml_version = r.value;
    } elif id == MKV_EBML_READ_VERSION_ID {
      let r = _uint_field(data, dstart, size);
      if !r.is_ok { return _err_file(r.error); }
      ebml_read_version = r.value;
    } elif id == MKV_EBML_MAX_ID_LENGTH_ID {
      let r = _uint_field(data, dstart, size);
      if !r.is_ok { return _err_file(r.error); }
      ebml_max_id_length = r.value;
    } elif id == MKV_EBML_MAX_SIZE_LENGTH_ID {
      let r = _uint_field(data, dstart, size);
      if !r.is_ok { return _err_file(r.error); }
      ebml_max_size_length = r.value;
    } elif id == MKV_DOCTYPE_ID {
      let r = _text(data, dstart, size);
      if !r.is_ok { return _err_file(r.error); }
      doctype = r.value;
    } elif id == MKV_DOCTYPE_VERSION_ID {
      let r = _uint_field(data, dstart, size);
      if !r.is_ok { return _err_file(r.error); }
      doctype_version = r.value;
    } elif id == MKV_DOCTYPE_READ_VERSION_ID {
      let r = _uint_field(data, dstart, size);
      if !r.is_ok { return _err_file(r.error); }
      doctype_read_version = r.value;
    }
    hpos = dend;
  }
  if ebml_version < 1 { return _err_file("mkv: bad ebml header"); }
  if ebml_read_version != 1 { return _err_file("mkv: unsupported ebml version"); }
  if ebml_max_id_length < 1 || ebml_max_id_length > 4 { return _err_file("mkv: bad ebml header"); }
  if ebml_max_size_length < 1 || ebml_max_size_length > 8 { return _err_file("mkv: bad ebml header"); }
  if doctype_version < 1 { return _err_file("mkv: bad ebml header"); }
  if doctype_read_version < 1 { return _err_file("mkv: bad ebml header"); }
  if doctype_read_version > doctype_version { return _err_file("mkv: bad ebml header"); }
  let is_matroska = compare.str_compare(doctype, "matroska");
  let is_webm = compare.str_compare(doctype, "webm");
  if is_matroska != 0 && is_webm != 0 {
    return _err_file("mkv: bad doctype");
  }

  // --- top level: Void* then Segment ---
  var segment_offset = -1;
  var segment_size = -1;
  var segment_data = -1;
  var tpos = head_end;
  while tpos < n {
    let er = _element(data, tpos, n);
    if !er.is_ok { return _err_file(er.error); }
    let e = er.value;
    let id: Int = e.id;
    let size: Int = e.size;
    let dstart: Int = e.data_off;
    if id == MKV_SEGMENT_ID {
      segment_offset = tpos;
      segment_size = size;
      segment_data = dstart;
      tpos = n;
    } elif id == MKV_VOID_ID {
      if size < 0 { return _err_file("mkv: unknown-size element"); }
      let dend = dstart + size;
      if dend > n { return _err_file("mkv: truncated element"); }
      tpos = dend;
    } else {
      return _err_file("mkv: segment not found");
    }
  }
  if segment_offset < 0 {
    return _err_file("mkv: segment not found");
  }

  // --- Segment ---
  var segment_end = n;
  if segment_size >= 0 {
    segment_end = segment_data + segment_size;
    if segment_end > n { return _err_file("mkv: truncated segment"); }
  }
  var info_offset = -1;
  var timestamp_scale = 1000000;
  var duration_units_milli = -1;
  var muxing_app = "";
  var writing_app = "";
  var title = "";
  var trk_offsets = Vec[Int].new();
  var trk_numbers = Vec[Int].new();
  var trk_uids = Vec[Int].new();
  var trk_types = Vec[Int].new();
  var trk_codec_ids = Vec[Str].new();
  var trk_names = Vec[Str].new();
  var trk_languages = Vec[Str].new();
  var trk_language_ietfs = Vec[Str].new();
  var trk_video_widths = Vec[Int].new();
  var trk_video_heights = Vec[Int].new();
  var trk_audio_sampling_millihz = Vec[Int].new();
  var trk_audio_channels = Vec[Int].new();
  var cls_offsets = Vec[Int].new();
  var cls_data_offsets = Vec[Int].new();
  var cls_sizes = Vec[Int].new();
  var cls_end_offsets = Vec[Int].new();
  var cls_unknown = Vec[Int].new();
  var spos = segment_data;
  while spos < segment_end {
    let er = _element(data, spos, segment_end);
    if !er.is_ok { return _err_file(er.error); }
    let e = er.value;
    let id: Int = e.id;
    let size: Int = e.size;
    let dstart: Int = e.data_off;
    if id == MKV_CLUSTER_ID {
      if size < 0 {
        let bound = _scan_next_top_level(data, dstart, segment_end);
        var cend = segment_end;
        if bound >= 0 { cend = bound; }
        cls_offsets.push(spos);
        cls_data_offsets.push(dstart);
        cls_sizes.push(MKV_SIZE_UNKNOWN);
        cls_end_offsets.push(cend);
        cls_unknown.push(1);
        spos = cend;
      } else {
        let dend = dstart + size;
        if dend > segment_end { return _err_file("mkv: truncated element"); }
        cls_offsets.push(spos);
        cls_data_offsets.push(dstart);
        cls_sizes.push(size);
        cls_end_offsets.push(dend);
        cls_unknown.push(0);
        spos = dend;
      }
    } elif id == MKV_INFO_ID {
      if size < 0 { return _err_file("mkv: unknown-size element"); }
      let dend = dstart + size;
      if dend > segment_end { return _err_file("mkv: truncated element"); }
      info_offset = spos;
      var ipos = dstart;
      while ipos < dend {
        let ie = _element(data, ipos, dend);
        if !ie.is_ok { return _err_file(ie.error); }
        let i = ie.value;
        let iid: Int = i.id;
        let isize: Int = i.size;
        let istart: Int = i.data_off;
        if isize < 0 { return _err_file("mkv: unknown-size element"); }
        let iend = istart + isize;
        if iend > dend { return _err_file("mkv: truncated element"); }
        if iid == MKV_TIMESTAMP_SCALE_ID {
          let r = _uint_field(data, istart, isize);
          if !r.is_ok { return _err_file(r.error); }
          let v: Int = r.value;
          if v == 0 { return _err_file("mkv: bad timestamp scale"); }
          timestamp_scale = v;
        } elif iid == MKV_DURATION_ID {
          let r = _float_milli(data, istart, isize);
          if !r.is_ok { return _err_file(r.error); }
          duration_units_milli = r.value;
        } elif iid == MKV_MUXING_APP_ID {
          let r = _text(data, istart, isize);
          if !r.is_ok { return _err_file(r.error); }
          muxing_app = r.value;
        } elif iid == MKV_WRITING_APP_ID {
          let r = _text(data, istart, isize);
          if !r.is_ok { return _err_file(r.error); }
          writing_app = r.value;
        } elif iid == MKV_TITLE_ID {
          let r = _text(data, istart, isize);
          if !r.is_ok { return _err_file(r.error); }
          title = r.value;
        }
        ipos = iend;
      }
      spos = dend;
    } elif id == MKV_TRACKS_ID {
      if size < 0 { return _err_file("mkv: unknown-size element"); }
      let dend = dstart + size;
      if dend > segment_end { return _err_file("mkv: truncated element"); }
      var tpos2 = dstart;
      while tpos2 < dend {
        let te = _element(data, tpos2, dend);
        if !te.is_ok { return _err_file(te.error); }
        let t = te.value;
        let tid: Int = t.id;
        let tsize: Int = t.size;
        let tstart: Int = t.data_off;
        if tsize < 0 { return _err_file("mkv: unknown-size element"); }
        let tend = tstart + tsize;
        if tend > dend { return _err_file("mkv: truncated element"); }
        if tid == MKV_TRACK_ENTRY_ID {
          let tr = _parse_track_entry(data, tpos2, tstart, tend,
            &mut trk_offsets, &mut trk_numbers, &mut trk_uids, &mut trk_types,
            &mut trk_codec_ids, &mut trk_names, &mut trk_languages,
            &mut trk_language_ietfs, &mut trk_video_widths, &mut trk_video_heights,
            &mut trk_audio_sampling_millihz, &mut trk_audio_channels);
          if !tr.is_ok { return _err_file(tr.error); }
        }
        tpos2 = tend;
      }
      spos = dend;
    } else {
      if size < 0 { return _err_file("mkv: unknown-size element"); }
      let dend = dstart + size;
      if dend > segment_end { return _err_file("mkv: truncated element"); }
      spos = dend;
    }
  }
  let f = MkvFile{
    segment_offset: segment_offset;
    segment_size: segment_size;
    ebml_version: ebml_version;
    ebml_read_version: ebml_read_version;
    ebml_max_id_length: ebml_max_id_length;
    ebml_max_size_length: ebml_max_size_length;
    doctype: doctype;
    doctype_version: doctype_version;
    doctype_read_version: doctype_read_version;
    info_offset: info_offset;
    timestamp_scale: timestamp_scale;
    duration_units_milli: duration_units_milli;
    muxing_app: muxing_app;
    writing_app: writing_app;
    title: title;
    trk_offsets: trk_offsets;
    trk_numbers: trk_numbers;
    trk_uids: trk_uids;
    trk_types: trk_types;
    trk_codec_ids: trk_codec_ids;
    trk_names: trk_names;
    trk_languages: trk_languages;
    trk_language_ietfs: trk_language_ietfs;
    trk_video_widths: trk_video_widths;
    trk_video_heights: trk_video_heights;
    trk_audio_sampling_millihz: trk_audio_sampling_millihz;
    trk_audio_channels: trk_audio_channels;
    cls_offsets: cls_offsets;
    cls_data_offsets: cls_data_offsets;
    cls_sizes: cls_sizes;
    cls_end_offsets: cls_end_offsets;
    cls_unknown: cls_unknown;
  };
  return _ok_file(f);
}

// --------------------------------------------------
//  Internal length guards
// --------------------------------------------------

// Smaller of two Ints.
fn _min_int(a: Int, b: Int) -> Int {
  if a < b { return a; }
  return b;
}

// Number of complete track entries: the minimum length across all track
// parallel vectors, so a (never expected) drift cannot cause an out-of-range
// read.
fn _track_len(p: &MkvFile) -> Int {
  var m = p.trk_numbers.len();
  m = _min_int(m, p.trk_offsets.len());
  m = _min_int(m, p.trk_uids.len());
  m = _min_int(m, p.trk_types.len());
  m = _min_int(m, p.trk_codec_ids.len());
  m = _min_int(m, p.trk_names.len());
  m = _min_int(m, p.trk_languages.len());
  m = _min_int(m, p.trk_language_ietfs.len());
  m = _min_int(m, p.trk_video_widths.len());
  m = _min_int(m, p.trk_video_heights.len());
  m = _min_int(m, p.trk_audio_sampling_millihz.len());
  m = _min_int(m, p.trk_audio_channels.len());
  return m;
}

// Number of complete cluster entries: the minimum length across all cluster
// parallel vectors.
fn _cluster_len(p: &MkvFile) -> Int {
  var m = p.cls_offsets.len();
  m = _min_int(m, p.cls_data_offsets.len());
  m = _min_int(m, p.cls_sizes.len());
  m = _min_int(m, p.cls_end_offsets.len());
  m = _min_int(m, p.cls_unknown.len());
  return m;
}

// --------------------------------------------------
//  Public API: EBML header fields
// --------------------------------------------------

/// Offset of the Segment element ID in the source buffer (always >= 5 after a
/// successful parse). Complexity: O(1).
pub fn mkv_segment_offset(p: &MkvFile) -> Int {
  return p.segment_offset;
}

/// Declared Segment size (without the ID/size header), or MKV_SIZE_UNKNOWN
/// (-1) when the Segment uses the unknown-size encoding. Complexity: O(1).
pub fn mkv_segment_size(p: &MkvFile) -> Int {
  return p.segment_size;
}

/// EBMLVersion (default 1 when absent). Complexity: O(1).
pub fn mkv_ebml_version(p: &MkvFile) -> Int {
  return p.ebml_version;
}

/// EBMLReadVersion (default 1; a parsed file always has 1, any other value is
/// rejected). Complexity: O(1).
pub fn mkv_ebml_read_version(p: &MkvFile) -> Int {
  return p.ebml_read_version;
}

/// EBMLMaxIDLength (default 4; validated to 1..4). Complexity: O(1).
pub fn mkv_ebml_max_id_length(p: &MkvFile) -> Int {
  return p.ebml_max_id_length;
}

/// EBMLMaxSizeLength (default 8; validated to 1..8). Complexity: O(1).
pub fn mkv_ebml_max_size_length(p: &MkvFile) -> Int {
  return p.ebml_max_size_length;
}

/// DocType: "matroska" or "webm" (a parsed file is always one of the two).
/// Complexity: O(1).
pub fn mkv_doctype(p: &MkvFile) -> Str {
  let v: Str = p.doctype;
  return v;
}

/// DocTypeVersion (default 1; validated >= DocTypeReadVersion).
/// Complexity: O(1).
pub fn mkv_doctype_version(p: &MkvFile) -> Int {
  return p.doctype_version;
}

/// DocTypeReadVersion (default 1; validated <= DocTypeVersion).
/// Complexity: O(1).
pub fn mkv_doctype_read_version(p: &MkvFile) -> Int {
  return p.doctype_read_version;
}

// --------------------------------------------------
//  Public API: Info
// --------------------------------------------------

/// Offset of the Info element ID, or -1 when the Segment has no Info element.
/// Complexity: O(1).
pub fn mkv_info_offset(p: &MkvFile) -> Int {
  return p.info_offset;
}

/// TimestampScale in nanoseconds per timestamp unit (default 1000000, i.e.
/// one millisecond; 0 is rejected). Complexity: O(1).
pub fn mkv_timestamp_scale(p: &MkvFile) -> Int {
  return p.timestamp_scale;
}

/// Duration as a fixed-point integer in units of 1/1000 timestamp unit
/// (Duration (float) * 1000, rounded half away from zero); -1 when the Info
/// element or the Duration element is absent. Complexity: O(1).
pub fn mkv_duration_milli_units(p: &MkvFile) -> Int {
  return p.duration_units_milli;
}

/// Duration converted to nanoseconds:
/// duration_milli_units * timestamp_scale / 1000 (truncating); -1 when the
/// Duration element is absent. Complexity: O(1).
pub fn mkv_duration_nanos(p: &MkvFile) -> Int {
  if p.duration_units_milli < 0 {
    return -1;
  }
  return p.duration_units_milli * p.timestamp_scale / 1000;
}

/// Duration converted to milliseconds:
/// duration_milli_units * timestamp_scale / 1000000 (truncating); -1 when the
/// Duration element is absent. Complexity: O(1).
pub fn mkv_duration_millis(p: &MkvFile) -> Int {
  if p.duration_units_milli < 0 {
    return -1;
  }
  return p.duration_units_milli * p.timestamp_scale / 1000000;
}

/// MuxingApp (UTF-8), "" when absent. Complexity: O(1).
pub fn mkv_muxing_app(p: &MkvFile) -> Str {
  let v: Str = p.muxing_app;
  return v;
}

/// WritingApp (UTF-8), "" when absent. Complexity: O(1).
pub fn mkv_writing_app(p: &MkvFile) -> Str {
  let v: Str = p.writing_app;
  return v;
}

/// Title (UTF-8), "" when absent. Complexity: O(1).
pub fn mkv_title(p: &MkvFile) -> Str {
  let v: Str = p.title;
  return v;
}

// --------------------------------------------------
//  Public API: Tracks
// --------------------------------------------------

/// Number of parsed TrackEntry records. Complexity: O(1).
pub fn mkv_track_count(p: &MkvFile) -> Int {
  return _track_len(p);
}

/// Offset of track `i`'s TrackEntry element ID; -1 when `i` is out of range.
/// Complexity: O(1).
pub fn mkv_track_offset(p: &MkvFile, i: Int) -> Int {
  if i < 0 || i >= _track_len(p) {
    return -1;
  }
  let v: Int = p.trk_offsets[i];
  return v;
}

/// TrackNumber of track `i` (validated nonzero during parse); -1 when `i` is
/// out of range. Complexity: O(1).
pub fn mkv_track_number(p: &MkvFile, i: Int) -> Int {
  if i < 0 || i >= _track_len(p) {
    return -1;
  }
  let v: Int = p.trk_numbers[i];
  return v;
}

/// TrackUID of track `i`; 0 when absent, -1 when `i` is out of range.
/// Complexity: O(1).
pub fn mkv_track_uid(p: &MkvFile, i: Int) -> Int {
  if i < 0 || i >= _track_len(p) {
    return -1;
  }
  let v: Int = p.trk_uids[i];
  return v;
}

/// TrackType of track `i`: 1 video, 2 audio, 3 complex, 17 subtitle (other
/// values are reported as stored; 0 when absent); -1 when `i` is out of
/// range. Complexity: O(1).
pub fn mkv_track_type(p: &MkvFile, i: Int) -> Int {
  if i < 0 || i >= _track_len(p) {
    return -1;
  }
  let v: Int = p.trk_types[i];
  return v;
}

/// CodecID of track `i`, "" when absent or `i` out of range. Complexity: O(1).
pub fn mkv_track_codec_id(p: &MkvFile, i: Int) -> Str {
  if i < 0 || i >= _track_len(p) {
    return "";
  }
  let v: Str = p.trk_codec_ids[i];
  return v;
}

/// Track Name of track `i`, "" when absent or `i` out of range.
/// Complexity: O(1).
pub fn mkv_track_name(p: &MkvFile, i: Int) -> Str {
  if i < 0 || i >= _track_len(p) {
    return "";
  }
  let v: Str = p.trk_names[i];
  return v;
}

/// Track Language (ISO 639-2) of track `i`, "" when absent or `i` out of
/// range. Complexity: O(1).
pub fn mkv_track_language(p: &MkvFile, i: Int) -> Str {
  if i < 0 || i >= _track_len(p) {
    return "";
  }
  let v: Str = p.trk_languages[i];
  return v;
}

/// Track LanguageIETF (BCP 47) of track `i`, "" when absent or `i` out of
/// range. Complexity: O(1).
pub fn mkv_track_language_ietf(p: &MkvFile, i: Int) -> Str {
  if i < 0 || i >= _track_len(p) {
    return "";
  }
  let v: Str = p.trk_language_ietfs[i];
  return v;
}

/// Video PixelWidth of track `i`; 0 when absent; -1 when `i` is out of range.
/// Complexity: O(1).
pub fn mkv_track_video_width(p: &MkvFile, i: Int) -> Int {
  if i < 0 || i >= _track_len(p) {
    return -1;
  }
  let v: Int = p.trk_video_widths[i];
  return v;
}

/// Video PixelHeight of track `i`; 0 when absent; -1 when `i` is out of
/// range. Complexity: O(1).
pub fn mkv_track_video_height(p: &MkvFile, i: Int) -> Int {
  if i < 0 || i >= _track_len(p) {
    return -1;
  }
  let v: Int = p.trk_video_heights[i];
  return v;
}

/// Audio SamplingFrequency of track `i` in milliHertz (the EBML Float value
/// times 1000, rounded half away from zero); 0 when absent; -1 when `i` is
/// out of range. Complexity: O(1).
pub fn mkv_track_audio_sampling_millihz(p: &MkvFile, i: Int) -> Int {
  if i < 0 || i >= _track_len(p) {
    return -1;
  }
  let v: Int = p.trk_audio_sampling_millihz[i];
  return v;
}

/// Audio Channels of track `i`; 0 when absent; -1 when `i` is out of range.
/// Complexity: O(1).
pub fn mkv_track_audio_channels(p: &MkvFile, i: Int) -> Int {
  if i < 0 || i >= _track_len(p) {
    return -1;
  }
  let v: Int = p.trk_audio_channels[i];
  return v;
}

// --------------------------------------------------
//  Public API: Clusters
// --------------------------------------------------

/// Number of top-level Cluster elements recorded. Complexity: O(1).
pub fn mkv_cluster_count(p: &MkvFile) -> Int {
  return _cluster_len(p);
}

/// Offset of cluster `i`'s Cluster element ID; -1 when `i` is out of range.
/// Complexity: O(1).
pub fn mkv_cluster_offset(p: &MkvFile, i: Int) -> Int {
  if i < 0 || i >= _cluster_len(p) {
    return -1;
  }
  let v: Int = p.cls_offsets[i];
  return v;
}

/// Offset of cluster `i`'s first payload byte (after the size VINT); -1 when
/// `i` is out of range. Complexity: O(1).
pub fn mkv_cluster_data_offset(p: &MkvFile, i: Int) -> Int {
  if i < 0 || i >= _cluster_len(p) {
    return -1;
  }
  let v: Int = p.cls_data_offsets[i];
  return v;
}

/// Declared size of cluster `i` in bytes, or MKV_SIZE_UNKNOWN (-1) when the
/// Cluster used the unknown-size encoding; -1 is also returned when `i` is out
/// of range, so pair this with mkv_cluster_is_unknown_size.
/// Complexity: O(1).
pub fn mkv_cluster_size(p: &MkvFile, i: Int) -> Int {
  if i < 0 || i >= _cluster_len(p) {
    return -1;
  }
  let v: Int = p.cls_sizes[i];
  return v;
}

/// Exclusive end offset of cluster `i`: for a sized Cluster the payload end;
/// for an unknown-size Cluster the offset of the next recognised Segment-level
/// element (or the Segment/buffer end when none was found); -1 when `i` is
/// out of range. Complexity: O(1).
pub fn mkv_cluster_end_offset(p: &MkvFile, i: Int) -> Int {
  if i < 0 || i >= _cluster_len(p) {
    return -1;
  }
  let v: Int = p.cls_end_offsets[i];
  return v;
}

/// True when cluster `i` declared the EBML unknown-size encoding; false when
/// `i` is out of range. Complexity: O(1).
pub fn mkv_cluster_is_unknown_size(p: &MkvFile, i: Int) -> Bool {
  if i < 0 || i >= _cluster_len(p) {
    return false;
  }
  let v: Int = p.cls_unknown[i];
  if v == 1 {
    return true;
  }
  return false;
}
