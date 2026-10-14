// XIOM -- xiom.stb: stb image codecs (vendored stb_image + stb_image_write).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// DESIGN: vendored single-header pattern (the miniaudio method).  Both
// stb headers are vendored unmodified in `vendor/` and one TU
// (`src/stb_all.c`) carries `STB_IMAGE_IMPLEMENTATION` +
// `STB_IMAGE_WRITE_IMPLEMENTATION` plus the probe/HDR bridge; no system
// library, no SDK.
//
// The probe is self-contained: it encodes a 4x4 RGBA gradient to PNG in
// memory, decodes it back and verifies every pixel and the checksum, then
// decodes a hardcoded 1x1 24-bit BMP.  All `unsafe`/`extern "C"` live in
// this single module (G5).
//
// 0.3.0 adds the HDR class surface: every `.hdr`-related public entry of
// the vendored stb_image.h is bound (stbi_is_hdr[_from_memory/_from_file/
// _from_callbacks], stbi_loadf[_from_memory/_from_file/_from_callbacks],
// stbi_hdr_to_ldr_gamma/_scale, stbi_ldr_to_hdr_gamma/_scale) plus the
// 8-bit remap witness stbi_load_from_memory, with owned-buffer interop and
// typed errors.  Native data never crosses as a foreign pointer: the
// bridge copies it into XIOM-owned slots byte-by-byte (B-20/B-24), one
// owned slot per out-param (B-11), no handle casts (B-25), no
// Result[Option[_]] (B-26).
//
// G2 pin (SPEC.md): upstream commit 2c980bb5... + per-header SHA256.

module xiom.stb

use xiom.string;

extern "C" {
  fn stbprobe_version() -> Int32;
  fn stbprobe_run() -> Int32;
  fn stbprobe_png_size() -> Int32;
  fn stbprobe_roundtrip_ok() -> Int32;
  fn stbprobe_checksum() -> Int32;
  fn stbprobe_bmp_ok() -> Int32;

  fn stbprobe_loadf_mem(data: *UInt8, len: Int32, desired: Int32) -> Int32;
  fn stbprobe_loadf_callbacks(data: *UInt8, len: Int32, desired: Int32) -> Int32;
  fn stbprobe_loadf_file(path: *UInt8, desired: Int32) -> Int32;
  fn stbprobe_loadf_from_file(path: *UInt8, desired: Int32) -> Int32;
  fn stbprobe_load8_mem(data: *UInt8, len: Int32, desired: Int32) -> Int32;
  fn stbprobe_img_w() -> Int32;
  fn stbprobe_img_h() -> Int32;
  fn stbprobe_img_comp() -> Int32;
  fn stbprobe_img_file_comp() -> Int32;
  fn stbprobe_img_bytes() -> Int32;
  fn stbprobe_img_copy(dst: *UInt8, cap: Int32) -> Int32;
  fn stbprobe_img_release();
  fn stbprobe_hdr_is_mem(data: *UInt8, len: Int32) -> Int32;
  fn stbprobe_hdr_is_callbacks(data: *UInt8, len: Int32) -> Int32;
  fn stbprobe_hdr_is_file(path: *UInt8) -> Int32;
  fn stbprobe_hdr_is_from_file(path: *UInt8) -> Int32;
  fn stbprobe_hdr_to_ldr_gamma(gamma: Float32);
  fn stbprobe_hdr_to_ldr_scale(scale: Float32);
  fn stbprobe_ldr_to_hdr_gamma(gamma: Float32);
  fn stbprobe_ldr_to_hdr_scale(scale: Float32);
  fn stbprobe_failure_reason() -> *UInt8;
}

// ---- constants (vendored stb_image.h) ------------------------------------

pub const STB_OK: Int = 0;
pub const STB_ERR_LOAD: Int = 1;
pub const STB_ERR_ARG: Int = 2;
pub const STB_ERR_STATE: Int = 3;

