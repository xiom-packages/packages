// XIOM -- xiom.cache conformance tests (26 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers: capacity validation and accessors on all four policies; the LRU
// eviction-order matrix with touch/update/peek effects; LRU capacity 1;
// explicit-remove semantics; evict_one ordering and the empty error; clear as
// a full reset; LRU stats; LFU frequency ordering, insertion-order tie-breaks
// and ordinal preservation across updates; CLOCK hand sweeps and second
// chances; TTL expired-on-get, sweep boundaries, refresh order, earliest-
// expiry capacity eviction, peek/contains/remove purity, past-expiry
// rejection and expired-on-put re-insertion; the pinned error catalog;
// cross-policy independence; and replay determinism.
//
// All state is built in-test: every test starts with a <policy>_create call,
// which is a full reset, or with <policy>_clear. Str equality goes through
// str_compare (BUG 17 discipline) and every Result is consumed exactly once
// through the typed helpers below.

module cache_tests
use xiom.io; use xiom.test; use xiom.cache;
use xiom.string.compare;

// --------------------------------------------------
//  Result helpers (one consumption per Result value)
// --------------------------------------------------

// True when the Result is Err with exactly the (code, key, detail) triple.
fn err_is(r: Result[Int, CacheError], code: Int, key: Int, detail: Int) -> Bool {
  if r.is_ok { return false; }
  let e: CacheError = r.error;
  if e.code != code { return false; }
  if e.key != key { return false; }
  return e.detail == detail;
}

// True when the Result is Ok with the given value.
fn ok_is(r: Result[Int, CacheError], want: Int) -> Bool {
  if !r.is_ok { return false; }
  let v: Int = r.value;
  return v == want;
}

// True when the counter snapshot matches all four fields.
fn stats_is(s: CacheStats, hits: Int, misses: Int, evictions: Int, size: Int) -> Bool {
  if s.hits != hits { return false; }
  if s.misses != misses { return false; }
  if s.evictions != evictions { return false; }
  return s.size == size;
}

// True when cache_error_message(code) equals `want` byte-wise.
fn msg_is(code: Int, want: Str) -> Bool {
  let m: Str = cache_error_message(code);
  return compare.str_compare(m, want) == 0;
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  var ok = ok_is(lru_create(3), 3);
  if lru_len() != 0 { ok = false; }
  if lru_capacity() != 3 { ok = false; }
  if !err_is(lru_create(0), 1, -1, 0) { ok = false; }
  if !err_is(lru_create(-7), 1, -1, -7) { ok = false; }
  if !err_is(lru_create(1048577), 2, -1, 1048577) { ok = false; }
  if lru_capacity() != 3 { ok = false; }
  if !ok_is(lfu_create(2), 2) { ok = false; }
  if !err_is(lfu_create(0), 1, -1, 0) { ok = false; }
  if !ok_is(clock_create(4), 4) { ok = false; }
  if !err_is(clock_create(-1), 1, -1, -1) { ok = false; }
  if !ok_is(ttl_create(5), 5) { ok = false; }
  if !err_is(ttl_create(1048577), 2, -1, 1048577) { ok = false; }
  if cache_max_capacity() != 1048576 { ok = false; }
  if !stats_is(lru_stats(), 0, 0, 0, 0) { ok = false; }
  if !stats_is(ttl_stats(), 0, 0, 0, 0) { ok = false; }
  return assert(ok, "create validates capacity 1..1048576 on all four policies");
}

fn t2() -> TestResult {
  var ok = ok_is(lru_create(3), 3);
  if !ok_is(lru_put(7, 700), 0) { ok = false; }
  if !ok_is(lru_put(8, 800), 0) { ok = false; }
  if lru_len() != 2 { ok = false; }
  if !lru_contains(7) { ok = false; }
  if lru_contains(9) { ok = false; }
  if !ok_is(lru_get(7), 700) { ok = false; }
  if !ok_is(lru_peek(8), 800) { ok = false; }
  if !err_is(lru_get(9), 3, 9, -1) { ok = false; }
  if !err_is(lru_peek(9), 3, 9, -1) { ok = false; }
  if !stats_is(lru_stats(), 1, 1, 0, 2) { ok = false; }
  return assert(ok, "LRU put/get/peek/len/contains and the miss counters");
}

