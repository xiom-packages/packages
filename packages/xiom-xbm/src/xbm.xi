// XIOM -- xiom.xbm: X BitMap (XBM) parsing and building for X11 1-bit rasters
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure XIOM, no FFI. XBM is the C-source 1-bit bitmap format used by X11:
//
//   #define sample_width 16
//   #define sample_height 16
//   static char sample_bits[] = {
//      0x00, 0x01, 0x02, ... };
//
// This module parses that subset -- the two dimension defines and one
// char / unsigned char array -- extracts the packed raster into a flat
// Vec[UInt8], exposes width/height/name/byte-span accessors plus an (x, y)
// bit lookup, and rebuilds canonical XBM text. Within a raster byte bit 0 is
// the leftmost pixel (LSB first, per X11) and 1 means foreground. C comments
// ('/* ... */') and any whitespace may separate tokens. See SPEC.md for the
// exact grammar, the canonical build layout, the error catalog and the test
// matrix.

module xiom.xbm

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;

// Parsed XBM image: dimensions, shared base name and the packed raster.
// `bits` holds exactly xbm_row_bytes(width) * height bytes; pixel (x, y) is
// bit (x % 8) of byte y * xbm_row_bytes(width) + x / 8, where 1 is
// foreground. Parsed images always have width/height in 1..1000000.
pub type XbmImage = {
  width: Int;        // 1..1000000
  height: Int;       // 1..1000000
  name: Str;         // shared base name of the two defines and the array
  bits: Vec[UInt8];  // packed raster, LSB-first within each byte
}

// ---------------------------------------------------------------------------
// Result leaf helpers (v0.61.3: Ok/Err construction is confined to fns that
// return a Result directly, so fallible public fns return through these).
// ---------------------------------------------------------------------------

// Ok(v) for Result[XbmImage, Str].
fn _ok_img(v: XbmImage) -> Result[XbmImage, Str] { return Ok(v); }

// Err(m) for Result[XbmImage, Str].
fn _err_img(m: Str) -> Result[XbmImage, Str] { return Err(m); }

// Ok(v) for Result[Vec[UInt8], Str].
fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], Str] { return Ok(v); }

// Err(m) for Result[Vec[UInt8], Str].
fn _err_bytes(m: Str) -> Result[Vec[UInt8], Str] { return Err(m); }

// ---------------------------------------------------------------------------
// Byte predicates and scanners
// ---------------------------------------------------------------------------

// Unsigned byte at index i (widening masked to 0..255).
fn _b(data: &Vec[UInt8], i: Int) -> Int {
  return (data[i] as Int) & 0xFF;
}

// C whitespace: SPACE, TAB, LF, CR, VT, FF.
fn _is_space(b: Int) -> Bool {
  if (b == 32) { return true; }
  if (b == 9) { return true; }
  if (b == 10) { return true; }
  if (b == 13) { return true; }
  if (b == 11) { return true; }
  if (b == 12) { return true; }
  return false;
}

// ASCII '0'..'9'.
fn _is_digit(b: Int) -> Bool {
  if (b < 48) { return false; }
  if (b > 57) { return false; }
  return true;
}

// C identifier start: A-Z, a-z, '_'.
fn _is_ident_start(b: Int) -> Bool {
  if (b >= 65 && b <= 90) { return true; }
  if (b >= 97 && b <= 122) { return true; }
  if (b == 95) { return true; }
  return false;
}

// C identifier continuation: identifier start or ASCII digit.
fn _is_ident_char(b: Int) -> Bool {
  if (_is_ident_start(b)) { return true; }
  if (_is_digit(b)) { return true; }
  return false;
}

// Hex digit value 0..15, or -1 when `b` is not [0-9A-Fa-f].
fn _hex_val(b: Int) -> Int {
  if (b >= 48 && b <= 57) { return b - 48; }
  if (b >= 97 && b <= 102) { return b - 87; }
  if (b >= 65 && b <= 70) { return b - 55; }
  return -1;
}

// Length of the decimal digit run starting at `start` (0 when not a digit).
fn _dec_len(data: &Vec[UInt8], n: Int, start: Int) -> Int {
  var i = start;
  while (i < n) {
    let c = _b(data, i);
    if (!_is_digit(c)) { break; }
    i = i + 1;
  }
  return i - start;
}

