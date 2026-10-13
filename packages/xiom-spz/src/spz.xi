// XIOM -- xiom.spz: nianticlabs/spz (Gaussian-splat compression) bindings.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Public safe API over the vendored spz C++ library at pin v3.0.0
// (5bf2945de1a003cee07133b1e495fe9c6ffdc7e7, MIT).  This module contains no
// `unsafe`: every foreign call goes through the confined FFI core in
// `xiom.spz.ffi` (G5).  Math helpers bound to the public spz math surface
// live in `xiom.spz.math`.
//
// Model: an unpacked Gaussian cloud is a caller-owned float workspace whose
// stream layout is SPZ_STREAM_* / spz_work_offset (see SPEC.md).  Pack/unpack
// cross the FFI as that one owned buffer, so no pointer ever round-trips
// through XIOM (B-17/B-20/B-24/B-25 discipline).
//
// Error model: fallible calls return Result[_, SpzError] with a typed code
// (SPZ_ERR_*) and a stable message; the codes mirror src/spz_bridge.cpp.

module xiom.spz

use xiom.spz.ffi;

// --- header constants (spz v3.0.0, load-spz.h) ------------------------------

pub const SPZ_LATEST_HEADER_VERSION: Int = 4;
pub const SPZ_MIN_ZSTD_HEADER_VERSION: Int = 4;
pub const SPZ_MIN_SMALLEST_THREE_VERSION: Int = 3;
pub const SPZ_SH_MAX_DEGREE: Int = 4;
pub const SPZ_SH_MAX_COEFFS: Int = 24;
pub const SPZ_DEFAULT_SH1_BITS: Int = 5;
pub const SPZ_DEFAULT_SH_REST_BITS: Int = 4;
pub const SPZ_NGSP_MAGIC: Int = 1347635022;
pub const SPZ_PACKED_GAUSSIAN_BYTES: Int = 92;
pub const SPZ_UNPACKED_FLOATS: Int = 86;

// --- CoordinateSystem values (splat-types.h) --------------------------------

pub const SPZ_COORD_UNSPECIFIED: Int = 0;
pub const SPZ_COORD_LDB: Int = 1;
pub const SPZ_COORD_RDB: Int = 2;
pub const SPZ_COORD_LUB: Int = 3;
pub const SPZ_COORD_RUB: Int = 4;
pub const SPZ_COORD_LDF: Int = 5;
pub const SPZ_COORD_RDF: Int = 6;
pub const SPZ_COORD_LUF: Int = 7;
pub const SPZ_COORD_RUF: Int = 8;

// --- workspace streams ------------------------------------------------------

pub const SPZ_STREAM_POSITIONS: Int = 0;
pub const SPZ_STREAM_SCALES: Int = 1;
pub const SPZ_STREAM_ROTATIONS: Int = 2;
pub const SPZ_STREAM_ALPHAS: Int = 3;
pub const SPZ_STREAM_COLORS: Int = 4;
pub const SPZ_STREAM_SH: Int = 5;
pub const SPZ_STREAM_COUNT: Int = 6;

// --- PackedGaussian raw byte offsets (92 bytes, static_assert-pinned) -------

pub const SPZ_PACKED_OFF_POSITION: Int = 0;
pub const SPZ_PACKED_OFF_ROTATION: Int = 9;
pub const SPZ_PACKED_OFF_SCALE: Int = 13;
pub const SPZ_PACKED_OFF_COLOR: Int = 16;
pub const SPZ_PACKED_OFF_ALPHA: Int = 19;
pub const SPZ_PACKED_OFF_SHR: Int = 20;
pub const SPZ_PACKED_OFF_SHG: Int = 44;
pub const SPZ_PACKED_OFF_SHB: Int = 68;

// --- UnpackedGaussian flat float offsets (86 floats) ------------------------

pub const SPZ_UNPACKED_OFF_POSITION: Int = 0;
pub const SPZ_UNPACKED_OFF_ROTATION: Int = 3;
pub const SPZ_UNPACKED_OFF_SCALE: Int = 7;
pub const SPZ_UNPACKED_OFF_COLOR: Int = 10;
pub const SPZ_UNPACKED_OFF_ALPHA: Int = 13;
pub const SPZ_UNPACKED_OFF_SHR: Int = 14;
pub const SPZ_UNPACKED_OFF_SHG: Int = 38;
pub const SPZ_UNPACKED_OFF_SHB: Int = 62;

