// XIOM -- xiom.tsv conformance tests (22 checks)
// Port task: prove the pure-XIOM xiom.tsv module against its documented
// IANA-style TSV subset (raw-tab delimiters, LF records, \\ \t \n \r escapes).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every element check
// below is routed through streq/field_is/cell_is/err_eq instead of `==`.

module tsv_tests
use xiom.io; use xiom.test; use xiom.tsv;
use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn field_is(fields: &Vec[Str], c: Int, want: Str) -> Bool {
  if c < 0 || c >= fields.len() { return false; }
  let got: Str = fields[c];
  return streq(got, want);
}

fn cell_is(rows: &Vec[Vec[Str]], r: Int, c: Int, want: Str) -> Bool {
  if r < 0 || r >= rows.len() { return false; }
  if c < 0 || c >= rows[r].len() { return false; }
  let got: Str = rows[r][c];
  return streq(got, want);
}

fn err_eq(r: Result[Str, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  let msg: Str = r.error;
  return streq(msg, want);
}

fn fields_err_eq(r: Result[Vec[Str], Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  let msg: Str = r.error;
  return streq(msg, want);
}

fn t1() -> TestResult {
  let r = tsv_parse_line("a\tb\tc");
  var ok = r.is_ok;
  if ok {
    let fields: Vec[Str] = r.value;
    if fields.len() != 3 { ok = false; }
    if !field_is(&fields, 0, "a") { ok = false; }
    if !field_is(&fields, 1, "b") { ok = false; }
    if !field_is(&fields, 2, "c") { ok = false; }
  }
  return assert(ok, "parse_line splits simple fields on raw tabs");
}

fn t2() -> TestResult {
  let blank = tsv_parse_line("");
  let tabs = tsv_parse_line("\t");
  let middle = tsv_parse_line("a\t\tc");
  var ok = blank.is_ok;
  if ok {
    let bf: Vec[Str] = blank.value;
    if bf.len() != 1 { ok = false; }
    if !field_is(&bf, 0, "") { ok = false; }
  }
  if !tabs.is_ok { ok = false; }
  if tabs.is_ok {
    let tf: Vec[Str] = tabs.value;
    if tf.len() != 2 { ok = false; }
    if !field_is(&tf, 0, "") { ok = false; }
    if !field_is(&tf, 1, "") { ok = false; }
  }
  if !middle.is_ok { ok = false; }
  if middle.is_ok {
    let mf: Vec[Str] = middle.value;
    if mf.len() != 3 { ok = false; }
    if !field_is(&mf, 0, "a") { ok = false; }
    if !field_is(&mf, 1, "") { ok = false; }
    if !field_is(&mf, 2, "c") { ok = false; }
  }
  return assert(ok, "empty line and empty fields are preserved");
}

fn t3() -> TestResult {
  let enc = tsv_escape_field("a\tb");
  var ok = streq(enc, "a\\tb");
  let only = tsv_escape_field("\t");
  if !streq(only, "\\t") { ok = false; }
  let dec = tsv_unescape_field("a\\tb");
  if !dec.is_ok { ok = false; }
  if dec.is_ok {
    let txt: Str = dec.value;
    if txt.len() != 3 { ok = false; }
    if !streq(txt, "a\tb") { ok = false; }
  }
  return assert(ok, "tab escapes to \\t and decodes back");
}

fn t4() -> TestResult {
  let enc = tsv_escape_field("l1\nl2");
  var ok = streq(enc, "l1\\nl2");
  let only = tsv_escape_field("\n");
  if !streq(only, "\\n") { ok = false; }
  let dec = tsv_unescape_field("l1\\nl2");
  if !dec.is_ok { ok = false; }
  if dec.is_ok {
    let txt: Str = dec.value;
    if txt.len() != 5 { ok = false; }
    if !streq(txt, "l1\nl2") { ok = false; }
  }
  return assert(ok, "LF escapes to \\n and decodes back");
}

fn t5() -> TestResult {
  let enc = tsv_escape_field("c\rz");
  var ok = streq(enc, "c\\rz");
  let only = tsv_escape_field("\r");
  if !streq(only, "\\r") { ok = false; }
  let dec = tsv_unescape_field("c\\rz");
  if !dec.is_ok { ok = false; }
  if dec.is_ok {
    let txt: Str = dec.value;
    if txt.len() != 3 { ok = false; }
    if !streq(txt, "c\rz") { ok = false; }
  }
  return assert(ok, "CR escapes to \\r and decodes back");
}

fn t6() -> TestResult {
  let enc = tsv_escape_field("back\\slash");
  var ok = streq(enc, "back\\\\slash");
  let only = tsv_escape_field("\\");
  if !streq(only, "\\\\") { ok = false; }
  let dec = tsv_unescape_field("back\\\\slash");
  if !dec.is_ok { ok = false; }
  if dec.is_ok {
    let txt: Str = dec.value;
    if txt.len() != 10 { ok = false; }
    if !streq(txt, "back\\slash") { ok = false; }
  }
  return assert(ok, "backslash escapes to \\\\ and decodes back");
}

fn t7() -> TestResult {
  var samples = Vec[Str].new();
  samples.push("");
  samples.push("plain");
  samples.push("tab\there");
  samples.push("line1\nline2");
  samples.push("cr\rhere");
  samples.push("back\\slash");
  samples.push("all\t\n\r\\ mixed");
  samples.push("café ✓");
  var ok = true;
  var i = 0;
  while i < samples.len() {
    let raw: Str = samples[i];
    let rt = tsv_unescape_field(tsv_escape_field(raw));
    if !rt.is_ok {
      ok = false;
    } else {
      let got: Str = rt.value;
      if !streq(got, raw) { ok = false; }
    }
    i = i + 1;
  }
  return assert(ok, "escape then unescape round-trips every sample");
}

fn t8() -> TestResult {
  let q = tsv_unescape_field("a\\qb");
  let trail = tsv_unescape_field("abc\\");
  let x = tsv_unescape_field("\\x41");
  var ok = err_eq(q, "tsv: invalid escape");
  if !err_eq(trail, "tsv: invalid escape") { ok = false; }
  if !err_eq(x, "tsv: invalid escape") { ok = false; }
  let line = tsv_parse_line("a\tb\\q");
  if !fields_err_eq(line, "tsv: invalid escape") { ok = false; }
  let valid = tsv_unescape_field("\\t\\n\\r\\\\");
  if !valid.is_ok { ok = false; }
  return assert(ok, "unknown and trailing escapes are Err; valid escapes are Ok");
}

fn t9() -> TestResult {
  let one = tsv_parse_line("solo");
  let two = tsv_parse_line("x\ty");
  let four = tsv_parse_line("1\t2\t3\t4");
  var ok = one.is_ok;
  if ok {
    let f1: Vec[Str] = one.value;
    if f1.len() != 1 { ok = false; }
    if !field_is(&f1, 0, "solo") { ok = false; }
  }
  if !two.is_ok { ok = false; }
  if two.is_ok {
    let f2: Vec[Str] = two.value;
    if f2.len() != 2 { ok = false; }
    if !field_is(&f2, 0, "x") { ok = false; }
    if !field_is(&f2, 1, "y") { ok = false; }
  }
  if !four.is_ok { ok = false; }
  if four.is_ok {
    let f4: Vec[Str] = four.value;
    if f4.len() != 4 { ok = false; }
    if !field_is(&f4, 2, "3") { ok = false; }
    if !field_is(&f4, 3, "4") { ok = false; }
  }
  return assert(ok, "raw tab bytes delimit fields");
}

fn t10() -> TestResult {
  let r = tsv_parse_line("a\\tb");
  var ok = r.is_ok;
  if ok {
    let f: Vec[Str] = r.value;
    if f.len() != 1 { ok = false; }
    if !field_is(&f, 0, "a\tb") { ok = false; }
  }
  let whole = tsv_parse("a\\tb\tc");
  if whole.len() != 1 { ok = false; }
  if !cell_is(&whole, 0, 0, "a\tb") { ok = false; }
  if !cell_is(&whole, 0, 1, "c") { ok = false; }
  return assert(ok, "an escaped tab is data inside one field");
}

fn t11() -> TestResult {
  let doc = tsv_parse("a\tb\r\nc\td\r\n");
  var ok = doc.len() == 2;
  if !cell_is(&doc, 0, 0, "a") { ok = false; }
  if !cell_is(&doc, 0, 1, "b") { ok = false; }
  if !cell_is(&doc, 1, 0, "c") { ok = false; }
  if !cell_is(&doc, 1, 1, "d") { ok = false; }
  let line = tsv_parse_line("x\ty\r");
  if !line.is_ok { ok = false; }
  if line.is_ok {
    let lf: Vec[Str] = line.value;
    if lf.len() != 2 { ok = false; }
    if !field_is(&lf, 0, "x") { ok = false; }
    if !field_is(&lf, 1, "y") { ok = false; }
  }
  return assert(ok, "CRLF rows and a trailing CR are terminator bytes");
}

fn t12() -> TestResult {
  let lf = tsv_parse("a\tb\n");
  let crlf = tsv_parse("a\tb\r\n");
  let twice = tsv_parse("a\n\n");
  var ok = lf.len() == 1;
  if crlf.len() != 1 { ok = false; }
  if !cell_is(&lf, 0, 0, "a") { ok = false; }
  if !cell_is(&lf, 0, 1, "b") { ok = false; }
  if !cell_is(&crlf, 0, 0, "a") { ok = false; }
  if twice.len() != 2 { ok = false; }
  if !cell_is(&twice, 0, 0, "a") { ok = false; }
  if !cell_is(&twice, 1, 0, "") { ok = false; }
  return assert(ok, "one trailing newline adds no row; two do");
}

fn t13() -> TestResult {
  let rows = tsv_parse("");
  var ok = rows.len() == 0;
  let written = tsv_write(&rows);
  if !streq(written, "") { ok = false; }
  return assert(ok, "empty text parses to zero rows and writes back empty");
}

fn t14() -> TestResult {
  let lf = tsv_parse("\n");
  let crlf = tsv_parse("\r\n");
  var ok = lf.len() == 1;
  if !cell_is(&lf, 0, 0, "") { ok = false; }
  if lf[0].len() != 1 { ok = false; }
  if crlf.len() != 1 { ok = false; }
  if !cell_is(&crlf, 0, 0, "") { ok = false; }
  return assert(ok, "a single empty line is one row with one empty field");
}

fn t15() -> TestResult {
  let rows = tsv_parse("a\t\tc");
  let bare = tsv_parse_line("\t\t");
  var ok = rows.len() == 1;
  if !cell_is(&rows, 0, 0, "a") { ok = false; }
  if !cell_is(&rows, 0, 1, "") { ok = false; }
  if !cell_is(&rows, 0, 2, "c") { ok = false; }
  if !bare.is_ok { ok = false; }
  if bare.is_ok {
    let bf: Vec[Str] = bare.value;
    if bf.len() != 3 { ok = false; }
    if !field_is(&bf, 0, "") { ok = false; }
    if !field_is(&bf, 1, "") { ok = false; }
    if !field_is(&bf, 2, "") { ok = false; }
  }
  return assert(ok, "empty fields between tabs survive");
}

fn t16() -> TestResult {
  var fields = Vec[Str].new();
  fields.push("a");
  fields.push("b\tc");
  fields.push("d\ne");
  fields.push("f\rg");
  fields.push("h\\i");
  fields.push("");
  let written = tsv_write_row(&fields);
  var ok = streq(written, "a\tb\\tc\td\\ne\tf\\rg\th\\\\i\t");
  var empty = Vec[Str].new();
  if !streq(tsv_write_row(&empty), "") { ok = false; }
  return assert(ok, "write_row escapes fields and joins with raw tabs");
}

fn t17() -> TestResult {
  var rows = Vec[Vec[Str]].new();
  var r1 = Vec[Str].new();
  r1.push("a");
  r1.push("b");
  rows.push(r1);
  var r2 = Vec[Str].new();
  r2.push("c\tx");
  r2.push("d");
  rows.push(r2);
  let written = tsv_write(&rows);
  var ok = streq(written, "a\tb\nc\\tx\td");
  var none = Vec[Vec[Str]].new();
  if !streq(tsv_write(&none), "") { ok = false; }
  var one = Vec[Vec[Str]].new();
  var solo = Vec[Str].new();
  solo.push("x");
  one.push(solo);
  if !streq(tsv_write(&one), "x") { ok = false; }
  return assert(ok, "write joins rows with LF and no trailing newline");
}

fn t18() -> TestResult {
  var fields = Vec[Str].new();
  fields.push("plain");
  fields.push("with\ttab");
  fields.push("with\nnewline");
  fields.push("with\rcr");
  fields.push("with\\slash");
  fields.push("");
  let written = tsv_write_row(&fields);
  let back = tsv_parse_line(written);
  var ok = back.is_ok;
  if ok {
    let got: Vec[Str] = back.value;
    if got.len() != fields.len() { ok = false; }
    var i = 0;
    while i < fields.len() {
      if !field_is(&got, i, fields[i]) { ok = false; }
      i = i + 1;
    }
  }
  return assert(ok, "write_row then parse_line round-trips every field");
}

fn t19() -> TestResult {
  var rows = Vec[Vec[Str]].new();
  var r1 = Vec[Str].new();
  r1.push("name");
  r1.push("note");
  rows.push(r1);
  var r2 = Vec[Str].new();
  r2.push("Ada");
  r2.push("loves\ttabs\nand\rslashes\\");
  rows.push(r2);
  let written = tsv_write(&rows);
  var back = tsv_parse(written);
  var ok = back.len() == 2;
  if !cell_is(&back, 0, 0, "name") { ok = false; }
  if !cell_is(&back, 0, 1, "note") { ok = false; }
  if !cell_is(&back, 1, 0, "Ada") { ok = false; }
  if !cell_is(&back, 1, 1, "loves\ttabs\nand\rslashes\\") { ok = false; }
  if !tsv_is_rectangular(&back) { ok = false; }
  return assert(ok, "write then parse round-trips a whole document");
}

fn t20() -> TestResult {
  let empty = Vec[Vec[Str]].new();
  let one = tsv_parse("a\tb");
  let square = tsv_parse("a\tb\nc\td");
  var zeros = Vec[Vec[Str]].new();
  var z1 = Vec[Str].new();
  var z2 = Vec[Str].new();
  zeros.push(z1);
  zeros.push(z2);
  var ok = tsv_is_rectangular(&empty);
  if !tsv_is_rectangular(&one) { ok = false; }
  if !tsv_is_rectangular(&square) { ok = false; }
  if !tsv_is_rectangular(&zeros) { ok = false; }
  return assert(ok, "rectangular is true for 0, 1 and equal-width rows");
}

fn t21() -> TestResult {
  let ragged = tsv_parse("a\tb\nc");
  let ragged2 = tsv_parse("a\nb\tc\td");
  var ok = !tsv_is_rectangular(&ragged);
  if tsv_is_rectangular(&ragged2) { ok = false; }
  return assert(ok, "rectangular is false when row widths differ");
}

fn t22() -> TestResult {
  let three = tsv_parse("a\tb\tc\nx");
  let empty = tsv_parse("");
  let one = tsv_parse("solo");
  var ok = tsv_field_count(&three) == 3;
  if tsv_field_count(&empty) != 0 { ok = false; }
  if tsv_field_count(&one) != 1 { ok = false; }
  return assert(ok, "field_count reports the first row width, 0 when empty");
}

fn main() -> Int {
  io.println("=== xiom.tsv conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.tsv: all tests passed");
  } else {
    io.println("xiom.tsv: tests failed");
  }
  return failed;
}
