// XIOM -- xiom.hcl conformance tests (26 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Greenfield package: prove the pure-XIOM xiom.hcl module against its
// documented HCL2 subset grammar, flat storage accessors, canonical emitter
// and error catalog.
//
// Coverage: top-level attributes (names/raw values/lines), comments of all
// three kinds and comment markers inside quoted strings, labeled and nested
// blocks with parent indices and body byte ranges, multi-line list/object
// capture, CRLF and whitespace tolerance, duplicate attributes (first-match
// lookup), per-block lookups, canonical emit bytes, emit round trip and
// idempotence, label escapes, every documented error message and the
// documented duplicate-label / repeated-block policies.
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str
// values read from Vec[Str] elements to a pointer comparison, so every
// comparison below is routed through streq instead of `==`.

module hcl_tests
use xiom.io; use xiom.test; use xiom.hcl;
use xiom.string;
use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn opt_str_is(o: Option[Str], want: Str) -> Bool {
  match o {
    Some(v) => { return streq(v, want); },
    None => { return false; },
  }
  return false;
}

fn opt_str_none(o: Option[Str]) -> Bool {
  match o {
    Some(_) => { return false; },
    None => { return true; },
  }
  return true;
}

fn new_doc() -> HclDoc {
  return HclDoc{
    source: "";
    attr_names: Vec[Str].new();
    attr_values: Vec[Str].new();
    attr_lines: Vec[Int].new();
    attr_parents: Vec[Int].new();
    attr_offsets: Vec[Int].new();
    block_types: Vec[Str].new();
    block_label_counts: Vec[Int].new();
    block_label_starts: Vec[Int].new();
    block_labels: Vec[Str].new();
    block_parents: Vec[Int].new();
    block_body_starts: Vec[Int].new();
    block_body_ends: Vec[Int].new();
    block_lines: Vec[Int].new();
    block_offsets: Vec[Int].new();
  };
}

// Error message of a failed parse, or "" when the text parses.
fn err_of(text: Str) -> Str {
  let r = hcl_parse(text);
  match r {
    Ok(_) => { return ""; },
    Err(e) => { return e; },
  }
  return "";
}

fn parses(text: Str) -> Bool {
  return err_of(text).len() == 0;
}

// Parsed document, or an empty document when parsing failed (each test that
// uses this also asserts `parses(...)`).
fn parse_doc(text: Str) -> HclDoc {
  let r = hcl_parse(text);
  match r {
    Ok(d) => { return d; },
    Err(_) => { return new_doc(); },
  }
  return new_doc();
}

fn t1() -> TestResult {
  let text = "name = \"web\"\ncount = 3\nenabled = true\n";
  var ok = parses(text);
  let d = parse_doc(text);
  if hcl_attr_count(&d) != 3 { ok = false; }
  if hcl_attr_total(&d) != 3 { ok = false; }
  if hcl_block_count(&d) != 0 { ok = false; }
  if !streq(hcl_attr_name(&d, 0), "name") { ok = false; }
  if !streq(hcl_attr_name(&d, 1), "count") { ok = false; }
  if !streq(hcl_attr_name(&d, 2), "enabled") { ok = false; }
  if !streq(hcl_attr_value(&d, 0), "\"web\"") { ok = false; }
  if !streq(hcl_attr_value(&d, 1), "3") { ok = false; }
  if !streq(hcl_attr_value(&d, 2), "true") { ok = false; }
  if hcl_attr_line(&d, 0) != 1 { ok = false; }
  if hcl_attr_line(&d, 1) != 2 { ok = false; }
  if hcl_attr_line(&d, 2) != 3 { ok = false; }
  if hcl_attr_parent(&d, 0) != -1 { ok = false; }
  return assert(ok, "top-level attributes: names, raw values, lines, parents");
}

