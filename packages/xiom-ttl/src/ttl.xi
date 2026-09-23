// XIOM -- xiom.ttl: time-to-live cache with lazy and eager expiration
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Storage model: a StringMap (xiom.collect.stringmap) indexes keys to slots
// in parallel Vec arenas. Slots are appended in insertion order and never
// reused, so a lower slot index is an older insertion (the eviction
// tie-break). Expiry uses the wall clock at second resolution
// (xiom.time.unix_timestamp), so an entry with ttl_secs <= 0 is expired as
// soon as it is inserted; see SPEC.md for the documented limitations.

module xiom.ttl

use xiom.time;
use xiom.collect.stringmap;

/// Time-to-live cache. Every field is internal state: use the ttl_* API.
pub type TtlCache = {
  capacity: Int;      // internal: maximum stored entries, >= 1
  default_ttl: Int;   // internal: seconds applied by ttl_insert, >= 0
  index: StringMap;   // internal: key -> slot in the arenas below
  keys: Vec[Str];     // internal: slot -> key
  values: Vec[Int];   // internal: slot -> value
  expires: Vec[Int];  // internal: slot -> Unix seconds when it expires
  live: Vec[Bool];    // internal: slot -> still stored (not removed)
  count: Int;         // internal: stored entries (expired unswept included)
  hits: Int;          // internal: ttl_get hits
  misses: Int;        // internal: ttl_get misses
  expirations: Int;   // internal: entries discarded because they expired
}

// Current wall-clock time as Unix seconds.
fn _now() -> Int {
  return time.unix_timestamp();
}

// True when the entry in `slot` has reached its expiry instant.
fn _is_expired(c: &TtlCache, slot: Int, now: Int) -> Bool {
  return c.expires[slot] <= now;
}

// Unlink `slot` from the index and mark it dead. When the entry had already
// expired the discard is counted in `expirations`.
fn _drop_slot(c: &mut TtlCache, slot: Int, now: Int) {
  let key = c.keys[slot];
  stringmap.string_map_remove(&mut c.index, key);
  if c.expires[slot] <= now {
    c.expirations = c.expirations + 1;
  }
  c.live[slot] = false;
  c.count = c.count - 1;
}

// Evict the stored entry with the earliest expires_at. Ties go to the lower
// slot index, i.e. the older first insertion. No-op when nothing is stored.
fn _evict_earliest(c: &mut TtlCache, now: Int) {
  var victim: Int = -1;
  var victim_expires: Int = 0;
  var i: Int = 0;
  while i < c.live.len() {
    if c.live[i] {
      if victim < 0 || c.expires[i] < victim_expires {
        victim = i;
        victim_expires = c.expires[i];
      }
    }
    i = i + 1;
  }
  if victim >= 0 {
    _drop_slot(c, victim, now);
  }
}

// Evict earliest-expiry entries until a new slot fits.
fn _make_room(c: &mut TtlCache, now: Int) {
  while c.count >= c.capacity {
    _evict_earliest(c, now);
  }
}

/// Create a cache holding at most `capacity` entries (>= 1) with a default
/// lifetime of `default_ttl_secs` seconds (>= 0).
pub fn ttl_new(capacity: Int, default_ttl_secs: Int) -> TtlCache
  requires: capacity >= 1 && default_ttl_secs >= 0
{
  return TtlCache{
    capacity: capacity,
    default_ttl: default_ttl_secs,
    index: stringmap.string_map_new(),
    keys: Vec[Str].new(),
    values: Vec[Int].new(),
    expires: Vec[Int].new(),
    live: Vec[Bool].new(),
    count: 0,
    hits: 0,
    misses: 0,
    expirations: 0,
  };
}

/// Insert or replace `key` -> `value` using the default TTL.
pub fn ttl_insert(c: &mut TtlCache, key: Str, value: Int) {
  let ttl = c.default_ttl;
  ttl_insert_with_ttl(c, key, value, ttl);
}

/// Insert or replace `key` -> `value` with an explicit lifetime. A value
/// <= 0 stores an entry that is already expired. When the cache is full the
/// stored entry with the earliest expires_at is evicted first (ties: the
/// older insertion). Inserts do not change the hit/miss counters.
pub fn ttl_insert_with_ttl(c: &mut TtlCache, key: Str, value: Int, ttl_secs: Int) {
  let now = _now();
  let expires_at = now + ttl_secs;
  let existing = stringmap.string_map_get(&c.index, key);
  match existing {
    Some(slot) => {
      c.values[slot] = value;
      c.expires[slot] = expires_at;
      return;
    },
    None => {},
  };
  _make_room(c, now);
  let slot = c.keys.len();
  c.keys.push(key);
  c.values.push(value);
  c.expires.push(expires_at);
  c.live.push(true);
  stringmap.string_map_put(&mut c.index, key, slot);
  c.count = c.count + 1;
}

