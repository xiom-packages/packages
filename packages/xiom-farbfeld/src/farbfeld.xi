// XIOM -- xiom.farbfeld: farbfeld 16-bit RGBA image codec
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure XIOM, no FFI. Reads and writes the farbfeld format on flat
// Vec[UInt8] buffers:
//
//   header := "farbfeld" BE32(width) BE32(height)
//   raster := width * height pixels of 8 bytes each:
//             BE16(R) BE16(G) BE16(B) BE16(A)
//
// The header is exactly 16 bytes and the raster starts immediately after it;
// a complete buffer must contain exactly 16 + 8*width*height bytes (shorter
// input is "farbfeld: truncated pixels", longer input is
// "farbfeld: extra pixel data"). Width and height are unsigned 32-bit
// big-endian fields: zero is rejected, and each axis is capped at 1,000,000
// (farbfeld_max_dim) so that 8*width*height can never overflow the 64-bit Int
// used for offsets. Pixels are row-major with a top-left origin, four channels
// per pixel, and no padding anywhere. Channels are stored as raw big-endian
// 16-bit values: no premultiplication, no color management, no interpretation
// of alpha. See SPEC.md for the byte-level layout and the full error catalog.

module xiom.farbfeld

// A parsed farbfeld header. The raster always starts at byte 16.
pub type FarbfeldImage = {
  width: Int;       // 1..1000000 pixels per row
  height: Int;      // 1..1000000 rows
  data_offset: Int; // first raster byte; always 16 for a parsed image
}

// One decoded pixel: four 16-bit channels widened to Int in 0..65535.
pub type FarbfeldPixel = {
  r: Int; // red 0..65535
  g: Int; // green 0..65535
  b: Int; // blue 0..65535
  a: Int; // alpha 0..65535
}

// ---------------------------------------------------------------------------
// Result leaf helpers (v0.61.3: Ok/Err may only appear in fns that return a
// Result directly, so every fallible public fn returns through one of these).
// ---------------------------------------------------------------------------

fn _err_img(m: Str) -> Result[FarbfeldImage, Str] { return Err(m); }
fn _ok_img(i: FarbfeldImage) -> Result[FarbfeldImage, Str] { return Ok(i); }
fn _err_px(m: Str) -> Result[FarbfeldPixel, Str] { return Err(m); }
fn _ok_px(p: FarbfeldPixel) -> Result[FarbfeldPixel, Str] { return Ok(p); }
fn _err_int(m: Str) -> Result[Int, Str] { return Err(m); }
fn _ok_int(v: Int) -> Result[Int, Str] { return Ok(v); }
fn _err_bytes(m: Str) -> Result[Vec[UInt8], Str] { return Err(m); }
fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], Str] { return Ok(v); }

// ---------------------------------------------------------------------------
// Byte readers and writers
// ---------------------------------------------------------------------------

// Unsigned byte at index i (widening masked to 0..255).
fn _b(data: &Vec[UInt8], i: Int) -> Int {
  return (data[i] as Int) & 0xFF;
}

// Big-endian 16-bit value at `off` (0..65535).
fn _be16(data: &Vec[UInt8], off: Int) -> Int {
  return _b(data, off) * 256 + _b(data, off + 1);
}

// Big-endian 32-bit value at `off` (0..4294967295).
fn _be32(data: &Vec[UInt8], off: Int) -> Int {
  return _b(data, off) * 16777216 + _b(data, off + 1) * 65536 + _b(data, off + 2) * 256 + _b(data, off + 3);
}

// True when data[0, 8) is exactly "farbfeld" (ASCII 102 97 114 98 102 101 108 100).
fn _magic_is(data: &Vec[UInt8]) -> Bool {
  if (_b(data, 0) != 102) { return false; }
  if (_b(data, 1) != 97) { return false; }
  if (_b(data, 2) != 114) { return false; }
  if (_b(data, 3) != 98) { return false; }
  if (_b(data, 4) != 102) { return false; }
  if (_b(data, 5) != 101) { return false; }
  if (_b(data, 6) != 108) { return false; }
  if (_b(data, 7) != 100) { return false; }
  return true;
}

