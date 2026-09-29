// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// XIOM -- xiom.countdown: pure deterministic countdown latches over ticks
//
// Scope (full rules in SPEC.md):
//   * A process-wide registry of integer handles, each a countdown latch
//     driven only by explicit tick calls. Nothing reads a clock, sleeps,
//     spawns threads or calls FFI; the caller owns the clock and feeds
//     elapsed ticks to countdown_advance.
//   * Two modes: a one-shot countdown fires once after `ticks` accepted
//     ticks and then stays disarmed until re-armed; a repeating countdown
//     fires every `period` accepted ticks, auto-re-arms, and records every
//     expiry.
//   * Fan-out waiting: many waiters can observe one latch. A waiter
//     registered at generation g is released when the latch's monotonic
//     expiry counter passes g; countdown_wait_ack re-arms the waiter to the
//     current generation. One expiry releases every pending waiter.
//   * Reset/re-arm: countdown_reset(handle, ticks) re-arms with a new
//     duration (one-shot initial or repeating period); countdown_rearm(handle)
//     re-arms with the stored duration. Both clear elapsed, preserve the
//     monotonic expiry counter and the registered waiters.
//   * Overflow-safe arithmetic: accepted ticks never let `elapsed` pass
//     _CD_MAX (2^62 - 1); an advance that would is rejected untouched, and
//     the repeating-expiry formula is written so every intermediate product
//     stays below 2^63.
//   * Storage is parallel primitive vectors only: no Vec[StructType], no
//     maps, no heap nodes, no methods, no callbacks. Two pre-sized pools
//     (handles and waiters) recycle slots through free lists.
//
// v0.62.1 traps that shaped this module:
//   * free functions only; module-level parallel vectors;
//   * every Vec[Int] read goes through a typed local;
//   * Ok/Err are constructed only in the leaf helpers below;
//   * only Int arithmetic (+, -, *, /, %), no bitwise ops and no `as` casts;
//   * no `&mut Int` out-parameters: every operation returns a value or a
//     Result.

module xiom.countdown

// --------------------------------------------------
//  Constants
// --------------------------------------------------

// Simultaneous countdown handle capacity of the pre-sized pool.
const _CD_CAPACITY: Int = 256;

// Simultaneous registered-waiter capacity of the pre-sized pool.
const _CD_WAITER_CAPACITY: Int = 512;

// Largest accepted duration and largest reachable `elapsed`: 2^62 - 1.
// Keeping every accepted tick sum under it makes all intermediate products
// of the repeating-expiry formula stay below 2^63, so Int arithmetic never
// wraps. An advance that would pass it is rejected with code 4.
const _CD_MAX: Int = 4611686018427387903;

// "Not applicable" filler for unused CountdownError fields.
const _CD_NONE: Int = -1;

// CountdownError codes (messages pinned in countdown_error_message).
const _CD_ERR_TICKS_POSITIVE: Int = 1;
const _CD_ERR_TICKS_MAX: Int = 2;
const _CD_ERR_NEGATIVE_ADVANCE: Int = 3;
const _CD_ERR_OVERFLOW: Int = 4;
const _CD_ERR_UNKNOWN_HANDLE: Int = 5;
const _CD_ERR_DISARMED: Int = 6;
const _CD_ERR_FULL: Int = 7;
const _CD_ERR_UNKNOWN_WAITER: Int = 8;
const _CD_ERR_DUPLICATE_WAITER: Int = 9;
const _CD_ERR_WAITER_FULL: Int = 10;
const _CD_ERR_WAITER_INDEX: Int = 11;

// --------------------------------------------------
//  Types
// --------------------------------------------------

/// Typed error carried by every fallible countdown operation.
/// `code` identifies the failure (see countdown_error_message); `handle`
/// carries the offending countdown handle and `value` the offending
/// argument (ticks, waiter id or waiter index) where the rule names one,
/// else -1 (_CD_NONE). Codes 1 and 2 are raised before a handle exists, so
/// their `handle` is -1; code 7 carries -1 in both fields.
pub type CountdownError = {
  code: Int;
  handle: Int;
  value: Int;
}

// --------------------------------------------------
//  Module state (parallel primitive vectors only)
// --------------------------------------------------

