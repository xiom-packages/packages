// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// XIOM -- xiom.formatter_fw: a Wadler/Leijen-style pretty-printing framework
// over an explicit document model.
//
// Scope: a deterministic, IO-free document algebra plus a greedy line-break
// renderer. Callers build a document as an arena (FmtDoc) of concrete nodes --
// no closures, no fn-pointer values, no Vec[StructType] and no generic
// callbacks -- and render it to a Str with an integer page width.
//
// Document model (kinds):
//   * TEXT     -- verbatim text. Its byte length is recorded at build time
//                 and is the only width it contributes. When the text embeds
//                 CR or LF bytes it is treated as containing a break: it can
//                 never be flattened, and the renderer tracks the column from
//                 the byte after its last CR/LF. The bytes are always emitted
//                 verbatim (no indentation is inserted after an embedded
//                 break; use HARDLINE for layout-owned breaks).
//   * LINE     -- a break opportunity: one space when flat, a newline plus
//                 indentation when broken.
//   * SOFTLINE -- a break opportunity with no space when flat, a newline plus
//                 indentation when broken.
//   * HARDLINE -- an unconditional break opportunity: always emits a newline
//                 plus indentation. A subtree containing a hardline can never
//                 be flattened, so every group over it always breaks.
//   * CONCAT   -- ordered pair: child_a then child_b.
//   * NEST(n)  -- render child_a with indentation increased by n (the total
//                 is clamped at 0); only line breaks observe indentation.
//   * GROUP    -- render child_a flat when it fits, broken otherwise.
//   * ALIGN    -- render child_a with indentation set to the column reached
//                 when the align node itself is rendered.
//   * NIL      -- the empty document; the identity of CONCAT.
//
// Layout algorithm (greedy, local, deterministic, total):
//   1. The renderer walks the document with an explicit work stack of
//      (indent, mode, node) triples; mode is FLAT or BREAK. The root starts
//      broken with indent 0 and column 0. Each iteration pops exactly one
//      item (the three parallel stack Vecs are popped in lockstep) and pushes
//      the item's children, so the stack length is the single source of
//      truth for progress; a mismatched stack length also stops the walk.
//      Both traversals are additionally capped at FMT_STEP_LIMIT pops.
//   2. TEXT emits its bytes; the column advances by the recorded byte length,
//      or to the number of bytes after the last CR/LF when the text embeds a
//      break.
//   3. LINE emits a space in FLAT mode and a newline + `indent` spaces in
//      BREAK mode. SOFTLINE emits nothing in FLAT mode and a newline +
//      `indent` spaces in BREAK mode. HARDLINE always does the BREAK-mode
//      thing, whatever the mode.
//   4. CONCAT pushes both children with the current indent and mode. NEST
//      adds its delta to the indent (clamped at 0). ALIGN replaces the
//      indent with the current column.
//   5. A GROUP reached in BREAK mode is flattened exactly when its child's
//      flat width is finite (strictly below FMT_WIDTH_INFINITE) and fits the
//      remaining width: flat_width(child) <= width - column. An exact fit
//      (equality) counts as fitting. Otherwise the child is pushed with
//      BREAK mode. A GROUP reached in FLAT mode stays flat.
//   6. flat_width is the fully flattened byte width of a subtree: TEXT gives
//      its recorded byte length, or FMT_WIDTH_INFINITE when it embeds CR/LF;
//      LINE gives 1; SOFTLINE and NIL give 0; HARDLINE gives
//      FMT_WIDTH_INFINITE; CONCAT gives the saturated sum of its children;
//      NEST, GROUP and ALIGN are transparent (the child's flat width).
//   Every group decides independently -- the fit test is the group's own
//   flattened subtree, not a lookahead over the rest of the line -- so the
//   layout is greedy and local: an outer group may break while an inner group
//   on the same line stays flat. `width` is clamped to >= 0. Out-of-range
//   node indices are empty documents: they render nothing and have flat
//   width 0.
//
// Complexity: building a node is O(1); rendering performs O(nodes) stack
// steps, and each group evaluated in BREAK mode costs one flat-width scan of
// its subtree, so a render is O(nodes^2) in the worst case (O(nodes) for
// documents without groups). Text emission accumulates with Str concat.
//
// Language notes (XIOM v0.62.1): free functions only; the arena holds seven
// parallel Vec fields fed by one push site, so they cannot drift; text byte
// lengths are recorded at build time, so no Str read back from the arena is
// ever measured with `.len()` outside a function parameter; bytes read back
// for embedded-break detection go through a typed UInt8 local widened with
// `(b as Int) & 0xFF` before comparison; every Int read from a Vec goes
// through a typed local; no Result/Ok/Err values; no generic angle-bracket
// spellings anywhere.

