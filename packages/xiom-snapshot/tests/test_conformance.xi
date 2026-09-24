// XIOM -- xiom.snapshot conformance tests (20 checks)
// Port task: prove line splitting, normalization, equality and
// first-difference summaries against pinned expected values.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module snapshot_tests
use xiom.io; use xiom.test; use xiom.snapshot;
use xiom.string.compare;

// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every element check
// below is routed through eq/line_is instead of `==`.

fn eq(a: Str, b: Str) -> Bool {
  return str_compare(a, b) == 0;
}

fn line_is(v: &Vec[Str], i: Int, want: Str) -> Bool {
  if i < 0 || i >= v.len() { return false; }
  return eq(v[i], want);
}

fn t1() -> TestResult {
  let v = snapshot_lines("a\nb\nc");
  var ok = v.len() == 3;
  if !line_is(&v, 0, "a") { ok = false; }
  if !line_is(&v, 1, "b") { ok = false; }
  if !line_is(&v, 2, "c") { ok = false; }
  return assert(ok, "split LF text into one entry per line");
}

fn t2() -> TestResult {
  let one = snapshot_lines("a\n");
  let empty = snapshot_lines("");
  let blank = snapshot_lines("\n");
  let two = snapshot_lines("a\n\n");
  var ok = one.len() == 1;
  if !line_is(&one, 0, "a") { ok = false; }
  if empty.len() != 0 { ok = false; }
  if blank.len() != 1 { ok = false; }
  if !line_is(&blank, 0, "") { ok = false; }
  if two.len() != 2 { ok = false; }
  if !line_is(&two, 1, "") { ok = false; }
  return assert(ok, "trailing newline adds no line; empty text is zero lines");
}

fn t3() -> TestResult {
  let crlf = snapshot_lines("a\r\nb\r\n");
  let mixed = snapshot_lines("a\r\nb");
  let lone = snapshot_lines("x\r");
  var ok = crlf.len() == 2;
  if !line_is(&crlf, 0, "a") { ok = false; }
  if !line_is(&crlf, 1, "b") { ok = false; }
  if mixed.len() != 2 { ok = false; }
  if !line_is(&mixed, 1, "b") { ok = false; }
  if lone.len() != 1 { ok = false; }
  if !line_is(&lone, 0, "x") { ok = false; }
  return assert(ok, "CRLF and a final lone CR are stripped from lines");
}

fn t4() -> TestResult {
  let v = snapshot_lines("a\n\nb");
  var ok = v.len() == 3;
  if !line_is(&v, 1, "") { ok = false; }
  if !line_is(&v, 2, "b") { ok = false; }
  let keep = snapshot_lines("a\rb");
  if keep.len() != 1 { ok = false; }
  if !line_is(&keep, 0, "a\rb") { ok = false; }
  return assert(ok, "interior blank lines and interior CR bytes survive splitting");
}

fn t5() -> TestResult {
  let n = snapshot_normalized("a\r\nb\r\n", false);
  var ok = eq(n, "a\nb");
  if !eq(snapshot_normalized("a\r\n", false), "a") { ok = false; }
  if !eq(snapshot_normalized("", false), "") { ok = false; }
  return assert(ok, "normalization rewrites CRLF to LF without a trailing newline");
}

fn t6() -> TestResult {
  let trimmed = snapshot_normalized("a  \nb\t\n", true);
  let kept = snapshot_normalized("a  \nb\t\n", false);
  var ok = eq(trimmed, "a\nb");
  if !eq(kept, "a  \nb\t") { ok = false; }
  return assert(ok, "trailing space/tab trim is optional and per line");
}

fn t7() -> TestResult {
  var ok = eq(snapshot_normalized("a\n\n\n", true), "a");
  if !eq(snapshot_normalized("\n\n", true), "") { ok = false; }
  if !eq(snapshot_normalized("a\n", true), "a") { ok = false; }
  if !eq(snapshot_normalized("a\n\nb\n\n", true), "a\n\nb") { ok = false; }
  return assert(ok, "trailing blank lines are dropped, interior ones are kept");
}

fn t8() -> TestResult {
  let v = snapshot_lines(snapshot_normalized("a\n  \nb\n \n", true));
  var ok = v.len() == 3;
  if !line_is(&v, 0, "a") { ok = false; }
  if !line_is(&v, 1, "") { ok = false; }
  if !line_is(&v, 2, "b") { ok = false; }
  return assert(ok, "normalization does not alter interior blank lines");
}

fn t9() -> TestResult {
  var ok = snapshot_equal("a\r\nb", "a\nb", false);
  if !snapshot_equal("a  \nb", "a\nb", true) { ok = false; }
  if !snapshot_equal("a\n\n", "a", true) { ok = false; }
  if !snapshot_equal("", "", true) { ok = false; }
  return assert(ok, "equal after CRLF/newline/blank-tail normalization");
}

