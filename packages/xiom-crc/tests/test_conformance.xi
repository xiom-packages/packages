// XIOM -- xiom.crc conformance tests (20 checks)
// Port task: prove the pure-XIOM xiom.crc engine against the CRC catalogue
// known-answer vectors, the parameter-model reflection/masking rules and
// pinned local sums. Every expected number below was cross-checked against an
// independent implementation of the same published model; the standard
// catalogue check values all match (CRC-32 0xCBF43926, CRC-32C 0xE3069283,
// CCITT-FALSE 0x29B1, ARC 0xBB3D, CRC-8 0xF4, KERMIT 0x2189, XMODEM 0x31C3,
// MODBUS 0x4B37, RIELLO 0x63D0, GENIBUS 0xD64E, MAXIM 0xA1, ROHC 0xD0,
// JAMCRC 0x340BC6D9, BZIP2 0xFC891918, MPEG-2 0x0376E6E7, POSIX 0x765E7680).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// All checks compare Int values, so BUG 17 (`==` on Str read from a Vec) is
// never reachable here and no Str comparison helper is needed.

module crc_tests
use xiom.io; use xiom.test;
use xiom.crc;
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

// 300 bytes, byte k = k % 256. The same buffer the xiom.packet suite pins
// (its CRC-32 of 985464046 is an independent zlib cross-check for t20).
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

// Test-local 16-bit reversal, independent of the module under test, used to
// state the refout rule as a property.
fn reflect16(v: Int) -> Int {
  var out = 0;
  var x = v;
  var i = 0;
  while i < 16 {
    out = out * 2 + (x & 1);
    x = x >> 1;
    i = i + 1;
  }
  return out;
}

fn t1() -> TestResult {
  let d = bytes_of("123456789");
  return assert(crc32_ieee(&d) == 3421780262, "CRC-32/IEEE check value is 0xCBF43926 (3421780262)");
}

fn t2() -> TestResult {
  let d = bytes_of("123456789");
  return assert(crc32c(&d) == 3808858755, "CRC-32C check value is 0xE3069283 (3808858755)");
}

fn t3() -> TestResult {
  let d = bytes_of("123456789");
  return assert(crc16_ccitt_false(&d) == 10673, "CRC-16/CCITT-FALSE check value is 0x29B1 (10673)");
}

fn t4() -> TestResult {
  let d = bytes_of("123456789");
  return assert(crc16_arc(&d) == 47933, "CRC-16/ARC check value is 0xBB3D (47933)");
}

fn t5() -> TestResult {
  let d = bytes_of("123456789");
  return assert(crc8(&d) == 244, "CRC-8 check value is 0xF4 (244)");
}

fn t6() -> TestResult {
  var e = Vec[UInt8].new();
  var ok = crc32_ieee(&e) == 0;
  if crc32c(&e) != 0 { ok = false; }
  if crc16_ccitt_false(&e) != 65535 { ok = false; }
  if crc16_arc(&e) != 0 { ok = false; }
  if crc8(&e) != 0 { ok = false; }
  return assert(ok, "empty input yields init^xorout per preset (0/0/65535/0/0)");
}

fn t7() -> TestResult {
  let d = bytes_of("a");
  var ok = crc32_ieee(&d) == 3904355907;
  if crc32c(&d) != 3251651376 { ok = false; }
  if crc16_ccitt_false(&d) != 40311 { ok = false; }
  if crc16_arc(&d) != 59585 { ok = false; }
  if crc8(&d) != 32 { ok = false; }
  return assert(ok, "single byte \"a\" pinned per preset");
}

fn t8() -> TestResult {
  let d = high_bytes();
  var ok = crc32_ieee(&d) == 852721342;
  if crc32c(&d) != 3296080556 { ok = false; }
  if crc16_ccitt_false(&d) != 30911 { ok = false; }
  if crc16_arc(&d) != 3316 { ok = false; }
  if crc8(&d) != 84 { ok = false; }
  return assert(ok, "high-bit bytes ff 00 80 7f 01 pinned per preset");
}

