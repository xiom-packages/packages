// XIOM -- xiom.pbm: Netpbm PBM (P1 ASCII / P4 binary) parsing and building
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure XIOM, no FFI. Supports the two bitmap Netpbm variants:
//   P1 -- ASCII raster of '0' (white) and '1' (black) digits separated by
//         arbitrary whitespace;
//   P4 -- binary raster, one bit per pixel, rows padded with zero bits to a
//         whole byte, most significant bit first (x = 0 is the 0x80 bit).
// Header tokens (magic, width, height) are separated by any whitespace; '#'
// starts a comment that runs to the end of the line and acts as a separator
// anywhere in the header. The raster is not a comment context: after the
// height token a P4 raster is raw bytes, and a P1 raster accepts only 0/1
// digits and whitespace. pbm_bit returns the documented sentinel -1 for
// out-of-range coordinates and for buffers that do not parse. See SPEC.md for
// the full grammar, the padding rules and the error catalog.

module xiom.pbm

use xiom.string;

pub type PbmImage = {
  format: Int;      // 1 = ASCII (P1), 4 = binary (P4)
  width: Int;       // 1..1000000
  height: Int;      // 1..1000000
  data_offset: Int; // first raster byte (P4) or first raster digit (P1)
}

// ---------------------------------------------------------------------------
// Result leaf helpers (v0.61.3: Ok/Err may only appear in fns that return a
// Result directly, so every fallible public fn returns through one of these).
// ---------------------------------------------------------------------------

fn _err_img(m: Str) -> Result[PbmImage, Str] { return Err(m); }
fn _ok_img(i: PbmImage) -> Result[PbmImage, Str] { return Ok(i); }
fn _err_bytes(m: Str) -> Result[Vec[UInt8], Str] { return Err(m); }
fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], Str] { return Ok(v); }

// ---------------------------------------------------------------------------
// Byte predicates and scanners
// ---------------------------------------------------------------------------

// Unsigned byte at index i (widening masked to 0..255).
fn _b(data: &Vec[UInt8], i: Int) -> Int {
  return (data[i] as Int) & 0xFF;
}

// Netpbm whitespace: SPACE, TAB, LF, CR, VT, FF.
fn _is_space(b: Int) -> Bool {
  if (b == 32) { return true; }
  if (b == 9) { return true; }
  if (b == 10) { return true; }
  if (b == 13) { return true; }
  if (b == 11) { return true; }
  if (b == 12) { return true; }
  return false;
}

// ASCII '0' or '1': a P1 raster digit.
fn _is_bit(b: Int) -> Bool {
  if (b == 48) { return true; }
  if (b == 49) { return true; }
  return false;
}

// ASCII decimal digit byte.
fn _is_digit(b: Int) -> Bool {
  if (b < 48) { return false; }
  if (b > 57) { return false; }
  return true;
}

// Length of the digit run starting at `start` (0 when the byte is not a digit).
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

// Index just past the comment starting at `start` (past the LF, or n at EOF).
fn _skip_comment(data: &Vec[UInt8], n: Int, start: Int) -> Int {
  var i = start;
  while (i < n) {
    let c = _b(data, i);
    if (c == 10) { return i + 1; }
    i = i + 1;
  }
  return i;
}

// Index of the next header separator byte: skips whitespace and comments.
fn _skip_ws(data: &Vec[UInt8], n: Int, start: Int) -> Int {
  var i = start;
  var go: Bool = true;
  while (go) {
    if (i >= n) {
      go = false;
    } else {
      let c = _b(data, i);
      if (c == 35) {
        i = _skip_comment(data, n, i);
      } else {
        if (_is_space(c)) { i = i + 1; } else { go = false; }
      }
    }
  }
  return i;
}

