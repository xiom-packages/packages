// XIOM -- xiom.exr: OpenEXR reader over the vendored tinyexr C API.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// DESIGN: tinyexr (v3.2.0, BSD-3) is vendored in `vendor/tinyexr/` as one
// header (+ exr_reader.hh + streamreader.hh + deps/miniz) with ONE
// mechanical include rewrite (`<miniz.h>` -> `"miniz.h"`; see
// tools/vendor_exr.py + PROVENANCE.md).  The bridge
// (`src/exr_bridge.cpp`, one C++ TU) drives tinyexr's own extern "C" API
// and owns a single load session + save buffer; XIOM never sees a foreign
// pointer.  Data crosses as owned planar float32 little-endian buffers
// copied byte-wise into XIOM-owned slots (B-20/B-24), one owned slot per
// out-param (B-11), no handle casts (B-25), no Result[Option[_]] (B-26),
// no `ffi.write_*_at` (B-27), no `Vec.with_len` (B-28).
//
// Declared surface: read from memory/file into owned float channel buffers
// plus metadata queries (dimensions, channel count/names, declared pixel
// types, compression, data window) with typed errors; the save path uses
// tinyexr's own writer to build EXR blobs (fixtures/round trips).

module xiom.exr

use xiom.string;

extern "C" {
  fn exrprobe_is_exr_mem(data: *UInt8, size: Int32) -> Int32;
  fn exrprobe_is_exr_file(path: *UInt8) -> Int32;
  fn exrprobe_load_mem(data: *UInt8, size: Int32) -> Int32;
  fn exrprobe_load_file(path: *UInt8) -> Int32;
  fn exrprobe_width() -> Int32;
  fn exrprobe_height() -> Int32;
  fn exrprobe_channels() -> Int32;
  fn exrprobe_compression() -> Int32;
  fn exrprobe_window_min_x() -> Int32;
  fn exrprobe_window_min_y() -> Int32;
  fn exrprobe_window_max_x() -> Int32;
  fn exrprobe_window_max_y() -> Int32;
  fn exrprobe_channel_pixel_type(index: Int32) -> Int32;
  fn exrprobe_channel_name_len(index: Int32) -> Int32;
  fn exrprobe_channel_name_copy(index: Int32, dst: *UInt8, cap: Int32) -> Int32;
  fn exrprobe_image_bytes() -> Int32;
  fn exrprobe_image_copy(dst: *UInt8, cap: Int32) -> Int32;
  fn exrprobe_save(data: *UInt8, data_len: Int32, width: Int32, height: Int32, channels: Int32, fp16: Int32, names: *UInt8, names_len: Int32) -> Int32;
  fn exrprobe_saved_size() -> Int32;
  fn exrprobe_saved_copy(dst: *UInt8, cap: Int32) -> Int32;
  fn exrprobe_error_code() -> Int32;
  fn exrprobe_error_message() -> *UInt8;
  fn exrprobe_release();
}

// ---- constants (vendored tinyexr.h) --------------------------------------

pub const EXR_OK: Int = 0;
pub const EXR_ERROR_INVALID_MAGIC_NUMBER: Int = -1;
pub const EXR_ERROR_INVALID_EXR_VERSION: Int = -2;
pub const EXR_ERROR_INVALID_ARGUMENT: Int = -3;
pub const EXR_ERROR_INVALID_DATA: Int = -4;
pub const EXR_ERROR_INVALID_FILE: Int = -5;
pub const EXR_ERROR_INVALID_PARAMETER: Int = -6;
pub const EXR_ERROR_CANT_OPEN_FILE: Int = -7;
pub const EXR_ERROR_UNSUPPORTED_FORMAT: Int = -8;
pub const EXR_ERROR_INVALID_HEADER: Int = -9;
pub const EXR_ERROR_UNSUPPORTED_FEATURE: Int = -10;
pub const EXR_ERROR_CANT_WRITE_FILE: Int = -11;
pub const EXR_ERROR_SERIALIZATION_FAILED: Int = -12;
pub const EXR_ERROR_LAYER_NOT_FOUND: Int = -13;
pub const EXR_ERROR_DATA_TOO_LARGE: Int = -14;

pub const EXR_PIXELTYPE_UINT: Int = 0;
pub const EXR_PIXELTYPE_HALF: Int = 1;
pub const EXR_PIXELTYPE_FLOAT: Int = 2;