fn t3() -> TestResult {
  var ok = ok_is(lru_create(3), 3);
  if !ok_is(lru_put(1, 10), 0) { ok = false; }
  if !ok_is(lru_put(2, 20), 0) { ok = false; }
  if !ok_is(lru_put(3, 30), 0) { ok = false; }
  if !ok_is(lru_get(1), 10) { ok = false; }
  if !ok_is(lru_get(2), 20) { ok = false; }
  if !ok_is(lru_put(4, 40), 1) { ok = false; }
  if lru_contains(3) { ok = false; }
  if !ok_is(lru_get(1), 10) { ok = false; }
  if !ok_is(lru_put(5, 50), 1) { ok = false; }
  if lru_contains(2) { ok = false; }
  if !ok_is(lru_put(6, 60), 1) { ok = false; }
  if lru_contains(4) { ok = false; }
  if !lru_contains(1) { ok = false; }
  if !lru_contains(5) { ok = false; }
  if !lru_contains(6) { ok = false; }
  if !ok_is(lru_last_evicted(), 4) { ok = false; }
  if !stats_is(lru_stats(), 3, 0, 3, 3) { ok = false; }
  return assert(ok, "LRU eviction order follows least-recently-used first");
}

fn t4() -> TestResult {
  var ok = ok_is(lru_create(2), 2);
  if !ok_is(lru_put(1, 10), 0) { ok = false; }
  if !ok_is(lru_put(2, 20), 0) { ok = false; }
  if !ok_is(lru_touch(1), 10) { ok = false; }
  if !ok_is(lru_put(3, 30), 1) { ok = false; }
  if lru_contains(2) { ok = false; }
  if !lru_contains(1) { ok = false; }
  if !lru_contains(3) { ok = false; }
  if !ok_is(lru_last_evicted(), 2) { ok = false; }
  if !ok_is(lru_touch(1), 10) { ok = false; }
  if !err_is(lru_touch(99), 3, 99, -1) { ok = false; }
  if !stats_is(lru_stats(), 0, 0, 1, 2) { ok = false; }
  return assert(ok, "LRU touch refreshes recency without counting a hit");
}

fn t5() -> TestResult {
  var ok = ok_is(lru_create(1), 1);
  if lru_capacity() != 1 { ok = false; }
  if !ok_is(lru_put(1, 11), 0) { ok = false; }
  if !ok_is(lru_get(1), 11) { ok = false; }
  if !ok_is(lru_put(2, 22), 1) { ok = false; }
  if lru_contains(1) { ok = false; }
  if !lru_contains(2) { ok = false; }
  if !err_is(lru_get(1), 3, 1, -1) { ok = false; }
  if !ok_is(lru_get(2), 22) { ok = false; }
  if !ok_is(lru_peek(2), 22) { ok = false; }
  if lru_len() != 1 { ok = false; }
  if !ok_is(lru_remove(2), 22) { ok = false; }
  if lru_len() != 0 { ok = false; }
  if !err_is(lru_evict_one(), 5, -1, -1) { ok = false; }
  if !stats_is(lru_stats(), 2, 1, 1, 0) { ok = false; }
  return assert(ok, "LRU capacity 1 evicts the only entry on the next put");
}

fn t6() -> TestResult {
  var ok = ok_is(lru_create(2), 2);
  if !ok_is(lru_put(1, 10), 0) { ok = false; }
  if !ok_is(lru_put(2, 20), 0) { ok = false; }
  if !ok_is(lru_put(1, 99), 0) { ok = false; }
  if lru_len() != 2 { ok = false; }
  if !ok_is(lru_get(1), 99) { ok = false; }
  if !ok_is(lru_get(2), 20) { ok = false; }
  if !ok_is(lru_put(3, 30), 1) { ok = false; }
  if !ok_is(lru_last_evicted(), 1) { ok = false; }
  if lru_contains(1) { ok = false; }
  if !lru_contains(3) { ok = false; }
  if !lru_contains(2) { ok = false; }
  if !stats_is(lru_stats(), 2, 0, 1, 2) { ok = false; }
  return assert(ok, "LRU update replaces the value and refreshes recency");
}

