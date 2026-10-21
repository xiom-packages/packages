// XIOM -- xiom.charts conformance tests (v0.2.0)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the declared v0.2.0 surface: public constants, Float64 model,
// deterministic formatting, escaping, color/colormap model, series, linear and
// log scales, axes, tick locators, layout, element emitters, annotations,
// figure defaults/setters, and all nine renderers (line, scatter, grouped bar,
// stacked bar, area, step, histogram, pie, doughnut) plus the dispatcher.
// Exact documents are pinned for line, grouped bar and pie; the remaining
// renderers use exact element/path assertions plus determinism checks.
//
// All Str equality goes through str_compare (BUG 17 discipline) and every
// Vec element read is bound to a typed local first.

module charts_tests

use xiom.io;
use xiom.test;
use xiom.string;
use xiom.string.compare;
use xiom.charts;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn close(a: Float64, b: Float64) -> Bool {
  var d = a - b;
  if d < 0.0 {
    d = 0.0 - d;
  }
  return d < 0.001;
}

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

fn fv1(a: Float64) -> Vec[Float64] {
  var v = Vec[Float64].new();
  v.push(a);
  return v;
}

fn fv2(a: Float64, b: Float64) -> Vec[Float64] {
  var v = Vec[Float64].new();
  v.push(a);
  v.push(b);
  return v;
}

fn fv3(a: Float64, b: Float64, c: Float64) -> Vec[Float64] {
  var v = Vec[Float64].new();
  v.push(a);
  v.push(b);
  v.push(c);
  return v;
}

fn fv4(a: Float64, b: Float64, c: Float64, d: Float64) -> Vec[Float64] {
  var v = Vec[Float64].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  return v;
}

fn fv5(a: Float64, b: Float64, c: Float64, d: Float64, e: Float64) -> Vec[Float64] {
  var v = Vec[Float64].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  v.push(e);
  return v;
}

fn hex(c: ChartColor) -> Str {
  return color_to_hex(c);
}

fn t01() -> TestResult {
  var ok = CHART_LINE == 0 && CHART_SCATTER == 1 && CHART_BAR == 2;
  if CHART_BAR_STACKED != 3 || CHART_AREA != 4 || CHART_STEP != 5 { ok = false; }
  if CHART_PIE != 6 || CHART_DOUGHNUT != 7 || CHART_HISTOGRAM != 8 { ok = false; }
  if MARKER_NONE != 0 || MARKER_TRIANGLE != 5 { ok = false; }
  if ANNOTATION_TEXT != 0 || ANNOTATION_VLINE != 3 { ok = false; }
  return assert(ok, "public kind, marker and annotation constants are stable");
}

fn t02() -> TestResult {
  let s = series_new("alpha", fv3(1.0, 2.0, 3.0), fv3(4.0, 5.0, 6.0));
  var ok = streq(s.name, "alpha");
  if s.xs.len() != 3 || s.ys.len() != 3 || s.labels.len() != 0 { ok = false; }
  if !s.auto_color || s.marker != MARKER_NONE { ok = false; }
  if !close(s.line_width, 2.0) || !close(s.opacity, 1.0) { ok = false; }
  if series_len(&s) != 3 { ok = false; }
  return assert(ok, "series_new stores numeric data and defaults");
}

fn t03() -> TestResult {
  let a = series_cat("a", lv2("x", "y"), fv3(1.0, 2.0, 3.0));
  var ok = series_len(&a) == 2;
  if a.xs.len() != 0 || a.labels.len() != 2 { ok = false; }
  let b = series_new("b", fv2(1.0, 2.0), fv4(1.0, 2.0, 3.0, 4.0));
  if series_len(&b) != 2 { ok = false; }
  let c = series_new("c", Vec[Float64].new(), Vec[Float64].new());
  if series_len(&c) != 0 { ok = false; }
  return assert(ok, "series_len is the shortest non-empty vector");
}

fn t04() -> TestResult {
  var s = series_cat("s", lv1("x"), fv1(1.0));
  series_set_color(&mut s, color_rgb(255, 0, 0));
  var ok = !s.auto_color;
  if !streq(hex(s.color), "#ff0000") { ok = false; }
  series_set_marker(&mut s, MARKER_DIAMOND);
  if s.marker != MARKER_DIAMOND { ok = false; }
  series_set_marker(&mut s, 99);
  if s.marker != MARKER_NONE { ok = false; }
  return assert(ok, "series_set_color and series_set_marker update the series");
}

fn t05() -> TestResult {
  let c = color_rgb(300, 0 - 4, 128);
  var ok = c.a == 1.0 && !c.none;
  if c.r != 255 || c.g != 0 || c.b != 128 { ok = false; }
  let d = color_rgba(1, 2, 3, 2.0);
  if !close(d.a, 1.0) { ok = false; }
  let e = color_rgba(1, 2, 3, 0.25);
  if !close(e.a, 0.25) { ok = false; }
  return assert(ok, "color_rgb/color_rgba clamp channels and alpha");
}

fn t06() -> TestResult {
  let n = color_none();
  var ok = n.none;
  if !streq(color_to_hex(n), "#000000") { ok = false; }
  let el = chart_rect_element(0.0, 0.0, 1.0, 1.0, n);
  if !streq(el, "<rect x=\"0\" y=\"0\" width=\"1\" height=\"1\" fill=\"none\"/>") { ok = false; }
  return assert(ok, "color_none emits the SVG none paint");
}

fn t07() -> TestResult {
  var ok = streq(hex(color_from_hex("#4C78A8")), "#4c78a8");
  if !streq(hex(color_from_hex("4c78a8")), "#000000") { ok = false; }
  if !streq(hex(color_from_hex("#4c78ag")), "#000000") { ok = false; }
  if !streq(hex(color_from_hex("#000000")), "#000000") { ok = false; }
  return assert(ok, "color_from_hex parses case-insensitively and fails closed");
}

fn t08() -> TestResult {
  let red = color_rgb(255, 0, 0);
  let blue = color_rgb(0, 0, 255);
  var ok = streq(hex(color_lerp(red, blue, 0.5)), "#800080");
  if !close(color_with_alpha(red, 0.4).a, 0.4) { ok = false; }
  if !color_with_alpha(color_none(), 0.4).none { ok = false; }
  if !color_lerp(red, color_none(), 0.5).none { ok = false; }
  return assert(ok, "color_lerp and color_with_alpha follow the model");
}

fn t09() -> TestResult {
  var ok = streq(hex(palette_color(0)), "#4c78a8");
  if !streq(hex(palette_color(10)), "#4c78a8") { ok = false; }
  if !streq(hex(palette_color(0 - 1)), "#bab0ac") { ok = false; }
  return assert(ok, "palette_color cycles ten colors and wraps negatives");
}

fn t10() -> TestResult {
  var ok = streq(hex(colormap_viridis(0.0)), "#440154");
  if !streq(hex(colormap_viridis(1.0)), "#fde725") { ok = false; }
  if !streq(hex(colormap_viridis(0.5)), "#23908c") { ok = false; }
  if !streq(hex(colormap_viridis(0 - 1.0)), "#440154") { ok = false; }
  return assert(ok, "viridis colormap endpoints and midpoint are deterministic");
}

fn t11() -> TestResult {
  var ok = streq(hex(colormap_magma(0.0)), "#000004");
  if !streq(hex(colormap_magma(1.0)), "#fcfdbf") { ok = false; }
  if !streq(hex(colormap_magma(0.5)), "#b63878") { ok = false; }
  return assert(ok, "magma colormap endpoints and midpoint are deterministic");
}

fn t12() -> TestResult {
  let s = scale_linear(0.0, 10.0, 100.0, 0.0);
  var ok = close(scale_map(&s, 0.0), 100.0);
  if !close(scale_map(&s, 10.0), 0.0) { ok = false; }
  if !close(scale_map(&s, 5.0), 50.0) { ok = false; }
  if !close(scale_map(&s, 0 - 5.0), 100.0) { ok = false; }
  if !close(scale_map(&s, 15.0), 0.0) { ok = false; }
  return assert(ok, "scale_linear maps endpoints, midpoint and clamps");
}

