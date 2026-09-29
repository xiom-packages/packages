// XIOM -- xiom.charts: deterministic integer chart model with an SVG emitter
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Scope (SPEC.md is the full contract): turn an integer data series into a
// complete SVG 1.1 document. Line and bar charts share one integer layout
// (canvas width/height, uniform padding, y-tick count) and one scaling rule:
//
//   y = y_bottom - round_half_away_from_zero((v - dom_min) * plot_h / span)
//
// where span = dom_max - dom_min, v is clamped to [dom_min, dom_max] first,
// and every arithmetic step is Int -- no Float64 anywhere in the module.
// Rounding rules are pinned in SPEC.md sections 3-5 and by the conformance
// suite (tests/test_conformance.xi).
//
// v0.62.1 notes that shaped this module:
//   * Free functions only; no self methods, no inline lambdas, no
//     Vec[StructType].
//   * Str values read from Vec[Str] elements are always bound to a typed
//     local before use (BUG 17: `==` and `.len()` on the element expression
//     mislower to pointer operations).
//   * The module itself never compares Str values; Str equality lives in the
//     tests and goes through xiom.string.compare.
//   * Document text is Str-concatenation built. Byte-level work happens only
//     in chart_escape, where 0x00 bytes are dropped because a Str cannot
//     round-trip NUL (sb_to_str aborts on it).
//   * Int -> Str is convert.int_to_string (exact for the full Int range).
//   * `(0 - x)` is used instead of unary minus in the rounding helper.

module xiom.charts

use xiom.string;
use xiom.string.builder;
use xiom.convert;

// --------------------------------------------------
//  Byte constants (all < 128, so direct UInt8 comparison is safe)
// --------------------------------------------------

const _CH_AMP: UInt8 = 38u8;
const _CH_LT: UInt8 = 60u8;
const _CH_GT: UInt8 = 62u8;
const _CH_DQUOTE: UInt8 = 34u8;
const _CH_SQUOTE: UInt8 = 39u8;

// --------------------------------------------------
//  Default palette (v0.1.0: fixed, not configurable)
// --------------------------------------------------

const _CH_AXIS: Str = "#000000";
const _CH_GRID: Str = "#e6e6e6";
const _CH_BAR_FILL: Str = "#4c78a8";
const _CH_LINE_STROKE: Str = "#4c78a8";
const _CH_LABEL_FILL: Str = "#333333";
const _CH_LABEL_SIZE: Int = 10;
const _CH_LABEL_GAP: Int = 12;
const _CH_TICK_DX: Int = 4;
const _CH_TICK_DY: Int = 3;

// --------------------------------------------------
//  Model
// --------------------------------------------------

/// A labelled integer data series.
/// labels and values are parallel vectors; series_len is authoritative and
/// every function reads at most that many entries, so a caller that supplies
/// vectors of different lengths never triggers an out-of-bounds read (the
/// longer vector is truncated for all purposes).
pub type ChartSeries = {
  labels: Vec[Str];
  values: Vec[Int];
}

/// A fixed integer chart layout.
/// width/height - canvas size in user units; pad - uniform padding on all
/// four sides; ticks - number of y-axis ticks (including both ends).
/// chart_layout clamps all four fields (see chart_layout docs); after that,
/// the plot rectangle is always at least 1 x 1.
pub type ChartLayout = {
  width: Int;
  height: Int;
  pad: Int;
  ticks: Int;
}

// --------------------------------------------------
//  Internal helpers
// --------------------------------------------------

// Round n/d to the nearest integer, halves away from zero. Requires d > 0.
// Int division truncates toward zero, so the naive ceil idiom (n + d - 1)/d
// is wrong for negative n; the remainder decides the correction instead.
fn _div_round_half_away(n: Int, d: Int) -> Int {
  let q = n / d;
  let r = n % d;
  let two_r = r * 2;
  if two_r >= d {
    return q + 1;
  }
  if (0 - two_r) >= d {
    return q - 1;
  }
  return q;
}

// ` name="<value>"` with the integer rendered in exact decimal.
fn _attr_int(name: Str, value: Int) -> Str {
  return " " + name + "=\"" + convert.int_to_string(value) + "\"";
}

