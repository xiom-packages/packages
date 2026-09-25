// XIOM -- xiom.wkt: Well-Known Text (WKT) geometry codec for a documented subset
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM reader/writer for the WKT geometry subset listed in SPEC.md:
// POINT, LINESTRING, POLYGON, MULTIPOINT, MULTILINESTRING, MULTIPOLYGON and
// GEOMETRYCOLLECTION, each with an EMPTY form, nested parentheses, and
// coordinate tuples kept as validated decimal text tokens (this module never
// converts a coordinate to a number).
//
// Model:
//   * one parsed document is one root geometry plus its descendants;
//   * every geometry element is one entry in parallel flat Vecs (XIOM
//     v0.61.3 cannot hold a Vec[StructType]); direct children are listed in
//     the flat child_ids table, rings and coordinates as [start, end) spans
//     over flat per-ordinal text tables;
//   * a coordinate is four parallel text tokens (x, y, z, m); absent z/m
//     ordinates are the empty string;
//   * type keywords are matched case-insensitively and emitted in canonical
//     uppercase; Z/M/ZM ordinate markers are accepted pass-through and
//     canonically re-emitted (space-separated only; POINTZ is rejected);
//   * the canonical emitter normalizes all whitespace to single spaces and
//     its output re-parses to the same document (round trip).
//
// Language notes (XIOM v0.61.3): free functions only; all Str equality goes
// through xiom.string.compare (BUG 17: `==` on Str values read from Vec[Str]
// elements lowers to a pointer comparison); every Vec element read is bound
// to a typed local first; Ok/Err are constructed only in the leaf helpers
// (_ok_doc/_err_doc, _ok_at/_err_at, _ok_str/_err_str) because direct
// construction in other shapes miscompiles. See SPEC.md for the full
// grammar, error catalog and test matrix.

module xiom.wkt

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;
use xiom.convert;

// --------------------------------------------------
//  Parsed document
// --------------------------------------------------

// Flat element table: element i describes one geometry. The arrays are
// parallel because XIOM v0.61.3 cannot hold a Vec[StructType]. All ranges are
// [start, end) index spans. Ring and coordinate ranges cover the element's
// whole subtree and are contiguous because rings and coordinates are appended
// in pre-order; child_starts/child_ends index child_ids, which lists the
// direct child elements in order (sibling element indices are NOT contiguous
// once a sibling has descendants, so the ids are listed explicitly).
pub type WktDoc = {
  kinds: Vec[Int];             // element kind, _WK_POINT .. _WK_GEOMETRYCOLLECTION
  markers: Vec[Int];           // declared ordinate marker: 0 none, 1 Z, 2 M, 3 ZM
  arities: Vec[Int];           // effective ordinates per coordinate tuple (2..4)
  empties: Vec[Bool];          // true when the element was declared EMPTY
  parents: Vec[Int];           // parent element, -1 for the root
  child_starts: Vec[Int];      // [start, end) range into child_ids
  child_ends: Vec[Int];
  child_ids: Vec[Int];         // element index of each direct child, in order
  ring_starts: Vec[Int];       // [start, end) range of rings in the subtree
  ring_ends: Vec[Int];
  point_starts: Vec[Int];      // [start, end) range of coordinates in the subtree
  point_ends: Vec[Int];
  ring_parents: Vec[Int];      // owning polygon element per ring
  ring_point_starts: Vec[Int]; // [start, end) coordinate range per ring
  ring_point_ends: Vec[Int];
  xs: Vec[Str];                // first ordinate text, verbatim
  ys: Vec[Str];                // second ordinate text, verbatim
  zs: Vec[Str];                // z ordinate text, "" when the tuple has none
  ms: Vec[Str];                // m ordinate text, "" when the tuple has none
}

// --------------------------------------------------
//  Constants
// --------------------------------------------------

const _WK_POINT: Int = 0;
const _WK_LINESTRING: Int = 1;
const _WK_POLYGON: Int = 2;
const _WK_MULTIPOINT: Int = 3;
const _WK_MULTILINESTRING: Int = 4;
const _WK_MULTIPOLYGON: Int = 5;
const _WK_GEOMETRYCOLLECTION: Int = 6;

const _WK_MARKER_Z: Int = 1;
const _WK_MARKER_M: Int = 2;
const _WK_MARKER_ZM: Int = 3;

const _WK_TAB: UInt8 = 9u8;
const _WK_LF: UInt8 = 10u8;
const _WK_CR: UInt8 = 13u8;
const _WK_SPACE: UInt8 = 32u8;
const _WK_LPAREN: UInt8 = 40u8;
const _WK_RPAREN: UInt8 = 41u8;
const _WK_COMMA: UInt8 = 44u8;
const _WK_PLUS: UInt8 = 43u8;
const _WK_MINUS: UInt8 = 45u8;
const _WK_DOT: UInt8 = 46u8;
const _WK_DIGIT_0: UInt8 = 48u8;
const _WK_DIGIT_9: UInt8 = 57u8;
const _WK_UPPER_E: UInt8 = 69u8;
const _WK_UPPER_A: UInt8 = 65u8;
const _WK_UPPER_Z: UInt8 = 90u8;
const _WK_LOWER_E: UInt8 = 101u8;
const _WK_LOWER_A: UInt8 = 97u8;
const _WK_LOWER_Z: UInt8 = 122u8;
const _WK_LOWER_CASE_BIT: UInt8 = 32u8;

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[WktDoc, Str].
fn _ok_doc(v: WktDoc) -> Result[WktDoc, Str] {
  return Ok(v);
}

// Err(m) for Result[WktDoc, Str].
fn _err_doc(m: Str) -> Result[WktDoc, Str] {
  return Err(m);
}

