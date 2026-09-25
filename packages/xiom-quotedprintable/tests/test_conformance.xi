// XIOM -- xiom.quotedprintable conformance tests (20 checks)
// Port task: prove the pure-XIOM quoted-printable codec against the RFC 2045
// section 6.7 rules documented in SPEC.md.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Coverage map: see SPEC.md section 8. Every check is a named
// assert(cond, "name") call, one fn per check, and main returns the failure
// count (0 = green).
//
// BUG 17 discipline: all Str equality goes through
// xiom.string.compare.str_compare (never `==`, which lowers to a pointer
// comparison for Str values read from a Vec), and every Vec[UInt8] element
// read is widened with `(x as Int) & 0xFF` before use.

module quotedprintable_tests
use xiom.io; use xiom.test; use xiom.quotedprintable;
use xiom.string; use xiom.string.compare;

// --------------------------------------------------
//  Helpers
// --------------------------------------------------

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// Raw bytes of a Str (one byte per index).
fn sb(s: Str) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < s.len() {
    v.push(string.byte_at(s, i));
    i = i + 1;
  }
  return v;
}

// Byte i of v widened to Int space (0..255).
fn vbyte(v: Vec[UInt8], i: Int) -> Int {
  return (v[i] as Int) & 0xFF;
}

fn bytes_equal(a: Vec[UInt8], b: Vec[UInt8]) -> Bool {
  if a.len() != b.len() {
    return false;
  }
  var i = 0;
  while i < a.len() {
    if vbyte(a, i) != vbyte(b, i) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// Encoded bytes of a Str literal.
fn enc_bytes(s: Str) -> Vec[UInt8] {
  let data = sb(s);
  return qp_encode(&data);
}

// Encoded form of a Str literal as a Str (the encoder emits no NUL bytes).
fn enc_str(s: Str) -> Str {
  return Str::from_utf8(enc_bytes(s));
}

// Decode through the byte API (bound local; never & of a call result).
fn dec_of(s: Str) -> Result[Vec[UInt8], Str] {
  let data = sb(s);
  return qp_decode(&data);
}

// Decode through the text wrapper.
fn dec_str(s: Str) -> Result[Str, Str] {
  return qp_decode_str(s);
}

// Validate through the byte API.
fn valid_of(s: Str) -> Bool {
  let data = sb(s);
  return qp_is_valid(&data);
}

// True when r is Ok(bytes) equal to the bytes of `want`.
fn bytes_ok_is(r: Result[Vec[UInt8], Str], want: Str) -> Bool {
  if !r.is_ok {
    return false;
  }
  return bytes_equal(r.value, sb(want));
}

// True when r is Ok(text) equal to `want`.
fn str_ok_is(r: Result[Str, Str], want: Str) -> Bool {
  if !r.is_ok {
    return false;
  }
  return streq(r.value, want);
}

// True when r is Err with exactly the message `want`.
fn err_is(r: Result[Vec[UInt8], Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return streq(r.error, want);
}

// True when r is Err with exactly the message `want` (Str result).
fn str_err_is(r: Result[Str, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return streq(r.error, want);
}

// Deterministic byte sequence of length n; covers 0x00 and bytes >= 0x80.
fn seq_bytes(n: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < n {
    v.push(((i * 37 + 7) % 256) as UInt8);
    i = i + 1;
  }
  return v;
}

// A vector of `count` copies of byte `b`.
fn repeat_byte(b: Int, count: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < count {
    v.push(b as UInt8);
    i = i + 1;
  }
  return v;
}

// True when encode -> decode returns the same bytes.
fn rt_ok(data: Vec[UInt8]) -> Bool {
  let enc = qp_encode(&data);
  let dec = qp_decode(&enc);
  if !dec.is_ok {
    return false;
  }
  return bytes_equal(dec.value, data);
}

// True when no physical line of `v` exceeds `limit` characters, every raw
// CRLF is well-formed, and every CRLF is a soft break marked by a preceding
// '=' (the only line break qp_encode ever emits).
fn lines_within(v: Vec[UInt8], limit: Int) -> Bool {
  var i = 0;
  var cur = 0;
  while i < v.len() {
    let b = vbyte(v, i);
    if b == 13 {
      if i + 1 >= v.len() {
        return false;
      }
      if vbyte(v, i + 1) != 10 {
        return false;
      }
      if cur > limit {
        return false;
      }
      if i == 0 {
        return false;
      }
      if vbyte(v, i - 1) != 61 {
        return false;
      }
      cur = 0;
      i = i + 2;
    } elif b == 10 {
      return false;
    } else {
      cur = cur + 1;
      i = i + 1;
    }
  }
  if cur > limit {
    return false;
  }
  return true;
}

// --------------------------------------------------
//  Checks
// --------------------------------------------------

fn t1() -> TestResult {
  let empty = Vec[UInt8].new();
  let enc = qp_encode(&empty);
  var ok = enc.len() == 0;
  if !streq(enc_str(""), "") { ok = false; }
  if !bytes_ok_is(qp_decode(&empty), "") { ok = false; }
  if !str_ok_is(dec_str(""), "") { ok = false; }
  return assert(ok, "empty input: encode empty, decode Ok(empty)");
}

fn t2() -> TestResult {
  let s = "Hello, world! 0123456789";
  var ok = streq(enc_str(s), s);
  if !str_ok_is(dec_str(enc_str(s)), s) { ok = false; }
  return assert(ok, "ascii text: printable bytes pass through unchanged");
}

fn t3() -> TestResult {
  var ok = streq(enc_str("a=b"), "a=3Db");
  var raw = Vec[UInt8].new();
  raw.push(0 as UInt8);
  raw.push(8 as UInt8);
  raw.push(11 as UInt8);
  raw.push(12 as UInt8);
  raw.push(31 as UInt8);
  raw.push(127 as UInt8);
  raw.push(128 as UInt8);
  raw.push(255 as UInt8);
  let enc = qp_encode(&raw);
  let encs = Str::from_utf8(enc);
  if !streq(encs, "=00=08=0B=0C=1F=7F=80=FF") { ok = false; }
  return assert(ok, "escapes: '=' and non-printables become =XX uppercase");
}

fn t4() -> TestResult {
  let s = "a\tb c !~";
  var ok = streq(enc_str(s), s);
  // A leading TAB before a literal byte stays literal; the same TAB alone
  // (last byte of the input) is escaped, which t5 pins separately.
  var mixed = Vec[UInt8].new();
  mixed.push(9 as UInt8);
  mixed.push(65 as UInt8);
  if !streq(Str::from_utf8(qp_encode(&mixed)), "\tA") { ok = false; }
  return assert(ok, "literal: TAB and space stay literal when not line-final");
}

fn t5() -> TestResult {
  var ok = streq(enc_str("a "), "a=20");
  if !streq(enc_str("a\t"), "a=09") { ok = false; }
  if !streq(enc_str(" "), "=20") { ok = false; }
  if !streq(enc_str("  "), " =20") { ok = false; }
  if !streq(enc_str("a  b"), "a  b") { ok = false; }
  return assert(ok, "trailing whitespace: line-final space/TAB are escaped");
}

fn t6() -> TestResult {
  let s = "café ✓";
  var ok = streq(enc_str(s), "caf=C3=A9 =E2=9C=93");
  let ev = enc_bytes(s);
  var i = 0;
  while i < ev.len() {
    if vbyte(ev, i) > 126 { ok = false; }
    i = i + 1;
  }
  if !str_ok_is(dec_str(enc_str(s)), s) { ok = false; }
  return assert(ok, "non-ASCII: every byte >= 0x80 is escaped, round-trips");
}

fn t7() -> TestResult {
  let a75 = repeat_byte(97, 75);
  let e75 = qp_encode(&a75);
  var ok = e75.len() == 75;
  var j = 0;
  while j < e75.len() {
    if vbyte(e75, j) != 97 { ok = false; }
    j = j + 1;
  }
  let a76 = repeat_byte(97, 76);
  let e76 = qp_encode(&a76);
  if e76.len() != 79 { ok = false; }
  if e76.len() == 79 {
    if vbyte(e76, 75) != 61 { ok = false; }
    if vbyte(e76, 76) != 13 { ok = false; }
    if vbyte(e76, 77) != 10 { ok = false; }
    if vbyte(e76, 78) != 97 { ok = false; }
  }
  if !lines_within(e75, qp_line_limit()) { ok = false; }
  if !lines_within(e76, qp_line_limit()) { ok = false; }
  return assert(ok, "line limit: 75 bytes stay on one line, 76 wrap");
}

fn t8() -> TestResult {
  let data = seq_bytes(200);
  let enc = qp_encode(&data);
  var ok = lines_within(enc, qp_line_limit());
  if enc.len() <= data.len() { ok = false; }
  let dec = qp_decode(&enc);
  if !dec.is_ok { ok = false; }
  if dec.is_ok {
    if !bytes_equal(dec.value, data) { ok = false; }
  }
  return assert(ok, "long binary input: no line over 76, soft-break-only");
}

fn t9() -> TestResult {
  var ok = bytes_ok_is(dec_of("=41=42=43"), "ABC");
  if !bytes_ok_is(dec_of("=6a=4A"), "jJ") { ok = false; }
  if !str_ok_is(dec_str("=41"), "A") { ok = false; }
  let pair = dec_of("=00=FF");
  if !pair.is_ok { ok = false; }
  if pair.is_ok {
    if pair.value.len() != 2 { ok = false; }
    if vbyte(pair.value, 0) != 0 { ok = false; }
    if vbyte(pair.value, 1) != 255 { ok = false; }
  }
  return assert(ok, "decode: hex pairs, lowercase accepted, 0x00/0xFF exact");
}

fn t10() -> TestResult {
  var ok = str_ok_is(dec_str("ab=\r\ncd"), "abcd");
  if !str_ok_is(dec_str("a=\r\n=\r\nb"), "ab") { ok = false; }
  if !str_ok_is(dec_str("ab=\r\n"), "ab") { ok = false; }
  return assert(ok, "decode: =CRLF soft breaks are removed");
}

fn t11() -> TestResult {
  var ok = str_ok_is(dec_str("a\r\nb"), "a\r\nb");
  if !bytes_ok_is(dec_of("=0D=0A"), "\r\n") { ok = false; }
  if !str_ok_is(dec_str("a\r\n"), "a\r\n") { ok = false; }
  return assert(ok, "decode: raw CRLF hard break and =0D=0A yield CR LF");
}

fn t12() -> TestResult {
  let s = "a b\tc~!";
  var ok = str_ok_is(dec_str(s), s);
  if !str_ok_is(dec_str(" trailing "), " trailing ") { ok = false; }
  return assert(ok, "decode: printable bytes, space and TAB are literal");
}

fn t13() -> TestResult {
  let w = "quotedprintable: stray equals";
  var ok = err_is(dec_of("a=x"), w);
  if !err_is(dec_of("=!2"), w) { ok = false; }
  if !err_is(dec_of("=%"), w) { ok = false; }
  if !err_is(dec_of("==41"), w) { ok = false; }
  if !str_err_is(dec_str("a=%b"), w) { ok = false; }
  return assert(ok, "error: '=' not starting an escape is a stray equals");
}

fn t14() -> TestResult {
  let w = "quotedprintable: invalid hex digit";
  var ok = err_is(dec_of("=4G"), w);
  if !err_is(dec_of("=1Z2"), w) { ok = false; }
  if !err_is(dec_of("=2g"), w) { ok = false; }
  if !str_err_is(dec_str("=41=4G"), w) { ok = false; }
  return assert(ok, "error: bad second hex digit is invalid hex digit");
}

fn t15() -> TestResult {
  let w = "quotedprintable: truncated escape at EOF";
  var ok = err_is(dec_of("abc="), w);
  if !err_is(dec_of("abc=4"), w) { ok = false; }
  if !err_is(dec_of("=A"), w) { ok = false; }
  if !str_err_is(dec_str("="), w) { ok = false; }
  return assert(ok, "error: escaped input ending mid-escape is truncated");
}

fn t16() -> TestResult {
  let w = "quotedprintable: invalid line break";
  var ok = err_is(dec_of("a\nb"), w);
  if !err_is(dec_of("a\rb"), w) { ok = false; }
  if !err_is(dec_of("=\n"), w) { ok = false; }
  if !err_is(dec_of("=\r"), w) { ok = false; }
  if !err_is(dec_of("a\r"), w) { ok = false; }
  if !err_is(dec_of("=\rX"), w) { ok = false; }
  return assert(ok, "error: bare CR/LF and malformed soft breaks are invalid");
}

fn t17() -> TestResult {
  var data = Vec[UInt8].new();
  var i = 0;
  while i < 256 {
    data.push(i as UInt8);
    i = i + 1;
  }
  let enc = qp_encode(&data);
  var ok = lines_within(enc, qp_line_limit());
  let dec = qp_decode(&enc);
  if !dec.is_ok { ok = false; }
  if dec.is_ok {
    if !bytes_equal(dec.value, data) { ok = false; }
  }
  return assert(ok, "round-trip: all 256 byte values");
}

fn t18() -> TestResult {
  var ok = true;
  var n = 0;
  while n <= 8 {
    if !rt_ok(seq_bytes(n)) { ok = false; }
    n = n + 1;
  }
  if !rt_ok(seq_bytes(257)) { ok = false; }
  return assert(ok, "round-trip: lengths 0..8 and 257");
}

fn t19() -> TestResult {
  let s = "Grüße, 世界! line two";
  var ok = str_ok_is(dec_str(enc_str(s)), s);
  if !streq(enc_str(""), "") { ok = false; }
  var long = "";
  var i = 0;
  while i < 30 {
    long = long + "0123456789";
    i = i + 1;
  }
  let enc = enc_str(long);
  if enc.len() <= long.len() { ok = false; }
  if !str_ok_is(dec_str(enc), long) { ok = false; }
  return assert(ok, "text wrapper: encode_str/decode_str round-trip");
}

fn t20() -> TestResult {
  var ok = qp_line_limit() == 76;
  if !valid_of("a=3Db=\r\nc") { ok = false; }
  if !valid_of("") { ok = false; }
  if valid_of("a=x") { ok = false; }
  if valid_of("=\r") { ok = false; }
  return assert(ok, "is_valid accepts well-formed input; line limit is 76");
}

// --------------------------------------------------
//  Harness
// --------------------------------------------------

fn main() -> Int {
  io.println("=== xiom.quotedprintable conformance tests ===");
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
    io.println("xiom.quotedprintable: all tests passed");
  } else {
    io.println("xiom.quotedprintable: tests failed");
  }
  return failed;
}
