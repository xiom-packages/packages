// XIOM -- xiom.fnv conformance tests (19 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// The "", "a", "fo", "foo", "foob", "fooba" and "foobar" vectors for all
// four functions are pinned from the official FNV reference test-vector
// tables (https://github.com/lcn2/fnv, test_fnv.c: fnv1_32_vector,
// fnv1a_32_vector, fnv1_64_vector, fnv1a_64_vector, entries 0-11).
//
// The four zero-hash vectors are the shortest published solutions to the
// FNV zero-hash challenges on the official FNV page:
//   FNV-1  32-bit of 01 47 6c 10 f3              = 0
//   FNV-1a 32-bit of cc 24 31 c4                 = 0
//   FNV-1  64-bit of 92 06 77 4c e0 2f 89 2a d2  = 0
//   FNV-1a 64-bit of d5 6b b9 53 42 87 08 36     = 0
//
// The "123456789", high-byte, 300-byte pattern and 1000 x 0xFF vectors,
// and every signed decimal below, were computed with independent
// BigInteger implementations (Python and .NET) of the published
// algorithm and cross-checked against the official reference tables.
//
// Str comparisons in this suite only ever compare fnv_hex*() results with
// string literals (the xiom.hello pattern); no Str is ever read out of a
// Vec, so BUG 17 is unreachable. Test dispatch is direct tN() calls, not
// a Vec[fn] table.

module fnv_tests
use xiom.io; use xiom.test;
use xiom.fnv;
use xiom.string;

fn bytes_of(s: Str) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < s.len() {
    v.push(string.byte_at(s, i));
    i = i + 1;
  }
  return v;
}

// Bytes [from, to) of `d`, as a fresh vector (the incremental API must be
// fed its own buffers; see the &struct.field trap in the porter notes).
fn chunk(d: &Vec[UInt8], from: Int, to: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = from;
  while i < to {
    v.push(d[i]);
    i = i + 1;
  }
  return v;
}

// 300 bytes, byte k = k % 256 (the xiom.crc/xiom.packet fixture).
fn pattern_300() -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < 300 {
    v.push((i % 256) as UInt8);
    i = i + 1;
  }
  return v;
}

// ff 00 80 7f 01: exercises byte widening for values with bit 7 set.
fn high_bytes() -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(255);
  v.push(0);
  v.push(128);
  v.push(127);
  v.push(1);
  return v;
}

// `n` copies of byte `b`.
fn repeat_byte(b: Int, n: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < n {
    v.push(b as UInt8);
    i = i + 1;
  }
  return v;
}

// Shortest published FNV-1 32-bit zero-hash solution (01 47 6c 10 f3).
fn zero32_1() -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(1);
  v.push(71);
  v.push(108);
  v.push(16);
  v.push(243);
  return v;
}

// Shortest published FNV-1a 32-bit zero-hash solution (cc 24 31 c4).
fn zero32_1a() -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(204);
  v.push(36);
  v.push(49);
  v.push(196);
  return v;
}

// Published FNV-1 64-bit zero-hash solution
// (92 06 77 4c e0 2f 89 2a d2).
fn zero64_1() -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(146);
  v.push(6);
  v.push(119);
  v.push(76);
  v.push(224);
  v.push(47);
  v.push(137);
  v.push(42);
  v.push(210);
  return v;
}

// The only published length-8 FNV-1a 64-bit zero-hash solution
// (d5 6b b9 53 42 87 08 36).
fn zero64_1a() -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(213);
  v.push(107);
  v.push(185);
  v.push(83);
  v.push(66);
  v.push(135);
  v.push(8);
  v.push(54);
  return v;
}

fn t1() -> TestResult {
  var ok = fnv_offset_basis32() == 2166136261;
  if fnv_prime32() != 16777619 { ok = false; }
  if fnv_offset_basis64() != (0 - 3750763034362895579) { ok = false; }
  if fnv_prime64() != 1099511628211 { ok = false; }
  if fnv1_32_init() != fnv_offset_basis32() { ok = false; }
  if fnv1a_32_init() != fnv_offset_basis32() { ok = false; }
  if fnv1_64_init() != fnv_offset_basis64() { ok = false; }
  if fnv1a_64_init() != fnv_offset_basis64() { ok = false; }
  return assert(ok, "offset bases, primes and init states match the FNV specification");
}

