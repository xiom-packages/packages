// XIOM -- xiom.cancel: cooperative cancellation tokens as a deterministic tree
// Port task: replace the xiom.cancel placeholder with a real, tested, pure-XIOM
// package (no FFI, no threads, no wall clock).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model: cancellation tokens and propagation primitives as a pure,
// deterministic state machine. The library owns the *semantics* a runtime
// (thread pool, async executor, request pipeline) would drive; it contains no
// threads, no atomics, no locks, no wall clock and no I/O. Time is a logical
// integer clock advanced explicitly by the caller.
//
// A Canceller holds a forest of tokens stored as parallel Vec[Int] fields:
//   * token_ids[i]   the caller-assigned token id (unique, >= 0)
//   * parents[i]      parent token id, or -1 for a root; a parent always
//                    precedes its child in the vectors (forest, no cycles)
//   * states[i]       CANCEL_STATE_ACTIVE or CANCEL_STATE_CANCELLED
//   * reasons[i]      CANCEL_REASON_* code: why THIS token is cancelled
//   * sources[i]      the token that initiated the cancellation: the token
//                    itself for a direct or deadline cancel, the originating
//                    ancestor for a propagated (PARENT) cancel
//   * cancel_ticks[i] the logical clock value at the cancellation
//   * deadlines[i]    absolute logical tick, or -1 when none
//
// Cancellation semantics (all deterministic, all total):
//   * canceller_cancel(id, reason) cancels one ACTIVE token and, transitively,
//     every ACTIVE descendant. Descendants receive reason CANCEL_REASON_PARENT
//     and source = the initiating token. Already-cancelled descendants are
//     left untouched (their own reason/source/tick are never overwritten).
//   * cancellation is a one-way ACTIVE -> CANCELLED transition; a repeat
//     cancel is refused by canceller_cancel ("already cancelled") and is a
//     no-op returning Ok(0) by canceller_cancel_idempotent.
//   * a child added under an already-cancelled parent is born CANCELLED with
//     reason PARENT and the parent's origin source, so the propagation
//     closure (parent cancelled => child cancelled) always holds.
//   * deadlines are absolute logical ticks: a token is due when
//     now >= deadline. canceller_check_deadline checks one token,
//     canceller_sweep checks every token in creation order, and
//     canceller_tick = advance the clock + sweep. A due token is cancelled
//     with reason CANCEL_REASON_DEADLINE and propagates like any other
//     cancel.
//   * aggregation classifies a caller-supplied id list: NONE / SOME / ALL /
//     EMPTY / UNKNOWN.
//
// Language notes (XIOM v0.62.1): free functions only; Ok/Err are constructed
// only inside the _ok_int/_err_int leaf helpers; Vec[Int] element reads are
// bound with a typed `let`; the parallel Vec fields are pushed and rewritten
// together so they can never skew; no Vec[StructType], no indexed Vec[fn]
// dispatch, no generic callbacks, no Vec[Float64], no `mut` in match patterns,
// no FFI, no threads, no `log`-named function. Str values are compared only
// with string.str_compare.

module xiom.cancel

// ---------------------------------------------------------------------------
// Public constants
// ---------------------------------------------------------------------------

/// Token state: accepting cancellation (cancellable).
pub const CANCEL_STATE_ACTIVE: Int = 0;

/// Token state: cancelled (terminal; never leaves this state).
pub const CANCEL_STATE_CANCELLED: Int = 1;

/// Reason code of an active token (reserved: canceller_cancel rejects it).
pub const CANCEL_REASON_NONE: Int = 0;

/// Well-known reason: an explicit caller request.
pub const CANCEL_REASON_USER: Int = 1;

/// Well-known reason: a logical-tick deadline expired. Reserved: only the
/// deadline check functions may set it.
pub const CANCEL_REASON_DEADLINE: Int = 2;

/// Well-known reason: an ancestor was cancelled. Reserved: only propagation
/// sets it.
pub const CANCEL_REASON_PARENT: Int = 3;

/// Well-known reason: the owning resource is shutting down.
pub const CANCEL_REASON_SHUTDOWN: Int = 4;

/// Aggregation code: no listed token is cancelled.
pub const CANCEL_AGG_NONE: Int = 0;

/// Aggregation code: some, but not all, listed tokens are cancelled.
pub const CANCEL_AGG_SOME: Int = 1;

/// Aggregation code: every listed token is cancelled.
pub const CANCEL_AGG_ALL: Int = 2;

/// Aggregation code: the id list is empty.
pub const CANCEL_AGG_EMPTY: Int = 3;

/// Aggregation code: at least one listed id is unknown (takes precedence).
pub const CANCEL_AGG_UNKNOWN: Int = 4;

/// Sentinel: token has no parent (a root).
pub const CANCEL_NO_PARENT: Int = -1;

/// Sentinel: token has no deadline.
pub const CANCEL_NO_DEADLINE: Int = -1;

