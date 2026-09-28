// XIOM -- xiom.lockfree: deterministic atomic-step models of lock-free structures
// Port task: replace the xiom.lockfree placeholder with a real, tested,
// pure-XIOM package (no FFI, no real threads, no clock).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Scope (full rules in SPEC.md): this module is a single-threaded,
// deterministic model of three concurrent algorithms. It never spawns a
// thread, never executes an atomic instruction, never reads a clock and
// never calls FFI. Instead, every concurrent operation is written as an
// explicit sequence of atomic steps -- read a shared snapshot, compute a
// candidate, run a compare-and-swap (CAS) step, retry on failure -- exactly
// the shape a real lock-free implementation has. In this deterministic
// model the CAS step always succeeds on the first attempt unless a test
// drives a raw CAS probe function with a stale expected value, so the
// failure path is exercised explicitly rather than by real contention. A
// real atomics or scheduler backend is out of scope (uses of xiom.sync are
// deliberately avoided).
//
// Algorithms:
//   * Treiber stack over a pre-sized node pool (parallel Vec[Int] fields).
//     The head word packs (tag, node index) as
//     head = tag * stride + (index + 1), stride = capacity + 1, so
//     head % stride == 0 encodes an empty stack and residues 1..capacity
//     encode nodes 0..capacity-1. Every successful head CAS increments the
//     tag by one, so a token naming node i after one push differs from a
//     token naming node i after a later push/pop cycle: that is the ABA tag
//     that makes a stale snapshot fail its CAS.
//   * Bounded MPMC ring queue. head and tail are monotonic operation
//     counters; the slot is counter % capacity, so the counters keep
//     growing past capacity while the ring wraps. head == tail modulo
//     capacity is ambiguous between full and empty, so an exact element
//     count disambiguates (equivalent to a phase bit per lap).
//   * Atomic counter with CAS-step emulation: counter_add spins on
//     counter_cas_step and fails outside [0, 2^62 - 1];
//     counter_add_saturating clamps to that range instead of failing.
//
// Error model: every fallible operation returns Result[Int, LockfreeError]
// where LockfreeError carries (code, value, extra); lockfree_error_message
// is the pinned catalog.
//
// Language notes (XIOM v0.62.0) that shaped this module:
//   * free functions only; module-level parallel Vec[Int] state, no
//     Vec[StructType], no struct out-parameters;
//   * every Vec[Int] element read is bound with a typed `let`;
//   * Ok/Err are constructed only inside the leaf helpers below;
//   * no bitwise operators: the head word is packed and unpacked with
//     multiplication, division and modulo, so no sign-bit tests are needed;
//   * no `&mut` out-parameters: results are returned.

module xiom.lockfree

use xiom.string;
use xiom.convert;
use xiom.convert.int;

// --------------------------------------------------
//  Constants
// --------------------------------------------------

// Stack geometry.
const _LF_STACK_DEF_CAP: Int = 16;
const _LF_STACK_MAX_CAP: Int = 4096;

// Queue geometry.
const _LF_QUEUE_DEF_CAP: Int = 16;
const _LF_QUEUE_MAX_CAP: Int = 65536;

// Counter range [0, 2^62 - 1]. The limit keeps every intermediate sum inside
// the Int (i64) range: |value| <= limit and |delta| <= limit imply
// |value + delta| <= 2^63 - 2.
const _LF_COUNTER_MIN: Int = 0;
const _LF_COUNTER_LIMIT: Int = 4611686018427387903;

// LockfreeError codes (pinned messages in lockfree_error_message).
const _LF_ERR_STACK_CAPACITY: Int = 1;
const _LF_ERR_STACK_EMPTY: Int = 2;
const _LF_ERR_STACK_POOL: Int = 3;
const _LF_ERR_QUEUE_CAPACITY: Int = 4;
const _LF_ERR_QUEUE_EMPTY: Int = 5;
const _LF_ERR_QUEUE_FULL: Int = 6;
const _LF_ERR_COUNTER_OVERFLOW: Int = 7;
const _LF_ERR_COUNTER_UNDERFLOW: Int = 8;

// "Not applicable" filler for unused LockfreeError fields.
const _LF_NONE: Int = -1;

// --------------------------------------------------
//  Types
// --------------------------------------------------

/// Typed error carried by every fallible lock-free model operation.
/// `code` identifies the failure (see lockfree_error_message); `value` is
/// the offending input value (-1 when the operation has none); `extra` is
/// the bound or current context (capacity, counter value; -1 when none).
pub type LockfreeError = {
  code: Int;
  value: Int;
  extra: Int;
}

