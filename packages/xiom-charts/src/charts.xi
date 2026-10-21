// XIOM -- xiom.charts: deterministic Float64 2D chart model with an SVG emitter
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Design split (P1 of the charts/plots program):
//   * model   -- Float64 series, scales, axes, ticks, colors, annotations
//   * render  -- deterministic SVG 1.1 text, no global state, no FFI, no I/O
//   * xiom.plots (future) consumes the model + element emitters from here
//
// Every coordinate that reaches the document is quantized by _fmt_dec to at
// most three decimals. Non-finite inputs format as "0" so output is always
// valid, byte-stable SVG text. Rounding is half away from zero on the absolute
// value, with "-0" normalized to "0".
//
// Compiler discipline (v0.64.8):
//   * Free functions only; no methods, no inline lambdas.
//   * Str values read from Vec[Str] are bound to a typed local before use
//     (BUG 17 discipline); all Str comparisons live in the tests and go
//     through xiom.string.compare.
//   * Structs are values; setters take `&mut` and mutate the caller's value.
//   * Public names are prefixed (Chart*, chart_*, scale_*, axis_*, ticks_*,
//     series_*, figure_*, color_*, colormap_*, palette_*).

module xiom.charts

use xiom.string;
use xiom.string.builder;
use xiom.convert;
use xiom.format.number;
use xiom.math;
use xiom.num;

// --------------------------------------------------
//  Public constants (kind / marker / annotation tags)
// --------------------------------------------------

pub const CHART_LINE: Int = 0;
pub const CHART_SCATTER: Int = 1;
pub const CHART_BAR: Int = 2;
pub const CHART_BAR_STACKED: Int = 3;
pub const CHART_AREA: Int = 4;
pub const CHART_STEP: Int = 5;
pub const CHART_PIE: Int = 6;
pub const CHART_DOUGHNUT: Int = 7;
pub const CHART_HISTOGRAM: Int = 8;

pub const MARKER_NONE: Int = 0;
pub const MARKER_CIRCLE: Int = 1;
pub const MARKER_SQUARE: Int = 2;
pub const MARKER_DIAMOND: Int = 3;
pub const MARKER_CROSS: Int = 4;
pub const MARKER_TRIANGLE: Int = 5;

pub const ANNOTATION_TEXT: Int = 0;
pub const ANNOTATION_ARROW: Int = 1;
pub const ANNOTATION_HLINE: Int = 2;
pub const ANNOTATION_VLINE: Int = 3;

// --------------------------------------------------
//  Byte constants (all < 128, direct UInt8 comparison)
// --------------------------------------------------

const _CH_AMP: UInt8 = 38u8;
const _CH_LT: UInt8 = 60u8;
const _CH_GT: UInt8 = 62u8;
const _CH_DQUOTE: UInt8 = 34u8;
const _CH_SQUOTE: UInt8 = 39u8;
const _CH_HASH: UInt8 = 35u8;
const _CH_ZERO: UInt8 = 48u8;
const _CH_NINE: UInt8 = 57u8;
const _CH_UPPER_A: UInt8 = 65u8;
const _CH_UPPER_F: UInt8 = 70u8;
const _CH_LOWER_A: UInt8 = 97u8;
const _CH_LOWER_F: UInt8 = 102u8;
const _CH_DOT: UInt8 = 46u8;

// --------------------------------------------------
//  Fixed document style
// --------------------------------------------------

const _AXIS_COLOR: Str = "#000000";
const _GRID_COLOR: Str = "#e6e6e6";
const _LABEL_COLOR: Str = "#333333";
const _LABEL_SIZE: Float64 = 10.0;
const _TITLE_SIZE: Float64 = 16.0;
const _AXIS_LABEL_SIZE: Float64 = 11.0;
const _TICK_GAP: Float64 = 6.0;
const _TEXT_GAP: Float64 = 16.0;
const _MARKER_RADIUS: Float64 = 3.0;
const _PI: Float64 = 3.141592653589793;
const _TWO_PI: Float64 = 6.283185307179586;
const _EPS: Float64 = 0.000000001;

// --------------------------------------------------
//  Model
// --------------------------------------------------

/// An RGB color with an alpha channel, plus an explicit SVG `none` paint.
pub type ChartColor = {
  r: Int;
  g: Int;
  b: Int;
  a: Float64;
  none: Bool;
}

/// One data series.
/// labels are category labels (may be empty); xs are explicit x coordinates
/// (empty means index positions); ys are the values. series_len is the drift
/// guard: it is the shortest of the three vectors that are non-empty. color is
/// used when auto_color is false; otherwise the renderer assigns palette_color
/// by series index. opacity scales the color alpha at render time.
pub type ChartSeries = {
  name: Str;
  labels: Vec[Str];
  xs: Vec[Float64];
  ys: Vec[Float64];
  color: ChartColor;
  auto_color: Bool;
  line_width: Float64;
  marker: Int;
  opacity: Float64;
}

/// Canvas plus four margins (all Float64 user units).
pub type ChartLayout = {
  width: Float64;
  height: Float64;
  left: Float64;
  right: Float64;
  top: Float64;
  bottom: Float64;
}

/// Axis descriptor. auto=true means the renderer derives min/max from data;
/// log=true selects a base-10 log scale.
pub type ChartAxis = {
  min: Float64;
  max: Float64;
  auto: Bool;
  log: Bool;
  label: Str;
  tick_count: Int;
}

/// Linear or logarithmic value <-> pixel mapping.
pub type ChartScale = {
  min: Float64;
  max: Float64;
  p0: Float64;
  p1: Float64;
  log: Bool;
}

/// One annotation in data coordinates.
pub type ChartAnnotation = {
  kind: Int;
  x1: Float64;
  y1: Float64;
  x2: Float64;
  y2: Float64;
  text: Str;
  color: ChartColor;
}

/// A complete static figure. Renderers never mutate it.
pub type ChartFigure = {
  series: Vec[ChartSeries];
  layout: ChartLayout;
  title: Str;
  x_axis: ChartAxis;
  y_axis: ChartAxis;
  grid_x: Bool;
  grid_y: Bool;
  legend: Bool;
  kind: Int;
  bar_width: Float64;
  doughnut_hole: Float64;
  bins: Int;
  annotations: Vec[ChartAnnotation];
  background: ChartColor;
}

// Internal resolved domain.
type _Bounds = {
  xmin: Float64;
  xmax: Float64;
  ymin: Float64;
  ymax: Float64;
}

// --------------------------------------------------
//  Numeric helpers and deterministic formatting
// --------------------------------------------------

fn _clampf(x: Float64, lo: Float64, hi: Float64) -> Float64 {
  var v = x;
  if v < lo {
    v = lo;
  }
  if v > hi {
    v = hi;
  }
  return v;
}

fn _clampi(x: Int, lo: Int, hi: Int) -> Int {
  var v = x;
  if v < lo {
    v = lo;
  }
  if v > hi {
    v = hi;
  }
  return v;
}

fn _absf(x: Float64) -> Float64 {
  if x < 0.0 {
    return 0.0 - x;
  }
  return x;
}

fn _round_pos(x: Float64) -> Int {
  return to_int(x + 0.5);
}

fn _pow10_i(n: Int) -> Int {
  let e = _clampi(n, 0, 18);
  var p = 1;
  var i = 0;
  while i < e {
    p = p * 10;
    i = i + 1;
  }
  return p;
}

// Format x with exactly `decimals` fractional digits, then trim trailing
// zeros. Negative values are rounded half away from zero by rounding the
// absolute value; "-0" is rendered "0". Non-finite values render "0".
fn _fmt_dec(x: Float64, decimals: Int) -> Str {
  if !num.is_finite(x) {
    return "0";
  }
  let d = _clampi(decimals, 0, 9);
  var ax = x;
  var neg = false;
  if ax < 0.0 {
    neg = true;
    ax = 0.0 - ax;
  }
  if ax > 9000000000000000.0 {
    return "0";
  }
  let scale = _pow10_i(d);
  let scaled = ax * (scale as Float64);
  let rounded = _round_pos(scaled);
  let int_part = rounded / scale;
  let frac_part = rounded % scale;
  var body = convert.int_to_string(int_part);
  if d > 0 && frac_part > 0 {
    var fs = convert.int_to_string(frac_part);
    var pad = d - fs.len();
    body = body + ".";
    while pad > 0 {
      body = body + "0";
      pad = pad - 1;
    }
    body = body + fs;
    var end = body.len();
    while end > 0 {
      let b: UInt8 = string.byte_at(body, end - 1);
      if b != _CH_ZERO {
        break;
      }
      end = end - 1;
    }
    if end > 0 {
      let b2: UInt8 = string.byte_at(body, end - 1);
      if b2 == _CH_DOT {
        end = end - 1;
      }
    }
    if end <= 0 {
      body = "0";
    } else {
      body = string.str_slice(body, 0, end);
    }
  }
  if neg && rounded > 0 {
    body = "-" + body;
  }
  return body;
}

fn _fmt_coord(x: Float64) -> Str {
  return _fmt_dec(x, 3);
}

fn _fmt_alpha(x: Float64) -> Str {
  return _fmt_dec(x, 3);
}

fn _attr_num(name: Str, value: Float64) -> Str {
  return " " + name + "=\"" + _fmt_coord(value) + "\"";
}

fn _attr_str(name: Str, value: Str) -> Str {
  return " " + name + "=\"" + chart_escape(value) + "\"";
}

fn _opacity_attr(name: Str, alpha: Float64, emit: Bool) -> Str {
  if !emit {
    return "";
  }
  let a = _clampf(alpha, 0.0, 1.0);
  if a >= 1.0 {
    return "";
  }
  return " " + name + "=\"" + _fmt_alpha(a) + "\"";
}

/// Deterministic fixed-point formatting for chart output.
/// Params: x - value; decimals - 0..6 (outside the range is clamped).
/// Returns: decimal text with trailing fractional zeros removed; "-0" -> "0";
/// non-finite values -> "0". Rounds half away from zero on the absolute value.
/// Error case: none. Complexity: O(decimals + digits).
pub fn chart_format_float(x: Float64, decimals: Int) -> Str {
  return _fmt_dec(x, _clampi(decimals, 0, 6));
}

/// Magnitude-adaptive tick/value formatting.
/// Returns: chart_format_float with 0 decimals at >= 1000, 1 at >= 10,
/// 2 at >= 1, 3 at >= 0.01, and 6 below that (trailing zeros trimmed).
/// Error case: none. Complexity: O(digits).
pub fn chart_format_value(x: Float64) -> Str {
  let a = _absf(x);
  if a >= 1000.0 {
    return _fmt_dec(x, 0);
  }
  if a >= 10.0 {
    return _fmt_dec(x, 1);
  }
  if a >= 1.0 {
    return _fmt_dec(x, 2);
  }
  if a >= 0.01 {
    return _fmt_dec(x, 3);
  }
  return _fmt_dec(x, 6);
}

// --------------------------------------------------
//  XML escaping
// --------------------------------------------------