/// Sentinel: unknown token id / out-of-range accessor result.
pub const CANCEL_NOT_FOUND: Int = -1;

/// Cancellation registry. Every field is an internal implementation detail;
/// callers must go through the canceller_* free functions. The seven token
/// vectors are parallel and always share one length:
/// token_ids[i], parents[i], states[i], reasons[i], sources[i],
/// cancel_ticks[i], deadlines[i]. `now` is the logical clock (monotonic,
/// starts at 0). Counters: `direct_cancels` (successful explicit cancels of
/// the target token), `deadline_cancels` (tokens cancelled by a due
/// deadline), `propagated_cancels` (descendants cancelled by propagation).
pub type Canceller = {
  token_ids: Vec[Int];
  parents: Vec[Int];
  states: Vec[Int];
  reasons: Vec[Int];
  sources: Vec[Int];
  cancel_ticks: Vec[Int];
  deadlines: Vec[Int];
  now: Int;
  direct_cancels: Int;
  deadline_cancels: Int;
  propagated_cancels: Int;
}

// ---------------------------------------------------------------------------
// Result constructors (leaf helpers only; see the header comment)
// ---------------------------------------------------------------------------

fn _ok_int(v: Int) -> Result[Int, Str] { return Ok(v); }
fn _err_int(m: Str) -> Result[Int, Str] { return Err(m); }

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

// Slot of token `id` in the token vectors, or -1 when unknown.
fn _index(c: &Canceller, id: Int) -> Int {
  var i = 0;
  while i < c.token_ids.len() {
    let cur: Int = c.token_ids[i];
    if cur == id { return i; }
    i = i + 1;
  }
  return -1;
}

// True when `anc_slot` (an ancestor slot) is a proper ancestor of `slot`
// (walk the parent chain; parents store ids, so resolve the ancestor id).
fn _is_descendant(c: &Canceller, slot: Int, anc_slot: Int) -> Bool {
  let anc_id: Int = c.token_ids[anc_slot];
  var cur = slot;
  var alive = true;
  while alive {
    let p: Int = c.parents[cur];
    if p < 0 {
      alive = false;
    } else {
      if p == anc_id { return true; }
      cur = _index(c, p);
    }
  }
  return false;
}

// True for the two reason codes the library reserves for itself.
fn _reason_reserved(reason: Int) -> Bool {
  if reason == CANCEL_REASON_DEADLINE { return true; }
  if reason == CANCEL_REASON_PARENT { return true; }
  return false;
}

// Cancel an ACTIVE token (`slot`) with `reason`, then cancel every ACTIVE
// descendant with reason PARENT and source `source_id` (the origin token).
// Returns the number of newly cancelled tokens (the target plus descendants)
// and adds the descendants to the propagated counter. The caller validates
// the reason and the ACTIVE state, and increments direct/deadline counters.
fn _apply_cancel(c: &mut Canceller, slot: Int, reason: Int, source_id: Int) -> Int {
  c.states[slot] = CANCEL_STATE_CANCELLED;
  c.reasons[slot] = reason;
  c.sources[slot] = source_id;
  c.cancel_ticks[slot] = c.now;
  var n = 1;
  var j = 0;
  while j < c.token_ids.len() {
    let st: Int = c.states[j];
    if st == CANCEL_STATE_ACTIVE {
      if _is_descendant(c, j, slot) {
        c.states[j] = CANCEL_STATE_CANCELLED;
        c.reasons[j] = CANCEL_REASON_PARENT;
        c.sources[j] = source_id;
        c.cancel_ticks[j] = c.now;
        n = n + 1;
      }
    }
    j = j + 1;
  }
  c.propagated_cancels = c.propagated_cancels + (n - 1);
  return n;
}

// ---------------------------------------------------------------------------
// Construction and the token tree
// ---------------------------------------------------------------------------

/// Create an empty cancellation registry: no tokens, clock at 0, all
/// counters zero. Complexity: O(1).
pub fn canceller_new() -> Canceller {
  return Canceller{
    token_ids: Vec[Int].new();
    parents: Vec[Int].new();
    states: Vec[Int].new();
    reasons: Vec[Int].new();
    sources: Vec[Int].new();
    cancel_ticks: Vec[Int].new();
    deadlines: Vec[Int].new();
    now: 0;
    direct_cancels: 0;
    deadline_cancels: 0;
    propagated_cancels: 0;
  };
}

