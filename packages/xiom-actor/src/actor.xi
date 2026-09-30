// XIOM -- xiom.actor: pure deterministic actor-model scheduler
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model: the actor model as a pure, deterministic state machine -- the
// semantic core an actor runtime would drive. There are no threads, no
// atomics, no locks, no clock and no I/O here: the caller owns concurrency
// and every function is a total transition over plain values. The system
// owns:
//   * actors as parallel Vec[Int] fields (ids, priorities, creation order,
//     lifecycle states, behavior codes and versions, spawn behaviors,
//     mailbox capacities and overflow policies, supervision links,
//     supervision directives, restart/processed/accumulator counters);
//   * a bounded mailbox per actor, stored as one global FIFO of messages
//     (parallel id/target/sender/tag/payload vectors) filtered by owner,
//     with two overflow policies: DROP_NEW and DROP_OLDEST -- both route
//     the lost message to the dead-letter sink with an exact reason code;
//   * a ready queue (actor ids) whose selection rule is: largest priority
//     first, ties broken by queue arrival (FIFO within a priority level);
//   * behavior switch (`become`) with versioned state: every switch bumps
//     the behavior version, and a supervised restart resets behavior state;
//   * supervision links (one supervisor per actor, a forest with acyclicity
//     enforced at link time) with three directives: RESTART, STOP, ESCALATE;
//   * dead-letter routing with a reason code per lost message;
//   * step-driven execution (`actor_step`, `actor_run_all`) with a dispatch
//     trace, a processed-message log, an event log and stats counters.
//
// Actor states: IDLE -> SCHEDULED -> RUNNING -> IDLE | STOPPED | FAILED.
//   IDLE       not queued and mailbox empty
//   SCHEDULED  in the ready queue, waiting for dispatch
//   RUNNING    transient: only observable inside actor_step
//   STOPPED    terminal (self-stop or a supervisor STOP directive)
//   FAILED     terminal (unhandled crash or an escalated crash)
// A restart (supervision RESTART) moves FAILED -> IDLE -> SCHEDULED and
// resets the behavior to the spawn behavior with version 0 and accumulator
// 0; the mailbox is preserved. STOP and ESCALATE drain the mailbox to the
// dead letters.
//
// Language notes (XIOM v0.62.2): free functions only; Ok/Err are constructed
// only inside the _ok_*/_err_* leaf helpers; Vec[Int] element reads are bound
// with a typed `let`; parallel Vec fields are pushed and rebuilt together so
// they can never skew; no Vec[StructType], no indexed Vec[fn] dispatch, no
// generic callbacks, no Vec[Float64], no `mut` in match patterns, no FFI, no
// threads, no `log`-named function. No Str value is ever compared with `==`.

module xiom.actor

use xiom.convert;

// ---------------------------------------------------------------------------
// Public constants
// ---------------------------------------------------------------------------

/// Mailbox overflow policy: when the mailbox is full the new message is
/// dropped to the dead letters (reason ACTOR_DEAD_OVERFLOW).
pub const ACTOR_OVERFLOW_DROP_NEW: Int = 0;

/// Mailbox overflow policy: when the mailbox is full the oldest queued
/// message is evicted to the dead letters (reason ACTOR_DEAD_EVICTED) and
/// the new message is appended.
pub const ACTOR_OVERFLOW_DROP_OLDEST: Int = 1;

/// Actor state: idle, not queued, empty mailbox.
pub const ACTOR_IDLE: Int = 0;

/// Actor state: in the ready queue, waiting for dispatch.
pub const ACTOR_SCHEDULED: Int = 1;

/// Actor state: dispatched; transient, only observable inside actor_step.
pub const ACTOR_RUNNING: Int = 2;

/// Actor state: terminal, stopped by itself or by a supervisor STOP.
pub const ACTOR_STOPPED: Int = 3;

/// Actor state: terminal, unhandled or escalated crash.
pub const ACTOR_FAILED: Int = 4;

/// Behavior: echo the message to the trace; a tag >= ACTOR_TAG_BECOME
/// switches the actor to ACTOR_BEHAVIOR_COUNT.
pub const ACTOR_BEHAVIOR_ECHO: Int = 0;

/// Behavior: add the payload to the accumulator; tag ACTOR_TAG_REVERT
/// switches back to ECHO, tag ACTOR_TAG_SELF_STOP stops the actor.
pub const ACTOR_BEHAVIOR_COUNT: Int = 1;

/// Behavior: count the message and do nothing else.
pub const ACTOR_BEHAVIOR_SINK: Int = 2;

/// Supervision directive: restart the failed child (mailbox preserved,
/// behavior reset to the spawn behavior, restart counter incremented).
pub const ACTOR_RESTART: Int = 0;

/// Supervision directive: stop the failed child and dead-letter its mailbox.
pub const ACTOR_STOP: Int = 1;

/// Supervision directive: fail the child permanently, dead-letter its
/// mailbox, then crash the supervisor with the same code.
pub const ACTOR_ESCALATE: Int = 2;

/// Dead-letter reason: the target actor does not exist.
pub const ACTOR_DEAD_UNKNOWN: Int = 0;

/// Dead-letter reason: the target actor is stopped.
pub const ACTOR_DEAD_STOPPED: Int = 1;

/// Dead-letter reason: the target mailbox was full (DROP_NEW).
pub const ACTOR_DEAD_OVERFLOW: Int = 2;

/// Dead-letter reason: evicted from a full mailbox (DROP_OLDEST).
pub const ACTOR_DEAD_EVICTED: Int = 3;

/// Dead-letter reason: the target actor is failed, or a STOP/ESCALATE
/// directive drained a terminal mailbox.
pub const ACTOR_DEAD_FAILED: Int = 4;

/// Well-known tag: crashes the receiving actor with the message payload as
/// the crash code, whatever its current behavior.
pub const ACTOR_TAG_CRASH: Int = 999;

/// Well-known tag: an ECHO actor switches to COUNT when tag >= this value.
pub const ACTOR_TAG_BECOME: Int = 100;

/// Well-known tag: a COUNT actor switches back to ECHO.
pub const ACTOR_TAG_REVERT: Int = 200;

/// Well-known tag: a COUNT actor stops itself.
pub const ACTOR_TAG_SELF_STOP: Int = 201;

/// Sentinel: no supervisor is linked.
pub const ACTOR_NO_SUPERVISOR: Int = -1;

/// Sentinel: no external sender (the message originates outside the system).
pub const ACTOR_NO_SENDER: Int = -1;

/// Sentinel: unknown actor / out of range accessor result.
pub const ACTOR_NOT_FOUND: Int = -1;

/// Actor system state. Every field is an internal implementation detail;
/// callers must go through the actor_* free functions.
///
/// Actors are stored as parallel Vec[Int] fields indexed by actor slot:
/// actor_ids[i] (unique, >= 0), actor_priorities[i] (>= 0, larger = more
/// urgent), actor_orders[i] (creation sequence, dense: order == slot),
/// actor_states[i] (an ACTOR_* state code), actor_behaviors[i] and
/// actor_spawn_behaviors[i] (an ACTOR_BEHAVIOR_* code), actor_versions[i]
/// (behavior version: 0 at spawn and after a restart, +1 per become),
/// actor_capacities[i] (0 = unbounded), actor_overflows[i], and
/// actor_supervisors[i] (supervisor actor id or ACTOR_NO_SUPERVISOR).
/// actor_directives[i] is the directive this actor applies as a supervisor;
/// actor_restarts[i], actor_processed[i] and actor_accumulators[i] are
/// per-actor counters. Messages are stored as one global FIFO in parallel
/// msg_* vectors indexed by queue position (0 = oldest): every message
/// carries its target actor id and its globally unique sequence id assigned
/// by actor_send. Dead letters mirror the message shape in dead_* vectors
/// plus a reason code. dispatch_order is the global dispatch trace;
/// proc_actors/proc_tags/proc_payloads are the consumed-message log;
/// events is the human-readable audit trail. Global counters: messages_sent
/// (successful enqueues), messages_processed, mail_drained (messages removed
/// from a mailbox without being consumed: evictions and terminal drains),
/// steps, total_restarts, total_stops, total_escalations, total_crashes.
pub type ActorSystem = {
  actor_ids: Vec[Int];
  actor_priorities: Vec[Int];
  actor_orders: Vec[Int];
  actor_states: Vec[Int];
  actor_behaviors: Vec[Int];
  actor_spawn_behaviors: Vec[Int];
  actor_versions: Vec[Int];
  actor_capacities: Vec[Int];
  actor_overflows: Vec[Int];
  actor_supervisors: Vec[Int];
  actor_directives: Vec[Int];
  actor_restarts: Vec[Int];
  actor_processed: Vec[Int];
  actor_accumulators: Vec[Int];
  next_order: Int;
  ready_ids: Vec[Int];
  msg_ids: Vec[Int];
  msg_targets: Vec[Int];
  msg_senders: Vec[Int];
  msg_tags: Vec[Int];
  msg_payloads: Vec[Int];
  next_message_id: Int;
  mail_drained: Int;
  dead_ids: Vec[Int];
  dead_targets: Vec[Int];
  dead_senders: Vec[Int];
  dead_tags: Vec[Int];
  dead_payloads: Vec[Int];
  dead_reasons: Vec[Int];
  dispatch_order: Vec[Int];
  events: Vec[Str];
  proc_actors: Vec[Int];
  proc_tags: Vec[Int];
  proc_payloads: Vec[Int];
  messages_sent: Int;
  messages_processed: Int;
  steps: Int;
  total_restarts: Int;
  total_stops: Int;
  total_escalations: Int;
  total_crashes: Int;
}

