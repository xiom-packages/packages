// XIOM -- xiom.ktx: KTX 1 texture-container header, key/value and level codec
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure XIOM, no FFI. Parses and builds the structural parts of KTX 1
// ("KTX 11") texture containers:
//   * the 12-byte file identifier;
//   * the 64-byte header, little- or big-endian (the endianness marker at
//     offset 12 is stored as 0x04030201 little-endian / 0x01020304
//     big-endian and all remaining u32 fields follow that endianness);
//   * the key/value metadata region: for each pair a u32 keyAndValueByteSize
//     followed by keyAndValue (NUL-terminated printable-ASCII key, then
//     opaque value bytes) and valuePadding to the next 4-byte boundary. The
//     region is indexed into flat parallel vectors: keys, value offsets and
//     value lengths; value bytes stay in the source buffer;
//   * the mipmap-level records of non-array (numberOfArrayElements == 0),
//     non-cubemap (numberOfFaces == 1) textures: u32 imageSize, then
//     imageSize bytes of image data, then mipPadding to the next 4-byte
//     boundary before the next imageSize. image data is never decoded.
// KTX2 ("KTX 20") files are detected and rejected. Compression metadata
// (glInternalFormat values) is carried through as an integer and never
// interpreted. See SPEC.md for the layout tables, validation order, error
// catalog and test plan.
//
// v0.61.3 notes that shaped this module:
//   * Ok/Err construction is confined to the tiny leaf helpers below.
//   * every byte read from a Vec[UInt8] is widened with
//     `(data[pos] as Int) & 0xFF` before it enters Int arithmetic.
//   * Vec[Int] and Vec[Str] element reads are bound to typed locals first.
//   * Str values read from Vec[Str] fields are compared by callers with
//     xiom.string.compare.str_compare, never with `==`.
//   * free functions only; no Vec[StructType] and no `mut` match bindings.

module xiom.ktx

use xiom.string;

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/// Length of the KTX 1 identifier in bytes.
pub const KTX_ID_BYTES: Int = 12;

/// Total header length in bytes: 12-byte identifier + 13 u32 fields.
pub const KTX_HEADER_BYTES: Int = 64;

/// Marker value observed when the four bytes at offset 12 are read as a
/// little-endian u32. 0x04030201 means the file stores 01 02 03 04 and every
/// header field is little-endian.
pub const KTX_ENDIAN_LE: Int = 0x04030201;

/// Marker value observed when the four bytes at offset 12 are read as a
/// little-endian u32. 0x01020304 means the file stores 04 03 02 01 and every
/// header field is big-endian.
pub const KTX_ENDIAN_BE: Int = 0x01020304;

/// Smallest accepted glTypeSize (the documented 1..8 range).
pub const KTX_TYPE_SIZE_MIN: Int = 1;

/// Largest accepted glTypeSize (the documented 1..8 range).
pub const KTX_TYPE_SIZE_MAX: Int = 8;

// ---------------------------------------------------------------------------
// Parsed structures
// ---------------------------------------------------------------------------

/// A fully decoded KTX 1 header (64 bytes including the identifier).
///
/// `endianness` is the marker as read little-endian at offset 12:
/// KTX_ENDIAN_LE (0x04030201) or KTX_ENDIAN_BE (0x01020304). `big_endian`
/// is true for the latter, and every multi-byte field in the file is then
/// read big-endian. All remaining fields are unsigned 32-bit values kept as
/// Int so arithmetic cannot overflow; they are carried through verbatim and
/// never interpreted (in particular glInternalFormat is opaque compression
/// metadata).
pub type KtxHeader = {
  endianness: Int;              // KTX_ENDIAN_LE or KTX_ENDIAN_BE
  big_endian: Bool;             // true when the file fields are big-endian
  gl_type: Int;                 // 0 for compressed textures, else GL type
  gl_type_size: Int;            // data type size for endian conversion, 1..8
  gl_format: Int;               // 0 for compressed textures, else GL format
  gl_internal_format: Int;      // sized or compressed internal format (opaque)
  gl_base_internal_format: Int; // base internal format (RGB, RGBA, ...)
  pixel_width: Int;             // level-0 width in pixels, must be >= 1
  pixel_height: Int;            // level-0 height, 0 for 1D textures
  pixel_depth: Int;             // level-0 depth, 0 for 1D/2D textures
  array_elements: Int;          // number of array elements, 0 = not an array
  faces: Int;                   // 1 = non-cubemap, 6 = cubemap
  mipmap_levels: Int;           // stored levels, 0 = generate a full pyramid
  kv_bytes: Int;                // total bytesOfKeyValueData region size
}