// Pool flags and free lists.
var _cd_ready: Bool = false;
var _cd_pool_count: Int = 0;
var _cd_free_head: Int = _CD_NONE;
var _cd_live: Int = 0;

// Per countdown handle, indexed by pool slot.
var _cd_initial: Vec[Int] = Vec[Int].new();
var _cd_remaining: Vec[Int] = Vec[Int].new();
var _cd_elapsed: Vec[Int] = Vec[Int].new();
var _cd_period: Vec[Int] = Vec[Int].new();
var _cd_fires: Vec[Int] = Vec[Int].new();
var _cd_armed: Vec[Int] = Vec[Int].new();
var _cd_alive: Vec[Int] = Vec[Int].new();
var _cd_next: Vec[Int] = Vec[Int].new();

// Per waiter, indexed by waiter slot.
var _cdw_count: Int = 0;
var _cdw_free_head: Int = _CD_NONE;
var _cdw_owner: Vec[Int] = Vec[Int].new();
var _cdw_id: Vec[Int] = Vec[Int].new();
var _cdw_since: Vec[Int] = Vec[Int].new();
var _cdw_alive: Vec[Int] = Vec[Int].new();
var _cdw_next: Vec[Int] = Vec[Int].new();

// --------------------------------------------------
//  Result leaves
// --------------------------------------------------

// Ok(v) for Result[Int, CountdownError].
fn _cd_ok(v: Int) -> Result[Int, CountdownError] {
  return Ok(v);
}

// Err(code, handle, value) for Result[Int, CountdownError].
fn _cd_err(code: Int, handle: Int, value: Int) -> Result[Int, CountdownError] {
  let e = CountdownError{ code: code; handle: handle; value: value; };
  return Err(e);
}

// Ok(v) for Result[Bool, CountdownError].
fn _cd_ok_bool(v: Bool) -> Result[Bool, CountdownError] {
  return Ok(v);
}

// Err(code, handle, value) for Result[Bool, CountdownError].
fn _cd_err_bool(code: Int, handle: Int, value: Int) -> Result[Bool, CountdownError] {
  let e = CountdownError{ code: code; handle: handle; value: value; };
  return Err(e);
}

// --------------------------------------------------
//  Setup
// --------------------------------------------------

// Reset every pool and counter. Both pools are pre-filled with pushes and
// then cleared so that no later push reallocates. Complexity: O(capacity).
fn _cd_setup() {
  _cd_pool_count = 0;
  _cd_free_head = _CD_NONE;
  _cd_live = 0;

  _cd_initial.clear();
  _cd_remaining.clear();
  _cd_elapsed.clear();
  _cd_period.clear();
  _cd_fires.clear();
  _cd_armed.clear();
  _cd_alive.clear();
  _cd_next.clear();
  var i = 0;
  while i < _CD_CAPACITY {
    _cd_initial.push(0);
    _cd_remaining.push(0);
    _cd_elapsed.push(0);
    _cd_period.push(0);
    _cd_fires.push(0);
    _cd_armed.push(0);
    _cd_alive.push(0);
    _cd_next.push(_CD_NONE);
    i = i + 1;
  }

  _cdw_count = 0;
  _cdw_free_head = _CD_NONE;
  _cdw_owner.clear();
  _cdw_id.clear();
  _cdw_since.clear();
  _cdw_alive.clear();
  _cdw_next.clear();
  i = 0;
  while i < _CD_WAITER_CAPACITY {
    _cdw_owner.push(_CD_NONE);
    _cdw_id.push(0);
    _cdw_since.push(0);
    _cdw_alive.push(0);
    _cdw_next.push(_CD_NONE);
    i = i + 1;
  }

  _cd_ready = true;
}

// Configure the registry on first use so the public API works without an
// explicit countdown_clear call.
fn _cd_ensure() {
  if !_cd_ready {
    _cd_setup();
  }
}

// --------------------------------------------------
//  Slot bookkeeping
// --------------------------------------------------

// True when `h` is a live countdown handle.
fn _cd_valid(h: Int) -> Bool {
  if h < 0 {
    return false;
  }
  if h >= _cd_pool_count {
    return false;
  }
  let a: Int = _cd_alive[h];
  return a == 1;
}