// --------------------------------------------------
//  Result leaves (Ok/Err construction is confined here)
// --------------------------------------------------

// Ok(v) for Result[Int, LockfreeError].
fn _lf_ok(v: Int) -> Result[Int, LockfreeError] {
  return Ok(v);
}

// Err triple for Result[Int, LockfreeError].
fn _lf_err(code: Int, value: Int, extra: Int) -> Result[Int, LockfreeError] {
  let e = LockfreeError{ code: code; value: value; extra: extra; };
  return Err(e);
}

// --------------------------------------------------
//  Shared helpers
// --------------------------------------------------

// Decimal text for a possibly negative Int (int_to_base is exact across the
// full Int range, sign included).
fn _lf_dec(n: Int) -> Str {
  return int_to_base(n, 10);
}

// 1 when b, 0 otherwise (keeps dump lines numeric).
fn _lf_flag(b: Bool) -> Int {
  if b { return 1; }
  return 0;
}

// --------------------------------------------------
//  Treiber stack -- module state
// --------------------------------------------------

// Node pool: parallel vectors, one entry per node index 0..cap-1.
var _lf_st_ready: Bool = false;
var _lf_st_cap: Int = _LF_STACK_DEF_CAP;
var _lf_st_value: Vec[Int] = Vec[Int].new();
var _lf_st_next: Vec[Int] = Vec[Int].new();
var _lf_st_free: Vec[Int] = Vec[Int].new();

// Shared head word (the modeled atomic word).
var _lf_st_head: Int = 0;

var _lf_st_count: Int = 0;
var _lf_st_free_head: Int = _LF_NONE;
var _lf_st_cas_ok: Int = 0;
var _lf_st_cas_fail: Int = 0;
var _lf_st_pushes: Int = 0;
var _lf_st_pops: Int = 0;

// --------------------------------------------------
//  Treiber stack -- head-word packing
// --------------------------------------------------

// Stride between adjacent tags: capacity + 1 leaves residue 0 for "empty".
fn _lf_st_stride() -> Int {
  return _lf_st_cap + 1;
}

// Packed head token for (tag, idx); idx == -1 packs to tag * stride.
fn _lf_st_token(tag: Int, idx: Int) -> Int {
  return tag * _lf_st_stride() + (idx + 1);
}

// Node index of a head token, -1 when the token encodes an empty stack.
fn _lf_st_token_index(tok: Int) -> Int {
  return tok % _lf_st_stride() - 1;
}

// ABA tag of a head token: the number of successful head CAS steps since
// the last reset.
fn _lf_st_token_tag(tok: Int) -> Int {
  return tok / _lf_st_stride();
}

// --------------------------------------------------
//  Treiber stack -- setup
// --------------------------------------------------

// Reset and (re)build the node pool for a validated capacity. Every
// parallel vector receives exactly `cap` pushes in one mirrored loop, and
// the free list is chained 0 -> 1 -> ... -> cap-1 -> -1, so no later push
// reallocates.
// Complexity: O(capacity).
fn _lf_stack_setup(cap: Int) {
  _lf_st_cap = cap;
  _lf_st_value.clear();
  _lf_st_next.clear();
  _lf_st_free.clear();
  var i = 0;
  while i < cap {
    _lf_st_value.push(0);
    _lf_st_next.push(_LF_NONE);
    _lf_st_free.push(i + 1);
    i = i + 1;
  }
  _lf_st_free[cap - 1] = _LF_NONE;
  _lf_st_free_head = 0;
  _lf_st_head = 0;
  _lf_st_count = 0;
  _lf_st_cas_ok = 0;
  _lf_st_cas_fail = 0;
  _lf_st_pushes = 0;
  _lf_st_pops = 0;
  _lf_st_ready = true;
}

// Build the default-capacity pool when nothing was configured yet, so the
// public API works without an explicit stack_configure call.
fn _lf_stack_ensure() {
  if !_lf_st_ready {
    _lf_stack_setup(_LF_STACK_DEF_CAP);
  }
}

// --------------------------------------------------
//  Treiber stack -- public API
// --------------------------------------------------

/// Configure the stack node pool, resetting every node, the head word and
/// all counters (configure is a full reset, not a resize).
/// Params: capacity - number of stack nodes, 1..stack_max_capacity().
/// Returns: Ok(capacity). On Err code 1 (value = capacity, extra =
/// stack_max_capacity) the previous configuration is unchanged.
/// Complexity: O(capacity).
pub fn stack_configure(capacity: Int) -> Result[Int, LockfreeError] {
  if capacity < 1 {
    return _lf_err(_LF_ERR_STACK_CAPACITY, capacity, _LF_STACK_MAX_CAP);
  }
  if capacity > _LF_STACK_MAX_CAP {
    return _lf_err(_LF_ERR_STACK_CAPACITY, capacity, _LF_STACK_MAX_CAP);
  }
  _lf_stack_setup(capacity);
  return _lf_ok(capacity);
}

