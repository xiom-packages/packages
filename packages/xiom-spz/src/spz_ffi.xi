// xiom.spz.ffi -- confined FFI core for xiom.spz (G5: the ONLY module in the
// package with `extern "C"` declarations; every foreign call is wrapped here).
//
// Bridge: src/spz_bridge.cpp (our code, MIT OR Apache-2.0) over the vendored
// spz C++ API at pin v3.0.0 (5bf2945de1a003cee07133b1e495fe9c6ffdc7e7, MIT).
// See PROVENANCE.md and SPEC.md for the pin, the workspace layout and the
// portability workarounds applied on toolchain v0.64.4:
//
//   * out-param slots are XIOM-owned `Vec[UInt8]` buffers; their contents are
//     read byte-indexed (B-24 discipline -- no pointer dereference, no
//     ffi.ptr_read_* helpers, no pointer arithmetic (B-17)).
//   * float workspaces cross as XIOM-owned `Vec[Float32]` buffers written by
//     the bridge; XIOM reads them with plain vector indexing.
//   * no Int <-> pointer casts (B-25), no bare `null` (B-23): the bridge takes
//     sizes and buffers only, and owns every C++ temporary.
//   * error codes are plain negative ints; the mapping to typed XIOM errors
//     lives in xiom.spz.
//
// Code table (keep in sync with src/spz_bridge.cpp):
//   0 ok, -1 bad args, -2 bad magic, -3 bad version, -4 decompress failure,
//   -5 truncated, -6 malformed header, -7 capacity too small, -8 internal.

module xiom.spz.ffi

// --- owned-slot helpers -----------------------------------------------------

/// Zeroed byte slot (`n` bytes) owned by XIOM.
/// Complexity: O(n).
pub fn zero_bytes(n: Int) -> Vec[UInt8]
  requires: n >= 0
{
  var v: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < n {
    v.push(0 as UInt8);
    i = i + 1;
  }
  return v;
}

/// Zero-filled float vector (`n` elements) owned by XIOM.
/// Complexity: O(n).
pub fn zero_floats(n: Int) -> Vec[Float32]
  requires: n >= 0
{
  var v: Vec[Float32] = Vec[Float32].new();
  var i: Int = 0;
  while i < n {
    v.push(0.0);
    i = i + 1;
  }
  return v;
}

/// Little-endian u64 read from an XIOM-owned slot (byte-indexed; B-24).
/// Complexity: O(1).
pub fn read_u64_le(buf: &Vec[UInt8], off: Int) -> Int
  requires: off >= 0
  requires: off + 8 <= buf.len()
{
  let b0 = buf[off + 0] as Int;
  let b1 = buf[off + 1] as Int;
  let b2 = buf[off + 2] as Int;
  let b3 = buf[off + 3] as Int;
  let b4 = buf[off + 4] as Int;
  let b5 = buf[off + 5] as Int;
  let b6 = buf[off + 6] as Int;
  let b7 = buf[off + 7] as Int;
  return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24) | (b4 << 32) | (b5 << 40) | (b6 << 48) | (b7 << 56);
}

/// NUL-terminated byte copy of `s` for C path arguments.
/// Complexity: O(len).
pub fn cpath(s: Str) -> Vec[UInt8]
  requires: true
{
  var v: Vec[UInt8] = Vec[UInt8].new();
  let n = s.len();
  var i: Int = 0;
  while i < n {
    v.push(s.byte_at(i));
    i = i + 1;
  }
  v.push(0 as UInt8);
  return v;
}

// ---------------------------------------------------------------------------
// Raw C declarations (private to this module)
// ---------------------------------------------------------------------------