/// Add a root token (no parent) in the ACTIVE state.
/// Params: c - the registry; id - caller-assigned token id, unique, >= 0.
/// Returns: Ok(id); Err("cancel: token id must be >= 0") or
/// Err("cancel: duplicate token id") -- in every Err case the state is
/// unchanged.
/// Complexity: O(token count).
pub fn canceller_add_root(c: &mut Canceller, id: Int) -> Result[Int, Str] {
  if id < 0 {
    return _err_int("cancel: token id must be >= 0");
  }
  if _index(c, id) >= 0 {
    return _err_int("cancel: duplicate token id");
  }
  c.token_ids.push(id);
  c.parents.push(CANCEL_NO_PARENT);
  c.states.push(CANCEL_STATE_ACTIVE);
  c.reasons.push(CANCEL_REASON_NONE);
  c.sources.push(CANCEL_NOT_FOUND);
  c.cancel_ticks.push(CANCEL_NOT_FOUND);
  c.deadlines.push(CANCEL_NO_DEADLINE);
  return _ok_int(id);
}

/// Add a child token under an existing parent, in the ACTIVE state. When the
/// parent is already CANCELLED the child is born CANCELLED with reason PARENT
/// and the parent's origin source (the propagation closure is preserved).
/// Params: c - the registry; parent - id of an existing token; id - the new
///         token id, unique, >= 0.
/// Returns: Ok(id); Err("cancel: token id must be >= 0"),
/// Err("cancel: duplicate token id") or Err("cancel: unknown parent token
/// id") -- in every Err case the state is unchanged. A born-cancelled child
/// increments the propagated counter.
/// Complexity: O(token count).
pub fn canceller_add_child(c: &mut Canceller, parent: Int, id: Int) -> Result[Int, Str] {
  if id < 0 {
    return _err_int("cancel: token id must be >= 0");
  }
  if _index(c, id) >= 0 {
    return _err_int("cancel: duplicate token id");
  }
  let pslot = _index(c, parent);
  if pslot < 0 {
    return _err_int("cancel: unknown parent token id");
  }
  let pstate: Int = c.states[pslot];
  let psource: Int = c.sources[pslot];
  c.token_ids.push(id);
  c.parents.push(parent);
  c.deadlines.push(CANCEL_NO_DEADLINE);
  if pstate == CANCEL_STATE_CANCELLED {
    c.states.push(CANCEL_STATE_CANCELLED);
    c.reasons.push(CANCEL_REASON_PARENT);
    c.sources.push(psource);
    c.cancel_ticks.push(c.now);
    c.propagated_cancels = c.propagated_cancels + 1;
  } else {
    c.states.push(CANCEL_STATE_ACTIVE);
    c.reasons.push(CANCEL_REASON_NONE);
    c.sources.push(CANCEL_NOT_FOUND);
    c.cancel_ticks.push(CANCEL_NOT_FOUND);
  }
  return _ok_int(id);
}

/// True when a token with `id` exists. Complexity: O(token count).
pub fn canceller_has_token(c: &Canceller, id: Int) -> Bool {
  return _index(c, id) >= 0;
}

/// Number of tokens in the registry (tokens are never removed).
/// Complexity: O(1).
pub fn canceller_token_count(c: &Canceller) -> Int {
  return c.token_ids.len();
}

/// Parent id of token `id`, or CANCEL_NO_PARENT (-1) for a root or an unknown
/// id (use canceller_has_token to distinguish). Complexity: O(token count).
pub fn canceller_parent(c: &Canceller, id: Int) -> Int {
  let slot = _index(c, id);
  if slot < 0 { return CANCEL_NO_PARENT; }
  let p: Int = c.parents[slot];
  return p;
}

/// Direct children of token `id`, in creation order; empty for an unknown id.
/// Complexity: O(token count).
pub fn canceller_children(c: &Canceller, id: Int) -> Vec[Int] {
  var out = Vec[Int].new();
  let slot = _index(c, id);
  if slot < 0 { return out; }
  var i = 0;
  while i < c.token_ids.len() {
    let p: Int = c.parents[i];
    if p == id {
      let cid: Int = c.token_ids[i];
      out.push(cid);
    }
    i = i + 1;
  }
  return out;
}

/// Number of direct children of token `id` (0 for an unknown id).
/// Complexity: O(token count).
pub fn canceller_child_count(c: &Canceller, id: Int) -> Int {
  var n = 0;
  let slot = _index(c, id);
  if slot < 0 { return 0; }
  var i = 0;
  while i < c.token_ids.len() {
    let p: Int = c.parents[i];
    if p == id { n = n + 1; }
    i = i + 1;
  }
  return n;
}

/// Depth of token `id`: 0 for a root, 1 for its children, and so on; -1 for
/// an unknown id. Complexity: O(depth).
pub fn canceller_depth(c: &Canceller, id: Int) -> Int {
  let slot = _index(c, id);
  if slot < 0 { return CANCEL_NOT_FOUND; }
  var depth = 0;
  var cur = slot;
  var alive = true;
  while alive {
    let p: Int = c.parents[cur];
    if p < 0 {
      alive = false;
    } else {
      depth = depth + 1;
      cur = _index(c, p);
    }
  }
  return depth;
}

