// XIOM -- xiom.svg: SVG 1.1 document builder with element helpers and escaping
// Port task: replace the xiom.svg placeholder with a pure-XIOM module (no FFI).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Scope (SPEC.md is the full contract): an in-memory SVG document builder.
// Callers assemble element strings with the shape helpers, append them to an
// SvgDoc, and serialize the document with svg_render. Output is deterministic:
// fixed attribute order, LF line endings, and a two-space indent per element
// line.
//
// Geometry model: every coordinate, size and width is an Int. Fractional
// coordinates are NOT supported; the caller scales fractions to integers
// before calling (e.g. 12.5 * scale) and keeps the scale alongside the
// document. svg_new clamps a non-positive canvas width or height to 1; the
// shape helpers pass negative values through verbatim (SVG renderers ignore
// non-positive geometry).
//
// Escaping policy (SPEC.md section 5): text content (svg_text) and the path
// values d/stroke (svg_path) are escaped through svg_escape; paint values
// (fill everywhere, svg_line stroke) are emitted verbatim because they are
// keywords, colors or url(#id) references rather than text content.
//
// v0.61.3 notes that shaped this module:
//   * Free functions only (no self methods) and no inline lambdas.
//   * Str equality never uses `==` on values read from Vec[Str] elements
//     (BUG 17: that lowers to a pointer comparison). This module only
//     concatenates element strings; it never compares them.
//   * Elements are read back one at a time through _indented_line so no
//     Vec[Str] element is concatenated in place.
//   * Int -> Str rendering is local (_int_to_str) and exact across the Int
//     range; it uses the proven xiom.string.str_slice + concat idiom rather
//     than pulling in a conversion tower.

module xiom.svg

use xiom.string;
use xiom.string.builder;

// --------------------------------------------------
//  Byte constants (all < 128, so direct UInt8 comparison is safe)
// --------------------------------------------------

const _SVG_AMP: UInt8 = 38u8;
const _SVG_LT: UInt8 = 60u8;
const _SVG_GT: UInt8 = 62u8;
const _SVG_DQUOTE: UInt8 = 34u8;
const _SVG_SQUOTE: UInt8 = 39u8;

// --------------------------------------------------
//  Document model
// --------------------------------------------------

/// An SVG canvas under construction.
/// width/height are canvas dimensions in user units (Int). elements holds
/// prebuilt element strings in append order; each entry is one logical line
/// of the rendered document (svg_add does not split or reformat it).
pub type SvgDoc = {
  width: Int;
  height: Int;
  elements: Vec[Str];
}

// --------------------------------------------------
//  Internal helpers
// --------------------------------------------------

// Exact decimal rendering of an Int (negatives handled; INT_MIN included).
fn _int_to_str(n: Int) -> Str {
  if n == 0 {
    return "0";
  }
  var x = n;
  var neg = false;
  if x < 0 {
    neg = true;
  }
  if x > 0 {
    x = 0 - x;
  }
  var digits = "";
  while x != 0 {
    var d = x % 10;
    if d < 0 {
      d = 0 - d;
    }
    digits = string.str_slice("0123456789", d, d + 1) + digits;
    x = x / 10;
  }
  if neg {
    return "-" + digits;
  }
  return digits;
}

// ` name="<int>"`.
fn _attr_int(name: Str, value: Int) -> Str {
  return " " + name + "=\"" + _int_to_str(value) + "\"";
}

// ` name="<value>"` with the value verbatim, or "" when value is empty.
fn _attr_raw_opt(name: Str, value: Str) -> Str {
  if value.len() == 0 {
    return "";
  }
  return " " + name + "=\"" + value + "\"";
}

// ` name="<value>"` with the value escaped, always emitted.
fn _attr_esc(name: Str, value: Str) -> Str {
  return " " + name + "=\"" + svg_escape(value) + "\"";
}

