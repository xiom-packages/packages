// XIOM -- xiom.stl: STL mesh structure -- binary triangle parsing and
// ASCII detection; IEEE-754 values are exposed as raw 32-bit bit patterns.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Binary STL layout: 80-byte header, little-endian u32 triangle count at
// offset 80, then 50 bytes per triangle: the normal (3 x f32), three
// vertices (3 x 3 x f32) and a trailing u16 attribute byte count:
//
//   [0,80)      header (free-form, not interpreted)
//   [80,84)     triangle count, LE u32
//   [84+50i, 96+50i)    normal x, y, z (3 x LE f32)
//   [96+50i, 132+50i)   vertex 0..2 x, y, z (9 x LE f32)
//   [132+50i, 134+50i)  attribute byte count, LE u16
//
// Total size: 84 + 50*n bytes. stl_kind classifies a buffer as binary only
// when this formula matches the exact length, so a file that starts with
// "solid" but also matches the binary size is reported as binary.
//
// Floats stay raw bits: v0.61.3 has no f32<->Int bitcast and Vec[Float64]
// is unavailable, so every accessor returns the little-endian u32 as an
// Int (0..2^32-1). Decoding IEEE-754 is caller-side (see README.md).
//
// v0.61.3 notes that shaped this module:
//   * Ok/Err construction is confined to the _ok_int/_err_int leaf helpers
//     (constructing Results directly inside other functions miscompiles).
//   * Vec[UInt8] reads are masked with & 0xFF (widening discipline).
//   * no self methods, lambdas, Vec[StructType] or Vec[fn] dispatch: the
//     module is a flat set of free functions over &Vec[UInt8].

module xiom.stl

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[Int, Str].
fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

