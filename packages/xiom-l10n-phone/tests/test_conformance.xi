// XIOM -- xiom.l10n.phone conformance tests (23 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Provenance: every fixture is a synthetic string built in-test (no real
// subscriber data). Country codes, ISO alpha-2 codes and the minimum
// national lengths pinned here are taken from the embedded table of the
// module under test and from ITU-T E.164 / national numbering-plan notes;
// the table-integrity checks sample the documented rows.
//
// BUG 17 note: all Str equality goes through str_compare (via streq); no
// test indexes a Vec[Str], and every library call receives plain locals.
// Compiler note: test dispatch is a direct call chain (t1..t22 from main),
// never a Vec[fn] table.

module l10n_phone_tests
use xiom.io; use xiom.test;
use xiom.l10n.phone;
use xiom.string.compare;
use xiom.convert;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// ---------------------------------------------------------------------------
// Result probes (never compare Str with ==; always return typed locals)
// ---------------------------------------------------------------------------

fn parse_ok(s: Str) -> Bool {
  match phone_parse(s) {
    Ok(v) => { return true; },
    Err(e) => { return false; },
  }
}

fn parse_err_is(s: Str, want: Str) -> Bool {
  match phone_parse(s) {
    Ok(v) => { return false; },
    Err(e) => { return streq(e, want); },
  }
}

fn dummy_number() -> PhoneNumber {
  let none = Vec[Int].new();
  let d = PhoneNumber{ country_code: ""; iso: ""; national: ""; extension: ""; digit_offsets: none };
  return d;
}

fn parse_or_dummy(s: Str) -> PhoneNumber {
  match phone_parse(s) {
    Ok(v) => { return v; },
    Err(e) => { return dummy_number(); },
  }
}

fn fields_are(s: Str, cc: Str, iso: Str, nat: Str, ext: Str) -> Bool {
  let v = parse_or_dummy(s);
  let a: Str = phone_country_code(&v);
  let b: Str = phone_iso(&v);
  let c: Str = phone_national(&v);
  let d: Str = phone_extension(&v);
  return streq(a, cc) && streq(b, iso) && streq(c, nat) && streq(d, ext);
}

fn e164_of(s: Str) -> Str {
  let v = parse_or_dummy(s);
  return phone_e164(&v);
}

fn intl_of(s: Str) -> Str {
  let v = parse_or_dummy(s);
  return phone_international(&v);
}

fn mask_of(s: Str) -> Str {
  let v = parse_or_dummy(s);
  return phone_mask(&v);
}

fn uri_of(s: Str) -> Str {
  let v = parse_or_dummy(s);
  return phone_tel_uri(&v);
}

fn count_of(s: Str) -> Int {
  let v = parse_or_dummy(s);
  return phone_digit_count(&v);
}

fn off_of(s: Str, i: Int) -> Int {
  let v = parse_or_dummy(s);
  return phone_digit_offset(&v, i);
}

fn uri_ok_eq(s: Str, want: Str) -> Bool {
  match phone_parse_tel_uri(s) {
    Ok(v) => { return streq(phone_tel_uri(&v), want); },
    Err(e) => { return false; },
  }
}

fn uri_fields_are(s: Str, cc: Str, nat: Str, ext: Str) -> Bool {
  match phone_parse_tel_uri(s) {
    Ok(v) => {
      let a: Str = phone_country_code(&v);
      let b: Str = phone_national(&v);
      let c: Str = phone_extension(&v);
      return streq(a, cc) && streq(b, nat) && streq(c, ext);
    },
    Err(e) => { return false; },
  }
}

fn uri_off_of(s: Str, i: Int) -> Int {
  match phone_parse_tel_uri(s) {
    Ok(v) => { return phone_digit_offset(&v, i); },
    Err(e) => { return -1; },
  }
}

