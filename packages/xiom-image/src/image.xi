// XIOM -- xiom.image: unified image decode/encode pipeline with format sniffing
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure XIOM, no FFI, no cross-package imports. xiom.image is the shared front
// door for image bytes: it sniffs the container format from magic bytes,
// extracts metadata, converts between packed pixel formats, and decodes or
// encodes a documented proof subset.
//
// Pixel model: RgbaImage is packed RGBA8, one byte per channel, row-major, with
// an explicit stride (stride >= width * 4; only the first width * 4 bytes of
// each row are image data, the rest is unreachable padding). Every producer in
// this module returns stride == width * 4 (compacted). Color math is
// integer-only; grayscale uses the Rec.601 luma weights
// (77R + 150G + 29B + 128) / 256.
//
// Format coverage:
//   * sniff + metadata: BMP, PNG, JPEG, GIF, PPM (P6), TGA (heuristic).
//   * decode: BMP 24/32-bit (bottom-up and top-down) and PPM P6 (maxval 255).
//   * encode: BMP 24-bit, BMP 32-bit, PPM P6.
//   PNG/JPEG/GIF/TGA are recognized and described, but their payloads are not
//   decoded: compressed or palettized rasters are out of the documented subset.
//
// v0.62.2 constraints honored: explicit case dispatch instead of function
// tables, no vectors of structs, Ok/Err construction confined to leaf helpers,
// byte reads widened with (b as Int) & 0xFF, &mut vector arguments written
// &mut at every call site, and every loop either has a strictly increasing
// counter or a hard cap on untrusted sizes.

module xiom.image

// ---------------------------------------------------------------------------
//  Public types
// ---------------------------------------------------------------------------

// Packed RGBA8 image. `pixels` holds `height` rows of `stride` bytes each,
// row-major; pixel (x, y) occupies bytes y*stride + x*4 .. +3 as R, G, B, A.
// width and height are >= 1 and stride >= width * 4.
pub type RgbaImage = {
  width: Int;
  height: Int;
  stride: Int;
  pixels: Vec[UInt8];
}

// Container metadata extracted without decoding the raster. `bits` is the
// on-disk per-pixel or per-sample bit depth (PNG bit depth, GIF 8, PPM 8,
// JPEG 8, TGA pixel depth, BMP 24/32).
pub type ImageMeta = {
  width: Int;
  height: Int;
  format: Int;
  bits: Int;
}

// Decoded 40-byte-DIB BMP header. `height` follows the format: positive means
// bottom-up rows (the standard), negative means top-down storage.
pub type BmpHeader = {
  width: Int;
  height: Int;
  bits: Int;
  data_offset: Int;
  row_bytes: Int;
}

// Strict P6 header: no comments, tokens separated by Netpbm whitespace, one
// whitespace byte after maxval, then the raw RGB raster at `data_offset`.
pub type PpmHeader = {
  width: Int;
  height: Int;
  maxval: Int;
  data_offset: Int;
}

// ---------------------------------------------------------------------------
//  Format and encoder identifiers
// ---------------------------------------------------------------------------

pub const IMG_FMT_UNKNOWN: Int = -1;
pub const IMG_FMT_BMP: Int = 0;
pub const IMG_FMT_PNG: Int = 1;
pub const IMG_FMT_JPEG: Int = 2;
pub const IMG_FMT_GIF: Int = 3;
pub const IMG_FMT_PPM: Int = 4;
pub const IMG_FMT_TGA: Int = 5;

pub const IMG_ENC_BMP24: Int = 0;
pub const IMG_ENC_BMP32: Int = 1;
pub const IMG_ENC_PPM: Int = 2;

// ---------------------------------------------------------------------------
//  Result leaf helpers (v0.62.2: Ok/Err may only be constructed in functions
//  that return a Result directly)
// ---------------------------------------------------------------------------

fn _img_err_image(m: Str) -> Result[RgbaImage, Str] { return Err(m); }
fn _img_ok_image(v: RgbaImage) -> Result[RgbaImage, Str] { return Ok(v); }
fn _img_err_meta(m: Str) -> Result[ImageMeta, Str] { return Err(m); }
fn _img_ok_meta(v: ImageMeta) -> Result[ImageMeta, Str] { return Ok(v); }
fn _img_err_bmp(m: Str) -> Result[BmpHeader, Str] { return Err(m); }
fn _img_ok_bmp(v: BmpHeader) -> Result[BmpHeader, Str] { return Ok(v); }
fn _img_err_ppm(m: Str) -> Result[PpmHeader, Str] { return Err(m); }
fn _img_ok_ppm(v: PpmHeader) -> Result[PpmHeader, Str] { return Ok(v); }
fn _img_err_bytes(m: Str) -> Result[Vec[UInt8], Str] { return Err(m); }
fn _img_ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], Str] { return Ok(v); }

// ---------------------------------------------------------------------------
//  Byte readers and writers
// ---------------------------------------------------------------------------

// Unsigned byte at index i (widened and masked to 0..255).
fn _b(data: &Vec[UInt8], i: Int) -> Int {
  return (data[i] as Int) & 0xFF;
}

fn _le16(data: &Vec[UInt8], off: Int) -> Int {
  let b0 = _b(data, off);
  let b1 = _b(data, off + 1);
  return b0 + b1 * 256;
}