// --- error codes (mirror src/spz_bridge.cpp; keep in sync) ------------------

pub const SPZ_OK: Int = 0;
pub const SPZ_ERR_BAD_ARGS: Int = -1;
pub const SPZ_ERR_MAGIC: Int = -2;
pub const SPZ_ERR_VERSION: Int = -3;
pub const SPZ_ERR_DECOMPRESS: Int = -4;
pub const SPZ_ERR_TRUNCATED: Int = -5;
pub const SPZ_ERR_BAD_HEADER: Int = -6;
pub const SPZ_ERR_CAPACITY: Int = -7;
pub const SPZ_ERR_INTERNAL: Int = -8;

// --- types ------------------------------------------------------------------

pub type SpzError = {
  code: Int;
  message: Str;
}

pub fn SpzError.new(code: Int, message: Str) -> SpzError {
  return SpzError{ code: code, message: message };
}

pub type SpzBytes = {
  bytes: Vec[UInt8];
}

pub fn SpzBytes.new() -> SpzBytes {
  return SpzBytes{ bytes: Vec[UInt8].new() };
}

pub type SpzMeta = {
  version: Int;
  num_points: Int;
  sh_degree: Int;
  fractional_bits: Int;
  antialiased: Bool;
  uses_smallest_three: Bool;
  uses_float16: Bool;
}

pub fn SpzMeta.new() -> SpzMeta {
  return SpzMeta{
    version: 0, num_points: 0, sh_degree: 0, fractional_bits: 0,
    antialiased: false, uses_smallest_three: false, uses_float16: false
  };
}

pub type SpzCloud = {
  num_points: Int;
  sh_degree: Int;
  antialiased: Bool;
  work: Vec[Float32];
}

pub fn SpzCloud.new() -> SpzCloud {
  return SpzCloud{ num_points: 0, sh_degree: 0, antialiased: false, work: Vec[Float32].new() };
}

pub type SpzPackedGaussian = {
  raw: Vec[UInt8];
}

pub fn SpzPackedGaussian.new() -> SpzPackedGaussian {
  return SpzPackedGaussian{ raw: Vec[UInt8].new() };
}

pub type SpzUnpackedGaussian = {
  fields: Vec[Float32];
}

pub fn SpzUnpackedGaussian.new() -> SpzUnpackedGaussian {
  return SpzUnpackedGaussian{ fields: Vec[Float32].new() };
}

pub type SpzAxes = {
  x: Bool;
  y: Bool;
  z: Bool;
}

pub fn SpzAxes.new() -> SpzAxes {
  return SpzAxes{ x: false, y: false, z: false };
}

// --- helpers ----------------------------------------------------------------

/// SH coefficient count for a degree (0, 3, 8, 15, 24), or -1 when invalid.
/// Complexity: O(1).
pub fn spz_dim_for_degree(degree: Int) -> Int {
  if degree == 0 { return 0; }
  if degree == 1 { return 3; }
  if degree == 2 { return 8; }
  if degree == 3 { return 15; }
  if degree == 4 { return 24; }
  return -1;
}

/// Float count of the unpacked workspace: 14n + 3*dim*n.
/// Complexity: O(1).
pub fn spz_work_size(num_points: Int, sh_degree: Int) -> Int {
  let dim = spz_dim_for_degree(sh_degree);
  if dim < 0 || num_points < 0 { return -1; }
  return 14 * num_points + 3 * dim * num_points;
}

/// First float index of a workspace stream, or -1 for an unknown stream.
/// Complexity: O(1).
pub fn spz_work_offset(stream: Int, num_points: Int, sh_degree: Int) -> Int {
  if stream == SPZ_STREAM_POSITIONS { return 0; }
  if stream == SPZ_STREAM_SCALES { return 3 * num_points; }
  if stream == SPZ_STREAM_ROTATIONS { return 6 * num_points; }
  if stream == SPZ_STREAM_ALPHAS { return 10 * num_points; }
  if stream == SPZ_STREAM_COLORS { return 11 * num_points; }
  if stream == SPZ_STREAM_SH { return 14 * num_points; }
  return -1;
}