fn t2() -> TestResult {
  let text = "# top\n// slash\n/* block\n   comment */\na = 1 # trailing\nb = 2 // trailing\n/* inline */ c = 3\ns = \"a # b\"\nurl = \"http://x\"\n";
  var ok = parses(text);
  let d = parse_doc(text);
  if hcl_attr_count(&d) != 5 { ok = false; }
  if !streq(hcl_attr_value(&d, 0), "1") { ok = false; }
  if !streq(hcl_attr_value(&d, 1), "2") { ok = false; }
  if !streq(hcl_attr_value(&d, 2), "3") { ok = false; }
  if !streq(hcl_attr_value(&d, 3), "\"a # b\"") { ok = false; }
  if !streq(hcl_attr_value(&d, 4), "\"http://x\"") { ok = false; }
  if hcl_attr_line(&d, 0) != 5 { ok = false; }
  if hcl_attr_line(&d, 1) != 6 { ok = false; }
  if hcl_attr_line(&d, 2) != 7 { ok = false; }
  if hcl_attr_line(&d, 3) != 8 { ok = false; }
  if hcl_attr_line(&d, 4) != 9 { ok = false; }
  return assert(ok, "# / // / /* */ comments; markers inside strings are data");
}

fn t3() -> TestResult {
  let text = "resource \"aws_instance\" \"web\" {\n  ami = \"ami-1\"\n}\n";
  var ok = parses(text);
  let d = parse_doc(text);
  if hcl_block_count(&d) != 1 { ok = false; }
  if hcl_block_total(&d) != 1 { ok = false; }
  if !streq(hcl_block_type(&d, 0), "resource") { ok = false; }
  if hcl_block_label_count(&d, 0) != 2 { ok = false; }
  if !streq(hcl_block_label(&d, 0, 0), "aws_instance") { ok = false; }
  if !streq(hcl_block_label(&d, 0, 1), "web") { ok = false; }
  if !streq(hcl_block_label(&d, 0, 2), "") { ok = false; }
  let labels = hcl_block_labels(&d, 0);
  if labels.len() != 2 { ok = false; }
  if hcl_block_parent(&d, 0) != -1 { ok = false; }
  if hcl_block_line(&d, 0) != 1 { ok = false; }
  if hcl_attr_count(&d) != 0 { ok = false; }
  if hcl_attr_count_in(&d, 0) != 1 { ok = false; }
  if hcl_child_attr(&d, 0, 0) != 0 { ok = false; }
  if hcl_child_attr(&d, 0, 1) != -1 { ok = false; }
  if hcl_child_block(&d, 0, 0) != -1 { ok = false; }
  if hcl_child_total(&d, 0) != 1 { ok = false; }
  if !streq(hcl_attr_name(&d, 0), "ami") { ok = false; }
  if hcl_attr_parent(&d, 0) != 0 { ok = false; }
  return assert(ok, "labeled block: type, labels, parent, body attributes");
}

fn t4() -> TestResult {
  let text = "a {\n  b {\n    c = 1\n  }\n  d = 2\n}\ne {\n}\n";
  var ok = parses(text);
  let d = parse_doc(text);
  if hcl_block_total(&d) != 3 { ok = false; }
  if hcl_block_count(&d) != 2 { ok = false; }
  if !streq(hcl_block_type(&d, 0), "a") { ok = false; }
  if !streq(hcl_block_type(&d, 1), "b") { ok = false; }
  if !streq(hcl_block_type(&d, 2), "e") { ok = false; }
  if hcl_block_parent(&d, 1) != 0 { ok = false; }
  if hcl_block_parent(&d, 2) != -1 { ok = false; }
  if hcl_block_line(&d, 2) != 7 { ok = false; }
  if hcl_child_block(&d, 0, 0) != 1 { ok = false; }
  if hcl_child_block(&d, 0, 1) != -1 { ok = false; }
  if hcl_child_attr(&d, 0, 0) != 1 { ok = false; }
  if hcl_child_attr(&d, 1, 0) != 0 { ok = false; }
  if hcl_child_total(&d, 0) != 2 { ok = false; }
  if hcl_child_total(&d, 1) != 1 { ok = false; }
  if hcl_child_total(&d, 2) != 0 { ok = false; }
  if !streq(hcl_attr_name(&d, 0), "c") { ok = false; }
  if !streq(hcl_attr_name(&d, 1), "d") { ok = false; }
  if hcl_attr_parent(&d, 0) != 1 { ok = false; }
  if hcl_attr_parent(&d, 1) != 0 { ok = false; }
  return assert(ok, "nested blocks: parent indices and child navigation");
}

