// XIOM -- xiom.iban conformance tests (21 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Provenance: every valid fixture is a published IBAN example; each one was
// independently re-checked with a separate MOD-97-10 implementation before
// being pinned here. The invalid fixtures differ from their valid originals
// by exactly one byte (or by spacing / case), so each error class is
// reachable in isolation.
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str
// values read from Vec[Str] elements to a pointer comparison. No test indexes
// a Vec[Str], and every library call receives plain locals.

module iban_tests
use xiom.io; use xiom.test;
use xiom.iban;
use xiom.string;
use xiom.string.compare;
use xiom.convert;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn parse_ok(s: Str) -> Bool {
  match iban_parse(s) {
    Ok(v) => { return true; },
    Err(e) => { return false; },
  }
}

fn parse_err_is(s: Str, want: Str) -> Bool {
  match iban_parse(s) {
    Ok(v) => { return false; },
    Err(e) => { return streq(e, want); },
  }
}

fn fields_are(s: Str, cc: Str, check: Int, bban: Str) -> Bool {
  match iban_parse(s) {
    Ok(v) => {
      return streq(iban_country(&v), cc) && iban_check_digits(&v) == check && streq(iban_bban(&v), bban);
    },
    Err(e) => { return false; },
  }
}

fn fmt_is(s: Str, want: Str) -> Bool {
  match iban_parse(s) {
    Ok(v) => { return streq(iban_format(&v), want); },
    Err(e) => { return false; },
  }
}

fn fmt_of(s: Str) -> Str {
  match iban_parse(s) {
    Ok(v) => { return iban_format(&v); },
    Err(e) => { return ""; },
  }
}

fn compact_is(s: Str, want: Str) -> Bool {
  match iban_parse(s) {
    Ok(v) => { return streq(iban_compact(&v), want); },
    Err(e) => { return false; },
  }
}

fn check_of(cc: Str, bban: Str) -> Int {
  match iban_compute_check_digits(cc, bban) {
    Ok(n) => { return n; },
    Err(e) => { return -1; },
  }
}

fn compute_err_is(cc: Str, bban: Str, want: Str) -> Bool {
  match iban_compute_check_digits(cc, bban) {
    Ok(n) => { return false; },
    Err(e) => { return streq(e, want); },
  }
}

fn two_digits(n: Int) -> Str {
  if n < 10 { return "0" + convert.int_to_string(n); }
  return convert.int_to_string(n);
}

fn strip_spaces(s: Str) -> Str {
  var out = "";
  var i = 0;
  while i < s.len() {
    let b = string.byte_at(s, i);
    if b != 32u8 { out = out + string.str_slice(s, i, i + 1); }
    i = i + 1;
  }
  return out;
}

// Compute the check digits for (country, bban) with the module under test,
// build "CCkkBBAN" from them, and require that iban_parse accepts exactly
// that text and reports the same fields.
fn roundtrip(cc: Str, bban: Str, want_check: Int) -> Bool {
  let k = check_of(cc, bban);
  if k != want_check { return false; }
  let full = cc + two_digits(k) + bban;
  match iban_parse(full) {
    Ok(v) => {
      return iban_check_digits(&v) == k && streq(iban_country(&v), cc) && streq(iban_bban(&v), bban) && streq(iban_compact(&v), full);
    },
    Err(e) => { return false; },
  }
}

// Positive fixtures: published examples, all MOD-97-verified.
fn t1() -> TestResult {
  var ok = fields_are("DE89370400440532013000", "DE", 89, "370400440532013000");
  if !fields_are("GB82WEST12345698765432", "GB", 82, "WEST12345698765432") { ok = false; }
  if !fields_are("FR1420041010050500013M02606", "FR", 14, "20041010050500013M02606") { ok = false; }
  if !fields_are("NO9386011117947", "NO", 93, "86011117947") { ok = false; }
  return assert(ok, "parse: country, check digits and BBAN of DE/GB/FR/NO fixtures");
}

