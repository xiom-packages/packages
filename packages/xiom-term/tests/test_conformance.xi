// XIOM -- xiom.term conformance tests (20 checks)
// Greenfield port task: prove the pure-XIOM xiom.term module against the
// sequence grammar, per-function rules and truncation policy pinned in
// SPEC.md.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers: SGR stripping, cursor/erase stripping, OSC with BEL and with ST,
// consecutive escapes, plain-text passthrough, has_escapes/is_plain, escape
// counting, visible length, truncation at the exact boundary, truncation with
// an SGR reset appended when an SGR was cut, truncation inside plain text,
// n = 0 and negative budgets, unterminated CSI, a trailing lone ESC, SGR
// parameter flattening (empty parameter => 0), escapes at the string edges,
// several SGR sequences, non-SGR cuts and strip idempotence.
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every comparison
// below is routed through streq instead of `==`.

module term_tests
use xiom.io; use xiom.test; use xiom.term;
use xiom.string.compare;

// Str equality via the v0.61.3 workaround (see header).
fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// Element check for a Vec[Int] with an explicit typed local (no implicit
// element coerces; see the port traps).
fn int_is(v: &Vec[Int], i: Int, want: Int) -> Bool {
  if i < 0 || i >= v.len() {
    return false;
  }
  let got: Int = v[i];
  return got == want;
}

fn t1() -> TestResult {
  var ok = streq(term_strip("\x1b[31mred\x1b[0m"), "red");
  if !streq(term_strip("\x1b[1;32mOK\x1b[0m"), "OK") { ok = false; }
  if !streq(term_strip("\x1b[38;5;196mX"), "X") { ok = false; }
  return assert(ok, "strip: SGR colour sequences are removed");
}

fn t2() -> TestResult {
  var ok = streq(term_strip("\x1b[2Amove\x1b[K"), "move");
  if !streq(term_strip("\x1b[10;20Hxy"), "xy") { ok = false; }
  if !streq(term_strip("\x1b[1A\x1b[2Bz"), "z") { ok = false; }
  return assert(ok, "strip: cursor-move and erase sequences are removed");
}

fn t3() -> TestResult {
  var ok = streq(term_strip("\x1b]0;title\x07text"), "text");
  if !streq(term_strip("\x1b]2;window\x07"), "") { ok = false; }
  if !streq(term_strip("a\x1b]8;;https://x\x07 b"), "a b") { ok = false; }
  return assert(ok, "strip: OSC terminated by BEL is removed");
}

fn t4() -> TestResult {
  var ok = streq(term_strip("\x1b]0;title\x1b\\text"), "text");
  if !streq(term_strip("a\x1b]8;;https://x\x1b\\z"), "az") { ok = false; }
  if !streq(term_strip("\x1b]0;t\x1b\\"), "") { ok = false; }
  return assert(ok, "strip: OSC terminated by ST is removed");
}

fn t5() -> TestResult {
  var ok = streq(term_strip("\x1b[1m\x1b[31m\x1b[4mA"), "A");
  if !streq(term_strip("\x1b[1m\x1b[2m"), "") { ok = false; }
  if !streq(term_strip("\x1b[31m\x1b[0mab\x1b[1m"), "ab") { ok = false; }
  return assert(ok, "strip: consecutive and adjacent escapes are all removed");
}

fn t6() -> TestResult {
  var ok = streq(term_strip("plain text"), "plain text");
  if !streq(term_strip(""), "") { ok = false; }
  if !streq(term_strip("a\tb\nc"), "a\tb\nc") { ok = false; }
  return assert(ok, "strip: plain text (including TAB/LF) is unchanged");
}

fn t7() -> TestResult {
  var ok = term_has_escapes("\x1b[31m");
  if term_has_escapes("plain") { ok = false; }
  if term_has_escapes("") { ok = false; }
  if term_is_plain("\x1b[31m") { ok = false; }
  if !term_is_plain("plain") { ok = false; }
  return assert(ok, "has_escapes/is_plain detect any ESC byte");
}

fn t8() -> TestResult {
  var ok = term_count_escapes("\x1b[31mred\x1b[0m") == 2;
  if term_count_escapes("\x1b[1m\x1b[31m\x1b[4mA") != 3 { ok = false; }
  if term_count_escapes("plain") != 0 { ok = false; }
  if term_count_escapes("") != 0 { ok = false; }
  return assert(ok, "count: one unit per removed escape");
}

fn t9() -> TestResult {
  var ok = term_visible_len("\x1b[31mred\x1b[0m") == 3;
  if term_visible_len("\x1b]0;t\x07hi") != 2 { ok = false; }
  if term_visible_len("abc") != 3 { ok = false; }
  if term_visible_len("\x1b[31m") != 0 { ok = false; }
  return assert(ok, "visible_len: byte length after stripping");
}

fn t10() -> TestResult {
  var ok = streq(term_truncate_visible("\x1b[31mabcd", 4), "\x1b[31mabcd");
  if !streq(term_truncate_visible("\x1b[31mabcd\x1b[0m", 4), "\x1b[31mabcd\x1b[0m") { ok = false; }
  if !streq(term_truncate_visible("\x1b[31mabcd\x1b[2A", 4), "\x1b[31mabcd") { ok = false; }
  return assert(ok, "truncate: exact visible boundary keeps the prefix intact");
}

