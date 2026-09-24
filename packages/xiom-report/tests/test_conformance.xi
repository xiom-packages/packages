// XIOM -- xiom.report conformance tests (24 checks)
// Port task: prove the pure-XIOM xiom.report module against the layout rules
// pinned in SPEC.md: fixed-width tables, aligned key/value blocks, bullet
// indentation, greedy word wrap and horizontal rules.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every output and
// element check below is routed through streq/line_is instead of `==`.

module report_tests
use xiom.io; use xiom.test; use xiom.report;
use xiom.string;
use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn line_is(lines: &Vec[Str], i: Int, want: Str) -> Bool {
  if i < 0 || i >= lines.len() { return false; }
  let got: Str = lines[i];
  return streq(got, want);
}

fn line_len_is(lines: &Vec[Str], i: Int, want: Int) -> Bool {
  if i < 0 || i >= lines.len() { return false; }
  let got: Str = lines[i];
  return got.len() == want;
}

fn all_lines_len(lines: &Vec[Str], want: Int) -> Bool {
  var i = 0;
  while i < lines.len() {
    if !line_len_is(lines, i, want) { return false; }
    i = i + 1;
  }
  return true;
}

fn t1() -> TestResult {
  var headers = Vec[Str].new();
  headers.push("name");
  headers.push("age");
  var r1 = Vec[Str].new(); r1.push("Ada"); r1.push("36");
  var r2 = Vec[Str].new(); r2.push("Bob"); r2.push("7");
  var rows = Vec[Vec[Str]].new();
  rows.push(r1);
  rows.push(r2);
  let got = report_table(&headers, &rows, 1);
  var ok = streq(got, "name age \n---------\nAda  36  \nBob  7   ");
  let out_lines = string.lines(got);
  if out_lines.len() != 4 { ok = false; }
  if !all_lines_len(&out_lines, 9) { ok = false; }
  if !line_is(&out_lines, 0, "name age ") { ok = false; }
  return assert(ok, "table: header, separator and rows share one width (pad 1)");
}

fn t2() -> TestResult {
  var headers = Vec[Str].new();
  var r1 = Vec[Str].new(); r1.push("a"); r1.push("b");
  var rows = Vec[Vec[Str]].new();
  rows.push(r1);
  let got = report_table(&headers, &rows, 1);
  var ok = streq(got, "a b ");
  let out_lines = string.lines(got);
  if out_lines.len() != 1 { ok = false; }
  return assert(ok, "table: no headers means no separator line");
}

fn t3() -> TestResult {
  var headers = Vec[Str].new();
  headers.push("a");
  var r1 = Vec[Str].new(); r1.push("b");
  var rows = Vec[Vec[Str]].new();
  rows.push(r1);
  var ok = streq(report_table(&headers, &rows, 0), "a\n-\nb");
  if !streq(report_table(&headers, &rows, 2), "a  \n---\nb  ") { ok = false; }
  if !streq(report_table(&headers, &rows, -3), "a\n-\nb") { ok = false; }
  return assert(ok, "table: pad 0, pad 2, and a negative pad clamped to 0");
}

fn t4() -> TestResult {
  var headers = Vec[Str].new();
  headers.push("a");
  headers.push("b");
  headers.push("c");
  var r1 = Vec[Str].new(); r1.push("1");
  var r2 = Vec[Str].new(); r2.push("2"); r2.push("33");
  var rows = Vec[Vec[Str]].new();
  rows.push(r1);
  rows.push(r2);
  let got = report_table(&headers, &rows, 0);
  var ok = streq(got, "ab c\n----\n1   \n233 ");
  let out_lines = string.lines(got);
  if out_lines.len() != 4 { ok = false; }
  if !all_lines_len(&out_lines, 4) { ok = false; }
  return assert(ok, "table: short rows are padded with empty cells");
}

fn t5() -> TestResult {
  var headers = Vec[Str].new();
  headers.push("h");
  var r1 = Vec[Str].new(); r1.push("x"); r1.push("yyy");
  var rows = Vec[Vec[Str]].new();
  rows.push(r1);
  let got = report_table(&headers, &rows, 1);
  var ok = streq(got, "h     \n------\nx yyy ");
  let out_lines = string.lines(got);
  if out_lines.len() != 3 { ok = false; }
  if !all_lines_len(&out_lines, 6) { ok = false; }
  if !line_is(&out_lines, 2, "x yyy ") { ok = false; }
  return assert(ok, "table: cells beyond the headers use data-only widths");
}

