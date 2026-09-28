// XIOM -- xiom.semaphore: counting semaphore as a deterministic state machine
// Port task: replace the xiom.semaphore placeholder with a real, tested,
// pure-XIOM package (no FFI, no threads, no clock).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model: a counting semaphore as a pure, deterministic state machine -- the
// semantic core that a scheduler, atomics backend or blocking runtime would
// drive. There are no threads, no atomics, no clock and no I/O here: the
// caller (or a future backend) owns the concurrency and every function is a
// total transition over plain values.
//
// Semantics: `permits` stays in [0, capacity]; sem_try_acquire takes permits
// or refuses with Err("semaphore: would block"); sem_enqueue_waiter records a
// blocked waiter (FIFO) with its request size; sem_grant_next wakes exactly
// the queue head when its full request fits (strict FIFO, head-of-line
// blocking); sem_release returns permits and refuses over-release.
// `grant_order` is the ordered trace of waiter IDs actually woken, the
// fairness witness.
//
// Language notes (XIOM v0.62.0): free functions only; Ok/Err are constructed
// only inside the _ok_*/_err_* leaf helpers; Vec[Int] element reads are bound
// with a typed `let`; no Vec[StructType], no FFI, no threads. `waiters` and
// `waiter_sizes` are parallel Vec[Int] fields kept mirrored by every mutation.

module xiom.semaphore

use xiom.string;
use xiom.convert;

/// Counting semaphore state. Every field is an internal implementation
/// detail; callers must go through the sem_* free functions.
///
/// `capacity` is fixed at construction; `permits` is the free-permit count
/// and always satisfies 0 <= permits <= capacity. `waiters` is the FIFO queue
/// of blocked waiter IDs (index 0 = oldest) and `waiter_sizes` the parallel
/// Vec of their request sizes: waiters[i] is waiting for waiter_sizes[i]
/// permits. `grants` counts successful grants (sem_try_acquire and
/// sem_grant_next), `blocks` counts enqueued waiters and `releases` counts
/// successful sem_release calls. `grant_order` is the ordered trace of waiter
/// IDs woken by sem_grant_next.
pub type Semaphore = {
  capacity: Int;
  permits: Int;
  waiters: Vec[Int];
  waiter_sizes: Vec[Int];
  grants: Int;
  blocks: Int;
  releases: Int;
  grant_order: Vec[Int];
}

// ---------------------------------------------------------------------------
// Result constructors (leaf helpers only; see the header comment)
// ---------------------------------------------------------------------------

fn _ok_sem(v: Semaphore) -> Result[Semaphore, Str] { return Ok(v); }
fn _err_sem(m: Str) -> Result[Semaphore, Str] { return Err(m); }
fn _ok_int(v: Int) -> Result[Int, Str] { return Ok(v); }
fn _err_int(m: Str) -> Result[Int, Str] { return Err(m); }

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

// True when `id` is already queued.
fn _queue_has(s: &Semaphore, id: Int) -> Bool {
  var i = 0;
  while i < s.waiters.len() {
    let queued: Int = s.waiters[i];
    if queued == id { return true; }
    i = i + 1;
  }
  return false;
}

// Drop the queue head, rebuilding both parallel Vecs in step.
fn _pop_front(s: &mut Semaphore) {
  var ids = Vec[Int].new();
  var sizes = Vec[Int].new();
  var i = 1;
  while i < s.waiters.len() {
    let id: Int = s.waiters[i];
    let sz: Int = s.waiter_sizes[i];
    ids.push(id);
    sizes.push(sz);
    i = i + 1;
  }
  s.waiters = ids;
  s.waiter_sizes = sizes;
}

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

/// Create a semaphore whose capacity is `capacity`, with every permit free.
/// Capacity 0 is valid: every request is refused until a release frees
/// permits. The capacity is fixed for the semaphore's lifetime.
/// Params: capacity - total permits, must be >= 0.
/// Returns: Ok(Semaphore); Err("semaphore: capacity must be >= 0") otherwise.
/// Complexity: O(1).
pub fn sem_new(capacity: Int) -> Result[Semaphore, Str] {
  if capacity < 0 {
    return _err_sem("semaphore: capacity must be >= 0");
  }
  return _ok_sem(Semaphore{
    capacity: capacity;
    permits: capacity;
    waiters: Vec[Int].new();
    waiter_sizes: Vec[Int].new();
    grants: 0;
    blocks: 0;
    releases: 0;
    grant_order: Vec[Int].new();
  });
}

// ---------------------------------------------------------------------------
// Non-blocking acquire
// ---------------------------------------------------------------------------

