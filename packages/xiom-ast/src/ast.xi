// XIOM -- xiom.ast: a deterministic abstract-syntax-tree toolkit
// Port task: replace the xiom.ast placeholder with a pure-XIOM module
// (no FFI, no IO, no Vec[Float64], no Vec[StructType]).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Scope: the generic, language-agnostic machinery an AST consumer needs,
// demonstrated on a small fixture grammar of expression/statement nodes:
//   * node kinds as Int constants (program, let, if, block, return, binary,
//     ident, literal) plus a node model built from PARALLEL Vec fields;
//   * an append-only builder (ast_add_node / ast_add_child / ast_reparent)
//     that keeps every array in lockstep and refuses cycles;
//   * traversal: roots, pre-order, post-order (children left-to-right);
//   * queries: parent, child(k), child_count, next_sibling, is_leaf, depth,
//     is_ancestor, kind counting and leaf counting;
//   * spans: per-node [start,end) byte spans, ast_span_text over the source,
//     a per-node span/diagnostic table and a canonical pretty-printer
//     (2 spaces per depth level);
//   * ast_fixture_source/ast_fixture_ast: a fixed 52-byte program
//     ("let x = 1 + 2;\nif x { return x; } else { return 0; }") whose 14
//     nodes are created in a deliberately non-preorder sequence so the
//     traversal tests exercise a real ordering.
//
// Design decisions (see SPEC.md for the full statement):
//   * No Vec[StructType]: nodes live in seven parallel Vec fields of the same
//     length (kinds, starts, ends, parents, first_child, next_sibling,
//     labels). Only ast_add_node pushes, and it pushes on all seven arrays,
//     so the lengths cannot drift.
//   * Children are a first_child/next_sibling chain per node: mutation is
//     O(children) and never rewrites stored indices, so reparenting cannot
//     invalidate other nodes.
//   * Every Str read out of a Vec[Str] goes through a typed local and is
//     compared with str_compare (BUG 17: `==` on Vec[Str] elements lowers to
//     a pointer comparison; .len() on them is unreliable).
//   * Traversals are iterative with an explicit stack and a step budget, so
//     even a foreign/corrupt tree cannot loop forever.
//
// Language notes (XIOM v0.62.1): free functions only; Str values read from
// Vec[Str] elements are compared with str_compare; Vec element reads go
// through typed locals; mutators touch the tree only through &mut-taking
// private helpers (advisory E001: a `&` call before a `&mut` access on the
// same local is flagged by this compiler).

module xiom.ast

use xiom.string;
use xiom.string.compare;
use xiom.convert;

// ---------------------------------------------------------------------------
// Node kinds
// ---------------------------------------------------------------------------

/// No node / unknown kind (the zero value; never produced by the builder).
pub const AST_KIND_NONE: Int = 0;

/// The root of a compilation unit.
pub const AST_KIND_PROGRAM: Int = 1;

/// `let name = expr` (the trailing ';' is not part of the span).
pub const AST_KIND_LET: Int = 2;

/// `if cond { ... } else { ... }`.
pub const AST_KIND_IF: Int = 3;

/// A `{ ... }` block of statements (braces included).
pub const AST_KIND_BLOCK: Int = 4;

/// `return expr` (the trailing ';' is not part of the span).
pub const AST_KIND_RETURN: Int = 5;

/// A binary operator application with exactly two children (left, right).
pub const AST_KIND_BINARY: Int = 6;

/// An identifier reference (label = the name text).
pub const AST_KIND_IDENT: Int = 7;

/// A literal (label = the literal text).
pub const AST_KIND_LITERAL: Int = 8;

// ---------------------------------------------------------------------------
// Node model
// ---------------------------------------------------------------------------