fn _le32(data: &Vec[UInt8], off: Int) -> Int {
  let b0 = _b(data, off);
  let b1 = _b(data, off + 1);
  let b2 = _b(data, off + 2);
  let b3 = _b(data, off + 3);
  return b0 + b1 * 256 + b2 * 65536 + b3 * 16777216;
}

fn _be16(data: &Vec[UInt8], off: Int) -> Int {
  let b0 = _b(data, off);
  let b1 = _b(data, off + 1);
  return b0 * 256 + b1;
}

fn _be32(data: &Vec[UInt8], off: Int) -> Int {
  let b0 = _b(data, off);
  let b1 = _b(data, off + 1);
  let b2 = _b(data, off + 2);
  let b3 = _b(data, off + 3);
  return b0 * 16777216 + b1 * 65536 + b2 * 256 + b3;
}

// Signed 32-bit little-endian value (two's complement).
fn _s32(data: &Vec[UInt8], off: Int) -> Int {
  let v = _le32(data, off);
  if (v >= 2147483648) { return v - 4294967296; }
  return v;
}

fn _p16(out: &mut Vec[UInt8], v: Int) {
  out.push((v % 256) as UInt8);
  out.push(((v / 256) % 256) as UInt8);
}

fn _p32(out: &mut Vec[UInt8], v: Int) {
  out.push((v % 256) as UInt8);
  out.push(((v / 256) % 256) as UInt8);
  out.push(((v / 65536) % 256) as UInt8);
  out.push(((v / 16777216) % 256) as UInt8);
}

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

// Channel value in 0..255.
fn _img_channel_ok(v: Int) -> Bool {
  if (v < 0) { return false; }
  if (v > 255) { return false; }
  return true;
}

// Absolute value of a possibly negative height.
fn _img_abs(v: Int) -> Int {
  if (v < 0) { return 0 - v; }
  return v;
}

// Netpbm whitespace: SPACE, TAB, LF, CR, VT, FF.
fn _img_is_ws(b: Int) -> Bool {
  if (b == 32) { return true; }
  if (b == 9) { return true; }
  if (b == 10) { return true; }
  if (b == 13) { return true; }
  if (b == 11) { return true; }
  if (b == 12) { return true; }
  return false;
}

fn _img_skip_ws(data: &Vec[UInt8], n: Int, start: Int) -> Int {
  var i = start;
  while (i < n) {
    if (!_img_is_ws(_b(data, i))) { return i; }
    i = i + 1;
  }
  return i;
}

// One decimal token: value is -1 when no digit is present; next is the index
// just past the digits. At most 9 digits are consumed (value <= 999999999),
// keeping the scan bounded and the subsequent range checks meaningful.
type _ImgDec = {
  value: Int;
  next: Int;
}

fn _img_take_dec(data: &Vec[UInt8], n: Int, start: Int) -> _ImgDec {
  var i = start;
  var v = 0;
  var digits = 0;
  while (i < n && digits < 9) {
    let c = _b(data, i);
    if (c < 48 || c > 57) { break; }
    v = v * 10 + (c - 48);
    digits = digits + 1;
    i = i + 1;
  }
  if (digits == 0) { return _ImgDec{ value: -1; next: start; }; }
  return _ImgDec{ value: v; next: i; };
}

// ---------------------------------------------------------------------------
//  Format sniffing
// ---------------------------------------------------------------------------

// True when the 8-byte PNG signature starts at byte 0.
fn _img_is_png(data: &Vec[UInt8]) -> Bool {
  let n = data.len();
  if (n < 8) { return false; }
  if (_b(data, 0) != 137) { return false; }
  if (_b(data, 1) != 80) { return false; }
  if (_b(data, 2) != 78) { return false; }
  if (_b(data, 3) != 71) { return false; }
  if (_b(data, 4) != 13) { return false; }
  if (_b(data, 5) != 10) { return false; }
  if (_b(data, 6) != 26) { return false; }
  if (_b(data, 7) != 10) { return false; }
  return true;
}

// True for the JPEG SOI + first marker prefix (FF D8 FF).
fn _img_is_jpeg(data: &Vec[UInt8]) -> Bool {
  let n = data.len();
  if (n < 3) { return false; }
  if (_b(data, 0) != 255) { return false; }
  if (_b(data, 1) != 216) { return false; }
  if (_b(data, 2) != 255) { return false; }
  return true;
}

// True for the GIF87a / GIF89a signature.
fn _img_is_gif(data: &Vec[UInt8]) -> Bool {
  let n = data.len();
  if (n < 6) { return false; }
  if (_b(data, 0) != 71) { return false; }
  if (_b(data, 1) != 73) { return false; }
  if (_b(data, 2) != 70) { return false; }
  if (_b(data, 3) != 56) { return false; }
  let v = _b(data, 4);
  if (v != 55 && v != 57) { return false; }
  if (_b(data, 5) != 97) { return false; }
  return true;
}

// True for the binary Netpbm P6 magic.
fn _img_is_ppm(data: &Vec[UInt8]) -> Bool {
  let n = data.len();
  if (n < 2) { return false; }
  if (_b(data, 0) != 80) { return false; }
  if (_b(data, 1) != 54) { return false; }
  return true;
}