fn t7() -> TestResult {
  var ok = ok_is(lru_create(3), 3);
  if !ok_is(lru_put(1, 10), 0) { ok = false; }
  if !ok_is(lru_put(2, 20), 0) { ok = false; }
  if !ok_is(lru_remove(1), 10) { ok = false; }
  if lru_len() != 1 { ok = false; }
  if lru_contains(1) { ok = false; }
  if !err_is(lru_remove(1), 3, 1, -1) { ok = false; }
  if !err_is(lru_last_evicted(), 6, -1, -1) { ok = false; }
  if !ok_is(lru_put(3, 30), 0) { ok = false; }
  if !ok_is(lru_get(2), 20) { ok = false; }
  if !ok_is(lru_get(3), 30) { ok = false; }
  if !stats_is(lru_stats(), 2, 0, 0, 2) { ok = false; }
  return assert(ok, "LRU remove is explicit: no eviction counter, slot reused");
}

fn t8() -> TestResult {
  var ok = ok_is(lru_create(3), 3);
  if !err_is(lru_evict_one(), 5, -1, -1) { ok = false; }
  if !ok_is(lru_put(1, 10), 0) { ok = false; }
  if !ok_is(lru_put(2, 20), 0) { ok = false; }
  if !ok_is(lru_put(3, 30), 0) { ok = false; }
  if !ok_is(lru_evict_one(), 1) { ok = false; }
  if !ok_is(lru_last_evicted(), 1) { ok = false; }
  if !ok_is(lru_evict_one(), 2) { ok = false; }
  if !ok_is(lru_evict_one(), 3) { ok = false; }
  if !err_is(lru_evict_one(), 5, -1, -1) { ok = false; }
  if !ok_is(lru_last_evicted(), 3) { ok = false; }
  if !stats_is(lru_stats(), 0, 0, 3, 0) { ok = false; }
  return assert(ok, "LRU evict_one walks the recency order and records it");
}

fn t9() -> TestResult {
  var ok = ok_is(lru_create(4), 4);
  if !ok_is(lru_put(1, 10), 0) { ok = false; }
  if !ok_is(lru_put(2, 20), 0) { ok = false; }
  if !ok_is(lru_put(3, 30), 0) { ok = false; }
  if !ok_is(lru_put(4, 40), 0) { ok = false; }
  if !ok_is(lru_get(1), 10) { ok = false; }
  if !ok_is(lru_evict_one(), 2) { ok = false; }
  if !stats_is(lru_stats(), 1, 0, 1, 3) { ok = false; }
  lru_clear();
  if lru_len() != 0 { ok = false; }
  if lru_capacity() != 4 { ok = false; }
  if !stats_is(lru_stats(), 0, 0, 0, 0) { ok = false; }
  if !err_is(lru_last_evicted(), 6, -1, -1) { ok = false; }
  if !ok_is(lru_put(1, 10), 0) { ok = false; }
  if !ok_is(lru_put(2, 20), 0) { ok = false; }
  if !ok_is(lru_put(3, 30), 0) { ok = false; }
  if !ok_is(lru_put(4, 40), 0) { ok = false; }
  if !ok_is(lru_put(5, 50), 1) { ok = false; }
  if !ok_is(lru_last_evicted(), 1) { ok = false; }
  return assert(ok, "LRU clear is a full reset that preserves capacity");
}

fn t10() -> TestResult {
  var ok = ok_is(lru_create(2), 2);
  if !ok_is(lru_put(1, 10), 0) { ok = false; }
  if !ok_is(lru_put(2, 20), 0) { ok = false; }
  if !ok_is(lru_get(1), 10) { ok = false; }
  if !err_is(lru_get(5), 3, 5, -1) { ok = false; }
  if !ok_is(lru_put(3, 30), 1) { ok = false; }
  if !ok_is(lru_evict_one(), 1) { ok = false; }
  if !stats_is(lru_stats(), 1, 1, 2, 1) { ok = false; }
  return assert(ok, "LRU stats: hits, misses, evictions and size are exact");
}

fn t11() -> TestResult {
  var ok = ok_is(lfu_create(3), 3);
  if !ok_is(lfu_put(1, 10), 0) { ok = false; }
  if !ok_is(lfu_put(2, 20), 0) { ok = false; }
  if !ok_is(lfu_put(3, 30), 0) { ok = false; }
  if !ok_is(lfu_get(1), 10) { ok = false; }
  if !ok_is(lfu_get(1), 10) { ok = false; }
  if !ok_is(lfu_get(2), 20) { ok = false; }
  if !ok_is(lfu_evict_one(), 3) { ok = false; }
  if !ok_is(lfu_last_evicted(), 3) { ok = false; }
  if !ok_is(lfu_evict_one(), 2) { ok = false; }
  if !ok_is(lfu_evict_one(), 1) { ok = false; }
  if !err_is(lfu_evict_one(), 5, -1, -1) { ok = false; }
  if !stats_is(lfu_stats(), 3, 0, 3, 0) { ok = false; }
  return assert(ok, "LFU evicts by lowest frequency first");
}

