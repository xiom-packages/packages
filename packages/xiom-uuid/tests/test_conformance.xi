// XIOM -- xiom.uuid conformance tests (18 checks)
// Port task: prove the pure-XIOM xiom.uuid module against its documented
// grammar and bit rules.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Coverage map: see SPEC.md section 5. Every check is a named
// assert(cond, "name") call and main returns the failure count (0 = green).
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every comparison
// below is routed through streq instead of `==`. Expected byte vectors are
// built with the stdlib xiom.encoding.hex decoder (independent of the module
// under test).

module uuid_tests
use xiom.io; use xiom.test; use xiom.uuid;
use xiom.string; use xiom.string.compare;
use xiom.encoding.hex;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// Expected bytes for a hex string ("" on malformed input; the test then
// fails on the byte comparison).
fn hb(hexstr: Str) -> Vec[UInt8] {
  let r = hex.hex_decode(hexstr);
  match r {
    Ok(v) => { return v; },
    Err(_) => {},
  }
  return Vec[UInt8].new();
}

fn bytes_equal(a: Vec[UInt8], b: Vec[UInt8]) -> Bool {
  if a.len() != b.len() {
    return false;
  }
  var i = 0;
  while i < a.len() {
    if (((a[i] as Int) & 0xFF) != ((b[i] as Int) & 0xFF)) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// True when r is Ok and its bytes equal `want`.
fn bytes_ok_is(r: Result[Vec[UInt8], Str], want: Vec[UInt8]) -> Bool {
  if !r.is_ok {
    return false;
  }
  return bytes_equal(r.value, want);
}

// True when r is an Err whose message starts with "uuid: ".
fn bytes_err(r: Result[Vec[UInt8], Str]) -> Bool {
  if r.is_ok {
    return false;
  }
  let m: Str = r.error;
  if m.len() < 6 {
    return false;
  }
  return streq(string.str_slice(m, 0, 6), "uuid: ");
}

// True when r is Ok(text) with text equal to `want`.
fn str_ok_is(r: Result[Str, Str], want: Str) -> Bool {
  if !r.is_ok {
    return false;
  }
  return streq(r.value, want);
}

// True when r is an Err whose message starts with "uuid: ".
fn str_err(r: Result[Str, Str]) -> Bool {
  if r.is_ok {
    return false;
  }
  let m: Str = r.error;
  if m.len() < 6 {
    return false;
  }
  return streq(string.str_slice(m, 0, 6), "uuid: ");
}

// True when r is Ok(v) with v == want.
fn int_ok_is(r: Result[Int, Str], want: Int) -> Bool {
  if !r.is_ok {
    return false;
  }
  return r.value == want;
}

// True when r is an Err whose message starts with "uuid: ".
fn int_err(r: Result[Int, Str]) -> Bool {
  if r.is_ok {
    return false;
  }
  let m: Str = r.error;
  if m.len() < 6 {
    return false;
  }
  return streq(string.str_slice(m, 0, 6), "uuid: ");
}

// True when r is Ok(v) with v == want.
fn bool_ok_is(r: Result[Bool, Str], want: Bool) -> Bool {
  if !r.is_ok {
    return false;
  }
  return r.value == want;
}

// True when r is an Err whose message starts with "uuid: ".
fn bool_err(r: Result[Bool, Str]) -> Bool {
  if r.is_ok {
    return false;
  }
  let m: Str = r.error;
  if m.len() < 6 {
    return false;
  }
  return streq(string.str_slice(m, 0, 6), "uuid: ");
}

// Deterministic 16-byte sequence 0x00..0x0F.
fn bytes16() -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < 16 {
    v.push(i as UInt8);
    i = i + 1;
  }
  return v;
}

// Deterministic 16-byte sequence with high bytes: 0x80..0x8F.
fn high16() -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < 16 {
    v.push((128 + i) as UInt8);
    i = i + 1;
  }
  return v;
}

