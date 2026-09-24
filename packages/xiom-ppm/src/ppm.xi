// XIOM -- xiom.ppm: Netpbm PPM (P3/P6) parsing and building for 8-bit RGB rasters
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure XIOM, no FFI. Supports the two RGB Netpbm variants:
//   P3 -- ASCII raster, decimal samples after the header;
//   P6 -- binary raster, raw samples immediately after the single whitespace
//         byte that terminates maxval.
// Header tokens (magic, width, height, maxval) are separated by any
// whitespace; '#' starts a comment that runs to the end of the line and acts
// as a separator. Pixel access handles 8-bit P6 only (maxval <= 255); the
// header parser accepts 16-bit maxval (2 bytes per sample) and
// ppm_pixel_rgb rejects it. See SPEC.md for the full grammar and error
// catalog.

module xiom.ppm

pub type PpmImage = {
  format: Int;      // 3 = ASCII (P3), 6 = binary (P6)
  width: Int;
  height: Int;
  maxval: Int;      // 1..65535 (the PPM format allows up to 65535)
  data_offset: Int; // first pixel byte (P6) or first sample token (P3)
}

// ---------------------------------------------------------------------------
// Result leaf helpers (v0.61.3: Ok/Err may only appear in fns that return a
// Result directly, so every fallible public fn returns through one of these).
// ---------------------------------------------------------------------------

fn _err_img(m: Str) -> Result[PpmImage, Str] { return Err(m); }
fn _ok_img(i: PpmImage) -> Result[PpmImage, Str] { return Ok(i); }
fn _err_int(m: Str) -> Result[Int, Str] { return Err(m); }
fn _ok_int(v: Int) -> Result[Int, Str] { return Ok(v); }
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

// True for an ASCII decimal digit byte.
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

// Index of the next byte that is neither whitespace nor inside a comment.
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

