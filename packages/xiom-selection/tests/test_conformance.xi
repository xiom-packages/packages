// XIOM -- xiom.selection conformance tests (25 checks)
// Port task: prove the pure-XIOM xiom.selection operators against its SPEC.md.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Coverage: weight summing with negatives, the roulette core (boundaries,
// out-of-range and degenerate draws), seeded roulette determinism and pinned
// bucket draws, tournament determinism / clamping / tie rule, elite ordering
// and clamps, best/worst ties, rank weights, and 100-element determinism.
//
// Every PRNG-dependent expectation below is pinned from the documented recipe
// (SPEC.md section 3) and cross-checked against an independent simulator; the
// values are deterministic inputs/outputs, not tunable thresholds. All Vec
// element reads use an explicitly typed `let x: Int = v[i];`.

module selection_tests
use xiom.io; use xiom.test; use xiom.selection;

// --- helpers ----------------------------------------------------------------

fn ints_eq(a: &Vec[Int], b: &Vec[Int]) -> Bool {
  if a.len() != b.len() { return false; }
  var i = 0;
  while i < a.len() {
    let av: Int = a[i];
    let bv: Int = b[i];
    if av != bv { return false; }
    i = i + 1;
  }
  return true;
}

fn ints1(a: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  return v;
}

fn ints2(a: Int, b: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  return v;
}

fn ints3(a: Int, b: Int, c: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  return v;
}

fn ints4(a: Int, b: Int, c: Int, d: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  return v;
}

fn is_permutation(v: &Vec[Int], n: Int) -> Bool {
  if v.len() != n { return false; }
  var seen = Vec[Int].new();
  var i = 0;
  while i < n {
    seen.push(0);
    i = i + 1;
  }
  var k = 0;
  while k < n {
    let x: Int = v[k];
    if x < 0 || x >= n { return false; }
    let flag: Int = seen[x];
    if flag != 0 { return false; }
    seen[x] = 1;
    k = k + 1;
  }
  return true;
}

fn elite_sorted_ok(fitness: &Vec[Int], order: &Vec[Int]) -> Bool {
  var i = 0;
  while i + 1 < order.len() {
    let a: Int = order[i];
    let b: Int = order[i + 1];
    let fa: Int = fitness[a];
    let fb: Int = fitness[b];
    if fa < fb { return false; }
    if fa == fb && a > b { return false; }
    i = i + 1;
  }
  return true;
}

fn hundred_fitness() -> Vec[Int] {
  var f = Vec[Int].new();
  var i = 0;
  while i < 100 {
    f.push((i * 37) % 101 - 50);
    i = i + 1;
  }
  return f;
}

// --- sel_sum ----------------------------------------------------------------

fn t1() -> TestResult {
  var empty = Vec[Int].new();
  var a = ints3(1, 2, 3);
  var b = ints3(5, -2, 3);
  var c = ints2(-1, -2);
  var z = ints2(0, 0);
  var ok = sel_sum(&empty) == 0;
  if sel_sum(&a) != 6 { ok = false; }
  if sel_sum(&b) != 8 { ok = false; }
  if sel_sum(&c) != 0 { ok = false; }
  if sel_sum(&z) != 0 { ok = false; }
  return assert(ok, "sum: empty 0, positives add, negatives count as 0");
}

fn t2() -> TestResult {
  var one = ints1(7);
  var big = ints2(1000000, 234567);
  var neg = ints1(-5);
  var ok = sel_sum(&one) == 7;
  if sel_sum(&big) != 1234567 { ok = false; }
  if sel_sum(&neg) != 0 { ok = false; }
  return assert(ok, "sum: single, large and all-negative vectors");
}

// --- sel_roulette_index -----------------------------------------------------

fn t3() -> TestResult {
  var w = ints3(3, 5, 2);
  var ok = sel_roulette_index(&w, 0) == 0;
  if sel_roulette_index(&w, 2) != 0 { ok = false; }
  if sel_roulette_index(&w, 3) != 1 { ok = false; }
  if sel_roulette_index(&w, 7) != 1 { ok = false; }
  if sel_roulette_index(&w, 8) != 2 { ok = false; }
  if sel_roulette_index(&w, 9) != 2 { ok = false; }
  return assert(ok, "roulette_index: draw at every bucket and cumulative edge");
}

fn t4() -> TestResult {
  var w = ints3(3, 5, 2);
  var ok = sel_roulette_index(&w, 10) == -1;
  if sel_roulette_index(&w, 11) != -1 { ok = false; }
  if sel_roulette_index(&w, 999) != -1 { ok = false; }
  if sel_roulette_index(&w, -1) != -1 { ok = false; }
  if sel_roulette_index(&w, -999) != -1 { ok = false; }
  return assert(ok, "roulette_index: draw at or beyond total, or negative, is -1");
}

