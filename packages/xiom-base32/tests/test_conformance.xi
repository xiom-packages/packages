// XIOM -- xiom.base32 conformance tests (18 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API: the RFC 4648 section 10 vectors ("", "f", "fo",
// "foo", "foob", "fooba", "foobar"), boundary remainders 1..5 bytes, empty
// input, case-insensitive decoding, strict padding position and padding
// count rules, unpadded (truncated) input, non-canonical trailing bits,
// invalid characters, round-trips for lengths 0..40 plus a pinned 64-byte
// buffer, high-byte vectors, an exhaustive one-byte sweep, base32_is_valid
// and the alphabet.
//
// All Str equality goes through str_compare (BUG 17 discipline: `==` on Str
// values read from a Vec lowers to a pointer comparison, so every comparison
// below is routed through streq). Expected byte vectors are built with the
// stdlib xiom.encoding.hex decoder, independent of the module under test;
// pinned vectors were cross-checked against an independent Base32
// implementation (Python base64.b32encode).

module base32_tests
use xiom.io; use xiom.test; use xiom.base32;
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

// True when r is Ok(empty).
fn bytes_ok_empty(r: Result[Vec[UInt8], Str]) -> Bool {
  if !r.is_ok {
    return false;
  }
  return r.value.len() == 0;
}

