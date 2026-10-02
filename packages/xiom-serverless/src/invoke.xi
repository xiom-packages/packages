// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// XIOM -- xiom.serverless.invoke: execution plane of xiom.serverless.
// Synchronous and asynchronous invocation, the deterministic FIFO
// dispatch/finish queue (bounded by max_concurrency), runtime instances
// (COLD -> WARM -> BUSY -> WARM) and cold-start accounting. Pure and
// deterministic: no networking, no threads, no clock, no FFI, no I/O; the
// caller supplies simulated execution time as `elapsed_ms`.
//
// This module owns the invocation/runtime half of the ServerlessSystem value
// defined by xiom.serverless: it reads and mutates the same parallel Vec[Int]
// fields through the shared type. Language notes (XIOM v0.62.2): free
// functions only; Ok/Err constructed only inside _ok_*/_err_* leaf helpers;
// Vec[Int] element reads bound with typed `let`; parallel Vec fields pushed
// together; no Vec[StructType], no Vec[Str], no indexed Vec[fn] dispatch
// (handlers use explicit case dispatch), no generic callbacks, no
// Vec[Float64], no `mut` patterns, no `log`-named function, no FFI.

module xiom.serverless.invoke

use xiom.convert;
use xiom.serverless;

// Private table selectors (same values as xiom.serverless).
const _TBL_FN: Int = 0;
const _TBL_TRIGGER: Int = 1;
const _TBL_DEPLOY: Int = 2;
const _TBL_INVOCATION: Int = 3;
const _TBL_INSTANCE: Int = 4;

// ---------------------------------------------------------------------------
// Result constructors (leaf helpers only)
// ---------------------------------------------------------------------------

fn _ok_int(v: Int) -> Result[Int, Str] { return Ok(v); }
fn _err_int(m: Str) -> Result[Int, Str] { return Err(m); }
fn _ok_vec(v: Vec[Int]) -> Result[Vec[Int], Str] { return Ok(v); }
fn _err_vec(m: Str) -> Result[Vec[Int], Str] { return Err(m); }

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

// Slot of entity `id` in table `which`, or -1 when unknown. Module-local copy
// of the same helper in xiom.serverless (private helpers do not cross module
// boundaries); element reads use typed `let` bindings.
fn _slot_in(s: &ServerlessSystem, which: Int, id: Int) -> Int {
  var n = 0;
  if which == _TBL_FN { n = s.function_ids.len(); }
  if which == _TBL_TRIGGER { n = s.trigger_ids.len(); }
  if which == _TBL_DEPLOY { n = s.deploy_ids.len(); }
  if which == _TBL_INVOCATION { n = s.invocation_ids.len(); }
  if which == _TBL_INSTANCE { n = s.instance_ids.len(); }
  var i = 0;
  while i < n {
    var cur = 0;
    if which == _TBL_FN { cur = s.function_ids[i]; }
    if which == _TBL_TRIGGER { cur = s.trigger_ids[i]; }
    if which == _TBL_DEPLOY { cur = s.deploy_ids[i]; }
    if which == _TBL_INVOCATION { cur = s.invocation_ids[i]; }
    if which == _TBL_INSTANCE { cur = s.instance_ids[i]; }
    if cur == id { return i; }
    i = i + 1;
  }
  return -1;
}

// Remove the queue entry at `idx`, rebuilding the vector in step.
fn _remove_queue_at(s: &mut ServerlessSystem, idx: Int) {
  var out = Vec[Int].new();
  var i = 0;
  while i < s.queue.len() {
    if i != idx {
      let v: Int = s.queue[i];
      out.push(v);
    }
    i = i + 1;
  }
  s.queue = out;
}

// First instance of `function_id` in state `want`, or -1. Slots ascend, so the
// choice is deterministic (oldest instance first).
fn _pick_instance(s: &ServerlessSystem, function_id: Int, want: Int) -> Int {
  var i = 0;
  while i < s.instance_ids.len() {
    let fid: Int = s.instance_functions[i];
    let st: Int = s.instance_states[i];
    if fid == function_id && st == want { return i; }
    i = i + 1;
  }
  return -1;
}

