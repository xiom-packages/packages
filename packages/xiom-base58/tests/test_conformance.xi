// XIOM -- xiom.base58 conformance tests (18 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API: encode/decode vectors over the Bitcoin
// alphabet, leading-zero handling, empty input, round-trips for lengths 0..8
// and a 64-byte buffer, invalid-character and invalid-UTF-8 errors, and
// base58_is_valid.
//
// All Str equality goes through str_compare (BUG 17 discipline: `==` on Str
// values read from a Vec lowers to a pointer comparison, so every comparison
// below is routed through streq). Expected byte vectors are built with the
// stdlib xiom.encoding.hex decoder, independent of the module under test; the
// pinned vectors (including the 32-byte Bitcoin-genesis-style sample) were
// cross-checked against an independent big-integer implementation.

module base58_tests
use xiom.io; use xiom.test; use xiom.base58;
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

// One-byte vector for value 0..255.
fn one_byte(b: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(b as UInt8);
  return v;
}

// True when encoding the bytes of `hexstr` yields `want`.
fn enc_hex_is(hexstr: Str, want: Str) -> Bool {
  let data = hb(hexstr);
  return streq(base58_encode(&data), want);
}

// True when decoding `s` yields exactly the bytes of `hexstr`.
fn dec_hex_is(s: Str, hexstr: Str) -> Bool {
  let r = base58_decode(s);
  if !r.is_ok {
    return false;
  }
  return bytes_equal(r.value, hb(hexstr));
}

// True when `r` is an Err whose message starts with "base58: ".
fn dec_err(r: Result[Vec[UInt8], Str]) -> Bool {
  if r.is_ok {
    return false;
  }
  let m = r.error;
  if m.len() < 8 {
    return false;
  }
  return streq(string.str_slice(m, 0, 8), "base58: ");
}