pub const EXR_COMPRESSION_NONE: Int = 0;
pub const EXR_COMPRESSION_RLE: Int = 1;
pub const EXR_COMPRESSION_ZIPS: Int = 2;
pub const EXR_COMPRESSION_ZIP: Int = 3;
pub const EXR_COMPRESSION_PIZ: Int = 4;
pub const EXR_COMPRESSION_PXR24: Int = 5;
pub const EXR_COMPRESSION_B44: Int = 6;
pub const EXR_COMPRESSION_B44A: Int = 7;
pub const EXR_COMPRESSION_DWAA: Int = 8;
pub const EXR_COMPRESSION_DWAB: Int = 9;

pub const EXR_TILE_ONE_LEVEL: Int = 0;
pub const EXR_TILE_MIPMAP_LEVELS: Int = 1;
pub const EXR_TILE_RIPMAP_LEVELS: Int = 2;
pub const EXR_TILE_ROUND_DOWN: Int = 0;
pub const EXR_TILE_ROUND_UP: Int = 1;

pub const EXR_MAX_HEADER_ATTRIBUTES: Int = 1024;
pub const EXR_MAX_CUSTOM_ATTRIBUTES: Int = 128;

pub const EXR_MAX_CHANNELS: Int = 32;

// ---- types ----------------------------------------------------------------

/// Typed error: `code` is a tinyexr error code (EXR_ERROR_*), `message` the
/// bridge/tinyexr diagnostic text.
pub type ExrError = {
  code: Int;
  message: Str;
}

/// Owned EXR image: `data` is planar float32 little-endian; channel `c`
/// occupies `data[c * width * height * 4 ..]` (row-major, y increasing).
/// `pixel_types` holds the DECLARED per-channel types from the file.
/// `window_*` is the data window (min inclusive, max inclusive) and
/// `compression` the file's compression type (EXR_COMPRESSION_*).
pub type ExrImage = {
  width: Int;
  height: Int;
  channels: Int;
  compression: Int;
  window_min_x: Int;
  window_min_y: Int;
  window_max_x: Int;
  window_max_y: Int;
  names: Vec[Str];
  pixel_types: Vec[Int];
  data: Vec<UInt8];
}

/// Save specification: planar float32 data (channel-major), one name per
/// channel; fp16=true writes HALF channels through tinyexr's writer.
pub type ExrSaveSpec = {
  width: Int;
  height: Int;
  fp16: Bool;
  names: Vec[Str];
  data: Vec[UInt8];
}

// ---- detection ------------------------------------------------------------

/// IsEXRFromMemory: true when `bytes` starts a parsable EXR header.
/// Complexity: O(header).
pub fn exr_is_exr_from_memory(bytes: &Vec[UInt8]) -> Bool
  requires: bytes.len() > 0
{
  let r = unsafe { exrprobe_is_exr_mem(bytes.as_mut_ptr(), bytes.len() as Int32) as Int };
  return r != 0;
}

/// IsEXR: true when the file is an EXR (false for missing/unreadable).
/// Complexity: O(header).
pub fn exr_is_exr_from_file(path: Str) -> Bool
  requires: path.len() > 0
{
  let r = unsafe { exrprobe_is_exr_file(path.c_str()) as Int };
  return r != 0;
}

// ---- read -----------------------------------------------------------------

/// Load a single-part EXR from memory into owned planar float channels
/// (HALF channels are converted to FLOAT by tinyexr; UINT channels are
/// widened by the bridge).  Complexity: O(image).
pub fn exr_load_from_memory(bytes: &Vec[UInt8]) -> Result[ExrImage, ExrError]
  requires: bytes.len() > 0
{
  let rc = unsafe { exrprobe_load_mem(bytes.as_mut_ptr(), bytes.len() as Int32) as Int };
  if rc != EXR_OK {
    return Err(exr_take_error(rc));
  }
  return exr_take_image();
}

/// Load a single-part EXR from a file path.  Complexity: O(image).
pub fn exr_load_from_file(path: Str) -> Result[ExrImage, ExrError]
  requires: path.len() > 0
{
  let rc = unsafe { exrprobe_load_file(path.c_str()) as Int };
  if rc != EXR_OK {
    return Err(exr_take_error(rc));
  }
  return exr_take_image();
}

// ---- save (tinyexr's own writer; fixtures / round trips) ------------------

