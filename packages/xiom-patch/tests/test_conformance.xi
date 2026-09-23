// XIOM -- xiom.patch conformance tests (18 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module patch_tests
use xiom.io; use xiom.test; use xiom.patch;
use xiom.string; use xiom.string.compare;

// Vec[Str] elements are compared with str_compare (BUG 17: `==` on Str values
// read from a Vec lowers to a pointer comparison).

fn vec_eq(v: &Vec[Str], want: &Vec[Str]) -> Bool {
  if v.len() != want.len() { return false; }
  var i = 0;
  while i < v.len() {
    let a = v[i];
    let b = want[i];
    if str_compare(a, b) != 0 { return false; }
    i = i + 1;
  }
  return true;
}

fn hdr_is(line: Str, os: Int, oc: Int, ns: Int, nc: Int) -> Bool {
  var ok = false;
  match patch_parse_hunk_header(line) {
    Some((a, b, c, d)) => { ok = a == os && b == oc && c == ns && d == nc; },
    None => {},
  }
  return ok;
}

fn hdr_none(line: Str) -> Bool {
  var none = false;
  match patch_parse_hunk_header(line) {
    Some((_, _, _, _)) => {},
    None => { none = true; },
  }
  return none;
}

fn apply_eq(src: &Vec[Str], p: Str, want: &Vec[Str]) -> Bool {
  var ok = false;
  match patch_apply(src, p) {
    Ok(v) => { ok = vec_eq(&v, want); },
    Err(_) => {},
  }
  return ok;
}

fn apply_err_eq(src: &Vec[Str], p: Str, want: Str) -> Bool {
  var ok = false;
  match patch_apply(src, p) {
    Ok(_) => {},
    Err(e) => { ok = str_compare(e, want) == 0; },
  }
  return ok;
}

fn apply_err_has(src: &Vec[Str], p: Str, needle: Str) -> Bool {
  var ok = false;
  match patch_apply(src, p) {
    Ok(_) => {},
    Err(e) => { ok = str_contains(e, needle); },
  }
  return ok;
}

fn text_eq(src: Str, p: Str, want: Str) -> Bool {
  var ok = false;
  match patch_apply_text(src, p) {
    Ok(s) => { ok = str_compare(s, want) == 0; },
    Err(_) => {},
  }
  return ok;
}

fn t1() -> TestResult {
  var ok = hdr_is("@@ -1,5 +2,6 @@", 1, 5, 2, 6);
  if !hdr_is("@@ -0,0 +1,3 @@", 0, 0, 1, 3) { ok = false; }
  if !hdr_is("@@ -1,5 +2,6", 1, 5, 2, 6) { ok = false; }
  if !hdr_is("@@ -10,1 +10,1 @@ fn main() {", 10, 1, 10, 1) { ok = false; }
  return assert(ok, "hunk header parses with explicit counts");
}

fn t2() -> TestResult {
  var ok = hdr_is("@@ -3 +7 @@", 3, 1, 7, 1);
  if !hdr_is("@@ -3,2 +7 @@", 3, 2, 7, 1) { ok = false; }
  if !hdr_is("@@ -3 +7,4 @@", 3, 1, 7, 4) { ok = false; }
  return assert(ok, "missing ,count defaults to 1");
}

fn t3() -> TestResult {
  var ok = hdr_none("@@ 1,5 +2,6 @@");
  if !hdr_none("@@ -1,5 2,6 @@") { ok = false; }
  if !hdr_none("@@ -x +1 @@") { ok = false; }
  if !hdr_none("@@ -1 + @@") { ok = false; }
  if !hdr_none("@@ -1,5 +2,6 junk") { ok = false; }
  if !hdr_none("not a header") { ok = false; }
  if !hdr_none("") { ok = false; }
  return assert(ok, "malformed headers yield None");
}

fn t4() -> TestResult {
  let text = "@@ -1,1 +1,1 @@\n-a\n+b\n@@ -3,1 +3,1 @@\n-c\n+d\n";
  var ok = patch_count_hunks(text) == 2;
  if patch_count_hunks("") != 0 { ok = false; }
  if patch_count_hunks("x@@ -1 +1 @@\n") != 0 { ok = false; }
  if patch_count_hunks("@@ -1 +1 @@\n") != 1 { ok = false; }
  return assert(ok, "count_hunks counts @@ header lines");
}

fn t5() -> TestResult {
  let text = "--- a/file.txt\n+++ b/file.txt\n@@ -1,3 +1,3 @@\n keep\n-old one\n+new one\n-gone\n+added\n";
  let got = patch_extract_removed(text);
  var want = Vec[Str].new();
  want.push("old one");
  want.push("gone");
  return assert(vec_eq(&got, &want), "extract_removed strips '-' and skips --- headers");
}

fn t6() -> TestResult {
  let text = "--- a/file.txt\n+++ b/file.txt\n@@ -1,3 +1,3 @@\n keep\n-old one\n+new one\n-gone\n+added\n";
  let got = patch_extract_added(text);
  var want = Vec[Str].new();
  want.push("new one");
  want.push("added");
  return assert(vec_eq(&got, &want), "extract_added strips '+' and skips +++ headers");
}