extern "C" {
  fn xspz_constants(out8: *UInt8) -> Int32;
  fn xspz_has_extension_support() -> Int32;
  fn xspz_coordinate_values(out9: *UInt8) -> Int32;
  fn xspz_axes_match(a: Int32, b: Int32, out3: *UInt8) -> Int32;
  fn xspz_coordinate_converter(from: Int32, to: Int32, out30: *Float32) -> Int32;

  fn xspz_pack(work: *Float32, work_cap: Int, num_points: Int, sh_degree: Int, antialiased: Int,
    version: Int, from_coord: Int, sh1_bits: Int, sh_rest_bits: Int, out: *UInt8,
    out_cap: Int) -> Int;
  fn xspz_load_packed(data: *UInt8, size: Int, slot8: *UInt8) -> Int32;
  fn xspz_unpack(data: *UInt8, size: Int, to_coord: Int, slot4: *UInt8, work: *Float32,
    work_cap: Int) -> Int32;
  fn xspz_packed_gaussian(data: *UInt8, size: Int, index: Int, out92: *UInt8,
    out_cap: Int) -> Int32;
  fn xspz_packed_gaussian_unpack(data: *UInt8, size: Int, index: Int, to_coord: Int,
    out86: *Float32, out_cap: Int) -> Int32;

  fn xspz_save_file(path: *UInt8, work: *Float32, work_cap: Int, num_points: Int,
    sh_degree: Int, antialiased: Int, version: Int, from_coord: Int, sh1_bits: Int,
    sh_rest_bits: Int) -> Int32;
  fn xspz_load_file(path: *UInt8, to_coord: Int, slot4: *UInt8, work: *Float32,
    work_cap: Int) -> Int32;
  fn xspz_save_ply(path: *UInt8, work: *Float32, work_cap: Int, num_points: Int,
    sh_degree: Int, antialiased: Int, version: Int, from_coord: Int, sh1_bits: Int,
    sh_rest_bits: Int) -> Int32;
  fn xspz_load_ply(path: *UInt8, to_coord: Int, slot4: *UInt8, work: *Float32,
    work_cap: Int) -> Int32;

  fn xspz_serialize_packed(data: *UInt8, size: Int, out: *UInt8, out_cap: Int) -> Int;
  fn xspz_compress_gzipped(data: *UInt8, size: Int, out: *UInt8, out_cap: Int) -> Int;

  fn xspz_cloud_data(work: *Float32, work_cap: Int, num_points: Int, sh_degree: Int,
    antialiased: Int, out_work: *Float32, out_cap: Int) -> Int32;
  fn xspz_cloud_convert(work: *Float32, work_cap: Int, num_points: Int, sh_degree: Int,
    from_coord: Int, to_coord: Int) -> Int32;
  fn xspz_cloud_rotate180(work: *Float32, work_cap: Int, num_points: Int,
    sh_degree: Int) -> Int32;
  fn xspz_median_volume(work: *Float32, work_cap: Int, num_points: Int,
    sh_degree: Int) -> Float32;

  fn xspz_math_half_to_float(half16: Int, out1: *Float32) -> Int32;
  fn xspz_math_float_to_half(f: Float32) -> Int;
  fn xspz_math_norm3(x: Float32, y: Float32, z: Float32, out1: *Float32) -> Int32;
  fn xspz_math_norm4(x: Float32, y: Float32, z: Float32, w: Float32, out1: *Float32) -> Int32;
  fn xspz_math_normalized3(x: Float32, y: Float32, z: Float32, out3: *Float32) -> Int32;
  fn xspz_math_normalized4(x: Float32, y: Float32, z: Float32, w: Float32,
    out4: *Float32) -> Int32;
  fn xspz_math_axis_angle_quat(x: Float32, y: Float32, z: Float32, out4: *Float32) -> Int32;
  fn xspz_math_vec3f(x: Float32, y: Float32, z: Float32, out3: *Float32) -> Int32;
  fn xspz_math_quat4f(x: Float32, y: Float32, z: Float32, w: Float32, out4: *Float32) -> Int32;
  fn xspz_math_dot3(ax: Float32, ay: Float32, az: Float32, bx: Float32, by: Float32,
    bz: Float32, out1: *Float32) -> Int32;
  fn xspz_math_squared_norm3(x: Float32, y: Float32, z: Float32, out1: *Float32) -> Int32;
  fn xspz_math_times_qv(qw: Float32, qx: Float32, qy: Float32, qz: Float32, vx: Float32,
    vy: Float32, vz: Float32, out3: *Float32) -> Int32;
  fn xspz_math_times_qq(aw: Float32, ax: Float32, ay: Float32, az: Float32, bw: Float32,
    bx: Float32, by: Float32, bz: Float32, out4: *Float32) -> Int32;
  fn xspz_math_times_qs(qw: Float32, qx: Float32, qy: Float32, qz: Float32, s: Float32,
    out4: *Float32) -> Int32;
  fn xspz_math_plus_qq(aw: Float32, ax: Float32, ay: Float32, az: Float32, bw: Float32,
    bx: Float32, by: Float32, bz: Float32, out4: *Float32) -> Int32;
  fn xspz_math_times_vs(x: Float32, y: Float32, z: Float32, s: Float32, out3: *Float32) -> Int32;
  fn xspz_math_plus_vv(ax: Float32, ay: Float32, az: Float32, bx: Float32, by: Float32,
    bz: Float32, out3: *Float32) -> Int32;
  fn xspz_math_times_vv(ax: Float32, ay: Float32, az: Float32, bx: Float32, by: Float32,
    bz: Float32, out3: *Float32) -> Int32;
  fn xspz_math_copy_float_buffer(src: *Float32, count: Int, out: *Float32,
    out_cap: Int) -> Int32;
}

