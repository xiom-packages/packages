// XIOM -- xiom.geom3d: deterministic fixed-point 3D geometry.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Scope: vec3, mat3, mat4, quaternion, ray/plane/triangle/AABB intersection and
// a small scene transform helper, all in pure XIOM integer math. No FFI, no
// Float64, no Vec anywhere in the module.
//
// Fixed-point model (pinned in SPEC.md, exercised by tests/test_conformance.xi):
//   * Every scalar is an Int in units of 1e-4 (G3_SCALE = 10000 = 1.0), so a
//     raw value 25000 means 2.5. Coordinates and directions share the scale;
//     ray directions need not be unit length.
//   * Rounding is half away from zero at every scaling division: the single
//     /10000 after a product sum, and every mixed-unit ratio such as a ray
//     parameter. XIOM division truncates toward zero, so _g3_div_round
//     normalizes the denominator, takes the truncated quotient and remainder,
//     and steps one unit away from zero when |remainder| >= den/2.
//   * Dot products, cross products, matrix entries and quaternion components
//     accumulate their raw products (scale 1e-8) and scale the sum ONCE, so
//     each carries at most one rounding step.
//   * Every product is guarded by _g3_sat_mul and every sum by _g3_sat_add /
//     _g3_sat_sub: overflow saturates at +/-9223372036854775807 instead of
//     wrapping. Products saturate when |a*b| > 2^63-1, so raw coordinates
//     should stay below about 1.7e9 (real ~1.7e5 in the default scale) for
//     length2 not to saturate; larger values stay total but lose precision.
//   * Zero-length vectors normalize to (0,0,0); a zero quaternion normalizes
//     to the identity rotation (10000,0,0,0). Both are total, documented
//     fallbacks, never errors.
//   * The only trigonometry is g3_quat_from_axis_angle: sin/cos are the
//     degree-11 Taylor polynomial on [-pi/2, pi/2] after range reduction to
//     [-pi, pi], evaluated in fixed point (see _g3_sin). G3_PI = 31416 is pi
//     rounded to 1e-4, so angle-derived quaternions are accurate to about
//     1e-4 and their exact outputs are pinned by the conformance suite.
//   * All loops are bounded (Newton isqrt, Taylor term build); no Vec means
//     no element-lowering workarounds are needed.

module xiom.geom3d

use xiom.math;

// --------------------------------------------------
//  Scale and constants
// --------------------------------------------------

/// Fixed-point scale: 10000 raw units = 1.0.
pub const G3_SCALE: Int = 10000;

/// Pi in raw units (3.1416), used by from-axis-angle trigonometry.
pub const G3_PI: Int = 31416;

/// Pi/2 in raw units (1.5708), used by from-axis-angle trigonometry.
pub const G3_HALF_PI: Int = 15708;

// Full turn in raw units.
const _G3_TWO_PI: Int = 62832;

// Saturating arithmetic range (symmetric; -9223372036854775808 is excluded).
const _G3_MAX: Int = 9223372036854775807;
const _G3_MIN: Int = -9223372036854775807;

// --------------------------------------------------
//  Public types
// --------------------------------------------------

/// 3D vector / point, raw fixed-point components (G3_SCALE per unit).
pub type G3Vec3 = {
  x: Int;
  y: Int;
  z: Int;
}

/// 3x3 matrix, row-major: m[row][col] is m<row><col>.
pub type G3Mat3 = {
  m00: Int; m01: Int; m02: Int;
  m10: Int; m11: Int; m12: Int;
  m20: Int; m21: Int; m22: Int;
}

/// 4x4 matrix, row-major, affine convention: m03/m13/m23 is the translation
/// and the last row is 0,0,0,G3_SCALE for rigid transforms.
pub type G3Mat4 = {
  m00: Int; m01: Int; m02: Int; m03: Int;
  m10: Int; m11: Int; m12: Int; m13: Int;
  m20: Int; m21: Int; m22: Int; m23: Int;
  m30: Int; m31: Int; m32: Int; m33: Int;
}

/// Quaternion (w, x, y, z), raw fixed-point. Unit length represents rotation.
pub type G3Quat = {
  w: Int;
  x: Int;
  y: Int;
  z: Int;
}

/// Axis-aligned box with inclusive min/max corners.
pub type G3Aabb = {
  min: G3Vec3;
  max: G3Vec3;
}

/// Ray: origin plus direction (not necessarily unit length).
pub type G3Ray = {
  origin: G3Vec3;
  dir: G3Vec3;
}

/// Plane: normal . p = d, with d at the same scale as a dot of raw values.
pub type G3Plane = {
  normal: G3Vec3;
  d: Int;
}

/// Triangle with vertices in counter-clockwise order.
pub type G3Triangle = {
  a: G3Vec3;
  b: G3Vec3;
  c: G3Vec3;
}

/// Intersection result: hit flag, raw ray parameter t, and the raw point.
pub type G3Hit = {
  hit: Bool;
  t: Int;
  px: Int;
  py: Int;
  pz: Int;
}

/// Uniform-scale rigid scene transform: rotate then scale, then translate.
pub type G3Scene = {
  position: G3Vec3;
  rotation: G3Quat;
  scale: Int;
}

// Private slab interval used by the ray-AABB helper: ok is false when the
// slab is parallel and the origin is outside; lo/hi are raw t values.
type G3Span = {
  ok: Bool;
  lo: Int;
  hi: Int;
}

// --------------------------------------------------
//  Saturating fixed-point arithmetic (private)
// --------------------------------------------------

// Saturating Int addition.
fn _g3_sat_add(a: Int, b: Int) -> Int {
  if b > 0 && a > _G3_MAX - b { return _G3_MAX; }
  if b < 0 && a < _G3_MIN - b { return _G3_MIN; }
  return a + b;
}

