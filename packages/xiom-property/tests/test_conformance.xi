// XIOM -- xiom.property conformance tests (26 checks)
// Port task: prove the pure-XIOM xiom.property engine against its SPEC.md.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Coverage: RNG determinism/bounds, range semantics, string generation, seed
// derivation, the three runners (Int, bounded Int, Str), the shrinker and
// report inspection.
//
// Every callback is a NAMED top-level function (`fn(&Int) -> Bool` /
// `fn(&Str) -> Bool`): the compiler's function-pointer codegen rejects inline
// lambdas. String comparisons go through xiom.string.compare.str_compare --
// never `==` on Str values that came out of a Vec[Str].

module property_tests
use xiom.io; use xiom.test; use xiom.property;
use xiom.string; use xiom.string.compare;

// --- named callbacks -------------------------------------------------------

fn always_true(x: &Int) -> Bool { return true; }

fn always_false(x: &Int) -> Bool { return false; }

fn is_even(x: &Int) -> Bool { return *x % 2 == 0; }

fn below_100(x: &Int) -> Bool { return *x < 100; }

fn non_positive(x: &Int) -> Bool { return *x <= 0; }

fn beyond_neg_100(x: &Int) -> Bool { return *x > -100; }

fn not_700(x: &Int) -> Bool { return *x != 700; }

fn always_true_str(s: &Str) -> Bool { return true; }

fn no_x(s: &Str) -> Bool {
  let t = *s;
  return !string.str_contains(t, "x");
}

// --- helpers ---------------------------------------------------------------

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// Byte-level membership check: every byte of `s` occurs in `alphabet`. For
// ASCII alphabets this is exactly "every character comes from the alphabet".
fn alphabet_ok(s: Str, alphabet: Str) -> Bool {
  var i = 0;
  while i < s.len() {
    let b = string.byte_at(s, i);
    var found = false;
    var j = 0;
    while j < alphabet.len() {
      if string.byte_at(alphabet, j) == b {
        found = true;
        break;
      }
      j = j + 1;
    }
    if !found { return false; }
    i = i + 1;
  }
  return true;
}