fn t5() -> TestResult {
  let text = "servers = [\n  \"a\",\n  \"b\",\n]\ntags = {\n  name = \"x\"\n}\nafter = 1\n";
  var ok = parses(text);
  let d = parse_doc(text);
  if hcl_attr_count(&d) != 3 { ok = false; }
  if !streq(hcl_attr_value(&d, 0), "[\n  \"a\",\n  \"b\",\n]") { ok = false; }
  if !streq(hcl_attr_value(&d, 1), "{\n  name = \"x\"\n}") { ok = false; }
  if !streq(hcl_attr_value(&d, 2), "1") { ok = false; }
  if hcl_attr_line(&d, 0) != 1 { ok = false; }
  if hcl_attr_line(&d, 1) != 5 { ok = false; }
  if hcl_attr_line(&d, 2) != 8 { ok = false; }
  let text2 = "weird = [\"#\", \"//\", \"]\", \"/*\"]\n";
  if !parses(text2) { ok = false; }
  let d2 = parse_doc(text2);
  if !streq(hcl_attr_value(&d2, 0), "[\"#\", \"//\", \"]\", \"/*\"]") { ok = false; }
  return assert(ok, "multi-line lists/objects captured whole; string chars ignored");
}

fn t6() -> TestResult {
  let text = "\r\n  a\t=\t1\r\n\r\n\tb{\r\n}\r\n";
  var ok = parses(text);
  let d = parse_doc(text);
  if hcl_attr_count(&d) != 1 { ok = false; }
  if !streq(hcl_attr_value(&d, 0), "1") { ok = false; }
  if hcl_attr_line(&d, 0) != 2 { ok = false; }
  if hcl_block_count(&d) != 1 { ok = false; }
  if !streq(hcl_block_type(&d, 0), "b") { ok = false; }
  if hcl_block_line(&d, 0) != 4 { ok = false; }
  if !streq(hcl_emit(&d), "a = 1\nb {}\n") { ok = false; }
  return assert(ok, "CRLF and tab/space tolerance");
}

fn t7() -> TestResult {
  let text = "a = 1\na = 2\nb = 3\n";
  var ok = parses(text);
  let d = parse_doc(text);
  if hcl_attr_total(&d) != 3 { ok = false; }
  if hcl_attr_lookup(&d, "a") != 0 { ok = false; }
  if hcl_attr_lookup(&d, "b") != 2 { ok = false; }
  if hcl_attr_lookup(&d, "z") != -1 { ok = false; }
  if !opt_str_is(hcl_attr_value_in(&d, -1, "a"), "1") { ok = false; }
  if !opt_str_is(hcl_attr_value_in(&d, -1, "b"), "3") { ok = false; }
  if !opt_str_none(hcl_attr_value_in(&d, -1, "z")) { ok = false; }
  if !streq(hcl_attr_value(&d, 1), "2") { ok = false; }
  return assert(ok, "duplicate attributes allowed; lookup returns first match");
}