// Decimal value of data[start, start+len), a non-empty digit run.
fn _dec_value(data: &Vec[UInt8], start: Int, len: Int) -> Int {
  var v = 0;
  var i = 0;
  while (i < len) {
    let c = _b(data, start + i);
    v = v * 10 + (c - 48);
    i = i + 1;
  }
  return v;
}

// Bit `shift` (0 = least significant) of a 0..255 byte value.
fn _bit_value(b: Int, shift: Int) -> Int {
  var v = b;
  var i = 0;
  while (i < shift) {
    v = v / 2;
    i = i + 1;
  }
  return v % 2;
}

// 2^k for 0 <= k <= 7 (LSB-first packing helper).
fn _pow2(k: Int) -> Int {
  var v = 1;
  var i = 0;
  while (i < k) {
    v = v * 2;
    i = i + 1;
  }
  return v;
}

// True when every '/*' in data[0, n) has a matching '*/'. Stray '*' or '/'
// outside a comment is not inspected here: it fails later as a token.
fn _comments_balanced(data: &Vec[UInt8], n: Int) -> Bool {
  var i = 0;
  var ok: Bool = true;
  while (i + 1 < n) {
    if (_b(data, i) == 47 && _b(data, i + 1) == 42) {
      i = i + 2;
      var closed: Bool = false;
      while (i + 1 < n) {
        if (_b(data, i) == 42 && _b(data, i + 1) == 47) {
          i = i + 2;
          closed = true;
          break;
        }
        i = i + 1;
      }
      if (!closed) { ok = false; break; }
    } else {
      i = i + 1;
    }
  }
  return ok;
}

// Index of the next byte that is neither C whitespace nor inside a comment.
// Comments are pre-validated as balanced, so an unclosed one cannot appear.
fn _skip_trivia(data: &Vec[UInt8], n: Int, start: Int) -> Int {
  var i = start;
  var go: Bool = true;
  while (go) {
    if (i >= n) {
      go = false;
    } else {
      let c = _b(data, i);
      if (c == 47 && i + 1 < n && _b(data, i + 1) == 42) {
        i = i + 2;
        var closed: Bool = false;
        while (i + 1 < n) {
          if (_b(data, i) == 42 && _b(data, i + 1) == 47) {
            i = i + 2;
            closed = true;
            break;
          }
          i = i + 1;
        }
        if (!closed) { i = n; }
      } else {
        if (_is_space(c)) { i = i + 1; } else { go = false; }
      }
    }
  }
  return i;
}

// True when keyword `s` matches data at `start` and ends on a word boundary
// (the following byte is not an identifier character). Used for `define`,
// `static`, `unsigned` and `char`, so `#definefoo` is rejected.
fn _match_kw(data: &Vec[UInt8], n: Int, start: Int, s: Str) -> Bool {
  let sl = s.len();
  if (start + sl > n) { return false; }
  var i = 0;
  while (i < sl) {
    let a = _b(data, start + i);
    let b: UInt8 = string.byte_at(s, i);
    if (a != ((b as Int) & 0xFF)) { return false; }
    i = i + 1;
  }
  if (start + sl < n) {
    if (_is_ident_char(_b(data, start + sl))) { return false; }
  }
  return true;
}

// End index of the C identifier at `start`, or `start` when none begins there.
fn _ident_end(data: &Vec[UInt8], n: Int, start: Int) -> Int {
  if (start >= n) { return start; }
  if (!_is_ident_start(_b(data, start))) { return start; }
  var i = start + 1;
  while (i < n) {
    if (!_is_ident_char(_b(data, i))) { break; }
    i = i + 1;
  }
  return i;
}

// True when data[start, end) ends with `suf` and has at least one byte before
// it (so a bare `_width` is not a valid name suffix).
fn _has_suffix(data: &Vec[UInt8], start: Int, end: Int, suf: Str) -> Bool {
  let sl = suf.len();
  if (end - start <= sl) { return false; }
  var i = 0;
  while (i < sl) {
    let a = _b(data, start + (end - start - sl) + i);
    let b: UInt8 = string.byte_at(suf, i);
    if (a != ((b as Int) & 0xFF)) { return false; }
    i = i + 1;
  }
  return true;
}