// ---------------------------------------------------------------------------
// Result constructors (leaf helpers only; see the header comment)
// ---------------------------------------------------------------------------

fn _ok_int(v: Int) -> Result[Int, Str] { return Ok(v); }
fn _err_int(m: Str) -> Result[Int, Str] { return Err(m); }
fn _ok_vec(v: Vec[Int]) -> Result[Vec[Int], Str] { return Ok(v); }
fn _err_vec(m: Str) -> Result[Vec[Int], Str] { return Err(m); }

// ---------------------------------------------------------------------------
// Validation helpers
// ---------------------------------------------------------------------------

fn _valid_overflow(o: Int) -> Bool {
  if o == ACTOR_OVERFLOW_DROP_NEW { return true; }
  if o == ACTOR_OVERFLOW_DROP_OLDEST { return true; }
  return false;
}

fn _valid_behavior(b: Int) -> Bool {
  if b == ACTOR_BEHAVIOR_ECHO { return true; }
  if b == ACTOR_BEHAVIOR_COUNT { return true; }
  if b == ACTOR_BEHAVIOR_SINK { return true; }
  return false;
}

fn _valid_directive(d: Int) -> Bool {
  if d == ACTOR_RESTART { return true; }
  if d == ACTOR_STOP { return true; }
  if d == ACTOR_ESCALATE { return true; }
  return false;
}

fn _valid_state(st: Int) -> Bool {
  if st < ACTOR_IDLE { return false; }
  if st > ACTOR_FAILED { return false; }
  return true;
}

// ---------------------------------------------------------------------------
// Text helpers
// ---------------------------------------------------------------------------

fn _ev1(name: Str, a: Int) -> Str {
  return name + ":" + convert.int_to_string(a);
}

fn _ev2(name: Str, a: Int, b: Int) -> Str {
  return name + ":" + convert.int_to_string(a) + ":" + convert.int_to_string(b);
}

fn _ev3(name: Str, a: Int, b: Int, c: Int) -> Str {
  return name + ":" + convert.int_to_string(a) + ":" + convert.int_to_string(b) + ":" + convert.int_to_string(c);
}

fn _event(s: &mut ActorSystem, text: Str) {
  s.events.push(text);
}

// ---------------------------------------------------------------------------
// Lookup helpers
// ---------------------------------------------------------------------------

// Slot of actor `id`, or -1 when unknown.
fn _actor_slot(s: &ActorSystem, id: Int) -> Int {
  var i = 0;
  while i < s.actor_ids.len() {
    let cur: Int = s.actor_ids[i];
    if cur == id { return i; }
    i = i + 1;
  }
  return -1;
}

// Number of messages queued for actor `id`.
fn _mailbox_len(s: &ActorSystem, id: Int) -> Int {
  var n = 0;
  var i = 0;
  while i < s.msg_targets.len() {
    let t: Int = s.msg_targets[i];
    if t == id { n = n + 1; }
    i = i + 1;
  }
  return n;
}

// Queue position of the oldest message for actor `id`, or -1 when none.
fn _mailbox_head_index(s: &ActorSystem, id: Int) -> Int {
  var i = 0;
  while i < s.msg_targets.len() {
    let t: Int = s.msg_targets[i];
    if t == id { return i; }
    i = i + 1;
  }
  return -1;
}

// True when `id` is currently in the ready queue.
fn _queue_has(s: &ActorSystem, id: Int) -> Bool {
  var i = 0;
  while i < s.ready_ids.len() {
    let cur: Int = s.ready_ids[i];
    if cur == id { return true; }
    i = i + 1;
  }
  return false;
}

// Ready-queue position selected by the scheduling rule: largest actor
// priority first, ties broken by queue arrival (FIFO within a level). The
// scan is left-to-right and only a strictly larger priority wins, so the
// earliest queue position keeps a residual tie. Returns -1 when empty.
fn _pick_index(s: &ActorSystem) -> Int {
  let n = s.ready_ids.len();
  if n == 0 { return -1; }
  let first: Int = s.ready_ids[0];
  let fslot = _actor_slot(s, first);
  var best = 0;
  var best_pri = -1;
  if fslot >= 0 { best_pri = s.actor_priorities[fslot]; }
  var i = 1;
  while i < n {
    let cand: Int = s.ready_ids[i];
    let cslot = _actor_slot(s, cand);
    var cpri = -1;
    if cslot >= 0 { cpri = s.actor_priorities[cslot]; }
    if cpri > best_pri {
      best = i;
      best_pri = cpri;
    }
    i = i + 1;
  }
  return best;
}

// ---------------------------------------------------------------------------
// Queue and mailbox mutation helpers
// ---------------------------------------------------------------------------

// Remove the first ready-queue entry equal to `id`, rebuilding the vector.
fn _queue_remove_id(s: &mut ActorSystem, id: Int) {
  var out = Vec[Int].new();
  var removed = false;
  var i = 0;
  while i < s.ready_ids.len() {
    let cur: Int = s.ready_ids[i];
    if cur == id && !removed { removed = true; } else { out.push(cur); }
    i = i + 1;
  }
  s.ready_ids = out;
}

// Remove the ready-queue entry at `idx`, rebuilding the vector.
fn _queue_remove_at(s: &mut ActorSystem, idx: Int) {
  var out = Vec[Int].new();
  var i = 0;
  while i < s.ready_ids.len() {
    if i != idx {
      let v: Int = s.ready_ids[i];
      out.push(v);
    }
    i = i + 1;
  }
  s.ready_ids = out;
}

// IDLE -> SCHEDULED: append the actor to the back of the ready queue.
fn _schedule(s: &mut ActorSystem, slot: Int) {
  s.actor_states[slot] = ACTOR_SCHEDULED;
  let id: Int = s.actor_ids[slot];
  s.ready_ids.push(id);
}

// Append one message to the global FIFO (all five vectors in step).
fn _enqueue_msg(s: &mut ActorSystem, seq: Int, target: Int, sender: Int, tag: Int, payload: Int) {
  s.msg_ids.push(seq);
  s.msg_targets.push(target);
  s.msg_senders.push(sender);
  s.msg_tags.push(tag);
  s.msg_payloads.push(payload);
}

// Remove the message at `idx`, rebuilding all five vectors in step.
fn _remove_message_at(s: &mut ActorSystem, idx: Int) {
  var ids = Vec[Int].new();
  var targets = Vec[Int].new();
  var senders = Vec[Int].new();
  var tags = Vec[Int].new();
  var payloads = Vec[Int].new();
  var i = 0;
  while i < s.msg_ids.len() {
    if i != idx {
      let a: Int = s.msg_ids[i];
      let b: Int = s.msg_targets[i];
      let c: Int = s.msg_senders[i];
      let d: Int = s.msg_tags[i];
      let e: Int = s.msg_payloads[i];
      ids.push(a);
      targets.push(b);
      senders.push(c);
      tags.push(d);
      payloads.push(e);
    }
    i = i + 1;
  }
  s.msg_ids = ids;
  s.msg_targets = targets;
  s.msg_senders = senders;
  s.msg_tags = tags;
  s.msg_payloads = payloads;
}

