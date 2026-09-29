// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// XIOM -- xiom.parsing: spanned parser combinators over a Str input.
//
// Scope: a deterministic, IO-free parser-combinator framework with absolute
// source-position tracking. Combinators are concrete arena nodes (no
// closures, no fn-pointer values, no Vec[StructType]); the engine is one
// recursive dispatch function, parse_run, over a PGrammar arena built from
// parallel Vec fields.
//
// Result model: every successful sub-parse yields a PSpan { start; end;
// present } naming the half-open byte range [start, end) of the recognized
// text. There is no separate semantic value: the span IS the result, so a
// caller evaluates a parse by slicing the source with parse_span_text.
//
// Backtracking semantics: every combinator restores PState.pos to the
// position it saw when it (or a child it owns) fails.
//   * LITERAL / CLASS consume at most one literal/byte and consume nothing on
//     failure.
//   * SEQ restores its start position when its second child fails, so a
//     failed sequence never leaves the input half-consumed.
//   * ALT is ordered choice: try child_a; on failure restore the position and
//     try child_b; the first success wins (no longest-match search, no
//     speculative reordering).
//   * MANY / MANY1 are greedy and stop at the first child failure; the failed
//     iteration is rolled back. MANY never fails; MANY1 fails (restoring the
//     position) only when its first iteration fails. An iteration that
//     succeeds without consuming input terminates the loop, so many over a
//     nullable child cannot diverge.
//   * OPTIONAL never fails: when the child fails, the position is restored
//     and the result is a zero-width span with present = false.
//   * CAPTURE runs the child and reports the child's span unchanged (the
//     explicit map-to-index-range node).
//
// Errors: leaves record (position, label) into the mutable PState; the error
// reported when the top-level parse fails describes the FURTHEST failure
// position reached and the deduplicated, insertion-ordered set of labels
// expected there, with 1-based line/column computed over raw bytes (LF
// advances the line; CRLF counts as one newline because only LF does).
// Expected sets therefore include labels from speculative probes (e.g. the
// iteration that ended a MANY loop); they are diagnostics, not a proof that
// the grammar could have continued there.
//
// Language notes (XIOM v0.62.1): free functions only; no Vec[StructType]
// (PGrammar and PState hold parallel Vec fields and every push site goes
// through the single private _node_push); Ok/Err literals live only in the
// leaf helpers at the bottom of the file; Str values read from Vec[Str]
// elements go through typed locals and str_compare; every byte read is
// widened with `(b as Int) & 0xFF` before any comparison; bitwise/additive
// mixes are parenthesized.

module xiom.parsing

use xiom.string;
use xiom.string.compare;
use xiom.convert;

// ---------------------------------------------------------------------------
// Combinator kinds
// ---------------------------------------------------------------------------

/// No node / lookup miss (the zero value; never built by a builder).
pub const PARSE_KIND_NONE: Int = 0;

/// Exact-literal match; uses the node's literal text.
pub const PARSE_KIND_LITERAL: Int = 1;

/// One-byte predicate / character class; uses predicate, class_lo, class_hi.
pub const PARSE_KIND_CLASS: Int = 2;

/// Sequence: child_a then child_b, all-or-nothing.
pub const PARSE_KIND_SEQ: Int = 3;

/// Ordered choice: child_a, else child_b, with full backtracking.
pub const PARSE_KIND_ALT: Int = 4;

/// Zero or more child_a applications; greedy; never fails.
pub const PARSE_KIND_MANY: Int = 5;

/// One or more child_a applications; greedy.
pub const PARSE_KIND_MANY1: Int = 6;

/// Optional child_a; never fails; present=false when absent.
pub const PARSE_KIND_OPTIONAL: Int = 7;

/// Capture / map-to-index-range: reports the child's span unchanged.
pub const PARSE_KIND_CAPTURE: Int = 8;

/// End of input: succeeds zero-width only at the end of the source.
pub const PARSE_KIND_EOF: Int = 9;

// ---------------------------------------------------------------------------
// Predicates (used by PARSE_KIND_CLASS)
// ---------------------------------------------------------------------------

/// No predicate; never matches.
pub const PARSE_PRED_NONE: Int = 0;

/// Inclusive byte range class_lo..class_hi (both in 0..255).
pub const PARSE_PRED_RANGE: Int = 1;

/// ASCII `0`-`9`.
pub const PARSE_PRED_DIGIT: Int = 2;

/// ASCII `A`-`Z` or `a`-`z`.
pub const PARSE_PRED_ALPHA: Int = 3;

