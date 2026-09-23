// XIOM -- xiom.svg conformance tests (20 checks)
// Port task: prove the pure-XIOM xiom.svg module against its documented contract.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API: exact element strings and fixed attribute order,
// escaping (& < > " '), empty-attribute omission, clamping, element count and
// order, render layout (header, two-space indent, footer, LF only), negative
// coordinates, large integers and the escape round-trip of typical text.
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every check below is
// routed through streq.

module svg_tests
use xiom.io; use xiom.test;
use xiom.string; use xiom.string.builder; use xiom.string.compare;
use xiom.svg;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// True when `needle` occurs in `s` starting at byte `at`.
fn starts_at(s: Str, at: Int, needle: Str) -> Bool {
  let n = needle.len();
  if at < 0 || at + n > s.len() {
    return false;
  }
  let part = string.str_slice(s, at, at + n);
  return compare.str_compare(part, needle) == 0;
}

// Byte offset of the first occurrence of `needle`, -1 when absent.
fn pos_of(s: Str, needle: Str) -> Int {
  let found = string.index_of(s, needle);
  match found {
    Some(i) => { return i; },
    None => {},
  }
  return -1;
}

// Inverse of svg_escape for the five predefined entities (test-local; the
// package itself deliberately ships no unescape). Non-entity bytes pass
// through verbatim.
fn unescape_five(s: Str) -> Str {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < s.len() {
    let b = string.byte_at(s, i);
    if b == 38u8 && starts_at(s, i, "&amp;") {
      builder.sb_push_str(&mut out, "&");
      i = i + 5;
    } elif b == 38u8 && starts_at(s, i, "&lt;") {
      builder.sb_push_str(&mut out, "<");
      i = i + 4;
    } elif b == 38u8 && starts_at(s, i, "&gt;") {
      builder.sb_push_str(&mut out, ">");
      i = i + 4;
    } elif b == 38u8 && starts_at(s, i, "&quot;") {
      builder.sb_push_str(&mut out, "\"");
      i = i + 6;
    } elif b == 38u8 && starts_at(s, i, "&apos;") {
      builder.sb_push_str(&mut out, "'");
      i = i + 6;
    } else {
      out.push(b);
      i = i + 1;
    }
  }
  return builder.sb_to_str(&out);
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  let got = svg_rect(1, 2, 3, 4, "red");
  return assert(streq(got, "<rect x=\"1\" y=\"2\" width=\"3\" height=\"4\" fill=\"red\"/>"), "rect exact string and attribute order");
}

fn t2() -> TestResult {
  let r = svg_rect(0, 0, 5, 5, "");
  var ok = streq(r, "<rect x=\"0\" y=\"0\" width=\"5\" height=\"5\"/>");
  let c = svg_circle(0, 0, 1, "");
  if !streq(c, "<circle cx=\"0\" cy=\"0\" r=\"1\"/>") { ok = false; }
  let e = svg_ellipse(0, 0, 2, 3, "");
  if !streq(e, "<ellipse cx=\"0\" cy=\"0\" rx=\"2\" ry=\"3\"/>") { ok = false; }
  return assert(ok, "empty fill omits the attribute on rect, circle and ellipse");
}

fn t3() -> TestResult {
  let got = svg_circle(7, 8, 9, "blue");
  return assert(streq(got, "<circle cx=\"7\" cy=\"8\" r=\"9\" fill=\"blue\"/>"), "circle exact string");
}

fn t4() -> TestResult {
  let got = svg_ellipse(1, 2, 3, 4, "#f00");
  return assert(streq(got, "<ellipse cx=\"1\" cy=\"2\" rx=\"3\" ry=\"4\" fill=\"#f00\"/>"), "ellipse exact string");
}

fn t5() -> TestResult {
  let got = svg_line(0, 1, 2, 3, "black", 4);
  return assert(streq(got, "<line x1=\"0\" y1=\"1\" x2=\"2\" y2=\"3\" stroke=\"black\" stroke-width=\"4\"/>"), "line exact string with stroke and stroke-width");
}

fn t6() -> TestResult {
  let got = svg_text(5, 6, "a&b<c>d\"e'f", 12, "#000");
  return assert(streq(got, "<text x=\"5\" y=\"6\" font-size=\"12\" fill=\"#000\">a&amp;b&lt;c&gt;d&quot;e&apos;f</text>"), "text escapes all five metacharacters");
}

fn t7() -> TestResult {
  let got = svg_text(0, 0, "hi", 10, "");
  return assert(streq(got, "<text x=\"0\" y=\"0\" font-size=\"10\">hi</text>"), "text without fill omits the attribute");
}

fn t8() -> TestResult {
  let got = svg_path("M0 0 L10 10", "none", "red");
  return assert(streq(got, "<path d=\"M0 0 L10 10\" fill=\"none\" stroke=\"red\"/>"), "path exact string with fill and stroke");
}

fn t9() -> TestResult {
  let bare = svg_path("M1 1", "", "");
  var ok = streq(bare, "<path d=\"M1 1\"/>");
  let filled = svg_path("M2 2", "blue", "");
  if !streq(filled, "<path d=\"M2 2\" fill=\"blue\"/>") { ok = false; }
  return assert(ok, "path omits empty fill and empty stroke");
}