// ---------------------------------------------------------------------------
// Confined wrappers (small unsafe blocks; plain scalars out)
// ---------------------------------------------------------------------------

/// Fill `out` (>= 64 bytes) with the 8 header constants; returns the C rc.
/// Complexity: O(1).
pub fn constants(out: &mut Vec[UInt8]) -> Int32
  requires: out.len() >= 64
{
  unsafe { return xspz_constants(out.as_mut_ptr()); }
}

/// 1 when the pinned build has extension support, else 0.
/// Complexity: O(1).
pub fn extension_support() -> Int32
  requires: true
{
  unsafe { return xspz_has_extension_support(); }
}

/// Fill `out` (>= 72 bytes) with the 9 CoordinateSystem values; returns rc.
/// Complexity: O(1).
pub fn coordinate_values(out: &mut Vec[UInt8]) -> Int32
  requires: out.len() >= 72
{
  unsafe { return xspz_coordinate_values(out.as_mut_ptr()); }
}

/// Fill `out` (>= 24 bytes) with the 3 axesMatch bytes; returns rc.
/// Complexity: O(1).
pub fn axes_match(a: Int, b: Int, out: &mut Vec[UInt8]) -> Int32
  requires: out.len() >= 24
{
  unsafe { return xspz_axes_match(a as Int32, b as Int32, out.as_mut_ptr()); }
}

/// Fill `out` (>= 30 floats) with flipP(3)+flipQ(3)+flipSh(24); returns rc.
/// Complexity: O(1).
pub fn coordinate_converter(from: Int, to: Int, out: &mut Vec[Float32]) -> Int32
  requires: out.len() >= 30
{
  unsafe { return xspz_coordinate_converter(from as Int32, to as Int32, out.as_mut_ptr()); }
}

/// Pack the workspace into `out`; returns bytes needed (>= 0) or a negative rc.
/// Complexity: O(num_points) plus compression work.
pub fn pack(work: &mut Vec[Float32], num_points: Int, sh_degree: Int, antialiased: Bool,
    version: Int, from_coord: Int, sh1_bits: Int, sh_rest_bits: Int, out: &mut Vec[UInt8]) -> Int
  requires: num_points > 0
{
  let flags: Int = if antialiased { 1 } else { 0 };
  unsafe {
    return xspz_pack(work.as_mut_ptr(), work.len(), num_points, sh_degree, flags, version,
      from_coord, sh1_bits, sh_rest_bits, out.as_mut_ptr(), out.len());
  }
}

/// Metadata of a packed container into `slot` (>= 64 bytes); returns rc.
/// Complexity: O(num_points).
pub fn load_packed(data: &mut Vec[UInt8], slot: &mut Vec[UInt8]) -> Int32
  requires: slot.len() >= 64
{
  unsafe { return xspz_load_packed(data.as_mut_ptr(), data.len(), slot.as_mut_ptr()); }
}

/// Full unpack into `work`; `slot` (>= 32 bytes) receives counts; returns rc.
/// Complexity: O(num_points).
pub fn unpack(data: &mut Vec[UInt8], to_coord: Int, slot: &mut Vec[UInt8],
    work: &mut Vec[Float32]) -> Int32
  requires: slot.len() >= 32
{
  unsafe {
    return xspz_unpack(data.as_mut_ptr(), data.len(), to_coord, slot.as_mut_ptr(),
      work.as_mut_ptr(), work.len());
  }
}