// Saturating Int subtraction.
fn _g3_sat_sub(a: Int, b: Int) -> Int {
  if b > 0 && a < _G3_MIN + b { return _G3_MIN; }
  if b < 0 && a > _G3_MAX + b { return _G3_MAX; }
  return a - b;
}

// Saturating Int multiplication (no scale division).
fn _g3_sat_mul(a: Int, b: Int) -> Int {
  if a == 0 || b == 0 { return 0; }
  var x = a;
  if x < 0 { x = 0 - x; }
  var y = b;
  if y < 0 { y = 0 - y; }
  if x > _G3_MAX / y {
    if (a < 0) != (b < 0) { return _G3_MIN; }
    return _G3_MAX;
  }
  return a * b;
}

// Division rounded half away from zero. Total: den == 0 yields 0.
fn _g3_div_round(num: Int, den: Int) -> Int {
  if den == 0 { return 0; }
  var n = num;
  var d = den;
  if d < 0 {
    n = 0 - n;
    d = 0 - d;
  }
  var q = n / d;
  var r = n % d;
  if r < 0 { r = 0 - r; }
  if r >= d - d / 2 {
    if n >= 0 { q = q + 1; } else { q = q - 1; }
  }
  return q;
}

// Raw product scaled once by 1/G3_SCALE, rounded half away from zero.
fn _g3_mul(a: Int, b: Int) -> Int {
  return _g3_div_round(_g3_sat_mul(a, b), G3_SCALE);
}

// Negative of an Int (no MIN_INT edge: the module range is symmetric).
fn _g3_neg(a: Int) -> Int {
  return 0 - a;
}

// Sum of four raw products, scaled once by 1/G3_SCALE.
fn _g3_sum4_scale(t0: Int, t1: Int, t2: Int, t3: Int) -> Int {
  var s = _g3_sat_add(t0, t1);
  s = _g3_sat_add(s, t2);
  s = _g3_sat_add(s, t3);
  return _g3_div_round(s, G3_SCALE);
}

// Sum of three raw products, scaled once by 1/G3_SCALE.
fn _g3_sum3_scale(t0: Int, t1: Int, t2: Int) -> Int {
  return _g3_sum4_scale(t0, t1, t2, 0);
}

// Sum of two raw products, scaled once by 1/G3_SCALE.
fn _g3_sum2_scale(t0: Int, t1: Int) -> Int {
  return _g3_sum4_scale(t0, t1, 0, 0);
}

// 2*t scaled once by 1/G3_SCALE, rounded half away from zero.
fn _g3_two_scale(t: Int) -> Int {
  return _g3_div_round(_g3_sat_mul(2, t), G3_SCALE);
}

// Dot product of two raw triples, scaled once.
fn _g3_dot3(ax: Int, ay: Int, az: Int, bx: Int, by: Int, bz: Int) -> Int {
  return _g3_sum3_scale(_g3_sat_mul(ax, bx), _g3_sat_mul(ay, by), _g3_sat_mul(az, bz));
}

// One component of a cross product: (a1*b2 - a2*b1) scaled once.
fn _g3_cross_comp(a1: Int, a2: Int, b1: Int, b2: Int) -> Int {
  return _g3_sum2_scale(_g3_sat_mul(a1, b2), _g3_neg(_g3_sat_mul(a2, b1)));
}

// Squared length of a raw triple (scale 1e-8 units, no division).
fn _g3_len2(x: Int, y: Int, z: Int) -> Int {
  var s = _g3_sat_mul(x, x);
  s = _g3_sat_add(s, _g3_sat_mul(y, y));
  s = _g3_sat_add(s, _g3_sat_mul(z, z));
  return s;
}

// Floor integer square root for n >= 0; 0 for n <= 0. Newton iteration from
// above; the loop body strictly decreases x, so it terminates.
fn _g3_isqrt(n: Int) -> Int {
  if n <= 0 { return 0; }
  var x = n;
  var y = _g3_sat_add(x, n / x) / 2;
  while y < x {
    x = y;
    y = _g3_sat_add(x, n / x) / 2;
  }
  return x;
}

// --------------------------------------------------
//  Fixed-point trigonometry (private)
// --------------------------------------------------

// sin Taylor polynomial (through x^11) on |x| <= pi/2 in raw units. Terms are
// scaled individually by integer factorial divisors, rounded half away.
fn _g3_sin_core(x: Int) -> Int {
  let x2 = _g3_mul(x, x);
  let x3 = _g3_mul(x2, x);
  let x5 = _g3_mul(x3, x2);
  let x7 = _g3_mul(x5, x2);
  let x9 = _g3_mul(x7, x2);
  let x11 = _g3_mul(x9, x2);
  var s = x;
  s = _g3_sat_sub(s, _g3_div_round(x3, 6));
  s = _g3_sat_add(s, _g3_div_round(x5, 120));
  s = _g3_sat_sub(s, _g3_div_round(x7, 5040));
  s = _g3_sat_add(s, _g3_div_round(x9, 362880));
  s = _g3_sat_sub(s, _g3_div_round(x11, 39916800));
  return s;
}

// Reduce a raw angle to [-pi, pi] by subtracting the nearest multiple of 2*pi.
fn _g3_wrap_two_pi(a: Int) -> Int {
  let k = _g3_div_round(a, _G3_TWO_PI);
  var r = _g3_sat_sub(a, _g3_sat_mul(k, _G3_TWO_PI));
  if r > G3_PI { r = _g3_sat_sub(r, _G3_TWO_PI); }
  if r < _g3_neg(G3_PI) { r = _g3_sat_add(r, _G3_TWO_PI); }
  return r;
}

