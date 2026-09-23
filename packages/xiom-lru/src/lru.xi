// XIOM -- xiom.lru: bounded least-recently-used cache
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Module xiom.lru implements a bounded LRU cache over Str keys and Int
// values. Key -> node index lives in a StringMap; recency order is a doubly
// linked list over parallel arenas (keys/values/prev/next) with a free list
// for node reuse. head = most recently used, tail = least recently used.
// All entry operations are O(1) amortized; lru_keys_mru is O(n).

module xiom.lru

use xiom.collect.stringmap;

/// Bounded least-recently-used cache with Str keys and Int values.
///
/// Every field is an internal implementation detail; callers must go through
/// the free functions below. Internally: capacity is the entry bound
/// (clamped to >= 1); map stores key -> node index; keys/values/prev/next
/// are the parallel node arenas; free lists reusable node indices; head and
/// tail are the MRU/LRU node indices (-1 when empty); size is the live entry
/// count; hits/misses/evictions are cumulative counters.
pub type LruCache = {
  capacity: Int;
  map: StringMap;
  keys: Vec[Str];
  values: Vec[Int];
  prev: Vec[Int];
  next: Vec[Int];
  free: Vec[Int];
  head: Int;
  tail: Int;
  size: Int;
  hits: Int;
  misses: Int;
  evictions: Int;
}

/// Create a new empty cache that holds at most `capacity` entries.
/// Params: capacity - maximum live entries; values below 1 are clamped to 1.
/// Returns: an empty cache with zeroed hit/miss/eviction counters.
/// Complexity: O(1).
pub fn lru_new(capacity: Int) -> LruCache {
  var cap = capacity;
  if cap < 1 { cap = 1; }
  return LruCache{ capacity: cap; map: string_map_new(); keys: Vec[Str].new(); values: Vec[Int].new(); prev: Vec[Int].new(); next: Vec[Int].new(); free: Vec[Int].new(); head: -1; tail: -1; size: 0; hits: 0; misses: 0; evictions: 0; };
}

// Allocate a node index, reusing a freed slot when one is available.
fn _node_alloc(c: &mut LruCache) -> Int {
  if c.free.len() > 0 {
    let reused = c.free[c.free.len() - 1];
    c.free.pop();
    return reused;
  }
  c.keys.push("");
  c.values.push(0);
  c.prev.push(-1);
  c.next.push(-1);
  return c.keys.len() - 1;
}

// Detach `node` from the recency list, keeping head/tail consistent.
fn _unlink_node(c: &mut LruCache, node: Int) {
  let before = c.prev[node];
  let after = c.next[node];
  if before != -1 { c.next[before] = after; } else { c.head = after; }
  if after != -1 { c.prev[after] = before; } else { c.tail = before; }
  c.prev[node] = -1;
  c.next[node] = -1;
}

// Make `node` the most recently used entry.
fn _push_mru(c: &mut LruCache, node: Int) {
  c.prev[node] = -1;
  c.next[node] = c.head;
  if c.head != -1 { c.prev[c.head] = node; }
  c.head = node;
  if c.tail == -1 { c.tail = node; }
}

// Promote `node` to MRU; a no-op when it is already the head.
fn _touch(c: &mut LruCache, node: Int) {
  if c.head == node { return; }
  _unlink_node(c, node);
  _push_mru(c, node);
}

// Evict the LRU entry (tail); a no-op on an empty cache.
fn _evict_lru(c: &mut LruCache) {
  if c.tail == -1 { return; }
  let victim = c.tail;
  let victim_key = c.keys[victim];
  string_map_remove(&mut c.map, victim_key);
  _unlink_node(c, victim);
  c.free.push(victim);
  c.size = c.size - 1;
  c.evictions = c.evictions + 1;
}

/// Insert or update `key` -> `value`.
/// Params: c - the cache; key - Str key; value - Int value.
/// Existing key: the value is replaced in place, the entry is promoted to
/// MRU, and no eviction happens. New key: the entry is inserted as MRU and,
/// when the cache is already at capacity, the LRU entry is evicted first
/// (evictions is incremented). Hits/misses are not touched.
/// Complexity: O(1) amortized.
pub fn lru_put(c: &mut LruCache, key: Str, value: Int) {
  var existing = string_map_get(&c.map, key);
  match existing {
    Some(node) => {
      c.values[node] = value;
      _touch(c, node);
      return;
    },
    None => {},
  }
  if c.size >= c.capacity {
    _evict_lru(c);
  }
  let node = _node_alloc(c);
  c.keys[node] = key;
  c.values[node] = value;
  c.prev[node] = -1;
  c.next[node] = -1;
  _push_mru(c, node);
  string_map_put(&mut c.map, key, node);
  c.size = c.size + 1;
}

