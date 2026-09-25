// XIOM -- xiom.luhn conformance tests (18 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Provenance: every valid fixture is a public arithmetic fixture -- a number
// widely published as a test vector -- and each one was independently
// re-checked with a separate implementation of the Luhn rule (double every
// second digit from the right, subtract 9 above 9, sum, require a multiple of
// 10) before being pinned here. They are arithmetic fixtures, not claims that
// any issuer assigned them. The invalid fixtures are one-digit mutations, so
// every error class is reachable in isolation.
//
// BUG 17 note: all Str equality goes through str_compare, and no test indexes
// a Vec (the suite uses no Vec at all); every library call receives a plain
// local.
//
// Compiler note: test dispatch is a direct call chain (t1..t18 from main),
// never a Vec[fn] table.

module luhn_tests
use xiom.io; use xiom.test;
use xiom.luhn;
use xiom.string;
use xiom.string.compare;
use xiom.convert;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn parse_ok(s: Str) -> Bool {
  match luhn_parse(s) {
    Ok(v) => { return true; },
    Err(e) => { return false; },
  }
}

fn parse_err_is(s: Str, want: Str) -> Bool {
  match luhn_parse(s) {
    Ok(v) => { return false; },
    Err(e) => { return streq(e, want); },
  }
}

fn normalized_ok(s: Str) -> Bool {
  match luhn_parse_normalized(s) {
    Ok(v) => { return true; },
    Err(e) => { return false; },
  }
}

fn normalized_err_is(s: Str, want: Str) -> Bool {
  match luhn_parse_normalized(s) {
    Ok(v) => { return false; },
    Err(e) => { return streq(e, want); },
  }
}

fn fields_are(s: Str, count: Int, body: Str, check: Int) -> Bool {
  match luhn_parse(s) {
    Ok(v) => {
      return luhn_digit_count(&v) == count && luhn_check_digit(&v) == check && streq(luhn_body(&v), body) && streq(luhn_digits(&v), s);
    },
    Err(e) => { return false; },
  }
}

fn normalized_fields_are(raw: Str, canon: Str, count: Int, body: Str, check: Int) -> Bool {
  match luhn_parse_normalized(raw) {
    Ok(v) => {
      return streq(luhn_digits(&v), canon) && luhn_digit_count(&v) == count && luhn_check_digit(&v) == check && streq(luhn_body(&v), body);
    },
    Err(e) => { return false; },
  }
}

fn check_of(body: Str) -> Int {
  match luhn_compute_check_digit(body) {
    Ok(n) => { return n; },
    Err(e) => { return -1; },
  }
}

fn compute_err_is(body: Str, want: Str) -> Bool {
  match luhn_compute_check_digit(body) {
    Ok(n) => { return false; },
    Err(e) => { return streq(e, want); },
  }
}

fn appended(body: Str) -> Str {
  match luhn_append_check_digit(body) {
    Ok(t) => { return t; },
    Err(e) => { return ""; },
  }
}

fn append_err_is(body: Str, want: Str) -> Bool {
  match luhn_append_check_digit(body) {
    Ok(t) => { return false; },
    Err(e) => { return streq(e, want); },
  }
}

fn roundtrip(body: Str, want: Int) -> Bool {
  let k = check_of(body);
  if k != want { return false; }
  let full = body + convert.int_to_string(k);
  if !parse_ok(full) { return false; }
  if !fields_are(full, body.len() + 1, body, k) { return false; }
  return streq(appended(body), full);
}

fn t1() -> TestResult {
  var ok = fields_are("79927398713", 11, "7992739871", 3);
  if !fields_are("1234567812345670", 16, "123456781234567", 0) { ok = false; }
  if !fields_are("4532015112830366", 16, "453201511283036", 6) { ok = false; }
  if !fields_are("4111111111111111", 16, "411111111111111", 1) { ok = false; }
  return assert(ok, "strict parse: structure accessors on four public arithmetic fixtures");
}

fn t2() -> TestResult {
  var ok = fields_are("378282246310005", 15, "37828224631000", 5);
  if !fields_are("3566002020360505", 16, "356600202036050", 5) { ok = false; }
  if !parse_ok("79927398713") { ok = false; }
  if !luhn_is_valid("1234567812345670") { ok = false; }
  if !luhn_is_valid("4532015112830366") { ok = false; }
  if !luhn_is_valid("4111111111111111") { ok = false; }
  return assert(ok, "strict parse and is_valid accept all six fixtures");
}

fn t3() -> TestResult {
  var ok = check_of("7992739871") == 3;
  if check_of("123456781234567") != 0 { ok = false; }
  if check_of("453201511283036") != 6 { ok = false; }
  if check_of("411111111111111") != 1 { ok = false; }
  if check_of("37828224631000") != 5 { ok = false; }
  if check_of("356600202036050") != 5 { ok = false; }
  return assert(ok, "compute_check_digit reproduces the check digit of six fixture bodies");
}