/// Serialize planar float32 channels to an EXR blob (uncompressed; the
/// writer converts to HALF when spec.fp16).  Complexity: O(image).
pub fn exr_save_to_memory(spec: &ExrSaveSpec) -> Result[Vec[UInt8], ExrError]
  requires: spec.width > 0
  requires: spec.height > 0
  requires: spec.names.len() > 0
{
  let nch = spec.names.len();
  if nch > EXR_MAX_CHANNELS {
    return Err(ExrError{ code: EXR_ERROR_INVALID_ARGUMENT; message: "exr: too many channels (max 32)" });
  }
  let want = spec.width * spec.height * nch * 4;
  if spec.data.len() != want {
    return Err(ExrError{ code: EXR_ERROR_INVALID_ARGUMENT; message: "exr: planar data size mismatch" });
  }
  var names_blob = Vec[UInt8].new();
  var i = 0;
  while i < nch {
    exr_push_text(&mut names_blob, spec.names[i]);
    names_blob.push(0 as UInt8);
    i = i + 1;
  }
  var fp = 0;
  if spec.fp16 { fp = 1; }
  let rc = unsafe {
    exrprobe_save(spec.data.as_mut_ptr(), spec.data.len() as Int32,
      spec.width as Int32, spec.height as Int32, nch as Int32, fp as Int32,
      names_blob.as_mut_ptr(), names_blob.len() as Int32) as Int
  };
  if rc != EXR_OK {
    return Err(exr_take_error(rc));
  }
  let size = unsafe { exrprobe_saved_size() as Int };
  if size <= 0 {
    return Err(ExrError{ code: EXR_ERROR_INVALID_DATA; message: "exr: empty save buffer" });
  }
  var out = exr_owned_bytes(size);
  var copied: Int = 0;
  unsafe {
    let p = out.as_mut_ptr();
    copied = exrprobe_saved_copy(p, size as Int32) as Int;
  }
  unsafe { exrprobe_release(); }
  if copied != size {
    return Err(ExrError{ code: EXR_ERROR_INVALID_DATA; message: "exr: save copy-out failed" });
  }
  return Ok(out);
}

// ---- pure helpers ---------------------------------------------------------

/// Index of the channel named `name`, or -1.  Comparison via
/// string.str_compare (Str == on Vec elements is a pointer compare).
/// Complexity: O(channels).
pub fn exr_channel_index(img: &ExrImage, name: Str) -> Int
  requires: true
{
  var i = 0;
  while i < img.names.len() {
    if string.str_compare(img.names[i], name) == 0 { return i; }
    i = i + 1;
  }
  return -1;
}

/// Value of pixel (x, y) in channel `channel`, exactly reconstructed as
/// Float64.  Complexity: O(1).
pub fn exr_pixel_f64(img: &ExrImage, channel: Int, x: Int, y: Int) -> Float64
  requires: channel >= 0
  requires: x >= 0
  requires: y >= 0
  requires: channel < img.channels
  requires: x < img.width
  requires: y < img.height
{
  let plane = img.width * img.height * 4;
  let index = y * img.width + x;
  return exr_float32_from_bytes(&img.data, channel * plane + index * 4);
}

/// Exact little-endian float32->Float64 reconstruction of the 4 bytes at
/// `base` (finite IEEE-754 patterns; no bitcast intrinsic).
/// Complexity: O(1) (<= 150 exact scalings).
pub fn exr_float32_from_bytes(data: &Vec[UInt8], base: Int) -> Float64
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
      mag = exr_scale_pow2(mant as Float64, 0 - 149);
    }
  } else {
    if exp != 255 {
      mag = exr_scale_pow2((8388608 + mant) as Float64, exp - 150);
    }
  }
  if sign == 1 { return 0.0 - mag; }
  return mag;
}

/// Stable name for a tinyexr error code (literals only: B-02/B-03 keep the
/// resolver away from const chains; the EXR_ERROR_* consts are pinned
/// against these literals by the suite).
pub fn exr_error_name(code: Int) -> Str
  requires: true
{
  if code == 0 { return "SUCCESS"; }
  if code == -1 { return "INVALID_MAGIC_NUMBER"; }
  if code == -2 { return "INVALID_EXR_VERSION"; }
  if code == -3 { return "INVALID_ARGUMENT"; }
  if code == -4 { return "INVALID_DATA"; }
  if code == -5 { return "INVALID_FILE"; }
  if code == -6 { return "INVALID_PARAMETER"; }
  if code == -7 { return "CANT_OPEN_FILE"; }
  if code == -8 { return "UNSUPPORTED_FORMAT"; }
  if code == -9 { return "INVALID_HEADER"; }
  if code == -10 { return "UNSUPPORTED_FEATURE"; }
  if code == -11 { return "CANT_WRITE_FILE"; }
  if code == -12 { return "SERIALIZATION_FAILED"; }
  if code == -13 { return "LAYER_NOT_FOUND"; }
  if code == -14 { return "DATA_TOO_LARGE"; }
  return "UNKNOWN";
}

