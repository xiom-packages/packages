// XIOM -- xiom.terraform: pure infrastructure-as-code workflow model
// Port task: promote the xiom.terraform placeholder to a real, tested,
// pure-XIOM package: an HCL subset parser, an execution plan graph with
// per-attribute diffs, an apply/destroy state machine with revision IDs, a
// state model (lineage + serial) and a provider registry.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// This module is a pure deterministic value layer: no network, no sockets,
// no FFI, no clock, no randomness, no file access. A configuration string
// plus a state value always yield the same plan and the same state.
//
// Model shape (XIOM v0.62.2): free functions only; Ok/Err are constructed
// only inside the _*_ok/_*_err leaf helpers; structs hold parallel vectors
// (never Vec[StructType]); every Vec element read binds a typed local first;
// no Str is ever compared with `==` (all equality goes through
// string.str_compare); every byte read is widened and masked ((b as Int) &
// 0xFF) before comparison.
//
// Sections in this file:
//   1. constants and data model
//   2. leaf Result constructors
//   3. byte/Str primitives
//   4. HCL parser internals
//   5. HCL public API and config accessors
//   6. value helpers (kind, lists, maps, refs, quoting)
//   7. execution plan (changes, diffs, dependency graph, rendering)
//   8. state machine (resources, transitions, revisions, apply/destroy)
//   9. provider registry (registration, init, config integration)

module xiom.terraform

use xiom.string;
use xiom.convert;

// ---------------------------------------------------------------------------
// 1. Constants and data model
// ---------------------------------------------------------------------------

/// Sentinel: unknown index / out-of-range accessor result.
pub const TF_NOT_FOUND: Int = -1;

/// Plan action: create a resource.
pub const TF_ACTION_CREATE: Int = 1;

/// Plan action: update a resource in place.
pub const TF_ACTION_UPDATE: Int = 2;

/// Plan action: delete a resource.
pub const TF_ACTION_DELETE: Int = 3;

/// Resource status: declared but not yet created.
pub const TF_RES_PENDING: Int = 0;

/// Resource status: created.
pub const TF_RES_CREATED: Int = 1;

/// Resource status: updated after creation.
pub const TF_RES_UPDATED: Int = 2;

/// Resource status: deleted (still present in the state for history).
pub const TF_RES_DELETED: Int = 3;

/// Capacity: maximum block nesting depth.
pub const TF_MAX_DEPTH: Int = 32;

/// Capacity: maximum blocks per document.
pub const TF_MAX_BLOCKS: Int = 256;

/// Capacity: maximum attributes per document.
pub const TF_MAX_ATTRS: Int = 1024;

/// Capacity: maximum resources per state.
pub const TF_MAX_RESOURCES: Int = 256;

/// Capacity: maximum plan changes.
pub const TF_MAX_CHANGES: Int = 256;

/// Capacity: maximum plan dependency edges.
pub const TF_MAX_EDGES: Int = 1024;

/// Capacity: maximum registered providers.
pub const TF_MAX_PROVIDERS: Int = 64;

/// Capacity: maximum input document size in bytes.
pub const TF_MAX_INPUT: Int = 65536;

// Byte constants (widened Int values; reads are masked by _byte).
const _TF_TAB: Int = 9;
const _TF_LF: Int = 10;
const _TF_CR: Int = 13;
const _TF_SPACE: Int = 32;
const _TF_QUOTE: Int = 34;
const _TF_HASH: Int = 35;
const _TF_DOLLAR: Int = 36;
const _TF_LPAREN: Int = 40;
const _TF_STAR: Int = 42;
const _TF_COMMA: Int = 44;
const _TF_MINUS: Int = 45;
const _TF_DOT: Int = 46;
const _TF_SLASH: Int = 47;
const _TF_ZERO: Int = 48;
const _TF_NINE: Int = 57;
const _TF_COLON: Int = 58;
const _TF_EQ: Int = 61;
const _TF_A: Int = 65;
const _TF_Z: Int = 90;
const _TF_LBRACKET: Int = 91;
const _TF_BACKSLASH: Int = 92;
const _TF_RBRACKET: Int = 93;
const _TF_UNDERSCORE: Int = 95;
const _TF_a: Int = 97;
const _TF_z: Int = 122;
const _TF_LBRACE: Int = 123;
const _TF_RBRACE: Int = 125;

/// A parsed HCL document. Blocks are in source preorder; attributes are in
/// source order with `attr_owner` = owning block index or -1 for top-level
/// attributes. Fields are implementation detail; use the config_* accessors.
pub type TfConfig = {
  block_type: Vec[Str];
  block_labels: Vec[Str];
  block_line: Vec[Int];
  block_parent: Vec[Int];
  attr_name: Vec[Str];
  attr_owner: Vec[Int];
  attr_kind: Vec[Str];
  attr_value: Vec[Str];
  attr_line: Vec[Int];
}

/// An execution plan: parallel vectors for change nodes (`ch_*`), attribute
/// diffs (`df_*`, each carrying its change index in `df_owner`) and
/// dependency edges (`edge_from` -> `edge_to`, meaning `edge_to` waits for
/// `edge_from`). Build plans with plan_add_change/plan_add_diff/plan_add_dep.
pub type TfPlan = {
  ch_addr: Vec[Str];
  ch_action: Vec[Int];
  ch_reason: Vec[Str];
  df_owner: Vec[Int];
  df_attr: Vec[Str];
  df_before: Vec[Str];
  df_after: Vec[Str];
  edge_from: Vec[Int];
  edge_to: Vec[Int];
}

/// A resource state: lineage identity, monotonically increasing serial and
/// per-resource status/revision vectors (index-aligned). Resources are never
/// removed; a deleted resource keeps its slot and revision for history.
pub type TfState = {
  lineage: Str;
  serial: Int;
  next_rev: Int;
  res_addr: Vec[Str];
  res_status: Vec[Int];
  res_rev: Vec[Int];
}

/// A provider registry: index-aligned name/source/version/init flag vectors
/// plus the initialized count.
pub type TfProviders = {
  p_name: Vec[Str];
  p_source: Vec[Str];
  p_version: Vec[Str];
  p_inited: Vec[Int];
  init_count: Int;
}

/// Internal parser state (not part of the stable API).
pub type TfParser = {
  src: Str;
  pos: Int;
  line: Int;
  last_kind: Str;
  err: Str;
}

// ---------------------------------------------------------------------------
// 2. Leaf Result constructors (Ok/Err only here; see module header)
// ---------------------------------------------------------------------------

fn _cfg_ok(c: TfConfig) -> Result[TfConfig, Str] { return Ok(c); }
fn _cfg_err(m: Str) -> Result[TfConfig, Str] { return Err(m); }
fn _state_ok(s: TfState) -> Result[TfState, Str] { return Ok(s); }
fn _state_err(m: Str) -> Result[TfState, Str] { return Err(m); }
fn _int_ok(v: Int) -> Result[Int, Str] { return Ok(v); }
fn _int_err(m: Str) -> Result[Int, Str] { return Err(m); }
fn _order_ok(v: Vec[Int]) -> Result[Vec[Int], Str] { return Ok(v); }
fn _order_err(m: Str) -> Result[Vec[Int], Str] { return Err(m); }

// ---------------------------------------------------------------------------
// 3. Byte/Str primitives
// ---------------------------------------------------------------------------

// Widen and mask one byte of `s`. byte_at returns UInt8 and comparisons on
// bytes >= 128 miscompile unless widened to Int and masked first.
fn _byte(s: Str, i: Int) -> Int {
  return (string.byte_at(s, i) as Int) & 0xFF;
}

// Byte-exact Str equality (never use `==` on Str values).
fn _streq(a: Str, b: Str) -> Bool {
  return string.str_compare(a, b) == 0;
}

// True when `s` contains a NUL byte (parse rejects such input so no rendered
// value can carry a NUL sentinel).
fn _has_nul(s: Str) -> Bool {
  var i = 0;
  while i < s.len() {
    if _byte(s, i) == 0 {
      return true;
    }
    i = i + 1;
  }
  return false;
}

fn _is_ws(c: Int) -> Bool {
  return c == _TF_SPACE || c == _TF_TAB;
}

// Left-trim ASCII space/tab.
fn _ltrim_ws(s: Str) -> Str {
  var i = 0;
  while i < s.len() && _is_ws(_byte(s, i)) {
    i = i + 1;
  }
  if i == 0 {
    return s;
  }
  return string.str_slice(s, i, s.len());
}

// Right-trim ASCII space/tab.
fn _rtrim_ws(s: Str) -> Str {
  var n = s.len();
  while n > 0 && _is_ws(_byte(s, n - 1)) {
    n = n - 1;
  }
  if n == s.len() {
    return s;
  }
  return string.str_slice(s, 0, n);
}

// Trim ASCII space/tab from both ends.
fn _trim_ws(s: Str) -> Str {
  return _rtrim_ws(_ltrim_ws(s));
}

fn _is_digit(c: Int) -> Bool {
  return c >= _TF_ZERO && c <= _TF_NINE;
}

fn _is_ident_start(c: Int) -> Bool {
  if c >= _TF_a && c <= _TF_z { return true; }
  if c >= _TF_A && c <= _TF_Z { return true; }
  return c == _TF_UNDERSCORE;
}

fn _is_ident_char(c: Int) -> Bool {
  if _is_ident_start(c) { return true; }
  if _is_digit(c) { return true; }
  return c == _TF_MINUS;
}

// True when `s` contains byte `b` (widened comparison).
fn _contains_byte(s: Str, b: Int) -> Bool {
  var i = 0;
  while i < s.len() {
    if _byte(s, i) == b {
      return true;
    }
    i = i + 1;
  }
  return false;
}