fn t2() -> TestResult {
  var e = Vec[UInt8].new();
  let a = bytes_of("a");
  let fo = bytes_of("fo");
  let foo = bytes_of("foo");
  let foob = bytes_of("foob");
  let fooba = bytes_of("fooba");
  let foobar = bytes_of("foobar");
  var ok = fnv1_32(&e) == 2166136261;
  if fnv1_32(&a) != 84696446 { ok = false; }
  if fnv1_32(&fo) != 1802970388 { ok = false; }
  if fnv1_32(&foo) != 1083137555 { ok = false; }
  if fnv1_32(&foob) != 3031504779 { ok = false; }
  if fnv1_32(&fooba) != 4257746864 { ok = false; }
  if fnv1_32(&foobar) != 837857890 { ok = false; }
  return assert(ok, "FNV-1 32-bit official vectors for empty, a, fo, foo, foob, fooba, foobar");
}

fn t3() -> TestResult {
  var e = Vec[UInt8].new();
  let a = bytes_of("a");
  let fo = bytes_of("fo");
  let foo = bytes_of("foo");
  let foob = bytes_of("foob");
  let fooba = bytes_of("fooba");
  let foobar = bytes_of("foobar");
  var ok = fnv1a_32(&e) == 2166136261;
  if fnv1a_32(&a) != 3826002220 { ok = false; }
  if fnv1a_32(&fo) != 1646454850 { ok = false; }
  if fnv1a_32(&foo) != 2851307223 { ok = false; }
  if fnv1a_32(&foob) != 1062237935 { ok = false; }
  if fnv1a_32(&fooba) != 967483786 { ok = false; }
  if fnv1a_32(&foobar) != 3214735720 { ok = false; }
  return assert(ok, "FNV-1a 32-bit official vectors for empty, a, fo, foo, foob, fooba, foobar");
}

fn t4() -> TestResult {
  var e = Vec[UInt8].new();
  let a = bytes_of("a");
  let fo = bytes_of("fo");
  let foo = bytes_of("foo");
  let foob = bytes_of("foob");
  let fooba = bytes_of("fooba");
  let foobar = bytes_of("foobar");
  var ok = fnv1_64(&e) == (0 - 3750763034362895579);
  if fnv1_64(&a) != (0 - 5808590958014384194) { ok = false; }
  if fnv1_64(&fo) != 590642286378561332 { ok = false; }
  if fnv1_64(&foo) != (0 - 2824945433545984717) { ok = false; }
  if fnv1_64(&foob) != 250092161292133835 { ok = false; }
  if fnv1_64(&fooba) != (0 - 3230816393391507568) { ok = false; }
  if fnv1_64(&foobar) != 3750802935296928194 { ok = false; }
  return assert(ok, "FNV-1 64-bit official vectors for empty, a, fo, foo, foob, fooba, foobar");
}

fn t5() -> TestResult {
  var e = Vec[UInt8].new();
  let a = bytes_of("a");
  let fo = bytes_of("fo");
  let foo = bytes_of("foo");
  let foob = bytes_of("foob");
  let fooba = bytes_of("fooba");
  let foobar = bytes_of("foobar");
  var ok = fnv1a_64(&e) == (0 - 3750763034362895579);
  if fnv1a_64(&a) != (0 - 5808556873153909620) { ok = false; }
  if fnv1a_64(&fo) != 619342838404076354 { ok = false; }
  if fnv1a_64(&foo) != (0 - 2543842089295555209) { ok = false; }
  if fnv1a_64(&foob) != (0 - 2516933328689098065) { ok = false; }
  if fnv1a_64(&fooba) != (0 - 3836673602514652150) { ok = false; }
  if fnv1a_64(&foobar) != (0 - 8821353812377114648) { ok = false; }
  return assert(ok, "FNV-1a 64-bit official vectors for empty, a, fo, foo, foob, fooba, foobar");
}

fn t6() -> TestResult {
  let d = bytes_of("123456789");
  var ok = fnv1_32(&d) == 605325334;
  if fnv1a_32(&d) != 3146166556 { ok = false; }
  if fnv1_64(&d) != (0 - 6399619235874007338) { ok = false; }
  if fnv1a_64(&d) != 492395637191921148 { ok = false; }
  return assert(ok, "123456789 pinned for all four functions (605325334 / 3146166556 / -6399619235874007338 / 492395637191921148)");
}