pub const STBI_DEFAULT: Int = 0;
pub const STBI_GREY: Int = 1;
pub const STBI_GREY_ALPHA: Int = 2;
pub const STBI_RGB: Int = 3;
pub const STBI_RGB_ALPHA: Int = 4;
pub const STBI_MAX_DIMENSIONS: Int = 16777216;

// ---- types ----------------------------------------------------------------

pub type StbProbe = {
  version: Int;       // STBI_VERSION
  png_size: Int;      // bytes of the in-memory PNG produced by the encoder
  checksum: Int;      // sum of the 64 decoded RGBA bytes (expected 8400)
  roundtrip_ok: Bool; // every decoded pixel equals the encoded source
  bmp_ok: Bool;       // the 1x1 red BMP decoded as 1x1x3 with (255,0,0)
}

/// Typed error for the HDR class surface.  `code` is one of the STB_ERR_*
/// constants; `message` is stbi_failure_reason() text (or an internal
/// diagnostic).
pub type StbError = {
  code: Int;
  message: Str;
}

/// Owned float raster.  `data` is interleaved float32 little-endian
/// (`width * height * channels * 4` bytes); read values exactly with
/// `stb_f32_at` / `stb_pixel_f64`.
pub type StbFloatImage = {
  width: Int;
  height: Int;
  channels: Int;      // channels per pixel in `data` (requested, or native when 0)
  file_channels: Int; // channels detected in the file by the decoder
  data: Vec[UInt8];
}

/// Owned 8-bit raster (`width * height * channels` bytes, interleaved).
pub type StbByteImage = {
  width: Int;
  height: Int;
  channels: Int;
  file_channels: Int;
  data: Vec[UInt8];
}

/// STBI_VERSION of the vendored stb_image.  Complexity: O(1).
pub fn stb_version() -> Int
  requires: true
{
  unsafe { return stbprobe_version() as Int; }
}

/// Run the in-memory codec probe (PNG encode/decode round trip + BMP
/// decode).  Complexity: O(image).
pub fn stb_probe() -> Result[StbProbe, Str]
  requires: true
{
  let rc = unsafe { stbprobe_run() as Int };
  if rc != 0 {
    return Err("stb: probe rc=" + stb_i2s(0 - rc));
  }
  return Ok(StbProbe{
    version: unsafe { stbprobe_version() as Int };
    png_size: unsafe { stbprobe_png_size() as Int };
    checksum: unsafe { stbprobe_checksum() as Int };
    roundtrip_ok: unsafe { stbprobe_roundtrip_ok() as Int } != 0;
    bmp_ok: unsafe { stbprobe_bmp_ok() as Int } != 0;
  });
}

// ---- HDR class surface (0.3.0) -------------------------------------------

/// stbi_is_hdr_from_memory.  Complexity: O(header).
pub fn stb_hdr_is_from_memory(bytes: &Vec[UInt8]) -> Bool
  requires: bytes.len() > 0
{
  let r = unsafe { stbprobe_hdr_is_mem(bytes.as_mut_ptr(), bytes.len() as Int32) as Int };
  return r != 0;
}

/// stbi_is_hdr_from_callbacks, driven by the bridge's memory-cursor
/// callback set.  Complexity: O(header).
pub fn stb_hdr_is_from_callbacks(bytes: &Vec[UInt8]) -> Bool
  requires: bytes.len() > 0
{
  let r = unsafe { stbprobe_hdr_is_callbacks(bytes.as_mut_ptr(), bytes.len() as Int32) as Int };
  return r != 0;
}

/// stbi_is_hdr (filename; false when the file cannot be opened).
/// Complexity: O(header).
pub fn stb_hdr_is(path: Str) -> Bool
  requires: path.len() > 0
{
  let r = unsafe { stbprobe_hdr_is_file(path.c_str()) as Int };
  return r != 0;
}