// Append one dead letter (all six vectors in step).
fn _dead_letter_new(s: &mut ActorSystem, seq: Int, target: Int, sender: Int, tag: Int, payload: Int, reason: Int) {
  s.dead_ids.push(seq);
  s.dead_targets.push(target);
  s.dead_senders.push(sender);
  s.dead_tags.push(tag);
  s.dead_payloads.push(payload);
  s.dead_reasons.push(reason);
}

// Move the queued message at `idx` to the dead letters with `reason`; this
// is the only removal path that does not consume a message, so the drained
// counter is bumped here (evictions and terminal mailbox drains).
fn _dead_letter_at(s: &mut ActorSystem, idx: Int, reason: Int) {
  let mid: Int = s.msg_ids[idx];
  let mt: Int = s.msg_targets[idx];
  let ms: Int = s.msg_senders[idx];
  let mtg: Int = s.msg_tags[idx];
  let mp: Int = s.msg_payloads[idx];
  _dead_letter_new(s, mid, mt, ms, mtg, mp, reason);
  _remove_message_at(s, idx);
  s.mail_drained = s.mail_drained + 1;
}

// Move every queued message of actor `id` to the dead letters. The loop
// walks forward without incrementing after a removal (the next candidate
// shifts into the freed position), so it always makes progress.
fn _dead_letter_mailbox(s: &mut ActorSystem, id: Int, reason: Int) {
  var i = 0;
  while i < s.msg_targets.len() {
    let t: Int = s.msg_targets[i];
    if t == id {
      _dead_letter_at(s, i, reason);
    } else {
      i = i + 1;
    }
  }
}

// ---------------------------------------------------------------------------
// Behavior, stop and crash transitions
// ---------------------------------------------------------------------------

// Switch the behavior of slot `slot` and bump its version. Returns the new
// version. The caller has validated the behavior code and the state.
fn _become_inner(s: &mut ActorSystem, slot: Int, behavior: Int) -> Int {
  s.actor_behaviors[slot] = behavior;
  let v: Int = s.actor_versions[slot] + 1;
  s.actor_versions[slot] = v;
  let id: Int = s.actor_ids[slot];
  _event(s, _ev3("become", id, behavior, v));
  return v;
}

// Stop slot `slot` (self-stop or a STOP directive): terminal, drained.
fn _stop_actor(s: &mut ActorSystem, slot: Int, reason: Str) {
  let id: Int = s.actor_ids[slot];
  s.actor_states[slot] = ACTOR_STOPPED;
  _queue_remove_id(s, id);
  _dead_letter_mailbox(s, id, ACTOR_DEAD_STOPPED);
  s.total_stops = s.total_stops + 1;
  _event(s, "stop:" + convert.int_to_string(id) + ":" + reason);
}

// Crash slot `slot` with `code` and apply supervision. The caller has
// validated that the actor exists and is not already terminal. The walk up
// the supervision chain is bounded by the chain length (the link-time cycle
// check keeps the forest acyclic), so the recursion terminates.
fn _crash_inner(s: &mut ActorSystem, slot: Int, code: Int) {
  let st: Int = s.actor_states[slot];
  if st == ACTOR_STOPPED { return; }
  if st == ACTOR_FAILED { return; }
  let id: Int = s.actor_ids[slot];
  s.actor_states[slot] = ACTOR_FAILED;
  s.total_crashes = s.total_crashes + 1;
  _queue_remove_id(s, id);
  _event(s, _ev2("crash", id, code));
  let sup: Int = s.actor_supervisors[slot];
  if sup < 0 {
    _dead_letter_mailbox(s, id, ACTOR_DEAD_FAILED);
    _event(s, _ev1("unhandled", id));
    return;
  }
  let sslot = _actor_slot(s, sup);
  if sslot < 0 {
    _dead_letter_mailbox(s, id, ACTOR_DEAD_FAILED);
    _event(s, _ev1("unhandled", id));
    return;
  }
  let directive: Int = s.actor_directives[sslot];
  if directive == ACTOR_RESTART {
    s.actor_states[slot] = ACTOR_IDLE;
    let sb: Int = s.actor_spawn_behaviors[slot];
    s.actor_behaviors[slot] = sb;
    s.actor_versions[slot] = 0;
    s.actor_accumulators[slot] = 0;
    s.actor_restarts[slot] = s.actor_restarts[slot] + 1;
    s.total_restarts = s.total_restarts + 1;
    _event(s, _ev2("restart", id, sup));
    if _mailbox_len(s, id) > 0 {
      _schedule(s, slot);
    }
    return;
  }
  if directive == ACTOR_STOP {
    s.actor_states[slot] = ACTOR_STOPPED;
    _dead_letter_mailbox(s, id, ACTOR_DEAD_STOPPED);
    s.total_stops = s.total_stops + 1;
    _event(s, "stop:" + convert.int_to_string(id) + ":" + convert.int_to_string(sup));
    return;
  }
  // ESCALATE: fail the child permanently, drain it, then crash the
  // supervisor with the same code (recursively up the chain).
  _dead_letter_mailbox(s, id, ACTOR_DEAD_FAILED);
  s.total_escalations = s.total_escalations + 1;
  _event(s, _ev2("escalate", id, sup));
  _crash_inner(s, sslot, code);
}

// Consume one message for slot `slot`. The message is counted and logged
// first, then the well-known CRASH tag wins over the behavior; otherwise the
// behavior state machine runs. Called only from actor_step, so the actor is
// RUNNING (or becomes terminal/IDLE through this call).
fn _process(s: &mut ActorSystem, slot: Int, tag: Int, payload: Int) {
  let id: Int = s.actor_ids[slot];
  s.actor_processed[slot] = s.actor_processed[slot] + 1;
  s.messages_processed = s.messages_processed + 1;
  s.proc_actors.push(id);
  s.proc_tags.push(tag);
  s.proc_payloads.push(payload);
  if tag == ACTOR_TAG_CRASH {
    _crash_inner(s, slot, payload);
    return;
  }
  let b: Int = s.actor_behaviors[slot];
  if b == ACTOR_BEHAVIOR_ECHO {
    _event(s, _ev3("echo", id, tag, payload));
    if tag >= ACTOR_TAG_BECOME {
      let nv = _become_inner(s, slot, ACTOR_BEHAVIOR_COUNT);
    }
    return;
  }
  if b == ACTOR_BEHAVIOR_COUNT {
    s.actor_accumulators[slot] = s.actor_accumulators[slot] + payload;
    _event(s, _ev3("count", id, tag, payload));
    if tag == ACTOR_TAG_REVERT {
      let nv = _become_inner(s, slot, ACTOR_BEHAVIOR_ECHO);
    }
    if tag == ACTOR_TAG_SELF_STOP {
      _stop_actor(s, slot, "self");
    }
    return;
  }
  _event(s, _ev2("sink", id, tag));
}

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

/// Create an empty actor system: no actors, empty ready queue, empty
/// mailboxes, empty traces, zero counters.
/// Complexity: O(1).
pub fn actor_system_new() -> ActorSystem {
  return ActorSystem{
    actor_ids: Vec[Int].new();
    actor_priorities: Vec[Int].new();
    actor_orders: Vec[Int].new();
    actor_states: Vec[Int].new();
    actor_behaviors: Vec[Int].new();
    actor_spawn_behaviors: Vec[Int].new();
    actor_versions: Vec[Int].new();
    actor_capacities: Vec[Int].new();
    actor_overflows: Vec[Int].new();
    actor_supervisors: Vec[Int].new();
    actor_directives: Vec[Int].new();
    actor_restarts: Vec[Int].new();
    actor_processed: Vec[Int].new();
    actor_accumulators: Vec[Int].new();
    next_order: 0;
    ready_ids: Vec[Int].new();
    msg_ids: Vec[Int].new();
    msg_targets: Vec[Int].new();
    msg_senders: Vec[Int].new();
    msg_tags: Vec[Int].new();
    msg_payloads: Vec[Int].new();
    next_message_id: 0;
    mail_drained: 0;
    dead_ids: Vec[Int].new();
    dead_targets: Vec[Int].new();
    dead_senders: Vec[Int].new();
    dead_tags: Vec[Int].new();
    dead_payloads: Vec[Int].new();
    dead_reasons: Vec[Int].new();
    dispatch_order: Vec[Int].new();
    events: Vec[Str].new();
    proc_actors: Vec[Int].new();
    proc_tags: Vec[Int].new();
    proc_payloads: Vec[Int].new();
    messages_sent: 0;
    messages_processed: 0;
    steps: 0;
    total_restarts: 0;
    total_stops: 0;
    total_escalations: 0;
    total_crashes: 0;
  };
}