// Append `v` (0..4294967295) to `out` as four big-endian bytes.
fn _push_be32(out: &mut Vec[UInt8], v: Int) {
  out.push(((v / 16777216) % 256) as UInt8);
  out.push(((v / 65536) % 256) as UInt8);
  out.push(((v / 256) % 256) as UInt8);
  out.push((v % 256) as UInt8);
}

// Append the canonical 16-byte header: the magic, then width and height as
// big-endian 32-bit fields. Dimensions must already be validated.
fn _put_header(out: &mut Vec[UInt8], width: Int, height: Int) {
  out.push(102 as UInt8); // 'f'
  out.push(97 as UInt8);  // 'a'
  out.push(114 as UInt8); // 'r'
  out.push(98 as UInt8);  // 'b'
  out.push(102 as UInt8); // 'f'
  out.push(101 as UInt8); // 'e'
  out.push(108 as UInt8); // 'l'
  out.push(100 as UInt8); // 'd'
  _push_be32(out, width);
  _push_be32(out, height);
}

// Deterministic dimension rejection shared by both builders: "" when
// width/height are usable (1..1000000), otherwise the error message.
fn _dim_error(width: Int, height: Int) -> Str {
  if (width == 0) { return "farbfeld: zero width"; }
  if (width < 0) { return "farbfeld: invalid width"; }
  if (width > 1000000) { return "farbfeld: dimension overflow"; }
  if (height == 0) { return "farbfeld: zero height"; }
  if (height < 0) { return "farbfeld: invalid height"; }
  if (height > 1000000) { return "farbfeld: dimension overflow"; }
  return "";
}