fn t6() -> TestResult {
  var headers = Vec[Str].new();
  headers.push("a");
  var empty_row = Vec[Str].new();
  var r2 = Vec[Str].new(); r2.push("b");
  var rows = Vec[Vec[Str]].new();
  rows.push(empty_row);
  rows.push(r2);
  let got = report_table(&headers, &rows, 0);
  var ok = streq(got, "a\n-\n \nb");
  let out_lines = string.lines(got);
  if out_lines.len() != 4 { ok = false; }
  return assert(ok, "table: a row with no cells renders as one padded blank line");
}

fn t7() -> TestResult {
  var headers = Vec[Str].new();
  var rows = Vec[Vec[Str]].new();
  var ok = streq(report_table(&headers, &rows, 1), "");
  var only_header = Vec[Str].new();
  only_header.push("h");
  if !streq(report_table(&only_header, &rows, 0), "h\n-") { ok = false; }
  var empty_row = Vec[Str].new();
  var cell_less = Vec[Vec[Str]].new();
  cell_less.push(empty_row);
  if !streq(report_table(&headers, &cell_less, 1), "") { ok = false; }
  return assert(ok, "table: empty inputs render as \"\", headers-only as two lines");
}

fn t8() -> TestResult {
  var headers = Vec[Str].new();
  headers.push("a");
  headers.push("b");
  var r1 = Vec[Str].new(); r1.push(""); r1.push("");
  var rows = Vec[Vec[Str]].new();
  rows.push(r1);
  let got = report_table(&headers, &rows, 0);
  var ok = streq(got, "ab\n--\n  ");
  let out_lines = string.lines(got);
  if !all_lines_len(&out_lines, 2) { ok = false; }
  return assert(ok, "table: empty cells still occupy their columns");
}

fn t9() -> TestResult {
  var keys = Vec[Str].new();
  keys.push("name");
  keys.push("id");
  var values = Vec[Str].new();
  values.push("Ada");
  values.push("42");
  let got = report_kv(&keys, &values, ": ");
  var ok = streq(got, "name: Ada\nid  : 42");
  let out_lines = string.lines(got);
  if out_lines.len() != 2 { ok = false; }
  if !line_is(&out_lines, 1, "id  : 42") { ok = false; }
  return assert(ok, "kv: keys are left-justified before the separator");
}

fn t10() -> TestResult {
  var keys = Vec[Str].new(); keys.push("a"); keys.push("b"); keys.push("c");
  var one = Vec[Str].new(); one.push("1");
  var ok = streq(report_kv(&keys, &one, ": "), "a: 1");
  var keys2 = Vec[Str].new(); keys2.push("x");
  var two = Vec[Str].new(); two.push("1"); two.push("2");
  if !streq(report_kv(&keys2, &two, "="), "x=1") { ok = false; }
  var empty = Vec[Str].new();
  if !streq(report_kv(&empty, &two, ": "), "") { ok = false; }
  if !streq(report_kv(&keys, &empty, ": "), "") { ok = false; }
  return assert(ok, "kv: rendering stops at the shorter of keys and values");
}

fn t11() -> TestResult {
  var keys = Vec[Str].new(); keys.push("k"); keys.push("kk");
  var values = Vec[Str].new(); values.push(""); values.push("v");
  var ok = streq(report_kv(&keys, &values, ": "), "k : \nkk: v");
  var k2 = Vec[Str].new(); k2.push("a");
  var v2 = Vec[Str].new(); v2.push("b");
  if !streq(report_kv(&k2, &v2, ""), "ab") { ok = false; }
  return assert(ok, "kv: the separator is verbatim and empty values are kept");
}

fn t12() -> TestResult {
  var keys = Vec[Str].new(); keys.push("x"); keys.push("longkey");
  var values = Vec[Str].new(); values.push("v");
  let got = report_kv(&keys, &values, ": ");
  var ok = streq(got, "x: v");
  return assert(ok, "kv: alignment uses rendered keys only");
}

fn t13() -> TestResult {
  var items = Vec[Str].new(); items.push("alpha"); items.push("beta");
  var ok = streq(report_bullets(&items, "- "), "- alpha\n- beta");
  if !streq(report_bullets(&items, "*"), "*alpha\n*beta") { ok = false; }
  return assert(ok, "bullets: marker + item lines joined with LF");
}

fn t14() -> TestResult {
  var items = Vec[Str].new();
  items.push("first\nsecond\nthird");
  let got = report_bullets(&items, "- ");
  var ok = streq(got, "- first\n  second\n  third");
  let out_lines = string.lines(got);
  if out_lines.len() != 3 { ok = false; }
  if !line_is(&out_lines, 1, "  second") { ok = false; }
  return assert(ok, "bullets: embedded newlines indent by marker.len() spaces");
}

