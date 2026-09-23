// XIOM -- xiom.ttl conformance tests
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module ttl_tests
use xiom.io; use xiom.test;
use xiom.ttl;

// Extracted Int payload; -1 when the Option is None (test values are >= 0).
fn option_int(o: Option[Int]) -> Int {
  var v: Int = 0 - 1;
  match o {
    Some(x) => { v = x; },
    None => {},
  };
  return v;
}

// True when the Option is None.
fn option_none(o: Option[Int]) -> Bool {
  var empty: Bool = true;
  match o {
    Some(_) => { empty = false; },
    None => {},
  };
  return empty;
}

fn t_ttl_zero_expires_immediately() -> TestResult {
  var c = ttl_new(4, 60);
  ttl_insert_with_ttl(&mut c, "zero", 7, 0);
  let got = ttl_get(&mut c, "zero");
  let exps = ttl_expirations(&c);
  let misses = ttl_misses(&c);
  let empty = option_none(got);
  let ok = empty && exps == 1 && misses == 1;
  return assert(ok, "ttl 0: already expired on insert (expirations=1, misses=1)");
}

fn t_negative_ttl_expires() -> TestResult {
  var c = ttl_new(4, 60);
  ttl_insert_with_ttl(&mut c, "neg", 7, 0 - 5);
  let got = ttl_get(&mut c, "neg");
  let empty = option_none(got);
  return assert(empty, "negative ttl: already expired on insert");
}

fn t_large_ttl_is_live() -> TestResult {
  var c = ttl_new(4, 60);
  ttl_insert(&mut c, "live", 42);
  let got = ttl_get(&mut c, "live");
  let value = option_int(got);
  let hits = ttl_hits(&c);
  let ok = value == 42 && hits == 1;
  return assert(ok, "large ttl: live get returns 42 and counts a hit");
}

fn t_peek_returns_none_for_expired_without_removing() -> TestResult {
  var c = ttl_new(4, 60);
  ttl_insert_with_ttl(&mut c, "p", 9, 0);
  let peeked = ttl_peek(&c, "p");
  let exps = ttl_expirations(&c);
  let len = ttl_len(&c);
  let misses = ttl_misses(&c);
  let peek_none = option_none(peeked);
  let untouched = exps == 0 && len == 0 && misses == 0;
  let ok = peek_none && untouched;
  return assert(ok, "peek expired: None, no counters changed, entry not removed");
}

fn t_evict_expired_returns_count() -> TestResult {
  var c = ttl_new(8, 60);
  ttl_insert_with_ttl(&mut c, "e1", 1, 0);
  ttl_insert_with_ttl(&mut c, "e2", 2, 0 - 3);
  ttl_insert(&mut c, "live", 3);
  let removed = ttl_evict_expired(&mut c);
  let exps = ttl_expirations(&c);
  let len = ttl_len(&c);
  let ok = removed == 2 && exps == 2 && len == 1;
  return assert(ok, "evict_expired: sweeps 2 expired entries, keeps 1 live");
}

fn t_get_expired_counts_expiration_and_miss() -> TestResult {
  var c = ttl_new(4, 60);
  ttl_insert_with_ttl(&mut c, "e", 5, 0);
  let got = ttl_get(&mut c, "e");
  let exps = ttl_expirations(&c);
  let misses = ttl_misses(&c);
  let len = ttl_len(&c);
  let empty = option_none(got);
  let ok = empty && exps == 1 && misses == 1 && len == 0;
  return assert(ok, "get expired: None, expirations=1, misses=1, entry removed");
}

fn t_hits_count_live_gets() -> TestResult {
  var c = ttl_new(4, 60);
  ttl_insert(&mut c, "h", 1);
  let first = ttl_get(&mut c, "h");
  let second = ttl_get(&mut c, "h");
  let v1 = option_int(first);
  let v2 = option_int(second);
  let hits = ttl_hits(&c);
  let misses = ttl_misses(&c);
  let ok = v1 == 1 && v2 == 1 && hits == 2 && misses == 0;
  return assert(ok, "live gets: hits=2, misses=0");
}

fn t_len_excludes_expired() -> TestResult {
  var c = ttl_new(8, 60);
  ttl_insert(&mut c, "a", 1);
  ttl_insert_with_ttl(&mut c, "b", 2, 0);
  let len = ttl_len(&c);
  return assert(len == 1, "len: counts live entries only");
}

fn t_remaining_secs_in_range() -> TestResult {
  var c = ttl_new(8, 60);
  ttl_insert_with_ttl(&mut c, "r", 1, 30);
  ttl_insert_with_ttl(&mut c, "e", 2, 0);
  let rem = ttl_remaining_secs(&c, "r");
  let value = option_int(rem);
  let in_range = value > 0 && value <= 30;
  let missing = ttl_remaining_secs(&c, "missing");
  let missing_none = option_none(missing);
  let expired = ttl_remaining_secs(&c, "e");
  let expired_none = option_none(expired);
  let ok = in_range && missing_none && expired_none;
  return assert(ok, "remaining_secs: (0, ttl] when live, None when absent/expired");
}