/// Root (topmost ancestor) of token `id`, or CANCEL_NOT_FOUND (-1) when
/// unknown. Complexity: O(depth).
pub fn canceller_root_of(c: &Canceller, id: Int) -> Int {
  let slot = _index(c, id);
  if slot < 0 { return CANCEL_NOT_FOUND; }
  var cur = slot;
  var alive = true;
  while alive {
    let p: Int = c.parents[cur];
    if p < 0 {
      alive = false;
    } else {
      cur = _index(c, p);
    }
  }
  let rid: Int = c.token_ids[cur];
  return rid;
}

/// True when token `ancestor` is a proper ancestor of token `id` (strict:
/// false when they are equal or either id is unknown). Complexity: O(depth).
pub fn canceller_is_ancestor(c: &Canceller, ancestor: Int, id: Int) -> Bool {
  let a = _index(c, ancestor);
  if a < 0 { return false; }
  let d = _index(c, id);
  if d < 0 { return false; }
  return _is_descendant(c, d, a);
}

// ---------------------------------------------------------------------------
// Cancellation
// ---------------------------------------------------------------------------

/// Cancel one ACTIVE token and, transitively, every ACTIVE descendant.
/// Validation order: unknown id -> Err("cancel: unknown token id");
/// `reason < 1` -> Err("cancel: reason must be >= 1"); `reason` equal to
/// CANCEL_REASON_DEADLINE or CANCEL_REASON_PARENT -> Err("cancel: reason code
/// is reserved"); token already CANCELLED -> Err("cancel: already cancelled").
/// On success the target is CANCELLED with `reason`, `source` = its own id and
/// `cancel_tick` = the current logical clock; every ACTIVE descendant is
/// CANCELLED with reason PARENT and `source` = the target id. Descendants
/// already cancelled (for example by their own deadline) keep their original
/// reason/source/tick. The direct counter grows by one, the propagated
/// counter by the number of descendants cancelled by this call.
/// Params: c - the registry; id - the token to cancel; reason - the reason
///         code (>= 1, not 2/3; use CANCEL_REASON_USER, CANCEL_REASON_SHUTDOWN
///         or a custom code >= 5).
/// Returns: Ok(count) with the number of newly cancelled tokens (target plus
/// descendants); the Err cases above leave the state unchanged.
/// Complexity: O(token count^2) (descendant scan).
pub fn canceller_cancel(c: &mut Canceller, id: Int, reason: Int) -> Result[Int, Str] {
  let slot = _index(c, id);
  if slot < 0 {
    return _err_int("cancel: unknown token id");
  }
  if reason < 1 {
    return _err_int("cancel: reason must be >= 1");
  }
  if _reason_reserved(reason) {
    return _err_int("cancel: reason code is reserved");
  }
  let st: Int = c.states[slot];
  if st == CANCEL_STATE_CANCELLED {
    return _err_int("cancel: already cancelled");
  }
  let n = _apply_cancel(c, slot, reason, id);
  c.direct_cancels = c.direct_cancels + 1;
  return _ok_int(n);
}

/// Idempotent cancel: the strict canceller_cancel contract, except that a
/// token already CANCELLED is a no-op.
/// Validation order: unknown id -> Err("cancel: unknown token id");
/// `reason < 1` -> Err("cancel: reason must be >= 1"); reserved reason
/// (DEADLINE/PARENT) -> Err("cancel: reason code is reserved"); already
/// CANCELLED -> Ok(0) with the state (and the original reason/source/tick)
/// unchanged.
/// Returns: Ok(count) with the number of newly cancelled tokens: 0 for a
/// repeat call, otherwise as canceller_cancel.
/// Complexity: O(token count^2).
pub fn canceller_cancel_idempotent(c: &mut Canceller, id: Int, reason: Int) -> Result[Int, Str] {
  let slot = _index(c, id);
  if slot < 0 {
    return _err_int("cancel: unknown token id");
  }
  if reason < 1 {
    return _err_int("cancel: reason must be >= 1");
  }
  if _reason_reserved(reason) {
    return _err_int("cancel: reason code is reserved");
  }
  let st: Int = c.states[slot];
  if st == CANCEL_STATE_CANCELLED {
    return _ok_int(0);
  }
  let n = _apply_cancel(c, slot, reason, id);
  c.direct_cancels = c.direct_cancels + 1;
  return _ok_int(n);
}

// ---------------------------------------------------------------------------
// State accessors (read-only)
// ---------------------------------------------------------------------------

/// State code of token `id` (a CANCEL_STATE_* value), or CANCEL_NOT_FOUND
/// (-1) when unknown. Complexity: O(token count).
pub fn canceller_state(c: &Canceller, id: Int) -> Int {
  let slot = _index(c, id);
  if slot < 0 { return CANCEL_NOT_FOUND; }
  let st: Int = c.states[slot];
  return st;
}

/// True when token `id` exists and is CANCELLED. Complexity: O(token count).
pub fn canceller_is_cancelled(c: &Canceller, id: Int) -> Bool {
  return canceller_state(c, id) == CANCEL_STATE_CANCELLED;
}

