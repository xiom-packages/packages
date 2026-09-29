// XIOM -- xiom.executor: task execution engine as a deterministic state machine
// Port task: replace the xiom.executor placeholder with a real, tested,
// pure-XIOM package (no FFI, no threads, no clock).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model: a task execution engine as a pure, deterministic state machine --
// the semantic core a scheduler, thread pool or async runtime would drive.
// There are no threads, no atomics, no clock and no I/O here: the caller (or
// a future backend) owns concurrency and every function is a total transition
// over plain values. The engine owns:
//   * task metadata (ids, priorities, submission order, states) as parallel
//     Vec[Int] fields;
//   * a ready queue with two selection policies: FIFO (queue arrival order)
//     and PRIORITY (largest priority, ties broken by smallest submission
//     sequence -- stable and deterministic);
//   * futures (Pending/Ready/Failed with a value slot and a failure code) that
//     a producing task completes when it reaches DONE or FAILED;
//   * continuations: a future may name one continuation task; when the future
//     reaches a terminal state that task is enqueued exactly once;
//   * a bounded driver loop (executor_run_all) returning the completion order
//     trace, and stats counters (submitted, completed, failed, steps).
//
// Task states:  NEW -> READY -> RUNNING -> DONE | FAILED.
//   NEW      submitted, not yet in the ready queue
//   READY    in the ready queue, waiting for dispatch
//   RUNNING  dispatched by executor_next, not yet terminal
//   DONE     completed successfully (executor_complete)
//   FAILED   completed with a failure code (executor_fail)
// Future states: PENDING -> READY | FAILED.  Both terminal transitions are
// final; a second terminal transition is refused (double-complete), and
// publish-after-failure is refused with a distinct error.
//
// Language notes (XIOM v0.62.1): free functions only; Ok/Err are constructed
// only inside the _ok_*/_err_* leaf helpers; Vec[Int] element reads are bound
// with a typed `let`; parallel Vec fields are pushed and rebuilt together so
// they can never skew; no Vec[StructType], no indexed Vec[fn] dispatch, no
// generic callbacks, no Vec[Float64], no `mut` in match patterns, no FFI, no
// threads, no `log`-named function. Str values are compared only with
// string.str_compare.

module xiom.executor

use xiom.string;
use xiom.convert;

// ---------------------------------------------------------------------------
// Public constants
// ---------------------------------------------------------------------------

/// Ready-queue selection policy: first in, first out (queue arrival order).
pub const EXEC_POLICY_FIFO: Int = 0;

/// Ready-queue selection policy: largest priority first, ties broken by the
/// smallest submission sequence (stable by submission id).
pub const EXEC_POLICY_PRIORITY: Int = 1;

/// Task state: submitted, not yet in the ready queue.
pub const EXEC_TASK_NEW: Int = 0;

/// Task state: in the ready queue, waiting for dispatch.
pub const EXEC_TASK_READY: Int = 1;

/// Task state: dispatched by executor_next, not yet terminal.
pub const EXEC_TASK_RUNNING: Int = 2;

/// Task state: completed successfully.
pub const EXEC_TASK_DONE: Int = 3;

/// Task state: completed with a failure code.
pub const EXEC_TASK_FAILED: Int = 4;

/// Future state: not yet completed.
pub const EXEC_FUTURE_PENDING: Int = 0;

/// Future state: completed with a value.
pub const EXEC_FUTURE_READY: Int = 1;

/// Future state: completed with a failure code.
pub const EXEC_FUTURE_FAILED: Int = 2;

/// Sentinel: no continuation task is attached to a future.
pub const EXEC_NO_CONTINUATION: Int = -1;

/// Sentinel: unknown id / out of range accessor result.
pub const EXEC_NOT_FOUND: Int = -1;

/// Executor state. Every field is an internal implementation detail; callers
/// must go through the executor_*/future_* free functions.
///
/// Tasks are stored as four parallel Vec[Int] fields indexed by task slot:
/// task_ids[i], task_priorities[i], task_orders[i] (the submission sequence
/// assigned by executor_submit) and task_states[i] (an EXEC_TASK_* code).
/// `ready_ids` is the ready queue (index 0 = front); `next_order` is the next
/// submission sequence. Futures are stored as five parallel Vec[Int] fields
/// indexed by future slot: future_ids[i], future_states[i] (an EXEC_FUTURE_*
/// code), future_values[i], future_codes[i] and future_cont[i] (an attached
/// continuation task id or EXEC_NO_CONTINUATION). Counters: `submitted`,
/// `completed`, `failed`, `steps` (successful executor_next dispatches).
/// `completion_order` is the trace of task ids that reached a terminal state,
/// in order.
pub type Executor = {
  policy: Int;
  task_ids: Vec[Int];
  task_priorities: Vec[Int];
  task_orders: Vec[Int];
  task_states: Vec[Int];
  ready_ids: Vec[Int];
  next_order: Int;
  future_ids: Vec[Int];
  future_states: Vec[Int];
  future_values: Vec[Int];
  future_codes: Vec[Int];
  future_cont: Vec[Int];
  submitted: Int;
  completed: Int;
  failed: Int;
  steps: Int;
  completion_order: Vec[Int];
}

