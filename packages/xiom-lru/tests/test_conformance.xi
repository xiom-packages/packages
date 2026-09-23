// XIOM -- xiom.lru conformance tests (16 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module lru_tests
use xiom.io; use xiom.test; use xiom.lru;
use xiom.string.compare;

// Read-only operations are wrapped in small helpers that take `&mut`. Local
// values in XIOM v0.61.3 warn (E001, advisory) when a `&c` call is followed
// by a `&mut c` call in the same function, so every call site below passes
// `&mut c`; the helpers call the real `&LruCache` API internally.
// Vec[Str] elements are compared with str_compare (BUG 17: `==` on Str
// values read from a Vec lowers to a pointer comparison).

fn get_is(c: &mut LruCache, key: Str, want: Int) -> Bool {
  let got = lru_get(c, key);
  match got {
    Some(v) => { return v == want; },
    None => {},
  }
  return false;
}

fn peek_is(c: &mut LruCache, key: Str, want: Int) -> Bool {
  let got = lru_peek(c, key);
  match got {
    Some(v) => { return v == want; },
    None => {},
  }
  return false;
}

fn peek_none(c: &mut LruCache, key: Str) -> Bool {
  let got = lru_peek(c, key);
  match got {
    Some(_) => { return false; },
    None => { return true; },
  }
  return true;
}

fn has(c: &mut LruCache, key: Str) -> Bool {
  return lru_contains(c, key);
}

fn len_of(c: &mut LruCache) -> Int {
  return lru_len(c);
}

fn cap_of(c: &mut LruCache) -> Int {
  return lru_capacity(c);
}

fn hits_of(c: &mut LruCache) -> Int {
  return lru_hits(c);
}

fn misses_of(c: &mut LruCache) -> Int {
  return lru_misses(c);
}

fn evictions_of(c: &mut LruCache) -> Int {
  return lru_evictions(c);
}

fn mru_len(c: &mut LruCache) -> Int {
  return lru_keys_mru(c).len();
}

fn mru_is3(c: &mut LruCache, k0: Str, k1: Str, k2: Str) -> Bool {
  let ks = lru_keys_mru(c);
  if ks.len() != 3 { return false; }
  if compare.str_compare(ks[0], k0) != 0 { return false; }
  if compare.str_compare(ks[1], k1) != 0 { return false; }
  if compare.str_compare(ks[2], k2) != 0 { return false; }
  return true;
}

fn t1() -> TestResult {
  var c = lru_new(1);
  lru_put(&mut c, "a", 1);
  lru_put(&mut c, "b", 2);
  var ok = cap_of(&mut c) == 1;
  if len_of(&mut c) != 1 { ok = false; }
  if !has(&mut c, "b") { ok = false; }
  if has(&mut c, "a") { ok = false; }
  if !peek_none(&mut c, "a") { ok = false; }
  if !peek_is(&mut c, "b", 2) { ok = false; }
  if evictions_of(&mut c) != 1 { ok = false; }
  return assert(ok, "capacity 1 keeps only the newest entry");
}

fn t2() -> TestResult {
  var low = lru_new(0);
  var negative = lru_new(-5);
  var ok = cap_of(&mut low) == 1;
  if cap_of(&mut negative) != 1 { ok = false; }
  if len_of(&mut low) != 0 { ok = false; }
  return assert(ok, "capacity below 1 clamps to 1");
}

fn t3() -> TestResult {
  var c = lru_new(2);
  lru_put(&mut c, "a", 1);
  lru_put(&mut c, "b", 2);
  var ok = get_is(&mut c, "a", 1);
  lru_put(&mut c, "c", 3);
  if has(&mut c, "b") { ok = false; }
  if !has(&mut c, "a") { ok = false; }
  if !has(&mut c, "c") { ok = false; }
  if len_of(&mut c) != 2 { ok = false; }
  return assert(ok, "evicts the least recently used entry");
}

fn t4() -> TestResult {
  var c = lru_new(3);
  lru_put(&mut c, "a", 1);
  lru_put(&mut c, "b", 2);
  lru_put(&mut c, "c", 3);
  var ok = get_is(&mut c, "a", 1);
  if !mru_is3(&mut c, "a", "c", "b") { ok = false; }
  return assert(ok, "lru_get promotes the entry to MRU");
}

fn t5() -> TestResult {
  var c = lru_new(2);
  lru_put(&mut c, "a", 1);
  lru_put(&mut c, "b", 2);
  lru_put(&mut c, "a", 10);
  var ok = peek_is(&mut c, "a", 10);
  if len_of(&mut c) != 2 { ok = false; }
  if evictions_of(&mut c) != 0 { ok = false; }
  return assert(ok, "put on existing key updates value without eviction");
}

fn t6() -> TestResult {
  var c = lru_new(2);
  lru_put(&mut c, "a", 1);
  lru_put(&mut c, "b", 2);
  lru_put(&mut c, "a", 9);
  lru_put(&mut c, "c", 3);
  var ok = peek_is(&mut c, "a", 9);
  if !has(&mut c, "c") { ok = false; }
  if has(&mut c, "b") { ok = false; }
  if len_of(&mut c) != 2 { ok = false; }
  return assert(ok, "put on existing key keeps it MRU");
}

fn t7() -> TestResult {
  var c = lru_new(2);
  lru_put(&mut c, "a", 1);
  lru_put(&mut c, "b", 2);
  var ok = peek_is(&mut c, "a", 1);
  lru_put(&mut c, "c", 3);
  if has(&mut c, "a") { ok = false; }
  if !has(&mut c, "b") { ok = false; }
  if !has(&mut c, "c") { ok = false; }
  return assert(ok, "lru_peek does not promote recency");
}

