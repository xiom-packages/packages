// XIOM -- xiom.msgpack conformance tests (24 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API: nil/bool/int/str/array-header/map-header
// encodings at every format boundary, reader round-trips, cursor position
// tracking, truncation errors and wrong-type errors.
//
// Read-only reader accessors are routed through tiny `&mut` helpers: XIOM
// v0.61.3 emits advisory E001 when a `&local` call is followed by a
// `&mut local` call in the same function. Str payloads are compared with
// str_compare (BUG 17 discipline: `==` on Str values read from a Vec lowers
// to a pointer comparison).

module msgpack_tests
use xiom.io; use xiom.test;
use xiom.string; use xiom.string.compare;
use xiom.encoding.hex;
use xiom.msgpack;

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

fn repeat_byte(b: Int, n: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < n {
    v.push(b as UInt8);
    i = i + 1;
  }
  return v;
}

fn concat_bytes(a: Vec[UInt8], b: Vec[UInt8]) -> Vec[UInt8] {
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

// Decode helpers: each runs one reader on a fresh buffer.
fn int_read(data: Vec[UInt8]) -> Result[Int, Str] {
  var r = msgpack_reader_new(data);
  return msgpack_read_int(&mut r);
}

fn str_read(data: Vec[UInt8]) -> Result[Str, Str] {
  var r = msgpack_reader_new(data);
  return msgpack_read_str(&mut r);
}

fn bool_read(data: Vec[UInt8]) -> Result[Bool, Str] {
  var r = msgpack_reader_new(data);
  return msgpack_read_bool(&mut r);
}

fn array_len_read(data: Vec[UInt8]) -> Result[Int, Str] {
  var r = msgpack_reader_new(data);
  return msgpack_read_array_len(&mut r);
}

fn map_len_read(data: Vec[UInt8]) -> Result[Int, Str] {
  var r = msgpack_reader_new(data);
  return msgpack_read_map_len(&mut r);
}

fn peek_of(data: Vec[UInt8]) -> Result[Int, Str] {
  var r = msgpack_reader_new(data);
  return peek_mut(&mut r);
}

// Read-only API wrappers taking &mut (E001 advisory avoidance).
fn peek_mut(r: &mut MsgpackReader) -> Result[Int, Str] {
  return msgpack_peek_type(r);
}

fn r_pos(r: &mut MsgpackReader) -> Int {
  return msgpack_reader_pos(r);
}

fn r_remaining(r: &mut MsgpackReader) -> Int {
  return msgpack_reader_remaining(r);
}

fn err_text_is(r: Result[Int, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return compare.str_compare(r.error, want) == 0;
}

fn roundtrip_int(n: Int) -> Bool {
  var r = msgpack_reader_new(msgpack_encode_int(n));
  let res = msgpack_read_int(&mut r);
  if !res.is_ok {
    return false;
  }
  if res.value != n {
    return false;
  }
  if r_remaining(&mut r) != 0 {
    return false;
  }
  return r_pos(&mut r) > 0;
}

fn roundtrip_str(s: Str) -> Bool {
  var r = msgpack_reader_new(msgpack_encode_str(s));
  let res = msgpack_read_str(&mut r);
  if !res.is_ok {
    return false;
  }
  if compare.str_compare(res.value, s) != 0 {
    return false;
  }
  return r_remaining(&mut r) == 0;
}

fn roundtrip_bool(b: Bool) -> Bool {
  var r = msgpack_reader_new(msgpack_encode_bool(b));
  let res = msgpack_read_bool(&mut r);
  if !res.is_ok {
    return false;
  }
  if res.value != b {
    return false;
  }
  return r_remaining(&mut r) == 0;
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  var ok = bytes_equal(msgpack_encode_nil(), hb("c0"));
  if !bytes_equal(msgpack_encode_bool(false), hb("c2")) { ok = false; }
  if !bytes_equal(msgpack_encode_bool(true), hb("c3")) { ok = false; }
  return assert(ok, "nil and bool encodings: c0 / c2 / c3");
}

fn t2() -> TestResult {
  var ok = bytes_equal(msgpack_encode_int(0), hb("00"));
  if !bytes_equal(msgpack_encode_int(1), hb("01")) { ok = false; }
  if !bytes_equal(msgpack_encode_int(127), hb("7f")) { ok = false; }
  return assert(ok, "positive fixint: 0, 1, 127");
}

fn t3() -> TestResult {
  var ok = bytes_equal(msgpack_encode_int(-1), hb("ff"));
  if !bytes_equal(msgpack_encode_int(-32), hb("e0")) { ok = false; }
  return assert(ok, "negative fixint: -1, -32");
}

fn t4() -> TestResult {
  var ok = bytes_equal(msgpack_encode_int(128), hb("cc80"));
  if !bytes_equal(msgpack_encode_int(255), hb("ccff")) { ok = false; }
  if !bytes_equal(msgpack_encode_int(256), hb("cd0100")) { ok = false; }
  if !bytes_equal(msgpack_encode_int(65535), hb("cdffff")) { ok = false; }
  return assert(ok, "uint8/uint16 boundaries: 128, 255, 256, 65535");
}

fn t5() -> TestResult {
  var ok = bytes_equal(msgpack_encode_int(65536), hb("ce00010000"));
  if !bytes_equal(msgpack_encode_int(4294967295), hb("ceffffffff")) { ok = false; }
  if !bytes_equal(msgpack_encode_int(4294967296), hb("cf0000000100000000")) { ok = false; }
  return assert(ok, "uint32/uint64 boundaries: 65536, 2^32-1, 2^32");
}

fn t6() -> TestResult {
  var ok = bytes_equal(msgpack_encode_int(-33), hb("d0df"));
  if !bytes_equal(msgpack_encode_int(-128), hb("d080")) { ok = false; }
  if !bytes_equal(msgpack_encode_int(-129), hb("d1ff7f")) { ok = false; }
  if !bytes_equal(msgpack_encode_int(-32768), hb("d18000")) { ok = false; }
  return assert(ok, "int8/int16 boundaries: -33, -128, -129, -32768");
}

fn t7() -> TestResult {
  var ok = bytes_equal(msgpack_encode_int(-32769), hb("d2ffff7fff"));
  if !bytes_equal(msgpack_encode_int(-2147483648), hb("d280000000")) { ok = false; }
  if !bytes_equal(msgpack_encode_int(-2147483649), hb("d3ffffffff7fffffff")) { ok = false; }
  let int64min = 0 - 9223372036854775807 - 1;
  if !bytes_equal(msgpack_encode_int(int64min), hb("d38000000000000000")) { ok = false; }
  return assert(ok, "int32/int64 boundaries incl. INT64_MIN");
}

fn t8() -> TestResult {
  var ok = bytes_equal(msgpack_encode_str(""), hb("a0"));
  if !bytes_equal(msgpack_encode_str("abc"), hb("a3616263")) { ok = false; }
  let s31 = string.str_repeat("a", 31);
  let want31 = concat_bytes(hb("bf"), repeat_byte(97, 31));
  if !bytes_equal(msgpack_encode_str(s31), want31) { ok = false; }
  return assert(ok, "fixstr: empty, abc, 31-byte payload");
}

fn t9() -> TestResult {
  let s32 = string.str_repeat("a", 32);
  var ok = bytes_equal(msgpack_encode_str(s32), concat_bytes(hb("d920"), repeat_byte(97, 32)));
  let s255 = string.str_repeat("b", 255);
  if !bytes_equal(msgpack_encode_str(s255), concat_bytes(hb("d9ff"), repeat_byte(98, 255))) { ok = false; }
  return assert(ok, "str8: 32-byte and 255-byte payloads");
}

fn t10() -> TestResult {
  let s256 = string.str_repeat("c", 256);
  var ok = bytes_equal(msgpack_encode_str(s256), concat_bytes(hb("da0100"), repeat_byte(99, 256)));
  let s300 = string.str_repeat("d", 300);
  if msgpack_encode_str(s300).len() != 303 { ok = false; }
  if !roundtrip_str(s300) { ok = false; }
  return assert(ok, "str16: 256-byte and 300-byte payloads");
}

fn t11() -> TestResult {
  var ok = bytes_equal(msgpack_encode_array_header(0), hb("90"));
  if !bytes_equal(msgpack_encode_array_header(15), hb("9f")) { ok = false; }
  if !bytes_equal(msgpack_encode_array_header(16), hb("dc0010")) { ok = false; }
  if !bytes_equal(msgpack_encode_array_header(65535), hb("dcffff")) { ok = false; }
  if !bytes_equal(msgpack_encode_array_header(65536), hb("dd00010000")) { ok = false; }
  return assert(ok, "array headers: fixarray, array16, array32");
}

fn t12() -> TestResult {
  var ok = bytes_equal(msgpack_encode_map_header(0), hb("80"));
  if !bytes_equal(msgpack_encode_map_header(15), hb("8f")) { ok = false; }
  if !bytes_equal(msgpack_encode_map_header(16), hb("de0010")) { ok = false; }
  if !bytes_equal(msgpack_encode_map_header(65536), hb("df00010000")) { ok = false; }
  return assert(ok, "map headers: fixmap, map16, map32");
}

fn t13() -> TestResult {
  let neg_arr = msgpack_encode_array_header(-1);
  let neg_map = msgpack_encode_map_header(-1);
  let too_big = msgpack_encode_array_header(4294967296);
  var ok = neg_arr.len() == 0;
  if neg_map.len() != 0 { ok = false; }
  if too_big.len() != 0 { ok = false; }
  return assert(ok, "negative / > 2^32-1 counts encode as an empty vector");
}

fn t14() -> TestResult {
  var ok = roundtrip_int(0);
  if !roundtrip_int(1) { ok = false; }
  if !roundtrip_int(127) { ok = false; }
  if !roundtrip_int(128) { ok = false; }
  if !roundtrip_int(255) { ok = false; }
  if !roundtrip_int(256) { ok = false; }
  if !roundtrip_int(65535) { ok = false; }
  if !roundtrip_int(65536) { ok = false; }
  if !roundtrip_int(4294967295) { ok = false; }
  if !roundtrip_int(4294967296) { ok = false; }
  if !roundtrip_int(-1) { ok = false; }
  if !roundtrip_int(-32) { ok = false; }
  if !roundtrip_int(-33) { ok = false; }
  if !roundtrip_int(-128) { ok = false; }
  if !roundtrip_int(-129) { ok = false; }
  if !roundtrip_int(-32768) { ok = false; }
  if !roundtrip_int(-32769) { ok = false; }
  if !roundtrip_int(-2147483648) { ok = false; }
  if !roundtrip_int(-2147483649) { ok = false; }
  if !roundtrip_int(0 - 9223372036854775807 - 1) { ok = false; }
  return assert(ok, "reader round-trips every int boundary");
}

fn t15() -> TestResult {
  var ok = roundtrip_str("");
  if !roundtrip_str("a") { ok = false; }
  if !roundtrip_str("hello, msgpack") { ok = false; }
  if !roundtrip_str("héllo wörld") { ok = false; }
  if !roundtrip_str(string.str_repeat("x", 31)) { ok = false; }
  if !roundtrip_str(string.str_repeat("y", 32)) { ok = false; }
  if !roundtrip_str(string.str_repeat("z", 256)) { ok = false; }
  return assert(ok, "reader round-trips str payloads incl. UTF-8 and boundaries");
}

fn t16() -> TestResult {
  var ok = roundtrip_bool(false);
  if !roundtrip_bool(true) { ok = false; }
  var r = msgpack_reader_new(hb("c3"));
  let p = peek_mut(&mut r);
  if !p.is_ok { return assert(false, "peek_type sees the raw byte without advancing"); }
  if p.value != 195 { ok = false; }
  if r_pos(&mut r) != 0 { ok = false; }
  if r_remaining(&mut r) != 1 { ok = false; }
  return assert(ok, "reader round-trips bool and peek_type sees the raw byte");
}

fn t17() -> TestResult {
  var r = msgpack_reader_new(hb("2aa3616263c3"));
  if r_pos(&mut r) != 0 { return assert(false, "reader starts at position 0"); }
  if r_remaining(&mut r) != 6 { return assert(false, "reader remaining equals buffer length"); }
  let i1 = msgpack_read_int(&mut r);
  if !i1.is_ok { return assert(false, "stream int reads"); }
  if i1.value != 42 { return assert(false, "stream int value"); }
  if r_pos(&mut r) != 1 { return assert(false, "position advances past int"); }
  let s1 = msgpack_read_str(&mut r);
  if !s1.is_ok { return assert(false, "stream str reads"); }
  if compare.str_compare(s1.value, "abc") != 0 { return assert(false, "stream str value"); }
  if r_pos(&mut r) != 5 { return assert(false, "position advances past str"); }
  let b1 = msgpack_read_bool(&mut r);
  if !b1.is_ok { return assert(false, "stream bool reads"); }
  if !b1.value { return assert(false, "stream bool value"); }
  if r_pos(&mut r) != 6 { return assert(false, "position advances past bool"); }
  if r_remaining(&mut r) != 0 { return assert(false, "reader exhausted"); }
  return assert(true, "position advances over int + str + bool stream");
}

fn t18() -> TestResult {
  var ok = true;
  let a = int_read(hb("cc"));
  if a.is_ok { ok = false; }
  let b = int_read(hb("cd01"));
  if b.is_ok { ok = false; }
  let c = int_read(hb("ce0001"));
  if c.is_ok { ok = false; }
  let d = int_read(hb("d0"));
  if d.is_ok { ok = false; }
  let e = int_read(hb("cf00000000000000"));
  if e.is_ok { ok = false; }
  let f = int_read(hb(""));
  if f.is_ok { ok = false; }
  return assert(ok, "truncated int payloads are Err");
}

fn t19() -> TestResult {
  var ok = true;
  let a = str_read(hb("a361"));
  if a.is_ok { ok = false; }
  let b = str_read(hb("d9"));
  if b.is_ok { ok = false; }
  let c = str_read(hb("da01"));
  if c.is_ok { ok = false; }
  let d = str_read(hb("db000000"));
  if d.is_ok { ok = false; }
  let e = str_read(hb("db00000001"));
  if e.is_ok { ok = false; }
  return assert(ok, "truncated str headers and payloads are Err");
}

fn t20() -> TestResult {
  var ok = err_text_is(int_read(hb("c0")), "msgpack: unexpected type 0xc0");
  let s1 = str_read(hb("01"));
  if s1.is_ok { ok = false; }
  let b1 = bool_read(hb("cc00"));
  if b1.is_ok { ok = false; }
  let b2 = bool_read(hb("ff"));
  if b2.is_ok { ok = false; }
  let al = array_len_read(hb("80"));
  if al.is_ok { ok = false; }
  let ml = map_len_read(hb("90"));
  if ml.is_ok { ok = false; }
  return assert(ok, "wrong-type reads are Err with the 0xNN message");
}

fn t21() -> TestResult {
  var ok = err_text_is(int_read(hb("cc")), "msgpack: truncated buffer");
  let p = peek_of(hb(""));
  if p.is_ok { ok = false; }
  var r = msgpack_reader_new(Vec[UInt8].new());
  if r_pos(&mut r) != 0 { ok = false; }
  if r_remaining(&mut r) != 0 { ok = false; }
  return assert(ok, "truncated buffer message and empty reader state");
}

fn t22() -> TestResult {
  let a0 = array_len_read(hb("90"));
  let a16 = array_len_read(hb("dc0010"));
  let a32 = array_len_read(hb("dd00010000"));
  let m0 = map_len_read(hb("80"));
  let m16 = map_len_read(hb("de0010"));
  let m32 = map_len_read(hb("df00010000"));
  var ok = a0.is_ok && a0.value == 0;
  if !a16.is_ok { ok = false; } elif a16.value != 16 { ok = false; }
  if !a32.is_ok { ok = false; } elif a32.value != 65536 { ok = false; }
  if !m0.is_ok { ok = false; } elif m0.value != 0 { ok = false; }
  if !m16.is_ok { ok = false; } elif m16.value != 16 { ok = false; }
  if !m32.is_ok { ok = false; } elif m32.value != 65536 { ok = false; }
  return assert(ok, "read_array_len / read_map_len decode fix, 16 and 32-bit headers");
}

fn t23() -> TestResult {
  var ok = true;
  let a = array_len_read(hb("dc01"));
  if a.is_ok { ok = false; }
  let b = array_len_read(hb("dd0001"));
  if b.is_ok { ok = false; }
  let c = map_len_read(hb("de01"));
  if c.is_ok { ok = false; }
  let d = map_len_read(hb("df0001"));
  if d.is_ok { ok = false; }
  return assert(ok, "truncated array16/32 and map16/32 headers are Err");
}

fn t24() -> TestResult {
  let e255 = msgpack_encode_str(string.str_repeat("q", 255));
  let e256 = msgpack_encode_str(string.str_repeat("r", 256));
  var ok = e255.len() == 257;
  if e256.len() != 259 { ok = false; }
  if !roundtrip_str(string.str_repeat("q", 255)) { ok = false; }
  if !roundtrip_str(string.str_repeat("r", 256)) { ok = false; }
  return assert(ok, "str8/str16 round-trips at the 255/256-byte boundaries");
}

fn main() -> Int {
  io.println("=== xiom.msgpack conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.msgpack: all tests passed");
  } else {
    io.println("xiom.msgpack: tests failed");
  }
  return failed;
}