fn t12() -> TestResult {
  var ok = ok_is(lfu_create(2), 2);
  if !ok_is(lfu_put(10, 100), 0) { ok = false; }
  if !ok_is(lfu_put(20, 200), 0) { ok = false; }
  if !ok_is(lfu_evict_one(), 10) { ok = false; }
  if !ok_is(lfu_put(30, 300), 0) { ok = false; }
  if !ok_is(lfu_evict_one(), 20) { ok = false; }
  if !lfu_contains(30) { ok = false; }
  if !ok_is(lfu_create(3), 3) { ok = false; }
  if !ok_is(lfu_put(1, 10), 0) { ok = false; }
  if !ok_is(lfu_put(2, 20), 0) { ok = false; }
  if !ok_is(lfu_put(1, 99), 0) { ok = false; }
  if !ok_is(lfu_get(2), 20) { ok = false; }
  if !ok_is(lfu_evict_one(), 1) { ok = false; }
  if lfu_contains(1) { ok = false; }
  if !lfu_contains(2) { ok = false; }
  return assert(ok, "LFU ties break by insertion order and updates keep the ordinal");
}

fn t13() -> TestResult {
  var ok = ok_is(lfu_create(2), 2);
  if !err_is(lfu_evict_one(), 5, -1, -1) { ok = false; }
  if !ok_is(lfu_put(1, 10), 0) { ok = false; }
  if !ok_is(lfu_put(2, 20), 0) { ok = false; }
  if !ok_is(lfu_get(1), 10) { ok = false; }
  if !ok_is(lfu_put(3, 30), 1) { ok = false; }
  if !ok_is(lfu_last_evicted(), 2) { ok = false; }
  if lfu_contains(2) { ok = false; }
  if !lfu_contains(1) { ok = false; }
  if !lfu_contains(3) { ok = false; }
  if lfu_len() != 2 { ok = false; }
  if !stats_is(lfu_stats(), 1, 0, 1, 2) { ok = false; }
  return assert(ok, "LFU frequency protects a key from capacity eviction");
}

fn t14() -> TestResult {
  var ok = ok_is(clock_create(3), 3);
  if !ok_is(clock_put(1, 10), 0) { ok = false; }
  if !ok_is(clock_put(2, 20), 0) { ok = false; }
  if !ok_is(clock_put(3, 30), 0) { ok = false; }
  if !ok_is(clock_evict_one(), 1) { ok = false; }
  if !ok_is(clock_last_evicted(), 1) { ok = false; }
  if !ok_is(clock_put(4, 40), 0) { ok = false; }
  if !ok_is(clock_evict_one(), 2) { ok = false; }
  if !ok_is(clock_evict_one(), 3) { ok = false; }
  if !ok_is(clock_put(5, 50), 0) { ok = false; }
  if !ok_is(clock_evict_one(), 4) { ok = false; }
  if !ok_is(clock_evict_one(), 5) { ok = false; }
  if !ok_is(clock_last_evicted(), 5) { ok = false; }
  if !err_is(clock_evict_one(), 5, -1, -1) { ok = false; }
  if !stats_is(clock_stats(), 0, 0, 5, 0) { ok = false; }
  return assert(ok, "CLOCK sweep order is fully determined by the hand");
}

fn t15() -> TestResult {
  var ok = ok_is(clock_create(3), 3);
  if !ok_is(clock_put(1, 10), 0) { ok = false; }
  if !ok_is(clock_put(2, 20), 0) { ok = false; }
  if !ok_is(clock_put(3, 30), 0) { ok = false; }
  if !ok_is(clock_evict_one(), 1) { ok = false; }
  if !ok_is(clock_put(4, 40), 0) { ok = false; }
  if !ok_is(clock_get(2), 20) { ok = false; }
  if !ok_is(clock_evict_one(), 3) { ok = false; }
  if !clock_contains(2) { ok = false; }
  if !clock_contains(4) { ok = false; }
  if !ok_is(clock_evict_one(), 2) { ok = false; }
  if !ok_is(clock_evict_one(), 4) { ok = false; }
  if !err_is(clock_evict_one(), 5, -1, -1) { ok = false; }
  return assert(ok, "CLOCK ref bits give entries a second chance");
}