// Reserve a countdown slot: a released slot when one exists, else the next
// never-used slot. Returns -1 (_CD_NONE) when all capacity is live.
fn _cd_alloc() -> Int {
  if _cd_free_head >= 0 {
    let idx: Int = _cd_free_head;
    _cd_free_head = _cd_next[idx];
    return idx;
  }
  if _cd_pool_count >= _CD_CAPACITY {
    return _CD_NONE;
  }
  let idx: Int = _cd_pool_count;
  _cd_pool_count = _cd_pool_count + 1;
  return idx;
}

// Reserve a waiter slot under the same free-list discipline.
fn _cdw_alloc() -> Int {
  if _cdw_free_head >= 0 {
    let idx: Int = _cdw_free_head;
    _cdw_free_head = _cdw_next[idx];
    return idx;
  }
  if _cdw_count >= _CD_WAITER_CAPACITY {
    return _CD_NONE;
  }
  let idx: Int = _cdw_count;
  _cdw_count = _cdw_count + 1;
  return idx;
}

// Release waiter slot `w` back to the waiter free list.
fn _cdw_release(w: Int) {
  _cdw_alive[w] = 0;
  _cdw_owner[w] = _CD_NONE;
  _cdw_next[w] = _cdw_free_head;
  _cdw_free_head = w;
}

// Drop every waiter owned by `owner` and return how many were removed.
fn _cd_remove_waiters(owner: Int) -> Int {
  var removed = 0;
  var i = 0;
  while i < _cdw_count {
    let a: Int = _cdw_alive[i];
    if a == 1 {
      let o: Int = _cdw_owner[i];
      if o == owner {
        _cdw_release(i);
        removed = removed + 1;
      }
    }
    i = i + 1;
  }
  return removed;
}

// Waiter slot observing (owner, waiter_id), or -1.
fn _cd_find_wait(owner: Int, wid: Int) -> Int {
  var i = 0;
  while i < _cdw_count {
    let a: Int = _cdw_alive[i];
    if a == 1 {
      let o: Int = _cdw_owner[i];
      if o == owner {
        let cur: Int = _cdw_id[i];
        if cur == wid {
          return i;
        }
      }
    }
    i = i + 1;
  }
  return _CD_NONE;
}

// True when waiter slot `w` belongs to `owner` and its generation is behind
// the owner's monotonic expiry counter.
fn _cdw_released(w: Int, owner: Int) -> Bool {
  let a: Int = _cdw_alive[w];
  if a != 1 {
    return false;
  }
  let o: Int = _cdw_owner[w];
  if o != owner {
    return false;
  }
  let since: Int = _cdw_since[w];
  let f: Int = _cd_fires[owner];
  return f > since;
}

// Live waiters owned by `owner`.
fn _cd_waiters_of(owner: Int) -> Int {
  var n = 0;
  var i = 0;
  while i < _cdw_count {
    let a: Int = _cdw_alive[i];
    if a == 1 {
      let o: Int = _cdw_owner[i];
      if o == owner {
        n = n + 1;
      }
    }
    i = i + 1;
  }
  return n;
}

// Live waiters of `owner` whose generation is behind its expiry counter.
fn _cd_released_waiters_of(owner: Int) -> Int {
  var n = 0;
  var i = 0;
  while i < _cdw_count {
    if _cdw_released(i, owner) {
      n = n + 1;
    }
    i = i + 1;
  }
  return n;
}

// Live waiters across every countdown.
fn _cd_waiter_total() -> Int {
  var n = 0;
  var i = 0;
  while i < _cdw_count {
    let a: Int = _cdw_alive[i];
    if a == 1 {
      n = n + 1;
    }
    i = i + 1;
  }
  return n;
}

// --------------------------------------------------
//  Public API -- registry lifecycle
// --------------------------------------------------

/// Drop every countdown and waiter and reset both pools. Handles from
/// before the call are invalid afterwards and later creates start at slot 0
/// again. Complexity: O(capacity).
pub fn countdown_clear() {
  _cd_setup();
}

/// Number of live countdowns. Complexity: O(1).
pub fn countdown_count() -> Int {
  _cd_ensure();
  return _cd_live;
}