// ---------------------------------------------------------------------------
// Spawning
// ---------------------------------------------------------------------------

/// Spawn an actor in state IDLE with the given scheduling priority, mailbox
/// capacity (0 = unbounded), overflow policy and initial (spawn) behavior.
/// The actor becomes its own spawn behavior on every supervised restart.
/// Params: s - the system; id - caller-assigned actor id, unique, >= 0;
///         priority - scheduling priority, >= 0 (larger = more urgent);
///         capacity - mailbox capacity, 0 = unbounded;
///         overflow - ACTOR_OVERFLOW_DROP_NEW or ACTOR_OVERFLOW_DROP_OLDEST;
///         behavior - ACTOR_BEHAVIOR_ECHO, ACTOR_BEHAVIOR_COUNT or
///         ACTOR_BEHAVIOR_SINK.
/// Returns: Ok(creation order) (dense: 0, 1, 2, ...);
/// Err("actor: actor id must be >= 0"), Err("actor: priority must be >= 0"),
/// Err("actor: capacity must be >= 0"), Err("actor: unknown overflow
/// policy"), Err("actor: unknown behavior") or Err("actor: duplicate actor
/// id") -- in every Err case the state is unchanged.
/// Complexity: O(actor count).
pub fn actor_spawn(s: &mut ActorSystem, id: Int, priority: Int, capacity: Int, overflow: Int, behavior: Int) -> Result[Int, Str] {
  if id < 0 { return _err_int("actor: actor id must be >= 0"); }
  if priority < 0 { return _err_int("actor: priority must be >= 0"); }
  if capacity < 0 { return _err_int("actor: capacity must be >= 0"); }
  if !_valid_overflow(overflow) { return _err_int("actor: unknown overflow policy"); }
  if !_valid_behavior(behavior) { return _err_int("actor: unknown behavior"); }
  if _actor_slot(s, id) >= 0 { return _err_int("actor: duplicate actor id"); }
  let order = s.next_order;
  s.actor_ids.push(id);
  s.actor_priorities.push(priority);
  s.actor_orders.push(order);
  s.actor_states.push(ACTOR_IDLE);
  s.actor_behaviors.push(behavior);
  s.actor_spawn_behaviors.push(behavior);
  s.actor_versions.push(0);
  s.actor_capacities.push(capacity);
  s.actor_overflows.push(overflow);
  s.actor_supervisors.push(ACTOR_NO_SUPERVISOR);
  s.actor_directives.push(ACTOR_RESTART);
  s.actor_restarts.push(0);
  s.actor_processed.push(0);
  s.actor_accumulators.push(0);
  s.next_order = order + 1;
  _event(s, _ev2("spawn", id, behavior));
  return _ok_int(order);
}

// ---------------------------------------------------------------------------
// Messaging
// ---------------------------------------------------------------------------

/// Send a message to `target`. The message gets the next global sequence id.
/// A valid send to a live actor is enqueued (and an IDLE target is scheduled);
/// a send to an unknown, stopped or failed actor is routed to the dead
/// letters with the matching reason. When the target mailbox is full the
/// overflow policy decides: DROP_NEW dead-letters the new message (reason
/// ACTOR_DEAD_OVERFLOW), DROP_OLDEST evicts the oldest queued message to the
/// dead letters (reason ACTOR_DEAD_EVICTED) and then enqueues the new one.
/// Params: s - the system; target - recipient actor id, >= 0;
///         sender - sender actor id, or ACTOR_NO_SENDER (-1) for external;
///         tag - caller-defined message tag, >= 0; payload - any Int.
/// Returns: Ok(message sequence id) in every accepted case (dead-lettered
/// sends return the id of the dead-lettered message too);
/// Err("actor: target id must be >= 0"), Err("actor: sender id must be >=
/// -1"), Err("actor: tag must be >= 0") or Err("actor: unknown sender id") --
/// in every Err case the state is unchanged.
/// Complexity: O(queue length).
pub fn actor_send(s: &mut ActorSystem, target: Int, sender: Int, tag: Int, payload: Int) -> Result[Int, Str] {
  if target < 0 { return _err_int("actor: target id must be >= 0"); }
  if sender < ACTOR_NO_SENDER { return _err_int("actor: sender id must be >= -1"); }
  if tag < 0 { return _err_int("actor: tag must be >= 0"); }
  if sender >= 0 {
    if _actor_slot(s, sender) < 0 { return _err_int("actor: unknown sender id"); }
  }
  let seq = s.next_message_id;
  s.next_message_id = seq + 1;
  let tslot = _actor_slot(s, target);
  if tslot < 0 {
    _dead_letter_new(s, seq, target, sender, tag, payload, ACTOR_DEAD_UNKNOWN);
    return _ok_int(seq);
  }
  let st: Int = s.actor_states[tslot];
  if st == ACTOR_STOPPED {
    _dead_letter_new(s, seq, target, sender, tag, payload, ACTOR_DEAD_STOPPED);
    return _ok_int(seq);
  }
  if st == ACTOR_FAILED {
    _dead_letter_new(s, seq, target, sender, tag, payload, ACTOR_DEAD_FAILED);
    return _ok_int(seq);
  }
  let cap: Int = s.actor_capacities[tslot];
  if cap > 0 {
    if _mailbox_len(s, target) >= cap {
      let ov: Int = s.actor_overflows[tslot];
      if ov == ACTOR_OVERFLOW_DROP_NEW {
        _dead_letter_new(s, seq, target, sender, tag, payload, ACTOR_DEAD_OVERFLOW);
        return _ok_int(seq);
      }
      let head = _mailbox_head_index(s, target);
      _dead_letter_at(s, head, ACTOR_DEAD_EVICTED);
    }
  }
  _enqueue_msg(s, seq, target, sender, tag, payload);
  s.messages_sent = s.messages_sent + 1;
  if st == ACTOR_IDLE {
    _schedule(s, tslot);
  }
  return _ok_int(seq);
}

// ---------------------------------------------------------------------------
// Behavior switch
// ---------------------------------------------------------------------------

/// Switch an actor to a new behavior and bump its version (versioned state:
/// spawn and restart reset it to 0, every become increments it).
/// Params: s - the system; id - actor id; behavior - an ACTOR_BEHAVIOR_* code.
/// Returns: Ok(new version); Err("actor: unknown behavior"),
/// Err("actor: unknown actor id"), Err("actor: actor already stopped") or
/// Err("actor: actor already failed") -- in every Err case the state is
/// unchanged.
/// Complexity: O(actor count).
pub fn actor_become(s: &mut ActorSystem, id: Int, behavior: Int) -> Result[Int, Str] {
  if !_valid_behavior(behavior) { return _err_int("actor: unknown behavior"); }
  let slot = _actor_slot(s, id);
  if slot < 0 { return _err_int("actor: unknown actor id"); }
  let st: Int = s.actor_states[slot];
  if st == ACTOR_STOPPED { return _err_int("actor: actor already stopped"); }
  if st == ACTOR_FAILED { return _err_int("actor: actor already failed"); }
  let v = _become_inner(s, slot, behavior);
  return _ok_int(v);
}

// ---------------------------------------------------------------------------
// Supervision
// ---------------------------------------------------------------------------