/// stbi_is_hdr_from_file (bridge opens/closes the FILE*).
/// Complexity: O(header).
pub fn stb_hdr_is_from_file(path: Str) -> Bool
  requires: path.len() > 0
{
  let r = unsafe { stbprobe_hdr_is_from_file(path.c_str()) as Int };
  return r != 0;
}

/// stbi_loadf_from_memory.  `desired` = 0 (native) or 1..4 channels.
/// Complexity: O(pixels).
pub fn stb_loadf_from_memory(bytes: &Vec[UInt8], desired: Int) -> Result[StbFloatImage, StbError]
  requires: bytes.len() > 0
  requires: desired >= 0
  requires: desired <= 4
{
  let rc = unsafe { stbprobe_loadf_mem(bytes.as_mut_ptr(), bytes.len() as Int32, desired as Int32) as Int };
  if rc != STB_OK {
    if rc == -2 { return Err(StbError{ code: STB_ERR_ARG; message: "stb: empty buffer" }); }
    return Err(stb_err_load());
  }
  return stb_take_f32_image();
}

/// stbi_loadf_from_callbacks (bridge memory-cursor callbacks).
/// Complexity: O(pixels).
pub fn stb_loadf_from_callbacks(bytes: &Vec[UInt8], desired: Int) -> Result[StbFloatImage, StbError]
  requires: bytes.len() > 0
  requires: desired >= 0
  requires: desired <= 4
{
  let rc = unsafe { stbprobe_loadf_callbacks(bytes.as_mut_ptr(), bytes.len() as Int32, desired as Int32) as Int };
  if rc != STB_OK {
    if rc == -2 { return Err(StbError{ code: STB_ERR_ARG; message: "stb: empty buffer" }); }
    return Err(stb_err_load());
  }
  return stb_take_f32_image();
}

/// stbi_loadf (filename).  Complexity: O(pixels).
pub fn stb_loadf(path: Str, desired: Int) -> Result[StbFloatImage, StbError]
  requires: path.len() > 0
  requires: desired >= 0
  requires: desired <= 4
{
  let rc = unsafe { stbprobe_loadf_file(path.c_str(), desired as Int32) as Int };
  if rc != STB_OK {
    return Err(stb_err_load());
  }
  return stb_take_f32_image();
}

/// stbi_loadf_from_file (bridge opens/closes the FILE*).
/// Complexity: O(pixels).
pub fn stb_loadf_from_file(path: Str, desired: Int) -> Result[StbFloatImage, StbError]
  requires: path.len() > 0
  requires: desired >= 0
  requires: desired <= 4
{
  let rc = unsafe { stbprobe_loadf_from_file(path.c_str(), desired as Int32) as Int };
  if rc != STB_OK {
    return Err(stb_err_load());
  }
  return stb_take_f32_image();
}

/// stbi_load_from_memory: the 8-bit load path.  For HDR inputs this is the
/// HDR->LDR remap witness -- stbi_hdr_to_ldr_gamma/scale govern the
/// conversion.  Complexity: O(pixels).
pub fn stb_load_rgba8_from_memory(bytes: &Vec[UInt8], desired: Int) -> Result[StbByteImage, StbError]
  requires: bytes.len() > 0
  requires: desired >= 0
  requires: desired <= 4
{
  let rc = unsafe { stbprobe_load8_mem(bytes.as_mut_ptr(), bytes.len() as Int32, desired as Int32) as Int };
  if rc != STB_OK {
    if rc == -2 { return Err(StbError{ code: STB_ERR_ARG; message: "stb: empty buffer" }); }
    return Err(stb_err_load());
  }
  return stb_take_u8_image();
}

/// stbi_hdr_to_ldr_gamma: gamma for the automatic HDR->LDR remap (the
/// library inverts it; default 2.2).  Complexity: O(1).
pub fn stb_hdr_to_ldr_gamma(gamma: Float32)
  requires: gamma > 0.0
{
  unsafe { stbprobe_hdr_to_ldr_gamma(gamma); }
}

