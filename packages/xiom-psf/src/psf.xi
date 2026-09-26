// XIOM -- xiom.psf: PSF1/PSF2 console-font codec (glyph bytes and unicode tables)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure XIOM, no FFI. PSF (PC Screen Font) is the Linux console font format
// in two header flavours:
//
//   PSF1: magic 0x36 0x04, one mode byte (bit 0: 512 glyphs else 256; bit 1:
//         unicode table present; bits 2..7 reserved and rejected), one
//         charsize byte (1..32), char_count * charsize glyph bytes, then the
//         optional unicode table: per glyph a run of little-endian u16
//         codepoints terminated by 0xFFFF. Width is 8 columns and height
//         equals charsize (documented; PSF1 carries neither as a field).
//   PSF2: 32-byte little-endian header (magic 0x72 0xB5 0x4A 0x86, version 0,
//         header size 32, flags bit 0 = unicode table with bits 1+ reserved,
//         glyph count, charsize 1..256, height, width 1..64), then
//         char_count * charsize glyph bytes, then the optional unicode table
//         exactly as in PSF1.
//
// The codec validates and indexes either flavour into a flat PsfFont (header
// scalars plus per-glyph unicode ranges over one shared codepoint pool -- no
// Vec of structs), exposes header accessors, a per-glyph codepoint pair and
// a first-match codepoint lookup, copies a glyph's bytes, and builds
// canonical PSF1/PSF2 streams from raw glyph bytes plus optional per-glyph
// codepoint lists. See SPEC.md for the exact layouts, the pinned policies,
// the error catalog and the test matrix.
//
// v0.61.3 notes that shaped this module:
//   * free functions only; state travels by reference.
//   * all Ok/Err construction is confined to the leaf helpers below
//     (constructing a Result with a struct payload elsewhere miscompiles).
//   * every raw byte widens through `(b as Int) & 0xFF`; mode/flag bits are
//     tested arithmetically (% 2, / 2), never with shifts or masks.
//   * the per-glyph Vecs are appended only in lockstep.

module xiom.psf

// Parsed PSF font index. The header fields are scalars; the optional unicode
// table is flattened into a codepoint pool plus two parallel per-glyph
// vectors. When has_unicode is false, uni_starts/uni_counts/uni_values are
// empty; when it is true, uni_starts.len() == uni_counts.len() ==
// char_count and uni_values holds every codepoint of every glyph in glyph
// order, without the 0xFFFF terminators. Values are implementation details;
// callers should go through the free functions below.
pub type PsfFont = {
  version: Int;          // 1 (PSF1) or 2 (PSF2)
  char_count: Int;       // glyph count: 256/512 (PSF1), header length (PSF2)
  charsize: Int;         // bytes per glyph: 1..32 (PSF1), 1..256 (PSF2)
  height: Int;           // PSF2 header height; PSF1 = charsize (documented)
  width: Int;            // PSF2 header width 1..64; PSF1 = 8 (documented)
  has_unicode: Bool;     // unicode table present in the source
  glyph_offset: Int;     // start of the glyph area: 4 (PSF1) or 32 (PSF2)
  uni_starts: Vec[Int];  // per glyph: index into uni_values (empty if absent)
  uni_counts: Vec[Int];  // per glyph: codepoint count (empty if absent)
  uni_values: Vec[Int];  // flat codepoint pool in glyph order
}

// ---------------------------------------------------------------------------
// Result leaf helpers (v0.61.3: Ok/Err construction is confined to fns that
// return a Result directly, so fallible public fns return through these).
// ---------------------------------------------------------------------------

// Ok(v) for Result[PsfFont, Str].
fn _ok_font(v: PsfFont) -> Result[PsfFont, Str] { return Ok(v); }

// Err(m) for Result[PsfFont, Str].
fn _err_font(m: Str) -> Result[PsfFont, Str] { return Err(m); }

// Ok(v) for Result[Vec[UInt8], Str].
fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], Str] { return Ok(v); }

// Err(m) for Result[Vec[UInt8], Str].
fn _err_bytes(m: Str) -> Result[Vec[UInt8], Str] { return Err(m); }

// ---------------------------------------------------------------------------
// Byte readers and writers (little-endian, arithmetic only)
// ---------------------------------------------------------------------------

// Byte at index `pos` widened to an Int (0..255); callers guarantee bounds.
fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// Unsigned little-endian u16 at `pos`; the caller guarantees pos + 2 <= len.
fn _le16(data: &Vec[UInt8], pos: Int) -> Int {
  let b0: Int = (data[pos] as Int) & 0xFF;
  let b1: Int = (data[pos + 1] as Int) & 0xFF;
  return b0 + b1 * 256;
}

