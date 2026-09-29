// XIOM -- xiom.executor conformance tests (26 checks)
// Port task: prove the pure-XIOM xiom.executor state machine against its
// documented API (submission, FIFO/priority dispatch, futures, continuations,
// the bounded run_all driver, stats and the structural invariant).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// All Str equality goes through str_compare: `==` on Str values read from
// Vec[Str] elements lowers to a pointer comparison, so every message and text
// check below is routed through streq. Vec[Int] element reads use a typed
// `let`. Read-only operations are wrapped in small helpers that take `&mut`,
// so a `&local` read call is never followed by a `&mut local` call in the
// same function body (advisory E001); each helper calls the real `&`-based
// API. Int-code classifiers turn Result/Option outcomes into small Int codes
// so test bodies stay branch-free.

module executor_tests
use xiom.io; use xiom.test; use xiom.executor;
use xiom.string.compare;

const _E_POLICY: Str = "executor: unknown policy";
const _E_TASK_ID: Str = "executor: task id must be >= 0";
const _E_PRIO: Str = "executor: priority must be >= 0";
const _E_DUP_TASK: Str = "executor: duplicate task id";
const _E_UNKNOWN_TASK: Str = "executor: unknown task id";
const _E_QUEUED: Str = "executor: task already queued";
const _E_RUNNING: Str = "executor: task already running";
const _E_TASK_DONE: Str = "executor: task already complete";
const _E_TASK_FAILED: Str = "executor: task already failed";
const _E_NOT_RUNNING: Str = "executor: task is not running";
const _E_NO_READY: Str = "executor: no ready tasks";
const _E_LIMIT: Str = "executor: step limit exceeded";
const _E_MAXSTEPS: Str = "executor: max_steps must be >= 0";
const _E_FUT_ID: Str = "executor: future id must be >= 0";
const _E_DUP_FUT: Str = "executor: duplicate future id";
const _E_UNKNOWN_FUT: Str = "executor: unknown future id";
const _E_FUT_COMPLETE: Str = "executor: future already complete";
const _E_FUT_READY: Str = "executor: future already ready";
const _E_FUT_FAILED: Str = "executor: future already failed";
const _E_CONT_DONE: Str = "executor: continuation task already complete";
const _E_CONT_FAILED: Str = "executor: continuation task already failed";
const _E_HAS_CONT: Str = "executor: future already has a continuation";

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// Fixture: the Err branch is unreachable for the policies the tests pass, but
// the function must still return an Executor value.
fn empty_exec(policy: Int) -> Executor {
  return Executor{
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
  };
}

fn e_of(policy: Int) -> Executor {
  match executor_new(policy) {
    Ok(e) => { return e; },
    Err(_) => { return empty_exec(policy); },
  }
}

fn new_err_is(policy: Int, want: Str) -> Bool {
  match executor_new(policy) {
    Ok(_) => { return false; },
    Err(m) => { return streq(m, want); },
  }
  return false;
}

// Read-only accessors routed through `&mut` (advisory E001).

fn policy_of(e: &mut Executor) -> Int {
  return executor_policy(e);
}

fn ready_len_of(e: &mut Executor) -> Int {
  return executor_ready_len(e);
}

fn ready_ids_of(e: &mut Executor) -> Vec[Int] {
  return executor_ready_ids(e);
}

fn task_count_of(e: &mut Executor) -> Int {
  return executor_task_count(e);
}

fn has_task_of(e: &mut Executor, id: Int) -> Bool {
  return executor_has_task(e, id);
}

fn state_of(e: &mut Executor, id: Int) -> Int {
  return executor_task_state(e, id);
}

fn prio_of(e: &mut Executor, id: Int) -> Int {
  return executor_task_priority(e, id);
}

fn order_of(e: &mut Executor, id: Int) -> Int {
  return executor_task_order(e, id);
}

fn future_count_of(e: &mut Executor) -> Int {
  return executor_future_count(e);
}

fn has_future_of(e: &mut Executor, id: Int) -> Bool {
  return executor_has_future(e, id);
}

fn fstate_of(e: &mut Executor, id: Int) -> Int {
  return executor_future_state(e, id);
}

fn fvalue_of(e: &mut Executor, id: Int) -> Int {
  return executor_future_value(e, id);
}

fn fcode_of(e: &mut Executor, id: Int) -> Int {
  return executor_future_code(e, id);
}

fn fcont_of(e: &mut Executor, id: Int) -> Int {
  return executor_future_continuation(e, id);
}

fn fhas_cont_of(e: &mut Executor, id: Int) -> Bool {
  return executor_future_has_continuation(e, id);
}

fn submitted_of(e: &mut Executor) -> Int {
  return executor_submitted(e);
}

fn completed_of(e: &mut Executor) -> Int {
  return executor_completed(e);
}

fn failed_of(e: &mut Executor) -> Int {
  return executor_failed(e);
}

fn steps_of(e: &mut Executor) -> Int {
  return executor_steps(e);
}

fn trace_len_of(e: &mut Executor) -> Int {
  return executor_trace_len(e);
}