fn t9() -> TestResult {
  let d = bytes_of("abc");
  var ok = crc_compute(&d, 7, 7, 0, false, false, 0) == 0;
  if crc_compute(&d, 64, 7, 0, false, false, 0) != 0 { ok = false; }
  if crc_compute(&d, 0, 7, 0, false, false, 0) != 0 { ok = false; }
  if crc_compute(&d, 24, 7, 0, false, false, 0) != 0 { ok = false; }
  if crc_compute(&d, 8, 7, 0, false, false, 0) == 0 { ok = false; }
  if crc_compute(&d, 16, 4129, 65535, false, false, 0) == 0 { ok = false; }
  if crc_compute(&d, 32, 79764919, 4294967295, true, true, 4294967295) == 0 { ok = false; }
  return assert(ok, "width 7/64/0/24 return 0; widths 8/16/32 compute");
}

fn t10() -> TestResult {
  let d = bytes_of("123456789");
  var ok = crc_compute(&d, 32, 79764919, 4294967295, true, true, 4294967295) == crc32_ieee(&d);
  if crc_compute(&d, 32, 517762881, 4294967295, true, true, 4294967295) != crc32c(&d) { ok = false; }
  if crc_compute(&d, 16, 4129, 65535, false, false, 0) != crc16_ccitt_false(&d) { ok = false; }
  if crc_compute(&d, 16, 32773, 0, true, true, 0) != crc16_arc(&d) { ok = false; }
  if crc_compute(&d, 8, 7, 0, false, false, 0) != crc8(&d) { ok = false; }
  var e = Vec[UInt8].new();
  if crc_compute(&e, 32, 79764919, 4294967295, true, true, 4294967295) != 0 { ok = false; }
  if crc_compute(&e, 16, 4129, 65535, false, false, 0) != 65535 { ok = false; }
  return assert(ok, "crc_compute with preset parameters equals every preset wrapper");
}

fn t11() -> TestResult {
  let d = bytes_of("123456789");
  var ok = crc_compute(&d, 16, 4129, 0, true, true, 0) == 8585;
  if crc_compute(&d, 16, 4129, 0, false, false, 0) != 12739 { ok = false; }
  return assert(ok, "CRC-16/KERMIT 0x2189 and XMODEM 0x31C3 catalogue vectors");
}

fn t12() -> TestResult {
  let d = bytes_of("123456789");
  var ok = crc_compute(&d, 16, 32773, 65535, true, true, 0) == 19255;
  if crc_compute(&d, 16, 4129, 45738, true, true, 0) != 25552 { ok = false; }
  return assert(ok, "CRC-16/MODBUS 0x4B37 and RIELLO 0x63D0 (reflected init) vectors");
}

fn t13() -> TestResult {
  let d = bytes_of("123456789");
  var ok = crc_compute(&d, 16, 4129, 65535, false, false, 65535) == 54862;
  if crc_compute(&d, 8, 49, 0, true, true, 0) != 161 { ok = false; }
  if crc_compute(&d, 8, 7, 255, true, true, 0) != 208 { ok = false; }
  if crc_compute(&d, 8, 7, 0, false, false, 85) != 161 { ok = false; }
  return assert(ok, "CRC-16/GENIBUS, CRC-8/MAXIM-DOW, ROHC and ITU catalogue vectors");
}

fn t14() -> TestResult {
  let d = bytes_of("123456789");
  var ok = crc_compute(&d, 32, 79764919, 4294967295, true, true, 0) == 873187033;
  if crc_compute(&d, 32, 79764919, 4294967295, false, false, 4294967295) != 4236843288 { ok = false; }
  if crc_compute(&d, 32, 79764919, 4294967295, false, false, 0) != 58124007 { ok = false; }
  if crc_compute(&d, 32, 79764919, 0, false, false, 4294967295) != 1985902208 { ok = false; }
  return assert(ok, "CRC-32/JAMCRC, BZIP2, MPEG-2 and POSIX catalogue vectors");
}