// Ok(v) for Result[Int, Str] (a scan position).
fn _ok_at(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

// Err(m) for Result[Int, Str].
fn _err_at(m: Str) -> Result[Int, Str] {
  return Err(m);
}

// Ok(v) for Result[Str, Str] (a canonical text).
fn _ok_str(v: Str) -> Result[Str, Str] {
  return Ok(v);
}

// Err(m) for Result[Str, Str].
fn _err_str(m: Str) -> Result[Str, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Byte predicates and string helpers
// --------------------------------------------------

// True for space, TAB, LF and CR.
fn _is_ws_byte(b: UInt8) -> Bool {
  if b == _WK_SPACE { return true; }
  if b == _WK_TAB { return true; }
  if b == _WK_LF { return true; }
  return b == _WK_CR;
}

// True for an ASCII decimal digit.
fn _is_digit_byte(b: UInt8) -> Bool {
  return b >= _WK_DIGIT_0 && b <= _WK_DIGIT_9;
}

// True for an ASCII letter (either case).
fn _is_alpha_byte(b: UInt8) -> Bool {
  if b >= _WK_UPPER_A && b <= _WK_UPPER_Z { return true; }
  return b >= _WK_LOWER_A && b <= _WK_LOWER_Z;
}

// ASCII uppercase of one byte; non-letters pass through.
fn _to_upper_byte(b: UInt8) -> UInt8 {
  if b >= _WK_LOWER_A && b <= _WK_LOWER_Z {
    return b - _WK_LOWER_CASE_BIT;
  }
  return b;
}

// True when two Str values have identical bytes (BUG 17-safe).
fn _streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// Skip spaces, TABS, LF and CR from `pos`; returns the first non-space offset.
fn _skip_ws(text: Str, pos: Int) -> Int {
  var i = pos;
  let n = text.len();
  while i < n && _is_ws_byte(string.byte_at(text, i)) {
    i = i + 1;
  }
  return i;
}

// Read the maximal run of ASCII letters at `pos`, uppercased; "" when the
// byte at `pos` is not a letter. Used for type keywords and Z/M/ZM markers.
fn _read_upper_word(text: Str, pos: Int) -> Str {
  let n = text.len();
  var i = pos;
  var buf = Vec[UInt8].new();
  while i < n {
    let b = string.byte_at(text, i);
    if !_is_alpha_byte(b) {
      break;
    }
    buf.push(_to_upper_byte(b));
    i = i + 1;
  }
  return Str::from_utf8(buf);
}

// --------------------------------------------------
//  Lexical number scanning
// --------------------------------------------------

// Length of the valid decimal number starting at `pos`, or 0 when the bytes
// at `pos` do not start one. Grammar: [+-]? digits ( "." digits )?
// ( [eE] [+-]? digits )? -- leading "+" and exponents are accepted; ".5" and
// "5." are not; the text is never converted.
fn _scan_number_len(text: Str, pos: Int) -> Int {
  let n = text.len();
  var i = pos;
  if i >= n {
    return 0;
  }
  let b0 = string.byte_at(text, i);
  if b0 == _WK_PLUS || b0 == _WK_MINUS {
    i = i + 1;
  }
  var int_digits = 0;
  while i < n && _is_digit_byte(string.byte_at(text, i)) {
    i = i + 1;
    int_digits = int_digits + 1;
  }
  if int_digits == 0 {
    return 0;
  }
  if i < n && string.byte_at(text, i) == _WK_DOT {
    i = i + 1;
    var frac_digits = 0;
    while i < n && _is_digit_byte(string.byte_at(text, i)) {
      i = i + 1;
      frac_digits = frac_digits + 1;
    }
    if frac_digits == 0 {
      return 0;
    }
  }
  if i < n {
    let eb = string.byte_at(text, i);
    if eb == _WK_LOWER_E || eb == _WK_UPPER_E {
      i = i + 1;
      if i < n {
        let sign = string.byte_at(text, i);
        if sign == _WK_PLUS || sign == _WK_MINUS {
          i = i + 1;
        }
      }
      var exp_digits = 0;
      while i < n && _is_digit_byte(string.byte_at(text, i)) {
        i = i + 1;
        exp_digits = exp_digits + 1;
      }
      if exp_digits == 0 {
        return 0;
      }
    }
  }
  return i - pos;
}

// True when the byte could start a number token (digit, sign or dot).
fn _is_number_start_byte(b: UInt8) -> Bool {
  if _is_digit_byte(b) { return true; }
  if b == _WK_PLUS || b == _WK_MINUS { return true; }
  return b == _WK_DOT;
}

// --------------------------------------------------
//  Structural scanning helpers
// --------------------------------------------------

// Skip whitespace and consume "("; returns the offset just past it.
fn _expect_open(text: Str, pos: Int) -> Result[Int, Str] {
  let i = _skip_ws(text, pos);
  if i < text.len() && string.byte_at(text, i) == _WK_LPAREN {
    return _ok_at(i + 1);
  }
  return _err_at("wkt: expected \"(\" at " + int_to_string(i));
}

// Skip whitespace and reject an immediate ")": an empty parenthesized list is
// always an error, EMPTY is the only empty spelling. Returns the offset of the
// first token after the paren.
fn _check_nonempty(text: Str, pos: Int) -> Result[Int, Str] {
  let i = _skip_ws(text, pos);
  if i < text.len() && string.byte_at(text, i) == _WK_RPAREN {
    return _err_at("wkt: empty coordinate list at " + int_to_string(i));
  }
  return _ok_at(i);
}

// Skip whitespace and consume ")"; `open` is the offset of the "(" this close
// belongs to, reported when the input ends first.
fn _expect_close(text: Str, pos: Int, open: Int) -> Result[Int, Str] {
  let i = _skip_ws(text, pos);
  if i >= text.len() {
    return _err_at("wkt: unbalanced parentheses at " + int_to_string(open));
  }
  if string.byte_at(text, i) == _WK_RPAREN {
    return _ok_at(i + 1);
  }
  return _err_at("wkt: expected \")\" at " + int_to_string(i));
}

// True when the offset is inside the text and points at ")".
fn _at_close(text: Str, i: Int) -> Bool {
  if i >= text.len() {
    return false;
  }
  return string.byte_at(text, i) == _WK_RPAREN;
}

// Separator decision after one list item. Returns the offset after a comma, or
// the offset of a ")" for the caller to close with _expect_close. Any other
// token is a missing comma; end of input is an unbalanced open parenthesis.
fn _list_next(text: Str, pos: Int, open: Int) -> Result[Int, Str] {
  let i = _skip_ws(text, pos);
  if i >= text.len() {
    return _err_at("wkt: unbalanced parentheses at " + int_to_string(open));
  }
  let b = string.byte_at(text, i);
  if b == _WK_COMMA {
    return _ok_at(i + 1);
  }
  if b == _WK_RPAREN {
    return _ok_at(i);
  }
  return _err_at("wkt: missing \",\" at " + int_to_string(i));
}

// --------------------------------------------------
//  Element table maintenance
// --------------------------------------------------

// Kind index of an uppercased keyword, or -1 when it names no known type.
fn _kind_of(word: Str) -> Int {
  if _streq(word, "POINT") { return _WK_POINT; }
  if _streq(word, "LINESTRING") { return _WK_LINESTRING; }
  if _streq(word, "POLYGON") { return _WK_POLYGON; }
  if _streq(word, "MULTIPOINT") { return _WK_MULTIPOINT; }
  if _streq(word, "MULTILINESTRING") { return _WK_MULTILINESTRING; }
  if _streq(word, "MULTIPOLYGON") { return _WK_MULTIPOLYGON; }
  if _streq(word, "GEOMETRYCOLLECTION") { return _WK_GEOMETRYCOLLECTION; }
  return -1;
}

// Canonical uppercase name of a kind ("UNKNOWN" outside 0..6).
fn _kind_name(kind: Int) -> Str {
  if kind == _WK_POINT { return "POINT"; }
  if kind == _WK_LINESTRING { return "LINESTRING"; }
  if kind == _WK_POLYGON { return "POLYGON"; }
  if kind == _WK_MULTIPOINT { return "MULTIPOINT"; }
  if kind == _WK_MULTILINESTRING { return "MULTILINESTRING"; }
  if kind == _WK_MULTIPOLYGON { return "MULTIPOLYGON"; }
  if kind == _WK_GEOMETRYCOLLECTION { return "GEOMETRYCOLLECTION"; }
  return "UNKNOWN";
}

// Ordinates added by a marker: Z and M add one each, ZM adds two.
fn _marker_dims(marker: Int) -> Int {
  if marker == _WK_MARKER_Z { return 1; }
  if marker == _WK_MARKER_M { return 1; }
  if marker == _WK_MARKER_ZM { return 2; }
  return 0;
}

// Append one element with empty spans and return its index. Rings and
// coordinates appended afterwards fall inside the spans the caller closes;
// the child range is filled by the container parser (child ids are appended in
// post-order bursts so nesting cannot interleave them).
fn _new_element(doc: &mut WktDoc, kind: Int, marker: Int, arity: Int, parent: Int, empty: Bool) -> Int {
  let idx = doc.kinds.len();
  doc.kinds.push(kind);
  doc.markers.push(marker);
  doc.arities.push(arity);
  doc.empties.push(empty);
  doc.parents.push(parent);
  doc.child_starts.push(0);
  doc.child_ends.push(0);
  doc.ring_starts.push(doc.ring_parents.len());
  doc.ring_ends.push(doc.ring_parents.len());
  doc.point_starts.push(doc.xs.len());
  doc.point_ends.push(doc.xs.len());
  return idx;
}

// Copy the direct-child element ids collected for `owner` into the flat child
// table and close the owner's [start, end) range. Containers call this once,
// after their child loop, so nested containers cannot interleave the bursts.
fn _append_kids(doc: &mut WktDoc, owner: Int, kids: &Vec[Int]) {
  doc.child_starts[owner] = doc.child_ids.len();
  var k = 0;
  while k < kids.len() {
    let kid: Int = kids[k];
    doc.child_ids.push(kid);
    k = k + 1;
  }
  doc.child_ends[owner] = doc.child_ids.len();
}

// --------------------------------------------------
//  Tuple parsing
// --------------------------------------------------

// Parse one whitespace-separated coordinate tuple of exactly `arity` numbers
// (arity = 2 + dims(marker)) and append the ordinate texts to the document:
// x and y always, then z, m or both following the marker. Extra or missing
// ordinates are an "expected <n> ordinates" error; a token that starts no
// number and is not ")" or "," is an "invalid number" error.
fn _parse_tuple(text: Str, pos: Int, marker: Int, doc: &mut WktDoc) -> Result[Int, Str] {
  let arity = 2 + _marker_dims(marker);
  var i = _skip_ws(text, pos);
  let first = i;
  var v0 = "";
  var v1 = "";
  var v2 = "";
  var v3 = "";
  var count = 0;
  var scanning = true;
  while scanning {
    let nlen = _scan_number_len(text, i);
    if nlen == 0 {
      scanning = false;
    } else {
      let tok = string.str_slice(text, i, i + nlen);
      if count == 0 { v0 = tok; }
      elif count == 1 { v1 = tok; }
      elif count == 2 { v2 = tok; }
      elif count == 3 { v3 = tok; }
      count = count + 1;
      i = i + nlen;
      let j = _skip_ws(text, i);
      if j == i { scanning = false; } else { i = j; }
    }
  }
  if count != arity {
    if i < text.len() {
      let b = string.byte_at(text, i);
      if b != _WK_RPAREN && b != _WK_COMMA {
        return _err_at("wkt: invalid number at " + int_to_string(i));
      }
    }
    return _err_at("wkt: expected " + int_to_string(arity) + " ordinates at " + int_to_string(first));
  }
  var ztext = "";
  var mtext = "";
  if marker == _WK_MARKER_Z {
    ztext = v2;
  } elif marker == _WK_MARKER_M {
    mtext = v2;
  } elif marker == _WK_MARKER_ZM {
    ztext = v2;
    mtext = v3;
  }
  doc.xs.push(v0);
  doc.ys.push(v1);
  doc.zs.push(ztext);
  doc.ms.push(mtext);
  return _ok_at(i);
}

// --------------------------------------------------
//  Geometry parsing
// --------------------------------------------------

// Parse the body of a POINT (the "(" already required): one tuple then ")".
fn _parse_point_body(text: Str, pos: Int, idx: Int, eff_marker: Int, doc: &mut WktDoc) -> Result[Int, Str] {
  let o = _expect_open(text, pos);
  var i = 0;
  match o {
    Ok(v) => { i = v; },
    Err(m) => { return _err_at(m); },
  }
  let open = i - 1;
  let e = _check_nonempty(text, i);
  match e {
    Ok(v) => { i = v; },
    Err(m) => { return _err_at(m); },
  }
  let t = _parse_tuple(text, i, eff_marker, doc);
  match t {
    Ok(v) => { i = v; },
    Err(m) => { return _err_at(m); },
  }
  let c = _expect_close(text, i, open);
  match c {
    Ok(v) => {
      doc.point_ends[idx] = doc.xs.len();
      return _ok_at(v);
    },
    Err(m) => { return _err_at(m); },
  }
  return _err_at("wkt: unreachable");
}

// Parse the body of a LINESTRING: one or more tuples separated by commas.
fn _parse_linestring_body(text: Str, pos: Int, idx: Int, eff_marker: Int, doc: &mut WktDoc) -> Result[Int, Str] {
  let o = _expect_open(text, pos);
  var i = 0;
  match o {
    Ok(v) => { i = v; },
    Err(m) => { return _err_at(m); },
  }
  let open = i - 1;
  let e = _check_nonempty(text, i);
  match e {
    Ok(v) => { i = v; },
    Err(m) => { return _err_at(m); },
  }
  var more = true;
  while more {
    let t = _parse_tuple(text, i, eff_marker, doc);
    match t {
      Ok(v) => { i = v; },
      Err(m) => { return _err_at(m); },
    }
    let nx = _list_next(text, i, open);
    match nx {
      Ok(v) => { i = v; },
      Err(m) => { return _err_at(m); },
    }
    if _at_close(text, i) {
      more = false;
    }
  }
  let c = _expect_close(text, i, open);
  match c {
    Ok(v) => {
      doc.point_ends[idx] = doc.xs.len();
      return _ok_at(v);
    },
    Err(m) => { return _err_at(m); },
  }
  return _err_at("wkt: unreachable");
}

// Parse the rings of one polygon starting at `pos` (just past the owning "(").
// Each ring is "(tuple, tuple, ...)" separated by commas; `open` is the
// owning parenthesis, reported for unbalanced input. Rings are appended to the
// document and attributed to element `owner`.
fn _parse_ring_list(text: Str, pos: Int, owner: Int, eff_marker: Int, doc: &mut WktDoc, open: Int) -> Result[Int, Str] {
  var i = pos;
  var more = true;
  while more {
    let ro = _expect_open(text, i);
    match ro {
      Ok(v) => { i = v; },
      Err(m) => { return _err_at(m); },
    }
    let ropen = i - 1;
    let ne = _check_nonempty(text, i);
    match ne {
      Ok(v) => { i = v; },
      Err(m) => { return _err_at(m); },
    }
    let ring_start = doc.xs.len();
    var in_ring = true;
    while in_ring {
      let t = _parse_tuple(text, i, eff_marker, doc);
      match t {
        Ok(v) => { i = v; },
        Err(m) => { return _err_at(m); },
      }
      let nx = _list_next(text, i, ropen);
      match nx {
        Ok(v) => { i = v; },
        Err(m) => { return _err_at(m); },
      }
      if _at_close(text, i) {
        in_ring = false;
      }
    }
    let rc = _expect_close(text, i, ropen);
    match rc {
      Ok(v) => { i = v; },
      Err(m) => { return _err_at(m); },
    }
    doc.ring_parents.push(owner);
    doc.ring_point_starts.push(ring_start);
    doc.ring_point_ends.push(doc.xs.len());
    let nx2 = _list_next(text, i, open);
    match nx2 {
      Ok(v) => { i = v; },
      Err(m) => { return _err_at(m); },
    }
    if _at_close(text, i) {
      more = false;
    }
  }
  return _ok_at(i);
}

// Parse the body of a POLYGON: one or more rings.
fn _parse_polygon_body(text: Str, pos: Int, idx: Int, eff_marker: Int, doc: &mut WktDoc) -> Result[Int, Str] {
  let o = _expect_open(text, pos);
  var i = 0;
  match o {
    Ok(v) => { i = v; },
    Err(m) => { return _err_at(m); },
  }
  let open = i - 1;
  let e = _check_nonempty(text, i);
  match e {
    Ok(v) => { i = v; },
    Err(m) => { return _err_at(m); },
  }
  let r = _parse_ring_list(text, i, idx, eff_marker, doc, open);
  match r {
    Ok(v) => { i = v; },
    Err(m) => { return _err_at(m); },
  }
  let c = _expect_close(text, i, open);
  match c {
    Ok(v) => {
      doc.ring_ends[idx] = doc.ring_parents.len();
      doc.point_ends[idx] = doc.xs.len();
      return _ok_at(v);
    },
    Err(m) => { return _err_at(m); },
  }
  return _err_at("wkt: unreachable");
}

// Parse the body of a MULTIPOINT: "(tuple)" items separated by commas; one
// POINT child element is created per item.
fn _parse_multipoint_body(text: Str, pos: Int, idx: Int, eff_marker: Int, doc: &mut WktDoc) -> Result[Int, Str] {
  let o = _expect_open(text, pos);
  var i = 0;
  match o {
    Ok(v) => { i = v; },
    Err(m) => { return _err_at(m); },
  }
  let open = i - 1;
  let e = _check_nonempty(text, i);
  match e {
    Ok(v) => { i = v; },
    Err(m) => { return _err_at(m); },
  }
  let arity = 2 + _marker_dims(eff_marker);
  var kids = Vec[Int].new();
  var more = true;
  while more {
    let po = _expect_open(text, i);
    match po {
      Ok(v) => { i = v; },
      Err(m) => { return _err_at(m); },
    }
    let popen = i - 1;
    let ne = _check_nonempty(text, i);
    match ne {
      Ok(v) => { i = v; },
      Err(m) => { return _err_at(m); },
    }
    let child = _new_element(doc, _WK_POINT, 0, arity, idx, false);
    kids.push(child);
    let t = _parse_tuple(text, i, eff_marker, doc);
    match t {
      Ok(v) => { i = v; },
      Err(m) => { return _err_at(m); },
    }
    doc.point_ends[child] = doc.xs.len();
    let pc = _expect_close(text, i, popen);
    match pc {
      Ok(v) => { i = v; },
      Err(m) => { return _err_at(m); },
    }
    let nx = _list_next(text, i, open);
    match nx {
      Ok(v) => { i = v; },
      Err(m) => { return _err_at(m); },
    }
    if _at_close(text, i) {
      more = false;
    }
  }
  let c = _expect_close(text, i, open);
  match c {
    Ok(v) => {
      _append_kids(doc, idx, &kids);
      doc.point_ends[idx] = doc.xs.len();
      return _ok_at(v);
    },
    Err(m) => { return _err_at(m); },
  }
  return _err_at("wkt: unreachable");
}

// Parse the body of a MULTILINESTRING: "(tuple, ...)" items separated by
// commas; one LINESTRING child element is created per item.
fn _parse_multilinestring_body(text: Str, pos: Int, idx: Int, eff_marker: Int, doc: &mut WktDoc) -> Result[Int, Str] {
  let o = _expect_open(text, pos);
  var i = 0;
  match o {
    Ok(v) => { i = v; },
    Err(m) => { return _err_at(m); },
  }
  let open = i - 1;
  let e = _check_nonempty(text, i);
  match e {
    Ok(v) => { i = v; },
    Err(m) => { return _err_at(m); },
  }
  let arity = 2 + _marker_dims(eff_marker);
  var kids = Vec[Int].new();
  var more = true;
  while more {
    let lo = _expect_open(text, i);
    match lo {
      Ok(v) => { i = v; },
      Err(m) => { return _err_at(m); },
    }
    let lopen = i - 1;
    let ne = _check_nonempty(text, i);
    match ne {
      Ok(v) => { i = v; },
      Err(m) => { return _err_at(m); },
    }
    let child = _new_element(doc, _WK_LINESTRING, 0, arity, idx, false);
    kids.push(child);
    var in_line = true;
    while in_line {
      let t = _parse_tuple(text, i, eff_marker, doc);
      match t {
        Ok(v) => { i = v; },
        Err(m) => { return _err_at(m); },
      }
      let nx = _list_next(text, i, lopen);
      match nx {
        Ok(v) => { i = v; },
        Err(m) => { return _err_at(m); },
      }
      if _at_close(text, i) {
        in_line = false;
      }
    }
    let lc = _expect_close(text, i, lopen);
    match lc {
      Ok(v) => { i = v; },
      Err(m) => { return _err_at(m); },
    }
    doc.point_ends[child] = doc.xs.len();
    let nx2 = _list_next(text, i, open);
    match nx2 {
      Ok(v) => { i = v; },
      Err(m) => { return _err_at(m); },
    }
    if _at_close(text, i) {
      more = false;
    }
  }
  let c = _expect_close(text, i, open);
  match c {
    Ok(v) => {
      _append_kids(doc, idx, &kids);
      doc.point_ends[idx] = doc.xs.len();
      return _ok_at(v);
    },
    Err(m) => { return _err_at(m); },
  }
  return _err_at("wkt: unreachable");
}

// Parse the body of a MULTIPOLYGON: "(ring, ...)" items separated by commas;
// one POLYGON child element is created per item.
fn _parse_multipolygon_body(text: Str, pos: Int, idx: Int, eff_marker: Int, doc: &mut WktDoc) -> Result[Int, Str] {
  let o = _expect_open(text, pos);
  var i = 0;
  match o {
    Ok(v) => { i = v; },
    Err(m) => { return _err_at(m); },
  }
  let open = i - 1;
  let e = _check_nonempty(text, i);
  match e {
    Ok(v) => { i = v; },
    Err(m) => { return _err_at(m); },
  }
  let arity = 2 + _marker_dims(eff_marker);
  var kids = Vec[Int].new();
  var more = true;
  while more {
    let po = _expect_open(text, i);
    match po {
      Ok(v) => { i = v; },
      Err(m) => { return _err_at(m); },
    }
    let popen = i - 1;
    let ne = _check_nonempty(text, i);
    match ne {
      Ok(v) => { i = v; },
      Err(m) => { return _err_at(m); },
    }
    let child = _new_element(doc, _WK_POLYGON, 0, arity, idx, false);
    kids.push(child);
    let r = _parse_ring_list(text, i, child, eff_marker, doc, popen);
    match r {
      Ok(v) => { i = v; },
      Err(m) => { return _err_at(m); },
    }
    let pc = _expect_close(text, i, popen);
    match pc {
      Ok(v) => { i = v; },
      Err(m) => { return _err_at(m); },
    }
    doc.ring_ends[child] = doc.ring_parents.len();
    doc.point_ends[child] = doc.xs.len();
    let nx = _list_next(text, i, open);
    match nx {
      Ok(v) => { i = v; },
      Err(m) => { return _err_at(m); },
    }
    if _at_close(text, i) {
      more = false;
    }
  }
  let c = _expect_close(text, i, open);
  match c {
    Ok(v) => {
      _append_kids(doc, idx, &kids);
      doc.ring_ends[idx] = doc.ring_parents.len();
      doc.point_ends[idx] = doc.xs.len();
      return _ok_at(v);
    },
    Err(m) => { return _err_at(m); },
  }
  return _err_at("wkt: unreachable");
}

// Parse the body of a GEOMETRYCOLLECTION: one or more geometry elements
// separated by commas. `eff_marker` is the marker children inherit when they
// declare none of their own.
fn _parse_collection_body(text: Str, pos: Int, idx: Int, eff_marker: Int, doc: &mut WktDoc) -> Result[Int, Str] {
  let o = _expect_open(text, pos);
  var i = 0;
  match o {
    Ok(v) => { i = v; },
    Err(m) => { return _err_at(m); },
  }
  let open = i - 1;
  let e = _check_nonempty(text, i);
  match e {
    Ok(v) => { i = v; },
    Err(m) => { return _err_at(m); },
  }
  var kids = Vec[Int].new();
  var more = true;
  while more {
    let child = doc.kinds.len();
    let g = _parse_geometry(text, i, eff_marker, idx, doc);
    match g {
      Ok(v) => { i = v; },
      Err(m) => { return _err_at(m); },
    }
    kids.push(child);
    let nx = _list_next(text, i, open);
    match nx {
      Ok(v) => { i = v; },
      Err(m) => { return _err_at(m); },
    }
    if _at_close(text, i) {
      more = false;
    }
  }
  let c = _expect_close(text, i, open);
  match c {
    Ok(v) => {
      _append_kids(doc, idx, &kids);
      doc.ring_ends[idx] = doc.ring_parents.len();
      doc.point_ends[idx] = doc.xs.len();
      return _ok_at(v);
    },
    Err(m) => { return _err_at(m); },
  }
  return _err_at("wkt: unreachable");
}

// Parse one geometry element at `pos`: keyword, optional ordinate marker,
// optional EMPTY, then the kind-specific body. `par_eff_marker` is the marker
// in force in the enclosing container (0 when none); an element that declares
// its own marker must not contradict one in force, and an element that
// declares none inherits the enclosing arity.
fn _parse_geometry(text: Str, pos: Int, par_eff_marker: Int, parent: Int, doc: &mut WktDoc) -> Result[Int, Str] {
  var i = _skip_ws(text, pos);
  let kw_pos = i;
  let word = _read_upper_word(text, i);
  let wlen = word.len();
  if wlen == 0 {
    return _err_at("wkt: unknown geometry type at " + int_to_string(kw_pos));
  }
  let kind = _kind_of(word);
  if kind < 0 {
    return _err_at("wkt: unknown geometry type at " + int_to_string(kw_pos));
  }
  i = i + wlen;
  i = _skip_ws(text, i);
  var marker = 0;
  var empty = false;
  let marker_pos = i;
  if i < text.len() && _is_alpha_byte(string.byte_at(text, i)) {
    let w1 = _read_upper_word(text, i);
    if _streq(w1, "EMPTY") {
      empty = true;
      i = i + w1.len();
    } else {
      if _streq(w1, "Z") {
        marker = _WK_MARKER_Z;
      } elif _streq(w1, "M") {
        marker = _WK_MARKER_M;
      } elif _streq(w1, "ZM") {
        marker = _WK_MARKER_ZM;
      } else {
        return _err_at("wkt: unknown ordinate marker at " + int_to_string(i));
      }
      i = i + w1.len();
      i = _skip_ws(text, i);
      if i < text.len() && _is_alpha_byte(string.byte_at(text, i)) {
        let w2 = _read_upper_word(text, i);
        if _streq(w2, "EMPTY") {
          empty = true;
          i = i + w2.len();
        } else {
          return _err_at("wkt: unknown ordinate marker at " + int_to_string(i));
        }
      }
    }
  }
  var arity = 2 + _marker_dims(par_eff_marker);
  var eff_marker = par_eff_marker;
  if marker != 0 {
    if par_eff_marker != 0 && marker != par_eff_marker {
      return _err_at("wkt: conflicting ordinate markers at " + int_to_string(marker_pos));
    }
    eff_marker = marker;
    arity = 2 + _marker_dims(marker);
  }
  let idx = _new_element(doc, kind, marker, arity, parent, empty);
  if empty {
    return _ok_at(i);
  }
  if kind == _WK_POINT {
    return _parse_point_body(text, i, idx, eff_marker, doc);
  }
  if kind == _WK_LINESTRING {
    return _parse_linestring_body(text, i, idx, eff_marker, doc);
  }
  if kind == _WK_POLYGON {
    return _parse_polygon_body(text, i, idx, eff_marker, doc);
  }
  if kind == _WK_MULTIPOINT {
    return _parse_multipoint_body(text, i, idx, eff_marker, doc);
  }
  if kind == _WK_MULTILINESTRING {
    return _parse_multilinestring_body(text, i, idx, eff_marker, doc);
  }
  if kind == _WK_MULTIPOLYGON {
    return _parse_multipolygon_body(text, i, idx, eff_marker, doc);
  }
  return _parse_collection_body(text, i, idx, eff_marker, doc);
}

// --------------------------------------------------
//  Public API: parsing
// --------------------------------------------------

/// Parse a WKT geometry document.
/// Params: text - one geometry in the subset documented in SPEC.md; leading
/// and trailing whitespace is allowed, keywords are case-insensitive, and
/// coordinate tokens must be decimal numbers ([+-]? digits [. digits]?
/// [[eE][+-]? digits]?).
/// Returns: Ok(WktDoc) with the root element at index 0. Every descendant is
/// a flat element; a container's ring/coordinate spans cover its whole
/// subtree, while its child span lists the direct children in order.
/// Error case: Err with a "wkt: ..." message and byte offset: unknown type,
/// unknown ordinate marker, expected "(", expected ")", unbalanced
/// parentheses, invalid number, wrong ordinate count, missing comma, empty
/// coordinate list, trailing tokens, conflicting ordinate markers.
/// Complexity: O(n) over the input; recursion depth is the nesting depth.
pub fn wkt_parse(text: Str) -> Result[WktDoc, Str] {
  var doc = WktDoc{
    kinds: Vec[Int].new();
    markers: Vec[Int].new();
    arities: Vec[Int].new();
    empties: Vec[Bool].new();
    parents: Vec[Int].new();
    child_starts: Vec[Int].new();
    child_ends: Vec[Int].new();
    child_ids: Vec[Int].new();
    ring_starts: Vec[Int].new();
    ring_ends: Vec[Int].new();
    point_starts: Vec[Int].new();
    point_ends: Vec[Int].new();
    ring_parents: Vec[Int].new();
    ring_point_starts: Vec[Int].new();
    ring_point_ends: Vec[Int].new();
    xs: Vec[Str].new();
    ys: Vec[Str].new();
    zs: Vec[Str].new();
    ms: Vec[Str].new();
  };
  let r = _parse_geometry(text, 0, 0, -1, &mut doc);
  match r {
    Ok(i) => {
      let j = _skip_ws(text, i);
      if j < text.len() {
        return _err_doc("wkt: trailing tokens at " + int_to_string(j));
      }
      return _ok_doc(doc);
    },
    Err(m) => { return _err_doc(m); },
  }
  return _err_doc("wkt: unreachable");
}

/// Parse and canonically re-emit a WKT geometry in one call.
/// Params: text - the input document.
/// Returns: Ok(canonical) with the exact text wkt_write would produce for
/// wkt_parse(text).
/// Error case: the same Err messages as wkt_parse.
/// Complexity: O(n).
pub fn wkt_normalize(text: Str) -> Result[Str, Str] {
  let r = wkt_parse(text);
  match r {
    Ok(d) => { return _ok_str(wkt_write(&d)); },
    Err(m) => { return _err_str(m); },
  }
  return _err_str("wkt: unreachable");
}

// --------------------------------------------------
//  Canonical emission
// --------------------------------------------------

// Append " Z", " M" or " ZM" for a declared marker.
fn _emit_marker(sb: &mut Vec[UInt8], marker: Int) {
  if marker == _WK_MARKER_Z {
    builder.sb_push_str(sb, " Z");
  } elif marker == _WK_MARKER_M {
    builder.sb_push_str(sb, " M");
  } elif marker == _WK_MARKER_ZM {
    builder.sb_push_str(sb, " ZM");
  }
}

// Append one coordinate tuple: "x y" plus z/m when present.
fn _emit_tuple(sb: &mut Vec[UInt8], doc: &WktDoc, p: Int) {
  let x: Str = doc.xs[p];
  let y: Str = doc.ys[p];
  let z: Str = doc.zs[p];
  let m: Str = doc.ms[p];
  builder.sb_push_str(sb, x);
  builder.sb_push_str(sb, " ");
  builder.sb_push_str(sb, y);
  if !_streq(z, "") {
    builder.sb_push_str(sb, " ");
    builder.sb_push_str(sb, z);
  }
  if !_streq(m, "") {
    builder.sb_push_str(sb, " ");
    builder.sb_push_str(sb, m);
  }
}

// Append [start, end) coordinate tuples separated by ", ".
fn _emit_tuples(sb: &mut Vec[UInt8], doc: &WktDoc, start: Int, end: Int) {
  var p = start;
  while p < end {
    if p > start {
      builder.sb_push_str(sb, ", ");
    }
    _emit_tuple(sb, doc, p);
    p = p + 1;
  }
}

// Append [start, end) rings as "(tuple, ...)" separated by ", ".
fn _emit_rings(sb: &mut Vec[UInt8], doc: &WktDoc, start: Int, end: Int) {
  var r = start;
  while r < end {
    if r > start {
      builder.sb_push_str(sb, ", ");
    }
    let ps: Int = doc.ring_point_starts[r];
    let pe: Int = doc.ring_point_ends[r];
    builder.sb_push_str(sb, "(");
    _emit_tuples(sb, doc, ps, pe);
    builder.sb_push_str(sb, ")");
    r = r + 1;
  }
}

// Append the canonical text of element i (pre-order).
fn _emit_element(sb: &mut Vec[UInt8], doc: &WktDoc, i: Int) {
  let kind: Int = doc.kinds[i];
  let marker: Int = doc.markers[i];
  let empty: Bool = doc.empties[i];
  builder.sb_push_str(sb, _kind_name(kind));
  _emit_marker(sb, marker);
  if empty {
    builder.sb_push_str(sb, " EMPTY");
    return;
  }
  let ps: Int = doc.point_starts[i];
  let pe: Int = doc.point_ends[i];
  if kind == _WK_POINT {
    builder.sb_push_str(sb, " (");
    _emit_tuple(sb, doc, ps);
    builder.sb_push_str(sb, ")");
    return;
  }
  if kind == _WK_LINESTRING {
    builder.sb_push_str(sb, " (");
    _emit_tuples(sb, doc, ps, pe);
    builder.sb_push_str(sb, ")");
    return;
  }
  if kind == _WK_POLYGON {
    let rs: Int = doc.ring_starts[i];
    let re: Int = doc.ring_ends[i];
    builder.sb_push_str(sb, " (");
    _emit_rings(sb, doc, rs, re);
    builder.sb_push_str(sb, ")");
    return;
  }
  let cs: Int = doc.child_starts[i];
  let ce: Int = doc.child_ends[i];
  builder.sb_push_str(sb, " (");
  var c = cs;
  while c < ce {
    if c > cs {
      builder.sb_push_str(sb, ", ");
    }
    let child: Int = doc.child_ids[c];
    if kind == _WK_MULTIPOINT {
      let cps: Int = doc.point_starts[child];
      builder.sb_push_str(sb, "(");
      _emit_tuple(sb, doc, cps);
      builder.sb_push_str(sb, ")");
    } elif kind == _WK_MULTILINESTRING {
      let cps: Int = doc.point_starts[child];
      let cpe: Int = doc.point_ends[child];
      builder.sb_push_str(sb, "(");
      _emit_tuples(sb, doc, cps, cpe);
      builder.sb_push_str(sb, ")");
    } elif kind == _WK_MULTIPOLYGON {
      let crs: Int = doc.ring_starts[child];
      let cre: Int = doc.ring_ends[child];
      builder.sb_push_str(sb, "(");
      _emit_rings(sb, doc, crs, cre);
      builder.sb_push_str(sb, ")");
    } else {
      _emit_element(sb, doc, child);
    }
    c = c + 1;
  }
  builder.sb_push_str(sb, ")");
}

/// Canonically emit a parsed document.
/// Params: doc - a document from wkt_parse (an empty table emits "").
/// Returns: canonical text: uppercase type keywords, a single space between
/// every token, tuples joined with ", ", EMPTY as the only empty spelling.
/// Coordinate tokens are emitted verbatim, so the output re-parses to an
/// equal document.
/// Error case: none.
/// Complexity: O(n) with an amortized O(1) string builder.
pub fn wkt_write(doc: &WktDoc) -> Str {
  var sb = builder.sb_new();
  if doc.kinds.len() > 0 {
    _emit_element(&mut sb, doc, 0);
  }
  return builder.sb_to_str(&sb);
}

// --------------------------------------------------
//  Public API: document accessors
// --------------------------------------------------

/// Number of elements in the document (the root plus every descendant).
/// Params: doc - the document.
/// Returns: element count; 0 for an empty table.
/// Error case: none.
/// Complexity: O(1).
pub fn wkt_geometry_count(doc: &WktDoc) -> Int {
  return doc.kinds.len();
}

/// Canonical uppercase type name of element `i`.
/// Params: doc - the document; i - zero-based element index (0 is the root).
/// Returns: "POINT", "LINESTRING", "POLYGON", "MULTIPOINT",
/// "MULTILINESTRING", "MULTIPOLYGON" or "GEOMETRYCOLLECTION"; "" when `i` is
/// out of range (so an empty result is distinguishable from every type).
/// Error case: none.
/// Complexity: O(1).
pub fn wkt_type(doc: &WktDoc, i: Int) -> Str {
  if i < 0 || i >= doc.kinds.len() {
    return "";
  }
  let kind: Int = doc.kinds[i];
  return _kind_name(kind);
}

/// Declared ordinate marker of element `i`.
/// Params: doc - the document; i - zero-based element index.
/// Returns: 0 (none), 1 (Z), 2 (M) or 3 (ZM); -1 when `i` is out of range.
/// A marker inherited from an ancestor is not reported here (see
/// wkt_coord_arity for the effective ordinate count).
/// Error case: none.
/// Complexity: O(1).
pub fn wkt_marker(doc: &WktDoc, i: Int) -> Int {
  if i < 0 || i >= doc.markers.len() {
    return -1;
  }
  let marker: Int = doc.markers[i];
  return marker;
}

/// Effective number of ordinates per coordinate tuple of element `i`: the
/// declared marker count, or the value inherited from the enclosing container
/// when the element declares no marker.
/// Params: doc - the document; i - zero-based element index.
/// Returns: 2, 3 or 4; -1 when `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn wkt_coord_arity(doc: &WktDoc, i: Int) -> Int {
  if i < 0 || i >= doc.arities.len() {
    return -1;
  }
  let arity: Int = doc.arities[i];
  return arity;
}

/// True when element `i` was declared EMPTY (or `i` is out of range).
/// Params: doc - the document; i - zero-based element index.
/// Returns: the EMPTY flag.
/// Error case: none.
/// Complexity: O(1).
pub fn wkt_is_empty(doc: &WktDoc, i: Int) -> Bool {
  if i < 0 || i >= doc.empties.len() {
    return true;
  }
  let empty: Bool = doc.empties[i];
  return empty;
}

/// Parent element of element `i`.
/// Params: doc - the document; i - zero-based element index.
/// Returns: the parent index; -1 for the root or when `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn wkt_parent(doc: &WktDoc, i: Int) -> Int {
  if i < 0 || i >= doc.parents.len() {
    return -1;
  }
  let parent: Int = doc.parents[i];
  return parent;
}

