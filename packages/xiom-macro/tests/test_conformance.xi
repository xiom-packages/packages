// XIOM -- xiom.macro conformance tests (25 checks)
// Port task: prove the pure-XIOM xiom.macro module against its SPEC.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every comparison
// below is routed through streq / ok_is / err_is instead of `==`, and every
// Vec[Str] element is read into a typed local first.

module macro_tests
use xiom.io; use xiom.test; use xiom.macro;
use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// True when r is Ok and its payload is exactly `want`.
fn ok_is(r: Result[Str, Str], want: Str) -> Bool {
  if !r.is_ok {
    return false;
  }
  return streq(r.value, want);
}

// True when r is Err and its message is exactly `want`.
fn err_is(r: Result[Str, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return streq(r.error, want);
}

// True when r is Ok(Vec) of exactly two names `a`, `b`.
fn names_is2(r: Result[Vec[Str], Str], a: Str, b: Str) -> Bool {
  if !r.is_ok {
    return false;
  }
  let v: Vec[Str] = r.value;
  if v.len() != 2 {
    return false;
  }
  let x: Str = v[0];
  let y: Str = v[1];
  return streq(x, a) && streq(y, b);
}

// True when r (a names result) is Err with message exactly `want`.
fn names_err_is(r: Result[Vec[Str], Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return streq(r.error, want);
}

// Record `i` of the trace equals `want`.
fn trace_at(t: &Vec[Str], i: Int, want: Str) -> Bool {
  if i < 0 || i >= t.len() {
    return false;
  }
  let e: Str = t[i];
  return streq(e, want);
}

// Trace is exactly [a, b, c, d].
fn trace_is4(t: &Vec[Str], a: Str, b: Str, c: Str, d: Str) -> Bool {
  if t.len() != 4 {
    return false;
  }
  return trace_at(t, 0, a) && trace_at(t, 1, b) && trace_at(t, 2, c) && trace_at(t, 3, d);
}

fn t1() -> TestResult {
  let src = "Hello, world!\nSecond line, no macros.\n";
  return assert(ok_is(macro_expand(src), src), "plain text passes through byte-exact");
}

fn t2() -> TestResult {
  return assert(ok_is(macro_expand(""), ""), "empty input expands to empty output");
}

fn t3() -> TestResult {
  let src = "define GREET Hello\n$GREET\n";
  return assert(ok_is(macro_expand(src), "Hello\n"), "define then a zero-arity invocation");
}

fn t4() -> TestResult {
  let src = "define ADD(a,b) $1+$2\n$ADD(a,b)\n";
  return assert(ok_is(macro_expand(src), "a+b\n"), "positional substitution $1..$N");
}

fn t5() -> TestResult {
  let src = "define PAIR(left,right) ($(left),$(right))\n$PAIR(1,2)\n";
  return assert(ok_is(macro_expand(src), "(1,2)\n"), "named substitution $(name)");
}

fn t6() -> TestResult {
  let src = "define B hi\ndefine A <$B>\n$A\n";
  var trace = Vec[Str].new();
  let r = macro_expand_traced(src, &mut trace);
  var ok = ok_is(r, "<hi>\n");
  if !trace_is4(&trace, "define B/0", "define A/0", "expand A/0 depth=1", "expand B/0 depth=2") {
    ok = false;
  }
  return assert(ok, "nested expansion and its trace depths");
}

fn t7() -> TestResult {
  let src = "define X(a) [$1]\n$X( a )$X(b)$X(c)\n";
  return assert(ok_is(macro_expand(src), "[a][b][c]\n"), "multiple calls per line and argument trimming");
}

fn t8() -> TestResult {
  let src = "define X one\n$X\ndefine X two\n$X\n";
  var trace = Vec[Str].new();
  let r = macro_expand_traced(src, &mut trace);
  var ok = ok_is(r, "one\ntwo\n");
  if trace.len() != 4 {
    ok = false;
  }
  if !trace_at(&trace, 1, "expand X/0 depth=1") { ok = false; }
  if !trace_at(&trace, 2, "redefine X/0") { ok = false; }
  return assert(ok, "redefinition wins and is recorded as a redefine");
}

fn t9() -> TestResult {
  let src = "define X a\nundef X\n$X\n";
  return assert(err_is(macro_expand(src), "macro: unknown macro: X"), "undef then invoke is unknown");
}

fn t10() -> TestResult {
  let src = "define F(a) $1\n$F(1,2)\n";
  return assert(err_is(macro_expand(src), "macro: arity mismatch: F expects 1, got 2"), "arity mismatch: too many arguments");
}

fn t11() -> TestResult {
  return assert(err_is(macro_expand("$NOPE(1)\n"), "macro: unknown macro: NOPE"), "unknown macro with parentheses");
}

fn t12() -> TestResult {
  let src = "define F(a) $1\n$F(1\n";
  return assert(err_is(macro_expand(src), "macro: unterminated call: F"), "unterminated call");
}

fn t13() -> TestResult {
  let src = "define A $B\ndefine B $A\n$A\n";
  return assert(err_is(macro_expand(src), "macro: cycle detected: A"), "mutual recursion is detected as a cycle");
}

fn t14() -> TestResult {
  let src = "define A $B\ndefine B $C\ndefine C end\n$A\n";
  var trace = Vec[Str].new();
  let r = macro_expand_with_limit(src, 2, &mut trace);
  return assert(err_is(r, "macro: recursion limit exceeded: C"), "depth limit stops a deep chain");
}

fn t15() -> TestResult {
  var ok = ok_is(macro_expand("define D $$1 \\$x\n$D\n"), "$1 $x\n");
  if !ok_is(macro_expand("cost: \\$5\n"), "cost: $5\n") { ok = false; }
  if !ok_is(macro_expand("a $$ b\n"), "a $ b\n") { ok = false; }
  return assert(ok, "escaped delimiters $$ and \\$ emit one literal $");
}

fn t16() -> TestResult {
  let src = "define ID(p) $1\n$ID($$1)\n";
  return assert(ok_is(macro_expand(src), "$1\n"), "inserted argument text is never re-scanned");
}

fn t17() -> TestResult {
  var ok = ok_is(macro_expand("define Z zero\n$Z()$Z\n"), "zerozero\n");
  if !err_is(macro_expand("define F(a,b) $1$2\n$F\n"), "macro: arity mismatch: F expects 2, got 0") {
    ok = false;
  }
  return assert(ok, "bare and empty-paren invocation arity");
}

fn t18() -> TestResult {
  let src = "define A x\ndefine A y\nundef A\nundef A\n";
  var trace = Vec[Str].new();
  let r = macro_expand_traced(src, &mut trace);
  var ok = ok_is(r, "");
  if !trace_is4(&trace, "define A/0", "redefine A/0", "undef A", "undef-missing A") {
    ok = false;
  }
  return assert(ok, "define / redefine / undef / undef-missing trace records");
}

fn t19() -> TestResult {
  let src = "defined above\nundefine x\nprefix define here\n";
  return assert(ok_is(macro_expand(src), src), "keyword prefixes that are not directives stay text");
}

fn t20() -> TestResult {
  var ok = err_is(macro_expand("define 1x body\n"), "macro: malformed define directive");
  if !err_is(macro_expand("define F(a $1\n"), "macro: malformed define directive") { ok = false; }
  if !err_is(macro_expand("define X"), "macro: malformed define directive") { ok = false; }
  return assert(ok, "malformed define directives");
}

fn t21() -> TestResult {
  return assert(err_is(macro_expand("define F(a,a) $1\n"), "macro: duplicate parameter: a"), "duplicate parameter names");
}

fn t22() -> TestResult {
  var ok = err_is(macro_expand("define F(a) $(b)\n$F(1)\n"), "macro: unknown parameter: b");
  if !err_is(macro_expand("define F(a) $2\n$F(1)\n"), "macro: no such argument: $2") { ok = false; }
  if !err_is(macro_expand("$1\n"), "macro: no such argument: $1") { ok = false; }
  return assert(ok, "unknown parameter and out-of-range positional reference");
}

fn t23() -> TestResult {
  var trace = Vec[Str].new();
  var ok = err_is(macro_expand_with_limit("x\n", 0, &mut trace), "macro: bad depth limit: 0");
  if !err_is(macro_expand_with_limit("x\n", -3, &mut trace), "macro: bad depth limit: -3") { ok = false; }
  if !names_is2(macro_names("define A x\ndefine B y\nplain $A\n"), "A", "B") { ok = false; }
  if !names_err_is(macro_names("define F(a,a) $1\n"), "macro: duplicate parameter: a") { ok = false; }
  return assert(ok, "depth-limit validation and directive-only macro_names");
}

fn t24() -> TestResult {
  let src = "define F(a) $(a\n$F(1)\n";
  return assert(err_is(macro_expand(src), "macro: unterminated parameter reference"), "unterminated $( name reference");
}

fn t25() -> TestResult {
  let src = "define X v\r\n$X\r\n";
  return assert(ok_is(macro_expand(src), "v\r\n"), "CRLF directive lines are consumed, text bytes are kept");
}

fn main() -> Int {
  io.println("=== xiom.macro conformance tests ===");
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
    io.println("xiom.macro: all tests passed");
  } else {
    io.println("xiom.macro: tests failed");
  }
  return failed;
}
