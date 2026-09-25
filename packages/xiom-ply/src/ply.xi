// XIOM -- xiom.ply: ASCII PLY header/body codec with canonical re-emission
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Supported subset (pinned in SPEC.md, exercised by tests/test_conformance.xi):
//
// - Header: `ply`, `format ascii 1.0`, `comment ...`, `element <name>
//   <count>`, `property <type> <name>` for the eight scalar PLY types (char,
//   uchar, short, ushort, int, uint, float, double) and `end_header`.
//   `property list` is not supported: it fails as an unknown property type.
// - Body: rows are consumed element by element in declaration order, and a
//   row must carry exactly one whitespace-separated token per declared
//   property. Declared and actual element counts must agree, and no line may
//   follow the last declared row.
// - Scalar values are validated per declared type and kept as their original
//   text tokens. Integer tokens (char, uchar, short, ushort, int, uint) are
//   range-checked; float and double tokens are syntax-checked only -- this
//   compiler has no Vec[Float64] and this module never converts a float.
//
// v0.61.3 notes that shaped this module: free functions only (no self
// methods, no lambdas, no Vec[StructType], no Vec[fn]); PlyDoc is a struct
// of flat parallel Vecs; Ok/Err are constructed only in the _ply_ok_* and
// _ply_err_* leaf helpers; Str comparisons go through
// xiom.string.compare.str_compare (BUG 17: `==` on Str values read from
// Vec[Str] elements lowers to a pointer comparison); bytes widen with
// (string.byte_at(s, i) as Int) & 0xFF; every Vec element read is bound with
// an explicit type; output is built with xiom.string.builder.

module xiom.ply

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;
use xiom.convert;

// --------------------------------------------------
//  Constants
// --------------------------------------------------

const _PLY_TAB: Int = 9;
const _PLY_LF: Int = 10;
const _PLY_CR: Int = 13;
const _PLY_SPACE: Int = 32;
const _PLY_PLUS: Int = 43;
const _PLY_MINUS: Int = 45;
const _PLY_DOT: Int = 46;
const _PLY_DIGIT0: Int = 48;
const _PLY_DIGIT9: Int = 57;
const _PLY_E_UPPER: Int = 69;
const _PLY_E_LOWER: Int = 101;

// Scalar type codes; 0 means "no such type".
const _PLY_T_CHAR: Int = 1;
const _PLY_T_UCHAR: Int = 2;
const _PLY_T_SHORT: Int = 3;
const _PLY_T_USHORT: Int = 4;
const _PLY_T_INT: Int = 5;
const _PLY_T_UINT: Int = 6;
const _PLY_T_FLOAT: Int = 7;
const _PLY_T_DOUBLE: Int = 8;

// Integer scanner sentinels. A successful scan returns a non-negative
// magnitude, so the negative values are unambiguous.
const _PLY_SCAN_BAD: Int = -1;
const _PLY_SCAN_OVERFLOW: Int = -2;
// Int64 maximum / 10: the pre-multiply overflow guard.
const _PLY_SCAN_LIMIT: Int = 922337203685477580;
const _PLY_INT_MAX: Int = 9223372036854775807;

// --------------------------------------------------
//  Data model
// --------------------------------------------------