/// stbi_hdr_to_ldr_scale: scale for the automatic HDR->LDR remap (the
/// library inverts it; default 1.0).  Complexity: O(1).
pub fn stb_hdr_to_ldr_scale(scale: Float32)
  requires: scale > 0.0
{
  unsafe { stbprobe_hdr_to_ldr_scale(scale); }
}

/// stbi_ldr_to_hdr_gamma: gamma for the automatic LDR->float conversion of
/// stbi_loadf on 8-bit inputs (default 2.2).  Complexity: O(1).
pub fn stb_ldr_to_hdr_gamma(gamma: Float32)
  requires: gamma > 0.0
{
  unsafe { stbprobe_ldr_to_hdr_gamma(gamma); }
}

/// stbi_ldr_to_hdr_scale: scale for the automatic LDR->float conversion of
/// stbi_loadf on 8-bit inputs (default 1.0).  Complexity: O(1).
pub fn stb_ldr_to_hdr_scale(scale: Float32)
  requires: scale > 0.0
{
  unsafe { stbprobe_ldr_to_hdr_scale(scale); }
}

/// stbi_failure_reason() of the most recent failed call ("" when none).
/// Complexity: O(reason).
pub fn stb_failure_reason() -> Str
  requires: true
{
  unsafe {
    let p = stbprobe_failure_reason();
    if (p as Int) != 0 {
      return Str::from_c_str(p);
    }
  }
  return "";
}

/// Byte offset of pixel `index` (row-major, interleaved) in `data`.
/// Complexity: O(1).
pub fn stb_f32_at(img: &StbFloatImage, index: Int) -> Float64
  requires: index >= 0
  requires: index * 4 + 4 <= img.data.len()
{
  return stb_float32_from_bytes(&img.data, index * 4);
}

/// Value of pixel (x, y), channel c, exactly reconstructed as Float64.
/// Complexity: O(1).
pub fn stb_pixel_f64(img: &StbFloatImage, x: Int, y: Int, c: Int) -> Float64
  requires: x >= 0
  requires: y >= 0
  requires: c >= 0
  requires: x < img.width
  requires: y < img.height
  requires: c < img.channels
{
  let index = (y * img.width + x) * img.channels + c;
  return stb_float32_from_bytes(&img.data, index * 4);
}

/// Exact little-endian float32->Float64 reconstruction of the 4 bytes at
/// `base` in `data` (finite IEEE-754 patterns; no bitcast intrinsic is
/// used, so the result is exact on every pin).
/// Complexity: O(1) (<= 150 exact scalings).
pub fn stb_float32_from_bytes(data: &Vec[UInt8], base: Int) -> Float64
  requires: base >= 0
  requires: base + 4 <= data.len()
{
  let b0 = data[base] as Int;
  let b1 = data[base + 1] as Int;
  let b2 = data[base + 2] as Int;
  let b3 = data[base + 3] as Int;
  let bits = b0 | (b1 << 8) | (b2 << 16) | (b3 << 24);
  let sign = (bits >> 31) & 1;
  let exp = (bits >> 23) & 255;
  let mant = bits & 8388607;
  var mag = 0.0;
  if exp == 0 {
    if mant != 0 {
      mag = stb_scale_pow2(mant as Float64, 0 - 149);
    }
  } else {
    if exp != 255 {
      mag = stb_scale_pow2((8388608 + mant) as Float64, exp - 150);
    }
  }
  if sign == 1 { return 0.0 - mag; }
  return mag;
}

// ---- internals -----------------------------------------------------------

/// Zeroed owned buffer built with push-growth (never `Vec.with_len`: the
/// 0.64.4 `Vec.reserve` cap==0 defect under-allocates; B-28).
fn owned_bytes(size: Int) -> Vec[UInt8]
  requires: size > 0
{
  var v: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < size {
    v.push(0 as UInt8);
    i = i + 1;
  }
  return v;
}

