// XIOM -- xiom.dimacs conformance tests (25 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module dimacs_tests
use xiom.io; use xiom.test; use xiom.dimacs;
use xiom.string.compare;

// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every string check
// below (error messages included) is routed through streq.

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// Signed literal at flat position i, read through a typed local.
fn lit_is(c: &Cnf, i: Int, want: Int) -> Bool {
  let got: Int = dimacs_literal(c, i);
  return got == want;
}

// Signed literal j of clause k, read through a typed local.
fn clause_lit_is(c: &Cnf, k: Int, j: Int, want: Int) -> Bool {
  let got: Int = dimacs_clause_literal(c, k, j);
  return got == want;
}

// True when parsing `text` fails with exactly the error `want`.
fn parse_err_is(text: Str, want: Str) -> Bool {
  let r = dimacs_parse(text);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// True when parsing `text` succeeds.
fn parses_ok(text: Str) -> Bool {
  let r = dimacs_parse(text);
  match r {
    Ok(_) => { return true; },
    Err(_) => { return false; },
  }
  return false;
}

// True when parsing `text` succeeds with exactly 1 literal equal to 1.
fn parses_one(text: Str) -> Bool {
  let r = dimacs_parse(text);
  match r {
    Ok(c) => {
      if dimacs_clause_count(&c) != 1 { return false; }
      if dimacs_literal_count(&c) != 1 { return false; }
      if !lit_is(&c, 0, 1) { return false; }
      return true;
    },
    Err(_) => { return false; },
  }
  return false;
}

// True when parsing `text` succeeds with the wanted clause/literal counts.
fn parses_with(text: Str, want_clauses: Int, want_lits: Int) -> Bool {
  let r = dimacs_parse(text);
  match r {
    Ok(c) => {
      var ok = dimacs_clause_count(&c) == want_clauses;
      if dimacs_literal_count(&c) != want_lits { ok = false; }
      return ok;
    },
    Err(_) => { return false; },
  }
  return false;
}

// Element-wise equality of the flat literal vectors of two formulas.
fn same_lits(a: &Cnf, b: &Cnf) -> Bool {
  if dimacs_literal_count(a) != dimacs_literal_count(b) { return false; }
  var i = 0;
  while i < dimacs_literal_count(a) {
    let wanted: Int = dimacs_literal(b, i);
    if !lit_is(a, i, wanted) { return false; }
    i = i + 1;
  }
  return true;
}

fn t1() -> TestResult {
  let r = dimacs_parse("p cnf 3 2\n1 -3 0\n2 0\n");
  match r {
    Ok(c) => {
      var ok = dimacs_var_count(&c) == 3;
      if dimacs_clause_count(&c) != 2 { ok = false; }
      if dimacs_literal_count(&c) != 3 { ok = false; }
      if !lit_is(&c, 0, 1) { ok = false; }
      if !lit_is(&c, 1, -3) { ok = false; }
      if !lit_is(&c, 2, 2) { ok = false; }
      if !clause_lit_is(&c, 0, 0, 1) { ok = false; }
      if !clause_lit_is(&c, 0, 1, -3) { ok = false; }
      if !clause_lit_is(&c, 1, 0, 2) { ok = false; }
      if dimacs_clause_start(&c, 0) != 0 { ok = false; }
      if dimacs_clause_start(&c, 1) != 2 { ok = false; }
      if dimacs_clause_len(&c, 0) != 2 { ok = false; }
      if dimacs_clause_len(&c, 1) != 1 { ok = false; }
      return assert(ok, "parse: counts, flat literals and clause boundaries");
    },
    Err(_) => { return assert(false, "parse: counts, flat literals and clause boundaries"); },
  }
  return assert(false, "unreachable");
}

fn t2() -> TestResult {
  let r = dimacs_parse("c hello\n\nc more\np cnf 2 1\nc split\n1\n-2 0\n");
  match r {
    Ok(c) => {
      var ok = dimacs_clause_count(&c) == 1;
      if dimacs_literal_count(&c) != 2 { ok = false; }
      if !clause_lit_is(&c, 0, 0, 1) { ok = false; }
      if !clause_lit_is(&c, 0, 1, -2) { ok = false; }
      return assert(ok, "comments and blank lines are ignored anywhere");
    },
    Err(_) => { return assert(false, "comments and blank lines are ignored anywhere"); },
  }
  return assert(false, "unreachable");
}

fn t3() -> TestResult {
  let r = dimacs_parse("p cnf 3 1\n1\n-2\n3 0\n");
  match r {
    Ok(c) => {
      var ok = dimacs_clause_count(&c) == 1;
      if dimacs_clause_len(&c, 0) != 3 { ok = false; }
      if !clause_lit_is(&c, 0, 0, 1) { ok = false; }
      if !clause_lit_is(&c, 0, 1, -2) { ok = false; }
      if !clause_lit_is(&c, 0, 2, 3) { ok = false; }
      return assert(ok, "clause split across lines is one clause");
    },
    Err(_) => { return assert(false, "clause split across lines is one clause"); },
  }
  return assert(false, "unreachable");
}

fn t4() -> TestResult {
  let r = dimacs_parse("p cnf 0 2\n0\n0\n");
  match r {
    Ok(c) => {
      var ok = dimacs_var_count(&c) == 0;
      if dimacs_clause_count(&c) != 2 { ok = false; }
      if dimacs_literal_count(&c) != 0 { ok = false; }
      if dimacs_clause_len(&c, 0) != 0 { ok = false; }
      if dimacs_clause_len(&c, 1) != 0 { ok = false; }
      if dimacs_clause_start(&c, 1) != 0 { ok = false; }
      return assert(ok, "empty clauses: a bare 0 closes a zero-literal clause");
    },
    Err(_) => { return assert(false, "empty clauses: a bare 0 closes a zero-literal clause"); },
  }
  return assert(false, "unreachable");
}

fn t5() -> TestResult {
  let r = dimacs_parse("p cnf 5 0\n");
  match r {
    Ok(c) => {
      var ok = dimacs_var_count(&c) == 5;
      if dimacs_clause_count(&c) != 0 { ok = false; }
      if dimacs_literal_count(&c) != 0 { ok = false; }
      if !streq(dimacs_emit(&c), "p cnf 5 0\n") { ok = false; }
      return assert(ok, "header-only document: zero clauses, canonical emit");
    },
    Err(_) => { return assert(false, "header-only document: zero clauses, canonical emit"); },
  }
  return assert(false, "unreachable");
}

fn t6() -> TestResult {
  var ok = parses_one("p cnf 1 1\r\n1 0\r\n");
  if !parses_one("p cnf 1 1\r1 0\r") { ok = false; }
  return assert(ok, "line endings: LF, CRLF and lone CR all terminate lines");
}

fn t7() -> TestResult {
  return assert(parse_err_is("1 0\n", "dimacs: missing header at line 1"), "error: clause token before the header");
}

fn t8() -> TestResult {
  var ok = parse_err_is("", "dimacs: missing header at end of input");
  if !parse_err_is("c only\n\n", "dimacs: missing header at end of input") { ok = false; }
  if !parse_err_is("   \n", "dimacs: missing header at end of input") { ok = false; }
  return assert(ok, "error: no header in empty or comment-only input");
}

fn t9() -> TestResult {
  return assert(parse_err_is("p cnf 1 1\np cnf 1 1\n1 0\n", "dimacs: duplicate header at line 2"), "error: exactly one header, duplicate rejected");
}

fn t10() -> TestResult {
  var ok = parse_err_is("p cnf 1\n", "dimacs: malformed header at line 1");
  if !parse_err_is("p dimacs 1 1\n", "dimacs: malformed header at line 1") { ok = false; }
  if !parse_err_is("p cnf 1 1 extra\n", "dimacs: malformed header at line 1") { ok = false; }
  return assert(ok, "error: malformed header shapes are rejected");
}

fn t11() -> TestResult {
  var ok = parse_err_is("p cnf x 1\n", "dimacs: invalid variable count at line 1");
  if !parse_err_is("p cnf 1 y\n", "dimacs: invalid clause count at line 1") { ok = false; }
  if !parse_err_is("p cnf 9223372036854775808 1\n", "dimacs: invalid variable count at line 1") { ok = false; }
  if !parses_ok("p cnf 9223372036854775807 0\n") { ok = false; }
  return assert(ok, "header counts: non-digits rejected, INT_MAX accepted");
}

fn t12() -> TestResult {
  return assert(parse_err_is("p cnf 2 3\n1 0\n", "dimacs: clause count mismatch: expected 3, got 1"), "error: fewer clauses than the header declares");
}

fn t13() -> TestResult {
  var ok = parse_err_is("p cnf 1 1\n1\n", "dimacs: unterminated clause at end of input");
  if !parse_err_is("p cnf 2 2\n1 0\n2\n", "dimacs: unterminated clause at end of input") { ok = false; }
  return assert(ok, "error: missing zero terminator at end of input");
}

fn t14() -> TestResult {
  var ok = parse_err_is("p cnf 1 1\n1 0 2 0\n", "dimacs: token after final clause at line 2");
  if !parse_err_is("p cnf 1 0\n1 0\n", "dimacs: token after final clause at line 2") { ok = false; }
  return assert(ok, "error: no token after the final declared clause");
}

fn t15() -> TestResult {
  var ok = parse_err_is("p cnf 2 1\n3 0\n", "dimacs: literal out of range at line 2");
  if !parse_err_is("p cnf 2 1\n-3 0\n", "dimacs: literal out of range at line 2") { ok = false; }
  return assert(ok, "error: literal magnitude above the declared variable count");
}

fn t16() -> TestResult {
  return assert(parse_err_is("p cnf 2 1\n-0\n", "dimacs: negative literal 0 at line 2"), "error: negative literal 0 is rejected");
}

fn t17() -> TestResult {
  var ok = parse_err_is("p cnf 2 1\nx 0\n", "dimacs: invalid token at line 2");
  if !parse_err_is("p cnf 2 1\n1 + 0\n", "dimacs: invalid token at line 2") { ok = false; }
  if !parse_err_is("p cnf 2 1\n--1 0\n", "dimacs: invalid token at line 2") { ok = false; }
  return assert(ok, "error: non-integer, plus sign and double minus are invalid tokens");
}

fn t18() -> TestResult {
  return assert(parse_err_is("p cnf 2 1\n99999999999999999999 0\n", "dimacs: integer overflow at line 2"), "error: literal that does not fit in an Int");
}

fn t19() -> TestResult {
  let r = dimacs_parse("p cnf 3 2\n  1   -3 0\n2 0");
  match r {
    Ok(c) => {
      return assert(streq(dimacs_emit(&c), "p cnf 3 2\n1 -3 0\n2 0\n"), "emit: canonical spacing, one clause per line, LF terminator");
    },
    Err(_) => { return assert(false, "emit: canonical spacing, one clause per line, LF terminator"); },
  }
  return assert(false, "unreachable");
}

fn t20() -> TestResult {
  let text = "p cnf 3 3\n1 -2 0\n0\n-3 3 0\n";
  let first = dimacs_parse(text);
  match first {
    Ok(a) => {
      if !streq(dimacs_emit(&a), text) { return assert(false, "round trip: emit of a canonical document is itself"); }
      let second = dimacs_parse(dimacs_emit(&a));
      match second {
        Ok(b) => {
          var ok = dimacs_var_count(&b) == dimacs_var_count(&a);
          if dimacs_clause_count(&b) != dimacs_clause_count(&a) { ok = false; }
          if !same_lits(&a, &b) { ok = false; }
          return assert(ok, "round trip: parse, emit and parse again is stable");
        },
        Err(_) => { return assert(false, "round trip: reparse of the emitted text failed"); },
      }
    },
    Err(_) => { return assert(false, "round trip: initial parse failed"); },
  }
  return assert(false, "unreachable");
}

fn t21() -> TestResult {
  var c = dimacs_new(2);
  var cl1 = Vec[Int].new();
  cl1.push(1);
  cl1.push(-2);
  dimacs_add_clause(&mut c, &cl1);
  var cl2 = Vec[Int].new();
  dimacs_add_clause(&mut c, &cl2);
  var cl3 = Vec[Int].new();
  cl3.push(2);
  dimacs_add_clause(&mut c, &cl3);
  var ok = dimacs_var_count(&c) == 2;
  if dimacs_clause_count(&c) != 3 { ok = false; }
  if dimacs_literal_count(&c) != 3 { ok = false; }
  if dimacs_clause_len(&c, 1) != 0 { ok = false; }
  if !clause_lit_is(&c, 0, 0, 1) { ok = false; }
  if !clause_lit_is(&c, 0, 1, -2) { ok = false; }
  if !clause_lit_is(&c, 2, 0, 2) { ok = false; }
  if !streq(dimacs_emit(&c), "p cnf 2 3\n1 -2 0\n0\n2 0\n") { ok = false; }
  return assert(ok, "builders: dimacs_new and dimacs_add_clause feed emit");
}

fn t22() -> TestResult {
  let r = dimacs_parse("p cnf 2 1\n1 0\n");
  match r {
    Ok(c) => {
      var ok = dimacs_clause_start(&c, -1) == -1;
      if dimacs_clause_start(&c, 1) != -1 { ok = false; }
      if dimacs_clause_len(&c, -1) != -1 { ok = false; }
      if dimacs_clause_len(&c, 5) != -1 { ok = false; }
      if dimacs_literal(&c, -1) != 0 { ok = false; }
      if dimacs_literal(&c, 7) != 0 { ok = false; }
      if dimacs_clause_literal(&c, 0, -1) != 0 { ok = false; }
      if dimacs_clause_literal(&c, 0, 7) != 0 { ok = false; }
      if dimacs_clause_literal(&c, 9, 0) != 0 { ok = false; }
      return assert(ok, "accessors: out-of-range indices use the -1 / 0 sentinels");
    },
    Err(_) => { return assert(false, "accessors: out-of-range indices use the -1 / 0 sentinels"); },
  }
  return assert(false, "unreachable");
}

fn t23() -> TestResult {
  let r = dimacs_parse("p cnf 2 3\n1 0 2 0 -1 -2 0\n");
  match r {
    Ok(c) => {
      var ok = dimacs_clause_count(&c) == 3;
      if dimacs_literal_count(&c) != 4 { ok = false; }
      if dimacs_clause_len(&c, 0) != 1 { ok = false; }
      if dimacs_clause_len(&c, 1) != 1 { ok = false; }
      if dimacs_clause_len(&c, 2) != 2 { ok = false; }
      if !clause_lit_is(&c, 2, 0, -1) { ok = false; }
      if !clause_lit_is(&c, 2, 1, -2) { ok = false; }
      return assert(ok, "several clauses may share one line");
    },
    Err(_) => { return assert(false, "several clauses may share one line"); },
  }
  return assert(false, "unreachable");
}

fn t24() -> TestResult {
  var ok = parses_one("   c leading comment\n  p  cnf  1  1\n1 0");
  if !parses_with("p cnf 1 2\n1 0\n-1 0", 2, 2) { ok = false; }
  return assert(ok, "whitespace before markers and a missing final newline are accepted");
}

fn t25() -> TestResult {
  let r = dimacs_parse("p cnf 2 1\n-2 2 0\n");
  match r {
    Ok(c) => {
      var ok = dimacs_literal_count(&c) == 2;
      if !lit_is(&c, 0, -2) { ok = false; }
      if !lit_is(&c, 1, 2) { ok = false; }
      if !parses_with("p cnf 1 1\n-1 0\n", 1, 1) { ok = false; }
      return assert(ok, "literal magnitude equal to vars is the valid boundary");
    },
    Err(_) => { return assert(false, "literal magnitude equal to vars is the valid boundary"); },
  }
  return assert(false, "unreachable");
}

fn main() -> Int {
  io.println("=== xiom.dimacs conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.dimacs: all tests passed");
  } else {
    io.println("xiom.dimacs: tests failed");
  }
  return failed;
}