/// A tree (or forest) of AST nodes stored as seven parallel Vec fields.
///
/// Node i is fully described by (kinds[i], starts[i], ends[i]) plus its
/// structural links (parents[i], first_child[i], next_sibling[i]) and its
/// optional labels[i]. All seven arrays always have the same length; the
/// builder is the only writer that grows them.
///
/// A node with parents[i] == -1 is a root of the forest. Children of a node
/// form a singly linked chain: first_child[i] is the first child (insertion
/// order) and next_sibling[c] links to the next one, -1 terminating. The
/// span of node i is the byte range [starts[i], ends[i]) into some source
/// text; spans are metadata only and are never validated by the builder.
pub type Ast = {
  kinds: Vec[Int];
  starts: Vec[Int];
  ends: Vec[Int];
  parents: Vec[Int];
  first_child: Vec[Int];
  next_sibling: Vec[Int];
  labels: Vec[Str];
}

/// A fresh empty tree (all seven arrays empty).
/// Params: none.
/// Returns: the empty tree.
/// Error case: none.
/// Complexity: O(1).
pub fn ast_new() -> Ast {
  return Ast{
    kinds: Vec[Int].new();
    starts: Vec[Int].new();
    ends: Vec[Int].new();
    parents: Vec[Int].new();
    first_child: Vec[Int].new();
    next_sibling: Vec[Int].new();
    labels: Vec[Str].new();
  };
}

/// Append a new detached node (a forest root) with kind `kind` and span
/// [start, end). The span is stored verbatim: negative and inverted spans are
/// accepted and reported by ast_diagnostics, never trapped.
/// Params: t - the tree to grow; kind - an AST_KIND_* value; start, end - the
///         byte span.
/// Returns: the index of the new node.
/// Error case: none.
/// Complexity: O(1) amortized.
pub fn ast_add_node(t: &mut Ast, kind: Int, start: Int, end: Int) -> Int {
  let idx = t.kinds.len();
  t.kinds.push(kind);
  t.starts.push(start);
  t.ends.push(end);
  t.parents.push(-1);
  t.first_child.push(-1);
  t.next_sibling.push(-1);
  t.labels.push("");
  return idx;
}

/// Overwrite the span of node `i`.
/// Params: t - the tree; i - the node; start, end - the new byte span.
/// Returns: true when `i` is a valid node and the span was stored.
/// Error case: false and no change when `i` is out of range.
/// Complexity: O(1).
pub fn ast_set_span(t: &mut Ast, i: Int, start: Int, end: Int) -> Bool {
  if i < 0 || i >= t.kinds.len() {
    return false;
  }
  t.starts[i] = start;
  t.ends[i] = end;
  return true;
}

/// Overwrite the label of node `i` (an empty label is the default and is
/// omitted by the pretty-printer).
/// Params: t - the tree; i - the node; label - the new label text.
/// Returns: true when `i` is a valid node and the label was stored.
/// Error case: false and no change when `i` is out of range.
/// Complexity: O(1).
pub fn ast_set_label(t: &mut Ast, i: Int, label: Str) -> Bool {
  if i < 0 || i >= t.kinds.len() {
    return false;
  }
  t.labels[i] = label;
  return true;
}

// ---------------------------------------------------------------------------
// Field accessors (range-safe: never trap on out-of-range indices)
// ---------------------------------------------------------------------------

/// Number of nodes. Complexity: O(1).
pub fn ast_node_count(t: &Ast) -> Int {
  return t.kinds.len();
}

/// Kind of node `i`, or AST_KIND_NONE when `i` is out of range.
/// Complexity: O(1).
pub fn ast_kind(t: &Ast, i: Int) -> Int {
  if i < 0 || i >= t.kinds.len() {
    return AST_KIND_NONE;
  }
  let k: Int = t.kinds[i];
  return k;
}

/// Span start (inclusive) of node `i`, or -1 when `i` is out of range.
/// Complexity: O(1).
pub fn ast_span_start(t: &Ast, i: Int) -> Int {
  if i < 0 || i >= t.starts.len() {
    return -1;
  }
  let v: Int = t.starts[i];
  return v;
}

/// Span end (exclusive) of node `i`, or -1 when `i` is out of range.
/// Complexity: O(1).
pub fn ast_span_end(t: &Ast, i: Int) -> Int {
  if i < 0 || i >= t.ends.len() {
    return -1;
  }
  let v: Int = t.ends[i];
  return v;
}