// Err(m) for Result[Int, Str].
fn _err_int(m: Str) -> Result[Int, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Internal byte helpers
// --------------------------------------------------

// Masked byte read: Vec[UInt8] widening is not trustworthy without & 0xFF.
fn _byte(data: &Vec[UInt8], off: Int) -> Int {
  return (data[off] as Int) & 0xFF;
}

// Little-endian u16 at an absolute offset (caller checks bounds).
fn _le16(data: &Vec[UInt8], off: Int) -> Int {
  return _byte(data, off) + _byte(data, off + 1) * 256;
}

// Little-endian u32 at an absolute offset (caller checks bounds).
fn _le32(data: &Vec[UInt8], off: Int) -> Int {
  return _byte(data, off) + _byte(data, off + 1) * 256 + _byte(data, off + 2) * 65536 + _byte(data, off + 3) * 16777216;
}

// True when the buffer length equals 84 + 50*count for the declared count.
// ASCII files can coincidentally match; stl_kind resolves that in favor of
// binary (see SPEC.md).
fn _is_binary_sized(data: &Vec[UInt8]) -> Bool {
  let n = data.len();
  if n < 84 { return false; }
  let count = _le32(data, 80);
  return 84 + count * 50 == n;
}

// ASCII whitespace accepted before the "solid" keyword.
fn _is_ws(b: Int) -> Bool {
  if b == 32 { return true; }
  if b == 9 { return true; }
  if b == 10 { return true; }
  if b == 13 { return true; }
  return false;
}

// True when data starts with optional ASCII whitespace then "solid".
fn _starts_with_solid(data: &Vec[UInt8]) -> Bool {
  let n = data.len();
  var i = 0;
  while i < n && _is_ws(_byte(data, i)) {
    i = i + 1;
  }
  if n - i < 5 { return false; }
  if _byte(data, i) != 115 { return false; }      // s
  if _byte(data, i + 1) != 111 { return false; }  // o
  if _byte(data, i + 2) != 108 { return false; }  // l
  if _byte(data, i + 3) != 105 { return false; }  // i
  if _byte(data, i + 4) != 100 { return false; }  // d
  return true;
}

// --------------------------------------------------
//  Public API
// --------------------------------------------------

/// Classify a buffer: 1 = binary STL, 2 = ASCII STL (optional whitespace
/// then "solid"), 0 = unknown/short. Binary wins whenever the exact size
/// matches 84 + 50*count, even if the header starts with "solid".
pub fn stl_kind(data: &Vec[UInt8]) -> Int {
  if _is_binary_sized(data) { return 1; }
  if _starts_with_solid(data) { return 2; }
  return 0;
}

/// Number of triangles when the buffer is exactly 84 + 50*n bytes.
/// Err("stl: truncated header") when n < 84, Err("stl: truncated triangle
/// data") when the declared count needs more bytes than are present, and
/// Err("stl: trailing bytes") when the buffer is longer than declared.
pub fn stl_triangle_count(data: &Vec[UInt8]) -> Result[Int, Str] {
  let n = data.len();
  if n < 84 { return _err_int("stl: truncated header"); }
  let count = _le32(data, 80);
  let need = 84 + count * 50;
  if need > n { return _err_int("stl: truncated triangle data"); }
  if need < n { return _err_int("stl: trailing bytes"); }
  return _ok_int(count);
}

/// Little-endian u32 at an absolute offset, returned as a non-negative Int
/// holding the raw IEEE-754 bit pattern. Err("stl: offset out of range")
/// when offset < 0 or offset + 4 > data.len().
pub fn stl_float_bits(data: &Vec[UInt8], offset: Int) -> Result[Int, Str] {
  if offset < 0 { return _err_int("stl: offset out of range"); }
  if offset + 4 > data.len() { return _err_int("stl: offset out of range"); }
  return _ok_int(_le32(data, offset));
}

/// Raw bits of the normal component for triangle `tri` and axis 0..2
/// (0 = x, 1 = y, 2 = z). The triangle bounds are checked first, then the
/// axis. Err("stl: triangle out of range") / Err("stl: axis out of range").
pub fn stl_normal_bits(data: &Vec[UInt8], tri: Int, axis: Int) -> Result[Int, Str] {
  let count = stl_triangle_count(data);
  if !count.is_ok { return _err_int(count.error); }
  if tri < 0 || tri >= count.value { return _err_int("stl: triangle out of range"); }
  if axis < 0 || axis > 2 { return _err_int("stl: axis out of range"); }
  return _ok_int(_le32(data, 84 + tri * 50 + axis * 4));
}

/// Raw bits of vertex `vertex` (0..2) component `axis` (0..2) for triangle
/// `tri`. The triangle bounds are checked first, then the vertex, then the
/// axis. Err("stl: triangle out of range") / Err("stl: vertex out of
/// range") / Err("stl: axis out of range").
pub fn stl_vertex_bits(data: &Vec[UInt8], tri: Int, vertex: Int, axis: Int) -> Result[Int, Str] {
  let count = stl_triangle_count(data);
  if !count.is_ok { return _err_int(count.error); }
  if tri < 0 || tri >= count.value { return _err_int("stl: triangle out of range"); }
  if vertex < 0 || vertex > 2 { return _err_int("stl: vertex out of range"); }
  if axis < 0 || axis > 2 { return _err_int("stl: axis out of range"); }
  return _ok_int(_le32(data, 84 + tri * 50 + 12 + vertex * 12 + axis * 4));
}

/// Trailing u16 attribute byte count for triangle `tri` (0..65535).
/// Err("stl: triangle out of range") when the index is outside the
/// declared triangles.
pub fn stl_attribute(data: &Vec[UInt8], tri: Int) -> Result[Int, Str] {
  let count = stl_triangle_count(data);
  if !count.is_ok { return _err_int(count.error); }
  if tri < 0 || tri >= count.value { return _err_int("stl: triangle out of range"); }
  return _ok_int(_le16(data, 84 + tri * 50 + 48));
}

/// Exact binary size for `triangles` triangles: 84 + 50*n. Negative counts
/// return 0 (documented sentinel; callers must treat 0 as "no binary").
pub fn stl_binary_size(triangles: Int) -> Int {
  if triangles < 0 { return 0; }
  return 84 + triangles * 50;
}
