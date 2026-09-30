// XIOM -- xiom.legacy_proto: Finger, Gopher and WHOIS text-protocol codecs
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Port task: implement xiom.legacy-proto as a real, tested, pure-XIOM codec
// for three legacy internet text protocols:
//   * Finger (RFC 1288): query lines ("user", "user/W") and responses that
//     are either one line or a CRLF-separated block ended by a lone ".".
//   * Gopher (RFC 1436): menu documents of type+display+selector+host+port
//     lines, with info-text lines starting with ".".
//   * WHOIS (RFC 3912): response records of "Key: value" fields, repeated
//     keys, continuation lines and "%"/"#" comment lines.
// Text in, text out: every function takes and returns Str / plain structs;
// there is no I/O, no networking and no FFI.
//
// Wire model (the exact grammar is pinned in SPEC.md):
//   finger query    = [ user ] [ "/W" ] CRLF
//   finger response = line *( CRLF line ) [ CRLF "." ] CRLF
//   gopher item     = type display TAB selector TAB host TAB port CRLF
//   gopher info     = "." display CRLF
//   whois field     = key ":" value CRLF
//   whois comment   = ( "%" / "#" ) ... CRLF
//
// v0.62.2 notes that shaped this module:
//   * free functions only: no self methods, no lambdas, no Vec[StructType]
//     and no Vec[Float64]; the menu and record models are flat, with
//     parallel homogeneous vectors (trap 10);
//   * Str values are never compared with `==` when they were read from a
//     Vec[Str] element (that lowers to a pointer comparison); key lookups go
//     through xiom.string.compare.str_compare (trap 1);
//   * every Vec[Int]/Vec[Str] element read is bound with a typed `let`
//     first (traps 2 and 16);
//   * byte_at results are compared directly to UInt8 constants and widened
//     with `(b as Int) & 0xFF` only for arithmetic (traps 3 and 13);
//   * `&struct.field` is never passed as a `&Vec[...]` parameter; fields
//     are bound to locals first (trap 4);
//   * Ok/Err for Result[...] are constructed only in the tiny leaf helpers
//     below (trap 6);
//   * no mutable match bindings, every match is exhaustive (trap 8);
//   * decimal output uses xiom.convert.int_to_string, never sb_push_int,
//     and no builder materializes NUL-bearing bytes (trap 15);
//   * every loop makes progress: each body either increments its cursor or
//     returns (the suite terminates in well under a second).

module xiom.legacy_proto

use xiom.string;
use xiom.string.compare;
use xiom.convert;

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

// Byte constants (compared directly against byte_at results).
const _LF: UInt8 = 10u8;
const _TAB: UInt8 = 9u8;
const _CR: UInt8 = 13u8;
const _SP: UInt8 = 32u8;
const _DOT: UInt8 = 46u8;
const _SLASH: UInt8 = 47u8;
const _HASH: UInt8 = 35u8;
const _PERCENT: UInt8 = 37u8;
const _COLON: UInt8 = 58u8;
const _W_UPPER: UInt8 = 87u8;
const _W_LOWER: UInt8 = 119u8;
const _BACKSLASH: UInt8 = 92u8;
const _LOWER_N: UInt8 = 110u8;
const _LOWER_R: UInt8 = 114u8;
const _LOWER_T: UInt8 = 116u8;

/// Default Finger service port (RFC 1288).
pub const FINGER_PORT_DEFAULT: Int = 79;
/// Default Gopher service port (RFC 1436).
pub const GOPHER_PORT_DEFAULT: Int = 70;
/// Default WHOIS service port (RFC 3912).
pub const WHOIS_PORT_DEFAULT: Int = 43;

// ---------------------------------------------------------------------------
// Result constructors (leaf helpers; see the module header, trap 6)
// ---------------------------------------------------------------------------

// Ok(q) for Result[FingerQuery, Str].
fn _ok_finger_query(q: FingerQuery) -> Result[FingerQuery, Str] {
  return Ok(q);
}

// Err(m) for Result[FingerQuery, Str].
fn _err_finger_query(m: Str) -> Result[FingerQuery, Str] {
  return Err(m);
}

// Ok(r) for Result[FingerResponse, Str].
fn _ok_finger_response(r: FingerResponse) -> Result[FingerResponse, Str] {
  return Ok(r);
}

// Err(m) for Result[FingerResponse, Str].
fn _err_finger_response(m: Str) -> Result[FingerResponse, Str] {
  return Err(m);
}

// Ok(i) for Result[GopherItem, Str].
fn _ok_gopher_item(i: GopherItem) -> Result[GopherItem, Str] {
  return Ok(i);
}

// Err(m) for Result[GopherItem, Str].
fn _err_gopher_item(m: Str) -> Result[GopherItem, Str] {
  return Err(m);
}

