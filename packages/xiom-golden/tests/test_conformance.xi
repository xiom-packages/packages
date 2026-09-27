// XIOM -- xiom.golden conformance tests (35 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API against synthetic byte buffers built in-test
// (no external data files):
//   * exact byte comparison: equal, first-difference offset, content vs
//     one-side-prefix kinds, empty buffers;
//   * text comparison: CRLF and lone-CR normalization, trailing-space and
//     trailing-newline tolerance flags, first differing line, line counts;
//   * hex rendering (full and bounded) and escape rendering including a
//     NUL byte, which must render as \x00 and never truncate the result;
//   * bounded line-diff summary: equal case, count/truncation header,
//     missing lines, trailing-newline marker;
//   * update-mode and tolerance flag parsing: defaults, every recognized
//     token, --max-lines bounds and the error catalog;
//   * path conventions: default tests/golden/<slug>.golden, join rules,
//     .actual/.new siblings, slug sanitising.
//
// Harness style mirrors xiom.lcov: one fn tN() -> Int per check, main sums
// them and returns the failure count. Str payloads are compared with
// str_compare and every Vec element read is bound to a typed local.

module golden_tests
use xiom.io; use xiom.test;
use xiom.string; use xiom.string.compare;
use xiom.golden;

// --------------------------------------------------
//  Harness helpers
// --------------------------------------------------

fn report(passed: Bool, name: Str) -> Int {
  if passed {
    io.println("  [PASS] " + name);
    return 0;
  }
  io.println("  [FAIL] " + name);
  return 1;
}

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn vec_eq(a: &Vec[UInt8], b: &Vec[UInt8]) -> Bool {
  if a.len() != b.len() {
    return false;
  }
  var i = 0;
  while i < a.len() {
    let x: UInt8 = a[i];
    let y: UInt8 = b[i];
    if (x as Int) != (y as Int) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// True when `needle` occurs in `hay` (hand rolled; no extra import).
fn contains(hay: Str, needle: Str) -> Bool {
  let hn = string.str_len(hay);
  let nn = string.str_len(needle);
  if nn == 0 {
    return true;
  }
  if nn > hn {
    return false;
  }
  var i = 0;
  while i + nn <= hn {
    let part = string.str_slice(hay, i, i + nn);
    if str_eq(part, needle) {
      return true;
    }
    i = i + 1;
  }
  return false;
}

fn expect_opts_err(r: Result[GoldenOptions, Str], want: Str, name: Str) -> Int {
  if r.is_ok {
    return report(false, name + " (expected Err)");
  }
  let got: Str = r.error;
  if !str_eq(got, want) {
    return report(false, name + " (got: " + got + ")");
  }
  return report(true, name);
}

// ASCII bytes of `s` (all fixture literals are NUL-free).
fn bytes(s: Str) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  let n = string.str_len(s);
  while i < n {
    let b: UInt8 = string.byte_at(s, i);
    v.push(b);
    i = i + 1;
  }
  return v;
}

// [0x00, 'A', LF, TAB, backslash, quote] -- the NUL-truncation fixture.
fn esc_bytes() -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push((0 as UInt8));
  v.push((65 as UInt8));
  v.push((10 as UInt8));
  v.push((9 as UInt8));
  v.push((92 as UInt8));
  v.push((34 as UInt8));
  return v;
}

fn args1(a: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  return v;
}

fn args2(a: Str, b: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  v.push(b);
  return v;
}

fn args5(a: Str, b: Str, c: Str, d: Str, e: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  v.push(e);
  return v;
}

// --------------------------------------------------
//  Byte comparison
// --------------------------------------------------

// Identical buffers compare equal with no first difference.
fn t1() -> Int {
  let a = bytes("hello");
  let b = bytes("hello");
  let r = golden_compare_bytes(&a, &b);
  if !golden_equal(&r) {
    return report(false, "bytes: equal buffers are equal");
  }
  if golden_kind(&r) != 0 {
    return report(false, "bytes: equal kind is 0");
  }
  return report(golden_first_diff(&r) == -1, "bytes: equal first_diff is -1");
}

// Content difference reports the exact first-difference offset.
fn t2() -> Int {
  let a = bytes("abcdef");
  let b = bytes("abcXef");
  let r = golden_compare_bytes(&a, &b);
  if golden_equal(&r) {
    return report(false, "bytes: content difference detected");
  }
  if golden_kind(&r) != 1 {
    return report(false, "bytes: content kind is 1");
  }
  return report(golden_first_diff(&r) == 3, "bytes: first difference at 3");
}