// Index of the next non-whitespace byte (raster scanning: '#' is data there).
fn _skip_plain_ws(data: &Vec[UInt8], n: Int, start: Int) -> Int {
  var i = start;
  while (i < n) {
    let c = _b(data, i);
    if (!_is_space(c)) { return i; }
    i = i + 1;
  }
  return i;
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

// Value (0/1) of the `index`-th raster digit of an already-validated P1 image.
fn _p1_bit_at(data: &Vec[UInt8], n: Int, offset: Int, index: Int) -> Int {
  var pos = offset;
  var seen = 0;
  while (pos < n) {
    let c = _b(data, pos);
    if (_is_bit(c)) {
      if (seen == index) { return c - 48; }
      seen = seen + 1;
    }
    pos = pos + 1;
  }
  return -1;
}

// Value (0/1) of pixel (x, y) in an already-validated P4 image.
fn _p4_bit_at(data: &Vec[UInt8], offset: Int, row_bytes: Int, x: Int, y: Int) -> Int {
  let pos = offset + y * row_bytes + x / 8;
  let b = _b(data, pos);
  let shift = 7 - (x % 8);
  return _bit_value(b, shift);
}

// ---------------------------------------------------------------------------
// Writers (builders)
// ---------------------------------------------------------------------------

// Append the ASCII decimal spelling of v (v >= 0) to out.
fn _put_decimal(out: &mut Vec[UInt8], v: Int) {
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

// Append the two magic bytes: "P1" when format == 1, "P4" otherwise.
fn _put_magic(out: &mut Vec[UInt8], format: Int) {
  out.push(80 as UInt8);
  if (format == 1) {
    out.push(49 as UInt8);
  } else {
    out.push(52 as UInt8);
  }
}

// True when every byte of `comment` is printable ASCII (32..126) or >= 128.
// LF, CR, NUL and the other control bytes would break the single comment line.
fn _comment_ok(comment: Str) -> Bool {
  let n = comment.len();
  var i = 0;
  while (i < n) {
    let b: UInt8 = string.byte_at(comment, i);
    let v: Int = (b as Int) & 0xFF;
    if (v < 32) { return false; }
    if (v == 127) { return false; }
    i = i + 1;
  }
  return true;
}

// Append the emitted comment line "# <comment>\n" (callers check _comment_ok).
fn _put_comment(out: &mut Vec[UInt8], comment: Str) {
  out.push(35 as UInt8);
  out.push(32 as UInt8);
  let n = comment.len();
  var i = 0;
  while (i < n) {
    let b: UInt8 = string.byte_at(comment, i);
    out.push(b);
    i = i + 1;
  }
  out.push(10 as UInt8);
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

// P4 row stride in bytes: (width + 7) / 8, and 0 for width <= 0. The unused
// low bits of the final byte of every row are zero padding.
pub fn pbm_row_bytes(width: Int) -> Int {
  if (width <= 0) { return 0; }
  return (width + 7) / 8;
}

// Raster width in pixels (always 1..1000000 for a parsed image).
pub fn pbm_width(img: &PbmImage) -> Int {
  return img.width;
}

// Raster height in pixels (always 1..1000000 for a parsed image).
pub fn pbm_height(img: &PbmImage) -> Int {
  return img.height;
}

// Format code: 1 for ASCII (P1), 4 for binary (P4).
pub fn pbm_format(img: &PbmImage) -> Int {
  return img.format;
}

// Parse and validate a P1/P4 header and raster. Returns the header fields
// plus data_offset: the first raster byte (P4) or the first raster digit (P1).
// P4 buffers must contain exactly pbm_row_bytes(width) * height raster bytes,
// optionally followed by whitespace; P1 rasters must contain exactly
// width * height 0/1 digits, separated by optional whitespace.
pub fn pbm_parse_header(data: &Vec[UInt8]) -> Result[PbmImage, Str] {
  let n = data.len();
  if (n < 2) { return _err_img("pbm: truncated header"); }
  let m0 = _b(data, 0);
  if (m0 != 80) { return _err_img("pbm: bad magic"); }
  let m1 = _b(data, 1);
  var format = 0;
  if (m1 == 49) {
    format = 1;
  } else {
    if (m1 == 52) { format = 4; } else { return _err_img("pbm: bad magic"); }
  }
  if (n < 3) { return _err_img("pbm: truncated header"); }
  let sep = _b(data, 2);
  if (!_is_space(sep)) { return _err_img("pbm: missing whitespace after magic"); }
  var pos = _skip_ws(data, n, 2);

  let wlen = _dec_len(data, n, pos);
  if (wlen == 0) { return _err_img("pbm: missing width"); }
  if (wlen > 9) { return _err_img("pbm: invalid width"); }
  let width = _dec_value(data, pos, wlen);
  pos = pos + wlen;
  pos = _skip_ws(data, n, pos);

  let hlen = _dec_len(data, n, pos);
  if (hlen == 0) { return _err_img("pbm: missing height"); }
  if (hlen > 9) { return _err_img("pbm: invalid height"); }
  let height = _dec_value(data, pos, hlen);
  pos = pos + hlen;

  if (width <= 0) { return _err_img("pbm: invalid width"); }
  if (width > 1000000) { return _err_img("pbm: invalid width"); }
  if (height <= 0) { return _err_img("pbm: invalid height"); }
  if (height > 1000000) { return _err_img("pbm: invalid height"); }
  let pixels = width * height;

  if (format == 4) {
    if (pos >= n) { return _err_img("pbm: truncated raster"); }
    let sp = _b(data, pos);
    if (!_is_space(sp)) { return _err_img("pbm: missing whitespace after height"); }
    let offset = pos + 1;
    let need = pbm_row_bytes(width) * height;
    if (offset + need > n) { return _err_img("pbm: truncated raster"); }
    var tail = offset + need;
    while (tail < n) {
      let t = _b(data, tail);
      if (!_is_space(t)) { return _err_img("pbm: extra tokens"); }
      tail = tail + 1;
    }
    let img = PbmImage{ format: format; width: width; height: height; data_offset: offset; };
    return _ok_img(img);
  }

  // P1: skip header separators to the first raster digit, then require
  // exactly width*height 0/1 digits separated by plain whitespace.
  pos = _skip_ws(data, n, pos);
  if (pos >= n) { return _err_img("pbm: truncated raster"); }
  let offset = pos;
  var count = 0;
  var go: Bool = true;
  while (go) {
    pos = _skip_plain_ws(data, n, pos);
    if (pos >= n) {
      go = false;
    } else {
      let c = _b(data, pos);
      if (_is_bit(c)) {
        count = count + 1;
        if (count > pixels) { return _err_img("pbm: extra tokens"); }
      } else {
        return _err_img("pbm: non-binary digit");
      }
      pos = pos + 1;
    }
  }
  if (count < pixels) { return _err_img("pbm: truncated raster"); }
  let img = PbmImage{ format: format; width: width; height: height; data_offset: offset; };
  return _ok_img(img);
}

// Raster bit at (x, y) with a top-left origin: 0 = white, 1 = black.
// Sentinel: returns -1 when (x, y) is outside the image or when `data` does
// not parse as P1/P4; call pbm_parse_header to distinguish the two cases.
pub fn pbm_bit(data: &Vec[UInt8], x: Int, y: Int) -> Int {
  let parsed = pbm_parse_header(data);
  match parsed {
    Ok(img) => {
      if (x < 0) { return -1; }
      if (y < 0) { return -1; }
      if (x >= img.width) { return -1; }
      if (y >= img.height) { return -1; }
      if (img.format == 4) {
        return _p4_bit_at(data, img.data_offset, pbm_row_bytes(img.width), x, y);
      }
      return _p1_bit_at(data, data.len(), img.data_offset, y * img.width + x);
    },
    Err(e) => { return -1; },
  }
}

// Build a canonical ASCII P1 image: "P1\n", an optional "# <comment>\n" line,
// "<w> <h>\n", then one 0/1 digit per pixel, separated by single spaces and
// wrapped to `bits_per_line` digits per LF-terminated line (values < 1 clamp
// to 1), ending with exactly one LF. `comment` must be a single printable
// line; any byte < 32 or 127 is rejected so the header stays well formed.
pub fn pbm_build_p1(bits: &Vec[UInt8], width: Int, height: Int, bits_per_line: Int, comment: Str) -> Result[Vec[UInt8], Str] {
  if (width <= 0) { return _err_bytes("pbm: invalid width"); }
  if (width > 1000000) { return _err_bytes("pbm: invalid width"); }
  if (height <= 0) { return _err_bytes("pbm: invalid height"); }
  if (height > 1000000) { return _err_bytes("pbm: invalid height"); }
  let need = width * height;
  if (bits.len() != need) { return _err_bytes("pbm: bit buffer size mismatch"); }
  if (!_comment_ok(comment)) { return _err_bytes("pbm: invalid comment"); }
  var per_line = bits_per_line;
  if (per_line < 1) { per_line = 1; }
  let out = Vec[UInt8].new();
  _put_magic(&mut out, 1);
  out.push(10 as UInt8);
  if (comment.len() > 0) { _put_comment(&mut out, comment); }
  _put_decimal(&mut out, width);
  out.push(32 as UInt8);
  _put_decimal(&mut out, height);
  out.push(10 as UInt8);
  var idx = 0;
  var col = 0;
  while (idx < need) {
    let b: UInt8 = bits[idx];
    let v: Int = (b as Int) & 0xFF;
    if (v > 1) { return _err_bytes("pbm: non-binary bit"); }
    if (col > 0) { out.push(32 as UInt8); }
    out.push((48 + v) as UInt8);
    col = col + 1;
    if (col == per_line) {
      out.push(10 as UInt8);
      col = 0;
    }
    idx = idx + 1;
  }
  if (col > 0) { out.push(10 as UInt8); }
  return _ok_bytes(out);
}

// Build a canonical binary P4 image: "P4\n", an optional "# <comment>\n" line,
// "<w> <h>\n", then width*height bits in top-left scan order packed most
// significant bit first. Every row occupies pbm_row_bytes(width) whole bytes;
// the unused low bits of the last byte of a row are written as zero. The
// comment rules match pbm_build_p1.
pub fn pbm_build_p4(bits: &Vec[UInt8], width: Int, height: Int, comment: Str) -> Result[Vec[UInt8], Str] {
  if (width <= 0) { return _err_bytes("pbm: invalid width"); }
  if (width > 1000000) { return _err_bytes("pbm: invalid width"); }
  if (height <= 0) { return _err_bytes("pbm: invalid height"); }
  if (height > 1000000) { return _err_bytes("pbm: invalid height"); }
  let need = width * height;
  if (bits.len() != need) { return _err_bytes("pbm: bit buffer size mismatch"); }
  if (!_comment_ok(comment)) { return _err_bytes("pbm: invalid comment"); }
  let out = Vec[UInt8].new();
  _put_magic(&mut out, 4);
  out.push(10 as UInt8);
  if (comment.len() > 0) { _put_comment(&mut out, comment); }
  _put_decimal(&mut out, width);
  out.push(32 as UInt8);
  _put_decimal(&mut out, height);
  out.push(10 as UInt8);
  var y = 0;
  while (y < height) {
    var cur = 0;
    var used = 0;
    var x = 0;
    while (x < width) {
      let b: UInt8 = bits[y * width + x];
      let v: Int = (b as Int) & 0xFF;
      if (v > 1) { return _err_bytes("pbm: non-binary bit"); }
      cur = cur * 2 + v;
      used = used + 1;
      if (used == 8) {
        out.push(cur as UInt8);
        cur = 0;
        used = 0;
      }
      x = x + 1;
    }
    if (used > 0) {
      while (used < 8) {
        cur = cur * 2;
        used = used + 1;
      }
      out.push(cur as UInt8);
    }
    y = y + 1;
  }
  return _ok_bytes(out);
}