fn t10() -> TestResult {
  var ok = !snapshot_equal("a  \nb", "a\nb", false);
  if snapshot_equal("a\nb", "a\nc", true) { ok = false; }
  if snapshot_equal("a", "a\nb", true) { ok = false; }
  if snapshot_equal("", "x", true) { ok = false; }
  return assert(ok, "not equal on whitespace, content or length mismatch");
}

fn t11() -> TestResult {
  var ok = snapshot_first_diff_line("x\ny", "z\ny", true) == 1;
  if snapshot_first_diff_line("a\r\nb", "a\nx", true) != 2 { ok = false; }
  return assert(ok, "first difference at line 1 and after a CRLF-only first line");
}

fn t12() -> TestResult {
  let a = "a\nb\nc\nd";
  let b = "a\nb\nx\nd";
  var ok = snapshot_first_diff_line(a, b, true) == 3;
  if snapshot_first_diff_line(a, "a\nb\nc\ny", true) != 4 { ok = false; }
  return assert(ok, "first difference in the middle and at the last line");
}

fn t13() -> TestResult {
  var ok = snapshot_first_diff_line("a\nb\nc", "a\nb\nc", true) == -1;
  if snapshot_first_diff_line("", "", true) != -1 { ok = false; }
  if snapshot_first_diff_line("a\n", "a", true) != -1 { ok = false; }
  return assert(ok, "equal texts report -1, including trailing-newline variants");
}

fn t14() -> TestResult {
  var ok = snapshot_first_diff_line("a", "a\nb", true) == 2;
  if snapshot_first_diff_line("a\nb", "a", true) != 2 { ok = false; }
  if snapshot_first_diff_line("", "x", true) != 1 { ok = false; }
  if snapshot_first_diff_line("x", "", true) != 1 { ok = false; }
  return assert(ok, "a missing line on either side counts as a difference");
}

fn t15() -> TestResult {
  var ok = eq(snapshot_diff_summary("a\nb", "a\nb", true), "equal");
  if !eq(snapshot_diff_summary("a\r\nb\r\n", "a\nb", true), "equal") { ok = false; }
  if !eq(snapshot_diff_summary("", "\n\n", true), "equal") { ok = false; }
  return assert(ok, "summary is the bare word equal for matching texts");
}

fn t16() -> TestResult {
  let s = snapshot_diff_summary("alpha\nbeta\ngamma", "alpha\ndelta\ngamma", true);
  return assert(eq(s, "1 line(s) differ; first at line 2\n  expected: beta\n  actual:   delta"), "single-line summary pins count, position and both sides");
}

fn t17() -> TestResult {
  let multi = snapshot_diff_summary("a\nb\nc", "a\nx\ny", true);
  var ok = eq(multi, "2 line(s) differ; first at line 2\n  expected: b\n  actual:   x");
  let missing_b = snapshot_diff_summary("a\nb\nc", "a", true);
  if !eq(missing_b, "2 line(s) differ; first at line 2\n  expected: b\n  actual:   <missing>") { ok = false; }
  let missing_a = snapshot_diff_summary("a", "a\nb\nc", true);
  if !eq(missing_a, "2 line(s) differ; first at line 2\n  expected: <missing>\n  actual:   b") { ok = false; }
  return assert(ok, "summary counts every differing position and marks missing lines");
}

fn t18() -> TestResult {
  var ok = snapshot_is_clean("a \nb\n", "a\nb");
  if snapshot_is_clean("a\nb", "a\nc") { ok = false; }
  if !snapshot_is_clean("x", "x\n\n\n") { ok = false; }
  if snapshot_is_clean("", "x") { ok = false; }
  return assert(ok, "clean wrapper equals with default trailing-ws trim");
}

fn t19() -> TestResult {
  let n = snapshot_normalized("héllo\r\nwörld\r\n", true);
  var ok = eq(n, "héllo\nwörld");
  if n.len() != 13 { ok = false; }
  let v = snapshot_lines("αβ\nγ");
  if v.len() != 2 { ok = false; }
  if !line_is(&v, 0, "αβ") { ok = false; }
  if !line_is(&v, 1, "γ") { ok = false; }
  return assert(ok, "non-ASCII UTF-8 bytes pass through unchanged");
}

fn t20() -> TestResult {
  let e = snapshot_lines("");
  let n = snapshot_normalized("", true);
  var ok = e.len() == 0;
  if !eq(n, "") { ok = false; }
  if !snapshot_equal("", "", true) { ok = false; }
  if snapshot_equal("", "x", true) { ok = false; }
  if snapshot_first_diff_line("", "") != -1 { ok = false; }
  if snapshot_first_diff_line("", "x", true) != 1 { ok = false; }
  let s = snapshot_diff_summary("", "x", true);
  if !eq(s, "1 line(s) differ; first at line 1\n  expected: <missing>\n  actual:   x") { ok = false; }
  return assert(ok, "empty vs empty and empty vs non-empty in every entry point");
}

fn main() -> Int {
  io.println("=== xiom.snapshot conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.snapshot: all tests passed");
  } else {
    io.println("xiom.snapshot: tests failed");
  }
  return failed;
}
