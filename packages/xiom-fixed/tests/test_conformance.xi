// XIOM -- xiom.fixed conformance tests (18 checks)
// Port task: prove the pure-XIOM xiom.fixed module against the rules pinned in
// SPEC.md: cumulative-width slicing, LF/CRLF line boundaries, raw vs trimmed
// parsing, and fixed-width writing with truncation and padding.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every output and
// element check below is routed through streq/cell_is instead of `==`.

module fixed_tests
use xiom.io; use xiom.test; use xiom.fixed;
use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn cell_is(rows: &Vec[Vec[Str]], r: Int, c: Int, want: Str) -> Bool {
  let got = fixed_field(rows, r, c);
  match got {
    Some(v) => { return streq(v, want); },
    None => {},
  }
  return false;
}

fn cell_none(rows: &Vec[Vec[Str]], r: Int, c: Int) -> Bool {
  let got = fixed_field(rows, r, c);
  match got {
    Some(_) => { return false; },
    None => { return true; },
  }
  return true;
}

fn widths2(a: Int, b: Int) -> Vec[Int] {
  var w = Vec[Int].new();
  w.push(a);
  w.push(b);
  return w;
}

fn widths3(a: Int, b: Int, c: Int) -> Vec[Int] {
  var w = Vec[Int].new();
  w.push(a);
  w.push(b);
  w.push(c);
  return w;
}

fn t1() -> TestResult {
  var w2 = widths2(3, 4);
  var rows = fixed_parse("abcDEFG\nxyz1234", &w2);
  var ok = rows.len() == 2;
  if !cell_is(&rows, 0, 0, "abc") { ok = false; }
  if !cell_is(&rows, 0, 1, "DEFG") { ok = false; }
  if !cell_is(&rows, 1, 0, "xyz") { ok = false; }
  if !cell_is(&rows, 1, 1, "1234") { ok = false; }
  var w3 = widths3(2, 3, 2);
  var three = fixed_parse("aaBBBcc\n11b22cc", &w3);
  if three.len() != 2 { ok = false; }
  if !cell_is(&three, 0, 0, "aa") { ok = false; }
  if !cell_is(&three, 0, 1, "BBB") { ok = false; }
  if !cell_is(&three, 0, 2, "cc") { ok = false; }
  if !cell_is(&three, 1, 0, "11") { ok = false; }
  if !cell_is(&three, 1, 1, "b22") { ok = false; }
  if !cell_is(&three, 1, 2, "cc") { ok = false; }
  return assert(ok, "parse slices each line at the cumulative widths (2-3 cols)");
}

fn t2() -> TestResult {
  var w = widths3(4, 4, 4);
  var rows = fixed_parse("abcdefgh\nxy", &w);
  var ok = rows.len() == 2;
  if !cell_is(&rows, 0, 0, "abcd") { ok = false; }
  if !cell_is(&rows, 0, 1, "efgh") { ok = false; }
  if !cell_is(&rows, 0, 2, "") { ok = false; }
  if !cell_is(&rows, 1, 0, "xy") { ok = false; }
  if !cell_is(&rows, 1, 1, "") { ok = false; }
  if !cell_is(&rows, 1, 2, "") { ok = false; }
  return assert(ok, "a short line yields \"\" for every missing field");
}

fn t3() -> TestResult {
  var w = widths2(3, 3);
  var z = widths2(0, 0);
  var none = Vec[Int].new();
  var rows = fixed_parse("", &w);
  var trimmed = fixed_parse_trimmed("", &w);
  var zero = fixed_parse("", &z);
  var empty = fixed_parse("", &none);
  var ok = rows.len() == 0;
  if trimmed.len() != 0 { ok = false; }
  if zero.len() != 0 { ok = false; }
  if empty.len() != 0 { ok = false; }
  return assert(ok, "empty text parses to no rows");
}