// Unsigned little-endian u32 at `pos`; the caller guarantees pos + 4 <= len.
fn _le32(data: &Vec[UInt8], pos: Int) -> Int {
  let b0: Int = (data[pos] as Int) & 0xFF;
  let b1: Int = (data[pos + 1] as Int) & 0xFF;
  let b2: Int = (data[pos + 2] as Int) & 0xFF;
  let b3: Int = (data[pos + 3] as Int) & 0xFF;
  return b0 + b1 * 256 + b2 * 65536 + b3 * 16777216;
}

// Append the low 16 bits of `v` (0..65535) as two little-endian bytes.
fn _put_u16le(out: &mut Vec[UInt8], v: Int) {
  out.push((v % 256) as UInt8);
  out.push(((v / 256) % 256) as UInt8);
}

// Append the low 32 bits of `v` (0..4294967295) as four little-endian bytes.
fn _put_u32le(out: &mut Vec[UInt8], v: Int) {
  out.push((v % 256) as UInt8);
  out.push(((v / 256) % 256) as UInt8);
  out.push(((v / 65536) % 256) as UInt8);
  out.push(((v / 16777216) % 256) as UInt8);
}

// Append the bytes of `v` verbatim.
fn _put_bytes(out: &mut Vec[UInt8], v: &Vec[UInt8]) {
  var i = 0;
  while (i < v.len()) {
    out.push(v[i]);
    i = i + 1;
  }
}

// ---------------------------------------------------------------------------
// Builder helpers
// ---------------------------------------------------------------------------

// Classify the per-glyph codepoint lists: -1 when any codepoint is outside
// 0..65534 (0xFFFF is the terminator and cannot be an entry), 0 when every
// list is empty, 1 when at least one list carries a codepoint.
fn _uni_class(uni: &Vec[Vec[Int]], char_count: Int) -> Int {
  var cls = 0;
  var g = 0;
  while (g < char_count) {
    let list: Vec[Int] = uni[g];
    let ln = list.len();
    if (ln > 0) { cls = 1; }
    var i = 0;
    while (i < ln) {
      let cp: Int = list[i];
      if (cp < 0) { return -1; }
      if (cp > 65534) { return -1; }
      i = i + 1;
    }
    g = g + 1;
  }
  return cls;
}

// Append the unicode table for `char_count` glyphs: each list's codepoints
// as little-endian u16 values, then the 0xFFFF terminator. Empty lists emit
// the terminator alone.
fn _put_unicode(out: &mut Vec[UInt8], uni: &Vec[Vec[Int]], char_count: Int) {
  var g = 0;
  while (g < char_count) {
    let list: Vec[Int] = uni[g];
    let ln = list.len();
    var i = 0;
    while (i < ln) {
      let cp: Int = list[i];
      _put_u16le(out, cp);
      i = i + 1;
    }
    _put_u16le(out, 65535);
    g = g + 1;
  }
}

// ---------------------------------------------------------------------------
// Header accessors
// ---------------------------------------------------------------------------

// Format version of a parsed font: 1 for PSF1, 2 for PSF2.
pub fn psf_version(p: &PsfFont) -> Int {
  return p.version;
}

// Glyph count: 256 or 512 for PSF1, the header `length` field for PSF2.
pub fn psf_charcount(p: &PsfFont) -> Int {
  return p.char_count;
}

// Bytes per glyph: 1..32 (PSF1) or 1..256 (PSF2). Every glyph span is
// exactly this many bytes.
pub fn psf_charsize(p: &PsfFont) -> Int {
  return p.charsize;
}

// Glyph height in rows: the PSF2 header field, or charsize for PSF1 (PSF1
// has no height field; the documented convention is height == charsize).
pub fn psf_height(p: &PsfFont) -> Int {
  return p.height;
}

// Glyph width in columns: the PSF2 header field (1..64), or the constant 8
// for PSF1 (PSF1 has no width field; the documented convention is width 8).
pub fn psf_width(p: &PsfFont) -> Int {
  return p.width;
}

// True when the source carried a unicode table.
pub fn psf_has_unicode(p: &PsfFont) -> Bool {
  return p.has_unicode;
}

// Glyph bytes span of character `ch`: always charsize, or -1 when `ch` is
// outside 0..psf_charcount(p)-1.
pub fn psf_glyph_span(p: &PsfFont, ch: Int) -> Int {
  if (ch < 0) { return -1; }
  if (ch >= p.char_count) { return -1; }
  return p.charsize;
}

