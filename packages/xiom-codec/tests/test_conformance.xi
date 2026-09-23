// XIOM -- xiom.codec conformance tests (24 checks)
// Port task: prove the pure-XIOM xiom.codec module against RFC 4648.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API: base64 and base64url encode/decode (RFC 4648
// vectors, 0..8-byte round trips, optional padding, ignored whitespace,
// alphabet cross-decoding), base32 encode/decode (RFC 4648 vectors,
// case-insensitive decode, optional padding), hex encode/decode (lowercase
// output, case-insensitive input, odd-length errors) and the Str <-> UTF-8
// byte conversions.
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every comparison
// below is routed through streq instead of `==`. Expected byte vectors are
// built with the stdlib xiom.encoding.hex decoder (independent of the module
// under test).

module codec_tests
use xiom.io; use xiom.test; use xiom.codec;
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

// True when r is Ok and its bytes equal the hex expectation.
fn bytes_is(r: Result[Vec[UInt8], Str], hexstr: Str) -> Bool {
  if !r.is_ok {
    return false;
  }
  return bytes_equal(r.value, hb(hexstr));
}

// True when r is an Err whose message starts with "codec: ".
fn bytes_err(r: Result[Vec[UInt8], Str]) -> Bool {
  if r.is_ok {
    return false;
  }
  let m = r.error;
  if m.len() < 7 {
    return false;
  }
  return streq(string.str_slice(m, 0, 7), "codec: ");
}

// True when r is Ok(text) with text equal to `want`.
fn str_ok_is(r: Result[Str, Str], want: Str) -> Bool {
  if !r.is_ok {
    return false;
  }
  return streq(r.value, want);
}

// True when r is an Err whose message starts with "codec: ".
fn str_err(r: Result[Str, Str]) -> Bool {
  if r.is_ok {
    return false;
  }
  let m = r.error;
  if m.len() < 7 {
    return false;
  }
  return streq(string.str_slice(m, 0, 7), "codec: ");
}

// Deterministic byte sequence of length n (covers 0 and bytes >= 0x80).
fn seq_bytes(n: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < n {
    v.push(((i * 37 + 7) % 256) as UInt8);
    i = i + 1;
  }
  return v;
}

fn rt_b64(data: Vec[UInt8]) -> Bool {
  let dec = codec_b64_decode(codec_b64_encode(&data));
  if !dec.is_ok { return false; }
  return bytes_equal(dec.value, data);
}

fn rt_b64url(data: Vec[UInt8]) -> Bool {
  let dec = codec_b64url_decode(codec_b64url_encode(&data));
  if !dec.is_ok { return false; }
  return bytes_equal(dec.value, data);
}

fn rt_b32(data: Vec[UInt8]) -> Bool {
  let dec = codec_base32_decode(codec_base32_encode(&data));
  if !dec.is_ok { return false; }
  return bytes_equal(dec.value, data);
}

fn rt_hex(data: Vec[UInt8]) -> Bool {
  let dec = codec_hex_decode(codec_hex_encode(&data));
  if !dec.is_ok { return false; }
  return bytes_equal(dec.value, data);
}

fn t1() -> TestResult {
  var ok = streq(codec_b64_encode(&codec_str_to_bytes("")), "");
  if !streq(codec_b64_encode(&codec_str_to_bytes("f")), "Zg==") { ok = false; }
  if !streq(codec_b64_encode(&codec_str_to_bytes("fo")), "Zm8=") { ok = false; }
  if !streq(codec_b64_encode(&codec_str_to_bytes("foo")), "Zm9v") { ok = false; }
  if !streq(codec_b64_encode(&codec_str_to_bytes("foobar")), "Zm9vYmFy") { ok = false; }
  return assert(ok, "base64 encode: RFC 4648 vectors");
}

fn t2() -> TestResult {
  var ok = bytes_is(codec_b64_decode(""), "");
  if !bytes_is(codec_b64_decode("Zg=="), "66") { ok = false; }
  if !bytes_is(codec_b64_decode("Zm8="), "666f") { ok = false; }
  if !bytes_is(codec_b64_decode("Zm9v"), "666f6f") { ok = false; }
  if !bytes_is(codec_b64_decode("Zm9vYmFy"), "666f6f626172") { ok = false; }
  return assert(ok, "base64 decode: RFC 4648 vectors");
}