// sin(theta) for any raw angle.
fn _g3_sin(theta: Int) -> Int {
  let r = _g3_wrap_two_pi(theta);
  var s = r;
  if s > G3_HALF_PI { s = _g3_sat_sub(G3_PI, r); }
  if s < _g3_neg(G3_HALF_PI) { s = _g3_sat_sub(_g3_neg(G3_PI), r); }
  return _g3_sin_core(s);
}

// cos(theta) = sin(theta + pi/2), with the angle wrapped first.
fn _g3_cos(theta: Int) -> Int {
  let r = _g3_wrap_two_pi(theta);
  return _g3_sin(_g3_sat_add(r, G3_HALF_PI));
}

// --------------------------------------------------
//  Vec3
// --------------------------------------------------

/// Construct a vec3 from raw fixed-point components.
/// Complexity: O(1).
pub fn g3_vec3(x: Int, y: Int, z: Int) -> G3Vec3 {
  return G3Vec3{ x: x; y: y; z: z; };
}

/// Component-wise sum a + b (saturating).
/// Complexity: O(1).
pub fn g3_vec3_add(a: G3Vec3, b: G3Vec3) -> G3Vec3 {
  return G3Vec3{
    x: _g3_sat_add(a.x, b.x);
    y: _g3_sat_add(a.y, b.y);
    z: _g3_sat_add(a.z, b.z);
  };
}

/// Component-wise difference a - b (saturating).
/// Complexity: O(1).
pub fn g3_vec3_sub(a: G3Vec3, b: G3Vec3) -> G3Vec3 {
  return G3Vec3{
    x: _g3_sat_sub(a.x, b.x);
    y: _g3_sat_sub(a.y, b.y);
    z: _g3_sat_sub(a.z, b.z);
  };
}

/// Component-wise scale a * k, with k a raw fixed-point scalar (k = G3_SCALE
/// is 1.0). Each component is one raw product rounded once.
/// Complexity: O(1).
pub fn g3_vec3_scale(a: G3Vec3, k: Int) -> G3Vec3 {
  return G3Vec3{
    x: _g3_mul(a.x, k);
    y: _g3_mul(a.y, k);
    z: _g3_mul(a.z, k);
  };
}

/// Dot product a . b in raw fixed-point units (the sum of the three raw
/// products, scaled once).
/// Complexity: O(1).
pub fn g3_vec3_dot(a: G3Vec3, b: G3Vec3) -> Int {
  return _g3_dot3(a.x, a.y, a.z, b.x, b.y, b.z);
}

/// Cross product a x b (right-handed), each component scaled once.
/// Complexity: O(1).
pub fn g3_vec3_cross(a: G3Vec3, b: G3Vec3) -> G3Vec3 {
  return G3Vec3{
    x: _g3_cross_comp(a.y, a.z, b.y, b.z);
    y: _g3_cross_comp(a.z, a.x, b.z, b.x);
    z: _g3_cross_comp(a.x, a.y, b.x, b.y);
  };
}

/// Squared length x*x + y*y + z*z in raw 1e-8 units (no scaling division, so
/// small inputs stay exact). Real length = isqrt(length2)/G3_SCALE.
/// Complexity: O(1).
pub fn g3_vec3_length2(a: G3Vec3) -> Int {
  return _g3_len2(a.x, a.y, a.z);
}

/// Unit vector in the direction of a. Returns (0,0,0) for the zero vector.
/// Each component is rounded half away from zero.
/// Complexity: O(log(length2)) (Newton isqrt).
pub fn g3_vec3_normalize(a: G3Vec3) -> G3Vec3 {
  let ax = a.x;
  let ay = a.y;
  let az = a.z;
  let len = _g3_isqrt(_g3_len2(ax, ay, az));
  if len <= 0 {
    return G3Vec3{ x: 0; y: 0; z: 0; };
  }
  return G3Vec3{
    x: _g3_div_round(_g3_sat_mul(ax, G3_SCALE), len);
    y: _g3_div_round(_g3_sat_mul(ay, G3_SCALE), len);
    z: _g3_div_round(_g3_sat_mul(az, G3_SCALE), len);
  };
}

// --------------------------------------------------
//  Mat3 (row-major)
// --------------------------------------------------

/// 3x3 identity matrix.
/// Complexity: O(1).
pub fn g3_mat3_identity() -> G3Mat3 {
  return G3Mat3{
    m00: G3_SCALE; m01: 0; m02: 0;
    m10: 0; m11: G3_SCALE; m12: 0;
    m20: 0; m21: 0; m22: G3_SCALE;
  };
}

/// Matrix product a * b.
/// Complexity: O(1).
pub fn g3_mat3_mul(a: G3Mat3, b: G3Mat3) -> G3Mat3 {
  return G3Mat3{
    m00: _g3_sum3_scale(_g3_sat_mul(a.m00, b.m00), _g3_sat_mul(a.m01, b.m10), _g3_sat_mul(a.m02, b.m20));
    m01: _g3_sum3_scale(_g3_sat_mul(a.m00, b.m01), _g3_sat_mul(a.m01, b.m11), _g3_sat_mul(a.m02, b.m21));
    m02: _g3_sum3_scale(_g3_sat_mul(a.m00, b.m02), _g3_sat_mul(a.m01, b.m12), _g3_sat_mul(a.m02, b.m22));
    m10: _g3_sum3_scale(_g3_sat_mul(a.m10, b.m00), _g3_sat_mul(a.m11, b.m10), _g3_sat_mul(a.m12, b.m20));
    m11: _g3_sum3_scale(_g3_sat_mul(a.m10, b.m01), _g3_sat_mul(a.m11, b.m11), _g3_sat_mul(a.m12, b.m21));
    m12: _g3_sum3_scale(_g3_sat_mul(a.m10, b.m02), _g3_sat_mul(a.m11, b.m12), _g3_sat_mul(a.m12, b.m22));
    m20: _g3_sum3_scale(_g3_sat_mul(a.m20, b.m00), _g3_sat_mul(a.m21, b.m10), _g3_sat_mul(a.m22, b.m20));
    m21: _g3_sum3_scale(_g3_sat_mul(a.m20, b.m01), _g3_sat_mul(a.m21, b.m11), _g3_sat_mul(a.m22, b.m21));
    m22: _g3_sum3_scale(_g3_sat_mul(a.m20, b.m02), _g3_sat_mul(a.m21, b.m12), _g3_sat_mul(a.m22, b.m22));
  };
}