// Copy data[start, start+len) into a fresh Str. Callers pass only ranges that
// were already validated as C identifiers, so no NUL byte can appear.
fn _range_str(data: &Vec[UInt8], start: Int, len: Int) -> Str {
  let sb = Vec[UInt8].new();
  var i = 0;
  while (i < len) {
    let b: UInt8 = data[start + i];
    sb.push(b);
    i = i + 1;
  }
  return builder.sb_to_str(&sb);
}

// True when `name` is a non-empty C identifier: [A-Za-z_][A-Za-z0-9_]*.
fn _name_ok(name: Str) -> Bool {
  let n = name.len();
  if (n <= 0) { return false; }
  let b0: UInt8 = string.byte_at(name, 0);
  if (!_is_ident_start((b0 as Int) & 0xFF)) { return false; }
  var i = 1;
  while (i < n) {
    let b: UInt8 = string.byte_at(name, i);
    if (!_is_ident_char((b as Int) & 0xFF)) { return false; }
    i = i + 1;
  }
  return true;
}

// ---------------------------------------------------------------------------
// Writers (canonical builder)
// ---------------------------------------------------------------------------

// Append `s` verbatim to `out`.
fn _put_str(out: &mut Vec[UInt8], s: Str) {
  let n = s.len();
  var i = 0;
  while (i < n) {
    let b: UInt8 = string.byte_at(s, i);
    out.push(b);
    i = i + 1;
  }
}

// Append the ASCII decimal spelling of v (v >= 0) to out.
fn _put_uint(out: &mut Vec[UInt8], v: Int) {
  if (v == 0) {
    out.push(48 as UInt8);
    return;
  }
  let tmp = Vec[UInt8].new();
  var n = v;
  while (n > 0) {
    let d: Int = n % 10;
    tmp.push((48 + d) as UInt8);
    n = n / 10;
  }
  var i = tmp.len() - 1;
  while (i >= 0) {
    let b: UInt8 = tmp[i];
    out.push(b);
    i = i - 1;
  }
}

// ASCII byte of hex digit d (0..15): '0'..'9' then 'a'..'f'.
fn _hex_digit(d: Int) -> Int {
  if (d < 10) { return 48 + d; }
  return 87 + d;
}

