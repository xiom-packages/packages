// XIOM -- xiom.ean conformance tests (20 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Provenance: every valid fixture is a published EAN-13 / EAN-8 / UPC-A
// example; each one was independently re-checked with a separate
// implementation of the GS1 check-digit rule (weights 3,1,3,1,... from the
// right, sum, (10 - sum mod 10) mod 10) before being pinned here. The
// invalid fixtures are one-digit mutations, so every error class is
// reachable in isolation. The all-zero, all-nines and zero-check-digit
// fixtures are constructed boundaries, valid under the check-digit rule
// even though GS1 does not assign them.
//
// BUG 17 note: all Str equality goes through str_compare, and every library
// call receives a plain local, never a Vec element.
//
// Compiler note: test dispatch is a direct call chain (t1..t20 from main),
// never a Vec[fn] table.

module ean_tests
use xiom.io; use xiom.test;
use xiom.ean;
use xiom.string.compare;
use xiom.convert;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn ean_ok(s: Str) -> Bool {
  match ean_parse(s) {
    Ok(v) => { return true; },
    Err(e) => { return false; },
  }
}

fn ean_err_is(s: Str, want: Str) -> Bool {
  match ean_parse(s) {
    Ok(v) => { return false; },
    Err(e) => { return streq(e, want); },
  }
}

fn ean13_ok(s: Str) -> Bool {
  match ean13_parse(s) {
    Ok(v) => { return true; },
    Err(e) => { return false; },
  }
}

fn ean13_err_is(s: Str, want: Str) -> Bool {
  match ean13_parse(s) {
    Ok(v) => { return false; },
    Err(e) => { return streq(e, want); },
  }
}

fn ean8_ok(s: Str) -> Bool {
  match ean8_parse(s) {
    Ok(v) => { return true; },
    Err(e) => { return false; },
  }
}

fn ean8_err_is(s: Str, want: Str) -> Bool {
  match ean8_parse(s) {
    Ok(v) => { return false; },
    Err(e) => { return streq(e, want); },
  }
}

fn upca_ok(s: Str) -> Bool {
  match upca_parse(s) {
    Ok(v) => { return true; },
    Err(e) => { return false; },
  }
}

fn upca_err_is(s: Str, want: Str) -> Bool {
  match upca_parse(s) {
    Ok(v) => { return false; },
    Err(e) => { return streq(e, want); },
  }
}

fn kind_of(s: Str) -> Int {
  match ean_parse(s) {
    Ok(v) => { return ean_kind(&v); },
    Err(e) => { return -1; },
  }
}

fn body_of(s: Str) -> Str {
  match ean_parse(s) {
    Ok(v) => { return ean_body(&v); },
    Err(e) => { return ""; },
  }
}

fn check_of(s: Str) -> Int {
  match ean_parse(s) {
    Ok(v) => { return ean_check_digit(&v); },
    Err(e) => { return -1; },
  }
}

fn prefix_of(s: Str) -> Str {
  match ean_parse(s) {
    Ok(v) => { return ean_country_prefix(&v); },
    Err(e) => { return ""; },
  }
}

fn compact_of(s: Str) -> Str {
  match ean_parse(s) {
    Ok(v) => { return ean_compact(&v); },
    Err(e) => { return ""; },
  }
}

fn fmt_of(s: Str) -> Str {
  match ean_parse(s) {
    Ok(v) => { return ean_format(&v); },
    Err(e) => { return ""; },
  }
}

fn structure_is(s: Str, kind: Int, body: Str, check: Int) -> Bool {
  match ean_parse(s) {
    Ok(v) => {
      return ean_kind(&v) == kind && ean_check_digit(&v) == check && streq(ean_body(&v), body) && streq(ean_digits(&v), s);
    },
    Err(e) => { return false; },
  }
}

fn c13(body: Str) -> Int {
  match ean13_compute_check_digit(body) {
    Ok(n) => { return n; },
    Err(e) => { return -1; },
  }
}

fn c8(body: Str) -> Int {
  match ean8_compute_check_digit(body) {
    Ok(n) => { return n; },
    Err(e) => { return -1; },
  }
}

fn cu(body: Str) -> Int {
  match upca_compute_check_digit(body) {
    Ok(n) => { return n; },
    Err(e) => { return -1; },
  }
}

fn c13_err_is(body: Str, want: Str) -> Bool {
  match ean13_compute_check_digit(body) {
    Ok(n) => { return false; },
    Err(e) => { return streq(e, want); },
  }
}