// Append a fresh COLD instance for `function_id`, auto-assigning the smallest
// free id at or after next_instance_id; returns its slot. The skip loop
// strictly increases the candidate, so it terminates.
fn _alloc_instance(s: &mut ServerlessSystem, function_id: Int) -> Int {
  var nid = s.next_instance_id;
  while _slot_in(s, _TBL_INSTANCE, nid) >= 0 { nid = nid + 1; }
  s.instance_ids.push(nid);
  s.instance_functions.push(function_id);
  s.instance_states.push(SV_RT_COLD);
  s.instance_served.push(0);
  s.next_instance_id = nid + 1;
  let n: Int = s.instance_ids.len();
  return n - 1;
}

// COLD -> WARM: charge one cold start and the configured boot cost.
fn _init_instance(s: &mut ServerlessSystem, slot: Int) {
  s.instance_states[slot] = SV_RT_WARM;
  s.cold_starts = s.cold_starts + 1;
  s.cold_start_ms = s.cold_start_ms + s.boot_ms;
}

// Acquire a WARM instance for `function_id`: reuse a warm one, else initialize
// a cold one, else allocate and initialize a fresh one. Cold-start counters
// are updated on every COLD -> WARM transition.
fn _ensure_instance(s: &mut ServerlessSystem, function_id: Int) -> Int {
  let warm = _pick_instance(s, function_id, SV_RT_WARM);
  if warm >= 0 { return warm; }
  let cold = _pick_instance(s, function_id, SV_RT_COLD);
  if cold >= 0 {
    _init_instance(s, cold);
    return cold;
  }
  let fresh = _alloc_instance(s, function_id);
  _init_instance(s, fresh);
  return fresh;
}

// Append a fully parallel invocation row and return its slot.
fn _record_invocation(s: &mut ServerlessSystem, id: Int, function_id: Int, payload: Int, state: Int) -> Int {
  s.invocation_ids.push(id);
  s.invocation_functions.push(function_id);
  s.invocation_states.push(state);
  s.invocation_payloads.push(payload);
  s.invocation_outputs.push(0);
  s.invocation_codes.push(SV_CODE_OK);
  s.invocation_instances.push(SV_NO_INSTANCE);
  s.invocation_colds.push(0);
  let n: Int = s.invocation_ids.len();
  return n - 1;
}

// Bind a runtime instance to invocation `slot`: reuse a WARM instance, or pay
// a cold start on a COLD/fresh one. Records the instance and the cold flag.
fn _attach_runtime(s: &mut ServerlessSystem, slot: Int, function_id: Int) {
  let warm = _pick_instance(s, function_id, SV_RT_WARM);
  var cold = 0;
  var inst = warm;
  if inst < 0 {
    cold = 1;
    inst = _ensure_instance(s, function_id);
  }
  s.invocation_instances[slot] = inst;
  s.invocation_colds[slot] = cold;
  s.instance_states[inst] = SV_RT_BUSY;
  s.instance_served[inst] = s.instance_served[inst] + 1;
}

// Deterministic handler evaluation. SV_HANDLER_FAIL is checked by the caller;
// it never reaches this helper.
fn _handler_output(handler: Int, payload: Int) -> Int {
  if handler == SV_HANDLER_DOUBLE { return payload * 2; }
  return payload;
}

// Settle a RUNNING invocation: timeout (elapsed_ms > timeout_ms) wins over a
// failing handler, which wins over success. Releases the runtime instance,
// decrements the async running gauge when `is_async == 1`, counts cold vs warm
// execution, appends the id to the completion trace and returns Ok(output) or
// the exact failure message (the state/code slots keep the detail).
fn _settle(s: &mut ServerlessSystem, slot: Int, elapsed_ms: Int, is_async: Int) -> Result[Int, Str] {
  let fid: Int = s.invocation_functions[slot];
  let fslot = _slot_in(s, _TBL_FN, fid);
  let timeout: Int = s.function_timeout_ms[fslot];
  let handler: Int = s.function_handlers[fslot];
  let inst: Int = s.invocation_instances[slot];
  if inst >= 0 {
    if s.instance_states[inst] == SV_RT_BUSY {
      s.instance_states[inst] = SV_RT_WARM;
    }
  }
  if is_async == 1 { s.running = s.running - 1; }
  let cold: Int = s.invocation_colds[slot];
  if cold == 1 { s.cold_invocations = s.cold_invocations + 1; } else { s.warm_invocations = s.warm_invocations + 1; }
  let id: Int = s.invocation_ids[slot];
  if elapsed_ms > timeout {
    s.invocation_states[slot] = SV_INV_FAILED;
    s.invocation_codes[slot] = SV_CODE_TIMEOUT;
    s.failed = s.failed + 1;
    s.timed_out = s.timed_out + 1;
    s.completion_order.push(id);
    return _err_int("serverless: invocation timed out");
  }
  if handler == SV_HANDLER_FAIL {
    s.invocation_states[slot] = SV_INV_FAILED;
    s.invocation_codes[slot] = SV_CODE_HANDLER;
    s.failed = s.failed + 1;
    s.completion_order.push(id);
    return _err_int("serverless: handler failed");
  }
  let payload: Int = s.invocation_payloads[slot];
  let out = _handler_output(handler, payload);
  s.invocation_states[slot] = SV_INV_DONE;
  s.invocation_outputs[slot] = out;
  s.completed = s.completed + 1;
  s.completion_order.push(id);
  return _ok_int(out);
}