/// Take `n` permits without blocking.
/// Params: s - the semaphore; n - requested permits, must be >= 1 and
///         <= capacity.
/// Returns: Ok(permits remaining after the grant) when `n` permits were
/// free; Err("semaphore: would block") when fewer than `n` permits are free
/// (no state change); Err("semaphore: n must be >= 1") or Err("semaphore:
/// request exceeds capacity") for an invalid `n` (no state change).
/// A successful take increments the grants counter.
/// Complexity: O(1).
pub fn sem_try_acquire(s: &mut Semaphore, n: Int) -> Result[Int, Str] {
  if n < 1 {
    return _err_int("semaphore: n must be >= 1");
  }
  if n > s.capacity {
    return _err_int("semaphore: request exceeds capacity");
  }
  if n > s.permits {
    return _err_int("semaphore: would block");
  }
  s.permits = s.permits - n;
  s.grants = s.grants + 1;
  return _ok_int(s.permits);
}

// ---------------------------------------------------------------------------
// Blocking model: waiter queue + wakeups
// ---------------------------------------------------------------------------

/// Record a waiter that wants `n` permits and is blocked until granted.
/// The waiter joins the back of the FIFO queue. Waiter IDs must be unique
/// while queued; a waiter may re-enqueue with the same ID after it has been
/// granted. Enqueueing does not require permits to be unavailable -- the
/// caller decides when to model blocking.
/// Params: s - the semaphore; id - caller-assigned waiter ID, >= 0;
///         n - requested permits, >= 1 and <= capacity (a request larger
///         than capacity could never be granted).
/// Returns: Ok(pos) with the 0-based queue position the waiter now occupies;
/// Err("semaphore: waiter id must be >= 0"), Err("semaphore: n must be
/// >= 1"), Err("semaphore: request exceeds capacity") or Err("semaphore:
/// duplicate waiter id") -- in every Err case the state is unchanged.
/// A successful enqueue increments the blocks counter.
/// Complexity: O(queue length) (duplicate scan).
pub fn sem_enqueue_waiter(s: &mut Semaphore, id: Int, n: Int) -> Result[Int, Str] {
  if id < 0 {
    return _err_int("semaphore: waiter id must be >= 0");
  }
  if n < 1 {
    return _err_int("semaphore: n must be >= 1");
  }
  if n > s.capacity {
    return _err_int("semaphore: request exceeds capacity");
  }
  if _queue_has(s, id) {
    return _err_int("semaphore: duplicate waiter id");
  }
  s.waiters.push(id);
  s.waiter_sizes.push(n);
  s.blocks = s.blocks + 1;
  return _ok_int(s.waiters.len() - 1);
}

/// Wake the queue head when its full request fits in the free permits.
/// Strict FIFO: only the head is considered, so a large head request blocks
/// smaller followers (head-of-line blocking) until enough permits
/// accumulate; the queue order is never bypassed.
/// Params: s - the semaphore.
/// Returns: Some(id) when the head waiter was granted: its request is
/// subtracted from permits, the waiter leaves the queue, the grants counter
/// is incremented and the ID is appended to the fairness trace;
/// None when the queue is empty or the head still needs more permits than
/// are free (no state change).
/// Complexity: O(queue length) for the front removal.
pub fn sem_grant_next(s: &mut Semaphore) -> Option[Int] {
  if s.waiters.len() == 0 { return None; }
  let head: Int = s.waiters[0];
  let need: Int = s.waiter_sizes[0];
  if need > s.permits { return None; }
  _pop_front(s);
  s.permits = s.permits - need;
  s.grants = s.grants + 1;
  s.grant_order.push(head);
  return Some(head);
}

// ---------------------------------------------------------------------------
// Release
// ---------------------------------------------------------------------------

/// Return `n` permits to the semaphore.
/// Releasing does not grant queued waiters by itself: the driver calls
/// sem_grant_next to model wakeups. Over-release (permits would exceed
/// capacity) is refused, so the capacity bound always holds.
/// Params: s - the semaphore; n - permits to return, must be >= 1 and
///         <= capacity - permits.
/// Returns: Ok(permits free after the release); Err("semaphore: n must be
/// >= 1") or Err("semaphore: over-release (permits would exceed capacity)")
/// -- in every Err case the state is unchanged. A successful release
/// increments the releases counter.
/// Complexity: O(1).
pub fn sem_release(s: &mut Semaphore, n: Int) -> Result[Int, Str] {
  if n < 1 {
    return _err_int("semaphore: n must be >= 1");
  }
  if n > s.capacity - s.permits {
    return _err_int("semaphore: over-release (permits would exceed capacity)");
  }
  s.permits = s.permits + n;
  s.releases = s.releases + 1;
  return _ok_int(s.permits);
}

// ---------------------------------------------------------------------------
// Drain
// ---------------------------------------------------------------------------