/// Transpose of m.
/// Complexity: O(1).
pub fn g3_mat3_transpose(m: G3Mat3) -> G3Mat3 {
  return G3Mat3{
    m00: m.m00; m01: m.m10; m02: m.m20;
    m10: m.m01; m11: m.m11; m12: m.m21;
    m20: m.m02; m21: m.m12; m22: m.m22;
  };
}

/// Linear transform m * v.
/// Complexity: O(1).
pub fn g3_mat3_transform_vec(m: G3Mat3, v: G3Vec3) -> G3Vec3 {
  return G3Vec3{
    x: _g3_sum3_scale(_g3_sat_mul(m.m00, v.x), _g3_sat_mul(m.m01, v.y), _g3_sat_mul(m.m02, v.z));
    y: _g3_sum3_scale(_g3_sat_mul(m.m10, v.x), _g3_sat_mul(m.m11, v.y), _g3_sat_mul(m.m12, v.z));
    z: _g3_sum3_scale(_g3_sat_mul(m.m20, v.x), _g3_sat_mul(m.m21, v.y), _g3_sat_mul(m.m22, v.z));
  };
}

// --------------------------------------------------
//  Mat4 (row-major, affine)
// --------------------------------------------------

/// 4x4 identity matrix.
/// Complexity: O(1).
pub fn g3_mat4_identity() -> G3Mat4 {
  return G3Mat4{
    m00: G3_SCALE; m01: 0; m02: 0; m03: 0;
    m10: 0; m11: G3_SCALE; m12: 0; m13: 0;
    m20: 0; m21: 0; m22: G3_SCALE; m23: 0;
    m30: 0; m31: 0; m32: 0; m33: G3_SCALE;
  };
}

/// Matrix product a * b.
/// Complexity: O(1).
pub fn g3_mat4_mul(a: G3Mat4, b: G3Mat4) -> G3Mat4 {
  return G3Mat4{
    m00: _g3_sum4_scale(_g3_sat_mul(a.m00, b.m00), _g3_sat_mul(a.m01, b.m10), _g3_sat_mul(a.m02, b.m20), _g3_sat_mul(a.m03, b.m30));
    m01: _g3_sum4_scale(_g3_sat_mul(a.m00, b.m01), _g3_sat_mul(a.m01, b.m11), _g3_sat_mul(a.m02, b.m21), _g3_sat_mul(a.m03, b.m31));
    m02: _g3_sum4_scale(_g3_sat_mul(a.m00, b.m02), _g3_sat_mul(a.m01, b.m12), _g3_sat_mul(a.m02, b.m22), _g3_sat_mul(a.m03, b.m32));
    m03: _g3_sum4_scale(_g3_sat_mul(a.m00, b.m03), _g3_sat_mul(a.m01, b.m13), _g3_sat_mul(a.m02, b.m23), _g3_sat_mul(a.m03, b.m33));
    m10: _g3_sum4_scale(_g3_sat_mul(a.m10, b.m00), _g3_sat_mul(a.m11, b.m10), _g3_sat_mul(a.m12, b.m20), _g3_sat_mul(a.m13, b.m30));
    m11: _g3_sum4_scale(_g3_sat_mul(a.m10, b.m01), _g3_sat_mul(a.m11, b.m11), _g3_sat_mul(a.m12, b.m21), _g3_sat_mul(a.m13, b.m31));
    m12: _g3_sum4_scale(_g3_sat_mul(a.m10, b.m02), _g3_sat_mul(a.m11, b.m12), _g3_sat_mul(a.m12, b.m22), _g3_sat_mul(a.m13, b.m32));
    m13: _g3_sum4_scale(_g3_sat_mul(a.m10, b.m03), _g3_sat_mul(a.m11, b.m13), _g3_sat_mul(a.m12, b.m23), _g3_sat_mul(a.m13, b.m33));
    m20: _g3_sum4_scale(_g3_sat_mul(a.m20, b.m00), _g3_sat_mul(a.m21, b.m10), _g3_sat_mul(a.m22, b.m20), _g3_sat_mul(a.m23, b.m30));
    m21: _g3_sum4_scale(_g3_sat_mul(a.m20, b.m01), _g3_sat_mul(a.m21, b.m11), _g3_sat_mul(a.m22, b.m21), _g3_sat_mul(a.m23, b.m31));
    m22: _g3_sum4_scale(_g3_sat_mul(a.m20, b.m02), _g3_sat_mul(a.m21, b.m12), _g3_sat_mul(a.m22, b.m22), _g3_sat_mul(a.m23, b.m32));
    m23: _g3_sum4_scale(_g3_sat_mul(a.m20, b.m03), _g3_sat_mul(a.m21, b.m13), _g3_sat_mul(a.m22, b.m23), _g3_sat_mul(a.m23, b.m33));
    m30: _g3_sum4_scale(_g3_sat_mul(a.m30, b.m00), _g3_sat_mul(a.m31, b.m10), _g3_sat_mul(a.m32, b.m20), _g3_sat_mul(a.m33, b.m30));
    m31: _g3_sum4_scale(_g3_sat_mul(a.m30, b.m01), _g3_sat_mul(a.m31, b.m11), _g3_sat_mul(a.m32, b.m21), _g3_sat_mul(a.m33, b.m31));
    m32: _g3_sum4_scale(_g3_sat_mul(a.m30, b.m02), _g3_sat_mul(a.m31, b.m12), _g3_sat_mul(a.m32, b.m22), _g3_sat_mul(a.m33, b.m32));
    m33: _g3_sum4_scale(_g3_sat_mul(a.m30, b.m03), _g3_sat_mul(a.m31, b.m13), _g3_sat_mul(a.m32, b.m23), _g3_sat_mul(a.m33, b.m33));
  };
}