// ---------------------------------------------------------------------------
// Result constructors (leaf helpers only; see the header comment)
// ---------------------------------------------------------------------------

fn _ok_exec(v: Executor) -> Result[Executor, Str] { return Ok(v); }
fn _err_exec(m: Str) -> Result[Executor, Str] { return Err(m); }
fn _ok_int(v: Int) -> Result[Int, Str] { return Ok(v); }
fn _err_int(m: Str) -> Result[Int, Str] { return Err(m); }
fn _ok_vec(v: Vec[Int]) -> Result[Vec[Int], Str] { return Ok(v); }
fn _err_vec(m: Str) -> Result[Vec[Int], Str] { return Err(m); }

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

fn _is_valid_policy(policy: Int) -> Bool {
  if policy == EXEC_POLICY_FIFO { return true; }
  if policy == EXEC_POLICY_PRIORITY { return true; }
  return false;
}

// Slot of task `id` in the task metadata vectors, or -1 when unknown.
fn _task_index(e: &Executor, id: Int) -> Int {
  var i = 0;
  while i < e.task_ids.len() {
    let cur: Int = e.task_ids[i];
    if cur == id { return i; }
    i = i + 1;
  }
  return -1;
}

// Slot of future `id` in the future vectors, or -1 when unknown.
fn _future_index(e: &Executor, id: Int) -> Int {
  var i = 0;
  while i < e.future_ids.len() {
    let cur: Int = e.future_ids[i];
    if cur == id { return i; }
    i = i + 1;
  }
  return -1;
}

fn _set_task_state(e: &mut Executor, slot: Int, state: Int) {
  e.task_states[slot] = state;
}

// True when `id` is currently in the ready queue.
fn _queue_has(e: &Executor, id: Int) -> Bool {
  var i = 0;
  while i < e.ready_ids.len() {
    let cur: Int = e.ready_ids[i];
    if cur == id { return true; }
    i = i + 1;
  }
  return false;
}

// NEW -> READY: mark the task ready and append it to the back of the queue.
fn _enqueue_new_task(e: &mut Executor, slot: Int) {
  _set_task_state(e, slot, EXEC_TASK_READY);
  let id: Int = e.task_ids[slot];
  e.ready_ids.push(id);
}

// Remove the ready-queue entry at `idx`, rebuilding the vector in step.
fn _remove_ready_at(e: &mut Executor, idx: Int) {
  var out = Vec[Int].new();
  var i = 0;
  while i < e.ready_ids.len() {
    if i != idx {
      let v: Int = e.ready_ids[i];
      out.push(v);
    }
    i = i + 1;
  }
  e.ready_ids = out;
}

// Ready-queue index selected by `policy`, or -1 when the queue is empty.
// FIFO: index 0. PRIORITY: largest task priority, ties broken by the smallest
// submission sequence (EXEC task_orders); the scan is left-to-right, so the
// earliest queue position wins a residual tie. The caller validates `policy`.
fn _pick_index(e: &Executor, policy: Int) -> Int {
  let n = e.ready_ids.len();
  if n == 0 { return -1; }
  if policy == EXEC_POLICY_FIFO { return 0; }
  var best = 0;
  var i = 1;
  while i < n {
    let cand: Int = e.ready_ids[i];
    let best_id: Int = e.ready_ids[best];
    let cand_slot = _task_index(e, cand);
    let best_slot = _task_index(e, best_id);
    if cand_slot >= 0 && best_slot >= 0 {
      let cand_pr: Int = e.task_priorities[cand_slot];
      let best_pr: Int = e.task_priorities[best_slot];
      var better = false;
      if cand_pr > best_pr { better = true; }
      if cand_pr == best_pr {
        let cand_or: Int = e.task_orders[cand_slot];
        let best_or: Int = e.task_orders[best_slot];
        if cand_or < best_or { better = true; }
      }
      if better { best = i; }
    }
    i = i + 1;
  }
  return best;
}

// Publish a terminal future state. `fi` must be a PENDING future slot; the
// caller checks that first. When the future carries an attached continuation
// task that is still NEW, that task is enqueued here -- the one and only
// enqueue point, so a completed future enqueues its continuation at most once
// (terminal states are final). A continuation that is already queued,
// running or terminal is left untouched (no duplicate queue entry).
fn _publish_future(e: &mut Executor, fi: Int, state: Int, value: Int, code: Int) {
  e.future_states[fi] = state;
  e.future_values[fi] = value;
  e.future_codes[fi] = code;
  let cont: Int = e.future_cont[fi];
  if cont >= 0 {
    let slot = _task_index(e, cont);
    if slot >= 0 {
      let st: Int = e.task_states[slot];
      if st == EXEC_TASK_NEW {
        _enqueue_new_task(e, slot);
      }
    }
  }
}

