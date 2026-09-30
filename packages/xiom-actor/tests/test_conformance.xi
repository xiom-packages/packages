// XIOM -- xiom.actor conformance tests (28 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Fixture-driven deterministic tests of the documented API: spawning and
// metadata, sending and scheduling, mailbox FIFO order and overflow
// (DROP_NEW / DROP_OLDEST), become with versioned state, the COUNT/ECHO/SINK
// behaviors, supervision links with RESTART/STOP/ESCALATE, dead-letter
// routing, the step-driven driver with traces and stats, accessor bounds,
// name helpers and the structural invariant.
//
// All Str equality goes through str_compare: `==` on Str values read from
// Vec[Str] elements lowers to a pointer comparison, so every text check
// below is routed through streq. Vec[Int] element reads use a typed `let`.
// Read-only operations are wrapped in small helpers that take `&mut`, so a
// `&local` read call is never followed by a `&mut local` call in the same
// function body (advisory E001); each helper calls the real `&`-based API.
// Action helpers turn Result outcomes into small Int codes so test bodies
// stay branch-free.

module actor_tests
use xiom.io; use xiom.test; use xiom.actor;
use xiom.string.compare;

const _E_NO_READY: Str = "actor: no ready actors";
const _E_MAXSTEPS: Str = "actor: max_steps must be >= 0";
const _E_LIMIT: Str = "actor: step limit exceeded";
const _E_TARGET: Str = "actor: target id must be >= 0";
const _E_SENDER: Str = "actor: sender id must be >= -1";
const _E_TAG: Str = "actor: tag must be >= 0";
const _E_UNKNOWN_SENDER: Str = "actor: unknown sender id";
const _E_ID: Str = "actor: actor id must be >= 0";
const _E_PRIO: Str = "actor: priority must be >= 0";
const _E_CAP: Str = "actor: capacity must be >= 0";
const _E_OVERFLOW: Str = "actor: unknown overflow policy";
const _E_BEHAVIOR: Str = "actor: unknown behavior";
const _E_DUP: Str = "actor: duplicate actor id";
const _E_UNKNOWN_ACTOR: Str = "actor: unknown actor id";
const _E_STOPPED: Str = "actor: actor already stopped";
const _E_FAILED: Str = "actor: actor already failed";
const _E_SELF: Str = "actor: cannot supervise itself";
const _E_ALREADY_SUPERVISED: Str = "actor: actor already supervised";
const _E_CHILD: Str = "actor: unknown child id";
const _E_SUPERVISOR: Str = "actor: unknown supervisor id";
const _E_CYCLE: Str = "actor: supervision cycle";
const _E_DIRECTIVE: Str = "actor: unknown directive";

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn sys() -> ActorSystem {
  return actor_system_new();
}

// Read-only accessors routed through `&mut` (advisory E001).

fn count_of(e: &mut ActorSystem) -> Int { return actor_count(e); }
fn has_of(e: &mut ActorSystem, id: Int) -> Bool { return actor_has_actor(e, id); }
fn state_of(e: &mut ActorSystem, id: Int) -> Int { return actor_state(e, id); }
fn beh_of(e: &mut ActorSystem, id: Int) -> Int { return actor_behavior(e, id); }
fn ver_of(e: &mut ActorSystem, id: Int) -> Int { return actor_behavior_version(e, id); }
fn spawn_beh_of(e: &mut ActorSystem, id: Int) -> Int { return actor_spawn_behavior(e, id); }
fn prio_of(e: &mut ActorSystem, id: Int) -> Int { return actor_priority(e, id); }
fn cap_of(e: &mut ActorSystem, id: Int) -> Int { return actor_capacity(e, id); }
fn ov_of(e: &mut ActorSystem, id: Int) -> Int { return actor_overflow(e, id); }
fn sup_of(e: &mut ActorSystem, id: Int) -> Int { return actor_supervisor(e, id); }
fn dir_of(e: &mut ActorSystem, id: Int) -> Int { return actor_directive(e, id); }
fn restarts_of(e: &mut ActorSystem, id: Int) -> Int { return actor_restart_count(e, id); }
fn proc_of(e: &mut ActorSystem, id: Int) -> Int { return actor_processed_count(e, id); }
fn acc_of(e: &mut ActorSystem, id: Int) -> Int { return actor_accumulator(e, id); }
fn mbox_of(e: &mut ActorSystem, id: Int) -> Int { return actor_mailbox_len(e, id); }
fn mbox_tags_of(e: &mut ActorSystem, id: Int) -> Vec[Int] { return actor_mailbox_tags(e, id); }
fn ready_len_of(e: &mut ActorSystem) -> Int { return actor_ready_len(e); }
fn ready_ids_of(e: &mut ActorSystem) -> Vec[Int] { return actor_ready_ids(e); }
fn sent_of(e: &mut ActorSystem) -> Int { return actor_messages_sent(e); }
fn processed_of(e: &mut ActorSystem) -> Int { return actor_messages_processed(e); }
fn steps_of(e: &mut ActorSystem) -> Int { return actor_steps(e); }
fn restarts_total_of(e: &mut ActorSystem) -> Int { return actor_restarts(e); }
fn stops_of(e: &mut ActorSystem) -> Int { return actor_stops(e); }
fn escalations_of(e: &mut ActorSystem) -> Int { return actor_escalations(e); }
fn crashes_of(e: &mut ActorSystem) -> Int { return actor_crashes(e); }
fn trace_len_of(e: &mut ActorSystem) -> Int { return actor_trace_len(e); }
fn trace_of(e: &mut ActorSystem) -> Vec[Int] { return actor_trace(e); }
fn trace_text_of(e: &mut ActorSystem) -> Str { return actor_trace_text(e); }
fn proc_total_of(e: &mut ActorSystem) -> Int { return actor_processed_total(e); }
fn proc_actor_of(e: &mut ActorSystem, i: Int) -> Int { return actor_processed_actor(e, i); }
fn proc_tag_of(e: &mut ActorSystem, i: Int) -> Int { return actor_processed_tag(e, i); }
fn proc_payload_of(e: &mut ActorSystem, i: Int) -> Int { return actor_processed_payload(e, i); }
fn proc_text_of(e: &mut ActorSystem) -> Str { return actor_processed_text(e); }
fn event_count_of(e: &mut ActorSystem) -> Int { return actor_event_count(e); }
fn event_at_of(e: &mut ActorSystem, i: Int) -> Str { return actor_event_at(e, i); }
fn dead_count_of(e: &mut ActorSystem) -> Int { return actor_dead_letter_count(e); }
fn dead_id_of(e: &mut ActorSystem, i: Int) -> Int { return actor_dead_letter_id(e, i); }
fn dead_target_of(e: &mut ActorSystem, i: Int) -> Int { return actor_dead_letter_target(e, i); }
fn dead_sender_of(e: &mut ActorSystem, i: Int) -> Int { return actor_dead_letter_sender(e, i); }
fn dead_tag_of(e: &mut ActorSystem, i: Int) -> Int { return actor_dead_letter_tag(e, i); }
fn dead_payload_of(e: &mut ActorSystem, i: Int) -> Int { return actor_dead_letter_payload(e, i); }
fn dead_reason_of(e: &mut ActorSystem, i: Int) -> Int { return actor_dead_letter_reason(e, i); }
fn invariant_of(e: &mut ActorSystem) -> Bool { return actor_check_invariant(e); }

fn has_event(e: &mut ActorSystem, want: Str) -> Bool {
  var found = false;
  var i = 0;
  while i < event_count_of(e) {
    let ev: Str = event_at_of(e, i);
    if streq(ev, want) { found = true; }
    i = i + 1;
  }
  return found;
}

