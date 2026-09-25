// XIOM -- xiom.smtlib: SMT-LIB2 command/term parser and canonical emitter
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// A pure-XIOM (no FFI) reader/writer for a documented SMT-LIB2 subset. The
// reader accepts s-expressions over simple symbols, keywords (`:name`),
// numerals, decimals (kept as validated source text) and strings (doubled
// quotes plus the documented backslash escapes), with `;` line comments, and
// validates the shape of the top-level commands set-logic, set-option,
// set-info, declare-const, declare-fun, define-fun, assert, check-sat,
// get-model and exit. Term bodies are pass-through data: this package does
// not solve, type-check, infer sorts or validate SMT-LIB 2.6 semantics.
//
// The parse result is stored flat -- parallel Vec fields, no Vec[StructType]
// -- in depth-first pre-order. Every node has a kind (one of the
// smtlib_kind_* codes), a parent, a byte range in the input, its source text
// (the decoded text for strings; "" for lists), and a child range:
// node i owns the slice children[child_starts[i] .. child_starts[i] +
// child_lengths[i]] of one shared flat children array. A command index
// records the root node of every top-level command. `smtlib_emit` rebuilds
// the canonical form: one command per line, single spaces between list
// elements, strings re-escaped with `""`, `\\`, `\n`, `\r` and `\t`.
//
// Errors are deterministic `Err(Str)` values from the catalog in SPEC.md;
// every lexical and structural error carries the offending byte offset.
//
// Non-goals: no solving, no sort checking or type inference, no proofs, no
// SMT-LIB 2.6 semantic validation, no quoted symbols (`|...|`), no
// `\u{...}` escapes, no hexadecimal/binary spec constants, no s-expression
// attribute values, no macro expansion of let/forall/exists (terms are
// pass-through), no comments in the emitted output.
//
// XIOM v0.61.3 workarounds used here (same shape as the other ported codecs):
//   * free functions only, no methods on SmtDoc;
//   * Ok/Err construction is confined to the leaf helpers below (a struct
//     payload must be built through _ok_doc/_err_doc);
//   * Str values read from Vec[Str] elements are bound to typed locals and
//     compared with xiom.string.compare.str_compare (BUG 17);
//   * Vec[Int] element reads are bound to typed locals, and bytes are
//     widened with `(b as Int) & 0xFF` before Int arithmetic;
//   * bytes are accumulated in a Vec[UInt8] and materialized with
//     Str::from_utf8 (never sb_to_str, which NUL-terminates);
//   * no Vec[StructType]: SmtDoc is parallel arrays plus child ranges only.

module xiom.smtlib

use xiom.string;
use xiom.string.compare;
use xiom.string.builder;
use xiom.convert;

// --------------------------------------------------
//  Document model
// --------------------------------------------------

/// Parsed SMT-LIB2 document (flat node storage).
///
/// Nodes are stored in depth-first pre-order, one entry per node. Node 0 is
/// the root list of the first top-level command; `commands[c]` is the node
/// index of the c-th top-level command, in source order.
///
/// Per node:
///   * `kinds[i]` -- one of the `smtlib_kind_*` codes;
///   * `texts[i]` -- the source text of a symbol/keyword/numeral/decimal,
///     the decoded text of a string, "" for a list;
///   * `parents[i]` -- the containing list node, -1 for a command root;
///   * `child_starts[i]`/`child_lengths[i]` -- the child range: the direct
///     children are `children[child_starts[i] .. child_starts[i] +
///     child_lengths[i]]` (length 0 for atoms);
///   * `starts[i]`/`ends[i]` -- byte range of the node in the parsed input
///     (a list spans its opening `(` through its closing `)`).
///
/// This layout avoids `Vec[StructType]`, which this compiler does not
/// support. Use the `smtlib_*` accessors instead of the raw fields.
pub type SmtDoc = {
  kinds: Vec[Int];
  texts: Vec[Str];
  parents: Vec[Int];
  child_starts: Vec[Int];
  child_lengths: Vec[Int];
  children: Vec[Int];
  starts: Vec[Int];
  ends: Vec[Int];
  commands: Vec[Int];
}