// True when `s` contains the two-byte sequence "${".
fn _has_interp(s: Str) -> Bool {
  var i = 0;
  while i + 1 < s.len() {
    if _byte(s, i) == _TF_DOLLAR && _byte(s, i + 1) == _TF_LBRACE {
      return true;
    }
    i = i + 1;
  }
  return false;
}

// Field `idx` of `s` split on byte `sep` (0-based), or "".
fn _slice_field(s: Str, idx: Int, sep: Int) -> Str {
  if idx < 0 {
    return "";
  }
  var cur = 0;
  var start = 0;
  var i = 0;
  while i < s.len() {
    if _byte(s, i) == sep {
      if cur == idx {
        return string.str_slice(s, start, i);
      }
      cur = cur + 1;
      start = i + 1;
    }
    i = i + 1;
  }
  if cur == idx {
    return string.str_slice(s, start, s.len());
  }
  return "";
}

// Number of `sep`-separated fields in `s` (0 fields when s is empty).
fn _count_field(s: Str, sep: Int) -> Int {
  if s.len() == 0 {
    return 0;
  }
  var n = 1;
  var i = 0;
  while i < s.len() {
    if _byte(s, i) == sep {
      n = n + 1;
    }
    i = i + 1;
  }
  return n;
}

// True when `v` contains `s` (byte-exact).
fn _vec_str_has(v: &Vec[Str], s: Str) -> Bool {
  var i = 0;
  while i < v.len() {
    let e: Str = v[i];
    if _streq(e, s) {
      return true;
    }
    i = i + 1;
  }
  return false;
}

// ---------------------------------------------------------------------------
// 4. HCL parser internals
// ---------------------------------------------------------------------------

fn _p_new(src: Str) -> TfParser {
  return TfParser{ src: src; pos: 0; line: 1; last_kind: ""; err: ""; };
}

fn _p_eof(p: &TfParser) -> Bool {
  return p.pos >= p.src.len();
}

// Current byte, or -1 at end of input.
fn _p_cur(p: &TfParser) -> Int {
  if _p_eof(p) {
    return -1;
  }
  return _byte(p.src, p.pos);
}

// Byte at offset `off` from the cursor, or -1 past the end.
fn _p_peek(p: &TfParser, off: Int) -> Int {
  if p.pos + off >= p.src.len() || p.pos + off < 0 {
    return -1;
  }
  return _byte(p.src, p.pos + off);
}

fn _p_adv(p: &mut TfParser) {
  p.pos = p.pos + 1;
}

// Set the sticky error with a line suffix and return false.
fn _p_err(p: &mut TfParser, msg: Str) -> Bool {
  p.err = "hcl: " + msg + " at line " + convert.int_to_string(p.line);
  return false;
}

// True when a sticky parser error is set.
fn _p_failed(p: &TfParser) -> Bool {
  let e: Str = p.err;
  return !_streq(e, "");
}

// Skip ASCII space/tab only.
fn _p_skip_inline(p: &mut TfParser) {
  loop {
    if _p_eof(p) {
      return;
    }
    let c = _p_cur(p);
    if c == _TF_SPACE || c == _TF_TAB {
      _p_adv(p);
      continue;
    }
    return;
  }
}

// Skip to the next LF/CR without consuming it.
fn _p_skip_to_eol(p: &mut TfParser) {
  loop {
    if _p_eof(p) {
      return;
    }
    let c = _p_cur(p);
    if c == _TF_LF || c == _TF_CR {
      return;
    }
    _p_adv(p);
  }
}

// Skip a block comment whose "/*" starts at the cursor. Returns false (and
// sets the error) when it never closes.
fn _p_skip_block_comment(p: &mut TfParser) -> Bool {
  _p_adv(p);
  _p_adv(p);
  loop {
    if _p_eof(p) {
      return _p_err(p, "unterminated block comment");
    }
    let c = _p_cur(p);
    if c == _TF_STAR && _p_peek(p, 1) == _TF_SLASH {
      _p_adv(p);
      _p_adv(p);
      return true;
    }
    if c == _TF_LF {
      _p_adv(p);
      p.line = p.line + 1;
      continue;
    }
    if c == _TF_CR {
      _p_adv(p);
      if _p_cur(p) == _TF_LF {
        _p_adv(p);
      }
      p.line = p.line + 1;
      continue;
    }
    _p_adv(p);
  }
  return false;
}

// Skip whitespace and comments. Returns false on an unterminated block
// comment (every loop branch advances, so this always makes progress).
fn _p_skip_ws(p: &mut TfParser) -> Bool {
  loop {
    if _p_eof(p) {
      return true;
    }
    let c = _p_cur(p);
    if c == _TF_SPACE || c == _TF_TAB {
      _p_adv(p);
      continue;
    }
    if c == _TF_LF {
      _p_adv(p);
      p.line = p.line + 1;
      continue;
    }
    if c == _TF_CR {
      _p_adv(p);
      if _p_cur(p) == _TF_LF {
        _p_adv(p);
      }
      p.line = p.line + 1;
      continue;
    }
    if c == _TF_HASH {
      _p_skip_to_eol(p);
      continue;
    }
    if c == _TF_SLASH && _p_peek(p, 1) == _TF_SLASH {
      _p_adv(p);
      _p_adv(p);
      _p_skip_to_eol(p);
      continue;
    }
    if c == _TF_SLASH && _p_peek(p, 1) == _TF_STAR {
      if !_p_skip_block_comment(p) {
        return false;
      }
      continue;
    }
    return true;
  }
}

// After an attribute value: inline whitespace, a line break, a comment or a
// closing '}' are fine; anything else is trailing garbage. Returns false and
// sets the error otherwise.
fn _p_at_line_end(p: &mut TfParser) -> Bool {
  loop {
    _p_skip_inline(p);
    if _p_eof(p) {
      return true;
    }
    let c = _p_cur(p);
    if c == _TF_LF || c == _TF_CR || c == _TF_RBRACE {
      return true;
    }
    if c == _TF_HASH {
      return true;
    }
    if c == _TF_SLASH && _p_peek(p, 1) == _TF_SLASH {
      return true;
    }
    if c == _TF_SLASH && _p_peek(p, 1) == _TF_STAR {
      if !_p_skip_block_comment(p) {
        return false;
      }
      continue;
    }
    return _p_err(p, "unexpected text after attribute");
  }
  return false;
}

// Parse an identifier (must start here). Sets the error on failure.
fn _p_parse_ident(p: &mut TfParser) -> Str {
  if !_is_ident_start(_p_cur(p)) {
    _p_err(p, "invalid identifier");
    return "";
  }
  let start = p.pos;
  _p_adv(p);
  while !_p_eof(p) && _is_ident_char(_p_cur(p)) {
    _p_adv(p);
  }
  return string.str_slice(p.src, start, p.pos);
}

// Parse a quoted string with the supported escapes (" \" \\ \n \t \r"),
// returning the decoded content without quotes.
fn _p_parse_string(p: &mut TfParser) -> Str {
  _p_adv(p);
  var out = "";
  loop {
    if _p_eof(p) {
      _p_err(p, "unterminated string");
      return "";
    }
    let c = _p_cur(p);
    if c == _TF_QUOTE {
      _p_adv(p);
      return out;
    }
    if c == _TF_LF || c == _TF_CR {
      _p_err(p, "unterminated string");
      return "";
    }
    if c == _TF_BACKSLASH {
      let e = _p_peek(p, 1);
      if e == _TF_QUOTE {
        out = out + "\"";
        _p_adv(p);
        _p_adv(p);
      } elif e == _TF_BACKSLASH {
        out = out + "\\";
        _p_adv(p);
        _p_adv(p);
      } elif e == 110 {
        out = out + "\n";
        _p_adv(p);
        _p_adv(p);
      } elif e == 116 {
        out = out + "\t";
        _p_adv(p);
        _p_adv(p);
      } elif e == 114 {
        out = out + "\r";
        _p_adv(p);
        _p_adv(p);
      } else {
        _p_err(p, "invalid escape sequence");
        return "";
      }
      continue;
    }
    out = out + string.str_slice(p.src, p.pos, p.pos + 1);
    _p_adv(p);
  }
  return "";
}

// Skip a raw quoted string while scanning a group (no decoding, but escape
// sequences are honored so an escaped quote does not close it).
fn _p_skip_string_raw(p: &mut TfParser) -> Bool {
  _p_adv(p);
  loop {
    if _p_eof(p) {
      return _p_err(p, "unterminated string");
    }
    let c = _p_cur(p);
    if c == _TF_QUOTE {
      _p_adv(p);
      return true;
    }
    if c == _TF_LF || c == _TF_CR {
      return _p_err(p, "unterminated string");
    }
    if c == _TF_BACKSLASH {
      _p_adv(p);
      if _p_eof(p) {
        return _p_err(p, "unterminated string");
      }
      _p_adv(p);
      continue;
    }
    _p_adv(p);
  }
  return false;
}

// Scan a bracketed group starting at '[' or '{' and return its inner text
// (without the outer brackets). An explicit stack validates bracket pairing
// and quoted strings; the scan consumes at least one byte per iteration.
fn _p_scan_group(p: &mut TfParser, what: Str) -> Str {
  var stack = Vec[Int].new();
  stack.push(_p_cur(p));
  _p_adv(p);
  let start = p.pos;
  var sp = 1;
  loop {
    if _p_eof(p) {
      _p_err(p, "unterminated " + what);
      return "";
    }
    let c = _p_cur(p);
    if c == _TF_QUOTE {
      if !_p_skip_string_raw(p) {
        return "";
      }
      continue;
    }
    if c == _TF_LBRACKET || c == _TF_LBRACE {
      stack.push(c);
      sp = sp + 1;
      _p_adv(p);
      continue;
    }
    if c == _TF_RBRACKET || c == _TF_RBRACE {
      let top: Int = stack[sp - 1];
      if c == _TF_RBRACKET && top != _TF_LBRACKET {
        _p_err(p, "mismatched brackets in " + what);
        return "";
      }
      if c == _TF_RBRACE && top != _TF_LBRACE {
        _p_err(p, "mismatched brackets in " + what);
        return "";
      }
      sp = sp - 1;
      if sp == 0 {
        let end = p.pos;
        _p_adv(p);
        return string.str_slice(p.src, start, end);
      }
      _p_adv(p);
      continue;
    }
    if c == _TF_LF {
      _p_adv(p);
      p.line = p.line + 1;
      continue;
    }
    if c == _TF_CR {
      _p_adv(p);
      if _p_cur(p) == _TF_LF {
        _p_adv(p);
      }
      p.line = p.line + 1;
      continue;
    }
    _p_adv(p);
  }
  return "";
}