/// Escape the five XML metacharacters as predefined entities.
/// Params: s - the text to escape.
/// Returns: s with & -> &amp;, < -> &lt;, > -> &gt;, " -> &quot; and
/// ' -> &apos;; every other byte (including multi-byte UTF-8 sequences)
/// passes through unchanged, except 0x00 which is dropped (a XIOM Str cannot
/// round-trip NUL).
/// Error case: none. Complexity: O(s.len()).
pub fn chart_escape(s: Str) -> Str {
  var out = Vec[UInt8].new();
  var i = 0;
  let n = s.len();
  while i < n {
    let b: UInt8 = string.byte_at(s, i);
    if b == _CH_AMP {
      builder.sb_push_str(&mut out, "&amp;");
    } elif b == _CH_LT {
      builder.sb_push_str(&mut out, "&lt;");
    } elif b == _CH_GT {
      builder.sb_push_str(&mut out, "&gt;");
    } elif b == _CH_DQUOTE {
      builder.sb_push_str(&mut out, "&quot;");
    } elif b == _CH_SQUOTE {
      builder.sb_push_str(&mut out, "&apos;");
    } else {
      if b != 0u8 {
        out.push(b);
      }
    }
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}

// --------------------------------------------------
//  Color model and colormaps
// --------------------------------------------------

fn _hex_nibble(b: UInt8) -> Int {
  if b >= _CH_ZERO && b <= _CH_NINE {
    return (b as Int) - 48;
  }
  if b >= _CH_UPPER_A && b <= _CH_UPPER_F {
    return (b as Int) - 55;
  }
  if b >= _CH_LOWER_A && b <= _CH_LOWER_F {
    return (b as Int) - 87;
  }
  return 0 - 1;
}

fn _hex_digit(n: Int) -> Str {
  if n < 10 {
    return convert.int_to_string(n);
  }
  if n == 10 {
    return "a";
  }
  if n == 11 {
    return "b";
  }
  if n == 12 {
    return "c";
  }
  if n == 13 {
    return "d";
  }
  if n == 14 {
    return "e";
  }
  return "f";
}

fn _hex2(v: Int) -> Str {
  let n = _clampi(v, 0, 255);
  return _hex_digit(n / 16) + _hex_digit(n % 16);
}

fn _paint(c: ChartColor) -> Str {
  if c.none {
    return "none";
  }
  return "#" + _hex2(c.r) + _hex2(c.g) + _hex2(c.b);
}

fn _round_channel(x: Float64) -> Int {
  return _clampi(_round_pos(x), 0, 255);
}

/// Opaque RGB color; channels are clamped to 0..255.
/// Complexity: O(1).
pub fn color_rgb(r: Int, g: Int, b: Int) -> ChartColor {
  return ChartColor{ r: _clampi(r, 0, 255); g: _clampi(g, 0, 255); b: _clampi(b, 0, 255); a: 1.0; none: false; };
}

/// RGB color with alpha; channels are clamped to 0..255, alpha to 0..1.
/// Complexity: O(1).
pub fn color_rgba(r: Int, g: Int, b: Int, a: Float64) -> ChartColor {
  return ChartColor{ r: _clampi(r, 0, 255); g: _clampi(g, 0, 255); b: _clampi(b, 0, 255); a: _clampf(a, 0.0, 1.0); none: false; };
}

/// The SVG `none` paint (no fill / no stroke).
/// Complexity: O(1).
pub fn color_none() -> ChartColor {
  return ChartColor{ r: 0; g: 0; b: 0; a: 1.0; none: true; };
}

/// Copy c with a new alpha (clamped to 0..1; `none` is preserved).
/// Complexity: O(1).
pub fn color_with_alpha(c: ChartColor, a: Float64) -> ChartColor {
  return ChartColor{ r: c.r; g: c.g; b: c.b; a: _clampf(a, 0.0, 1.0); none: c.none; };
}

/// Parse "#rrggbb" (case-insensitive) into a color.
/// Returns: black on any malformed input (wrong length, missing '#', or a
/// non-hex digit); no other validation is performed.
/// Complexity: O(1).
pub fn color_from_hex(s: Str) -> ChartColor {
  if s.len() != 7 {
    return color_rgb(0, 0, 0);
  }
  let b0: UInt8 = string.byte_at(s, 0);
  if b0 != _CH_HASH {
    return color_rgb(0, 0, 0);
  }
  var v = 0;
  var i = 1;
  while i < 7 {
    let b: UInt8 = string.byte_at(s, i);
    let nib = _hex_nibble(b);
    if nib < 0 {
      return color_rgb(0, 0, 0);
    }
    v = (v * 16) + nib;
    i = i + 1;
  }
  return color_rgb((v / 65536) % 256, (v / 256) % 256, v % 256);
}

/// Render a color as lowercase "#rrggbb" (alpha is not included).
/// Returns "#000000" for the `none` paint.
/// Complexity: O(1).
pub fn color_to_hex(c: ChartColor) -> Str {
  if c.none {
    return "#000000";
  }
  return "#" + _hex2(c.r) + _hex2(c.g) + _hex2(c.b);
}

/// Linear RGB interpolation; t is clamped to 0..1. If either color is `none`,
/// the result is `none`.
/// Complexity: O(1).
pub fn color_lerp(a: ChartColor, b: ChartColor, t: Float64) -> ChartColor {
  if a.none || b.none {
    return color_none();
  }
  let u = _clampf(t, 0.0, 1.0);
  let ar = a.r as Float64;
  let ag = a.g as Float64;
  let ab = a.b as Float64;
  let br = b.r as Float64;
  let bg = b.g as Float64;
  let bb = b.b as Float64;
  return color_rgba(
    _round_channel(ar + ((br - ar) * u)),
    _round_channel(ag + ((bg - ag) * u)),
    _round_channel(ab + ((bb - ab) * u)),
    a.a + ((b.a - a.a) * u)
  );
}

fn _sample_stops(stops: &Vec[Int], t: Float64) -> ChartColor {
  let n = stops.len() / 3;
  if n <= 0 {
    return color_rgb(0, 0, 0);
  }
  let u = _clampf(t, 0.0, 1.0);
  let pos = u * ((n - 1) as Float64);
  var idx = to_int(pos);
  if idx > n - 2 {
    idx = n - 2;
  }
  if idx < 0 {
    idx = 0;
  }
  let f = pos - (idx as Float64);
  let i0 = idx * 3;
  let i1 = (idx + 1) * 3;
  let r0: Int = stops[i0];
  let g0: Int = stops[i0 + 1];
  let b0: Int = stops[i0 + 2];
  let r1: Int = stops[i1];
  let g1: Int = stops[i1 + 1];
  let b1: Int = stops[i1 + 2];
  return color_rgba(
    _round_channel((r0 as Float64) + (((r1 - r0) as Float64) * f)),
    _round_channel((g0 as Float64) + (((g1 - g0) as Float64) * f)),
    _round_channel((b0 as Float64) + (((b1 - b0) as Float64) * f)),
    1.0
  );
}

fn _palette_stops() -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(76); v.push(120); v.push(168);
  v.push(245); v.push(133); v.push(24);
  v.push(84); v.push(162); v.push(75);
  v.push(228); v.push(87); v.push(86);
  v.push(114); v.push(183); v.push(178);
  v.push(238); v.push(202); v.push(59);
  v.push(178); v.push(121); v.push(162);
  v.push(255); v.push(157); v.push(166);
  v.push(157); v.push(117); v.push(93);
  v.push(186); v.push(176); v.push(172);
  return v;
}

/// One of the ten default series colors (index wraps for negative input).
/// Complexity: O(1).
pub fn palette_color(index: Int) -> ChartColor {
  let stops = _palette_stops();
  let n = stops.len() / 3;
  var i = index % n;
  if i < 0 {
    i = i + n;
  }
  let k = i * 3;
  let r: Int = stops[k];
  let g: Int = stops[k + 1];
  let b: Int = stops[k + 2];
  return color_rgb(r, g, b);
}

fn _viridis_stops() -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(68); v.push(1); v.push(84);
  v.push(72); v.push(40); v.push(120);
  v.push(62); v.push(73); v.push(137);
  v.push(49); v.push(104); v.push(142);
  v.push(38); v.push(130); v.push(142);
  v.push(31); v.push(158); v.push(137);
  v.push(53); v.push(183); v.push(121);
  v.push(110); v.push(206); v.push(88);
  v.push(181); v.push(222); v.push(43);
  v.push(253); v.push(231); v.push(37);
  return v;
}

fn _magma_stops() -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(0); v.push(0); v.push(4);
  v.push(24); v.push(15); v.push(61);
  v.push(68); v.push(15); v.push(118);
  v.push(114); v.push(31); v.push(129);
  v.push(158); v.push(47); v.push(127);
  v.push(205); v.push(64); v.push(113);
  v.push(241); v.push(96); v.push(93);
  v.push(253); v.push(150); v.push(104);
  v.push(254); v.push(202); v.push(141);
  v.push(252); v.push(253); v.push(191);
  return v;
}

/// Sample the viridis colormap at t in 0..1 (clamped).
/// Complexity: O(1).
pub fn colormap_viridis(t: Float64) -> ChartColor {
  let stops = _viridis_stops();
  return _sample_stops(&stops, t);
}

/// Sample the magma colormap at t in 0..1 (clamped).
/// Complexity: O(1).
pub fn colormap_magma(t: Float64) -> ChartColor {
  let stops = _magma_stops();
  return _sample_stops(&stops, t);
}

// --------------------------------------------------
//  Series
// --------------------------------------------------

/// Create a numeric series.
/// Params: name - legend label; xs - explicit x coordinates (may be empty for
/// index positioning); ys - values.
/// Returns: a series with auto_color=true, marker=MARKER_NONE, line_width=2.0,
/// opacity=1.0 and empty category labels.
/// Error case: none. Complexity: O(1).
pub fn series_new(name: Str, xs: Vec[Float64], ys: Vec[Float64]) -> ChartSeries {
  return ChartSeries{
    name: name;
    labels: Vec[Str].new();
    xs: xs;
    ys: ys;
    color: color_rgb(76, 120, 168);
    auto_color: true;
    line_width: 2.0;
    marker: MARKER_NONE;
    opacity: 1.0;
  };
}

/// Create a category series (line/bar/pie).
/// Params: name - legend label; labels - category labels; ys - values.
/// Returns: a series with empty xs (index positioning) and the same defaults
/// as series_new.
/// Error case: none. Complexity: O(1).
pub fn series_cat(name: Str, labels: Vec[Str], ys: Vec[Float64]) -> ChartSeries {
  return ChartSeries{
    name: name;
    labels: labels;
    xs: Vec[Float64].new();
    ys: ys;
    color: color_rgb(76, 120, 168);
    auto_color: true;
    line_width: 2.0;
    marker: MARKER_NONE;
    opacity: 1.0;
  };
}

/// Usable series length: the shortest of ys, non-empty labels and non-empty
/// xs. Empty labels/xs are not constraints.
/// Error case: none. Complexity: O(1).
pub fn series_len(s: &ChartSeries) -> Int {
  var n = s.ys.len();
  let nl = s.labels.len();
  if nl > 0 && nl < n {
    n = nl;
  }
  let nx = s.xs.len();
  if nx > 0 && nx < n {
    n = nx;
  }
  return n;
}

