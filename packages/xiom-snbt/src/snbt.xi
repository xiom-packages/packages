// XIOM -- xiom.snbt: pure-XIOM SNBT (stringified NBT) codec
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// SNBT is the text form of Minecraft's Named Binary Tag data: compounds
// `{key:value,...}` (unquoted or quoted keys), lists `[value,...]`, typed
// arrays `[B;...]` / `[I;...]` / `[L;...]`, quoted or bare strings, booleans
// and suffixed numbers. snbt_parse validates one complete document into an
// SnbtTree, a flat node store built from parallel vectors with contiguous
// child ranges (no Vec[StructType]); snbt_emit writes a canonical, stable
// document back. See SPEC.md for the exact grammar, the key/word charsets,
// the canonical form and the error catalog.
//
// Number policy (v0.61.3: no Float64 in the public API, no Vec[Float64]):
//   * integer text (`1`, `-2`) and `b`/`s`/`L` suffixed forms are parsed to
//     Int values, range-checked per kind, and re-emitted canonically from
//     those values;
//   * decimal and exponent forms (`1.5`, `1e-3`, `1.5f`, `2.0d`) are kept as
//     validated text tokens: the numeric body is preserved verbatim and the
//     canonical suffix (`f` for float, `d` for double) is appended on emit.
//
// v0.61.3 notes that shaped this module:
//   * Ok/Err construction is confined to the leaf helpers below
//     (constructing Result values directly in struct-returning functions
//     miscompiles).
//   * Str values read from Vec[Str] elements are never compared with `==`
//     and never measured with str_len (BUG 17): text byte lengths live in
//     the parallel `text_len` vector, key lookup compares `data` bytes, and
//     materialized text is bound to a typed local before it is returned.
//   * all byte_at results widen through `(b as Int) & 0xFF` (BUG 17 family:
//     sign extension of high bytes), and every Vec[Int] element read is
//     bound to a typed local.
//   * every push on one parallel vector is mirrored on all its siblings;
//     snbt_emit refuses trees whose parallel vectors have drifted apart.

module xiom.snbt

use xiom.string;
use xiom.string.builder;
use xiom.convert;

/// String node (quoted or bare): `texts[node]` holds the decoded text.
pub const SNBT_KIND_STRING: Int = 1;
/// Boolean node: `values[node]` is 1 (`true`) or 0 (`false`).
pub const SNBT_KIND_BOOLEAN: Int = 2;
/// Byte node: `values[node]` is the signed 8-bit value, emitted as `<v>b`.
pub const SNBT_KIND_BYTE: Int = 3;
/// Short node: `values[node]` is the signed 16-bit value, emitted as `<v>s`.
pub const SNBT_KIND_SHORT: Int = 4;
/// Int node: `values[node]` is the signed 32-bit value, emitted bare.
pub const SNBT_KIND_INT: Int = 5;
/// Long node: `values[node]` is the signed 64-bit value, emitted as `<v>L`.
pub const SNBT_KIND_LONG: Int = 6;
/// Float node: `texts[node]` is the validated numeric body, emitted as `<body>f`.
pub const SNBT_KIND_FLOAT: Int = 7;
/// Double node: `texts[node]` is the validated numeric body, emitted as `<body>d`.
pub const SNBT_KIND_DOUBLE: Int = 8;
/// Compound node: ordered keyed children in its child range.
pub const SNBT_KIND_COMPOUND: Int = 9;
/// List node: ordered children of any kinds (heterogeneous lists are legal).
pub const SNBT_KIND_LIST: Int = 10;
/// Byte array `[B;...]`: children must all be SNBT_KIND_BYTE.
pub const SNBT_KIND_BYTE_ARRAY: Int = 11;
/// Int array `[I;...]`: children must all be SNBT_KIND_INT.
pub const SNBT_KIND_INT_ARRAY: Int = 12;
/// Long array `[L;...]`: children must all be SNBT_KIND_LONG.
pub const SNBT_KIND_LONG_ARRAY: Int = 13;
/// Maximum container (compound/list/array) nesting accepted by parse and emit.
pub const SNBT_MAX_DEPTH: Int = 64;

/// Flat SNBT node store. Every node is one index into the parallel vectors:
/// `kinds` is the node kind (1-13), `texts` the materialized text ("" for
/// containers, booleans and lists), `text_off`/`text_len` the exact text
/// bytes inside the shared `data` buffer, `key_off`/`key_len` the parent
/// compound key bytes (0/0 outside a compound), `parents` the owning node
/// (-1 for the root), and `child_start`/`child_count`/`order` a contiguous
/// child range inside `order`. `values` holds the integer/boolean payload or
/// a typed array's element kind. `root` is the root node index, or -1 for an
/// empty tree. Fields are implementation details; callers must go through
/// the free functions below.
pub type SnbtTree = {
  kinds: Vec[Int];
  texts: Vec[Str];
  text_off: Vec[Int];
  text_len: Vec[Int];
  key_off: Vec[Int];
  key_len: Vec[Int];
  parents: Vec[Int];
  child_start: Vec[Int];
  child_count: Vec[Int];
  order: Vec[Int];
  values: Vec[Int];
  data: Vec[UInt8];
  root: Int;
}

/// Internal byte cursor over the input text.
type SnbtParser = {
  input: Str;
  pos: Int;
  len: Int;
}

// --------------------------------------------------
//  Byte constants (ASCII)
// --------------------------------------------------

const BYTE_TAB: Int = 9;
const BYTE_LF: Int = 10;
const BYTE_CR: Int = 13;
const BYTE_SPACE: Int = 32;
const BYTE_QUOTE_D: Int = 34;
const BYTE_QUOTE_S: Int = 39;
const BYTE_PLUS: Int = 43;
const BYTE_COMMA: Int = 44;
const BYTE_MINUS: Int = 45;
const BYTE_DOT: Int = 46;
const BYTE_0: Int = 48;
const BYTE_9: Int = 57;
const BYTE_COLON: Int = 58;
const BYTE_SEMICOLON: Int = 59;
const BYTE_UPPER_A: Int = 65;
const BYTE_UPPER_B: Int = 66;
const BYTE_UPPER_D: Int = 68;
const BYTE_UPPER_E: Int = 69;
const BYTE_UPPER_F: Int = 70;
const BYTE_UPPER_I: Int = 73;
const BYTE_UPPER_L: Int = 76;
const BYTE_UPPER_S: Int = 83;
const BYTE_UPPER_Z: Int = 90;
const BYTE_BACKSLASH: Int = 92;
const BYTE_UNDERSCORE: Int = 95;
const BYTE_LOWER_A: Int = 97;
const BYTE_LOWER_B: Int = 98;
const BYTE_LOWER_D: Int = 100;
const BYTE_LOWER_E: Int = 101;
const BYTE_LOWER_F: Int = 102;
const BYTE_LOWER_L: Int = 108;
const BYTE_LOWER_N: Int = 110;
const BYTE_LOWER_S: Int = 115;
const BYTE_LOWER_T: Int = 116;
const BYTE_LOWER_Z: Int = 122;
const BYTE_OPEN_BRACE: Int = 123;
const BYTE_CLOSE_BRACE: Int = 125;
const BYTE_OPEN_BRACKET: Int = 91;
const BYTE_CLOSE_BRACKET: Int = 93;
const INT_MAX64: Int = 9223372036854775807;