fn c8_err_is(body: Str, want: Str) -> Bool {
  match ean8_compute_check_digit(body) {
    Ok(n) => { return false; },
    Err(e) => { return streq(e, want); },
  }
}

fn cu_err_is(body: Str, want: Str) -> Bool {
  match upca_compute_check_digit(body) {
    Ok(n) => { return false; },
    Err(e) => { return streq(e, want); },
  }
}

fn roundtrip13(body: Str, want: Int) -> Bool {
  let k = c13(body);
  if k != want { return false; }
  let full = body + convert.int_to_string(k);
  if !ean13_ok(full) { return false; }
  if !streq(compact_of(full), full) { return false; }
  return streq(body_of(full), body);
}

fn roundtrip8(body: Str, want: Int) -> Bool {
  let k = c8(body);
  if k != want { return false; }
  let full = body + convert.int_to_string(k);
  if !ean8_ok(full) { return false; }
  if !streq(compact_of(full), full) { return false; }
  return streq(body_of(full), body);
}

fn roundtrip_upca(body: Str, want: Int) -> Bool {
  let k = cu(body);
  if k != want { return false; }
  let full = body + convert.int_to_string(k);
  if !upca_ok(full) { return false; }
  if !streq(compact_of(full), full) { return false; }
  return streq(body_of(full), body);
}

fn upca_to_ean13_of(s: Str) -> Str {
  match upca_to_ean13(s) {
    Ok(t) => { return t; },
    Err(e) => { return ""; },
  }
}

fn ean13_to_upca_of(s: Str) -> Str {
  match ean13_to_upca(s) {
    Ok(t) => { return t; },
    Err(e) => { return ""; },
  }
}

fn ean13_to_upca_err_is(s: Str, want: Str) -> Bool {
  match ean13_to_upca(s) {
    Ok(t) => { return false; },
    Err(e) => { return streq(e, want); },
  }
}

fn upca_to_ean13_err_is(s: Str, want: Str) -> Bool {
  match upca_to_ean13(s) {
    Ok(t) => { return false; },
    Err(e) => { return streq(e, want); },
  }
}

fn t1() -> TestResult {
  var ok = structure_is("4006381333931", 13, "400638133393", 1);
  if !structure_is("5901234123457", 13, "590123412345", 7) { ok = false; }
  if !structure_is("9780201379624", 13, "978020137962", 4) { ok = false; }
  if !structure_is("0036000291452", 13, "003600029145", 2) { ok = false; }
  return assert(ok, "EAN-13 fixtures: kind, body, check digit and digits accessors");
}

fn t2() -> TestResult {
  var ok = ean13_ok("4006381333931");
  if !ean13_ok("5901234123457") { ok = false; }
  if !ean13_ok("9780201379624") { ok = false; }
  if !ean13_is_valid("0036000291452") { ok = false; }
  if ean13_is_valid("0036000291451") { ok = false; }
  return assert(ok, "EAN-13: typed parse accepts fixtures; is_valid rejects a mutated check digit");
}

fn t3() -> TestResult {
  var ok = structure_is("96385074", 8, "9638507", 4);
  if !structure_is("73513537", 8, "7351353", 7) { ok = false; }
  if !ean8_ok("96385074") { ok = false; }
  if !ean8_is_valid("73513537") { ok = false; }
  if ean8_is_valid("96385075") { ok = false; }
  return assert(ok, "EAN-8 fixtures: structure, typed parse and is_valid");
}

fn t4() -> TestResult {
  var ok = structure_is("036000291452", 12, "03600029145", 2);
  if !structure_is("042100005264", 12, "04210000526", 4) { ok = false; }
  if !upca_ok("036000291452") { ok = false; }
  if !upca_is_valid("042100005264") { ok = false; }
  if upca_is_valid("036000291453") { ok = false; }
  return assert(ok, "UPC-A fixtures: structure, typed parse and is_valid");
}

fn t5() -> TestResult {
  var ok = c13("400638133393") == 1;
  if c13("590123412345") != 7 { ok = false; }
  if c13("978020137962") != 4 { ok = false; }
  if c8("9638507") != 4 { ok = false; }
  if c8("7351353") != 7 { ok = false; }
  if cu("03600029145") != 2 { ok = false; }
  if cu("04210000526") != 4 { ok = false; }
  return assert(ok, "compute_check_digit reproduces the check digit of seven fixtures");
}

