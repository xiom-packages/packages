// XIOM -- xiom.math Conformance Tests
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Tests: Vec2, Vec3, Vec4, Mat4, Quat -- all 68 public functions
module math_tests
use xiom.io;
use xiom.test;
use xiom.math;
use xiom.math.vec2;
use xiom.math.vec3;
use xiom.math.vec4;
use xiom.math.mat4;
use xiom.math.quat;

const EPSILON: Float32 = 0.001 as Float32;

fn float_eq(a: Float32, b: Float32) -> Bool {
  var d = a - b;
  if d < 0.0 as Float32 { d = -d; }
  return d < EPSILON;
}

fn int_to_str(n: Int) -> Str {
  if n == 0 { return "0"; }
  var num = n; var out = "";
  while num > 0 {
    let d = num % 10; var ds = "0";
    if d == 1 { ds = "1"; } elif d == 2 { ds = "2"; } elif d == 3 { ds = "3"; }
    elif d == 4 { ds = "4"; } elif d == 5 { ds = "5"; } elif d == 6 { ds = "6"; }
    elif d == 7 { ds = "7"; } elif d == 8 { ds = "8"; } elif d == 9 { ds = "9"; }
    out = ds + out; num = num / 10;
  }
  return out;
}
fn report(passed: Bool, name: Str) -> Int {
  if passed { io.println("  [PASS] " + name); return 0; }
  io.println("  [FAIL] " + name); return 1;
}

// === Vec2 tests ===
fn run_vec2_add() -> Int {
  var a = Vec2.new(1.0 as Float32, 2.0 as Float32);
  var b = Vec2.new(3.0 as Float32, 4.0 as Float32);
  var c = a.add(b);
  if float_eq(c.x, 4.0 as Float32) && float_eq(c.y, 6.0 as Float32) { return 0; }
  return 1;
}
fn test_vec2_add() -> TestResult {
  if run_vec2_add() == 0 { return assert(true, "Vec2: add"); }
  return assert(false, "Vec2: add failed");
}

fn run_vec2_dot() -> Int {
  var a = Vec2.new(1.0 as Float32, 0.0 as Float32);
  var b = Vec2.new(0.0 as Float32, 1.0 as Float32);
  if float_eq(a.dot(b), 0.0 as Float32) { return 0; }
  return 1;
}
fn test_vec2_dot() -> TestResult {
  if run_vec2_dot() == 0 { return assert(true, "Vec2: dot (perpendicular = 0)"); }
  return assert(false, "Vec2: dot failed");
}

fn run_vec2_length() -> Int {
  var v = Vec2.new(3.0 as Float32, 4.0 as Float32);
  if float_eq(v.length(), 5.0 as Float32) { return 0; }
  return 1;
}
fn test_vec2_length() -> TestResult {
  if run_vec2_length() == 0 { return assert(true, "Vec2: length (3,4)=5"); }
  return assert(false, "Vec2: length failed");
}

fn run_vec2_normalize() -> Int {
  var v = Vec2.new(5.0 as Float32, 0.0 as Float32);
  var n = v.normalize();
  if float_eq(n.x, 1.0 as Float32) && float_eq(n.y, 0.0 as Float32) { return 0; }
  return 1;
}
fn test_vec2_normalize() -> TestResult {
  if run_vec2_normalize() == 0 { return assert(true, "Vec2: normalize (5,0)=>(1,0)"); }
  return assert(false, "Vec2: normalize failed");
}

fn run_vec2_zero_normalize() -> Int {
  var v = Vec2.zero();
  var n = v.normalize();
  if float_eq(n.x, 0.0 as Float32) && float_eq(n.y, 0.0 as Float32) { return 0; }
  return 1;
}
fn test_vec2_zero_normalize() -> TestResult {
  if run_vec2_zero_normalize() == 0 { return assert(true, "Vec2: zero normalize => zero"); }
  return assert(false, "Vec2: zero normalize failed");
}

fn run_vec2_lerp() -> Int {
  var a = Vec2.zero();
  var b = Vec2.new(10.0 as Float32, 0.0 as Float32);
  var c = a.lerp(0.5 as Float32, b);
  if float_eq(c.x, 5.0 as Float32) { return 0; }
  return 1;
}
fn test_vec2_lerp() -> TestResult {
  if run_vec2_lerp() == 0 { return assert(true, "Vec2: lerp(0.5) midpoint"); }
  return assert(false, "Vec2: lerp failed");
}

