// XIOM -- xiom.radix conformance tests (20 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API: the 36-character alphabet, digit classification
// for 0-9/a-z/A-Z and non-digits (including bytes >= 0x80), baselines in
// bases 2/8/10/16/36, uppercase input, optional '+'/'-' signs, leading
// zeros, canonical emit, the INT_MAX/INT_MIN boundaries in several bases,
// positive and negative overflow, invalid digits with their 0-based byte
// position, base-out-of-range, empty input and lone sign, round-trips across
// base pairs, base-to-base conversion, radix_is_valid and an exhaustive
// single-digit sweep over every base.
//
// All Str equality goes through str_compare (BUG 17 discipline: `==` on Str
// values read from a Vec lowers to a pointer comparison, so every comparison
// below is routed through streq). The big-value pins (INT_MAX/INT_MIN in
// bases 2/8/10/16/36) were cross-checked against an independent big-integer
// implementation.

module radix_tests
use xiom.io; use xiom.test; use xiom.radix;
use xiom.string; use xiom.string.compare;
use xiom.core;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// True when r is Ok(v) with v == want.
fn int_ok_is(r: Result[Int, Str], want: Int) -> Bool {
  if !r.is_ok { return false; }
  return r.value == want;
}

// True when r is Err with exactly the message `want`.
fn int_err_is(r: Result[Int, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return streq(r.error, want);
}

// True when r is Ok(text) with text equal to `want`.
fn str_ok_is(r: Result[Str, Str], want: Str) -> Bool {
  if !r.is_ok { return false; }
  return streq(r.value, want);
}

// True when r is Err with exactly the message `want`.
fn str_err_is(r: Result[Str, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return streq(r.error, want);
}

// True when format -> parse returns the original value.
fn rt_int(n: Int, base: Int) -> Bool {
  let f = radix_from_int(n, base);
  if !f.is_ok { return false; }
  let p = radix_to_int(f.value, base);
  if !p.is_ok { return false; }
  return p.value == n;
}

fn t1() -> TestResult {
  let want = "0123456789abcdefghijklmnopqrstuvwxyz";
  var ok = streq(radix_alphabet(), want);
  if radix_alphabet().len() != 36 { ok = false; }
  if !streq(string.str_slice(radix_alphabet(), 0, 1), "0") { ok = false; }
  if !streq(string.str_slice(radix_alphabet(), 9, 10), "9") { ok = false; }
  if !streq(string.str_slice(radix_alphabet(), 10, 11), "a") { ok = false; }
  if !streq(string.str_slice(radix_alphabet(), 35, 36), "z") { ok = false; }
  return assert(ok, "alphabet is the 36-character lowercase set");
}

fn t2() -> TestResult {
  var ok = radix_digit_value(string.byte_at("0", 0)) == 0;
  if radix_digit_value(string.byte_at("9", 0)) != 9 { ok = false; }
  if radix_digit_value(string.byte_at("a", 0)) != 10 { ok = false; }
  if radix_digit_value(string.byte_at("f", 0)) != 15 { ok = false; }
  if radix_digit_value(string.byte_at("z", 0)) != 35 { ok = false; }
  if radix_digit_value(string.byte_at("A", 0)) != 10 { ok = false; }
  if radix_digit_value(string.byte_at("F", 0)) != 15 { ok = false; }
  if radix_digit_value(string.byte_at("Z", 0)) != 35 { ok = false; }
  if radix_digit_value(string.byte_at("!", 0)) != 0 - 1 { ok = false; }
  if radix_digit_value(string.byte_at(" ", 0)) != 0 - 1 { ok = false; }
  if radix_digit_value(string.byte_at("-", 0)) != 0 - 1 { ok = false; }
  if radix_digit_value(string.byte_at("+", 0)) != 0 - 1 { ok = false; }
  if radix_digit_value(string.byte_at(":", 0)) != 0 - 1 { ok = false; }
  if radix_digit_value(string.byte_at("@", 0)) != 0 - 1 { ok = false; }
  if radix_digit_value(string.byte_at("{", 0)) != 0 - 1 { ok = false; }
  if radix_digit_value(string.byte_at("é", 0)) != 0 - 1 { ok = false; }
  if radix_digit_value(255u8) != 0 - 1 { ok = false; }
  if radix_digit_value(128u8) != 0 - 1 { ok = false; }
  return assert(ok, "digit values 0..35 for 0-9/a-z/A-Z, -1 otherwise");
}

fn t3() -> TestResult {
  var ok = int_ok_is(radix_to_int("0", 2), 0);
  if !int_ok_is(radix_to_int("1", 2), 1) { ok = false; }
  if !int_ok_is(radix_to_int("1010", 2), 10) { ok = false; }
  if !int_ok_is(radix_to_int("777", 8), 511) { ok = false; }
  if !int_ok_is(radix_to_int("12345", 10), 12345) { ok = false; }
  if !int_ok_is(radix_to_int("ff", 16), 255) { ok = false; }
  if !int_ok_is(radix_to_int("100", 16), 256) { ok = false; }
  if !int_ok_is(radix_to_int("z", 36), 35) { ok = false; }
  if !int_ok_is(radix_to_int("10", 36), 36) { ok = false; }
  if !int_ok_is(radix_to_int("1y2p0ij32e8e7", 36), core.INT_MAX) { ok = false; }
  return assert(ok, "parse: baseline values in bases 2/8/10/16/36");
}

fn t4() -> TestResult {
  var ok = int_ok_is(radix_to_int("FF", 16), 255);
  if !int_ok_is(radix_to_int("DeadBeef", 16), 3735928559) { ok = false; }
  if !int_ok_is(radix_to_int("Zz", 36), 1295) { ok = false; }
  if !int_ok_is(radix_to_int("ABCDEF", 16), 11259375) { ok = false; }
  if !int_ok_is(radix_to_int("Ac", 16), 172) { ok = false; }
  return assert(ok, "uppercase A-Z is accepted as the same digit values");
}

fn t5() -> TestResult {
  var ok = int_ok_is(radix_to_int("+42", 10), 42);
  if !int_ok_is(radix_to_int("-42", 10), 0 - 42) { ok = false; }
  if !int_ok_is(radix_to_int("+ff", 16), 255) { ok = false; }
  if !int_ok_is(radix_to_int("-ff", 16), 0 - 255) { ok = false; }
  if !int_ok_is(radix_to_int("-0", 10), 0) { ok = false; }
  if !int_ok_is(radix_to_int("+0", 2), 0) { ok = false; }
  if !int_ok_is(radix_to_int("-1010", 2), 0 - 10) { ok = false; }
  return assert(ok, "optional leading '+'/'-' with '-' canonical on emit");
}

fn t6() -> TestResult {
  var ok = int_ok_is(radix_to_int("00042", 10), 42);
  if !int_ok_is(radix_to_int("007", 8), 7) { ok = false; }
  if !int_ok_is(radix_to_int("0000", 10), 0) { ok = false; }
  if !int_ok_is(radix_to_int("-0007", 10), 0 - 7) { ok = false; }
  if !int_ok_is(radix_to_int("00000000ff", 16), 255) { ok = false; }
  if !int_ok_is(radix_to_int("000z", 36), 35) { ok = false; }
  return assert(ok, "leading zeros are accepted on parse");
}

fn t7() -> TestResult {
  var ok = str_ok_is(radix_from_int(0, 10), "0");
  if !str_ok_is(radix_from_int(42, 10), "42") { ok = false; }
  if !str_ok_is(radix_from_int(255, 16), "ff") { ok = false; }
  if !str_ok_is(radix_from_int(10, 2), "1010") { ok = false; }
  if !str_ok_is(radix_from_int(511, 8), "777") { ok = false; }
  if !str_ok_is(radix_from_int(35, 36), "z") { ok = false; }
  if !str_ok_is(radix_from_int(36, 36), "10") { ok = false; }
  if !str_ok_is(radix_from_int(0 - 42, 10), "-42") { ok = false; }
  if !str_ok_is(radix_from_int(0 - 255, 16), "-ff") { ok = false; }
  return assert(ok, "format: lowercase canonical output");
}

fn t8() -> TestResult {
  var ok = str_ok_is(radix_from_int(0, 2), "0");
  if !str_ok_is(radix_from_int(0, 36), "0") { ok = false; }
  var b = 2;
  while b <= 36 {
    if !str_ok_is(radix_from_int(1, b), "1") { ok = false; }
    if !str_ok_is(radix_from_int(0 - 1, b), "-1") { ok = false; }
    if !int_ok_is(radix_to_int("0", b), 0) { ok = false; }
    if !int_ok_is(radix_to_int("-1", b), 0 - 1) { ok = false; }
    b = b + 1;
  }
  return assert(ok, "zero is '0' and +/-1 is '1'/'-1' in every base");
}

fn t9() -> TestResult {
  var ok = str_ok_is(radix_from_int(core.INT_MAX, 10), "9223372036854775807");
  if !str_ok_is(radix_from_int(core.INT_MAX, 16), "7fffffffffffffff") { ok = false; }
  if !str_ok_is(radix_from_int(core.INT_MAX, 2), "111111111111111111111111111111111111111111111111111111111111111") { ok = false; }
  if !str_ok_is(radix_from_int(core.INT_MAX, 8), "777777777777777777777") { ok = false; }
  if !str_ok_is(radix_from_int(core.INT_MAX, 36), "1y2p0ij32e8e7") { ok = false; }
  if !int_ok_is(radix_to_int("7fffffffffffffff", 16), core.INT_MAX) { ok = false; }
  if !int_ok_is(radix_to_int("1y2p0ij32e8e7", 36), core.INT_MAX) { ok = false; }
  if !rt_int(core.INT_MAX, 16) { ok = false; }
  if !rt_int(core.INT_MAX, 36) { ok = false; }
  return assert(ok, "INT_MAX formats and parses in bases 2/8/10/16/36");
}

fn t10() -> TestResult {
  var ok = str_ok_is(radix_from_int(core.INT_MIN, 10), "-9223372036854775808");
  if !str_ok_is(radix_from_int(core.INT_MIN, 16), "-8000000000000000") { ok = false; }
  if !str_ok_is(radix_from_int(core.INT_MIN, 2), "-1000000000000000000000000000000000000000000000000000000000000000") { ok = false; }
  if !str_ok_is(radix_from_int(core.INT_MIN, 36), "-1y2p0ij32e8e8") { ok = false; }
  if !int_ok_is(radix_to_int("-9223372036854775808", 10), core.INT_MIN) { ok = false; }
  if !int_ok_is(radix_to_int("-8000000000000000", 16), core.INT_MIN) { ok = false; }
  if !int_ok_is(radix_to_int("-1y2p0ij32e8e8", 36), core.INT_MIN) { ok = false; }
  if !rt_int(core.INT_MIN, 10) { ok = false; }
  if !rt_int(core.INT_MIN, 2) { ok = false; }
  return assert(ok, "INT_MIN formats and parses in bases 2/10/16/36");
}

fn t11() -> TestResult {
  var ok = int_err_is(radix_to_int("9223372036854775808", 10), "radix: overflow");
  if !int_err_is(radix_to_int("+9223372036854775808", 10), "radix: overflow") { ok = false; }
  if !int_err_is(radix_to_int("8000000000000000", 16), "radix: overflow") { ok = false; }
  if !int_err_is(radix_to_int("1000000000000000000000000000000000000000000000000000000000000000", 2), "radix: overflow") { ok = false; }
  if !int_err_is(radix_to_int("1111111111111111111111111111111111111111111111111111111111111111", 2), "radix: overflow") { ok = false; }
  if !int_err_is(radix_to_int("999999999999999999999999", 10), "radix: overflow") { ok = false; }
  return assert(ok, "positive overflow (2^63 and beyond) is Err");
}

fn t12() -> TestResult {
  var ok = int_err_is(radix_to_int("-9223372036854775809", 10), "radix: overflow");
  if !int_err_is(radix_to_int("-8000000000000001", 16), "radix: overflow") { ok = false; }
  if !int_err_is(radix_to_int("-1y2p0ij32e8e9", 36), "radix: overflow") { ok = false; }
  if !int_err_is(radix_to_int("-1111111111111111111111111111111111111111111111111111111111111111", 2), "radix: overflow") { ok = false; }
  return assert(ok, "negative overflow (below INT_MIN) is Err");
}

fn t13() -> TestResult {
  var ok = int_err_is(radix_to_int("12z", 10), "radix: invalid digit at position 2");
  if !int_err_is(radix_to_int("12g", 16), "radix: invalid digit at position 2") { ok = false; }
  if !int_err_is(radix_to_int("ff!", 16), "radix: invalid digit at position 2") { ok = false; }
  if !int_err_is(radix_to_int("2", 2), "radix: invalid digit at position 0") { ok = false; }
  if !int_err_is(radix_to_int("-1@", 10), "radix: invalid digit at position 2") { ok = false; }
  if !int_err_is(radix_to_int("+1 ", 10), "radix: invalid digit at position 2") { ok = false; }
  if !int_err_is(radix_to_int("1_0", 10), "radix: invalid digit at position 1") { ok = false; }
  if !int_err_is(radix_to_int(" 12", 10), "radix: invalid digit at position 0") { ok = false; }
  if !int_err_is(radix_to_int("0x1f", 16), "radix: invalid digit at position 1") { ok = false; }
  if !int_err_is(radix_to_int("1111111111!", 10), "radix: invalid digit at position 10") { ok = false; }
  return assert(ok, "invalid digit errors carry the 0-based byte position");
}

fn t14() -> TestResult {
  var ok = int_err_is(radix_to_int("1", 1), "radix: base out of range");
  if !int_err_is(radix_to_int("1", 0), "radix: base out of range") { ok = false; }
  if !int_err_is(radix_to_int("1", 37), "radix: base out of range") { ok = false; }
  if !int_err_is(radix_to_int("1", 0 - 2), "radix: base out of range") { ok = false; }
  if !int_err_is(radix_to_int("", 99), "radix: base out of range") { ok = false; }
  if !str_err_is(radix_from_int(1, 1), "radix: base out of range") { ok = false; }
  if !str_err_is(radix_from_int(1, 37), "radix: base out of range") { ok = false; }
  if !str_err_is(radix_convert("1", 0, 10), "radix: base out of range") { ok = false; }
  if !str_err_is(radix_convert("1", 10, 99), "radix: base out of range") { ok = false; }
  return assert(ok, "base outside 2..36 is Err and precedes input errors");
}

fn t15() -> TestResult {
  var ok = int_err_is(radix_to_int("", 10), "radix: empty input");
  if !int_err_is(radix_to_int("", 2), "radix: empty input") { ok = false; }
  if !int_err_is(radix_to_int("", 36), "radix: empty input") { ok = false; }
  if !int_err_is(radix_to_int("+", 10), "radix: lone sign") { ok = false; }
  if !int_err_is(radix_to_int("-", 2), "radix: lone sign") { ok = false; }
  if !int_err_is(radix_to_int("-", 36), "radix: lone sign") { ok = false; }
  return assert(ok, "empty input and lone sign have distinct errors");
}

fn t16() -> TestResult {
  var vals = Vec[Int].new();
  vals.push(0);
  vals.push(1);
  vals.push(0 - 1);
  vals.push(7);
  vals.push(8);
  vals.push(255);
  vals.push(256);
  vals.push(0 - 255);
  vals.push(1000000);
  vals.push(0 - 1000000);
  vals.push(core.INT_MAX);
  vals.push(core.INT_MIN);
  var bases = Vec[Int].new();
  bases.push(2);
  bases.push(8);
  bases.push(10);
  bases.push(16);
  bases.push(36);
  var ok = true;
  var i = 0;
  while i < vals.len() {
    let v: Int = vals[i];
    var j = 0;
    while j < bases.len() {
      let b: Int = bases[j];
      if !rt_int(v, b) { ok = false; }
      let f = radix_from_int(v, b);
      if !f.is_ok { ok = false; }
      if f.is_ok {
        if !radix_is_valid(f.value, b) { ok = false; }
      }
      j = j + 1;
    }
    i = i + 1;
  }
  return assert(ok, "round-trip 12 values across bases 2/8/10/16/36");
}

fn t17() -> TestResult {
  var ok = str_ok_is(radix_convert("ff", 16, 2), "11111111");
  if !str_ok_is(radix_convert("11111111", 2, 16), "ff") { ok = false; }
  if !str_ok_is(radix_convert("777", 8, 10), "511") { ok = false; }
  if !str_ok_is(radix_convert("511", 10, 8), "777") { ok = false; }
  if !str_ok_is(radix_convert("-ff", 16, 10), "-255") { ok = false; }
  if !str_ok_is(radix_convert("1010", 2, 36), "a") { ok = false; }
  if !str_ok_is(radix_convert("z", 36, 10), "35") { ok = false; }
  if !str_ok_is(radix_convert("0000ff", 16, 16), "ff") { ok = false; }
  if !str_ok_is(radix_convert("+1010", 2, 10), "10") { ok = false; }
  if !str_ok_is(radix_convert("9223372036854775807", 10, 16), "7fffffffffffffff") { ok = false; }
  if !str_ok_is(radix_convert("-8000000000000000", 16, 10), "-9223372036854775808") { ok = false; }
  if !str_err_is(radix_convert("12z", 10, 16), "radix: invalid digit at position 2") { ok = false; }
  if !str_err_is(radix_convert("9223372036854775808", 10, 2), "radix: overflow") { ok = false; }
  if !str_err_is(radix_convert("", 16, 2), "radix: empty input") { ok = false; }
  if !str_err_is(radix_convert("-", 2, 10), "radix: lone sign") { ok = false; }
  return assert(ok, "base-to-base conversion via Int and error propagation");
}

fn t18() -> TestResult {
  var ok = radix_is_valid("0", 2);
  if !radix_is_valid("1010", 2) { ok = false; }
  if !radix_is_valid("ff", 16) { ok = false; }
  if !radix_is_valid("FF", 16) { ok = false; }
  if !radix_is_valid("+42", 10) { ok = false; }
  if !radix_is_valid("-0", 10) { ok = false; }
  if !radix_is_valid("00012", 10) { ok = false; }
  if !radix_is_valid("z", 36) { ok = false; }
  if radix_is_valid("", 10) { ok = false; }
  if radix_is_valid("+", 10) { ok = false; }
  if radix_is_valid("-", 10) { ok = false; }
  if radix_is_valid("12z", 10) { ok = false; }
  if radix_is_valid("2", 2) { ok = false; }
  if radix_is_valid("g", 16) { ok = false; }
  if radix_is_valid("1", 1) { ok = false; }
  if radix_is_valid("1", 37) { ok = false; }
  if radix_is_valid(" ", 10) { ok = false; }
  if radix_is_valid("0x10", 16) { ok = false; }
  return assert(ok, "is_valid mirrors the parser for every error class");
}

fn t19() -> TestResult {
  let p1 = radix_to_int("00ff", 16);
  var ok = int_ok_is(p1, 255);
  if p1.is_ok {
    if !str_ok_is(radix_from_int(p1.value, 16), "ff") { ok = false; }
  }
  let p2 = radix_to_int("+ff", 16);
  if !int_ok_is(p2, 255) { ok = false; }
  let p3 = radix_to_int("-000z", 36);
  if !int_ok_is(p3, 0 - 35) { ok = false; }
  if p3.is_ok {
    if !str_ok_is(radix_from_int(p3.value, 36), "-z") { ok = false; }
  }
  let p4 = radix_to_int("-0", 10);
  if !int_ok_is(p4, 0) { ok = false; }
  if p4.is_ok {
    if !str_ok_is(radix_from_int(p4.value, 10), "0") { ok = false; }
  }
  let p5 = radix_to_int("DEADBEEF", 16);
  if !int_ok_is(p5, 3735928559) { ok = false; }
  if p5.is_ok {
    if !str_ok_is(radix_from_int(p5.value, 16), "deadbeef") { ok = false; }
  }
  return assert(ok, "canonical emit: no leading zeros, lowercase, '-' only");
}

fn t20() -> TestResult {
  var ok = true;
  var b = 2;
  while b <= 36 {
    var d = 0;
    while d < b {
      let ch = string.str_slice(radix_alphabet(), d, d + 1);
      if !int_ok_is(radix_to_int(ch, b), d) { ok = false; }
      if !str_ok_is(radix_from_int(d, b), ch) { ok = false; }
      d = d + 1;
    }
    b = b + 1;
  }
  return assert(ok, "every digit 0..b-1 round-trips in every base 2..36");
}

fn main() -> Int {
  io.println("=== xiom.radix conformance tests ===");
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
    io.println("xiom.radix: all tests passed");
  } else {
    io.println("xiom.radix: tests failed");
  }
  return failed;
}
