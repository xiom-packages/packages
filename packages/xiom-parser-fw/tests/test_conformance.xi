// XIOM -- xiom.parser-fw conformance tests (27 checks)
// Port task: prove the pure-XIOM xiom.parser_fw module against its SPEC.md:
// token model, grammar arena, core engine, precedence climbing, panic-mode
// recovery and the parse-tree model.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module parser_fw_tests
use xiom.io; use xiom.test; use xiom.parser_fw;
use xiom.string; use xiom.string.compare; use xiom.convert;

// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison.
fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// ---------------------------------------------------------------------------
// Fixture token kinds (operator kinds are caller-defined; binding-power
// tables are keyed by them)
// ---------------------------------------------------------------------------

const TK_PLUS: Int = 20;
const TK_MINUS: Int = 21;
const TK_STAR: Int = 22;
const TK_SLASH: Int = 23;
const TK_LPAREN: Int = 24;
const TK_RPAREN: Int = 25;
const TK_SEMI: Int = 26;
const TK_EQ: Int = 27;
const TK_LET: Int = 28;
const TK_BAD: Int = 29;

// Rule indices of make_expr_g (build order is fixed).
const RULE_INT: Int = 0;
const RULE_IDENT: Int = 1;
const EXPR_RULE: Int = 4;
const ATOM_RULE: Int = 8;

// make_stmt_g appends after the nine expression rules.
const STMT_RULE: Int = 16;
const PROG_RULE: Int = 17;

// ---------------------------------------------------------------------------
// Token streams
// ---------------------------------------------------------------------------

fn ts_1(k0: Int) -> TokenStream {
  var t = ts_new();
  ts_push(&mut t, k0, 0, 1);
  return t;
}

fn ts_2(k0: Int, k1: Int) -> TokenStream {
  var t = ts_new();
  ts_push(&mut t, k0, 0, 1);
  ts_push(&mut t, k1, 1, 2);
  return t;
}

fn ts_3(k0: Int, k1: Int, k2: Int) -> TokenStream {
  var t = ts_new();
  ts_push(&mut t, k0, 0, 1);
  ts_push(&mut t, k1, 1, 2);
  ts_push(&mut t, k2, 2, 3);
  return t;
}

fn ts_ints_3() -> TokenStream {
  var t = ts_new();
  ts_push(&mut t, P_KIND_INT, 0, 1);
  ts_push(&mut t, P_KIND_INT, 1, 2);
  ts_push(&mut t, P_KIND_INT, 2, 3);
  return t;
}

// "1+2*3"
fn ts_add_mul() -> TokenStream {
  var t = ts_new();
  ts_push(&mut t, P_KIND_INT, 0, 1);
  ts_push(&mut t, TK_PLUS, 1, 2);
  ts_push(&mut t, P_KIND_INT, 2, 3);
  ts_push(&mut t, TK_STAR, 3, 4);
  ts_push(&mut t, P_KIND_INT, 4, 5);
  return t;
}

// "1*2+3"
fn ts_mul_add() -> TokenStream {
  var t = ts_new();
  ts_push(&mut t, P_KIND_INT, 0, 1);
  ts_push(&mut t, TK_STAR, 1, 2);
  ts_push(&mut t, P_KIND_INT, 2, 3);
  ts_push(&mut t, TK_PLUS, 3, 4);
  ts_push(&mut t, P_KIND_INT, 4, 5);
  return t;
}

// "1-2-3"
fn ts_sub_sub() -> TokenStream {
  var t = ts_new();
  ts_push(&mut t, P_KIND_INT, 0, 1);
  ts_push(&mut t, TK_MINUS, 1, 2);
  ts_push(&mut t, P_KIND_INT, 2, 3);
  ts_push(&mut t, TK_MINUS, 3, 4);
  ts_push(&mut t, P_KIND_INT, 4, 5);
  return t;
}

// "-1+2"
fn ts_neg_add() -> TokenStream {
  var t = ts_new();
  ts_push(&mut t, TK_MINUS, 0, 1);
  ts_push(&mut t, P_KIND_INT, 1, 2);
  ts_push(&mut t, TK_PLUS, 2, 3);
  ts_push(&mut t, P_KIND_INT, 3, 4);
  return t;
}

