// XIOM -- xiom.geom3d conformance tests (27 checks)
// Port task: prove the pure-XIOM fixed-point (scale 1e-4) 3D geometry module
// against its SPEC. Every expected value is an exact fixed-point result
// captured from the implementation contract (no tolerance except where the
// test name says so); every test is a direct call, no function tables.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Struct values are moved on every by-value call, so fixtures are produced by
// small constructor helpers and every call site gets a fresh value. No
// Vec[StructType], no lambdas, no string comparison.

module geom3d_tests
use xiom.io; use xiom.test; use xiom.geom3d;

// --------------------------------------------------
//  Fresh-value fixture constructors
// --------------------------------------------------

fn v3(x: Int, y: Int, z: Int) -> G3Vec3 {
  return g3_vec3(x, y, z);
}

// 90-degree rotation about Z with the exact raw 1/sqrt(2) literal 7071.
fn m3rz() -> G3Mat3 {
  return G3Mat3{ m00: 0; m01: -10000; m02: 0; m10: 10000; m11: 0; m12: 0; m20: 0; m21: 0; m22: 10000; };
}

fn q180z() -> G3Quat {
  return g3_quat_from_axis_angle(v3(0, 0, 10000), G3_PI);
}

fn q180x() -> G3Quat {
  return g3_quat_from_axis_angle(v3(10000, 0, 0), G3_PI);
}

fn q90z() -> G3Quat {
  return G3Quat{ w: 7071; x: 0; y: 0; z: 7071; };
}

// Triangle (0,0,0), (2,0,0), (0,2,0) in the z = 0 plane.
fn tri01() -> G3Triangle {
  return g3_triangle(v3(0, 0, 0), v3(20000, 0, 0), v3(0, 20000, 0));
}

// Unit box [0,1]^3.
fn box1() -> G3Aabb {
  return g3_aabb(v3(0, 0, 0), v3(10000, 10000, 10000));
}

// 180-degree Z rotation with translation (1, 2, 3).
fn m4a() -> G3Mat4 {
  return g3_mat4_from_quat_translation(q180z(), v3(10000, 20000, 30000));
}

fn m4ai() -> G3Mat4 {
  return g3_mat4_rigid_inverse(m4a());
}

// --------------------------------------------------
//  Vec3 checks
// --------------------------------------------------

fn t1() -> TestResult {
  var ok = true;
  let a = g3_vec3_add(v3(10000, -20000, 30000), v3(5000, 20000, -10000));
  if a.x != 15000 { ok = false; }
  if a.y != 0 { ok = false; }
  if a.z != 20000 { ok = false; }
  let b = g3_vec3_sub(v3(10000, -20000, 30000), v3(5000, 20000, -10000));
  if b.x != 5000 { ok = false; }
  if b.y != -40000 { ok = false; }
  if b.z != 40000 { ok = false; }
  return assert(ok, "vec3 add/sub: component-wise over signed raw values");
}

fn t2() -> TestResult {
  var ok = true;
  let s1 = g3_vec3_scale(v3(10000, 0, 0), 5000);
  if s1.x != 5000 { ok = false; }
  if s1.y != 0 || s1.z != 0 { ok = false; }
  let s2 = g3_vec3_scale(v3(1, 0, 0), 5000);
  if s2.x != 1 { ok = false; }
  let s3 = g3_vec3_scale(v3(1, 0, 0), 4999);
  if s3.x != 0 { ok = false; }
  let s4 = g3_vec3_scale(v3(-1, 0, 0), 5000);
  if s4.x != -1 { ok = false; }
  let s5 = g3_vec3_scale(v3(1, 0, 0), -5000);
  if s5.x != -1 { ok = false; }
  return assert(ok, "vec3 scale: 2.5*2 = 5; rounding half away from zero at 0.5 ulp");
}

