// XIOM -- xiom.tga: Truevision TGA header and footer codec (documented subset)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure XIOM, no FFI. Parses and builds the 18-byte TGA header and the 26-byte
// TGA 2.0 footer, locates the optional image ID field, the optional color map
// data, and the raster of uncompressed image types. RLE raster data is located
// by offset only: its length is unknown without decoding, so `data_bytes` is
// -1 and tga_image_data rejects RLE buffers. No pixel is ever decoded.
//
// Supported image types: 0 (no image data), 1/2/3 (uncompressed color-mapped,
// true-color, black-and-white) and 9/10/11 (their RLE counterparts). Pixel
// depth rules: type 0 -> 0; types 1/9 -> 8 or 16; types 2/10 -> 15, 16, 24 or
// 32; types 3/11 -> 8 or 16. Color map entry sizes: 15, 16, 24 or 32 bits.
// Version 2 is detected when the trailing 26 bytes carry the
// "TRUEVISION-XFILE." signature plus its NUL terminator; otherwise the buffer
// is treated as version 1, which by definition has no footer (documented TGA
// 1.0 behavior) and therefore also no extension/developer area offsets.
// Extension and developer areas are bounds-checked but never parsed. Bits 6-7
// of the image descriptor (TGA 1.0 interleaving) are ignored on parse and
// written as zero on build. See SPEC.md for the layout tables and the error
// catalog.

module xiom.tga

// The 18-byte TGA header, fully decoded. All fields are unsigned; they are
// kept as Int so arithmetic cannot overflow. `origin_bits` is descriptor bits
// 4-5: 0 = bottom-left origin, 1 = bottom-right, 2 = top-left, 3 = top-right.
// `attribute_bits` is descriptor bits 0-3 (alpha or overlay bits).
pub type TgaHeader = {
  id_length: Int;        // image ID field length, 0..255
  color_map_type: Int;   // 0 = no color map, 1 = color map present
  image_type: Int;       // 0, 1, 2, 3, 9, 10 or 11
  cmap_first: Int;       // first color map entry index, 0..65535
  cmap_length: Int;      // number of color map entries, 0..65535
  cmap_entry_bits: Int;  // bits per color map entry: 15, 16, 24 or 32
  x_origin: Int;         // image origin X coordinate, 0..65535
  y_origin: Int;         // image origin Y coordinate, 0..65535
  width: Int;            // image width in pixels, 0..65535
  height: Int;           // image height in pixels, 0..65535
  pixel_depth: Int;      // bits per pixel: 0, 8, 15, 16, 24 or 32
  attribute_bits: Int;   // descriptor bits 0-3
  origin_bits: Int;      // descriptor bits 4-5, 0..3
}

// The 26-byte TGA 2.0 footer, decoded. An offset of 0 means the corresponding
// area is absent.
pub type TgaFooter = {
  extension_offset: Int;  // byte offset of the extension area, 0 = absent
  developer_offset: Int;  // byte offset of the developer area, 0 = absent
}

// A fully located TGA buffer: the decoded header plus every region offset.
// `data_bytes` is the exact uncompressed raster length, 0 for image type 0,
// and -1 when the raster is RLE encoded (length unknown without decoding).
pub type TgaImage = {
  header: TgaHeader;
  version: Int;            // 1 = no footer detected, 2 = v2 footer detected
  id_offset: Int;          // always 18
  cmap_offset: Int;        // 18 + id_length
  cmap_bytes: Int;         // cmap_length * entry size in bytes
  data_offset: Int;        // first raster byte (or first RLE packet byte)
  data_bytes: Int;         // uncompressed raster length, or -1 for RLE
  extension_offset: Int;   // v2 only, 0 = absent
  developer_offset: Int;   // v2 only, 0 = absent
}

// ---------------------------------------------------------------------------
// Result leaf helpers (v0.61.3: Ok/Err may only be constructed in fns that
// return a Result directly, so every fallible public fn returns through one
// of these small constructors).
// ---------------------------------------------------------------------------