// True when `r` is Err with exactly the message `want`.
fn bytes_err_is(r: Result[Vec[UInt8], Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return streq(r.error, want);
}

// True when `r` is Ok(text) with text equal to `want`.
fn str_ok_is(r: Result[Str, Str], want: Str) -> Bool {
  if !r.is_ok {
    return false;
  }
  return streq(r.value, want);
}

// True when `r` is Err with exactly the message `want`.
fn str_err_is(r: Result[Str, Str], want: Str) -> Bool {
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
  let dec = base58_decode(base58_encode(&data));
  if !dec.is_ok { return false; }
  return bytes_equal(dec.value, data);
}

fn t1() -> TestResult {
  let empty = Vec[UInt8].new();
  var ok = streq(base58_encode(&empty), "");
  if !dec_hex_is("", "") { ok = false; }
  let d = base58_decode("");
  if !d.is_ok { ok = false; }
  if d.is_ok {
    if d.value.len() != 0 { ok = false; }
  }
  return assert(ok, "empty input: encode \"\" and decode Ok(empty)");
}

fn t2() -> TestResult {
  var ok = enc_hex_is("00", "1");
  if !dec_hex_is("1", "00") { ok = false; }
  return assert(ok, "{0} <-> \"1\"");
}

fn t3() -> TestResult {
  var ok = enc_hex_is("0000", "11");
  if !dec_hex_is("11", "0000") { ok = false; }
  if !enc_hex_is("000000", "111") { ok = false; }
  return assert(ok, "{0,0} <-> \"11\" and three zeros <-> \"111\"");
}

fn t4() -> TestResult {
  var ok = enc_hex_is("01", "2");
  if !dec_hex_is("2", "01") { ok = false; }
  if !enc_hex_is("ff", "5Q") { ok = false; }
  if !dec_hex_is("5Q", "ff") { ok = false; }
  if !enc_hex_is("0100", "5R") { ok = false; }
  if !enc_hex_is("3a", "21") { ok = false; }
  if !dec_hex_is("21", "3a") { ok = false; }
  return assert(ok, "{1} <-> \"2\" and other single-byte vectors");
}

fn t5() -> TestResult {
  let data = hb("48656c6c6f20576f726c64");
  var ok = streq(base58_encode(&data), "JxF12TrwUP45BMd");
  if !streq(base58_encode_str("Hello World"), "JxF12TrwUP45BMd") { ok = false; }
  if !str_ok_is(base58_decode_str("JxF12TrwUP45BMd"), "Hello World") { ok = false; }
  return assert(ok, "known vector: \"Hello World\" <-> \"JxF12TrwUP45BMd\"");
}

fn t6() -> TestResult {
  let genesis_hex = "000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f";
  let want = "111114VYJtj3yEDffZem7N3PkK563wkLZZ8RjKzcfY";
  let data = hb(genesis_hex);
  var ok = data.len() == 32;
  if !streq(base58_encode(&data), want) { ok = false; }
  if !dec_hex_is(want, genesis_hex) { ok = false; }
  if !rt(data) { ok = false; }
  return assert(ok, "bitcoin-genesis-style 32-byte sample is pinned");
}

fn t7() -> TestResult {
  var ok = true;
  var n = 0;
  while n <= 8 {
    if !rt(seq_bytes(n)) { ok = false; }
    n = n + 1;
  }
  return assert(ok, "round-trip for 0..8 byte lengths");
}

fn t8() -> TestResult {
  var ok = enc_hex_is("0001", "12");
  if !enc_hex_is("000001", "112") { ok = false; }
  if !enc_hex_is("00000001", "1112") { ok = false; }
  if !enc_hex_is("0000000001", "11112") { ok = false; }
  if !dec_hex_is("12", "0001") { ok = false; }
  if !dec_hex_is("11112", "0000000001") { ok = false; }
  return assert(ok, "leading zero bytes become leading '1' characters");
}

fn t9() -> TestResult {
  var ok = dec_err(base58_decode("0"));
  if !dec_err(base58_decode("O")) { ok = false; }
  if !dec_err(base58_decode("I")) { ok = false; }
  if !dec_err(base58_decode("l")) { ok = false; }
  if !dec_err(base58_decode("abc0")) { ok = false; }
  if !dec_err(base58_decode(" ")) { ok = false; }
  if !dec_err(base58_decode("+")) { ok = false; }
  if !dec_err(base58_decode("/")) { ok = false; }
  return assert(ok, "invalid characters 0/O/I/l/space/+/slash are Err");
}

fn t10() -> TestResult {
  var ok = bytes_err_is(base58_decode("0"), "base58: invalid character");
  if !bytes_err_is(base58_decode("O"), "base58: invalid character") { ok = false; }
  if !bytes_err_is(base58_decode("JxF12TrwUP45BMd0"), "base58: invalid character") { ok = false; }
  return assert(ok, "decode error message is \"base58: invalid character\"");
}

fn t11() -> TestResult {
  var ok = base58_is_valid("");
  if !base58_is_valid("1") { ok = false; }
  if !base58_is_valid("2") { ok = false; }
  if !base58_is_valid("z") { ok = false; }
  if !base58_is_valid("JxF12TrwUP45BMd") { ok = false; }
  if !base58_is_valid(base58_alphabet()) { ok = false; }
  return assert(ok, "is_valid accepts the alphabet and empty input");
}

fn t12() -> TestResult {
  var ok = !base58_is_valid("0");
  if base58_is_valid("O") { ok = false; }
  if base58_is_valid("I") { ok = false; }
  if base58_is_valid("l") { ok = false; }
  if base58_is_valid("!") { ok = false; }
  if base58_is_valid("ab c") { ok = false; }
  if base58_is_valid("é") { ok = false; }
  return assert(ok, "is_valid rejects non-alphabet bytes");
}

fn t13() -> TestResult {
  let text = "héllo 😀";
  let enc = base58_encode_str(text);
  var ok = streq(enc, "Syn5qUMrqzd8brf");
  if !streq(enc, base58_encode(&hb("68c3a96c6c6f20f09f9880"))) { ok = false; }
  if !str_ok_is(base58_decode_str(enc), text) { ok = false; }
  if !str_ok_is(base58_decode_str(""), "") { ok = false; }
  return assert(ok, "encode_str/decode_str round-trip with unicode");
}

fn t14() -> TestResult {
  let want = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
  var ok = streq(base58_alphabet(), want);
  if base58_alphabet().len() != 58 { ok = false; }
  return assert(ok, "alphabet is the 58-character Bitcoin alphabet");
}

fn t15() -> TestResult {
  let alpha = base58_alphabet();
  var ok = true;
  var i = 0;
  while i < 58 {
    let ch = string.str_slice(alpha, i, i + 1);
    if !streq(base58_encode(&one_byte(i)), ch) { ok = false; }
    let r = base58_decode(ch);
    if !r.is_ok { ok = false; }
    if r.is_ok {
      if !bytes_equal(r.value, one_byte(i)) { ok = false; }
    }
    i = i + 1;
  }
  return assert(ok, "every one-byte value 0..57 maps to its alphabet char");
}

fn t16() -> TestResult {
  var ok = enc_hex_is("00ff", "15Q");
  if !dec_hex_is("15Q", "00ff") { ok = false; }
  if !enc_hex_is("ffff", "LUv") { ok = false; }
  if !dec_hex_is("LUv", "ffff") { ok = false; }
  if !enc_hex_is("010203", "Ldp") { ok = false; }
  if !dec_hex_is("Ldp", "010203") { ok = false; }
  return assert(ok, "multi-byte vectors with leading zero and high bytes");
}

fn t17() -> TestResult {
  var ok = str_err_is(base58_decode_str("0"), "base58: invalid character");
  if !str_err_is(base58_decode_str("3D"), "base58: invalid UTF-8") { ok = false; }
  if !str_err_is(base58_decode_str("4N"), "base58: invalid UTF-8") { ok = false; }
  if !str_err_is(base58_decode_str("5Q"), "base58: invalid UTF-8") { ok = false; }
  if !str_err_is(base58_decode_str("AnC"), "base58: invalid UTF-8") { ok = false; }
  return assert(ok, "decode_str rejects invalid base58 and invalid UTF-8");
}

fn t18() -> TestResult {
  let data = seq_bytes(64);
  let enc = base58_encode(&data);
  var ok = streq(enc, "9KSiV2hovo6nC4yQD2LjwhaxrdNeqfNamM5RWSsZ8BrM7mguAmXP5dzvXA95ZkmWZDeWLrxnwEjSzG3k4tj36iM");
  if !base58_is_valid(enc) { ok = false; }
  let dec = base58_decode(enc);
  if !dec.is_ok { ok = false; }
  if dec.is_ok {
    if !bytes_equal(dec.value, data) { ok = false; }
  }
  return assert(ok, "64-byte buffer round-trip with pinned encoding");
}

fn main() -> Int {
  io.println("=== xiom.base58 conformance tests ===");
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
    io.println("xiom.base58: all tests passed");
  } else {
    io.println("xiom.base58: tests failed");
  }
  return failed;
}