/// Label of node `i`, or "" when `i` is out of range.
/// Complexity: O(1).
pub fn ast_label(t: &Ast, i: Int) -> Str {
  if i < 0 || i >= t.labels.len() {
    return "";
  }
  let s: Str = t.labels[i];
  return s;
}

/// Parent of node `i`: a node index, or -1 for a root / out-of-range `i`.
/// Complexity: O(1).
pub fn ast_parent(t: &Ast, i: Int) -> Int {
  if i < 0 || i >= t.parents.len() {
    return -1;
  }
  let v: Int = t.parents[i];
  return v;
}

/// First child of node `i` (insertion order), or -1 for a leaf /
/// out-of-range `i`.
/// Complexity: O(1).
pub fn ast_first_child(t: &Ast, i: Int) -> Int {
  if i < 0 || i >= t.first_child.len() {
    return -1;
  }
  let v: Int = t.first_child[i];
  return v;
}

/// Next sibling of node `i`, or -1 when `i` is last / out of range.
/// Complexity: O(1).
pub fn ast_next_sibling(t: &Ast, i: Int) -> Int {
  if i < 0 || i >= t.next_sibling.len() {
    return -1;
  }
  let v: Int = t.next_sibling[i];
  return v;
}

/// k-th child of node `i` in insertion order (k is 0-based), or -1 when `i`
/// is out of range, k < 0, or `i` has at most k children.
/// Complexity: O(k).
pub fn ast_child(t: &Ast, i: Int, k: Int) -> Int {
  let n = t.kinds.len();
  if i < 0 || i >= n {
    return -1;
  }
  if k < 0 {
    return -1;
  }
  var c: Int = t.first_child[i];
  var steps = 0;
  while c != -1 && steps < k {
    if c < 0 || c >= n {
      return -1;
    }
    c = t.next_sibling[c];
    steps = steps + 1;
  }
  if c < 0 || c >= n {
    return -1;
  }
  return c;
}

/// Number of children of node `i` (0 when out of range).
/// Complexity: O(children).
pub fn ast_child_count(t: &Ast, i: Int) -> Int {
  let n = t.kinds.len();
  if i < 0 || i >= n {
    return 0;
  }
  var count = 0;
  var c: Int = t.first_child[i];
  while c != -1 && count < n {
    if c < 0 || c >= n {
      return count;
    }
    count = count + 1;
    c = t.next_sibling[c];
  }
  return count;
}

/// True when node `i` is valid and has no children.
/// Complexity: O(1).
pub fn ast_is_leaf(t: &Ast, i: Int) -> Bool {
  if i < 0 || i >= t.kinds.len() {
    return false;
  }
  let fc: Int = t.first_child[i];
  return fc == -1;
}

/// Depth of node `i`: 0 for a root, +1 per parent hop; -1 when `i` is out of
/// range or sits on a corrupt parent chain.
/// Complexity: O(depth).
pub fn ast_depth(t: &Ast, i: Int) -> Int {
  let n = t.kinds.len();
  if i < 0 || i >= n {
    return -1;
  }
  var depth = 0;
  var cur: Int = t.parents[i];
  var steps = 0;
  while cur != -1 && steps <= n {
    if cur < 0 || cur >= n {
      return -1;
    }
    depth = depth + 1;
    cur = t.parents[cur];
    steps = steps + 1;
  }
  return depth;
}

/// True when node `a` is a strict ancestor of node `b` (a node is never its
/// own ancestor; out-of-range or corrupt chains yield false).
/// Complexity: O(depth).
pub fn ast_is_ancestor(t: &Ast, a: Int, b: Int) -> Bool {
  return _is_ancestor_ref(t, a, b);
}

// ---------------------------------------------------------------------------
// Structure queries
// ---------------------------------------------------------------------------