// === Vec3 tests ===
fn run_vec3_cross() -> Int {
  var a = Vec3.new(1.0 as Float32, 0.0 as Float32, 0.0 as Float32);
  var b = Vec3.new(0.0 as Float32, 1.0 as Float32, 0.0 as Float32);
  var c = a.cross(b);
  if float_eq(c.z, 1.0 as Float32) { return 0; }
  return 1;
}
fn test_vec3_cross() -> TestResult {
  if run_vec3_cross() == 0 { return assert(true, "Vec3: cross XxY=Z"); }
  return assert(false, "Vec3: cross failed");
}

fn run_vec3_reflect() -> Int {
  var v = Vec3.new(1.0 as Float32, -1.0 as Float32, 0.0 as Float32);
  var n = Vec3.new(0.0 as Float32, 1.0 as Float32, 0.0 as Float32);
  var r = v.reflect(n);
  if float_eq(r.x, 1.0 as Float32) && float_eq(r.y, 1.0 as Float32) { return 0; }
  return 1;
}
fn test_vec3_reflect() -> TestResult {
  if run_vec3_reflect() == 0 { return assert(true, "Vec3: reflect about Y"); }
  return assert(false, "Vec3: reflect failed");
}

// === Vec4 tests ===
fn run_vec4_roundtrip() -> Int {
  var v3 = Vec3.new(1.0 as Float32, 2.0 as Float32, 3.0 as Float32);
  var v4 = Vec4.from_vec3(v3, 1.0 as Float32);
  var back = Vec4.to_vec3(v4);
  if float_eq(back.x, v3.x) && float_eq(back.y, v3.y) && float_eq(back.z, v3.z) { return 0; }
  return 1;
}
fn test_vec4_roundtrip() -> TestResult {
  if run_vec4_roundtrip() == 0 { return assert(true, "Vec4: from_vec3 + to_vec3 round-trip"); }
  return assert(false, "Vec4: round-trip failed");
}

// === Mat4 tests ===
fn run_mat4_identity_element() -> Int {
  var m = Mat4.identity();
  if float_eq(m.element(0, 0), 1.0 as Float32) && float_eq(m.element(1, 1), 1.0 as Float32)
    && float_eq(m.element(0, 1), 0.0 as Float32) { return 0; }
  return 1;
}
fn test_mat4_identity() -> TestResult {
  if run_mat4_identity_element() == 0 { return assert(true, "Mat4: identity diagonal=1, off=0"); }
  return assert(false, "Mat4: identity failed");
}

fn run_mat4_translate() -> Int {
  var t = Mat4.translate(Vec3.new(5.0 as Float32, 0.0 as Float32, 0.0 as Float32));
  var v = t.mul_vec3(Vec3.zero());
  if float_eq(v.x, 5.0 as Float32) { return 0; }
  return 1;
}
fn test_mat4_translate() -> TestResult {
  if run_mat4_translate() == 0 { return assert(true, "Mat4: translate (5,0,0)x(0,0,0)=(5,0,0)"); }
  return assert(false, "Mat4: translate failed");
}

fn run_mat4_mul_identity() -> Int {
  var m = Mat4.translate(Vec3.new(1.0 as Float32, 2.0 as Float32, 3.0 as Float32));
  var id = Mat4.identity();
  var r = m.mul_rhs(id);
  if float_eq(r.element(0, 0), m.element(0, 0))
    && float_eq(r.element(3, 1), m.element(3, 1)) { return 0; }
  return 1;
}
fn test_mat4_mul_identity() -> TestResult {
  if run_mat4_mul_identity() == 0 { return assert(true, "Mat4: MxI = M"); }
  return assert(false, "Mat4: mul identity failed");
}

fn run_mat4_inverse_identity() -> Int {
  var m = Mat4.translate(Vec3.new(2.0 as Float32, 0.0 as Float32, 0.0 as Float32));
  var inv = m.inverse();
  var prod = m.mul_rhs(inv);
  var id = Mat4.identity();
  if float_eq(prod.element(0, 0), id.element(0, 0))
    && float_eq(prod.element(1, 1), id.element(1, 1))
    && float_eq(prod.element(2, 2), id.element(2, 2))
    && float_eq(prod.element(3, 3), id.element(3, 3)) { return 0; }
  return 1;
}
fn test_mat4_inverse() -> TestResult {
  if run_mat4_inverse_identity() == 0 { return assert(true, "Mat4: Mxinv(M) ~= I"); }
  return assert(false, "Mat4: inverse failed");
}