// Actual shorter than expected (expected has a longer prefix).
fn t3() -> Int {
  let a = bytes("abcdef");
  let b = bytes("abc");
  let r = golden_compare_bytes(&a, &b);
  if golden_kind(&r) != 2 {
    return report(false, "bytes: actual-shorter kind is 2");
  }
  if golden_first_diff(&r) != 3 {
    return report(false, "bytes: actual-shorter first_diff 3");
  }
  if golden_expected_len(&r) != 6 || golden_actual_len(&r) != 3 {
    return report(false, "bytes: actual-shorter lengths");
  }
  return report(true, "bytes: actual shorter detected");
}

// Actual longer than expected.
fn t4() -> Int {
  let a = bytes("abc");
  let b = bytes("abcdef");
  let r = golden_compare_bytes(&a, &b);
  if golden_kind(&r) != 3 {
    return report(false, "bytes: actual-longer kind is 3");
  }
  return report(golden_first_diff(&r) == 3, "bytes: actual-longer first_diff 3");
}

// Empty buffer boundaries.
fn t5() -> Int {
  let e = bytes("");
  let x = bytes("x");
  let r0 = golden_compare_bytes(&e, &e);
  if !golden_equal(&r0) {
    return report(false, "bytes: empty equals empty");
  }
  let r1 = golden_compare_bytes(&e, &x);
  if golden_kind(&r1) != 3 {
    return report(false, "bytes: empty vs x is kind 3");
  }
  return report(golden_first_diff(&r1) == 0, "bytes: empty vs x diff at 0");
}

// --------------------------------------------------
//  Text normalization and tolerance flags
// --------------------------------------------------

// CRLF and LF inputs compare equal after normalization.
fn t6() -> Int {
  let crlf = bytes("a\r\nb\r\n");
  let lf = bytes("a\nb\n");
  let raw = golden_compare_bytes(&crlf, &lf);
  if golden_equal(&raw) {
    return report(false, "text: raw CRLF differs from LF");
  }
  let r = golden_compare_text(&crlf, &lf, 0);
  return report(golden_equal(&r), "text: CRLF equals LF");
}

// A lone CR is a line break as well.
fn t7() -> Int {
  let cr = bytes("a\rb");
  let lf = bytes("a\nb");
  let r = golden_compare_text(&cr, &lf, 0);
  return report(golden_equal(&r), "text: lone CR equals LF");
}

// Trailing spaces differ by default and are ignored with flag bit 0.
fn t8() -> Int {
  let spaced = bytes("a  \nb\t\n");
  let plain = bytes("a\nb\n");
  let r0 = golden_compare_text(&spaced, &plain, 0);
  if golden_equal(&r0) {
    return report(false, "text: trailing spaces differ by default");
  }
  let flag = golden_flag_ignore_trailing_space();
  let r1 = golden_compare_text(&spaced, &plain, flag);
  return report(golden_equal(&r1), "text: trailing spaces ignored with flag");
}

// Trailing newline differs by default and is ignored with flag bit 1.
fn t9() -> Int {
  let a = bytes("a");
  let b = bytes("a\n");
  let r0 = golden_compare_text(&a, &b, 0);
  if golden_kind(&r0) != 3 {
    return report(false, "text: missing final newline is actual-longer");
  }
  if golden_first_diff(&r0) != 1 {
    return report(false, "text: missing final newline diff at 1");
  }
  let flag = golden_flag_ignore_trailing_newline();
  let r1 = golden_compare_text(&a, &b, flag);
  return report(golden_equal(&r1), "text: trailing newline ignored with flag");
}

// Multiple trailing newlines are dropped by the same flag.
fn t10() -> Int {
  let a = bytes("a\n\n");
  let b = bytes("a\n");
  let flag = golden_flag_ignore_trailing_newline();
  let r = golden_compare_text(&a, &b, flag);
  return report(golden_equal(&r), "text: repeated trailing newlines ignored");
}

// The first differing line is reported for text compares.
fn t11() -> Int {
  let a = bytes("a\nb\nc\n");
  let b = bytes("a\nb\nX\n");
  let r = golden_compare_text(&a, &b, 0);
  if golden_first_diff(&r) != 4 {
    return report(false, "text: first diff byte is 4");
  }
  return report(golden_diff_line(&r) == 3, "text: first diff line is 3");
}