/// ASCII letter or digit.
pub const PARSE_PRED_ALNUM: Int = 4;

/// ASCII space, tab, LF or CR.
pub const PARSE_PRED_SPACE: Int = 5;

/// Identifier start: ASCII letter or `_`.
pub const PARSE_PRED_IDENT_START: Int = 6;

/// Identifier byte: identifier start or ASCII digit.
pub const PARSE_PRED_IDENT_BYTE: Int = 7;

// ---------------------------------------------------------------------------
// Byte constants (ASCII; every comparison happens in the Int domain)
// ---------------------------------------------------------------------------

const _PX_TAB: Int = 9;
const _PX_LF: Int = 10;
const _PX_CR: Int = 13;
const _PX_SPACE: Int = 32;
const _PX_DIGIT_0: Int = 48;
const _PX_DIGIT_9: Int = 57;
const _PX_UPPER_A: Int = 65;
const _PX_UPPER_Z: Int = 90;
const _PX_UNDERSCORE: Int = 95;
const _PX_LOWER_A: Int = 97;
const _PX_LOWER_Z: Int = 122;

// ---------------------------------------------------------------------------
// Values
// ---------------------------------------------------------------------------

/// A successful parse result: the half-open source byte range [start, end).
/// `present` is false only for OPTIONAL results that took the absent branch
/// (then start == end); every other combinator reports true.
pub type PSpan = {
  start: Int;
  end: Int;
  present: Bool;
}

/// A 1-based source point, derived from a byte offset.
pub type PPoint = {
  line: Int;
  col: Int;
}

/// Structured parse error. `pos` is the furthest failing byte offset; `line`
/// and `col` are its 1-based point; `found` is the raw byte text at `pos`
/// ("" at end of input); `expected` is the deduplicated, insertion-ordered
/// label set recorded at `pos`; `message` is the human-readable rendering.
pub type PError = {
  pos: Int;
  line: Int;
  col: Int;
  found: Str;
  message: Str;
  expected: Vec[Str];
}

/// Mutable parse state over an immutable source: the cursor `pos` (byte
/// offset, 0-based) plus the furthest-failure bookkeeping (`fail_pos`, -1
/// before the first recorded failure, and the expected-label set).
pub type PState = {
  source: Str;
  pos: Int;
  fail_pos: Int;
  expected: Vec[Str];
}

/// The combinator arena. Node i is fully described by index i in each
/// parallel Vec: kind, label (for errors), literal text (LITERAL),
/// class_lo/class_hi (RANGE class), class_pred (predicate id), and up to two
/// child node indices child_a/child_b (-1 when unused). All eight Vecs are
/// pushed together by _node_push, so they cannot drift.
pub type PGrammar = {
  kinds: Vec[Int];
  labels: Vec[Str];
  literals: Vec[Str];
  class_lo: Vec[Int];
  class_hi: Vec[Int];
  class_pred: Vec[Int];
  child_a: Vec[Int];
  child_b: Vec[Int];
}

// ---------------------------------------------------------------------------
// Grammar construction
// ---------------------------------------------------------------------------

// The single push site for all eight parallel Vecs: node <-> field alignment
// is structural, not a convention at each builder.
fn _node_push(g: &mut PGrammar, kind: Int, label: Str, literal: Str, lo: Int, hi: Int, pred: Int, a: Int, b: Int) -> Int {
  let id = g.kinds.len();
  g.kinds.push(kind);
  g.labels.push(label);
  g.literals.push(literal);
  g.class_lo.push(lo);
  g.class_hi.push(hi);
  g.class_pred.push(pred);
  g.child_a.push(a);
  g.child_b.push(b);
  return id;
}

/// An empty arena (no nodes). Params: none. Returns: a fresh grammar.
/// Complexity: O(1).
pub fn parse_grammar_new() -> PGrammar {
  return PGrammar{
    kinds: Vec[Int].new();
    labels: Vec[Str].new();
    literals: Vec[Str].new();
    class_lo: Vec[Int].new();
    class_hi: Vec[Int].new();
    class_pred: Vec[Int].new();
    child_a: Vec[Int].new();
    child_b: Vec[Int].new();
  };
}

/// Number of nodes in the arena. Complexity: O(1).
pub fn parse_node_count(g: &PGrammar) -> Int {
  return g.kinds.len();
}

