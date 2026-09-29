// XIOM -- xiom.diagrams: Graphviz DOT-subset parser and deterministic serializer
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Scope (SPEC.md is the full contract): a text-in / text-out codec for a
// Graphviz DOT subset -- `graph`/`digraph` with node statements, edge
// statements (`->` in digraphs, `--` in graphs, chains normalized to pairwise
// edges), `key=value` attribute statements, bracketed attribute lists, quoted
// strings with escapes, `#` and `//` line comments, and optional semicolons.
// Parse errors are precise: Err("<CODE>@<line>:<col>") with the catalog in
// SPEC.md. Serialization is byte-deterministic: one statement per line, a
// two-space indent, canonical `, ` attribute separators, `;` after every
// statement, LF endings and no trailing newline.
//
// Model: statements are stored in four index-aligned parallel vectors
// (`stmt_kind`, `stmt_id`, `stmt_target`, `stmt_attrs`) because Vec[StructType]
// is unsupported in this compiler. Kinds: 0 = node, 1 = edge, 2 = attr
// statement. The three text vectors hold canonical DOT text (identifiers are
// quoted and escaped exactly when needed); the add functions take raw text.
//
// v0.62.1 notes that shaped this module:
//   * Free functions only; no self methods, no inline lambdas, no Vec of
//     structs.
//   * Ok/Err for Result[DotGraph, Str] are constructed only in the leaf
//     helpers _ok_graph/_err_graph (constructing Results directly inside
//     other functions miscompiles in this compiler); Result[Str, Str] uses
//     _ok_str/_err_str leaf helpers for the same reason.
//   * Str equality and emptiness go through xiom.string.compare.str_compare
//     (BUG 17: `==` on Str values read from Vec[Str] elements lowers to a
//     pointer comparison and .len() is unreliable on them).
//   * Quoted-string bytes are collected in a Vec[UInt8] and materialized with
//     xiom.string.builder.sb_to_str; an embedded NUL is rejected with
//     E_BAD_CHAR before it can reach sb_to_str (which aborts on 0x00).
//   * Int -> Str (error positions) is a local exact decimal renderer, the
//     proven xiom.svg idiom; the conversion tower is not used.

module xiom.diagrams

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;

// --------------------------------------------------
//  Byte constants (all < 128, safe to compare with byte_at output directly)
// --------------------------------------------------

const _D_TAB: UInt8 = 9u8;
const _D_LF: UInt8 = 10u8;
const _D_CR: UInt8 = 13u8;
const _D_SPACE: UInt8 = 32u8;
const _D_DQUOTE: UInt8 = 34u8;
const _D_HASH: UInt8 = 35u8;
const _D_COMMA: UInt8 = 44u8;
const _D_DASH: UInt8 = 45u8;
const _D_SLASH: UInt8 = 47u8;
const _D_SEMI: UInt8 = 59u8;
const _D_EQ: UInt8 = 61u8;
const _D_GT: UInt8 = 62u8;
const _D_LBRACKET: UInt8 = 91u8;
const _D_BACKSLASH: UInt8 = 92u8;
const _D_RBRACKET: UInt8 = 93u8;
const _D_UNDERSCORE: UInt8 = 95u8;
const _D_N: UInt8 = 110u8;
const _D_R: UInt8 = 114u8;
const _D_T: UInt8 = 116u8;
const _D_LBRACE: UInt8 = 123u8;
const _D_RBRACE: UInt8 = 125u8;

// --------------------------------------------------
//  Token kinds
// --------------------------------------------------

const _TK_EOF: Int = 0;
const _TK_ID: Int = 1;
const _TK_STRING: Int = 2;
const _TK_LBRACE: Int = 3;
const _TK_RBRACE: Int = 4;
const _TK_LBRACKET: Int = 5;
const _TK_RBRACKET: Int = 6;
const _TK_EQ: Int = 7;
const _TK_SEMI: Int = 8;
const _TK_COMMA: Int = 9;
const _TK_ARROW: Int = 10;
const _TK_DASH: Int = 11;

// Statement kinds stored in DotGraph.stmt_kind.
const _K_NODE: Int = 0;
const _K_EDGE: Int = 1;
const _K_ATTR: Int = 2;

// --------------------------------------------------
//  Data model
// --------------------------------------------------

/// A DOT-subset graph as four index-aligned parallel vectors, one entry per
/// statement. Kind 0 = node statement (`id [attrs]`), 1 = edge statement
/// (`id -> target` or `id -- target` depending on `directed`), 2 = attribute
/// statement (`id = target`). For kinds 0 and 1, `stmt_attrs` is the canonical
/// attribute-list body without brackets (e.g. `label="a b", shape=box`); for
/// kind 2 it is "". Text vectors hold canonical DOT text: an entry is quoted
/// and escaped exactly when `_emit_id` would need to (a valid bare identifier
/// stays bare, anything else is a quoted string).
pub type DotGraph = {
  directed: Bool;
  name: Str;
  stmt_kind: Vec[Int];
  stmt_id: Vec[Str];
  stmt_target: Vec[Str];
  stmt_attrs: Vec[Str];
}