/// Set an explicit color (disables automatic palette assignment).
/// Complexity: O(1).
pub fn series_set_color(s: &mut ChartSeries, c: ChartColor) {
  s.color = c;
  s.auto_color = false;
}

/// Set the marker tag (MARKER_*); out-of-range tags are stored as
/// MARKER_NONE.
/// Complexity: O(1).
pub fn series_set_marker(s: &mut ChartSeries, marker: Int) {
  var m = marker;
  if m < MARKER_NONE || m > MARKER_TRIANGLE {
    m = MARKER_NONE;
  }
  s.marker = m;
}

// --------------------------------------------------
//  Scales
// --------------------------------------------------

/// Build a linear scale. A degenerate domain is widened to [min, min+1];
/// non-finite bounds become [0, 1]. p0/p1 may be reversed.
/// Complexity: O(1).
pub fn scale_linear(min: Float64, max: Float64, p0: Float64, p1: Float64) -> ChartScale {
  var lo = min;
  var hi = max;
  if !num.is_finite(lo) || !num.is_finite(hi) {
    lo = 0.0;
    hi = 1.0;
  }
  if hi <= lo {
    hi = lo + 1.0;
  }
  return ChartScale{ min: lo; max: hi; p0: p0; p1: p1; log: false; };
}

/// Build a base-10 log scale. A non-positive minimum becomes 1; a domain at
/// or below one decade is widened to [min, min*10].
/// Complexity: O(1).
pub fn scale_log(min: Float64, max: Float64, p0: Float64, p1: Float64) -> ChartScale {
  var lo = min;
  if !num.is_finite(lo) || lo <= 0.0 {
    lo = 1.0;
  }
  var hi = max;
  if !num.is_finite(hi) {
    hi = lo * 10.0;
  }
  if hi <= lo {
    hi = lo * 10.0;
  }
  return ChartScale{ min: lo; max: hi; p0: p0; p1: p1; log: true; };
}

fn _scale_t(s: &ChartScale, v: Float64) -> Float64 {
  if s.log {
    let vv = if v <= 0.0 { s.min } else { v };
    let lmin = math.log10(s.min);
    let lmax = math.log10(s.max);
    let lv = math.log10(vv);
    return (lv - lmin) / (lmax - lmin);
  }
  return (v - s.min) / (s.max - s.min);
}

/// Map a value to a pixel position, clamping to the domain ends.
/// Log scales map non-positive values to the domain minimum.
/// Complexity: O(1).
pub fn scale_map(s: &ChartScale, v: Float64) -> Float64 {
  var t = _scale_t(s, v);
  if !num.is_finite(t) {
    t = 0.0;
  }
  t = _clampf(t, 0.0, 1.0);
  return s.p0 + (t * (s.p1 - s.p0));
}

/// Map a value without clamping (linear scales); log scales still floor
/// non-positive values at the domain minimum.
/// Complexity: O(1).
pub fn scale_map_unclamped(s: &ChartScale, v: Float64) -> Float64 {
  var t = _scale_t(s, v);
  if !num.is_finite(t) {
    t = 0.0;
  }
  return s.p0 + (t * (s.p1 - s.p0));
}

/// Invert a pixel position back to a data value.
/// A zero-width pixel span returns the domain minimum.
/// Complexity: O(1).
pub fn scale_invert(s: &ChartScale, px: Float64) -> Float64 {
  let denom = s.p1 - s.p0;
  if denom == 0.0 {
    return s.min;
  }
  let t = (px - s.p0) / denom;
  if s.log {
    let lmin = math.log10(s.min);
    let lmax = math.log10(s.max);
    return math.pow(10.0, lmin + (t * (lmax - lmin)));
  }
  return s.min + (t * (s.max - s.min));
}

/// Scale domain minimum. Complexity: O(1).
pub fn scale_min(s: &ChartScale) -> Float64 {
  return s.min;
}

/// Scale domain maximum. Complexity: O(1).
pub fn scale_max(s: &ChartScale) -> Float64 {
  return s.max;
}

/// Arithmetic domain width (max - min). Complexity: O(1).
pub fn scale_span(s: &ChartScale) -> Float64 {
  return s.max - s.min;
}

// --------------------------------------------------
//  Axes and tick locators
// --------------------------------------------------

/// Auto-scaled axis. The renderer derives the domain from data.
/// Complexity: O(1).
pub fn axis_auto(label: Str, tick_count: Int) -> ChartAxis {
  return ChartAxis{ min: 0.0; max: 1.0; auto: true; log: false; label: label; tick_count: _clampi(tick_count, 2, 100); };
}

/// Explicit linear axis; a degenerate domain is widened to [min, min+1].
/// Complexity: O(1).
pub fn axis_linear(min: Float64, max: Float64, label: Str, tick_count: Int) -> ChartAxis {
  let sc = scale_linear(min, max, 0.0, 1.0);
  return ChartAxis{ min: sc.min; max: sc.max; auto: false; log: false; label: label; tick_count: _clampi(tick_count, 2, 100); };
}

/// Explicit base-10 log axis; non-positive bounds are normalized like
/// scale_log.
/// Complexity: O(1).
pub fn axis_log(min: Float64, max: Float64, label: Str, tick_count: Int) -> ChartAxis {
  let sc = scale_log(min, max, 0.0, 1.0);
  return ChartAxis{ min: sc.min; max: sc.max; auto: false; log: true; label: label; tick_count: _clampi(tick_count, 2, 100); };
}

/// Ticks for an explicit axis. Auto axes return ticks over their stored
/// [0,1] domain; renderers resolve auto domains before calling.
/// Complexity: O(tick_count).
pub fn axis_ticks(a: &ChartAxis) -> Vec[Float64] {
  if a.log {
    return ticks_log(a.min, a.max);
  }
  return ticks_nice(a.min, a.max, a.tick_count);
}

/// Build the scale for an axis over pixel span p0..p1.
/// Complexity: O(1).
pub fn axis_scale(a: &ChartAxis, p0: Float64, p1: Float64) -> ChartScale {
  if a.log {
    return scale_log(a.min, a.max, p0, p1);
  }
  return scale_linear(a.min, a.max, p0, p1);
}

/// "Nice" ascending tick locator for a linear domain.
/// Chooses a 1/2/2.5/5/10 step at the magnitude of span/(count-1), then
/// emits grid multiples inside [min, max]. Tick count is advisory: the result
/// may be shorter (never empty) and its ends may be inside the domain.
/// Complexity: O(count).
pub fn ticks_nice(min: Float64, max: Float64, count: Int) -> Vec[Float64] {
  var lo = min;
  var hi = max;
  if !num.is_finite(lo) || !num.is_finite(hi) {
    lo = 0.0;
    hi = 1.0;
  }
  if hi <= lo {
    hi = lo + 1.0;
  }
  let c = _clampi(count, 2, 1000);
  let span = hi - lo;
  let raw = span / ((c - 1) as Float64);
  let exp = num.floor(math.log10(raw));
  let base = math.pow(10.0, exp as Float64);
  let f = raw / base;
  var step = base;
  if f <= 1.0 {
    step = base;
  } elif f <= 2.0 {
    step = base * 2.0;
  } elif f <= 2.5 {
    step = base * 2.5;
  } elif f <= 5.0 {
    step = base * 5.0;
  } else {
    step = base * 10.0;
  }
  var out = Vec[Float64].new();
  let first = num.ceil(lo / step);
  var k = first;
  let eps = step * _EPS;
  var guard = 0;
  while guard < 10000 {
    let v = (k as Float64) * step;
    if v > hi + eps {
      break;
    }
    if v >= lo - eps {
      out.push(v);
    }
    k = k + 1;
    guard = guard + 1;
  }
  if out.len() == 0 {
    out.push(lo);
    if hi > lo {
      out.push(hi);
    }
  } elif out.len() == 1 {
    let only: Float64 = out[0];
    if hi > only {
      out.push(hi);
    }
  }
  return out;
}

/// Power-of-ten ticks inside a positive domain. If the domain spans less than
/// one decade, the two endpoints are returned instead.
/// Complexity: O(decades).
pub fn ticks_log(min: Float64, max: Float64) -> Vec[Float64] {
  var lo = min;
  var hi = max;
  if !num.is_finite(lo) || lo <= 0.0 {
    lo = 1.0;
  }
  if !num.is_finite(hi) || hi <= lo {
    hi = lo * 10.0;
  }
  let e0 = num.ceil(math.log10(lo) - _EPS);
  let e1 = num.floor(math.log10(hi) + _EPS);
  var out = Vec[Float64].new();
  if e1 < e0 {
    out.push(lo);
    out.push(hi);
    return out;
  }
  var e = e0;
  while e <= e1 {
    out.push(math.pow(10.0, e as Float64));
    e = e + 1;
  }
  return out;
}

/// Category positions 0..n-1 as Float64 ticks. n < 0 is treated as 0.
/// Complexity: O(n).
pub fn ticks_category(n: Int) -> Vec[Float64] {
  var out = Vec[Float64].new();
  var i = 0;
  while i < n {
    out.push(i as Float64);
    i = i + 1;
  }
  return out;
}

// --------------------------------------------------
//  Layout
// --------------------------------------------------

fn _finite_size(x: Float64) -> Float64 {
  if !num.is_finite(x) || x <= 0.0 {
    return 1.0;
  }
  return x;
}

/// Build a layout with explicit margins. Width/height are clamped to >= 1 and
/// margins to >= 0; the plot rectangle is guaranteed to be at least 1 x 1 by
/// clamping left/top first, then right/bottom.
/// Complexity: O(1).
pub fn chart_layout(width: Float64, height: Float64, left: Float64, right: Float64, top: Float64, bottom: Float64) -> ChartLayout {
  let w = _finite_size(width);
  let h = _finite_size(height);
  var l = _clampf(left, 0.0, w - 1.0);
  var t = _clampf(top, 0.0, h - 1.0);
  var r = _clampf(right, 0.0, w - 1.0 - l);
  var b = _clampf(bottom, 0.0, h - 1.0 - t);
  if !num.is_finite(l) {
    l = 0.0;
  }
  if !num.is_finite(t) {
    t = 0.0;
  }
  if !num.is_finite(r) {
    r = 0.0;
  }
  if !num.is_finite(b) {
    b = 0.0;
  }
  return ChartLayout{ width: w; height: h; left: l; right: r; top: t; bottom: b; };
}

/// Uniform-margin layout; the same pad is used on all four sides.
/// Complexity: O(1).
pub fn chart_layout_uniform(width: Float64, height: Float64, pad: Float64) -> ChartLayout {
  return chart_layout(width, height, pad, pad, pad, pad);
}

/// Default 640 x 360 layout with left=56, right=20, top=36, bottom=44.
/// Complexity: O(1).
pub fn chart_layout_default() -> ChartLayout {
  return chart_layout(640.0, 360.0, 56.0, 20.0, 36.0, 44.0);
}

