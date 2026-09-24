// XIOM -- xiom.ascii85 conformance tests (20 checks)
// Port task: prove the greenfield xiom.ascii85 module against Adobe ASCII85.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API: full-group encode/decode vectors (Wikipedia and
// Adobe examples, "Man " -> "9jqo^", "sure" -> "F*2M7", "Hello, World!"),
// partial groups ("M" -> "9`", "Ma" -> "9jn", "Man" -> "9jqo"), the 'z'
// zero-group shorthand and its boundary rule, ignored whitespace, optional
// "<~"/"~>" delimiters, empty input, round-trips for lengths 0..8 plus a
// pinned 64-byte buffer, exhaustive one- and two-byte round-trips, invalid
// characters, the single-leftover-character error, 32-bit overflow (with
// "s8W-!" = 0xFFFFFFFF as the boundary vector), a85_is_valid and
// a85_max_decoded_len.
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every comparison
// below is routed through streq instead of `==`. Expected byte vectors are
// built with the stdlib xiom.encoding.hex decoder, independent of the module
// under test; the pinned vectors (including the 64-byte sample and the
// overflow boundary) were cross-checked against an independent ASCII85
// implementation.

module ascii85_tests
use xiom.io; use xiom.test; use xiom.ascii85;
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

// UTF-8 bytes of a Str (test-local; the module under test has no Str helper).
fn sb(s: Str) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < s.len() {
    v.push(string.byte_at(s, i));
    i = i + 1;
  }
  return v;
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

// True when r is an Err whose message starts with "ascii85: ".
fn bytes_err(r: Result[Vec[UInt8], Str]) -> Bool {
  if r.is_ok {
    return false;
  }
  let m = r.error;
  if m.len() < 9 {
    return false;
  }
  return streq(string.str_slice(m, 0, 9), "ascii85: ");
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
  let dec = a85_decode(a85_encode(&data));
  if !dec.is_ok { return false; }
  return bytes_equal(dec.value, data);
}

fn t1() -> TestResult {
  var ok = streq(a85_encode(&sb("")), "");
  if !streq(a85_encode(&sb("Man ")), "9jqo^") { ok = false; }
  if !streq(a85_encode(&sb("sure")), "F*2M7") { ok = false; }
  if !streq(a85_encode(&sb("Hello, World!")), "87cURD_*#4DfTZ)+T") { ok = false; }
  return assert(ok, "encode: Wikipedia/Adobe full-group vectors");
}

fn t2() -> TestResult {
  var ok = streq(a85_encode(&hb("4d")), "9`");
  if !streq(a85_encode(&hb("4d61")), "9jn") { ok = false; }
  if !streq(a85_encode(&hb("4d616e")), "9jqo") { ok = false; }
  if !streq(a85_encode(&hb("ff")), "rr") { ok = false; }
  if !streq(a85_encode(&hb("ffff")), "s8N") { ok = false; }
  if !streq(a85_encode(&hb("ffffff")), "s8W*") { ok = false; }
  return assert(ok, "encode: partial groups become n+1 characters");
}

fn t3() -> TestResult {
  var ok = streq(a85_encode(&hb("00")), "!!");
  if !streq(a85_encode(&hb("0000")), "!!!") { ok = false; }
  if !streq(a85_encode(&hb("000000")), "!!!!") { ok = false; }
  if !streq(a85_encode(&hb("00000000")), "z") { ok = false; }
  if !streq(a85_encode(&hb("0000000000000000")), "zz") { ok = false; }
  if !streq(a85_encode(&hb("00000001")), "!!!!\"") { ok = false; }
  if !streq(a85_encode(&hb("ffffffff")), "s8W-!") { ok = false; }
  return assert(ok, "encode: all-zero groups and 0x00000001/0xFFFFFFFF");
}

fn t4() -> TestResult {
  var ok = bytes_is(a85_decode("9jqo^"), "4d616e20");
  if !bytes_is(a85_decode("F*2M7"), "73757265") { ok = false; }
  if !bytes_is(a85_decode("87cURD_*#4DfTZ)+T"), "48656c6c6f2c20576f726c6421") { ok = false; }
  if !bytes_is(a85_decode("!!!!!"), "00000000") { ok = false; }
  if !bytes_is(a85_decode("!!!!\""), "00000001") { ok = false; }
  if !bytes_is(a85_decode("s8W-!"), "ffffffff") { ok = false; }
  return assert(ok, "decode: full-group vectors incl. 0xFFFFFFFF");
}

fn t5() -> TestResult {
  var ok = bytes_is(a85_decode("9`"), "4d");
  if !bytes_is(a85_decode("9j"), "4d") { ok = false; }
  if !bytes_is(a85_decode("9jn"), "4d61") { ok = false; }
  if !bytes_is(a85_decode("9jqo"), "4d616e") { ok = false; }
  if !bytes_is(a85_decode("rr"), "ff") { ok = false; }
  if !bytes_is(a85_decode("s8N"), "ffff") { ok = false; }
  if !bytes_is(a85_decode("s8W*"), "ffffff") { ok = false; }
  if !bytes_is(a85_decode("9`P.n"), "4d000000") { ok = false; }
  return assert(ok, "decode: partial groups of 2..4 chars");
}

