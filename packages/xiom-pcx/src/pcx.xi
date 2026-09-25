// XIOM -- xiom.pcx: PCX header, palette and pixel-span codec (documented subset)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure XIOM, no FFI. Parses and builds the 128-byte PCX header, reads the
// 16-entry header palette and the optional 768-byte VGA palette trailer
// (detected by its 0x0C marker at file end), locates the RLE pixel-data span
// between the header and the trailer, and validates the documented subset.
// Pixel data is never decoded: no RLE packet is expanded and no pixel is
// rendered. See SPEC.md for the layout tables, the supported plane
// configurations and the error catalog.

module xiom.pcx

// The 128-byte PCX header, fully decoded. All on-disk fields are unsigned and
// kept as Int so arithmetic cannot overflow. `width` and `height` are derived
// from xmin/ymin/xmax/ymax (PCX geometry is inclusive); pcx_build_header
// ignores those two derived fields and recomputes them via pcx_parse_header.
// `reserved` is the byte at offset 64: informational and never validated.
// `palette_type` is 0/1 for color or black-and-white and 2 for grayscale.
pub type PcxHeader = {
  manufacturer: Int;   // must be 10 (0x0A); pinned to 10 by the builder
  version: Int;        // 0..5 (0 = 2.5, 5 = 3.0+)
  encoding: Int;       // must be 1 (RLE); 0 = unencoded is out of subset
  bits_per_pixel: Int; // 1, 2, 4 or 8 bits per plane
  xmin: Int;           // left edge, inclusive, 0..65535
  ymin: Int;           // top edge, inclusive, 0..65535
  xmax: Int;           // right edge, inclusive, >= xmin
  ymax: Int;           // bottom edge, inclusive, >= ymin
  hdpi: Int;           // horizontal resolution, 0..65535
  vdpi: Int;           // vertical resolution, 0..65535
  reserved: Int;       // byte 64, informational
  color_planes: Int;   // 1..4, constrained by the plane/bits table
  bytes_per_line: Int; // per plane per scanline: even, >= scanline bytes
  palette_type: Int;   // 0/1 = color or black-and-white, 2 = grayscale
  hscreen: Int;        // horizontal screen size, 0..65535
  vscreen: Int;        // vertical screen size, 0..65535
  width: Int;          // derived: xmax - xmin + 1 (1..65536)
  height: Int;         // derived: ymax - ymin + 1 (1..65536)
}

// A fully located PCX buffer: the decoded header plus the pixel-data span and
// the VGA trailer position. `trailer_offset` is the offset of the 0x0C trailer
// marker when the trailer is present, otherwise it equals the file length.
// `pixel_bytes` is always at least 1: a file with no RLE bytes between the
// header and the trailer is rejected as truncated.
pub type PcxInfo = {
  header: PcxHeader;
  has_vga_palette: Bool; // true when the 769-byte trailer was detected
  trailer_offset: Int;   // n - 769 when present, else n
  pixel_offset: Int;     // always 128 (right after the header)
  pixel_bytes: Int;      // trailer_offset - 128; RLE bytes, never decoded
}

// ---------------------------------------------------------------------------
// Result leaf helpers (v0.61.3: Ok/Err may only be constructed in fns that
// return a Result directly, so every fallible public fn returns through one
// of these small constructors).
// ---------------------------------------------------------------------------

fn _err_hdr(m: Str) -> Result[PcxHeader, Str] { return Err(m); }
fn _ok_hdr(h: PcxHeader) -> Result[PcxHeader, Str] { return Ok(h); }
fn _err_info(m: Str) -> Result[PcxInfo, Str] { return Err(m); }
fn _ok_info(v: PcxInfo) -> Result[PcxInfo, Str] { return Ok(v); }
fn _err_int(m: Str) -> Result[Int, Str] { return Err(m); }
fn _ok_int(v: Int) -> Result[Int, Str] { return Ok(v); }
fn _err_bytes(m: Str) -> Result[Vec[UInt8], Str] { return Err(m); }
fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], Str] { return Ok(v); }

