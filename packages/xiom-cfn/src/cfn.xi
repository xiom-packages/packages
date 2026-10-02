// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// XIOM -- xiom.cfn: AWS CloudFormation templating and stack-lifecycle model.
// Port task: promote the xiom.cfn placeholder to a real, tested, pure-XIOM
// package. This is a deterministic MODEL of CloudFormation -- no AWS calls,
// no networking, no clock, no FFI, no file I/O.
//
// Contents:
//   * JSON-ish template parsing. A hand-rolled byte scanner parses a strict
//     JSON subset (objects, arrays, strings with the standard escapes plus
//     BMP \uXXXX, integer numbers, booleans, null) into a flat arena
//     (JsonDoc) of parallel vectors -- never a Vec[StructType]. See the
//     header of section 3 for the exact subset.
//   * Template validation and accessors: Resources is required and every
//     resource needs a string Type; Parameters, Mappings, Conditions and
//     Outputs are read on demand.
//   * Intrinsic-function evaluation over the subset Ref, Fn::GetAtt,
//     Fn::Join, Fn::Sub, Fn::Select, Fn::Split, Fn::If, Fn::Equals and
//     Fn::FindInMap, with a bounded resolution depth (CFN_MAX_DEPTH) and
//     trail-based cycle rejection for condition chains.
//   * Parameter and output handling: effective values (override > default),
//     static validation (unknown/missing/Number), output values,
//     descriptions and export names.
//   * Stack lifecycle state machine: CREATE / UPDATE / DELETE plus the
//     rollback states, driven by explicit events; every transition is
//     recorded in a history trace.
//   * Change sets: resource diff classification ADD / REMOVE / MODIFY /
//     NONE with type-change replacement flags.
//
// Language notes (XIOM v0.62.2) that shaped this module:
//   * Free functions only; all state lives in value structs.
//   * Ok/Err are constructed only inside the tiny leaf helpers _doc_ok,
//     _doc_err, _str_ok, _str_err, _bool_ok, _bool_err, _cv_ok, _cv_err,
//     _stack_ok, _stack_err (constructing Results inside larger functions
//     miscompiles in this compiler).
//   * Str equality goes through xiom.string.compare.str_compare (`==` on Str
//     values read from Vec[Str] elements lowers to a pointer comparison).
//   * Every byte read is widened and masked ((b as Int) & 0xFF) by the _byte
//     helper before any comparison (byte comparisons at >= 128 miscompile).
//   * Vec[Int]/Vec[Str] element reads use typed `let` bindings.
//   * No Vec[StructType] and no Vec[Float64]: the JSON tree is an arena of
//     parallel vectors and all numbers are Int or Str.
//   * Character construction for decoded \uXXXX escapes goes through
//     xiom.convert.int_to_char + xiom.convert.tostring.to_string_char.
//   * JSON parsing returns JsonScan structs (not Result); only the public
//     json_parse / cfn_template_parse wrap a struct in a Result leaf.

module xiom.cfn

use xiom.string;
use xiom.string.compare;
use xiom.convert;
use xiom.convert.tostring;

// ---------------------------------------------------------------------------
// Public constants
// ---------------------------------------------------------------------------

/// Maximum JSON nesting depth and maximum intrinsic resolution depth.
pub const CFN_MAX_DEPTH: Int = 64;

/// Sentinel for "no node" / "not found".
pub const CFN_NONE: Int = -1;

/// JSON node kind: null.
pub const JSON_NULL: Int = 0;
/// JSON node kind: boolean.
pub const JSON_BOOL: Int = 1;
/// JSON node kind: integer number.
pub const JSON_INT: Int = 2;
/// JSON node kind: string.
pub const JSON_STR: Int = 3;
/// JSON node kind: array.
pub const JSON_ARR: Int = 4;
/// JSON node kind: object.
pub const JSON_OBJ: Int = 5;

/// Resolved value kind: scalar string.
pub const CFN_SCALAR: Int = 0;
/// Resolved value kind: list of scalar strings.
pub const CFN_LIST: Int = 1;

/// Parameter type name: a plain string.
pub const CFN_PARAM_STRING: Str = "String";
/// Parameter type name: an integer number.
pub const CFN_PARAM_NUMBER: Str = "Number";
/// Parameter type name: a comma-separated list.
pub const CFN_PARAM_LIST: Str = "CommaDelimitedList";

// Stack states (0..15).
/// Stack state: the model-only initial state (no deployment yet).
pub const STACK_NOT_CREATED: Int = 0;
/// Stack state: CREATE_IN_PROGRESS.
pub const STACK_CREATE_IN_PROGRESS: Int = 1;
/// Stack state: CREATE_COMPLETE.
pub const STACK_CREATE_COMPLETE: Int = 2;
/// Stack state: CREATE_FAILED (no rollback was attempted).
pub const STACK_CREATE_FAILED: Int = 3;
/// Stack state: ROLLBACK_IN_PROGRESS.
pub const STACK_ROLLBACK_IN_PROGRESS: Int = 4;
/// Stack state: ROLLBACK_COMPLETE.
pub const STACK_ROLLBACK_COMPLETE: Int = 5;
/// Stack state: ROLLBACK_FAILED.
pub const STACK_ROLLBACK_FAILED: Int = 6;
/// Stack state: UPDATE_IN_PROGRESS.
pub const STACK_UPDATE_IN_PROGRESS: Int = 7;
/// Stack state: UPDATE_COMPLETE.
pub const STACK_UPDATE_COMPLETE: Int = 8;
/// Stack state: UPDATE_ROLLBACK_IN_PROGRESS.
pub const STACK_UPDATE_ROLLBACK_IN_PROGRESS: Int = 9;
/// Stack state: UPDATE_ROLLBACK_COMPLETE.
pub const STACK_UPDATE_ROLLBACK_COMPLETE: Int = 10;
/// Stack state: UPDATE_ROLLBACK_FAILED.
pub const STACK_UPDATE_ROLLBACK_FAILED: Int = 11;
/// Stack state: DELETE_IN_PROGRESS.
pub const STACK_DELETE_IN_PROGRESS: Int = 12;
/// Stack state: DELETE_COMPLETE.
pub const STACK_DELETE_COMPLETE: Int = 13;
/// Stack state: DELETE_FAILED.
pub const STACK_DELETE_FAILED: Int = 14;
/// Stack state: REVIEW_IN_PROGRESS (a change set is under review).
pub const STACK_REVIEW_IN_PROGRESS: Int = 15;

// Stack events.
/// Stack event: begin a create (or execute a create change set).
pub const STACK_EV_CREATE_BEGIN: Int = 1;
/// Stack event: begin an update (or execute an update change set).
pub const STACK_EV_UPDATE_BEGIN: Int = 2;
/// Stack event: begin a delete.
pub const STACK_EV_DELETE_BEGIN: Int = 3;
/// Stack event: the in-progress operation succeeded.
pub const STACK_EV_SUCCEED: Int = 4;
/// Stack event: the in-progress operation failed.
pub const STACK_EV_FAIL: Int = 5;
/// Stack event: put a not-yet-created stack under change-set review.
pub const STACK_EV_REVIEW_BEGIN: Int = 6;

// Change kinds.
/// Change classification: the resource is unchanged.
pub const CHANGE_NONE: Int = 0;
/// Change classification: the resource is new in the target template.
pub const CHANGE_ADD: Int = 1;
/// Change classification: the resource was removed from the target template.
pub const CHANGE_REMOVE: Int = 2;
/// Change classification: the resource exists in both but differs.
pub const CHANGE_MODIFY: Int = 3;

// ---------------------------------------------------------------------------
// Byte constants (widened Int values; always read through _byte)
// ---------------------------------------------------------------------------

const _B_TAB: Int = 9;
const _B_LF: Int = 10;
const _B_CR: Int = 13;
const _B_SPACE: Int = 32;
const _B_BANG: Int = 33;
const _B_QUOTE: Int = 34;
const _B_DOLLAR: Int = 36;
const _B_PLUS: Int = 43;
const _B_COMMA: Int = 44;
const _B_MINUS: Int = 45;
const _B_DOT: Int = 46;
const _B_SLASH: Int = 47;
const _B_ZERO: Int = 48;
const _B_NINE: Int = 57;
const _B_COLON: Int = 58;
const _B_UPPER_E: Int = 69;
const _B_LBRACKET: Int = 91;
const _B_BACKSLASH: Int = 92;
const _B_RBRACKET: Int = 93;
const _B_LOWER_B: Int = 98;
const _B_LOWER_E: Int = 101;
const _B_LOWER_F: Int = 102;
const _B_LOWER_N: Int = 110;
const _B_LOWER_R: Int = 114;
const _B_LOWER_T: Int = 116;
const _B_LOWER_U: Int = 117;
const _B_LBRACE: Int = 123;
const _B_RBRACE: Int = 125;
const _B_NUL: Int = 0;

// JSON integer magnitude bound: floor(INT_MAX / 10) and INT_MAX % 10.
const _INT_MAX_DIV10: Int = 922337203685477580;
const _INT_MAX_LAST: Int = 7;

const _HEX_DIGITS: Str = "0123456789abcdef";

// ---------------------------------------------------------------------------
// Leaf Result helpers (see the module header)
// ---------------------------------------------------------------------------

fn _doc_ok(d: JsonDoc) -> Result[JsonDoc, Str] { return Ok(d); }
fn _doc_err(m: Str) -> Result[JsonDoc, Str] { return Err(m); }
fn _str_ok(s: Str) -> Result[Str, Str] { return Ok(s); }
fn _str_err(m: Str) -> Result[Str, Str] { return Err(m); }
fn _bool_ok(b: Bool) -> Result[Bool, Str] { return Ok(b); }
fn _bool_err(m: Str) -> Result[Bool, Str] { return Err(m); }
fn _cv_ok(v: CfnValue) -> Result[CfnValue, Str] { return Ok(v); }
fn _cv_err(m: Str) -> Result[CfnValue, Str] { return Err(m); }
fn _stack_ok(s: Stack) -> Result[Stack, Str] { return Ok(s); }
fn _stack_err(m: Str) -> Result[Stack, Str] { return Err(m); }

// ---------------------------------------------------------------------------
// Byte and Str primitives
// ---------------------------------------------------------------------------

// Widen and mask one byte of `s`. byte_at returns UInt8 and comparisons on
// bytes >= 128 miscompile unless widened to Int and masked first, so every
// byte read in this module goes through here.
fn _byte(s: Str, i: Int) -> Int {
  return (string.byte_at(s, i) as Int) & 0xFF;
}

// Byte-exact Str equality through str_compare (`==` on Str elements of
// Vec[Str] lowers to a pointer comparison in this compiler).
fn _streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// True for the four JSON whitespace bytes.
fn _is_json_ws(c: Int) -> Bool {
  if c == _B_SPACE { return true; }
  if c == _B_TAB { return true; }
  if c == _B_LF { return true; }
  if c == _B_CR { return true; }
  return false;
}

// True when `s` contains a NUL byte. JSON input with NUL is rejected so no
// parsed or rendered value can carry a NUL sentinel.
fn _has_nul(s: Str) -> Bool {
  var i = 0;
  while i < s.len() {
    if _byte(s, i) == _B_NUL {
      return true;
    }
    i = i + 1;
  }
  return false;
}

// Fresh copy of a Vec[Str].
fn _copy_strs(v: &Vec[Str]) -> Vec[Str] {
  var out = Vec[Str].new();
  var i = 0;
  while i < v.len() {
    let x: Str = v[i];
    out.push(x);
    i = i + 1;
  }
  return out;
}

// Fresh copy of a Vec[Int].
fn _copy_ints(v: &Vec[Int]) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 0;
  while i < v.len() {
    let x: Int = v[i];
    out.push(x);
    i = i + 1;
  }
  return out;
}

