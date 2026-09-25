// XIOM -- xiom.ico: ICO/CUR icon container codec (header, entries, payloads)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Scope: the ICONDIR container shared by Windows .ico icon files and .cur
// cursor files. A 6-byte header (reserved, type, image count) is followed by
// one 16-byte ICONDIRENTRY per image (width, height, color count, reserved,
// planes or hotspot X, bit count or hotspot Y, resource size, resource
// offset) and then by the image resources themselves. Payloads are opaque
// pass-through bytes: PNG, BMP/DIB and every legacy encoding are neither
// decoded nor rendered, and no palette, alpha or DPI field is interpreted.
//
// The package offers three layers:
//   * ico_parse_header / ico_parse -- structural validation with a
//     deterministic error catalog (see SPEC.md);
//   * ico_entry / ico_image_data -- decode one directory entry and copy one
//     resource payload out of the buffer;
//   * ico_builder_new / ico_builder_add / ico_builder_add_cursor /
//     ico_builder_emit -- append images and emit a canonical container
//     whose count and offsets are recomputed from scratch.
//
// v0.61.3 notes that shaped this module:
//   * Ok/Err construction is confined to the tiny leaf helpers below.
//   * every byte read from a Vec[UInt8] is widened with
//     `(data[i] as Int) & 0xFF`.
//   * every Vec[Int] element read is bound to a typed Int local.
//   * there is no Vec[StructType]: the builder keeps one flat payload vector
//     plus parallel Vec[Int] fields, and IcoInfo/IcoEntry are plain structs
//     returned through the leaf constructors.
// See SPEC.md for the byte layout tables, validation order, error catalog
// and test matrix.

module xiom.ico

// --------------------------------------------------
//  Constants
// --------------------------------------------------

/// Resource type of an icon container (ICONDIR.idType for .ico).
pub const ICO_TYPE_ICON: Int = 1;

/// Resource type of a cursor container (ICONDIR.idType for .cur).
pub const ICO_TYPE_CURSOR: Int = 2;

/// Size of the ICONDIR header in bytes.
pub const ICO_DIR_HEADER_BYTES: Int = 6;

/// Size of one ICONDIRENTRY in bytes.
pub const ICO_DIR_ENTRY_BYTES: Int = 16;

// --------------------------------------------------
//  Public types
// --------------------------------------------------

/// Parsed ICONDIR header. `count` is always 1..65535 and `dir_bytes` is
/// always 6 + 16 * count; both are derived from the validated header.
pub type IcoInfo = {
  kind: Int;        // ICO_TYPE_ICON (1) or ICO_TYPE_CURSOR (2)
  count: Int;       // number of directory entries, 1..65535
  dir_bytes: Int;   // 6 + 16 * count
}

/// One decoded 16-byte ICONDIRENTRY. Width and height are returned decoded:
/// the on-disk byte 0 (the 256-pixel sentinel) reads back as 256. For cursor
/// containers `planes` holds hotspot X and `bits` holds hotspot Y; for icon
/// containers they hold the color-plane count and the bits per pixel.
pub type IcoEntry = {
  width: Int;        // 1..256
  height: Int;       // 1..256
  color_count: Int;  // palette entry count as stored, 0 = unspecified
  planes: Int;       // ICO: color planes; CUR: hotspot X
  bits: Int;         // ICO: bits per pixel; CUR: hotspot Y
  bytes: Int;        // resource length in bytes, > 0
  offset: Int;       // resource offset from the start of the file
}

