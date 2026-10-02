// XIOM -- xiom.parser_fw: recursive-descent and precedence-climbing parsers
// Port task: replace the xiom.parser-fw placeholder with a pure-XIOM module
// (no FFI, no IO, no Vec[Float64], no Vec[StructType], no closures).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Scope: the reusable machinery of a hand-written parser over a
// caller-provided token stream. Six pieces:
//   * token kinds as Int constants plus a TokenStream (three parallel Vecs:
//     kinds/starts/ends) and a caller-built classification table (KindTable)
//     that maps exact words to token kinds;
//   * Grammar: a concrete arena of rules (empty, token, sequence, ordered
//     choice, zero/one-or-more, optional, EOF, precedence-climbing) with
//     patch helpers for recursive rules, infix and prefix binding-power
//     tables and a panic-mode synchronization set;
//   * the core engine `parse_run` interpreting the arena recursively with
//     full backtracking (a failed rule restores the cursor and discards the
//     parse-tree nodes it created);
//   * Pratt/precedence climbing over an atom rule with an infix table
//     (lbp/rbp) and a prefix table (rbp);
//   * panic-mode recovery in the repetition rules: on a child failure the
//     engine reports the failure, skips tokens to the synchronization set and
//     resumes with an explicit error node, bounded by max_errors and by
//     progress caps;
//   * ParseTree: seven parallel Vecs (kind/rule/token/start/end/first/next)
//     using a first-child/next-sibling layout, with an S-expression renderer
//     for tests and diagnostics.
//
// Semantics (see SPEC.md for the full statement):
//   * The token stream is caller-built and only read; the engine never
//     mutates it. A position at or past the end reads as P_KIND_EOF.
//   * Backtracking invariant: when a rule returns -1 it has restored the
//     cursor to its entry position and truncated the tree to its entry
//     length, so ordered choice is plain first-match-wins.
//   * Diagnostics: every failed attempt records the furthest failure
//     position and the first label seen there (a Str per rule, e.g.
//     "number", "expr"); the pending failure is materialized as one error
//     message either at a recovery point or when the top-level parse fails.
//   * Recovery skips stop BEFORE a synchronization token (the token is left
//     for the next attempt); a skip that consumes nothing stops the loop, so
//     every repetition makes progress.
//
// Language notes (XIOM v0.62.2): free functions only; no match statements;
// Str values read from Vec[Str] elements go through typed locals and are
// compared with str_compare; Vec element reads use typed locals; parallel
// Vecs are pushed only through the single `_tree_push`/`ts_push` sites; loops
// carry progress guards; `Ok`/`Err` are not used at all (no Result types).

module xiom.parser_fw

use xiom.string;
use xiom.string.compare;
use xiom.convert;

// ---------------------------------------------------------------------------
// Token model and classification
// ---------------------------------------------------------------------------

/// No token / unknown kind (the zero value).
pub const P_KIND_NONE: Int = 0;

/// End of input; also what a position at or past the stream end reads as.
pub const P_KIND_EOF: Int = 1;

/// An unclassified identifier.
pub const P_KIND_IDENT: Int = 2;

/// An integer/numeric literal.
pub const P_KIND_INT: Int = 3;

/// A string literal.
pub const P_KIND_STRING: Int = 4;

/// An operator (binding-power tables are keyed by the operator's own kind).
pub const P_KIND_OP: Int = 5;

/// Punctuation (parentheses, separators, terminators, ...).
pub const P_KIND_PUNCT: Int = 6;

/// A reserved word; classification tables use this for exact words.
pub const P_KIND_KEYWORD: Int = 7;

/// Token stream as three parallel Vecs: token `i` spans `[starts[i], ends[i])`
/// in the caller's source and has kind `kinds[i]`. The engine never appends an
/// EOF sentinel; out-of-range reads report P_KIND_EOF.
pub type TokenStream = {
  kinds: Vec[Int];
  starts: Vec[Int];
  ends: Vec[Int];
}

/// Exact-word classification table: parallel Vec[Str] words and Vec[Int]
/// kinds (entry `i` pairs `words[i]` with `kinds[i]`).
pub type KindTable = {
  words: Vec[Str];
  kinds: Vec[Int];
}

/// A fresh empty stream. Complexity: O(1).
pub fn ts_new() -> TokenStream {
  return TokenStream{ kinds: Vec[Int].new(); starts: Vec[Int].new(); ends: Vec[Int].new(); };
}

/// Append one token. `start` is inclusive and `end` exclusive; the caller is
/// responsible for keeping spans sane (the engine only reads them).
/// Complexity: O(1) amortized.
pub fn ts_push(t: &mut TokenStream, kind: Int, start: Int, end: Int) {
  t.kinds.push(kind);
  t.starts.push(start);
  t.ends.push(end);
}

/// Number of tokens. Complexity: O(1).
pub fn ts_len(t: &TokenStream) -> Int {
  return t.kinds.len();
}

/// Kind of token `i`, or P_KIND_EOF when out of range. Complexity: O(1).
pub fn ts_kind(t: &TokenStream, i: Int) -> Int {
  if i < 0 || i >= t.kinds.len() {
    return P_KIND_EOF;
  }
  let k: Int = t.kinds[i];
  return k;
}

/// Inclusive start byte of token `i`, or -1 when out of range. O(1).
pub fn ts_start(t: &TokenStream, i: Int) -> Int {
  if i < 0 || i >= t.starts.len() {
    return -1;
  }
  let v: Int = t.starts[i];
  return v;
}