// ---------------------------------------------------------------------------
// Byte readers and writers (little-endian, as the PCX format requires)
// ---------------------------------------------------------------------------

// Unsigned byte at index i (widened and masked to 0..255).
fn _b(data: &Vec[UInt8], i: Int) -> Int {
  return (data[i] as Int) & 0xFF;
}

// Unsigned 16-bit little-endian value at `off`.
fn _le16(data: &Vec[UInt8], off: Int) -> Int {
  let b0 = _b(data, off);
  let b1 = _b(data, off + 1);
  return b0 + b1 * 256;
}

// Append the low 16 bits of v to out, little-endian.
fn _p16(out: &mut Vec[UInt8], v: Int) {
  out.push((v % 256) as UInt8);
  out.push(((v / 256) % 256) as UInt8);
}

// ---------------------------------------------------------------------------
// Field predicates and derived sizes
// ---------------------------------------------------------------------------

// Minimum bytes needed for one scanline of one plane:
// ceil(width * bits_per_pixel / 8). Zero when width or bits is not positive.
// pcx_parse_header requires bytes_per_line to be even and at least this large.
pub fn pcx_scanline_bytes(width: Int, bits_per_pixel: Int) -> Int {
  if (width <= 0) { return 0; }
  if (bits_per_pixel <= 0) { return 0; }
  return (width * bits_per_pixel + 7) / 8;
}

// Bytes a fully decoded image occupies under this header:
// bytes_per_line * color_planes * height. This codec never expands an RLE
// stream, so the value is informational (buffer sizing, sanity checks).
pub fn pcx_decoded_bytes(h: &PcxHeader) -> Int {
  return h.bytes_per_line * h.color_planes * h.height;
}

// True for the documented plane/bits combinations. For palette type 2
// (grayscale) only 1 plane at 1 or 8 bits is supported. For the color types
// 0/1 the table is: 1 bit with 1..4 planes, 2 bits with 1 plane, 4 bits with
// 1 plane, 8 bits with 1, 3 or 4 planes (indexed, RGB, RGBA). `bits` must
// already be one of 1/2/4/8.
fn _combo_ok(bits: Int, planes: Int, ptype: Int) -> Bool {
  if (ptype == 2) {
    if (planes != 1) { return false; }
    if (bits == 1) { return true; }
    if (bits == 8) { return true; }
    return false;
  }
  if (bits == 1) {
    if (planes < 1) { return false; }
    if (planes > 4) { return false; }
    return true;
  }
  if (bits == 2) { return planes == 1; }
  if (bits == 4) { return planes == 1; }
  if (bits == 8) {
    if (planes == 1) { return true; }
    if (planes == 3) { return true; }
    if (planes == 4) { return true; }
    return false;
  }
  return false;
}