// Deterministic byte sequence of length n (covers 0 and bytes >= 0x80).
fn seq(n: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < n {
    v.push(((i * 37 + 7) % 256) as UInt8);
    i = i + 1;
  }
  return v;
}

// Independent v4 bit-rule transform: byte 6 high nibble = 4, byte 8 top two
// bits = 10. Mirrors the RFC 4122 layout specified in SPEC.md section 4.
fn v4_expect(src: Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < src.len() {
    var v = 0;
    v = (src[i] as Int) & 0xFF;
    if i == 6 {
      v = (v & 0x0F) | 0x40;
    }
    if i == 8 {
      v = (v & 0x3F) | 0x80;
    }
    out.push(v as UInt8);
    i = i + 1;
  }
  return out;
}

fn t1() -> TestResult {
  let allf = hb("ffffffffffffffffffffffffffffffff");
  let known = hb("550e8400e29b41d4a716446655440000");
  var ok = str_ok_is(uuid_format(&bytes16()), "00010203-0405-0607-0809-0a0b0c0d0e0f");
  if !str_ok_is(uuid_format(&allf), "ffffffff-ffff-ffff-ffff-ffffffffffff") { ok = false; }
  if !str_ok_is(uuid_format(&known), "550e8400-e29b-41d4-a716-446655440000") { ok = false; }
  return assert(ok, "format: known bytes to canonical lowercase");
}

fn t2() -> TestResult {
  let empty = Vec[UInt8].new();
  var ok = str_err(uuid_format(&empty));
  if !str_err(uuid_format(&seq(15))) { ok = false; }
  if !str_err(uuid_format(&seq(17))) { ok = false; }
  return assert(ok, "format: lengths 0, 15 and 17 are Err");
}

fn t3() -> TestResult {
  let known = hb("550e8400e29b41d4a716446655440000");
  let high = high16();
  let seqd = seq(16);
  var ok = bytes_ok_is(uuid_parse("00010203-0405-0607-0809-0a0b0c0d0e0f"), bytes16());
  if !bytes_ok_is(uuid_parse("550e8400-e29b-41d4-a716-446655440000"), known) { ok = false; }
  let fh = uuid_format(&high);
  if !fh.is_ok { ok = false; }
  if fh.is_ok {
    if !bytes_ok_is(uuid_parse(fh.value), high) { ok = false; }
  }
  let fs = uuid_format(&seqd);
  if !fs.is_ok { ok = false; }
  if fs.is_ok {
    if !bytes_ok_is(uuid_parse(fs.value), seqd) { ok = false; }
  }
  return assert(ok, "parse/format: round-trip for low and high byte vectors");
}

fn t4() -> TestResult {
  let want = hb("550e8400e29b41d4a716446655440000");
  var ok = bytes_ok_is(uuid_parse("550E8400-E29B-41D4-A716-446655440000"), want);
  if !bytes_ok_is(uuid_parse("550e8400-E29B-41d4-a716-446655440000"), want) { ok = false; }
  return assert(ok, "parse: hex case-insensitive");
}

fn t5() -> TestResult {
  var ok = bytes_err(uuid_parse("550e8400e29b41d4a716446655440000"));
  if !bytes_err(uuid_parse("550e8400-e29b-41d4-a716-44665544000")) { ok = false; }
  if !bytes_err(uuid_parse("550e8400-e29b-41d4-a716446655440000")) { ok = false; }
  if !bytes_err(uuid_parse("550e8400+e29b-41d4-a716-446655440000")) { ok = false; }
  if !bytes_err(uuid_parse("550e8400-e29b-41d4-a716-44665544-000")) { ok = false; }
  return assert(ok, "parse: bad hyphen placement is Err");
}