/// 92 raw bytes of PackedGaussian::at(index) into `out`; returns rc.
/// Complexity: O(num_points) (the container is re-parsed per call).
pub fn packed_gaussian(data: &mut Vec[UInt8], index: Int, out: &mut Vec[UInt8]) -> Int32
  requires: out.len() >= 92
{
  unsafe { return xspz_packed_gaussian(data.as_mut_ptr(), data.len(), index, out.as_mut_ptr(), out.len()); }
}

/// 86 floats of PackedGaussian::unpack(index) into `out`; returns rc.
/// Complexity: O(num_points) (the container is re-parsed per call).
pub fn packed_gaussian_unpack(data: &mut Vec[UInt8], index: Int, to_coord: Int,
    out: &mut Vec[Float32]) -> Int32
  requires: out.len() >= 86
{
  unsafe {
    return xspz_packed_gaussian_unpack(data.as_mut_ptr(), data.len(), index, to_coord,
      out.as_mut_ptr(), out.len());
  }
}

/// Save the workspace as a packed file; returns rc.
/// Complexity: O(num_points) plus compression work.
pub fn save_file(path: &mut Vec[UInt8], work: &mut Vec[Float32], num_points: Int,
    sh_degree: Int, antialiased: Bool, version: Int, from_coord: Int, sh1_bits: Int,
    sh_rest_bits: Int) -> Int32
  requires: num_points > 0
  requires: path.len() >= 1
{
  let flags: Int = if antialiased { 1 } else { 0 };
  unsafe {
    return xspz_save_file(path.as_mut_ptr(), work.as_mut_ptr(), work.len(), num_points,
      sh_degree, flags, version, from_coord, sh1_bits, sh_rest_bits);
  }
}

/// Load a packed file into `work`; `slot` (>= 32 bytes) receives counts.
/// Complexity: O(num_points) plus decompression work.
pub fn load_file(path: &mut Vec[UInt8], to_coord: Int, slot: &mut Vec[UInt8],
    work: &mut Vec[Float32]) -> Int32
  requires: slot.len() >= 32
{
  unsafe {
    return xspz_load_file(path.as_mut_ptr(), to_coord, slot.as_mut_ptr(), work.as_mut_ptr(),
      work.len());
  }
}

/// Save the workspace as a PLY file; returns rc.
/// Complexity: O(num_points).
pub fn save_ply(path: &mut Vec[UInt8], work: &mut Vec[Float32], num_points: Int,
    sh_degree: Int, antialiased: Bool, version: Int, from_coord: Int, sh1_bits: Int,
    sh_rest_bits: Int) -> Int32
  requires: num_points > 0
  requires: path.len() >= 1
{
  let flags: Int = if antialiased { 1 } else { 0 };
  unsafe {
    return xspz_save_ply(path.as_mut_ptr(), work.as_mut_ptr(), work.len(), num_points,
      sh_degree, flags, version, from_coord, sh1_bits, sh_rest_bits);
  }
}

/// Load a PLY file into `work`; `slot` (>= 32 bytes) receives counts.
/// Complexity: O(num_points).
pub fn load_ply(path: &mut Vec[UInt8], to_coord: Int, slot: &mut Vec[UInt8],
    work: &mut Vec[Float32]) -> Int32
  requires: slot.len() >= 32
{
  unsafe {
    return xspz_load_ply(path.as_mut_ptr(), to_coord, slot.as_mut_ptr(), work.as_mut_ptr(),
      work.len());
  }
}

/// Legacy single-stream serialization of a packed container; returns bytes
/// needed (>= 0) or a negative rc.
/// Complexity: O(num_points).
pub fn serialize_packed(data: &mut Vec[UInt8], out: &mut Vec[UInt8]) -> Int
  requires: true
{
  unsafe { return xspz_serialize_packed(data.as_mut_ptr(), data.len(), out.as_mut_ptr(), out.len()); }
}

/// GZIP (deflate2) compression of raw bytes; returns bytes needed or rc.
/// Complexity: O(len) plus compression work.
pub fn compress_gzipped(data: &mut Vec[UInt8], out: &mut Vec[UInt8]) -> Int
  requires: true
{
  unsafe { return xspz_compress_gzipped(data.as_mut_ptr(), data.len(), out.as_mut_ptr(), out.len()); }
}