/// Indices of the forest roots (parent == -1), in index order.
/// Complexity: O(n).
pub fn ast_roots(t: &Ast) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 0;
  let n = t.kinds.len();
  while i < n {
    let p: Int = t.parents[i];
    if p == -1 {
      out.push(i);
    }
    i = i + 1;
  }
  return out;
}

/// Pre-order traversal of the whole forest: a node is emitted before its
/// children, children left-to-right, roots in index order. The result is a
/// permutation of 0..ast_node_count(t) for a tree built by this module.
/// A corrupt tree is walked no further than one visit per node.
/// Complexity: O(n + total children).
pub fn ast_preorder(t: &Ast) -> Vec[Int] {
  var out = Vec[Int].new();
  let n = t.kinds.len();
  var stack = Vec[Int].new();
  let roots = ast_roots(t);
  var i = roots.len() - 1;
  while i >= 0 {
    let r: Int = roots[i];
    stack.push(r);
    i = i - 1;
  }
  var budget = n + 1;
  while stack.len() > 0 {
    if budget <= 0 {
      return out;
    }
    budget = budget - 1;
    let top = stack.pop();
    match top {
      Some(cur) => {
        out.push(cur);
        let kids = _children_of(t, cur);
        var k = kids.len() - 1;
        while k >= 0 {
          let c: Int = kids[k];
          stack.push(c);
          k = k - 1;
        }
      },
      None => { return out; },
    }
  }
  return out;
}

/// Post-order traversal of the whole forest: children left-to-right before
/// their parent; forest roots in index order. A corrupt tree is walked no
/// further than one visit per node.
/// Complexity: O(n + total children).
pub fn ast_postorder(t: &Ast) -> Vec[Int] {
  var rev = Vec[Int].new();
  let n = t.kinds.len();
  var stack = Vec[Int].new();
  let roots = ast_roots(t);
  var i = 0;
  while i < roots.len() {
    let r: Int = roots[i];
    stack.push(r);
    i = i + 1;
  }
  var budget = n + 1;
  while stack.len() > 0 {
    if budget <= 0 {
      break;
    }
    budget = budget - 1;
    let top = stack.pop();
    match top {
      Some(cur) => {
        rev.push(cur);
        let kids = _children_of(t, cur);
        var k = 0;
        while k < kids.len() {
          let c: Int = kids[k];
          stack.push(c);
          k = k + 1;
        }
      },
      None => { break; },
    }
  }
  var out = Vec[Int].new();
  var j = rev.len() - 1;
  while j >= 0 {
    let v: Int = rev[j];
    out.push(v);
    j = j - 1;
  }
  return out;
}

// ---------------------------------------------------------------------------
// Structure mutation (builder)
// ---------------------------------------------------------------------------

/// Attach the fresh node `child` as the LAST child of `parent`. `child` must
/// currently be a root (parents[child] == -1); moving an already-attached
/// node is ast_reparent's job. Cycles are refused.
/// Params: t - the tree; parent - the node that receives a child; child - the
///         currently detached node.
/// Returns: true when the link was made.
/// Error case: false and no change when either index is out of range,
/// parent == child, `child` already has a parent, or `child` is an ancestor
/// of `parent` (which would create a cycle).
/// Complexity: O(children of parent + depth).
pub fn ast_add_child(t: &mut Ast, parent: Int, child: Int) -> Bool {
  let n = t.kinds.len();
  if parent < 0 || parent >= n {
    return false;
  }
  if child < 0 || child >= n {
    return false;
  }
  if parent == child {
    return false;
  }
  let p: Int = t.parents[child];
  if p != -1 {
    return false;
  }
  if _is_ancestor_mut(t, child, parent) {
    return false;
  }
  _append_child_mut(t, parent, child);
  t.parents[child] = parent;
  return true;
}

