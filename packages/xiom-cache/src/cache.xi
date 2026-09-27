// XIOM -- xiom.cache: deterministic in-memory cache eviction structures
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Scope (full rules in SPEC.md):
//   * Four capacity-bounded cache policies over Int keys and Int values:
//     LRU (recency list + hash index), LFU (frequency counters with an
//     insertion-order tie-break), CLOCK (reference bits + hand pointer) and
//     TTL (absolute expire ticks + insertion-order sweep). No threads, no
//     clocks, no FFI: every decision follows from the call sequence alone.
//   * Each policy is a module-level singleton, like the xiom.timer wheel:
//     <policy>_create(capacity) is a full reset of that policy's entries,
//     counters and last-evicted record. Two live caches of the same policy
//     cannot coexist; the four policies never interact.
//   * Uniform API per policy: create, put, get, peek, remove, evict_one,
//     clear, len, contains, capacity, stats, last_evicted (LRU also has
//     touch).
//   * LRU is O(1) expected per operation: a separate-chaining hash index
//     over a 32-bit mixing hash (buckets/hnext/hprev), a doubly linked
//     recency list (prev/next: head = least recently used) and a free list
//     threaded through hnext. LFU, CLOCK and TTL locate keys by scanning
//     the slot table: O(capacity) worst case with capacity <= 2^20.
//   * Only get moves hits/misses. Evictions are policy removals, capacity
//     replacements and TTL expired removals only; explicit remove and clear
//     are not evictions. Every eviction records its key for
//     <policy>_last_evicted.
//
// v0.61.3 notes that shaped this module:
//   * free functions only; module-level parallel Vec[Int] state; no methods,
//     no lambdas, no Vec[StructType], no casts, no bitwise AND/OR/shifts;
//   * every Vec[Int] read goes through a typed local;
//   * Ok/Err are constructed only in _ca_ok_int/_ca_err_int;
//   * arithmetic is +, -, *, /, % (truncating) and ^ (mixing hash only);
//   * no &mut Int out-parameters: every helper returns its result.

module xiom.cache

// --------------------------------------------------
//  Constants
// --------------------------------------------------

// Largest capacity any policy may declare.
const _CA_MAX_CAPACITY: Int = 1048576;

// Capacity lazily created on first use when <policy>_create was never called.
const _CA_DEFAULT_CAPACITY: Int = 16;

// "Not applicable" filler for unused CacheError fields and list ends.
const _CA_NONE: Int = -1;

// 2^32, the modulus of the mixing hash.
const _CA_U32_MOD: Int = 4294967296;

// Mixing-hash constants (0x9E3779B9 and 0x85EBCA6B).
const _CA_MIX_A: Int = 2654435761;
const _CA_MIX_B: Int = 2246822519;

// CacheError codes (pinned messages in cache_error_message).
const _CA_ERR_CAPACITY_POSITIVE: Int = 1;
const _CA_ERR_CAPACITY_MAX: Int = 2;
const _CA_ERR_UNKNOWN_KEY: Int = 3;
const _CA_ERR_EXPIRED: Int = 4;
const _CA_ERR_EMPTY: Int = 5;
const _CA_ERR_NO_EVICTION: Int = 6;
const _CA_ERR_EXPIRY_PAST: Int = 7;

// --------------------------------------------------
//  Types
// --------------------------------------------------

/// Typed error carried by every fallible cache operation.
/// `code` identifies the failure (see cache_error_message). `key` carries
/// the offending key where the rule mentions one, else -1. `detail` carries
/// the offending capacity for codes 1..2, the stale expire tick for code 4
/// and the rejected expire tick for code 7, else -1.
pub type CacheError = {
  code: Int;
  key: Int;
  detail: Int;
}

/// Counter snapshot of one policy, returned by <policy>_stats.
/// hits/misses are moved by get only; evictions counts policy removals,
/// capacity replacements and expired removals; size is the number of
/// physically present entries (TTL: expired but unswept entries still count).
pub type CacheStats = {
  hits: Int;
  misses: Int;
  evictions: Int;
  size: Int;
}

// --------------------------------------------------
//  Result leaves
// --------------------------------------------------

// Ok(v) for Result[Int, CacheError].
fn _ca_ok_int(v: Int) -> Result[Int, CacheError] {
  return Ok(v);
}

// Err(code, key, detail) for Result[Int, CacheError].
fn _ca_err_int(code: Int, key: Int, detail: Int) -> Result[Int, CacheError] {
  let e = CacheError{ code: code; key: key; detail: detail; };
  return Err(e);
}

// --------------------------------------------------
//  Shared arithmetic
// --------------------------------------------------

// (a * b) mod 2^32 for 0 <= a, b < 2^32, computed exactly by splitting the
// operands into 16-bit halves (a raw 32x32 product can overflow Int).
fn _ca_mul32(a: Int, b: Int) -> Int {
  let ahi = a / 65536;
  let alo = a % 65536;
  let bhi = b / 65536;
  let blo = b % 65536;
  let mid1 = (ahi * blo) % 65536;
  let mid2 = (alo * bhi) % 65536;
  let low = alo * blo;
  return (mid1 * 65536 + mid2 * 65536 + low) % _CA_U32_MOD;
}

// Deterministic mixing hash of any Int key, in 0..2^32-1: the key is reduced
// to its non-negative 32-bit representative, then two multiplicative rounds
// with an add-shift finalizer.
fn _ca_mix(key: Int) -> Int {
  var h = key % _CA_U32_MOD;
  if h < 0 {
    h = h + _CA_U32_MOD;
  }
  h = _ca_mul32(h, _CA_MIX_A);
  h = (h + h / 65536) % _CA_U32_MOD;
  h = _ca_mul32(h, _CA_MIX_B);
  h = (h + h / 65536) % _CA_U32_MOD;
  return h;
}

// Bucket index of `key` for a table with `nbuckets` buckets (>= 1).
fn _ca_bucket(key: Int, nbuckets: Int) -> Int {
  return _ca_mix(key) % nbuckets;
}

// 0 when `capacity` is valid, else code 1 (non-positive) or code 2 (above
// cache_max_capacity).
fn _ca_capacity_code(capacity: Int) -> Int {
  if capacity <= 0 {
    return _CA_ERR_CAPACITY_POSITIVE;
  }
  if capacity > _CA_MAX_CAPACITY {
    return _CA_ERR_CAPACITY_MAX;
  }
  return 0;
}

// --------------------------------------------------
//  Shared accessors and error catalog
// --------------------------------------------------

/// Largest capacity any policy may declare: 1048576. Error case: none.
/// Complexity: O(1).
pub fn cache_max_capacity() -> Int {
  return _CA_MAX_CAPACITY;
}

