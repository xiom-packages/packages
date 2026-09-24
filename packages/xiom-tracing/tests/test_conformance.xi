// XIOM -- xiom.tracing conformance tests (20 checks)
// Port task: prove the pure-XIOM in-memory span tree against its documented API.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module tracing_tests
use xiom.io; use xiom.test; use xiom.tracing;
use xiom.string.compare;

// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every name check is
// routed through streq instead of `==`.
//
// Read-only operations are wrapped in small helpers that take `&mut`, so a
// `&local` read call is never followed by a `&mut local` call in the same
// function body (advisory E001). Each helper calls the real `&`-based API.

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn count_of(t: &mut SpanTree) -> Int {
  return trace_span_count(t);
}

fn name_of(t: &mut SpanTree, id: Int) -> Str {
  return trace_span_name(t, id);
}

fn parent_of(t: &mut SpanTree, id: Int) -> Int {
  return trace_span_parent(t, id);
}

fn open_at(t: &mut SpanTree, id: Int) -> Bool {
  return trace_is_open(t, id);
}

fn duration_of(t: &mut SpanTree, id: Int) -> Int {
  return trace_duration_ms(t, id);
}

fn depth_of(t: &mut SpanTree, id: Int) -> Int {
  return trace_depth(t, id);
}

fn self_of(t: &mut SpanTree, id: Int) -> Int {
  return trace_self_time_ms(t, id);
}

fn root_duration_of(t: &mut SpanTree) -> Int {
  return trace_root_duration_ms(t);
}

fn children_len(t: &mut SpanTree, id: Int) -> Int {
  let kids = trace_children(t, id);
  return kids.len();
}

fn child_at(t: &mut SpanTree, id: Int, index: Int) -> Int {
  let kids = trace_children(t, id);
  if index < 0 { return -1; }
  if index >= kids.len() { return -1; }
  let value: Int = kids[index];
  return value;
}

fn t1() -> TestResult {
  var t = trace_new();
  var ok = count_of(&mut t) == 0;
  if root_duration_of(&mut t) != 0 { ok = false; }
  if open_at(&mut t, 0) { ok = false; }
  if duration_of(&mut t, 0) != -1 { ok = false; }
  if parent_of(&mut t, 0) != -2 { ok = false; }
  if depth_of(&mut t, 0) != -1 { ok = false; }
  if self_of(&mut t, 0) != -1 { ok = false; }
  if children_len(&mut t, 0) != 0 { ok = false; }
  if !streq(name_of(&mut t, 0), "") { ok = false; }
  return assert(ok, "empty tree reports zeroed defaults for every lookup");
}

fn t2() -> TestResult {
  var t = trace_new();
  let root = trace_start_span(&mut t, -1, "root", 0);
  let child = trace_start_span(&mut t, -1, "child", 5);
  var ok = root == 0;
  if child != 1 { ok = false; }
  if count_of(&mut t) != 2 { ok = false; }
  if !streq(name_of(&mut t, root), "root") { ok = false; }
  if !streq(name_of(&mut t, child), "child") { ok = false; }
  if parent_of(&mut t, root) != -1 { ok = false; }
  if parent_of(&mut t, child) != -1 { ok = false; }
  return assert(ok, "start_span appends and returns sequential ids");
}

fn t3() -> TestResult {
  var t = trace_new();
  let id = trace_start_span(&mut t, -1, "work", 100);
  var ok = open_at(&mut t, id);
  if duration_of(&mut t, id) != -1 { ok = false; }
  let closed = trace_end_span(&mut t, id, 180);
  if !closed { ok = false; }
  if open_at(&mut t, id) { ok = false; }
  if duration_of(&mut t, id) != 80 { ok = false; }
  if root_duration_of(&mut t) != 80 { ok = false; }
  return assert(ok, "end_span closes the span and duration is end - start");
}