fn t8() -> TestResult {
  let text = "outer {\n  k = 1\n  inner {\n    k = 2\n  }\n}\nk = 9\n";
  var ok = parses(text);
  let d = parse_doc(text);
  if hcl_attr_total(&d) != 3 { ok = false; }
  if hcl_attr_lookup(&d, "k") != 2 { ok = false; }
  if hcl_attr_lookup_in(&d, 0, "k") != 0 { ok = false; }
  if hcl_attr_lookup_in(&d, 1, "k") != 1 { ok = false; }
  if hcl_attr_lookup_in(&d, 2, "k") != -1 { ok = false; }
  if !opt_str_is(hcl_attr_value_in(&d, 0, "k"), "1") { ok = false; }
  if !opt_str_is(hcl_attr_value_in(&d, 1, "k"), "2") { ok = false; }
  if !opt_str_is(hcl_attr_value_in(&d, -1, "k"), "9") { ok = false; }
  return assert(ok, "attribute lookup is scoped per body");
}

fn t9() -> TestResult {
  let text = "server \"web\" {\n  host = \"localhost\"\n  ports = [80, 443]\n}\n\n# comment dropped\ntop = 1\n";
  var ok = parses(text);
  let d = parse_doc(text);
  let want = "server \"web\" {\n  host = \"localhost\"\n  ports = [80, 443]\n}\ntop = 1\n";
  if !streq(hcl_emit(&d), want) { ok = false; }
  return assert(ok, "canonical emit: 2-space indent, normalized spacing");
}

fn t10() -> TestResult {
  let text = "resource \"a\" \"b\" {\n  x = 1\n  nested {\n    y = [1, 2]\n  }\n  z = {\n    q = 2\n  }\n}\nh = 3\n";
  var ok = parses(text);
  let d1 = parse_doc(text);
  let e1 = hcl_emit(&d1);
  if !streq(e1, text) { ok = false; }
  let d2 = parse_doc(e1);
  let e2 = hcl_emit(&d2);
  if !streq(e2, e1) { ok = false; }
  if hcl_block_total(&d2) != 2 { ok = false; }
  if hcl_attr_total(&d2) != 4 { ok = false; }
  if !streq(hcl_attr_value(&d2, 1), "[1, 2]") { ok = false; }
  if hcl_child_attr(&d2, 0, 0) != 0 { ok = false; }
  return assert(ok, "canonical input round-trips byte-for-byte and emit is idempotent");
}

fn t11() -> TestResult {
  let text = "empty {\n}\n";
  var ok = parses(text);
  let d = parse_doc(text);
  if hcl_child_total(&d, 0) != 0 { ok = false; }
  if !streq(hcl_emit(&d), "empty {}\n") { ok = false; }
  let again = parse_doc(hcl_emit(&d));
  if !streq(hcl_emit(&again), "empty {}\n") { ok = false; }
  return assert(ok, "empty block emits as {} and re-parses");
}

fn t12() -> TestResult {
  let text = "b \"a\\\"b\" \"c\\\\d\" {}\n";
  var ok = parses(text);
  let d = parse_doc(text);
  if hcl_block_label_count(&d, 0) != 2 { ok = false; }
  if !streq(hcl_block_label(&d, 0, 0), "a\"b") { ok = false; }
  if !streq(hcl_block_label(&d, 0, 1), "c\\d") { ok = false; }
  let want = "b \"a\\\"b\" \"c\\\\d\" {}\n";
  if !streq(hcl_emit(&d), want) { ok = false; }
  return assert(ok, "label escapes: \\\" and \\\\ decode and re-encode");
}

fn t13() -> TestResult {
  var ok = streq(err_of("}\n"), "hcl: unmatched '}' at line 1");
  if !streq(err_of("a {\n}\n}\n"), "hcl: unmatched '}' at line 3") { ok = false; }
  if !streq(err_of("a {\n  b {\n}\n"), "hcl: unterminated block starting at line 1") { ok = false; }
  if !streq(err_of("a {"), "hcl: unterminated block starting at line 1") { ok = false; }
  if !parses("a {\n}\n") { ok = false; }
  return assert(ok, "unbalanced braces: unmatched } and unterminated block");
}

