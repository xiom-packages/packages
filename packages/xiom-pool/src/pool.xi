// XIOM -- xiom.pool: deterministic slot pool with leases
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Greenfield package: pure XIOM, no FFI, single-threaded by construction.
//
// A fixed-capacity pool of integer slots: callers keep their own resources
// in a container indexed by slot id, borrow a free slot, and release it when
// done. The pool never allocates, never blocks and never runs a destructor;
// it is a deterministic state machine over integer ids.
//
// Two release paths exist:
//   * pool_release(p, id) -- raw, for callers that track ids themselves;
//   * pool_borrow_lease / pool_release_lease -- an opaque lease token that
//     encodes the slot id and a per-slot generation, so a stale or duplicate
//     release is rejected instead of silently corrupting the free list.
//
// Reuse order is documented: a fresh pool hands out slots in ascending order
// (0, 1, 2, ...); a released slot is reused by the next borrow (LIFO).
//
// Language notes (XIOM v0.61.3): free functions only; flat parallel Vecs
// instead of Vec[StructType]; Vec.pop() returns Option[T]; every Vec element
// read is bound to a typed local before use.

module xiom.pool

use xiom.string;
use xiom.convert;

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[Int, Str].
fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

// Err(m) for Result[Int, Str].
fn _err_int(m: Str) -> Result[Int, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Data model
// --------------------------------------------------

/// A fixed-capacity pool of slots.
/// `free` is the free-slot stack (borrow pops, release pushes); `borrowed`
/// and `generations` are per-slot flags and borrow counters, both of length
/// capacity. `in_use` is the number of currently borrowed slots, `high_water`
/// the maximum it has ever reached, and `borrows` / `releases` the lifetime
/// totals. All four parallel vectors stay index-aligned with the slot ids
/// 0..capacity-1.
pub type Pool = {
  capacity: Int;
  free: Vec[Int];
  borrowed: Vec[Int];
  generations: Vec[Int];
  in_use: Int;
  high_water: Int;
  borrows: Int;
  releases: Int;
}

// --------------------------------------------------
//  Construction and read-only accessors
// --------------------------------------------------

/// A fresh pool with `capacity` free slots. A negative capacity is clamped
/// to 0 (a valid pool that can never hand out a slot).
/// Params: capacity - the number of slots.
/// Returns: the pool; fresh pools hand out slots in ascending order.
/// Error case: none.
/// Complexity: O(capacity).
pub fn pool_new(capacity: Int) -> Pool
  ensures: capacity >= 0 => pool_capacity(result) == capacity;
  ensures: capacity < 0 => pool_capacity(result) == 0;
  ensures: pool_in_use(result) == 0;
{
  var cap = capacity;
  if cap < 0 {
    cap = 0;
  }
  var pool = Pool{
    capacity: cap;
    free: Vec[Int].new();
    borrowed: Vec[Int].new();
    generations: Vec[Int].new();
    in_use: 0;
    high_water: 0;
    borrows: 0;
    releases: 0;
  };
  var i = cap - 1;
  while i >= 0 {
    pool.free.push(i);
    i = i - 1;
  }
  i = 0;
  while i < cap {
    pool.borrowed.push(0);
    pool.generations.push(0);
    i = i + 1;
  }
  return pool;
}

/// Number of slots in the pool.
/// Params: p - the pool.
/// Returns: the capacity.
/// Error case: none.
/// Complexity: O(1).
pub fn pool_capacity(p: &Pool) -> Int
  ensures: result == p.capacity;
{
  let v: Int = p.capacity;
  return v;
}

/// Number of slots currently borrowed.
/// Params: p - the pool.
/// Returns: the borrowed count.
/// Error case: none.
/// Complexity: O(1).
pub fn pool_in_use(p: &Pool) -> Int
  ensures: result == p.in_use;
{
  let v: Int = p.in_use;
  return v;
}

/// Number of slots available for borrowing.
/// Params: p - the pool.
/// Returns: capacity - in_use (never negative).
/// Error case: none.
/// Complexity: O(1).
pub fn pool_available(p: &Pool) -> Int
  ensures: result >= 0;
  ensures: p.capacity - p.in_use >= 0 => result == p.capacity - p.in_use;
  ensures: p.capacity - p.in_use < 0 => result == 0;
{
  let v: Int = p.capacity - p.in_use;
  if v < 0 {
    return 0;
  }
  return v;
}

/// Highest number of simultaneously borrowed slots ever reached.
/// Params: p - the pool.
/// Returns: the high-water mark.
/// Error case: none.
/// Complexity: O(1).
pub fn pool_high_water(p: &Pool) -> Int
  ensures: result == p.high_water;
{
  let v: Int = p.high_water;
  return v;
}

/// Lifetime count of successful borrows.
/// Params: p - the pool.
/// Returns: the total.
/// Error case: none.
/// Complexity: O(1).
pub fn pool_total_borrows(p: &Pool) -> Int
  ensures: result == p.borrows;
{
  let v: Int = p.borrows;
  return v;
}

/// Lifetime count of successful releases (including drains).
/// Params: p - the pool.
/// Returns: the total.
/// Error case: none.
/// Complexity: O(1).
pub fn pool_total_releases(p: &Pool) -> Int
  ensures: result == p.releases;
{
  let v: Int = p.releases;
  return v;
}

/// True when slot `id` is currently borrowed.
/// Params: p - the pool; id - the slot id.
/// Returns: the flag; false when `id` is negative or out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn pool_is_borrowed(p: &Pool, id: Int) -> Bool
  ensures: id < 0 => !result;
  ensures: id >= p.capacity => !result;
  ensures: result => id >= 0 && id < p.capacity;
{
  if id < 0 || id >= p.capacity {
    return false;
  }
  let v: Int = p.borrowed[id];
  return v == 1;
}

/// Current borrow generation of slot `id`: 0 before the first borrow, and
/// one higher after every borrow.
/// Params: p - the pool; id - the slot id.
/// Returns: the generation; -1 when `id` is negative or out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn pool_generation(p: &Pool, id: Int) -> Int
  ensures: id < 0 => result == -1;
  ensures: id >= p.capacity => result == -1;
{
  if id < 0 || id >= p.capacity {
    return -1;
  }
  let v: Int = p.generations[id];
  return v;
}

// --------------------------------------------------
//  Borrowing
// --------------------------------------------------

// Pop one free slot id, or -1 when the pool is exhausted.
fn _take_free(p: &mut Pool) -> Int {
  if p.free.len() == 0 {
    return -1;
  }
  let popt = p.free.pop();
  var id = -1;
  match popt {
    Some(v) => { id = v; },
    None => { return -1; },
  }
  return id;
}

// Mark slot `id` borrowed: bump its generation, update the counters.
fn _mark_borrowed(p: &mut Pool, id: Int) {
  let g: Int = p.generations[id];
  p.generations[id] = g + 1;
  p.borrowed[id] = 1;
  let u: Int = p.in_use + 1;
  p.in_use = u;
  if u > p.high_water {
    p.high_water = u;
  }
  let b: Int = p.borrows + 1;
  p.borrows = b;
}

/// Borrow one free slot.
/// Params: p - the pool.
/// Returns: Ok(id) with a free slot id. A fresh pool returns 0, then 1, ...;
/// a released slot is reused by the next borrow (LIFO).
/// Error case: Err("pool: exhausted") when no slot is free.
/// Complexity: O(1).
pub fn pool_borrow(p: &mut Pool) -> Result[Int, Str]
  ensures: result is Ok => result.value >= 0;
  ensures: result is Ok => p.in_use == p.in_use@pre + 1;
  ensures: result is Err => p.in_use == p.in_use@pre;
{
  let id = _take_free(p);
  if id < 0 {
    return _err_int("pool: exhausted");
  }
  _mark_borrowed(p, id);
  return _ok_int(id);
}

// Lease token for slot `id` at generation `gen`:
// gen * (capacity + 1) + id. Leases are >= 1.
fn _lease_of(p: &Pool, id: Int, gen: Int) -> Int {
  return gen * (p.capacity + 1) + id;
}

// Slot id encoded in `lease`, or -1 when the token is not decodable for `p`.
fn _lease_slot(p: &Pool, lease: Int) -> Int {
  if lease < 0 {
    return -1;
  }
  let base = p.capacity + 1;
  let gen = lease / base;
  if gen < 1 {
    return -1;
  }
  let id = lease % base;
  if id < 0 || id >= p.capacity {
    return -1;
  }
  return id;
}

/// Borrow one free slot and return an opaque lease token instead of the raw
/// id. The token is valid only for this pool instance and the current
/// borrow; release it with pool_release_lease.
/// Params: p - the pool.
/// Returns: Ok(lease) with lease >= 1.
/// Error case: Err("pool: exhausted") when no slot is free.
/// Complexity: O(1).
pub fn pool_borrow_lease(p: &mut Pool) -> Result[Int, Str]
  ensures: result is Ok => p.in_use == p.in_use@pre + 1;
  ensures: result is Ok => p.borrows == p.borrows@pre + 1;
  ensures: result is Err => p.in_use == p.in_use@pre;
{
  let id = _take_free(p);
  if id < 0 {
    return _err_int("pool: exhausted");
  }
  let g: Int = p.generations[id] + 1;
  _mark_borrowed(p, id);
  return _ok_int(_lease_of(p, id, g));
}

// --------------------------------------------------
//  Releasing
// --------------------------------------------------

// Put slot `id` back on the free stack and update the counters.
fn _put_back(p: &mut Pool, id: Int) {
  p.borrowed[id] = 0;
  p.free.push(id);
  let u: Int = p.in_use - 1;
  p.in_use = u;
  let r: Int = p.releases + 1;
  p.releases = r;
}

// Validate a raw release target: "" on success, else the error message.
fn _check_release(p: &Pool, id: Int) -> Str {
  if id < 0 || id >= p.capacity {
    return "pool: bad slot " + int_to_string(id);
  }
  let b: Int = p.borrowed[id];
  if b != 1 {
    return "pool: slot " + int_to_string(id) + " is not borrowed";
  }
  return "";
}

/// Release one borrowed slot by raw id.
/// Params: p - the pool; id - the slot to release.
/// Returns: Ok(id) after the slot was returned to the free stack.
/// Error case: Err("pool: bad slot <id>") when `id` is negative or out of
/// range; Err("pool: slot <id> is not borrowed") when the slot is already
/// free (a repeated release is rejected, never counted twice).
/// Complexity: O(1).
pub fn pool_release(p: &mut Pool, id: Int) -> Result[Int, Str]
  ensures: result is Ok => result.value == id;
  ensures: result is Ok => p.releases == p.releases@pre + 1;
  ensures: result is Err => p.releases == p.releases@pre;
{
  let err = _check_release(p, id);
  if err.len() > 0 {
    return _err_int(err);
  }
  _put_back(p, id);
  return _ok_int(id);
}

/// Release a slot through the lease token returned by pool_borrow_lease.
/// The token must encode the slot's current generation and the slot must be
/// borrowed, so a duplicate or stale release is rejected without touching
/// the free stack.
/// Params: p - the pool; lease - the token from pool_borrow_lease.
/// Returns: Ok(id) with the decoded slot id.
/// Error case: Err("pool: bad lease <lease>") when the token is not
/// decodable for this pool; Err("pool: stale lease <lease>") when it is
/// decodable but the slot is free or its generation has moved on.
/// Complexity: O(1).
pub fn pool_release_lease(p: &mut Pool, lease: Int) -> Result[Int, Str]
  ensures: result is Ok => result.value >= 0;
  ensures: result is Ok => p.releases == p.releases@pre + 1;
  ensures: result is Err => p.releases == p.releases@pre;
{
  let id = _lease_slot(p, lease);
  if id < 0 {
    return _err_int("pool: bad lease " + int_to_string(lease));
  }
  let gen = lease / (p.capacity + 1);
  let cur: Int = p.generations[id];
  let b: Int = p.borrowed[id];
  if gen != cur || b != 1 {
    return _err_int("pool: stale lease " + int_to_string(lease));
  }
  _put_back(p, id);
  return _ok_int(id);
}

/// Release every borrowed slot.
/// Params: p - the pool.
/// Returns: the number of slots released (0 when nothing was borrowed); the
/// lifetime release counter grows by that number and the free stack is
/// rebuilt so the next borrows follow the fresh-pool order.
/// Error case: none.
/// Complexity: O(capacity).
pub fn pool_drain(p: &mut Pool) -> Int
  ensures: result >= 0;
  ensures: p.capacity >= 0 => result <= p.capacity;
  ensures: result > 0 => p.in_use == 0;
{
  var released = 0;
  var i = 0;
  let cap: Int = p.capacity;
  while i < cap {
    let b: Int = p.borrowed[i];
    if b == 1 {
      p.borrowed[i] = 0;
      released = released + 1;
    }
    i = i + 1;
  }
  if released == 0 {
    return 0;
  }
  p.free = Vec[Int].new();
  i = cap - 1;
  while i >= 0 {
    p.free.push(i);
    i = i - 1;
  }
  p.in_use = 0;
  let r: Int = p.releases + released;
  p.releases = r;
  return released;
}