fn t3() -> TestResult {
  var ok = true;
  let s1 = g3_vec3_scale(v3(9223372036854775807, 0, 0), G3_SCALE);
  if s1.x != 922337203685478 { ok = false; }
  let s2 = g3_vec3_scale(v3(-9223372036854775807, 0, 0), G3_SCALE);
  if s2.x != -922337203685478 { ok = false; }
  let a1 = g3_vec3_add(v3(9223372036854775807, 0, 0), v3(10000, 0, 0));
  if a1.x != 9223372036854775807 { ok = false; }
  let a2 = g3_vec3_sub(v3(-9223372036854775807, 0, 0), v3(10000, 0, 0));
  if a2.x != -9223372036854775807 { ok = false; }
  return assert(ok, "overflow guards: products and sums saturate at +/- 2^63-1, scale still rounds");
}

fn t4() -> TestResult {
  var ok = true;
  if g3_vec3_dot(v3(30000, 40000, 0), v3(10000, 0, 0)) != 30000 { ok = false; }
  if g3_vec3_dot(v3(30000, 40000, 0), v3(30000, 40000, 0)) != 250000 { ok = false; }
  if g3_vec3_dot(v3(10000, 0, 0), v3(0, 10000, 0)) != 0 { ok = false; }
  if g3_vec3_dot(v3(1, 2, 3), v3(1, 2, 3)) != 0 { ok = false; }
  return assert(ok, "vec3 dot: 3-4-5 squared = 25; orthogonal axes give 0; sub-ulp terms round to 0");
}

fn t5() -> TestResult {
  var ok = true;
  let c1 = g3_vec3_cross(v3(10000, 0, 0), v3(0, 10000, 0));
  if c1.x != 0 || c1.y != 0 { ok = false; }
  if c1.z != 10000 { ok = false; }
  let c2 = g3_vec3_cross(v3(10000, 20000, 30000), v3(-40000, 5000, 10000));
  if c2.x != 5000 { ok = false; }
  if c2.y != -130000 { ok = false; }
  if c2.z != 85000 { ok = false; }
  let ab = g3_vec3_cross(v3(10000, 20000, 30000), v3(-40000, 5000, 10000));
  let ba = g3_vec3_cross(v3(-40000, 5000, 10000), v3(10000, 20000, 30000));
  if ba.x != 0 - ab.x { ok = false; }
  if ba.y != 0 - ab.y { ok = false; }
  if ba.z != 0 - ab.z { ok = false; }
  return assert(ok, "vec3 cross: X x Y = Z, pinned mixed product, anti-commutative");
}

fn t6() -> TestResult {
  var ok = true;
  if g3_vec3_length2(v3(30000, 40000, 0)) != 2500000000 { ok = false; }
  if g3_vec3_length2(v3(1, 0, 0)) != 1 { ok = false; }
  let n1 = g3_vec3_normalize(v3(30000, 40000, 0));
  if n1.x != 6000 || n1.y != 8000 || n1.z != 0 { ok = false; }
  let n2 = g3_vec3_normalize(v3(10000, 0, 0));
  if n2.x != 10000 { ok = false; }
  let n3 = g3_vec3_normalize(v3(0, 0, 0));
  if n3.x != 0 || n3.y != 0 || n3.z != 0 { ok = false; }
  let n4 = g3_vec3_normalize(v3(1, 0, 0));
  if n4.x != 10000 { ok = false; }
  return assert(ok, "vec3 length2 raw 1e-8 units; normalize 3-4-5 = 0.6/0.8; zero vector total");
}

fn t7() -> TestResult {
  var ok = true;
  let n = g3_vec3_normalize(v3(-30000, -40000, 0));
  if n.x != -6000 || n.y != -8000 || n.z != 0 { ok = false; }
  let n2 = g3_vec3_normalize(v3(0, -10000, 0));
  if n2.y != -10000 { ok = false; }
  return assert(ok, "normalize keeps the signed direction (half-away rounding is odd)");
}

// --------------------------------------------------
//  Mat3 / Mat4 checks
// --------------------------------------------------

fn t8() -> TestResult {
  var ok = true;
  let t = g3_mat3_transpose(m3rz());
  if t.m00 != 0 || t.m01 != 10000 || t.m02 != 0 { ok = false; }
  if t.m10 != -10000 || t.m11 != 0 || t.m12 != 0 { ok = false; }
  if t.m20 != 0 || t.m21 != 0 || t.m22 != 10000 { ok = false; }
  let v = g3_mat3_transform_vec(g3_mat3_identity(), v3(10000, -20000, 30000));
  if v.x != 10000 || v.y != -20000 || v.z != 30000 { ok = false; }
  return assert(ok, "mat3 transpose swaps rows and columns; identity leaves a vector fixed");
}