// Outcome classifiers: Int codes keep the tests readable.

// Creation order on success, -1 on any error.
fn spawn_ok(e: &mut ActorSystem, id: Int, prio: Int, cap: Int, ov: Int, beh: Int) -> Int {
  match actor_spawn(e, id, prio, cap, ov, beh) {
    Ok(order) => { return order; },
    Err(_) => { return -1; },
  }
  return -1;
}

fn spawn_err_is(e: &mut ActorSystem, id: Int, prio: Int, cap: Int, ov: Int, beh: Int, want: Str) -> Bool {
  match actor_spawn(e, id, prio, cap, ov, beh) {
    Ok(_) => { return false; },
    Err(m) => { return streq(m, want); },
  }
  return false;
}

// Message sequence id on success, -1 on any error.
fn send_seq(e: &mut ActorSystem, target: Int, sender: Int, tag: Int, payload: Int) -> Int {
  match actor_send(e, target, sender, tag, payload) {
    Ok(seq) => { return seq; },
    Err(_) => { return -1; },
  }
  return -1;
}

fn send_err_is(e: &mut ActorSystem, target: Int, sender: Int, tag: Int, payload: Int, want: Str) -> Bool {
  match actor_send(e, target, sender, tag, payload) {
    Ok(_) => { return false; },
    Err(m) => { return streq(m, want); },
  }
  return false;
}

// New behavior version on success, -1 on any error.
fn become_ok(e: &mut ActorSystem, id: Int, beh: Int) -> Int {
  match actor_become(e, id, beh) {
    Ok(v) => { return v; },
    Err(_) => { return -1; },
  }
  return -1;
}

fn become_err_is(e: &mut ActorSystem, id: Int, beh: Int, want: Str) -> Bool {
  match actor_become(e, id, beh) {
    Ok(_) => { return false; },
    Err(m) => { return streq(m, want); },
  }
  return false;
}

// Supervisor id on success, -1 on any error.
fn sup_ok(e: &mut ActorSystem, child: Int, sup: Int) -> Int {
  match actor_supervise(e, child, sup) {
    Ok(v) => { return v; },
    Err(_) => { return -1; },
  }
  return -1;
}

fn sup_err_is(e: &mut ActorSystem, child: Int, sup: Int, want: Str) -> Bool {
  match actor_supervise(e, child, sup) {
    Ok(_) => { return false; },
    Err(m) => { return streq(m, want); },
  }
  return false;
}

// Directive on success, -1 on any error.
fn policy_ok(e: &mut ActorSystem, id: Int, d: Int) -> Int {
  match actor_set_supervise_policy(e, id, d) {
    Ok(v) => { return v; },
    Err(_) => { return -1; },
  }
  return -1;
}

fn policy_err_is(e: &mut ActorSystem, id: Int, d: Int, want: Str) -> Bool {
  match actor_set_supervise_policy(e, id, d) {
    Ok(_) => { return false; },
    Err(m) => { return streq(m, want); },
  }
  return false;
}

// Crash code on success, -1 on any error.
fn crash_ok(e: &mut ActorSystem, id: Int, code: Int) -> Int {
  match actor_crash(e, id, code) {
    Ok(v) => { return v; },
    Err(_) => { return -1; },
  }
  return -1;
}

fn crash_err_is(e: &mut ActorSystem, id: Int, code: Int, want: Str) -> Bool {
  match actor_crash(e, id, code) {
    Ok(_) => { return false; },
    Err(m) => { return streq(m, want); },
  }
  return false;
}

// Dispatched actor id, -1 on any error.
fn step_id(e: &mut ActorSystem) -> Int {
  match actor_step(e) {
    Ok(id) => { return id; },
    Err(_) => { return -1; },
  }
  return -1;
}

fn step_err_is(e: &mut ActorSystem, want: Str) -> Bool {
  match actor_step(e) {
    Ok(_) => { return false; },
    Err(m) => { return streq(m, want); },
  }
  return false;
}

// Peeked actor id, -1 on any error.
fn peek_id(e: &mut ActorSystem) -> Int {
  match actor_peek_next(e) {
    Ok(id) => { return id; },
    Err(_) => { return -1; },
  }
  return -1;
}

fn peek_err_is(e: &mut ActorSystem, want: Str) -> Bool {
  match actor_peek_next(e) {
    Ok(_) => { return false; },
    Err(m) => { return streq(m, want); },
  }
  return false;
}

// Number of actors dispatched by this run, -1 on any error.
fn run_len(e: &mut ActorSystem, max_steps: Int) -> Int {
  match actor_run_all(e, max_steps) {
    Ok(trace) => { return trace.len(); },
    Err(_) => { return -1; },
  }
  return -1;
}