fn t13() -> TestResult {
  let s = scale_linear(5.0, 5.0, 100.0, 0.0);
  var ok = close(scale_min(&s), 5.0);
  if !close(scale_max(&s), 6.0) { ok = false; }
  if !close(scale_map(&s, 5.0), 100.0) { ok = false; }
  if !close(scale_map(&s, 6.0), 0.0) { ok = false; }
  let r = scale_linear(0.0, 10.0, 0.0, 100.0);
  if !close(scale_map(&r, 2.5), 25.0) { ok = false; }
  return assert(ok, "scale_linear widens flat domains and supports reversal");
}

fn t14() -> TestResult {
  let s = scale_linear(0.0, 10.0, 100.0, 0.0);
  var ok = close(scale_map_unclamped(&s, 0 - 5.0), 150.0);
  if !close(scale_map_unclamped(&s, 15.0), 0.0 - 50.0) { ok = false; }
  return assert(ok, "scale_map_unclamped extrapolates beyond the domain");
}

fn t15() -> TestResult {
  let s = scale_linear(0.0, 10.0, 100.0, 0.0);
  var ok = close(scale_invert(&s, 50.0), 5.0);
  if !close(scale_invert(&s, 100.0), 0.0) { ok = false; }
  let lg = scale_log(1.0, 100.0, 0.0, 100.0);
  if !close(scale_invert(&lg, 50.0), 10.0) { ok = false; }
  return assert(ok, "scale_invert round-trips linear and log scales");
}

fn t16() -> TestResult {
  let s = scale_log(0.0, 100.0, 0.0, 100.0);
  var ok = close(scale_min(&s), 1.0);
  if !close(scale_max(&s), 100.0) { ok = false; }
  if !close(scale_map(&s, 1.0), 0.0) { ok = false; }
  if !close(scale_map(&s, 10.0), 50.0) { ok = false; }
  if !close(scale_map(&s, 0.0), 0.0) { ok = false; }
  let d = scale_log(5.0, 5.0, 0.0, 100.0);
  if !close(scale_max(&d), 50.0) { ok = false; }
  return assert(ok, "scale_log normalizes non-positive and flat domains");
}

fn t17() -> TestResult {
  let s = scale_linear(2.0, 8.0, 0.0, 100.0);
  var ok = close(scale_min(&s), 2.0);
  if !close(scale_max(&s), 8.0) { ok = false; }
  if !close(scale_span(&s), 6.0) { ok = false; }
  return assert(ok, "scale_min/max/span expose the normalized domain");
}

fn t18() -> TestResult {
  let a = axis_auto("Y", 1);
  var ok = a.auto && !a.log;
  if a.tick_count != 2 { ok = false; }
  if !streq(a.label, "Y") { ok = false; }
  let l = axis_linear(5.0, 5.0, "", 5);
  if l.auto || l.log { ok = false; }
  if !close(l.min, 5.0) || !close(l.max, 6.0) { ok = false; }
  return assert(ok, "axis_auto/axis_linear clamp ticks and widen flat domains");
}

fn t19() -> TestResult {
  let a = axis_log(0.0, 100.0, "log", 4);
  var ok = !a.auto && a.log;
  if !close(a.min, 1.0) || !close(a.max, 100.0) { ok = false; }
  let t = axis_ticks(&a);
  if t.len() != 3 { ok = false; }
  let t0: Float64 = t[0];
  let t2: Float64 = t[2];
  if !close(t0, 1.0) || !close(t2, 100.0) { ok = false; }
  return assert(ok, "axis_log normalizes and axis_ticks emits powers of ten");
}

fn t20() -> TestResult {
  let a = axis_linear(0.0, 10.0, "", 3);
  let t = axis_ticks(&a);
  var ok = t.len() == 3;
  let t0: Float64 = t[0];
  let t1: Float64 = t[1];
  let t2: Float64 = t[2];
  if !close(t0, 0.0) || !close(t1, 5.0) || !close(t2, 10.0) { ok = false; }
  let s = axis_scale(&a, 0.0, 100.0);
  if !close(scale_map(&s, 5.0), 50.0) { ok = false; }
  return assert(ok, "axis_ticks and axis_scale use the axis domain");
}

fn t21() -> TestResult {
  let t = ticks_nice(0.0, 10.0, 6);
  var ok = t.len() == 6;
  let t0: Float64 = t[0];
  let t1: Float64 = t[1];
  let t5: Float64 = t[5];
  if !close(t0, 0.0) || !close(t1, 2.0) || !close(t5, 10.0) { ok = false; }
  return assert(ok, "ticks_nice steps by 2 across 0..10 for six ticks");
}

fn t22() -> TestResult {
  let t = ticks_nice(0.0, 10.0, 5);
  var ok = t.len() == 5;
  let t1: Float64 = t[1];
  let t3: Float64 = t[3];
  if !close(t1, 2.5) || !close(t3, 7.5) { ok = false; }
  let n = ticks_nice(0.0 - 3.0, 7.0, 6);
  if n.len() != 5 { ok = false; }
  let n0: Float64 = n[0];
  let n4: Float64 = n[4];
  if !close(n0, 0.0 - 2.0) || !close(n4, 6.0) { ok = false; }
  return assert(ok, "ticks_nice supports 2.5 steps and negative domains");
}

fn t23() -> TestResult {
  let a = ticks_log(1.0, 1000.0);
  var ok = a.len() == 4;
  let a0: Float64 = a[0];
  let a3: Float64 = a[3];
  if !close(a0, 1.0) || !close(a3, 1000.0) { ok = false; }
  let b = ticks_log(2.0, 500.0);
  if b.len() != 2 { ok = false; }
  let b0: Float64 = b[0];
  let b1: Float64 = b[1];
  if !close(b0, 10.0) || !close(b1, 100.0) { ok = false; }
  let c = ticks_log(2.0, 5.0);
  if c.len() != 2 { ok = false; }
  return assert(ok, "ticks_log emits powers of ten or domain endpoints");
}

fn t24() -> TestResult {
  let a = ticks_category(4);
  var ok = a.len() == 4;
  let a0: Float64 = a[0];
  let a3: Float64 = a[3];
  if !close(a0, 0.0) || !close(a3, 3.0) { ok = false; }
  if ticks_category(0).len() != 0 { ok = false; }
  if ticks_category(0 - 2).len() != 0 { ok = false; }
  return assert(ok, "ticks_category emits indices and ignores negative n");
}

fn t25() -> TestResult {
  var ok = streq(chart_format_float(1.23456, 3), "1.235");
  if !streq(chart_format_float(0.0 - 1.23456, 3), "-1.235") { ok = false; }
  if !streq(chart_format_float(0.0 - 0.004, 2), "0") { ok = false; }
  if !streq(chart_format_float(2.675, 2), "2.68") { ok = false; }
  if !streq(chart_format_float(10.0, 3), "10") { ok = false; }
  if !streq(chart_format_float(0.30000000000000004, 3), "0.3") { ok = false; }
  return assert(ok, "chart_format_float rounds half away and trims zeros");
}

fn t26() -> TestResult {
  var ok = streq(chart_format_value(1234.5), "1235");
  if !streq(chart_format_value(12.34), "12.3") { ok = false; }
  if !streq(chart_format_value(1.234), "1.23") { ok = false; }
  if !streq(chart_format_value(0.1234), "0.123") { ok = false; }
  if !streq(chart_format_value(0.0001234), "0.000123") { ok = false; }
  if !streq(chart_format_value(0.0 - 0.5), "-0.5") { ok = false; }
  return assert(ok, "chart_format_value adapts decimals by magnitude");
}

fn t27() -> TestResult {
  let l = chart_layout_default();
  var ok = close(l.width, 640.0) && close(l.height, 360.0);
  if !close(chart_plot_x0(&l), 56.0) || !close(chart_plot_y0(&l), 36.0) { ok = false; }
  if !close(chart_plot_w(&l), 564.0) || !close(chart_plot_h(&l), 280.0) { ok = false; }
  if !close(chart_plot_x1(&l), 620.0) || !close(chart_plot_y1(&l), 316.0) { ok = false; }
  return assert(ok, "chart_layout_default and plot accessors are stable");
}