/// Pinned message for a CacheError code; "cache: unknown error" for codes
/// outside the catalog. Complexity: O(1).
pub fn cache_error_message(code: Int) -> Str {
  if code == _CA_ERR_CAPACITY_POSITIVE {
    return "cache: capacity must be positive";
  }
  if code == _CA_ERR_CAPACITY_MAX {
    return "cache: capacity exceeds maximum";
  }
  if code == _CA_ERR_UNKNOWN_KEY {
    return "cache: unknown key";
  }
  if code == _CA_ERR_EXPIRED {
    return "cache: entry expired";
  }
  if code == _CA_ERR_EMPTY {
    return "cache: cache is empty";
  }
  if code == _CA_ERR_NO_EVICTION {
    return "cache: no eviction yet";
  }
  if code == _CA_ERR_EXPIRY_PAST {
    return "cache: expiry must be in the future";
  }
  return "cache: unknown error";
}

// ==================================================================
//  LRU -- least recently used, O(1) expected per operation
// ==================================================================
//
// Data model (parallel Vec[Int] fields, all length = capacity):
//   keys/vals   payload of each slot; meaningful while alive == 1
//   prev/next   doubly linked recency list; head (prev == -1) is the least
//               recently used slot, tail (next == -1) the most recent
//   hnext/hprev separate-chaining hash index; hnext is also the free-list
//               link while a slot is dead, hprev is -1 in that state
//   alive       1 = slot holds a live entry, 0 = slot is free
//   buckets     bucket heads of the hash index, length = capacity
// Eviction always takes the recency-list head. get/put/touch on an existing
// key move the slot to the tail. Every step is O(1): find and unlink use
// hprev/hnext, the recency list uses prev/next, allocation uses the free
// list head threaded through hnext.

// --- state ---
var _lru_ready: Bool = false;
var _lru_cap: Int = 0;
var _lru_count: Int = 0;
var _lru_nbuckets: Int = 0;
var _lru_free: Int = _CA_NONE;
var _lru_head: Int = _CA_NONE;
var _lru_tail: Int = _CA_NONE;
var _lru_hits: Int = 0;
var _lru_misses: Int = 0;
var _lru_evictions: Int = 0;
var _lru_last: Int = 0;
var _lru_has_last: Bool = false;
var _lru_keys: Vec[Int] = Vec[Int].new();
var _lru_vals: Vec[Int] = Vec[Int].new();
var _lru_prev: Vec[Int] = Vec[Int].new();
var _lru_next: Vec[Int] = Vec[Int].new();
var _lru_hnext: Vec[Int] = Vec[Int].new();
var _lru_hprev: Vec[Int] = Vec[Int].new();
var _lru_alive: Vec[Int] = Vec[Int].new();
var _lru_buckets: Vec[Int] = Vec[Int].new();

// --- internals ---

// Rebuild the whole LRU state for a validated capacity >= 1: every slot is
// free, the free list is 0 -> 1 -> ... -> capacity-1, all lists and counters
// are empty. Complexity: O(capacity).
fn _lru_reset(capacity: Int) {
  _lru_cap = capacity;
  _lru_count = 0;
  _lru_nbuckets = capacity;
  _lru_free = 0;
  _lru_head = _CA_NONE;
  _lru_tail = _CA_NONE;
  _lru_hits = 0;
  _lru_misses = 0;
  _lru_evictions = 0;
  _lru_last = 0;
  _lru_has_last = false;
  _lru_keys.clear();
  _lru_vals.clear();
  _lru_prev.clear();
  _lru_next.clear();
  _lru_hnext.clear();
  _lru_hprev.clear();
  _lru_alive.clear();
  _lru_buckets.clear();
  var i = 0;
  while i < capacity {
    _lru_keys.push(0);
    _lru_vals.push(0);
    _lru_prev.push(_CA_NONE);
    _lru_next.push(_CA_NONE);
    _lru_hnext.push(i + 1);
    _lru_hprev.push(_CA_NONE);
    _lru_alive.push(0);
    _lru_buckets.push(_CA_NONE);
    i = i + 1;
  }
  _lru_hnext[capacity - 1] = _CA_NONE;
  _lru_ready = true;
}

// Lazy default so the API is usable without an explicit create (same
// discipline as the xiom.timer wheel).
fn _lru_ensure() {
  if !_lru_ready {
    _lru_reset(_CA_DEFAULT_CAPACITY);
  }
}

// Slot holding `key`, or -1. Walks one hash chain.
fn _lru_find(key: Int) -> Int {
  let b = _ca_bucket(key, _lru_nbuckets);
  var cur: Int = _lru_buckets[b];
  while cur >= 0 {
    let al: Int = _lru_alive[cur];
    if al == 1 {
      let k: Int = _lru_keys[cur];
      if k == key {
        return cur;
      }
    }
    let nx: Int = _lru_hnext[cur];
    cur = nx;
  }
  return _CA_NONE;
}

// Push slot into the hash chain of its key, at the bucket head.
fn _lru_link(slot: Int, key: Int) {
  let b = _ca_bucket(key, _lru_nbuckets);
  let head: Int = _lru_buckets[b];
  _lru_hnext[slot] = head;
  _lru_hprev[slot] = _CA_NONE;
  if head >= 0 {
    _lru_hprev[head] = slot;
  }
  _lru_buckets[b] = slot;
}

// Unlink a live slot from its hash chain. `key` must be the slot's key.
fn _lru_unlink(slot: Int, key: Int) {
  let p: Int = _lru_hprev[slot];
  let n: Int = _lru_hnext[slot];
  if p < 0 {
    let b = _ca_bucket(key, _lru_nbuckets);
    _lru_buckets[b] = n;
  } else {
    _lru_hnext[p] = n;
  }
  if n >= 0 {
    _lru_hprev[n] = p;
  }
  _lru_hnext[slot] = _CA_NONE;
  _lru_hprev[slot] = _CA_NONE;
}

// Reserve a free slot (free-list head), or -1 when the cache is full.
fn _lru_alloc() -> Int {
  let slot: Int = _lru_free;
  if slot < 0 {
    return _CA_NONE;
  }
  _lru_free = _lru_hnext[slot];
  _lru_alive[slot] = 1;
  _lru_prev[slot] = _CA_NONE;
  _lru_next[slot] = _CA_NONE;
  _lru_hnext[slot] = _CA_NONE;
  _lru_hprev[slot] = _CA_NONE;
  return slot;
}

// Release a slot whose hash link was already removed: it joins the free
// list and the live count drops by one.
fn _lru_release(slot: Int) {
  _lru_alive[slot] = 0;
  _lru_prev[slot] = _CA_NONE;
  _lru_next[slot] = _CA_NONE;
  _lru_hprev[slot] = _CA_NONE;
  _lru_hnext[slot] = _lru_free;
  _lru_free = slot;
  _lru_count = _lru_count - 1;
}

// Detach a linked slot from the recency list. The slot must currently be in
// the list (every live slot is, except transiently during insert).
fn _lru_dll_remove(slot: Int) {
  let p: Int = _lru_prev[slot];
  let n: Int = _lru_next[slot];
  if p < 0 {
    _lru_head = n;
  } else {
    _lru_next[p] = n;
  }
  if n < 0 {
    _lru_tail = p;
  } else {
    _lru_prev[n] = p;
  }
  _lru_prev[slot] = _CA_NONE;
  _lru_next[slot] = _CA_NONE;
}