fn _err_hdr(m: Str) -> Result[TgaHeader, Str] { return Err(m); }
fn _ok_hdr(h: TgaHeader) -> Result[TgaHeader, Str] { return Ok(h); }
fn _err_foot(m: Str) -> Result[TgaFooter, Str] { return Err(m); }
fn _ok_foot(f: TgaFooter) -> Result[TgaFooter, Str] { return Ok(f); }
fn _err_img(m: Str) -> Result[TgaImage, Str] { return Err(m); }
fn _ok_img(v: TgaImage) -> Result[TgaImage, Str] { return Ok(v); }
fn _err_bytes(m: Str) -> Result[Vec[UInt8], Str] { return Err(m); }
fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], Str] { return Ok(v); }

// ---------------------------------------------------------------------------
// Byte readers and writers (little-endian, as the TGA format requires)
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

// Unsigned 32-bit little-endian value at `off`.
fn _le32(data: &Vec[UInt8], off: Int) -> Int {
  let b0 = _b(data, off);
  let b1 = _b(data, off + 1);
  let b2 = _b(data, off + 2);
  let b3 = _b(data, off + 3);
  return b0 + b1 * 256 + b2 * 65536 + b3 * 16777216;
}

// Append the low 16 bits of v to out, little-endian.
fn _p16(out: &mut Vec[UInt8], v: Int) {
  out.push((v % 256) as UInt8);
  out.push(((v / 256) % 256) as UInt8);
}

// Append the low 32 bits of v to out, little-endian.
fn _p32(out: &mut Vec[UInt8], v: Int) {
  out.push((v % 256) as UInt8);
  out.push(((v / 256) % 256) as UInt8);
  out.push(((v / 65536) % 256) as UInt8);
  out.push(((v / 16777216) % 256) as UInt8);
}

// ---------------------------------------------------------------------------
// Field predicates
// ---------------------------------------------------------------------------

// True for the RLE image types 9, 10 and 11.
pub fn tga_is_rle(image_type: Int) -> Bool {
  if (image_type == 9) { return true; }
  if (image_type == 10) { return true; }
  if (image_type == 11) { return true; }
  return false;
}

// Bytes per pixel for a pixel depth: ceil(depth / 8); 0 for depth 0 or less.
pub fn tga_bytes_per_pixel(pixel_depth: Int) -> Int {
  if (pixel_depth <= 0) { return 0; }
  return (pixel_depth + 7) / 8;
}

// Raster length in bytes implied by the header: 0 for image type 0, -1 for
// RLE types (unknown without decoding), otherwise bytes_per_pixel * width *
// height for the uncompressed types 1, 2 and 3.
pub fn tga_data_bytes(h: &TgaHeader) -> Int {
  if (h.image_type == 0) { return 0; }
  if (tga_is_rle(h.image_type)) { return -1; }
  return tga_bytes_per_pixel(h.pixel_depth) * h.width * h.height;
}

// Bytes per color map entry: 2 for 15/16-bit, 3 for 24-bit, 4 for 32-bit,
// 0 for anything else (the header parser rejects 0).
fn _cmap_entry_bytes(bits: Int) -> Int {
  if (bits == 15) { return 2; }
  if (bits == 16) { return 2; }
  if (bits == 24) { return 3; }
  if (bits == 32) { return 4; }
  return 0;
}

// True for the seven supported image type codes.
fn _is_known_type(t: Int) -> Bool {
  if (t == 0) { return true; }
  if (t == 1) { return true; }
  if (t == 2) { return true; }
  if (t == 3) { return true; }
  if (t == 9) { return true; }
  if (t == 10) { return true; }
  if (t == 11) { return true; }
  return false;
}