/// True when all eight parallel Vecs have the same length.
/// Params: g - the arena to check. Returns: the invariant's truth value.
/// Complexity: O(1).
pub fn parse_is_consistent(g: &PGrammar) -> Bool {
  let n = g.kinds.len();
  if g.labels.len() != n {
    return false;
  }
  if g.literals.len() != n {
    return false;
  }
  if g.class_lo.len() != n {
    return false;
  }
  if g.class_hi.len() != n {
    return false;
  }
  if g.class_pred.len() != n {
    return false;
  }
  if g.child_a.len() != n {
    return false;
  }
  if g.child_b.len() != n {
    return false;
  }
  return true;
}

/// Add an exact-literal node. An empty literal matches trivially (zero width)
/// at any position. `label` names the node in errors.
/// Params: g - the arena (mutated); text - the literal; label - error name.
/// Returns: the new node index.
/// Complexity: O(1) plus the literal's bytes at match time.
pub fn parse_literal(g: &mut PGrammar, text: Str, label: Str) -> Int {
  return _node_push(g, PARSE_KIND_LITERAL, label, text, 0, 0, PARSE_PRED_NONE, -1, -1);
}

/// Add a character-class node matching exactly one byte in the inclusive
/// range `lo..hi` (both 0..255). An inverted range (lo > hi) never matches.
/// Params: g - the arena (mutated); lo/hi - inclusive byte bounds;
///         label - error name.
/// Returns: the new node index. Complexity: O(1).
pub fn parse_class_range(g: &mut PGrammar, lo: Int, hi: Int, label: Str) -> Int {
  return _node_push(g, PARSE_KIND_CLASS, label, "", lo, hi, PARSE_PRED_RANGE, -1, -1);
}

/// Add a named-predicate class node (PARSE_PRED_*): matches exactly one byte
/// satisfying the predicate. PARSE_PRED_NONE and unknown ids never match.
/// Params: g - the arena (mutated); pred - the predicate id; label - name.
/// Returns: the new node index. Complexity: O(1).
pub fn parse_class_pred(g: &mut PGrammar, pred: Int, label: Str) -> Int {
  return _node_push(g, PARSE_KIND_CLASS, label, "", 0, 0, pred, -1, -1);
}

/// Add a sequence node: run child_a, then child_b; all-or-nothing.
/// Params: g - the arena (mutated); a/b - child node indices.
/// Returns: the new node index. Complexity: O(1).
pub fn parse_seq(g: &mut PGrammar, a: Int, b: Int) -> Int {
  return _node_push(g, PARSE_KIND_SEQ, "seq", "", 0, 0, PARSE_PRED_NONE, a, b);
}

/// Add an ordered-choice node: child_a, else child_b, with full backtracking.
/// Params: g - the arena (mutated); a/b - child node indices.
/// Returns: the new node index. Complexity: O(1).
pub fn parse_alt(g: &mut PGrammar, a: Int, b: Int) -> Int {
  return _node_push(g, PARSE_KIND_ALT, "alt", "", 0, 0, PARSE_PRED_NONE, a, b);
}

/// Add a zero-or-more node over child_a (greedy, never fails).
/// Params: g - the arena (mutated); a - child node index.
/// Returns: the new node index. Complexity: O(1).
pub fn parse_many(g: &mut PGrammar, a: Int) -> Int {
  return _node_push(g, PARSE_KIND_MANY, "many", "", 0, 0, PARSE_PRED_NONE, a, -1);
}

/// Add a one-or-more node over child_a (greedy).
/// Params: g - the arena (mutated); a - child node index.
/// Returns: the new node index. Complexity: O(1).
pub fn parse_many1(g: &mut PGrammar, a: Int) -> Int {
  return _node_push(g, PARSE_KIND_MANY1, "many1", "", 0, 0, PARSE_PRED_NONE, a, -1);
}

/// Add an optional node over child_a (never fails).
/// Params: g - the arena (mutated); a - child node index.
/// Returns: the new node index. Complexity: O(1).
pub fn parse_optional(g: &mut PGrammar, a: Int) -> Int {
  return _node_push(g, PARSE_KIND_OPTIONAL, "optional", "", 0, 0, PARSE_PRED_NONE, a, -1);
}

/// Add a capture node: the map-to-index-range combinator. It runs child_a and
/// reports the child's span unchanged, so a grammar can name an explicit
/// index range (pinned by tests: capture(seq(a, b)) == the seq span).
/// Params: g - the arena (mutated); a - child node index.
/// Returns: the new node index. Complexity: O(1).
pub fn parse_capture(g: &mut PGrammar, a: Int) -> Int {
  return _node_push(g, PARSE_KIND_CAPTURE, "capture", "", 0, 0, PARSE_PRED_NONE, a, -1);
}