// Append the two magic bytes for format 3 (P3) or anything else (P6).
fn _put_magic(out: &mut Vec[UInt8], format: Int) {
  out.push(80 as UInt8);
  if (format == 3) {
    out.push(51 as UInt8);
  } else {
    out.push(54 as UInt8);
  }
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

// Parse and validate a P3/P6 header. Returns the header fields plus
// data_offset: the first pixel byte (P6) or the first sample token (P3).
// For P6 the raster must fit in `data` (16-bit samples need 2 bytes each);
// for P3 every remaining token is validated and at least width*height*3
// sample tokens must be present (trailing extra tokens are ignored).
pub fn ppm_parse_header(data: &Vec[UInt8]) -> Result[PpmImage, Str] {
  let n = data.len();
  if (n < 2) { return _err_img("ppm: truncated header"); }
  let m0 = _b(data, 0);
  if (m0 != 80) { return _err_img("ppm: bad magic"); }
  let m1 = _b(data, 1);
  var format = 0;
  if (m1 == 51) {
    format = 3;
  } else {
    if (m1 == 54) { format = 6; } else { return _err_img("ppm: bad magic"); }
  }
  if (n < 3) { return _err_img("ppm: truncated header"); }
  let sep = _b(data, 2);
  if (!_is_space(sep)) { return _err_img("ppm: missing whitespace after magic"); }
  var pos = _skip_ws(data, n, 2);

  let wlen = _dec_len(data, n, pos);
  if (wlen == 0) { return _err_img("ppm: missing width"); }
  if (wlen > 9) { return _err_img("ppm: invalid width"); }
  let width = _dec_value(data, pos, wlen);
  pos = pos + wlen;
  pos = _skip_ws(data, n, pos);

  let hlen = _dec_len(data, n, pos);
  if (hlen == 0) { return _err_img("ppm: missing height"); }
  if (hlen > 9) { return _err_img("ppm: invalid height"); }
  let height = _dec_value(data, pos, hlen);
  pos = pos + hlen;
  pos = _skip_ws(data, n, pos);

  let mlen = _dec_len(data, n, pos);
  if (mlen == 0) { return _err_img("ppm: missing maxval"); }
  if (mlen > 5) { return _err_img("ppm: invalid maxval"); }
  let maxval = _dec_value(data, pos, mlen);
  pos = pos + mlen;

  if (width <= 0) { return _err_img("ppm: invalid width"); }
  if (width > 1000000) { return _err_img("ppm: invalid width"); }
  if (height <= 0) { return _err_img("ppm: invalid height"); }
  if (height > 1000000) { return _err_img("ppm: invalid height"); }
  if (maxval <= 0) { return _err_img("ppm: invalid maxval"); }
  if (maxval > 65535) { return _err_img("ppm: invalid maxval"); }

  let samples = width * height * 3;

  if (format == 6) {
    if (pos >= n) { return _err_img("ppm: truncated pixel data"); }
    let sp = _b(data, pos);
    if (!_is_space(sp)) { return _err_img("ppm: missing whitespace after maxval"); }
    let offset = pos + 1;
    var bytes_per_sample = 1;
    if (maxval > 255) { bytes_per_sample = 2; }
    let need = samples * bytes_per_sample;
    if (offset + need > n) { return _err_img("ppm: truncated pixel data"); }
    let img = PpmImage{
      format: format;
      width: width;
      height: height;
      maxval: maxval;
      data_offset: offset;
    };
    return _ok_img(img);
  }

  // P3: skip whitespace/comments to the first sample token, then validate
  // that every remaining token is decimal and that at least samples exist.
  pos = _skip_ws(data, n, pos);
  if (pos >= n) { return _err_img("ppm: truncated pixel data"); }
  let offset = pos;
  var count = 0;
  while (pos < n) {
    pos = _skip_ws(data, n, pos);
    if (pos >= n) { break; }
    let len = _dec_len(data, n, pos);
    if (len == 0) { return _err_img("ppm: malformed sample"); }
    count = count + 1;
    pos = pos + len;
  }
  if (count < samples) { return _err_img("ppm: truncated pixel data"); }
  let img = PpmImage{
    format: format;
    width: width;
    height: height;
    maxval: maxval;
    data_offset: offset;
  };
  return _ok_img(img);
}

// Read one pixel from a P6 image with maxval <= 255 as 0xRRGGBB using a
// top-left origin. P3 rasters and 16-bit P6 rasters are rejected.
pub fn ppm_pixel_rgb(data: &Vec[UInt8], x: Int, y: Int) -> Result[Int, Str] {
  let parsed = ppm_parse_header(data);
  match parsed {
    Ok(img) => {
      if (img.format != 6) { return _err_int("ppm: pixel accessor requires P6"); }
      if (img.maxval > 255) { return _err_int("ppm: 16-bit samples unsupported"); }
      if (x < 0) { return _err_int("ppm: pixel out of range"); }
      if (y < 0) { return _err_int("ppm: pixel out of range"); }
      if (x >= img.width) { return _err_int("ppm: pixel out of range"); }
      if (y >= img.height) { return _err_int("ppm: pixel out of range"); }
      let pos = img.data_offset + (y * img.width + x) * 3;
      let r = _b(data, pos);
      let g = _b(data, pos + 1);
      let b = _b(data, pos + 2);
      return _ok_int(r * 65536 + g * 256 + b);
    },
    Err(e) => { return _err_int(e); },
  }
}

// Build a canonical binary P6 image: header "P6\n<w> <h>\n255\n" followed by
// raw RGB bytes in top-left scan order (no padding anywhere).
pub fn ppm_build_p6(rgb: &Vec[UInt8], width: Int, height: Int) -> Result[Vec[UInt8], Str] {
  if (width <= 0) { return _err_bytes("ppm: invalid width"); }
  if (height <= 0) { return _err_bytes("ppm: invalid height"); }
  let need = width * height * 3;
  if (rgb.len() != need) { return _err_bytes("ppm: pixel buffer size mismatch"); }
  let out = Vec[UInt8].new();
  _put_magic(&mut out, 6);
  out.push(10 as UInt8);
  _put_decimal(&mut out, width);
  out.push(32 as UInt8);
  _put_decimal(&mut out, height);
  out.push(10 as UInt8);
  _put_decimal(&mut out, 255);
  out.push(10 as UInt8);
  var i = 0;
  while (i < need) {
    let b: UInt8 = rgb[i];
    out.push(b);
    i = i + 1;
  }
  return _ok_bytes(out);
}

// Build an ASCII P3 image: canonical header "P3\n<w> <h>\n255\n", then
// decimal samples separated by single spaces and wrapped to at most
// `samples_per_line` samples per line (values < 1 are clamped to 1). Lines
// are LF-terminated, with exactly one trailing LF at the end of the raster.
pub fn ppm_build_p3(rgb: &Vec[UInt8], width: Int, height: Int, samples_per_line: Int) -> Result[Vec[UInt8], Str] {
  if (width <= 0) { return _err_bytes("ppm: invalid width"); }
  if (height <= 0) { return _err_bytes("ppm: invalid height"); }
  let need = width * height * 3;
  if (rgb.len() != need) { return _err_bytes("ppm: pixel buffer size mismatch"); }
  var per_line = samples_per_line;
  if (per_line < 1) { per_line = 1; }
  let out = Vec[UInt8].new();
  _put_magic(&mut out, 3);
  out.push(10 as UInt8);
  _put_decimal(&mut out, width);
  out.push(32 as UInt8);
  _put_decimal(&mut out, height);
  out.push(10 as UInt8);
  _put_decimal(&mut out, 255);
  out.push(10 as UInt8);
  var idx = 0;
  var col = 0;
  while (idx < need) {
    if (col > 0) { out.push(32 as UInt8); }
    let v: UInt8 = rgb[idx];
    _put_decimal(&mut out, (v as Int) & 0xFF);
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

// Sample count of the raster: width * height * 3 (three per pixel).
pub fn ppm_sample_count(img: &PpmImage) -> Int {
  return img.width * img.height * 3;
}