// Execute the default step for a freshly dispatched task: succeed with the
// task id as the published value. Used by executor_run_all.
fn _step_succeed(e: &mut Executor, id: Int) -> Result[Int, Str] {
  return executor_complete(e, id, id);
}

fn _is_no_ready(msg: Str) -> Bool {
  return string.str_compare(msg, "executor: no ready tasks") == 0;
}

// ---------------------------------------------------------------------------
// Construction and policy
// ---------------------------------------------------------------------------

/// Create an empty executor with the given ready-queue selection policy.
/// Params: policy - EXEC_POLICY_FIFO or EXEC_POLICY_PRIORITY.
/// Returns: Ok(Executor); Err("executor: unknown policy") for any other code.
/// Complexity: O(1).
pub fn executor_new(policy: Int) -> Result[Executor, Str] {
  if !_is_valid_policy(policy) {
    return _err_exec("executor: unknown policy");
  }
  return _ok_exec(Executor{
    policy: policy;
    task_ids: Vec[Int].new();
    task_priorities: Vec[Int].new();
    task_orders: Vec[Int].new();
    task_states: Vec[Int].new();
    ready_ids: Vec[Int].new();
    next_order: 0;
    future_ids: Vec[Int].new();
    future_states: Vec[Int].new();
    future_values: Vec[Int].new();
    future_codes: Vec[Int].new();
    future_cont: Vec[Int].new();
    submitted: 0;
    completed: 0;
    failed: 0;
    steps: 0;
    completion_order: Vec[Int].new();
  });
}

/// Change the ready-queue selection policy.
/// Params: e - the executor; policy - EXEC_POLICY_FIFO or
///         EXEC_POLICY_PRIORITY.
/// Returns: Ok(policy) on success; Err("executor: unknown policy") otherwise
/// (state unchanged).
/// Complexity: O(1).
pub fn executor_set_policy(e: &mut Executor, policy: Int) -> Result[Int, Str] {
  if !_is_valid_policy(policy) {
    return _err_int("executor: unknown policy");
  }
  e.policy = policy;
  return _ok_int(policy);
}

/// Active ready-queue selection policy. Complexity: O(1).
pub fn executor_policy(e: &Executor) -> Int {
  return e.policy;
}

// ---------------------------------------------------------------------------
// Submission and the ready queue
// ---------------------------------------------------------------------------

/// Submit a task. The task starts NEW (not queued); call executor_enqueue to
/// make it dispatchable, or executor_submit_ready to do both at once. The
/// submission sequence returned here is the tie-breaker of the PRIORITY
/// policy.
/// Params: e - the executor; id - caller-assigned task id, unique, >= 0;
///         priority - scheduling priority, >= 0 (larger = more urgent).
/// Returns: Ok(order) with the 0-based submission sequence; Err("executor:
/// task id must be >= 0"), Err("executor: priority must be >= 0") or
/// Err("executor: duplicate task id") -- in every Err case the state is
/// unchanged. A successful submit increments the submitted counter.
/// Complexity: O(task count) (duplicate scan).
pub fn executor_submit(e: &mut Executor, id: Int, priority: Int) -> Result[Int, Str] {
  if id < 0 {
    return _err_int("executor: task id must be >= 0");
  }
  if priority < 0 {
    return _err_int("executor: priority must be >= 0");
  }
  if _task_index(e, id) >= 0 {
    return _err_int("executor: duplicate task id");
  }
  let order = e.next_order;
  e.task_ids.push(id);
  e.task_priorities.push(priority);
  e.task_orders.push(order);
  e.task_states.push(EXEC_TASK_NEW);
  e.next_order = order + 1;
  e.submitted = e.submitted + 1;
  return _ok_int(order);
}

/// Move a NEW task into the ready queue (NEW -> READY).
/// Params: e - the executor; id - task id.
/// Returns: Ok(position) with the append position in the queue (under the
/// PRIORITY policy this is not the dispatch order); Err("executor: unknown
/// task id"), Err("executor: task already queued"), Err("executor: task
/// already running"), Err("executor: task already complete") or
/// Err("executor: task already failed") -- in every Err case the state is
/// unchanged.
/// Complexity: O(task count) (id lookup).
pub fn executor_enqueue(e: &mut Executor, id: Int) -> Result[Int, Str] {
  let slot = _task_index(e, id);
  if slot < 0 {
    return _err_int("executor: unknown task id");
  }
  let st: Int = e.task_states[slot];
  if st == EXEC_TASK_READY {
    return _err_int("executor: task already queued");
  }
  if st == EXEC_TASK_RUNNING {
    return _err_int("executor: task already running");
  }
  if st == EXEC_TASK_DONE {
    return _err_int("executor: task already complete");
  }
  if st == EXEC_TASK_FAILED {
    return _err_int("executor: task already failed");
  }
  _enqueue_new_task(e, slot);
  return _ok_int(e.ready_ids.len() - 1);
}