/// Incremental ICO/CUR builder. Images are appended in order; the flat
/// `payload` vector concatenates every resource and the parallel Int
/// vectors hold one value per image at the same index. Fields are
/// implementation details; callers use the free functions below.
pub type IcoBuilder = {
  kind: Int;
  widths: Vec[Int];
  heights: Vec[Int];
  color_counts: Vec[Int];
  planes: Vec[Int];
  bits: Vec[Int];
  sizes: Vec[Int];
  payload: Vec[UInt8];
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[IcoInfo, Str].
fn _ok_info(v: IcoInfo) -> Result[IcoInfo, Str] { return Ok(v); }

// Err(m) for Result[IcoInfo, Str].
fn _err_info(m: Str) -> Result[IcoInfo, Str] { return Err(m); }

// Ok(v) for Result[IcoEntry, Str].
fn _ok_entry(v: IcoEntry) -> Result[IcoEntry, Str] { return Ok(v); }

// Err(m) for Result[IcoEntry, Str].
fn _err_entry(m: Str) -> Result[IcoEntry, Str] { return Err(m); }

// Ok(v) for Result[IcoBuilder, Str].
fn _ok_builder(v: IcoBuilder) -> Result[IcoBuilder, Str] { return Ok(v); }

// Err(m) for Result[IcoBuilder, Str].
fn _err_builder(m: Str) -> Result[IcoBuilder, Str] { return Err(m); }

// Ok(v) for Result[Int, Str].
fn _ok_int(v: Int) -> Result[Int, Str] { return Ok(v); }

// Err(m) for Result[Int, Str].
fn _err_int(m: Str) -> Result[Int, Str] { return Err(m); }

// Ok(v) for Result[Vec[UInt8], Str].
fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], Str] { return Ok(v); }

// Err(m) for Result[Vec[UInt8], Str].
fn _err_bytes(m: Str) -> Result[Vec[UInt8], Str] { return Err(m); }

// --------------------------------------------------
//  Internal byte helpers (little-endian, as ICONDIR requires)
// --------------------------------------------------

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

// Append every byte of `v` to `out`.
fn _push_bytes(out: &mut Vec[UInt8], v: &Vec[UInt8]) {
  var i = 0;
  while (i < v.len()) {
    out.push(v[i]);
    i = i + 1;
  }
}

// Decode a stored dimension byte: 0 is the 256-pixel sentinel.
fn _entry_dim(raw: Int) -> Int {
  if (raw == 0) { return 256; }
  return raw;
}

// Encode a validated dimension (1..256): 256 becomes the 0 sentinel.
fn _dim_byte(dim: Int) -> Int {
  if (dim == 256) { return 0; }
  return dim;
}

// --------------------------------------------------
//  Directory size and header validation
// --------------------------------------------------

/// Bytes occupied by the 6-byte ICONDIR header plus `count` 16-byte
/// directory entries: `6 + 16 * count`. Callers pass a non-negative count
/// (the parsers validate the count before calling this).
pub fn ico_dir_bytes(count: Int) -> Int {
  return 6 + count * 16;
}

/// Parse the 6-byte ICONDIR header and check that the declared directory
/// fits the buffer.
///
/// Validation order: buffer has at least 6 bytes ->
/// Err("ico: truncated header"); reserved word is 0 ->
/// Err("ico: invalid reserved field"); type is 1 or 2 ->
/// Err("ico: unknown resource type"); count is at least 1 ->
/// Err("ico: zero image count"); `6 + 16 * count <= data.len()` ->
/// Err("ico: directory out of bounds"). Directory entries and payloads are
/// not inspected here; use ico_parse for that.
pub fn ico_parse_header(data: &Vec[UInt8]) -> Result[IcoInfo, Str] {
  let n = data.len();
  if (n < 6) { return _err_info("ico: truncated header"); }
  let reserved = _le16(data, 0);
  if (reserved != 0) { return _err_info("ico: invalid reserved field"); }
  let kind = _le16(data, 2);
  if (kind != 1 && kind != 2) { return _err_info("ico: unknown resource type"); }
  let count = _le16(data, 4);
  if (count == 0) { return _err_info("ico: zero image count"); }
  let dir = 6 + count * 16;
  if (dir > n) { return _err_info("ico: directory out of bounds"); }
  return _ok_info(IcoInfo{ kind: kind; count: count; dir_bytes: dir });
}

