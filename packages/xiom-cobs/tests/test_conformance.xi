// XIOM -- xiom.cobs conformance tests (20 checks)
// Port task: prove the pure-XIOM xiom.cobs COBS codec against the standard
// encoding rules, the 254-byte boundary, zero-byte handling and the
// documented error catalog.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Error texts are compared with str_compare (BUG 17 discipline: `==` on Str
// values read from a Vec lowers to a pointer comparison). Every Vec[UInt8]
// read is widened with `as Int` before use. No function pointers, no
// Vec[StructType], no inline lambdas.

module cobs_tests
use xiom.io; use xiom.test;
use xiom.cobs;
use xiom.string.compare;

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn bytes_equal(a: Vec[UInt8], b: Vec[UInt8]) -> Bool {
  if a.len() != b.len() {
    return false;
  }
  var i = 0;
  while i < a.len() {
    if (a[i] as Int) != (b[i] as Int) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn vec_of(b: Int, n: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < n {
    v.push(b as UInt8);
    i = i + 1;
  }
  return v;
}

fn bytes1(a: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(a as UInt8);
  return v;
}

fn bytes2(a: Int, b: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(a as UInt8);
  v.push(b as UInt8);
  return v;
}

fn bytes3(a: Int, b: Int, c: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(a as UInt8);
  v.push(b as UInt8);
  v.push(c as UInt8);
  return v;
}

fn bytes4(a: Int, b: Int, c: Int, d: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(a as UInt8);
  v.push(b as UInt8);
  v.push(c as UInt8);
  v.push(d as UInt8);
  return v;
}

fn bytes5(a: Int, b: Int, c: Int, d: Int, e: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(a as UInt8);
  v.push(b as UInt8);
  v.push(c as UInt8);
  v.push(d as UInt8);
  v.push(e as UInt8);
  return v;
}

fn err_is(r: Result[Vec[UInt8], Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

// Deterministic payload patterns for the round-trip sweeps.
fn pattern_seq(n: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < n {
    v.push((i % 256) as UInt8);
    i = i + 1;
  }
  return v;
}

// Zeros every 7th byte, non-zero (1..255) elsewhere.
fn pattern_mixed(n: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < n {
    if i % 7 == 0 {
      v.push(0 as UInt8);
    } else {
      v.push(((i * 13 + 7) % 255 + 1) as UInt8);
    }
    i = i + 1;
  }
  return v;
}

fn has_zero(v: Vec[UInt8]) -> Bool {
  var i = 0;
  while i < v.len() {
    if (v[i] as Int) == 0 {
      return true;
    }
    i = i + 1;
  }
  return false;
}

// encode -> (no 0x00) -> exact size -> decode -> byte-identical payload.
fn roundtrip_ok(src: Vec[UInt8]) -> Bool {
  let e = cobs_encode(&src);
  if !cobs_is_encoded(&e) {
    return false;
  }
  if has_zero(e) {
    return false;
  }
  if cobs_encoded_size(&src) != e.len() {
    return false;
  }
  let d = cobs_decode(&e);
  if !d.is_ok {
    return false;
  }
  if !bytes_equal(d.value, src) {
    return false;
  }
  return true;
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  var empty = Vec[UInt8].new();
  let e = cobs_encode(&empty);
  var ok = e.len() == 1;
  if e.len() == 1 {
    if (e[0] as Int) != 1 { ok = false; }
  }
  let d = cobs_decode(&e);
  if !d.is_ok { ok = false; } elif !bytes_equal(d.value, empty) { ok = false; }
  return assert(ok, "empty input encodes to the single code byte 0x01 and decodes back to empty");
}

fn t2() -> TestResult {
  let e = cobs_encode(&bytes1(0x2A));
  var ok = e.len() == 2;
  if e.len() == 2 {
    if (e[0] as Int) != 2 { ok = false; }
    if (e[1] as Int) != 0x2A { ok = false; }
  }
  if !cobs_is_encoded(&e) { ok = false; }
  if cobs_encoded_size(&bytes1(0x2A)) != e.len() { ok = false; }
  return assert(ok, "single non-zero byte b encodes to [0x02, b]");
}

fn t3() -> TestResult {
  let src = bytes2(0x11, 0x22);
  let e = cobs_encode(&src);
  var ok = bytes_equal(e, bytes3(3, 0x11, 0x22));
  if cobs_encoded_size(&src) != e.len() { ok = false; }
  let d = cobs_decode(&e);
  if !d.is_ok { ok = false; } elif !bytes_equal(d.value, src) { ok = false; }
  return assert(ok, "two non-zero bytes b1 b2 encode to [0x03, b1, b2]");
}

fn t4() -> TestResult {
  let src = bytes3(0x11, 0x00, 0x22);
  let e = cobs_encode(&src);
  var ok = bytes_equal(e, bytes4(2, 0x11, 2, 0x22));
  let d = cobs_decode(&e);
  if !d.is_ok { ok = false; } elif !bytes_equal(d.value, src) { ok = false; }
  return assert(ok, "a 0x00 in the middle splits the codes ([02 11 02 22])");
}

fn t5() -> TestResult {
  let src = bytes2(0x00, 0x05);
  let e = cobs_encode(&src);
  var ok = bytes_equal(e, bytes3(1, 2, 0x05));
  let d = cobs_decode(&e);
  if !d.is_ok { ok = false; } elif !bytes_equal(d.value, src) { ok = false; }
  return assert(ok, "input starting with 0x00 encodes with a leading code 0x01");
}

fn t6() -> TestResult {
  let src = bytes2(0x05, 0x00);
  let e = cobs_encode(&src);
  var ok = bytes_equal(e, bytes3(2, 0x05, 1));
  let d = cobs_decode(&e);
  if !d.is_ok { ok = false; } elif !bytes_equal(d.value, src) { ok = false; }
  return assert(ok, "input ending with 0x00 gets a trailing code 0x01");
}

fn t7() -> TestResult {
  let src = vec_of(0xAB, 254);
  let e = cobs_encode(&src);
  var ok = e.len() == 255;
  if e.len() == 255 {
    if (e[0] as Int) != 255 { ok = false; }
    if (e[1] as Int) != 0xAB { ok = false; }
    if (e[254] as Int) != 0xAB { ok = false; }
  }
  if !cobs_is_encoded(&e) { ok = false; }
  if cobs_encoded_size(&src) != 255 { ok = false; }
  let d = cobs_decode(&e);
  if !d.is_ok { ok = false; } elif !bytes_equal(d.value, src) { ok = false; }
  return assert(ok, "254 non-zero bytes encode as [0xFF] + 254 bytes (255 bytes total)");
}

fn t8() -> TestResult {
  let src = vec_of(0xAB, 255);
  let e = cobs_encode(&src);
  var ok = e.len() == 257;
  if e.len() == 257 {
    if (e[0] as Int) != 255 { ok = false; }
    if (e[254] as Int) != 0xAB { ok = false; }
    if (e[255] as Int) != 2 { ok = false; }
    if (e[256] as Int) != 0xAB { ok = false; }
  }
  if !cobs_is_encoded(&e) { ok = false; }
  if cobs_encoded_size(&src) != 257 { ok = false; }
  let d = cobs_decode(&e);
  if !d.is_ok { ok = false; } elif !bytes_equal(d.value, src) { ok = false; }
  return assert(ok, "255 non-zero bytes need an extra code byte ([FF][254][02][last])");
}

fn t9() -> TestResult {
  let src = vec_of(0, 3);
  let e = cobs_encode(&src);
  var ok = bytes_equal(e, bytes4(1, 1, 1, 1));
  let d = cobs_decode(&e);
  if !d.is_ok { ok = false; } elif !bytes_equal(d.value, src) { ok = false; }
  return assert(ok, "all-zero input 00 00 00 encodes to [01 01 01 01]");
}

fn t10() -> TestResult {
  let e1 = cobs_encode(&bytes4(0x11, 0x22, 0x00, 0x33));
  var ok = bytes_equal(e1, bytes5(3, 0x11, 0x22, 2, 0x33));
  let e2 = cobs_encode(&bytes4(0x11, 0x00, 0x00, 0x00));
  if !bytes_equal(e2, bytes5(2, 0x11, 1, 1, 1)) { ok = false; }
  return assert(ok, "standard COBS vectors [03 11 22 02 33] and [02 11 01 01 01]");
}

fn t11() -> TestResult {
  var ok = true;
  var n = 0;
  while n <= 300 {
    let src = pattern_seq(n);
    if !roundtrip_ok(src) { ok = false; }
    n = n + 1;
  }
  return assert(ok, "round-trips hold for every length 0..300 (i % 256 pattern)");
}

fn t12() -> TestResult {
  var ok = true;
  var n = 0;
  while n <= 300 {
    let src = pattern_mixed(n);
    if !roundtrip_ok(src) { ok = false; }
    n = n + 1;
  }
  return assert(ok, "round-trips hold for every length 0..300 (zero every 7th byte)");
}

fn t13() -> TestResult {
  var ok = true;
  var empty = Vec[UInt8].new();
  let e0 = cobs_encode(&empty);
  if has_zero(e0) { ok = false; }
  let e1 = cobs_encode(&vec_of(0, 5));
  if has_zero(e1) { ok = false; }
  let e2 = cobs_encode(&vec_of(0xFF, 254));
  if has_zero(e2) { ok = false; }
  let e3 = cobs_encode(&vec_of(0x80, 255));
  if has_zero(e3) { ok = false; }
  let e4 = cobs_encode(&pattern_mixed(300));
  if has_zero(e4) { ok = false; }
  if !cobs_is_encoded(&e4) { ok = false; }
  return assert(ok, "encoded frames never contain a 0x00 byte");
}

fn t14() -> TestResult {
  var ok = err_is(cobs_decode(&bytes1(0)), "cobs: zero byte in frame");
  if !err_is(cobs_decode(&bytes2(1, 0)), "cobs: zero byte in frame") { ok = false; }
  if !err_is(cobs_decode(&bytes3(2, 0, 3)), "cobs: zero byte in frame") { ok = false; }
  if !err_is(cobs_decode(&bytes3(1, 0, 0)), "cobs: zero byte in frame") { ok = false; }
  return assert(ok, "any 0x00 byte in the frame is Err(cobs: zero byte in frame)");
}

fn t15() -> TestResult {
  var ok = err_is(cobs_decode(&bytes1(2)), "cobs: truncated frame");
  if !err_is(cobs_decode(&bytes2(3, 1)), "cobs: truncated frame") { ok = false; }
  if !err_is(cobs_decode(&bytes2(3, 255)), "cobs: truncated frame") { ok = false; }
  if !err_is(cobs_decode(&bytes4(255, 1, 2, 3)), "cobs: truncated frame") { ok = false; }
  let good = cobs_decode(&bytes3(3, 1, 2));
  if !good.is_ok { ok = false; } elif !bytes_equal(good.value, bytes2(1, 2)) { ok = false; }
  return assert(ok, "a code byte beyond the remaining bytes is Err(cobs: truncated frame)");
}

fn t16() -> TestResult {
  var empty = Vec[UInt8].new();
  var ok = cobs_encoded_size(&empty) == 1;
  if cobs_encoded_size(&bytes1(5)) != 2 { ok = false; }
  if cobs_encoded_size(&bytes3(0, 0, 0)) != 4 { ok = false; }
  if cobs_encoded_size(&vec_of(0x01, 254)) != 255 { ok = false; }
  if cobs_encoded_size(&vec_of(0x01, 255)) != 257 { ok = false; }
  var full_then_zero = vec_of(0x01, 254);
  full_then_zero.push(0 as UInt8);
  if cobs_encoded_size(&full_then_zero) != 257 { ok = false; }
  if cobs_encoded_size(&full_then_zero) != cobs_encode(&full_then_zero).len() { ok = false; }
  if cobs_encoded_size(&pattern_mixed(300)) != cobs_encode(&pattern_mixed(300)).len() { ok = false; }
  return assert(ok, "encoded_size is the exact encoded length at the boundaries");
}

fn t17() -> TestResult {
  var empty = Vec[UInt8].new();
  var ok = cobs_is_encoded(&empty);
  if !cobs_is_encoded(&bytes1(1)) { ok = false; }
  if !cobs_is_encoded(&bytes3(255, 7, 9)) { ok = false; }
  if cobs_is_encoded(&bytes1(0)) { ok = false; }
  if cobs_is_encoded(&bytes2(1, 0)) { ok = false; }
  if cobs_is_encoded(&bytes3(1, 2, 0)) { ok = false; }
  let framed = cobs_encode(&pattern_mixed(300));
  if !cobs_is_encoded(&framed) { ok = false; }
  return assert(ok, "is_encoded is exactly 'contains no 0x00 byte'");
}

fn t18() -> TestResult {
  var ok = cobs_max_payload_for(0) == 0;
  if cobs_max_payload_for(1) != 0 { ok = false; }
  if cobs_max_payload_for(2) != 1 { ok = false; }
  if cobs_max_payload_for(3) != 2 { ok = false; }
  if cobs_max_payload_for(253) != 252 { ok = false; }
  if cobs_max_payload_for(254) != 253 { ok = false; }
  if cobs_max_payload_for(255) != 254 { ok = false; }
  if cobs_max_payload_for(256) != 254 { ok = false; }
  if cobs_max_payload_for(257) != 255 { ok = false; }
  if cobs_max_payload_for(510) != 508 { ok = false; }
  if cobs_max_payload_for(512) != 509 { ok = false; }
  if cobs_max_payload_for(-5) != 0 { ok = false; }
  return assert(ok, "max_payload_for returns the documented boundary values");
}

fn t19() -> TestResult {
  var ok = true;
  var f = 2;
  while f <= 600 {
    let m = cobs_max_payload_for(f);
    if m < 0 { ok = false; }
    let fits = vec_of(0x01, m);
    if cobs_encoded_size(&fits) > f { ok = false; }
    let bigger = vec_of(0x01, m + 1);
    if cobs_encoded_size(&bigger) <= f { ok = false; }
    f = f + 1;
  }
  return assert(ok, "max_payload_for is the largest worst-case payload that fits");
}

fn t20() -> TestResult {
  var padded = Vec[UInt8].new();
  padded.push(255 as UInt8);
  var i = 0;
  while i < 254 {
    padded.push(0xCD as UInt8);
    i = i + 1;
  }
  padded.push(1 as UInt8);
  var ok = cobs_is_encoded(&padded);
  let d = cobs_decode(&padded);
  if !d.is_ok { ok = false; } elif !bytes_equal(d.value, vec_of(0xCD, 254)) { ok = false; }
  let minimal = cobs_encode(&vec_of(0xCD, 254));
  if minimal.len() != 255 { ok = false; }
  if !cobs_is_encoded(&minimal) { ok = false; }
  return assert(ok, "decoder accepts the padded [FF][254 bytes][01] form of a full run");
}

fn main() -> Int {
  io.println("=== xiom.cobs conformance tests ===");
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
    io.println("xiom.cobs: all tests passed");
  } else {
    io.println("xiom.cobs: tests failed");
  }
  return failed;
}
