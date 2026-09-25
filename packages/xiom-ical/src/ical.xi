// XIOM -- xiom.ical: RFC 5545-subset iCalendar codec: CRLF folding/unfolding,
// content lines with parameters, TEXT escaping, BEGIN/END component trees and
// a minimal VCALENDAR builder
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model: a parsed stream is a flat component tree. `comp_names` and
// `comp_parents` hold one entry per component (names lowercased; parents are
// component indices, -1 for top-level components). Properties live in the
// `prop_*` vectors; `prop_comps` records the owning component index.
// `Vec[StructType]` is unsupported in this compiler, so the tree is a set of
// flat parallel vectors instead of a vector of component nodes. Parameters
// live in the shared `param_*` pools; each property owns the contiguous slice
// `param_names[prop_param_starts[i] .. +prop_param_lengths[i]]`.
//
// Grammar (see SPEC.md for the exact statement):
//   stream      = *( contentline / blank )
//   contentline = name *( ";" param ) ":" value
//   name        = 1*( ALPHA / DIGIT / "-" )
//   param       = param-name "=" param-value
//   param-value = *( byte except ";" / ":" ) / DQUOTE *( byte except DQUOTE ) DQUOTE
//   value       = *( byte except CR / LF )
//   blank       = *( SP / TAB )
//   line-break  = CRLF / CR / LF
//
// v0.61.3 notes that shaped this module:
//   * Free functions only; all scanning is byte-wise over Str.
//   * Err(Str) for Result[Ical, Str] is constructed only in the leaf helpers
//     _ok_ical/_err_ical (constructing Ok/Err inside other functions
//     miscompiles in this compiler).
//   * Str equality between Vec[Str] elements goes through
//     xiom.string.compare.str_compare (BUG 17: `==` on such values lowers to
//     a pointer comparison).
//   * Every Vec[Int] element read is bound to a typed Int local.

module xiom.ical

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[Ical, Str].
fn _ok_ical(v: Ical) -> Result[Ical, Str] {
  return Ok(v);
}