/// Number of direct child elements of element `i` (points of a MULTIPOINT,
/// lines of a MULTILINESTRING, polygons of a MULTIPOLYGON, members of a
/// GEOMETRYCOLLECTION; 0 for POINT, LINESTRING and POLYGON).
/// Params: doc - the document; i - zero-based element index.
/// Returns: the direct child count; 0 when `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn wkt_child_count(doc: &WktDoc, i: Int) -> Int {
  if i < 0 || i >= doc.kinds.len() {
    return 0;
  }
  let start: Int = doc.child_starts[i];
  let end: Int = doc.child_ends[i];
  return end - start;
}

/// Index of direct child `k` of element `i`.
/// Params: doc - the document; i - parent element index; k - zero-based child
/// ordinal.
/// Returns: the child element index; -1 when `i` or `k` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn wkt_child(doc: &WktDoc, i: Int, k: Int) -> Int {
  if i < 0 || i >= doc.kinds.len() {
    return -1;
  }
  if k < 0 {
    return -1;
  }
  let start: Int = doc.child_starts[i];
  let end: Int = doc.child_ends[i];
  if start + k >= end {
    return -1;
  }
  let child: Int = doc.child_ids[start + k];
  return child;
}

/// First coordinate index of the subtree rooted at element `i`.
/// Params: doc - the document; i - zero-based element index.
/// Returns: the start of the [start, end) coordinate span; -1 when `i` is out
/// of range.
/// Error case: none.
/// Complexity: O(1).
pub fn wkt_point_start(doc: &WktDoc, i: Int) -> Int {
  if i < 0 || i >= doc.point_starts.len() {
    return -1;
  }
  let start: Int = doc.point_starts[i];
  return start;
}