/// Link `child` to `supervisor`: when `child` crashes, `supervisor`'s
/// directive decides what happens. Each child has at most one supervisor;
/// the link is refused when it would create a cycle (the supervision graph
/// is always a forest). The supervisor must be live (not stopped/failed).
/// Params: s - the system; child - child actor id; supervisor - supervisor
/// actor id.
/// Returns: Ok(supervisor); Err("actor: unknown child id"), Err("actor:
/// unknown supervisor id"), Err("actor: cannot supervise itself"),
/// Err("actor: actor already supervised"), Err("actor: supervisor is
/// stopped"), Err("actor: supervisor is failed") or Err("actor: supervision
/// cycle") -- in every Err case the state is unchanged.
/// Complexity: O(actor count^2) (cycle walk).
pub fn actor_supervise(s: &mut ActorSystem, child: Int, supervisor: Int) -> Result[Int, Str] {
  let cslot = _actor_slot(s, child);
  if cslot < 0 { return _err_int("actor: unknown child id"); }
  let sslot = _actor_slot(s, supervisor);
  if sslot < 0 { return _err_int("actor: unknown supervisor id"); }
  if child == supervisor { return _err_int("actor: cannot supervise itself"); }
  let sst: Int = s.actor_states[sslot];
  if sst == ACTOR_STOPPED { return _err_int("actor: supervisor is stopped"); }
  if sst == ACTOR_FAILED { return _err_int("actor: supervisor is failed"); }
  let cur: Int = s.actor_supervisors[cslot];
  if cur >= 0 { return _err_int("actor: actor already supervised"); }
  // Refuse the link when `child` is already on `supervisor`'s ancestor chain
  // (that is exactly when child -> supervisor would close a cycle). The walk
  // is bounded by the actor count even if the invariant is broken.
  var walk = sslot;
  var guard = 0;
  while walk >= 0 {
    if guard > s.actor_ids.len() { return _err_int("actor: supervision cycle"); }
    let wid: Int = s.actor_ids[walk];
    if wid == child { return _err_int("actor: supervision cycle"); }
    let sup: Int = s.actor_supervisors[walk];
    if sup < 0 { walk = -1; } else { walk = _actor_slot(s, sup); }
    guard = guard + 1;
  }
  s.actor_supervisors[cslot] = supervisor;
  return _ok_int(supervisor);
}

/// Set the supervision directive this actor applies when one of its children
/// crashes: ACTOR_RESTART, ACTOR_STOP or ACTOR_ESCALATE (default RESTART).
/// Params: s - the system; id - actor id acting as a supervisor;
///         directive - an ACTOR_* directive code.
/// Returns: Ok(directive); Err("actor: unknown directive") or
/// Err("actor: unknown actor id") -- in every Err case the state is
/// unchanged. The directive is accepted even for terminal actors (it only
/// matters while they supervise).
/// Complexity: O(actor count).
pub fn actor_set_supervise_policy(s: &mut ActorSystem, id: Int, directive: Int) -> Result[Int, Str] {
  if !_valid_directive(directive) { return _err_int("actor: unknown directive"); }
  let slot = _actor_slot(s, id);
  if slot < 0 { return _err_int("actor: unknown actor id"); }
  s.actor_directives[slot] = directive;
  return _ok_int(directive);
}

/// Crash an actor with `code` and apply its supervisor's directive:
/// RESTART resets behavior state (spawn behavior, version 0, accumulator 0),
/// increments the restart counters, keeps the mailbox and reschedules when
/// it is not empty; STOP stops the actor and dead-letters its mailbox
/// (reason ACTOR_DEAD_STOPPED); ESCALATE fails the actor permanently,
/// dead-letters its mailbox (reason ACTOR_DEAD_FAILED) and then crashes the
/// supervisor with the same code. An actor without a supervisor fails
/// permanently and dead-letters its mailbox.
/// Params: s - the system; id - actor id; code - caller-defined crash code.
/// Returns: Ok(code); Err("actor: unknown actor id"), Err("actor: actor
/// already stopped") or Err("actor: actor already failed").
/// Complexity: O(actor count^2) worst case (escalation chain).
pub fn actor_crash(s: &mut ActorSystem, id: Int, code: Int) -> Result[Int, Str] {
  let slot = _actor_slot(s, id);
  if slot < 0 { return _err_int("actor: unknown actor id"); }
  let st: Int = s.actor_states[slot];
  if st == ACTOR_STOPPED { return _err_int("actor: actor already stopped"); }
  if st == ACTOR_FAILED { return _err_int("actor: actor already failed"); }
  _crash_inner(s, slot, code);
  return _ok_int(code);
}

// ---------------------------------------------------------------------------
// Execution
// ---------------------------------------------------------------------------

/// Perform one deterministic step: select the next ready actor (largest
/// priority, FIFO within a level), remove it from the queue, mark it
/// RUNNING, consume its oldest queued message and run the behavior state
/// machine (the CRASH tag wins over the behavior). The actor then returns to
/// IDLE -- or is rescheduled immediately when its mailbox still has messages
/// -- unless the message stopped, failed or restarted it.
/// Params: s - the system.
/// Returns: Ok(actor id); Err("actor: no ready actors") when the queue is
/// empty.
/// Complexity: O(actor count + queue length).
pub fn actor_step(s: &mut ActorSystem) -> Result[Int, Str] {
  if s.ready_ids.len() == 0 { return _err_int("actor: no ready actors"); }
  let idx = _pick_index(s);
  let id: Int = s.ready_ids[idx];
  _queue_remove_at(s, idx);
  let slot = _actor_slot(s, id);
  if slot < 0 { return _err_int("actor: unknown actor id"); }
  s.actor_states[slot] = ACTOR_RUNNING;
  s.steps = s.steps + 1;
  s.dispatch_order.push(id);
  _event(s, _ev1("dispatch", id));
  let mi = _mailbox_head_index(s, id);
  if mi < 0 {
    // Unreachable when the invariant holds (SCHEDULED implies a non-empty
    // mailbox); fail closed and restore the actor.
    s.actor_states[slot] = ACTOR_IDLE;
    return _err_int("actor: mailbox is empty");
  }
  let tag: Int = s.msg_tags[mi];
  let payload: Int = s.msg_payloads[mi];
  _remove_message_at(s, mi);
  _process(s, slot, tag, payload);
  let st: Int = s.actor_states[slot];
  if st == ACTOR_RUNNING {
    s.actor_states[slot] = ACTOR_IDLE;
    if _mailbox_len(s, id) > 0 {
      _schedule(s, slot);
    }
  }
  return _ok_int(id);
}

/// Peek at the actor the next actor_step would dispatch (same selection
/// rule) without changing any state.
/// Params: s - the system.
/// Returns: Ok(actor id); Err("actor: no ready actors") when the queue is
/// empty.
/// Complexity: O(actor count + queue length).
pub fn actor_peek_next(s: &ActorSystem) -> Result[Int, Str] {
  if s.ready_ids.len() == 0 { return _err_int("actor: no ready actors"); }
  let idx = _pick_index(s);
  let id: Int = s.ready_ids[idx];
  return _ok_int(id);
}

/// Drive the system to quiescence: repeatedly dispatch and process messages
/// until the ready queue is empty (Ok) or the dispatch bound is reached
/// while work remains (Err). Every step consumes exactly one message, so the
/// number of iterations is bounded by the queued message count as well.
/// Params: s - the system; max_steps - dispatch bound, >= 0.
/// Returns: Ok(trace) with the actor ids dispatched by THIS run, in dispatch
/// order (empty when nothing was ready); Err("actor: max_steps must be
/// >= 0"); Err("actor: step limit exceeded") when the bound is reached while
/// the queue is still non-empty (states reached so far are retained, no
/// trace is returned).
/// Complexity: O(max_steps * (actor count + queue length)).
pub fn actor_run_all(s: &mut ActorSystem, max_steps: Int) -> Result[Vec[Int], Str] {
  if max_steps < 0 { return _err_vec("actor: max_steps must be >= 0"); }
  var trace = Vec[Int].new();
  var dispatched = 0;
  while true {
    if s.ready_ids.len() == 0 { return _ok_vec(trace); }
    if dispatched >= max_steps { return _err_vec("actor: step limit exceeded"); }
    let nxt = actor_step(s);
    match nxt {
      Ok(id) => { trace.push(id); },
      Err(m) => { return _err_vec(m); },
    }
    dispatched = dispatched + 1;
  }
  return _ok_vec(trace);
}

// ---------------------------------------------------------------------------
// Actor accessors (read-only)
// ---------------------------------------------------------------------------

/// Number of spawned actors. Complexity: O(1).
pub fn actor_count(s: &ActorSystem) -> Int {
  return s.actor_ids.len();
}