fn t15() -> TestResult {
  let d = bytes_of("123456789");
  let plain = crc_compute(&d, 16, 4129, 65535, false, false, 0);
  let reflected = crc_compute(&d, 16, 4129, 65535, true, true, 0);
  var ok = reflect16(plain) == crc_compute(&d, 16, 4129, 65535, false, true, 0);
  if plain != 10673 { ok = false; }
  if reflect16(reflected) != crc_compute(&d, 16, 4129, 65535, true, false, 0) { ok = false; }
  return assert(ok, "refout differs from refin: the final register is reflected");
}

fn t16() -> TestResult {
  let d = bytes_of("abc");
  let base = crc8(&d);
  var ok = crc_compute(&d, 8, 7, 0, false, false, 85) == base ^ 85;
  let p = pattern_300();
  let zero = crc_compute(&p, 32, 79764919, 4294967295, true, true, 0);
  if crc_compute(&p, 32, 79764919, 4294967295, true, true, 252645135) != (zero ^ 252645135) { ok = false; }
  if zero != (crc32_ieee(&p) ^ 4294967295) { ok = false; }
  return assert(ok, "xorout is applied as a final XOR (8-bit and 32-bit)");
}

fn t17() -> TestResult {
  let d = bytes_of("123456789");
  var ok = crc_compute(&d, 16, 65536 + 4129, 65536 + 65535, false, false, 65536) == 10673;
  if crc_compute(&d, 8, 256 + 7, 0, false, false, 256) != 244 { ok = false; }
  if crc_compute(&d, 16, 4129, 65536 + 45738, true, true, 0) != 25552 { ok = false; }
  return assert(ok, "poly/init/xorout masked to the width (oversized inputs reduce)");
}

fn t18() -> TestResult {
  let d = bytes_of("123456789");
  var ok = crc_matches(&d, 32, 79764919, 4294967295, true, true, 4294967295, 3421780262);
  if crc_matches(&d, 32, 79764919, 4294967295, true, true, 4294967295, 3421780263) { ok = false; }
  var e = Vec[UInt8].new();
  if !crc_matches(&e, 16, 4129, 65535, false, false, 0, 65535) { ok = false; }
  if crc_matches(&e, 16, 4129, 65535, false, false, 0, 0) { ok = false; }
  let one = bytes_of("a");
  if !crc_matches(&one, 8, 7, 0, false, false, 0, 32) { ok = false; }
  if crc_matches(&one, 8, 7, 0, false, false, 0, 33) { ok = false; }
  return assert(ok, "crc_matches is true on the check value and false otherwise");
}

fn t19() -> TestResult {
  let p = pattern_300();
  let a = crc32_ieee(&p);
  let b = crc32_ieee(&p);
  var ok = a == b;
  let q = pattern_300();
  if crc32c(&q) != crc32c(&p) { ok = false; }
  var other = Vec[UInt8].new();
  var i = 0;
  while i < 300 {
    other.push(((i + 1) % 256) as UInt8);
    i = i + 1;
  }
  if crc32_ieee(&other) == a { ok = false; }
  return assert(ok, "CRC is deterministic and separates different inputs");
}

fn t20() -> TestResult {
  let p = pattern_300();
  var ok = crc32_ieee(&p) == 985464046;
  if crc32c(&p) != 1108128698 { ok = false; }
  if crc16_ccitt_false(&p) != 43353 { ok = false; }
  if crc16_arc(&p) != 50424 { ok = false; }
  if crc8(&p) != 102 { ok = false; }
  return assert(ok, "300-byte pattern (i % 256) pinned per preset");
}

fn main() -> Int {
  io.println("=== xiom.crc conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.crc: all tests passed");
  } else {
    io.println("xiom.crc: tests failed");
  }
  return failed;
}