fn t9() -> TestResult {
  var ok = true;
  let id = g3_mat3_mul(m3rz(), g3_mat3_transpose(m3rz()));
  if id.m00 != 10000 || id.m01 != 0 || id.m02 != 0 { ok = false; }
  if id.m10 != 0 || id.m11 != 10000 || id.m12 != 0 { ok = false; }
  if id.m20 != 0 || id.m21 != 0 || id.m22 != 10000 { ok = false; }
  return assert(ok, "mat3 multiply: Rz * Rz^T = identity exactly (orthogonal 90-degree fixture)");
}

fn t10() -> TestResult {
  var ok = true;
  let x = g3_mat3_transform_vec(m3rz(), v3(10000, 0, 0));
  if x.x != 0 || x.y != 10000 || x.z != 0 { ok = false; }
  let y = g3_mat3_transform_vec(m3rz(), v3(0, 10000, 0));
  if y.x != -10000 || y.y != 0 || y.z != 0 { ok = false; }
  return assert(ok, "mat3 transform_vec: +90 degrees about Z maps X to Y and Y to -X");
}

fn t11() -> TestResult {
  var ok = true;
  let p = g3_mat4_transform_point(g3_mat4_identity(), v3(10000, -20000, 30000));
  if p.x != 10000 || p.y != -20000 || p.z != 30000 { ok = false; }
  let v = g3_mat4_transform_vec(g3_mat4_identity(), v3(10000, -20000, 30000));
  if v.x != 10000 || v.y != -20000 || v.z != 30000 { ok = false; }
  let t = g3_mat4_transpose(m4a());
  if t.m03 != 0 || t.m13 != 0 || t.m23 != 0 { ok = false; }
  if t.m30 != 10000 || t.m31 != 20000 || t.m32 != 30000 { ok = false; }
  if t.m00 != -10000 || t.m11 != -10000 || t.m22 != 10000 { ok = false; }
  return assert(ok, "mat4 identity transforms; transpose moves the translation into the last row");
}

fn t12() -> TestResult {
  var ok = true;
  let m = m4a();
  if m.m00 != -10000 || m.m11 != -10000 || m.m22 != 10000 { ok = false; }
  if m.m01 != 0 || m.m02 != 0 || m.m10 != 0 || m.m12 != 0 || m.m20 != 0 || m.m21 != 0 { ok = false; }
  if m.m03 != 10000 || m.m13 != 20000 || m.m23 != 30000 { ok = false; }
  if m.m30 != 0 || m.m31 != 0 || m.m32 != 0 || m.m33 != 10000 { ok = false; }
  return assert(ok, "mat4 from 180-degree Z quaternion: diag(-1,-1,1) rotation plus translation (1,2,3)");
}

fn t13() -> TestResult {
  var ok = true;
  let p = g3_mat4_transform_point(m4a(), v3(10000, 0, 0));
  if p.x != 0 || p.y != 20000 || p.z != 30000 { ok = false; }
  let v = g3_mat4_transform_vec(m4a(), v3(10000, 0, 0));
  if v.x != -10000 || v.y != 0 || v.z != 0 { ok = false; }
  return assert(ok, "mat4 transform_point applies translation; transform_vec ignores it");
}

