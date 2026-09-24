// XIOM -- xiom.refactor conformance tests (20 checks)
// Port task: prove the pure-XIOM xiom.refactor module against its SPEC.md.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module refactor_tests
use xiom.io; use xiom.test; use xiom.refactor;
use xiom.string.compare;

// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every element check
// below is routed through streq/vec_eq instead of `==`.

// The default alphabet without '_' -- used to show that the boundary set is a
// parameter, not a hardcoded rule.
const _ALNUM: Str = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn vec_eq(got: &Vec[Str], want: &Vec[Str]) -> Bool {
  if got.len() != want.len() { return false; }
  var i = 0;
  while i < got.len() {
    if !streq(got[i], want[i]) { return false; }
    i = i + 1;
  }
  return true;
}

fn ivec_eq(got: &Vec[Int], want: &Vec[Int]) -> Bool {
  if got.len() != want.len() { return false; }
  var i = 0;
  while i < got.len() {
    if got[i] != want[i] { return false; }
    i = i + 1;
  }
  return true;
}

fn lines1(a: Str) -> Vec[Str] {
  var out = Vec[Str].new();
  out.push(a);
  return out;
}

fn lines2(a: Str, b: Str) -> Vec[Str] {
  var out = Vec[Str].new();
  out.push(a);
  out.push(b);
  return out;
}

fn t1() -> TestResult {
  let d = refactor_word_chars_default();
  var ok = d.len() == 63;
  if !streq(d, "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_") { ok = false; }
  if !refactor_is_word_char(65, d) { ok = false; }
  if !refactor_is_word_char(95, d) { ok = false; }
  return assert(ok, "word_chars_default: exact 63-byte alphabet");
}

fn t2() -> TestResult {
  let d = refactor_word_chars_default();
  var ok = refactor_is_word_char(122, d);       // 'z'
  if !refactor_is_word_char(48, d) { ok = false; }   // '0'
  if refactor_is_word_char(45, d) { ok = false; }    // '-'
  if refactor_is_word_char(32, d) { ok = false; }    // ' '
  if refactor_is_word_char(233, d) { ok = false; }   // latin-1 'e-acute'
  if refactor_is_word_char(195, d) { ok = false; }   // first UTF-8 byte of 'e-acute'
  if refactor_is_word_char(-1, d) { ok = false; }
  if refactor_is_word_char(256, d) { ok = false; }
  if refactor_is_word_char(65, "") { ok = false; }
  return assert(ok, "is_word_char: membership, range checks and empty set");
}

fn t3() -> TestResult {
  let d = refactor_word_chars_default();
  var ok = refactor_count("foo foo foo", "foo", d) == 3;
  if refactor_count("foo", "foo", d) != 1 { ok = false; }
  if refactor_count("a foo b", "foo", d) != 1 { ok = false; }
  return assert(ok, "count: standalone occurrences");
}

fn t4() -> TestResult {
  let d = refactor_word_chars_default();
  var ok = refactor_count("foobar", "foo", d) == 0;   // suffix must not count
  if refactor_count("barfoo", "foo", d) != 0 { ok = false; }   // prefix must not count
  if refactor_count("foofoo", "foo", d) != 0 { ok = false; }
  if refactor_count("fo", "foo", d) != 0 { ok = false; }
  if refactor_count("foo", "foofoo", d) != 0 { ok = false; }
  return assert(ok, "count: prefix/suffix/substring matches are not whole words");
}

fn t5() -> TestResult {
  let d = refactor_word_chars_default();
  var ok = refactor_count("foo_bar _foo_ foo", "foo", d) == 1;   // '_' is a word char
  if refactor_count("foo_bar _foo_ foo", "foo", _ALNUM) != 3 { ok = false; }  // '_' is not
  if refactor_count("foo_bar", "foo", _ALNUM) != 1 { ok = false; }
  return assert(ok, "count: underscore boundary depends on word_chars");
}