fn t4() -> TestResult {
  var t = trace_new();
  let id = trace_start_span(&mut t, -1, "s", 50);
  var ok = !trace_end_span(&mut t, id, 49);
  if !open_at(&mut t, id) { ok = false; }
  if duration_of(&mut t, id) != -1 { ok = false; }
  if !trace_end_span(&mut t, id, 50) { ok = false; }
  if duration_of(&mut t, id) != 0 { ok = false; }
  return assert(ok, "end before start is rejected; end == start gives duration 0");
}

fn t5() -> TestResult {
  var t = trace_new();
  let id = trace_start_span(&mut t, -1, "s", 0);
  var ok = trace_end_span(&mut t, id, 10);
  if trace_end_span(&mut t, id, 20) { ok = false; }
  if duration_of(&mut t, id) != 10 { ok = false; }
  return assert(ok, "second end_span returns false and keeps the duration");
}

fn t6() -> TestResult {
  var t = trace_new();
  let id = trace_start_span(&mut t, -1, "s", 0);
  trace_end_span(&mut t, id, 10);
  var ok = !trace_end_span(&mut t, 7, 20);
  if trace_end_span(&mut t, -1, 20) { ok = false; }
  if open_at(&mut t, 7) { ok = false; }
  if open_at(&mut t, -5) { ok = false; }
  if duration_of(&mut t, 7) != -1 { ok = false; }
  if parent_of(&mut t, 7) != -2 { ok = false; }
  if depth_of(&mut t, 7) != -1 { ok = false; }
  if self_of(&mut t, 7) != -1 { ok = false; }
  if children_len(&mut t, 7) != 0 { ok = false; }
  if !streq(name_of(&mut t, 7), "") { ok = false; }
  if count_of(&mut t) != 1 { ok = false; }
  return assert(ok, "unknown ids report defaults and end_span returns false");
}

fn t7() -> TestResult {
  var t = trace_new();
  let root = trace_start_span(&mut t, -1, "root", 0);
  let c1 = trace_start_span(&mut t, root, "c1", 10);
  let c2 = trace_start_span(&mut t, root, "c2", 20);
  let g = trace_start_span(&mut t, c1, "g", 30);
  var ok = parent_of(&mut t, c1) == root;
  if parent_of(&mut t, c2) != root { ok = false; }
  if parent_of(&mut t, g) != c1 { ok = false; }
  if depth_of(&mut t, c1) != 1 { ok = false; }
  if depth_of(&mut t, g) != 2 { ok = false; }
  return assert(ok, "children link to their parent id");
}

fn t8() -> TestResult {
  var t = trace_new();
  let root = trace_start_span(&mut t, -1, "root", 0);
  let c1 = trace_start_span(&mut t, root, "c1", 10);
  let c2 = trace_start_span(&mut t, root, "c2", 20);
  let c3 = trace_start_span(&mut t, root, "c3", 30);
  trace_end_span(&mut t, c2, 25);
  var ok = children_len(&mut t, root) == 3;
  if child_at(&mut t, root, 0) != c1 { ok = false; }
  if child_at(&mut t, root, 1) != c2 { ok = false; }
  if child_at(&mut t, root, 2) != c3 { ok = false; }
  if child_at(&mut t, root, 3) != -1 { ok = false; }
  return assert(ok, "children are listed in creation order");
}

fn t9() -> TestResult {
  var t = trace_new();
  let root = trace_start_span(&mut t, -1, "root", 0);
  let c1 = trace_start_span(&mut t, root, "c1", 0);
  let g = trace_start_span(&mut t, c1, "g", 0);
  var ok = children_len(&mut t, root) == 1;
  if child_at(&mut t, root, 0) != c1 { ok = false; }
  if children_len(&mut t, c1) != 1 { ok = false; }
  if child_at(&mut t, c1, 0) != g { ok = false; }
  if children_len(&mut t, g) != 0 { ok = false; }
  return assert(ok, "children only include direct children");
}