/// A parsed ASCII PLY document. Elements are index-aligned across elem_names,
/// elem_counts, elem_prop_starts and elem_prop_ends; property p belongs to
/// the element whose half-open range [elem_prop_starts[e], elem_prop_ends[e])
/// contains it. Body values are a flat token stream in source order: because
/// every scalar row has one token per property, the tokens of element e are
/// the elem_counts[e] * property_count(e) consecutive entries starting at the
/// token offset of the element.
pub type PlyDoc = {
  elem_names: Vec[Str];
  elem_counts: Vec[Int];
  elem_prop_starts: Vec[Int];
  elem_prop_ends: Vec[Int];
  prop_types: Vec[Int];
  prop_names: Vec[Str];
  comments: Vec[Str];
  tokens: Vec[Str];
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(d) for Result[PlyDoc, Str].
fn _ply_ok_doc(d: PlyDoc) -> Result[PlyDoc, Str] {
  return Ok(d);
}

// Err(m) for Result[PlyDoc, Str].
fn _ply_err_doc(m: Str) -> Result[PlyDoc, Str] {
  return Err(m);
}

// Ok(v) for Result[Str, Str].
fn _ply_ok_str(v: Str) -> Result[Str, Str] {
  return Ok(v);
}

// Err(m) for Result[Str, Str].
fn _ply_err_str(m: Str) -> Result[Str, Str] {
  return Err(m);
}

// Ok(v) for Result[Int, Str].
fn _ply_ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

// Err(m) for Result[Int, Str].
fn _ply_err_int(m: Str) -> Result[Int, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Byte, line and token helpers
// --------------------------------------------------

// A document with every vector empty.
fn _ply_new_doc() -> PlyDoc {
  return PlyDoc{
    elem_names: Vec[Str].new();
    elem_counts: Vec[Int].new();
    elem_prop_starts: Vec[Int].new();
    elem_prop_ends: Vec[Int].new();
    prop_types: Vec[Int].new();
    prop_names: Vec[Str].new();
    comments: Vec[Str].new();
    tokens: Vec[Str].new();
  };
}

// One byte of `s` at `i`, zero-extended to Int (0..255). The mask keeps the
// comparison domain Int even for bytes >= 128.
fn _ply_byte(s: Str, i: Int) -> Int {
  return (string.byte_at(s, i) as Int) & 0xFF;
}

// True for an ASCII decimal digit byte.
fn _ply_is_digit(b: Int) -> Bool {
  return b >= _PLY_DIGIT0 && b <= _PLY_DIGIT9;
}

// True for the two ASCII whitespace bytes that separate header tokens and
// body values (space and TAB).
fn _ply_is_ws(b: Int) -> Bool {
  return b == _PLY_SPACE || b == _PLY_TAB;
}

// Byte index of the LF ending the line starting at `start`, or text.len().
fn _ply_line_end(text: Str, start: Int) -> Int {
  let n = text.len();
  var i = start;
  while i < n {
    if _ply_byte(text, i) == _PLY_LF {
      break;
    }
    i = i + 1;
  }
  return i;
}

// End of the line content: the LF index with one immediately preceding CR
// dropped (CRLF support).
fn _ply_content_end(text: Str, start: Int) -> Int {
  let e = _ply_line_end(text, start);
  if e > start && _ply_byte(text, e - 1) == _PLY_CR {
    return e - 1;
  }
  return e;
}

// Number of LF bytes in text[0, before); used to recover the 1-based line
// number of a byte offset.
fn _ply_count_lf(text: Str, before: Int) -> Int {
  var i = 0;
  var c = 0;
  while i < before {
    if _ply_byte(text, i) == _PLY_LF {
      c = c + 1;
    }
    i = i + 1;
  }
  return c;
}

// Split text[start, end) on runs of space/TAB into tokens. Every other byte
// is token data; an empty range yields no tokens.
fn _ply_tokens(text: Str, start: Int, end: Int) -> Vec[Str] {
  var out = Vec[Str].new();
  var i = start;
  while i < end {
    let b = _ply_byte(text, i);
    if _ply_is_ws(b) {
      i = i + 1;
    } else {
      var j = i;
      while j < end {
        let c = _ply_byte(text, j);
        if _ply_is_ws(c) {
          break;
        }
        j = j + 1;
      }
      out.push(string.str_slice(text, i, j));
      i = j;
    }
  }
  return out;
}

// text[start, end) without leading or trailing space/TAB.
fn _ply_trim(text: Str, start: Int, end: Int) -> Str {
  var s = start;
  var e = end;
  while s < e && _ply_is_ws(_ply_byte(text, s)) {
    s = s + 1;
  }
  while e > s && _ply_is_ws(_ply_byte(text, e - 1)) {
    e = e - 1;
  }
  return string.str_slice(text, s, e);
}

// --------------------------------------------------
//  Scalar type table
// --------------------------------------------------

/// Canonical name of scalar type code `code` (1..8), or "" when `code` is
/// not a PLY scalar type.
/// Params: code - a type code, 0 for unknown.
/// Returns: "char", "uchar", "short", "ushort", "int", "uint", "float" or
/// "double"; "" otherwise. Complexity: O(1).
pub fn ply_type_name(code: Int) -> Str {
  if code == _PLY_T_CHAR { return "char"; }
  if code == _PLY_T_UCHAR { return "uchar"; }
  if code == _PLY_T_SHORT { return "short"; }
  if code == _PLY_T_USHORT { return "ushort"; }
  if code == _PLY_T_INT { return "int"; }
  if code == _PLY_T_UINT { return "uint"; }
  if code == _PLY_T_FLOAT { return "float"; }
  if code == _PLY_T_DOUBLE { return "double"; }
  return "";
}

/// Type code of the canonical scalar name `name`, or 0 when the name is not
/// one of the eight PLY scalar types. Case-sensitive.
/// Params: name - a candidate type name.
/// Returns: 1..8, or 0. Complexity: O(1) (at most eight str_compares).
pub fn ply_type_code(name: Str) -> Int {
  if compare.str_compare(name, "char") == 0 { return _PLY_T_CHAR; }
  if compare.str_compare(name, "uchar") == 0 { return _PLY_T_UCHAR; }
  if compare.str_compare(name, "short") == 0 { return _PLY_T_SHORT; }
  if compare.str_compare(name, "ushort") == 0 { return _PLY_T_USHORT; }
  if compare.str_compare(name, "int") == 0 { return _PLY_T_INT; }
  if compare.str_compare(name, "uint") == 0 { return _PLY_T_UINT; }
  if compare.str_compare(name, "float") == 0 { return _PLY_T_FLOAT; }
  if compare.str_compare(name, "double") == 0 { return _PLY_T_DOUBLE; }
  return 0;
}

/// True when `code` is one of the six integer scalar types (char, uchar,
/// short, ushort, int, uint), whose values are range-checked at parse time.
/// Params: code - a type code.
/// Returns: true for 1..6, false otherwise. Complexity: O(1).
pub fn ply_type_is_integer(code: Int) -> Bool {
  return code >= _PLY_T_CHAR && code <= _PLY_T_UINT;
}

// Minimum representable value of integer type `code` (unused for float).
fn _ply_type_min(code: Int) -> Int {
  if code == _PLY_T_CHAR { return -128; }
  if code == _PLY_T_SHORT { return -32768; }
  if code == _PLY_T_INT { return -2147483648; }
  return 0;
}

// Maximum representable value of integer type `code` (unused for float).
fn _ply_type_max(code: Int) -> Int {
  if code == _PLY_T_CHAR { return 127; }
  if code == _PLY_T_UCHAR { return 255; }
  if code == _PLY_T_SHORT { return 32767; }
  if code == _PLY_T_USHORT { return 65535; }
  if code == _PLY_T_INT { return 2147483647; }
  if code == _PLY_T_UINT { return 4294967295; }
  return 0;
}

// --------------------------------------------------
//  Scalar token validation
// --------------------------------------------------

// Scan one integer token: an optional "+"/"-" sign followed by 1..19 ASCII
// digits. Returns the non-negative magnitude, _PLY_SCAN_BAD for a syntax
// error, or _PLY_SCAN_OVERFLOW when the magnitude exceeds Int64. Leading
// zeros are skipped before the digit count (they cannot overflow), and a
// leading "+" is accepted; the sign is applied by the caller.
fn _ply_scan_mag(tok: Str) -> Int {
  let n = tok.len();
  if n == 0 { return _PLY_SCAN_BAD; }
  var i = 0;
  let b0 = _ply_byte(tok, 0);
  if b0 == _PLY_PLUS || b0 == _PLY_MINUS { i = 1; }
  var mag = 0;
  var sig = 0;
  var saw = 0;
  while i < n {
    let b = _ply_byte(tok, i);
    if !_ply_is_digit(b) { return _PLY_SCAN_BAD; }
    saw = saw + 1;
    if mag == 0 && b == _PLY_DIGIT0 {
      i = i + 1;
    } else {
      sig = sig + 1;
      if sig > 19 { return _PLY_SCAN_OVERFLOW; }
      if mag > _PLY_SCAN_LIMIT { return _PLY_SCAN_OVERFLOW; }
      if mag == _PLY_SCAN_LIMIT && (b - _PLY_DIGIT0) > 7 { return _PLY_SCAN_OVERFLOW; }
      mag = mag * 10 + (b - _PLY_DIGIT0);
      i = i + 1;
    }
  }
  if saw == 0 { return _PLY_SCAN_BAD; }
  return mag;
}

// True when the token starts with "-" (its magnitude ignores the sign).
fn _ply_token_neg(tok: Str) -> Bool {
  if tok.len() == 0 { return false; }
  if _ply_byte(tok, 0) == _PLY_MINUS { return true; }
  return false;
}

// Float/double token grammar: sign? ( digits ("." digits?)? | "." digits )
// ( ("e"|"E") sign? digits )? -- at least one mantissa digit. "nan", "inf",
// hex floats and a bare "." are rejected.
fn _ply_is_float_token(tok: Str) -> Bool {
  let n = tok.len();
  if n == 0 { return false; }
  var i = 0;
  let b0 = _ply_byte(tok, 0);
  if b0 == _PLY_PLUS || b0 == _PLY_MINUS { i = 1; }
  var mant = 0;
  while i < n && _ply_is_digit(_ply_byte(tok, i)) {
    mant = mant + 1;
    i = i + 1;
  }
  if i < n && _ply_byte(tok, i) == _PLY_DOT {
    i = i + 1;
    while i < n && _ply_is_digit(_ply_byte(tok, i)) {
      mant = mant + 1;
      i = i + 1;
    }
  }
  if mant == 0 { return false; }
  if i < n {
    let e = _ply_byte(tok, i);
    if e != _PLY_E_LOWER && e != _PLY_E_UPPER { return false; }
    i = i + 1;
    if i < n {
      let s = _ply_byte(tok, i);
      if s == _PLY_PLUS || s == _PLY_MINUS { i = i + 1; }
    }
    let dstart = i;
    while i < n && _ply_is_digit(_ply_byte(tok, i)) {
      i = i + 1;
    }
    if i == dstart { return false; }
  }
  return i == n;
}

// Validation status of one scalar token against declared type `type_code`:
// 0 = valid, 1 = malformed value, 2 = integer out of range.
fn _ply_value_status(tok: Str, type_code: Int) -> Int {
  if ply_type_is_integer(type_code) {
    let mag = _ply_scan_mag(tok);
    if mag == _PLY_SCAN_BAD { return 1; }
    if mag == _PLY_SCAN_OVERFLOW { return 2; }
    var v = mag;
    if _ply_token_neg(tok) { v = 0 - mag; }
    if v < _ply_type_min(type_code) { return 2; }
    if v > _ply_type_max(type_code) { return 2; }
    return 0;
  }
  if type_code == _PLY_T_FLOAT || type_code == _PLY_T_DOUBLE {
    if _ply_is_float_token(tok) { return 0; }
    return 1;
  }
  return 1;
}

// --------------------------------------------------
//  Header parsing
// --------------------------------------------------

// Parse the header (magic through end_header) into `doc` and return the byte
// offset where the body starts. Errors are the header entries of the error
// catalog in SPEC.md section 7.
fn _ply_header(text: Str, doc: &mut PlyDoc) -> Result[Int, Str] {
  let n = text.len();
  var pos = 0;
  var end = 0;
  // Line 1: magic.
  if pos >= n { return _ply_err_int("ply: missing magic"); }
  end = _ply_content_end(text, pos);
  let magic = _ply_tokens(text, pos, end);
  if magic.len() != 1 { return _ply_err_int("ply: missing magic"); }
  let m0: Str = magic[0];
  if compare.str_compare(m0, "ply") != 0 { return _ply_err_int("ply: missing magic"); }
  pos = _ply_line_end(text, pos) + 1;
  // Line 2: format line, exactly `format ascii 1.0`.
  if pos >= n { return _ply_err_int("ply: unsupported format line"); }
  end = _ply_content_end(text, pos);
  let fmt = _ply_tokens(text, pos, end);
  if fmt.len() != 3 { return _ply_err_int("ply: unsupported format line"); }
  let f0: Str = fmt[0];
  let f1: Str = fmt[1];
  let f2: Str = fmt[2];
  if compare.str_compare(f0, "format") != 0 { return _ply_err_int("ply: unsupported format line"); }
  if compare.str_compare(f1, "ascii") != 0 { return _ply_err_int("ply: unsupported format line"); }
  if compare.str_compare(f2, "1.0") != 0 { return _ply_err_int("ply: unsupported format line"); }
  pos = _ply_line_end(text, pos) + 1;
  // Header records until end_header.
  var line_no = 2;
  while pos < n {
    line_no = line_no + 1;
    end = _ply_content_end(text, pos);
    let toks = _ply_tokens(text, pos, end);
    if toks.len() == 0 {
      return _ply_err_int("ply: unknown header record at line " + int_to_string(line_no));
    }
    let kw: Str = toks[0];
    if compare.str_compare(kw, "comment") == 0 {
      var k = pos;
      while k < end && _ply_is_ws(_ply_byte(text, k)) {
        k = k + 1;
      }
      k = k + 7;
      doc.comments.push(_ply_trim(text, k, end));
    } elif compare.str_compare(kw, "element") == 0 {
      if toks.len() != 3 {
        return _ply_err_int("ply: malformed element at line " + int_to_string(line_no));
      }
      let name: Str = toks[1];
      let cnt: Str = toks[2];
      let c0 = _ply_byte(cnt, 0);
      if c0 == _PLY_PLUS || c0 == _PLY_MINUS {
        return _ply_err_int("ply: malformed element at line " + int_to_string(line_no));
      }
      let mag = _ply_scan_mag(cnt);
      if mag < 0 {
        return _ply_err_int("ply: malformed element at line " + int_to_string(line_no));
      }
      let at = doc.prop_names.len();
      doc.elem_names.push(name);
      doc.elem_counts.push(mag);
      doc.elem_prop_starts.push(at);
      doc.elem_prop_ends.push(at);
    } elif compare.str_compare(kw, "property") == 0 {
      if toks.len() < 2 || doc.elem_names.len() == 0 {
        return _ply_err_int("ply: malformed property at line " + int_to_string(line_no));
      }
      let tyname: Str = toks[1];
      let code = ply_type_code(tyname);
      if code == 0 {
        return _ply_err_int("ply: unknown property type at line " + int_to_string(line_no));
      }
      if toks.len() != 3 {
        return _ply_err_int("ply: malformed property at line " + int_to_string(line_no));
      }
      let pname: Str = toks[2];
      doc.prop_types.push(code);
      doc.prop_names.push(pname);
      let last = doc.elem_prop_ends.len() - 1;
      let nn = doc.prop_names.len();
      doc.elem_prop_ends[last] = nn;
    } elif compare.str_compare(kw, "end_header") == 0 {
      if toks.len() != 1 {
        return _ply_err_int("ply: unknown header record at line " + int_to_string(line_no));
      }
      return _ply_ok_int(_ply_line_end(text, pos) + 1);
    } else {
      return _ply_err_int("ply: unknown header record at line " + int_to_string(line_no));
    }
    pos = _ply_line_end(text, pos) + 1;
  }
  return _ply_err_int("ply: missing end_header");
}

// --------------------------------------------------
//  Body parsing
// --------------------------------------------------

// Property-range start of element `e` (caller guarantees `e` is in range).
fn _ply_prop_start(doc: &PlyDoc, e: Int) -> Int {
  let v: Int = doc.elem_prop_starts[e];
  return v;
}

// Property count of element `e` (caller guarantees `e` is in range).
fn _ply_prop_count(doc: &PlyDoc, e: Int) -> Int {
  let s: Int = doc.elem_prop_starts[e];
  let t: Int = doc.elem_prop_ends[e];
  return t - s;
}

// Read the body rows into `doc`. Returns "" on success or the error message;
// rows are consumed element by element in declaration order and must match
// each element's property count exactly.
fn _ply_body(text: Str, start: Int, doc: &mut PlyDoc) -> Str {
  let n = text.len();
  var pos = start;
  var line_no = _ply_count_lf(text, start);
  var e = 0;
  let ne = doc.elem_names.len();
  while e < ne {
    let pcount = _ply_prop_count(doc, e);
    let rows: Int = doc.elem_counts[e];
    var r = 0;
    while r < rows {
      if pos >= n {
        return "ply: element count mismatch";
      }
      line_no = line_no + 1;
      let end = _ply_content_end(text, pos);
      let toks = _ply_tokens(text, pos, end);
      if toks.len() != pcount {
        return "ply: row token-count mismatch at line " + int_to_string(line_no);
      }
      var j = 0;
      while j < pcount {
        let tok: Str = toks[j];
        let p = _ply_prop_start(doc, e) + j;
        let ty: Int = doc.prop_types[p];
        let st = _ply_value_status(tok, ty);
        if st == 1 {
          return "ply: malformed value at line " + int_to_string(line_no);
        }
        if st == 2 {
          return "ply: bad integer range at line " + int_to_string(line_no);
        }
        doc.tokens.push(tok);
        j = j + 1;
      }
      pos = _ply_line_end(text, pos) + 1;
      r = r + 1;
    }
    e = e + 1;
  }
  if pos < n {
    return "ply: trailing rows at line " + int_to_string(line_no + 1);
  }
  return "";
}

// --------------------------------------------------
//  Public parsing API
// --------------------------------------------------

/// Parse a complete ASCII PLY document (header and body).
/// Params: text - the PLY text, treated as a byte buffer.
/// Returns: Ok(PlyDoc) holding the declared elements and properties plus the
/// body values as their original text tokens, in source order.
/// Error case: the first structural or value error stops the parse; see
/// SPEC.md section 7 (for example Err("ply: missing magic"), Err("ply:
/// unknown property type at line N"), Err("ply: row token-count mismatch at
/// line N"), Err("ply: trailing rows at line N")). Line numbers are 1-based
/// and count physical lines.
/// Complexity: O(text bytes).
pub fn ply_parse(text: Str) -> Result[PlyDoc, Str] {
  var doc = _ply_new_doc();
  let h = _ply_header(text, &mut doc);
  match h {
    Ok(body_at) => {
      let err = _ply_body(text, body_at, &mut doc);
      if err.len() > 0 {
        return _ply_err_doc(err);
      }
      return _ply_ok_doc(doc);
    },
    Err(e) => {
      return _ply_err_doc(e);
    },
  }
  return _ply_err_doc("ply: malformed document");
}

// --------------------------------------------------
//  Structural accessors
// --------------------------------------------------

/// Number of elements declared in `doc`.
/// Params: doc - the document, read only.
/// Returns: elem_names.len(); 0 for an empty document. Complexity: O(1).
pub fn ply_element_count(doc: &PlyDoc) -> Int {
  return doc.elem_names.len();
}

/// Name of element `e` (`"vertex"`, `"face"`, ...).
/// Params: doc - the document, read only; e - zero-based element index.
/// Returns: the name; "" when `e` is out of range. Complexity: O(1).
pub fn ply_element_name(doc: &PlyDoc, e: Int) -> Str {
  if e < 0 || e >= doc.elem_names.len() {
    return "";
  }
  let v: Str = doc.elem_names[e];
  return v;
}

/// Declared row count of element `e`. Parsing guarantees that exactly this
/// many rows were accepted from the body.
/// Params: doc - the document, read only; e - zero-based element index.
/// Returns: the count; 0 when `e` is out of range. Complexity: O(1).
pub fn ply_element_rows(doc: &PlyDoc, e: Int) -> Int {
  if e < 0 || e >= doc.elem_counts.len() {
    return 0;
  }
  let v: Int = doc.elem_counts[e];
  return v;
}

/// Number of properties declared for element `e`.
/// Params: doc - the document, read only; e - zero-based element index.
/// Returns: the property count; 0 when `e` is out of range. Complexity: O(1).
pub fn ply_element_property_count(doc: &PlyDoc, e: Int) -> Int {
  if e < 0 || e >= doc.elem_prop_starts.len() {
    return 0;
  }
  if e >= doc.elem_prop_ends.len() {
    return 0;
  }
  let s: Int = doc.elem_prop_starts[e];
  let t: Int = doc.elem_prop_ends[e];
  if s < 0 || t < s {
    return 0;
  }
  return t - s;
}

/// Global property index of slot `j` (0-based) inside element `e`.
/// Params: doc - the document, read only; e - zero-based element index; j -
/// zero-based property slot.
/// Returns: the index used by ply_property_name/ply_property_type; -1 when
/// `e` or `j` is out of range. Complexity: O(1).
pub fn ply_element_property(doc: &PlyDoc, e: Int, j: Int) -> Int {
  let pc = ply_element_property_count(doc, e);
  if j < 0 || j >= pc {
    return -1;
  }
  return _ply_prop_start(doc, e) + j;
}

/// Name of property `p` (a global property index).
/// Params: doc - the document, read only; p - global property index.
/// Returns: the name; "" when `p` is out of range. Complexity: O(1).
pub fn ply_property_name(doc: &PlyDoc, p: Int) -> Str {
  if p < 0 || p >= doc.prop_names.len() {
    return "";
  }
  let v: Str = doc.prop_names[p];
  return v;
}

/// Scalar type code of property `p` (1..8, see ply_type_name).
/// Params: doc - the document, read only; p - global property index.
/// Returns: the code; 0 when `p` is out of range. Complexity: O(1).
pub fn ply_property_type(doc: &PlyDoc, p: Int) -> Int {
  if p < 0 || p >= doc.prop_types.len() {
    return 0;
  }
  let v: Int = doc.prop_types[p];
  return v;
}

/// Element that owns property `p`.
/// Params: doc - the document, read only; p - global property index.
/// Returns: the zero-based element index; -1 when `p` is out of range or
/// owned by no element. Complexity: O(elements).
pub fn ply_property_element(doc: &PlyDoc, p: Int) -> Int {
  if p < 0 || p >= doc.prop_types.len() {
    return -1;
  }
  var e = 0;
  while e < doc.elem_names.len() {
    let count = ply_element_property_count(doc, e);
    if count > 0 {
      let first = ply_element_property(doc, e, 0);
      if p >= first && p < first + count {
        return e;
      }
    }
    e = e + 1;
  }
  return -1;
}

/// Global index of the first property named `name` in element `e`, or -1.
/// Params: doc - the document, read only; e - zero-based element index;
/// name - the exact, case-sensitive property name.
/// Returns: the global property index; -1 when `e` is out of range or the
/// element has no such property. Complexity: O(properties of e).
pub fn ply_property_index(doc: &PlyDoc, e: Int, name: Str) -> Int {
  let pc = ply_element_property_count(doc, e);
  var j = 0;
  while j < pc {
    let p = ply_element_property(doc, e, j);
    if p >= 0 && p < doc.prop_names.len() {
      let pname: Str = doc.prop_names[p];
      if compare.str_compare(pname, name) == 0 {
        return p;
      }
    }
    j = j + 1;
  }
  return -1;
}

/// Total number of body values kept in `doc`.
/// Params: doc - the document, read only.
/// Returns: tokens.len(). Complexity: O(1).
pub fn ply_token_count(doc: &PlyDoc) -> Int {
  return doc.tokens.len();
}

/// Number of comments preserved from the header.
/// Params: doc - the document, read only.
/// Returns: comments.len(). Complexity: O(1).
pub fn ply_comment_count(doc: &PlyDoc) -> Int {
  return doc.comments.len();
}

/// Text of comment `i` (the bytes after the `comment` keyword, trimmed).
/// Params: doc - the document, read only; i - zero-based comment index.
/// Returns: the text ("" for an empty comment); "" when `i` is out of
/// range. Complexity: O(1).
pub fn ply_comment(doc: &PlyDoc, i: Int) -> Str {
  if i < 0 || i >= doc.comments.len() {
    return "";
  }
  let v: Str = doc.comments[i];
  return v;
}

/// Byte offset where element `e`'s rows start in the flat token stream.
//  Caller guarantees `e` is in range. Returns -1 when the document's
//  parallel vectors are inconsistent.
fn _ply_element_token_start(doc: &PlyDoc, e: Int) -> Int {
  var off = 0;
  var k = 0;
  while k < e {
    if k >= doc.elem_names.len() { return -1; }
    if k >= doc.elem_counts.len() { return -1; }
    if k >= doc.elem_prop_starts.len() { return -1; }
    if k >= doc.elem_prop_ends.len() { return -1; }
    let s: Int = doc.elem_prop_starts[k];
    let t: Int = doc.elem_prop_ends[k];
    let rows: Int = doc.elem_counts[k];
    if s < 0 || t < s { return -1; }
    if t > doc.prop_types.len() { return -1; }
    let pc = t - s;
    if pc > 1 {
      if rows > _PLY_INT_MAX / pc { return -1; }
    }
    off = off + rows * pc;
    k = k + 1;
  }
  return off;
}

/// Text token of value `j` in row `r` of element `e`.
/// Params: doc - the document, read only; e - zero-based element index; r -
/// zero-based row index; j - zero-based property slot.
/// Returns: the original token text; "" when any index is out of range. A
/// stored token is never empty, so "" is an unambiguous sentinel.
/// Complexity: O(elements + 1).
pub fn ply_row_value(doc: &PlyDoc, e: Int, r: Int, j: Int) -> Str {
  let pc = ply_element_property_count(doc, e);
  let rows = ply_element_rows(doc, e);
  if j < 0 || j >= pc {
    return "";
  }
  if r < 0 || r >= rows {
    return "";
  }
  let base = _ply_element_token_start(doc, e);
  if base < 0 {
    return "";
  }
  let off = base + r * pc + j;
  if off < 0 || off >= doc.tokens.len() {
    return "";
  }
  let v: Str = doc.tokens[off];
  return v;
}

/// Convert the text token of value `j` in row `r` of element `e` to Int.
/// The token was validated against its declared type at parse time, so this
/// only re-reads the decimal text; tokens of float/double properties are
/// rejected because their value is not represented as an Int.
/// Params: doc - the document, read only; e - zero-based element index; r -
/// zero-based row index; j - zero-based property slot.
/// Returns: Ok(value) for integer properties.
/// Error case: Err("ply: property out of range") when the property slot is
/// invalid; Err("ply: value out of range") when row or element is out of
/// range; Err("ply: value is not an integer") for float/double properties;
/// Err("ply: malformed value") / Err("ply: bad integer range") when the
/// stored token cannot be converted (only possible for a hand-built
/// document).
/// Complexity: O(elements + digits).
pub fn ply_value_int(doc: &PlyDoc, e: Int, r: Int, j: Int) -> Result[Int, Str] {
  let p = ply_element_property(doc, e, j);
  if p < 0 {
    return _ply_err_int("ply: property out of range");
  }
  let ty: Int = doc.prop_types[p];
  if !ply_type_is_integer(ty) {
    return _ply_err_int("ply: value is not an integer");
  }
  let tok = ply_row_value(doc, e, r, j);
  if compare.str_compare(tok, "") == 0 {
    return _ply_err_int("ply: value out of range");
  }
  let mag = _ply_scan_mag(tok);
  if mag == _PLY_SCAN_BAD {
    return _ply_err_int("ply: malformed value");
  }
  if mag == _PLY_SCAN_OVERFLOW {
    return _ply_err_int("ply: bad integer range");
  }
  if _ply_token_neg(tok) {
    return _ply_ok_int(0 - mag);
  }
  return _ply_ok_int(mag);
}

// --------------------------------------------------
//  Emission
// --------------------------------------------------

// Append `line` plus LF to the builder.
fn _ply_emit_line(sb: &mut Vec[UInt8], line: Str) {
  builder.sb_push_str(sb, line);
  builder.sb_push_byte(sb, 10 as UInt8);
}

// Append the canonical header (magic through end_header) to the builder.
// Elements are emitted in declaration order; each element's properties follow
// it; comments are emitted right after the format line, in source order.
fn _ply_emit_header(doc: &PlyDoc, sb: &mut Vec[UInt8]) {
  _ply_emit_line(sb, "ply");
  _ply_emit_line(sb, "format ascii 1.0");
  var c = 0;
  while c < doc.comments.len() {
    let text: Str = doc.comments[c];
    if compare.str_compare(text, "") == 0 {
      _ply_emit_line(sb, "comment");
    } else {
      builder.sb_push_str(sb, "comment ");
      builder.sb_push_str(sb, text);
      builder.sb_push_byte(sb, 10 as UInt8);
    }
    c = c + 1;
  }
  var e = 0;
  while e < doc.elem_names.len() {
    let name: Str = doc.elem_names[e];
    builder.sb_push_str(sb, "element ");
    builder.sb_push_str(sb, name);
    builder.sb_push_byte(sb, 32 as UInt8);
    if e < doc.elem_counts.len() {
      let count: Int = doc.elem_counts[e];
      builder.sb_push_int(sb, count);
    } else {
      builder.sb_push_str(sb, "0");
    }
    builder.sb_push_byte(sb, 10 as UInt8);
    let pc = ply_element_property_count(doc, e);
    var j = 0;
    while j < pc {
      let p = ply_element_property(doc, e, j);
      if p >= 0 && p < doc.prop_names.len() && p < doc.prop_types.len() {
        let pname: Str = doc.prop_names[p];
        let ty: Int = doc.prop_types[p];
        builder.sb_push_str(sb, "property ");
        builder.sb_push_str(sb, ply_type_name(ty));
        builder.sb_push_byte(sb, 32 as UInt8);
        builder.sb_push_str(sb, pname);
        builder.sb_push_byte(sb, 10 as UInt8);
      }
      j = j + 1;
    }
    e = e + 1;
  }
  _ply_emit_line(sb, "end_header");
}

// Total token count implied by the declared element counts, or -1 when the
// arithmetic overflows or an element's property range is inconsistent.
fn _ply_tokens_needed(doc: &PlyDoc) -> Int {
  let ne = doc.elem_names.len();
  if doc.elem_counts.len() != ne { return -1; }
  if doc.elem_prop_starts.len() != ne { return -1; }
  if doc.elem_prop_ends.len() != ne { return -1; }
  var total = 0;
  var e = 0;
  while e < ne {
    let s: Int = doc.elem_prop_starts[e];
    let t: Int = doc.elem_prop_ends[e];
    let rows: Int = doc.elem_counts[e];
    if s < 0 || t < s { return -1; }
    if t > doc.prop_types.len() { return -1; }
    if t > doc.prop_names.len() { return -1; }
    let pc = t - s;
    if pc > 0 {
      if rows > _PLY_INT_MAX / pc { return -1; }
      let add = rows * pc;
      if total > _PLY_INT_MAX - add { return -1; }
      total = total + add;
    }
    e = e + 1;
  }
  return total;
}

/// Canonical header text of `doc` (`ply` through `end_header`, LF endings).
/// Params: doc - the document, read only.
/// Returns: the header, with comments right after the format line and one
/// `element`/`property` line per declaration; it always ends in LF.
/// Error case: none (inconsistent parallel vectors are skipped defensively).
/// Complexity: O(header size).
pub fn ply_build_header(doc: &PlyDoc) -> Str {
  var sb = builder.sb_new();
  _ply_emit_header(doc, &mut sb);
  return builder.sb_to_str(&sb);
}

/// Re-emit a canonical ASCII PLY document from `doc`.
/// Params: doc - the document, read only.
/// Returns: Ok(text) with LF line endings, single spaces between tokens and
/// a trailing LF; values are the stored text tokens. For a document produced
/// by ply_parse from a canonical document, parsing the result yields an
/// equivalent document (comments are normalized to the format-line block).
/// Error case: Err("ply: element count mismatch") when the declared element
/// counts and the stored token stream disagree.
/// Complexity: O(output bytes).
pub fn ply_build(doc: &PlyDoc) -> Result[Str, Str] {
  let need = _ply_tokens_needed(doc);
  if need < 0 {
    return _ply_err_str("ply: element count mismatch");
  }
  if need != doc.tokens.len() {
    return _ply_err_str("ply: element count mismatch");
  }
  var sb = builder.sb_new();
  _ply_emit_header(doc, &mut sb);
  var e = 0;
  while e < doc.elem_names.len() {
    let pc = ply_element_property_count(doc, e);
    let rows: Int = doc.elem_counts[e];
    let base = _ply_element_token_start(doc, e);
    var r = 0;
    while r < rows {
      var j = 0;
      while j < pc {
        if j > 0 {
          builder.sb_push_byte(&mut sb, 32 as UInt8);
        }
        let off = base + r * pc + j;
        let tok: Str = doc.tokens[off];
        builder.sb_push_str(&mut sb, tok);
        j = j + 1;
      }
      builder.sb_push_byte(&mut sb, 10 as UInt8);
      r = r + 1;
    }
    e = e + 1;
  }
  return _ply_ok_str(builder.sb_to_str(&sb));
}