fn t4() -> TestResult {
  var ok = streq(appended("7992739871"), "79927398713");
  if !streq(appended("123456781234567"), "1234567812345670") { ok = false; }
  if !streq(appended("453201511283036"), "4532015112830366") { ok = false; }
  if !roundtrip("411111111111111", 1) { ok = false; }
  if !roundtrip("37828224631000", 5) { ok = false; }
  if !roundtrip("356600202036050", 5) { ok = false; }
  return assert(ok, "append_check_digit -> parse round-trip for every fixture body");
}

fn t5() -> TestResult {
  var ok = check_of("0") == 0 && streq(appended("0"), "00");
  if check_of("1") != 8 { ok = false; }
  if check_of("9") != 1 { ok = false; }
  if check_of("89") != 3 { ok = false; }
  if !roundtrip("0", 0) { ok = false; }
  if !roundtrip("1", 8) { ok = false; }
  if !roundtrip("9", 1) { ok = false; }
  if !roundtrip("89", 3) { ok = false; }
  return assert(ok, "small bodies: 9-subtraction boundary and one-digit bodies");
}

fn t6() -> TestResult {
  var ok = fields_are("00", 2, "0", 0);
  if !fields_are("18", 2, "1", 8) { ok = false; }
  if !parse_err_is("0", "luhn: too short: 0 (minimum 2 digits)") { ok = false; }
  if !parse_err_is("", "luhn: empty input") { ok = false; }
  if !normalized_ok("0 0") { ok = false; }
  if !normalized_err_is("5", "luhn: too short: 5 (minimum 2 digits)") { ok = false; }
  return assert(ok, "minimum length policy: two digits accepted, one digit is too short");
}

fn t7() -> TestResult {
  var ok = streq(luhn_normalize("4532-0151 1283-0366"), "4532015112830366");
  if !streq(luhn_normalize("  --  "), "") { ok = false; }
  if !streq(luhn_normalize(""), "") { ok = false; }
  if !streq(luhn_normalize("a-b c"), "abc") { ok = false; }
  if !streq(luhn_normalize("no separators"), "noseparators") { ok = false; }
  return assert(ok, "normalize strips exactly space and hyphen and keeps every other byte");
}

fn t8() -> TestResult {
  var ok = normalized_fields_are("4532-0151-1283-0366", "4532015112830366", 16, "453201511283036", 6);
  if !normalized_fields_are("4532 0151 1283 0366", "4532015112830366", 16, "453201511283036", 6) { ok = false; }
  if !normalized_fields_are("7992-7398 713", "79927398713", 11, "7992739871", 3) { ok = false; }
  if !normalized_ok("1234-5678-1234-5670") { ok = false; }
  if !normalized_ok("4532015112830366") { ok = false; }
  return assert(ok, "normalized parse accepts hyphen, space and mixed grouped forms");
}

fn t9() -> TestResult {
  var ok = normalized_err_is("4532.0151.1283.0366", "luhn: bad characters: 4532.0151.1283.0366");
  if !normalized_err_is("4532/0151/1283/0366", "luhn: bad characters: 4532/0151/1283/0366") { ok = false; }
  if !normalized_err_is("45_32015112830366", "luhn: bad characters: 45_32015112830366") { ok = false; }
  return assert(ok, "normalized parse rejects every separator outside the documented set");
}

fn t10() -> TestResult {
  var ok = normalized_err_is("", "luhn: empty input");
  if !normalized_err_is(" ", "luhn: only separators:  ") { ok = false; }
  if !normalized_err_is("-", "luhn: only separators: -") { ok = false; }
  if !normalized_err_is(" - - ", "luhn: only separators:  - - ") { ok = false; }
  if !normalized_err_is("a", "luhn: bad characters: a") { ok = false; }
  return assert(ok, "normalized parse distinguishes raw empty, only separators and bad characters");
}

fn t11() -> TestResult {
  var ok = parse_err_is("4532-0151-1283-0366", "luhn: bad characters: 4532-0151-1283-0366");
  if !parse_err_is("4532 0151 1283 0366", "luhn: bad characters: 4532 0151 1283 0366") { ok = false; }
  if luhn_is_valid("4532-0151-1283-0366") { ok = false; }
  if !normalized_ok("4532-0151-1283-0366") { ok = false; }
  return assert(ok, "strict parse rejects raw separator forms that the normalized parser accepts");
}

fn t12() -> TestResult {
  var ok = parse_err_is("A", "luhn: bad characters: A");
  if !parse_err_is("12A", "luhn: bad characters: 12A") { ok = false; }
  if !parse_err_is("7992739871A", "luhn: bad characters: 7992739871A") { ok = false; }
  if !parse_err_is("A9927398713", "luhn: bad characters: A9927398713") { ok = false; }
  if !normalized_err_is("79-92A", "luhn: bad characters: 7992A") { ok = false; }
  return assert(ok, "non-digit bytes are bad characters, checked before length and check digit");
}