fn t5() -> TestResult {
  var empty = Vec[Int].new();
  var zeros = ints3(0, 0, 0);
  var mixed = ints4(-4, 3, -1, 2);
  var ok = sel_roulette_index(&empty, 0) == -1;
  if sel_roulette_index(&zeros, 0) != -1 { ok = false; }
  if sel_roulette_index(&mixed, 0) != 1 { ok = false; }
  if sel_roulette_index(&mixed, 1) != 1 { ok = false; }
  if sel_roulette_index(&mixed, 2) != 1 { ok = false; }
  if sel_roulette_index(&mixed, 3) != 3 { ok = false; }
  if sel_roulette_index(&mixed, 4) != 3 { ok = false; }
  if sel_roulette_index(&mixed, 5) != -1 { ok = false; }
  return assert(ok, "roulette_index: empty/all-zero -1; negative entries skipped");
}

// --- sel_roulette -----------------------------------------------------------

fn t6() -> TestResult {
  var w = ints3(5, 3, 2);
  var want = Vec[Int].new();
  want.push(0); want.push(1); want.push(0); want.push(1); want.push(0);
  want.push(1); want.push(0); want.push(1); want.push(0); want.push(0);
  var ok = true;
  var s = 0;
  while s < 10 {
    let a = sel_roulette(&w, s);
    let b = sel_roulette(&w, s);
    if a != b { ok = false; }
    let at: Int = want[s];
    if a != at { ok = false; }
    s = s + 1;
  }
  let n1 = sel_roulette(&w, -7);
  let n2 = sel_roulette(&w, -7);
  if n1 != n2 { ok = false; }
  return assert(ok, "roulette: same seed same bucket (pinned), negative seed stable");
}

fn t7() -> TestResult {
  var w = ints3(1, 1, 1);
  var ok = sel_roulette(&w, 0) == 0;
  if sel_roulette(&w, 1) != 2 { ok = false; }
  return assert(ok, "roulette: pinned first and last bucket draws");
}

fn t8() -> TestResult {
  var w = ints3(1, 1, 1);
  var c0 = 0; var c1 = 0; var c2 = 0;
  var i = 0;
  while i < 100 {
    let idx = sel_roulette(&w, i);
    if idx == 0 { c0 = c0 + 1; }
    if idx == 1 { c1 = c1 + 1; }
    if idx == 2 { c2 = c2 + 1; }
    if idx < 0 || idx > 2 { c0 = -1000; }
    i = i + 1;
  }
  var ok = c0 == 30 && c1 == 26 && c2 == 44;
  var wide = ints3(5, 3, 2);
  var j = 0;
  while j < 100 {
    let idx = sel_roulette(&wide, j);
    if idx < 0 || idx > 2 { ok = false; }
    j = j + 1;
  }
  return assert(ok, "roulette: pinned 100-seed bucket histogram and range");
}

fn t9() -> TestResult {
  var empty = Vec[Int].new();
  var zeros = ints2(0, 0);
  var negs = ints2(-3, -1);
  var ok = sel_roulette(&empty, 42) == -1;
  if sel_roulette(&zeros, 7) != -1 { ok = false; }
  if sel_roulette(&negs, 5) != -1 { ok = false; }
  return assert(ok, "roulette: empty and all-nonpositive vectors yield -1");
}

// --- sel_tournament_index ---------------------------------------------------

fn t10() -> TestResult {
  var f = Vec[Int].new();
  f.push(10); f.push(20); f.push(30); f.push(40); f.push(50);
  var ok = sel_tournament_index(&f, 2, 12345) == sel_tournament_index(&f, 2, 12345);
  var s = 0;
  while s < 5 {
    let a = sel_tournament_index(&f, 3, s);
    let b = sel_tournament_index(&f, 3, s);
    if a != b { ok = false; }
    if a < 0 || a >= 5 { ok = false; }
    s = s + 1;
  }
  return assert(ok, "tournament: same seed same winner, result in range");
}

fn t11() -> TestResult {
  var f = Vec[Int].new();
  f.push(10); f.push(20); f.push(30); f.push(40); f.push(50);
  var ok = sel_tournament_index(&f, 0, 12345) == 0;
  if sel_tournament_index(&f, 1, 12345) != 0 { ok = false; }
  if sel_tournament_index(&f, 2, 12345) != 4 { ok = false; }
  if sel_tournament_index(&f, 5, 12345) != 4 { ok = false; }
  if sel_tournament_index(&f, 99, 12345) != 4 { ok = false; }
  if sel_tournament_index(&f, -7, 12345) != 0 { ok = false; }
  return assert(ok, "tournament: pinned winners across k variants");
}