/// Plot rectangle left edge. Complexity: O(1).
pub fn chart_plot_x0(l: &ChartLayout) -> Float64 {
  return l.left;
}

/// Plot rectangle top edge. Complexity: O(1).
pub fn chart_plot_y0(l: &ChartLayout) -> Float64 {
  return l.top;
}

/// Plot rectangle width (>= 1). Complexity: O(1).
pub fn chart_plot_w(l: &ChartLayout) -> Float64 {
  return l.width - l.left - l.right;
}

/// Plot rectangle height (>= 1). Complexity: O(1).
pub fn chart_plot_h(l: &ChartLayout) -> Float64 {
  return l.height - l.top - l.bottom;
}

/// Plot rectangle right edge. Complexity: O(1).
pub fn chart_plot_x1(l: &ChartLayout) -> Float64 {
  return l.width - l.right;
}

/// Plot rectangle bottom edge. Complexity: O(1).
pub fn chart_plot_y1(l: &ChartLayout) -> Float64 {
  return l.height - l.bottom;
}

// --------------------------------------------------
//  SVG element emitters (attribute order is fixed)
// --------------------------------------------------

/// `<rect>` element. Opacity comes from fill.a and is emitted as
/// fill-opacity when below 1.
/// Complexity: O(digits).
pub fn chart_rect_element(x: Float64, y: Float64, w: Float64, h: Float64, fill: ChartColor) -> Str {
  var s = "<rect" + _attr_num("x", x) + _attr_num("y", y);
  s = s + _attr_num("width", w) + _attr_num("height", h);
  s = s + " fill=\"" + _paint(fill) + "\"";
  s = s + _opacity_attr("fill-opacity", fill.a, !fill.none);
  return s + "/>";
}

/// `<circle>` element. Negative radius is emitted as 0.
/// Complexity: O(digits).
pub fn chart_circle_element(cx: Float64, cy: Float64, r: Float64, fill: ChartColor) -> Str {
  var s = "<circle" + _attr_num("cx", cx) + _attr_num("cy", cy);
  s = s + _attr_num("r", _clampf(r, 0.0, 1000000000.0));
  s = s + " fill=\"" + _paint(fill) + "\"";
  s = s + _opacity_attr("fill-opacity", fill.a, !fill.none);
  return s + "/>";
}

/// `<line>` element. Opacity comes from stroke.a.
/// Complexity: O(digits).
pub fn chart_line_element(x1: Float64, y1: Float64, x2: Float64, y2: Float64, stroke: ChartColor, width: Float64) -> Str {
  var s = "<line" + _attr_num("x1", x1) + _attr_num("y1", y1);
  s = s + _attr_num("x2", x2) + _attr_num("y2", y2);
  s = s + " stroke=\"" + _paint(stroke) + "\"";
  s = s + _attr_num("stroke-width", width);
  s = s + _opacity_attr("stroke-opacity", stroke.a, !stroke.none);
  return s + "/>";
}

/// `<path>` element; d is escaped, fill and stroke are always emitted (use
/// color_none for `none`). Stroke width accompanies the stroke.
/// Complexity: O(digits + d bytes).
pub fn chart_path_element(d: Str, fill: ChartColor, stroke: ChartColor, width: Float64) -> Str {
  var s = "<path" + _attr_str("d", d);
  s = s + " fill=\"" + _paint(fill) + "\"";
  s = s + _opacity_attr("fill-opacity", fill.a, !fill.none);
  s = s + " stroke=\"" + _paint(stroke) + "\"";
  s = s + _attr_num("stroke-width", width);
  s = s + _opacity_attr("stroke-opacity", stroke.a, !stroke.none);
  return s + "/>";
}

/// `<text>` element in character data form; text is escaped.
/// Complexity: O(digits + text bytes).
pub fn chart_text_element(x: Float64, y: Float64, text: Str, size: Float64, fill: ChartColor) -> Str {
  var s = "<text" + _attr_num("x", x) + _attr_num("y", y);
  s = s + _attr_num("font-size", size);
  s = s + " fill=\"" + _paint(fill) + "\"";
  s = s + _opacity_attr("fill-opacity", fill.a, !fill.none);
  return s + ">" + chart_escape(text) + "</text>";
}

/// `<text>` with an explicit text-anchor. The anchor string is escaped and
/// emitted only when non-empty.
/// Complexity: O(digits + text bytes).
pub fn chart_text_anchor_element(x: Float64, y: Float64, text: Str, size: Float64, fill: ChartColor, anchor: Str) -> Str {
  var s = "<text" + _attr_num("x", x) + _attr_num("y", y);
  s = s + _attr_num("font-size", size);
  s = s + " fill=\"" + _paint(fill) + "\"";
  s = s + _opacity_attr("fill-opacity", fill.a, !fill.none);
  if anchor.len() > 0 {
    s = s + _attr_str("text-anchor", anchor);
  }
  return s + ">" + chart_escape(text) + "</text>";
}

fn _points_attr(points: &Vec[Float64]) -> Str {
  if points.len() < 2 {
    return "";
  }
  let x0: Float64 = points[0];
  let y0: Float64 = points[1];
  var d = _fmt_coord(x0) + "," + _fmt_coord(y0);
  var i = 2;
  while i + 1 < points.len() {
    let x: Float64 = points[i];
    let y: Float64 = points[i + 1];
    d = d + " " + _fmt_coord(x) + "," + _fmt_coord(y);
    i = i + 2;
  }
  return d;
}

/// `<polygon>` from a flat [x0,y0,x1,y1,...] vector. Fewer than two pairs
/// produce points="". Opacity comes from fill.a.
/// Complexity: O(points).
pub fn chart_polygon_element(points: Vec[Float64], fill: ChartColor) -> Str {
  let pts = _points_attr(&points);
  var s = "<polygon" + _attr_str("points", pts);
  s = s + " fill=\"" + _paint(fill) + "\"";
  s = s + _opacity_attr("fill-opacity", fill.a, !fill.none);
  return s + "/>";
}

/// `<polyline>` from a flat [x0,y0,x1,y1,...] vector. Fewer than two pairs
/// produce points="". Opacity comes from stroke.a.
/// Complexity: O(points).
pub fn chart_polyline_element(points: Vec[Float64], stroke: ChartColor, width: Float64) -> Str {
  let pts = _points_attr(&points);
  var s = "<polyline" + _attr_str("points", pts);
  s = s + " stroke=\"" + _paint(stroke) + "\"";
  s = s + _attr_num("stroke-width", width);
  s = s + _opacity_attr("stroke-opacity", stroke.a, !stroke.none);
  return s + "/>";
}

/// SVG 1.1 document header with a viewBox matching the canvas.
/// Complexity: O(digits).
pub fn chart_svg_open(width: Float64, height: Float64) -> Str {
  let w = _fmt_coord(width);
  let h = _fmt_coord(height);
  return "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"" + w + "\" height=\"" + h + "\" viewBox=\"0 0 " + w + " " + h + "\">";
}

/// Closing tag for chart_svg_open.
/// Complexity: O(1).
pub fn chart_svg_close() -> Str {
  return "</svg>";
}

// --------------------------------------------------
//  Annotations
// --------------------------------------------------

/// Text annotation at a data point.
/// Complexity: O(1).
pub fn annotation_text(x: Float64, y: Float64, text: Str, c: ChartColor) -> ChartAnnotation {
  return ChartAnnotation{ kind: ANNOTATION_TEXT; x1: x; y1: y; x2: x; y2: y; text: text; color: c; };
}

/// Arrow annotation from (x1,y1) to (x2,y2) with a triangular head.
/// Complexity: O(1).
pub fn annotation_arrow(x1: Float64, y1: Float64, x2: Float64, y2: Float64, c: ChartColor) -> ChartAnnotation {
  return ChartAnnotation{ kind: ANNOTATION_ARROW; x1: x1; y1: y1; x2: x2; y2: y2; text: ""; color: c; };
}

/// Horizontal reference line at y.
/// Complexity: O(1).
pub fn annotation_hline(y: Float64, c: ChartColor) -> ChartAnnotation {
  return ChartAnnotation{ kind: ANNOTATION_HLINE; x1: 0.0; y1: y; x2: 0.0; y2: y; text: ""; color: c; };
}

/// Vertical reference line at x.
/// Complexity: O(1).
pub fn annotation_vline(x: Float64, c: ChartColor) -> ChartAnnotation {
  return ChartAnnotation{ kind: ANNOTATION_VLINE; x1: x; y1: 0.0; x2: x; y2: 0.0; text: ""; color: c; };
}

// --------------------------------------------------
//  Figure
// --------------------------------------------------

/// Create a figure with defaults: auto axes, y-grid on, legend on,
/// CHART_LINE, bar_width=0.8, doughnut_hole=0.5, bins=10, white background.
/// Complexity: O(1).
pub fn figure_new(series: Vec[ChartSeries], layout: ChartLayout) -> ChartFigure {
  return ChartFigure{
    series: series;
    layout: layout;
    title: "";
    x_axis: axis_auto("", 6);
    y_axis: axis_auto("", 5);
    grid_x: false;
    grid_y: true;
    legend: true;
    kind: CHART_LINE;
    bar_width: 0.8;
    doughnut_hole: 0.5;
    bins: 10;
    annotations: Vec[ChartAnnotation].new();
    background: color_rgb(255, 255, 255);
  };
}

/// Set the figure title. Complexity: O(1).
pub fn figure_set_title(f: &mut ChartFigure, title: Str) {
  f.title = title;
}

/// Replace both axes. Complexity: O(1).
pub fn figure_set_axes(f: &mut ChartFigure, x_axis: ChartAxis, y_axis: ChartAxis) {
  f.x_axis = x_axis;
  f.y_axis = y_axis;
}

/// Set the chart kind (clamped to CHART_LINE..CHART_HISTOGRAM).
/// Complexity: O(1).
pub fn figure_set_kind(f: &mut ChartFigure, kind: Int) {
  f.kind = _clampi(kind, CHART_LINE, CHART_HISTOGRAM);
}

/// Enable or disable both grid directions. Complexity: O(1).
pub fn figure_set_grid(f: &mut ChartFigure, grid_x: Bool, grid_y: Bool) {
  f.grid_x = grid_x;
  f.grid_y = grid_y;
}

/// Enable or disable the legend. Complexity: O(1).
pub fn figure_set_legend(f: &mut ChartFigure, on: Bool) {
  f.legend = on;
}

/// Append an annotation. Complexity: O(1).
pub fn figure_add_annotation(f: &mut ChartFigure, a: ChartAnnotation) {
  f.annotations.push(a);
}

// --------------------------------------------------
//  Internal geometry
// --------------------------------------------------

fn _series_x(s: &ChartSeries, i: Int) -> Float64 {
  if s.xs.len() > 0 {
    let x: Float64 = s.xs[i];
    return x;
  }
  return i as Float64;
}