/// Flat key/value index. Slot `i` (0..count-1) has the decoded printable
/// key `keys[i]`, its value bytes live in the source buffer at absolute
/// offset `value_offsets[i]` and are `value_bytes[i]` long. Value bytes are
/// opaque: any byte value is allowed and NUL termination is not assumed.
pub type KtxKeyValues = {
  count: Int;
  keys: Vec[Str];
  value_offsets: Vec[Int];
  value_bytes: Vec[Int];
}

/// A parsed non-array, non-cubemap KTX 1 buffer. The key/value region sits
/// at `kv_offset` (always KTX_HEADER_BYTES); the first level record starts
/// at `data_offset` (KTX_HEADER_BYTES + header.kv_bytes). For each level
/// `i`, `size_offsets[i]` is the absolute offset of its u32 imageSize field,
/// `image_sizes[i]` that field's value and the image bytes start four bytes
/// later. `data_bytes` counts `data_offset` through the end of the last
/// level's image data (padding after the final level is not counted).
pub type KtxInfo = {
  header: KtxHeader;
  kv: KtxKeyValues;
  kv_offset: Int;        // always 64
  data_offset: Int;      // 64 + header.kv_bytes
  level_count: Int;      // effective level count (0 is treated as 1)
  size_offsets: Vec[Int]; // absolute offset of each level's u32 imageSize
  image_sizes: Vec[Int];  // each level's imageSize value
  data_bytes: Int;        // bytes from data_offset through the last image
}

// ---------------------------------------------------------------------------
// Result leaf helpers (v0.61.3: Ok/Err may only be constructed in fns that
// return a Result directly, so every fallible public fn returns through one
// of these small constructors).
// ---------------------------------------------------------------------------

fn _err_hdr(m: Str) -> Result[KtxHeader, Str] { return Err(m); }
fn _ok_hdr(h: KtxHeader) -> Result[KtxHeader, Str] { return Ok(h); }
fn _err_kv(m: Str) -> Result[KtxKeyValues, Str] { return Err(m); }
fn _ok_kv(kv: KtxKeyValues) -> Result[KtxKeyValues, Str] { return Ok(kv); }
fn _err_info(m: Str) -> Result[KtxInfo, Str] { return Err(m); }
fn _ok_info(info: KtxInfo) -> Result[KtxInfo, Str] { return Ok(info); }
fn _err_bytes(m: Str) -> Result[Vec[UInt8], Str] { return Err(m); }
fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], Str] { return Ok(v); }

// ---------------------------------------------------------------------------
// Byte readers and writers
// ---------------------------------------------------------------------------

// Unsigned byte at index i (widened and masked to 0..255).
fn _b(data: &Vec[UInt8], i: Int) -> Int {
  return (data[i] as Int) & 0xFF;
}

// Unsigned 32-bit value at `off`, read little- or big-endian.
fn _u32(data: &Vec[UInt8], off: Int, big: Bool) -> Int {
  let b0: Int = _b(data, off);
  let b1: Int = _b(data, off + 1);
  let b2: Int = _b(data, off + 2);
  let b3: Int = _b(data, off + 3);
  if big {
    return b0 * 16777216 + b1 * 65536 + b2 * 256 + b3;
  }
  return b3 * 16777216 + b2 * 65536 + b1 * 256 + b0;
}

// Append the low 32 bits of v, little-endian (the canonical builder order).
fn _p32(out: &mut Vec[UInt8], v: Int) {
  out.push((v % 256) as UInt8);
  out.push(((v / 256) % 256) as UInt8);
  out.push(((v / 65536) % 256) as UInt8);
  out.push(((v / 16777216) % 256) as UInt8);
}

// `len` bytes at `off` as a Str (the caller guarantees the bounds). The
// printable-key rule guarantees no embedded NUL reaches this helper.
fn _bytes_str(data: &Vec[UInt8], off: Int, len: Int) -> Str {
  let bytes = Vec[UInt8].new();
  var i = 0;
  while (i < len) {
    bytes.push(data[off + i]);
    i = i + 1;
  }
  return Str::from_utf8(bytes);
}