// Parse a number literal: optional '-', digits, optional '.' digits.
fn _p_parse_number(p: &mut TfParser) -> Str {
  let start = p.pos;
  if _p_cur(p) == _TF_MINUS {
    _p_adv(p);
  }
  var digits = 0;
  while !_p_eof(p) && _is_digit(_p_cur(p)) {
    _p_adv(p);
    digits = digits + 1;
  }
  if digits == 0 {
    _p_err(p, "invalid number");
    return "";
  }
  if _p_cur(p) == _TF_DOT {
    _p_adv(p);
    var frac = 0;
    while !_p_eof(p) && _is_digit(_p_cur(p)) {
      _p_adv(p);
      frac = frac + 1;
    }
    if frac == 0 {
      _p_err(p, "invalid number");
      return "";
    }
  }
  if _is_ident_start(_p_cur(p)) {
    _p_err(p, "invalid number");
    return "";
  }
  return string.str_slice(p.src, start, p.pos);
}

// Parse a value after an attribute '='. Sets p.last_kind to the value kind
// ("str", "interp", "num", "bool", "null", "list", "map", "ref").
fn _p_parse_value(p: &mut TfParser) -> Str {
  p.last_kind = "";
  if _p_eof(p) {
    _p_err(p, "unsupported value expression");
    return "";
  }
  let c = _p_cur(p);
  if c == _TF_QUOTE {
    let raw = _p_parse_string(p);
    if _p_failed(p) {
      return "";
    }
    if _has_interp(raw) {
      p.last_kind = "interp";
    } else {
      p.last_kind = "str";
    }
    return raw;
  }
  if c == _TF_LBRACKET {
    let inner = _p_scan_group(p, "list");
    if _p_failed(p) {
      return "";
    }
    p.last_kind = "list";
    return _trim_ws(inner);
  }
  if c == _TF_LBRACE {
    let inner = _p_scan_group(p, "map");
    if _p_failed(p) {
      return "";
    }
    p.last_kind = "map";
    return _trim_ws(inner);
  }
  if c == _TF_MINUS || _is_digit(c) {
    let num = _p_parse_number(p);
    if _p_failed(p) {
      return "";
    }
    p.last_kind = "num";
    return num;
  }
  if _is_ident_start(c) {
    return _p_parse_ref(p);
  }
  _p_err(p, "unsupported value expression");
  return "";
}

// Parse a reference expression (dotted path with optional [..] indexes) or a
// bare keyword (true/false/null). Function calls are rejected.
fn _p_parse_ref(p: &mut TfParser) -> Str {
  let first = _p_parse_ident(p);
  if _p_failed(p) {
    return "";
  }
  if _p_cur(p) == _TF_LPAREN {
    _p_err(p, "unsupported value expression");
    return "";
  }
  if _p_cur(p) != _TF_DOT && _p_cur(p) != _TF_LBRACKET {
    if _streq(first, "true") || _streq(first, "false") {
      p.last_kind = "bool";
      return first;
    }
    if _streq(first, "null") {
      p.last_kind = "null";
      return first;
    }
    p.last_kind = "ref";
    return first;
  }
  var out = first;
  loop {
    if _p_cur(p) == _TF_DOT {
      _p_adv(p);
      if !_is_ident_start(_p_cur(p)) {
        _p_err(p, "invalid identifier");
        return "";
      }
      let seg = _p_parse_ident(p);
      if _p_failed(p) {
        return "";
      }
      out = out + "." + seg;
      continue;
    }
    if _p_cur(p) == _TF_LBRACKET {
      let inner = _p_scan_group(p, "index");
      if _p_failed(p) {
        return "";
      }
      out = out + "[" + _trim_ws(inner) + "]";
      continue;
    }
    break;
  }
  if _p_cur(p) == _TF_LPAREN {
    _p_err(p, "unsupported value expression");
    return "";
  }
  p.last_kind = "ref";
  return out;
}

// True when `owner` already has an attribute named `name`.
fn _has_attr(c: &TfConfig, owner: Int, name: Str) -> Bool {
  var i = 0;
  while i < c.attr_name.len() {
    let o: Int = c.attr_owner[i];
    if o == owner {
      let n: Str = c.attr_name[i];
      if _streq(n, name) {
        return true;
      }
    }
    i = i + 1;
  }
  return false;
}

// Parse one body (attributes and nested blocks) into `cfg`. `parent` is the
// owning block index or -1 at top level. Returns false with p.err set on the
// first error.
fn _p_parse_body(p: &mut TfParser, parent: Int, depth: Int, cfg: &mut TfConfig) -> Bool {
  loop {
    if !_p_skip_ws(p) {
      return false;
    }
    if _p_eof(p) {
      return true;
    }
    let c = _p_cur(p);
    if c == _TF_RBRACE {
      return true;
    }
    if !_is_ident_start(c) {
      _p_err(p, "invalid identifier");
      return false;
    }
    let start_line = p.line;
    let name = _p_parse_ident(p);
    if _p_failed(p) {
      return false;
    }
    _p_skip_inline(p);
    if _p_cur(p) == _TF_EQ {
      _p_adv(p);
      if !_p_skip_ws(p) {
        return false;
      }
      let val = _p_parse_value(p);
      if _p_failed(p) {
        return false;
      }
      let kind: Str = p.last_kind;
      if _p_attr_count(cfg) >= TF_MAX_ATTRS {
        _p_err(p, "too many attributes");
        return false;
      }
      if _has_attr(cfg, parent, name) {
        _p_err(p, "duplicate attribute " + name);
        return false;
      }
      cfg.attr_name.push(name);
      cfg.attr_owner.push(parent);
      cfg.attr_kind.push(kind);
      cfg.attr_value.push(val);
      cfg.attr_line.push(start_line);
      if !_p_at_line_end(p) {
        return false;
      }
      continue;
    }
    var labels = "";
    loop {
      _p_skip_inline(p);
      if _p_cur(p) != _TF_QUOTE {
        break;
      }
      let lab = _p_parse_string(p);
      if _p_failed(p) {
        return false;
      }
      if _streq(lab, "") || _contains_byte(lab, _TF_SLASH) {
        _p_err(p, "invalid block label");
        return false;
      }
      if !_streq(labels, "") {
        labels = labels + "/";
      }
      labels = labels + lab;
    }
    if _p_cur(p) != _TF_LBRACE {
      _p_err(p, "expected '{' after block header");
      return false;
    }
    if cfg.block_type.len() >= TF_MAX_BLOCKS {
      _p_err(p, "too many blocks");
      return false;
    }
    if depth + 1 > TF_MAX_DEPTH {
      _p_err(p, "block nesting too deep");
      return false;
    }
    cfg.block_type.push(name);
    cfg.block_labels.push(labels);
    cfg.block_line.push(start_line);
    cfg.block_parent.push(parent);
    let bi = cfg.block_type.len() - 1;
    _p_adv(p);
    if !_p_parse_body(p, bi, depth + 1, cfg) {
      return false;
    }
    if _p_cur(p) != _TF_RBRACE {
      _p_err(p, "expected '}' to close block");
      return false;
    }
    _p_adv(p);
  }
  return false;
}

// Len of the attribute name vector (kept as a helper so the parser never
// reads a Vec[Str] length through an intermediate binding).
fn _p_attr_count(c: &TfConfig) -> Int {
  return c.attr_name.len();
}

// ---------------------------------------------------------------------------
// 5. HCL public API and config accessors
// ---------------------------------------------------------------------------

// Empty config value (used by hcl_parse only).
fn _cfg_empty() -> TfConfig {
  return TfConfig{
    block_type: Vec[Str].new();
    block_labels: Vec[Str].new();
    block_line: Vec[Int].new();
    block_parent: Vec[Int].new();
    attr_name: Vec[Str].new();
    attr_owner: Vec[Int].new();
    attr_kind: Vec[Str].new();
    attr_value: Vec[Str].new();
    attr_line: Vec[Int].new();
  };
}

/// Parse one HCL-subset document (see SPEC.md for the grammar and the full
/// error catalog). Returns Ok(TfConfig) for a valid document (including an
/// empty one) and Err("hcl: ... at line <n>") on the first error. Comments
/// (#, //, /* */), blocks with labels and nesting, attributes, strings with
/// escapes, numbers (kept as text), booleans, null, lists, maps, references
/// and "${...}" interpolation tokens are supported.
pub fn hcl_parse(text: Str) -> Result[TfConfig, Str] {
  if _has_nul(text) {
    return _cfg_err("hcl: NUL byte in input");
  }
  if text.len() > TF_MAX_INPUT {
    return _cfg_err("hcl: input too large");
  }
  var cfg = _cfg_empty();
  var p = _p_new(text);
  if !_p_parse_body(&mut p, -1, 0, &mut cfg) {
    return _cfg_err(p.err);
  }
  if !_p_eof(&p) {
    return _cfg_err("hcl: unexpected '}' at line " + convert.int_to_string(p.line));
  }
  return _cfg_ok(cfg);
}

