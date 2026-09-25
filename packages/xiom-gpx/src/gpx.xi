// XIOM -- xiom.gpx: GPX subset codec (parse and canonical build)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Supported subset (SPEC.md has the grammar, semantics and error catalog):
// the optional <?xml ...?> declaration, a <gpx version creator> root,
// <wpt lat lon> waypoints, <rte> routes, <trk>/<trkseg>/<trkpt lat lon>
// tracks, and the child text elements name/desc/sym/type/ele/time on
// waypoints, routes, tracks and track points. Attribute values are quoted
// (double or single quotes) and entity-decoded: the five predefined entities
// plus validated numeric &#NN; / &#xHH; references. Coordinates are kept as
// integer microdegrees (1e-6 degree, no Float64 anywhere); parsing rounds
// extra fraction digits half away from zero and rejects malformed or
// out-of-range values (latitude -90..90, longitude -180..180). gpx_build
// emits canonical GPX: two-space indentation, double-quoted attributes,
// entities escaped again, empty elements self-closed.
//
// Non-goals: full XML (namespaces, CDATA, comments, DTD, processing
// instructions other than the declaration, <extensions>), <rtept> route
// points, geo math and schema validation.
//
// v0.61.3 notes that shaped this module (same idioms as xiom.xml/xiom.toml):
//   * The document is flat: parallel Vec fields, no Vec[StructType].
//   * Ok/Err for Result[GpxDoc, Str] are constructed only in the leaf
//     helpers _ok_doc/_err_doc (constructing Results inside larger functions
//     miscompiles in this compiler).
//   * Str equality always goes through xiom.string.compare.str_compare
//     (BUG 17: `==` on Str values read from Vec[Str] elements lowers to a
//     pointer comparison) and Vec element reads bind typed locals first.
//   * No FFI: byte output is collected with Vec[UInt8].push and materialized
//     with xiom.string.builder.sb_to_str.

module xiom.gpx

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;
use xiom.convert;

// --------------------------------------------------
//  Node kinds (public document model)
// --------------------------------------------------

// Node kinds stored in GpxDoc.kinds: 0 = gpx root, 1 = wpt, 2 = rte,
// 3 = trk, 4 = trkseg, 5 = trkpt.
// Field kinds stored in GpxDoc.field_kinds: 0 = name, 1 = desc, 2 = sym,
// 3 = type, 4 = ele, 5 = time.

// --------------------------------------------------
//  Byte constants
// --------------------------------------------------

const _X_LT: UInt8 = 60u8;
const _X_GT: UInt8 = 62u8;
const _X_SLASH: UInt8 = 47u8;
const _X_EQ: UInt8 = 61u8;
const _X_BANG: UInt8 = 33u8;
const _X_QUEST: UInt8 = 63u8;
const _X_DQUOTE: UInt8 = 34u8;
const _X_SQUOTE: UInt8 = 39u8;
const _X_HASH: UInt8 = 35u8;
const _X_AMP: UInt8 = 38u8;
const _X_SEMI: UInt8 = 59u8;
const _X_SPACE: UInt8 = 32u8;
const _X_TAB: UInt8 = 9u8;
const _X_CR: UInt8 = 13u8;
const _X_LF: UInt8 = 10u8;
const _X_DOT: UInt8 = 46u8;
const _X_PLUS: UInt8 = 43u8;
const _X_MINUS: UInt8 = 45u8;
const _X_LOWER_X: UInt8 = 120u8;
const _X_UPPER_X: UInt8 = 88u8;

// Sentinels returned by _scan_degrees for values that cannot be stored:
// _GPX_DEG_INVALID for a malformed literal and _GPX_DEG_OVERFLOW for a
// lexically valid value with more than six integer digits. Both are far
// outside every accepted lat/lon range, so callers can classify without
// confusing valid negative coordinates with failure.
const _GPX_DEG_INVALID: Int = -2000000000000;
const _GPX_DEG_OVERFLOW: Int = 1000000000001;

// --------------------------------------------------
//  Document model
// --------------------------------------------------

/// Parsed or constructed GPX document: a flat node list with parallel
/// vectors plus a flat field association list. kinds[i] is a node kind
/// (0 gpx, 1 wpt, 2 rte, 3 trk, 4 trkseg, 5 trkpt); node 0 is the gpx root
/// and parents[0] is -1. lat_udeg[i] / lon_udeg[i] hold waypoint and track
/// point coordinates in microdegrees (0 for every other node).
/// field_owners[k], field_kinds[k] and field_values[k] describe one child
/// text element: the owning node, its kind (0 name, 1 desc, 2 sym, 3 type,
/// 4 ele, 5 time) and the entity-decoded text. version and creator hold the
/// root attributes ("" when absent). Read everything through the accessors
/// below so that out-of-range indices stay safe. Vec[StructType] is not
/// usable in this compiler, hence the flat layout.
pub type GpxDoc = {
  kinds: Vec[Int];
  parents: Vec[Int];
  lat_udeg: Vec[Int];
  lon_udeg: Vec[Int];
  field_owners: Vec[Int];
  field_kinds: Vec[Int];
  field_values: Vec[Str];
  version: Str;
  creator: Str;
}