fn t14() -> TestResult {
  var ok = true;
  let inv = m4ai();
  if inv.m00 != -10000 || inv.m11 != -10000 || inv.m22 != 10000 { ok = false; }
  if inv.m03 != 10000 || inv.m13 != 20000 || inv.m23 != -30000 { ok = false; }
  if inv.m33 != 10000 { ok = false; }
  let id = g3_mat4_mul(m4a(), m4ai());
  if id.m00 != 10000 || id.m11 != 10000 || id.m22 != 10000 || id.m33 != 10000 { ok = false; }
  if id.m01 != 0 || id.m02 != 0 || id.m03 != 0 { ok = false; }
  if id.m10 != 0 || id.m12 != 0 || id.m13 != 0 { ok = false; }
  if id.m20 != 0 || id.m21 != 0 || id.m23 != 0 { ok = false; }
  if id.m30 != 0 || id.m31 != 0 || id.m32 != 0 { ok = false; }
  let back = g3_mat4_transform_point(m4ai(), v3(0, 20000, 30000));
  if back.x != 10000 || back.y != 0 || back.z != 0 { ok = false; }
  return assert(ok, "mat4 rigid inverse: R^T with -R^T t; M * M^-1 = identity exactly");
}

// --------------------------------------------------
//  Quaternion checks
// --------------------------------------------------

fn t15() -> TestResult {
  var ok = true;
  let id = g3_quat_identity();
  if id.w != 10000 || id.x != 0 || id.y != 0 || id.z != 0 { ok = false; }
  let c = g3_quat_conjugate(g3_quat(1000, -2000, 3000, -4000));
  if c.w != 1000 || c.x != 2000 || c.y != -3000 || c.z != 4000 { ok = false; }
  return assert(ok, "quat identity and conjugate (w, -x, -y, -z)");
}

fn t16() -> TestResult {
  var ok = true;
  let q = g3_quat(0, 1000, 2000, 3000);
  let a = g3_quat_mul(g3_quat_identity(), g3_quat(0, 1000, 2000, 3000));
  if a.w != q.w || a.x != q.x || a.y != q.y || a.z != q.z { ok = false; }
  let b = g3_quat_mul(g3_quat(0, 1000, 2000, 3000), g3_quat_identity());
  if b.w != 0 || b.x != 1000 || b.y != 2000 || b.z != 3000 { ok = false; }
  let sq = g3_quat_mul(q90z(), q90z());
  if sq.w != 0 || sq.x != 0 || sq.y != 0 || sq.z != 10000 { ok = false; }
  let zz = g3_quat_mul(q180z(), q180z());
  if zz.w != -10000 || zz.x != 0 || zz.y != 0 || zz.z != 0 { ok = false; }
  return assert(ok, "quat multiply: identity neutral; q90 * q90 = 180-degree Z; q180 * q180 = -identity");
}

fn t17() -> TestResult {
  var ok = true;
  let n = g3_quat_normalize(g3_quat(30000, 0, 0, 40000));
  if n.w != 6000 || n.x != 0 || n.y != 0 || n.z != 8000 { ok = false; }
  let z = g3_quat_normalize(g3_quat(0, 0, 0, 0));
  if z.w != 10000 || z.x != 0 || z.y != 0 || z.z != 0 { ok = false; }
  let c = g3_quat_mul(q180z(), g3_quat_conjugate(q180z()));
  if c.w != 10000 || c.x != 0 || c.y != 0 || c.z != 0 { ok = false; }
  return assert(ok, "quat normalize 3-0-0-4 = 0.6/0.8; zero quaternion -> identity; q * conj(q) = identity");
}

fn t18() -> TestResult {
  var ok = true;
  let x = g3_quat_rotate_vec(q180z(), v3(10000, 0, 0));
  if x.x != -10000 || x.y != 0 || x.z != 0 { ok = false; }
  let y = g3_quat_rotate_vec(q180z(), v3(0, 10000, 0));
  if y.x != 0 || y.y != -10000 || y.z != 0 { ok = false; }
  let z = g3_quat_rotate_vec(q180z(), v3(0, 0, 10000));
  if z.x != 0 || z.y != 0 || z.z != 10000 { ok = false; }
  let id = g3_quat_rotate_vec(g3_quat_identity(), v3(10000, -20000, 30000));
  if id.x != 10000 || id.y != -20000 || id.z != 30000 { ok = false; }
  return assert(ok, "quat rotate: 180 degrees about Z negates x and y axes, keeps z; identity keeps a vector");
}