// "(1+2)*3"
fn ts_paren_mul() -> TokenStream {
  var t = ts_new();
  ts_push(&mut t, TK_LPAREN, 0, 1);
  ts_push(&mut t, P_KIND_INT, 1, 2);
  ts_push(&mut t, TK_PLUS, 2, 3);
  ts_push(&mut t, P_KIND_INT, 3, 4);
  ts_push(&mut t, TK_RPAREN, 4, 5);
  ts_push(&mut t, TK_STAR, 5, 6);
  ts_push(&mut t, P_KIND_INT, 6, 7);
  return t;
}

// "((1))"
fn ts_nested_paren() -> TokenStream {
  var t = ts_new();
  ts_push(&mut t, TK_LPAREN, 0, 1);
  ts_push(&mut t, TK_LPAREN, 1, 2);
  ts_push(&mut t, P_KIND_INT, 2, 3);
  ts_push(&mut t, TK_RPAREN, 3, 4);
  ts_push(&mut t, TK_RPAREN, 4, 5);
  return t;
}

// "let x = 1 ; @ @ let y = 2 ;" -- spans as in the source literal.
fn ts_recover() -> TokenStream {
  var t = ts_new();
  ts_push(&mut t, TK_LET, 0, 3);
  ts_push(&mut t, P_KIND_IDENT, 4, 5);
  ts_push(&mut t, TK_EQ, 6, 7);
  ts_push(&mut t, P_KIND_INT, 8, 9);
  ts_push(&mut t, TK_SEMI, 10, 11);
  ts_push(&mut t, TK_BAD, 12, 13);
  ts_push(&mut t, TK_BAD, 14, 15);
  ts_push(&mut t, TK_LET, 16, 19);
  ts_push(&mut t, P_KIND_IDENT, 20, 21);
  ts_push(&mut t, TK_EQ, 22, 23);
  ts_push(&mut t, P_KIND_INT, 24, 25);
  ts_push(&mut t, TK_SEMI, 26, 27);
  return t;
}

// "@ @ let x = 1 ; @ @ let y = 2 ;"
fn ts_leading_bad() -> TokenStream {
  var t = ts_new();
  ts_push(&mut t, TK_BAD, 0, 1);
  ts_push(&mut t, TK_BAD, 2, 3);
  ts_push(&mut t, TK_LET, 4, 7);
  ts_push(&mut t, P_KIND_IDENT, 8, 9);
  ts_push(&mut t, TK_EQ, 10, 11);
  ts_push(&mut t, P_KIND_INT, 12, 13);
  ts_push(&mut t, TK_SEMI, 14, 15);
  ts_push(&mut t, TK_BAD, 16, 17);
  ts_push(&mut t, TK_BAD, 18, 19);
  ts_push(&mut t, TK_LET, 20, 23);
  ts_push(&mut t, P_KIND_IDENT, 24, 25);
  ts_push(&mut t, TK_EQ, 26, 27);
  ts_push(&mut t, P_KIND_INT, 28, 29);
  ts_push(&mut t, TK_SEMI, 30, 31);
  return t;
}

// ---------------------------------------------------------------------------
// Grammar fixtures
// ---------------------------------------------------------------------------

// Expression grammar: 1+2*3 style, unary minus, parenthesized atom.
fn make_expr_g() -> Grammar {
  var g = grammar_new();
  let r_int = rule_token(&mut g, P_KIND_INT, "number");
  let r_ident = rule_token(&mut g, P_KIND_IDENT, "identifier");
  let r_lpar = rule_token(&mut g, TK_LPAREN, "(");
  let r_rpar = rule_token(&mut g, TK_RPAREN, ")");
  let r_expr = rule_prec(&mut g, 0, "expr");
  let r_paren = rule_seq3(&mut g, r_lpar, r_expr, r_rpar, "paren");
  let r_atom = rule_choice(&mut g, r_int, r_ident, "atom");
  let r_atom2 = rule_choice(&mut g, r_atom, r_paren, "");
  rule_patch_a(&mut g, r_expr, r_atom2);
  grammar_op_add(&mut g, TK_PLUS, 1, 2);
  grammar_op_add(&mut g, TK_MINUS, 1, 2);
  grammar_op_add(&mut g, TK_STAR, 3, 4);
  grammar_op_add(&mut g, TK_SLASH, 3, 4);
  grammar_prefix_add(&mut g, TK_MINUS, 5);
  return g;
}