fn same_ints(a: &Vec[Int], b: &Vec[Int]) -> Bool {
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

// --- RNG: determinism and bounds -------------------------------------------

fn t1() -> TestResult {
  var a = prop_rng_new(12345);
  var b = prop_rng_new(12345);
  var ok = true;
  var i = 0;
  while i < 5 {
    let va = prop_rng_next(&mut a);
    let vb = prop_rng_next(&mut b);
    if va != vb { ok = false; }
    i = i + 1;
  }
  return assert(ok, "same seed yields the same first five draws");
}

fn t2() -> TestResult {
  var a = prop_rng_new(1);
  var b = prop_rng_new(2);
  var same = true;
  var i = 0;
  while i < 5 {
    let va = prop_rng_next(&mut a);
    let vb = prop_rng_next(&mut b);
    if va != vb { same = false; }
    i = i + 1;
  }
  return assert(!same, "different seeds produce different streams");
}

fn t3() -> TestResult {
  var r = prop_rng_new(4242);
  var saw_true = false;
  var saw_false = false;
  var i = 0;
  while i < 20 {
    let b = prop_rng_bool(&mut r);
    if b { saw_true = true; } else { saw_false = true; }
    i = i + 1;
  }
  return assert(saw_true && saw_false, "rng_bool produces both outcomes over 20 draws");
}

fn t4() -> TestResult {
  var r = prop_rng_new(7);
  var ok = true;
  var i = 0;
  while i < 200 {
    let v = prop_rng_range(&mut r, -17, 31);
    if v < -17 || v > 31 { ok = false; }
    i = i + 1;
  }
  var pinned = prop_rng_new(99);
  var j = 0;
  while j < 200 {
    let w = prop_rng_range(&mut pinned, 5, 5);
    if w != 5 { ok = false; }
    j = j + 1;
  }
  return assert(ok, "range draws stay within [lo, hi] and pin a single point");
}

fn t5() -> TestResult {
  var r = prop_rng_new(3);
  let v = prop_rng_range(&mut r, 10, 4);
  var ok = v == 10;
  var fresh = prop_rng_new(3);
  let x = prop_rng_next(&mut r);
  let y = prop_rng_next(&mut fresh);
  if x != y { ok = false; }
  return assert(ok, "hi < lo returns lo and consumes no randomness");
}

fn t6() -> TestResult {
  var r = prop_rng_new(2026);
  var saw0 = false;
  var saw1 = false;
  var saw2 = false;
  var saw3 = false;
  var i = 0;
  while i < 200 {
    let v = prop_rng_range(&mut r, 0, 3);
    if v == 0 { saw0 = true; }
    if v == 1 { saw1 = true; }
    if v == 2 { saw2 = true; }
    if v == 3 { saw3 = true; }
    i = i + 1;
  }
  return assert(saw0 && saw1 && saw2 && saw3, "range is inclusive at both bounds");
}

fn t7() -> TestResult {
  var r = prop_rng_new(-12345);
  var ok = true;
  var i = 0;
  while i < 500 {
    let v = prop_rng_next(&mut r);
    if v < 0 { ok = false; }
    if v > 2147483647 { ok = false; }
    i = i + 1;
  }
  return assert(ok, "rng_next stays non-negative and below 2^31");
}

fn t8() -> TestResult {
  var r = prop_rng_new(77);
  var ok = true;
  var max_seen = 0;
  var i = 0;
  while i < 30 {
    let s = prop_rng_string(&mut r, 12, "abc");
    if s.len() > 12 { ok = false; }
    if !alphabet_ok(s, "abc") { ok = false; }
    if s.len() > max_seen { max_seen = s.len(); }
    i = i + 1;
  }
  if max_seen == 0 { ok = false; }
  return assert(ok, "string draws are length-bounded and alphabet-only");
}

fn t9() -> TestResult {
  var r = prop_rng_new(8);
  let s = prop_rng_string(&mut r, 8, "");
  return assert(streq(s, ""), "empty alphabet yields the empty string");
}

fn t10() -> TestResult {
  var r = prop_rng_new(9);
  let zero = prop_rng_string(&mut r, 0, "abc");
  let negative = prop_rng_string(&mut r, -4, "abc");
  var ok = streq(zero, "");
  if !streq(negative, "") { ok = false; }
  return assert(ok, "len <= 0 yields the empty string");
}

// --- seed derivation --------------------------------------------------------

fn t11() -> TestResult {
  var a = prop_seeds(6, 42);
  var b = prop_seeds(6, 42);
  var ok = same_ints(&a, &b);
  if a.len() != 6 { ok = false; }
  var e = prop_seeds(6, 43);
  if same_ints(&a, &e) { ok = false; }
  var c = prop_seeds(0, 42);
  var d = prop_seeds(-3, 42);
  if c.len() != 0 { ok = false; }
  if d.len() != 0 { ok = false; }
  var i = 0;
  while i < a.len() {
    let av: Int = a[i];
    if av < 0 { ok = false; }
    var j = i + 1;
    while j < a.len() {
      let bv: Int = a[j];
      if av == bv { ok = false; }
      j = j + 1;
    }
    i = i + 1;
  }
  return assert(ok, "seeds are deterministic, counted and distinct-looking");
}

// --- runners: Int -----------------------------------------------------------

fn t12() -> TestResult {
  var seeds = prop_seeds(10, 5);
  let rep = prop_run_int(always_true, &seeds);
  var ok = rep.passed == 10;
  if rep.failed != 0 { ok = false; }
  if !prop_report_ok(&rep) { ok = false; }
  return assert(ok, "always-true property passes every seed");
}

fn t13() -> TestResult {
  var seeds = prop_seeds(4, 11);
  let rep = prop_run_int(always_true, &seeds);
  var ok = rep.first_seed == 0;
  if rep.first_value != 0 { ok = false; }
  return assert(ok, "a green report records no failure seed or value");
}

fn t14() -> TestResult {
  var seeds = prop_seeds(8, 3);
  let rep = prop_run_int(always_false, &seeds);
  var ok = rep.failed == 1;
  if rep.passed != 0 { ok = false; }
  let first: Int = seeds[0];
  if rep.first_seed != first { ok = false; }
  if rep.first_value < -1000 || rep.first_value > 1000 { ok = false; }
  if prop_report_ok(&rep) { ok = false; }
  return assert(ok, "always-false fails on the first seed and records it");
}

fn t15() -> TestResult {
  var seeds = prop_seeds(16, 21);
  let rep = prop_run_int(below_100, &seeds);
  var ok = rep.failed == 1;
  if rep.first_value < 100 { ok = false; }
  if rep.first_value > 1000 { ok = false; }
  if rep.passed >= 16 { ok = false; }
  let expect: Int = seeds[rep.passed];
  if rep.first_seed != expect { ok = false; }
  return assert(ok, "a failing property stops at the first failure");
}

// --- runners: bounded Int and Str -------------------------------------------

fn t16() -> TestResult {
  var seeds = prop_seeds(12, 13);
  let green = prop_run_range(always_true, &seeds, -5, 5);
  var ok = green.passed == 12;
  if green.failed != 0 { ok = false; }
  let rep = prop_run_range(below_100, &seeds, 0, 999);
  if rep.failed != 1 { ok = false; }
  if rep.first_value < 100 || rep.first_value > 999 { ok = false; }
  var re = prop_rng_new(rep.first_seed);
  let v = prop_rng_range(&mut re, 0, 999);
  if v != rep.first_value { ok = false; }
  return assert(ok, "range runs respect the bounds and replay the failing draw");
}

fn t17() -> TestResult {
  var seeds = prop_seeds(10, 17);
  let rep = prop_run_str(always_true_str, &seeds, 6, "xyz");
  var ok = rep.passed == 10;
  if rep.failed != 0 { ok = false; }
  if !prop_report_ok(&rep) { ok = false; }
  return assert(ok, "always-true string property passes every seed");
}

fn t18() -> TestResult {
  var seeds = prop_seeds(12, 19);
  let rep = prop_run_str(no_x, &seeds, 6, "xyz");
  var ok = rep.failed == 1;
  if rep.first_value < 1 { ok = false; }
  if rep.first_value > 6 { ok = false; }
  var re = prop_rng_new(rep.first_seed);
  let s = prop_rng_string(&mut re, 6, "xyz");
  if s.len() != rep.first_value { ok = false; }
  if !alphabet_ok(s, "xyz") { ok = false; }
  if no_x(&s) { ok = false; }
  if prop_report_ok(&rep) { ok = false; }
  return assert(ok, "a failing string run replays its counterexample length");
}

fn t19() -> TestResult {
  var seeds = prop_seeds(5, 23);
  let even = prop_run_range(is_even, &seeds, 0, 0);
  var ok = even.passed == 5;
  if even.failed != 0 { ok = false; }
  let odd = prop_run_range(is_even, &seeds, 1, 1);
  if odd.failed != 1 { ok = false; }
  if odd.first_value != 1 { ok = false; }
  let first: Int = seeds[0];
  if odd.first_seed != first { ok = false; }
  return assert(ok, "a pinned range decides the property deterministically");
}

// --- shrinking --------------------------------------------------------------

fn t20() -> TestResult {
  let shrunk = prop_shrink_int(1000000, below_100);
  var ok = shrunk == 122;
  if below_100(&shrunk) { ok = false; }
  let half = shrunk / 2;
  if !below_100(&half) { ok = false; }
  if shrunk >= 1000000 { ok = false; }
  return assert(ok, "shrink below_100 minimises to the halving-chain edge");
}

fn t21() -> TestResult {
  let shrunk = prop_shrink_int(777, always_true);
  return assert(shrunk == 777, "shrink on a passing property returns the input");
}

fn t22() -> TestResult {
  let shrunk = prop_shrink_int(700, not_700);
  var ok = shrunk == 700;
  if not_700(&shrunk) { ok = false; }
  let half = shrunk / 2;
  if !not_700(&half) { ok = false; }
  return assert(ok, "shrink stops as soon as a candidate passes");
}

fn t23() -> TestResult {
  let shrunk = prop_shrink_int(1000000, non_positive);
  var ok = shrunk == 1;
  if non_positive(&shrunk) { ok = false; }
  return assert(ok, "shrink walks down to the chain floor above zero");
}

fn t24() -> TestResult {
  let shrunk = prop_shrink_int(-1000000, beyond_neg_100);
  var ok = shrunk == -122;
  if beyond_neg_100(&shrunk) { ok = false; }
  let half = shrunk / 2;
  if !beyond_neg_100(&half) { ok = false; }
  return assert(ok, "shrink on a negative input keeps the sign and shrinks magnitude");
}

fn t25() -> TestResult {
  var seeds = prop_seeds(3, 29);
  let good = prop_run_int(always_true, &seeds);
  let bad = prop_run_int(always_false, &seeds);
  var ok = prop_report_ok(&good);
  if prop_report_ok(&bad) { ok = false; }
  return assert(ok, "prop_report_ok reflects the failure count");
}

fn t26() -> TestResult {
  var a = prop_rng_new(555);
  var b = prop_rng_new(555);
  var ok = true;
  var i = 0;
  while i < 8 {
    let va = prop_rng_bool(&mut a);
    let vb = prop_rng_bool(&mut b);
    if va != vb { ok = false; }
    i = i + 1;
  }
  return assert(ok, "bool draws are reproducible for the same seed");
}

fn main() -> Int {
  io.println("=== xiom.property conformance tests ===");
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
    io.println("xiom.property: all tests passed");
  } else {
    io.println("xiom.property: tests failed");
  }
  return failed;
}