/// Largest node capacity stack_configure accepts: 4096.
/// Complexity: O(1).
pub fn stack_max_capacity() -> Int {
  return _LF_STACK_MAX_CAP;
}

/// Current node-pool capacity. Complexity: O(1).
pub fn stack_capacity() -> Int {
  _lf_stack_ensure();
  return _lf_st_cap;
}

/// Current node count. Complexity: O(1).
pub fn stack_count() -> Int {
  _lf_stack_ensure();
  return _lf_st_count;
}

/// Number of pool nodes currently free (capacity - count). Complexity: O(1).
pub fn stack_free_count() -> Int {
  _lf_stack_ensure();
  return _lf_st_cap - _lf_st_count;
}

/// Current packed head token; 0 encodes the fresh empty state. Complexity: O(1).
pub fn stack_head_token() -> Int {
  _lf_stack_ensure();
  return _lf_st_head;
}

/// Node index named by the current head token, -1 when empty. Complexity: O(1).
pub fn stack_head_index() -> Int {
  _lf_stack_ensure();
  return _lf_st_token_index(_lf_st_head);
}

/// ABA tag of the current head token: successful head CAS steps since the
/// last stack_configure. Complexity: O(1).
pub fn stack_head_tag() -> Int {
  _lf_stack_ensure();
  return _lf_st_token_tag(_lf_st_head);
}

/// Successful head CAS steps since the last stack_configure. Complexity: O(1).
pub fn stack_cas_successes() -> Int {
  _lf_stack_ensure();
  return _lf_st_cas_ok;
}

/// Failed head CAS steps since the last stack_configure (0 unless a raw
/// stack_cas_step probe ran with a stale expected token). Complexity: O(1).
pub fn stack_cas_failures() -> Int {
  _lf_stack_ensure();
  return _lf_st_cas_fail;
}

/// Successful stack_push calls since the last stack_configure. Complexity: O(1).
pub fn stack_push_count() -> Int {
  _lf_stack_ensure();
  return _lf_st_pushes;
}

/// Successful stack_pop calls since the last stack_configure. Complexity: O(1).
pub fn stack_pop_count() -> Int {
  _lf_stack_ensure();
  return _lf_st_pops;
}

/// One modeled atomic compare-and-swap step on the stack head word: when
/// the current head token equals `expected`, store `desired`, count a
/// success and return true; otherwise count a failure and return false.
/// This is the raw step the push/pop retry loops spin on, exposed so tests
/// can pin both outcomes. It does not maintain the node-pool invariants:
/// pass only tokens consistent with the current structure (the no-op
/// success stack_cas_step(stack_head_token(), stack_head_token()) is always
/// safe).
/// Complexity: O(1).
pub fn stack_cas_step(expected: Int, desired: Int) -> Bool {
  _lf_stack_ensure();
  if _lf_st_head == expected {
    _lf_st_head = desired;
    _lf_st_cas_ok = _lf_st_cas_ok + 1;
    return true;
  }
  _lf_st_cas_fail = _lf_st_cas_fail + 1;
  return false;
}

/// Modeled Treiber push (single-threaded execution of the concurrent
/// algorithm; see the module header). Sequence: take a free node, link it
/// to the head snapshot, then CAS the packed head to (tag + 1, new node).
/// On a failed CAS the loop re-reads the head and re-links (the
/// deterministic model succeeds on the first attempt).
/// Params: value - the payload.
/// Returns: Ok(token) - the packed head token after the push: tag one
/// greater than before, node index of the allocated node.
/// Error case: 3 pool exhausted, all capacity nodes already stacked
/// (value = value, extra = capacity).
/// Complexity: O(1).
pub fn stack_push(value: Int) -> Result[Int, LockfreeError] {
  _lf_stack_ensure();
  if _lf_st_free_head < 0 {
    return _lf_err(_LF_ERR_STACK_POOL, value, _lf_st_cap);
  }
  let idx: Int = _lf_st_free_head;
  let free_next: Int = _lf_st_free[idx];
  _lf_st_free_head = free_next;
  _lf_st_value[idx] = value;
  var token = 0;
  var done = false;
  while !done {
    let old: Int = _lf_st_head;
    let old_idx = _lf_st_token_index(old);
    _lf_st_next[idx] = old_idx;
    let tag = _lf_st_token_tag(old) + 1;
    let desired = _lf_st_token(tag, idx);
    if stack_cas_step(old, desired) {
      token = desired;
      done = true;
    }
  }
  _lf_st_count = _lf_st_count + 1;
  _lf_st_pushes = _lf_st_pushes + 1;
  return _lf_ok(token);
}