/// True when an actor with `id` exists. Complexity: O(actor count).
pub fn actor_has_actor(s: &ActorSystem, id: Int) -> Bool {
  return _actor_slot(s, id) >= 0;
}

/// State code of actor `id` (an ACTOR_* state), or ACTOR_NOT_FOUND (-1)
/// when unknown. Complexity: O(actor count).
pub fn actor_state(s: &ActorSystem, id: Int) -> Int {
  let slot = _actor_slot(s, id);
  if slot < 0 { return ACTOR_NOT_FOUND; }
  let st: Int = s.actor_states[slot];
  return st;
}

/// Current behavior code of actor `id` (an ACTOR_BEHAVIOR_*), or
/// ACTOR_NOT_FOUND (-1) when unknown. Complexity: O(actor count).
pub fn actor_behavior(s: &ActorSystem, id: Int) -> Int {
  let slot = _actor_slot(s, id);
  if slot < 0 { return ACTOR_NOT_FOUND; }
  let b: Int = s.actor_behaviors[slot];
  return b;
}

/// Behavior version of actor `id`: 0 at spawn and after a restart, +1 per
/// become. ACTOR_NOT_FOUND (-1) when unknown. Complexity: O(actor count).
pub fn actor_behavior_version(s: &ActorSystem, id: Int) -> Int {
  let slot = _actor_slot(s, id);
  if slot < 0 { return ACTOR_NOT_FOUND; }
  let v: Int = s.actor_versions[slot];
  return v;
}

/// Spawn behavior of actor `id` (the behavior a restart resets to), or
/// ACTOR_NOT_FOUND (-1) when unknown. Complexity: O(actor count).
pub fn actor_spawn_behavior(s: &ActorSystem, id: Int) -> Int {
  let slot = _actor_slot(s, id);
  if slot < 0 { return ACTOR_NOT_FOUND; }
  let b: Int = s.actor_spawn_behaviors[slot];
  return b;
}

/// Scheduling priority of actor `id`, or ACTOR_NOT_FOUND (-1) when unknown.
/// Complexity: O(actor count).
pub fn actor_priority(s: &ActorSystem, id: Int) -> Int {
  let slot = _actor_slot(s, id);
  if slot < 0 { return ACTOR_NOT_FOUND; }
  let p: Int = s.actor_priorities[slot];
  return p;
}

/// Mailbox capacity of actor `id` (0 = unbounded), or ACTOR_NOT_FOUND (-1)
/// when unknown. Complexity: O(actor count).
pub fn actor_capacity(s: &ActorSystem, id: Int) -> Int {
  let slot = _actor_slot(s, id);
  if slot < 0 { return ACTOR_NOT_FOUND; }
  let c: Int = s.actor_capacities[slot];
  return c;
}

/// Overflow policy of actor `id`, or ACTOR_NOT_FOUND (-1) when unknown.
/// Complexity: O(actor count).
pub fn actor_overflow(s: &ActorSystem, id: Int) -> Int {
  let slot = _actor_slot(s, id);
  if slot < 0 { return ACTOR_NOT_FOUND; }
  let o: Int = s.actor_overflows[slot];
  return o;
}

/// Supervisor id of actor `id` (ACTOR_NO_SUPERVISOR when none), or
/// ACTOR_NOT_FOUND (-1) when unknown. Complexity: O(actor count).
pub fn actor_supervisor(s: &ActorSystem, id: Int) -> Int {
  let slot = _actor_slot(s, id);
  if slot < 0 { return ACTOR_NOT_FOUND; }
  let sup: Int = s.actor_supervisors[slot];
  return sup;
}

/// Supervision directive actor `id` applies as a supervisor, or
/// ACTOR_NOT_FOUND (-1) when unknown. Complexity: O(actor count).
pub fn actor_directive(s: &ActorSystem, id: Int) -> Int {
  let slot = _actor_slot(s, id);
  if slot < 0 { return ACTOR_NOT_FOUND; }
  let d: Int = s.actor_directives[slot];
  return d;
}

/// Number of supervised restarts of actor `id`, or ACTOR_NOT_FOUND (-1)
/// when unknown. Complexity: O(actor count).
pub fn actor_restart_count(s: &ActorSystem, id: Int) -> Int {
  let slot = _actor_slot(s, id);
  if slot < 0 { return ACTOR_NOT_FOUND; }
  let r: Int = s.actor_restarts[slot];
  return r;
}

/// Number of messages consumed by actor `id`, or ACTOR_NOT_FOUND (-1) when
/// unknown. Complexity: O(actor count).
pub fn actor_processed_count(s: &ActorSystem, id: Int) -> Int {
  let slot = _actor_slot(s, id);
  if slot < 0 { return ACTOR_NOT_FOUND; }
  let p: Int = s.actor_processed[slot];
  return p;
}

/// Accumulator of actor `id` (COUNT behavior), or ACTOR_NOT_FOUND (-1) when
/// unknown. Complexity: O(actor count).
pub fn actor_accumulator(s: &ActorSystem, id: Int) -> Int {
  let slot = _actor_slot(s, id);
  if slot < 0 { return ACTOR_NOT_FOUND; }
  let a: Int = s.actor_accumulators[slot];
  return a;
}

/// Number of messages queued for actor `id`, or ACTOR_NOT_FOUND (-1) when
/// unknown. Complexity: O(queue length).
pub fn actor_mailbox_len(s: &ActorSystem, id: Int) -> Int {
  if _actor_slot(s, id) < 0 { return ACTOR_NOT_FOUND; }
  return _mailbox_len(s, id);
}

/// Copy of the queued tags for actor `id`, oldest first; empty for an
/// unknown actor. Complexity: O(queue length).
pub fn actor_mailbox_tags(s: &ActorSystem, id: Int) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 0;
  while i < s.msg_targets.len() {
    let t: Int = s.msg_targets[i];
    if t == id {
      let tg: Int = s.msg_tags[i];
      out.push(tg);
    }
    i = i + 1;
  }
  return out;
}

// ---------------------------------------------------------------------------
// Ready queue and system accessors (read-only)
// ---------------------------------------------------------------------------

/// Number of actors in the ready queue. Complexity: O(1).
pub fn actor_ready_len(s: &ActorSystem) -> Int {
  return s.ready_ids.len();
}

/// Copy of the ready-queue actor ids, front first (the dispatch order under
/// the priority rule may differ). Complexity: O(queue length).
pub fn actor_ready_ids(s: &ActorSystem) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 0;
  while i < s.ready_ids.len() {
    let id: Int = s.ready_ids[i];
    out.push(id);
    i = i + 1;
  }
  return out;
}

/// Successful actor_send enqueues (dead-lettered sends are not counted).
/// Complexity: O(1).
pub fn actor_messages_sent(s: &ActorSystem) -> Int {
  return s.messages_sent;
}

/// Messages consumed by actor_step (including messages that crashed their
/// receiver). Complexity: O(1).
pub fn actor_messages_processed(s: &ActorSystem) -> Int {
  return s.messages_processed;
}

/// Successful actor_step dispatches. Complexity: O(1).
pub fn actor_steps(s: &ActorSystem) -> Int {
  return s.steps;
}

/// Total supervised restarts. Complexity: O(1).
pub fn actor_restarts(s: &ActorSystem) -> Int {
  return s.total_restarts;
}

/// Total stops (self-stop and STOP directives). Complexity: O(1).
pub fn actor_stops(s: &ActorSystem) -> Int {
  return s.total_stops;
}

/// Total escalations. Complexity: O(1).
pub fn actor_escalations(s: &ActorSystem) -> Int {
  return s.total_escalations;
}

/// Total crashes (every _crash_inner transition, including escalated ones
/// and unhandled ones). Complexity: O(1).
pub fn actor_crashes(s: &ActorSystem) -> Int {
  return s.total_crashes;
}

// ---------------------------------------------------------------------------
// Traces, processed log and events (read-only)
// ---------------------------------------------------------------------------

/// Length of the global dispatch trace. Complexity: O(1).
pub fn actor_trace_len(s: &ActorSystem) -> Int {
  return s.dispatch_order.len();
}

/// Copy of the global dispatch trace: actor ids in dispatch order.
/// Complexity: O(trace length).
pub fn actor_trace(s: &ActorSystem) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 0;
  while i < s.dispatch_order.len() {
    let id: Int = s.dispatch_order[i];
    out.push(id);
    i = i + 1;
  }
  return out;
}