/// Simultaneous countdown capacity of the pre-sized pool: 256. Slots freed
/// by countdown_destroy are reused, so this bounds simultaneously live
/// countdowns, not the lifetime create count. Complexity: O(1).
pub fn countdown_capacity() -> Int {
  _cd_ensure();
  return _CD_CAPACITY;
}

/// Simultaneous registered-waiter capacity of the pre-sized pool: 512.
/// Complexity: O(1).
pub fn countdown_waiter_capacity() -> Int {
  _cd_ensure();
  return _CD_WAITER_CAPACITY;
}

/// Number of registered waiters across every countdown. Complexity: O(waiters).
pub fn countdown_waiter_total() -> Int {
  _cd_ensure();
  return _cd_waiter_total();
}

/// True when `handle` is a live countdown. Complexity: O(1).
pub fn countdown_is_valid(handle: Int) -> Bool {
  _cd_ensure();
  return _cd_valid(handle);
}

/// Create a one-shot countdown that fires once after `ticks` accepted ticks.
/// Params: ticks - 1.._CD_MAX.
/// Returns: Ok(handle), the pool slot the countdown lives in.
/// Error case: 1 ticks <= 0 (value = ticks); 2 ticks > _CD_MAX
/// (value = ticks); 7 all 256 slots live (handle = value = -1).
/// Complexity: O(1) amortized; O(capacity) on the first call.
pub fn countdown_create(ticks: Int) -> Result[Int, CountdownError] {
  _cd_ensure();
  if ticks <= 0 {
    return _cd_err(_CD_ERR_TICKS_POSITIVE, _CD_NONE, ticks);
  }
  if ticks > _CD_MAX {
    return _cd_err(_CD_ERR_TICKS_MAX, _CD_NONE, ticks);
  }
  let idx = _cd_alloc();
  if idx < 0 {
    return _cd_err(_CD_ERR_FULL, _CD_NONE, _CD_NONE);
  }
  _cd_initial[idx] = ticks;
  _cd_remaining[idx] = ticks;
  _cd_elapsed[idx] = 0;
  _cd_period[idx] = 0;
  _cd_fires[idx] = 0;
  _cd_armed[idx] = 1;
  _cd_alive[idx] = 1;
  _cd_live = _cd_live + 1;
  return _cd_ok(idx);
}

/// Create a repeating countdown that fires every `period` accepted ticks,
/// auto-re-arms after every expiry and never disarms.
/// Params: period - 1.._CD_MAX, the interval between expiries.
/// Returns: Ok(handle), the pool slot the countdown lives in.
/// Error case: 1 period <= 0; 2 period > _CD_MAX; 7 all 256 slots live.
/// Complexity: O(1) amortized; O(capacity) on the first call.
pub fn countdown_create_repeating(period: Int) -> Result[Int, CountdownError] {
  _cd_ensure();
  if period <= 0 {
    return _cd_err(_CD_ERR_TICKS_POSITIVE, _CD_NONE, period);
  }
  if period > _CD_MAX {
    return _cd_err(_CD_ERR_TICKS_MAX, _CD_NONE, period);
  }
  let idx = _cd_alloc();
  if idx < 0 {
    return _cd_err(_CD_ERR_FULL, _CD_NONE, _CD_NONE);
  }
  _cd_initial[idx] = period;
  _cd_remaining[idx] = period;
  _cd_elapsed[idx] = 0;
  _cd_period[idx] = period;
  _cd_fires[idx] = 0;
  _cd_armed[idx] = 1;
  _cd_alive[idx] = 1;
  _cd_live = _cd_live + 1;
  return _cd_ok(idx);
}

/// Destroy a countdown: unregister every waiter it owns and release its
/// slot for reuse.
/// Returns: Ok(removed_waiters), the number of waiters unregistered.
/// Error case: 5 unknown handle (value = -1).
/// Complexity: O(waiters).
pub fn countdown_destroy(handle: Int) -> Result[Int, CountdownError] {
  _cd_ensure();
  if !_cd_valid(handle) {
    return _cd_err(_CD_ERR_UNKNOWN_HANDLE, handle, _CD_NONE);
  }
  let removed = _cd_remove_waiters(handle);
  _cd_alive[handle] = 0;
  _cd_next[handle] = _cd_free_head;
  _cd_free_head = handle;
  _cd_live = _cd_live - 1;
  return _cd_ok(removed);
}