// Line counts: empty 0, "a\n" 1, "a\nb" 2, "a\n\n" 2.
fn t12() -> Int {
  let e = bytes("");
  let a = bytes("a\n");
  let b = bytes("a\nb");
  let c = bytes("a\n\n");
  let r0 = golden_compare_text(&e, &e, 0);
  if golden_expected_lines(&r0) != 0 {
    return report(false, "lines: empty is 0");
  }
  let r1 = golden_compare_text(&a, &a, 0);
  if golden_expected_lines(&r1) != 1 {
    return report(false, "lines: a\\n is 1");
  }
  let r2 = golden_compare_text(&b, &b, 0);
  if golden_expected_lines(&r2) != 2 {
    return report(false, "lines: a\\nb is 2");
  }
  let r3 = golden_compare_text(&c, &c, 0);
  return report(golden_expected_lines(&r3) == 2, "lines: a\\n\\n is 2");
}

// --------------------------------------------------
//  Hex and escape rendering
// --------------------------------------------------

// Hex rendering includes NUL and high bytes as text.
fn t13() -> Int {
  var v = Vec[UInt8].new();
  v.push((0 as UInt8));
  v.push((65 as UInt8));
  v.push((255 as UInt8));
  let h = golden_hex(&v);
  return report(str_eq(h, "0041ff"), "hex: 0041ff");
}

// Bounded hex renders a truncation marker and the omitted count.
fn t14() -> Int {
  let v = bytes("ABCDE");
  let h = golden_hex_bounded(&v, 2);
  return report(str_eq(h, "4142...(3 more bytes)"), "hex: bounded marker");
}

// Escape rendering: NUL becomes \x00 and never truncates the result.
fn t15() -> Int {
  let v = esc_bytes();
  let s = golden_escape(&v);
  if string.str_len(s) != 13 {
    return report(false, "escape: NUL-safe length 13");
  }
  if !contains(s, "\\x00") {
    return report(false, "escape: NUL renders as \\x00");
  }
  if !contains(s, "\\n") || !contains(s, "\\t") {
    return report(false, "escape: LF and TAB escapes");
  }
  if !contains(s, "\\\\") || !contains(s, "\\\"") {
    return report(false, "escape: backslash and quote escapes");
  }
  return report(!contains(s, "\n"), "escape: no raw newline in output");
}

// Bounded escape rendering.
fn t16() -> Int {
  let v = bytes("ABCD");
  let s = golden_escape_bounded(&v, 2);
  return report(str_eq(s, "AB...(2 more bytes)"), "escape: bounded marker");
}

// Range escape rendering honours start/end.
fn t17() -> Int {
  let v = bytes("ABCDEF");
  let s = golden_escape_range(&v, 1, 4, -1);
  return report(str_eq(s, "BCD"), "escape: range 1..4 is BCD");
}

// --------------------------------------------------
//  Bounded line-diff summary
// --------------------------------------------------

// Equal buffers summarize as "golden: equal".
fn t18() -> Int {
  let a = bytes("x\ny\n");
  let b = bytes("x\ny\n");
  let s = golden_diff_summary(&a, &b, 0, 8);
  return report(str_eq(s, "golden: equal\n"), "summary: equal");
}

// The summary counts all differing lines and renders only the bound.
fn t19() -> Int {
  let a = bytes("l1\nl2\nl3\nl4\n");
  let b = bytes("x1\nx2\nx3\nx4\n");
  let s = golden_diff_summary(&a, &b, 0, 2);
  if !contains(s, "golden: 4 line(s) differ") {
    return report(false, "summary: header counts 4");
  }
  if !contains(s, "line 1") || !contains(s, "line 2") {
    return report(false, "summary: renders lines 1 and 2");
  }
  if contains(s, "line 3") {
    return report(false, "summary: line 3 beyond the bound");
  }
  return report(contains(s, "... (2 more differing line(s))"), "summary: truncation marker");
}

// A line present on one side only renders as <none>.
fn t20() -> Int {
  let a = bytes("a\nb\n");
  let b = bytes("a\nb\nc\n");
  let s = golden_diff_summary(&a, &b, 0, 8);
  if !contains(s, "line 3") {
    return report(false, "summary: missing line is line 3");
  }
  return report(contains(s, "expected=<none>"), "summary: missing side is <none>");
}