fn t6() -> TestResult {
  var ok = roundtrip13("400638133393", 1);
  if !roundtrip13("590123412345", 7) { ok = false; }
  if !roundtrip13("978020137962", 4) { ok = false; }
  if !roundtrip8("9638507", 4) { ok = false; }
  if !roundtrip8("7351353", 7) { ok = false; }
  if !roundtrip_upca("03600029145", 2) { ok = false; }
  if !roundtrip_upca("04210000526", 4) { ok = false; }
  return assert(ok, "compute -> build -> parse round-trip for every fixture");
}

fn t7() -> TestResult {
  var ok = structure_is("0000000000000", 13, "000000000000", 0);
  if !structure_is("000000000000", 12, "00000000000", 0) { ok = false; }
  if !structure_is("00000000", 8, "0000000", 0) { ok = false; }
  if c13("000000000000") != 0 { ok = false; }
  if cu("00000000000") != 0 { ok = false; }
  if c8("0000000") != 0 { ok = false; }
  return assert(ok, "all-zero boundaries: accepted with check digit 0 at all three lengths");
}

fn t8() -> TestResult {
  var ok = structure_is("9999999999994", 13, "999999999999", 4);
  if !structure_is("999999999993", 12, "99999999999", 3) { ok = false; }
  if !structure_is("99999995", 8, "9999999", 5) { ok = false; }
  if c13("999999999999") != 4 { ok = false; }
  if cu("99999999999") != 3 { ok = false; }
  if c8("9999999") != 5 { ok = false; }
  return assert(ok, "all-nines boundaries: maximum digit load yields check digits 4/3/5");
}

fn t9() -> TestResult {
  var ok = c13("400638133390") == 0;
  if !ean13_ok("4006381333900") { ok = false; }
  if !structure_is("4006381333900", 13, "400638133390", 0) { ok = false; }
  if !roundtrip13("400638133390", 0) { ok = false; }
  return assert(ok, "zero check digit: computed 0 is accepted and round-trips");
}

fn t10() -> TestResult {
  var ok = kind_of("96385074") == 8;
  if kind_of("036000291452") != 12 { ok = false; }
  if kind_of("4006381333931") != 13 { ok = false; }
  if !ean_is_valid("96385074") { ok = false; }
  if !ean_is_valid("036000291452") { ok = false; }
  if !ean_is_valid("4006381333931") { ok = false; }
  if ean_is_valid("4006381333932") { ok = false; }
  return assert(ok, "ean_parse auto-detects the three types by length; ean_is_valid agrees");
}

fn t11() -> TestResult {
  var ok = ean13_err_is("", "ean: empty input");
  if !ean8_err_is("", "ean: empty input") { ok = false; }
  if !upca_err_is("", "ean: empty input") { ok = false; }
  if !ean_err_is("", "ean: empty input") { ok = false; }
  return assert(ok, "empty input is an error for every parser entry point");
}

fn t12() -> TestResult {
  var ok = ean13_err_is("400638133393", "ean: bad length for EAN-13: expected 13, got 12");
  if !ean13_err_is("40063813339310", "ean: bad length for EAN-13: expected 13, got 14") { ok = false; }
  if !ean8_err_is("9638507", "ean: bad length for EAN-8: expected 8, got 7") { ok = false; }
  if !upca_err_is("0360002914520", "ean: bad length for UPC-A: expected 12, got 13") { ok = false; }
  if !upca_err_is("03600029145", "ean: bad length for UPC-A: expected 12, got 11") { ok = false; }
  return assert(ok, "declared-type parsers report bad length with expected/got counts");
}

fn t13() -> TestResult {
  var ok = ean_err_is("1234567", "ean: bad length: 7 (expected 8, 12 or 13)");
  if !ean_err_is("123456789", "ean: bad length: 9 (expected 8, 12 or 13)") { ok = false; }
  if !ean_err_is("12345678901234", "ean: bad length: 14 (expected 8, 12 or 13)") { ok = false; }
  return assert(ok, "ean_parse reports the exact unsupported-length message");
}

fn t14() -> TestResult {
  var ok = ean13_err_is("400638133393A", "ean: bad characters: 400638133393A");
  if !ean13_err_is("40063813339 1", "ean: bad characters: 40063813339 1") { ok = false; }
  if !ean8_err_is("9638507A", "ean: bad characters: 9638507A") { ok = false; }
  if !upca_err_is("03600029145A", "ean: bad characters: 03600029145A") { ok = false; }
  if !ean_err_is("A006381333931", "ean: bad characters: A006381333931") { ok = false; }
  return assert(ok, "non-digit bytes are bad characters, checked before the check digit");
}