// Statement list over the expression grammar, with a panic set.
fn make_stmt_g() -> Grammar {
  var g = make_expr_g();
  let r_let = rule_token(&mut g, TK_LET, "let");
  let r_name = rule_token(&mut g, P_KIND_IDENT, "identifier");
  let r_eq = rule_token(&mut g, TK_EQ, "=");
  let r_semi = rule_token(&mut g, TK_SEMI, ";");
  let h = rule_seq(&mut g, r_let, r_name, "let-head");
  let h2 = rule_seq(&mut g, h, r_eq, "let-eq");
  let h3 = rule_seq(&mut g, h2, EXPR_RULE, "let-val");
  let stmt = rule_seq(&mut g, h3, r_semi, "let-stmt");
  rule_repeat0(&mut g, stmt, "prog");
  grammar_sync_add(&mut g, TK_SEMI);
  grammar_sync_add(&mut g, TK_LET);
  return g;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

fn t1() -> TestResult {
  var t = ts_new();
  ts_push(&mut t, P_KIND_KEYWORD, 0, 3);
  ts_push(&mut t, P_KIND_IDENT, 4, 5);
  var ok = ts_len(&t) == 2;
  if ts_kind(&t, 0) != P_KIND_KEYWORD { ok = false; }
  if ts_kind(&t, 1) != P_KIND_IDENT { ok = false; }
  if ts_kind(&t, 2) != P_KIND_EOF { ok = false; }
  if ts_kind(&t, -1) != P_KIND_EOF { ok = false; }
  if ts_start(&t, 0) != 0 { ok = false; }
  if ts_end(&t, 0) != 3 { ok = false; }
  if ts_start(&t, 1) != 4 { ok = false; }
  if ts_end(&t, 9) != -1 { ok = false; }
  if ts_start(&t, -3) != -1 { ok = false; }
  if !streq(token_text("let x", &t, 0), "let") { ok = false; }
  if !streq(token_text("let x", &t, 1), "x") { ok = false; }
  if !streq(token_text("let x", &t, 5), "") { ok = false; }
  if !streq(ts_kind_name(P_KIND_NONE), "none") { ok = false; }
  if !streq(ts_kind_name(P_KIND_EOF), "EOF") { ok = false; }
  if !streq(ts_kind_name(P_KIND_IDENT), "ident") { ok = false; }
  if !streq(ts_kind_name(P_KIND_INT), "int") { ok = false; }
  if !streq(ts_kind_name(P_KIND_STRING), "string") { ok = false; }
  if !streq(ts_kind_name(P_KIND_OP), "op") { ok = false; }
  if !streq(ts_kind_name(P_KIND_PUNCT), "punct") { ok = false; }
  if !streq(ts_kind_name(P_KIND_KEYWORD), "keyword") { ok = false; }
  if !streq(ts_kind_name(12345), "?") { ok = false; }
  return assert(ok, "token stream: push/len/kind/start/end, EOF and -1 ranges, raw text, kind names");
}

fn t2() -> TestResult {
  var kt = kt_new();
  kt_add(&mut kt, "let", P_KIND_KEYWORD);
  kt_add(&mut kt, "+", P_KIND_OP);
  kt_add(&mut kt, "==", P_KIND_OP);
  var ok = kt_len(&kt) == 3;
  if !streq(kt_word(&kt, 0), "let") { ok = false; }
  if kt_kind(&kt, 0) != P_KIND_KEYWORD { ok = false; }
  if kt_lookup(&kt, "let") != P_KIND_KEYWORD { ok = false; }
  if kt_lookup(&kt, "lets") != P_KIND_NONE { ok = false; }
  if kt_lookup(&kt, "") != P_KIND_NONE { ok = false; }
  if kt_classify(&kt, "==") != P_KIND_OP { ok = false; }
  if kt_classify(&kt, "x") != P_KIND_IDENT { ok = false; }
  if !streq(kt_word(&kt, 99), "") { ok = false; }
  if kt_kind(&kt, 99) != P_KIND_NONE { ok = false; }
  if kt_kind(&kt, -1) != P_KIND_NONE { ok = false; }
  return assert(ok, "kind table: exact lookup, identifier fallback, range safety");
}

fn t3() -> TestResult {
  let g = make_expr_g();
  var ok = grammar_rule_count(&g) == 9;
  if !grammar_is_consistent(&g) { ok = false; }
  if grammar_rule_kind(&g, EXPR_RULE) != P_RULE_PREC { ok = false; }
  if grammar_rule_a(&g, EXPR_RULE) != ATOM_RULE { ok = false; }
  if grammar_rule_kind(&g, ATOM_RULE) != P_RULE_CHOICE { ok = false; }
  if !streq(grammar_rule_label(&g, RULE_INT), "number") { ok = false; }
  if !streq(grammar_rule_label(&g, 99), "") { ok = false; }
  if grammar_rule_kind(&g, 99) != -1 { ok = false; }
  if grammar_rule_a(&g, 99) != -1 { ok = false; }
  if grammar_rule_b(&g, -1) != -1 { ok = false; }
  if grammar_rule_token(&g, RULE_INT) != P_KIND_INT { ok = false; }
  let s = make_stmt_g();
  if grammar_rule_count(&s) != 18 { ok = false; }
  if !grammar_is_consistent(&s) { ok = false; }
  if grammar_rule_kind(&s, PROG_RULE) != P_RULE_REPEAT0 { ok = false; }
  var g2 = grammar_new();
  let r_tmp = rule_empty(&mut g2, "tmp");
  rule_patch_a(&mut g2, 99, r_tmp);
  rule_patch_b(&mut g2, -1, r_tmp);
  if grammar_rule_a(&g2, r_tmp) != -1 { ok = false; }
  return assert(ok, "grammar arena: builders, accessors, recursion patch, parallel-vector consistency");
}

fn t4() -> TestResult {
  var g = grammar_new();
  let r_empty = rule_empty(&mut g, "eps");
  let r_eof = rule_eof(&mut g, "end");
  let ts = ts_new();
  let o1 = parse_run(&g, r_empty, &ts, 4);
  let o2 = parse_run(&g, r_eof, &ts, 4);
  let ts2 = ts_1(P_KIND_INT);
  let o3 = parse_run(&g, r_eof, &ts2, 4);
  var ok = o1.ok;
  if !streq(tree_to_sexpr(&g, "", &ts, &o1.tree, o1.root), "<empty>") { ok = false; }
  if !o2.ok { ok = false; }
  if o3.ok { ok = false; }
  if o3.error_count != 1 { ok = false; }
  let e0: Str = o3.errors[0];
  if !streq(e0, "parser: expected end at token 0") { ok = false; }
  return assert(ok, "empty and EOF rules: empty match, end-of-input guard, exact error");
}

fn t5() -> TestResult {
  let g = make_expr_g();
  let ts = ts_1(P_KIND_INT);
  let o = parse_run(&g, RULE_INT, &ts, 4);
  var ok = o.ok;
  if o.pos != 1 { ok = false; }
  if tree_node_kind(&o.tree, o.root) != P_NODE_TOKEN { ok = false; }
  if tree_node_token(&o.tree, o.root) != 0 { ok = false; }
  if tree_node_start(&o.tree, o.root) != 0 { ok = false; }
  if tree_node_end(&o.tree, o.root) != 1 { ok = false; }
  if !streq(tree_to_sexpr(&g, "7", &ts, &o.tree, o.root), "7") { ok = false; }
  return assert(ok, "token rule: kind match, span, cursor advance, token-node fields");
}

fn t6() -> TestResult {
  let g = make_expr_g();
  let ts = ts_1(P_KIND_IDENT);
  let o = parse_run(&g, RULE_INT, &ts, 4);
  var ok = !o.ok;
  if o.root != -1 { ok = false; }
  if o.pos != 0 { ok = false; }
  if o.error_count != 1 { ok = false; }
  let e0: Str = o.errors[0];
  if !streq(e0, "parser: expected number at token 0") { ok = false; }
  return assert(ok, "token rule failure: root -1, cursor restored, exact expected message");
}

fn t7() -> TestResult {
  var g = grammar_new();
  let r_let = rule_token(&mut g, TK_LET, "let");
  let r_name = rule_token(&mut g, P_KIND_IDENT, "identifier");
  let r_seq = rule_seq(&mut g, r_let, r_name, "let-head");
  var ts = ts_new();
  ts_push(&mut ts, TK_LET, 0, 3);
  ts_push(&mut ts, P_KIND_IDENT, 4, 5);
  let o = parse_run(&g, r_seq, &ts, 4);
  var ok = o.ok;
  if o.pos != 2 { ok = false; }
  if tree_node_kind(&o.tree, o.root) != P_NODE_RULE { ok = false; }
  if tree_child_count(&o.tree, o.root) != 2 { ok = false; }
  if tree_node_start(&o.tree, o.root) != 0 { ok = false; }
  if tree_node_end(&o.tree, o.root) != 2 { ok = false; }
  if !streq(tree_to_sexpr(&g, "let x", &ts, &o.tree, o.root), "(let-head let x)") { ok = false; }
  return assert(ok, "sequence rule: children in order, span, labeled S-expression");
}

fn t8() -> TestResult {
  var g = grammar_new();
  let r_int = rule_token(&mut g, P_KIND_INT, "number");
  let r_ident = rule_token(&mut g, P_KIND_IDENT, "identifier");
  let r_seq = rule_seq(&mut g, r_int, r_ident, "pair");
  let ts = ts_2(P_KIND_INT, TK_PLUS);
  let o = parse_run(&g, r_seq, &ts, 4);
  var ok = !o.ok;
  if o.pos != 0 { ok = false; }
  if tree_len(&o.tree) != 0 { ok = false; }
  if o.error_count != 1 { ok = false; }
  let e0: Str = o.errors[0];
  if !streq(e0, "parser: expected identifier at token 1") { ok = false; }
  return assert(ok, "sequence rollback: failed tail restores cursor and discards partial nodes");
}

fn t9() -> TestResult {
  var g = grammar_new();
  let r_int = rule_token(&mut g, P_KIND_INT, "number");
  let r_ident = rule_token(&mut g, P_KIND_IDENT, "identifier");
  let r_choice = rule_choice(&mut g, r_int, r_ident, "atom");
  let ts = ts_1(P_KIND_INT);
  let o = parse_run(&g, r_choice, &ts, 4);
  var ok = o.ok;
  if tree_node_kind(&o.tree, o.root) != P_NODE_TOKEN { ok = false; }
  if o.pos != 1 { ok = false; }
  if !streq(tree_to_sexpr(&g, "5", &ts, &o.tree, o.root), "5") { ok = false; }
  return assert(ok, "ordered choice: first alternative wins without a wrapper node");
}

fn t10() -> TestResult {
  var g = grammar_new();
  let r_int = rule_token(&mut g, P_KIND_INT, "number");
  let r_ident = rule_token(&mut g, P_KIND_IDENT, "identifier");
  let r_choice = rule_choice(&mut g, r_int, r_ident, "atom");
  let ts = ts_1(P_KIND_IDENT);
  let o = parse_run(&g, r_choice, &ts, 4);
  var ok = o.ok;
  if tree_node_kind(&o.tree, o.root) != P_NODE_TOKEN { ok = false; }
  if tree_node_rule(&o.tree, o.root) != RULE_IDENT { ok = false; }
  if !streq(tree_to_sexpr(&g, "x", &ts, &o.tree, o.root), "x") { ok = false; }
  return assert(ok, "ordered choice: second alternative after a clean first failure");
}

fn t11() -> TestResult {
  var g = grammar_new();
  let r_int = rule_token(&mut g, P_KIND_INT, "number");
  let r_ident = rule_token(&mut g, P_KIND_IDENT, "identifier");
  let r_a = rule_seq(&mut g, r_int, r_ident, "id-pair");
  let r_b = rule_seq(&mut g, r_int, r_int, "int-pair");
  let r_choice = rule_choice(&mut g, r_a, r_b, "pair");
  let ts = ts_2(P_KIND_INT, TK_PLUS);
  let o = parse_run(&g, r_choice, &ts, 4);
  var ok = !o.ok;
  if o.pos != 0 { ok = false; }
  if o.error_count != 1 { ok = false; }
  let e0: Str = o.errors[0];
  if !streq(e0, "parser: expected identifier at token 1") { ok = false; }
  return assert(ok, "choice diagnostics: furthest failure position and first label win");
}

fn t12() -> TestResult {
  var g = grammar_new();
  let r_int = rule_token(&mut g, P_KIND_INT, "number");
  let r_list = rule_repeat0(&mut g, r_int, "list");
  let ts = ts_new();
  let o = parse_run(&g, r_list, &ts, 4);
  var ok = o.ok;
  if o.root != 0 { ok = false; }
  if tree_child_count(&o.tree, o.root) != 0 { ok = false; }
  if !streq(tree_to_sexpr(&g, "", &ts, &o.tree, o.root), "(list)") { ok = false; }
  return assert(ok, "repeat0: empty input yields one empty list node");
}

fn t13() -> TestResult {
  var g = grammar_new();
  let r_int = rule_token(&mut g, P_KIND_INT, "number");
  let r_list = rule_repeat0(&mut g, r_int, "list");
  let ts = ts_ints_3();
  let o = parse_run(&g, r_list, &ts, 4);
  var ok = o.ok;
  if o.pos != 3 { ok = false; }
  if tree_child_count(&o.tree, o.root) != 3 { ok = false; }
  if tree_node_end(&o.tree, o.root) != 3 { ok = false; }
  if !streq(tree_to_sexpr(&g, "123", &ts, &o.tree, o.root), "(list 1 2 3)") { ok = false; }
  return assert(ok, "repeat0: many matches, child order and growing span");
}

fn t14() -> TestResult {
  var g = grammar_new();
  let r_empty = rule_empty(&mut g, "eps");
  let r_list = rule_repeat0(&mut g, r_empty, "list");
  let ts = ts_new();
  let o = parse_run(&g, r_list, &ts, 4);
  var ok = o.ok;
  if tree_child_count(&o.tree, o.root) != 1 { ok = false; }
  if tree_node_kind(&o.tree, tree_child(&o.tree, o.root, 0)) != P_NODE_EMPTY { ok = false; }
  if !streq(tree_to_sexpr(&g, "", &ts, &o.tree, o.root), "(list <empty>)") { ok = false; }
  return assert(ok, "repeat0 progress guard: an empty child match stops the loop after one node");
}

fn t15() -> TestResult {
  var g = grammar_new();
  let r_int = rule_token(&mut g, P_KIND_INT, "number");
  let r_list = rule_repeat1(&mut g, r_int, "list1");
  let ts = ts_1(TK_PLUS);
  let o = parse_run(&g, r_list, &ts, 4);
  var ok = !o.ok;
  if o.pos != 0 { ok = false; }
  if tree_len(&o.tree) != 0 { ok = false; }
  if o.error_count != 1 { ok = false; }
  let e0: Str = o.errors[0];
  if !streq(e0, "parser: expected number at token 0") { ok = false; }
  return assert(ok, "repeat1: no first match fails and rolls back completely");
}

fn t16() -> TestResult {
  var g = grammar_new();
  let r_int = rule_token(&mut g, P_KIND_INT, "number");
  let r_list = rule_repeat1(&mut g, r_int, "list1");
  let ts = ts_2(P_KIND_INT, P_KIND_INT);
  let o = parse_run(&g, r_list, &ts, 4);
  var ok = o.ok;
  if tree_child_count(&o.tree, o.root) != 2 { ok = false; }
  if !streq(tree_to_sexpr(&g, "12", &ts, &o.tree, o.root), "(list1 1 2)") { ok = false; }
  return assert(ok, "repeat1: many matches succeed");
}

fn t17() -> TestResult {
  var g = grammar_new();
  let r_int = rule_token(&mut g, P_KIND_INT, "number");
  let r_opt = rule_optional(&mut g, r_int, "opt");
  let ts1 = ts_1(P_KIND_INT);
  let o1 = parse_run(&g, r_opt, &ts1, 4);
  let ts2 = ts_1(TK_PLUS);
  let o2 = parse_run(&g, r_opt, &ts2, 4);
  var ok = o1.ok;
  if !streq(tree_to_sexpr(&g, "9", &ts1, &o1.tree, o1.root), "9") { ok = false; }
  if !o2.ok { ok = false; }
  if o2.pos != 0 { ok = false; }
  if tree_node_kind(&o2.tree, o2.root) != P_NODE_EMPTY { ok = false; }
  if !streq(tree_to_sexpr(&g, "", &ts2, &o2.tree, o2.root), "<empty>") { ok = false; }
  return assert(ok, "optional: present child passes through, absent yields one empty node");
}

fn t18() -> TestResult {
  let g = make_expr_g();
  let ts = ts_add_mul();
  let o = parse_run(&g, EXPR_RULE, &ts, 4);
  var ok = o.ok;
  if !streq(tree_to_sexpr(&g, "1+2*3", &ts, &o.tree, o.root), "(1 + (2 * 3))") { ok = false; }
  return assert(ok, "precedence: '*' binds tighter than '+' (1+2*3)");
}

fn t19() -> TestResult {
  let g = make_expr_g();
  let ts = ts_mul_add();
  let o = parse_run(&g, EXPR_RULE, &ts, 4);
  var ok = o.ok;
  if !streq(tree_to_sexpr(&g, "1*2+3", &ts, &o.tree, o.root), "((1 * 2) + 3)") { ok = false; }
  return assert(ok, "precedence: lower operator joins completed higher group (1*2+3)");
}

fn t20() -> TestResult {
  let g = make_expr_g();
  let ts = ts_sub_sub();
  let o = parse_run(&g, EXPR_RULE, &ts, 4);
  var ok = o.ok;
  if !streq(tree_to_sexpr(&g, "1-2-3", &ts, &o.tree, o.root), "((1 - 2) - 3)") { ok = false; }
  return assert(ok, "precedence: left associativity via rbp = lbp + 1 (1-2-3)");
}

fn t21() -> TestResult {
  let g = make_expr_g();
  let ts = ts_neg_add();
  let o = parse_run(&g, EXPR_RULE, &ts, 4);
  var ok = o.ok;
  if !streq(tree_to_sexpr(&g, "-1+2", &ts, &o.tree, o.root), "((- 1) + 2)") { ok = false; }
  return assert(ok, "precedence: prefix minus binds only its operand (-1+2)");
}

fn t22() -> TestResult {
  let g = make_expr_g();
  let ts = ts_paren_mul();
  let o = parse_run(&g, EXPR_RULE, &ts, 4);
  var ok = o.ok;
  if o.pos != 7 { ok = false; }
  if tree_node_kind(&o.tree, o.root) != P_NODE_RULE { ok = false; }
  let star = tree_child(&o.tree, o.root, 1);
  if !streq(token_text("(1+2)*3", &ts, tree_node_token(&o.tree, star)), "*") { ok = false; }
  let paren = tree_child(&o.tree, o.root, 0);
  if tree_child_count(&o.tree, paren) != 2 { ok = false; }
  let ab = tree_child(&o.tree, paren, 0);
  let inner = tree_child(&o.tree, ab, 1);
  if !streq(tree_to_sexpr(&g, "(1+2)*3", &ts, &o.tree, inner), "(1 + 2)") { ok = false; }
  let ts2 = ts_nested_paren();
  let o2 = parse_run(&g, EXPR_RULE, &ts2, 4);
  if !o2.ok { ok = false; }
  if o2.pos != 5 { ok = false; }
  if tree_node_kind(&o2.tree, o2.root) != P_NODE_RULE { ok = false; }
  return assert(ok, "precedence: parentheses override binding and recursion is data-driven");
}

fn t23() -> TestResult {
  var g = make_expr_g();
  let sfx = rule_eof(&mut g, "end");
  let r_root = rule_seq(&mut g, EXPR_RULE, sfx, "root");
  let ts_ok = ts_2(P_KIND_INT, P_KIND_INT);
  let o1 = parse_run(&g, r_root, &ts_ok, 4);
  let ts_ok2 = ts_1(P_KIND_INT);
  let o2 = parse_run(&g, r_root, &ts_ok2, 4);
  var ok = !o1.ok;
  if o1.error_count != 1 { ok = false; }
  let e0: Str = o1.errors[0];
  if !streq(e0, "parser: expected end at token 1") { ok = false; }
  if !o2.ok { ok = false; }
  if o2.pos != 1 { ok = false; }
  return assert(ok, "EOF guard: trailing tokens fail an expression-plus-EOF root");
}

fn t24() -> TestResult {
  let g = make_stmt_g();
  let src = "let x = 1 ; @ @ let y = 2 ;";
  let ts = ts_recover();
  let o = parse_run(&g, PROG_RULE, &ts, 4);
  var ok = o.ok;
  if o.error_count != 1 { ok = false; }
  if o.recovered != 2 { ok = false; }
  let e0: Str = o.errors[0];
  if !streq(e0, "parser: expected let at token 5") { ok = false; }
  let want = "(prog (let-stmt (let-val (let-eq (let-head let x) =) 1) ;) <err> (let-stmt (let-val (let-eq (let-head let y) =) 2) ;))";
  if !streq(tree_to_sexpr(&g, src, &ts, &o.tree, o.root), want) { ok = false; }
  let errnode = tree_child(&o.tree, o.root, 1);
  if tree_node_kind(&o.tree, errnode) != P_NODE_ERROR { ok = false; }
  if tree_node_start(&o.tree, errnode) != 5 { ok = false; }
  if tree_node_end(&o.tree, errnode) != 7 { ok = false; }
  if !streq(tree_span_text(src, &ts, &o.tree, errnode), "@ @") { ok = false; }
  return assert(ok, "panic-mode recovery: skip to sync set, error node, parsing continues (exact tree)");
}

fn t25() -> TestResult {
  let g = make_stmt_g();
  let ts = ts_leading_bad();
  let o = parse_run(&g, PROG_RULE, &ts, 1);
  var ok = o.ok;
  if o.error_count != 1 { ok = false; }
  if o.recovered != 2 { ok = false; }
  if !o.stopped { ok = false; }
  if o.pos != 2 { ok = false; }
  if !streq(tree_to_sexpr(&g, "", &ts, &o.tree, o.root), "(prog <err>)") { ok = false; }
  return assert(ok, "recovery budget: max_errors=1 stops after the first recovery");
}

fn t26() -> TestResult {
  let g = make_stmt_g();
  let ts = ts_recover();
  let o = parse_run(&g, PROG_RULE, &ts, 4);
  var ok = o.ok;
  if tree_child_count(&o.tree, o.root) != 3 { ok = false; }
  let c0 = tree_first_child(&o.tree, o.root);
  let c1 = tree_next_sibling(&o.tree, c0);
  let c2 = tree_next_sibling(&o.tree, c1);
  if c1 != tree_child(&o.tree, o.root, 1) { ok = false; }
  if c2 != tree_child(&o.tree, o.root, 2) { ok = false; }
  if tree_next_sibling(&o.tree, c2) != -1 { ok = false; }
  if tree_child(&o.tree, o.root, 3) != -1 { ok = false; }
  if tree_child(&o.tree, o.root, -1) != -1 { ok = false; }
  if tree_child_count(&o.tree, 999) != 0 { ok = false; }
  if tree_first_child(&o.tree, 999) != -1 { ok = false; }
  if tree_next_sibling(&o.tree, 999) != -1 { ok = false; }
  if tree_node_kind(&o.tree, 999) != -1 { ok = false; }
  if tree_node_rule(&o.tree, 999) != -1 { ok = false; }
  if tree_node_token(&o.tree, 999) != -1 { ok = false; }
  if tree_node_start(&o.tree, 999) != -1 { ok = false; }
  if tree_node_end(&o.tree, 999) != -1 { ok = false; }
  if !streq(tree_span_text("", &ts, &o.tree, 999), "") { ok = false; }
  return assert(ok, "parse-tree accessors: sibling walk, child indexing and range safety");
}

fn t27() -> TestResult {
  let g = make_stmt_g();
  let ts = ts_recover();
  let o1 = parse_run(&g, PROG_RULE, &ts, 4);
  let o2 = parse_run(&g, PROG_RULE, &ts, 4);
  var ok = o1.ok && o2.ok;
  if o1.error_count != o2.error_count { ok = false; }
  if o1.recovered != o2.recovered { ok = false; }
  if o1.pos != o2.pos { ok = false; }
  let s1 = tree_to_sexpr(&g, "let x = 1 ; @ @ let y = 2 ;", &ts, &o1.tree, o1.root);
  let s2 = tree_to_sexpr(&g, "let x = 1 ; @ @ let y = 2 ;", &ts, &o2.tree, o2.root);
  if !streq(s1, s2) { ok = false; }
  return assert(ok, "determinism: repeated parses yield identical trees, errors and cursor");
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
  io.println("=== xiom.parser-fw conformance tests ===");
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
  failed = failed + report(t25());
  failed = failed + report(t26());
  failed = failed + report(t27());
  if failed == 0 {
    io.println("xiom.parser-fw: all tests passed");
  } else {
    io.println("xiom.parser-fw: tests failed");
  }
  return failed;
}
