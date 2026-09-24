// XIOM -- xiom.eml: RFC 5322/MIME message structure: unfolded headers, body
// split, and multipart boundaries
// Greenfield package: pure XIOM, no FFI, no file I/O (in-memory Str only).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model: a parsed message is a flat Email. `names` holds every header field
// name lowercased, in document order; `values` holds the unfolded field
// values, aligned by index; `body` is the raw text after the first blank
// line, verbatim. Duplicate headers are preserved in order (RFC 5322 allows
// repeated fields, e.g. Received). Vec[StructType] is unsupported in this
// compiler, so the header list is deliberately flat (two Vec[Str]) instead of
// a list of field structs.
//
// Grammar (see SPEC.md for the full statement):
//   message     = *( field ) blank-line body
//   field       = name ":" *WSP value *( line-break WSP value )
//   name        = 1* ( byte except ":" / CR / LF )   ; lowercased on parse
//   value       = *( byte except CR / LF )
//   body        = *( byte )                          ; verbatim, may be empty
// A physical line is terminated by LF, CRLF or a lone CR; the first
// zero-length line ends the header block. A continuation line that appears
// before any header, or any header line without ":", is
// Err("eml: malformed header line: <line>").
//
// v0.61.3 notes that shaped this module:
//   * Free functions only; all scanning is byte-wise over the input Str.
//   * Output bytes are collected in a Vec[UInt8] and materialized with
//     xiom.string.builder.sb_to_str.
//   * Ok/Err for Result[Email, Str] are constructed only in the tiny leaf
//     helpers _ok_email/_err_email (constructing Results directly inside
//     other functions miscompiles in this compiler).
//   * Str equality goes through xiom.string.compare.str_compare (BUG 17:
//     `==` on Str values read from Vec[Str] elements lowers to a pointer
//     comparison).

module xiom.eml

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(e) for Result[Email, Str].
fn _ok_email(e: Email) -> Result[Email, Str] {
  return Ok(e);
}