fn t10() -> TestResult {
  var t = trace_new();
  let root = trace_start_span(&mut t, -1, "r", 0);
  var cur = root;
  var i = 0;
  while i < 40 {
    let next = trace_start_span(&mut t, cur, "n", i);
    cur = next;
    i = i + 1;
  }
  var ok = depth_of(&mut t, root) == 0;
  if depth_of(&mut t, cur) != 40 { ok = false; }
  if depth_of(&mut t, 11) != 11 { ok = false; }
  if depth_of(&mut t, 25) != 25 { ok = false; }
  return assert(ok, "depth counts the ancestor chain");
}

fn t11() -> TestResult {
  var t = trace_new();
  let root = trace_start_span(&mut t, -1, "root", 0);
  let a = trace_start_span(&mut t, root, "a", 10);
  let b = trace_start_span(&mut t, root, "b", 40);
  trace_end_span(&mut t, a, 30);
  trace_end_span(&mut t, b, 60);
  trace_end_span(&mut t, root, 100);
  var ok = duration_of(&mut t, root) == 100;
  if self_of(&mut t, root) != 60 { ok = false; }
  if self_of(&mut t, a) != 20 { ok = false; }
  if self_of(&mut t, b) != 20 { ok = false; }
  return assert(ok, "self time subtracts sequential closed children");
}

fn t12() -> TestResult {
  var t = trace_new();
  let full = trace_start_span(&mut t, -1, "full", 0);
  let a = trace_start_span(&mut t, full, "a", 0);
  let b = trace_start_span(&mut t, full, "b", 50);
  trace_end_span(&mut t, a, 80);
  trace_end_span(&mut t, b, 100);
  trace_end_span(&mut t, full, 100);
  var ok = self_of(&mut t, full) == 0;
  if self_of(&mut t, a) != 80 { ok = false; }
  if self_of(&mut t, b) != 50 { ok = false; }
  var u = trace_new();
  let partial = trace_start_span(&mut u, -1, "partial", 0);
  let ca = trace_start_span(&mut u, partial, "ca", 0);
  let cb = trace_start_span(&mut u, partial, "cb", 40);
  trace_end_span(&mut u, ca, 30);
  trace_end_span(&mut u, cb, 90);
  trace_end_span(&mut u, partial, 100);
  if self_of(&mut u, partial) != 20 { ok = false; }
  return assert(ok, "overlapping children are subtracted and the result clamps at 0");
}

fn t13() -> TestResult {
  var t = trace_new();
  let root = trace_start_span(&mut t, -1, "root", 0);
  let child = trace_start_span(&mut t, root, "open", 10);
  trace_end_span(&mut t, root, 100);
  var ok = self_of(&mut t, root) == 100;
  if self_of(&mut t, child) != -1 { ok = false; }
  if duration_of(&mut t, child) != -1 { ok = false; }
  return assert(ok, "open children are ignored; an open span has no self time");
}

fn t14() -> TestResult {
  var t = trace_new();
  let a = trace_start_span(&mut t, -1, "a", 0);
  let b = trace_start_span(&mut t, -1, "b", 100);
  let c = trace_start_span(&mut t, -1, "c", 0);
  let open_root = trace_start_span(&mut t, -1, "open", 0);
  trace_end_span(&mut t, a, 30);
  trace_end_span(&mut t, b, 250);
  trace_end_span(&mut t, c, 500);
  var ok = root_duration_of(&mut t) == 500;
  trace_end_span(&mut t, open_root, 2000);
  if root_duration_of(&mut t) != 2000 { ok = false; }
  return assert(ok, "root duration is the max closed root duration");
}

fn t15() -> TestResult {
  var t = trace_new();
  let id = trace_start_span(&mut t, -1, "neg", -42);
  var ok = trace_end_span(&mut t, id, 10);
  if duration_of(&mut t, id) != 10 { ok = false; }
  return assert(ok, "negative start_ms is clamped to 0");
}