/// Exclusive end byte of token `i`, or -1 when out of range. O(1).
pub fn ts_end(t: &TokenStream, i: Int) -> Int {
  if i < 0 || i >= t.ends.len() {
    return -1;
  }
  let v: Int = t.ends[i];
  return v;
}

/// Short name of a token kind (diagnostics; "?" for unknown kinds). O(1).
pub fn ts_kind_name(kind: Int) -> Str {
  if kind == P_KIND_NONE {
    return "none";
  }
  if kind == P_KIND_EOF {
    return "EOF";
  }
  if kind == P_KIND_IDENT {
    return "ident";
  }
  if kind == P_KIND_INT {
    return "int";
  }
  if kind == P_KIND_STRING {
    return "string";
  }
  if kind == P_KIND_OP {
    return "op";
  }
  if kind == P_KIND_PUNCT {
    return "punct";
  }
  if kind == P_KIND_KEYWORD {
    return "keyword";
  }
  return "?";
}

/// Raw source text of token `i`: the inclusive/exclusive span slice, or ""
/// when `i` is out of range. Complexity: O(token length).
pub fn token_text(source: Str, t: &TokenStream, i: Int) -> Str {
  if i < 0 || i >= t.kinds.len() {
    return "";
  }
  let a: Int = t.starts[i];
  let b: Int = t.ends[i];
  return string.str_slice(source, a, b);
}

/// An empty table. Complexity: O(1).
pub fn kt_new() -> KindTable {
  return KindTable{ words: Vec[Str].new(); kinds: Vec[Int].new(); };
}

/// Register `word` with `kind` (exact, case-sensitive; earliest duplicate
/// wins). An empty word is registrable but never matches. Complexity: O(1).
pub fn kt_add(t: &mut KindTable, word: Str, kind: Int) {
  t.words.push(word);
  t.kinds.push(kind);
}

/// Number of registered words. Complexity: O(1).
pub fn kt_len(t: &KindTable) -> Int {
  return t.words.len();
}

/// Word at `i`, or "" when out of range. Complexity: O(1).
pub fn kt_word(t: &KindTable, i: Int) -> Str {
  if i < 0 || i >= t.words.len() {
    return "";
  }
  let w: Str = t.words[i];
  return w;
}

/// Kind at `i`, or P_KIND_NONE when out of range. Complexity: O(1).
pub fn kt_kind(t: &KindTable, i: Int) -> Int {
  if i < 0 || i >= t.kinds.len() {
    return P_KIND_NONE;
  }
  let k: Int = t.kinds[i];
  return k;
}

/// Exact lookup: the kind registered for the first entry whose text equals
/// `word`, or P_KIND_NONE. Complexity: O(|table| * |word|).
pub fn kt_lookup(t: &KindTable, word: Str) -> Int {
  var i = 0;
  while i < t.words.len() {
    let w: Str = t.words[i];
    if compare.str_compare(w, word) == 0 {
      let k: Int = t.kinds[i];
      return k;
    }
    i = i + 1;
  }
  return P_KIND_NONE;
}

/// Classify an identifier text: the registered kind when present, else
/// P_KIND_IDENT. Complexity: O(|table| * |word|).
pub fn kt_classify(t: &KindTable, word: Str) -> Int {
  let k = kt_lookup(t, word);
  if k != P_KIND_NONE {
    return k;
  }
  return P_KIND_IDENT;
}

// ---------------------------------------------------------------------------
// Grammar rules
// ---------------------------------------------------------------------------

/// Always succeeds, consumes nothing.
pub const P_RULE_EMPTY: Int = 0;

/// Match one token of a fixed kind.
pub const P_RULE_TOKEN: Int = 1;

/// Sequence of two child rules (n-ary sequences nest).
pub const P_RULE_SEQ: Int = 2;

/// Ordered choice of two child rules (first match wins, full backtracking).
pub const P_RULE_CHOICE: Int = 3;

/// Zero or more repetitions of the child; panic-recovers on failure.
pub const P_RULE_REPEAT0: Int = 4;

/// One or more repetitions of the child; fails when the first attempt fails.
pub const P_RULE_REPEAT1: Int = 5;

/// Child or nothing; an absent match yields one P_NODE_EMPTY node.
pub const P_RULE_OPTIONAL: Int = 6;

/// Succeed only at end of input (end of token stream).
pub const P_RULE_EOF: Int = 7;

/// Precedence-climbing expression: `rule_a` is the atom rule; the grammar's
/// infix and prefix binding-power tables drive the operator loops.
pub const P_RULE_PREC: Int = 8;

/// A concrete grammar arena. Rule `i` is described by index `i` in
/// `rule_kind`, `rule_label`, `rule_token`, `rule_a` and `rule_b` (all five
/// vectors share a length; `-1` marks an unused child). Operator tables are
/// keyed by token kind: infix rows are (op_kind, op_lbp, op_rbp), prefix rows
/// are (pre_kind, pre_rbp); `sync_kind` is the panic-mode set.
pub type Grammar = {
  rule_kind: Vec[Int];
  rule_label: Vec[Str];
  rule_token: Vec[Int];
  rule_a: Vec[Int];
  rule_b: Vec[Int];
  op_kind: Vec[Int];
  op_lbp: Vec[Int];
  op_rbp: Vec[Int];
  pre_kind: Vec[Int];
  pre_rbp: Vec[Int];
  sync_kind: Vec[Int];
}