// --------------------------------------------------
//  Public API -- ticks
// --------------------------------------------------

/// Advance a countdown by `ticks` accepted ticks and return the number of
/// expiries this call recorded.
/// Params: ticks - number of ticks, >= 0.
/// Returns: Ok(expiries), 0 or more. A one-shot fires at most once and
/// absorbs the overshoot in `elapsed`; a repeating countdown fires once per
/// crossed period boundary, so a large advance can record many expiries.
/// Zero ticks is always a no-op Ok(0), even on a disarmed countdown.
/// Error case: 5 unknown handle (value = ticks); 3 ticks < 0; 6 one-shot
/// already disarmed (value = ticks); 4 elapsed + ticks > _CD_MAX. On Err the
/// countdown is untouched.
/// Complexity: O(1).
pub fn countdown_advance(handle: Int, ticks: Int) -> Result[Int, CountdownError] {
  _cd_ensure();
  if !_cd_valid(handle) {
    return _cd_err(_CD_ERR_UNKNOWN_HANDLE, handle, ticks);
  }
  if ticks < 0 {
    return _cd_err(_CD_ERR_NEGATIVE_ADVANCE, handle, ticks);
  }
  if ticks == 0 {
    return _cd_ok(0);
  }
  let armed: Int = _cd_armed[handle];
  let period: Int = _cd_period[handle];
  if period == 0 && armed == 0 {
    return _cd_err(_CD_ERR_DISARMED, handle, ticks);
  }
  let elapsed: Int = _cd_elapsed[handle];
  if ticks > _CD_MAX - elapsed {
    return _cd_err(_CD_ERR_OVERFLOW, handle, ticks);
  }
  let remaining: Int = _cd_remaining[handle];
  let fires: Int = _cd_fires[handle];
  if ticks < remaining {
    _cd_remaining[handle] = remaining - ticks;
    _cd_elapsed[handle] = elapsed + ticks;
    return _cd_ok(0);
  }
  if period == 0 {
    // One-shot expiry: exactly one expiry; overshoot lives in elapsed.
    _cd_remaining[handle] = 0;
    _cd_elapsed[handle] = elapsed + ticks;
    _cd_armed[handle] = 0;
    _cd_fires[handle] = fires + 1;
    return _cd_ok(1);
  }
  // Repeating expiry: ticks >= remaining >= 1 and period >= 1, so both
  // divisions are floor divisions of non-negative values. k*period never
  // passes ticks + period, so every intermediate stays below 2^63.
  let k = 1 + (ticks - remaining) / period;
  _cd_remaining[handle] = remaining + k * period - ticks;
  _cd_elapsed[handle] = elapsed + ticks;
  _cd_fires[handle] = fires + k;
  return _cd_ok(k);
}

/// Re-arm a countdown with a new duration: for a one-shot it becomes the new
/// initial value, for a repeating countdown the new period. `elapsed` resets
/// to 0, the countdown arms, the monotonic expiry counter and the registered
/// waiters are preserved.
/// Params: ticks - 1.._CD_MAX.
/// Returns: Ok(ticks).
/// Error case: 5 unknown handle (value = ticks); 1 ticks <= 0; 2 ticks >
/// _CD_MAX. On Err the countdown is untouched.
/// Complexity: O(1).
pub fn countdown_reset(handle: Int, ticks: Int) -> Result[Int, CountdownError] {
  _cd_ensure();
  if !_cd_valid(handle) {
    return _cd_err(_CD_ERR_UNKNOWN_HANDLE, handle, ticks);
  }
  if ticks <= 0 {
    return _cd_err(_CD_ERR_TICKS_POSITIVE, handle, ticks);
  }
  if ticks > _CD_MAX {
    return _cd_err(_CD_ERR_TICKS_MAX, handle, ticks);
  }
  let period: Int = _cd_period[handle];
  if period == 0 {
    _cd_initial[handle] = ticks;
  } else {
    _cd_period[handle] = ticks;
  }
  _cd_remaining[handle] = ticks;
  _cd_elapsed[handle] = 0;
  _cd_armed[handle] = 1;
  return _cd_ok(ticks);
}