// Append the canonical lowercase two-digit form 0x%02x of v (0..255).
fn _put_hex_byte(out: &mut Vec[UInt8], v: Int) {
  out.push(48 as UInt8);
  out.push(120 as UInt8);
  out.push(_hex_digit((v / 16) % 16) as UInt8);
  out.push(_hex_digit(v % 16) as UInt8);
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

// Row stride of a width-`width` XBM raster in bytes: (width + 7) / 8, and 0
// for width <= 0. Every row is padded independently to whole bytes; the
// unused high bits of a row's final byte are padding.
pub fn xbm_row_bytes(width: Int) -> Int {
  if (width <= 0) { return 0; }
  return (width + 7) / 8;
}

// Raster width in pixels of a parsed image (always 1..1000000).
pub fn xbm_width(img: &XbmImage) -> Int {
  return img.width;
}

// Raster height in pixels of a parsed image (always 1..1000000).
pub fn xbm_height(img: &XbmImage) -> Int {
  return img.height;
}

// Shared base name: the `<name>` of `<name>_width`, `<name>_height` and
// `<name>_bits`.
pub fn xbm_name(img: &XbmImage) -> Str {
  return img.name;
}

// Packed raster size in bytes: xbm_row_bytes(width) * height, i.e.
// img.bits.len() for a parsed or built image.
pub fn xbm_byte_span(img: &XbmImage) -> Int {
  return img.bits.len();
}

// Raster bit at (x, y) with a top-left origin: 1 = foreground, 0 =
// background. Returns the documented sentinel -1 when (x, y) is outside the
// image or when the image struct is internally inconsistent; callers that
// need to tell "malformed input" from "out of range" call xbm_parse first.
pub fn xbm_bit(img: &XbmImage, x: Int, y: Int) -> Int {
  if (img.width <= 0) { return -1; }
  if (img.height <= 0) { return -1; }
  if (x < 0) { return -1; }
  if (y < 0) { return -1; }
  if (x >= img.width) { return -1; }
  if (y >= img.height) { return -1; }
  let idx = y * xbm_row_bytes(img.width) + x / 8;
  if (idx >= img.bits.len()) { return -1; }
  let b: UInt8 = img.bits[idx];
  return _bit_value((b as Int) & 0xFF, x % 8);
}

// Parse an XBM text into an XbmImage. Accepts the two dimension defines
// (`<name>_width`, `<name>_height`, either order, each a positive decimal of
// at most 9 digits) followed by the array
// `static [unsigned] char <name>_bits[] = { 0x.., ... };` as the final
// construct. Whitespace and C comments may separate every token; hex bytes
// accept upper/lower case, an upper/lower `x`, and one or two hex digits; a
// trailing comma before `}` is allowed. The three names must agree and the
// byte count must equal xbm_row_bytes(width) * height. Errors are the
// deterministic `xbm: ...` strings catalogued in SPEC.md.
pub fn xbm_parse(data: &Vec[UInt8]) -> Result[XbmImage, Str] {
  let n = data.len();
  if (!_comments_balanced(data, n)) { return _err_img("xbm: unclosed comment"); }
  var pos = 0;
  var have_width = false;
  var have_height = false;
  var width = 0;
  var height = 0;
  var name_width = "";
  var name_height = "";
  var have_array = false;
  var name_bits = "";
  let bytes = Vec[UInt8].new();
  var go: Bool = true;
  while (go) {
    pos = _skip_trivia(data, n, pos);
    if (pos >= n) { break; }
    let c = _b(data, pos);
    if (c == 35) {
      // '#define <name>_width|_height <decimal>'
      pos = pos + 1;
      pos = _skip_trivia(data, n, pos);
      if (!_match_kw(data, n, pos, "define")) { return _err_img("xbm: malformed define"); }
      pos = pos + 6;
      pos = _skip_trivia(data, n, pos);
      let istart = pos;
      let iend = _ident_end(data, n, istart);
      if (iend == istart) { return _err_img("xbm: malformed define"); }
      var is_width = false;
      var is_height = false;
      if (_has_suffix(data, istart, iend, "_width")) {
        is_width = true;
      } else {
        if (_has_suffix(data, istart, iend, "_height")) { is_height = true; }
      }
      if (!is_width && !is_height) { return _err_img("xbm: malformed define"); }
      var base_len = iend - istart - 6;
      if (is_height) { base_len = iend - istart - 7; }
      if (base_len <= 0) { return _err_img("xbm: malformed define"); }
      let nm = _range_str(data, istart, base_len);
      pos = _skip_trivia(data, n, iend);
      let dlen = _dec_len(data, n, pos);
      if (dlen == 0) { return _err_img("xbm: malformed define"); }
      if (dlen > 9) {
        if (is_width) { return _err_img("xbm: invalid width"); }
        return _err_img("xbm: invalid height");
      }
      let value = _dec_value(data, pos, dlen);
      pos = pos + dlen;
      if (is_width) {
        if (have_width) { return _err_img("xbm: duplicate width define"); }
        if (value <= 0) { return _err_img("xbm: invalid width"); }
        if (value > 1000000) { return _err_img("xbm: invalid width"); }
        have_width = true;
        width = value;
        name_width = nm;
      } else {
        if (have_height) { return _err_img("xbm: duplicate height define"); }
        if (value <= 0) { return _err_img("xbm: invalid height"); }
        if (value > 1000000) { return _err_img("xbm: invalid height"); }
        have_height = true;
        height = value;
        name_height = nm;
      }
    } else {
      // 'static [unsigned] char <name>_bits[] = { ... };'
      if (!_match_kw(data, n, pos, "static")) { return _err_img("xbm: malformed array declaration"); }
      pos = pos + 6;
      pos = _skip_trivia(data, n, pos);
      if (_match_kw(data, n, pos, "unsigned")) {
        pos = pos + 8;
        pos = _skip_trivia(data, n, pos);
      }
      if (!_match_kw(data, n, pos, "char")) { return _err_img("xbm: malformed array declaration"); }
      pos = pos + 4;
      pos = _skip_trivia(data, n, pos);
      let astart = pos;
      let aend = _ident_end(data, n, astart);
      if (aend == astart) { return _err_img("xbm: malformed array declaration"); }
      if (!_has_suffix(data, astart, aend, "_bits")) { return _err_img("xbm: malformed array declaration"); }
      let base_len = aend - astart - 5;
      if (base_len <= 0) { return _err_img("xbm: malformed array declaration"); }
      name_bits = _range_str(data, astart, base_len);
      pos = _skip_trivia(data, n, aend);
      if (pos >= n) { return _err_img("xbm: malformed array declaration"); }
      if (_b(data, pos) != 91) { return _err_img("xbm: malformed array declaration"); }   // '['
      pos = pos + 1;
      pos = _skip_trivia(data, n, pos);
      if (pos >= n) { return _err_img("xbm: malformed array declaration"); }
      if (_b(data, pos) != 93) { return _err_img("xbm: malformed array declaration"); }   // ']'
      pos = pos + 1;
      pos = _skip_trivia(data, n, pos);
      if (pos >= n) { return _err_img("xbm: malformed array declaration"); }
      if (_b(data, pos) != 61) { return _err_img("xbm: malformed array declaration"); }   // '='
      pos = pos + 1;
      pos = _skip_trivia(data, n, pos);
      if (pos >= n) { return _err_img("xbm: malformed array declaration"); }
      if (_b(data, pos) != 123) { return _err_img("xbm: malformed array declaration"); }  // '{'
      pos = pos + 1;
      var body_go: Bool = true;
      while (body_go) {
        pos = _skip_trivia(data, n, pos);
        if (pos >= n) { return _err_img("xbm: malformed byte list"); }
        let bc = _b(data, pos);
        if (bc == 125) { break; }                                                        // '}'
        if (bytes.len() > 0) {
          if (bc != 44) { return _err_img("xbm: malformed byte list"); }                  // ','
          pos = pos + 1;
          pos = _skip_trivia(data, n, pos);
          if (pos >= n) { return _err_img("xbm: malformed byte list"); }
          if (_b(data, pos) == 125) { break; }
        }
        if (_b(data, pos) != 48) { return _err_img("xbm: non-hex byte"); }                // '0'
        if (pos + 1 >= n) { return _err_img("xbm: non-hex byte"); }
        let xc = _b(data, pos + 1);
        if (xc != 120 && xc != 88) { return _err_img("xbm: non-hex byte"); }              // 'x'/'X'
        var k = pos + 2;
        var val = 0;
        var digits = 0;
        var hex_go: Bool = true;
        while (hex_go) {
          if (k >= n) {
            hex_go = false;
          } else {
            let hv = _hex_val(_b(data, k));
            if (hv < 0) {
              hex_go = false;
            } else {
              if (digits >= 2) { return _err_img("xbm: non-hex byte"); }
              val = val * 16 + hv;
              digits = digits + 1;
              k = k + 1;
            }
          }
        }
        if (digits == 0) { return _err_img("xbm: non-hex byte"); }
        if (k < n) {
          if (_is_ident_char(_b(data, k))) { return _err_img("xbm: non-hex byte"); }
        }
        bytes.push(val as UInt8);
        pos = k;
      }
      pos = pos + 1;
      pos = _skip_trivia(data, n, pos);
      if (pos >= n) { return _err_img("xbm: malformed array declaration"); }
      if (_b(data, pos) != 59) { return _err_img("xbm: malformed array declaration"); }   // ';'
      pos = pos + 1;
      have_array = true;
      let rest = _skip_trivia(data, n, pos);
      if (rest < n) { return _err_img("xbm: trailing tokens"); }
      pos = rest;
      break;
    }
  }
  if (!have_width) { return _err_img("xbm: missing width define"); }
  if (!have_height) { return _err_img("xbm: missing height define"); }
  if (!have_array) { return _err_img("xbm: missing array"); }
  if (compare.str_compare(name_width, name_height) != 0) { return _err_img("xbm: name mismatch"); }
  if (compare.str_compare(name_width, name_bits) != 0) { return _err_img("xbm: name mismatch"); }
  let expected = xbm_row_bytes(width) * height;
  if (bytes.len() != expected) { return _err_img("xbm: byte count mismatch"); }
  let img = XbmImage{ width: width; height: height; name: name_width; bits: bytes; };
  return _ok_img(img);
}

// Pack a row-major width * height pixel buffer of 0/1 bytes into canonical
// XBM raster bytes: for every row, bit `x % 8` of byte `y * row_bytes + x / 8`
// is the pixel (x, y), LSB first; unused high bits of a row's final byte are
// zero. A wrong pixel count is `xbm: pixel buffer size mismatch`; any value
// above 1 is `xbm: non-binary pixel`.
pub fn xbm_pack(pixels: &Vec[UInt8], width: Int, height: Int) -> Result[Vec[UInt8], Str] {
  if (width <= 0) { return _err_bytes("xbm: invalid width"); }
  if (width > 1000000) { return _err_bytes("xbm: invalid width"); }
  if (height <= 0) { return _err_bytes("xbm: invalid height"); }
  if (height > 1000000) { return _err_bytes("xbm: invalid height"); }
  if (pixels.len() != width * height) { return _err_bytes("xbm: pixel buffer size mismatch"); }
  let out = Vec[UInt8].new();
  let stride = xbm_row_bytes(width);
  var y = 0;
  while (y < height) {
    var xb = 0;
    while (xb < stride) {
      var v = 0;
      var k = 0;
      while (k < 8) {
        let x = xb * 8 + k;
        if (x < width) {
          let p: UInt8 = pixels[y * width + x];
          let pv: Int = (p as Int) & 0xFF;
          if (pv > 1) { return _err_bytes("xbm: non-binary pixel"); }
          if (pv == 1) { v = v + _pow2(k); }
        }
        k = k + 1;
      }
      out.push(v as UInt8);
      xb = xb + 1;
    }
    y = y + 1;
  }
  return _ok_bytes(out);
}

// Build canonical XBM text from a base name and packed raster bytes:
//
//   #define <name>_width <width>\n
//   #define <name>_height <height>\n
//   static char <name>_bits[] = {\n
//      0x00, 0x01, ...\n
//   };\n
//
// Exactly 12 bytes per line, three-space indent, lowercase `0x%02x` bytes
// separated by `, `; when a line break falls between two bytes the comma is
// kept at the end of the earlier line, and the final byte has no comma. `name`
// must be a C identifier and `bits` must contain xbm_row_bytes(width) * height
// bytes; errors are `xbm: invalid name`, `xbm: invalid width`,
// `xbm: invalid height` and `xbm: byte count mismatch`.
pub fn xbm_build(name: Str, bits: &Vec<UInt8>, width: Int, height: Int) -> Result[Vec[UInt8], Str] {
  if (width <= 0) { return _err_bytes("xbm: invalid width"); }
  if (width > 1000000) { return _err_bytes("xbm: invalid width"); }
  if (height <= 0) { return _err_bytes("xbm: invalid height"); }
  if (height > 1000000) { return _err_bytes("xbm: invalid height"); }
  if (!_name_ok(name)) { return _err_bytes("xbm: invalid name"); }
  let expected = xbm_row_bytes(width) * height;
  if (bits.len() != expected) { return _err_bytes("xbm: byte count mismatch"); }
  let out = Vec[UInt8].new();
  _put_str(&mut out, "#define ");
  _put_str(&mut out, name);
  _put_str(&mut out, "_width ");
  _put_uint(&mut out, width);
  out.push(10 as UInt8);
  _put_str(&mut out, "#define ");
  _put_str(&mut out, name);
  _put_str(&mut out, "_height ");
  _put_uint(&mut out, height);
  out.push(10 as UInt8);
  _put_str(&mut out, "static char ");
  _put_str(&mut out, name);
  _put_str(&mut out, "_bits[] = {\n");
  var i = 0;
  while (i < expected) {
    if (i % 12 == 0) { _put_str(&mut out, "   "); }
    let b: UInt8 = bits[i];
    _put_hex_byte(&mut out, (b as Int) & 0xFF);
    if (i + 1 < expected) {
      if ((i + 1) % 12 == 0) {
        out.push(44 as UInt8);
        out.push(10 as UInt8);
      } else {
        _put_str(&mut out, ", ");
      }
    }
    i = i + 1;
  }
  out.push(10 as UInt8);
  _put_str(&mut out, "};\n");
  return _ok_bytes(out);
}