// Ok(m) for Result[GopherMenu, Str].
fn _ok_gopher_menu(m: GopherMenu) -> Result[GopherMenu, Str] {
  return Ok(m);
}

// Err(m) for Result[GopherMenu, Str].
fn _err_gopher_menu(m: Str) -> Result[GopherMenu, Str] {
  return Err(m);
}

// Ok(r) for Result[WhoisRecord, Str].
fn _ok_whois(r: WhoisRecord) -> Result[WhoisRecord, Str] {
  return Ok(r);
}

// Err(m) for Result[WhoisRecord, Str].
fn _err_whois(m: Str) -> Result[WhoisRecord, Str] {
  return Err(m);
}

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

/// One parsed Finger query. `username` is the requested user ("" selects the
/// server default user) and `verbose` is true when the long "/W" format was
/// requested.
pub type FingerQuery = {
  username: Str;
  verbose: Bool;
}

/// One parsed Finger response. `lines` holds the content lines with their
/// terminators stripped (empty lines preserved); `is_multiline` is true when
/// the wire form was multi-line (more than one line, or a terminator line was
/// present); `had_terminator` records whether a lone "." line ended it.
pub type FingerResponse = {
  lines: Vec[Str];
  is_multiline: Bool;
  had_terminator: Bool;
}

/// One parsed Gopher menu item. `item_type` is the one-byte item type ("."
/// marks an info-text line, in which case `selector`/`host` are empty and
/// `port` is 0); `display`, `selector` and `host` are decoded from the codec
/// escape convention (section 5 of SPEC.md) and `port` is 0..65535.
pub type GopherItem = {
  item_type: Str;
  display: Str;
  selector: Str;
  host: Str;
  port: Int;
}

/// One parsed Gopher menu document. The five vectors are parallel and equal
/// length; `types[i]` is the one-byte item type of item `i`.
pub type GopherMenu = {
  types: Vec[Str];
  displays: Vec[Str];
  selectors: Vec[Str];
  hosts: Vec[Str];
  ports: Vec[Int];
}

/// One parsed WHOIS response. `keys`/`values` are parallel (repeated keys
/// preserved in wire order); `continuation_counts[i]` is how many
/// continuation lines followed field `i` and those lines are stored in
/// `continuations` in wire order (the first `continuation_counts[0]` entries
/// belong to field 0, and so on); `comments` holds "%"/"#" lines in wire
/// order, trimmed of surrounding whitespace.
pub type WhoisRecord = {
  keys: Vec[Str];
  values: Vec[Str];
  continuation_counts: Vec[Int];
  continuations: Vec[Str];
  comments: Vec[Str];
}

// ---------------------------------------------------------------------------
// Byte and line helpers
// ---------------------------------------------------------------------------

// True when byte `b` is an ASCII space or tab.
fn _is_ws_byte(b: UInt8) -> Bool {
  return b == _SP || b == _TAB;
}