/// An empty grammar. Complexity: O(1).
pub fn grammar_new() -> Grammar {
  return Grammar{
    rule_kind: Vec[Int].new(); rule_label: Vec[Str].new(); rule_token: Vec[Int].new();
    rule_a: Vec[Int].new(); rule_b: Vec[Int].new();
    op_kind: Vec[Int].new(); op_lbp: Vec[Int].new(); op_rbp: Vec[Int].new();
    pre_kind: Vec[Int].new(); pre_rbp: Vec[Int].new();
    sync_kind: Vec[Int].new();
  };
}

// Single rule push site: the five rule vectors can never drift (trap 16).
fn _rule_push(g: &mut Grammar, kind: Int, label: Str, tok: Int, a: Int, b: Int) -> Int {
  g.rule_kind.push(kind);
  g.rule_label.push(label);
  g.rule_token.push(tok);
  g.rule_a.push(a);
  g.rule_b.push(b);
  return g.rule_kind.len() - 1;
}

/// Rule that always succeeds with an empty node. Returns the rule index.
/// Complexity: O(1).
pub fn rule_empty(g: &mut Grammar, label: Str) -> Int {
  return _rule_push(g, P_RULE_EMPTY, label, -1, -1, -1);
}

/// Rule matching one token of `token_kind`; `label` names what was expected in
/// diagnostics. Complexity: O(1).
pub fn rule_token(g: &mut Grammar, token_kind: Int, label: Str) -> Int {
  return _rule_push(g, P_RULE_TOKEN, label, token_kind, -1, -1);
}

/// Sequence rule `a b`; `label` names the production in the parse tree.
/// Complexity: O(1).
pub fn rule_seq(g: &mut Grammar, a: Int, b: Int, label: Str) -> Int {
  return _rule_push(g, P_RULE_SEQ, label, -1, a, b);
}

/// Three-element sequence `a b c` (nested pairs; the outer rule carries the
/// label). Complexity: O(1).
pub fn rule_seq3(g: &mut Grammar, a: Int, b: Int, c: Int, label: Str) -> Int {
  let ab = _rule_push(g, P_RULE_SEQ, "", -1, a, b);
  return _rule_push(g, P_RULE_SEQ, label, -1, ab, c);
}

/// Ordered choice `a | b` (first match wins). Complexity: O(1).
pub fn rule_choice(g: &mut Grammar, a: Int, b: Int, label: Str) -> Int {
  return _rule_push(g, P_RULE_CHOICE, label, -1, a, b);
}

/// Zero-or-more repetition of `child` (panic-recovers on child failure).
/// Complexity: O(1).
pub fn rule_repeat0(g: &mut Grammar, child: Int, label: Str) -> Int {
  return _rule_push(g, P_RULE_REPEAT0, label, -1, child, -1);
}

/// One-or-more repetition of `child`; fails when the first child attempt
/// fails. Complexity: O(1).
pub fn rule_repeat1(g: &mut Grammar, child: Int, label: Str) -> Int {
  return _rule_push(g, P_RULE_REPEAT1, label, -1, child, -1);
}

/// Optional `child`; absence yields one P_NODE_EMPTY node. O(1).
pub fn rule_optional(g: &mut Grammar, child: Int, label: Str) -> Int {
  return _rule_push(g, P_RULE_OPTIONAL, label, -1, child, -1);
}

/// End-of-input rule. Complexity: O(1).
pub fn rule_eof(g: &mut Grammar, label: Str) -> Int {
  return _rule_push(g, P_RULE_EOF, label, -1, -1, -1);
}

/// Precedence-climbing rule over `atom`; patched atom rules wire recursion.
/// Complexity: O(1).
pub fn rule_prec(g: &mut Grammar, atom: Int, label: Str) -> Int {
  return _rule_push(g, P_RULE_PREC, label, -1, atom, -1);
}

/// Set the `a` child of an existing rule (recursion wiring); out-of-range
/// indices are a no-op. Complexity: O(1).
pub fn rule_patch_a(g: &mut Grammar, rule: Int, child: Int) {
  if rule < 0 || rule >= g.rule_a.len() {
    return;
  }
  g.rule_a[rule] = child;
}

/// Set the `b` child of an existing rule; out-of-range indices are a no-op.
/// Complexity: O(1).
pub fn rule_patch_b(g: &mut Grammar, rule: Int, child: Int) {
  if rule < 0 || rule >= g.rule_b.len() {
    return;
  }
  g.rule_b[rule] = child;
}

/// Register an infix operator: binding powers `lbp` (left, compared against
/// the minimum) and `rbp` (right, the operand's minimum). Use `rbp = lbp + 1`
/// for left associativity. Complexity: O(1).
pub fn grammar_op_add(g: &mut Grammar, token_kind: Int, lbp: Int, rbp: Int) {
  g.op_kind.push(token_kind);
  g.op_lbp.push(lbp);
  g.op_rbp.push(rbp);
}

/// Register a prefix operator with right binding power `rbp` (typically
/// larger than every infix lbp it should bind tighter than). O(1).
pub fn grammar_prefix_add(g: &mut Grammar, token_kind: Int, rbp: Int) {
  g.pre_kind.push(token_kind);
  g.pre_rbp.push(rbp);
}