/// Submit and enqueue in one step: executor_submit followed by
/// executor_enqueue. Errors carry the same messages as those functions.
/// Params: e - the executor; id - task id; priority - priority, >= 0.
/// Returns: Ok(position) as executor_enqueue; when submit fails nothing is
/// submitted.
/// Complexity: O(task count).
pub fn executor_submit_ready(e: &mut Executor, id: Int, priority: Int) -> Result[Int, Str] {
  match executor_submit(e, id, priority) {
    Ok(_) => {},
    Err(m) => { return _err_int(m); },
  }
  return executor_enqueue(e, id);
}

/// Number of tasks currently in the ready queue. Complexity: O(1).
pub fn executor_ready_len(e: &Executor) -> Int {
  return e.ready_ids.len();
}

/// Copy of the ready-queue task ids, front first. Complexity: O(queue len).
pub fn executor_ready_ids(e: &Executor) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 0;
  while i < e.ready_ids.len() {
    let id: Int = e.ready_ids[i];
    out.push(id);
    i = i + 1;
  }
  return out;
}

// ---------------------------------------------------------------------------
// Dispatch (READY -> RUNNING)
// ---------------------------------------------------------------------------

/// Dispatch the next ready task under an explicit policy.
/// Selection rule: FIFO takes the queue front; PRIORITY takes the largest
/// task priority with ties broken by the smallest submission sequence (a
/// total, deterministic order).
/// Params: e - the executor; policy - EXEC_POLICY_FIFO or
///         EXEC_POLICY_PRIORITY.
/// Returns: Ok(task id) with the task moved READY -> RUNNING; Err("executor:
/// no ready tasks") when the queue is empty; Err("executor: unknown policy")
/// for any other policy code. In every Err case the state is unchanged. A
/// successful dispatch increments the steps counter.
/// Complexity: O(queue length * task count) (selection scan with lookups).
pub fn executor_next_policy(e: &mut Executor, policy: Int) -> Result[Int, Str] {
  if !_is_valid_policy(policy) {
    return _err_int("executor: unknown policy");
  }
  if e.ready_ids.len() == 0 {
    return _err_int("executor: no ready tasks");
  }
  let idx = _pick_index(e, policy);
  let id: Int = e.ready_ids[idx];
  _remove_ready_at(e, idx);
  let slot = _task_index(e, id);
  _set_task_state(e, slot, EXEC_TASK_RUNNING);
  e.steps = e.steps + 1;
  return _ok_int(id);
}

/// Dispatch the next ready task under the executor's active policy. Same
/// contract as executor_next_policy with policy = executor_policy(e).
/// Complexity: O(queue length * task count).
pub fn executor_next(e: &mut Executor) -> Result[Int, Str] {
  let policy = e.policy;
  return executor_next_policy(e, policy);
}

// ---------------------------------------------------------------------------
// Task completion (RUNNING -> DONE | FAILED)
// ---------------------------------------------------------------------------

/// Complete a RUNNING task successfully. If a future with the same id exists
/// and is still PENDING it is set READY with `value`; that future's attached
/// continuation (if any) is then enqueued exactly once (see the continuation
/// rule). When no such future exists, or it is already terminal, the task
/// completion still succeeds and nothing else changes.
/// Params: e - the executor; id - task id; value - the result value
///         published to the same-id future.
/// Returns: Ok(completed count) on success; Err("executor: unknown task id"),
/// Err("executor: task is not running"), Err("executor: task already
/// complete") or Err("executor: task already failed") -- in every Err case
/// the state is unchanged. A successful completion appends the id to the
/// completion order trace and increments the completed counter.
/// Complexity: O(task count + future count).
pub fn executor_complete(e: &mut Executor, id: Int, value: Int) -> Result[Int, Str] {
  let slot = _task_index(e, id);
  if slot < 0 {
    return _err_int("executor: unknown task id");
  }
  let st: Int = e.task_states[slot];
  if st == EXEC_TASK_DONE {
    return _err_int("executor: task already complete");
  }
  if st == EXEC_TASK_FAILED {
    return _err_int("executor: task already failed");
  }
  if st != EXEC_TASK_RUNNING {
    return _err_int("executor: task is not running");
  }
  _set_task_state(e, slot, EXEC_TASK_DONE);
  e.completed = e.completed + 1;
  e.completion_order.push(id);
  let fi = _future_index(e, id);
  if fi >= 0 {
    let fst: Int = e.future_states[fi];
    if fst == EXEC_FUTURE_PENDING {
      _publish_future(e, fi, EXEC_FUTURE_READY, value, 0);
    }
  }
  return _ok_int(e.completed);
}