fn trace_of(e: &mut Executor) -> Vec[Int] {
  return executor_trace(e);
}

fn trace_text_of(e: &mut Executor) -> Str {
  return executor_trace_text(e);
}

fn invariant_of(e: &mut Executor) -> Bool {
  return executor_check_invariant(e);
}

// Outcome classifiers: Int codes keep the tests readable.

// Submission order on success, -1 on any error.
fn submit_ok(e: &mut Executor, id: Int, prio: Int) -> Int {
  match executor_submit(e, id, prio) {
    Ok(order) => { return order; },
    Err(_) => { return -1; },
  }
  return -1;
}

fn submit_err_is(e: &mut Executor, id: Int, prio: Int, want: Str) -> Bool {
  match executor_submit(e, id, prio) {
    Ok(_) => { return false; },
    Err(m) => { return streq(m, want); },
  }
  return false;
}

// Queue position on success, -1 on any error.
fn submit_ready_ok(e: &mut Executor, id: Int, prio: Int) -> Int {
  match executor_submit_ready(e, id, prio) {
    Ok(pos) => { return pos; },
    Err(_) => { return -1; },
  }
  return -1;
}

fn enqueue_ok(e: &mut Executor, id: Int) -> Int {
  match executor_enqueue(e, id) {
    Ok(pos) => { return pos; },
    Err(_) => { return -1; },
  }
  return -1;
}

fn enqueue_err_is(e: &mut Executor, id: Int, want: Str) -> Bool {
  match executor_enqueue(e, id) {
    Ok(_) => { return false; },
    Err(m) => { return streq(m, want); },
  }
  return false;
}

// Dispatched task id, -1 on any error.
fn next_id_or_neg(e: &mut Executor) -> Int {
  match executor_next(e) {
    Ok(id) => { return id; },
    Err(_) => { return -1; },
  }
  return -1;
}

fn next_err_is(e: &mut Executor, want: Str) -> Bool {
  match executor_next(e) {
    Ok(_) => { return false; },
    Err(m) => { return streq(m, want); },
  }
  return false;
}

// Dispatched task id under an explicit policy, -1 on any error.
fn next_policy_id(e: &mut Executor, policy: Int) -> Int {
  match executor_next_policy(e, policy) {
    Ok(id) => { return id; },
    Err(_) => { return -1; },
  }
  return -1;
}

fn next_policy_err_is(e: &mut Executor, policy: Int, want: Str) -> Bool {
  match executor_next_policy(e, policy) {
    Ok(_) => { return false; },
    Err(m) => { return streq(m, want); },
  }
  return false;
}

// Completed count on success, -1 on any error.
fn complete_ok(e: &mut Executor, id: Int, value: Int) -> Int {
  match executor_complete(e, id, value) {
    Ok(n) => { return n; },
    Err(_) => { return -1; },
  }
  return -1;
}

fn complete_err_is(e: &mut Executor, id: Int, value: Int, want: Str) -> Bool {
  match executor_complete(e, id, value) {
    Ok(_) => { return false; },
    Err(m) => { return streq(m, want); },
  }
  return false;
}

// Failed count on success, -1 on any error.
fn fail_ok(e: &mut Executor, id: Int, code: Int) -> Int {
  match executor_fail(e, id, code) {
    Ok(n) => { return n; },
    Err(_) => { return -1; },
  }
  return -1;
}

fn fail_err_is(e: &mut Executor, id: Int, code: Int, want: Str) -> Bool {
  match executor_fail(e, id, code) {
    Ok(_) => { return false; },
    Err(m) => { return streq(m, want); },
  }
  return false;
}

fn set_policy_ok(e: &mut Executor, policy: Int) -> Int {
  match executor_set_policy(e, policy) {
    Ok(p) => { return p; },
    Err(_) => { return -1; },
  }
  return -1;
}

fn set_policy_err_is(e: &mut Executor, policy: Int, want: Str) -> Bool {
  match executor_set_policy(e, policy) {
    Ok(_) => { return false; },
    Err(m) => { return streq(m, want); },
  }
  return false;
}

// Future id on success, -1 on any error.
fn future_new_ok(e: &mut Executor, id: Int) -> Int {
  match future_new(e, id) {
    Ok(fid) => { return fid; },
    Err(_) => { return -1; },
  }
  return -1;
}

fn future_new_err_is(e: &mut Executor, id: Int, want: Str) -> Bool {
  match future_new(e, id) {
    Ok(_) => { return false; },
    Err(m) => { return streq(m, want); },
  }
  return false;
}

// Continuation task id on success, -1 on any error.
fn attach_ok(e: &mut Executor, fid: Int, tid: Int) -> Int {
  match future_attach_continuation(e, fid, tid) {
    Ok(id) => { return id; },
    Err(_) => { return -1; },
  }
  return -1;
}

fn attach_err_is(e: &mut Executor, fid: Int, tid: Int, want: Str) -> Bool {
  match future_attach_continuation(e, fid, tid) {
    Ok(_) => { return false; },
    Err(m) => { return streq(m, want); },
  }
  return false;
}