/// Add an end-of-input node: succeeds zero-width at the end of the source and
/// fails with label "end of input" otherwise.
/// Params: g - the arena (mutated). Returns: the new node index.
/// Complexity: O(1).
pub fn parse_eof(g: &mut PGrammar) -> Int {
  return _node_push(g, PARSE_KIND_EOF, "end of input", "", 0, 0, PARSE_PRED_NONE, -1, -1);
}

/// Overwrite child_a of `node` (used to wire recursive grammars after their
/// nodes exist). Out-of-range `node` is a no-op.
/// Params: g - the arena (mutated); node - the node to patch; child - the
///         new child index (-1 clears it). Complexity: O(1).
pub fn parse_patch_child_a(g: &mut PGrammar, node: Int, child: Int) {
  if node < 0 || node >= g.child_a.len() {
    return;
  }
  g.child_a.set(node, child);
}

/// Overwrite child_b of `node`; out-of-range `node` is a no-op.
/// Params: g - the arena (mutated); node - the node to patch; child - the
///         new child index (-1 clears it). Complexity: O(1).
pub fn parse_patch_child_b(g: &mut PGrammar, node: Int, child: Int) {
  if node < 0 || node >= g.child_b.len() {
    return;
  }
  g.child_b.set(node, child);
}

// ---------------------------------------------------------------------------
// Grammar introspection (range-safe; defaults on out-of-range indices)
// ---------------------------------------------------------------------------

/// Kind of node `i`, or PARSE_KIND_NONE when out of range. Complexity: O(1).
pub fn parse_node_kind(g: &PGrammar, i: Int) -> Int {
  if i < 0 || i >= g.kinds.len() {
    return PARSE_KIND_NONE;
  }
  let v: Int = g.kinds[i];
  return v;
}

/// Label of node `i`, or "" when out of range. Complexity: O(1).
pub fn parse_node_label(g: &PGrammar, i: Int) -> Str {
  if i < 0 || i >= g.labels.len() {
    return "";
  }
  let v: Str = g.labels[i];
  return v;
}

/// Literal text of node `i`, or "" when out of range. Complexity: O(1).
pub fn parse_node_literal(g: &PGrammar, i: Int) -> Str {
  if i < 0 || i >= g.literals.len() {
    return "";
  }
  let v: Str = g.literals[i];
  return v;
}

/// Predicate id of node `i`, or PARSE_PRED_NONE when out of range. O(1).
pub fn parse_node_pred(g: &PGrammar, i: Int) -> Int {
  if i < 0 || i >= g.class_pred.len() {
    return PARSE_PRED_NONE;
  }
  let v: Int = g.class_pred[i];
  return v;
}

/// Inclusive class lower bound of node `i`, or 0 when out of range. O(1).
pub fn parse_node_lo(g: &PGrammar, i: Int) -> Int {
  if i < 0 || i >= g.class_lo.len() {
    return 0;
  }
  let v: Int = g.class_lo[i];
  return v;
}

/// Inclusive class upper bound of node `i`, or 0 when out of range. O(1).
pub fn parse_node_hi(g: &PGrammar, i: Int) -> Int {
  if i < 0 || i >= g.class_hi.len() {
    return 0;
  }
  let v: Int = g.class_hi[i];
  return v;
}

/// child_a of node `i`, or -1 when out of range. Complexity: O(1).
pub fn parse_node_child_a(g: &PGrammar, i: Int) -> Int {
  if i < 0 || i >= g.child_a.len() {
    return -1;
  }
  let v: Int = g.child_a[i];
  return v;
}

/// child_b of node `i`, or -1 when out of range. Complexity: O(1).
pub fn parse_node_child_b(g: &PGrammar, i: Int) -> Int {
  if i < 0 || i >= g.child_b.len() {
    return -1;
  }
  let v: Int = g.child_b[i];
  return v;
}

/// Name of a combinator kind constant ("literal", "class", "seq", "alt",
/// "many", "many1", "optional", "capture", "EOF", "none").
/// Params: kind - a PARSE_KIND_* value. Complexity: O(1).
pub fn parse_kind_name(kind: Int) -> Str {
  if kind == PARSE_KIND_LITERAL {
    return "literal";
  }
  if kind == PARSE_KIND_CLASS {
    return "class";
  }
  if kind == PARSE_KIND_SEQ {
    return "seq";
  }
  if kind == PARSE_KIND_ALT {
    return "alt";
  }
  if kind == PARSE_KIND_MANY {
    return "many";
  }
  if kind == PARSE_KIND_MANY1 {
    return "many1";
  }
  if kind == PARSE_KIND_OPTIONAL {
    return "optional";
  }
  if kind == PARSE_KIND_CAPTURE {
    return "capture";
  }
  if kind == PARSE_KIND_EOF {
    return "EOF";
  }
  return "none";
}

