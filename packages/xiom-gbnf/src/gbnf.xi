// XIOM -- xiom.gbnf: GBNF (llama.cpp grammar) parser, validator and canonical emitter
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// A small, dependency-free codec for the llama.cpp GBNF grammar format.
// Supported subset: `name ::= alternates` rules; `|` alternation; sequences;
// `"..."` string literals with \" \\ \n \t \r and \xNN escapes; character
// classes `[a-z]` / `[^...]` with `-` ranges and the same escapes plus
// \] \- \^; `*` `+` `?` repetition; `( )` grouping; rule references; `#`
// comments; free whitespace and newlines. See SPEC.md for the exact grammar,
// the error catalog and the non-goals (no \uNNNN escapes, no {m,n} bounds,
// no left-recursion analysis, no sample generation or inference). \x00 is
// rejected inside string literals because XIOM Str cannot carry a NUL byte;
// it is accepted inside character classes, whose canonical spelling is ASCII.
//
// Model: a grammar is an ordered rule list (parallel `names`/`roots`) over one
// flat expression-tree pool shared by every rule. Nodes are stored in postfix
// order (children before parents); every internal node owns a slice of the
// shared `node_children` index pool. Vec[StructType] is unsupported in this
// compiler, so the tree is eight parallel vectors instead of node objects.
// Parsing validates structure, duplicate rules and unresolved references;
// gbnf_emit renders the parsed grammar back to canonical GBNF text so
// parse -> emit -> parse is stable (idempotent).
//
// Language notes (XIOM v0.61.3): free functions only; Str values read from
// Vec[Str] elements are compared with xiom.string.compare.str_compare (BUG 17:
// `==` on such elements lowers to a pointer comparison); Ok/Err are built only
// in the leaf constructors _ok_grammar/_err_grammar/_ok_int/_err_int/_ok_text/
// _err_text; Vec[Int] element reads bind a typed local first (BUG 17 family).

module xiom.gbnf

use xiom.string;
use xiom.string.compare;
use xiom.convert;

// Node kinds of the flat expression tree.
const _GB_NODE_LIT: Int = 0;   // string literal; text = decoded bytes
const _GB_NODE_CLASS: Int = 1; // char class; text = canonical "[...]" spelling
const _GB_NODE_REF: Int = 2;   // rule reference; text = rule name
const _GB_NODE_SEQ: Int = 3;   // sequence; child list, >= 1 child
const _GB_NODE_ALT: Int = 4;   // alternation; child list, >= 2 children
const _GB_NODE_STAR: Int = 5;  // zero or more; exactly 1 child
const _GB_NODE_PLUS: Int = 6;  // one or more; exactly 1 child
const _GB_NODE_OPT: Int = 7;   // zero or one; exactly 1 child

/// Parsed GBNF grammar: an ordered rule list plus one flat expression tree per
/// rule. `names[i]` is the name of rule `i` in definition order and
/// `roots[i]` is the index of its root node. Rule `i` owns every node in
/// node_starts[rule_starts[i] ..= roots[i]]; the roots are increasing, so the
/// per-rule slices are contiguous and in order. For a node `n`:
///   * leaf kinds LIT / CLASS / REF carry their payload in node_texts[n]
///     (decoded literal bytes / canonical "[...]" text / rule name);
///   * internal kinds SEQ / ALT / STAR / PLUS / OPT describe their children as
///     node_children[node_starts[n] .. node_starts[n] + node_counts[n] - 1];
///   * leaves have node_counts[n] == 0.
pub type GbnfGrammar = {
  names: Vec[Str];
  roots: Vec[Int];
  rule_starts: Vec[Int];
  node_kinds: Vec[Int];
  node_texts: Vec[Str];
  node_starts: Vec[Int];
  node_counts: Vec[Int];
  node_children: Vec[Int];
}

// ---------------------------------------------------------------------------
// Result constructors (see the module header)
// ---------------------------------------------------------------------------

// Ok(v) for Result[GbnfGrammar, Str].
fn _ok_grammar(v: GbnfGrammar) -> Result[GbnfGrammar, Str] {
  return Ok(v);
}

// Err(m) for Result[GbnfGrammar, Str].
fn _err_grammar(m: Str) -> Result[GbnfGrammar, Str] {
  return Err(m);
}

// Ok(v) for Result[Int, Str].
fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