fn t_capacity_evicts_earliest_expiry() -> TestResult {
  var c = ttl_new(2, 1000);
  ttl_insert_with_ttl(&mut c, "old", 1, 100);
  ttl_insert_with_ttl(&mut c, "mid", 2, 200);
  ttl_insert_with_ttl(&mut c, "new", 3, 300);
  let cap = ttl_capacity(&c);
  let len = ttl_len(&c);
  let old_gone = !ttl_contains(&c, "old");
  let mid_kept = ttl_contains(&c, "mid");
  let new_kept = ttl_contains(&c, "new");
  let ok = cap == 2 && len == 2 && old_gone && mid_kept && new_kept;
  return assert(ok, "capacity: earliest expires_at evicted, live set correct");
}

fn t_remove_live_and_absent() -> TestResult {
  var c = ttl_new(4, 60);
  ttl_insert(&mut c, "k", 1);
  let removed = ttl_remove(&mut c, "k");
  let again = ttl_remove(&mut c, "k");
  let present = ttl_contains(&c, "k");
  let len = ttl_len(&c);
  let ok = removed && !present && !again && len == 0;
  return assert(ok, "remove: live=true then absent, second remove=false");
}

fn t_clear_empties_the_cache() -> TestResult {
  var c = ttl_new(3, 60);
  ttl_insert(&mut c, "a", 1);
  ttl_insert(&mut c, "b", 2);
  ttl_clear(&mut c);
  let after = ttl_len(&c);
  let hits = ttl_hits(&c);
  let exps = ttl_expirations(&c);
  let cap = ttl_capacity(&c);
  let present = ttl_contains(&c, "a");
  let ok = after == 0 && hits == 0 && exps == 0 && cap == 3 && !present;
  return assert(ok, "clear: entries and statistics reset, capacity preserved");
}

fn t_contains_false_for_expired() -> TestResult {
  var c = ttl_new(4, 60);
  ttl_insert(&mut c, "live", 1);
  ttl_insert_with_ttl(&mut c, "dead", 2, 0);
  let has_live = ttl_contains(&c, "live");
  let has_dead = ttl_contains(&c, "dead");
  let ok = has_live && !has_dead;
  return assert(ok, "contains: true when live, false when expired");
}

fn t_insert_with_ttl_overrides_default() -> TestResult {
  var c = ttl_new(4, 1000);
  ttl_insert_with_ttl(&mut c, "short", 1, 0);
  ttl_insert(&mut c, "defaulted", 2);
  let short_got = ttl_get(&mut c, "short");
  let short_none = option_none(short_got);
  let defaulted_got = ttl_get(&mut c, "defaulted");
  let defaulted_value = option_int(defaulted_got);
  let ok = short_none && defaulted_value == 2;
  return assert(ok, "insert_with_ttl: explicit ttl overrides the default");
}

fn main() -> Int {
  io.println("=== xiom.ttl conformance tests ===");
  var failed: Int = 0;
  let r1 = t_ttl_zero_expires_immediately();
  if r1.passed { io.println("  [PASS] " + r1.name); } else { io.println("  [FAIL] " + r1.name); failed = failed + 1; }
  let r2 = t_negative_ttl_expires();
  if r2.passed { io.println("  [PASS] " + r2.name); } else { io.println("  [FAIL] " + r2.name); failed = failed + 1; }
  let r3 = t_large_ttl_is_live();
  if r3.passed { io.println("  [PASS] " + r3.name); } else { io.println("  [FAIL] " + r3.name); failed = failed + 1; }
  let r4 = t_peek_returns_none_for_expired_without_removing();
  if r4.passed { io.println("  [PASS] " + r4.name); } else { io.println("  [FAIL] " + r4.name); failed = failed + 1; }
  let r5 = t_evict_expired_returns_count();
  if r5.passed { io.println("  [PASS] " + r5.name); } else { io.println("  [FAIL] " + r5.name); failed = failed + 1; }
  let r6 = t_get_expired_counts_expiration_and_miss();
  if r6.passed { io.println("  [PASS] " + r6.name); } else { io.println("  [FAIL] " + r6.name); failed = failed + 1; }
  let r7 = t_hits_count_live_gets();
  if r7.passed { io.println("  [PASS] " + r7.name); } else { io.println("  [FAIL] " + r7.name); failed = failed + 1; }
  let r8 = t_len_excludes_expired();
  if r8.passed { io.println("  [PASS] " + r8.name); } else { io.println("  [FAIL] " + r8.name); failed = failed + 1; }
  let r9 = t_remaining_secs_in_range();
  if r9.passed { io.println("  [PASS] " + r9.name); } else { io.println("  [FAIL] " + r9.name); failed = failed + 1; }
  let r10 = t_capacity_evicts_earliest_expiry();
  if r10.passed { io.println("  [PASS] " + r10.name); } else { io.println("  [FAIL] " + r10.name); failed = failed + 1; }
  let r11 = t_remove_live_and_absent();
  if r11.passed { io.println("  [PASS] " + r11.name); } else { io.println("  [FAIL] " + r11.name); failed = failed + 1; }
  let r12 = t_clear_empties_the_cache();
  if r12.passed { io.println("  [PASS] " + r12.name); } else { io.println("  [FAIL] " + r12.name); failed = failed + 1; }
  let r13 = t_contains_false_for_expired();
  if r13.passed { io.println("  [PASS] " + r13.name); } else { io.println("  [FAIL] " + r13.name); failed = failed + 1; }
  let r14 = t_insert_with_ttl_overrides_default();
  if r14.passed { io.println("  [PASS] " + r14.name); } else { io.println("  [FAIL] " + r14.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.ttl: all tests passed");
  } else {
    io.println("xiom.ttl: tests failed");
  }
  return failed;
}