fn t16() -> TestResult {
  var t = trace_new();
  let root = trace_start_span(&mut t, -1, "root", 0);
  let bad = trace_start_span(&mut t, 99, "bad", 0);
  let neg = trace_start_span(&mut t, -9, "neg", 0);
  let fwd = trace_start_span(&mut t, 42, "fwd", 0);
  var ok = parent_of(&mut t, bad) == -1;
  if parent_of(&mut t, neg) != -1 { ok = false; }
  if parent_of(&mut t, fwd) != -1 { ok = false; }
  if depth_of(&mut t, bad) != 0 { ok = false; }
  if children_len(&mut t, root) != 0 { ok = false; }
  if count_of(&mut t) != 4 { ok = false; }
  return assert(ok, "unknown parents fall back to root (-1)");
}

fn t17() -> TestResult {
  var t = trace_new();
  let r = trace_start_span(&mut t, -1, "r", 0);
  let c = trace_start_span(&mut t, r, "c", 10);
  let g = trace_start_span(&mut t, c, "g", 20);
  trace_end_span(&mut t, g, 30);
  trace_end_span(&mut t, c, 50);
  trace_end_span(&mut t, r, 100);
  var ok = self_of(&mut t, g) == 10;
  if self_of(&mut t, c) != 30 { ok = false; }
  if self_of(&mut t, r) != 60 { ok = false; }
  return assert(ok, "self time only subtracts direct children");
}

fn t18() -> TestResult {
  var t = trace_new();
  let root = trace_start_span(&mut t, -1, "root", 0);
  var i = 0;
  var leaf_ms: Int = 0;
  while i < 49 {
    let start = 100 + i * 100;
    let id = trace_start_span(&mut t, root, "leaf", start);
    trace_end_span(&mut t, id, start + 50);
    leaf_ms = leaf_ms + 50;
    i = i + 1;
  }
  let root_end = 100 + 48 * 100 + 50;
  trace_end_span(&mut t, root, root_end);
  var ok = count_of(&mut t) == 50;
  if children_len(&mut t, root) != 49 { ok = false; }
  if parent_of(&mut t, 49) != root { ok = false; }
  if depth_of(&mut t, 49) != 1 { ok = false; }
  if duration_of(&mut t, root) != root_end { ok = false; }
  if self_of(&mut t, root) != root_end - leaf_ms { ok = false; }
  if root_duration_of(&mut t) != root_end { ok = false; }
  return assert(ok, "50-span tree: links, counts and self time stay consistent");
}

fn t19() -> TestResult {
  var t = trace_new();
  let r = trace_start_span(&mut t, -1, "r", 0);
  trace_end_span(&mut t, r, 10);
  let late = trace_start_span(&mut t, r, "late", 5);
  trace_end_span(&mut t, late, 7);
  var ok = parent_of(&mut t, late) == r;
  if duration_of(&mut t, r) != 10 { ok = false; }
  if self_of(&mut t, r) != 8 { ok = false; }
  return assert(ok, "a child closed after its parent still subtracts its duration");
}

fn t20() -> TestResult {
  var a = trace_new();
  var b = trace_new();
  let ra = trace_start_span(&mut a, -1, "a", 0);
  let rb = trace_start_span(&mut b, -1, "b", 0);
  trace_end_span(&mut a, ra, 10);
  var ok = duration_of(&mut a, ra) == 10;
  if count_of(&mut a) != 1 { ok = false; }
  if count_of(&mut b) != 1 { ok = false; }
  if duration_of(&mut b, rb) != -1 { ok = false; }
  if children_len(&mut a, -1) != 0 { ok = false; }
  if children_len(&mut b, -1) != 0 { ok = false; }
  return assert(ok, "trees are independent; children of a non-span id are empty");
}

fn main() -> Int {
  io.println("=== xiom.tracing conformance tests ===");
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
    io.println("xiom.tracing: all tests passed");
  } else {
    io.println("xiom.tracing: tests failed");
  }
  return failed;
}