/// Name of a predicate constant ("none", "range", "digit", "alpha", "alnum",
/// "space", "ident-start", "ident-byte").
/// Params: pred - a PARSE_PRED_* value. Complexity: O(1).
pub fn parse_pred_name(pred: Int) -> Str {
  if pred == PARSE_PRED_RANGE {
    return "range";
  }
  if pred == PARSE_PRED_DIGIT {
    return "digit";
  }
  if pred == PARSE_PRED_ALPHA {
    return "alpha";
  }
  if pred == PARSE_PRED_ALNUM {
    return "alnum";
  }
  if pred == PARSE_PRED_SPACE {
    return "space";
  }
  if pred == PARSE_PRED_IDENT_START {
    return "ident-start";
  }
  if pred == PARSE_PRED_IDENT_BYTE {
    return "ident-byte";
  }
  return "none";
}

// ---------------------------------------------------------------------------
// Parse state
// ---------------------------------------------------------------------------

/// A fresh state at byte 0 with no recorded failure.
/// Params: source - the immutable input. Returns: the initial state.
/// Complexity: O(1).
pub fn parse_state_new(source: Str) -> PState {
  return PState{ source: source; pos: 0; fail_pos: -1; expected: Vec[Str].new(); };
}

/// Current byte offset (0-based). Complexity: O(1).
pub fn parse_pos(st: &PState) -> Int {
  return st.pos;
}

/// True when every byte has been consumed. Complexity: O(1).
pub fn parse_at_end(st: &PState) -> Bool {
  return st.pos >= st.source.len();
}

/// Byte at the current position as 0..255, or -1 at end of input.
/// Complexity: O(1).
pub fn parse_peek(st: &PState) -> Int {
  return _peek(st.source, st.pos);
}

// ---------------------------------------------------------------------------
// Byte access and predicates
// ---------------------------------------------------------------------------

// Widened, masked byte value: the only way bytes leave UInt8 land.
fn _widen(b: UInt8) -> Int {
  return (b as Int) & 0xFF;
}

// Byte at `pos` as 0..255, or -1 when out of bounds.
fn _peek(source: Str, pos: Int) -> Int {
  if pos < 0 {
    return -1;
  }
  if pos >= source.len() {
    return -1;
  }
  let raw: UInt8 = string.byte_at(source, pos);
  return _widen(raw);
}

// 1-based point of byte offset `pos` (clamped to the source). LF advances the
// line and resets the column; every other byte increments the column, so
// CRLF counts as one newline and a lone CR is an ordinary column.
fn _line_col(source: Str, pos: Int) -> PPoint {
  var line = 1;
  var col = 1;
  var p = pos;
  let n = source.len();
  if p < 0 {
    p = 0;
  }
  if p > n {
    p = n;
  }
  var i = 0;
  while i < p {
    let b = _peek(source, i);
    if b == _PX_LF {
      line = line + 1;
      col = 1;
    } else {
      col = col + 1;
    }
    i = i + 1;
  }
  return PPoint{ line: line; col: col; };
}

fn _pred_matches(pred: Int, lo: Int, hi: Int, b: Int) -> Bool {
  if pred == PARSE_PRED_RANGE {
    return b >= lo && b <= hi;
  }
  if pred == PARSE_PRED_DIGIT {
    return b >= _PX_DIGIT_0 && b <= _PX_DIGIT_9;
  }
  if pred == PARSE_PRED_ALPHA {
    if b >= _PX_UPPER_A && b <= _PX_UPPER_Z {
      return true;
    }
    return b >= _PX_LOWER_A && b <= _PX_LOWER_Z;
  }
  if pred == PARSE_PRED_ALNUM {
    if b >= _PX_DIGIT_0 && b <= _PX_DIGIT_9 {
      return true;
    }
    if b >= _PX_UPPER_A && b <= _PX_UPPER_Z {
      return true;
    }
    return b >= _PX_LOWER_A && b <= _PX_LOWER_Z;
  }
  if pred == PARSE_PRED_SPACE {
    if b == _PX_SPACE || b == _PX_TAB || b == _PX_LF || b == _PX_CR {
      return true;
    }
    return false;
  }
  if pred == PARSE_PRED_IDENT_START {
    if b >= _PX_UPPER_A && b <= _PX_UPPER_Z {
      return true;
    }
    if b >= _PX_LOWER_A && b <= _PX_LOWER_Z {
      return true;
    }
    return b == _PX_UNDERSCORE;
  }
  if pred == PARSE_PRED_IDENT_BYTE {
    if b >= _PX_DIGIT_0 && b <= _PX_DIGIT_9 {
      return true;
    }
    if b >= _PX_UPPER_A && b <= _PX_UPPER_Z {
      return true;
    }
    if b >= _PX_LOWER_A && b <= _PX_LOWER_Z {
      return true;
    }
    return b == _PX_UNDERSCORE;
  }
  return false;
}