/// Dispatch trace rendered as comma-separated actor ids, "" when empty.
/// Complexity: O(trace length).
pub fn actor_trace_text(s: &ActorSystem) -> Str {
  var out = "";
  var i = 0;
  while i < s.dispatch_order.len() {
    let id: Int = s.dispatch_order[i];
    if i > 0 { out = out + ","; }
    out = out + convert.int_to_string(id);
    i = i + 1;
  }
  return out;
}

/// Number of consumed messages in the processed log. Complexity: O(1).
pub fn actor_processed_total(s: &ActorSystem) -> Int {
  return s.proc_actors.len();
}

/// Actor id of processed-log entry `i`, or ACTOR_NOT_FOUND (-1) when out of
/// range. Complexity: O(1).
pub fn actor_processed_actor(s: &ActorSystem, i: Int) -> Int {
  if i < 0 || i >= s.proc_actors.len() { return ACTOR_NOT_FOUND; }
  let v: Int = s.proc_actors[i];
  return v;
}

/// Tag of processed-log entry `i`, or ACTOR_NOT_FOUND (-1) when out of
/// range. Complexity: O(1).
pub fn actor_processed_tag(s: &ActorSystem, i: Int) -> Int {
  if i < 0 || i >= s.proc_tags.len() { return ACTOR_NOT_FOUND; }
  let v: Int = s.proc_tags[i];
  return v;
}

/// Payload of processed-log entry `i`, or ACTOR_NOT_FOUND (-1) when out of
/// range. Complexity: O(1).
pub fn actor_processed_payload(s: &ActorSystem, i: Int) -> Int {
  if i < 0 || i >= s.proc_payloads.len() { return ACTOR_NOT_FOUND; }
  let v: Int = s.proc_payloads[i];
  return v;
}

/// Processed log rendered as comma-separated "actor:tag" pairs, "" when
/// empty. Complexity: O(log length).
pub fn actor_processed_text(s: &ActorSystem) -> Str {
  var out = "";
  var i = 0;
  while i < s.proc_actors.len() {
    let a: Int = s.proc_actors[i];
    let t: Int = s.proc_tags[i];
    if i > 0 { out = out + ","; }
    out = out + convert.int_to_string(a) + ":" + convert.int_to_string(t);
    i = i + 1;
  }
  return out;
}

/// Number of event-log entries. Complexity: O(1).
pub fn actor_event_count(s: &ActorSystem) -> Int {
  return s.events.len();
}

/// Event-log entry `i`, or "" when out of range. Complexity: O(1).
pub fn actor_event_at(s: &ActorSystem, i: Int) -> Str {
  if i < 0 || i >= s.events.len() { return ""; }
  let e: Str = s.events[i];
  return e;
}

// ---------------------------------------------------------------------------
// Dead letters (read-only)
// ---------------------------------------------------------------------------

/// Number of dead-lettered messages. Complexity: O(1).
pub fn actor_dead_letter_count(s: &ActorSystem) -> Int {
  return s.dead_ids.len();
}

/// Sequence id of dead letter `i`, or ACTOR_NOT_FOUND (-1) when out of
/// range. Complexity: O(1).
pub fn actor_dead_letter_id(s: &ActorSystem, i: Int) -> Int {
  if i < 0 || i >= s.dead_ids.len() { return ACTOR_NOT_FOUND; }
  let v: Int = s.dead_ids[i];
  return v;
}

/// Intended target of dead letter `i`, or ACTOR_NOT_FOUND (-1) when out of
/// range. Complexity: O(1).
pub fn actor_dead_letter_target(s: &ActorSystem, i: Int) -> Int {
  if i < 0 || i >= s.dead_targets.len() { return ACTOR_NOT_FOUND; }
  let v: Int = s.dead_targets[i];
  return v;
}

/// Sender of dead letter `i`, or ACTOR_NOT_FOUND (-1) when out of range.
/// Complexity: O(1).
pub fn actor_dead_letter_sender(s: &ActorSystem, i: Int) -> Int {
  if i < 0 || i >= s.dead_senders.len() { return ACTOR_NOT_FOUND; }
  let v: Int = s.dead_senders[i];
  return v;
}

/// Tag of dead letter `i`, or ACTOR_NOT_FOUND (-1) when out of range.
/// Complexity: O(1).
pub fn actor_dead_letter_tag(s: &ActorSystem, i: Int) -> Int {
  if i < 0 || i >= s.dead_tags.len() { return ACTOR_NOT_FOUND; }
  let v: Int = s.dead_tags[i];
  return v;
}

/// Payload of dead letter `i`, or ACTOR_NOT_FOUND (-1) when out of range.
/// Complexity: O(1).
pub fn actor_dead_letter_payload(s: &ActorSystem, i: Int) -> Int {
  if i < 0 || i >= s.dead_payloads.len() { return ACTOR_NOT_FOUND; }
  let v: Int = s.dead_payloads[i];
  return v;
}

/// Reason code of dead letter `i` (an ACTOR_DEAD_* code), or
/// ACTOR_NOT_FOUND (-1) when out of range. Complexity: O(1).
pub fn actor_dead_letter_reason(s: &ActorSystem, i: Int) -> Int {
  if i < 0 || i >= s.dead_reasons.len() { return ACTOR_NOT_FOUND; }
  let v: Int = s.dead_reasons[i];
  return v;
}

// ---------------------------------------------------------------------------
// Names
// ---------------------------------------------------------------------------

/// Human-readable actor state name, or "unknown" for an unknown code.
/// Complexity: O(1).
pub fn actor_state_name(state: Int) -> Str {
  if state == ACTOR_IDLE { return "idle"; }
  if state == ACTOR_SCHEDULED { return "scheduled"; }
  if state == ACTOR_RUNNING { return "running"; }
  if state == ACTOR_STOPPED { return "stopped"; }
  if state == ACTOR_FAILED { return "failed"; }
  return "unknown";
}

/// Human-readable behavior name, or "unknown" for an unknown code.
/// Complexity: O(1).
pub fn actor_behavior_name(behavior: Int) -> Str {
  if behavior == ACTOR_BEHAVIOR_ECHO { return "echo"; }
  if behavior == ACTOR_BEHAVIOR_COUNT { return "count"; }
  if behavior == ACTOR_BEHAVIOR_SINK { return "sink"; }
  return "unknown";
}

/// Human-readable supervision directive name, or "unknown" for an unknown
/// code. Complexity: O(1).
pub fn actor_directive_name(directive: Int) -> Str {
  if directive == ACTOR_RESTART { return "restart"; }
  if directive == ACTOR_STOP { return "stop"; }
  if directive == ACTOR_ESCALATE { return "escalate"; }
  return "unknown";
}

/// Human-readable mailbox overflow policy name, or "unknown" for an unknown
/// code. Complexity: O(1).
pub fn actor_overflow_name(overflow: Int) -> Str {
  if overflow == ACTOR_OVERFLOW_DROP_NEW { return "drop-new"; }
  if overflow == ACTOR_OVERFLOW_DROP_OLDEST { return "drop-oldest"; }
  return "unknown";
}

/// Human-readable dead-letter reason name, or "unknown" for an unknown
/// code. Complexity: O(1).
pub fn actor_dead_reason_name(reason: Int) -> Str {
  if reason == ACTOR_DEAD_UNKNOWN { return "unknown-target"; }
  if reason == ACTOR_DEAD_STOPPED { return "stopped"; }
  if reason == ACTOR_DEAD_OVERFLOW { return "overflow"; }
  if reason == ACTOR_DEAD_EVICTED { return "evicted"; }
  if reason == ACTOR_DEAD_FAILED { return "failed"; }
  return "unknown";
}

// ---------------------------------------------------------------------------
// Structural invariant
// ---------------------------------------------------------------------------