fn t12() -> TestResult {
  var f = hundred_fitness();
  var ok = sel_tournament_index(&f, 10, 5) == 65;
  let full = sel_tournament_index(&f, 100, 5);
  let over = sel_tournament_index(&f, 500, 5);
  let huge = sel_tournament_index(&f, 1000, 5);
  if full != 30 { ok = false; }
  if over != full { ok = false; }
  if huge != full { ok = false; }
  return assert(ok, "tournament: pinned 100-element winners and k clamp to len");
}

fn t13() -> TestResult {
  var four = Vec[Int].new();
  four.push(7); four.push(7); four.push(7); four.push(7);
  var ties = ints4(3, 1, 3, 1);
  var ok = sel_tournament_index(&four, 3, 99) == 0;
  if sel_tournament_index(&four, 4, 99) != 0 { ok = false; }
  if sel_tournament_index(&ties, 4, 7) != 2 { ok = false; }
  return assert(ok, "tournament: equal fitness keeps the earliest sampled index");
}

fn t14() -> TestResult {
  var empty = Vec[Int].new();
  var one = ints1(42);
  var ok = sel_tournament_index(&empty, 5, 1) == -1;
  if sel_tournament_index(&empty, 0, 1) != -1 { ok = false; }
  if sel_tournament_index(&one, 5, 1) != 0 { ok = false; }
  if sel_tournament_index(&one, -3, 1) != 0 { ok = false; }
  return assert(ok, "tournament: empty -1; single-element vector returns 0");
}

fn t15() -> TestResult {
  var f = Vec[Int].new();
  f.push(1); f.push(2); f.push(3); f.push(2); f.push(1);
  var g = Vec[Int].new();
  g.push(10); g.push(20); g.push(30); g.push(40); g.push(50);
  var ok = sel_tournament_index(&f, 5, 3) == 2;
  if sel_tournament_index(&g, 5, 12345) != 4 { ok = false; }
  return assert(ok, "tournament: pinned picks favour the highest fitness");
}

// --- sel_elite_indices ------------------------------------------------------

fn t16() -> TestResult {
  var f = ints4(5, 1, 5, 3);
  let e1 = sel_elite_indices(&f, 1);
  let e2 = sel_elite_indices(&f, 2);
  let e3 = sel_elite_indices(&f, 3);
  let e4 = sel_elite_indices(&f, 4);
  let e9 = sel_elite_indices(&f, 9);
  let w1 = ints1(0);
  let w2 = ints2(0, 2);
  let w3 = ints3(0, 2, 3);
  let w4 = ints4(0, 2, 3, 1);
  var ok = ints_eq(&e1, &w1);
  if !ints_eq(&e2, &w2) { ok = false; }
  if !ints_eq(&e3, &w3) { ok = false; }
  if !ints_eq(&e4, &w4) { ok = false; }
  if !ints_eq(&e9, &w4) { ok = false; }
  if !elite_sorted_ok(&f, &e4) { ok = false; }
  return assert(ok, "elite: top-k order by fitness desc, ties earlier index");
}

fn t17() -> TestResult {
  var f = ints4(5, 1, 5, 3);
  var empty = Vec[Int].new();
  let z0 = sel_elite_indices(&f, 0);
  let zn = sel_elite_indices(&f, -2);
  let ze = sel_elite_indices(&empty, 3);
  var ok = z0.len() == 0;
  if zn.len() != 0 { ok = false; }
  if ze.len() != 0 { ok = false; }
  return assert(ok, "elite: k <= 0 or empty population yields an empty vector");
}

fn t18() -> TestResult {
  var flat = ints3(4, 4, 4);
  var mixed = ints4(2, 1, 2, 1);
  var neg = ints3(-5, -5, -1);
  let a = sel_elite_indices(&flat, 3);
  let b = sel_elite_indices(&mixed, 4);
  let c = sel_elite_indices(&neg, 3);
  let wa = ints3(0, 1, 2);
  let wb = ints4(0, 2, 1, 3);
  let wc = ints3(2, 0, 1);
  var ok = ints_eq(&a, &wa);
  if !ints_eq(&b, &wb) { ok = false; }
  if !ints_eq(&c, &wc) { ok = false; }
  if !elite_sorted_ok(&mixed, &b) { ok = false; }
  return assert(ok, "elite: tie stability keeps ascending index order");
}

// --- sel_best_index / sel_worst_index ---------------------------------------

fn t19() -> TestResult {
  var a = ints4(4, 9, 9, 2);
  var flat = ints3(3, 3, 3);
  var neg = ints3(-5, -5, -1);
  var one = ints1(7);
  var ok = sel_best_index(&a) == 1;
  if sel_worst_index(&a) != 3 { ok = false; }
  if sel_best_index(&flat) != 0 { ok = false; }
  if sel_worst_index(&flat) != 0 { ok = false; }
  if sel_best_index(&neg) != 2 { ok = false; }
  if sel_worst_index(&neg) != 0 { ok = false; }
  if sel_best_index(&one) != 0 { ok = false; }
  if sel_worst_index(&one) != 0 { ok = false; }
  return assert(ok, "best/worst: ties resolve to the first occurrence");
}