/// Transpose of m.
/// Complexity: O(1).
pub fn g3_mat4_transpose(m: G3Mat4) -> G3Mat4 {
  return G3Mat4{
    m00: m.m00; m01: m.m10; m02: m.m20; m03: m.m30;
    m10: m.m01; m11: m.m11; m12: m.m21; m13: m.m31;
    m20: m.m02; m21: m.m12; m22: m.m22; m23: m.m32;
    m30: m.m03; m31: m.m13; m32: m.m23; m33: m.m33;
  };
}

/// Inverse of a rigid transform: the upper-left 3x3 is transposed and the
/// translation becomes -R^T * t. The input must be rigid (orthonormal R, last
/// row 0,0,0,1); the function does not verify that.
/// Complexity: O(1).
pub fn g3_mat4_rigid_inverse(m: G3Mat4) -> G3Mat4 {
  return G3Mat4{
    m00: m.m00; m01: m.m10; m02: m.m20;
    m03: _g3_neg(_g3_sum3_scale(_g3_sat_mul(m.m00, m.m03), _g3_sat_mul(m.m10, m.m13), _g3_sat_mul(m.m20, m.m23)));
    m10: m.m01; m11: m.m11; m12: m.m21;
    m13: _g3_neg(_g3_sum3_scale(_g3_sat_mul(m.m01, m.m03), _g3_sat_mul(m.m11, m.m13), _g3_sat_mul(m.m21, m.m23)));
    m20: m.m02; m21: m.m12; m22: m.m22;
    m23: _g3_neg(_g3_sum3_scale(_g3_sat_mul(m.m02, m.m03), _g3_sat_mul(m.m12, m.m13), _g3_sat_mul(m.m22, m.m23)));
    m30: 0; m31: 0; m32: 0; m33: G3_SCALE;
  };
}

/// Transform a point (w = G3_SCALE): m * (p, 1).
/// Complexity: O(1).
pub fn g3_mat4_transform_point(m: G3Mat4, p: G3Vec3) -> G3Vec3 {
  return G3Vec3{
    x: _g3_sum4_scale(_g3_sat_mul(m.m00, p.x), _g3_sat_mul(m.m01, p.y), _g3_sat_mul(m.m02, p.z), _g3_sat_mul(m.m03, G3_SCALE));
    y: _g3_sum4_scale(_g3_sat_mul(m.m10, p.x), _g3_sat_mul(m.m11, p.y), _g3_sat_mul(m.m12, p.z), _g3_sat_mul(m.m13, G3_SCALE));
    z: _g3_sum4_scale(_g3_sat_mul(m.m20, p.x), _g3_sat_mul(m.m21, p.y), _g3_sat_mul(m.m22, p.z), _g3_sat_mul(m.m23, G3_SCALE));
  };
}

/// Transform a direction (w = 0): m * (v, 0), translation ignored.
/// Complexity: O(1).
pub fn g3_mat4_transform_vec(m: G3Mat4, v: G3Vec3) -> G3Vec3 {
  return G3Vec3{
    x: _g3_sum3_scale(_g3_sat_mul(m.m00, v.x), _g3_sat_mul(m.m01, v.y), _g3_sat_mul(m.m02, v.z));
    y: _g3_sum3_scale(_g3_sat_mul(m.m10, v.x), _g3_sat_mul(m.m11, v.y), _g3_sat_mul(m.m12, v.z));
    z: _g3_sum3_scale(_g3_sat_mul(m.m20, v.x), _g3_sat_mul(m.m21, v.y), _g3_sat_mul(m.m22, v.z));
  };
}

/// Rigid transform from a (normalized first) quaternion and a translation.
/// The rotation matrix uses the standard 1 - 2(y^2+z^2) form, so a non-unit
/// input is normalized before conversion.
/// Complexity: O(1) plus quaternion normalization.
pub fn g3_mat4_from_quat_translation(q: G3Quat, t: G3Vec3) -> G3Mat4 {
  let qn = g3_quat_normalize(q);
  let xx = _g3_sat_mul(qn.x, qn.x);
  let yy = _g3_sat_mul(qn.y, qn.y);
  let zz = _g3_sat_mul(qn.z, qn.z);
  let xy = _g3_sat_mul(qn.x, qn.y);
  let xz = _g3_sat_mul(qn.x, qn.z);
  let yz = _g3_sat_mul(qn.y, qn.z);
  let wx = _g3_sat_mul(qn.w, qn.x);
  let wy = _g3_sat_mul(qn.w, qn.y);
  let wz = _g3_sat_mul(qn.w, qn.z);
  return G3Mat4{
    m00: _g3_sat_sub(G3_SCALE, _g3_two_scale(_g3_sat_add(yy, zz)));
    m01: _g3_two_scale(_g3_sat_sub(xy, wz));
    m02: _g3_two_scale(_g3_sat_add(xz, wy));
    m03: t.x;
    m10: _g3_two_scale(_g3_sat_add(xy, wz));
    m11: _g3_sat_sub(G3_SCALE, _g3_two_scale(_g3_sat_add(xx, zz)));
    m12: _g3_two_scale(_g3_sat_sub(yz, wx));
    m13: t.y;
    m20: _g3_two_scale(_g3_sat_sub(xz, wy));
    m21: _g3_two_scale(_g3_sat_add(yz, wx));
    m22: _g3_sat_sub(G3_SCALE, _g3_two_scale(_g3_sat_add(xx, yy)));
    m23: t.z;
    m30: 0; m31: 0; m32: 0; m33: G3_SCALE;
  };
}

