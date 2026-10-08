// XIOM -- xiom.webp: WebP (RIFF) container parser
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure XIOM, no FFI. This module implements the container layer of the WebP
// format (RIFF container, WebP Container Specification) over flat
// Vec[UInt8] buffers. It parses structure only: no VP8 or VP8L pixel decode,
// no alpha-plane decode, no ICC/EXIF/XMP interpretation.
//
//   header := "RIFF" LE32(file size) "WEBP", file size = total bytes - 8
//   chunk  := fourcc[4] LE32(size) payload[size] pad[1 when size is odd]
//
// Every chunk is padded to an even byte boundary; the padding byte MUST be 0.
// The RIFF size field must describe the buffer exactly (no trailing data).
//
// Chunks recognized and validated structurally:
//
//   VP8   lossy bitstream: 3-byte frame tag (key-frame bit, 3-bit version,
//         show-frame bit, 19-bit first-partition size), start code
//         0x9D 0x01 0x2A, 14-bit width and height (2-bit scale each)
//   VP8L  lossless bitstream: 0x2F signature, then LE32 with 14-bit width-1,
//         14-bit height-1, alpha hint and 3-bit version (must be 0)
//   VP8X  extended header: flags byte (ICC/alpha/EXIF/XMP/animation plus
//         reserved bits), 3 reserved bytes, 24-bit canvas width-1/height-1
//   ALPH  alpha sub-chunk: opaque payload (method byte not interpreted)
//   ANIM  background color (BGRA byte order) and loop count
//   ANMF  frame x/y (units of 2 pixels), width-1/height-1, duration,
//         blend/dispose bits, then nested padded sub-chunks
//   ICCP  color profile: opaque presence and size
//   EXIF  Exif metadata: opaque presence and size
//   XMP   XMP metadata: opaque presence and size
//
// Container kinds:
//   0 simple    no VP8X, exactly one top-level VP8/VP8L image chunk
//   1 extended  VP8X present, animation flag clear, one VP8/VP8L image
//   2 animated  VP8X animation flag set, ANIM plus one or more ANMF frames
//
// Unknown fourcc chunks are kept opaque and bounded: the fourcc must be
// printable ASCII, the declared size must fit the enclosing chunk stream,
// and the chunk is recorded in the chunk index but never interpreted. A zero
// byte can therefore never reach a Str (sb_to_str hands out NUL-terminated
// strings), and no unknown payload is ever copied.
//
// Parsed results use parallel Vec fields (no Vec[StructType]): the top-level
// chunk index (chunk_fourcc/chunk_offset/chunk_size/chunk_data_offset/
// chunk_padding/chunk_kind) and the per-frame index (frame_x/frame_y/
// frame_width/frame_height/frame_duration/frame_blend/frame_dispose/
// frame_offset/frame_size/frame_format/frame_data_offset/frame_data_size/
// frame_has_alpha/frame_nested_count/frame_unknown_count).
//
// v0.61.3 notes that shaped this module:
//   * Ok/Err construction is confined to the tiny leaf helpers below.
//   * every byte read from a Vec[UInt8] is widened with
//     `(data[i] as Int) & 0xFF` (0x9D and 0x2F are read this way).
//   * every Vec[Int]/Vec[Str] element read is bound to a typed local.
//   * no Vec[Float64], no lambdas, no methods, no table-driven dispatch,
//     no `==` on a Str read from a Vec[Str].
//   * RIFF sizes are little-endian (PNG was big-endian; nothing is copied).
// See SPEC.md for the byte layout tables, the validation order, the full
// error catalog and the test matrix.

module xiom.webp

use xiom.convert;
use xiom.string.builder;

// --------------------------------------------------
//  Constants
// --------------------------------------------------

/// Fixed WebP file header size: "RIFF" + LE32 + "WEBP".
pub fn webp_header_size() -> Int {
  return 12;
}

/// Size of a RIFF chunk header: fourcc[4] + LE32 size.
pub fn webp_chunk_header_size() -> Int {
  return 8;
}

/// Exact VP8X payload size: flags 1 + reserved 3 + canvas 3 + canvas 3.
pub fn webp_vp8x_size() -> Int {
  return 10;
}

/// Exact ANIM payload size: background color 4 + loop count 2.
pub fn webp_anim_size() -> Int {
  return 6;
}

/// Size of the ANMF frame header that precedes the nested frame data.
pub fn webp_anmf_header_size() -> Int {
  return 16;
}

/// Largest canvas dimension expressible in VP8X: 24-bit width-1 + 1.
pub fn webp_max_canvas_dimension() -> Int {
  return 16777216;
}

/// Largest image dimension expressible in VP8/VP8L: 14-bit width + 1.
pub fn webp_max_dimension_14() -> Int {
  return 16384;
}

/// Container kind code for a simple file (no VP8X).
pub fn webp_kind_simple() -> Int {
  return 0;
}

/// Container kind code for a static extended file (VP8X, no animation).
pub fn webp_kind_extended() -> Int {
  return 1;
}

/// Container kind code for an animated file (VP8X animation flag).
pub fn webp_kind_animated() -> Int {
  return 2;
}

/// Chunk kind code for an unknown/other fourcc.
pub fn webp_chunk_other() -> Int {
  return 0;
}

/// Chunk kind code for a VP8 (lossy) bitstream chunk.
pub fn webp_chunk_vp8() -> Int {
  return 1;
}

/// Chunk kind code for a VP8L (lossless) bitstream chunk.
pub fn webp_chunk_vp8l() -> Int {
  return 2;
}

/// Chunk kind code for a VP8X extended header chunk.
pub fn webp_chunk_vp8x() -> Int {
  return 3;
}

/// Chunk kind code for an ALPH alpha sub-chunk.
pub fn webp_chunk_alph() -> Int {
  return 4;
}

/// Chunk kind code for an ANIM animation parameters chunk.
pub fn webp_chunk_anim() -> Int {
  return 5;
}

/// Chunk kind code for an ANMF animation frame chunk.
pub fn webp_chunk_anmf() -> Int {
  return 6;
}

/// Chunk kind code for an ICCP color profile chunk.
pub fn webp_chunk_iccp() -> Int {
  return 7;
}

/// Chunk kind code for an EXIF metadata chunk.
pub fn webp_chunk_exif() -> Int {
  return 8;
}

/// Chunk kind code for an XMP metadata chunk.
pub fn webp_chunk_xmp() -> Int {
  return 9;
}

/// Image format code for "no image chunk seen".
pub fn webp_format_none() -> Int {
  return 0;
}

/// Image format code for a VP8 (lossy) bitstream.
pub fn webp_format_vp8() -> Int {
  return 1;
}

/// Image format code for a VP8L (lossless) bitstream.
pub fn webp_format_vp8l() -> Int {
  return 2;
}

/// VP8X flags byte mask for the ICC profile bit (I, 0x20).
pub fn webp_mask_icc() -> Int {
  return 32;
}

/// VP8X flags byte mask for the alpha bit (L, 0x10).
pub fn webp_mask_alpha() -> Int {
  return 16;
}

/// VP8X flags byte mask for the Exif metadata bit (E, 0x08).
pub fn webp_mask_exif() -> Int {
  return 8;
}

/// VP8X flags byte mask for the XMP metadata bit (X, 0x04).
pub fn webp_mask_xmp() -> Int {
  return 4;
}

/// VP8X flags byte mask for the animation bit (A, 0x02).
pub fn webp_mask_animation() -> Int {
  return 2;
}

/// VP8X flags byte mask of every reserved bit (0xC0 plus 0x01).
pub fn webp_mask_reserved() -> Int {
  return 193;
}

/// ANMF flags byte mask of the six reserved bits (0xFC).
pub fn webp_mask_anmf_reserved() -> Int {
  return 252;
}