// Image type and color map combination accepted by the TGA header.
fn _img_tga_type_ok(t: Int, cmap: Int) -> Bool {
  if (t == 2 || t == 3 || t == 10 || t == 11) { return cmap == 0; }
  if (t == 1 || t == 9) { return cmap == 1; }
  return false;
}

// Pixel depth accepted for a TGA image type.
fn _img_tga_depth_ok(t: Int, d: Int) -> Bool {
  if (t == 2 || t == 10) {
    if (d == 15 || d == 16 || d == 24 || d == 32) { return true; }
    return false;
  }
  if (d == 8 || d == 16) { return true; }
  return false;
}

// True when the 18 bytes at `off` are the "TRUEVISION-XFILE." footer signature
// plus NUL.
fn _img_tga_sig_at(data: &Vec[UInt8], off: Int) -> Bool {
  if (_b(data, off + 0) != 84) { return false; }
  if (_b(data, off + 1) != 82) { return false; }
  if (_b(data, off + 2) != 85) { return false; }
  if (_b(data, off + 3) != 69) { return false; }
  if (_b(data, off + 4) != 86) { return false; }
  if (_b(data, off + 5) != 73) { return false; }
  if (_b(data, off + 6) != 83) { return false; }
  if (_b(data, off + 7) != 73) { return false; }
  if (_b(data, off + 8) != 79) { return false; }
  if (_b(data, off + 9) != 78) { return false; }
  if (_b(data, off + 10) != 45) { return false; }
  if (_b(data, off + 11) != 88) { return false; }
  if (_b(data, off + 12) != 70) { return false; }
  if (_b(data, off + 13) != 73) { return false; }
  if (_b(data, off + 14) != 76) { return false; }
  if (_b(data, off + 15) != 69) { return false; }
  if (_b(data, off + 16) != 46) { return false; }
  if (_b(data, off + 17) != 0) { return false; }
  return true;
}

// TGA heuristic: the v2 footer signature, or a header whose color map type,
// image type, pixel depth and non-zero dimensions are all mutually consistent.
fn _img_is_tga(data: &Vec[UInt8]) -> Bool {
  let n = data.len();
  if (n >= 26) {
    if (_img_tga_sig_at(data, n - 18)) { return true; }
  }
  if (n < 18) { return false; }
  let cmap = _b(data, 1);
  if (cmap > 1) { return false; }
  let itype = _b(data, 2);
  if (!_img_tga_type_ok(itype, cmap)) { return false; }
  let depth = _b(data, 16);
  if (!_img_tga_depth_ok(itype, depth)) { return false; }
  let w = _le16(data, 12);
  let h = _le16(data, 14);
  if (w == 0 || h == 0) { return false; }
  return true;
}

// Sniff the container format from magic bytes. Returns an IMG_FMT_* code, or
// IMG_FMT_UNKNOWN when no supported signature matches. Formats with exact
// signatures are tested first; TGA is a structural heuristic and comes last.
pub fn image_sniff(data: &Vec[UInt8]) -> Int {
  let n = data.len();
  if (n >= 2 && _b(data, 0) == 66 && _b(data, 1) == 77) { return IMG_FMT_BMP; }
  if (_img_is_png(data)) { return IMG_FMT_PNG; }
  if (_img_is_jpeg(data)) { return IMG_FMT_JPEG; }
  if (_img_is_gif(data)) { return IMG_FMT_GIF; }
  if (_img_is_ppm(data)) { return IMG_FMT_PPM; }
  if (_img_is_tga(data)) { return IMG_FMT_TGA; }
  return IMG_FMT_UNKNOWN;
}

// Human-readable lowercase name for a format code.
pub fn image_format_name(fmt: Int) -> Str {
  if (fmt == IMG_FMT_BMP) { return "bmp"; }
  if (fmt == IMG_FMT_PNG) { return "png"; }
  if (fmt == IMG_FMT_JPEG) { return "jpeg"; }
  if (fmt == IMG_FMT_GIF) { return "gif"; }
  if (fmt == IMG_FMT_PPM) { return "ppm"; }
  if (fmt == IMG_FMT_TGA) { return "tga"; }
  return "unknown";
}

// ---------------------------------------------------------------------------
//  JPEG SOF scan (private)
// ---------------------------------------------------------------------------

type _JpegSize = {
  width: Int;
  height: Int;
}

// Scan JPEG marker segments for the first SOF frame header. Returns width -1
// when no SOF with positive dimensions is found. The scan advances by at least
// one byte per iteration and re-synchronizes on FF, so it always terminates.
fn _img_jpeg_scan(data: &Vec[UInt8]) -> _JpegSize {
  let bad = _JpegSize{ width: -1; height: -1; };
  let n = data.len();
  var pos = 2;
  while (pos + 9 < n) {
    if (_b(data, pos) != 255) {
      pos = pos + 1;
      continue;
    }
    let mk = _b(data, pos + 1);
    if (mk == 255 || mk == 1) {
      pos = pos + 2;
      continue;
    }
    if (mk >= 208 && mk <= 217) {
      pos = pos + 2;
      continue;
    }
    let seglen = _be16(data, pos + 2);
    if (seglen < 2) { return bad; }
    let sof = (mk >= 192 && mk <= 195) || (mk >= 197 && mk <= 199)
           || (mk >= 201 && mk <= 203) || (mk >= 205 && mk <= 207);
    if (sof) {
      let h = _be16(data, pos + 5);
      let w = _be16(data, pos + 7);
      if (w > 0 && h > 0) {
        return _JpegSize{ width: w; height: h; };
      }
      return bad;
    }
    pos = pos + 2 + seglen;
  }
  return bad;
}