/// Modeled Treiber pop (single-threaded execution of the concurrent
/// algorithm; see the module header). Sequence: read the head snapshot,
/// read the successor from the top node, then CAS the packed head to
/// (tag + 1, successor). On success the value is returned and the node is
/// released to the free list for reuse.
/// Returns: Ok(value) - payload of the previous top node (LIFO).
/// Error case: 2 stack empty (value = -1, extra = capacity); a failed pop
/// changes nothing and is not counted in stack_pop_count().
/// Complexity: O(1).
pub fn stack_pop() -> Result[Int, LockfreeError] {
  _lf_stack_ensure();
  let first: Int = _lf_st_head;
  if _lf_st_token_index(first) < 0 {
    return _lf_err(_LF_ERR_STACK_EMPTY, _LF_NONE, _lf_st_cap);
  }
  var value = 0;
  var done = false;
  while !done {
    let old: Int = _lf_st_head;
    let idx = _lf_st_token_index(old);
    if idx < 0 {
      return _lf_err(_LF_ERR_STACK_EMPTY, _LF_NONE, _lf_st_cap);
    }
    let nx: Int = _lf_st_next[idx];
    let tag = _lf_st_token_tag(old) + 1;
    let desired = _lf_st_token(tag, nx);
    if stack_cas_step(old, desired) {
      let v: Int = _lf_st_value[idx];
      value = v;
      _lf_st_free[idx] = _lf_st_free_head;
      _lf_st_free_head = idx;
      _lf_st_count = _lf_st_count - 1;
      _lf_st_pops = _lf_st_pops + 1;
      done = true;
    }
  }
  return _lf_ok(value);
}

/// Value of the top node without popping.
/// Returns: Ok(value), or Err code 2 when empty (value = -1, extra =
/// capacity).
/// Complexity: O(1).
pub fn stack_peek() -> Result[Int, LockfreeError] {
  _lf_stack_ensure();
  let idx = _lf_st_token_index(_lf_st_head);
  if idx < 0 {
    return _lf_err(_LF_ERR_STACK_EMPTY, _LF_NONE, _lf_st_cap);
  }
  let v: Int = _lf_st_value[idx];
  return _lf_ok(v);
}

/// One-line state dump for tests. Format:
/// stack[cap=.. count=.. head_idx=.. head_tag=.. free=.. top=a,b cas_ok=.. cas_fail=..]
/// with `top` the stack contents from top to bottom (empty prints nothing
/// after `top=`).
/// Complexity: O(count).
pub fn stack_dump() -> Str {
  _lf_stack_ensure();
  var out = "stack[cap=" + _lf_dec(_lf_st_cap);
  out = out + " count=" + _lf_dec(_lf_st_count);
  out = out + " head_idx=" + _lf_dec(_lf_st_token_index(_lf_st_head));
  out = out + " head_tag=" + _lf_dec(_lf_st_token_tag(_lf_st_head));
  out = out + " free=" + _lf_dec(_lf_st_cap - _lf_st_count);
  out = out + " top=";
  var idx = _lf_st_token_index(_lf_st_head);
  var n = 0;
  while idx >= 0 && n < _lf_st_count {
    let v: Int = _lf_st_value[idx];
    if n > 0 { out = out + ","; }
    out = out + _lf_dec(v);
    let nx: Int = _lf_st_next[idx];
    idx = nx;
    n = n + 1;
  }
  out = out + " cas_ok=" + _lf_dec(_lf_st_cas_ok);
  out = out + " cas_fail=" + _lf_dec(_lf_st_cas_fail) + "]";
  return out;
}

// --------------------------------------------------
//  Bounded MPMC ring queue -- module state
// --------------------------------------------------

// Ring slots (pre-sized to capacity) and the monotonic operation counters.
var _lf_rq_ready: Bool = false;
var _lf_rq_cap: Int = _LF_QUEUE_DEF_CAP;
var _lf_rq_data: Vec[Int] = Vec[Int].new();
var _lf_rq_head: Int = 0;
var _lf_rq_tail: Int = 0;