fn t28() -> TestResult {
  let l = chart_layout(100.0, 80.0, 10.0, 20.0, 5.0, 15.0);
  var ok = close(chart_plot_w(&l), 70.0);
  if !close(chart_plot_h(&l), 60.0) { ok = false; }
  let u = chart_layout_uniform(100.0, 80.0, 10.0);
  if !close(u.left, 10.0) || !close(u.bottom, 10.0) { ok = false; }
  if !close(chart_plot_w(&u), 80.0) || !close(chart_plot_h(&u), 60.0) { ok = false; }
  return assert(ok, "chart_layout and chart_layout_uniform honor margins");
}

fn t29() -> TestResult {
  let a = chart_layout(0.0, 0.0 - 5.0, 0.0 - 3.0, 0.0, 0.0, 0.0);
  var ok = close(a.width, 1.0) && close(a.height, 1.0) && close(a.left, 0.0);
  let b = chart_layout(10.0, 10.0, 100.0, 100.0, 100.0, 100.0);
  if !close(b.left, 9.0) || !close(b.top, 9.0) { ok = false; }
  if chart_plot_w(&b) < 1.0 || chart_plot_h(&b) < 1.0 { ok = false; }
  return assert(ok, "chart_layout clamps size and margins to a >= 1 x 1 plot");
}

fn t30() -> TestResult {
  var ok = streq(chart_escape("&<>\"'"), "&amp;&lt;&gt;&quot;&apos;");
  if !streq(chart_escape(""), "") { ok = false; }
  if !streq(chart_escape("plain"), "plain") { ok = false; }
  let raw = "\u{0001}\u{000B}\u{001F}\u{007F}";
  if !streq(chart_escape(raw), raw) { ok = false; }
  return assert(ok, "chart_escape maps five entities and passes control bytes");
}

fn t31() -> TestResult {
  let got = chart_rect_element(1.0, 2.5, 0.0 - 3.0, 4.0, color_from_hex("#ff0000"));
  var ok = streq(got, "<rect x=\"1\" y=\"2.5\" width=\"-3\" height=\"4\" fill=\"#ff0000\"/>");
  let op = chart_rect_element(0.0, 0.0, 10.0, 5.0, color_rgba(0, 255, 0, 0.5));
  if !streq(op, "<rect x=\"0\" y=\"0\" width=\"10\" height=\"5\" fill=\"#00ff00\" fill-opacity=\"0.5\"/>") { ok = false; }
  return assert(ok, "chart_rect_element format, negative geometry and opacity");
}

fn t32() -> TestResult {
  let got = chart_circle_element(1.25, 2.0, 0.0 - 1.0, color_rgb(0, 0, 255));
  var ok = streq(got, "<circle cx=\"1.25\" cy=\"2\" r=\"0\" fill=\"#0000ff\"/>");
  let op = chart_circle_element(0.0, 0.0, 3.0, color_rgba(0, 0, 255, 0.25));
  if !streq(op, "<circle cx=\"0\" cy=\"0\" r=\"3\" fill=\"#0000ff\" fill-opacity=\"0.25\"/>") { ok = false; }
  return assert(ok, "chart_circle_element clamps radius and emits opacity");
}

fn t33() -> TestResult {
  let got = chart_line_element(0.0, 0.0, 10.0, 5.0, color_rgb(0, 0, 0), 1.5);
  var ok = streq(got, "<line x1=\"0\" y1=\"0\" x2=\"10\" y2=\"5\" stroke=\"#000000\" stroke-width=\"1.5\"/>");
  let op = chart_line_element(1.0, 2.0, 3.0, 4.0, color_rgba(255, 0, 0, 0.5), 2.0);
  if !streq(op, "<line x1=\"1\" y1=\"2\" x2=\"3\" y2=\"4\" stroke=\"#ff0000\" stroke-width=\"2\" stroke-opacity=\"0.5\"/>") { ok = false; }
  return assert(ok, "chart_line_element format and stroke opacity");
}

fn t34() -> TestResult {
  let got = chart_path_element("M0 0\"q\"", color_none(), color_rgb(255, 0, 0), 2.0);
  var ok = streq(got, "<path d=\"M0 0&quot;q&quot;\" fill=\"none\" stroke=\"#ff0000\" stroke-width=\"2\"/>");
  let bare = chart_path_element("M1 1", color_none(), color_none(), 1.0);
  if !streq(bare, "<path d=\"M1 1\" fill=\"none\" stroke=\"none\" stroke-width=\"1\"/>") { ok = false; }
  return assert(ok, "chart_path_element escapes d and emits paint pairs");
}

fn t35() -> TestResult {
  let got = chart_text_element(5.0, 6.0, "a&b<c>", 12.0, color_from_hex("#000000"));
  var ok = streq(got, "<text x=\"5\" y=\"6\" font-size=\"12\" fill=\"#000000\">a&amp;b&lt;c&gt;</text>");
  let op = chart_text_element(0.0, 0.0, "x", 10.0, color_rgba(0, 0, 0, 0.5));
  if !streq(op, "<text x=\"0\" y=\"0\" font-size=\"10\" fill=\"#000000\" fill-opacity=\"0.5\">x</text>") { ok = false; }
  return assert(ok, "chart_text_element escapes character data and emits opacity");
}

fn t36() -> TestResult {
  let got = chart_text_anchor_element(10.0, 20.0, "x", 10.0, color_rgb(51, 51, 51), "middle");
  var ok = streq(got, "<text x=\"10\" y=\"20\" font-size=\"10\" fill=\"#333333\" text-anchor=\"middle\">x</text>");
  let bare = chart_text_anchor_element(0.0, 0.0, "x", 10.0, color_rgb(0, 0, 0), "");
  if !streq(bare, "<text x=\"0\" y=\"0\" font-size=\"10\" fill=\"#000000\">x</text>") { ok = false; }
  return assert(ok, "chart_text_anchor_element emits anchor only when non-empty");
}

fn t37() -> TestResult {
  let p = fv4(1.0, 2.0, 3.0, 4.0);
  let got = chart_polygon_element(p, color_rgb(255, 0, 0));
  var ok = streq(got, "<polygon points=\"1,2 3,4\" fill=\"#ff0000\"/>");
  let empty = chart_polygon_element(fv1(1.0), color_rgb(0, 0, 0));
  if !streq(empty, "<polygon points=\"\" fill=\"#000000\"/>") { ok = false; }
  return assert(ok, "chart_polygon_element formats flat point pairs");
}

fn t38() -> TestResult {
  let p = fv4(0.0, 0.0, 10.0, 10.0);
  let got = chart_polyline_element(p, color_rgb(0, 0, 0), 1.0);
  var ok = streq(got, "<polyline points=\"0,0 10,10\" stroke=\"#000000\" stroke-width=\"1\"/>");
  let op = chart_polyline_element(fv4(0.0, 0.0, 10.0, 10.0), color_rgba(0, 0, 0, 0.5), 2.0);
  if !streq(op, "<polyline points=\"0,0 10,10\" stroke=\"#000000\" stroke-width=\"2\" stroke-opacity=\"0.5\"/>") { ok = false; }
  return assert(ok, "chart_polyline_element formats points and stroke opacity");
}

fn t39() -> TestResult {
  let got = chart_svg_open(100.0, 50.0);
  var ok = streq(got, "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"100\" height=\"50\" viewBox=\"0 0 100 50\">");
  if !streq(chart_svg_close(), "</svg>") { ok = false; }
  return assert(ok, "chart_svg_open/close emit the SVG 1.1 root");
}

fn t40() -> TestResult {
  let c = color_rgb(1, 2, 3);
  let a = annotation_text(1.0, 2.0, "note", c);
  var ok = a.kind == ANNOTATION_TEXT && streq(a.text, "note");
  if !close(a.x1, 1.0) || !close(a.y1, 2.0) { ok = false; }
  let b = annotation_arrow(0.0, 1.0, 2.0, 3.0, c);
  if b.kind != ANNOTATION_ARROW || !close(b.x2, 2.0) || !close(b.y2, 3.0) { ok = false; }
  let h = annotation_hline(5.0, c);
  if h.kind != ANNOTATION_HLINE || !close(h.y1, 5.0) { ok = false; }
  let v = annotation_vline(7.0, c);
  if v.kind != ANNOTATION_VLINE || !close(v.x1, 7.0) { ok = false; }
  return assert(ok, "annotation constructors encode kind and coordinates");
}