module xiom.formatter_fw

use xiom.string;

// ---------------------------------------------------------------------------
// Render modes
// ---------------------------------------------------------------------------

/// Flat mode: LINE renders as one space, SOFTLINE as nothing.
pub const FMT_MODE_FLAT: Int = 0;

/// Break mode: LINE and SOFTLINE render as a newline plus indentation.
pub const FMT_MODE_BREAK: Int = 1;

// ---------------------------------------------------------------------------
// Node kinds
// ---------------------------------------------------------------------------

/// Lookup miss / unbuilt slot; contributes nothing.
pub const FMT_KIND_NONE: Int = 0;

/// The empty document; the identity of CONCAT.
pub const FMT_KIND_NIL: Int = 1;

/// Verbatim text; carries the text plus its byte length and break flag.
pub const FMT_KIND_TEXT: Int = 2;

/// Break opportunity that is one space when flat.
pub const FMT_KIND_LINE: Int = 3;

/// Break opportunity that is nothing when flat.
pub const FMT_KIND_SOFTLINE: Int = 4;

/// Unconditional break; never flattened.
pub const FMT_KIND_HARDLINE: Int = 5;

/// Ordered concatenation: child_a then child_b.
pub const FMT_KIND_CONCAT: Int = 6;

/// child_a rendered with the indentation increased by `indents[i]`.
pub const FMT_KIND_NEST: Int = 7;

/// child_a rendered flat when it fits, broken otherwise.
pub const FMT_KIND_GROUP: Int = 8;

/// child_a rendered with the indentation set to the current column.
pub const FMT_KIND_ALIGN: Int = 9;

/// Sentinel flat width of a subtree that can never be flattened (it contains
/// a hardline, or a text with an embedded CR/LF), and the saturation bound
/// for flat-width sums.
pub const FMT_WIDTH_INFINITE: Int = 1073741823;

/// Iteration budget of the two document traversals (fmt_flat_width and
/// fmt_render): each traversal step pops exactly one work item, so an acyclic
/// document is walked in at most one step per root-to-node path. The cap is a
/// totality guard: builders cannot create cycles (every node references only
/// previously created nodes), but the bound is made explicit so neither
/// traversal can ever spin. When the budget is exhausted, fmt_flat_width
/// returns FMT_WIDTH_INFINITE (conservative: never flattened) and fmt_render
/// returns the text produced so far; both outcomes are deterministic.
pub const FMT_STEP_LIMIT: Int = 1048576;

// ---------------------------------------------------------------------------
// Values
// ---------------------------------------------------------------------------

/// The document arena. Node i is fully described by index i in each of the
/// seven parallel Vec fields:
///   kinds[i]        FMT_KIND_*
///   texts[i]        TEXT payload ("" otherwise)
///   text_lens[i]    TEXT byte length, recorded at build time
///   text_breaks[i]  1 when texts[i] embeds CR or LF, else 0
///   indents[i]      NEST delta
///   child_a[i]      first child index (-1 when unused)
///   child_b[i]      second child index (-1 when unused)
/// All seven are pushed together by _doc_push, so they cannot drift.
pub type FmtDoc = {
  kinds: Vec[Int];
  texts: Vec[Str];
  text_lens: Vec[Int];
  text_breaks: Vec[Int];
  indents: Vec[Int];
  child_a: Vec[Int];
  child_b: Vec[Int];
}

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

// The single push site for all seven parallel Vec fields: node <-> field
// alignment is structural, not a convention at each builder.
fn _doc_push(g: &mut FmtDoc, kind: Int, text: Str, tlen: Int, tbreak: Int, indent: Int, a: Int, b: Int) -> Int {
  let id = g.kinds.len();
  g.kinds.push(kind);
  g.texts.push(text);
  g.text_lens.push(tlen);
  g.text_breaks.push(tbreak);
  g.indents.push(indent);
  g.child_a.push(a);
  g.child_b.push(b);
  return id;
}