// ---- internals ------------------------------------------------------------

/// Zeroed owned buffer built with push-growth (B-28: never `Vec.with_len`).
fn exr_owned_bytes(size: Int) -> Vec[UInt8]
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

fn exr_push_text(v: &mut Vec[UInt8], s: Str)
  requires: true
{
  var i = 0;
  let n = string.byte_count(s);
  while i < n {
    v.push(string.byte_at(s, i));
    i = i + 1;
  }
}

fn exr_scale_pow2(m: Float64, e: Int) -> Float64
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

fn exr_take_error(rc: Int) -> ExrError
  requires: true
{
  unsafe {
    let p = exrprobe_error_message();
    if (p as Int) != 0 {
      let msg = Str::from_c_str(p);
      if msg.len() > 0 {
        return ExrError{ code: rc; message: exr_error_name(rc) + ": " + msg };
      }
    }
  }
  return ExrError{ code: rc; message: "exr: " + exr_error_name(rc) };
}

fn exr_take_image() -> Result[ExrImage, ExrError]
  requires: true
{
  let w = unsafe { exrprobe_width() as Int };
  let h = unsafe { exrprobe_height() as Int };
  let nch = unsafe { exrprobe_channels() as Int };
  let total = unsafe { exrprobe_image_bytes() as Int };
  let compression = unsafe { exrprobe_compression() as Int };
  let wminx = unsafe { exrprobe_window_min_x() as Int };
  let wminy = unsafe { exrprobe_window_min_y() as Int };
  let wmaxx = unsafe { exrprobe_window_max_x() as Int };
  let wmaxy = unsafe { exrprobe_window_max_y() as Int };
  if w <= 0 || h <= 0 || nch <= 0 || total <= 0 {
    unsafe { exrprobe_release(); }
    return Err(ExrError{ code: EXR_ERROR_INVALID_DATA; message: "exr: empty session" });
  }
  var names = Vec[Str].new();
  var types: Vec[Int] = Vec[Int].new();
  var c = 0;
  while c < nch {
    let nl = unsafe { exrprobe_channel_name_len(c as Int32) as Int };
    if nl < 0 {
      unsafe { exrprobe_release(); }
      return Err(ExrError{ code: EXR_ERROR_INVALID_ARGUMENT; message: "exr: channel name query failed" });
    }
    var name_buf = exr_owned_bytes(nl + 1);
    var copied: Int = 0;
    unsafe {
      let p = name_buf.as_mut_ptr();
      copied = exrprobe_channel_name_copy(c as Int32, p, (nl + 1) as Int32) as Int;
    }
    if copied < 0 {
      unsafe { exrprobe_release(); }
      return Err(ExrError{ code: EXR_ERROR_INVALID_ARGUMENT; message: "exr: channel name copy failed" });
    }
    var name = "";
    unsafe {
      name = Str::from_c_str(name_buf.as_mut_ptr());
    }
    names.push(name);
    let pt = unsafe { exrprobe_channel_pixel_type(c as Int32) as Int };
    types.push(pt);
    c = c + 1;
  }
  var data = exr_owned_bytes(total);
  var copied_all: Int = 0;
  unsafe {
    let p = data.as_mut_ptr();
    copied_all = exrprobe_image_copy(p, total as Int32) as Int;
  }
  unsafe { exrprobe_release(); }
  if copied_all != total {
    return Err(ExrError{ code: EXR_ERROR_INVALID_DATA; message: "exr: pixel copy-out failed" });
  }
  return Ok(ExrImage{
    width: w;
    height: h;
    channels: nch;
    compression: compression;
    window_min_x: wminx;
    window_min_y: wminy;
    window_max_x: wmaxx;
    window_max_y: wmaxy;
    names: names;
    pixel_types: types;
    data: data;
  });
}
