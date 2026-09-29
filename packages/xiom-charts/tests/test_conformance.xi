// XIOM -- xiom.charts conformance tests (28 checks)
// Port task: prove the pure-XIOM xiom.charts module against its documented contract.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API: series construction and the drift guard, min/max,
// layout clamping and plot geometry, linear scaling (exact endpoints,
// half-away-from-zero rounding, domain clamping, flat and negative domains),
// tick generation, XML escaping (five entities plus control-byte pass-through),
// the four element emitters (exact strings, attribute order, empty-attribute
// omission), and both document renderers (exact byte-for-byte fixtures, label
// escaping, single-point and empty series, x rounding, determinism).
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every comparison
// below is routed through streq and every Vec element read is bound to a
// typed local first. Tests call the module directly (no fn tables).

module charts_tests
use xiom.io; use xiom.test;
use xiom.string; use xiom.string.compare;
use xiom.charts;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// --------------------------------------------------
//  Fixture builders (Vec[Str] and Vec[Int] literals)
// --------------------------------------------------

fn lv1(a: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  return v;
}

fn lv2(a: Str, b: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  v.push(b);
  return v;
}

fn lv3(a: Str, b: Str, c: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  v.push(b);
  v.push(c);
  return v;
}

fn lv4(a: Str, b: Str, c: Str, d: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  return v;
}

fn lv5(a: Str, b: Str, c: Str, d: Str, e: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  v.push(e);
  return v;
}

fn iv1(a: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  return v;
}

fn iv2(a: Int, b: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  return v;
}

fn iv3(a: Int, b: Int, c: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  return v;
}

fn iv4(a: Int, b: Int, c: Int, d: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  return v;
}