// Err(m) for Result[Int, Str].
fn _err_int(m: Str) -> Result[Int, Str] {
  return Err(m);
}

// Ok(v) for Result[Str, Str].
fn _ok_text(v: Str) -> Result[Str, Str] {
  return Ok(v);
}

// Err(m) for Result[Str, Str].
fn _err_text(m: Str) -> Result[Str, Str] {
  return Err(m);
}

// ---------------------------------------------------------------------------
// Byte predicates
// ---------------------------------------------------------------------------

// True for ASCII space, tab, LF or CR.
fn _is_space_byte(b: UInt8) -> Bool {
  return b == 32u8 || b == 9u8 || b == 10u8 || b == 13u8;
}

// True for a rule-name start byte: A-Z, a-z or _.
fn _is_name_start(b: UInt8) -> Bool {
  if b >= 65u8 && b <= 90u8 { return true; }
  if b >= 97u8 && b <= 122u8 { return true; }
  return b == 95u8;
}

// True for a rule-name byte: A-Z, a-z, 0-9, _ or -.
fn _is_name_byte(b: UInt8) -> Bool {
  if _is_name_start(b) { return true; }
  if b >= 48u8 && b <= 57u8 { return true; }
  return b == 45u8;
}

// Hex value of an ASCII hex digit, or -1.
fn _hex_val(x: Int) -> Int {
  if x >= 48 && x <= 57 { return x - 48; }
  if x >= 97 && x <= 102 { return x - 87; }
  if x >= 65 && x <= 70 { return x - 55; }
  return -1;
}

// ---------------------------------------------------------------------------
// Scanning helpers
// ---------------------------------------------------------------------------

// Advance *pos past spaces, tabs, LF, CR and `#` comments (to end of line).
fn _skip_space(s: Str, pos: &mut Int) {
  let n = s.len();
  loop {
    if *pos >= n { break; }
    let c = string.byte_at(s, *pos);
    if _is_space_byte(c) {
      *pos = *pos + 1;
    } elif c == 35u8 {
      while *pos < n && string.byte_at(s, *pos) != 10u8 {
        *pos = *pos + 1;
      }
    } else {
      break;
    }
  }
}

// Read a rule name at *pos; "" when no name starts there.
fn _try_name(s: Str, pos: &mut Int) -> Str {
  let n = s.len();
  if *pos >= n { return ""; }
  if !_is_name_start(string.byte_at(s, *pos)) { return ""; }
  let start = *pos;
  *pos = *pos + 1;
  while *pos < n && _is_name_byte(string.byte_at(s, *pos)) {
    *pos = *pos + 1;
  }
  return string.str_slice(s, start, *pos);
}

// True when the bytes at `pos` are exactly "::=".
fn _assign3(s: Str, pos: Int) -> Bool {
  let n = s.len();
  if pos + 2 >= n { return false; }
  if string.byte_at(s, pos) != 58u8 { return false; }
  if string.byte_at(s, pos + 1) != 58u8 { return false; }
  return string.byte_at(s, pos + 2) == 61u8;
}

// True when *pos starts `name ::=`, i.e. the next rule definition. Used to
// terminate a rule body; *pos is restored before returning.
fn _rule_ahead(s: Str, pos: &mut Int) -> Bool {
  let save = *pos;
  _skip_space(s, pos);
  var found = false;
  let n = s.len();
  if *pos < n && _is_name_start(string.byte_at(s, *pos)) {
    _try_name(s, pos);
    _skip_space(s, pos);
    if _assign3(s, *pos) { found = true; }
  }
  *pos = save;
  return found;
}

// Index of `name` in g.names, or -1. str_compare because BUG 17 lowers `==`
// on Vec[Str] elements to a pointer comparison.
fn _name_index(g: &GbnfGrammar, name: Str) -> Int {
  var i = 0;
  while i < g.names.len() {
    if compare.str_compare(g.names[i], name) == 0 { return i; }
    i = i + 1;
  }
  return -1;
}

// ---------------------------------------------------------------------------
// Escapes
// ---------------------------------------------------------------------------

// Error message for a backslash escape outside the supported table.
fn _bad_escape(in_class: Bool, pos: Int) -> Str {
  if in_class {
    return "gbnf: invalid escape in character class at " + convert.int_to_string(pos);
  }
  return "gbnf: invalid escape in string at " + convert.int_to_string(pos);
}