fn t41() -> TestResult {
  let f = figure_new(Vec[ChartSeries].new(), chart_layout_default());
  var ok = f.kind == CHART_LINE && f.x_axis.auto && f.y_axis.auto;
  if f.grid_x || !f.grid_y || !f.legend { ok = false; }
  if !close(f.bar_width, 0.8) || !close(f.doughnut_hole, 0.5) { ok = false; }
  if f.bins != 10 || f.annotations.len() != 0 { ok = false; }
  if !streq(hex(f.background), "#ffffff") { ok = false; }
  return assert(ok, "figure_new default axes, grid, legend and style");
}

fn t42() -> TestResult {
  var f = figure_new(Vec[ChartSeries].new(), chart_layout_default());
  figure_set_title(&mut f, "T");
  figure_set_axes(&mut f, axis_linear(0.0, 5.0, "X", 4), axis_log(1.0, 100.0, "Y", 3));
  figure_set_grid(&mut f, true, false);
  figure_set_legend(&mut f, false);
  var ok = streq(f.title, "T");
  if f.x_axis.auto || !close(f.x_axis.max, 5.0) { ok = false; }
  if !f.y_axis.log { ok = false; }
  if !f.grid_x || f.grid_y || f.legend { ok = false; }
  return assert(ok, "figure setters update title, axes, grid and legend");
}

fn t43() -> TestResult {
  var f = figure_new(Vec[ChartSeries].new(), chart_layout_default());
  figure_set_kind(&mut f, 99);
  var ok = f.kind == CHART_HISTOGRAM;
  figure_set_kind(&mut f, 0 - 1);
  if f.kind != CHART_LINE { ok = false; }
  figure_add_annotation(&mut f, annotation_hline(1.0, color_rgb(0, 0, 0)));
  if f.annotations.len() != 1 { ok = false; }
  return assert(ok, "figure_set_kind clamps and figure_add_annotation appends");
}

fn t44() -> TestResult {
  var ss = Vec[ChartSeries].new();
  ss.push(series_new("alpha", fv3(0.0, 5.0, 10.0), fv3(1.0, 4.0, 2.0)));
  var s2 = series_new("beta", fv3(0.0, 5.0, 10.0), fv3(2.0, 3.0, 5.0));
  series_set_marker(&mut s2, MARKER_SQUARE);
  ss.push(s2);
  let f = figure_new(ss, chart_layout(100.0, 100.0, 20.0, 20.0, 20.0, 20.0));
  let doc = chart_line_svg(&f);
  var ok = string.str_contains(doc, "stroke=\"#4c78a8\"");
  if !string.str_contains(doc, "stroke=\"#f58518\"") { ok = false; }
  if !string.str_contains(doc, "stroke=\"#4c78a8\" stroke-width=\"2\"") { ok = false; }
  if !string.str_contains(doc, ">alpha</text>") || !string.str_contains(doc, ">beta</text>") { ok = false; }
  if !string.str_contains(doc, "<rect x=") { ok = false; }
  return assert(ok, "chart_line_svg renders two series, markers and legend");
}

fn t45() -> TestResult {
  var ss = Vec[ChartSeries].new();
  ss.push(series_new("s", fv3(0.0, 5.0, 10.0), fv3(0.0, 10.0, 5.0)));
  var f = figure_new(ss, chart_layout(100.0, 100.0, 20.0, 20.0, 20.0, 20.0));
  figure_set_legend(&mut f, false);
  figure_set_axes(&mut f, axis_linear(0.0, 10.0, "", 3), axis_linear(0.0, 10.0, "", 3));
  let doc = chart_line_svg(&f);
  var want = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"100\" height=\"100\" viewBox=\"0 0 100 100\">";
  want = want + "\n  <rect x=\"0\" y=\"0\" width=\"100\" height=\"100\" fill=\"#ffffff\"/>";
  want = want + "\n  <line x1=\"20\" y1=\"80\" x2=\"80\" y2=\"80\" stroke=\"#e6e6e6\" stroke-width=\"1\"/>";
  want = want + "\n  <line x1=\"20\" y1=\"50\" x2=\"80\" y2=\"50\" stroke=\"#e6e6e6\" stroke-width=\"1\"/>";
  want = want + "\n  <line x1=\"20\" y1=\"20\" x2=\"80\" y2=\"20\" stroke=\"#e6e6e6\" stroke-width=\"1\"/>";
  want = want + "\n  <line x1=\"20\" y1=\"20\" x2=\"20\" y2=\"80\" stroke=\"#000000\" stroke-width=\"1\"/>";
  want = want + "\n  <line x1=\"20\" y1=\"80\" x2=\"80\" y2=\"80\" stroke=\"#000000\" stroke-width=\"1\"/>";
  want = want + "\n  <text x=\"14\" y=\"83\" font-size=\"10\" fill=\"#333333\" text-anchor=\"end\">0</text>";
  want = want + "\n  <text x=\"14\" y=\"53\" font-size=\"10\" fill=\"#333333\" text-anchor=\"end\">5</text>";
  want = want + "\n  <text x=\"14\" y=\"23\" font-size=\"10\" fill=\"#333333\" text-anchor=\"end\">10</text>";
  want = want + "\n  <text x=\"20\" y=\"96\" font-size=\"10\" fill=\"#333333\" text-anchor=\"middle\">0</text>";
  want = want + "\n  <text x=\"50\" y=\"96\" font-size=\"10\" fill=\"#333333\" text-anchor=\"middle\">5</text>";
  want = want + "\n  <text x=\"80\" y=\"96\" font-size=\"10\" fill=\"#333333\" text-anchor=\"middle\">10</text>";
  want = want + "\n  <path d=\"M20 80 L50 20 L80 50\" fill=\"none\" stroke=\"#4c78a8\" stroke-width=\"2\"/>";
  want = want + "\n</svg>";
  return assert(streq(doc, want), "chart_line_svg exact document for numeric x series");
}

fn t46() -> TestResult {
  var one = Vec[ChartSeries].new();
  one.push(series_new("s", fv1(0.0), fv1(5.0)));
  let f1 = figure_new(one, chart_layout(100.0, 100.0, 20.0, 20.0, 20.0, 20.0));
  let d1 = chart_line_svg(&f1);
  var ok = string.str_contains(d1, "<path d=\"M50 50\"");
  if string.str_contains(d1, " L") { ok = false; }
  var empty = Vec[ChartSeries].new();
  let f2 = figure_new(empty, chart_layout(100.0, 100.0, 20.0, 20.0, 20.0, 20.0));
  let d2 = chart_line_svg(&f2);
  if string.str_contains(d2, "<path") { ok = false; }
  if !string.str_contains(d2, "<line") { ok = false; }
  return assert(ok, "line single point is a lone M; empty series renders no path");
}

fn t47() -> TestResult {
  var ss = Vec[ChartSeries].new();
  var markers = Vec[Int].new();
  markers.push(MARKER_CIRCLE);
  markers.push(MARKER_SQUARE);
  markers.push(MARKER_DIAMOND);
  markers.push(MARKER_CROSS);
  markers.push(MARKER_TRIANGLE);
  var i = 0;
  while i < markers.len() {
    let m: Int = markers[i];
    var s = series_new("s", fv1(i as Float64), fv1(5.0));
    series_set_marker(&mut s, m);
    ss.push(s);
    i = i + 1;
  }
  var f = figure_new(ss, chart_layout(200.0, 100.0, 20.0, 20.0, 20.0, 20.0));
  figure_set_axes(&mut f, axis_linear(0.0, 4.0, "", 5), axis_linear(0.0, 10.0, "", 3));
  figure_set_legend(&mut f, false);
  let doc = chart_scatter_svg(&f);
  var ok = string.str_contains(doc, "<circle");
  if !string.str_contains(doc, "<rect x=") { ok = false; }
  if !string.str_contains(doc, "<polygon") { ok = false; }
  if !string.str_contains(doc, "stroke-width=\"1\"") { ok = false; }
  return assert(ok, "chart_scatter_svg emits all five marker shapes");
}