// Append a not-yet-linked slot as the recency-list tail (most recently used).
fn _lru_dll_append(slot: Int) {
  let tail: Int = _lru_tail;
  _lru_prev[slot] = tail;
  _lru_next[slot] = _CA_NONE;
  if tail < 0 {
    _lru_head = slot;
  } else {
    _lru_next[tail] = slot;
  }
  _lru_tail = slot;
}

// Move a live slot to the recency-list tail (most recently used).
fn _lru_touch_slot(slot: Int) {
  _lru_dll_remove(slot);
  _lru_dll_append(slot);
}

// Policy-evict a live slot: detach it from the recency list and the hash
// index, release it, then record the eviction. Complexity: O(1) expected.
fn _lru_evict_slot(slot: Int) {
  let k: Int = _lru_keys[slot];
  _lru_dll_remove(slot);
  _lru_unlink(slot, k);
  _lru_release(slot);
  _lru_evictions = _lru_evictions + 1;
  _lru_last = k;
  _lru_has_last = true;
}

// --- public API ---

/// Create (or fully reset) the LRU cache with `capacity` slots.
/// Params: capacity - 1..cache_max_capacity().
/// Returns: Ok(capacity).
/// Error case: Err(code 1, key = -1, detail = capacity) when capacity <= 0;
/// Err(code 2, key = -1, detail = capacity) when capacity exceeds
/// cache_max_capacity(). On Err the previous LRU state is unchanged.
/// Complexity: O(capacity).
pub fn lru_create(capacity: Int) -> Result[Int, CacheError] {
  let code: Int = _ca_capacity_code(capacity);
  if code != 0 {
    return _ca_err_int(code, _CA_NONE, capacity);
  }
  _lru_reset(capacity);
  return _ca_ok_int(capacity);
}

/// Insert or update `key`. A new key goes to the most-recently-used end; an
/// update replaces the value and refreshes recency. When the cache is full
/// the least recently used entry is evicted first.
/// Params: key, value - any Int.
/// Returns: Ok(evicted) with evicted = 0 or 1, the number of policy
/// evictions this call caused.
/// Error case: none. Complexity: O(1) expected.
pub fn lru_put(key: Int, value: Int) -> Result[Int, CacheError] {
  _lru_ensure();
  let slot: Int = _lru_find(key);
  if slot >= 0 {
    _lru_vals[slot] = value;
    _lru_touch_slot(slot);
    return _ca_ok_int(0);
  }
  var evicted = 0;
  if _lru_count >= _lru_cap {
    let victim: Int = _lru_head;
    _lru_evict_slot(victim);
    evicted = 1;
  }
  let ns: Int = _lru_alloc();
  _lru_keys[ns] = key;
  _lru_vals[ns] = value;
  _lru_link(ns, key);
  _lru_dll_append(ns);
  _lru_count = _lru_count + 1;
  return _ca_ok_int(evicted);
}

/// Read `key` and mark it most recently used. Moves the hit counter on
/// success and the miss counter when no entry holds `key`.
/// Returns: Ok(value), or Err(code 3, key = key, detail = -1).
/// Complexity: O(1) expected.
pub fn lru_get(key: Int) -> Result[Int, CacheError] {
  _lru_ensure();
  let slot: Int = _lru_find(key);
  if slot < 0 {
    _lru_misses = _lru_misses + 1;
    return _ca_err_int(_CA_ERR_UNKNOWN_KEY, key, _CA_NONE);
  }
  let v: Int = _lru_vals[slot];
  _lru_touch_slot(slot);
  _lru_hits = _lru_hits + 1;
  return _ca_ok_int(v);
}

/// Read `key` without changing recency and without moving hits/misses.
/// Returns: Ok(value), or Err(code 3, key = key, detail = -1).
/// Complexity: O(1) expected.
pub fn lru_peek(key: Int) -> Result[Int, CacheError] {
  _lru_ensure();
  let slot: Int = _lru_find(key);
  if slot < 0 {
    return _ca_err_int(_CA_ERR_UNKNOWN_KEY, key, _CA_NONE);
  }
  let v: Int = _lru_vals[slot];
  return _ca_ok_int(v);
}

/// Mark `key` most recently used without moving the hit counter.
/// Returns: Ok(value), or Err(code 3, key = key, detail = -1).
/// Complexity: O(1) expected.
pub fn lru_touch(key: Int) -> Result[Int, CacheError] {
  _lru_ensure();
  let slot: Int = _lru_find(key);
  if slot < 0 {
    return _ca_err_int(_CA_ERR_UNKNOWN_KEY, key, _CA_NONE);
  }
  let v: Int = _lru_vals[slot];
  _lru_touch_slot(slot);
  return _ca_ok_int(v);
}

/// Remove `key` explicitly. Not an eviction: the eviction counter and the
/// last-evicted record are untouched.
/// Returns: Ok(value), or Err(code 3, key = key, detail = -1).
/// Complexity: O(1) expected.
pub fn lru_remove(key: Int) -> Result[Int, CacheError] {
  _lru_ensure();
  let slot: Int = _lru_find(key);
  if slot < 0 {
    return _ca_err_int(_CA_ERR_UNKNOWN_KEY, key, _CA_NONE);
  }
  let v: Int = _lru_vals[slot];
  _lru_dll_remove(slot);
  _lru_unlink(slot, key);
  _lru_release(slot);
  return _ca_ok_int(v);
}

/// Evict the least recently used entry and record it.
/// Returns: Ok(key), or Err(code 5, key = -1, detail = -1) when empty.
/// Complexity: O(1) expected.
pub fn lru_evict_one() -> Result[Int, CacheError] {
  _lru_ensure();
  if _lru_count == 0 {
    return _ca_err_int(_CA_ERR_EMPTY, _CA_NONE, _CA_NONE);
  }
  let victim: Int = _lru_head;
  let k: Int = _lru_keys[victim];
  _lru_evict_slot(victim);
  return _ca_ok_int(k);
}

/// Remove every entry and reset hits/misses/evictions/last-evicted to their
/// initial state. Capacity is preserved (create is the only capacity change).
/// Complexity: O(capacity).
pub fn lru_clear() {
  _lru_ensure();
  _lru_reset(_lru_cap);
}

/// Number of live entries. Error case: none. Complexity: O(1).
pub fn lru_len() -> Int {
  _lru_ensure();
  return _lru_count;
}

/// Active capacity. Error case: none. Complexity: O(1).
pub fn lru_capacity() -> Int {
  _lru_ensure();
  return _lru_cap;
}

/// True when `key` has a live entry. Error case: none.
/// Complexity: O(1) expected.
pub fn lru_contains(key: Int) -> Bool {
  _lru_ensure();
  return _lru_find(key) >= 0;
}

/// Counter snapshot, including the current size.
pub fn lru_stats() -> CacheStats {
  _lru_ensure();
  return CacheStats{ hits: _lru_hits; misses: _lru_misses; evictions: _lru_evictions; size: _lru_count; };
}