// ---------------------------------------------------------------------------
//  BMP header parsing
// ---------------------------------------------------------------------------

// Parse and validate a canonical 14 + 40-byte BMP header. Accepts 24/32-bit
// uncompressed rasters with sane dimensions and verifies that the pixel data
// fits the buffer.
pub fn image_bmp_header(data: &Vec[UInt8]) -> Result[BmpHeader, Str] {
  let n = data.len();
  if (n < 54) { return _img_err_bmp("image: truncated bmp header"); }
  if (_b(data, 0) != 66) { return _img_err_bmp("image: bad bmp magic"); }
  if (_b(data, 1) != 77) { return _img_err_bmp("image: bad bmp magic"); }
  let dib = _le32(data, 14);
  if (dib < 40) { return _img_err_bmp("image: unsupported bmp dib header"); }
  let width = _le32(data, 18);
  if (width <= 0) { return _img_err_bmp("image: invalid bmp width"); }
  if (width > 1000000) { return _img_err_bmp("image: invalid bmp width"); }
  let height = _s32(data, 22);
  if (height == 0) { return _img_err_bmp("image: invalid bmp height"); }
  if (height > 1000000) { return _img_err_bmp("image: invalid bmp height"); }
  if (height < -1000000) { return _img_err_bmp("image: invalid bmp height"); }
  let planes = _le16(data, 26);
  if (planes != 1) { return _img_err_bmp("image: invalid bmp planes"); }
  let bits = _le16(data, 28);
  if (bits != 24 && bits != 32) {
    return _img_err_bmp("image: unsupported bmp bit depth");
  }
  let comp = _le32(data, 30);
  if (comp != 0) { return _img_err_bmp("image: unsupported bmp compression"); }
  let offset = _le32(data, 10);
  if (offset > n) { return _img_err_bmp("image: bmp pixel data out of bounds"); }
  let rb = ((width * bits + 31) / 32) * 4;
  let abs_h = _img_abs(height);
  let need = offset + rb * abs_h;
  if (need > n) { return _img_err_bmp("image: bmp pixel data out of bounds"); }
  let h = BmpHeader{
    width: width;
    height: height;
    bits: bits;
    data_offset: offset;
    row_bytes: rb;
  };
  return _img_ok_bmp(h);
}

// ---------------------------------------------------------------------------
//  PPM P6 header parsing
// ---------------------------------------------------------------------------

// Parse a strict P6 header: magic "P6", whitespace, decimal width, whitespace,
// decimal height, whitespace, decimal maxval in 1..255, one whitespace byte,
// then the raster. Comments are not supported. All dimensions are bounded and
// the raster must fit the buffer.
pub fn image_ppm_header(data: &Vec[UInt8]) -> Result[PpmHeader, Str] {
  let n = data.len();
  if (n < 3) { return _img_err_ppm("image: truncated ppm header"); }
  if (_b(data, 0) != 80) { return _img_err_ppm("image: bad ppm magic"); }
  if (_b(data, 1) != 54) { return _img_err_ppm("image: bad ppm magic"); }
  if (!_img_is_ws(_b(data, 2))) { return _img_err_ppm("image: missing ppm whitespace"); }
  var pos = _img_skip_ws(data, n, 2);
  let wd = _img_take_dec(data, n, pos);
  if (wd.value < 0) { return _img_err_ppm("image: missing ppm width"); }
  pos = wd.next;
  if (pos >= n) { return _img_err_ppm("image: truncated ppm header"); }
  if (!_img_is_ws(_b(data, pos))) { return _img_err_ppm("image: missing ppm whitespace"); }
  pos = _img_skip_ws(data, n, pos);
  let hd = _img_take_dec(data, n, pos);
  if (hd.value < 0) { return _img_err_ppm("image: missing ppm height"); }
  pos = hd.next;
  if (pos >= n) { return _img_err_ppm("image: truncated ppm header"); }
  if (!_img_is_ws(_b(data, pos))) { return _img_err_ppm("image: missing ppm whitespace"); }
  pos = _img_skip_ws(data, n, pos);
  let md = _img_take_dec(data, n, pos);
  if (md.value < 0) { return _img_err_ppm("image: missing ppm maxval"); }
  pos = md.next;
  if (pos >= n) { return _img_err_ppm("image: truncated ppm header"); }
  if (!_img_is_ws(_b(data, pos))) { return _img_err_ppm("image: missing ppm whitespace"); }
  let offset = pos + 1;
  let width = wd.value;
  let height = hd.value;
  let maxval = md.value;
  if (width < 1 || width > 1000000) { return _img_err_ppm("image: invalid ppm width"); }
  if (height < 1 || height > 1000000) { return _img_err_ppm("image: invalid ppm height"); }
  if (maxval < 1 || maxval > 255) { return _img_err_ppm("image: unsupported ppm maxval"); }
  let need = width * height * 3;
  if (offset + need > n) { return _img_err_ppm("image: truncated ppm pixel data"); }
  let ph = PpmHeader{
    width: width;
    height: height;
    maxval: maxval;
    data_offset: offset;
  };
  return _img_ok_ppm(ph);
}