/// Byte of a SpzPackedGaussian raw record.
/// Complexity: O(1).
pub fn spz_packed_byte(g: &SpzPackedGaussian, i: Int) -> Int {
  return g.raw[i] as Int;
}

/// Float field of a SpzUnpackedGaussian record.
/// Complexity: O(1).
pub fn spz_unpacked_field(u: &SpzUnpackedGaussian, i: Int) -> Float32 {
  return u.fields[i];
}

/// Stable name for an spz bridge error code.
/// Complexity: O(1).
pub fn spz_error_name(code: Int) -> Str {
  if code == SPZ_OK { return "ok"; }
  if code == SPZ_ERR_BAD_ARGS { return "spz: bad arguments"; }
  if code == SPZ_ERR_MAGIC { return "spz: not an spz file (bad magic)"; }
  if code == SPZ_ERR_VERSION { return "spz: unsupported header version"; }
  if code == SPZ_ERR_DECOMPRESS { return "spz: decompression failed"; }
  if code == SPZ_ERR_TRUNCATED { return "spz: truncated input"; }
  if code == SPZ_ERR_BAD_HEADER { return "spz: malformed header"; }
  if code == SPZ_ERR_CAPACITY { return "spz: output capacity too small"; }
  if code == SPZ_ERR_INTERNAL { return "spz: internal error"; }
  return "spz: unknown error";
}

/// Typed error for a bridge code.
/// Complexity: O(1).
pub fn spz_error(code: Int) -> SpzError {
  return SpzError.new(code, spz_error_name(code));
}

// --- constants evidence -----------------------------------------------------

/// True when the runtime bridge constants match the module constants.
/// Complexity: O(1).
pub fn spz_constants_match() -> Bool {
  var slot = ffi.zero_bytes(64);
  let rc = ffi.constants(&mut slot);
  if rc != 0 { return false; }
  if ffi.read_u64_le(&slot, 0) != SPZ_LATEST_HEADER_VERSION { return false; }
  if ffi.read_u64_le(&slot, 8) != SPZ_MIN_ZSTD_HEADER_VERSION { return false; }
  if ffi.read_u64_le(&slot, 16) != SPZ_MIN_SMALLEST_THREE_VERSION { return false; }
  if ffi.read_u64_le(&slot, 24) != SPZ_SH_MAX_DEGREE { return false; }
  if ffi.read_u64_le(&slot, 32) != SPZ_SH_MAX_COEFFS { return false; }
  if ffi.read_u64_le(&slot, 40) != SPZ_DEFAULT_SH1_BITS { return false; }
  if ffi.read_u64_le(&slot, 48) != SPZ_DEFAULT_SH_REST_BITS { return false; }
  if ffi.read_u64_le(&slot, 56) != SPZ_NGSP_MAGIC { return false; }
  return true;
}

/// True when the runtime CoordinateSystem values are 0..8 in order.
/// Complexity: O(1).
pub fn spz_coordinate_values_match() -> Bool {
  var slot = ffi.zero_bytes(72);
  let rc = ffi.coordinate_values(&mut slot);
  if rc != 0 { return false; }
  var i: Int = 0;
  while i < 9 {
    if ffi.read_u64_le(&slot, i * 8) != i { return false; }
    i = i + 1;
  }
  return true;
}

/// Runtime extension-support flag (false: the pinned build has extensions off).
/// Complexity: O(1).
pub fn spz_has_extension_support() -> Bool {
  return ffi.extension_support() != 0;
}

/// CoordinateSystem axis-match triple (axesMatch).
/// Complexity: O(1).
pub fn spz_axes_match(a: Int, b: Int) -> SpzAxes {
  var slot = ffi.zero_bytes(24);
  let rc = ffi.axes_match(a, b, &mut slot);
  if rc != 0 { return SpzAxes.new(); }
  return SpzAxes{
    x: ffi.read_u64_le(&slot, 0) != 0,
    y: ffi.read_u64_le(&slot, 8) != 0,
    z: ffi.read_u64_le(&slot, 16) != 0
  };
}

/// CoordinateConverter for (from, to): 30 floats = flipP(3) + flipQ(3) +
/// flipSh(24).
/// Complexity: O(1).
pub fn spz_coordinate_converter(from_coord: Int, to_coord: Int) -> Result[Vec[Float32], SpzError] {
  var out = ffi.zero_floats(30);
  let rc = ffi.coordinate_converter(from_coord, to_coord, &mut out);
  if rc != 0 { return Err(spz_error(rc)); }
  return Ok(out);
}