// --------------------------------------------------
//  Quaternions
// --------------------------------------------------

/// Construct a quaternion from raw fixed-point components.
/// Complexity: O(1).
pub fn g3_quat(w: Int, x: Int, y: Int, z: Int) -> G3Quat {
  return G3Quat{ w: w; x: x; y: y; z: z; };
}

/// Identity quaternion (G3_SCALE, 0, 0, 0): the zero rotation.
/// Complexity: O(1).
pub fn g3_quat_identity() -> G3Quat {
  return G3Quat{ w: G3_SCALE; x: 0; y: 0; z: 0; };
}

/// Conjugate (w, -x, -y, -z): the inverse rotation for a unit quaternion.
/// Complexity: O(1).
pub fn g3_quat_conjugate(q: G3Quat) -> G3Quat {
  return G3Quat{
    w: q.w;
    x: _g3_neg(q.x);
    y: _g3_neg(q.y);
    z: _g3_neg(q.z);
  };
}

/// Hamilton product a * b (rotation b followed by rotation a).
/// Complexity: O(1).
pub fn g3_quat_mul(a: G3Quat, b: G3Quat) -> G3Quat {
  return G3Quat{
    w: _g3_sum4_scale(_g3_sat_mul(a.w, b.w), _g3_neg(_g3_sat_mul(a.x, b.x)), _g3_neg(_g3_sat_mul(a.y, b.y)), _g3_neg(_g3_sat_mul(a.z, b.z)));
    x: _g3_sum4_scale(_g3_sat_mul(a.w, b.x), _g3_sat_mul(a.x, b.w), _g3_sat_mul(a.y, b.z), _g3_neg(_g3_sat_mul(a.z, b.y)));
    y: _g3_sum4_scale(_g3_sat_mul(a.w, b.y), _g3_neg(_g3_sat_mul(a.x, b.z)), _g3_sat_mul(a.y, b.w), _g3_sat_mul(a.z, b.x));
    z: _g3_sum4_scale(_g3_sat_mul(a.w, b.z), _g3_sat_mul(a.x, b.y), _g3_neg(_g3_sat_mul(a.y, b.x)), _g3_sat_mul(a.z, b.w));
  };
}

/// Unit quaternion in the direction of q. A zero quaternion returns the
/// identity rotation (G3_SCALE, 0, 0, 0).
/// Complexity: O(log(length2)) (Newton isqrt).
pub fn g3_quat_normalize(q: G3Quat) -> G3Quat {
  var l2 = _g3_sat_mul(q.w, q.w);
  l2 = _g3_sat_add(l2, _g3_sat_mul(q.x, q.x));
  l2 = _g3_sat_add(l2, _g3_sat_mul(q.y, q.y));
  l2 = _g3_sat_add(l2, _g3_sat_mul(q.z, q.z));
  let len = _g3_isqrt(l2);
  if len <= 0 {
    return g3_quat_identity();
  }
  return G3Quat{
    w: _g3_div_round(_g3_sat_mul(q.w, G3_SCALE), len);
    x: _g3_div_round(_g3_sat_mul(q.x, G3_SCALE), len);
    y: _g3_div_round(_g3_sat_mul(q.y, G3_SCALE), len);
    z: _g3_div_round(_g3_sat_mul(q.z, G3_SCALE), len);
  };
}

/// Rotate a vector by q using the expanded form
/// (w^2 - u.u) v + 2 u (u.v) + 2 w (u x v), where u is the vector part.
/// A non-unit q scales the result by |q|^2; normalize first for pure
/// rotation.
/// Complexity: O(1).
pub fn g3_quat_rotate_vec(q: G3Quat, v: G3Vec3) -> G3Vec3 {
  let w = q.w;
  let qx = q.x;
  let qy = q.y;
  let qz = q.z;
  let vx = v.x;
  let vy = v.y;
  let vz = v.z;
  let w2 = _g3_sat_mul(w, w);
  let uu = _g3_len2(qx, qy, qz);
  let c = _g3_div_round(_g3_sat_sub(w2, uu), G3_SCALE);
  let dot = _g3_dot3(qx, qy, qz, vx, vy, vz);
  let cx = _g3_cross_comp(qy, qz, vy, vz);
  let cy = _g3_cross_comp(qz, qx, vz, vx);
  let cz = _g3_cross_comp(qx, qy, vx, vy);
  let k2 = _g3_sat_mul(2, dot);
  let k3 = _g3_sat_mul(2, w);
  return G3Vec3{
    x: _g3_sat_add(_g3_sat_add(_g3_mul(vx, c), _g3_mul(qx, k2)), _g3_mul(cx, k3));
    y: _g3_sat_add(_g3_sat_add(_g3_mul(vy, c), _g3_mul(qy, k2)), _g3_mul(cy, k3));
    z: _g3_sat_add(_g3_sat_add(_g3_mul(vz, c), _g3_mul(qz, k2)), _g3_mul(cz, k3));
  };
}