fn t14() -> TestResult {
  var ok = streq(err_of("a = \"x\n"), "hcl: unterminated string in expression at line 1");
  if !streq(err_of("a = \"x"), "hcl: unterminated string in expression at line 1") { ok = false; }
  if !streq(err_of("b {\n  c = \"y\n}\n"), "hcl: unterminated string in expression at line 2") { ok = false; }
  return assert(ok, "unterminated string in an expression");
}

fn t15() -> TestResult {
  var ok = streq(err_of("/* x\n y"), "hcl: unterminated block comment at line 1");
  if !streq(err_of("a = 1\n/* x"), "hcl: unterminated block comment at line 2") { ok = false; }
  return assert(ok, "unterminated block comment");
}

fn t16() -> TestResult {
  var ok = streq(err_of("b \"x\n"), "hcl: unterminated string in block label at line 1");
  if !streq(err_of("b \"x"), "hcl: unterminated string in block label at line 1") { ok = false; }
  return assert(ok, "unterminated string in a block label");
}

fn t17() -> TestResult {
  var ok = streq(err_of("b \"x\\qy\" {}\n"), "hcl: invalid escape in block label at line 1");
  if !parses("b \"a\\\\b\" {}\n") { ok = false; }
  return assert(ok, "label escapes other than \\\" and \\\\ are rejected");
}

fn t18() -> TestResult {
  var ok = streq(err_of("= 1\n"), "hcl: invalid attribute name at line 1");
  if !streq(err_of("a =\n"), "hcl: missing attribute value at line 1") { ok = false; }
  if !streq(err_of("a = # c\n"), "hcl: missing attribute value at line 1") { ok = false; }
  if !streq(err_of("a = /* c */ 1\n"), "hcl: missing attribute value at line 1") { ok = false; }
  if !streq(err_of("+ 1\n"), "hcl: stray token at line 1") { ok = false; }
  if !streq(err_of("123 = 4\n"), "hcl: stray token at line 1") { ok = false; }
  if !streq(err_of("foo bar\n"), "hcl: expected '=' or '{' after 'foo' at line 1") { ok = false; }
  if !streq(err_of("foo\n"), "hcl: expected '=' or '{' after 'foo' at line 1") { ok = false; }
  if !streq(err_of("\"a\" {}\n"), "hcl: block has no type at line 1") { ok = false; }
  if !streq(err_of("{ }\n"), "hcl: block has no type at line 1") { ok = false; }
  if !streq(err_of("a \"x\"\n"), "hcl: expected '{' after block labels at line 1") { ok = false; }
  if !streq(err_of("a \"x\" = 1\n"), "hcl: expected '{' after block labels at line 1") { ok = false; }
  return assert(ok, "statement errors: bad name, missing value, stray token, no type, no brace");
}

fn t19() -> TestResult {
  var ok = streq(err_of("a = [1, 2\n"), "hcl: unbalanced brackets in expression at line 1");
  if !streq(err_of("a = ]\n"), "hcl: unbalanced brackets in expression at line 1") { ok = false; }
  if !streq(err_of("a = {x = 1\n"), "hcl: unbalanced brackets in expression at line 1") { ok = false; }
  if !streq(err_of("a = [1, 2}\n"), "hcl: unbalanced brackets in expression at line 1") { ok = false; }
  if !streq(err_of("a = (1\n"), "hcl: unbalanced brackets in expression at line 1") { ok = false; }
  if !parses("a = [1, (2), {b = 3}]\n") { ok = false; }
  return assert(ok, "unbalanced and mismatched brackets in expressions");
}

fn t20() -> TestResult {
  var ok = streq(err_of("a = <<EOF\nhello\nEOF\n"), "hcl: heredocs are not supported at line 1");
  if !streq(err_of("a = <<-EOF\nhello\nEOF\n"), "hcl: heredocs are not supported at line 1") { ok = false; }
  if !parses("a = 1 << 2\n") { ok = false; }
  return assert(ok, "heredocs are rejected with a clear error; << elsewhere is raw");
}