fn t6() -> TestResult {
  var ok = bytes_is(a85_decode("z"), "00000000");
  if !bytes_is(a85_decode("zz"), "0000000000000000") { ok = false; }
  if !bytes_is(a85_decode("z9jqo^"), "000000004d616e20") { ok = false; }
  if !bytes_is(a85_decode("9jqo^z"), "4d616e2000000000") { ok = false; }
  if !bytes_is(a85_decode("z!<N?+z"), "000000000102030400000000") { ok = false; }
  if !bytes_is(a85_decode("<~z~>"), "00000000") { ok = false; }
  return assert(ok, "decode: z is four zero bytes at a group boundary");
}

fn t7() -> TestResult {
  var ok = bytes_err_is(a85_decode("9jzqo"), "ascii85: z inside group");
  if !bytes_err_is(a85_decode("9z"), "ascii85: z inside group") { ok = false; }
  if !bytes_err_is(a85_decode("!!!!z"), "ascii85: z inside group") { ok = false; }
  if !bytes_err_is(a85_decode("z9jz"), "ascii85: z inside group") { ok = false; }
  if !bytes_err_is(a85_decode("9jqz^"), "ascii85: z inside group") { ok = false; }
  return assert(ok, "decode: misplaced z is Err");
}

fn t8() -> TestResult {
  var ok = bytes_is(a85_decode(" 9jqo^ "), "4d616e20");
  if !bytes_is(a85_decode("9j qo^"), "4d616e20") { ok = false; }
  if !bytes_is(a85_decode("9jqo^\t\n"), "4d616e20") { ok = false; }
  let ws = Str::from_utf8(hb("090b0c0d20"));
  if !bytes_is(a85_decode(ws + "9jqo^" + ws), "4d616e20") { ok = false; }
  return assert(ok, "decode: ASCII whitespace is ignored anywhere");
}

fn t9() -> TestResult {
  var ok = bytes_is(a85_decode("<~9jqo^~>"), "4d616e20");
  if !bytes_is(a85_decode("9jqo^~>"), "4d616e20") { ok = false; }
  if !bytes_is(a85_decode("<~9jqo^"), "4d616e20") { ok = false; }
  if !bytes_is(a85_decode("  <~\t9jqo^~>\r\n"), "4d616e20") { ok = false; }
  if !bytes_ok_empty(a85_decode("")) { ok = false; }
  if !bytes_ok_empty(a85_decode("~>")) { ok = false; }
  if !bytes_ok_empty(a85_decode("<~")) { ok = false; }
  if !bytes_ok_empty(a85_decode("   ")) { ok = false; }
  return assert(ok, "decode: optional <~ ~> delimiters and empty input");
}

fn t10() -> TestResult {
  var ok = true;
  var n = 0;
  while n <= 8 {
    if !rt(seq_bytes(n)) { ok = false; }
    n = n + 1;
  }
  return assert(ok, "round-trip for 0..8 byte lengths");
}

fn t11() -> TestResult {
  let s8 = seq_bytes(8);
  var ok = streq(a85_encode(&s8), "#:r_qS&\"+m");
  if !rt(s8) { ok = false; }
  let mixed = hb("000000000102030400000000");
  if !streq(a85_encode(&mixed), "z!<N?+z") { ok = false; }
  if !rt(mixed) { ok = false; }
  let empty = Vec[UInt8].new();
  if !streq(a85_encode(&empty), "") { ok = false; }
  return assert(ok, "encode: pinned 8-byte and zero-group vectors with round-trips");
}

fn t12() -> TestResult {
  let data = seq_bytes(64);
  let enc = a85_encode(&data);
  var ok = streq(enc, "#:r_qS&\"+m03!4g_rqOb=+$^]lOYpWJ#(3S'0'9LVp+ZH4(*cBch&)=@u.88pDcJ2Mm1b.+%0h'Ze54#");
  if enc.len() != 80 { ok = false; }
  if !a85_is_valid(enc) { ok = false; }
  let dec = a85_decode(enc);
  if !dec.is_ok { ok = false; }
  if dec.is_ok {
    if !bytes_equal(dec.value, data) { ok = false; }
  }
  return assert(ok, "64-byte buffer round-trip with pinned encoding");
}

fn t13() -> TestResult {
  var ok = bytes_err_is(a85_decode("9jqo~"), "ascii85: invalid character");
  if !bytes_err_is(a85_decode("9jqo{"), "ascii85: invalid character") { ok = false; }
  if !bytes_err(a85_decode("9jqo|")) { ok = false; }
  if !bytes_err(a85_decode("9jqo}")) { ok = false; }
  if !bytes_err(a85_decode("9jqoé")) { ok = false; }
  let ctrl = Str::from_utf8(hb("0f"));
  if !bytes_err_is(a85_decode(ctrl + "9jqo^"), "ascii85: invalid character") { ok = false; }
  return assert(ok, "decode: bytes outside '!'..'u' are Err");
}