fn t16() -> TestResult {
  var ok = ok_is(ttl_create(3), 3);
  if !ok_is(ttl_put(1, 10, 0, 10), 0) { ok = false; }
  if ttl_len() != 1 { ok = false; }
  if !ttl_contains(1, 9) { ok = false; }
  if !ok_is(ttl_get(1, 9), 10) { ok = false; }
  if !err_is(ttl_peek(1, 10), 4, 1, 10) { ok = false; }
  if ttl_len() != 1 { ok = false; }
  if !err_is(ttl_get(1, 10), 4, 1, 10) { ok = false; }
  if ttl_len() != 0 { ok = false; }
  if !ok_is(ttl_last_evicted(), 1) { ok = false; }
  if !err_is(ttl_get(1, 10), 3, 1, -1) { ok = false; }
  if !stats_is(ttl_stats(), 1, 2, 1, 0) { ok = false; }
  return assert(ok, "TTL get at exp <= now is an expired removal");
}

fn t17() -> TestResult {
  var ok = ok_is(ttl_create(4), 4);
  if !ok_is(ttl_put(1, 10, 0, 10), 0) { ok = false; }
  if !ok_is(ttl_put(2, 20, 0, 20), 0) { ok = false; }
  if !ok_is(ttl_put(3, 30, 0, 30), 0) { ok = false; }
  if !ok_is(ttl_sweep(9), 0) { ok = false; }
  if ttl_len() != 3 { ok = false; }
  if !ok_is(ttl_sweep(10), 1) { ok = false; }
  if !ok_is(ttl_last_evicted(), 1) { ok = false; }
  if ttl_contains(1, 10) { ok = false; }
  if ttl_len() != 2 { ok = false; }
  if !ok_is(ttl_sweep(19), 0) { ok = false; }
  if !ok_is(ttl_get(2, 19), 20) { ok = false; }
  if !ok_is(ttl_sweep(30), 2) { ok = false; }
  if !ok_is(ttl_last_evicted(), 3) { ok = false; }
  if ttl_len() != 0 { ok = false; }
  if !ok_is(ttl_sweep(1000), 0) { ok = false; }
  if !stats_is(ttl_stats(), 1, 0, 3, 0) { ok = false; }
  return assert(ok, "TTL sweep evicts exp <= now in insertion order");
}

fn t18() -> TestResult {
  var ok = ok_is(ttl_create(3), 3);
  if !ok_is(ttl_put(1, 10, 0, 10), 0) { ok = false; }
  if !ok_is(ttl_put(2, 20, 0, 20), 0) { ok = false; }
  if !ok_is(ttl_put(1, 11, 5, 20), 0) { ok = false; }
  if !ok_is(ttl_sweep(20), 2) { ok = false; }
  if !ok_is(ttl_last_evicted(), 1) { ok = false; }
  if ttl_len() != 0 { ok = false; }
  return assert(ok, "TTL put moves the entry to the newest insertion position");
}

fn t19() -> TestResult {
  var ok = ok_is(ttl_create(2), 2);
  if !ok_is(ttl_put(1, 10, 0, 50), 0) { ok = false; }
  if !ok_is(ttl_put(2, 20, 0, 60), 0) { ok = false; }
  if !ok_is(ttl_put(3, 30, 0, 70), 1) { ok = false; }
  if !ok_is(ttl_last_evicted(), 1) { ok = false; }
  if ttl_contains(1, 0) { ok = false; }
  if !ttl_contains(2, 0) { ok = false; }
  if !ttl_contains(3, 0) { ok = false; }
  if !ok_is(ttl_put(4, 40, 0, 65), 1) { ok = false; }
  if !ok_is(ttl_last_evicted(), 2) { ok = false; }
  if ttl_contains(2, 0) { ok = false; }
  if !ttl_contains(3, 0) { ok = false; }
  if !ttl_contains(4, 0) { ok = false; }
  if !ok_is(ttl_create(2), 2) { ok = false; }
  if !ok_is(ttl_put(5, 50, 0, 40), 0) { ok = false; }
  if !ok_is(ttl_put(6, 60, 0, 40), 0) { ok = false; }
  if !ok_is(ttl_put(7, 70, 0, 80), 1) { ok = false; }
  if !ok_is(ttl_last_evicted(), 5) { ok = false; }
  return assert(ok, "TTL capacity eviction takes the earliest expire tick");
}