fn _max_series_len(f: &ChartFigure) -> Int {
  var n = 0;
  var i = 0;
  while i < f.series.len() {
    let s: ChartSeries = f.series[i];
    let k = series_len(&s);
    if k > n {
      n = k;
    }
    i = i + 1;
  }
  return n;
}

fn _is_category(f: &ChartFigure) -> Bool {
  if f.kind == CHART_HISTOGRAM {
    return false;
  }
  if f.kind == CHART_BAR || f.kind == CHART_BAR_STACKED || f.kind == CHART_PIE || f.kind == CHART_DOUGHNUT {
    return true;
  }
  if f.series.len() == 0 {
    return false;
  }
  let s: ChartSeries = f.series[0];
  if s.xs.len() == 0 && s.labels.len() > 0 {
    return true;
  }
  return false;
}

fn _scan_y_min(f: &ChartFigure) -> Float64 {
  var m = 0.0;
  var seen = false;
  var i = 0;
  while i < f.series.len() {
    let s: ChartSeries = f.series[i];
    let n = series_len(&s);
    var j = 0;
    while j < n {
      let v: Float64 = s.ys[j];
      if num.is_finite(v) {
        if !seen || v < m {
          m = v;
        }
        seen = true;
      }
      j = j + 1;
    }
    i = i + 1;
  }
  return m;
}

fn _scan_y_max(f: &ChartFigure) -> Float64 {
  var m = 0.0;
  var seen = false;
  var i = 0;
  while i < f.series.len() {
    let s: ChartSeries = f.series[i];
    let n = series_len(&s);
    var j = 0;
    while j < n {
      let v: Float64 = s.ys[j];
      if num.is_finite(v) {
        if !seen || v > m {
          m = v;
        }
        seen = true;
      }
      j = j + 1;
    }
    i = i + 1;
  }
  return m;
}

fn _scan_x_min(f: &ChartFigure) -> Float64 {
  var m = 0.0;
  var seen = false;
  var i = 0;
  while i < f.series.len() {
    let s: ChartSeries = f.series[i];
    let n = series_len(&s);
    var j = 0;
    while j < n {
      let v = _series_x(&s, j);
      if num.is_finite(v) {
        if !seen || v < m {
          m = v;
        }
        seen = true;
      }
      j = j + 1;
    }
    i = i + 1;
  }
  return m;
}

fn _scan_x_max(f: &ChartFigure) -> Float64 {
  var m = 0.0;
  var seen = false;
  var i = 0;
  while i < f.series.len() {
    let s: ChartSeries = f.series[i];
    let n = series_len(&s);
    var j = 0;
    while j < n {
      let v = _series_x(&s, j);
      if num.is_finite(v) {
        if !seen || v > m {
          m = v;
        }
        seen = true;
      }
      j = j + 1;
    }
    i = i + 1;
  }
  return m;
}

fn _stack_bounds(f: &ChartFigure) -> Vec[Float64] {
  let ncat = _max_series_len(f);
  var lo = 0.0;
  var hi = 0.0;
  var seen = false;
  var i = 0;
  while i < ncat {
    var pos = 0.0;
    var neg = 0.0;
    var si = 0;
    while si < f.series.len() {
      let s: ChartSeries = f.series[si];
      if i < series_len(&s) {
        let v: Float64 = s.ys[i];
        if v >= 0.0 {
          pos = pos + v;
        } else {
          neg = neg + v;
        }
      }
      si = si + 1;
    }
    if !seen || neg < lo {
      lo = neg;
    }
    if !seen || pos > hi {
      hi = pos;
    }
    seen = true;
    i = i + 1;
  }
  var out = Vec[Float64].new();
  out.push(lo);
  out.push(hi);
  return out;
}

fn _pad_domain(lo: Float64, hi: Float64, include_zero: Bool) -> Vec[Float64] {
  var a = lo;
  var b = hi;
  if !num.is_finite(a) || !num.is_finite(b) {
    a = 0.0;
    b = 1.0;
  }
  if include_zero {
    if a >= 0.0 {
      a = 0.0;
      if b <= 0.0 {
        b = 1.0;
      } else {
        b = b + (b * 0.05);
      }
    } elif b <= 0.0 {
      b = 0.0;
      a = a + (a * 0.05);
    } else {
      let pad = (b - a) * 0.05;
      a = a - pad;
      b = b + pad;
    }
  } else {
    if b <= a {
      if a == 0.0 {
        b = 1.0;
      } else {
        let d = _absf(a) * 0.1;
        a = a - d;
        b = b + d;
      }
    }
    let span = b - a;
    let pad = span * 0.05;
    a = a - pad;
    b = b + pad;
  }
  var out = Vec[Float64].new();
  out.push(a);
  out.push(b);
  return out;
}

fn _bounds(f: &ChartFigure) -> _Bounds {
  let cat = _is_category(f);
  var xmin = 0.0;
  var xmax = 1.0;
  var ymin = 0.0;
  var ymax = 1.0;

  if cat {
    let n = _max_series_len(f);
    if n > 0 {
      xmin = 0.0 - 0.5;
      xmax = (n as Float64) - 0.5;
    } else {
      xmin = 0.0 - 0.5;
      xmax = 0.5;
    }
  } elif f.x_axis.auto {
    if f.kind == CHART_HISTOGRAM {
      let d = _pad_domain(_scan_y_min(f), _scan_y_max(f), false);
      let a: Float64 = d[0];
      let b: Float64 = d[1];
      xmin = a;
      xmax = b;
    } else {
      let n = _max_series_len(f);
      if n <= 1 {
        xmin = 0.0 - 0.5;
        xmax = 0.5;
      } else {
        let d = _pad_domain(_scan_x_min(f), _scan_x_max(f), false);
        let a: Float64 = d[0];
        let b: Float64 = d[1];
        xmin = a;
        xmax = b;
      }
    }
  } else {
    xmin = f.x_axis.min;
    xmax = f.x_axis.max;
  }

  if f.y_axis.auto {
    if f.kind == CHART_BAR_STACKED {
      let sb = _stack_bounds(f);
      let slo: Float64 = sb[0];
      let shi: Float64 = sb[1];
      let d = _pad_domain(slo, shi, true);
      let a: Float64 = d[0];
      let b: Float64 = d[1];
      ymin = a;
      ymax = b;
    } else {
      let inc0 = f.kind == CHART_BAR || f.kind == CHART_AREA || f.kind == CHART_HISTOGRAM;
      let d = _pad_domain(_scan_y_min(f), _scan_y_max(f), inc0);
      let a: Float64 = d[0];
      let b: Float64 = d[1];
      ymin = a;
      ymax = b;
    }
  } else {
    ymin = f.y_axis.min;
    ymax = f.y_axis.max;
  }

  if f.x_axis.log {
    if xmin <= 0.0 {
      xmin = 1.0;
    }
    if xmax <= xmin {
      xmax = xmin * 10.0;
    }
  } else if xmax <= xmin {
    xmax = xmin + 1.0;
  }
  if f.y_axis.log {
    if ymin <= 0.0 {
      ymin = 1.0;
    }
    if ymax <= ymin {
      ymax = ymin * 10.0;
    }
  } else if ymax <= ymin {
    ymax = ymin + 1.0;
  }

  return _Bounds{ xmin: xmin; xmax: xmax; ymin: ymin; ymax: ymax; };
}

fn _x_scale(f: &ChartFigure, b: &_Bounds, p0: Float64, p1: Float64) -> ChartScale {
  if f.x_axis.log && !_is_category(f) {
    return scale_log(b.xmin, b.xmax, p0, p1);
  }
  return scale_linear(b.xmin, b.xmax, p0, p1);
}

fn _y_scale(f: &ChartFigure, b: &_Bounds, p0: Float64, p1: Float64) -> ChartScale {
  if f.y_axis.log {
    return scale_log(b.ymin, b.ymax, p0, p1);
  }
  return scale_linear(b.ymin, b.ymax, p0, p1);
}

fn _series_color(f: &ChartFigure, index: Int, s: &ChartSeries) -> ChartColor {
  var c = s.color;
  if s.auto_color {
    c = palette_color(index);
  }
  let op = _clampf(s.opacity, 0.0, 1.0);
  return color_with_alpha(c, c.a * op);
}

fn _x_tick_values(f: &ChartFigure, b: &_Bounds) -> Vec[Float64] {
  if _is_category(f) {
    let n = _max_series_len(f);
    return ticks_category(n);
  }
  if f.x_axis.log {
    return ticks_log(b.xmin, b.xmax);
  }
  return ticks_nice(b.xmin, b.xmax, f.x_axis.tick_count);
}

fn _y_tick_values(f: &ChartFigure, b: &_Bounds) -> Vec[Float64] {
  if f.y_axis.log {
    return ticks_log(b.ymin, b.ymax);
  }
  if f.kind == CHART_HISTOGRAM && f.y_axis.auto {
    var top = to_int(num.ceil(b.ymax));
    if top < 1 {
      top = 1;
    }
    var step = 1;
    if top > 5 {
      step = (top + 4) / 5;
    }
    var out = Vec[Float64].new();
    var v = 0;
    while v <= top {
      out.push(v as Float64);
      v = v + step;
    }
    return out;
  }
  return ticks_nice(b.ymin, b.ymax, f.y_axis.tick_count);
}

fn _category_label(s: &ChartSeries, i: Int) -> Str {
  if i < s.labels.len() {
    let lab: Str = s.labels[i];
    return lab;
  }
  return convert.int_to_string(i + 1);
}

fn _render_legend(f: &ChartFigure) -> Str {
  if !f.legend {
    return "";
  }
  let x0 = chart_plot_x0(&f.layout);
  let y0 = chart_plot_y0(&f.layout);
  let x1 = chart_plot_x1(&f.layout);
  let pie = f.kind == CHART_PIE || f.kind == CHART_DOUGHNUT;
  var rows = 0;
  var maxlen = 0;
  if pie {
    if f.series.len() > 0 {
      let s: ChartSeries = f.series[0];
      rows = series_len(&s);
      var i = 0;
      while i < rows {
        let lab = _category_label(&s, i);
        if lab.len() > maxlen {
          maxlen = lab.len();
        }
        i = i + 1;
      }
    }
  } else {
    rows = f.series.len();
    var i = 0;
    while i < rows {
      let s: ChartSeries = f.series[i];
      let n = s.name.len();
      if n > maxlen {
        maxlen = n;
      }
      i = i + 1;
    }
  }
  if rows == 0 {
    return "";
  }
  let want = ((maxlen as Float64) * 6.0) + 34.0;
  var lx = x1 - want;
  if lx < x0 + 4.0 {
    lx = x0 + 4.0;
  }
  let ly = y0 + 6.0;
  var out = "";
  var i = 0;
  while i < rows {
    var c = palette_color(i);
    var label = "";
    if pie {
      let s: ChartSeries = f.series[0];
      label = _category_label(&s, i);
    } else {
      let s: ChartSeries = f.series[i];
      c = _series_color(f, i, &s);
      label = s.name;
      if label.len() == 0 {
        label = "series " + convert.int_to_string(i + 1);
      }
    }
    let y = ly + ((i as Float64) * 14.0);
    out = out + "\n  " + chart_rect_element(lx, y, 10.0, 10.0, c);
    out = out + "\n  " + chart_text_element(lx + 14.0, y + 9.0, label, _LABEL_SIZE, color_from_hex(_LABEL_COLOR));
    i = i + 1;
  }
  return out;
}