fn t8() -> TestResult {
  var c = lru_new(2);
  lru_put(&mut c, "a", 1);
  var ok = peek_is(&mut c, "a", 1);
  if !peek_none(&mut c, "zz") { ok = false; }
  if hits_of(&mut c) != 0 { ok = false; }
  if misses_of(&mut c) != 0 { ok = false; }
  return assert(ok, "lru_peek changes no statistics");
}

fn t9() -> TestResult {
  var c = lru_new(3);
  lru_put(&mut c, "a", 1);
  lru_put(&mut c, "b", 2);
  var ok = lru_remove(&mut c, "a");
  if len_of(&mut c) != 1 { ok = false; }
  if has(&mut c, "a") { ok = false; }
  if !peek_none(&mut c, "a") { ok = false; }
  if !has(&mut c, "b") { ok = false; }
  return assert(ok, "remove existing key returns true and frees it");
}

fn t10() -> TestResult {
  var c = lru_new(3);
  lru_put(&mut c, "a", 1);
  var ok = !lru_remove(&mut c, "zz");
  if len_of(&mut c) != 1 { ok = false; }
  if !has(&mut c, "a") { ok = false; }
  if evictions_of(&mut c) != 0 { ok = false; }
  return assert(ok, "remove absent key returns false and changes nothing");
}

fn t11() -> TestResult {
  var c = lru_new(3);
  lru_put(&mut c, "a", 1);
  lru_put(&mut c, "b", 2);
  lru_put(&mut c, "c", 3);
  var ok = get_is(&mut c, "a", 1);
  if !peek_none(&mut c, "zz") { ok = false; }
  var miss = lru_get(&mut c, "zz");
  match miss {
    Some(_) => { ok = false; },
    None => {},
  }
  lru_clear(&mut c);
  if len_of(&mut c) != 0 { ok = false; }
  if has(&mut c, "a") { ok = false; }
  if cap_of(&mut c) != 3 { ok = false; }
  if hits_of(&mut c) != 1 { ok = false; }
  if misses_of(&mut c) != 1 { ok = false; }
  if mru_len(&mut c) != 0 { ok = false; }
  lru_put(&mut c, "d", 4);
  if !peek_is(&mut c, "d", 4) { ok = false; }
  if mru_len(&mut c) != 1 { ok = false; }
  if len_of(&mut c) != 1 { ok = false; }
  return assert(ok, "clear drops entries, keeps capacity and statistics");
}

fn t12() -> TestResult {
  var c = lru_new(5);
  lru_put(&mut c, "a", 1);
  lru_put(&mut c, "b", 2);
  lru_put(&mut c, "c", 3);
  var ok = len_of(&mut c) == 3;
  lru_put(&mut c, "b", 20);
  if len_of(&mut c) != 3 { ok = false; }
  lru_put(&mut c, "d", 4);
  if len_of(&mut c) != 4 { ok = false; }
  return assert(ok, "len tracks live entries");
}

fn t13() -> TestResult {
  var c = lru_new(3);
  lru_put(&mut c, "a", 1);
  var ok = get_is(&mut c, "a", 1);
  if !get_is(&mut c, "a", 1) { ok = false; }
  var miss = lru_get(&mut c, "zz");
  match miss {
    Some(_) => { ok = false; },
    None => {},
  }
  if hits_of(&mut c) != 2 { ok = false; }
  if misses_of(&mut c) != 1 { ok = false; }
  return assert(ok, "hits and misses are counted per lru_get");
}

fn t14() -> TestResult {
  var c = lru_new(2);
  lru_put(&mut c, "a", 1);
  lru_put(&mut c, "b", 2);
  lru_put(&mut c, "c", 3);
  var ok = evictions_of(&mut c) == 1;
  lru_put(&mut c, "b", 20);
  if evictions_of(&mut c) != 1 { ok = false; }
  lru_put(&mut c, "d", 4);
  if evictions_of(&mut c) != 2 { ok = false; }
  if len_of(&mut c) != 2 { ok = false; }
  return assert(ok, "evictions counts only capacity-driven evictions");
}

fn t15() -> TestResult {
  var c = lru_new(3);
  lru_put(&mut c, "a", 1);
  lru_put(&mut c, "b", 2);
  lru_put(&mut c, "c", 3);
  var ok = mru_is3(&mut c, "c", "b", "a");
  if !get_is(&mut c, "b", 2) { ok = false; }
  if !mru_is3(&mut c, "b", "c", "a") { ok = false; }
  if !peek_is(&mut c, "c", 3) { ok = false; }
  if !mru_is3(&mut c, "b", "c", "a") { ok = false; }
  lru_put(&mut c, "d", 4);
  if !mru_is3(&mut c, "d", "b", "c") { ok = false; }
  return assert(ok, "keys_mru is ordered most recent first");
}

fn t16() -> TestResult {
  var c = lru_new(4);
  lru_put(&mut c, "k", 1);
  lru_put(&mut c, "k", 2);
  lru_put(&mut c, "k", 3);
  var ok = len_of(&mut c) == 1;
  if !peek_is(&mut c, "k", 3) { ok = false; }
  if evictions_of(&mut c) != 0 { ok = false; }
  if cap_of(&mut c) != 4 { ok = false; }
  return assert(ok, "duplicate puts do not grow len");
}

fn main() -> Int {
  io.println("=== xiom.lru conformance tests ===");
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
    io.println("xiom.lru: all tests passed");
  } else {
    io.println("xiom.lru: tests failed");
  }
  return failed;
}