/// Key evicted by the most recent policy eviction of this policy.
/// Returns: Ok(key), or Err(code 6, key = -1, detail = -1) when no eviction
/// has happened since the last create/clear.
pub fn lru_last_evicted() -> Result[Int, CacheError] {
  _lru_ensure();
  if !_lru_has_last {
    return _ca_err_int(_CA_ERR_NO_EVICTION, _CA_NONE, _CA_NONE);
  }
  return _ca_ok_int(_lru_last);
}

// ==================================================================
//  LFU -- least frequently used, insertion-order tie-break
// ==================================================================
//
// Data model (parallel Vec[Int] fields, all length = capacity):
//   keys/vals   payload of each slot; meaningful while alive == 1
//   freq        access count: 1 on insert, +1 on every get and update
//   seq         insertion ordinal, assigned at first insert and preserved
//               across updates; ties on the minimum freq go to the smallest
//               seq (the earliest first insert)
//   alive       1 = live, 0 = free
//   link        free-list link while dead
// Eviction scans all slots for the minimum (freq, seq) pair: O(capacity).

// --- state ---
var _lfu_ready: Bool = false;
var _lfu_cap: Int = 0;
var _lfu_count: Int = 0;
var _lfu_free: Int = _CA_NONE;
var _lfu_seq_next: Int = 1;
var _lfu_hits: Int = 0;
var _lfu_misses: Int = 0;
var _lfu_evictions: Int = 0;
var _lfu_last: Int = 0;
var _lfu_has_last: Bool = false;
var _lfu_keys: Vec[Int] = Vec[Int].new();
var _lfu_vals: Vec[Int] = Vec[Int].new();
var _lfu_freq: Vec[Int] = Vec[Int].new();
var _lfu_seq: Vec[Int] = Vec[Int].new();
var _lfu_alive: Vec[Int] = Vec[Int].new();
var _lfu_link: Vec[Int] = Vec[Int].new();

// --- internals ---

// Rebuild the LFU state for a validated capacity >= 1.
// Complexity: O(capacity).
fn _lfu_reset(capacity: Int) {
  _lfu_cap = capacity;
  _lfu_count = 0;
  _lfu_free = 0;
  _lfu_seq_next = 1;
  _lfu_hits = 0;
  _lfu_misses = 0;
  _lfu_evictions = 0;
  _lfu_last = 0;
  _lfu_has_last = false;
  _lfu_keys.clear();
  _lfu_vals.clear();
  _lfu_freq.clear();
  _lfu_seq.clear();
  _lfu_alive.clear();
  _lfu_link.clear();
  var i = 0;
  while i < capacity {
    _lfu_keys.push(0);
    _lfu_vals.push(0);
    _lfu_freq.push(0);
    _lfu_seq.push(_CA_NONE);
    _lfu_alive.push(0);
    _lfu_link.push(i + 1);
    i = i + 1;
  }
  _lfu_link[capacity - 1] = _CA_NONE;
  _lfu_ready = true;
}

fn _lfu_ensure() {
  if !_lfu_ready {
    _lfu_reset(_CA_DEFAULT_CAPACITY);
  }
}

// Slot holding `key`, or -1. Scans the slot table. Complexity: O(capacity).
fn _lfu_find(key: Int) -> Int {
  var i = 0;
  while i < _lfu_cap {
    let al: Int = _lfu_alive[i];
    if al == 1 {
      let k: Int = _lfu_keys[i];
      if k == key {
        return i;
      }
    }
    i = i + 1;
  }
  return _CA_NONE;
}

// Reserve the free-list head, or -1 when full.
fn _lfu_alloc() -> Int {
  let slot: Int = _lfu_free;
  if slot < 0 {
    return _CA_NONE;
  }
  _lfu_free = _lfu_link[slot];
  _lfu_alive[slot] = 1;
  return slot;
}

// Release a dead slot to the free list.
fn _lfu_release(slot: Int) {
  _lfu_alive[slot] = 0;
  _lfu_seq[slot] = _CA_NONE;
  _lfu_link[slot] = _lfu_free;
  _lfu_free = slot;
  _lfu_count = _lfu_count - 1;
}

// Slot with the minimum (freq, seq) among live entries: lowest frequency
// first, earliest first-insert on ties. Returns -1 only when empty.
// Complexity: O(capacity).
fn _lfu_min_slot() -> Int {
  var best: Int = _CA_NONE;
  var best_freq = 0;
  var best_seq = 0;
  var i = 0;
  while i < _lfu_cap {
    let al: Int = _lfu_alive[i];
    if al == 1 {
      let f: Int = _lfu_freq[i];
      let s: Int = _lfu_seq[i];
      var better = false;
      if best < 0 {
        better = true;
      } else {
        if f < best_freq {
          better = true;
        } else {
          if f == best_freq {
            if s < best_seq {
              better = true;
            }
          }
        }
      }
      if better {
        best = i;
        best_freq = f;
        best_seq = s;
      }
    }
    i = i + 1;
  }
  return best;
}

// Policy-evict a live slot and record it.
fn _lfu_evict_slot(slot: Int) {
  let k: Int = _lfu_keys[slot];
  _lfu_release(slot);
  _lfu_evictions = _lfu_evictions + 1;
  _lfu_last = k;
  _lfu_has_last = true;
}

// --- public API ---

/// Create (or fully reset) the LFU cache with `capacity` slots.
/// Params: capacity - 1..cache_max_capacity().
/// Returns: Ok(capacity).
/// Error case: codes 1/2 with key = -1 and detail = capacity; the previous
/// state is unchanged on Err. Complexity: O(capacity).
pub fn lfu_create(capacity: Int) -> Result[Int, CacheError] {
  let code: Int = _ca_capacity_code(capacity);
  if code != 0 {
    return _ca_err_int(code, _CA_NONE, capacity);
  }
  _lfu_reset(capacity);
  return _ca_ok_int(capacity);
}

/// Insert or update `key`. A new key starts at frequency 1 with the next
/// insertion ordinal; an update replaces the value, raises the frequency and
/// keeps the ordinal. When full, the lowest frequency (then earliest insert)
/// is evicted first.
/// Returns: Ok(evicted) with evicted = 0 or 1.
/// Error case: none. Complexity: O(capacity).
pub fn lfu_put(key: Int, value: Int) -> Result[Int, CacheError] {
  _lfu_ensure();
  let slot: Int = _lfu_find(key);
  if slot >= 0 {
    _lfu_vals[slot] = value;
    _lfu_freq[slot] = _lfu_freq[slot] + 1;
    return _ca_ok_int(0);
  }
  var evicted = 0;
  if _lfu_count >= _lfu_cap {
    let victim: Int = _lfu_min_slot();
    _lfu_evict_slot(victim);
    evicted = 1;
  }
  let ns: Int = _lfu_alloc();
  _lfu_keys[ns] = key;
  _lfu_vals[ns] = value;
  _lfu_freq[ns] = 1;
  _lfu_seq[ns] = _lfu_seq_next;
  _lfu_seq_next = _lfu_seq_next + 1;
  _lfu_count = _lfu_count + 1;
  return _ca_ok_int(evicted);
}

