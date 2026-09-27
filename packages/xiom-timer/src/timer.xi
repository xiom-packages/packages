// XIOM -- xiom.timer: pure deterministic hierarchical timer wheel over ticks
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Scope (full rules in SPEC.md):
//   * A process-wide wheel over a monotonic integer tick counter. It never
//     reads a clock, never sleeps, never spawns threads and never calls FFI;
//     the caller owns the clock and feeds elapsed ticks to timer_advance.
//   * Geometry: `levels` levels of `slots` buckets each. The granularity of
//     level L is slots^L ticks; the largest representable delay is
//     slots^levels - 1 (default 4 levels x 64 slots -> 16777215 ticks), and
//     inserts beyond it are rejected with Err.
//   * Storage is parallel primitive vectors only: no Vec[StructType], no
//     maps, no heap nodes. The entry pool is pre-sized at configuration
//     time; fires and cancels release pool slots to a free list, so no
//     allocation happens after timer_configure (or the first lazy default
//     setup). At most timer_capacity() entries are active at once.
//   * Insert places an entry at the lowest level whose coverage holds the
//     remaining delay, in bucket (deadline / slots^L) % slots. As time
//     advances, the wrap of a level L bucket re-buckets that bucket's
//     entries into the levels their remaining delay now demands, adjusting
//     the remaining delay implicitly through the fixed absolute deadline;
//     entries that reach level 0 fire on the tick their bucket comes due.
//     Fired ids are collected per advance call in a deterministic order
//     (same-deadline FIFO within a bucket chain -- SPEC.md section 5).
//   * Rules: delay must be 1..max_delay; a duplicate active id is Err; an
//     unknown cancellation is Err; a negative advance is Err; loading more
//     than timer_capacity() concurrent entries is Err. Operation errors are
//     typed TimerError values carrying a code plus the offending id/delay.
//
// v0.61.3 notes that shaped this module:
//   * free functions only; module-level parallel vectors; no methods;
//   * every Vec[Int] read goes through a typed local;
//   * Ok/Err are constructed only in the leaf helpers below;
//   * only Int arithmetic (+, -, *, /, %) -- no shifts, no bitwise ops, no
//     `as` casts anywhere;
//   * no &mut Int out-parameters (miscompiled): results are returned.

module xiom.timer

// --------------------------------------------------
//  Constants
// --------------------------------------------------

// Lazy default geometry: 4 levels x 64 slots (max delay 2^24 - 1 ticks).
const _TW_DEF_LEVELS: Int = 4;
const _TW_DEF_SLOTS: Int = 64;

// Geometry caps.
const _TW_MAX_LEVELS: Int = 8;
const _TW_MAX_SLOTS: Int = 1024;

// Largest allowed slots^levels. Keeps every granularity, max delay and
// deadline sum inside [1, 2^32 - 1] so Int arithmetic stays exact.
const _TW_MAX_COVERAGE: Int = 4294967296;

// Concurrent entry capacity of the pre-sized pool.
const _TW_CAPACITY: Int = 1024;

// TimerError codes (pinned messages in timer_error_message).
const _TW_ERR_LEVELS_POSITIVE: Int = 1;
const _TW_ERR_SLOTS_MIN: Int = 2;
const _TW_ERR_LEVELS_MAX: Int = 3;
const _TW_ERR_SLOTS_MAX: Int = 4;
const _TW_ERR_GEOMETRY: Int = 5;
const _TW_ERR_DELAY_POSITIVE: Int = 6;
const _TW_ERR_DELAY_MAX: Int = 7;
const _TW_ERR_DUPLICATE_ID: Int = 8;
const _TW_ERR_UNKNOWN_ID: Int = 9;
const _TW_ERR_NEGATIVE_ADVANCE: Int = 10;
const _TW_ERR_FULL: Int = 11;
const _TW_ERR_LEVEL_RANGE: Int = 12;

// "Not applicable" filler for unused TimerError fields.
const _TW_NONE: Int = -1;

