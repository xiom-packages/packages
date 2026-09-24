// XIOM -- xiom.query conformance tests (22 checks)
// Port task: prove the pure-XIOM xiom.query module against its documented
// filter-expression grammar and evaluation rules.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module query_tests
use xiom.io; use xiom.test; use xiom.query;
use xiom.string.compare;

// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, and parse errors come
// back as Result payloads; every string check below is routed through streq.

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn term_is(expr: Str, i: Int, field: Str, op: Str, value: Str) -> Bool {
  let r = query_parse(expr);
  match r {
    Ok(q) => {
      if i < 0 || i >= query_term_count(&q) { return false; }
      let f: Str = q.fields[i];
      let o: Str = q.ops[i];
      let v: Str = q.values[i];
      if !streq(f, field) { return false; }
      if !streq(o, op) { return false; }
      if !streq(v, value) { return false; }
      return true;
    },
    Err(_) => { return false; },
  }
  return false;
}

fn term_count_is(expr: Str, want: Int) -> Bool {
  let r = query_parse(expr);
  match r {
    Ok(q) => { return query_term_count(&q) == want; },
    Err(_) => { return false; },
  }
  return false;
}

fn join_is(expr: Str, i: Int, want: Str) -> Bool {
  let r = query_parse(expr);
  match r {
    Ok(q) => {
      if i < 0 || i >= query_term_count(&q) { return false; }
      let got: Str = q.joins[i];
      return streq(got, want);
    },
    Err(_) => { return false; },
  }
  return false;
}