/// Add `token_kind` to the panic-mode synchronization set. Recovery skips
/// tokens until it reaches one of these kinds (left unconsumed) or EOF.
/// Complexity: O(1).
pub fn grammar_sync_add(g: &mut Grammar, token_kind: Int) {
  g.sync_kind.push(token_kind);
}

/// Number of rules in the arena. Complexity: O(1).
pub fn grammar_rule_count(g: &Grammar) -> Int {
  return g.rule_kind.len();
}

/// True iff the five rule vectors have equal length (arena invariant).
/// Complexity: O(1).
pub fn grammar_is_consistent(g: &Grammar) -> Bool {
  let n = g.rule_kind.len();
  if g.rule_label.len() != n {
    return false;
  }
  if g.rule_token.len() != n {
    return false;
  }
  if g.rule_a.len() != n {
    return false;
  }
  return g.rule_b.len() == n;
}

/// Rule kind at `r`, or -1 when out of range. Complexity: O(1).
pub fn grammar_rule_kind(g: &Grammar, r: Int) -> Int {
  if r < 0 || r >= g.rule_kind.len() {
    return -1;
  }
  let k: Int = g.rule_kind[r];
  return k;
}

/// Rule label at `r`, or "" when out of range. Complexity: O(1).
pub fn grammar_rule_label(g: &Grammar, r: Int) -> Str {
  if r < 0 || r >= g.rule_label.len() {
    return "";
  }
  let s: Str = g.rule_label[r];
  return s;
}

/// Rule token kind at `r`, or -1 when out of range. Complexity: O(1).
pub fn grammar_rule_token(g: &Grammar, r: Int) -> Int {
  if r < 0 || r >= g.rule_token.len() {
    return -1;
  }
  let v: Int = g.rule_token[r];
  return v;
}

/// First child of rule `r`, or -1 when out of range. Complexity: O(1).
pub fn grammar_rule_a(g: &Grammar, r: Int) -> Int {
  if r < 0 || r >= g.rule_a.len() {
    return -1;
  }
  let v: Int = g.rule_a[r];
  return v;
}

/// Second child of rule `r`, or -1 when out of range. Complexity: O(1).
pub fn grammar_rule_b(g: &Grammar, r: Int) -> Int {
  if r < 0 || r >= g.rule_b.len() {
    return -1;
  }
  let v: Int = g.rule_b[r];
  return v;
}