fn t21() -> TestResult {
  var ok = streq(err_of("b \"x\" \"x\" {}\n"), "hcl: duplicate block label at line 1");
  let text = "r \"a\" \"b\" {\n}\nr \"a\" \"b\" {\n}\n";
  if !parses(text) { ok = false; }
  let d = parse_doc(text);
  if hcl_block_count(&d) != 2 { ok = false; }
  if !streq(hcl_block_label(&d, 1, 1), "b") { ok = false; }
  return assert(ok, "duplicate labels in one header rejected; repeated blocks allowed");
}

fn t22() -> TestResult {
  var ok = streq(err_of(""), "");
  let d = parse_doc("");
  if hcl_attr_total(&d) != 0 { ok = false; }
  if hcl_block_total(&d) != 0 { ok = false; }
  if !streq(hcl_emit(&d), "") { ok = false; }
  let text = "# c\n// d\n/* e */\n\n";
  if !parses(text) { ok = false; }
  let d2 = parse_doc(text);
  if hcl_attr_total(&d2) != 0 { ok = false; }
  if hcl_block_total(&d2) != 0 { ok = false; }
  if !streq(hcl_emit(&d2), "") { ok = false; }
  return assert(ok, "empty and comment-only documents");
}

fn t23() -> TestResult {
  let text = "outer {\n  x = 1\n}\n";
  var ok = parses(text);
  let d = parse_doc(text);
  if hcl_block_body_start(&d, 0) != 7 { ok = false; }
  if hcl_block_body_end(&d, 0) != 16 { ok = false; }
  if !streq(hcl_block_body(&d, 0), "\n  x = 1\n") { ok = false; }
  if !streq(hcl_block_body(&d, 99), "") { ok = false; }
  if hcl_block_body_start(&d, 99) != -1 { ok = false; }
  return assert(ok, "body byte ranges slice the source verbatim");
}

fn t24() -> TestResult {
  let text = "l0 {\n  l1 \"x\" {\n    l2 {\n      a = 1\n    }\n  }\n}\n";
  var ok = parses(text);
  let d = parse_doc(text);
  if !streq(hcl_emit(&d), text) { ok = false; }
  if hcl_block_parent(&d, 2) != 1 { ok = false; }
  if hcl_attr_parent(&d, 0) != 2 { ok = false; }
  return assert(ok, "three-level nesting emits with 2-space indentation per level");
}

fn t25() -> TestResult {
  let text = "u = http://x\nq = \"http://x\"\n";
  var ok = parses(text);
  let d = parse_doc(text);
  if !streq(hcl_attr_value(&d, 0), "http:") { ok = false; }
  if !streq(hcl_attr_value(&d, 1), "\"http://x\"") { ok = false; }
  if !streq(hcl_emit(&d), "u = http:\nq = \"http://x\"\n") { ok = false; }
  return assert(ok, "unquoted // starts a comment; quoted // is preserved");
}

fn t26() -> TestResult {
  let text = "# c\na = [\n  1,\n]\n\nb = 2\n";
  var ok = parses(text);
  let d = parse_doc(text);
  if hcl_attr_count(&d) != 2 { ok = false; }
  if hcl_attr_line(&d, 0) != 2 { ok = false; }
  if hcl_attr_line(&d, 1) != 6 { ok = false; }
  if !streq(hcl_emit(&d), "a = [\n  1,\n]\nb = 2\n") { ok = false; }
  return assert(ok, "line numbers stay correct across multi-line values and comments");
}

fn main() -> Int {
  io.println("=== xiom.hcl conformance tests ===");
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
  let r25 = t25();
  if r25.passed { io.println("  [PASS] " + r25.name); } else { io.println("  [FAIL] " + r25.name); failed = failed + 1; }
  let r26 = t26();
  if r26.passed { io.println("  [PASS] " + r26.name); } else { io.println("  [FAIL] " + r26.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.hcl: all tests passed");
  } else {
    io.println("xiom.hcl: tests failed");
  }
  return failed;
}