fn t48() -> TestResult {
  let f = figure_new(Vec[ChartSeries].new(), chart_layout(100.0, 100.0, 20.0, 20.0, 20.0, 20.0));
  let doc = chart_scatter_svg(&f);
  var ok = string.str_contains(doc, "<svg");
  if string.str_contains(doc, "<circle") || string.str_contains(doc, "<polygon") { ok = false; }
  return assert(ok, "empty scatter renders the frame only");
}

fn t49() -> TestResult {
  var ss = Vec[ChartSeries].new();
  ss.push(series_cat("s", lv3("a", "b", "c"), fv3(0.0, 10.0, 5.0)));
  var f = figure_new(ss, chart_layout(100.0, 100.0, 20.0, 20.0, 20.0, 20.0));
  figure_set_legend(&mut f, false);
  figure_set_axes(&mut f, axis_linear(0.0, 3.0, "", 4), axis_linear(0.0, 10.0, "", 5));
  figure_set_kind(&mut f, CHART_BAR);
  let doc = chart_bar_svg(&f);
  var want = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"100\" height=\"100\" viewBox=\"0 0 100 100\">";
  want = want + "\n  <rect x=\"0\" y=\"0\" width=\"100\" height=\"100\" fill=\"#ffffff\"/>";
  want = want + "\n  <line x1=\"20\" y1=\"80\" x2=\"80\" y2=\"80\" stroke=\"#e6e6e6\" stroke-width=\"1\"/>";
  want = want + "\n  <line x1=\"20\" y1=\"65\" x2=\"80\" y2=\"65\" stroke=\"#e6e6e6\" stroke-width=\"1\"/>";
  want = want + "\n  <line x1=\"20\" y1=\"50\" x2=\"80\" y2=\"50\" stroke=\"#e6e6e6\" stroke-width=\"1\"/>";
  want = want + "\n  <line x1=\"20\" y1=\"35\" x2=\"80\" y2=\"35\" stroke=\"#e6e6e6\" stroke-width=\"1\"/>";
  want = want + "\n  <line x1=\"20\" y1=\"20\" x2=\"80\" y2=\"20\" stroke=\"#e6e6e6\" stroke-width=\"1\"/>";
  want = want + "\n  <line x1=\"20\" y1=\"20\" x2=\"20\" y2=\"80\" stroke=\"#000000\" stroke-width=\"1\"/>";
  want = want + "\n  <line x1=\"20\" y1=\"80\" x2=\"80\" y2=\"80\" stroke=\"#000000\" stroke-width=\"1\"/>";
  want = want + "\n  <text x=\"14\" y=\"83\" font-size=\"10\" fill=\"#333333\" text-anchor=\"end\">0</text>";
  want = want + "\n  <text x=\"14\" y=\"68\" font-size=\"10\" fill=\"#333333\" text-anchor=\"end\">2.5</text>";
  want = want + "\n  <text x=\"14\" y=\"53\" font-size=\"10\" fill=\"#333333\" text-anchor=\"end\">5</text>";
  want = want + "\n  <text x=\"14\" y=\"38\" font-size=\"10\" fill=\"#333333\" text-anchor=\"end\">7.5</text>";
  want = want + "\n  <text x=\"14\" y=\"23\" font-size=\"10\" fill=\"#333333\" text-anchor=\"end\">10</text>";
  want = want + "\n  <text x=\"30\" y=\"96\" font-size=\"10\" fill=\"#333333\" text-anchor=\"middle\">a</text>";
  want = want + "\n  <text x=\"50\" y=\"96\" font-size=\"10\" fill=\"#333333\" text-anchor=\"middle\">b</text>";
  want = want + "\n  <text x=\"70\" y=\"96\" font-size=\"10\" fill=\"#333333\" text-anchor=\"middle\">c</text>";
  want = want + "\n  <rect x=\"22\" y=\"80\" width=\"16\" height=\"0\" fill=\"#4c78a8\"/>";
  want = want + "\n  <rect x=\"42\" y=\"20\" width=\"16\" height=\"60\" fill=\"#4c78a8\"/>";
  want = want + "\n  <rect x=\"62\" y=\"50\" width=\"16\" height=\"30\" fill=\"#4c78a8\"/>";
  want = want + "\n</svg>";
  return assert(streq(doc, want), "chart_bar_svg exact document for grouped categories");
}

fn t50() -> TestResult {
  var ss = Vec[ChartSeries].new();
  ss.push(series_cat("s", lv1("n"), fv1(0.0 - 5.0)));
  var f = figure_new(ss, chart_layout(100.0, 100.0, 20.0, 20.0, 20.0, 20.0));
  figure_set_legend(&mut f, false);
  figure_set_axes(&mut f, axis_linear(0.0, 1.0, "", 2), axis_linear(0.0 - 10.0, 10.0, "", 5));
  let doc = chart_bar_svg(&f);
  var ok = string.str_contains(doc, "<rect x=\"26\" y=\"50\" width=\"48\" height=\"15\" fill=\"#4c78a8\"/>");
  f.bar_width = 0.5;
  let half = chart_bar_svg(&f);
  if !string.str_contains(half, "<rect x=\"35\" y=\"50\" width=\"30\" height=\"15\" fill=\"#4c78a8\"/>") { ok = false; }
  var ns = Vec[ChartSeries].new();
  ns.push(series_new("s", Vec[Float64].new(), fv1(1.0)));
  var nf = figure_new(ns, chart_layout(100.0, 100.0, 20.0, 20.0, 20.0, 20.0));
  figure_set_legend(&mut nf, false);
  figure_set_kind(&mut nf, CHART_BAR);
  if !string.str_contains(chart_bar_svg(&nf), "text-anchor=\"middle\">1</text>") { ok = false; }
  return assert(ok, "grouped bars grow from zero for negatives and honor bar_width");
}

fn t51() -> TestResult {
  var ss = Vec[ChartSeries].new();
  ss.push(series_cat("a", lv1("k"), fv1(3.0)));
  ss.push(series_cat("b", lv1("k"), fv1(2.0)));
  var f = figure_new(ss, chart_layout(100.0, 100.0, 20.0, 20.0, 20.0, 20.0));
  figure_set_legend(&mut f, false);
  figure_set_axes(&mut f, axis_linear(0.0, 1.0, "", 2), axis_linear(0.0, 10.0, "", 3));
  figure_set_kind(&mut f, CHART_BAR_STACKED);
  let doc = chart_bar_stacked_svg(&f);
  var ok = string.str_contains(doc, "<rect x=\"26\" y=\"62\" width=\"48\" height=\"18\" fill=\"#4c78a8\"/>");
  if !string.str_contains(doc, "<rect x=\"26\" y=\"50\" width=\"48\" height=\"12\" fill=\"#f58518\"/>") { ok = false; }
  return assert(ok, "stacked bars accumulate positive values bottom-to-top");
}

fn t52() -> TestResult {
  var ss = Vec[ChartSeries].new();
  ss.push(series_cat("a", lv1("k"), fv1(0.0 - 2.0)));
  ss.push(series_cat("b", lv1("k"), fv1(0.0 - 3.0)));
  var f = figure_new(ss, chart_layout(100.0, 100.0, 20.0, 20.0, 20.0, 20.0));
  figure_set_legend(&mut f, false);
  figure_set_axes(&mut f, axis_linear(0.0, 1.0, "", 2), axis_linear(0.0 - 10.0, 10.0, "", 5));
  figure_set_kind(&mut f, CHART_BAR_STACKED);
  let doc = chart_bar_stacked_svg(&f);
  var ok = string.str_contains(doc, "<rect x=\"26\" y=\"50\" width=\"48\" height=\"6\" fill=\"#4c78a8\"/>");
  if !string.str_contains(doc, "<rect x=\"26\" y=\"56\" width=\"48\" height=\"9\" fill=\"#f58518\"/>") { ok = false; }
  return assert(ok, "stacked bars accumulate negative values downward");
}

