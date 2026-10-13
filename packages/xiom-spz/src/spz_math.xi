// xiom.spz.math -- public wrappers over the spz math surface (splat-types.h).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the public math helpers declared in splat-types.h: half precision
// (halfToFloat/floatToHalf), vector/quaternion norms and normalization,
// axisAngleQuat, the Vec3f/Quat4f constructors, dot/squaredNorm, the
// times/plus operators and copyFloatBuffer.  Quaternion order is w, x, y, z
// (upstream Quat4f); GaussianCloud rotations use x, y, z, w (see SPEC.md).
//
// No `unsafe` and no externs here: every call goes through the confined core
// in xiom.spz.ffi (G5).  The wrappers are infallible from XIOM: the bridge's
// only error path there is a null out-pointer, which XIOM cannot produce.

module xiom.spz.math

use xiom.spz.ffi;

/// halfToFloat: IEEE-754 binary16 bit pattern -> Float32.
/// Complexity: O(1).
pub fn spz_half_to_float(half16: Int) -> Float32
  requires: half16 >= 0
  requires: half16 <= 65535
{
  return ffi.math_half_to_float(half16);
}

/// floatToHalf: Float32 -> IEEE-754 binary16 bit pattern.
/// Complexity: O(1).
pub fn spz_float_to_half(f: Float32) -> Int {
  return ffi.math_float_to_half(f);
}

/// norm(Vec3f).
/// Complexity: O(1).
pub fn spz_norm3(x: Float32, y: Float32, z: Float32) -> Float32 {
  return ffi.math_norm3(x, y, z);
}

/// norm(Quat4f) (w-first).
/// Complexity: O(1).
pub fn spz_norm4(x: Float32, y: Float32, z: Float32, w: Float32) -> Float32 {
  return ffi.math_norm4(x, y, z, w);
}

/// normalized(Vec3f).
/// Complexity: O(1).
pub fn spz_normalized3(x: Float32, y: Float32, z: Float32) -> Vec[Float32] {
  return ffi.math_normalized3(x, y, z);
}

/// normalized(Quat4f) (w-first).
/// Complexity: O(1).
pub fn spz_normalized4(x: Float32, y: Float32, z: Float32, w: Float32) -> Vec[Float32] {
  return ffi.math_normalized4(x, y, z, w);
}

/// axisAngleQuat: quaternion (w, x, y, z) from a scaled rotation axis.
/// Complexity: O(1).
pub fn spz_axis_angle_quat(x: Float32, y: Float32, z: Float32) -> Vec[Float32] {
  return ffi.math_axis_angle_quat(x, y, z);
}

/// vec3f(const float*): Vec3f from components.
/// Complexity: O(1).
pub fn spz_vec3f(x: Float32, y: Float32, z: Float32) -> Vec[Float32] {
  return ffi.math_vec3f(x, y, z);
}

/// quat4f(const float*): Quat4f (x, y, z, w arguments) from components.
/// Complexity: O(1).
pub fn spz_quat4f(x: Float32, y: Float32, z: Float32, w: Float32) -> Vec[Float32] {
  return ffi.math_quat4f(x, y, z, w);
}

/// dot(Vec3f, Vec3f).
/// Complexity: O(1).
pub fn spz_dot3(ax: Float32, ay: Float32, az: Float32, bx: Float32, by: Float32,
    bz: Float32) -> Float32 {
  return ffi.math_dot3(ax, ay, az, bx, by, bz);
}

/// squaredNorm(Vec3f).
/// Complexity: O(1).
pub fn spz_squared_norm3(x: Float32, y: Float32, z: Float32) -> Float32 {
  return ffi.math_squared_norm3(x, y, z);
}

/// times(Quat4f, Vec3f): rotate a vector (quat is w-first).
/// Complexity: O(1).
pub fn spz_times_qv(qw: Float32, qx: Float32, qy: Float32, qz: Float32, vx: Float32,
    vy: Float32, vz: Float32) -> Vec[Float32] {
  return ffi.math_times_qv(qw, qx, qy, qz, vx, vy, vz);
}

/// times(Quat4f, Quat4f) (w-first).
/// Complexity: O(1).
pub fn spz_times_qq(aw: Float32, ax: Float32, ay: Float32, az: Float32, bw: Float32,
    bx: Float32, by: Float32, bz: Float32) -> Vec[Float32] {
  return ffi.math_times_qq(aw, ax, ay, az, bw, bx, by, bz);
}

/// times(Quat4f, float) (w-first).
/// Complexity: O(1).
pub fn spz_times_qs(qw: Float32, qx: Float32, qy: Float32, qz: Float32,
    s: Float32) -> Vec[Float32] {
  return ffi.math_times_qs(qw, qx, qy, qz, s);
}

/// plus(Quat4f, Quat4f) (w-first).
/// Complexity: O(1).
pub fn spz_plus_qq(aw: Float32, ax: Float32, ay: Float32, az: Float32, bw: Float32,
    bx: Float32, by: Float32, bz: Float32) -> Vec[Float32] {
  return ffi.math_plus_qq(aw, ax, ay, az, bw, bx, by, bz);
}

/// times(Vec3f, float).
/// Complexity: O(1).
pub fn spz_times_vs(x: Float32, y: Float32, z: Float32, s: Float32) -> Vec[Float32] {
  return ffi.math_times_vs(x, y, z, s);
}

/// plus(Vec3f, Vec3f).
/// Complexity: O(1).
pub fn spz_plus_vv(ax: Float32, ay: Float32, az: Float32, bx: Float32, by: Float32,
    bz: Float32) -> Vec[Float32] {
  return ffi.math_plus_vv(ax, ay, az, bx, by, bz);
}

/// times(Vec3f, Vec3f).
/// Complexity: O(1).
pub fn spz_times_vv(ax: Float32, ay: Float32, az: Float32, bx: Float32, by: Float32,
    bz: Float32) -> Vec[Float32] {
  return ffi.math_times_vv(ax, ay, az, bx, by, bz);
}

/// copyFloatBuffer(const std::vector<float>&): copies `src` into `out`
/// through the upstream helper; returns the bridge rc (0 = ok).
/// Complexity: O(count).
pub fn spz_copy_float_buffer(src: &mut Vec[Float32], out: &mut Vec[Float32]) -> Int {
  return ffi.math_copy_float_buffer(src, out) as Int;
}
