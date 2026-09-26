// XIOM -- xiom.mp4: pure-XIOM ISO BMFF / MP4 box parser
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Scope: parse (never decode, never write) the ISO Base Media File Format
// (ISO/IEC 14496-12) container layout used by .mp4 files.
//
// A file is a sequence of boxes (atoms). Each box is a 32-bit big-endian
// size, a four-character type, and (size - 8) payload bytes:
//
//   size == 1          -> a 64-bit largesize follows the type (header 16)
//   size == 0          -> the box extends to the end of the enclosing
//                         context (the end of the file at top level)
//   type == "uuid"     -> 16 user-type bytes follow the size/type header,
//                         so the header is 8+16 (or 16+16 with largesize)
//
// The parser walks the whole tree recursively. Container boxes whose
// children are walked are exactly: moov, trak, mdia, minf, stbl, dinf,
// edts. Every box (container or leaf) is recorded in file order in parallel
// vectors: fourcc type, absolute offset, total size, header size, nesting
// depth, parent index and uuid user-type hex (empty for non-uuid boxes).
// The walk is depth-limited (32 nesting levels) and rejects truncated
// headers, sizes below 8, sizes that extend past the file, child boxes that
// overrun their parent container, non-printable four character codes and
// malformed payloads of the boxes listed below.
//
// Metadata extracted (first occurrence semantics are the caller's):
//   * ftyp  -> major brand, minor version, compatible brand list
//   * mvhd  -> version, timescale, duration (v0 32-bit / v1 64-bit)
//   * tkhd  -> version, track id, duration, width/height in whole pixels
//              (16.16 fixed point rounded to nearest, halves up)
//   * mdhd  -> timescale, duration, ISO-639-2/T three-letter language
//   * hdlr  -> handler type fourcc ("vide", "soun", "text", ...)
//   * stsd  -> sample-entry fourccs; width/height for visual entries
//   * elst  -> entry count
//   * stco/co64 -> chunk-offset entry count (kind 0 = stco, 1 = co64)
//   * stsz  -> sample count and uniform sample size
// Top-level moov / moof / mdat occurrences are counted so fragmented files
// (moof present) and moov-at-end layouts are detectable.
//
// Non-goals: no media decoding, no sample-table expansion (entry counts
// only), no muxing or writing, no 64-bit segment tables inside tfhd/trun,
// no QuickTime-only atoms beyond the five listed containers.
//
// v0.61.3 notes that shaped this module:
//   * free functions only, no self methods; state travels by reference.
//   * Ok/Err construction is confined to the tiny leaf helpers below.
//   * Str values read out of a Vec[Str] are bound to a typed local and
//     compared with str_compare, never with `==` (BUG-17 lowering).
//   * every UInt8 is widened with `(b as Int) & 0xFF` before arithmetic.
//   * fourccs are validated as printable ASCII before a Str is built from
//     their bytes; uuid user types are rendered as hex text, never as a
//     raw byte string (a 0x00 byte would truncate it).
//   * `&struct.field` is never passed where a `&Vec[UInt8]` parameter is
//     expected; callers bind a local first.
//   * parallel Vec fields are only appended in _walk and the four _parse_*
//     helpers, where every push on one pool is mirrored on its siblings.

module xiom.mp4

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;

// --------------------------------------------------
//  Types
// --------------------------------------------------