fn t53() -> TestResult {
  var ss = Vec[ChartSeries].new();
  ss.push(series_new("s", fv3(0.0, 5.0, 10.0), fv3(2.0, 6.0, 4.0)));
  var f = figure_new(ss, chart_layout(100.0, 100.0, 20.0, 20.0, 20.0, 20.0));
  figure_set_legend(&mut f, false);
  figure_set_axes(&mut f, axis_linear(0.0, 10.0, "", 3), axis_linear(0.0, 10.0, "", 3));
  figure_set_kind(&mut f, CHART_AREA);
  let doc = chart_area_svg(&f);
  var ok = string.str_contains(doc, "<polygon points=\"20,80 20,68 50,44 80,56 80,80\" fill=\"#4c78a8\" fill-opacity=\"0.3\"/>");
  if !string.str_contains(doc, "<path d=\"M20 68 L50 44 L80 56\" fill=\"none\" stroke=\"#4c78a8\" stroke-width=\"2\"/>") { ok = false; }
  return assert(ok, "chart_area_svg emits a closed polygon plus the outline");
}

fn t54() -> TestResult {
  var ss = Vec[ChartSeries].new();
  ss.push(series_new("a", fv2(0.0, 10.0), fv2(1.0, 2.0)));
  ss.push(series_new("b", fv2(0.0, 10.0), fv2(2.0, 1.0)));
  var f = figure_new(ss, chart_layout(100.0, 100.0, 20.0, 20.0, 20.0, 20.0));
  figure_set_kind(&mut f, CHART_AREA);
  let doc = chart_area_svg(&f);
  var ok = string.str_contains(doc, "fill=\"#4c78a8\" fill-opacity=\"0.3\"");
  if !string.str_contains(doc, "fill=\"#f58518\" fill-opacity=\"0.3\"") { ok = false; }
  let e = figure_new(Vec[ChartSeries].new(), chart_layout_default());
  if string.str_contains(chart_area_svg(&e), "<polygon") { ok = false; }
  return assert(ok, "area renderer supports multiple and empty series");
}

fn t55() -> TestResult {
  var ss = Vec[ChartSeries].new();
  ss.push(series_new("s", fv3(0.0, 5.0, 10.0), fv3(0.0, 10.0, 5.0)));
  var f = figure_new(ss, chart_layout(100.0, 100.0, 20.0, 20.0, 20.0, 20.0));
  figure_set_legend(&mut f, false);
  figure_set_axes(&mut f, axis_linear(0.0, 10.0, "", 3), axis_linear(0.0, 10.0, "", 3));
  figure_set_kind(&mut f, CHART_STEP);
  let doc = chart_step_svg(&f);
  return assert(string.str_contains(doc, "<path d=\"M20 80 L50 80 L50 20 L80 20 L80 50\" fill=\"none\" stroke=\"#4c78a8\" stroke-width=\"2\"/>"), "chart_step_svg emits step-post geometry");
}

fn t56() -> TestResult {
  var ss = Vec[ChartSeries].new();
  ss.push(series_new("s", fv1(0.0), fv1(0.0)));
  var f = figure_new(ss, chart_layout(100.0, 100.0, 20.0, 20.0, 20.0, 20.0));
  figure_set_legend(&mut f, false);
  figure_set_axes(&mut f, axis_linear(0.0, 10.0, "", 3), axis_linear(0.0, 10.0, "", 3));
  figure_set_kind(&mut f, CHART_STEP);
  let doc = chart_step_svg(&f);
  var ok = string.str_contains(doc, "<path d=\"M20 80\"");
  if string.str_contains(doc, " L") { ok = false; }
  return assert(ok, "step chart renders a single point as a lone M");
}

fn t57() -> TestResult {
  var ss = Vec[ChartSeries].new();
  ss.push(series_new("s", Vec[Float64].new(), fv4(1.0, 1.0, 2.0, 2.0)));
  var s2 = series_new("t", Vec[Float64].new(), fv2(2.0, 3.0));
  ss.push(s2);
  var f = figure_new(ss, chart_layout(100.0, 100.0, 20.0, 20.0, 20.0, 20.0));
  figure_set_legend(&mut f, false);
  figure_set_axes(&mut f, axis_linear(1.0, 3.0, "", 3), axis_auto("", 4));
  f.bins = 3;
  figure_set_kind(&mut f, CHART_HISTOGRAM);
  let doc = chart_histogram_svg(&f);
  var ok = string.str_contains(doc, "<rect x=\"20\" y=\"40\" width=\"20\" height=\"40\" fill=\"#4c78a8\"/>");
  if !string.str_contains(doc, "<rect x=\"40\" y=\"20\" width=\"20\" height=\"60\" fill=\"#4c78a8\"/>") { ok = false; }
  if !string.str_contains(doc, "<rect x=\"60\" y=\"60\" width=\"20\" height=\"20\" fill=\"#4c78a8\"/>") { ok = false; }
  return assert(ok, "histogram pools series and emits one bar per non-empty bin");
}

fn t58() -> TestResult {
  var ss = Vec[ChartSeries].new();
  ss.push(series_new("s", Vec[Float64].new(), fv4(5.0, 5.0, 5.0, 5.0)));
  var f = figure_new(ss, chart_layout(100.0, 100.0, 20.0, 20.0, 20.0, 20.0));
  figure_set_legend(&mut f, false);
  f.bins = 4;
  figure_set_kind(&mut f, CHART_HISTOGRAM);
  let doc = chart_histogram_svg(&f);
  return assert(string.str_contains(doc, "<rect x=\"50\" y=\"20\" width=\"15\" height=\"60\" fill=\"#4c78a8\"/>"), "histogram widens a flat data range without crashing");
}

fn t59() -> TestResult {
  var ss = Vec[ChartSeries].new();
  ss.push(series_new("s", Vec[Float64].new(), fv3(1.0, 2.0, 3.0)));
  var f = figure_new(ss, chart_layout(100.0, 100.0, 20.0, 20.0, 20.0, 20.0));
  figure_set_legend(&mut f, false);
  figure_set_axes(&mut f, axis_linear(0.0, 10.0, "", 3), axis_linear(0.0, 10.0, "", 3));
  f.bins = 0;
  figure_set_kind(&mut f, CHART_HISTOGRAM);
  let doc = chart_histogram_svg(&f);
  var ok = string.str_contains(doc, "<rect x=\"20\" y=\"62\" width=\"60\" height=\"18\" fill=\"#4c78a8\"/>");
  if string.str_contains(doc, "<rect x=\"80\"") { ok = false; }
  return assert(ok, "histogram clamps bins to >= 1 and honors explicit axes");
}

fn t60() -> TestResult {
  var ss = Vec[ChartSeries].new();
  ss.push(series_cat("s", lv3("a", "b", "c"), fv3(1.0, 1.0, 0.0)));
  var f = figure_new(ss, chart_layout(100.0, 100.0, 10.0, 10.0, 10.0, 10.0));
  figure_set_legend(&mut f, false);
  figure_set_kind(&mut f, CHART_PIE);
  let doc = chart_pie_svg(&f);
  var want = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"100\" height=\"100\" viewBox=\"0 0 100 100\">";
  want = want + "\n  <rect x=\"0\" y=\"0\" width=\"100\" height=\"100\" fill=\"#ffffff\"/>";
  want = want + "\n  <path d=\"M50 50 L50 14 A36 36 0 0 1 50 86 Z\" fill=\"#4c78a8\" stroke=\"#ffffff\" stroke-width=\"1\"/>";
  want = want + "\n  <path d=\"M50 50 L50 86 A36 36 0 0 1 50 14 Z\" fill=\"#f58518\" stroke=\"#ffffff\" stroke-width=\"1\"/>";
  want = want + "\n</svg>";
  return assert(streq(doc, want), "chart_pie_svg exact document for two equal slices");
}

fn t61() -> TestResult {
  var ss = Vec[ChartSeries].new();
  ss.push(series_cat("s", lv1("all"), fv1(5.0)));
  var f = figure_new(ss, chart_layout(100.0, 100.0, 10.0, 10.0, 10.0, 10.0));
  figure_set_legend(&mut f, false);
  figure_set_kind(&mut f, CHART_PIE);
  let doc = chart_pie_svg(&f);
  var ok = string.str_contains(doc, "A36 36 0 1 1");
  if !string.str_contains(doc, "M50 50 L50 14") { ok = false; }
  var df = f;
  figure_set_kind(&mut df, CHART_DOUGHNUT);
  df.doughnut_hole = 0.5;
  if !string.str_contains(chart_doughnut_svg(&df), "A18 18 0 1 0") { ok = false; }
  var neg = Vec[ChartSeries].new();
  neg.push(series_cat("s", lv1("x"), fv1(0.0 - 3.0)));
  var f2 = figure_new(neg, chart_layout(100.0, 100.0, 10.0, 10.0, 10.0, 10.0));
  figure_set_legend(&mut f2, false);
  if string.str_contains(chart_pie_svg(&f2), "<path") { ok = false; }
  return assert(ok, "pie handles a full circle and ignores non-positive values");
}

