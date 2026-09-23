// XIOM -- xiom.sanitize conformance tests (20 checks)
// Port task: prove the pure-XIOM xiom.sanitize module against its documented rules.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API: control-character replacement (C0 and DEL, with
// LF/TAB preserved and the replacement used verbatim), ASCII filtering,
// whitespace normalization (collapse, trailing-before-LF, trim), allow-list
// filtering, filename sanitizing (metacharacters, dots/spaces, empty
// fallback), digit extraction, slug conversion (case, separator runs, edge
// dashes, non-ASCII) and empty inputs.
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every comparison
// below is routed through streq instead of `==`.

module sanitize_tests
use xiom.io; use xiom.test; use xiom.sanitize;
use xiom.string;
use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// Str from two raw bytes (for control bytes that source literals cannot spell).
fn str_of2(a: Int, b: Int) -> Str {
  var v = Vec[UInt8].new();
  v.push(a as UInt8);
  v.push(b as UInt8);
  return Str::from_utf8(v);
}

// Str from three raw bytes.
fn str_of3(a: Int, b: Int, c: Int) -> Str {
  var v = Vec[UInt8].new();
  v.push(a as UInt8);
  v.push(b as UInt8);
  v.push(c as UInt8);
  return Str::from_utf8(v);
}

fn t1() -> TestResult {
  var ok = streq(sanitize_control_chars(str_of3(65, 1, 66), "_"), "A_B");
  if !streq(sanitize_control_chars(str_of2(8, 65), "_"), "_A") { ok = false; }
  if !streq(sanitize_control_chars(str_of3(65, 31, 66), "_"), "A_B") { ok = false; }
  return assert(ok, "control chars 0x01-0x1F are replaced with _");
}

fn t2() -> TestResult {
  let mixed = "line1\nline2\tend";
  var ok = streq(sanitize_control_chars(mixed, "_"), mixed);
  if !streq(sanitize_control_chars("\n\t", "_"), "\n\t") { ok = false; }
  if !streq(sanitize_control_chars("tabs\tand\nlines", "_"), "tabs\tand\nlines") { ok = false; }
  return assert(ok, "LF and TAB pass through control-char sanitizing");
}

fn t3() -> TestResult {
  var ok = streq(sanitize_control_chars(str_of3(65, 127, 66), "_"), "A_B");
  if !streq(sanitize_control_chars(str_of2(127, 127), "_"), "__") { ok = false; }
  if !streq(sanitize_control_chars(str_of3(65, 126, 127), "_"), "A~_") { ok = false; }
  return assert(ok, "0x7F DEL is replaced");
}

fn t4() -> TestResult {
  var ok = streq(sanitize_control_chars(str_of3(65, 2, 66), "<X>"), "A<X>B");
  if !streq(sanitize_control_chars(str_of3(65, 2, 66), ""), "AB") { ok = false; }
  if !streq(sanitize_control_chars(str_of3(2, 3, 4), "--"), "------") { ok = false; }
  return assert(ok, "replacement string is used verbatim");
}

fn t5() -> TestResult {
  let mixed = "abc" + str_of2(195, 169) + "z";
  var ok = streq(sanitize_ascii(mixed), "abcz");
  if !streq(sanitize_ascii(str_of2(226, 156)), "") { ok = false; }
  if !streq(sanitize_ascii("plain ASCII"), "plain ASCII") { ok = false; }
  return assert(ok, "sanitize_ascii drops bytes >= 0x80");
}

fn t6() -> TestResult {
  var ok = streq(sanitize_whitespace("a   b\t\tc"), "a b c");
  if !streq(sanitize_whitespace("one  two"), "one two") { ok = false; }
  if !streq(sanitize_whitespace("x\t \t y"), "x y") { ok = false; }
  return assert(ok, "whitespace runs collapse to one space");
}

fn t7() -> TestResult {
  var ok = streq(sanitize_whitespace("  hello  "), "hello");
  if !streq(sanitize_whitespace("\t\ttabbed\t"), "tabbed") { ok = false; }
  if !streq(sanitize_whitespace("   "), "") { ok = false; }
  return assert(ok, "leading and trailing whitespace is trimmed");
}

fn t8() -> TestResult {
  var ok = streq(sanitize_whitespace("line1   \nline2"), "line1\nline2");
  if !streq(sanitize_whitespace("a\t \t\nb"), "a\nb") { ok = false; }
  if !streq(sanitize_whitespace("a  \n  b"), "a\n b") { ok = false; }
  if !streq(sanitize_whitespace("keep\nthe\nLF"), "keep\nthe\nLF") { ok = false; }
  return assert(ok, "spaces before newline are stripped, newline kept");
}