// --------------------------------------------------
//  Result leaf constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[Int, Str].
fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

// Err(m) for Result[Int, Str].
fn _err_int(m: Str) -> Result[Int, Str] {
  return Err(m);
}

// Ok(v) for Result[Bool, Str].
fn _ok_bool(v: Bool) -> Result[Bool, Str] {
  return Ok(v);
}

// Err(m) for Result[Bool, Str].
fn _err_bool(m: Str) -> Result[Bool, Str] {
  return Err(m);
}

// Ok(v) for Result[Str, Str].
fn _ok_str(v: Str) -> Result[Str, Str] {
  return Ok(v);
}

// Err(m) for Result[Str, Str].
fn _err_str(m: Str) -> Result[Str, Str] {
  return Err(m);
}

// Ok(v) for Result[Vec[UInt8], Str].
fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  return Ok(v);
}

// Err(m) for Result[Vec[UInt8], Str].
fn _err_bytes(m: Str) -> Result[Vec[UInt8], Str] {
  return Err(m);
}

// Ok(v) for Result[SnbtTree, Str].
fn _ok_tree(v: SnbtTree) -> Result[SnbtTree, Str] {
  return Ok(v);
}

// Err(m) for Result[SnbtTree, Str].
fn _err_tree(m: Str) -> Result[SnbtTree, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Internal helpers
// --------------------------------------------------

// "snbt: unexpected kind N" for a reader called on the wrong node kind.
fn _unexpected_kind(k: Int) -> Str {
  return "snbt: unexpected kind " + convert.int_to_string(k);
}

// ASCII letter (A-Z / a-z)?
fn _is_alpha(b: Int) -> Bool {
  if b >= BYTE_UPPER_A && b <= BYTE_UPPER_Z { return true; }
  if b >= BYTE_LOWER_A && b <= BYTE_LOWER_Z { return true; }
  return false;
}

// ASCII digit (0-9)?
fn _is_digit(b: Int) -> Bool {
  return b >= BYTE_0 && b <= BYTE_9;
}

// Documented bare charset: A-Z a-z 0-9 . _ + -
fn _is_bare(b: Int) -> Bool {
  if _is_alpha(b) { return true; }
  if _is_digit(b) { return true; }
  if b == BYTE_DOT { return true; }
  if b == BYTE_UNDERSCORE { return true; }
  if b == BYTE_PLUS { return true; }
  if b == BYTE_MINUS { return true; }
  return false;
}

// Inter-token whitespace: space, tab, LF, CR.
fn _is_ws(b: Int) -> Bool {
  if b == BYTE_SPACE { return true; }
  if b == BYTE_TAB { return true; }
  if b == BYTE_LF { return true; }
  if b == BYTE_CR { return true; }
  return false;
}

// Current byte at the cursor, or -1 at end of input.
fn _peek(p: &SnbtParser) -> Int {
  if p.pos >= p.len { return -1; }
  return (string.byte_at(p.input, p.pos) as Int) & 0xFF;
}

// Byte at the cursor + offset, or -1 past the end of input.
fn _peek_at(p: &SnbtParser, off: Int) -> Int {
  let at = p.pos + off;
  if at >= p.len { return -1; }
  return (string.byte_at(p.input, at) as Int) & 0xFF;
}

// Advance the cursor one byte; no-op at end of input.
fn _advance(p: &mut SnbtParser) {
  if p.pos < p.len {
    p.pos = p.pos + 1;
  }
}

// Skip inter-token whitespace.
fn _skip_ws(p: &mut SnbtParser) {
  while _is_ws(_peek(p)) {
    _advance(p);
  }
}

// Does the input span [start, end) equal the ASCII literal `lit`?
fn _span_equals(p: &SnbtParser, start: Int, end: Int, lit: Str) -> Bool {
  let n = string.str_len(lit);
  if end - start != n { return false; }
  var i = 0;
  while i < n {
    let want = (string.byte_at(lit, i) as Int) & 0xFF;
    let got = (string.byte_at(p.input, start + i) as Int) & 0xFF;
    if want != got { return false; }
    i = i + 1;
  }
  return true;
}

// Materialize data[off, off + len) as a Str. A raw 0x00 byte terminates the
// Str view (parse never admits one, so this is defense in depth); truncating
// BEFORE sb_to_str keeps its len contract intact.
fn _materialize(tree: &SnbtTree, off: Int, len: Int) -> Str {
  var sb = Vec[UInt8].new();
  var i = 0;
  var done = false;
  while i < len && !done {
    var b: UInt8 = 0 as UInt8;
    let at = off + i;
    if at >= 0 && at < tree.data.len() {
      b = tree.data[at];
    }
    if b == 0 as UInt8 {
      done = true;
    } else {
      sb.push(b);
      i = i + 1;
    }
  }
  return builder.sb_to_str(&sb);
}

// Append the bytes of `bytes` to tree.data and return their offset.
fn _append_bytes(tree: &mut SnbtTree, bytes: &Vec[UInt8]) -> Int {
  let off = tree.data.len();
  var i = 0;
  while i < bytes.len() {
    tree.data.push(bytes[i]);
    i = i + 1;
  }
  return off;
}

// Append the input span [start, end) to tree.data and return its offset.
fn _append_span(tree: &mut SnbtTree, p: &SnbtParser, start: Int, end: Int) -> Int {
  let off = tree.data.len();
  var i = start;
  while i < end {
    tree.data.push(string.byte_at(p.input, i));
    i = i + 1;
  }
  return off;
}

// Create an empty node store (no root).
fn _tree_new() -> SnbtTree {
  return SnbtTree{
    kinds: Vec[Int].new();
    texts: Vec[Str].new();
    text_off: Vec[Int].new();
    text_len: Vec[Int].new();
    key_off: Vec[Int].new();
    key_len: Vec[Int].new();
    parents: Vec[Int].new();
    child_start: Vec[Int].new();
    child_count: Vec[Int].new();
    order: Vec[Int].new();
    values: Vec[Int].new();
    data: Vec[UInt8].new();
    root: -1;
  };
}

// Append a node to the store and return its index. `parent` < 0 marks the
// root (the first root wins). Every parallel vector receives exactly one
// push here.
fn _add_node(tree: &mut SnbtTree, kind: Int, parent: Int) -> Int {
  let idx = tree.kinds.len();
  tree.kinds.push(kind);
  tree.texts.push("");
  tree.text_off.push(0);
  tree.text_len.push(0);
  tree.key_off.push(0);
  tree.key_len.push(0);
  tree.parents.push(parent);
  tree.child_start.push(-1);
  tree.child_count.push(0);
  tree.values.push(0);
  if parent < 0 && tree.root < 0 {
    tree.root = idx;
  }
  return idx;
}

// Store `bytes` as the node text (used by quoted strings).
fn _set_text_bytes(tree: &mut SnbtTree, node: Int, bytes: &Vec[UInt8]) {
  let off = _append_bytes(tree, bytes);
  let n = bytes.len();
  tree.text_off[node] = off;
  tree.text_len[node] = n;
  let s = _materialize(tree, off, n);
  tree.texts[node] = s;
}

// Store the input span [start, end) as the node text (bare words, numeric
// bodies).
fn _set_text_span(tree: &mut SnbtTree, node: Int, p: &SnbtParser, start: Int, end: Int) {
  let off = _append_span(tree, p, start, end);
  let n = end - start;
  tree.text_off[node] = off;
  tree.text_len[node] = n;
  let s = _materialize(tree, off, n);
  tree.texts[node] = s;
}

// Store the canonical decimal rendering of `v` as the node text. The
// emitter renders integer kinds from `values`; this text is the accessor
// view (snbt_text) and is always consistent with the value.
fn _set_text_int(tree: &mut SnbtTree, node: Int, v: Int) {
  let s = convert.int_to_string(v);
  let n = string.str_len(s);
  let off = tree.data.len();
  var i = 0;
  while i < n {
    tree.data.push(string.byte_at(s, i));
    i = i + 1;
  }
  tree.text_off[node] = off;
  tree.text_len[node] = n;
  tree.texts[node] = s;
}

// Rebuild `child_start` / `child_count` / `order` from `parents`. O(nodes).
// Called by snbt_parse; the parse order makes parent indices always smaller
// than child indices, so the counting sort below is stable in document order.
fn _finalize(tree: &mut SnbtTree) {
  let n = tree.kinds.len();
  var counts = Vec[Int].new();
  var i = 0;
  while i < n {
    counts.push(0);
    i = i + 1;
  }
  i = 0;
  while i < n {
    let p: Int = tree.parents[i];
    if p >= 0 && p < n {
      let c: Int = counts[p];
      counts[p] = c + 1;
    }
    i = i + 1;
  }
  var starts = Vec[Int].new();
  var acc = 0;
  i = 0;
  while i < n {
    starts.push(acc);
    let c: Int = counts[i];
    acc = acc + c;
    i = i + 1;
  }
  var order = Vec[Int].new();
  i = 0;
  while i < n {
    order.push(-1);
    i = i + 1;
  }
  var cursors = Vec[Int].new();
  i = 0;
  while i < n {
    let s: Int = starts[i];
    cursors.push(s);
    i = i + 1;
  }
  i = 0;
  while i < n {
    let p: Int = tree.parents[i];
    if p >= 0 && p < n {
      let cur: Int = cursors[p];
      if cur >= 0 && cur < n {
        order[cur] = i;
        cursors[p] = cur + 1;
      }
    }
    i = i + 1;
  }
  tree.child_start = starts;
  tree.child_count = counts;
  tree.order = order;
}

// --------------------------------------------------
//  Parser
// --------------------------------------------------

// Parse a quoted string (single or double quotes, the caller has checked).
// Documented escapes: \\ \" \' \n \t. Any other escape is a bad escape; a
// raw byte below 32 is an unexpected character; EOF before the closing
// quote is an unterminated string.
fn _parse_quoted(p: &mut SnbtParser) -> Result[Vec[UInt8], Str] {
  let quote = _peek(p);
  _advance(p);
  var out = Vec[UInt8].new();
  var done = false;
  while !done {
    let b = _peek(p);
    if b < 0 {
      return _err_bytes("snbt: unterminated string");
    }
    if b == quote {
      _advance(p);
      done = true;
    } elif b == BYTE_BACKSLASH {
      _advance(p);
      let e = _peek(p);
      if e == BYTE_BACKSLASH {
        out.push(BYTE_BACKSLASH as UInt8);
        _advance(p);
      } elif e == BYTE_QUOTE_D {
        out.push(BYTE_QUOTE_D as UInt8);
        _advance(p);
      } elif e == BYTE_QUOTE_S {
        out.push(BYTE_QUOTE_S as UInt8);
        _advance(p);
      } elif e == BYTE_LOWER_N {
        out.push(BYTE_LF as UInt8);
        _advance(p);
      } elif e == BYTE_LOWER_T {
        out.push(BYTE_TAB as UInt8);
        _advance(p);
      } else {
        return _err_bytes("snbt: bad escape");
      }
    } elif b < 32 {
      return _err_bytes("snbt: unexpected character");
    } else {
      out.push(b as UInt8);
      _advance(p);
    }
  }
  return _ok_bytes(out);
}

// Parse a number token starting at the cursor (the caller has checked that
// the first byte is a digit or '-'). Integer forms yield BYTE/SHORT/INT/LONG
// nodes with range-checked values; decimal/exponent forms yield FLOAT/DOUBLE
// text nodes preserving the numeric body verbatim.
fn _parse_number(p: &mut SnbtParser, tree: &mut SnbtTree, parent: Int) -> Result[Int, Str] {
  let start = p.pos;
  var neg = false;
  if _peek(p) == BYTE_MINUS {
    neg = true;
    _advance(p);
  }
  if !_is_digit(_peek(p)) {
    return _err_int("snbt: invalid number");
  }
  var acc: Int = 0;
  var overflow = false;
  while _is_digit(_peek(p)) {
    let d = _peek(p) - BYTE_0;
    let cap = (INT_MAX64 - d) / 10;
    if acc > cap { overflow = true; }
    if !overflow { acc = acc * 10 + d; }
    _advance(p);
  }
  var has_frac = false;
  if _peek(p) == BYTE_DOT {
    _advance(p);
    if !_is_digit(_peek(p)) {
      return _err_int("snbt: invalid number");
    }
    while _is_digit(_peek(p)) {
      _advance(p);
    }
    has_frac = true;
  }
  var has_exp = false;
  let eb = _peek(p);
  if eb == BYTE_LOWER_E || eb == BYTE_UPPER_E {
    _advance(p);
    let sb = _peek(p);
    if sb == BYTE_PLUS || sb == BYTE_MINUS {
      _advance(p);
    }
    if !_is_digit(_peek(p)) {
      return _err_int("snbt: invalid number");
    }
    while _is_digit(_peek(p)) {
      _advance(p);
    }
    has_exp = true;
  }
  let body_end = p.pos;
  var suffix = -1;
  let sb2 = _peek(p);
  if _is_alpha(sb2) {
    suffix = sb2;
    _advance(p);
    if _is_bare(_peek(p)) {
      return _err_int("snbt: bad number suffix");
    }
  } elif _is_bare(sb2) {
    return _err_int("snbt: invalid number");
  }
  if !has_frac && !has_exp {
    var kind = SNBT_KIND_INT;
    if suffix == BYTE_LOWER_B || suffix == BYTE_UPPER_B {
      kind = SNBT_KIND_BYTE;
    } elif suffix == BYTE_LOWER_S || suffix == BYTE_UPPER_S {
      kind = SNBT_KIND_SHORT;
    } elif suffix == BYTE_LOWER_L || suffix == BYTE_UPPER_L {
      kind = SNBT_KIND_LONG;
    } elif suffix == BYTE_LOWER_F || suffix == BYTE_UPPER_F {
      kind = SNBT_KIND_FLOAT;
    } elif suffix == BYTE_LOWER_D || suffix == BYTE_UPPER_D {
      kind = SNBT_KIND_DOUBLE;
    } elif suffix >= 0 {
      return _err_int("snbt: bad number suffix");
    }
    if kind == SNBT_KIND_FLOAT || kind == SNBT_KIND_DOUBLE {
      let node = _add_node(tree, kind, parent);
      _set_text_span(tree, node, p, start, body_end);
      return _ok_int(node);
    }
    if overflow {
      return _err_int("snbt: integer out of range");
    }
    var in_range = true;
    if kind == SNBT_KIND_BYTE {
      if neg { in_range = acc <= 128; } else { in_range = acc <= 127; }
    } elif kind == SNBT_KIND_SHORT {
      if neg { in_range = acc <= 32768; } else { in_range = acc <= 32767; }
    } elif kind == SNBT_KIND_INT {
      if neg { in_range = acc <= 2147483648; } else { in_range = acc <= 2147483647; }
    }
    if !in_range {
      return _err_int("snbt: integer out of range");
    }
    var v = acc;
    if neg { v = -acc; }
    let node = _add_node(tree, kind, parent);
    tree.values[node] = v;
    _set_text_int(tree, node, v);
    return _ok_int(node);
  }
  if suffix >= 0 && suffix != BYTE_LOWER_F && suffix != BYTE_UPPER_F && suffix != BYTE_LOWER_D && suffix != BYTE_UPPER_D {
    return _err_int("snbt: bad number suffix");
  }
  var kind = SNBT_KIND_DOUBLE;
  if suffix == BYTE_LOWER_F || suffix == BYTE_UPPER_F {
    kind = SNBT_KIND_FLOAT;
  }
  let node = _add_node(tree, kind, parent);
  _set_text_span(tree, node, p, start, body_end);
  return _ok_int(node);
}

// Parse a bare word (unquoted, documented charset). `true`/`false` become
// boolean nodes; every other word is a string node.
fn _parse_bare(p: &mut SnbtParser, tree: &mut SnbtTree, parent: Int) -> Result[Int, Str] {
  let start = p.pos;
  while _is_bare(_peek(p)) {
    _advance(p);
  }
  let end = p.pos;
  if _span_equals(p, start, end, "true") {
    let node = _add_node(tree, SNBT_KIND_BOOLEAN, parent);
    tree.values[node] = 1;
    return _ok_int(node);
  }
  if _span_equals(p, start, end, "false") {
    let node = _add_node(tree, SNBT_KIND_BOOLEAN, parent);
    tree.values[node] = 0;
    return _ok_int(node);
  }
  let node = _add_node(tree, SNBT_KIND_STRING, parent);
  _set_text_span(tree, node, p, start, end);
  return _ok_int(node);
}

// Parse one value at the cursor into the store and return its node index.
fn _parse_value(p: &mut SnbtParser, tree: &mut SnbtTree, parent: Int, depth: Int) -> Result[Int, Str] {
  let b = _peek(p);
  if b == BYTE_OPEN_BRACE {
    return _parse_compound(p, tree, parent, depth);
  }
  if b == BYTE_OPEN_BRACKET {
    return _parse_list(p, tree, parent, depth);
  }
  if b == BYTE_QUOTE_D || b == BYTE_QUOTE_S {
    let qr = _parse_quoted(p);
    if !qr.is_ok {
      return _err_int(qr.error);
    }
    let bytes = qr.value;
    let node = _add_node(tree, SNBT_KIND_STRING, parent);
    _set_text_bytes(tree, node, &bytes);
    return _ok_int(node);
  }
  if _is_digit(b) || b == BYTE_MINUS {
    return _parse_number(p, tree, parent);
  }
  if _is_bare(b) {
    return _parse_bare(p, tree, parent);
  }
  return _err_int("snbt: unexpected character");
}

// Parse a compound starting at '{'. Keys are quoted or bare; a single
// trailing comma before '}' is accepted.
fn _parse_compound(p: &mut SnbtParser, tree: &mut SnbtTree, parent: Int, depth: Int) -> Result[Int, Str] {
  if depth > SNBT_MAX_DEPTH {
    return _err_int("snbt: depth exceeded");
  }
  _advance(p);
  let node = _add_node(tree, SNBT_KIND_COMPOUND, parent);
  _skip_ws(p);
  if _peek(p) == BYTE_CLOSE_BRACE {
    _advance(p);
    return _ok_int(node);
  }
  var done = false;
  while !done {
    _skip_ws(p);
    let b = _peek(p);
    if b < 0 {
      return _err_int("snbt: unbalanced braces");
    }
    var key_off = 0;
    var key_len = 0;
    if b == BYTE_QUOTE_D || b == BYTE_QUOTE_S {
      let qr = _parse_quoted(p);
      if !qr.is_ok {
        return _err_int(qr.error);
      }
      let kbytes = qr.value;
      key_off = _append_bytes(tree, &kbytes);
      key_len = kbytes.len();
    } elif _is_bare(b) {
      let ks = p.pos;
      while _is_bare(_peek(p)) {
        _advance(p);
      }
      let ke = p.pos;
      let stop = _peek(p);
      if stop >= 0 && stop != BYTE_COLON && !_is_ws(stop) {
        return _err_int("snbt: bad key");
      }
      key_off = _append_span(tree, p, ks, ke);
      key_len = ke - ks;
    } else {
      return _err_int("snbt: bad key");
    }
    _skip_ws(p);
    if _peek(p) != BYTE_COLON {
      return _err_int("snbt: missing colon");
    }
    _advance(p);
    _skip_ws(p);
    let vr = _parse_value(p, tree, node, depth + 1);
    if !vr.is_ok {
      return _err_int(vr.error);
    }
    let child = vr.value;
    tree.key_off[child] = key_off;
    tree.key_len[child] = key_len;
    _skip_ws(p);
    let nb = _peek(p);
    if nb == BYTE_COMMA {
      _advance(p);
      _skip_ws(p);
      if _peek(p) == BYTE_CLOSE_BRACE {
        _advance(p);
        done = true;
      }
    } elif nb == BYTE_CLOSE_BRACE {
      _advance(p);
      done = true;
    } elif nb < 0 {
      return _err_int("snbt: unbalanced braces");
    } else {
      if nb == BYTE_CLOSE_BRACKET {
        return _err_int("snbt: unbalanced braces");
      }
      return _err_int("snbt: unexpected character");
    }
  }
  return _ok_int(node);
}

// Parse a list or typed array starting at '['. `[B;` / `[I;` / `[L;` (the
// ';' directly after an uppercase type letter) introduce a homogeneous typed
// array; anything else is a heterogeneous list. A single trailing comma
// before ']' is accepted.
fn _parse_list(p: &mut SnbtParser, tree: &mut SnbtTree, parent: Int, depth: Int) -> Result[Int, Str] {
  if depth > SNBT_MAX_DEPTH {
    return _err_int("snbt: depth exceeded");
  }
  _advance(p);
  _skip_ws(p);
  var elem_kind = -1;
  let b0 = _peek(p);
  let b1 = _peek_at(p, 1);
  if b1 == BYTE_SEMICOLON && (b0 == BYTE_UPPER_B || b0 == BYTE_UPPER_I || b0 == BYTE_UPPER_L) {
    if b0 == BYTE_UPPER_B {
      elem_kind = SNBT_KIND_BYTE;
    } elif b0 == BYTE_UPPER_I {
      elem_kind = SNBT_KIND_INT;
    } else {
      elem_kind = SNBT_KIND_LONG;
    }
    _advance(p);
    _advance(p);
  }
  var array_kind = SNBT_KIND_LIST;
  if elem_kind == SNBT_KIND_BYTE {
    array_kind = SNBT_KIND_BYTE_ARRAY;
  } elif elem_kind == SNBT_KIND_INT {
    array_kind = SNBT_KIND_INT_ARRAY;
  } elif elem_kind == SNBT_KIND_LONG {
    array_kind = SNBT_KIND_LONG_ARRAY;
  }
  let node = _add_node(tree, array_kind, parent);
  if elem_kind >= 0 {
    tree.values[node] = elem_kind;
  }
  _skip_ws(p);
  if _peek(p) == BYTE_CLOSE_BRACKET {
    _advance(p);
    return _ok_int(node);
  }
  var done = false;
  while !done {
    _skip_ws(p);
    let vr = _parse_value(p, tree, node, depth + 1);
    if !vr.is_ok {
      return _err_int(vr.error);
    }
    if elem_kind >= 0 {
      let ek: Int = tree.kinds[vr.value];
      if ek != elem_kind {
        return _err_int("snbt: mixed typed array");
      }
    }
    _skip_ws(p);
    let nb = _peek(p);
    if nb == BYTE_COMMA {
      _advance(p);
      _skip_ws(p);
      if _peek(p) == BYTE_CLOSE_BRACKET {
        _advance(p);
        done = true;
      }
    } elif nb == BYTE_CLOSE_BRACKET {
      _advance(p);
      done = true;
    } elif nb < 0 {
      return _err_int("snbt: unbalanced brackets");
    } else {
      if nb == BYTE_CLOSE_BRACE {
        return _err_int("snbt: unbalanced brackets");
      }
      return _err_int("snbt: unexpected character");
    }
  }
  return _ok_int(node);
}

// --------------------------------------------------
//  Public parse
// --------------------------------------------------

/// Parse one complete SNBT document into a flat node store. The root may be
/// any kind; container nesting is capped at SNBT_MAX_DEPTH and trailing
/// non-whitespace text is an error ("snbt: trailing tokens"). The returned
/// tree is finalized, so all navigation accessors work immediately.
pub fn snbt_parse(input: Str) -> Result[SnbtTree, Str] {
  var tree = _tree_new();
  var p = SnbtParser{ input: input; pos: 0; len: string.str_len(input); };
  _skip_ws(&mut p);
  if p.pos >= p.len {
    return _err_tree("snbt: empty input");
  }
  let vr = _parse_value(&mut p, &mut tree, -1, 1);
  if !vr.is_ok {
    return _err_tree(vr.error);
  }
  _skip_ws(&mut p);
  if p.pos < p.len {
    return _err_tree("snbt: trailing tokens");
  }
  _finalize(&mut tree);
  return _ok_tree(tree);
}

// --------------------------------------------------
//  Navigation accessors
// --------------------------------------------------

/// Number of nodes in the store (0 for an empty tree).
pub fn snbt_node_count(tree: &SnbtTree) -> Int {
  return tree.kinds.len();
}

/// Root node index, or -1 when the tree has no root.
pub fn snbt_root(tree: &SnbtTree) -> Int {
  return tree.root;
}

/// Kind (1-13, `SNBT_KIND_*`) of `node`, or -1 for an out-of-range index.
pub fn snbt_kind(tree: &SnbtTree, node: Int) -> Int {
  if node < 0 || node >= tree.kinds.len() {
    return -1;
  }
  let k: Int = tree.kinds[node];
  return k;
}

/// Stable lower-case name of a kind constant ("" for an unknown value).
pub fn snbt_kind_name(kind: Int) -> Str {
  if kind == SNBT_KIND_STRING { return "string"; }
  if kind == SNBT_KIND_BOOLEAN { return "boolean"; }
  if kind == SNBT_KIND_BYTE { return "byte"; }
  if kind == SNBT_KIND_SHORT { return "short"; }
  if kind == SNBT_KIND_INT { return "int"; }
  if kind == SNBT_KIND_LONG { return "long"; }
  if kind == SNBT_KIND_FLOAT { return "float"; }
  if kind == SNBT_KIND_DOUBLE { return "double"; }
  if kind == SNBT_KIND_COMPOUND { return "compound"; }
  if kind == SNBT_KIND_LIST { return "list"; }
  if kind == SNBT_KIND_BYTE_ARRAY { return "byte_array"; }
  if kind == SNBT_KIND_INT_ARRAY { return "int_array"; }
  if kind == SNBT_KIND_LONG_ARRAY { return "long_array"; }
  return "";
}

/// Stored text of `node`: the decoded string, a numeric body for
/// float/double, the canonical decimal for integer kinds; "" for booleans,
/// containers and out-of-range indices.
pub fn snbt_text(tree: &SnbtTree, node: Int) -> Str {
  if node < 0 || node >= tree.texts.len() {
    return "";
  }
  let s: Str = tree.texts[node];
  return s;
}

/// Key of `node` inside its parent compound, or "" when the node is not a
/// compound child (an empty quoted key also reads as "").
pub fn snbt_key(tree: &SnbtTree, node: Int) -> Str {
  if node < 0 || node >= tree.key_len.len() {
    return "";
  }
  let off: Int = tree.key_off[node];
  let len: Int = tree.key_len[node];
  return _materialize(tree, off, len);
}

/// Parent node index, or -1 for the root and out-of-range nodes.
pub fn snbt_parent(tree: &SnbtTree, node: Int) -> Int {
  if node < 0 || node >= tree.parents.len() {
    return -1;
  }
  let p: Int = tree.parents[node];
  return p;
}

/// Number of children of `node` (0 for leaves and out-of-range nodes).
pub fn snbt_child_count(tree: &SnbtTree, node: Int) -> Int {
  if node < 0 || node >= tree.child_count.len() {
    return 0;
  }
  let c: Int = tree.child_count[node];
  return c;
}

/// Child node index at position `index` (0-based), or -1 when out of range.
pub fn snbt_child_at(tree: &SnbtTree, node: Int, index: Int) -> Int {
  if node < 0 || node >= tree.kinds.len() {
    return -1;
  }
  if index < 0 {
    return -1;
  }
  let c: Int = tree.child_count[node];
  if index >= c {
    return -1;
  }
  let s: Int = tree.child_start[node];
  let at = s + index;
  if at < 0 || at >= tree.order.len() {
    return -1;
  }
  let ch: Int = tree.order[at];
  if ch < 0 || ch >= tree.kinds.len() {
    return -1;
  }
  return ch;
}

// Does the stored key of `node` equal `key` byte for byte?
fn _key_equals(tree: &SnbtTree, node: Int, key: Str) -> Bool {
  let klen = string.str_len(key);
  let len: Int = tree.key_len[node];
  if len != klen {
    return false;
  }
  let off: Int = tree.key_off[node];
  var i = 0;
  while i < len {
    let at = off + i;
    var b: UInt8 = 0 as UInt8;
    if at >= 0 && at < tree.data.len() {
      b = tree.data[at];
    }
    let got = (b as Int) & 0xFF;
    let want = (string.byte_at(key, i) as Int) & 0xFF;
    if got != want {
      return false;
    }
    i = i + 1;
  }
  return true;
}

/// First compound child of `node` whose key equals `key`, or -1 when absent
/// (or when `node` is not a compound). Byte-exact key comparison.
pub fn snbt_find_child(tree: &SnbtTree, node: Int, key: Str) -> Int {
  if node < 0 || node >= tree.kinds.len() {
    return -1;
  }
  let c: Int = snbt_child_count(tree, node);
  var i = 0;
  while i < c {
    let ch: Int = snbt_child_at(tree, node, i);
    if ch >= 0 {
      if _key_equals(tree, ch, key) {
        return ch;
      }
    }
    i = i + 1;
  }
  return -1;
}

// --------------------------------------------------
//  Typed readers
// --------------------------------------------------

// Ok(kind) when `node` exists; Err otherwise.
fn _require_kind(tree: &SnbtTree, node: Int) -> Result[Int, Str] {
  if node < 0 || node >= tree.kinds.len() {
    return _err_int("snbt: node index out of range");
  }
  let k: Int = tree.kinds[node];
  return _ok_int(k);
}

/// Element count of a list node. Err("snbt: unexpected kind N") on another
/// kind, Err("snbt: node index out of range") on a bad index.
pub fn snbt_list_count(tree: &SnbtTree, node: Int) -> Result[Int, Str] {
  let kr = _require_kind(tree, node);
  if !kr.is_ok {
    return _err_int(kr.error);
  }
  if kr.value != SNBT_KIND_LIST {
    return _err_int(_unexpected_kind(kr.value));
  }
  let c: Int = tree.child_count[node];
  return _ok_int(c);
}

/// Element node index of list element `index` (0-based). Err on a non-list
/// node or an out-of-range index ("snbt: list index out of range").
pub fn snbt_list_item(tree: &SnbtTree, node: Int, index: Int) -> Result[Int, Str] {
  let kr = _require_kind(tree, node);
  if !kr.is_ok {
    return _err_int(kr.error);
  }
  if kr.value != SNBT_KIND_LIST {
    return _err_int(_unexpected_kind(kr.value));
  }
  let ch = snbt_child_at(tree, node, index);
  if ch < 0 {
    return _err_int("snbt: list index out of range");
  }
  return _ok_int(ch);
}

/// Element count of a typed array node (`[B;`, `[I;` or `[L;`). Err on
/// another kind or a bad index.
pub fn snbt_array_count(tree: &SnbtTree, node: Int) -> Result[Int, Str] {
  let kr = _require_kind(tree, node);
  if !kr.is_ok {
    return _err_int(kr.error);
  }
  let k = kr.value;
  if k != SNBT_KIND_BYTE_ARRAY && k != SNBT_KIND_INT_ARRAY && k != SNBT_KIND_LONG_ARRAY {
    return _err_int(_unexpected_kind(k));
  }
  let c: Int = tree.child_count[node];
  return _ok_int(c);
}

/// Declared element kind of a typed array node (SNBT_KIND_BYTE for `[B;`,
/// SNBT_KIND_INT for `[I;`, SNBT_KIND_LONG for `[L;`). Err on another kind
/// or a bad index.
pub fn snbt_array_element_kind(tree: &SnbtTree, node: Int) -> Result[Int, Str] {
  let kr = _require_kind(tree, node);
  if !kr.is_ok {
    return _err_int(kr.error);
  }
  let k = kr.value;
  if k != SNBT_KIND_BYTE_ARRAY && k != SNBT_KIND_INT_ARRAY && k != SNBT_KIND_LONG_ARRAY {
    return _err_int(_unexpected_kind(k));
  }
  let e: Int = tree.values[node];
  return _ok_int(e);
}

// Shared body of the typed integer readers: require `want`, return the value.
fn _read_integer(tree: &SnbtTree, node: Int, want: Int) -> Result[Int, Str] {
  let kr = _require_kind(tree, node);
  if !kr.is_ok {
    return _err_int(kr.error);
  }
  if kr.value != want {
    return _err_int(_unexpected_kind(kr.value));
  }
  let v: Int = tree.values[node];
  return _ok_int(v);
}

/// Value of any integer node (BYTE, SHORT, INT or LONG) as an Int. Err on
/// another kind or a bad index.
pub fn snbt_get_integer(tree: &SnbtTree, node: Int) -> Result[Int, Str] {
  let kr = _require_kind(tree, node);
  if !kr.is_ok {
    return _err_int(kr.error);
  }
  let k = kr.value;
  if k < SNBT_KIND_BYTE || k > SNBT_KIND_LONG {
    return _err_int(_unexpected_kind(k));
  }
  let v: Int = tree.values[node];
  return _ok_int(v);
}

/// Signed value of a BYTE node. Err on another kind or a bad index.
pub fn snbt_get_byte(tree: &SnbtTree, node: Int) -> Result[Int, Str] {
  return _read_integer(tree, node, SNBT_KIND_BYTE);
}

/// Signed value of a SHORT node. Err on another kind or a bad index.
pub fn snbt_get_short(tree: &SnbtTree, node: Int) -> Result[Int, Str] {
  return _read_integer(tree, node, SNBT_KIND_SHORT);
}

/// Signed value of an INT node. Err on another kind or a bad index.
pub fn snbt_get_int(tree: &SnbtTree, node: Int) -> Result[Int, Str] {
  return _read_integer(tree, node, SNBT_KIND_INT);
}

/// Signed value of a LONG node. Err on another kind or a bad index.
pub fn snbt_get_long(tree: &SnbtTree, node: Int) -> Result[Int, Str] {
  return _read_integer(tree, node, SNBT_KIND_LONG);
}

/// Boolean value of a BOOLEAN node. Err on another kind or a bad index.
pub fn snbt_get_bool(tree: &SnbtTree, node: Int) -> Result[Bool, Str] {
  let kr = _require_kind(tree, node);
  if !kr.is_ok {
    return _err_bool(kr.error);
  }
  if kr.value != SNBT_KIND_BOOLEAN {
    return _err_bool(_unexpected_kind(kr.value));
  }
  let v: Int = tree.values[node];
  if v != 0 {
    return _ok_bool(true);
  }
  return _ok_bool(false);
}

/// Decoded text of a STRING node (quoted or bare). Err on another kind or a
/// bad index.
pub fn snbt_get_string(tree: &SnbtTree, node: Int) -> Result[Str, Str] {
  let kr = _require_kind(tree, node);
  if !kr.is_ok {
    return _err_str(kr.error);
  }
  if kr.value != SNBT_KIND_STRING {
    return _err_str(_unexpected_kind(kr.value));
  }
  let s: Str = tree.texts[node];
  return _ok_str(s);
}

// --------------------------------------------------
//  Canonical emitter
// --------------------------------------------------

// All parallel vectors share one length and every text/key range lies inside
// `data` (drift guard; misalignment can otherwise cause access violations).
fn _tree_well_formed(tree: &SnbtTree) -> Bool {
  let n = tree.kinds.len();
  if tree.texts.len() != n { return false; }
  if tree.text_off.len() != n { return false; }
  if tree.text_len.len() != n { return false; }
  if tree.key_off.len() != n { return false; }
  if tree.key_len.len() != n { return false; }
  if tree.parents.len() != n { return false; }
  if tree.child_start.len() != n { return false; }
  if tree.child_count.len() != n { return false; }
  if tree.order.len() != n { return false; }
  if tree.values.len() != n { return false; }
  if tree.root < -1 || tree.root >= n { return false; }
  var i = 0;
  while i < n {
    let to: Int = tree.text_off[i];
    let tl: Int = tree.text_len[i];
    if to < 0 || tl < 0 || to + tl > tree.data.len() { return false; }
    let ko: Int = tree.key_off[i];
    let kl: Int = tree.key_len[i];
    if ko < 0 || kl < 0 || ko + kl > tree.data.len() { return false; }
    i = i + 1;
  }
  return true;
}

// Is the stored integer value inside the kind's signed range?
fn _int_value_in_range(v: Int, kind: Int) -> Bool {
  if kind == SNBT_KIND_BYTE {
    return v >= -128 && v <= 127;
  }
  if kind == SNBT_KIND_SHORT {
    return v >= -32768 && v <= 32767;
  }
  if kind == SNBT_KIND_INT {
    return v >= -2147483648 && v <= 2147483647;
  }
  return true;
}

// Push the raw bytes of data[off, off + len) into the output.
fn _emit_raw_range(tree: &SnbtTree, off: Int, len: Int, out: &mut Vec[UInt8]) {
  var i = 0;
  while i < len {
    let at = off + i;
    var b: UInt8 = 0 as UInt8;
    if at >= 0 && at < tree.data.len() {
      b = tree.data[at];
    }
    out.push(b);
    i = i + 1;
  }
}

// Push data[off, off + len) as a double-quoted string with the documented
// canonical escapes: \" \\ \n \t. Other bytes pass through verbatim (parse
// admits no other control bytes).
fn _emit_quoted_range(tree: &SnbtTree, off: Int, len: Int, out: &mut Vec[UInt8]) {
  builder.sb_push_byte(out, BYTE_QUOTE_D as UInt8);
  var i = 0;
  while i < len {
    let at = off + i;
    var b: UInt8 = 0 as UInt8;
    if at >= 0 && at < tree.data.len() {
      b = tree.data[at];
    }
    let bi = (b as Int) & 0xFF;
    if bi == BYTE_BACKSLASH {
      builder.sb_push_byte(out, BYTE_BACKSLASH as UInt8);
      builder.sb_push_byte(out, BYTE_BACKSLASH as UInt8);
    } elif bi == BYTE_QUOTE_D {
      builder.sb_push_byte(out, BYTE_BACKSLASH as UInt8);
      builder.sb_push_byte(out, BYTE_QUOTE_D as UInt8);
    } elif bi == BYTE_LF {
      builder.sb_push_byte(out, BYTE_BACKSLASH as UInt8);
      builder.sb_push_byte(out, BYTE_LOWER_N as UInt8);
    } elif bi == BYTE_TAB {
      builder.sb_push_byte(out, BYTE_BACKSLASH as UInt8);
      builder.sb_push_byte(out, BYTE_LOWER_T as UInt8);
    } else {
      builder.sb_push_byte(out, b);
    }
    i = i + 1;
  }
  builder.sb_push_byte(out, BYTE_QUOTE_D as UInt8);
}

// Store the text bytes of `node` verbatim (float/double bodies).
fn _emit_text_range(tree: &SnbtTree, node: Int, out: &mut Vec[UInt8]) {
  let off: Int = tree.text_off[node];
  let len: Int = tree.text_len[node];
  _emit_raw_range(tree, off, len, out);
}

// Emit a key: bare when every byte is in the documented charset and the key
// is non-empty, double-quoted otherwise.
fn _emit_key(tree: &SnbtTree, node: Int, out: &mut Vec[UInt8]) {
  let off: Int = tree.key_off[node];
  let len: Int = tree.key_len[node];
  var bare = len > 0;
  var i = 0;
  while i < len && bare {
    let at = off + i;
    var b: UInt8 = 0 as UInt8;
    if at >= 0 && at < tree.data.len() {
      b = tree.data[at];
    }
    if !_is_bare((b as Int) & 0xFF) {
      bare = false;
    }
    i = i + 1;
  }
  if bare {
    _emit_raw_range(tree, off, len, out);
  } else {
    _emit_quoted_range(tree, off, len, out);
  }
}

// Emit one node. Container depth is capped at SNBT_MAX_DEPTH.
fn _emit_node(tree: &SnbtTree, node: Int, out: &mut Vec[UInt8], depth: Int) -> Result[Int, Str] {
  if node < 0 || node >= tree.kinds.len() {
    return _err_int("snbt: invalid tree");
  }
  let k: Int = tree.kinds[node];
  if k < SNBT_KIND_STRING || k > SNBT_KIND_LONG_ARRAY {
    return _err_int("snbt: invalid tree");
  }
  if k == SNBT_KIND_STRING {
    let off: Int = tree.text_off[node];
    let len: Int = tree.text_len[node];
    _emit_quoted_range(tree, off, len, out);
    return _ok_int(0);
  }
  if k == SNBT_KIND_BOOLEAN {
    let v: Int = tree.values[node];
    if v != 0 {
      builder.sb_push_str(out, "true");
    } else {
      builder.sb_push_str(out, "false");
    }
    return _ok_int(0);
  }
  if k >= SNBT_KIND_BYTE && k <= SNBT_KIND_LONG {
    let v: Int = tree.values[node];
    if !_int_value_in_range(v, k) {
      return _err_int("snbt: invalid tree");
    }
    builder.sb_push_int(out, v);
    if k == SNBT_KIND_BYTE {
      out.push(BYTE_LOWER_B as UInt8);
    } elif k == SNBT_KIND_SHORT {
      out.push(BYTE_LOWER_S as UInt8);
    } elif k == SNBT_KIND_LONG {
      out.push(BYTE_UPPER_L as UInt8);
    }
    return _ok_int(0);
  }
  if k == SNBT_KIND_FLOAT {
    _emit_text_range(tree, node, out);
    out.push(BYTE_LOWER_F as UInt8);
    return _ok_int(0);
  }
  if k == SNBT_KIND_DOUBLE {
    _emit_text_range(tree, node, out);
    out.push(BYTE_LOWER_D as UInt8);
    return _ok_int(0);
  }
  if k == SNBT_KIND_COMPOUND {
    return _emit_compound(tree, node, out, depth);
  }
  if k == SNBT_KIND_LIST {
    return _emit_list(tree, node, out, depth);
  }
  return _emit_array(tree, node, out, depth, k);
}

// `{key:value,...}`; children are emitted in document order.
fn _emit_compound(tree: &SnbtTree, node: Int, out: &mut Vec[UInt8], depth: Int) -> Result[Int, Str] {
  if depth > SNBT_MAX_DEPTH {
    return _err_int("snbt: depth exceeded");
  }
  builder.sb_push_byte(out, BYTE_OPEN_BRACE as UInt8);
  let c: Int = tree.child_count[node];
  var i = 0;
  while i < c {
    let ch = snbt_child_at(tree, node, i);
    if ch < 0 {
      return _err_int("snbt: invalid tree");
    }
    if i > 0 {
      builder.sb_push_byte(out, BYTE_COMMA as UInt8);
    }
    _emit_key(tree, ch, out);
    builder.sb_push_byte(out, BYTE_COLON as UInt8);
    let r = _emit_node(tree, ch, out, depth + 1);
    if !r.is_ok {
      return _err_int(r.error);
    }
    i = i + 1;
  }
  builder.sb_push_byte(out, BYTE_CLOSE_BRACE as UInt8);
  return _ok_int(0);
}

// `[value,...]`, any kinds.
fn _emit_list(tree: &SnbtTree, node: Int, out: &mut Vec[UInt8], depth: Int) -> Result[Int, Str] {
  if depth > SNBT_MAX_DEPTH {
    return _err_int("snbt: depth exceeded");
  }
  builder.sb_push_byte(out, BYTE_OPEN_BRACKET as UInt8);
  let c: Int = tree.child_count[node];
  var i = 0;
  while i < c {
    let ch = snbt_child_at(tree, node, i);
    if ch < 0 {
      return _err_int("snbt: invalid tree");
    }
    if i > 0 {
      builder.sb_push_byte(out, BYTE_COMMA as UInt8);
    }
    let r = _emit_node(tree, ch, out, depth + 1);
    if !r.is_ok {
      return _err_int(r.error);
    }
    i = i + 1;
  }
  builder.sb_push_byte(out, BYTE_CLOSE_BRACKET as UInt8);
  return _ok_int(0);
}

// `[B;...]` / `[I;...]` / `[L;...]`; every child is checked against the
// declared element kind.
fn _emit_array(tree: &SnbtTree, node: Int, out: &mut Vec[UInt8], depth: Int, kind: Int) -> Result[Int, Str] {
  if depth > SNBT_MAX_DEPTH {
    return _err_int("snbt: depth exceeded");
  }
  var elem = SNBT_KIND_BYTE;
  var letter = BYTE_UPPER_B;
  if kind == SNBT_KIND_INT_ARRAY {
    elem = SNBT_KIND_INT;
    letter = BYTE_UPPER_I;
  } elif kind == SNBT_KIND_LONG_ARRAY {
    elem = SNBT_KIND_LONG;
    letter = BYTE_UPPER_L;
  } elif kind != SNBT_KIND_BYTE_ARRAY {
    return _err_int("snbt: invalid tree");
  }
  builder.sb_push_byte(out, BYTE_OPEN_BRACKET as UInt8);
  builder.sb_push_byte(out, letter as UInt8);
  builder.sb_push_byte(out, BYTE_SEMICOLON as UInt8);
  let c: Int = tree.child_count[node];
  var i = 0;
  while i < c {
    let ch = snbt_child_at(tree, node, i);
    if ch < 0 {
      return _err_int("snbt: invalid tree");
    }
    let ck: Int = tree.kinds[ch];
    if ck != elem {
      return _err_int("snbt: invalid tree");
    }
    if i > 0 {
      builder.sb_push_byte(out, BYTE_COMMA as UInt8);
    }
    let r = _emit_node(tree, ch, out, depth + 1);
    if !r.is_ok {
      return _err_int(r.error);
    }
    i = i + 1;
  }
  builder.sb_push_byte(out, BYTE_CLOSE_BRACKET as UInt8);
  return _ok_int(0);
}

/// Emit `tree` in canonical form: no whitespace, keys bare when their bytes
/// are all in the documented charset (quoted otherwise), strings always
/// double-quoted, integer kinds rendered from their values with the
/// canonical suffixes `b`/`s`/`L`, float/double bodies preserved verbatim
/// with `f`/`d` appended, typed arrays as `[B;...]`/`[I;...]`/`[L;...]`.
/// Err("snbt: invalid tree") on drifted parallel vectors or an inconsistent
/// store, Err("snbt: empty tree") when there is no root.
pub fn snbt_emit(tree: &SnbtTree) -> Result[Str, Str] {
  if !_tree_well_formed(tree) {
    return _err_str("snbt: invalid tree");
  }
  let root = tree.root;
  if root < 0 {
    return _err_str("snbt: empty tree");
  }
  var out = Vec[UInt8].new();
  let r = _emit_node(tree, root, &mut out, 1);
  if !r.is_ok {
    return _err_str(r.error);
  }
  return _ok_str(builder.sb_to_str(&out));
}