/// Parse and fully validate an ICO/CUR buffer: header plus every directory
/// entry and every declared resource span.
///
/// Runs ico_parse_header first and forwards its messages, then checks each
/// entry in directory order: entry reserved byte is 0 ->
/// Err("ico: invalid entry reserved field"); resource size is positive ->
/// Err("ico: empty image resource"); resource size does not exceed the
/// whole buffer -> Err("ico: entry size out of bounds"); resource offset is
/// at or past the end of the directory -> Err("ico: image data overlaps
/// directory"); resource offset plus size stays inside the buffer ->
/// Err("ico: image data out of bounds").
///
/// Two resources may point at the same bytes (that is accepted), and any
/// bytes after the last resource are ignored. Complexity: O(count).
pub fn ico_parse(data: &Vec[UInt8]) -> Result[IcoInfo, Str] {
  let hp = ico_parse_header(data);
  if (!hp.is_ok) { return _err_info(hp.error); }
  let info: IcoInfo = hp.value;
  let n = data.len();
  var i = 0;
  while (i < info.count) {
    let base = 6 + i * 16;
    let entry_reserved = _b(data, base + 3);
    if (entry_reserved != 0) {
      return _err_info("ico: invalid entry reserved field");
    }
    let size = _le32(data, base + 8);
    if (size == 0) { return _err_info("ico: empty image resource"); }
    if (size > n) { return _err_info("ico: entry size out of bounds"); }
    let offset = _le32(data, base + 12);
    if (offset < info.dir_bytes) {
      return _err_info("ico: image data overlaps directory");
    }
    if (offset + size > n) {
      return _err_info("ico: image data out of bounds");
    }
    i = i + 1;
  }
  return _ok_info(info);
}

// --------------------------------------------------
//  Entry and payload accessors
// --------------------------------------------------

/// Decode directory entry `i` of an ICO/CUR buffer.
///
/// Runs the full ico_parse validation first and forwards its messages, then
/// returns Err("ico: entry index out of range") when `i` is negative or at
/// least the image count. Dimensions are decoded: an on-disk 0 reads back
/// as 256. Complexity: O(count) validation plus O(1) decode.
pub fn ico_entry(data: &Vec[UInt8], i: Int) -> Result[IcoEntry, Str] {
  let pp = ico_parse(data);
  if (!pp.is_ok) { return _err_entry(pp.error); }
  let info: IcoInfo = pp.value;
  if (i < 0 || i >= info.count) {
    return _err_entry("ico: entry index out of range");
  }
  let base = 6 + i * 16;
  let e = IcoEntry{
    width: _entry_dim(_b(data, base));
    height: _entry_dim(_b(data, base + 1));
    color_count: _b(data, base + 2);
    planes: _le16(data, base + 4);
    bits: _le16(data, base + 6);
    bytes: _le32(data, base + 8);
    offset: _le32(data, base + 12);
  };
  return _ok_entry(e);
}

/// Copy the image resource of entry `i`: exactly `bytes` bytes starting at
/// the entry's `offset`, as declared in the validated directory.
///
/// Validation errors of ico_entry (including
/// Err("ico: entry index out of range")) are forwarded unchanged. The copy
/// is a pass-through: payload bytes are never interpreted. Complexity:
/// O(count) validation plus O(bytes).
pub fn ico_image_data(data: &Vec[UInt8], i: Int) -> Result[Vec[UInt8], Str] {
  let ep = ico_entry(data, i);
  if (!ep.is_ok) { return _err_bytes(ep.error); }
  let e: IcoEntry = ep.value;
  let out = Vec[UInt8].new();
  var k = 0;
  while (k < e.bytes) {
    out.push(data[e.offset + k]);
    k = k + 1;
  }
  return _ok_bytes(out);
}

// --------------------------------------------------
//  Classification helpers
// --------------------------------------------------

/// True when the buffer carries a header that ico_parse_header accepts with
/// resource type 1 (icon). Malformed headers return false rather than an
/// error; use ico_parse_header when the reason matters.
pub fn ico_is_ico(data: &Vec[UInt8]) -> Bool {
  let hp = ico_parse_header(data);
  if (!hp.is_ok) { return false; }
  let info: IcoInfo = hp.value;
  return info.kind == 1;
}

/// True when the buffer carries a header that ico_parse_header accepts with
/// resource type 2 (cursor). Malformed headers return false rather than an
/// error; use ico_parse_header when the reason matters.
pub fn ico_is_cur(data: &Vec[UInt8]) -> Bool {
  let hp = ico_parse_header(data);
  if (!hp.is_ok) { return false; }
  let info: IcoInfo = hp.value;
  return info.kind == 2;
}

// --------------------------------------------------
//  Builder
// --------------------------------------------------