// Mutable parse state. text/pos are the input cursor; the node and field
// vectors accumulate the flat document; open_names/open_kinds/open_nodes are
// the parallel open-element stacks; leaf_start/leaf_end delimit the raw span
// of the current leaf element's single text run (-1 when none was seen);
// failed/error carry the first failure (the parse loop stops at the first
// false). Element kinds 6..11 are the internal leaf kinds name..time, i.e.
// public field kind = open kind - 6.
type _GpxParser = {
  text: Str;
  pos: Int;
  kinds: Vec[Int];
  parents: Vec[Int];
  lat_udeg: Vec[Int];
  lon_udeg: Vec[Int];
  field_owners: Vec[Int];
  field_kinds: Vec[Int];
  field_values: Vec[Str];
  open_names: Vec[Str];
  open_kinds: Vec[Int];
  open_nodes: Vec[Int];
  have_root: Bool;
  failed: Bool;
  error: Str;
  version: Str;
  creator: Str;
  have_version: Bool;
  have_creator: Bool;
  cur_kind: Int;
  cur_lat: Int;
  cur_lon: Int;
  have_lat: Bool;
  have_lon: Bool;
  self_close: Bool;
  leaf_start: Int;
  leaf_end: Int;
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(d) for Result[GpxDoc, Str].
fn _ok_doc(d: GpxDoc) -> Result[GpxDoc, Str] {
  return Ok(d);
}

// Err(m) for Result[GpxDoc, Str].
fn _err_doc(m: Str) -> Result[GpxDoc, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Byte predicates
// --------------------------------------------------

fn _is_ws(b: UInt8) -> Bool {
  if b == _X_SPACE { return true; }
  if b == _X_TAB { return true; }
  if b == _X_CR { return true; }
  if b == _X_LF { return true; }
  return false;
}

// Byte that terminates a tag or attribute name: whitespace, '<', '>', '/' or
// '='.
fn _is_name_end(b: UInt8) -> Bool {
  if _is_ws(b) { return true; }
  if b == _X_LT { return true; }
  if b == _X_GT { return true; }
  if b == _X_SLASH { return true; }
  if b == _X_EQ { return true; }
  return false;
}

// True when every byte of s[start, end) is XML whitespace.
fn _raw_all_ws(s: Str, start: Int, end: Int) -> Bool {
  var i = start;
  while i < end {
    let b: UInt8 = string.byte_at(s, i);
    if !_is_ws(b) { return false; }
    i = i + 1;
  }
  return true;
}

// --------------------------------------------------
//  Names
// --------------------------------------------------

// Element name of a public node kind or an internal leaf kind.
fn _kind_name(k: Int) -> Str {
  if k == 0 { return "gpx"; }
  if k == 1 { return "wpt"; }
  if k == 2 { return "rte"; }
  if k == 3 { return "trk"; }
  if k == 4 { return "trkseg"; }
  if k == 5 { return "trkpt"; }
  if k == 6 { return "name"; }
  if k == 7 { return "desc"; }
  if k == 8 { return "sym"; }
  if k == 9 { return "type"; }
  if k == 10 { return "ele"; }
  if k == 11 { return "time"; }
  return "";
}

// Kind of an element name: 0..5 structural, 6..11 leaf, -1 unknown.
fn _element_kind(name: Str) -> Int {
  if compare.str_compare(name, "gpx") == 0 { return 0; }
  if compare.str_compare(name, "wpt") == 0 { return 1; }
  if compare.str_compare(name, "rte") == 0 { return 2; }
  if compare.str_compare(name, "trk") == 0 { return 3; }
  if compare.str_compare(name, "trkseg") == 0 { return 4; }
  if compare.str_compare(name, "trkpt") == 0 { return 5; }
  if compare.str_compare(name, "name") == 0 { return 6; }
  if compare.str_compare(name, "desc") == 0 { return 7; }
  if compare.str_compare(name, "sym") == 0 { return 8; }
  if compare.str_compare(name, "type") == 0 { return 9; }
  if compare.str_compare(name, "ele") == 0 { return 10; }
  if compare.str_compare(name, "time") == 0 { return 11; }
  return -1;
}

// Structural placement rule: which child kinds are allowed inside which
// open element kind. Leaves (6..11) belong to wpt/rte/trk/trkpt; trk also
// accepts trkseg, and trkseg accepts trkpt.
fn _placement_ok(parent_kind: Int, child_kind: Int) -> Bool {
  if parent_kind == 0 {
    if child_kind == 1 { return true; }
    if child_kind == 2 { return true; }
    if child_kind == 3 { return true; }
    return false;
  }
  if parent_kind == 3 {
    if child_kind == 4 { return true; }
    return child_kind >= 6 && child_kind <= 11;
  }
  if parent_kind == 4 {
    return child_kind == 5;
  }
  if parent_kind == 1 || parent_kind == 2 || parent_kind == 5 {
    return child_kind >= 6 && child_kind <= 11;
  }
  return false;
}

// --------------------------------------------------
//  Entity decoding
// --------------------------------------------------

// Append the UTF-8 encoding of codepoint `code` (1..0x10FFFF) to out.
fn _push_utf8(out: &mut Vec[UInt8], code: Int) {
  if code <= 127 {
    out.push(code as UInt8);
    return;
  }
  if code <= 2047 {
    out.push((192 + code / 64) as UInt8);
    out.push((128 + code % 64) as UInt8);
    return;
  }
  if code <= 65535 {
    out.push((224 + code / 4096) as UInt8);
    out.push((128 + (code / 64) % 64) as UInt8);
    out.push((128 + code % 64) as UInt8);
    return;
  }
  out.push((240 + code / 262144) as UInt8);
  out.push((128 + (code / 4096) % 64) as UInt8);
  out.push((128 + (code / 64) % 64) as UInt8);
  out.push((128 + code % 64) as UInt8);
}

// Codepoint of a "#NN" or "#xHH" numeric reference body, or -1 when the body
// is malformed, zero, a surrogate or beyond U+10FFFF.
fn _entity_code(body: Str) -> Int {
  let n = body.len();
  if n < 2 { return -1; }
  if string.byte_at(body, 0) != _X_HASH { return -1; }
  var i = 1;
  var base = 10;
  let mark: UInt8 = string.byte_at(body, i);
  if mark == _X_LOWER_X || mark == _X_UPPER_X {
    base = 16;
    i = i + 1;
  }
  if i >= n { return -1; }
  var v = 0;
  while i < n {
    let b: Int = string.byte_at(body, i) as Int;
    var d = -1;
    if b >= 48 && b <= 57 {
      d = b - 48;
    } elif base == 16 && b >= 97 && b <= 102 {
      d = b - 87;
    } elif base == 16 && b >= 65 && b <= 70 {
      d = b - 55;
    } else {
      return -1;
    }
    if d >= base { return -1; }
    v = v * base + d;
    if v > 1114111 { return -1; }
    i = i + 1;
  }
  if v == 0 { return -1; }
  if v >= 55296 && v <= 57343 { return -1; }
  return v;
}

// Decode the entity starting at s[at] (which is '&') into out. Returns the
// number of consumed input bytes, or -1 when the reference is malformed,
// unknown or unterminated.
fn _entity_decode(s: Str, at: Int, end: Int, out: &mut Vec[UInt8]) -> Int {
  var semi = -1;
  var j = at + 1;
  while j < end {
    let b: UInt8 = string.byte_at(s, j);
    if b == _X_SEMI {
      semi = j;
      break;
    }
    if b == _X_AMP { break; }
    j = j + 1;
  }
  if semi < 0 { return -1; }
  let body = string.str_slice(s, at + 1, semi);
  if compare.str_compare(body, "amp") == 0 {
    out.push(_X_AMP);
    return semi - at + 1;
  }
  if compare.str_compare(body, "lt") == 0 {
    out.push(_X_LT);
    return semi - at + 1;
  }
  if compare.str_compare(body, "gt") == 0 {
    out.push(_X_GT);
    return semi - at + 1;
  }
  if compare.str_compare(body, "quot") == 0 {
    out.push(_X_DQUOTE);
    return semi - at + 1;
  }
  if compare.str_compare(body, "apos") == 0 {
    out.push(_X_SQUOTE);
    return semi - at + 1;
  }
  let code = _entity_code(body);
  if code < 0 { return -1; }
  _push_utf8(out, code);
  return semi - at + 1;
}

// Deterministic error for the entity at s[at] (the same scan as
// _entity_decode, used only on failure).
fn _entity_error(s: Str, at: Int, end: Int) -> Str {
  var semi = -1;
  var j = at + 1;
  while j < end {
    let b: UInt8 = string.byte_at(s, j);
    if b == _X_SEMI {
      semi = j;
      break;
    }
    if b == _X_AMP { break; }
    j = j + 1;
  }
  if semi < 0 { return "gpx: unterminated entity"; }
  let body = string.str_slice(s, at + 1, semi);
  return "gpx: bad entity: &" + body + ";";
}

// Entity-decode s[start, end) into a fresh Str. Err("gpx: ...") on the first
// malformed or unterminated reference.
fn _decode_range(s: Str, start: Int, end: Int) -> Result[Str, Str] {
  var out = Vec[UInt8].new();
  var i = start;
  while i < end {
    let b: UInt8 = string.byte_at(s, i);
    if b == _X_AMP {
      let adv = _entity_decode(s, i, end, &mut out);
      if adv < 0 { return Err(_entity_error(s, i, end)); }
      i = i + adv;
    } else {
      out.push(b);
      i = i + 1;
    }
  }
  return Ok(builder.sb_to_str(&out));
}

// --------------------------------------------------
//  Coordinate lexical validation (microdegrees)
// --------------------------------------------------

// Scan a decimal-degree literal: optional '+'/'-', at least one integer
// digit, an optional '.'-fraction, nothing else. Returns the value in
// microdegrees rounded half away from zero, _GPX_DEG_INVALID when malformed,
// or _GPX_DEG_OVERFLOW when the integer part has more than six digits (which
// is out of range for both latitude and longitude).
fn _scan_degrees(s: Str) -> Int {
  let n = s.len();
  if n == 0 { return _GPX_DEG_INVALID; }
  var i = 0;
  var neg = false;
  let b0: UInt8 = string.byte_at(s, 0);
  if b0 == _X_MINUS {
    neg = true;
    i = 1;
  } elif b0 == _X_PLUS {
    i = 1;
  }
  let int_start = i;
  while i < n {
    let b: UInt8 = string.byte_at(s, i);
    if !(b >= 48 && b <= 57) { break; }
    i = i + 1;
  }
  let int_digits = i - int_start;
  if int_digits == 0 { return _GPX_DEG_INVALID; }
  if int_digits > 6 { return _GPX_DEG_OVERFLOW; }
  var frac_start = -1;
  var frac_digits = 0;
  if i < n {
    if string.byte_at(s, i) != _X_DOT { return _GPX_DEG_INVALID; }
    i = i + 1;
    frac_start = i;
    while i < n {
      let b2: UInt8 = string.byte_at(s, i);
      if !(b2 >= 48 && b2 <= 57) { break; }
      i = i + 1;
    }
    frac_digits = i - frac_start;
    if frac_digits == 0 { return _GPX_DEG_INVALID; }
  }
  if i != n { return _GPX_DEG_INVALID; }
  var scaled = 0;
  var k = int_start;
  while k < int_start + int_digits {
    scaled = scaled * 10 + (string.byte_at(s, k) as Int - 48);
    k = k + 1;
  }
  scaled = scaled * 1000000;
  var micro = 0;
  var taken = 0;
  while taken < frac_digits && taken < 6 {
    micro = micro * 10 + (string.byte_at(s, frac_start + taken) as Int - 48);
    taken = taken + 1;
  }
  if frac_digits > 6 {
    let seventh: UInt8 = string.byte_at(s, frac_start + 6);
    if seventh >= 53 { micro = micro + 1; }
  }
  while taken < 6 {
    micro = micro * 10;
    taken = taken + 1;
  }
  scaled = scaled + micro;
  if neg { scaled = 0 - scaled; }
  return scaled;
}

/// Parse a decimal-degree literal into microdegrees (1e-6 degree).
/// Params: text - optional sign, integer digits, optional '.' fraction.
/// Returns: Some(microdegrees) for a value in [-180, 180] (the widest GPX
/// coordinate range); extra fraction digits beyond six are rounded half away
/// from zero. None when the text is malformed (empty, non-decimal, spaces,
/// exponent) or outside [-180, 180].
/// Complexity: O(text length).
pub fn gpx_coord_parse(text: Str) -> Option[Int] {
  let v = _scan_degrees(text);
  if v == _GPX_DEG_INVALID { return None; }
  if v > 180000000 { return None; }
  if v < -180000000 { return None; }
  return Some(v);
}

/// Format microdegrees as a canonical decimal-degree literal.
/// Params: udeg - the microdegree value (any Int).
/// Returns: the shortest exact text with at least one fraction digit, e.g.
/// 0 -> "0.0", 37500000 -> "37.5", -122400000 -> "-122.4". Negative zero is
/// never emitted.
/// Complexity: O(digits).
pub fn gpx_coord_text(udeg: Int) -> Str {
  var m = udeg;
  var neg = false;
  if m < 0 {
    neg = true;
    m = 0 - m;
  }
  let whole = m / 1000000;
  let frac = m % 1000000;
  var out = Vec[UInt8].new();
  if neg && m != 0 {
    out.push(_X_MINUS);
  }
  builder.sb_push_str(&mut out, convert.int_to_string(whole));
  out.push(_X_DOT);
  var digits = Vec[Int].new();
  digits.push(frac / 100000);
  digits.push((frac / 10000) % 10);
  digits.push((frac / 1000) % 10);
  digits.push((frac / 100) % 10);
  digits.push((frac / 10) % 10);
  digits.push(frac % 10);
  var keep = 6;
  while keep > 1 {
    let d: Int = digits[keep - 1];
    if d != 0 { break; }
    keep = keep - 1;
  }
  var k = 0;
  while k < keep {
    let d2: Int = digits[k];
    out.push((48 + d2) as UInt8);
    k = k + 1;
  }
  return builder.sb_to_str(&out);
}

// --------------------------------------------------
//  Parser helpers
// --------------------------------------------------

fn _fail(p: &mut _GpxParser, m: Str) -> Bool {
  p.failed = true;
  p.error = m;
  return false;
}

fn _byte(p: &mut _GpxParser, i: Int) -> UInt8 {
  return string.byte_at(p.text, i);
}

fn _skip_ws(p: &mut _GpxParser) {
  let n = p.text.len();
  while p.pos < n {
    if !_is_ws(_byte(p, p.pos)) { break; }
    p.pos = p.pos + 1;
  }
}

// True when the parent node already owns the field kind (duplicate child).
fn _has_field(p: &mut _GpxParser, owner: Int, fkind: Int) -> Bool {
  var i = 0;
  while i < p.field_owners.len() {
    let o: Int = p.field_owners[i];
    if o == owner {
      let k: Int = p.field_kinds[i];
      if k == fkind { return true; }
    }
    i = i + 1;
  }
  return false;
}

// Append one structural node, returning its index.
fn _push_node(p: &mut _GpxParser, kind: Int, parent: Int, lat: Int, lon: Int) -> Int {
  p.kinds.push(kind);
  p.parents.push(parent);
  p.lat_udeg.push(lat);
  p.lon_udeg.push(lon);
  return p.kinds.len() - 1;
}

// Append one child text element.
fn _push_field(p: &mut _GpxParser, owner: Int, fkind: Int, value: Str) {
  p.field_owners.push(owner);
  p.field_kinds.push(fkind);
  p.field_values.push(value);
}

// Skip a leading <?xml ...?> declaration when present; nothing else may
// precede the root element.
fn _skip_declaration(p: &mut _GpxParser) -> Bool {
  _skip_ws(p);
  let n = p.text.len();
  if p.pos + 1 >= n { return true; }
  if _byte(p, p.pos) != _X_LT { return true; }
  if _byte(p, p.pos + 1) != _X_QUEST { return true; }
  if p.pos + 5 > n { return _fail(p, "gpx: malformed declaration"); }
  if _byte(p, p.pos + 2) != _X_LOWER_X { return _fail(p, "gpx: malformed declaration"); }
  if _byte(p, p.pos + 3) != 109u8 { return _fail(p, "gpx: malformed declaration"); }
  if _byte(p, p.pos + 4) != 108u8 { return _fail(p, "gpx: malformed declaration"); }
  if p.pos + 5 < n {
    let after: UInt8 = _byte(p, p.pos + 5);
    if !_is_ws(after) && after != _X_QUEST {
      return _fail(p, "gpx: malformed declaration");
    }
  }
  var i = p.pos + 5;
  while i + 1 < n {
    if _byte(p, i) == _X_QUEST {
      if _byte(p, i + 1) == _X_GT {
        p.pos = i + 2;
        return true;
      }
    }
    i = i + 1;
  }
  return _fail(p, "gpx: malformed declaration");
}

// Parse attributes after an element name. Values must be quoted; the result
// is validated against p.cur_kind and stored in the parser (version/creator
// for the root, lat/lon for wpt/trkpt, nothing else).
fn _parse_attrs(p: &mut _GpxParser) -> Bool {
  let n = p.text.len();
  loop {
    _skip_ws(p);
    if p.pos >= n { return _fail(p, "gpx: premature end of input"); }
    let b: UInt8 = _byte(p, p.pos);
    if b == _X_GT {
      p.pos = p.pos + 1;
      return true;
    }
    if b == _X_SLASH {
      p.pos = p.pos + 1;
      _skip_ws(p);
      if p.pos >= n { return _fail(p, "gpx: premature end of input"); }
      if _byte(p, p.pos) != _X_GT { return _fail(p, "gpx: malformed tag"); }
      p.pos = p.pos + 1;
      p.self_close = true;
      return true;
    }
    let an_start = p.pos;
    while p.pos < n {
      if _is_name_end(_byte(p, p.pos)) { break; }
      p.pos = p.pos + 1;
    }
    if p.pos == an_start { return _fail(p, "gpx: malformed attribute"); }
    let aname = string.str_slice(p.text, an_start, p.pos);
    _skip_ws(p);
    if p.pos >= n { return _fail(p, "gpx: premature end of input"); }
    if _byte(p, p.pos) != _X_EQ { return _fail(p, "gpx: malformed attribute"); }
    p.pos = p.pos + 1;
    _skip_ws(p);
    if p.pos >= n { return _fail(p, "gpx: premature end of input"); }
    let q: UInt8 = _byte(p, p.pos);
    if q != _X_DQUOTE && q != _X_SQUOTE {
      return _fail(p, "gpx: unquoted attribute value: " + aname);
    }
    p.pos = p.pos + 1;
    let v_start = p.pos;
    var bad_lt = false;
    while p.pos < n {
      let vb: UInt8 = _byte(p, p.pos);
      if vb == q { break; }
      if vb == _X_LT {
        bad_lt = true;
        break;
      }
      p.pos = p.pos + 1;
    }
    if p.pos >= n { return _fail(p, "gpx: premature end of input"); }
    if bad_lt { return _fail(p, "gpx: malformed attribute"); }
    let raw = string.str_slice(p.text, v_start, p.pos);
    p.pos = p.pos + 1;
    let dr = _decode_range(raw, 0, raw.len());
    var value = "";
    match dr {
      Ok(v) => { value = v; },
      Err(e) => { return _fail(p, e); },
    }
    if p.cur_kind == 0 {
      if compare.str_compare(aname, "version") == 0 {
        if p.have_version { return _fail(p, "gpx: duplicate attribute: version"); }
        p.have_version = true;
        p.version = value;
      } elif compare.str_compare(aname, "creator") == 0 {
        if p.have_creator { return _fail(p, "gpx: duplicate attribute: creator"); }
        p.have_creator = true;
        p.creator = value;
      } else {
        return _fail(p, "gpx: unexpected attribute: " + aname);
      }
    } elif p.cur_kind == 1 || p.cur_kind == 5 {
      if compare.str_compare(aname, "lat") == 0 {
        if p.have_lat { return _fail(p, "gpx: duplicate attribute: lat"); }
        let cv = _scan_degrees(value);
        if cv == _GPX_DEG_INVALID { return _fail(p, "gpx: malformed latitude: " + value); }
        if cv > 90000000 || cv < -90000000 { return _fail(p, "gpx: latitude out of range: " + value); }
        p.have_lat = true;
        p.cur_lat = cv;
      } elif compare.str_compare(aname, "lon") == 0 {
        if p.have_lon { return _fail(p, "gpx: duplicate attribute: lon"); }
        let cv2 = _scan_degrees(value);
        if cv2 == _GPX_DEG_INVALID { return _fail(p, "gpx: malformed longitude: " + value); }
        if cv2 > 180000000 || cv2 < -180000000 { return _fail(p, "gpx: longitude out of range: " + value); }
        p.have_lon = true;
        p.cur_lon = cv2;
      } else {
        return _fail(p, "gpx: unexpected attribute: " + aname);
      }
    } else {
      return _fail(p, "gpx: unexpected attribute: " + aname);
    }
  }
  return true;
}

// Consume a start tag (p.pos at the first name byte), validate placement,
// register the node (or leaf field) and push it on the open stack unless it
// is self-closing.
fn _start_tag(p: &mut _GpxParser) -> Bool {
  let n = p.text.len();
  let name_start = p.pos;
  while p.pos < n {
    if _is_name_end(_byte(p, p.pos)) { break; }
    p.pos = p.pos + 1;
  }
  if p.pos == name_start { return _fail(p, "gpx: malformed tag"); }
  let name = string.str_slice(p.text, name_start, p.pos);
  let kind = _element_kind(name);
  if kind < 0 { return _fail(p, "gpx: unknown element: <" + name + ">"); }
  var parent_node = -1;
  if p.open_kinds.len() == 0 {
    if p.have_root { return _fail(p, "gpx: multiple root elements"); }
    if kind != 0 { return _fail(p, "gpx: wrong root element: <" + name + ">"); }
  } else {
    let parent_kind: Int = p.open_kinds[p.open_kinds.len() - 1];
    parent_node = p.open_nodes[p.open_nodes.len() - 1];
    if !_placement_ok(parent_kind, kind) {
      return _fail(p, "gpx: element not allowed here: <" + name + ">");
    }
    if kind >= 6 {
      if _has_field(p, parent_node, kind - 6) {
        return _fail(p, "gpx: duplicate element: <" + name + ">");
      }
    }
  }
  p.cur_kind = kind;
  p.have_lat = false;
  p.have_lon = false;
  p.self_close = false;
  if !_parse_attrs(p) { return false; }
  if kind == 1 || kind == 5 {
    if !p.have_lat { return _fail(p, "gpx: missing latitude attribute"); }
    if !p.have_lon { return _fail(p, "gpx: missing longitude attribute"); }
  }
  var node = -1;
  if kind <= 5 {
    node = _push_node(p, kind, parent_node, p.cur_lat, p.cur_lon);
  }
  if kind == 0 { p.have_root = true; }
  if p.self_close {
    if kind >= 6 { _push_field(p, parent_node, kind - 6, ""); }
    return true;
  }
  p.open_names.push(name);
  p.open_kinds.push(kind);
  if kind >= 6 {
    p.open_nodes.push(parent_node);
    p.leaf_start = -1;
    p.leaf_end = -1;
  } else {
    p.open_nodes.push(node);
  }
  return true;
}

// Consume a closing tag (p.pos at the first name byte after "</"), pop the
// open element and finalize a leaf field's decoded text.
fn _close_tag(p: &mut _GpxParser) -> Bool {
  let n = p.text.len();
  let name_start = p.pos;
  while p.pos < n {
    if _is_name_end(_byte(p, p.pos)) { break; }
    p.pos = p.pos + 1;
  }
  if p.pos == name_start { return _fail(p, "gpx: malformed tag"); }
  let name = string.str_slice(p.text, name_start, p.pos);
  _skip_ws(p);
  if p.pos >= n { return _fail(p, "gpx: premature end of input"); }
  if _byte(p, p.pos) != _X_GT { return _fail(p, "gpx: malformed tag"); }
  p.pos = p.pos + 1;
  if p.open_names.len() == 0 {
    return _fail(p, "gpx: unexpected closing tag: </" + name + ">");
  }
  let top_name: Str = p.open_names[p.open_names.len() - 1];
  if compare.str_compare(top_name, name) != 0 {
    return _fail(p, "gpx: mismatched closing tag: expected </" + top_name + ">, found </" + name + ">");
  }
  let top_kind: Int = p.open_kinds[p.open_kinds.len() - 1];
  let top_node: Int = p.open_nodes[p.open_nodes.len() - 1];
  p.open_names.pop();
  p.open_kinds.pop();
  p.open_nodes.pop();
  if top_kind >= 6 {
    var val = "";
    if p.leaf_start >= 0 {
      let dr = _decode_range(p.text, p.leaf_start, p.leaf_end);
      match dr {
        Ok(v) => { val = v; },
        Err(e) => { return _fail(p, e); },
      }
    }
    _push_field(p, top_node, top_kind - 6, val);
  }
  return true;
}

// Consume markup after '<'.
fn _consume_markup(p: &mut _GpxParser) -> Bool {
  let n = p.text.len();
  if p.pos >= n { return _fail(p, "gpx: premature end of input"); }
  let b: UInt8 = _byte(p, p.pos);
  if b == _X_SLASH {
    p.pos = p.pos + 1;
    return _close_tag(p);
  }
  if b == _X_QUEST || b == _X_BANG {
    return _fail(p, "gpx: unsupported markup");
  }
  return _start_tag(p);
}

// Consume character data up to the next '<' or EOF. Document-level text must
// be whitespace; container text must be whitespace; a leaf's single text run
// is remembered as a raw span and decoded when the leaf closes.
fn _consume_text(p: &mut _GpxParser) -> Bool {
  let n = p.text.len();
  let start = p.pos;
  var i = p.pos;
  while i < n {
    if _byte(p, i) == _X_LT { break; }
    i = i + 1;
  }
  p.pos = i;
  if p.open_kinds.len() == 0 {
    if _raw_all_ws(p.text, start, i) { return true; }
    return _fail(p, "gpx: text outside elements");
  }
  let top: Int = p.open_kinds[p.open_kinds.len() - 1];
  if top >= 6 {
    p.leaf_start = start;
    p.leaf_end = i;
    return true;
  }
  if _raw_all_ws(p.text, start, i) { return true; }
  return _fail(p, "gpx: unexpected text in <" + _kind_name(top) + ">");
}

// --------------------------------------------------
//  Public parsing API
// --------------------------------------------------

/// Parse a GPX document in the supported subset.
/// Params: text - the whole document as one Str.
/// Returns: Ok(doc) with the flat node model (node 0 is the gpx root).
/// Error case: Err("gpx: ...") on the first malformed construct; see SPEC.md
/// for the catalog (declaration, unknown/misplaced elements, attribute
/// quoting and duplicates, missing or invalid coordinates, entities,
/// mismatched closing tags, unexpected text, premature end of input).
/// Complexity: O(input length).
pub fn gpx_parse(text: Str) -> Result[GpxDoc, Str] {
  var p = _GpxParser{
    text: text; pos: 0;
    kinds: Vec[Int].new(); parents: Vec[Int].new();
    lat_udeg: Vec[Int].new(); lon_udeg: Vec[Int].new();
    field_owners: Vec[Int].new(); field_kinds: Vec[Int].new();
    field_values: Vec[Str].new();
    open_names: Vec[Str].new(); open_kinds: Vec[Int].new(); open_nodes: Vec[Int].new();
    have_root: false; failed: false; error: "";
    version: ""; creator: ""; have_version: false; have_creator: false;
    cur_kind: -1; cur_lat: 0; cur_lon: 0; have_lat: false; have_lon: false;
    self_close: false; leaf_start: -1; leaf_end: -1;
  };
  if !_skip_declaration(&mut p) { return _err_doc(p.error); }
  let n = text.len();
  while p.pos < n {
    let b: UInt8 = _byte(&mut p, p.pos);
    if b == _X_LT {
      p.pos = p.pos + 1;
      if !_consume_markup(&mut p) { return _err_doc(p.error); }
    } else {
      if !_consume_text(&mut p) { return _err_doc(p.error); }
    }
  }
  if p.open_kinds.len() > 0 { return _err_doc("gpx: premature end of input"); }
  if !p.have_root { return _err_doc("gpx: premature end of input"); }
  return _ok_doc(GpxDoc{
    kinds: p.kinds; parents: p.parents;
    lat_udeg: p.lat_udeg; lon_udeg: p.lon_udeg;
    field_owners: p.field_owners; field_kinds: p.field_kinds;
    field_values: p.field_values;
    version: p.version; creator: p.creator;
  });
}

// --------------------------------------------------
//  Document accessors
// --------------------------------------------------

/// Number of nodes, including the gpx root.
/// Params: d - the document.
/// Returns: d.kinds.len(); a document always has at least the root.
/// Complexity: O(1).
pub fn gpx_node_count(d: &GpxDoc) -> Int {
  return d.kinds.len();
}

/// Node kind: 0 gpx, 1 wpt, 2 rte, 3 trk, 4 trkseg, 5 trkpt.
/// Params: d - the document; node - the node index.
/// Returns: the kind, or -1 when node is out of range.
/// Complexity: O(1).
pub fn gpx_kind(d: &GpxDoc, node: Int) -> Int {
  if node < 0 || node >= d.kinds.len() { return -1; }
  let k: Int = d.kinds[node];
  return k;
}

/// Parent node index of a node.
/// Params: d - the document; node - the node index.
/// Returns: the parent index (-1 for the root), or -2 when node is out of
/// range.
/// Complexity: O(1).
pub fn gpx_parent(d: &GpxDoc, node: Int) -> Int {
  if node < 0 || node >= d.parents.len() { return -2; }
  let v: Int = d.parents[node];
  return v;
}

/// Root attribute `version` ("" when the source had none).
/// Params: d - the document.
/// Returns: the stored version text (entity-decoded).
/// Complexity: O(1).
pub fn gpx_version(d: &GpxDoc) -> Str {
  return d.version;
}

/// Root attribute `creator` ("" when the source had none).
/// Params: d - the document.
/// Returns: the stored creator text (entity-decoded).
/// Complexity: O(1).
pub fn gpx_creator(d: &GpxDoc) -> Str {
  return d.creator;
}

/// Latitude of a waypoint or track point, in microdegrees.
/// Params: d - the document; node - the node index.
/// Returns: Some(microdegrees) for wpt/trkpt nodes; None for every other
/// kind or an out-of-range index.
/// Complexity: O(1).
pub fn gpx_lat_udeg(d: &GpxDoc, node: Int) -> Option[Int] {
  if node < 0 || node >= d.kinds.len() { return None; }
  let k: Int = d.kinds[node];
  if k != 1 && k != 5 { return None; }
  let v: Int = d.lat_udeg[node];
  return Some(v);
}

/// Longitude of a waypoint or track point, in microdegrees.
/// Params: d - the document; node - the node index.
/// Returns: Some(microdegrees) for wpt/trkpt nodes; None for every other
/// kind or an out-of-range index.
/// Complexity: O(1).
pub fn gpx_lon_udeg(d: &GpxDoc, node: Int) -> Option[Int] {
  if node < 0 || node >= d.kinds.len() { return None; }
  let k: Int = d.kinds[node];
  if k != 1 && k != 5 { return None; }
  let v: Int = d.lon_udeg[node];
  return Some(v);
}

/// Direct child text element of a node.
/// Params: d - the document; node - the node index; field - the field kind
/// (0 name, 1 desc, 2 sym, 3 type, 4 ele, 5 time).
/// Returns: Some(decoded text) for the first matching field (an explicitly
/// empty element yields Some("")); None when the node has no such field or
/// an index is out of range. Duplicate fields are rejected at parse time.
/// Complexity: O(fields).
pub fn gpx_field(d: &GpxDoc, node: Int, field: Int) -> Option[Str] {
  if field < 0 || field > 5 { return None; }
  var i = 0;
  while i < d.field_owners.len() {
    let o: Int = d.field_owners[i];
    if o == node {
      let k: Int = d.field_kinds[i];
      if k == field {
        let s: Str = d.field_values[i];
        return Some(s);
      }
    }
    i = i + 1;
  }
  return None;
}

/// True when the node has the given child text element.
/// Params: d - the document; node - the node index; field - the field kind.
/// Returns: true when gpx_field would return Some.
/// Complexity: O(fields).
pub fn gpx_has_field(d: &GpxDoc, node: Int, field: Int) -> Bool {
  match gpx_field(d, node, field) {
    Some(_) => { return true; },
    None => { return false; },
  }
  return false;
}

/// Number of child text elements of a node.
/// Params: d - the document; node - the node index.
/// Returns: the count; 0 for out-of-range nodes.
/// Complexity: O(fields).
pub fn gpx_field_count(d: &GpxDoc, node: Int) -> Int {
  var count = 0;
  var i = 0;
  while i < d.field_owners.len() {
    let o: Int = d.field_owners[i];
    if o == node { count = count + 1; }
    i = i + 1;
  }
  return count;
}

/// All nodes of one kind, in document order.
/// Params: d - the document; kind - the node kind (0..5).
/// Returns: their node indices (empty when nothing matches).
/// Complexity: O(nodes).
pub fn gpx_nodes_of_kind(d: &GpxDoc, kind: Int) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 0;
  while i < d.kinds.len() {
    let k: Int = d.kinds[i];
    if k == kind { out.push(i); }
    i = i + 1;
  }
  return out;
}

/// Direct children of a node, in document order (elements only; child text is
/// reached through gpx_field).
/// Params: d - the document; node - the node index.
/// Returns: their node indices (empty for out-of-range nodes and leaves).
/// Complexity: O(nodes).
pub fn gpx_children(d: &GpxDoc, node: Int) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 0;
  while i < d.parents.len() {
    let par: Int = d.parents[i];
    if par == node { out.push(i); }
    i = i + 1;
  }
  return out;
}