fn t7() -> TestResult {
  var src = Vec[Str].new();
  src.push("a");
  src.push("b");
  var want = Vec[Str].new();
  want.push("first");
  want.push("a");
  want.push("b");
  return assert(apply_eq(&src, "@@ -0,0 +1,1 @@\n+first\n", &want), "apply inserts a line at the start");
}

fn t8() -> TestResult {
  var src = Vec[Str].new();
  src.push("a");
  src.push("b");
  src.push("c");
  var want = Vec[Str].new();
  want.push("a");
  want.push("c");
  return assert(apply_eq(&src, "@@ -2,1 +1,0 @@\n-b\n", &want), "apply deletes a middle line");
}

fn t9() -> TestResult {
  var src = Vec[Str].new();
  src.push("a");
  src.push("b");
  src.push("c");
  var want = Vec[Str].new();
  want.push("a");
  want.push("B");
  want.push("c");
  return assert(apply_eq(&src, "@@ -2,1 +2,1 @@\n-b\n+B\n", &want), "apply replaces a line");
}

fn t10() -> TestResult {
  var src = Vec[Str].new();
  src.push("a");
  src.push("b");
  src.push("c");
  src.push("d");
  var want = Vec[Str].new();
  want.push("a");
  want.push("inserted");
  want.push("b");
  want.push("C");
  want.push("d");
  let p = "@@ -1,1 +1,2 @@\n a\n+inserted\n@@ -3,1 +4,1 @@\n-c\n+C\n";
  return assert(apply_eq(&src, p, &want), "apply processes hunks in order across a shift");
}

fn t11() -> TestResult {
  var src = Vec[Str].new();
  src.push("x");
  src.push("y");
  src.push("z");
  let p = "@@ -1,2 +1,2 @@\n a\n-b\n+B\n";
  var ok = apply_err_has(&src, p, "patch: hunk");
  if !apply_err_eq(&src, p, "patch: hunk 1 failed to apply at line 1") { ok = false; }
  return assert(ok, "context mismatch fails with a patch: hunk error");
}

fn t12() -> TestResult {
  var src = Vec[Str].new();
  src.push("a");
  let p = "@@ -1,x +1,1 @@\n-a\n+A\n";
  return assert(apply_err_eq(&src, p, "patch: malformed hunk header"), "malformed header fails with a specific error");
}

fn t13() -> TestResult {
  var src = Vec[Str].new();
  src.push("a");
  src.push("b");
  var ok = apply_eq(&src, "", &src);
  if !apply_eq(&src, "\n", &src) { ok = false; }
  if !apply_eq(&src, "just a note, no hunks\n", &src) { ok = false; }
  return assert(ok, "empty or hunk-less patch returns the source unchanged");
}

fn t14() -> TestResult {
  var ok = text_eq("a\nb\nc", "@@ -2,1 +2,1 @@\n-b\n+B\n", "a\nB\nc");
  if !text_eq("a\nb\n", "@@ -1,1 +1,1 @@\n-a\n+A\n", "A\nb\n") { ok = false; }
  if !text_eq("a\nb", "", "a\nb") { ok = false; }
  return assert(ok, "apply_text splits on newline and joins back");
}

fn t15() -> TestResult {
  var src = Vec[Str].new();
  src.push("a");
  let p = "@@ -4,3 +4,3 @@\n x\n-y\n+z\n";
  return assert(apply_err_eq(&src, p, "patch: hunk 1 failed to apply at line 4"), "source shorter than the hunk fails");
}

fn t16() -> TestResult {
  var src = Vec[Str].new();
  src.push("zero");
  src.push("a");
  src.push("b");
  src.push("c");
  src.push("d");
  var want = Vec[Str].new();
  want.push("zero");
  want.push("a");
  want.push("B");
  want.push("c");
  want.push("d");
  let p = "@@ -1,2 +1,2 @@\n a\n-b\n+B\n";
  return assert(apply_eq(&src, p, &want), "fuzz relocates a hunk within +-20 lines");
}

fn t17() -> TestResult {
  var src = Vec[Str].new();
  var i = 0;
  while i < 25 {
    src.push("x" + int_to_string(i));
    i = i + 1;
  }
  src.push("a");
  src.push("b");
  let p = "@@ -1,2 +1,2 @@\n a\n-b\n+B\n";
  return assert(apply_err_has(&src, p, "patch: hunk"), "mismatch beyond the fuzz window fails");
}

fn t18() -> TestResult {
  var src = Vec[Str].new();
  src.push("a");
  src.push("b");
  src.push("c");
  var want = Vec[Str].new();
  want.push("a");
  want.push("X");
  want.push("b");
  want.push("c");
  return assert(apply_eq(&src, "@@ -1,0 +2,1 @@\n+X\n", &want), "zero-count insertion anchors after oldStart");
}

fn main() -> Int {
  io.println("=== xiom.patch conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.patch: all tests passed");
  } else {
    io.println("xiom.patch: tests failed");
  }
  return failed;
}