/// Complete a RUNNING task with a failure code. If a future with the same id
/// exists and is still PENDING it is set FAILED with `code`; that future's
/// attached continuation (if any) is then enqueued exactly once (a failed
/// future notifies its continuation just like a ready one).
/// Params: e - the executor; id - task id; code - the failure code published
///         to the same-id future.
/// Returns: Ok(failed count) on success; Err("executor: unknown task id"),
/// Err("executor: task is not running"), Err("executor: task already
/// complete") or Err("executor: task already failed") -- in every Err case
/// the state is unchanged. A successful failure appends the id to the
/// completion order trace and increments the failed counter.
/// Complexity: O(task count + future count).
pub fn executor_fail(e: &mut Executor, id: Int, code: Int) -> Result[Int, Str] {
  let slot = _task_index(e, id);
  if slot < 0 {
    return _err_int("executor: unknown task id");
  }
  let st: Int = e.task_states[slot];
  if st == EXEC_TASK_DONE {
    return _err_int("executor: task already complete");
  }
  if st == EXEC_TASK_FAILED {
    return _err_int("executor: task already failed");
  }
  if st != EXEC_TASK_RUNNING {
    return _err_int("executor: task is not running");
  }
  _set_task_state(e, slot, EXEC_TASK_FAILED);
  e.failed = e.failed + 1;
  e.completion_order.push(id);
  let fi = _future_index(e, id);
  if fi >= 0 {
    let fst: Int = e.future_states[fi];
    if fst == EXEC_FUTURE_PENDING {
      _publish_future(e, fi, EXEC_FUTURE_FAILED, 0, code);
    }
  }
  return _ok_int(e.failed);
}

// ---------------------------------------------------------------------------
// Driver loop
// ---------------------------------------------------------------------------

/// Drive the executor to quiescence: repeatedly dispatch the next ready task
/// under the executor's active policy and complete it successfully with the
/// task id as its value (a continuation enqueued by a completed future is
/// picked up by later iterations). The loop stops when the ready queue is
/// empty (Ok) or when it would exceed `max_steps` dispatches (Err).
/// Params: e - the executor; max_steps - dispatch bound, >= 0.
/// Returns: Ok(trace) with the task ids completed by THIS run, in completion
/// order (empty when nothing was ready); Err("executor: max_steps must be
/// >= 0"); Err("executor: step limit exceeded") when the bound is reached
/// while work remains (states reached so far are retained, no trace is
/// returned); other transition errors are surfaced unchanged.
/// Complexity: O(max_steps * task count).
pub fn executor_run_all(e: &mut Executor, max_steps: Int) -> Result[Vec[Int], Str] {
  if max_steps < 0 {
    return _err_vec("executor: max_steps must be >= 0");
  }
  var trace = Vec[Int].new();
  var dispatched = 0;
  while true {
    if dispatched >= max_steps {
      if e.ready_ids.len() > 0 {
        return _err_vec("executor: step limit exceeded");
      }
      return _ok_vec(trace);
    }
    let nxt = executor_next(e);
    match nxt {
      Ok(id) => {
        let done = _step_succeed(e, id);
        match done {
          Ok(_) => { trace.push(id); },
          Err(m) => { return _err_vec(m); },
        }
        dispatched = dispatched + 1;
      },
      Err(m) => {
        if _is_no_ready(m) { return _ok_vec(trace); }
        return _err_vec(m);
      },
    }
  }
  return _ok_vec(trace);
}

// ---------------------------------------------------------------------------
// Futures
// ---------------------------------------------------------------------------

/// Create a future in the PENDING state with empty slots (value 0, failure
/// code 0, no continuation).
/// Params: e - the executor; id - caller-assigned future id, unique, >= 0.
/// Returns: Ok(id); Err("executor: future id must be >= 0") or
/// Err("executor: duplicate future id") -- in every Err case the state is
/// unchanged.
/// Complexity: O(future count).
pub fn future_new(e: &mut Executor, id: Int) -> Result[Int, Str] {
  if id < 0 {
    return _err_int("executor: future id must be >= 0");
  }
  if _future_index(e, id) >= 0 {
    return _err_int("executor: duplicate future id");
  }
  e.future_ids.push(id);
  e.future_states.push(EXEC_FUTURE_PENDING);
  e.future_values.push(0);
  e.future_codes.push(0);
  e.future_cont.push(EXEC_NO_CONTINUATION);
  return _ok_int(id);
}