// True when v fits an unsigned 32-bit header field.
fn _u32_ok(v: Int) -> Bool {
  if (v < 0) { return false; }
  if (v > 4294967295) { return false; }
  return true;
}

// ---------------------------------------------------------------------------
// Identifier
// ---------------------------------------------------------------------------

// 0 = not a KTX identifier, 1 = KTX 1 ("KTX 11"), 2 = KTX 2 ("KTX 20").
// Buffers shorter than the 12 identifier bytes are 0.
fn _identifier_kind(data: &Vec[UInt8]) -> Int {
  if (data.len() < KTX_ID_BYTES) { return 0; }
  if (_b(data, 0) != 0xAB) { return 0; }
  if (_b(data, 1) != 75) { return 0; }   // K
  if (_b(data, 2) != 84) { return 0; }   // T
  if (_b(data, 3) != 88) { return 0; }   // X
  if (_b(data, 4) != 32) { return 0; }   // space
  if (_b(data, 7) != 0xBB) { return 0; }
  if (_b(data, 8) != 13) { return 0; }   // CR
  if (_b(data, 9) != 10) { return 0; }   // LF
  if (_b(data, 10) != 26) { return 0; }  // 0x1A
  if (_b(data, 11) != 10) { return 0; }  // LF
  if (_b(data, 5) == 49 && _b(data, 6) == 49) {
    return 1;
  }
  if (_b(data, 5) == 50 && _b(data, 6) == 48) {
    return 2;
  }
  return 0;
}
  if (_b(data, 5) == 50 && _b(data, 6) == 48 && _b(data, 7) == 0xBB) {
    return 2;
  }
  return 0;
}

// Append the 12 identifier bytes of KTX 1.
fn _put_identifier(out: &mut Vec[UInt8]) {
  out.push((0xAB) as UInt8);
  out.push(75 as UInt8);   // K
  out.push(84 as UInt8);   // T
  out.push(88 as UInt8);   // X
  out.push(32 as UInt8);   // space
  out.push(49 as UInt8);   // 1
  out.push(49 as UInt8);   // 1
  out.push((0xBB) as UInt8);
  out.push(13 as UInt8);   // CR
  out.push(10 as UInt8);   // LF
  out.push(26 as UInt8);   // 0x1A
  out.push(10 as UInt8);   // LF
}

// ---------------------------------------------------------------------------
// Key/value region
// ---------------------------------------------------------------------------