// True when the 18 signature bytes at `off` are "TRUEVISION-XFILE." followed
// by the NUL terminator (TGA 2.0 footer signature).
fn _signature_at(data: &Vec[UInt8], off: Int) -> Bool {
  if (_b(data, off + 0) != 84) { return false; }   // T
  if (_b(data, off + 1) != 82) { return false; }   // R
  if (_b(data, off + 2) != 85) { return false; }   // U
  if (_b(data, off + 3) != 69) { return false; }   // E
  if (_b(data, off + 4) != 86) { return false; }   // V
  if (_b(data, off + 5) != 73) { return false; }   // I
  if (_b(data, off + 6) != 83) { return false; }   // S
  if (_b(data, off + 7) != 73) { return false; }   // I
  if (_b(data, off + 8) != 79) { return false; }   // O
  if (_b(data, off + 9) != 78) { return false; }   // N
  if (_b(data, off + 10) != 45) { return false; }  // -
  if (_b(data, off + 11) != 88) { return false; }  // X
  if (_b(data, off + 12) != 70) { return false; }  // F
  if (_b(data, off + 13) != 73) { return false; }  // I
  if (_b(data, off + 14) != 76) { return false; }  // L
  if (_b(data, off + 15) != 69) { return false; }  // E
  if (_b(data, off + 16) != 46) { return false; }  // .
  if (_b(data, off + 17) != 0) { return false; }   // NUL
  return true;
}