/// Move node `child` under `new_parent`, or detach it to a forest root when
/// `new_parent` == -1. The child is removed from its old parent's chain and
/// appended as the last child of the new parent. Cycles are refused.
/// Params: t - the tree; child - the node to move; new_parent - the new
///         parent, or -1 to detach.
/// Returns: true when the move succeeded (a no-op move also returns true).
/// Error case: false and no change when either index is out of range,
/// new_parent == child, or `child` is an ancestor of `new_parent`.
/// Complexity: O(children + depth).
pub fn ast_reparent(t: &mut Ast, child: Int, new_parent: Int) -> Bool {
  let n = t.kinds.len();
  if child < 0 || child >= n {
    return false;
  }
  if new_parent < -1 || new_parent >= n {
    return false;
  }
  if new_parent == child {
    return false;
  }
  let old: Int = t.parents[child];
  if new_parent != -1 {
    if _is_ancestor_mut(t, child, new_parent) {
      return false;
    }
  }
  if old == new_parent {
    return true;
  }
  if old != -1 {
    _unlink_child_mut(t, old, child);
  }
  t.next_sibling[child] = -1;
  if new_parent != -1 {
    _append_child_mut(t, new_parent, child);
  }
  t.parents[child] = new_parent;
  return true;
}

// ---------------------------------------------------------------------------
// Names, counting, spans
// ---------------------------------------------------------------------------

/// Human-readable name of an AST_KIND_* value ("program", "let", "if",
/// "block", "return", "binary", "ident", "literal", or "none").
/// Complexity: O(1).
pub fn ast_kind_name(kind: Int) -> Str {
  if kind == AST_KIND_PROGRAM {
    return "program";
  }
  if kind == AST_KIND_LET {
    return "let";
  }
  if kind == AST_KIND_IF {
    return "if";
  }
  if kind == AST_KIND_BLOCK {
    return "block";
  }
  if kind == AST_KIND_RETURN {
    return "return";
  }
  if kind == AST_KIND_BINARY {
    return "binary";
  }
  if kind == AST_KIND_IDENT {
    return "ident";
  }
  if kind == AST_KIND_LITERAL {
    return "literal";
  }
  return "none";
}

/// Number of nodes whose kind equals `kind`.
/// Complexity: O(n).
pub fn ast_count_kind(t: &Ast, kind: Int) -> Int {
  var count = 0;
  var i = 0;
  while i < t.kinds.len() {
    let k: Int = t.kinds[i];
    if k == kind {
      count = count + 1;
    }
    i = i + 1;
  }
  return count;
}

/// Number of leaf nodes (no children).
/// Complexity: O(n).
pub fn ast_leaf_count(t: &Ast) -> Int {
  var count = 0;
  var i = 0;
  while i < t.kinds.len() {
    let fc: Int = t.first_child[i];
    if fc == -1 {
      count = count + 1;
    }
    i = i + 1;
  }
  return count;
}

/// Raw source slice of node `i`'s span, [starts[i], ends[i]); out-of-range
/// `i` yields "" and inverted spans clamp exactly like xiom.string.str_slice.
/// Params: source - the text the spans refer to; t - the tree; i - the node.
/// Returns: the slice, possibly "".
/// Error case: none.
/// Complexity: O(span length).
pub fn ast_span_text(source: Str, t: &Ast, i: Int) -> Str {
  if i < 0 || i >= t.kinds.len() {
    return "";
  }
  let s: Int = t.starts[i];
  let e: Int = t.ends[i];
  return string.str_slice(source, s, e);
}

/// One span-table row for node `i`:
/// "<i>: <kind> [<start>,<end>) parent=<p> depth=<d>"; "" when `i` is out of
/// range.
/// Complexity: O(depth).
pub fn ast_span_row(t: &Ast, i: Int) -> Str {
  if i < 0 || i >= t.kinds.len() {
    return "";
  }
  let k: Int = t.kinds[i];
  let s: Int = t.starts[i];
  let e: Int = t.ends[i];
  let p: Int = t.parents[i];
  let d = ast_depth(t, i);
  return int_to_string(i) + ": " + ast_kind_name(k) + " [" + int_to_string(s) + "," + int_to_string(e) + ")" + " parent=" + int_to_string(p) + " depth=" + int_to_string(d);
}