// Private scanner state of the DOT-subset lexer.
type _Lex = {
  src: Str;
  pos: Int;
  line: Int;
  col: Int;
  tok: Int;
  text: Str;
  tline: Int;
  tcol: Int;
  err: Str;
}

// --------------------------------------------------
//  Result leaf constructors (see the module header)
// --------------------------------------------------

// Ok(g) for Result[DotGraph, Str].
fn _ok_graph(g: DotGraph) -> Result[DotGraph, Str] {
  return Ok(g);
}

// Err(m) for Result[DotGraph, Str].
fn _err_graph(m: Str) -> Result[DotGraph, Str] {
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

// --------------------------------------------------
//  Small helpers
// --------------------------------------------------

// Exact decimal rendering of an Int (negatives and 0 included). Local on
// purpose: it avoids the xiom.convert / xiom.num.base conversion tower.
fn _int_to_str(n: Int) -> Str {
  if n == 0 {
    return "0";
  }
  var x = n;
  var neg = false;
  if x < 0 {
    neg = true;
  }
  if x < 0 {
    x = 0 - x;
  }
  var digits = "";
  while x != 0 {
    var d = x % 10;
    if d < 0 {
      d = 0 - d;
    }
    digits = string.str_slice("0123456789", d, d + 1) + digits;
    x = x / 10;
  }
  if neg {
    return "-" + digits;
  }
  return digits;
}

// "<CODE>@<line>:<col>" -- the error message format of this codec.
fn _err_at(code: Str, line: Int, col: Int) -> Str {
  return code + "@" + _int_to_str(line) + ":" + _int_to_str(col);
}

// True when s is not the empty string (safe on any Str value).
fn _not_empty(s: Str) -> Bool {
  return compare.str_compare(s, "") != 0;
}

fn _is_ws(b: UInt8) -> Bool {
  if b == _D_SPACE { return true; }
  if b == _D_TAB { return true; }
  if b == _D_CR { return true; }
  if b == _D_LF { return true; }
  return false;
}

// ASCII identifier byte: A-Z, a-z, 0-9, underscore.
fn _is_id_byte(b: UInt8) -> Bool {
  if b >= 65u8 && b <= 90u8 { return true; }
  if b >= 97u8 && b <= 122u8 { return true; }
  if b >= 48u8 && b <= 57u8 { return true; }
  if b == _D_UNDERSCORE { return true; }
  return false;
}

// True when s can be emitted as a bare DOT identifier.
fn _is_id_text(s: Str) -> Bool {
  let n = s.len();
  if n == 0 { return false; }
  var i = 0;
  while i < n {
    if !_is_id_byte(string.byte_at(s, i)) { return false; }
    i = i + 1;
  }
  return true;
}

// Canonical DOT rendering of one identifier / value: bare when valid,
// otherwise a quoted string with escapes. Applied exactly once per value.
fn _emit_id(s: Str) -> Str {
  if _is_id_text(s) {
    return s;
  }
  var out = Vec[UInt8].new();
  out.push(_D_DQUOTE);
  builder.sb_push_str(&mut out, dot_escape(s));
  out.push(_D_DQUOTE);
  return builder.sb_to_str(&out);
}

// Number of statements that can be serialized without an out-of-bounds read:
// the minimum length of the four parallel vectors.
fn _stmt_len(g: &DotGraph) -> Int {
  var n = g.stmt_kind.len();
  if g.stmt_id.len() < n { n = g.stmt_id.len(); }
  if g.stmt_target.len() < n { n = g.stmt_target.len(); }
  if g.stmt_attrs.len() < n { n = g.stmt_attrs.len(); }
  return n;
}

// --------------------------------------------------
//  Lexer
// --------------------------------------------------

fn _lex_new(src: Str) -> _Lex {
  return _Lex{ src: src; pos: 0; line: 1; col: 1; tok: _TK_EOF; text: ""; tline: 1; tcol: 1; err: ""; };
}

fn _set_tok(l: &mut _Lex, kind: Int, line: Int, col: Int, text: Str) {
  l.tok = kind;
  l.tline = line;
  l.tcol = col;
  l.text = text;
}

fn _lex_fail(l: &mut _Lex, code: Str) {
  l.err = _err_at(code, l.line, l.col);
}

// Advance one byte, tracking 1-based line and column.
fn _adv1(l: &mut _Lex) {
  let b = string.byte_at(l.src, l.pos);
  l.pos = l.pos + 1;
  if b == _D_LF {
    l.line = l.line + 1;
    l.col = 1;
  } else {
    l.col = l.col + 1;
  }
}

// Skip to the end of the line (the LF itself is left for the whitespace skip).
// The caller guarantees l.pos sits at '#' or at the first '/' of "//".
fn _skip_comment(l: &mut _Lex) {
  while l.pos < l.src.len() {
    if string.byte_at(l.src, l.pos) == _D_LF { break; }
    _adv1(l);
  }
}

// Scan an unquoted identifier run.
fn _scan_id(l: &mut _Lex, line: Int, col: Int) {
  let start = l.pos;
  while l.pos < l.src.len() {
    if !_is_id_byte(string.byte_at(l.src, l.pos)) { break; }
    _adv1(l);
  }
  l.text = string.str_slice(l.src, start, l.pos);
  l.tok = _TK_ID;
  l.tline = line;
  l.tcol = col;
}

// Scan a quoted string; `\` escapes `"`, `\`, `n`, `t`, `r`, anything else is
// E_BAD_ESCAPE at the backslash. A raw NUL byte is E_BAD_CHAR. An unterminated
// string is E_UNTERMINATED_STRING at the opening quote.
fn _scan_string(l: &mut _Lex, line: Int, col: Int) {
  _adv1(l);
  var out = Vec[UInt8].new();
  var closed = false;
  while l.pos < l.src.len() {
    let b = string.byte_at(l.src, l.pos);
    if b == _D_DQUOTE {
      _adv1(l);
      closed = true;
      break;
    }
    if b == _D_BACKSLASH {
      let bl = l.line;
      let bc = l.col;
      _adv1(l);
      if l.pos >= l.src.len() {
        l.err = _err_at("E_BAD_ESCAPE", bl, bc);
        return;
      }
      let e = string.byte_at(l.src, l.pos);
      if e == _D_DQUOTE {
        out.push(_D_DQUOTE);
      } elif e == _D_BACKSLASH {
        out.push(_D_BACKSLASH);
      } elif e == _D_N {
        out.push(_D_LF);
      } elif e == _D_T {
        out.push(_D_TAB);
      } elif e == _D_R {
        out.push(_D_CR);
      } else {
        l.err = _err_at("E_BAD_ESCAPE", bl, bc);
        return;
      }
      _adv1(l);
    } else {
      if b == 0u8 {
        l.err = _err_at("E_BAD_CHAR", l.line, l.col);
        return;
      }
      out.push(b);
      _adv1(l);
    }
  }
  if !closed {
    l.err = _err_at("E_UNTERMINATED_STRING", line, col);
    return;
  }
  l.text = builder.sb_to_str(&out);
  l.tok = _TK_STRING;
  l.tline = line;
  l.tcol = col;
}

// Read the next token, skipping whitespace, `#` line comments and `//` line
// comments. On a lexical error the token fields are left untouched and
// l.err is set; callers must check l.err before reading the token.
fn _lex_advance(l: &mut _Lex) {
  l.text = "";
  var skipping = true;
  while skipping {
    skipping = false;
    if l.pos >= l.src.len() {
      _set_tok(l, _TK_EOF, l.line, l.col, "");
      return;
    }
    let b = string.byte_at(l.src, l.pos);
    if _is_ws(b) {
      _adv1(l);
      skipping = true;
    } elif b == _D_HASH {
      _skip_comment(l);
      skipping = true;
    } elif b == _D_SLASH {
      if l.pos + 1 < l.src.len() && string.byte_at(l.src, l.pos + 1) == _D_SLASH {
        _skip_comment(l);
        skipping = true;
      } else {
        _lex_fail(l, "E_UNEXPECTED_CHAR");
        return;
      }
    }
  }
  let start_line = l.line;
  let start_col = l.col;
  let b = string.byte_at(l.src, l.pos);
  if b == _D_LBRACE {
    _adv1(l);
    _set_tok(l, _TK_LBRACE, start_line, start_col, "");
  } elif b == _D_RBRACE {
    _adv1(l);
    _set_tok(l, _TK_RBRACE, start_line, start_col, "");
  } elif b == _D_LBRACKET {
    _adv1(l);
    _set_tok(l, _TK_LBRACKET, start_line, start_col, "");
  } elif b == _D_RBRACKET {
    _adv1(l);
    _set_tok(l, _TK_RBRACKET, start_line, start_col, "");
  } elif b == _D_EQ {
    _adv1(l);
    _set_tok(l, _TK_EQ, start_line, start_col, "");
  } elif b == _D_SEMI {
    _adv1(l);
    _set_tok(l, _TK_SEMI, start_line, start_col, "");
  } elif b == _D_COMMA {
    _adv1(l);
    _set_tok(l, _TK_COMMA, start_line, start_col, "");
  } elif b == _D_DQUOTE {
    _scan_string(l, start_line, start_col);
  } elif _is_id_byte(b) {
    _scan_id(l, start_line, start_col);
  } elif b == _D_DASH {
    if l.pos + 1 < l.src.len() {
      let b2 = string.byte_at(l.src, l.pos + 1);
      if b2 == _D_DASH {
        _adv1(l);
        _adv1(l);
        _set_tok(l, _TK_DASH, start_line, start_col, "");
      } elif b2 == _D_GT {
        _adv1(l);
        _adv1(l);
        _set_tok(l, _TK_ARROW, start_line, start_col, "");
      } else {
        _lex_fail(l, "E_UNEXPECTED_CHAR");
      }
    } else {
      _lex_fail(l, "E_UNEXPECTED_CHAR");
    }
  } else {
    _lex_fail(l, "E_UNEXPECTED_CHAR");
  }
}

// --------------------------------------------------
//  Attribute lists
// --------------------------------------------------

// Parse one bracketed attribute list; l.tok must be _TK_LBRACKET on entry.
// Returns the canonical body without brackets ("a=b, c=\"d e\"") and consumes
// the closing ']'. On failure returns "" and sets l.err.
fn _parse_attr_list(l: &mut _Lex) -> Str {
  _lex_advance(l);
  if _not_empty(l.err) { return ""; }
  if l.tok == _TK_RBRACKET {
    _lex_advance(l);
    return "";
  }
  var out = Vec[UInt8].new();
  var wrote = false;
  var done = false;
  while !done {
    if _not_empty(l.err) { return ""; }
    if l.tok != _TK_ID && l.tok != _TK_STRING {
      l.err = _err_at("E_EXPECTED_ATTR_KEY", l.tline, l.tcol);
      return "";
    }
    let key: Str = l.text;
    _lex_advance(l);
    if _not_empty(l.err) { return ""; }
    if l.tok != _TK_EQ {
      l.err = _err_at("E_EXPECTED_EQUALS", l.tline, l.tcol);
      return "";
    }
    _lex_advance(l);
    if _not_empty(l.err) { return ""; }
    if l.tok != _TK_ID && l.tok != _TK_STRING {
      l.err = _err_at("E_EXPECTED_ATTR_VALUE", l.tline, l.tcol);
      return "";
    }
    let val: Str = l.text;
    if wrote {
      builder.sb_push_str(&mut out, ", ");
    }
    builder.sb_push_str(&mut out, _emit_id(key));
    out.push(_D_EQ);
    builder.sb_push_str(&mut out, _emit_id(val));
    wrote = true;
    _lex_advance(l);
    if _not_empty(l.err) { return ""; }
    if l.tok == _TK_COMMA || l.tok == _TK_SEMI {
      _lex_advance(l);
      if _not_empty(l.err) { return ""; }
      if l.tok == _TK_RBRACKET {
        _lex_advance(l);
        done = true;
      }
    } elif l.tok == _TK_RBRACKET {
      _lex_advance(l);
      done = true;
    } else {
      l.err = _err_at("E_EXPECTED_ATTR_SEP", l.tline, l.tcol);
      return "";
    }
  }
  return builder.sb_to_str(&out);
}

// --------------------------------------------------
//  Statements (each returns false with l.err set on failure)
// --------------------------------------------------

// Node statement: `id [attrs]?`; l.tok decides whether an attribute list
// follows. `first` is the raw identifier text.
fn _parse_node_stmt(l: &mut _Lex, g: &mut DotGraph, first: Str) -> Bool {
  var body = "";
  if l.tok == _TK_LBRACKET {
    body = _parse_attr_list(l);
    if _not_empty(l.err) { return false; }
  }
  dot_add_node(g, first, body);
  return true;
}

// Attribute statement: `id = value`; l.tok must be _TK_EQ on entry.
fn _parse_attr_stmt(l: &mut _Lex, g: &mut DotGraph, first: Str) -> Bool {
  _lex_advance(l);
  if _not_empty(l.err) { return false; }
  if l.tok != _TK_ID && l.tok != _TK_STRING {
    l.err = _err_at("E_EXPECTED_ATTR_VALUE", l.tline, l.tcol);
    return false;
  }
  let val: Str = l.text;
  dot_add_attr(g, first, val);
  _lex_advance(l);
  if _not_empty(l.err) { return false; }
  return true;
}

// Edge statement: `id (op id)+ [attrs]?`; l.tok must be _TK_ARROW or _TK_DASH
// on entry. A chain is normalized to one edge per adjacent pair, each pair
// carrying the same attribute-list body. `first` is the raw leading id.
fn _parse_edge_stmt(l: &mut _Lex, g: &mut DotGraph, first: Str) -> Bool {
  var tails = Vec[Str].new();
  var heads = Vec[Str].new();
  tails.push(first);
  var more = true;
  while more {
    let is_arrow = l.tok == _TK_ARROW;
    if is_arrow != g.directed {
      l.err = _err_at("E_EDGE_OP_MISMATCH", l.tline, l.tcol);
      return false;
    }
    _lex_advance(l);
    if _not_empty(l.err) { return false; }
    if l.tok != _TK_ID && l.tok != _TK_STRING {
      l.err = _err_at("E_EXPECTED_EDGE_TARGET", l.tline, l.tcol);
      return false;
    }
    let tgt: Str = l.text;
    heads.push(tgt);
    _lex_advance(l);
    if _not_empty(l.err) { return false; }
    if l.tok == _TK_ARROW || l.tok == _TK_DASH {
      tails.push(tgt);
    } else {
      more = false;
    }
  }
  // Parallel-vector guard: one tail per head (cannot drift as written, but
  // never index a mismatched pair).
  if tails.len() != heads.len() {
    l.err = _err_at("E_INTERNAL", l.tline, l.tcol);
    return false;
  }
  var body = "";
  if l.tok == _TK_LBRACKET {
    body = _parse_attr_list(l);
    if _not_empty(l.err) { return false; }
  }
  var j = 0;
  while j < heads.len() {
    let t: Str = tails[j];
    let h: Str = heads[j];
    dot_add_edge(g, t, h, body);
    j = j + 1;
  }
  return true;
}

// --------------------------------------------------
//  Parse
// --------------------------------------------------

/// Parse one DOT-subset document.
/// Params: text - the whole document; must not contain NUL bytes.
/// Returns: Ok(DotGraph) for a valid document; Err("<CODE>@<line>:<col>")
/// otherwise (catalog in SPEC.md section 6). Line and column are 1-based;
/// E_UNTERMINATED_STRING points at the opening quote, every other lexical
/// error at the offending byte, and EOF errors at the end-of-input position.
/// Comments: `#` and `//` run to the end of the line (inside quoted strings
/// they are data). Semicolons after statements are optional and empty `;`
/// statements are allowed. An edge chain is normalized to pairwise edges.
/// Error case: see above; a malformed document never yields a partial graph.
/// Complexity: O(text.len()); no backtracking.
pub fn dot_parse(text: Str) -> Result[DotGraph, Str] {
  var l = _lex_new(text);
  _lex_advance(&mut l);
  if _not_empty(l.err) { return _err_graph(l.err); }
  if l.tok == _TK_EOF {
    return _err_graph(_err_at("E_EMPTY_INPUT", l.tline, l.tcol));
  }
  if l.tok != _TK_ID {
    return _err_graph(_err_at("E_EXPECTED_GRAPH_KEYWORD", l.tline, l.tcol));
  }
  var directed = false;
  let kw: Str = l.text;
  if compare.str_compare(kw, "digraph") == 0 {
    directed = true;
  } elif compare.str_compare(kw, "graph") == 0 {
    directed = false;
  } else {
    return _err_graph(_err_at("E_EXPECTED_GRAPH_KEYWORD", l.tline, l.tcol));
  }
  _lex_advance(&mut l);
  if _not_empty(l.err) { return _err_graph(l.err); }
  var name = "";
  if l.tok == _TK_ID || l.tok == _TK_STRING {
    name = l.text;
    _lex_advance(&mut l);
    if _not_empty(l.err) { return _err_graph(l.err); }
  }
  if l.tok != _TK_LBRACE {
    return _err_graph(_err_at("E_EXPECTED_LBRACE", l.tline, l.tcol));
  }
  _lex_advance(&mut l);
  if _not_empty(l.err) { return _err_graph(l.err); }
  var g = dot_new(directed, name);
  var in_body = true;
  while in_body {
    if _not_empty(l.err) { return _err_graph(l.err); }
    if l.tok == _TK_EOF {
      return _err_graph(_err_at("E_EXPECTED_RBRACE", l.tline, l.tcol));
    }
    if l.tok == _TK_RBRACE {
      in_body = false;
    } elif l.tok == _TK_SEMI {
      _lex_advance(&mut l);
    } elif l.tok == _TK_ID || l.tok == _TK_STRING {
      let first: Str = l.text;
      _lex_advance(&mut l);
      if _not_empty(l.err) { return _err_graph(l.err); }
      if l.tok == _TK_EQ {
        if !_parse_attr_stmt(&mut l, &mut g, first) { return _err_graph(l.err); }
      } elif l.tok == _TK_ARROW || l.tok == _TK_DASH {
        if !_parse_edge_stmt(&mut l, &mut g, first) { return _err_graph(l.err); }
      } elif l.tok == _TK_LBRACKET || l.tok == _TK_SEMI || l.tok == _TK_RBRACE {
        if !_parse_node_stmt(&mut l, &mut g, first) { return _err_graph(l.err); }
      } else {
        return _err_graph(_err_at("E_EXPECTED_STMT_END", l.tline, l.tcol));
      }
    } else {
      return _err_graph(_err_at("E_UNEXPECTED_TOKEN", l.tline, l.tcol));
    }
  }
  _lex_advance(&mut l);
  if _not_empty(l.err) { return _err_graph(l.err); }
  if l.tok != _TK_EOF {
    return _err_graph(_err_at("E_TRAILING_INPUT", l.tline, l.tcol));
  }
  return _ok_graph(g);
}

// --------------------------------------------------
//  Escaping
// --------------------------------------------------

/// Escape the characters that are special inside a DOT quoted string.
/// Params: s - raw text.
/// Returns: s with `"` -> `\"`, `\` -> `\\`, LF -> `\n`, TAB -> `\t` and
/// CR -> `\r`; every other byte (including multi-byte UTF-8 sequences and
/// other control bytes) passes through byte-exact. NUL is outside the
/// codec's contract and must not be passed.
/// Error case: none.
/// Complexity: O(s.len()).
pub fn dot_escape(s: Str) -> Str {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < s.len() {
    let b = string.byte_at(s, i);
    if b == _D_DQUOTE {
      out.push(_D_BACKSLASH);
      out.push(_D_DQUOTE);
    } elif b == _D_BACKSLASH {
      out.push(_D_BACKSLASH);
      out.push(_D_BACKSLASH);
    } elif b == _D_LF {
      out.push(_D_BACKSLASH);
      out.push(_D_N);
    } elif b == _D_TAB {
      out.push(_D_BACKSLASH);
      out.push(_D_T);
    } elif b == _D_CR {
      out.push(_D_BACKSLASH);
      out.push(_D_R);
    } else {
      out.push(b);
    }
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}

/// Inverse of dot_escape.
/// Params: s - escaped text (as produced by dot_escape).
/// Returns: Ok(unescaped text) when every `\` starts one of `\"`, `\\`, `\n`,
/// `\t`, `\r`; Err("E_BAD_ESCAPE@<line>:<col>") at the first offending
/// backslash otherwise (a trailing backslash is offending too). A raw NUL
/// byte is Err("E_BAD_CHAR@<line>:<col>"). All other bytes pass through.
/// Error case: E_BAD_ESCAPE, E_BAD_CHAR.
/// Complexity: O(s.len()).
pub fn dot_unescape(s: Str) -> Result[Str, Str] {
  var out = Vec[UInt8].new();
  var i = 0;
  var line = 1;
  var col = 1;
  while i < s.len() {
    let b = string.byte_at(s, i);
    if b == _D_BACKSLASH {
      let sl = line;
      let sc = col;
      i = i + 1;
      col = col + 1;
      if i >= s.len() {
        return _err_str(_err_at("E_BAD_ESCAPE", sl, sc));
      }
      let e = string.byte_at(s, i);
      if e == _D_DQUOTE {
        out.push(_D_DQUOTE);
      } elif e == _D_BACKSLASH {
        out.push(_D_BACKSLASH);
      } elif e == _D_N {
        out.push(_D_LF);
      } elif e == _D_T {
        out.push(_D_TAB);
      } elif e == _D_R {
        out.push(_D_CR);
      } else {
        return _err_str(_err_at("E_BAD_ESCAPE", sl, sc));
      }
      i = i + 1;
      col = col + 1;
    } else {
      if b == 0u8 {
        return _err_str(_err_at("E_BAD_CHAR", line, col));
      }
      out.push(b);
      if b == _D_LF {
        line = line + 1;
        col = 1;
      } else {
        col = col + 1;
      }
      i = i + 1;
    }
  }
  return _ok_str(builder.sb_to_str(&out));
}

// --------------------------------------------------
//  Construction API
// --------------------------------------------------

/// Create an empty graph.
/// Params: directed - true for `digraph` (`->` edges), false for `graph`
/// (`--` edges); name - raw graph name ("" for an anonymous graph; a name
/// that is not a bare identifier is quoted and escaped on serialization).
/// Returns: a graph with no statements.
/// Error case: none.
/// Complexity: O(1).
pub fn dot_new(directed: Bool, name: Str) -> DotGraph {
  return DotGraph{
    directed: directed;
    name: name;
    stmt_kind: Vec[Int].new();
    stmt_id: Vec[Str].new();
    stmt_target: Vec[Str].new();
    stmt_attrs: Vec[Str].new();
  };
}

/// Append a node statement.
/// Params: g - the graph; id - raw node identifier; attrs - canonical
/// attribute-list body without brackets (see dot_attr_pair), "" for none.
/// The body is stored verbatim; build it with dot_attr_pair to stay canonical.
/// Returns: nothing.
/// Error case: none.
/// Complexity: amortized O(1).
pub fn dot_add_node(g: &mut DotGraph, id: Str, attrs: Str) {
  g.stmt_kind.push(_K_NODE);
  g.stmt_id.push(_emit_id(id));
  g.stmt_target.push("");
  g.stmt_attrs.push(attrs);
}

/// Append an edge statement (one directed or undirected edge, per
/// g.directed). Params: g - the graph; from, to - raw endpoint identifiers;
/// attrs - canonical attribute-list body, "" for none.
/// Returns: nothing.
/// Error case: none.
/// Complexity: amortized O(1).
pub fn dot_add_edge(g: &mut DotGraph, from: Str, to: Str, attrs: Str) {
  g.stmt_kind.push(_K_EDGE);
  g.stmt_id.push(_emit_id(from));
  g.stmt_target.push(_emit_id(to));
  g.stmt_attrs.push(attrs);
}

/// Append an attribute statement (`key = value`).
/// Params: g - the graph; key, value - raw texts; both are canonicalized
/// (quoted and escaped) exactly like identifiers.
/// Returns: nothing.
/// Error case: none.
/// Complexity: amortized O(1).
pub fn dot_add_attr(g: &mut DotGraph, key: Str, value: Str) {
  g.stmt_kind.push(_K_ATTR);
  g.stmt_id.push(_emit_id(key));
  g.stmt_target.push(_emit_id(value));
  g.stmt_attrs.push("");
}

/// One canonical attribute-list pair for the attrs parameter of
/// dot_add_node / dot_add_edge: `key=value`, both sides quoted and escaped
/// exactly when needed (e.g. `shape=box`, `label="Start Node"`).
/// Params: key, value - raw texts.
/// Returns: the pair text; join pairs with ", ".
/// Error case: none.
/// Complexity: O(key.len() + value.len()).
pub fn dot_attr_pair(key: Str, value: Str) -> Str {
  return _emit_id(key) + "=" + _emit_id(value);
}

// --------------------------------------------------
//  Accessors
// --------------------------------------------------

/// The graph name as stored (raw text). `""` for an anonymous graph.
pub fn dot_name(g: &DotGraph) -> Str {
  let n: Str = g.name;
  return n;
}

/// True for a `digraph` (edges serialize as `->`), false for a `graph`.
pub fn dot_is_directed(g: &DotGraph) -> Bool {
  return g.directed;
}

/// Number of statements.
pub fn dot_stmt_count(g: &DotGraph) -> Int {
  return g.stmt_kind.len();
}

/// True when the four parallel vectors have equal lengths. dot_serialize
/// tolerates drift by serializing the shortest prefix, but callers should
/// keep graphs consistent (all mutation through the add functions does).
pub fn dot_is_consistent(g: &DotGraph) -> Bool {
  let n = g.stmt_kind.len();
  if g.stmt_id.len() != n { return false; }
  if g.stmt_target.len() != n { return false; }
  if g.stmt_attrs.len() != n { return false; }
  return true;
}

/// Statement kind at index i: 0 = node, 1 = edge, 2 = attr statement; -1 when
/// i is out of range.
pub fn dot_stmt_kind(g: &DotGraph, i: Int) -> Int {
  if i < 0 || i >= g.stmt_kind.len() { return -1; }
  let k: Int = g.stmt_kind[i];
  return k;
}

/// Canonical `stmt_id` at index i (node id, edge tail or attr key); "" when i
/// is out of range.
pub fn dot_stmt_id(g: &DotGraph, i: Int) -> Str {
  if i < 0 || i >= g.stmt_id.len() { return ""; }
  let x: Str = g.stmt_id[i];
  return x;
}

/// Canonical `stmt_target` at index i (edge head or attr value); "" when i is
/// out of range or the statement has no target.
pub fn dot_stmt_target(g: &DotGraph, i: Int) -> Str {
  if i < 0 || i >= g.stmt_target.len() { return ""; }
  let x: Str = g.stmt_target[i];
  return x;
}

/// Canonical attribute-list body at index i (without brackets); "" when i is
/// out of range or the statement has no attribute list.
pub fn dot_stmt_attrs(g: &DotGraph, i: Int) -> Str {
  if i < 0 || i >= g.stmt_attrs.len() { return ""; }
  let x: Str = g.stmt_attrs[i];
  return x;
}

fn _count_kind(g: &DotGraph, kind: Int) -> Int {
  var n = 0;
  var i = 0;
  while i < g.stmt_kind.len() {
    let k: Int = g.stmt_kind[i];
    if k == kind {
      n = n + 1;
    }
    i = i + 1;
  }
  return n;
}

/// Number of node statements (kind 0).
pub fn dot_node_count(g: &DotGraph) -> Int {
  return _count_kind(g, _K_NODE);
}

/// Number of edge statements (kind 1).
pub fn dot_edge_count(g: &DotGraph) -> Int {
  return _count_kind(g, _K_EDGE);
}

/// Number of attribute statements (kind 2).
pub fn dot_attr_count(g: &DotGraph) -> Int {
  return _count_kind(g, _K_ATTR);
}

// --------------------------------------------------
//  Attribute lookup
// --------------------------------------------------

/// Look one attribute up in a canonical attribute-list body (the value of
/// dot_stmt_attrs, or a body built with dot_attr_pair).
/// Params: body - the body text; key - raw key text.
/// Returns: Ok(raw value text) for the first matching pair; the value is
/// unescaped. Err("E_ATTR_NOT_FOUND") when the key is absent;
/// Err("<CODE>@<line>:<col>") when the body itself is malformed
/// (E_EXPECTED_EQUALS, E_EXPECTED_ATTR_VALUE, E_EXPECTED_ATTR_SEP,
/// E_ATTR_BODY, or a lexer code).
/// Error case: E_ATTR_NOT_FOUND, E_ATTR_BODY and the parse codes above.
/// Complexity: O(body.len()).
pub fn dot_attr_get(body: Str, key: Str) -> Result[Str, Str] {
  var l = _lex_new(body);
  _lex_advance(&mut l);
  var scanning = true;
  while scanning {
    if _not_empty(l.err) { return _err_str(l.err); }
    if l.tok == _TK_EOF {
      scanning = false;
    } else {
      if l.tok != _TK_ID && l.tok != _TK_STRING {
        return _err_str(_err_at("E_ATTR_BODY", l.tline, l.tcol));
      }
      let k: Str = l.text;
      _lex_advance(&mut l);
      if _not_empty(l.err) { return _err_str(l.err); }
      if l.tok != _TK_EQ {
        return _err_str(_err_at("E_EXPECTED_EQUALS", l.tline, l.tcol));
      }
      _lex_advance(&mut l);
      if _not_empty(l.err) { return _err_str(l.err); }
      if l.tok != _TK_ID && l.tok != _TK_STRING {
        return _err_str(_err_at("E_EXPECTED_ATTR_VALUE", l.tline, l.tcol));
      }
      let v: Str = l.text;
      if compare.str_compare(k, key) == 0 {
        return _ok_str(v);
      }
      _lex_advance(&mut l);
      if _not_empty(l.err) { return _err_str(l.err); }
      if l.tok == _TK_COMMA || l.tok == _TK_SEMI {
        _lex_advance(&mut l);
      } elif l.tok == _TK_EOF {
        scanning = false;
      } else {
        return _err_str(_err_at("E_EXPECTED_ATTR_SEP", l.tline, l.tcol));
      }
    }
  }
  return _err_str("E_ATTR_NOT_FOUND");
}

// --------------------------------------------------
//  Serialization
// --------------------------------------------------

// One statement without the leading indent and the trailing ';'.
fn _emit_stmt(out: &mut Vec[UInt8], g: &DotGraph, i: Int) {
  let k: Int = g.stmt_kind[i];
  let idt: Str = g.stmt_id[i];
  builder.sb_push_str(out, idt);
  if k == _K_ATTR {
    out.push(_D_EQ);
    let val: Str = g.stmt_target[i];
    builder.sb_push_str(out, val);
    return;
  }
  if k == _K_EDGE {
    if g.directed {
      builder.sb_push_str(out, " -> ");
    } else {
      builder.sb_push_str(out, " -- ");
    }
    let tgt: Str = g.stmt_target[i];
    builder.sb_push_str(out, tgt);
  }
  let attrs: Str = g.stmt_attrs[i];
  if _not_empty(attrs) {
    out.push(_D_SPACE);
    out.push(_D_LBRACKET);
    builder.sb_push_str(out, attrs);
    out.push(_D_RBRACKET);
  }
}

/// Serialize a graph deterministically.
/// Params: g - the graph.
/// Returns: `digraph`/`graph` (+ ` name`), ` {`, then each statement on its
/// own line indented by two spaces and terminated with `;`, then `}`; LF
/// separators and no trailing newline. Statements keep stored order (parse
/// order, or insertion order for the add functions). Unknown kind values are
/// rendered as node statements; when the parallel vectors drift, only the
/// shortest prefix is emitted (see dot_is_consistent).
/// Error case: none.
/// Complexity: O(total output bytes).
pub fn dot_serialize(g: &DotGraph) -> Str {
  var out = Vec[UInt8].new();
  if g.directed {
    builder.sb_push_str(&mut out, "digraph");
  } else {
    builder.sb_push_str(&mut out, "graph");
  }
  let nm: Str = g.name;
  if _not_empty(nm) {
    out.push(_D_SPACE);
    builder.sb_push_str(&mut out, _emit_id(nm));
  }
  out.push(_D_SPACE);
  out.push(_D_LBRACE);
  let n = _stmt_len(g);
  var i = 0;
  while i < n {
    out.push(_D_LF);
    out.push(_D_SPACE);
    out.push(_D_SPACE);
    _emit_stmt(&mut out, g, i);
    out.push(_D_SEMI);
    i = i + 1;
  }
  out.push(_D_LF);
  out.push(_D_RBRACE);
  return builder.sb_to_str(&out);
}

// --------------------------------------------------
//  Error helpers
// --------------------------------------------------

/// The code part of a "<CODE>@<line>:<col>" message: everything before the
/// first '@'; a message without '@' is returned unchanged.
/// Params: msg - an error message.
/// Returns: the code.
/// Error case: none.
/// Complexity: O(msg.len()).
pub fn dot_error_code(msg: Str) -> Str {
  let at = string.index_of(msg, "@");
  match at {
    Some(i) => { return string.str_slice(msg, 0, i); },
    None => {},
  }
  return msg;
}