/// Read `key` and raise its frequency. Moves hits/misses like lru_get.
/// Returns: Ok(value), or Err(code 3, key = key, detail = -1).
/// Complexity: O(capacity).
pub fn lfu_get(key: Int) -> Result[Int, CacheError] {
  _lfu_ensure();
  let slot: Int = _lfu_find(key);
  if slot < 0 {
    _lfu_misses = _lfu_misses + 1;
    return _ca_err_int(_CA_ERR_UNKNOWN_KEY, key, _CA_NONE);
  }
  let v: Int = _lfu_vals[slot];
  _lfu_freq[slot] = _lfu_freq[slot] + 1;
  _lfu_hits = _lfu_hits + 1;
  return _ca_ok_int(v);
}

/// Read `key` without raising its frequency and without moving hits/misses.
/// Returns: Ok(value), or Err(code 3, key = key, detail = -1).
/// Complexity: O(capacity).
pub fn lfu_peek(key: Int) -> Result[Int, CacheError] {
  _lfu_ensure();
  let slot: Int = _lfu_find(key);
  if slot < 0 {
    return _ca_err_int(_CA_ERR_UNKNOWN_KEY, key, _CA_NONE);
  }
  let v: Int = _lfu_vals[slot];
  return _ca_ok_int(v);
}

/// Remove `key` explicitly. Not an eviction.
/// Returns: Ok(value), or Err(code 3, key = key, detail = -1).
/// Complexity: O(capacity).
pub fn lfu_remove(key: Int) -> Result[Int, CacheError] {
  _lfu_ensure();
  let slot: Int = _lfu_find(key);
  if slot < 0 {
    return _ca_err_int(_CA_ERR_UNKNOWN_KEY, key, _CA_NONE);
  }
  let v: Int = _lfu_vals[slot];
  _lfu_release(slot);
  return _ca_ok_int(v);
}

/// Evict the entry with the lowest frequency (earliest insert on ties).
/// Returns: Ok(key), or Err(code 5, key = -1, detail = -1) when empty.
/// Complexity: O(capacity).
pub fn lfu_evict_one() -> Result[Int, CacheError] {
  _lfu_ensure();
  if _lfu_count == 0 {
    return _ca_err_int(_CA_ERR_EMPTY, _CA_NONE, _CA_NONE);
  }
  let victim: Int = _lfu_min_slot();
  let k: Int = _lfu_keys[victim];
  _lfu_evict_slot(victim);
  return _ca_ok_int(k);
}

/// Remove every entry and reset all counters. Capacity is preserved.
/// Complexity: O(capacity).
pub fn lfu_clear() {
  _lfu_ensure();
  _lfu_reset(_lfu_cap);
}

/// Number of live entries. Error case: none. Complexity: O(1).
pub fn lfu_len() -> Int {
  _lfu_ensure();
  return _lfu_count;
}

/// Active capacity. Error case: none. Complexity: O(1).
pub fn lfu_capacity() -> Int {
  _lfu_ensure();
  return _lfu_cap;
}

/// True when `key` has a live entry. Error case: none.
/// Complexity: O(capacity).
pub fn lfu_contains(key: Int) -> Bool {
  _lfu_ensure();
  return _lfu_find(key) >= 0;
}

/// Counter snapshot, including the current size.
pub fn lfu_stats() -> CacheStats {
  _lfu_ensure();
  return CacheStats{ hits: _lfu_hits; misses: _lfu_misses; evictions: _lfu_evictions; size: _lfu_count; };
}

/// Key evicted by the most recent policy eviction of this policy.
/// Returns: Ok(key), or Err(code 6, key = -1, detail = -1) when no eviction
/// has happened since the last create/clear.
pub fn lfu_last_evicted() -> Result[Int, CacheError] {
  _lfu_ensure();
  if !_lfu_has_last {
    return _ca_err_int(_CA_ERR_NO_EVICTION, _CA_NONE, _CA_NONE);
  }
  return _ca_ok_int(_lfu_last);
}

// ==================================================================
//  CLOCK -- second chance, reference bits and a hand pointer
// ==================================================================
//
// Data model (parallel Vec[Int] fields, all length = capacity):
//   keys/vals   payload of each slot; meaningful while alive == 1
//   ref         0/1 reference bit; set on insert, update and get
//   alive       1 = live, 0 = free
//   link        free-list link while dead
//   hand        slot the sweep inspects next
// evict_one inspects the slot at `hand` and advances the hand: a live slot
// with ref == 1 is cleared and gets a second chance; the first live slot with
// ref == 0 is evicted. The sweep is bounded by two full passes, so eviction
// is deterministic and terminates. Complexity: O(capacity) worst case.

// --- state ---
var _clk_ready: Bool = false;
var _clk_cap: Int = 0;
var _clk_count: Int = 0;
var _clk_free: Int = _CA_NONE;
var _clk_hand: Int = 0;
var _clk_hits: Int = 0;
var _clk_misses: Int = 0;
var _clk_evictions: Int = 0;
var _clk_last: Int = 0;
var _clk_has_last: Bool = false;
var _clk_keys: Vec[Int] = Vec[Int].new();
var _clk_vals: Vec[Int] = Vec[Int].new();
var _clk_ref: Vec[Int] = Vec[Int].new();
var _clk_alive: Vec[Int] = Vec[Int].new();
var _clk_link: Vec[Int] = Vec[Int].new();

// --- internals ---

// Rebuild the CLOCK state for a validated capacity >= 1; the hand restarts
// at slot 0. Complexity: O(capacity).
fn _clk_reset(capacity: Int) {
  _clk_cap = capacity;
  _clk_count = 0;
  _clk_free = 0;
  _clk_hand = 0;
  _clk_hits = 0;
  _clk_misses = 0;
  _clk_evictions = 0;
  _clk_last = 0;
  _clk_has_last = false;
  _clk_keys.clear();
  _clk_vals.clear();
  _clk_ref.clear();
  _clk_alive.clear();
  _clk_link.clear();
  var i = 0;
  while i < capacity {
    _clk_keys.push(0);
    _clk_vals.push(0);
    _clk_ref.push(0);
    _clk_alive.push(0);
    _clk_link.push(i + 1);
    i = i + 1;
  }
  _clk_link[capacity - 1] = _CA_NONE;
  _clk_ready = true;
}

fn _clk_ensure() {
  if !_clk_ready {
    _clk_reset(_CA_DEFAULT_CAPACITY);
  }
}

// Slot holding `key`, or -1. Scans the slot table. Complexity: O(capacity).
fn _clk_find(key: Int) -> Int {
  var i = 0;
  while i < _clk_cap {
    let al: Int = _clk_alive[i];
    if al == 1 {
      let k: Int = _clk_keys[i];
      if k == key {
        return i;
      }
    }
    i = i + 1;
  }
  return _CA_NONE;
}

// Reserve the free-list head, or -1 when full.
fn _clk_alloc() -> Int {
  let slot: Int = _clk_free;
  if slot < 0 {
    return _CA_NONE;
  }
  _clk_free = _clk_link[slot];
  _clk_alive[slot] = 1;
  _clk_ref[slot] = 1;
  return slot;
}