// --------------------------------------------------
//  Public types
// --------------------------------------------------

/// Parsed WebP container.
///
/// `kind` is 0 simple, 1 extended or 2 animated. `size` is the buffer length
/// in bytes and `riff_size` the declared RIFF size field (size - 8).
///
/// VP8X state: `has_vp8x` is 0 or 1, `vp8x_offset` the absolute chunk offset,
/// `flags` the raw flags byte and `flag_icc`/`flag_alpha`/`flag_exif`/
/// `flag_xmp`/`flag_animation` its decoded bits (0 or 1). `canvas_width` and
/// `canvas_height` are the canvas dimensions: VP8X values in extended and
/// animated files, the image dimensions in simple files. Absent fields use
/// -1 as sentinel.
///
/// Image state: `has_image` is 0 or 1 for the top-level image chunk of simple
/// and static extended files (0 in animated files, where the bitstreams live
/// inside ANMF frames). `image_format` is 0 none, 1 VP8, 2 VP8L;
/// `image_offset` is the absolute fourcc offset, `image_data_offset` the
/// absolute offset of the first payload byte and `image_size` the declared
/// payload size; `image_width`/`image_height` are the decoded 14-bit
/// dimensions. `vp8_version`, `vp8_show_frame` and `vp8_first_part_size` are
/// the VP8 frame-tag fields; `vp8l_alpha` and `vp8l_version` the VP8L header
/// bits.
///
/// Metadata state: `has_alph`/`has_iccp`/`has_exif`/`has_xmp` are chunk
/// presence flags (not the VP8X bits) with `alph_offset`/`iccp_offset`/
/// `exif_offset`/`xmp_offset` chunk offsets and `*_size` payload sizes.
/// ICCP/EXIF/XMP payloads are never interpreted.
///
/// Animation state: `has_anim`, `anim_offset`, `anim_background` (raw LE32 in
/// BGRA byte order), `anim_loop_count` (0 = infinite).
///
/// Chunk index: one entry per top-level chunk in stream order. `chunk_fourcc`
/// is the printable-ASCII fourcc, `chunk_offset` the absolute offset of the
/// fourcc, `chunk_size` the declared payload size, `chunk_data_offset` the
/// absolute offset of the first payload byte, `chunk_padding` 1 when a
/// padding byte follows and `chunk_kind` the kind code above.
///
/// Frame index: one entry per ANMF chunk in stream order. `frame_x`/`frame_y`
/// are pixel coordinates (the stored units multiplied by 2), `frame_width`/
/// `frame_height` the frame size, `frame_duration` milliseconds,
/// `frame_blend`/`frame_dispose` the two flag bits, `frame_offset`/`frame_size`
/// locate the ANMF payload, `frame_format` is 0 none, 1 VP8 or 2 VP8L,
/// `frame_data_offset`/`frame_data_size` locate the nested bitstream payload,
/// `frame_has_alpha` is 1 when the frame carries an ALPH sub-chunk and
/// `frame_nested_count`/`frame_unknown_count` count the nested sub-chunks.
pub type WebpImage = {
  kind: Int;
  size: Int;
  riff_size: Int;
  has_vp8x: Int;
  vp8x_offset: Int;
  flags: Int;
  flag_icc: Int;
  flag_alpha: Int;
  flag_exif: Int;
  flag_xmp: Int;
  flag_animation: Int;
  canvas_width: Int;
  canvas_height: Int;
  has_image: Int;
  image_format: Int;
  image_offset: Int;
  image_data_offset: Int;
  image_size: Int;
  image_width: Int;
  image_height: Int;
  vp8_version: Int;
  vp8_show_frame: Int;
  vp8_first_part_size: Int;
  vp8l_alpha: Int;
  vp8l_version: Int;
  has_alph: Int;
  alph_offset: Int;
  alph_size: Int;
  has_iccp: Int;
  iccp_offset: Int;
  iccp_size: Int;
  has_exif: Int;
  exif_offset: Int;
  exif_size: Int;
  has_xmp: Int;
  xmp_offset: Int;
  xmp_size: Int;
  has_anim: Int;
  anim_offset: Int;
  anim_background: Int;
  anim_loop_count: Int;
  chunk_fourcc: Vec[Str];
  chunk_offset: Vec[Int];
  chunk_size: Vec[Int];
  chunk_data_offset: Vec[Int];
  chunk_padding: Vec[Int];
  chunk_kind: Vec[Int];
  frame_x: Vec[Int];
  frame_y: Vec[Int];
  frame_width: Vec[Int];
  frame_height: Vec[Int];
  frame_duration: Vec[Int];
  frame_blend: Vec[Int];
  frame_dispose: Vec[Int];
  frame_offset: Vec[Int];
  frame_size: Vec[Int];
  frame_format: Vec[Int];
  frame_data_offset: Vec[Int];
  frame_data_size: Vec[Int];
  frame_has_alpha: Vec[Int];
  frame_nested_count: Vec[Int];
  frame_unknown_count: Vec[Int];
}

// --------------------------------------------------
//  Result leaf helpers (v0.61.3: Ok/Err may only be constructed in fns that
//  return a Result directly, so every fallible public fn returns through
//  these).
// --------------------------------------------------

// Ok(v) for Result[WebpImage, Str].
fn _ok_img(v: WebpImage) -> Result[WebpImage, Str] {
  return Ok(v);
}