// X pixel of point i of n evenly spaced points across a plot of width pw
// that starts at x0. n <= 1 returns x0; otherwise
// x0 + round_half_away_from_zero(i * pw / (n - 1)).
fn _x_at(i: Int, n: Int, x0: Int, pw: Int) -> Int {
  if n <= 1 {
    return x0;
  }
  return x0 + _div_round_half_away(i * pw, n - 1);
}

// --------------------------------------------------
//  Series, layout and geometry
// --------------------------------------------------

/// Create a series from parallel label/value vectors.
/// Params: labels - category labels; values - data points.
/// Returns: a ChartSeries holding both vectors as given.
/// Error case: none. Mismatched lengths are allowed; series_len exposes the
/// usable prefix length.
/// Complexity: O(1).
pub fn series_new(labels: Vec[Str], values: Vec[Int]) -> ChartSeries {
  return ChartSeries{ labels: labels; values: values; };
}

/// Usable series length.
/// Params: s - the series.
/// Returns: min(labels.len(), values.len()) -- the number of points every
/// reader is allowed to touch.
/// Error case: none.
/// Complexity: O(1).
pub fn series_len(s: &ChartSeries) -> Int {
  let n_labels = s.labels.len();
  let n_values = s.values.len();
  if n_values < n_labels {
    return n_values;
  }
  return n_labels;
}

/// Smallest value in the usable prefix.
/// Params: s - the series.
/// Returns: the minimum of values[0..series_len); 0 for an empty prefix.
/// Error case: none.
/// Complexity: O(series_len).
pub fn chart_min(s: &ChartSeries) -> Int {
  let n = series_len(s);
  if n == 0 {
    return 0;
  }
  let first: Int = s.values[0];
  var m = first;
  var i = 1;
  while i < n {
    let v: Int = s.values[i];
    if v < m {
      m = v;
    }
    i = i + 1;
  }
  return m;
}

/// Largest value in the usable prefix.
/// Params: s - the series.
/// Returns: the maximum of values[0..series_len); 0 for an empty prefix.
/// Error case: none.
/// Complexity: O(series_len).
pub fn chart_max(s: &ChartSeries) -> Int {
  let n = series_len(s);
  if n == 0 {
    return 0;
  }
  let first: Int = s.values[0];
  var m = first;
  var i = 1;
  while i < n {
    let v: Int = s.values[i];
    if v > m {
      m = v;
    }
    i = i + 1;
  }
  return m;
}

/// Create a validated layout.
/// Params: width, height - canvas size; pad - uniform padding; ticks -
/// requested y-tick count.
/// Returns: a ChartLayout with width/height clamped to >= 1, pad clamped to
/// [0, min((width-1)/2, (height-1)/2)] (integer division), and ticks clamped
/// to >= 2. The clamp guarantees plot_w >= 1 and plot_h >= 1.
/// Error case: none.
/// Complexity: O(1).
pub fn chart_layout(width: Int, height: Int, pad: Int, ticks: Int) -> ChartLayout {
  var w = width;
  var h = height;
  if w <= 0 {
    w = 1;
  }
  if h <= 0 {
    h = 1;
  }
  var p = pad;
  if p < 0 {
    p = 0;
  }
  let max_pad_w = (w - 1) / 2;
  let max_pad_h = (h - 1) / 2;
  if p > max_pad_w {
    p = max_pad_w;
  }
  if p > max_pad_h {
    p = max_pad_h;
  }
  var t = ticks;
  if t < 2 {
    t = 2;
  }
  return ChartLayout{ width: w; height: h; pad: p; ticks: t; };
}

/// Plot rectangle left edge. Params: l - the layout. Returns: l.pad.
/// Error case: none. Complexity: O(1).
pub fn chart_plot_x0(l: &ChartLayout) -> Int {
  return l.pad;
}

/// Plot rectangle top edge. Params: l - the layout. Returns: l.pad.
/// Error case: none. Complexity: O(1).
pub fn chart_plot_y0(l: &ChartLayout) -> Int {
  return l.pad;
}

/// Plot rectangle width. Params: l - the layout.
/// Returns: l.width - 2 * l.pad, always >= 1.
/// Error case: none. Complexity: O(1).
pub fn chart_plot_w(l: &ChartLayout) -> Int {
  return l.width - (2 * l.pad);
}

