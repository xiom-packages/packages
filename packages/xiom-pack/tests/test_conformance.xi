// XIOM -- xiom.pack conformance tests (22 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API: exact bytes for every token in both byte
// orders (u8/s8/b8, u16/s16, u32/s32, u64/s64 LE+BE), signed
// two's-complement negatives, INT64 extremes, the u64 bit-pattern maximum,
// per-token range violations, token-count mismatches, unknown tokens, the
// pack_size table, a six-field round-trip, an all-token round-trip, offset
// reads inside a longer stream, truncated data, negative offsets and the
// masked convenience appenders.
//
// Str values are compared with str_compare (BUG 17 discipline: `==` on Str
// values read from a Vec lowers to a pointer comparison) and every Vec read
// goes through a typed local before it is used.

module pack_tests
use xiom.io; use xiom.test;
use xiom.string.compare;
use xiom.encoding.hex;
use xiom.pack;

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

fn ints_equal(a: Vec[Int], b: Vec[Int]) -> Bool {
  if a.len() != b.len() {
    return false;
  }
  var i = 0;
  while i < a.len() {
    let x: Int = a[i];
    let y: Int = b[i];
    if x != y {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// Vec[Int] builders (v0.61.3 has no lambdas).
fn empty_ints() -> Vec[Int] {
  var v = Vec[Int].new();
  return v;
}

fn v1(a: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  return v;
}

fn v2(a: Int, b: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  return v;
}

fn v3(a: Int, b: Int, c: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  return v;
}

fn v6(a: Int, b: Int, c: Int, d: Int, e: Int, f: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  v.push(e);
  v.push(f);
  return v;
}

// True when pack_format(fmt, vals) is Ok and its bytes equal `want_hex`.
fn pack_is(fmt: Str, vals: &Vec[Int], want_hex: Str) -> Bool {
  let r = pack_format(fmt, vals);
  if !r.is_ok {
    return false;
  }
  let got: Vec[UInt8] = r.value;
  return bytes_equal(got, hb(want_hex));
}

// True when pack_format(fmt, vals) is Err with exactly the message `want`.
fn pack_err_is(fmt: Str, vals: &Vec[Int], want: Str) -> Bool {
  let r = pack_format(fmt, vals);
  if r.is_ok {
    return false;
  }
  return streq(r.error, want);
}

// True when pack_size(fmt) is Ok with the exact total `want`.
fn size_is(fmt: Str, want: Int) -> Bool {
  let r = pack_size(fmt);
  if !r.is_ok {
    return false;
  }
  let got: Int = r.value;
  return got == want;
}

// True when pack_size(fmt) is Err with exactly the message `want`.
fn size_err_is(fmt: Str, want: Str) -> Bool {
  let r = pack_size(fmt);
  if r.is_ok {
    return false;
  }
  return streq(r.error, want);
}

// True when unpack_format(fmt, data, off) is Ok with exactly `want`.
fn unpack_is(fmt: Str, data: &Vec[UInt8], off: Int, want: &Vec[Int]) -> Bool {
  let r = unpack_format(fmt, data, off);
  if !r.is_ok {
    return false;
  }
  let got: Vec[Int] = r.value;
  return ints_equal(got, want);
}

// True when unpack_format(fmt, data, off) is Err with exactly `want`.
fn unpack_err_is(fmt: Str, data: &Vec[UInt8], off: Int, want: Str) -> Bool {
  let r = unpack_format(fmt, data, off);
  if r.is_ok {
    return false;
  }
  return streq(r.error, want);
}

// Pack then unpack the same field list; true when the values round-trip and
// the encoded length equals pack_size(fmt).
fn roundtrip(fmt: Str, vals: &Vec[Int]) -> Bool {
  let pr = pack_format(fmt, vals);
  if !pr.is_ok {
    return false;
  }
  let bytes: Vec[UInt8] = pr.value;
  let sr = pack_size(fmt);
  if !sr.is_ok {
    return false;
  }
  let total: Int = sr.value;
  if bytes.len() != total {
    return false;
  }
  return unpack_is(fmt, &bytes, 0, vals);
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  let e = empty_ints();
  let eb = Vec[UInt8].new();
  var ok = pack_is("", &e, "");
  if !size_is("", 0) { ok = false; }
  if !size_is("   ", 0) { ok = false; }
  if !unpack_is("", &eb, 0, &e) { ok = false; }
  if !unpack_is("", hb("aabb"), 2, &e) { ok = false; }
  if pack_token_size("") != 0 { ok = false; }
  return assert(ok, "empty format with empty values packs to an empty vector");
}

fn t2() -> TestResult {
  var ok = pack_is("u8", v1(0), "00");
  if !pack_is("u8", v1(18), "12") { ok = false; }
  if !pack_is("u8", v1(255), "ff") { ok = false; }
  if !unpack_is("u8", hb("00"), 0, v1(0)) { ok = false; }
  if !unpack_is("u8", hb("12"), 0, v1(18)) { ok = false; }
  if !unpack_is("u8", hb("ff"), 0, v1(255)) { ok = false; }
  return assert(ok, "u8 exact bytes 00/12/ff and decode");
}

fn t3() -> TestResult {
  var ok = pack_is("s8", v1(0), "00");
  if !pack_is("s8", v1(127), "7f") { ok = false; }
  if !pack_is("s8", v1(-1), "ff") { ok = false; }
  if !pack_is("s8", v1(-128), "80") { ok = false; }
  if !unpack_is("s8", hb("7f"), 0, v1(127)) { ok = false; }
  if !unpack_is("s8", hb("80"), 0, v1(-128)) { ok = false; }
  if !unpack_is("s8", hb("ff"), 0, v1(-1)) { ok = false; }
  return assert(ok, "s8 -1 packs to ff; signed bytes sign-extend on decode");
}

fn t4() -> TestResult {
  var ok = pack_is("b8", v1(0), "00");
  if !pack_is("b8", v1(1), "01") { ok = false; }
  if !unpack_is("b8", hb("00"), 0, v1(0)) { ok = false; }
  if !unpack_is("b8", hb("01"), 0, v1(1)) { ok = false; }
  if !unpack_is("b8", hb("02"), 0, v1(1)) { ok = false; }
  if !pack_err_is("b8", v1(2), "pack: b8 out of range") { ok = false; }
  if !pack_err_is("b8", v1(-1), "pack: b8 out of range") { ok = false; }
  return assert(ok, "b8 values encode 0/1 and decode 0/1 (nonzero canonicalised)");
}

fn t5() -> TestResult {
  var ok = pack_is("u16le", v1(0x1234), "3412");
  if !pack_is("u16be", v1(0x1234), "1234") { ok = false; }
  if !pack_is("u16le", v1(0), "0000") { ok = false; }
  if !pack_is("u16le", v1(65535), "ffff") { ok = false; }
  if !pack_is("u16be", v1(65535), "ffff") { ok = false; }
  if !unpack_is("u16le", hb("3412"), 0, v1(0x1234)) { ok = false; }
  if !unpack_is("u16be", hb("1234"), 0, v1(0x1234)) { ok = false; }
  if !unpack_is("u16be", hb("ffff"), 0, v1(65535)) { ok = false; }
  return assert(ok, "u16le/u16be: 0x1234 is 34 12 / 12 34");
}

fn t6() -> TestResult {
  var ok = pack_is("s16le", v1(-1), "ffff");
  if !pack_is("s16be", v1(-1), "ffff") { ok = false; }
  if !pack_is("s16le", v1(-2), "feff") { ok = false; }
  if !pack_is("s16be", v1(-2), "fffe") { ok = false; }
  if !pack_is("s16le", v1(-32768), "0080") { ok = false; }
  if !pack_is("s16be", v1(-32768), "8000") { ok = false; }
  if !pack_is("s16le", v1(32767), "ff7f") { ok = false; }
  if !pack_is("s16be", v1(32767), "7fff") { ok = false; }
  if !unpack_is("s16le", hb("0080"), 0, v1(-32768)) { ok = false; }
  if !unpack_is("s16be", hb("8000"), 0, v1(-32768)) { ok = false; }
  if !unpack_is("s16le", hb("ff7f"), 0, v1(32767)) { ok = false; }
  if !unpack_is("s16be", hb("7fff"), 0, v1(32767)) { ok = false; }
  return assert(ok, "s16le/s16be two's-complement negatives in both byte orders");
}

fn t7() -> TestResult {
  var ok = pack_is("u32le", v1(0x12345678), "78563412");
  if !pack_is("u32be", v1(0x12345678), "12345678") { ok = false; }
  if !unpack_is("u32le", hb("78563412"), 0, v1(0x12345678)) { ok = false; }
  if !unpack_is("u32be", hb("12345678"), 0, v1(0x12345678)) { ok = false; }
  return assert(ok, "u32le/u32be: 0x12345678 is 78 56 34 12 / 12 34 56 78");
}

fn t8() -> TestResult {
  var ok = pack_is("u32le", v1(4294967295), "ffffffff");
  if !pack_is("u32be", v1(4294967295), "ffffffff") { ok = false; }
  if !unpack_is("u32le", hb("ffffffff"), 0, v1(4294967295)) { ok = false; }
  if !unpack_is("u32be", hb("ffffffff"), 0, v1(4294967295)) { ok = false; }
  return assert(ok, "u32 0xffffffff pins to all-ff in both byte orders");
}

fn t9() -> TestResult {
  var ok = pack_is("s32le", v1(-1), "ffffffff");
  if !pack_is("s32be", v1(-1), "ffffffff") { ok = false; }
  if !pack_is("s32le", v1(-2147483648), "00000080") { ok = false; }
  if !pack_is("s32be", v1(-2147483648), "80000000") { ok = false; }
  if !pack_is("s32le", v1(2147483647), "ffffff7f") { ok = false; }
  if !pack_is("s32be", v1(2147483647), "7fffffff") { ok = false; }
  if !unpack_is("s32le", hb("00000080"), 0, v1(-2147483648)) { ok = false; }
  if !unpack_is("s32be", hb("80000000"), 0, v1(-2147483648)) { ok = false; }
  if !unpack_is("s32le", hb("ffffff7f"), 0, v1(2147483647)) { ok = false; }
  if !unpack_is("s32be", hb("7fffffff"), 0, v1(2147483647)) { ok = false; }
  return assert(ok, "s32le/s32be boundaries -2^31, 2^31-1 and -1");
}

fn t10() -> TestResult {
  var ok = pack_is("u64le", v1(0x0102030405060708), "0807060504030201");
  if !pack_is("u64be", v1(0x0102030405060708), "0102030405060708") { ok = false; }
  if !pack_is("u64le", v1(9223372036854775807), "ffffffffffffff7f") { ok = false; }
  if !pack_is("u64be", v1(9223372036854775807), "7fffffffffffffff") { ok = false; }
  if !unpack_is("u64le", hb("0807060504030201"), 0, v1(0x0102030405060708)) { ok = false; }
  if !unpack_is("u64be", hb("7fffffffffffffff"), 0, v1(9223372036854775807)) { ok = false; }
  return assert(ok, "u64le/u64be: 0x0102030405060708 byte reversal and 2^63-1");
}

fn t11() -> TestResult {
  var ok = pack_is("u64le", v1(0 - 1), "ffffffffffffffff");
  if !pack_is("u64be", v1(0 - 1), "ffffffffffffffff") { ok = false; }
  if !unpack_is("u64le", hb("ffffffffffffffff"), 0, v1(0 - 1)) { ok = false; }
  if !unpack_is("u64be", hb("ffffffffffffffff"), 0, v1(0 - 1)) { ok = false; }
  return assert(ok, "u64 max (2^64-1) is ff*8; the bit pattern decodes as Int -1");
}

fn t12() -> TestResult {
  let i64max = 9223372036854775807;
  let i64min = 0 - 9223372036854775807 - 1;
  var ok = pack_is("s64le", v1(-1), "ffffffffffffffff");
  if !pack_is("s64be", v1(-1), "ffffffffffffffff") { ok = false; }
  if !pack_is("s64le", v1(i64min), "0000000000000080") { ok = false; }
  if !pack_is("s64be", v1(i64min), "8000000000000000") { ok = false; }
  if !pack_is("s64le", v1(i64max), "ffffffffffffff7f") { ok = false; }
  if !pack_is("s64be", v1(i64max), "7fffffffffffffff") { ok = false; }
  if !unpack_is("s64le", hb("0000000000000080"), 0, v1(i64min)) { ok = false; }
  if !unpack_is("s64be", hb("8000000000000000"), 0, v1(i64min)) { ok = false; }
  if !unpack_is("s64le", hb("ffffffffffffff7f"), 0, v1(i64max)) { ok = false; }
  if !unpack_is("s64be", hb("7fffffffffffffff"), 0, v1(i64max)) { ok = false; }
  return assert(ok, "s64le/s64be INT64_MIN, INT64_MAX and -1");
}

fn t13() -> TestResult {
  var ok = pack_err_is("u8", v1(256), "pack: u8 out of range");
  if !pack_err_is("u8", v1(-1), "pack: u8 out of range") { ok = false; }
  if !pack_err_is("s8", v1(128), "pack: s8 out of range") { ok = false; }
  if !pack_err_is("s8", v1(-129), "pack: s8 out of range") { ok = false; }
  if !pack_err_is("u16le", v1(65536), "pack: u16le out of range") { ok = false; }
  if !pack_err_is("u16be", v1(-1), "pack: u16be out of range") { ok = false; }
  if !pack_err_is("s16le", v1(-32769), "pack: s16le out of range") { ok = false; }
  if !pack_err_is("s16be", v1(32768), "pack: s16be out of range") { ok = false; }
  if !pack_err_is("u32le", v1(4294967296), "pack: u32le out of range") { ok = false; }
  if !pack_err_is("u32be", v1(-1), "pack: u32be out of range") { ok = false; }
  if !pack_err_is("s32le", v1(2147483648), "pack: s32le out of range") { ok = false; }
  if !pack_err_is("s32be", v1(-2147483649), "pack: s32be out of range") { ok = false; }
  return assert(ok, "range violations are Err(pack: <token> out of range)");
}

fn t14() -> TestResult {
  let e = empty_ints();
  var ok = pack_err_is("u8", &e, "pack: token count mismatch");
  if !pack_err_is("", v1(1), "pack: token count mismatch") { ok = false; }
  if !pack_err_is("u8 u8", v1(1), "pack: token count mismatch") { ok = false; }
  if !pack_err_is("u8", v2(1, 2), "pack: token count mismatch") { ok = false; }
  if !pack_err_is("u16le u16be", v3(1, 2, 3), "pack: token count mismatch") { ok = false; }
  return assert(ok, "token count must equal values.len()");
}

fn t15() -> TestResult {
  var ok = size_is("u8 s8 b8", 3);
  if !size_is("u16le u32be", 6) { ok = false; }
  if !size_is("s64le u64be", 16) { ok = false; }
  if !size_is("u8", 1) { ok = false; }
  if !size_is("", 0) { ok = false; }
  if pack_token_size("u8") != 1 { ok = false; }
  if pack_token_size("s8") != 1 { ok = false; }
  if pack_token_size("b8") != 1 { ok = false; }
  if pack_token_size("u16le") != 2 { ok = false; }
  if pack_token_size("s16be") != 2 { ok = false; }
  if pack_token_size("u32be") != 4 { ok = false; }
  if pack_token_size("s32le") != 4 { ok = false; }
  if pack_token_size("u64le") != 8 { ok = false; }
  if pack_token_size("s64be") != 8 { ok = false; }
  if pack_token_size("u16") != 0 { ok = false; }
  if pack_token_size("U8") != 0 { ok = false; }
  if pack_token_size("nope") != 0 { ok = false; }
  if !size_err_is("u9", "pack: unknown token 'u9'") { ok = false; }
  if !size_err_is("u8 u16", "pack: unknown token 'u16'") { ok = false; }
  return assert(ok, "pack_size table and pack_token_size widths");
}

fn t16() -> TestResult {
  let fmt = "u8 s8 u16le u16be s32le s64be";
  let vals = v6(200, -5, 0x1234, 0xBEEF, -123456, -1);
  let want = "c8fb3412beefc01dfeff" + "ffffffffffffffff";
  var ok = pack_is(fmt, &vals, want);
  if !size_is(fmt, 18) { ok = false; }
  if !roundtrip(fmt, &vals) { ok = false; }
  return assert(ok, "six-field format round-trips (18 bytes)");
}

fn t17() -> TestResult {
  let stream = hb("aabb3412fffeccdd");
  var ok = unpack_is("u16le s16be", &stream, 2, v2(0x1234, -2));
  if !unpack_is("s16be", &stream, 4, v1(-2)) { ok = false; }
  if !unpack_is("u16le", &stream, 2, v1(0x1234)) { ok = false; }
  if !unpack_is("u8 u8 u16le s16be u8 u8", &stream, 0, v6(0xAA, 0xBB, 0x1234, -2, 0xCC, 0xDD)) { ok = false; }
  return assert(ok, "unpack honours a non-zero offset inside a stream");
}

fn t18() -> TestResult {
  var ok = unpack_err_is("u32le", hb("010203"), 0, "pack: truncated data");
  if !unpack_err_is("u8", hb(""), 0, "pack: truncated data") { ok = false; }
  if !unpack_err_is("u16be", hb("01"), 0, "pack: truncated data") { ok = false; }
  if !unpack_err_is("u8", hb("0102"), 2, "pack: truncated data") { ok = false; }
  if !unpack_err_is("u8", hb("0102"), 3, "pack: truncated data") { ok = false; }
  if !unpack_err_is("", hb("0102"), 3, "pack: truncated data") { ok = false; }
  if !unpack_err_is("u8", hb("01"), -1, "pack: negative offset") { ok = false; }
  if !unpack_err_is("u64le", hb("0102"), 0, "pack: truncated data") { ok = false; }
  return assert(ok, "truncated data and negative offsets are Err");
}

fn t19() -> TestResult {
  var ok = pack_err_is("u9", v1(0), "pack: unknown token 'u9'");
  if !pack_err_is("u8 nope", v2(1, 2), "pack: unknown token 'nope'") { ok = false; }
  if !pack_err_is("U8", v1(1), "pack: unknown token 'U8'") { ok = false; }
  if !pack_err_is("u16", v1(1), "pack: unknown token 'u16'") { ok = false; }
  if !pack_err_is("s8le", v1(1), "pack: unknown token 's8le'") { ok = false; }
  if !unpack_err_is("u9", hb("00"), 0, "pack: unknown token 'u9'") { ok = false; }
  if !unpack_err_is("u8 zz", hb("0000"), 0, "pack: unknown token 'zz'") { ok = false; }
  if pack_token_size("u9") != 0 { ok = false; }
  return assert(ok, "unknown tokens are Err in pack_format, pack_size and unpack_format");
}

fn t20() -> TestResult {
  var out = Vec[UInt8].new();
  pack_u16_le(&mut out, 0x1234);
  pack_u16_be(&mut out, 0x1234);
  var ok = bytes_equal(out, hb("34121234"));
  var masked = Vec[UInt8].new();
  pack_u16_le(&mut masked, 0x12345);
  pack_u16_be(&mut masked, 0x12345);
  if !bytes_equal(masked, hb("45232345")) { ok = false; }
  var wide = Vec[UInt8].new();
  pack_u32_le(&mut wide, 4294967296);
  pack_u32_be(&mut wide, 4294967296);
  if !bytes_equal(wide, hb("0000000000000000")) { ok = false; }
  var neg = Vec[UInt8].new();
  pack_u32_le(&mut neg, -1);
  pack_u32_be(&mut neg, -1);
  if !bytes_equal(neg, hb("ffffffffffffffff")) { ok = false; }
  var w64 = Vec[UInt8].new();
  pack_u64_le(&mut w64, 0x0102030405060708);
  pack_u64_be(&mut w64, 0x0102030405060708);
  if !bytes_equal(w64, hb("08070605040302010102030405060708")) { ok = false; }
  var m64 = Vec[UInt8].new();
  pack_u64_le(&mut m64, 0 - 1);
  pack_u64_be(&mut m64, 0 - 1);
  if !bytes_equal(m64, hb("ffffffffffffffffffffffffffffffff")) { ok = false; }
  return assert(ok, "u16/u32/u64 appenders write masked low bytes in order");
}

fn t21() -> TestResult {
  var out = Vec[UInt8].new();
  pack_s16_le(&mut out, -1);
  pack_s16_be(&mut out, -2);
  pack_s16_le(&mut out, -32768);
  pack_s16_be(&mut out, -32768);
  var ok = bytes_equal(out, hb("fffffffe00808000"));
  var w32 = Vec[UInt8].new();
  pack_s32_le(&mut w32, -1);
  pack_s32_be(&mut w32, -2147483648);
  if !bytes_equal(w32, hb("ffffffff80000000")) { ok = false; }
  let i64min = 0 - 9223372036854775807 - 1;
  var w64 = Vec[UInt8].new();
  pack_s64_le(&mut w64, i64min);
  pack_s64_be(&mut w64, i64min);
  pack_s64_le(&mut w64, -1);
  if !bytes_equal(w64, hb("00000000000000808000000000000000ffffffffffffffff")) { ok = false; }
  return assert(ok, "s16/s32/s64 appenders write two's-complement bytes in order");
}

fn t22() -> TestResult {
  let fmt = "u8 s8 b8 u16le s16le u32le s32le u64le s64le u16be s16be u32be s32be u64be s64be";
  var vals = Vec[Int].new();
  vals.push(255);
  vals.push(-128);
  vals.push(1);
  vals.push(0xFFFF);
  vals.push(-32768);
  vals.push(0xFFFFFFFF);
  vals.push(-2147483648);
  vals.push(0x0102030405060708);
  vals.push(0 - 9223372036854775807 - 1);
  vals.push(0x1234);
  vals.push(-2);
  vals.push(0x12345678);
  vals.push(-123456);
  vals.push(9223372036854775807);
  vals.push(-1);
  var ok = size_is(fmt, 59);
  if !roundtrip(fmt, &vals) { ok = false; }
  return assert(ok, "all 19 tokens in one format round-trip (59 bytes)");
}

fn main() -> Int {
  io.println("=== xiom.pack conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.pack: all tests passed");
  } else {
    io.println("xiom.pack: tests failed");
  }
  return failed;
}