/// True when token `id` exists and is ACTIVE. Complexity: O(token count).
pub fn canceller_is_active(c: &Canceller, id: Int) -> Bool {
  return canceller_state(c, id) == CANCEL_STATE_ACTIVE;
}

/// Reason code of token `id`: CANCEL_REASON_NONE (0) while ACTIVE, a
/// CANCEL_REASON_* (or custom) code while CANCELLED, CANCEL_NOT_FOUND (-1)
/// when unknown. Complexity: O(token count).
pub fn canceller_reason(c: &Canceller, id: Int) -> Int {
  let slot = _index(c, id);
  if slot < 0 { return CANCEL_NOT_FOUND; }
  let r: Int = c.reasons[slot];
  return r;
}

/// Source token of the cancellation of `id`: the token itself for a direct or
/// deadline cancel, the originating ancestor for a propagated (PARENT)
/// cancel; CANCEL_NOT_FOUND (-1) while ACTIVE or when unknown.
/// Complexity: O(token count).
pub fn canceller_source(c: &Canceller, id: Int) -> Int {
  let slot = _index(c, id);
  if slot < 0 { return CANCEL_NOT_FOUND; }
  let s: Int = c.sources[slot];
  return s;
}

/// Logical clock value at the cancellation of token `id`, or
/// CANCEL_NOT_FOUND (-1) while ACTIVE or when unknown.
/// Complexity: O(token count).
pub fn canceller_cancel_tick(c: &Canceller, id: Int) -> Int {
  let slot = _index(c, id);
  if slot < 0 { return CANCEL_NOT_FOUND; }
  let t: Int = c.cancel_ticks[slot];
  return t;
}

// ---------------------------------------------------------------------------
// Logical clock and deadlines
// ---------------------------------------------------------------------------

/// Current logical clock value (starts at 0, only moves forward).
/// Complexity: O(1).
pub fn canceller_now(c: &Canceller) -> Int {
  return c.now;
}

/// Advance the logical clock without checking deadlines.
/// Params: c - the registry; to - the new clock value, >= the current one.
/// Returns: Ok(to); Err("cancel: clock cannot go backwards") when
/// `to < c.now` (state unchanged). Deadlines are only evaluated by
/// canceller_check_deadline, canceller_sweep and canceller_tick.
/// Complexity: O(1).
pub fn canceller_advance(c: &mut Canceller, to: Int) -> Result[Int, Str] {
  if to < c.now {
    return _err_int("cancel: clock cannot go backwards");
  }
  c.now = to;
  return _ok_int(to);
}

/// Set (or replace) the absolute logical-tick deadline of an ACTIVE token.
/// Validation order: unknown id -> Err("cancel: unknown token id");
/// `tick < 0` -> Err("cancel: deadline must be >= 0"); token already
/// CANCELLED -> Err("cancel: already cancelled").
/// Returns: Ok(tick) on success; every Err case leaves the state unchanged.
/// Complexity: O(token count).
pub fn canceller_set_deadline(c: &mut Canceller, id: Int, tick: Int) -> Result[Int, Str] {
  let slot = _index(c, id);
  if slot < 0 {
    return _err_int("cancel: unknown token id");
  }
  if tick < 0 {
    return _err_int("cancel: deadline must be >= 0");
  }
  let st: Int = c.states[slot];
  if st == CANCEL_STATE_CANCELLED {
    return _err_int("cancel: already cancelled");
  }
  c.deadlines[slot] = tick;
  return _ok_int(tick);
}

/// Clear the deadline of an ACTIVE token.
/// Validation order: unknown id -> Err("cancel: unknown token id"); token
/// already CANCELLED -> Err("cancel: already cancelled").
/// Returns: Ok(CANCEL_NO_DEADLINE) (-1) on success; every Err case leaves the
/// state unchanged.
/// Complexity: O(token count).
pub fn canceller_clear_deadline(c: &mut Canceller, id: Int) -> Result[Int, Str] {
  let slot = _index(c, id);
  if slot < 0 {
    return _err_int("cancel: unknown token id");
  }
  let st: Int = c.states[slot];
  if st == CANCEL_STATE_CANCELLED {
    return _err_int("cancel: already cancelled");
  }
  c.deadlines[slot] = CANCEL_NO_DEADLINE;
  return _ok_int(CANCEL_NO_DEADLINE);
}

/// Deadline of token `id` (absolute logical tick), or CANCEL_NO_DEADLINE
/// (-1) when none is set or the id is unknown.
/// Complexity: O(token count).
pub fn canceller_deadline(c: &Canceller, id: Int) -> Int {
  let slot = _index(c, id);
  if slot < 0 { return CANCEL_NO_DEADLINE; }
  let d: Int = c.deadlines[slot];
  return d;
}