// Err(m) for Result[Email, Str].
fn _err_email(m: Str) -> Result[Email, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Byte constants
// --------------------------------------------------

const _EML_TAB: UInt8 = 9u8;
const _EML_LF: UInt8 = 10u8;
const _EML_CR: UInt8 = 13u8;
const _EML_SPACE: UInt8 = 32u8;
const _EML_DQUOTE: UInt8 = 34u8;
const _EML_DASH: UInt8 = 45u8;
const _EML_COLON: UInt8 = 58u8;
const _EML_SEMI: UInt8 = 59u8;
const _EML_EQ: UInt8 = 61u8;

// --------------------------------------------------
//  Data model
// --------------------------------------------------

/// A parsed message: `names` and `values` are index-aligned header fields
/// (names lowercased, values unfolded, duplicates kept in order); `body` is
/// the verbatim text after the first blank line (empty when the message has
/// no blank line).
pub type Email = {
  names: Vec[Str];
  values: Vec[Str];
  body: Str;
}

// --------------------------------------------------
//  Byte helpers
// --------------------------------------------------

// True for an ASCII space or horizontal tab.
fn _is_ws(b: UInt8) -> Bool {
  return b == _EML_SPACE || b == _EML_TAB;
}

// Left-strip spaces and tabs.
fn _lstrip_ws(s: Str) -> Str {
  var i = 0;
  while i < s.len() && _is_ws(string.byte_at(s, i)) {
    i = i + 1;
  }
  if i == 0 {
    return s;
  }
  return string.str_slice(s, i, s.len());
}

// Right-strip spaces and tabs.
fn _rstrip_ws(s: Str) -> Str {
  var n = s.len();
  while n > 0 && _is_ws(string.byte_at(s, n - 1)) {
    n = n - 1;
  }
  if n == s.len() {
    return s;
  }
  return string.str_slice(s, 0, n);
}

// The ASCII lowercase of byte `c` widened to 0..255 (non-letters unchanged).
fn _lower_byte(c: Int) -> Int {
  if c >= 65 && c <= 90 {
    return c + 32;
  }
  return c;
}

// True when `s` starts with the byte sequence `w` at byte index `at`,
// comparing ASCII letters case-insensitively (used for MIME parameter names).
fn _match_word_ci(s: Str, at: Int, w: Str) -> Bool {
  if at + w.len() > s.len() {
    return false;
  }
  var i = 0;
  while i < w.len() {
    let a = (string.byte_at(s, at + i) as Int) & 0xFF;
    let b = (string.byte_at(w, i) as Int) & 0xFF;
    if _lower_byte(a) != _lower_byte(b) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// ASCII-lowercase every byte of `s` (field and parameter names are ASCII;
// other bytes pass through, so the byte length is preserved).
fn _lower_ascii(s: Str) -> Str {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < s.len() {
    let c = (string.byte_at(s, i) as Int) & 0xFF;
    out.push(_lower_byte(c) as UInt8);
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}

// Index of the first ":" in `line`, or -1.
fn _find_colon(line: Str) -> Int {
  var i = 0;
  while i < line.len() {
    if string.byte_at(line, i) == _EML_COLON {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Index of the first header whose lowercased name equals `lname`, or -1.
// Str comparisons go through str_compare (BUG 17: `==` on Vec[Str] elements
// lowers to a pointer comparison).
fn _header_index(e: &Email, lname: Str) -> Int {
  var i = 0;
  while i < e.names.len() {
    let k: Str = e.names[i];
    if compare.str_compare(k, lname) == 0 {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// True when body[from, to) is a boundary delimiter line: exactly
// "--" + boundary for an opening delimiter, plus "--" for the closing one
// (the line terminators were already removed by the caller).
fn _is_delim(body: Str, from: Int, to: Int, boundary: Str, closing: Bool) -> Bool {
  let blen = boundary.len();
  var want = blen + 2;
  if closing {
    want = blen + 4;
  }
  if to - from != want {
    return false;
  }
  if string.byte_at(body, from) != _EML_DASH || string.byte_at(body, from + 1) != _EML_DASH {
    return false;
  }
  var i = 0;
  while i < blen {
    if string.byte_at(body, from + 2 + i) != string.byte_at(boundary, i) {
      return false;
    }
    i = i + 1;
  }
  if closing {
    if string.byte_at(body, from + 2 + blen) != _EML_DASH || string.byte_at(body, from + 2 + blen + 1) != _EML_DASH {
      return false;
    }
  }
  return true;
}

// --------------------------------------------------
//  Parsing helpers
// --------------------------------------------------

// Fold one physical header line into `e`.
// A line starting with space/tab is a continuation: its fold whitespace is
// stripped and it is joined to the previous value with a single space. Any
// other line must contain ":"; the name is lowercased and the value is
// stripped of surrounding spaces/tabs.
// Returns "" on success, or the "eml: ..." message on failure.
fn _consume_header_line(e: &mut Email, line: Str) -> Str {
  if line.len() > 0 && _is_ws(string.byte_at(line, 0)) {
    if e.values.len() == 0 {
      return "eml: malformed header line: " + line;
    }
    let last = e.values.len() - 1;
    let prev: Str = e.values[last];
    e.values[last] = _rstrip_ws(prev + " " + _lstrip_ws(line));
    return "";
  }
  let colon = _find_colon(line);
  if colon < 0 {
    return "eml: malformed header line: " + line;
  }
  let name = _lower_ascii(string.str_slice(line, 0, colon));
  let value = _rstrip_ws(_lstrip_ws(string.str_slice(line, colon + 1, line.len())));
  e.names.push(name);
  e.values.push(value);
  return "";
}

// Extract the value of the `boundary` parameter from a Content-Type header
// value (attribute scanning, case-insensitive name). A quoted value loses
// its quotes; a bare value runs to the next ";" or whitespace byte. None
// when no boundary parameter is present.
fn _boundary_of(ct: Str) -> Option[Str] {
  let n = ct.len();
  var i = 0;
  while i < n {
    while i < n && (_is_ws(string.byte_at(ct, i)) || string.byte_at(ct, i) == _EML_SEMI) {
      i = i + 1;
    }
    let name_start = i;
    while i < n {
      let b = string.byte_at(ct, i);
      if b == _EML_EQ || b == _EML_SEMI || _is_ws(b) {
        break;
      }
      i = i + 1;
    }
    let name_end = i;
    var j = i;
    while j < n && _is_ws(string.byte_at(ct, j)) {
      j = j + 1;
    }
    if j < n && string.byte_at(ct, j) == _EML_EQ && name_end - name_start == 8 && _match_word_ci(ct, name_start, "boundary") {
      j = j + 1;
      while j < n && _is_ws(string.byte_at(ct, j)) {
        j = j + 1;
      }
      if j < n && string.byte_at(ct, j) == _EML_DQUOTE {
        var k = j + 1;
        while k < n && string.byte_at(ct, k) != _EML_DQUOTE {
          k = k + 1;
        }
        return Some(string.str_slice(ct, j + 1, k));
      }
      var k = j;
      while k < n && string.byte_at(ct, k) != _EML_SEMI && !_is_ws(string.byte_at(ct, k)) {
        k = k + 1;
      }
      return Some(string.str_slice(ct, j, k));
    }
    while i < n && string.byte_at(ct, i) != _EML_SEMI {
      i = i + 1;
    }
    if i < n {
      i = i + 1;
    }
  }
  return None;
}

// --------------------------------------------------
//  Public API
// --------------------------------------------------

/// Parse one in-memory RFC 5322/MIME message.
/// Params: text - the whole message (LF, CRLF or lone CR line endings).
/// Returns: Ok(Email) for any message whose header block parses; Err with an
/// "eml: ..." message on a malformed header line (no ":") or on a folded
/// continuation line that appears before any header. Header names are
/// lowercased; folded continuations are unfolded with a single space;
/// duplicate headers are preserved in order; the body is kept verbatim.
/// A message with no blank line has an empty body. An empty message parses
/// as an email with no headers and an empty body.
/// Complexity: O(total input length).
pub fn eml_parse(text: Str) -> Result[Email, Str] {
  var e = Email{ names: Vec[Str].new(); values: Vec[Str].new(); body: ""; };
  let n = text.len();
  var line_start = 0;
  var i = 0;
  while i <= n {
    if i == n || string.byte_at(text, i) == _EML_LF || string.byte_at(text, i) == _EML_CR {
      let le = i;
      var after = i;
      if i < n {
        if string.byte_at(text, i) == _EML_CR && i + 1 < n && string.byte_at(text, i + 1) == _EML_LF {
          after = i + 2;
        } else {
          after = i + 1;
        }
      }
      if le == line_start {
        // First blank line: the rest of the message is the body, verbatim.
        e.body = string.str_slice(text, after, n);
        return _ok_email(e);
      }
      let line = string.str_slice(text, line_start, le);
      let err = _consume_header_line(&mut e, line);
      if err.len() > 0 {
        return _err_email(err);
      }
      if i == n {
        break;
      }
      line_start = after;
      i = after;
    } else {
      i = i + 1;
    }
  }
  // No blank line: the whole message is headers, so the body is empty.
  e.body = "";
  return _ok_email(e);
}

/// First value of the header `name`; None when the header is absent. The
/// lookup is case-insensitive: both the stored names and `name` are
/// lowercased before comparing.
pub fn eml_header(e: &Email, name: Str) -> Option[Str] {
  let lname = _lower_ascii(name);
  let i = _header_index(e, lname);
  if i < 0 {
    return None;
  }
  let v: Str = e.values[i];
  return Some(v);
}

/// Every value of the header `name`, in document order (a fresh copy); an
/// empty vector when the header is absent. Case-insensitive, like
/// `eml_header`.
pub fn eml_headers_all(e: &Email, name: Str) -> Vec[Str] {
  let lname = _lower_ascii(name);
  var out = Vec[Str].new();
  var i = 0;
  while i < e.names.len() {
    let k: Str = e.names[i];
    if compare.str_compare(k, lname) == 0 {
      let v: Str = e.values[i];
      out.push(v);
    }
    i = i + 1;
  }
  return out;
}

/// Number of header fields (duplicates counted).
pub fn eml_header_count(e: &Email) -> Int {
  return e.names.len();
}

/// True when the first Content-Type header starts with "multipart/"
/// (case-insensitive).
pub fn eml_is_multipart(e: &Email) -> Bool {
  let ct = eml_header(e, "content-type");
  match ct {
    Some(v) => {
      let lv: Str = _lower_ascii(v);
      return string.str_starts_with(lv, "multipart/");
    },
    None => { return false; },
  }
  return false;
}

/// Value of the `boundary` parameter of the first Content-Type header
/// (`boundary="quoted"` or `boundary=bare`); None when there is no
/// Content-Type header or no boundary parameter. A quoted value loses its
/// quotes; an empty boundary is returned as Some("").
pub fn eml_content_type_boundary(e: &Email) -> Option[Str] {
  let ct = eml_header(e, "content-type");
  match ct {
    Some(v) => { return _boundary_of(v); },
    None => { return None; },
  }
  return None;
}

/// Split a multipart body on lines equal to "--" + `boundary`.
/// Params: e - the parsed message (its body is scanned); boundary - the
/// delimiter value, e.g. from `eml_content_type_boundary`.
/// Returns: the raw part payloads in order. The preamble before the first
/// delimiter and the epilogue after the closing delimiter
/// "--" + `boundary` + "--" are ignored, as is the closing delimiter itself;
/// the line terminator immediately preceding a delimiter belongs to the
/// delimiter and is not part of the preceding part. An empty boundary yields
/// an empty vector; a body that never opens a delimiter also yields one.
/// Complexity: O(body length).
pub fn eml_split_parts(e: &Email, boundary: Str) -> Vec[Str] {
  var parts = Vec[Str].new();
  if boundary.len() == 0 {
    return parts;
  }
  let body: Str = e.body;
  let n = body.len();
  var line_start = 0;
  var term_start = 0;
  var open = -1;
  var i = 0;
  while i <= n {
    if i == n || string.byte_at(body, i) == _EML_LF || string.byte_at(body, i) == _EML_CR {
      let le = i;
      var after = i;
      if i < n {
        if string.byte_at(body, i) == _EML_CR && i + 1 < n && string.byte_at(body, i + 1) == _EML_LF {
          after = i + 2;
        } else {
          after = i + 1;
        }
      }
      if _is_delim(body, line_start, le, boundary, true) {
        if open >= 0 {
          var part_end = term_start;
          if part_end < open {
            part_end = open;
          }
          parts.push(string.str_slice(body, open, part_end));
        }
        // The closing delimiter ends the multipart body: drop the epilogue.
        return parts;
      }
      if _is_delim(body, line_start, le, boundary, false) {
        if open >= 0 {
          var part_end = term_start;
          if part_end < open {
            part_end = open;
          }
          parts.push(string.str_slice(body, open, part_end));
        }
        open = after;
      }
      if i == n {
        break;
      }
      term_start = i;
      line_start = after;
      i = after;
    } else {
      i = i + 1;
    }
  }
  if open >= 0 {
    // No closing delimiter: the final part runs to the end of the body.
    parts.push(string.str_slice(body, open, n));
  }
  return parts;
}
