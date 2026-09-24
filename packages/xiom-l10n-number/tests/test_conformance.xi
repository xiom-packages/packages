// XIOM -- xiom.l10n.number conformance tests (30 checks)
// Port task: prove the pure-XIOM xiom.l10n.number module against its
// documented scaled-integer formatting, rounding and parsing contract.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module l10n_number_tests
use xiom.io; use xiom.test; use xiom.l10n.number;
use xiom.string; use xiom.string.compare;

// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, and the parse errors
// come back as Result payloads; every string check below is routed through
// streq instead of `==`.

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn parse_is(text: Str, sep: Str, dec: Int, want: Int) -> Bool {
  let r = l10n_decimal_parse(text, sep, dec);
  match r {
    Ok(v) => { return v == want; },
    Err(_) => { return false; },
  }
  return false;
}

fn parse_err_is(text: Str, sep: Str, dec: Int, want: Str) -> Bool {
  let r = l10n_decimal_parse(text, sep, dec);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn t1() -> TestResult {
  var ok = streq(l10n_int_format(1000, ","), "1,000");
  if !streq(l10n_int_format(999, ","), "999") { ok = false; }
  if !streq(l10n_int_format(100, ","), "100") { ok = false; }
  if !streq(l10n_int_format(12, ","), "12") { ok = false; }
  return assert(ok, "grouping: 1000 -> 1,000 and values below need none");
}

fn t2() -> TestResult {
  var ok = streq(l10n_int_format(1000000, ","), "1,000,000");
  if !streq(l10n_int_format(1234567, ","), "1,234,567") { ok = false; }
  if !streq(l10n_int_format(100000, ","), "100,000") { ok = false; }
  if !streq(l10n_int_format(12345, ","), "12,345") { ok = false; }
  return assert(ok, "grouping: millions and mid-size values group from the right");
}

fn t3() -> TestResult {
  var ok = streq(l10n_int_format(-1000, ","), "-1,000");
  if !streq(l10n_int_format(-999, ","), "-999") { ok = false; }
  if !streq(l10n_int_format(-1, ","), "-1") { ok = false; }
  if !streq(l10n_int_format(-1234567, ","), "-1,234,567") { ok = false; }
  return assert(ok, "grouping: negative sign is emitted once, before the groups");
}

fn t4() -> TestResult {
  var ok = streq(l10n_int_format(0, ","), "0");
  if !streq(l10n_int_format(0, ""), "0") { ok = false; }
  if !streq(l10n_int_format(0, " "), "0") { ok = false; }
  return assert(ok, "grouping: zero is plain 0 for every separator");
}

fn t5() -> TestResult {
  var ok = streq(l10n_int_format(1234567, "."), "1.234.567");
  if !streq(l10n_int_format(1234567, "_"), "1_234_567") { ok = false; }
  if !streq(l10n_int_format(1234567, " "), "1 234 567") { ok = false; }
  if !streq(l10n_int_format(1234567, ""), "1234567") { ok = false; }
  if !streq(l10n_int_format(123456, "::"), "123::456") { ok = false; }
  return assert(ok, "custom group separators, including empty and multi-char");
}

fn t6() -> TestResult {
  let int_min = 0 - 9223372036854775807 - 1;
  var ok = streq(l10n_int_format(9223372036854775807, ","), "9,223,372,036,854,775,807");
  if !streq(l10n_int_format(int_min, ","), "-9,223,372,036,854,775,808") { ok = false; }
  if !streq(l10n_int_format(int_min, ""), "-9223372036854775808") { ok = false; }
  return assert(ok, "big integers group exactly, including the 64-bit minimum");
}

fn t7() -> TestResult {
  var ok = streq(l10n_decimal_format(12345, 1, ",", "."), "1,234.5");
  if !streq(l10n_decimal_format(-12345, 1, ",", "."), "-1,234.5") { ok = false; }
  if !streq(l10n_decimal_format(5, 1, ",", "."), "0.5") { ok = false; }
  return assert(ok, "decimal format with one fraction digit");
}

fn t8() -> TestResult {
  var ok = streq(l10n_decimal_format(12345, 2, ",", "."), "123.45");
  if !streq(l10n_decimal_format(12345, 3, ",", "."), "12.345") { ok = false; }
  if !streq(l10n_decimal_format(123, 3, ",", "."), "0.123") { ok = false; }
  return assert(ok, "decimal format with two and three fraction digits");
}

fn t9() -> TestResult {
  var ok = streq(l10n_decimal_format(12345, 0, ",", "."), "12,345");
  if !streq(l10n_decimal_format(-12345, 0, ",", "."), "-12,345") { ok = false; }
  if !streq(l10n_decimal_format(0, 0, ",", "."), "0") { ok = false; }
  return assert(ok, "decimal format with zero decimals is plain integer formatting");
}

fn t10() -> TestResult {
  var ok = streq(l10n_decimal_format(5, 3, ",", "."), "0.005");
  if !streq(l10n_decimal_format(50, 3, ",", "."), "0.050") { ok = false; }
  if !streq(l10n_decimal_format(0, 2, ",", "."), "0.00") { ok = false; }
  if !streq(l10n_decimal_format(12345678, 4, ",", "."), "1,234.5678") { ok = false; }
  return assert(ok, "fraction digits are zero-padded and the integer part is grouped");
}

fn t11() -> TestResult {
  var ok = streq(l10n_decimal_format(-5, 2, ",", "."), "-0.05");
  if !streq(l10n_decimal_format(-12345, 2, ".", ","), "-123,45") { ok = false; }
  if !streq(l10n_decimal_format(-50, 3, ",", "."), "-0.050") { ok = false; }
  return assert(ok, "negative decimal values keep one sign; locale pair is swappable");
}

fn t12() -> TestResult {
  var ok = streq(l10n_decimal_format(12345, -1, ",", "."), "12,345");
  if !streq(l10n_decimal_format(5, -3, ",", "."), "5") { ok = false; }
  if !streq(l10n_decimal_format(1234, 2, ",", ""), "1234") { ok = false; }
  return assert(ok, "negative decimals clamp to zero; empty decimal_sep concatenates");
}

fn t13() -> TestResult {
  var ok = l10n_decimal_round(15, 1, 0) == 2;
  if l10n_decimal_round(14, 1, 0) != 1 { ok = false; }
  if l10n_decimal_round(5, 1, 0) != 1 { ok = false; }
  if l10n_decimal_round(4, 1, 0) != 0 { ok = false; }
  if l10n_decimal_round(0, 1, 0) != 0 { ok = false; }
  return assert(ok, "rounding halves away from zero for positive values");
}

fn t14() -> TestResult {
  var ok = l10n_decimal_round(-15, 1, 0) == -2;
  if l10n_decimal_round(-14, 1, 0) != -1 { ok = false; }
  if l10n_decimal_round(-5, 1, 0) != -1 { ok = false; }
  if l10n_decimal_round(-4, 1, 0) != 0 { ok = false; }
  if l10n_decimal_round(-1, 1, 0) != 0 { ok = false; }
  return assert(ok, "rounding halves away from zero for negative values");
}

fn t15() -> TestResult {
  var ok = l10n_decimal_round(999, 1, 0) == 100;
  if l10n_decimal_round(995, 1, 0) != 100 { ok = false; }
  if l10n_decimal_round(994, 1, 0) != 99 { ok = false; }
  if l10n_decimal_round(123456, 3, 1) != 1235 { ok = false; }
  if l10n_decimal_round(-995, 1, 0) != -100 { ok = false; }
  return assert(ok, "rounding propagates carries across several digits");
}

fn t16() -> TestResult {
  var ok = l10n_decimal_round(1234, 2, 2) == 1234;
  if l10n_decimal_round(1234, 2, 7) != 1234 { ok = false; }
  if l10n_decimal_round(1234, 0, 0) != 1234 { ok = false; }
  if l10n_decimal_round(-1234, 3, 3) != -1234 { ok = false; }
  if l10n_decimal_round(0, 0, 0) != 0 { ok = false; }
  return assert(ok, "rounding is a no-op when to_decimals >= from_decimals");
}

fn t17() -> TestResult {
  var ok = l10n_decimal_round(1234, 2, -1) == 12;
  if l10n_decimal_round(1234, -5, -1) != 1234 { ok = false; }
  if l10n_decimal_round(1234, -5, 2) != 1234 { ok = false; }
  if l10n_decimal_round(1234, 2, -9) != 12 { ok = false; }
  return assert(ok, "negative decimal counts clamp to zero");
}

fn t18() -> TestResult {
  var ok = l10n_decimal_round(999999999999999999, 19, 0) == 0;
  if l10n_decimal_round(5000000000000000000, 19, 0) != 1 { ok = false; }
  if l10n_decimal_round(-5000000000000000000, 19, 0) != -1 { ok = false; }
  if l10n_decimal_round(4999999999999999999, 19, 0) != 0 { ok = false; }
  if l10n_decimal_round(9223372036854775807, 20, 0) != 0 { ok = false; }
  return assert(ok, "rounding survives drops beyond 10^18 without overflow");
}

fn t19() -> TestResult {
  let int_min = 0 - 9223372036854775807 - 1;
  var ok = l10n_decimal_round(9223372036854775807, 1, 0) == 922337203685477581;
  if l10n_decimal_round(int_min, 1, 0) != -922337203685477581 { ok = false; }
  if !streq(l10n_decimal_format(int_min, 2, ",", "."), "-92,233,720,368,547,758.08") { ok = false; }
  if !streq(l10n_decimal_format(9223372036854775807, 0, ",", "."), "9,223,372,036,854,775,807") { ok = false; }
  return assert(ok, "rounding and formatting are exact at the 64-bit boundaries");
}

fn t20() -> TestResult {
  var ok = parse_is("1234", ".", 0, 1234);
  if !parse_is("1.234", ".", 3, 1234) { ok = false; }
  if !parse_is("1.23", ".", 3, 1230) { ok = false; }
  if !parse_is("1", ".", 3, 1000) { ok = false; }
  if !parse_is("1.2", ".", 3, 1200) { ok = false; }
  if !parse_is("0", ".", 5, 0) { ok = false; }
  if !parse_is("1..5", "..", 1, 15) { ok = false; }
  return assert(ok, "parse: fraction digits are right-padded to the wanted scale");
}

fn t21() -> TestResult {
  var ok = parse_is("+12.5", ".", 3, 12500);
  if !parse_is("-0.5", ".", 2, -50) { ok = false; }
  if !parse_is("-1234", ".", 0, -1234) { ok = false; }
  if !parse_is(".5", ".", 1, 5) { ok = false; }
  if !parse_is("5.", ".", 2, 500) { ok = false; }
  if !parse_is("-0", ".", 3, 0) { ok = false; }
  return assert(ok, "parse: sign, empty integer part, trailing separator, minus zero");
}

fn t22() -> TestResult {
  var ok = parse_is("1 234", ".", 0, 1234);
  if !parse_is("1_234", ".", 0, 1234) { ok = false; }
  if !parse_is("1,234", ".", 0, 1234) { ok = false; }
  if !parse_is("1,2,3", ".", 1, 1230) { ok = false; }
  if !parse_is("1,234.5", ".", 1, 12345) { ok = false; }
  if !parse_is("1 234,5", ",", 1, 12345) { ok = false; }
  if !parse_is("1_234_567", ".", 0, 1234567) { ok = false; }
  return assert(ok, "parse: ',' '_' and ' ' groups are ignored on both sides");
}

fn t23() -> TestResult {
  let int_text = l10n_int_format(-9876543, ",");
  var ok = parse_is(int_text, ".", 0, -9876543);
  let dec_text = l10n_decimal_format(123456, 2, ",", ".");
  if !streq(dec_text, "1,234.56") { ok = false; }
  if !parse_is(dec_text, ".", 2, 123456) { ok = false; }
  let back = l10n_decimal_format(1234567, 3, " ", ",");
  if !streq(back, "1 234,567") { ok = false; }
  if !parse_is(back, ",", 3, 1234567) { ok = false; }
  if !parse_is(l10n_permille_format(12345, 2, ",", "."), ".", 2, 123450) { ok = false; }
  return assert(ok, "format -> parse round-trips for int, decimal and permille");
}

fn t24() -> TestResult {
  var ok = parse_err_is("1.234", ".", 2, "l10n: too many decimals");
  if !parse_err_is("1,234", ",", 2, "l10n: too many decimals") { ok = false; }
  if !parse_err_is("1.5", ".", 0, "l10n: too many decimals") { ok = false; }
  return assert(ok, "parse: more fraction digits than requested is Err(too many decimals)");
}

fn t25() -> TestResult {
  var ok = parse_err_is("", ".", 2, "l10n: empty input");
  if !parse_err_is("-", ".", 0, "l10n: no digits") { ok = false; }
  if !parse_err_is(",,", ".", 0, "l10n: no digits") { ok = false; }
  if !parse_err_is("1.2.3", ".", 2, "l10n: multiple decimal separators") { ok = false; }
  if !parse_err_is("1a", ".", 0, "l10n: unexpected character: a") { ok = false; }
  if !parse_err_is("5-6", ".", 0, "l10n: unexpected character: -") { ok = false; }
  if !parse_err_is("1.234,56", ",", 2, "l10n: unexpected character: .") { ok = false; }
  return assert(ok, "parse: malformed input returns the documented Err messages");
}

fn t26() -> TestResult {
  var ok = parse_is("9223372036854775807", ".", 0, 9223372036854775807);
  if !parse_is("9,223,372,036,854,775,807", ".", 0, 9223372036854775807) { ok = false; }
  if !parse_is("-9223372036854775807", ".", 0, 0 - 9223372036854775807) { ok = false; }
  if !parse_err_is("9223372036854775808", ".", 0, "l10n: number too large") { ok = false; }
  if !parse_err_is("-9223372036854775808", ".", 0, "l10n: number too large") { ok = false; }
  if !parse_err_is("99999999999999999999", ".", 0, "l10n: number too large") { ok = false; }
  return assert(ok, "parse: 64-bit edges accepted, magnitudes beyond them are Err");
}

fn t27() -> TestResult {
  var ok = streq(l10n_permille_format(12345, 1, ",", "."), "1,234.5");
  if !streq(l10n_permille_format(12345, 2, ",", "."), "1,234.50") { ok = false; }
  if !streq(l10n_permille_format(999, 1, ",", "."), "99.9") { ok = false; }
  if !streq(l10n_permille_format(5, 1, ",", "."), "0.5") { ok = false; }
  if !streq(l10n_permille_format(5, 3, ",", "."), "0.500") { ok = false; }
  if !streq(l10n_permille_format(12345, 1, ".", ","), "1.234,5") { ok = false; }
  return assert(ok, "permille formats permille/10 with exactly the requested digits");
}

fn t28() -> TestResult {
  var ok = streq(l10n_permille_format(12345, 0, ",", "."), "1,235");
  if !streq(l10n_permille_format(1234, 0, ",", "."), "123") { ok = false; }
  if !streq(l10n_permille_format(1235, 0, ",", "."), "124") { ok = false; }
  if !streq(l10n_permille_format(-1235, 0, ",", "."), "-124") { ok = false; }
  if !streq(l10n_permille_format(4, 0, ",", "."), "0") { ok = false; }
  if !streq(l10n_permille_format(-4, 0, ",", "."), "0") { ok = false; }
  if !streq(l10n_permille_format(0, 0, ",", "."), "0") { ok = false; }
  if !streq(l10n_permille_format(85, 0, ",", "."), "9") { ok = false; }
  if !streq(l10n_permille_format(9995, 0, ",", "."), "1,000") { ok = false; }
  return assert(ok, "permille with zero decimals rounds half away and drops a zero sign");
}

fn t29() -> TestResult {
  let int_min = 0 - 9223372036854775807 - 1;
  var ok = streq(l10n_permille_format(-12345, 1, ",", "."), "-1,234.5");
  if !streq(l10n_permille_format(0, 3, ",", "."), "0.000") { ok = false; }
  if !streq(l10n_permille_format(-1, 1, ",", "."), "-0.1") { ok = false; }
  if !streq(l10n_permille_format(9223372036854775807, 1, ",", "."), "922,337,203,685,477,580.7") { ok = false; }
  if !streq(l10n_permille_format(int_min, 1, ",", "."), "-922,337,203,685,477,580.8") { ok = false; }
  return assert(ok, "permille is exact for negatives, zero and 64-bit extremes");
}

fn t30() -> TestResult {
  var ok = l10n_decimal_round(15000, 4, 0) == 2;
  if l10n_decimal_round(14999, 4, 0) != 1 { ok = false; }
  if l10n_decimal_round(-15000, 4, 0) != -2 { ok = false; }
  if l10n_decimal_round(99999999, 8, 4) != 10000 { ok = false; }
  if l10n_decimal_round(-99999999, 8, 4) != -10000 { ok = false; }
  return assert(ok, "rounding exact ties through several dropped digits, both signs");
}

fn main() -> Int {
  io.println("=== xiom.l10n.number conformance tests ===");
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
  let r24 = t24();
  if r24.passed { io.println("  [PASS] " + r24.name); } else { io.println("  [FAIL] " + r24.name); failed = failed + 1; }
  let r25 = t25();
  if r25.passed { io.println("  [PASS] " + r25.name); } else { io.println("  [FAIL] " + r25.name); failed = failed + 1; }
  let r26 = t26();
  if r26.passed { io.println("  [PASS] " + r26.name); } else { io.println("  [FAIL] " + r26.name); failed = failed + 1; }
  let r27 = t27();
  if r27.passed { io.println("  [PASS] " + r27.name); } else { io.println("  [FAIL] " + r27.name); failed = failed + 1; }
  let r28 = t28();
  if r28.passed { io.println("  [PASS] " + r28.name); } else { io.println("  [FAIL] " + r28.name); failed = failed + 1; }
  let r29 = t29();
  if r29.passed { io.println("  [PASS] " + r29.name); } else { io.println("  [FAIL] " + r29.name); failed = failed + 1; }
  let r30 = t30();
  if r30.passed { io.println("  [PASS] " + r30.name); } else { io.println("  [FAIL] " + r30.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.l10n.number: all tests passed");
  } else {
    io.println("xiom.l10n.number: tests failed");
  }
  return failed;
}