/// Create an empty builder for `kind`: ICO_TYPE_ICON for an .ico container
/// or ICO_TYPE_CURSOR for a .cur container. Any other kind (including a
/// negative one) is Err("ico: unknown resource type").
pub fn ico_builder_new(kind: Int) -> Result[IcoBuilder, Str] {
  if (kind != 1 && kind != 2) {
    return _err_builder("ico: unknown resource type");
  }
  let b = IcoBuilder{
    kind: kind;
    widths: Vec[Int].new();
    heights: Vec[Int].new();
    color_counts: Vec[Int].new();
    planes: Vec[Int].new();
    bits: Vec[Int].new();
    sizes: Vec[Int].new();
    payload: Vec[UInt8].new();
  };
  return _ok_builder(b);
}

/// Number of images appended so far. Complexity: O(1).
pub fn ico_builder_count(b: &IcoBuilder) -> Int {
  return b.widths.len();
}

/// Resource type of the builder: ICO_TYPE_ICON or ICO_TYPE_CURSOR.
/// Complexity: O(1).
pub fn ico_builder_kind(b: &IcoBuilder) -> Int {
  return b.kind;
}

// Validate one image description and append it, returning the new count.
// The builder is unchanged on Err.
fn _append_entry(b: &mut IcoBuilder, image: &Vec[UInt8], width: Int, height: Int, color_count: Int, planes: Int, bits: Int) -> Result[Int, Str] {
  if (width < 1 || width > 256) { return _err_int("ico: invalid width"); }
  if (height < 1 || height > 256) { return _err_int("ico: invalid height"); }
  if (color_count < 0 || color_count > 255) {
    return _err_int("ico: invalid color count");
  }
  if (planes < 0 || planes > 65535) {
    return _err_int("ico: invalid planes or hotspot x");
  }
  if (bits < 0 || bits > 65535) {
    return _err_int("ico: invalid bit count or hotspot y");
  }
  if (image.len() == 0) { return _err_int("ico: empty image resource"); }
  if (image.len() > 4294967295) {
    return _err_int("ico: image resource too large");
  }
  if (b.widths.len() >= 65535) { return _err_int("ico: too many images"); }
  b.widths.push(width);
  b.heights.push(height);
  b.color_counts.push(color_count);
  b.planes.push(planes);
  b.bits.push(bits);
  b.sizes.push(image.len());
  _push_bytes(&mut b.payload, image);
  return _ok_int(b.widths.len());
}

/// Append one icon image to an ICO builder and return the new image count
/// (1-based). `image` is any non-empty resource payload -- a PNG file, a
/// DIB, or a legacy bitmap -- and is stored verbatim; `width` and `height`
/// are 1..256 (256 is written as the on-disk 0 sentinel); `color_count` is
/// 0..255; `planes` is the color-plane count and `bit_count` the bits per
/// pixel, both 0..65535.
///
/// Err("ico: not an icon builder") when the builder kind is cursor;
/// otherwise the append catalog: Err("ico: invalid width"),
/// Err("ico: invalid height"), Err("ico: invalid color count"),
/// Err("ico: invalid planes or hotspot x"),
/// Err("ico: invalid bit count or hotspot y"),
/// Err("ico: empty image resource"),
/// Err("ico: image resource too large"),
/// Err("ico: too many images") (the on-disk count is 16-bit, so at most
/// 65535 images are accepted). The builder is unchanged on every Err.
/// Complexity: O(image.len()).
pub fn ico_builder_add(b: &mut IcoBuilder, image: &Vec[UInt8], width: Int, height: Int, color_count: Int, planes: Int, bit_count: Int) -> Result[Int, Str] {
  if (b.kind != 1) { return _err_int("ico: not an icon builder"); }
  return _append_entry(b, image, width, height, color_count, planes, bit_count);
}

/// Append one cursor image to a CUR builder and return the new image count
/// (1-based). Field ranges match ico_builder_add; `hotspot_x` and
/// `hotspot_y` are the cursor hotspot coordinates (0..65535) and are stored
/// in the on-disk planes and bit-count words.
///
/// Err("ico: not a cursor builder") when the builder kind is icon;
/// otherwise the same append catalog as ico_builder_add. The builder is
/// unchanged on every Err. Complexity: O(image.len()).
pub fn ico_builder_add_cursor(b: &mut IcoBuilder, image: &Vec[UInt8], width: Int, height: Int, color_count: Int, hotspot_x: Int, hotspot_y: Int) -> Result[Int, Str] {
  if (b.kind != 2) { return _err_int("ico: not a cursor builder"); }
  return _append_entry(b, image, width, height, color_count, hotspot_x, hotspot_y);
}