fn t4() -> TestResult {
  var w = widths2(2, 2);
  var rows = fixed_parse("aabb\n\nccdd", &w);
  var ok = rows.len() == 3;
  if !cell_is(&rows, 0, 0, "aa") { ok = false; }
  if !cell_is(&rows, 0, 1, "bb") { ok = false; }
  if !cell_is(&rows, 1, 0, "") { ok = false; }
  if !cell_is(&rows, 1, 1, "") { ok = false; }
  if !cell_is(&rows, 2, 0, "cc") { ok = false; }
  var only = fixed_parse("\n", &w);
  if only.len() != 1 { ok = false; }
  if !cell_is(&only, 0, 0, "") { ok = false; }
  if !cell_is(&only, 0, 1, "") { ok = false; }
  return assert(ok, "a blank line is one row of empty fields");
}

fn t5() -> TestResult {
  var w = widths2(2, 3);
  var rows = fixed_parse("aabb\r\ncc\r\n", &w);
  var ok = rows.len() == 2;
  if !cell_is(&rows, 0, 0, "aa") { ok = false; }
  // "bb" would read back as "bb\r" if the CR were kept as field data.
  if !cell_is(&rows, 0, 1, "bb") { ok = false; }
  if !cell_is(&rows, 1, 0, "cc") { ok = false; }
  if !cell_is(&rows, 1, 1, "") { ok = false; }
  return assert(ok, "CRLF terminates a line and the CR is not field data");
}

fn t6() -> TestResult {
  var w = widths2(4, 4);
  var no_nl = fixed_parse("aabbccdd", &w);
  var lf = fixed_parse("aabbccdd\n", &w);
  var crlf = fixed_parse("aabbccdd\r\n", &w);
  var dbl = fixed_parse("aabbccdd\n\n", &w);
  var ok = no_nl.len() == 1;
  if lf.len() != 1 { ok = false; }
  if crlf.len() != 1 { ok = false; }
  if dbl.len() != 2 { ok = false; }
  if !cell_is(&lf, 0, 1, "ccdd") { ok = false; }
  if !cell_is(&crlf, 0, 0, "aabb") { ok = false; }
  if !cell_is(&crlf, 0, 1, "ccdd") { ok = false; }
  if !cell_is(&dbl, 1, 0, "") { ok = false; }
  if !cell_is(&dbl, 1, 1, "") { ok = false; }
  return assert(ok, "one trailing newline adds no row; two add one blank row");
}

fn t7() -> TestResult {
  var w = widths2(6, 6);
  var raw = fixed_parse("  abc  xyz  \n", &w);
  var trimmed = fixed_parse_trimmed("  abc  xyz  \n", &w);
  var ok = raw.len() == 1;
  if trimmed.len() != 1 { ok = false; }
  if !cell_is(&raw, 0, 0, "  abc ") { ok = false; }
  if !cell_is(&raw, 0, 1, " xyz  ") { ok = false; }
  if !cell_is(&trimmed, 0, 0, "abc") { ok = false; }
  if !cell_is(&trimmed, 0, 1, "xyz") { ok = false; }
  return assert(ok, "parse returns raw fields; parse_trimmed trims both ends");
}

fn t8() -> TestResult {
  var w = widths3(2, 0, 2);
  var rows = fixed_parse("abXY", &w);
  var ok = rows.len() == 1;
  if !cell_is(&rows, 0, 0, "ab") { ok = false; }
  if !cell_is(&rows, 0, 1, "") { ok = false; }
  if !cell_is(&rows, 0, 2, "XY") { ok = false; }
  var neg = widths3(2, -1, 2);
  var rows2 = fixed_parse("abXY", &neg);
  if rows2.len() != 1 { ok = false; }
  if !cell_is(&rows2, 0, 0, "ab") { ok = false; }
  if !cell_is(&rows2, 0, 1, "") { ok = false; }
  if !cell_is(&rows2, 0, 2, "XY") { ok = false; }
  var zero = widths2(0, 0);
  var rows3 = fixed_parse("anything", &zero);
  if rows3.len() != 1 { ok = false; }
  if !cell_is(&rows3, 0, 0, "") { ok = false; }
  if !cell_is(&rows3, 0, 1, "") { ok = false; }
  return assert(ok, "a width <= 0 yields an empty field and consumes no input");
}