fn t10() -> TestResult {
  let got = svg_path("M0 0\"q\"", "", "a&b");
  return assert(streq(got, "<path d=\"M0 0&quot;q&quot;\" stroke=\"a&amp;b\"/>"), "path escapes d and stroke");
}

fn t11() -> TestResult {
  let a = svg_new(-5, 0);
  var ok = a.width == 1;
  if a.height != 1 { ok = false; }
  if svg_element_count(&a) != 0 { ok = false; }
  let b = svg_new(0, -3);
  if b.width != 1 { ok = false; }
  if b.height != 1 { ok = false; }
  let c = svg_new(100, 50);
  if c.width != 100 { ok = false; }
  if c.height != 50 { ok = false; }
  return assert(ok, "svg_new clamps non-positive sizes to 1 and keeps positives");
}

fn t12() -> TestResult {
  var d = svg_new(10, 10);
  var ok = svg_element_count(&d) == 0;
  svg_add(&mut d, svg_rect(0, 0, 1, 1, "red"));
  svg_add(&mut d, svg_circle(1, 1, 1, "blue"));
  svg_add(&mut d, svg_line(0, 0, 2, 2, "black", 1));
  if svg_element_count(&d) != 3 { ok = false; }
  var r = svg_render(&d);
  let rect_at = pos_of(r, "<rect");
  let circle_at = pos_of(r, "<circle");
  let line_at = pos_of(r, "<line");
  if rect_at < 0 { ok = false; }
  if circle_at <= rect_at { ok = false; }
  if line_at <= circle_at { ok = false; }
  return assert(ok, "element count grows by one per add and render preserves order");
}

fn t13() -> TestResult {
  var d = svg_new(20, 30);
  svg_add(&mut d, svg_rect(0, 0, 10, 10, "red"));
  svg_add(&mut d, svg_circle(5, 5, 2, ""));
  let want = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"20\" height=\"30\">\n  <rect x=\"0\" y=\"0\" width=\"10\" height=\"10\" fill=\"red\"/>\n  <circle cx=\"5\" cy=\"5\" r=\"2\"/>\n</svg>";
  return assert(streq(svg_render(&d), want), "render header, two-space indent per element and footer");
}

fn t14() -> TestResult {
  let d = svg_new(1, 1);
  let want = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"1\" height=\"1\">\n</svg>";
  return assert(streq(svg_render(&d), want), "render of an empty document is header + footer lines");
}

fn t15() -> TestResult {
  let r = svg_rect(-1, -2, -3, -4, "none");
  var ok = streq(r, "<rect x=\"-1\" y=\"-2\" width=\"-3\" height=\"-4\" fill=\"none\"/>");
  let l = svg_line(-10, -20, -30, -40, "red", 1);
  if !streq(l, "<line x1=\"-10\" y1=\"-20\" x2=\"-30\" y2=\"-40\" stroke=\"red\" stroke-width=\"1\"/>") { ok = false; }
  return assert(ok, "negative coordinates and sizes are emitted as-is");
}

fn t16() -> TestResult {
  let r = svg_rect(1234567890123456789, 0, 1, 1, "");
  var ok = streq(r, "<rect x=\"1234567890123456789\" y=\"0\" width=\"1\" height=\"1\"/>");
  let c = svg_circle(-2147483648, 2147483647, 0, "black");
  if !streq(c, "<circle cx=\"-2147483648\" cy=\"2147483647\" r=\"0\" fill=\"black\"/>") { ok = false; }
  return assert(ok, "large positive and negative integers render exactly");
}

fn t17() -> TestResult {
  let five = svg_escape("&<>\"'");
  var ok = streq(five, "&amp;&lt;&gt;&quot;&apos;");
  if !streq(svg_escape(""), "") { ok = false; }
  if !streq(svg_escape("plain text"), "plain text") { ok = false; }
  return assert(ok, "escape maps the five metacharacters and passes plain text through");
}

fn t18() -> TestResult {
  let typical = "R&D <tag attr=\"v\"> 'quoted' café ✓";
  let escaped = svg_escape(typical);
  var ok = streq(unescape_five(escaped), typical);
  if string.str_contains(escaped, "<") { ok = false; }
  if string.str_contains(escaped, ">") { ok = false; }
  if string.str_contains(escaped, "\"") { ok = false; }
  return assert(ok, "escape round-trips typical text and leaves no raw markup bytes");
}

fn t19() -> TestResult {
  var d = svg_new(8, 8);
  svg_add(&mut d, "<g id=\"layer1\"/>");
  var ok = svg_element_count(&d) == 1;
  let want = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"8\" height=\"8\">\n  <g id=\"layer1\"/>\n</svg>";
  if !streq(svg_render(&d), want) { ok = false; }
  return assert(ok, "svg_add appends a prebuilt element verbatim");
}

fn t20() -> TestResult {
  let got = svg_line(0, 0, 1, 1, "", 0);
  return assert(streq(got, "<line x1=\"0\" y1=\"0\" x2=\"1\" y2=\"1\" stroke=\"\" stroke-width=\"0\"/>"), "line always emits stroke, empty or not");
}

fn main() -> Int {
  io.println("=== xiom.svg conformance tests ===");
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
    io.println("xiom.svg: all tests passed");
  } else {
    io.println("xiom.svg: tests failed");
  }
  return failed;
}