/// Re-arm a countdown with its stored duration: the initial value for a
/// one-shot, the period for a repeating countdown. Same reset rules as
/// countdown_reset.
/// Returns: Ok(ticks), the duration it was re-armed with.
/// Error case: 5 unknown handle (value = -1).
/// Complexity: O(1).
pub fn countdown_rearm(handle: Int) -> Result[Int, CountdownError] {
  _cd_ensure();
  if !_cd_valid(handle) {
    return _cd_err(_CD_ERR_UNKNOWN_HANDLE, handle, _CD_NONE);
  }
  let period: Int = _cd_period[handle];
  var ticks: Int = 0;
  if period == 0 {
    ticks = _cd_initial[handle];
  } else {
    ticks = period;
  }
  _cd_remaining[handle] = ticks;
  _cd_elapsed[handle] = 0;
  _cd_armed[handle] = 1;
  return _cd_ok(ticks);
}

// --------------------------------------------------
//  Public API -- queries
// --------------------------------------------------

/// Ticks left before the next expiry: 0 on a fired one-shot, 1..period on an
/// armed repeating countdown. Complexity: O(1).
pub fn countdown_remaining(handle: Int) -> Result[Int, CountdownError] {
  _cd_ensure();
  if !_cd_valid(handle) {
    return _cd_err(_CD_ERR_UNKNOWN_HANDLE, handle, _CD_NONE);
  }
  let v: Int = _cd_remaining[handle];
  return _cd_ok(v);
}

/// Ticks accepted since the last create/reset/re-arm. Complexity: O(1).
pub fn countdown_elapsed(handle: Int) -> Result[Int, CountdownError] {
  _cd_ensure();
  if !_cd_valid(handle) {
    return _cd_err(_CD_ERR_UNKNOWN_HANDLE, handle, _CD_NONE);
  }
  let v: Int = _cd_elapsed[handle];
  return _cd_ok(v);
}

/// Stored one-shot duration (== the repeating period for a repeating
/// countdown). Complexity: O(1).
pub fn countdown_initial(handle: Int) -> Result[Int, CountdownError] {
  _cd_ensure();
  if !_cd_valid(handle) {
    return _cd_err(_CD_ERR_UNKNOWN_HANDLE, handle, _CD_NONE);
  }
  let v: Int = _cd_initial[handle];
  return _cd_ok(v);
}

/// Repeating period, or 0 for a one-shot countdown. Complexity: O(1).
pub fn countdown_period(handle: Int) -> Result[Int, CountdownError] {
  _cd_ensure();
  if !_cd_valid(handle) {
    return _cd_err(_CD_ERR_UNKNOWN_HANDLE, handle, _CD_NONE);
  }
  let v: Int = _cd_period[handle];
  return _cd_ok(v);
}

/// Monotonic expiry counter: every expiry (any mode) increments it, and
/// reset/re-arm never clears it. Also the waiter generation. Complexity: O(1).
pub fn countdown_fire_count(handle: Int) -> Result[Int, CountdownError] {
  _cd_ensure();
  if !_cd_valid(handle) {
    return _cd_err(_CD_ERR_UNKNOWN_HANDLE, handle, _CD_NONE);
  }
  let v: Int = _cd_fires[handle];
  return _cd_ok(v);
}

/// True while the countdown accepts ticks: a one-shot is armed until its
/// expiry, a repeating countdown is always armed. Complexity: O(1).
pub fn countdown_is_armed(handle: Int) -> Result[Bool, CountdownError] {
  _cd_ensure();
  if !_cd_valid(handle) {
    return _cd_err_bool(_CD_ERR_UNKNOWN_HANDLE, handle, _CD_NONE);
  }
  let a: Int = _cd_armed[handle];
  return _cd_ok_bool(a == 1);
}

/// True once the countdown has expired at least once since creation (the
/// monotonic expiry counter is positive). reset/re-arm does not clear it.
/// Complexity: O(1).
pub fn countdown_is_expired(handle: Int) -> Result[Bool, CountdownError] {
  _cd_ensure();
  if !_cd_valid(handle) {
    return _cd_err_bool(_CD_ERR_UNKNOWN_HANDLE, handle, _CD_NONE);
  }
  let f: Int = _cd_fires[handle];
  return _cd_ok_bool(f > 0);
}

