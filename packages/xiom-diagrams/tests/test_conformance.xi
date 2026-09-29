// XIOM -- xiom.diagrams conformance tests (34 checks)
// Port task: prove the pure-XIOM Graphviz DOT-subset codec against its
// documented grammar, canonical form and error catalog.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Coverage: quote/backslash/control escaping and the unescape inverse, the
// full error catalog with exact "CODE@line:col" positions, node/edge/attr
// statements, chains, comments, optional semicolons, empty attribute lists,
// canonical quoted-string normalization, byte-deterministic serialization,
// parse->serialize->parse idempotence, accessors, the parallel-vector guard
// and dot_attr_get (found, missing, malformed).
//
// All Str equality goes through str_compare (BUG 17: `==` on Str values read
// from Vec[Str] elements lowers to a pointer comparison). Tests are called
// directly from main -- no table-driven dispatch.

module diagrams_tests
use xiom.io; use xiom.test;
use xiom.string; use xiom.string.compare;
use xiom.diagrams;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn graph_err_is(r: Result[DotGraph, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn str_err_is(r: Result[Str, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn str_res_is(r: Result[Str, Str], want: Str) -> Bool {
  match r {
    Ok(v) => { return streq(v, want); },
    Err(_) => { return false; },
  }
  return false;
}

// --------------------------------------------------
//  Escaping
// --------------------------------------------------

fn t01() -> TestResult {
  let got = dot_escape("a\"b\\c\nd\te\rf");
  return assert(streq(got, "a\\\"b\\\\c\\nd\\te\\rf"), "dot_escape escapes quote, backslash, LF, TAB and CR");
}

fn t02() -> TestResult {
  var ok = streq(dot_escape("plain café ✓ # not a comment"), "plain café ✓ # not a comment");
  if !streq(dot_escape(""), "") { ok = false; }
  if !streq(dot_escape("A-Z_9"), "A-Z_9") { ok = false; }
  return assert(ok, "dot_escape passes every other byte through, including UTF-8");
}

fn t03() -> TestResult {
  var ok = str_res_is(dot_unescape("a\\\"b\\\\c\\nd\\te\\rf"), "a\"b\\c\nd\te\rf");
  if !str_res_is(dot_unescape(""), "") { ok = false; }
  return assert(ok, "dot_unescape inverts dot_escape and accepts the empty string");
}

fn t04() -> TestResult {
  var ok = str_err_is(dot_unescape("a\\xb"), "E_BAD_ESCAPE@1:2");
  if !str_err_is(dot_unescape("tail\\"), "E_BAD_ESCAPE@1:5") { ok = false; }
  if !str_err_is(dot_unescape("line1\nline2\\q"), "E_BAD_ESCAPE@2:6") { ok = false; }
  return assert(ok, "dot_unescape reports the offending backslash position");
}

fn t05() -> TestResult {
  let src = "quote \" backslash \\ tab \t cr \r lf \n ctl \u{0001}\u{001F}";
  let escaped = dot_escape(src);
  var ok = streq(escaped, "quote \\\" backslash \\\\ tab \\t cr \\r lf \\n ctl \u{0001}\u{001F}");
  if !str_res_is(dot_unescape(escaped), src) { ok = false; }
  return assert(ok, "escape/unescape round-trip preserves text and control bytes");
}

// --------------------------------------------------
//  Parsing
// --------------------------------------------------

fn t06() -> TestResult {
  let r = dot_parse("digraph G { a -> b; }");
  var ok = false;
  match r {
    Ok(g) => {
      ok = dot_is_directed(&g);
      if !streq(dot_name(&g), "G") { ok = false; }
      if dot_stmt_count(&g) != 1 { ok = false; }
      if dot_stmt_kind(&g, 0) != 1 { ok = false; }
      if !streq(dot_stmt_id(&g, 0), "a") { ok = false; }
      if !streq(dot_stmt_target(&g, 0), "b") { ok = false; }
      if !streq(dot_stmt_attrs(&g, 0), "") { ok = false; }
      if !dot_is_consistent(&g) { ok = false; }
      if dot_node_count(&g) != 0 { ok = false; }
      if dot_edge_count(&g) != 1 { ok = false; }
      if dot_attr_count(&g) != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "parse digraph with one edge");
}

fn t07() -> TestResult {
  let r = dot_parse("graph { a -- b b -- c }");
  var ok = false;
  match r {
    Ok(g) => {
      ok = !dot_is_directed(&g);
      if !streq(dot_name(&g), "") { ok = false; }
      if dot_stmt_count(&g) != 2 { ok = false; }
      if dot_stmt_kind(&g, 0) != 1 { ok = false; }
      if !streq(dot_stmt_id(&g, 0), "a") { ok = false; }
      if !streq(dot_stmt_target(&g, 0), "b") { ok = false; }
      if !streq(dot_stmt_id(&g, 1), "b") { ok = false; }
      if !streq(dot_stmt_target(&g, 1), "c") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "parse anonymous undirected graph without semicolons");
}

fn t08() -> TestResult {
  let r = dot_parse("digraph { a [label=\"Start Node\", shape=box]; }");
  var ok = false;
  match r {
    Ok(g) => {
      ok = dot_stmt_count(&g) == 1;
      if dot_stmt_kind(&g, 0) != 0 { ok = false; }
      if !streq(dot_stmt_id(&g, 0), "a") { ok = false; }
      if !streq(dot_stmt_attrs(&g, 0), "label=\"Start Node\", shape=box") { ok = false; }
      if !streq(dot_stmt_target(&g, 0), "") { ok = false; }
      if dot_node_count(&g) != 1 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "parse node statement with attribute list");
}

fn t09() -> TestResult {
  let r = dot_parse("digraph { a [label=\"say \\\"hi\\\"\\nbye\", color=red]; }");
  var ok = false;
  match r {
    Ok(g) => {
      let body: Str = dot_stmt_attrs(&g, 0);
      ok = streq(body, "label=\"say \\\"hi\\\"\\nbye\", color=red");
      if !str_res_is(dot_attr_get(body, "label"), "say \"hi\"\nbye") { ok = false; }
      if !str_res_is(dot_attr_get(body, "color"), "red") { ok = false; }
      if !str_err_is(dot_attr_get(body, "missing"), "E_ATTR_NOT_FOUND") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "attribute values are canonicalized, escaped and readable back");
}

fn t10() -> TestResult {
  let r = dot_parse("digraph { rankdir=LR; }");
  var ok = false;
  match r {
    Ok(g) => {
      ok = dot_stmt_kind(&g, 0) == 2;
      if !streq(dot_stmt_id(&g, 0), "rankdir") { ok = false; }
      if !streq(dot_stmt_target(&g, 0), "LR") { ok = false; }
      if !streq(dot_stmt_attrs(&g, 0), "") { ok = false; }
      if dot_attr_count(&g) != 1 { ok = false; }
      if dot_node_count(&g) != 0 { ok = false; }
      if dot_edge_count(&g) != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "parse attribute statement key=value");
}

fn t11() -> TestResult {
  let r = dot_parse("# top\n// note\ndigraph G { # inner\na -> b // tail\n}\n# end\n");
  var ok = false;
  match r {
    Ok(g) => {
      ok = dot_is_directed(&g);
      if !streq(dot_name(&g), "G") { ok = false; }
      if dot_stmt_count(&g) != 1 { ok = false; }
      if !streq(dot_stmt_id(&g, 0), "a") { ok = false; }
      if !streq(dot_stmt_target(&g, 0), "b") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "# and // comments are skipped everywhere outside strings");
}

fn t12() -> TestResult {
  let r = dot_parse("graph { ;; solo; a -- b ;; x []; }");
  var ok = false;
  match r {
    Ok(g) => {
      ok = dot_stmt_count(&g) == 3;
      if dot_stmt_kind(&g, 0) != 0 { ok = false; }
      if !streq(dot_stmt_id(&g, 0), "solo") { ok = false; }
      if !streq(dot_stmt_attrs(&g, 0), "") { ok = false; }
      if dot_stmt_kind(&g, 1) != 1 { ok = false; }
      if !streq(dot_stmt_id(&g, 1), "a") { ok = false; }
      if !streq(dot_stmt_target(&g, 1), "b") { ok = false; }
      if dot_stmt_kind(&g, 2) != 0 { ok = false; }
      if !streq(dot_stmt_id(&g, 2), "x") { ok = false; }
      if !streq(dot_stmt_attrs(&g, 2), "") { ok = false; }
      if !streq(dot_serialize(&g), "graph {\n  solo;\n  a -- b;\n  x;\n}") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "empty statements and empty attribute lists parse; [] canonicalizes away");
}

fn t13() -> TestResult {
  let r = dot_parse("digraph { a -> b -> c [color=red]; }");
  var ok = false;
  match r {
    Ok(g) => {
      ok = dot_edge_count(&g) == 2;
      if !streq(dot_stmt_id(&g, 0), "a") { ok = false; }
      if !streq(dot_stmt_target(&g, 0), "b") { ok = false; }
      if !streq(dot_stmt_attrs(&g, 0), "color=red") { ok = false; }
      if !streq(dot_stmt_id(&g, 1), "b") { ok = false; }
      if !streq(dot_stmt_target(&g, 1), "c") { ok = false; }
      if !streq(dot_stmt_attrs(&g, 1), "color=red") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "an edge chain normalizes to pairwise edges with replicated attributes");
}

fn t34() -> TestResult {
  let r = dot_parse("digraph { \"node one\" -> n2; }");
  var ok = false;
  match r {
    Ok(g) => {
      ok = streq(dot_stmt_id(&g, 0), "\"node one\"");
      if !streq(dot_stmt_target(&g, 0), "n2") { ok = false; }
      if !streq(dot_serialize(&g), "digraph {\n  \"node one\" -> n2;\n}") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "quoted identifiers are stored and serialized in canonical form");
}

// --------------------------------------------------
//  Serialization
// --------------------------------------------------

fn t14() -> TestResult {
  var g = dot_new(true, "G");
  dot_add_node(&mut g, "a", dot_attr_pair("label", "Start Node") + ", " + dot_attr_pair("shape", "box"));
  dot_add_edge(&mut g, "a", "b", "");
  let got = dot_serialize(&g);
  return assert(streq(got, "digraph G {\n  a [label=\"Start Node\", shape=box];\n  a -> b;\n}"), "serialize programmatic graph with fixed layout");
}

fn t15() -> TestResult {
  var g = dot_new(false, "my g");
  dot_add_node(&mut g, "a b", "");
  dot_add_attr(&mut g, "rankdir", "LR");
  let got = dot_serialize(&g);
  return assert(streq(got, "graph \"my g\" {\n  \"a b\";\n  rankdir=LR;\n}"), "serialize undirected graph with quoted name, node and attr statement");
}

fn t16() -> TestResult {
  let d = dot_new(true, "");
  var ok = streq(dot_serialize(&d), "digraph {\n}");
  let u = dot_new(false, "");
  if !streq(dot_serialize(&u), "graph {\n}") { ok = false; }
  return assert(ok, "serialize an empty graph as header + closing brace");
}

fn t17() -> TestResult {
  let src = "digraph \"my g\" {\n  \"a\" -> b [label=\"x y\",color=\"#fff\"];\n}";
  let r = dot_parse(src);
  var ok = false;
  match r {
    Ok(g) => {
      ok = streq(dot_serialize(&g), "digraph \"my g\" {\n  a -> b [label=\"x y\", color=\"#fff\"];\n}");
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "serialization normalizes separators and needless quotes");
}

fn t18() -> TestResult {
  let src = "digraph G {\n  \"a b\" [label=\"x\\ny\"];\n  \"a b\" -> \"c d\" [weight=2];\n  rankdir=LR;\n  solo;\n}";
  let r1 = dot_parse(src);
  var ok = false;
  match r1 {
    Ok(g1) => {
      let s1 = dot_serialize(&g1);
      ok = streq(s1, "digraph G {\n  \"a b\" [label=\"x\\ny\"];\n  \"a b\" -> \"c d\" [weight=2];\n  rankdir=LR;\n  solo;\n}");
      let r2 = dot_parse(s1);
      match r2 {
        Ok(g2) => {
          if !streq(dot_serialize(&g2), s1) { ok = false; }
          if dot_stmt_count(&g2) != 4 { ok = false; }
        },
        Err(_) => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "parse -> serialize -> parse is idempotent and canonical");
}

// --------------------------------------------------
//  Error catalog
// --------------------------------------------------

fn t19() -> TestResult {
  let r = dot_parse("digraph G {\n  a [label=\"open];\n}");
  return assert(graph_err_is(r, "E_UNTERMINATED_STRING@2:12"), "unterminated string reports the opening quote");
}

fn t20() -> TestResult {
  var ok = graph_err_is(dot_parse("flowchart G {}"), "E_EXPECTED_GRAPH_KEYWORD@1:1");
  if !graph_err_is(dot_parse("graphx {}"), "E_EXPECTED_GRAPH_KEYWORD@1:1") { ok = false; }
  if !graph_err_is(dot_parse("digraph"), "E_EXPECTED_LBRACE@1:8") { ok = false; }
  return assert(ok, "a missing or wrong graph keyword is E_EXPECTED_GRAPH_KEYWORD");
}

fn t21() -> TestResult {
  return assert(graph_err_is(dot_parse("digraph G a -> b"), "E_EXPECTED_LBRACE@1:11"), "missing opening brace is E_EXPECTED_LBRACE");
}

fn t22() -> TestResult {
  var ok = graph_err_is(dot_parse("digraph { a -> b"), "E_EXPECTED_RBRACE@1:17");
  if !graph_err_is(dot_parse("digraph {\n  a -> b;\n"), "E_EXPECTED_RBRACE@3:1") { ok = false; }
  return assert(ok, "EOF inside the body is E_EXPECTED_RBRACE at the end position");
}

fn t23() -> TestResult {
  var ok = graph_err_is(dot_parse("graph { a -> b }"), "E_EDGE_OP_MISMATCH@1:11");
  if !graph_err_is(dot_parse("digraph { a -- b }"), "E_EDGE_OP_MISMATCH@1:13") { ok = false; }
  if !graph_err_is(dot_parse("digraph { a -> b -- c }"), "E_EDGE_OP_MISMATCH@1:18") { ok = false; }
  return assert(ok, "a `->` in a graph or `--` in a digraph is E_EDGE_OP_MISMATCH");
}

fn t24() -> TestResult {
  return assert(graph_err_is(dot_parse("digraph { a [label=\"x\\q\"]; }"), "E_BAD_ESCAPE@1:22"), "an unknown escape in a quoted string is E_BAD_ESCAPE");
}

fn t25() -> TestResult {
  var ok = graph_err_is(dot_parse("digraph { a [label \"x\"]; }"), "E_EXPECTED_EQUALS@1:20");
  if !graph_err_is(dot_parse("digraph { a [x=1 y=2]; }"), "E_EXPECTED_ATTR_SEP@1:18") { ok = false; }
  if !graph_err_is(dot_parse("digraph { a [x=]; }"), "E_EXPECTED_ATTR_VALUE@1:16") { ok = false; }
  if !graph_err_is(dot_parse("digraph { a [=1]; }"), "E_EXPECTED_ATTR_KEY@1:14") { ok = false; }
  return assert(ok, "malformed attribute lists report equals, separator, value and key errors");
}

fn t26() -> TestResult {
  return assert(graph_err_is(dot_parse("digraph { a -> b; } extra"), "E_TRAILING_INPUT@1:21"), "input after the closing brace is E_TRAILING_INPUT");
}

fn t27() -> TestResult {
  var ok = graph_err_is(dot_parse(""), "E_EMPTY_INPUT@1:1");
  if !graph_err_is(dot_parse("  \n// c\n"), "E_EMPTY_INPUT@3:1") { ok = false; }
  return assert(ok, "empty and comment-only input is E_EMPTY_INPUT at the end position");
}

fn t28() -> TestResult {
  var ok = graph_err_is(dot_parse("digraph { @ }"), "E_UNEXPECTED_CHAR@1:11");
  if !graph_err_is(dot_parse("digraph { a -> - }"), "E_UNEXPECTED_CHAR@1:16") { ok = false; }
  return assert(ok, "@ and a lone dash are E_UNEXPECTED_CHAR at the offending byte");
}

fn t29() -> TestResult {
  var ok = graph_err_is(dot_parse("digraph { a -> b = 1 }"), "E_UNEXPECTED_TOKEN@1:18");
  if !graph_err_is(dot_parse("digraph { , }"), "E_UNEXPECTED_TOKEN@1:11") { ok = false; }
  return assert(ok, "a token that cannot start a statement is E_UNEXPECTED_TOKEN");
}

fn t30() -> TestResult {
  var ok = streq(dot_error_code("E_BAD_ESCAPE@2:7"), "E_BAD_ESCAPE");
  if !streq(dot_error_code("E_ATTR_NOT_FOUND"), "E_ATTR_NOT_FOUND") { ok = false; }
  return assert(ok, "dot_error_code extracts the code before the first @");
}

fn t31() -> TestResult {
  let body = "\"my key\"=v1, plain=2";
  var ok = str_res_is(dot_attr_get(body, "my key"), "v1");
  if !str_res_is(dot_attr_get(body, "plain"), "2") { ok = false; }
  if !str_err_is(dot_attr_get(body, "absent"), "E_ATTR_NOT_FOUND") { ok = false; }
  if !str_err_is(dot_attr_get("x", "x"), "E_EXPECTED_EQUALS@1:2") { ok = false; }
  if !str_err_is(dot_attr_get("a=", "a"), "E_EXPECTED_ATTR_VALUE@1:3") { ok = false; }
  if !str_res_is(dot_attr_get("a=1;b=2", "b"), "2") { ok = false; }
  return assert(ok, "dot_attr_get finds, misses and diagnoses malformed bodies");
}

fn t32() -> TestResult {
  var g = dot_new(true, "T");
  dot_add_node(&mut g, "n1", "");
  dot_add_node(&mut g, "n2", dot_attr_pair("color", "red"));
  dot_add_edge(&mut g, "n1", "n2", "");
  dot_add_attr(&mut g, "rankdir", "TB");
  var ok = dot_stmt_count(&g) == 4;
  if dot_node_count(&g) != 2 { ok = false; }
  if dot_edge_count(&g) != 1 { ok = false; }
  if dot_attr_count(&g) != 1 { ok = false; }
  if dot_stmt_kind(&g, 0) != 0 { ok = false; }
  if dot_stmt_kind(&g, 2) != 1 { ok = false; }
  if dot_stmt_kind(&g, 3) != 2 { ok = false; }
  if dot_stmt_kind(&g, -1) != -1 { ok = false; }
  if dot_stmt_kind(&g, 4) != -1 { ok = false; }
  if !streq(dot_stmt_id(&g, 99), "") { ok = false; }
  if !streq(dot_stmt_attrs(&g, 99), "") { ok = false; }
  if !streq(dot_stmt_target(&g, -1), "") { ok = false; }
  if !dot_is_consistent(&g) { ok = false; }
  g.stmt_kind.push(0);
  if dot_is_consistent(&g) { ok = false; }
  if dot_stmt_count(&g) != 5 { ok = false; }
  let deg = dot_serialize(&g);
  if !streq(deg, "digraph T {\n  n1;\n  n2 [color=red];\n  n1 -> n2;\n  rankdir=TB;\n}") { ok = false; }
  return assert(ok, "builder API, counts, kinds and the parallel-vector guard");
}

fn t33() -> TestResult {
  var ok = streq(dot_attr_pair("a b", "c\"d"), "\"a b\"=\"c\\\"d\"");
  if !streq(dot_attr_pair("shape", "box"), "shape=box") { ok = false; }
  if !streq(dot_attr_pair("k", ""), "k=\"\"") { ok = false; }
  if !streq(dot_attr_pair("", "v"), "\"\"=v") { ok = false; }
  return assert(ok, "dot_attr_pair quotes and escapes each side only when needed");
}

fn main() -> Int {
  io.println("=== xiom.diagrams conformance tests ===");
  var failed: Int = 0;
  let r01 = t01();
  if r01.passed { io.println("  [PASS] " + r01.name); } else { io.println("  [FAIL] " + r01.name); failed = failed + 1; }
  let r02 = t02();
  if r02.passed { io.println("  [PASS] " + r02.name); } else { io.println("  [FAIL] " + r02.name); failed = failed + 1; }
  let r03 = t03();
  if r03.passed { io.println("  [PASS] " + r03.name); } else { io.println("  [FAIL] " + r03.name); failed = failed + 1; }
  let r04 = t04();
  if r04.passed { io.println("  [PASS] " + r04.name); } else { io.println("  [FAIL] " + r04.name); failed = failed + 1; }
  let r05 = t05();
  if r05.passed { io.println("  [PASS] " + r05.name); } else { io.println("  [FAIL] " + r05.name); failed = failed + 1; }
  let r06 = t06();
  if r06.passed { io.println("  [PASS] " + r06.name); } else { io.println("  [FAIL] " + r06.name); failed = failed + 1; }
  let r07 = t07();
  if r07.passed { io.println("  [PASS] " + r07.name); } else { io.println("  [FAIL] " + r07.name); failed = failed + 1; }
  let r08 = t08();
  if r08.passed { io.println("  [PASS] " + r08.name); } else { io.println("  [FAIL] " + r08.name); failed = failed + 1; }
  let r09 = t09();
  if r09.passed { io.println("  [PASS] " + r09.name); } else { io.println("  [FAIL] " + r09.name); failed = failed + 1; }
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
  let r25 = t25();
  if r25.passed { io.println("  [PASS] " + r25.name); } else { io.println("  [FAIL] " + r25.name); failed = failed + 1; }
  let r26 = t26();
  if r26.passed { io.println("  [PASS] " + r26.name); } else { io.println("  [FAIL] " + r26.name); failed = failed + 1; }
  let r27 = t27();
  if r27.passed { io.println("  [PASS] " + r27.name); } else { io.println("  [FAIL] " + r27.name); failed = failed + 1; }
  let r28 = t28();
  if r28.passed { io.println("  [PASS] " + r28.name); } else { io.println("  [FAIL] " + r28.name); failed = failed + 1; }
  let r29 = t29();
  if r29.passed { io.println("  [PASS] " + r29.name); } else { io.println("  [FAIL] " + r29.name); failed = failed + 1; }
  let r30 = t30();
  if r30.passed { io.println("  [PASS] " + r30.name); } else { io.println("  [FAIL] " + r30.name); failed = failed + 1; }
  let r31 = t31();
  if r31.passed { io.println("  [PASS] " + r31.name); } else { io.println("  [FAIL] " + r31.name); failed = failed + 1; }
  let r32 = t32();
  if r32.passed { io.println("  [PASS] " + r32.name); } else { io.println("  [FAIL] " + r32.name); failed = failed + 1; }
  let r33 = t33();
  if r33.passed { io.println("  [PASS] " + r33.name); } else { io.println("  [FAIL] " + r33.name); failed = failed + 1; }
  let r34 = t34();
  if r34.passed { io.println("  [PASS] " + r34.name); } else { io.println("  [FAIL] " + r34.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.diagrams: all tests passed");
  } else {
    io.println("xiom.diagrams: tests failed");
  }
  return failed;
}