/// Plot rectangle height. Params: l - the layout.
/// Returns: l.height - 2 * l.pad, always >= 1.
/// Error case: none. Complexity: O(1).
pub fn chart_plot_h(l: &ChartLayout) -> Int {
  return l.height - (2 * l.pad);
}

// --------------------------------------------------
//  Scaling and ticks
// --------------------------------------------------

/// Map a data value to a pixel y coordinate.
/// Params: v - the value; dom_min/dom_max - the value domain (normalized so
/// dom_max > dom_min; a degenerate domain behaves as [dom_min, dom_min + 1]);
/// y_bottom - pixel y of the domain minimum; plot_h - plot height in pixels
/// (negative treated as 0).
/// Returns: y_bottom - round_half_away_from_zero((vc - dom_min) * plot_h /
/// (dom_max - dom_min)), where vc is v clamped to the normalized domain. The
/// result therefore always lies in [y_bottom - plot_h, y_bottom].
/// Error case: none. Rounding is exact half away from zero; after clamping
/// the numerator is never negative, but the helper is sign-correct anyway.
/// Complexity: O(1).
pub fn chart_scale_y(v: Int, dom_min: Int, dom_max: Int, y_bottom: Int, plot_h: Int) -> Int {
  var dmax = dom_max;
  if dmax <= dom_min {
    dmax = dom_min + 1;
  }
  var ph = plot_h;
  if ph < 0 {
    ph = 0;
  }
  var vc = v;
  if vc < dom_min {
    vc = dom_min;
  }
  if vc > dmax {
    vc = dmax;
  }
  let span = dmax - dom_min;
  let num = (vc - dom_min) * ph;
  let off = _div_round_half_away(num, span);
  return y_bottom - off;
}

/// Evenly spaced y-axis tick values.
/// Params: dom_min/dom_max - the value domain (normalized so dom_max >
/// dom_min; degenerate behaves as [dom_min, dom_min + 1]); count - requested
/// tick count (clamped to >= 2).
/// Returns: exactly max(count, 2) values, ascending, with tick[0] = dom_min
/// and tick[last] = normalized dom_max; interior tick j is
/// dom_min + round_half_away_from_zero(j * span / (count - 1)). Adjacent
/// ticks may coincide when the domain is narrower than the tick count.
/// Error case: none.
/// Complexity: O(count).
pub fn chart_ticks(dom_min: Int, dom_max: Int, count: Int) -> Vec[Int] {
  var t = count;
  if t < 2 {
    t = 2;
  }
  var dmax = dom_max;
  if dmax <= dom_min {
    dmax = dom_min + 1;
  }
  let span = dmax - dom_min;
  let denom = t - 1;
  var out = Vec[Int].new();
  var j = 0;
  while j < t {
    let off = _div_round_half_away(j * span, denom);
    out.push(dom_min + off);
    j = j + 1;
  }
  return out;
}

// --------------------------------------------------
//  Escaping
// --------------------------------------------------

/// Escape the five XML metacharacters as predefined entities.
/// Params: s - the text to escape.
/// Returns: s with & -> &amp;, < -> &lt;, > -> &gt;, " -> &quot; and
/// ' -> &apos;; every other byte (including multi-byte UTF-8 sequences)
/// passes through unchanged, except 0x00 which is dropped (XML 1.0 cannot
/// represent NUL and a Str cannot round-trip it).
/// Error case: none.
/// Complexity: O(s.len()).
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
//  Element emitters (attribute order is fixed; all Str values are escaped)
// --------------------------------------------------

/// Build a <rect> element.
/// Params: x, y - top-left corner; w, h - size; fill - paint value ESCAPED,
/// omitted when empty.
/// Returns: `<rect x=".." y=".." width=".." height=".." fill=".."/>`.
/// Error case: none. Negative geometry is emitted as-is.
/// Complexity: O(digits).
pub fn chart_rect_element(x: Int, y: Int, w: Int, h: Int, fill: Str) -> Str {
  var s = "<rect" + _attr_int("x", x) + _attr_int("y", y);
  s = s + _attr_int("width", w) + _attr_int("height", h);
  if fill.len() > 0 {
    s = s + " fill=\"" + chart_escape(fill) + "\"";
  }
  return s + "/>";
}