fn run_err_is(e: &mut ActorSystem, max_steps: Int, want: Str) -> Bool {
  match actor_run_all(e, max_steps) {
    Ok(_) => { return false; },
    Err(m) => { return streq(m, want); },
  }
  return false;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

fn t1() -> TestResult {
  var s = sys();
  var ok = count_of(&mut s) == 0;
  if ready_len_of(&mut s) != 0 { ok = false; }
  if steps_of(&mut s) != 0 { ok = false; }
  if trace_len_of(&mut s) != 0 { ok = false; }
  if dead_count_of(&mut s) != 0 { ok = false; }
  if proc_total_of(&mut s) != 0 { ok = false; }
  if event_count_of(&mut s) != 0 { ok = false; }
  if !step_err_is(&mut s, _E_NO_READY) { ok = false; }
  if !peek_err_is(&mut s, _E_NO_READY) { ok = false; }
  if run_len(&mut s, 0) != 0 { ok = false; }
  if !invariant_of(&mut s) { ok = false; }
  return assert(ok, "an empty system has empty traces and refuses to step");
}

fn t2() -> TestResult {
  var s = sys();
  var ok = spawn_ok(&mut s, 1, 2, 4, ACTOR_OVERFLOW_DROP_NEW, ACTOR_BEHAVIOR_ECHO) == 0;
  if count_of(&mut s) != 1 { ok = false; }
  if !has_of(&mut s, 1) { ok = false; }
  if state_of(&mut s, 1) != ACTOR_IDLE { ok = false; }
  if prio_of(&mut s, 1) != 2 { ok = false; }
  if cap_of(&mut s, 1) != 4 { ok = false; }
  if ov_of(&mut s, 1) != ACTOR_OVERFLOW_DROP_NEW { ok = false; }
  if beh_of(&mut s, 1) != ACTOR_BEHAVIOR_ECHO { ok = false; }
  if spawn_beh_of(&mut s, 1) != ACTOR_BEHAVIOR_ECHO { ok = false; }
  if ver_of(&mut s, 1) != 0 { ok = false; }
  if sup_of(&mut s, 1) != ACTOR_NO_SUPERVISOR { ok = false; }
  if dir_of(&mut s, 1) != ACTOR_RESTART { ok = false; }
  if restarts_of(&mut s, 1) != 0 { ok = false; }
  if !spawn_err_is(&mut s, 1, 0, 0, ACTOR_OVERFLOW_DROP_NEW, ACTOR_BEHAVIOR_ECHO, _E_DUP) { ok = false; }
  if !spawn_err_is(&mut s, -1, 0, 0, ACTOR_OVERFLOW_DROP_NEW, ACTOR_BEHAVIOR_ECHO, _E_ID) { ok = false; }
  if !spawn_err_is(&mut s, 2, -1, 0, ACTOR_OVERFLOW_DROP_NEW, ACTOR_BEHAVIOR_ECHO, _E_PRIO) { ok = false; }
  if !spawn_err_is(&mut s, 2, 0, -1, ACTOR_OVERFLOW_DROP_NEW, ACTOR_BEHAVIOR_ECHO, _E_CAP) { ok = false; }
  if !spawn_err_is(&mut s, 2, 0, 0, 9, ACTOR_BEHAVIOR_ECHO, _E_OVERFLOW) { ok = false; }
  if !spawn_err_is(&mut s, 2, 0, 0, ACTOR_OVERFLOW_DROP_NEW, 9, _E_BEHAVIOR) { ok = false; }
  if count_of(&mut s) != 1 { ok = false; }
  if has_of(&mut s, 2) { ok = false; }
  if !invariant_of(&mut s) { ok = false; }
  return assert(ok, "spawn validates its inputs and records actor metadata");
}

fn t3() -> TestResult {
  var s = sys();
  var ok = spawn_ok(&mut s, 1, 0, 4, ACTOR_OVERFLOW_DROP_NEW, ACTOR_BEHAVIOR_ECHO) == 0;
  if send_seq(&mut s, 1, -1, 5, 7) != 0 { ok = false; }
  if state_of(&mut s, 1) != ACTOR_SCHEDULED { ok = false; }
  if ready_len_of(&mut s) != 1 { ok = false; }
  if mbox_of(&mut s, 1) != 1 { ok = false; }
  if sent_of(&mut s) != 1 { ok = false; }
  if dead_count_of(&mut s) != 0 { ok = false; }
  if step_id(&mut s) != 1 { ok = false; }
  if steps_of(&mut s) != 1 { ok = false; }
  if processed_of(&mut s) != 1 { ok = false; }
  if proc_of(&mut s, 1) != 1 { ok = false; }
  if proc_actor_of(&mut s, 0) != 1 { ok = false; }
  if proc_tag_of(&mut s, 0) != 5 { ok = false; }
  if proc_payload_of(&mut s, 0) != 7 { ok = false; }
  if state_of(&mut s, 1) != ACTOR_IDLE { ok = false; }
  if ready_len_of(&mut s) != 0 { ok = false; }
  if mbox_of(&mut s, 1) != 0 { ok = false; }
  if !streq(proc_text_of(&mut s), "1:5") { ok = false; }
  if !streq(trace_text_of(&mut s), "1") { ok = false; }
  if !step_err_is(&mut s, _E_NO_READY) { ok = false; }
  if !invariant_of(&mut s) { ok = false; }
  return assert(ok, "a send schedules the target and a step consumes the message");
}

fn t4() -> TestResult {
  var s = sys();
  var ok = spawn_ok(&mut s, 1, 0, 0, ACTOR_OVERFLOW_DROP_NEW, ACTOR_BEHAVIOR_ECHO) == 0;
  if send_seq(&mut s, 1, -1, 10, 0) != 0 { ok = false; }
  if send_seq(&mut s, 1, -1, 11, 0) != 1 { ok = false; }
  if send_seq(&mut s, 1, -1, 12, 0) != 2 { ok = false; }
  if ready_len_of(&mut s) != 1 { ok = false; }
  if mbox_of(&mut s, 1) != 3 { ok = false; }
  if step_id(&mut s) != 1 { ok = false; }
  if step_id(&mut s) != 1 { ok = false; }
  if step_id(&mut s) != 1 { ok = false; }
  if steps_of(&mut s) != 3 { ok = false; }
  if proc_total_of(&mut s) != 3 { ok = false; }
  if proc_tag_of(&mut s, 0) != 10 { ok = false; }
  if proc_tag_of(&mut s, 1) != 11 { ok = false; }
  if proc_tag_of(&mut s, 2) != 12 { ok = false; }
  if mbox_of(&mut s, 1) != 0 { ok = false; }
  if !invariant_of(&mut s) { ok = false; }
  return assert(ok, "one mailbox is a FIFO: messages are consumed oldest first");
}

fn t5() -> TestResult {
  var s = sys();
  var ok = spawn_ok(&mut s, 1, 0, 0, ACTOR_OVERFLOW_DROP_NEW, ACTOR_BEHAVIOR_ECHO) == 0;
  if send_seq(&mut s, 1, -1, ACTOR_TAG_BECOME, 0) != 0 { ok = false; }
  if step_id(&mut s) != 1 { ok = false; }
  if beh_of(&mut s, 1) != ACTOR_BEHAVIOR_COUNT { ok = false; }
  if ver_of(&mut s, 1) != 1 { ok = false; }
  if spawn_beh_of(&mut s, 1) != ACTOR_BEHAVIOR_ECHO { ok = false; }
  if event_count_of(&mut s) != 4 { ok = false; }
  if !streq(event_at_of(&mut s, 0), "spawn:1:0") { ok = false; }
  if !streq(event_at_of(&mut s, 1), "dispatch:1") { ok = false; }
  if !streq(event_at_of(&mut s, 2), "echo:1:100:0") { ok = false; }
  if !streq(event_at_of(&mut s, 3), "become:1:1:1") { ok = false; }
  if !invariant_of(&mut s) { ok = false; }
  return assert(ok, "an ECHO actor becomes COUNT at the threshold tag and logs it");
}

fn t6() -> TestResult {
  var s = sys();
  var ok = spawn_ok(&mut s, 1, 0, 0, ACTOR_OVERFLOW_DROP_NEW, ACTOR_BEHAVIOR_ECHO) == 0;
  if become_ok(&mut s, 1, ACTOR_BEHAVIOR_SINK) != 1 { ok = false; }
  if beh_of(&mut s, 1) != ACTOR_BEHAVIOR_SINK { ok = false; }
  if ver_of(&mut s, 1) != 1 { ok = false; }
  if become_ok(&mut s, 1, ACTOR_BEHAVIOR_ECHO) != 2 { ok = false; }
  if ver_of(&mut s, 1) != 2 { ok = false; }
  if !become_err_is(&mut s, 1, 9, _E_BEHAVIOR) { ok = false; }
  if !become_err_is(&mut s, 99, ACTOR_BEHAVIOR_ECHO, _E_UNKNOWN_ACTOR) { ok = false; }
  if spawn_ok(&mut s, 2, 0, 0, ACTOR_OVERFLOW_DROP_NEW, ACTOR_BEHAVIOR_COUNT) != 1 { ok = false; }
  if send_seq(&mut s, 2, -1, ACTOR_TAG_SELF_STOP, 0) != 0 { ok = false; }
  if step_id(&mut s) != 2 { ok = false; }
  if state_of(&mut s, 2) != ACTOR_STOPPED { ok = false; }
  if !become_err_is(&mut s, 2, ACTOR_BEHAVIOR_ECHO, _E_STOPPED) { ok = false; }
  if spawn_ok(&mut s, 3, 0, 0, ACTOR_OVERFLOW_DROP_NEW, ACTOR_BEHAVIOR_ECHO) != 2 { ok = false; }
  if crash_ok(&mut s, 3, 5) != 5 { ok = false; }
  if state_of(&mut s, 3) != ACTOR_FAILED { ok = false; }
  if !become_err_is(&mut s, 3, ACTOR_BEHAVIOR_ECHO, _E_FAILED) { ok = false; }
  if !invariant_of(&mut s) { ok = false; }
  return assert(ok, "become bumps versions and refuses invalid or terminal actors");
}

fn t7() -> TestResult {
  var s = sys();
  var ok = spawn_ok(&mut s, 1, 0, 0, ACTOR_OVERFLOW_DROP_NEW, ACTOR_BEHAVIOR_COUNT) == 0;
  if send_seq(&mut s, 1, -1, 5, 3) != 0 { ok = false; }
  if send_seq(&mut s, 1, -1, ACTOR_TAG_REVERT, 4) != 1 { ok = false; }
  if send_seq(&mut s, 1, -1, 7, 2) != 2 { ok = false; }
  if step_id(&mut s) != 1 { ok = false; }
  if step_id(&mut s) != 1 { ok = false; }
  if step_id(&mut s) != 1 { ok = false; }
  if acc_of(&mut s, 1) != 7 { ok = false; }
  if beh_of(&mut s, 1) != ACTOR_BEHAVIOR_ECHO { ok = false; }
  if ver_of(&mut s, 1) != 1 { ok = false; }
  if !invariant_of(&mut s) { ok = false; }
  return assert(ok, "COUNT accumulates payloads and reverts to ECHO on the revert tag");
}

fn t8() -> TestResult {
  var s = sys();
  var ok = spawn_ok(&mut s, 1, 0, 0, ACTOR_OVERFLOW_DROP_NEW, ACTOR_BEHAVIOR_COUNT) == 0;
  if send_seq(&mut s, 1, -1, ACTOR_TAG_SELF_STOP, 0) != 0 { ok = false; }
  if step_id(&mut s) != 1 { ok = false; }
  if state_of(&mut s, 1) != ACTOR_STOPPED { ok = false; }
  if stops_of(&mut s) != 1 { ok = false; }
  if mbox_of(&mut s, 1) != 0 { ok = false; }
  if send_seq(&mut s, 1, -1, 5, 0) != 1 { ok = false; }
  if dead_count_of(&mut s) != 1 { ok = false; }
  if dead_reason_of(&mut s, 0) != ACTOR_DEAD_STOPPED { ok = false; }
  if !invariant_of(&mut s) { ok = false; }
  return assert(ok, "the self-stop tag stops the actor and later sends dead-letter");
}

fn t9() -> TestResult {
  var s = sys();
  var ok = spawn_ok(&mut s, 1, 1, 0, ACTOR_OVERFLOW_DROP_NEW, ACTOR_BEHAVIOR_ECHO) == 0;
  if spawn_ok(&mut s, 2, 5, 0, ACTOR_OVERFLOW_DROP_NEW, ACTOR_BEHAVIOR_ECHO) != 1 { ok = false; }
  if spawn_ok(&mut s, 3, 5, 0, ACTOR_OVERFLOW_DROP_NEW, ACTOR_BEHAVIOR_ECHO) != 2 { ok = false; }
  if send_seq(&mut s, 1, -1, 1, 0) != 0 { ok = false; }
  if send_seq(&mut s, 2, -1, 2, 0) != 1 { ok = false; }
  if send_seq(&mut s, 3, -1, 3, 0) != 2 { ok = false; }
  if ready_len_of(&mut s) != 3 { ok = false; }
  if peek_id(&mut s) != 2 { ok = false; }
  if step_id(&mut s) != 2 { ok = false; }
  if step_id(&mut s) != 3 { ok = false; }
  if step_id(&mut s) != 1 { ok = false; }
  if !streq(trace_text_of(&mut s), "2,3,1") { ok = false; }
  if !invariant_of(&mut s) { ok = false; }
  return assert(ok, "selection takes the largest priority with FIFO tie-breaking");
}

fn t10() -> TestResult {
  var s = sys();
  var ok = spawn_ok(&mut s, 1, 0, 0, ACTOR_OVERFLOW_DROP_NEW, ACTOR_BEHAVIOR_ECHO) == 0;
  if spawn_ok(&mut s, 2, 0, 0, ACTOR_OVERFLOW_DROP_NEW, ACTOR_BEHAVIOR_ECHO) != 1 { ok = false; }
  if send_seq(&mut s, 1, -1, 1, 0) != 0 { ok = false; }
  if send_seq(&mut s, 2, -1, 2, 0) != 1 { ok = false; }
  var ids = ready_ids_of(&mut s);
  if ids.len() != 2 { ok = false; }
  let first: Int = ids[0];
  let second: Int = ids[1];
  if first != 1 { ok = false; }
  if second != 2 { ok = false; }
  ids.push(99);
  if ready_len_of(&mut s) != 2 { ok = false; }
  if !invariant_of(&mut s) { ok = false; }
  return assert(ok, "the ready-queue snapshot is a copy, not a view");
}

fn t11() -> TestResult {
  var s = sys();
  var ok = spawn_ok(&mut s, 1, 0, 2, ACTOR_OVERFLOW_DROP_NEW, ACTOR_BEHAVIOR_ECHO) == 0;
  if send_seq(&mut s, 1, -1, 1, 0) != 0 { ok = false; }
  if send_seq(&mut s, 1, -1, 2, 0) != 1 { ok = false; }
  if send_seq(&mut s, 1, -1, 3, 0) != 2 { ok = false; }
  if mbox_of(&mut s, 1) != 2 { ok = false; }
  if sent_of(&mut s) != 2 { ok = false; }
  if dead_count_of(&mut s) != 1 { ok = false; }
  if dead_id_of(&mut s, 0) != 2 { ok = false; }
  if dead_target_of(&mut s, 0) != 1 { ok = false; }
  if dead_tag_of(&mut s, 0) != 3 { ok = false; }
  if dead_reason_of(&mut s, 0) != ACTOR_DEAD_OVERFLOW { ok = false; }
  if step_id(&mut s) != 1 { ok = false; }
  if step_id(&mut s) != 1 { ok = false; }
  if proc_tag_of(&mut s, 0) != 1 { ok = false; }
  if proc_tag_of(&mut s, 1) != 2 { ok = false; }
  if !invariant_of(&mut s) { ok = false; }
  return assert(ok, "DROP_NEW dead-letters the arriving message when the mailbox is full");
}

fn t12() -> TestResult {
  var s = sys();
  var ok = spawn_ok(&mut s, 1, 0, 2, ACTOR_OVERFLOW_DROP_OLDEST, ACTOR_BEHAVIOR_ECHO) == 0;
  if send_seq(&mut s, 1, -1, 1, 0) != 0 { ok = false; }
  if send_seq(&mut s, 1, -1, 2, 0) != 1 { ok = false; }
  if send_seq(&mut s, 1, -1, 3, 0) != 2 { ok = false; }
  if mbox_of(&mut s, 1) != 2 { ok = false; }
  if dead_count_of(&mut s) != 1 { ok = false; }
  if dead_id_of(&mut s, 0) != 0 { ok = false; }
  if dead_tag_of(&mut s, 0) != 1 { ok = false; }
  if dead_reason_of(&mut s, 0) != ACTOR_DEAD_EVICTED { ok = false; }
  var tags = mbox_tags_of(&mut s, 1);
  if tags.len() != 2 { ok = false; }
  let t0: Int = tags[0];
  let t1: Int = tags[1];
  if t0 != 2 { ok = false; }
  if t1 != 3 { ok = false; }
  if step_id(&mut s) != 1 { ok = false; }
  if step_id(&mut s) != 1 { ok = false; }
  if proc_tag_of(&mut s, 0) != 2 { ok = false; }
  if proc_tag_of(&mut s, 1) != 3 { ok = false; }
  if !invariant_of(&mut s) { ok = false; }
  return assert(ok, "DROP_OLDEST evicts the oldest queued message and keeps the order");
}

fn t13() -> TestResult {
  var s = sys();
  var ok = send_seq(&mut s, 42, -1, 7, 0) == 0;
  if dead_count_of(&mut s) != 1 { ok = false; }
  if dead_target_of(&mut s, 0) != 42 { ok = false; }
  if dead_sender_of(&mut s, 0) != ACTOR_NO_SENDER { ok = false; }
  if dead_tag_of(&mut s, 0) != 7 { ok = false; }
  if dead_reason_of(&mut s, 0) != ACTOR_DEAD_UNKNOWN { ok = false; }
  if sent_of(&mut s) != 0 { ok = false; }
  if !send_err_is(&mut s, -1, 0, 0, 0, _E_TARGET) { ok = false; }
  if !send_err_is(&mut s, 1, -2, 0, 0, _E_SENDER) { ok = false; }
  if !send_err_is(&mut s, 1, 0, -1, 0, _E_TAG) { ok = false; }
  if !send_err_is(&mut s, 1, 9, 0, 0, _E_UNKNOWN_SENDER) { ok = false; }
  if dead_count_of(&mut s) != 1 { ok = false; }
  if !invariant_of(&mut s) { ok = false; }
  return assert(ok, "sends to unknown targets dead-letter and invalid sends are refused");
}

fn t14() -> TestResult {
  var s = sys();
  var ok = spawn_ok(&mut s, 1, 0, 0, ACTOR_OVERFLOW_DROP_NEW, ACTOR_BEHAVIOR_COUNT) == 0;
  if send_seq(&mut s, 1, -1, ACTOR_TAG_SELF_STOP, 0) != 0 { ok = false; }
  if step_id(&mut s) != 1 { ok = false; }
  if send_seq(&mut s, 1, -1, 5, 0) != 1 { ok = false; }
  if dead_reason_of(&mut s, 0) != ACTOR_DEAD_STOPPED { ok = false; }
  if spawn_ok(&mut s, 2, 0, 0, ACTOR_OVERFLOW_DROP_NEW, ACTOR_BEHAVIOR_ECHO) != 1 { ok = false; }
  if crash_ok(&mut s, 2, 3) != 3 { ok = false; }
  if state_of(&mut s, 2) != ACTOR_FAILED { ok = false; }
  if send_seq(&mut s, 2, -1, 5, 0) != 2 { ok = false; }
  if dead_count_of(&mut s) != 2 { ok = false; }
  if dead_reason_of(&mut s, 1) != ACTOR_DEAD_FAILED { ok = false; }
  if !invariant_of(&mut s) { ok = false; }
  return assert(ok, "sends to stopped and failed actors dead-letter with distinct reasons");
}

fn t15() -> TestResult {
  var s = sys();
  var ok = spawn_ok(&mut s, 1, 0, 0, ACTOR_OVERFLOW_DROP_NEW, ACTOR_BEHAVIOR_ECHO) == 0;
  if spawn_ok(&mut s, 2, 0, 0, ACTOR_OVERFLOW_DROP_NEW, ACTOR_BEHAVIOR_SINK) != 1 { ok = false; }
  if sup_ok(&mut s, 2, 1) != 1 { ok = false; }
  if sup_of(&mut s, 2) != 1 { ok = false; }
  if !sup_err_is(&mut s, 2, 1, _E_ALREADY_SUPERVISED) { ok = false; }
  if !sup_err_is(&mut s, 1, 1, _E_SELF) { ok = false; }
  if !sup_err_is(&mut s, 9, 1, _E_CHILD) { ok = false; }
  if !sup_err_is(&mut s, 1, 9, _E_SUPERVISOR) { ok = false; }
  if !sup_err_is(&mut s, 1, 2, _E_CYCLE) { ok = false; }
  if sup_of(&mut s, 1) != ACTOR_NO_SUPERVISOR { ok = false; }
  if !policy_err_is(&mut s, 1, 9, _E_DIRECTIVE) { ok = false; }
  if !policy_err_is(&mut s, 9, ACTOR_STOP, _E_UNKNOWN_ACTOR) { ok = false; }
  if policy_ok(&mut s, 1, ACTOR_STOP) != ACTOR_STOP { ok = false; }
  if dir_of(&mut s, 1) != ACTOR_STOP { ok = false; }
  if !invariant_of(&mut s) { ok = false; }
  return assert(ok, "supervision links validate the pair and refuse cycles");
}

fn t16() -> TestResult {
  var s = sys();
  var ok = spawn_ok(&mut s, 1, 0, 8, ACTOR_OVERFLOW_DROP_NEW, ACTOR_BEHAVIOR_ECHO) == 0;
  if spawn_ok(&mut s, 2, 9, 0, ACTOR_OVERFLOW_DROP_NEW, ACTOR_BEHAVIOR_SINK) != 1 { ok = false; }
  if sup_ok(&mut s, 1, 2) != 2 { ok = false; }
  if dir_of(&mut s, 2) != ACTOR_RESTART { ok = false; }
  if become_ok(&mut s, 1, ACTOR_BEHAVIOR_COUNT) != 1 { ok = false; }
  if send_seq(&mut s, 1, -1, 5, 1) != 0 { ok = false; }
  if send_seq(&mut s, 1, -1, ACTOR_TAG_CRASH, 7) != 1 { ok = false; }
  if send_seq(&mut s, 1, -1, 8, 2) != 2 { ok = false; }
  if step_id(&mut s) != 1 { ok = false; }
  if acc_of(&mut s, 1) != 1 { ok = false; }
  if step_id(&mut s) != 1 { ok = false; }
  if state_of(&mut s, 1) != ACTOR_SCHEDULED { ok = false; }
  if beh_of(&mut s, 1) != ACTOR_BEHAVIOR_ECHO { ok = false; }
  if ver_of(&mut s, 1) != 0 { ok = false; }
  if acc_of(&mut s, 1) != 0 { ok = false; }
  if restarts_of(&mut s, 1) != 1 { ok = false; }
  if restarts_total_of(&mut s) != 1 { ok = false; }
  if crashes_of(&mut s) != 1 { ok = false; }
  if step_id(&mut s) != 1 { ok = false; }
  if state_of(&mut s, 1) != ACTOR_IDLE { ok = false; }
  if proc_of(&mut s, 1) != 3 { ok = false; }
  if proc_tag_of(&mut s, 0) != 5 { ok = false; }
  if proc_tag_of(&mut s, 1) != ACTOR_TAG_CRASH { ok = false; }
  if proc_tag_of(&mut s, 2) != 8 { ok = false; }
  if !has_event(&mut s, "crash:1:7") { ok = false; }
  if !has_event(&mut s, "restart:1:2") { ok = false; }
  if !invariant_of(&mut s) { ok = false; }
  return assert(ok, "RESTART resets behavior state, keeps the mailbox and reschedules");
}

fn t17() -> TestResult {
  var s = sys();
  var ok = spawn_ok(&mut s, 1, 0, 8, ACTOR_OVERFLOW_DROP_NEW, ACTOR_BEHAVIOR_ECHO) == 0;
  if spawn_ok(&mut s, 2, 9, 0, ACTOR_OVERFLOW_DROP_NEW, ACTOR_BEHAVIOR_SINK) != 1 { ok = false; }
  if sup_ok(&mut s, 1, 2) != 2 { ok = false; }
  if policy_ok(&mut s, 2, ACTOR_STOP) != ACTOR_STOP { ok = false; }
  if send_seq(&mut s, 1, -1, 5, 0) != 0 { ok = false; }
  if send_seq(&mut s, 1, -1, ACTOR_TAG_CRASH, 1) != 1 { ok = false; }
  if send_seq(&mut s, 1, -1, 7, 0) != 2 { ok = false; }
  if send_seq(&mut s, 1, -1, 8, 0) != 3 { ok = false; }
  if step_id(&mut s) != 1 { ok = false; }
  if step_id(&mut s) != 1 { ok = false; }
  if state_of(&mut s, 1) != ACTOR_STOPPED { ok = false; }
  if stops_of(&mut s) != 1 { ok = false; }
  if mbox_of(&mut s, 1) != 0 { ok = false; }
  if dead_count_of(&mut s) != 2 { ok = false; }
  if dead_tag_of(&mut s, 0) != 7 { ok = false; }
  if dead_tag_of(&mut s, 1) != 8 { ok = false; }
  if dead_reason_of(&mut s, 0) != ACTOR_DEAD_STOPPED { ok = false; }
  if !crash_err_is(&mut s, 1, 0, _E_STOPPED) { ok = false; }
  if !invariant_of(&mut s) { ok = false; }
  return assert(ok, "a STOP directive stops the child and drains its mailbox to the dead letters");
}

fn t18() -> TestResult {
  var s = sys();
  var ok = spawn_ok(&mut s, 10, 1, 0, ACTOR_OVERFLOW_DROP_NEW, ACTOR_BEHAVIOR_SINK) == 0;
  if spawn_ok(&mut s, 11, 2, 0, ACTOR_OVERFLOW_DROP_NEW, ACTOR_BEHAVIOR_SINK) != 1 { ok = false; }
  if spawn_ok(&mut s, 12, 3, 0, ACTOR_OVERFLOW_DROP_NEW, ACTOR_BEHAVIOR_ECHO) != 2 { ok = false; }
  if sup_ok(&mut s, 11, 10) != 10 { ok = false; }
  if sup_ok(&mut s, 12, 11) != 11 { ok = false; }
  if policy_ok(&mut s, 11, ACTOR_ESCALATE) != ACTOR_ESCALATE { ok = false; }
  if send_seq(&mut s, 12, -1, 5, 0) != 0 { ok = false; }
  if send_seq(&mut s, 12, -1, ACTOR_TAG_CRASH, 4) != 1 { ok = false; }
  if send_seq(&mut s, 12, -1, 7, 0) != 2 { ok = false; }
  if step_id(&mut s) != 12 { ok = false; }
  if step_id(&mut s) != 12 { ok = false; }
  if state_of(&mut s, 12) != ACTOR_FAILED { ok = false; }
  if mbox_of(&mut s, 12) != 0 { ok = false; }
  if dead_count_of(&mut s) != 1 { ok = false; }
  if dead_tag_of(&mut s, 0) != 7 { ok = false; }
  if dead_reason_of(&mut s, 0) != ACTOR_DEAD_FAILED { ok = false; }
  if state_of(&mut s, 11) != ACTOR_IDLE { ok = false; }
  if restarts_of(&mut s, 11) != 1 { ok = false; }
  if escalations_of(&mut s) != 1 { ok = false; }
  if crashes_of(&mut s) != 2 { ok = false; }
  if state_of(&mut s, 10) != ACTOR_IDLE { ok = false; }
  if !has_event(&mut s, "escalate:12:11") { ok = false; }
  if !has_event(&mut s, "restart:11:10") { ok = false; }
  if !invariant_of(&mut s) { ok = false; }
  return assert(ok, "ESCALATE fails the child then crashes the supervisor up the chain");
}

fn t19() -> TestResult {
  var s = sys();
  var ok = spawn_ok(&mut s, 1, 0, 0, ACTOR_OVERFLOW_DROP_NEW, ACTOR_BEHAVIOR_ECHO) == 0;
  if send_seq(&mut s, 1, -1, 5, 0) != 0 { ok = false; }
  if send_seq(&mut s, 1, -1, ACTOR_TAG_CRASH, 3) != 1 { ok = false; }
  if send_seq(&mut s, 1, -1, 6, 0) != 2 { ok = false; }
  if step_id(&mut s) != 1 { ok = false; }
  if step_id(&mut s) != 1 { ok = false; }
  if state_of(&mut s, 1) != ACTOR_FAILED { ok = false; }
  if mbox_of(&mut s, 1) != 0 { ok = false; }
  if dead_count_of(&mut s) != 1 { ok = false; }
  if dead_tag_of(&mut s, 0) != 6 { ok = false; }
  if dead_reason_of(&mut s, 0) != ACTOR_DEAD_FAILED { ok = false; }
  if !crash_err_is(&mut s, 1, 3, _E_FAILED) { ok = false; }
  if !crash_err_is(&mut s, 99, 0, _E_UNKNOWN_ACTOR) { ok = false; }
  if !has_event(&mut s, "unhandled:1") { ok = false; }
  if !invariant_of(&mut s) { ok = false; }
  return assert(ok, "an unhandled crash fails the actor permanently and drains its mailbox");
}

fn t20() -> TestResult {
  var s = sys();
  var ok = spawn_ok(&mut s, 1, 0, 0, ACTOR_OVERFLOW_DROP_NEW, ACTOR_BEHAVIOR_COUNT) == 0;
  if send_seq(&mut s, 1, -1, ACTOR_TAG_SELF_STOP, 0) != 0 { ok = false; }
  if step_id(&mut s) != 1 { ok = false; }
  if !crash_err_is(&mut s, 1, 0, _E_STOPPED) { ok = false; }
  if stops_of(&mut s) != 1 { ok = false; }
  if !invariant_of(&mut s) { ok = false; }
  return assert(ok, "a stopped actor refuses further crashes");
}

fn t21() -> TestResult {
  var s = sys();
  var ok = spawn_ok(&mut s, 1, 0, 0, ACTOR_OVERFLOW_DROP_NEW, ACTOR_BEHAVIOR_ECHO) == 0;
  if spawn_ok(&mut s, 2, 0, 0, ACTOR_OVERFLOW_DROP_NEW, ACTOR_BEHAVIOR_ECHO) != 1 { ok = false; }
  if send_seq(&mut s, 1, -1, 1, 0) != 0 { ok = false; }
  if send_seq(&mut s, 2, -1, 2, 0) != 1 { ok = false; }
  if run_len(&mut s, 10) != 2 { ok = false; }
  if run_len(&mut s, 10) != 0 { ok = false; }
  if !run_err_is(&mut s, -1, _E_MAXSTEPS) { ok = false; }
  if spawn_ok(&mut s, 3, 0, 0, ACTOR_OVERFLOW_DROP_NEW, ACTOR_BEHAVIOR_ECHO) != 2 { ok = false; }
  if spawn_ok(&mut s, 4, 0, 0, ACTOR_OVERFLOW_DROP_NEW, ACTOR_BEHAVIOR_ECHO) != 3 { ok = false; }
  if send_seq(&mut s, 3, -1, 3, 0) != 2 { ok = false; }
  if send_seq(&mut s, 4, -1, 4, 0) != 3 { ok = false; }
  if !run_err_is(&mut s, 0, _E_LIMIT) { ok = false; }
  if ready_len_of(&mut s) != 2 { ok = false; }
  if run_len(&mut s, 1) != -1 { ok = false; }
  if !invariant_of(&mut s) { ok = false; }
  if run_len(&mut s, 5) != 1 { ok = false; }
  if ready_len_of(&mut s) != 0 { ok = false; }
  if !invariant_of(&mut s) { ok = false; }
  return assert(ok, "run_all drains quiescently and enforces the step bound");
}

fn t22() -> TestResult {
  var s = sys();
  var ok = spawn_ok(&mut s, 1, 0, 2, ACTOR_OVERFLOW_DROP_NEW, ACTOR_BEHAVIOR_ECHO) == 0;
  if spawn_ok(&mut s, 2, 0, 0, ACTOR_OVERFLOW_DROP_NEW, ACTOR_BEHAVIOR_COUNT) != 1 { ok = false; }
  if send_seq(&mut s, 1, -1, 1, 0) != 0 { ok = false; }
  if send_seq(&mut s, 1, -1, 2, 0) != 1 { ok = false; }
  if send_seq(&mut s, 1, -1, 3, 0) != 2 { ok = false; }
  if send_seq(&mut s, 2, -1, 5, 4) != 3 { ok = false; }
  if run_len(&mut s, 10) != 3 { ok = false; }
  if sent_of(&mut s) != 3 { ok = false; }
  if processed_of(&mut s) != 3 { ok = false; }
  if steps_of(&mut s) != 3 { ok = false; }
  if dead_count_of(&mut s) != 1 { ok = false; }
  if !streq(trace_text_of(&mut s), "1,2,1") { ok = false; }
  if acc_of(&mut s, 2) != 4 { ok = false; }
  if !streq(proc_text_of(&mut s), "1:1,2:5,1:2") { ok = false; }
  if !invariant_of(&mut s) { ok = false; }
  return assert(ok, "stats, traces and the processed log accumulate deterministically");
}

fn t23() -> TestResult {
  var s = sys();
  var ok = spawn_ok(&mut s, 1, 0, 0, ACTOR_OVERFLOW_DROP_NEW, ACTOR_BEHAVIOR_ECHO) == 0;
  if send_seq(&mut s, 1, -1, 5, 9) != 0 { ok = false; }
  if step_id(&mut s) != 1 { ok = false; }
  if proc_total_of(&mut s) != 1 { ok = false; }
  if proc_actor_of(&mut s, 0) != 1 { ok = false; }
  if proc_tag_of(&mut s, 0) != 5 { ok = false; }
  if proc_payload_of(&mut s, 0) != 9 { ok = false; }
  if proc_actor_of(&mut s, -1) != ACTOR_NOT_FOUND { ok = false; }
  if proc_tag_of(&mut s, 1) != ACTOR_NOT_FOUND { ok = false; }
  if proc_payload_of(&mut s, 99) != ACTOR_NOT_FOUND { ok = false; }
  if dead_id_of(&mut s, 0) != ACTOR_NOT_FOUND { ok = false; }
  if dead_reason_of(&mut s, 0) != ACTOR_NOT_FOUND { ok = false; }
  if actor_dead_letter_tag(&mut s, 5) != ACTOR_NOT_FOUND { ok = false; }
  var none = mbox_tags_of(&mut s, 77);
  if none.len() != 0 { ok = false; }
  if !streq(event_at_of(&mut s, -1), "") { ok = false; }
  if !streq(event_at_of(&mut s, 1000000), "") { ok = false; }
  return assert(ok, "accessors return sentinels for out-of-range indices");
}

fn t24() -> TestResult {
  var s = sys();
  var ok = spawn_ok(&mut s, 1, 0, 0, ACTOR_OVERFLOW_DROP_NEW, ACTOR_BEHAVIOR_ECHO) == 0;
  if send_seq(&mut s, 1, -1, 1, 0) != 0 { ok = false; }
  if step_id(&mut s) != 1 { ok = false; }
  var tr = trace_of(&mut s);
  var pt = proc_text_of(&mut s);
  if tr.len() != 1 { ok = false; }
  tr.push(99);
  if trace_len_of(&mut s) != 1 { ok = false; }
  if !streq(trace_text_of(&mut s), "1") { ok = false; }
  if !streq(pt, "1:1") { ok = false; }
  return assert(ok, "trace copies are independent snapshots");
}

fn t25() -> TestResult {
  var ok = streq(actor_state_name(ACTOR_IDLE), "idle");
  if !streq(actor_state_name(ACTOR_SCHEDULED), "scheduled") { ok = false; }
  if !streq(actor_state_name(ACTOR_RUNNING), "running") { ok = false; }
  if !streq(actor_state_name(ACTOR_STOPPED), "stopped") { ok = false; }
  if !streq(actor_state_name(ACTOR_FAILED), "failed") { ok = false; }
  if !streq(actor_state_name(7), "unknown") { ok = false; }
  if !streq(actor_behavior_name(ACTOR_BEHAVIOR_ECHO), "echo") { ok = false; }
  if !streq(actor_behavior_name(ACTOR_BEHAVIOR_COUNT), "count") { ok = false; }
  if !streq(actor_behavior_name(ACTOR_BEHAVIOR_SINK), "sink") { ok = false; }
  if !streq(actor_behavior_name(-1), "unknown") { ok = false; }
  if !streq(actor_directive_name(ACTOR_RESTART), "restart") { ok = false; }
  if !streq(actor_directive_name(ACTOR_STOP), "stop") { ok = false; }
  if !streq(actor_directive_name(ACTOR_ESCALATE), "escalate") { ok = false; }
  if !streq(actor_directive_name(9), "unknown") { ok = false; }
  if !streq(actor_overflow_name(ACTOR_OVERFLOW_DROP_NEW), "drop-new") { ok = false; }
  if !streq(actor_overflow_name(ACTOR_OVERFLOW_DROP_OLDEST), "drop-oldest") { ok = false; }
  if !streq(actor_overflow_name(2), "unknown") { ok = false; }
  if !streq(actor_dead_reason_name(ACTOR_DEAD_UNKNOWN), "unknown-target") { ok = false; }
  if !streq(actor_dead_reason_name(ACTOR_DEAD_STOPPED), "stopped") { ok = false; }
  if !streq(actor_dead_reason_name(ACTOR_DEAD_OVERFLOW), "overflow") { ok = false; }
  if !streq(actor_dead_reason_name(ACTOR_DEAD_EVICTED), "evicted") { ok = false; }
  if !streq(actor_dead_reason_name(ACTOR_DEAD_FAILED), "failed") { ok = false; }
  if !streq(actor_dead_reason_name(99), "unknown") { ok = false; }
  return assert(ok, "name helpers are stable for every documented code");
}

fn t26() -> TestResult {
  var s = sys();
  var ok = spawn_ok(&mut s, 1, 0, 0, ACTOR_OVERFLOW_DROP_NEW, ACTOR_BEHAVIOR_ECHO) == 0;
  if event_count_of(&mut s) != 1 { ok = false; }
  if !streq(event_at_of(&mut s, 0), "spawn:1:0") { ok = false; }
  if send_seq(&mut s, 1, -1, 5, 0) != 0 { ok = false; }
  if step_id(&mut s) != 1 { ok = false; }
  if event_count_of(&mut s) != 3 { ok = false; }
  if !streq(event_at_of(&mut s, 1), "dispatch:1") { ok = false; }
  if !streq(event_at_of(&mut s, 2), "echo:1:5:0") { ok = false; }
  if !invariant_of(&mut s) { ok = false; }
  return assert(ok, "the event log records spawn, dispatch and processing in order");
}

fn t27() -> TestResult {
  var s = sys();
  var ok = spawn_ok(&mut s, 1, 0, 4, ACTOR_OVERFLOW_DROP_OLDEST, ACTOR_BEHAVIOR_ECHO) == 0;
  if spawn_ok(&mut s, 2, 0, 4, ACTOR_OVERFLOW_DROP_NEW, ACTOR_BEHAVIOR_COUNT) != 1 { ok = false; }
  if spawn_ok(&mut s, 3, 0, 0, ACTOR_OVERFLOW_DROP_NEW, ACTOR_BEHAVIOR_SINK) != 2 { ok = false; }
  if spawn_ok(&mut s, 4, 0, 0, ACTOR_OVERFLOW_DROP_NEW, ACTOR_BEHAVIOR_SINK) != 3 { ok = false; }
  if sup_ok(&mut s, 1, 4) != 4 { ok = false; }
  if sup_ok(&mut s, 2, 4) != 4 { ok = false; }
  var i = 0;
  while i < 30 {
    let target = 1 + (i % 4);
    let tag = i % 5;
    if send_seq(&mut s, target, -1, tag, i) < 0 { ok = false; }
    if i % 3 == 0 {
      if step_id(&mut s) < 0 { ok = false; }
    }
    if !invariant_of(&mut s) { ok = false; }
    i = i + 1;
  }
  if run_len(&mut s, 100) < 0 { ok = false; }
  if ready_len_of(&mut s) != 0 { ok = false; }
  if !invariant_of(&mut s) { ok = false; }
  return assert(ok, "the invariant survives 30 mixed send/step cycles");
}

fn t28() -> TestResult {
  var s = sys();
  var ok = spawn_ok(&mut s, 1, 0, 0, ACTOR_OVERFLOW_DROP_NEW, ACTOR_BEHAVIOR_SINK) == 0;
  if spawn_ok(&mut s, 2, 5, 3, ACTOR_OVERFLOW_DROP_OLDEST, ACTOR_BEHAVIOR_ECHO) != 1 { ok = false; }
  if sup_ok(&mut s, 2, 1) != 1 { ok = false; }
  if send_seq(&mut s, 2, -1, 10, 1) != 0 { ok = false; }
  if send_seq(&mut s, 2, -1, 11, 2) != 1 { ok = false; }
  if send_seq(&mut s, 2, -1, 12, 3) != 2 { ok = false; }
  if send_seq(&mut s, 2, -1, 13, 4) != 3 { ok = false; }
  if dead_count_of(&mut s) != 1 { ok = false; }
  if dead_tag_of(&mut s, 0) != 10 { ok = false; }
  if dead_reason_of(&mut s, 0) != ACTOR_DEAD_EVICTED { ok = false; }
  if run_len(&mut s, 10) != 3 { ok = false; }
  if !streq(proc_text_of(&mut s), "2:11,2:12,2:13") { ok = false; }
  if send_seq(&mut s, 2, -1, ACTOR_TAG_CRASH, 1) != 4 { ok = false; }
  if run_len(&mut s, 10) != 1 { ok = false; }
  if state_of(&mut s, 2) != ACTOR_IDLE { ok = false; }
  if restarts_of(&mut s, 2) != 1 { ok = false; }
  if !streq(trace_text_of(&mut s), "2,2,2,2") { ok = false; }
  if !invariant_of(&mut s) { ok = false; }
  return assert(ok, "supervised worker survives a crash with priority scheduling intact");
}

fn main() -> Int {
  io.println("=== xiom.actor conformance tests ===");
  var failed: Int = 0;
  let r1 = t1();
  if r1.passed { io.println("  [PASS] " + r1.name); } else { io.println("  [FAIL] " + r1.name); failed = failed + 1; }
  let r2 = t2();
  if r2.passed { io.println("  [PASS] " + r2.name); } else { io.println("  [FAIL] " + r2.name); failed = failed + 1; }
  let r3 = t3();
  if r3.passed { io.println("  [PASS] " + r3.name); } else { io.println("  [FAIL] " + r3.name); failed = failed + 1; }
  let r4 = t4();
  if r4.passed { io.println("  [PASS] " + r4.name); } else { io.println("  [FAIL] " + r4.name); failed = failed + 1; }
  let r5 = t5();
  if r5.passed { io.println("  [PASS] " + r5.name); } else { io.println("  [FAIL] " + r5.name); failed = failed + 1; }
  let r6 = t6();
  if r6.passed { io.println("  [PASS] " + r6.name); } else { io.println("  [FAIL] " + r6.name); failed = failed + 1; }
  let r7 = t7();
  if r7.passed { io.println("  [PASS] " + r7.name); } else { io.println("  [FAIL] " + r7.name); failed = failed + 1; }
  let r8 = t8();
  if r8.passed { io.println("  [PASS] " + r8.name); } else { io.println("  [FAIL] " + r8.name); failed = failed + 1; }
  let r9 = t9();
  if r9.passed { io.println("  [PASS] " + r9.name); } else { io.println("  [FAIL] " + r9.name); failed = failed + 1; }
  let r10 = t10();
  if r10.passed { io.println("  [PASS] " + r10.name); } else { io.println("  [FAIL] " + r10.name); failed = failed + 1; }
  let r11 = t11();
  if r11.passed { io.println("  [PASS] " + r11.name); } else { io.println("  [FAIL] " + r11.name); failed = failed + 1; }
  let r12 = t12();
  if r12.passed { io.println("  [PASS] " + r12.name); } else { io.println("  [FAIL] " + r12.name); failed = failed + 1; }
  let r13 = t13();
  if r13.passed { io.println("  [PASS] " + r13.name); } else { io.println("  [FAIL] " + r13.name); failed = failed + 1; }
  let r14 = t14();
  if r14.passed { io.println("  [PASS] " + r14.name); } else { io.println("  [FAIL] " + r14.name); failed = failed + 1; }
  let r15 = t15();
  if r15.passed { io.println("  [PASS] " + r15.name); } else { io.println("  [FAIL] " + r15.name); failed = failed + 1; }
  let r16 = t16();
  if r16.passed { io.println("  [PASS] " + r16.name); } else { io.println("  [FAIL] " + r16.name); failed = failed + 1; }
  let r17 = t17();
  if r17.passed { io.println("  [PASS] " + r17.name); } else { io.println("  [FAIL] " + r17.name); failed = failed + 1; }
  let r18 = t18();
  if r18.passed { io.println("  [PASS] " + r18.name); } else { io.println("  [FAIL] " + r18.name); failed = failed + 1; }
  let r19 = t19();
  if r19.passed { io.println("  [PASS] " + r19.name); } else { io.println("  [FAIL] " + r19.name); failed = failed + 1; }
  let r20 = t20();
  if r20.passed { io.println("  [PASS] " + r20.name); } else { io.println("  [FAIL] " + r20.name); failed = failed + 1; }
  let r21 = t21();
  if r21.passed { io.println("  [PASS] " + r21.name); } else { io.println("  [FAIL] " + r21.name); failed = failed + 1; }
  let r22 = t22();
  if r22.passed { io.println("  [PASS] " + r22.name); } else { io.println("  [FAIL] " + r22.name); failed = failed + 1; }
  let r23 = t23();
  if r23.passed { io.println("  [PASS] " + r23.name); } else { io.println("  [FAIL] " + r23.name); failed = failed + 1; }
  let r24 = t24();
  if r24.passed { io.println("  [PASS] " + r24.name); } else { io.println("  [FAIL] " + r24.name); failed = failed + 1; }
  let r25 = t25();
  if r25.passed { io.println("  [PASS] " + r25.name); } else { io.println("  [FAIL] " + r25.name); failed = failed + 1; }
  let r26 = t26();
  if r26.passed { io.println("  [PASS] " + r26.name); } else { io.println("  [FAIL] " + r26.name); failed = failed + 1; }
  let r27 = t27();
  if r27.passed { io.println("  [PASS] " + r27.name); } else { io.println("  [FAIL] " + r27.name); failed = failed + 1; }
  let r28 = t28();
  if r28.passed { io.println("  [PASS] " + r28.name); } else { io.println("  [FAIL] " + r28.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.actor: all tests passed");
  } else {
    io.println("xiom.actor: tests failed");
  }
  return failed;
}