// True when `text` is the exact next bytes at `pos` (an empty text matches).
fn _lit_match(source: Str, pos: Int, text: Str) -> Bool {
  let n = text.len();
  if n == 0 {
    return true;
  }
  if pos + n > source.len() {
    return false;
  }
  let piece = string.str_slice(source, pos, pos + n);
  if compare.str_compare(piece, text) != 0 {
    return false;
  }
  return true;
}

// Raw found text: the single byte at `pos`, or "" at/beyond end of input.
fn _found_raw(source: Str, pos: Int) -> Str {
  if pos < 0 || pos >= source.len() {
    return "";
  }
  return string.str_slice(source, pos, pos + 1);
}

fn _hex2(n: Int) -> Str {
  let digits = "0123456789ABCDEF";
  let hi = (n / 16) % 16;
  let lo = n % 16;
  return string.str_slice(digits, hi, hi + 1) + string.str_slice(digits, lo, lo + 1);
}

// Human-readable description of the byte at `pos`: quoted printable ASCII,
// "byte 0xNN" for anything else, "end of input" at/beyond the end.
fn _found_desc(source: Str, pos: Int) -> Str {
  if pos < 0 || pos >= source.len() {
    return "end of input";
  }
  let b = _peek(source, pos);
  if b >= 32 && b <= 126 {
    return "'" + _found_raw(source, pos) + "'";
  }
  return "byte 0x" + _hex2(b);
}

// ---------------------------------------------------------------------------
// Failure bookkeeping and error construction
// ---------------------------------------------------------------------------

// Record a failure of `label` at `pos` into the furthest-failure state:
// farther positions reset the expected set; equal positions append the label
// once (str_compare dedup).
fn _record_failure(st: &mut PState, pos: Int, label: Str) {
  if st.fail_pos < 0 || pos > st.fail_pos {
    st.fail_pos = pos;
    st.expected.clear();
    st.expected.push(label);
    return;
  }
  if pos == st.fail_pos {
    var seen = false;
    var i = 0;
    while i < st.expected.len() {
      let e: Str = st.expected[i];
      if compare.str_compare(e, label) == 0 {
        seen = true;
      }
      i = i + 1;
    }
    if !seen {
      st.expected.push(label);
    }
  }
}

// Build the structured error for the furthest failure recorded so far.
fn _error_from_state(st: &mut PState) -> PError {
  var pos = st.fail_pos;
  if pos < 0 {
    pos = st.pos;
  }
  let pt = _line_col(st.source, pos);
  var exp = Vec[Str].new();
  var i = 0;
  while i < st.expected.len() {
    let e: Str = st.expected[i];
    exp.push(e);
    i = i + 1;
  }
  var msg = "parse error at line " + int_to_string(pt.line) + ", column " + int_to_string(pt.col) + ": expected ";
  var k = 0;
  while k < exp.len() {
    let e2: Str = exp[k];
    if k > 0 {
      msg = msg + ", ";
    }
    msg = msg + e2;
    k = k + 1;
  }
  msg = msg + "; found " + _found_desc(st.source, pos);
  return PError{ pos: pos; line: pt.line; col: pt.col; found: _found_raw(st.source, pos); message: msg; expected: exp; };
}

// Record the failure and return it as an Err.
fn _fail(st: &mut PState, pos: Int, label: Str) -> Result[PSpan, PError] {
  _record_failure(st, pos, label);
  let e = _error_from_state(st);
  return _err_span(e);
}

// ---------------------------------------------------------------------------
// The engine: one recursive dispatch over the arena
// ---------------------------------------------------------------------------