fn t6() -> TestResult {
  var ok = bytes_err(uuid_parse("g50e8400-e29b-41d4-a716-446655440000"));
  if !bytes_err(uuid_parse("550e8400-e29b-41d4-a716-44665544000g")) { ok = false; }
  if !bytes_err(uuid_parse("550e8400-e29b-41d4-a716-44665544zzzz")) { ok = false; }
  if !bytes_err(uuid_parse("550e8400-e29b-41d4-a716-4466554400 0")) { ok = false; }
  if !bytes_err(uuid_parse("550_8400-e29b-41d4-a716-446655440000")) { ok = false; }
  return assert(ok, "parse: non-hex bytes are Err");
}

fn t7() -> TestResult {
  var ok = bytes_err(uuid_parse("{550e8400-e29b-41d4-a716-446655440000}"));
  if !bytes_err(uuid_parse("urn:uuid:550e8400-e29b-41d4-a716-446655440000")) { ok = false; }
  if !bytes_err(uuid_parse("550e8400-e29b-41d4-a716-446655440000 ")) { ok = false; }
  return assert(ok, "parse: braces, urn form and trailing space are Err");
}

fn t8() -> TestResult {
  var ok = bytes_err(uuid_parse(""));
  if !bytes_err(uuid_parse("550e8400-e29b-41d4-a716-44665544000")) { ok = false; }
  if !bytes_err(uuid_parse("550e8400-e29b-41d4-a716-4466554400000")) { ok = false; }
  return assert(ok, "parse: wrong lengths are Err");
}

fn t9() -> TestResult {
  var ok = uuid_is_valid("550e8400-e29b-41d4-a716-446655440000");
  if !uuid_is_valid("550E8400-E29B-41D4-A716-446655440000") { ok = false; }
  if !uuid_is_valid("00000000-0000-0000-0000-000000000000") { ok = false; }
  if !uuid_is_valid("ffffffff-ffff-ffff-ffff-ffffffffffff") { ok = false; }
  if !uuid_is_valid("00010203-0405-4607-8809-0a0b0c0d0e0f") { ok = false; }
  return assert(ok, "is_valid: canonical forms are true");
}

fn t10() -> TestResult {
  var ok = !uuid_is_valid("");
  if uuid_is_valid("550e8400e29b41d4a716446655440000") { ok = false; }
  if uuid_is_valid("{550e8400-e29b-41d4-a716-446655440000}") { ok = false; }
  if uuid_is_valid("550e8400-e29b-41d4-a716-44665544zzzz") { ok = false; }
  if uuid_is_valid("550e8400-e29b-41d4-a716-44665544000") { ok = false; }
  if uuid_is_valid("550e8400-e29b-41d4-a716-4466554400+0") { ok = false; }
  return assert(ok, "is_valid: malformed forms are false");
}

fn t11() -> TestResult {
  let v4 = uuid_v4_from(&bytes16());
  var ok = v4.is_ok;
  if v4.is_ok {
    if !streq(v4.value, "00010203-0405-4607-8809-0a0b0c0d0e0f") { ok = false; }
  }
  let parsed = uuid_parse("00010203-0405-4607-8809-0a0b0c0d0e0f");
  if parsed.is_ok {
    let pb: Vec[UInt8] = parsed.value;
    let b6: Int = (pb[6] as Int) & 0xFF;
    let b8: Int = (pb[8] as Int) & 0xFF;
    if (b6 >> 4) != 4 { ok = false; }
    if (b8 & 0xC0) != 0x80 { ok = false; }
  } else {
    ok = false;
  }
  return assert(ok, "v4_from: version nibble 4 and variant bits 10");
}

fn t12() -> TestResult {
  let empty = Vec[UInt8].new();
  var ok = str_err(uuid_v4_from(&empty));
  if !str_err(uuid_v4_from(&seq(15))) { ok = false; }
  if !str_err(uuid_v4_from(&seq(17))) { ok = false; }
  return assert(ok, "v4_from: lengths 0, 15 and 17 are Err");
}