/// Attach a continuation task to a PENDING future. When the future reaches a
/// terminal state the continuation is enqueued exactly once (only while the
/// task is still NEW; a task already queued, running or terminal is left
/// untouched, so the queue never gains a duplicate entry). At most one
/// continuation per future.
/// Params: e - the executor; future_id - the future; task_id - the task to
///         enqueue on completion (must be submitted already).
/// Returns: Ok(task id); Err("executor: unknown future id"), Err("executor:
/// future already ready"), Err("executor: future already failed"),
/// Err("executor: unknown task id"), Err("executor: continuation task
/// already complete"), Err("executor: continuation task already failed") or
/// Err("executor: future already has a continuation") -- in every Err case
/// the state is unchanged.
/// Complexity: O(task count + future count).
pub fn future_attach_continuation(e: &mut Executor, future_id: Int, task_id: Int) -> Result[Int, Str] {
  let fi = _future_index(e, future_id);
  if fi < 0 {
    return _err_int("executor: unknown future id");
  }
  let fst: Int = e.future_states[fi];
  if fst == EXEC_FUTURE_READY {
    return _err_int("executor: future already ready");
  }
  if fst == EXEC_FUTURE_FAILED {
    return _err_int("executor: future already failed");
  }
  let slot = _task_index(e, task_id);
  if slot < 0 {
    return _err_int("executor: unknown task id");
  }
  let tst: Int = e.task_states[slot];
  if tst == EXEC_TASK_DONE {
    return _err_int("executor: continuation task already complete");
  }
  if tst == EXEC_TASK_FAILED {
    return _err_int("executor: continuation task already failed");
  }
  let current: Int = e.future_cont[fi];
  if current >= 0 {
    return _err_int("executor: future already has a continuation");
  }
  e.future_cont[fi] = task_id;
  return _ok_int(task_id);
}

/// Complete a PENDING future with a value.
/// Params: e - the executor; id - future id; value - the value slot.
/// Returns: Ok(value); Err("executor: unknown future id"); Err("executor:
/// future already complete") when the future is already READY (double
/// complete); Err("executor: future already failed") when it is FAILED
/// (complete-after-failure). In every Err case the state is unchanged.
/// Complexity: O(future count + task count).
pub fn future_set_ready(e: &mut Executor, id: Int, value: Int) -> Result[Int, Str] {
  let fi = _future_index(e, id);
  if fi < 0 {
    return _err_int("executor: unknown future id");
  }
  let st: Int = e.future_states[fi];
  if st == EXEC_FUTURE_PENDING {
    _publish_future(e, fi, EXEC_FUTURE_READY, value, 0);
    return _ok_int(value);
  }
  if st == EXEC_FUTURE_FAILED {
    return _err_int("executor: future already failed");
  }
  return _err_int("executor: future already complete");
}

/// Complete a PENDING future with a failure code.
/// Params: e - the executor; id - future id; code - the failure code slot.
/// Returns: Ok(code); Err("executor: unknown future id"); Err("executor:
/// future already complete") when the future is already READY or already
/// FAILED (double complete). In every Err case the state is unchanged.
/// Complexity: O(future count + task count).
pub fn future_set_failed(e: &mut Executor, id: Int, code: Int) -> Result[Int, Str] {
  let fi = _future_index(e, id);
  if fi < 0 {
    return _err_int("executor: unknown future id");
  }
  let st: Int = e.future_states[fi];
  if st == EXEC_FUTURE_PENDING {
    _publish_future(e, fi, EXEC_FUTURE_FAILED, 0, code);
    return _ok_int(code);
  }
  if st == EXEC_FUTURE_READY {
    return _err_int("executor: future already complete");
  }
  return _err_int("executor: future already complete");
}

// ---------------------------------------------------------------------------
// Task and future accessors (read-only)
// ---------------------------------------------------------------------------

/// Number of submitted tasks (tasks are never removed). Complexity: O(1).
pub fn executor_task_count(e: &Executor) -> Int {
  return e.task_ids.len();
}

/// True when a task with `id` exists. Complexity: O(task count).
pub fn executor_has_task(e: &Executor, id: Int) -> Bool {
  return _task_index(e, id) >= 0;
}

/// State code of task `id` (an EXEC_TASK_* value), or EXEC_NOT_FOUND (-1)
/// when unknown. Complexity: O(task count).
pub fn executor_task_state(e: &Executor, id: Int) -> Int {
  let slot = _task_index(e, id);
  if slot < 0 { return EXEC_NOT_FOUND; }
  let st: Int = e.task_states[slot];
  return st;
}

/// Priority of task `id`, or EXEC_NOT_FOUND (-1) when unknown.
/// Complexity: O(task count).
pub fn executor_task_priority(e: &Executor, id: Int) -> Int {
  let slot = _task_index(e, id);
  if slot < 0 { return EXEC_NOT_FOUND; }
  let pr: Int = e.task_priorities[slot];
  return pr;
}

/// Submission sequence of task `id`, or EXEC_NOT_FOUND (-1) when unknown.
/// Complexity: O(task count).
pub fn executor_task_order(e: &Executor, id: Int) -> Int {
  let slot = _task_index(e, id);
  if slot < 0 { return EXEC_NOT_FOUND; }
  let ord: Int = e.task_orders[slot];
  return ord;
}