// ---------------------------------------------------------------------------
// Invocation: synchronous path
// ---------------------------------------------------------------------------

/// Invoke a function synchronously: bypasses the queue, acquires a runtime
/// instance, evaluates the handler and settles in one call.
/// Params: s - the system; invocation_id - unique id, >= 0; function_id - an
///         ACTIVE function; payload - the request payload; elapsed_ms -
///         simulated execution time, >= 0.
/// Returns: Ok(output) on success; Err("serverless: invocation timed out")
///          when elapsed_ms > function timeout (code SV_CODE_TIMEOUT),
///          Err("serverless: handler failed") for SV_HANDLER_FAIL (code
///          SV_CODE_HANDLER); validation errors: Err("serverless: invocation
///          id must be >= 0"), Err("serverless: duplicate invocation id"),
///          Err("serverless: elapsed_ms must be >= 0"),
///          Err("serverless: unknown function id") or
///          Err("serverless: function is not active").
/// Complexity: O(function count + invocation count + instance count).
pub fn invoke_sync(s: &mut ServerlessSystem, invocation_id: Int, function_id: Int, payload: Int, elapsed_ms: Int) -> Result[Int, Str] {
  if invocation_id < 0 { return _err_int("serverless: invocation id must be >= 0"); }
  if _slot_in(s, _TBL_INVOCATION, invocation_id) >= 0 { return _err_int("serverless: duplicate invocation id"); }
  if elapsed_ms < 0 { return _err_int("serverless: elapsed_ms must be >= 0"); }
  let fslot = _slot_in(s, _TBL_FN, function_id);
  if fslot < 0 { return _err_int("serverless: unknown function id"); }
  let fst: Int = s.function_states[fslot];
  if fst != SV_FN_ACTIVE { return _err_int("serverless: function is not active"); }
  let slot = _record_invocation(s, invocation_id, function_id, payload, SV_INV_RUNNING);
  _attach_runtime(s, slot, function_id);
  return _settle(s, slot, elapsed_ms, 0);
}

// ---------------------------------------------------------------------------
// Invocation: asynchronous queue, dispatch, finish
// ---------------------------------------------------------------------------

/// Accept an invocation into the async FIFO queue (QUEUED).
/// Params: s - the system; invocation_id - unique id, >= 0; function_id - an
///         ACTIVE function; payload - the request payload.
/// Returns: Ok(invocation_id); errors as invoke_sync (minus elapsed_ms).
/// Complexity: O(function count + invocation count).
pub fn invoke_async(s: &mut ServerlessSystem, invocation_id: Int, function_id: Int, payload: Int) -> Result[Int, Str] {
  if invocation_id < 0 { return _err_int("serverless: invocation id must be >= 0"); }
  if _slot_in(s, _TBL_INVOCATION, invocation_id) >= 0 { return _err_int("serverless: duplicate invocation id"); }
  let fslot = _slot_in(s, _TBL_FN, function_id);
  if fslot < 0 { return _err_int("serverless: unknown function id"); }
  let fst: Int = s.function_states[fslot];
  if fst != SV_FN_ACTIVE { return _err_int("serverless: function is not active"); }
  _record_invocation(s, invocation_id, function_id, payload, SV_INV_QUEUED);
  s.queue.push(invocation_id);
  return _ok_int(invocation_id);
}