fn t15() -> TestResult {
  var empty = Vec[Str].new();
  var ok = streq(report_bullets(&empty, "- "), "");
  var items = Vec[Str].new(); items.push(""); items.push("x");
  if !streq(report_bullets(&items, "- "), "- \n- x") { ok = false; }
  var multi = Vec[Str].new(); multi.push("a\nb"); multi.push("c");
  if !streq(report_bullets(&multi, ""), "a\nb\nc") { ok = false; }
  return assert(ok, "bullets: empty input, empty item, empty marker");
}

fn t16() -> TestResult {
  var ok = streq(report_wrap("hello world", 20, ""), "hello world");
  if !streq(report_wrap("hello world", 11, "> "), "> hello world") { ok = false; }
  if !streq(report_wrap("exactly-ten", 11, ""), "exactly-ten") { ok = false; }
  return assert(ok, "wrap: text that fits stays on one indented line");
}

fn t17() -> TestResult {
  let got = report_wrap("the quick brown fox", 9, "> ");
  var ok = streq(got, "> the quick\n> brown fox");
  let out_lines = string.lines(got);
  if out_lines.len() != 2 { ok = false; }
  if !line_is(&out_lines, 1, "> brown fox") { ok = false; }
  return assert(ok, "wrap: greedy fill to the width on spaces");
}

fn t18() -> TestResult {
  var ok = streq(report_wrap("abcdefgh", 3, ""), "abc\ndef\ngh");
  if !streq(report_wrap("ab abcdefgh", 3, ""), "ab\nabc\ndef\ngh") { ok = false; }
  if !streq(report_wrap("abcdef", 6, ""), "abcdef") { ok = false; }
  return assert(ok, "wrap: words longer than width are hard-broken at width");
}

fn t19() -> TestResult {
  var ok = streq(report_wrap("a b\nc", 0, "> "), "a b\nc");
  if !streq(report_wrap("a b", -3, "x"), "a b") { ok = false; }
  return assert(ok, "wrap: width < 1 returns the text unchanged, indent ignored");
}

fn t20() -> TestResult {
  let got = report_wrap("one two\nthree", 5, "");
  var ok = streq(got, "one\ntwo\nthree");
  let out_lines = string.lines(got);
  if out_lines.len() != 3 { ok = false; }
  if !streq(report_wrap("a\nb", 10, "- "), "- a\n- b") { ok = false; }
  if !streq(report_wrap("a\n", 5, ""), "a\n") { ok = false; }
  return assert(ok, "wrap: LF starts a new wrapped and indented logical line");
}

fn t21() -> TestResult {
  var ok = streq(report_wrap("", 5, ">>"), "");
  if !streq(report_wrap("a b", 1, "  "), "  a\n  b") { ok = false; }
  if !streq(report_wrap("a   b", 10, ""), "a b") { ok = false; }
  if !streq(report_wrap("  lead", 10, ""), "lead") { ok = false; }
  return assert(ok, "wrap: empty text, indent per line, space runs collapse");
}

fn t22() -> TestResult {
  var ok = streq(report_wrap("ab cd", 5, ""), "ab cd");
  if !streq(report_wrap("ab cd", 4, ""), "ab\ncd") { ok = false; }
  if !streq(report_wrap("abc def", 5, ""), "abc\ndef") { ok = false; }
  if !streq(report_wrap("abc def", 7, ""), "abc def") { ok = false; }
  return assert(ok, "wrap: the joining space counts against the width");
}

fn t23() -> TestResult {
  var ok = streq(report_rule(5, "-"), "-----");
  if !streq(report_rule(3, "="), "===") { ok = false; }
  if !streq(report_rule(2, ""), "--") { ok = false; }
  if !streq(report_rule(4, "ab"), "aaaa") { ok = false; }
  if !streq(report_rule(0, "-"), "") { ok = false; }
  if !streq(report_rule(-2, "-"), "") { ok = false; }
  return assert(ok, "rule: first byte repeated width times, defaults and empties");
}

fn t24() -> TestResult {
  let line = report_rule(9, "-");
  var ok = line.len() == 9;
  var headers = Vec[Str].new();
  headers.push("name");
  headers.push("age");
  var r1 = Vec[Str].new(); r1.push("Ada"); r1.push("36");
  var rows = Vec[Vec[Str]].new();
  rows.push(r1);
  let table = report_table(&headers, &rows, 0);
  let table_lines = string.lines(table);
  if table_lines.len() != 3 { ok = false; }
  if !line_is(&table_lines, 1, report_rule(7, "-")) { ok = false; }
  return assert(ok, "rule: lengths match the table separator (integration)");
}

fn main() -> Int {
  io.println("=== xiom.report conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.report: all tests passed");
  } else {
    io.println("xiom.report: tests failed");
  }
  return failed;
}