fn iv5(a: Int, b: Int, c: Int, d: Int, e: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  v.push(e);
  return v;
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t01() -> TestResult {
  let s = series_new(lv2("a", "b"), iv2(1, 2));
  var ok = series_len(&s) == 2;
  let l0: Str = s.labels[0];
  if !streq(l0, "a") { ok = false; }
  let v0: Int = s.values[0];
  let v1: Int = s.values[1];
  if v0 != 1 { ok = false; }
  if v1 != 2 { ok = false; }
  return assert(ok, "series_new stores labels and values; series_len is 2");
}

fn t02() -> TestResult {
  let a = series_new(lv3("a", "b", "c"), iv5(1, 2, 3, 4, 5));
  var ok = series_len(&a) == 3;
  let b = series_new(lv5("a", "b", "c", "d", "e"), iv2(1, 2));
  if series_len(&b) != 2 { ok = false; }
  let c = series_new(Vec[Str].new(), Vec[Int].new());
  if series_len(&c) != 0 { ok = false; }
  return assert(ok, "series_len is the shorter of labels and values");
}

fn t03() -> TestResult {
  let s = series_new(lv3("a", "b", "c"), iv3(-3, 7, 2));
  var ok = chart_min(&s) == -3;
  if chart_max(&s) != 7 { ok = false; }
  let e = series_new(Vec[Str].new(), Vec[Int].new());
  if chart_min(&e) != 0 { ok = false; }
  if chart_max(&e) != 0 { ok = false; }
  return assert(ok, "chart_min and chart_max scan the usable prefix; empty is 0");
}

fn t04() -> TestResult {
  let a = chart_layout(0, -5, -3, 0);
  var ok = a.width == 1;
  if a.height != 1 { ok = false; }
  if a.pad != 0 { ok = false; }
  if a.ticks != 2 { ok = false; }
  let b = chart_layout(100, 50, 10, 7);
  if b.width != 100 { ok = false; }
  if b.height != 50 { ok = false; }
  if b.pad != 10 { ok = false; }
  if b.ticks != 7 { ok = false; }
  return assert(ok, "chart_layout clamps size to >= 1, pad to >= 0, ticks to >= 2");
}

fn t05() -> TestResult {
  let a = chart_layout(10, 10, 20, 1);
  var ok = a.pad == 4;
  if a.ticks != 2 { ok = false; }
  if chart_plot_w(&a) != 2 { ok = false; }
  if chart_plot_h(&a) != 2 { ok = false; }
  let b = chart_layout(5, 40, 2, 3);
  if b.pad != 2 { ok = false; }
  if chart_plot_w(&b) != 1 { ok = false; }
  if chart_plot_h(&b) != 36 { ok = false; }
  return assert(ok, "chart_layout clamps pad so the plot stays >= 1 x 1");
}

fn t06() -> TestResult {
  let l = chart_layout(100, 60, 10, 3);
  var ok = chart_plot_x0(&l) == 10;
  if chart_plot_y0(&l) != 10 { ok = false; }
  if chart_plot_w(&l) != 80 { ok = false; }
  if chart_plot_h(&l) != 40 { ok = false; }
  return assert(ok, "plot accessors return pad and size minus twice the pad");
}

fn t07() -> TestResult {
  var ok = chart_scale_y(0, 0, 10, 100, 10) == 100;
  if chart_scale_y(5, 0, 10, 100, 10) != 95 { ok = false; }
  if chart_scale_y(10, 0, 10, 100, 10) != 90 { ok = false; }
  return assert(ok, "chart_scale_y maps the domain ends and midpoint exactly");
}

fn t08() -> TestResult {
  var ok = chart_scale_y(1, 0, 4, 100, 10) == 97;
  if chart_scale_y(3, 0, 4, 100, 10) != 92 { ok = false; }
  return assert(ok, "chart_scale_y rounds exact halves away from zero");
}

fn t09() -> TestResult {
  var ok = chart_scale_y(-100, 0, 10, 100, 10) == 100;
  if chart_scale_y(100, 0, 10, 100, 10) != 90 { ok = false; }
  if chart_scale_y(5, 0, 10, 100, -5) != 100 { ok = false; }
  return assert(ok, "chart_scale_y clamps values to the domain and plot_h to >= 0");
}

fn t10() -> TestResult {
  var ok = chart_scale_y(-10, -10, 10, 0, 10) == 0;
  if chart_scale_y(0, -10, 10, 0, 10) != -5 { ok = false; }
  if chart_scale_y(10, -10, 10, 0, 10) != -10 { ok = false; }
  if chart_scale_y(-5, -10, 10, 0, 10) != -3 { ok = false; }
  return assert(ok, "chart_scale_y handles negative domains and negative y");
}

fn t11() -> TestResult {
  var ok = chart_scale_y(5, 5, 5, 100, 10) == 100;
  if chart_scale_y(6, 5, 5, 100, 10) != 90 { ok = false; }
  if chart_scale_y(4, 5, 5, 100, 10) != 100 { ok = false; }
  return assert(ok, "chart_scale_y widens a flat domain to [min, min + 1]");
}

fn t12() -> TestResult {
  let a = chart_ticks(0, 10, 3);
  var ok = a.len() == 3;
  let a0: Int = a[0];
  let a1: Int = a[1];
  let a2: Int = a[2];
  if a0 != 0 { ok = false; }
  if a1 != 5 { ok = false; }
  if a2 != 10 { ok = false; }
  let b = chart_ticks(0, 10, 1);
  if b.len() != 2 { ok = false; }
  let b0: Int = b[0];
  let b1: Int = b[1];
  if b0 != 0 { ok = false; }
  if b1 != 10 { ok = false; }
  return assert(ok, "chart_ticks spans the domain inclusive; count clamps to 2");
}

fn t13() -> TestResult {
  let a = chart_ticks(0, 10, 4);
  var ok = a.len() == 4;
  let a1: Int = a[1];
  let a2: Int = a[2];
  if a1 != 3 { ok = false; }
  if a2 != 7 { ok = false; }
  let b = chart_ticks(0, 100, 5);
  let b1: Int = b[1];
  let b2: Int = b[2];
  let b3: Int = b[3];
  if b1 != 25 { ok = false; }
  if b2 != 50 { ok = false; }
  if b3 != 75 { ok = false; }
  return assert(ok, "chart_ticks rounds interior ticks half away from zero");
}

fn t14() -> TestResult {
  let a = chart_ticks(5, 5, 2);
  var ok = a.len() == 2;
  let a0: Int = a[0];
  let a1: Int = a[1];
  if a0 != 5 { ok = false; }
  if a1 != 6 { ok = false; }
  let b = chart_ticks(-10, 10, 5);
  let b0: Int = b[0];
  let b1: Int = b[1];
  let b2: Int = b[2];
  let b3: Int = b[3];
  let b4: Int = b[4];
  if b0 != -10 { ok = false; }
  if b1 != -5 { ok = false; }
  if b2 != 0 { ok = false; }
  if b3 != 5 { ok = false; }
  if b4 != 10 { ok = false; }
  return assert(ok, "chart_ticks handles flat and negative domains");
}

fn t15() -> TestResult {
  var ok = streq(chart_escape("&<>\"'"), "&amp;&lt;&gt;&quot;&apos;");
  if !streq(chart_escape(""), "") { ok = false; }
  if !streq(chart_escape("plain text"), "plain text") { ok = false; }
  return assert(ok, "chart_escape maps the five metacharacters and passes plain text");
}

fn t16() -> TestResult {
  let raw = "\u{0001}\u{000B}\u{001F}\u{007F}";
  let esc = chart_escape(raw);
  var ok = streq(esc, raw);
  if string.str_len(esc) != 4 { ok = false; }
  let b0: UInt8 = string.byte_at(esc, 0);
  let b3: UInt8 = string.byte_at(esc, 3);
  if b0 != 1u8 { ok = false; }
  if b3 != 127u8 { ok = false; }
  return assert(ok, "chart_escape passes control bytes through byte-exact");
}

fn t17() -> TestResult {
  let got = chart_rect_element(1, 2, 3, 4, "red");
  var ok = streq(got, "<rect x=\"1\" y=\"2\" width=\"3\" height=\"4\" fill=\"red\"/>");
  let bare = chart_rect_element(0, 0, 5, 5, "");
  if !streq(bare, "<rect x=\"0\" y=\"0\" width=\"5\" height=\"5\"/>") { ok = false; }
  return assert(ok, "chart_rect_element format and empty-fill omission");
}

fn t18() -> TestResult {
  let got = chart_line_element(0, 1, 2, 3, "black", 4);
  var ok = streq(got, "<line x1=\"0\" y1=\"1\" x2=\"2\" y2=\"3\" stroke=\"black\" stroke-width=\"4\"/>");
  let esc = chart_line_element(0, 0, 1, 1, "a&b", 1);
  if !streq(esc, "<line x1=\"0\" y1=\"0\" x2=\"1\" y2=\"1\" stroke=\"a&amp;b\" stroke-width=\"1\"/>") { ok = false; }
  let empty = chart_line_element(0, 0, 1, 1, "", 1);
  if !streq(empty, "<line x1=\"0\" y1=\"0\" x2=\"1\" y2=\"1\" stroke=\"\" stroke-width=\"1\"/>") { ok = false; }
  return assert(ok, "chart_line_element escapes stroke and always emits stroke-width");
}

fn t19() -> TestResult {
  let got = chart_path_element("M0 0 L10 10", "none", "red", 2);
  var ok = streq(got, "<path d=\"M0 0 L10 10\" fill=\"none\" stroke=\"red\" stroke-width=\"2\"/>");
  let bare = chart_path_element("M1 1", "", "", 1);
  if !streq(bare, "<path d=\"M1 1\"/>") { ok = false; }
  let esc = chart_path_element("M0 0\"q\"", "", "a&b", 1);
  if !streq(esc, "<path d=\"M0 0&quot;q&quot;\" stroke=\"a&amp;b\" stroke-width=\"1\"/>") { ok = false; }
  return assert(ok, "chart_path_element escaping and empty fill/stroke omission");
}

fn t20() -> TestResult {
  let got = chart_text_element(5, 6, "a&b<c>d\"e'f", 12, "#000");
  var ok = streq(got, "<text x=\"5\" y=\"6\" font-size=\"12\" fill=\"#000\">a&amp;b&lt;c&gt;d&quot;e&apos;f</text>");
  let bare = chart_text_element(0, 0, "hi", 10, "");
  if !streq(bare, "<text x=\"0\" y=\"0\" font-size=\"10\">hi</text>") { ok = false; }
  return assert(ok, "chart_text_element escapes character data and omits empty fill");
}

fn t21() -> TestResult {
  let s = series_new(lv2("x", "y"), iv2(0, 10));
  let l = chart_layout(40, 40, 10, 2);
  let doc = chart_bar_svg(&s, &l);
  var want = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"40\" height=\"40\">";
  want = want + "\n  <line x1=\"10\" y1=\"10\" x2=\"10\" y2=\"30\" stroke=\"#000000\" stroke-width=\"1\"/>";
  want = want + "\n  <line x1=\"10\" y1=\"30\" x2=\"30\" y2=\"30\" stroke=\"#000000\" stroke-width=\"1\"/>";
  want = want + "\n  <line x1=\"10\" y1=\"30\" x2=\"30\" y2=\"30\" stroke=\"#e6e6e6\" stroke-width=\"1\"/>";
  want = want + "\n  <text x=\"6\" y=\"33\" font-size=\"10\" fill=\"#333333\">0</text>";
  want = want + "\n  <line x1=\"10\" y1=\"10\" x2=\"30\" y2=\"10\" stroke=\"#e6e6e6\" stroke-width=\"1\"/>";
  want = want + "\n  <text x=\"6\" y=\"13\" font-size=\"10\" fill=\"#333333\">10</text>";
  want = want + "\n  <rect x=\"10\" y=\"30\" width=\"9\" height=\"0\" fill=\"#4c78a8\"/>";
  want = want + "\n  <rect x=\"20\" y=\"10\" width=\"9\" height=\"20\" fill=\"#4c78a8\"/>";
  want = want + "\n  <text x=\"10\" y=\"42\" font-size=\"10\" fill=\"#333333\">x</text>";
  want = want + "\n  <text x=\"20\" y=\"42\" font-size=\"10\" fill=\"#333333\">y</text>";
  want = want + "\n</svg>";
  return assert(streq(doc, want), "chart_bar_svg exact document for a 2-point fixture");
}

fn t22() -> TestResult {
  let s = series_new(lv2("a&b", "c<d"), iv2(1, 2));
  let l = chart_layout(40, 40, 10, 2);
  let doc = chart_bar_svg(&s, &l);
  var ok = string.str_contains(doc, ">a&amp;b</text>");
  if !string.str_contains(doc, ">c&lt;d</text>") { ok = false; }
  if string.str_contains(doc, "a&b") { ok = false; }
  return assert(ok, "chart_bar_svg escapes category labels");
}

fn t23() -> TestResult {
  let s = series_new(lv3("p", "q", "r"), iv3(0, 10, 5));
  let l = chart_layout(40, 40, 10, 2);
  let doc = chart_line_svg(&s, &l);
  var ok = string.str_contains(doc, "<path d=\"M10 30 L20 10 L30 20\" fill=\"none\" stroke=\"#4c78a8\" stroke-width=\"1\"/>");
  if string.str_contains(doc, "<rect") { ok = false; }
  if !string.str_contains(doc, ">p</text>") { ok = false; }
  return assert(ok, "chart_line_svg emits one polyline path with scaled coordinates");
}

fn t24() -> TestResult {
  let s = series_new(lv1("p"), iv1(5));
  let l = chart_layout(40, 40, 10, 2);
  let doc = chart_line_svg(&s, &l);
  var ok = string.str_contains(doc, "<path d=\"M10 30\" fill=\"none\" stroke=\"#4c78a8\" stroke-width=\"1\"/>");
  if string.str_contains(doc, " L") { ok = false; }
  return assert(ok, "chart_line_svg renders a single point as a lone M command");
}

fn t25() -> TestResult {
  let s = series_new(Vec[Str].new(), Vec[Int].new());
  let l = chart_layout(40, 40, 10, 2);
  let doc = chart_bar_svg(&s, &l);
  var ok = string.str_contains(doc, "<line x1=\"10\" y1=\"10\" x2=\"10\" y2=\"30\" stroke=\"#000000\" stroke-width=\"1\"/>");
  if !string.str_contains(doc, ">1</text>") { ok = false; }
  if string.str_contains(doc, "<rect") { ok = false; }
  if string.str_contains(doc, "<path") { ok = false; }
  return assert(ok, "empty series renders axes and ticks only");
}

fn t26() -> TestResult {
  let s = series_new(lv4("a", "b", "c", "d"), iv4(0, 0, 0, 0));
  let l = chart_layout(20, 20, 5, 2);
  let doc = chart_line_svg(&s, &l);
  return assert(string.str_contains(doc, "<path d=\"M5 15 L8 15 L12 15 L15 15\" fill=\"none\" stroke=\"#4c78a8\" stroke-width=\"1\"/>"), "chart_line_svg rounds point x half away from zero");
}

fn t27() -> TestResult {
  let s = series_new(lv1("only"), iv1(0));
  let l = chart_layout(20, 20, 100, 2);
  var ok = l.pad == 9;
  if chart_plot_w(&l) != 2 { ok = false; }
  let doc = chart_bar_svg(&s, &l);
  if !string.str_contains(doc, "<rect x=\"9\" y=\"11\" width=\"1\" height=\"0\" fill=\"#4c78a8\"/>") { ok = false; }
  return assert(ok, "extreme padding collapses to a 2 x 2 plot without crashing");
}

fn t28() -> TestResult {
  let s = series_new(lv3("p", "q", "r"), iv3(0, 10, 5));
  let l = chart_layout(40, 40, 10, 2);
  var ok = streq(chart_bar_svg(&s, &l), chart_bar_svg(&s, &l));
  if !streq(chart_line_svg(&s, &l), chart_line_svg(&s, &l)) { ok = false; }
  return assert(ok, "renderers are deterministic across repeated calls");
}

fn main() -> Int {
  io.println("=== xiom.charts conformance tests ===");
  var failed: Int = 0;
  let r1 = t01();
  if r1.passed { io.println("  [PASS] " + r1.name); } else { io.println("  [FAIL] " + r1.name); failed = failed + 1; }
  let r2 = t02();
  if r2.passed { io.println("  [PASS] " + r2.name); } else { io.println("  [FAIL] " + r2.name); failed = failed + 1; }
  let r3 = t03();
  if r3.passed { io.println("  [PASS] " + r3.name); } else { io.println("  [FAIL] " + r3.name); failed = failed + 1; }
  let r4 = t04();
  if r4.passed { io.println("  [PASS] " + r4.name); } else { io.println("  [FAIL] " + r4.name); failed = failed + 1; }
  let r5 = t05();
  if r5.passed { io.println("  [PASS] " + r5.name); } else { io.println("  [FAIL] " + r5.name); failed = failed + 1; }
  let r6 = t06();
  if r6.passed { io.println("  [PASS] " + r6.name); } else { io.println("  [FAIL] " + r6.name); failed = failed + 1; }
  let r7 = t07();
  if r7.passed { io.println("  [PASS] " + r7.name); } else { io.println("  [FAIL] " + r7.name); failed = failed + 1; }
  let r8 = t08();
  if r8.passed { io.println("  [PASS] " + r8.name); } else { io.println("  [FAIL] " + r8.name); failed = failed + 1; }
  let r9 = t09();
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
  let r25 = t25();
  if r25.passed { io.println("  [PASS] " + r25.name); } else { io.println("  [FAIL] " + r25.name); failed = failed + 1; }
  let r26 = t26();
  if r26.passed { io.println("  [PASS] " + r26.name); } else { io.println("  [FAIL] " + r26.name); failed = failed + 1; }
  let r27 = t27();
  if r27.passed { io.println("  [PASS] " + r27.name); } else { io.println("  [FAIL] " + r27.name); failed = failed + 1; }
  let r28 = t28();
  if r28.passed { io.println("  [PASS] " + r28.name); } else { io.println("  [FAIL] " + r28.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.charts: all tests passed");
  } else {
    io.println("xiom.charts: tests failed");
  }
  return failed;
}