/// Run node `node` against the mutable state, backtracking on failure.
///
/// Params: g - the arena; node - the combinator node index; st - the state
///         (position advanced on success, restored on failure).
/// Returns: Ok(PSpan) with the half-open range of everything the node
///          consumed; Err(PError) with the furthest-failure structured error.
/// Error case: any leaf mismatch; malformed child indices (out of range or
///             -1 on a used slot) fail with expected label
///             "unknown-combinator".
/// Complexity: O(consumed bytes * grammar lookup) per node, additive over
///             alternatives; recursive over the grammar depth.
pub fn parse_run(g: &PGrammar, node: Int, st: &mut PState) -> Result[PSpan, PError] {
  let start = st.pos;
  let kind = parse_node_kind(g, node);
  if kind == PARSE_KIND_LITERAL {
    let text = parse_node_literal(g, node);
    if _lit_match(st.source, start, text) {
      st.pos = start + text.len();
      return _ok_span(PSpan{ start: start; end: st.pos; present: true; });
    }
    return _fail(st, start, parse_node_label(g, node));
  }
  if kind == PARSE_KIND_CLASS {
    let b = _peek(st.source, start);
    let pred = parse_node_pred(g, node);
    let lo = parse_node_lo(g, node);
    let hi = parse_node_hi(g, node);
    if b >= 0 && _pred_matches(pred, lo, hi, b) {
      st.pos = start + 1;
      return _ok_span(PSpan{ start: start; end: st.pos; present: true; });
    }
    return _fail(st, start, parse_node_label(g, node));
  }
  if kind == PARSE_KIND_SEQ {
    let ca = parse_node_child_a(g, node);
    let cb = parse_node_child_b(g, node);
    let ra = parse_run(g, ca, st);
    if !ra.is_ok {
      let e: PError = ra.error;
      st.pos = start;
      return _err_span(e);
    }
    let sa: PSpan = ra.value;
    let rb = parse_run(g, cb, st);
    if !rb.is_ok {
      let e2: PError = rb.error;
      st.pos = start;
      return _err_span(e2);
    }
    let sb: PSpan = rb.value;
    return _ok_span(PSpan{ start: start; end: sb.end; present: true; });
  }
  if kind == PARSE_KIND_ALT {
    let ca = parse_node_child_a(g, node);
    let cb = parse_node_child_b(g, node);
    let ra = parse_run(g, ca, st);
    if ra.is_ok {
      let sa: PSpan = ra.value;
      return _ok_span(sa);
    }
    st.pos = start;
    let rb = parse_run(g, cb, st);
    if rb.is_ok {
      let sb: PSpan = rb.value;
      return _ok_span(sb);
    }
    let e2: PError = rb.error;
    st.pos = start;
    return _err_span(e2);
  }
  if kind == PARSE_KIND_MANY {
    let ca = parse_node_child_a(g, node);
    var going = true;
    while going {
      let before = st.pos;
      let r = parse_run(g, ca, st);
      if !r.is_ok {
        st.pos = before;
        going = false;
      } else {
        let sp: PSpan = r.value;
        if sp.end == before {
          going = false;
        }
      }
    }
    return _ok_span(PSpan{ start: start; end: st.pos; present: true; });
  }
  if kind == PARSE_KIND_MANY1 {
    let ca = parse_node_child_a(g, node);
    let first = parse_run(g, ca, st);
    if !first.is_ok {
      let e: PError = first.error;
      st.pos = start;
      return _err_span(e);
    }
    let fsp: PSpan = first.value;
    if fsp.end == start {
      return _ok_span(PSpan{ start: start; end: start; present: true; });
    }
    var going = true;
    while going {
      let before = st.pos;
      let r = parse_run(g, ca, st);
      if !r.is_ok {
        st.pos = before;
        going = false;
      } else {
        let sp: PSpan = r.value;
        if sp.end == before {
          going = false;
        }
      }
    }
    return _ok_span(PSpan{ start: start; end: st.pos; present: true; });
  }
  if kind == PARSE_KIND_OPTIONAL {
    let ca = parse_node_child_a(g, node);
    let r = parse_run(g, ca, st);
    if !r.is_ok {
      st.pos = start;
      return _ok_span(PSpan{ start: start; end: start; present: false; });
    }
    let sp: PSpan = r.value;
    return _ok_span(sp);
  }
  if kind == PARSE_KIND_CAPTURE {
    let ca = parse_node_child_a(g, node);
    let r = parse_run(g, ca, st);
    if !r.is_ok {
      let e: PError = r.error;
      st.pos = start;
      return _err_span(e);
    }
    let sp: PSpan = r.value;
    return _ok_span(PSpan{ start: sp.start; end: sp.end; present: sp.present; });
  }
  if kind == PARSE_KIND_EOF {
    if start >= st.source.len() {
      return _ok_span(PSpan{ start: start; end: start; present: true; });
    }
    return _fail(st, start, parse_node_label(g, node));
  }
  return _fail(st, start, "unknown-combinator");
}

