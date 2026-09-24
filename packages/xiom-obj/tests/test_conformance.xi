// XIOM -- xiom.obj conformance tests (23 checks)
// Port task: prove the pure-XIOM xiom.obj module against its SPEC.md.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Coverage map (see SPEC.md section 8): coordinate scaling and truncation,
// signs and optional w, triangle/quad polygons kept as-is, every index form
// (n, n/t, n//n, n/t/n), negative index resolution, comments and ignored
// records, CRLF line endings, empty input, malformed vertices and faces,
// index 0 / beyond-count rejection, faces seeing only earlier vertices,
// accessor defaults, scale 1, and a pinned 2x2 quad fixture.
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every error message
// check below is routed through streq/err_is instead of `==`.

module obj_tests
use xiom.io; use xiom.test; use xiom.obj;
use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// True when parsing fails with exactly `want`.
fn err_is(r: Result[ObjMesh, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// True when vertex i has exactly the given scaled coordinates.
fn vertex_is(m: &ObjMesh, i: Int, x: Int, y: Int, z: Int) -> Bool {
  var ok = obj_vertex_x(m, i) == x;
  if obj_vertex_y(m, i) != y { ok = false; }
  if obj_vertex_z(m, i) != z { ok = false; }
  return ok;
}

// True when face f is a triangle with the given indices.
fn face3_is(m: &ObjMesh, f: Int, a: Int, b: Int, c: Int) -> Bool {
  var ok = obj_face_len(m, f) == 3;
  if obj_face_index(m, f, 0) != a { ok = false; }
  if obj_face_index(m, f, 1) != b { ok = false; }
  if obj_face_index(m, f, 2) != c { ok = false; }
  return ok;
}

// True when face f is a quad with the given indices.
fn face4_is(m: &ObjMesh, f: Int, a: Int, b: Int, c: Int, d: Int) -> Bool {
  var ok = obj_face_len(m, f) == 4;
  if obj_face_index(m, f, 0) != a { ok = false; }
  if obj_face_index(m, f, 1) != b { ok = false; }
  if obj_face_index(m, f, 2) != c { ok = false; }
  if obj_face_index(m, f, 3) != d { ok = false; }
  return ok;
}

fn t1() -> TestResult {
  let r = obj_parse("v 1 2 3\nv -4 5.5 -6.25", 1000);
  match r {
    Ok(m) => {
      var ok = obj_vertex_count(&m) == 2;
      if !vertex_is(&m, 0, 1000, 2000, 3000) { ok = false; }
      if !vertex_is(&m, 1, -4000, 5500, -6250) { ok = false; }
      return assert(ok, "vertices: integers and decimals scaled 1000");
    },
    Err(_) => { return assert(false, "vertices: integers and decimals scaled 1000"); },
  }
  return assert(false, "unreachable");
}

fn t2() -> TestResult {
  let r = obj_parse("v 0.0001 1.9999 -2.5\nv -0.0009 2.0009 -0.001", 1000);
  match r {
    Ok(m) => {
      var ok = obj_vertex_count(&m) == 2;
      if !vertex_is(&m, 0, 0, 1999, -2500) { ok = false; }
      if !vertex_is(&m, 1, 0, 2000, -1) { ok = false; }
      return assert(ok, "vertices: exact truncation toward zero at scale 1000");
    },
    Err(_) => { return assert(false, "vertices: exact truncation toward zero at scale 1000"); },
  }
  return assert(false, "unreachable");
}

fn t3() -> TestResult {
  let r = obj_parse("v +1 -2 +3\nv 4 5 6 7\nv 8 9 10 1 0 0 1", 1);
  match r {
    Ok(m) => {
      var ok = obj_vertex_count(&m) == 3;
      if !vertex_is(&m, 0, 1, -2, 3) { ok = false; }
      if !vertex_is(&m, 1, 4, 5, 6) { ok = false; }
      if !vertex_is(&m, 2, 8, 9, 10) { ok = false; }
      return assert(ok, "vertices: signs, optional w and extra tokens ignored");
    },
    Err(_) => { return assert(false, "vertices: signs, optional w and extra tokens ignored"); },
  }
  return assert(false, "unreachable");
}

fn t4() -> TestResult {
  let r = obj_parse("v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3", 1);
  match r {
    Ok(m) => {
      var ok = obj_vertex_count(&m) == 3;
      if obj_face_count(&m) != 1 { ok = false; }
      if !face3_is(&m, 0, 0, 1, 2) { ok = false; }
      return assert(ok, "faces: triangle kept as-is");
    },
    Err(_) => { return assert(false, "faces: triangle kept as-is"); },
  }
  return assert(false, "unreachable");
}

fn t5() -> TestResult {
  let r = obj_parse("v 0 0 0\nv 1 0 0\nv 0 1 0\nv 1 1 0\nf 1 2 4 3", 1000);
  match r {
    Ok(m) => {
      var ok = obj_vertex_count(&m) == 4;
      if obj_face_count(&m) != 1 { ok = false; }
      if !face4_is(&m, 0, 0, 1, 3, 2) { ok = false; }
      return assert(ok, "faces: quad kept as-is (no triangulation)");
    },
    Err(_) => { return assert(false, "faces: quad kept as-is (no triangulation)"); },
  }
  return assert(false, "unreachable");
}

fn t6() -> TestResult {
  let r = obj_parse("v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1/1 2/2 3/3\nf 1//1 2//2 3//3\nf 1/1/1 2/2/2 3/3/3", 1);
  match r {
    Ok(m) => {
      var ok = obj_face_count(&m) == 3;
      if !face3_is(&m, 0, 0, 1, 2) { ok = false; }
      if !face3_is(&m, 1, 0, 1, 2) { ok = false; }
      if !face3_is(&m, 2, 0, 1, 2) { ok = false; }
      return assert(ok, "index forms: n/t, n//n and n/t/n");
    },
    Err(_) => { return assert(false, "index forms: n/t, n//n and n/t/n"); },
  }
  return assert(false, "unreachable");
}

fn t7() -> TestResult {
  let r = obj_parse("v 0 0 0\nv 1 0 0\nv 0 1 0\nv 1 1 0\nf -4 -3 -2 -1\nf -3 -2 -1", 1);
  match r {
    Ok(m) => {
      var ok = obj_face_count(&m) == 2;
      if !face4_is(&m, 0, 0, 1, 2, 3) { ok = false; }
      if !face3_is(&m, 1, 1, 2, 3) { ok = false; }
      return assert(ok, "negative indices resolve against the current vertex count");
    },
    Err(_) => { return assert(false, "negative indices resolve against the current vertex count"); },
  }
  return assert(false, "unreachable");
}

fn t8() -> TestResult {
  let text = "# leading comment\nvt 0 0\nvn 0 0 1\nvp 0.5 0.5\ng group1\no cube\ns 1\nusemtl red\nmtllib cube.mtl\n\n   # indented comment\nv 1 2 3\nf 1 1 1 # inline comment";
  let r = obj_parse(text, 1000);
  match r {
    Ok(m) => {
      var ok = obj_vertex_count(&m) == 1;
      if obj_face_count(&m) != 1 { ok = false; }
      if !vertex_is(&m, 0, 1000, 2000, 3000) { ok = false; }
      if !face3_is(&m, 0, 0, 0, 0) { ok = false; }
      return assert(ok, "comments and ignored records are skipped");
    },
    Err(_) => { return assert(false, "comments and ignored records are skipped"); },
  }
  return assert(false, "unreachable");
}

fn t9() -> TestResult {
  let r = obj_parse("v 1 2 3\r\nv 4 5 6\r\nf 1 2 2\r\n", 1);
  match r {
    Ok(m) => {
      var ok = obj_vertex_count(&m) == 2;
      if obj_face_count(&m) != 1 { ok = false; }
      if !vertex_is(&m, 0, 1, 2, 3) { ok = false; }
      if !vertex_is(&m, 1, 4, 5, 6) { ok = false; }
      if !face3_is(&m, 0, 0, 1, 1) { ok = false; }
      return assert(ok, "CRLF line endings parse like LF");
    },
    Err(_) => { return assert(false, "CRLF line endings parse like LF"); },
  }
  return assert(false, "unreachable");
}

fn t10() -> TestResult {
  let r1 = obj_parse("", 1000);
  var ok = false;
  match r1 {
    Ok(m) => {
      ok = obj_vertex_count(&m) == 0;
      if obj_face_count(&m) != 0 { ok = false; }
      if obj_vertex_x(&m, 0) != 0 { ok = false; }
      if obj_vertex_y(&m, -1) != 0 { ok = false; }
      if obj_vertex_z(&m, 0) != 0 { ok = false; }
      if obj_face_len(&m, 0) != 0 { ok = false; }
      if obj_face_index(&m, 0, 0) != -1 { ok = false; }
    },
    Err(_) => { return assert(false, "empty input yields an empty mesh"); },
  }
  let r2 = obj_parse("\n\n \n", 1000);
  match r2 {
    Ok(m) => {
      if obj_vertex_count(&m) != 0 { ok = false; }
      if obj_face_count(&m) != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r3 = obj_parse("# only a comment\n   # indented\n", 1000);
  match r3 {
    Ok(m) => {
      if obj_vertex_count(&m) != 0 { ok = false; }
      if obj_face_count(&m) != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "empty input yields an empty mesh");
}

fn t11() -> TestResult {
  let r1 = obj_parse("v 1 2", 1000);
  var ok = err_is(r1, "obj: malformed vertex at line 1");
  let r2 = obj_parse("v 1 x 3", 1000);
  if !err_is(r2, "obj: malformed vertex at line 1") { ok = false; }
  let r3 = obj_parse("v 1 2 3.4.5", 1000);
  if !err_is(r3, "obj: malformed vertex at line 1") { ok = false; }
  let r4 = obj_parse("v 1e3 0 0", 1000);
  if !err_is(r4, "obj: malformed vertex at line 1") { ok = false; }
  let r5 = obj_parse("v 1234567890123 0 0", 1000);
  if !err_is(r5, "obj: malformed vertex at line 1") { ok = false; }
  let r6 = obj_parse("v 0.1234567891 0 0", 1000);
  if !err_is(r6, "obj: malformed vertex at line 1") { ok = false; }
  let r7 = obj_parse("v 1 2 3\nv 1 2", 1000);
  if !err_is(r7, "obj: malformed vertex at line 2") { ok = false; }
  let r8 = obj_parse("v 1 2 3\nv 1 2 3\nvt 1 2\nv 1 2", 1000);
  if !err_is(r8, "obj: malformed vertex at line 4") { ok = false; }
  return assert(ok, "malformed vertex records are rejected");
}

fn t12() -> TestResult {
  let r1 = obj_parse("v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2", 1);
  var ok = err_is(r1, "obj: malformed face at line 4");
  let r2 = obj_parse("v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 x", 1);
  if !err_is(r2, "obj: malformed face at line 4") { ok = false; }
  let r3 = obj_parse("v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3/", 1);
  if !err_is(r3, "obj: malformed face at line 4") { ok = false; }
  let r4 = obj_parse("v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3//", 1);
  if !err_is(r4, "obj: malformed face at line 4") { ok = false; }
  let r5 = obj_parse("v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3/1/2/3", 1);
  if !err_is(r5, "obj: malformed face at line 4") { ok = false; }
  let r6 = obj_parse("f", 1);
  if !err_is(r6, "obj: malformed face at line 1") { ok = false; }
  return assert(ok, "malformed face records are rejected");
}

fn t13() -> TestResult {
  let r1 = obj_parse("v 0 0 0\nf 0 1 1", 1000);
  var ok = err_is(r1, "obj: index out of range at line 2");
  let r2 = obj_parse("v 0 0 0\nv 1 0 0\nf 1 2 3", 1000);
  if !err_is(r2, "obj: index out of range at line 3") { ok = false; }
  let r3 = obj_parse("v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 4", 1000);
  if !err_is(r3, "obj: index out of range at line 4") { ok = false; }
  let r4 = obj_parse("v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 -4", 1000);
  if !err_is(r4, "obj: index out of range at line 4") { ok = false; }
  let r5 = obj_parse("v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1/1 2/2 -4/1", 1000);
  if !err_is(r5, "obj: index out of range at line 4") { ok = false; }
  return assert(ok, "index 0 and out-of-range indices are rejected");
}

fn t14() -> TestResult {
  let r1 = obj_parse("f 1 2 3\nv 0 0 0\nv 1 0 0\nv 0 1 0", 1);
  var ok = err_is(r1, "obj: index out of range at line 1");
  let r2 = obj_parse("v 0 0 0\nv 1 0 0\nv 0 1 0\nf -1 -2 -3\nv 9 9 9", 1);
  match r2 {
    Ok(m) => {
      if obj_vertex_count(&m) != 4 { ok = false; }
      if !face3_is(&m, 0, 2, 1, 0) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "faces can only reference earlier vertices");
}

fn t15() -> TestResult {
  let r = obj_parse("v 0 0 0\nv 1 2 3\nf 1 2 2", 1);
  match r {
    Ok(m) => {
      var ok = obj_vertex_count(&m) == 2;
      if obj_face_count(&m) != 1 { ok = false; }
      if !vertex_is(&m, 0, 0, 0, 0) { ok = false; }
      if !vertex_is(&m, 1, 1, 2, 3) { ok = false; }
      if obj_vertex_x(&m, -1) != 0 { ok = false; }
      if obj_vertex_x(&m, 2) != 0 { ok = false; }
      if obj_vertex_y(&m, 7) != 0 { ok = false; }
      if obj_vertex_z(&m, -9) != 0 { ok = false; }
      if obj_face_len(&m, -1) != 0 { ok = false; }
      if obj_face_len(&m, 1) != 0 { ok = false; }
      if obj_face_len(&m, 0) != 3 { ok = false; }
      if obj_face_index(&m, 0, -1) != -1 { ok = false; }
      if obj_face_index(&m, 0, 3) != -1 { ok = false; }
      if obj_face_index(&m, 1, 0) != -1 { ok = false; }
      if obj_face_index(&m, -1, 0) != -1 { ok = false; }
      if obj_face_index(&m, 0, 0) != 0 { ok = false; }
      if obj_face_index(&m, 0, 1) != 1 { ok = false; }
      if obj_face_index(&m, 0, 2) != 1 { ok = false; }
      return assert(ok, "accessors handle out-of-range indices");
    },
    Err(_) => { return assert(false, "accessors handle out-of-range indices"); },
  }
  return assert(false, "unreachable");
}

fn t16() -> TestResult {
  let r = obj_parse("v 1.9 -2.9 0.5\nv -0.9 2.999 1.001", 1);
  match r {
    Ok(m) => {
      var ok = obj_vertex_count(&m) == 2;
      if !vertex_is(&m, 0, 1, -2, 0) { ok = false; }
      if !vertex_is(&m, 1, 0, 2, 1) { ok = false; }
      return assert(ok, "scale 1 truncates fractional coordinates toward zero");
    },
    Err(_) => { return assert(false, "scale 1 truncates fractional coordinates toward zero"); },
  }
  return assert(false, "unreachable");
}

fn t17() -> TestResult {
  let text = "# 2x2 quad fixture\nv 0 0 0\nv 2 0 0\nv 2 2 0\nv 0 2 0\nf 1 2 3 4\n";
  let r = obj_parse(text, 1000);
  match r {
    Ok(m) => {
      var ok = obj_vertex_count(&m) == 4;
      if obj_face_count(&m) != 1 { ok = false; }
      if !vertex_is(&m, 0, 0, 0, 0) { ok = false; }
      if !vertex_is(&m, 1, 2000, 0, 0) { ok = false; }
      if !vertex_is(&m, 2, 2000, 2000, 0) { ok = false; }
      if !vertex_is(&m, 3, 0, 2000, 0) { ok = false; }
      if !face4_is(&m, 0, 0, 1, 2, 3) { ok = false; }
      return assert(ok, "2x2 quad fixture is pinned");
    },
    Err(_) => { return assert(false, "2x2 quad fixture is pinned"); },
  }
  return assert(false, "unreachable");
}

fn t18() -> TestResult {
  let r = obj_parse("v 0 0 0\nv 1 0 0\nv 0 1 0\nv 1 1 0\nf 1 2 3\nf 2 4 3", 1000);
  match r {
    Ok(m) => {
      var ok = obj_face_count(&m) == 2;
      if !face3_is(&m, 0, 0, 1, 2) { ok = false; }
      if !face3_is(&m, 1, 1, 3, 2) { ok = false; }
      return assert(ok, "multiple faces share vertices with correct ranges");
    },
    Err(_) => { return assert(false, "multiple faces share vertices with correct ranges"); },
  }
  return assert(false, "unreachable");
}

fn t19() -> TestResult {
  let r1 = obj_parse("v 1 2 3\nl 1 2\n", 1000);
  var ok = err_is(r1, "obj: unknown record at line 2");
  let r2 = obj_parse("p 1\n", 1000);
  if !err_is(r2, "obj: unknown record at line 1") { ok = false; }
  let r3 = obj_parse("V 1 2 3\n", 1000);
  if !err_is(r3, "obj: unknown record at line 1") { ok = false; }
  return assert(ok, "unknown records are rejected");
}

fn t20() -> TestResult {
  let r1 = obj_parse("v 1 2 3", 0);
  var ok = err_is(r1, "obj: scale out of range");
  let r2 = obj_parse("v 1 2 3", -5);
  if !err_is(r2, "obj: scale out of range") { ok = false; }
  let r3 = obj_parse("", 1000001);
  if !err_is(r3, "obj: scale out of range") { ok = false; }
  let low = obj_parse("", 1);
  match low {
    Ok(m) => { if obj_vertex_count(&m) != 0 { ok = false; } },
    Err(_) => { ok = false; },
  }
  let high = obj_parse("", 1000000);
  match high {
    Ok(m) => { if obj_face_count(&m) != 0 { ok = false; } },
    Err(_) => { ok = false; },
  }
  return assert(ok, "scale must be in 1..1000000");
}

fn t21() -> TestResult {
  let r1 = obj_parse("\n# c\nv 1 2\n", 1000);
  var ok = err_is(r1, "obj: malformed vertex at line 3");
  let r2 = obj_parse("# c\r\nv 1 2\r\n", 1000);
  if !err_is(r2, "obj: malformed vertex at line 2") { ok = false; }
  return assert(ok, "error line numbers count blank and comment lines");
}

fn t22() -> TestResult {
  let r = obj_parse("v 0 0 0\nv 1 0 0\nv 0 1 0\nv 1 1 0\nf 1/1/1 2//2 3/3 4", 1);
  match r {
    Ok(m) => {
      var ok = obj_face_count(&m) == 1;
      if !face4_is(&m, 0, 0, 1, 2, 3) { ok = false; }
      return assert(ok, "mixed index forms on one polygon resolve alike");
    },
    Err(_) => { return assert(false, "mixed index forms on one polygon resolve alike"); },
  }
  return assert(false, "unreachable");
}

fn t23() -> TestResult {
  let r = obj_parse("v 007.50 +.5 -.5\nv 5. 1. 2.", 1000);
  match r {
    Ok(m) => {
      var ok = obj_vertex_count(&m) == 2;
      if !vertex_is(&m, 0, 7500, 500, -500) { ok = false; }
      if !vertex_is(&m, 1, 5000, 1000, 2000) { ok = false; }
      return assert(ok, "leading zeros, plus signs and bare fractions");
    },
    Err(_) => { return assert(false, "leading zeros, plus signs and bare fractions"); },
  }
  return assert(false, "unreachable");
}

fn main() -> Int {
  io.println("=== xiom.obj conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.obj: all tests passed");
  } else {
    io.println("xiom.obj: tests failed");
  }
  return failed;
}