// --------------------------------------------------
//  Types
// --------------------------------------------------

/// Typed error carried by every fallible timer operation.
/// `code` identifies the failure (see timer_error_message); `id` and `delay`
/// carry the offending values where the rule mentions them, else -1
/// (_TW_NONE). For geometry errors `id` carries the levels argument and
/// `delay` the slots argument.
pub type TimerError = {
  code: Int;
  id: Int;
  delay: Int;
}

// --------------------------------------------------
//  Module state (parallel primitive vectors only)
// --------------------------------------------------

// Geometry and clock.
var _tw_configured: Bool = false;
var _tw_levels: Int = _TW_DEF_LEVELS;
var _tw_slots: Int = _TW_DEF_SLOTS;
var _tw_now: Int = 0;
var _tw_pending: Int = 0;
var _tw_cascades: Int = 0;
var _tw_pool_count: Int = 0;
var _tw_free_head: Int = _TW_NONE;

// Per-level granularity slots^L, index 0..levels-1.
var _tw_g: Vec[Int] = Vec[Int].new();

// Bucket chains: head/tail entry indices per bucket, -1 = empty.
var _tw_head: Vec[Int] = Vec[Int].new();
var _tw_tail: Vec[Int] = Vec[Int].new();

// Entry pool, pre-sized to _TW_CAPACITY at setup time.
var _tw_ids: Vec[Int] = Vec[Int].new();
var _tw_dl: Vec[Int] = Vec[Int].new();
var _tw_lvl: Vec[Int] = Vec[Int].new();
var _tw_slot: Vec[Int] = Vec[Int].new();
var _tw_alive: Vec[Int] = Vec[Int].new();
var _tw_next: Vec[Int] = Vec[Int].new();

// Ids fired by the most recent timer_advance call.
var _tw_fired: Vec[Int] = Vec[Int].new();

// --------------------------------------------------
//  Result leaves
// --------------------------------------------------

// Ok(v) for Result[Int, TimerError].
fn _tw_ok(v: Int) -> Result[Int, TimerError] {
  return Ok(v);
}

// Err(code, id, delay) for Result[Int, TimerError].
fn _tw_err(code: Int, id: Int, delay: Int) -> Result[Int, TimerError] {
  let e = TimerError{ code: code; id: id; delay: delay; };
  return Err(e);
}