/// An empty arena (no nodes). Params: none. Returns: a fresh document arena.
/// Complexity: O(1).
pub fn fmt_doc_new() -> FmtDoc {
  return FmtDoc{
    kinds: Vec[Int].new();
    texts: Vec[Str].new();
    text_lens: Vec[Int].new();
    text_breaks: Vec[Int].new();
    indents: Vec[Int].new();
    child_a: Vec[Int].new();
    child_b: Vec[Int].new();
  };
}

/// Number of nodes in the arena. Complexity: O(1).
pub fn fmt_node_count(g: &FmtDoc) -> Int {
  return g.kinds.len();
}

/// True when all seven parallel Vec fields have the same length.
/// Params: g - the arena to check. Returns: the invariant's truth value.
/// Complexity: O(1).
pub fn fmt_is_consistent(g: &FmtDoc) -> Bool {
  let n = g.kinds.len();
  if g.texts.len() != n {
    return false;
  }
  if g.text_lens.len() != n {
    return false;
  }
  if g.text_breaks.len() != n {
    return false;
  }
  if g.indents.len() != n {
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

/// Add the empty document (NIL). Params: g - the arena (mutated).
/// Returns: the new node index. Complexity: O(1).
pub fn fmt_nil(g: &mut FmtDoc) -> Int {
  return _doc_push(g, FMT_KIND_NIL, "", 0, 0, 0, -1, -1);
}

/// Add a verbatim-text node. The byte length and the embedded-break flag are
/// computed once, here; rendering never measures the text again.
/// Params: g - the arena (mutated); text - the payload.
/// Returns: the new node index. Complexity: O(text bytes).
pub fn fmt_text(g: &mut FmtDoc, text: Str) -> Int {
  let n = text.len();
  var brk = 0;
  if _text_has_break(text) {
    brk = 1;
  }
  return _doc_push(g, FMT_KIND_TEXT, text, n, brk, 0, -1, -1);
}

/// Add a LINE break opportunity (one space when flat).
/// Params: g - the arena (mutated). Returns: the new node index.
/// Complexity: O(1).
pub fn fmt_line(g: &mut FmtDoc) -> Int {
  return _doc_push(g, FMT_KIND_LINE, "", 0, 0, 0, -1, -1);
}

/// Add a SOFTLINE break opportunity (nothing when flat).
/// Params: g - the arena (mutated). Returns: the new node index.
/// Complexity: O(1).
pub fn fmt_softline(g: &mut FmtDoc) -> Int {
  return _doc_push(g, FMT_KIND_SOFTLINE, "", 0, 0, 0, -1, -1);
}

/// Add a HARDLINE unconditional break.
/// Params: g - the arena (mutated). Returns: the new node index.
/// Complexity: O(1).
pub fn fmt_hardline(g: &mut FmtDoc) -> Int {
  return _doc_push(g, FMT_KIND_HARDLINE, "", 0, 0, 0, -1, -1);
}

/// Add a CONCAT node: child_a then child_b.
/// Params: g - the arena (mutated); a/b - child node indices.
/// Returns: the new node index. Complexity: O(1).
pub fn fmt_concat(g: &mut FmtDoc, a: Int, b: Int) -> Int {
  return _doc_push(g, FMT_KIND_CONCAT, "", 0, 0, 0, a, b);
}

/// Add a NEST node: child a rendered with indentation + `indent`.
/// Params: g - the arena (mutated); a - the child; indent - the delta (may be
///         negative; the resulting indentation is clamped at 0).
/// Returns: the new node index. Complexity: O(1).
pub fn fmt_nest(g: &mut FmtDoc, a: Int, indent: Int) -> Int {
  return _doc_push(g, FMT_KIND_NEST, "", 0, 0, indent, a, -1);
}

/// Add a GROUP node: child a rendered flat when it fits.
/// Params: g - the arena (mutated); a - the child.
/// Returns: the new node index. Complexity: O(1).
pub fn fmt_group(g: &mut FmtDoc, a: Int) -> Int {
  return _doc_push(g, FMT_KIND_GROUP, "", 0, 0, 0, a, -1);
}

/// Add an ALIGN node: child a rendered with indentation = current column.
/// Params: g - the arena (mutated); a - the child.
/// Returns: the new node index. Complexity: O(1).
pub fn fmt_align(g: &mut FmtDoc, a: Int) -> Int {
  return _doc_push(g, FMT_KIND_ALIGN, "", 0, 0, 0, a, -1);
}

/// Fold a list of document nodes into one with `sep` between consecutive
/// elements. An empty list yields a fresh NIL node; a single-element list
/// returns that element unchanged (no new node); a longer list is a
/// left-nested CONCAT chain: ((id0 sep id1) sep id2) ...
/// Params: g - the arena (mutated); ids - the element node indices; sep - the
///         separator node index.
/// Returns: the combined node index.
/// Complexity: O(elements).
pub fn fmt_join(g: &mut FmtDoc, ids: &Vec[Int], sep: Int) -> Int {
  let n = ids.len();
  if n == 0 {
    return fmt_nil(g);
  }
  let first: Int = ids[0];
  if n == 1 {
    return first;
  }
  var acc: Int = first;
  var i: Int = 1;
  while i < n {
    let id: Int = ids[i];
    let joined = fmt_concat(g, acc, sep);
    acc = fmt_concat(g, joined, id);
    i = i + 1;
  }
  return acc;
}

// ---------------------------------------------------------------------------
// Introspection (range-safe; defaults on out-of-range indices)
// ---------------------------------------------------------------------------

/// Kind of node i, or FMT_KIND_NONE when out of range. Complexity: O(1).
pub fn fmt_node_kind(g: &FmtDoc, i: Int) -> Int {
  if i < 0 || i >= g.kinds.len() {
    return FMT_KIND_NONE;
  }
  let v: Int = g.kinds[i];
  return v;
}

/// Text payload of node i, or "" when out of range or not a TEXT node.
/// Complexity: O(1).
pub fn fmt_node_text(g: &FmtDoc, i: Int) -> Str {
  if i < 0 || i >= g.texts.len() {
    return "";
  }
  let v: Str = g.texts[i];
  return v;
}

/// Recorded byte length of the text of node i, or 0 when out of range.
/// Complexity: O(1).
pub fn fmt_text_len(g: &FmtDoc, i: Int) -> Int {
  if i < 0 || i >= g.text_lens.len() {
    return 0;
  }
  let v: Int = g.text_lens[i];
  return v;
}

/// True when the text of node i embeds a CR or LF byte (such a text can never
/// be flattened). False when out of range or not a TEXT node. O(1).
pub fn fmt_text_has_break(g: &FmtDoc, i: Int) -> Bool {
  if i < 0 || i >= g.text_breaks.len() {
    return false;
  }
  let v: Int = g.text_breaks[i];
  return v != 0;
}

/// NEST delta of node i, or 0 when out of range. Complexity: O(1).
pub fn fmt_node_indent(g: &FmtDoc, i: Int) -> Int {
  if i < 0 || i >= g.indents.len() {
    return 0;
  }
  let v: Int = g.indents[i];
  return v;
}

/// child_a of node i, or -1 when out of range. Complexity: O(1).
pub fn fmt_node_child_a(g: &FmtDoc, i: Int) -> Int {
  if i < 0 || i >= g.child_a.len() {
    return -1;
  }
  let v: Int = g.child_a[i];
  return v;
}

/// child_b of node i, or -1 when out of range. Complexity: O(1).
pub fn fmt_node_child_b(g: &FmtDoc, i: Int) -> Int {
  if i < 0 || i >= g.child_b.len() {
    return -1;
  }
  let v: Int = g.child_b[i];
  return v;
}

/// Name of a node kind constant ("nil", "text", "line", "softline",
/// "hardline", "concat", "nest", "group", "align", "none").
/// Params: kind - an FMT_KIND_* value. Complexity: O(1).
pub fn fmt_kind_name(kind: Int) -> Str {
  if kind == FMT_KIND_NIL {
    return "nil";
  }
  if kind == FMT_KIND_TEXT {
    return "text";
  }
  if kind == FMT_KIND_LINE {
    return "line";
  }
  if kind == FMT_KIND_SOFTLINE {
    return "softline";
  }
  if kind == FMT_KIND_HARDLINE {
    return "hardline";
  }
  if kind == FMT_KIND_CONCAT {
    return "concat";
  }
  if kind == FMT_KIND_NEST {
    return "nest";
  }
  if kind == FMT_KIND_GROUP {
    return "group";
  }
  if kind == FMT_KIND_ALIGN {
    return "align";
  }
  return "none";
}

/// Name of a render mode constant ("flat", "break", "none").
/// Params: mode - an FMT_MODE_* value. Complexity: O(1).
pub fn fmt_mode_name(mode: Int) -> Str {
  if mode == FMT_MODE_FLAT {
    return "flat";
  }
  if mode == FMT_MODE_BREAK {
    return "break";
  }
  return "none";
}

// ---------------------------------------------------------------------------
// Flat width
// ---------------------------------------------------------------------------

/// Fully flattened byte width of the subtree rooted at `node`:
/// TEXT -> its recorded byte length, or FMT_WIDTH_INFINITE when the text
/// embeds CR/LF; LINE -> 1; SOFTLINE / NIL / NONE -> 0; HARDLINE ->
/// FMT_WIDTH_INFINITE; CONCAT -> the saturated sum of its children; NEST,
/// GROUP and ALIGN -> the child's flat width. Out-of-range indices give 0.
/// Params: g - the arena; node - the subtree root.
/// Returns: the flat width, saturated at FMT_WIDTH_INFINITE (or
///          FMT_WIDTH_INFINITE when FMT_STEP_LIMIT is exhausted).
/// Complexity: O(nodes in the subtree); iterative, no recursion.
pub fn fmt_flat_width(g: &FmtDoc, node: Int) -> Int {
  var acc: Int = 0;
  var stack: Vec[Int] = Vec[Int].new();
  stack.push(node);
  var steps: Int = 0;
  var running: Bool = true;
  while running {
    let total = stack.len();
    if total == 0 {
      running = false;
    } else if steps >= FMT_STEP_LIMIT {
      acc = FMT_WIDTH_INFINITE;
      running = false;
    } else {
      steps = steps + 1;
      let idx = total - 1;
      let n: Int = stack[idx];
      stack.pop();
      let k: Int = fmt_node_kind(g, n);
      if k == FMT_KIND_TEXT {
        if fmt_text_has_break(g, n) {
          acc = FMT_WIDTH_INFINITE;
          running = false;
        } else {
          acc = acc + fmt_text_len(g, n);
          if acc > FMT_WIDTH_INFINITE {
            acc = FMT_WIDTH_INFINITE;
          }
        }
      } else if k == FMT_KIND_LINE {
        acc = acc + 1;
      } else if k == FMT_KIND_HARDLINE {
        acc = FMT_WIDTH_INFINITE;
        running = false;
      } else if k == FMT_KIND_CONCAT {
        stack.push(fmt_node_child_a(g, n));
        stack.push(fmt_node_child_b(g, n));
      } else if k == FMT_KIND_NEST || k == FMT_KIND_GROUP || k == FMT_KIND_ALIGN {
        stack.push(fmt_node_child_a(g, n));
      }
    }
  }
  return acc;
}

// ---------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------

/// Render the document rooted at `root` at page width `width`.
///
/// Algorithm: explicit work stack of (indent, mode, node); the root is
/// pushed with indent 0 and BREAK mode. TEXT emits its bytes and advances
/// the column; LINE/SOFTLINE/HARDLINE emit a space or a newline plus
/// indentation per the rules in the module header; CONCAT pushes child_b then
/// child_a (so child_a renders first); NEST raises the indent; ALIGN sets it
/// to the current column; a GROUP in BREAK mode is flattened exactly when
/// its finite flat width fits the remaining width
/// (flat_width(child) <= width - column), otherwise it stays broken.
///
/// Params: g - the arena; root - the subtree root; width - the page width in
///         bytes, clamped to >= 0.
/// Returns: the rendered text (no synthetic trailing newline; a trailing
///          LINE/HARDLINE in BREAK mode does produce a trailing newline plus
///          indentation; if FMT_STEP_LIMIT is exhausted, the text produced so
///          far).
/// Complexity: O(nodes) stack steps plus one O(subtree) flat-width scan per
///             group evaluated in BREAK mode; total O(nodes^2) worst case.
pub fn fmt_render(g: &FmtDoc, root: Int, width: Int) -> Str {
  var w = width;
  if w < 0 {
    w = 0;
  }
  var out = "";
  var col: Int = 0;
  var s_indent: Vec[Int] = Vec[Int].new();
  var s_mode: Vec[Int] = Vec[Int].new();
  var s_node: Vec[Int] = Vec[Int].new();
  _push_work(&mut s_indent, &mut s_mode, &mut s_node, 0, FMT_MODE_BREAK, root);
  var steps: Int = 0;
  var running: Bool = true;
  while running {
    let total = s_node.len();
    if total == 0 {
      running = false;
    } else if s_indent.len() != total || s_mode.len() != total {
      running = false;
    } else if steps >= FMT_STEP_LIMIT {
      running = false;
    } else {
      steps = steps + 1;
      let idx = total - 1;
      let ind: Int = s_indent[idx];
      let mode: Int = s_mode[idx];
      let n: Int = s_node[idx];
      s_indent.pop();
      s_mode.pop();
      s_node.pop();
      let k: Int = fmt_node_kind(g, n);
      if k == FMT_KIND_TEXT {
        let t: Str = fmt_node_text(g, n);
        out = out + t;
        if fmt_text_has_break(g, n) {
          col = _last_line_len(t);
        } else {
          col = col + fmt_text_len(g, n);
        }
      } else if k == FMT_KIND_LINE {
        if mode == FMT_MODE_FLAT {
          out = out + " ";
          col = col + 1;
        } else {
          out = _emit_break(out, ind);
          col = ind;
        }
      } else if k == FMT_KIND_SOFTLINE {
        if mode == FMT_MODE_BREAK {
          out = _emit_break(out, ind);
          col = ind;
        }
      } else if k == FMT_KIND_HARDLINE {
        out = _emit_break(out, ind);
        col = ind;
      } else if k == FMT_KIND_CONCAT {
        let ca: Int = fmt_node_child_a(g, n);
        let cb: Int = fmt_node_child_b(g, n);
        _push_work(&mut s_indent, &mut s_mode, &mut s_node, ind, mode, cb);
        _push_work(&mut s_indent, &mut s_mode, &mut s_node, ind, mode, ca);
      } else if k == FMT_KIND_NEST {
        let ca: Int = fmt_node_child_a(g, n);
        var ni: Int = ind + fmt_node_indent(g, n);
        if ni < 0 {
          ni = 0;
        }
        _push_work(&mut s_indent, &mut s_mode, &mut s_node, ni, mode, ca);
      } else if k == FMT_KIND_GROUP {
        let ca: Int = fmt_node_child_a(g, n);
        var child_mode: Int = FMT_MODE_BREAK;
        if mode == FMT_MODE_FLAT {
          child_mode = FMT_MODE_FLAT;
        } else {
          let fw: Int = fmt_flat_width(g, ca);
          if fw < FMT_WIDTH_INFINITE && fw <= w - col {
            child_mode = FMT_MODE_FLAT;
          }
        }
        _push_work(&mut s_indent, &mut s_mode, &mut s_node, ind, child_mode, ca);
      } else if k == FMT_KIND_ALIGN {
        let ca: Int = fmt_node_child_a(g, n);
        _push_work(&mut s_indent, &mut s_mode, &mut s_node, col, mode, ca);
      }
    }
  }
  return out;
}

/// Render with every flattenable group flattened: fmt_render with width
/// FMT_WIDTH_INFINITE. Hardlines (and texts with embedded CR/LF) still emit
/// their breaks, because they can never be flattened.
/// Params: g - the arena; root - the subtree root.
/// Returns: the rendered text. Complexity: as fmt_render.
pub fn fmt_render_flat(g: &FmtDoc, root: Int) -> Str {
  return fmt_render(g, root, FMT_WIDTH_INFINITE);
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

// Single push site for the three parallel render-stack Vec fields.
fn _push_work(si: &mut Vec[Int], sm: &mut Vec[Int], sn: &mut Vec[Int], ind: Int, mode: Int, node: Int) {
  si.push(ind);
  sm.push(mode);
  sn.push(node);
}

// One newline followed by `ind` spaces; `ind` < 0 means no spaces.
fn _emit_break(out: Str, ind: Int) -> Str {
  var r = out + "\n";
  var i = 0;
  while i < ind {
    r = r + " ";
    i = i + 1;
  }
  return r;
}

// True when `t` contains a CR (13) or LF (10) byte; every byte is widened
// with `(b as Int) & 0xFF` before comparison (v0.62.1 trap).
fn _text_has_break(t: Str) -> Bool {
  let n = t.len();
  var i = 0;
  while i < n {
    let raw: UInt8 = string.byte_at(t, i);
    let b = (raw as Int) & 0xFF;
    if b == 10 || b == 13 {
      return true;
    }
    i = i + 1;
  }
  return false;
}

// Number of bytes after the last CR/LF byte of `t` (the column the text
// leaves behind when it embeds a break). Always >= 0.
fn _last_line_len(t: Str) -> Int {
  let n = t.len();
  var last = 0;
  var i = 0;
  while i < n {
    let raw: UInt8 = string.byte_at(t, i);
    let b = (raw as Int) & 0xFF;
    if b == 10 || b == 13 {
      last = i + 1;
    }
    i = i + 1;
  }
  return n - last;
}