// Exact element count: the full/empty disambiguator.
var _lf_rq_count: Int = 0;
var _lf_rq_cas_ok: Int = 0;
var _lf_rq_cas_fail: Int = 0;
var _lf_rq_enqueues: Int = 0;
var _lf_rq_dequeues: Int = 0;

// --------------------------------------------------
//  Bounded MPMC ring queue -- setup
// --------------------------------------------------

// Reset and (re)build the ring for a validated capacity: `cap` data slots
// pre-filled so no later enqueue reallocates, counters and statistics
// zeroed.
// Complexity: O(capacity).
fn _lf_queue_setup(cap: Int) {
  _lf_rq_cap = cap;
  _lf_rq_data.clear();
  var i = 0;
  while i < cap {
    _lf_rq_data.push(0);
    i = i + 1;
  }
  _lf_rq_head = 0;
  _lf_rq_tail = 0;
  _lf_rq_count = 0;
  _lf_rq_cas_ok = 0;
  _lf_rq_cas_fail = 0;
  _lf_rq_enqueues = 0;
  _lf_rq_dequeues = 0;
  _lf_rq_ready = true;
}

// Build the default-capacity ring when nothing was configured yet, so the
// public API works without an explicit queue_configure call.
fn _lf_queue_ensure() {
  if !_lf_rq_ready {
    _lf_queue_setup(_LF_QUEUE_DEF_CAP);
  }
}

// --------------------------------------------------
//  Bounded MPMC ring queue -- public API
// --------------------------------------------------

/// Configure the ring, resetting every slot, both counters and all
/// statistics (configure is a full reset).
/// Params: capacity - number of queue slots, 1..queue_max_capacity().
/// Returns: Ok(capacity). On Err code 4 (value = capacity, extra =
/// queue_max_capacity) the previous configuration is unchanged.
/// Complexity: O(capacity).
pub fn queue_configure(capacity: Int) -> Result[Int, LockfreeError] {
  if capacity < 1 {
    return _lf_err(_LF_ERR_QUEUE_CAPACITY, capacity, _LF_QUEUE_MAX_CAP);
  }
  if capacity > _LF_QUEUE_MAX_CAP {
    return _lf_err(_LF_ERR_QUEUE_CAPACITY, capacity, _LF_QUEUE_MAX_CAP);
  }
  _lf_queue_setup(capacity);
  return _lf_ok(capacity);
}

/// Largest ring capacity queue_configure accepts: 65536.
/// Complexity: O(1).
pub fn queue_max_capacity() -> Int {
  return _LF_QUEUE_MAX_CAP;
}

/// Current ring capacity. Complexity: O(1).
pub fn queue_capacity() -> Int {
  _lf_queue_ensure();
  return _lf_rq_cap;
}

/// Current element count; 0 means empty. Complexity: O(1).
pub fn queue_count() -> Int {
  _lf_queue_ensure();
  return _lf_rq_count;
}

/// Monotonic dequeue counter: total successful dequeue CAS steps since the
/// last queue_configure; the next dequeue reads slot head % capacity.
/// Complexity: O(1).
pub fn queue_head_counter() -> Int {
  _lf_queue_ensure();
  return _lf_rq_head;
}

/// Monotonic enqueue counter: total successful enqueue CAS steps since the
/// last queue_configure; the next enqueue writes slot tail % capacity.
/// Complexity: O(1).
pub fn queue_tail_counter() -> Int {
  _lf_queue_ensure();
  return _lf_rq_tail;
}

/// True when no elements are queued (count == 0). Complexity: O(1).
pub fn queue_is_empty() -> Bool {
  _lf_queue_ensure();
  return _lf_rq_count <= 0;
}

/// True when the ring is full (count == capacity). Complexity: O(1).
pub fn queue_is_full() -> Bool {
  _lf_queue_ensure();
  return _lf_rq_count >= _lf_rq_cap;
}

/// Successful queue CAS steps (tail and head combined) since the last
/// queue_configure. Complexity: O(1).
pub fn queue_cas_successes() -> Int {
  _lf_queue_ensure();
  return _lf_rq_cas_ok;
}

/// Failed queue CAS steps since the last queue_configure (0 unless a raw
/// queue_cas_tail_step / queue_cas_head_step probe ran with a stale
/// expected counter). Complexity: O(1).
pub fn queue_cas_failures() -> Int {
  _lf_queue_ensure();
  return _lf_rq_cas_fail;
}

/// Successful queue_enqueue calls since the last queue_configure. Complexity: O(1).
pub fn queue_enqueue_count() -> Int {
  _lf_queue_ensure();
  return _lf_rq_enqueues;
}