// Release a dead slot to the free list.
fn _clk_release(slot: Int) {
  _clk_alive[slot] = 0;
  _clk_ref[slot] = 0;
  _clk_link[slot] = _clk_free;
  _clk_free = slot;
  _clk_count = _clk_count - 1;
}

// One hand sweep: clear the reference bit of each live slot passed, evict the
// first live slot found with ref == 0. Free slots are skipped. Returns the
// victim slot, or -1 when no live slot exists. Complexity: O(capacity).
fn _clk_sweep_slot() -> Int {
  let limit = 2 * _clk_cap;
  var steps = 0;
  while steps < limit {
    let slot: Int = _clk_hand;
    _clk_hand = (_clk_hand + 1) % _clk_cap;
    steps = steps + 1;
    let al: Int = _clk_alive[slot];
    if al == 1 {
      let r: Int = _clk_ref[slot];
      if r == 1 {
        _clk_ref[slot] = 0;
      } else {
        return slot;
      }
    }
  }
  return _CA_NONE;
}

// Policy-evict a live slot and record it.
fn _clk_evict_slot(slot: Int) {
  let k: Int = _clk_keys[slot];
  _clk_release(slot);
  _clk_evictions = _clk_evictions + 1;
  _clk_last = k;
  _clk_has_last = true;
}

// --- public API ---

/// Create (or fully reset) the CLOCK cache with `capacity` slots.
/// Params: capacity - 1..cache_max_capacity().
/// Returns: Ok(capacity).
/// Error case: codes 1/2 with key = -1 and detail = capacity; the previous
/// state is unchanged on Err. Complexity: O(capacity).
pub fn clock_create(capacity: Int) -> Result[Int, CacheError] {
  let code: Int = _ca_capacity_code(capacity);
  if code != 0 {
    return _ca_err_int(code, _CA_NONE, capacity);
  }
  _clk_reset(capacity);
  return _ca_ok_int(capacity);
}

/// Insert or update `key`; the entry gets reference bit 1. When full, one
/// hand sweep selects the victim first (see clock_evict_one).
/// Returns: Ok(evicted) with evicted = 0 or 1.
/// Error case: none. Complexity: O(capacity).
pub fn clock_put(key: Int, value: Int) -> Result[Int, CacheError] {
  _clk_ensure();
  let slot: Int = _clk_find(key);
  if slot >= 0 {
    _clk_vals[slot] = value;
    _clk_ref[slot] = 1;
    return _ca_ok_int(0);
  }
  var evicted = 0;
  if _clk_count >= _clk_cap {
    let victim: Int = _clk_sweep_slot();
    _clk_evict_slot(victim);
    evicted = 1;
  }
  let ns: Int = _clk_alloc();
  _clk_keys[ns] = key;
  _clk_vals[ns] = value;
  _clk_count = _clk_count + 1;
  return _ca_ok_int(evicted);
}

/// Read `key` and set its reference bit. Moves hits/misses like lru_get.
/// Returns: Ok(value), or Err(code 3, key = key, detail = -1).
/// Complexity: O(capacity).
pub fn clock_get(key: Int) -> Result[Int, CacheError] {
  _clk_ensure();
  let slot: Int = _clk_find(key);
  if slot < 0 {
    _clk_misses = _clk_misses + 1;
    return _ca_err_int(_CA_ERR_UNKNOWN_KEY, key, _CA_NONE);
  }
  let v: Int = _clk_vals[slot];
  _clk_ref[slot] = 1;
  _clk_hits = _clk_hits + 1;
  return _ca_ok_int(v);
}

/// Read `key` without touching its reference bit or the counters.
/// Returns: Ok(value), or Err(code 3, key = key, detail = -1).
/// Complexity: O(capacity).
pub fn clock_peek(key: Int) -> Result[Int, CacheError] {
  _clk_ensure();
  let slot: Int = _clk_find(key);
  if slot < 0 {
    return _ca_err_int(_CA_ERR_UNKNOWN_KEY, key, _CA_NONE);
  }
  let v: Int = _clk_vals[slot];
  return _ca_ok_int(v);
}

/// Remove `key` explicitly. Not an eviction; the hand is untouched.
/// Returns: Ok(value), or Err(code 3, key = key, detail = -1).
/// Complexity: O(capacity).
pub fn clock_remove(key: Int) -> Result[Int, CacheError] {
  _clk_ensure();
  let slot: Int = _clk_find(key);
  if slot < 0 {
    return _ca_err_int(_CA_ERR_UNKNOWN_KEY, key, _CA_NONE);
  }
  let v: Int = _clk_vals[slot];
  _clk_release(slot);
  return _ca_ok_int(v);
}

/// Run one hand sweep and evict the selected entry.
/// Returns: Ok(key), or Err(code 5, key = -1, detail = -1) when empty.
/// Complexity: O(capacity).
pub fn clock_evict_one() -> Result[Int, CacheError] {
  _clk_ensure();
  if _clk_count == 0 {
    return _ca_err_int(_CA_ERR_EMPTY, _CA_NONE, _CA_NONE);
  }
  let victim: Int = _clk_sweep_slot();
  if victim < 0 {
    return _ca_err_int(_CA_ERR_EMPTY, _CA_NONE, _CA_NONE);
  }
  let k: Int = _clk_keys[victim];
  _clk_evict_slot(victim);
  return _ca_ok_int(k);
}

/// Remove every entry and reset all counters; the hand restarts at slot 0.
/// Capacity is preserved. Complexity: O(capacity).
pub fn clock_clear() {
  _clk_ensure();
  _clk_reset(_clk_cap);
}

/// Number of live entries. Error case: none. Complexity: O(1).
pub fn clock_len() -> Int {
  _clk_ensure();
  return _clk_count;
}

/// Active capacity. Error case: none. Complexity: O(1).
pub fn clock_capacity() -> Int {
  _clk_ensure();
  return _clk_cap;
}

/// True when `key` has a live entry. Error case: none.
/// Complexity: O(capacity).
pub fn clock_contains(key: Int) -> Bool {
  _clk_ensure();
  return _clk_find(key) >= 0;
}

/// Counter snapshot, including the current size.
pub fn clock_stats() -> CacheStats {
  _clk_ensure();
  return CacheStats{ hits: _clk_hits; misses: _clk_misses; evictions: _clk_evictions; size: _clk_count; };
}

/// Key evicted by the most recent policy eviction of this policy.
/// Returns: Ok(key), or Err(code 6, key = -1, detail = -1) when no eviction
/// has happened since the last create/clear.
pub fn clock_last_evicted() -> Result[Int, CacheError] {
  _clk_ensure();
  if !_clk_has_last {
    return _ca_err_int(_CA_ERR_NO_EVICTION, _CA_NONE, _CA_NONE);
  }
  return _ca_ok_int(_clk_last);
}