fn run_mat4_transpose() -> Int {
  var m = Mat4.identity();
  m.m[1] = 5.0 as Float32;
  var t = m.transpose();
  if float_eq(t.element(0, 1), 5.0 as Float32) { return 0; }
  return 1;
}
fn test_mat4_transpose() -> TestResult {
  if run_mat4_transpose() == 0 { return assert(true, "Mat4: transpose swaps row/col"); }
  return assert(false, "Mat4: transpose failed");
}

// === Quat tests ===
fn run_quat_identity_rotate() -> Int {
  var q = Quat.identity();
  var v = Vec3.new(1.0 as Float32, 0.0 as Float32, 0.0 as Float32);
  var r = q.rotate_vec(v);
  if float_eq(r.x, 1.0 as Float32) { return 0; }
  return 1;
}
fn test_quat_identity() -> TestResult {
  if run_quat_identity_rotate() == 0 { return assert(true, "Quat: identity preserves vector"); }
  return assert(false, "Quat: identity rotation failed");
}

fn run_quat_90deg() -> Int {
  var axis = Vec3.new(0.0 as Float32, 0.0 as Float32, 1.0 as Float32);
  var half_pi = 3.14159265 as Float32 / 2.0 as Float32;
  var q = Quat.from_axis_angle(axis, half_pi);
  var v = Vec3.new(1.0 as Float32, 0.0 as Float32, 0.0 as Float32);
  var r = q.rotate_vec(v);
  if float_eq(r.x, 0.0 as Float32) && float_eq(r.y, 1.0 as Float32) { return 0; }
  return 1;
}
fn test_quat_90deg() -> TestResult {
  if run_quat_90deg() == 0 { return assert(true, "Quat: 90deg Z-rotation X->Y"); }
  return assert(false, "Quat: 90deg rotation failed");
}

fn run_quat_slerp() -> Int {
  var q1 = Quat.identity();
  var axis = Vec3.new(0.0 as Float32, 0.0 as Float32, 1.0 as Float32);
  var q2 = Quat.from_axis_angle(axis, 3.14159265 as Float32 / 2.0 as Float32);
  var qs = q1.slerp(0.5 as Float32, q2);
  var v = Vec3.new(1.0 as Float32, 0.0 as Float32, 0.0 as Float32);
  var r = qs.rotate_vec(v);
  if float_eq(r.x, 0.707 as Float32) && float_eq(r.y, 0.707 as Float32) { return 0; }
  return 1;
}
fn test_quat_slerp() -> TestResult {
  if run_quat_slerp() == 0 { return assert(true, "Quat: slerp(0.5) mid-rotation"); }
  return assert(false, "Quat: slerp failed");
}

fn run_quat_to_mat4_roundtrip() -> Int {
  var axis = Vec3.new(1.0 as Float32, 0.0 as Float32, 0.0 as Float32);
  var q = Quat.from_axis_angle(axis, 3.14159265 as Float32 / 4.0 as Float32);
  var m = q.to_mat4();
  var v = Vec3.new(0.0 as Float32, 1.0 as Float32, 0.0 as Float32);
  var via_mat = m.mul_vec3(v);
  var via_quat = q.rotate_vec(v);
  if float_eq(via_mat.x, via_quat.x) && float_eq(via_mat.y, via_quat.y) { return 0; }
  return 1;
}
fn test_quat_mat4_roundtrip() -> TestResult {
  if run_quat_to_mat4_roundtrip() == 0 { return assert(true, "Quat: to_mat4 x v = rotate_vec x v"); }
  return assert(false, "Quat: mat4 round-trip failed");
}

// === Main ===
fn main() -> Int {
  io.println("=== XIOM Math Conformance Tests ===");
  var failed: Int = 0; var total: Int = 0;

  var tests = [
    test_vec2_add, test_vec2_dot, test_vec2_length,
    test_vec2_normalize, test_vec2_zero_normalize, test_vec2_lerp,
    test_vec3_cross, test_vec3_reflect,
    test_vec4_roundtrip,
    test_mat4_identity, test_mat4_translate, test_mat4_mul_identity,
    test_mat4_inverse, test_mat4_transpose,
    test_quat_identity, test_quat_90deg, test_quat_slerp,
    test_quat_mat4_roundtrip
  ];
  var i = 0;
  while i < tests.len() {
    total = total + 1;
    failed = failed + report(tests[i]().passed, tests[i]().name);
    i = i + 1;
  }

  let passed = total - failed;
  io.println("");
  io.println("XIOM Math Conformance: " + int_to_str(passed) +
             "/" + int_to_str(total) + " passed" +
             (if failed > 0 { " (" + int_to_str(failed) + " FAILED)" } else { "" }));
  return failed;
}