/// Span table: one ast_span_row per node in INDEX order (storage order, not
/// traversal order).
/// Complexity: O(n * depth).
pub fn ast_span_table(t: &Ast) -> Vec[Str] {
  var out = Vec[Str].new();
  var i = 0;
  while i < t.kinds.len() {
    out.push(ast_span_row(t, i));
    i = i + 1;
  }
  return out;
}

// ---------------------------------------------------------------------------
// Pretty-printing and diagnostics
// ---------------------------------------------------------------------------

/// Canonical pretty-print of the whole forest in PRE-ORDER, one node per
/// line, 2 spaces of indentation per depth level, and a trailing newline
/// after every line. A line is:
/// `<indent><kind>[ <label>] [<start>,<end>)`
/// where the label is omitted when empty. An empty tree prints "".
/// Complexity: O(n * depth).
pub fn ast_pretty(t: &Ast) -> Str {
  var out = "";
  let order = ast_preorder(t);
  var i = 0;
  while i < order.len() {
    let idx: Int = order[i];
    let depth = ast_depth(t, idx);
    var indent = "";
    var d = 0;
    while d < depth {
      indent = indent + "  ";
      d = d + 1;
    }
    var line = indent + ast_kind_name(ast_kind(t, idx));
    let label: Str = t.labels[idx];
    if compare.str_compare(label, "") != 0 {
      line = line + " " + label;
    }
    line = line + " [" + int_to_string(ast_span_start(t, idx)) + "," + int_to_string(ast_span_end(t, idx)) + ")\n";
    out = out + line;
    i = i + 1;
  }
  return out;
}

/// Span diagnostics, one message per offending node in INDEX order:
///   "ast: node <i> has negative span [<s>,<e>)" when s < 0 or e < 0,
///   "ast: node <i> has inverted span [<s>,<e>)" when s > e.
/// A clean tree yields an empty vector.
/// Complexity: O(n).
pub fn ast_diagnostics(t: &Ast) -> Vec[Str] {
  var out = Vec[Str].new();
  var i = 0;
  while i < t.kinds.len() {
    let s: Int = t.starts[i];
    let e: Int = t.ends[i];
    if s < 0 || e < 0 {
      out.push("ast: node " + int_to_string(i) + " has negative span [" + int_to_string(s) + "," + int_to_string(e) + ")");
    } elif s > e {
      out.push("ast: node " + int_to_string(i) + " has inverted span [" + int_to_string(s) + "," + int_to_string(e) + ")");
    }
    i = i + 1;
  }
  return out;
}

/// Structural integrity check: every parent/sibling/child index is in range
/// and consistent (child links agree with parents, siblings share a parent),
/// and the pre-order traversal visits every node exactly once (no cycles, no
/// duplicates, no orphans). The builder below always maintains this.
/// Complexity: O(n + total children).
pub fn ast_is_well_formed(t: &Ast) -> Bool {
  let n = t.kinds.len();
  if n == 0 {
    return true;
  }
  var i = 0;
  while i < n {
    let p: Int = t.parents[i];
    if p < -1 || p >= n {
      return false;
    }
    if p == i {
      return false;
    }
    let ns: Int = t.next_sibling[i];
    if ns != -1 {
      if ns < 0 || ns >= n {
        return false;
      }
      if ns == i {
        return false;
      }
      let pns: Int = t.parents[ns];
      if pns != p {
        return false;
      }
    }
    let fc: Int = t.first_child[i];
    if fc != -1 {
      if fc < 0 || fc >= n {
        return false;
      }
      if fc == i {
        return false;
      }
      let pfc: Int = t.parents[fc];
      if pfc != i {
        return false;
      }
    }
    i = i + 1;
  }
  let order = ast_preorder(t);
  if order.len() != n {
    return false;
  }
  var marks = Vec[Int].new();
  var m = 0;
  while m < n {
    marks.push(0);
    m = m + 1;
  }
  var j = 0;
  while j < order.len() {
    let idx: Int = order[j];
    let seen: Int = marks[idx];
    if seen != 0 {
      return false;
    }
    marks[idx] = 1;
    j = j + 1;
  }
  return true;
}