// --- pack / unpack ----------------------------------------------------------

/// Pack an unpacked workspace into an `.spz` container.
/// Complexity: O(num_points) plus compression work.
pub fn spz_pack(work: &mut Vec[Float32], num_points: Int, sh_degree: Int, antialiased: Bool,
    version: Int, from_coord: Int, sh1_bits: Int, sh_rest_bits: Int) -> Result[SpzBytes, SpzError]
  requires: num_points > 0
{
  if version < 1 { return Err(spz_error(SPZ_ERR_VERSION)); }
  if version > SPZ_LATEST_HEADER_VERSION { return Err(spz_error(SPZ_ERR_VERSION)); }
  let cap = num_points * 128 + 4096;
  var out = ffi.zero_bytes(cap);
  let rc = ffi.pack(work, num_points, sh_degree, antialiased, version, from_coord, sh1_bits,
    sh_rest_bits, &mut out);
  if rc < 0 { return Err(spz_error(rc)); }
  if rc > cap { return Err(spz_error(SPZ_ERR_CAPACITY)); }
  var bytes: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < rc {
    bytes.push(out[i]);
    i = i + 1;
  }
  return Ok(SpzBytes{ bytes: bytes });
}

/// Metadata of a packed container (NGSP v4 or legacy gzip v1-3).
/// Complexity: O(num_points).
pub fn spz_load_packed(data: &mut Vec[UInt8]) -> Result[SpzMeta, SpzError] {
  var slot = ffi.zero_bytes(64);
  let rc = ffi.load_packed(data, &mut slot);
  if rc != 0 { return Err(spz_error(rc)); }
  return Ok(SpzMeta{
    version: ffi.read_u64_le(&slot, 0),
    num_points: ffi.read_u64_le(&slot, 8),
    sh_degree: ffi.read_u64_le(&slot, 16),
    fractional_bits: ffi.read_u64_le(&slot, 24),
    antialiased: ffi.read_u64_le(&slot, 32) != 0,
    uses_smallest_three: ffi.read_u64_le(&slot, 40) != 0,
    uses_float16: ffi.read_u64_le(&slot, 48) != 0
  });
}

/// Unpack a packed container into a fresh owned workspace, converting to
/// `to_coord` (SPZ_COORD_UNSPECIFIED keeps the stored RUB orientation).
/// Complexity: O(num_points) plus decompression work.
pub fn spz_unpack(data: &mut Vec[UInt8], to_coord: Int) -> Result[SpzCloud, SpzError] {
  let meta = spz_load_packed(data);
  if !meta.is_ok { return Err(meta.error); }
  let m = meta.value;
  let need = spz_work_size(m.num_points, m.sh_degree);
  if need <= 0 { return Err(spz_error(SPZ_ERR_BAD_HEADER)); }
  var work = ffi.zero_floats(need);
  var slot = ffi.zero_bytes(32);
  let rc = ffi.unpack(data, to_coord, &mut slot, &mut work);
  if rc != 0 { return Err(spz_error(rc)); }
  return Ok(SpzCloud{
    num_points: ffi.read_u64_le(&slot, 0),
    sh_degree: ffi.read_u64_le(&slot, 8),
    antialiased: ffi.read_u64_le(&slot, 16) != 0,
    work: work
  });
}

/// PackedGaussian::at(index): the 92-byte raw record.
/// Complexity: O(num_points).
pub fn spz_packed_gaussian(data: &mut Vec[UInt8], index: Int) -> Result[SpzPackedGaussian, SpzError] {
  var out = ffi.zero_bytes(SPZ_PACKED_GAUSSIAN_BYTES);
  let rc = ffi.packed_gaussian(data, index, &mut out);
  if rc != 0 { return Err(spz_error(rc)); }
  return Ok(SpzPackedGaussian{ raw: out });
}