/// Successful queue_dequeue calls since the last queue_configure. Complexity: O(1).
pub fn queue_dequeue_count() -> Int {
  _lf_queue_ensure();
  return _lf_rq_dequeues;
}

/// One modeled atomic CAS step on the queue tail counter (enqueue side):
/// when the current tail equals `expected`, store `desired`, count a
/// success and return true; otherwise count a failure and return false.
/// Raw step; see stack_cas_step for the usage contract.
/// Complexity: O(1).
pub fn queue_cas_tail_step(expected: Int, desired: Int) -> Bool {
  _lf_queue_ensure();
  if _lf_rq_tail == expected {
    _lf_rq_tail = desired;
    _lf_rq_cas_ok = _lf_rq_cas_ok + 1;
    return true;
  }
  _lf_rq_cas_fail = _lf_rq_cas_fail + 1;
  return false;
}

/// One modeled atomic CAS step on the queue head counter (dequeue side);
/// same contract as queue_cas_tail_step.
/// Complexity: O(1).
pub fn queue_cas_head_step(expected: Int, desired: Int) -> Bool {
  _lf_queue_ensure();
  if _lf_rq_head == expected {
    _lf_rq_head = desired;
    _lf_rq_cas_ok = _lf_rq_cas_ok + 1;
    return true;
  }
  _lf_rq_cas_fail = _lf_rq_cas_fail + 1;
  return false;
}

/// Modeled MPMC enqueue (single-threaded execution of the concurrent
/// algorithm; see the module header). Sequence: read the tail snapshot,
/// write the payload into slot tail % capacity, then CAS the tail counter
/// to tail + 1; on success the count is bumped in the same modeled atomic
/// step, so the ring is never observed full-but-empty. A full ring is
/// rejected before the write; on a failed CAS the loop re-reads the tail
/// and rewrites the slot (the deterministic model succeeds on the first
/// attempt).
/// Params: value - the payload.
/// Returns: Ok(slot) - the ring slot index that received the value.
/// Error case: 6 ring full, count == capacity (value = value, extra =
/// capacity).
/// Complexity: O(1).
pub fn queue_enqueue(value: Int) -> Result[Int, LockfreeError] {
  _lf_queue_ensure();
  if _lf_rq_count >= _lf_rq_cap {
    return _lf_err(_LF_ERR_QUEUE_FULL, value, _lf_rq_cap);
  }
  var slot = 0;
  var done = false;
  while !done {
    let old: Int = _lf_rq_tail;
    let s = old % _lf_rq_cap;
    _lf_rq_data[s] = value;
    if queue_cas_tail_step(old, old + 1) {
      slot = s;
      done = true;
    }
  }
  _lf_rq_count = _lf_rq_count + 1;
  _lf_rq_enqueues = _lf_rq_enqueues + 1;
  return _lf_ok(slot);
}

/// Modeled MPMC dequeue (single-threaded execution of the concurrent
/// algorithm; see the module header). Sequence: read the head snapshot,
/// read slot head % capacity, then CAS the head counter to head + 1; on
/// success the count is dropped in the same modeled atomic step. An empty
/// ring is rejected before the read; on a failed CAS the loop re-reads the
/// head (the deterministic model succeeds on the first attempt).
/// Returns: Ok(value) - the oldest queued element (FIFO).
/// Error case: 5 ring empty, count == 0 (value = -1, extra = capacity); a
/// failed dequeue changes nothing and is not counted in
/// queue_dequeue_count().
/// Complexity: O(1).
pub fn queue_dequeue() -> Result[Int, LockfreeError] {
  _lf_queue_ensure();
  if _lf_rq_count <= 0 {
    return _lf_err(_LF_ERR_QUEUE_EMPTY, _LF_NONE, _lf_rq_cap);
  }
  var value = 0;
  var done = false;
  while !done {
    let old: Int = _lf_rq_head;
    let s = old % _lf_rq_cap;
    let v: Int = _lf_rq_data[s];
    if queue_cas_head_step(old, old + 1) {
      value = v;
      done = true;
    }
  }
  _lf_rq_count = _lf_rq_count - 1;
  _lf_rq_dequeues = _lf_rq_dequeues + 1;
  return _lf_ok(value);
}