/// GaussianCloud::data() copy into `out_work`; returns rc.
/// Complexity: O(num_points).
pub fn cloud_data(work: &mut Vec[Float32], num_points: Int, sh_degree: Int, antialiased: Bool,
    out_work: &mut Vec[Float32]) -> Int32
  requires: num_points > 0
{
  let flags: Int = if antialiased { 1 } else { 0 };
  unsafe {
    return xspz_cloud_data(work.as_mut_ptr(), work.len(), num_points, sh_degree, flags,
      out_work.as_mut_ptr(), out_work.len());
  }
}

/// GaussianCloud::convertCoordinates(from, to), in place; returns rc.
/// Complexity: O(num_points).
pub fn cloud_convert(work: &mut Vec[Float32], num_points: Int, sh_degree: Int, from_coord: Int,
    to_coord: Int) -> Int32
  requires: num_points > 0
{
  unsafe {
    return xspz_cloud_convert(work.as_mut_ptr(), work.len(), num_points, sh_degree, from_coord,
      to_coord);
  }
}

/// GaussianCloud::rotate180DegAboutX(), in place; returns rc.
/// Complexity: O(num_points).
pub fn cloud_rotate180(work: &mut Vec[Float32], num_points: Int, sh_degree: Int) -> Int32
  requires: num_points > 0
{
  unsafe { return xspz_cloud_rotate180(work.as_mut_ptr(), work.len(), num_points, sh_degree); }
}

/// GaussianCloud::medianVolume() over the workspace scales stream.
/// Complexity: O(num_points).
pub fn median_volume(work: &mut Vec[Float32], num_points: Int, sh_degree: Int) -> Float32
  requires: num_points > 0
{
  unsafe { return xspz_median_volume(work.as_mut_ptr(), work.len(), num_points, sh_degree); }
}

// --- math helpers -----------------------------------------------------------

pub fn math_half_to_float(half16: Int) -> Float32
  requires: half16 >= 0
  requires: half16 <= 65535
{
  var out = zero_floats(1);
  unsafe {
    let rc = xspz_math_half_to_float(half16, out.as_mut_ptr());
    if rc != 0 { return 0.0; }
  }
  return out[0];
}

pub fn math_float_to_half(f: Float32) -> Int
  requires: true
{
  unsafe { return xspz_math_float_to_half(f); }
}

pub fn math_norm3(x: Float32, y: Float32, z: Float32) -> Float32
  requires: true
{
  var out = zero_floats(1);
  unsafe {
    let rc = xspz_math_norm3(x, y, z, out.as_mut_ptr());
    if rc != 0 { return 0.0; }
  }
  return out[0];
}

pub fn math_norm4(x: Float32, y: Float32, z: Float32, w: Float32) -> Float32
  requires: true
{
  var out = zero_floats(1);
  unsafe {
    let rc = xspz_math_norm4(x, y, z, w, out.as_mut_ptr());
    if rc != 0 { return 0.0; }
  }
  return out[0];
}

pub fn math_dot3(ax: Float32, ay: Float32, az: Float32, bx: Float32, by: Float32,
    bz: Float32) -> Float32
  requires: true
{
  var out = zero_floats(1);
  unsafe {
    let rc = xspz_math_dot3(ax, ay, az, bx, by, bz, out.as_mut_ptr());
    if rc != 0 { return 0.0; }
  }
  return out[0];
}

pub fn math_squared_norm3(x: Float32, y: Float32, z: Float32) -> Float32
  requires: true
{
  var out = zero_floats(1);
  unsafe {
    let rc = xspz_math_squared_norm3(x, y, z, out.as_mut_ptr());
    if rc != 0 { return 0.0; }
  }
  return out[0];
}

pub fn math_normalized3(x: Float32, y: Float32, z: Float32) -> Vec[Float32]
  requires: true
{
  var out = zero_floats(3);
  unsafe {
    let rc = xspz_math_normalized3(x, y, z, out.as_mut_ptr());
    if rc != 0 { return zero_floats(3); }
  }
  return out;
}

pub fn math_normalized4(x: Float32, y: Float32, z: Float32, w: Float32) -> Vec[Float32]
  requires: true
{
  var out = zero_floats(4);
  unsafe {
    let rc = xspz_math_normalized4(x, y, z, w, out.as_mut_ptr());
    if rc != 0 { return zero_floats(4); }
  }
  return out;
}

