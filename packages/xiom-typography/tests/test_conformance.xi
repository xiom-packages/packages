// XIOM -- xiom.typography conformance tests (20 checks)
// Port task: prove the pure-XIOM xiom.typography module against its documented
// smart-quote, dash, ellipsis and spacing rules.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module typography_tests
use xiom.io; use xiom.test; use xiom.typography;
use xiom.string.compare;

// All Str equality goes through str_compare (BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison). The expected literals
// below contain the actual UTF-8 punctuation characters: U+2018 ' U+2019 '
// U+201C " U+201D " U+2013 - U+2014 - U+2026 ....
fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn t1() -> TestResult {
  return assert(streq(typography_smart_quotes("\"Hello\""), "“Hello”"), "double quotes around a word open and close");
}

fn t2() -> TestResult {
  return assert(streq(typography_smart_quotes("\"open at start"), "“open at start"), "double quote at string start opens");
}

fn t3() -> TestResult {
  return assert(streq(typography_smart_quotes("close at end\""), "close at end”"), "double quote at string end closes");
}

fn t4() -> TestResult {
  return assert(streq(typography_smart_quotes("don't"), "don’t"), "single quote inside a word is an apostrophe");
}

fn t5() -> TestResult {
  return assert(streq(typography_smart_quotes("say 'hi'"), "say ‘hi’"), "single quote opens after whitespace and closes after a word");
}

fn t6() -> TestResult {
  return assert(streq(typography_smart_quotes("(\"x\")"), "(“x”)"), "double quote after an opening bracket opens");
}

fn t7() -> TestResult {
  return assert(streq(typography_smart_quotes("-'hi'"), "-‘hi’"), "single quote after a dash opens");
}

fn t8() -> TestResult {
  let converted = typography_smart_dashes("--\"hi\"");
  return assert(streq(typography_smart_quotes(converted), "–“hi”"), "quote after a converted en dash still opens");
}

fn t9() -> TestResult {
  return assert(streq(typography_smart_quotes("\"it's\" 'ok'"), "“it’s” ‘ok’"), "mixed single and double quotes resolve independently");
}

fn t10() -> TestResult {
  return assert(streq(typography_smart_dashes("a---b"), "a—b"), "triple hyphen becomes an em dash");
}

fn t11() -> TestResult {
  return assert(streq(typography_smart_dashes("a--b"), "a–b"), "double hyphen becomes an en dash");
}

fn t12() -> TestResult {
  return assert(streq(typography_smart_dashes("a---b--c"), "a—b–c"), "longest match first: triple hyphen beats double hyphen");
}

fn t13() -> TestResult {
  return assert(streq(typography_ellipsis("wait..."), "wait…"), "three dots become an ellipsis");
}

fn t14() -> TestResult {
  var ok = streq(typography_ellipsis("a...b...c"), "a…b…c");
  if !streq(typography_ellipsis("a...."), "a….") { ok = false; }
  return assert(ok, "multiple ellipses convert; a fourth dot stays literal");
}

fn t15() -> TestResult {
  var ok = streq(typography_collapse_spaces("a   b"), "a b");
  if !streq(typography_collapse_spaces("a\t\t\tb"), "a b") { ok = false; }
  if !streq(typography_collapse_spaces("a \t  b"), "a b") { ok = false; }
  return assert(ok, "runs of spaces and tabs collapse to one space");
}

fn t16() -> TestResult {
  var ok = streq(typography_collapse_spaces("a  \n \t b"), "a \n b");
  if !streq(typography_collapse_spaces("x\r\ny"), "x\r\ny") { ok = false; }
  return assert(ok, "collapse preserves newlines and carriage returns");
}

fn t17() -> TestResult {
  return assert(streq(typography_collapse_spaces("  x  "), " x "), "collapse trims nothing");
}

fn t18() -> TestResult {
  let out = typography_smart("\"Well...\"  --  it's  \"fine\"  now");
  return assert(streq(out, "“Well…” – it’s “fine” now"), "smart applies ellipsis, dashes, quotes and collapse in order");
}

fn t19() -> TestResult {
  var ok = streq(typography_smart("plain text 101"), "plain text 101");
  if !streq(typography_smart_quotes("plain"), "plain") { ok = false; }
  if !streq(typography_smart_dashes("plain-text"), "plain-text") { ok = false; }
  if !streq(typography_ellipsis("plain."), "plain.") { ok = false; }
  return assert(ok, "text without triggers is unchanged");
}

fn t20() -> TestResult {
  var ok = streq(typography_smart_quotes("'start"), "‘start");
  if !streq(typography_smart_quotes("finish'"), "finish’") { ok = false; }
  return assert(ok, "single quote at string start opens, at string end closes");
}

fn main() -> Int {
  io.println("=== xiom.typography conformance tests ===");
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
    io.println("xiom.typography: all tests passed");
  } else {
    io.println("xiom.typography: tests failed");
  }
  return failed;
}