/// One-line state dump for tests. Format:
/// queue[cap=.. count=.. head=.. tail=.. full=0/1 empty=0/1 slots=a,b,.. cas_ok=.. cas_fail=..]
/// with `slots` the raw ring contents in index order.
/// Complexity: O(capacity).
pub fn queue_dump() -> Str {
  _lf_queue_ensure();
  var out = "queue[cap=" + _lf_dec(_lf_rq_cap);
  out = out + " count=" + _lf_dec(_lf_rq_count);
  out = out + " head=" + _lf_dec(_lf_rq_head);
  out = out + " tail=" + _lf_dec(_lf_rq_tail);
  out = out + " full=" + _lf_dec(_lf_flag(_lf_rq_count >= _lf_rq_cap));
  out = out + " empty=" + _lf_dec(_lf_flag(_lf_rq_count <= 0));
  out = out + " slots=";
  var i = 0;
  while i < _lf_rq_cap {
    let v: Int = _lf_rq_data[i];
    if i > 0 { out = out + ","; }
    out = out + _lf_dec(v);
    i = i + 1;
  }
  out = out + " cas_ok=" + _lf_dec(_lf_rq_cas_ok);
  out = out + " cas_fail=" + _lf_dec(_lf_rq_cas_fail) + "]";
  return out;
}

// --------------------------------------------------
//  Atomic counter -- module state
// --------------------------------------------------

// The modeled atomic word.
var _lf_ct_value: Int = 0;
var _lf_ct_cas_ok: Int = 0;
var _lf_ct_cas_fail: Int = 0;
var _lf_ct_adds: Int = 0;
var _lf_ct_saturating_adds: Int = 0;

// --------------------------------------------------
//  Atomic counter -- public API
// --------------------------------------------------

/// Reset the counter to `v` and clear its CAS statistics.
/// Params: v - the initial value; the model invariant is
/// counter_min() <= v <= counter_max() (raw setup helper, not validated).
/// Complexity: O(1).
pub fn counter_reset(v: Int) {
  _lf_ct_value = v;
  _lf_ct_cas_ok = 0;
  _lf_ct_cas_fail = 0;
  _lf_ct_adds = 0;
  _lf_ct_saturating_adds = 0;
}

/// Current counter value. Complexity: O(1).
pub fn counter_get() -> Int {
  return _lf_ct_value;
}

/// Lower bound of the counter range: 0. Complexity: O(1).
pub fn counter_min() -> Int {
  return _LF_COUNTER_MIN;
}

/// Upper bound of the counter range: 2^62 - 1 = 4611686018427387903.
/// Complexity: O(1).
pub fn counter_max() -> Int {
  return _LF_COUNTER_LIMIT;
}

/// Successful counter CAS steps since the last counter_reset. Complexity: O(1).
pub fn counter_cas_successes() -> Int {
  return _lf_ct_cas_ok;
}

/// Failed counter CAS steps since the last counter_reset. Complexity: O(1).
pub fn counter_cas_failures() -> Int {
  return _lf_ct_cas_fail;
}

/// Successful counter_add calls since the last counter_reset. Complexity: O(1).
pub fn counter_add_count() -> Int {
  return _lf_ct_adds;
}

/// counter_add_saturating calls since the last counter_reset. Complexity: O(1).
pub fn counter_saturating_add_count() -> Int {
  return _lf_ct_saturating_adds;
}

/// One modeled atomic compare-and-swap step on the counter word: when the
/// current value equals `expected`, store `desired`, count a success and
/// return true; otherwise count a failure and return false. Raw step; see
/// stack_cas_step for the usage contract (the model invariant
/// counter_min() <= desired <= counter_max() is not enforced here).
/// Complexity: O(1).
pub fn counter_cas_step(expected: Int, desired: Int) -> Bool {
  if _lf_ct_value == expected {
    _lf_ct_value = desired;
    _lf_ct_cas_ok = _lf_ct_cas_ok + 1;
    return true;
  }
  _lf_ct_cas_fail = _lf_ct_cas_fail + 1;
  return false;
}

/// Modeled atomic fetch-and-add: spin on counter_cas_step replacing the
/// current value `cur` with `cur + delta` until a step succeeds.
/// Params: delta - the addend, |delta| <= counter_max().
/// Returns: Ok(new value) after the add.
/// Error case: 7 result would exceed counter_max() (value = delta, extra =
/// value before the call); 8 result would drop below counter_min() (same
/// fields); the counter is unchanged on Err and the call is not counted.
/// Complexity: O(1) steps in the deterministic model (one CAS attempt).
pub fn counter_add(delta: Int) -> Result[Int, LockfreeError] {
  if delta > _LF_COUNTER_LIMIT {
    return _lf_err(_LF_ERR_COUNTER_OVERFLOW, delta, _lf_ct_value);
  }
  if delta < 0 - _LF_COUNTER_LIMIT {
    return _lf_err(_LF_ERR_COUNTER_UNDERFLOW, delta, _lf_ct_value);
  }
  var result = 0;
  var failed_code = 0;
  var done = false;
  while !done {
    let cur: Int = _lf_ct_value;
    let candidate = cur + delta;
    if candidate > _LF_COUNTER_LIMIT {
      failed_code = _LF_ERR_COUNTER_OVERFLOW;
      done = true;
    } else {
      if candidate < _LF_COUNTER_MIN {
        failed_code = _LF_ERR_COUNTER_UNDERFLOW;
        done = true;
      } else {
        if counter_cas_step(cur, candidate) {
          result = candidate;
          done = true;
        }
      }
    }
  }
  if failed_code != 0 {
    return _lf_err(failed_code, delta, _lf_ct_value);
  }
  _lf_ct_adds = _lf_ct_adds + 1;
  return _lf_ok(result);
}