/// Absolute tick count, relative to the current arm, at which the next
/// expiry happens: elapsed + remaining (still >= 1 after an expiry of a
/// repeating countdown, since it re-arms immediately). Complexity: O(1).
pub fn countdown_next_expiry(handle: Int) -> Result[Int, CountdownError] {
  _cd_ensure();
  if !_cd_valid(handle) {
    return _cd_err(_CD_ERR_UNKNOWN_HANDLE, handle, _CD_NONE);
  }
  let e: Int = _cd_elapsed[handle];
  let r: Int = _cd_remaining[handle];
  return _cd_ok(e + r);
}

// --------------------------------------------------
//  Public API -- fan-out waiters
// --------------------------------------------------

/// Register waiter `waiter_id` on `handle` (fan-out: any number of waiters
/// observe one countdown). The waiter starts at the countdown's current
/// expiry generation, so it never observes expiries that happened before it
/// registered.
/// Params: waiter_id - any Int, unique per countdown.
/// Returns: Ok(generation), the expiry counter value the waiter starts at.
/// Error case: 5 unknown handle (value = waiter_id); 9 waiter_id already
/// registered on this countdown (value = waiter_id); 10 all 512 waiter slots
/// live (value = waiter_id).
/// Complexity: O(waiters).
pub fn countdown_watch(handle: Int, waiter_id: Int) -> Result[Int, CountdownError] {
  _cd_ensure();
  if !_cd_valid(handle) {
    return _cd_err(_CD_ERR_UNKNOWN_HANDLE, handle, waiter_id);
  }
  if _cd_find_wait(handle, waiter_id) >= 0 {
    return _cd_err(_CD_ERR_DUPLICATE_WAITER, handle, waiter_id);
  }
  let w = _cdw_alloc();
  if w < 0 {
    return _cd_err(_CD_ERR_WAITER_FULL, handle, waiter_id);
  }
  let gen: Int = _cd_fires[handle];
  _cdw_owner[w] = handle;
  _cdw_id[w] = waiter_id;
  _cdw_since[w] = gen;
  _cdw_alive[w] = 1;
  _cdw_next[w] = _CD_NONE;
  return _cd_ok(gen);
}

/// Unregister waiter `waiter_id` from `handle`.
/// Returns: Ok(remaining), the number of waiters still registered on the
/// countdown.
/// Error case: 5 unknown handle (value = waiter_id); 8 no such waiter on
/// this countdown (value = waiter_id).
/// Complexity: O(waiters).
pub fn countdown_unwatch(handle: Int, waiter_id: Int) -> Result[Int, CountdownError] {
  _cd_ensure();
  if !_cd_valid(handle) {
    return _cd_err(_CD_ERR_UNKNOWN_HANDLE, handle, waiter_id);
  }
  let w = _cd_find_wait(handle, waiter_id);
  if w < 0 {
    return _cd_err(_CD_ERR_UNKNOWN_WAITER, handle, waiter_id);
  }
  _cdw_release(w);
  return _cd_ok(_cd_waiters_of(handle));
}

/// True when `handle` has expired at least once since waiter `waiter_id`
/// registered (or since its last countdown_wait_ack). This is the fan-out
/// observation: one expiry flips every waiter registered before it.
/// Error case: 5 unknown handle (value = waiter_id); 8 unknown waiter.
/// Complexity: O(waiters).
pub fn countdown_wait_released(handle: Int, waiter_id: Int) -> Result[Bool, CountdownError] {
  _cd_ensure();
  if !_cd_valid(handle) {
    return _cd_err_bool(_CD_ERR_UNKNOWN_HANDLE, handle, waiter_id);
  }
  let w = _cd_find_wait(handle, waiter_id);
  if w < 0 {
    return _cd_err_bool(_CD_ERR_UNKNOWN_WAITER, handle, waiter_id);
  }
  let since: Int = _cdw_since[w];
  let f: Int = _cd_fires[handle];
  return _cd_ok_bool(f > since);
}