/// Quaternion for a rotation of `angle` raw radians about `axis` (the axis is
/// normalized first; a zero axis yields the identity). The half-angle pair
/// (cos, sin) is computed with the fixed-point polynomial trigonometry
/// documented in the module header and the result is normalized.
/// Complexity: O(log(length2)) plus the fixed Taylor work.
pub fn g3_quat_from_axis_angle(axis: G3Vec3, angle: Int) -> G3Quat {
  let u = g3_vec3_normalize(axis);
  if (u.x == 0) && (u.y == 0) && (u.z == 0) {
    return g3_quat_identity();
  }
  let half = _g3_div_round(angle, 2);
  let c = _g3_cos(half);
  let s = _g3_sin(half);
  let q = G3Quat{
    w: c;
    x: _g3_mul(s, u.x);
    y: _g3_mul(s, u.y);
    z: _g3_mul(s, u.z);
  };
  return g3_quat_normalize(q);
}

// --------------------------------------------------
//  Constructors
// --------------------------------------------------

/// Construct a ray from an origin and a direction (direction need not be unit).
/// Complexity: O(1).
pub fn g3_ray(origin: G3Vec3, dir: G3Vec3) -> G3Ray {
  return G3Ray{ origin: origin; dir: dir; };
}

/// Construct a plane from a normal and d (normal need not be unit).
/// Complexity: O(1).
pub fn g3_plane(normal: G3Vec3, d: Int) -> G3Plane {
  return G3Plane{ normal: normal; d: d; };
}

/// Construct a triangle from three vertices.
/// Complexity: O(1).
pub fn g3_triangle(a: G3Vec3, b: G3Vec3, c: G3Vec3) -> G3Triangle {
  return G3Triangle{ a: a; b: b; c: c; };
}

/// Construct an axis-aligned box from inclusive min and max corners.
/// Complexity: O(1).
pub fn g3_aabb(min: G3Vec3, max: G3Vec3) -> G3Aabb {
  return G3Aabb{ min: min; max: max; };
}

// --------------------------------------------------
//  Intersections
// --------------------------------------------------

// A hit at parameter t with point p.
fn _g3_hit(t: Int, p: G3Vec3) -> G3Hit {
  return G3Hit{ hit: true; t: t; px: p.x; py: p.y; pz: p.z; };
}

// The canonical miss (hit = false, t and point zero).
fn _g3_miss() -> G3Hit {
  return G3Hit{ hit: false; t: 0; px: 0; py: 0; pz: 0; };
}

// One slab of the AABB test: the raw t interval where o + t*d stays inside
// [mn, mx] on one axis. d == 0 yields ok=false when o is outside the slab and
// the full real line when inside; otherwise lo/hi are the two endpoint t
// values, rounded half away from zero.
fn _g3_slab(o: Int, d: Int, mn: Int, mx: Int) -> G3Span {
  if d == 0 {
    if o < mn || o > mx {
      return G3Span{ ok: false; lo: 0; hi: 0; };
    }
    return G3Span{ ok: true; lo: _G3_MIN; hi: _G3_MAX; };
  }
  let t1 = _g3_div_round(_g3_sat_mul(_g3_sat_sub(mn, o), G3_SCALE), d);
  let t2 = _g3_div_round(_g3_sat_mul(_g3_sat_sub(mx, o), G3_SCALE), d);
  return G3Span{ ok: true; lo: math.min_int(t1, t2); hi: math.max_int(t1, t2); };
}

/// Ray-plane intersection: the first t >= 0 solving (o + t*d) . n = d, then
/// the point o + t*d. Miss when the ray is parallel to the plane (n . dir ==
/// 0) or the intersection lies behind the origin (t < 0).
/// Complexity: O(1).
pub fn g3_ray_plane(ray: G3Ray, plane: G3Plane) -> G3Hit {
  let nx = plane.normal.x;
  let ny = plane.normal.y;
  let nz = plane.normal.z;
  let pd = plane.d;
  let ox = ray.origin.x;
  let oy = ray.origin.y;
  let oz = ray.origin.z;
  let dx = ray.dir.x;
  let dy = ray.dir.y;
  let dz = ray.dir.z;
  let den = _g3_dot3(nx, ny, nz, dx, dy, dz);
  if den == 0 {
    return _g3_miss();
  }
  let num = _g3_sat_sub(pd, _g3_dot3(nx, ny, nz, ox, oy, oz));
  let t = _g3_div_round(_g3_sat_mul(num, G3_SCALE), den);
  if t < 0 {
    return _g3_miss();
  }
  return _g3_hit(t, G3Vec3{
    x: _g3_sat_add(ox, _g3_mul(dx, t));
    y: _g3_sat_add(oy, _g3_mul(dy, t));
    z: _g3_sat_add(oz, _g3_mul(dz, t));
  });
}