fn t62() -> TestResult {
  var ss = Vec[ChartSeries].new();
  ss.push(series_cat("s", lv2("a", "b"), fv2(1.0, 1.0)));
  var f = figure_new(ss, chart_layout(100.0, 100.0, 10.0, 10.0, 10.0, 10.0));
  figure_set_legend(&mut f, false);
  figure_set_kind(&mut f, CHART_DOUGHNUT);
  f.doughnut_hole = 0.5;
  let doc = chart_doughnut_svg(&f);
  var ok = string.str_contains(doc, "M50 14 A36 36 0 0 1 50 86 L50 68 A18 18 0 0 0 50 32 Z");
  if !string.str_contains(doc, "M50 86 A36 36 0 0 1 50 14 L50 32 A18 18 0 0 0 50 68 Z") { ok = false; }
  return assert(ok, "doughnut emits outer and inner arcs with the configured hole");
}

fn t63() -> TestResult {
  var ss = Vec[ChartSeries].new();
  ss.push(series_cat("s", lv2("a", "b"), fv2(1.0, 1.0)));
  var f = figure_new(ss, chart_layout(100.0, 100.0, 10.0, 10.0, 10.0, 10.0));
  figure_set_legend(&mut f, false);
  figure_set_kind(&mut f, CHART_DOUGHNUT);
  f.doughnut_hole = 2.0;
  let doc = chart_doughnut_svg(&f);
  var ok = string.str_contains(doc, "A34.2 34.2");
  f.doughnut_hole = 0.0 - 1.0;
  let pie = chart_doughnut_svg(&f);
  if string.str_contains(pie, "A34.2 34.2") { ok = false; }
  if !string.str_contains(pie, "M50 50 L50 14") { ok = false; }
  return assert(ok, "doughnut_hole clamps to 0..0.95");
}

fn t64() -> TestResult {
  var ss = Vec[ChartSeries].new();
  ss.push(series_new("s", fv3(0.0, 5.0, 10.0), fv3(0.0, 5.0, 10.0)));
  var f = figure_new(ss, chart_layout(100.0, 100.0, 20.0, 20.0, 20.0, 20.0));
  figure_set_legend(&mut f, false);
  figure_set_axes(&mut f, axis_linear(0.0, 10.0, "", 3), axis_linear(0.0, 10.0, "", 3));
  let c = color_rgb(255, 0, 0);
  figure_add_annotation(&mut f, annotation_text(5.0, 5.0, "peak", c));
  figure_add_annotation(&mut f, annotation_arrow(0.0, 0.0, 10.0, 10.0, c));
  figure_add_annotation(&mut f, annotation_hline(5.0, c));
  figure_add_annotation(&mut f, annotation_vline(5.0, c));
  let doc = chart_line_svg(&f);
  var ok = string.str_contains(doc, ">peak</text>");
  if !string.str_contains(doc, "<polygon points=") { ok = false; }
  if !string.str_contains(doc, "<line x1=\"20\" y1=\"50\" x2=\"80\" y2=\"50\" stroke=\"#ff0000\" stroke-width=\"1\"/>") { ok = false; }
  if !string.str_contains(doc, "<line x1=\"50\" y1=\"20\" x2=\"50\" y2=\"80\" stroke=\"#ff0000\" stroke-width=\"1\"/>") { ok = false; }
  return assert(ok, "annotations render text, arrows and reference lines");
}

fn t65() -> TestResult {
  var ss = Vec[ChartSeries].new();
  ss.push(series_new("alpha", fv2(0.0, 1.0), fv2(1.0, 2.0)));
  ss.push(series_new("beta", fv2(0.0, 1.0), fv2(2.0, 1.0)));
  var f = figure_new(ss, chart_layout(100.0, 100.0, 20.0, 20.0, 20.0, 20.0));
  let on = chart_line_svg(&f);
  var ok = string.str_contains(on, ">alpha</text>") && string.str_contains(on, ">beta</text>");
  figure_set_legend(&mut f, false);
  let off = chart_line_svg(&f);
  if string.str_contains(off, ">alpha</text>") { ok = false; }
  return assert(ok, "legend can be disabled");
}

fn t66() -> TestResult {
  var ss = Vec[ChartSeries].new();
  ss.push(series_new("s", fv2(0.0, 10.0), fv2(0.0, 10.0)));
  var f = figure_new(ss, chart_layout(100.0, 100.0, 20.0, 20.0, 20.0, 20.0));
  figure_set_grid(&mut f, false, false);
  let off = chart_line_svg(&f);
  var ok = !string.str_contains(off, "#e6e6e6");
  figure_set_grid(&mut f, true, true);
  let on = chart_line_svg(&f);
  if !string.str_contains(on, "#e6e6e6") { ok = false; }
  return assert(ok, "grid_x/grid_y control gridline emission");
}

fn t67() -> TestResult {
  var ss = Vec[ChartSeries].new();
  ss.push(series_new("s", fv2(0.0, 1.0), fv2(1.0, 2.0)));
  var f = figure_new(ss, chart_layout(100.0, 100.0, 20.0, 20.0, 20.0, 20.0));
  figure_set_title(&mut f, "A & <B>");
  f.background = color_from_hex("#ff0000");
  let doc = chart_line_svg(&f);
  var ok = string.str_contains(doc, ">A &amp; &lt;B&gt;</text>");
  if !string.str_contains(doc, "<rect x=\"0\" y=\"0\" width=\"100\" height=\"100\" fill=\"#ff0000\"/>") { ok = false; }
  return assert(ok, "title is escaped and the background color is emitted");
}

fn t68() -> TestResult {
  var ss = Vec[ChartSeries].new();
  ss.push(series_new("s", fv3(0.0, 5.0, 10.0), fv3(1.0, 4.0, 2.0)));
  var f = figure_new(ss, chart_layout(100.0, 100.0, 20.0, 20.0, 20.0, 20.0));
  var ok = true;
  var k = CHART_LINE;
  while k <= CHART_HISTOGRAM {
    figure_set_kind(&mut f, k);
    let doc = chart_svg(&f);
    if !string.str_contains(doc, "<svg") || !string.str_contains(doc, "</svg>") { ok = false; }
    if k == CHART_BAR && !string.str_contains(doc, "<rect x=") { ok = false; }
    if k == CHART_SCATTER && !string.str_contains(doc, "<circle") { ok = false; }
    if k == CHART_AREA && !string.str_contains(doc, "<polygon") { ok = false; }
    k = k + 1;
  }
  return assert(ok, "chart_svg dispatches every declared kind");
}

fn t69() -> TestResult {
  var ss = Vec[ChartSeries].new();
  ss.push(series_cat("s", lv3("a", "b", "c"), fv3(1.0, 4.0, 2.0)));
  var f = figure_new(ss, chart_layout(120.0, 80.0, 20.0, 10.0, 10.0, 20.0));
  var ok = streq(chart_line_svg(&f), chart_line_svg(&f));
  if !streq(chart_bar_svg(&f), chart_bar_svg(&f)) { ok = false; }
  if !streq(chart_svg(&f), chart_svg(&f)) { ok = false; }
  return assert(ok, "line, bar and dispatch output are byte-stable");
}

fn t70() -> TestResult {
  var ss = Vec[ChartSeries].new();
  ss.push(series_cat("s", lv3("a", "b", "c"), fv3(1.0, 2.0, 3.0)));
  var f = figure_new(ss, chart_layout(120.0, 80.0, 20.0, 10.0, 10.0, 20.0));
  figure_set_kind(&mut f, CHART_PIE);
  var ok = streq(chart_pie_svg(&f), chart_pie_svg(&f));
  figure_set_kind(&mut f, CHART_DOUGHNUT);
  if !streq(chart_doughnut_svg(&f), chart_doughnut_svg(&f)) { ok = false; }
  figure_set_kind(&mut f, CHART_HISTOGRAM);
  if !streq(chart_histogram_svg(&f), chart_histogram_svg(&f)) { ok = false; }
  return assert(ok, "pie, doughnut and histogram output are byte-stable");
}