// --------------------------------------------------
//  Builder (from-scratch construction)
// --------------------------------------------------

/// Create an empty document with a gpx root (node 0).
/// Params: version / creator - stored root attributes; gpx_build emits them
/// verbatim, so pass "" to emit empty attributes.
/// Returns: a document with exactly the root node.
/// Complexity: O(1).
pub fn gpx_new(version: Str, creator: Str) -> GpxDoc {
  var d = GpxDoc{
    kinds: Vec[Int].new(); parents: Vec[Int].new();
    lat_udeg: Vec[Int].new(); lon_udeg: Vec[Int].new();
    field_owners: Vec[Int].new(); field_kinds: Vec[Int].new();
    field_values: Vec[Str].new();
    version: version; creator: creator;
  };
  d.kinds.push(0);
  d.parents.push(-1);
  d.lat_udeg.push(0);
  d.lon_udeg.push(0);
  return d;
}

/// Append a waypoint.
/// Params: d - the document; lat_udeg / lon_udeg - microdegrees, latitude in
/// [-90e6, 90e6], longitude in [-180e6, 180e6].
/// Returns: the new node index, or -1 when a coordinate is out of range.
/// Complexity: O(1).
pub fn gpx_add_waypoint(d: &mut GpxDoc, lat_udeg: Int, lon_udeg: Int) -> Int {
  if lat_udeg > 90000000 || lat_udeg < -90000000 { return -1; }
  if lon_udeg > 180000000 || lon_udeg < -180000000 { return -1; }
  let idx = d.kinds.len();
  d.kinds.push(1);
  d.parents.push(0);
  d.lat_udeg.push(lat_udeg);
  d.lon_udeg.push(lon_udeg);
  return idx;
}

