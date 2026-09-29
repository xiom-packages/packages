// XIOM -- xiom.ast conformance tests (24 checks)
// Port task: prove the pure-XIOM xiom.ast module against its SPEC.md: the
// parallel-array node model, the builder (add child / reparent / cycle
// refusal), pre/post-order traversal, span text and span/diagnostic tables,
// the canonical pretty-printer, counting and range safety.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module ast_tests
use xiom.io; use xiom.test; use xiom.ast;
use xiom.string.compare; use xiom.string.join;

// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every label and
// table-row check below is routed through streq instead of `==`.

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// One "\n"-terminated line per Vec[Str] entry (stdlib join, typed reads).
fn rows_code(v: &Vec[Str]) -> Str {
  if v.len() == 0 { return ""; }
  return join.str_join(v, "\n") + "\n";
}

// Comma-separated node kinds of the whole tree in index order.
fn kinds_code(t: &Ast) -> Str {
  var ks = Vec[Int].new();
  var i = 0;
  while i < ast_node_count(t) {
    ks.push(ast_kind(t, i));
    i = i + 1;
  }
  return join.vec_int_join(&ks, ",");
}

// The expected pre-order of the fixture (see ast_fixture_ast).
fn fixture_preorder_text() -> Str {
  return "13,4,3,2,0,1,12,5,8,6,7,11,9,10";
}

// The expected post-order of the fixture.
fn fixture_postorder_text() -> Str {
  return "3,0,1,2,4,5,7,6,8,10,9,11,12,13";
}

// The exact canonical pretty-print of the fixture.
fn fixture_pretty_text() -> Str {
  return "program [0,52)\n  let [0,13)\n    ident x [4,5)\n    binary + [8,13)\n      literal 1 [8,9)\n      literal 2 [12,13)\n  if [15,52)\n    ident x [18,19)\n    block [20,33)\n      return [22,30)\n        ident x [29,30)\n    block [39,52)\n      return [41,49)\n        literal 0 [48,49)\n";
}