/// Number of blocks in `c`.
pub fn config_block_count(c: &TfConfig) -> Int {
  return c.block_type.len();
}

/// Type of block `i` ("" when out of range).
pub fn config_block_type(c: &TfConfig, i: Int) -> Str {
  if i < 0 || i >= c.block_type.len() {
    return "";
  }
  let t: Str = c.block_type[i];
  return t;
}

/// Labels of block `i` joined with "/" ("" when out of range or no labels).
pub fn config_block_labels(c: &TfConfig, i: Int) -> Str {
  if i < 0 || i >= c.block_labels.len() {
    return "";
  }
  let l: Str = c.block_labels[i];
  return l;
}

/// Number of labels of block `i` (0 when out of range).
pub fn config_block_label_count(c: &TfConfig, i: Int) -> Int {
  let labs = config_block_labels(c, i);
  return _count_field(labs, _TF_SLASH);
}

/// Label `li` of block `i` ("" when out of range).
pub fn config_block_label(c: &TfConfig, i: Int, li: Int) -> Str {
  let labs = config_block_labels(c, i);
  return _slice_field(labs, li, _TF_SLASH);
}

/// Labels of block `i` as a fresh vector (empty when out of range).
pub fn config_block_label_list(c: &TfConfig, i: Int) -> Vec[Str] {
  var out = Vec[Str].new();
  let labs = config_block_labels(c, i);
  if _streq(labs, "") {
    return out;
  }
  var li = 0;
  let n = _count_field(labs, _TF_SLASH);
  while li < n {
    out.push(_slice_field(labs, li, _TF_SLASH));
    li = li + 1;
  }
  return out;
}

/// Source line of block `i` (1-based; 0 when out of range).
pub fn config_block_line(c: &TfConfig, i: Int) -> Int {
  if i < 0 || i >= c.block_line.len() {
    return 0;
  }
  let v: Int = c.block_line[i];
  return v;
}

/// Parent block index of block `i` (-1 at top level or out of range).
pub fn config_block_parent(c: &TfConfig, i: Int) -> Int {
  if i < 0 || i >= c.block_parent.len() {
    return -1;
  }
  let v: Int = c.block_parent[i];
  return v;
}

/// First block of type `btype` whose first label equals `label` (label ""
/// matches any block of that type), or -1.
pub fn config_block_index(c: &TfConfig, btype: Str, label: Str) -> Int {
  var i = 0;
  while i < c.block_type.len() {
    let t: Str = c.block_type[i];
    if _streq(t, btype) {
      if _streq(label, "") {
        return i;
      }
      let labs: Str = c.block_labels[i];
      let first = _slice_field(labs, 0, _TF_SLASH);
      if _streq(first, label) {
        return i;
      }
    }
    i = i + 1;
  }
  return -1;
}

/// Index of the n-th (0-based) block of type `btype`, or -1.
pub fn config_nth_block(c: &TfConfig, btype: Str, n: Int) -> Int {
  if n < 0 {
    return -1;
  }
  var seen = 0;
  var i = 0;
  while i < c.block_type.len() {
    let t: Str = c.block_type[i];
    if _streq(t, btype) {
      if seen == n {
        return i;
      }
      seen = seen + 1;
    }
    i = i + 1;
  }
  return -1;
}

/// Number of attributes in `c`.
pub fn config_attr_count(c: &TfConfig) -> Int {
  return c.attr_name.len();
}

/// Name of attribute `i` ("" when out of range).
pub fn config_attr_name(c: &TfConfig, i: Int) -> Str {
  if i < 0 || i >= c.attr_name.len() {
    return "";
  }
  let v: Str = c.attr_name[i];
  return v;
}

/// Kind of attribute `i` ("" when out of range).
pub fn config_attr_kind(c: &TfConfig, i: Int) -> Str {
  if i < 0 || i >= c.attr_kind.len() {
    return "";
  }
  let v: Str = c.attr_kind[i];
  return v;
}

/// Normalized value text of attribute `i` ("" when out of range).
pub fn config_attr_value(c: &TfConfig, i: Int) -> Str {
  if i < 0 || i >= c.attr_value.len() {
    return "";
  }
  let v: Str = c.attr_value[i];
  return v;
}

/// Source line of attribute `i` (1-based; 0 when out of range).
pub fn config_attr_line(c: &TfConfig, i: Int) -> Int {
  if i < 0 || i >= c.attr_line.len() {
    return 0;
  }
  let v: Int = c.attr_line[i];
  return v;
}

/// Owning block index of attribute `i` (-1 at top level or out of range).
pub fn config_attr_owner(c: &TfConfig, i: Int) -> Int {
  if i < 0 || i >= c.attr_owner.len() {
    return -1;
  }
  let v: Int = c.attr_owner[i];
  return v;
}

/// Index of the first attribute of `owner` named `name`, or -1.
pub fn config_attr_index(c: &TfConfig, owner: Int, name: Str) -> Int {
  var i = 0;
  while i < c.attr_name.len() {
    let o: Int = c.attr_owner[i];
    if o == owner {
      let n: Str = c.attr_name[i];
      if _streq(n, name) {
        return i;
      }
    }
    i = i + 1;
  }
  return -1;
}

/// Value of the attribute of `owner` named `name`; None when absent.
pub fn config_attr_get(c: &TfConfig, owner: Int, name: Str) -> Option[Str] {
  let i = config_attr_index(c, owner, name);
  if i < 0 {
    return None;
  }
  let v: Str = c.attr_value[i];
  return Some(v);
}

/// Kind of the attribute of `owner` named `name`; None when absent.
pub fn config_attr_get_kind(c: &TfConfig, owner: Int, name: Str) -> Option[Str] {
  let i = config_attr_index(c, owner, name);
  if i < 0 {
    return None;
  }
  let v: Str = c.attr_kind[i];
  return Some(v);
}

/// Number of attributes owned by block `bi` (-1 means top level).
pub fn config_block_attr_count(c: &TfConfig, bi: Int) -> Int {
  var n = 0;
  var i = 0;
  while i < c.attr_owner.len() {
    let o: Int = c.attr_owner[i];
    if o == bi {
      n = n + 1;
    }
    i = i + 1;
  }
  return n;
}

// Attribute slot of the j-th attribute owned by `bi`, or -1.
fn _block_attr_slot(c: &TfConfig, bi: Int, j: Int) -> Int {
  if j < 0 {
    return -1;
  }
  var seen = 0;
  var i = 0;
  while i < c.attr_owner.len() {
    let o: Int = c.attr_owner[i];
    if o == bi {
      if seen == j {
        return i;
      }
      seen = seen + 1;
    }
    i = i + 1;
  }
  return -1;
}

/// Name of the j-th attribute owned by block `bi` ("" out of range).
pub fn config_block_attr_name(c: &TfConfig, bi: Int, j: Int) -> Str {
  return config_attr_name(c, _block_attr_slot(c, bi, j));
}

/// Kind of the j-th attribute owned by block `bi` ("" out of range).
pub fn config_block_attr_kind(c: &TfConfig, bi: Int, j: Int) -> Str {
  return config_attr_kind(c, _block_attr_slot(c, bi, j));
}

/// Value of the j-th attribute owned by block `bi` ("" out of range).
pub fn config_block_attr_value(c: &TfConfig, bi: Int, j: Int) -> Str {
  return config_attr_value(c, _block_attr_slot(c, bi, j));
}

/// Number of `resource` blocks.
pub fn config_resource_count(c: &TfConfig) -> Int {
  var n = 0;
  var i = 0;
  while i < c.block_type.len() {
    let t: Str = c.block_type[i];
    if _streq(t, "resource") {
      n = n + 1;
    }
    i = i + 1;
  }
  return n;
}

/// Address (`type.name`) of the n-th (0-based) resource block, or "".
pub fn config_resource_address(c: &TfConfig, n: Int) -> Str {
  let bi = config_nth_block(c, "resource", n);
  if bi < 0 {
    return "";
  }
  let labs: Str = c.block_labels[bi];
  let first = _slice_field(labs, 0, _TF_SLASH);
  let second = _slice_field(labs, 1, _TF_SLASH);
  if _streq(second, "") {
    return first;
  }
  return first + "." + second;
}

// Escape a Str for a double-quoted HCL string (the supported escapes).
fn _esc(s: Str) -> Str {
  var out = "";
  var i = 0;
  while i < s.len() {
    let c = _byte(s, i);
    if c == _TF_QUOTE {
      out = out + "\\\"";
    } elif c == _TF_BACKSLASH {
      out = out + "\\\\";
    } elif c == _TF_LF {
      out = out + "\\n";
    } elif c == _TF_TAB {
      out = out + "\\t";
    } elif c == _TF_CR {
      out = out + "\\r";
    } else {
      out = out + string.str_slice(s, i, i + 1);
    }
    i = i + 1;
  }
  return out;
}

/// Quote and escape `s` as an HCL string literal.
pub fn hcl_quote(s: Str) -> Str {
  return "\"" + _esc(s) + "\"";
}

// Render one attribute value by kind.
fn _render_value(kind: Str, value: Str) -> Str {
  if _streq(kind, "str") || _streq(kind, "interp") {
    return hcl_quote(value);
  }
  if _streq(kind, "list") {
    if _streq(value, "") {
      return "[]";
    }
    return "[" + value + "]";
  }
  if _streq(kind, "map") {
    if _streq(value, "") {
      return "{}";
    }
    return "{" + value + "}";
  }
  return value;
}

// Render an indent of `n` levels (two spaces per level).
fn _indent_of(n: Int) -> Str {
  var out = "";
  var i = 0;
  while i < n {
    out = out + "  ";
    i = i + 1;
  }
  return out;
}

