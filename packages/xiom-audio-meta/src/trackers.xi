// XIOM -- xiom.audio_meta.trackers: XM, S3M, IT and NSF metadata parsers
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Scope: structural metadata only (headers, order tables and pattern
// geometry). Pattern payloads and instrument/sample payloads are walked for
// their declared sizes but never decoded; no audio is rendered. The module
// is deliberately independent of xiom.audio_meta (no intra-package import):
// it repeats the handful of private byte helpers it needs so each source
// file stays self-contained.
//
// v0.62.2 porter discipline: Ok/Err only in the leaf helpers below; every
// byte widened with `(data[pos] as Int) & 0xFF`; Strs only via
// `_tr_printable_prefix`, which stops at NUL/non-printable bytes so
// sb_to_str never sees a NUL; all table counts are bounded before any loop
// and all pattern/instrument pointers are range-checked before every read.
// See SPEC.md for layouts and the error catalog.

module xiom.audio_meta.trackers

use xiom.string;
use xiom.string.builder;

// --------------------------------------------------
//  Public types
// --------------------------------------------------

/// Parsed FastTracker II (XM) module header plus pattern/instrument
/// geometry.
///
/// `name` is the 20-byte module name and `tracker` the 20-byte tracker name,
/// each truncated at the first NUL/non-printable byte. `header_size` is the
/// declared u32 (>= 276). `order` holds `song_length` entries, each <
/// `patterns`. For every pattern, `pattern_rows[i]` is the declared row
/// count (1..256) and `pattern_data[i]` the byte size of the pattern data
/// that follows its header: the declared packed size, or `rows * channels *
/// 5` for unpacked patterns and for packed patterns with a zero packed size.
/// `instrument_bytes` sums the declared instrument header sizes (each
/// includes its own 4-byte size field). `sample_count` counts the sample
/// headers attached to instruments and `sample_bytes` sums their data sizes
/// (a 16-bit sample stores twice its declared length).
pub type XmInfo = {
  name: Str;
  tracker: Str;
  version: Int;
  header_size: Int;
  song_length: Int;
  restart: Int;
  channels: Int;
  patterns: Int;
  instruments: Int;
  flags: Int;
  tempo: Int;
  bpm: Int;
  order: Vec[Int];
  pattern_rows: Vec[Int];
  pattern_data: Vec[Int];
  instrument_bytes: Int;
  sample_count: Int;
  sample_bytes: Int;
}

/// Parsed Scream Tracker 3 (S3M) header plus pattern geometry.
///
/// `order` holds `ordnum` raw order bytes (255 is the end marker, 254 a skip
/// marker). For every pattern, `pattern_rows[i]` is 64 for a null pointer
/// and otherwise the declared row count; `pattern_packed[i]` is the declared
/// packed length (0 for null pointers). The packed length includes the
/// 2-byte pattern header, as the format requires.
pub type S3mInfo = {
  name: Str;
  ordnum: Int;
  insnum: Int;
  patnum: Int;
  flags: Int;
  cwtv: Int;
  ffi: Int;
  global_volume: Int;
  initial_speed: Int;
  initial_tempo: Int;
  master_volume: Int;
  order: Vec[Int];
  pattern_rows: Vec[Int];
  pattern_packed: Vec[Int];
}

/// Parsed Impulse Tracker (IT) header plus pattern geometry.
///
/// `order` holds `ordnum` raw order bytes (255 is the end marker, 254 a skip
/// marker; any other entry must be < `patnum`). For every pattern,
/// `pattern_rows[i]` is 64 for a null pointer and otherwise the declared row
/// count; `pattern_packed[i]` is the declared pattern length in bytes
/// (header included) or 0 for a null pointer.
pub type ItInfo = {
  name: Str;
  ordnum: Int;
  insnum: Int;
  smpnum: Int;
  patnum: Int;
  cwtv: Int;
  cmwt: Int;
  flags: Int;
  special: Int;
  global_volume: Int;
  mix_volume: Int;
  initial_speed: Int;
  initial_tempo: Int;
  message_length: Int;
  order: Vec[Int];
  pattern_rows: Vec[Int];
  pattern_packed: Vec[Int];
}

/// Parsed NES Sound Format (NSF) header.
///
/// `name`, `artist` and `copyright` are the three 32-byte header text fields,
/// each truncated at the first NUL/non-printable byte. `banks` always holds
/// the 8 declared bank-switch bytes. `data_size` is the PRG payload size
/// (`data.len() - 128`); the PRG bytes themselves are opaque.
pub type NsfInfo = {
  version: Int;
  total_songs: Int;
  starting_song: Int;
  load_address: Int;
  init_address: Int;
  play_address: Int;
  name: Str;
  artist: Str;
  copyright: Str;
  ntsc_speed: Int;
  pal_speed: Int;
  pal_flag: Int;
  chip_flags: Int;
  banks: Vec[Int];
  data_size: Int;
}

// --------------------------------------------------
//  Result constructors (leaf helpers; see module header)
// --------------------------------------------------

fn _tr_ok_xm(v: XmInfo) -> Result[XmInfo, Str] {
  return Ok(v);
}

fn _tr_err_xm(m: Str) -> Result[XmInfo, Str] {
  return Err(m);
}

fn _tr_ok_s3m(v: S3mInfo) -> Result[S3mInfo, Str] {
  return Ok(v);
}

fn _tr_err_s3m(m: Str) -> Result[S3mInfo, Str] {
  return Err(m);
}

fn _tr_ok_it(v: ItInfo) -> Result[ItInfo, Str] {
  return Ok(v);
}

fn _tr_err_it(m: Str) -> Result[ItInfo, Str] {
  return Err(m);
}

fn _tr_ok_nsf(v: NsfInfo) -> Result[NsfInfo, Str] {
  return Ok(v);
}

fn _tr_err_nsf(m: Str) -> Result[NsfInfo, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Byte helpers
// --------------------------------------------------

// Byte at `pos` widened to 0..255; callers guarantee the bounds.
fn _tr_byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// Unsigned little-endian u16 at `pos`; callers guarantee the bounds.
fn _tr_le16(data: &Vec[UInt8], pos: Int) -> Int {
  return _tr_byte(data, pos) + _tr_byte(data, pos + 1) * 256;
}

// Unsigned little-endian u32 at `pos`; callers guarantee the bounds.
fn _tr_le32(data: &Vec[UInt8], pos: Int) -> Int {
  var v: Int = 0;
  var i = 3;
  while i >= 0 {
    v = v * 256 + _tr_byte(data, pos + i);
    i = i - 1;
  }
  return v;
}

// True when the four bytes at `pos` equal the ASCII codes a, b, c, d.
fn _tr_tag4(data: &Vec[UInt8], pos: Int, a: Int, b: Int, c: Int, d: Int) -> Bool {
  if _tr_byte(data, pos) != a { return false; }
  if _tr_byte(data, pos + 1) != b { return false; }
  if _tr_byte(data, pos + 2) != c { return false; }
  if _tr_byte(data, pos + 3) != d { return false; }
  return true;
}

// True when the `n` bytes at `pos` equal the bytes of `s` (a Str literal of
// known length; `s.len()` is reliable for literals). Callers guarantee
// pos + s.len() <= data.len().
fn _tr_match(data: &Vec[UInt8], pos: Int, s: Str) -> Bool {
  var i = 0;
  let m = s.len();
  while i < m {
    if _tr_byte(data, pos + i) != ((string.byte_at(s, i) as Int) & 0xFF) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// Build a Str from the printable ASCII prefix of the `n` bytes at `pos`:
// stops at the first NUL or non-printable byte ("" when that is the first
// byte). The only byte-to-Str path here, so no NUL reaches sb_to_str.
fn _tr_printable_prefix(data: &Vec[UInt8], pos: Int, n: Int) -> Str {
  var m = 0;
  var stop = false;
  while m < n && !stop {
    let b = _tr_byte(data, pos + m);
    if b == 0 {
      stop = true;
    } elif b < 32 {
      stop = true;
    } elif b > 126 {
      stop = true;
    } else {
      m = m + 1;
    }
  }
  if m == 0 {
    return "";
  }
  var sb = Vec[UInt8].new();
  var i = 0;
  while i < m {
    builder.sb_push_byte(&mut sb, _tr_byte(data, pos + i) as UInt8);
    i = i + 1;
  }
  return builder.sb_to_str(&sb);
}

// --------------------------------------------------
//  Public API: XM
// --------------------------------------------------

/// Parse a FastTracker II (XM) module header.
///
/// Checks, in order (first failure wins): non-empty buffer; the 60-byte
/// fixed header; the 17-byte "Extended Module: " magic; the 0x1A marker at
/// offset 37; version 0x0102..0x0104; a header size >= 276 that fits;
/// song length 1..256; restart position <= 255; 1..64 channels; 1..256
/// patterns; <= 128 instruments; tempo 1..31; BPM 32..255; every one of the
/// `song_length` order entries < `patterns`; then every pattern header
/// (length >= 9, packing type 0..1, rows 1..256, data of the computed size)
/// and every instrument: an instrument header (declared size >= 29 and
/// fitting; the size includes its own 4-byte field), a sample count <= 128
/// and, per sample, a 40-byte sample header plus its declared data (16-bit
/// samples store twice the declared length). The buffer must end exactly
/// after the last instrument.
///
/// See SPEC.md for the layout table and the error catalog.
/// Complexity: O(data.len()).
pub fn xm_parse(data: &Vec[UInt8]) -> Result[XmInfo, Str] {
  let n = data.len();
  if n == 0 {
    return _tr_err_xm("xm: empty input");
  }
  if n < 60 {
    return _tr_err_xm("xm: truncated header");
  }
  if !_tr_match(data, 0, "Extended Module: ") {
    return _tr_err_xm("xm: bad magic");
  }
  if _tr_byte(data, 37) != 26 {
    return _tr_err_xm("xm: missing 0x1A marker");
  }
  let version = _tr_le16(data, 58);
  if version < 258 {
    return _tr_err_xm("xm: bad version");
  }
  if version > 260 {
    return _tr_err_xm("xm: bad version");
  }
  let hsize = _tr_le32(data, 60);
  if hsize < 276 {
    return _tr_err_xm("xm: bad header size");
  }
  if hsize > n - 60 {
    return _tr_err_xm("xm: truncated header");
  }
  let song_len = _tr_le16(data, 64);
  if song_len < 1 {
    return _tr_err_xm("xm: bad song length");
  }
  if song_len > 256 {
    return _tr_err_xm("xm: bad song length");
  }
  let restart = _tr_le16(data, 66);
  if restart > 255 {
    return _tr_err_xm("xm: bad restart position");
  }
  let channels = _tr_le16(data, 68);
  if channels < 1 {
    return _tr_err_xm("xm: bad channel count");
  }
  if channels > 64 {
    return _tr_err_xm("xm: bad channel count");
  }
  let patterns = _tr_le16(data, 70);
  if patterns < 1 {
    return _tr_err_xm("xm: bad pattern count");
  }
  if patterns > 256 {
    return _tr_err_xm("xm: bad pattern count");
  }
  let instruments = _tr_le16(data, 72);
  if instruments > 128 {
    return _tr_err_xm("xm: bad instrument count");
  }
  let flags = _tr_le16(data, 74);
  let tempo = _tr_le16(data, 76);
  if tempo < 1 {
    return _tr_err_xm("xm: bad tempo");
  }
  if tempo > 31 {
    return _tr_err_xm("xm: bad tempo");
  }
  let bpm = _tr_le16(data, 78);
  if bpm < 32 {
    return _tr_err_xm("xm: bad bpm");
  }
  var order = Vec[Int].new();
  var i = 0;
  while i < song_len {
    let e = _tr_byte(data, 80 + i);
    if e >= patterns {
      return _tr_err_xm("xm: bad order entry");
    }
    order.push(e);
    i = i + 1;
  }
  var rows = Vec[Int].new();
  var pdata = Vec[Int].new();
  var p = 60 + hsize;
  i = 0;
  while i < patterns {
    if n - p < 9 {
      return _tr_err_xm("xm: truncated pattern header");
    }
    let plen = _tr_le32(data, p);
    if plen < 9 {
      return _tr_err_xm("xm: bad pattern header size");
    }
    if plen > n - p {
      return _tr_err_xm("xm: truncated pattern header");
    }
    let ptype = _tr_byte(data, p + 4);
    if ptype > 1 {
      return _tr_err_xm("xm: bad pattern packing");
    }
    let prows = _tr_le16(data, p + 5);
    if prows < 1 {
      return _tr_err_xm("xm: bad pattern rows");
    }
    if prows > 256 {
      return _tr_err_xm("xm: bad pattern rows");
    }
    let psize = _tr_le16(data, p + 7);
    var dsize = psize;
    if ptype == 0 || psize == 0 {
      dsize = prows * channels * 5;
    }
    if dsize > n - p - plen {
      return _tr_err_xm("xm: truncated pattern data");
    }
    rows.push(prows);
    pdata.push(dsize);
    p = p + plen + dsize;
    i = i + 1;
  }
  var instr_bytes = 0;
  var total_samples = 0;
  var sample_bytes = 0;
  i = 0;
  while i < instruments {
    if n - p < 29 {
      return _tr_err_xm("xm: truncated instrument");
    }
    let isize = _tr_le32(data, p);
    if isize < 29 {
      return _tr_err_xm("xm: bad instrument size");
    }
    if isize > n - p {
      return _tr_err_xm("xm: truncated instrument");
    }
    let nsamples = _tr_le16(data, p + 27);
    if nsamples > 128 {
      return _tr_err_xm("xm: bad sample count");
    }
    instr_bytes = instr_bytes + isize;
    p = p + isize;
    var s = 0;
    while s < nsamples {
      if n - p < 40 {
        return _tr_err_xm("xm: truncated sample header");
      }
      let slen = _tr_le32(data, p);
      let stype = _tr_byte(data, p + 14);
      var dbytes = slen;
      if (stype / 16) % 2 == 1 {
        dbytes = slen * 2;
      }
      if dbytes > n - p - 40 {
        return _tr_err_xm("xm: truncated sample data");
      }
      total_samples = total_samples + 1;
      sample_bytes = sample_bytes + dbytes;
      p = p + 40 + dbytes;
      s = s + 1;
    }
    i = i + 1;
  }
  if p != n {
    return _tr_err_xm("xm: trailing data");
  }
  let info = XmInfo{
    name: _tr_printable_prefix(data, 17, 20);
    tracker: _tr_printable_prefix(data, 38, 20);
    version: version;
    header_size: hsize;
    song_length: song_len;
    restart: restart;
    channels: channels;
    patterns: patterns;
    instruments: instruments;
    flags: flags;
    tempo: tempo;
    bpm: bpm;
    order: order;
    pattern_rows: rows;
    pattern_data: pdata;
    instrument_bytes: instr_bytes;
    sample_count: total_samples;
    sample_bytes: sample_bytes;
  };
  return _tr_ok_xm(info);
}

/// True when xm_parse succeeds. Complexity: O(data.len()).
pub fn xm_is_valid(data: &Vec[UInt8]) -> Bool {
  let r = xm_parse(data);
  return r.is_ok;
}

// --------------------------------------------------
//  Public API: S3M
// --------------------------------------------------

/// Parse a Scream Tracker 3 (S3M) module header.
///
/// Checks, in order (first failure wins): non-empty buffer; the 94-byte
/// fixed header; the 0x1A marker at offset 28; file type 0x10 at offset 29;
/// the "SCRM" magic at offset 44; ordnum 1..256; insnum and patnum <= 256;
/// initial speed 1..255; initial tempo >= 32; then `94 + ordnum +
/// 2*insnum + 2*patnum` bytes of order and pointer tables. Every nonzero
/// pattern pointer must resolve to a paragraph (offset = pointer * 16) whose
/// packed length (header included) fits in the buffer; row counts must be
/// 1..1024. Null pattern pointers mean an empty default pattern (64 rows).
///
/// See SPEC.md for the layout table and the error catalog.
/// Complexity: O(data.len()).
pub fn s3m_parse(data: &Vec[UInt8]) -> Result[S3mInfo, Str] {
  let n = data.len();
  if n == 0 {
    return _tr_err_s3m("s3m: empty input");
  }
  if n < 94 {
    return _tr_err_s3m("s3m: truncated header");
  }
  if _tr_byte(data, 28) != 26 {
    return _tr_err_s3m("s3m: missing 0x1A marker");
  }
  if _tr_byte(data, 29) != 16 {
    return _tr_err_s3m("s3m: bad file type");
  }
  if !_tr_tag4(data, 44, 83, 67, 82, 77) {
    return _tr_err_s3m("s3m: bad SCRM magic");
  }
  let ordnum = _tr_le16(data, 32);
  if ordnum < 1 {
    return _tr_err_s3m("s3m: bad order count");
  }
  if ordnum > 256 {
    return _tr_err_s3m("s3m: bad order count");
  }
  let insnum = _tr_le16(data, 34);
  if insnum > 256 {
    return _tr_err_s3m("s3m: bad table count");
  }
  let patnum = _tr_le16(data, 36);
  if patnum > 256 {
    return _tr_err_s3m("s3m: bad table count");
  }
  let speed = _tr_byte(data, 49);
  if speed < 1 {
    return _tr_err_s3m("s3m: bad initial speed");
  }
  let tempo = _tr_byte(data, 50);
  if tempo < 32 {
    return _tr_err_s3m("s3m: bad initial tempo");
  }
  let need = 94 + ordnum + insnum * 2 + patnum * 2;
  if n < need {
    return _tr_err_s3m("s3m: truncated tables");
  }
  var order = Vec[Int].new();
  var i = 0;
  while i < ordnum {
    order.push(_tr_byte(data, 94 + i));
    i = i + 1;
  }
  var rows = Vec[Int].new();
  var packed = Vec[Int].new();
  let pptr = 94 + ordnum + insnum * 2;
  i = 0;
  while i < patnum {
    let ptr = _tr_le16(data, pptr + i * 2);
    if ptr == 0 {
      rows.push(64);
      packed.push(0);
    } else {
      let off = ptr * 16;
      if off < 0 {
        return _tr_err_s3m("s3m: bad pattern pointer");
      }
      if n - off < 2 {
        return _tr_err_s3m("s3m: bad pattern pointer");
      }
      let plen = _tr_le16(data, off);
      if plen < 2 {
        return _tr_err_s3m("s3m: bad pattern pointer");
      }
      if plen > n - off {
        return _tr_err_s3m("s3m: bad pattern pointer");
      }
      let prows = _tr_le16(data, off + 2);
      if prows < 1 {
        return _tr_err_s3m("s3m: bad pattern rows");
      }
      if prows > 1024 {
        return _tr_err_s3m("s3m: bad pattern rows");
      }
      rows.push(prows);
      packed.push(plen);
    }
    i = i + 1;
  }
  let info = S3mInfo{
    name: _tr_printable_prefix(data, 0, 28);
    ordnum: ordnum;
    insnum: insnum;
    patnum: patnum;
    flags: _tr_le16(data, 38);
    cwtv: _tr_le16(data, 40);
    ffi: _tr_le16(data, 42);
    global_volume: _tr_byte(data, 48);
    initial_speed: speed;
    initial_tempo: tempo;
    master_volume: _tr_byte(data, 51);
    order: order;
    pattern_rows: rows;
    pattern_packed: packed;
  };
  return _tr_ok_s3m(info);
}

/// True when s3m_parse succeeds. Complexity: O(data.len()).
pub fn s3m_is_valid(data: &Vec[UInt8]) -> Bool {
  let r = s3m_parse(data);
  return r.is_ok;
}

// --------------------------------------------------
//  Public API: IT
// --------------------------------------------------

/// Parse an Impulse Tracker (IT) module header.
///
/// Checks, in order (first failure wins): non-empty buffer; the 192-byte
/// fixed header; the "IMPM" magic at offset 0; ordnum 1..256; global volume
/// <= 128; mix volume <= 128; initial speed >= 1; initial tempo >= 32; then
/// `192 + ordnum + 4*insnum + 4*smpnum + 4*patnum` bytes of order and
/// pointer tables. Order entries must be 254/255 or < `patnum`. Every
/// nonzero pattern pointer must resolve to a header whose declared length
/// fits in the buffer; row counts must be 1..1024. Null pointers mean an
/// empty default pattern (64 rows).
///
/// See SPEC.md for the layout table and the error catalog.
/// Complexity: O(data.len()).
pub fn it_parse(data: &Vec[UInt8]) -> Result[ItInfo, Str] {
  let n = data.len();
  if n == 0 {
    return _tr_err_it("it: empty input");
  }
  if n < 192 {
    return _tr_err_it("it: truncated header");
  }
  if !_tr_tag4(data, 0, 73, 77, 80, 77) {
    return _tr_err_it("it: bad IMPM magic");
  }
  let ordnum = _tr_le16(data, 32);
  if ordnum < 1 {
    return _tr_err_it("it: bad order count");
  }
  if ordnum > 256 {
    return _tr_err_it("it: bad order count");
  }
  let insnum = _tr_le16(data, 34);
  let smpnum = _tr_le16(data, 36);
  let patnum = _tr_le16(data, 38);
  let gv = _tr_byte(data, 48);
  if gv > 128 {
    return _tr_err_it("it: bad global volume");
  }
  let mv = _tr_byte(data, 49);
  if mv > 128 {
    return _tr_err_it("it: bad mix volume");
  }
  let speed = _tr_byte(data, 50);
  if speed < 1 {
    return _tr_err_it("it: bad initial speed");
  }
  let tempo = _tr_byte(data, 51);
  if tempo < 32 {
    return _tr_err_it("it: bad initial tempo");
  }
  let need = 192 + ordnum + (insnum + smpnum + patnum) * 4;
  if n < need {
    return _tr_err_it("it: truncated tables");
  }
  var order = Vec[Int].new();
  var i = 0;
  while i < ordnum {
    let e = _tr_byte(data, 192 + i);
    if e == 255 {
      order.push(e);
    } elif e == 254 {
      order.push(e);
    } elif e >= patnum {
      return _tr_err_it("it: bad order entry");
    } else {
      order.push(e);
    }
    i = i + 1;
  }
  var rows = Vec[Int].new();
  var packed = Vec[Int].new();
  let pptr = 192 + ordnum + insnum * 4 + smpnum * 4;
  i = 0;
  while i < patnum {
    let ptr = _tr_le32(data, pptr + i * 4);
    if ptr == 0 {
      rows.push(64);
      packed.push(0);
    } else {
      let off = ptr;
      if n - off < 8 {
        return _tr_err_it("it: bad pattern pointer");
      }
      let plen = _tr_le32(data, off);
      if plen > n - off {
        return _tr_err_it("it: bad pattern pointer");
      }
      let prows = _tr_le16(data, off + 4);
      if prows < 1 {
        return _tr_err_it("it: bad pattern rows");
      }
      if prows > 1024 {
        return _tr_err_it("it: bad pattern rows");
      }
      rows.push(prows);
      packed.push(plen);
    }
    i = i + 1;
  }
  let info = ItInfo{
    name: _tr_printable_prefix(data, 4, 26);
    ordnum: ordnum;
    insnum: insnum;
    smpnum: smpnum;
    patnum: patnum;
    cwtv: _tr_le16(data, 40);
    cmwt: _tr_le16(data, 42);
    flags: _tr_le16(data, 44);
    special: _tr_le16(data, 46);
    global_volume: gv;
    mix_volume: mv;
    initial_speed: speed;
    initial_tempo: tempo;
    message_length: _tr_le16(data, 54);
    order: order;
    pattern_rows: rows;
    pattern_packed: packed;
  };
  return _tr_ok_it(info);
}

/// True when it_parse succeeds. Complexity: O(data.len()).
pub fn it_is_valid(data: &Vec[UInt8]) -> Bool {
  let r = it_parse(data);
  return r.is_ok;
}

// --------------------------------------------------
//  Public API: NSF
// --------------------------------------------------

/// Parse a 128-byte NES Sound Format (NSF) header.
///
/// Checks, in order (first failure wins): non-empty buffer; the 128-byte
/// header; the "NESM" magic plus 0x1A marker at offset 4; version 1..2;
/// at least one song; a starting song index below the song count. The PRG
/// payload after offset 128 is opaque and reported as `data_size`.
///
/// See SPEC.md for the layout table and the error catalog.
/// Complexity: O(data.len()).
pub fn nsf_parse(data: &Vec[UInt8]) -> Result[NsfInfo, Str] {
  let n = data.len();
  if n == 0 {
    return _tr_err_nsf("nsf: empty input");
  }
  if n < 128 {
    return _tr_err_nsf("nsf: truncated header");
  }
  if !_tr_tag4(data, 0, 78, 69, 83, 77) {
    return _tr_err_nsf("nsf: bad NESM magic");
  }
  if _tr_byte(data, 4) != 26 {
    return _tr_err_nsf("nsf: bad NESM magic");
  }
  let version = _tr_byte(data, 5);
  if version < 1 {
    return _tr_err_nsf("nsf: bad version");
  }
  if version > 2 {
    return _tr_err_nsf("nsf: bad version");
  }
  let total = _tr_byte(data, 6);
  if total == 0 {
    return _tr_err_nsf("nsf: zero songs");
  }
  let start = _tr_byte(data, 7);
  if start >= total {
    return _tr_err_nsf("nsf: bad starting song");
  }
  var banks = Vec[Int].new();
  var i = 0;
  while i < 8 {
    banks.push(_tr_byte(data, 112 + i));
    i = i + 1;
  }
  let info = NsfInfo{
    version: version;
    total_songs: total;
    starting_song: start;
    load_address: _tr_le16(data, 8);
    init_address: _tr_le16(data, 10);
    play_address: _tr_le16(data, 12);
    name: _tr_printable_prefix(data, 14, 32);
    artist: _tr_printable_prefix(data, 46, 32);
    copyright: _tr_printable_prefix(data, 78, 32);
    ntsc_speed: _tr_le16(data, 110);
    pal_speed: _tr_le16(data, 120);
    pal_flag: _tr_byte(data, 122);
    chip_flags: _tr_byte(data, 123);
    banks: banks;
    data_size: n - 128;
  };
  return _tr_ok_nsf(info);
}

/// True when nsf_parse succeeds. Complexity: O(data.len()).
pub fn nsf_is_valid(data: &Vec[UInt8]) -> Bool {
  let r = nsf_parse(data);
  return r.is_ok;
}