fn t3() -> TestResult {
  var ok = true;
  var n = 0;
  while n <= 8 {
    if !rt_b64(seq_bytes(n)) { ok = false; }
    n = n + 1;
  }
  return assert(ok, "base64 round-trip for 0..8 byte lengths");
}

fn t4() -> TestResult {
  var ok = bytes_err(codec_b64_decode("Zg="));
  if !bytes_err(codec_b64_decode("Zg===")) { ok = false; }
  if !bytes_err(codec_b64_decode("=")) { ok = false; }
  if !bytes_err(codec_b64_decode("Zm9v=")) { ok = false; }
  if !bytes_err(codec_b64_decode("Zg==Zg==")) { ok = false; }
  if !bytes_err(codec_b64_decode("Z=Z")) { ok = false; }
  return assert(ok, "base64 decode: malformed padding is Err");
}

fn t5() -> TestResult {
  var ok = bytes_err(codec_b64_decode("Zm9v!"));
  if !bytes_err(codec_b64_decode("Zm$v")) { ok = false; }
  if !bytes_err(codec_b64_decode("Zm9v.")) { ok = false; }
  if !bytes_err(codec_b64_decode("Zm9v-")) { ok = false; }
  if !bytes_err(codec_b64_decode("Zgé")) { ok = false; }
  return assert(ok, "base64 decode: invalid character is Err");
}

fn t6() -> TestResult {
  var ok = bytes_is(codec_b64_decode(" Zm9v "), "666f6f");
  if !bytes_is(codec_b64_decode("Zg==\r\n"), "66") { ok = false; }
  if !bytes_is(codec_b64_decode("Z\ng\t=\n="), "66") { ok = false; }
  if !bytes_is(codec_b64_decode("\t Zm9vYmFy \r\n"), "666f6f626172") { ok = false; }
  return assert(ok, "base64 decode: ASCII whitespace is ignored");
}

fn t7() -> TestResult {
  let e = codec_b64_decode("");
  var ok = e.is_ok;
  if ok {
    if e.value.len() != 0 { ok = false; }
  }
  if !bytes_is(codec_b64_decode("Zg"), "66") { ok = false; }
  if !bytes_is(codec_b64_decode("Zm8"), "666f") { ok = false; }
  return assert(ok, "base64 decode: empty input and optional padding");
}

fn t8() -> TestResult {
  var ok = streq(codec_b64url_encode(&codec_str_to_bytes("f")), "Zg");
  if !streq(codec_b64url_encode(&codec_str_to_bytes("fo")), "Zm8") { ok = false; }
  if !streq(codec_b64url_encode(&codec_str_to_bytes("foobar")), "Zm9vYmFy") { ok = false; }
  if !streq(codec_b64url_encode(&hb("fbefbe")), "----") { ok = false; }
  if !streq(codec_b64url_encode(&hb("ff")), "_w") { ok = false; }
  if !streq(codec_b64_encode(&hb("fbefbe")), "++++") { ok = false; }
  return assert(ok, "base64url encode: url alphabet, no padding");
}

fn t9() -> TestResult {
  var ok = bytes_is(codec_b64url_decode("Zg"), "66");
  if !bytes_is(codec_b64url_decode("Zg=="), "66") { ok = false; }
  if !bytes_is(codec_b64url_decode("----"), "fbefbe") { ok = false; }
  if !bytes_is(codec_b64url_decode("++++"), "fbefbe") { ok = false; }
  if !bytes_is(codec_b64url_decode("-w"), "fb") { ok = false; }
  if !bytes_is(codec_b64url_decode("+w"), "fb") { ok = false; }
  return assert(ok, "base64url decode: both alphabets, padding optional");
}