// Render block `bi` and its descendants, appending to `out`.
fn _render_block(c: &TfConfig, bi: Int, indent: Int, out: Str) -> Str {
  var res = out;
  let ind = _indent_of(indent);
  let btype: Str = c.block_type[bi];
  res = res + ind + btype;
  let li = 0;
  let lc = config_block_label_count(c, bi);
  while li < lc {
    res = res + " " + hcl_quote(config_block_label(c, bi, li));
    li = li + 1;
  }
  res = res + " {\n";
  let inner = _indent_of(indent + 1);
  var i = 0;
  while i < c.attr_owner.len() {
    let o: Int = c.attr_owner[i];
    if o == bi {
      let an: Str = c.attr_name[i];
      let ak: Str = c.attr_kind[i];
      let av: Str = c.attr_value[i];
      res = res + inner + an + " = " + _render_value(ak, av) + "\n";
    }
    i = i + 1;
  }
  var b = 0;
  while b < c.block_type.len() {
    let par: Int = c.block_parent[b];
    if par == bi {
      res = _render_block(c, b, indent + 1, res);
    }
    b = b + 1;
  }
  res = res + ind + "}\n";
  return res;
}

/// Render `c` as canonical HCL text: top-level attributes first, then
/// top-level blocks in order (attributes before nested blocks inside each).
/// The relative order of an attribute and a block in the same body is not
/// preserved; parse -> render -> parse preserves the block tree, kinds and
/// values.
pub fn config_render(c: &TfConfig) -> Str {
  var out = "";
  var i = 0;
  while i < c.attr_owner.len() {
    let o: Int = c.attr_owner[i];
    if o < 0 {
      let an: Str = c.attr_name[i];
      let ak: Str = c.attr_kind[i];
      let av: Str = c.attr_value[i];
      out = out + an + " = " + _render_value(ak, av) + "\n";
    }
    i = i + 1;
  }
  var b = 0;
  while b < c.block_type.len() {
    let par: Int = c.block_parent[b];
    if par < 0 {
      out = _render_block(c, b, 0, out);
    }
    b = b + 1;
  }
  return out;
}

// ---------------------------------------------------------------------------
// 6. Value helpers (kind, lists, maps, refs, quoting)
// ---------------------------------------------------------------------------

// Strip one pair of outer brackets after trimming, but only when the first
// open bracket actually closes at the very last byte (so inner text such as
// "[1, 2], [3]" is left intact).
fn _strip_outer(s: Str, open: Int, close: Int) -> Str {
  let t = _trim_ws(s);
  let n = t.len();
  if n < 2 || _byte(t, 0) != open {
    return t;
  }
  var depth = 0;
  var i = 0;
  while i < n {
    let c = _byte(t, i);
    if c == open {
      depth = depth + 1;
    } elif c == close {
      depth = depth - 1;
      if depth == 0 {
        if i == n - 1 {
          return _trim_ws(string.str_slice(t, 1, n - 1));
        }
        return t;
      }
    }
    i = i + 1;
  }
  return t;
}

// Split `v` on top-level commas: commas inside quotes, [] or {} do not
// split. Elements are trimmed; an empty inner text yields an empty vector.
fn _split_top_commas(v: Str) -> Vec[Str] {
  var out = Vec[Str].new();
  let s = _trim_ws(v);
  if s.len() == 0 {
    return out;
  }
  var i = 0;
  var start = 0;
  var sq = 0;
  var cu = 0;
  var instr = false;
  var esc = false;
  while i < s.len() {
    let c = _byte(s, i);
    if instr {
      if esc {
        esc = false;
      } elif c == _TF_BACKSLASH {
        esc = true;
      } elif c == _TF_QUOTE {
        instr = false;
      }
      i = i + 1;
      continue;
    }
    if c == _TF_QUOTE {
      instr = true;
      i = i + 1;
      continue;
    }
    if c == _TF_LBRACKET {
      sq = sq + 1;
    } elif c == _TF_RBRACKET {
      if sq > 0 {
        sq = sq - 1;
      }
    } elif c == _TF_LBRACE {
      cu = cu + 1;
    } elif c == _TF_RBRACE {
      if cu > 0 {
        cu = cu - 1;
      }
    } elif c == _TF_COMMA && sq == 0 && cu == 0 {
      out.push(_trim_ws(string.str_slice(s, start, i)));
      start = i + 1;
    }
    i = i + 1;
  }
  let last = _trim_ws(string.str_slice(s, start, s.len()));
  if last.len() > 0 {
    out.push(last);
  }
  return out;
}

// True for a syntactically complete number text.
fn _num_text_ok(s: Str) -> Bool {
  let n = s.len();
  if n == 0 {
    return false;
  }
  var i = 0;
  if _byte(s, 0) == _TF_MINUS {
    i = 1;
  }
  var digits = 0;
  while i < n && _is_digit(_byte(s, i)) {
    i = i + 1;
    digits = digits + 1;
  }
  if digits == 0 {
    return false;
  }
  if i < n && _byte(s, i) == _TF_DOT {
    i = i + 1;
    var frac = 0;
    while i < n && _is_digit(_byte(s, i)) {
      i = i + 1;
      frac = frac + 1;
    }
    if frac == 0 {
      return false;
    }
  }
  return i == n;
}

// True for a syntactically complete reference text.
fn _ref_text_ok(s: Str) -> Bool {
  let n = s.len();
  if n == 0 {
    return false;
  }
  if !_is_ident_start(_byte(s, 0)) {
    return false;
  }
  var i = 1;
  while i < n {
    let c = _byte(s, i);
    if _is_ident_char(c) {
      i = i + 1;
      continue;
    }
    if c == _TF_DOT {
      i = i + 1;
      if i >= n || !_is_ident_start(_byte(s, i)) {
        return false;
      }
      i = i + 1;
      continue;
    }
    if c == _TF_LBRACKET {
      var depth = 1;
      i = i + 1;
      while i < n && depth > 0 {
        let c2 = _byte(s, i);
        if c2 == _TF_LBRACKET {
          depth = depth + 1;
        } elif c2 == _TF_RBRACKET {
          depth = depth - 1;
        }
        i = i + 1;
      }
      if depth != 0 {
        return false;
      }
      continue;
    }
    return false;
  }
  return true;
}

/// Classify a raw value text: "str", "interp", "num", "bool", "null",
/// "list", "map", "ref" or "invalid". Outer brackets of lists/maps may be
/// present; the value is trimmed first.
pub fn hcl_kind(v: Str) -> Str {
  let s = _trim_ws(v);
  if s.len() == 0 {
    return "str";
  }
  let c = _byte(s, 0);
  if c == _TF_QUOTE {
    if s.len() < 2 {
      return "invalid";
    }
    if _byte(s, s.len() - 1) != _TF_QUOTE {
      return "invalid";
    }
    if _has_interp(s) {
      return "interp";
    }
    return "str";
  }
  if c == _TF_LBRACKET {
    return "list";
  }
  if c == _TF_LBRACE {
    return "map";
  }
  if _streq(s, "true") || _streq(s, "false") {
    return "bool";
  }
  if _streq(s, "null") {
    return "null";
  }
  if c == _TF_MINUS || _is_digit(c) {
    if _num_text_ok(s) {
      return "num";
    }
    return "invalid";
  }
  if _ref_text_ok(s) {
    return "ref";
  }
  return "invalid";
}

/// True when `v` contains a "${...}" interpolation token.
pub fn hcl_is_interp(v: Str) -> Bool {
  return _has_interp(v);
}

/// First segment of a reference: up to the first "." or "[".
pub fn hcl_ref_root(ref: Str) -> Str {
  var i = 0;
  while i < ref.len() {
    let c = _byte(ref, i);
    if c == _TF_DOT || c == _TF_LBRACKET {
      return string.str_slice(ref, 0, i);
    }
    i = i + 1;
  }
  return ref;
}

/// Split list text (with or without outer brackets) into trimmed element
/// texts on top-level commas; an empty list yields an empty vector.
pub fn hcl_split_list(v: Str) -> Vec[Str] {
  let inner = _strip_outer(v, _TF_LBRACKET, _TF_RBRACKET);
  return _split_top_commas(inner);
}

/// Number of elements in list text `v`.
pub fn hcl_list_count(v: Str) -> Int {
  let items = hcl_split_list(v);
  return items.len();
}

/// Element `i` of list text `v` ("" out of range).
pub fn hcl_list_item(v: Str, i: Int) -> Str {
  let items = hcl_split_list(v);
  if i < 0 || i >= items.len() {
    return "";
  }
  let e: Str = items[i];
  return e;
}