/// Drop every queued waiter, returning their IDs in FIFO order (oldest
/// first). Permits and counters are untouched: the waiters are abandoned,
/// not granted (a shutdown/reset of the waiter set).
/// Params: s - the semaphore.
/// Returns: the removed waiter IDs; the queue is empty afterwards.
/// Complexity: O(queue length).
pub fn sem_drain(s: &mut Semaphore) -> Vec[Int] {
  var ids = Vec[Int].new();
  var i = 0;
  while i < s.waiters.len() {
    let id: Int = s.waiters[i];
    ids.push(id);
    i = i + 1;
  }
  s.waiters = Vec[Int].new();
  s.waiter_sizes = Vec[Int].new();
  return ids;
}

// ---------------------------------------------------------------------------
// Accessors (read-only) and invariant check
// ---------------------------------------------------------------------------

/// Total permits (fixed at construction). Complexity: O(1).
pub fn sem_capacity(s: &Semaphore) -> Int {
  return s.capacity;
}

/// Free permits (always 0 <= permits <= capacity). Complexity: O(1).
pub fn sem_permits(s: &Semaphore) -> Int {
  return s.permits;
}

/// Number of queued waiters. Complexity: O(1).
pub fn sem_queue_len(s: &Semaphore) -> Int {
  return s.waiters.len();
}

/// Waiter ID at FIFO position `index`, or -1 when out of range.
/// Complexity: O(1).
pub fn sem_queue_id_at(s: &Semaphore, index: Int) -> Int {
  if index < 0 { return -1; }
  if index >= s.waiters.len() { return -1; }
  let id: Int = s.waiters[index];
  return id;
}

/// Request size of the waiter at FIFO position `index`, or -1 when out of
/// range. Complexity: O(1).
pub fn sem_queue_size_at(s: &Semaphore, index: Int) -> Int {
  if index < 0 { return -1; }
  if index >= s.waiter_sizes.len() { return -1; }
  let sz: Int = s.waiter_sizes[index];
  return sz;
}

/// Copy of the queued waiter IDs, FIFO order (index 0 = oldest).
/// Complexity: O(queue length).
pub fn sem_queue_ids(s: &Semaphore) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 0;
  while i < s.waiters.len() {
    let id: Int = s.waiters[i];
    out.push(id);
    i = i + 1;
  }
  return out;
}

/// Successful grants so far (sem_try_acquire plus sem_grant_next).
/// Complexity: O(1).
pub fn sem_grant_count(s: &Semaphore) -> Int {
  return s.grants;
}

/// Waiters enqueued so far (successful sem_enqueue_waiter calls).
/// Complexity: O(1).
pub fn sem_block_count(s: &Semaphore) -> Int {
  return s.blocks;
}

/// Successful sem_release calls so far. Complexity: O(1).
pub fn sem_release_count(s: &Semaphore) -> Int {
  return s.releases;
}

/// Length of the fairness trace: waiters woken by sem_grant_next.
/// Complexity: O(1).
pub fn sem_grant_order_len(s: &Semaphore) -> Int {
  return s.grant_order.len();
}

/// Copy of the ordered wakeup trace: waiter IDs in the order sem_grant_next
/// granted them. Complexity: O(trace length).
pub fn sem_grant_order(s: &Semaphore) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 0;
  while i < s.grant_order.len() {
    let id: Int = s.grant_order[i];
    out.push(id);
    i = i + 1;
  }
  return out;
}

/// Fairness trace rendered as comma-separated waiter IDs in wakeup order,
/// "" when nothing has been woken. Complexity: O(trace length).
pub fn sem_grant_trace(s: &Semaphore) -> Str {
  var out = "";
  var i = 0;
  while i < s.grant_order.len() {
    let id: Int = s.grant_order[i];
    if i > 0 { out = out + ","; }
    out = out + convert.int_to_string(id);
    i = i + 1;
  }
  return out;
}

/// Structural invariant of a semaphore:
/// 0 <= permits <= capacity; `waiters` and `waiter_sizes` have equal length
/// with every size in [1, capacity] and every ID >= 0 and unique; the
/// fairness trace is no longer than the number of grants and of blocks.
/// Complexity: O(queue length^2) (pairwise ID uniqueness).
pub fn sem_check_invariant(s: &Semaphore) -> Bool {
  if s.capacity < 0 { return false; }
  if s.permits < 0 { return false; }
  if s.permits > s.capacity { return false; }
  if s.waiters.len() != s.waiter_sizes.len() { return false; }
  if s.grant_order.len() > s.grants { return false; }
  if s.grant_order.len() > s.blocks { return false; }
  var i = 0;
  while i < s.waiters.len() {
    let id: Int = s.waiters[i];
    let sz: Int = s.waiter_sizes[i];
    if id < 0 { return false; }
    if sz < 1 { return false; }
    if sz > s.capacity { return false; }
    var j = i + 1;
    while j < s.waiters.len() {
      let other: Int = s.waiters[j];
      if other == id { return false; }
      j = j + 1;
    }
    i = i + 1;
  }
  return true;
}