// ` name="<value>"` with the value escaped, or "" when value is empty.
fn _attr_esc_opt(name: Str, value: Str) -> Str {
  if value.len() == 0 {
    return "";
  }
  return " " + name + "=\"" + svg_escape(value) + "\"";
}

// One rendered line: LF, two spaces, element text.
fn _indented_line(element: Str) -> Str {
  return "\n  " + element;
}

// --------------------------------------------------
//  Document API
// --------------------------------------------------

/// Create an empty canvas.
/// Params: width - canvas width in user units; height - canvas height.
/// Returns: a document with no elements; a non-positive width or height is
/// clamped to 1 so the rendered <svg> always has positive dimensions.
/// Error case: none.
/// Complexity: O(1).
pub fn svg_new(width: Int, height: Int) -> SvgDoc {
  var w = width;
  var h = height;
  if w <= 0 {
    w = 1;
  }
  if h <= 0 {
    h = 1;
  }
  return SvgDoc{ width: w; height: h; elements: Vec[Str].new(); };
}

/// Append a prebuilt element string.
/// Params: d - the canvas; element - one element's markup, appended verbatim
/// (not escaped, not validated, not reformatted).
/// Returns: nothing.
/// Error case: none.
/// Complexity: amortized O(1).
pub fn svg_add(d: &mut SvgDoc, element: Str) {
  d.elements.push(element);
}

/// Element count.
/// Params: d - the canvas.
/// Returns: the number of elements appended so far.
/// Error case: none.
/// Complexity: O(1).
pub fn svg_element_count(d: &SvgDoc) -> Int {
  return d.elements.len();
}

// --------------------------------------------------
//  Element helpers (attribute order is fixed; see SPEC.md section 4)
// --------------------------------------------------

/// Build a <rect> element.
/// Params: x, y - top-left corner; w, h - size; fill - paint value emitted
/// verbatim; an empty fill omits the attribute.
/// Returns: `<rect x=".." y=".." width=".." height=".." fill=".."/>`.
/// Error case: none. Negative geometry is emitted as-is.
/// Complexity: O(digits).
pub fn svg_rect(x: Int, y: Int, w: Int, h: Int, fill: Str) -> Str {
  return "<rect" + _attr_int("x", x) + _attr_int("y", y) + _attr_int("width", w) + _attr_int("height", h) + _attr_raw_opt("fill", fill) + "/>";
}

/// Build a <circle> element.
/// Params: cx, cy - center; r - radius; fill - paint value emitted verbatim;
/// an empty fill omits the attribute.
/// Returns: `<circle cx=".." cy=".." r=".." fill=".."/>`.
/// Error case: none. Negative geometry is emitted as-is.
/// Complexity: O(digits).
pub fn svg_circle(cx: Int, cy: Int, r: Int, fill: Str) -> Str {
  return "<circle" + _attr_int("cx", cx) + _attr_int("cy", cy) + _attr_int("r", r) + _attr_raw_opt("fill", fill) + "/>";
}

/// Build an <ellipse> element.
/// Params: cx, cy - center; rx, ry - radii; fill - paint value emitted
/// verbatim; an empty fill omits the attribute.
/// Returns: `<ellipse cx=".." cy=".." rx=".." ry=".." fill=".."/>`.
/// Error case: none. Negative geometry is emitted as-is.
/// Complexity: O(digits).
pub fn svg_ellipse(cx: Int, cy: Int, rx: Int, ry: Int, fill: Str) -> Str {
  return "<ellipse" + _attr_int("cx", cx) + _attr_int("cy", cy) + _attr_int("rx", rx) + _attr_int("ry", ry) + _attr_raw_opt("fill", fill) + "/>";
}