fn t2() -> TestResult {
  var ok = parse_ok("ES9121000418450200051332");
  if !parse_ok("IT60X0542811101000000123456") { ok = false; }
  if !parse_ok("NL91ABNA0417164300") { ok = false; }
  if !parse_ok("BE68539007547034") { ok = false; }
  if !parse_ok("CH9300762011623852957") { ok = false; }
  if !parse_ok("AT611904300234573201") { ok = false; }
  if !parse_ok("PT50000201231234567890154") { ok = false; }
  if !parse_ok("IE29AIBK93115212345678") { ok = false; }
  return assert(ok, "parse: ES/IT/NL/BE/CH/AT/PT/IE fixtures");
}

fn t3() -> TestResult {
  var ok = parse_ok("FI2112345600000785");
  if !parse_ok("SE4550000000058398257466") { ok = false; }
  if !parse_ok("DK5000400440116243") { ok = false; }
  if !parse_ok("PL61109010140000071219812874") { ok = false; }
  if !parse_ok("GR1601101250000000012300695") { ok = false; }
  if !parse_ok("CZ6508000000192000145399") { ok = false; }
  if !parse_ok("LU280019400644750000") { ok = false; }
  return assert(ok, "parse: FI/SE/DK/PL/GR/CZ/LU fixtures");
}

fn t4() -> TestResult {
  var ok = iban_length_for_country("DE") == 22;
  if iban_length_for_country("GB") != 22 { ok = false; }
  if iban_length_for_country("FR") != 27 { ok = false; }
  if iban_length_for_country("ES") != 24 { ok = false; }
  if iban_length_for_country("IT") != 27 { ok = false; }
  if iban_length_for_country("NL") != 18 { ok = false; }
  if iban_length_for_country("BE") != 16 { ok = false; }
  if iban_length_for_country("CH") != 21 { ok = false; }
  if iban_length_for_country("AT") != 20 { ok = false; }
  if iban_length_for_country("PT") != 25 { ok = false; }
  if iban_length_for_country("IE") != 22 { ok = false; }
  if iban_length_for_country("FI") != 18 { ok = false; }
  if iban_length_for_country("SE") != 24 { ok = false; }
  if iban_length_for_country("NO") != 15 { ok = false; }
  if iban_length_for_country("DK") != 18 { ok = false; }
  if iban_length_for_country("PL") != 28 { ok = false; }
  if iban_length_for_country("GR") != 27 { ok = false; }
  if iban_length_for_country("CZ") != 24 { ok = false; }
  if iban_length_for_country("LU") != 20 { ok = false; }
  if iban_length_for_country("ZZ") != 0 { ok = false; }
  if iban_length_for_country("de") != 0 { ok = false; }
  if iban_length_for_country("") != 0 { ok = false; }
  return assert(ok, "length table: 19 registered countries; unknown, lowercase and empty are 0");
}

fn t5() -> TestResult {
  var ok = fmt_is("DE89370400440532013000", "DE89 3704 0044 0532 0130 00");
  if !fmt_is("GB82WEST12345698765432", "GB82 WEST 1234 5698 7654 32") { ok = false; }
  if !fmt_is("FR1420041010050500013M02606", "FR14 2004 1010 0505 0001 3M02 606") { ok = false; }
  if !fmt_is("NO9386011117947", "NO93 8601 1117 947") { ok = false; }
  if !fmt_is("PL61109010140000071219812874", "PL61 1090 1014 0000 0712 1981 2874") { ok = false; }
  return assert(ok, "format: space-separated groups of four, final group may be short");
}

fn t6() -> TestResult {
  var ok = compact_is("DE89370400440532013000", "DE89370400440532013000");
  if !compact_is("GB82WEST12345698765432", "GB82WEST12345698765432") { ok = false; }
  if !compact_is("NO9386011117947", "NO9386011117947") { ok = false; }
  return assert(ok, "compact: canonical uppercase round-trip of the fixtures");
}

fn t7() -> TestResult {
  let a = Iban{ country: "DE"; check: 5; bban: "370400440532013000" };
  let b = Iban{ country: "NO"; check: 2; bban: "86011117947" };
  var ok = streq(iban_compact(&a), "DE05370400440532013000");
  if !streq(iban_format(&a), "DE05 3704 0044 0532 0130 00") { ok = false; }
  if !streq(iban_compact(&b), "NO0286011117947") { ok = false; }
  if !streq(iban_format(&b), "NO02 8601 1117 947") { ok = false; }
  return assert(ok, "emit: zero-pads a single-digit check value");
}