fn t14() -> TestResult {
  var ok = bytes_err_is(a85_decode("9"), "ascii85: incomplete group");
  if !bytes_err_is(a85_decode("z9"), "ascii85: incomplete group") { ok = false; }
  if !bytes_err_is(a85_decode("9jqo^9"), "ascii85: incomplete group") { ok = false; }
  if !bytes_err_is(a85_decode("zz!"), "ascii85: incomplete group") { ok = false; }
  if !bytes_is(a85_decode("9j"), "4d") { ok = false; }
  return assert(ok, "decode: a single leftover character is Err");
}

fn t15() -> TestResult {
  var ok = bytes_err_is(a85_decode("uuuuu"), "ascii85: value overflows 32 bits");
  if !bytes_err_is(a85_decode("s8W-\""), "ascii85: value overflows 32 bits") { ok = false; }
  if !bytes_err_is(a85_decode("s8W-"), "ascii85: value overflows 32 bits") { ok = false; }
  if !bytes_err_is(a85_decode("uuuu"), "ascii85: value overflows 32 bits") { ok = false; }
  if !bytes_is(a85_decode("s8W-!"), "ffffffff") { ok = false; }
  return assert(ok, "decode: values above 0xFFFFFFFF are Err");
}

fn t16() -> TestResult {
  var ok = a85_is_valid("");
  if !a85_is_valid("z") { ok = false; }
  if !a85_is_valid("9jqo^") { ok = false; }
  if !a85_is_valid("<~9jqo^~>") { ok = false; }
  if !a85_is_valid(" 9jqo^ ") { ok = false; }
  if !a85_is_valid("!!!!\"") { ok = false; }
  if a85_is_valid("9") { ok = false; }
  if a85_is_valid("9jzqo") { ok = false; }
  if a85_is_valid("uuuuu") { ok = false; }
  if a85_is_valid("9jqo~") { ok = false; }
  return assert(ok, "is_valid mirrors decode acceptance");
}

fn t17() -> TestResult {
  var ok = a85_max_decoded_len(0) == 0;
  if a85_max_decoded_len(-7) != 0 { ok = false; }
  if a85_max_decoded_len(1) != 1 { ok = false; }
  if a85_max_decoded_len(2) != 2 { ok = false; }
  if a85_max_decoded_len(3) != 3 { ok = false; }
  if a85_max_decoded_len(4) != 4 { ok = false; }
  if a85_max_decoded_len(5) != 4 { ok = false; }
  if a85_max_decoded_len(6) != 5 { ok = false; }
  if a85_max_decoded_len(7) != 6 { ok = false; }
  if a85_max_decoded_len(8) != 7 { ok = false; }
  if a85_max_decoded_len(64) != 52 { ok = false; }
  if a85_max_decoded_len(80) != 64 { ok = false; }
  return assert(ok, "max_decoded_len: ceil(chars*4/5) upper bound");
}

fn t18() -> TestResult {
  let data = hb("68c3a96c6c6f20f09f9880");
  var ok = streq(a85_encode(&data), "BZ$fcCi:HcT9t-");
  if !rt(data) { ok = false; }
  return assert(ok, "unicode UTF-8 bytes round-trip");
}

fn t19() -> TestResult {
  var ok = true;
  var b = 0;
  while b < 256 {
    var v = Vec[UInt8].new();
    v.push(b as UInt8);
    let e = a85_encode(&v);
    if e.len() != 2 { ok = false; }
    let d = a85_decode(e);
    if !d.is_ok { ok = false; }
    if d.is_ok && !bytes_equal(d.value, v) { ok = false; }
    b = b + 1;
  }
  return assert(ok, "every one-byte value encodes to 2 chars and round-trips");
}

fn t20() -> TestResult {
  var ok = true;
  var b = 0;
  while b < 256 {
    var v = Vec[UInt8].new();
    v.push(b as UInt8);
    v.push(128u8);
    let e = a85_encode(&v);
    if e.len() != 3 { ok = false; }
    let d = a85_decode(e);
    if !d.is_ok { ok = false; }
    if d.is_ok && !bytes_equal(d.value, v) { ok = false; }
    b = b + 1;
  }
  var n = 0;
  while n <= 40 {
    let data = seq_bytes(n);
    let enc = a85_encode(&data);
    let dec = a85_decode(enc);
    if !dec.is_ok { ok = false; }
    if dec.is_ok {
      if dec.value.len() > a85_max_decoded_len(enc.len()) { ok = false; }
      if !bytes_equal(dec.value, data) { ok = false; }
    }
    n = n + 1;
  }
  return assert(ok, "2-byte round-trips and the 0..40-byte size bound");
}

fn main() -> Int {
  io.println("=== xiom.ascii85 conformance tests ===");
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
    io.println("xiom.ascii85: all tests passed");
  } else {
    io.println("xiom.ascii85: tests failed");
  }
  return failed;
}