/// PackedGaussian::unpack(index, converter): 86 floats in the documented
/// SPZ_UNPACKED_OFF_* layout.
/// Complexity: O(num_points).
pub fn spz_packed_gaussian_unpack(data: &mut Vec[UInt8], index: Int,
    to_coord: Int) -> Result[SpzUnpackedGaussian, SpzError] {
  var out = ffi.zero_floats(SPZ_UNPACKED_FLOATS);
  let rc = ffi.packed_gaussian_unpack(data, index, to_coord, &mut out);
  if rc != 0 { return Err(spz_error(rc)); }
  return Ok(SpzUnpackedGaussian{ fields: out });
}

// --- files ------------------------------------------------------------------

/// saveSpz(cloud, options, filename).
/// Complexity: O(num_points) plus compression work.
pub fn spz_save_file(path: Str, work: &mut Vec[Float32], num_points: Int, sh_degree: Int,
    antialiased: Bool, version: Int, from_coord: Int, sh1_bits: Int,
    sh_rest_bits: Int) -> Result[Bool, SpzError]
  requires: num_points > 0
{
  var p = ffi.cpath(path);
  let rc = ffi.save_file(&mut p, work, num_points, sh_degree, antialiased, version, from_coord,
    sh1_bits, sh_rest_bits);
  if rc != 0 { return Err(spz_error(rc)); }
  return Ok(true);
}

/// loadSpz(filename, options): two-phase (a capacity probe sizes the owned
/// workspace from the file header, then the load fills it).
/// Complexity: O(num_points) plus decompression work.
pub fn spz_load_file(path: Str, to_coord: Int) -> Result[SpzCloud, SpzError] {
  var p = ffi.cpath(path);
  var probe_slot = ffi.zero_bytes(32);
  var one = ffi.zero_floats(1);
  let probe = ffi.load_file(&mut p, to_coord, &mut probe_slot, &mut one);
  if probe != SPZ_ERR_CAPACITY { return Err(spz_error(probe)); }
  let num_points = ffi.read_u64_le(&probe_slot, 0);
  let sh_degree = ffi.read_u64_le(&probe_slot, 8);
  let need = spz_work_size(num_points, sh_degree);
  if need <= 0 { return Err(spz_error(SPZ_ERR_BAD_HEADER)); }
  var work = ffi.zero_floats(need);
  var slot = ffi.zero_bytes(32);
  let rc = ffi.load_file(&mut p, to_coord, &mut slot, &mut work);
  if rc != 0 { return Err(spz_error(rc)); }
  return Ok(SpzCloud{
    num_points: ffi.read_u64_le(&slot, 0),
    sh_degree: ffi.read_u64_le(&slot, 8),
    antialiased: ffi.read_u64_le(&slot, 16) != 0,
    work: work
  });
}

/// saveSplatToPly(cloud, options, filename).
/// Complexity: O(num_points).
pub fn spz_save_ply(path: Str, work: &mut Vec[Float32], num_points: Int, sh_degree: Int,
    antialiased: Bool, version: Int, from_coord: Int, sh1_bits: Int,
    sh_rest_bits: Int) -> Result[Bool, SpzError]
  requires: num_points > 0
{
  var p = ffi.cpath(path);
  let rc = ffi.save_ply(&mut p, work, num_points, sh_degree, antialiased, version, from_coord,
    sh1_bits, sh_rest_bits);
  if rc != 0 { return Err(spz_error(rc)); }
  return Ok(true);
}

/// loadSplatFromPly(filename, options).
/// Complexity: O(num_points).
pub fn spz_load_ply(path: Str, to_coord: Int) -> Result[SpzCloud, SpzError] {
  var p = ffi.cpath(path);
  var probe_slot = ffi.zero_bytes(32);
  var one = ffi.zero_floats(1);
  let probe = ffi.load_ply(&mut p, to_coord, &mut probe_slot, &mut one);
  if probe != SPZ_ERR_CAPACITY { return Err(spz_error(probe)); }
  let num_points = ffi.read_u64_le(&probe_slot, 0);
  let sh_degree = ffi.read_u64_le(&probe_slot, 8);
  let need = spz_work_size(num_points, sh_degree);
  if need <= 0 { return Err(spz_error(SPZ_ERR_BAD_HEADER)); }
  var work = ffi.zero_floats(need);
  var slot = ffi.zero_bytes(32);
  let rc = ffi.load_ply(&mut p, to_coord, &mut slot, &mut work);
  if rc != 0 { return Err(spz_error(rc)); }
  return Ok(SpzCloud{
    num_points: ffi.read_u64_le(&slot, 0),
    sh_degree: ffi.read_u64_le(&slot, 8),
    antialiased: ffi.read_u64_le(&slot, 16) != 0,
    work: work
  });
}