// Err(m) for Result[WebpImage, Str].
fn _err_img(m: Str) -> Result[WebpImage, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Byte readers, message helpers and fourcc predicates
// --------------------------------------------------

// Unsigned byte at index i (widened and masked to 0..255).
fn _b(data: &Vec[UInt8], i: Int) -> Int {
  return (data[i] as Int) & 0xFF;
}

// Little-endian unsigned 16-bit value at `off`.
fn _le16(data: &Vec[UInt8], off: Int) -> Int {
  return _b(data, off) + _b(data, off + 1) * 256;
}

// Little-endian unsigned 24-bit value at `off`.
fn _le24(data: &Vec[UInt8], off: Int) -> Int {
  return _b(data, off) + _b(data, off + 1) * 256 + _b(data, off + 2) * 65536;
}

// Little-endian unsigned 32-bit value at `off` (0..4294967295).
fn _le32(data: &Vec[UInt8], off: Int) -> Int {
  return _b(data, off) + _b(data, off + 1) * 256 + _b(data, off + 2) * 65536 + _b(data, off + 3) * 16777216;
}

// Append one message with an absolute byte offset: "<base> at <off>".
fn _at(base: Str, off: Int) -> Str {
  return base + " at " + convert.int_to_string(off);
}

// True when data[off, off+4) is four printable ASCII bytes (0x20..0x7E).
// Guarantees a fourcc Str built from the range is NUL-free.
fn _fourcc_ok(data: &Vec[UInt8], off: Int) -> Bool {
  var i = 0;
  while (i < 4) {
    let b = _b(data, off + i);
    if (b < 32 || b > 126) { return false; }
    i = i + 1;
  }
  return true;
}

// True when data[off, off+4) is exactly the four bytes a, b, c, d.
fn _fourcc_is(data: &Vec[UInt8], off: Int, a: Int, b: Int, c: Int, d: Int) -> Bool {
  if (_b(data, off) != a) { return false; }
  if (_b(data, off + 1) != b) { return false; }
  if (_b(data, off + 2) != c) { return false; }
  if (_b(data, off + 3) != d) { return false; }
  return true;
}

// Chunk kind code for the fourcc at `off` (webp_chunk_* codes).
fn _chunk_kind(data: &Vec[UInt8], off: Int) -> Int {
  if (_fourcc_is(data, off, 86, 80, 56, 32)) { return 1; }
  if (_fourcc_is(data, off, 86, 80, 56, 76)) { return 2; }
  if (_fourcc_is(data, off, 86, 80, 56, 88)) { return 3; }
  if (_fourcc_is(data, off, 65, 76, 80, 72)) { return 4; }
  if (_fourcc_is(data, off, 65, 78, 73, 77)) { return 5; }
  if (_fourcc_is(data, off, 65, 78, 77, 70)) { return 6; }
  if (_fourcc_is(data, off, 73, 67, 67, 80)) { return 7; }
  if (_fourcc_is(data, off, 69, 88, 73, 70)) { return 8; }
  if (_fourcc_is(data, off, 88, 77, 80, 32)) { return 9; }
  return 0;
}

// Build a Str from the fourcc bytes of data[start, end). Callers guarantee
// the range is four printable ASCII bytes, so the NUL-terminated result
// preserves every byte.
fn _str_range(data: &Vec[UInt8], start: Int, end: Int) -> Str {
  var sb = Vec[UInt8].new();
  var i = start;
  while (i < end) {
    builder.sb_push_byte(&mut sb, data[i]);
    i = i + 1;
  }
  return builder.sb_to_str(&sb);
}

// True when data starts with "RIFF" at 0 and "WEBP" at 8 (12 bytes).
fn _magic_ok(data: &Vec[UInt8], n: Int) -> Bool {
  if (n < 12) { return false; }
  if (_b(data, 0) != 82) { return false; }
  if (_b(data, 1) != 73) { return false; }
  if (_b(data, 2) != 70) { return false; }
  if (_b(data, 3) != 70) { return false; }
  if (_b(data, 8) != 87) { return false; }
  if (_b(data, 9) != 69) { return false; }
  if (_b(data, 10) != 66) { return false; }
  if (_b(data, 11) != 80) { return false; }
  return true;
}

// "" when the RIFF header is well formed, otherwise the documented error.
// Order: length below 4, "RIFF", length below 12, "WEBP", exact file size.
fn _header_error(data: &Vec[UInt8], n: Int) -> Str {
  if (n < 4) { return "webp: truncated header at 0"; }
  if (_b(data, 0) != 82) { return _at("webp: bad magic", 0); }
  if (_b(data, 1) != 73) { return _at("webp: bad magic", 1); }
  if (_b(data, 2) != 70) { return _at("webp: bad magic", 2); }
  if (_b(data, 3) != 70) { return _at("webp: bad magic", 3); }
  if (n < 12) { return "webp: truncated header at 0"; }
  if (_b(data, 8) != 87) { return _at("webp: bad magic", 8); }
  if (_b(data, 9) != 69) { return _at("webp: bad magic", 9); }
  if (_b(data, 10) != 66) { return _at("webp: bad magic", 10); }
  if (_b(data, 11) != 80) { return _at("webp: bad magic", 11); }
  if (_le32(data, 4) + 8 != n) { return "webp: riff size mismatch at 4"; }
  return "";
}

// --------------------------------------------------
//  VP8 (lossy bitstream) structure
// --------------------------------------------------

// "" when the VP8 payload data[d, d+size) has a valid uncompressed header,
// otherwise the documented error. Validates: minimum length 10, start code,
// key-frame bit, version 0..3, first partition fits, non-zero 14-bit
// dimensions. The 2-bit scale fields and show-frame bit are recorded by the
// caller but not rejected.
fn _vp8_error(data: &Vec[UInt8], d: Int, size: Int) -> Str {
  if (size < 10) { return _at("webp: invalid VP8 length", d); }
  if (_b(data, d + 3) != 157 || _b(data, d + 4) != 1 || _b(data, d + 5) != 42) {
    return _at("webp: invalid VP8 start code", d + 3);
  }
  let ftag = _b(data, d) + _b(data, d + 1) * 256 + _b(data, d + 2) * 65536;
  if (ftag % 2 != 0) { return _at("webp: invalid VP8 frame tag", d); }
  if ((ftag / 2) % 8 > 3) { return _at("webp: invalid VP8 version", d); }
  if (10 + ftag / 32 > size) { return _at("webp: invalid VP8 partition size", d); }
  if (_le16(data, d + 6) % 16384 == 0) { return _at("webp: invalid VP8 dimensions", d + 6); }
  if (_le16(data, d + 8) % 16384 == 0) { return _at("webp: invalid VP8 dimensions", d + 6); }
  return "";
}

// VP8 frame-tag version bits (0..7; parse accepts 0..3).
fn _vp8_version(data: &Vec[UInt8], d: Int) -> Int {
  let ftag = _b(data, d) + _b(data, d + 1) * 256 + _b(data, d + 2) * 65536;
  return (ftag / 2) % 8;
}

// VP8 frame-tag show-frame bit.
fn _vp8_show_frame(data: &Vec[UInt8], d: Int) -> Int {
  let ftag = _b(data, d) + _b(data, d + 1) * 256 + _b(data, d + 2) * 65536;
  return (ftag / 16) % 2;
}

// VP8 frame-tag 19-bit first-partition size.
fn _vp8_first_part_size(data: &Vec[UInt8], d: Int) -> Int {
  let ftag = _b(data, d) + _b(data, d + 1) * 256 + _b(data, d + 2) * 65536;
  return ftag / 32;
}

// VP8 14-bit width from the two bytes at d+6.
fn _vp8_width(data: &Vec[UInt8], d: Int) -> Int {
  return _le16(data, d + 6) % 16384;
}

// VP8 14-bit height from the two bytes at d+8.
fn _vp8_height(data: &Vec[UInt8], d: Int) -> Int {
  return _le16(data, d + 8) % 16384;
}

// --------------------------------------------------
//  VP8L (lossless bitstream) structure
// --------------------------------------------------

// "" when the VP8L payload data[d, d+size) has a valid header, otherwise the
// documented error. Validates: minimum length 5, 0x2F signature, version 0.
fn _vp8l_error(data: &Vec[UInt8], d: Int, size: Int) -> Str {
  if (size < 5) { return _at("webp: invalid VP8L length", d); }
  if (_b(data, d) != 47) { return _at("webp: invalid VP8L signature", d); }
  let bits = _le32(data, d + 1);
  if ((bits / 536870912) % 8 != 0) { return _at("webp: invalid VP8L version", d); }
  return "";
}

// VP8L 14-bit width: (width - 1) + 1.
fn _vp8l_width(data: &Vec[UInt8], d: Int) -> Int {
  return (_le32(data, d + 1) % 16384) + 1;
}

// VP8L 14-bit height: (height - 1) + 1.
fn _vp8l_height(data: &Vec[UInt8], d: Int) -> Int {
  return ((_le32(data, d + 1) / 16384) % 16384) + 1;
}

// VP8L alpha-is-used hint bit (bit 28).
fn _vp8l_alpha(data: &Vec[UInt8], d: Int) -> Int {
  return (_le32(data, d + 1) / 268435456) % 2;
}

// VP8L 3-bit version (bits 29..31; parse accepts only 0).
fn _vp8l_version(data: &Vec[UInt8], d: Int) -> Int {
  return (_le32(data, d + 1) / 536870912) % 8;
}

// --------------------------------------------------
//  Index record helpers
// --------------------------------------------------

// Append one top-level chunk-index record; all six vectors always receive
// exactly one entry, so parallel-Vec drift is structurally impossible.
fn _push_chunk(a: &mut WebpImage, fourcc: Str, off: Int, size: Int, data_off: Int, pad: Int, kind: Int) {
  a.chunk_fourcc.push(fourcc);
  a.chunk_offset.push(off);
  a.chunk_size.push(size);
  a.chunk_data_offset.push(data_off);
  a.chunk_padding.push(pad);
  a.chunk_kind.push(kind);
}

// Append one frame-index record; all sixteen vectors always receive exactly
// one entry, so parallel-Vec drift is structurally impossible.
fn _push_frame(a: &mut WebpImage, x: Int, y: Int, w: Int, h: Int, dur: Int, blend: Int, dispose: Int, off: Int, size: Int, fmt: Int, data_off: Int, data_size: Int, alpha: Int, nested: Int, unknown: Int) {
  a.frame_x.push(x);
  a.frame_y.push(y);
  a.frame_width.push(w);
  a.frame_height.push(h);
  a.frame_duration.push(dur);
  a.frame_blend.push(blend);
  a.frame_dispose.push(dispose);
  a.frame_offset.push(off);
  a.frame_size.push(size);
  a.frame_format.push(fmt);
  a.frame_data_offset.push(data_off);
  a.frame_data_size.push(data_size);
  a.frame_has_alpha.push(alpha);
  a.frame_nested_count.push(nested);
  a.frame_unknown_count.push(unknown);
}

// --------------------------------------------------
//  Per-chunk validation helpers: each returns "" on success (and mutates the
//  accumulator), or the documented error message.
// --------------------------------------------------

// VP8X: duplicate, first-chunk, exact length, reserved bits/bytes, canvas.
fn _parse_vp8x(a: &mut WebpImage, data: &Vec[UInt8], p: Int, d: Int, size: Int) -> Str {
  if (a.has_vp8x != 0) { return _at("webp: duplicate VP8X", p); }
  if (a.chunk_fourcc.len() > 0) { return _at("webp: VP8X not first", p); }
  if (size != 10) { return _at("webp: invalid VP8X length", p); }
  let flags = _b(data, d);
  if ((flags & 193) != 0) { return _at("webp: reserved VP8X bits", d); }
  if (_b(data, d + 1) != 0 || _b(data, d + 2) != 0 || _b(data, d + 3) != 0) {
    return _at("webp: reserved VP8X bytes", d + 1);
  }
  let cw = _le24(data, d + 4) + 1;
  let ch = _le24(data, d + 7) + 1;
  if (cw * ch > 4294967295) { return _at("webp: canvas too large", p); }
  a.has_vp8x = 1;
  a.vp8x_offset = p;
  a.flags = flags;
  a.flag_icc = (flags / 32) % 2;
  a.flag_alpha = (flags / 16) % 2;
  a.flag_exif = (flags / 8) % 2;
  a.flag_xmp = (flags / 4) % 2;
  a.flag_animation = (flags / 2) % 2;
  a.canvas_width = cw;
  a.canvas_height = ch;
  return "";
}

// VP8 bitstream chunk: single top-level image, structural VP8 header.
fn _parse_vp8_chunk(a: &mut WebpImage, data: &Vec[UInt8], p: Int, d: Int, size: Int) -> Str {
  if (a.has_image != 0) { return _at("webp: multiple image chunks", p); }
  let e = _vp8_error(data, d, size);
  if (e.len() > 0) { return e; }
  a.has_image = 1;
  a.image_format = 1;
  a.image_offset = p;
  a.image_data_offset = d;
  a.image_size = size;
  a.image_width = _vp8_width(data, d);
  a.image_height = _vp8_height(data, d);
  a.vp8_version = _vp8_version(data, d);
  a.vp8_show_frame = _vp8_show_frame(data, d);
  a.vp8_first_part_size = _vp8_first_part_size(data, d);
  return "";
}

// VP8L bitstream chunk: single top-level image, structural VP8L header.
fn _parse_vp8l_chunk(a: &mut WebpImage, data: &Vec[UInt8], p: Int, d: Int, size: Int) -> Str {
  if (a.has_image != 0) { return _at("webp: multiple image chunks", p); }
  let e = _vp8l_error(data, d, size);
  if (e.len() > 0) { return e; }
  a.has_image = 1;
  a.image_format = 2;
  a.image_offset = p;
  a.image_data_offset = d;
  a.image_size = size;
  a.image_width = _vp8l_width(data, d);
  a.image_height = _vp8l_height(data, d);
  a.vp8l_alpha = _vp8l_alpha(data, d);
  a.vp8l_version = _vp8l_version(data, d);
  return "";
}

// ALPH: duplicate, ordering before the image, minimum one method byte.
fn _parse_alph(a: &mut WebpImage, data: &Vec[UInt8], p: Int, d: Int, size: Int) -> Str {
  if (a.has_alph != 0) { return _at("webp: duplicate ALPH", p); }
  if (a.has_image != 0) { return _at("webp: ALPH after image", p); }
  if (size < 1) { return _at("webp: invalid ALPH length", p); }
  a.has_alph = 1;
  a.alph_offset = p;
  a.alph_size = size;
  return "";
}

// ANIM: duplicate, ordering before frames, exact length, payload fields.
fn _parse_anim(a: &mut WebpImage, data: &Vec[UInt8], p: Int, d: Int, size: Int) -> Str {
  if (a.has_anim != 0) { return _at("webp: duplicate ANIM", p); }
  if (a.frame_x.len() > 0) { return _at("webp: ANIM after ANMF", p); }
  if (size != 6) { return _at("webp: invalid ANIM length", p); }
  a.has_anim = 1;
  a.anim_offset = p;
  a.anim_background = _le32(data, d);
  a.anim_loop_count = _le16(data, d + 4);
  return "";
}

// ANMF: minimum length, reserved bits, frame bounds, nested padded sub-chunk
// stream (ALPH then VP8/VP8L, then unknown chunks), exactly one bitstream.
fn _parse_anmf(a: &mut WebpImage, data: &Vec[UInt8], p: Int, d: Int, size: Int) -> Str {
  if (size < 16) { return _at("webp: invalid ANMF length", p); }
  let fbyte = _b(data, d + 15);
  if ((fbyte & 252) != 0) { return _at("webp: reserved ANMF bits", d + 15); }
  let fx = _le24(data, d) * 2;
  let fy = _le24(data, d + 3) * 2;
  let fw = _le24(data, d + 6) + 1;
  let fh = _le24(data, d + 9) + 1;
  let dur = _le24(data, d + 12);
  let blend = (fbyte / 2) % 2;
  let dispose = fbyte % 2;
  if (a.has_vp8x != 0) {
    if (fx + fw > a.canvas_width) { return _at("webp: frame outside canvas", p); }
    if (fy + fh > a.canvas_height) { return _at("webp: frame outside canvas", p); }
  }
  var fmt = 0;
  var data_off = 0;
  var data_size = 0;
  var has_alpha = 0;
  var nested = 0;
  var unknown = 0;
  var pos = d + 16;
  let end = d + size;
  while (pos < end) {
    if (pos + 8 > end) { return _at("webp: truncated frame chunk", pos); }
    let fsize = _le32(data, pos + 4);
    if (pos + 8 + fsize > end) { return _at("webp: truncated frame chunk", pos); }
    if (!_fourcc_ok(data, pos)) { return _at("webp: invalid FourCC", pos); }
    let fd = pos + 8;
    if (fsize % 2 != 0) {
      if (fd + fsize + 1 > end) { return _at("webp: truncated padding", fd + fsize); }
      if (_b(data, fd + fsize) != 0) { return _at("webp: invalid padding byte", fd + fsize); }
    }
    let kind = _chunk_kind(data, pos);
    if (kind == 4) {
      if (has_alpha != 0) { return _at("webp: duplicate frame alpha", pos); }
      if (fmt != 0) { return _at("webp: frame alpha after image", pos); }
      if (fsize < 1) { return _at("webp: invalid ALPH length", pos); }
      has_alpha = 1;
    } elif (kind == 1) {
      if (fmt != 0) { return _at("webp: multiple frame image chunks", pos); }
      let e = _vp8_error(data, fd, fsize);
      if (e.len() > 0) { return e; }
      fmt = 1;
      data_off = fd;
      data_size = fsize;
    } elif (kind == 2) {
      if (fmt != 0) { return _at("webp: multiple frame image chunks", pos); }
      let e = _vp8l_error(data, fd, fsize);
      if (e.len() > 0) { return e; }
      fmt = 2;
      data_off = fd;
      data_size = fsize;
    } else {
      unknown = unknown + 1;
    }
    nested = nested + 1;
    pos = fd + fsize + (fsize % 2);
  }
  if (fmt == 0) { return _at("webp: ANMF missing image data", p); }
  _push_frame(a, fx, fy, fw, fh, dur, blend, dispose, p, size, fmt, data_off, data_size, has_alpha, nested, unknown);
  return "";
}

// ICCP: duplicate, ordering before image data.
fn _parse_iccp(a: &mut WebpImage, data: &Vec[UInt8], p: Int, d: Int, size: Int) -> Str {
  if (a.has_iccp != 0) { return _at("webp: duplicate ICCP", p); }
  if (a.has_image != 0) { return _at("webp: ICCP after image data", p); }
  a.has_iccp = 1;
  a.iccp_offset = p;
  a.iccp_size = size;
  return "";
}

// EXIF: duplicate (payload opaque).
fn _parse_exif(a: &mut WebpImage, data: &Vec[UInt8], p: Int, d: Int, size: Int) -> Str {
  if (a.has_exif != 0) { return _at("webp: duplicate EXIF", p); }
  a.has_exif = 1;
  a.exif_offset = p;
  a.exif_size = size;
  return "";
}

// XMP: duplicate (payload opaque).
fn _parse_xmp(a: &mut WebpImage, data: &Vec[UInt8], p: Int, d: Int, size: Int) -> Str {
  if (a.has_xmp != 0) { return _at("webp: duplicate XMP", p); }
  a.has_xmp = 1;
  a.xmp_offset = p;
  a.xmp_size = size;
  return "";
}

// Dispatch one top-level chunk by kind code; unknown chunks are opaque.
fn _dispatch(a: &mut WebpImage, data: &Vec[UInt8], p: Int, d: Int, size: Int, kind: Int) -> Str {
  if (kind == 3) { return _parse_vp8x(a, data, p, d, size); }
  if (kind == 1) { return _parse_vp8_chunk(a, data, p, d, size); }
  if (kind == 2) { return _parse_vp8l_chunk(a, data, p, d, size); }
  if (kind == 4) { return _parse_alph(a, data, p, d, size); }
  if (kind == 5) { return _parse_anim(a, data, p, d, size); }
  if (kind == 6) { return _parse_anmf(a, data, p, d, size); }
  if (kind == 7) { return _parse_iccp(a, data, p, d, size); }
  if (kind == 8) { return _parse_exif(a, data, p, d, size); }
  if (kind == 9) { return _parse_xmp(a, data, p, d, size); }
  return "";
}

// Walk the top-level chunk stream from offset 12 to the end of the buffer.
// Returns "" on success, otherwise the documented error. Every chunk's
// declared size must fit, the fourcc must be printable ASCII, an odd size
// must be followed by a zero padding byte, and the chunk is appended to the
// index after its validation succeeds.
fn _scan_chunks(a: &mut WebpImage, data: &Vec[UInt8], n: Int) -> Str {
  var pos = 12;
  while (pos < n) {
    if (pos + 8 > n) { return _at("webp: truncated chunk", pos); }
    let size = _le32(data, pos + 4);
    if (pos + 8 + size > n) { return _at("webp: truncated chunk", pos); }
    if (!_fourcc_ok(data, pos)) { return _at("webp: invalid FourCC", pos); }
    let d = pos + 8;
    var pad = 0;
    if (size % 2 != 0) {
      pad = 1;
      if (d + size + 1 > n) { return _at("webp: truncated padding", d + size); }
      if (_b(data, d + size) != 0) { return _at("webp: invalid padding byte", d + size); }
    }
    let kind = _chunk_kind(data, pos);
    let e = _dispatch(&mut a, data, pos, d, size, kind);
    if (e.len() > 0) { return e; }
    _push_chunk(a, _str_range(data, pos, pos + 4), pos, size, d, pad, kind);
    pos = d + size + pad;
  }
  return "";
}

// --------------------------------------------------
//  Post-walk consistency
// --------------------------------------------------

// "" when the collected state is a coherent container, otherwise the
// documented error. Simple files must have exactly one image chunk and no
// VP8X-only chunks; extended files must match their VP8X flag bits; animated
// files must have ANIM, at least one frame and no top-level image.
fn _post_error(a: &WebpImage) -> Str {
  if (a.has_vp8x == 0) {
    if (a.has_alph != 0) { return _at("webp: metadata chunk without VP8X", a.alph_offset); }
    if (a.has_iccp != 0) { return _at("webp: metadata chunk without VP8X", a.iccp_offset); }
    if (a.has_exif != 0) { return _at("webp: metadata chunk without VP8X", a.exif_offset); }
    if (a.has_xmp != 0) { return _at("webp: metadata chunk without VP8X", a.xmp_offset); }
    if (a.has_anim != 0) { return _at("webp: metadata chunk without VP8X", a.anim_offset); }
    if (a.frame_x.len() > 0) {
      let fo: Int = a.frame_offset[0];
      return _at("webp: metadata chunk without VP8X", fo);
    }
    if (a.has_image == 0) { return "webp: missing image data at 12"; }
    return "";
  }
  if (a.flag_animation != 0) {
    if (a.has_anim == 0) { return _at("webp: animation flag without ANIM", a.vp8x_offset); }
    if (a.frame_x.len() == 0) { return _at("webp: animation without frames", a.anim_offset); }
    if (a.has_image != 0) { return _at("webp: image chunk in animation", a.image_offset); }
    if (a.has_alph != 0) { return _at("webp: ALPH chunk in animation", a.alph_offset); }
    return "";
  }
  if (a.has_anim != 0) { return _at("webp: animation chunk without flag", a.anim_offset); }
  if (a.frame_x.len() > 0) {
    let fo: Int = a.frame_offset[0];
    return _at("webp: animation frame without flag", fo);
  }
  if (a.has_image == 0) { return "webp: missing image data at 12"; }
  if (a.has_iccp != 0 && a.flag_icc == 0) { return _at("webp: ICCP without ICC flag", a.iccp_offset); }
  if (a.has_iccp == 0 && a.flag_icc != 0) { return _at("webp: ICC flag without ICCP", a.vp8x_offset); }
  if (a.has_exif != 0 && a.flag_exif == 0) { return _at("webp: EXIF without EXIF flag", a.exif_offset); }
  if (a.has_exif == 0 && a.flag_exif != 0) { return _at("webp: EXIF flag without EXIF", a.vp8x_offset); }
  if (a.has_xmp != 0 && a.flag_xmp == 0) { return _at("webp: XMP without XMP flag", a.xmp_offset); }
  if (a.has_xmp == 0 && a.flag_xmp != 0) { return _at("webp: XMP flag without XMP", a.vp8x_offset); }
  if (a.has_alph != 0 && a.flag_alpha == 0) { return _at("webp: ALPH without alpha flag", a.alph_offset); }
  if (a.has_alph == 0 && a.flag_alpha != 0 && a.image_format == 1) {
    return _at("webp: alpha flag without ALPH", a.vp8x_offset);
  }
  return "";
}

// --------------------------------------------------
//  Parser
// --------------------------------------------------

/// Parse and fully validate one WebP (RIFF) buffer. Nothing is materialized:
/// the result carries the container kind, the canvas dimensions, the VP8X
/// flag bits, the top-level chunk index, the still-image metadata and the
/// animation frame index; bitstream payloads are never decoded.
///
/// Validation order and messages (see SPEC.md for the catalog):
///   1. fewer than 4 bytes, or fewer than 12 with "RIFF" -> "webp: truncated
///      header at 0"; a wrong magic byte -> "webp: bad magic at <offset>";
///      a RIFF size field that is not exactly size-8 -> "webp: riff size
///      mismatch at 4";
///   2. per chunk: a header or payload that runs past the buffer ->
///      "webp: truncated chunk at <offset>"; a fourcc byte outside 0x20..0x7E
///      -> "webp: invalid FourCC at <offset>"; an odd-size chunk without its
///      padding byte -> "webp: truncated padding at <offset>"; a non-zero
///      padding byte -> "webp: invalid padding byte at <offset>";
///   3. VP8 / VP8L / VP8X / ALPH / ANIM / ANMF / ICCP / EXIF / XMP payloads
///      are validated as documented (catalog below); unknown chunks are
///      recorded opaque in the index;
///   4. post-walk: container-kind consistency, VP8X flag/chunk agreement and
///      metadata chunk ordering.
/// Complexity: O(input bytes).
pub fn webp_parse(data: &Vec[UInt8]) -> Result[WebpImage, Str]
  ensures: !webp_is_webp(data) => result is Err;
  ensures: result is Ok => webp_is_webp(data);
{
  let n = data.len();
  let hdr = _header_error(data, n);
  if (hdr.len() > 0) { return _err_img(hdr); }
  var a = WebpImage{
    kind: 0;
    size: n;
    riff_size: _le32(data, 4);
    has_vp8x: 0;
    vp8x_offset: -1;
    flags: 0;
    flag_icc: 0;
    flag_alpha: 0;
    flag_exif: 0;
    flag_xmp: 0;
    flag_animation: 0;
    canvas_width: 0;
    canvas_height: 0;
    has_image: 0;
    image_format: 0;
    image_offset: -1;
    image_data_offset: -1;
    image_size: -1;
    image_width: 0;
    image_height: 0;
    vp8_version: -1;
    vp8_show_frame: -1;
    vp8_first_part_size: -1;
    vp8l_alpha: -1;
    vp8l_version: -1;
    has_alph: 0;
    alph_offset: -1;
    alph_size: -1;
    has_iccp: 0;
    iccp_offset: -1;
    iccp_size: -1;
    has_exif: 0;
    exif_offset: -1;
    exif_size: -1;
    has_xmp: 0;
    xmp_offset: -1;
    xmp_size: -1;
    has_anim: 0;
    anim_offset: -1;
    anim_background: 0;
    anim_loop_count: 0;
    chunk_fourcc: Vec[Str].new();
    chunk_offset: Vec[Int].new();
    chunk_size: Vec[Int].new();
    chunk_data_offset: Vec[Int].new();
    chunk_padding: Vec[Int].new();
    chunk_kind: Vec[Int].new();
    frame_x: Vec[Int].new();
    frame_y: Vec[Int].new();
    frame_width: Vec[Int].new();
    frame_height: Vec[Int].new();
    frame_duration: Vec[Int].new();
    frame_blend: Vec[Int].new();
    frame_dispose: Vec[Int].new();
    frame_offset: Vec[Int].new();
    frame_size: Vec[Int].new();
    frame_format: Vec[Int].new();
    frame_data_offset: Vec[Int].new();
    frame_data_size: Vec[Int].new();
    frame_has_alpha: Vec[Int].new();
    frame_nested_count: Vec[Int].new();
    frame_unknown_count: Vec[Int].new();
  };
  let walk = _scan_chunks(&mut a, data, n);
  if (walk.len() > 0) { return _err_img(walk); }
  let post = _post_error(&a);
  if (post.len() > 0) { return _err_img(post); }
  if (a.has_vp8x == 0) {
    a.kind = 0;
    a.canvas_width = a.image_width;
    a.canvas_height = a.image_height;
  } elif (a.flag_animation != 0) {
    a.kind = 2;
  } else {
    a.kind = 1;
  }
  return _ok_img(a);
}

// --------------------------------------------------
//  Classification
// --------------------------------------------------

/// True when the buffer starts with the 12-byte RIFF/WEBP header. Malformed
/// or short buffers return false rather than an error; use webp_parse when
/// the reason matters. Complexity: O(1).
pub fn webp_is_webp(data: &Vec[UInt8]) -> Bool
  ensures: data.len() < 12 => !result;
  ensures: result => data.len() >= 12;
{
  return _magic_ok(data, data.len());
}

// --------------------------------------------------
//  Container accessors
// --------------------------------------------------

/// Container kind: 0 simple, 1 extended, 2 animated.
/// Complexity: O(1).
pub fn webp_kind(img: &WebpImage) -> Int
  ensures: result == img.kind;
{
  return img.kind;
}

/// Total buffer size in bytes (the parsed input length).
/// Complexity: O(1).
pub fn webp_size(img: &WebpImage) -> Int {
  return img.size;
}

/// Declared RIFF size field (input length minus 8).
/// Complexity: O(1).
pub fn webp_riff_size(img: &WebpImage) -> Int {
  return img.riff_size;
}

/// True when a VP8X chunk was present.
/// Complexity: O(1).
pub fn webp_has_vp8x(img: &WebpImage) -> Bool
  ensures: img.has_vp8x != 0 => result;
  ensures: img.has_vp8x == 0 => !result;
{
  return img.has_vp8x != 0;
}

/// Absolute offset of the VP8X chunk fourcc, or -1 when absent.
/// Complexity: O(1).
pub fn webp_vp8x_offset(img: &WebpImage) -> Int {
  return img.vp8x_offset;
}

/// Raw VP8X flags byte, or 0 when there is no VP8X chunk.
/// Complexity: O(1).
pub fn webp_flags(img: &WebpImage) -> Int {
  return img.flags;
}

/// VP8X ICC profile bit (I) as 0 or 1.
/// Complexity: O(1).
pub fn webp_flag_icc(img: &WebpImage) -> Int
  ensures: result == img.flag_icc;
{
  return img.flag_icc;
}

/// VP8X alpha bit (L) as 0 or 1.
/// Complexity: O(1).
pub fn webp_flag_alpha(img: &WebpImage) -> Int {
  return img.flag_alpha;
}

/// VP8X Exif metadata bit (E) as 0 or 1.
/// Complexity: O(1).
pub fn webp_flag_exif(img: &WebpImage) -> Int {
  return img.flag_exif;
}

/// VP8X XMP metadata bit (X) as 0 or 1.
/// Complexity: O(1).
pub fn webp_flag_xmp(img: &WebpImage) -> Int {
  return img.flag_xmp;
}

/// VP8X animation bit (A) as 0 or 1.
/// Complexity: O(1).
pub fn webp_flag_animation(img: &WebpImage) -> Int {
  return img.flag_animation;
}

/// Canvas width in pixels: the VP8X value in extended/animated files, the
/// image width in simple files.
/// Complexity: O(1).
pub fn webp_canvas_width(img: &WebpImage) -> Int {
  return img.canvas_width;
}

/// Canvas height in pixels: the VP8X value in extended/animated files, the
/// image height in simple files.
/// Complexity: O(1).
pub fn webp_canvas_height(img: &WebpImage) -> Int {
  return img.canvas_height;
}

// --------------------------------------------------
//  Still image accessors
// --------------------------------------------------

/// True when a top-level VP8/VP8L image chunk was present.
/// Complexity: O(1).
pub fn webp_has_image(img: &WebpImage) -> Bool {
  return img.has_image != 0;
}

/// Top-level image format: 0 none, 1 VP8, 2 VP8L.
/// Complexity: O(1).
pub fn webp_image_format(img: &WebpImage) -> Int {
  return img.image_format;
}

/// Absolute offset of the top-level image chunk fourcc, or -1 when absent.
/// Complexity: O(1).
pub fn webp_image_offset(img: &WebpImage) -> Int {
  return img.image_offset;
}

/// Absolute offset of the top-level image payload, or -1 when absent.
/// Complexity: O(1).
pub fn webp_image_data_offset(img: &WebpImage) -> Int {
  return img.image_data_offset;
}

/// Declared size of the top-level image payload, or -1 when absent.
/// Complexity: O(1).
pub fn webp_image_size(img: &WebpImage) -> Int {
  return img.image_size;
}

/// Image width in pixels (VP8 14-bit value or VP8L 14-bit value + 1), 0 when
/// there is no top-level image.
/// Complexity: O(1).
pub fn webp_image_width(img: &WebpImage) -> Int {
  return img.image_width;
}

/// Image height in pixels (VP8 14-bit value or VP8L 14-bit value + 1), 0 when
/// there is no top-level image.
/// Complexity: O(1).
pub fn webp_image_height(img: &WebpImage) -> Int {
  return img.image_height;
}

/// VP8 frame-tag version bits (0..3), or -1 when the image is not VP8.
/// Complexity: O(1).
pub fn webp_vp8_version(img: &WebpImage) -> Int {
  return img.vp8_version;
}

/// VP8 frame-tag show-frame bit, or -1 when the image is not VP8.
/// Complexity: O(1).
pub fn webp_vp8_show_frame(img: &WebpImage) -> Int {
  return img.vp8_show_frame;
}

/// VP8 frame-tag 19-bit first-partition size, or -1 when the image is not
/// VP8.
/// Complexity: O(1).
pub fn webp_vp8_first_part_size(img: &WebpImage) -> Int {
  return img.vp8_first_part_size;
}

/// VP8L alpha-is-used hint bit, or -1 when the image is not VP8L.
/// Complexity: O(1).
pub fn webp_vp8l_alpha(img: &WebpImage) -> Int {
  return img.vp8l_alpha;
}

/// VP8L 3-bit version (always 0 when a VP8L image parsed), or -1 when the
/// image is not VP8L.
/// Complexity: O(1).
pub fn webp_vp8l_version(img: &WebpImage) -> Int {
  return img.vp8l_version;
}

// --------------------------------------------------
//  Metadata accessors (payloads are never interpreted)
// --------------------------------------------------

/// True when a top-level ALPH chunk was present.
/// Complexity: O(1).
pub fn webp_has_alph(img: &WebpImage) -> Bool {
  return img.has_alph != 0;
}

/// Absolute offset of the ALPH chunk fourcc, or -1 when absent.
/// Complexity: O(1).
pub fn webp_alph_offset(img: &WebpImage) -> Int {
  return img.alph_offset;
}

/// ALPH payload size, or -1 when absent.
/// Complexity: O(1).
pub fn webp_alph_size(img: &WebpImage) -> Int {
  return img.alph_size;
}

/// True when an ICCP chunk was present.
/// Complexity: O(1).
pub fn webp_has_iccp(img: &WebpImage) -> Bool {
  return img.has_iccp != 0;
}

/// Absolute offset of the ICCP chunk fourcc, or -1 when absent.
/// Complexity: O(1).
pub fn webp_iccp_offset(img: &WebpImage) -> Int {
  return img.iccp_offset;
}

/// ICCP payload size, or -1 when absent.
/// Complexity: O(1).
pub fn webp_iccp_size(img: &WebpImage) -> Int {
  return img.iccp_size;
}

/// True when an EXIF chunk was present.
/// Complexity: O(1).
pub fn webp_has_exif(img: &WebpImage) -> Bool {
  return img.has_exif != 0;
}

/// Absolute offset of the EXIF chunk fourcc, or -1 when absent.
/// Complexity: O(1).
pub fn webp_exif_offset(img: &WebpImage) -> Int {
  return img.exif_offset;
}

/// EXIF payload size, or -1 when absent.
/// Complexity: O(1).
pub fn webp_exif_size(img: &WebpImage) -> Int {
  return img.exif_size;
}

/// True when an XMP chunk was present.
/// Complexity: O(1).
pub fn webp_has_xmp(img: &WebpImage) -> Bool {
  return img.has_xmp != 0;
}

/// Absolute offset of the XMP chunk fourcc, or -1 when absent.
/// Complexity: O(1).
pub fn webp_xmp_offset(img: &WebpImage) -> Int {
  return img.xmp_offset;
}

/// XMP payload size, or -1 when absent.
/// Complexity: O(1).
pub fn webp_xmp_size(img: &WebpImage) -> Int {
  return img.xmp_size;
}

// --------------------------------------------------
//  Animation accessors
// --------------------------------------------------

/// True when an ANIM chunk was present.
/// Complexity: O(1).
pub fn webp_has_anim(img: &WebpImage) -> Bool {
  return img.has_anim != 0;
}

/// Absolute offset of the ANIM chunk fourcc, or -1 when absent.
/// Complexity: O(1).
pub fn webp_anim_offset(img: &WebpImage) -> Int {
  return img.anim_offset;
}

/// Raw ANIM background color as a LE32 value in [Blue, Green, Red, Alpha]
/// byte order, or 0 when absent.
/// Complexity: O(1).
pub fn webp_anim_background(img: &WebpImage) -> Int {
  return img.anim_background;
}

/// Background color blue byte from the ANIM chunk.
/// Complexity: O(1).
pub fn webp_anim_background_blue(img: &WebpImage) -> Int
  ensures: result == img.anim_background % 256;
{
  return img.anim_background % 256;
}

/// Background color green byte from the ANIM chunk.
/// Complexity: O(1).
pub fn webp_anim_background_green(img: &WebpImage) -> Int
  ensures: result == (img.anim_background / 256) % 256;
{
  return (img.anim_background / 256) % 256;
}

/// Background color red byte from the ANIM chunk.
/// Complexity: O(1).
pub fn webp_anim_background_red(img: &WebpImage) -> Int
  ensures: result == (img.anim_background / 65536) % 256;
{
  return (img.anim_background / 65536) % 256;
}

/// Background color alpha byte from the ANIM chunk.
/// Complexity: O(1).
pub fn webp_anim_background_alpha(img: &WebpImage) -> Int
  ensures: result == (img.anim_background / 16777216) % 256;
{
  return (img.anim_background / 16777216) % 256;
}

/// ANIM loop count (0 = loop forever), or 0 when absent.
/// Complexity: O(1).
pub fn webp_anim_loop_count(img: &WebpImage) -> Int {
  return img.anim_loop_count;
}

// --------------------------------------------------
//  Chunk index accessors (out-of-range values return "" or -1)
// --------------------------------------------------

/// Number of top-level chunks in the chunk index.
/// Complexity: O(1).
pub fn webp_chunk_count(img: &WebpImage) -> Int
  ensures: result == img.chunk_fourcc.len();
{
  return img.chunk_fourcc.len();
}

/// Fourcc of chunk `i` as a 4-character Str, or "" when `i` is outside the
/// index. Because the value comes from a Vec[Str], compare it with
/// xiom.string.compare.str_compare, never with `==`.
/// Complexity: O(1).
pub fn webp_chunk_fourcc(img: &WebpImage, i: Int) -> Str
  ensures: i < 0 => result.len() == 0;
  ensures: i >= img.chunk_fourcc.len() => result.len() == 0;
{
  if (i < 0 || i >= img.chunk_fourcc.len()) { return ""; }
  let v: Str = img.chunk_fourcc[i];
  return v;
}

/// Absolute offset of chunk `i`'s fourcc, or -1 when out of range.
/// Complexity: O(1).
pub fn webp_chunk_offset(img: &WebpImage, i: Int) -> Int
  ensures: i < 0 => result == -1;
  ensures: i >= img.chunk_offset.len() => result == -1;
  ensures: result != -1 => i >= 0 && i < img.chunk_offset.len();
{
  if (i < 0 || i >= img.chunk_offset.len()) { return -1; }
  let v: Int = img.chunk_offset[i];
  return v;
}

/// Declared payload size of chunk `i`, or -1 when out of range.
/// Complexity: O(1).
pub fn webp_chunk_size(img: &WebpImage, i: Int) -> Int {
  if (i < 0 || i >= img.chunk_size.len()) { return -1; }
  let v: Int = img.chunk_size[i];
  return v;
}

/// Absolute offset of chunk `i`'s first payload byte, or -1 when out of
/// range.
/// Complexity: O(1).
pub fn webp_chunk_data_offset(img: &WebpImage, i: Int) -> Int {
  if (i < 0 || i >= img.chunk_data_offset.len()) { return -1; }
  let v: Int = img.chunk_data_offset[i];
  return v;
}

/// Padding state of chunk `i`: 1 when a padding byte follows (odd size), 0
/// otherwise; -1 when out of range.
/// Complexity: O(1).
pub fn webp_chunk_padding(img: &WebpImage, i: Int) -> Int {
  if (i < 0 || i >= img.chunk_padding.len()) { return -1; }
  let v: Int = img.chunk_padding[i];
  return v;
}

/// Kind code of chunk `i` (webp_chunk_*), or -1 when out of range.
/// Complexity: O(1).
pub fn webp_chunk_kind(img: &WebpImage, i: Int) -> Int {
  if (i < 0 || i >= img.chunk_kind.len()) { return -1; }
  let v: Int = img.chunk_kind[i];
  return v;
}

// --------------------------------------------------
//  Frame index accessors (out-of-range values return -1)
// --------------------------------------------------

/// Number of ANMF frames in the frame index.
/// Complexity: O(1).
pub fn webp_frame_count(img: &WebpImage) -> Int
  ensures: result == img.frame_x.len();
{
  return img.frame_x.len();
}

/// Frame `i` X coordinate in pixels, or -1 when out of range.
/// Complexity: O(1).
pub fn webp_frame_x(img: &WebpImage, i: Int) -> Int
  ensures: i < 0 => result == -1;
  ensures: i >= img.frame_x.len() => result == -1;
  ensures: result != -1 => i >= 0 && i < img.frame_x.len();
{
  if (i < 0 || i >= img.frame_x.len()) { return -1; }
  let v: Int = img.frame_x[i];
  return v;
}

/// Frame `i` Y coordinate in pixels, or -1 when out of range.
/// Complexity: O(1).
pub fn webp_frame_y(img: &WebpImage, i: Int) -> Int {
  if (i < 0 || i >= img.frame_y.len()) { return -1; }
  let v: Int = img.frame_y[i];
  return v;
}

/// Frame `i` width in pixels, or -1 when out of range.
/// Complexity: O(1).
pub fn webp_frame_width(img: &WebpImage, i: Int) -> Int {
  if (i < 0 || i >= img.frame_width.len()) { return -1; }
  let v: Int = img.frame_width[i];
  return v;
}

/// Frame `i` height in pixels, or -1 when out of range.
/// Complexity: O(1).
pub fn webp_frame_height(img: &WebpImage, i: Int) -> Int {
  if (i < 0 || i >= img.frame_height.len()) { return -1; }
  let v: Int = img.frame_height[i];
  return v;
}

/// Frame `i` duration in milliseconds, or -1 when out of range.
/// Complexity: O(1).
pub fn webp_frame_duration(img: &WebpImage, i: Int) -> Int {
  if (i < 0 || i >= img.frame_duration.len()) { return -1; }
  let v: Int = img.frame_duration[i];
  return v;
}

/// Frame `i` blending method bit (0 alpha-blend, 1 do not blend), or -1 when
/// out of range.
/// Complexity: O(1).
pub fn webp_frame_blend(img: &WebpImage, i: Int) -> Int {
  if (i < 0 || i >= img.frame_blend.len()) { return -1; }
  let v: Int = img.frame_blend[i];
  return v;
}

/// Frame `i` disposal method bit (0 none, 1 background), or -1 when out of
/// range.
/// Complexity: O(1).
pub fn webp_frame_dispose(img: &WebpImage, i: Int) -> Int {
  if (i < 0 || i >= img.frame_dispose.len()) { return -1; }
  let v: Int = img.frame_dispose[i];
  return v;
}

/// Absolute offset of frame `i`'s ANMF payload, or -1 when out of range.
/// Complexity: O(1).
pub fn webp_frame_offset(img: &WebpImage, i: Int) -> Int {
  if (i < 0 || i >= img.frame_offset.len()) { return -1; }
  let v: Int = img.frame_offset[i];
  return v;
}

/// Declared ANMF payload size of frame `i`, or -1 when out of range.
/// Complexity: O(1).
pub fn webp_frame_size(img: &WebpImage, i: Int) -> Int {
  if (i < 0 || i >= img.frame_size.len()) { return -1; }
  let v: Int = img.frame_size[i];
  return v;
}

/// Bitstream format of frame `i`: 1 VP8, 2 VP8L; -1 when out of range.
/// Complexity: O(1).
pub fn webp_frame_format(img: &WebpImage, i: Int) -> Int
  ensures: i < 0 => result == -1;
  ensures: i >= img.frame_format.len() => result == -1;
  ensures: result != -1 => i >= 0 && i < img.frame_format.len();
{
  if (i < 0 || i >= img.frame_format.len()) { return -1; }
  let v: Int = img.frame_format[i];
  return v;
}

/// Absolute offset of frame `i`'s nested bitstream payload, or -1 when out of
/// range.
/// Complexity: O(1).
pub fn webp_frame_data_offset(img: &WebpImage, i: Int) -> Int {
  if (i < 0 || i >= img.frame_data_offset.len()) { return -1; }
  let v: Int = img.frame_data_offset[i];
  return v;
}

/// Size of frame `i`'s nested bitstream payload, or -1 when out of range.
/// Complexity: O(1).
pub fn webp_frame_data_size(img: &WebpImage, i: Int) -> Int {
  if (i < 0 || i >= img.frame_data_size.len()) { return -1; }
  let v: Int = img.frame_data_size[i];
  return v;
}

/// 1 when frame `i` carries a nested ALPH sub-chunk, 0 when not, -1 when out
/// of range.
/// Complexity: O(1).
pub fn webp_frame_has_alpha(img: &WebpImage, i: Int) -> Int {
  if (i < 0 || i >= img.frame_has_alpha.len()) { return -1; }
  let v: Int = img.frame_has_alpha[i];
  return v;
}

/// Number of nested sub-chunks recorded for frame `i`, or -1 when out of
/// range.
/// Complexity: O(1).
pub fn webp_frame_nested_count(img: &WebpImage, i: Int) -> Int {
  if (i < 0 || i >= img.frame_nested_count.len()) { return -1; }
  let v: Int = img.frame_nested_count[i];
  return v;
}

/// Number of unknown nested sub-chunks recorded for frame `i`, or -1 when out
/// of range.
/// Complexity: O(1).
pub fn webp_frame_unknown_count(img: &WebpImage, i: Int) -> Int {
  if (i < 0 || i >= img.frame_unknown_count.len()) { return -1; }
  let v: Int = img.frame_unknown_count[i];
  return v;
}