// Published value on success, -1 on any error.
fn set_ready_ok(e: &mut Executor, id: Int, value: Int) -> Int {
  match future_set_ready(e, id, value) {
    Ok(v) => { return v; },
    Err(_) => { return -1; },
  }
  return -1;
}

fn set_ready_err_is(e: &mut Executor, id: Int, value: Int, want: Str) -> Bool {
  match future_set_ready(e, id, value) {
    Ok(_) => { return false; },
    Err(m) => { return streq(m, want); },
  }
  return false;
}

// Published code on success, -1 on any error.
fn set_failed_ok(e: &mut Executor, id: Int, code: Int) -> Int {
  match future_set_failed(e, id, code) {
    Ok(c) => { return c; },
    Err(_) => { return -1; },
  }
  return -1;
}

fn set_failed_err_is(e: &mut Executor, id: Int, code: Int, want: Str) -> Bool {
  match future_set_failed(e, id, code) {
    Ok(_) => { return false; },
    Err(m) => { return streq(m, want); },
  }
  return false;
}

// Trace length on success, -1 on any error.
fn run_all_len(e: &mut Executor, max_steps: Int) -> Int {
  match executor_run_all(e, max_steps) {
    Ok(tr) => { return tr.len(); },
    Err(_) => { return -1; },
  }
  return -1;
}