/// Look up `key` and promote it to most recently used.
/// Params: c - the cache; key - Str key.
/// Returns: Some(value) on a hit (hits incremented) or None on a miss
/// (misses incremented).
/// Complexity: O(1) amortized.
pub fn lru_get(c: &mut LruCache, key: Str) -> Option[Int] {
  var found = string_map_get(&c.map, key);
  match found {
    Some(node) => {
      let value = c.values[node];
      _touch(c, node);
      c.hits = c.hits + 1;
      return Some(value);
    },
    None => {},
  }
  c.misses = c.misses + 1;
  return None;
}

/// Look up `key` without changing recency or hit/miss statistics.
/// Params: c - the cache; key - Str key.
/// Returns: Some(value) when present, None otherwise.
/// Complexity: O(1) amortized.
pub fn lru_peek(c: &LruCache, key: Str) -> Option[Int] {
  var found = string_map_get(&c.map, key);
  match found {
    Some(node) => { return Some(c.values[node]); },
    None => {},
  }
  return None;
}

/// Check whether `key` is present; does not change recency or statistics.
/// Params: c - the cache; key - Str key.
/// Returns: true when the key has a live entry.
/// Complexity: O(1) amortized.
pub fn lru_contains(c: &LruCache, key: Str) -> Bool {
  return string_map_contains(&c.map, key);
}

/// Remove the entry for `key` when present.
/// Params: c - the cache; key - Str key.
/// Returns: true when an entry was removed (its node slot freed), false when
/// the key was absent. Does not touch hits/misses/evictions.
/// Complexity: O(1) amortized.
pub fn lru_remove(c: &mut LruCache, key: Str) -> Bool {
  var found = string_map_get(&c.map, key);
  match found {
    Some(node) => {
      string_map_remove(&mut c.map, key);
      _unlink_node(c, node);
      c.free.push(node);
      c.size = c.size - 1;
      return true;
    },
    None => {},
  }
  return false;
}

/// Drop every entry.
/// Params: c - the cache.
/// Capacity is preserved. The cumulative hits, misses and evictions counters
/// are intentionally retained (they are lifetime statistics); call lru_new
/// for a fresh cache with zeroed counters. Recency order and the free list
/// are reset. Complexity: O(n).
pub fn lru_clear(c: &mut LruCache) {
  var node = c.head;
  while node != -1 {
    string_map_remove(&mut c.map, c.keys[node]);
    node = c.next[node];
  }
  while c.keys.len() > 0 {
    c.keys.pop();
    c.values.pop();
    c.prev.pop();
    c.next.pop();
  }
  while c.free.len() > 0 {
    c.free.pop();
  }
  c.head = -1;
  c.tail = -1;
  c.size = 0;
}

/// Number of live entries.
/// Params: c - the cache. Complexity: O(1).
pub fn lru_len(c: &LruCache) -> Int {
  return c.size;
}

/// Maximum number of live entries (always >= 1).
/// Params: c - the cache. Complexity: O(1).
pub fn lru_capacity(c: &LruCache) -> Int {
  return c.capacity;
}

/// Cumulative successful lru_get calls.
/// Params: c - the cache. Complexity: O(1).
pub fn lru_hits(c: &LruCache) -> Int {
  return c.hits;
}

/// Cumulative failed lru_get calls.
/// Params: c - the cache. Complexity: O(1).
pub fn lru_misses(c: &LruCache) -> Int {
  return c.misses;
}

/// Cumulative evictions performed by lru_put.
/// Params: c - the cache. Complexity: O(1).
pub fn lru_evictions(c: &LruCache) -> Int {
  return c.evictions;
}

/// Keys ordered most-recently-used first.
/// Params: c - the cache.
/// Returns: a fresh Vec[Str]; empty when the cache is empty.
/// Complexity: O(n).
pub fn lru_keys_mru(c: &LruCache) -> Vec[Str] {
  var out = Vec[Str].new();
  var node = c.head;
  while node != -1 {
    out.push(c.keys[node]);
    node = c.next[node];
  }
  return out;
}