/// True when token `id` exists and has a deadline set.
/// Complexity: O(token count).
pub fn canceller_has_deadline(c: &Canceller, id: Int) -> Bool {
  return canceller_deadline(c, id) >= 0;
}

/// Check one token against the current logical clock: when it is ACTIVE, has
/// a deadline and `now >= deadline`, cancel it (and its ACTIVE descendants)
/// with reason CANCEL_REASON_DEADLINE and source = its own id.
/// Params: c - the registry; id - the token to check.
/// Returns: Ok(count) with the number of tokens newly cancelled by this call
/// (0 when the token has no deadline, is not due, or is already CANCELLED);
/// Err("cancel: unknown token id") when unknown (state unchanged).
/// Complexity: O(token count^2).
pub fn canceller_check_deadline(c: &mut Canceller, id: Int) -> Result[Int, Str] {
  let slot = _index(c, id);
  if slot < 0 {
    return _err_int("cancel: unknown token id");
  }
  let st: Int = c.states[slot];
  if st != CANCEL_STATE_ACTIVE {
    return _ok_int(0);
  }
  let d: Int = c.deadlines[slot];
  if d < 0 {
    return _ok_int(0);
  }
  if c.now < d {
    return _ok_int(0);
  }
  let n = _apply_cancel(c, slot, CANCEL_REASON_DEADLINE, id);
  c.deadline_cancels = c.deadline_cancels + 1;
  return _ok_int(n);
}

/// Sweep every token in creation order against the current logical clock and
/// cancel the due ones with reason CANCEL_REASON_DEADLINE (propagation
/// included). A token already cancelled (for example by an earlier due
/// ancestor in the same sweep) is skipped, so no token is cancelled twice.
/// Returns: the number of tokens newly cancelled by this sweep.
/// Complexity: O(token count^2).
pub fn canceller_sweep(c: &mut Canceller) -> Int {
  var total = 0;
  var i = 0;
  while i < c.token_ids.len() {
    let st: Int = c.states[i];
    if st == CANCEL_STATE_ACTIVE {
      let d: Int = c.deadlines[i];
      if d >= 0 && c.now >= d {
        let tid: Int = c.token_ids[i];
        let n = _apply_cancel(c, i, CANCEL_REASON_DEADLINE, tid);
        c.deadline_cancels = c.deadline_cancels + 1;
        total = total + n;
      }
    }
    i = i + 1;
  }
  return total;
}

/// Advance the logical clock to `to` and sweep all deadlines at the new
/// clock value: canceller_advance followed by canceller_sweep.
/// Params: c - the registry; to - the new clock value, >= the current one.
/// Returns: Ok(count) with the number of tokens newly cancelled by the sweep;
/// Err("cancel: clock cannot go backwards") when `to < c.now` (state
/// unchanged; no sweep runs).
/// Complexity: O(token count^2).
pub fn canceller_tick(c: &mut Canceller, to: Int) -> Result[Int, Str] {
  if to < c.now {
    return _err_int("cancel: clock cannot go backwards");
  }
  c.now = to;
  let n = canceller_sweep(c);
  return _ok_int(n);
}

// ---------------------------------------------------------------------------
// Counters
// ---------------------------------------------------------------------------

/// Number of tokens in the CANCELLED state. Complexity: O(token count).
pub fn canceller_cancelled_count(c: &Canceller) -> Int {
  var n = 0;
  var i = 0;
  while i < c.states.len() {
    let st: Int = c.states[i];
    if st == CANCEL_STATE_CANCELLED { n = n + 1; }
    i = i + 1;
  }
  return n;
}

/// Number of tokens in the ACTIVE state. Complexity: O(token count).
pub fn canceller_active_count(c: &Canceller) -> Int {
  var n = 0;
  var i = 0;
  while i < c.states.len() {
    let st: Int = c.states[i];
    if st == CANCEL_STATE_ACTIVE { n = n + 1; }
    i = i + 1;
  }
  return n;
}

/// Successful explicit cancels (canceller_cancel and
/// canceller_cancel_idempotent); each grows the counter by exactly one for
/// the target token. Complexity: O(1).
pub fn canceller_direct_cancels(c: &Canceller) -> Int {
  return c.direct_cancels;
}

/// Tokens cancelled by a due deadline (check/sweep/tick).
/// Complexity: O(1).
pub fn canceller_deadline_cancels(c: &Canceller) -> Int {
  return c.deadline_cancels;
}

/// Descendants cancelled by propagation, including children born under an
/// already-cancelled parent. Complexity: O(1).
pub fn canceller_propagated_cancels(c: &Canceller) -> Int {
  return c.propagated_cancels;
}

// ---------------------------------------------------------------------------
// Aggregation of cancellation state
// ---------------------------------------------------------------------------