/// One past the last coordinate index of the subtree rooted at element `i`.
/// Params: doc - the document; i - zero-based element index.
/// Returns: the end of the [start, end) coordinate span; -1 when `i` is out
/// of range.
/// Error case: none.
/// Complexity: O(1).
pub fn wkt_point_end(doc: &WktDoc, i: Int) -> Int {
  if i < 0 || i >= doc.point_ends.len() {
    return -1;
  }
  let end: Int = doc.point_ends[i];
  return end;
}

/// Number of coordinates in the subtree rooted at element `i` (a POINT has
/// one, a LINESTRING has its vertices, a POLYGON has all ring vertices, a
/// container has the total of its descendants).
/// Params: doc - the document; i - zero-based element index.
/// Returns: the coordinate count; 0 when `i` is out of range or EMPTY.
/// Error case: none.
/// Complexity: O(1).
pub fn wkt_point_count(doc: &WktDoc, i: Int) -> Int {
  if i < 0 || i >= doc.kinds.len() {
    return 0;
  }
  let start: Int = doc.point_starts[i];
  let end: Int = doc.point_ends[i];
  return end - start;
}

/// Number of rings in the subtree rooted at element `i` (rings of a POLYGON,
/// or the total of the polygons below a MULTIPOLYGON or
/// GEOMETRYCOLLECTION).
/// Params: doc - the document; i - zero-based element index.
/// Returns: the ring count; 0 when `i` is out of range or there are no rings.
/// Error case: none.
/// Complexity: O(1).
pub fn wkt_ring_count(doc: &WktDoc, i: Int) -> Int {
  if i < 0 || i >= doc.kinds.len() {
    return 0;
  }
  let start: Int = doc.ring_starts[i];
  let end: Int = doc.ring_ends[i];
  return end - start;
}

