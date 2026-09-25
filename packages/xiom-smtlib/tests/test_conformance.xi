// XIOM -- xiom.smtlib conformance tests (24 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented subset: every supported command shape, symbols,
// keywords, numerals, decimals, strings (doubled quotes and backslash
// escapes), comments, the flat node/command accessors, the full error
// catalog, the nesting-depth limit and canonical emit round-trips.
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str
// values read from Vec[Str] elements to a pointer comparison, so every
// element check below is routed through streq instead of `==`.

module smtlib_tests
use xiom.io; use xiom.test;
use xiom.string.compare;
use xiom.smtlib;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// True when the text parses without error.
fn parse_ok(text: Str) -> Bool {
  let r = smtlib_parse(text);
  match r {
    Ok(_) => { return true; },
    Err(_) => { return false; },
  }
  return false;
}

// True when the text fails with exactly the error `want`.
fn parse_err(text: Str, want: Str) -> Bool {
  let r = smtlib_parse(text);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// Canonical emit of `text`; "<error>" when it does not parse.
fn emit_of(text: Str) -> Str {
  let r = smtlib_parse(text);
  match r {
    Ok(d) => { return smtlib_emit(&d); },
    Err(_) => { return "<error>"; },
  }
  return "<error>";
}

// True when two documents have the same kinds, texts, parents, child counts
// and command roots (source offsets may legitimately differ after emit).
fn tree_shape_eq(a: &SmtDoc, b: &SmtDoc) -> Bool {
  if smtlib_node_count(a) != smtlib_node_count(b) { return false; }
  if smtlib_command_count(a) != smtlib_command_count(b) { return false; }
  var i = 0;
  while i < smtlib_node_count(a) {
    if smtlib_kind(a, i) != smtlib_kind(b, i) { return false; }
    if !streq(smtlib_node_text(a, i), smtlib_node_text(b, i)) { return false; }
    if smtlib_parent(a, i) != smtlib_parent(b, i) { return false; }
    if smtlib_child_count(a, i) != smtlib_child_count(b, i) { return false; }
    i = i + 1;
  }
  return true;
}

// True when parse -> emit -> parse is shape-stable and emit is idempotent.
fn roundtrip_stable(text: Str) -> Bool {
  let r1 = smtlib_parse(text);
  match r1 {
    Ok(d1) => {
      let e1 = smtlib_emit(&d1);
      let r2 = smtlib_parse(e1);
      match r2 {
        Ok(d2) => {
          if !tree_shape_eq(&d1, &d2) { return false; }
          let e2 = smtlib_emit(&d2);
          return streq(e1, e2);
        },
        Err(_) => { return false; },
      }
    },
    Err(_) => { return false; },
  }
  return false;
}

// `(assert ` + `levels` nested `(x ...)` lists + `)`; `levels + 1` lists on
// the nesting path.
fn deep_text(levels: Int) -> Str {
  var s = "x";
  var i = 0;
  while i < levels {
    s = "(" + s + ")";
    i = i + 1;
  }
  return "(assert " + s + ")";
}

fn t1() -> TestResult {
  let src = "(set-logic QF_LIA)\n(set-option :produce-models true)\n(set-info :status unsat)\n(declare-const x Int)\n(declare-fun f (Int Bool) Real)\n(define-fun g ((a Int)) Int (+ a 1))\n(assert (> x 0))\n(check-sat)\n(get-model)\n(exit)";
  let r = smtlib_parse(src);
  match r {
    Ok(d) => {
      var ok = smtlib_command_count(&d) == 10;
      if !streq(smtlib_command_name(&d, 0), "set-logic") { ok = false; }
      if !streq(smtlib_command_name(&d, 1), "set-option") { ok = false; }
      if !streq(smtlib_command_name(&d, 2), "set-info") { ok = false; }
      if !streq(smtlib_command_name(&d, 3), "declare-const") { ok = false; }
      if !streq(smtlib_command_name(&d, 4), "declare-fun") { ok = false; }
      if !streq(smtlib_command_name(&d, 5), "define-fun") { ok = false; }
      if !streq(smtlib_command_name(&d, 6), "assert") { ok = false; }
      if !streq(smtlib_command_name(&d, 7), "check-sat") { ok = false; }
      if !streq(smtlib_command_name(&d, 8), "get-model") { ok = false; }
      if !streq(smtlib_command_name(&d, 9), "exit") { ok = false; }
      return assert(ok, "full script: ten commands in source order");
    },
    Err(_) => { return assert(false, "full script: ten commands in source order"); },
  }
  return assert(false, "unreachable");
}

fn t2() -> TestResult {
  let r = smtlib_parse("(declare-fun f (Int Bool) Real)");
  match r {
    Ok(d) => {
      var ok = smtlib_command_arg_count(&d, 0) == 3;
      let name = smtlib_command_arg(&d, 0, 0);
      if smtlib_kind(&d, name) != smtlib_kind_symbol() { ok = false; }
      if !streq(smtlib_symbol_text(&d, name), "f") { ok = false; }
      let params = smtlib_command_arg(&d, 0, 1);
      if smtlib_kind(&d, params) != smtlib_kind_list() { ok = false; }
      if smtlib_child_count(&d, params) != 2 { ok = false; }
      if !streq(smtlib_symbol_text(&d, smtlib_child(&d, params, 0)), "Int") { ok = false; }
      if !streq(smtlib_symbol_text(&d, smtlib_child(&d, params, 1)), "Bool") { ok = false; }
      if smtlib_kind(&d, smtlib_command_arg(&d, 0, 2)) != smtlib_kind_symbol() { ok = false; }
      if smtlib_command_arg(&d, 0, 3) != -1 { ok = false; }
      return assert(ok, "declare-fun accessors: symbol, parameter list, return sort");
    },
    Err(_) => { return assert(false, "declare-fun accessors: symbol, parameter list, return sort"); },
  }
  return assert(false, "unreachable");
}

fn t3() -> TestResult {
  let src = "; header comment\n(assert (= s \"; not a comment\"))\n  ; trailing\n(check-sat)\n";
  let r = smtlib_parse(src);
  match r {
    Ok(d) => {
      var ok = smtlib_command_count(&d) == 2;
      if !streq(smtlib_command_name(&d, 0), "assert") { ok = false; }
      if !streq(smtlib_command_name(&d, 1), "check-sat") { ok = false; }
      let term = smtlib_command_arg(&d, 0, 0);
      if !streq(smtlib_symbol_text(&d, smtlib_child(&d, term, 0)), "=") { ok = false; }
      let s_node = smtlib_child(&d, term, 2);
      if smtlib_kind(&d, s_node) != smtlib_kind_string() { ok = false; }
      if !streq(smtlib_node_text(&d, s_node), "; not a comment") { ok = false; }
      return assert(ok, "comments: `;` is skipped but literal inside a string");
    },
    Err(_) => { return assert(false, "comments: `;` is skipped but literal inside a string"); },
  }
  return assert(false, "unreachable");
}

fn t4() -> TestResult {
  var ok = streq(emit_of("  (  set-logic   QF_LIA  )  "), "(set-logic QF_LIA)");
  if !streq(emit_of("(exit)\n(check-sat)"), "(exit)\n(check-sat)") { ok = false; }
  if !streq(emit_of("(assert\n(= x\n1))"), "(assert (= x 1))") { ok = false; }
  if !streq(emit_of(""), "") { ok = false; }
  return assert(ok, "emitter: single-space normalization and one command per line");
}

fn t5() -> TestResult {
  let r = smtlib_parse("(assert (= a 0))(assert (= b 42))(assert (< c 3.14))(assert (< d 0.50))");
  match r {
    Ok(d) => {
      var ok = smtlib_command_count(&d) == 4;
      let n1 = smtlib_command_arg(&d, 0, 0);
      let v1 = smtlib_child(&d, n1, 2);
      if smtlib_kind(&d, v1) != smtlib_kind_numeral() { ok = false; }
      if !streq(smtlib_node_text(&d, v1), "0") { ok = false; }
      let n2 = smtlib_command_arg(&d, 1, 0);
      let v2 = smtlib_child(&d, n2, 2);
      if smtlib_kind(&d, v2) != smtlib_kind_numeral() { ok = false; }
      if !streq(smtlib_node_text(&d, v2), "42") { ok = false; }
      let n3 = smtlib_command_arg(&d, 2, 0);
      let v3 = smtlib_child(&d, n3, 2);
      if smtlib_kind(&d, v3) != smtlib_kind_decimal() { ok = false; }
      if !streq(smtlib_node_text(&d, v3), "3.14") { ok = false; }
      let n4 = smtlib_command_arg(&d, 3, 0);
      let v4 = smtlib_child(&d, n4, 2);
      if smtlib_kind(&d, v4) != smtlib_kind_decimal() { ok = false; }
      if !streq(smtlib_node_text(&d, v4), "0.50") { ok = false; }
      if !streq(emit_of("(assert (< d 0.50))"), "(assert (< d 0.50))") { ok = false; }
      return assert(ok, "numerals and decimals: validated text tokens kept verbatim");
    },
    Err(_) => { return assert(false, "numerals and decimals: validated text tokens kept verbatim"); },
  }
  return assert(false, "unreachable");
}

fn t6() -> TestResult {
  let src = "(set-info :source \"he said \"\"hi\"\"\")";
  let r = smtlib_parse(src);
  match r {
    Ok(d) => {
      let arg = smtlib_command_arg(&d, 0, 1);
      var ok = smtlib_kind(&d, arg) == smtlib_kind_string();
      if !streq(smtlib_node_text(&d, arg), "he said \"hi\"") { ok = false; }
      if !streq(emit_of(src), src) { ok = false; }
      return assert(ok, "strings: doubled quote decodes and re-emits canonically");
    },
    Err(_) => { return assert(false, "strings: doubled quote decodes and re-emits canonically"); },
  }
  return assert(false, "unreachable");
}

fn t7() -> TestResult {
  let src = "(set-info :note \"l1\\nl2\\tl3\\\\l4\\\"l5\\r\")";
  let r = smtlib_parse(src);
  match r {
    Ok(d) => {
      let arg = smtlib_command_arg(&d, 0, 1);
      var ok = smtlib_kind(&d, arg) == smtlib_kind_string();
      let want = "l1\nl2\tl3\\l4\"l5\r";
      if !streq(smtlib_node_text(&d, arg), want) { ok = false; }
      return assert(ok, "strings: backslash escapes decode (\\n \\t \\\\ \\\" \\r)");
    },
    Err(_) => { return assert(false, "strings: backslash escapes decode (\\n \\t \\\\ \\\" \\r)"); },
  }
  return assert(false, "unreachable");
}

fn t8() -> TestResult {
  let src = "(set-info :note \"say \"\"hi\"\" and \\n and \\\\\")";
  var ok = streq(emit_of(src), src);
  if !streq(emit_of("(set-info :note \"a;b\")"), "(set-info :note \"a;b\")") { ok = false; }
  return assert(ok, "emitter: strings are re-escaped and canonical output is a fixed point");
}

fn t9() -> TestResult {
  let r = smtlib_parse("(set-option :produce-models true)(set-info :smt-lib-version 2.6)");
  match r {
    Ok(d) => {
      let k = smtlib_command_arg(&d, 0, 0);
      var ok = smtlib_kind(&d, k) == smtlib_kind_keyword();
      if !streq(smtlib_node_text(&d, k), ":produce-models") { ok = false; }
      let v = smtlib_command_arg(&d, 0, 1);
      if smtlib_kind(&d, v) != smtlib_kind_symbol() { ok = false; }
      let k2 = smtlib_command_arg(&d, 1, 0);
      if !streq(smtlib_node_text(&d, k2), ":smt-lib-version") { ok = false; }
      let v2 = smtlib_command_arg(&d, 1, 1);
      if smtlib_kind(&d, v2) != smtlib_kind_decimal() { ok = false; }
      return assert(ok, "keywords: `:name` keeps the colon and takes atom values");
    },
    Err(_) => { return assert(false, "keywords: `:name` keeps the colon and takes atom values"); },
  }
  return assert(false, "unreachable");
}

fn t10() -> TestResult {
  let src = "(declare-const a (Array Int Int))(declare-fun f ((_ BitVec 32)) (_ BitVec 32))(declare-fun g () Bool)";
  let r = smtlib_parse(src);
  match r {
    Ok(d) => {
      var ok = smtlib_command_count(&d) == 3;
      let s1 = smtlib_command_arg(&d, 0, 1);
      if smtlib_kind(&d, s1) != smtlib_kind_list() { ok = false; }
      if smtlib_child_count(&d, s1) != 3 { ok = false; }
      if !streq(smtlib_symbol_text(&d, smtlib_child(&d, s1, 0)), "Array") { ok = false; }
      let params = smtlib_command_arg(&d, 1, 1);
      if smtlib_child_count(&d, params) != 1 { ok = false; }
      let psort = smtlib_child(&d, params, 0);
      if smtlib_kind(&d, psort) != smtlib_kind_list() { ok = false; }
      if smtlib_child_count(&d, psort) != 3 { ok = false; }
      if !streq(smtlib_symbol_text(&d, smtlib_child(&d, psort, 0)), "_") { ok = false; }
      let ret = smtlib_command_arg(&d, 1, 2);
      if smtlib_kind(&d, ret) != smtlib_kind_list() { ok = false; }
      if !streq(smtlib_symbol_text(&d, smtlib_child(&d, ret, 1)), "BitVec") { ok = false; }
      let empty_params = smtlib_command_arg(&d, 2, 1);
      if smtlib_child_count(&d, empty_params) != 0 { ok = false; }
      return assert(ok, "sorts: symbols, nested sort lists and empty parameter lists");
    },
    Err(_) => { return assert(false, "sorts: symbols, nested sort lists and empty parameter lists"); },
  }
  return assert(false, "unreachable");
}

fn t11() -> TestResult {
  let src = "(define-fun f ((x Int) (y Int)) Int (+ x y))";
  let r = smtlib_parse(src);
  match r {
    Ok(d) => {
      var ok = smtlib_command_arg_count(&d, 0) == 4;
      let params = smtlib_command_arg(&d, 0, 1);
      if smtlib_child_count(&d, params) != 2 { ok = false; }
      let p0 = smtlib_child(&d, params, 0);
      if smtlib_child_count(&d, p0) != 2 { ok = false; }
      if !streq(smtlib_symbol_text(&d, smtlib_child(&d, p0, 0)), "x") { ok = false; }
      if !streq(smtlib_symbol_text(&d, smtlib_child(&d, p0, 1)), "Int") { ok = false; }
      let body = smtlib_command_arg(&d, 0, 3);
      if smtlib_kind(&d, body) != smtlib_kind_list() { ok = false; }
      if !streq(smtlib_symbol_text(&d, smtlib_child(&d, body, 0)), "+") { ok = false; }
      if !streq(emit_of(src), src) { ok = false; }
      return assert(ok, "define-fun: named parameters, return sort and pass-through body");
    },
    Err(_) => { return assert(false, "define-fun: named parameters, return sort and pass-through body"); },
  }
  return assert(false, "unreachable");
}

fn t12() -> TestResult {
  let src = "(assert (! (> x 0) :named pos))";
  var ok = parse_ok(src);
  if !streq(emit_of(src), src) { ok = false; }
  if !streq(emit_of("(assert (! (> x 0)   :named   pos))"), src) { ok = false; }
  return assert(ok, "assert: `!` attribute terms are pass-through and normalized");
}

fn t13() -> TestResult {
  var ok = streq(emit_of(""), "");
  if !streq(emit_of("   \n\t "), "") { ok = false; }
  if !streq(emit_of("; only a comment"), "") { ok = false; }
  let r = smtlib_parse("");
  match r {
    Ok(d) => {
      if smtlib_command_count(&d) != 0 { ok = false; }
      if smtlib_node_count(&d) != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "empty input: zero nodes and zero commands, emit is empty");
}

fn t14() -> TestResult {
  let src = "; benchmark\n(set-logic QF_UF)\n(set-option :produce-models true)\n(declare-const p Bool)\n(declare-fun not  (Bool) Bool)\n(define-fun id ((q Bool)) Bool q)\n(assert (! (and p (not p)) :named c1))\n(assert (= (id p) p))\n(check-sat)\n(get-model)\n(exit)";
  return assert(roundtrip_stable(src), "round trip: parse, emit, parse is shape-stable and idempotent");
}

fn t15() -> TestResult {
  var ok = parse_err("(assert (= x 1)))", "smtlib: unbalanced parenthesis at 16");
  if !parse_err("(assert (= x 1)", "smtlib: unbalanced parenthesis at 0") { ok = false; }
  if !parse_err("(exit))", "smtlib: unbalanced parenthesis at 6") { ok = false; }
  if !parse_err("(assert (and x", "smtlib: unbalanced parenthesis at 8") { ok = false; }
  return assert(ok, "unbalanced parens: reported at the extra `)` or the unclosed `(`");
}

fn t16() -> TestResult {
  var ok = parse_err("(set-info :note \"abc)", "smtlib: unterminated string at 16");
  if !parse_err("(set-info :note \"a\\qb\")", "smtlib: invalid escape at 18") { ok = false; }
  if !parse_err("(set-info :note \"a\\", "smtlib: unterminated string at 16") { ok = false; }
  return assert(ok, "string errors: unterminated quote, invalid escape, trailing backslash");
}

fn t17() -> TestResult {
  var ok = parse_err("(assert (= x 007))", "smtlib: malformed numeric token at 13");
  if !parse_err("(assert (< x 1.))", "smtlib: malformed numeric token at 13") { ok = false; }
  if !parse_err("(assert (= x 1a))", "smtlib: malformed numeric token at 13") { ok = false; }
  if !parse_err("(assert (= x 1.2.3))", "smtlib: malformed numeric token at 13") { ok = false; }
  if !parse_ok("(assert (= x 0.5))") { ok = false; }
  if !parse_ok("(assert (= x 10))") { ok = false; }
  return assert(ok, "numeric errors: leading zeros, dangling dot, trailing symbol chars");
}

fn t18() -> TestResult {
  var ok = parse_err("()", "smtlib: empty command at 0");
  if !parse_err("foo", "smtlib: expected command at 0") { ok = false; }
  if !parse_err("(foobar)", "smtlib: unknown command 'foobar' at 1") { ok = false; }
  if !parse_err("(1 2)", "smtlib: misplaced token at 1") { ok = false; }
  if !parse_err("(assert 1) (basil)", "smtlib: unknown command 'basil' at 12") { ok = false; }
  return assert(ok, "command errors: empty, expected, unknown and misplaced tokens");
}

fn t19() -> TestResult {
  var ok = parse_err("(set-logic)", "smtlib: set-logic expects 1 argument, got 0");
  if !parse_err("(set-logic QF_LIA QF_UF)", "smtlib: set-logic expects 1 argument, got 2") { ok = false; }
  if !parse_err("(check-sat now)", "smtlib: check-sat expects 0 arguments, got 1") { ok = false; }
  if !parse_err("(get-model extra)", "smtlib: get-model expects 0 arguments, got 1") { ok = false; }
  if !parse_err("(declare-fun f ())", "smtlib: declare-fun expects 3 arguments, got 2") { ok = false; }
  if !parse_err("(declare-fun f () Int Bool)", "smtlib: declare-fun expects 3 arguments, got 4") { ok = false; }
  if !parse_err("(assert)", "smtlib: assert expects 1 argument, got 0") { ok = false; }
  return assert(ok, "arity errors: missing arguments, extra arguments, missing return sort");
}

fn t20() -> TestResult {
  var ok = parse_err("(set-logic :foo)", "smtlib: set-logic expects a symbol at 11");
  if !parse_err("(set-option produce-models true)", "smtlib: set-option expects a keyword at 12") { ok = false; }
  if !parse_err("(set-option :k (a))", "smtlib: set-option expects an atom at 15") { ok = false; }
  if !parse_err("(assert :foo)", "smtlib: assert expects a term at 8") { ok = false; }
  if !parse_err("(assert ())", "smtlib: assert expects a term at 8") { ok = false; }
  if !parse_err("(declare-const 5 Int)", "smtlib: declare-const expects a symbol at 15") { ok = false; }
  if !parse_err("(declare-const x 3)", "smtlib: declare-const expects a sort at 17") { ok = false; }
  if !parse_err("(declare-fun f Int Int)", "smtlib: declare-fun expects a parameter list at 15") { ok = false; }
  if !parse_err("(declare-fun f (Int 5) Int)", "smtlib: declare-fun expects a sort at 20") { ok = false; }
  if !parse_err("(declare-fun f () 5)", "smtlib: declare-fun expects a sort at 18") { ok = false; }
  return assert(ok, "argument kinds: symbols, keywords, atoms, sorts and parameter lists");
}

fn t21() -> TestResult {
  var ok = parse_err("(define-fun f x Int x)", "smtlib: define-fun expects a parameter list at 14");
  if !parse_err("(define-fun f (x Int) Int x)", "smtlib: define-fun expects a sorted variable at 15") { ok = false; }
  if !parse_err("(define-fun f ((x)) Int x)", "smtlib: define-fun expects a sorted variable at 15") { ok = false; }
  if !parse_err("(define-fun f ((5 Int)) Int x)", "smtlib: define-fun expects a symbol at 16") { ok = false; }
  if !parse_err("(define-fun f ((x 5)) Int x)", "smtlib: define-fun expects a sort at 18") { ok = false; }
  if !parse_err("(define-fun f ((x Int)) Int :k)", "smtlib: define-fun expects a term at 28") { ok = false; }
  if !parse_err("(define-fun f ((x Int)) 5 x)", "smtlib: define-fun expects a sort at 24") { ok = false; }
  return assert(ok, "define-fun shapes: parameter list, sorted variables, return sort and term");
}

fn t22() -> TestResult {
  let r = smtlib_parse("(check-sat)");
  match r {
    Ok(d) => {
      var ok = smtlib_node_count(&d) == 2;
      if smtlib_kind(&d, -1) != -1 { ok = false; }
      if smtlib_kind(&d, 2) != -1 { ok = false; }
      if !streq(smtlib_node_text(&d, -1), "") { ok = false; }
      if !streq(smtlib_symbol_text(&d, -1), "") { ok = false; }
      if smtlib_parent(&d, -1) != -1 { ok = false; }
      if smtlib_parent(&d, 0) != -1 { ok = false; }
      if smtlib_child_count(&d, -1) != 0 { ok = false; }
      if smtlib_child(&d, -1, 0) != -1 { ok = false; }
      if smtlib_child(&d, 0, -1) != -1 { ok = false; }
      if smtlib_child(&d, 0, 99) != -1 { ok = false; }
      if smtlib_node_start(&d, -1) != -1 { ok = false; }
      if smtlib_node_end(&d, 9) != -1 { ok = false; }
      if smtlib_command_node(&d, -1) != -1 { ok = false; }
      if smtlib_command_node(&d, 1) != -1 { ok = false; }
      if !streq(smtlib_command_name(&d, 5), "") { ok = false; }
      if smtlib_command_arg_count(&d, -1) != 0 { ok = false; }
      if smtlib_command_arg(&d, -1, 0) != -1 { ok = false; }
      if smtlib_command_arg(&d, 0, -1) != -1 { ok = false; }
      if smtlib_command_arg(&d, 0, 0) != -1 { ok = false; }
      return assert(ok, "accessors: out-of-range indices return -1, \"\" or 0");
    },
    Err(_) => { return assert(false, "accessors: out-of-range indices return -1, \"\" or 0"); },
  }
  return assert(false, "unreachable");
}

fn t23() -> TestResult {
  var ok = parse_ok(deep_text(127));
  if !parse_err(deep_text(128), "smtlib: nesting depth exceeds limit of 128") { ok = false; }
  return assert(ok, "nesting depth: 128 lists accepted, 129 rejected");
}

fn t24() -> TestResult {
  let src = "(assert (= x 1))";
  let r = smtlib_parse(src);
  match r {
    Ok(d) => {
      var ok = smtlib_node_count(&d) == 6;
      if smtlib_command_node(&d, 0) != 0 { ok = false; }
      if smtlib_node_start(&d, 0) != 0 { ok = false; }
      if smtlib_node_end(&d, 0) != 16 { ok = false; }
      if smtlib_node_start(&d, 1) != 1 { ok = false; }
      if smtlib_node_end(&d, 1) != 7 { ok = false; }
      if smtlib_node_start(&d, 2) != 8 { ok = false; }
      if smtlib_node_end(&d, 2) != 15 { ok = false; }
      if smtlib_node_start(&d, 5) != 13 { ok = false; }
      if smtlib_child_count(&d, 2) != 3 { ok = false; }
      if smtlib_child(&d, 2, 1) != 4 { ok = false; }
      let r2 = smtlib_parse(src);
      match r2 {
        Ok(d2) => {
          if !streq(smtlib_emit(&d), smtlib_emit(&d2)) { ok = false; }
          if !tree_shape_eq(&d, &d2) { ok = false; }
        },
        Err(_) => { ok = false; },
      }
      return assert(ok, "positions and determinism: byte ranges, child order, repeated parses");
    },
    Err(_) => { return assert(false, "positions and determinism: byte ranges, child order, repeated parses"); },
  }
  return assert(false, "unreachable");
}

fn main() -> Int {
  io.println("=== xiom.smtlib conformance tests ===");
  var failed: Int = 0;
  let r1 = t1();
  if r1.passed { io.println("  [PASS] " + r1.name); } else { io.println("  [FAIL] " + r1.name); failed = failed + 1; }
  let r2 = t2();
  if r2.passed { io.println("  [PASS] " + r2.name); } else { io.println("  [FAIL] " + r2.name); failed = failed + 1; }
  let r3 = t3();
  if r3.passed { io.println("  [PASS] " + r3.name); } else { io.println("  [FAIL] " + r3.name); failed = failed + 1; }
  let r4 = t4();
  if r4.passed { io.println("  [PASS] " + r4.name); } else { io.println("  [FAIL] " + r4.name); failed = failed + 1; }
  let r5 = t5();
  if r5.passed { io.println("  [PASS] " + r5.name); } else { io.println("  [FAIL] " + r5.name); failed = failed + 1; }
  let r6 = t6();
  if r6.passed { io.println("  [PASS] " + r6.name); } else { io.println("  [FAIL] " + r6.name); failed = failed + 1; }
  let r7 = t7();
  if r7.passed { io.println("  [PASS] " + r7.name); } else { io.println("  [FAIL] " + r7.name); failed = failed + 1; }
  let r8 = t8();
  if r8.passed { io.println("  [PASS] " + r8.name); } else { io.println("  [FAIL] " + r8.name); failed = failed + 1; }
  let r9 = t9();
  if r9.passed { io.println("  [PASS] " + r9.name); } else { io.println("  [FAIL] " + r9.name); failed = failed + 1; }
  let r10 = t10();
  if r10.passed { io.println("  [PASS] " + r10.name); } else { io.println("  [FAIL] " + r10.name); failed = failed + 1; }
  let r11 = t11();
  if r11.passed { io.println("  [PASS] " + r11.name); } else { io.println("  [FAIL] " + r11.name); failed = failed + 1; }
  let r12 = t12();
  if r12.passed { io.println("  [PASS] " + r12.name); } else { io.println("  [FAIL] " + r12.name); failed = failed + 1; }
  let r13 = t13();
  if r13.passed { io.println("  [PASS] " + r13.name); } else { io.println("  [FAIL] " + r13.name); failed = failed + 1; }
  let r14 = t14();
  if r14.passed { io.println("  [PASS] " + r14.name); } else { io.println("  [FAIL] " + r14.name); failed = failed + 1; }
  let r15 = t15();
  if r15.passed { io.println("  [PASS] " + r15.name); } else { io.println("  [FAIL] " + r15.name); failed = failed + 1; }
  let r16 = t16();
  if r16.passed { io.println("  [PASS] " + r16.name); } else { io.println("  [FAIL] " + r16.name); failed = failed + 1; }
  let r17 = t17();
  if r17.passed { io.println("  [PASS] " + r17.name); } else { io.println("  [FAIL] " + r17.name); failed = failed + 1; }
  let r18 = t18();
  if r18.passed { io.println("  [PASS] " + r18.name); } else { io.println("  [FAIL] " + r18.name); failed = failed + 1; }
  let r19 = t19();
  if r19.passed { io.println("  [PASS] " + r19.name); } else { io.println("  [FAIL] " + r19.name); failed = failed + 1; }
  let r20 = t20();
  if r20.passed { io.println("  [PASS] " + r20.name); } else { io.println("  [FAIL] " + r20.name); failed = failed + 1; }
  let r21 = t21();
  if r21.passed { io.println("  [PASS] " + r21.name); } else { io.println("  [FAIL] " + r21.name); failed = failed + 1; }
  let r22 = t22();
  if r22.passed { io.println("  [PASS] " + r22.name); } else { io.println("  [FAIL] " + r22.name); failed = failed + 1; }
  let r23 = t23();
  if r23.passed { io.println("  [PASS] " + r23.name); } else { io.println("  [FAIL] " + r23.name); failed = failed + 1; }
  let r24 = t24();
  if r24.passed { io.println("  [PASS] " + r24.name); } else { io.println("  [FAIL] " + r24.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.smtlib: all tests passed");
  } else {
    io.println("xiom.smtlib: tests failed");
  }
  return failed;
}