/// Ray-triangle intersection by the integer Moller-Trumbore form: with
/// e1 = b-a, e2 = c-a, h = dir x e2, a = e1 . h, s = o-a, q = s x e1 the hit
/// conditions are u = (s.h)/a >= 0, v = (dir.q)/a >= 0, u+v <= 1 and t =
/// (e2.q)/a >= 0, all evaluated without dividing (cross-multiplied), so the
/// barycentric tests are exact for the rounded dot/cross values. Degenerate
/// triangles (a == 0) miss.
/// Complexity: O(1).
pub fn g3_ray_triangle(ray: G3Ray, tri: G3Triangle) -> G3Hit {
  let ax = tri.a.x;
  let ay = tri.a.y;
  let az = tri.a.z;
  let bx = tri.b.x;
  let by = tri.b.y;
  let bz = tri.b.z;
  let cx = tri.c.x;
  let cy = tri.c.y;
  let cz = tri.c.z;
  let ox = ray.origin.x;
  let oy = ray.origin.y;
  let oz = ray.origin.z;
  let dx = ray.dir.x;
  let dy = ray.dir.y;
  let dz = ray.dir.z;
  let e1x = _g3_sat_sub(bx, ax);
  let e1y = _g3_sat_sub(by, ay);
  let e1z = _g3_sat_sub(bz, az);
  let e2x = _g3_sat_sub(cx, ax);
  let e2y = _g3_sat_sub(cy, ay);
  let e2z = _g3_sat_sub(cz, az);
  let hx = _g3_cross_comp(dy, dz, e2y, e2z);
  let hy = _g3_cross_comp(dz, dx, e2z, e2x);
  let hz = _g3_cross_comp(dx, dy, e2x, e2y);
  let a = _g3_dot3(e1x, e1y, e1z, hx, hy, hz);
  if a == 0 {
    return _g3_miss();
  }
  let sx = _g3_sat_sub(ox, ax);
  let sy = _g3_sat_sub(oy, ay);
  let sz = _g3_sat_sub(oz, az);
  let u_num = _g3_dot3(sx, sy, sz, hx, hy, hz);
  let qx = _g3_cross_comp(sy, sz, e1y, e1z);
  let qy = _g3_cross_comp(sz, sx, e1z, e1x);
  let qz = _g3_cross_comp(sx, sy, e1x, e1y);
  let v_num = _g3_dot3(dx, dy, dz, qx, qy, qz);
  if a > 0 {
    if u_num < 0 || v_num < 0 {
      return _g3_miss();
    }
    if _g3_sat_add(u_num, v_num) > a {
      return _g3_miss();
    }
  } else {
    if u_num > 0 || v_num > 0 {
      return _g3_miss();
    }
    if _g3_sat_add(u_num, v_num) < a {
      return _g3_miss();
    }
  }
  let t = _g3_div_round(_g3_sat_mul(_g3_dot3(e2x, e2y, e2z, qx, qy, qz), G3_SCALE), a);
  if t < 0 {
    return _g3_miss();
  }
  return _g3_hit(t, G3Vec3{
    x: _g3_sat_add(ox, _g3_mul(dx, t));
    y: _g3_sat_add(oy, _g3_mul(dy, t));
    z: _g3_sat_add(oz, _g3_mul(dz, t));
  });
}

/// Ray-AABB intersection by the slab method, inclusive on the box boundary.
/// Miss when any slab is parallel-and-outside, when tmax < tmin, or when the
/// whole interval lies behind the origin (tmax < 0). When the origin is inside
/// the box (tmin < 0 <= tmax) the hit distance is 0 and the point is the
/// origin.
/// Complexity: O(1).
pub fn g3_ray_aabb(ray: G3Ray, box: G3Aabb) -> G3Hit {
  let sx = _g3_slab(ray.origin.x, ray.dir.x, box.min.x, box.max.x);
  if !sx.ok {
    return _g3_miss();
  }
  let sy = _g3_slab(ray.origin.y, ray.dir.y, box.min.y, box.max.y);
  if !sy.ok {
    return _g3_miss();
  }
  let sz = _g3_slab(ray.origin.z, ray.dir.z, box.min.z, box.max.z);
  if !sz.ok {
    return _g3_miss();
  }
  var tmin = math.max_int(sx.lo, sy.lo);
  tmin = math.max_int(tmin, sz.lo);
  var tmax = math.min_int(sx.hi, sy.hi);
  tmax = math.min_int(tmax, sz.hi);
  if tmax < tmin {
    return _g3_miss();
  }
  if tmax < 0 {
    return _g3_miss();
  }
  var t = tmin;
  if t < 0 {
    t = 0;
  }
  return _g3_hit(t, g3_vec3_add(ray.origin, g3_vec3_scale(ray.dir, t)));
}

/// True when two axis-aligned boxes overlap; touching faces count as overlap
/// (inclusive bounds on every axis).
/// Complexity: O(1).
pub fn g3_aabb_overlap(a: G3Aabb, b: G3Aabb) -> Bool {
  if a.min.x > b.max.x || b.min.x > a.max.x { return false; }
  if a.min.y > b.max.y || b.min.y > a.max.y { return false; }
  if a.min.z > b.max.z || b.min.z > a.max.z { return false; }
  return true;
}

// --------------------------------------------------
//  Scene transform helper
// --------------------------------------------------

/// Construct a scene transform: rotate by `rotation`, scale uniformly by
/// `scale` (raw, G3_SCALE = 1.0), then translate by `position`.
/// Complexity: O(1).
pub fn g3_scene(position: G3Vec3, rotation: G3Quat, scale: Int) -> G3Scene {
  return G3Scene{ position: position; rotation: rotation; scale: scale; };
}

/// Identity scene: no rotation, unit scale, zero translation.
/// Complexity: O(1).
pub fn g3_scene_identity() -> G3Scene {
  return G3Scene{
    position: G3Vec3{ x: 0; y: 0; z: 0; };
    rotation: g3_quat_identity();
    scale: G3_SCALE;
  };
}

/// Transform a scene point: rotate(scale(p)) + position. A non-unit rotation
/// quaternion additionally multiplies the scaled point by |q|^2.
/// Complexity: O(1).
pub fn g3_scene_transform_point(s: G3Scene, p: G3Vec3) -> G3Vec3 {
  let k = s.scale;
  let scaled = G3Vec3{
    x: _g3_mul(p.x, k);
    y: _g3_mul(p.y, k);
    z: _g3_mul(p.z, k);
  };
  let r = s.rotation;
  let pos = s.position;
  return g3_vec3_add(g3_quat_rotate_vec(r, scaled), pos);
}

/// Transform a scene direction: rotate(scale(v)); translation is ignored.
/// Complexity: O(1).
pub fn g3_scene_transform_vector(s: G3Scene, v: G3Vec3) -> G3Vec3 {
  let k = s.scale;
  let r = s.rotation;
  return g3_quat_rotate_vec(r, g3_vec3_scale(v, k));
}