fn run_all_err_is(e: &mut Executor, max_steps: Int, want: Str) -> Bool {
  match executor_run_all(e, max_steps) {
    Ok(_) => { return false; },
    Err(m) => { return streq(m, want); },
  }
  return false;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

fn t1() -> TestResult {
  var e = e_of(EXEC_POLICY_FIFO);
  var ok = policy_of(&mut e) == EXEC_POLICY_FIFO;
  if task_count_of(&mut e) != 0 { ok = false; }
  if future_count_of(&mut e) != 0 { ok = false; }
  if submitted_of(&mut e) != 0 { ok = false; }
  if completed_of(&mut e) != 0 { ok = false; }
  if failed_of(&mut e) != 0 { ok = false; }
  if steps_of(&mut e) != 0 { ok = false; }
  if ready_len_of(&mut e) != 0 { ok = false; }
  if trace_len_of(&mut e) != 0 { ok = false; }
  if !invariant_of(&mut e) { ok = false; }
  return assert(ok, "executor_new initializes policy, empty metadata and zero stats");
}

fn t2() -> TestResult {
  var ok = new_err_is(7, _E_POLICY);
  if !new_err_is(-1, _E_POLICY) { ok = false; }
  var e = e_of(EXEC_POLICY_FIFO);
  if !set_policy_err_is(&mut e, 9, _E_POLICY) { ok = false; }
  if policy_of(&mut e) != EXEC_POLICY_FIFO { ok = false; }
  if !invariant_of(&mut e) { ok = false; }
  return assert(ok, "unknown policies are rejected by new and set_policy");
}

fn t3() -> TestResult {
  var e = e_of(EXEC_POLICY_FIFO);
  var ok = submit_err_is(&mut e, -1, 0, _E_TASK_ID);
  if !submit_err_is(&mut e, 1, -2, _E_PRIO) { ok = false; }
  if submit_ok(&mut e, 1, 0) != 0 { ok = false; }
  if !submit_err_is(&mut e, 1, 5, _E_DUP_TASK) { ok = false; }
  if task_count_of(&mut e) != 1 { ok = false; }
  if submitted_of(&mut e) != 1 { ok = false; }
  if !invariant_of(&mut e) { ok = false; }
  return assert(ok, "submit validates id >= 0, priority >= 0 and uniqueness");
}

fn t4() -> TestResult {
  var e = e_of(EXEC_POLICY_FIFO);
  var ok = submit_ready_ok(&mut e, 10, 0) == 0;
  if submit_ready_ok(&mut e, 11, 0) != 1 { ok = false; }
  if submit_ready_ok(&mut e, 12, 0) != 2 { ok = false; }
  if ready_len_of(&mut e) != 3 { ok = false; }
  if next_id_or_neg(&mut e) != 10 { ok = false; }
  if complete_ok(&mut e, 10, 0) != 1 { ok = false; }
  if next_id_or_neg(&mut e) != 11 { ok = false; }
  if next_id_or_neg(&mut e) != 12 { ok = false; }
  if ready_len_of(&mut e) != 0 { ok = false; }
  if !invariant_of(&mut e) { ok = false; }
  return assert(ok, "FIFO dispatches ready tasks in queue arrival order");
}

fn t5() -> TestResult {
  var e = e_of(EXEC_POLICY_PRIORITY);
  var ok = submit_ready_ok(&mut e, 10, 1) == 0;
  if submit_ready_ok(&mut e, 11, 5) != 1 { ok = false; }
  if submit_ready_ok(&mut e, 12, 5) != 2 { ok = false; }
  if submit_ready_ok(&mut e, 13, 5) != 3 { ok = false; }
  if next_id_or_neg(&mut e) != 11 { ok = false; }
  if next_id_or_neg(&mut e) != 12 { ok = false; }
  if next_id_or_neg(&mut e) != 13 { ok = false; }
  if next_id_or_neg(&mut e) != 10 { ok = false; }
  if !invariant_of(&mut e) { ok = false; }
  return assert(ok, "priority policy picks the largest priority first");
}

fn t6() -> TestResult {
  var e = e_of(EXEC_POLICY_PRIORITY);
  var ok = submit_ready_ok(&mut e, 20, 3) == 0;
  if submit_ready_ok(&mut e, 21, 3) != 1 { ok = false; }
  if submit_ready_ok(&mut e, 22, 9) != 2 { ok = false; }
  if submit_ready_ok(&mut e, 30, 4) != 3 { ok = false; }
  if submit_ready_ok(&mut e, 29, 4) != 4 { ok = false; }
  if next_id_or_neg(&mut e) != 22 { ok = false; }
  if next_id_or_neg(&mut e) != 30 { ok = false; }
  if next_id_or_neg(&mut e) != 29 { ok = false; }
  if next_id_or_neg(&mut e) != 20 { ok = false; }
  if next_id_or_neg(&mut e) != 21 { ok = false; }
  if !invariant_of(&mut e) { ok = false; }
  return assert(ok, "priority ties are stable by submission sequence, later high priority jumps ahead");
}

fn t7() -> TestResult {
  var e = e_of(EXEC_POLICY_FIFO);
  var ok = submit_ready_ok(&mut e, 1, 1) == 0;
  if submit_ready_ok(&mut e, 2, 5) != 1 { ok = false; }
  if next_id_or_neg(&mut e) != 1 { ok = false; }
  if complete_ok(&mut e, 1, 0) != 1 { ok = false; }
  if set_policy_ok(&mut e, EXEC_POLICY_PRIORITY) != EXEC_POLICY_PRIORITY { ok = false; }
  if next_id_or_neg(&mut e) != 2 { ok = false; }
  if submit_ready_ok(&mut e, 5, 1) != 0 { ok = false; }
  if submit_ready_ok(&mut e, 6, 9) != 1 { ok = false; }
  if next_policy_id(&mut e, EXEC_POLICY_FIFO) != 5 { ok = false; }
  if next_policy_id(&mut e, EXEC_POLICY_PRIORITY) != 6 { ok = false; }
  if !next_policy_err_is(&mut e, 9, _E_POLICY) { ok = false; }
  if !invariant_of(&mut e) { ok = false; }
  return assert(ok, "policy can be switched and overridden per dispatch");
}

fn t8() -> TestResult {
  var e = e_of(EXEC_POLICY_FIFO);
  var ok = submit_ready_ok(&mut e, 7, 0) == 0;
  if submit_ready_ok(&mut e, 8, 0) != 1 { ok = false; }
  if next_id_or_neg(&mut e) != 7 { ok = false; }
  if state_of(&mut e, 7) != EXEC_TASK_RUNNING { ok = false; }
  if ready_len_of(&mut e) != 1 { ok = false; }
  var ids = ready_ids_of(&mut e);
  let first: Int = ids[0];
  if first != 8 { ok = false; }
  if steps_of(&mut e) != 1 { ok = false; }
  if !has_task_of(&mut e, 7) { ok = false; }
  if !invariant_of(&mut e) { ok = false; }
  return assert(ok, "dispatch pops the queue entry and marks the task RUNNING");
}

fn t9() -> TestResult {
  var e = e_of(EXEC_POLICY_FIFO);
  var ok = enqueue_err_is(&mut e, 99, _E_UNKNOWN_TASK);
  if submit_ok(&mut e, 9, 0) != 0 { ok = false; }
  if enqueue_ok(&mut e, 9) != 0 { ok = false; }
  if !enqueue_err_is(&mut e, 9, _E_QUEUED) { ok = false; }
  if next_id_or_neg(&mut e) != 9 { ok = false; }
  if !enqueue_err_is(&mut e, 9, _E_RUNNING) { ok = false; }
  if complete_ok(&mut e, 9, 0) != 1 { ok = false; }
  if !enqueue_err_is(&mut e, 9, _E_TASK_DONE) { ok = false; }
  if submit_ready_ok(&mut e, 10, 0) != 0 { ok = false; }
  if next_id_or_neg(&mut e) != 10 { ok = false; }
  if fail_ok(&mut e, 10, 1) != 1 { ok = false; }
  if !enqueue_err_is(&mut e, 10, _E_TASK_FAILED) { ok = false; }
  if ready_len_of(&mut e) != 0 { ok = false; }
  if !invariant_of(&mut e) { ok = false; }
  return assert(ok, "enqueue validates the task lifecycle and refuses re-entry");
}

fn t10() -> TestResult {
  var e = e_of(EXEC_POLICY_FIFO);
  var ok = next_err_is(&mut e, _E_NO_READY);
  if next_id_or_neg(&mut e) != -1 { ok = false; }
  if steps_of(&mut e) != 0 { ok = false; }
  if !invariant_of(&mut e) { ok = false; }
  return assert(ok, "dispatch on an empty queue errors without changing state");
}

fn t11() -> TestResult {
  var e = e_of(EXEC_POLICY_FIFO);
  var ok = complete_err_is(&mut e, 99, 0, _E_UNKNOWN_TASK);
  if submit_ok(&mut e, 7, 0) != 0 { ok = false; }
  if !complete_err_is(&mut e, 7, 5, _E_NOT_RUNNING) { ok = false; }
  if submit_ready_ok(&mut e, 8, 0) != 0 { ok = false; }
  if !complete_err_is(&mut e, 8, 5, _E_NOT_RUNNING) { ok = false; }
  if next_id_or_neg(&mut e) != 8 { ok = false; }
  if state_of(&mut e, 8) != EXEC_TASK_RUNNING { ok = false; }
  if complete_ok(&mut e, 8, 42) != 1 { ok = false; }
  if state_of(&mut e, 8) != EXEC_TASK_DONE { ok = false; }
  if !complete_err_is(&mut e, 8, 1, _E_TASK_DONE) { ok = false; }
  if completed_of(&mut e) != 1 { ok = false; }
  if steps_of(&mut e) != 1 { ok = false; }
  if !streq(trace_text_of(&mut e), "8") { ok = false; }
  if !invariant_of(&mut e) { ok = false; }
  return assert(ok, "complete moves RUNNING -> DONE, traces it and validates");
}

fn t12() -> TestResult {
  var e = e_of(EXEC_POLICY_FIFO);
  var ok = fail_err_is(&mut e, 99, 0, _E_UNKNOWN_TASK);
  if submit_ready_ok(&mut e, 9, 0) != 0 { ok = false; }
  if !fail_err_is(&mut e, 9, 1, _E_NOT_RUNNING) { ok = false; }
  if next_id_or_neg(&mut e) != 9 { ok = false; }
  if fail_ok(&mut e, 9, 5) != 1 { ok = false; }
  if state_of(&mut e, 9) != EXEC_TASK_FAILED { ok = false; }
  if !fail_err_is(&mut e, 9, 5, _E_TASK_FAILED) { ok = false; }
  if !complete_err_is(&mut e, 9, 5, _E_TASK_FAILED) { ok = false; }
  if failed_of(&mut e) != 1 { ok = false; }
  if completed_of(&mut e) != 0 { ok = false; }
  if !streq(trace_text_of(&mut e), "9") { ok = false; }
  if !invariant_of(&mut e) { ok = false; }
  return assert(ok, "fail moves RUNNING -> FAILED, traces it and validates");
}

fn t13() -> TestResult {
  var e = e_of(EXEC_POLICY_FIFO);
  var ok = !has_task_of(&mut e, 3);
  if state_of(&mut e, 3) != EXEC_NOT_FOUND { ok = false; }
  if submit_ok(&mut e, 3, 4) != 0 { ok = false; }
  if !has_task_of(&mut e, 3) { ok = false; }
  if state_of(&mut e, 3) != EXEC_TASK_NEW { ok = false; }
  if prio_of(&mut e, 3) != 4 { ok = false; }
  if order_of(&mut e, 3) != 0 { ok = false; }
  if prio_of(&mut e, 99) != EXEC_NOT_FOUND { ok = false; }
  if order_of(&mut e, 99) != EXEC_NOT_FOUND { ok = false; }
  return assert(ok, "task accessors expose state, priority and submission order");
}

fn t14() -> TestResult {
  var e = e_of(EXEC_POLICY_FIFO);
  var ok = future_new_err_is(&mut e, -1, _E_FUT_ID);
  if future_new_ok(&mut e, 4) != 4 { ok = false; }
  if !future_new_err_is(&mut e, 4, _E_DUP_FUT) { ok = false; }
  if future_count_of(&mut e) != 1 { ok = false; }
  if !has_future_of(&mut e, 4) { ok = false; }
  if fstate_of(&mut e, 4) != EXEC_FUTURE_PENDING { ok = false; }
  if fvalue_of(&mut e, 4) != 0 { ok = false; }
  if fcode_of(&mut e, 4) != 0 { ok = false; }
  if fcont_of(&mut e, 4) != EXEC_NO_CONTINUATION { ok = false; }
  if fhas_cont_of(&mut e, 4) { ok = false; }
  if fstate_of(&mut e, 99) != EXEC_NOT_FOUND { ok = false; }
  if !invariant_of(&mut e) { ok = false; }
  return assert(ok, "future_new validates ids and starts PENDING with empty slots");
}

fn t15() -> TestResult {
  var e = e_of(EXEC_POLICY_FIFO);
  var ok = future_new_ok(&mut e, 1) == 1;
  if set_ready_ok(&mut e, 1, 77) != 77 { ok = false; }
  if fstate_of(&mut e, 1) != EXEC_FUTURE_READY { ok = false; }
  if fvalue_of(&mut e, 1) != 77 { ok = false; }
  if fcode_of(&mut e, 1) != 0 { ok = false; }
  if !set_ready_err_is(&mut e, 1, 5, _E_FUT_COMPLETE) { ok = false; }
  if !set_failed_err_is(&mut e, 1, 5, _E_FUT_COMPLETE) { ok = false; }
  if !set_ready_err_is(&mut e, 99, 0, _E_UNKNOWN_FUT) { ok = false; }
  if !set_failed_err_is(&mut e, 99, 0, _E_UNKNOWN_FUT) { ok = false; }
  if !invariant_of(&mut e) { ok = false; }
  return assert(ok, "future_set_ready publishes once and refuses double-complete");
}

fn t16() -> TestResult {
  var e = e_of(EXEC_POLICY_FIFO);
  var ok = future_new_ok(&mut e, 2) == 2;
  if set_failed_ok(&mut e, 2, 9) != 9 { ok = false; }
  if fstate_of(&mut e, 2) != EXEC_FUTURE_FAILED { ok = false; }
  if fcode_of(&mut e, 2) != 9 { ok = false; }
  if fvalue_of(&mut e, 2) != 0 { ok = false; }
  if !set_ready_err_is(&mut e, 2, 1, _E_FUT_FAILED) { ok = false; }
  if !set_failed_err_is(&mut e, 2, 1, _E_FUT_COMPLETE) { ok = false; }
  if !invariant_of(&mut e) { ok = false; }
  return assert(ok, "future_set_failed publishes once and refuses complete-after-failure");
}

fn t17() -> TestResult {
  var e = e_of(EXEC_POLICY_FIFO);
  var ok = attach_err_is(&mut e, 99, 1, _E_UNKNOWN_FUT);
  if future_new_ok(&mut e, 1) != 1 { ok = false; }
  if !attach_err_is(&mut e, 1, 99, _E_UNKNOWN_TASK) { ok = false; }
  if submit_ok(&mut e, 5, 0) != 0 { ok = false; }
  if submit_ok(&mut e, 6, 0) != 1 { ok = false; }
  if attach_ok(&mut e, 1, 5) != 5 { ok = false; }
  if !attach_err_is(&mut e, 1, 6, _E_HAS_CONT) { ok = false; }
  if submit_ready_ok(&mut e, 7, 0) != 0 { ok = false; }
  if next_id_or_neg(&mut e) != 7 { ok = false; }
  if complete_ok(&mut e, 7, 0) != 1 { ok = false; }
  if future_new_ok(&mut e, 2) != 2 { ok = false; }
  if !attach_err_is(&mut e, 2, 7, _E_CONT_DONE) { ok = false; }
  if submit_ready_ok(&mut e, 8, 0) != 0 { ok = false; }
  if next_id_or_neg(&mut e) != 8 { ok = false; }
  if fail_ok(&mut e, 8, 1) != 1 { ok = false; }
  if future_new_ok(&mut e, 3) != 3 { ok = false; }
  if !attach_err_is(&mut e, 3, 8, _E_CONT_FAILED) { ok = false; }
  if future_new_ok(&mut e, 4) != 4 { ok = false; }
  if set_ready_ok(&mut e, 4, 0) != 0 { ok = false; }
  if !attach_err_is(&mut e, 4, 5, _E_FUT_READY) { ok = false; }
  if future_new_ok(&mut e, 4) != -1 { ok = false; }
  if future_new_ok(&mut e, 40) != 40 { ok = false; }
  if set_failed_ok(&mut e, 40, 2) != 2 { ok = false; }
  if !attach_err_is(&mut e, 40, 5, _E_FUT_FAILED) { ok = false; }
  if !invariant_of(&mut e) { ok = false; }
  return assert(ok, "attach_continuation validates future and task lifecycles");
}

fn t18() -> TestResult {
  var e = e_of(EXEC_POLICY_FIFO);
  var ok = future_new_ok(&mut e, 1) == 1;
  if submit_ok(&mut e, 2, 0) != 0 { ok = false; }
  if attach_ok(&mut e, 1, 2) != 2 { ok = false; }
  if ready_len_of(&mut e) != 0 { ok = false; }
  if set_ready_ok(&mut e, 1, 55) != 55 { ok = false; }
  if ready_len_of(&mut e) != 1 { ok = false; }
  var ids = ready_ids_of(&mut e);
  let first: Int = ids[0];
  if first != 2 { ok = false; }
  if state_of(&mut e, 2) != EXEC_TASK_READY { ok = false; }
  if !set_ready_err_is(&mut e, 1, 56, _E_FUT_COMPLETE) { ok = false; }
  if ready_len_of(&mut e) != 1 { ok = false; }
  if next_id_or_neg(&mut e) != 2 { ok = false; }
  if complete_ok(&mut e, 2, 0) != 1 { ok = false; }
  if !streq(trace_text_of(&mut e), "2") { ok = false; }
  if !invariant_of(&mut e) { ok = false; }
  return assert(ok, "a ready future enqueues its continuation exactly once");
}

fn t19() -> TestResult {
  var e = e_of(EXEC_POLICY_FIFO);
  var ok = future_new_ok(&mut e, 3) == 3;
  if submit_ok(&mut e, 4, 0) != 0 { ok = false; }
  if attach_ok(&mut e, 3, 4) != 4 { ok = false; }
  if set_failed_ok(&mut e, 3, 7) != 7 { ok = false; }
  if fstate_of(&mut e, 3) != EXEC_FUTURE_FAILED { ok = false; }
  if fcode_of(&mut e, 3) != 7 { ok = false; }
  if ready_len_of(&mut e) != 1 { ok = false; }
  var ids = ready_ids_of(&mut e);
  let first: Int = ids[0];
  if first != 4 { ok = false; }
  if next_id_or_neg(&mut e) != 4 { ok = false; }
  if complete_ok(&mut e, 4, 0) != 1 { ok = false; }
  if !invariant_of(&mut e) { ok = false; }
  return assert(ok, "a failed future also notifies its continuation once");
}

fn t20() -> TestResult {
  var e = e_of(EXEC_POLICY_FIFO);
  var ok = future_new_ok(&mut e, 5) == 5;
  if submit_ready_ok(&mut e, 5, 0) != 0 { ok = false; }
  if next_id_or_neg(&mut e) != 5 { ok = false; }
  if complete_ok(&mut e, 5, 42) != 1 { ok = false; }
  if fstate_of(&mut e, 5) != EXEC_FUTURE_READY { ok = false; }
  if fvalue_of(&mut e, 5) != 42 { ok = false; }
  if fcode_of(&mut e, 5) != 0 { ok = false; }
  if future_new_ok(&mut e, 6) != 6 { ok = false; }
  if submit_ready_ok(&mut e, 6, 0) != 0 { ok = false; }
  if next_id_or_neg(&mut e) != 6 { ok = false; }
  if fail_ok(&mut e, 6, 9) != 1 { ok = false; }
  if fstate_of(&mut e, 6) != EXEC_FUTURE_FAILED { ok = false; }
  if fcode_of(&mut e, 6) != 9 { ok = false; }
  if fvalue_of(&mut e, 6) != 0 { ok = false; }
  if !invariant_of(&mut e) { ok = false; }
  return assert(ok, "task completion publishes to the same-id future (value or code)");
}

fn t21() -> TestResult {
  var e = e_of(EXEC_POLICY_FIFO);
  var ok = submit_ready_ok(&mut e, 1, 0) == 0;
  if submit_ready_ok(&mut e, 2, 0) != 1 { ok = false; }
  if submit_ready_ok(&mut e, 3, 0) != 2 { ok = false; }
  if run_all_len(&mut e, 10) != 3 { ok = false; }
  if !streq(trace_text_of(&mut e), "1,2,3") { ok = false; }
  if completed_of(&mut e) != 3 { ok = false; }
  if failed_of(&mut e) != 0 { ok = false; }
  if submitted_of(&mut e) != 3 { ok = false; }
  if steps_of(&mut e) != 3 { ok = false; }
  if state_of(&mut e, 2) != EXEC_TASK_DONE { ok = false; }
  if !invariant_of(&mut e) { ok = false; }
  return assert(ok, "run_all completes FIFO tasks and returns the completion trace");
}

fn t22() -> TestResult {
  var e = e_of(EXEC_POLICY_FIFO);
  var ok = submit_ok(&mut e, 1, 0) == 0;
  if submit_ok(&mut e, 2, 0) != 1 { ok = false; }
  if future_new_ok(&mut e, 1) != 1 { ok = false; }
  if attach_ok(&mut e, 1, 2) != 2 { ok = false; }
  if enqueue_ok(&mut e, 1) != 0 { ok = false; }
  if run_all_len(&mut e, 10) != 2 { ok = false; }
  if !streq(trace_text_of(&mut e), "1,2") { ok = false; }
  if completed_of(&mut e) != 2 { ok = false; }
  if steps_of(&mut e) != 2 { ok = false; }
  if fstate_of(&mut e, 1) != EXEC_FUTURE_READY { ok = false; }
  if fvalue_of(&mut e, 1) != 1 { ok = false; }
  if state_of(&mut e, 2) != EXEC_TASK_DONE { ok = false; }
  if !invariant_of(&mut e) { ok = false; }
  return assert(ok, "run_all follows the continuation chain enqueued by a future");
}

fn t23() -> TestResult {
  var e = e_of(EXEC_POLICY_FIFO);
  var ok = submit_ready_ok(&mut e, 1, 0) == 0;
  if submit_ready_ok(&mut e, 2, 0) != 1 { ok = false; }
  if submit_ready_ok(&mut e, 3, 0) != 2 { ok = false; }
  if !run_all_err_is(&mut e, 2, _E_LIMIT) { ok = false; }
  if completed_of(&mut e) != 2 { ok = false; }
  if ready_len_of(&mut e) != 1 { ok = false; }
  if run_all_len(&mut e, 1) != 1 { ok = false; }
  if completed_of(&mut e) != 3 { ok = false; }
  if run_all_len(&mut e, 0) != 0 { ok = false; }
  if !run_all_err_is(&mut e, -1, _E_MAXSTEPS) { ok = false; }
  var e2 = e_of(EXEC_POLICY_FIFO);
  if run_all_len(&mut e2, 0) != 0 { ok = false; }
  if !invariant_of(&mut e) { ok = false; }
  if !invariant_of(&mut e2) { ok = false; }
  return assert(ok, "run_all enforces max_steps and validates the bound");
}

fn t24() -> TestResult {
  var e = e_of(EXEC_POLICY_FIFO);
  var ok = submit_ok(&mut e, 1, 0) == 0;
  if submitted_of(&mut e) != 1 { ok = false; }
  if enqueue_ok(&mut e, 1) != 0 { ok = false; }
  if next_id_or_neg(&mut e) != 1 { ok = false; }
  if steps_of(&mut e) != 1 { ok = false; }
  if complete_ok(&mut e, 1, 0) != 1 { ok = false; }
  if completed_of(&mut e) != 1 { ok = false; }
  if submit_ready_ok(&mut e, 2, 0) != 0 { ok = false; }
  if submitted_of(&mut e) != 2 { ok = false; }
  if next_id_or_neg(&mut e) != 2 { ok = false; }
  if steps_of(&mut e) != 2 { ok = false; }
  if fail_ok(&mut e, 2, 5) != 1 { ok = false; }
  if failed_of(&mut e) != 1 { ok = false; }
  if completed_of(&mut e) != 1 { ok = false; }
  if !invariant_of(&mut e) { ok = false; }
  return assert(ok, "stats accumulate submitted, steps, completed and failed");
}

fn t25() -> TestResult {
  var e = e_of(EXEC_POLICY_FIFO);
  var ok = submit_ready_ok(&mut e, 1, 0) == 0;
  if submit_ready_ok(&mut e, 2, 0) != 1 { ok = false; }
  if run_all_len(&mut e, 5) != 2 { ok = false; }
  if !streq(trace_text_of(&mut e), "1,2") { ok = false; }
  var tr = trace_of(&mut e);
  tr.push(99);
  if trace_len_of(&mut e) != 2 { ok = false; }
  if !streq(trace_text_of(&mut e), "1,2") { ok = false; }
  var ids = ready_ids_of(&mut e);
  ids.push(77);
  if ready_len_of(&mut e) != 0 { ok = false; }
  var empty = e_of(EXEC_POLICY_FIFO);
  if !streq(trace_text_of(&mut empty), "") { ok = false; }
  return assert(ok, "trace text renders comma-separated ids and copies are independent");
}

fn t26() -> TestResult {
  var e = e_of(EXEC_POLICY_PRIORITY);
  var ok = true;
  var i = 0;
  while i < 30 {
    let pos = submit_ready_ok(&mut e, 100 + i, i % 4);
    if pos < 0 { ok = false; }
    let nid = next_id_or_neg(&mut e);
    if nid >= 0 {
      if nid % 2 == 0 {
        if complete_ok(&mut e, nid, i) < 0 { ok = false; }
      } else {
        if fail_ok(&mut e, nid, i) < 0 { ok = false; }
      }
    }
    if !invariant_of(&mut e) { ok = false; }
    i = i + 1;
  }
  if completed_of(&mut e) + failed_of(&mut e) != 30 { ok = false; }
  if steps_of(&mut e) != 30 { ok = false; }
  if !invariant_of(&mut e) { ok = false; }
  return assert(ok, "the invariant holds across 30 mixed dispatch cycles");
}

fn t27() -> TestResult {
  var ok = streq(executor_policy_name(EXEC_POLICY_FIFO), "fifo");
  if !streq(executor_policy_name(EXEC_POLICY_PRIORITY), "priority") { ok = false; }
  if !streq(executor_policy_name(7), "unknown") { ok = false; }
  if !streq(executor_task_state_name(EXEC_TASK_NEW), "new") { ok = false; }
  if !streq(executor_task_state_name(EXEC_TASK_READY), "ready") { ok = false; }
  if !streq(executor_task_state_name(EXEC_TASK_RUNNING), "running") { ok = false; }
  if !streq(executor_task_state_name(EXEC_TASK_DONE), "done") { ok = false; }
  if !streq(executor_task_state_name(EXEC_TASK_FAILED), "failed") { ok = false; }
  if !streq(executor_task_state_name(-1), "unknown") { ok = false; }
  if !streq(executor_future_state_name(EXEC_FUTURE_PENDING), "pending") { ok = false; }
  if !streq(executor_future_state_name(EXEC_FUTURE_READY), "ready") { ok = false; }
  if !streq(executor_future_state_name(EXEC_FUTURE_FAILED), "failed") { ok = false; }
  if !streq(executor_future_state_name(-1), "unknown") { ok = false; }
  return assert(ok, "policy and state name helpers are stable");
}

fn main() -> Int {
  io.println("=== xiom.executor conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.executor: all tests passed");
  } else {
    io.println("xiom.executor: tests failed");
  }
  return failed;
}