/// Append a route under the root.
/// Params: d - the document.
/// Returns: the new node index.
/// Complexity: O(1).
pub fn gpx_add_route(d: &mut GpxDoc) -> Int {
  let idx = d.kinds.len();
  d.kinds.push(2);
  d.parents.push(0);
  d.lat_udeg.push(0);
  d.lon_udeg.push(0);
  return idx;
}

/// Append a track under the root.
/// Params: d - the document.
/// Returns: the new node index.
/// Complexity: O(1).
pub fn gpx_add_track(d: &mut GpxDoc) -> Int {
  let idx = d.kinds.len();
  d.kinds.push(3);
  d.parents.push(0);
  d.lat_udeg.push(0);
  d.lon_udeg.push(0);
  return idx;
}

/// Append a track segment to an existing track.
/// Params: d - the document; track - the index of a trk node.
/// Returns: the new node index, or -1 when track is not a trk node.
/// Complexity: O(1).
pub fn gpx_add_segment(d: &mut GpxDoc, track: Int) -> Int {
  if track < 0 || track >= d.kinds.len() { return -1; }
  let k: Int = d.kinds[track];
  if k != 3 { return -1; }
  let idx = d.kinds.len();
  d.kinds.push(4);
  d.parents.push(track);
  d.lat_udeg.push(0);
  d.lon_udeg.push(0);
  return idx;
}