// Index of the infix row for `kind`, or -1 when absent.
fn _op_index(g: &Grammar, kind: Int) -> Int {
  var i = 0;
  while i < g.op_kind.len() {
    let k: Int = g.op_kind[i];
    if k == kind {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Right binding power of prefix `kind`, or 0 when absent.
fn _pre_bp(g: &Grammar, kind: Int) -> Int {
  var i = 0;
  while i < g.pre_kind.len() {
    let k: Int = g.pre_kind[i];
    if k == kind {
      let v: Int = g.pre_rbp[i];
      return v;
    }
    i = i + 1;
  }
  return 0;
}

// True when `kind` is in the synchronization set.
fn _sync_has(g: &Grammar, kind: Int) -> Bool {
  var i = 0;
  while i < g.sync_kind.len() {
    let k: Int = g.sync_kind[i];
    if k == kind {
      return true;
    }
    i = i + 1;
  }
  return false;
}

// ---------------------------------------------------------------------------
// Parse-tree node model
// ---------------------------------------------------------------------------

/// An interior rule node (carries the rule index and children).
pub const P_NODE_RULE: Int = 0;

/// A leaf token node (`node_token` is the token index).
pub const P_NODE_TOKEN: Int = 1;

/// A recovery node spanning the tokens panic-mode skipped.
pub const P_NODE_ERROR: Int = 2;

/// An empty match (optional absent, empty rule, EOF).
pub const P_NODE_EMPTY: Int = 3;

/// Parse tree as seven parallel Vecs; node `i` uses index `i` in each. The
/// child layout is first-child/next-sibling: `node_first[i]` is the first
/// child (-1 = none) and `node_next[c]` is c's next sibling (-1 = last).
/// Interior nodes span the token range `[node_start, node_end)`; token nodes
/// span exactly one token; error nodes span the skipped tokens.
pub type ParseTree = {
  node_kind: Vec[Int];
  node_rule: Vec[Int];
  node_token: Vec[Int];
  node_start: Vec[Int];
  node_end: Vec[Int];
  node_first: Vec[Int];
  node_next: Vec[Int];
}

/// An empty tree. Complexity: O(1).
pub fn tree_new() -> ParseTree {
  return ParseTree{
    node_kind: Vec[Int].new(); node_rule: Vec[Int].new(); node_token: Vec[Int].new();
    node_start: Vec[Int].new(); node_end: Vec[Int].new();
    node_first: Vec[Int].new(); node_next: Vec[Int].new();
  };
}

// Single node push site: the seven tree vectors can never drift (trap 16).
fn _tree_push(tr: &mut ParseTree, kind: Int, rule: Int, token: Int, start: Int, end: Int) -> Int {
  tr.node_kind.push(kind);
  tr.node_rule.push(rule);
  tr.node_token.push(token);
  tr.node_start.push(start);
  tr.node_end.push(end);
  tr.node_first.push(-1);
  tr.node_next.push(-1);
  return tr.node_kind.len() - 1;
}

// Number of nodes (internal; the public accessor is tree_len).
fn _tree_len(tr: &ParseTree) -> Int {
  return tr.node_kind.len();
}

// Pop all seven vectors back to `mark` nodes (backtracking).
fn _tree_truncate(tr: &mut ParseTree, mark: Int) {
  while tr.node_kind.len() > mark {
    let d0 = tr.node_kind.pop();
  }
  while tr.node_rule.len() > mark {
    let d1 = tr.node_rule.pop();
  }
  while tr.node_token.len() > mark {
    let d2 = tr.node_token.pop();
  }
  while tr.node_start.len() > mark {
    let d3 = tr.node_start.pop();
  }
  while tr.node_end.len() > mark {
    let d4 = tr.node_end.pop();
  }
  while tr.node_first.len() > mark {
    let d5 = tr.node_first.pop();
  }
  while tr.node_next.len() > mark {
    let d6 = tr.node_next.pop();
  }
}

// Append `child` to `parent`'s sibling chain (progress-capped walk).
fn _tree_add_child(tr: &mut ParseTree, parent: Int, child: Int) {
  if parent < 0 || child < 0 {
    return;
  }
  if parent >= tr.node_kind.len() || child >= tr.node_kind.len() {
    return;
  }
  let f: Int = tr.node_first[parent];
  if f < 0 {
    tr.node_first[parent] = child;
    return;
  }
  var cur = f;
  var last = f;
  var guard = 0;
  while cur >= 0 && guard < 100000 {
    last = cur;
    let nx: Int = tr.node_next[cur];
    cur = nx;
    guard = guard + 1;
  }
  tr.node_next[last] = child;
}

/// Number of nodes. Complexity: O(1).
pub fn tree_len(tr: &ParseTree) -> Int {
  return tr.node_kind.len();
}

/// Node kind at `i`, or -1 when out of range. Complexity: O(1).
pub fn tree_node_kind(tr: &ParseTree, i: Int) -> Int {
  if i < 0 || i >= tr.node_kind.len() {
    return -1;
  }
  let k: Int = tr.node_kind[i];
  return k;
}

/// Rule index of node `i` (-1 when out of range or not applicable). O(1).
pub fn tree_node_rule(tr: &ParseTree, i: Int) -> Int {
  if i < 0 || i >= tr.node_rule.len() {
    return -1;
  }
  let v: Int = tr.node_rule[i];
  return v;
}

/// Token index of token node `i`, or -1 (out of range or non-token). O(1).
pub fn tree_node_token(tr: &ParseTree, i: Int) -> Int {
  if i < 0 || i >= tr.node_token.len() {
    return -1;
  }
  let v: Int = tr.node_token[i];
  return v;
}

/// Inclusive start token of node `i`, or -1 when out of range. O(1).
pub fn tree_node_start(tr: &ParseTree, i: Int) -> Int {
  if i < 0 || i >= tr.node_start.len() {
    return -1;
  }
  let v: Int = tr.node_start[i];
  return v;
}

/// Exclusive end token of node `i`, or -1 when out of range. O(1).
pub fn tree_node_end(tr: &ParseTree, i: Int) -> Int {
  if i < 0 || i >= tr.node_end.len() {
    return -1;
  }
  let v: Int = tr.node_end[i];
  return v;
}

/// First child of node `i`, or -1 (out of range or leaf). O(1).
pub fn tree_first_child(tr: &ParseTree, i: Int) -> Int {
  if i < 0 || i >= tr.node_first.len() {
    return -1;
  }
  let v: Int = tr.node_first[i];
  return v;
}

/// Next sibling of node `i`, or -1 (out of range or last). O(1).
pub fn tree_next_sibling(tr: &ParseTree, i: Int) -> Int {
  if i < 0 || i >= tr.node_next.len() {
    return -1;
  }
  let v: Int = tr.node_next[i];
  return v;
}

/// Number of direct children of node `i` (0 when out of range). O(children).
pub fn tree_child_count(tr: &ParseTree, i: Int) -> Int {
  if i < 0 || i >= tr.node_first.len() {
    return 0;
  }
  var n = 0;
  var cur: Int = tr.node_first[i];
  var guard = 0;
  while cur >= 0 && guard < 100000 {
    n = n + 1;
    let nx: Int = tr.node_next[cur];
    cur = nx;
    guard = guard + 1;
  }
  return n;
}

/// `k`-th direct child (0-based) of node `i`, or -1. O(k).
pub fn tree_child(tr: &ParseTree, i: Int, k: Int) -> Int {
  if k < 0 {
    return -1;
  }
  var cur: Int = tree_first_child(tr, i);
  var at = 0;
  var guard = 0;
  while cur >= 0 && at < k && guard < 100000 {
    let nx: Int = tr.node_next[cur];
    cur = nx;
    at = at + 1;
    guard = guard + 1;
  }
  return cur;
}

/// Raw source text covered by node `i` (`[start of first token, end of last
/// token)`), or "" when the node is empty, out of range or misaligned.
/// Complexity: O(span length).
pub fn tree_span_text(source: Str, ts: &TokenStream, tr: &ParseTree, i: Int) -> Str {
  if i < 0 || i >= tr.node_kind.len() {
    return "";
  }
  let s: Int = tr.node_start[i];
  let e: Int = tr.node_end[i];
  if s < 0 || e <= s {
    return "";
  }
  let a = ts_start(ts, s);
  let b = ts_end(ts, e - 1);
  if a < 0 || b < 0 {
    return "";
  }
  return string.str_slice(source, a, b);
}

// S-expression of one node: tokens render as their raw text, error nodes as
// "<err>", empty nodes as "<empty>", rule nodes as "(label children...)" with
// an empty label rendered transparently on precedence nodes.
pub fn tree_to_sexpr(g: &Grammar, source: Str, ts: &TokenStream, tr: &ParseTree, node: Int) -> Str {
  return _sexpr_node(g, source, ts, tr, node, 0);
}

fn _sexpr_node(g: &Grammar, source: Str, ts: &TokenStream, tr: &ParseTree, node: Int, depth: Int) -> Str {
  if node < 0 || node >= tr.node_kind.len() || depth > 200 {
    return "";
  }
  let nk: Int = tr.node_kind[node];
  if nk == P_NODE_TOKEN {
    let ti: Int = tr.node_token[node];
    return token_text(source, ts, ti);
  }
  if nk == P_NODE_ERROR {
    return "<err>";
  }
  if nk == P_NODE_EMPTY {
    return "<empty>";
  }
  var inner = "";
  var count = 0;
  var child: Int = tr.node_first[node];
  var guard = 0;
  while child >= 0 && guard < 100000 {
    if count > 0 {
      inner = inner + " ";
    }
    inner = inner + _sexpr_node(g, source, ts, tr, child, depth + 1);
    count = count + 1;
    let nx: Int = tr.node_next[child];
    child = nx;
    guard = guard + 1;
  }
  let r: Int = tr.node_rule[node];
  let rk = grammar_rule_kind(g, r);
  var lbl: Str = "";
  if rk != P_RULE_PREC {
    lbl = grammar_rule_label(g, r);
  }
  if compare.str_compare(lbl, "") == 0 {
    return "(" + inner + ")";
  }
  if compare.str_compare(inner, "") == 0 {
    return "(" + lbl + ")";
  }
  return "(" + lbl + " " + inner + ")";
}

// ---------------------------------------------------------------------------
// Parser state and diagnostics
// ---------------------------------------------------------------------------

/// Mutable parser state: cursor, collected error messages, the pending
/// (furthest) failure and recovery counters. `max_errors` bounds the number
/// of recovery errors; the engine stops recovering once it is reached.
pub type PState = {
  pos: Int;
  errors: Vec[Str];
  fail_pos: Int;
  fail_label: Str;
  recovered: Int;
  max_errors: Int;
  stopped: Bool;
}

/// Result of one `parse_run`: whether the root rule matched, its tree node
/// (-1 on failure), the final cursor, all error messages, recovery stats and
/// the parse tree.
pub type ParseOutcome = {
  ok: Bool;
  root: Int;
  pos: Int;
  errors: Vec[Str];
  error_count: Int;
  recovered: Int;
  stopped: Bool;
  tree: ParseTree;
}

// Clear the pending failure (start of a fresh attempt).
fn _reset_fail(st: &mut PState) {
  st.fail_pos = -1;
  st.fail_label = "";
}

// Record a failure at `pos`: the furthest position wins; at an equal position
// the first label recorded wins (deterministic diagnostics).
fn _record_fail(st: &mut PState, pos: Int, label: Str) {
  if pos > st.fail_pos {
    st.fail_pos = pos;
    st.fail_label = label;
  }
}

// Materialize the pending failure as one error message (recovery point or
// top-level failure). A missing label produces the generic message.
fn _flush_fail(st: &mut PState) {
  if st.fail_pos < 0 {
    return;
  }
  let at = st.fail_pos;
  let lbl: Str = st.fail_label;
  var msg = "";
  if compare.str_compare(lbl, "") == 0 {
    msg = "parser: syntax error at token " + int_to_string(at);
  } else {
    msg = "parser: expected " + lbl + " at token " + int_to_string(at);
  }
  st.errors.push(msg);
  st.fail_pos = -1;
  st.fail_label = "";
}

// True when panic-mode recovery can skip from the current position: a sync
// kind is registered, the cursor is not at EOF or at a sync token, and the
// error budget is not exhausted.
fn _can_recover(g: &Grammar, ts: &TokenStream, st: &PState) -> Bool {
  if st.errors.len() >= st.max_errors {
    return false;
  }
  if st.pos >= ts_len(ts) {
    return false;
  }
  let k = ts_kind(ts, st.pos);
  if k == P_KIND_EOF {
    return false;
  }
  if _sync_has(g, k) {
    return false;
  }
  return g.sync_kind.len() > 0;
}

// Skip tokens until EOF or a synchronization token (left unconsumed).
// Returns the number skipped; never exceeds the stream length.
fn _panic_skip(g: &Grammar, ts: &TokenStream, st: &mut PState) -> Int {
  var skipped = 0;
  var going = true;
  while going && st.pos < ts_len(ts) && skipped < 100000 {
    let k = ts_kind(ts, st.pos);
    if k == P_KIND_EOF {
      going = false;
    } elif _sync_has(g, k) {
      going = false;
    } else {
      st.pos = st.pos + 1;
      skipped = skipped + 1;
    }
  }
  return skipped;
}

// ---------------------------------------------------------------------------
// Engine
// ---------------------------------------------------------------------------

// One token rule attempt.
fn _parse_token(g: &Grammar, r: Int, ts: &TokenStream, st: &mut PState, tr: &mut ParseTree) -> Int {
  let want: Int = g.rule_token[r];
  let k = ts_kind(ts, st.pos);
  if k == want {
    let i = st.pos;
    st.pos = st.pos + 1;
    return _tree_push(tr, P_NODE_TOKEN, r, i, i, i + 1);
  }
  let lbl: Str = g.rule_label[r];
  _record_fail(st, st.pos, lbl);
  return -1;
}

// Sequence: both children must match; any failure restores the entry state.
fn _parse_seq(g: &Grammar, r: Int, ts: &TokenStream, st: &mut PState, tr: &mut ParseTree) -> Int {
  let entry_pos = st.pos;
  let entry_tm = _tree_len(tr);
  let a = _parse_rule(g, grammar_rule_a(g, r), ts, st, tr);
  if a < 0 {
    st.pos = entry_pos;
    _tree_truncate(tr, entry_tm);
    return -1;
  }
  let b = _parse_rule(g, grammar_rule_b(g, r), ts, st, tr);
  if b < 0 {
    st.pos = entry_pos;
    _tree_truncate(tr, entry_tm);
    return -1;
  }
  let p = _tree_push(tr, P_NODE_RULE, r, -1, entry_pos, st.pos);
  _tree_add_child(tr, p, a);
  _tree_add_child(tr, p, b);
  let bs: Int = tr.node_start[a];
  let be: Int = tr.node_end[b];
  tr.node_start[p] = bs;
  tr.node_end[p] = be;
  return p;
}

// Ordered choice: first match wins; children restore on their own failures.
fn _parse_choice(g: &Grammar, r: Int, ts: &TokenStream, st: &mut PState, tr: &mut ParseTree) -> Int {
  let na = _parse_rule(g, grammar_rule_a(g, r), ts, st, tr);
  if na >= 0 {
    return na;
  }
  let nb = _parse_rule(g, grammar_rule_b(g, r), ts, st, tr);
  if nb >= 0 {
    return nb;
  }
  return -1;
}

// Zero-or-more and one-or-more with panic-mode recovery. `is_one` makes the
// rule fail when no iteration ever matched.
fn _parse_repeat(g: &Grammar, r: Int, ts: &TokenStream, st: &mut PState, tr: &mut ParseTree, is_one: Bool) -> Int {
  let entry_pos = st.pos;
  let entry_tm = _tree_len(tr);
  let parent = _tree_push(tr, P_NODE_RULE, r, -1, entry_pos, entry_pos);
  var count = 0;
  var going = true;
  var guard = 0;
  while going && guard < 100000 {
    guard = guard + 1;
    let mark = st.pos;
    _reset_fail(st);
    let c = _parse_rule(g, grammar_rule_a(g, r), ts, st, tr);
    if c >= 0 {
      _tree_add_child(tr, parent, c);
      let ce: Int = tr.node_end[c];
      tr.node_end[parent] = ce;
      count = count + 1;
      if st.pos == mark {
        going = false;
      }
    } else {
      if _can_recover(g, ts, st) {
        _flush_fail(st);
        let skip_start = st.pos;
        let skipped = _panic_skip(g, ts, st);
        if skipped > 0 {
          let en = _tree_push(tr, P_NODE_ERROR, r, -1, skip_start, st.pos);
          _tree_add_child(tr, parent, en);
          tr.node_end[parent] = st.pos;
          st.recovered = st.recovered + skipped;
        } else {
          going = false;
        }
        if st.errors.len() >= st.max_errors {
          going = false;
          st.stopped = true;
        }
      } else {
        going = false;
      }
    }
  }
  if is_one && count == 0 {
    st.pos = entry_pos;
    _tree_truncate(tr, entry_tm);
    return -1;
  }
  return parent;
}

// Optional: child or one empty node.
fn _parse_optional(g: &Grammar, r: Int, ts: &TokenStream, st: &mut PState, tr: &mut ParseTree) -> Int {
  let entry_pos = st.pos;
  let entry_tm = _tree_len(tr);
  let c = _parse_rule(g, grammar_rule_a(g, r), ts, st, tr);
  if c >= 0 {
    return c;
  }
  st.pos = entry_pos;
  _tree_truncate(tr, entry_tm);
  return _tree_push(tr, P_NODE_EMPTY, r, -1, entry_pos, entry_pos);
}

// End of input.
fn _parse_eof(g: &Grammar, r: Int, ts: &TokenStream, st: &mut PState, tr: &mut ParseTree) -> Int {
  if st.pos >= ts_len(ts) {
    return _tree_push(tr, P_NODE_EMPTY, r, -1, st.pos, st.pos);
  }
  let lbl: Str = g.rule_label[r];
  _record_fail(st, st.pos, lbl);
  return -1;
}

// Precedence climbing: `min_bp` is the minimum left binding power accepted in
// the infix loop. Prefix operators recurse with their own rbp; the atom is
// parsed with the same rule, so recursion is data-driven (trap 5: no indexed
// function dispatch anywhere).
fn _parse_prec(g: &Grammar, r: Int, ts: &TokenStream, st: &mut PState, tr: &mut ParseTree, min_bp: Int) -> Int {
  let entry_pos = st.pos;
  let entry_tm = _tree_len(tr);
  let atom = grammar_rule_a(g, r);
  var lhs = -1;
  let k0 = ts_kind(ts, st.pos);
  let prbp = _pre_bp(g, k0);
  if prbp > 0 {
    let opn = _tree_push(tr, P_NODE_TOKEN, r, st.pos, st.pos, st.pos + 1);
    st.pos = st.pos + 1;
    let plbl: Str = g.rule_label[r];
    _record_fail(st, st.pos, plbl);
    let rhs = _parse_prec(g, r, ts, st, tr, prbp);
    if rhs < 0 {
      st.pos = entry_pos;
      _tree_truncate(tr, entry_tm);
      return -1;
    }
    let p = _tree_push(tr, P_NODE_RULE, r, -1, entry_pos, st.pos);
    _tree_add_child(tr, p, opn);
    _tree_add_child(tr, p, rhs);
    let pe: Int = tr.node_end[rhs];
    tr.node_end[p] = pe;
    lhs = p;
  } else {
    let albl: Str = g.rule_label[r];
    _record_fail(st, st.pos, albl);
    let a = _parse_rule(g, atom, ts, st, tr);
    if a < 0 {
      st.pos = entry_pos;
      _tree_truncate(tr, entry_tm);
      return -1;
    }
    lhs = a;
  }
  var left = lhs;
  var going = true;
  var guard = 0;
  while going && guard < 100000 {
    guard = guard + 1;
    let k = ts_kind(ts, st.pos);
    let idx = _op_index(g, k);
    if idx < 0 {
      going = false;
    } else {
      let lbp: Int = g.op_lbp[idx];
      if lbp < min_bp {
        going = false;
      } else {
        let rbp: Int = g.op_rbp[idx];
        let opn = _tree_push(tr, P_NODE_TOKEN, r, st.pos, st.pos, st.pos + 1);
        st.pos = st.pos + 1;
        let rlbl: Str = g.rule_label[r];
        _record_fail(st, st.pos, rlbl);
        let rhs = _parse_prec(g, r, ts, st, tr, rbp);
        if rhs < 0 {
          st.pos = entry_pos;
          _tree_truncate(tr, entry_tm);
          return -1;
        }
        let p = _tree_push(tr, P_NODE_RULE, r, -1, entry_pos, st.pos);
        _tree_add_child(tr, p, left);
        _tree_add_child(tr, p, opn);
        _tree_add_child(tr, p, rhs);
        let pe: Int = tr.node_end[rhs];
        tr.node_end[p] = pe;
        left = p;
      }
    }
  }
  return left;
}

// Rule dispatch by declared kind (explicit if-chain; no function vectors).
fn _parse_rule(g: &Grammar, r: Int, ts: &TokenStream, st: &mut PState, tr: &mut ParseTree) -> Int {
  if r < 0 || r >= g.rule_kind.len() {
    _record_fail(st, st.pos, "rule");
    return -1;
  }
  let kind: Int = g.rule_kind[r];
  if kind == P_RULE_EMPTY {
    return _tree_push(tr, P_NODE_EMPTY, r, -1, st.pos, st.pos);
  }
  if kind == P_RULE_TOKEN {
    return _parse_token(g, r, ts, st, tr);
  }
  if kind == P_RULE_SEQ {
    return _parse_seq(g, r, ts, st, tr);
  }
  if kind == P_RULE_CHOICE {
    return _parse_choice(g, r, ts, st, tr);
  }
  if kind == P_RULE_REPEAT0 {
    return _parse_repeat(g, r, ts, st, tr, false);
  }
  if kind == P_RULE_REPEAT1 {
    return _parse_repeat(g, r, ts, st, tr, true);
  }
  if kind == P_RULE_OPTIONAL {
    return _parse_optional(g, r, ts, st, tr);
  }
  if kind == P_RULE_EOF {
    return _parse_eof(g, r, ts, st, tr);
  }
  if kind == P_RULE_PREC {
    return _parse_prec(g, r, ts, st, tr, 0);
  }
  _record_fail(st, st.pos, "rule");
  return -1;
}

/// Parse `root` over `ts` with a fresh tree and state. `max_errors` bounds the
/// number of recovery errors (values < 1 are raised to 1). On root failure
/// the pending furthest failure is materialized as the final error message.
/// Params: g - the grammar; root - the root rule index; ts - the caller's
///         token stream (read only); max_errors - recovery error budget.
/// Returns: a ParseOutcome with the tree, cursor and diagnostics.
/// Complexity: O(tokens * rules) worst case (full backtracking).
pub fn parse_run(g: &Grammar, root: Int, ts: &TokenStream, max_errors: Int) -> ParseOutcome {
  var tr = tree_new();
  var cap = max_errors;
  if cap < 1 {
    cap = 1;
  }
  var st = PState{
    pos: 0; errors: Vec[Str].new(); fail_pos: -1; fail_label: "";
    recovered: 0; max_errors: cap; stopped: false;
  };
  let n = _parse_rule(g, root, ts, &mut st, &mut tr);
  if n < 0 {
    _flush_fail(&mut st);
    if st.errors.len() == 0 {
      let msg = "parser: syntax error at token " + int_to_string(st.pos);
      st.errors.push(msg);
    }
  }
  let ok_val = n >= 0;
  let ec = st.errors.len();
  let rec = st.recovered;
  let stopped_val = st.stopped;
  let end_pos = st.pos;
  return ParseOutcome{
    ok: ok_val; root: n; pos: end_pos; errors: st.errors;
    error_count: ec; recovered: rec; stopped: stopped_val; tree: tr;
  };
}
