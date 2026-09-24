// XIOM -- xiom.roman conformance tests (16 checks)
// Greenfield package: prove the pure-XIOM xiom.roman module against its
// documented parsing, formatting and canonical-validation contract.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module roman_tests
use xiom.io; use xiom.test; use xiom.roman;
use xiom.string.compare;

// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, and Result/error
// payloads come back as strings, so every string check below is routed
// through streq instead of `==`.

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn parse_is(text: Str, want: Int) -> Bool {
  let r = roman_parse(text);
  match r {
    Ok(v) => { return v == want; },
    Err(_) => { return false; },
  }
  return false;
}

fn parse_is_err(text: Str) -> Bool {
  let r = roman_parse(text);
  match r {
    Ok(_) => { return false; },
    Err(_) => { return true; },
  }
  return true;
}

fn parse_err_message(text: Str, want: Str) -> Bool {
  let r = roman_parse(text);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn format_is(n: Int, want: Str) -> Bool {
  let r = roman_format(n);
  match r {
    Ok(s) => { return streq(s, want); },
    Err(_) => { return false; },
  }
  return false;
}

fn format_is_err(n: Int) -> Bool {
  let r = roman_format(n);
  match r {
    Ok(_) => { return false; },
    Err(_) => { return true; },
  }
  return true;
}

fn format_err_message(n: Int, want: Str) -> Bool {
  let r = roman_format(n);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// True when format(n) succeeds and parses back to n.
fn round_trip_is(n: Int) -> Bool {
  let f = roman_format(n);
  match f {
    Ok(s) => { return parse_is(s, n); },
    Err(_) => { return false; },
  }
  return false;
}

// True when n formats to exactly `want` and `want` parses back to n.
fn round_trips(n: Int, want: Str) -> Bool {
  if !format_is(n, want) { return false; }
  if !parse_is(want, n) { return false; }
  return round_trip_is(n);
}

fn t1_parse_known_values() -> TestResult {
  var ok = parse_is("I", 1);
  if !parse_is("IV", 4) { ok = false; }
  if !parse_is("IX", 9) { ok = false; }
  if !parse_is("XIV", 14) { ok = false; }
  if !parse_is("XL", 40) { ok = false; }
  if !parse_is("XC", 90) { ok = false; }
  if !parse_is("CD", 400) { ok = false; }
  if !parse_is("CM", 900) { ok = false; }
  if !parse_is("MCMXCIV", 1994) { ok = false; }
  if !parse_is("MMMCMXCIX", 3999) { ok = false; }
  return assert(ok, "parse known values I/IV/IX/XIV/XL/XC/CD/CM/MCMXCIV/MMMCMXCIX");
}

fn t2_parse_additive_forms() -> TestResult {
  var ok = parse_is("II", 2);
  if !parse_is("III", 3) { ok = false; }
  if !parse_is("VIII", 8) { ok = false; }
  if !parse_is("LX", 60) { ok = false; }
  if !parse_is("CLX", 160) { ok = false; }
  if !parse_is("MMMDCCCLXXXVIII", 3888) { ok = false; }
  return assert(ok, "parse additive forms and the longest canonical numeral (3888)");
}

fn t3_parse_lowercase_and_mixed() -> TestResult {
  var ok = parse_is("i", 1);
  if !parse_is("iv", 4) { ok = false; }
  if !parse_is("ix", 9) { ok = false; }
  if !parse_is("xiv", 14) { ok = false; }
  if !parse_is("mcmxciv", 1994) { ok = false; }
  if !parse_is("mmmcmxcix", 3999) { ok = false; }
  if !parse_is("McMxCiv", 1994) { ok = false; }
  return assert(ok, "parse is case-insensitive: lowercase and mixed case accepted");
}

fn t4_format_table() -> TestResult {
  var ok = round_trips(1, "I");
  if !round_trips(2, "II") { ok = false; }
  if !round_trips(3, "III") { ok = false; }
  if !round_trips(4, "IV") { ok = false; }
  if !round_trips(5, "V") { ok = false; }
  if !round_trips(9, "IX") { ok = false; }
  if !round_trips(14, "XIV") { ok = false; }
  if !round_trips(40, "XL") { ok = false; }
  if !round_trips(90, "XC") { ok = false; }
  if !round_trips(400, "CD") { ok = false; }
  if !round_trips(900, "CM") { ok = false; }
  if !round_trips(1994, "MCMXCIV") { ok = false; }
  return assert(ok, "format round-trips a 12-value table");
}

fn t5_format_boundaries() -> TestResult {
  var ok = format_is(1, "I");
  if !format_is(3999, "MMMCMXCIX") { ok = false; }
  if !round_trip_is(1) { ok = false; }
  if !round_trip_is(3999) { ok = false; }
  return assert(ok, "format covers the 1 and 3999 boundaries");
}

fn t6_format_out_of_range() -> TestResult {
  var ok = format_is_err(0);
  if !format_is_err(4000) { ok = false; }
  if !format_is_err(0 - 1) { ok = false; }
  if !format_is_err(10000) { ok = false; }
  if !format_err_message(0, "roman: out of range") { ok = false; }
  return assert(ok, "format rejects 0, negatives and values above 3999");
}

fn t7_parse_out_of_range() -> TestResult {
  var ok = parse_is_err("MMMM");
  if !parse_is_err("MMMMM") { ok = false; }
  if !parse_is_err("MMMMCMXCIX") { ok = false; }
  return assert(ok, "parse rejects numerals whose value exceeds 3999");
}

fn t8_parse_empty() -> TestResult {
  var ok = parse_is_err("");
  if !parse_is_err(" ") { ok = false; }
  if !parse_err_message("", "roman: empty input") { ok = false; }
  return assert(ok, "parse rejects the empty string and blank-only input");
}

fn t9_parse_invalid_letters() -> TestResult {
  var ok = parse_is_err("A");
  if !parse_is_err("Z") { ok = false; }
  if !parse_is_err("a") { ok = false; }
  if !parse_is_err("z") { ok = false; }
  if !parse_is_err("Q") { ok = false; }
  if !parse_is_err("123") { ok = false; }
  if !parse_is_err("I V") { ok = false; }
  return assert(ok, "parse rejects letters outside I,V,X,L,C,D,M and non-letters");
}

fn t10_parse_invalid_placements() -> TestResult {
  var ok = parse_is_err("IIII");
  if !parse_is_err("VX") { ok = false; }
  if !parse_is_err("IL") { ok = false; }
  if !parse_is_err("XD") { ok = false; }
  if !parse_is_err("MMMM") { ok = false; }
  if !parse_is_err("VIV") { ok = false; }
  if !parse_is_err("IIX") { ok = false; }
  if !parse_is_err("IC") { ok = false; }
  if !parse_is_err("XM") { ok = false; }
  return assert(ok, "parse rejects invalid placements IIII/VX/IL/XD/MMMM/VIV/IIX/IC/XM");
}

fn t11_canonical_true() -> TestResult {
  var ok = roman_is_canonical("I");
  if !roman_is_canonical("IV") { ok = false; }
  if !roman_is_canonical("XIV") { ok = false; }
  if !roman_is_canonical("MCMXCIV") { ok = false; }
  if !roman_is_canonical("MMMCMXCIX") { ok = false; }
  if !roman_is_canonical("MMMDCCCLXXXVIII") { ok = false; }
  return assert(ok, "canonical is true for uppercase canonical forms");
}

fn t12_canonical_false() -> TestResult {
  var ok = !roman_is_canonical("IIII");
  if roman_is_canonical("iv") { ok = false; }
  if roman_is_canonical("mcmxciv") { ok = false; }
  if roman_is_canonical("VX") { ok = false; }
  if roman_is_canonical("IL") { ok = false; }
  if roman_is_canonical("MMMM") { ok = false; }
  if roman_is_canonical("") { ok = false; }
  if roman_is_canonical("MCMXCIV ") { ok = false; }
  return assert(ok, "canonical is false for additive, illegal, lowercase and padded input");
}

fn t13_max_pinned() -> TestResult {
  var ok = roman_max() == 3999;
  if !format_is(roman_max(), "MMMCMXCIX") { ok = false; }
  if !parse_is("MMMCMXCIX", roman_max()) { ok = false; }
  if !format_is(roman_max() - 1, "MMMCMXCVIII") { ok = false; }
  return assert(ok, "roman_max is pinned at 3999 = MMMCMXCIX");
}

fn t14_round_trip_loop() -> TestResult {
  var ok = true;
  var n = 1;
  while n <= 50 {
    if !round_trip_is(n) { ok = false; }
    n = n + 1;
  }
  return assert(ok, "parse(format(n)) == n for every n in 1..50");
}

fn t15_error_catalog() -> TestResult {
  var ok = parse_err_message("", "roman: empty input");
  if !parse_err_message("A", "roman: invalid character: A") { ok = false; }
  if !parse_err_message("a", "roman: invalid character: a") { ok = false; }
  if !parse_err_message("IIII", "roman: not canonical") { ok = false; }
  if !parse_err_message("MMMM", "roman: out of range") { ok = false; }
  if !format_err_message(0, "roman: out of range") { ok = false; }
  if !format_err_message(4000, "roman: out of range") { ok = false; }
  return assert(ok, "the documented error catalog is stable");
}

fn t16_format_samples() -> TestResult {
  var ok = round_trips(49, "XLIX");
  if !round_trips(944, "CMXLIV") { ok = false; }
  if !round_trips(1066, "MLXVI") { ok = false; }
  if !round_trips(2024, "MMXXIV") { ok = false; }
  if !round_trips(3888, "MMMDCCCLXXXVIII") { ok = false; }
  return assert(ok, "format round-trips sampled values XLIX/CMXLIV/MLXVI/MMXXIV/3888");
}

fn main() -> Int {
  io.println("=== xiom.roman conformance tests ===");
  var failed: Int = 0;
  let r1 = t1_parse_known_values();
  if r1.passed { io.println("  [PASS] " + r1.name); } else { io.println("  [FAIL] " + r1.name); failed = failed + 1; }
  let r2 = t2_parse_additive_forms();
  if r2.passed { io.println("  [PASS] " + r2.name); } else { io.println("  [FAIL] " + r2.name); failed = failed + 1; }
  let r3 = t3_parse_lowercase_and_mixed();
  if r3.passed { io.println("  [PASS] " + r3.name); } else { io.println("  [FAIL] " + r3.name); failed = failed + 1; }
  let r4 = t4_format_table();
  if r4.passed { io.println("  [PASS] " + r4.name); } else { io.println("  [FAIL] " + r4.name); failed = failed + 1; }
  let r5 = t5_format_boundaries();
  if r5.passed { io.println("  [PASS] " + r5.name); } else { io.println("  [FAIL] " + r5.name); failed = failed + 1; }
  let r6 = t6_format_out_of_range();
  if r6.passed { io.println("  [PASS] " + r6.name); } else { io.println("  [FAIL] " + r6.name); failed = failed + 1; }
  let r7 = t7_parse_out_of_range();
  if r7.passed { io.println("  [PASS] " + r7.name); } else { io.println("  [FAIL] " + r7.name); failed = failed + 1; }
  let r8 = t8_parse_empty();
  if r8.passed { io.println("  [PASS] " + r8.name); } else { io.println("  [FAIL] " + r8.name); failed = failed + 1; }
  let r9 = t9_parse_invalid_letters();
  if r9.passed { io.println("  [PASS] " + r9.name); } else { io.println("  [FAIL] " + r9.name); failed = failed + 1; }
  let r10 = t10_parse_invalid_placements();
  if r10.passed { io.println("  [PASS] " + r10.name); } else { io.println("  [FAIL] " + r10.name); failed = failed + 1; }
  let r11 = t11_canonical_true();
  if r11.passed { io.println("  [PASS] " + r11.name); } else { io.println("  [FAIL] " + r11.name); failed = failed + 1; }
  let r12 = t12_canonical_false();
  if r12.passed { io.println("  [PASS] " + r12.name); } else { io.println("  [FAIL] " + r12.name); failed = failed + 1; }
  let r13 = t13_max_pinned();
  if r13.passed { io.println("  [PASS] " + r13.name); } else { io.println("  [FAIL] " + r13.name); failed = failed + 1; }
  let r14 = t14_round_trip_loop();
  if r14.passed { io.println("  [PASS] " + r14.name); } else { io.println("  [FAIL] " + r14.name); failed = failed + 1; }
  let r15 = t15_error_catalog();
  if r15.passed { io.println("  [PASS] " + r15.name); } else { io.println("  [FAIL] " + r15.name); failed = failed + 1; }
  let r16 = t16_format_samples();
  if r16.passed { io.println("  [PASS] " + r16.name); } else { io.println("  [FAIL] " + r16.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.roman: all tests passed");
  } else {
    io.println("xiom.roman: tests failed");
  }
  return failed;
}