fn t20() -> TestResult {
  var empty = Vec[Int].new();
  var ok = sel_best_index(&empty) == -1;
  if sel_worst_index(&empty) != -1 { ok = false; }
  return assert(ok, "best/worst: empty vector yields -1");
}

// --- sel_rank_weights -------------------------------------------------------

fn t21() -> TestResult {
  let z = sel_rank_weights(0);
  let neg = sel_rank_weights(-3);
  let one = sel_rank_weights(1);
  let five = sel_rank_weights(5);
  let two = sel_rank_weights(2);
  let w1 = ints1(1);
  let w5 = Vec[Int].new();
  w5.push(5); w5.push(4); w5.push(3); w5.push(2); w5.push(1);
  let w2 = ints2(2, 1);
  var ok = z.len() == 0;
  if neg.len() != 0 { ok = false; }
  if !ints_eq(&one, &w1) { ok = false; }
  if !ints_eq(&five, &w5) { ok = false; }
  if !ints_eq(&two, &w2) { ok = false; }
  return assert(ok, "rank weights: [n, n-1, ..., 1]; n < 1 empty");
}

// --- 100-element determinism ------------------------------------------------

fn t22() -> TestResult {
  var f = hundred_fitness();
  let top5 = sel_elite_indices(&f, 5);
  let full = sel_elite_indices(&f, 100);
  let none = sel_elite_indices(&f, 0);
  let w5 = Vec[Int].new();
  w5.push(30); w5.push(60); w5.push(90); w5.push(19); w5.push(49);
  var head = Vec[Int].new();
  var i = 0;
  while i < 5 {
    let x: Int = full[i];
    head.push(x);
    i = i + 1;
  }
  var ok = ints_eq(&top5, &w5);
  if !is_permutation(&full, 100) { ok = false; }
  if !elite_sorted_ok(&f, &full) { ok = false; }
  if !ints_eq(&head, &top5) { ok = false; }
  if none.len() != 0 { ok = false; }
  let top_fitness: Int = f[30];
  if top_fitness != 50 { ok = false; }
  return assert(ok, "elite 100: pinned top-5, full order is a sorted permutation");
}

fn t23() -> TestResult {
  var w = Vec[Int].new();
  var i = 0;
  while i < 100 {
    w.push(i + 1);
    i = i + 1;
  }
  var ok = sel_sum(&w) == 5050;
  var s = 1000;
  while s < 1100 {
    let a = sel_roulette(&w, s);
    let b = sel_roulette(&w, s);
    if a != b { ok = false; }
    if a < 0 || a >= 100 { ok = false; }
    s = s + 1;
  }
  if sel_roulette(&w, 1000) != 75 { ok = false; }
  if sel_roulette(&w, 1001) != 89 { ok = false; }
  if sel_roulette(&w, 1002) != 22 { ok = false; }
  if sel_roulette(&w, 1003) != 54 { ok = false; }
  if sel_roulette(&w, 1004) != 73 { ok = false; }
  return assert(ok, "roulette 100: pinned draws, 100-seed determinism and range");
}

fn t24() -> TestResult {
  var f = hundred_fitness();
  let a = sel_tournament_index(&f, 10, 5);
  let b = sel_tournament_index(&f, 10, 5);
  var ok = a == b;
  if a != 65 { ok = false; }
  if sel_tournament_index(&f, 100, 5) != 30 { ok = false; }
  if sel_tournament_index(&f, 500, 5) != 30 { ok = false; }
  if sel_tournament_index(&f, 1000, 5) != 30 { ok = false; }
  return assert(ok, "tournament 100: pinned winner, determinism, clamp to len");
}

fn t25() -> TestResult {
  var mixed = ints4(-4, 3, -1, 2);
  var ok = sel_sum(&mixed) == 5;
  var c1 = 0; var c3 = 0;
  var s = 0;
  while s < 50 {
    let idx = sel_roulette(&mixed, s);
    if idx == 1 { c1 = c1 + 1; }
    if idx == 3 { c3 = c3 + 1; }
    if idx != 1 && idx != 3 { ok = false; }
    s = s + 1;
  }
  if c1 != 32 { ok = false; }
  if c3 != 18 { ok = false; }
  if sel_roulette(&mixed, 0) != 1 { ok = false; }
  if sel_roulette(&mixed, 9) != 3 { ok = false; }
  return assert(ok, "roulette: negative entries never selected; pinned histogram");
}

fn main() -> Int {
  io.println("=== xiom.selection conformance tests ===");
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
    io.println("xiom.selection: all tests passed");
  } else {
    io.println("xiom.selection: tests failed");
  }
  return failed;
}