// Consume the backslash escape at *pos and return its byte value (0..255).
// Supported: \\ \n \t \r \xHH; \" in strings; \] \- \^ in character classes.
// \x00 is rejected inside string literals because XIOM Str cannot carry a NUL
// byte; inside a character class it is kept (the class stores its spelling).
fn _read_escape(s: Str, pos: &mut Int, in_class: Bool) -> Result[Int, Str] {
  let bs = *pos;
  *pos = *pos + 1;
  let n = s.len();
  if *pos >= n { return _err_int(_bad_escape(in_class, bs)); }
  let e = (string.byte_at(s, *pos) as Int) & 0xFF;
  *pos = *pos + 1;
  if e == 110 { return _ok_int(10); }
  if e == 116 { return _ok_int(9); }
  if e == 114 { return _ok_int(13); }
  if e == 92 { return _ok_int(92); }
  if e == 120 {
    if *pos + 1 >= n {
      return _err_int("gbnf: invalid hex escape at " + convert.int_to_string(bs));
    }
    let d1 = _hex_val((string.byte_at(s, *pos) as Int) & 0xFF);
    let d2 = _hex_val((string.byte_at(s, *pos + 1) as Int) & 0xFF);
    if d1 < 0 || d2 < 0 {
      return _err_int("gbnf: invalid hex escape at " + convert.int_to_string(bs));
    }
    let v = d1 * 16 + d2;
    if v == 0 && !in_class {
      return _err_int("gbnf: NUL byte is not supported at " + convert.int_to_string(bs));
    }
    *pos = *pos + 2;
    return _ok_int(v);
  }
  if !in_class && e == 34 { return _ok_int(34); }
  if in_class && e == 93 { return _ok_int(93); }
  if in_class && e == 45 { return _ok_int(45); }
  if in_class && e == 94 { return _ok_int(94); }
  return _err_int(_bad_escape(in_class, bs));
}

// Read one character-class member starting at *pos (raw byte or escape).
fn _read_class_char(s: Str, pos: &mut Int) -> Result[Int, Str] {
  let n = s.len();
  if *pos >= n {
    return _err_int("gbnf: unterminated character class at " + convert.int_to_string(*pos));
  }
  let c = string.byte_at(s, *pos);
  if c == 92u8 {
    return _read_escape(s, pos, true);
  }
  *pos = *pos + 1;
  return _ok_int((c as Int) & 0xFF);
}

// ---------------------------------------------------------------------------
// Literal and class rendering
// ---------------------------------------------------------------------------

// One byte as a fresh Str (bytes of multi-byte UTF-8 stay raw).
fn _single_byte(c: Int) -> Str {
  var v = Vec[UInt8].new();
  v.push(c as UInt8);
  return Str::from_utf8(v);
}

// Two lower-case hex digits for a byte value.
fn _hex2(c: Int) -> Str {
  let hi = (c / 16) & 15;
  let lo = c & 15;
  let digits = "0123456789abcdef";
  return string.str_slice(digits, hi, hi + 1) + string.str_slice(digits, lo, lo + 1);
}

// Canonical escape of one byte inside a "..." literal body.
fn _escape_lit_char(c: Int) -> Str {
  if c == 34 { return "\\\""; }
  if c == 92 { return "\\\\"; }
  if c == 10 { return "\\n"; }
  if c == 9 { return "\\t"; }
  if c == 13 { return "\\r"; }
  if c < 32 || c == 127 { return "\\x" + _hex2(c); }
  return _single_byte(c);
}

// Canonical escape of one byte inside a [...] character-class body.
fn _escape_class_char(c: Int) -> Str {
  if c == 93 { return "\\]"; }
  if c == 92 { return "\\\\"; }
  if c == 45 { return "\\-"; }
  if c == 94 { return "\\^"; }
  if c == 10 { return "\\n"; }
  if c == 9 { return "\\t"; }
  if c == 13 { return "\\r"; }
  if c < 32 || c == 127 { return "\\x" + _hex2(c); }
  return _single_byte(c);
}

// Canonical escape of a whole decoded literal body.
fn _escape_literal(v: Str) -> Str {
  var out = "";
  var i = 0;
  while i < v.len() {
    let c = (string.byte_at(v, i) as Int) & 0xFF;
    out = out + _escape_lit_char(c);
    i = i + 1;
  }
  return out;
}