pub fn math_axis_angle_quat(x: Float32, y: Float32, z: Float32) -> Vec[Float32]
  requires: true
{
  var out = zero_floats(4);
  unsafe {
    let rc = xspz_math_axis_angle_quat(x, y, z, out.as_mut_ptr());
    if rc != 0 { return zero_floats(4); }
  }
  return out;
}

pub fn math_vec3f(x: Float32, y: Float32, z: Float32) -> Vec[Float32]
  requires: true
{
  var out = zero_floats(3);
  unsafe {
    let rc = xspz_math_vec3f(x, y, z, out.as_mut_ptr());
    if rc != 0 { return zero_floats(3); }
  }
  return out;
}

pub fn math_quat4f(x: Float32, y: Float32, z: Float32, w: Float32) -> Vec[Float32]
  requires: true
{
  var out = zero_floats(4);
  unsafe {
    let rc = xspz_math_quat4f(x, y, z, w, out.as_mut_ptr());
    if rc != 0 { return zero_floats(4); }
  }
  return out;
}

pub fn math_times_qv(qw: Float32, qx: Float32, qy: Float32, qz: Float32, vx: Float32,
    vy: Float32, vz: Float32) -> Vec[Float32]
  requires: true
{
  var out = zero_floats(3);
  unsafe {
    let rc = xspz_math_times_qv(qw, qx, qy, qz, vx, vy, vz, out.as_mut_ptr());
    if rc != 0 { return zero_floats(3); }
  }
  return out;
}

pub fn math_times_qq(aw: Float32, ax: Float32, ay: Float32, az: Float32, bw: Float32,
    bx: Float32, by: Float32, bz: Float32) -> Vec[Float32]
  requires: true
{
  var out = zero_floats(4);
  unsafe {
    let rc = xspz_math_times_qq(aw, ax, ay, az, bw, bx, by, bz, out.as_mut_ptr());
    if rc != 0 { return zero_floats(4); }
  }
  return out;
}

pub fn math_times_qs(qw: Float32, qx: Float32, qy: Float32, qz: Float32, s: Float32) -> Vec[Float32]
  requires: true
{
  var out = zero_floats(4);
  unsafe {
    let rc = xspz_math_times_qs(qw, qx, qy, qz, s, out.as_mut_ptr());
    if rc != 0 { return zero_floats(4); }
  }
  return out;
}

pub fn math_plus_qq(aw: Float32, ax: Float32, ay: Float32, az: Float32, bw: Float32,
    bx: Float32, by: Float32, bz: Float32) -> Vec[Float32]
  requires: true
{
  var out = zero_floats(4);
  unsafe {
    let rc = xspz_math_plus_qq(aw, ax, ay, az, bw, bx, by, bz, out.as_mut_ptr());
    if rc != 0 { return zero_floats(4); }
  }
  return out;
}

pub fn math_times_vs(x: Float32, y: Float32, z: Float32, s: Float32) -> Vec[Float32]
  requires: true
{
  var out = zero_floats(3);
  unsafe {
    let rc = xspz_math_times_vs(x, y, z, s, out.as_mut_ptr());
    if rc != 0 { return zero_floats(3); }
  }
  return out;
}

pub fn math_plus_vv(ax: Float32, ay: Float32, az: Float32, bx: Float32, by: Float32,
    bz: Float32) -> Vec[Float32]
  requires: true
{
  var out = zero_floats(3);
  unsafe {
    let rc = xspz_math_plus_vv(ax, ay, az, bx, by, bz, out.as_mut_ptr());
    if rc != 0 { return zero_floats(3); }
  }
  return out;
}

pub fn math_times_vv(ax: Float32, ay: Float32, az: Float32, bx: Float32, by: Float32,
    bz: Float32) -> Vec[Float32]
  requires: true
{
  var out = zero_floats(3);
  unsafe {
    let rc = xspz_math_times_vv(ax, ay, az, bx, by, bz, out.as_mut_ptr());
    if rc != 0 { return zero_floats(3); }
  }
  return out;
}

/// copyFloatBuffer() coverage: copies `src` through the upstream helper.
/// Complexity: O(count).
pub fn math_copy_float_buffer(src: &mut Vec[Float32], out: &mut Vec[Float32]) -> Int32
  requires: true
{
  unsafe {
    return xspz_math_copy_float_buffer(src.as_mut_ptr(), src.len(), out.as_mut_ptr(), out.len());
  }
}