fn stb_scale_pow2(m: Float64, e: Int) -> Float64
  requires: true
{
  var s = m;
  var k = e;
  while k > 0 {
    s = s * 2.0;
    k = k - 1;
  }
  while k < 0 {
    s = s * 0.5;
    k = k + 1;
  }
  return s;
}

fn stb_err_load() -> StbError
  requires: true
{
  unsafe {
    let p = stbprobe_failure_reason();
    if (p as Int) != 0 {
      let msg = Str::from_c_str(p);
      if msg.len() > 0 {
        return StbError{ code: STB_ERR_LOAD; message: msg };
      }
    }
  }
  return StbError{ code: STB_ERR_LOAD; message: "stb: load failed" };
}

fn stb_take_f32_image() -> Result[StbFloatImage, StbError]
  requires: true
{
  let w = unsafe { stbprobe_img_w() as Int };
  let h = unsafe { stbprobe_img_h() as Int };
  let comp = unsafe { stbprobe_img_comp() as Int };
  let file_comp = unsafe { stbprobe_img_file_comp() as Int };
  let nbytes = unsafe { stbprobe_img_bytes() as Int };
  if nbytes <= 0 {
    return Err(StbError{ code: STB_ERR_STATE; message: "stb: no cached image" });
  }
  var data = owned_bytes(nbytes);
  var copied: Int = 0;
  unsafe {
    let p = data.as_mut_ptr();
    copied = stbprobe_img_copy(p, nbytes as Int32) as Int;
  }
  unsafe { stbprobe_img_release(); }
  if copied != nbytes {
    return Err(StbError{ code: STB_ERR_STATE; message: "stb: copy-out failed" });
  }
  return Ok(StbFloatImage{
    width: w;
    height: h;
    channels: comp;
    file_channels: file_comp;
    data: data;
  });
}

fn stb_take_u8_image() -> Result[StbByteImage, StbError]
  requires: true
{
  let w = unsafe { stbprobe_img_w() as Int };
  let h = unsafe { stbprobe_img_h() as Int };
  let comp = unsafe { stbprobe_img_comp() as Int };
  let file_comp = unsafe { stbprobe_img_file_comp() as Int };
  let nbytes = unsafe { stbprobe_img_bytes() as Int };
  if nbytes <= 0 {
    return Err(StbError{ code: STB_ERR_STATE; message: "stb: no cached image" });
  }
  var data = owned_bytes(nbytes);
  var copied: Int = 0;
  unsafe {
    let p = data.as_mut_ptr();
    copied = stbprobe_img_copy(p, nbytes as Int32) as Int;
  }
  unsafe { stbprobe_img_release(); }
  if copied != nbytes {
    return Err(StbError{ code: STB_ERR_STATE; message: "stb: copy-out failed" });
  }
  return Ok(StbByteImage{
    width: w;
    height: h;
    channels: comp;
    file_channels: file_comp;
    data: data;
  });
}

fn stb_i2s(n: Int) -> Str
  requires: n >= 0
{
  if n == 0 { return "0"; }
  var val = n;
  var buf = "";
  while val > 0 {
    let digit = val % 10;
    val = val / 10;
    if digit == 0 { buf = "0" + buf; }
    elif digit == 1 { buf = "1" + buf; }
    elif digit == 2 { buf = "2" + buf; }
    elif digit == 3 { buf = "3" + buf; }
    elif digit == 4 { buf = "4" + buf; }
    elif digit == 5 { buf = "5" + buf; }
    elif digit == 6 { buf = "6" + buf; }
    elif digit == 7 { buf = "7" + buf; }
    elif digit == 8 { buf = "8" + buf; }
    elif digit == 9 { buf = "9" + buf; }
  }
  return buf;
}
