// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// XIOM -- xiom.parsing conformance tests (28 checks).
//
// Fixture-driven: a recursive arithmetic grammar and a compact JSON-subset
// grammar are built in-test with the public builder API, then exercised with
// direct calls (no fn tables, trap 5). All Str equality goes through
// str_compare (BUG 17 / trap 1) and all Result payload structs are bound to
// typed locals before use.
//
// Grammar fixture node ids are pinned by build order; t25 re-checks the kinds
// so a reordering fails loudly.

module parsing_tests
use xiom.io; use xiom.test; use xiom.parsing;
use xiom.string.compare; use xiom.convert;

// ---------------------------------------------------------------------------
// Pinned node ids of the arithmetic fixture (see arith_grammar)
// ---------------------------------------------------------------------------

const AR_DIGIT: Int = 0;
const AR_NUMBER: Int = 1;
const AR_LPAREN: Int = 2;
const AR_PAREN: Int = 7;
const AR_ATOM: Int = 8;
const AR_TERM: Int = 11;
const AR_EXPR: Int = 14;
const AR_EOF: Int = 15;
const AR_ROOT: Int = 16;
const AR_NODES: Int = 17;

// ---------------------------------------------------------------------------
// Pinned node ids of the JSON fixture (see json_grammar)
// ---------------------------------------------------------------------------

const JS_QUOTE: Int = 2;
const JS_STRING: Int = 10;
const JS_LBRACE: Int = 11;
const JS_LBRACK: Int = 13;
const JS_ARRAY: Int = 24;
const JS_OBJECT: Int = 31;
const JS_VALUE: Int = 37;
const JS_NODES: Int = 38;

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

// expr   := term ('+' term)*
// term   := atom ('*' atom)*
// atom   := '(' expr ')' | number
// number := [0-9]+
// root   := expr eof
// The parenthesized-expr reference is recursive and wired with
// parse_patch_child_a after the expr node exists.
fn arith_grammar() -> PGrammar {
  var g = parse_grammar_new();
  let n_digit = parse_class_pred(&mut g, PARSE_PRED_DIGIT, "digit");
  let n_number = parse_many1(&mut g, n_digit);
  let n_lparen = parse_literal(&mut g, "(", "'('");
  let n_rparen = parse_literal(&mut g, ")", "')'");
  let n_plus = parse_literal(&mut g, "+", "'+'");
  let n_star = parse_literal(&mut g, "*", "'*'");
  let n_paren_in = parse_seq(&mut g, -1, n_rparen);
  let n_paren = parse_seq(&mut g, n_lparen, n_paren_in);
  let n_atom = parse_alt(&mut g, n_paren, n_number);
  let n_star_atom = parse_seq(&mut g, n_star, n_atom);
  let n_star_tail = parse_many(&mut g, n_star_atom);
  let n_term = parse_seq(&mut g, n_atom, n_star_tail);
  let n_plus_term = parse_seq(&mut g, n_plus, n_term);
  let n_plus_tail = parse_many(&mut g, n_plus_term);
  let n_expr = parse_seq(&mut g, n_term, n_plus_tail);
  let n_eof = parse_eof(&mut g);
  let n_root = parse_seq(&mut g, n_expr, n_eof);
  parse_patch_child_a(&mut g, n_paren_in, n_expr);
  return g;
}