fn _render_annotations(f: &ChartFigure, b: &_Bounds) -> Str {
  if f.annotations.len() == 0 {
    return "";
  }
  let px0 = chart_plot_x0(&f.layout);
  let py0 = chart_plot_y0(&f.layout);
  let px1 = chart_plot_x1(&f.layout);
  let py1 = chart_plot_y1(&f.layout);
  let xs = _x_scale(f, b, px0, px1);
  let ys = _y_scale(f, b, py1, py0);
  var out = "";
  var i = 0;
  while i < f.annotations.len() {
    let a: ChartAnnotation = f.annotations[i];
    if a.kind == ANNOTATION_TEXT {
      let x = scale_map(&xs, a.x1);
      let y = scale_map(&ys, a.y1);
      out = out + "\n  " + chart_text_element(x + 4.0, y - 4.0, a.text, _LABEL_SIZE, a.color);
    } elif a.kind == ANNOTATION_ARROW {
      let x1 = scale_map(&xs, a.x1);
      let y1 = scale_map(&ys, a.y1);
      let x2 = scale_map(&xs, a.x2);
      let y2 = scale_map(&ys, a.y2);
      out = out + "\n  " + chart_line_element(x1, y1, x2, y2, a.color, 1.0);
      let ang = math.atan2(y2 - y1, x2 - x1);
      let bx = x2 - (8.0 * math.cos(ang));
      let by = y2 - (8.0 * math.sin(ang));
      let ox = 3.0 * math.sin(ang);
      let oy = 0.0 - (3.0 * math.cos(ang));
      var pts = Vec[Float64].new();
      pts.push(x2); pts.push(y2);
      pts.push(bx + ox); pts.push(by + oy);
      pts.push(bx - ox); pts.push(by - oy);
      out = out + "\n  " + chart_polygon_element(pts, a.color);
    } elif a.kind == ANNOTATION_HLINE {
      let y = scale_map(&ys, a.y1);
      out = out + "\n  " + chart_line_element(px0, y, px1, y, a.color, 1.0);
    } elif a.kind == ANNOTATION_VLINE {
      let x = scale_map(&xs, a.x1);
      out = out + "\n  " + chart_line_element(x, py0, x, py1, a.color, 1.0);
    }
    i = i + 1;
  }
  return out;
}

fn _render_y_axis_text(f: &ChartFigure, b: &_Bounds) -> Str {
  let px0 = chart_plot_x0(&f.layout);
  let py1 = chart_plot_y1(&f.layout);
  let py0 = chart_plot_y0(&f.layout);
  let ys = _y_scale(f, b, py1, py0);
  let ticks = _y_tick_values(f, b);
  var out = "";
  var i = 0;
  while i < ticks.len() {
    let tv: Float64 = ticks[i];
    let ty = scale_map(&ys, tv);
    out = out + "\n  " + chart_text_anchor_element(px0 - _TICK_GAP, ty + 3.0, chart_format_value(tv), _LABEL_SIZE, color_from_hex(_LABEL_COLOR), "end");
    i = i + 1;
  }
  if f.y_axis.label.len() > 0 {
    let cy = (py0 + py1) * 0.5;
    out = out + "\n  " + chart_text_element(8.0, cy, f.y_axis.label, _AXIS_LABEL_SIZE, color_from_hex(_LABEL_COLOR));
  }
  return out;
}

fn _render_x_axis_text(f: &ChartFigure, b: &_Bounds) -> Str {
  let px0 = chart_plot_x0(&f.layout);
  let px1 = chart_plot_x1(&f.layout);
  let py1 = chart_plot_y1(&f.layout);
  let xs = _x_scale(f, b, px0, px1);
  let ticks = _x_tick_values(f, b);
  let cat = _is_category(f);
  var labels = Vec[Str].new();
  if f.series.len() > 0 {
    let fs: ChartSeries = f.series[0];
    labels = fs.labels;
  }
  var out = "";
  var i = 0;
  while i < ticks.len() {
    let tv: Float64 = ticks[i];
    let tx = scale_map(&xs, tv);
    var label = chart_format_value(tv);
    if cat {
      let idx = to_int(tv + 0.5);
      if idx >= 0 {
        if idx < labels.len() {
          let lab: Str = labels[idx];
          label = lab;
        } else {
          label = convert.int_to_string(idx + 1);
        }
      }
    }
    out = out + "\n  " + chart_text_anchor_element(tx, py1 + _TEXT_GAP, label, _LABEL_SIZE, color_from_hex(_LABEL_COLOR), "middle");
    i = i + 1;
  }
  if f.x_axis.label.len() > 0 {
    let cx = (px0 + px1) * 0.5;
    out = out + "\n  " + chart_text_anchor_element(cx, f.layout.height - 6.0, f.x_axis.label, _AXIS_LABEL_SIZE, color_from_hex(_LABEL_COLOR), "middle");
  }
  return out;
}

fn _render_frame(f: &ChartFigure, b: &_Bounds) -> Str {
  let w = f.layout.width;
  let h = f.layout.height;
  let px0 = chart_plot_x0(&f.layout);
  let py0 = chart_plot_y0(&f.layout);
  let px1 = chart_plot_x1(&f.layout);
  let py1 = chart_plot_y1(&f.layout);
  let xs = _x_scale(f, b, px0, px1);
  let ys = _y_scale(f, b, py1, py0);
  var out = chart_svg_open(w, h);
  out = out + "\n  " + chart_rect_element(0.0, 0.0, w, h, f.background);
  if f.title.len() > 0 {
    out = out + "\n  " + chart_text_anchor_element(w * 0.5, _TITLE_SIZE + 4.0, f.title, _TITLE_SIZE, color_from_hex("#222222"), "middle");
  }
  let axis_col = color_from_hex(_AXIS_COLOR);
  let grid_col = color_from_hex(_GRID_COLOR);
  let yt = _y_tick_values(f, b);
  let xt = _x_tick_values(f, b);
  if f.grid_y {
    var i = 0;
    while i < yt.len() {
      let tv: Float64 = yt[i];
      let ty = scale_map(&ys, tv);
      out = out + "\n  " + chart_line_element(px0, ty, px1, ty, grid_col, 1.0);
      i = i + 1;
    }
  }
  if f.grid_x {
    var i2 = 0;
    while i2 < xt.len() {
      let tv: Float64 = xt[i2];
      let tx = scale_map(&xs, tv);
      out = out + "\n  " + chart_line_element(tx, py0, tx, py1, grid_col, 1.0);
      i2 = i2 + 1;
    }
  }
  out = out + "\n  " + chart_line_element(px0, py0, px0, py1, axis_col, 1.0);
  out = out + "\n  " + chart_line_element(px0, py1, px1, py1, axis_col, 1.0);
  out = out + _render_y_axis_text(f, b);
  out = out + _render_x_axis_text(f, b);
  return out;
}

// --------------------------------------------------
//  Markers
// --------------------------------------------------

fn _marker_shape(x: Float64, y: Float64, marker: Int, c: ChartColor) -> Str {
  var m = marker;
  if m < MARKER_CIRCLE || m > MARKER_TRIANGLE {
    m = MARKER_CIRCLE;
  }
  let r = _MARKER_RADIUS;
  if m == MARKER_CIRCLE {
    return chart_circle_element(x, y, r, c);
  }
  if m == MARKER_SQUARE {
    return chart_rect_element(x - r, y - r, r * 2.0, r * 2.0, c);
  }
  if m == MARKER_DIAMOND {
    var p = Vec[Float64].new();
    p.push(x); p.push(y - (r * 1.3));
    p.push(x + (r * 1.3)); p.push(y);
    p.push(x); p.push(y + (r * 1.3));
    p.push(x - (r * 1.3)); p.push(y);
    return chart_polygon_element(p, c);
  }
  if m == MARKER_CROSS {
    var out = chart_line_element(x - r, y, x + r, y, c, 1.0);
    out = out + "\n  " + chart_line_element(x, y - r, x, y + r, c, 1.0);
    return out;
  }
  var t = Vec[Float64].new();
  t.push(x); t.push(y - r);
  t.push(x + r); t.push(y + r);
  t.push(x - r); t.push(y + r);
  return chart_polygon_element(t, c);
}

// --------------------------------------------------
//  Cartesian renderers
// --------------------------------------------------

fn _line_d(f: &ChartFigure, b: &_Bounds, s: &ChartSeries) -> Str {
  let n = series_len(s);
  if n == 0 {
    return "";
  }
  let px0 = chart_plot_x0(&f.layout);
  let px1 = chart_plot_x1(&f.layout);
  let py0 = chart_plot_y0(&f.layout);
  let py1 = chart_plot_y1(&f.layout);
  let xs = _x_scale(f, b, px0, px1);
  let ys = _y_scale(f, b, py1, py0);
  var d = "";
  var i = 0;
  while i < n {
    let v: Float64 = s.ys[i];
    let xv = _series_x(s, i);
    let x = scale_map(&xs, xv);
    let y = scale_map(&ys, v);
    if i == 0 {
      d = "M" + _fmt_coord(x) + " " + _fmt_coord(y);
    } else {
      d = d + " L" + _fmt_coord(x) + " " + _fmt_coord(y);
    }
    i = i + 1;
  }
  return d;
}

fn _step_d(f: &ChartFigure, s: &ChartSeries) -> Str {
  let n = series_len(s);
  if n == 0 {
    return "";
  }
  let b = _bounds(f);
  let px0 = chart_plot_x0(&f.layout);
  let px1 = chart_plot_x1(&f.layout);
  let py0 = chart_plot_y0(&f.layout);
  let py1 = chart_plot_y1(&f.layout);
  let xs = _x_scale(f, b, px0, px1);
  let ys = _y_scale(f, b, py1, py0);
  let x0 = scale_map(&xs, _series_x(s, 0));
  let v0: Float64 = s.ys[0];
  var py = scale_map(&ys, v0);
  var d = "M" + _fmt_coord(x0) + " " + _fmt_coord(py);
  var i = 1;
  while i < n {
    let xv = _series_x(s, i);
    let x = scale_map(&xs, xv);
    let v: Float64 = s.ys[i];
    let yn = scale_map(&ys, v);
    d = d + " L" + _fmt_coord(x) + " " + _fmt_coord(py);
    d = d + " L" + _fmt_coord(x) + " " + _fmt_coord(yn);
    py = yn;
    i = i + 1;
  }
  return d;
}