// A missing final newline is marked on the line that lacks it.
fn t21() -> Int {
  let a = bytes("a");
  let b = bytes("a\n");
  let s = golden_diff_summary(&a, &b, 0, 8);
  if !contains(s, "line 1") {
    return report(false, "summary: newline diff on line 1");
  }
  return report(contains(s, "actual=\"a\"\\n"), "summary: terminator marker");
}

// --------------------------------------------------
//  Options parsing
// --------------------------------------------------

// Defaults: no update, text mode, no flags, 8 lines, not quiet.
fn t22() -> Int {
  let args = Vec[Str].new();
  let r = golden_parse_options(&args);
  if !r.is_ok {
    return report(false, "opts: defaults parse");
  }
  let o = r.value;
  if golden_option_update(&o) {
    return report(false, "opts: update defaults off");
  }
  if !golden_option_text(&o) {
    return report(false, "opts: text defaults on");
  }
  if golden_option_flags(&o) != 0 {
    return report(false, "opts: flags default 0");
  }
  if golden_option_max_lines(&o) != 8 {
    return report(false, "opts: max-lines default 8");
  }
  return report(!golden_option_quiet(&o), "opts: quiet defaults off");
}

// Update, tolerance flags, quiet and explicit text mode.
fn t23() -> Int {
  let args = args5("-u", "--ignore-trailing-space", "--ignore-trailing-newline", "-q", "--text");
  let r = golden_parse_options(&args);
  if !r.is_ok {
    return report(false, "opts: update flags parse");
  }
  let o = r.value;
  if !golden_option_update(&o) {
    return report(false, "opts: -u enables update");
  }
  if golden_option_flags(&o) != 3 {
    return report(false, "opts: both tolerance bits set");
  }
  return report(golden_option_quiet(&o) && golden_option_text(&o), "opts: quiet and text set");
}

// --bytes switches off text mode; --max-lines sets the bound.
fn t24() -> Int {
  let args = args2("--bytes", "--max-lines=3");
  let r = golden_parse_options(&args);
  if !r.is_ok {
    return report(false, "opts: bytes/max-lines parse");
  }
  let o = r.value;
  if golden_option_text(&o) {
    return report(false, "opts: --bytes disables text");
  }
  return report(golden_option_max_lines(&o) == 3, "opts: max-lines is 3");
}

// Unknown flags produce the documented error.
fn t25() -> Int {
  let args = args1("--wat");
  let r = golden_parse_options(&args);
  return expect_opts_err(r, "golden: unknown flag: --wat", "opts: unknown flag rejected");
}

// Non-numeric max-lines value.
fn t26() -> Int {
  let args = args1("--max-lines=abc");
  let r = golden_parse_options(&args);
  return expect_opts_err(r, "golden: max-lines must be a number", "opts: non-numeric max-lines");
}

// Empty and zero max-lines values.
fn t27() -> Int {
  let r1 = golden_parse_options(&args1("--max-lines="));
  if r1.is_ok {
    return report(false, "opts: empty max-lines is Err");
  }
  let e1: Str = r1.error;
  if !str_eq(e1, "golden: max-lines needs a number") {
    return report(false, "opts: empty max-lines message");
  }
  let r2 = golden_parse_options(&args1("--max-lines=0"));
  if r2.is_ok {
    return report(false, "opts: zero max-lines is Err");
  }
  let e2: Str = r2.error;
  return report(str_eq(e2, "golden: max-lines out of range"), "opts: zero max-lines message");
}

// --------------------------------------------------
//  Path conventions
// --------------------------------------------------

// Default path uses the slug and the .golden suffix.
fn t28() -> Int {
  if !str_eq(golden_default_path("case 1"), "tests/golden/case_1.golden") {
    return report(false, "path: default path for 'case 1'");
  }
  return report(str_eq(golden_default_path("/"), "tests/golden/golden.golden"), "path: empty slug fallback");
}

// Join tolerates empty parts and trailing separators.
fn t29() -> Int {
  if !str_eq(golden_join("dir", "x"), "dir/x") {
    return report(false, "path: join dir + x");
  }
  if !str_eq(golden_join("dir/", "x"), "dir/x") {
    return report(false, "path: join dir/ + x");
  }
  if !str_eq(golden_join("", "x"), "x") {
    return report(false, "path: join empty dir");
  }
  if !str_eq(golden_join("d", ""), "d") {
    return report(false, "path: join empty name");
  }
  return report(str_eq(golden_join("dir\\", "x"), "dir\\x"), "path: join backslash dir");
}