/// Build a <line> element.
/// Params: x1, y1 - start point; x2, y2 - end point; stroke - stroke paint
/// value ESCAPED and always emitted; stroke_width - stroke width, always
/// emitted.
/// Returns: `<line x1=".." y1=".." x2=".." y2=".." stroke=".."
/// stroke-width=".."/>`.
/// Error case: none. Negative coordinates and widths are emitted as-is.
/// Complexity: O(digits).
pub fn chart_line_element(x1: Int, y1: Int, x2: Int, y2: Int, stroke: Str, stroke_width: Int) -> Str {
  var s = "<line" + _attr_int("x1", x1) + _attr_int("y1", y1);
  s = s + _attr_int("x2", x2) + _attr_int("y2", y2);
  s = s + " stroke=\"" + chart_escape(stroke) + "\"";
  return s + _attr_int("stroke-width", stroke_width) + "/>";
}

/// Build a <path> element.
/// Params: d - path data, ESCAPED and always emitted; fill - paint value
/// ESCAPED, omitted when empty; stroke - stroke paint value ESCAPED, omitted
/// when empty; stroke_width - emitted exactly when stroke is non-empty.
/// Returns: `<path d=".." fill=".." stroke=".." stroke-width=".."/>` with
/// the empty fill/stroke attributes (and stroke-width) omitted.
/// Error case: none. An empty d is still emitted as d="".
/// Complexity: O(digits + d/stroke bytes).
pub fn chart_path_element(d: Str, fill: Str, stroke: Str, stroke_width: Int) -> Str {
  var s = "<path d=\"" + chart_escape(d) + "\"";
  if fill.len() > 0 {
    s = s + " fill=\"" + chart_escape(fill) + "\"";
  }
  if stroke.len() > 0 {
    s = s + " stroke=\"" + chart_escape(stroke) + "\"";
    s = s + _attr_int("stroke-width", stroke_width);
  }
  return s + "/>";
}

/// Build a <text> element.
/// Params: x, y - text anchor; text - character data, ESCAPED; font_size -
/// font size; fill - paint value ESCAPED, omitted when empty.
/// Returns: `<text x=".." y=".." font-size=".." fill="..">escaped</text>`.
/// Error case: none. Negative coordinates and non-positive font sizes are
/// emitted as-is.
/// Complexity: O(digits + text bytes).
pub fn chart_text_element(x: Int, y: Int, text: Str, font_size: Int, fill: Str) -> Str {
  var s = "<text" + _attr_int("x", x) + _attr_int("y", y);
  s = s + _attr_int("font-size", font_size);
  if fill.len() > 0 {
    s = s + " fill=\"" + chart_escape(fill) + "\"";
  }
  return s + ">" + chart_escape(text) + "</text>";
}

// --------------------------------------------------
//  Document rendering
// --------------------------------------------------

// Header, both axes and the y-tick gridlines/labels, LF-joined with
// two-space indentation. Callers append series elements and "\n</svg>".
fn _chart_frame(s: &ChartSeries, l: &ChartLayout) -> Str {
  let px0 = chart_plot_x0(l);
  let py0 = chart_plot_y0(l);
  let pw = chart_plot_w(l);
  let ph = chart_plot_h(l);
  let px1 = px0 + pw;
  let pbot = py0 + ph;
  let dmin = chart_min(s);
  var dmax = chart_max(s);
  if dmax <= dmin {
    dmax = dmin + 1;
  }
  var out = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"" + convert.int_to_string(l.width) + "\" height=\"" + convert.int_to_string(l.height) + "\">";
  out = out + "\n  " + chart_line_element(px0, py0, px0, pbot, _CH_AXIS, 1);
  out = out + "\n  " + chart_line_element(px0, pbot, px1, pbot, _CH_AXIS, 1);
  let ticks = chart_ticks(dmin, dmax, l.ticks);
  var j = 0;
  while j < ticks.len() {
    let tv: Int = ticks[j];
    let ty = chart_scale_y(tv, dmin, dmax, pbot, ph);
    out = out + "\n  " + chart_line_element(px0, ty, px1, ty, _CH_GRID, 1);
    var lx = px0 - _CH_TICK_DX;
    if lx < 0 {
      lx = 0;
    }
    let ly = ty + _CH_TICK_DY;
    out = out + "\n  " + chart_text_element(lx, ly, convert.int_to_string(tv), _CH_LABEL_SIZE, _CH_LABEL_FILL);
    j = j + 1;
  }
  return out;
}