// ---------------------------------------------------------------------------
// Expression tree construction
// ---------------------------------------------------------------------------

// Append a leaf node and return its index.
fn _push_leaf(g: &mut GbnfGrammar, kind: Int, text: Str) -> Int {
  let idx = g.node_kinds.len();
  g.node_kinds.push(kind);
  g.node_texts.push(text);
  g.node_starts.push(0);
  g.node_counts.push(0);
  return idx;
}

// Append a one-child repetition node and return its index.
fn _push_repeat(g: &mut GbnfGrammar, kind: Int, child: Int) -> Int {
  let start = g.node_children.len();
  g.node_children.push(child);
  let idx = g.node_kinds.len();
  g.node_kinds.push(kind);
  g.node_texts.push("");
  g.node_starts.push(start);
  g.node_counts.push(1);
  return idx;
}

// Append an internal node over the given child indices and return its index.
fn _push_internal(g: &mut GbnfGrammar, kind: Int, kids: &Vec[Int]) -> Int {
  let start = g.node_children.len();
  var i = 0;
  while i < kids.len() {
    let k: Int = kids[i];
    g.node_children.push(k);
    i = i + 1;
  }
  let idx = g.node_kinds.len();
  g.node_kinds.push(kind);
  g.node_texts.push("");
  g.node_starts.push(start);
  g.node_counts.push(kids.len());
  return idx;
}

// ---------------------------------------------------------------------------
// Parser
// ---------------------------------------------------------------------------

// Parse a "..." literal at *pos; returns the decoded bytes.
fn _parse_literal(s: Str, pos: &mut Int) -> Result[Str, Str] {
  let open = *pos;
  *pos = *pos + 1;
  let n = s.len();
  var out = Vec[UInt8].new();
  while *pos < n {
    let c = string.byte_at(s, *pos);
    if c == 34u8 {
      *pos = *pos + 1;
      return _ok_text(Str::from_utf8(out));
    }
    if c == 92u8 {
      let er = _read_escape(s, pos, false);
      match er {
        Ok(v) => { out.push(v as UInt8); },
        Err(e) => { return _err_text(e); },
      }
    } else {
      out.push(c);
      *pos = *pos + 1;
    }
  }
  return _err_text("gbnf: unterminated string at " + convert.int_to_string(open));
}

// Parse a [...] character class at *pos; returns its canonical spelling.
fn _parse_class(s: Str, pos: &mut Int) -> Result[Str, Str] {
  let open = *pos;
  *pos = *pos + 1;
  let n = s.len();
  var negated = false;
  if *pos < n && string.byte_at(s, *pos) == 94u8 {
    negated = true;
    *pos = *pos + 1;
  }
  var parts = Vec[Str].new();
  while *pos < n && string.byte_at(s, *pos) != 93u8 {
    let c1pos = *pos;
    let r1 = _read_class_char(s, pos);
    var c1 = 0;
    match r1 {
      Ok(v) => { c1 = v; },
      Err(e) => { return _err_text(e); },
    }
    var is_range = false;
    if *pos + 1 < n {
      let dash = string.byte_at(s, *pos);
      let after = string.byte_at(s, *pos + 1);
      if dash == 45u8 && after != 93u8 { is_range = true; }
    }
    if is_range {
      *pos = *pos + 1;
      let r2 = _read_class_char(s, pos);
      var c2 = 0;
      match r2 {
        Ok(v) => { c2 = v; },
        Err(e) => { return _err_text(e); },
      }
      if c2 < c1 {
        return _err_text("gbnf: reversed character range at " + convert.int_to_string(c1pos));
      }
      parts.push(_escape_class_char(c1) + "-" + _escape_class_char(c2));
    } else {
      parts.push(_escape_class_char(c1));
    }
  }
  if *pos >= n {
    return _err_text("gbnf: unterminated character class at " + convert.int_to_string(open));
  }
  *pos = *pos + 1;
  if parts.len() == 0 {
    return _err_text("gbnf: empty character class at " + convert.int_to_string(open));
  }
  var out = "[";
  if negated { out = out + "^"; }
  var i = 0;
  while i < parts.len() {
    let p: Str = parts[i];
    out = out + p;
    i = i + 1;
  }
  out = out + "]";
  return _ok_text(out);
}