fn t11() -> TestResult {
  var ok = streq(term_truncate_visible("\x1b[31mabcdef\x1b[0m", 3), "\x1b[31mabc\x1b[0m");
  if !streq(term_truncate_visible("\x1b[31mab\x1b[32mcd\x1b[33mef", 3), "\x1b[31mab\x1b[32mc\x1b[0m") { ok = false; }
  if !streq(term_truncate_visible("\x1b[31mab\x1b[4mcdef", 2), "\x1b[31mab\x1b[0m") { ok = false; }
  return assert(ok, "truncate: reset is appended when an SGR is cut");
}

fn t12() -> TestResult {
  var ok = streq(term_truncate_visible("hello world", 5), "hello");
  if !streq(term_truncate_visible("hello world", 11), "hello world") { ok = false; }
  if !streq(term_truncate_visible("hello world", 99), "hello world") { ok = false; }
  if !streq(term_truncate_visible("hi", 5), "hi") { ok = false; }
  return assert(ok, "truncate: plain text is cut at n visible bytes");
}

fn t13() -> TestResult {
  var ok = streq(term_truncate_visible("\x1b[31mred", 0), "");
  if !streq(term_truncate_visible("red", -1), "") { ok = false; }
  if !streq(term_truncate_visible("\x1b[31mred\x1b[0m", -7), "") { ok = false; }
  if !streq(term_truncate_visible("", 0), "") { ok = false; }
  return assert(ok, "truncate: n = 0 and n < 0 yield an empty string");
}

fn t14() -> TestResult {
  var ok = streq(term_strip("ab\x1b[31"), "ab");
  if term_visible_len("ab\x1b[31") != 2 { ok = false; }
  if term_count_escapes("ab\x1b[31") != 1 { ok = false; }
  if !streq(term_strip("\x1b["), "") { ok = false; }
  return assert(ok, "unterminated CSI consumes to end of input");
}

fn t15() -> TestResult {
  var ok = streq(term_strip("abc\x1b"), "abc");
  if term_count_escapes("abc\x1b") != 1 { ok = false; }
  if !streq(term_strip("\x1b"), "") { ok = false; }
  if term_visible_len("abc\x1b") != 3 { ok = false; }
  return assert(ok, "a trailing lone ESC is dropped");
}

fn t16() -> TestResult {
  var p1 = term_parse_sgr("\x1b[1;31m");
  var ok = p1.len() == 2;
  if !int_is(&p1, 0, 1) { ok = false; }
  if !int_is(&p1, 1, 31) { ok = false; }
  var p2 = term_parse_sgr("\x1b[m");
  if p2.len() != 1 { ok = false; }
  if !int_is(&p2, 0, 0) { ok = false; }
  var p3 = term_parse_sgr("\x1b[1;;3m");
  if p3.len() != 3 { ok = false; }
  if !int_is(&p3, 1, 0) { ok = false; }
  return assert(ok, "parse_sgr: parameters are flattened with empty => 0");
}

fn t17() -> TestResult {
  var ok = streq(term_strip("\x1b[31mred"), "red");
  if !streq(term_strip("red\x1b[0m"), "red") { ok = false; }
  if !term_has_escapes("\x1b[31mred") { ok = false; }
  if !term_has_escapes("red\x1b[0m") { ok = false; }
  if !streq(term_truncate_visible("red\x1b[0m", 3), "red\x1b[0m") { ok = false; }
  if !streq(term_truncate_visible("\x1b[31mred", 3), "\x1b[31mred") { ok = false; }
  return assert(ok, "escape bytes at the start and end are handled");
}

fn t18() -> TestResult {
  var p1 = term_parse_sgr("\x1b[38:5:196mX\x1b[1m");
  var ok = p1.len() == 4;
  if !int_is(&p1, 0, 38) { ok = false; }
  if !int_is(&p1, 1, 5) { ok = false; }
  if !int_is(&p1, 2, 196) { ok = false; }
  if !int_is(&p1, 3, 1) { ok = false; }
  var p2 = term_parse_sgr("\x1b[31mred\x1b[0m");
  if p2.len() != 2 { ok = false; }
  if !int_is(&p2, 0, 31) { ok = false; }
  if !int_is(&p2, 1, 0) { ok = false; }
  return assert(ok, "parse_sgr: several sequences flatten in order");
}

fn t19() -> TestResult {
  var ok = streq(term_truncate_visible("\x1b[31mabc\x1b[2A", 2), "\x1b[31mab");
  if !streq(term_truncate_visible("\x1b]0;t\x07zbc", 1), "\x1b]0;t\x07z") { ok = false; }
  if !streq(term_truncate_visible("\x1b[31mab\x1b[2Acd", 3), "\x1b[31mab\x1b[2Ac") { ok = false; }
  return assert(ok, "truncate: no reset when no SGR was cut");
}

fn t20() -> TestResult {
  var e = term_parse_sgr("plain");
  var ok = e.len() == 0;
  var u = term_parse_sgr("\x1b[31");
  if u.len() != 0 { ok = false; }
  var osc = term_parse_sgr("\x1b]0;t\x07");
  if osc.len() != 0 { ok = false; }
  let once = term_strip("\x1b[1m\x1b[31ma\x1b]0;tz\x07 b\x1b[0m");
  if !streq(once, "a b") { ok = false; }
  let twice = term_strip(once);
  if !streq(twice, "a b") { ok = false; }
  if term_count_escapes(once) != 0 { ok = false; }
  return assert(ok, "parse_sgr ignores non-SGR input; strip is idempotent");
}

fn main() -> Int {
  io.println("=== xiom.term conformance tests ===");
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
    io.println("xiom.term: all tests passed");
  } else {
    io.println("xiom.term: tests failed");
  }
  return failed;
}