/// Classify a caller-supplied id list. Precedence: an empty list is
/// CANCEL_AGG_EMPTY; any unknown id makes the result CANCEL_AGG_UNKNOWN;
/// otherwise CANCEL_AGG_ALL when every listed token is CANCELLED,
/// CANCEL_AGG_NONE when none is, and CANCEL_AGG_SOME in between. Duplicate
/// ids are counted per entry.
/// Params: c - the registry; ids - the token ids to classify.
/// Returns: one of the CANCEL_AGG_* codes.
/// Complexity: O(list length * token count).
pub fn canceller_aggregate(c: &Canceller, ids: &Vec[Int]) -> Int {
  let n = ids.len();
  if n == 0 { return CANCEL_AGG_EMPTY; }
  var cancelled = 0;
  var unknown = 0;
  var i = 0;
  while i < n {
    let id: Int = ids[i];
    let slot = _index(c, id);
    if slot < 0 {
      unknown = unknown + 1;
    } else {
      let st: Int = c.states[slot];
      if st == CANCEL_STATE_CANCELLED { cancelled = cancelled + 1; }
    }
    i = i + 1;
  }
  if unknown > 0 { return CANCEL_AGG_UNKNOWN; }
  if cancelled == 0 { return CANCEL_AGG_NONE; }
  if cancelled == n { return CANCEL_AGG_ALL; }
  return CANCEL_AGG_SOME;
}

/// True when at least one listed token is CANCELLED (false for an empty list;
/// unknown ids are treated as not cancelled).
/// Complexity: O(list length * token count).
pub fn canceller_any_cancelled(c: &Canceller, ids: &Vec[Int]) -> Bool {
  var i = 0;
  while i < ids.len() {
    let id: Int = ids[i];
    if canceller_is_cancelled(c, id) { return true; }
    i = i + 1;
  }
  return false;
}

/// True when every listed token is CANCELLED (true for an empty list; an
/// unknown id makes the result false).
/// Complexity: O(list length * token count).
pub fn canceller_all_cancelled(c: &Canceller, ids: &Vec[Int]) -> Bool {
  var i = 0;
  while i < ids.len() {
    let id: Int = ids[i];
    let slot = _index(c, id);
    if slot < 0 { return false; }
    let st: Int = c.states[slot];
    if st != CANCEL_STATE_CANCELLED { return false; }
    i = i + 1;
  }
  return true;
}

/// Number of listed tokens that are CANCELLED (unknown ids are not counted;
/// duplicates are counted per entry). Complexity: O(list length * token
/// count).
pub fn canceller_count_cancelled(c: &Canceller, ids: &Vec[Int]) -> Int {
  var n = 0;
  var i = 0;
  while i < ids.len() {
    let id: Int = ids[i];
    if canceller_is_cancelled(c, id) { n = n + 1; }
    i = i + 1;
  }
  return n;
}

/// First id in list order whose token is CANCELLED, or CANCEL_NOT_FOUND (-1)
/// when none is (unknown ids are skipped).
/// Complexity: O(list length * token count).
pub fn canceller_first_cancelled(c: &Canceller, ids: &Vec[Int]) -> Int {
  var i = 0;
  while i < ids.len() {
    let id: Int = ids[i];
    if canceller_is_cancelled(c, id) { return id; }
    i = i + 1;
  }
  return CANCEL_NOT_FOUND;
}

/// Largest reason code among the listed CANCELLED tokens (a simple
/// "worst reason so far" aggregate), or CANCEL_REASON_NONE (0) when none is
/// cancelled; unknown ids and ACTIVE tokens are skipped.
/// Complexity: O(list length * token count).
pub fn canceller_worst_reason(c: &Canceller, ids: &Vec[Int]) -> Int {
  var worst = CANCEL_REASON_NONE;
  var i = 0;
  while i < ids.len() {
    let id: Int = ids[i];
    let r = canceller_reason(c, id);
    if r > worst { worst = r; }
    i = i + 1;
  }
  return worst;
}

// ---------------------------------------------------------------------------
// Names and invariant check
// ---------------------------------------------------------------------------

/// Human-readable state name: "active", "cancelled" or "unknown".
/// Complexity: O(1).
pub fn canceller_state_name(state: Int) -> Str {
  if state == CANCEL_STATE_ACTIVE { return "active"; }
  if state == CANCEL_STATE_CANCELLED { return "cancelled"; }
  return "unknown";
}

/// Human-readable reason name: "none", "user", "deadline", "parent",
/// "shutdown", "custom" for any code >= 5, or "unknown" for a negative code.
/// Complexity: O(1).
pub fn cancel_reason_name(code: Int) -> Str {
  if code == CANCEL_REASON_NONE { return "none"; }
  if code == CANCEL_REASON_USER { return "user"; }
  if code == CANCEL_REASON_DEADLINE { return "deadline"; }
  if code == CANCEL_REASON_PARENT { return "parent"; }
  if code == CANCEL_REASON_SHUTDOWN { return "shutdown"; }
  if code < 1 { return "unknown"; }
  return "custom";
}