// Parse one atom: literal, class, group or rule reference.
fn _parse_atom(g: &mut GbnfGrammar, s: Str, pos: &mut Int) -> Result[Int, Str] {
  let n = s.len();
  if *pos >= n {
    return _err_int("gbnf: empty expression at " + convert.int_to_string(*pos));
  }
  let c = string.byte_at(s, *pos);
  if c == 34u8 {
    let lr = _parse_literal(s, pos);
    match lr {
      Ok(text) => { return _ok_int(_push_leaf(g, _GB_NODE_LIT, text)); },
      Err(e) => { return _err_int(e); },
    }
  }
  if c == 91u8 {
    let cr = _parse_class(s, pos);
    match cr {
      Ok(text) => { return _ok_int(_push_leaf(g, _GB_NODE_CLASS, text)); },
      Err(e) => { return _err_int(e); },
    }
  }
  if c == 40u8 {
    let open = *pos;
    *pos = *pos + 1;
    let ar = _parse_alternates(g, s, pos);
    match ar {
      Ok(inner) => {
        _skip_space(s, pos);
        if *pos < n && string.byte_at(s, *pos) == 41u8 {
          *pos = *pos + 1;
          return _ok_int(inner);
        }
        return _err_int("gbnf: unterminated group at " + convert.int_to_string(open));
      },
      Err(e) => { return _err_int(e); },
    }
  }
  if _is_name_start(c) {
    let name = _try_name(s, pos);
    return _ok_int(_push_leaf(g, _GB_NODE_REF, name));
  }
  return _err_int("gbnf: unexpected byte at " + convert.int_to_string(*pos));
}

// Parse one term: an atom plus at most one adjacent repetition suffix.
fn _parse_term(g: &mut GbnfGrammar, s: Str, pos: &mut Int) -> Result[Int, Str] {
  let ar = _parse_atom(g, s, pos);
  var node = 0;
  match ar {
    Ok(v) => { node = v; },
    Err(e) => { return _err_int(e); },
  }
  if *pos < s.len() {
    let c = string.byte_at(s, *pos);
    if c == 42u8 || c == 43u8 || c == 63u8 {
      *pos = *pos + 1;
      if c == 42u8 {
        node = _push_repeat(g, _GB_NODE_STAR, node);
      } elif c == 43u8 {
        node = _push_repeat(g, _GB_NODE_PLUS, node);
      } else {
        node = _push_repeat(g, _GB_NODE_OPT, node);
      }
    }
  }
  return _ok_int(node);
}

// Parse a whitespace-separated sequence of terms. Stops at `|`, `)`, the next
// `name ::=` definition or end of input.
fn _parse_sequence(g: &mut GbnfGrammar, s: Str, pos: &mut Int) -> Result[Int, Str] {
  _skip_space(s, pos);
  var terms = Vec[Int].new();
  loop {
    _skip_space(s, pos);
    let n = s.len();
    if *pos >= n { break; }
    let c = string.byte_at(s, *pos);
    if c == 124u8 || c == 41u8 { break; }
    if _rule_ahead(s, pos) { break; }
    let tr = _parse_term(g, s, pos);
    match tr {
      Ok(v) => { terms.push(v); },
      Err(e) => { return _err_int(e); },
    }
  }
  if terms.len() == 0 {
    return _err_int("gbnf: empty expression at " + convert.int_to_string(*pos));
  }
  if terms.len() == 1 {
    let only: Int = terms[0];
    return _ok_int(only);
  }
  return _ok_int(_push_internal(g, _GB_NODE_SEQ, &terms));
}

// Parse `sequence ( "|" sequence )*`.
fn _parse_alternates(g: &mut GbnfGrammar, s: Str, pos: &mut Int) -> Result[Int, Str] {
  let fr = _parse_sequence(g, s, pos);
  var first = 0;
  match fr {
    Ok(v) => { first = v; },
    Err(e) => { return _err_int(e); },
  }
  var alts = Vec[Int].new();
  alts.push(first);
  loop {
    _skip_space(s, pos);
    if *pos >= s.len() { break; }
    if string.byte_at(s, *pos) != 124u8 { break; }
    *pos = *pos + 1;
    let nr = _parse_sequence(g, s, pos);
    match nr {
      Ok(v) => { alts.push(v); },
      Err(e) => { return _err_int(e); },
    }
  }
  if alts.len() == 1 {
    let only: Int = alts[0];
    return _ok_int(only);
  }
  return _ok_int(_push_internal(g, _GB_NODE_ALT, &alts));
}

