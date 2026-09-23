// XIOM -- xiom.csv conformance tests (20 checks)
// Port task: prove the pure-XIOM xiom.csv module against its RFC 4180 subset.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module csv_tests
use xiom.io; use xiom.test; use xiom.csv;
use xiom.string.compare;

// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every element check
// below is routed through streq/field_is/cell_is instead of `==`.

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn field_is(fields: &Vec[Str], c: Int, want: Str) -> Bool {
  if c < 0 || c >= fields.len() { return false; }
  return streq(fields[c], want);
}

fn cell_is(rows: &Vec[Vec[Str]], r: Int, c: Int, want: Str) -> Bool {
  let got = csv_get(rows, r, c);
  match got {
    Some(v) => { return streq(v, want); },
    None => {},
  }
  return false;
}

fn cell_none(rows: &Vec[Vec[Str]], r: Int, c: Int) -> Bool {
  let got = csv_get(rows, r, c);
  match got {
    Some(_) => { return false; },
    None => { return true; },
  }
  return true;
}

fn t1() -> TestResult {
  var f = csv_parse_line("a,b,c");
  var ok = f.len() == 3;
  if !field_is(&f, 0, "a") { ok = false; }
  if !field_is(&f, 1, "b") { ok = false; }
  if !field_is(&f, 2, "c") { ok = false; }
  return assert(ok, "parse simple comma-separated fields");
}

fn t2() -> TestResult {
  var f = csv_parse_line("\"a,b\",c");
  var ok = f.len() == 2;
  if !field_is(&f, 0, "a,b") { ok = false; }
  if !field_is(&f, 1, "c") { ok = false; }
  return assert(ok, "quoted field may contain a comma");
}

fn t3() -> TestResult {
  var f = csv_parse_line("\"he said \"\"hi\"\"\"");
  var ok = f.len() == 1;
  if !field_is(&f, 0, "he said \"hi\"") { ok = false; }
  return assert(ok, "doubled quotes decode to one literal quote");
}

fn t4() -> TestResult {
  var rows = csv_parse("\"l1\nl2\",z");
  var ok = rows.len() == 1;
  if !cell_is(&rows, 0, 0, "l1\nl2") { ok = false; }
  if !cell_is(&rows, 0, 1, "z") { ok = false; }
  return assert(ok, "quoted field may contain a newline");
}

fn t5() -> TestResult {
  var rows = csv_parse("a,b\r\n1,2");
  var ok = rows.len() == 2;
  if !cell_is(&rows, 0, 0, "a") { ok = false; }
  if !cell_is(&rows, 0, 1, "b") { ok = false; }
  if !cell_is(&rows, 1, 0, "1") { ok = false; }
  if !cell_is(&rows, 1, 1, "2") { ok = false; }
  return assert(ok, "CRLF terminator parses as one record boundary");
}

fn t6() -> TestResult {
  var lf = csv_parse("a,b\n");
  var crlf = csv_parse("a,b\r\n");
  var ok = lf.len() == 1;
  if crlf.len() != 1 { ok = false; }
  if !cell_is(&lf, 0, 1, "b") { ok = false; }
  if !cell_is(&crlf, 0, 0, "a") { ok = false; }
  return assert(ok, "single trailing newline adds no empty record");
}

fn t7() -> TestResult {
  var rows = csv_parse("");
  var one = csv_parse_line("");
  var ok = rows.len() == 0;
  if one.len() != 1 { ok = false; }
  if !field_is(&one, 0, "") { ok = false; }
  return assert(ok, "empty text has no records; empty line has one empty field");
}

fn t8() -> TestResult {
  var rows = csv_parse("a,,c");
  var one = csv_parse_line(",");
  var quoted = csv_parse("\"\"");
  var ok = rows.len() == 1;
  if !cell_is(&rows, 0, 0, "a") { ok = false; }
  if !cell_is(&rows, 0, 1, "") { ok = false; }
  if !cell_is(&rows, 0, 2, "c") { ok = false; }
  if one.len() != 2 { ok = false; }
  if !field_is(&one, 0, "") { ok = false; }
  if !field_is(&one, 1, "") { ok = false; }
  if quoted.len() != 1 { ok = false; }
  if !cell_is(&quoted, 0, 0, "") { ok = false; }
  return assert(ok, "empty fields are preserved, including quoted empty");
}

fn t9() -> TestResult {
  var f = csv_parse_line(" a , b ");
  var only = csv_parse_line("  ");
  var ok = f.len() == 2;
  if !field_is(&f, 0, " a ") { ok = false; }
  if !field_is(&f, 1, " b ") { ok = false; }
  if only.len() != 1 { ok = false; }
  if !field_is(&only, 0, "  ") { ok = false; }
  return assert(ok, "unquoted whitespace is preserved verbatim");
}

fn t10() -> TestResult {
  var ok = csv_needs_quoting("a,b");
  if !csv_needs_quoting("a\"b") { ok = false; }
  if !csv_needs_quoting("a\nb") { ok = false; }
  if !csv_needs_quoting("a\rb") { ok = false; }
  if csv_needs_quoting("plain") { ok = false; }
  if csv_needs_quoting("") { ok = false; }
  return assert(ok, "needs_quoting detects comma, quote, LF and CR");
}

fn t11() -> TestResult {
  var ok = csv_needs_quoting(" lead");
  if !csv_needs_quoting("trail ") { ok = false; }
  if csv_needs_quoting("mid dle") { ok = false; }
  if csv_needs_quoting("x") { ok = false; }
  return assert(ok, "needs_quoting detects leading and trailing spaces only");
}