/// Number of created futures. Complexity: O(1).
pub fn executor_future_count(e: &Executor) -> Int {
  return e.future_ids.len();
}

/// True when a future with `id` exists. Complexity: O(future count).
pub fn executor_has_future(e: &Executor, id: Int) -> Bool {
  return _future_index(e, id) >= 0;
}

/// State code of future `id` (an EXEC_FUTURE_* value), or EXEC_NOT_FOUND (-1)
/// when unknown. Complexity: O(future count).
pub fn executor_future_state(e: &Executor, id: Int) -> Int {
  let fi = _future_index(e, id);
  if fi < 0 { return EXEC_NOT_FOUND; }
  let st: Int = e.future_states[fi];
  return st;
}

/// Value slot of future `id` (0 while unset), or EXEC_NOT_FOUND (-1) when
/// unknown. Complexity: O(future count).
pub fn executor_future_value(e: &Executor, id: Int) -> Int {
  let fi = _future_index(e, id);
  if fi < 0 { return EXEC_NOT_FOUND; }
  let v: Int = e.future_values[fi];
  return v;
}

/// Failure code slot of future `id` (0 while unset), or EXEC_NOT_FOUND (-1)
/// when unknown. Complexity: O(future count).
pub fn executor_future_code(e: &Executor, id: Int) -> Int {
  let fi = _future_index(e, id);
  if fi < 0 { return EXEC_NOT_FOUND; }
  let c: Int = e.future_codes[fi];
  return c;
}

/// Continuation task id attached to future `id`, or EXEC_NO_CONTINUATION
/// (-1) when none is attached or the future is unknown.
/// Complexity: O(future count).
pub fn executor_future_continuation(e: &Executor, id: Int) -> Int {
  let fi = _future_index(e, id);
  if fi < 0 { return EXEC_NO_CONTINUATION; }
  let c: Int = e.future_cont[fi];
  return c;
}

/// True when future `id` exists and carries a continuation.
/// Complexity: O(future count).
pub fn executor_future_has_continuation(e: &Executor, id: Int) -> Bool {
  return executor_future_continuation(e, id) >= 0;
}

// ---------------------------------------------------------------------------
// Stats and trace
// ---------------------------------------------------------------------------

/// Successful executor_submit calls. Complexity: O(1).
pub fn executor_submitted(e: &Executor) -> Int {
  return e.submitted;
}

/// Successful executor_complete calls. Complexity: O(1).
pub fn executor_completed(e: &Executor) -> Int {
  return e.completed;
}

/// Successful executor_fail calls. Complexity: O(1).
pub fn executor_failed(e: &Executor) -> Int {
  return e.failed;
}

/// Successful executor_next / executor_next_policy dispatches.
/// Complexity: O(1).
pub fn executor_steps(e: &Executor) -> Int {
  return e.steps;
}

/// Length of the completion order trace. Complexity: O(1).
pub fn executor_trace_len(e: &Executor) -> Int {
  return e.completion_order.len();
}

/// Copy of the completion order trace: task ids in the order they reached a
/// terminal state (DONE or FAILED). Complexity: O(trace length).
pub fn executor_trace(e: &Executor) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 0;
  while i < e.completion_order.len() {
    let id: Int = e.completion_order[i];
    out.push(id);
    i = i + 1;
  }
  return out;
}

/// Completion order trace rendered as comma-separated task ids, "" when
/// empty. Complexity: O(trace length).
pub fn executor_trace_text(e: &Executor) -> Str {
  var out = "";
  var i = 0;
  while i < e.completion_order.len() {
    let id: Int = e.completion_order[i];
    if i > 0 { out = out + ","; }
    out = out + convert.int_to_string(id);
    i = i + 1;
  }
  return out;
}

// ---------------------------------------------------------------------------
// Names and invariant check
// ---------------------------------------------------------------------------

/// Human-readable policy name: "fifo", "priority" or "unknown".
/// Complexity: O(1).
pub fn executor_policy_name(policy: Int) -> Str {
  if policy == EXEC_POLICY_FIFO { return "fifo"; }
  if policy == EXEC_POLICY_PRIORITY { return "priority"; }
  return "unknown";
}

/// Human-readable task state name, or "unknown" for an unknown code.
/// Complexity: O(1).
pub fn executor_task_state_name(state: Int) -> Str {
  if state == EXEC_TASK_NEW { return "new"; }
  if state == EXEC_TASK_READY { return "ready"; }
  if state == EXEC_TASK_RUNNING { return "running"; }
  if state == EXEC_TASK_DONE { return "done"; }
  if state == EXEC_TASK_FAILED { return "failed"; }
  return "unknown";
}