/// Dispatch the front queued invocation (QUEUED -> RUNNING): pops the FIFO,
/// enforces max_concurrency, acquires a runtime instance and increments the
/// running gauge. When the bound function is no longer ACTIVE the invocation
/// is settled ABORTED (SV_CODE_ABORTED) instead.
/// Params: s - the system.
/// Returns: Ok(invocation_id); Err("serverless: no queued invocations"),
///          Err("serverless: concurrency limit reached") or
///          Err("serverless: function is not active") (invocation aborted).
/// Complexity: O(queue length + invocation count + instance count).
pub fn invoke_dispatch(s: &mut ServerlessSystem) -> Result[Int, Str] {
  if s.queue.len() == 0 { return _err_int("serverless: no queued invocations"); }
  if s.running >= s.max_concurrency { return _err_int("serverless: concurrency limit reached"); }
  let id: Int = s.queue[0];
  _remove_queue_at(s, 0);
  let slot = _slot_in(s, _TBL_INVOCATION, id);
  let fid: Int = s.invocation_functions[slot];
  let fslot = _slot_in(s, _TBL_FN, fid);
  let fst: Int = s.function_states[fslot];
  if fst != SV_FN_ACTIVE {
    s.invocation_states[slot] = SV_INV_FAILED;
    s.invocation_codes[slot] = SV_CODE_ABORTED;
    s.failed = s.failed + 1;
    s.aborted = s.aborted + 1;
    s.completion_order.push(id);
    return _err_int("serverless: function is not active");
  }
  _attach_runtime(s, slot, fid);
  s.invocation_states[slot] = SV_INV_RUNNING;
  s.running = s.running + 1;
  return _ok_int(id);
}

/// Finish a RUNNING invocation (RUNNING -> DONE | FAILED) with the same
/// outcome rules as invoke_sync; releases the runtime instance and decrements
/// the running gauge.
/// Params: s - the system; invocation_id - the running invocation;
///         elapsed_ms - simulated execution time, >= 0.
/// Returns: Ok(output); Err("serverless: invocation timed out"),
///          Err("serverless: handler failed"),
///          Err("serverless: elapsed_ms must be >= 0"),
///          Err("serverless: unknown invocation id"),
///          Err("serverless: invocation already complete"),
///          Err("serverless: invocation already failed") or
///          Err("serverless: invocation is not running").
/// Complexity: O(function count + invocation count + instance count).
pub fn invoke_finish(s: &mut ServerlessSystem, invocation_id: Int, elapsed_ms: Int) -> Result[Int, Str] {
  if elapsed_ms < 0 { return _err_int("serverless: elapsed_ms must be >= 0"); }
  let slot = _slot_in(s, _TBL_INVOCATION, invocation_id);
  if slot < 0 { return _err_int("serverless: unknown invocation id"); }
  let st: Int = s.invocation_states[slot];
  if st == SV_INV_DONE { return _err_int("serverless: invocation already complete"); }
  if st == SV_INV_FAILED { return _err_int("serverless: invocation already failed"); }
  if st != SV_INV_RUNNING { return _err_int("serverless: invocation is not running"); }
  return _settle(s, slot, elapsed_ms, 1);
}

/// Drive the async queue to quiescence: repeatedly dispatch the front
/// invocation and finish it with `elapsed_ms`. The loop is bounded: every
/// iteration removes one queue entry, and `max_steps` caps the number of
/// dispatches.
/// Params: s - the system; max_steps - dispatch bound, >= 0; elapsed_ms -
///         simulated execution time per invocation, >= 0.
/// Returns: Ok(trace) with the invocation ids finished by THIS run, in
///          completion order (empty when the queue was empty);
///          Err("serverless: max_steps must be >= 0"),
///          Err("serverless: elapsed_ms must be >= 0"),
///          Err("serverless: step limit exceeded") when the bound is reached
///          with work left, or any dispatch/finish error (surfaced unchanged;
///          completed states are retained).
/// Complexity: O(max_steps * (queue length + function count + instance count)).
pub fn invoke_run_all(s: &mut ServerlessSystem, max_steps: Int, elapsed_ms: Int) -> Result[Vec[Int], Str] {
  if max_steps < 0 { return _err_vec("serverless: max_steps must be >= 0"); }
  if elapsed_ms < 0 { return _err_vec("serverless: elapsed_ms must be >= 0"); }
  var trace = Vec[Int].new();
  var dispatched = 0;
  while true {
    if s.queue.len() == 0 { return _ok_vec(trace); }
    if dispatched >= max_steps { return _err_vec("serverless: step limit exceeded"); }
    let disp = invoke_dispatch(s);
    var id = 0;
    match disp {
      Ok(v) => { id = v; },
      Err(m) => { return _err_vec(m); },
    }
    let fin = invoke_finish(s, id, elapsed_ms);
    match fin {
      Ok(_) => { trace.push(id); },
      Err(m) => { return _err_vec(m); },
    }
    dispatched = dispatched + 1;
  }
  return _ok_vec(trace);
}