fn t19() -> TestResult {
  var ok = true;
  let q = g3_quat_mul(q180x(), q180z());
  if q.w != 0 || q.x != 0 || q.y != -10000 || q.z != 0 { ok = false; }
  let x = g3_quat_rotate_vec(g3_quat_mul(q180x(), q180z()), v3(10000, 0, 0));
  if x.x != -10000 || x.y != 0 || x.z != 0 { ok = false; }
  let y = g3_quat_rotate_vec(g3_quat_mul(q180x(), q180z()), v3(0, 10000, 0));
  if y.x != 0 || y.y != 10000 || y.z != 0 { ok = false; }
  let z = g3_quat_rotate_vec(g3_quat_mul(q180x(), q180z()), v3(0, 0, 10000));
  if z.x != 0 || z.y != 0 || z.z != -10000 { ok = false; }
  return assert(ok, "rotation composition: 180 about X then Z = 180 about Y; axes pinned");
}

fn t20() -> TestResult {
  var ok = true;
  let a = g3_quat_rotate_vec(q90z(), v3(40000, 0, 0));
  if a.x != 0 || a.y != 39999 || a.z != 0 { ok = false; }
  let b = g3_quat_rotate_vec(q90z(), v3(0, 40000, 0));
  if b.x != -39999 || b.y != 0 || b.z != 0 { ok = false; }
  if g3_vec3_dot(v3(40000, 0, 0), g3_quat_rotate_vec(q90z(), v3(40000, 0, 0))) != 0 { ok = false; }
  if g3_vec3_length2(g3_quat_rotate_vec(q90z(), v3(40000, 0, 0))) != 1599920001 { ok = false; }
  return assert(ok, "90-degree literal quaternion: orthogonal to the source, length2 preserved within 8e4");
}

fn t21() -> TestResult {
  var ok = true;
  let i0 = g3_quat_from_axis_angle(v3(0, 0, 10000), 0);
  if i0.w != 10000 || i0.x != 0 || i0.y != 0 || i0.z != 0 { ok = false; }
  let pi = g3_quat_from_axis_angle(v3(0, 0, 10000), G3_PI);
  if pi.w != 0 || pi.x != 0 || pi.y != 0 || pi.z != 10000 { ok = false; }
  let mpi = g3_quat_from_axis_angle(v3(0, 0, 10000), 0 - G3_PI);
  if mpi.w != 0 || mpi.z != -10000 { ok = false; }
  let nu = g3_quat_from_axis_angle(v3(0, 0, 20000), G3_PI);
  if nu.w != 0 || nu.z != 10000 { ok = false; }
  let h = g3_quat_from_axis_angle(v3(0, 0, 10000), G3_HALF_PI);
  if h.w != 7072 || h.x != 0 || h.y != 0 || h.z != 7072 { ok = false; }
  let zero = g3_quat_from_axis_angle(v3(0, 0, 0), G3_PI);
  if zero.w != 10000 || zero.z != 0 { ok = false; }
  return assert(ok, "from_axis_angle: 0 -> identity, +/-pi -> exact 180-Z, half-pi -> 7072/7072, zero axis total");
}

// --------------------------------------------------
//  Intersection checks
// --------------------------------------------------

fn t22() -> TestResult {
  var ok = true;
  let h1 = g3_ray_plane(g3_ray(v3(0, 0, 0), v3(0, 0, 10000)), g3_plane(v3(0, 0, 10000), 5000));
  if !h1.hit { ok = false; }
  if h1.t != 5000 || h1.px != 0 || h1.py != 0 || h1.pz != 5000 { ok = false; }
  let h2 = g3_ray_plane(g3_ray(v3(0, 0, 0), v3(20000, 0, 0)), g3_plane(v3(10000, 0, 0), 5000));
  if !h2.hit || h2.t != 2500 || h2.px != 5000 || h2.py != 0 || h2.pz != 0 { ok = false; }
  let h3 = g3_ray_plane(g3_ray(v3(0, 0, 10000), v3(0, 0, -10000)), g3_plane(v3(0, 0, 10000), 5000));
  if !h3.hit || h3.t != 5000 || h3.pz != 5000 { ok = false; }
  let m1 = g3_ray_plane(g3_ray(v3(0, 0, 6000), v3(0, 0, 10000)), g3_plane(v3(0, 0, 10000), 5000));
  if m1.hit { ok = false; }
  let m2 = g3_ray_plane(g3_ray(v3(0, 0, 0), v3(10000, 0, 0)), g3_plane(v3(0, 0, 10000), 5000));
  if m2.hit { ok = false; }
  let r = g3_ray_plane(g3_ray(v3(0, 0, 0), v3(0, 0, 30000)), g3_plane(v3(0, 0, 10000), 5000));
  if !r.hit || r.t != 1667 || r.pz != 5001 { ok = false; }
  return assert(ok, "ray-plane: exact t = 0.5 with unit and non-unit dirs, negative den, behind and parallel miss, rounded t -> rounded point");
}