/// Append a track point to an existing segment.
/// Params: d - the document; segment - the index of a trkseg node;
/// lat_udeg / lon_udeg - microdegrees within the GPX coordinate ranges.
/// Returns: the new node index, or -1 when segment is not a trkseg node or
/// a coordinate is out of range.
/// Complexity: O(1).
pub fn gpx_add_trackpoint(d: &mut GpxDoc, segment: Int, lat_udeg: Int, lon_udeg: Int) -> Int {
  if segment < 0 || segment >= d.kinds.len() { return -1; }
  let k: Int = d.kinds[segment];
  if k != 4 { return -1; }
  if lat_udeg > 90000000 || lat_udeg < -90000000 { return -1; }
  if lon_udeg > 180000000 || lon_udeg < -180000000 { return -1; }
  let idx = d.kinds.len();
  d.kinds.push(5);
  d.parents.push(segment);
  d.lat_udeg.push(lat_udeg);
  d.lon_udeg.push(lon_udeg);
  return idx;
}

/// Set (or replace) a child text element on a node.
/// Params: d - the document; node - the node index; field - the field kind
/// (0 name, 1 desc, 2 sym, 3 type, 4 ele, 5 time); value - the text, stored
/// verbatim (gpx_build escapes it).
/// Returns: true when the node accepts fields (wpt/rte/trk/trkpt) and the
/// field kind is valid; false otherwise (no change). Setting a field twice
/// replaces the first value.
/// Complexity: O(fields).
pub fn gpx_set_field(d: &mut GpxDoc, node: Int, field: Int, value: Str) -> Bool {
  if field < 0 || field > 5 { return false; }
  if node < 0 || node >= d.kinds.len() { return false; }
  let k: Int = d.kinds[node];
  if k != 1 && k != 2 && k != 3 && k != 5 { return false; }
  var i = 0;
  while i < d.field_owners.len() {
    let o: Int = d.field_owners[i];
    if o == node {
      let fk: Int = d.field_kinds[i];
      if fk == field {
        d.field_values[i] = value;
        return true;
      }
    }
    i = i + 1;
  }
  d.field_owners.push(node);
  d.field_kinds.push(field);
  d.field_values.push(value);
  return true;
}