// ---------------------------------------------------------------------------
// Canonical emission
// ---------------------------------------------------------------------------

// Canonical rendering of node `n` with kind-aware parentheses.
fn _emit_node(g: &GbnfGrammar, n: Int) -> Str {
  let kind: Int = g.node_kinds[n];
  if kind == _GB_NODE_LIT {
    let text: Str = g.node_texts[n];
    return "\"" + _escape_literal(text) + "\"";
  }
  if kind == _GB_NODE_CLASS {
    let cls: Str = g.node_texts[n];
    return cls;
  }
  if kind == _GB_NODE_REF {
    let ref: Str = g.node_texts[n];
    return ref;
  }
  let start: Int = g.node_starts[n];
  let count: Int = g.node_counts[n];
  if kind == _GB_NODE_SEQ || kind == _GB_NODE_ALT {
    var sep = " ";
    if kind == _GB_NODE_ALT { sep = " | "; }
    var out = "";
    var i = 0;
    while i < count {
      if i > 0 { out = out + sep; }
      let child: Int = g.node_children[start + i];
      let ck: Int = g.node_kinds[child];
      var piece = _emit_node(g, child);
      if ck == _GB_NODE_ALT && kind == _GB_NODE_SEQ { piece = "(" + piece + ")"; }
      out = out + piece;
      i = i + 1;
    }
    return out;
  }
  let child2: Int = g.node_children[start];
  var inner = _emit_node(g, child2);
  let ck2: Int = g.node_kinds[child2];
  if ck2 >= _GB_NODE_SEQ { inner = "(" + inner + ")"; }
  if kind == _GB_NODE_STAR { return inner + "*"; }
  if kind == _GB_NODE_PLUS { return inner + "+"; }
  return inner + "?";
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Parse and validate a GBNF grammar.
/// Params: text - the whole grammar text (may be empty).
/// Returns: Ok(GbnfGrammar) with rules in definition order; Err(msg) with a
/// "gbnf: ..." message for a malformed construct, a duplicate rule name or an
/// unresolved rule reference. Validation is conservative: no left-recursion or
/// reachability analysis is performed.
/// Complexity: O(input length) for well-formed input; a duplicate-name check
/// adds O(rules) per definition.
pub fn gbnf_parse(text: Str) -> Result[GbnfGrammar, Str] {
  var pos = 0;
  var g = GbnfGrammar{
    names: Vec[Str].new();
    roots: Vec[Int].new();
    rule_starts: Vec[Int].new();
    node_kinds: Vec[Int].new();
    node_texts: Vec[Str].new();
    node_starts: Vec[Int].new();
    node_counts: Vec[Int].new();
    node_children: Vec[Int].new();
  };
  loop {
    _skip_space(text, &mut pos);
    if pos >= text.len() { break; }
    if !_is_name_start(string.byte_at(text, pos)) {
      return _err_grammar("gbnf: expected rule name at " + convert.int_to_string(pos));
    }
    let name_start = pos;
    let name = _try_name(text, &mut pos);
    if _name_index(&g, name) >= 0 {
      return _err_grammar("gbnf: duplicate rule \"" + name + "\" at " + convert.int_to_string(name_start));
    }
    _skip_space(text, &mut pos);
    if !_assign3(text, pos) {
      return _err_grammar("gbnf: expected '::=' at " + convert.int_to_string(pos));
    }
    pos = pos + 3;
    _skip_space(text, &mut pos);
    let node_start = g.node_kinds.len();
    let ar = _parse_alternates(&mut g, text, &mut pos);
    var root = 0;
    match ar {
      Ok(v) => { root = v; },
      Err(e) => { return _err_grammar(e); },
    }
    g.names.push(name);
    g.roots.push(root);
    g.rule_starts.push(node_start);
  }
  var r = 0;
  while r < g.names.len() {
    let rule_name: Str = g.names[r];
    let from: Int = g.rule_starts[r];
    let rule_root: Int = g.roots[r];
    var node = from;
    while node <= rule_root {
      let kind: Int = g.node_kinds[node];
      if kind == _GB_NODE_REF {
        let ref: Str = g.node_texts[node];
        if _name_index(&g, ref) < 0 {
          return _err_grammar("gbnf: unresolved reference \"" + ref + "\" in rule \"" + rule_name + "\"");
        }
      }
      node = node + 1;
    }
    r = r + 1;
  }
  return _ok_grammar(g);
}

/// Parse `text` and validate it without building a caller-visible grammar.
/// Params: text - the whole grammar text.
/// Returns: Ok(rule_count) for a valid grammar (0 for an empty one); Err(msg)
/// with the same "gbnf: ..." messages as gbnf_parse.
/// Complexity: same as gbnf_parse.
pub fn gbnf_validate(text: Str) -> Result[Int, Str] {
  let r = gbnf_parse(text);
  match r {
    Ok(g) => { return _ok_int(g.names.len()); },
    Err(e) => { return _err_int(e); },
  }
  return _err_int("gbnf: unreachable");
}

/// Canonical GBNF text of a parsed grammar: one `name ::= expression` line
/// per rule, in definition order, with normalized whitespace and no comments.
/// Params: g - the parsed grammar.
/// Returns: the canonical text; "" for an empty grammar. Parsing the result
/// again yields the same canonical text (idempotent round-trip).
/// Error case: none.
/// Complexity: O(rules * expression size).
pub fn gbnf_emit(g: &GbnfGrammar) -> Str {
  var out = "";
  var r = 0;
  while r < g.names.len() {
    let name: Str = g.names[r];
    let root: Int = g.roots[r];
    out = out + name + " ::= " + _emit_node(g, root) + "\n";
    r = r + 1;
  }
  return out;
}

/// Number of rules.
/// Params: g - the parsed grammar.
/// Returns: the rule count; 0 for an empty grammar.
/// Error case: none.
/// Complexity: O(1).
pub fn gbnf_rule_count(g: &GbnfGrammar) -> Int {
  return g.names.len();
}

/// Name of rule `i` in definition order.
/// Params: g - the parsed grammar; i - zero-based rule index.
/// Returns: the rule name; "" when `i` is negative or out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn gbnf_rule_name(g: &GbnfGrammar, i: Int) -> Str {
  if i < 0 || i >= g.names.len() {
    return "";
  }
  let name: Str = g.names[i];
  return name;
}