/// Run node `node` on a fresh state over `source` and require that the whole
/// source is consumed: after the node succeeds, a trailing byte makes the
/// parse fail with expected label "end of input" at that byte.
/// Params: g - the arena; node - the combinator node index; source - input.
/// Returns: Ok(PSpan) covering the node's range (which equals the whole
///          source on success); Err(PError) otherwise.
/// Error case: as parse_run, plus trailing input.
/// Complexity: as parse_run plus O(source) for the trailing check.
pub fn parse_run_all(g: &PGrammar, node: Int, source: Str) -> Result[PSpan, PError] {
  var st = parse_state_new(source);
  let r = parse_run(g, node, &mut st);
  if !r.is_ok {
    let e: PError = r.error;
    return _err_span(e);
  }
  let sp: PSpan = r.value;
  if st.pos < source.len() {
    _record_failure(&mut st, st.pos, "end of input");
    let e2 = _error_from_state(&mut st);
    return _err_span(e2);
  }
  return _ok_span(sp);
}

// ---------------------------------------------------------------------------
// Span accessors
// ---------------------------------------------------------------------------

/// Start byte offset (inclusive) of a span. Complexity: O(1).
pub fn parse_span_start(sp: &PSpan) -> Int {
  return sp.start;
}

/// End byte offset (exclusive) of a span. Complexity: O(1).
pub fn parse_span_end(sp: &PSpan) -> Int {
  return sp.end;
}

/// Length of a span in bytes (0 for absent/zero-width spans). O(1).
pub fn parse_span_len(sp: &PSpan) -> Int {
  if sp.end <= sp.start {
    return 0;
  }
  return sp.end - sp.start;
}

/// Whether the span came from a present match (false only for an OPTIONAL
/// result that took the absent branch). Complexity: O(1).
pub fn parse_span_present(sp: &PSpan) -> Bool {
  return sp.present;
}

/// The raw source text of a span, [start, end). Out-of-range and inverted
/// spans clamp to the overlapping region (xiom.string.str_slice semantics),
/// so this never traps.
/// Params: source - the parsed input; sp - the span.
/// Returns: the slice, or "" when the span is empty after clamping.
/// Complexity: O(span length).
pub fn parse_span_text(source: Str, sp: &PSpan) -> Str {
  return string.str_slice(source, sp.start, sp.end);
}

// ---------------------------------------------------------------------------
// Error accessors
// ---------------------------------------------------------------------------

/// Furthest failing byte offset of an error. Complexity: O(1).
pub fn parse_error_pos(e: &PError) -> Int {
  return e.pos;
}

/// 1-based line of the error position. Complexity: O(1).
pub fn parse_error_line(e: &PError) -> Int {
  return e.line;
}

/// 1-based column of the error position (bytes since the last LF, plus one).
/// Complexity: O(1).
pub fn parse_error_col(e: &PError) -> Int {
  return e.col;
}

/// Raw found text at the error position ("" at end of input). O(1).
pub fn parse_error_found(e: &PError) -> Str {
  return e.found;
}

/// Human-readable error message ("parse error at line L, column C: expected
/// <labels>; found <found-or-end-of-input>"). Complexity: O(message length).
pub fn parse_error_message(e: &PError) -> Str {
  return e.message;
}

/// Number of labels in the expected set. Complexity: O(1).
pub fn parse_error_expected_count(e: &PError) -> Int {
  return e.expected.len();
}

/// Label `i` of the expected set (insertion order), or "" when out of range.
/// Complexity: O(1).
pub fn parse_error_expected(e: &PError, i: Int) -> Str {
  if i < 0 || i >= e.expected.len() {
    return "";
  }
  let v: Str = e.expected[i];
  return v;
}

// ---------------------------------------------------------------------------
// Result constructors (leaf helpers only -- see the module header)
// ---------------------------------------------------------------------------

fn _ok_span(s: PSpan) -> Result[PSpan, PError] {
  return Ok(s);
}

fn _err_span(e: PError) -> Result[PSpan, PError] {
  return Err(e);
}