// ==================================================================
//  TTL -- absolute expire ticks, insertion-order sweep
// ==================================================================
//
// Data model (parallel Vec[Int] fields, all length = capacity):
//   keys/vals   payload of each slot; meaningful while alive == 1
//   exp         absolute expire tick; the entry is expired when exp <= now
//   alive       1 = live, 0 = free
//   prev/next   doubly linked insertion-order list: head is the oldest
//               insertion, tail the newest; next is also the free-list link
//               while a slot is dead
// Ticks are caller-supplied Ints: there is no wall clock inside this module.
// Every successful put (insert or update) makes the entry the newest in
// insertion order. sweep walks the list from the head and evicts entries with
// exp <= now in that order. evict_one selects the smallest exp, ties by
// insertion order. An expired entry is logically absent for get/peek/
// contains, but it still occupies capacity and counts in len until it is
// removed by sweep, get, evict_one, put or remove.

// --- state ---
var _ttl_ready: Bool = false;
var _ttl_cap: Int = 0;
var _ttl_count: Int = 0;
var _ttl_free: Int = _CA_NONE;
var _ttl_head: Int = _CA_NONE;
var _ttl_tail: Int = _CA_NONE;
var _ttl_hits: Int = 0;
var _ttl_misses: Int = 0;
var _ttl_evictions: Int = 0;
var _ttl_last: Int = 0;
var _ttl_has_last: Bool = false;
var _ttl_keys: Vec[Int] = Vec[Int].new();
var _ttl_vals: Vec[Int] = Vec[Int].new();
var _ttl_exp: Vec[Int] = Vec[Int].new();
var _ttl_alive: Vec[Int] = Vec[Int].new();
var _ttl_prev: Vec[Int] = Vec[Int].new();
var _ttl_next: Vec[Int] = Vec[Int].new();

// --- internals ---

// Rebuild the TTL state for a validated capacity >= 1. Complexity: O(capacity).
fn _ttl_reset(capacity: Int) {
  _ttl_cap = capacity;
  _ttl_count = 0;
  _ttl_free = 0;
  _ttl_head = _CA_NONE;
  _ttl_tail = _CA_NONE;
  _ttl_hits = 0;
  _ttl_misses = 0;
  _ttl_evictions = 0;
  _ttl_last = 0;
  _ttl_has_last = false;
  _ttl_keys.clear();
  _ttl_vals.clear();
  _ttl_exp.clear();
  _ttl_alive.clear();
  _ttl_prev.clear();
  _ttl_next.clear();
  var i = 0;
  while i < capacity {
    _ttl_keys.push(0);
    _ttl_vals.push(0);
    _ttl_exp.push(0);
    _ttl_alive.push(0);
    _ttl_prev.push(_CA_NONE);
    _ttl_next.push(i + 1);
    i = i + 1;
  }
  _ttl_next[capacity - 1] = _CA_NONE;
  _ttl_ready = true;
}

fn _ttl_ensure() {
  if !_ttl_ready {
    _ttl_reset(_CA_DEFAULT_CAPACITY);
  }
}

// Slot holding `key`, or -1. Scans the slot table. Complexity: O(capacity).
fn _ttl_find(key: Int) -> Int {
  var i = 0;
  while i < _ttl_cap {
    let al: Int = _ttl_alive[i];
    if al == 1 {
      let k: Int = _ttl_keys[i];
      if k == key {
        return i;
      }
    }
    i = i + 1;
  }
  return _CA_NONE;
}

// Reserve the free-list head, or -1 when full.
fn _ttl_alloc() -> Int {
  let slot: Int = _ttl_free;
  if slot < 0 {
    return _CA_NONE;
  }
  _ttl_free = _ttl_next[slot];
  _ttl_alive[slot] = 1;
  _ttl_prev[slot] = _CA_NONE;
  _ttl_next[slot] = _CA_NONE;
  return slot;
}

// Release a dead slot to the free list.
fn _ttl_release(slot: Int) {
  _ttl_alive[slot] = 0;
  _ttl_prev[slot] = _CA_NONE;
  _ttl_next[slot] = _ttl_free;
  _ttl_free = slot;
  _ttl_count = _ttl_count - 1;
}

// Append a live slot as the newest entry of the insertion-order list.
fn _ttl_dll_append(slot: Int) {
  let tail: Int = _ttl_tail;
  _ttl_prev[slot] = tail;
  _ttl_next[slot] = _CA_NONE;
  if tail < 0 {
    _ttl_head = slot;
  } else {
    _ttl_next[tail] = slot;
  }
  _ttl_tail = slot;
}

// Detach a live slot from the insertion-order list.
fn _ttl_dll_remove(slot: Int) {
  let p: Int = _ttl_prev[slot];
  let n: Int = _ttl_next[slot];
  if p < 0 {
    _ttl_head = n;
  } else {
    _ttl_next[p] = n;
  }
  if n < 0 {
    _ttl_tail = p;
  } else {
    _ttl_prev[n] = p;
  }
  _ttl_prev[slot] = _CA_NONE;
  _ttl_next[slot] = _CA_NONE;
}

// Slot with the smallest expire tick among live entries, ties by insertion
// order (strict < while walking from the head keeps the earliest). Returns -1
// only when empty. Complexity: O(capacity).
fn _ttl_min_exp_slot() -> Int {
  var best: Int = _CA_NONE;
  var best_exp = 0;
  var cur: Int = _ttl_head;
  while cur >= 0 {
    let e: Int = _ttl_exp[cur];
    if best < 0 {
      best = cur;
      best_exp = e;
    } else {
      if e < best_exp {
        best = cur;
        best_exp = e;
      }
    }
    let nxt: Int = _ttl_next[cur];
    cur = nxt;
  }
  return best;
}

// Policy-evict a live slot: detach it, release it and record the eviction.
fn _ttl_evict_slot(slot: Int) {
  let k: Int = _ttl_keys[slot];
  _ttl_dll_remove(slot);
  _ttl_release(slot);
  _ttl_evictions = _ttl_evictions + 1;
  _ttl_last = k;
  _ttl_has_last = true;
}

// --- public API ---

/// Create (or fully reset) the TTL cache with `capacity` slots.
/// Params: capacity - 1..cache_max_capacity().
/// Returns: Ok(capacity).
/// Error case: codes 1/2 with key = -1 and detail = capacity; the previous
/// state is unchanged on Err. Complexity: O(capacity).
pub fn ttl_create(capacity: Int) -> Result[Int, CacheError] {
  let code: Int = _ca_capacity_code(capacity);
  if code != 0 {
    return _ca_err_int(code, _CA_NONE, capacity);
  }
  _ttl_reset(capacity);
  return _ca_ok_int(capacity);
}