/// Structural invariant of an actor system, true exactly when:
/// 1. all fourteen actor vectors have equal length n, next_order == n, and
///    actor_orders[i] == i;
/// 2. every actor id is >= 0 and unique; every priority is >= 0; every
///    capacity is >= 0; every state, behavior, spawn behavior, overflow and
///    directive code is valid; every restart/processed counter is >= 0;
///    every supervisor either is ACTOR_NO_SUPERVISOR or an existing actor
///    id different from the actor itself, and the supervision graph is
///    acyclic (no parent chain longer than n);
/// 3. every ready-queue entry names a SCHEDULED actor, with no duplicates,
///    and every SCHEDULED actor is queued exactly once with a non-empty
///    mailbox; no actor is observed RUNNING; every non-terminal actor with a
///    non-empty mailbox is SCHEDULED and every IDLE actor has an empty
///    mailbox;
/// 4. the five message vectors have equal length; every target exists and
///    is live (not STOPPED, not FAILED); every message sequence id is
///    strictly increasing along the queue; no mailbox exceeds its capacity
///    (when > 0);
/// 5. the six dead-letter vectors have equal length and every reason is an
///    ACTOR_DEAD_* code;
/// 6. the three processed-log vectors have equal length and
///    messages_processed equals their length and equals the sum of the
///    per-actor processed counters; steps equals dispatch_order length;
///    every sequence id (queued or dead-lettered) is < next_message_id;
///    messages_sent equals queued + processed + drained messages, and the
///    ids assigned by actor_send are dense (sent + never-enqueued dead
///    letters == next_message_id).
/// Complexity: O(n^2 + queue length^2).
pub fn actor_check_invariant(s: &ActorSystem) -> Bool {
  let n = s.actor_ids.len();
  if s.actor_priorities.len() != n { return false; }
  if s.actor_orders.len() != n { return false; }
  if s.actor_states.len() != n { return false; }
  if s.actor_behaviors.len() != n { return false; }
  if s.actor_spawn_behaviors.len() != n { return false; }
  if s.actor_versions.len() != n { return false; }
  if s.actor_capacities.len() != n { return false; }
  if s.actor_overflows.len() != n { return false; }
  if s.actor_supervisors.len() != n { return false; }
  if s.actor_directives.len() != n { return false; }
  if s.actor_restarts.len() != n { return false; }
  if s.actor_processed.len() != n { return false; }
  if s.actor_accumulators.len() != n { return false; }
  if s.next_order != n { return false; }
  var i = 0;
  while i < n {
    let id: Int = s.actor_ids[i];
    let pr: Int = s.actor_priorities[i];
    let ord: Int = s.actor_orders[i];
    let st: Int = s.actor_states[i];
    let b: Int = s.actor_behaviors[i];
    let sb: Int = s.actor_spawn_behaviors[i];
    let ver: Int = s.actor_versions[i];
    let cap: Int = s.actor_capacities[i];
    let ov: Int = s.actor_overflows[i];
    let sup: Int = s.actor_supervisors[i];
    let dir: Int = s.actor_directives[i];
    let rst: Int = s.actor_restarts[i];
    let pc: Int = s.actor_processed[i];
    if id < 0 { return false; }
    if pr < 0 { return false; }
    if ord != i { return false; }
    if !_valid_state(st) { return false; }
    if st == ACTOR_RUNNING { return false; }
    if !_valid_behavior(b) { return false; }
    if !_valid_behavior(sb) { return false; }
    if ver < 0 { return false; }
    if cap < 0 { return false; }
    if !_valid_overflow(ov) { return false; }
    if !_valid_directive(dir) { return false; }
    if rst < 0 { return false; }
    if pc < 0 { return false; }
    if sup >= 0 {
      if sup == id { return false; }
      if _actor_slot(s, sup) < 0 { return false; }
    }
    var j = i + 1;
    while j < n {
      let other: Int = s.actor_ids[j];
      if other == id { return false; }
      j = j + 1;
    }
    i = i + 1;
  }
  // Supervision acyclicity: every parent chain reaches -1 within n steps.
  var a = 0;
  while a < n {
    var walk = a;
    var step = 0;
    while walk >= 0 {
      if step > n { return false; }
      let sup: Int = s.actor_supervisors[walk];
      if sup < 0 { walk = -1; } else { walk = _actor_slot(s, sup); }
      step = step + 1;
    }
    a = a + 1;
  }
  // Ready queue: unique, SCHEDULED, non-empty mailbox.
  var r = 0;
  while r < s.ready_ids.len() {
    let rid: Int = s.ready_ids[r];
    let rslot = _actor_slot(s, rid);
    if rslot < 0 { return false; }
    let rst: Int = s.actor_states[rslot];
    if rst != ACTOR_SCHEDULED { return false; }
    if _mailbox_len(s, rid) == 0 { return false; }
    var r2 = r + 1;
    while r2 < s.ready_ids.len() {
      let other: Int = s.ready_ids[r2];
      if other == rid { return false; }
      r2 = r2 + 1;
    }
    r = r + 1;
  }
  // Every SCHEDULED actor is queued exactly once; IDLE actors have empty
  // mailboxes; terminal actors have empty mailboxes (no message may target
  // them, checked below).
  var k = 0;
  while k < n {
    let st: Int = s.actor_states[k];
    let idk: Int = s.actor_ids[k];
    let len = _mailbox_len(s, idk);
    if st == ACTOR_SCHEDULED {
      if !_queue_has(s, idk) { return false; }
    }
    if st == ACTOR_IDLE {
      if len != 0 { return false; }
    }
    if st == ACTOR_STOPPED {
      if len != 0 { return false; }
    }
    if st == ACTOR_FAILED {
      if len != 0 { return false; }
    }
    k = k + 1;
  }
  // Mailbox capacity per actor.
  var c = 0;
  while c < n {
    let capc: Int = s.actor_capacities[c];
    if capc > 0 {
      let idc: Int = s.actor_ids[c];
      if _mailbox_len(s, idc) > capc { return false; }
    }
    c = c + 1;
  }
  // Message vectors: equal length, live targets, strictly increasing ids.
  let nm = s.msg_ids.len();
  if s.msg_targets.len() != nm { return false; }
  if s.msg_senders.len() != nm { return false; }
  if s.msg_tags.len() != nm { return false; }
  if s.msg_payloads.len() != nm { return false; }
  var m = 0;
  while m < nm {
    let mid: Int = s.msg_ids[m];
    let mt: Int = s.msg_targets[m];
    if mid < 0 { return false; }
    if mid >= s.next_message_id { return false; }
    if m > 0 {
      let prev: Int = s.msg_ids[m - 1];
      if prev >= mid { return false; }
    }
    let tslot = _actor_slot(s, mt);
    if tslot < 0 { return false; }
    let mst: Int = s.actor_states[tslot];
    if mst == ACTOR_STOPPED { return false; }
    if mst == ACTOR_FAILED { return false; }
    m = m + 1;
  }
  // Dead letters: equal length, valid reasons, ids below next_message_id.
  let nd = s.dead_ids.len();
  if s.dead_targets.len() != nd { return false; }
  if s.dead_senders.len() != nd { return false; }
  if s.dead_tags.len() != nd { return false; }
  if s.dead_payloads.len() != nd { return false; }
  if s.dead_reasons.len() != nd { return false; }
  var d = 0;
  while d < nd {
    let did: Int = s.dead_ids[d];
    let dr: Int = s.dead_reasons[d];
    if did < 0 { return false; }
    if did >= s.next_message_id { return false; }
    if dr < ACTOR_DEAD_UNKNOWN { return false; }
    if dr > ACTOR_DEAD_FAILED { return false; }
    d = d + 1;
  }
  // Processed log and counters.
  let np = s.proc_actors.len();
  if s.proc_tags.len() != np { return false; }
  if s.proc_payloads.len() != np { return false; }
  if s.messages_processed != np { return false; }
  if s.steps != s.dispatch_order.len() { return false; }
  var sum = 0;
  var p = 0;
  while p < n {
    let pc: Int = s.actor_processed[p];
    sum = sum + pc;
    p = p + 1;
  }
  if sum != np { return false; }
  // Conservation: every sequence id assigned by actor_send is currently
  // queued, dead-lettered, consumed by a step, or drained from a mailbox;
  // ids are assigned densely from 0, so messages_sent plus the number of
  // sends that were dead-lettered without ever being enqueued equals
  // next_message_id.
  if s.messages_sent + (s.dead_ids.len() - s.mail_drained) != s.next_message_id { return false; }
  if s.messages_sent != nm + s.messages_processed + s.mail_drained { return false; }
  return true;
}
