// XIOM -- xiom.stl conformance tests (17 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Fixtures are built in-test from byte pushes with pinned IEEE-754 bit
// patterns (1.0f = 0x3F800000, 2.0f = 0x40000000, ...). The two-triangle
// fixture additionally pins NaN (0x7FC00000), +inf (0x7F800000), -inf
// (0xFF800000), -0.0 (0x80000000), a denormal (0x00000001) and values of
// 1.2f/0.3f, proving the accessors expose raw bits (bit 31 included)
// without any float conversion.
//
// Str error messages are compared with str_compare (BUG 17 discipline:
// `==` on Str is unreliable, and no Str crosses a Vec[Str] here).

module stl_tests
use xiom.io; use xiom.test;
use xiom.string.compare;
use xiom.string.builder;
use xiom.stl;

// --------------------------------------------------
//  Result helpers
// --------------------------------------------------

// Value of an Ok result, or -1. No accessor can legitimately return a
// negative value: bit patterns, counts and attributes are unsigned.
fn ok_int(r: Result[Int, Str]) -> Int {
  match r {
    Ok(v) => { return v; },
    Err(_) => {},
  }
  return -1;
}

// True when the result is any Err.
fn bad_int(r: Result[Int, Str]) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(_) => { return true; },
  }
  return true;
}

// True when the result is Err with the exact message `want`.
fn err_is(r: Result[Int, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return compare.str_compare(r.error, want) == 0;
}

// --------------------------------------------------
//  Fixture builders
// --------------------------------------------------

fn push_zeros(out: &mut Vec[UInt8], n: Int) {
  var i = 0;
  while i < n {
    out.push(0 as UInt8);
    i = i + 1;
  }
}

fn push_u16(out: &mut Vec[UInt8], v: Int) {
  out.push((v % 256) as UInt8);
  out.push(((v / 256) % 256) as UInt8);
}

fn push_u32(out: &mut Vec[UInt8], v: Int) {
  out.push((v % 256) as UInt8);
  out.push(((v / 256) % 256) as UInt8);
  out.push(((v / 65536) % 256) as UInt8);
  out.push(((v / 16777216) % 256) as UInt8);
}

fn ascii_bytes(s: Str) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  builder.sb_push_str(&mut out, s);
  return out;
}

// 84-byte binary STL with zero triangles.
fn mk_zero() -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  push_zeros(&mut out, 80);
  push_u32(&mut out, 0);
  return out;
}

// 134-byte, one-triangle binary STL:
//   normal   (1.0, 0.5, 0.0) -> 0x3F800000 0x3F000000 0x00000000
//   vertex 0 (1.0, 2.0, 3.0) -> 0x3F800000 0x40000000 0x40400000
//   vertex 1 (4.0, 5.0, 6.0) -> 0x40800000 0x40A00000 0x40C00000
//   vertex 2 (7.0, 8.0, 9.0) -> 0x40E00000 0x41000000 0x41100000
//   attribute 0x1234
fn mk_one() -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  push_zeros(&mut out, 80);
  push_u32(&mut out, 1);
  push_u32(&mut out, 0x3F800000);
  push_u32(&mut out, 0x3F000000);
  push_u32(&mut out, 0x00000000);
  push_u32(&mut out, 0x3F800000);
  push_u32(&mut out, 0x40000000);
  push_u32(&mut out, 0x40400000);
  push_u32(&mut out, 0x40800000);
  push_u32(&mut out, 0x40A00000);
  push_u32(&mut out, 0x40C00000);
  push_u32(&mut out, 0x40E00000);
  push_u32(&mut out, 0x41000000);
  push_u32(&mut out, 0x41100000);
  push_u16(&mut out, 0x1234);
  return out;
}