// Codepoint count of character `ch`: 0 when no unicode table is present, and
// -1 when `ch` is outside 0..psf_charcount(p)-1.
pub fn psf_unicode_count(p: &PsfFont, ch: Int) -> Int {
  if (ch < 0) { return -1; }
  if (ch >= p.char_count) { return -1; }
  if (!p.has_unicode) { return 0; }
  let c: Int = p.uni_counts[ch];
  return c;
}

// The `i`-th codepoint of character `ch` (0 <= value <= 65534), or -1 when
// `i` or `ch` is out of range or no unicode table is present.
pub fn psf_unicode_at(p: &PsfFont, ch: Int, i: Int) -> Int {
  if (ch < 0) { return -1; }
  if (ch >= p.char_count) { return -1; }
  if (i < 0) { return -1; }
  if (!p.has_unicode) { return -1; }
  let c: Int = p.uni_counts[ch];
  if (i >= c) { return -1; }
  let s: Int = p.uni_starts[ch];
  let v: Int = p.uni_values[s + i];
  return v;
}

// First character whose unicode list contains codepoint `cp`, scanning
// characters 0..charcount-1 and each list in order; -1 when no character
// matches or `cp` is outside 0..65534 (0xFFFF is the table terminator and is
// never a codepoint). Duplicate codepoints are tolerated: the first match
// wins. Returns -1 when no unicode table is present.
pub fn psf_char_for_unicode(p: &PsfFont, cp: Int) -> Int {
  if (cp < 0) { return -1; }
  if (cp > 65534) { return -1; }
  if (!p.has_unicode) { return -1; }
  var g = 0;
  while (g < p.char_count) {
    let c: Int = p.uni_counts[g];
    let s: Int = p.uni_starts[g];
    var i = 0;
    while (i < c) {
      let v: Int = p.uni_values[s + i];
      if (v == cp) { return g; }
      i = i + 1;
    }
    g = g + 1;
  }
  return -1;
}

// ---------------------------------------------------------------------------
// Parsing
// ---------------------------------------------------------------------------