fn t20() -> TestResult {
  var ok = ok_is(ttl_create(3), 3);
  if !ok_is(ttl_put(1, 11, 0, 10), 0) { ok = false; }
  if !ok_is(ttl_peek(1, 5), 11) { ok = false; }
  if !err_is(ttl_peek(1, 10), 4, 1, 10) { ok = false; }
  if ttl_len() != 1 { ok = false; }
  if ttl_contains(1, 10) { ok = false; }
  if !ttl_contains(1, 9) { ok = false; }
  if !ok_is(ttl_remove(1), 11) { ok = false; }
  if ttl_len() != 0 { ok = false; }
  if !err_is(ttl_remove(1), 3, 1, -1) { ok = false; }
  if !err_is(ttl_last_evicted(), 6, -1, -1) { ok = false; }
  if !ok_is(ttl_put(2, 22, 0, 10), 0) { ok = false; }
  if !ok_is(ttl_remove(2), 22) { ok = false; }
  if !stats_is(ttl_stats(), 0, 0, 0, 0) { ok = false; }
  return assert(ok, "TTL peek/contains/remove never count as evictions");
}

fn t21() -> TestResult {
  var ok = ok_is(ttl_create(3), 3);
  if !err_is(ttl_put(1, 10, 10, 10), 7, 1, 10) { ok = false; }
  if !err_is(ttl_put(1, 10, 10, 5), 7, 1, 5) { ok = false; }
  if ttl_len() != 0 { ok = false; }
  if !ok_is(ttl_put(1, 10, 0, 10), 0) { ok = false; }
  if !ok_is(ttl_put(1, 20, 10, 50), 1) { ok = false; }
  if !ok_is(ttl_last_evicted(), 1) { ok = false; }
  if ttl_len() != 1 { ok = false; }
  if !ok_is(ttl_get(1, 11), 20) { ok = false; }
  if !stats_is(ttl_stats(), 1, 0, 1, 1) { ok = false; }
  return assert(ok, "TTL rejects past expiry; put over an expired key re-inserts");
}

fn t22() -> TestResult {
  var ok = ok_is(ttl_create(2), 2);
  if !err_is(ttl_evict_one(), 5, -1, -1) { ok = false; }
  if !ok_is(ttl_put(1, 10, 0, 100), 0) { ok = false; }
  if !ok_is(ttl_put(2, 20, 0, 100), 0) { ok = false; }
  if !ok_is(ttl_get(1, 5), 10) { ok = false; }
  if !err_is(ttl_get(9, 5), 3, 9, -1) { ok = false; }
  if !err_is(ttl_get(2, 200), 4, 2, 100) { ok = false; }
  if !ok_is(ttl_evict_one(), 1) { ok = false; }
  if !err_is(ttl_evict_one(), 5, -1, -1) { ok = false; }
  if !stats_is(ttl_stats(), 1, 2, 2, 0) { ok = false; }
  return assert(ok, "TTL stats count expired-on-get as miss plus eviction");
}

fn t23() -> TestResult {
  var ok = ok_is(lfu_create(2), 2);
  if !ok_is(lfu_put(1, 10), 0) { ok = false; }
  if !ok_is(lfu_get(1), 10) { ok = false; }
  lfu_clear();
  if lfu_len() != 0 { ok = false; }
  if lfu_capacity() != 2 { ok = false; }
  if !stats_is(lfu_stats(), 0, 0, 0, 0) { ok = false; }
  if !err_is(lfu_last_evicted(), 6, -1, -1) { ok = false; }
  if !ok_is(clock_create(3), 3) { ok = false; }
  if !ok_is(clock_put(1, 10), 0) { ok = false; }
  clock_clear();
  if clock_len() != 0 { ok = false; }
  if clock_capacity() != 3 { ok = false; }
  if !ok_is(clock_put(2, 20), 0) { ok = false; }
  if !ok_is(clock_evict_one(), 2) { ok = false; }
  if !ok_is(ttl_create(4), 4) { ok = false; }
  if !ok_is(ttl_put(1, 10, 0, 100), 0) { ok = false; }
  ttl_clear();
  if ttl_len() != 0 { ok = false; }
  if ttl_capacity() != 4 { ok = false; }
  if !stats_is(ttl_stats(), 0, 0, 0, 0) { ok = false; }
  return assert(ok, "clear is a full reset on LFU, CLOCK and TTL too");
}

