// XIOM -- xiom.varint conformance tests (20 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API: unsigned LEB128 encoding pinning at every
// width boundary (0, 1, 127, 128, 300, 624485, 2^32-1, 2^63-1), zigzag
// pinning (0, -1, 1, -2, 2, INT64_MIN, INT64_MAX), encode/decode
// round-trips including non-zero offsets into a stream, truncation and
// overflow errors, the 10-byte maximum, varint_size_u consistency, the
// canonicality predicate (overlong 0x80 0x00 rejected) and out-of-range
// offsets.
//
// Str values are compared with str_compare (BUG 17 discipline), and every
// Vec read goes through a typed local before it is used.

module varint_tests
use xiom.io; use xiom.test;
use xiom.varint;
use xiom.string.compare;
use xiom.encoding.hex;

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
    if a[i] != b[i] {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn concat2(a: Vec[UInt8], b: Vec[UInt8]) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < a.len() {
    v.push(a[i]);
    i = i + 1;
  }
  var j = 0;
  while j < b.len() {
    v.push(b[j]);
    j = j + 1;
  }
  return v;
}

fn err_pair_is(r: Result[(Int, Int), Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return compare.str_compare(r.error, want) == 0;
}

fn dec_is(data: Vec[UInt8], off: Int, want_val: Int, want_next: Int) -> Bool {
  let r = varint_decode_u(&data, off);
  if !r.is_ok {
    return false;
  }
  let pair = r.value;
  let val: Int = pair.0;
  let next: Int = pair.1;
  return val == want_val && next == want_next;
}

fn zz_is(data: Vec[UInt8], off: Int, want_val: Int, want_next: Int) -> Bool {
  let r = varint_decode_zigzag(&data, off);
  if !r.is_ok {
    return false;
  }
  let pair = r.value;
  let val: Int = pair.0;
  let next: Int = pair.1;
  return val == want_val && next == want_next;
}

fn canon(data: Vec[UInt8], off: Int) -> Bool {
  return varint_is_canonical_u(&data, off);
}

fn roundtrip_u(n: Int) -> Bool {
  let enc = varint_encode_u(n);
  let r = varint_decode_u(&enc, 0);
  if !r.is_ok {
    return false;
  }
  let pair = r.value;
  let val: Int = pair.0;
  let next: Int = pair.1;
  if val != n {
    return false;
  }
  if next != enc.len() {
    return false;
  }
  return varint_size_u(n) == enc.len();
}

fn roundtrip_zz(n: Int) -> Bool {
  let enc = varint_encode_zigzag(n);
  let r = varint_decode_zigzag(&enc, 0);
  if !r.is_ok {
    return false;
  }
  let pair = r.value;
  let val: Int = pair.0;
  let next: Int = pair.1;
  return val == n && next == enc.len();
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  var ok = bytes_equal(varint_encode_u(0), hb("00"));
  if !bytes_equal(varint_encode_u(1), hb("01")) { ok = false; }
  if !bytes_equal(varint_encode_u(127), hb("7f")) { ok = false; }
  if !bytes_equal(varint_encode_u(128), hb("8001")) { ok = false; }
  if !bytes_equal(varint_encode_u(300), hb("ac02")) { ok = false; }
  if !bytes_equal(varint_encode_u(624485), hb("e58e26")) { ok = false; }
  return assert(ok, "encode_u pinned: 0, 1, 127, 128, 300, 624485");
}

fn t2() -> TestResult {
  var ok = bytes_equal(varint_encode_u(4294967295), hb("ffffffff0f"));
  if !bytes_equal(varint_encode_u(9223372036854775807), hb("ffffffffffffffff7f")) { ok = false; }
  return assert(ok, "encode_u pinned: 2^32-1 (5 bytes) and 2^63-1 (9 bytes)");
}

fn t3() -> TestResult {
  let i64min = 0 - 9223372036854775807 - 1;
  var ok = varint_encode_u(-1).len() == 0;
  if varint_encode_u(i64min).len() != 0 { ok = false; }
  if varint_size_u(-1) != 0 { ok = false; }
  if varint_size_u(i64min) != 0 { ok = false; }
  return assert(ok, "negative values encode to an empty vector and size 0");
}

fn t4() -> TestResult {
  var table = Vec[Int].new();
  table.push(0);
  table.push(1);
  table.push(127);
  table.push(128);
  table.push(300);
  table.push(624485);
  table.push(4294967295);
  table.push(9223372036854775807);
  var ok = varint_size_u(0) == 1;
  if varint_size_u(127) != 1 { ok = false; }
  if varint_size_u(128) != 2 { ok = false; }
  if varint_size_u(300) != 2 { ok = false; }
  if varint_size_u(624485) != 3 { ok = false; }
  if varint_size_u(4294967295) != 5 { ok = false; }
  if varint_size_u(9223372036854775807) != 9 { ok = false; }
  var i = 0;
  while i < table.len() {
    let v: Int = table[i];
    if varint_size_u(v) != varint_encode_u(v).len() { ok = false; }
    i = i + 1;
  }
  return assert(ok, "varint_size_u matches the encoded length across the boundary table");
}

fn t5() -> TestResult {
  var ok = dec_is(hb("00"), 0, 0, 1);
  if !dec_is(hb("01"), 0, 1, 1) { ok = false; }
  if !dec_is(hb("2a"), 0, 42, 1) { ok = false; }
  if !dec_is(hb("7f"), 0, 127, 1) { ok = false; }
  if !dec_is(hb("8001"), 0, 128, 2) { ok = false; }
  if !dec_is(hb("8101"), 0, 129, 2) { ok = false; }
  if !dec_is(hb("ac02"), 0, 300, 2) { ok = false; }
  return assert(ok, "decode_u pinned single/two-byte: 0, 1, 42, 127, 128, 129, 300");
}

fn t6() -> TestResult {
  var ok = dec_is(hb("e58e26"), 0, 624485, 3);
  if !dec_is(hb("ffffffff0f"), 0, 4294967295, 5) { ok = false; }
  if !dec_is(hb("ffffffffffffffff7f"), 0, 9223372036854775807, 9) { ok = false; }
  return assert(ok, "decode_u pinned multi-byte: 624485, 2^32-1, 2^63-1");
}

fn t7() -> TestResult {
  let stream = hb("aa8001e58e2600");
  var ok = dec_is(stream, 1, 128, 3);
  if !dec_is(stream, 3, 624485, 6) { ok = false; }
  if !dec_is(stream, 6, 0, 7) { ok = false; }
  return assert(ok, "decode_u honours non-zero offsets and reports the next offset");
}

fn t8() -> TestResult {
  let empty = Vec[UInt8].new();
  let cont = hb("80");
  let cont9 = hb("808080808080808080");
  var ok = err_pair_is(varint_decode_u(&empty, 0), "varint: truncated");
  if !err_pair_is(varint_decode_u(&cont, 0), "varint: truncated") { ok = false; }
  if !err_pair_is(varint_decode_u(&cont9, 0), "varint: truncated") { ok = false; }
  if !err_pair_is(varint_decode_u(&cont9, -1), "varint: negative offset") { ok = false; }
  return assert(ok, "empty and truncated buffers are Err(varint: truncated)");
}

fn t9() -> TestResult {
  let ten_cont = hb("ffffffffffffffffffff");
  let eleven = hb("8080808080808080808001");
  let top2 = hb("80808080808080808002");
  let top7f = hb("ffffffffffffffffff7f");
  var ok = err_pair_is(varint_decode_u(&ten_cont, 0), "varint: overflow");
  if !err_pair_is(varint_decode_u(&eleven, 0), "varint: overflow") { ok = false; }
  if !err_pair_is(varint_decode_u(&top2, 0), "varint: overflow") { ok = false; }
  if !err_pair_is(varint_decode_u(&top7f, 0), "varint: overflow") { ok = false; }
  return assert(ok, "11-byte and >63-bit encodings are Err(varint: overflow)");
}

fn t10() -> TestResult {
  let maxbit = hb("ffffffffffffffffff01");
  let two63 = hb("80808080808080808001");
  let overlong = hb("80808080808080808000");
  var ok = dec_is(maxbit, 0, -1, 10);
  if !dec_is(two63, 0, 0 - 9223372036854775807 - 1, 10) { ok = false; }
  if !dec_is(overlong, 0, 0, 10) { ok = false; }
  return assert(ok, "10-byte encodings decode (2^64-1 -> -1, 2^63 -> INT64_MIN)");
}

fn t11() -> TestResult {
  var ok = roundtrip_u(0);
  if !roundtrip_u(1) { ok = false; }
  if !roundtrip_u(127) { ok = false; }
  if !roundtrip_u(128) { ok = false; }
  if !roundtrip_u(300) { ok = false; }
  if !roundtrip_u(624485) { ok = false; }
  if !roundtrip_u(65535) { ok = false; }
  if !roundtrip_u(65536) { ok = false; }
  if !roundtrip_u(4294967295) { ok = false; }
  if !roundtrip_u(9223372036854775806) { ok = false; }
  if !roundtrip_u(9223372036854775807) { ok = false; }
  let first = varint_encode_u(300);
  let second = varint_encode_u(624485);
  let stream = concat2(concat2(first, second), varint_encode_u(0));
  if !dec_is(stream, 2, 624485, 5) { ok = false; }
  if !dec_is(stream, 5, 0, 6) { ok = false; }
  return assert(ok, "encode/decode round-trips incl. a non-zero offset in a stream");
}

fn t12() -> TestResult {
  var ok = bytes_equal(varint_encode_zigzag(0), hb("00"));
  if !bytes_equal(varint_encode_zigzag(-1), hb("01")) { ok = false; }
  if !bytes_equal(varint_encode_zigzag(1), hb("02")) { ok = false; }
  if !bytes_equal(varint_encode_zigzag(-2), hb("03")) { ok = false; }
  if !bytes_equal(varint_encode_zigzag(2), hb("04")) { ok = false; }
  return assert(ok, "zigzag pinned: 0 -> 00, -1 -> 01, 1 -> 02, -2 -> 03, 2 -> 04");
}

fn t13() -> TestResult {
  let i64max = 9223372036854775807;
  let i64min = 0 - i64max - 1;
  var ok = bytes_equal(varint_encode_zigzag(i64min), hb("ffffffffffffffffff01"));
  if !bytes_equal(varint_encode_zigzag(i64max), hb("feffffffffffffffff01")) { ok = false; }
  if !bytes_equal(varint_encode_zigzag(0 - i64max), hb("fdffffffffffffffff01")) { ok = false; }
  return assert(ok, "zigzag extremes: INT64_MIN, INT64_MAX, -(2^63-1)");
}

fn t14() -> TestResult {
  var ok = zz_is(hb("01"), 0, -1, 1);
  if !zz_is(hb("02"), 0, 1, 1) { ok = false; }
  if !zz_is(hb("03"), 0, -2, 1) { ok = false; }
  if !zz_is(hb("04"), 0, 2, 1) { ok = false; }
  if !zz_is(hb("ac02"), 0, 150, 2) { ok = false; }
  if !zz_is(hb("e58e26"), 0, -312243, 3) { ok = false; }
  if !zz_is(hb("ffffffffffffffffff01"), 0, 0 - 9223372036854775807 - 1, 10) { ok = false; }
  if !zz_is(hb("feffffffffffffffff01"), 0, 9223372036854775807, 10) { ok = false; }
  return assert(ok, "decode_zigzag pinned incl. 10-byte INT64_MIN/INT64_MAX");
}

fn t15() -> TestResult {
  var ok = roundtrip_zz(0);
  if !roundtrip_zz(-1) { ok = false; }
  if !roundtrip_zz(1) { ok = false; }
  if !roundtrip_zz(-2) { ok = false; }
  if !roundtrip_zz(2) { ok = false; }
  if !roundtrip_zz(63) { ok = false; }
  if !roundtrip_zz(64) { ok = false; }
  if !roundtrip_zz(-64) { ok = false; }
  if !roundtrip_zz(-65) { ok = false; }
  if !roundtrip_zz(127) { ok = false; }
  if !roundtrip_zz(-128) { ok = false; }
  if !roundtrip_zz(300) { ok = false; }
  if !roundtrip_zz(-300) { ok = false; }
  if !roundtrip_zz(4294967295) { ok = false; }
  if !roundtrip_zz(0 - 4294967295) { ok = false; }
  if !roundtrip_zz(9223372036854775807) { ok = false; }
  if !roundtrip_zz(0 - 9223372036854775807 - 1) { ok = false; }
  return assert(ok, "zigzag encode/decode round-trips across the signed range");
}

fn t16() -> TestResult {
  var ok = canon(hb("00"), 0);
  if !canon(hb("7f"), 0) { ok = false; }
  if !canon(hb("8001"), 0) { ok = false; }
  if !canon(hb("ac02"), 0) { ok = false; }
  if !canon(hb("e58e26"), 0) { ok = false; }
  if !canon(hb("ffffffff0f"), 0) { ok = false; }
  if !canon(hb("ffffffffffffffff7f"), 0) { ok = false; }
  if !canon(hb("ffffffffffffffffff01"), 0) { ok = false; }
  return assert(ok, "canonical: minimal single/multi-byte and 10-byte forms");
}

fn t17() -> TestResult {
  var ok = !canon(hb("8000"), 0);
  if canon(hb("8100"), 0) { ok = false; }
  if canon(hb("ac8200"), 0) { ok = false; }
  if canon(hb("80808080808080808000"), 0) { ok = false; }
  if !canon(hb("80808080808080808001"), 0) { ok = false; }
  return assert(ok, "overlong 80 00 is not canonical; the 10-byte 2^63 form is");
}

fn t18() -> TestResult {
  let empty = Vec[UInt8].new();
  let one = hb("01");
  let two = hb("ac02");
  var ok = err_pair_is(varint_decode_u(&one, 1), "varint: truncated");
  if !err_pair_is(varint_decode_u(&one, 5), "varint: truncated") { ok = false; }
  if !err_pair_is(varint_decode_u(&two, 2), "varint: truncated") { ok = false; }
  if !err_pair_is(varint_decode_u(&two, -1), "varint: negative offset") { ok = false; }
  if !err_pair_is(varint_decode_zigzag(&one, 1), "varint: truncated") { ok = false; }
  if !err_pair_is(varint_decode_zigzag(&two, 2), "varint: truncated") { ok = false; }
  if !err_pair_is(varint_decode_zigzag(&two, -1), "varint: negative offset") { ok = false; }
  if !err_pair_is(varint_decode_zigzag(&empty, 0), "varint: truncated") { ok = false; }
  return assert(ok, "empty buffer and out-of-range offsets are Err for both decoders");
}

fn t19() -> TestResult {
  let first = varint_encode_zigzag(-300);
  let second = varint_encode_zigzag(300);
  let stream = concat2(first, second);
  let off = first.len();
  var ok = zz_is(stream, off, 300, stream.len());
  if !canon(stream, off) { ok = false; }
  let su = concat2(varint_encode_u(0), varint_encode_u(128));
  if !canon(su, 1) { ok = false; }
  return assert(ok, "decoders and canonicality honour a non-zero offset");
}

fn t20() -> TestResult {
  var table = Vec[Int].new();
  table.push(0);
  table.push(1);
  table.push(63);
  table.push(64);
  table.push(127);
  table.push(128);
  table.push(255);
  table.push(256);
  table.push(300);
  table.push(16383);
  table.push(16384);
  table.push(624485);
  table.push(4294967295);
  table.push(4294967296);
  table.push(9223372036854775806);
  table.push(9223372036854775807);
  var ok = true;
  var i = 0;
  while i < table.len() {
    let v: Int = table[i];
    let enc = varint_encode_u(v);
    if varint_size_u(v) != enc.len() { ok = false; }
    let r = varint_decode_u(&enc, 0);
    if !r.is_ok {
      ok = false;
    } else {
      let pair = r.value;
      let val: Int = pair.0;
      let next: Int = pair.1;
      if val != v { ok = false; }
      if next != enc.len() { ok = false; }
    }
    i = i + 1;
  }
  return assert(ok, "size/decode consistency across two-group boundaries");
}

fn main() -> Int {
  io.println("=== xiom.varint conformance tests ===");
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
    io.println("xiom.varint: all tests passed");
  } else {
    io.println("xiom.varint: tests failed");
  }
  return failed;
}