// ---------------------------------------------------------------------------
// Fixture grammar
// ---------------------------------------------------------------------------

/// The fixed 52-byte fixture source the spans in ast_fixture_ast refer to:
/// "let x = 1 + 2;\nif x { return x; } else { return 0; }".
/// Complexity: O(1).
pub fn ast_fixture_source() -> Str {
  return "let x = 1 + 2;\nif x { return x; } else { return 0; }";
}

/// The 14-node fixture AST over ast_fixture_source(). Nodes are created in a
/// deliberately non-preorder sequence, so traversals are not trivial:
///   index 0  literal "1"      [8,9)    parent 2
///   index 1  literal "2"      [12,13)  parent 2
///   index 2  binary  "+"      [8,13)   parent 4
///   index 3  ident   "x"      [4,5)    parent 4
///   index 4  let              [0,13)   parent 13
///   index 5  ident   "x"      [18,19)  parent 12
///   index 6  return           [22,30)  parent 8
///   index 7  ident   "x"      [29,30)  parent 6
///   index 8  block            [20,33)  parent 12
///   index 9  return           [41,49)  parent 11
///   index 10 literal "0"      [48,49)  parent 9
///   index 11 block            [39,52)  parent 12
///   index 12 if               [15,52)  parent 13
///   index 13 program          [0,52)   root
/// Pre-order: 13,4,3,2,0,1,12,5,8,6,7,11,9,10.
/// Complexity: O(1).
pub fn ast_fixture_ast() -> Ast {
  var t = ast_new();
  let lit1 = ast_add_node(&mut t, AST_KIND_LITERAL, 8, 9);
  let lit2 = ast_add_node(&mut t, AST_KIND_LITERAL, 12, 13);
  let bin = ast_add_node(&mut t, AST_KIND_BINARY, 8, 13);
  let lhs = ast_add_node(&mut t, AST_KIND_IDENT, 4, 5);
  let letn = ast_add_node(&mut t, AST_KIND_LET, 0, 13);
  let cond = ast_add_node(&mut t, AST_KIND_IDENT, 18, 19);
  let ret_then = ast_add_node(&mut t, AST_KIND_RETURN, 22, 30);
  let then_x = ast_add_node(&mut t, AST_KIND_IDENT, 29, 30);
  let then_block = ast_add_node(&mut t, AST_KIND_BLOCK, 20, 33);
  let ret_else = ast_add_node(&mut t, AST_KIND_RETURN, 41, 49);
  let else_0 = ast_add_node(&mut t, AST_KIND_LITERAL, 48, 49);
  let else_block = ast_add_node(&mut t, AST_KIND_BLOCK, 39, 52);
  let ifn = ast_add_node(&mut t, AST_KIND_IF, 15, 52);
  let prog = ast_add_node(&mut t, AST_KIND_PROGRAM, 0, 52);
  let _ = ast_set_label(&mut t, lit1, "1");
  let _ = ast_set_label(&mut t, lit2, "2");
  let _ = ast_set_label(&mut t, bin, "+");
  let _ = ast_set_label(&mut t, lhs, "x");
  let _ = ast_set_label(&mut t, cond, "x");
  let _ = ast_set_label(&mut t, then_x, "x");
  let _ = ast_set_label(&mut t, else_0, "0");
  let _ = ast_add_child(&mut t, bin, lit1);
  let _ = ast_add_child(&mut t, bin, lit2);
  let _ = ast_add_child(&mut t, letn, lhs);
  let _ = ast_add_child(&mut t, letn, bin);
  let _ = ast_add_child(&mut t, ret_then, then_x);
  let _ = ast_add_child(&mut t, then_block, ret_then);
  let _ = ast_add_child(&mut t, ret_else, else_0);
  let _ = ast_add_child(&mut t, else_block, ret_else);
  let _ = ast_add_child(&mut t, ifn, cond);
  let _ = ast_add_child(&mut t, ifn, then_block);
  let _ = ast_add_child(&mut t, ifn, else_block);
  let _ = ast_add_child(&mut t, prog, letn);
  let _ = ast_add_child(&mut t, prog, ifn);
  return t;
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

// Ancestor walk on a shared tree: true when `a` is a strict ancestor of `b`.
// Corrupt chains stop at the node budget and yield false.
fn _is_ancestor_ref(t: &Ast, a: Int, b: Int) -> Bool {
  let n = t.kinds.len();
  if a < 0 || b < 0 || a >= n || b >= n {
    return false;
  }
  if a == b {
    return false;
  }
  var cur: Int = t.parents[b];
  var steps = 0;
  while cur != -1 && steps <= n {
    if cur == a {
      return true;
    }
    if cur < 0 || cur >= n {
      return false;
    }
    cur = t.parents[cur];
    steps = steps + 1;
  }
  return false;
}

// Same walk as _is_ancestor_ref but &mut-taking: mutators call only &mut
// helpers on the tree before their own &mut field accesses (advisory E001).
fn _is_ancestor_mut(t: &mut Ast, a: Int, b: Int) -> Bool {
  let n = t.kinds.len();
  if a < 0 || b < 0 || a >= n || b >= n {
    return false;
  }
  if a == b {
    return false;
  }
  var cur: Int = t.parents[b];
  var steps = 0;
  while cur != -1 && steps <= n {
    if cur == a {
      return true;
    }
    if cur < 0 || cur >= n {
      return false;
    }
    cur = t.parents[cur];
    steps = steps + 1;
  }
  return false;
}

// Children of node `i` as a fresh Vec, insertion order; corrupt chains stop
// after one step per node. Used by both traversals.
fn _children_of(t: &Ast, i: Int) -> Vec[Int] {
  var out = Vec[Int].new();
  let n = t.kinds.len();
  if i < 0 || i >= n {
    return out;
  }
  var c: Int = t.first_child[i];
  var steps = 0;
  while c != -1 && steps < n {
    if c < 0 || c >= n {
      return out;
    }
    out.push(c);
    c = t.next_sibling[c];
    steps = steps + 1;
  }
  return out;
}

// Last node in the child chain of `parent`, or -1 when childless.
fn _last_child_of_mut(t: &mut Ast, parent: Int) -> Int {
  let n = t.kinds.len();
  if parent < 0 || parent >= n {
    return -1;
  }
  var c: Int = t.first_child[parent];
  if c == -1 {
    return -1;
  }
  var steps = 0;
  while steps < n {
    let nxt: Int = t.next_sibling[c];
    if nxt == -1 {
      return c;
    }
    if nxt < 0 || nxt >= n {
      return c;
    }
    c = nxt;
    steps = steps + 1;
  }
  return c;
}

// Append `child` as the last child of `parent`. Caller guarantees both
// indices are valid and next_sibling[child] == -1.
fn _append_child_mut(t: &mut Ast, parent: Int, child: Int) {
  let fc: Int = t.first_child[parent];
  if fc == -1 {
    t.first_child[parent] = child;
    return;
  }
  let last = _last_child_of_mut(t, parent);
  t.next_sibling[last] = child;
}

// Unlink `child` from the child chain of `parent` (no-op when absent).
fn _unlink_child_mut(t: &mut Ast, parent: Int, child: Int) -> Bool {
  let fc: Int = t.first_child[parent];
  if fc == -1 {
    return false;
  }
  if fc == child {
    let nxt: Int = t.next_sibling[child];
    t.first_child[parent] = nxt;
    return true;
  }
  let n = t.kinds.len();
  var prev: Int = fc;
  var steps = 0;
  while steps < n {
    let nxt: Int = t.next_sibling[prev];
    if nxt == -1 {
      return false;
    }
    if nxt < 0 || nxt >= n {
      return false;
    }
    if nxt == child {
      let after: Int = t.next_sibling[child];
      t.next_sibling[prev] = after;
      return true;
    }
    prev = nxt;
    steps = steps + 1;
  }
  return false;
}