fn t7() -> TestResult {
  let d = high_bytes();
  var ok = fnv1_32(&d) == 3241118348;
  if fnv1a_32(&d) != 2980932822 { ok = false; }
  if fnv1_64(&d) != (0 - 8473324096044310740) { ok = false; }
  if fnv1a_64(&d) != (0 - 8608316359277527594) { ok = false; }
  return assert(ok, "high-bit bytes ff 00 80 7f 01 pinned for all four functions");
}

fn t8() -> TestResult {
  let p = pattern_300();
  var ok = fnv1_32(&p) == 2806697729;
  if fnv1a_32(&p) != 850699257 { ok = false; }
  if fnv1_64(&p) != 3701077766089453601 { ok = false; }
  if fnv1a_64(&p) != 5505869966771167897 { ok = false; }
  return assert(ok, "300-byte pattern (byte k = k % 256) pinned for all four functions");
}

fn t9() -> TestResult {
  let d = repeat_byte(255, 1000);
  var ok = fnv1_32(&d) == 1924235885;
  if fnv1a_32(&d) != 3662916093 { ok = false; }
  if fnv1_64(&d) != (0 - 5185522427156778419) { ok = false; }
  if fnv1a_64(&d) != (0 - 1875925227212054051) { ok = false; }
  return assert(ok, "1000 x 0xFF (deep wrap for both widths) pinned for all four functions");
}

fn t10() -> TestResult {
  let a = zero32_1();
  let b = zero32_1a();
  let c = zero64_1();
  let d = zero64_1a();
  var ok = fnv1_32(&a) == 0;
  if fnv1a_32(&b) != 0 { ok = false; }
  if fnv1_64(&c) != 0 { ok = false; }
  if fnv1a_64(&d) != 0 { ok = false; }
  if fnv1_32(&b) == 0 { ok = false; }
  if fnv1a_32(&a) == 0 { ok = false; }
  if fnv1_64(&d) == 0 { ok = false; }
  if fnv1a_64(&c) == 0 { ok = false; }
  return assert(ok, "official zero-hash challenge solutions for all four functions hash to 0");
}

fn t11() -> TestResult {
  let d = bytes_of("The quick brown fox jumps over the lazy dog");
  var ok = fnv1_32(&d) == 3922226286;
  if fnv1a_32(&d) != 76545936 { ok = false; }
  if fnv1_64(&d) != (0 - 6290698473031107890) { ok = false; }
  if fnv1a_64(&d) != (0 - 866459186506731248) { ok = false; }
  return assert(ok, "longer ASCII sentence pinned for all four functions");
}

fn t12() -> TestResult {
  let d = bytes_of("foobar");
  var ok = true;
  var s = 0;
  while s <= 6 {
    let head = chunk(&d, 0, s);
    let tail = chunk(&d, s, 6);
    var h: Int = fnv1a_32_init();
    h = fnv1a_32_update(h, &head);
    h = fnv1a_32_update(h, &tail);
    if h != 3214735720 { ok = false; }
    s = s + 1;
  }
  return assert(ok, "fnv1a_32 incremental at every split point of \"foobar\" equals one-shot 0xBF9CF968");
}

fn t13() -> TestResult {
  let d = bytes_of("foobar");
  var ok = true;
  var s = 0;
  while s <= 6 {
    let head = chunk(&d, 0, s);
    let tail = chunk(&d, s, 6);
    var h: Int = fnv1_64_init();
    h = fnv1_64_update(h, &head);
    h = fnv1_64_update(h, &tail);
    if h != 3750802935296928194 { ok = false; }
    s = s + 1;
  }
  return assert(ok, "fnv1_64 incremental at every split point of \"foobar\" equals one-shot 0x340D8765A4DDA9C2");
}

fn t14() -> TestResult {
  let d = bytes_of("foobar");
  var h1: Int = fnv1_32_init();
  var h1a: Int = fnv1a_32_init();
  var h2: Int = fnv1_64_init();
  var h2a: Int = fnv1a_64_init();
  var i = 0;
  while i < 6 {
    let one = chunk(&d, i, i + 1);
    h1 = fnv1_32_update(h1, &one);
    h1a = fnv1a_32_update(h1a, &one);
    h2 = fnv1_64_update(h2, &one);
    h2a = fnv1a_64_update(h2a, &one);
    i = i + 1;
  }
  var ok = h1 == fnv1_32(&d);
  if h1a != fnv1a_32(&d) { ok = false; }
  if h2 != fnv1_64(&d) { ok = false; }
  if h2a != fnv1a_64(&d) { ok = false; }
  if h1 != 837857890 { ok = false; }
  if h1a != 3214735720 { ok = false; }
  if h2 != 3750802935296928194 { ok = false; }
  if h2a != (0 - 8821353812377114648) { ok = false; }
  return assert(ok, "byte-at-a-time incremental equals one-shot for all four variants");
}