// ---------------------------------------------------------------------------
//  Metadata extraction
// ---------------------------------------------------------------------------

// Extract container metadata without decoding the raster. BMP, PNG, GIF, PPM
// and TGA are all described; JPEG requires a findable SOF segment. Returns
// "image: unknown format" when sniffing fails and a format-specific error when
// the header is malformed.
pub fn image_meta(data: &Vec[UInt8]) -> Result[ImageMeta, Str] {
  let fmt = image_sniff(data);
  let n = data.len();
  if (fmt == IMG_FMT_BMP) {
    let hp = image_bmp_header(data);
    match hp {
      Ok(h) => {
        let m = ImageMeta{ width: h.width; height: h.height; format: IMG_FMT_BMP; bits: h.bits; };
        return _img_ok_meta(m);
      },
      Err(e) => { return _img_err_meta(e); },
    }
  }
  if (fmt == IMG_FMT_PNG) {
    if (n < 25) { return _img_err_meta("image: truncated png header"); }
    if (_b(data, 12) != 73 || _b(data, 13) != 72 || _b(data, 14) != 68 || _b(data, 15) != 82) {
      return _img_err_meta("image: missing png ihdr");
    }
    let w = _be32(data, 16);
    let h = _be32(data, 20);
    if (w <= 0 || h <= 0) { return _img_err_meta("image: invalid png dimensions"); }
    let m = ImageMeta{ width: w; height: h; format: IMG_FMT_PNG; bits: _b(data, 24); };
    return _img_ok_meta(m);
  }
  if (fmt == IMG_FMT_JPEG) {
    let js = _img_jpeg_scan(data);
    if (js.width <= 0 || js.height <= 0) { return _img_err_meta("image: jpeg frame header not found"); }
    let m = ImageMeta{ width: js.width; height: js.height; format: IMG_FMT_JPEG; bits: 8; };
    return _img_ok_meta(m);
  }
  if (fmt == IMG_FMT_GIF) {
    if (n < 10) { return _img_err_meta("image: truncated gif header"); }
    let w = _le16(data, 6);
    let h = _le16(data, 8);
    if (w <= 0 || h <= 0) { return _img_err_meta("image: invalid gif dimensions"); }
    let m = ImageMeta{ width: w; height: h; format: IMG_FMT_GIF; bits: 8; };
    return _img_ok_meta(m);
  }
  if (fmt == IMG_FMT_PPM) {
    let pp = image_ppm_header(data);
    match pp {
      Ok(h) => {
        let m = ImageMeta{ width: h.width; height: h.height; format: IMG_FMT_PPM; bits: 8; };
        return _img_ok_meta(m);
      },
      Err(e) => { return _img_err_meta(e); },
    }
  }
  if (fmt == IMG_FMT_TGA) {
    if (n < 18) { return _img_err_meta("image: truncated tga header"); }
    let w = _le16(data, 12);
    let h = _le16(data, 14);
    if (w <= 0 || h <= 0) { return _img_err_meta("image: invalid tga dimensions"); }
    let m = ImageMeta{ width: w; height: h; format: IMG_FMT_TGA; bits: _b(data, 16); };
    return _img_ok_meta(m);
  }
  return _img_err_meta("image: unknown format");
}

// ---------------------------------------------------------------------------
//  Constructors and accessors
// ---------------------------------------------------------------------------

// Allocate a width x height packed RGBA image filled with one color, stride ==
// width * 4. Errors: "image: invalid width", "image: invalid height",
// "image: channel out of range".
pub fn image_new_rgba(width: Int, height: Int, r: Int, g: Int, b: Int, a: Int) -> Result[RgbaImage, Str] {
  if (width <= 0) { return _img_err_image("image: invalid width"); }
  if (height <= 0) { return _img_err_image("image: invalid height"); }
  if (!_img_channel_ok(r) || !_img_channel_ok(g) || !_img_channel_ok(b) || !_img_channel_ok(a)) {
    return _img_err_image("image: channel out of range");
  }
  let out = Vec[UInt8].new();
  let count = width * height;
  var i = 0;
  while (i < count) {
    out.push(r as UInt8);
    out.push(g as UInt8);
    out.push(b as UInt8);
    out.push(a as UInt8);
    i = i + 1;
  }
  let img = RgbaImage{ width: width; height: height; stride: width * 4; pixels: out; };
  return _img_ok_image(img);
}

// Adopt an existing packed RGBA buffer. Requires width/height >= 1, stride >=
// width * 4 and exactly stride * height bytes. Errors: "image: invalid width",
// "image: invalid height", "image: invalid stride",
// "image: pixel buffer size mismatch".
pub fn image_from_rgba(width: Int, height: Int, stride: Int, pixels: Vec[UInt8]) -> Result[RgbaImage, Str] {
  if (width <= 0) { return _img_err_image("image: invalid width"); }
  if (height <= 0) { return _img_err_image("image: invalid height"); }
  if (stride < width * 4) { return _img_err_image("image: invalid stride"); }
  if (pixels.len() != stride * height) { return _img_err_image("image: pixel buffer size mismatch"); }
  let img = RgbaImage{ width: width; height: height; stride: stride; pixels: pixels; };
  return _img_ok_image(img);
}

pub fn image_width(img: &RgbaImage) -> Int {
  return img.width;
}