/// Name of the first rule (the GBNF root rule by convention).
/// Params: g - the parsed grammar.
/// Returns: the first rule name; "" for an empty grammar.
/// Error case: none.
/// Complexity: O(1).
pub fn gbnf_root_name(g: &GbnfGrammar) -> Str {
  if g.names.len() == 0 {
    return "";
  }
  let name: Str = g.names[0];
  return name;
}

/// True when a rule named `name` is defined (exact, case-sensitive match).
/// Params: g - the parsed grammar; name - the rule name to look up.
/// Returns: true when defined.
/// Error case: none.
/// Complexity: O(rules).
pub fn gbnf_has_rule(g: &GbnfGrammar, name: Str) -> Bool {
  return _name_index(g, name) >= 0;
}

/// Number of nodes in rule `i`'s expression tree.
/// Params: g - the parsed grammar; i - zero-based rule index.
/// Returns: the node count (>= 1 for a defined rule); -1 when `i` is negative
/// or out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn gbnf_node_count(g: &GbnfGrammar, i: Int) -> Int {
  if i < 0 || i >= g.rule_starts.len() {
    return -1;
  }
  let start: Int = g.rule_starts[i];
  let root: Int = g.roots[i];
  return root - start + 1;
}

/// Rule names referenced by rule `i`, in source order (duplicates kept).
/// Params: g - the parsed grammar; i - zero-based rule index.
/// Returns: the referenced names; an empty vector when `i` is out of range or
/// the rule references no other rule.
/// Error case: none.
/// Complexity: O(nodes of rule i).
pub fn gbnf_rule_refs(g: &GbnfGrammar, i: Int) -> Vec[Str] {
  var out = Vec[Str].new();
  if i < 0 || i >= g.rule_starts.len() {
    return out;
  }
  let start: Int = g.rule_starts[i];
  let root: Int = g.roots[i];
  var node = start;
  while node <= root {
    let kind: Int = g.node_kinds[node];
    if kind == _GB_NODE_REF {
      let ref: Str = g.node_texts[node];
      out.push(ref);
    }
    node = node + 1;
  }
  return out;
}