// The channel of the pixel `p` selected by c: 0 = R, 1 = G, 2 = B, anything
// else = A. Callers validate c before selecting.
fn _px_channel(p: FarbfeldPixel, c: Int) -> Int {
  if (c == 0) { return p.r; }
  if (c == 1) { return p.g; }
  if (c == 2) { return p.b; }
  return p.a;
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

// The documented dimension cap for both axes: 1,000,000. At the cap a full
// raster is 8,000,000,000,000 bytes, still far below the 64-bit Int range, so
// width*height*8 and data_offset + raster_len cannot overflow.
pub fn farbfeld_max_dim() -> Int {
  return 1000000;
}

// Width in pixels of a parsed image (always 1..1000000).
pub fn farbfeld_width(img: &FarbfeldImage) -> Int {
  return img.width;
}

// Height in rows of a parsed image (always 1..1000000).
pub fn farbfeld_height(img: &FarbfeldImage) -> Int {
  return img.height;
}

// Byte offset of the first raster byte in the buffer passed to
// farbfeld_parse_header (always 16).
pub fn farbfeld_data_offset(img: &FarbfeldImage) -> Int {
  return img.data_offset;
}

// Pixel count of the raster: width * height.
pub fn farbfeld_pixel_count(img: &FarbfeldImage) -> Int {
  return img.width * img.height;
}

// Length in bytes of one row: width * 8 (four 16-bit channels per pixel).
pub fn farbfeld_row_bytes(img: &FarbfeldImage) -> Int {
  return img.width * 8;
}

// Exact raster length in bytes: width * height * 8.
pub fn farbfeld_raster_len(img: &FarbfeldImage) -> Int {
  return img.width * img.height * 8;
}

// Byte offset of pixel (x, y) with a top-left origin, or -1 when the
// coordinate is outside the image. The sentinel is unambiguous because every
// in-range offset is >= 16.
pub fn farbfeld_pixel_offset(img: &FarbfeldImage, x: Int, y: Int) -> Int {
  if (x < 0) { return -1; }
  if (y < 0) { return -1; }
  if (x >= img.width) { return -1; }
  if (y >= img.height) { return -1; }
  return img.data_offset + (y * img.width + x) * 8;
}

// Parse and validate a complete single-image farbfeld buffer. Buffers shorter
// than 8 bytes are "farbfeld: truncated header"; the magic is checked next, so
// 8..15 byte buffers with the right magic are also "farbfeld: truncated
// header" while 8..15 byte buffers with a wrong magic are "farbfeld: bad
// magic". Zero axes are "farbfeld: zero width"/"farbfeld: zero height", axes
// above farbfeld_max_dim are "farbfeld: dimension overflow", and the raster
// must be exactly 8*width*height bytes: shorter is "farbfeld: truncated
// pixels", longer is "farbfeld: extra pixel data".
pub fn farbfeld_parse_header(data: &Vec[UInt8]) -> Result[FarbfeldImage, Str] {
  let n = data.len();
  if (n < 8) { return _err_img("farbfeld: truncated header"); }
  if (!_magic_is(data)) { return _err_img("farbfeld: bad magic"); }
  if (n < 16) { return _err_img("farbfeld: truncated header"); }
  let width = _be32(data, 8);
  if (width == 0) { return _err_img("farbfeld: zero width"); }
  if (width > 1000000) { return _err_img("farbfeld: dimension overflow"); }
  let height = _be32(data, 12);
  if (height == 0) { return _err_img("farbfeld: zero height"); }
  if (height > 1000000) { return _err_img("farbfeld: dimension overflow"); }
  let need = width * height * 8;
  if (n < 16 + need) { return _err_img("farbfeld: truncated pixels"); }
  if (n > 16 + need) { return _err_img("farbfeld: extra pixel data"); }
  let img = FarbfeldImage{ width: width; height: height; data_offset: 16; };
  return _ok_img(img);
}

// Decode pixel (x, y) with a top-left origin as four Ints in 0..65535 (R, G,
// B, A). Coordinates outside the image return Err("farbfeld: pixel out of
// range"); validation errors from farbfeld_parse_header are propagated
// unchanged, and a decoded pixel is always fully populated.
pub fn farbfeld_pixel_rgba(data: &Vec[UInt8], x: Int, y: Int) -> Result[FarbfeldPixel, Str] {
  let parsed = farbfeld_parse_header(data);
  match parsed {
    Ok(img) => {
      if (x < 0) { return _err_px("farbfeld: pixel out of range"); }
      if (y < 0) { return _err_px("farbfeld: pixel out of range"); }
      if (x >= img.width) { return _err_px("farbfeld: pixel out of range"); }
      if (y >= img.height) { return _err_px("farbfeld: pixel out of range"); }
      let pos = img.data_offset + (y * img.width + x) * 8;
      let p = FarbfeldPixel{
        r: _be16(data, pos);
        g: _be16(data, pos + 2);
        b: _be16(data, pos + 4);
        a: _be16(data, pos + 6);
      };
      return _ok_px(p);
    },
    Err(e) => { return _err_px(e); },
  }
}

// One channel of pixel (x, y): c 0 = R, 1 = G, 2 = B, 3 = A. Coordinates are
// validated exactly like farbfeld_pixel_rgba; c outside 0..3 is
// "farbfeld: channel index out of range".
pub fn farbfeld_pixel_channel(data: &Vec[UInt8], x: Int, y: Int, c: Int) -> Result[Int, Str] {
  let parsed = farbfeld_pixel_rgba(data, x, y);
  match parsed {
    Ok(p) => {
      if (c < 0) { return _err_int("farbfeld: channel index out of range"); }
      if (c > 3) { return _err_int("farbfeld: channel index out of range"); }
      return _ok_int(_px_channel(p, c));
    },
    Err(e) => { return _err_int(e); },
  }
}

// Copy one row (width * 8 bytes, no padding) out of `data` for the zero-based
// row index y. y outside 0..height-1 is "farbfeld: row out of range"; a forged
// or stale image whose span falls outside `data` is
// "farbfeld: raster out of range".
pub fn farbfeld_row_copy(data: &Vec[UInt8], img: &FarbfeldImage, y: Int) -> Result[Vec[UInt8], Str] {
  if (y < 0) { return _err_bytes("farbfeld: row out of range"); }
  if (y >= img.height) { return _err_bytes("farbfeld: row out of range"); }
  let rb = img.width * 8;
  let off = img.data_offset + y * rb;
  if (off < 0) { return _err_bytes("farbfeld: raster out of range"); }
  if (off + rb > data.len()) { return _err_bytes("farbfeld: raster out of range"); }
  let out = Vec[UInt8].new();
  var i = 0;
  while (i < rb) {
    let b: UInt8 = data[off + i];
    out.push(b);
    i = i + 1;
  }
  return _ok_bytes(out);
}

// Copy the exact raster span (width * height * 8 bytes, no padding) out of
// `data`. The span is guarded against the buffer length so a forged or stale
// image cannot read out of bounds: "farbfeld: raster out of range".
pub fn farbfeld_raster_copy(data: &Vec[UInt8], img: &FarbfeldImage) -> Result[Vec[UInt8], Str] {
  let rl = img.width * img.height * 8;
  if (img.data_offset < 0) { return _err_bytes("farbfeld: raster out of range"); }
  if (rl < 0) { return _err_bytes("farbfeld: raster out of range"); }
  if (img.data_offset + rl > data.len()) { return _err_bytes("farbfeld: raster out of range"); }
  let out = Vec[UInt8].new();
  var i = 0;
  while (i < rl) {
    let b: UInt8 = data[img.data_offset + i];
    out.push(b);
    i = i + 1;
  }
  return _ok_bytes(out);
}

// Build a canonical farbfeld byte string from a flat channel buffer: `rgba`
// holds width * height * 4 channel values in pixel order (R, G, B, A), each
// 0..65535. Emits the 16-byte header followed by every channel as two
// big-endian bytes, no padding. Err when a dimension is zero, negative or
// above farbfeld_max_dim, when rgba.len() != width*height*4
// ("farbfeld: channel buffer size mismatch"), or when any channel is outside
// 0..65535 ("farbfeld: channel out of range"). Nothing is emitted unless the
// whole buffer validates.
pub fn farbfeld_build(rgba: &Vec[Int], width: Int, height: Int) -> Result[Vec[UInt8], Str] {
  let e = _dim_error(width, height);
  if (e.len() > 0) { return _err_bytes(e); }
  let need = width * height * 4;
  if (rgba.len() != need) { return _err_bytes("farbfeld: channel buffer size mismatch"); }
  var i = 0;
  while (i < need) {
    let v: Int = rgba[i];
    if (v < 0) { return _err_bytes("farbfeld: channel out of range"); }
    if (v > 65535) { return _err_bytes("farbfeld: channel out of range"); }
    i = i + 1;
  }
  var out = Vec[UInt8].new();
  _put_header(&mut out, width, height);
  i = 0;
  while (i < need) {
    let v: Int = rgba[i];
    out.push(((v / 256) % 256) as UInt8);
    out.push((v % 256) as UInt8);
    i = i + 1;
  }
  return _ok_bytes(out);
}

// Build a canonical farbfeld byte string from width * height * 8 pre-encoded
// big-endian channel bytes (8 bytes per pixel, in pixel order). The bytes are
// copied verbatim: no channel values are interpreted or range checked.
// Dimensions are validated exactly like farbfeld_build; a byte count other
// than width*height*8 is "farbfeld: raster buffer size mismatch".
pub fn farbfeld_build_raw(be_rgba: &Vec[UInt8], width: Int, height: Int) -> Result[Vec[UInt8], Str] {
  let e = _dim_error(width, height);
  if (e.len() > 0) { return _err_bytes(e); }
  let need = width * height * 8;
  if (be_rgba.len() != need) { return _err_bytes("farbfeld: raster buffer size mismatch"); }
  var out = Vec[UInt8].new();
  _put_header(&mut out, width, height);
  var i = 0;
  while (i < need) {
    let b: UInt8 = be_rgba[i];
    out.push(b);
    i = i + 1;
  }
  return _ok_bytes(out);
}
