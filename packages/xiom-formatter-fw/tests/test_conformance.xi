// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// XIOM -- xiom.formatter-fw conformance tests (23 checks).
//
// Fixture-driven and deterministic: every check builds its document with the
// public builder API and renders it at one or more widths (including the
// 20/40/80 matrix, exact-fit boundaries and deep nesting), then compares the
// text with str_compare (BUG 17 / trap 1). All dispatch is by direct calls:
// there are no fn tables and no indexed Vec[fn] calls (trap 5). No Result
// values are used anywhere; TestResult comes from xiom.test.assert.
//
// Every builder call is its own statement: no expression nests two `&mut g`
// borrows (E001), so no call can silently operate on a copy of the arena.
// Node indices are pinned by build order where a check inspects the arena
// (t19 re-checks kinds, payloads, children and bounded accessors so a
// reordering fails loudly).

module formatter_fw_tests
use xiom.io; use xiom.test; use xiom.formatter_fw;
use xiom.string.compare;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn report(r: TestResult) -> Int {
  if r.passed {
    io.println("  [PASS] " + r.name);
    return 0;
  }
  io.println("  [FAIL] " + r.name);
  return 1;
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

// Three 12-byte words joined by LINE inside one GROUP: flat width 38, so it
// fits at 40 and 80 and breaks at 20.
fn words12() -> FmtDoc {
  var g = fmt_doc_new();
  let a = fmt_text(&mut g, "aaaaaaaaaaaa");
  let b = fmt_text(&mut g, "bbbbbbbbbbbb");
  let c = fmt_text(&mut g, "cccccccccccc");
  let ln1 = fmt_line(&mut g);
  let ln2 = fmt_line(&mut g);
  let ln2c = fmt_concat(&mut g, ln2, c);
  let bc = fmt_concat(&mut g, b, ln2c);
  let ln1bc = fmt_concat(&mut g, ln1, bc);
  let abc = fmt_concat(&mut g, a, ln1bc);
  let grp = fmt_group(&mut g, abc);
  return g;
}

// Three 20-byte words joined by LINE inside one GROUP: flat width 62, so it
// fits at 80 and breaks at 40 and 20.
fn words20() -> FmtDoc {
  var g = fmt_doc_new();
  let a = fmt_text(&mut g, "aaaaaaaaaaaaaaaaaaaa");
  let b = fmt_text(&mut g, "bbbbbbbbbbbbbbbbbbbb");
  let c = fmt_text(&mut g, "cccccccccccccccccccc");
  let ln1 = fmt_line(&mut g);
  let ln2 = fmt_line(&mut g);
  let ln2c = fmt_concat(&mut g, ln2, c);
  let bc = fmt_concat(&mut g, b, ln2c);
  let ln1bc = fmt_concat(&mut g, ln1, bc);
  let abc = fmt_concat(&mut g, a, ln1bc);
  let grp = fmt_group(&mut g, abc);
  return g;
}

// call(alpha, beta, gamma) as one GROUP with NEST(4) argument indentation and
// SOFTLINE edges: flat width 24.
fn call_doc() -> FmtDoc {
  var g = fmt_doc_new();
  var ids: Vec[Int] = Vec[Int].new();
  let na = fmt_text(&mut g, "alpha");
  let nb = fmt_text(&mut g, "beta");
  let nc = fmt_text(&mut g, "gamma");
  ids.push(na);
  ids.push(nb);
  ids.push(nc);
  let comma = fmt_text(&mut g, ",");
  let sep_line = fmt_line(&mut g);
  let sep = fmt_concat(&mut g, comma, sep_line);
  let args = fmt_join(&mut g, &ids, sep);
  let open = fmt_text(&mut g, "call(");
  let sl1 = fmt_softline(&mut g);
  let inner = fmt_concat(&mut g, sl1, args);
  let inner_n = fmt_nest(&mut g, inner, 4);
  let sl2 = fmt_softline(&mut g);
  let close = fmt_text(&mut g, ")");
  let tail = fmt_concat(&mut g, sl2, close);
  let body_t = fmt_concat(&mut g, inner_n, tail);
  let body = fmt_concat(&mut g, open, body_t);
  let grp = fmt_group(&mut g, body);
  return g;
}

// Root index of a fixture: all three fixtures end by pushing their root
// GROUP, so the root is the last node.
fn root_of(g: &FmtDoc) -> Int {
  return fmt_node_count(g) - 1;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

fn t1() -> TestResult {
  var g = fmt_doc_new();
  let a = fmt_text(&mut g, "ab");
  let b = fmt_text(&mut g, "cd");
  let c = fmt_concat(&mut g, a, b);
  var ok = fmt_node_count(&g) == 3;
  if !streq(fmt_render(&g, c, 80), "abcd") { ok = false; }
  if fmt_flat_width(&g, c) != 4 { ok = false; }
  if !fmt_is_consistent(&g) { ok = false; }
  return assert(ok, "text: concat renders verbatim and reports flat width");
}

fn t2() -> TestResult {
  var g = fmt_doc_new();
  let nl = fmt_nil(&mut g);
  let x = fmt_text(&mut g, "x");
  let c = fmt_concat(&mut g, nl, x);
  var ok = streq(fmt_render(&g, nl, 80), "");
  if fmt_node_count(&g) != 3 { ok = false; }
  if fmt_flat_width(&g, nl) != 0 { ok = false; }
  if !streq(fmt_render(&g, c, 80), "x") { ok = false; }
  return assert(ok, "nil: the empty document is the concat identity");
}

fn t3() -> TestResult {
  var g = fmt_doc_new();
  let a = fmt_text(&mut g, "a");
  let ln = fmt_line(&mut g);
  let b = fmt_text(&mut g, "b");
  let lnb = fmt_concat(&mut g, ln, b);
  let inner = fmt_concat(&mut g, a, lnb);
  let grp = fmt_group(&mut g, inner);
  var ok = fmt_flat_width(&g, inner) == 3;
  if !streq(fmt_render(&g, grp, 80), "a b") { ok = false; }
  if !streq(fmt_render_flat(&g, grp), "a b") { ok = false; }
  return assert(ok, "line: flat inside a fitting group renders as one space");
}

fn t4() -> TestResult {
  var g = fmt_doc_new();
  let a = fmt_text(&mut g, "a");
  let ln = fmt_line(&mut g);
  let b = fmt_text(&mut g, "b");
  let lnb = fmt_concat(&mut g, ln, b);
  let inner = fmt_concat(&mut g, a, lnb);
  let grp = fmt_group(&mut g, inner);
  var ok = streq(fmt_render(&g, grp, 3), "a b");
  if !streq(fmt_render(&g, grp, 2), "a\nb") { ok = false; }
  if !streq(fmt_render(&g, grp, 0), "a\nb") { ok = false; }
  return assert(ok, "line: broken group turns the line into a newline");
}

fn t5() -> TestResult {
  var g = fmt_doc_new();
  let open = fmt_text(&mut g, "f(");
  let sl = fmt_softline(&mut g);
  let x = fmt_text(&mut g, "x");
  let body_in = fmt_concat(&mut g, sl, x);
  let body_n = fmt_nest(&mut g, body_in, 2);
  let close = fmt_text(&mut g, ")");
  let body_t = fmt_concat(&mut g, body_n, close);
  let body = fmt_concat(&mut g, open, body_t);
  let grp = fmt_group(&mut g, body);
  var ok = fmt_flat_width(&g, body) == 4;
  if !streq(fmt_render(&g, grp, 80), "f(x)") { ok = false; }
  if !streq(fmt_render(&g, grp, 4), "f(x)") { ok = false; }
  if !streq(fmt_render(&g, grp, 3), "f(\n  x)") { ok = false; }
  return assert(ok, "softline: nothing flat, newline + nest indentation broken");
}

fn t6() -> TestResult {
  var g = fmt_doc_new();
  let a = fmt_text(&mut g, "a");
  let hl = fmt_hardline(&mut g);
  let b = fmt_text(&mut g, "b");
  let hlb = fmt_concat(&mut g, hl, b);
  let inner = fmt_concat(&mut g, a, hlb);
  let grp = fmt_group(&mut g, inner);
  var ok = fmt_flat_width(&g, inner) == FMT_WIDTH_INFINITE;
  if !streq(fmt_render(&g, grp, 80), "a\nb") { ok = false; }
  if !streq(fmt_render(&g, inner, 80), "a\nb") { ok = false; }
  return assert(ok, "hardline: always breaks and is never flattenable");
}

fn t7() -> TestResult {
  var g = fmt_doc_new();
  let y = fmt_text(&mut g, "y");
  let hl = fmt_hardline(&mut g);
  let z = fmt_text(&mut g, "z");
  let hlz = fmt_concat(&mut g, hl, z);
  let inner_a = fmt_concat(&mut g, y, hlz);
  let inner = fmt_group(&mut g, inner_a);
  let inner_n = fmt_nest(&mut g, inner, 2);
  let x = fmt_text(&mut g, "x");
  let ln = fmt_line(&mut g);
  let ln_in = fmt_concat(&mut g, ln, inner_n);
  let outer_a = fmt_concat(&mut g, x, ln_in);
  let outer = fmt_group(&mut g, outer_a);
  var ok = streq(fmt_render(&g, outer, 80), "x\ny\n  z");
  let hl2 = fmt_hardline(&mut g);
  let z2 = fmt_text(&mut g, "z");
  let hlz2 = fmt_concat(&mut g, hl2, z2);
  let inner2_a = fmt_concat(&mut g, y, hlz2);
  let inner2 = fmt_group(&mut g, inner2_a);
  let ln2 = fmt_line(&mut g);
  let ln_in2 = fmt_concat(&mut g, ln2, inner2);
  let outer2_a = fmt_concat(&mut g, x, ln_in2);
  let outer2 = fmt_group(&mut g, outer2_a);
  if !streq(fmt_render(&g, outer2, 80), "x\ny\nz") { ok = false; }
  return assert(ok, "hardline: propagates breaking to every enclosing group");
}

fn t8() -> TestResult {
  var g = fmt_doc_new();
  let a = fmt_text(&mut g, "a");
  let hl = fmt_hardline(&mut g);
  let b = fmt_text(&mut g, "b");
  let hlb = fmt_concat(&mut g, hl, b);
  let pair = fmt_concat(&mut g, a, hlb);
  var d = fmt_group(&mut g, pair);
  d = fmt_nest(&mut g, d, 2);
  d = fmt_nest(&mut g, d, 2);
  d = fmt_nest(&mut g, d, 2);
  d = fmt_nest(&mut g, d, 2);
  d = fmt_nest(&mut g, d, 2);
  var ok = fmt_flat_width(&g, d) == FMT_WIDTH_INFINITE;
  if !streq(fmt_render(&g, d, 80), "a\n          b") { ok = false; }
  return assert(ok, "nest: five levels accumulate ten spaces of indentation");
}

fn t9() -> TestResult {
  var g = fmt_doc_new();
  let ab = fmt_text(&mut g, "ab");
  let ln = fmt_line(&mut g);
  let c = fmt_text(&mut g, "c");
  let lnc = fmt_concat(&mut g, ln, c);
  let grp = fmt_group(&mut g, lnc);
  let al = fmt_align(&mut g, grp);
  let doc = fmt_concat(&mut g, ab, al);
  var ok = streq(fmt_render(&g, doc, 1), "ab\n  c");
  let c2 = fmt_text(&mut g, "c");
  let lnc2 = fmt_concat(&mut g, ln, c2);
  let grp2 = fmt_group(&mut g, lnc2);
  let doc2 = fmt_concat(&mut g, ab, grp2);
  if !streq(fmt_render(&g, doc2, 1), "ab\nc") { ok = false; }
  return assert(ok, "align: indentation becomes the column at the align node");
}

fn t10() -> TestResult {
  var g = fmt_doc_new();
  let t12 = fmt_text(&mut g, "12");
  let ln = fmt_line(&mut g);
  let t34 = fmt_text(&mut g, "34");
  let ln34 = fmt_concat(&mut g, ln, t34);
  let inner_a = fmt_concat(&mut g, t12, ln34);
  let inner = fmt_group(&mut g, inner_a);
  let x = fmt_text(&mut g, "X");
  let ln2 = fmt_line(&mut g);
  let ln2_inner = fmt_concat(&mut g, ln2, inner);
  let outer_a = fmt_concat(&mut g, x, ln2_inner);
  let outer = fmt_group(&mut g, outer_a);
  var ok = streq(fmt_render(&g, outer, 4), "X\n12\n34");
  if !streq(fmt_render(&g, outer, 5), "X\n12 34") { ok = false; }
  if !streq(fmt_render(&g, outer, 7), "X 12 34") { ok = false; }
  return assert(ok, "group: an inner group decides independently of the outer one");
}

fn t11() -> TestResult {
  let g12 = words12();
  let g20 = words20();
  let r12 = root_of(&g12);
  let r20 = root_of(&g20);
  let flat12 = "aaaaaaaaaaaa bbbbbbbbbbbb cccccccccccc";
  let flat20 = "aaaaaaaaaaaaaaaaaaaa bbbbbbbbbbbbbbbbbbbb cccccccccccccccccccc";
  let broken12 = "aaaaaaaaaaaa\nbbbbbbbbbbbb\ncccccccccccc";
  let broken20 = "aaaaaaaaaaaaaaaaaaaa\nbbbbbbbbbbbbbbbbbbbb\ncccccccccccccccccccc";
  var ok = streq(fmt_render(&g12, r12, 80), flat12);
  if !streq(fmt_render(&g12, r12, 40), flat12) { ok = false; }
  if !streq(fmt_render(&g12, r12, 20), broken12) { ok = false; }
  if !streq(fmt_render(&g20, r20, 80), flat20) { ok = false; }
  if !streq(fmt_render(&g20, r20, 40), broken20) { ok = false; }
  if !streq(fmt_render(&g20, r20, 20), broken20) { ok = false; }
  if fmt_flat_width(&g12, r12) != 38 { ok = false; }
  if fmt_flat_width(&g20, r20) != 62 { ok = false; }
  return assert(ok, "widths 20/40/80: the same group fits or breaks per width");
}

fn t12() -> TestResult {
  var g = fmt_doc_new();
  let abc = fmt_text(&mut g, "abc");
  let ln = fmt_line(&mut g);
  let de = fmt_text(&mut g, "de");
  let lnde = fmt_concat(&mut g, ln, de);
  let inner = fmt_concat(&mut g, abc, lnde);
  let grp = fmt_group(&mut g, inner);
  var ok = fmt_flat_width(&g, inner) == 6;
  if !streq(fmt_render(&g, grp, 6), "abc de") { ok = false; }
  if !streq(fmt_render(&g, grp, 5), "abc\nde") { ok = false; }
  return assert(ok, "fit: an exact fit (flat width == width) stays flat");
}

fn t13() -> TestResult {
  var g = fmt_doc_new();
  let key = fmt_text(&mut g, "key");
  let ln1 = fmt_line(&mut g);
  let val = fmt_text(&mut g, "val");
  let ln1val = fmt_concat(&mut g, ln1, val);
  let key_ln = fmt_concat(&mut g, key, ln1val);
  let inner = fmt_group(&mut g, key_ln);
  let open = fmt_text(&mut g, "(");
  let ln2 = fmt_line(&mut g);
  let ln2_inner = fmt_concat(&mut g, ln2, inner);
  let inner_n = fmt_nest(&mut g, ln2_inner, 2);
  let ln3 = fmt_line(&mut g);
  let close = fmt_text(&mut g, ")");
  let ln3close = fmt_concat(&mut g, ln3, close);
  let outer_a = fmt_concat(&mut g, inner_n, ln3close);
  let outer_b = fmt_concat(&mut g, open, outer_a);
  let outer = fmt_group(&mut g, outer_b);
  var ok = streq(fmt_render(&g, outer, 10), "(\n  key val\n)");
  if !streq(fmt_render(&g, outer, 11), "( key val )") { ok = false; }
  return assert(ok, "group: a broken outer group leaves a fitting inner group flat");
}

fn t14() -> TestResult {
  var g = fmt_doc_new();
  let pref = fmt_text(&mut g, "name =");
  let ln = fmt_line(&mut g);
  let val = fmt_text(&mut g, "value");
  let lnval = fmt_concat(&mut g, ln, val);
  let grp = fmt_group(&mut g, lnval);
  let al = fmt_align(&mut g, grp);
  let doc = fmt_concat(&mut g, pref, al);
  var ok = streq(fmt_render(&g, doc, 20), "name = value");
  if !streq(fmt_render(&g, doc, 5), "name =\n      value") { ok = false; }
  return assert(ok, "align: continuation lines line up after a fixed prefix");
}

fn t15() -> TestResult {
  var g = fmt_doc_new();
  var ids: Vec[Int] = Vec[Int].new();
  let na = fmt_text(&mut g, "a");
  let nb = fmt_text(&mut g, "bb");
  let nc = fmt_text(&mut g, "ccc");
  ids.push(na);
  ids.push(nb);
  ids.push(nc);
  let sep = fmt_line(&mut g);
  let joined = fmt_join(&mut g, &ids, sep);
  let grp = fmt_group(&mut g, joined);
  var ok = streq(fmt_render(&g, grp, 80), "a bb ccc");
  if !streq(fmt_render(&g, grp, 1), "a\nbb\nccc") { ok = false; }
  var ids1: Vec[Int] = Vec[Int].new();
  let nz = fmt_text(&mut g, "z");
  ids1.push(nz);
  let before = fmt_node_count(&g);
  let one = fmt_join(&mut g, &ids1, sep);
  if fmt_node_count(&g) != before { ok = false; }
  if !streq(fmt_render(&g, one, 80), "z") { ok = false; }
  var ids0: Vec[Int] = Vec[Int].new();
  let none = fmt_join(&mut g, &ids0, sep);
  if !streq(fmt_render(&g, none, 80), "") { ok = false; }
  return assert(ok, "join: folds elements with a separator; empty and single cases");
}

fn t16() -> TestResult {
  var g = fmt_doc_new();
  let ln = fmt_line(&mut g);
  let sl = fmt_softline(&mut g);
  let hl = fmt_hardline(&mut g);
  let nl = fmt_nil(&mut g);
  let t = fmt_text(&mut g, "abc");
  var ok = fmt_flat_width(&g, ln) == 1;
  if fmt_flat_width(&g, sl) != 0 { ok = false; }
  if fmt_flat_width(&g, hl) != FMT_WIDTH_INFINITE { ok = false; }
  if fmt_flat_width(&g, nl) != 0 { ok = false; }
  if fmt_flat_width(&g, t) != 3 { ok = false; }
  let c = fmt_concat(&mut g, t, ln);
  if fmt_flat_width(&g, c) != 4 { ok = false; }
  let ab = fmt_text(&mut g, "ab");
  let ln2 = fmt_line(&mut g);
  let pair = fmt_concat(&mut g, ab, ln2);
  let nst = fmt_nest(&mut g, pair, 5);
  if fmt_flat_width(&g, nst) != 3 { ok = false; }
  let grp = fmt_group(&mut g, c);
  if fmt_flat_width(&g, grp) != 4 { ok = false; }
  let al = fmt_align(&mut g, c);
  if fmt_flat_width(&g, al) != 4 { ok = false; }
  if fmt_flat_width(&g, -1) != 0 { ok = false; }
  if fmt_flat_width(&g, 999) != 0 { ok = false; }
  return assert(ok, "flat width: per-kind widths, transparent nest/group/align, bounds");
}

fn t17() -> TestResult {
  let g1 = words12();
  let r1 = root_of(&g1);
  let a1 = fmt_render(&g1, r1, 40);
  let a2 = fmt_render(&g1, r1, 40);
  var ok = streq(a1, a2);
  let g2 = words12();
  let r2 = root_of(&g2);
  if !streq(a1, fmt_render(&g2, r2, 40)) { ok = false; }
  let b1 = fmt_render(&g1, r1, 20);
  if !streq(b1, fmt_render(&g1, r1, 20)) { ok = false; }
  if !streq(b1, fmt_render(&g2, r2, 20)) { ok = false; }
  return assert(ok, "determinism: identical documents render identically");
}

fn t18() -> TestResult {
  var g = fmt_doc_new();
  var ok = streq(fmt_render(&g, -1, 80), "");
  if !streq(fmt_render(&g, 999, 80), "") { ok = false; }
  let ln = fmt_line(&mut g);
  let x = fmt_text(&mut g, "x");
  let d = fmt_concat(&mut g, ln, x);
  if !streq(fmt_render(&g, d, -5), "\nx") { ok = false; }
  let pair = fmt_concat(&mut g, ln, x);
  let nst = fmt_nest(&mut g, pair, -10);
  if !streq(fmt_render(&g, nst, 80), "\nx") { ok = false; }
  let bad = fmt_group(&mut g, 999);
  if !streq(fmt_render(&g, bad, 80), "") { ok = false; }
  if fmt_flat_width(&g, bad) != 0 { ok = false; }
  return assert(ok, "totality: empty arena, negative width/nest, out-of-range nodes");
}

fn t19() -> TestResult {
  var g = fmt_doc_new();
  let t = fmt_text(&mut g, "ab");
  let ln = fmt_line(&mut g);
  let sl = fmt_softline(&mut g);
  let hl = fmt_hardline(&mut g);
  let nl = fmt_nil(&mut g);
  let c = fmt_concat(&mut g, t, ln);
  let nst = fmt_nest(&mut g, c, 3);
  let grp = fmt_group(&mut g, nst);
  let al = fmt_align(&mut g, grp);
  var ok = fmt_node_count(&g) == 9;
  if !fmt_is_consistent(&g) { ok = false; }
  if fmt_node_kind(&g, t) != FMT_KIND_TEXT { ok = false; }
  if fmt_node_kind(&g, ln) != FMT_KIND_LINE { ok = false; }
  if fmt_node_kind(&g, sl) != FMT_KIND_SOFTLINE { ok = false; }
  if fmt_node_kind(&g, hl) != FMT_KIND_HARDLINE { ok = false; }
  if fmt_node_kind(&g, nl) != FMT_KIND_NIL { ok = false; }
  if fmt_node_kind(&g, c) != FMT_KIND_CONCAT { ok = false; }
  if fmt_node_kind(&g, nst) != FMT_KIND_NEST { ok = false; }
  if fmt_node_kind(&g, grp) != FMT_KIND_GROUP { ok = false; }
  if fmt_node_kind(&g, al) != FMT_KIND_ALIGN { ok = false; }
  if fmt_node_child_a(&g, c) != t { ok = false; }
  if fmt_node_child_b(&g, c) != ln { ok = false; }
  if fmt_node_child_a(&g, nst) != c { ok = false; }
  if !streq(fmt_node_text(&g, t), "ab") { ok = false; }
  if fmt_text_len(&g, t) != 2 { ok = false; }
  if fmt_text_has_break(&g, t) { ok = false; }
  if fmt_node_indent(&g, nst) != 3 { ok = false; }
  if !streq(fmt_kind_name(FMT_KIND_TEXT), "text") { ok = false; }
  if !streq(fmt_kind_name(FMT_KIND_HARDLINE), "hardline") { ok = false; }
  if !streq(fmt_kind_name(12345), "none") { ok = false; }
  if !streq(fmt_mode_name(FMT_MODE_FLAT), "flat") { ok = false; }
  if !streq(fmt_mode_name(FMT_MODE_BREAK), "break") { ok = false; }
  if !streq(fmt_mode_name(9), "none") { ok = false; }
  if fmt_node_kind(&g, -1) != FMT_KIND_NONE { ok = false; }
  if !streq(fmt_node_text(&g, 999), "") { ok = false; }
  if fmt_text_len(&g, 999) != 0 { ok = false; }
  if fmt_text_has_break(&g, 999) { ok = false; }
  if fmt_node_indent(&g, 999) != 0 { ok = false; }
  if fmt_node_child_a(&g, 999) != -1 { ok = false; }
  if fmt_node_child_b(&g, 999) != -1 { ok = false; }
  return assert(ok, "arena: seven parallel fields stay consistent; accessors bounded");
}

fn t20() -> TestResult {
  let g = call_doc();
  let r = root_of(&g);
  let flat = "call(alpha, beta, gamma)";
  let broken = "call(\n    alpha,\n    beta,\n    gamma\n)";
  var ok = fmt_flat_width(&g, r) == 24;
  if !streq(fmt_render(&g, r, 80), flat) { ok = false; }
  if !streq(fmt_render(&g, r, 24), flat) { ok = false; }
  if !streq(fmt_render(&g, r, 10), broken) { ok = false; }
  return assert(ok, "call fixture: nest(4) argument block breaks one item per line");
}

fn t21() -> TestResult {
  var g = fmt_doc_new();
  let t = fmt_text(&mut g, "a\nb");
  var ok = fmt_text_has_break(&g, t);
  if fmt_flat_width(&g, t) != FMT_WIDTH_INFINITE { ok = false; }
  if !streq(fmt_render(&g, t, 80), "a\nb") { ok = false; }
  let ln = fmt_line(&mut g);
  let c = fmt_text(&mut g, "c");
  let lnc = fmt_concat(&mut g, ln, c);
  let grp = fmt_group(&mut g, lnc);
  let doc = fmt_concat(&mut g, t, grp);
  if !streq(fmt_render(&g, doc, 3), "a\nb c") { ok = false; }
  if !streq(fmt_render(&g, doc, 2), "a\nb\nc") { ok = false; }
  return assert(ok, "embedded break: multi-line text is never flattenable; column resets");
}

fn t22() -> TestResult {
  let g = call_doc();
  let r = root_of(&g);
  var ok = streq(fmt_render_flat(&g, r), "call(alpha, beta, gamma)");
  var g2 = fmt_doc_new();
  let a = fmt_text(&mut g2, "a");
  let hl = fmt_hardline(&mut g2);
  let b = fmt_text(&mut g2, "b");
  let hlb = fmt_concat(&mut g2, hl, b);
  let pair = fmt_concat(&mut g2, a, hlb);
  let doc = fmt_group(&mut g2, pair);
  if !streq(fmt_render_flat(&g2, doc), "a\nb") { ok = false; }
  return assert(ok, "render_flat: flattens groups but never hardlines");
}

fn t23() -> TestResult {
  var g = fmt_doc_new();
  let long = fmt_text(&mut g, "0123456789012345678901234567890");
  let grp = fmt_group(&mut g, long);
  var ok = fmt_flat_width(&g, long) == 31;
  if !streq(fmt_render(&g, grp, 10), "0123456789012345678901234567890") { ok = false; }
  return assert(ok, "overflow: an unbreakable text is emitted whole, never truncated");
}

// ---------------------------------------------------------------------------

fn main() -> Int {
  io.println("=== xiom.formatter-fw conformance tests ===");
  var failed: Int = 0;
  failed = failed + report(t1());
  failed = failed + report(t2());
  failed = failed + report(t3());
  failed = failed + report(t4());
  failed = failed + report(t5());
  failed = failed + report(t6());
  failed = failed + report(t7());
  failed = failed + report(t8());
  failed = failed + report(t9());
  failed = failed + report(t10());
  failed = failed + report(t11());
  failed = failed + report(t12());
  failed = failed + report(t13());
  failed = failed + report(t14());
  failed = failed + report(t15());
  failed = failed + report(t16());
  failed = failed + report(t17());
  failed = failed + report(t18());
  failed = failed + report(t19());
  failed = failed + report(t20());
  failed = failed + report(t21());
  failed = failed + report(t22());
  failed = failed + report(t23());
  if failed == 0 {
    io.println("xiom.formatter-fw: all tests passed");
  } else {
    io.println("xiom.formatter-fw: tests failed");
  }
  return failed;
}