// Trailer detection: the buffer must be at least 128 + 769 bytes (room for a
// header, the 0x0C marker and the 768 palette bytes) and byte n-769 must be
// 0x0C. Requiring the header room keeps the marker out of the header for
// short buffers.
fn _has_vga(data: &Vec[UInt8]) -> Bool {
  let n = data.len();
  if (n < 897) { return false; }
  return _b(data, n - 769) == 12;
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

// Parse and validate the 128-byte header. Structural rules, in order: the
// buffer must hold all 128 bytes; manufacturer must be 10; version must be
// 0..5; encoding must be 1 (RLE -- the unencoded encoding 0 is out of this
// codec's subset); bits per pixel must be 1, 2, 4 or 8; xmax >= xmin and
// ymax >= ymin (zero or negative geometry is rejected); color planes must be
// 1..4; bytes_per_line must be even and at least
// pcx_scanline_bytes(width, bits_per_pixel); palette_type must be 0, 1 or 2;
// and the bits/planes pair must appear in the documented table. The reserved
// byte and the 54 filler bytes are parsed/ignored, never validated.
pub fn pcx_parse_header(data: &Vec[UInt8]) -> Result[PcxHeader, Str] {
  let n = data.len();
  if (n < 128) { return _err_hdr("pcx: truncated header"); }
  let manufacturer = _b(data, 0);
  if (manufacturer != 10) { return _err_hdr("pcx: bad manufacturer"); }
  let version = _b(data, 1);
  if (version > 5) { return _err_hdr("pcx: unsupported version"); }
  let encoding = _b(data, 2);
  if (encoding != 1) { return _err_hdr("pcx: unsupported encoding"); }
  let bits = _b(data, 3);
  if (bits != 1 && bits != 2 && bits != 4 && bits != 8) {
    return _err_hdr("pcx: invalid bits per pixel");
  }
  let xmin = _le16(data, 4);
  let ymin = _le16(data, 6);
  let xmax = _le16(data, 8);
  let ymax = _le16(data, 10);
  if (xmax < xmin) { return _err_hdr("pcx: invalid geometry"); }
  if (ymax < ymin) { return _err_hdr("pcx: invalid geometry"); }
  let planes = _b(data, 65);
  if (planes < 1 || planes > 4) {
    return _err_hdr("pcx: invalid color planes");
  }
  let width = xmax - xmin + 1;
  let height = ymax - ymin + 1;
  let bpl = _le16(data, 66);
  if (bpl % 2 != 0) { return _err_hdr("pcx: invalid bytes per line"); }
  if (bpl < pcx_scanline_bytes(width, bits)) {
    return _err_hdr("pcx: invalid bytes per line");
  }
  let ptype = _le16(data, 68);
  if (ptype != 0 && ptype != 1 && ptype != 2) {
    return _err_hdr("pcx: invalid palette type");
  }
  if (!_combo_ok(bits, planes, ptype)) {
    return _err_hdr("pcx: invalid plane configuration");
  }
  let hdpi = _le16(data, 12);
  let vdpi = _le16(data, 14);
  let reserved = _b(data, 64);
  let hscreen = _le16(data, 70);
  let vscreen = _le16(data, 72);
  let h = PcxHeader{
    manufacturer: manufacturer;
    version: version;
    encoding: encoding;
    bits_per_pixel: bits;
    xmin: xmin;
    ymin: ymin;
    xmax: xmax;
    ymax: ymax;
    hdpi: hdpi;
    vdpi: vdpi;
    reserved: reserved;
    color_planes: planes;
    bytes_per_line: bpl;
    palette_type: ptype;
    hscreen: hscreen;
    vscreen: vscreen;
    width: width;
    height: height;
  };
  return _ok_hdr(h);
}

// Build the 128-byte header. `palette` must hold exactly 48 bytes (16 RGB
// triplets) and is copied verbatim; padding bytes are zeroed. Every scalar
// field is range-checked against its on-disk width, then the assembled buffer
// is re-validated by pcx_parse_header, whose messages are forwarded unchanged
// (so reversed geometry, odd bytes_per_line, bad plane combinations and the
// rest all surface with their parser message). The builder always writes
// manufacturer 10 and reserved 0; the `manufacturer`, `reserved`, `width` and
// `height` fields of `h` are ignored.
pub fn pcx_build_header(h: &PcxHeader, palette: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  if (palette.len() != 48) { return _err_bytes("pcx: invalid palette size"); }
  if (h.version < 0 || h.version > 5) {
    return _err_bytes("pcx: unsupported version");
  }
  if (h.encoding < 0 || h.encoding > 255) {
    return _err_bytes("pcx: unsupported encoding");
  }
  if (h.bits_per_pixel < 0 || h.bits_per_pixel > 255) {
    return _err_bytes("pcx: invalid bits per pixel");
  }
  if (h.xmin < 0 || h.xmin > 65535) {
    return _err_bytes("pcx: invalid geometry");
  }
  if (h.ymin < 0 || h.ymin > 65535) {
    return _err_bytes("pcx: invalid geometry");
  }
  if (h.xmax < 0 || h.xmax > 65535) {
    return _err_bytes("pcx: invalid geometry");
  }
  if (h.ymax < 0 || h.ymax > 65535) {
    return _err_bytes("pcx: invalid geometry");
  }
  if (h.hdpi < 0 || h.hdpi > 65535) {
    return _err_bytes("pcx: invalid resolution");
  }
  if (h.vdpi < 0 || h.vdpi > 65535) {
    return _err_bytes("pcx: invalid resolution");
  }
  if (h.color_planes < 0 || h.color_planes > 255) {
    return _err_bytes("pcx: invalid color planes");
  }
  if (h.bytes_per_line < 0 || h.bytes_per_line > 65535) {
    return _err_bytes("pcx: invalid bytes per line");
  }
  if (h.palette_type < 0 || h.palette_type > 65535) {
    return _err_bytes("pcx: invalid palette type");
  }
  if (h.hscreen < 0 || h.hscreen > 65535) {
    return _err_bytes("pcx: invalid screen size");
  }
  if (h.vscreen < 0 || h.vscreen > 65535) {
    return _err_bytes("pcx: invalid screen size");
  }
  let out = Vec[UInt8].new();
  out.push(10 as UInt8);
  out.push(h.version as UInt8);
  out.push(h.encoding as UInt8);
  out.push(h.bits_per_pixel as UInt8);
  _p16(&mut out, h.xmin);
  _p16(&mut out, h.ymin);
  _p16(&mut out, h.xmax);
  _p16(&mut out, h.ymax);
  _p16(&mut out, h.hdpi);
  _p16(&mut out, h.vdpi);
  var i = 0;
  while (i < 48) {
    let b: UInt8 = palette[i];
    out.push(b);
    i = i + 1;
  }
  out.push(0 as UInt8);
  out.push(h.color_planes as UInt8);
  _p16(&mut out, h.bytes_per_line);
  _p16(&mut out, h.palette_type);
  _p16(&mut out, h.hscreen);
  _p16(&mut out, h.vscreen);
  var pad = 0;
  while (pad < 54) {
    out.push(0 as UInt8);
    pad = pad + 1;
  }
  let check = pcx_parse_header(out);
  match check {
    Ok(ok) => { return _ok_bytes(out); },
    Err(e) => { return _err_bytes(e); },
  }
}

// ---------------------------------------------------------------------------
// Whole-buffer parse and span accessors
// ---------------------------------------------------------------------------

// Parse and validate a whole PCX buffer: the header plus the pixel-data span
// between the header and the optional trailer. The trailer is present when
// pcx_has_vga_palette is true, in which case the span ends at its 0x0C marker;
// otherwise the span runs to the end of the buffer. A span shorter than one
// byte is `pcx: truncated pixel data`. The RLE bytes themselves are opaque:
// they are located and copied, never expanded.
pub fn pcx_parse(data: &Vec[UInt8]) -> Result[PcxInfo, Str] {
  let hp = pcx_parse_header(data);
  match hp {
    Ok(h) => {
      let n = data.len();
      var trailer = n;
      var has_vga = false;
      if (_has_vga(data)) {
        trailer = n - 769;
        has_vga = true;
      }
      let span = trailer - 128;
      if (span < 1) { return _err_info("pcx: truncated pixel data"); }
      let info = PcxInfo{
        header: h;
        has_vga_palette: has_vga;
        trailer_offset: trailer;
        pixel_offset: 128;
        pixel_bytes: span;
      };
      return _ok_info(info);
    },
    Err(e) => { return _err_info(e); },
  }
}

// True when the buffer ends with a 769-byte VGA palette trailer: at least
// 128 + 769 bytes long with the 0x0C marker at byte n-769, immediately
// followed by 768 RGB bytes. Only the length and the marker byte are
// inspected; the header is not validated and the palette content is not
// interpreted.
pub fn pcx_has_vga_palette(data: &Vec[UInt8]) -> Bool {
  return _has_vga(data);
}

// Offset of the first RLE pixel byte: always 128, immediately after the
// header. Validates the buffer through pcx_parse.
pub fn pcx_pixel_offset(data: &Vec[UInt8]) -> Result[Int, Str] {
  let p = pcx_parse(data);
  match p {
    Ok(info) => { return _ok_int(info.pixel_offset); },
    Err(e) => { return _err_int(e); },
  }
}

// Number of RLE bytes between the header and the trailer (or the end of the
// buffer when no trailer is present). Validates the buffer through pcx_parse.
pub fn pcx_pixel_length(data: &Vec[UInt8]) -> Result[Int, Str] {
  let p = pcx_parse(data);
  match p {
    Ok(info) => { return _ok_int(info.pixel_bytes); },
    Err(e) => { return _err_int(e); },
  }
}

// Copy the RLE pixel-data span (128 .. trailer_offset). The bytes are opaque:
// no packet is expanded and no pixel is decoded.
pub fn pcx_pixel_data(data: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  let p = pcx_parse(data);
  match p {
    Ok(info) => {
      let out = Vec[UInt8].new();
      var i = 0;
      while (i < info.pixel_bytes) {
        let b: UInt8 = data[info.pixel_offset + i];
        out.push(b);
        i = i + 1;
      }
      return _ok_bytes(out);
    },
    Err(e) => { return _err_bytes(e); },
  }
}

// ---------------------------------------------------------------------------
// Palettes
// ---------------------------------------------------------------------------

// Copy the 16-entry header palette (48 raw RGB bytes at offset 16). Validates
// the header first. Entry i starts at byte 16 + 3*i.
pub fn pcx_header_palette(data: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  let hp = pcx_parse_header(data);
  match hp {
    Ok(h) => {
      let out = Vec[UInt8].new();
      var i = 0;
      while (i < 48) {
        let b: UInt8 = data[16 + i];
        out.push(b);
        i = i + 1;
      }
      return _ok_bytes(out);
    },
    Err(e) => { return _err_bytes(e); },
  }
}

// Packed 0xRRGGBB value of one of the 16 header-palette entries (0..15).
// Validates the header first; an index outside 0..15 is
// `pcx: palette index out of range`.
pub fn pcx_header_palette_entry(data: &Vec[UInt8], index: Int) -> Result[Int, Str] {
  if (index < 0 || index > 15) {
    return _err_int("pcx: palette index out of range");
  }
  let hp = pcx_parse_header(data);
  match hp {
    Ok(h) => {
      let base = 16 + index * 3;
      let r = _b(data, base);
      let g = _b(data, base + 1);
      let b = _b(data, base + 2);
      return _ok_int(r * 65536 + g * 256 + b);
    },
    Err(e) => { return _err_int(e); },
  }
}

// Copy the 768 RGB bytes of the VGA palette trailer (256 entries). Validates
// the header, then requires the trailer; without one the result is
// `pcx: missing vga palette trailer`.
pub fn pcx_vga_palette(data: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  let hp = pcx_parse_header(data);
  match hp {
    Ok(h) => {
      if (!_has_vga(data)) {
        return _err_bytes("pcx: missing vga palette trailer");
      }
      let n = data.len();
      let out = Vec[UInt8].new();
      var i = 0;
      while (i < 768) {
        let b: UInt8 = data[n - 768 + i];
        out.push(b);
        i = i + 1;
      }
      return _ok_bytes(out);
    },
    Err(e) => { return _err_bytes(e); },
  }
}

// Packed 0xRRGGBB value of one of the 256 VGA trailer entries (0..255).
// Validates the header, then requires the trailer; an index outside 0..255 is
// `pcx: vga palette index out of range`, a missing trailer is
// `pcx: missing vga palette trailer`.
pub fn pcx_vga_palette_entry(data: &Vec[UInt8], index: Int) -> Result[Int, Str] {
  if (index < 0 || index > 255) {
    return _err_int("pcx: vga palette index out of range");
  }
  let hp = pcx_parse_header(data);
  match hp {
    Ok(h) => {
      if (!_has_vga(data)) {
        return _err_int("pcx: missing vga palette trailer");
      }
      let n = data.len();
      let base = n - 768 + index * 3;
      let r = _b(data, base);
      let g = _b(data, base + 1);
      let b = _b(data, base + 2);
      return _ok_int(r * 65536 + g * 256 + b);
    },
    Err(e) => { return _err_int(e); },
  }
}