fn t8() -> TestResult {
  var ok = check_of("DE", "370400440532013000") == 89;
  if check_of("GB", "WEST12345698765432") != 82 { ok = false; }
  if check_of("FR", "20041010050500013M02606") != 14 { ok = false; }
  if check_of("NO", "86011117947") != 93 { ok = false; }
  if check_of("PL", "109010140000071219812874") != 61 { ok = false; }
  if check_of("LU", "0019400644750000") != 28 { ok = false; }
  return assert(ok, "compute: check digits of six published fixtures");
}

fn t9() -> TestResult {
  var ok = roundtrip("CH", "0076201162385295A", 92);
  if !roundtrip("GR", "01101250000000012300A95", 17) { ok = false; }
  if !roundtrip("LU", "001940064475000A", 87) { ok = false; }
  if !roundtrip("NL", "ABNA0417164300", 91) { ok = false; }
  if !roundtrip("IT", "X0542811101000000123456", 60) { ok = false; }
  if !roundtrip("IE", "AIBK93115212345678", 29) { ok = false; }
  return assert(ok, "compute+parse round-trip: alphanumeric BBANs carrying letters");
}

fn t10() -> TestResult {
  var ok = fields_are("DE02370400440532010007", "DE", 2, "370400440532010007");
  if !fmt_is("DE02370400440532010007", "DE02 3704 0044 0532 0100 07") { ok = false; }
  if !roundtrip("DE", "370400440532010007", 2) { ok = false; }
  return assert(ok, "parse/emit: single-digit check value 02");
}

fn t11() -> TestResult {
  var ok = roundtrip("PL", "999999999999999999999999", 43);
  if !roundtrip("CZ", "99999999999999999999", 75) { ok = false; }
  if !roundtrip("DE", "999999999999999999", 85) { ok = false; }
  if !parse_ok("PL43999999999999999999999999") { ok = false; }
  if !parse_ok("CZ7599999999999999999999") { ok = false; }
  return assert(ok, "MOD-97: all-nines BBANs stay Int-safe digit-wise");
}

fn t12() -> TestResult {
  var ok = parse_ok("DE89370400440532013000");
  if !parse_ok("ES9121000418450200051332") { ok = false; }
  if !parse_ok("BE68539007547034") { ok = false; }
  if !parse_err_is("DE8937040044053201300A", "iban: bad characters: DE8937040044053201300A") { ok = false; }
  if !parse_err_is("ES912100041845020005133A", "iban: bad characters: ES912100041845020005133A") { ok = false; }
  if !parse_err_is("BE6853900754703A", "iban: bad characters: BE6853900754703A") { ok = false; }
  return assert(ok, "charset: numeric-only BBANs reject letters");
}

fn t13() -> TestResult {
  var ok = parse_err_is("de89370400440532013000", "iban: bad characters: de89370400440532013000");
  if !parse_err_is("De89370400440532013000", "iban: bad characters: De89370400440532013000") { ok = false; }
  if !parse_err_is("GB82west12345698765432", "iban: bad characters: GB82west12345698765432") { ok = false; }
  if !parse_err_is("GB82WEST1234569876543a", "iban: bad characters: GB82WEST1234569876543a") { ok = false; }
  if !parse_err_is("D39370400440532013000", "iban: bad characters: D39370400440532013000") { ok = false; }
  return assert(ok, "case: lowercase country or BBAN letters are bad characters");
}

fn t14() -> TestResult {
  var ok = parse_err_is("", "iban: empty input");
  if !parse_err_is("G", "iban: bad characters: G") { ok = false; }
  if !parse_err_is("1B82WEST12345698765432", "iban: bad characters: 1B82WEST12345698765432") { ok = false; }
  if !parse_err_is("GB", "iban: bad length for GB: expected 22, got 2") { ok = false; }
  if !parse_err_is("GB82", "iban: bad length for GB: expected 22, got 4") { ok = false; }
  if !parse_err_is("GB82WEST1234569876543", "iban: bad length for GB: expected 22, got 21") { ok = false; }
  return assert(ok, "errors: empty input, non-letter country, short input");
}