// Err(m) for Result[Ical, Str].
fn _err_ical(m: Str) -> Result[Ical, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Byte constants
// --------------------------------------------------

const _ICAL_TAB: UInt8 = 9u8;
const _ICAL_LF: UInt8 = 10u8;
const _ICAL_CR: UInt8 = 13u8;
const _ICAL_SP: UInt8 = 32u8;
const _ICAL_DQUOTE: UInt8 = 34u8;
const _ICAL_COMMA: UInt8 = 44u8;
const _ICAL_COLON: UInt8 = 58u8;
const _ICAL_SEMI: UInt8 = 59u8;
const _ICAL_EQ: UInt8 = 61u8;
const _ICAL_BSLASH: UInt8 = 92u8;
const _ICAL_LOWER_N: UInt8 = 110u8;
const _ICAL_UPPER_N: UInt8 = 78u8;

// --------------------------------------------------
//  Data model
// --------------------------------------------------

/// A parsed iCalendar stream: a flat component tree plus a flat property and
/// parameter record. `comp_names[i]` is the lowercased component name of
/// component `i` and `comp_parents[i]` its parent index (-1 at top level).
/// Property `k` belongs to component `prop_comps[k]`; its name is lowercased
/// in `prop_names[k]`, its raw value (escapes preserved) in `prop_values[k]`,
/// and its parameters in `param_names`/`param_values` over the slice
/// `[prop_param_starts[k], prop_param_starts[k] + prop_param_lengths[k])`.
pub type Ical = {
  comp_names: Vec[Str];
  comp_parents: Vec[Int];
  prop_comps: Vec[Int];
  prop_names: Vec[Str];
  prop_values: Vec[Str];
  prop_param_starts: Vec[Int];
  prop_param_lengths: Vec[Int];
  param_names: Vec[Str];
  param_values: Vec[Str];
}

// An empty stream (no components, no properties).
fn _empty_ical() -> Ical {
  return Ical{
    comp_names: Vec[Str].new();
    comp_parents: Vec[Int].new();
    prop_comps: Vec[Int].new();
    prop_names: Vec[Str].new();
    prop_values: Vec[Str].new();
    prop_param_starts: Vec[Int].new();
    prop_param_lengths: Vec[Int].new();
    param_names: Vec[Str].new();
    param_values: Vec[Str].new();
  };
}

// --------------------------------------------------
//  Byte helpers
// --------------------------------------------------

// True for an ASCII space or horizontal tab.
fn _is_wsp(b: UInt8) -> Bool {
  return b == _ICAL_SP || b == _ICAL_TAB;
}

// True for a UTF-8 continuation byte (0x80..0xBF), widened before comparing.
fn _is_utf8_cont(b: UInt8) -> Bool {
  let v = (b as Int) & 0xFF;
  return v >= 128 && v <= 191;
}

// True when `b` is ALPHA, DIGIT or "-": the only bytes allowed in a property
// or component name.
fn _is_token_byte(b: UInt8) -> Bool {
  let c = (b as Int) & 0xFF;
  if c >= 97 && c <= 122 { return true; }
  if c >= 65 && c <= 90 { return true; }
  if c >= 48 && c <= 57 { return true; }
  return c == 45;
}

// True when `s` is a non-empty name made of ALPHA / DIGIT / "-".
fn _token_ok(s: Str) -> Bool {
  if s.len() == 0 {
    return false;
  }
  var i = 0;
  while i < s.len() {
    if !_is_token_byte(string.byte_at(s, i)) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// True when `s` contains a CR or LF byte (such text cannot be a single
// content-line value).
fn _has_line_break(s: Str) -> Bool {
  var i = 0;
  while i < s.len() {
    let b = string.byte_at(s, i);
    if b == _ICAL_CR || b == _ICAL_LF {
      return true;
    }
    i = i + 1;
  }
  return false;
}

// ASCII-lowercase every byte of `s` (names are ASCII; other bytes pass
// through, so the byte length is preserved).
fn _lower_ascii(s: Str) -> Str {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < s.len() {
    let c = (string.byte_at(s, i) as Int) & 0xFF;
    if c >= 65 && c <= 90 {
      out.push((c + 32) as UInt8);
    } else {
      out.push(c as UInt8);
    }
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}

// ASCII-uppercase every byte of `s` (used for serialization; other bytes pass
// through unchanged).
fn _upper_ascii(s: Str) -> Str {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < s.len() {
    let c = (string.byte_at(s, i) as Int) & 0xFF;
    if c >= 97 && c <= 122 {
      out.push((c - 32) as UInt8);
    } else {
      out.push(c as UInt8);
    }
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}

// --------------------------------------------------
//  Folding and TEXT escaping (public)
// --------------------------------------------------

/// Remove RFC 5545 line folding from a whole stream: every line break (CRLF,
/// LF or lone CR) immediately followed by one space or tab is replaced by
/// nothing, together with that single folding whitespace byte. Line breaks
/// that are not followed by whitespace are kept verbatim. A break at the very
/// start of the text is removed too when it is followed by whitespace (the
/// function works on the byte stream, not on logical lines).
/// Complexity: O(text length).
pub fn ical_unfold(text: Str) -> Str {
  var out = Vec[UInt8].new();
  let n = text.len();
  var i = 0;
  while i < n {
    let b = string.byte_at(text, i);
    if b == _ICAL_CR || b == _ICAL_LF {
      var after = i + 1;
      if b == _ICAL_CR && after < n && string.byte_at(text, after) == _ICAL_LF {
        after = after + 1;
      }
      if after < n && _is_wsp(string.byte_at(text, after)) {
        i = after + 1;
      } else {
        out.push(b);
        i = i + 1;
      }
    } else {
      out.push(b);
      i = i + 1;
    }
  }
  return builder.sb_to_str(&out);
}

/// Escape a raw text value for a TEXT-typed property (RFC 5545 3.3.11):
/// backslash -> "\\\\", semicolon -> "\\;", comma -> "\\,", LF -> "\\n" and
/// CR (including the CR of a CRLF pair) -> "\\n". All other bytes are copied
/// verbatim. Complexity: O(s length).
pub fn ical_escape_text(s: Str) -> Str {
  var out = Vec[UInt8].new();
  let n = s.len();
  var i = 0;
  while i < n {
    let b = string.byte_at(s, i);
    if b == _ICAL_BSLASH {
      out.push(_ICAL_BSLASH);
      out.push(_ICAL_BSLASH);
      i = i + 1;
    } elif b == _ICAL_SEMI {
      out.push(_ICAL_BSLASH);
      out.push(_ICAL_SEMI);
      i = i + 1;
    } elif b == _ICAL_COMMA {
      out.push(_ICAL_BSLASH);
      out.push(_ICAL_COMMA);
      i = i + 1;
    } elif b == _ICAL_LF {
      out.push(_ICAL_BSLASH);
      out.push(_ICAL_LOWER_N);
      i = i + 1;
    } elif b == _ICAL_CR {
      if i + 1 < n && string.byte_at(s, i + 1) == _ICAL_LF {
        i = i + 2;
      } else {
        i = i + 1;
      }
      out.push(_ICAL_BSLASH);
      out.push(_ICAL_LOWER_N);
    } else {
      out.push(b);
      i = i + 1;
    }
  }
  return builder.sb_to_str(&out);
}

/// Undo TEXT escaping: "\\\\" -> "\\", "\\;" -> ";", "\\," -> ",", "\\n" and
/// "\\N" -> LF. An unknown escape such as "\\q" is preserved byte-for-byte
/// (both the backslash and the escaped byte are kept), and a trailing lone
/// backslash is kept. Complexity: O(s length).
pub fn ical_unescape_text(s: Str) -> Str {
  var out = Vec[UInt8].new();
  let n = s.len();
  var i = 0;
  while i < n {
    let b = string.byte_at(s, i);
    if b == _ICAL_BSLASH && i + 1 < n {
      let e = string.byte_at(s, i + 1);
      if e == _ICAL_BSLASH {
        out.push(_ICAL_BSLASH);
      } elif e == _ICAL_SEMI {
        out.push(_ICAL_SEMI);
      } elif e == _ICAL_COMMA {
        out.push(_ICAL_COMMA);
      } elif e == _ICAL_LOWER_N || e == _ICAL_UPPER_N {
        out.push(_ICAL_LF);
      } else {
        out.push(_ICAL_BSLASH);
        out.push(e);
      }
      i = i + 2;
    } else {
      out.push(b);
      i = i + 1;
    }
  }
  return builder.sb_to_str(&out);
}

// --------------------------------------------------
//  Content-line scanning helpers
// --------------------------------------------------

// Byte index of the structural ":" of a content line: the first colon
// outside a double-quoted parameter value. -1 when the line has no such colon
// (including when a quote is never closed).
fn _colon_index(line: Str) -> Int {
  var i = 0;
  var in_quote = false;
  while i < line.len() {
    let b = string.byte_at(line, i);
    if in_quote {
      if b == _ICAL_DQUOTE {
        in_quote = false;
      }
      i = i + 1;
    } elif b == _ICAL_DQUOTE {
      in_quote = true;
      i = i + 1;
    } elif b == _ICAL_COLON {
      return i;
    } else {
      i = i + 1;
    }
  }
  return -1;
}

// True when the line has no bytes other than spaces and tabs.
fn _line_is_blank(line: Str) -> Bool {
  var i = 0;
  while i < line.len() {
    if !_is_wsp(string.byte_at(line, i)) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// Parse the parameters of a content line: `line[from, colon)` starts with the
// first ";" and must consist of ";name=value" groups. Names are lowercased;
// values are stored verbatim (quotes kept). Parameter names and values are
// appended to the shared pools `c.param_names`/`c.param_values`. Returns ""
// on success or an "ical: ..." message on failure.
fn _consume_params(c: &mut Ical, line: Str, from: Int, colon: Int) -> Str {
  var p = from;
  while p < colon {
    // p points at a ";".
    p = p + 1;
    let seg_start = p;
    var in_quote = false;
    var eq = -1;
    var seg_end = colon;
    while p < colon {
      let b = string.byte_at(line, p);
      if in_quote {
        if b == _ICAL_DQUOTE {
          in_quote = false;
        }
        p = p + 1;
      } elif b == _ICAL_DQUOTE {
        in_quote = true;
        p = p + 1;
      } elif b == _ICAL_SEMI {
        seg_end = p;
        break;
      } elif b == _ICAL_EQ && eq < 0 {
        eq = p;
        p = p + 1;
      } else {
        p = p + 1;
      }
    }
    if in_quote {
      return "ical: unterminated quoted parameter: " + line;
    }
    if eq < 0 || eq == seg_start {
      return "ical: malformed parameter: " + line;
    }
    c.param_names.push(_lower_ascii(string.str_slice(line, seg_start, eq)));
    c.param_values.push(string.str_slice(line, eq + 1, seg_end));
    p = seg_end;
  }
  return "";
}

// --------------------------------------------------
//  Flat-tree lookup helpers
// --------------------------------------------------

// Pool index of the i-th property of component `comp`, or -1.
fn _prop_index(c: &Ical, comp: Int, i: Int) -> Int {
  var seen = 0;
  var k = 0;
  while k < c.prop_names.len() {
    let pc: Int = c.prop_comps[k];
    if pc == comp {
      if seen == i {
        return k;
      }
      seen = seen + 1;
    }
    k = k + 1;
  }
  return -1;
}

// Pool index of the first property of `comp` whose lowercased name equals
// `lname`, or -1.
fn _find_prop_in(c: &Ical, comp: Int, lname: Str) -> Int {
  var i = 0;
  while i < c.prop_names.len() {
    let pc: Int = c.prop_comps[i];
    if pc == comp {
      let n: Str = c.prop_names[i];
      if compare.str_compare(n, lname) == 0 {
        return i;
      }
    }
    i = i + 1;
  }
  return -1;
}

// Index of the first child of `comp` whose lowercased name equals `lname`,
// or -1.
fn _find_child_in(c: &Ical, comp: Int, lname: Str) -> Int {
  var i = 0;
  while i < c.comp_names.len() {
    let p: Int = c.comp_parents[i];
    if p == comp {
      let n: Str = c.comp_names[i];
      if compare.str_compare(n, lname) == 0 {
        return i;
      }
    }
    i = i + 1;
  }
  return -1;
}

// --------------------------------------------------
//  Parsing (public)
// --------------------------------------------------

/// Parse an in-memory RFC 5545-subset iCalendar stream.
/// Params: text - the whole stream (CRLF preferred; LF and lone CR accepted).
/// Returns: Ok(Ical) with the component tree, properties and parameters, or
/// Err with an "ical: ..." message. Folding is removed first; blank lines are
/// skipped; names are compared case-insensitively and stored lowercased;
/// values and parameter values are stored raw (escaping preserved). BEGIN and
/// END pair by name; nested components nest by stack; parameters on BEGIN/END
/// lines are ignored. Multiple top-level components are allowed; an empty
/// stream parses as an empty tree.
/// Complexity: O(total input length).
pub fn ical_parse(text: Str) -> Result[Ical, Str] {
  var c = _empty_ical();
  let unfolded = ical_unfold(text);
  let n = unfolded.len();
  var open = -1;
  var line_start = 0;
  var i = 0;
  while i <= n {
    if i == n || string.byte_at(unfolded, i) == _ICAL_LF || string.byte_at(unfolded, i) == _ICAL_CR {
      let line = string.str_slice(unfolded, line_start, i);
      if !_line_is_blank(line) {
        let colon = _colon_index(line);
        if colon < 0 {
          return _err_ical("ical: malformed content line: " + line);
        }
        var name_end = 0;
        while name_end < colon && string.byte_at(line, name_end) != _ICAL_SEMI {
          name_end = name_end + 1;
        }
        let name = string.str_slice(line, 0, name_end);
        if !_token_ok(name) {
          return _err_ical("ical: invalid property name: " + name);
        }
        let lname = _lower_ascii(name);
        let value = string.str_slice(line, colon + 1, line.len());
        if compare.str_compare(lname, "begin") == 0 {
          if !_token_ok(value) {
            return _err_ical("ical: invalid component name: " + value);
          }
          let idx = c.comp_names.len();
          c.comp_names.push(_lower_ascii(value));
          c.comp_parents.push(open);
          open = idx;
        } elif compare.str_compare(lname, "end") == 0 {
          if !_token_ok(value) {
            return _err_ical("ical: invalid component name: " + value);
          }
          if open < 0 {
            return _err_ical("ical: unexpected END: " + value);
          }
          let open_name: Str = c.comp_names[open];
          if compare.str_compare(_lower_ascii(value), open_name) != 0 {
            return _err_ical("ical: END:" + value + " does not match BEGIN:" + open_name);
          }
          let parent: Int = c.comp_parents[open];
          open = parent;
        } else {
          if open < 0 {
            return _err_ical("ical: property outside component: " + name);
          }
          let pstart = c.param_names.len();
          let perr = _consume_params(&mut c, line, name_end, colon);
          if perr.len() > 0 {
            return _err_ical(perr);
          }
          c.prop_comps.push(open);
          c.prop_names.push(lname);
          c.prop_values.push(value);
          c.prop_param_starts.push(pstart);
          c.prop_param_lengths.push(c.param_names.len() - pstart);
        }
      }
      if i == n {
        break;
      }
      if string.byte_at(unfolded, i) == _ICAL_CR && i + 1 < n && string.byte_at(unfolded, i + 1) == _ICAL_LF {
        line_start = i + 2;
        i = i + 2;
      } else {
        line_start = i + 1;
        i = i + 1;
      }
    } else {
      i = i + 1;
    }
  }
  if open >= 0 {
    let open_name: Str = c.comp_names[open];
    return _err_ical("ical: unterminated component: " + open_name);
  }
  return _ok_ical(c);
}

// --------------------------------------------------
//  Tree navigation (public)
// --------------------------------------------------

/// Number of components in the stream (every BEGIN/END pair counts once).
pub fn ical_component_count(c: &Ical) -> Int {
  return c.comp_names.len();
}

/// Number of top-level components (parent index -1).
pub fn ical_root_count(c: &Ical) -> Int {
  var n = 0;
  var i = 0;
  while i < c.comp_names.len() {
    let p: Int = c.comp_parents[i];
    if p == -1 {
      n = n + 1;
    }
    i = i + 1;
  }
  return n;
}

/// Index of the i-th top-level component, or -1 when i is out of range.
pub fn ical_root(c: &Ical, i: Int) -> Int {
  var seen = 0;
  var k = 0;
  while k < c.comp_names.len() {
    let p: Int = c.comp_parents[k];
    if p == -1 {
      if seen == i {
        return k;
      }
      seen = seen + 1;
    }
    k = k + 1;
  }
  return -1;
}

/// Lowercased name of component `comp` ("" for an out-of-range index).
pub fn ical_component_name(c: &Ical, comp: Int) -> Str {
  if comp < 0 || comp >= c.comp_names.len() {
    return "";
  }
  let n: Str = c.comp_names[comp];
  return n;
}

/// Parent index of component `comp`: -1 for a top-level component and -2 for
/// an out-of-range index.
pub fn ical_component_parent(c: &Ical, comp: Int) -> Int {
  if comp < 0 || comp >= c.comp_parents.len() {
    return -2;
  }
  let p: Int = c.comp_parents[comp];
  return p;
}

/// Number of direct children of component `comp` (-1 addresses the top level,
/// so `ical_child_count(c, -1)` equals `ical_root_count(c)`).
pub fn ical_child_count(c: &Ical, comp: Int) -> Int {
  var n = 0;
  var i = 0;
  while i < c.comp_names.len() {
    let p: Int = c.comp_parents[i];
    if p == comp {
      n = n + 1;
    }
    i = i + 1;
  }
  return n;
}

/// Index of the i-th direct child of component `comp`, or -1. Pass -1 as
/// `comp` to walk the top level.
pub fn ical_child(c: &Ical, comp: Int, i: Int) -> Int {
  var seen = 0;
  var k = 0;
  while k < c.comp_names.len() {
    let p: Int = c.comp_parents[k];
    if p == comp {
      if seen == i {
        return k;
      }
      seen = seen + 1;
    }
    k = k + 1;
  }
  return -1;
}

/// First direct child of `comp` whose name equals `name`
/// (case-insensitive), or -1. Pass -1 as `comp` to search the top level.
pub fn ical_find_child(c: &Ical, comp: Int, name: Str) -> Int {
  return _find_child_in(c, comp, _lower_ascii(name));
}

// --------------------------------------------------
//  Property access (public)
// --------------------------------------------------

/// Number of direct properties of component `comp` (children excluded).
pub fn ical_prop_count(c: &Ical, comp: Int) -> Int {
  var n = 0;
  var i = 0;
  while i < c.prop_names.len() {
    let pc: Int = c.prop_comps[i];
    if pc == comp {
      n = n + 1;
    }
    i = i + 1;
  }
  return n;
}

/// Lowercased name of the i-th direct property of component `comp` ("" when
/// the ordinal is out of range).
pub fn ical_prop_name(c: &Ical, comp: Int, i: Int) -> Str {
  let k = _prop_index(c, comp, i);
  if k < 0 {
    return "";
  }
  let n: Str = c.prop_names[k];
  return n;
}

/// Raw (still escaped) value of the i-th direct property of component `comp`
/// ("" when the ordinal is out of range).
pub fn ical_prop_value(c: &Ical, comp: Int, i: Int) -> Str {
  let k = _prop_index(c, comp, i);
  if k < 0 {
    return "";
  }
  let v: Str = c.prop_values[k];
  return v;
}

/// TEXT-unescaped value of the i-th direct property of component `comp` (""
/// when the ordinal is out of range).
pub fn ical_prop_value_text(c: &Ical, comp: Int, i: Int) -> Str {
  return ical_unescape_text(ical_prop_value(c, comp, i));
}

/// Pool index of the first direct property of component `comp` named `name`
/// (case-insensitive), or -1.
pub fn ical_find_prop(c: &Ical, comp: Int, name: Str) -> Int {
  return _find_prop_in(c, comp, _lower_ascii(name));
}

/// Raw (still escaped) value of the first direct property of component `comp`
/// named `name` (case-insensitive); None when the property is absent. The
/// first match in document order wins; use `ical_prop_count` and
/// `ical_prop_value` to read duplicates.
pub fn ical_get(c: &Ical, comp: Int, name: Str) -> Option[Str] {
  let k = ical_find_prop(c, comp, name);
  if k < 0 {
    return None;
  }
  let v: Str = c.prop_values[k];
  return Some(v);
}

/// TEXT-unescaped value of the first direct property of component `comp`
/// named `name` (case-insensitive); None when the property is absent.
pub fn ical_get_text(c: &Ical, comp: Int, name: Str) -> Option[Str] {
  let o = ical_get(c, comp, name);
  match o {
    Some(v) => { return Some(ical_unescape_text(v)); },
    None => { return None; },
  }
  return None;
}

/// Number of parameters on the i-th direct property of component `comp`
/// (0 when the ordinal is out of range).
pub fn ical_prop_param_count(c: &Ical, comp: Int, i: Int) -> Int {
  let k = _prop_index(c, comp, i);
  if k < 0 {
    return 0;
  }
  let n: Int = c.prop_param_lengths[k];
  return n;
}

/// Lowercased name of parameter `j` on the i-th direct property of component
/// `comp` ("" when either ordinal is out of range).
pub fn ical_prop_param_name(c: &Ical, comp: Int, i: Int, j: Int) -> Str {
  let k = _prop_index(c, comp, i);
  if k < 0 {
    return "";
  }
  let start: Int = c.prop_param_starts[k];
  let len: Int = c.prop_param_lengths[k];
  if j < 0 || j >= len {
    return "";
  }
  let n: Str = c.param_names[start + j];
  return n;
}

/// Verbatim value of parameter `j` on the i-th direct property of component
/// `comp` ("" when either ordinal is out of range). Quotes of a quoted-string
/// parameter are preserved.
pub fn ical_prop_param_value(c: &Ical, comp: Int, i: Int, j: Int) -> Str {
  let k = _prop_index(c, comp, i);
  if k < 0 {
    return "";
  }
  let start: Int = c.prop_param_starts[k];
  let len: Int = c.prop_param_lengths[k];
  if j < 0 || j >= len {
    return "";
  }
  let v: Str = c.param_values[start + j];
  return v;
}

// --------------------------------------------------
//  Building (public)
// --------------------------------------------------

/// A new empty stream: no components, no properties.
pub fn ical_new() -> Ical {
  return _empty_ical();
}

/// Append a component named `name` under `parent` (use -1 for a top-level
/// component) and return its index. Returns -1 without changing the stream
/// when `name` is not a valid name (ALPHA / DIGIT / "-") or `parent` is
/// neither -1 nor an existing component index.
pub fn ical_add_component(c: &mut Ical, parent: Int, name: Str) -> Int {
  if !_token_ok(name) {
    return -1;
  }
  if parent < -1 || parent >= c.comp_names.len() {
    return -1;
  }
  let idx = c.comp_names.len();
  c.comp_names.push(_lower_ascii(name));
  c.comp_parents.push(parent);
  return idx;
}

/// Append a raw property to component `comp`: `name` is lowercased and
/// `value` is stored verbatim (no escaping is applied; call
/// `ical_add_text_prop` for TEXT values). Returns false without changing the
/// stream when `comp` is out of range, `name` is invalid, or `value` contains
/// a CR or LF byte (which cannot appear in one content line).
pub fn ical_add_prop(c: &mut Ical, comp: Int, name: Str, value: Str) -> Bool {
  if comp < 0 || comp >= c.comp_names.len() {
    return false;
  }
  if !_token_ok(name) {
    return false;
  }
  if _has_line_break(value) {
    return false;
  }
  c.prop_comps.push(comp);
  c.prop_names.push(_lower_ascii(name));
  c.prop_values.push(value);
  c.prop_param_starts.push(c.param_names.len());
  c.prop_param_lengths.push(0);
  return true;
}

/// Append a TEXT property to component `comp`: `text` is escaped with
/// `ical_escape_text` and stored. Returns false without changing the stream
/// when `comp` is out of range or `name` is invalid (escaping always produces
/// a value that fits one content line).
pub fn ical_add_text_prop(c: &mut Ical, comp: Int, name: Str, text: Str) -> Bool {
  return ical_add_prop(c, comp, name, ical_escape_text(text));
}

/// Build a minimal VCALENDAR containing one VEVENT, with the RFC-required
/// VERSION ("2.0") and PRODID properties and the seven event properties in
/// this order: UID, DTSTAMP, DTSTART, DTEND, SUMMARY, DESCRIPTION, LOCATION.
/// UID, SUMMARY, DESCRIPTION and LOCATION are escaped as TEXT; DTSTAMP,
/// DTSTART and DTEND are DATE-TIME values and are stored verbatim, so they
/// must not contain CR or LF (such values are dropped).
pub fn ical_build_event(uid: Str, dtstamp: Str, dtstart: Str, dtend: Str, summary: Str, description: Str, location: Str) -> Ical {
  var c = _empty_ical();
  let cal = ical_add_component(&mut c, -1, "VCALENDAR");
  let ev = ical_add_component(&mut c, cal, "VEVENT");
  ical_add_prop(&mut c, cal, "VERSION", "2.0");
  ical_add_prop(&mut c, cal, "PRODID", "-//xiom-packages//xiom.ical 0.1.0//EN");
  ical_add_text_prop(&mut c, ev, "UID", uid);
  ical_add_prop(&mut c, ev, "DTSTAMP", dtstamp);
  ical_add_prop(&mut c, ev, "DTSTART", dtstart);
  ical_add_prop(&mut c, ev, "DTEND", dtend);
  ical_add_text_prop(&mut c, ev, "SUMMARY", summary);
  ical_add_text_prop(&mut c, ev, "DESCRIPTION", description);
  ical_add_text_prop(&mut c, ev, "LOCATION", location);
  return c;
}

// --------------------------------------------------
//  Serialization (public)
// --------------------------------------------------

// Append one content line to `out` followed by CRLF. When `fold` is true the
// line is folded at 75 octets for the first physical line and 74 octets for
// each continuation (the leading space of a continuation counts), without
// ever splitting a multi-byte UTF-8 sequence: the boundary is moved back over
// UTF-8 continuation bytes (0x80..0xBF). A pathological line made only of
// continuation bytes advances by one byte to guarantee progress.
fn _emit_line(out: &mut Vec[UInt8], line: Str, fold: Bool) {
  if !fold {
    builder.sb_push_str(out, line);
    builder.sb_push_byte(out, _ICAL_CR);
    builder.sb_push_byte(out, _ICAL_LF);
    return;
  }
  let n = line.len();
  var start = 0;
  var limit = 75;
  while n - start > limit {
    var end = start + limit;
    while end > start && _is_utf8_cont(string.byte_at(line, end)) {
      end = end - 1;
    }
    if end == start {
      end = start + 1;
    }
    var i = start;
    while i < end {
      out.push(string.byte_at(line, i));
      i = i + 1;
    }
    out.push(_ICAL_CR);
    out.push(_ICAL_LF);
    out.push(_ICAL_SP);
    start = end;
    limit = 74;
  }
  var j = start;
  while j < n {
    out.push(string.byte_at(line, j));
    j = j + 1;
  }
  out.push(_ICAL_CR);
  out.push(_ICAL_LF);
}

// Append one property (name uppercased, parameters verbatim, value verbatim).
fn _emit_prop(c: &Ical, pi: Int, out: &mut Vec[UInt8], fold: Bool) {
  let name: Str = c.prop_names[pi];
  var line = Vec[UInt8].new();
  builder.sb_push_str(&mut line, _upper_ascii(name));
  let pstart: Int = c.prop_param_starts[pi];
  let plen: Int = c.prop_param_lengths[pi];
  var j = 0;
  while j < plen {
    let pn: Str = c.param_names[pstart + j];
    let pv: Str = c.param_values[pstart + j];
    builder.sb_push_byte(&mut line, _ICAL_SEMI);
    builder.sb_push_str(&mut line, _upper_ascii(pn));
    builder.sb_push_byte(&mut line, _ICAL_EQ);
    builder.sb_push_str(&mut line, pv);
    j = j + 1;
  }
  builder.sb_push_byte(&mut line, _ICAL_COLON);
  let value: Str = c.prop_values[pi];
  builder.sb_push_str(&mut line, value);
  _emit_line(out, builder.sb_to_str(&line), fold);
}

// Append BEGIN:name, the component's properties, its children (in component
// order) and END:name.
fn _emit_comp(c: &Ical, comp: Int, out: &mut Vec<UInt8>, fold: Bool) {
  let name: Str = c.comp_names[comp];
  var head = Vec[UInt8].new();
  builder.sb_push_str(&mut head, "BEGIN:");
  builder.sb_push_str(&mut head, _upper_ascii(name));
  _emit_line(out, builder.sb_to_str(&head), fold);
  var i = 0;
  while i < c.prop_names.len() {
    let pc: Int = c.prop_comps[i];
    if pc == comp {
      _emit_prop(c, i, out, fold);
    }
    i = i + 1;
  }
  var k = 0;
  while k < c.comp_names.len() {
    let p: Int = c.comp_parents[k];
    if p == comp {
      _emit_comp(c, k, out, fold);
    }
    k = k + 1;
  }
  var tail = Vec[UInt8].new();
  builder.sb_push_str(&mut tail, "END:");
  builder.sb_push_str(&mut tail, _upper_ascii(name));
  _emit_line(out, builder.sb_to_str(&tail), fold);
}

/// Serialize the stream to iCalendar text: CRLF line endings, names
/// uppercased, parameters and raw values preserved verbatim, top-level
/// components and their subtrees in component order, each component's
/// BEGIN, then its direct properties, then its children, then its END. No
/// folding is applied; use `ical_serialize_folded` for transport-sized lines.
/// Complexity: O(output length).
pub fn ical_serialize(c: &Ical) -> Str {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < c.comp_names.len() {
    let p: Int = c.comp_parents[i];
    if p == -1 {
      _emit_comp(c, i, &mut out, false);
    }
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}

/// Like `ical_serialize`, but each content line is folded so that every
/// physical line is at most 75 octets long excluding CRLF, with multi-byte
/// UTF-8 sequences kept intact. `ical_unfold(ical_serialize_folded(c))` equals
/// `ical_serialize(c)`.
/// Complexity: O(output length).
pub fn ical_serialize_folded(c: &Ical) -> Str {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < c.comp_names.len() {
    let p: Int = c.comp_parents[i];
    if p == -1 {
      _emit_comp(c, i, &mut out, true);
    }
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}