/// Build a <line> element.
/// Params: x1, y1 - start point; x2, y2 - end point; stroke - stroke paint
/// value, emitted ESCAPED and always present (an empty stroke renders as
/// stroke=""); stroke_width - stroke width in user units, emitted verbatim.
/// Returns: `<line x1=".." y1=".." x2=".." y2=".." stroke=".." stroke-width=".."/>`.
/// Error case: none. Negative coordinates and widths are emitted as-is.
/// Complexity: O(digits).
pub fn svg_line(x1: Int, y1: Int, x2: Int, y2: Int, stroke: Str, stroke_width: Int) -> Str {
  return "<line" + _attr_int("x1", x1) + _attr_int("y1", y1) + _attr_int("x2", x2) + _attr_int("y2", y2) + _attr_esc("stroke", stroke) + _attr_int("stroke-width", stroke_width) + "/>";
}

/// Build a <text> element.
/// Params: x, y - text anchor; text - the character data, ESCAPED; font_size -
/// font size in user units; fill - paint value emitted verbatim; an empty fill
/// omits the attribute.
/// Returns: `<text x=".." y=".." font-size=".." fill="..">escaped</text>`.
/// Error case: none. Negative coordinates and non-positive font sizes are
/// emitted as-is.
/// Complexity: O(digits + text bytes).
pub fn svg_text(x: Int, y: Int, text: Str, font_size: Int, fill: Str) -> Str {
  return "<text" + _attr_int("x", x) + _attr_int("y", y) + _attr_int("font-size", font_size) + _attr_raw_opt("fill", fill) + ">" + svg_escape(text) + "</text>";
}

/// Build a <path> element.
/// Params: d - path data, ESCAPED (this module does not parse or validate
/// it); fill - paint value emitted verbatim, empty omits the attribute;
/// stroke - stroke paint value, ESCAPED, empty omits the attribute.
/// Returns: `<path d=".." fill=".." stroke=".."/>` (fill/stroke omitted when
/// empty, in that order).
/// Error case: none. An empty d is still emitted as d="".
/// Complexity: O(digits + d/stroke bytes).
pub fn svg_path(d: Str, fill: Str, stroke: Str) -> Str {
  return "<path" + _attr_esc("d", d) + _attr_raw_opt("fill", fill) + _attr_esc_opt("stroke", stroke) + "/>";
}

// --------------------------------------------------
//  Escaping
// --------------------------------------------------

/// Escape the five XML/SVG metacharacters as predefined entities.
/// Params: s - the text to escape.
/// Returns: s with & -> &amp;, < -> &lt;, > -> &gt;, " -> &quot; and
/// ' -> &apos;; every other byte (including UTF-8 sequences) passes through
/// byte-exact.
/// Error case: none.
/// Complexity: O(s.len()).
pub fn svg_escape(s: Str) -> Str {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < s.len() {
    let b = string.byte_at(s, i);
    if b == _SVG_AMP {
      builder.sb_push_str(&mut out, "&amp;");
    } elif b == _SVG_LT {
      builder.sb_push_str(&mut out, "&lt;");
    } elif b == _SVG_GT {
      builder.sb_push_str(&mut out, "&gt;");
    } elif b == _SVG_DQUOTE {
      builder.sb_push_str(&mut out, "&quot;");
    } elif b == _SVG_SQUOTE {
      builder.sb_push_str(&mut out, "&apos;");
    } else {
      out.push(b);
    }
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}

// --------------------------------------------------
//  Rendering
// --------------------------------------------------

/// Serialize the document to an SVG string.
/// Params: d - the canvas.
/// Returns: the header
/// `<svg xmlns="http://www.w3.org/2000/svg" width="W" height="H">`, then each
/// element on its own line indented with two spaces, then `</svg>`, joined
/// with LF and no trailing newline. An empty canvas renders as the header
/// line followed by the footer line.
/// Error case: none.
/// Complexity: O(total element bytes).
pub fn svg_render(d: &SvgDoc) -> Str {
  var out = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"" + _int_to_str(d.width) + "\" height=\"" + _int_to_str(d.height) + "\">";
  var i = 0;
  while i < d.elements.len() {
    out = out + _indented_line(d.elements[i]);
    i = i + 1;
  }
  return out + "\n</svg>";
}