// --- serialize / gzip -------------------------------------------------------

/// serializePackedGaussians: legacy single-stream bytes (16-byte header +
/// attribute streams).  This is exactly the payload a v1-3 gzip container
/// wraps (see the round-trip test).
/// Complexity: O(num_points).
pub fn spz_serialize_packed(data: &mut Vec[UInt8]) -> Result[SpzBytes, SpzError] {
  let meta = spz_load_packed(data);
  if !meta.is_ok { return Err(meta.error); }
  let m = meta.value;
  let dim = spz_dim_for_degree(m.sh_degree);
  if dim < 0 { return Err(spz_error(SPZ_ERR_BAD_HEADER)); }
  let cap = 16 + (20 + 3 * dim) * m.num_points + 1024;
  var out = ffi.zero_bytes(cap);
  let rc = ffi.serialize_packed(data, &mut out);
  if rc < 0 { return Err(spz_error(rc)); }
  if rc > cap { return Err(spz_error(SPZ_ERR_CAPACITY)); }
  var bytes: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < rc {
    bytes.push(out[i]);
    i = i + 1;
  }
  return Ok(SpzBytes{ bytes: bytes });
}

/// compressGzipped: GZIP (RFC 1952) of raw bytes.
/// Complexity: O(len) plus compression work.
pub fn spz_compress_gzipped(data: &mut Vec[UInt8]) -> Result[SpzBytes, SpzError] {
  let cap = data.len() / 4 + data.len() + 65536;
  var out = ffi.zero_bytes(cap);
  let rc = ffi.compress_gzipped(data, &mut out);
  if rc < 0 { return Err(spz_error(rc)); }
  if rc > cap { return Err(spz_error(SPZ_ERR_CAPACITY)); }
  var bytes: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < rc {
    bytes.push(out[i]);
    i = i + 1;
  }
  return Ok(SpzBytes{ bytes: bytes });
}

// --- GaussianCloud methods --------------------------------------------------

/// GaussianCloud::data(): copy every stream (counts + payload) into a fresh
/// owned workspace.
/// Complexity: O(num_points).
pub fn spz_cloud_data(work: &mut Vec[Float32], num_points: Int, sh_degree: Int,
    antialiased: Bool) -> Result[SpzCloud, SpzError]
  requires: num_points > 0
{
  let need = spz_work_size(num_points, sh_degree);
  if need <= 0 { return Err(spz_error(SPZ_ERR_BAD_HEADER)); }
  var out = ffi.zero_floats(need);
  let rc = ffi.cloud_data(work, num_points, sh_degree, antialiased, &mut out);
  if rc != 0 { return Err(spz_error(rc)); }
  return Ok(SpzCloud{
    num_points: num_points, sh_degree: sh_degree, antialiased: antialiased, work: out
  });
}

/// GaussianCloud::convertCoordinates(from, to), in place.
/// Complexity: O(num_points).
pub fn spz_cloud_convert(work: &mut Vec[Float32], num_points: Int, sh_degree: Int,
    from_coord: Int, to_coord: Int) -> Result[Bool, SpzError]
  requires: num_points > 0
{
  let rc = ffi.cloud_convert(work, num_points, sh_degree, from_coord, to_coord);
  if rc != 0 { return Err(spz_error(rc)); }
  return Ok(true);
}

/// GaussianCloud::rotate180DegAboutX(), in place (RUB <-> RDF).
/// Complexity: O(num_points).
pub fn spz_cloud_rotate180(work: &mut Vec[Float32], num_points: Int,
    sh_degree: Int) -> Result[Bool, SpzError]
  requires: num_points > 0
{
  let rc = ffi.cloud_rotate180(work, num_points, sh_degree);
  if rc != 0 { return Err(spz_error(rc)); }
  return Ok(true);
}

/// GaussianCloud::medianVolume() (ellipsoid volume at the median log-scale).
/// Complexity: O(num_points).
pub fn spz_median_volume(work: &mut Vec[Float32], num_points: Int, sh_degree: Int) -> Float32
  requires: num_points > 0
{
  return ffi.median_volume(work, num_points, sh_degree);
}