/// Owner of ring `r`.
/// Params: doc - the document; r - zero-based ring index (ring indices are
/// global document order).
/// Returns: the POLYGON element index that owns the ring; -1 when `r` is out
/// of range.
/// Error case: none.
/// Complexity: O(1).
pub fn wkt_ring_parent(doc: &WktDoc, r: Int) -> Int {
  if r < 0 || r >= doc.ring_parents.len() {
    return -1;
  }
  let parent: Int = doc.ring_parents[r];
  return parent;
}

/// First coordinate index of ring `r`.
/// Params: doc - the document; r - zero-based ring index.
/// Returns: the start of the ring's [start, end) coordinate span; -1 when `r`
/// is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn wkt_ring_point_start(doc: &WktDoc, r: Int) -> Int {
  if r < 0 || r >= doc.ring_point_starts.len() {
    return -1;
  }
  let start: Int = doc.ring_point_starts[r];
  return start;
}

/// One past the last coordinate index of ring `r`.
/// Params: doc - the document; r - zero-based ring index.
/// Returns: the end of the ring's [start, end) coordinate span; -1 when `r`
/// is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn wkt_ring_point_end(doc: &WktDoc, r: Int) -> Int {
  if r < 0 || r >= doc.ring_point_ends.len() {
    return -1;
  }
  let end: Int = doc.ring_point_ends[r];
  return end;
}