fn t71() -> TestResult {
  let f = figure_new(Vec[ChartSeries].new(), chart_layout_default());
  var ok = true;
  var k = CHART_LINE;
  while k <= CHART_HISTOGRAM {
    var g = f;
    figure_set_kind(&mut g, k);
    let doc = chart_svg(&g);
    if !string.str_contains(doc, "<svg") || !string.str_contains(doc, "</svg>") { ok = false; }
    if k == CHART_LINE && string.str_contains(doc, "<path") { ok = false; }
    if k == CHART_PIE && string.str_contains(doc, "<path") { ok = false; }
    k = k + 1;
  }
  return assert(ok, "empty figures render every kind without crashing");
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
  let r29 = t29();
  if r29.passed { io.println("  [PASS] " + r29.name); } else { io.println("  [FAIL] " + r29.name); failed = failed + 1; }
  let r30 = t30();
  if r30.passed { io.println("  [PASS] " + r30.name); } else { io.println("  [FAIL] " + r30.name); failed = failed + 1; }
  let r31 = t31();
  if r31.passed { io.println("  [PASS] " + r31.name); } else { io.println("  [FAIL] " + r31.name); failed = failed + 1; }
  let r32 = t32();
  if r32.passed { io.println("  [PASS] " + r32.name); } else { io.println("  [FAIL] " + r32.name); failed = failed + 1; }
  let r33 = t33();
  if r33.passed { io.println("  [PASS] " + r33.name); } else { io.println("  [FAIL] " + r33.name); failed = failed + 1; }
  let r34 = t34();
  if r34.passed { io.println("  [PASS] " + r34.name); } else { io.println("  [FAIL] " + r34.name); failed = failed + 1; }
  let r35 = t35();
  if r35.passed { io.println("  [PASS] " + r35.name); } else { io.println("  [FAIL] " + r35.name); failed = failed + 1; }
  let r36 = t36();
  if r36.passed { io.println("  [PASS] " + r36.name); } else { io.println("  [FAIL] " + r36.name); failed = failed + 1; }
  let r37 = t37();
  if r37.passed { io.println("  [PASS] " + r37.name); } else { io.println("  [FAIL] " + r37.name); failed = failed + 1; }
  let r38 = t38();
  if r38.passed { io.println("  [PASS] " + r38.name); } else { io.println("  [FAIL] " + r38.name); failed = failed + 1; }
  let r39 = t39();
  if r39.passed { io.println("  [PASS] " + r39.name); } else { io.println("  [FAIL] " + r39.name); failed = failed + 1; }
  let r40 = t40();
  if r40.passed { io.println("  [PASS] " + r40.name); } else { io.println("  [FAIL] " + r40.name); failed = failed + 1; }
  let r41 = t41();
  if r41.passed { io.println("  [PASS] " + r41.name); } else { io.println("  [FAIL] " + r41.name); failed = failed + 1; }
  let r42 = t42();
  if r42.passed { io.println("  [PASS] " + r42.name); } else { io.println("  [FAIL] " + r42.name); failed = failed + 1; }
  let r43 = t43();
  if r43.passed { io.println("  [PASS] " + r43.name); } else { io.println("  [FAIL] " + r43.name); failed = failed + 1; }
  let r44 = t44();
  if r44.passed { io.println("  [PASS] " + r44.name); } else { io.println("  [FAIL] " + r44.name); failed = failed + 1; }
  let r45 = t45();
  if r45.passed { io.println("  [PASS] " + r45.name); } else { io.println("  [FAIL] " + r45.name); failed = failed + 1; }
  let r46 = t46();
  if r46.passed { io.println("  [PASS] " + r46.name); } else { io.println("  [FAIL] " + r46.name); failed = failed + 1; }
  let r47 = t47();
  if r47.passed { io.println("  [PASS] " + r47.name); } else { io.println("  [FAIL] " + r47.name); failed = failed + 1; }
  let r48 = t48();
  if r48.passed { io.println("  [PASS] " + r48.name); } else { io.println("  [FAIL] " + r48.name); failed = failed + 1; }
  let r49 = t49();
  if r49.passed { io.println("  [PASS] " + r49.name); } else { io.println("  [FAIL] " + r49.name); failed = failed + 1; }
  let r50 = t50();
  if r50.passed { io.println("  [PASS] " + r50.name); } else { io.println("  [FAIL] " + r50.name); failed = failed + 1; }
  let r51 = t51();
  if r51.passed { io.println("  [PASS] " + r51.name); } else { io.println("  [FAIL] " + r51.name); failed = failed + 1; }
  let r52 = t52();
  if r52.passed { io.println("  [PASS] " + r52.name); } else { io.println("  [FAIL] " + r52.name); failed = failed + 1; }
  let r53 = t53();
  if r53.passed { io.println("  [PASS] " + r53.name); } else { io.println("  [FAIL] " + r53.name); failed = failed + 1; }
  let r54 = t54();
  if r54.passed { io.println("  [PASS] " + r54.name); } else { io.println("  [FAIL] " + r54.name); failed = failed + 1; }
  let r55 = t55();
  if r55.passed { io.println("  [PASS] " + r55.name); } else { io.println("  [FAIL] " + r55.name); failed = failed + 1; }
  let r56 = t56();
  if r56.passed { io.println("  [PASS] " + r56.name); } else { io.println("  [FAIL] " + r56.name); failed = failed + 1; }
  let r57 = t57();
  if r57.passed { io.println("  [PASS] " + r57.name); } else { io.println("  [FAIL] " + r57.name); failed = failed + 1; }
  let r58 = t58();
  if r58.passed { io.println("  [PASS] " + r58.name); } else { io.println("  [FAIL] " + r58.name); failed = failed + 1; }
  let r59 = t59();
  if r59.passed { io.println("  [PASS] " + r59.name); } else { io.println("  [FAIL] " + r59.name); failed = failed + 1; }
  let r60 = t60();
  if r60.passed { io.println("  [PASS] " + r60.name); } else { io.println("  [FAIL] " + r60.name); failed = failed + 1; }
  let r61 = t61();
  if r61.passed { io.println("  [PASS] " + r61.name); } else { io.println("  [FAIL] " + r61.name); failed = failed + 1; }
  let r62 = t62();
  if r62.passed { io.println("  [PASS] " + r62.name); } else { io.println("  [FAIL] " + r62.name); failed = failed + 1; }
  let r63 = t63();
  if r63.passed { io.println("  [PASS] " + r63.name); } else { io.println("  [FAIL] " + r63.name); failed = failed + 1; }
  let r64 = t64();
  if r64.passed { io.println("  [PASS] " + r64.name); } else { io.println("  [FAIL] " + r64.name); failed = failed + 1; }
  let r65 = t65();
  if r65.passed { io.println("  [PASS] " + r65.name); } else { io.println("  [FAIL] " + r65.name); failed = failed + 1; }
  let r66 = t66();
  if r66.passed { io.println("  [PASS] " + r66.name); } else { io.println("  [FAIL] " + r66.name); failed = failed + 1; }
  let r67 = t67();
  if r67.passed { io.println("  [PASS] " + r67.name); } else { io.println("  [FAIL] " + r67.name); failed = failed + 1; }
  let r68 = t68();
  if r68.passed { io.println("  [PASS] " + r68.name); } else { io.println("  [FAIL] " + r68.name); failed = failed + 1; }
  let r69 = t69();
  if r69.passed { io.println("  [PASS] " + r69.name); } else { io.println("  [FAIL] " + r69.name); failed = failed + 1; }
  let r70 = t70();
  if r70.passed { io.println("  [PASS] " + r70.name); } else { io.println("  [FAIL] " + r70.name); failed = failed + 1; }
  let r71 = t71();
  if r71.passed { io.println("  [PASS] " + r71.name); } else { io.println("  [FAIL] " + r71.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.charts: all tests passed");
  } else {
    io.println("xiom.charts: tests failed");
  }
  return failed;
}