fn t15() -> TestResult {
  var e = Vec[UInt8].new();
  var ok = fnv1_32_update(fnv1_32_init(), &e) == fnv1_32_init();
  if fnv1a_32_update(fnv1a_32_init(), &e) != fnv1a_32_init() { ok = false; }
  if fnv1_64_update(fnv1_64_init(), &e) != fnv1_64_init() { ok = false; }
  if fnv1a_64_update(fnv1a_64_init(), &e) != fnv1a_64_init() { ok = false; }
  if fnv1_32(&e) != fnv1_32_init() { ok = false; }
  if fnv1a_32(&e) != fnv1a_32_init() { ok = false; }
  if fnv1_64(&e) != fnv1_64_init() { ok = false; }
  if fnv1a_64(&e) != fnv1a_64_init() { ok = false; }
  if fnv1_32_finalize(123456789) != 123456789 { ok = false; }
  if fnv1a_64_finalize(fnv1a_64_init()) != fnv1a_64_init() { ok = false; }
  return assert(ok, "empty update is identity, finalize is identity, init equals one-shot of empty");
}

fn t16() -> TestResult {
  let d = bytes_of("foobar");
  var ok = fnv_hex32(0) == "00000000";
  if fnv_hex32(2166136261) != "811c9dc5" { ok = false; }
  if fnv_hex32(fnv1_32(&d)) != "31f0b262" { ok = false; }
  if fnv_hex32(fnv1a_32(&d)) != "bf9cf968" { ok = false; }
  if fnv_hex32(4294967295) != "ffffffff" { ok = false; }
  if fnv_hex32(0 - 1) != "ffffffff" { ok = false; }
  if fnv_hex32(4294967301) != "00000005" { ok = false; }
  return assert(ok, "fnv_hex32 renders the low 32 bits as 8 unsigned hex digits");
}

fn t17() -> TestResult {
  let d = bytes_of("foobar");
  var ok = fnv_hex64(0) == "0000000000000000";
  if fnv_hex64(fnv_offset_basis64()) != "cbf29ce484222325" { ok = false; }
  if fnv_hex64(0 - 1) != "ffffffffffffffff" { ok = false; }
  if fnv_hex64(fnv1_64(&d)) != "340d8765a4dda9c2" { ok = false; }
  if fnv_hex64(fnv1a_64(&d)) != "85944171f73967e8" { ok = false; }
  if fnv_hex64(fnv1a_64_init()) != "cbf29ce484222325" { ok = false; }
  return assert(ok, "fnv_hex64 renders the 64-bit pattern as 16 unsigned hex digits");
}

fn t18() -> TestResult {
  let d = bytes_of("foobar");
  let e = bytes_of("foobar");
  var ok = fnv1_32(&d) == fnv1_32(&d);
  if fnv1a_32(&d) != fnv1a_32(&e) { ok = false; }
  if fnv1_64(&d) != fnv1_64(&e) { ok = false; }
  if fnv1a_64(&d) != fnv1a_64(&e) { ok = false; }
  let p = pattern_300();
  if fnv1_32(&p) != fnv1_32(&p) { ok = false; }
  if fnv1a_64(&p) != fnv1a_64(&p) { ok = false; }
  return assert(ok, "hashing is deterministic across repeated calls and equal buffers");
}

fn t19() -> TestResult {
  let d = bytes_of("foobar");
  var ok = fnv1_32(&d) != fnv1a_32(&d);
  if fnv1_64(&d) == fnv1a_64(&d) { ok = false; }
  var e = Vec[UInt8].new();
  if fnv1_32(&e) != fnv1a_32(&e) { ok = false; }
  if fnv1_64(&e) != fnv1a_64(&e) { ok = false; }
  let p = pattern_300();
  if fnv1a_32(&p) == fnv1a_32(&d) { ok = false; }
  if fnv1a_64(&p) == fnv1a_64(&d) { ok = false; }
  return assert(ok, "FNV-1 and FNV-1a agree on empty input, differ on non-empty input");
}

fn main() -> Int {
  io.println("=== xiom.fnv conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.fnv: all tests passed");
  } else {
    io.println("xiom.fnv: tests failed");
  }
  return failed;
}