pub fn image_height(img: &RgbaImage) -> Int {
  return img.height;
}

pub fn image_stride(img: &RgbaImage) -> Int {
  return img.stride;
}

// Packed 0xRRGGBBAA at (x, y), or -1 when the coordinate is outside the image.
pub fn image_get_rgba(img: &RgbaImage, x: Int, y: Int) -> Int {
  if (x < 0 || y < 0 || x >= img.width || y >= img.height) { return -1; }
  let o = y * img.stride + x * 4;
  let r: Int = (img.pixels[o] as Int) & 0xFF;
  let g: Int = (img.pixels[o + 1] as Int) & 0xFF;
  let b: Int = (img.pixels[o + 2] as Int) & 0xFF;
  let a: Int = (img.pixels[o + 3] as Int) & 0xFF;
  return r * 16777216 + g * 65536 + b * 256 + a;
}

// Write one packed RGBA pixel. Returns false when the coordinate is outside
// the image or any channel is outside 0..255.
pub fn image_set_rgba(img: &mut RgbaImage, x: Int, y: Int, r: Int, g: Int, b: Int, a: Int) -> Bool {
  if (x < 0 || y < 0 || x >= img.width || y >= img.height) { return false; }
  if (!_img_channel_ok(r) || !_img_channel_ok(g) || !_img_channel_ok(b) || !_img_channel_ok(a)) {
    return false;
  }
  let o = y * img.stride + x * 4;
  img.pixels[o] = r as UInt8;
  img.pixels[o + 1] = g as UInt8;
  img.pixels[o + 2] = b as UInt8;
  img.pixels[o + 3] = a as UInt8;
  return true;
}

// Deep copy compacted to stride == width * 4.
pub fn image_copy(img: &RgbaImage) -> RgbaImage {
  let out = Vec[UInt8].new();
  var y = 0;
  while (y < img.height) {
    var x = 0;
    while (x < img.width) {
      let o = y * img.stride + x * 4;
      out.push(img.pixels[o]);
      out.push(img.pixels[o + 1]);
      out.push(img.pixels[o + 2]);
      out.push(img.pixels[o + 3]);
      x = x + 1;
    }
    y = y + 1;
  }
  let res = RgbaImage{ width: img.width; height: img.height; stride: img.width * 4; pixels: out; };
  return res;
}

// ---------------------------------------------------------------------------
//  Pixel format and color space conversion
// ---------------------------------------------------------------------------

// Compact top-down RGB triplets (width * height * 3 bytes); alpha is dropped
// and padding is skipped.
pub fn image_rgba_to_rgb(img: &RgbaImage) -> Vec[UInt8] {
  let out = Vec[UInt8].new();
  var y = 0;
  while (y < img.height) {
    var x = 0;
    while (x < img.width) {
      let o = y * img.stride + x * 4;
      out.push(img.pixels[o]);
      out.push(img.pixels[o + 1]);
      out.push(img.pixels[o + 2]);
      x = x + 1;
    }
    y = y + 1;
  }
  return out;
}

// Expand RGB triplets to packed RGBA with a constant alpha. Errors:
// "image: invalid width", "image: invalid height", "image: channel out of
// range" and "image: pixel buffer size mismatch".
pub fn image_rgb_to_rgba(rgb: &Vec[UInt8], width: Int, height: Int, a: Int) -> Result[RgbaImage, Str] {
  if (width <= 0) { return _img_err_image("image: invalid width"); }
  if (height <= 0) { return _img_err_image("image: invalid height"); }
  if (!_img_channel_ok(a)) { return _img_err_image("image: channel out of range"); }
  if (rgb.len() != width * height * 3) { return _img_err_image("image: pixel buffer size mismatch"); }
  let out = Vec[UInt8].new();
  var y = 0;
  while (y < height) {
    var x = 0;
    while (x < width) {
      let o = (y * width + x) * 3;
      out.push(rgb[o]);
      out.push(rgb[o + 1]);
      out.push(rgb[o + 2]);
      out.push(a as UInt8);
      x = x + 1;
    }
    y = y + 1;
  }
  let img = RgbaImage{ width: width; height: height; stride: width * 4; pixels: out; };
  return _img_ok_image(img);
}

// Compact 8-bit grayscale via Rec.601 luma (77R + 150G + 29B + 128) / 256;
// alpha is ignored.
pub fn image_rgba_to_gray(img: &RgbaImage) -> Vec[UInt8] {
  let out = Vec[UInt8].new();
  var y = 0;
  while (y < img.height) {
    var x = 0;
    while (x < img.width) {
      let o = y * img.stride + x * 4;
      let r: Int = (img.pixels[o] as Int) & 0xFF;
      let g: Int = (img.pixels[o + 1] as Int) & 0xFF;
      let b: Int = (img.pixels[o + 2] as Int) & 0xFF;
      out.push(((77 * r + 150 * g + 29 * b + 128) / 256) as UInt8);
      x = x + 1;
    }
    y = y + 1;
  }
  return out;
}