// Ok(v) for Result[Int, Str].
fn _tw_ok_str(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

// Err(m) for Result[Int, Str].
fn _tw_err_str(m: Str) -> Result[Int, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Setup and geometry
// --------------------------------------------------

// Validity code for a geometry pair: 0 when valid, else the TimerError code.
// The power loop returns as soon as the running product would pass
// _TW_MAX_COVERAGE, so the product itself never overflows.
fn _tw_geometry_code(levels: Int, slots: Int) -> Int {
  if levels < 1 {
    return _TW_ERR_LEVELS_POSITIVE;
  }
  if slots < 2 {
    return _TW_ERR_SLOTS_MIN;
  }
  if levels > _TW_MAX_LEVELS {
    return _TW_ERR_LEVELS_MAX;
  }
  if slots > _TW_MAX_SLOTS {
    return _TW_ERR_SLOTS_MAX;
  }
  var p = 1;
  var i = 0;
  while i < levels {
    if p > _TW_MAX_COVERAGE / slots {
      return _TW_ERR_GEOMETRY;
    }
    p = p * slots;
    i = i + 1;
  }
  return 0;
}

// Reset and (re)build the wheel for a validated geometry. Every vector is
// re-sized here and the entry pool plus fired output are pre-filled with
// pushes (then cleared) so that no later push reallocates.
// Complexity: O(levels * slots + capacity).
fn _tw_setup(levels: Int, slots: Int) {
  _tw_levels = levels;
  _tw_slots = slots;
  _tw_now = 0;
  _tw_pending = 0;
  _tw_cascades = 0;
  _tw_pool_count = 0;
  _tw_free_head = _TW_NONE;

  _tw_g.clear();
  var g = 1;
  var i = 0;
  while i < levels {
    _tw_g.push(g);
    g = g * slots;
    i = i + 1;
  }

  _tw_head.clear();
  _tw_tail.clear();
  let buckets = levels * slots;
  i = 0;
  while i < buckets {
    _tw_head.push(_TW_NONE);
    _tw_tail.push(_TW_NONE);
    i = i + 1;
  }

  _tw_ids.clear();
  _tw_dl.clear();
  _tw_lvl.clear();
  _tw_slot.clear();
  _tw_alive.clear();
  _tw_next.clear();
  i = 0;
  while i < _TW_CAPACITY {
    _tw_ids.push(0);
    _tw_dl.push(0);
    _tw_lvl.push(0);
    _tw_slot.push(0);
    _tw_alive.push(0);
    _tw_next.push(_TW_NONE);
    i = i + 1;
  }

  _tw_fired.clear();
  i = 0;
  while i < _TW_CAPACITY {
    _tw_fired.push(0);
    i = i + 1;
  }
  _tw_fired.clear();

  _tw_configured = true;
}

// Configure the default geometry when nothing was configured yet, so the
// public API works without an explicit timer_configure call.
fn _tw_ensure() {
  if !_tw_configured {
    _tw_setup(_TW_DEF_LEVELS, _TW_DEF_SLOTS);
  }
}

// Largest valid delay for the current geometry: slots^levels - 1.
fn _tw_max_delay() -> Int {
  let top: Int = _tw_g[_tw_levels - 1];
  return top * _tw_slots - 1;
}

// 0 when `d` is a valid insert delay, else code 6 (non-positive) or 7
// (above the geometry maximum).
fn _tw_delay_code(d: Int) -> Int {
  if d <= 0 {
    return _TW_ERR_DELAY_POSITIVE;
  }
  let md = _tw_max_delay();
  if d > md {
    return _TW_ERR_DELAY_MAX;
  }
  return 0;
}

// Lowest level whose coverage holds remaining delay r: the smallest L with
// r < slots^(L+1), capped at levels-1. Callers pass 1 <= r <= max_delay.
fn _tw_level_for(r: Int) -> Int {
  var l = 0;
  while l + 1 < _tw_levels {
    let next: Int = _tw_g[l + 1];
    if r < next {
      return l;
    }
    l = l + 1;
  }
  return l;
}

// Bucket index of (level, slot) inside the head/tail vectors.
fn _tw_bucket(level: Int, slot: Int) -> Int {
  return level * _tw_slots + slot;
}

// --------------------------------------------------
//  Bucket chains and pool slots
// --------------------------------------------------

// Append pool slot `idx` as the tail of bucket (level, slot). Entries already
// in the bucket keep their relative order, so the chain is FIFO.
fn _tw_enqueue(idx: Int, level: Int, slot: Int) {
  _tw_lvl[idx] = level;
  _tw_slot[idx] = slot;
  _tw_next[idx] = _TW_NONE;
  let b = _tw_bucket(level, slot);
  let tail: Int = _tw_tail[b];
  if tail < 0 {
    _tw_head[b] = idx;
    _tw_tail[b] = idx;
  } else {
    _tw_next[tail] = idx;
    _tw_tail[b] = idx;
  }
}

// Detach and return the whole chain of bucket (level, slot) as its head
// index, or -1 when empty. Both ends are cleared for the re-link pass.
fn _tw_detach(level: Int, slot: Int) -> Int {
  let b = _tw_bucket(level, slot);
  let head: Int = _tw_head[b];
  _tw_head[b] = _TW_NONE;
  _tw_tail[b] = _TW_NONE;
  return head;
}

// Reserve a pool slot: a released slot when one exists, else the next
// never-used slot. Returns -1 (_TW_NONE) when all capacity is live.
fn _tw_alloc() -> Int {
  if _tw_free_head >= 0 {
    let idx: Int = _tw_free_head;
    _tw_free_head = _tw_next[idx];
    return idx;
  }
  if _tw_pool_count >= _TW_CAPACITY {
    return _TW_NONE;
  }
  let idx: Int = _tw_pool_count;
  _tw_pool_count = _tw_pool_count + 1;
  return idx;
}

// Mark pool slot `idx` dead and release it for reuse. The caller must have
// unlinked the slot from its bucket chain first.
fn _tw_release(idx: Int) {
  _tw_alive[idx] = 0;
  _tw_next[idx] = _tw_free_head;
  _tw_free_head = idx;
  _tw_pending = _tw_pending - 1;
}

// Append the id of pool slot `idx` to the fired output and release the slot.
fn _tw_fire(idx: Int) {
  let id: Int = _tw_ids[idx];
  _tw_fired.push(id);
  _tw_release(idx);
}

// Index of the active entry with `id`, or -1.
fn _tw_find(id: Int) -> Int {
  var i = 0;
  while i < _tw_pool_count {
    if _tw_alive[i] == 1 {
      let eid: Int = _tw_ids[i];
      if eid == id {
        return i;
      }
    }
    i = i + 1;
  }
  return _TW_NONE;
}

// Unlink pool slot `idx` from its bucket chain. Complexity: O(chain).
fn _tw_unlink(idx: Int) {
  let lvl: Int = _tw_lvl[idx];
  let sl: Int = _tw_slot[idx];
  let b = _tw_bucket(lvl, sl);
  var cur: Int = _tw_head[b];
  var prev = _TW_NONE;
  while cur >= 0 {
    if cur == idx {
      let nxt: Int = _tw_next[cur];
      if prev < 0 {
        _tw_head[b] = nxt;
      } else {
        _tw_next[prev] = nxt;
      }
      if _tw_tail[b] == cur {
        _tw_tail[b] = prev;
      }
      _tw_next[cur] = _TW_NONE;
      return;
    }
    prev = cur;
    cur = _tw_next[cur];
  }
}

// --------------------------------------------------
//  Cascading and stepping
// --------------------------------------------------

// Re-bucket every live entry of bucket (level, slot), called when that
// bucket's window opens (every slots^level ticks). Each entry is either
// fired (deadline <= now), cascaded strictly downward to the level its
// remaining delay now demands, or parked unchanged when its own window has
// not opened yet. Chain order is preserved into each destination bucket, so
// same-deadline FIFO holds there too. Every downward move bumps the cascade
// counter. Complexity: O(chain + levels) per entry.
fn _tw_cascade(level: Int, slot: Int) {
  let head: Int = _tw_detach(level, slot);
  if head < 0 {
    return;
  }
  var idx = head;
  while idx >= 0 {
    let nxt: Int = _tw_next[idx];
    if _tw_alive[idx] == 1 {
      let dl: Int = _tw_dl[idx];
      let r = dl - _tw_now;
      if r <= 0 {
        _tw_fire(idx);
      } else {
        let nl = _tw_level_for(r);
        if nl >= level {
          _tw_enqueue(idx, level, slot);
        } else {
          _tw_cascades = _tw_cascades + 1;
          let g: Int = _tw_g[nl];
          let ns = (dl / g) % _tw_slots;
          _tw_enqueue(idx, nl, ns);
        }
      }
    }
    idx = nxt;
  }
}

// Advance exactly one tick: first open every higher-level window that starts
// at the new time (highest first, so an entry cascaded down this tick is
// caught by the lower levels in the same tick), then fire the level-0 bucket
// that is now current.
fn _tw_step() {
  _tw_now = _tw_now + 1;
  var l = _tw_levels - 1;
  while l >= 1 {
    let g: Int = _tw_g[l];
    if _tw_now % g == 0 {
      let s = (_tw_now / g) % _tw_slots;
      _tw_cascade(l, s);
    }
    l = l - 1;
  }
  let s0 = _tw_now % _tw_slots;
  let head: Int = _tw_detach(0, s0);
  if head < 0 {
    return;
  }
  var idx = head;
  while idx >= 0 {
    let nxt: Int = _tw_next[idx];
    if _tw_alive[idx] == 1 {
      let r = _tw_dl[idx] - _tw_now;
      if r <= 0 {
        _tw_fire(idx);
      } else {
        // Unreachable by the level-0 invariant (a level-0 entry is always
        // due within one slot); park it for the next wrap instead of firing
        // early, keeping the failure deterministic rather than silent.
        _tw_enqueue(idx, 0, s0);
      }
    }
    idx = nxt;
  }
}

// --------------------------------------------------
//  Public API -- configuration
// --------------------------------------------------

/// Configure a `levels` x `slots` wheel, resetting every entry, the clock and
/// the counters (configure is a full reset, not a resize).
/// Params: levels - hierarchy depth, 1..8; slots - buckets per level, 2..1024.
/// Returns: Ok(max_delay) with max_delay = slots^levels - 1, the largest
/// delay the following inserts may pass.
/// Error case (code, id, delay): 1 levels < 1 (id = levels, delay = slots);
/// 2 slots < 2; 3 levels > 8; 4 slots > 1024; 5 slots^levels > 2^32. On Err
/// the previous configuration and all entries are unchanged.
/// Complexity: O(levels * slots + capacity).
pub fn timer_configure(levels: Int, slots: Int) -> Result[Int, TimerError] {
  let code: Int = _tw_geometry_code(levels, slots);
  if code != 0 {
    return _tw_err(code, levels, slots);
  }
  _tw_setup(levels, slots);
  return _tw_ok(_tw_max_delay());
}

/// Number of levels of the active geometry. Complexity: O(1).
pub fn timer_levels() -> Int {
  _tw_ensure();
  return _tw_levels;
}

/// Number of buckets per level of the active geometry. Complexity: O(1).
pub fn timer_slots() -> Int {
  _tw_ensure();
  return _tw_slots;
}

/// Largest delay timer_insert accepts: slots^levels - 1. With the default
/// 4 x 64 geometry this is 16777215. Complexity: O(1).
pub fn timer_max_delay() -> Int {
  _tw_ensure();
  return _tw_max_delay();
}

/// Concurrent entry capacity of the pre-sized pool: 1024. Slots freed by a
/// fire or a cancel are reused, so this bounds simultaneously active entries,
/// not the lifetime insert count. Complexity: O(1).
pub fn timer_capacity() -> Int {
  _tw_ensure();
  return _TW_CAPACITY;
}

/// Current tick counter. Starts at 0 after every timer_configure and grows by
/// the ticks accepted by timer_advance. Complexity: O(1).
pub fn timer_now() -> Int {
  _tw_ensure();
  return _tw_now;
}

/// Number of active entries (inserted, not yet fired or cancelled).
/// Complexity: O(1).
pub fn timer_pending_count() -> Int {
  _tw_ensure();
  return _tw_pending;
}

/// Total downward re-buckets since the last timer_configure. Fires and
/// same-level parks are not counted. Complexity: O(1).
pub fn timer_cascade_count() -> Int {
  _tw_ensure();
  return _tw_cascades;
}

/// True when `id` has an active entry. Complexity: O(active entries).
pub fn timer_is_scheduled(id: Int) -> Bool {
  _tw_ensure();
  return _tw_find(id) >= 0;
}

/// Granularity in ticks of `level`: slots^level.
/// Params: level - 0..timer_levels()-1.
/// Returns: Ok(slots^level), or Err code 12 with id = level when out of range.
/// Complexity: O(1).
pub fn timer_level_granularity(level: Int) -> Result[Int, TimerError] {
  _tw_ensure();
  if level < 0 || level >= _tw_levels {
    return _tw_err(_TW_ERR_LEVEL_RANGE, level, _TW_NONE);
  }
  let g: Int = _tw_g[level];
  return _tw_ok(g);
}

// --------------------------------------------------
//  Public API -- scheduling
// --------------------------------------------------

/// Schedule `id` to fire `delay_ticks` ticks after the current time.
/// Params: id - any Int handle not currently active; delay_ticks -
/// 1..timer_max_delay().
/// Returns: Ok(level) - the wheel level the entry was placed at (0 for
/// delays below slots, then one level per further factor of slots).
/// Error case: 6 delay_ticks <= 0 (delay = delay_ticks); 7 delay_ticks >
/// timer_max_delay() (delay = delay_ticks); 8 id already active (id = id);
/// 11 pool full, timer_capacity() live entries (id = id).
/// Complexity: O(active entries) duplicate scan + O(1) bucket link.
pub fn timer_insert(id: Int, delay_ticks: Int) -> Result[Int, TimerError] {
  _tw_ensure();
  if delay_ticks <= 0 {
    return _tw_err(_TW_ERR_DELAY_POSITIVE, id, delay_ticks);
  }
  let md = _tw_max_delay();
  if delay_ticks > md {
    return _tw_err(_TW_ERR_DELAY_MAX, id, delay_ticks);
  }
  if _tw_find(id) >= 0 {
    return _tw_err(_TW_ERR_DUPLICATE_ID, id, delay_ticks);
  }
  let idx = _tw_alloc();
  if idx < 0 {
    return _tw_err(_TW_ERR_FULL, id, delay_ticks);
  }
  let lvl = _tw_level_for(delay_ticks);
  let dl = _tw_now + delay_ticks;
  let g: Int = _tw_g[lvl];
  let slot = (dl / g) % _tw_slots;
  _tw_ids[idx] = id;
  _tw_dl[idx] = dl;
  _tw_alive[idx] = 1;
  _tw_enqueue(idx, lvl, slot);
  _tw_pending = _tw_pending + 1;
  return _tw_ok(lvl);
}

/// Cancel the active entry for `id`.
/// Returns: Ok(remaining) with remaining = deadline - now (>= 1), or Err
/// code 9 with id = id when no active entry has that id.
/// Complexity: O(active entries) lookup + O(bucket chain) unlink.
pub fn timer_cancel(id: Int) -> Result[Int, TimerError] {
  _tw_ensure();
  let idx = _tw_find(id);
  if idx < 0 {
    return _tw_err(_TW_ERR_UNKNOWN_ID, id, _TW_NONE);
  }
  let remaining = _tw_dl[idx] - _tw_now;
  _tw_unlink(idx);
  _tw_release(idx);
  return _tw_ok(remaining);
}

/// Advance the wheel by `ticks` ticks, firing every entry whose deadline is
/// reached. Ticks are integer and simulated; no wall-clock time passes.
/// Params: ticks - number of ticks, >= 0.
/// Returns: Ok(fired) - the number of ids fired by this call, also readable
/// in order through timer_fired_count()/timer_fired_id(i). The fired output
/// is reset by every advance call, including advance(0).
/// Error case: 10 ticks < 0 (delay = ticks); the wheel is unchanged then.
/// Ordering: within one tick, entries fire during the higher-level cascades
/// first (highest level first, bucket chain order) and then from the level-0
/// bucket (chain order). Entries sharing a bucket keep FIFO insert order.
/// Complexity: O(ticks * levels) plus cascade and fire work; when nothing is
/// pending the clock jumps in O(ticks=0-style) O(1).
pub fn timer_advance(ticks: Int) -> Result[Int, TimerError] {
  _tw_ensure();
  if ticks < 0 {
    return _tw_err(_TW_ERR_NEGATIVE_ADVANCE, _TW_NONE, ticks);
  }
  _tw_fired.clear();
  if ticks == 0 {
    return _tw_ok(0);
  }
  if _tw_pending == 0 {
    _tw_now = _tw_now + ticks;
    return _tw_ok(0);
  }
  var k = 0;
  while k < ticks {
    _tw_step();
    k = k + 1;
  }
  return _tw_ok(_tw_fired.len());
}

// --------------------------------------------------
//  Public API -- fired output
// --------------------------------------------------

/// Number of ids fired by the most recent timer_advance; 0 before the first
/// advance and after any advance(0). Complexity: O(1).
pub fn timer_fired_count() -> Int {
  _tw_ensure();
  return _tw_fired.len();
}

/// Id fired at position i of the most recent timer_advance (0-based, in
/// firing order). Params: i - 0..timer_fired_count()-1.
/// Returns: Ok(id), or Err("timer: fired index out of range").
/// Complexity: O(1).
pub fn timer_fired_id(i: Int) -> Result[Int, Str] {
  _tw_ensure();
  if i < 0 || i >= _tw_fired.len() {
    return _tw_err_str("timer: fired index out of range");
  }
  let v: Int = _tw_fired[i];
  return _tw_ok_str(v);
}

// --------------------------------------------------
//  Public API -- test-facing breakdown helpers
// --------------------------------------------------

/// Level the wheel would place a new entry with `delay_ticks` at: the lowest
/// L with delay_ticks < slots^(L+1). Delay validation matches timer_insert.
/// Returns: Ok(level), or Err 6/7 with delay = delay_ticks.
/// Complexity: O(levels).
pub fn timer_bucket_level(delay_ticks: Int) -> Result[Int, TimerError] {
  _tw_ensure();
  let code: Int = _tw_delay_code(delay_ticks);
  if code != 0 {
    return _tw_err(code, _TW_NONE, delay_ticks);
  }
  return _tw_ok(_tw_level_for(delay_ticks));
}

/// Bucket slot a new entry with `delay_ticks` would land in, for a deadline
/// of now + delay_ticks: (deadline / slots^level) % slots. Pinning this makes
/// the divisor/modulo placement testable without touching the entry pool.
/// Delay validation matches timer_insert.
/// Returns: Ok(slot), or Err 6/7 with delay = delay_ticks.
/// Complexity: O(levels).
pub fn timer_bucket_slot(delay_ticks: Int) -> Result[Int, TimerError] {
  _tw_ensure();
  let code: Int = _tw_delay_code(delay_ticks);
  if code != 0 {
    return _tw_err(code, _TW_NONE, delay_ticks);
  }
  let lvl = _tw_level_for(delay_ticks);
  let g: Int = _tw_g[lvl];
  return _tw_ok(((_tw_now + delay_ticks) / g) % _tw_slots);
}

// --------------------------------------------------
//  Public API -- error catalog
// --------------------------------------------------

/// Pinned message for a TimerError code; "timer: unknown error" for codes
/// outside the catalog. Complexity: O(1).
pub fn timer_error_message(code: Int) -> Str {
  if code == _TW_ERR_LEVELS_POSITIVE {
    return "timer: levels must be positive";
  }
  if code == _TW_ERR_SLOTS_MIN {
    return "timer: slots must be at least 2";
  }
  if code == _TW_ERR_LEVELS_MAX {
    return "timer: levels exceeds maximum";
  }
  if code == _TW_ERR_SLOTS_MAX {
    return "timer: slots exceeds maximum";
  }
  if code == _TW_ERR_GEOMETRY {
    return "timer: geometry exceeds maximum delay";
  }
  if code == _TW_ERR_DELAY_POSITIVE {
    return "timer: delay must be positive";
  }
  if code == _TW_ERR_DELAY_MAX {
    return "timer: delay exceeds maximum";
  }
  if code == _TW_ERR_DUPLICATE_ID {
    return "timer: duplicate id";
  }
  if code == _TW_ERR_UNKNOWN_ID {
    return "timer: unknown id";
  }
  if code == _TW_ERR_NEGATIVE_ADVANCE {
    return "timer: negative advance";
  }
  if code == _TW_ERR_FULL {
    return "timer: entry pool is full";
  }
  if code == _TW_ERR_LEVEL_RANGE {
    return "timer: level out of range";
  }
  return "timer: unknown error";
}