fn t9() -> TestResult {
  var w = widths2(4, 4);
  var rows = Vec[Vec[Str]].new();
  var r1 = Vec[Str].new(); r1.push("ab"); r1.push("c");
  var r2 = Vec[Str].new(); r2.push("d"); r2.push("ef");
  rows.push(r1);
  rows.push(r2);
  let got = fixed_write(&rows, &w, "");
  var ok = streq(got, "ab  c   \nd   ef  ");
  if !streq(fixed_write(&rows, &w, " "), "ab  c   \nd   ef  ") { ok = false; }
  var empty = Vec[Vec[Str]].new();
  if !streq(fixed_write(&empty, &w, ""), "") { ok = false; }
  var single = Vec[Vec[Str]].new();
  var s1 = Vec[Str].new(); s1.push("x"); s1.push("y");
  single.push(s1);
  if !streq(fixed_write(&single, &w, ""), "x   y   ") { ok = false; }
  return assert(ok, "write pins the exact padded output (LF join, no terminator)");
}

fn t10() -> TestResult {
  var w = widths2(3, 3);
  var rows = Vec[Vec[Str]].new();
  var r1 = Vec[Str].new(); r1.push("a"); r1.push("bb");
  rows.push(r1);
  var ok = streq(fixed_write(&rows, &w, "."), "a..bb.");
  if !streq(fixed_write(&rows, &w, "xyz"), "axxbbx") { ok = false; }
  if !streq(fixed_write(&rows, &w, ""), "a  bb ") { ok = false; }
  return assert(ok, "pad uses the first byte of the pad text, space when empty");
}

fn t11() -> TestResult {
  var w = widths2(3, 3);
  var rows = Vec[Vec[Str]].new();
  var r1 = Vec[Str].new(); r1.push("abcdef"); r1.push("x");
  rows.push(r1);
  var ok = streq(fixed_write(&rows, &w, ""), "abcx  ");
  var w0 = widths2(2, 0);
  var rows0 = Vec[Vec[Str]].new();
  var r0 = Vec[Str].new(); r0.push("ab"); r0.push("zzz");
  rows0.push(r0);
  if !streq(fixed_write(&rows0, &w0, ""), "ab") { ok = false; }
  return assert(ok, "cells longer than their width are truncated");
}

fn t12() -> TestResult {
  var w = widths3(2, 2, 2);
  var rows = Vec[Vec[Str]].new();
  var r1 = Vec[Str].new(); r1.push("a");
  rows.push(r1);
  var ok = streq(fixed_write(&rows, &w, ""), "a     ");
  var w2 = widths2(1, 1);
  var wide = Vec[Vec[Str]].new();
  var r2 = Vec[Str].new(); r2.push("a"); r2.push("b"); r2.push("c"); r2.push("d");
  wide.push(r2);
  if !streq(fixed_write(&wide, &w2, ""), "ab") { ok = false; }
  return assert(ok, "missing cells are empty; cells beyond the layout are ignored");
}

fn t13() -> TestResult {
  var w = widths2(4, 4);
  var rows = Vec[Vec[Str]].new();
  var r1 = Vec[Str].new(); r1.push("ab"); r1.push("cd");
  var r2 = Vec[Str].new(); r2.push("efgh"); r2.push("ij");
  rows.push(r1);
  rows.push(r2);
  let block = fixed_write(&rows, &w, "");
  var back = fixed_parse_trimmed(block, &w);
  var ok = back.len() == 2;
  if !cell_is(&back, 0, 0, "ab") { ok = false; }
  if !cell_is(&back, 0, 1, "cd") { ok = false; }
  if !cell_is(&back, 1, 0, "efgh") { ok = false; }
  if !cell_is(&back, 1, 1, "ij") { ok = false; }
  return assert(ok, "write then parse_trimmed round-trips fixed-size data");
}

fn t14() -> TestResult {
  var w = widths2(3, 3);
  var rows = fixed_parse("abcXYZ\ndef", &w);
  var ok = cell_is(&rows, 0, 0, "abc");
  if !cell_is(&rows, 0, 1, "XYZ") { ok = false; }
  if !cell_is(&rows, 1, 0, "def") { ok = false; }
  if !cell_is(&rows, 1, 1, "") { ok = false; }
  if !cell_none(&rows, 2, 0) { ok = false; }
  if !cell_none(&rows, 0, 2) { ok = false; }
  if !cell_none(&rows, 0, -1) { ok = false; }
  if !cell_none(&rows, -1, 0) { ok = false; }
  return assert(ok, "fixed_field returns valid cells and None out of range");
}