fn t24() -> TestResult {
  var ok = msg_is(1, "cache: capacity must be positive");
  if !msg_is(2, "cache: capacity exceeds maximum") { ok = false; }
  if !msg_is(3, "cache: unknown key") { ok = false; }
  if !msg_is(4, "cache: entry expired") { ok = false; }
  if !msg_is(5, "cache: cache is empty") { ok = false; }
  if !msg_is(6, "cache: no eviction yet") { ok = false; }
  if !msg_is(7, "cache: expiry must be in the future") { ok = false; }
  if !msg_is(99, "cache: unknown error") { ok = false; }
  return assert(ok, "error catalog messages are pinned");
}

fn t25() -> TestResult {
  var ok = ok_is(lru_create(2), 2);
  if !ok_is(lfu_create(2), 2) { ok = false; }
  if !ok_is(clock_create(2), 2) { ok = false; }
  if !ok_is(ttl_create(2), 2) { ok = false; }
  if !ok_is(lru_put(1, 10), 0) { ok = false; }
  if !ok_is(lfu_put(2, 20), 0) { ok = false; }
  if !ok_is(clock_put(3, 30), 0) { ok = false; }
  if !ok_is(ttl_put(4, 40, 0, 100), 0) { ok = false; }
  if !lru_contains(1) { ok = false; }
  if lru_contains(2) { ok = false; }
  if !lfu_contains(2) { ok = false; }
  if lfu_contains(1) { ok = false; }
  if !clock_contains(3) { ok = false; }
  if !ttl_contains(4, 0) { ok = false; }
  if lru_len() != 1 { ok = false; }
  if lfu_len() != 1 { ok = false; }
  if clock_len() != 1 { ok = false; }
  if ttl_len() != 1 { ok = false; }
  return assert(ok, "the four policy singletons never share state");
}

// One fixed LRU scenario; the returned vector holds the pinned observations
// [put4-evicts-2, evict_one-key, final len, evictions]; any failed step
// appends a negative marker so the replay comparison fails loudly.
fn lru_scenario() -> Vec[Int] {
  var out = Vec[Int].new();
  let c = lru_create(3);
  if !ok_is(c, 3) { out.push(-1); }
  let p1 = lru_put(1, 10);
  if !ok_is(p1, 0) { out.push(-2); }
  let p2 = lru_put(2, 20);
  if !ok_is(p2, 0) { out.push(-3); }
  let p3 = lru_put(3, 30);
  if !ok_is(p3, 0) { out.push(-4); }
  let g1 = lru_get(1);
  if !ok_is(g1, 10) { out.push(-5); }
  let p4 = lru_put(4, 40);
  if !ok_is(p4, 1) { out.push(-6); }
  let le = lru_last_evicted();
  if ok_is(le, 2) { out.push(2); } else { out.push(-7); }
  let e1 = lru_evict_one();
  if ok_is(e1, 3) { out.push(3); } else { out.push(-8); }
  out.push(lru_len());
  let st: CacheStats = lru_stats();
  out.push(st.evictions);
  return out;
}

fn t26() -> TestResult {
  let a = lru_scenario();
  let b = lru_scenario();
  var ok = a.len() == 4;
  if b.len() != 4 { ok = false; }
  if ok {
    let a0: Int = a[0];
    let a1: Int = a[1];
    let a2: Int = a[2];
    let a3: Int = a[3];
    let b0: Int = b[0];
    let b1: Int = b[1];
    let b2: Int = b[2];
    let b3: Int = b[3];
    if a0 != 2 { ok = false; }
    if a1 != 3 { ok = false; }
    if a2 != 2 { ok = false; }
    if a3 != 2 { ok = false; }
    if a0 != b0 { ok = false; }
    if a1 != b1 { ok = false; }
    if a2 != b2 { ok = false; }
    if a3 != b3 { ok = false; }
  }
  return assert(ok, "replaying one LRU scenario yields identical evictions");
}

fn main() -> Int {
  io.println("=== xiom.cache conformance tests ===");
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
    io.println("xiom.cache: all tests passed");
  } else {
    io.println("xiom.cache: tests failed");
  }
  return failed;
}