fn t10() -> TestResult {
  var ok = bytes_err(codec_b64url_decode("Zg="));
  if !bytes_err(codec_b64url_decode("_w!")) { ok = false; }
  if !bytes_err(codec_b64url_decode("Z.g")) { ok = false; }
  if !bytes_err(codec_b64url_decode("====")) { ok = false; }
  if !bytes_err(codec_b64_decode("----")) { ok = false; }
  return assert(ok, "base64url decode: bad char/padding, standard-alphabet rejection");
}

fn t11() -> TestResult {
  var ok = streq(codec_base32_encode(&codec_str_to_bytes("")), "");
  if !streq(codec_base32_encode(&codec_str_to_bytes("f")), "MY======") { ok = false; }
  if !streq(codec_base32_encode(&codec_str_to_bytes("fo")), "MZXQ====") { ok = false; }
  if !streq(codec_base32_encode(&codec_str_to_bytes("foo")), "MZXW6===") { ok = false; }
  if !streq(codec_base32_encode(&codec_str_to_bytes("foobar")), "MZXW6YTBOI======") { ok = false; }
  return assert(ok, "base32 encode: RFC 4648 vectors");
}

fn t12() -> TestResult {
  var ok = bytes_is(codec_base32_decode(""), "");
  if !bytes_is(codec_base32_decode("MY======"), "66") { ok = false; }
  if !bytes_is(codec_base32_decode("MZXQ===="), "666f") { ok = false; }
  if !bytes_is(codec_base32_decode("MZXW6==="), "666f6f") { ok = false; }
  if !bytes_is(codec_base32_decode("MZXW6YTBOI======"), "666f6f626172") { ok = false; }
  return assert(ok, "base32 decode: RFC 4648 vectors");
}

fn t13() -> TestResult {
  var ok = bytes_is(codec_base32_decode("my======"), "66");
  if !bytes_is(codec_base32_decode("MzXw6YtBoI======"), "666f6f626172") { ok = false; }
  if !bytes_is(codec_base32_decode("mZxW6==="), "666f6f") { ok = false; }
  return assert(ok, "base32 decode: case-insensitive");
}

fn t14() -> TestResult {
  var ok = bytes_is(codec_base32_decode("MY"), "66");
  if !bytes_is(codec_base32_decode("MZXQ"), "666f") { ok = false; }
  if !bytes_is(codec_base32_decode("MZXW6"), "666f6f") { ok = false; }
  if !bytes_is(codec_base32_decode("MZXW6YTB"), "666f6f6261") { ok = false; }
  if !bytes_is(codec_base32_decode("MZXW6YTBOI"), "666f6f626172") { ok = false; }
  return assert(ok, "base32 decode: padding optional");
}

fn t15() -> TestResult {
  var ok = bytes_err(codec_base32_decode("M"));
  if !bytes_err(codec_base32_decode("MY=")) { ok = false; }
  if !bytes_err(codec_base32_decode("MY=====")) { ok = false; }
  if !bytes_err(codec_base32_decode("MY=====M")) { ok = false; }
  if !bytes_err(codec_base32_decode("M1======")) { ok = false; }
  if !bytes_err(codec_base32_decode("MY!=====")) { ok = false; }
  if !bytes_err(codec_base32_decode("========")) { ok = false; }
  return assert(ok, "base32 decode: invalid char, length and padding are Err");
}

fn t16() -> TestResult {
  var ok = true;
  var n = 0;
  while n <= 8 {
    if !rt_b32(seq_bytes(n)) { ok = false; }
    n = n + 1;
  }
  return assert(ok, "base32 round-trip for 0..8 byte lengths");
}

fn t17() -> TestResult {
  var ok = streq(codec_hex_encode(&codec_str_to_bytes("")), "");
  if !streq(codec_hex_encode(&codec_str_to_bytes("foobar")), "666f6f626172") { ok = false; }
  if !streq(codec_hex_encode(&hb("000f10ff")), "000f10ff") { ok = false; }
  if !streq(codec_hex_encode(&hb("ABCDEF")), "abcdef") { ok = false; }
  return assert(ok, "hex encode: lowercase hex");
}