// Expand 8-bit gray samples to opaque packed RGBA. Errors: "image: invalid
// width", "image: invalid height", "image: pixel buffer size mismatch".
pub fn image_gray_to_rgba(gray: &Vec[UInt8], width: Int, height: Int) -> Result[RgbaImage, Str] {
  if (width <= 0) { return _img_err_image("image: invalid width"); }
  if (height <= 0) { return _img_err_image("image: invalid height"); }
  if (gray.len() != width * height) { return _img_err_image("image: pixel buffer size mismatch"); }
  let out = Vec[UInt8].new();
  var y = 0;
  while (y < height) {
    var x = 0;
    while (x < width) {
      let v: UInt8 = gray[y * width + x];
      out.push(v);
      out.push(v);
      out.push(v);
      out.push(255 as UInt8);
      x = x + 1;
    }
    y = y + 1;
  }
  let img = RgbaImage{ width: width; height: height; stride: width * 4; pixels: out; };
  return _img_ok_image(img);
}

// Compact packed BGRA (channel-swapped RGBA, alpha kept as byte 3).
pub fn image_rgba_to_bgra(img: &RgbaImage) -> Vec[UInt8] {
  let out = Vec[UInt8].new();
  var y = 0;
  while (y < img.height) {
    var x = 0;
    while (x < img.width) {
      let o = y * img.stride + x * 4;
      out.push(img.pixels[o + 2]);
      out.push(img.pixels[o + 1]);
      out.push(img.pixels[o]);
      out.push(img.pixels[o + 3]);
      x = x + 1;
    }
    y = y + 1;
  }
  return out;
}

// Expand packed BGRA back to packed RGBA. Errors: "image: invalid width",
// "image: invalid height", "image: pixel buffer size mismatch".
pub fn image_bgra_to_rgba(bgra: &Vec[UInt8], width: Int, height: Int) -> Result[RgbaImage, Str] {
  if (width <= 0) { return _img_err_image("image: invalid width"); }
  if (height <= 0) { return _img_err_image("image: invalid height"); }
  if (bgra.len() != width * height * 4) { return _img_err_image("image: pixel buffer size mismatch"); }
  let out = Vec[UInt8].new();
  var y = 0;
  while (y < height) {
    var x = 0;
    while (x < width) {
      let o = (y * width + x) * 4;
      out.push(bgra[o + 2]);
      out.push(bgra[o + 1]);
      out.push(bgra[o]);
      out.push(bgra[o + 3]);
      x = x + 1;
    }
    y = y + 1;
  }
  let img = RgbaImage{ width: width; height: height; stride: width * 4; pixels: out; };
  return _img_ok_image(img);
}

// ---------------------------------------------------------------------------
//  Decoders (proof subset: BMP 24/32 and PPM P6)
// ---------------------------------------------------------------------------

// Decode a BMP 24/32-bit uncompressed raster to packed RGBA. Bottom-up storage
// is flipped to top-down; 24-bit pixels get alpha 255; row padding is skipped.
pub fn image_decode_bmp(data: &Vec[UInt8]) -> Result[RgbaImage, Str] {
  let hp = image_bmp_header(data);
  match hp {
    Ok(h) => {
      let w = h.width;
      let abs_h = _img_abs(h.height);
      let out = Vec[UInt8].new();
      var y = 0;
      while (y < abs_h) {
        var row = y;
        if (h.height > 0) { row = abs_h - 1 - y; }
        let base = h.data_offset + row * h.row_bytes;
        var x = 0;
        while (x < w) {
          let p = base + x * (h.bits / 8);
          let bl: Int = (data[p] as Int) & 0xFF;
          let gl: Int = (data[p + 1] as Int) & 0xFF;
          let rl: Int = (data[p + 2] as Int) & 0xFF;
          var al = 255;
          if (h.bits == 32) { al = (data[p + 3] as Int) & 0xFF; }
          out.push(rl as UInt8);
          out.push(gl as UInt8);
          out.push(bl as UInt8);
          out.push(al as UInt8);
          x = x + 1;
        }
        y = y + 1;
      }
      let img = RgbaImage{ width: w; height: abs_h; stride: w * 4; pixels: out; };
      return _img_ok_image(img);
    },
    Err(e) => { return _img_err_image(e); },
  }
}

// Decode a P6 raster with maxval 255 to packed RGBA (alpha 255).
pub fn image_decode_ppm(data: &Vec[UInt8]) -> Result[RgbaImage, Str] {
  let pp = image_ppm_header(data);
  match pp {
    Ok(h) => {
      if (h.maxval != 255) { return _img_err_image("image: unsupported ppm maxval"); }
      let w = h.width;
      let hh = h.height;
      let out = Vec[UInt8].new();
      var y = 0;
      while (y < hh) {
        var x = 0;
        while (x < w) {
          let p = h.data_offset + (y * w + x) * 3;
          out.push(data[p]);
          out.push(data[p + 1]);
          out.push(data[p + 2]);
          out.push(255 as UInt8);
          x = x + 1;
        }
        y = y + 1;
      }
      let img = RgbaImage{ width: w; height: hh; stride: w * 4; pixels: out; };
      return _img_ok_image(img);
    },
    Err(e) => { return _img_err_image(e); },
  }
}

// Unified decode pipeline: sniff the format, then dispatch explicitly to the
// decoder for that case. PNG/JPEG/GIF/TGA are recognized but not decodable in
// this subset; unknown or unsupported input yields
// "image: unsupported format for decode".
pub fn image_decode(data: &Vec[UInt8]) -> Result[RgbaImage, Str] {
  let fmt = image_sniff(data);
  if (fmt == IMG_FMT_BMP) { return image_decode_bmp(data); }
  if (fmt == IMG_FMT_PPM) { return image_decode_ppm(data); }
  return _img_err_image("image: unsupported format for decode");
}