fn uri_err_is(s: Str, want: Str) -> Bool {
  match phone_parse_tel_uri(s) {
    Ok(v) => { return false; },
    Err(e) => { return streq(e, want); },
  }
}

fn eq_of(a: Str, b: Str) -> Bool {
  let va = parse_or_dummy(a);
  let vb = parse_or_dummy(b);
  let ra: Str = phone_raw_digits(&va);
  let rb: Str = phone_raw_digits(&vb);
  if ra.len() == 0 { return false; }
  if rb.len() == 0 { return false; }
  return phone_equals(&va, &vb);
}

fn roundtrip_ok(s: Str) -> Bool {
  let v = parse_or_dummy(s);
  let raw: Str = phone_raw_digits(&v);
  if raw.len() == 0 { return false; }
  let e = phone_e164(&v);
  let w = parse_or_dummy(e);
  return streq(phone_e164(&w), e) && phone_equals(&v, &w);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

fn t1() -> TestResult {
  var ok = fields_are("+1 202 555 0147", "1", "US", "2025550147", "");
  if !fields_are("14155552671", "1", "US", "4155552671", "") { ok = false; }
  if !fields_are("+7 999 123 4567", "7", "RU", "9991234567", "") { ok = false; }
  if !streq(e164_of("+1 202 555 0147"), "+12025550147") { ok = false; }
  if !streq(e164_of("14155552671"), "+14155552671") { ok = false; }
  if !streq(e164_of("+7 999 123 4567"), "+79991234567") { ok = false; }
  return assert(ok, "parse: 1-digit country codes 1 and 7 in +, 00 and bare shapes");
}

fn t2() -> TestResult {
  var ok = fields_are("+44 20 7946 0958", "44", "GB", "2079460958", "");
  if !fields_are("0049-30-1234567", "49", "DE", "301234567", "") { ok = false; }
  if !fields_are("+33 1 42 68 53 00", "33", "FR", "142685300", "") { ok = false; }
  if !fields_are("+81 3 1234 5678", "81", "JP", "312345678", "") { ok = false; }
  if !fields_are("+86 138 0013 8000", "86", "CN", "13800138000", "") { ok = false; }
  if !fields_are("+65 8123 4567", "65", "SG", "81234567", "") { ok = false; }
  return assert(ok, "parse: 2-digit country codes (GB/DE/FR/JP/CN/SG)");
}

fn t3() -> TestResult {
  var ok = fields_are("+212 6 61 23 45 67", "212", "MA", "661234567", "");
  if !fields_are("+351 912 345 678", "351", "PT", "912345678", "") { ok = false; }
  if !fields_are("+998 90 123 45 67", "998", "UZ", "901234567", "") { ok = false; }
  if !fields_are("+679 123 4567", "679", "FJ", "1234567", "") { ok = false; }
  if !fields_are("+423 234 56 78", "423", "LI", "2345678", "") { ok = false; }
  return assert(ok, "parse: 3-digit country codes (MA/PT/UZ/FJ/LI)");
}

fn t4() -> TestResult {
  var ok = streq(e164_of("+1 (202) 555-0147"), "+12025550147");
  if !streq(e164_of("00 49.30.1234567"), "+49301234567") { ok = false; }
  if !streq(e164_of("+ 44 20 7946 0958"), "+442079460958") { ok = false; }
  if count_of("+1 (202) 555-0147") != 11 { ok = false; }
  if off_of("+1 (202) 555-0147", 0) != 1 { ok = false; }
  if off_of("+1 (202) 555-0147", 3) != 6 { ok = false; }
  if off_of("+1 (202) 555-0147", 7) != 13 { ok = false; }
  if off_of("+1 (202) 555-0147", 10) != 16 { ok = false; }
  if off_of("+1 (202) 555-0147", 11) != 0 - 1 { ok = false; }
  if off_of("+1 (202) 555-0147", 0 - 1) != 0 - 1 { ok = false; }
  if off_of("00 49.30.1234567", 2) != 6 { ok = false; }
  return assert(ok, "separators: stripped, digit offsets preserved, out-of-range is -1");
}

fn t5() -> TestResult {
  var ok = parse_ok("+123456789012345");
  if !streq(e164_of("+123456789012345"), "+123456789012345") { ok = false; }
  if count_of("+123456789012345") != 15 { ok = false; }
  if !parse_ok("+441234567890123") { ok = false; }
  if count_of("+441234567890123") != 15 { ok = false; }
  if !parse_ok("00 1 234 567 890 123 4") { ok = false; }
  return assert(ok, "E.164 boundary: exactly 15 digits parse");
}

fn t6() -> TestResult {
  var ok = parse_err_is("+1234567890123456", "phone: more than 15 digits (E.164 max) at offset 16");
  if !parse_err_is("+4412345678901234", "phone: more than 15 digits (E.164 max) at offset 16") { ok = false; }
  if !parse_err_is("001234567890123456", "phone: more than 15 digits (E.164 max) at offset 17") { ok = false; }
  return assert(ok, "E.164 boundary: a 16th digit is rejected with its offset");
}

fn t7() -> TestResult {
  var ok = fields_are("+1 202 555 0147 x89", "1", "US", "2025550147", "89");
  if !fields_are("0044 20 7946 0958 ext 42", "44", "GB", "2079460958", "42") { ok = false; }
  if !fields_are("+442079460958;ext=7", "44", "GB", "2079460958", "7") { ok = false; }
  if !fields_are("+442079460958X007", "44", "GB", "2079460958", "007") { ok = false; }
  if !fields_are("+49 30 1234567 EXT 123", "49", "DE", "301234567", "123") { ok = false; }
  if !streq(e164_of("+1 202 555 0147 x89"), "+12025550147") { ok = false; }
  if !streq(uri_of("+1 202 555 0147 x89"), "tel:+12025550147;ext=89") { ok = false; }
  if !streq(intl_of("+1 202 555 0147 x89"), "+1 2 025 550 147 x89") { ok = false; }
  return assert(ok, "extensions: x, ext, ;ext= (case insensitive), excluded from E.164");
}

fn t8() -> TestResult {
  var ok = streq(uri_of("+1 202 555 0147"), "tel:+12025550147");
  if !streq(uri_of("+1 202 555 0147 x89"), "tel:+12025550147;ext=89") { ok = false; }
  if !uri_ok_eq("tel:+442079460958", "tel:+442079460958") { ok = false; }
  if !uri_ok_eq("tel:+442079460958;ext=42", "tel:+442079460958;ext=42") { ok = false; }
  if !uri_ok_eq("tel:%2B442079460958", "tel:+442079460958") { ok = false; }
  if !uri_ok_eq("TEL:+442079460958", "tel:+442079460958") { ok = false; }
  if !uri_fields_are("tel:%2B442079460958;ext=5", "44", "2079460958", "5") { ok = false; }
  if uri_off_of("tel:%2B442079460958", 0) != 7 { ok = false; }
  if uri_off_of("tel:+442079460958", 0) != 5 { ok = false; }
  return assert(ok, "tel URI: build, parse, %2B and TEL: forms, input offsets");
}

fn t9() -> TestResult {
  var ok = uri_err_is("http://example.com", "phone: not a tel URI at offset 0");
  if !uri_err_is("", "phone: not a tel URI at offset 0") { ok = false; }
  if !uri_err_is("tel", "phone: not a tel URI at offset 0") { ok = false; }
  if !uri_err_is("tel:", "phone: tel URI missing '+' or '%2B' at offset 4") { ok = false; }
  if !uri_err_is("tel:442079460958", "phone: tel URI missing '+' or '%2B' at offset 4") { ok = false; }
  if !uri_err_is("tel:+442079460958;ext=", "phone: empty extension at offset 17") { ok = false; }
  if !uri_err_is("tel:+442079460", "phone: national number too short for GB: 7 digits, minimum 10 at offset 7") { ok = false; }
  return assert(ok, "tel URI errors: scheme, prefix, empty extension, body errors with URI offsets");
}

fn t10() -> TestResult {
  var ok = streq(intl_of("+351 912 345 678"), "+351 912 345 678");
  if !streq(intl_of("+44 20 7946 0958"), "+44 2 079 460 958") { ok = false; }
  if !streq(intl_of("+86 138 0013 8000"), "+86 13 800 138 000") { ok = false; }
  if !streq(intl_of("+690 1234"), "+690 1 234") { ok = false; }
  if !streq(mask_of("+1 (202) 555-0147"), "+1******0147") { ok = false; }
  if !streq(mask_of("+679 123 4567"), "+679***4567") { ok = false; }
  if !streq(mask_of("+690 1234"), "+690****") { ok = false; }
  if !streq(mask_of("+351 912 345 678"), "+351*****5678") { ok = false; }
  return assert(ok, "format: 3-from-the-right grouping and masked national digits");
}

fn t11() -> TestResult {
  let v = parse_or_dummy("+44 20 7946 0958 x42");
  let c: Str = phone_country_code(&v);
  let i: Str = phone_iso(&v);
  let n: Str = phone_national(&v);
  let x: Str = phone_extension(&v);
  let r: Str = phone_raw_digits(&v);
  var ok = streq(c, "44");
  if !streq(i, "GB") { ok = false; }
  if !streq(n, "2079460958") { ok = false; }
  if !streq(x, "42") { ok = false; }
  if !streq(r, "442079460958") { ok = false; }
  if phone_digit_count(&v) != 12 { ok = false; }
  if phone_digit_offset(&v, 0) != 1 { ok = false; }
  if phone_digit_offset(&v, 11) != 15 { ok = false; }
  if phone_digit_offset(&v, 12) != 0 - 1 { ok = false; }
  if phone_digit_offset(&v, 0 - 5) != 0 - 1 { ok = false; }
  return assert(ok, "accessors: country, ISO, national, extension, raw digits, offsets");
}

fn t12() -> TestResult {
  var ok = eq_of("+44 20 7946 0958", "0044-20-7946-0958");
  if !eq_of("+442079460958", "44 20 7946 0958") { ok = false; }
  if !eq_of("+44 20 7946 0958 x9", "+442079460958") { ok = false; }
  if eq_of("+44 20 7946 0958", "+44 20 7946 0959") { ok = false; }
  if eq_of("+44 20 7946 0958", "+7 999 123 4567") { ok = false; }
  return assert(ok, "equality: canonical digits, extension-independent, differences detected");
}

fn t13() -> TestResult {
  var ok = phone_min_length("1") == 10;
  if phone_min_length("7") != 10 { ok = false; }
  if phone_min_length("44") != 10 { ok = false; }
  if phone_min_length("33") != 9 { ok = false; }
  if phone_min_length("49") != 9 { ok = false; }
  if phone_min_length("81") != 9 { ok = false; }
  if phone_min_length("86") != 9 { ok = false; }
  if phone_min_length("212") != 9 { ok = false; }
  if phone_min_length("351") != 9 { ok = false; }
  if phone_min_length("998") != 9 { ok = false; }
  if phone_min_length("679") != 7 { ok = false; }
  if phone_min_length("690") != 4 { ok = false; }
  if phone_min_length("999") != 0 { ok = false; }
  if phone_min_length("24") != 0 { ok = false; }
  if phone_min_length("1234") != 0 { ok = false; }
  if phone_min_length("") != 0 { ok = false; }
  return assert(ok, "table: documented minimum national lengths; unknown codes are 0");
}

fn t14() -> TestResult {
  var ok = streq(phone_iso_for_code("1"), "US");
  if !streq(phone_iso_for_code("7"), "RU") { ok = false; }
  if !streq(phone_iso_for_code("44"), "GB") { ok = false; }
  if !streq(phone_iso_for_code("49"), "DE") { ok = false; }
  if !streq(phone_iso_for_code("61"), "AU") { ok = false; }
  if !streq(phone_iso_for_code("81"), "JP") { ok = false; }
  if !streq(phone_iso_for_code("86"), "CN") { ok = false; }
  if !streq(phone_iso_for_code("212"), "MA") { ok = false; }
  if !streq(phone_iso_for_code("351"), "PT") { ok = false; }
  if !streq(phone_iso_for_code("998"), "UZ") { ok = false; }
  if !streq(phone_iso_for_code("690"), "TK") { ok = false; }
  if !streq(phone_iso_for_code("999"), "") { ok = false; }
  if !streq(phone_iso_for_code("4"), "") { ok = false; }
  let pv = parse_or_dummy("+44 20 7946 0958");
  if !streq(phone_iso(&pv), "GB") { ok = false; }
  return assert(ok, "table: ISO alpha-2 lookups and the parsed number's ISO");
}

fn t15() -> TestResult {
  var ok = parse_err_is("+442079460", "phone: national number too short for GB: 7 digits, minimum 10 at offset 3");
  if !parse_err_is("123", "phone: national number too short for US: 2 digits, minimum 10 at offset 1") { ok = false; }
  if !parse_err_is("+351912345", "phone: national number too short for PT: 6 digits, minimum 9 at offset 4") { ok = false; }
  if !parse_err_is("+690 12", "phone: national number too short for TK: 2 digits, minimum 4 at offset 5") { ok = false; }
  return assert(ok, "validation: national shorter than the table minimum is rejected");
}

fn t16() -> TestResult {
  var ok = parse_err_is("+44 020 7946 0958", "phone: national number starts with zero at offset 4");
  if !parse_err_is("+1 020 555 0147", "phone: national number starts with zero at offset 3") { ok = false; }
  if !parse_err_is("+39 06 6982", "phone: national number starts with zero at offset 4") { ok = false; }
  if parse_ok("+4402079460958") { ok = false; }
  return assert(ok, "validation: a national number starting with zero is rejected (trunk prefix)");
}

fn t17() -> TestResult {
  var ok = parse_err_is("+999 123 4567", "phone: unknown country code '999' at offset 1");
  if !parse_err_is("999 123 4567", "phone: unknown country code '999' at offset 0") { ok = false; }
  if !parse_err_is("+0234567890", "phone: unknown country code '023' at offset 1") { ok = false; }
  if !parse_err_is("0", "phone: unknown country code '0' at offset 0") { ok = false; }
  if !parse_err_is("+012345", "phone: unknown country code '012' at offset 1") { ok = false; }
  if !parse_ok("+12425550147") { ok = false; }
  if !fields_are("+12425550147", "1", "US", "2425550147", "") { ok = false; }
  return assert(ok, "unknown country codes report up to three leading digits with the offset");
}

fn t18() -> TestResult {
  var ok = parse_err_is("+44@2079460958", "phone: unexpected character '@' at offset 3");
  if !parse_err_is("++442079460958", "phone: unexpected character '+' at offset 1") { ok = false; }
  if !parse_err_is("+442079460958 garbage", "phone: unexpected character 'g' at offset 14") { ok = false; }
  if !parse_err_is("+44 20 7946 0958#1", "phone: unexpected character '#' at offset 16") { ok = false; }
  if !parse_err_is("+44_2079460958", "phone: unexpected character '_' at offset 3") { ok = false; }
  return assert(ok, "parsing: non-digit text after the prefix is rejected with its offset");
}

fn t19() -> TestResult {
  var ok = parse_err_is("", "phone: empty input");
  if !parse_err_is("+", "phone: empty national number at offset 1") { ok = false; }
  if !parse_err_is("00", "phone: empty national number at offset 2") { ok = false; }
  if !parse_err_is("+44", "phone: empty national number at offset 3") { ok = false; }
  if !parse_err_is("+44x5", "phone: empty national number at offset 3") { ok = false; }
  if !parse_err_is("+44 ( )", "phone: empty national number at offset 3") { ok = false; }
  if !parse_err_is("+44x", "phone: empty extension at offset 3") { ok = false; }
  return assert(ok, "empty inputs: missing digits and markers are rejected with offsets");
}

fn t20() -> TestResult {
  var ok = phone_is_valid("+1 202 555 0147");
  if !phone_is_valid("0044-20-7946-0958") { ok = false; }
  if !phone_is_valid("+679 123 4567") { ok = false; }
  if phone_is_valid("") { ok = false; }
  if phone_is_valid("+") { ok = false; }
  if phone_is_valid("+442079460") { ok = false; }
  if phone_is_valid("+999 123 4567") { ok = false; }
  if phone_is_valid("+44 020 7946 0958") { ok = false; }
  if phone_is_valid("+1234567890123456") { ok = false; }
  return assert(ok, "is_valid: true for valid numbers, false for every error class");
}

fn t21() -> TestResult {
  var ok = roundtrip_ok("+1 202 555 0147");
  if !roundtrip_ok("0049-30-1234567") { ok = false; }
  if !roundtrip_ok("+351 912 345 678") { ok = false; }
  if !roundtrip_ok("+679 123 4567") { ok = false; }
  if !roundtrip_ok("+212 6 61 23 45 67") { ok = false; }
  if !roundtrip_ok("+123456789012345") { ok = false; }
  if !roundtrip_ok("+1 202 555 0147 x89") { ok = false; }
  return assert(ok, "round-trip: parse -> E.164 -> parse keeps digits and equality");
}

fn t22() -> TestResult {
  var ok = phone_country_count() == 200;
  if phone_country_count() < 80 { ok = false; }
  let none_a = Vec[Int].new();
  let a = PhoneNumber{ country_code: "1"; iso: "US"; national: "2025550147"; extension: ""; digit_offsets: none_a };
  if !streq(phone_e164(&a), "+12025550147") { ok = false; }
  if !streq(phone_international(&a), "+1 2 025 550 147") { ok = false; }
  if !streq(phone_mask(&a), "+1******0147") { ok = false; }
  if !streq(phone_tel_uri(&a), "tel:+12025550147") { ok = false; }
  if phone_digit_count(&a) != 11 { ok = false; }
  if phone_digit_offset(&a, 0) != 0 - 1 { ok = false; }
  return assert(ok, "table size and hand-built value: emitters and empty offset vector");
}

fn t23() -> TestResult {
  let none_b = Vec[Int].new();
  let a = PhoneNumber{ country_code: "1"; iso: "US"; national: "2025550147"; extension: ""; digit_offsets: none_b };
  let none_c = Vec[Int].new();
  let b = PhoneNumber{ country_code: "1"; iso: "US"; national: "2025550147"; extension: "89"; digit_offsets: none_c };
  let none_d = Vec[Int].new();
  let c = PhoneNumber{ country_code: "7"; iso: "RU"; national: "2025550147"; extension: ""; digit_offsets: none_d };
  var ok = phone_equals(&a, &b);
  if phone_equals(&a, &c) { ok = false; }
  if !streq(phone_tel_uri(&b), "tel:+12025550147;ext=89") { ok = false; }
  if !streq(phone_international(&b), "+1 2 025 550 147 x89") { ok = false; }
  if !streq(phone_raw_digits(&b), "12025550147") { ok = false; }
  return assert(ok, "equality: extension-independent; extension rendered by URI and grouped forms");
}

fn main() -> Int {
  io.println("=== xiom.l10n.phone conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.l10n-phone: all tests passed");
  } else {
    io.println("xiom.l10n-phone: tests failed");
  }
  return failed;
}