fn t18() -> TestResult {
  var ok = bytes_is(codec_hex_decode("666f6f626172"), "666f6f626172");
  if !bytes_is(codec_hex_decode("666F6F626172"), "666f6f626172") { ok = false; }
  if !bytes_is(codec_hex_decode("DEADBEEF"), "deadbeef") { ok = false; }
  if !bytes_is(codec_hex_decode(""), "") { ok = false; }
  return assert(ok, "hex decode: upper- and lowercase, empty input");
}

fn t19() -> TestResult {
  var ok = bytes_err(codec_hex_decode("abc"));
  if !bytes_err(codec_hex_decode("0")) { ok = false; }
  if !bytes_err(codec_hex_decode("0g")) { ok = false; }
  if !bytes_err(codec_hex_decode("zz")) { ok = false; }
  if !bytes_err(codec_hex_decode("1 34")) { ok = false; }
  return assert(ok, "hex decode: odd length and invalid characters are Err");
}

fn t20() -> TestResult {
  var ok = true;
  var n = 0;
  while n <= 8 {
    if !rt_hex(seq_bytes(n)) { ok = false; }
    n = n + 1;
  }
  return assert(ok, "hex round-trip for 0..8 byte lengths");
}

fn t21() -> TestResult {
  var ok = str_ok_is(codec_bytes_to_str(&codec_str_to_bytes("")), "");
  if !str_ok_is(codec_bytes_to_str(&codec_str_to_bytes("hello")), "hello") { ok = false; }
  if !str_ok_is(codec_bytes_to_str(&codec_str_to_bytes("héllo")), "héllo") { ok = false; }
  let four = codec_bytes_to_str(&hb("f09f9880"));
  if !four.is_ok { ok = false; }
  if four.is_ok {
    if four.value.len() != 4 { ok = false; }
  }
  return assert(ok, "bytes_to_str: valid UTF-8 (ASCII, 2-byte, 4-byte)");
}

fn t22() -> TestResult {
  var ok = str_err(codec_bytes_to_str(&hb("ff")));
  if !str_err(codec_bytes_to_str(&hb("80"))) { ok = false; }
  if !str_err(codec_bytes_to_str(&hb("c3"))) { ok = false; }
  if !str_err(codec_bytes_to_str(&hb("eda080"))) { ok = false; }
  if !str_err(codec_bytes_to_str(&hb("f0808080"))) { ok = false; }
  return assert(ok, "bytes_to_str: malformed UTF-8 is Err");
}

fn t23() -> TestResult {
  var ok = bytes_equal(codec_str_to_bytes("A"), hb("41"));
  if codec_str_to_bytes("").len() != 0 { ok = false; }
  if !bytes_equal(codec_str_to_bytes("é"), hb("c3a9")) { ok = false; }
  if !bytes_equal(codec_str_to_bytes("foobar"), hb("666f6f626172")) { ok = false; }
  return assert(ok, "str_to_bytes: UTF-8 bytes verbatim");
}

fn t24() -> TestResult {
  let text = "The quick brown fox! 123";
  let bytes = codec_str_to_bytes(text);
  var ok = true;
  if !bytes_equal(codec_b64_decode(codec_b64_encode(&bytes)).value, bytes) { ok = false; }
  if !bytes_equal(codec_b64url_decode(codec_b64url_encode(&bytes)).value, bytes) { ok = false; }
  if !bytes_equal(codec_base32_decode(codec_base32_encode(&bytes)).value, bytes) { ok = false; }
  if !bytes_equal(codec_hex_decode(codec_hex_encode(&bytes)).value, bytes) { ok = false; }
  let back = codec_bytes_to_str(&bytes);
  if !back.is_ok { ok = false; }
  if back.is_ok && !streq(back.value, text) { ok = false; }
  return assert(ok, "full pipeline: str -> bytes -> four codecs -> str");
}

fn main() -> Int {
  io.println("=== xiom.codec conformance tests ===");
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
    io.println("xiom.codec: all tests passed");
  } else {
    io.println("xiom.codec: tests failed");
  }
  return failed;
}