fn t23() -> TestResult {
  var ok = true;
  let h = g3_ray_triangle(g3_ray(v3(5000, 5000, 10000), v3(0, 0, -10000)), tri01());
  if !h.hit || h.t != 10000 || h.px != 5000 || h.py != 5000 || h.pz != 0 { ok = false; }
  let v0 = g3_ray_triangle(g3_ray(v3(0, 0, 10000), v3(0, 0, -10000)), tri01());
  if !v0.hit || v0.t != 10000 || v0.px != 0 || v0.py != 0 { ok = false; }
  let e = g3_ray_triangle(g3_ray(v3(20000, 0, 10000), v3(0, 0, -10000)), tri01());
  if !e.hit || e.px != 20000 || e.py != 0 { ok = false; }
  let below = g3_ray_triangle(g3_ray(v3(5000, 5000, -10000), v3(0, 0, 10000)), tri01());
  if !below.hit || below.t != 10000 { ok = false; }
  let off = g3_ray_triangle(g3_ray(v3(12000, 12000, 10000), v3(0, 0, -10000)), tri01());
  if off.hit { ok = false; }
  let out = g3_ray_triangle(g3_ray(v3(30000, 5000, 10000), v3(0, 0, -10000)), tri01());
  if out.hit { ok = false; }
  let behind = g3_ray_triangle(g3_ray(v3(5000, 5000, 10000), v3(0, 0, 10000)), tri01());
  if behind.hit { ok = false; }
  let par = g3_ray_triangle(g3_ray(v3(5000, 5000, 10000), v3(0, 20000, 0)), tri01());
  if par.hit { ok = false; }
  let deg = g3_ray_triangle(g3_ray(v3(5000, 5000, 10000), v3(0, 0, -10000)), g3_triangle(v3(0, 0, 0), v3(10000, 0, 0), v3(20000, 0, 0)));
  if deg.hit { ok = false; }
  return assert(ok, "ray-triangle Moller-Trumbore: interior/vertex/edge/below hits at t = 1, outside/behind/parallel/degenerate miss");
}

fn t24() -> TestResult {
  var ok = true;
  let h = g3_ray_aabb(g3_ray(v3(-5000, 5000, 5000), v3(10000, 0, 0)), box1());
  if !h.hit || h.t != 5000 || h.px != 0 || h.py != 5000 || h.pz != 5000 { ok = false; }
  let inside = g3_ray_aabb(g3_ray(v3(5000, 5000, 5000), v3(10000, 0, 0)), box1());
  if !inside.hit || inside.t != 0 || inside.px != 5000 || inside.py != 5000 || inside.pz != 5000 { ok = false; }
  let neg = g3_ray_aabb(g3_ray(v3(20000, 5000, 5000), v3(-10000, 0, 0)), box1());
  if !neg.hit || neg.t != 10000 || neg.px != 10000 || neg.py != 5000 { ok = false; }
  let touch = g3_ray_aabb(g3_ray(v3(-5000, 0, 5000), v3(10000, 0, 0)), box1());
  if !touch.hit || touch.t != 5000 || touch.px != 0 || touch.py != 0 { ok = false; }
  let parout = g3_ray_aabb(g3_ray(v3(-5000, 20000, 5000), v3(10000, 0, 0)), box1());
  if parout.hit { ok = false; }
  let behind = g3_ray_aabb(g3_ray(v3(20000, 5000, 5000), v3(10000, 0, 0)), box1());
  if behind.hit { ok = false; }
  return assert(ok, "ray-AABB slabs: entry at 0.5, inside returns t = 0, negative dir enters at the far face, touch counts, miss cases");
}

