// XIOM -- xiom.png: PNG (W3C PNG 1.2) container codec
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure XIOM, no FFI. This module implements the container layer of the
// Portable Network Graphics format (W3C PNG 1.2, RFC 2083) over flat
// Vec[UInt8] buffers:
//
//   signature := 89 50 4E 47 0D 0A 1A 0A
//   chunk     := BE32(length) type[4] data[length] BE32(crc32(type data))
//
// Parsing validates the 8-byte signature, walks the chunk stream, verifies
// every chunk CRC-32 (IEEE, reflected polynomial 0xEDB88320, implemented
// locally), and validates the known chunk kinds:
//
//   IHDR  dimensions, bit depth, color type, compression/filter/interlace
//   PLTE  palette entries (3 bytes each, 1..256), ordering and size limits
//   IDAT  image data presence (payload bytes are never decompressed)
//   IEND  zero length and end-of-buffer terminator
//   tRNS  transparency samples / palette alpha (length and ordering rules)
//   gAMA  image gamma (exactly 4 bytes, non-zero)
//   pHYs  physical pixel size (9 bytes, unit 0 or 1)
//   sRGB  rendering intent (1 byte, 0..3)
//   tEXt  Latin-1 keyword + text (NUL separated)
//   zTXt  keyword + zlib-compressed text (method must be 0, not inflated)
//   iTXt  keyword + UTF-8 text (flag/method/language/translated keyword)
//
// Ordering rules enforced: IHDR is the first chunk and appears once, IEND is
// the last chunk with no bytes after it, PLTE precedes IDAT (and forbids
// color types 0 and 4), tRNS follows PLTE and precedes IDAT for color type 3,
// gAMA and sRGB precede PLTE and IDAT, pHYs precedes IDAT, and text chunks
// may appear anywhere. Unknown chunk types are structurally validated
// (reserved bit, CRC, length) but not interpreted.
//
// The whole buffer must be in memory; only structure is parsed, never pixels.
// Parsed results use parallel Vec fields (no Vec[StructType]): the chunk index
// (chunk_type/chunk_offset/chunk_length/chunk_data_offset/chunk_crc) and the
// text index (text_kind/text_offset/text_length/text_keyword/text_value/
// text_lang/text_translated/text_compressed/text_method).
//
// v0.61.3 notes that shaped this module:
//   * Ok/Err construction is confined to the tiny leaf helpers below.
//   * every byte read from a Vec[UInt8] is widened with
//     `(data[i] as Int) & 0xFF` (0x89 is the first signature byte).
//   * every Vec[Int]/Vec[Str] element read is bound to a typed local.
//   * Strs built from file bytes are only created after the byte range is
//     validated NUL-free (builder.sb_to_str hands out a NUL-terminated
//     string; a raw 0x00 would trip its length contract at run time).
//   * iTXt text and translated keywords are checked with a local strict
//     RFC 3629 scanner: xiom.utf8.utf8_validate treats unrecognized lead
//     bytes (standalone 0x80..0xBF, 0xF8..0xFF) as one ASCII byte.
//   * no Vec[Float64], no lambdas, no methods, no table-driven dispatch.
// See SPEC.md for the byte layout tables, the validation order, the full
// error catalog and the test matrix.

module xiom.png

use xiom.convert;
use xiom.string.builder;

// --------------------------------------------------
//  Constants
// --------------------------------------------------

/// Size of the PNG signature in bytes.
pub fn png_signature_size() -> Int {
  return 8;
}

/// Size of a chunk header in bytes: BE32 length + 4-byte type.
pub fn png_chunk_header_size() -> Int {
  return 8;
}

/// Size of the trailing chunk CRC field in bytes.
pub fn png_chunk_crc_size() -> Int {
  return 4;
}

/// Smallest possible complete chunk in bytes: 8 header + 4 CRC, empty data.
pub fn png_min_chunk_size() -> Int {
  return 12;
}

/// Largest legal chunk data length: 2^31 - 1 (the PNG 1.2 upper bound).
pub fn png_max_chunk_length() -> Int {
  return 2147483647;
}

/// Text index kind code for a tEXt chunk.
pub fn png_text_kind_text() -> Int {
  return 0;
}

/// Text index kind code for a zTXt chunk.
pub fn png_text_kind_ztxt() -> Int {
  return 1;
}

/// Text index kind code for an iTXt chunk.
pub fn png_text_kind_itxt() -> Int {
  return 2;
}

// --------------------------------------------------
//  Public types
// --------------------------------------------------

/// Parsed PNG container.
///
/// Header fields decode the validated 13-byte IHDR: dimensions are positive
/// 32-bit values (`width`, `height`), `bit_depth`, `color_type`,
/// `compression`, `filter` and `interlace` are the validated single bytes
/// (compression and filter are always 0, interlace is 0 or 1).
///
/// Chunk index: one entry per chunk in stream order (IHDR through IEND).
/// `chunk_type` is the 4-letter type as a Str, `chunk_offset` is the absolute
/// offset of the length field, `chunk_length` the declared data length,
/// `chunk_data_offset` the absolute offset of the first data byte and
/// `chunk_crc` the CRC-32 read from the stream (already verified).
///
/// Ancillary state: `has_plte`/`has_trns` are 0 or 1 and `palette`/`trns`
/// hold the raw chunk payload bytes when present (PLTE: 3 bytes per entry).
/// `gamma`, `phys_x`, `phys_y`, `phys_unit` and `srgb_intent` are -1 when the
/// chunk is absent, otherwise the stored values.
///
/// Text index: parallel vectors with one entry per tEXt/zTXt/iTXt chunk.
/// `text_kind` is 0 (tEXt), 1 (zTXt) or 2 (iTXt); `text_offset`/`text_length`
/// locate the raw chunk data; `text_keyword` is the validated keyword;
/// `text_value` is the decoded text for tEXt and uncompressed iTXt, "" for
/// zTXt and compressed iTXt; `text_lang`/`text_translated` carry the iTXt
/// language tag and translated keyword ("" otherwise); `text_compressed` is
/// 0 for tEXt, 1 for zTXt and the iTXt compression flag; `text_method` is the
/// stored compression method (always 0 when present).
pub type PngImage = {
  width: Int;
  height: Int;
  bit_depth: Int;
  color_type: Int;
  compression: Int;
  filter: Int;
  interlace: Int;
  has_plte: Int;
  palette: Vec[UInt8];
  has_trns: Int;
  trns: Vec[UInt8];
  gamma: Int;
  phys_x: Int;
  phys_y: Int;
  phys_unit: Int;
  srgb_intent: Int;
  chunk_type: Vec[Str];
  chunk_offset: Vec[Int];
  chunk_length: Vec[Int];
  chunk_data_offset: Vec[Int];
  chunk_crc: Vec[Int];
  text_kind: Vec[Int];
  text_offset: Vec[Int];
  text_length: Vec[Int];
  text_keyword: Vec[Str];
  text_value: Vec[Str];
  text_lang: Vec[Str];
  text_translated: Vec[Str];
  text_compressed: Vec[Int];
  text_method: Vec[Int];
}