// 184-byte, two-triangle binary STL. Triangle 0 is a unit corner with
// attribute 1; triangle 1 pins the special bit patterns:
//   normal   (-1.0, NaN, -0.0) -> 0xBF800000 0x7FC00000 0x80000000
//   vertex 0 (+inf, -inf, min normal) -> 0x7F800000 0xFF800000 0x00800000
//   vertex 1 (denormal, 0.3f, 1.2f) -> 0x00000001 0x3E99999A 0x3F99999A
//   vertex 2 (10.0, 100.0, 0.5) -> 0x41200000 0x42C80000 0x3F000000
//   attribute 0xFFFF
fn mk_two() -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  push_zeros(&mut out, 80);
  push_u32(&mut out, 2);
  push_u32(&mut out, 0x00000000);
  push_u32(&mut out, 0x00000000);
  push_u32(&mut out, 0x00000000);
  push_u32(&mut out, 0x3F800000);
  push_u32(&mut out, 0x00000000);
  push_u32(&mut out, 0x00000000);
  push_u32(&mut out, 0x00000000);
  push_u32(&mut out, 0x3F800000);
  push_u32(&mut out, 0x00000000);
  push_u32(&mut out, 0x00000000);
  push_u32(&mut out, 0x00000000);
  push_u32(&mut out, 0x3F800000);
  push_u16(&mut out, 1);
  push_u32(&mut out, 0xBF800000);
  push_u32(&mut out, 0x7FC00000);
  push_u32(&mut out, 0x80000000);
  push_u32(&mut out, 0x7F800000);
  push_u32(&mut out, 0xFF800000);
  push_u32(&mut out, 0x00800000);
  push_u32(&mut out, 0x00000001);
  push_u32(&mut out, 0x3E99999A);
  push_u32(&mut out, 0x3F99999A);
  push_u32(&mut out, 0x41200000);
  push_u32(&mut out, 0x42C80000);
  push_u32(&mut out, 0x3F000000);
  push_u16(&mut out, 0xFFFF);
  return out;
}

// Declares one triangle but carries only 49 of its 50 bytes (133 total).
fn mk_truncated() -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  push_zeros(&mut out, 80);
  push_u32(&mut out, 1);
  push_zeros(&mut out, 49);
  return out;
}

// 83 bytes: one short of the minimum binary header.
fn mk_short() -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  push_zeros(&mut out, 83);
  return out;
}

// 134 bytes that START with "solid" but whose size exactly matches the
// binary formula: stl_kind must report 1 (binary wins on a size match).
fn mk_solid_sized() -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  builder.sb_push_str(&mut out, "solid binary impostor");
  push_zeros(&mut out, 59);
  push_u32(&mut out, 1);
  push_zeros(&mut out, 50);
  return out;
}

// 100-byte ASCII file: "solid" + 95 spaces. Offset 80..83 are ASCII spaces,
// so the declared count is absurd and stl_triangle_count reports truncation.
fn mk_solid_long() -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  builder.sb_push_str(&mut out, "solid");
  var i = 0;
  while i < 95 {
    out.push(32 as UInt8);
    i = i + 1;
  }
  return out;
}

// Leading ASCII whitespace (space, CR, LF, TAB) before "solid".
fn mk_solid_ws() -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  out.push(32 as UInt8);
  out.push(13 as UInt8);
  out.push(10 as UInt8);
  out.push(9 as UInt8);
  builder.sb_push_str(&mut out, "solid x");
  return out;
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  let one = mk_one();
  let zero = mk_zero();
  var ok = stl_kind(one) == 1;
  if ok_int(stl_triangle_count(one)) != 1 { ok = false; }
  if one.len() != 134 { ok = false; }
  if stl_kind(zero) != 1 { ok = false; }
  if ok_int(stl_triangle_count(zero)) != 0 { ok = false; }
  if zero.len() != 84 { ok = false; }
  return assert(ok, "one- and zero-triangle fixtures are binary with the right counts");
}

fn t2() -> TestResult {
  let one = mk_one();
  var ok = ok_int(stl_float_bits(one, 0)) == 0;
  if ok_int(stl_float_bits(one, 80)) != 1 { ok = false; }
  if ok_int(stl_float_bits(one, 84)) != 0x3F800000 { ok = false; }
  if ok_int(stl_float_bits(one, 88)) != 0x3F000000 { ok = false; }
  if ok_int(stl_float_bits(one, 92)) != 0x00000000 { ok = false; }
  if ok_int(stl_float_bits(one, 128)) != 0x41100000 { ok = false; }
  return assert(ok, "float_bits reads little-endian u32 at absolute offsets");
}

