// XIOM -- xiom.fuzz conformance tests (22 checks)
// Port task: prove the pure-XIOM xiom.fuzz mutation engine against SPEC.md.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Coverage: RNG determinism/bounds, every single-step mutator (length and
// byte/bit-level invariants, determinism, empty-input behavior), the
// multi-step fuzz_mutate driver (identity at 0 steps, determinism, replay of
// the documented op and step-seed derivation, actual growth/shrink), and the
// byte-level Str wrapper.
//
// Str equality goes through xiom.string.compare.str_compare (BUG 17: `==` on
// Str values read from a Vec lowers to a pointer comparison). byte_at results
// are cast to Int before any comparison, so no UInt8 constant >= 128 is ever
// compared directly. `test_mix`/`step_seed` replicate the SPEC-pinned seed
// derivation so the suite can predict fuzz_mutate's exact step seeds.

module fuzz_tests
use xiom.io; use xiom.test; use xiom.fuzz;
use xiom.string; use xiom.string.compare;

// --- helpers ---------------------------------------------------------------

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn bytes_of(s: Str) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < s.len() {
    v.push(string.byte_at(s, i));
    i = i + 1;
  }
  return v;
}

fn bytes_equal(a: Vec[UInt8], b: Vec[UInt8]) -> Bool {
  if a.len() != b.len() {
    return false;
  }
  var i = 0;
  while i < a.len() {
    if a[i] != b[i] {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn remove_at(v: &Vec[UInt8], p: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < v.len() {
    if i != p {
      out.push(v[i]);
    }
    i = i + 1;
  }
  return out;
}

fn is_subsequence(sub: &Vec[UInt8], sup: &Vec[UInt8]) -> Bool {
  var j = 0;
  var i = 0;
  while i < sup.len() && j < sub.len() {
    if sub[j] == sup[i] {
      j = j + 1;
    }
    i = i + 1;
  }
  return j == sub.len();
}

fn differs_at_count(a: &Vec[UInt8], b: &Vec[UInt8]) -> Int {
  if a.len() != b.len() {
    return -1;
  }
  var c = 0;
  var i = 0;
  while i < a.len() {
    if a[i] != b[i] {
      c = c + 1;
    }
    i = i + 1;
  }
  return c;
}

fn first_diff(a: &Vec[UInt8], b: &Vec[UInt8]) -> Int {
  var i = 0;
  while i < a.len() {
    if a[i] != b[i] {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

fn bit_count(v: Int) -> Int {
  var x = v;
  var c = 0;
  while x > 0 {
    c = c + (x % 2);
    x = x / 2;
  }
  return c;
}

// SPEC.md section 3 copy: the fuzz mixer, used to predict step seeds.
fn test_mix(v: Int) -> Int {
  var h = v;
  h = h ^ (h >> 13);
  h = h & 0x00FFFFFFFFFFFFFF;
  h = h ^ (h << 7);
  h = h ^ (h >> 17);
  h = h & 0x7FFFFFFF;
  return h;
}

fn step_seed(base: Int, index: Int) -> Int {
  return test_mix(base + index * 2654435761);
}

// --- RNG -------------------------------------------------------------------

fn t1() -> TestResult {
  var a = fuzz_rng_new(12345);
  var b = fuzz_rng_new(12345);
  var ok = true;
  var i = 0;
  while i < 8 {
    let va = fuzz_next(&mut a);
    let vb = fuzz_next(&mut b);
    if va != vb { ok = false; }
    i = i + 1;
  }
  return assert(ok, "same seed yields the same first eight draws");
}

fn t2() -> TestResult {
  var a = fuzz_rng_new(1);
  var b = fuzz_rng_new(2);
  var same = true;
  var i = 0;
  while i < 8 {
    let va = fuzz_next(&mut a);
    let vb = fuzz_next(&mut b);
    if va != vb { same = false; }
    i = i + 1;
  }
  return assert(!same, "different seeds produce different streams");
}

fn t3() -> TestResult {
  var r = fuzz_rng_new(-987654321);
  var ok = true;
  var i = 0;
  while i < 300 {
    let v = fuzz_next(&mut r);
    if v < 0 { ok = false; }
    if v > 2147483647 { ok = false; }
    i = i + 1;
  }
  return assert(ok, "fuzz_next stays in [0, 2^31-1] from a negative seed");
}

fn t4() -> TestResult {
  var r = fuzz_rng_new(20260923);
  let first = fuzz_next(&mut r);
  var any_different = false;
  var i = 0;
  while i < 8 {
    let v = fuzz_next(&mut r);
    if v != first { any_different = true; }
    i = i + 1;
  }
  return assert(any_different, "the draw stream is not constant");
}

// --- flip_byte --------------------------------------------------------------

fn t5() -> TestResult {
  var data = bytes_of("abcd");
  let m = fuzz_flip_byte(&data, 11);
  var ok = m.len() == data.len();
  if differs_at_count(&data, &m) != 1 { ok = false; }
  return assert(ok, "flip_byte changes exactly one byte and keeps the length");
}

fn t6() -> TestResult {
  var data = bytes_of("flip me");
  let a = fuzz_flip_byte(&data, 99);
  let b = fuzz_flip_byte(&data, 99);
  var ok = bytes_equal(a, b);
  if bytes_equal(a, data) { ok = false; }
  return assert(ok, "flip_byte is deterministic and never a no-op");
}

fn t7() -> TestResult {
  var e = Vec[UInt8].new();
  var ok = fuzz_flip_byte(&e, 5).len() == 0;
  if fuzz_flip_bit(&e, 6).len() != 0 { ok = false; }
  return assert(ok, "flip_byte and flip_bit on empty input stay empty");
}

// --- flip_bit ---------------------------------------------------------------

fn t8() -> TestResult {
  var data = bytes_of("ABCDE");
  let m = fuzz_flip_bit(&data, 7);
  var ok = m.len() == data.len();
  if differs_at_count(&data, &m) != 1 { ok = false; }
  let p = first_diff(&data, &m);
  if p < 0 { ok = false; } else {
    let delta = (data[p] as Int) ^ (m[p] as Int);
    if bit_count(delta) != 1 { ok = false; }
  }
  return assert(ok, "flip_bit toggles exactly one bit in one byte");
}

fn t9() -> TestResult {
  var data = bytes_of("bitwise");
  let a = fuzz_flip_bit(&data, 21);
  let b = fuzz_flip_bit(&data, 21);
  var ok = bytes_equal(a, b);
  if bytes_equal(a, data) { ok = false; }
  return assert(ok, "flip_bit is deterministic and never a no-op");
}

// --- insert_byte ------------------------------------------------------------

fn t10() -> TestResult {
  var data = bytes_of("xyz");
  let m = fuzz_insert_byte(&data, 13);
  var ok = m.len() == data.len() + 1;
  var found = false;
  var p = 0;
  while p < m.len() {
    if bytes_equal(remove_at(&m, p), data) { found = true; }
    p = p + 1;
  }
  if !found { ok = false; }
  return assert(ok, "insert_byte grows by 1 and preserves the original bytes");
}

fn t11() -> TestResult {
  var data = bytes_of("insert");
  let a = fuzz_insert_byte(&data, 44);
  let b = fuzz_insert_byte(&data, 44);
  var ok = bytes_equal(a, b);
  var e = Vec[UInt8].new();
  if fuzz_insert_byte(&e, 6).len() != 1 { ok = false; }
  return assert(ok, "insert_byte is deterministic and grows empty input to 1");
}

// --- delete_byte ------------------------------------------------------------

fn t12() -> TestResult {
  var data = bytes_of("abcdef");
  let m = fuzz_delete_byte(&data, 17);
  var ok = m.len() == data.len() - 1;
  var found = false;
  var p = 0;
  while p < data.len() {
    if bytes_equal(remove_at(&data, p), m) { found = true; }
    p = p + 1;
  }
  if !found { ok = false; }
  return assert(ok, "delete_byte shrinks by 1 and removes exactly one byte");
}

fn t13() -> TestResult {
  var data = bytes_of("delete");
  let a = fuzz_delete_byte(&data, 3);
  let b = fuzz_delete_byte(&data, 3);
  var ok = bytes_equal(a, b);
  var e = Vec[UInt8].new();
  if fuzz_delete_byte(&e, 9).len() != 0 { ok = false; }
  return assert(ok, "delete_byte is deterministic and empty stays empty");
}

// --- duplicate_range --------------------------------------------------------

fn t14() -> TestResult {
  var data = bytes_of("keep me");
  let m = fuzz_duplicate_range(&data, 31);
  var ok = m.len() > data.len();
  if !is_subsequence(&data, &m) { ok = false; }
  let again = fuzz_duplicate_range(&data, 31);
  if !bytes_equal(m, again) { ok = false; }
  return assert(ok, "duplicate_range grows, keeps byte order and is deterministic");
}

fn t15() -> TestResult {
  var e = Vec[UInt8].new();
  var ok = fuzz_duplicate_range(&e, 2).len() == 0;
  if fuzz_mutate(&e, 2, 0).len() != 0 { ok = false; }
  return assert(ok, "duplicate_range and a zero-step mutate on empty stay empty");
}

// --- fuzz_mutate ------------------------------------------------------------

fn t16() -> TestResult {
  var data = bytes_of("identity");
  let z = fuzz_mutate(&data, 555, 0);
  var ok = bytes_equal(z, data);
  let neg = fuzz_mutate(&data, 555, -4);
  if !bytes_equal(neg, data) { ok = false; }
  return assert(ok, "mutations <= 0 returns the input unchanged");
}

fn t17() -> TestResult {
  var data = bytes_of("determinism");
  let a = fuzz_mutate(&data, 2026, 16);
  let b = fuzz_mutate(&data, 2026, 16);
  var ok = bytes_equal(a, b);
  var any_diff = false;
  var s = 0;
  while s < 5 {
    let x = fuzz_mutate(&data, 9000 + s, 16);
    if !bytes_equal(x, a) { any_diff = true; }
    s = s + 1;
  }
  if !any_diff { ok = false; }
  return assert(ok, "mutate is deterministic and seed-sensitive");
}

fn t18() -> TestResult {
  var base = bytes_of("xiom fuzz replay base");
  let seed = 20260923;
  let steps = 12;
  var expect = base;
  var r = fuzz_rng_new(seed);
  var i = 0;
  while i < steps {
    let op = fuzz_next(&mut r) % 5;
    let ss = step_seed(seed, i);
    if op == 0 { expect = fuzz_flip_byte(&expect, ss); }
    elif op == 1 { expect = fuzz_flip_bit(&expect, ss); }
    elif op == 2 { expect = fuzz_insert_byte(&expect, ss); }
    elif op == 3 { expect = fuzz_delete_byte(&expect, ss); }
    else { expect = fuzz_duplicate_range(&expect, ss); }
    i = i + 1;
  }
  let got = fuzz_mutate(&base, seed, steps);
  var ok = bytes_equal(got, expect);
  let again = fuzz_mutate(&base, seed, steps);
  if !bytes_equal(again, expect) { ok = false; }
  return assert(ok, "mutate replays the documented op and step-seed derivation");
}

fn t19() -> TestResult {
  var data = bytes_of("change");
  var ok = true;
  var saw_grow = false;
  var saw_shrink = false;
  var s = 0;
  while s < 12 {
    let m = fuzz_mutate(&data, 300 + s, 1);
    if bytes_equal(m, data) { ok = false; }
    if m.len() > data.len() { saw_grow = true; }
    if m.len() < data.len() { saw_shrink = true; }
    s = s + 1;
  }
  if !saw_grow { ok = false; }
  if !saw_shrink { ok = false; }
  return assert(ok, "one-step mutate always mutates and both grows and shrinks");
}

// --- str mutation -----------------------------------------------------------

fn t20() -> TestResult {
  let s = "fuzz string";
  let a = fuzz_mutate_str(s, 777, 8);
  let b = fuzz_mutate_str(s, 777, 8);
  var ok = streq(a, b);
  let zero = fuzz_mutate_str(s, 777, 0);
  if !streq(zero, s) { ok = false; }
  var any_diff = false;
  var k = 0;
  while k < 5 {
    let x = fuzz_mutate_str(s, 800 + k, 8);
    if !streq(x, a) { any_diff = true; }
    k = k + 1;
  }
  if !any_diff { ok = false; }
  return assert(ok, "str mutation is deterministic, seed-sensitive and 0 = identity");
}

fn t21() -> TestResult {
  let s = "hello fuzz";
  let seed = 4242;
  let muts = 12;
  let ms = fuzz_mutate_str(s, seed, muts);
  let mb = fuzz_mutate(&bytes_of(s), seed, muts);
  var ok = ms.len() == mb.len();
  var i = 0;
  while i < mb.len() {
    let want = mb[i] as Int;
    let got = string.byte_at(ms, i) as Int;
    if want != got { ok = false; }
    i = i + 1;
  }
  return assert(ok, "ASCII str mutation equals byte mutation byte-for-byte");
}

fn t22() -> TestResult {
  var e = Vec[UInt8].new();
  var ok = fuzz_flip_byte(&e, 1).len() == 0;
  if fuzz_flip_bit(&e, 2).len() != 0 { ok = false; }
  if fuzz_delete_byte(&e, 3).len() != 0 { ok = false; }
  if fuzz_duplicate_range(&e, 4).len() != 0 { ok = false; }
  if fuzz_insert_byte(&e, 5).len() != 1 { ok = false; }
  if fuzz_mutate(&e, 6, 0).len() != 0 { ok = false; }
  let m8a = fuzz_mutate(&e, 6, 8);
  let m8b = fuzz_mutate(&e, 6, 8);
  if !bytes_equal(m8a, m8b) { ok = false; }
  let es = fuzz_mutate_str("", 7, 4);
  let es2 = fuzz_mutate_str("", 7, 4);
  if !streq(es, es2) { ok = false; }
  return assert(ok, "empty inputs: no-op ops stay empty, insert grows to 1");
}

fn main() -> Int {
  io.println("=== xiom.fuzz conformance tests ===");
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
    io.println("xiom.fuzz: all tests passed");
  } else {
    io.println("xiom.fuzz: tests failed");
  }
  return failed;
}