fn t13() -> TestResult {
  let v4 = uuid_v4_from(&seq(16));
  var ok = v4.is_ok;
  if v4.is_ok {
    let text: Str = v4.value;
    if !uuid_is_valid(text) { ok = false; }
    if !int_ok_is(uuid_version(text), 4) { ok = false; }
    if !bool_ok_is(uuid_variant_ok(text), true) { ok = false; }
    if !bytes_ok_is(uuid_parse(text), v4_expect(seq(16))) { ok = false; }
  }
  return assert(ok, "v4_from: output parses back as version 4, RFC variant");
}

fn t14() -> TestResult {
  var ok = int_ok_is(uuid_version("550e8400-e29b-41d4-a716-446655440000"), 4);
  if !int_ok_is(uuid_version("00000000-0000-0000-0000-000000000000"), 0) { ok = false; }
  if !int_ok_is(uuid_version("ffffffff-ffff-ffff-ffff-ffffffffffff"), 15) { ok = false; }
  if !int_ok_is(uuid_version("00010203-0405-1607-8809-0a0b0c0d0e0f"), 1) { ok = false; }
  if !int_err(uuid_version("not-a-uuid")) { ok = false; }
  if !int_err(uuid_version("550e8400-e29b-41d4-a716-44665544zzzz")) { ok = false; }
  return assert(ok, "version: nibble of valid UUIDs, Err otherwise");
}

fn t15() -> TestResult {
  var ok = bool_ok_is(uuid_variant_ok("550e8400-e29b-41d4-a716-446655440000"), true);
  if !bool_ok_is(uuid_variant_ok("00010203-0405-4607-8809-0a0b0c0d0e0f"), true) { ok = false; }
  if !bool_ok_is(uuid_variant_ok("00010203-0405-4607-b809-0a0b0c0d0e0f"), true) { ok = false; }
  return assert(ok, "variant: RFC 4122 10xx variant is true");
}

fn t16() -> TestResult {
  var ok = bool_ok_is(uuid_variant_ok("00010203-0405-4607-0809-0a0b0c0d0e0f"), false);
  if !bool_ok_is(uuid_variant_ok("00000000-0000-0000-0000-000000000000"), false) { ok = false; }
  if !bool_ok_is(uuid_variant_ok("550e8400-e29b-41d4-c716-446655440000"), false) { ok = false; }
  if !bool_ok_is(uuid_variant_ok("550e8400-e29b-41d4-f716-446655440000"), false) { ok = false; }
  return assert(ok, "variant: non-RFC top bits are false");
}

fn t17() -> TestResult {
  var ok = bool_err(uuid_variant_ok("550e8400-e29b-41d4-a716-44665544000"));
  if !bool_err(uuid_variant_ok("")) { ok = false; }
  if !int_err(uuid_version("g50e8400-e29b-41d4-a716-446655440000")) { ok = false; }
  if !int_err(uuid_version("")) { ok = false; }
  return assert(ok, "version/variant: malformed input is Err");
}

fn t18() -> TestResult {
  let a = uuid_v4_from(&seq(16));
  let b = uuid_v4_from(&seq(16));
  var ok = a.is_ok;
  if !b.is_ok { ok = false; }
  if a.is_ok && b.is_ok {
    if !streq(a.value, b.value) { ok = false; }
  }
  let x = seq(16);
  let fa = uuid_format(&x);
  let fb = uuid_format(&x);
  if !fa.is_ok { ok = false; }
  if !fb.is_ok { ok = false; }
  if fa.is_ok && fb.is_ok {
    if !streq(fa.value, fb.value) { ok = false; }
  }
  let pa = uuid_parse("550e8400-e29b-41d4-a716-446655440000");
  let pb = uuid_parse("550e8400-e29b-41d4-a716-446655440000");
  if !pa.is_ok { ok = false; }
  if !pb.is_ok { ok = false; }
  if pa.is_ok && pb.is_ok {
    if !bytes_equal(pa.value, pb.value) { ok = false; }
  }
  return assert(ok, "deterministic: same input gives the same output");
}

fn main() -> Int {
  io.println("=== xiom.uuid conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.uuid: all tests passed");
  } else {
    io.println("xiom.uuid: tests failed");
  }
  return failed;
}