fn t13() -> TestResult {
  var ok = parse_err_is("79927398714", "luhn: bad check digit: 79927398714");
  if !parse_err_is("1234567812345671", "luhn: bad check digit: 1234567812345671") { ok = false; }
  if !parse_err_is("4532015112830367", "luhn: bad check digit: 4532015112830367") { ok = false; }
  if !parse_err_is("378282246310006", "luhn: bad check digit: 378282246310006") { ok = false; }
  if !parse_err_is("4112111111111111", "luhn: bad check digit: 4112111111111111") { ok = false; }
  return assert(ok, "one-byte mutations of the check digit and of a body digit are bad check digits");
}

fn t14() -> TestResult {
  var ok = compute_err_is("", "luhn: empty input");
  if !compute_err_is("12A", "luhn: bad characters: 12A") { ok = false; }
  if !compute_err_is("79-9273", "luhn: bad characters: 79-9273") { ok = false; }
  if !compute_err_is("79 92", "luhn: bad characters: 79 92") { ok = false; }
  return assert(ok, "compute_check_digit error catalog: empty body and non-digit bodies");
}

fn t15() -> TestResult {
  var ok = append_err_is("", "luhn: empty input");
  if !append_err_is("12A", "luhn: bad characters: 12A") { ok = false; }
  if !streq(appended("0"), "00") { ok = false; }
  if !streq(appended("999999999999999"), "9999999999999995") { ok = false; }
  if !roundtrip("999999999999999", 5) { ok = false; }
  return assert(ok, "append_check_digit propagates compute errors and returns body + check");
}

fn t16() -> TestResult {
  var ok = luhn_is_valid("79927398713");
  if !luhn_is_valid("1234567812345670") { ok = false; }
  if !luhn_is_valid("4532015112830366") { ok = false; }
  if !luhn_is_valid("378282246310005") { ok = false; }
  if luhn_is_valid("") { ok = false; }
  if luhn_is_valid("0") { ok = false; }
  if luhn_is_valid("79927398714") { ok = false; }
  if luhn_is_valid("4532-0151-1283-0366") { ok = false; }
  if luhn_is_valid("A") { ok = false; }
  if !luhn_is_valid_normalized("4532-0151-1283-0366") { ok = false; }
  if !luhn_is_valid_normalized("4532 0151 1283 0366") { ok = false; }
  if !luhn_is_valid_normalized("4532015112830366") { ok = false; }
  if luhn_is_valid_normalized("4532.0151.1283.0366") { ok = false; }
  if luhn_is_valid_normalized("   ") { ok = false; }
  if luhn_is_valid_normalized("79927398714") { ok = false; }
  return assert(ok, "is_valid truth table for strict and normalized verification");
}

fn t17() -> TestResult {
  let zeros = string.str_repeat("0", 1000);
  let full0 = appended(zeros);
  var ok = streq(full0, string.str_repeat("0", 1001));
  if !parse_ok(full0) { ok = false; }
  if !fields_are(full0, 1001, zeros, 0) { ok = false; }
  let nines = string.str_repeat("9", 1000);
  let k = check_of(nines);
  if k != 0 { ok = false; }
  let full9 = nines + convert.int_to_string(k);
  if !fields_are(full9, 1001, nines, 0) { ok = false; }
  return assert(ok, "long inputs: 1000-digit bodies stay Int-safe and round-trip");
}

fn t18() -> TestResult {
  let f1 = "79927398713";
  let f2 = "1234567812345670";
  let f3 = "4532015112830366";
  let f4 = "4111111111111111";
  var ok = streq(luhn_normalize("7992-7398-713"), f1);
  if !streq(luhn_normalize("1234-5678-1234-5670"), f2) { ok = false; }
  if !streq(luhn_normalize("4532-0151-1283-0366"), f3) { ok = false; }
  if !streq(luhn_normalize("4111 1111 1111 1111"), f4) { ok = false; }
  if !normalized_fields_are("7992-7398-713", f1, 11, "7992739871", 3) { ok = false; }
  if !normalized_fields_are("1234-5678-1234-5670", f2, 16, "123456781234567", 0) { ok = false; }
  if !parse_ok(f1) { ok = false; }
  if !parse_ok(f2) { ok = false; }
  return assert(ok, "normalize -> parse equivalence: display forms canonicalize to the same digits");
}

fn main() -> Int {
  io.println("=== xiom.luhn conformance tests ===");
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
    io.println("xiom.luhn: all tests passed");
  } else {
    io.println("xiom.luhn: tests failed");
  }
  return failed;
}