/// Human-readable future state name, or "unknown" for an unknown code.
/// Complexity: O(1).
pub fn executor_future_state_name(state: Int) -> Str {
  if state == EXEC_FUTURE_PENDING { return "pending"; }
  if state == EXEC_FUTURE_READY { return "ready"; }
  if state == EXEC_FUTURE_FAILED { return "failed"; }
  return "unknown";
}

/// Structural invariant of an executor, true exactly when:
/// 1. the four task vectors have equal length and submitted == that length,
///    and next_order is that length;
/// 2. every task id is >= 0 and unique; every priority is >= 0; task_orders[i]
///    == i (submission sequences are dense and ascending); every state is an
///    EXEC_TASK_* code;
/// 3. every ready-queue id names a task in state READY, with no duplicates,
///    and every READY task is queued exactly once;
/// 4. completed == number of DONE tasks; failed == number of FAILED tasks;
///    steps == DONE + FAILED + RUNNING;
/// 5. the completion order trace lists each terminal task exactly once, in
///    order, and its length is completed + failed;
/// 6. the five future vectors have equal length; every future id is >= 0 and
///    unique; every future state is an EXEC_FUTURE_* code; every attached
///    continuation names an existing task.
/// Complexity: O(task count^2 + future count^2).
pub fn executor_check_invariant(e: &Executor) -> Bool {
  let n = e.task_ids.len();
  if e.task_priorities.len() != n { return false; }
  if e.task_orders.len() != n { return false; }
  if e.task_states.len() != n { return false; }
  if e.submitted != n { return false; }
  if e.next_order != n { return false; }
  var i = 0;
  while i < n {
    let id: Int = e.task_ids[i];
    let pr: Int = e.task_priorities[i];
    let ord: Int = e.task_orders[i];
    let st: Int = e.task_states[i];
    if id < 0 { return false; }
    if pr < 0 { return false; }
    if ord != i { return false; }
    if st < EXEC_TASK_NEW { return false; }
    if st > EXEC_TASK_FAILED { return false; }
    var j = i + 1;
    while j < n {
      let other: Int = e.task_ids[j];
      if other == id { return false; }
      j = j + 1;
    }
    i = i + 1;
  }
  var r = 0;
  while r < e.ready_ids.len() {
    let rid: Int = e.ready_ids[r];
    let rslot = _task_index(e, rid);
    if rslot < 0 { return false; }
    let rst: Int = e.task_states[rslot];
    if rst != EXEC_TASK_READY { return false; }
    var r2 = r + 1;
    while r2 < e.ready_ids.len() {
      let other: Int = e.ready_ids[r2];
      if other == rid { return false; }
      r2 = r2 + 1;
    }
    r = r + 1;
  }
  var k = 0;
  while k < n {
    let st: Int = e.task_states[k];
    if st == EXEC_TASK_READY {
      let idk: Int = e.task_ids[k];
      if !_queue_has(e, idk) { return false; }
    }
    k = k + 1;
  }
  var done = 0;
  var bad = 0;
  var running = 0;
  var t = 0;
  while t < n {
    let st: Int = e.task_states[t];
    if st == EXEC_TASK_DONE { done = done + 1; }
    if st == EXEC_TASK_FAILED { bad = bad + 1; }
    if st == EXEC_TASK_RUNNING { running = running + 1; }
    t = t + 1;
  }
  if e.completed != done { return false; }
  if e.failed != bad { return false; }
  if e.steps != done + bad + running { return false; }
  if e.completion_order.len() != done + bad { return false; }
  var q = 0;
  while q < e.completion_order.len() {
    let tid: Int = e.completion_order[q];
    let qslot = _task_index(e, tid);
    if qslot < 0 { return false; }
    let qst: Int = e.task_states[qslot];
    if qst != EXEC_TASK_DONE && qst != EXEC_TASK_FAILED { return false; }
    var q2 = q + 1;
    while q2 < e.completion_order.len() {
      let other: Int = e.completion_order[q2];
      if other == tid { return false; }
      q2 = q2 + 1;
    }
    q = q + 1;
  }
  let nf = e.future_ids.len();
  if e.future_states.len() != nf { return false; }
  if e.future_values.len() != nf { return false; }
  if e.future_codes.len() != nf { return false; }
  if e.future_cont.len() != nf { return false; }
  var f = 0;
  while f < nf {
    let fid: Int = e.future_ids[f];
    let fst: Int = e.future_states[f];
    if fid < 0 { return false; }
    if fst < EXEC_FUTURE_PENDING { return false; }
    if fst > EXEC_FUTURE_FAILED { return false; }
    let cont: Int = e.future_cont[f];
    if cont >= 0 {
      if _task_index(e, cont) < 0 { return false; }
    }
    var f2 = f + 1;
    while f2 < nf {
      let other: Int = e.future_ids[f2];
      if other == fid { return false; }
      f2 = f2 + 1;
    }
    f = f + 1;
  }
  return true;
}