/// Modeled atomic saturating fetch-and-add: spin on counter_cas_step
/// replacing the current value with clamp(cur + delta, counter_min(),
/// counter_max()); it never returns Err. `delta` is clamped before the
/// addition so no intermediate overflows.
/// Params: delta - the addend, any Int.
/// Returns: the new value, clamped to [counter_min(), counter_max()].
/// Complexity: O(1) steps in the deterministic model (one CAS attempt).
pub fn counter_add_saturating(delta: Int) -> Int {
  var result = 0;
  var done = false;
  while !done {
    let cur: Int = _lf_ct_value;
    var candidate = _LF_COUNTER_LIMIT;
    if delta > _LF_COUNTER_LIMIT {
      candidate = _LF_COUNTER_LIMIT;
    } else {
      if delta < 0 - _LF_COUNTER_LIMIT {
        candidate = _LF_COUNTER_MIN;
      } else {
        candidate = cur + delta;
        if candidate > _LF_COUNTER_LIMIT {
          candidate = _LF_COUNTER_LIMIT;
        }
        if candidate < _LF_COUNTER_MIN {
          candidate = _LF_COUNTER_MIN;
        }
      }
    }
    if counter_cas_step(cur, candidate) {
      result = candidate;
      done = true;
    }
  }
  _lf_ct_saturating_adds = _lf_ct_saturating_adds + 1;
  return result;
}

/// One-line state dump for tests. Format:
/// counter[value=.. min=.. max=.. cas_ok=.. cas_fail=.. adds=.. sat_adds=..]
/// Complexity: O(1).
pub fn counter_dump() -> Str {
  var out = "counter[value=" + _lf_dec(_lf_ct_value);
  out = out + " min=" + _lf_dec(_LF_COUNTER_MIN);
  out = out + " max=" + _lf_dec(_LF_COUNTER_LIMIT);
  out = out + " cas_ok=" + _lf_dec(_lf_ct_cas_ok);
  out = out + " cas_fail=" + _lf_dec(_lf_ct_cas_fail);
  out = out + " adds=" + _lf_dec(_lf_ct_adds);
  out = out + " sat_adds=" + _lf_dec(_lf_ct_saturating_adds) + "]";
  return out;
}

// --------------------------------------------------
//  Combined dump and error catalog
// --------------------------------------------------

/// Combined multi-line state dump for tests: stack_dump(), queue_dump() and
/// counter_dump() joined with newline separators. Complexity: O(capacity).
pub fn lockfree_dump() -> Str {
  return stack_dump() + "\n" + queue_dump() + "\n" + counter_dump();
}

/// Pinned message for a LockfreeError code; "lockfree: unknown error" for
/// codes outside the catalog. Complexity: O(1).
pub fn lockfree_error_message(code: Int) -> Str {
  if code == _LF_ERR_STACK_CAPACITY {
    return "lockfree: stack capacity out of range";
  }
  if code == _LF_ERR_STACK_EMPTY {
    return "lockfree: stack is empty";
  }
  if code == _LF_ERR_STACK_POOL {
    return "lockfree: stack node pool exhausted";
  }
  if code == _LF_ERR_QUEUE_CAPACITY {
    return "lockfree: queue capacity out of range";
  }
  if code == _LF_ERR_QUEUE_EMPTY {
    return "lockfree: queue is empty";
  }
  if code == _LF_ERR_QUEUE_FULL {
    return "lockfree: queue is full";
  }
  if code == _LF_ERR_COUNTER_OVERFLOW {
    return "lockfree: counter overflow";
  }
  if code == _LF_ERR_COUNTER_UNDERFLOW {
    return "lockfree: counter underflow";
  }
  return "lockfree: unknown error";
}