fn t15() -> TestResult {
  var ok = parse_err_is("ZZ89370400440532013000", "iban: unknown country: ZZ");
  if !parse_err_is("AA89370400440532013000", "iban: unknown country: AA") { ok = false; }
  if !parse_err_is("ZZ", "iban: unknown country: ZZ") { ok = false; }
  if iban_is_valid("ZZ89370400440532013000") { ok = false; }
  return assert(ok, "errors: unknown country codes are reported before length");
}

fn t16() -> TestResult {
  var ok = parse_err_is("DE8937040044053201300", "iban: bad length for DE: expected 22, got 21");
  if !parse_err_is("DE893704004405320130001", "iban: bad length for DE: expected 22, got 23") { ok = false; }
  if !parse_err_is("CH930076201162385295", "iban: bad length for CH: expected 21, got 20") { ok = false; }
  if !parse_err_is("DE89 3704 0044 0532 0130 00", "iban: bad length for DE: expected 22, got 27") { ok = false; }
  return assert(ok, "errors: exact bad-length messages; spaced input is rejected");
}

fn t17() -> TestResult {
  var ok = parse_err_is("DE89-70400440532013000", "iban: bad characters: DE89-70400440532013000");
  if !parse_err_is("DE8A370400440532013000", "iban: bad characters: DE8A370400440532013000") { ok = false; }
  if !parse_err_is("GB82WEST1234569876543$", "iban: bad characters: GB82WEST1234569876543$") { ok = false; }
  if !parse_err_is("GR160110125000000001230069$", "iban: bad characters: GR160110125000000001230069$") { ok = false; }
  return assert(ok, "errors: malformed check digits and non-alphanumeric BBAN");
}

fn t18() -> TestResult {
  var ok = parse_err_is("DE89370400440532013001", "iban: bad check digits: DE89370400440532013001");
  if !parse_err_is("DE98370400440532013000", "iban: bad check digits: DE98370400440532013000") { ok = false; }
  if !parse_err_is("GB82WEST12345698765433", "iban: bad check digits: GB82WEST12345698765433") { ok = false; }
  if !parse_err_is("NO9386011117948", "iban: bad check digits: NO9386011117948") { ok = false; }
  return assert(ok, "errors: MOD-97 mismatch reports bad check digits");
}

fn t19() -> TestResult {
  var ok = compute_err_is("DE", "3704", "iban: bad length for DE: expected 22, got 8");
  if !compute_err_is("DE", "37040044053201300A", "iban: bad characters: 37040044053201300A") { ok = false; }
  if !compute_err_is("de", "370400440532013000", "iban: bad characters: de") { ok = false; }
  if !compute_err_is("ZZ", "370400440532013000", "iban: unknown country: ZZ") { ok = false; }
  if !compute_err_is("DEE", "370400440532013000", "iban: bad characters: DEE") { ok = false; }
  if !compute_err_is("", "12", "iban: empty input") { ok = false; }
  if !compute_err_is("DE", "", "iban: empty input") { ok = false; }
  return assert(ok, "compute errors: empty, bad country, unknown, length, charset");
}

fn t20() -> TestResult {
  var ok = iban_is_valid("DE89370400440532013000");
  if !iban_is_valid("GB82WEST12345698765432") { ok = false; }
  if !iban_is_valid("LU280019400644750000") { ok = false; }
  if iban_is_valid("DE89370400440532013001") { ok = false; }
  if iban_is_valid("") { ok = false; }
  if iban_is_valid("de89370400440532013000") { ok = false; }
  return assert(ok, "is_valid: true for valid fixtures, false for every error class");
}

fn t21() -> TestResult {
  var ok = streq(strip_spaces(fmt_of("DE89370400440532013000")), "DE89370400440532013000");
  if !streq(strip_spaces(fmt_of("GB82WEST12345698765432")), "GB82WEST12345698765432") { ok = false; }
  if !streq(strip_spaces(fmt_of("NO9386011117947")), "NO9386011117947") { ok = false; }
  if !streq(strip_spaces(fmt_of("PL43999999999999999999999999")), "PL43999999999999999999999999") { ok = false; }
  return assert(ok, "round-trip: format -> strip spaces -> canonical compact");
}

fn main() -> Int {
  io.println("=== xiom.iban conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.iban: all tests passed");
  } else {
    io.println("xiom.iban: tests failed");
  }
  return failed;
}