// Index of the top-level '=' or ':' in one map entry, or -1.
fn _map_entry_sep(entry: Str) -> Int {
  var i = 0;
  var sq = 0;
  var cu = 0;
  var instr = false;
  var esc = false;
  while i < entry.len() {
    let c = _byte(entry, i);
    if instr {
      if esc {
        esc = false;
      } elif c == _TF_BACKSLASH {
        esc = true;
      } elif c == _TF_QUOTE {
        instr = false;
      }
      i = i + 1;
      continue;
    }
    if c == _TF_QUOTE {
      instr = true;
      i = i + 1;
      continue;
    }
    if c == _TF_LBRACKET {
      sq = sq + 1;
    } elif c == _TF_RBRACKET {
      if sq > 0 {
        sq = sq - 1;
      }
    } elif c == _TF_LBRACE {
      cu = cu + 1;
    } elif c == _TF_RBRACE {
      if cu > 0 {
        cu = cu - 1;
      }
    } elif (c == _TF_EQ || c == _TF_COLON) && sq == 0 && cu == 0 {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Strip one pair of outer double quotes when present.
fn _unquote_loose(s: Str) -> Str {
  let t = _trim_ws(s);
  let n = t.len();
  if n >= 2 && _byte(t, 0) == _TF_QUOTE && _byte(t, n - 1) == _TF_QUOTE {
    return string.str_slice(t, 1, n - 1);
  }
  return t;
}

// Map entries of `v` (outer braces optional).
fn _map_entries(v: Str) -> Vec[Str] {
  let inner = _strip_outer(v, _TF_LBRACE, _TF_RBRACE);
  return _split_top_commas(inner);
}

/// Number of entries in map text `v`.
pub fn hcl_map_count(v: Str) -> Int {
  let entries = _map_entries(v);
  return entries.len();
}

/// Key of map entry `i` ("" out of range; quotes stripped).
pub fn hcl_map_key(v: Str, i: Int) -> Str {
  let entries = _map_entries(v);
  if i < 0 || i >= entries.len() {
    return "";
  }
  let e: Str = entries[i];
  let sep = _map_entry_sep(e);
  if sep < 0 {
    return "";
  }
  return _unquote_loose(string.str_slice(e, 0, sep));
}

/// Value of map entry `i` ("" out of range; outer quotes stripped).
pub fn hcl_map_value(v: Str, i: Int) -> Str {
  let entries = _map_entries(v);
  if i < 0 || i >= entries.len() {
    return "";
  }
  let e: Str = entries[i];
  let sep = _map_entry_sep(e);
  if sep < 0 {
    return "";
  }
  return _unquote_loose(string.str_slice(e, sep + 1, e.len()));
}

/// Value of `key` in map text `v`; None when the key is absent.
pub fn hcl_map_get(v: Str, key: Str) -> Option[Str] {
  let entries = _map_entries(v);
  var i = 0;
  while i < entries.len() {
    let e: Str = entries[i];
    let sep = _map_entry_sep(e);
    if sep >= 0 {
      let k = _unquote_loose(string.str_slice(e, 0, sep));
      if _streq(k, key) {
        let val = _unquote_loose(string.str_slice(e, sep + 1, e.len()));
        return Some(val);
      }
    }
    i = i + 1;
  }
  return None;
}

// ---------------------------------------------------------------------------
// 7. Execution plan (changes, diffs, dependency graph, rendering)
// ---------------------------------------------------------------------------

/// An empty plan.
pub fn plan_new() -> TfPlan {
  return TfPlan{
    ch_addr: Vec[Str].new();
    ch_action: Vec[Int].new();
    ch_reason: Vec[Str].new();
    df_owner: Vec[Int].new();
    df_attr: Vec[Str].new();
    df_before: Vec[Str].new();
    df_after: Vec[Str].new();
    edge_from: Vec[Int].new();
    edge_to: Vec[Int].new();
  };
}

// Append one change node without validation.
fn _plan_push_change(p: &mut TfPlan, addr: Str, action: Int, reason: Str) {
  p.ch_addr.push(addr);
  p.ch_action.push(action);
  p.ch_reason.push(reason);
}

// True when any change already uses `addr`.
fn _plan_addr_used(p: &TfPlan, addr: Str) -> Bool {
  var i = 0;
  while i < p.ch_addr.len() {
    let a: Str = p.ch_addr[i];
    if _streq(a, addr) {
      return true;
    }
    i = i + 1;
  }
  return false;
}

/// Add one change node (action is TF_ACTION_CREATE/UPDATE/DELETE) and return
/// its index. Errors: empty address, unknown action, duplicate address,
/// change limit exceeded.
pub fn plan_add_change(p: &mut TfPlan, addr: Str, action: Int, reason: Str) -> Result[Int, Str] {
  if _streq(addr, "") {
    return _int_err("plan: resource address must not be empty");
  }
  if action != TF_ACTION_CREATE && action != TF_ACTION_UPDATE && action != TF_ACTION_DELETE {
    return _int_err("plan: unknown action");
  }
  if _plan_addr_used(p, addr) {
    return _int_err("plan: duplicate resource address: " + addr);
  }
  if p.ch_addr.len() >= TF_MAX_CHANGES {
    return _int_err("plan: change limit exceeded");
  }
  let idx = p.ch_addr.len();
  _plan_push_change(p, addr, action, reason);
  return _int_ok(idx);
}

/// Number of change nodes.
pub fn plan_count(p: &TfPlan) -> Int {
  return p.ch_addr.len();
}

/// Address of change `i` ("" out of range).
pub fn plan_addr(p: &TfPlan, i: Int) -> Str {
  if i < 0 || i >= p.ch_addr.len() {
    return "";
  }
  let a: Str = p.ch_addr[i];
  return a;
}

/// Action code of change `i` (0 out of range).
pub fn plan_action(p: &TfPlan, i: Int) -> Int {
  if i < 0 || i >= p.ch_action.len() {
    return 0;
  }
  let a: Int = p.ch_action[i];
  return a;
}

/// Human name of an action code: "create", "update", "delete" or "unknown".
pub fn plan_action_name(a: Int) -> Str {
  if a == TF_ACTION_CREATE {
    return "create";
  }
  if a == TF_ACTION_UPDATE {
    return "update";
  }
  if a == TF_ACTION_DELETE {
    return "delete";
  }
  return "unknown";
}

/// Reason text of change `i` ("" out of range).
pub fn plan_reason(p: &TfPlan, i: Int) -> Str {
  if i < 0 || i >= p.ch_reason.len() {
    return "";
  }
  let r: Str = p.ch_reason[i];
  return r;
}

// True when change `ci` already has an attribute diff for `attr`.
fn _plan_diff_used(p: &TfPlan, ci: Int, attr: Str) -> Bool {
  var i = 0;
  while i < p.df_owner.len() {
    let o: Int = p.df_owner[i];
    if o == ci {
      let a: Str = p.df_attr[i];
      if _streq(a, attr) {
        return true;
      }
    }
    i = i + 1;
  }
  return false;
}

/// Add one attribute diff under change `ci` (before/after; "" on the absent
/// side) and return its index. Errors: unknown change, empty attribute,
/// duplicate attribute for that change, diff limit exceeded.
pub fn plan_add_diff(p: &mut TfPlan, ci: Int, attr: Str, before: Str, after: Str) -> Result[Int, Str] {
  if ci < 0 || ci >= p.ch_addr.len() {
    return _int_err("plan: unknown change id");
  }
  if _streq(attr, "") {
    return _int_err("plan: diff attribute must not be empty");
  }
  if _plan_diff_used(p, ci, attr) {
    return _int_err("plan: duplicate diff attribute: " + attr);
  }
  if p.df_owner.len() >= TF_MAX_EDGES {
    return _int_err("plan: diff limit exceeded");
  }
  let idx = p.df_owner.len();
  p.df_owner.push(ci);
  p.df_attr.push(attr);
  p.df_before.push(before);
  p.df_after.push(after);
  return _int_ok(idx);
}

/// Number of attribute diffs in the plan.
pub fn plan_diff_count(p: &TfPlan) -> Int {
  return p.df_owner.len();
}

/// Number of diffs attached to change `ci` (0 out of range).
pub fn plan_change_diff_count(p: &TfPlan, ci: Int) -> Int {
  if ci < 0 || ci >= p.ch_addr.len() {
    return 0;
  }
  var n = 0;
  var i = 0;
  while i < p.df_owner.len() {
    let o: Int = p.df_owner[i];
    if o == ci {
      n = n + 1;
    }
    i = i + 1;
  }
  return n;
}

/// Owning change index of diff `i` (-1 out of range).
pub fn plan_diff_owner(p: &TfPlan, i: Int) -> Int {
  if i < 0 || i >= p.df_owner.len() {
    return -1;
  }
  let o: Int = p.df_owner[i];
  return o;
}

/// Attribute name of diff `i` ("" out of range).
pub fn plan_diff_attr(p: &TfPlan, i: Int) -> Str {
  if i < 0 || i >= p.df_attr.len() {
    return "";
  }
  let v: Str = p.df_attr[i];
  return v;
}

/// Observed value of diff `i` ("" out of range).
pub fn plan_diff_before(p: &TfPlan, i: Int) -> Str {
  if i < 0 || i >= p.df_before.len() {
    return "";
  }
  let v: Str = p.df_before[i];
  return v;
}

/// Planned value of diff `i` ("" out of range).
pub fn plan_diff_after(p: &TfPlan, i: Int) -> Str {
  if i < 0 || i >= p.df_after.len() {
    return "";
  }
  let v: Str = p.df_after[i];
  return v;
}

// True when the edge from -> to exists.
fn _edge_exists(p: &TfPlan, from: Int, to: Int) -> Bool {
  var i = 0;
  while i < p.edge_from.len() {
    let f: Int = p.edge_from[i];
    let t: Int = p.edge_to[i];
    if f == from && t == to {
      return true;
    }
    i = i + 1;
  }
  return false;
}

/// Declare that change `after` depends on change `before` (before applies
/// first). Errors: unknown id, self edge, duplicate edge, edge limit.
pub fn plan_add_dep(p: &mut TfPlan, before: Int, after: Int) -> Result[Int, Str] {
  let n = p.ch_addr.len();
  if before < 0 || before >= n || after < 0 || after >= n {
    return _int_err("plan: unknown dependency id");
  }
  if before == after {
    return _int_err("plan: dependency on self");
  }
  if _edge_exists(p, before, after) {
    return _int_err("plan: duplicate dependency");
  }
  if p.edge_from.len() >= TF_MAX_EDGES {
    return _int_err("plan: dependency limit exceeded");
  }
  p.edge_from.push(before);
  p.edge_to.push(after);
  return _int_ok(p.edge_from.len());
}

// Count of not-yet-applied dependencies of `v` (edges from a change whose
// done flag is 0). Kahn frontier test, recomputed per pass.
fn _waiting_deps(p: &TfPlan, done: &Vec[Int], v: Int) -> Int {
  var k = 0;
  var i = 0;
  while i < p.edge_to.len() {
    let t: Int = p.edge_to[i];
    if t == v {
      let f: Int = p.edge_from[i];
      let d: Int = done[f];
      if d == 0 {
        k = k + 1;
      }
    }
    i = i + 1;
  }
  return k;
}

/// Deterministic topological order of the changes (Kahn's algorithm,
/// smallest ready index first). Returns Err("plan: dependency cycle") when
/// the dependency graph is cyclic.
pub fn plan_order(p: &TfPlan) -> Result[Vec[Int], Str] {
  let n = p.ch_addr.len();
  var out = Vec[Int].new();
  var done = Vec[Int].new();
  var i = 0;
  while i < n {
    done.push(0);
    i = i + 1;
  }
  var emitted = 0;
  while emitted < n {
    var pick = -1;
    i = 0;
    while i < n {
      let d: Int = done[i];
      if d == 0 {
        let wait = _waiting_deps(p, &done, i);
        if wait == 0 {
          pick = i;
          break;
        }
      }
      i = i + 1;
    }
    if pick < 0 {
      return _order_err("plan: dependency cycle");
    }
    done[pick] = 1;
    out.push(pick);
    emitted = emitted + 1;
  }
  return _order_ok(out);
}

/// True when the dependency graph contains a cycle.
pub fn plan_has_cycle(p: &TfPlan) -> Bool {
  match plan_order(p) {
    Ok(_) => { return false; },
    Err(_) => { return true; },
  }
  return false;
}

/// Deterministic summary "<c> to create, <u> to update, <d> to delete".
pub fn plan_summary(p: &TfPlan) -> Str {
  var c = 0;
  var u = 0;
  var d = 0;
  var i = 0;
  while i < p.ch_action.len() {
    let a: Int = p.ch_action[i];
    if a == TF_ACTION_CREATE {
      c = c + 1;
    } elif a == TF_ACTION_UPDATE {
      u = u + 1;
    } elif a == TF_ACTION_DELETE {
      d = d + 1;
    }
    i = i + 1;
  }
  return convert.int_to_string(c) + " to create, " + convert.int_to_string(u) + " to update, " + convert.int_to_string(d) + " to delete";
}

/// Deterministic multi-line rendering: "+ addr" (create), "~ addr" (update),
/// "- addr" (delete), an optional " (reason)" suffix, then two-space
/// indented "attr: before -> after" lines per diff. LF separated with a
/// trailing LF.
pub fn plan_render(p: &TfPlan) -> Str {
  var out = "";
  var i = 0;
  while i < p.ch_addr.len() {
    let a: Str = p.ch_addr[i];
    let act: Int = p.ch_action[i];
    let reason: Str = p.ch_reason[i];
    var sym = "?";
    if act == TF_ACTION_CREATE {
      sym = "+";
    } elif act == TF_ACTION_UPDATE {
      sym = "~";
    } elif act == TF_ACTION_DELETE {
      sym = "-";
    }
    var line = sym + " " + a;
    if !_streq(reason, "") {
      line = line + " (" + reason + ")";
    }
    out = out + line + "\n";
    var j = 0;
    while j < p.df_owner.len() {
      let o: Int = p.df_owner[j];
      if o == i {
        let at: Str = p.df_attr[j];
        let bf: Str = p.df_before[j];
        let af: Str = p.df_after[j];
        out = out + "  " + at + ": " + bf + " -> " + af + "\n";
      }
      j = j + 1;
    }
    i = i + 1;
  }
  return out;
}

// ---------------------------------------------------------------------------
// 8. State machine (resources, transitions, revisions, apply/destroy)
// ---------------------------------------------------------------------------

/// A fresh state with `lineage` and serial 1. Errors on an empty lineage.
pub fn state_new(lineage: Str) -> Result[TfState, Str] {
  if _streq(lineage, "") {
    return _state_err("state: lineage must not be empty");
  }
  return _state_ok(TfState{
    lineage: lineage;
    serial: 1;
    next_rev: 1;
    res_addr: Vec[Str].new();
    res_status: Vec[Int].new();
    res_rev: Vec[Int].new();
  });
}

// Slot of `addr` in the state, or -1.
fn _state_find(s: &TfState, addr: Str) -> Int {
  var i = 0;
  while i < s.res_addr.len() {
    let a: Str = s.res_addr[i];
    if _streq(a, addr) {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

/// Add a pending resource with revision 0 and return its index. Errors:
/// empty address, duplicate address, resource limit.
pub fn state_add_resource(s: &mut TfState, addr: Str) -> Result[Int, Str] {
  if _streq(addr, "") {
    return _int_err("state: resource address must not be empty");
  }
  if _state_find(s, addr) >= 0 {
    return _int_err("state: duplicate resource address: " + addr);
  }
  let cnt = s.res_addr.len();
  if cnt >= TF_MAX_RESOURCES {
    return _int_err("state: resource limit exceeded");
  }
  s.res_addr.push(addr);
  s.res_status.push(TF_RES_PENDING);
  s.res_rev.push(0);
  return _int_ok(cnt);
}

/// Number of resources (including deleted ones).
pub fn state_count(s: &TfState) -> Int {
  return s.res_addr.len();
}

/// Number of resources whose status is not deleted.
pub fn state_live_count(s: &TfState) -> Int {
  var n = 0;
  var i = 0;
  while i < s.res_status.len() {
    let st: Int = s.res_status[i];
    if st != TF_RES_DELETED {
      n = n + 1;
    }
    i = i + 1;
  }
  return n;
}

/// Address of resource `i` ("" out of range).
pub fn state_addr(s: &TfState, i: Int) -> Str {
  if i < 0 || i >= s.res_addr.len() {
    return "";
  }
  let a: Str = s.res_addr[i];
  return a;
}

/// Status of resource `i` (-1 out of range).
pub fn state_status(s: &TfState, i: Int) -> Int {
  if i < 0 || i >= s.res_status.len() {
    return -1;
  }
  let st: Int = s.res_status[i];
  return st;
}

/// Revision of resource `i` (0 when none/out of range).
pub fn state_rev(s: &TfState, i: Int) -> Int {
  if i < 0 || i >= s.res_rev.len() {
    return 0;
  }
  let r: Int = s.res_rev[i];
  return r;
}

/// Current serial.
pub fn state_serial(s: &TfState) -> Int {
  return s.serial;
}

/// Lineage identity.
pub fn state_lineage(s: &TfState) -> Str {
  return s.lineage;
}

/// Slot of `addr` in the state, or TF_NOT_FOUND (-1).
pub fn state_index(s: &TfState, addr: Str) -> Int {
  return _state_find(s, addr);
}

/// True when the state contains `addr` (deleted resources included).
pub fn state_has(s: &TfState, addr: Str) -> Bool {
  return _state_find(s, addr) >= 0;
}

/// Human name of a status code: "pending", "created", "updated", "deleted"
/// or "unknown".
pub fn state_status_name(st: Int) -> Str {
  if st == TF_RES_PENDING {
    return "pending";
  }
  if st == TF_RES_CREATED {
    return "created";
  }
  if st == TF_RES_UPDATED {
    return "updated";
  }
  if st == TF_RES_DELETED {
    return "deleted";
  }
  return "unknown";
}

/// Transition table: exactly six legal pairs (pending->created,
/// pending->deleted, created->updated, created->deleted, updated->updated,
/// updated->deleted).
pub fn state_can_transition(from: Int, to: Int) -> Bool {
  if from == TF_RES_PENDING && to == TF_RES_CREATED { return true; }
  if from == TF_RES_PENDING && to == TF_RES_DELETED { return true; }
  if from == TF_RES_CREATED && to == TF_RES_UPDATED { return true; }
  if from == TF_RES_CREATED && to == TF_RES_DELETED { return true; }
  if from == TF_RES_UPDATED && to == TF_RES_UPDATED { return true; }
  if from == TF_RES_UPDATED && to == TF_RES_DELETED { return true; }
  return false;
}

/// Perform one resource transition: sets the status, assigns the next
/// revision ID to the resource and increments the serial. Returns the new
/// revision. Errors: unknown resource id, already deleted, illegal
/// transition.
pub fn state_transition(s: &mut TfState, i: Int, to: Int) -> Result[Int, Str] {
  if i < 0 || i >= s.res_addr.len() {
    return _int_err("state: unknown resource id");
  }
  let from: Int = s.res_status[i];
  if from == TF_RES_DELETED {
    return _int_err("state: resource already deleted");
  }
  if !state_can_transition(from, to) {
    return _int_err("state: illegal state transition: " + state_status_name(from) + " -> " + state_status_name(to));
  }
  s.res_status[i] = to;
  let r = s.next_rev;
  s.next_rev = r + 1;
  s.serial = s.serial + 1;
  s.res_rev[i] = r;
  return _int_ok(r);
}

// Apply an already-computed order to the state.
fn _state_apply_order(s: &mut TfState, order: &Vec[Int], p: &TfPlan) -> Result[Int, Str] {
  var applied = 0;
  var k = 0;
  while k < order.len() {
    let ci: Int = order[k];
    let addr: Str = p.ch_addr[ci];
    let act: Int = p.ch_action[ci];
    if act == TF_ACTION_CREATE {
      if _state_find(s, addr) >= 0 {
        return _int_err("state: resource already exists: " + addr);
      }
      let a = state_add_resource(s, addr);
      match a {
        Ok(ri) => {
          let tr = state_transition(s, ri, TF_RES_CREATED);
          match tr {
            Ok(_) => {},
            Err(e2) => { return _int_err(e2); },
          }
        },
        Err(e2) => { return _int_err(e2); },
      }
    } elif act == TF_ACTION_UPDATE {
      let ri = _state_find(s, addr);
      if ri < 0 {
        return _int_err("state: has no resource: " + addr);
      }
      let st: Int = s.res_status[ri];
      if st == TF_RES_DELETED {
        return _int_err("state: resource already deleted: " + addr);
      }
      if st == TF_RES_PENDING {
        return _int_err("state: resource not created: " + addr);
      }
      let tr = state_transition(s, ri, TF_RES_UPDATED);
      match tr {
        Ok(_) => {},
        Err(e2) => { return _int_err(e2); },
      }
    } elif act == TF_ACTION_DELETE {
      let ri = _state_find(s, addr);
      if ri < 0 {
        return _int_err("state: has no resource: " + addr);
      }
      let tr = state_transition(s, ri, TF_RES_DELETED);
      match tr {
        Ok(_) => {},
        Err(e2) => { return _int_err(e2); },
      }
    } else {
      return _int_err("state: unknown action");
    }
    applied = applied + 1;
    k = k + 1;
  }
  return _int_ok(applied);
}

/// Apply every change of `p` to `s` in plan order. Returns the number of
/// applied changes, or the first error: "plan: dependency cycle",
/// "state: resource already exists: <addr>", "state: has no resource:
/// <addr>", "state: resource not created: <addr>", "state: resource already
/// deleted: <addr>". On error the state is only partially modified (the
/// changes before the failing one stay applied) -- deterministic.
pub fn state_apply_plan(s: &mut TfState, p: &TfPlan) -> Result[Int, Str] {
  let order = plan_order(p);
  match order {
    Ok(v) => { return _state_apply_order(s, &v, p); },
    Err(e) => { return _int_err(e); },
  }
  return _int_err("state: unreachable");
}

/// Delete plan for every live resource, in state insertion order (reason
/// "destroy"). Deterministic; never fails on a state built through
/// state_add_resource.
pub fn state_destroy_plan(s: &TfState) -> TfPlan {
  var p = plan_new();
  var i = 0;
  while i < s.res_addr.len() {
    let st: Int = s.res_status[i];
    if st != TF_RES_DELETED {
      let addr: Str = s.res_addr[i];
      _plan_push_change(&mut p, addr, TF_ACTION_DELETE, "destroy");
    }
    i = i + 1;
  }
  return p;
}

/// Destroy every live resource; returns the number of destroyed resources.
pub fn state_destroy_all(s: &mut TfState) -> Result[Int, Str] {
  let p = state_destroy_plan(s);
  return state_apply_plan(s, &p);
}

/// Deterministic state rendering: "lineage = <lineage>", "serial = <n>" and
/// one "<addr> <status> rev=<rev>" line per resource, LF separated with a
/// trailing LF.
pub fn state_render(s: &TfState) -> Str {
  var out = "lineage = " + s.lineage + "\n";
  out = out + "serial = " + convert.int_to_string(s.serial) + "\n";
  var i = 0;
  while i < s.res_addr.len() {
    let a: Str = s.res_addr[i];
    let st: Int = s.res_status[i];
    let rv: Int = s.res_rev[i];
    out = out + a + " " + state_status_name(st) + " rev=" + convert.int_to_string(rv) + "\n";
    i = i + 1;
  }
  return out;
}

// ---------------------------------------------------------------------------
// 9. Provider registry (registration, init, config integration)
// ---------------------------------------------------------------------------

/// An empty provider registry.
pub fn providers_new() -> TfProviders {
  return TfProviders{
    p_name: Vec[Str].new();
    p_source: Vec[Str].new();
    p_version: Vec[Str].new();
    p_inited: Vec[Int].new();
    init_count: 0;
  };
}

// Slot of provider `name`, or -1.
fn _provider_find(r: &TfProviders, name: Str) -> Int {
  var i = 0;
  while i < r.p_name.len() {
    let n: Str = r.p_name[i];
    if _streq(n, name) {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

/// Register one provider and return its index. Errors: empty name/source/
/// version, duplicate name, provider limit.
pub fn provider_register(r: &mut TfProviders, name: Str, source: Str, version: Str) -> Result[Int, Str] {
  if _streq(name, "") {
    return _int_err("provider: name must not be empty");
  }
  if _streq(source, "") {
    return _int_err("provider: source must not be empty");
  }
  if _streq(version, "") {
    return _int_err("provider: version must not be empty");
  }
  if _provider_find(r, name) >= 0 {
    return _int_err("provider: duplicate provider: " + name);
  }
  let cnt = r.p_name.len();
  if cnt >= TF_MAX_PROVIDERS {
    return _int_err("provider: provider limit exceeded");
  }
  r.p_name.push(name);
  r.p_source.push(source);
  r.p_version.push(version);
  r.p_inited.push(0);
  return _int_ok(cnt);
}

/// Number of registered providers.
pub fn provider_count(r: &TfProviders) -> Int {
  return r.p_name.len();
}

/// Slot of provider `name`, or TF_NOT_FOUND (-1).
pub fn provider_index(r: &TfProviders, name: Str) -> Int {
  return _provider_find(r, name);
}

/// Name of provider `i` ("" out of range).
pub fn provider_name(r: &TfProviders, i: Int) -> Str {
  if i < 0 || i >= r.p_name.len() {
    return "";
  }
  let v: Str = r.p_name[i];
  return v;
}

/// Source of provider `i` ("" out of range).
pub fn provider_source(r: &TfProviders, i: Int) -> Str {
  if i < 0 || i >= r.p_source.len() {
    return "";
  }
  let v: Str = r.p_source[i];
  return v;
}

/// Version constraint of provider `i` ("" out of range).
pub fn provider_version(r: &TfProviders, i: Int) -> Str {
  if i < 0 || i >= r.p_version.len() {
    return "";
  }
  let v: Str = r.p_version[i];
  return v;
}

/// True when provider `i` is initialized.
pub fn provider_is_initialized(r: &TfProviders, i: Int) -> Bool {
  if i < 0 || i >= r.p_inited.len() {
    return false;
  }
  let v: Int = r.p_inited[i];
  return v != 0;
}

/// Initialize one registered provider; returns the new initialized count.
/// Errors: unknown provider, already initialized.
pub fn provider_init(r: &mut TfProviders, name: Str) -> Result[Int, Str] {
  let i = _provider_find(r, name);
  if i < 0 {
    return _int_err("provider: unknown provider: " + name);
  }
  let cur: Int = r.p_inited[i];
  if cur != 0 {
    return _int_err("provider: already initialized: " + name);
  }
  r.p_inited[i] = 1;
  r.init_count = r.init_count + 1;
  return _int_ok(r.init_count);
}

/// Initialize every pending provider in registration order; returns how many
/// were initialized by this call.
pub fn provider_init_all(r: &mut TfProviders) -> Result[Int, Str] {
  var n = 0;
  var i = 0;
  while i < r.p_name.len() {
    let cur: Int = r.p_inited[i];
    if cur == 0 {
      r.p_inited[i] = 1;
      r.init_count = r.init_count + 1;
      n = n + 1;
    }
    i = i + 1;
  }
  return _int_ok(n);
}

/// Number of initialized providers.
pub fn provider_init_count(r: &TfProviders) -> Int {
  return r.init_count;
}

/// True when `name` is registered and initialized.
pub fn provider_is_ready(r: &TfProviders, name: Str) -> Bool {
  let i = _provider_find(r, name);
  if i < 0 {
    return false;
  }
  let v: Int = r.p_inited[i];
  return v != 0;
}

/// Provider names declared by top-level `provider` blocks, deduplicated in
/// first-occurrence order.
pub fn providers_from_config(c: &TfConfig) -> Vec[Str] {
  var out = Vec[Str].new();
  var i = 0;
  while i < c.block_type.len() {
    let t: Str = c.block_type[i];
    if _streq(t, "provider") {
      let labs: Str = c.block_labels[i];
      let name = _slice_field(labs, 0, _TF_SLASH);
      if !_streq(name, "") && !_vec_str_has(&out, name) {
        out.push(name);
      }
    }
    i = i + 1;
  }
  return out;
}

/// Configured providers that are not registered or not initialized.
pub fn provider_missing_from_config(r: &TfProviders, c: &TfConfig) -> Vec[Str] {
  var out = Vec[Str].new();
  let names = providers_from_config(c);
  var i = 0;
  while i < names.len() {
    let nm: Str = names[i];
    var ready = false;
    let idx = _provider_find(r, nm);
    if idx >= 0 {
      let cur: Int = r.p_inited[idx];
      if cur != 0 {
        ready = true;
      }
    }
    if !ready {
      out.push(nm);
    }
    i = i + 1;
  }
  return out;
}

/// Initialize every provider named by `c`; returns how many were initialized
/// by this call. Errors with "provider: not registered: <name>" when a
/// configured provider is absent from the registry.
pub fn provider_apply_config(r: &mut TfProviders, c: &TfConfig) -> Result[Int, Str] {
  let names = providers_from_config(c);
  var n = 0;
  var i = 0;
  while i < names.len() {
    let nm: Str = names[i];
    let idx = _provider_find(r, nm);
    if idx < 0 {
      return _int_err("provider: not registered: " + nm);
    }
    let cur: Int = r.p_inited[idx];
    if cur == 0 {
      r.p_inited[idx] = 1;
      r.init_count = r.init_count + 1;
      n = n + 1;
    }
    i = i + 1;
  }
  return _int_ok(n);
}

/// Deterministic registry rendering: one
/// "<name> <source> <version> <initialized|pending>" line per provider, LF
/// separated with a trailing LF.
pub fn provider_render(r: &TfProviders) -> Str {
  var out = "";
  var i = 0;
  while i < r.p_name.len() {
    let nm: Str = r.p_name[i];
    let src: Str = r.p_source[i];
    let ver: Str = r.p_version[i];
    let ini: Int = r.p_inited[i];
    var st = "pending";
    if ini != 0 {
      st = "initialized";
    }
    out = out + nm + " " + src + " " + ver + " " + st + "\n";
    i = i + 1;
  }
  return out;
}