fn t15() -> TestResult {
  var ok = ean13_err_is("4006381333932", "ean: bad check digit: 4006381333932");
  if !ean13_err_is("4006381333930", "ean: bad check digit: 4006381333930") { ok = false; }
  if !ean8_err_is("96385075", "ean: bad check digit: 96385075") { ok = false; }
  if !upca_err_is("036000291453", "ean: bad check digit: 036000291453") { ok = false; }
  if !ean_err_is("9999999999993", "ean: bad check digit: 9999999999993") { ok = false; }
  return assert(ok, "mismatched check digits are rejected with the input echoed");
}

fn t16() -> TestResult {
  var ok = c13_err_is("", "ean: empty input");
  if !c8_err_is("", "ean: empty input") { ok = false; }
  if !cu_err_is("", "ean: empty input") { ok = false; }
  if !c13_err_is("40063813339", "ean: bad body length for EAN-13: expected 12, got 11") { ok = false; }
  if !cu_err_is("036000291452", "ean: bad body length for UPC-A: expected 11, got 12") { ok = false; }
  if !c8_err_is("96385074", "ean: bad body length for EAN-8: expected 7, got 8") { ok = false; }
  if !c13_err_is("40063813339A", "ean: bad characters: 40063813339A") { ok = false; }
  if !cu_err_is("0360002914A", "ean: bad characters: 0360002914A") { ok = false; }
  return assert(ok, "compute_check_digit errors: empty, body length per type, charset");
}

fn t17() -> TestResult {
  var ok = streq(upca_to_ean13_of("036000291452"), "0036000291452");
  if !streq(upca_to_ean13_of("042100005264"), "0042100005264") { ok = false; }
  if !streq(ean13_to_upca_of("0036000291452"), "036000291452") { ok = false; }
  if !ean13_is_upca_equivalent("0036000291452") { ok = false; }
  if ean13_is_upca_equivalent("4006381333931") { ok = false; }
  if !ean13_to_upca_err_is("4006381333931", "ean: not UPC-A equivalent: 4006381333931") { ok = false; }
  if !upca_to_ean13_err_is("036000291453", "ean: bad check digit: 036000291453") { ok = false; }
  return assert(ok, "UPC-A <-> EAN-13 zero-prefix equivalence both ways, with error paths");
}

fn t18() -> TestResult {
  var ok = streq(fmt_of("4006381333931"), "4 006381 333931");
  if !streq(fmt_of("036000291452"), "0 36000 29145 2") { ok = false; }
  if !streq(fmt_of("96385074"), "9638 5074") { ok = false; }
  if !streq(fmt_of("9999999999994"), "9 999999 999994") { ok = false; }
  return assert(ok, "grouped display: EAN-13 1-6-6, UPC-A 1-5-5-1, EAN-8 4-4");
}

fn t19() -> TestResult {
  var ok = streq(compact_of("4006381333931"), "4006381333931");
  if !streq(compact_of("036000291452"), "036000291452") { ok = false; }
  if !streq(compact_of("96385074"), "96385074") { ok = false; }
  if !streq(prefix_of("4006381333931"), "400") { ok = false; }
  if !streq(prefix_of("0036000291452"), "003") { ok = false; }
  if !streq(prefix_of("036000291452"), "036") { ok = false; }
  if !streq(prefix_of("96385074"), "963") { ok = false; }
  return assert(ok, "compact round-trip and informational 3-digit GS1 prefix field");
}

fn t20() -> TestResult {
  var ok = structure_is("5901234123457", 13, "590123412345", 7);
  if kind_of("5901234123457") != kind_of("5901234123457") { ok = false; }
  if !streq(body_of("5901234123457") + convert.int_to_string(check_of("5901234123457")), "5901234123457") { ok = false; }
  if check_of("5901234123457") != 7 { ok = false; }
  if !streq(body_of("036000291452") + convert.int_to_string(check_of("036000291452")), "036000291452") { ok = false; }
  return assert(ok, "body + check digit reconstructs the digits; accessors are deterministic");
}

fn main() -> Int {
  io.println("=== xiom.ean conformance tests ===");
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
    io.println("xiom.ean: all tests passed");
  } else {
    io.println("xiom.ean: tests failed");
  }
  return failed;
}