// ---------------------------------------------------------------------------
// Runtime instances and cold-start accounting
// ---------------------------------------------------------------------------

/// Allocate a runtime instance for a function in the COLD state. Cold-start
/// cost is charged when the instance is initialized (or first used), not here.
/// Params: s - the system; instance_id - unique id, >= 0; function_id - the
///         function the instance serves.
/// Returns: Ok(instance_id); Err("serverless: instance id must be >= 0"),
///          Err("serverless: duplicate instance id") or
///          Err("serverless: unknown function id") -- unchanged.
/// Complexity: O(function count + instance count).
pub fn runtime_alloc(s: &mut ServerlessSystem, instance_id: Int, function_id: Int) -> Result[Int, Str] {
  if instance_id < 0 { return _err_int("serverless: instance id must be >= 0"); }
  if _slot_in(s, _TBL_INSTANCE, instance_id) >= 0 { return _err_int("serverless: duplicate instance id"); }
  if _slot_in(s, _TBL_FN, function_id) < 0 { return _err_int("serverless: unknown function id"); }
  s.instance_ids.push(instance_id);
  s.instance_functions.push(function_id);
  s.instance_states.push(SV_RT_COLD);
  s.instance_served.push(0);
  return _ok_int(instance_id);
}

/// Initialize an instance (COLD -> WARM): charge one cold start and the
/// configured boot_ms.
/// Params: s - the system; instance_id - a COLD instance.
/// Returns: Ok(cold_starts) with the cumulative cold-start count;
///          Err("serverless: unknown instance id"),
///          Err("serverless: instance already warm") or
///          Err("serverless: instance is busy") -- unchanged.
/// Complexity: O(instance count).
pub fn runtime_init(s: &mut ServerlessSystem, instance_id: Int) -> Result[Int, Str] {
  let slot = _slot_in(s, _TBL_INSTANCE, instance_id);
  if slot < 0 { return _err_int("serverless: unknown instance id"); }
  let st: Int = s.instance_states[slot];
  if st == SV_RT_WARM { return _err_int("serverless: instance already warm"); }
  if st == SV_RT_BUSY { return _err_int("serverless: instance is busy"); }
  _init_instance(s, slot);
  return _ok_int(s.cold_starts);
}

// ---------------------------------------------------------------------------
// Accessors: invocations
// ---------------------------------------------------------------------------

/// Number of accepted invocations. Complexity: O(1).
pub fn invocation_count(s: &ServerlessSystem) -> Int {
  return s.invocation_ids.len();
}

/// State of invocation `id` (SV_INV_*), or SV_NOT_FOUND (-1).
/// Complexity: O(invocation count).
pub fn invocation_state(s: &ServerlessSystem, id: Int) -> Int {
  let slot = _slot_in(s, _TBL_INVOCATION, id);
  if slot < 0 { return SV_NOT_FOUND; }
  let st: Int = s.invocation_states[slot];
  return st;
}

/// Request payload of invocation `id`, or SV_NOT_FOUND (-1).
/// Complexity: O(invocation count).
pub fn invocation_payload(s: &ServerlessSystem, id: Int) -> Int {
  let slot = _slot_in(s, _TBL_INVOCATION, id);
  if slot < 0 { return SV_NOT_FOUND; }
  let p: Int = s.invocation_payloads[slot];
  return p;
}

/// Output of invocation `id` (0 until DONE), or SV_NOT_FOUND (-1).
/// Complexity: O(invocation count).
pub fn invocation_output(s: &ServerlessSystem, id: Int) -> Int {
  let slot = _slot_in(s, _TBL_INVOCATION, id);
  if slot < 0 { return SV_NOT_FOUND; }
  let o: Int = s.invocation_outputs[slot];
  return o;
}

/// Failure code of invocation `id` (SV_CODE_OK when not failed), or
/// SV_NOT_FOUND (-1). Complexity: O(invocation count).
pub fn invocation_code(s: &ServerlessSystem, id: Int) -> Int {
  let slot = _slot_in(s, _TBL_INVOCATION, id);
  if slot < 0 { return SV_NOT_FOUND; }
  let c: Int = s.invocation_codes[slot];
  return c;
}