/// Look `key` up. An expired entry is removed lazily: the result is None and
/// both expirations and misses increase. A live hit increases hits.
pub fn ttl_get(c: &mut TtlCache, key: Str) -> Option[Int] {
  let now = _now();
  let found = stringmap.string_map_get(&c.index, key);
  match found {
    Some(slot) => {
      if _is_expired(c, slot, now) {
        _drop_slot(c, slot, now);
        c.misses = c.misses + 1;
        return None;
      }
      c.hits = c.hits + 1;
      return Some(c.values[slot]);
    },
    None => {},
  };
  c.misses = c.misses + 1;
  return None;
}

/// Read `key` without mutating the cache. None when absent or expired; no
/// counter changes and the entry stays stored.
pub fn ttl_peek(c: &TtlCache, key: Str) -> Option[Int] {
  let now = _now();
  let found = stringmap.string_map_get(&c.index, key);
  match found {
    Some(slot) => {
      if _is_expired(c, slot, now) {
        return None;
      }
      return Some(c.values[slot]);
    },
    None => {},
  };
  return None;
}

/// Eagerly remove every expired entry and return how many were removed.
/// Each removal increases expirations.
pub fn ttl_evict_expired(c: &mut TtlCache) -> Int {
  let now = _now();
  var removed: Int = 0;
  var i: Int = 0;
  while i < c.live.len() {
    if c.live[i] {
      if c.expires[i] <= now {
        _drop_slot(c, i, now);
        removed = removed + 1;
      }
    }
    i = i + 1;
  }
  return removed;
}

/// True when `key` is stored and unexpired.
pub fn ttl_contains(c: &TtlCache, key: Str) -> Bool {
  let now = _now();
  let found = stringmap.string_map_get(&c.index, key);
  match found {
    Some(slot) => {
      return c.expires[slot] > now;
    },
    None => {},
  };
  return false;
}

/// Remove `key`. True only when a live (unexpired) entry was removed. A
/// stored-but-expired entry is discarded and counted in expirations, but the
/// result is false; an absent key is a false no-op.
pub fn ttl_remove(c: &mut TtlCache, key: Str) -> Bool {
  let now = _now();
  let found = stringmap.string_map_get(&c.index, key);
  match found {
    Some(slot) => {
      let was_live = c.expires[slot] > now;
      _drop_slot(c, slot, now);
      return was_live;
    },
    None => {},
  };
  return false;
}

/// Remove every entry and reset hits, misses and expirations. Capacity and
/// the default TTL are preserved.
pub fn ttl_clear(c: &mut TtlCache) {
  c.index = stringmap.string_map_new();
  c.keys = Vec[Str].new();
  c.values = Vec[Int].new();
  c.expires = Vec[Int].new();
  c.live = Vec[Bool].new();
  c.count = 0;
  c.hits = 0;
  c.misses = 0;
  c.expirations = 0;
}

/// Number of live (unexpired) entries. O(stored) scan.
pub fn ttl_len(c: &TtlCache) -> Int {
  let now = _now();
  var n: Int = 0;
  var i: Int = 0;
  while i < c.live.len() {
    if c.live[i] {
      if c.expires[i] > now {
        n = n + 1;
      }
    }
    i = i + 1;
  }
  return n;
}

/// Configured maximum number of stored entries.
pub fn ttl_capacity(c: &TtlCache) -> Int {
  return c.capacity;
}

/// Number of successful ttl_get calls.
pub fn ttl_hits(c: &TtlCache) -> Int {
  return c.hits;
}

/// Number of ttl_get calls that found no live entry.
pub fn ttl_misses(c: &TtlCache) -> Int {
  return c.misses;
}

/// Number of entries discarded because they had expired, by ttl_get,
/// ttl_evict_expired, ttl_remove or a capacity eviction.
pub fn ttl_expirations(c: &TtlCache) -> Int {
  return c.expirations;
}

/// Seconds until `key` expires (in (0, stored ttl]); None when absent or
/// already expired.
pub fn ttl_remaining_secs(c: &TtlCache, key: Str) -> Option[Int] {
  let now = _now();
  let found = stringmap.string_map_get(&c.index, key);
  match found {
    Some(slot) => {
      if _is_expired(c, slot, now) {
        return None;
      }
      return Some(c.expires[slot] - now);
    },
    None => {},
  };
  return None;
}