// Parse and validate a complete PSF1 or PSF2 buffer. The flavour is chosen
// by the magic bytes: 0x36 0x04 for PSF1, 0x72 0xB5 0x4A 0x86 for PSF2.
// Validation is ordered (see SPEC.md): header presence and magic, then the
// PSF1 mode/charsize or the PSF2 version/header size/flags/charsize/width/
// height fields, then the glyph area bounds, then the optional unicode table
// (every glyph's run must be terminated by 0xFFFF) and finally the strict
// trailing-bytes policy: the buffer must end exactly after the glyph area or
// after the last terminator. Returns a flat PsfFont; on error no partial
// index is returned.
pub fn psf_parse(data: &Vec[UInt8]) -> Result[PsfFont, Str] {
  let n = data.len();
  if (n < 2) { return _err_font("psf: truncated header"); }
  let b0: Int = (data[0] as Int) & 0xFF;
  let b1: Int = (data[1] as Int) & 0xFF;
  var version = 0;
  var char_count = 0;
  var charsize = 0;
  var height = 0;
  var width = 0;
  var has_unicode: Bool = false;
  var glyph_offset = 0;
  if (b0 == 54 && b1 == 4) {
    // PSF1: magic 0x36 0x04, mode byte, charsize byte.
    if (n < 4) { return _err_font("psf: truncated header"); }
    let mode: Int = (data[2] as Int) & 0xFF;
    if (mode > 3) { return _err_font("psf: reserved mode bits"); }
    char_count = 256;
    if (mode % 2 == 1) { char_count = 512; }
    if (mode / 2 == 1) { has_unicode = true; }
    charsize = (data[3] as Int) & 0xFF;
    if (charsize < 1) { return _err_font("psf: invalid charsize"); }
    if (charsize > 32) { return _err_font("psf: invalid charsize"); }
    version = 1;
    height = charsize;
    width = 8;
    glyph_offset = 4;
  } else {
    // PSF2: 32-byte little-endian header.
    if (n < 4) { return _err_font("psf: truncated header"); }
    let m0: Int = (data[0] as Int) & 0xFF;
    let m1: Int = (data[1] as Int) & 0xFF;
    let m2: Int = (data[2] as Int) & 0xFF;
    let m3: Int = (data[3] as Int) & 0xFF;
    if (m0 != 114) { return _err_font("psf: bad signature"); }
    if (m1 != 181) { return _err_font("psf: bad signature"); }
    if (m2 != 74) { return _err_font("psf: bad signature"); }
    if (m3 != 134) { return _err_font("psf: bad signature"); }
    if (n < 32) { return _err_font("psf: truncated header"); }
    let ver = _le32(data, 4);
    if (ver != 0) { return _err_font("psf: unsupported version"); }
    let hsize = _le32(data, 8);
    if (hsize != 32) { return _err_font("psf: bad header size"); }
    let flags = _le32(data, 12);
    if (flags > 1) { return _err_font("psf: reserved flag bits"); }
    if (flags == 1) { has_unicode = true; }
    char_count = _le32(data, 16);
    charsize = _le32(data, 20);
    height = _le32(data, 24);
    width = _le32(data, 28);
    if (charsize < 1) { return _err_font("psf: invalid charsize"); }
    if (charsize > 256) { return _err_font("psf: invalid charsize"); }
    if (width < 1) { return _err_font("psf: invalid width"); }
    if (width > 64) { return _err_font("psf: invalid width"); }
    if (height < 1) { return _err_font("psf: invalid height"); }
    version = 2;
    glyph_offset = 32;
  }
  // Glyph area: char_count * charsize must fit after the header. The
  // division form cannot overflow; charsize >= 1 is guaranteed above.
  let avail = n - glyph_offset;
  if (char_count > avail / charsize) { return _err_font("psf: glyph data out of bounds"); }
  let glyph_end = glyph_offset + char_count * charsize;
  var uni_starts = Vec[Int].new();
  var uni_counts = Vec[Int].new();
  var uni_values = Vec[Int].new();
  if (!has_unicode) {
    if (glyph_end != n) { return _err_font("psf: trailing bytes"); }
  } else {
    var pos = glyph_end;
    var g = 0;
    while (g < char_count) {
      uni_starts.push(uni_values.len());
      var count = 0;
      var go: Bool = true;
      while (go) {
        if (pos + 2 > n) { return _err_font("psf: unicode table out of bounds"); }
        let cp = _le16(data, pos);
        pos = pos + 2;
        if (cp == 65535) {
          go = false;
        } else {
          uni_values.push(cp);
          count = count + 1;
        }
      }
      uni_counts.push(count);
      g = g + 1;
    }
    if (pos != n) { return _err_font("psf: trailing bytes"); }
  }
  let font = PsfFont{
    version: version;
    char_count: char_count;
    charsize: charsize;
    height: height;
    width: width;
    has_unicode: has_unicode;
    glyph_offset: glyph_offset;
    uni_starts: uni_starts;
    uni_counts: uni_counts;
    uni_values: uni_values;
  };
  return _ok_font(font);
}

// ---------------------------------------------------------------------------
// Glyph span copier
// ---------------------------------------------------------------------------

// Copy character `ch`'s glyph bytes (psf_charsize of them) out of `data`,
// verbatim. Err("psf: index out of range") when `ch` is outside
// 0..psf_charcount(p)-1; Err("psf: glyph data out of bounds") when the
// recorded span does not fit `data` (a forged or stale index, or a shorter
// buffer than the one that was parsed).
pub fn psf_glyph_bytes(data: &Vec[UInt8], p: &PsfFont, ch: Int) -> Result[Vec[UInt8], Str] {
  if (ch < 0) { return _err_bytes("psf: index out of range"); }
  if (ch >= p.char_count) { return _err_bytes("psf: index out of range"); }
  let cs: Int = p.charsize;
  let off: Int = p.glyph_offset + ch * cs;
  if (off < 0) { return _err_bytes("psf: glyph data out of bounds"); }
  if (off + cs > data.len()) { return _err_bytes("psf: glyph data out of bounds"); }
  var out = Vec[UInt8].new();
  var i = 0;
  while (i < cs) {
    out.push(data[off + i]);
    i = i + 1;
  }
  return _ok_bytes(out);
}

// ---------------------------------------------------------------------------
// Building
// ---------------------------------------------------------------------------