/// Human-readable aggregate name: "none", "some", "all", "empty", "unknown"
/// (for CANCEL_AGG_UNKNOWN, which means at least one id is not in the
/// registry), or "invalid" for any other code. Complexity: O(1).
pub fn canceller_aggregate_name(code: Int) -> Str {
  if code == CANCEL_AGG_NONE { return "none"; }
  if code == CANCEL_AGG_SOME { return "some"; }
  if code == CANCEL_AGG_ALL { return "all"; }
  if code == CANCEL_AGG_EMPTY { return "empty"; }
  if code == CANCEL_AGG_UNKNOWN { return "unknown"; }
  return "invalid";
}

/// Structural invariant of a cancellation registry, true exactly when:
/// 1. the seven token vectors have equal length; `now` is >= 0;
/// 2. every token id is >= 0 and unique; every parent is -1 or names an
///    existing token at a smaller slot (forest, no cycles); every state is a
///    CANCEL_STATE_* code; every deadline is >= -1;
/// 3. an ACTIVE token has reason NONE (0), source -1 and cancel_tick -1;
/// 4. a CANCELLED token has reason >= 1, source >= 0 (an existing token) and
///    cancel_tick >= 0; for reason PARENT the source is a proper ancestor
///    whose own reason is not PARENT; otherwise the source is the token
///    itself;
/// 5. propagation closure: a token whose parent is CANCELLED is itself
///    CANCELLED;
/// 6. the counters match the states: direct + deadline + propagated equals
///    the number of CANCELLED tokens, each token classified by reason
///    (PARENT -> propagated, DEADLINE -> deadline, otherwise direct).
/// Complexity: O(token count^2).
pub fn canceller_check_invariant(c: &Canceller) -> Bool {
  let n = c.token_ids.len();
  if c.parents.len() != n { return false; }
  if c.states.len() != n { return false; }
  if c.reasons.len() != n { return false; }
  if c.sources.len() != n { return false; }
  if c.cancel_ticks.len() != n { return false; }
  if c.deadlines.len() != n { return false; }
  if c.now < 0 { return false; }
  var i = 0;
  while i < n {
    let id: Int = c.token_ids[i];
    let par: Int = c.parents[i];
    let st: Int = c.states[i];
    let rs: Int = c.reasons[i];
    let src: Int = c.sources[i];
    let tick: Int = c.cancel_ticks[i];
    let dl: Int = c.deadlines[i];
    if id < 0 { return false; }
    if st < CANCEL_STATE_ACTIVE { return false; }
    if st > CANCEL_STATE_CANCELLED { return false; }
    if dl < CANCEL_NO_DEADLINE { return false; }
    if par >= 0 {
      let pslot = _index(c, par);
      if pslot < 0 { return false; }
      if pslot >= i { return false; }
    }
    var dup = false;
    var j = 0;
    while j < n {
      if j != i {
        let other: Int = c.token_ids[j];
        if other == id { dup = true; }
      }
      j = j + 1;
    }
    if dup { return false; }
    if st == CANCEL_STATE_ACTIVE {
      if rs != CANCEL_REASON_NONE { return false; }
      if src != CANCEL_NOT_FOUND { return false; }
      if tick != CANCEL_NOT_FOUND { return false; }
    } else {
      if rs < 1 { return false; }
      if src < 0 { return false; }
      if tick < 0 { return false; }
      let sslot = _index(c, src);
      if sslot < 0 { return false; }
      if rs == CANCEL_REASON_PARENT {
        if sslot >= i { return false; }
        if !_is_descendant(c, i, sslot) { return false; }
        let srs: Int = c.reasons[sslot];
        if srs == CANCEL_REASON_PARENT { return false; }
      } else {
        if src != id { return false; }
      }
    }
    i = i + 1;
  }
  var k = 0;
  while k < n {
    let par: Int = c.parents[k];
    if par >= 0 {
      let pslot = _index(c, par);
      let pst: Int = c.states[pslot];
      if pst == CANCEL_STATE_CANCELLED {
        let kst: Int = c.states[k];
        if kst != CANCEL_STATE_CANCELLED { return false; }
      }
    }
    k = k + 1;
  }
  var direct = 0;
  var deadline = 0;
  var propagated = 0;
  var t = 0;
  while t < n {
    let st: Int = c.states[t];
    if st == CANCEL_STATE_CANCELLED {
      let rs: Int = c.reasons[t];
      if rs == CANCEL_REASON_PARENT { propagated = propagated + 1; }
      if rs == CANCEL_REASON_DEADLINE { deadline = deadline + 1; }
      if rs != CANCEL_REASON_PARENT && rs != CANCEL_REASON_DEADLINE { direct = direct + 1; }
    }
    t = t + 1;
  }
  if c.direct_cancels != direct { return false; }
  if c.deadline_cancels != deadline { return false; }
  if c.propagated_cancels != propagated { return false; }
  return true;
}