fn t25() -> TestResult {
  var ok = true;
  let touch = g3_aabb_overlap(
    g3_aabb(v3(0, 0, 0), v3(10000, 10000, 10000)),
    g3_aabb(v3(10000, 10000, 10000), v3(20000, 20000, 20000)));
  if !touch { ok = false; }
  let gap = g3_aabb_overlap(
    g3_aabb(v3(0, 0, 0), v3(10000, 10000, 10000)),
    g3_aabb(v3(10001, 0, 0), v3(20000, 20000, 20000)));
  if gap { ok = false; }
  let inside = g3_aabb_overlap(
    g3_aabb(v3(2000, 2000, 2000), v3(3000, 3000, 3000)), box1());
  if !inside { ok = false; }
  let sep = g3_aabb_overlap(
    g3_aabb(v3(-10000, -10000, -10000), v3(-5000, -5000, -5000)), box1());
  if sep { ok = false; }
  return assert(ok, "AABB overlap: touching faces overlap, a 1-ulp gap does not, containment and separation");
}

// --------------------------------------------------
//  Scene helper checks
// --------------------------------------------------

fn t26() -> TestResult {
  var ok = true;
  let p = g3_scene_transform_point(g3_scene_identity(), v3(10000, -20000, 30000));
  if p.x != 10000 || p.y != -20000 || p.z != 30000 { ok = false; }
  let v = g3_scene_transform_vector(g3_scene_identity(), v3(10000, -20000, 30000));
  if v.x != 10000 || v.y != -20000 || v.z != 30000 { ok = false; }
  let sc = g3_scene(v3(10000, 0, 0), g3_quat_identity(), 20000);
  let q = g3_scene_transform_point(sc, v3(30000, 10000, 0));
  if q.x != 70000 || q.y != 20000 || q.z != 0 { ok = false; }
  let w = g3_scene_transform_vector(g3_scene(v3(10000, 0, 0), g3_quat_identity(), 20000), v3(30000, 10000, 0));
  if w.x != 60000 || w.y != 20000 || w.z != 0 { ok = false; }
  return assert(ok, "scene: identity, and scale 2 then translate (1,0,0); vector ignores translation");
}

fn t27() -> TestResult {
  var ok = true;
  let r = g3_scene(
    v3(0, 0, 0),
    g3_quat_from_axis_angle(v3(0, 0, 10000), G3_PI),
    G3_SCALE);
  let p = g3_scene_transform_point(r, v3(10000, 20000, 0));
  if p.x != -10000 || p.y != -20000 || p.z != 0 { ok = false; }
  let v = g3_scene_transform_vector(
    g3_scene(v3(0, 0, 0), g3_quat_from_axis_angle(v3(0, 0, 10000), G3_PI), G3_SCALE),
    v3(10000, 20000, 0));
  if v.x != -10000 || v.y != -20000 || v.z != 0 { ok = false; }
  let mixed = g3_scene(v3(10000, 0, 0), g3_quat_from_axis_angle(v3(0, 0, 10000), G3_PI), 20000);
  let m = g3_scene_transform_point(mixed, v3(30000, 10000, 0));
  if m.x != -50000 || m.y != -20000 || m.z != 0 { ok = false; }
  return assert(ok, "scene rotation: 180 about Z flips point and vector; scale 2 with flip and translation");
}