// Internal mutable scan state. Mirrors PngImage plus the seen/duplicate flags;
// _finish drops the flags and copies the remainder into the public type.
type _Acc = {
  width: Int;
  height: Int;
  bit_depth: Int;
  color_type: Int;
  compression: Int;
  filter: Int;
  interlace: Int;
  seen_ihdr: Int;
  seen_plte: Int;
  seen_trns: Int;
  seen_idat: Int;
  seen_gama: Int;
  seen_phys: Int;
  seen_srgb: Int;
  gamma: Int;
  phys_x: Int;
  phys_y: Int;
  phys_unit: Int;
  srgb_intent: Int;
  chunk_type: Vec[Str];
  chunk_offset: Vec[Int];
  chunk_length: Vec[Int];
  chunk_data_offset: Vec[Int];
  chunk_crc: Vec[Int];
  palette: Vec[UInt8];
  trns: Vec[UInt8];
  text_kind: Vec[Int];
  text_offset: Vec[Int];
  text_length: Vec[Int];
  text_keyword: Vec[Str];
  text_value: Vec[Str];
  text_lang: Vec[Str];
  text_translated: Vec[Str];
  text_compressed: Vec[Int];
  text_method: Vec[Int];
}

// --------------------------------------------------
//  Result leaf helpers (v0.61.3: Ok/Err may only be constructed in fns that
//  return a Result directly, so every fallible public fn returns through
//  these).
// --------------------------------------------------

// Ok(v) for Result[PngImage, Str].
fn _ok_img(v: PngImage) -> Result[PngImage, Str] {
  return Ok(v);
}