fn t6() -> TestResult {
  let d = refactor_word_chars_default();
  var ok = refactor_count("abc", "", d) == 0;
  if refactor_count("", "", d) != 0 { ok = false; }
  if !streq(refactor_rename("abc", "", "x", d), "abc") { ok = false; }
  var pairs = lines1("=x");
  var got = refactor_rename_dry_run("abc", &pairs, d);
  if !vec_eq(&got, &lines1(" -> x: 0 replacement(s)")) { ok = false; }
  return assert(ok, "empty old name: 0 counts, unchanged text, dry-run line");
}

fn t7() -> TestResult {
  let d = refactor_word_chars_default();
  var ok = streq(refactor_rename("foo foobar foo_bar", "foo", "X", d), "X foobar foo_bar");
  if !streq(refactor_rename("foo, foo!", "foo", "x", d), "x, x!") { ok = false; }
  if !streq(refactor_rename("_foo_", "foo", "X", d), "_foo_") { ok = false; }
  return assert(ok, "rename: whole-word boundaries with punctuation");
}

fn t8() -> TestResult {
  var ok = streq(refactor_rename("_foo_", "foo", "X", _ALNUM), "_X_");
  if !streq(refactor_rename("foo_bar", "foo", "X", _ALNUM), "X_bar") { ok = false; }
  return assert(ok, "rename: '_' is a boundary when word_chars excludes it");
}

fn t9() -> TestResult {
  let d = refactor_word_chars_default();
  let same = refactor_rename("foo foo bar", "foo", "foo", d);
  return assert(streq(same, "foo foo bar"), "rename: old == new is identity");
}

fn t10() -> TestResult {
  let d = refactor_word_chars_default();
  var ok = streq(refactor_rename("bar baz", "foo", "X", d), "bar baz");
  if !streq(refactor_rename("", "foo", "X", d), "") { ok = false; }
  if !streq(refactor_rename("foo", "fOO", "X", d), "foo") { ok = false; }   // case-sensitive
  return assert(ok, "rename: absent name, empty text, case sensitivity");
}

fn t11() -> TestResult {
  let d = refactor_word_chars_default();
  var pairs = lines2("a=b", "b=c");
  return assert(streq(refactor_rename_batch("a b", &pairs, d), "c c"),
    "batch: a=b then b=c chains to c c");
}

fn t12() -> TestResult {
  let d = refactor_word_chars_default();
  var pairs = lines2("b=c", "a=b");
  return assert(streq(refactor_rename_batch("a b", &pairs, d), "b c"),
    "batch: reversed order yields b c (order sensitive)");
}

fn t13() -> TestResult {
  let d = refactor_word_chars_default();
  var pairs = Vec[Str].new();
  pairs.push("a=b");
  pairs.push("garbage");
  pairs.push("b=c");
  var ok = streq(refactor_rename_batch("a b", &pairs, d), "c c");
  var only = lines1("x");
  if !streq(refactor_rename_batch("x", &only, d), "x") { ok = false; }
  return assert(ok, "batch: malformed pairs are skipped, never errors");
}

fn t14() -> TestResult {
  let d = refactor_word_chars_default();
  var pairs = lines2("a=b", "b=c");
  var got = refactor_rename_dry_run("a b", &pairs, d);
  var want = lines2("a -> b: 1 replacement(s)", "b -> c: 2 replacement(s)");
  var ok = vec_eq(&got, &want);
  var one = lines1("foo=bar");
  if !vec_eq(&refactor_rename_dry_run("foo", &one, d), &lines1("foo -> bar: 1 replacement(s)")) { ok = false; }
  return assert(ok, "dry_run: ordered pairs report running-text counts");
}

fn t15() -> TestResult {
  let d = refactor_word_chars_default();
  var pairs = lines2("x=y", "oops");
  var got = refactor_rename_dry_run("x", &pairs, d);
  var want = lines2("x -> y: 1 replacement(s)", "oops -> ?: invalid");
  var ok = vec_eq(&got, &want);
  var lone = lines1("q");
  if !vec_eq(&refactor_rename_dry_run("", &lone, d), &lines1("q -> ?: invalid")) { ok = false; }
  return assert(ok, "dry_run: malformed pair line is 'old -> ?: invalid'");
}