// The exact span table of the fixture (index order).
fn fixture_table_text() -> Str {
  return "0: literal [8,9) parent=2 depth=3\n1: literal [12,13) parent=2 depth=3\n2: binary [8,13) parent=4 depth=2\n3: ident [4,5) parent=4 depth=2\n4: let [0,13) parent=13 depth=1\n5: ident [18,19) parent=12 depth=2\n6: return [22,30) parent=8 depth=3\n7: ident [29,30) parent=6 depth=4\n8: block [20,33) parent=12 depth=2\n9: return [41,49) parent=11 depth=3\n10: literal [48,49) parent=9 depth=4\n11: block [39,52) parent=12 depth=2\n12: if [15,52) parent=13 depth=1\n13: program [0,52) parent=-1 depth=0\n";
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

fn t1() -> TestResult {
  let t = ast_new();
  var ok = ast_node_count(&t) == 0;
  if ok && ast_preorder(&t).len() != 0 { ok = false; }
  if ok && ast_postorder(&t).len() != 0 { ok = false; }
  if ok && ast_roots(&t).len() != 0 { ok = false; }
  if ok && ast_span_table(&t).len() != 0 { ok = false; }
  if ok && ast_diagnostics(&t).len() != 0 { ok = false; }
  if ok && ast_leaf_count(&t) != 0 { ok = false; }
  if ok && !streq(ast_pretty(&t), "") { ok = false; }
  if ok && !ast_is_well_formed(&t) { ok = false; }
  return assert(ok, "empty tree: no nodes, empty traversals/tables, empty pretty, well formed");
}

fn t2() -> TestResult {
  var t = ast_new();
  let a = ast_add_node(&mut t, AST_KIND_LET, 3, 9);
  let b = ast_add_node(&mut t, AST_KIND_IDENT, 10, 11);
  var ok = a == 0;
  if ok && b != 1 { ok = false; }
  if ok && ast_node_count(&t) != 2 { ok = false; }
  if ok && ast_kind(&t, a) != AST_KIND_LET { ok = false; }
  if ok && ast_span_start(&t, a) != 3 { ok = false; }
  if ok && ast_span_end(&t, a) != 9 { ok = false; }
  if ok && ast_parent(&t, a) != -1 { ok = false; }
  if ok && ast_first_child(&t, a) != -1 { ok = false; }
  if ok && ast_next_sibling(&t, a) != -1 { ok = false; }
  if ok && !streq(ast_label(&t, a), "") { ok = false; }
  if ok && !ast_is_leaf(&t, a) { ok = false; }
  if ok && ast_depth(&t, a) != 0 { ok = false; }
  if ok && ast_child_count(&t, a) != 0 { ok = false; }
  if ok {
    let roots = ast_roots(&t);
    if roots.len() != 2 { ok = false; }
    let r0: Int = roots[0];
    let r1: Int = roots[1];
    if r0 != a { ok = false; }
    if r1 != b { ok = false; }
  }
  if ok && !ast_is_well_formed(&t) { ok = false; }
  return assert(ok, "add_node: index return, kind/span/parent defaults, two roots in index order");
}

fn t3() -> TestResult {
  var t = ast_new();
  let root = ast_add_node(&mut t, AST_KIND_PROGRAM, 0, 40);
  let c1 = ast_add_node(&mut t, AST_KIND_LET, 0, 10);
  let c2 = ast_add_node(&mut t, AST_KIND_IF, 11, 30);
  let c3 = ast_add_node(&mut t, AST_KIND_RETURN, 31, 39);
  var ok = ast_add_child(&mut t, root, c1);
  if ok && !ast_add_child(&mut t, root, c2) { ok = false; }
  if ok && !ast_add_child(&mut t, root, c3) { ok = false; }
  if ok && ast_child_count(&t, root) != 3 { ok = false; }
  if ok && ast_child(&t, root, 0) != c1 { ok = false; }
  if ok && ast_child(&t, root, 1) != c2 { ok = false; }
  if ok && ast_child(&t, root, 2) != c3 { ok = false; }
  if ok && ast_child(&t, root, 3) != -1 { ok = false; }
  if ok && ast_child(&t, root, -1) != -1 { ok = false; }
  if ok && ast_first_child(&t, root) != c1 { ok = false; }
  if ok && ast_next_sibling(&t, c1) != c2 { ok = false; }
  if ok && ast_next_sibling(&t, c2) != c3 { ok = false; }
  if ok && ast_next_sibling(&t, c3) != -1 { ok = false; }
  if ok && ast_parent(&t, c2) != root { ok = false; }
  if ok && ast_is_leaf(&t, root) { ok = false; }
  if ok && !ast_is_leaf(&t, c3) { ok = false; }
  if ok && ast_depth(&t, c2) != 1 { ok = false; }
  if ok && !ast_is_ancestor(&t, root, c3) { ok = false; }
  if ok && ast_is_ancestor(&t, c1, c2) { ok = false; }
  if ok && ast_is_ancestor(&t, root, root) { ok = false; }
  if ok && !ast_is_well_formed(&t) { ok = false; }
  return assert(ok, "child links: chain order, parent/child accessors, depth, ancestry");
}

fn t4() -> TestResult {
  var t = ast_fixture_ast();
  let before = ast_node_count(&t);
  var ok = !ast_add_child(&mut t, 99, 0);
  if ok && ast_add_child(&mut t, 2, 99) { ok = false; }
  if ok && ast_add_child(&mut t, 2, 2) { ok = false; }
  if ok && ast_add_child(&mut t, 2, 5) { ok = false; }
  if ok && ast_add_child(&mut t, 12, 13) { ok = false; }
  if ok && ast_add_child(&mut t, -1, 0) { ok = false; }
  if ok && ast_add_child(&mut t, 2, -1) { ok = false; }
  if ok && ast_child_count(&t, 2) != 2 { ok = false; }
  if ok && ast_node_count(&t) != before { ok = false; }
  if ok && ast_parent(&t, 5) != 12 { ok = false; }
  if ok && ast_parent(&t, 13) != -1 { ok = false; }
  if ok && !ast_is_well_formed(&t) { ok = false; }
  return assert(ok, "add_child guards: bad indices, self, already-parented child, cycle, no drift");
}

fn t5() -> TestResult {
  var t = ast_fixture_ast();
  var ok = ast_reparent(&mut t, 0, 8);
  if ok && ast_parent(&t, 0) != 8 { ok = false; }
  if ok && ast_child_count(&t, 2) != 1 { ok = false; }
  if ok && ast_child(&t, 2, 0) != 1 { ok = false; }
  if ok && ast_child_count(&t, 8) != 2 { ok = false; }
  if ok && ast_child(&t, 8, 0) != 6 { ok = false; }
  if ok && ast_child(&t, 8, 1) != 0 { ok = false; }
  if ok && !ast_is_well_formed(&t) { ok = false; }
  if ok && !ast_reparent(&mut t, 0, 8) { ok = false; }
  if ok && ast_child_count(&t, 8) != 2 { ok = false; }
  if ok && !ast_reparent(&mut t, 0, -1) { ok = false; }
  if ok && ast_parent(&t, 0) != -1 { ok = false; }
  if ok && ast_roots(&t).len() != 2 { ok = false; }
  if ok && !ast_is_well_formed(&t) { ok = false; }
  if ok && ast_reparent(&mut t, 13, 12) { ok = false; }
  if ok && ast_reparent(&mut t, 0, 0) { ok = false; }
  if ok && ast_reparent(&mut t, 99, 0) { ok = false; }
  if ok && ast_reparent(&mut t, 0, 99) { ok = false; }
  if ok && ast_reparent(&mut t, 0, -2) { ok = false; }
  if ok && !ast_is_well_formed(&t) { ok = false; }
  return assert(ok, "reparent: move subtree, no-op, detach to root, cycle/bounds refusals");
}

fn t6() -> TestResult {
  let t = ast_fixture_ast();
  let order = ast_preorder(&t);
  var ok = streq(join.vec_int_join(&order, ","), fixture_preorder_text());
  if ok && order.len() != 14 { ok = false; }
  return assert(ok, "fixture pre-order: index order 13,4,3,2,0,1,12,5,8,6,7,11,9,10");
}

fn t7() -> TestResult {
  let t = ast_fixture_ast();
  let order = ast_postorder(&t);
  var ok = streq(join.vec_int_join(&order, ","), fixture_postorder_text());
  if ok && order.len() != 14 { ok = false; }
  return assert(ok, "fixture post-order: children before parents, 3,0,1,2,4,5,7,6,8,10,9,11,12,13");
}

fn t8() -> TestResult {
  let t = ast_fixture_ast();
  let roots = ast_roots(&t);
  var ok = roots.len() == 1;
  if ok {
    let r: Int = roots[0];
    if r != 13 { ok = false; }
  }
  if ok && ast_parent(&t, 13) != -1 { ok = false; }
  if ok && ast_parent(&t, 4) != 13 { ok = false; }
  if ok && ast_first_child(&t, 13) != 4 { ok = false; }
  if ok && ast_next_sibling(&t, 4) != 12 { ok = false; }
  if ok && ast_next_sibling(&t, 12) != -1 { ok = false; }
  let order = ast_preorder(&t);
  if ok {
    let first: Int = order[0];
    if first != 13 { ok = false; }
  }
  return assert(ok, "fixture roots: single program root, statement chain let then if");
}

fn t9() -> TestResult {
  var t = ast_new();
  let r0 = ast_add_node(&mut t, AST_KIND_PROGRAM, 0, 1);
  let c = ast_add_node(&mut t, AST_KIND_IDENT, 0, 1);
  let r1 = ast_add_node(&mut t, AST_KIND_LITERAL, 2, 3);
  var ok = ast_add_child(&mut t, r0, c);
  if ok && ast_node_count(&t) != 3 { ok = false; }
  if ok && ast_roots(&t).len() != 2 { ok = false; }
  let pre = ast_preorder(&t);
  let post = ast_postorder(&t);
  if ok && !streq(join.vec_int_join(&pre, ","), "0,1,2") { ok = false; }
  if ok && !streq(join.vec_int_join(&post, ","), "1,0,2") { ok = false; }
  if ok && ast_depth(&t, r1) != 0 { ok = false; }
  if ok && ast_depth(&t, c) != 1 { ok = false; }
  if ok && !ast_is_well_formed(&t) { ok = false; }
  return assert(ok, "forest: two roots in index order, pre/post-order cover both trees");
}

fn t10() -> TestResult {
  let t = ast_fixture_ast();
  var ok = ast_depth(&t, 13) == 0;
  if ok && ast_depth(&t, 4) != 1 { ok = false; }
  if ok && ast_depth(&t, 12) != 1 { ok = false; }
  if ok && ast_depth(&t, 5) != 2 { ok = false; }
  if ok && ast_depth(&t, 8) != 2 { ok = false; }
  if ok && ast_depth(&t, 11) != 2 { ok = false; }
  if ok && ast_depth(&t, 2) != 2 { ok = false; }
  if ok && ast_depth(&t, 3) != 2 { ok = false; }
  if ok && ast_depth(&t, 0) != 3 { ok = false; }
  if ok && ast_depth(&t, 6) != 3 { ok = false; }
  if ok && ast_depth(&t, 9) != 3 { ok = false; }
  if ok && ast_depth(&t, 7) != 4 { ok = false; }
  if ok && ast_depth(&t, 10) != 4 { ok = false; }
  if ok && ast_depth(&t, -1) != -1 { ok = false; }
  if ok && ast_depth(&t, 99) != -1 { ok = false; }
  if ok && !ast_is_ancestor(&t, 13, 10) { ok = false; }
  if ok && !ast_is_ancestor(&t, 12, 9) { ok = false; }
  if ok && !ast_is_ancestor(&t, 2, 1) { ok = false; }
  if ok && ast_is_ancestor(&t, 0, 13) { ok = false; }
  if ok && ast_is_ancestor(&t, 3, 2) { ok = false; }
  if ok && ast_is_ancestor(&t, 13, 13) { ok = false; }
  if ok && ast_is_ancestor(&t, 99, 0) { ok = false; }
  if ok && ast_is_ancestor(&t, 13, 99) { ok = false; }
  return assert(ok, "depths 0..4 on all fixture nodes and strict ancestry (self/out-of-range false)");
}

fn t11() -> TestResult {
  let t = ast_fixture_ast();
  return assert(streq(ast_pretty(&t), fixture_pretty_text()), "pretty: exact pre-order text, 2-space indent, labels, trailing newline");
}

fn t12() -> TestResult {
  let t = ast_fixture_ast();
  let rows = ast_span_table(&t);
  var ok = rows.len() == 14;
  if ok && !streq(rows_code(&rows), fixture_table_text()) { ok = false; }
  let r13: Str = rows[13];
  if ok && !streq(r13, "13: program [0,52) parent=-1 depth=0") { ok = false; }
  let r0: Str = rows[0];
  if ok && !streq(r0, "0: literal [8,9) parent=2 depth=3") { ok = false; }
  if ok && !streq(ast_span_row(&t, 6), "6: return [22,30) parent=8 depth=3") { ok = false; }
  if ok && !streq(ast_span_row(&t, 99), "") { ok = false; }
  return assert(ok, "span table: 14 index-order rows, exact row text, out-of-range row empty");
}

fn t13() -> TestResult {
  var ok = streq(ast_kind_name(AST_KIND_NONE), "none");
  if ok && !streq(ast_kind_name(AST_KIND_PROGRAM), "program") { ok = false; }
  if ok && !streq(ast_kind_name(AST_KIND_LET), "let") { ok = false; }
  if ok && !streq(ast_kind_name(AST_KIND_IF), "if") { ok = false; }
  if ok && !streq(ast_kind_name(AST_KIND_BLOCK), "block") { ok = false; }
  if ok && !streq(ast_kind_name(AST_KIND_RETURN), "return") { ok = false; }
  if ok && !streq(ast_kind_name(AST_KIND_BINARY), "binary") { ok = false; }
  if ok && !streq(ast_kind_name(AST_KIND_IDENT), "ident") { ok = false; }
  if ok && !streq(ast_kind_name(AST_KIND_LITERAL), "literal") { ok = false; }
  if ok && !streq(ast_kind_name(12345), "none") { ok = false; }
  if ok && !streq(ast_kind_name(-3), "none") { ok = false; }
  return assert(ok, "kind names: all eight kinds plus none for unknown/negative values");
}

fn t14() -> TestResult {
  let t = ast_fixture_ast();
  var ok = ast_leaf_count(&t) == 6;
  if ok && ast_count_kind(&t, AST_KIND_LITERAL) != 3 { ok = false; }
  if ok && ast_count_kind(&t, AST_KIND_IDENT) != 3 { ok = false; }
  if ok && ast_count_kind(&t, AST_KIND_RETURN) != 2 { ok = false; }
  if ok && ast_count_kind(&t, AST_KIND_BLOCK) != 2 { ok = false; }
  if ok && ast_count_kind(&t, AST_KIND_PROGRAM) != 1 { ok = false; }
  if ok && ast_count_kind(&t, AST_KIND_IF) != 1 { ok = false; }
  if ok && ast_count_kind(&t, AST_KIND_LET) != 1 { ok = false; }
  if ok && ast_count_kind(&t, AST_KIND_BINARY) != 1 { ok = false; }
  if ok && ast_count_kind(&t, AST_KIND_NONE) != 0 { ok = false; }
  let empty = ast_new();
  if ok && ast_leaf_count(&empty) != 0 { ok = false; }
  return assert(ok, "counting: 6 leaves, 3 literals, 3 idents, 2 returns, 2 blocks, one of each other kind");
}

fn t15() -> TestResult {
  let t = ast_fixture_ast();
  var ok = ast_kind(&t, 99) == AST_KIND_NONE;
  if ok && ast_kind(&t, -1) != AST_KIND_NONE { ok = false; }
  if ok && ast_span_start(&t, 99) != -1 { ok = false; }
  if ok && ast_span_end(&t, 99) != -1 { ok = false; }
  if ok && !streq(ast_label(&t, 99), "") { ok = false; }
  if ok && ast_parent(&t, 99) != -1 { ok = false; }
  if ok && ast_first_child(&t, 99) != -1 { ok = false; }
  if ok && ast_next_sibling(&t, 99) != -1 { ok = false; }
  if ok && ast_child(&t, 99, 0) != -1 { ok = false; }
  if ok && ast_child_count(&t, 99) != 0 { ok = false; }
  if ok && ast_is_leaf(&t, 99) { ok = false; }
  if ok && ast_depth(&t, 99) != -1 { ok = false; }
  if ok && !streq(ast_span_text(ast_fixture_source(), &t, 99), "") { ok = false; }
  if ok && !streq(ast_span_row(&t, 99), "") { ok = false; }
  return assert(ok, "range safety: every accessor is total and returns NONE/-1/\"\" out of range");
}

fn t16() -> TestResult {
  var t = ast_new();
  let n = ast_add_node(&mut t, AST_KIND_IDENT, 0, 5);
  var ok = ast_set_span(&mut t, n, 2, 4);
  if ok && ast_span_start(&t, n) != 2 { ok = false; }
  if ok && ast_span_end(&t, n) != 4 { ok = false; }
  if ok && ast_set_span(&mut t, 99, 0, 1) { ok = false; }
  if ok && ast_set_span(&mut t, -1, 0, 1) { ok = false; }
  if ok && ast_span_start(&t, n) != 2 { ok = false; }
  return assert(ok, "set_span: overwrite works, out-of-range refused with no change");
}

fn t17() -> TestResult {
  var t = ast_new();
  let n = ast_add_node(&mut t, AST_KIND_IDENT, 0, 1);
  var ok = streq(ast_label(&t, n), "");
  if ok && !ast_set_label(&mut t, n, "count") { ok = false; }
  if ok && !streq(ast_label(&t, n), "count") { ok = false; }
  if ok && !streq(ast_pretty(&t), "ident count [0,1)\n") { ok = false; }
  if ok && ast_set_label(&mut t, 7, "x") { ok = false; }
  if ok && !streq(ast_label(&t, n), "count") { ok = false; }
  return assert(ok, "set_label: default empty, overwrite shown by pretty, out-of-range refused");
}

fn t18() -> TestResult {
  let clean = ast_fixture_ast();
  var ok = ast_diagnostics(&clean).len() == 0;
  var bad = ast_new();
  let _ = ast_add_node(&mut bad, AST_KIND_IDENT, 9, 4);
  let _ = ast_add_node(&mut bad, AST_KIND_LITERAL, -3, 5);
  let _ = ast_add_node(&mut bad, AST_KIND_PROGRAM, 0, 3);
  let diags = ast_diagnostics(&bad);
  if ok && diags.len() != 2 { ok = false; }
  if ok {
    let d0: Str = diags[0];
    let d1: Str = diags[1];
    if !streq(d0, "ast: node 0 has inverted span [9,4)") { ok = false; }
    if !streq(d1, "ast: node 1 has negative span [-3,5)") { ok = false; }
  }
  return assert(ok, "diagnostics: clean fixture silent, inverted and negative spans reported in index order");
}

fn t19() -> TestResult {
  let fixture = ast_fixture_ast();
  var ok = ast_is_well_formed(&fixture);
  var forest = ast_new();
  let _ = ast_add_node(&mut forest, AST_KIND_PROGRAM, 0, 1);
  let _ = ast_add_node(&mut forest, AST_KIND_IDENT, 0, 1);
  if ok && !ast_is_well_formed(&forest) { ok = false; }
  var moved = ast_fixture_ast();
  let _ = ast_reparent(&mut moved, 0, 8);
  if ok && !ast_is_well_formed(&moved) { ok = false; }
  let _ = ast_reparent(&mut moved, 0, -1);
  if ok && !ast_is_well_formed(&moved) { ok = false; }
  return assert(ok, "well formed: true for fixture, forest and reparented trees (builder invariants)");
}

fn t20() -> TestResult {
  let src = ast_fixture_source();
  let t = ast_fixture_ast();
  var ok = streq(src, "let x = 1 + 2;\nif x { return x; } else { return 0; }");
  if ok && src.len() != 52 { ok = false; }
  if ok && !streq(ast_span_text(src, &t, 13), src) { ok = false; }
  if ok && !streq(ast_span_text(src, &t, 0), "1") { ok = false; }
  if ok && !streq(ast_span_text(src, &t, 2), "1 + 2") { ok = false; }
  if ok && !streq(ast_span_text(src, &t, 3), "x") { ok = false; }
  if ok && !streq(ast_span_text(src, &t, 5), "x") { ok = false; }
  if ok && !streq(ast_span_text(src, &t, 8), "{ return x; }") { ok = false; }
  if ok && !streq(ast_span_text(src, &t, 6), "return x") { ok = false; }
  if ok && !streq(ast_span_text(src, &t, 9), "return 0") { ok = false; }
  if ok && !streq(ast_span_text(src, &t, 12), "if x { return x; } else { return 0; }") { ok = false; }
  return assert(ok, "span text: 52-byte fixture, program spans all of it, node slices exact");
}

fn t21() -> TestResult {
  let s1 = ast_fixture_source();
  let s2 = ast_fixture_source();
  let t1 = ast_fixture_ast();
  let t2 = ast_fixture_ast();
  var ok = streq(s1, s2);
  if ok && ast_node_count(&t1) != ast_node_count(&t2) { ok = false; }
  let pre1 = ast_preorder(&t1);
  let pre2 = ast_preorder(&t2);
  let post1 = ast_postorder(&t1);
  let post2 = ast_postorder(&t2);
  if ok && !streq(join.vec_int_join(&pre1, ","), join.vec_int_join(&pre2, ",")) { ok = false; }
  if ok && !streq(join.vec_int_join(&post1, ","), join.vec_int_join(&post2, ",")) { ok = false; }
  if ok && !streq(ast_pretty(&t1), ast_pretty(&t2)) { ok = false; }
  if ok && !streq(rows_code(&ast_span_table(&t1)), rows_code(&ast_span_table(&t2))) { ok = false; }
  return assert(ok, "determinism: two fixture builds give identical order, pretty and span table");
}

fn t22() -> TestResult {
  var t = ast_new();
  let _ = ast_add_node(&mut t, AST_KIND_PROGRAM, 0, 0);
  var ok = ast_span_table(&t).len() == 1;
  if ok && ast_diagnostics(&t).len() != 0 { ok = false; }
  if ok && !ast_is_leaf(&t, 0) { ok = false; }
  if ok && ast_depth(&t, 0) != 0 { ok = false; }
  if ok && !streq(ast_pretty(&t), "program [0,0)\n") { ok = false; }
  if ok && !streq(ast_span_row(&t, 0), "0: program [0,0) parent=-1 depth=0") { ok = false; }
  return assert(ok, "zero-width span: legal, no diagnostic, still a leaf and a root");
}

fn t23() -> TestResult {
  let t = ast_fixture_ast();
  var ok = ast_child_count(&t, 13) == 2;
  if ok && ast_child_count(&t, 4) != 2 { ok = false; }
  if ok && ast_child_count(&t, 12) != 3 { ok = false; }
  if ok && ast_child_count(&t, 2) != 2 { ok = false; }
  if ok && ast_child_count(&t, 8) != 1 { ok = false; }
  if ok && ast_child_count(&t, 11) != 1 { ok = false; }
  if ok && ast_child_count(&t, 0) != 0 { ok = false; }
  if ok && ast_child(&t, 12, 0) != 5 { ok = false; }
  if ok && ast_child(&t, 12, 1) != 8 { ok = false; }
  if ok && ast_child(&t, 12, 2) != 11 { ok = false; }
  if ok && ast_child(&t, 12, 3) != -1 { ok = false; }
  return assert(ok, "fixture child counts: program 2, let 2, if 3, blocks 1, binary 2, leaves 0");
}

fn t24() -> TestResult {
  let t = ast_fixture_ast();
  var ok = streq(kinds_code(&t), "8,8,6,7,2,7,5,7,4,5,8,4,3,1");
  if ok && ast_kind(&t, 13) != AST_KIND_PROGRAM { ok = false; }
  if ok && ast_kind(&t, 12) != AST_KIND_IF { ok = false; }
  if ok && ast_kind(&t, 9) != AST_KIND_RETURN { ok = false; }
  if ok && ast_kind(&t, 2) != AST_KIND_BINARY { ok = false; }
  if ok && ast_kind(&t, 7) != AST_KIND_IDENT { ok = false; }
  if ok && ast_kind(&t, 10) != AST_KIND_LITERAL { ok = false; }
  return assert(ok, "fixture kinds: storage order 8,8,6,7,2,7,5,7,4,5,8,4,3,1 (non-preorder creation)");
}

// ---------------------------------------------------------------------------

fn report(r: TestResult) -> Int {
  if r.passed {
    io.println("  [PASS] " + r.name);
    return 0;
  }
  io.println("  [FAIL] " + r.name);
  return 1;
}

fn main() -> Int {
  io.println("=== xiom.ast conformance tests ===");
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
  failed = failed + report(t24());
  if failed == 0 {
    io.println("xiom.ast: all tests passed");
  } else {
    io.println("xiom.ast: tests failed");
  }
  return failed;
}