/// Insert or update `key` with the absolute expire tick `expire_at`.
/// An update replaces the value and expiry and makes the entry the newest in
/// insertion order. A present-but-expired entry is first removed as an
/// eviction and then re-inserted fresh. When the cache is full the smallest
/// expire tick (ties by insertion order) is evicted first.
/// Params: key, value - any Int; now - current tick; expire_at - must be > now.
/// Returns: Ok(evicted) with evicted = 0 or 1.
/// Error case: Err(code 7, key = key, detail = expire_at) when
/// expire_at <= now; the cache is unchanged then.
/// Complexity: O(capacity).
pub fn ttl_put(key: Int, value: Int, now: Int, expire_at: Int) -> Result[Int, CacheError] {
  _ttl_ensure();
  if expire_at <= now {
    return _ca_err_int(_CA_ERR_EXPIRY_PAST, key, expire_at);
  }
  let found: Int = _ttl_find(key);
  var evicted = 0;
  if found >= 0 {
    let e: Int = _ttl_exp[found];
    if e <= now {
      _ttl_evict_slot(found);
      evicted = 1;
    } else {
      _ttl_vals[found] = value;
      _ttl_exp[found] = expire_at;
      _ttl_dll_remove(found);
      _ttl_dll_append(found);
      return _ca_ok_int(0);
    }
  }
  if _ttl_count >= _ttl_cap {
    let victim: Int = _ttl_min_exp_slot();
    _ttl_evict_slot(victim);
    evicted = evicted + 1;
  }
  let ns: Int = _ttl_alloc();
  _ttl_keys[ns] = key;
  _ttl_vals[ns] = value;
  _ttl_exp[ns] = expire_at;
  _ttl_dll_append(ns);
  _ttl_count = _ttl_count + 1;
  return _ca_ok_int(evicted);
}

/// Read `key` at tick `now`.
/// Expired-on-get: when the entry is present but exp <= now it is removed as
/// an eviction and the call returns Err code 4 with detail = the stale
/// expire tick; the miss counter also moves.
/// Returns: Ok(value) for a live entry, Ok moves the hit counter;
/// Err(code 3, key, -1) when absent (miss counter moves);
/// Err(code 4, key, exp) when expired (miss and eviction counters move).
/// Complexity: O(capacity).
pub fn ttl_get(key: Int, now: Int) -> Result[Int, CacheError] {
  _ttl_ensure();
  let slot: Int = _ttl_find(key);
  if slot < 0 {
    _ttl_misses = _ttl_misses + 1;
    return _ca_err_int(_CA_ERR_UNKNOWN_KEY, key, _CA_NONE);
  }
  let e: Int = _ttl_exp[slot];
  if e <= now {
    _ttl_evict_slot(slot);
    _ttl_misses = _ttl_misses + 1;
    return _ca_err_int(_CA_ERR_EXPIRED, key, e);
  }
  let v: Int = _ttl_vals[slot];
  _ttl_hits = _ttl_hits + 1;
  return _ca_ok_int(v);
}

/// Read `key` at tick `now` without removing or counting anything.
/// Returns: Ok(value) for a live entry;
/// Err(code 3, key, -1) when absent; Err(code 4, key, exp) when expired
/// (a pure observation: the entry stays in place and no counter moves).
/// Complexity: O(capacity).
pub fn ttl_peek(key: Int, now: Int) -> Result[Int, CacheError] {
  _ttl_ensure();
  let slot: Int = _ttl_find(key);
  if slot < 0 {
    return _ca_err_int(_CA_ERR_UNKNOWN_KEY, key, _CA_NONE);
  }
  let e: Int = _ttl_exp[slot];
  if e <= now {
    return _ca_err_int(_CA_ERR_EXPIRED, key, e);
  }
  let v: Int = _ttl_vals[slot];
  return _ca_ok_int(v);
}

/// True when `key` is present and unexpired at tick `now`. No counters move.
pub fn ttl_contains(key: Int, now: Int) -> Bool {
  _ttl_ensure();
  let slot: Int = _ttl_find(key);
  if slot < 0 {
    return false;
  }
  let e: Int = _ttl_exp[slot];
  if e <= now {
    return false;
  }
  return true;
}

/// Remove `key` explicitly (ignoring expiry) and return its stored value.
/// Not an eviction; counters and the last-evicted record are untouched.
/// Returns: Ok(value), or Err(code 3, key = key, detail = -1).
/// Complexity: O(capacity).
pub fn ttl_remove(key: Int) -> Result[Int, CacheError] {
  _ttl_ensure();
  let slot: Int = _ttl_find(key);
  if slot < 0 {
    return _ca_err_int(_CA_ERR_UNKNOWN_KEY, key, _CA_NONE);
  }
  let v: Int = _ttl_vals[slot];
  _ttl_dll_remove(slot);
  _ttl_release(slot);
  return _ca_ok_int(v);
}

/// Evict the entry with the smallest expire tick; ties go to the earlier
/// insertion. Recorded like every policy eviction.
/// Returns: Ok(key), or Err(code 5, key = -1, detail = -1) when empty.
/// Complexity: O(capacity).
pub fn ttl_evict_one() -> Result[Int, CacheError] {
  _ttl_ensure();
  if _ttl_count == 0 {
    return _ca_err_int(_CA_ERR_EMPTY, _CA_NONE, _CA_NONE);
  }
  let victim: Int = _ttl_min_exp_slot();
  let k: Int = _ttl_keys[victim];
  _ttl_evict_slot(victim);
  return _ca_ok_int(k);
}

/// Evict every live entry with exp <= now, walking the insertion-order list
/// from the oldest entry to the newest. Recorded like every policy eviction
/// (the last key swept stays in last_evicted).
/// Returns: Ok(swept), the number of entries removed.
/// Error case: none. Complexity: O(capacity).
pub fn ttl_sweep(now: Int) -> Result[Int, CacheError] {
  _ttl_ensure();
  var swept = 0;
  var cur: Int = _ttl_head;
  while cur >= 0 {
    let nxt: Int = _ttl_next[cur];
    let e: Int = _ttl_exp[cur];
    if e <= now {
      _ttl_evict_slot(cur);
      swept = swept + 1;
    }
    cur = nxt;
  }
  return _ca_ok_int(swept);
}

/// Remove every entry and reset all counters. Capacity is preserved.
/// Complexity: O(capacity).
pub fn ttl_clear() {
  _ttl_ensure();
  _ttl_reset(_ttl_cap);
}

/// Number of physically present entries, including expired-but-unswept ones.
/// Error case: none. Complexity: O(1).
pub fn ttl_len() -> Int {
  _ttl_ensure();
  return _ttl_count;
}

/// Active capacity. Error case: none. Complexity: O(1).
pub fn ttl_capacity() -> Int {
  _ttl_ensure();
  return _ttl_cap;
}

/// Counter snapshot, including the current size.
pub fn ttl_stats() -> CacheStats {
  _ttl_ensure();
  return CacheStats{ hits: _ttl_hits; misses: _ttl_misses; evictions: _ttl_evictions; size: _ttl_count; };
}

/// Key evicted by the most recent policy eviction of this policy.
/// Returns: Ok(key), or Err(code 6, key = -1, detail = -1) when no eviction
/// has happened since the last create/clear.
pub fn ttl_last_evicted() -> Result[Int, CacheError] {
  _ttl_ensure();
  if !_ttl_has_last {
    return _ca_err_int(_CA_ERR_NO_EVICTION, _CA_NONE, _CA_NONE);
  }
  return _ca_ok_int(_ttl_last);
}