// Build a canonical PSF1 font: magic 0x36 0x04, mode byte (bit 0 set for 512
// glyphs, bit 1 set when a unicode table is emitted), charsize byte, the
// glyph bytes verbatim, then the unicode table when one is emitted.
//
// Params: glyphs - raw glyph bytes, exactly 256*charsize (mode 256) or
//                 512*charsize (mode 512);
//         charsize - bytes per glyph, 1..32;
//         uni - exactly char_count per-glyph codepoint lists; every
//               codepoint must be 0..65534. When every list is empty no
//               unicode table is emitted (bit 1 clear); otherwise the table
//               is emitted for all glyphs, empty lists as a bare terminator.
// Error cases (nothing is emitted unless every check passes):
//   Err("psf: invalid charsize"); Err("psf: bad glyph byte count") when
//   glyphs.len() is neither 256*charsize nor 512*charsize;
//   Err("psf: unicode entry count mismatch") when uni.len() != char_count;
//   Err("psf: invalid codepoint") for a codepoint outside 0..65534.
pub fn psf_build1(glyphs: &Vec[UInt8], charsize: Int, uni: &Vec[Vec[Int]]) -> Result[Vec[UInt8], Str] {
  if (charsize < 1) { return _err_bytes("psf: invalid charsize"); }
  if (charsize > 32) { return _err_bytes("psf: invalid charsize"); }
  var char_count = 0;
  if (glyphs.len() == 256 * charsize) { char_count = 256; }
  if (glyphs.len() == 512 * charsize) { char_count = 512; }
  if (char_count == 0) { return _err_bytes("psf: bad glyph byte count"); }
  if (uni.len() != char_count) { return _err_bytes("psf: unicode entry count mismatch"); }
  let cls = _uni_class(uni, char_count);
  if (cls < 0) { return _err_bytes("psf: invalid codepoint"); }
  var mode = 0;
  if (char_count == 512) { mode = 1; }
  if (cls == 1) { mode = mode + 2; }
  var out = Vec[UInt8].new();
  out.push(54 as UInt8);
  out.push(4 as UInt8);
  out.push(mode as UInt8);
  out.push(charsize as UInt8);
  _put_bytes(&mut out, glyphs);
  if (cls == 1) { _put_unicode(&mut out, uni, char_count); }
  return _ok_bytes(out);
}

// Build a canonical PSF2 font: the 32-byte little-endian header (magic
// 0x72 0xB5 0x4A 0x86, version 0, header size 32, flags bit 0 set when a
// unicode table is emitted, glyph count, charsize, height, width), the glyph
// bytes verbatim, then the unicode table when one is emitted.
//
// Params: glyphs - raw glyph bytes, a whole multiple of charsize;
//         charsize - bytes per glyph, 1..256;
//         height - glyph height in rows, >= 1;
//         width - glyph width in columns, 1..64;
//         uni - exactly char_count per-glyph codepoint lists, codepoints
//               0..65534; all-empty means no table (flags bit 0 clear).
// Error cases (nothing is emitted unless every check passes):
//   Err("psf: invalid charsize"); Err("psf: invalid height");
//   Err("psf: invalid width"); Err("psf: bad glyph byte count") when
//   glyphs.len() is not a multiple of charsize;
//   Err("psf: unicode entry count mismatch") when uni.len() != char_count;
//   Err("psf: invalid codepoint") for a codepoint outside 0..65534.
pub fn psf_build2(glyphs: &Vec[UInt8], charsize: Int, height: Int, width: Int, uni: &Vec[Vec[Int]]) -> Result[Vec[UInt8], Str] {
  if (charsize < 1) { return _err_bytes("psf: invalid charsize"); }
  if (charsize > 256) { return _err_bytes("psf: invalid charsize"); }
  if (height < 1) { return _err_bytes("psf: invalid height"); }
  if (width < 1) { return _err_bytes("psf: invalid width"); }
  if (width > 64) { return _err_bytes("psf: invalid width"); }
  if (glyphs.len() % charsize != 0) { return _err_bytes("psf: bad glyph byte count"); }
  let char_count = glyphs.len() / charsize;
  if (uni.len() != char_count) { return _err_bytes("psf: unicode entry count mismatch"); }
  let cls = _uni_class(uni, char_count);
  if (cls < 0) { return _err_bytes("psf: invalid codepoint"); }
  var flags = 0;
  if (cls == 1) { flags = 1; }
  var out = Vec[UInt8].new();
  out.push(114 as UInt8);
  out.push(181 as UInt8);
  out.push(74 as UInt8);
  out.push(134 as UInt8);
  _put_u32le(&mut out, 0);
  _put_u32le(&mut out, 32);
  _put_u32le(&mut out, flags);
  _put_u32le(&mut out, char_count);
  _put_u32le(&mut out, charsize);
  _put_u32le(&mut out, height);
  _put_u32le(&mut out, width);
  _put_bytes(&mut out, glyphs);
  if (cls == 1) { _put_unicode(&mut out, uni, char_count); }
  return _ok_bytes(out);
}