// value  := string | number | true | false | null | array | object
// string := '"' ( printable-not-quote-backslash )+ '"'
// array  := '[' ( value (',' value)* )? ']'
// object := '{' ( member (',' member)* )? '}'
// member := string ':' value
// Compact (no whitespace around tokens); the recursive value references are
// wired with parse_patch_child_a/b after the nodes exist.
fn json_grammar() -> PGrammar {
  var g = parse_grammar_new();
  let n_digit = parse_class_pred(&mut g, PARSE_PRED_DIGIT, "digit");
  let n_number = parse_many1(&mut g, n_digit);
  let n_quote = parse_literal(&mut g, "\"", "string");
  let n_c1 = parse_class_range(&mut g, 32, 33, "string character");
  let n_c2 = parse_class_range(&mut g, 35, 91, "string character");
  let n_c3 = parse_class_range(&mut g, 93, 126, "string character");
  let n_c23 = parse_alt(&mut g, n_c2, n_c3);
  let n_c123 = parse_alt(&mut g, n_c1, n_c23);
  let n_chars = parse_many1(&mut g, n_c123);
  let n_str_inner = parse_seq(&mut g, n_chars, n_quote);
  let n_string = parse_seq(&mut g, n_quote, n_str_inner);
  let n_lbrace = parse_literal(&mut g, "{", "'{'");
  let n_rbrace = parse_literal(&mut g, "}", "'}'");
  let n_lbrack = parse_literal(&mut g, "[", "'['");
  let n_rbrack = parse_literal(&mut g, "]", "']'");
  let n_comma = parse_literal(&mut g, ",", "','");
  let n_colon = parse_literal(&mut g, ":", "':'");
  let n_true = parse_literal(&mut g, "true", "true");
  let n_false = parse_literal(&mut g, "false", "false");
  let n_null = parse_literal(&mut g, "null", "null");
  let n_atail_item = parse_seq(&mut g, n_comma, -1);
  let n_atail = parse_many(&mut g, n_atail_item);
  let n_items = parse_seq(&mut g, -1, n_atail);
  let n_array_in = parse_seq(&mut g, n_lbrack, n_items);
  let n_array = parse_seq(&mut g, n_array_in, n_rbrack);
  let n_colon_v = parse_seq(&mut g, n_colon, -1);
  let n_member = parse_seq(&mut g, n_string, n_colon_v);
  let n_mtail_item = parse_seq(&mut g, n_comma, -1);
  let n_mtail = parse_many(&mut g, n_mtail_item);
  let n_members = parse_seq(&mut g, n_member, n_mtail);
  let n_obj_in = parse_seq(&mut g, n_lbrace, n_members);
  let n_object = parse_seq(&mut g, n_obj_in, n_rbrace);
  let n_a = parse_alt(&mut g, n_string, n_number);
  let n_b = parse_alt(&mut g, n_true, n_false);
  let n_c = parse_alt(&mut g, n_null, n_array);
  let n_d = parse_alt(&mut g, n_b, n_c);
  let n_e = parse_alt(&mut g, n_a, n_d);
  let n_value = parse_alt(&mut g, n_e, n_object);
  parse_patch_child_b(&mut g, n_atail_item, n_value);
  parse_patch_child_a(&mut g, n_items, n_value);
  parse_patch_child_b(&mut g, n_colon_v, n_value);
  parse_patch_child_b(&mut g, n_mtail_item, n_value);
  return g;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn flag_str(b: Bool) -> Str {
  if b {
    return "1";
  }
  return "0";
}

// "start:end:present" of a Result, or "<err>".
fn span_code(r: Result[PSpan, PError]) -> Str {
  match r {
    Ok(sp) => {
      let s: PSpan = sp;
      return int_to_string(s.start) + ":" + int_to_string(s.end) + ":" + flag_str(s.present);
    },
    Err(_) => { return "<err>"; },
  }
  return "<err>";
}

// Whole-input parse (run_all) span code.
fn all_code(g: &PGrammar, node: Int, src: Str) -> Str {
  return span_code(parse_run_all(g, node, src));
}

// Whole-input parse (run_all) raw text, or "<err>".
fn all_text(g: &PGrammar, node: Int, src: Str) -> Str {
  let r = parse_run_all(g, node, src);
  match r {
    Ok(sp) => {
      let s: PSpan = sp;
      return parse_span_text(src, &s);
    },
    Err(_) => { return "<err>"; },
  }
  return "<err>";
}

// State parse (run, trailing input allowed): "start:end:present@pos".
fn run_state_code(g: &PGrammar, node: Int, src: Str) -> Str {
  var st = parse_state_new(src);
  let r = parse_run(g, node, &mut st);
  let code = span_code(r);
  return code + "@" + int_to_string(st.pos);
}

fn err_pos(g: &PGrammar, node: Int, src: Str) -> Int {
  let r = parse_run_all(g, node, src);
  match r {
    Ok(_) => { return 999999; },
    Err(e) => {
      let er: PError = e;
      return er.pos;
    },
  }
  return 999999;
}

fn err_lc(g: &PGrammar, node: Int, src: Str) -> Str {
  let r = parse_run_all(g, node, src);
  match r {
    Ok(_) => { return "<ok>"; },
    Err(e) => {
      let er: PError = e;
      return int_to_string(er.line) + ":" + int_to_string(er.col);
    },
  }
  return "<ok>";
}

fn err_msg(g: &PGrammar, node: Int, src: Str) -> Str {
  let r = parse_run_all(g, node, src);
  match r {
    Ok(_) => { return "<ok>"; },
    Err(e) => {
      let er: PError = e;
      return er.message;
    },
  }
  return "<ok>";
}

fn err_found(g: &PGrammar, node: Int, src: Str) -> Str {
  let r = parse_run_all(g, node, src);
  match r {
    Ok(_) => { return "<ok>"; },
    Err(e) => {
      let er: PError = e;
      return er.found;
    },
  }
  return "<ok>";
}

fn err_exp_count(g: &PGrammar, node: Int, src: Str) -> Int {
  let r = parse_run_all(g, node, src);
  match r {
    Ok(_) => { return -1; },
    Err(e) => {
      let er: PError = e;
      return er.expected.len();
    },
  }
  return -1;
}

fn err_exp_at(g: &PGrammar, node: Int, src: Str, i: Int) -> Str {
  let r = parse_run_all(g, node, src);
  match r {
    Ok(_) => { return "<ok>"; },
    Err(e) => {
      let er: PError = e;
      if i < 0 || i >= er.expected.len() {
        return "<oob>";
      }
      let s: Str = er.expected[i];
      return s;
    },
  }
  return "<ok>";
}

fn err_exp_has(g: &PGrammar, node: Int, src: Str, label: Str) -> Bool {
  let r = parse_run_all(g, node, src);
  match r {
    Ok(_) => { return false; },
    Err(e) => {
      let er: PError = e;
      let n = er.expected.len();
      var i = 0;
      while i < n {
        let s: Str = er.expected[i];
        if compare.str_compare(s, label) == 0 {
          return true;
        }
        i = i + 1;
      }
      return false;
    },
  }
  return false;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

fn t1() -> TestResult {
  var g = parse_grammar_new();
  let n = parse_literal(&mut g, "let", "let");
  var ok = streq(run_state_code(&g, n, "let x"), "0:3:1@3");
  if !streq(all_code(&g, n, "let"), "0:3:1") { ok = false; }
  if !streq(all_text(&g, n, "let"), "let") { ok = false; }
  return assert(ok, "literal: exact match yields the literal byte span");
}

fn t2() -> TestResult {
  var g = parse_grammar_new();
  let n = parse_literal(&mut g, "let", "let");
  var ok = err_pos(&g, n, "x") == 0;
  if !streq(err_lc(&g, n, "x"), "1:1") { ok = false; }
  if err_exp_count(&g, n, "x") != 1 { ok = false; }
  if !err_exp_has(&g, n, "x", "let") { ok = false; }
  if !streq(err_found(&g, n, "x"), "x") { ok = false; }
  return assert(ok, "literal: mismatch yields a structured error (pos/line/col/expected)");
}

fn t3() -> TestResult {
  var g = parse_grammar_new();
  let n = parse_literal(&mut g, "", "empty");
  var ok = streq(all_code(&g, n, ""), "0:0:1");
  if !streq(run_state_code(&g, n, "x"), "0:0:1@0") { ok = false; }
  return assert(ok, "literal: empty literal matches zero-width");
}

fn t4() -> TestResult {
  var g = parse_grammar_new();
  let n = parse_class_range(&mut g, 97, 122, "lowercase");
  var ok = streq(all_code(&g, n, "q"), "0:1:1");
  if !streq(all_code(&g, n, "Z"), "<err>") { ok = false; }
  if err_pos(&g, n, "Z") != 0 { ok = false; }
  if !err_exp_has(&g, n, "Z", "lowercase") { ok = false; }
  return assert(ok, "class: range predicate matches exactly one byte");
}

fn t5() -> TestResult {
  var g = parse_grammar_new();
  let n_digit = parse_class_pred(&mut g, PARSE_PRED_DIGIT, "digit");
  let n_alpha = parse_class_pred(&mut g, PARSE_PRED_ALPHA, "alpha");
  let n_alnum = parse_class_pred(&mut g, PARSE_PRED_ALNUM, "alnum");
  let n_space = parse_class_pred(&mut g, PARSE_PRED_SPACE, "space");
  let n_istart = parse_class_pred(&mut g, PARSE_PRED_IDENT_START, "ident-start");
  let n_ibyte = parse_class_pred(&mut g, PARSE_PRED_IDENT_BYTE, "ident-byte");
  var ok = streq(run_state_code(&g, n_digit, "7"), "0:1:1@1");
  if !streq(run_state_code(&g, n_digit, "a"), "<err>@0") { ok = false; }
  if !streq(run_state_code(&g, n_alpha, "Z"), "0:1:1@1") { ok = false; }
  if !streq(run_state_code(&g, n_alpha, "3"), "<err>@0") { ok = false; }
  if !streq(run_state_code(&g, n_alnum, "3"), "0:1:1@1") { ok = false; }
  if !streq(run_state_code(&g, n_alnum, "_"), "<err>@0") { ok = false; }
  if !streq(run_state_code(&g, n_space, " "), "0:1:1@1") { ok = false; }
  if !streq(run_state_code(&g, n_space, "x"), "<err>@0") { ok = false; }
  if !streq(run_state_code(&g, n_istart, "_"), "0:1:1@1") { ok = false; }
  if !streq(run_state_code(&g, n_istart, "7"), "<err>@0") { ok = false; }
  if !streq(run_state_code(&g, n_ibyte, "7"), "0:1:1@1") { ok = false; }
  if !streq(run_state_code(&g, n_ibyte, "-"), "<err>@0") { ok = false; }
  if !streq(run_state_code(&g, n_ibyte, "é"), "<err>@0") { ok = false; }
  return assert(ok, "class: named predicates (digit/alpha/alnum/space/ident)");
}

fn t6() -> TestResult {
  var g = parse_grammar_new();
  let a = parse_literal(&mut g, "ab", "ab");
  let b = parse_literal(&mut g, "cd", "cd");
  let s = parse_seq(&mut g, a, b);
  var ok = streq(all_code(&g, s, "abcd"), "0:4:1");
  if !streq(all_text(&g, s, "abcd"), "abcd") { ok = false; }
  if err_pos(&g, s, "abxd") != 2 { ok = false; }
  if !err_exp_has(&g, s, "abxd", "cd") { ok = false; }
  if !streq(run_state_code(&g, s, "abxd"), "<err>@0") { ok = false; }
  return assert(ok, "seq: span covers both children and order is enforced");
}

fn t7() -> TestResult {
  var g = parse_grammar_new();
  let a = parse_literal(&mut g, "ab", "ab");
  let x = parse_literal(&mut g, "x", "x");
  let s = parse_seq(&mut g, a, x);
  let top = parse_alt(&mut g, s, a);
  var ok = streq(all_code(&g, top, "ab"), "0:2:1");
  if !streq(all_text(&g, top, "ab"), "ab") { ok = false; }
  return assert(ok, "seq: failure restores the position (alt recovers)");
}

fn t8() -> TestResult {
  var g = parse_grammar_new();
  let a = parse_literal(&mut g, "a", "a");
  let ab = parse_literal(&mut g, "ab", "ab");
  let top = parse_alt(&mut g, a, ab);
  var ok = streq(run_state_code(&g, top, "ab"), "0:1:1@1");
  if !streq(all_code(&g, top, "a"), "0:1:1") { ok = false; }
  return assert(ok, "alt: ordered choice, first success wins (no longest match)");
}

fn t9() -> TestResult {
  var g = parse_grammar_new();
  let ab = parse_literal(&mut g, "ab", "ab");
  let m = parse_many(&mut g, ab);
  var ok = streq(run_state_code(&g, m, "ababX"), "0:4:1@4");
  if !streq(run_state_code(&g, m, "X"), "0:0:1@0") { ok = false; }
  if !streq(run_state_code(&g, m, ""), "0:0:1@0") { ok = false; }
  if !streq(run_state_code(&g, m, "abab"), "0:4:1@4") { ok = false; }
  return assert(ok, "many: zero or more, greedy, stops at first failure");
}

fn t10() -> TestResult {
  var g = parse_grammar_new();
  let ab = parse_literal(&mut g, "ab", "ab");
  let m = parse_many1(&mut g, ab);
  var ok = streq(run_state_code(&g, m, "abab"), "0:4:1@4");
  if !streq(run_state_code(&g, m, "x"), "<err>@0") { ok = false; }
  if err_pos(&g, m, "x") != 0 { ok = false; }
  if !err_exp_has(&g, m, "x", "ab") { ok = false; }
  return assert(ok, "many1: requires one match, fails zero-width otherwise");
}

fn t11() -> TestResult {
  var g = parse_grammar_new();
  let ab = parse_literal(&mut g, "ab", "ab");
  let o = parse_optional(&mut g, ab);
  var ok = streq(run_state_code(&g, o, "ab"), "0:2:1@2");
  if !streq(run_state_code(&g, o, "x"), "0:0:0@0") { ok = false; }
  if !streq(all_code(&g, o, ""), "0:0:0") { ok = false; }
  return assert(ok, "optional: present/absent spans without failing");
}

fn t12() -> TestResult {
  var g = parse_grammar_new();
  let a = parse_literal(&mut g, "a", "a");
  let b = parse_literal(&mut g, "b", "b");
  let s = parse_seq(&mut g, a, b);
  let cap = parse_capture(&mut g, s);
  var ok = streq(all_code(&g, cap, "ab"), "0:2:1");
  if !streq(run_state_code(&g, cap, "ab"), "0:2:1@2") { ok = false; }
  let x = parse_literal(&mut g, "x", "x");
  let o = parse_optional(&mut g, x);
  let capo = parse_capture(&mut g, o);
  if !streq(run_state_code(&g, capo, "y"), "0:0:0@0") { ok = false; }
  return assert(ok, "capture: maps parses to the child's index range");
}

fn t13() -> TestResult {
  var g = parse_grammar_new();
  let ab = parse_literal(&mut g, "ab", "ab");
  let x = parse_literal(&mut g, "x", "x");
  let bad = parse_seq(&mut g, ab, x);
  let top = parse_alt(&mut g, bad, ab);
  let cap = parse_capture(&mut g, top);
  var ok = streq(all_code(&g, cap, "ab"), "0:2:1");
  if !streq(all_text(&g, cap, "ab"), "ab") { ok = false; }
  return assert(ok, "capture: range after a backtracking alt branch");
}

fn t14() -> TestResult {
  var g = parse_grammar_new();
  let e = parse_eof(&mut g);
  var ok = streq(run_state_code(&g, e, ""), "0:0:1@0");
  if !streq(run_state_code(&g, e, "x"), "<err>@0") { ok = false; }
  if !err_exp_has(&g, e, "x", "end of input") { ok = false; }
  let a = parse_literal(&mut g, "a", "a");
  if !streq(all_code(&g, a, "a"), "0:1:1") { ok = false; }
  if err_pos(&g, a, "ab") != 1 { ok = false; }
  if !err_exp_has(&g, a, "ab", "end of input") { ok = false; }
  return assert(ok, "eof: end-of-input check and run_all trailing-input error");
}

fn t15() -> TestResult {
  var g = parse_grammar_new();
  let a = parse_literal(&mut g, "a\n", "a-lf");
  let z = parse_literal(&mut g, "z", "z");
  let s = parse_seq(&mut g, a, z);
  var ok = err_pos(&g, s, "a\nb") == 2;
  if !streq(err_lc(&g, s, "a\nb"), "2:1") { ok = false; }
  let ab = parse_literal(&mut g, "ab", "ab");
  let cd = parse_literal(&mut g, "cd", "cd");
  let s2 = parse_seq(&mut g, ab, cd);
  if err_pos(&g, s2, "abXc") != 2 { ok = false; }
  if !streq(err_lc(&g, s2, "abXc"), "1:3") { ok = false; }
  return assert(ok, "error: 1-based line/column tracking across LF newlines");
}

fn t16() -> TestResult {
  var g = parse_grammar_new();
  let a = parse_literal(&mut g, "aa", "first");
  let b = parse_literal(&mut g, "bb", "second");
  let c = parse_literal(&mut g, "cc", "first");
  let inner = parse_alt(&mut g, b, c);
  let top = parse_alt(&mut g, a, inner);
  var ok = err_exp_count(&g, top, "zz") == 2;
  if !err_exp_has(&g, top, "zz", "first") { ok = false; }
  if !err_exp_has(&g, top, "zz", "second") { ok = false; }
  return assert(ok, "error: expected set deduplicates labels at the same position");
}

fn t17() -> TestResult {
  var g = parse_grammar_new();
  let a = parse_literal(&mut g, "ab", "first");
  let ax = parse_literal(&mut g, "a", "second");
  let cd = parse_literal(&mut g, "cd", "third");
  let s = parse_seq(&mut g, ax, cd);
  let top = parse_alt(&mut g, a, s);
  var ok = err_pos(&g, top, "ay") == 1;
  if err_exp_count(&g, top, "ay") != 1 { ok = false; }
  if !err_exp_has(&g, top, "ay", "third") { ok = false; }
  return assert(ok, "error: furthest-failure position wins the expected set");
}

fn t18() -> TestResult {
  var g = parse_grammar_new();
  let a = parse_literal(&mut g, "let", "let");
  var ok = streq(err_msg(&g, a, "x"), "parse error at line 1, column 1: expected let; found 'x'");
  if !streq(err_msg(&g, a, ""), "parse error at line 1, column 1: expected let; found end of input") { ok = false; }
  let one = parse_literal(&mut g, "a", "a");
  if !streq(err_msg(&g, one, "ab"), "parse error at line 1, column 2: expected end of input; found 'b'") { ok = false; }
  let q = parse_literal(&mut g, "q", "q");
  if !streq(err_msg(&g, q, "\u{0001}"), "parse error at line 1, column 1: expected q; found byte 0x01") { ok = false; }
  return assert(ok, "error: message text, end-of-input and non-printable found bytes");
}

fn t19() -> TestResult {
  let g = arith_grammar();
  var ok = streq(all_code(&g, AR_ROOT, "1+2*3"), "0:5:1");
  if !streq(all_text(&g, AR_ROOT, "1+2*3"), "1+2*3") { ok = false; }
  if !streq(all_code(&g, AR_ROOT, "(1+2)*3"), "0:7:1") { ok = false; }
  if !streq(all_code(&g, AR_ROOT, "007"), "0:3:1") { ok = false; }
  return assert(ok, "arith: full expression parses via the fixture grammar");
}

fn t20() -> TestResult {
  let g = arith_grammar();
  var ok = streq(run_state_code(&g, AR_TERM, "1+2*3"), "0:1:1@1");
  if !streq(all_code(&g, AR_EXPR, "1+2*3"), "0:5:1") { ok = false; }
  if !streq(all_code(&g, AR_PAREN, "(1+2)"), "0:5:1") { ok = false; }
  if !streq(run_state_code(&g, AR_ATOM, "2*3"), "0:1:1@1") { ok = false; }
  return assert(ok, "arith: node spans for term/expr/paren subparses");
}

fn t21() -> TestResult {
  let g = arith_grammar();
  var ok = err_pos(&g, AR_ROOT, "1+") == 2;
  if err_exp_count(&g, AR_ROOT, "1+") != 2 { ok = false; }
  if !err_exp_has(&g, AR_ROOT, "1+", "digit") { ok = false; }
  if !err_exp_has(&g, AR_ROOT, "1+", "'('") { ok = false; }
  return assert(ok, "arith: error after a trailing operator reveals the expected set");
}

fn t22() -> TestResult {
  let g = json_grammar();
  let src = "{\"a\":[1,true,null]}";
  var ok = streq(all_code(&g, JS_VALUE, src), "0:19:1");
  if !streq(all_text(&g, JS_VALUE, src), src) { ok = false; }
  return assert(ok, "json: object with array/true/null parses fully");
}

fn t23() -> TestResult {
  let g = json_grammar();
  var ok = streq(all_code(&g, JS_VALUE, "[[1],[2]]"), "0:9:1");
  if !streq(all_code(&g, JS_VALUE, "\"hello world\""), "0:13:1") { ok = false; }
  if !streq(all_text(&g, JS_STRING, "\"abc\""), "\"abc\"") { ok = false; }
  if !streq(all_code(&g, JS_ARRAY, "[1,2]"), "0:5:1") { ok = false; }
  return assert(ok, "json: nested arrays and string content spans");
}

fn t24() -> TestResult {
  let g = json_grammar();
  let src = "[1,]";
  var ok = err_pos(&g, JS_VALUE, src) == 3;
  if err_exp_count(&g, JS_VALUE, src) != 7 { ok = false; }
  if !err_exp_has(&g, JS_VALUE, src, "string") { ok = false; }
  if !err_exp_has(&g, JS_VALUE, src, "digit") { ok = false; }
  if !err_exp_has(&g, JS_VALUE, src, "true") { ok = false; }
  if !err_exp_has(&g, JS_VALUE, src, "false") { ok = false; }
  if !err_exp_has(&g, JS_VALUE, src, "null") { ok = false; }
  if !err_exp_has(&g, JS_VALUE, src, "'['") { ok = false; }
  if !err_exp_has(&g, JS_VALUE, src, "'{'") { ok = false; }
  return assert(ok, "json: malformed input reports the furthest failure set");
}

fn t25() -> TestResult {
  let ag = arith_grammar();
  var ok = parse_is_consistent(&ag);
  if parse_node_count(&ag) != AR_NODES { ok = false; }
  if parse_node_kind(&ag, AR_DIGIT) != PARSE_KIND_CLASS { ok = false; }
  if parse_node_pred(&ag, AR_DIGIT) != PARSE_PRED_DIGIT { ok = false; }
  if !streq(parse_node_label(&ag, AR_DIGIT), "digit") { ok = false; }
  if parse_node_kind(&ag, AR_NUMBER) != PARSE_KIND_MANY1 { ok = false; }
  if parse_node_kind(&ag, AR_LPAREN) != PARSE_KIND_LITERAL { ok = false; }
  if !streq(parse_node_literal(&ag, AR_LPAREN), "(") { ok = false; }
  if parse_node_kind(&ag, AR_PAREN) != PARSE_KIND_SEQ { ok = false; }
  if parse_node_kind(&ag, AR_ROOT) != PARSE_KIND_SEQ { ok = false; }
  if parse_node_child_a(&ag, AR_ROOT) != AR_EXPR { ok = false; }
  if parse_node_child_b(&ag, AR_ROOT) != AR_EOF { ok = false; }
  if parse_node_kind(&ag, AR_EOF) != PARSE_KIND_EOF { ok = false; }
  if parse_node_kind(&ag, -1) != PARSE_KIND_NONE { ok = false; }
  if !streq(parse_node_label(&ag, 999), "") { ok = false; }
  if parse_node_child_a(&ag, 999) != -1 { ok = false; }
  if parse_node_child_b(&ag, 999) != -1 { ok = false; }
  if parse_node_pred(&ag, 999) != PARSE_PRED_NONE { ok = false; }
  if parse_node_lo(&ag, 999) != 0 { ok = false; }
  if parse_node_hi(&ag, 999) != 0 { ok = false; }
  if !streq(parse_node_literal(&ag, 999), "") { ok = false; }
  let jg = json_grammar();
  if !parse_is_consistent(&jg) { ok = false; }
  if parse_node_count(&jg) != JS_NODES { ok = false; }
  if parse_node_kind(&jg, JS_QUOTE) != PARSE_KIND_LITERAL { ok = false; }
  if parse_node_kind(&jg, JS_STRING) != PARSE_KIND_SEQ { ok = false; }
  if parse_node_kind(&jg, JS_LBRACE) != PARSE_KIND_LITERAL { ok = false; }
  if parse_node_kind(&jg, JS_ARRAY) != PARSE_KIND_SEQ { ok = false; }
  if parse_node_kind(&jg, JS_OBJECT) != PARSE_KIND_SEQ { ok = false; }
  if parse_node_kind(&jg, JS_VALUE) != PARSE_KIND_ALT { ok = false; }
  if parse_node_child_a(&jg, JS_LBRACK) != -1 { ok = false; }
  if !streq(parse_kind_name(PARSE_KIND_CAPTURE), "capture") { ok = false; }
  if !streq(parse_kind_name(PARSE_KIND_EOF), "EOF") { ok = false; }
  if !streq(parse_kind_name(12345), "none") { ok = false; }
  if !streq(parse_pred_name(PARSE_PRED_IDENT_BYTE), "ident-byte") { ok = false; }
  if !streq(parse_pred_name(PARSE_PRED_RANGE), "range") { ok = false; }
  if !streq(parse_pred_name(12345), "none") { ok = false; }
  return assert(ok, "grammar: parallel Vec fields stay consistent; accessors bounded");
}

fn t26() -> TestResult {
  let g1 = arith_grammar();
  let g2 = arith_grammar();
  var ok = streq(all_code(&g1, AR_ROOT, "1+2*3"), all_code(&g2, AR_ROOT, "1+2*3"));
  if !streq(err_msg(&g1, AR_ROOT, "1+"), err_msg(&g2, AR_ROOT, "1+")) { ok = false; }
  if !streq(all_code(&g1, AR_ROOT, "1+2"), all_code(&g1, AR_ROOT, "1+2")) { ok = false; }
  return assert(ok, "determinism: repeated parses agree on spans and errors");
}

fn t27() -> TestResult {
  var g = parse_grammar_new();
  let x = parse_literal(&mut g, "x", "x");
  let o = parse_optional(&mut g, x);
  let m = parse_many(&mut g, o);
  var ok = streq(run_state_code(&g, m, "xx"), "0:2:1@2");
  if !streq(run_state_code(&g, m, "y"), "0:0:1@0") { ok = false; }
  return assert(ok, "many: zero-width success terminates the loop (guard)");
}

fn t28() -> TestResult {
  var g = parse_grammar_new();
  let a = parse_literal(&mut g, "a", "a");
  let s = parse_seq(&mut g, a, -1);
  var ok = err_pos(&g, s, "a") == 1;
  if !err_exp_has(&g, s, "a", "unknown-combinator") { ok = false; }
  let b = parse_literal(&mut g, "b", "b");
  parse_patch_child_b(&mut g, s, b);
  if !streq(all_code(&g, s, "ab"), "0:2:1") { ok = false; }
  parse_patch_child_a(&mut g, 999, 0);
  if !parse_is_consistent(&g) { ok = false; }
  return assert(ok, "patch: recursive grammar wiring and bounded no-op patches");
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
  io.println("=== xiom.parsing conformance tests ===");
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
  failed = failed + report(t28());
  if failed == 0 {
    io.println("xiom.parsing: all tests passed");
  } else {
    io.println("xiom.parsing: tests failed");
  }
  return failed;
}