/// Emit the canonical ICO/CUR byte image: the 6-byte header, one 16-byte
/// entry per appended image, then every payload in append order.
///
/// Count and offsets are recomputed from scratch: the directory starts at
/// byte 6, the first resource at `6 + 16 * count`, and each next resource
/// immediately after the previous one. Dimensions of 256 are written as the
/// 0 sentinel and the reserved bytes (both header and per-entry) are
/// written as zero. Emitting twice yields identical bytes.
///
/// Err("ico: zero image count") for an empty builder. The remaining errors
/// guard against direct mutation of the public builder fields:
/// Err("ico: builder is inconsistent") when the parallel vectors disagree
/// or the payload length does not equal the sum of the recorded sizes,
/// Err("ico: unknown resource type") for a corrupted kind, then the append
/// catalog (invalid width/height/color count/planes/hotspot/bit count,
/// empty image resource) for a corrupted entry. Complexity: O(payload).
pub fn ico_builder_emit(b: &IcoBuilder) -> Result[Vec[UInt8], Str] {
  let count = b.widths.len();
  if (count == 0) { return _err_bytes("ico: zero image count"); }
  if (b.heights.len() != count) {
    return _err_bytes("ico: builder is inconsistent");
  }
  if (b.color_counts.len() != count) {
    return _err_bytes("ico: builder is inconsistent");
  }
  if (b.planes.len() != count) {
    return _err_bytes("ico: builder is inconsistent");
  }
  if (b.bits.len() != count) {
    return _err_bytes("ico: builder is inconsistent");
  }
  if (b.sizes.len() != count) {
    return _err_bytes("ico: builder is inconsistent");
  }
  if (b.kind != 1 && b.kind != 2) {
    return _err_bytes("ico: unknown resource type");
  }
  var total = 0;
  var i = 0;
  while (i < count) {
    let sz: Int = b.sizes[i];
    if (sz <= 0) { return _err_bytes("ico: empty image resource"); }
    total = total + sz;
    i = i + 1;
  }
  if (total != b.payload.len()) {
    return _err_bytes("ico: builder is inconsistent");
  }
  i = 0;
  while (i < count) {
    let w: Int = b.widths[i];
    let h: Int = b.heights[i];
    let cc: Int = b.color_counts[i];
    let pl: Int = b.planes[i];
    let bt: Int = b.bits[i];
    if (w < 1 || w > 256) { return _err_bytes("ico: invalid width"); }
    if (h < 1 || h > 256) { return _err_bytes("ico: invalid height"); }
    if (cc < 0 || cc > 255) {
      return _err_bytes("ico: invalid color count");
    }
    if (pl < 0 || pl > 65535) {
      return _err_bytes("ico: invalid planes or hotspot x");
    }
    if (bt < 0 || bt > 65535) {
      return _err_bytes("ico: invalid bit count or hotspot y");
    }
    i = i + 1;
  }
  let out = Vec[UInt8].new();
  out.push(0 as UInt8);                 // reserved low
  out.push(0 as UInt8);                 // reserved high
  _p16(&mut out, b.kind);               // type
  _p16(&mut out, count);                // image count
  var offset = 6 + count * 16;
  i = 0;
  while (i < count) {
    let w: Int = b.widths[i];
    let h: Int = b.heights[i];
    let cc: Int = b.color_counts[i];
    let pl: Int = b.planes[i];
    let bt: Int = b.bits[i];
    let sz: Int = b.sizes[i];
    out.push(_dim_byte(w) as UInt8);
    out.push(_dim_byte(h) as UInt8);
    out.push(cc as UInt8);
    out.push(0 as UInt8);               // entry reserved
    _p16(&mut out, pl);
    _p16(&mut out, bt);
    _p32(&mut out, sz);
    _p32(&mut out, offset);
    offset = offset + sz;
    i = i + 1;
  }
  var p = 0;
  while (p < b.payload.len()) {
    let byte: UInt8 = b.payload[p];
    out.push(byte);
    p = p + 1;
  }
  return _ok_bytes(out);
}
