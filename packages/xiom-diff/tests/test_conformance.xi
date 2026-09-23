// XIOM -- xiom.diff conformance tests (16 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module diff_tests
use xiom.io; use xiom.test; use xiom.diff;
use xiom.string;
use xiom.string.compare;

// Str equality goes through str_compare: BUG 17 lowers `==` between Str
// values read from Vec[Str] elements to a pointer comparison. Every xiom.diff
// call below takes `&Vec[Str]`, so the E001 borrow-order warning cannot
// trigger in this file.

fn eq(a: Str, b: Str) -> Bool {
  return str_compare(a, b) == 0;
}

// True when the prefixed script lines, joined with "\n", equal `expected`.
fn lines_is(v: &Vec[Str], expected: Str) -> Bool {
  var joined = "";
  var i = 0;
  while i < v.len() {
    if i > 0 {
      joined = joined + "\n";
    }
    joined = joined + v[i];
    i = i + 1;
  }
  return eq(joined, expected);
}

// True when every line carries one of the "  ", "- ", "+ " prefixes.
fn prefixes_ok(v: &Vec[Str]) -> Bool {
  var i = 0;
  while i < v.len() {
    let p = str_slice(v[i], 0, 2);
    let ok = eq(p, "  ") || eq(p, "- ") || eq(p, "+ ");
    if !ok {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn vec1(a: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  return v;
}

fn vec2(a: Str, b: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  v.push(b);
  return v;
}

fn vec3(a: Str, b: Str, c: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  v.push(b);
  v.push(c);
  return v;
}

fn vec4(a: Str, b: Str, c: Str, d: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  return v;
}

fn vec5(a: Str, b: Str, c: Str, d: Str, e: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  v.push(e);
  return v;
}

fn t1() -> TestResult {
  let a = vec2("a", "b");
  let b = vec2("a", "b");
  let e1 = Vec[Str].new();
  let e2 = Vec[Str].new();
  var ok = diff_equal(&a, &b);
  if !diff_equal(&e1, &e2) { ok = false; }
  return assert(ok, "diff_equal true for identical vectors and empty vectors");
}

fn t2() -> TestResult {
  let a = vec2("a", "b");
  let b = vec2("a", "c");
  let c = vec1("a");
  var ok = !diff_equal(&a, &b);
  if diff_equal(&a, &c) { ok = false; }
  return assert(ok, "diff_equal false on element or length mismatch");
}

fn t3() -> TestResult {
  let a = vec3("A", "B", "C");
  let b = vec4("A", "X", "B", "C");
  let d = diff_lines(&a, &b);
  var ok = lines_is(&d, "  A\n+ X\n  B\n  C");
  if diff_insertions(&a, &b) != 1 { ok = false; }
  if diff_deletions(&a, &b) != 0 { ok = false; }
  if diff_lcs_len(&a, &b) != 3 { ok = false; }
  return assert(ok, "one insertion: script, counts and LCS length");
}

fn t4() -> TestResult {
  let a = vec3("A", "B", "C");
  let b = vec2("A", "C");
  let d = diff_lines(&a, &b);
  var ok = lines_is(&d, "  A\n- B\n  C");
  if diff_insertions(&a, &b) != 0 { ok = false; }
  if diff_deletions(&a, &b) != 1 { ok = false; }
  if diff_lcs_len(&a, &b) != 2 { ok = false; }
  return assert(ok, "one deletion: script, counts and LCS length");
}

fn t5() -> TestResult {
  let a = vec3("A", "B", "C");
  let b = vec3("A", "X", "C");
  let d = diff_lines(&a, &b);
  var ok = lines_is(&d, "  A\n- B\n+ X\n  C");
  if diff_insertions(&a, &b) != 1 { ok = false; }
  if diff_deletions(&a, &b) != 1 { ok = false; }
  if diff_lcs_len(&a, &b) != 2 { ok = false; }
  return assert(ok, "replacement emits deletion before insertion");
}

fn t6() -> TestResult {
  let a = str_split("A\nB\nC\nB\nD\nA\nB", "\n");
  let b = str_split("B\nD\nC\nA\nB\nA", "\n");
  let one = vec1("same");
  let one_b = vec1("same");
  let q = vec1("q");
  let z = vec1("z");
  let e = Vec[Str].new();
  var ok = diff_lcs_len(&a, &b) == 4;
  if diff_lcs_len(&one, &one_b) != 1 { ok = false; }
  if diff_lcs_len(&q, &z) != 0 { ok = false; }
  if diff_lcs_len(&q, &e) != 0 { ok = false; }
  return assert(ok, "LCS known values: 4, 1, 0 and empty");
}

fn t7() -> TestResult {
  let a = vec4("a", "b", "c", "d");
  let b = vec5("a", "x", "c", "y", "e");
  var ok = diff_lcs_len(&a, &b) == 2;
  if diff_insertions(&a, &b) != 3 { ok = false; }
  if diff_deletions(&a, &b) != 2 { ok = false; }
  if diff_insertions(&a, &b) - diff_deletions(&a, &b) != b.len() - a.len() { ok = false; }
  return assert(ok, "insertions and deletions counts on a mixed edit");
}

fn t8() -> TestResult {
  let a = vec3("a", "b", "c");
  let b = vec4("a", "x", "c", "d");
  let d = diff_lines(&a, &b);
  var ok = prefixes_ok(&d);
  if !lines_is(&d, "  a\n- b\n+ x\n  c\n+ d") { ok = false; }
  return assert(ok, "every script line carries exactly one of the three prefixes");
}

fn t9() -> TestResult {
  let a = vec3("A", "B", "C");
  let b = vec3("A", "X", "C");
  let u = diff_unified(&a, &b, 1);
  var ok = eq(u, "@@ -1,3 +1,3 @@\n A\n-B\n+X\n C\n");
  if !str_contains(u, "@@") { ok = false; }
  return assert(ok, "unified hunk has @@ header with correct 1,3 counts");
}

fn t10() -> TestResult {
  let a = vec2("x", "y");
  let b = vec2("x", "y");
  let u = diff_unified(&a, &b, 3);
  let d = diff_lines(&a, &b);
  let dt = diff_text("x\ny", "x\ny");
  var ok = eq(u, "");
  if !lines_is(&d, "  x\n  y") { ok = false; }
  if !lines_is(&dt, "  x\n  y") { ok = false; }
  return assert(ok, "identical inputs produce an empty unified diff");
}

fn t11() -> TestResult {
  let a = str_split("x1\nx2\nx3\nx4\nx5\nx6\nx7", "\n");
  let b = str_split("x1\nx2\nx3\ny4\nx5\nx6\nx7", "\n");
  let u = diff_unified(&a, &b, 1);
  return assert(eq(u, "@@ -3,3 +3,3 @@\n x3\n-x4\n+y4\n x5\n"), "context=1 keeps exactly one unchanged line per side");
}

fn t12() -> TestResult {
  let a = str_split("x1\nx2\nx3\nx4\nx5\nx6\nx7", "\n");
  let b = str_split("x1\nx2\nx3\ny4\nx5\nx6\nx7", "\n");
  let u0 = diff_unified(&a, &b, 0);
  let c = vec4("A", "B", "C", "D");
  let d = vec4("X", "B", "C", "Y");
  let um = diff_unified(&c, &d, 1);
  var ok = eq(u0, "@@ -4,1 +4,1 @@\n-x4\n+y4\n");
  if !eq(um, "@@ -1,4 +1,4 @@\n-A\n+X\n B\n C\n-D\n+Y\n") { ok = false; }
  return assert(ok, "context 0 narrows hunks and nearby changes merge into one hunk");
}

fn t13() -> TestResult {
  let e = Vec[Str].new();
  let x = vec1("x");
  let d1 = diff_lines(&e, &x);
  let d2 = diff_lines(&x, &e);
  var ok = lines_is(&d1, "+ x");
  if !lines_is(&d2, "- x") { ok = false; }
  if !eq(diff_unified(&e, &x, 0), "@@ -0,0 +1,1 @@\n+x\n") { ok = false; }
  if !eq(diff_unified(&x, &e, 0), "@@ -1,1 +0,0 @@\n-x\n") { ok = false; }
  if diff_insertions(&e, &x) != 1 { ok = false; }
  if diff_deletions(&e, &x) != 0 { ok = false; }
  if diff_insertions(&x, &e) != 0 { ok = false; }
  if diff_deletions(&x, &e) != 1 { ok = false; }
  if diff_lcs_len(&e, &x) != 0 { ok = false; }
  return assert(ok, "empty vs non-empty in both directions with 0,0 hunk starts");
}

fn t14() -> TestResult {
  let same = diff_text("a\nb\nc", "a\nb\nc");
  let d = diff_text("a\nb", "a\nc");
  let t = diff_text("a\n", "a\nb");
  let e = diff_text("", "x");
  let both = diff_text("", "");
  var ok = lines_is(&same, "  a\n  b\n  c");
  if !lines_is(&d, "  a\n- b\n+ c") { ok = false; }
  if !lines_is(&t, "  a\n+ b") { ok = false; }
  if !lines_is(&e, "+ x") { ok = false; }
  if both.len() != 0 { ok = false; }
  return assert(ok, "diff_text splits on newlines without a trailing empty line");
}

fn t15() -> TestResult {
  let a = vec1("solo");
  let e = Vec[Str].new();
  let d = diff_lines(&a, &e);
  let dt = diff_text("solo", "");
  var ok = lines_is(&d, "- solo");
  if !lines_is(&dt, "- solo") { ok = false; }
  if !eq(diff_unified(&a, &e, 0), "@@ -1,1 +0,0 @@\n-solo\n") { ok = false; }
  if diff_deletions(&a, &e) != 1 { ok = false; }
  if diff_insertions(&a, &e) != 0 { ok = false; }
  return assert(ok, "single element vs empty deletes exactly that line");
}

fn t16() -> TestResult {
  let a = str_split("A\nB\nC\nD\nE\nF\nG\nH\nI", "\n");
  let b = str_split("A\nX\nC\nD\nE\nF\nY\nH\nI", "\n");
  let u = diff_unified(&a, &b, 1);
  let d = diff_lines(&a, &b);
  var ok = eq(u, "@@ -1,3 +1,3 @@\n A\n-B\n+X\n C\n@@ -6,3 +6,3 @@\n F\n-G\n+Y\n H\n");
  if !prefixes_ok(&d) { ok = false; }
  return assert(ok, "two distant changes yield two separate hunks");
}

fn main() -> Int {
  io.println("=== xiom.diff conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.diff: all tests passed");
  } else {
    io.println("xiom.diff: tests failed");
  }
  return failed;
}