/// Number of coordinates in ring `r`.
/// Params: doc - the document; r - zero-based ring index.
/// Returns: the ring's vertex count; 0 when `r` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn wkt_ring_point_count(doc: &WktDoc, r: Int) -> Int {
  if r < 0 || r >= doc.ring_point_ends.len() {
    return 0;
  }
  let start: Int = doc.ring_point_starts[r];
  let end: Int = doc.ring_point_ends[r];
  return end - start;
}

/// Total number of coordinates in the document.
/// Params: doc - the document.
/// Returns: doc.xs length, the number all element and ring spans index into.
/// Error case: none.
/// Complexity: O(1).
pub fn wkt_coord_count(doc: &WktDoc) -> Int {
  return doc.xs.len();
}

/// First ordinate (x) text of coordinate `p`.
/// Params: doc - the document; p - zero-based coordinate index.
/// Returns: the coordinate token exactly as parsed; "" when `p` is out of
/// range.
/// Error case: none.
/// Complexity: O(1).
pub fn wkt_x(doc: &WktDoc, p: Int) -> Str {
  if p < 0 || p >= doc.xs.len() {
    return "";
  }
  let v: Str = doc.xs[p];
  return v;
}

/// Second ordinate (y) text of coordinate `p`.
/// Params: doc - the document; p - zero-based coordinate index.
/// Returns: the coordinate token exactly as parsed; "" when `p` is out of
/// range.
/// Error case: none.
/// Complexity: O(1).
pub fn wkt_y(doc: &WktDoc, p: Int) -> Str {
  if p < 0 || p >= doc.ys.len() {
    return "";
  }
  let v: Str = doc.ys[p];
  return v;
}

/// Third ordinate (z) text of coordinate `p`.
/// Params: doc - the document; p - zero-based coordinate index.
/// Returns: the coordinate token exactly as parsed, or "" when the coordinate
/// has no z ordinate or `p` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn wkt_z(doc: &WktDoc, p: Int) -> Str {
  if p < 0 || p >= doc.zs.len() {
    return "";
  }
  let v: Str = doc.zs[p];
  return v;
}

/// Fourth ordinate (m) text of coordinate `p`.
/// Params: doc - the document; p - zero-based coordinate index.
/// Returns: the coordinate token exactly as parsed, or "" when the coordinate
/// has no m ordinate or `p` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn wkt_m(doc: &WktDoc, p: Int) -> Str {
  if p < 0 || p >= doc.ms.len() {
    return "";
  }
  let v: Str = doc.ms[p];
  return v;
}