/// Render a bar chart as a complete SVG document.
/// Params: s - the series (min/max over the usable prefix form the domain;
/// a flat domain is widened to [min, min + 1]); l - the layout.
/// Returns: `<svg>` header, y axis, x axis, then per y-tick a gridline and
/// its label, then one <rect> per point (left to right, stride
/// max(1, plot_w / n), width max(1, stride - 1), top at scale_y(value),
/// height down to the x axis), then one category label per point at x of the
/// bar and y = plot_bottom + 12. Elements are LF-joined with two-space
/// indentation and no trailing newline. An empty series renders the frame
/// only.
/// Error case: none.
/// Complexity: O(n * digits).
pub fn chart_bar_svg(s: &ChartSeries, l: &ChartLayout) -> Str {
  let n = series_len(s);
  let px0 = chart_plot_x0(l);
  let pw = chart_plot_w(l);
  let ph = chart_plot_h(l);
  let pbot = chart_plot_y0(l) + ph;
  let dmin = chart_min(s);
  var dmax = chart_max(s);
  if dmax <= dmin {
    dmax = dmin + 1;
  }
  var out = _chart_frame(s, l);
  if n > 0 {
    var slot = pw / n;
    if slot < 1 {
      slot = 1;
    }
    var bw = slot - 1;
    if bw < 1 {
      bw = 1;
    }
    var i = 0;
    while i < n {
      let v: Int = s.values[i];
      let by = chart_scale_y(v, dmin, dmax, pbot, ph);
      let bh = pbot - by;
      let bx = px0 + (i * slot);
      out = out + "\n  " + chart_rect_element(bx, by, bw, bh, _CH_BAR_FILL);
      i = i + 1;
    }
    i = 0;
    while i < n {
      let lab: Str = s.labels[i];
      let bx = px0 + (i * slot);
      out = out + "\n  " + chart_text_element(bx, pbot + _CH_LABEL_GAP, lab, _CH_LABEL_SIZE, _CH_LABEL_FILL);
      i = i + 1;
    }
  }
  return out + "\n</svg>";
}

/// Render a line chart as a complete SVG document.
/// Params: s - the series (min/max over the usable prefix form the domain;
/// a flat domain is widened to [min, min + 1]); l - the layout.
/// Returns: `<svg>` header, y axis, x axis, then per y-tick a gridline and
/// its label, then one <path> connecting the points (M x y, then " L x y"
/// per further point; x per _x_at, y per chart_scale_y), then one category
/// label per point at the point's x and y = plot_bottom + 12. Elements are
/// LF-joined with two-space indentation and no trailing newline. An empty
/// series renders the frame only; a single point renders a lone M command.
/// Error case: none.
/// Complexity: O(n * digits).
pub fn chart_line_svg(s: &ChartSeries, l: &ChartLayout) -> Str {
  let n = series_len(s);
  let px0 = chart_plot_x0(l);
  let pw = chart_plot_w(l);
  let ph = chart_plot_h(l);
  let pbot = chart_plot_y0(l) + ph;
  let dmin = chart_min(s);
  var dmax = chart_max(s);
  if dmax <= dmin {
    dmax = dmin + 1;
  }
  var out = _chart_frame(s, l);
  if n > 0 {
    var d = "";
    var i = 0;
    while i < n {
      let v: Int = s.values[i];
      let x = _x_at(i, n, px0, pw);
      let y = chart_scale_y(v, dmin, dmax, pbot, ph);
      if i == 0 {
        d = "M" + convert.int_to_string(x) + " " + convert.int_to_string(y);
      } else {
        d = d + " L" + convert.int_to_string(x) + " " + convert.int_to_string(y);
      }
      i = i + 1;
    }
    out = out + "\n  " + chart_path_element(d, "none", _CH_LINE_STROKE, 1);
    i = 0;
    while i < n {
      let lab: Str = s.labels[i];
      let x = _x_at(i, n, px0, pw);
      out = out + "\n  " + chart_text_element(x, pbot + _CH_LABEL_GAP, lab, _CH_LABEL_SIZE, _CH_LABEL_FILL);
      i = i + 1;
    }
  }
  return out + "\n</svg>";
}