// Index of the first `target` byte in [from, end), or -1.
fn _find_byte(s: Str, from: Int, end: Int, target: UInt8) -> Int {
  var i = from;
  while i < end {
    if string.byte_at(s, i) == target {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// End of the first line: the index of the first CR or LF, or len(s) when the
// text carries neither.
fn _line_end(s: Str) -> Int {
  var i = 0;
  while i < s.len() {
    let b = string.byte_at(s, i);
    if b == _CR || b == _LF {
      return i;
    }
    i = i + 1;
  }
  return s.len();
}

// First index in [from, to) holding a non-space/tab byte (to when none).
fn _ltrim_start(s: Str, from: Int, to: Int) -> Int {
  var i = from;
  while i < to && _is_ws_byte(string.byte_at(s, i)) {
    i = i + 1;
  }
  return i;
}

// End index after stripping trailing space/tab bytes from [from, to).
fn _rtrim_end(s: Str, from: Int, to: Int) -> Int {
  var e = to;
  while e > from && _is_ws_byte(string.byte_at(s, e - 1)) {
    e = e - 1;
  }
  return e;
}

// The [from, to) slice with surrounding space/tab bytes removed; "" when the
// range is empty or only whitespace.
fn _trimmed(s: Str, from: Int, to: Int) -> Str {
  let a = _ltrim_start(s, from, to);
  let b = _rtrim_end(s, a, to);
  if a >= b {
    return "";
  }
  return string.str_slice(s, a, b);
}

// True when [from, to) holds no byte other than space and tab.
fn _is_blank_range(s: Str, from: Int, to: Int) -> Bool {
  var i = from;
  while i < to {
    if !_is_ws_byte(string.byte_at(s, i)) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// True when the whole string is empty or only space/tab bytes.
fn _is_blank(s: Str) -> Bool {
  return _is_blank_range(s, 0, s.len());
}

// True when [from, to) holds a space or tab byte.
fn _has_ws(s: Str, from: Int, to: Int) -> Bool {
  var i = from;
  while i < to {
    if _is_ws_byte(string.byte_at(s, i)) {
      return true;
    }
    i = i + 1;
  }
  return false;
}

// Split `text` into lines at CRLF, LF or CR boundaries. Terminators are
// stripped; a final unterminated segment is kept; a trailing terminator does
// not produce a phantom empty line (stdlib `string.lines` is LF-only and
// keeps the CR, so this stays hand-rolled -- see SPEC.md section 12).
fn _split_lines(text: Str) -> Vec[Str] {
  var out = Vec[Str].new();
  let n = text.len();
  var start = 0;
  var i = 0;
  while i < n {
    let b = string.byte_at(text, i);
    if b == _CR {
      out.push(string.str_slice(text, start, i));
      if i + 1 < n && string.byte_at(text, i + 1) == _LF {
        i = i + 2;
      } else {
        i = i + 1;
      }
      start = i;
    } elif b == _LF {
      out.push(string.str_slice(text, start, i));
      i = i + 1;
      start = i;
    } else {
      i = i + 1;
    }
  }
  if start < n {
    out.push(string.str_slice(text, start, n));
  }
  return out;
}

// True when `s` is exactly the one-byte string ".".
fn _is_dot(s: Str) -> Bool {
  if s.len() != 1 {
    return false;
  }
  return string.byte_at(s, 0) == _DOT;
}

// Strict unsigned decimal of a Gopher port field: 0..65535, all ASCII
// digits, at most five bytes. Returns -1 when the text is empty, carries a
// non-digit byte, or exceeds 65535. (xiom.convert.parse.parse_int accepts a
// leading sign and is not wire-strict, so this stays hand-rolled -- see
// SPEC.md section 12.)
fn _parse_port(t: Str) -> Int {
  let n = t.len();
  if n == 0 || n > 5 {
    return -1;
  }
  var v = 0;
  var i = 0;
  while i < n {
    let b: Int = (string.byte_at(t, i) as Int) & 0xFF;
    if b < 48 || b > 57 {
      return -1;
    }
    v = v * 10 + (b - 48);
    if v > 65535 {
      return -1;
    }
    i = i + 1;
  }
  return v;
}

// ---------------------------------------------------------------------------
// Gopher field escaping
// ---------------------------------------------------------------------------

// Decode the codec escape convention in one Gopher text field: backslash + t
// decodes to TAB, backslash + n to LF, backslash + r to CR and backslash +
// backslash to one backslash. Any other escape keeps both bytes verbatim; a
// lone trailing backslash is kept (section 5 of SPEC.md).
fn _unescape_field(raw: Str) -> Str {
  let n = raw.len();
  var out = "";
  var seg = 0;
  var i = 0;
  while i < n {
    if string.byte_at(raw, i) == _BACKSLASH && i + 1 < n {
      let c = string.byte_at(raw, i + 1);
      if c == _LOWER_T {
        out = out + string.str_slice(raw, seg, i) + "\t";
        i = i + 2;
        seg = i;
      } elif c == _LOWER_N {
        out = out + string.str_slice(raw, seg, i) + "\n";
        i = i + 2;
        seg = i;
      } elif c == _LOWER_R {
        out = out + string.str_slice(raw, seg, i) + "\r";
        i = i + 2;
        seg = i;
      } elif c == _BACKSLASH {
        out = out + string.str_slice(raw, seg, i) + "\\";
        i = i + 2;
        seg = i;
      } else {
        i = i + 2;
      }
    } else {
      i = i + 1;
    }
  }
  return out + string.str_slice(raw, seg, n);
}

// Encode one Gopher text field: TAB -> backslash + t, LF -> backslash + n,
// CR -> backslash + r, backslash -> backslash + backslash; every other byte
// passes through verbatim. This makes the codec lossless for arbitrary field
// bytes (section 5 of SPEC.md).
fn _escape_field(raw: Str) -> Str {
  let n = raw.len();
  var out = "";
  var seg = 0;
  var i = 0;
  while i < n {
    let b = string.byte_at(raw, i);
    if b == _TAB {
      out = out + string.str_slice(raw, seg, i) + "\\t";
      i = i + 1;
      seg = i;
    } elif b == _LF {
      out = out + string.str_slice(raw, seg, i) + "\\n";
      i = i + 1;
      seg = i;
    } elif b == _CR {
      out = out + string.str_slice(raw, seg, i) + "\\r";
      i = i + 1;
      seg = i;
    } elif b == _BACKSLASH {
      out = out + string.str_slice(raw, seg, i) + "\\\\";
      i = i + 1;
      seg = i;
    } else {
      i = i + 1;
    }
  }
  return out + string.str_slice(raw, seg, n);
}

// ---------------------------------------------------------------------------
// Finger -- query
// ---------------------------------------------------------------------------

/// Parse one Finger query line.
/// Params: query - one query with or without a trailing CRLF/LF/CR.
/// Grammar: `[ user ] [ "/W" ]`; the exact statement is in SPEC.md. The
/// input is truncated at the first CR or LF, then surrounding spaces/tabs
/// are stripped. A trailing "/W" or "/w" requests the long format and is
/// removed from the user name; an empty user name selects the server default
/// user.
/// Returns: Ok(FingerQuery) with `username` ("" = default user) and
/// `verbose`.
/// Error case: Err("finger: empty query") when no non-space byte remains;
/// Err("finger: whitespace in query") when the user name holds an interior
/// space or tab.
/// Complexity: O(len(query)).
pub fn finger_parse_query(query: Str) -> Result[FingerQuery, Str] {
  let n = _line_end(query);
  let start = _ltrim_start(query, 0, n);
  var end = _rtrim_end(query, start, n);
  if start >= end {
    return _err_finger_query("finger: empty query");
  }
  var verbose = false;
  if end - start >= 2 {
    let last = string.byte_at(query, end - 1);
    let prev = string.byte_at(query, end - 2);
    if prev == _SLASH && (last == _W_UPPER || last == _W_LOWER) {
      verbose = true;
      end = _rtrim_end(query, start, end - 2);
    }
  }
  if _has_ws(query, start, end) {
    return _err_finger_query("finger: whitespace in query");
  }
  let user = string.str_slice(query, start, end);
  let q = FingerQuery{ username: user; verbose: verbose; };
  return _ok_finger_query(q);
}

/// Render one Finger query in canonical form.
/// Params: q - a query produced by finger_parse_query (or constructed).
/// Returns: `username` plus "/W" when `verbose`, terminated by CRLF; an
/// empty user name with `verbose` renders as "/W\r\n".
/// Error case: none.
/// Complexity: O(len(username)).
pub fn finger_render_query(q: &FingerQuery) -> Str {
  let u: Str = q.username;
  if q.verbose {
    return u + "/W\r\n";
  }
  return u + "\r\n";
}

// ---------------------------------------------------------------------------
// Finger -- response
// ---------------------------------------------------------------------------

/// Parse one Finger response body.
/// Params: text - the response text; lines may be separated by CRLF, LF or
/// CR and a final unterminated line is accepted.
/// Grammar: one or more content lines, optionally followed by a lone "."
/// terminator line (RFC 1288 long format). The first lone "." ends the
/// response and everything after it is ignored; content lines are kept
/// verbatim (empty lines included).
/// Returns: Ok(FingerResponse) with the content lines, `is_multiline` true
/// when more than one line or a terminator was present, and
/// `had_terminator` recording the lone ".".
/// Error case: Err("finger: empty response") when no content line precedes
/// the (optional) terminator.
/// Complexity: O(len(text)).
pub fn finger_parse_response(text: Str) -> Result[FingerResponse, Str] {
  let raw_lines = _split_lines(text);
  var lines = Vec[Str].new();
  var had_term = false;
  var i = 0;
  while i < raw_lines.len() {
    let ln: Str = raw_lines[i];
    if _is_dot(ln) {
      had_term = true;
      break;
    }
    lines.push(ln);
    i = i + 1;
  }
  if lines.len() == 0 {
    return _err_finger_response("finger: empty response");
  }
  var multiline = lines.len() > 1;
  if had_term {
    multiline = true;
  }
  let resp = FingerResponse{ lines: lines; is_multiline: multiline; had_terminator: had_term; };
  return _ok_finger_response(resp);
}

/// Render one Finger response in canonical form.
/// Params: r - a response produced by finger_parse_response (or constructed).
/// Returns: every content line followed by CRLF, then a ".\r\n" terminator
/// when `is_multiline` or `had_terminator` (RFC 1288 requires the terminator
/// for the long format). A single-line response without a terminator renders
/// as one CRLF-terminated line.
/// Error case: none.
/// Complexity: O(total length).
pub fn finger_render_response(r: &FingerResponse) -> Str {
  var out = "";
  var i = 0;
  while i < r.lines.len() {
    let ln: Str = r.lines[i];
    out = out + ln + "\r\n";
    i = i + 1;
  }
  if r.is_multiline || r.had_terminator {
    out = out + ".\r\n";
  }
  return out;
}

/// True when the response was multi-line (more than one content line or a
/// terminator line). Params: r - the parsed response. Returns: `r.is_multiline`.
/// Error case: none. Complexity: O(1).
pub fn finger_is_multiline(r: &FingerResponse) -> Bool {
  return r.is_multiline;
}

/// Number of content lines. Params: r - the parsed response.
/// Returns: the line count. Error case: none. Complexity: O(1).
pub fn finger_line_count(r: &FingerResponse) -> Int {
  return r.lines.len();
}

/// Content line `i`, terminator stripped.
/// Params: r - the parsed response; i - zero-based line index.
/// Returns: the line text; "" when i is negative or past the last line.
/// Error case: none. Complexity: O(1).
pub fn finger_line(r: &FingerResponse, i: Int) -> Str {
  if i < 0 || i >= r.lines.len() {
    return "";
  }
  let v: Str = r.lines[i];
  return v;
}

// ---------------------------------------------------------------------------
// Gopher -- items
// ---------------------------------------------------------------------------

// Validation reason for one Gopher item line (CR/LF already truncated), or
// "" when the line is well formed. Order: empty, info line, field count,
// item type, port (SPEC.md section 6).
fn _gopher_item_reason(line: Str) -> Str {
  let n = line.len();
  if n == 0 {
    return "empty line";
  }
  if string.byte_at(line, 0) == _DOT {
    return "";
  }
  var tabs = 0;
  var i = 0;
  while i < n {
    if string.byte_at(line, i) == _TAB {
      tabs = tabs + 1;
    }
    i = i + 1;
  }
  if tabs < 3 {
    return "missing fields";
  }
  if tabs > 3 {
    return "too many fields";
  }
  let tb: Int = (string.byte_at(line, 0) as Int) & 0xFF;
  if tb < 33 || tb > 126 {
    return "invalid item type";
  }
  let p2 = _find_byte(line, 0, n, _TAB);
  let p3 = _find_byte(line, p2 + 1, n, _TAB);
  let p4 = _find_byte(line, p3 + 1, n, _TAB);
  let port = _parse_port(string.str_slice(line, p4 + 1, n));
  if port < 0 {
    return "invalid port";
  }
  return "";
}

// Build a GopherItem from a line already accepted by _gopher_item_reason.
// Wire shape: type display TAB selector TAB host TAB port.
fn _gopher_item_from_line(line: Str) -> GopherItem {
  let n = line.len();
  if string.byte_at(line, 0) == _DOT {
    let d = _unescape_field(string.str_slice(line, 1, n));
    return GopherItem{ item_type: "."; display: d; selector: ""; host: ""; port: 0; };
  }
  let t0 = _find_byte(line, 0, n, _TAB);
  let t1 = _find_byte(line, t0 + 1, n, _TAB);
  let t2 = _find_byte(line, t1 + 1, n, _TAB);
  let tp = string.str_slice(line, 0, 1);
  let dp = _unescape_field(string.str_slice(line, 1, t0));
  let sp = _unescape_field(string.str_slice(line, t0 + 1, t1));
  let hp = _unescape_field(string.str_slice(line, t1 + 1, t2));
  let pp = _parse_port(string.str_slice(line, t2 + 1, n));
  return GopherItem{ item_type: tp; display: dp; selector: sp; host: hp; port: pp; };
}

/// Parse one Gopher menu line.
/// Params: line - one menu line, with or without a trailing CRLF/LF/CR.
/// Grammar: `type display TAB selector TAB host TAB port` where `type` is one
/// printable non-tab byte (33..126), or a display-text line starting with
/// "." (RFC 1436 info text; everything after the "." is the display).
/// `display`, `selector` and `host` are decoded per the codec escape
/// convention.
/// Returns: Ok(GopherItem); info-text lines carry item_type ".", empty
/// selector/host and port 0.
/// Error case: Err("gopher: empty line"); Err("gopher: missing fields") for
/// fewer than three tabs; Err("gopher: too many fields") for more than three;
/// Err("gopher: invalid item type") when the type byte is not printable
/// 33..126; Err("gopher: invalid port") when the port field is not 1..5
/// ASCII digits within 0..65535.
/// Complexity: O(len(line)).
pub fn gopher_parse_item(line: Str) -> Result[GopherItem, Str] {
  let body = string.str_slice(line, 0, _line_end(line));
  let reason = _gopher_item_reason(body);
  if reason.len() > 0 {
    return _err_gopher_item("gopher: " + reason);
  }
  let item = _gopher_item_from_line(body);
  return _ok_gopher_item(item);
}

/// Render one Gopher menu line in canonical form.
/// Params: item - an item produced by gopher_parse_item (or constructed).
/// Returns: for info text, "." + escaped display + CRLF; otherwise the type
/// byte + escaped display + TAB + escaped selector + TAB + escaped host +
/// TAB + decimal port + CRLF. The three text fields are escaped per the
/// codec convention, so display/selector/host bytes are lossless.
/// Error case: none (values from gopher_parse_item always satisfy the
/// item invariants).
/// Complexity: O(total length).
pub fn gopher_render_item(item: &GopherItem) -> Str {
  let t: Str = item.item_type;
  let d: Str = item.display;
  if _is_dot(t) {
    return "." + _escape_field(d) + "\r\n";
  }
  let s: Str = item.selector;
  let h: Str = item.host;
  let p: Int = item.port;
  return t + _escape_field(d) + "\t" + _escape_field(s) + "\t" + _escape_field(h) + "\t" + convert.int_to_string(p) + "\r\n";
}

// ---------------------------------------------------------------------------
// Gopher -- menus
// ---------------------------------------------------------------------------

/// Parse a whole Gopher menu document.
/// Params: text - the menu text; lines may be separated by CRLF, LF or CR.
/// Grammar: one or more menu lines as accepted by gopher_parse_item, in
/// order. Every line must be well formed (blank lines are errors, not
/// separators).
/// Returns: Ok(GopherMenu) with the five parallel vectors (types, displays,
/// selectors, hosts, ports) of equal length.
/// Error case: Err("gopher: empty menu") when the document holds no line;
/// Err("gopher: line N: <reason>") with the 1-based line number and the
/// gopher_parse_item reason for the first malformed line.
/// Complexity: O(len(text)).
pub fn gopher_parse_menu(text: Str) -> Result[GopherMenu, Str] {
  let raw_lines = _split_lines(text);
  if raw_lines.len() == 0 {
    return _err_gopher_menu("gopher: empty menu");
  }
  var types = Vec[Str].new();
  var displays = Vec[Str].new();
  var selectors = Vec[Str].new();
  var hosts = Vec[Str].new();
  var ports = Vec[Int].new();
  var i = 0;
  while i < raw_lines.len() {
    let ln: Str = raw_lines[i];
    let reason = _gopher_item_reason(ln);
    if reason.len() > 0 {
      return _err_gopher_menu("gopher: line " + convert.int_to_string(i + 1) + ": " + reason);
    }
    let it = _gopher_item_from_line(ln);
    let t: Str = it.item_type;
    let d: Str = it.display;
    let s: Str = it.selector;
    let h: Str = it.host;
    let p: Int = it.port;
    types.push(t);
    displays.push(d);
    selectors.push(s);
    hosts.push(h);
    ports.push(p);
    i = i + 1;
  }
  let menu = GopherMenu{ types: types; displays: displays; selectors: selectors; hosts: hosts; ports: ports; };
  return _ok_gopher_menu(menu);
}

/// Render a whole Gopher menu document in canonical form.
/// Params: m - a menu produced by gopher_parse_menu (or constructed with
/// equal-length parallel vectors).
/// Returns: every item rendered by gopher_render_item, joined in order with
/// CRLF line endings; a canonical menu is byte-stable across
/// parse/render/re-parse.
/// Error case: none (parse maintains the parallel-vector invariant).
/// Complexity: O(total length).
pub fn gopher_render_menu(m: &GopherMenu) -> Str {
  var out = "";
  var i = 0;
  while i < m.types.len() {
    let t: Str = m.types[i];
    let d: Str = m.displays[i];
    if _is_dot(t) {
      out = out + "." + _escape_field(d) + "\r\n";
    } else {
      let s: Str = m.selectors[i];
      let h: Str = m.hosts[i];
      let p: Int = m.ports[i];
      out = out + t + _escape_field(d) + "\t" + _escape_field(s) + "\t" + _escape_field(h) + "\t" + convert.int_to_string(p) + "\r\n";
    }
    i = i + 1;
  }
  return out;
}

/// Number of items in the menu.
/// Params: m - the parsed menu. Returns: types.len(). Error case: none.
/// Complexity: O(1).
pub fn gopher_item_count(m: &GopherMenu) -> Int {
  return m.types.len();
}

/// Item type of item `i` (a one-byte Str, "." for info text).
/// Params: m - the parsed menu; i - zero-based item index.
/// Returns: the type; "" when i is negative or past the last item.
/// Error case: none. Complexity: O(1).
pub fn gopher_item_type(m: &GopherMenu, i: Int) -> Str {
  if i < 0 || i >= m.types.len() {
    return "";
  }
  let v: Str = m.types[i];
  return v;
}

/// Display text of item `i`.
/// Params: m - the parsed menu; i - zero-based item index.
/// Returns: the decoded display text; "" when i is out of range.
/// Error case: none. Complexity: O(1).
pub fn gopher_item_display(m: &GopherMenu, i: Int) -> Str {
  if i < 0 || i >= m.displays.len() {
    return "";
  }
  let v: Str = m.displays[i];
  return v;
}

/// Selector of item `i`.
/// Params: m - the parsed menu; i - zero-based item index.
/// Returns: the decoded selector ("" for info text); "" when i is out of
/// range. Error case: none. Complexity: O(1).
pub fn gopher_item_selector(m: &GopherMenu, i: Int) -> Str {
  if i < 0 || i >= m.selectors.len() {
    return "";
  }
  let v: Str = m.selectors[i];
  return v;
}

/// Host of item `i`.
/// Params: m - the parsed menu; i - zero-based item index.
/// Returns: the decoded host ("" for info text); "" when i is out of range.
/// Error case: none. Complexity: O(1).
pub fn gopher_item_host(m: &GopherMenu, i: Int) -> Str {
  if i < 0 || i >= m.hosts.len() {
    return "";
  }
  let v: Str = m.hosts[i];
  return v;
}

/// Port of item `i` (0..65535).
/// Params: m - the parsed menu; i - zero-based item index.
/// Returns: the port number, or -1 when i is negative or past the last item.
/// Error case: none. Complexity: O(1).
pub fn gopher_item_port(m: &GopherMenu, i: Int) -> Int {
  if i < 0 || i >= m.ports.len() {
    return -1;
  }
  let v: Int = m.ports[i];
  return v;
}

/// True when item `i` is an info-text line (type ".").
/// Params: m - the parsed menu; i - zero-based item index.
/// Returns: true for a "." type; false otherwise (including out of range).
/// Error case: none. Complexity: O(1).
pub fn gopher_item_is_text(m: &GopherMenu, i: Int) -> Bool {
  if i < 0 || i >= m.types.len() {
    return false;
  }
  let t: Str = m.types[i];
  return _is_dot(t);
}

// ---------------------------------------------------------------------------
// WHOIS
// ---------------------------------------------------------------------------

/// Parse a WHOIS response into a flat record.
/// Params: text - the response text; lines may be separated by CRLF, LF or
/// CR.
/// Grammar: blank lines are skipped; a line whose first non-space byte is
/// "%" or "#" is a comment; a line holding ":" is a `key ":" value` field
/// (only the first colon splits, key and value are trimmed of surrounding
/// spaces/tabs, an empty value is legal); any other line is a continuation
/// of the most recent field. Repeated keys are preserved in wire order.
/// Returns: Ok(WhoisRecord) with parallel `keys`/`values`,
/// `continuation_counts` plus the flattened `continuations`, and `comments`.
/// Error case: Err("whois: empty response") when the text yields no field
/// and no comment; Err("whois: empty key") for a line whose key part is
/// empty (": x", "   :x"); Err("whois: continuation before any field") for
/// a non-field line before the first field.
/// Complexity: O(len(text)).
pub fn whois_parse(text: Str) -> Result[WhoisRecord, Str] {
  let raw_lines = _split_lines(text);
  var keys = Vec[Str].new();
  var values = Vec[Str].new();
  var cont_counts = Vec[Int].new();
  var conts = Vec[Str].new();
  var comments = Vec[Str].new();
  var i = 0;
  while i < raw_lines.len() {
    let ln: Str = raw_lines[i];
    if !_is_blank(ln) {
      let s = _ltrim_start(ln, 0, ln.len());
      let e = _rtrim_end(ln, s, ln.len());
      let b0 = string.byte_at(ln, s);
      if b0 == _PERCENT || b0 == _HASH {
        comments.push(string.str_slice(ln, s, e));
      } else {
        let colon = _find_byte(ln, s, e, _COLON);
        if colon < 0 {
          if keys.len() == 0 {
            return _err_whois("whois: continuation before any field");
          }
          let last = cont_counts.len() - 1;
          let c: Int = cont_counts[last];
          cont_counts[last] = c + 1;
          conts.push(string.str_slice(ln, s, e));
        } else {
          let k = _trimmed(ln, s, colon);
          if k.len() == 0 {
            return _err_whois("whois: empty key");
          }
          let v = _trimmed(ln, colon + 1, e);
          keys.push(k);
          values.push(v);
          cont_counts.push(0);
        }
      }
    }
    i = i + 1;
  }
  if keys.len() == 0 && comments.len() == 0 {
    return _err_whois("whois: empty response");
  }
  let rec = WhoisRecord{
    keys: keys;
    values: values;
    continuation_counts: cont_counts;
    continuations: conts;
    comments: comments;
  };
  return _ok_whois(rec);
}

/// Render a WHOIS record in canonical form.
/// Params: r - a record produced by whois_parse (or constructed).
/// Returns: every comment line (verbatim, marker included) followed by CRLF,
/// then every field as `key ": " value` (or `key ":"` for an empty value)
/// followed by CRLF and its continuation lines; line endings are CRLF.
/// Canonical order is comments first, then fields in wire order, so a parsed
/// document re-parses to the same logical record.
/// Error case: none.
/// Complexity: O(total length).
pub fn whois_render(r: &WhoisRecord) -> Str {
  var out = "";
  var i = 0;
  while i < r.comments.len() {
    let c: Str = r.comments[i];
    out = out + c + "\r\n";
    i = i + 1;
  }
  i = 0;
  while i < r.keys.len() {
    let k: Str = r.keys[i];
    let v: Str = r.values[i];
    if v.len() == 0 {
      out = out + k + ":\r\n";
    } else {
      out = out + k + ": " + v + "\r\n";
    }
    let cc: Int = r.continuation_counts[i];
    var j = 0;
    while j < cc {
      let line = whois_continuation(r, i, j);
      out = out + line + "\r\n";
      j = j + 1;
    }
    i = i + 1;
  }
  return out;
}

/// Number of fields (repeated keys counted).
/// Params: r - the parsed record. Returns: keys.len().
/// Error case: none. Complexity: O(1).
pub fn whois_field_count(r: &WhoisRecord) -> Int {
  return r.keys.len();
}

/// Key of field `i`, in wire order.
/// Params: r - the parsed record; i - zero-based field index.
/// Returns: the key text; "" when i is negative or past the last field.
/// Error case: none. Complexity: O(1).
pub fn whois_key(r: &WhoisRecord, i: Int) -> Str {
  if i < 0 || i >= r.keys.len() {
    return "";
  }
  let v: Str = r.keys[i];
  return v;
}

/// Value of field `i` (the text after the first colon, trimmed).
/// Params: r - the parsed record; i - zero-based field index.
/// Returns: the value text ("" for an empty value); "" when i is out of
/// range. Error case: none. Complexity: O(1).
pub fn whois_value(r: &WhoisRecord, i: Int) -> Str {
  if i < 0 || i >= r.values.len() {
    return "";
  }
  let v: Str = r.values[i];
  return v;
}

/// Number of continuation lines attached to field `i`.
/// Params: r - the parsed record; i - zero-based field index.
/// Returns: the count; 0 when i is negative or past the last field.
/// Error case: none. Complexity: O(1).
pub fn whois_continuation_count(r: &WhoisRecord, i: Int) -> Int {
  if i < 0 || i >= r.continuation_counts.len() {
    return 0;
  }
  let v: Int = r.continuation_counts[i];
  return v;
}

/// Continuation line `j` of field `i`, in wire order.
/// Params: r - the parsed record; i - zero-based field index; j - zero-based
/// continuation index within that field.
/// Returns: the continuation text (trimmed); "" when i or j is out of range.
/// Error case: none. Complexity: O(i).
pub fn whois_continuation(r: &WhoisRecord, i: Int, j: Int) -> Str {
  if i < 0 || i >= r.continuation_counts.len() {
    return "";
  }
  let c: Int = r.continuation_counts[i];
  if j < 0 || j >= c {
    return "";
  }
  var base = 0;
  var k = 0;
  while k < i {
    let ck: Int = r.continuation_counts[k];
    base = base + ck;
    k = k + 1;
  }
  let idx = base + j;
  if idx < 0 || idx >= r.continuations.len() {
    return "";
  }
  let v: Str = r.continuations[idx];
  return v;
}

/// Number of comments (lines starting with "%" or "#").
/// Params: r - the parsed record. Returns: comments.len().
/// Error case: none. Complexity: O(1).
pub fn whois_comment_count(r: &WhoisRecord) -> Int {
  return r.comments.len();
}

/// Comment line `i`, in wire order.
/// Params: r - the parsed record; i - zero-based comment index.
/// Returns: the comment text with its marker, trimmed of surrounding
/// whitespace; "" when i is negative or past the last comment.
/// Error case: none. Complexity: O(1).
pub fn whois_comment(r: &WhoisRecord, i: Int) -> Str {
  if i < 0 || i >= r.comments.len() {
    return "";
  }
  let v: Str = r.comments[i];
  return v;
}

/// Number of fields whose key equals `key` (byte-exact, case-sensitive).
/// Params: r - the parsed record; key - the key text to count.
/// Returns: the occurrence count (0 when absent).
/// Error case: none. Complexity: O(field count).
pub fn whois_count(r: &WhoisRecord, key: Str) -> Int {
  var n = 0;
  var i = 0;
  while i < r.keys.len() {
    let k: Str = r.keys[i];
    if compare.str_compare(k, key) == 0 {
      n = n + 1;
    }
    i = i + 1;
  }
  return n;
}

/// Value of the final field named `key`.
/// Params: r - the parsed record; key - the key text, matched byte-exactly.
/// Returns: Some(value) for the last occurrence (repeated keys: the final
/// one wins, as registry output supersedes earlier values), None when the
/// key is absent.
/// Error case: none. Complexity: O(field count).
pub fn whois_field(r: &WhoisRecord, key: Str) -> Option[Str] {
  var i = r.keys.len() - 1;
  while i >= 0 {
    let k: Str = r.keys[i];
    if compare.str_compare(k, key) == 0 {
      let v: Str = r.values[i];
      return Some(v);
    }
    i = i - 1;
  }
  return None;
}