fn t15() -> TestResult {
  var a = widths2(3, 4);
  var b = widths3(3, -2, 4);
  var zeros = widths2(0, 0);
  var negative = widths2(-5, 2);
  var empty = Vec[Int].new();
  var ok = fixed_total_width(&a) == 7;
  if fixed_total_width(&b) != 7 { ok = false; }
  if fixed_total_width(&zeros) != 0 { ok = false; }
  if fixed_total_width(&negative) != 2 { ok = false; }
  if fixed_total_width(&empty) != 0 { ok = false; }
  return assert(ok, "total_width sums the non-negative widths only");
}

fn t16() -> TestResult {
  var three = widths3(1, 2, 3);
  var empty = Vec[Int].new();
  var ok = fixed_column_count(&three) == 3;
  if fixed_column_count(&empty) != 0 { ok = false; }
  var rows = fixed_parse("abc", &three);
  if rows.len() != 1 { ok = false; }
  if !cell_is(&rows, 0, 0, "a") { ok = false; }
  if !cell_is(&rows, 0, 1, "bc") { ok = false; }
  if !cell_is(&rows, 0, 2, "") { ok = false; }
  if !cell_none(&rows, 0, 3) { ok = false; }
  return assert(ok, "column_count is widths.len() and matches parsed rows");
}

fn t17() -> TestResult {
  var w = widths3(2, 3, 2);
  var rows = Vec[Vec[Str]].new();
  var r1 = Vec[Str].new(); r1.push("ab"); r1.push("cde"); r1.push("fg");
  var r2 = Vec[Str].new(); r2.push("hi"); r2.push("jkl"); r2.push("mn");
  rows.push(r1);
  rows.push(r2);
  let block = fixed_write(&rows, &w, "");
  var back = fixed_parse(block, &w);
  var ok = back.len() == 2;
  if !cell_is(&back, 0, 0, "ab") { ok = false; }
  if !cell_is(&back, 0, 1, "cde") { ok = false; }
  if !cell_is(&back, 0, 2, "fg") { ok = false; }
  if !cell_is(&back, 1, 0, "hi") { ok = false; }
  if !cell_is(&back, 1, 1, "jkl") { ok = false; }
  if !cell_is(&back, 1, 2, "mn") { ok = false; }
  return assert(ok, "write then parse round-trips exact-width rows");
}

fn t18() -> TestResult {
  var w = widths3(5, 1, 4);
  var rows = Vec[Vec[Str]].new();
  var r1 = Vec[Str].new();
  r1.push("Ada"); r1.push(""); r1.push("36"); r1.push("extra");
  rows.push(r1);
  let dotted = fixed_write(&rows, &w, ".");
  var ok = streq(dotted, "Ada...36..");
  if dotted.len() != 10 { ok = false; }
  var raw = fixed_parse(dotted, &w);
  if raw.len() != 1 { ok = false; }
  // '.' is pad data, not whitespace, so a raw parse keeps it.
  if !cell_is(&raw, 0, 0, "Ada..") { ok = false; }
  if !cell_is(&raw, 0, 1, ".") { ok = false; }
  if !cell_is(&raw, 0, 2, "36..") { ok = false; }
  let spaced = fixed_write(&rows, &w, "");
  if !streq(spaced, "Ada   36  ") { ok = false; }
  var back = fixed_parse_trimmed(spaced, &w);
  if back.len() != 1 { ok = false; }
  if !cell_is(&back, 0, 0, "Ada") { ok = false; }
  if !cell_is(&back, 0, 1, "") { ok = false; }
  if !cell_is(&back, 0, 2, "36") { ok = false; }
  return assert(ok, "pad + empty cell + extra cell layout round-trips trimmed");
}

fn main() -> Int {
  io.println("=== xiom.fixed conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.fixed: all tests passed");
  } else {
    io.println("xiom.fixed: tests failed");
  }
  return failed;
}