// Walk the bytesOfKeyValueData region of a parsed header and index every
// pair into flat parallel vectors. Rules, in order:
//   * the declared region must fit in the buffer;
//   * bytesOfKeyValueData must be a multiple of 4 (the format aligns every
//     imageSize field to 4 bytes);
//   * each pair starts with a u32 keyAndValueByteSize, which must leave room
//     for at least one NUL-terminated key byte and must fit in the region;
//   * the key must contain a NUL terminator inside the pair;
//   * the key must be non-empty and every key byte must be printable ASCII
//     (0x20..0x7E). Keys beginning with "KTX"/"ktx" are reserved by the
//     specification but are accepted here (KTXorientation is a defined key),
//     so the rule is the printable range alone;
//   * the value is the remaining pair bytes (empty allowed) and the next
//     pair starts at the next 4-byte boundary. Value bytes are opaque.
fn _parse_kv(data: &Vec[UInt8], h: &KtxHeader) -> Result[KtxKeyValues, Str] {
  let n = data.len();
  let start = KTX_HEADER_BYTES;
  let end = start + h.kv_bytes;
  if (end > n) { return _err_kv("ktx: truncated key/value data"); }
  if (h.kv_bytes % 4 != 0) { return _err_kv("ktx: unaligned key/value data"); }
  let keys = Vec[Str].new();
  let value_offsets = Vec[Int].new();
  let value_bytes = Vec[Int].new();
  var pos = start;
  while (pos < end) {
    if (pos + 4 > end) { return _err_kv("ktx: truncated key/value data"); }
    let pair: Int = _u32(data, pos, h.big_endian);
    if (pair < 1) { return _err_kv("ktx: invalid key"); }
    let body = pos + 4;
    if (pair > end - body) { return _err_kv("ktx: bad key/value size"); }
    var z = -1;
    var j = 0;
    while (j < pair && z < 0) {
      if (_b(data, body + j) == 0) { z = j; }
      j = j + 1;
    }
    if (z < 0) { return _err_kv("ktx: missing key terminator"); }
    if (z == 0) { return _err_kv("ktx: invalid key"); }
    var k = 0;
    while (k < z) {
      let c: Int = _b(data, body + k);
      if (c < 32 || c > 126) { return _err_kv("ktx: invalid key"); }
      k = k + 1;
    }
    keys.push(_bytes_str(data, body, z));
    value_offsets.push(body + z + 1);
    value_bytes.push(pair - z - 1);
    let aligned = ((pair + 3) / 4) * 4;
    if (body + aligned > end) { return _err_kv("ktx: bad key/value size"); }
    pos = body + aligned;
  }
  let count = keys.len();
  let kv = KtxKeyValues{
    count: count;
    keys: keys;
    value_offsets: value_offsets;
    value_bytes: value_bytes;
  };
  return _ok_kv(kv);
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

/// True when `data` starts with the 12-byte KTX 1 identifier ("AB KTX 11 BB
/// CR LF 1A LF"). False for short buffers, corrupt identifiers and KTX 2
/// ("KTX 20") files.
pub fn ktx_is_ktx(data: &Vec[UInt8]) -> Bool {
  return _identifier_kind(data) == 1;
}

/// Parse and validate the KTX 1 header (identifier plus 13 u32 fields).
///
/// Validation order:
///   1. a buffer shorter than 12 bytes -> "ktx: truncated header";
///   2. a KTX 2 identifier -> "ktx: ktx2 not supported"; any other mismatch
///      -> "ktx: bad identifier";
///   3. a buffer shorter than 64 bytes -> "ktx: truncated header";
///   4. the endianness marker is neither 0x04030201 nor 0x01020304 ->
///      "ktx: bad endianness";
///   5. glTypeSize outside 1..8 -> "ktx: invalid type size";
///   6. numberOfFaces other than 1 or 6 -> "ktx: invalid face count";
///   7. pixelWidth == 0 -> "ktx: invalid width".
///
/// The height/depth shape rules of the specification (0 for absent axes) are
/// not enforced, glInternalFormat is never interpreted, and the key/value
/// region and level records are not required to be present here.
pub fn ktx_parse_header(data: &Vec[UInt8]) -> Result[KtxHeader, Str] {
  let n = data.len();
  if (n < KTX_ID_BYTES) { return _err_hdr("ktx: truncated header"); }
  let kind = _identifier_kind(data);
  if (kind == 2) { return _err_hdr("ktx: ktx2 not supported"); }
  if (kind != 1) { return _err_hdr("ktx: bad identifier"); }
  if (n < KTX_HEADER_BYTES) { return _err_hdr("ktx: truncated header"); }
  let marker: Int = _u32(data, 12, false);
  var big = false;
  if (marker == KTX_ENDIAN_LE) {
    big = false;
  } elif (marker == KTX_ENDIAN_BE) {
    big = true;
  } else {
    return _err_hdr("ktx: bad endianness");
  }
  let gl_type: Int = _u32(data, 16, big);
  let gl_type_size: Int = _u32(data, 20, big);
  let gl_format: Int = _u32(data, 24, big);
  let gl_internal_format: Int = _u32(data, 28, big);
  let gl_base_internal_format: Int = _u32(data, 32, big);
  let pixel_width: Int = _u32(data, 36, big);
  let pixel_height: Int = _u32(data, 40, big);
  let pixel_depth: Int = _u32(data, 44, big);
  let array_elements: Int = _u32(data, 48, big);
  let faces: Int = _u32(data, 52, big);
  let mipmap_levels: Int = _u32(data, 56, big);
  let kv_bytes: Int = _u32(data, 60, big);
  if (gl_type_size < KTX_TYPE_SIZE_MIN || gl_type_size > KTX_TYPE_SIZE_MAX) {
    return _err_hdr("ktx: invalid type size");
  }
  if (faces != 1 && faces != 6) {
    return _err_hdr("ktx: invalid face count");
  }
  if (pixel_width == 0) { return _err_hdr("ktx: invalid width"); }
  let h = KtxHeader{
    endianness: marker;
    big_endian: big;
    gl_type: gl_type;
    gl_type_size: gl_type_size;
    gl_format: gl_format;
    gl_internal_format: gl_internal_format;
    gl_base_internal_format: gl_base_internal_format;
    pixel_width: pixel_width;
    pixel_height: pixel_height;
    pixel_depth: pixel_depth;
    array_elements: array_elements;
    faces: faces;
    mipmap_levels: mipmap_levels;
    kv_bytes: kv_bytes;
  };
  return _ok_hdr(h);
}

/// Build the canonical 64-byte KTX 1 header: identifier, little-endian
/// endianness marker (0x04030201, stored as 01 02 03 04), every field
/// little-endian, and bytesOfKeyValueData pinned to 0 (the builder emits no
/// key/value data). `h.endianness`, `h.big_endian` and `h.kv_bytes` are
/// therefore ignored; a big-endian header is never built.
///
/// Every field must fit an unsigned 32-bit value, otherwise "ktx: field out
/// of range"; glTypeSize must be 1..8, numberOfFaces 1 or 6 and pixelWidth
/// at least 1. The assembled bytes are re-validated through
/// ktx_parse_header, whose messages are forwarded unchanged.
pub fn ktx_build_header(h: &KtxHeader) -> Result[Vec[UInt8], Str] {
  if (!_u32_ok(h.gl_type)) { return _err_bytes("ktx: field out of range"); }
  if (!_u32_ok(h.gl_type_size)) { return _err_bytes("ktx: field out of range"); }
  if (!_u32_ok(h.gl_format)) { return _err_bytes("ktx: field out of range"); }
  if (!_u32_ok(h.gl_internal_format)) {
    return _err_bytes("ktx: field out of range");
  }
  if (!_u32_ok(h.gl_base_internal_format)) {
    return _err_bytes("ktx: field out of range");
  }
  if (!_u32_ok(h.pixel_width)) { return _err_bytes("ktx: field out of range"); }
  if (!_u32_ok(h.pixel_height)) { return _err_bytes("ktx: field out of range"); }
  if (!_u32_ok(h.pixel_depth)) { return _err_bytes("ktx: field out of range"); }
  if (!_u32_ok(h.array_elements)) {
    return _err_bytes("ktx: field out of range");
  }
  if (!_u32_ok(h.faces)) { return _err_bytes("ktx: field out of range"); }
  if (!_u32_ok(h.mipmap_levels)) { return _err_bytes("ktx: field out of range"); }
  if (h.gl_type_size < KTX_TYPE_SIZE_MIN || h.gl_type_size > KTX_TYPE_SIZE_MAX) {
    return _err_bytes("ktx: invalid type size");
  }
  if (h.faces != 1 && h.faces != 6) {
    return _err_bytes("ktx: invalid face count");
  }
  if (h.pixel_width == 0) { return _err_bytes("ktx: invalid width"); }
  var out = Vec[UInt8].new();
  _put_identifier(&mut out);
  _p32(&mut out, KTX_ENDIAN_LE);
  _p32(&mut out, h.gl_type);
  _p32(&mut out, h.gl_type_size);
  _p32(&mut out, h.gl_format);
  _p32(&mut out, h.gl_internal_format);
  _p32(&mut out, h.gl_base_internal_format);
  _p32(&mut out, h.pixel_width);
  _p32(&mut out, h.pixel_height);
  _p32(&mut out, h.pixel_depth);
  _p32(&mut out, h.array_elements);
  _p32(&mut out, h.faces);
  _p32(&mut out, h.mipmap_levels);
  _p32(&mut out, 0);
  let check = ktx_parse_header(out);
  match check {
    Ok(ok) => { return _ok_bytes(out); },
    Err(e) => { return _err_bytes(e); },
  }
}

// ---------------------------------------------------------------------------
// Key/value accessors
// ---------------------------------------------------------------------------

/// Parse the header and then the full key/value region. Works for every
/// header shape (cubemaps and arrays included); only the pair structure is
/// validated, never the value contents.
pub fn ktx_parse_key_values(data: &Vec[UInt8]) -> Result[KtxKeyValues, Str] {
  let hp = ktx_parse_header(data);
  match hp {
    Ok(h) => { return _parse_kv(data, &h); },
    Err(e) => { return _err_kv(e); },
  }
}

/// Number of key/value pairs (0 when the region is empty).
pub fn ktx_kv_count(kv: &KtxKeyValues) -> Int {
  return kv.keys.len();
}

/// Key of pair `i`, or "" when `i` is out of range. The result is a Str read
/// from a Vec[Str] field: callers must compare it with
/// xiom.string.compare.str_compare rather than `==`.
pub fn ktx_kv_key(kv: &KtxKeyValues, i: Int) -> Str {
  if (i < 0 || i >= kv.keys.len()) { return ""; }
  let k: Str = kv.keys[i];
  return k;
}

/// Absolute offset of pair `i`'s first value byte, or -1 out of range.
pub fn ktx_kv_value_offset(kv: &KtxKeyValues, i: Int) -> Int {
  if (i < 0 || i >= kv.value_offsets.len()) { return -1; }
  let off: Int = kv.value_offsets[i];
  return off;
}

/// Length in bytes of pair `i`'s value, or -1 out of range. Zero is a valid
/// length (an empty value).
pub fn ktx_kv_value_bytes(kv: &KtxKeyValues, i: Int) -> Int {
  if (i < 0 || i >= kv.value_bytes.len()) { return -1; }
  let len: Int = kv.value_bytes[i];
  return len;
}

/// Copy the value bytes of pair `i` from `data`. Values are opaque: NUL and
/// any other byte value are copied verbatim. An out-of-range index is
/// "ktx: key/value index out of range"; value bytes that do not fit the
/// given buffer are "ktx: truncated key/value data".
pub fn ktx_kv_value(data: &Vec[UInt8], kv: &KtxKeyValues, i: Int) -> Result[Vec[UInt8], Str] {
  if (i < 0 || i >= kv.keys.len()) {
    return _err_bytes("ktx: key/value index out of range");
  }
  let off: Int = kv.value_offsets[i];
  let len: Int = kv.value_bytes[i];
  if (off < 0 || len < 0 || off + len > data.len()) {
    return _err_bytes("ktx: truncated key/value data");
  }
  let out = Vec[UInt8].new();
  var j = 0;
  while (j < len) {
    let b: UInt8 = data[off + j];
    out.push(b);
    j = j + 1;
  }
  return _ok_bytes(out);
}

// ---------------------------------------------------------------------------
// Whole-buffer parse and level accessors
// ---------------------------------------------------------------------------

/// Effective level count: numberOfMipmapLevels is 0 when the file asks the
/// loader to generate a full pyramid, and the level loop treats 0 as 1.
pub fn ktx_level_count(h: &KtxHeader) -> Int {
  if (h.mipmap_levels == 0) { return 1; }
  return h.mipmap_levels;
}

/// True when glType is 0, the marker for a compressed texture.
pub fn ktx_is_compressed(h: &KtxHeader) -> Bool {
  return h.gl_type == 0;
}

/// True when numberOfFaces is 6.
pub fn ktx_is_cubemap(h: &KtxHeader) -> Bool {
  return h.faces == 6;
}

/// True when numberOfArrayElements is nonzero.
pub fn ktx_is_array(h: &KtxHeader) -> Bool {
  return h.array_elements != 0;
}

/// Absolute offset of the first level record: KTX_HEADER_BYTES +
/// bytesOfKeyValueData.
pub fn ktx_data_offset(h: &KtxHeader) -> Int {
  return KTX_HEADER_BYTES + h.kv_bytes;
}

/// Level-0 width in pixels (always at least 1 in a parsed header).
pub fn ktx_width(h: &KtxHeader) -> Int {
  return h.pixel_width;
}

/// Level-0 height in pixels (0 for 1D textures).
pub fn ktx_height(h: &KtxHeader) -> Int {
  return h.pixel_height;
}

/// Level-0 depth in pixels (0 for 1D/2D textures).
pub fn ktx_depth(h: &KtxHeader) -> Int {
  return h.pixel_depth;
}

/// The glType field, carried through verbatim (0 = compressed).
pub fn ktx_gl_type(h: &KtxHeader) -> Int {
  return h.gl_type;
}

/// The glFormat field, carried through verbatim (0 = compressed).
pub fn ktx_gl_format(h: &KtxHeader) -> Int {
  return h.gl_format;
}

/// The glInternalFormat field. For compressed textures this is the
/// compressed format; the value is opaque compression metadata here.
pub fn ktx_gl_internal_format(h: &KtxHeader) -> Int {
  return h.gl_internal_format;
}

/// The glBaseInternalFormat field.
pub fn ktx_gl_base_internal_format(h: &KtxHeader) -> Int {
  return h.gl_base_internal_format;
}

/// Parse and validate a whole KTX 1 buffer: header, key/value region and
/// the mipmap-level records of a non-array (numberOfArrayElements == 0),
/// non-cubemap (numberOfFaces == 1) texture.
///
/// Level rules for the supported layout: each level is a u32 imageSize, then
/// imageSize bytes of image data; between levels the record is padded with
/// zero to four bytes so the next imageSize starts at a 4-byte boundary.
/// Every imageSize and its data must fit the buffer, and an intermediate
/// level must leave room for the next level's imageSize field. Padding after
/// the final level is optional. Image bytes are located, never decoded.
///
/// Other layout combinations (arrays, cubemaps) parse their header and
/// key/value data through the other entry points but are rejected here with
/// "ktx: unsupported level layout", because the per-level span rule for
/// them is out of this codec's scope.
pub fn ktx_parse(data: &Vec[UInt8]) -> Result[KtxInfo, Str] {
  let hp = ktx_parse_header(data);
  match hp {
    Ok(h) => {
      if (h.array_elements != 0 || h.faces != 1) {
        return _err_info("ktx: unsupported level layout");
      }
      let kvp = _parse_kv(data, &h);
      match kvp {
        Ok(kv) => {
          let n = data.len();
          let levels = ktx_level_count(&h);
          let base = KTX_HEADER_BYTES + h.kv_bytes;
          let size_offsets = Vec[Int].new();
          let image_sizes = Vec[Int].new();
          var pos = base;
          var i = 0;
          while (i < levels) {
            if (pos + 4 > n) { return _err_info("ktx: truncated level data"); }
            let image_size: Int = _u32(data, pos, h.big_endian);
            let payload = pos + 4;
            if (image_size > n - payload) {
              return _err_info("ktx: truncated level data");
            }
            size_offsets.push(pos);
            image_sizes.push(image_size);
            pos = payload + image_size;
            if (i + 1 < levels) {
              let aligned = payload + ((image_size + 3) / 4) * 4;
              if (aligned + 4 > n) {
                return _err_info("ktx: truncated level data");
              }
              pos = aligned;
            }
            i = i + 1;
          }
          let info = KtxInfo{
            header: h;
            kv: kv;
            kv_offset: KTX_HEADER_BYTES;
            data_offset: base;
            level_count: levels;
            size_offsets: size_offsets;
            image_sizes: image_sizes;
            data_bytes: pos - base;
          };
          return _ok_info(info);
        },
        Err(e) => { return _err_info(e); },
      }
    },
    Err(e) => { return _err_info(e); },
  }
}

/// Absolute offset of level `i`'s u32 imageSize field, or -1 out of range.
pub fn ktx_level_offset(info: &KtxInfo, i: Int) -> Int {
  if (i < 0 || i >= info.size_offsets.len()) { return -1; }
  let off: Int = info.size_offsets[i];
  return off;
}

/// imageSize of level `i`, or -1 out of range.
pub fn ktx_level_size(info: &KtxInfo, i: Int) -> Int {
  if (i < 0 || i >= info.image_sizes.len()) { return -1; }
  let size: Int = info.image_sizes[i];
  return size;
}

/// Absolute offset of level `i`'s first image byte (the offset of its u32
/// imageSize field plus 4), or -1 out of range.
pub fn ktx_payload_offset(info: &KtxInfo, i: Int) -> Int {
  let off: Int = ktx_level_offset(info, i);
  if (off < 0) { return -1; }
  return off + 4;
}

/// Copy the image bytes of level `i` from `data` (imageSize bytes, padding
/// excluded). An out-of-range index is "ktx: level index out of range";
/// image bytes that do not fit the given buffer are
/// "ktx: truncated level data". Pixels are never decoded.
pub fn ktx_level_data(data: &Vec[UInt8], info: &KtxInfo, i: Int) -> Result[Vec[UInt8], Str] {
  if (i < 0 || i >= info.image_sizes.len()) {
    return _err_bytes("ktx: level index out of range");
  }
  let size: Int = info.image_sizes[i];
  let off: Int = info.size_offsets[i] + 4;
  if (size < 0 || off + size > data.len()) {
    return _err_bytes("ktx: truncated level data");
  }
  let out = Vec[UInt8].new();
  var j = 0;
  while (j < size) {
    let b: UInt8 = data[off + j];
    out.push(b);
    j = j + 1;
  }
  return _ok_bytes(out);
}