fn _render_markers(f: &ChartFigure, s: &ChartSeries, c: ChartColor) -> Str {
  let n = series_len(s);
  if n == 0 || s.marker == MARKER_NONE {
    return "";
  }
  let b = _bounds(f);
  let px0 = chart_plot_x0(&f.layout);
  let px1 = chart_plot_x1(&f.layout);
  let py0 = chart_plot_y0(&f.layout);
  let py1 = chart_plot_y1(&f.layout);
  let xs = _x_scale(f, b, px0, px1);
  let ys = _y_scale(f, b, py1, py0);
  var out = "";
  var i = 0;
  while i < n {
    let v: Float64 = s.ys[i];
    let x = scale_map(&xs, _series_x(s, i));
    let y = scale_map(&ys, v);
    out = out + "\n  " + _marker_shape(x, y, s.marker, c);
    i = i + 1;
  }
  return out;
}

/// Render a multi-series line chart.
/// Each series is one path plus optional markers; the shared frame supplies
/// axes, ticks, grid and legend. Deterministic and byte-stable.
/// Complexity: O(total points).
pub fn chart_line_svg(f: &ChartFigure) -> Str {
  let b = _bounds(f);
  var out = _render_frame(f, &b);
  var si = 0;
  while si < f.series.len() {
    let s: ChartSeries = f.series[si];
    let d = _line_d(f, &b, &s);
    if d.len() > 0 {
      let c = _series_color(f, si, &s);
      out = out + "\n  " + chart_path_element(d, color_none(), c, _clampf(s.line_width, 0.1, 20.0));
      out = out + _render_markers(f, &s, c);
    }
    si = si + 1;
  }
  out = out + _render_annotations(f, &b);
  out = out + _render_legend(f);
  return out + "\n" + chart_svg_close();
}

/// Render a scatter chart. MARKER_NONE is treated as circles; every point is
/// an independent marker, no connecting path is emitted.
/// Complexity: O(total points).
pub fn chart_scatter_svg(f: &ChartFigure) -> Str {
  let b = _bounds(f);
  var out = _render_frame(f, &b);
  let px0 = chart_plot_x0(&f.layout);
  let px1 = chart_plot_x1(&f.layout);
  let py0 = chart_plot_y0(&f.layout);
  let py1 = chart_plot_y1(&f.layout);
  let xs = _x_scale(f, b, px0, px1);
  let ys = _y_scale(f, b, py1, py0);
  var si = 0;
  while si < f.series.len() {
    let s: ChartSeries = f.series[si];
    let c = _series_color(f, si, &s);
    let n = series_len(&s);
    var i = 0;
    while i < n {
      let v: Float64 = s.ys[i];
      let x = scale_map(&xs, _series_x(&s, i));
      let y = scale_map(&ys, v);
      out = out + "\n  " + _marker_shape(x, y, s.marker, c);
      i = i + 1;
    }
    si = si + 1;
  }
  out = out + _render_annotations(f, &b);
  out = out + _render_legend(f);
  return out + "\n" + chart_svg_close();
}

fn _category_geometry(f: &ChartFigure) -> Vec[Float64] {
  let ncat = _max_series_len(f);
  let nser = f.series.len();
  let px0 = chart_plot_x0(&f.layout);
  let pw = chart_plot_w(&f.layout);
  var group = 1.0;
  if ncat > 0 {
    group = pw / (ncat as Float64);
  }
  var inner = group * _clampf(f.bar_width, 0.05, 1.0);
  var bw = inner;
  if nser > 0 {
    bw = inner / (nser as Float64);
  }
  var out = Vec[Float64].new();
  out.push(group);
  out.push(inner);
  out.push(bw);
  out.push(px0);
  return out;
}

/// Render grouped category bars (one bar per series per category).
/// Bar widths use fig.bar_width (clamped to 0.05..1.0) as a fraction of the
/// category slot; positive and negative values both grow from the zero line.
/// Complexity: O(categories * series).
pub fn chart_bar_svg(f: &ChartFigure) -> Str {
  let b = _bounds(f);
  var out = _render_frame(f, &b);
  let geom = _category_geometry(f);
  let group: Float64 = geom[0];
  let inner: Float64 = geom[1];
  let bw: Float64 = geom[2];
  let px0: Float64 = geom[3];
  let py0 = chart_plot_y0(&f.layout);
  let py1 = chart_plot_y1(&f.layout);
  let ys = _y_scale(f, b, py1, py0);
  let base = scale_map(&ys, 0.0);
  var si = 0;
  while si < f.series.len() {
    let s: ChartSeries = f.series[si];
    let c = _series_color(f, si, &s);
    let n = series_len(&s);
    var i = 0;
    while i < n {
      let v: Float64 = s.ys[i];
      let cx = px0 + (((i as Float64) + 0.5) * group);
      let x = cx - (inner * 0.5) + ((si as Float64) * bw);
      let y = scale_map(&ys, v);
      var top = y;
      var h = base - y;
      if v < 0.0 {
        top = base;
        h = y - base;
      }
      out = out + "\n  " + chart_rect_element(x, top, bw, h, c);
      i = i + 1;
    }
    si = si + 1;
  }
  out = out + _render_annotations(f, &b);
  out = out + _render_legend(f);
  return out + "\n" + chart_svg_close();
}

/// Render stacked category bars. Positive values stack upward from zero and
/// negative values stack downward. Series order is bottom-to-top within each
/// sign; category order is left-to-right.
/// Complexity: O(categories * series).
pub fn chart_bar_stacked_svg(f: &ChartFigure) -> Str {
  let b = _bounds(f);
  var out = _render_frame(f, &b);
  let geom = _category_geometry(f);
  let group: Float64 = geom[0];
  let inner: Float64 = geom[1];
  let bw: Float64 = inner;
  let px0: Float64 = geom[3];
  let py0 = chart_plot_y0(&f.layout);
  let py1 = chart_plot_y1(&f.layout);
  let ys = _y_scale(f, b, py1, py0);
  let ncat = _max_series_len(f);
  var i = 0;
  while i < ncat {
    var pos = 0.0;
    var neg = 0.0;
    let cx = px0 + (((i as Float64) + 0.5) * group);
    let x = cx - (inner * 0.5);
    var si = 0;
    while si < f.series.len() {
      let s: ChartSeries = f.series[si];
      if i < series_len(&s) {
        let v: Float64 = s.ys[i];
        let c = _series_color(f, si, &s);
        if v >= 0.0 {
          let y0 = scale_map(&ys, pos);
          pos = pos + v;
          let y1 = scale_map(&ys, pos);
          out = out + "\n  " + chart_rect_element(x, y1, bw, y0 - y1, c);
        } else {
          let y0 = scale_map(&ys, neg);
          neg = neg + v;
          let y1 = scale_map(&ys, neg);
          out = out + "\n  " + chart_rect_element(x, y0, bw, y1 - y0, c);
        }
      }
      si = si + 1;
    }
    i = i + 1;
  }
  out = out + _render_annotations(f, &b);
  out = out + _render_legend(f);
  return out + "\n" + chart_svg_close();
}

/// Render filled areas under each series' line. The baseline is the pixel of
/// value 0 (clamped to the plot); fill alpha is 30% of the series alpha, and
/// the outline uses the full series color.
/// Complexity: O(total points).
pub fn chart_area_svg(f: &ChartFigure) -> Str {
  let b = _bounds(f);
  var out = _render_frame(f, &b);
  let px0 = chart_plot_x0(&f.layout);
  let px1 = chart_plot_x1(&f.layout);
  let py0 = chart_plot_y0(&f.layout);
  let py1 = chart_plot_y1(&f.layout);
  let xs = _x_scale(f, b, px0, px1);
  let ys = _y_scale(f, b, py1, py0);
  let base = scale_map(&ys, 0.0);
  var si = 0;
  while si < f.series.len() {
    let s: ChartSeries = f.series[si];
    let n = series_len(&s);
    if n > 0 {
      let c = _series_color(f, si, &s);
      var poly = Vec[Float64].new();
      let x_first = scale_map(&xs, _series_x(&s, 0));
      let x_last = scale_map(&xs, _series_x(&s, n - 1));
      poly.push(x_first); poly.push(base);
      var i = 0;
      while i < n {
        let v: Float64 = s.ys[i];
        poly.push(scale_map(&xs, _series_x(&s, i)));
        poly.push(scale_map(&ys, v));
        i = i + 1;
      }
      poly.push(x_last); poly.push(base);
      let fill = color_with_alpha(c, c.a * 0.3);
      out = out + "\n  " + chart_polygon_element(poly, fill);
      let d = _line_d(f, &b, &s);
      out = out + "\n  " + chart_path_element(d, color_none(), c, _clampf(s.line_width, 0.1, 20.0));
      out = out + _render_markers(f, &s, c);
    }
    si = si + 1;
  }
  out = out + _render_annotations(f, &b);
  out = out + _render_legend(f);
  return out + "\n" + chart_svg_close();
}

/// Render a step (step-post) chart: from each point go horizontally to the
/// next x, then vertically to the next y.
/// Complexity: O(total points).
pub fn chart_step_svg(f: &ChartFigure) -> Str {
  let b = _bounds(f);
  var out = _render_frame(f, &b);
  var si = 0;
  while si < f.series.len() {
    let s: ChartSeries = f.series[si];
    let d = _step_d(f, &s);
    if d.len() > 0 {
      let c = _series_color(f, si, &s);
      out = out + "\n  " + chart_path_element(d, color_none(), c, _clampf(s.line_width, 0.1, 20.0));
      out = out + _render_markers(f, &s, c);
    }
    si = si + 1;
  }
  out = out + _render_annotations(f, &b);
  out = out + _render_legend(f);
  return out + "\n" + chart_svg_close();
}

// --------------------------------------------------
//  Histogram
// --------------------------------------------------

fn _pool_values(f: &ChartFigure) -> Vec[Float64] {
  var out = Vec[Float64].new();
  var si = 0;
  while si < f.series.len() {
    let s: ChartSeries = f.series[si];
    let n = series_len(&s);
    var i = 0;
    while i < n {
      let v: Float64 = s.ys[i];
      if num.is_finite(v) {
        out.push(v);
      }
      i = i + 1;
    }
    si = si + 1;
  }
  return out;
}

fn _vec_min(v: &Vec[Float64]) -> Float64 {
  if v.len() == 0 {
    return 0.0;
  }
  let first: Float64 = v[0];
  var m = first;
  var i = 1;
  while i < v.len() {
    let x: Float64 = v[i];
    if x < m {
      m = x;
    }
    i = i + 1;
  }
  return m;
}

fn _vec_max(v: &Vec[Float64]) -> Float64 {
  if v.len() == 0 {
    return 0.0;
  }
  let first: Float64 = v[0];
  var m = first;
  var i = 1;
  while i < v.len() {
    let x: Float64 = v[i];
    if x > m {
      m = x;
    }
    i = i + 1;
  }
  return m;
}