// True when r is Err with exactly the message `want`.
fn bytes_err_is(r: Result[Vec[UInt8], Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return streq(r.error, want);
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

// True when encode -> decode returns the same bytes.
fn rt(data: Vec[UInt8]) -> Bool {
  let dec = base32_decode(base32_encode(&data));
  if !dec.is_ok { return false; }
  return bytes_equal(dec.value, data);
}

// True when encoding the bytes of `hexstr` yields `want`.
fn enc_hex_is(hexstr: Str, want: Str) -> Bool {
  let data = hb(hexstr);
  return streq(base32_encode(&data), want);
}

// True when decoding `s` yields exactly the bytes of `hexstr`.
fn dec_hex_is(s: Str, hexstr: Str) -> Bool {
  let r = base32_decode(s);
  if !r.is_ok {
    return false;
  }
  return bytes_equal(r.value, hb(hexstr));
}

fn t1() -> TestResult {
  var ok = enc_hex_is("", "");
  if !enc_hex_is("66", "MY======") { ok = false; }
  if !enc_hex_is("666f", "MZXQ====") { ok = false; }
  if !enc_hex_is("666f6f", "MZXW6===") { ok = false; }
  if !enc_hex_is("666f6f62", "MZXW6YQ=") { ok = false; }
  if !enc_hex_is("666f6f6261", "MZXW6YTB") { ok = false; }
  if !enc_hex_is("666f6f626172", "MZXW6YTBOI======") { ok = false; }
  return assert(ok, "encode: RFC 4648 section 10 vectors");
}

fn t2() -> TestResult {
  var ok = bytes_ok_empty(base32_decode(""));
  if !dec_hex_is("MY======", "66") { ok = false; }
  if !dec_hex_is("MZXQ====", "666f") { ok = false; }
  if !dec_hex_is("MZXW6===", "666f6f") { ok = false; }
  if !dec_hex_is("MZXW6YQ=", "666f6f62") { ok = false; }
  if !dec_hex_is("MZXW6YTB", "666f6f6261") { ok = false; }
  if !dec_hex_is("MZXW6YTBOI======", "666f6f626172") { ok = false; }
  return assert(ok, "decode: RFC 4648 section 10 vectors");
}

fn t3() -> TestResult {
  var ok = enc_hex_is("07", "A4======");
  if !enc_hex_is("072c", "A4WA====") { ok = false; }
  if !enc_hex_is("072c51", "A4WFC===") { ok = false; }
  if !enc_hex_is("072c5176", "A4WFC5Q=") { ok = false; }
  if !enc_hex_is("072c51769b", "A4WFC5U3") { ok = false; }
  if !enc_hex_is("072c51769bc0", "A4WFC5U3YA======") { ok = false; }
  return assert(ok, "encode: 1..5 byte remainders are pinned");
}

fn t4() -> TestResult {
  var ok = dec_hex_is("A4======", "07");
  if !dec_hex_is("A4WA====", "072c") { ok = false; }
  if !dec_hex_is("A4WFC===", "072c51") { ok = false; }
  if !dec_hex_is("A4WFC5Q=", "072c5176") { ok = false; }
  if !dec_hex_is("A4WFC5U3", "072c51769b") { ok = false; }
  var n = 0;
  while n <= 10 {
    let data = seq_bytes(n);
    let enc = base32_encode(&data);
    if enc.len() != ((n + 4) / 5) * 8 { ok = false; }
    if enc.len() % 8 != 0 { ok = false; }
    if !rt(data) { ok = false; }
    n = n + 1;
  }
  return assert(ok, "decode: remainders; encode length is 8*ceil(n/5)");
}

fn t5() -> TestResult {
  let empty = Vec[UInt8].new();
  var ok = streq(base32_encode(&empty), "");
  if !bytes_ok_empty(base32_decode("")) { ok = false; }
  if !base32_is_valid("") { ok = false; }
  if !rt(empty) { ok = false; }
  return assert(ok, "empty input: \"\" <-> Ok(empty), is_valid true");
}

fn t6() -> TestResult {
  var ok = dec_hex_is("my======", "66");
  if !dec_hex_is("mzxw6ytboi======", "666f6f626172") { ok = false; }
  if !dec_hex_is("MzXw6YtB", "666f6f6261") { ok = false; }
  if !dec_hex_is("A4wFc5u3", "072c51769b") { ok = false; }
  if !base32_is_valid("mzxw6===") { ok = false; }
  return assert(ok, "decode: lowercase and mixed case are accepted");
}

fn t7() -> TestResult {
  var ok = bytes_err_is(base32_decode("0"), "base32: invalid character");
  if !bytes_err_is(base32_decode("1"), "base32: invalid character") { ok = false; }
  if !bytes_err_is(base32_decode("8"), "base32: invalid character") { ok = false; }
  if !bytes_err_is(base32_decode("9"), "base32: invalid character") { ok = false; }
  if !bytes_err_is(base32_decode("MB!"), "base32: invalid character") { ok = false; }
  if !bytes_err_is(base32_decode("MZXW6 YTB"), "base32: invalid character") { ok = false; }
  if !bytes_err_is(base32_decode("MZXW6YTB-"), "base32: invalid character") { ok = false; }
  if !bytes_err_is(base32_decode("MZXW6YTB_"), "base32: invalid character") { ok = false; }
  if !bytes_err_is(base32_decode("MZXW6YTé"), "base32: invalid character") { ok = false; }
  return assert(ok, "decode: bytes outside A-Z/a-z/2-7/'=' are Err");
}

fn t8() -> TestResult {
  var ok = bytes_err_is(base32_decode("MY=====A"), "base32: invalid padding position");
  if !bytes_err_is(base32_decode("MZXW6YTB=B"), "base32: invalid padding position") { ok = false; }
  if !bytes_err_is(base32_decode("M=Y====="), "base32: invalid padding position") { ok = false; }
  if !bytes_err_is(base32_decode("=M======"), "base32: invalid padding position") { ok = false; }
  if !bytes_err_is(base32_decode("MY=====z"), "base32: invalid padding position") { ok = false; }
  if !bytes_err_is(base32_decode("MY===!="), "base32: invalid character") { ok = false; }
  return assert(ok, "decode: a digit after the first '=' is a padding-position error");
}

fn t9() -> TestResult {
  var ok = bytes_err_is(base32_decode("MY="), "base32: bad padding count");
  if !bytes_err_is(base32_decode("MY====="), "base32: bad padding count") { ok = false; }
  if !bytes_err_is(base32_decode("MY======="), "base32: bad padding count") { ok = false; }
  if !bytes_err_is(base32_decode("M======="), "base32: bad padding count") { ok = false; }
  if !bytes_err_is(base32_decode("========"), "base32: bad padding count") { ok = false; }
  if !bytes_err_is(base32_decode("MZXW6YTB="), "base32: bad padding count") { ok = false; }
  if !bytes_err_is(base32_decode("MZXW6YTBOI====="), "base32: bad padding count") { ok = false; }
  if !bytes_err_is(base32_decode("MZXW6YTB========="), "base32: bad padding count") { ok = false; }
  if !dec_hex_is("MY======", "66") { ok = false; }
  if !dec_hex_is("MZXW6===", "666f6f") { ok = false; }
  return assert(ok, "decode: wrong '=' count is Err, exact counts are Ok");
}

fn t10() -> TestResult {
  var ok = bytes_err_is(base32_decode("M"), "base32: truncated group");
  if !bytes_err_is(base32_decode("MZXW6"), "base32: truncated group") { ok = false; }
  if !bytes_err_is(base32_decode("MZXW6YQ"), "base32: truncated group") { ok = false; }
  if !bytes_err_is(base32_decode("MZXW6YTBOI"), "base32: truncated group") { ok = false; }
  if !dec_hex_is("MZXW6YTB", "666f6f6261") { ok = false; }
  if !dec_hex_is("MZXW6YTBOI======", "666f6f626172") { ok = false; }
  return assert(ok, "decode: unpadded partial groups are Err (padding required)");
}

fn t11() -> TestResult {
  var ok = bytes_err_is(base32_decode("MZ======"), "base32: non-canonical trailing bits");
  if !bytes_err_is(base32_decode("MZXR===="), "base32: non-canonical trailing bits") { ok = false; }
  if !bytes_err_is(base32_decode("MZXW7==="), "base32: non-canonical trailing bits") { ok = false; }
  if !bytes_err_is(base32_decode("MZXW6YR="), "base32: non-canonical trailing bits") { ok = false; }
  if !bytes_err_is(base32_decode("mz======"), "base32: non-canonical trailing bits") { ok = false; }
  if !dec_hex_is("MY======", "66") { ok = false; }
  if !dec_hex_is("MZXQ====", "666f") { ok = false; }
  if !dec_hex_is("MZXW6===", "666f6f") { ok = false; }
  if !dec_hex_is("MZXW6YQ=", "666f6f62") { ok = false; }
  return assert(ok, "decode: non-zero trailing bits are Err");
}

fn t12() -> TestResult {
  var ok = true;
  var n = 0;
  while n <= 8 {
    if !rt(seq_bytes(n)) { ok = false; }
    n = n + 1;
  }
  return assert(ok, "round-trip for 0..8 byte lengths");
}

fn t13() -> TestResult {
  var ok = enc_hex_is("ffffffffffffffffffffffffffffffff", "77777777777777777777777774======");
  if !rt(hb("ffffffffffffffffffffffffffffffff")) { ok = false; }
  var n = 0;
  while n <= 40 {
    let data = seq_bytes(n);
    let enc = base32_encode(&data);
    if enc.len() % 8 != 0 { ok = false; }
    let dec = base32_decode(enc);
    if !dec.is_ok { ok = false; }
    if dec.is_ok {
      if !bytes_equal(dec.value, data) { ok = false; }
    }
    if !base32_is_valid(enc) { ok = false; }
    n = n + 1;
  }
  return assert(ok, "round-trip for 0..40 bytes incl. all-0xFF high bytes");
}

fn t14() -> TestResult {
  let data = seq_bytes(64);
  let enc = base32_encode(&data);
  let want = "A4WFC5U3YDSQUL2UPGPMH2ANGJLXZIOG5MIDKWT7UTE64EZYLWBKPTHRCY5WBBNKZ72BSPTDRCW5F5Y4IFTIXMGV7IPUI2MOWPMP2IQ=";
  var ok = streq(enc, want);
  if enc.len() != 104 { ok = false; }
  if !base32_is_valid(enc) { ok = false; }
  let dec = base32_decode(enc);
  if !dec.is_ok { ok = false; }
  if dec.is_ok {
    if !bytes_equal(dec.value, data) { ok = false; }
  }
  return assert(ok, "64-byte buffer round-trip with pinned encoding");
}

fn t15() -> TestResult {
  var ok = enc_hex_is("ff", "74======");
  if !enc_hex_is("ffff", "777Q====") { ok = false; }
  if !enc_hex_is("ffffff", "77776===") { ok = false; }
  if !enc_hex_is("ffffffff", "777777Y=") { ok = false; }
  if !enc_hex_is("ffffffffff", "77777777") { ok = false; }
  if !enc_hex_is("ffffffffffffffffffffffffffffffff", "77777777777777777777777774======") { ok = false; }
  if !rt(hb("ff")) { ok = false; }
  if !rt(hb("ffff")) { ok = false; }
  if !rt(hb("ffffff")) { ok = false; }
  if !rt(hb("ffffffff")) { ok = false; }
  if !rt(hb("ffffffffff")) { ok = false; }
  if !rt(hb("00ff00ff00ff00ff00")) { ok = false; }
  return assert(ok, "high-byte 1..5 and 16 byte vectors are pinned and round-trip");
}

fn t16() -> TestResult {
  var ok = true;
  var b = 0;
  while b < 256 {
    var v = Vec[UInt8].new();
    v.push(b as UInt8);
    let e = base32_encode(&v);
    if e.len() != 8 { ok = false; }
    if !streq(string.str_slice(e, 2, 8), "======") { ok = false; }
    let d = base32_decode(e);
    if !d.is_ok { ok = false; }
    if d.is_ok && !bytes_equal(d.value, v) { ok = false; }
    b = b + 1;
  }
  return assert(ok, "every one-byte value encodes to 2 chars + 6 '=' and round-trips");
}

fn t17() -> TestResult {
  let data = hb("68c3a96c6c6f20f09f9880");
  var ok = streq(base32_encode(&data), "NDB2S3DMN4QPBH4YQA======");
  if !rt(data) { ok = false; }
  let mixed = hb("000000000102030400000000");
  if !streq(base32_encode(&mixed), "AAAAAAABAIBQIAAAAAAA====") { ok = false; }
  if !rt(mixed) { ok = false; }
  return assert(ok, "unicode and zero-run byte samples are pinned and round-trip");
}

fn t18() -> TestResult {
  let want = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
  var ok = streq(base32_alphabet(), want);
  if base32_alphabet().len() != 32 { ok = false; }
  if !enc_hex_is("0000000000", "AAAAAAAA") { ok = false; }
  if !bytes_is(base32_decode("AAAAAAAA"), "0000000000") { ok = false; }
  if !base32_is_valid("MZXW6===") { ok = false; }
  if base32_is_valid("MZXW6") { ok = false; }
  if base32_is_valid("MZ======") { ok = false; }
  if base32_is_valid("0") { ok = false; }
  if base32_is_valid("MY=====") { ok = false; }
  return assert(ok, "alphabet and is_valid mirror the decoder");
}

fn main() -> Int {
  io.println("=== xiom.base32 conformance tests ===");
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
    io.println("xiom.base32: all tests passed");
  } else {
    io.println("xiom.base32: tests failed");
  }
  return failed;
}