fn t9() -> TestResult {
  var ok = streq(sanitize_keep("a-b_c d!", "-_"), "a-b_cd");
  if !streq(sanitize_keep("file.name/v2", "./"), "file.name/v2") { ok = false; }
  if !streq(sanitize_keep("A1-b", ""), "A1b") { ok = false; }
  return assert(ok, "sanitize_keep keeps alnum plus the allow set");
}

fn t10() -> TestResult {
  var ok = streq(sanitize_keep("café", "-"), "caf");
  if !streq(sanitize_keep("a✓b", ""), "ab") { ok = false; }
  if !streq(sanitize_keep("Ünïcode", "x"), "ncode") { ok = false; }
  return assert(ok, "sanitize_keep drops non-ASCII bytes");
}

fn t11() -> TestResult {
  var ok = streq(sanitize_filename("a\\b:c*d"), "a_b_c_d");
  if !streq(sanitize_filename("a<b>c?d|e\"f/g"), "a_b_c_d_e_f_g") { ok = false; }
  if !streq(sanitize_filename("a\tb\nc"), "a_b_c") { ok = false; }
  return assert(ok, "filename metacharacters are replaced with _");
}

fn t12() -> TestResult {
  var ok = streq(sanitize_filename("report.txt..."), "report.txt");
  if !streq(sanitize_filename("  name . "), "name") { ok = false; }
  if !streq(sanitize_filename(".hidden"), "hidden") { ok = false; }
  return assert(ok, "filename strips leading/trailing spaces and dots");
}

fn t13() -> TestResult {
  var ok = streq(sanitize_filename(""), "_");
  if !streq(sanitize_filename("   "), "_") { ok = false; }
  if !streq(sanitize_filename("..."), "_") { ok = false; }
  if !streq(sanitize_filename("///"), "___") { ok = false; }
  return assert(ok, "empty filename falls back to _");
}

fn t14() -> TestResult {
  var ok = streq(sanitize_numeric("v1.2.3-beta"), "123");
  if !streq(sanitize_numeric("(555) 123-4567"), "5551234567") { ok = false; }
  if !streq(sanitize_numeric("no digits"), "") { ok = false; }
  return assert(ok, "sanitize_numeric keeps ASCII digits only");
}

fn t15() -> TestResult {
  var ok = streq(sanitize_slug("Hello World"), "hello-world");
  if !streq(sanitize_slug("  spaced  out  "), "spaced-out") { ok = false; }
  return assert(ok, "slug: spaces become single dashes");
}

fn t16() -> TestResult {
  var ok = streq(sanitize_slug("MIXED Case"), "mixed-case");
  if !streq(sanitize_slug("ABC123"), "abc123") { ok = false; }
  return assert(ok, "slug: ASCII letters are lowercased");
}

fn t17() -> TestResult {
  var ok = streq(sanitize_slug("a..b--c"), "a-b-c");
  if !streq(sanitize_slug("Hello,   World!!"), "hello-world") { ok = false; }
  return assert(ok, "slug: non-alphanumeric runs become one dash");
}

fn t18() -> TestResult {
  var ok = streq(sanitize_slug("--a-b--"), "a-b");
  if !streq(sanitize_slug("...lead"), "lead") { ok = false; }
  if !streq(sanitize_slug("-"), "") { ok = false; }
  return assert(ok, "slug: leading and trailing dashes are trimmed");
}

fn t19() -> TestResult {
  var ok = streq(sanitize_slug("Café au lait"), "caf-au-lait");
  if !streq(sanitize_slug("naïve"), "na-ve") { ok = false; }
  if !streq(sanitize_slug("é"), "") { ok = false; }
  return assert(ok, "slug: non-ASCII bytes are dropped as separators");
}

fn t20() -> TestResult {
  var ok = streq(sanitize_control_chars("", "_"), "");
  if !streq(sanitize_ascii(""), "") { ok = false; }
  if !streq(sanitize_whitespace(""), "") { ok = false; }
  if !streq(sanitize_keep("", "abc"), "") { ok = false; }
  if !streq(sanitize_numeric(""), "") { ok = false; }
  if !streq(sanitize_slug(""), "") { ok = false; }
  if !streq(sanitize_filename(""), "_") { ok = false; }
  return assert(ok, "empty inputs return empty; filename falls back to _");
}

fn main() -> Int {
  io.println("=== xiom.sanitize conformance tests ===");
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
    io.println("xiom.sanitize: all tests passed");
  } else {
    io.println("xiom.sanitize: tests failed");
  }
  return failed;
}