// Internal mutable parse state: the token vectors produced by the lexer, the
// cursor, and the node vectors being built. `child_count` is provisional
// during the parse and becomes `child_lengths` in the finished document.
type _SmtParser = {
  tok_kind: Vec[Int];
  tok_text: Vec[Str];
  tok_start: Vec[Int];
  tok_end: Vec[Int];
  pos: Int;
  kinds: Vec[Int];
  texts: Vec[Str];
  parents: Vec[Int];
  child_count: Vec[Int];
  starts: Vec[Int];
  ends: Vec[Int];
  commands: Vec[Int];
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[Int, Str].
fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

// Err(m) for Result[Int, Str].
fn _err_int(m: Str) -> Result[Int, Str] {
  return Err(m);
}

// Ok(d) for Result[SmtDoc, Str].
fn _ok_doc(d: SmtDoc) -> Result[SmtDoc, Str] {
  return Ok(d);
}

// Err(m) for Result[SmtDoc, Str].
fn _err_doc(m: Str) -> Result[SmtDoc, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Kind codes and limits
// --------------------------------------------------

/// Node kind code for a list (an s-expression).
pub fn smtlib_kind_list() -> Int {
  return 0;
}

/// Node kind code for a simple symbol.
pub fn smtlib_kind_symbol() -> Int {
  return 1;
}

/// Node kind code for a keyword (source text includes the leading `:`).
pub fn smtlib_kind_keyword() -> Int {
  return 2;
}

/// Node kind code for a numeral (validated digit text, leading zeros
/// rejected).
pub fn smtlib_kind_numeral() -> Int {
  return 3;
}

/// Node kind code for a decimal (validated `<numeral>.<digits>` text).
pub fn smtlib_kind_decimal() -> Int {
  return 4;
}

/// Node kind code for a string (text is the decoded content).
pub fn smtlib_kind_string() -> Int {
  return 5;
}

/// Human-readable name of a kind code: "list", "symbol", "keyword",
/// "numeral", "decimal", "string"; "" for any other value.
pub fn smtlib_kind_name(k: Int) -> Str {
  if k == 0 { return "list"; }
  if k == 1 { return "symbol"; }
  if k == 2 { return "keyword"; }
  if k == 3 { return "numeral"; }
  if k == 4 { return "decimal"; }
  if k == 5 { return "string"; }
  return "";
}

/// Documented maximum list nesting: 128 lists on any path (the top-level
/// command list plus 127 nested lists). A list nested at depth
/// `smtlib_max_depth()` is rejected with
/// `Err("smtlib: nesting depth exceeds limit of 128")`.
pub fn smtlib_max_depth() -> Int {
  return 128;
}

// --------------------------------------------------
//  Byte constants and predicates
// --------------------------------------------------

// Internal token kind codes: the atoms reuse the node kind codes above.
const _SMT_TK_LPAREN: Int = 10;
const _SMT_TK_RPAREN: Int = 11;

const _SMT_TAB: Int = 9;
const _SMT_LF: Int = 10;
const _SMT_CR: Int = 13;
const _SMT_SPACE: Int = 32;
const _SMT_QUOTE: Int = 34;
const _SMT_LPAREN: Int = 40;
const _SMT_RPAREN: Int = 41;
const _SMT_DOT: Int = 46;
const _SMT_ZERO: Int = 48;
const _SMT_COLON: Int = 58;
const _SMT_SEMI: Int = 59;
const _SMT_BACKSLASH: Int = 92;
const _SMT_LOWER_N: Int = 110;
const _SMT_LOWER_R: Int = 114;
const _SMT_LOWER_T: Int = 116;

// True when `a` and `b` hold the same bytes; Str values read from Vec[Str]
// elements must never be compared with `==` (BUG 17).
fn _str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// Byte at `pos` of `s` widened to an Int in 0..255.
fn _byte_at(s: Str, pos: Int) -> Int {
  return (string.byte_at(s, pos) as Int) & 0xFF;
}

// ASCII whitespace byte: space, tab, LF or CR.
fn _is_ws(b: Int) -> Bool {
  return b == _SMT_SPACE || b == _SMT_TAB || b == _SMT_LF || b == _SMT_CR;
}

// ASCII digit byte: 0-9.
fn _is_digit(b: Int) -> Bool {
  return b >= 48 && b <= 57;
}

// SMT-LIB simple-symbol character: letters, digits and
// ~ ! @ $ % ^ & * _ + = < > . ? / -
fn _is_symbol_char(b: Int) -> Bool {
  if b >= 97 && b <= 122 { return true; }   // a-z
  if b >= 65 && b <= 90 { return true; }    // A-Z
  if b >= 48 && b <= 57 { return true; }    // 0-9
  if b == 126 { return true; }              // ~
  if b == 33 { return true; }               // !
  if b == 64 { return true; }               // @
  if b == 36 { return true; }               // $
  if b == 37 { return true; }               // %
  if b == 94 { return true; }               // ^
  if b == 38 { return true; }               // &
  if b == 42 { return true; }               // *
  if b == 95 { return true; }               // _
  if b == 43 { return true; }               // +
  if b == 61 { return true; }               // =
  if b == 60 { return true; }               // <
  if b == 62 { return true; }               // >
  if b == _SMT_DOT { return true; }         // .
  if b == 63 { return true; }               // ?
  if b == 47 { return true; }               // /
  return b == 45;                           // -
}

// SMT-LIB simple-symbol start character: a symbol character that is not a
// digit (numerals and decimals are lexed separately).
fn _is_symbol_start(b: Int) -> Bool {
  if _is_digit(b) { return false; }
  return _is_symbol_char(b);
}

// --------------------------------------------------
//  Lexer
// --------------------------------------------------

// Append one token to the parser's token vectors.
fn _push_tok(p: &mut _SmtParser, kind: Int, text: Str, start: Int, end: Int) {
  p.tok_kind.push(kind);
  p.tok_text.push(text);
  p.tok_start.push(start);
  p.tok_end.push(end);
}

// Byte offset where token `i` starts (-1 when out of range).
fn _tok_start(p: &_SmtParser, i: Int) -> Int {
  if i < 0 || i >= p.tok_start.len() {
    return -1;
  }
  let v: Int = p.tok_start[i];
  return v;
}

// Byte offset one past token `i` (-1 when out of range).
fn _tok_end(p: &_SmtParser, i: Int) -> Int {
  if i < 0 || i >= p.tok_end.len() {
    return -1;
  }
  let v: Int = p.tok_end[i];
  return v;
}

// Lex a keyword starting at the `:` at `at`. Returns the index one past the
// token, or Err("smtlib: malformed keyword at <colon>") when the colon is
// not followed by a non-digit symbol character.
fn _lex_keyword(p: &mut _SmtParser, text: Str, at: Int) -> Result[Int, Str] {
  let n = text.len();
  if at + 1 >= n {
    return _err_int("smtlib: malformed keyword at " + int_to_string(at));
  }
  let first = _byte_at(text, at + 1);
  if !_is_symbol_start(first) {
    return _err_int("smtlib: malformed keyword at " + int_to_string(at));
  }
  var j = at + 2;
  while j < n {
    if _is_symbol_char(_byte_at(text, j)) {
      j = j + 1;
    } else {
      break;
    }
  }
  _push_tok(p, smtlib_kind_keyword(), string.str_slice(text, at, j), at, j);
  return _ok_int(j);
}

// Lex a numeral or decimal starting at the digit at `at`. Returns the index
// one past the token. The integer part must be `0` or start with 1-9, a
// decimal point must be followed by at least one digit, and a symbol
// character may not directly follow the digits:
// Err("smtlib: malformed numeric token at <start>").
fn _lex_number(p: &mut _SmtParser, text: Str, at: Int) -> Result[Int, Str] {
  let n = text.len();
  var j = at;
  while j < n {
    if _is_digit(_byte_at(text, j)) {
      j = j + 1;
    } else {
      break;
    }
  }
  let int_len = j - at;
  if int_len > 1 && _byte_at(text, at) == _SMT_ZERO {
    return _err_int("smtlib: malformed numeric token at " + int_to_string(at));
  }
  var is_decimal = false;
  if j < n && _byte_at(text, j) == _SMT_DOT {
    let frac_start = j + 1;
    var k = frac_start;
    while k < n {
      if _is_digit(_byte_at(text, k)) {
        k = k + 1;
      } else {
        break;
      }
    }
    if k == frac_start {
      return _err_int("smtlib: malformed numeric token at " + int_to_string(at));
    }
    is_decimal = true;
    j = k;
  }
  if j < n && _is_symbol_char(_byte_at(text, j)) {
    return _err_int("smtlib: malformed numeric token at " + int_to_string(at));
  }
  if is_decimal {
    _push_tok(p, smtlib_kind_decimal(), string.str_slice(text, at, j), at, j);
  } else {
    _push_tok(p, smtlib_kind_numeral(), string.str_slice(text, at, j), at, j);
  }
  return _ok_int(j);
}

// Lex a string literal starting at the opening quote at `at`. Returns the
// index one past the closing quote. `""` decodes to one quote; `\\`, `\"`,
// `\n`, `\r` and `\t` decode to backslash, quote, LF, CR and TAB; any other
// backslash sequence is Err("smtlib: invalid escape at <backslash>"), an
// unterminated literal (including a trailing backslash) is
// Err("smtlib: unterminated string at <opening quote>"), and a raw NUL byte
// is Err("smtlib: unexpected byte at <byte>").
fn _lex_string(p: &mut _SmtParser, text: Str, at: Int) -> Result[Int, Str] {
  let n = text.len();
  var sb = Vec[UInt8].new();
  var j = at + 1;
  var closed = false;
  while j < n {
    let c = _byte_at(text, j);
    if c == _SMT_QUOTE {
      if j + 1 < n && _byte_at(text, j + 1) == _SMT_QUOTE {
        sb.push(34u8);
        j = j + 2;
      } else {
        closed = true;
        j = j + 1;
        break;
      }
    } elif c == _SMT_BACKSLASH {
      if j + 1 >= n {
        return _err_int("smtlib: unterminated string at " + int_to_string(at));
      }
      let e = _byte_at(text, j + 1);
      if e == _SMT_QUOTE {
        sb.push(34u8);
        j = j + 2;
      } elif e == _SMT_BACKSLASH {
        sb.push(92u8);
        j = j + 2;
      } elif e == _SMT_LOWER_N {
        sb.push(10u8);
        j = j + 2;
      } elif e == _SMT_LOWER_R {
        sb.push(13u8);
        j = j + 2;
      } elif e == _SMT_LOWER_T {
        sb.push(9u8);
        j = j + 2;
      } else {
        return _err_int("smtlib: invalid escape at " + int_to_string(j));
      }
    } elif c == 0 {
      return _err_int("smtlib: unexpected byte at " + int_to_string(j));
    } else {
      sb.push(c as UInt8);
      j = j + 1;
    }
  }
  if !closed {
    return _err_int("smtlib: unterminated string at " + int_to_string(at));
  }
  let decoded = Str::from_utf8(sb);
  _push_tok(p, smtlib_kind_string(), decoded, at, j);
  return _ok_int(j);
}

// Scan `text` into the parser's token vectors. Returns the token count.
// Whitespace and `;` comments are skipped; `(` and `)` are single tokens;
// atoms are classified as symbol, keyword, numeral, decimal or string.
fn _lex_into(p: &mut _SmtParser, text: Str) -> Result[Int, Str] {
  let n = text.len();
  var i = 0;
  while i < n {
    let b = _byte_at(text, i);
    if _is_ws(b) {
      i = i + 1;
    } elif b == _SMT_LPAREN {
      _push_tok(p, _SMT_TK_LPAREN, "(", i, i + 1);
      i = i + 1;
    } elif b == _SMT_RPAREN {
      _push_tok(p, _SMT_TK_RPAREN, ")", i, i + 1);
      i = i + 1;
    } elif b == _SMT_SEMI {
      while i < n {
        let c = _byte_at(text, i);
        if c == _SMT_LF || c == _SMT_CR {
          break;
        }
        i = i + 1;
      }
    } elif b == _SMT_QUOTE {
      let r = _lex_string(p, text, i);
      if !r.is_ok {
        return _err_int(r.error);
      }
      i = r.value;
    } elif b == _SMT_COLON {
      let r = _lex_keyword(p, text, i);
      if !r.is_ok {
        return _err_int(r.error);
      }
      i = r.value;
    } elif _is_digit(b) {
      let r = _lex_number(p, text, i);
      if !r.is_ok {
        return _err_int(r.error);
      }
      i = r.value;
    } elif _is_symbol_start(b) {
      var j = i + 1;
      while j < n {
        if _is_symbol_char(_byte_at(text, j)) {
          j = j + 1;
        } else {
          break;
        }
      }
      _push_tok(p, smtlib_kind_symbol(), string.str_slice(text, i, j), i, j);
      i = j;
    } else {
      return _err_int("smtlib: unexpected byte at " + int_to_string(i));
    }
  }
  return _ok_int(p.tok_kind.len());
}

// --------------------------------------------------
//  Tree builder
// --------------------------------------------------

// Append one node and return its index; parent is -1 for a command root.
fn _push_node(p: &mut _SmtParser, kind: Int, text: Str, parent: Int, start: Int) -> Int {
  let idx = p.kinds.len();
  p.kinds.push(kind);
  p.texts.push(text);
  p.parents.push(parent);
  p.child_count.push(0);
  p.starts.push(start);
  p.ends.push(start);
  return idx;
}

// Parse the list whose `(` is the token at p.pos, consuming it. Returns the
// list node index, or Err("smtlib: unbalanced parenthesis at <open>") when
// the closing `)` is missing and Err("smtlib: nesting depth exceeds limit
// of 128") past the documented nesting limit.
fn _parse_list(p: &mut _SmtParser, depth: Int, parent: Int) -> Result[Int, Str] {
  if depth >= smtlib_max_depth() {
    return _err_int("smtlib: nesting depth exceeds limit of " + int_to_string(smtlib_max_depth()));
  }
  let open_pos = _tok_start(p, p.pos);
  let idx = _push_node(p, smtlib_kind_list(), "", parent, open_pos);
  p.pos = p.pos + 1;
  let n = p.tok_kind.len();
  while p.pos < n {
    let tk: Int = p.tok_kind[p.pos];
    if tk == _SMT_TK_RPAREN {
      p.ends[idx] = _tok_end(p, p.pos);
      p.pos = p.pos + 1;
      return _ok_int(idx);
    }
    let cr = _parse_form(p, depth + 1, idx);
    if !cr.is_ok {
      return _err_int(cr.error);
    }
    let child = cr.value;
    let cc: Int = p.child_count[idx];
    p.child_count[idx] = cc + 1;
  }
  return _err_int("smtlib: unbalanced parenthesis at " + int_to_string(open_pos));
}

// Parse one form at p.pos: a nested list or a single atom token. Returns the
// node index.
fn _parse_form(p: &mut _SmtParser, depth: Int, parent: Int) -> Result[Int, Str] {
  let tk: Int = p.tok_kind[p.pos];
  if tk == _SMT_TK_LPAREN {
    return _parse_list(p, depth, parent);
  }
  if tk == _SMT_TK_RPAREN {
    return _err_int("smtlib: unbalanced parenthesis at " + int_to_string(_tok_start(p, p.pos)));
  }
  let text: Str = p.tok_text[p.pos];
  let start: Int = p.tok_start[p.pos];
  let end: Int = p.tok_end[p.pos];
  let idx = _push_node(p, tk, text, parent, start);
  p.ends[idx] = end;
  p.pos = p.pos + 1;
  return _ok_int(idx);
}

// Parse every top-level command, recording its root node in p.commands.
// Returns the command count.
fn _parse_all(p: &mut _SmtParser) -> Result[Int, Str] {
  let n = p.tok_kind.len();
  while p.pos < n {
    let tk: Int = p.tok_kind[p.pos];
    if tk == _SMT_TK_LPAREN {
      let r = _parse_list(p, 0, -1);
      if !r.is_ok {
        return _err_int(r.error);
      }
      let node = r.value;
      let cc: Int = p.child_count[node];
      if cc == 0 {
        return _err_int("smtlib: empty command at " + int_to_string(_p_node_start(p, node)));
      }
      p.commands.push(node);
    } elif tk == _SMT_TK_RPAREN {
      return _err_int("smtlib: unbalanced parenthesis at " + int_to_string(_tok_start(p, p.pos)));
    } else {
      return _err_int("smtlib: expected command at " + int_to_string(_tok_start(p, p.pos)));
    }
  }
  return _ok_int(p.commands.len());
}

// Start offset of parser node `i` (-1 when out of range).
fn _p_node_start(p: &_SmtParser, i: Int) -> Int {
  if i < 0 || i >= p.starts.len() {
    return -1;
  }
  let v: Int = p.starts[i];
  return v;
}

// --------------------------------------------------
//  Document assembly
// --------------------------------------------------

// Move the parse state into the public document type, building the flat
// child ranges with a counting sort by parent: node i owns the slice
// children[child_starts[i] .. child_starts[i] + child_lengths[i]].
fn _finish(p: _SmtParser) -> SmtDoc {
  let n = p.kinds.len();
  var child_starts = Vec[Int].new();
  var total = 0;
  var i = 0;
  while i < n {
    child_starts.push(total);
    let c: Int = p.child_count[i];
    total = total + c;
    i = i + 1;
  }
  var cursor = Vec[Int].new();
  i = 0;
  while i < n {
    let s: Int = child_starts[i];
    cursor.push(s);
    i = i + 1;
  }
  var children = Vec[Int].new();
  while children.len() < total {
    children.push(0);
  }
  i = 0;
  while i < n {
    let par: Int = p.parents[i];
    if par >= 0 && par < n {
      let at: Int = cursor[par];
      if at >= 0 && at < children.len() {
        children[at] = i;
        cursor[par] = at + 1;
      }
    }
    i = i + 1;
  }
  return SmtDoc{
    kinds: p.kinds;
    texts: p.texts;
    parents: p.parents;
    child_starts: child_starts;
    child_lengths: p.child_count;
    children: children;
    starts: p.starts;
    ends: p.ends;
    commands: p.commands;
  };
}

// --------------------------------------------------
//  Document-side read helpers
// --------------------------------------------------

// True when `i` addresses a node of `doc`.
fn _node_valid(doc: &SmtDoc, i: Int) -> Bool {
  if i < 0 { return false; }
  if i >= doc.kinds.len() { return false; }
  if i >= doc.texts.len() { return false; }
  if i >= doc.parents.len() { return false; }
  if i >= doc.child_starts.len() { return false; }
  if i >= doc.child_lengths.len() { return false; }
  if i >= doc.starts.len() { return false; }
  if i >= doc.ends.len() { return false; }
  return true;
}

// Kind code of node `i`, or -1 when out of range.
fn _d_kind(doc: &SmtDoc, i: Int) -> Int {
  if !_node_valid(doc, i) {
    return -1;
  }
  let v: Int = doc.kinds[i];
  return v;
}

// Text of node `i`, or "" when out of range.
fn _d_text(doc: &SmtDoc, i: Int) -> Str {
  if !_node_valid(doc, i) {
    return "";
  }
  let s: Str = doc.texts[i];
  return s;
}

// Direct child count of node `i`, or 0 when out of range.
fn _d_child_count(doc: &SmtDoc, i: Int) -> Int {
  if !_node_valid(doc, i) {
    return 0;
  }
  let v: Int = doc.child_lengths[i];
  return v;
}

// n-th direct child (0-based) of node `i`, or -1 out of range.
fn _d_child(doc: &SmtDoc, i: Int, n: Int) -> Int {
  if n < 0 {
    return -1;
  }
  let cc = _d_child_count(doc, i);
  if n >= cc {
    return -1;
  }
  let base: Int = doc.child_starts[i];
  let at = base + n;
  if at < 0 || at >= doc.children.len() {
    return -1;
  }
  let v: Int = doc.children[at];
  return v;
}

// Start offset of node `i`, or -1 when out of range.
fn _d_start_of(doc: &SmtDoc, i: Int) -> Int {
  if !_node_valid(doc, i) {
    return -1;
  }
  let v: Int = doc.starts[i];
  return v;
}

// Argument count of a command node: children minus the head, floored at 0.
fn _d_arg_count(doc: &SmtDoc, node: Int) -> Int {
  let cc = _d_child_count(doc, node);
  if cc <= 0 {
    return 0;
  }
  return cc - 1;
}

// --------------------------------------------------
//  Shape predicates
// --------------------------------------------------

// A sort is a symbol or a non-empty list (sort contents are pass-through).
fn _d_is_sort(doc: &SmtDoc, i: Int) -> Bool {
  let k = _d_kind(doc, i);
  if k == smtlib_kind_symbol() {
    return true;
  }
  if k == smtlib_kind_list() {
    return _d_child_count(doc, i) >= 1;
  }
  return false;
}

// A term is a non-empty list or any atom other than a keyword.
fn _d_is_term(doc: &SmtDoc, i: Int) -> Bool {
  let k = _d_kind(doc, i);
  if k == smtlib_kind_list() {
    return _d_child_count(doc, i) >= 1;
  }
  if k == smtlib_kind_keyword() {
    return false;
  }
  if k < 0 {
    return false;
  }
  return true;
}

// An attribute value: symbol, numeral, decimal or string (no keywords, no
// lists).
fn _d_is_value_atom(doc: &SmtDoc, i: Int) -> Bool {
  let k = _d_kind(doc, i);
  if k == smtlib_kind_symbol() { return true; }
  if k == smtlib_kind_numeral() { return true; }
  if k == smtlib_kind_decimal() { return true; }
  if k == smtlib_kind_string() { return true; }
  return false;
}

// --------------------------------------------------
//  Command validation
// --------------------------------------------------

// "argument" for one, "arguments" otherwise, for arity messages.
fn _args_word(n: Int) -> Str {
  if n == 1 {
    return "argument";
  }
  return "arguments";
}

// Err("smtlib: <cmd> expects <want> <argument(s)>, got <got>").
fn _err_arity(cmd: Str, want: Int, got: Int) -> Result[Int, Str] {
  return _err_int("smtlib: " + cmd + " expects " + int_to_string(want) + " " + _args_word(want) + ", got " + int_to_string(got));
}

// Err("smtlib: <cmd> expects <what> at <pos>").
fn _err_expect(cmd: Str, what: Str, pos: Int) -> Result[Int, Str] {
  return _err_int("smtlib: " + cmd + " expects " + what + " at " + int_to_string(pos));
}

// `(check-sat)`, `(get-model)`, `(exit)` and any other zero-argument command.
fn _validate_no_args(doc: &SmtDoc, node: Int, cmd: Str) -> Result[Int, Str] {
  let got = _d_arg_count(doc, node);
  if got != 0 {
    return _err_arity(cmd, 0, got);
  }
  return _ok_int(0);
}

// `(set-logic <symbol>)`.
fn _validate_set_logic(doc: &SmtDoc, node: Int) -> Result[Int, Str] {
  let got = _d_arg_count(doc, node);
  if got != 1 {
    return _err_arity("set-logic", 1, got);
  }
  let a = _d_child(doc, node, 1);
  if _d_kind(doc, a) != smtlib_kind_symbol() {
    return _err_expect("set-logic", "a symbol", _d_start_of(doc, a));
  }
  return _ok_int(0);
}

// `(set-option <keyword> <atom>)` and `(set-info <keyword> <atom>)`.
fn _validate_attr(doc: &SmtDoc, node: Int, cmd: Str) -> Result[Int, Str] {
  let got = _d_arg_count(doc, node);
  if got != 2 {
    return _err_arity(cmd, 2, got);
  }
  let key = _d_child(doc, node, 1);
  if _d_kind(doc, key) != smtlib_kind_keyword() {
    return _err_expect(cmd, "a keyword", _d_start_of(doc, key));
  }
  let val = _d_child(doc, node, 2);
  if !_d_is_value_atom(doc, val) {
    return _err_expect(cmd, "an atom", _d_start_of(doc, val));
  }
  return _ok_int(0);
}

// `(declare-const <symbol> <sort>)`.
fn _validate_declare_const(doc: &SmtDoc, node: Int) -> Result[Int, Str] {
  let got = _d_arg_count(doc, node);
  if got != 2 {
    return _err_arity("declare-const", 2, got);
  }
  let name = _d_child(doc, node, 1);
  if _d_kind(doc, name) != smtlib_kind_symbol() {
    return _err_expect("declare-const", "a symbol", _d_start_of(doc, name));
  }
  let sort = _d_child(doc, node, 2);
  if !_d_is_sort(doc, sort) {
    return _err_expect("declare-const", "a sort", _d_start_of(doc, sort));
  }
  return _ok_int(0);
}

// `(declare-fun <symbol> (<sort> ...) <sort>)`.
fn _validate_declare_fun(doc: &SmtDoc, node: Int) -> Result[Int, Str] {
  let got = _d_arg_count(doc, node);
  if got != 3 {
    return _err_arity("declare-fun", 3, got);
  }
  let name = _d_child(doc, node, 1);
  if _d_kind(doc, name) != smtlib_kind_symbol() {
    return _err_expect("declare-fun", "a symbol", _d_start_of(doc, name));
  }
  let params = _d_child(doc, node, 2);
  if _d_kind(doc, params) != smtlib_kind_list() {
    return _err_expect("declare-fun", "a parameter list", _d_start_of(doc, params));
  }
  let pc = _d_child_count(doc, params);
  var i = 0;
  while i < pc {
    let item = _d_child(doc, params, i);
    if !_d_is_sort(doc, item) {
      return _err_expect("declare-fun", "a sort", _d_start_of(doc, item));
    }
    i = i + 1;
  }
  let ret = _d_child(doc, node, 3);
  if !_d_is_sort(doc, ret) {
    return _err_expect("declare-fun", "a sort", _d_start_of(doc, ret));
  }
  return _ok_int(0);
}

// `(define-fun <symbol> ((<name> <sort>) ...) <sort> <term>)`.
fn _validate_define_fun(doc: &SmtDoc, node: Int) -> Result[Int, Str] {
  let got = _d_arg_count(doc, node);
  if got != 4 {
    return _err_arity("define-fun", 4, got);
  }
  let name = _d_child(doc, node, 1);
  if _d_kind(doc, name) != smtlib_kind_symbol() {
    return _err_expect("define-fun", "a symbol", _d_start_of(doc, name));
  }
  let params = _d_child(doc, node, 2);
  if _d_kind(doc, params) != smtlib_kind_list() {
    return _err_expect("define-fun", "a parameter list", _d_start_of(doc, params));
  }
  let pc = _d_child_count(doc, params);
  var i = 0;
  while i < pc {
    let item = _d_child(doc, params, i);
    if _d_kind(doc, item) != smtlib_kind_list() || _d_child_count(doc, item) != 2 {
      return _err_expect("define-fun", "a sorted variable", _d_start_of(doc, item));
    }
    let pname = _d_child(doc, item, 0);
    if _d_kind(doc, pname) != smtlib_kind_symbol() {
      return _err_expect("define-fun", "a symbol", _d_start_of(doc, pname));
    }
    let psort = _d_child(doc, item, 1);
    if !_d_is_sort(doc, psort) {
      return _err_expect("define-fun", "a sort", _d_start_of(doc, psort));
    }
    i = i + 1;
  }
  let ret = _d_child(doc, node, 3);
  if !_d_is_sort(doc, ret) {
    return _err_expect("define-fun", "a sort", _d_start_of(doc, ret));
  }
  let body = _d_child(doc, node, 4);
  if !_d_is_term(doc, body) {
    return _err_expect("define-fun", "a term", _d_start_of(doc, body));
  }
  return _ok_int(0);
}

// `(assert <term>)`.
fn _validate_assert(doc: &SmtDoc, node: Int) -> Result[Int, Str] {
  let got = _d_arg_count(doc, node);
  if got != 1 {
    return _err_arity("assert", 1, got);
  }
  let body = _d_child(doc, node, 1);
  if !_d_is_term(doc, body) {
    return _err_expect("assert", "a term", _d_start_of(doc, body));
  }
  return _ok_int(0);
}

// Dispatch one command node on its head symbol.
fn _validate_one(doc: &SmtDoc, node: Int) -> Result[Int, Str] {
  let head = _d_child(doc, node, 0);
  if head < 0 {
    return _err_int("smtlib: empty command at " + int_to_string(_d_start_of(doc, node)));
  }
  if _d_kind(doc, head) != smtlib_kind_symbol() {
    return _err_int("smtlib: misplaced token at " + int_to_string(_d_start_of(doc, head)));
  }
  let name: Str = _d_text(doc, head);
  if _str_eq(name, "set-logic") {
    return _validate_set_logic(doc, node);
  }
  if _str_eq(name, "set-option") {
    return _validate_attr(doc, node, "set-option");
  }
  if _str_eq(name, "set-info") {
    return _validate_attr(doc, node, "set-info");
  }
  if _str_eq(name, "declare-const") {
    return _validate_declare_const(doc, node);
  }
  if _str_eq(name, "declare-fun") {
    return _validate_declare_fun(doc, node);
  }
  if _str_eq(name, "define-fun") {
    return _validate_define_fun(doc, node);
  }
  if _str_eq(name, "assert") {
    return _validate_assert(doc, node);
  }
  if _str_eq(name, "check-sat") {
    return _validate_no_args(doc, node, "check-sat");
  }
  if _str_eq(name, "get-model") {
    return _validate_no_args(doc, node, "get-model");
  }
  if _str_eq(name, "exit") {
    return _validate_no_args(doc, node, "exit");
  }
  return _err_int("smtlib: unknown command '" + name + "' at " + int_to_string(_d_start_of(doc, head)));
}

// Validate every command of `doc` in source order.
fn _validate_commands(doc: &SmtDoc) -> Result[Int, Str] {
  var c = 0;
  while c < doc.commands.len() {
    let node: Int = doc.commands[c];
    let r = _validate_one(doc, node);
    if !r.is_ok {
      return _err_int(r.error);
    }
    c = c + 1;
  }
  return _ok_int(doc.commands.len());
}

// --------------------------------------------------
//  Public parsing API
// --------------------------------------------------

/// Parse `text` into a flat SMT-LIB2 document.
/// Params: text - the whole document as one Str (UTF-8 bytes pass through;
/// only structural ASCII bytes are interpreted).
/// Returns: Ok(doc) with one node per symbol/keyword/numeral/decimal/string
/// and one per list, in depth-first pre-order, plus the command index. An
/// empty or comments-only document yields a document with zero nodes and
/// zero commands (not an error).
/// Error case: Err("smtlib: ...") on the first lexical or shape error; the
/// catalog (SPEC.md section 7) covers unexpected byte, malformed keyword,
/// malformed numeric token, invalid escape, unterminated string, unbalanced
/// parenthesis, expected command, empty command, unknown command, misplaced
/// token, nesting depth, command arity and command argument kind.
/// Complexity: O(text) time; the token and node vectors are proportional to
/// the token count.
pub fn smtlib_parse(text: Str) -> Result[SmtDoc, Str] {
  var p = _SmtParser{
    tok_kind: Vec[Int].new();
    tok_text: Vec[Str].new();
    tok_start: Vec[Int].new();
    tok_end: Vec[Int].new();
    pos: 0;
    kinds: Vec[Int].new();
    texts: Vec[Str].new();
    parents: Vec[Int].new();
    child_count: Vec[Int].new();
    starts: Vec[Int].new();
    ends: Vec[Int].new();
    commands: Vec[Int].new();
  };
  let lr = _lex_into(&mut p, text);
  if !lr.is_ok {
    return _err_doc(lr.error);
  }
  let pr = _parse_all(&mut p);
  if !pr.is_ok {
    return _err_doc(pr.error);
  }
  let doc = _finish(p);
  let vr = _validate_commands(&doc);
  if !vr.is_ok {
    return _err_doc(vr.error);
  }
  return _ok_doc(doc);
}

// --------------------------------------------------
//  Public accessors
// --------------------------------------------------

/// Number of nodes in the document.
/// Complexity: O(1).
pub fn smtlib_node_count(doc: &SmtDoc) -> Int {
  return doc.kinds.len();
}

/// Number of top-level commands in the document (the emitter writes exactly
/// this many lines).
/// Complexity: O(1).
pub fn smtlib_command_count(doc: &SmtDoc) -> Int {
  return doc.commands.len();
}

/// Kind code of node `i` (one of the `smtlib_kind_*` values), or -1 when `i`
/// is outside [0, smtlib_node_count(doc)).
/// Complexity: O(1).
pub fn smtlib_kind(doc: &SmtDoc, i: Int) -> Int {
  return _d_kind(doc, i);
}

/// Text of node `i`: source text for symbols, keywords, numerals and
/// decimals; decoded content for strings; "" for lists and for any
/// out-of-range `i` (check the kind to tell an empty string apart).
/// Complexity: O(1).
pub fn smtlib_node_text(doc: &SmtDoc, i: Int) -> Str {
  return _d_text(doc, i);
}

/// Text of node `i` when it is a symbol, else "" (including out-of-range
/// indices).
/// Complexity: O(1).
pub fn smtlib_symbol_text(doc: &SmtDoc, i: Int) -> Str {
  if _d_kind(doc, i) != smtlib_kind_symbol() {
    return "";
  }
  return _d_text(doc, i);
}

/// Index of the list containing node `i`, or -1 for a command root and for
/// out-of-range indices.
/// Complexity: O(1).
pub fn smtlib_parent(doc: &SmtDoc, i: Int) -> Int {
  if !_node_valid(doc, i) {
    return -1;
  }
  let v: Int = doc.parents[i];
  return v;
}

/// Number of direct children of node `i`, or 0 for an atom and for
/// out-of-range indices.
/// Complexity: O(1).
pub fn smtlib_child_count(doc: &SmtDoc, i: Int) -> Int {
  return _d_child_count(doc, i);
}

/// Index of the first entry of node `i`'s child range in
/// `SmtDoc.children`, or -1 for an out-of-range node.
/// Complexity: O(1).
pub fn smtlib_child_start(doc: &SmtDoc, i: Int) -> Int {
  if !_node_valid(doc, i) {
    return -1;
  }
  let v: Int = doc.child_starts[i];
  return v;
}

/// Index of the n-th direct child of node `i` (0-based), or -1 when `i` is
/// not a list or `n` is outside [0, smtlib_child_count(doc, i)).
/// Complexity: O(1).
pub fn smtlib_child(doc: &SmtDoc, i: Int, n: Int) -> Int {
  return _d_child(doc, i, n);
}

/// Byte offset of the first byte of node `i` in the parsed input, or -1 when
/// out of range.
/// Complexity: O(1).
pub fn smtlib_node_start(doc: &SmtDoc, i: Int) -> Int {
  if !_node_valid(doc, i) {
    return -1;
  }
  let v: Int = doc.starts[i];
  return v;
}

/// Byte offset one past the last byte of node `i` in the parsed input, or -1
/// when out of range.
/// Complexity: O(1).
pub fn smtlib_node_end(doc: &SmtDoc, i: Int) -> Int {
  if !_node_valid(doc, i) {
    return -1;
  }
  let v: Int = doc.ends[i];
  return v;
}

/// Root node index of command `c`, or -1 when `c` is out of range.
/// Complexity: O(1).
pub fn smtlib_command_node(doc: &SmtDoc, c: Int) -> Int {
  if c < 0 || c >= doc.commands.len() {
    return -1;
  }
  let v: Int = doc.commands[c];
  return v;
}

/// Head node index (the command symbol) of command `c`, or -1 when `c` is
/// out of range.
/// Complexity: O(1).
pub fn smtlib_command_head(doc: &SmtDoc, c: Int) -> Int {
  let node = smtlib_command_node(doc, c);
  if node < 0 {
    return -1;
  }
  return _d_child(doc, node, 0);
}

/// Head symbol text of command `c`, or "" when `c` is out of range.
/// Complexity: O(1).
pub fn smtlib_command_name(doc: &SmtDoc, c: Int) -> Str {
  let head = smtlib_command_head(doc, c);
  if head < 0 {
    return "";
  }
  return smtlib_symbol_text(doc, head);
}

/// Number of arguments of command `c` (its head symbol excluded), or 0 when
/// `c` is out of range.
/// Complexity: O(1).
pub fn smtlib_command_arg_count(doc: &SmtDoc, c: Int) -> Int {
  let node = smtlib_command_node(doc, c);
  if node < 0 {
    return 0;
  }
  return _d_arg_count(doc, node);
}

/// Node index of argument `a` (0-based, the head symbol excluded) of command
/// `c`, or -1 when either index is out of range.
/// Complexity: O(1).
pub fn smtlib_command_arg(doc: &SmtDoc, c: Int, a: Int) -> Int {
  if a < 0 {
    return -1;
  }
  let node = smtlib_command_node(doc, c);
  if node < 0 {
    return -1;
  }
  if a >= _d_arg_count(doc, node) {
    return -1;
  }
  return _d_child(doc, node, a + 1);
}

// --------------------------------------------------
//  Canonical emitter
// --------------------------------------------------

// Append the decoded text of a string node to `out`, re-escaped canonically:
// `"` -> `""`, `\` -> `\\`, LF -> `\n`, CR -> `\r`, TAB -> `\t`; every other
// byte is copied verbatim.
fn _emit_string(s: Str, out: &mut Vec[UInt8]) {
  let n = s.len();
  var i = 0;
  while i < n {
    let b = _byte_at(s, i);
    if b == _SMT_QUOTE {
      out.push(34u8);
      out.push(34u8);
    } elif b == _SMT_BACKSLASH {
      out.push(92u8);
      out.push(92u8);
    } elif b == _SMT_LF {
      out.push(92u8);
      out.push(110u8);
    } elif b == _SMT_CR {
      out.push(92u8);
      out.push(114u8);
    } elif b == _SMT_TAB {
      out.push(92u8);
      out.push(116u8);
    } else {
      out.push(b as UInt8);
    }
    i = i + 1;
  }
}

// Append node `i` and its subtree to `out` in canonical form: lists are
// parenthesized with single spaces between children, strings are quoted and
// re-escaped, other atoms are copied verbatim.
fn _emit_node(doc: &SmtDoc, i: Int, out: &mut Vec[UInt8]) {
  if !_node_valid(doc, i) {
    return;
  }
  let k: Int = doc.kinds[i];
  if k == smtlib_kind_list() {
    out.push(40u8);
    let cc = _d_child_count(doc, i);
    var n = 0;
    while n < cc {
      if n > 0 {
        out.push(32u8);
      }
      let child = _d_child(doc, i, n);
      _emit_node(doc, child, out);
      n = n + 1;
    }
    out.push(41u8);
    return;
  }
  if k == smtlib_kind_string() {
    out.push(34u8);
    let s: Str = doc.texts[i];
    _emit_string(s, out);
    out.push(34u8);
    return;
  }
  let s: Str = doc.texts[i];
  builder.sb_push_str(out, s);
}

/// Serialize a parsed document back to canonical SMT-LIB2 text: one command
/// per line (LF separated, no trailing newline), list elements separated by
/// single spaces, string content re-escaped (`""`, `\\`, `\n`, `\r`, `\t`)
/// and comments dropped. For any document produced by `smtlib_parse`,
/// re-parsing the output yields the same node kinds, texts, parent links and
/// child counts, and emitting again yields the identical text (the emitter
/// is idempotent). An empty document yields "".
/// Complexity: O(total node text length).
pub fn smtlib_emit(doc: &SmtDoc) -> Str {
  var out = Vec[UInt8].new();
  var c = 0;
  while c < doc.commands.len() {
    if c > 0 {
      out.push(10u8);
    }
    let node: Int = doc.commands[c];
    _emit_node(doc, node, &mut out);
    c = c + 1;
  }
  return Str::from_utf8(out);
}