// Actual/new siblings and the .golden predicate.
fn t30() -> Int {
  if !str_eq(golden_actual_path("a.golden"), "a.golden.actual") {
    return report(false, "path: actual sibling");
  }
  if !str_eq(golden_new_path("a.golden"), "a.golden.new") {
    return report(false, "path: new sibling");
  }
  if !golden_is_golden_path("a.golden") {
    return report(false, "path: .golden predicate true");
  }
  return report(!golden_is_golden_path("a.txt"), "path: .golden predicate false");
}

// Slug sanitising: collapse runs, drop edge separators, fallback.
fn t31() -> Int {
  if !str_eq(golden_slug("my test/1"), "my_test_1") {
    return report(false, "slug: spaces and slashes");
  }
  if !str_eq(golden_slug("a  b"), "a_b") {
    return report(false, "slug: runs collapse");
  }
  if !str_eq(golden_slug("weird<>"), "weird") {
    return report(false, "slug: trailing separator dropped");
  }
  return report(str_eq(golden_slug("///"), "golden"), "slug: fallback");
}

// Normalization keeps interior whitespace and strips only trailing runs.
fn t32() -> Int {
  let src = bytes("a  \nb \n");
  let flag = golden_flag_ignore_trailing_space();
  let out = golden_normalize_text(&src, flag);
  let want = bytes("a\nb\n");
  return report(vec_eq(&out, &want), "normalize: interior preserved, trailing stripped");
}

// CRLF plus the trailing-newline flag normalizes to the bare line.
fn t33() -> Int {
  let src = bytes("a\r\n\r\n");
  let flag = golden_flag_ignore_trailing_newline();
  let out = golden_normalize_text(&src, flag);
  let want = bytes("a");
  return report(vec_eq(&out, &want), "normalize: CRLF with newline flag");
}

// Kind names and flag bit accessors.
fn t34() -> Int {
  if !str_eq(golden_kind_name(0), "equal") {
    return report(false, "kind: 0 is equal");
  }
  if !str_eq(golden_kind_name(2), "actual-shorter") {
    return report(false, "kind: 2 is actual-shorter");
  }
  if !str_eq(golden_kind_name(9), "unknown") {
    return report(false, "kind: unknown fallback");
  }
  if golden_flag_ignore_trailing_space() != 1 {
    return report(false, "flags: space bit is 1");
  }
  return report(golden_flag_ignore_trailing_newline() == 2, "flags: newline bit is 2");
}

// Combined tolerance flags in a text compare.
fn t35() -> Int {
  let a = bytes("x \r\n");
  let b = bytes("x\n");
  let flags = golden_flag_ignore_trailing_space() + golden_flag_ignore_trailing_newline();
  let r = golden_compare_text(&a, &b, flags);
  return report(golden_equal(&r), "text: space+newline tolerance combined");
}

fn main() -> Int {
  io.println("=== xiom.golden conformance tests ===");
  var failed = 0;
  failed = failed + t1();
  failed = failed + t2();
  failed = failed + t3();
  failed = failed + t4();
  failed = failed + t5();
  failed = failed + t6();
  failed = failed + t7();
  failed = failed + t8();
  failed = failed + t9();
  failed = failed + t10();
  failed = failed + t11();
  failed = failed + t12();
  failed = failed + t13();
  failed = failed + t14();
  failed = failed + t15();
  failed = failed + t16();
  failed = failed + t17();
  failed = failed + t18();
  failed = failed + t19();
  failed = failed + t20();
  failed = failed + t21();
  failed = failed + t22();
  failed = failed + t23();
  failed = failed + t24();
  failed = failed + t25();
  failed = failed + t26();
  failed = failed + t27();
  failed = failed + t28();
  failed = failed + t29();
  failed = failed + t30();
  failed = failed + t31();
  failed = failed + t32();
  failed = failed + t33();
  failed = failed + t34();
  failed = failed + t35();
  if failed == 0 {
    io.println("xiom.golden: all tests passed");
  } else {
    io.println("xiom.golden: tests failed");
  }
  return failed;
}