/// Render a histogram pooled from every series. Exactly `fig.bins` equal-width
/// bins (clamped to 1..200) span the data range or the explicit x domain. The
/// y domain is [0, max count] unless y_axis is explicit.
/// Complexity: O(points + bins).
pub fn chart_histogram_svg(f: &ChartFigure) -> Str {
  let vals = _pool_values(f);
  let bins = _clampi(f.bins, 1, 200);
  var xmin = 0.0;
  var xmax = 1.0;
  if f.x_axis.auto {
    xmin = _vec_min(&vals);
    xmax = _vec_max(&vals);
    if xmax <= xmin {
      if xmin == 0.0 {
        xmax = 1.0;
      } else {
        let pad = _absf(xmin) * 0.1;
        xmin = xmin - pad;
        xmax = xmax + pad;
      }
    }
  } else {
    xmin = f.x_axis.min;
    xmax = f.x_axis.max;
    if xmax <= xmin {
      xmax = xmin + 1.0;
    }
  }
  let width = (xmax - xmin) / (bins as Float64);
  var counts = Vec[Int].new();
  var k = 0;
  while k < bins {
    counts.push(0);
    k = k + 1;
  }
  var i = 0;
  while i < vals.len() {
    let v: Float64 = vals[i];
    var idx = to_int((v - xmin) / width);
    if idx >= bins {
      idx = bins - 1;
    }
    if idx < 0 {
      idx = 0;
    }
    let cur: Int = counts[idx];
    counts[idx] = cur + 1;
    i = i + 1;
  }
  var maxc = 0;
  var j = 0;
  while j < bins {
    let c: Int = counts[j];
    if c > maxc {
      maxc = c;
    }
    j = j + 1;
  }
  var ymin = 0.0;
  var ymax = 1.0;
  if f.y_axis.auto {
    ymax = maxc as Float64;
    if ymax <= 0.0 {
      ymax = 1.0;
    }
  } else {
    ymin = f.y_axis.min;
    ymax = f.y_axis.max;
  }
  let bb = _Bounds{ xmin: xmin; xmax: xmax; ymin: ymin; ymax: ymax; };
  var out = _render_frame(f, &bb);
  let px0 = chart_plot_x0(&f.layout);
  let px1 = chart_plot_x1(&f.layout);
  let py0 = chart_plot_y0(&f.layout);
  let py1 = chart_plot_y1(&f.layout);
  let xs = _x_scale(f, &bb, px0, px1);
  let ys = _y_scale(f, &bb, py1, py0);
  let base = scale_map(&ys, 0.0);
  var c = palette_color(0);
  if f.series.len() > 0 {
    let s: ChartSeries = f.series[0];
    c = _series_color(f, 0, &s);
  }
  var bi = 0;
  while bi < bins {
    let count: Int = counts[bi];
    if count > 0 {
      let x0 = scale_map(&xs, xmin + ((bi as Float64) * width));
      let x1 = scale_map(&xs, xmin + (((bi + 1) as Float64) * width));
      let y = scale_map(&ys, count as Float64);
      out = out + "\n  " + chart_rect_element(x0, y, x1 - x0, base - y, c);
    }
    bi = bi + 1;
  }
  out = out + _render_annotations(f, &bb);
  out = out + _render_legend(f);
  return out + "\n" + chart_svg_close();
}

// --------------------------------------------------
//  Pie / doughnut
// --------------------------------------------------

fn _polar_x(cx: Float64, r: Float64, a: Float64) -> Float64 {
  return cx + (r * math.cos(a));
}

fn _polar_y(cy: Float64, r: Float64, a: Float64) -> Float64 {
  return cy + (r * math.sin(a));
}

fn _arc_d(cx: Float64, cy: Float64, ro: Float64, ri: Float64, a0: Float64, a1: Float64) -> Str {
  let sweep = a1 - a0;
  if sweep >= _TWO_PI - _EPS {
    let mid = a0 + _PI;
    if ri <= 0.0 {
      var full = "M" + _fmt_coord(cx) + " " + _fmt_coord(cy);
      full = full + " L" + _fmt_coord(_polar_x(cx, ro, a0)) + " " + _fmt_coord(_polar_y(cy, ro, a0));
      full = full + " A" + _fmt_coord(ro) + " " + _fmt_coord(ro) + " 0 1 1 " + _fmt_coord(_polar_x(cx, ro, mid)) + " " + _fmt_coord(_polar_y(cy, ro, mid));
      full = full + " A" + _fmt_coord(ro) + " " + _fmt_coord(ro) + " 0 1 1 " + _fmt_coord(_polar_x(cx, ro, a0)) + " " + _fmt_coord(_polar_y(cy, ro, a0));
      return full + " Z";
    }
    var ring = "M" + _fmt_coord(_polar_x(cx, ro, a0)) + " " + _fmt_coord(_polar_y(cy, ro, a0));
    ring = ring + " A" + _fmt_coord(ro) + " " + _fmt_coord(ro) + " 0 1 1 " + _fmt_coord(_polar_x(cx, ro, mid)) + " " + _fmt_coord(_polar_y(cy, ro, mid));
    ring = ring + " A" + _fmt_coord(ro) + " " + _fmt_coord(ro) + " 0 1 1 " + _fmt_coord(_polar_x(cx, ro, a1)) + " " + _fmt_coord(_polar_y(cy, ro, a1));
    ring = ring + " L" + _fmt_coord(_polar_x(cx, ri, a1)) + " " + _fmt_coord(_polar_y(cy, ri, a1));
    ring = ring + " A" + _fmt_coord(ri) + " " + _fmt_coord(ri) + " 0 1 0 " + _fmt_coord(_polar_x(cx, ri, mid)) + " " + _fmt_coord(_polar_y(cy, ri, mid));
    ring = ring + " A" + _fmt_coord(ri) + " " + _fmt_coord(ri) + " 0 1 0 " + _fmt_coord(_polar_x(cx, ri, a0)) + " " + _fmt_coord(_polar_y(cy, ri, a0));
    return ring + " Z";
  }
  let large = if sweep > _PI { "1" } else { "0" };
  let x0o = _polar_x(cx, ro, a0);
  let y0o = _polar_y(cy, ro, a0);
  let x1o = _polar_x(cx, ro, a1);
  let y1o = _polar_y(cy, ro, a1);
  if ri <= 0.0 {
    var d = "M" + _fmt_coord(cx) + " " + _fmt_coord(cy);
    d = d + " L" + _fmt_coord(x0o) + " " + _fmt_coord(y0o);
    d = d + " A" + _fmt_coord(ro) + " " + _fmt_coord(ro) + " 0 " + large + " 1 " + _fmt_coord(x1o) + " " + _fmt_coord(y1o);
    return d + " Z";
  }
  let x0i = _polar_x(cx, ri, a0);
  let y0i = _polar_y(cy, ri, a0);
  let x1i = _polar_x(cx, ri, a1);
  let y1i = _polar_y(cy, ri, a1);
  var d2 = "M" + _fmt_coord(x0o) + " " + _fmt_coord(y0o);
  d2 = d2 + " A" + _fmt_coord(ro) + " " + _fmt_coord(ro) + " 0 " + large + " 1 " + _fmt_coord(x1o) + " " + _fmt_coord(y1o);
  d2 = d2 + " L" + _fmt_coord(x1i) + " " + _fmt_coord(y1i);
  d2 = d2 + " A" + _fmt_coord(ri) + " " + _fmt_coord(ri) + " 0 " + large + " 0 " + _fmt_coord(x0i) + " " + _fmt_coord(y0i);
  return d2 + " Z";
}

fn _pie_parts(f: &ChartFigure) -> Vec[Float64] {
  var out = Vec[Float64].new();
  if f.series.len() == 0 {
    return out;
  }
  let s: ChartSeries = f.series[0];
  let n = series_len(&s);
  var sum = 0.0;
  var i = 0;
  while i < n {
    let v: Float64 = s.ys[i];
    if v > 0.0 {
      sum = sum + v;
    }
    i = i + 1;
  }
  out.push(sum);
  out.push(n as Float64);
  return out;
}

fn _render_pie_svg(f: &ChartFigure, hole: Float64) -> Str {
  let w = f.layout.width;
  let h = f.layout.height;
  var out = chart_svg_open(w, h);
  out = out + "\n  " + chart_rect_element(0.0, 0.0, w, h, f.background);
  if f.title.len() > 0 {
    out = out + "\n  " + chart_text_anchor_element(w * 0.5, _TITLE_SIZE + 4.0, f.title, _TITLE_SIZE, color_from_hex("#222222"), "middle");
  }
  let px0 = chart_plot_x0(&f.layout);
  let py0 = chart_plot_y0(&f.layout);
  let px1 = chart_plot_x1(&f.layout);
  let py1 = chart_plot_y1(&f.layout);
  let cx = (px0 + px1) * 0.5;
  let cy = (py0 + py1) * 0.5;
  let pw = px1 - px0;
  let ph = py1 - py0;
  let rmax = if pw < ph { pw } else { ph };
  let ro = rmax * 0.45;
  let ri = ro * _clampf(hole, 0.0, 0.95);
  let parts = _pie_parts(f);
  let sum: Float64 = parts[0];
  let n = to_int(parts[1]);
  if sum > 0.0 && f.series.len() > 0 {
    let s: ChartSeries = f.series[0];
    let start0 = 0.0 - (_PI * 0.5);
    var start = start0;
    var i = 0;
    while i < n {
      let v: Float64 = s.ys[i];
      var frac = 0.0;
      if v > 0.0 {
        frac = v / sum;
      }
      var end = start + (frac * _TWO_PI);
      if i == n - 1 {
        end = start0 + _TWO_PI;
      }
      if end > start {
        let d = _arc_d(cx, cy, ro, ri, start, end);
        let c = palette_color(i);
        out = out + "\n  " + chart_path_element(d, c, color_from_hex("#ffffff"), 1.0);
      }
      start = end;
      i = i + 1;
    }
  }
  out = out + _render_legend(f);
  return out + "\n" + chart_svg_close();
}

/// Render a pie chart from the first series (positive values only; labels come
/// from that series and color cycles the default palette).
/// Complexity: O(slices).
pub fn chart_pie_svg(f: &ChartFigure) -> Str {
  return _render_pie_svg(f, 0.0);
}

/// Render a doughnut chart from the first series. fig.doughnut_hole is the
/// inner-radius fraction, clamped to 0..0.95.
/// Complexity: O(slices).
pub fn chart_doughnut_svg(f: &ChartFigure) -> Str {
  return _render_pie_svg(f, f.doughnut_hole);
}

/// Dispatch to the renderer selected by fig.kind. Unknown kinds render as
/// CHART_LINE.
/// Complexity: O(total points).
pub fn chart_svg(f: &ChartFigure) -> Str {
  if f.kind == CHART_SCATTER {
    return chart_scatter_svg(f);
  }
  if f.kind == CHART_BAR {
    return chart_bar_svg(f);
  }
  if f.kind == CHART_BAR_STACKED {
    return chart_bar_stacked_svg(f);
  }
  if f.kind == CHART_AREA {
    return chart_area_svg(f);
  }
  if f.kind == CHART_STEP {
    return chart_step_svg(f);
  }
  if f.kind == CHART_PIE {
    return chart_pie_svg(f);
  }
  if f.kind == CHART_DOUGHNUT {
    return chart_doughnut_svg(f);
  }
  if f.kind == CHART_HISTOGRAM {
    return chart_histogram_svg(f);
  }
  return chart_line_svg(f);
}