// Index of `s` in `v` (byte-exact), or -1.
fn _index_of(v: &Vec[Str], s: Str) -> Int {
  var i = 0;
  while i < v.len() {
    let x: Str = v[i];
    if _streq(x, s) {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// True when `s` occurs in `v`.
fn _in_strs(v: &Vec[Str], s: Str) -> Bool {
  return _index_of(v, s) >= 0;
}

// Copy of `v` with `s` appended (used for the resolution trail).
fn _trail_with(v: &Vec[Str], s: Str) -> Vec[Str] {
  var out = _copy_strs(v);
  out.push(s);
  return out;
}

// One decoded character as a Str. Code point 0 is rejected before this is
// called. Returns "" for code points int_to_char refuses.
fn _cp_str(cp: Int) -> Str {
  let o = convert.int_to_char(cp);
  match o {
    Some(ch) => { return tostring.to_string_char(ch); },
    None => { return ""; },
  }
  return "";
}

// Parse the whole trimmed text as a signed decimal integer. No sign other
// than a leading '-', no '+', no whitespace; the magnitude is bounded like
// JSON numbers. Result struct instead of Result to keep call sites simple.
type IntParse = {
  ok: Bool;
  value: Int;
}

fn _try_parse_int(s: Str) -> IntParse {
  let n = s.len();
  if n == 0 {
    return IntParse{ ok: false; value: 0 };
  }
  var i = 0;
  var neg = false;
  if _byte(s, 0) == _B_MINUS {
    neg = true;
    i = 1;
  }
  if i >= n {
    return IntParse{ ok: false; value: 0 };
  }
  var mag: Int = 0;
  while i < n {
    let c = _byte(s, i);
    if c < _B_ZERO || c > _B_NINE {
      return IntParse{ ok: false; value: 0 };
    }
    let d = c - _B_ZERO;
    if mag > _INT_MAX_DIV10 {
      return IntParse{ ok: false; value: 0 };
    }
    if mag == _INT_MAX_DIV10 && d > _INT_MAX_LAST {
      return IntParse{ ok: false; value: 0 };
    }
    mag = mag * 10 + d;
    i = i + 1;
  }
  if neg {
    return IntParse{ ok: true; value: 0 - mag };
  }
  return IntParse{ ok: true; value: mag };
}

// True when `s` is an integer according to _try_parse_int.
fn _is_int_text(s: Str) -> Bool {
  let r = _try_parse_int(s);
  let o: Bool = r.ok;
  return o;
}

// ---------------------------------------------------------------------------
// 1. JSON document arena and accessors
// ---------------------------------------------------------------------------

/// A parsed JSON-ish document. Nodes are stored in parallel vectors; a node
/// id is an index into all four per-node vectors. Compound nodes (arrays and
/// objects) record a start offset into `kids` and a child count:
///   * array with N elements: `counts[n] == N`, children `kids[start..start+N]`
///     are the element node ids;
///   * object with M members: `counts[n] == 2*M`, children are
///     key0, value0, key1, value1, ... (keys are JSON_STR nodes).
/// `texts` holds string payloads ("" for non-strings); `ints` holds booleans
/// (0/1) and integer values (0 elsewhere).
pub type JsonDoc = {
  kinds: Vec[Int];
  ints: Vec[Int];
  counts: Vec[Int];
  texts: Vec[Str];
  kids: Vec[Int];
  root: Int;
}

/// Root node id (always 0 for a successfully parsed document).
pub fn json_root(doc: &JsonDoc) -> Int {
  let r: Int = doc.root;
  return r;
}

/// Kind of `node` (JSON_*), or CFN_NONE for an out-of-range node.
pub fn json_kind(doc: &JsonDoc, node: Int) -> Int {
  if node < 0 || node >= doc.kinds.len() {
    return CFN_NONE;
  }
  let k: Int = doc.kinds[node];
  return k;
}

/// String payload of `node`, or "" when it is not a string node.
pub fn json_text(doc: &JsonDoc, node: Int) -> Str {
  if json_kind(doc, node) != JSON_STR {
    return "";
  }
  let t: Str = doc.texts[node];
  return t;
}

/// Integer payload of `node` (JSON_INT), or 0.
pub fn json_int(doc: &JsonDoc, node: Int) -> Int {
  if json_kind(doc, node) != JSON_INT {
    return 0;
  }
  let v: Int = doc.ints[node];
  return v;
}

/// Boolean payload of `node` (JSON_BOOL), or false.
pub fn json_bool(doc: &JsonDoc, node: Int) -> Bool {
  if json_kind(doc, node) != JSON_BOOL {
    return false;
  }
  let v: Int = doc.ints[node];
  return v != 0;
}

/// Raw child-entry count of `node` (array elements, or 2*members for an
/// object), or 0.
pub fn json_count(doc: &JsonDoc, node: Int) -> Int {
  let k = json_kind(doc, node);
  if k != JSON_ARR && k != JSON_OBJ {
    return 0;
  }
  let c: Int = doc.counts[node];
  return c;
}

// Flat child node id at child-entry `i`, or -1.
fn _json_child(doc: &JsonDoc, node: Int, i: Int) -> Int {
  let c = json_count(doc, node);
  if i < 0 || i >= c {
    return CFN_NONE;
  }
  let start: Int = doc.ints[node];
  let kid: Int = doc.kids[start + i];
  return kid;
}

/// Number of array elements of `node`, or 0.
pub fn json_array_len(doc: &JsonDoc, node: Int) -> Int {
  if json_kind(doc, node) != JSON_ARR {
    return 0;
  }
  let c: Int = doc.counts[node];
  return c;
}

/// Element node of array `node` at index `i`, or -1.
pub fn json_array_get(doc: &JsonDoc, node: Int, i: Int) -> Int {
  if json_kind(doc, node) != JSON_ARR {
    return CFN_NONE;
  }
  return _json_child(doc, node, i);
}

/// Number of members of object `node`, or 0.
pub fn json_member_count(doc: &JsonDoc, node: Int) -> Int {
  if json_kind(doc, node) != JSON_OBJ {
    return 0;
  }
  let c: Int = doc.counts[node];
  return c / 2;
}

/// Key of member `i` of object `node`, or "".
pub fn json_member_key(doc: &JsonDoc, node: Int, i: Int) -> Str {
  if i < 0 || i >= json_member_count(doc, node) {
    return "";
  }
  let start: Int = doc.ints[node];
  let kn: Int = doc.kids[start + i * 2];
  let t: Str = doc.texts[kn];
  return t;
}

/// Value node of member `i` of object `node`, or -1.
pub fn json_member_value(doc: &JsonDoc, node: Int, i: Int) -> Int {
  if i < 0 || i >= json_member_count(doc, node) {
    return CFN_NONE;
  }
  let start: Int = doc.ints[node];
  let vn: Int = doc.kids[start + i * 2 + 1];
  return vn;
}

/// Value node of the member named `key` of object `node`, or -1. The first
/// match wins (JSON objects in this parser cannot have duplicate keys).
pub fn json_object_get(doc: &JsonDoc, node: Int, key: Str) -> Int {
  if json_kind(doc, node) != JSON_OBJ {
    return CFN_NONE;
  }
  let n = json_member_count(doc, node);
  var i = 0;
  while i < n {
    let k: Str = json_member_key(doc, node, i);
    if _streq(k, key) {
      return json_member_value(doc, node, i);
    }
    i = i + 1;
  }
  return CFN_NONE;
}

// ---------------------------------------------------------------------------
// 2. JSON scanner (hand-rolled; strict subset)
// ---------------------------------------------------------------------------

// Scanner outcome: node id + position after the scanned value. `ok == false`
// carries the stable error message in `err`.
type JsonScan = {
  node: Int;
  pos: Int;
  ok: Bool;
  err: Str;
}

fn _scan_ok(n: Int, p: Int) -> JsonScan {
  return JsonScan{ node: n; pos: p; ok: true; err: "" };
}

fn _scan_err(m: Str, p: Int) -> JsonScan {
  return JsonScan{ node: CFN_NONE; pos: p; ok: false; err: m };
}

// A decoded \uXXXX escape: code point + position after the fourth hex digit.
type JsonHex = {
  cp: Int;
  next: Int;
  ok: Bool;
  err: Str;
}

// Skip JSON whitespace from `pos`; returns the first non-whitespace index.
fn _skip_ws(text: Str, pos: Int) -> Int {
  var i = pos;
  while i < text.len() && _is_json_ws(_byte(text, i)) {
    i = i + 1;
  }
  return i;
}

// Append one node with a scalar payload. Returns the new node id.
fn _push_node(doc: &mut JsonDoc, kind: Int, iv: Int, cv: Int, tv: Str) -> Int {
  let id = doc.kinds.len();
  doc.kinds.push(kind);
  doc.ints.push(iv);
  doc.counts.push(cv);
  doc.texts.push(tv);
  return id;
}

// True when `word` occurs in `text` at byte `pos`.
fn _match_at(text: Str, pos: Int, word: Str) -> Bool {
  if pos + word.len() > text.len() {
    return false;
  }
  var i = 0;
  while i < word.len() {
    let a = _byte(text, pos + i);
    let b = _byte(word, i);
    if a != b {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// Hex digit value, or -1.
fn _hex_val(c: Int) -> Int {
  if c >= _B_ZERO && c <= _B_NINE {
    return c - _B_ZERO;
  }
  if c >= 97 && c <= 102 {
    return c - 97 + 10;
  }
  if c >= 65 && c <= 70 {
    return c - 65 + 10;
  }
  return CFN_NONE;
}

// Decode four hex digits starting at `pos`.
fn _scan_hex4(text: Str, pos: Int) -> JsonHex {
  if pos + 4 > text.len() {
    return JsonHex{ cp: 0; next: pos; ok: false; err: "cfn: invalid unicode escape" };
  }
  var cp: Int = 0;
  var i = 0;
  while i < 4 {
    let d = _hex_val(_byte(text, pos + i));
    if d < 0 {
      return JsonHex{ cp: 0; next: pos; ok: false; err: "cfn: invalid unicode escape" };
    }
    cp = cp * 16 + d;
    i = i + 1;
  }
  if cp == 0 {
    return JsonHex{ cp: 0; next: pos + 4; ok: false; err: "cfn: unsupported unicode escape (NUL)" };
  }
  if cp >= 0xD800 && cp <= 0xDFFF {
    return JsonHex{ cp: 0; next: pos + 4; ok: false; err: "cfn: unsupported unicode escape (surrogate)" };
  }
  return JsonHex{ cp: cp; next: pos + 4; ok: true; err: "" };
}

// Find `target` (a byte value) in text starting at `from`, or -1.
fn _find_byte_from(text: Str, from: Int, target: Int) -> Int {
  var i = from;
  while i < text.len() {
    if _byte(text, i) == target {
      return i;
    }
    i = i + 1;
  }
  return CFN_NONE;
}

// Scan a string literal; `pos` points at the opening quote.
fn _scan_string(doc: &mut JsonDoc, text: Str, pos: Int) -> JsonScan {
  let n = text.len();
  var i = pos + 1;
  var seg = pos + 1;
  var out = "";
  while i < n {
    let c = _byte(text, i);
    if c == _B_QUOTE {
      out = out + string.str_slice(text, seg, i);
      let id = _push_node(doc, JSON_STR, 0, 0, out);
      return _scan_ok(id, i + 1);
    }
    if c < _B_SPACE {
      return _scan_err("cfn: control character in JSON string", i);
    }
    if c == _B_BACKSLASH {
      out = out + string.str_slice(text, seg, i);
      i = i + 1;
      if i >= n {
        return _scan_err("cfn: unterminated string", i);
      }
      let e = _byte(text, i);
      if e == _B_QUOTE {
        out = out + "\"";
        i = i + 1;
      } elif e == _B_BACKSLASH {
        out = out + "\\";
        i = i + 1;
      } elif e == _B_SLASH {
        out = out + "/";
        i = i + 1;
      } elif e == _B_LOWER_B {
        out = out + _cp_str(8);
        i = i + 1;
      } elif e == _B_LOWER_F {
        out = out + _cp_str(12);
        i = i + 1;
      } elif e == _B_LOWER_N {
        out = out + _cp_str(10);
        i = i + 1;
      } elif e == _B_LOWER_R {
        out = out + _cp_str(13);
        i = i + 1;
      } elif e == _B_LOWER_T {
        out = out + _cp_str(9);
        i = i + 1;
      } elif e == _B_LOWER_U {
        let h = _scan_hex4(text, i + 1);
        if !h.ok {
          return _scan_err(h.err, i);
        }
        out = out + _cp_str(h.cp);
        i = h.next;
      } else {
        return _scan_err("cfn: invalid escape sequence in string", i);
      }
      seg = i;
      continue;
    }
    i = i + 1;
  }
  return _scan_err("cfn: unterminated string", i);
}

// Scan an integer literal; `pos` points at '-' or a digit.
fn _scan_number(doc: &mut JsonDoc, text: Str, pos: Int) -> JsonScan {
  var i = pos;
  var neg = false;
  if _byte(text, i) == _B_MINUS {
    neg = true;
    i = i + 1;
  }
  let dstart = i;
  while i < text.len() {
    let c = _byte(text, i);
    if c < _B_ZERO || c > _B_NINE {
      break;
    }
    i = i + 1;
  }
  if i == dstart {
    return _scan_err("cfn: invalid number", pos);
  }
  if _byte(text, dstart) == _B_ZERO && i - dstart > 1 {
    return _scan_err("cfn: invalid number", pos);
  }
  if i < text.len() {
    let c2 = _byte(text, i);
    if c2 == _B_DOT || c2 == _B_LOWER_E || c2 == _B_UPPER_E {
      return _scan_err("cfn: invalid number (only integers are supported)", pos);
    }
  }
  var mag: Int = 0;
  var k = dstart;
  while k < i {
    let d = _byte(text, k) - _B_ZERO;
    if mag > _INT_MAX_DIV10 {
      return _scan_err("cfn: number out of range", pos);
    }
    if mag == _INT_MAX_DIV10 && d > _INT_MAX_LAST {
      return _scan_err("cfn: number out of range", pos);
    }
    mag = mag * 10 + d;
    k = k + 1;
  }
  var val = mag;
  if neg {
    val = 0 - mag;
  }
  let id = _push_node(doc, JSON_INT, val, 0, "");
  return _scan_ok(id, i);
}

// Scan true/false/null; `pos` points at the first letter.
fn _scan_literal(doc: &mut JsonDoc, text: Str, pos: Int, word: Str, kind: Int, iv: Int) -> JsonScan {
  if !_match_at(text, pos, word) {
    return _scan_err("cfn: invalid literal", pos);
  }
  let id = _push_node(doc, kind, iv, 0, "");
  return _scan_ok(id, pos + word.len());
}

// Scan any value; `pos` is at the first byte (whitespace is skipped here).
fn _scan_value(doc: &mut JsonDoc, text: Str, pos: Int, depth: Int) -> JsonScan {
  if depth > CFN_MAX_DEPTH {
    return _scan_err("cfn: JSON nesting too deep", pos);
  }
  let p = _skip_ws(text, pos);
  if p >= text.len() {
    return _scan_err("cfn: unexpected end of input", p);
  }
  let c = _byte(text, p);
  if c == _B_LBRACE {
    return _scan_object(doc, text, p, depth);
  }
  if c == _B_LBRACKET {
    return _scan_array(doc, text, p, depth);
  }
  if c == _B_QUOTE {
    return _scan_string(doc, text, p);
  }
  if c == _B_MINUS {
    return _scan_number(doc, text, p);
  }
  if c >= _B_ZERO && c <= _B_NINE {
    return _scan_number(doc, text, p);
  }
  if c == _B_LOWER_T {
    return _scan_literal(doc, text, p, "true", JSON_BOOL, 1);
  }
  if c == _B_LOWER_F {
    return _scan_literal(doc, text, p, "false", JSON_BOOL, 0);
  }
  if c == _B_LOWER_N {
    return _scan_literal(doc, text, p, "null", JSON_NULL, 0);
  }
  return _scan_err("cfn: unexpected character in JSON", p);
}

// Scan an object; `pos` points at '{'.
fn _scan_object(doc: &mut JsonDoc, text: Str, pos: Int, depth: Int) -> JsonScan {
  let id = _push_node(doc, JSON_OBJ, 0, 0, "");
  var kids = Vec[Int].new();
  var p = _skip_ws(text, pos + 1);
  if p < text.len() && _byte(text, p) == _B_RBRACE {
    doc.ints[id] = doc.kids.len();
    doc.counts[id] = 0;
    return _scan_ok(id, p + 1);
  }
  var members = 0;
  var done = false;
  while !done {
    if p >= text.len() {
      return _scan_err("cfn: unterminated object", p);
    }
    if _byte(text, p) != _B_QUOTE {
      return _scan_err("cfn: object key must be a string", p);
    }
    let ks = _scan_string(doc, text, p);
    if !ks.ok {
      return ks;
    }
    kids.push(ks.node);
    p = _skip_ws(text, ks.pos);
    if p >= text.len() || _byte(text, p) != _B_COLON {
      return _scan_err("cfn: expected ':' in object", p);
    }
    let vs = _scan_value(doc, text, p + 1, depth + 1);
    if !vs.ok {
      return vs;
    }
    kids.push(vs.node);
    members = members + 1;
    p = _skip_ws(text, vs.pos);
    if p >= text.len() {
      return _scan_err("cfn: unterminated object", p);
    }
    let c = _byte(text, p);
    if c == _B_COMMA {
      p = _skip_ws(text, p + 1);
      if p < text.len() && _byte(text, p) == _B_RBRACE {
        return _scan_err("cfn: trailing comma in object", p);
      }
    } elif c == _B_RBRACE {
      doc.ints[id] = doc.kids.len();
      doc.counts[id] = members * 2;
      var k = 0;
      while k < kids.len() {
        let kid: Int = kids[k];
        doc.kids.push(kid);
        k = k + 1;
      }
      return _scan_ok(id, p + 1);
    } else {
      return _scan_err("cfn: expected ',' or '}' in object", p);
    }
  }
  return _scan_err("cfn: unterminated object", p);
}

// Scan an array; `pos` points at '['.
fn _scan_array(doc: &mut JsonDoc, text: Str, pos: Int, depth: Int) -> JsonScan {
  let id = _push_node(doc, JSON_ARR, 0, 0, "");
  var kids = Vec[Int].new();
  var p = _skip_ws(text, pos + 1);
  if p < text.len() && _byte(text, p) == _B_RBRACKET {
    doc.ints[id] = doc.kids.len();
    doc.counts[id] = 0;
    return _scan_ok(id, p + 1);
  }
  var items = 0;
  var done = false;
  while !done {
    if p >= text.len() {
      return _scan_err("cfn: unterminated array", p);
    }
    let vs = _scan_value(doc, text, p, depth + 1);
    if !vs.ok {
      return vs;
    }
    kids.push(vs.node);
    items = items + 1;
    p = _skip_ws(text, vs.pos);
    if p >= text.len() {
      return _scan_err("cfn: unterminated array", p);
    }
    let c = _byte(text, p);
    if c == _B_COMMA {
      p = _skip_ws(text, p + 1);
      if p < text.len() && _byte(text, p) == _B_RBRACKET {
        return _scan_err("cfn: trailing comma in array", p);
      }
    } elif c == _B_RBRACKET {
      doc.ints[id] = doc.kids.len();
      doc.counts[id] = items;
      var k = 0;
      while k < kids.len() {
        let kid: Int = kids[k];
        doc.kids.push(kid);
        k = k + 1;
      }
      return _scan_ok(id, p + 1);
    } else {
      return _scan_err("cfn: expected ',' or ']' in array", p);
    }
  }
  return _scan_err("cfn: unterminated array", p);
}

/// Parse the documented JSON subset (see SPEC.md section 2):
/// objects, arrays, strings (escapes \" \\ \/ \b \f \n \r \t and BMP \uXXXX,
/// NUL and surrogates rejected), integer numbers (no fraction, no exponent,
/// no leading zeros), true/false and null. Returns Err("cfn: ...") on the
/// first violation; the message set is stable and listed in SPEC.md.
pub fn json_parse(text: Str) -> Result[JsonDoc, Str] {
  if _has_nul(text) {
    return _doc_err("cfn: NUL byte in input");
  }
  var doc = JsonDoc{
    kinds: Vec[Int].new();
    ints: Vec[Int].new();
    counts: Vec[Int].new();
    texts: Vec[Str].new();
    kids: Vec[Int].new();
    root: 0;
  };
  let s = _scan_value(&mut doc, text, 0, 0);
  if !s.ok {
    return _doc_err(s.err);
  }
  let rest = _skip_ws(text, s.pos);
  if rest < text.len() {
    return _doc_err("cfn: trailing data after JSON value");
  }
  doc.root = s.node;
  return _doc_ok(doc);
}

// ---------------------------------------------------------------------------
// 3. JSON rendering and structural equality
// ---------------------------------------------------------------------------

// JSON-quote one string. Printable ASCII and raw UTF-8 pass through; the
// quote, the backslash and the control bytes are escaped.
fn _json_quote(s: Str) -> Str {
  var out = "\"";
  var i = 0;
  while i < s.len() {
    let c = _byte(s, i);
    if c == _B_QUOTE {
      out = out + "\\\"";
    } elif c == _B_BACKSLASH {
      out = out + "\\\\";
    } elif c == 8 {
      out = out + "\\b";
    } elif c == 12 {
      out = out + "\\f";
    } elif c == _B_LF {
      out = out + "\\n";
    } elif c == _B_CR {
      out = out + "\\r";
    } elif c == _B_TAB {
      out = out + "\\t";
    } elif c < _B_SPACE {
      out = out + "\\u00" + string.str_slice(_HEX_DIGITS, c / 16, c / 16 + 1) + string.str_slice(_HEX_DIGITS, c % 16, c % 16 + 1);
    } else {
      out = out + string.str_slice(s, i, i + 1);
    }
    i = i + 1;
  }
  return out + "\"";
}

/// Render `node` back to compact canonical JSON: keys in document order,
/// integers decimal, strings escaped as in _json_quote. parse -> render ->
/// parse is a fixed point for any accepted document. Out-of-range nodes
/// render as "".
pub fn json_render(doc: &JsonDoc, node: Int) -> Str {
  let k = json_kind(doc, node);
  if k < 0 {
    return "";
  }
  if k == JSON_NULL {
    return "null";
  }
  if k == JSON_BOOL {
    let v: Int = doc.ints[node];
    if v != 0 {
      return "true";
    }
    return "false";
  }
  if k == JSON_INT {
    let v: Int = doc.ints[node];
    return convert.int_to_string(v);
  }
  if k == JSON_STR {
    let t: Str = doc.texts[node];
    return _json_quote(t);
  }
  if k == JSON_ARR {
    var out = "[";
    let n = json_array_len(doc, node);
    var i = 0;
    while i < n {
      if i > 0 {
        out = out + ",";
      }
      let en = json_array_get(doc, node, i);
      out = out + json_render(doc, en);
      i = i + 1;
    }
    return out + "]";
  }
  var out = "{";
  let n = json_member_count(doc, node);
  var i = 0;
  while i < n {
    if i > 0 {
      out = out + ",";
    }
    let key: Str = json_member_key(doc, node, i);
    let vn = json_member_value(doc, node, i);
    out = out + _json_quote(key) + ":" + json_render(doc, vn);
    i = i + 1;
  }
  return out + "}";
}

// Recursive structural equality: same kind; scalars byte-equal; arrays
// equal length and element-wise equal; objects equal member count and each
// member of `a` matches a member of `b` by name (key order is irrelevant).
fn _json_equal(a: &JsonDoc, na: Int, b: &JsonDoc, nb: Int) -> Bool {
  let ka = json_kind(a, na);
  let kb = json_kind(b, nb);
  if ka != kb {
    return false;
  }
  if ka < 0 {
    return true;
  }
  if ka == JSON_STR {
    let x: Str = a.texts[na];
    let y: Str = b.texts[nb];
    return _streq(x, y);
  }
  if ka == JSON_INT || ka == JSON_BOOL {
    let x: Int = a.ints[na];
    let y: Int = b.ints[nb];
    return x == y;
  }
  if ka == JSON_ARR {
    let la = json_array_len(a, na);
    let lb = json_array_len(b, nb);
    if la != lb {
      return false;
    }
    var i = 0;
    while i < la {
      let ea = json_array_get(a, na, i);
      let eb = json_array_get(b, nb, i);
      if !_json_equal(a, ea, b, eb) {
        return false;
      }
      i = i + 1;
    }
    return true;
  }
  if ka == JSON_OBJ {
    let ma = json_member_count(a, na);
    let mb = json_member_count(b, nb);
    if ma != mb {
      return false;
    }
    var i = 0;
    while i < ma {
      let key: Str = json_member_key(a, na, i);
      let va = json_member_value(a, na, i);
      let vb = json_object_get(b, nb, key);
      if vb < 0 {
        return false;
      }
      if !_json_equal(a, va, b, vb) {
        return false;
      }
      i = i + 1;
    }
    return true;
  }
  return true;
}

/// Structural JSON equality (see _json_equal). Two absent nodes (both -1)
/// are equal.
pub fn json_equal(a: &JsonDoc, na: Int, b: &JsonDoc, nb: Int) -> Bool {
  return _json_equal(a, na, b, nb);
}

// Equality that treats "absent node" (-1) as equal to absent, and unequal to
// any present node (used by the change-set diff for optional Properties).
fn _nodes_equal(a: &JsonDoc, na: Int, b: &JsonDoc, nb: Int) -> Bool {
  if na < 0 && nb < 0 {
    return true;
  }
  if na < 0 || nb < 0 {
    return false;
  }
  return _json_equal(a, na, b, nb);
}

// ---------------------------------------------------------------------------
// 4. Template validation and accessors
// ---------------------------------------------------------------------------

// Member node of a top-level section, or -1.
fn _section(doc: &JsonDoc, name: Str) -> Int {
  let root = json_root(doc);
  return json_object_get(doc, root, name);
}

// Resource node for a logical id, or -1.
fn _resource_node(doc: &JsonDoc, logical: Str) -> Int {
  return json_object_get(doc, _section(doc, "Resources"), logical);
}

// "Type" text of one resource node, or "".
fn _resource_type_of(doc: &JsonDoc, rnode: Int) -> Str {
  let tn = json_object_get(doc, rnode, "Type");
  return json_text(doc, tn);
}

// Validate the structural template rules and return the document.
fn _check_template(doc: JsonDoc) -> Result[JsonDoc, Str] {
  if json_kind(&doc, json_root(&doc)) != JSON_OBJ {
    return _doc_err("cfn: template root must be an object");
  }
  let res = _section(&doc, "Resources");
  if res < 0 {
    return _doc_err("cfn: template is missing the Resources section");
  }
  if json_kind(&doc, res) != JSON_OBJ {
    return _doc_err("cfn: Resources must be an object");
  }
  let n = json_member_count(&doc, res);
  var i = 0;
  while i < n {
    let id: Str = json_member_key(&doc, res, i);
    let rn = json_member_value(&doc, res, i);
    if json_kind(&doc, rn) != JSON_OBJ {
      return _doc_err("cfn: resource " + id + " must be an object");
    }
    let tn = json_object_get(&doc, rn, "Type");
    if tn < 0 {
      return _doc_err("cfn: resource " + id + " is missing Type");
    }
    if json_kind(&doc, tn) != JSON_STR {
      return _doc_err("cfn: resource " + id + " Type must be a string");
    }
    i = i + 1;
  }
  return _doc_ok(doc);
}

/// Parse and validate a template: strict JSON subset (json_parse), root
/// object, a Resources object whose every member is an object carrying a
/// string Type. Parameters/Mappings/Conditions/Outputs are optional and are
/// NOT structurally validated here. Err messages are stable ("cfn: ...").
pub fn cfn_template_parse(text: Str) -> Result[JsonDoc, Str] {
  let r = json_parse(text);
  match r {
    Ok(doc) => { return _check_template(doc); },
    Err(e) => { return _doc_err(e); },
  }
  return _doc_err("cfn: template parse failed");
}

/// Number of resources (0 when the template is not valid or has none).
pub fn cfn_resource_count(doc: &JsonDoc) -> Int {
  return json_member_count(doc, _section(doc, "Resources"));
}

/// Logical id of resource `i` in document order, or "".
pub fn cfn_resource_id(doc: &JsonDoc, i: Int) -> Str {
  return json_member_key(doc, _section(doc, "Resources"), i);
}

/// Declared Type of the resource `logical`, or "".
pub fn cfn_resource_type(doc: &JsonDoc, logical: Str) -> Str {
  return _resource_type_of(doc, _resource_node(doc, logical));
}

/// Properties node of the resource `logical`, or -1 when absent/unknown.
pub fn cfn_resource_properties(doc: &JsonDoc, logical: Str) -> Int {
  return json_object_get(doc, _resource_node(doc, logical), "Properties");
}

/// Number of declared parameters, or 0.
pub fn cfn_parameter_count(doc: &JsonDoc) -> Int {
  return json_member_count(doc, _section(doc, "Parameters"));
}

/// Name of parameter `i` in document order, or "".
pub fn cfn_parameter_name(doc: &JsonDoc, i: Int) -> Str {
  return json_member_key(doc, _section(doc, "Parameters"), i);
}

/// Declared parameter type: the Type member, or CFN_PARAM_STRING when the
/// member is absent; "" for an unknown parameter.
pub fn cfn_parameter_type(doc: &JsonDoc, name: Str) -> Str {
  let pn = json_object_get(doc, _section(doc, "Parameters"), name);
  if pn < 0 {
    return "";
  }
  let tn = json_object_get(doc, pn, "Type");
  if tn < 0 {
    return CFN_PARAM_STRING;
  }
  let t = json_text(doc, tn);
  if t.len() == 0 {
    return CFN_PARAM_STRING;
  }
  return t;
}

/// Declared default of parameter `name`: Some(scalar text) for a string /
/// integer / boolean default, Some(comma-joined text) for an array default,
/// None when the parameter or its Default is absent or malformed.
pub fn cfn_parameter_default(doc: &JsonDoc, name: Str) -> Option[Str] {
  let pn = json_object_get(doc, _section(doc, "Parameters"), name);
  if pn < 0 {
    return None;
  }
  let dn = json_object_get(doc, pn, "Default");
  if dn < 0 {
    return None;
  }
  let r = _literal_text(doc, dn, "cfn: parameter default must be a scalar or list: " + name);
  match r {
    Ok(v) => { return Some(v); },
    Err(_) => { return None; },
  }
  return None;
}

/// Number of declared conditions, or 0.
pub fn cfn_condition_count(doc: &JsonDoc) -> Int {
  return json_member_count(doc, _section(doc, "Conditions"));
}

/// Name of condition `i` in document order, or "".
pub fn cfn_condition_name(doc: &JsonDoc, i: Int) -> Str {
  return json_member_key(doc, _section(doc, "Conditions"), i);
}

/// Number of declared outputs, or 0.
pub fn cfn_output_count(doc: &JsonDoc) -> Int {
  return json_member_count(doc, _section(doc, "Outputs"));
}

/// Name of output `i` in document order, or "".
pub fn cfn_output_name(doc: &JsonDoc, i: Int) -> Str {
  return json_member_key(doc, _section(doc, "Outputs"), i);
}

// ---------------------------------------------------------------------------
// 5. Resolved values and evaluation context
// ---------------------------------------------------------------------------

/// A resolved value: kind is CFN_SCALAR (text holds the string) or CFN_LIST
/// (items holds the elements; text is "").
pub type CfnValue = {
  kind: Int;
  text: Str;
  items: Vec[Str];
}

/// Scalar resolved value.
pub fn cfn_value_scalar(text: Str) -> CfnValue {
  return CfnValue{ kind: CFN_SCALAR; text: text; items: Vec[Str].new(); };
}

/// List resolved value.
pub fn cfn_value_list(items: Vec[Str]) -> CfnValue {
  return CfnValue{ kind: CFN_LIST; text: ""; items: items; };
}

fn _scalar(s: Str) -> CfnValue {
  return CfnValue{ kind: CFN_SCALAR; text: s; items: Vec[Str].new(); };
}

fn _list(it: Vec[Str]) -> CfnValue {
  return CfnValue{ kind: CFN_LIST; text: ""; items: it; };
}

/// Kind of a resolved value (CFN_SCALAR or CFN_LIST).
pub fn cfn_value_kind(v: &CfnValue) -> Int {
  let k: Int = v.kind;
  return k;
}

/// Scalar text of a resolved value, or "".
pub fn cfn_value_text(v: &CfnValue) -> Str {
  let t: Str = v.text;
  return t;
}

/// Fresh copy of the list items of a resolved value.
pub fn cfn_value_items(v: &CfnValue) -> Vec[Str] {
  return _copy_strs(&v.items);
}

/// True when the resolved value is a scalar.
pub fn cfn_value_is_scalar(v: &CfnValue) -> Bool {
  let k: Int = v.kind;
  return k == CFN_SCALAR;
}

/// Evaluation context: parameter overrides, simulated resource refs and
/// attributes, and the pseudo-parameter values. All vectors are parallel
/// name/value pairs; build contexts with the cfn_context_* helpers.
pub type CfnContext = {
  param_names: Vec[Str];
  param_values: Vec[Str];
  resource_refs: Vec[Str];
  resource_ref_values: Vec[Str];
  attr_keys: Vec[Str];
  attr_values: Vec[Str];
  notification_arns: Vec[Str];
  region: Str;
  account_id: Str;
  stack_name: Str;
  partition: Str;
  url_suffix: Str;
}

fn _copy_context(c: &CfnContext) -> CfnContext {
  return CfnContext{
    param_names: _copy_strs(&c.param_names);
    param_values: _copy_strs(&c.param_values);
    resource_refs: _copy_strs(&c.resource_refs);
    resource_ref_values: _copy_strs(&c.resource_ref_values);
    attr_keys: _copy_strs(&c.attr_keys);
    attr_values: _copy_strs(&c.attr_values);
    notification_arns: _copy_strs(&c.notification_arns);
    region: c.region;
    account_id: c.account_id;
    stack_name: c.stack_name;
    partition: c.partition;
    url_suffix: c.url_suffix;
  };
}

/// A context for the given pseudo-parameters (partition "aws", URL suffix
/// "amazonaws.com"), no overrides.
pub fn cfn_context_new(region: Str, account_id: Str, stack_name: Str) -> CfnContext {
  return CfnContext{
    param_names: Vec[Str].new();
    param_values: Vec[Str].new();
    resource_refs: Vec[Str].new();
    resource_ref_values: Vec[Str].new();
    attr_keys: Vec[Str].new();
    attr_values: Vec[Str].new();
    notification_arns: Vec[Str].new();
    region: region;
    account_id: account_id;
    stack_name: stack_name;
    partition: "aws";
    url_suffix: "amazonaws.com";
  };
}

/// The deterministic default context: us-east-1 / 123456789012 / demo-stack.
pub fn cfn_context_default() -> CfnContext {
  return cfn_context_new("us-east-1", "123456789012", "demo-stack");
}

/// Copy of `c` with parameter `name` set to `value` (replace or append).
pub fn cfn_context_set_parameter(c: &CfnContext, name: Str, value: Str) -> CfnContext {
  var out = _copy_context(c);
  let i = _index_of(&out.param_names, name);
  if i >= 0 {
    out.param_values[i] = value;
    return out;
  }
  out.param_names.push(name);
  out.param_values.push(value);
  return out;
}

/// Copy of `c` with the simulated physical id of resource `logical` set.
pub fn cfn_context_set_resource_ref(c: &CfnContext, logical: Str, value: Str) -> CfnContext {
  var out = _copy_context(c);
  let i = _index_of(&out.resource_refs, logical);
  if i >= 0 {
    out.resource_ref_values[i] = value;
    return out;
  }
  out.resource_refs.push(logical);
  out.resource_ref_values.push(value);
  return out;
}

/// Copy of `c` with the simulated attribute `logical.attr` set.
pub fn cfn_context_set_attribute(c: &CfnContext, logical_attr: Str, value: Str) -> CfnContext {
  var out = _copy_context(c);
  let i = _index_of(&out.attr_keys, logical_attr);
  if i >= 0 {
    out.attr_values[i] = value;
    return out;
  }
  out.attr_keys.push(logical_attr);
  out.attr_values.push(value);
  return out;
}

/// Copy of `c` with one notification ARN appended.
pub fn cfn_context_add_notification_arn(c: &CfnContext, arn: Str) -> CfnContext {
  var out = _copy_context(c);
  out.notification_arns.push(arn);
  return out;
}

// Parallel lookup: Some(value) when `key` is present in `keys`.
fn _ctx_lookup(keys: &Vec[Str], vals: &Vec[Str], key: Str) -> Option[Str] {
  let i = _index_of(keys, key);
  if i < 0 || i >= vals.len() {
    return None;
  }
  let v: Str = vals[i];
  return Some(v);
}

/// Override value for parameter `name`, or None.
pub fn cfn_context_parameter(c: &CfnContext, name: Str) -> Option[Str] {
  return _ctx_lookup(&c.param_names, &c.param_values, name);
}

/// True when the context overrides parameter `name`.
pub fn cfn_context_has_parameter(c: &CfnContext, name: Str) -> Bool {
  let o = cfn_context_parameter(c, name);
  match o {
    Some(_) => { return true; },
    None => { return false; },
  }
  return false;
}

// ---------------------------------------------------------------------------
// 6. Intrinsic evaluation
// ---------------------------------------------------------------------------

// Literal text of a scalar/list node; `errmsg` is returned for anything else.
// Arrays are comma-joined. Used for parameter defaults.
fn _literal_text(doc: &JsonDoc, node: Int, errmsg: Str) -> Result[Str, Str] {
  let r = _literal_value(doc, node, errmsg);
  match r {
    Ok(v) => {
      let k: Int = v.kind;
      if k == CFN_SCALAR {
        let t: Str = v.text;
        return _str_ok(t);
      }
      let items = v.items;
      var out = "";
      var i = 0;
      while i < items.len() {
        if i > 0 {
          out = out + ",";
        }
        let it: Str = items[i];
        out = out + it;
        i = i + 1;
      }
      return _str_ok(out);
    },
    Err(e) => { return _str_err(e); },
  }
  return _str_err(errmsg);
}

// Literal value of a node without evaluating intrinsics: string, integer,
// boolean, or an array of such literals (returned as a list). Mapping values
// and parameter defaults use this. `errmsg` covers any other shape.
fn _literal_value(doc: &JsonDoc, node: Int, errmsg: Str) -> Result[CfnValue, Str] {
  let k = json_kind(doc, node);
  if k == JSON_STR {
    let t: Str = doc.texts[node];
    return _cv_ok(_scalar(t));
  }
  if k == JSON_INT {
    let v: Int = doc.ints[node];
    return _cv_ok(_scalar(convert.int_to_string(v)));
  }
  if k == JSON_BOOL {
    let v: Int = doc.ints[node];
    if v != 0 {
      return _cv_ok(_scalar("true"));
    }
    return _cv_ok(_scalar("false"));
  }
  if k == JSON_ARR {
    var items = Vec[Str].new();
    let n = json_array_len(doc, node);
    var i = 0;
    while i < n {
      let en = json_array_get(doc, node, i);
      let ek = json_kind(doc, en);
      if ek == JSON_STR {
        let t: Str = doc.texts[en];
        items.push(t);
      } elif ek == JSON_INT {
        let v: Int = doc.ints[en];
        items.push(convert.int_to_string(v));
      } elif ek == JSON_BOOL {
        let v: Int = doc.ints[en];
        if v != 0 {
          items.push("true");
        } else {
          items.push("false");
        }
      } else {
        return _cv_err(errmsg);
      }
      i = i + 1;
    }
    return _cv_ok(_list(items));
  }
  return _cv_err(errmsg);
}

// Effective value of parameter `name`: context override first, then the
// template default; Err("cfn: parameter has no value: <name>") when neither
// exists. A list default is comma-joined.
pub fn cfn_parameter_effective(doc: &JsonDoc, name: Str, ctx: &CfnContext) -> Result[Str, Str] {
  let ov = cfn_context_parameter(ctx, name);
  match ov {
    Some(v) => { return _str_ok(v); },
    None => {},
  }
  let pn = json_object_get(doc, _section(doc, "Parameters"), name);
  if pn < 0 {
    return _str_err("cfn: parameter has no value: " + name);
  }
  let dn = json_object_get(doc, pn, "Default");
  if dn < 0 {
    return _str_err("cfn: parameter has no value: " + name);
  }
  return _literal_text(doc, dn, "cfn: parameter default must be a scalar or list: " + name);
}

// Resolve one name through Ref: pseudo-parameters, template parameters,
// then resources (context override, else the logical id itself). The trail
// guards against a name that is already being resolved.
fn _resolve_ref(doc: &JsonDoc, ctx: &CfnContext, name: Str, trail: &Vec[Str]) -> Result[Str, Str] {
  if _in_strs(trail, name) {
    return _str_err("cfn: cyclic reference: " + name);
  }
  if _streq(name, "AWS::Region") {
    return _str_ok(ctx.region);
  }
  if _streq(name, "AWS::AccountId") {
    return _str_ok(ctx.account_id);
  }
  if _streq(name, "AWS::StackName") {
    return _str_ok(ctx.stack_name);
  }
  if _streq(name, "AWS::Partition") {
    return _str_ok(ctx.partition);
  }
  if _streq(name, "AWS::URLSuffix") {
    return _str_ok(ctx.url_suffix);
  }
  if _streq(name, "AWS::NoValue") {
    return _str_ok("");
  }
  if _streq(name, "AWS::NotificationARNs") {
    var out = "";
    var i = 0;
    while i < ctx.notification_arns.len() {
      if i > 0 {
        out = out + ",";
      }
      let a: Str = ctx.notification_arns[i];
      out = out + a;
      i = i + 1;
    }
    return _str_ok(out);
  }
  let pn = json_object_get(doc, _section(doc, "Parameters"), name);
  if pn >= 0 {
    return cfn_parameter_effective(doc, name, ctx);
  }
  let rn = _resource_node(doc, name);
  if rn >= 0 {
    let ov = _ctx_lookup(&ctx.resource_refs, &ctx.resource_ref_values, name);
    match ov {
      Some(v) => { return _str_ok(v); },
      None => { return _str_ok(name); },
    }
  }
  return _str_err("cfn: unresolved Ref: " + name);
}

// Resolve GetAtt: the resource must exist; a context attribute override wins,
// otherwise the deterministic simulated value "<logical>.<attr>" is returned.
fn _resolve_getatt(doc: &JsonDoc, ctx: &CfnContext, logical: Str, attr: Str) -> Result[Str, Str] {
  if _resource_node(doc, logical) < 0 {
    return _str_err("cfn: unknown resource in Fn::GetAtt: " + logical);
  }
  if attr.len() == 0 {
    return _str_err("cfn: Fn::GetAtt attribute must not be empty");
  }
  let key = logical + "." + attr;
  let ov = _ctx_lookup(&ctx.attr_keys, &ctx.attr_values, key);
  match ov {
    Some(v) => { return _str_ok(v); },
    None => { return _str_ok(key); },
  }
}

// Evaluate `node` to a scalar string; Err when it resolves to a list.
fn _eval_scalar(doc: &JsonDoc, node: Int, ctx: &CfnContext, depth: Int, trail: &Vec[Str]) -> Result[Str, Str] {
  let r = _eval(doc, node, ctx, depth, trail);
  match r {
    Ok(v) => {
      let k: Int = v.kind;
      if k != CFN_SCALAR {
        return _str_err("cfn: value must resolve to a scalar");
      }
      let t: Str = v.text;
      return _str_ok(t);
    },
    Err(e) => { return _str_err(e); },
  }
}

// Split "Logical.Attr" at the first dot; returns ("", "") when there is none.
fn _split_logical_attr(s: Str) -> (Str, Str) {
  let dot = _find_byte_from(s, 0, _B_DOT);
  if dot < 0 {
    return ("", "");
  }
  return (string.str_slice(s, 0, dot), string.str_slice(s, dot + 1, s.len()));
}

// Evaluate an array node to a list of scalars.
fn _eval_array(doc: &JsonDoc, node: Int, ctx: &CfnContext, depth: Int, trail: &Vec[Str]) -> Result[CfnValue, Str] {
  var items = Vec[Str].new();
  let n = json_array_len(doc, node);
  var i = 0;
  while i < n {
    let en = json_array_get(doc, node, i);
    let r = _eval_scalar(doc, en, ctx, depth + 1, trail);
    match r {
      Ok(v) => { items.push(v); },
      Err(e) => { return _cv_err(e); },
    }
    i = i + 1;
  }
  return _cv_ok(_list(items));
}

// Fn::Join: [delimiter, list]. The list may be a literal array or any
// expression resolving to a list (e.g. Fn::Split).
fn _eval_join(doc: &JsonDoc, arg: Int, ctx: &CfnContext, depth: Int, trail: &Vec[Str]) -> Result[CfnValue, Str] {
  if json_kind(doc, arg) != JSON_ARR || json_array_len(doc, arg) != 2 {
    return _cv_err("cfn: Fn::Join expects [delimiter, list]");
  }
  let dn = json_array_get(doc, arg, 0);
  let ln = json_array_get(doc, arg, 1);
  let dr = _eval_scalar(doc, dn, ctx, depth + 1, trail);
  var delim = "";
  match dr {
    Ok(d) => { delim = d; },
    Err(e) => { return _cv_err(e); },
  }
  let lr = _eval(doc, ln, ctx, depth + 1, trail);
  match lr {
    Ok(lv) => {
      let lk: Int = lv.kind;
      if lk != CFN_LIST {
        return _cv_err("cfn: Fn::Join list must resolve to a list");
      }
      let items = lv.items;
      var out = "";
      var i = 0;
      while i < items.len() {
        if i > 0 {
          out = out + delim;
        }
        let it: Str = items[i];
        out = out + it;
        i = i + 1;
      }
      return _cv_ok(_scalar(out));
    },
    Err(e) => { return _cv_err(e); },
  }
  return _cv_err("cfn: Fn::Join failed");
}

// Fn::Select: [index, list]. The index may be an intrinsic resolving to an
// integer scalar; the list may be a literal array or an expression resolving
// to a list.
fn _eval_select(doc: &JsonDoc, arg: Int, ctx: &CfnContext, depth: Int, trail: &Vec[Str]) -> Result[CfnValue, Str] {
  if json_kind(doc, arg) != JSON_ARR || json_array_len(doc, arg) != 2 {
    return _cv_err("cfn: Fn::Select expects [index, list]");
  }
  let inode = json_array_get(doc, arg, 0);
  let lnode = json_array_get(doc, arg, 1);
  let ir = _eval_scalar(doc, inode, ctx, depth + 1, trail);
  var itext = "";
  match ir {
    Ok(v) => { itext = v; },
    Err(e) => { return _cv_err(e); },
  }
  let ip = _try_parse_int(itext);
  let iok: Bool = ip.ok;
  if !iok {
    return _cv_err("cfn: Fn::Select index must be an integer: " + itext);
  }
  let idx: Int = ip.value;
  let lr = _eval(doc, lnode, ctx, depth + 1, trail);
  match lr {
    Ok(lv) => {
      let lk: Int = lv.kind;
      if lk != CFN_LIST {
        return _cv_err("cfn: Fn::Select second argument must resolve to a list");
      }
      let items = lv.items;
      if idx < 0 || idx >= items.len() {
        return _cv_err("cfn: Fn::Select index out of range: " + convert.int_to_string(idx));
      }
      let chosen: Str = items[idx];
      return _cv_ok(_scalar(chosen));
    },
    Err(e) => { return _cv_err(e); },
  }
  return _cv_err("cfn: Fn::Select failed");
}

// Fn::Split: [delimiter, string] -> list. The delimiter must be non-empty.
fn _eval_split(doc: &JsonDoc, arg: Int, ctx: &CfnContext, depth: Int, trail: &Vec[Str]) -> Result[CfnValue, Str] {
  if json_kind(doc, arg) != JSON_ARR || json_array_len(doc, arg) != 2 {
    return _cv_err("cfn: Fn::Split expects [delimiter, string]");
  }
  let dn = json_array_get(doc, arg, 0);
  let sn = json_array_get(doc, arg, 1);
  let dr = _eval_scalar(doc, dn, ctx, depth + 1, trail);
  var delim = "";
  match dr {
    Ok(d) => { delim = d; },
    Err(e) => { return _cv_err(e); },
  }
  let sr = _eval_scalar(doc, sn, ctx, depth + 1, trail);
  var src = "";
  match sr {
    Ok(s) => { src = s; },
    Err(e) => { return _cv_err(e); },
  }
  if delim.len() == 0 {
    return _cv_err("cfn: Fn::Split delimiter must not be empty");
  }
  return _cv_ok(_list(string.str_split(src, delim)));
}

// Fn::Equals: [a, b] -> "true"/"false" (byte-exact scalar comparison).
fn _eval_equals(doc: &JsonDoc, arg: Int, ctx: &CfnContext, depth: Int, trail: &Vec[Str]) -> Result[CfnValue, Str] {
  if json_kind(doc, arg) != JSON_ARR || json_array_len(doc, arg) != 2 {
    return _cv_err("cfn: Fn::Equals expects [a, b]");
  }
  let an = json_array_get(doc, arg, 0);
  let bn = json_array_get(doc, arg, 1);
  let ar = _eval_scalar(doc, an, ctx, depth + 1, trail);
  var av = "";
  match ar {
    Ok(v) => { av = v; },
    Err(e) => { return _cv_err(e); },
  }
  let br = _eval_scalar(doc, bn, ctx, depth + 1, trail);
  var bv = "";
  match br {
    Ok(v) => { bv = v; },
    Err(e) => { return _cv_err(e); },
  }
  if _streq(av, bv) {
    return _cv_ok(_scalar("true"));
  }
  return _cv_ok(_scalar("false"));
}

// Evaluate a named condition from the Conditions section. A condition is
// {"Fn::Equals": [a, b]} or {"Condition": "Other"}; the trail rejects
// condition chains that (transitively) reference themselves.
fn _condition_value(doc: &JsonDoc, name: Str, ctx: &CfnContext, depth: Int, trail: &Vec[Str]) -> Result[Bool, Str] {
  if depth > CFN_MAX_DEPTH {
    return _bool_err("cfn: intrinsic resolution depth exceeded");
  }
  if _in_strs(trail, name) {
    return _bool_err("cfn: cyclic reference: " + name);
  }
  let conds = _section(doc, "Conditions");
  let expr = json_object_get(doc, conds, name);
  if expr < 0 {
    return _bool_err("cfn: unknown condition: " + name);
  }
  if json_kind(doc, expr) != JSON_OBJ || json_member_count(doc, expr) != 1 {
    return _bool_err("cfn: condition " + name + " must be Fn::Equals or Condition");
  }
  let key: Str = json_member_key(doc, expr, 0);
  let arg = json_member_value(doc, expr, 0);
  if _streq(key, "Fn::Equals") {
    let e = _eval_equals(doc, arg, ctx, depth + 1, trail);
    match e {
      Ok(v) => {
        let t: Str = v.text;
        if _streq(t, "true") {
          return _bool_ok(true);
        }
        return _bool_ok(false);
      },
      Err(m) => { return _bool_err(m); },
    }
  }
  if _streq(key, "Condition") {
    if json_kind(doc, arg) != JSON_STR {
      return _bool_err("cfn: Condition name must be a string");
    }
    let inner: Str = doc.texts[arg];
    let t2 = _trail_with(trail, name);
    return _condition_value(doc, inner, ctx, depth + 1, &t2);
  }
  return _bool_err("cfn: condition " + name + " must be Fn::Equals or Condition");
}

/// Evaluate one named condition to a Bool (public entry; empty trail).
pub fn cfn_condition_eval(doc: &JsonDoc, name: Str, ctx: &CfnContext) -> Result[Bool, Str] {
  var trail = Vec[Str].new();
  return _condition_value(doc, name, ctx, 0, &trail);
}

// Fn::If: [condition-name, true-expression, false-expression]. The condition
// name must be a string literal naming a template condition.
fn _eval_if(doc: &JsonDoc, arg: Int, ctx: &CfnContext, depth: Int, trail: &Vec[Str]) -> Result[CfnValue, Str] {
  if json_kind(doc, arg) != JSON_ARR || json_array_len(doc, arg) != 3 {
    return _cv_err("cfn: Fn::If expects [condition, true, false]");
  }
  let cn = json_array_get(doc, arg, 0);
  if json_kind(doc, cn) != JSON_STR {
    return _cv_err("cfn: Fn::If condition name must be a string");
  }
  let cname: Str = doc.texts[cn];
  let cv = _condition_value(doc, cname, ctx, depth + 1, trail);
  var taken = -1;
  match cv {
    Ok(b) => {
      if b {
        taken = json_array_get(doc, arg, 1);
      } else {
        taken = json_array_get(doc, arg, 2);
      }
    },
    Err(e) => { return _cv_err(e); },
  }
  if taken < 0 {
    return _cv_err("cfn: Fn::If expects [condition, true, false]");
  }
  return _eval(doc, taken, ctx, depth + 1, trail);
}

// Fn::FindInMap: [map, top-key, second-key]; keys may be intrinsics, the
// mapping value is a literal (scalar or list of scalars).
fn _eval_find_in_map(doc: &JsonDoc, arg: Int, ctx: &CfnContext, depth: Int, trail: &Vec[Str]) -> Result[CfnValue, Str] {
  if json_kind(doc, arg) != JSON_ARR || json_array_len(doc, arg) != 3 {
    return _cv_err("cfn: Fn::FindInMap expects [map, top key, second key]");
  }
  let mn = json_array_get(doc, arg, 0);
  let tn = json_array_get(doc, arg, 1);
  let sn = json_array_get(doc, arg, 2);
  let mr = _eval_scalar(doc, mn, ctx, depth + 1, trail);
  var mapname = "";
  match mr {
    Ok(v) => { mapname = v; },
    Err(e) => { return _cv_err(e); },
  }
  let tr = _eval_scalar(doc, tn, ctx, depth + 1, trail);
  var top = "";
  match tr {
    Ok(v) => { top = v; },
    Err(e) => { return _cv_err(e); },
  }
  let sr = _eval_scalar(doc, sn, ctx, depth + 1, trail);
  var second = "";
  match sr {
    Ok(v) => { second = v; },
    Err(e) => { return _cv_err(e); },
  }
  let path = mapname + "/" + top + "/" + second;
  let maps = _section(doc, "Mappings");
  let mnode = json_object_get(doc, maps, mapname);
  if mnode < 0 {
    return _cv_err("cfn: mapping not found: " + mapname);
  }
  let tnode = json_object_get(doc, mnode, top);
  if tnode < 0 {
    return _cv_err("cfn: mapping key not found: " + path);
  }
  let snode = json_object_get(doc, tnode, second);
  if snode < 0 {
    return _cv_err("cfn: mapping key not found: " + path);
  }
  return _literal_value(doc, snode, "cfn: mapping value must be a scalar or list: " + path);
}

// Fn::Sub: "text with ${Name}, ${Name.Attr}, ${!Literal} and ${Var}" or
// [text, {Var: expression}]. Substitution results are not re-expanded.
fn _eval_sub(doc: &JsonDoc, arg: Int, ctx: &CfnContext, depth: Int, trail: &Vec[Str]) -> Result[CfnValue, Str] {
  var text_node = CFN_NONE;
  var vars_node = CFN_NONE;
  let ka = json_kind(doc, arg);
  if ka == JSON_STR {
    text_node = arg;
  } elif ka == JSON_ARR {
    if json_array_len(doc, arg) != 2 {
      return _cv_err("cfn: Fn::Sub expects a string or [string, vars]");
    }
    text_node = json_array_get(doc, arg, 0);
    vars_node = json_array_get(doc, arg, 1);
    if json_kind(doc, text_node) != JSON_STR {
      return _cv_err("cfn: Fn::Sub template must be a string");
    }
    if vars_node >= 0 && json_kind(doc, vars_node) != JSON_OBJ {
      return _cv_err("cfn: Fn::Sub vars must be an object");
    }
  } else {
    return _cv_err("cfn: Fn::Sub expects a string or [string, vars]");
  }
  let src: Str = doc.texts[text_node];
  let n = src.len();
  var out = "";
  var i = 0;
  var seg = 0;
  while i < n {
    let c = _byte(src, i);
    if c == _B_DOLLAR && i + 1 < n && _byte(src, i + 1) == _B_LBRACE {
      out = out + string.str_slice(src, seg, i);
      let close = _find_byte_from(src, i + 2, _B_RBRACE);
      if close < 0 {
        return _cv_err("cfn: malformed Fn::Sub: missing '}'");
      }
      let inner = string.str_slice(src, i + 2, close);
      if inner.len() == 0 {
        return _cv_err("cfn: malformed Fn::Sub: empty placeholder");
      }
      if _byte(inner, 0) == _B_BANG {
        out = out + "${" + string.str_slice(inner, 1, inner.len()) + "}";
      } else {
        let dot = _find_byte_from(inner, 0, _B_DOT);
        if dot >= 0 {
          let logical = string.str_slice(inner, 0, dot);
          if logical.len() == 0 {
            return _cv_err("cfn: malformed Fn::Sub placeholder: " + inner);
          }
          let attr = string.str_slice(inner, dot + 1, inner.len());
          let gr = _resolve_getatt(doc, ctx, logical, attr);
          match gr {
            Ok(v) => { out = out + v; },
            Err(e) => { return _cv_err(e); },
          }
        } else {
          let vn = json_object_get(doc, vars_node, inner);
          if vars_node >= 0 && vn >= 0 {
            let vr = _eval_scalar(doc, vn, ctx, depth + 1, trail);
            match vr {
              Ok(v) => { out = out + v; },
              Err(e) => { return _cv_err(e); },
            }
          } else {
            let rr = _resolve_ref(doc, ctx, inner, trail);
            match rr {
              Ok(v) => { out = out + v; },
              Err(e) => { return _cv_err(e); },
            }
          }
        }
      }
      i = close + 1;
      seg = i;
    } else {
      i = i + 1;
    }
  }
  out = out + string.str_slice(src, seg, n);
  return _cv_ok(_scalar(out));
}

// Evaluate an object node expected to be a single-key intrinsic.
fn _eval_intrinsic(doc: &JsonDoc, node: Int, ctx: &CfnContext, depth: Int, trail: &Vec[Str]) -> Result[CfnValue, Str] {
  if json_member_count(doc, node) != 1 {
    return _cv_err("cfn: object is not a valid intrinsic");
  }
  let key: Str = json_member_key(doc, node, 0);
  let arg = json_member_value(doc, node, 0);
  if _streq(key, "Ref") {
    if json_kind(doc, arg) != JSON_STR {
      return _cv_err("cfn: Ref expects a string");
    }
    let name: Str = doc.texts[arg];
    let r = _resolve_ref(doc, ctx, name, trail);
    match r {
      Ok(v) => { return _cv_ok(_scalar(v)); },
      Err(e) => { return _cv_err(e); },
    }
  }
  if _streq(key, "Fn::GetAtt") {
    var logical = "";
    var attr = "";
    let ak = json_kind(doc, arg);
    if ak == JSON_STR {
      let s: Str = doc.texts[arg];
      let pair = _split_logical_attr(s);
      logical = pair.0;
      attr = pair.1;
      if logical.len() == 0 {
        return _cv_err("cfn: Fn::GetAtt expects 'Logical.Attr' or [logical, attribute]");
      }
    } elif ak == JSON_ARR && json_array_len(doc, arg) == 2 {
      let ln = json_array_get(doc, arg, 0);
      let an = json_array_get(doc, arg, 1);
      let lr = _eval_scalar(doc, ln, ctx, depth + 1, trail);
      match lr {
        Ok(v) => { logical = v; },
        Err(e) => { return _cv_err(e); },
      }
      let ar = _eval_scalar(doc, an, ctx, depth + 1, trail);
      match ar {
        Ok(v) => { attr = v; },
        Err(e) => { return _cv_err(e); },
      }
    } else {
      return _cv_err("cfn: Fn::GetAtt expects 'Logical.Attr' or [logical, attribute]");
    }
    let r = _resolve_getatt(doc, ctx, logical, attr);
    match r {
      Ok(v) => { return _cv_ok(_scalar(v)); },
      Err(e) => { return _cv_err(e); },
    }
  }
  if _streq(key, "Fn::Join") {
    return _eval_join(doc, arg, ctx, depth, trail);
  }
  if _streq(key, "Fn::Sub") {
    return _eval_sub(doc, arg, ctx, depth, trail);
  }
  if _streq(key, "Fn::Select") {
    return _eval_select(doc, arg, ctx, depth, trail);
  }
  if _streq(key, "Fn::Split") {
    return _eval_split(doc, arg, ctx, depth, trail);
  }
  if _streq(key, "Fn::If") {
    return _eval_if(doc, arg, ctx, depth, trail);
  }
  if _streq(key, "Fn::Equals") {
    return _eval_equals(doc, arg, ctx, depth, trail);
  }
  if _streq(key, "Fn::FindInMap") {
    return _eval_find_in_map(doc, arg, ctx, depth, trail);
  }
  return _cv_err("cfn: unknown intrinsic: " + key);
}

// Core evaluator: JSON node -> CfnValue. Intrinsics dispatch by exact key;
// plain objects are rejected, arrays become lists, null is not resolvable.
fn _eval(doc: &JsonDoc, node: Int, ctx: &CfnContext, depth: Int, trail: &Vec[Str]) -> Result[CfnValue, Str] {
  if depth > CFN_MAX_DEPTH {
    return _cv_err("cfn: intrinsic resolution depth exceeded");
  }
  let k = json_kind(doc, node);
  if k < 0 {
    return _cv_err("cfn: invalid JSON node");
  }
  if k == JSON_STR {
    let t: Str = doc.texts[node];
    return _cv_ok(_scalar(t));
  }
  if k == JSON_INT {
    let v: Int = doc.ints[node];
    return _cv_ok(_scalar(convert.int_to_string(v)));
  }
  if k == JSON_BOOL {
    let v: Int = doc.ints[node];
    if v != 0 {
      return _cv_ok(_scalar("true"));
    }
    return _cv_ok(_scalar("false"));
  }
  if k == JSON_ARR {
    return _eval_array(doc, node, ctx, depth, trail);
  }
  if k == JSON_OBJ {
    return _eval_intrinsic(doc, node, ctx, depth, trail);
  }
  return _cv_err("cfn: null is not a resolvable value");
}

/// Evaluate one JSON node of `doc` against `ctx`: the public intrinsic
/// entry. Ref / Fn::GetAtt / Fn::Join / Fn::Sub / Fn::Select / Fn::Split /
/// Fn::If / Fn::Equals / Fn::FindInMap are understood; see SPEC.md for the
/// semantics table. Returns Err("cfn: ...") for malformed intrinsics,
/// unknown names, list/scalar mismatches, the depth cap and cycles.
pub fn cfn_eval(doc: &JsonDoc, node: Int, ctx: &CfnContext) -> Result[CfnValue, Str] {
  var trail = Vec[Str].new();
  return _eval(doc, node, ctx, 0, &trail);
}

/// Evaluate one JSON node to a scalar string (Err when it resolves to a
/// list). Convenience wrapper over cfn_eval.
pub fn cfn_eval_str(doc: &JsonDoc, node: Int, ctx: &CfnContext) -> Result[Str, Str] {
  let r = cfn_eval(doc, node, ctx);
  match r {
    Ok(v) => {
      let k: Int = v.kind;
      if k != CFN_SCALAR {
        return _str_err("cfn: value must resolve to a scalar");
      }
      let t: Str = v.text;
      return _str_ok(t);
    },
    Err(e) => { return _str_err(e); },
  }
  return _str_err("cfn: evaluation failed");
}

// ---------------------------------------------------------------------------
// 7. Parameters and outputs
// ---------------------------------------------------------------------------

/// Validate the static parameter rules and return ALL errors in order:
///   1. every context override must name a declared parameter
///      ("cfn: unknown parameter: X");
///   2. every parameter without an override and without a default is
///      required ("cfn: missing required parameter: X");
///   3. Number parameters must hold an integer scalar
///      ("cfn: parameter X must be an integer: V").
/// An empty vector means valid. Semantics of defaults/types follow SPEC.md.
pub fn cfn_validate_parameters(doc: &JsonDoc, ctx: &CfnContext) -> Vec[Str] {
  var errs = Vec[Str].new();
  var i = 0;
  while i < ctx.param_names.len() {
    let n: Str = ctx.param_names[i];
    let pn = json_object_get(doc, _section(doc, "Parameters"), n);
    if pn < 0 {
      errs.push("cfn: unknown parameter: " + n);
    }
    i = i + 1;
  }
  let params = _section(doc, "Parameters");
  let n = json_member_count(doc, params);
  i = 0;
  while i < n {
    let name: Str = json_member_key(doc, params, i);
    var have = cfn_context_has_parameter(ctx, name);
    if !have {
      let dn = cfn_parameter_default(doc, name);
      match dn {
        Some(_) => { have = true; },
        None => {},
      }
    }
    if !have {
      errs.push("cfn: missing required parameter: " + name);
      i = i + 1;
      continue;
    }
    let typ = cfn_parameter_type(doc, name);
    if _streq(typ, CFN_PARAM_NUMBER) {
      let ev = cfn_parameter_effective(doc, name, ctx);
      match ev {
        Ok(v) => {
          if !_is_int_text(v) {
            errs.push("cfn: parameter " + name + " must be an integer: " + v);
          }
        },
        Err(_) => {},
      }
    }
    i = i + 1;
  }
  return errs;
}

/// True when cfn_validate_parameters finds no error.
pub fn cfn_parameters_valid(doc: &JsonDoc, ctx: &CfnContext) -> Bool {
  let errs = cfn_validate_parameters(doc, ctx);
  return errs.len() == 0;
}

/// Resolve the Value of output `name` to a scalar string. Errors:
/// "cfn: unknown output: X", "cfn: output has no Value: X",
/// "cfn: output value must resolve to a scalar: X", plus intrinsic errors.
pub fn cfn_output_value(doc: &JsonDoc, name: Str, ctx: &CfnContext) -> Result[Str, Str] {
  let on = json_object_get(doc, _section(doc, "Outputs"), name);
  if on < 0 {
    return _str_err("cfn: unknown output: " + name);
  }
  let vn = json_object_get(doc, on, "Value");
  if vn < 0 {
    return _str_err("cfn: output has no Value: " + name);
  }
  let r = cfn_eval(doc, vn, ctx);
  match r {
    Ok(v) => {
      let k: Int = v.kind;
      if k != CFN_SCALAR {
        return _str_err("cfn: output value must resolve to a scalar: " + name);
      }
      let t: Str = v.text;
      return _str_ok(t);
    },
    Err(e) => { return _str_err(e); },
  }
  return _str_err("cfn: output value must resolve to a scalar: " + name);
}

/// Description of output `name`, or None when absent.
pub fn cfn_output_description(doc: &JsonDoc, name: Str) -> Option[Str] {
  let on = json_object_get(doc, _section(doc, "Outputs"), name);
  if on < 0 {
    return None;
  }
  let dn = json_object_get(doc, on, "Description");
  if json_kind(doc, dn) != JSON_STR {
    return None;
  }
  let t: Str = doc.texts[dn];
  return Some(t);
}

/// Resolve the Export.Name of output `name` to a scalar string. Errors:
/// "cfn: unknown output: X", "cfn: output has no export: X",
/// "cfn: output export must resolve to a scalar: X", plus intrinsic errors.
pub fn cfn_output_export_name(doc: &JsonDoc, name: Str, ctx: &CfnContext) -> Result[Str, Str] {
  let on = json_object_get(doc, _section(doc, "Outputs"), name);
  if on < 0 {
    return _str_err("cfn: unknown output: " + name);
  }
  let ex = json_object_get(doc, on, "Export");
  if ex < 0 {
    return _str_err("cfn: output has no export: " + name);
  }
  let nn = json_object_get(doc, ex, "Name");
  if nn < 0 {
    return _str_err("cfn: output has no export: " + name);
  }
  let r = cfn_eval(doc, nn, ctx);
  match r {
    Ok(v) => {
      let k: Int = v.kind;
      if k != CFN_SCALAR {
        return _str_err("cfn: output export must resolve to a scalar: " + name);
      }
      let t: Str = v.text;
      return _str_ok(t);
    },
    Err(e) => { return _str_err(e); },
  }
  return _str_err("cfn: output export must resolve to a scalar: " + name);
}

// ---------------------------------------------------------------------------
// 8. Stack lifecycle state machine
// ---------------------------------------------------------------------------

/// A stack under the model state machine: current state plus the transition
/// history (parallel vectors: event i produced state i).
pub type Stack = {
  name: Str;
  state: Int;
  events: Vec[Int];
  states: Vec[Int];
}

/// A fresh stack in STACK_NOT_CREATED with an empty history.
pub fn stack_new(name: Str) -> Stack {
  return Stack{
    name: name;
    state: STACK_NOT_CREATED;
    events: Vec[Int].new();
    states: Vec[Int].new();
  };
}

/// Copy of `s` with the value of `event` applied. Err("cfn: stack cannot
/// apply <EVENT> in state <STATE>") for a transition the machine forbids.
pub fn stack_apply(s: &Stack, event: Int) -> Result[Stack, Str] {
  let next = _stack_next(s.state, event);
  if next < 0 {
    return _stack_err("cfn: stack cannot apply " + stack_event_name(event) + " in state " + stack_state_name(s.state));
  }
  var out = Stack{
    name: s.name;
    state: next;
    events: _copy_ints(&s.events);
    states: _copy_ints(&s.states);
  };
  out.events.push(event);
  out.states.push(next);
  return _stack_ok(out);
}

// The transition function: (state, event) -> next state, or -1.
fn _stack_next(state: Int, event: Int) -> Int {
  if state == STACK_NOT_CREATED {
    if event == STACK_EV_REVIEW_BEGIN { return STACK_REVIEW_IN_PROGRESS; }
    if event == STACK_EV_CREATE_BEGIN { return STACK_CREATE_IN_PROGRESS; }
    return CFN_NONE;
  }
  if state == STACK_REVIEW_IN_PROGRESS {
    if event == STACK_EV_CREATE_BEGIN { return STACK_CREATE_IN_PROGRESS; }
    if event == STACK_EV_UPDATE_BEGIN { return STACK_UPDATE_IN_PROGRESS; }
    return CFN_NONE;
  }
  if state == STACK_CREATE_IN_PROGRESS {
    if event == STACK_EV_SUCCEED { return STACK_CREATE_COMPLETE; }
    if event == STACK_EV_FAIL { return STACK_ROLLBACK_IN_PROGRESS; }
    return CFN_NONE;
  }
  if state == STACK_ROLLBACK_IN_PROGRESS {
    if event == STACK_EV_SUCCEED { return STACK_ROLLBACK_COMPLETE; }
    if event == STACK_EV_FAIL { return STACK_ROLLBACK_FAILED; }
    return CFN_NONE;
  }
  if state == STACK_CREATE_COMPLETE {
    if event == STACK_EV_UPDATE_BEGIN { return STACK_UPDATE_IN_PROGRESS; }
    if event == STACK_EV_DELETE_BEGIN { return STACK_DELETE_IN_PROGRESS; }
    return CFN_NONE;
  }
  if state == STACK_UPDATE_IN_PROGRESS {
    if event == STACK_EV_SUCCEED { return STACK_UPDATE_COMPLETE; }
    if event == STACK_EV_FAIL { return STACK_UPDATE_ROLLBACK_IN_PROGRESS; }
    return CFN_NONE;
  }
  if state == STACK_UPDATE_ROLLBACK_IN_PROGRESS {
    if event == STACK_EV_SUCCEED { return STACK_UPDATE_ROLLBACK_COMPLETE; }
    if event == STACK_EV_FAIL { return STACK_UPDATE_ROLLBACK_FAILED; }
    return CFN_NONE;
  }
  if state == STACK_UPDATE_COMPLETE {
    if event == STACK_EV_UPDATE_BEGIN { return STACK_UPDATE_IN_PROGRESS; }
    if event == STACK_EV_DELETE_BEGIN { return STACK_DELETE_IN_PROGRESS; }
    return CFN_NONE;
  }
  if state == STACK_ROLLBACK_COMPLETE {
    if event == STACK_EV_DELETE_BEGIN { return STACK_DELETE_IN_PROGRESS; }
    return CFN_NONE;
  }
  if state == STACK_UPDATE_ROLLBACK_COMPLETE {
    if event == STACK_EV_UPDATE_BEGIN { return STACK_UPDATE_IN_PROGRESS; }
    if event == STACK_EV_DELETE_BEGIN { return STACK_DELETE_IN_PROGRESS; }
    return CFN_NONE;
  }
  if state == STACK_ROLLBACK_FAILED {
    if event == STACK_EV_DELETE_BEGIN { return STACK_DELETE_IN_PROGRESS; }
    return CFN_NONE;
  }
  if state == STACK_UPDATE_ROLLBACK_FAILED {
    if event == STACK_EV_DELETE_BEGIN { return STACK_DELETE_IN_PROGRESS; }
    return CFN_NONE;
  }
  if state == STACK_CREATE_FAILED {
    if event == STACK_EV_DELETE_BEGIN { return STACK_DELETE_IN_PROGRESS; }
    return CFN_NONE;
  }
  if state == STACK_DELETE_IN_PROGRESS {
    if event == STACK_EV_SUCCEED { return STACK_DELETE_COMPLETE; }
    if event == STACK_EV_FAIL { return STACK_DELETE_FAILED; }
    return CFN_NONE;
  }
  if state == STACK_DELETE_FAILED {
    if event == STACK_EV_DELETE_BEGIN { return STACK_DELETE_IN_PROGRESS; }
    return CFN_NONE;
  }
  return CFN_NONE;
}

/// Stable display name of a stack state.
pub fn stack_state_name(state: Int) -> Str {
  if state == STACK_NOT_CREATED { return "NOT_CREATED"; }
  if state == STACK_CREATE_IN_PROGRESS { return "CREATE_IN_PROGRESS"; }
  if state == STACK_CREATE_COMPLETE { return "CREATE_COMPLETE"; }
  if state == STACK_CREATE_FAILED { return "CREATE_FAILED"; }
  if state == STACK_ROLLBACK_IN_PROGRESS { return "ROLLBACK_IN_PROGRESS"; }
  if state == STACK_ROLLBACK_COMPLETE { return "ROLLBACK_COMPLETE"; }
  if state == STACK_ROLLBACK_FAILED { return "ROLLBACK_FAILED"; }
  if state == STACK_UPDATE_IN_PROGRESS { return "UPDATE_IN_PROGRESS"; }
  if state == STACK_UPDATE_COMPLETE { return "UPDATE_COMPLETE"; }
  if state == STACK_UPDATE_ROLLBACK_IN_PROGRESS { return "UPDATE_ROLLBACK_IN_PROGRESS"; }
  if state == STACK_UPDATE_ROLLBACK_COMPLETE { return "UPDATE_ROLLBACK_COMPLETE"; }
  if state == STACK_UPDATE_ROLLBACK_FAILED { return "UPDATE_ROLLBACK_FAILED"; }
  if state == STACK_DELETE_IN_PROGRESS { return "DELETE_IN_PROGRESS"; }
  if state == STACK_DELETE_COMPLETE { return "DELETE_COMPLETE"; }
  if state == STACK_DELETE_FAILED { return "DELETE_FAILED"; }
  if state == STACK_REVIEW_IN_PROGRESS { return "REVIEW_IN_PROGRESS"; }
  return "UNKNOWN";
}

/// Stable display name of a stack event.
pub fn stack_event_name(event: Int) -> Str {
  if event == STACK_EV_CREATE_BEGIN { return "CREATE_BEGIN"; }
  if event == STACK_EV_UPDATE_BEGIN { return "UPDATE_BEGIN"; }
  if event == STACK_EV_DELETE_BEGIN { return "DELETE_BEGIN"; }
  if event == STACK_EV_SUCCEED { return "SUCCEED"; }
  if event == STACK_EV_FAIL { return "FAIL"; }
  if event == STACK_EV_REVIEW_BEGIN { return "REVIEW_BEGIN"; }
  return "UNKNOWN";
}

/// True while the stack state is an in-progress state.
pub fn stack_is_busy(state: Int) -> Bool {
  if state == STACK_CREATE_IN_PROGRESS { return true; }
  if state == STACK_ROLLBACK_IN_PROGRESS { return true; }
  if state == STACK_UPDATE_IN_PROGRESS { return true; }
  if state == STACK_UPDATE_ROLLBACK_IN_PROGRESS { return true; }
  if state == STACK_DELETE_IN_PROGRESS { return true; }
  if state == STACK_REVIEW_IN_PROGRESS { return true; }
  return false;
}

/// True for the four failed terminal states.
pub fn stack_is_failed(state: Int) -> Bool {
  if state == STACK_CREATE_FAILED { return true; }
  if state == STACK_ROLLBACK_FAILED { return true; }
  if state == STACK_UPDATE_ROLLBACK_FAILED { return true; }
  if state == STACK_DELETE_FAILED { return true; }
  return false;
}

/// Number of recorded transitions.
pub fn stack_history_len(s: &Stack) -> Int {
  return s.events.len();
}

/// Event recorded at history index `i`, or -1.
pub fn stack_history_event(s: &Stack, i: Int) -> Int {
  if i < 0 || i >= s.events.len() {
    return CFN_NONE;
  }
  let e: Int = s.events[i];
  return e;
}

/// State reached at history index `i`, or -1.
pub fn stack_history_state(s: &Stack, i: Int) -> Int {
  if i < 0 || i >= s.states.len() {
    return CFN_NONE;
  }
  let st: Int = s.states[i];
  return st;
}

// ---------------------------------------------------------------------------
// 9. Change sets (resource diff classification)
// ---------------------------------------------------------------------------

/// A resource-level change set: for each classified resource, its logical id,
/// kind (CHANGE_*), replacement flag (1 when the Type changed, 0 otherwise)
/// and old/new Type strings. All vectors are index-aligned.
pub type ChangeSet = {
  logical_ids: Vec[Str];
  kinds: Vec[Int];
  replacements: Vec[Int];
  old_types: Vec[Str];
  new_types: Vec[Str];
}

// Append one classification row (parallel vectors pushed together).
fn _cs_add(cs: &mut ChangeSet, logical: Str, kind: Int, repl: Int, ot: Str, nt: Str) {
  cs.logical_ids.push(logical);
  cs.kinds.push(kind);
  cs.replacements.push(repl);
  cs.old_types.push(ot);
  cs.new_types.push(nt);
}

/// Compute the resource diff old -> new. Order: every resource of `old`
/// (REMOVE / MODIFY / NONE in old document order), then resources only in
/// `new` (ADD in new document order). A resource is MODIFY when its Type
/// changed (replacement = 1) or its Properties subtree differs structurally
/// (replacement = 0, key order irrelevant). Change-set computation never
/// fails on structurally invalid templates; absent Resources sections diff
/// as empty.
pub fn changeset_compute(old: &JsonDoc, new: &JsonDoc) -> ChangeSet {
  var cs = ChangeSet{
    logical_ids: Vec[Str].new();
    kinds: Vec[Int].new();
    replacements: Vec[Int].new();
    old_types: Vec[Str].new();
    new_types: Vec[Str].new();
  };
  let orr = _section(old, "Resources");
  let nrr = _section(new, "Resources");
  let onc = json_member_count(old, orr);
  var i = 0;
  while i < onc {
    let id: Str = json_member_key(old, orr, i);
    let onode = json_member_value(old, orr, i);
    let ot = _resource_type_of(old, onode);
    let nnode = json_object_get(new, nrr, id);
    if nnode < 0 {
      _cs_add(&mut cs, id, CHANGE_REMOVE, 0, ot, "");
    } else {
      let nt = _resource_type_of(new, nnode);
      if !_streq(ot, nt) {
        _cs_add(&mut cs, id, CHANGE_MODIFY, 1, ot, nt);
      } else {
        let op = json_object_get(old, onode, "Properties");
        let np = json_object_get(new, nnode, "Properties");
        if _nodes_equal(old, op, new, np) {
          _cs_add(&mut cs, id, CHANGE_NONE, 0, ot, nt);
        } else {
          _cs_add(&mut cs, id, CHANGE_MODIFY, 0, ot, nt);
        }
      }
    }
    i = i + 1;
  }
  let nnc = json_member_count(new, nrr);
  i = 0;
  while i < nnc {
    let id: Str = json_member_key(new, nrr, i);
    let existed = json_object_get(old, orr, id);
    if existed < 0 {
      let nnode = json_member_value(new, nrr, i);
      let nt = _resource_type_of(new, nnode);
      _cs_add(&mut cs, id, CHANGE_ADD, 0, "", nt);
    }
    i = i + 1;
  }
  return cs;
}

/// Number of classified resources.
pub fn changeset_len(cs: &ChangeSet) -> Int {
  return cs.logical_ids.len();
}

/// Logical id of row `i`, or "".
pub fn changeset_logical(cs: &ChangeSet, i: Int) -> Str {
  if i < 0 || i >= cs.logical_ids.len() {
    return "";
  }
  let s: Str = cs.logical_ids[i];
  return s;
}

/// Kind of row `i`, or CFN_NONE.
pub fn changeset_kind(cs: &ChangeSet, i: Int) -> Int {
  if i < 0 || i >= cs.kinds.len() {
    return CFN_NONE;
  }
  let k: Int = cs.kinds[i];
  return k;
}

/// True when row `i` is flagged as requiring replacement.
pub fn changeset_is_replacement(cs: &ChangeSet, i: Int) -> Bool {
  if i < 0 || i >= cs.replacements.len() {
    return false;
  }
  let r: Int = cs.replacements[i];
  return r != 0;
}

/// Old Type of row `i`, or "".
pub fn changeset_old_type(cs: &ChangeSet, i: Int) -> Str {
  if i < 0 || i >= cs.old_types.len() {
    return "";
  }
  let s: Str = cs.old_types[i];
  return s;
}

/// New Type of row `i`, or "".
pub fn changeset_new_type(cs: &ChangeSet, i: Int) -> Str {
  if i < 0 || i >= cs.new_types.len() {
    return "";
  }
  let s: Str = cs.new_types[i];
  return s;
}

/// Stable display name of a change kind.
pub fn changeset_kind_name(kind: Int) -> Str {
  if kind == CHANGE_NONE { return "NONE"; }
  if kind == CHANGE_ADD { return "ADD"; }
  if kind == CHANGE_REMOVE { return "REMOVE"; }
  if kind == CHANGE_MODIFY { return "MODIFY"; }
  return "UNKNOWN";
}

/// Number of rows with the given kind.
pub fn changeset_count(cs: &ChangeSet, kind: Int) -> Int {
  var n = 0;
  var i = 0;
  while i < cs.kinds.len() {
    let k: Int = cs.kinds[i];
    if k == kind {
      n = n + 1;
    }
    i = i + 1;
  }
  return n;
}

/// True when at least one row is not CHANGE_NONE.
pub fn changeset_has_changes(cs: &ChangeSet) -> Bool {
  var i = 0;
  while i < cs.kinds.len() {
    let k: Int = cs.kinds[i];
    if k != CHANGE_NONE {
      return true;
    }
    i = i + 1;
  }
  return false;
}