// Err(m) for Result[PngImage, Str].
fn _err_img(m: Str) -> Result[PngImage, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Byte readers, message helpers and predicates
// --------------------------------------------------

// Unsigned byte at index i (widened and masked to 0..255).
fn _b(data: &Vec[UInt8], i: Int) -> Int {
  return (data[i] as Int) & 0xFF;
}

// Big-endian unsigned 32-bit value at `off` (0..4294967295).
fn _be32(data: &Vec[UInt8], off: Int) -> Int {
  return _b(data, off) * 16777216 + _b(data, off + 1) * 65536 + _b(data, off + 2) * 256 + _b(data, off + 3);
}

// Append one message with an absolute byte offset: "<base> at <off>".
fn _at(base: Str, off: Int) -> Str {
  return base + " at " + convert.int_to_string(off);
}

// Append data[start, end) to out.
fn _append_range(out: &mut Vec[UInt8], data: &Vec[UInt8], start: Int, end: Int) {
  var i = start;
  while (i < end) {
    out.push(data[i]);
    i = i + 1;
  }
}

// True when b is an ASCII letter (A-Z or a-z).
fn _is_letter(b: Int) -> Bool {
  if (b >= 65 && b <= 90) { return true; }
  if (b >= 97 && b <= 122) { return true; }
  return false;
}

// True when b is a printable Latin-1 keyword byte (0x20..0x7E, 0xA1..0xFF).
fn _is_keyword_byte(b: Int) -> Bool {
  if (b >= 32 && b <= 126) { return true; }
  if (b >= 161 && b <= 255) { return true; }
  return false;
}

// True when b is an accepted text byte: printable ASCII (0x20..0x7E),
// TAB/LF/CR, or 0xA0..0xFF. NUL and every other C0 control are rejected.
fn _is_text_byte(b: Int) -> Bool {
  if (b == 9 || b == 10 || b == 13) { return true; }
  if (b >= 32 && b <= 126) { return true; }
  if (b >= 160 && b <= 255) { return true; }
  return false;
}

// True when every byte of data[start, end) is a keyword byte.
fn _keyword_range_ok(data: &Vec[UInt8], start: Int, end: Int) -> Bool {
  var i = start;
  while (i < end) {
    let b = _b(data, i);
    if (!_is_keyword_byte(b)) { return false; }
    i = i + 1;
  }
  return true;
}

// True when every byte of data[start, end) is an accepted text byte
// (NUL-free guaranteed).
fn _text_range_ok(data: &Vec[UInt8], start: Int, end: Int) -> Bool {
  var i = start;
  while (i < end) {
    let b = _b(data, i);
    if (!_is_text_byte(b)) { return false; }
    i = i + 1;
  }
  return true;
}

// True when every byte of data[start, end) is printable ASCII (0x20..0x7E).
fn _ascii_range_ok(data: &Vec[UInt8], start: Int, end: Int) -> Bool {
  var i = start;
  while (i < end) {
    let b = _b(data, i);
    if (b < 32 || b > 126) { return false; }
    i = i + 1;
  }
  return true;
}

// True when b is a UTF-8 continuation byte (0x80..0xBF).
fn _is_cont(b: Int) -> Bool {
  return b >= 128 && b <= 191;
}

// Strict RFC 3629 validation of data[start, end). Rejects NUL bytes, invalid
// lead and continuation bytes, overlong forms, UTF-16 surrogate codepoints
// and codepoints above U+10FFFF. Implemented locally because the stdlib
// validator treats every unrecognized lead byte as one ASCII byte.
fn _utf8_range_ok(data: &Vec[UInt8], start: Int, end: Int) -> Bool {
  var i = start;
  while (i < end) {
    let b0 = _b(data, i);
    if (b0 == 0) { return false; }
    if (b0 <= 127) {
      i = i + 1;
    } elif (b0 >= 194 && b0 <= 223) {
      if (i + 1 >= end) { return false; }
      if (!_is_cont(_b(data, i + 1))) { return false; }
      i = i + 2;
    } elif (b0 >= 224 && b0 <= 239) {
      if (i + 2 >= end) { return false; }
      let b1 = _b(data, i + 1);
      let b2 = _b(data, i + 2);
      if (!_is_cont(b1) || !_is_cont(b2)) { return false; }
      if (b0 == 224 && b1 < 160) { return false; }
      if (b0 == 237 && b1 >= 160) { return false; }
      i = i + 3;
    } elif (b0 >= 240 && b0 <= 244) {
      if (i + 3 >= end) { return false; }
      let b1 = _b(data, i + 1);
      let b2 = _b(data, i + 2);
      let b3 = _b(data, i + 3);
      if (!_is_cont(b1) || !_is_cont(b2) || !_is_cont(b3)) { return false; }
      if (b0 == 240 && b1 < 144) { return false; }
      if (b0 == 244 && b1 > 143) { return false; }
      i = i + 4;
    } else {
      return false;
    }
  }
  return true;
}

// Build a Str from the bytes of data[start, end). Callers guarantee the
// range is NUL-free so the NUL-terminated result preserves every byte.
fn _str_range(data: &Vec[UInt8], start: Int, end: Int) -> Str {
  var sb = Vec[UInt8].new();
  var i = start;
  while (i < end) {
    builder.sb_push_byte(&mut sb, data[i]);
    i = i + 1;
  }
  return builder.sb_to_str(&sb);
}

// Index of the first 0x00 byte in data[start, end), or -1.
fn _find_nul(data: &Vec[UInt8], start: Int, end: Int) -> Int {
  var i = start;
  while (i < end) {
    if (_b(data, i) == 0) { return i; }
    i = i + 1;
  }
  return -1;
}

// True when data[off, off+4) is exactly the four type bytes a, b, c, d.
fn _type_is(data: &Vec[UInt8], off: Int, a: Int, b: Int, c: Int, d: Int) -> Bool {
  if (_b(data, off) != a) { return false; }
  if (_b(data, off + 1) != b) { return false; }
  if (_b(data, off + 2) != c) { return false; }
  if (_b(data, off + 3) != d) { return false; }
  return true;
}

// True when data[off, off+4) is the IHDR type.
fn _is_ihdr(data: &Vec[UInt8], off: Int) -> Bool {
  return _type_is(data, off, 73, 72, 68, 82);
}

// True when data[off, off+4) is the IEND type.
fn _is_iend(data: &Vec[UInt8], off: Int) -> Bool {
  return _type_is(data, off, 73, 69, 78, 68);
}

// --------------------------------------------------
//  CRC-32 (IEEE 802.3, as required by PNG)
// --------------------------------------------------

// CRC-32 of data[start, end): init 0xFFFFFFFF, reflected polynomial
// 0xEDB88320, final XOR 0xFFFFFFFF. Returns 0..4294967295.
fn _crc32(data: &Vec[UInt8], start: Int, end: Int) -> Int {
  var c = 4294967295;
  var i = start;
  while (i < end) {
    let b = _b(data, i);
    c = c ^ b;
    var k = 0;
    while (k < 8) {
      if ((c & 1) == 1) {
        c = (c / 2) ^ 3988292384;
      } else {
        c = c / 2;
      }
      k = k + 1;
    }
    i = i + 1;
  }
  return c ^ 4294967295;
}

/// CRC-32 (IEEE, zlib/PKZIP polynomial) of a whole buffer: init 0xFFFFFFFF,
/// reflected polynomial 0xEDB88320, final XOR 0xFFFFFFFF. The check value of
/// "123456789" is 0xCBF43926 (3421780262) and the empty buffer hashes to 0.
/// Complexity: O(data.len()).
pub fn png_crc32(data: &Vec[UInt8]) -> Int {
  return _crc32(data, 0, data.len());
}

// --------------------------------------------------
//  Signature
// --------------------------------------------------

// "" when data starts with the 8-byte PNG signature, otherwise the
// documented error (truncated below 8 bytes, first mismatching byte offset
// otherwise).
fn _signature_error(data: &Vec[UInt8], n: Int) -> Str {
  if (n < 8) { return "png: truncated signature"; }
  if (_b(data, 0) != 137) { return _at("png: bad signature", 0); }
  if (_b(data, 1) != 80) { return _at("png: bad signature", 1); }
  if (_b(data, 2) != 78) { return _at("png: bad signature", 2); }
  if (_b(data, 3) != 71) { return _at("png: bad signature", 3); }
  if (_b(data, 4) != 13) { return _at("png: bad signature", 4); }
  if (_b(data, 5) != 10) { return _at("png: bad signature", 5); }
  if (_b(data, 6) != 26) { return _at("png: bad signature", 6); }
  if (_b(data, 7) != 10) { return _at("png: bad signature", 7); }
  return "";
}

// --------------------------------------------------
//  Index and record helpers
// --------------------------------------------------

// Append one chunk-index record; all five vectors always receive exactly one
// entry, so parallel-Vec drift is structurally impossible.
fn _push_chunk(a: &mut _Acc, t: Str, off: Int, len: Int, data_off: Int, crc: Int) {
  a.chunk_type.push(t);
  a.chunk_offset.push(off);
  a.chunk_length.push(len);
  a.chunk_data_offset.push(data_off);
  a.chunk_crc.push(crc);
}

// Append one text-index record; all nine vectors always receive exactly one
// entry.
fn _push_text(a: &mut _Acc, kind: Int, off: Int, len: Int, keyword: Str, value: Str, lang: Str, translated: Str, compressed: Int, method: Int) {
  a.text_kind.push(kind);
  a.text_offset.push(off);
  a.text_length.push(len);
  a.text_keyword.push(keyword);
  a.text_value.push(value);
  a.text_lang.push(lang);
  a.text_translated.push(translated);
  a.text_compressed.push(compressed);
  a.text_method.push(method);
}

// True for every legal IHDR color type: 0, 2, 3, 4 or 6.
fn _color_type_ok(ctype: Int) -> Bool {
  if (ctype == 0 || ctype == 2 || ctype == 3) { return true; }
  if (ctype == 4 || ctype == 6) { return true; }
  return false;
}

// True for every legal (color type, bit depth) combination of PNG 1.2:
// 0: 1/2/4/8/16, 2: 8/16, 3: 1/2/4/8, 4: 8/16, 6: 8/16.
fn _depth_ok(ctype: Int, depth: Int) -> Bool {
  if (ctype == 0) {
    if (depth == 1 || depth == 2 || depth == 4) { return true; }
    if (depth == 8 || depth == 16) { return true; }
    return false;
  }
  if (ctype == 2) { return depth == 8 || depth == 16; }
  if (ctype == 3) {
    if (depth == 1 || depth == 2 || depth == 4) { return true; }
    return depth == 8;
  }
  if (ctype == 4) { return depth == 8 || depth == 16; }
  if (ctype == 6) { return depth == 8 || depth == 16; }
  return false;
}

// --------------------------------------------------
//  Per-chunk validation helpers: each returns "" on success and appends to
//  the accumulator, or the documented error message.
// --------------------------------------------------

// IHDR: `p` is the chunk offset, `d` the data offset, `len` the data length.
fn _parse_ihdr(a: &mut _Acc, data: &Vec[UInt8], p: Int, d: Int, len: Int) -> Str {
  if (len != 13) { return _at("png: invalid IHDR length", p); }
  let width = _be32(data, d);
  if (width < 1 || width > 2147483647) { return _at("png: invalid width", d); }
  let height = _be32(data, d + 4);
  if (height < 1 || height > 2147483647) { return _at("png: invalid height", d + 4); }
  let depth = _b(data, d + 8);
  let ctype = _b(data, d + 9);
  if (!_color_type_ok(ctype)) { return _at("png: invalid color type", d + 9); }
  if (!_depth_ok(ctype, depth)) { return _at("png: invalid bit depth", d + 8); }
  let comp = _b(data, d + 10);
  if (comp != 0) { return _at("png: invalid compression method", d + 10); }
  let filt = _b(data, d + 11);
  if (filt != 0) { return _at("png: invalid filter method", d + 11); }
  let inter = _b(data, d + 12);
  if (inter != 0 && inter != 1) { return _at("png: invalid interlace method", d + 12); }
  a.width = width;
  a.height = height;
  a.bit_depth = depth;
  a.color_type = ctype;
  a.compression = comp;
  a.filter = filt;
  a.interlace = inter;
  return "";
}

// PLTE: duplicate, length, color-type allowance, ordering, bit-depth capacity.
fn _parse_plte(a: &mut _Acc, data: &Vec[UInt8], p: Int, d: Int, len: Int) -> Str {
  if (a.seen_plte != 0) { return _at("png: duplicate PLTE", p); }
  if (len < 3 || len > 768 || len % 3 != 0) {
    return _at("png: invalid PLTE length", p);
  }
  if (a.color_type == 0 || a.color_type == 4) {
    return _at("png: PLTE not allowed", p);
  }
  if (a.seen_idat != 0) { return _at("png: PLTE after IDAT", p); }
  if (a.seen_trns != 0) { return _at("png: PLTE after tRNS", p); }
  if (a.color_type == 3) {
    let entries = len / 3;
    var max_entries = 1;
    var k = 0;
    while (k < a.bit_depth) {
      max_entries = max_entries * 2;
      k = k + 1;
    }
    if (entries > max_entries) {
      return _at("png: PLTE too large for bit depth", p);
    }
  }
  _append_range(&mut a.palette, data, d, d + len);
  a.seen_plte = 1;
  return "";
}

// tRNS: duplicate, color-type allowance, ordering, per-type length.
fn _parse_trns(a: &mut _Acc, data: &Vec[UInt8], p: Int, d: Int, len: Int) -> Str {
  if (a.seen_trns != 0) { return _at("png: duplicate tRNS", p); }
  if (a.color_type == 4 || a.color_type == 6) {
    return _at("png: tRNS not allowed", p);
  }
  if (a.seen_idat != 0) { return _at("png: tRNS after IDAT", p); }
  if (a.color_type == 3) {
    if (a.seen_plte == 0) { return _at("png: tRNS before PLTE", p); }
    let entries = a.palette.len() / 3;
    if (len < 1 || len > entries) {
      return _at("png: invalid tRNS length", p);
    }
  } elif (a.color_type == 0) {
    if (len != 2) { return _at("png: invalid tRNS length", p); }
  } elif (a.color_type == 2) {
    if (len != 6) { return _at("png: invalid tRNS length", p); }
  }
  _append_range(&mut a.trns, data, d, d + len);
  a.seen_trns = 1;
  return "";
}

// gAMA: duplicate, length, ordering, non-zero value.
fn _parse_gama(a: &mut _Acc, data: &Vec[UInt8], p: Int, d: Int, len: Int) -> Str {
  if (a.seen_gama != 0) { return _at("png: duplicate gAMA", p); }
  if (len != 4) { return _at("png: invalid gAMA length", p); }
  if (a.seen_plte != 0 || a.seen_idat != 0) {
    return _at("png: gAMA after PLTE or IDAT", p);
  }
  let g = _be32(data, d);
  if (g == 0) { return _at("png: invalid gAMA value", d); }
  a.gamma = g;
  a.seen_gama = 1;
  return "";
}

// pHYs: duplicate, length, ordering, unit specifier.
fn _parse_phys(a: &mut _Acc, data: &Vec[UInt8], p: Int, d: Int, len: Int) -> Str {
  if (a.seen_phys != 0) { return _at("png: duplicate pHYs", p); }
  if (len != 9) { return _at("png: invalid pHYs length", p); }
  if (a.seen_idat != 0) { return _at("png: pHYs after IDAT", p); }
  let unit = _b(data, d + 8);
  if (unit > 1) { return _at("png: invalid pHYs unit", d + 8); }
  a.phys_x = _be32(data, d);
  a.phys_y = _be32(data, d + 4);
  a.phys_unit = unit;
  a.seen_phys = 1;
  return "";
}

// sRGB: duplicate, length, ordering, rendering intent.
fn _parse_srgb(a: &mut _Acc, data: &Vec[UInt8], p: Int, d: Int, len: Int) -> Str {
  if (a.seen_srgb != 0) { return _at("png: duplicate sRGB", p); }
  if (len != 1) { return _at("png: invalid sRGB length", p); }
  if (a.seen_plte != 0 || a.seen_idat != 0) {
    return _at("png: sRGB after PLTE or IDAT", p);
  }
  let intent = _b(data, d);
  if (intent > 3) { return _at("png: invalid sRGB intent", d); }
  a.srgb_intent = intent;
  a.seen_srgb = 1;
  return "";
}

// tEXt: keyword NUL text.
fn _parse_text(a: &mut _Acc, data: &Vec[UInt8], p: Int, d: Int, len: Int) -> Str {
  let end = d + len;
  let sep = _find_nul(data, d, end);
  if (sep < 0) { return _at("png: missing keyword separator", d); }
  let klen = sep - d;
  if (klen < 1 || klen > 79) { return _at("png: invalid text keyword", d); }
  if (!_keyword_range_ok(data, d, sep)) {
    return _at("png: invalid text keyword", d);
  }
  let tstart = sep + 1;
  if (!_text_range_ok(data, tstart, end)) {
    return _at("png: invalid text", tstart);
  }
  let keyword = _str_range(data, d, sep);
  let value = _str_range(data, tstart, end);
  _push_text(a, 0, d, len, keyword, value, "", "", 0, 0);
  return "";
}

// zTXt: keyword NUL method compressed-data. The compressed bytes are never
// inflated and never turned into a Str.
fn _parse_ztxt(a: &mut _Acc, data: &Vec[UInt8], p: Int, d: Int, len: Int) -> Str {
  let end = d + len;
  let sep = _find_nul(data, d, end);
  if (sep < 0) { return _at("png: missing keyword separator", d); }
  let klen = sep - d;
  if (klen < 1 || klen > 79) { return _at("png: invalid text keyword", d); }
  if (!_keyword_range_ok(data, d, sep)) {
    return _at("png: invalid text keyword", d);
  }
  let mpos = sep + 1;
  if (mpos >= end) { return _at("png: invalid zTXt method", mpos); }
  let method = _b(data, mpos);
  if (method != 0) { return _at("png: invalid zTXt method", mpos); }
  let keyword = _str_range(data, d, sep);
  _push_text(a, 1, d, len, keyword, "", "", "", 1, method);
  return "";
}

// iTXt: keyword NUL flag method language NUL translated NUL text. Text and
// translated keyword are UTF-8; text is inflated by nobody.
fn _parse_itxt(a: &mut _Acc, data: &Vec[UInt8], p: Int, d: Int, len: Int) -> Str {
  let end = d + len;
  let sep = _find_nul(data, d, end);
  if (sep < 0) { return _at("png: missing keyword separator", d); }
  let klen = sep - d;
  if (klen < 1 || klen > 79) { return _at("png: invalid text keyword", d); }
  if (!_keyword_range_ok(data, d, sep)) {
    return _at("png: invalid text keyword", d);
  }
  let fpos = sep + 1;
  if (fpos >= end) { return _at("png: invalid iTXt flag", fpos); }
  let flag = _b(data, fpos);
  if (flag != 0 && flag != 1) { return _at("png: invalid iTXt flag", fpos); }
  let mpos = fpos + 1;
  if (mpos >= end) { return _at("png: invalid iTXt method", mpos); }
  let method = _b(data, mpos);
  if (method != 0) { return _at("png: invalid iTXt method", mpos); }
  let lstart = mpos + 1;
  let lsep = _find_nul(data, lstart, end);
  if (lsep < 0) { return _at("png: missing language separator", lstart); }
  if (!_ascii_range_ok(data, lstart, lsep)) {
    return _at("png: invalid iTXt language tag", lstart);
  }
  let tkstart = lsep + 1;
  let tksep = _find_nul(data, tkstart, end);
  if (tksep < 0) {
    return _at("png: missing translated keyword separator", tkstart);
  }
  if (!_utf8_range_ok(data, tkstart, tksep)) {
    return _at("png: invalid iTXt translated keyword", tkstart);
  }
  let tstart = tksep + 1;
  var value = "";
  if (flag == 0) {
    if (!_utf8_range_ok(data, tstart, end)) {
      return _at("png: invalid text", tstart);
    }
    value = _str_range(data, tstart, end);
  }
  let keyword = _str_range(data, d, sep);
  let lang = _str_range(data, lstart, lsep);
  let translated = _str_range(data, tkstart, tksep);
  _push_text(a, 2, d, len, keyword, value, lang, translated, flag, method);
  return "";
}

// Move the accumulator into the public result type, dropping the seen flags.
fn _finish(a: _Acc) -> PngImage {
  let width: Int = a.width;
  let height: Int = a.height;
  let bit_depth: Int = a.bit_depth;
  let color_type: Int = a.color_type;
  let compression: Int = a.compression;
  let filter: Int = a.filter;
  let interlace: Int = a.interlace;
  let has_plte: Int = a.seen_plte;
  let palette: Vec[UInt8] = a.palette;
  let has_trns: Int = a.seen_trns;
  let trns: Vec[UInt8] = a.trns;
  let gamma: Int = a.gamma;
  let phys_x: Int = a.phys_x;
  let phys_y: Int = a.phys_y;
  let phys_unit: Int = a.phys_unit;
  let srgb_intent: Int = a.srgb_intent;
  let chunk_type: Vec[Str] = a.chunk_type;
  let chunk_offset: Vec[Int] = a.chunk_offset;
  let chunk_length: Vec[Int] = a.chunk_length;
  let chunk_data_offset: Vec[Int] = a.chunk_data_offset;
  let chunk_crc: Vec[Int] = a.chunk_crc;
  let text_kind: Vec[Int] = a.text_kind;
  let text_offset: Vec[Int] = a.text_offset;
  let text_length: Vec[Int] = a.text_length;
  let text_keyword: Vec[Str] = a.text_keyword;
  let text_value: Vec[Str] = a.text_value;
  let text_lang: Vec[Str] = a.text_lang;
  let text_translated: Vec[Str] = a.text_translated;
  let text_compressed: Vec[Int] = a.text_compressed;
  let text_method: Vec[Int] = a.text_method;
  return PngImage{
    width: width;
    height: height;
    bit_depth: bit_depth;
    color_type: color_type;
    compression: compression;
    filter: filter;
    interlace: interlace;
    has_plte: has_plte;
    palette: palette;
    has_trns: has_trns;
    trns: trns;
    gamma: gamma;
    phys_x: phys_x;
    phys_y: phys_y;
    phys_unit: phys_unit;
    srgb_intent: srgb_intent;
    chunk_type: chunk_type;
    chunk_offset: chunk_offset;
    chunk_length: chunk_length;
    chunk_data_offset: chunk_data_offset;
    chunk_crc: chunk_crc;
    text_kind: text_kind;
    text_offset: text_offset;
    text_length: text_length;
    text_keyword: text_keyword;
    text_value: text_value;
    text_lang: text_lang;
    text_translated: text_translated;
    text_compressed: text_compressed;
    text_method: text_method;
  };
}

// --------------------------------------------------
//  Parser
// --------------------------------------------------

/// Parse and fully validate one PNG buffer. Nothing is materialized: the
/// result carries the validated IHDR fields, a chunk index, the raw PLTE and
/// tRNS payloads, the decoded gAMA/pHYs/sRGB values and a text index; pixel
/// data inside IDAT is never decompressed.
///
/// Validation order and messages (see SPEC.md for the catalog):
///   1. fewer than 8 bytes -> "png: truncated signature"; wrong signature
///      bytes -> "png: bad signature at <first mismatch>";
///   2. fewer than 20 bytes total (no room for even a minimal chunk) ->
///      "png: truncated chunk at 8";
///   3. per chunk: fewer than 12 bytes, a data length above 2^31-1, or a
///      length that runs past the buffer -> "png: truncated chunk at <offset>"
///      / "png: chunk length overflow at <offset>"; type bytes must be
///      letters with an uppercase third byte -> "png: invalid chunk type at
///      <offset>"; the stored CRC-32 must match -> "png: crc mismatch at
///      <offset>";
///   4. the first chunk must be IHDR -> "png: missing IHDR at 8"; a second
///      IHDR -> "png: duplicate IHDR";
///   5. IHDR fields: length, dimensions, color type, bit depth, compression,
///      filter, interlace (catalog below);
///   6. known ancillary chunks in file order, each with its own ordering and
///      duplicate rules (PLTE, tRNS, gAMA, pHYs, sRGB, tEXt, zTXt, iTXt);
///   7. IEND: zero length, end of buffer -> "png: invalid IEND length at
///      <offset>" / "png: data after IEND at <offset>";
///   8. after the loop: "png: missing IEND", then "png: missing IDAT", then
///      "png: missing PLTE" for color type 3.
/// Complexity: O(input bytes).
pub fn png_parse(data: &Vec[UInt8]) -> Result[PngImage, Str] {
  let n = data.len();
  let sig = _signature_error(data, n);
  if (sig.len() > 0) { return _err_img(sig); }
  if (n < 20) { return _err_img(_at("png: truncated chunk", 8)); }
  var a = _Acc{
    width: 0;
    height: 0;
    bit_depth: 0;
    color_type: -1;
    compression: 0;
    filter: 0;
    interlace: 0;
    seen_ihdr: 0;
    seen_plte: 0;
    seen_trns: 0;
    seen_idat: 0;
    seen_gama: 0;
    seen_phys: 0;
    seen_srgb: 0;
    gamma: -1;
    phys_x: -1;
    phys_y: -1;
    phys_unit: -1;
    srgb_intent: -1;
    chunk_type: Vec[Str].new();
    chunk_offset: Vec[Int].new();
    chunk_length: Vec[Int].new();
    chunk_data_offset: Vec[Int].new();
    chunk_crc: Vec[Int].new();
    palette: Vec[UInt8].new();
    trns: Vec[UInt8].new();
    text_kind: Vec[Int].new();
    text_offset: Vec[Int].new();
    text_length: Vec[Int].new();
    text_keyword: Vec[Str].new();
    text_value: Vec[Str].new();
    text_lang: Vec[Str].new();
    text_translated: Vec[Str].new();
    text_compressed: Vec[Int].new();
    text_method: Vec[Int].new();
  };
  var pos = 8;
  var saw_iend = 0;
  while (pos < n) {
    if (pos + 12 > n) { return _err_img(_at("png: truncated chunk", pos)); }
    let len = _be32(data, pos);
    if (len > 2147483647) {
      return _err_img(_at("png: chunk length overflow", pos));
    }
    if (pos + 12 + len > n) {
      return _err_img(_at("png: truncated chunk", pos));
    }
    let d = pos + 8;
    let t0 = _b(data, pos + 4);
    let t1 = _b(data, pos + 5);
    let t2 = _b(data, pos + 6);
    let t3 = _b(data, pos + 7);
    if (!_is_letter(t0) || !_is_letter(t1) || !_is_letter(t2) || !_is_letter(t3)) {
      return _err_img(_at("png: invalid chunk type", pos + 4));
    }
    if (t2 < 65 || t2 > 90) {
      return _err_img(_at("png: invalid chunk type", pos + 4));
    }
    let stored_crc = _be32(data, pos + 8 + len);
    let computed_crc = _crc32(data, pos + 4, pos + 8 + len);
    if (stored_crc != computed_crc) {
      return _err_img(_at("png: crc mismatch", pos + 8 + len));
    }
    if (pos == 8 && !_is_ihdr(data, pos + 4)) {
      return _err_img(_at("png: missing IHDR", pos));
    }
    let tname = _str_range(data, pos + 4, pos + 8);
    _push_chunk(&mut a, tname, pos, len, d, stored_crc);
    if (_is_ihdr(data, pos + 4)) {
      if (a.seen_ihdr != 0) { return _err_img(_at("png: duplicate IHDR", pos)); }
      let e = _parse_ihdr(&mut a, data, pos, d, len);
      if (e.len() > 0) { return _err_img(e); }
      a.seen_ihdr = 1;
    } elif (_type_is(data, pos + 4, 80, 76, 84, 69)) {
      let e = _parse_plte(&mut a, data, pos, d, len);
      if (e.len() > 0) { return _err_img(e); }
    } elif (_type_is(data, pos + 4, 73, 68, 65, 84)) {
      a.seen_idat = 1;
    } elif (_type_is(data, pos + 4, 116, 82, 78, 83)) {
      let e = _parse_trns(&mut a, data, pos, d, len);
      if (e.len() > 0) { return _err_img(e); }
    } elif (_type_is(data, pos + 4, 103, 65, 77, 65)) {
      let e = _parse_gama(&mut a, data, pos, d, len);
      if (e.len() > 0) { return _err_img(e); }
    } elif (_type_is(data, pos + 4, 112, 72, 89, 115)) {
      let e = _parse_phys(&mut a, data, pos, d, len);
      if (e.len() > 0) { return _err_img(e); }
    } elif (_type_is(data, pos + 4, 115, 82, 71, 66)) {
      let e = _parse_srgb(&mut a, data, pos, d, len);
      if (e.len() > 0) { return _err_img(e); }
    } elif (_type_is(data, pos + 4, 116, 69, 88, 116)) {
      let e = _parse_text(&mut a, data, pos, d, len);
      if (e.len() > 0) { return _err_img(e); }
    } elif (_type_is(data, pos + 4, 122, 84, 88, 116)) {
      let e = _parse_ztxt(&mut a, data, pos, d, len);
      if (e.len() > 0) { return _err_img(e); }
    } elif (_type_is(data, pos + 4, 105, 84, 88, 116)) {
      let e = _parse_itxt(&mut a, data, pos, d, len);
      if (e.len() > 0) { return _err_img(e); }
    }
    if (_is_iend(data, pos + 4)) {
      if (len != 0) { return _err_img(_at("png: invalid IEND length", pos)); }
      if (pos + 12 != n) {
        return _err_img(_at("png: data after IEND", pos + 12));
      }
      saw_iend = 1;
      pos = n;
    } else {
      pos = pos + 12 + len;
    }
  }
  if (saw_iend == 0) { return _err_img("png: missing IEND"); }
  if (a.seen_idat == 0) { return _err_img("png: missing IDAT"); }
  if (a.color_type == 3 && a.seen_plte == 0) { return _err_img("png: missing PLTE"); }
  return _ok_img(_finish(a));
}

// --------------------------------------------------
//  Classification
// --------------------------------------------------

/// True when the buffer starts with the 8-byte PNG signature. Malformed or
/// short buffers return false rather than an error; use png_parse when the
/// reason matters. Complexity: O(1).
pub fn png_is_png(data: &Vec[UInt8]) -> Bool {
  return _signature_error(data, data.len()).len() == 0;
}

// --------------------------------------------------
//  Header accessors
// --------------------------------------------------

/// Image width in pixels (1..2147483647).
/// Complexity: O(1).
pub fn png_width(img: &PngImage) -> Int {
  return img.width;
}

/// Image height in pixels (1..2147483647).
/// Complexity: O(1).
pub fn png_height(img: &PngImage) -> Int {
  return img.height;
}

/// IHDR bit depth (1, 2, 4, 8 or 16 depending on the color type).
/// Complexity: O(1).
pub fn png_bit_depth(img: &PngImage) -> Int {
  return img.bit_depth;
}

/// IHDR color type: 0 gray, 2 truecolor, 3 indexed, 4 gray+alpha, 6 RGBA.
/// Complexity: O(1).
pub fn png_color_type(img: &PngImage) -> Int {
  return img.color_type;
}

/// IHDR compression method (always 0).
/// Complexity: O(1).
pub fn png_compression(img: &PngImage) -> Int {
  return img.compression;
}

/// IHDR filter method (always 0).
/// Complexity: O(1).
pub fn png_filter(img: &PngImage) -> Int {
  return img.filter;
}

/// IHDR interlace method: 0 = none, 1 = Adam7.
/// Complexity: O(1).
pub fn png_interlace(img: &PngImage) -> Int {
  return img.interlace;
}

/// Number of chunks in the chunk index (including IHDR and IEND).
/// Complexity: O(1).
pub fn png_chunk_count(img: &PngImage) -> Int {
  return img.chunk_offset.len();
}

// --------------------------------------------------
//  Chunk index accessors (out-of-range values return "" or -1)
// --------------------------------------------------

/// Type of chunk `i` as a 4-letter Str, or "" when `i` is outside the index.
/// Because the value comes from a Vec[Str], compare it with
/// xiom.string.compare.str_compare, never with `==`.
/// Complexity: O(1).
pub fn png_chunk_type(img: &PngImage, i: Int) -> Str {
  if (i < 0 || i >= img.chunk_type.len()) { return ""; }
  let v: Str = img.chunk_type[i];
  return v;
}

/// Absolute offset of chunk `i`'s length field, or -1 when out of range.
/// Complexity: O(1).
pub fn png_chunk_offset(img: &PngImage, i: Int) -> Int {
  if (i < 0 || i >= img.chunk_offset.len()) { return -1; }
  let v: Int = img.chunk_offset[i];
  return v;
}

/// Declared data length of chunk `i`, or -1 when out of range.
/// Complexity: O(1).
pub fn png_chunk_length(img: &PngImage, i: Int) -> Int {
  if (i < 0 || i >= img.chunk_length.len()) { return -1; }
  let v: Int = img.chunk_length[i];
  return v;
}

/// Absolute offset of chunk `i`'s first data byte, or -1 when out of range.
/// Complexity: O(1).
pub fn png_chunk_data_offset(img: &PngImage, i: Int) -> Int {
  if (i < 0 || i >= img.chunk_data_offset.len()) { return -1; }
  let v: Int = img.chunk_data_offset[i];
  return v;
}

/// Verified CRC-32 stored in chunk `i`, or -1 when out of range.
/// Complexity: O(1).
pub fn png_chunk_crc(img: &PngImage, i: Int) -> Int {
  if (i < 0 || i >= img.chunk_crc.len()) { return -1; }
  let v: Int = img.chunk_crc[i];
  return v;
}

// --------------------------------------------------
//  Ancillary state accessors
// --------------------------------------------------

/// True when a PLTE chunk was present.
/// Complexity: O(1).
pub fn png_has_palette(img: &PngImage) -> Bool {
  return img.has_plte != 0;
}

/// Number of palette entries (palette bytes / 3), 0 when there is no PLTE.
/// Complexity: O(1).
pub fn png_palette_entries(img: &PngImage) -> Int {
  return img.palette.len() / 3;
}

/// Palette byte `i` of the raw PLTE payload (0..255), or -1 when `i` is
/// outside the payload.
/// Complexity: O(1).
pub fn png_palette_byte(img: &PngImage, i: Int) -> Int {
  if (i < 0 || i >= img.palette.len()) { return -1; }
  let v: Int = (img.palette[i] as Int) & 0xFF;
  return v;
}

/// True when a tRNS chunk was present.
/// Complexity: O(1).
pub fn png_has_trns(img: &PngImage) -> Bool {
  return img.has_trns != 0;
}

/// Length in bytes of the raw tRNS payload, 0 when there is no tRNS.
/// Complexity: O(1).
pub fn png_trns_len(img: &PngImage) -> Int {
  return img.trns.len();
}

/// Image gamma stored by gAMA as an integer scaled by 100000, or -1 when the
/// chunk is absent.
/// Complexity: O(1).
pub fn png_gamma(img: &PngImage) -> Int {
  return img.gamma;
}

/// pHYs pixels-per-unit on the X axis, or -1 when the chunk is absent.
/// Complexity: O(1).
pub fn png_phys_x(img: &PngImage) -> Int {
  return img.phys_x;
}

/// pHYs pixels-per-unit on the Y axis, or -1 when the chunk is absent.
/// Complexity: O(1).
pub fn png_phys_y(img: &PngImage) -> Int {
  return img.phys_y;
}

/// pHYs unit specifier: 0 = unknown, 1 = metre, -1 when the chunk is absent.
/// Complexity: O(1).
pub fn png_phys_unit(img: &PngImage) -> Int {
  return img.phys_unit;
}

/// sRGB rendering intent (0..3), or -1 when the chunk is absent.
/// Complexity: O(1).
pub fn png_srgb_intent(img: &PngImage) -> Int {
  return img.srgb_intent;
}

// --------------------------------------------------
//  Text index accessors (out-of-range values return "" or -1)
// --------------------------------------------------

/// Number of tEXt/zTXt/iTXt entries in the text index.
/// Complexity: O(1).
pub fn png_text_count(img: &PngImage) -> Int {
  return img.text_kind.len();
}

/// Kind of text entry `i` (png_text_kind_text/ztxt/itxt), or -1 when out of
/// range.
/// Complexity: O(1).
pub fn png_text_kind(img: &PngImage, i: Int) -> Int {
  if (i < 0 || i >= img.text_kind.len()) { return -1; }
  let v: Int = img.text_kind[i];
  return v;
}

/// Keyword of text entry `i`, or "" when out of range. Compare the returned
/// Str with str_compare, never with `==`.
/// Complexity: O(1).
pub fn png_text_keyword(img: &PngImage, i: Int) -> Str {
  if (i < 0 || i >= img.text_keyword.len()) { return ""; }
  let v: Str = img.text_keyword[i];
  return v;
}

/// Decoded text of entry `i` (tEXt and uncompressed iTXt), "" for zTXt,
/// compressed iTXt and out-of-range indices.
/// Complexity: O(1).
pub fn png_text_value(img: &PngImage, i: Int) -> Str {
  if (i < 0 || i >= img.text_value.len()) { return ""; }
  let v: Str = img.text_value[i];
  return v;
}

/// iTXt language tag of entry `i` ("" for other kinds and out of range).
/// Complexity: O(1).
pub fn png_text_language(img: &PngImage, i: Int) -> Str {
  if (i < 0 || i >= img.text_lang.len()) { return ""; }
  let v: Str = img.text_lang[i];
  return v;
}

/// iTXt translated keyword of entry `i` ("" for other kinds and out of
/// range).
/// Complexity: O(1).
pub fn png_text_translated(img: &PngImage, i: Int) -> Str {
  if (i < 0 || i >= img.text_translated.len()) { return ""; }
  let v: Str = img.text_translated[i];
  return v;
}

/// Compression state of entry `i`: 0 for tEXt, 1 for zTXt, the flag for
/// iTXt; -1 when out of range.
/// Complexity: O(1).
pub fn png_text_compressed(img: &PngImage, i: Int) -> Int {
  if (i < 0 || i >= img.text_compressed.len()) { return -1; }
  let v: Int = img.text_compressed[i];
  return v;
}

/// Stored compression method of entry `i` (0 for every supported kind), or
/// -1 when out of range.
/// Complexity: O(1).
pub fn png_text_method(img: &PngImage, i: Int) -> Int {
  if (i < 0 || i >= img.text_method.len()) { return -1; }
  let v: Int = img.text_method[i];
  return v;
}

/// Absolute offset of text entry `i`'s first data byte, or -1 when out of
/// range.
/// Complexity: O(1).
pub fn png_text_offset(img: &PngImage, i: Int) -> Int {
  if (i < 0 || i >= img.text_offset.len()) { return -1; }
  let v: Int = img.text_offset[i];
  return v;
}

/// Declared data length of text entry `i`, or -1 when out of range.
/// Complexity: O(1).
pub fn png_text_length(img: &PngImage, i: Int) -> Int {
  if (i < 0 || i >= img.text_length.len()) { return -1; }
  let v: Int = img.text_length[i];
  return v;
}