// ---------------------------------------------------------------------------
//  Encoders (proof subset: BMP 24, BMP 32, PPM P6)
// ---------------------------------------------------------------------------

// Build a canonical BMP with the given bit depth: 14 + 40-byte header,
// bottom-up rows, BGR(A) pixels, 4-byte padded rows. Shared by the 24 and 32
// bit public builders.
fn _img_build_bmp(img: &RgbaImage, bits: Int) -> Result[Vec[UInt8], Str] {
  let w = img.width;
  let h = img.height;
  if (w <= 0) { return _img_err_bytes("image: invalid width"); }
  if (h <= 0) { return _img_err_bytes("image: invalid height"); }
  if (img.stride < w * 4) { return _img_err_bytes("image: invalid stride"); }
  if (img.pixels.len() != img.stride * h) { return _img_err_bytes("image: pixel buffer size mismatch"); }
  let rb = ((w * bits + 31) / 32) * 4;
  let data_size = rb * h;
  let total = 54 + data_size;
  if (total > 4294967295) { return _img_err_bytes("image: image too large"); }
  var out = Vec[UInt8].new();
  out.push(66 as UInt8);
  out.push(77 as UInt8);
  _p32(&mut out, total);
  _p16(&mut out, 0);
  _p16(&mut out, 0);
  _p32(&mut out, 54);
  _p32(&mut out, 40);
  _p32(&mut out, w);
  _p32(&mut out, h);
  _p16(&mut out, 1);
  _p16(&mut out, bits);
  _p32(&mut out, 0);
  _p32(&mut out, data_size);
  _p32(&mut out, 2835);
  _p32(&mut out, 2835);
  _p32(&mut out, 0);
  _p32(&mut out, 0);
  var yrow = 0;
  while (yrow < h) {
    let src = h - 1 - yrow;
    var x = 0;
    while (x < w) {
      let base = src * img.stride + x * 4;
      let r: Int = (img.pixels[base] as Int) & 0xFF;
      let g: Int = (img.pixels[base + 1] as Int) & 0xFF;
      let b: Int = (img.pixels[base + 2] as Int) & 0xFF;
      out.push(b as UInt8);
      out.push(g as UInt8);
      out.push(r as UInt8);
      if (bits == 32) {
        let a: Int = (img.pixels[base + 3] as Int) & 0xFF;
        out.push(a as UInt8);
      }
      x = x + 1;
    }
    let pad = rb - w * (bits / 8);
    var p = 0;
    while (p < pad) {
      out.push(0 as UInt8);
      p = p + 1;
    }
    yrow = yrow + 1;
  }
  return _img_ok_bytes(out);
}

// Encode as a 24-bit BMP (alpha dropped).
pub fn image_encode_bmp24(img: &RgbaImage) -> Result[Vec[UInt8], Str] {
  return _img_build_bmp(img, 24);
}

// Encode as a 32-bit BMP (alpha preserved as byte 3 of BGRA).
pub fn image_encode_bmp32(img: &RgbaImage) -> Result[Vec[UInt8], Str] {
  return _img_build_bmp(img, 32);
}

// Encode as a canonical binary P6 PPM: "P6\n<w> <h>\n255\n" then raw RGB in
// top-down scan order, no padding.
pub fn image_encode_ppm(img: &RgbaImage) -> Result[Vec[UInt8], Str] {
  let w = img.width;
  let h = img.height;
  if (w <= 0) { return _img_err_bytes("image: invalid width"); }
  if (h <= 0) { return _img_err_bytes("image: invalid height"); }
  if (img.stride < w * 4) { return _img_err_bytes("image: invalid stride"); }
  if (img.pixels.len() != img.stride * h) { return _img_err_bytes("image: pixel buffer size mismatch"); }
  var out = Vec[UInt8].new();
  out.push(80 as UInt8);
  out.push(54 as UInt8);
  out.push(10 as UInt8);
  _put_decimal(&mut out, w);
  out.push(32 as UInt8);
  _put_decimal(&mut out, h);
  out.push(10 as UInt8);
  out.push(50 as UInt8);
  out.push(53 as UInt8);
  out.push(53 as UInt8);
  out.push(10 as UInt8);
  var y = 0;
  while (y < h) {
    var x = 0;
    while (x < w) {
      let o = y * img.stride + x * 4;
      out.push(img.pixels[o]);
      out.push(img.pixels[o + 1]);
      out.push(img.pixels[o + 2]);
      x = x + 1;
    }
    y = y + 1;
  }
  return _img_ok_bytes(out);
}

// Unified encode pipeline: explicit case dispatch on an IMG_ENC_* target.
// Unknown targets yield "image: unsupported format for encode".
pub fn image_encode(img: &RgbaImage, target: Int) -> Result[Vec[UInt8], Str] {
  if (target == IMG_ENC_BMP24) { return image_encode_bmp24(img); }
  if (target == IMG_ENC_BMP32) { return image_encode_bmp32(img); }
  if (target == IMG_ENC_PPM) { return image_encode_ppm(img); }
  return _img_err_bytes("image: unsupported format for encode");
}