// --------------------------------------------------
//  Canonical serialization
// --------------------------------------------------

// Escape &, < and > in element text.
fn _escape_text(s: Str) -> Str {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < s.len() {
    let b: UInt8 = string.byte_at(s, i);
    if b == _X_AMP {
      builder.sb_push_str(&mut out, "&amp;");
    } elif b == _X_LT {
      builder.sb_push_str(&mut out, "&lt;");
    } elif b == _X_GT {
      builder.sb_push_str(&mut out, "&gt;");
    } else {
      out.push(b);
    }
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}

// Escape &, <, > and " in double-quoted attribute values.
fn _escape_attr(s: Str) -> Str {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < s.len() {
    let b: UInt8 = string.byte_at(s, i);
    if b == _X_AMP {
      builder.sb_push_str(&mut out, "&amp;");
    } elif b == _X_LT {
      builder.sb_push_str(&mut out, "&lt;");
    } elif b == _X_GT {
      builder.sb_push_str(&mut out, "&gt;");
    } elif b == _X_DQUOTE {
      builder.sb_push_str(&mut out, "&quot;");
    } else {
      out.push(b);
    }
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}

// Append 2*level spaces.
fn _push_indent(out: &mut Vec[UInt8], level: Int) {
  var i = 0;
  while i < level * 2 {
    out.push(_X_SPACE);
    i = i + 1;
  }
}

fn _field_of(d: &GpxDoc, node: Int, field: Int) -> Option[Str] {
  var i = 0;
  while i < d.field_owners.len() {
    let o: Int = d.field_owners[i];
    if o == node {
      let k: Int = d.field_kinds[i];
      if k == field {
        let s: Str = d.field_values[i];
        return Some(s);
      }
    }
    i = i + 1;
  }
  return None;
}

// Emit one element with its fields (canonical order: name, desc, sym, type,
// ele, time) and its children, indented by 2*indent spaces. first/next are
// the precomputed child links (node 0 is the root).
fn _emit_element(d: &GpxDoc, node: Int, indent: Int, first: &Vec[Int], next: &Vec[Int], out: &mut Vec[UInt8]) {
  let kind: Int = d.kinds[node];
  if kind < 0 || kind > 5 { return; }
  _push_indent(out, indent);
  builder.sb_push_str(out, "<");
  builder.sb_push_str(out, _kind_name(kind));
  if kind == 0 {
    builder.sb_push_str(out, " version=\"");
    builder.sb_push_str(out, _escape_attr(d.version));
    builder.sb_push_str(out, "\" creator=\"");
    builder.sb_push_str(out, _escape_attr(d.creator));
    builder.sb_push_str(out, "\"");
  } elif kind == 1 || kind == 5 {
    builder.sb_push_str(out, " lat=\"");
    builder.sb_push_str(out, gpx_coord_text(d.lat_udeg[node]));
    builder.sb_push_str(out, "\" lon=\"");
    builder.sb_push_str(out, gpx_coord_text(d.lon_udeg[node]));
    builder.sb_push_str(out, "\"");
  }
  var fields = 0;
  if kind == 1 || kind == 2 || kind == 3 || kind == 5 {
    fields = gpx_field_count(d, node);
  }
  let first_child: Int = first[node];
  if fields == 0 && first_child < 0 {
    builder.sb_push_str(out, "/>\n");
    return;
  }
  builder.sb_push_str(out, ">\n");
  var f = 0;
  while f < 6 {
    let fv = _field_of(d, node, f);
    match fv {
      Some(text) => {
        _push_indent(out, indent + 1);
        builder.sb_push_str(out, "<");
        builder.sb_push_str(out, _kind_name(6 + f));
        builder.sb_push_str(out, ">");
        builder.sb_push_str(out, _escape_text(text));
        builder.sb_push_str(out, "</");
        builder.sb_push_str(out, _kind_name(6 + f));
        builder.sb_push_str(out, ">\n");
      },
      None => {},
    }
    f = f + 1;
  }
  var c = first_child;
  while c >= 0 {
    _emit_element(d, c, indent + 1, first, next, out);
    let following: Int = next[c];
    c = following;
  }
  _push_indent(out, indent);
  builder.sb_push_str(out, "</");
  builder.sb_push_str(out, _kind_name(kind));
  builder.sb_push_str(out, ">\n");
}

/// Serialize a document as canonical GPX text.
/// Params: d - a document from gpx_parse or gpx_new.
/// Returns: the canonical text: an <?xml?> declaration line, then the root
/// and its nodes indented with two spaces per level, double-quoted
/// attributes, escaped text, a trailing newline, and self-closed empty
/// elements. Field order is name, desc, sym, type, ele, time. "" when the
/// document has no root node.
/// Complexity: O(nodes + fields + text bytes).
pub fn gpx_build(d: &GpxDoc) -> Str {
  let n = d.kinds.len();
  if n == 0 { return ""; }
  var first = Vec[Int].new();
  var next = Vec[Int].new();
  var last = Vec[Int].new();
  var i = 0;
  while i < n {
    first.push(-1);
    next.push(-1);
    last.push(-1);
    i = i + 1;
  }
  var j = 1;
  while j < n {
    let par: Int = d.parents[j];
    if par >= 0 && par < n {
      let lc: Int = last[par];
      if lc < 0 {
        first[par] = j;
      } else {
        next[lc] = j;
      }
      last[par] = j;
    }
    j = j + 1;
  }
  var out = Vec[UInt8].new();
  builder.sb_push_str(&mut out, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
  _emit_element(d, 0, 0, &first, &next, &mut out);
  return builder.sb_to_str(&out);
}