fn t3() -> TestResult {
  let one = mk_one();
  var ok = err_is(stl_float_bits(one, -1), "stl: offset out of range");
  if !err_is(stl_float_bits(one, 131), "stl: offset out of range") { ok = false; }
  if !err_is(stl_float_bits(one, 134), "stl: offset out of range") { ok = false; }
  if ok_int(stl_float_bits(one, 130)) != 0x12344110 { ok = false; }
  return assert(ok, "float_bits rejects negative and over-long offsets but reads the last word");
}

fn t4() -> TestResult {
  let one = mk_one();
  var ok = ok_int(stl_normal_bits(one, 0, 0)) == 0x3F800000;
  if ok_int(stl_normal_bits(one, 0, 1)) != 0x3F000000 { ok = false; }
  if ok_int(stl_normal_bits(one, 0, 2)) != 0x00000000 { ok = false; }
  return assert(ok, "normal bits are pinned per axis");
}

fn t5() -> TestResult {
  let one = mk_one();
  var ok = ok_int(stl_vertex_bits(one, 0, 0, 0)) == 0x3F800000;
  if ok_int(stl_vertex_bits(one, 0, 0, 1)) != 0x40000000 { ok = false; }
  if ok_int(stl_vertex_bits(one, 0, 0, 2)) != 0x40400000 { ok = false; }
  if ok_int(stl_vertex_bits(one, 0, 1, 0)) != 0x40800000 { ok = false; }
  if ok_int(stl_vertex_bits(one, 0, 1, 1)) != 0x40A00000 { ok = false; }
  if ok_int(stl_vertex_bits(one, 0, 1, 2)) != 0x40C00000 { ok = false; }
  if ok_int(stl_vertex_bits(one, 0, 2, 0)) != 0x40E00000 { ok = false; }
  if ok_int(stl_vertex_bits(one, 0, 2, 1)) != 0x41000000 { ok = false; }
  if ok_int(stl_vertex_bits(one, 0, 2, 2)) != 0x41100000 { ok = false; }
  return assert(ok, "all nine vertex components are pinned");
}

fn t6() -> TestResult {
  let one = mk_one();
  let two = mk_two();
  var ok = ok_int(stl_attribute(one, 0)) == 0x1234;
  if ok_int(stl_attribute(two, 0)) != 1 { ok = false; }
  if ok_int(stl_attribute(two, 1)) != 0xFFFF { ok = false; }
  return assert(ok, "attribute u16 is read little-endian per triangle");
}

fn t7() -> TestResult {
  let two = mk_two();
  var ok = stl_kind(two) == 1;
  if ok_int(stl_triangle_count(two)) != 2 { ok = false; }
  if two.len() != 184 { ok = false; }
  if ok_int(stl_normal_bits(two, 1, 0)) != 0xBF800000 { ok = false; }
  if ok_int(stl_normal_bits(two, 1, 1)) != 0x7FC00000 { ok = false; }
  if ok_int(stl_normal_bits(two, 1, 2)) != 0x80000000 { ok = false; }
  if ok_int(stl_vertex_bits(two, 1, 0, 0)) != 0x7F800000 { ok = false; }
  if ok_int(stl_vertex_bits(two, 1, 0, 1)) != 0xFF800000 { ok = false; }
  if ok_int(stl_vertex_bits(two, 1, 1, 0)) != 0x00000001 { ok = false; }
  if ok_int(stl_vertex_bits(two, 1, 2, 2)) != 0x3F000000 { ok = false; }
  return assert(ok, "two-triangle fixture keeps raw bits for NaN, inf and -0.0");
}

fn t8() -> TestResult {
  let exact = ascii_bytes("solid test");
  let ws = mk_solid_ws();
  let vertex_text = ascii_bytes("vertex 1 2 3");
  var ok = stl_kind(exact) == 2;
  if stl_kind(ws) != 2 { ok = false; }
  if stl_kind(vertex_text) != 0 { ok = false; }
  if !err_is(stl_triangle_count(exact), "stl: truncated header") { ok = false; }
  return assert(ok, "ASCII detection accepts only leading whitespace + solid");
}