fn t16() -> TestResult {
  let d = refactor_word_chars_default();
  var got = refactor_occurrence_lines("foo\nbar foo\nfoo", "foo", d);
  var want = Vec[Int].new();
  want.push(1);
  want.push(2);
  want.push(3);
  var ok = ivec_eq(&got, &want);
  if refactor_occurrence_lines("bar\nbaz", "foo", d).len() != 0 { ok = false; }
  if refactor_occurrence_lines("", "foo", d).len() != 0 { ok = false; }
  var solo = refactor_occurrence_lines("foo", "foo", d);
  var want1 = Vec[Int].new();
  want1.push(1);
  if !ivec_eq(&solo, &want1) { ok = false; }
  return assert(ok, "occurrence_lines: multi-line and empty cases");
}

fn t17() -> TestResult {
  let d = refactor_word_chars_default();
  var got = refactor_occurrence_lines("foo\r\nbar foo\r\nfoo\r\nbaz", "foo", d);
  var want = Vec[Int].new();
  want.push(1);
  want.push(2);
  want.push(3);
  return assert(ivec_eq(&got, &want), "occurrence_lines: CRLF text keeps line numbers");
}

fn t18() -> TestResult {
  let d = refactor_word_chars_default();
  var got = refactor_occurrence_lines("foobar\nfoo_bar\nfoo\n", "foo", d);
  var want = Vec[Int].new();
  want.push(3);
  var ok = ivec_eq(&got, &want);
  var alnum = refactor_occurrence_lines("foo_bar\nfoo", "foo", _ALNUM);
  var want2 = Vec[Int].new();
  want2.push(1);
  want2.push(2);
  if !ivec_eq(&alnum, &want2) { ok = false; }
  return assert(ok, "occurrence_lines: boundaries and trailing newline");
}

fn t19() -> TestResult {
  let d = refactor_word_chars_default();
  var ok = refactor_count("caf\u{e9}foo\u{e9} foo", "foo", d) == 2;
  if !streq(refactor_rename("h\u{e9}llo", "llo", "X", d), "h\u{e9}X") { ok = false; }
  if !streq(refactor_rename("\u{5df2}foo\u{5df2}", "foo", "bar", d), "\u{5df2}bar\u{5df2}") { ok = false; }
  var lines = refactor_occurrence_lines("caf\u{e9}foo\u{e9}\nfoo", "foo", d);
  var want = Vec[Int].new();
  want.push(1);
  want.push(2);
  if !ivec_eq(&lines, &want) { ok = false; }
  return assert(ok, "unicode: non-ASCII bytes are not word chars");
}

fn t20() -> TestResult {
  let d = refactor_word_chars_default();
  var ok = refactor_count("", "foo", d) == 0;
  if !streq(refactor_rename("", "", "", d), "") { ok = false; }
  var pairs = lines1("a=b");
  if !streq(refactor_rename_batch("", &pairs, d), "") { ok = false; }
  if !vec_eq(&refactor_rename_dry_run("", &pairs, d), &lines1("a -> b: 0 replacement(s)")) { ok = false; }
  if refactor_occurrence_lines("", "", d).len() != 0 { ok = false; }
  // Empty word_chars: no byte is a word character, so foo matches inside foobar.
  if refactor_count("foobar", "foo", "") != 1 { ok = false; }
  if !streq(refactor_rename("abc", "b", "X", ""), "aXc") { ok = false; }
  return assert(ok, "empty text and empty word_chars");
}

fn main() -> Int {
  io.println("=== xiom.refactor conformance tests ===");
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
    io.println("xiom.refactor: all tests passed");
  } else {
    io.println("xiom.refactor: tests failed");
  }
  return failed;
}