// Append the 18 signature bytes "TRUEVISION-XFILE." plus NUL to out.
fn _put_signature(out: &mut Vec[UInt8]) {
  out.push(84 as UInt8);   // T
  out.push(82 as UInt8);   // R
  out.push(85 as UInt8);   // U
  out.push(69 as UInt8);   // E
  out.push(86 as UInt8);   // V
  out.push(73 as UInt8);   // I
  out.push(83 as UInt8);   // S
  out.push(73 as UInt8);   // I
  out.push(79 as UInt8);   // O
  out.push(78 as UInt8);   // N
  out.push(45 as UInt8);   // -
  out.push(88 as UInt8);   // X
  out.push(70 as UInt8);   // F
  out.push(73 as UInt8);   // I
  out.push(76 as UInt8);   // L
  out.push(69 as UInt8);   // E
  out.push(46 as UInt8);   // .
  out.push(0 as UInt8);    // NUL
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

// Parse and validate the 18-byte header. Structural rules: the image type must
// be one of 0/1/2/3/9/10/11; the color map type must be 0 or 1; zero width or
// height is rejected for every type that carries a raster, while image type 0
// requires width, height and pixel depth to be 0 and no color map; pixel
// depth must match the image type (1/9: 8 or 16, 2/10: 15/16/24/32, 3/11: 8 or
// 16); a color map type of 1 requires cmap_length > 0 and 15/16/24/32-bit
// entries, a color map type of 0 requires cmap_length == 0; image types 1 and
// 9 require a color map. The image ID and color map data are not required to
// be present here -- tga_parse and the slice accessors check the buffer.
pub fn tga_parse_header(data: &Vec[UInt8]) -> Result[TgaHeader, Str] {
  let n = data.len();
  if (n < 18) { return _err_hdr("tga: truncated header"); }
  let id_length = _b(data, 0);
  let cmap_type = _b(data, 1);
  let image_type = _b(data, 2);
  if (cmap_type != 0 && cmap_type != 1) {
    return _err_hdr("tga: invalid color map type");
  }
  if (!_is_known_type(image_type)) {
    return _err_hdr("tga: unknown image type");
  }
  let cmap_first = _le16(data, 3);
  let cmap_length = _le16(data, 5);
  let cmap_bits = _b(data, 7);
  let x_origin = _le16(data, 8);
  let y_origin = _le16(data, 10);
  let width = _le16(data, 12);
  let height = _le16(data, 14);
  let pixel_depth = _b(data, 16);
  let descriptor = _b(data, 17);
  if (image_type == 0) {
    if (cmap_type != 0) { return _err_hdr("tga: unexpected color map"); }
    if (pixel_depth != 0) { return _err_hdr("tga: unsupported pixel depth"); }
    if (width != 0) { return _err_hdr("tga: invalid width"); }
    if (height != 0) { return _err_hdr("tga: invalid height"); }
  } else {
    if (image_type == 1 || image_type == 9) {
      if (pixel_depth != 8 && pixel_depth != 16) {
        return _err_hdr("tga: unsupported pixel depth");
      }
    } else {
      if (image_type == 2 || image_type == 10) {
        if (pixel_depth != 15 && pixel_depth != 16 && pixel_depth != 24 && pixel_depth != 32) {
          return _err_hdr("tga: unsupported pixel depth");
        }
      } else {
        if (pixel_depth != 8 && pixel_depth != 16) {
          return _err_hdr("tga: unsupported pixel depth");
        }
      }
    }
    if (width == 0) { return _err_hdr("tga: invalid width"); }
    if (height == 0) { return _err_hdr("tga: invalid height"); }
  }
  if (image_type == 1 || image_type == 9) {
    if (cmap_type != 1) {
      return _err_hdr("tga: color map required for image type");
    }
  }
  if (cmap_type == 1) {
    if (cmap_length == 0) { return _err_hdr("tga: invalid color map length"); }
    if (_cmap_entry_bytes(cmap_bits) == 0) {
      return _err_hdr("tga: invalid color map entry size");
    }
  } else {
    if (cmap_length != 0) { return _err_hdr("tga: unexpected color map"); }
  }
  let h = TgaHeader{
    id_length: id_length;
    color_map_type: cmap_type;
    image_type: image_type;
    cmap_first: cmap_first;
    cmap_length: cmap_length;
    cmap_entry_bits: cmap_bits;
    x_origin: x_origin;
    y_origin: y_origin;
    width: width;
    height: height;
    pixel_depth: pixel_depth;
    attribute_bits: descriptor % 16;
    origin_bits: (descriptor / 16) % 4;
  };
  return _ok_hdr(h);
}

// Build the 18-byte header. Every field must fit its on-disk width (id_length
// 0..255, color map first/length 0..65535, origins 0..65535, width/height
// 0..65535, attribute bits 0..15, origin bits 0..3) and the assembled header
// must pass the same field validation as tga_parse_header, whose messages are
// forwarded unchanged. Descriptor bits 6-7 are written as zero.
pub fn tga_build_header(h: &TgaHeader) -> Result[Vec[UInt8], Str] {
  if (h.id_length < 0 || h.id_length > 255) {
    return _err_bytes("tga: invalid image id length");
  }
  if (h.color_map_type < 0 || h.color_map_type > 1) {
    return _err_bytes("tga: invalid color map type");
  }
  if (h.image_type < 0 || h.image_type > 255) {
    return _err_bytes("tga: unknown image type");
  }
  if (h.cmap_first < 0 || h.cmap_first > 65535) {
    return _err_bytes("tga: invalid color map first index");
  }
  if (h.cmap_length < 0 || h.cmap_length > 65535) {
    return _err_bytes("tga: invalid color map length");
  }
  if (h.cmap_entry_bits < 0 || h.cmap_entry_bits > 255) {
    return _err_bytes("tga: invalid color map entry size");
  }
  if (h.x_origin < 0 || h.x_origin > 65535) {
    return _err_bytes("tga: invalid x origin");
  }
  if (h.y_origin < 0 || h.y_origin > 65535) {
    return _err_bytes("tga: invalid y origin");
  }
  if (h.width < 0 || h.width > 65535) {
    return _err_bytes("tga: invalid width");
  }
  if (h.height < 0 || h.height > 65535) {
    return _err_bytes("tga: invalid height");
  }
  if (h.pixel_depth < 0 || h.pixel_depth > 255) {
    return _err_bytes("tga: unsupported pixel depth");
  }
  if (h.attribute_bits < 0 || h.attribute_bits > 15) {
    return _err_bytes("tga: invalid attribute bits");
  }
  if (h.origin_bits < 0 || h.origin_bits > 3) {
    return _err_bytes("tga: invalid origin bits");
  }
  let out = Vec[UInt8].new();
  out.push(h.id_length as UInt8);
  out.push(h.color_map_type as UInt8);
  out.push(h.image_type as UInt8);
  _p16(&mut out, h.cmap_first);
  _p16(&mut out, h.cmap_length);
  out.push(h.cmap_entry_bits as UInt8);
  _p16(&mut out, h.x_origin);
  _p16(&mut out, h.y_origin);
  _p16(&mut out, h.width);
  _p16(&mut out, h.height);
  out.push(h.pixel_depth as UInt8);
  out.push((h.origin_bits * 16 + h.attribute_bits) as UInt8);
  let check = tga_parse_header(out);
  match check {
    Ok(ok) => { return _ok_bytes(out); },
    Err(e) => { return _err_bytes(e); },
  }
}

// ---------------------------------------------------------------------------
// Footer and version detection
// ---------------------------------------------------------------------------

// True when the buffer carries a TGA 2.0 footer: at least 26 bytes and the
// exact "TRUEVISION-XFILE." signature plus NUL in the last 26 bytes. A false
// result means the buffer is version 1 (no footer exists in TGA 1.0).
pub fn tga_has_footer(data: &Vec[UInt8]) -> Bool {
  let n = data.len();
  if (n < 26) { return false; }
  return _signature_at(data, n - 18);
}

// Detect the file version: 2 when a v2 footer signature is present, else 1.
pub fn tga_detect_version(data: &Vec[UInt8]) -> Int {
  if (tga_has_footer(data)) { return 2; }
  return 1;
}

// Parse the 26-byte footer (extension offset, developer offset, signature).
// A buffer shorter than 26 bytes is "tga: truncated footer"; trailing bytes
// without the exact signature are "tga: missing v2 signature" (version 1
// files have no footer, so this function only applies to v2 buffers -- use
// tga_has_footer or tga_detect_version first). Non-zero offsets must leave
// room for the area size field they point at, otherwise the corresponding
// out-of-bounds error is returned.
pub fn tga_parse_footer(data: &Vec[UInt8]) -> Result[TgaFooter, Str] {
  let n = data.len();
  if (n < 26) { return _err_foot("tga: truncated footer"); }
  let base = n - 26;
  if (!_signature_at(data, base + 8)) {
    return _err_foot("tga: missing v2 signature");
  }
  let ext = _le32(data, base);
  let dev = _le32(data, base + 4);
  if (ext != 0 && ext > n - 2) {
    return _err_foot("tga: extension area out of bounds");
  }
  if (dev != 0 && dev > n - 2) {
    return _err_foot("tga: developer area out of bounds");
  }
  let f = TgaFooter{ extension_offset: ext; developer_offset: dev; };
  return _ok_foot(f);
}

// Build the 26-byte footer. Offsets are unsigned 32-bit byte offsets; 0 means
// the area is absent. Negative or 32-bit-overflowing offsets are rejected.
pub fn tga_build_footer(extension_offset: Int, developer_offset: Int) -> Result[Vec[UInt8], Str] {
  if (extension_offset < 0 || extension_offset > 4294967295) {
    return _err_bytes("tga: invalid extension offset");
  }
  if (developer_offset < 0 || developer_offset > 4294967295) {
    return _err_bytes("tga: invalid developer offset");
  }
  let out = Vec[UInt8].new();
  _p32(&mut out, extension_offset);
  _p32(&mut out, developer_offset);
  _put_signature(&mut out);
  return _ok_bytes(out);
}

// ---------------------------------------------------------------------------
// Full-buffer parse and region accessors
// ---------------------------------------------------------------------------

// Parse and validate a whole TGA buffer. Validates the header fields, then
// walks the declared layout in order: image ID present, color map present,
// uncompressed raster complete (RLE rasters only need to start inside the
// buffer, since their length cannot be known), and -- when a v2 footer is
// detected -- the footer signature and the bounds of the extension/developer
// area offsets. Uncompressed rasters must fit entirely; RLE rasters and
// trailing data (extension areas, developer areas, padding) are left opaque.
pub fn tga_parse(data: &Vec[UInt8]) -> Result[TgaImage, Str] {
  let n = data.len();
  let hp = tga_parse_header(data);
  match hp {
    Ok(h) => {
      if (n < 18 + h.id_length) { return _err_img("tga: truncated image id"); }
      let cmap_off = 18 + h.id_length;
      let cmap_bytes = h.cmap_length * _cmap_entry_bytes(h.cmap_entry_bits);
      if (cmap_off + cmap_bytes > n) { return _err_img("tga: truncated color map"); }
      let data_off = cmap_off + cmap_bytes;
      let raster = tga_data_bytes(&h);
      if (raster < 0) {
        if (data_off >= n) { return _err_img("tga: truncated image data"); }
      } else {
        if (data_off + raster > n) { return _err_img("tga: truncated image data"); }
      }
      var version = 1;
      var ext = 0;
      var dev = 0;
      if (tga_has_footer(data)) {
        version = 2;
        let fp = tga_parse_footer(data);
        match fp {
          Ok(f) => {
            ext = f.extension_offset;
            dev = f.developer_offset;
          },
          Err(e) => { return _err_img(e); },
        }
      }
      let img = TgaImage{
        header: h;
        version: version;
        id_offset: 18;
        cmap_offset: cmap_off;
        cmap_bytes: cmap_bytes;
        data_offset: data_off;
        data_bytes: raster;
        extension_offset: ext;
        developer_offset: dev;
      };
      return _ok_img(img);
    },
    Err(e) => { return _err_img(e); },
  }
}

// Copy the image ID field (bytes 18..18+id_length; empty when id_length is 0).
pub fn tga_id_field(data: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  let n = data.len();
  let hp = tga_parse_header(data);
  match hp {
    Ok(h) => {
      if (n < 18 + h.id_length) { return _err_bytes("tga: truncated image id"); }
      let out = Vec[UInt8].new();
      var i = 0;
      while (i < h.id_length) {
        let b: UInt8 = data[18 + i];
        out.push(b);
        i = i + 1;
      }
      return _ok_bytes(out);
    },
    Err(e) => { return _err_bytes(e); },
  }
}

// Copy the color map data region (cmap_length entries of 2/3/4 bytes each,
// immediately after the image ID field; empty when no color map is present).
pub fn tga_color_map_data(data: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  let n = data.len();
  let hp = tga_parse_header(data);
  match hp {
    Ok(h) => {
      let cmap_off = 18 + h.id_length;
      if (n < cmap_off) { return _err_bytes("tga: truncated image id"); }
      let cmap_bytes = h.cmap_length * _cmap_entry_bytes(h.cmap_entry_bits);
      if (cmap_off + cmap_bytes > n) { return _err_bytes("tga: truncated color map"); }
      let out = Vec[UInt8].new();
      var i = 0;
      while (i < cmap_bytes) {
        let b: UInt8 = data[cmap_off + i];
        out.push(b);
        i = i + 1;
      }
      return _ok_bytes(out);
    },
    Err(e) => { return _err_bytes(e); },
  }
}

// Copy the uncompressed raster region (data_offset..data_offset+data_bytes).
// Image type 0 yields an empty vector; RLE types are rejected with
// "tga: image data length unknown for RLE" because their packet stream has no
// declared length.
pub fn tga_image_data(data: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  let parsed = tga_parse(data);
  match parsed {
    Ok(img) => {
      if (img.data_bytes < 0) {
        return _err_bytes("tga: image data length unknown for RLE");
      }
      let out = Vec[UInt8].new();
      var i = 0;
      while (i < img.data_bytes) {
        let b: UInt8 = data[img.data_offset + i];
        out.push(b);
        i = i + 1;
      }
      return _ok_bytes(out);
    },
    Err(e) => { return _err_bytes(e); },
  }
}