fn t12() -> TestResult {
  var fields = Vec[Str].new();
  fields.push("plain");
  fields.push("b,c");
  fields.push("d\"e");
  let w = csv_write_row(&fields);
  var ok = streq(w, "plain,\"b,c\",\"d\"\"e\"");
  var spaced = Vec[Str].new();
  spaced.push(" x");
  let w2 = csv_write_row(&spaced);
  if !streq(w2, "\" x\"") { ok = false; }
  var empty = Vec[Str].new();
  empty.push("");
  let w3 = csv_write_row(&empty);
  if !streq(w3, "") { ok = false; }
  return assert(ok, "write_row quotes and escapes only when needed");
}

fn t13() -> TestResult {
  var rows = Vec[Vec[Str]].new();
  var r1 = Vec[Str].new(); r1.push("a"); r1.push("b");
  var r2 = Vec[Str].new(); r2.push("c"); r2.push("d");
  rows.push(r1);
  rows.push(r2);
  let block = csv_write(&rows);
  var ok = streq(block, "a,b\nc,d");
  var empty = Vec[Vec[Str]].new();
  if !streq(csv_write(&empty), "") { ok = false; }
  var one = Vec[Vec[Str]].new();
  var r = Vec[Str].new(); r.push("x");
  one.push(r);
  if !streq(csv_write(&one), "x") { ok = false; }
  return assert(ok, "write joins rows with LF and no trailing terminator");
}

fn t14() -> TestResult {
  var fields = Vec[Str].new();
  fields.push("plain");
  fields.push("with,comma");
  fields.push("with \"quotes\"");
  fields.push("line\nbreak");
  fields.push("  padded  ");
  fields.push("");
  let written = csv_write_row(&fields);
  var back = csv_parse_line(written);
  var ok = back.len() == fields.len();
  var i = 0;
  while i < fields.len() {
    if !field_is(&back, i, fields[i]) { ok = false; }
    i = i + 1;
  }
  return assert(ok, "write_row then parse_line round-trips every field");
}

fn t15() -> TestResult {
  var rows = Vec[Vec[Str]].new();
  var r1 = Vec[Str].new();
  r1.push("a");
  r1.push("b,c");
  rows.push(r1);
  var r2 = Vec[Str].new();
  r2.push("d\"e");
  r2.push("f\ng");
  rows.push(r2);
  let block = csv_write(&rows);
  var back = csv_parse(block);
  var ok = back.len() == 2;
  if !cell_is(&back, 0, 0, "a") { ok = false; }
  if !cell_is(&back, 0, 1, "b,c") { ok = false; }
  if !cell_is(&back, 1, 0, "d\"e") { ok = false; }
  if !cell_is(&back, 1, 1, "f\ng") { ok = false; }
  if !csv_is_rectangular(&back) { ok = false; }
  return assert(ok, "write then parse round-trips a whole document");
}

fn t16() -> TestResult {
  var empty = Vec[Vec[Str]].new();
  var one = csv_parse("a,b");
  var square = csv_parse("a,b\nc,d");
  var zero_width = Vec[Vec[Str]].new();
  var z1 = Vec[Str].new();
  var z2 = Vec[Str].new();
  zero_width.push(z1);
  zero_width.push(z2);
  var ok = csv_is_rectangular(&empty);
  if !csv_is_rectangular(&one) { ok = false; }
  if !csv_is_rectangular(&square) { ok = false; }
  if !csv_is_rectangular(&zero_width) { ok = false; }
  return assert(ok, "rectangular is true for 0, 1 and equal-width rows");
}

fn t17() -> TestResult {
  var ragged = csv_parse("a,b\nc");
  var ragged2 = csv_parse("a\nb,c,d");
  var ok = !csv_is_rectangular(&ragged);
  if csv_is_rectangular(&ragged2) { ok = false; }
  return assert(ok, "rectangular is false when row widths differ");
}

fn t18() -> TestResult {
  var rows = csv_parse("a,b\nc,d");
  var ok = cell_is(&rows, 0, 0, "a");
  if !cell_is(&rows, 0, 1, "b") { ok = false; }
  if !cell_is(&rows, 1, 1, "d") { ok = false; }
  if !cell_none(&rows, 2, 0) { ok = false; }
  if !cell_none(&rows, 0, 2) { ok = false; }
  if !cell_none(&rows, 0, -1) { ok = false; }
  if !cell_none(&rows, -1, 0) { ok = false; }
  return assert(ok, "csv_get returns valid cells and None out of range");
}

fn t19() -> TestResult {
  var three = csv_parse("a,b,c\nx");
  var empty = csv_parse("");
  var one = csv_parse("solo");
  var ok = csv_field_count(&three) == 3;
  if csv_field_count(&empty) != 0 { ok = false; }
  if csv_field_count(&one) != 1 { ok = false; }
  return assert(ok, "field_count reports the first row width");
}

fn t20() -> TestResult {
  var rows = csv_parse("a\n\nb");
  var tail = csv_parse("a,b\n\n");
  var ok = rows.len() == 3;
  if !cell_is(&rows, 0, 0, "a") { ok = false; }
  if !cell_is(&rows, 1, 0, "") { ok = false; }
  if !cell_is(&rows, 2, 0, "b") { ok = false; }
  if tail.len() != 2 { ok = false; }
  if !cell_is(&tail, 1, 0, "") { ok = false; }
  return assert(ok, "blank line is a record with one empty field");
}

fn main() -> Int {
  io.println("=== xiom.csv conformance tests ===");
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
    io.println("xiom.csv: all tests passed");
  } else {
    io.println("xiom.csv: tests failed");
  }
  return failed;
}