fn main() -> Int {
  io.println("=== xiom.geom3d conformance tests ===");
  var failed: Int = 0;
  let r1 = t1();
  if r1.passed { io.println("  [PASS] " + r1.name); } else { io.println("  [FAIL] " + r1.name); failed = failed + 1; }
  let r2 = t2();
  if r2.passed { io.println("  [PASS] " + r2.name); } else { io.println("  [FAIL] " + r2.name); failed = failed + 1; }
  let r3 = t3();
  if r3.passed { io.println("  [PASS] " + r3.name); } else { io.println("  [FAIL] " + r3.name); failed = failed + 1; }
  let r4 = t4();
  if r4.passed { io.println("  [PASS] " + r4.name); } else { io.println("  [FAIL] " + r4.name); failed = failed + 1; }
  let r5 = t5();
  if r5.passed { io.println("  [PASS] " + r5.name); } else { io.println("  [FAIL] " + r5.name); failed = failed + 1; }
  let r6 = t6();
  if r6.passed { io.println("  [PASS] " + r6.name); } else { io.println("  [FAIL] " + r6.name); failed = failed + 1; }
  let r7 = t7();
  if r7.passed { io.println("  [PASS] " + r7.name); } else { io.println("  [FAIL] " + r7.name); failed = failed + 1; }
  let r8 = t8();
  if r8.passed { io.println("  [PASS] " + r8.name); } else { io.println("  [FAIL] " + r8.name); failed = failed + 1; }
  let r9 = t9();
  if r9.passed { io.println("  [PASS] " + r9.name); } else { io.println("  [FAIL] " + r9.name); failed = failed + 1; }
  let r10 = t10();
  if r10.passed { io.println("  [PASS] " + r10.name); } else { io.println("  [FAIL] " + r10.name); failed = failed + 1; }
  let r11 = t11();
  if r11.passed { io.println("  [PASS] " + r11.name); } else { io.println("  [FAIL] " + r11.name); failed = failed + 1; }
  let r12 = t12();
  if r12.passed { io.println("  [PASS] " + r12.name); } else { io.println("  [FAIL] " + r12.name); failed = failed + 1; }
  let r13 = t13();
  if r13.passed { io.println("  [PASS] " + r13.name); } else { io.println("  [FAIL] " + r13.name); failed = failed + 1; }
  let r14 = t14();
  if r14.passed { io.println("  [PASS] " + r14.name); } else { io.println("  [FAIL] " + r14.name); failed = failed + 1; }
  let r15 = t15();
  if r15.passed { io.println("  [PASS] " + r15.name); } else { io.println("  [FAIL] " + r15.name); failed = failed + 1; }
  let r16 = t16();
  if r16.passed { io.println("  [PASS] " + r16.name); } else { io.println("  [FAIL] " + r16.name); failed = failed + 1; }
  let r17 = t17();
  if r17.passed { io.println("  [PASS] " + r17.name); } else { io.println("  [FAIL] " + r17.name); failed = failed + 1; }
  let r18 = t18();
  if r18.passed { io.println("  [PASS] " + r18.name); } else { io.println("  [FAIL] " + r18.name); failed = failed + 1; }
  let r19 = t19();
  if r19.passed { io.println("  [PASS] " + r19.name); } else { io.println("  [FAIL] " + r19.name); failed = failed + 1; }
  let r20 = t20();
  if r20.passed { io.println("  [PASS] " + r20.name); } else { io.println("  [FAIL] " + r20.name); failed = failed + 1; }
  let r21 = t21();
  if r21.passed { io.println("  [PASS] " + r21.name); } else { io.println("  [FAIL] " + r21.name); failed = failed + 1; }
  let r22 = t22();
  if r22.passed { io.println("  [PASS] " + r22.name); } else { io.println("  [FAIL] " + r22.name); failed = failed + 1; }
  let r23 = t23();
  if r23.passed { io.println("  [PASS] " + r23.name); } else { io.println("  [FAIL] " + r23.name); failed = failed + 1; }
  let r24 = t24();
  if r24.passed { io.println("  [PASS] " + r24.name); } else { io.println("  [FAIL] " + r24.name); failed = failed + 1; }
  let r25 = t25();
  if r25.passed { io.println("  [PASS] " + r25.name); } else { io.println("  [FAIL] " + r25.name); failed = failed + 1; }
  let r26 = t26();
  if r26.passed { io.println("  [PASS] " + r26.name); } else { io.println("  [FAIL] " + r26.name); failed = failed + 1; }
  let r27 = t27();
  if r27.passed { io.println("  [PASS] " + r27.name); } else { io.println("  [FAIL] " + r27.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.geom3d: all tests passed");
  } else {
    io.println("xiom.geom3d: tests failed");
  }
  return failed;
}