/// Parsed MP4 / ISO BMFF file.
///
/// Box pools (one entry per box, in file order): `box_types` (fourcc),
/// `box_offsets` (absolute start), `box_sizes` (total size including the
/// header), `box_header_sizes` (8, 16 for largesize, plus 16 for uuid),
/// `box_depths` (0 at top level), `box_parents` (index of the enclosing
/// box, -1 at top level), `box_uuids` (32 lowercase hex digits for uuid
/// boxes, "" otherwise) and `box_is_container` (1 when the box's children
/// were walked). Use the mp4_box_* accessors, not raw indexing.
///
/// ftyp pool: `ftyp_offsets`, `ftyp_majors`, `ftyp_minors`, and for each
/// ftyp entry a slice of the flat `brands` list given by
/// `ftyp_brand_offsets` / `ftyp_brand_counts`.
///
/// mvhd pool: `mvhd_offsets`, `mvhd_versions`, `mvhd_timescales`,
/// `mvhd_durations`.
/// tkhd pool: `tkhd_offsets`, `tkhd_versions`, `tkhd_track_ids`,
/// `tkhd_durations`, `tkhd_widths`, `tkhd_heights` (whole pixels).
/// mdhd pool: `mdhd_offsets`, `mdhd_versions`, `mdhd_timescales`,
/// `mdhd_durations`, `mdhd_languages`.
/// hdlr pool: `hdlr_offsets`, `hdlr_handlers`.
/// stsd pool: `stsd_offsets`, `stsd_entry_counts` (declared, per stsd box)
/// and the sample-entry pools `entry_fourccs`, `entry_offsets`,
/// `entry_widths` / `entry_heights` (-1 for non-visual entries) and
/// `entry_stsd` (index of the owning stsd box).
/// elst pool: `elst_offsets`, `elst_versions`, `elst_entry_counts`.
/// chunk-offset pool: `chunk_offsets`, `chunk_kinds` (0 = stco, 1 = co64),
/// `chunk_entry_counts`.
/// stsz pool: `stsz_offsets`, `stsz_uniform_sizes`, `stsz_sample_counts`.
///
/// Layout counters: `moov_count`, `moof_count`, `mdat_count` (top-level
/// occurrences), `first_moov_off`, `first_mdat_off`, `first_ftyp_off`
/// (-1 when absent) and `total_len` (input buffer length).
///
/// Fields are implementation details; use the mp4_* accessors. A value is
/// only produced by mp4_parse, so the invariants always hold.
pub type Mp4File = {
  box_types: Vec[Str];
  box_offsets: Vec[Int];
  box_sizes: Vec[Int];
  box_header_sizes: Vec[Int];
  box_depths: Vec[Int];
  box_parents: Vec[Int];
  box_uuids: Vec[Str];
  box_is_container: Vec[Int];
  ftyp_offsets: Vec[Int];
  ftyp_majors: Vec[Str];
  ftyp_minors: Vec[Int];
  ftyp_brand_offsets: Vec[Int];
  ftyp_brand_counts: Vec[Int];
  brands: Vec[Str];
  mvhd_offsets: Vec[Int];
  mvhd_versions: Vec[Int];
  mvhd_timescales: Vec[Int];
  mvhd_durations: Vec[Int];
  tkhd_offsets: Vec[Int];
  tkhd_versions: Vec[Int];
  tkhd_track_ids: Vec[Int];
  tkhd_durations: Vec[Int];
  tkhd_widths: Vec[Int];
  tkhd_heights: Vec[Int];
  mdhd_offsets: Vec[Int];
  mdhd_versions: Vec[Int];
  mdhd_timescales: Vec[Int];
  mdhd_durations: Vec[Int];
  mdhd_languages: Vec[Str];
  hdlr_offsets: Vec[Int];
  hdlr_handlers: Vec[Str];
  stsd_offsets: Vec[Int];
  stsd_entry_counts: Vec[Int];
  entry_fourccs: Vec[Str];
  entry_offsets: Vec[Int];
  entry_widths: Vec[Int];
  entry_heights: Vec[Int];
  entry_stsd: Vec[Int];
  elst_offsets: Vec[Int];
  elst_versions: Vec[Int];
  elst_entry_counts: Vec[Int];
  chunk_offsets: Vec[Int];
  chunk_kinds: Vec[Int];
  chunk_entry_counts: Vec[Int];
  stsz_offsets: Vec[Int];
  stsz_uniform_sizes: Vec[Int];
  stsz_sample_counts: Vec[Int];
  moov_count: Int;
  moof_count: Int;
  mdat_count: Int;
  first_moov_off: Int;
  first_mdat_off: Int;
  first_ftyp_off: Int;
  total_len: Int;
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[Mp4File, Str].
fn _ok_file(v: Mp4File) -> Result[Mp4File, Str] {
  return Ok(v);
}

// Err(m) for Result[Mp4File, Str].
fn _err_file(m: Str) -> Result[Mp4File, Str] {
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

// --------------------------------------------------
//  Small helpers
// --------------------------------------------------

// Maximum box nesting depth accepted by the walker.
fn _max_depth() -> Int {
  return 32;
}

// An empty file value; every pool is appended to during mp4_parse.
fn _new_file() -> Mp4File {
  return Mp4File{
    box_types: Vec[Str].new();
    box_offsets: Vec[Int].new();
    box_sizes: Vec[Int].new();
    box_header_sizes: Vec[Int].new();
    box_depths: Vec[Int].new();
    box_parents: Vec[Int].new();
    box_uuids: Vec[Str].new();
    box_is_container: Vec[Int].new();
    ftyp_offsets: Vec[Int].new();
    ftyp_majors: Vec[Str].new();
    ftyp_minors: Vec[Int].new();
    ftyp_brand_offsets: Vec[Int].new();
    ftyp_brand_counts: Vec[Int].new();
    brands: Vec[Str].new();
    mvhd_offsets: Vec[Int].new();
    mvhd_versions: Vec[Int].new();
    mvhd_timescales: Vec[Int].new();
    mvhd_durations: Vec[Int].new();
    tkhd_offsets: Vec[Int].new();
    tkhd_versions: Vec[Int].new();
    tkhd_track_ids: Vec[Int].new();
    tkhd_durations: Vec[Int].new();
    tkhd_widths: Vec[Int].new();
    tkhd_heights: Vec[Int].new();
    mdhd_offsets: Vec[Int].new();
    mdhd_versions: Vec[Int].new();
    mdhd_timescales: Vec[Int].new();
    mdhd_durations: Vec[Int].new();
    mdhd_languages: Vec[Str].new();
    hdlr_offsets: Vec[Int].new();
    hdlr_handlers: Vec[Str].new();
    stsd_offsets: Vec[Int].new();
    stsd_entry_counts: Vec[Int].new();
    entry_fourccs: Vec[Str].new();
    entry_offsets: Vec[Int].new();
    entry_widths: Vec[Int].new();
    entry_heights: Vec[Int].new();
    entry_stsd: Vec[Int].new();
    elst_offsets: Vec[Int].new();
    elst_versions: Vec[Int].new();
    elst_entry_counts: Vec[Int].new();
    chunk_offsets: Vec[Int].new();
    chunk_kinds: Vec[Int].new();
    chunk_entry_counts: Vec[Int].new();
    stsz_offsets: Vec[Int].new();
    stsz_uniform_sizes: Vec[Int].new();
    stsz_sample_counts: Vec[Int].new();
    moov_count: 0;
    moof_count: 0;
    mdat_count: 0;
    first_moov_off: -1;
    first_mdat_off: -1;
    first_ftyp_off: -1;
    total_len: 0;
  };
}

// True when `s` equals `want` (BUG-17 safe).
fn _str_is(s: Str, want: Str) -> Bool {
  return compare.str_compare(s, want) == 0;
}

// Container boxes whose children the walker descends into.
fn _is_container(t: Str) -> Bool {
  if _str_is(t, "moov") {
    return true;
  }
  if _str_is(t, "trak") {
    return true;
  }
  if _str_is(t, "mdia") {
    return true;
  }
  if _str_is(t, "minf") {
    return true;
  }
  if _str_is(t, "stbl") {
    return true;
  }
  if _str_is(t, "dinf") {
    return true;
  }
  if _str_is(t, "edts") {
    return true;
  }
  return false;
}

// Visual sample-entry four character codes understood by this parser.
fn _is_visual(t: Str) -> Bool {
  if _str_is(t, "avc1") {
    return true;
  }
  if _str_is(t, "avc3") {
    return true;
  }
  if _str_is(t, "hvc1") {
    return true;
  }
  if _str_is(t, "hev1") {
    return true;
  }
  if _str_is(t, "mp4v") {
    return true;
  }
  if _str_is(t, "vp08") {
    return true;
  }
  if _str_is(t, "vp09") {
    return true;
  }
  if _str_is(t, "av01") {
    return true;
  }
  if _str_is(t, "encv") {
    return true;
  }
  return false;
}

// 16.16 fixed-point value rounded to the nearest whole number (halves up).
// Inputs are unsigned box fields, so the addition cannot go negative.
fn _fixed_round(v: Int) -> Int {
  return (v + 32768) / 65536;
}

// --------------------------------------------------
//  Byte readers (MP4 fields are big-endian)
// --------------------------------------------------

// Byte `pos` of `buf` widened to 0..255. Callers bound-check first.
fn _byte_at(buf: &Vec[UInt8], pos: Int) -> Int {
  let raw: UInt8 = buf[pos];
  return (raw as Int) & 0xFF;
}

// Big-endian u16 at `pos`.
fn _rd_be16(buf: &Vec[UInt8], total: Int, pos: Int) -> Result[Int, Str] {
  if pos + 2 > total {
    return _err_int("mp4: truncated field");
  }
  let b0 = _byte_at(buf, pos);
  let b1 = _byte_at(buf, pos + 1);
  return _ok_int(b0 * 256 + b1);
}

// Big-endian u32 at `pos`.
fn _rd_be32(buf: &Vec[UInt8], total: Int, pos: Int) -> Result[Int, Str] {
  if pos + 4 > total {
    return _err_int("mp4: truncated field");
  }
  let b0 = _byte_at(buf, pos);
  let b1 = _byte_at(buf, pos + 1);
  let b2 = _byte_at(buf, pos + 2);
  let b3 = _byte_at(buf, pos + 3);
  return _ok_int(b0 * 16777216 + b1 * 65536 + b2 * 256 + b3);
}

// Big-endian u64 at `pos`, rejected when it does not fit in Int.
fn _rd_be64(buf: &Vec[UInt8], total: Int, pos: Int) -> Result[Int, Str] {
  if pos + 8 > total {
    return _err_int("mp4: truncated field");
  }
  let b0 = _byte_at(buf, pos);
  let b1 = _byte_at(buf, pos + 1);
  let b2 = _byte_at(buf, pos + 2);
  let b3 = _byte_at(buf, pos + 3);
  let b4 = _byte_at(buf, pos + 4);
  let b5 = _byte_at(buf, pos + 5);
  let b6 = _byte_at(buf, pos + 6);
  let b7 = _byte_at(buf, pos + 7);
  let hi = b0 * 16777216 + b1 * 65536 + b2 * 256 + b3;
  let lo = b4 * 16777216 + b5 * 65536 + b6 * 256 + b7;
  if hi >= 2147483648 {
    return _err_int("mp4: 64-bit value out of range");
  }
  return _ok_int(hi * 4294967296 + lo);
}

// True when four printable ASCII bytes sit at `pos`.
fn _fourcc_ok(buf: &Vec[UInt8], pos: Int, total: Int) -> Bool {
  if pos + 4 > total {
    return false;
  }
  var k = 0;
  while k < 4 {
    let c = _byte_at(buf, pos + k);
    if c < 32 {
      return false;
    }
    if c > 126 {
      return false;
    }
    k = k + 1;
  }
  return true;
}

// Four printable ASCII bytes at `pos` as a Str. Callers validated first.
fn _fourcc(buf: &Vec[UInt8], pos: Int) -> Str {
  var out = builder.sb_new();
  var k = 0;
  while k < 4 {
    let raw: UInt8 = buf[pos + k];
    builder.sb_push_byte(&mut out, raw);
    k = k + 1;
  }
  return builder.sb_to_str(&out);
}

// One byte as two lowercase hex digits.
fn _hex2(v: Int) -> Str {
  var digits = "0123456789abcdef";
  let hi = v / 16;
  let lo = v % 16;
  return string.str_slice(digits, hi, hi + 1) + string.str_slice(digits, lo, lo + 1);
}

// `n` bytes at `pos` as lowercase hex text. Bounds are pre-checked.
fn _hex_n(buf: &Vec[UInt8], pos: Int, n: Int) -> Str {
  var acc = "";
  var k = 0;
  while k < n {
    acc = acc + _hex2(_byte_at(buf, pos + k));
    k = k + 1;
  }
  return acc;
}

// One 1..26 language code point as its lowercase letter. Callers validate.
fn _letter(c: Int) -> Str {
  var letters = "abcdefghijklmnopqrstuvwxyz";
  let idx = c - 1;
  return string.str_slice(letters, idx, idx + 1);
}

// --------------------------------------------------
//  Metadata payload parsers
// --------------------------------------------------

// ftyp: major brand (4), minor version (u32), compatible brands (4 each).
fn _parse_ftyp(f: &mut Mp4File, buf: &Vec[UInt8], total: Int, box_start: Int, header: Int, box_end: Int) -> Result[Int, Str] {
  let p = box_start + header;
  let plen = box_end - p;
  if plen < 8 {
    return _err_int("mp4: ftyp too short");
  }
  let rest = plen - 8;
  if rest % 4 != 0 {
    return _err_int("mp4: ftyp compatible brands malformed");
  }
  if !_fourcc_ok(buf, p, total) {
    return _err_int("mp4: ftyp brand not printable");
  }
  let major = _fourcc(buf, p);
  let minor_r = _rd_be32(buf, total, p + 4);
  if !minor_r.is_ok {
    return _err_int(minor_r.error);
  }
  let brand_off = f.brands.len();
  var count = 0;
  var q = p + 8;
  while q < box_end {
    if !_fourcc_ok(buf, q, total) {
      return _err_int("mp4: ftyp brand not printable");
    }
    f.brands.push(_fourcc(buf, q));
    count = count + 1;
    q = q + 4;
  }
  f.ftyp_offsets.push(box_start);
  f.ftyp_majors.push(major);
  f.ftyp_minors.push(minor_r.value);
  f.ftyp_brand_offsets.push(brand_off);
  f.ftyp_brand_counts.push(count);
  return _ok_int(0);
}

// mvhd: full box; timescale/duration at version-dependent offsets.
fn _parse_mvhd(f: &mut Mp4File, buf: &Vec[UInt8], total: Int, box_start: Int, header: Int, box_end: Int) -> Result[Int, Str] {
  let p = box_start + header;
  let plen = box_end - p;
  if plen < 4 {
    return _err_int("mp4: mvhd too short");
  }
  let vr = _rd_be32(buf, total, p);
  if !vr.is_ok {
    return _err_int(vr.error);
  }
  let version = vr.value / 16777216;
  var timescale = 0;
  var duration = 0;
  if version == 1 {
    if plen < 32 {
      return _err_int("mp4: mvhd too short");
    }
    let ts_r = _rd_be32(buf, total, p + 20);
    if !ts_r.is_ok {
      return _err_int(ts_r.error);
    }
    let du_r = _rd_be64(buf, total, p + 24);
    if !du_r.is_ok {
      return _err_int(du_r.error);
    }
    timescale = ts_r.value;
    duration = du_r.value;
  } else if version == 0 {
    if plen < 20 {
      return _err_int("mp4: mvhd too short");
    }
    let ts_r = _rd_be32(buf, total, p + 12);
    if !ts_r.is_ok {
      return _err_int(ts_r.error);
    }
    let du_r = _rd_be32(buf, total, p + 16);
    if !du_r.is_ok {
      return _err_int(du_r.error);
    }
    timescale = ts_r.value;
    duration = du_r.value;
  } else {
    return _err_int("mp4: mvhd unsupported version");
  }
  f.mvhd_offsets.push(box_start);
  f.mvhd_versions.push(version);
  f.mvhd_timescales.push(timescale);
  f.mvhd_durations.push(duration);
  return _ok_int(0);
}

// tkhd: full box; track id, duration and 16.16 width/height.
fn _parse_tkhd(f: &mut Mp4File, buf: &Vec[UInt8], total: Int, box_start: Int, header: Int, box_end: Int) -> Result[Int, Str] {
  let p = box_start + header;
  let plen = box_end - p;
  if plen < 4 {
    return _err_int("mp4: tkhd too short");
  }
  let vr = _rd_be32(buf, total, p);
  if !vr.is_ok {
    return _err_int(vr.error);
  }
  let version = vr.value / 16777216;
  var track_id = 0;
  var duration = 0;
  var width = 0;
  var height = 0;
  if version == 1 {
    if plen < 96 {
      return _err_int("mp4: tkhd too short");
    }
    let id_r = _rd_be32(buf, total, p + 20);
    if !id_r.is_ok {
      return _err_int(id_r.error);
    }
    let du_r = _rd_be64(buf, total, p + 28);
    if !du_r.is_ok {
      return _err_int(du_r.error);
    }
    let w_r = _rd_be32(buf, total, p + 88);
    if !w_r.is_ok {
      return _err_int(w_r.error);
    }
    let h_r = _rd_be32(buf, total, p + 92);
    if !h_r.is_ok {
      return _err_int(h_r.error);
    }
    track_id = id_r.value;
    duration = du_r.value;
    width = _fixed_round(w_r.value);
    height = _fixed_round(h_r.value);
  } else if version == 0 {
    if plen < 84 {
      return _err_int("mp4: tkhd too short");
    }
    let id_r = _rd_be32(buf, total, p + 12);
    if !id_r.is_ok {
      return _err_int(id_r.error);
    }
    let du_r = _rd_be32(buf, total, p + 20);
    if !du_r.is_ok {
      return _err_int(du_r.error);
    }
    let w_r = _rd_be32(buf, total, p + 76);
    if !w_r.is_ok {
      return _err_int(w_r.error);
    }
    let h_r = _rd_be32(buf, total, p + 80);
    if !h_r.is_ok {
      return _err_int(h_r.error);
    }
    track_id = id_r.value;
    duration = du_r.value;
    width = _fixed_round(w_r.value);
    height = _fixed_round(h_r.value);
  } else {
    return _err_int("mp4: tkhd unsupported version");
  }
  f.tkhd_offsets.push(box_start);
  f.tkhd_versions.push(version);
  f.tkhd_track_ids.push(track_id);
  f.tkhd_durations.push(duration);
  f.tkhd_widths.push(width);
  f.tkhd_heights.push(height);
  return _ok_int(0);
}

// mdhd: full box; timescale, duration and packed three-letter language.
fn _parse_mdhd(f: &mut Mp4File, buf: &Vec[UInt8], total: Int, box_start: Int, header: Int, box_end: Int) -> Result[Int, Str] {
  let p = box_start + header;
  let plen = box_end - p;
  if plen < 4 {
    return _err_int("mp4: mdhd too short");
  }
  let vr = _rd_be32(buf, total, p);
  if !vr.is_ok {
    return _err_int(vr.error);
  }
  let version = vr.value / 16777216;
  var timescale = 0;
  var duration = 0;
  var lang_pos = 0;
  if version == 1 {
    if plen < 36 {
      return _err_int("mp4: mdhd too short");
    }
    let ts_r = _rd_be32(buf, total, p + 20);
    if !ts_r.is_ok {
      return _err_int(ts_r.error);
    }
    let du_r = _rd_be64(buf, total, p + 24);
    if !du_r.is_ok {
      return _err_int(du_r.error);
    }
    timescale = ts_r.value;
    duration = du_r.value;
    lang_pos = p + 32;
  } else if version == 0 {
    if plen < 24 {
      return _err_int("mp4: mdhd too short");
    }
    let ts_r = _rd_be32(buf, total, p + 12);
    if !ts_r.is_ok {
      return _err_int(ts_r.error);
    }
    let du_r = _rd_be32(buf, total, p + 16);
    if !du_r.is_ok {
      return _err_int(du_r.error);
    }
    timescale = ts_r.value;
    duration = du_r.value;
    lang_pos = p + 20;
  } else {
    return _err_int("mp4: mdhd unsupported version");
  }
  let lang_r = _rd_be16(buf, total, lang_pos);
  if !lang_r.is_ok {
    return _err_int(lang_r.error);
  }
  let lv = lang_r.value;
  let c1 = (lv / 1024) % 32;
  let c2 = (lv / 32) % 32;
  let c3 = lv % 32;
  if c1 < 1 || c1 > 26 {
    return _err_int("mp4: mdhd bad language");
  }
  if c2 < 1 || c2 > 26 {
    return _err_int("mp4: mdhd bad language");
  }
  if c3 < 1 || c3 > 26 {
    return _err_int("mp4: mdhd bad language");
  }
  let language = _letter(c1) + _letter(c2) + _letter(c3);
  f.mdhd_offsets.push(box_start);
  f.mdhd_versions.push(version);
  f.mdhd_timescales.push(timescale);
  f.mdhd_durations.push(duration);
  f.mdhd_languages.push(language);
  return _ok_int(0);
}

// hdlr: full box; handler type fourcc at payload offset 8.
fn _parse_hdlr(f: &mut Mp4File, buf: &Vec[UInt8], total: Int, box_start: Int, header: Int, box_end: Int) -> Result[Int, Str] {
  let p = box_start + header;
  let plen = box_end - p;
  if plen < 24 {
    return _err_int("mp4: hdlr too short");
  }
  if !_fourcc_ok(buf, p + 8, total) {
    return _err_int("mp4: hdlr handler not printable");
  }
  f.hdlr_offsets.push(box_start);
  f.hdlr_handlers.push(_fourcc(buf, p + 8));
  return _ok_int(0);
}

// stsd: full box; entry count then one sample-entry box per entry.
// Visual entries expose width/height at fixed offsets; audio and other
// entries only contribute their fourcc.
fn _parse_stsd(f: &mut Mp4File, buf: &Vec[UInt8], total: Int, box_start: Int, header: Int, box_end: Int) -> Result[Int, Str] {
  let p = box_start + header;
  let plen = box_end - p;
  if plen < 8 {
    return _err_int("mp4: stsd too short");
  }
  let cr = _rd_be32(buf, total, p + 4);
  if !cr.is_ok {
    return _err_int(cr.error);
  }
  let declared = cr.value;
  let stsd_ord = f.stsd_offsets.len();
  f.stsd_offsets.push(box_start);
  f.stsd_entry_counts.push(declared);
  var q = p + 8;
  var i = 0;
  while i < declared {
    if q + 8 > box_end {
      return _err_int("mp4: stsd entry truncated");
    }
    let sr = _rd_be32(buf, total, q);
    if !sr.is_ok {
      return _err_int(sr.error);
    }
    let esize = sr.value;
    if esize < 8 {
      return _err_int("mp4: stsd entry size below 8");
    }
    if q + esize > box_end {
      return _err_int("mp4: stsd entry overruns stsd box");
    }
    if !_fourcc_ok(buf, q + 4, total) {
      return _err_int("mp4: stsd entry type not printable");
    }
    let entry_type = _fourcc(buf, q + 4);
    var w = -1;
    var h = -1;
    if _is_visual(entry_type) {
      if esize < 86 {
        return _err_int("mp4: visual sample entry too short");
      }
      let wr = _rd_be16(buf, total, q + 32);
      if !wr.is_ok {
        return _err_int(wr.error);
      }
      let hr = _rd_be16(buf, total, q + 34);
      if !hr.is_ok {
        return _err_int(hr.error);
      }
      w = wr.value;
      h = hr.value;
    }
    f.entry_fourccs.push(entry_type);
    f.entry_offsets.push(q);
    f.entry_widths.push(w);
    f.entry_heights.push(h);
    f.entry_stsd.push(stsd_ord);
    q = q + esize;
    i = i + 1;
  }
  if q != box_end {
    return _err_int("mp4: stsd trailing bytes");
  }
  return _ok_int(0);
}

// elst: full box; entry count, with each entry's fixed size checked.
fn _parse_elst(f: &mut Mp4File, buf: &Vec[UInt8], total: Int, box_start: Int, header: Int, box_end: Int) -> Result[Int, Str] {
  let p = box_start + header;
  let plen = box_end - p;
  if plen < 8 {
    return _err_int("mp4: elst too short");
  }
  let vr = _rd_be32(buf, total, p);
  if !vr.is_ok {
    return _err_int(vr.error);
  }
  let version = vr.value / 16777216;
  if version != 0 && version != 1 {
    return _err_int("mp4: elst unsupported version");
  }
  let cr = _rd_be32(buf, total, p + 4);
  if !cr.is_ok {
    return _err_int(cr.error);
  }
  let count = cr.value;
  var esize = 12;
  if version == 1 {
    esize = 20;
  }
  if 8 + count * esize > plen {
    return _err_int("mp4: elst entries exceed box");
  }
  f.elst_offsets.push(box_start);
  f.elst_versions.push(version);
  f.elst_entry_counts.push(count);
  return _ok_int(0);
}

// stco (32-bit chunk offsets) or co64 (64-bit chunk offsets): full box.
fn _parse_chunk_offsets(f: &mut Mp4File, buf: &Vec[UInt8], total: Int, box_start: Int, header: Int, box_end: Int, kind: Int) -> Result[Int, Str] {
  let p = box_start + header;
  let plen = box_end - p;
  if plen < 8 {
    if kind == 1 {
      return _err_int("mp4: co64 too short");
    }
    return _err_int("mp4: stco too short");
  }
  let cr = _rd_be32(buf, total, p + 4);
  if !cr.is_ok {
    return _err_int(cr.error);
  }
  let count = cr.value;
  var need = 8;
  var esize = 4;
  if kind == 1 {
    esize = 8;
  }
  if count < 0 || need + count * esize > plen {
    if kind == 1 {
      return _err_int("mp4: co64 entries exceed box");
    }
    return _err_int("mp4: stco entries exceed box");
  }
  f.chunk_offsets.push(box_start);
  f.chunk_kinds.push(kind);
  f.chunk_entry_counts.push(count);
  return _ok_int(0);
}

// stsz: full box; uniform sample size (0 = per-sample table follows) and
// sample count. A zero uniform size means count u32 sizes must fit.
fn _parse_stsz(f: &mut Mp4File, buf: &Vec[UInt8], total: Int, box_start: Int, header: Int, box_end: Int) -> Result[Int, Str] {
  let p = box_start + header;
  let plen = box_end - p;
  if plen < 12 {
    return _err_int("mp4: stsz too short");
  }
  let ur = _rd_be32(buf, total, p + 4);
  if !ur.is_ok {
    return _err_int(ur.error);
  }
  let cr = _rd_be32(buf, total, p + 8);
  if !cr.is_ok {
    return _err_int(cr.error);
  }
  let uniform = ur.value;
  let count = cr.value;
  if uniform == 0 {
    if 12 + count * 4 > plen {
      return _err_int("mp4: stsz entries exceed box");
    }
  }
  f.stsz_offsets.push(box_start);
  f.stsz_uniform_sizes.push(uniform);
  f.stsz_sample_counts.push(count);
  return _ok_int(0);
}

// --------------------------------------------------
//  Tree walker
// --------------------------------------------------

// Walk the boxes in [start, end) at nesting `depth`; `parent` is the index
// of the enclosing box in the box pools (-1 at top level). Records every
// box, parses known payloads and recurses into container boxes.
fn _walk(f: &mut Mp4File, buf: &Vec[UInt8], total: Int, start: Int, end: Int, depth: Int, parent: Int) -> Result[Int, Str] {
  if depth > _max_depth() {
    return _err_int("mp4: nesting depth exceeds limit");
  }
  var pos = start;
  while pos < end {
    let rem = end - pos;
    if rem < 8 {
      return _err_int("mp4: truncated box header");
    }
    let size_r = _rd_be32(buf, total, pos);
    if !size_r.is_ok {
      return _err_int(size_r.error);
    }
    let s32 = size_r.value;
    if !_fourcc_ok(buf, pos + 4, total) {
      return _err_int("mp4: non-printable box type");
    }
    let box_type = _fourcc(buf, pos + 4);
    var header = 8;
    var size = 0;
    if s32 == 0 {
      size = end - pos;
    } else if s32 == 1 {
      if rem < 16 {
        return _err_int("mp4: truncated largesize");
      }
      let ls_r = _rd_be64(buf, total, pos + 8);
      if !ls_r.is_ok {
        return _err_int(ls_r.error);
      }
      size = ls_r.value;
      header = 16;
      if size < 16 {
        return _err_int("mp4: box size below header");
      }
    } else {
      size = s32;
      if size < 8 {
        return _err_int("mp4: box size below 8");
      }
    }
    var uuid_hex = "";
    if _str_is(box_type, "uuid") {
      if rem < header + 16 {
        return _err_int("mp4: truncated uuid user type");
      }
      uuid_hex = _hex_n(buf, pos + header, 16);
      header = header + 16;
      if size < header {
        return _err_int("mp4: box size below header");
      }
    }
    if pos + size > total {
      return _err_int("mp4: box extends beyond buffer");
    }
    if pos + size > end {
      return _err_int("mp4: box overruns parent container");
    }
    let box_end = pos + size;
    let payload = pos + header;
    let is_container = _is_container(box_type);
    var container_flag = 0;
    if is_container {
      container_flag = 1;
    }
    let idx = f.box_types.len();
    f.box_types.push(box_type);
    f.box_offsets.push(pos);
    f.box_sizes.push(size);
    f.box_header_sizes.push(header);
    f.box_depths.push(depth);
    f.box_parents.push(parent);
    f.box_uuids.push(uuid_hex);
    f.box_is_container.push(container_flag);
    if _str_is(box_type, "ftyp") {
      let pr = _parse_ftyp(f, buf, total, pos, header, box_end);
      if !pr.is_ok {
        return _err_int(pr.error);
      }
    } else if _str_is(box_type, "mvhd") {
      let pr = _parse_mvhd(f, buf, total, pos, header, box_end);
      if !pr.is_ok {
        return _err_int(pr.error);
      }
    } else if _str_is(box_type, "tkhd") {
      let pr = _parse_tkhd(f, buf, total, pos, header, box_end);
      if !pr.is_ok {
        return _err_int(pr.error);
      }
    } else if _str_is(box_type, "mdhd") {
      let pr = _parse_mdhd(f, buf, total, pos, header, box_end);
      if !pr.is_ok {
        return _err_int(pr.error);
      }
    } else if _str_is(box_type, "hdlr") {
      let pr = _parse_hdlr(f, buf, total, pos, header, box_end);
      if !pr.is_ok {
        return _err_int(pr.error);
      }
    } else if _str_is(box_type, "stsd") {
      let pr = _parse_stsd(f, buf, total, pos, header, box_end);
      if !pr.is_ok {
        return _err_int(pr.error);
      }
    } else if _str_is(box_type, "elst") {
      let pr = _parse_elst(f, buf, total, pos, header, box_end);
      if !pr.is_ok {
        return _err_int(pr.error);
      }
    } else if _str_is(box_type, "stco") {
      let pr = _parse_chunk_offsets(f, buf, total, pos, header, box_end, 0);
      if !pr.is_ok {
        return _err_int(pr.error);
      }
    } else if _str_is(box_type, "co64") {
      let pr = _parse_chunk_offsets(f, buf, total, pos, header, box_end, 1);
      if !pr.is_ok {
        return _err_int(pr.error);
      }
    } else if _str_is(box_type, "stsz") {
      let pr = _parse_stsz(f, buf, total, pos, header, box_end);
      if !pr.is_ok {
        return _err_int(pr.error);
      }
    }
    if depth == 0 {
      if _str_is(box_type, "moov") {
        f.moov_count = f.moov_count + 1;
        if f.first_moov_off < 0 {
          f.first_moov_off = pos;
        }
      } else if _str_is(box_type, "moof") {
        f.moof_count = f.moof_count + 1;
      } else if _str_is(box_type, "mdat") {
        f.mdat_count = f.mdat_count + 1;
        if f.first_mdat_off < 0 {
          f.first_mdat_off = pos;
        }
      } else if _str_is(box_type, "ftyp") {
        if f.first_ftyp_off < 0 {
          f.first_ftyp_off = pos;
        }
      }
    }
    if is_container && payload < box_end {
      let dr = _walk(f, buf, total, payload, box_end, depth + 1, idx);
      if !dr.is_ok {
        return _err_int(dr.error);
      }
    }
    pos = box_end;
  }
  return _ok_int(pos);
}

// --------------------------------------------------
//  Public parser
// --------------------------------------------------

/// Parse a whole MP4 / ISO BMFF buffer.
///
/// Returns Err(Str) with a deterministic message for a short buffer, a
/// truncated box header, a size below 8, a 64-bit size out of Int range, a
/// box that extends past the file or overruns its parent, nesting deeper
/// than 32 levels, a non-printable four character code, a truncated uuid
/// user type, and malformed payloads of ftyp/mvhd/tkhd/mdhd/hdlr/stsd/
/// elst/stco/co64/stsz (see SPEC.md for the catalog). Media payloads
/// (mdat) are never inspected; only their box framing is validated.
pub fn mp4_parse(buffer: &Vec[UInt8]) -> Result[Mp4File, Str] {
  let total = buffer.len();
  if total < 8 {
    return _err_file("mp4: buffer too small for box header");
  }
  var f = _new_file();
  let wr = _walk(&mut f, buffer, total, 0, total, 0, -1);
  if !wr.is_ok {
    return _err_file(wr.error);
  }
  f.total_len = total;
  return _ok_file(f);
}

// --------------------------------------------------
//  Box tree accessors
// --------------------------------------------------

/// Input buffer length recorded by mp4_parse.
pub fn mp4_total_len(f: &Mp4File) -> Int {
  return f.total_len;
}

/// Number of boxes recorded (every box at every depth, file order).
pub fn mp4_box_count(f: &Mp4File) -> Int {
  return f.box_types.len();
}

// Shared bounds check for box indices.
fn _box_ok(f: &Mp4File, i: Int) -> Bool {
  if i < 0 {
    return false;
  }
  return i < f.box_types.len();
}

/// Four character code of box `i`. Err("mp4: box index out of range") when
/// `i` is out of bounds.
pub fn mp4_box_type(f: &Mp4File, i: Int) -> Result[Str, Str] {
  if !_box_ok(f, i) {
    return _err_str("mp4: box index out of range");
  }
  let v: Vec[Str] = f.box_types;
  let s: Str = v[i];
  return _ok_str(s);
}

/// Absolute start offset of box `i`; -1 when out of bounds.
pub fn mp4_box_offset(f: &Mp4File, i: Int) -> Int {
  if !_box_ok(f, i) {
    return -1;
  }
  let v: Vec[Int] = f.box_offsets;
  let n: Int = v[i];
  return n;
}

/// Total size (header + payload) of box `i`; -1 when out of bounds.
pub fn mp4_box_size(f: &Mp4File, i: Int) -> Int {
  if !_box_ok(f, i) {
    return -1;
  }
  let v: Vec[Int] = f.box_sizes;
  let n: Int = v[i];
  return n;
}

/// Header size of box `i` (8, 16 with largesize, +16 for uuid);
/// -1 when out of bounds.
pub fn mp4_box_header_size(f: &Mp4File, i: Int) -> Int {
  if !_box_ok(f, i) {
    return -1;
  }
  let v: Vec[Int] = f.box_header_sizes;
  let n: Int = v[i];
  return n;
}

/// Nesting depth of box `i` (0 at top level); -1 when out of bounds.
pub fn mp4_box_depth(f: &Mp4File, i: Int) -> Int {
  if !_box_ok(f, i) {
    return -1;
  }
  let v: Vec[Int] = f.box_depths;
  let n: Int = v[i];
  return n;
}

/// Index of the enclosing box of box `i` (-1 at top level, also -1 when
/// out of bounds).
pub fn mp4_box_parent(f: &Mp4File, i: Int) -> Int {
  if !_box_ok(f, i) {
    return -1;
  }
  let v: Vec[Int] = f.box_parents;
  let n: Int = v[i];
  return n;
}

/// 32 lowercase hex digits of the user type for a uuid box; Err
/// ("mp4: box is not uuid" or "mp4: box index out of range") otherwise.
pub fn mp4_box_uuid(f: &Mp4File, i: Int) -> Result[Str, Str] {
  if !_box_ok(f, i) {
    return _err_str("mp4: box index out of range");
  }
  let v: Vec[Str] = f.box_types;
  let t: Str = v[i];
  if !_str_is(t, "uuid") {
    return _err_str("mp4: box is not uuid");
  }
  let u: Vec[Str] = f.box_uuids;
  let s: Str = u[i];
  return _ok_str(s);
}

/// True when box `i` is a container whose children were walked.
pub fn mp4_box_is_container(f: &Mp4File, i: Int) -> Bool {
  if !_box_ok(f, i) {
    return false;
  }
  let v: Vec[Int] = f.box_is_container;
  let n: Int = v[i];
  return n == 1;
}

/// Index of the first box whose type equals `t` in file order, or -1.
pub fn mp4_find_box(f: &Mp4File, t: Str) -> Int {
  var i = 0;
  let n = f.box_types.len();
  while i < n {
    let v: Vec[Str] = f.box_types;
    let s: Str = v[i];
    if _str_is(s, t) {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

/// Depth-limited indented listing of the box tree, one line per box:
/// two spaces per nesting level, then the fourcc, an optional `uuid=<hex>`
/// and `size=`/`off=` fields. Ends with a newline; "" for an empty file.
pub fn mp4_tree_text(f: &Mp4File) -> Str {
  var sb = builder.sb_new();
  var i = 0;
  let n = f.box_types.len();
  while i < n {
    let depths: Vec[Int] = f.box_depths;
    let d: Int = depths[i];
    let types: Vec[Str] = f.box_types;
    let t: Str = types[i];
    let sizes: Vec[Int] = f.box_sizes;
    let sz: Int = sizes[i];
    let offs: Vec[Int] = f.box_offsets;
    let off: Int = offs[i];
    var k = 0;
    while k < d {
      builder.sb_push_str(&mut sb, "  ");
      k = k + 1;
    }
    builder.sb_push_str(&mut sb, t);
    let uuids: Vec[Str] = f.box_uuids;
    let uh: Str = uuids[i];
    if compare.str_compare(uh, "") != 0 {
      builder.sb_push_str(&mut sb, " uuid=");
      builder.sb_push_str(&mut sb, uh);
    }
    builder.sb_push_str(&mut sb, " size=");
    builder.sb_push_int(&mut sb, sz);
    builder.sb_push_str(&mut sb, " off=");
    builder.sb_push_int(&mut sb, off);
    builder.sb_push_str(&mut sb, "\n");
    i = i + 1;
  }
  return builder.sb_to_str(&sb);
}

// --------------------------------------------------
//  ftyp accessors
// --------------------------------------------------

/// Number of ftyp boxes.
pub fn mp4_ftyp_count(f: &Mp4File) -> Int {
  return f.ftyp_offsets.len();
}

/// Major brand of ftyp box `i`.
pub fn mp4_ftyp_major(f: &Mp4File, i: Int) -> Result[Str, Str] {
  if i < 0 || i >= f.ftyp_majors.len() {
    return _err_str("mp4: ftyp index out of range");
  }
  let v: Vec[Str] = f.ftyp_majors;
  let s: Str = v[i];
  return _ok_str(s);
}

/// Minor version of ftyp box `i`; -1 when out of bounds.
pub fn mp4_ftyp_minor(f: &Mp4File, i: Int) -> Int {
  if i < 0 || i >= f.ftyp_minors.len() {
    return -1;
  }
  let v: Vec[Int] = f.ftyp_minors;
  let n: Int = v[i];
  return n;
}

/// Number of compatible brands of ftyp box `i`; -1 when out of bounds.
pub fn mp4_ftyp_brand_count(f: &Mp4File, i: Int) -> Int {
  if i < 0 || i >= f.ftyp_brand_counts.len() {
    return -1;
  }
  let v: Vec[Int] = f.ftyp_brand_counts;
  let n: Int = v[i];
  return n;
}

/// Compatible brand `e` of ftyp box `i`.
pub fn mp4_ftyp_brand(f: &Mp4File, i: Int, e: Int) -> Result[Str, Str] {
  if i < 0 || i >= f.ftyp_brand_offsets.len() {
    return _err_str("mp4: ftyp index out of range");
  }
  let offs: Vec[Int] = f.ftyp_brand_offsets;
  let counts: Vec[Int] = f.ftyp_brand_counts;
  let off: Int = offs[i];
  let cnt: Int = counts[i];
  if e < 0 || e >= cnt {
    return _err_str("mp4: brand index out of range");
  }
  let b: Vec[Str] = f.brands;
  let s: Str = b[off + e];
  return _ok_str(s);
}

/// True when the file starts with an ftyp box.
pub fn mp4_has_ftyp(f: &Mp4File) -> Bool {
  return f.first_ftyp_off == 0;
}

// --------------------------------------------------
//  mvhd accessors
// --------------------------------------------------

/// Number of mvhd boxes.
pub fn mp4_mvhd_count(f: &Mp4File) -> Int {
  return f.mvhd_timescales.len();
}

/// Version (0 or 1) of mvhd box `i`; -1 when out of bounds.
pub fn mp4_mvhd_version(f: &Mp4File, i: Int) -> Int {
  if i < 0 || i >= f.mvhd_versions.len() {
    return -1;
  }
  let v: Vec[Int] = f.mvhd_versions;
  let n: Int = v[i];
  return n;
}

/// Timescale of mvhd box `i`; -1 when out of bounds.
pub fn mp4_mvhd_timescale(f: &Mp4File, i: Int) -> Int {
  if i < 0 || i >= f.mvhd_timescales.len() {
    return -1;
  }
  let v: Vec[Int] = f.mvhd_timescales;
  let n: Int = v[i];
  return n;
}

/// Duration (in timescale units) of mvhd box `i`; -1 when out of bounds.
pub fn mp4_mvhd_duration(f: &Mp4File, i: Int) -> Int {
  if i < 0 || i >= f.mvhd_durations.len() {
    return -1;
  }
  let v: Vec[Int] = f.mvhd_durations;
  let n: Int = v[i];
  return n;
}

// --------------------------------------------------
//  tkhd accessors
// --------------------------------------------------

/// Number of tkhd boxes.
pub fn mp4_tkhd_count(f: &Mp4File) -> Int {
  return f.tkhd_track_ids.len();
}

/// Version (0 or 1) of tkhd box `i`; -1 when out of bounds.
pub fn mp4_tkhd_version(f: &Mp4File, i: Int) -> Int {
  if i < 0 || i >= f.tkhd_versions.len() {
    return -1;
  }
  let v: Vec[Int] = f.tkhd_versions;
  let n: Int = v[i];
  return n;
}

/// Track id of tkhd box `i`; -1 when out of bounds.
pub fn mp4_tkhd_track_id(f: &Mp4File, i: Int) -> Int {
  if i < 0 || i >= f.tkhd_track_ids.len() {
    return -1;
  }
  let v: Vec[Int] = f.tkhd_track_ids;
  let n: Int = v[i];
  return n;
}

/// Duration (in movie timescale units) of tkhd box `i`; -1 when out of
/// bounds.
pub fn mp4_tkhd_duration(f: &Mp4File, i: Int) -> Int {
  if i < 0 || i >= f.tkhd_durations.len() {
    return -1;
  }
  let v: Vec[Int] = f.tkhd_durations;
  let n: Int = v[i];
  return n;
}

/// Presentation width of tkhd box `i` in whole pixels (16.16 fixed
/// rounded to nearest); -1 when out of bounds.
pub fn mp4_tkhd_width(f: &Mp4File, i: Int) -> Int {
  if i < 0 || i >= f.tkhd_widths.len() {
    return -1;
  }
  let v: Vec[Int] = f.tkhd_widths;
  let n: Int = v[i];
  return n;
}

/// Presentation height of tkhd box `i` in whole pixels (16.16 fixed
/// rounded to nearest); -1 when out of bounds.
pub fn mp4_tkhd_height(f: &Mp4File, i: Int) -> Int {
  if i < 0 || i >= f.tkhd_heights.len() {
    return -1;
  }
  let v: Vec[Int] = f.tkhd_heights;
  let n: Int = v[i];
  return n;
}

// --------------------------------------------------
//  mdhd accessors
// --------------------------------------------------

/// Number of mdhd boxes.
pub fn mp4_mdhd_count(f: &Mp4File) -> Int {
  return f.mdhd_timescales.len();
}

/// Version (0 or 1) of mdhd box `i`; -1 when out of bounds.
pub fn mp4_mdhd_version(f: &Mp4File, i: Int) -> Int {
  if i < 0 || i >= f.mdhd_versions.len() {
    return -1;
  }
  let v: Vec[Int] = f.mdhd_versions;
  let n: Int = v[i];
  return n;
}

/// Timescale of mdhd box `i`; -1 when out of bounds.
pub fn mp4_mdhd_timescale(f: &Mp4File, i: Int) -> Int {
  if i < 0 || i >= f.mdhd_timescales.len() {
    return -1;
  }
  let v: Vec[Int] = f.mdhd_timescales;
  let n: Int = v[i];
  return n;
}

/// Duration (in media timescale units) of mdhd box `i`; -1 when out of
/// bounds.
pub fn mp4_mdhd_duration(f: &Mp4File, i: Int) -> Int {
  if i < 0 || i >= f.mdhd_durations.len() {
    return -1;
  }
  let v: Vec[Int] = f.mdhd_durations;
  let n: Int = v[i];
  return n;
}

/// Three-letter ISO-639-2/T language of mdhd box `i`.
pub fn mp4_mdhd_language(f: &Mp4File, i: Int) -> Result[Str, Str] {
  if i < 0 || i >= f.mdhd_languages.len() {
    return _err_str("mp4: mdhd index out of range");
  }
  let v: Vec[Str] = f.mdhd_languages;
  let s: Str = v[i];
  return _ok_str(s);
}

// --------------------------------------------------
//  hdlr accessors
// --------------------------------------------------

/// Number of hdlr boxes.
pub fn mp4_hdlr_count(f: &Mp4File) -> Int {
  return f.hdlr_handlers.len();
}

/// Handler type fourcc ("vide", "soun", "text", ...) of hdlr box `i`.
pub fn mp4_hdlr_handler(f: &Mp4File, i: Int) -> Result[Str, Str] {
  if i < 0 || i >= f.hdlr_handlers.len() {
    return _err_str("mp4: hdlr index out of range");
  }
  let v: Vec[Str] = f.hdlr_handlers;
  let s: Str = v[i];
  return _ok_str(s);
}

// --------------------------------------------------
//  stsd / sample-entry accessors
// --------------------------------------------------

/// Number of stsd boxes.
pub fn mp4_stsd_count(f: &Mp4File) -> Int {
  return f.stsd_offsets.len();
}

/// Declared sample-entry count of stsd box `i`; -1 when out of bounds.
pub fn mp4_stsd_entry_count(f: &Mp4File, i: Int) -> Int {
  if i < 0 || i >= f.stsd_entry_counts.len() {
    return -1;
  }
  let v: Vec[Int] = f.stsd_entry_counts;
  let n: Int = v[i];
  return n;
}

/// Number of parsed sample entries across all stsd boxes.
pub fn mp4_sample_entry_count(f: &Mp4File) -> Int {
  return f.entry_fourccs.len();
}

/// Fourcc of sample entry `e`.
pub fn mp4_sample_entry_fourcc(f: &Mp4File, e: Int) -> Result[Str, Str] {
  if e < 0 || e >= f.entry_fourccs.len() {
    return _err_str("mp4: sample entry index out of range");
  }
  let v: Vec[Str] = f.entry_fourccs;
  let s: Str = v[e];
  return _ok_str(s);
}

/// Width of visual sample entry `e` in pixels, or -1 for non-visual
/// entries and out-of-range indices.
pub fn mp4_sample_entry_width(f: &Mp4File, e: Int) -> Int {
  if e < 0 || e >= f.entry_widths.len() {
    return -1;
  }
  let v: Vec[Int] = f.entry_widths;
  let n: Int = v[e];
  return n;
}

/// Height of visual sample entry `e` in pixels, or -1 for non-visual
/// entries and out-of-range indices.
pub fn mp4_sample_entry_height(f: &Mp4File, e: Int) -> Int {
  if e < 0 || e >= f.entry_heights.len() {
    return -1;
  }
  let v: Vec[Int] = f.entry_heights;
  let n: Int = v[e];
  return n;
}

/// Index of the stsd box that owns sample entry `e`; -1 when out of range.
pub fn mp4_sample_entry_stsd(f: &Mp4File, e: Int) -> Int {
  if e < 0 || e >= f.entry_stsd.len() {
    return -1;
  }
  let v: Vec[Int] = f.entry_stsd;
  let n: Int = v[e];
  return n;
}

// --------------------------------------------------
//  elst accessors
// --------------------------------------------------

/// Number of elst boxes.
pub fn mp4_elst_count(f: &Mp4File) -> Int {
  return f.elst_entry_counts.len();
}

/// Version (0 or 1) of elst box `i`; -1 when out of bounds.
pub fn mp4_elst_version(f: &Mp4File, i: Int) -> Int {
  if i < 0 || i >= f.elst_versions.len() {
    return -1;
  }
  let v: Vec[Int] = f.elst_versions;
  let n: Int = v[i];
  return n;
}

/// Entry count of elst box `i`; -1 when out of bounds.
pub fn mp4_elst_entry_count(f: &Mp4File, i: Int) -> Int {
  if i < 0 || i >= f.elst_entry_counts.len() {
    return -1;
  }
  let v: Vec[Int] = f.elst_entry_counts;
  let n: Int = v[i];
  return n;
}

// --------------------------------------------------
//  stco / co64 accessors
// --------------------------------------------------

/// Number of chunk-offset tables (stco and co64 boxes).
pub fn mp4_chunk_offset_table_count(f: &Mp4File) -> Int {
  return f.chunk_entry_counts.len();
}

/// Kind of chunk-offset table `i`: 0 = stco (32-bit), 1 = co64 (64-bit);
/// -1 when out of bounds.
pub fn mp4_chunk_offset_kind(f: &Mp4File, i: Int) -> Int {
  if i < 0 || i >= f.chunk_kinds.len() {
    return -1;
  }
  let v: Vec[Int] = f.chunk_kinds;
  let n: Int = v[i];
  return n;
}

/// Chunk-offset entry count of table `i`; -1 when out of bounds.
pub fn mp4_chunk_offset_count(f: &Mp4File, i: Int) -> Int {
  if i < 0 || i >= f.chunk_entry_counts.len() {
    return -1;
  }
  let v: Vec[Int] = f.chunk_entry_counts;
  let n: Int = v[i];
  return n;
}

// --------------------------------------------------
//  stsz accessors
// --------------------------------------------------

/// Number of stsz boxes.
pub fn mp4_stsz_count(f: &Mp4File) -> Int {
  return f.stsz_sample_counts.len();
}

/// Sample count of stsz box `i`; -1 when out of bounds.
pub fn mp4_stsz_sample_count(f: &Mp4File, i: Int) -> Int {
  if i < 0 || i >= f.stsz_sample_counts.len() {
    return -1;
  }
  let v: Vec[Int] = f.stsz_sample_counts;
  let n: Int = v[i];
  return n;
}

/// Uniform sample size of stsz box `i` (0 = per-sample sizes follow in the
/// payload); -1 when out of bounds.
pub fn mp4_stsz_uniform_size(f: &Mp4File, i: Int) -> Int {
  if i < 0 || i >= f.stsz_uniform_sizes.len() {
    return -1;
  }
  let v: Vec[Int] = f.stsz_uniform_sizes;
  let n: Int = v[i];
  return n;
}

// --------------------------------------------------
//  Layout / fragmentation accessors
// --------------------------------------------------

/// Number of top-level moov boxes.
pub fn mp4_moov_count(f: &Mp4File) -> Int {
  return f.moov_count;
}

/// Number of top-level moof boxes (fragmented movie fragments).
pub fn mp4_moof_count(f: &Mp4File) -> Int {
  return f.moof_count;
}

/// Number of top-level mdat boxes.
pub fn mp4_mdat_count(f: &Mp4File) -> Int {
  return f.mdat_count;
}

/// True when the file carries at least one movie fragment (moof).
pub fn mp4_is_fragmented(f: &Mp4File) -> Bool {
  return f.moof_count > 0;
}

/// True when the file carries at least one media data box (mdat).
pub fn mp4_has_mdat(f: &Mp4File) -> Bool {
  return f.mdat_count > 0;
}

/// True when moov appears after the first mdat (progressive-download /
/// moov-at-end layout).
pub fn mp4_is_moov_at_end(f: &Mp4File) -> Bool {
  if f.first_moov_off < 0 {
    return false;
  }
  if f.first_mdat_off < 0 {
    return false;
  }
  return f.first_moov_off > f.first_mdat_off;
}