fn t9() -> TestResult {
  let long = mk_solid_long();
  var ok = long.len() == 100;
  if stl_kind(long) != 2 { ok = false; }
  if !err_is(stl_triangle_count(long), "stl: truncated triangle data") { ok = false; }
  return assert(ok, "long ASCII solid file is kind 2 and not a triangle buffer");
}

fn t10() -> TestResult {
  let longer = mk_one();
  longer.push(0 as UInt8);
  let bigger = mk_one();
  bigger[80] = 2 as UInt8;
  var ok = stl_kind(longer) == 0;
  if !err_is(stl_triangle_count(longer), "stl: trailing bytes") { ok = false; }
  if stl_kind(bigger) != 0 { ok = false; }
  if !err_is(stl_triangle_count(bigger), "stl: truncated triangle data") { ok = false; }
  return assert(ok, "size mismatches in both directions are kind 0");
}

fn t11() -> TestResult {
  let t = mk_truncated();
  var ok = t.len() == 133;
  if stl_kind(t) != 0 { ok = false; }
  if !err_is(stl_triangle_count(t), "stl: truncated triangle data") { ok = false; }
  return assert(ok, "a declared triangle beyond the buffer is Err");
}

fn t12() -> TestResult {
  let empty = Vec[UInt8].new();
  let short = mk_short();
  let word = ascii_bytes("solid");
  var ok = empty.len() == 0;
  if stl_kind(empty) != 0 { ok = false; }
  if !err_is(stl_triangle_count(empty), "stl: truncated header") { ok = false; }
  if stl_kind(short) != 0 { ok = false; }
  if !err_is(stl_triangle_count(short), "stl: truncated header") { ok = false; }
  if stl_kind(word) != 2 { ok = false; }
  return assert(ok, "empty and sub-84-byte buffers are kind 0; short solid is ASCII");
}

fn t13() -> TestResult {
  let one = mk_one();
  var ok = err_is(stl_normal_bits(one, 1, 0), "stl: triangle out of range");
  if !err_is(stl_vertex_bits(one, 1, 0, 0), "stl: triangle out of range") { ok = false; }
  if !err_is(stl_attribute(one, 1), "stl: triangle out of range") { ok = false; }
  if !err_is(stl_normal_bits(one, -1, 0), "stl: triangle out of range") { ok = false; }
  if !bad_int(stl_attribute(one, -1)) { ok = false; }
  return assert(ok, "triangle index must be in 0..count-1");
}

fn t14() -> TestResult {
  let one = mk_one();
  var ok = err_is(stl_normal_bits(one, 0, 3), "stl: axis out of range");
  if !err_is(stl_normal_bits(one, 0, -1), "stl: axis out of range") { ok = false; }
  if !err_is(stl_vertex_bits(one, 0, 0, 3), "stl: axis out of range") { ok = false; }
  if !err_is(stl_vertex_bits(one, 0, 0, -1), "stl: axis out of range") { ok = false; }
  return assert(ok, "axis must be 0, 1 or 2");
}

fn t15() -> TestResult {
  let one = mk_one();
  var ok = err_is(stl_vertex_bits(one, 0, 3, 0), "stl: vertex out of range");
  if !err_is(stl_vertex_bits(one, 0, -1, 0), "stl: vertex out of range") { ok = false; }
  return assert(ok, "vertex must be 0, 1 or 2");
}

fn t16() -> TestResult {
  var ok = stl_binary_size(0) == 84;
  if stl_binary_size(1) != 134 { ok = false; }
  if stl_binary_size(2) != 184 { ok = false; }
  if stl_binary_size(10) != 584 { ok = false; }
  if stl_binary_size(100) != 5084 { ok = false; }
  if stl_binary_size(-1) != 0 { ok = false; }
  return assert(ok, "binary_size is 84 + 50*n and 0 for negative n");
}

fn t17() -> TestResult {
  let imposter = mk_solid_sized();
  var ok = imposter.len() == 134;
  if stl_kind(imposter) != 1 { ok = false; }
  if ok_int(stl_triangle_count(imposter)) != 1 { ok = false; }
  return assert(ok, "an exact binary size wins over a solid-prefixed header");
}

fn main() -> Int {
  io.println("=== xiom.stl conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.stl: all tests passed");
  } else {
    io.println("xiom.stl: tests failed");
  }
  return failed;
}