/// Runtime instance slot serving invocation `id`, or SV_NO_INSTANCE /
/// SV_NOT_FOUND (-1). Complexity: O(invocation count).
pub fn invocation_instance(s: &ServerlessSystem, id: Int) -> Int {
  let slot = _slot_in(s, _TBL_INVOCATION, id);
  if slot < 0 { return SV_NOT_FOUND; }
  let i: Int = s.invocation_instances[slot];
  return i;
}

/// Length of the terminal-invocation trace. Complexity: O(1).
pub fn invocation_trace_len(s: &ServerlessSystem) -> Int {
  return s.completion_order.len();
}

/// Terminal-invocation trace rendered as comma-separated ids, "" when empty.
/// Complexity: O(trace length).
pub fn invocation_trace_text(s: &ServerlessSystem) -> Str {
  var out = "";
  var i = 0;
  while i < s.completion_order.len() {
    let id: Int = s.completion_order[i];
    if i > 0 { out = out + ","; }
    out = out + convert.int_to_string(id);
    i = i + 1;
  }
  return out;
}

// ---------------------------------------------------------------------------
// Accessors: runtime instances
// ---------------------------------------------------------------------------

/// Number of runtime instances. Complexity: O(1).
pub fn runtime_count(s: &ServerlessSystem) -> Int {
  return s.instance_ids.len();
}

/// State of instance `id` (SV_RT_*), or SV_NOT_FOUND (-1).
/// Complexity: O(instance count).
pub fn runtime_state(s: &ServerlessSystem, id: Int) -> Int {
  let slot = _slot_in(s, _TBL_INSTANCE, id);
  if slot < 0 { return SV_NOT_FOUND; }
  let st: Int = s.instance_states[slot];
  return st;
}

/// Invocations served by instance `id`, or SV_NOT_FOUND (-1).
/// Complexity: O(instance count).
pub fn runtime_served(s: &ServerlessSystem, id: Int) -> Int {
  let slot = _slot_in(s, _TBL_INSTANCE, id);
  if slot < 0 { return SV_NOT_FOUND; }
  let n: Int = s.instance_served[slot];
  return n;
}

// ---------------------------------------------------------------------------
// Accessors: configuration and counters
// ---------------------------------------------------------------------------

/// Async dispatch cap. Complexity: O(1).
pub fn serverless_max_concurrency(s: &ServerlessSystem) -> Int {
  return s.max_concurrency;
}

/// Invocations currently RUNNING. Complexity: O(1).
pub fn serverless_running(s: &ServerlessSystem) -> Int {
  return s.running;
}

/// Successfully finished invocations. Complexity: O(1).
pub fn serverless_completed(s: &ServerlessSystem) -> Int {
  return s.completed;
}

/// Invocations finished with a failure (handler, timeout or aborted).
/// Complexity: O(1).
pub fn serverless_failed(s: &ServerlessSystem) -> Int {
  return s.failed;
}

/// Invocations failed by timeout. Complexity: O(1).
pub fn serverless_timed_out(s: &ServerlessSystem) -> Int {
  return s.timed_out;
}

/// Invocations aborted at dispatch because the function was not ACTIVE.
/// Complexity: O(1).
pub fn serverless_aborted(s: &ServerlessSystem) -> Int {
  return s.aborted;
}

/// Cold starts paid (COLD -> WARM transitions). Complexity: O(1).
pub fn serverless_cold_starts(s: &ServerlessSystem) -> Int {
  return s.cold_starts;
}

/// Total cold-start time charged (cold_starts * boot_ms). Complexity: O(1).
pub fn serverless_cold_start_ms(s: &ServerlessSystem) -> Int {
  return s.cold_start_ms;
}

/// Finished invocations that paid a cold start. Complexity: O(1).
pub fn serverless_cold_invocations(s: &ServerlessSystem) -> Int {
  return s.cold_invocations;
}

/// Finished invocations served by an already-warm instance. Complexity: O(1).
pub fn serverless_warm_invocations(s: &ServerlessSystem) -> Int {
  return s.warm_invocations;
}

/// Invocations waiting in the async queue. Complexity: O(1).
pub fn serverless_queued(s: &ServerlessSystem) -> Int {
  return s.queue.len();
}