fn parse_err_is(expr: Str, want: Str) -> Bool {
  let r = query_parse(expr);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn to_string_is(expr: Str, want: Str) -> Bool {
  let r = query_parse(expr);
  match r {
    Ok(q) => { return streq(query_to_string(&q), want); },
    Err(_) => { return false; },
  }
  return false;
}

fn matches(expr: Str, keys: &Vec[Str], values: &Vec[Str]) -> Bool {
  let r = query_parse(expr);
  match r {
    Ok(q) => { return query_matches(&q, &keys, &values); },
    Err(_) => { return false; },
  }
  return false;
}

fn select_count(expr: Str, headers: &Vec[Str], rows: &Vec[Vec[Str]]) -> Int {
  let r = query_parse(expr);
  match r {
    Ok(q) => { return query_select(&headers, &rows, &q).len(); },
    Err(_) => { return -1; },
  }
  return -1;
}

fn select_cell(expr: Str, headers: &Vec[Str], rows: &Vec[Vec[Str]], row_i: Int, col_i: Int, want: Str) -> Bool {
  let r = query_parse(expr);
  match r {
    Ok(q) => {
      let sel = query_select(&headers, &rows, &q);
      if row_i < 0 || row_i >= sel.len() { return false; }
      let row: Vec[Str] = sel[row_i];
      if col_i < 0 || col_i >= row.len() { return false; }
      let got: Str = row[col_i];
      return streq(got, want);
    },
    Err(_) => { return false; },
  }
  return false;
}

fn t1() -> TestResult {
  var ok = term_is("age = 30", 0, "age", "=", "30");
  if !term_is("name = alice", 0, "name", "=", "alice") { ok = false; }
  if !term_count_is("age = 30", 1) { ok = false; }
  return assert(ok, "parse: '=' term with field, operator and value");
}

fn t2() -> TestResult {
  var ok = term_is("score != 10", 0, "score", "!=", "10");
  if !term_count_is("score != 10", 1) { ok = false; }
  return assert(ok, "parse: '!=' term");
}

fn t3() -> TestResult {
  var ok = term_is("x < 5", 0, "x", "<", "5");
  if !term_is("x <= 5", 0, "x", "<=", "5") { ok = false; }
  return assert(ok, "parse: '<' and '<=' terms");
}

fn t4() -> TestResult {
  var ok = term_is("x > 5", 0, "x", ">", "5");
  if !term_is("x >= 5", 0, "x", ">=", "5") { ok = false; }
  return assert(ok, "parse: '>' and '>=' terms");
}

fn t5() -> TestResult {
  var ok = term_is("text contains or", 0, "text", "contains", "or");
  if !term_is("text startswith pre", 0, "text", "startswith", "pre") { ok = false; }
  if !term_is("text endswith post", 0, "text", "endswith", "post") { ok = false; }
  return assert(ok, "parse: contains/startswith/endswith terms");
}

fn t6() -> TestResult {
  var ok = term_is("city = \"New York\"", 0, "city", "=", "New York");
  if !term_is("city = 'Los Angeles'", 0, "city", "=", "Los Angeles") { ok = false; }
  if !term_is("note = \"\"", 0, "note", "=", "") { ok = false; }
  if !term_is("\"first name\" = Ada", 0, "first name", "=", "Ada") { ok = false; }
  if !term_is("nick = it's", 0, "nick", "=", "it's") { ok = false; }
  return assert(ok, "parse: quoted values keep spaces; quotes only start a token");
}

fn t7() -> TestResult {
  var ok = term_count_is("a = 1 and b = 2 OR c = 3", 3);
  if !join_is("a = 1 and b = 2 OR c = 3", 0, "") { ok = false; }
  if !join_is("a = 1 and b = 2 OR c = 3", 1, "and") { ok = false; }
  if !join_is("a = 1 and b = 2 OR c = 3", 2, "or") { ok = false; }
  if !term_count_is("a = 1 And b = 2 oR c = 3", 3) { ok = false; }
  if !join_is("a = 1 And b = 2 oR c = 3", 1, "and") { ok = false; }
  if !join_is("a = 1 And b = 2 oR c = 3", 2, "or") { ok = false; }
  return assert(ok, "parse: AND/OR connectors are case-insensitive; joins recorded per term");
}

fn t8() -> TestResult {
  var ok = parse_err_is("a = b AND", "query: expected term after connector");
  if !parse_err_is("a =", "query: incomplete term") { ok = false; }
  if !parse_err_is("a", "query: incomplete term") { ok = false; }
  if !parse_err_is("a ~ b", "query: unknown operator: ~") { ok = false; }
  if !parse_err_is("a CONTAINS b", "query: unknown operator: CONTAINS") { ok = false; }
  return assert(ok, "parse errors: trailing connector, missing value, unknown operator");
}

fn t9() -> TestResult {
  var ok = parse_err_is("", "query: empty expression");
  if !parse_err_is("   ", "query: empty expression") { ok = false; }
  if !parse_err_is("a = \"x", "query: unterminated quote") { ok = false; }
  if !parse_err_is("AND a = b", "query: expression must start with a term") { ok = false; }
  if !parse_err_is("a = b c = d", "query: expected connector, got: c") { ok = false; }
  if !parse_err_is("\"\" = x", "query: empty field name") { ok = false; }
  return assert(ok, "parse errors: empty input, quote, leading connector, missing connector");
}

fn t10() -> TestResult {
  var ok = to_string_is("age >= 30 and city = NYC", "age >= 30 AND city = NYC");
  if !to_string_is("a != b OR c = d", "a != b OR c = d") { ok = false; }
  if !to_string_is("a = 1 or b = 2 or c = 3", "a = 1 OR b = 2 OR c = 3") { ok = false; }
  return assert(ok, "to_string: canonical spacing and uppercase connectors");
}

fn t11() -> TestResult {
  var ok = to_string_is("city = 'Los Angeles' and zip = 90001", "city = \"Los Angeles\" AND zip = 90001");
  if !to_string_is("city = \"Los Angeles\" AND zip = 90001", "city = \"Los Angeles\" AND zip = 90001") { ok = false; }
  if !term_is("city = \"Los Angeles\" AND zip = 90001", 1, "zip", "=", "90001") { ok = false; }
  if !to_string_is("quote = 'he said \"hi\"'", "quote = 'he said \"hi\"'") { ok = false; }
  return assert(ok, "to_string: values re-quote for a stable round trip");
}

fn t12() -> TestResult {
  var ok = query_match_one(">", "10", "9");
  if !query_match_one("<", "9", "10") { ok = false; }
  if query_match_one("=", "10", "9") { ok = false; }
  if !query_match_one("=", "10", "010") { ok = false; }
  if !query_match_one("=", "+5", "5") { ok = false; }
  if !query_match_one("=", "-0", "0") { ok = false; }
  return assert(ok, "match: integers compare by numeric value (leading zeros and signs fold)");
}

fn t13() -> TestResult {
  var ok = query_match_one("=", "apple", "apple");
  if query_match_one("=", "apple", "Apple") { ok = false; }
  if !query_match_one("<", "apple", "banana") { ok = false; }
  if !query_match_one(">", "banana", "apple") { ok = false; }
  if !query_match_one("<=", "apple", "apple") { ok = false; }
  if !query_match_one(">=", "banana", "banana") { ok = false; }
  if !query_match_one("!=", "apple", "banana") { ok = false; }
  if query_match_one("!=", "apple", "apple") { ok = false; }
  if !query_match_one("<", "apple", "apples") { ok = false; }
  return assert(ok, "match: non-integer pairs compare byte-wise via str_compare");
}

fn t14() -> TestResult {
  var ok = !query_match_one("<", "5", "+3");
  if !query_match_one(">", "5", "+3") { ok = false; }
  if query_match_one("<", "9223372036854775808", "9223372036854775807") { ok = false; }
  if !query_match_one("<", "9223372036854775806", "9223372036854775807") { ok = false; }
  if !query_match_one("<", "-10", "-5") { ok = false; }
  if !query_match_one("<=", "-10", "-10") { ok = false; }
  if query_match_one(">", "2", "10") { ok = false; }
  if query_match_one("=", "10", "abc") { ok = false; }
  if !query_match_one("<", "10", "abc") { ok = false; }
  return assert(ok, "match: numeric only when both sides parse within Int64; else bytes");
}

fn t15() -> TestResult {
  var ok = query_match_one("contains", "New York", "York");
  if query_match_one("contains", "New York", "york") { ok = false; }
  if !query_match_one("contains", "New York", "New") { ok = false; }
  if !query_match_one("startswith", "New York", "New") { ok = false; }
  if query_match_one("startswith", "New York", "York") { ok = false; }
  if !query_match_one("endswith", "New York", "York") { ok = false; }
  if query_match_one("endswith", "New York", "New") { ok = false; }
  if !query_match_one("contains", "abc", "") { ok = false; }
  if !query_match_one("startswith", "abc", "") { ok = false; }
  if !query_match_one("endswith", "abc", "") { ok = false; }
  if query_match_one("contains", "abc", "abcd") { ok = false; }
  return assert(ok, "match: substring operators are byte-wise; empty needle matches");
}

fn t16() -> TestResult {
  var ok = !query_match_one("~", "a", "b");
  if query_match_one("CONTAINS", "abc", "b") { ok = false; }
  let empty = Query{
    fields: Vec[Str].new();
    ops: Vec[Str].new();
    values: Vec[Str].new();
    joins: Vec[Str].new();
  };
  let keys = Vec[Str].new();
  let vals = Vec[Str].new();
  if !query_matches(&empty, &keys, &vals) { ok = false; }
  if !streq(query_to_string(&empty), "") { ok = false; }
  if query_term_count(&empty) != 0 { ok = false; }
  return assert(ok, "match: unknown operator is false; a query with no terms matches");
}

fn t17() -> TestResult {
  var keys = Vec[Str].new();
  keys.push("name"); keys.push("age"); keys.push("city");
  var vals = Vec[Str].new();
  vals.push("alice"); vals.push("30"); vals.push("NYC");
  var ok = matches("age >= 30", &keys, &vals);
  if matches("age > 30", &keys, &vals) { ok = false; }
  if !matches("name = alice AND city = NYC", &keys, &vals) { ok = false; }
  if !matches("name = bob OR city = NYC", &keys, &vals) { ok = false; }
  if matches("name = bob AND city = NYC", &keys, &vals) { ok = false; }
  if !matches("age = 30", &keys, &vals) { ok = false; }
  return assert(ok, "matches: AND/OR over a flat key/value record");
}

fn t18() -> TestResult {
  var keys = Vec[Str].new();
  keys.push("a");
  var vals = Vec[Str].new();
  vals.push("5");
  var ok = !matches("b = 5", &keys, &vals);
  if matches("b < 5", &keys, &vals) { ok = false; }
  if matches("b contains 5", &keys, &vals) { ok = false; }
  if !matches("b != 5", &keys, &vals) { ok = false; }
  if !matches("b = 5 OR a = 5", &keys, &vals) { ok = false; }
  if !matches("a = 5", &keys, &vals) { ok = false; }
  return assert(ok, "matches: a missing field is false except for '!='");
}

fn t19() -> TestResult {
  var keys = Vec[Str].new();
  keys.push("a"); keys.push("b"); keys.push("c");
  var vals = Vec[Str].new();
  vals.push("1"); vals.push("9"); vals.push("9");
  var ok = !matches("a = 1 OR b = 2 AND c = 3", &keys, &vals);
  if !matches("a = 2 AND b = 9 OR c = 9", &keys, &vals) { ok = false; }
  return assert(ok, "matches: terms fold strictly left to right (no precedence)");
}

fn t20() -> TestResult {
  var headers = Vec[Str].new();
  headers.push("name"); headers.push("age"); headers.push("city");
  var rows = Vec[Vec[Str]].new();
  var r0 = Vec[Str].new(); r0.push("alice"); r0.push("30"); r0.push("NYC"); rows.push(r0);
  var r1 = Vec[Str].new(); r1.push("bob"); r1.push("17"); r1.push("LA"); rows.push(r1);
  var r2 = Vec[Str].new(); r2.push("carol"); r2.push("41"); r2.push("NYC"); rows.push(r2);
  var r3 = Vec[Str].new(); r3.push("dave"); r3.push("30"); r3.push("SF"); rows.push(r3);
  var ok = select_count("age >= 30 AND city = NYC", &headers, &rows) == 2;
  if !select_cell("age >= 30 AND city = NYC", &headers, &rows, 0, 0, "alice") { ok = false; }
  if !select_cell("age >= 30 AND city = NYC", &headers, &rows, 0, 2, "NYC") { ok = false; }
  if !select_cell("age >= 30 AND city = NYC", &headers, &rows, 1, 0, "carol") { ok = false; }
  if !select_cell("age >= 30 AND city = NYC", &headers, &rows, 1, 1, "41") { ok = false; }
  if select_count("age > 100", &headers, &rows) != 0 { ok = false; }
  return assert(ok, "select: rows whose cell map matches, in original order");
}

fn t21() -> TestResult {
  var headers = Vec[Str].new();
  headers.push("name"); headers.push("age"); headers.push("city");
  var empty = Vec[Vec[Str]].new();
  var ok = select_count("name = alice", &headers, &empty) == 0;
  var ragged = Vec[Vec[Str]].new();
  var r0 = Vec[Str].new(); r0.push("eve"); ragged.push(r0);
  if select_count("name = eve AND age >= 1", &headers, &ragged) != 0 { ok = false; }
  if select_count("name = eve AND age != 1", &headers, &ragged) != 1 { ok = false; }
  var headers1 = Vec[Str].new();
  headers1.push("a");
  var wide = Vec[Vec[Str]].new();
  var w0 = Vec[Str].new(); w0.push("x"); w0.push("extra"); wide.push(w0);
  if select_count("a = x", &headers1, &wide) != 1 { ok = false; }
  if !select_cell("a = x", &headers1, &wide, 0, 1, "extra") { ok = false; }
  return assert(ok, "select: empty and ragged inputs; extra cells are preserved");
}

fn t22() -> TestResult {
  var headers = Vec[Str].new();
  headers.push("n"); headers.push("score");
  var rows = Vec[Vec[Str]].new();
  var r0 = Vec[Str].new(); r0.push("n1"); r0.push("9"); rows.push(r0);
  var r1 = Vec[Str].new(); r1.push("n2"); r1.push("10"); rows.push(r1);
  var r2 = Vec[Str].new(); r2.push("n3"); r2.push("100"); rows.push(r2);
  var ok = select_count("score >= 10", &headers, &rows) == 2;
  if !select_cell("score >= 10", &headers, &rows, 0, 0, "n2") { ok = false; }
  if !select_cell("score >= 10", &headers, &rows, 1, 1, "100") { ok = false; }
  return assert(ok, "select: comparison columns compare numerically");
}

fn main() -> Int {
  io.println("=== xiom.query conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.query: all tests passed");
  } else {
    io.println("xiom.query: tests failed");
  }
  return failed;
}