/// Re-arm waiter `waiter_id` to the countdown's current generation,
/// consuming any pending release.
/// Returns: Ok(was_released), whether the waiter was released before the
/// call.
/// Error case: 5 unknown handle (value = waiter_id); 8 unknown waiter.
/// Complexity: O(waiters).
pub fn countdown_wait_ack(handle: Int, waiter_id: Int) -> Result[Bool, CountdownError] {
  _cd_ensure();
  if !_cd_valid(handle) {
    return _cd_err_bool(_CD_ERR_UNKNOWN_HANDLE, handle, waiter_id);
  }
  let w = _cd_find_wait(handle, waiter_id);
  if w < 0 {
    return _cd_err_bool(_CD_ERR_UNKNOWN_WAITER, handle, waiter_id);
  }
  let since: Int = _cdw_since[w];
  let f: Int = _cd_fires[handle];
  let was: Bool = f > since;
  _cdw_since[w] = f;
  return _cd_ok_bool(was);
}

/// Number of waiters registered on `handle`. Complexity: O(waiters).
pub fn countdown_waiter_count(handle: Int) -> Result[Int, CountdownError] {
  _cd_ensure();
  if !_cd_valid(handle) {
    return _cd_err(_CD_ERR_UNKNOWN_HANDLE, handle, _CD_NONE);
  }
  return _cd_ok(_cd_waiters_of(handle));
}

/// Number of waiters on `handle` that currently observe a release.
/// Complexity: O(waiters).
pub fn countdown_released_waiter_count(handle: Int) -> Result[Int, CountdownError] {
  _cd_ensure();
  if !_cd_valid(handle) {
    return _cd_err(_CD_ERR_UNKNOWN_HANDLE, handle, _CD_NONE);
  }
  return _cd_ok(_cd_released_waiters_of(handle));
}

/// Waiter id at position `i` (0-based) among the live waiters of `handle`,
/// in ascending waiter-slot order. Stable while no waiter is added or
/// removed.
/// Returns: Ok(waiter_id), or Err 11 when `i` is outside
/// 0..countdown_waiter_count(handle)-1.
/// Error case: 5 unknown handle (value = i); 11 index out of range
/// (value = i).
/// Complexity: O(waiters).
pub fn countdown_waiter_at(handle: Int, i: Int) -> Result[Int, CountdownError] {
  _cd_ensure();
  if !_cd_valid(handle) {
    return _cd_err(_CD_ERR_UNKNOWN_HANDLE, handle, i);
  }
  if i < 0 || i >= _cd_waiters_of(handle) {
    return _cd_err(_CD_ERR_WAITER_INDEX, handle, i);
  }
  var seen = 0;
  var w = 0;
  while w < _cdw_count {
    let a: Int = _cdw_alive[w];
    if a == 1 {
      let o: Int = _cdw_owner[w];
      if o == handle {
        if seen == i {
          let wid: Int = _cdw_id[w];
          return _cd_ok(wid);
        }
        seen = seen + 1;
      }
    }
    w = w + 1;
  }
  return _cd_err(_CD_ERR_WAITER_INDEX, handle, i);
}

// --------------------------------------------------
//  Public API -- error catalog
// --------------------------------------------------

/// Pinned message for a CountdownError code; "countdown: unknown error" for
/// codes outside the catalog. Complexity: O(1).
pub fn countdown_error_message(code: Int) -> Str {
  if code == _CD_ERR_TICKS_POSITIVE {
    return "countdown: ticks must be positive";
  }
  if code == _CD_ERR_TICKS_MAX {
    return "countdown: ticks exceed maximum";
  }
  if code == _CD_ERR_NEGATIVE_ADVANCE {
    return "countdown: negative advance";
  }
  if code == _CD_ERR_OVERFLOW {
    return "countdown: elapsed ticks would overflow";
  }
  if code == _CD_ERR_UNKNOWN_HANDLE {
    return "countdown: unknown handle";
  }
  if code == _CD_ERR_DISARMED {
    return "countdown: countdown is disarmed";
  }
  if code == _CD_ERR_FULL {
    return "countdown: countdown capacity is full";
  }
  if code == _CD_ERR_UNKNOWN_WAITER {
    return "countdown: unknown waiter";
  }
  if code == _CD_ERR_DUPLICATE_WAITER {
    return "countdown: duplicate waiter";
  }
  if code == _CD_ERR_WAITER_FULL {
    return "countdown: waiter capacity is full";
  }
  if code == _CD_ERR_WAITER_INDEX {
    return "countdown: waiter index out of range";
  }
  return "countdown: unknown error";
}
