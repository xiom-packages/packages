// XIOM -- xiom.worker conformance tests (26 checks)
// Port task: prove the pure-XIOM xiom.worker pool model against its
// documented API (pool sizing, submission, FIFO/priority selection, worker
// leases and assignment, completion/failure, retry backoff accounting, lease
// expiry, starvation/fairness counters, tick accounting and statistics).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// All Str equality goes through str_compare: `==` on Str values read from
// Vec[Str] elements lowers to a pointer comparison, so every message and
// text check below is routed through streq. Vec[Int] element reads use a
// typed `let`. Read-only operations are wrapped in small helpers that take
// `&mut`, so a `&local` read call is never followed by a `&mut local` call
// in the same function body (advisory E001); each helper calls the real
// `&`-based API. Int-code classifiers turn Result outcomes into small Int
// codes so test bodies stay branch-free. All tests are fixture-driven and
// fully deterministic: no threads, no wall clock, explicit tick steps only.

module worker_tests
use xiom.io; use xiom.test; use xiom.worker;
use xiom.string.compare;

const _STATS_ONE_DONE: Str = "size=2 idle=2 busy=0 queued=0 leased=0 retry=0 done=1 failed=0 submitted=1 dispatches=1 completions=1 failures=0 attempt_failures=0 retries=0 backoff_ticks=0 leases_expired=0 starvation_skips=0 starvation_events=0 fair=1 unfair=0 max_wait_ticks=0 now=0";

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// Fixture: the Err branch is unreachable for the valid arguments the tests
// pass, but the function must still return a WorkerPool value.
fn empty_pool(policy: Int) -> WorkerPool {
  return WorkerPool{
    policy: policy;
    size: 0;
    lease_ticks: 0;
    now: 0;
    worker_states: Vec[Int].new();
    worker_jobs: Vec[Int].new();
    worker_lease_until: Vec[Int].new();
    worker_leases: Vec[Int].new();
    worker_busy_ticks: Vec[Int].new();
    job_ids: Vec[Int].new();
    job_priorities: Vec[Int].new();
    job_orders: Vec[Int].new();
    job_states: Vec[Int].new();
    job_attempts: Vec[Int].new();
    job_max_attempts: Vec[Int].new();
    job_ready_tick: Vec[Int].new();
    job_submit_tick: Vec[Int].new();
    job_worker: Vec[Int].new();
    job_wait_ticks: Vec[Int].new();
    job_queued_ticks: Vec[Int].new();
    job_skips: Vec[Int].new();
    submitted: 0;
    dispatches: 0;
    completions: 0;
    failures: 0;
    attempt_failures: 0;
    retries: 0;
    backoff_ticks: 0;
    leases_expired: 0;
    starvation_skips: 0;
    starvation_events: 0;
    fair_dispatches: 0;
    unfair_dispatches: 0;
    max_wait_ticks: 0;
  };
}

fn pool_of(size: Int, policy: Int, lease_ticks: Int) -> WorkerPool {
  match pool_new(size, policy, lease_ticks) {
    Ok(p) => { return p; },
    Err(_) => { return empty_pool(policy); },
  }
}

fn new_err_is(size: Int, policy: Int, lease_ticks: Int, want: Str) -> Bool {
  match pool_new(size, policy, lease_ticks) {
    Ok(_) => { return false; },
    Err(m) => { return streq(m, want); },
  }
  return false;
}

// Read-only accessors routed through `&mut` (advisory E001).

fn worker_count_of(p: &mut WorkerPool) -> Int {
  return pool_size(p);
}

fn policy_of(p: &mut WorkerPool) -> Int {
  return pool_policy(p);
}

fn lease_ticks_of(p: &mut WorkerPool) -> Int {
  return pool_lease_ticks(p);
}

fn now_of(p: &mut WorkerPool) -> Int {
  return pool_now(p);
}

fn job_count_of(p: &mut WorkerPool) -> Int {
  return pool_job_count(p);
}

fn has_job_of(p: &mut WorkerPool, id: Int) -> Bool {
  return pool_has_job(p, id);
}

fn state_of(p: &mut WorkerPool, id: Int) -> Int {
  return pool_job_state(p, id);
}

fn prio_of(p: &mut WorkerPool, id: Int) -> Int {
  return pool_job_priority(p, id);
}

fn order_of(p: &mut WorkerPool, id: Int) -> Int {
  return pool_job_order(p, id);
}

fn attempts_of(p: &mut WorkerPool, id: Int) -> Int {
  return pool_job_attempts(p, id);
}

fn max_attempts_of(p: &mut WorkerPool, id: Int) -> Int {
  return pool_job_max_attempts(p, id);
}

fn ready_tick_of(p: &mut WorkerPool, id: Int) -> Int {
  return pool_job_ready_tick(p, id);
}

fn submit_tick_of(p: &mut WorkerPool, id: Int) -> Int {
  return pool_job_submit_tick(p, id);
}

fn job_worker_of(p: &mut WorkerPool, id: Int) -> Int {
  return pool_job_worker(p, id);
}

fn wait_of(p: &mut WorkerPool, id: Int) -> Int {
  return pool_job_wait_ticks(p, id);
}

fn queued_of(p: &mut WorkerPool, id: Int) -> Int {
  return pool_job_queued_ticks(p, id);
}

fn skips_of(p: &mut WorkerPool, id: Int) -> Int {
  return pool_job_skips(p, id);
}

fn queued_count_of(p: &mut WorkerPool) -> Int {
  return pool_queued_count(p);
}

fn eligible_count_of(p: &mut WorkerPool) -> Int {
  return pool_eligible_count(p);
}

fn queued_ids_of(p: &mut WorkerPool) -> Vec[Int] {
  return pool_queued_ids(p);
}

fn pick_of(p: &mut WorkerPool) -> Int {
  return pool_pick_job(p);
}

fn idle_of(p: &mut WorkerPool) -> Int {
  return pool_idle_workers(p);
}

fn busy_of(p: &mut WorkerPool) -> Int {
  return pool_busy_workers(p);
}

fn worker_state_of(p: &mut WorkerPool, w: Int) -> Int {
  return pool_worker_state(p, w);
}

fn worker_job_of(p: &mut WorkerPool, w: Int) -> Int {
  return pool_worker_job(p, w);
}

fn lease_until_of(p: &mut WorkerPool, w: Int) -> Int {
  return pool_worker_lease_until(p, w);
}

fn remaining_of(p: &mut WorkerPool, w: Int) -> Int {
  return pool_lease_remaining(p, w);
}

fn worker_leases_of(p: &mut WorkerPool, w: Int) -> Int {
  return pool_worker_leases(p, w);
}

fn worker_busy_of(p: &mut WorkerPool, w: Int) -> Int {
  return pool_worker_busy_ticks(p, w);
}

fn submitted_of(p: &mut WorkerPool) -> Int {
  return pool_submitted(p);
}

fn dispatches_of(p: &mut WorkerPool) -> Int {
  return pool_dispatches(p);
}

fn completions_of(p: &mut WorkerPool) -> Int {
  return pool_completions(p);
}

fn failures_of(p: &mut WorkerPool) -> Int {
  return pool_failures(p);
}

fn attempt_failures_of(p: &mut WorkerPool) -> Int {
  return pool_attempt_failures(p);
}

fn retries_of(p: &mut WorkerPool) -> Int {
  return pool_retries(p);
}

fn backoff_total_of(p: &mut WorkerPool) -> Int {
  return pool_backoff_ticks(p);
}

fn expired_of(p: &mut WorkerPool) -> Int {
  return pool_leases_expired(p);
}

fn starve_skips_of(p: &mut WorkerPool) -> Int {
  return pool_starvation_skips(p);
}

fn starve_events_of(p: &mut WorkerPool) -> Int {
  return pool_starvation_events(p);
}

fn fair_of(p: &mut WorkerPool) -> Int {
  return pool_fair_dispatches(p);
}

fn unfair_of(p: &mut WorkerPool) -> Int {
  return pool_unfair_dispatches(p);
}

fn max_wait_of(p: &mut WorkerPool) -> Int {
  return pool_max_wait_ticks(p);
}

fn stats_of(p: &mut WorkerPool) -> PoolStats {
  return pool_stats(p);
}

fn stats_text_of(p: &mut WorkerPool) -> Str {
  return pool_stats_text(p);
}

fn invariant_of(p: &mut WorkerPool) -> Bool {
  return pool_check_invariant(p);
}

// Outcome classifiers: Int codes keep the tests readable.

fn set_policy_ok(p: &mut WorkerPool, policy: Int) -> Int {
  match pool_set_policy(p, policy) {
    Ok(v) => { return v; },
    Err(_) => { return -1; },
  }
  return -1;
}

fn set_policy_err_is(p: &mut WorkerPool, policy: Int, want: Str) -> Bool {
  match pool_set_policy(p, policy) {
    Ok(_) => { return false; },
    Err(m) => { return streq(m, want); },
  }
  return false;
}

// Submission sequence on success, -1 on any error.
fn submit_ok(p: &mut WorkerPool, id: Int, prio: Int, maxa: Int) -> Int {
  match pool_submit(p, id, prio, maxa) {
    Ok(o) => { return o; },
    Err(_) => { return -1; },
  }
  return -1;
}

fn submit_err_is(p: &mut WorkerPool, id: Int, prio: Int, maxa: Int, want: Str) -> Bool {
  match pool_submit(p, id, prio, maxa) {
    Ok(_) => { return false; },
    Err(m) => { return streq(m, want); },
  }
  return false;
}

// Leased job id on success, -1 on any error.
fn dispatch_ok(p: &mut WorkerPool) -> Int {
  match pool_dispatch(p) {
    Ok(id) => { return id; },
    Err(_) => { return -1; },
  }
  return -1;
}

fn dispatch_err_is(p: &mut WorkerPool, want: Str) -> Bool {
  match pool_dispatch(p) {
    Ok(_) => { return false; },
    Err(m) => { return streq(m, want); },
  }
  return false;
}

// Assigned job id on success, -1 on any error.
fn assign_ok(p: &mut WorkerPool, id: Int, w: Int) -> Int {
  match pool_assign(p, id, w) {
    Ok(v) => { return v; },
    Err(_) => { return -1; },
  }
  return -1;
}

fn assign_err_is(p: &mut WorkerPool, id: Int, w: Int, want: Str) -> Bool {
  match pool_assign(p, id, w) {
    Ok(_) => { return false; },
    Err(m) => { return streq(m, want); },
  }
  return false;
}

// Completions count on success, -1 on any error.
fn complete_ok(p: &mut WorkerPool, id: Int) -> Int {
  match pool_complete(p, id) {
    Ok(n) => { return n; },
    Err(_) => { return -1; },
  }
  return -1;
}

fn complete_err_is(p: &mut WorkerPool, id: Int, want: Str) -> Bool {
  match pool_complete(p, id) {
    Ok(_) => { return false; },
    Err(m) => { return streq(m, want); },
  }
  return false;
}

// Attempts made on success, -1 on any error.
fn fail_ok(p: &mut WorkerPool, id: Int) -> Int {
  match pool_fail(p, id) {
    Ok(n) => { return n; },
    Err(_) => { return -1; },
  }
  return -1;
}

fn fail_err_is(p: &mut WorkerPool, id: Int, want: Str) -> Bool {
  match pool_fail(p, id) {
    Ok(_) => { return false; },
    Err(m) => { return streq(m, want); },
  }
  return false;
}

// New tick value on success, -1 on any error.
fn tick_ok(p: &mut WorkerPool, ticks: Int) -> Int {
  match pool_tick(p, ticks) {
    Ok(t) => { return t; },
    Err(_) => { return -1; },
  }
  return -1;
}

fn tick_err_is(p: &mut WorkerPool, ticks: Int, want: Str) -> Bool {
  match pool_tick(p, ticks) {
    Ok(_) => { return false; },
    Err(m) => { return streq(m, want); },
  }
  return false;
}

// Deterministic replay scenario for the determinism test: identical
// operation sequences on two pools must produce identical statistics.
fn deterministic_scenario() -> WorkerPool {
  var p = pool_of(2, POOL_POLICY_PRIORITY, 3);
  submit_ok(&mut p, 1, 0, 3);
  submit_ok(&mut p, 2, 5, 2);
  submit_ok(&mut p, 3, 5, 1);
  tick_ok(&mut p, 2);
  let d1 = dispatch_ok(&mut p);
  fail_ok(&mut p, d1);
  tick_ok(&mut p, 1);
  let d2 = dispatch_ok(&mut p);
  complete_ok(&mut p, d2);
  tick_ok(&mut p, 3);
  let d3 = dispatch_ok(&mut p);
  tick_ok(&mut p, 4);
  let d4 = dispatch_ok(&mut p);
  if d4 >= 0 {
    complete_ok(&mut p, d4);
  }
  return p;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

fn t1() -> TestResult {
  var p = pool_of(2, POOL_POLICY_FIFO, 4);
  var ok = worker_count_of(&mut p) == 2;
  if policy_of(&mut p) != POOL_POLICY_FIFO { ok = false; }
  if lease_ticks_of(&mut p) != 4 { ok = false; }
  if now_of(&mut p) != 0 { ok = false; }
  if idle_of(&mut p) != 2 { ok = false; }
  if busy_of(&mut p) != 0 { ok = false; }
  if job_count_of(&mut p) != 0 { ok = false; }
  if queued_count_of(&mut p) != 0 { ok = false; }
  if eligible_count_of(&mut p) != 0 { ok = false; }
  if pick_of(&mut p) != -1 { ok = false; }
  if worker_state_of(&mut p, 0) != WORKER_IDLE { ok = false; }
  if worker_job_of(&mut p, 0) != -1 { ok = false; }
  if lease_until_of(&mut p, 0) != 0 { ok = false; }
  if remaining_of(&mut p, 0) != 0 { ok = false; }
  if worker_leases_of(&mut p, 0) != 0 { ok = false; }
  if worker_busy_of(&mut p, 0) != 0 { ok = false; }
  if submitted_of(&mut p) != 0 { ok = false; }
  if dispatches_of(&mut p) != 0 { ok = false; }
  if completions_of(&mut p) != 0 { ok = false; }
  if failures_of(&mut p) != 0 { ok = false; }
  if attempt_failures_of(&mut p) != 0 { ok = false; }
  if retries_of(&mut p) != 0 { ok = false; }
  if backoff_total_of(&mut p) != 0 { ok = false; }
  if expired_of(&mut p) != 0 { ok = false; }
  if starve_skips_of(&mut p) != 0 { ok = false; }
  if starve_events_of(&mut p) != 0 { ok = false; }
  if fair_of(&mut p) != 0 { ok = false; }
  if unfair_of(&mut p) != 0 { ok = false; }
  if max_wait_of(&mut p) != 0 { ok = false; }
  if !invariant_of(&mut p) { ok = false; }
  let s = stats_of(&mut p);
  if s.size != 2 { ok = false; }
  if s.idle != 2 { ok = false; }
  if s.jobs != 0 { ok = false; }
  if s.now != 0 { ok = false; }
  return assert(ok, "pool_new initializes sized workers, empty jobs and zero stats");
}

fn t2() -> TestResult {
  var ok = new_err_is(0, POOL_POLICY_FIFO, 4, "pool: size must be >= 1");
  if !new_err_is(-1, POOL_POLICY_FIFO, 4, "pool: size must be >= 1") { ok = false; }
  if !new_err_is(2, 7, 4, "pool: unknown policy") { ok = false; }
  if !new_err_is(2, POOL_POLICY_FIFO, 0, "pool: lease_ticks must be >= 1") { ok = false; }
  var p = pool_of(1, POOL_POLICY_FIFO, 2);
  if !set_policy_err_is(&mut p, 9, "pool: unknown policy") { ok = false; }
  if policy_of(&mut p) != POOL_POLICY_FIFO { ok = false; }
  if set_policy_ok(&mut p, POOL_POLICY_PRIORITY) != POOL_POLICY_PRIORITY { ok = false; }
  if policy_of(&mut p) != POOL_POLICY_PRIORITY { ok = false; }
  if !invariant_of(&mut p) { ok = false; }
  return assert(ok, "pool_new and pool_set_policy validate size, policy and lease_ticks");
}

fn t3() -> TestResult {
  var p = pool_of(1, POOL_POLICY_FIFO, 4);
  var ok = submit_err_is(&mut p, -1, 0, 2, "pool: job id must be >= 0");
  if !submit_err_is(&mut p, 1, -1, 2, "pool: priority must be >= 0") { ok = false; }
  if !submit_err_is(&mut p, 1, 0, 0, "pool: max_attempts must be >= 1") { ok = false; }
  if submit_ok(&mut p, 5, 2, 3) != 0 { ok = false; }
  if submit_ok(&mut p, 6, 1, 1) != 1 { ok = false; }
  if !submit_err_is(&mut p, 5, 0, 1, "pool: duplicate job id") { ok = false; }
  if job_count_of(&mut p) != 2 { ok = false; }
  if submitted_of(&mut p) != 2 { ok = false; }
  if !has_job_of(&mut p, 5) { ok = false; }
  if has_job_of(&mut p, 99) { ok = false; }
  if state_of(&mut p, 5) != JOB_QUEUED { ok = false; }
  if state_of(&mut p, 99) != POOL_NOT_FOUND { ok = false; }
  if prio_of(&mut p, 5) != 2 { ok = false; }
  if prio_of(&mut p, 99) != POOL_NOT_FOUND { ok = false; }
  if order_of(&mut p, 6) != 1 { ok = false; }
  if max_attempts_of(&mut p, 5) != 3 { ok = false; }
  if attempts_of(&mut p, 5) != 0 { ok = false; }
  if ready_tick_of(&mut p, 5) != 0 { ok = false; }
  if submit_tick_of(&mut p, 5) != 0 { ok = false; }
  if job_worker_of(&mut p, 5) != -1 { ok = false; }
  if wait_of(&mut p, 5) != 0 { ok = false; }
  if queued_of(&mut p, 5) != 0 { ok = false; }
  if skips_of(&mut p, 5) != 0 { ok = false; }
  if !invariant_of(&mut p) { ok = false; }
  return assert(ok, "pool_submit validates inputs, assigns dense orders and starts QUEUED");
}

fn t4() -> TestResult {
  var p = pool_of(1, POOL_POLICY_FIFO, 10);
  var ok = submit_ok(&mut p, 10, 5, 2) == 0;
  if submit_ok(&mut p, 11, 1, 2) != 1 { ok = false; }
  if submit_ok(&mut p, 12, 9, 2) != 2 { ok = false; }
  if pick_of(&mut p) != 10 { ok = false; }
  if queued_count_of(&mut p) != 3 { ok = false; }
  if eligible_count_of(&mut p) != 3 { ok = false; }
  var ids = queued_ids_of(&mut p);
  if ids.len() != 3 { ok = false; }
  let a: Int = ids[0];
  let b: Int = ids[1];
  let c: Int = ids[2];
  if a != 10 { ok = false; }
  if b != 11 { ok = false; }
  if c != 12 { ok = false; }
  ids.push(99);
  if queued_count_of(&mut p) != 3 { ok = false; }
  if dispatch_ok(&mut p) != 10 { ok = false; }
  if complete_ok(&mut p, 10) != 1 { ok = false; }
  if dispatch_ok(&mut p) != 11 { ok = false; }
  if complete_ok(&mut p, 11) != 2 { ok = false; }
  if dispatch_ok(&mut p) != 12 { ok = false; }
  if complete_ok(&mut p, 12) != 3 { ok = false; }
  if !invariant_of(&mut p) { ok = false; }
  return assert(ok, "FIFO ignores priority, keeps submission order and copies the queue");
}

fn t5() -> TestResult {
  var p = pool_of(1, POOL_POLICY_PRIORITY, 10);
  var ok = submit_ok(&mut p, 10, 1, 2) == 0;
  if submit_ok(&mut p, 11, 5, 2) != 1 { ok = false; }
  if submit_ok(&mut p, 12, 5, 2) != 2 { ok = false; }
  if submit_ok(&mut p, 13, 9, 2) != 3 { ok = false; }
  if submit_ok(&mut p, 14, 5, 2) != 4 { ok = false; }
  if pick_of(&mut p) != 13 { ok = false; }
  if dispatch_ok(&mut p) != 13 { ok = false; }
  if complete_ok(&mut p, 13) != 1 { ok = false; }
  if pick_of(&mut p) != 11 { ok = false; }
  if dispatch_ok(&mut p) != 11 { ok = false; }
  if complete_ok(&mut p, 11) != 2 { ok = false; }
  if pick_of(&mut p) != 12 { ok = false; }
  if dispatch_ok(&mut p) != 12 { ok = false; }
  if complete_ok(&mut p, 12) != 3 { ok = false; }
  if pick_of(&mut p) != 14 { ok = false; }
  if dispatch_ok(&mut p) != 14 { ok = false; }
  if complete_ok(&mut p, 14) != 4 { ok = false; }
  if dispatch_ok(&mut p) != 10 { ok = false; }
  if complete_ok(&mut p, 10) != 5 { ok = false; }
  if starve_skips_of(&mut p) != 10 { ok = false; }
  if skips_of(&mut p, 10) != 4 { ok = false; }
  if fair_of(&mut p) != 5 { ok = false; }
  if unfair_of(&mut p) != 0 { ok = false; }
  if !invariant_of(&mut p) { ok = false; }
  return assert(ok, "PRIORITY picks largest priority, ties stable by submission order");
}

fn t6() -> TestResult {
  var p = pool_of(2, POOL_POLICY_FIFO, 4);
  var ok = submit_ok(&mut p, 1, 0, 2) == 0;
  if submit_ok(&mut p, 2, 0, 2) != 1 { ok = false; }
  if dispatch_ok(&mut p) != 1 { ok = false; }
  if state_of(&mut p, 1) != JOB_LEASED { ok = false; }
  if attempts_of(&mut p, 1) != 1 { ok = false; }
  if job_worker_of(&mut p, 1) != 0 { ok = false; }
  if worker_state_of(&mut p, 0) != WORKER_BUSY { ok = false; }
  if worker_job_of(&mut p, 0) != 1 { ok = false; }
  if lease_until_of(&mut p, 0) != 4 { ok = false; }
  if remaining_of(&mut p, 0) != 4 { ok = false; }
  if idle_of(&mut p) != 1 { ok = false; }
  if busy_of(&mut p) != 1 { ok = false; }
  if dispatch_ok(&mut p) != 2 { ok = false; }
  if job_worker_of(&mut p, 2) != 1 { ok = false; }
  if idle_of(&mut p) != 0 { ok = false; }
  if busy_of(&mut p) != 2 { ok = false; }
  if worker_leases_of(&mut p, 0) != 1 { ok = false; }
  if worker_leases_of(&mut p, 1) != 1 { ok = false; }
  if dispatches_of(&mut p) != 2 { ok = false; }
  if submit_ok(&mut p, 3, 0, 2) != 2 { ok = false; }
  if !dispatch_err_is(&mut p, "pool: no idle workers") { ok = false; }
  if dispatches_of(&mut p) != 2 { ok = false; }
  if state_of(&mut p, 3) != JOB_QUEUED { ok = false; }
  if !invariant_of(&mut p) { ok = false; }
  return assert(ok, "pool_dispatch leases the lowest idle worker and marks the job LEASED");
}

fn t7() -> TestResult {
  var p = pool_of(1, POOL_POLICY_FIFO, 4);
  var ok = dispatch_err_is(&mut p, "pool: no eligible jobs");
  if dispatches_of(&mut p) != 0 { ok = false; }
  if !invariant_of(&mut p) { ok = false; }
  if submit_ok(&mut p, 1, 0, 2) != 0 { ok = false; }
  if dispatch_ok(&mut p) != 1 { ok = false; }
  if submit_ok(&mut p, 2, 0, 2) != 1 { ok = false; }
  if !dispatch_err_is(&mut p, "pool: no idle workers") { ok = false; }
  if dispatches_of(&mut p) != 1 { ok = false; }
  if !invariant_of(&mut p) { ok = false; }
  return assert(ok, "pool_dispatch reports an empty queue and a fully busy pool distinctly");
}

fn t8() -> TestResult {
  var p = pool_of(2, POOL_POLICY_FIFO, 4);
  var ok = submit_ok(&mut p, 1, 0, 2) == 0;
  if submit_ok(&mut p, 2, 0, 2) != 1 { ok = false; }
  if submit_ok(&mut p, 3, 0, 2) != 2 { ok = false; }
  if submit_ok(&mut p, 4, 0, 1) != 3 { ok = false; }
  if !assign_err_is(&mut p, 99, 0, "pool: unknown job id") { ok = false; }
  if !assign_err_is(&mut p, 1, -1, "pool: worker index must be >= 0") { ok = false; }
  if !assign_err_is(&mut p, 1, 5, "pool: unknown worker index") { ok = false; }
  if assign_ok(&mut p, 1, 0) != 1 { ok = false; }
  if attempts_of(&mut p, 1) != 1 { ok = false; }
  if job_worker_of(&mut p, 1) != 0 { ok = false; }
  if !assign_err_is(&mut p, 1, 1, "pool: job already leased") { ok = false; }
  if !assign_err_is(&mut p, 2, 0, "pool: worker is not idle") { ok = false; }
  if fail_ok(&mut p, 1) != 1 { ok = false; }
  if state_of(&mut p, 1) != JOB_RETRY_WAIT { ok = false; }
  if !assign_err_is(&mut p, 1, 1, "pool: job is waiting for retry") { ok = false; }
  if assign_ok(&mut p, 2, 1) != 2 { ok = false; }
  if complete_ok(&mut p, 2) != 1 { ok = false; }
  if !assign_err_is(&mut p, 2, 1, "pool: job already complete") { ok = false; }
  if dispatch_ok(&mut p) != 3 { ok = false; }
  if fail_ok(&mut p, 3) != 1 { ok = false; }
  if dispatch_ok(&mut p) != 4 { ok = false; }
  if fail_ok(&mut p, 4) != 1 { ok = false; }
  if state_of(&mut p, 4) != JOB_FAILED { ok = false; }
  if !assign_err_is(&mut p, 4, 1, "pool: job already failed") { ok = false; }
  if dispatches_of(&mut p) != 4 { ok = false; }
  if !invariant_of(&mut p) { ok = false; }
  return assert(ok, "pool_assign validates the job lifecycle, worker index and idleness");
}

fn t9() -> TestResult {
  var p = pool_of(1, POOL_POLICY_FIFO, 4);
  var ok = complete_err_is(&mut p, 99, "pool: unknown job id");
  if !fail_err_is(&mut p, 99, "pool: unknown job id") { ok = false; }
  if submit_ok(&mut p, 1, 0, 2) != 0 { ok = false; }
  if submit_ok(&mut p, 2, 0, 1) != 1 { ok = false; }
  if !complete_err_is(&mut p, 1, "pool: job is not leased") { ok = false; }
  if !fail_err_is(&mut p, 1, "pool: job is not leased") { ok = false; }
  if dispatch_ok(&mut p) != 1 { ok = false; }
  if complete_ok(&mut p, 1) != 1 { ok = false; }
  if state_of(&mut p, 1) != JOB_DONE { ok = false; }
  if job_worker_of(&mut p, 1) != -1 { ok = false; }
  if worker_state_of(&mut p, 0) != WORKER_IDLE { ok = false; }
  if lease_until_of(&mut p, 0) != 0 { ok = false; }
  if !complete_err_is(&mut p, 1, "pool: job already complete") { ok = false; }
  if !fail_err_is(&mut p, 1, "pool: job already complete") { ok = false; }
  if dispatch_ok(&mut p) != 2 { ok = false; }
  if fail_ok(&mut p, 2) != 1 { ok = false; }
  if state_of(&mut p, 2) != JOB_FAILED { ok = false; }
  if !complete_err_is(&mut p, 2, "pool: job already failed") { ok = false; }
  if !fail_err_is(&mut p, 2, "pool: job already failed") { ok = false; }
  if completions_of(&mut p) != 1 { ok = false; }
  if failures_of(&mut p) != 1 { ok = false; }
  if !invariant_of(&mut p) { ok = false; }
  return assert(ok, "pool_complete/pool_fail validate the LEASED state and release the worker");
}

fn t10() -> TestResult {
  var p = pool_of(1, POOL_POLICY_FIFO, 10);
  var ok = submit_ok(&mut p, 7, 0, 3) == 0;
  if dispatch_ok(&mut p) != 7 { ok = false; }
  if fail_ok(&mut p, 7) != 1 { ok = false; }
  if state_of(&mut p, 7) != JOB_RETRY_WAIT { ok = false; }
  if ready_tick_of(&mut p, 7) != 1 { ok = false; }
  if retries_of(&mut p) != 1 { ok = false; }
  if backoff_total_of(&mut p) != 1 { ok = false; }
  if attempt_failures_of(&mut p) != 1 { ok = false; }
  if failures_of(&mut p) != 0 { ok = false; }
  if worker_state_of(&mut p, 0) != WORKER_IDLE { ok = false; }
  if tick_ok(&mut p, 1) != 1 { ok = false; }
  if state_of(&mut p, 7) != JOB_QUEUED { ok = false; }
  if dispatch_ok(&mut p) != 7 { ok = false; }
  if attempts_of(&mut p, 7) != 2 { ok = false; }
  if fail_ok(&mut p, 7) != 2 { ok = false; }
  if ready_tick_of(&mut p, 7) != 3 { ok = false; }
  if retries_of(&mut p) != 2 { ok = false; }
  if backoff_total_of(&mut p) != 3 { ok = false; }
  if tick_ok(&mut p, 1) != 2 { ok = false; }
  if state_of(&mut p, 7) != JOB_RETRY_WAIT { ok = false; }
  if tick_ok(&mut p, 1) != 3 { ok = false; }
  if state_of(&mut p, 7) != JOB_QUEUED { ok = false; }
  if dispatch_ok(&mut p) != 7 { ok = false; }
  if attempts_of(&mut p, 7) != 3 { ok = false; }
  if fail_ok(&mut p, 7) != 3 { ok = false; }
  if state_of(&mut p, 7) != JOB_FAILED { ok = false; }
  if failures_of(&mut p) != 1 { ok = false; }
  if attempt_failures_of(&mut p) != 3 { ok = false; }
  if retries_of(&mut p) != 2 { ok = false; }
  if backoff_total_of(&mut p) != 3 { ok = false; }
  if wait_of(&mut p, 7) != 3 { ok = false; }
  if queued_of(&mut p, 7) != 0 { ok = false; }
  if !invariant_of(&mut p) { ok = false; }
  return assert(ok, "failure retries with doubling backoff until the attempt limit fails the job");
}

fn t11() -> TestResult {
  var p = pool_of(1, POOL_POLICY_FIFO, 3);
  var ok = submit_ok(&mut p, 1, 0, 2) == 0;
  if !tick_err_is(&mut p, -1, "pool: ticks must be >= 0") { ok = false; }
  if now_of(&mut p) != 0 { ok = false; }
  if tick_ok(&mut p, 0) != 0 { ok = false; }
  if tick_ok(&mut p, 2) != 2 { ok = false; }
  if wait_of(&mut p, 1) != 2 { ok = false; }
  if queued_of(&mut p, 1) != 2 { ok = false; }
  if dispatch_ok(&mut p) != 1 { ok = false; }
  if lease_until_of(&mut p, 0) != 5 { ok = false; }
  if remaining_of(&mut p, 0) != 3 { ok = false; }
  if tick_ok(&mut p, 2) != 4 { ok = false; }
  if wait_of(&mut p, 1) != 4 { ok = false; }
  if queued_of(&mut p, 1) != 2 { ok = false; }
  if worker_busy_of(&mut p, 0) != 2 { ok = false; }
  if tick_ok(&mut p, 2) != 6 { ok = false; }
  if wait_of(&mut p, 1) != 6 { ok = false; }
  if worker_busy_of(&mut p, 0) != 3 { ok = false; }
  if expired_of(&mut p) != 1 { ok = false; }
  if state_of(&mut p, 1) != JOB_RETRY_WAIT { ok = false; }
  if ready_tick_of(&mut p, 1) != 7 { ok = false; }
  if attempt_failures_of(&mut p) != 1 { ok = false; }
  if retries_of(&mut p) != 1 { ok = false; }
  if backoff_total_of(&mut p) != 1 { ok = false; }
  if worker_state_of(&mut p, 0) != WORKER_IDLE { ok = false; }
  if tick_ok(&mut p, 1) != 7 { ok = false; }
  if state_of(&mut p, 1) != JOB_QUEUED { ok = false; }
  if tick_ok(&mut p, 1) != 8 { ok = false; }
  if wait_of(&mut p, 1) != 8 { ok = false; }
  if queued_of(&mut p, 1) != 3 { ok = false; }
  if dispatch_ok(&mut p) != 1 { ok = false; }
  if attempts_of(&mut p, 1) != 2 { ok = false; }
  if complete_ok(&mut p, 1) != 1 { ok = false; }
  if !invariant_of(&mut p) { ok = false; }
  return assert(ok, "pool_tick accrues wait/queued/busy ticks, expires leases and promotes retries");
}

fn t12() -> TestResult {
  var p = pool_of(1, POOL_POLICY_FIFO, 5);
  var ok = submit_ok(&mut p, 1, 0, 1) == 0;
  if dispatch_ok(&mut p) != 1 { ok = false; }
  if fail_ok(&mut p, 1) != 1 { ok = false; }
  if state_of(&mut p, 1) != JOB_FAILED { ok = false; }
  if failures_of(&mut p) != 1 { ok = false; }
  if retries_of(&mut p) != 0 { ok = false; }
  if backoff_total_of(&mut p) != 0 { ok = false; }
  if attempt_failures_of(&mut p) != 1 { ok = false; }
  if worker_state_of(&mut p, 0) != WORKER_IDLE { ok = false; }
  if !invariant_of(&mut p) { ok = false; }
  return assert(ok, "max_attempts = 1 fails a job on its first failed attempt");
}

fn t13() -> TestResult {
  var p = pool_of(1, POOL_POLICY_FIFO, 2);
  var ok = submit_ok(&mut p, 1, 0, 1) == 0;
  if dispatch_ok(&mut p) != 1 { ok = false; }
  if tick_ok(&mut p, 2) != 2 { ok = false; }
  if expired_of(&mut p) != 1 { ok = false; }
  if state_of(&mut p, 1) != JOB_FAILED { ok = false; }
  if failures_of(&mut p) != 1 { ok = false; }
  if retries_of(&mut p) != 0 { ok = false; }
  if attempt_failures_of(&mut p) != 1 { ok = false; }
  if worker_state_of(&mut p, 0) != WORKER_IDLE { ok = false; }
  if !invariant_of(&mut p) { ok = false; }
  return assert(ok, "lease expiry at the attempt limit fails the job terminally");
}

fn t14() -> TestResult {
  var p = pool_of(1, POOL_POLICY_PRIORITY, 100);
  var ok = submit_ok(&mut p, 1, 0, 3) == 0;
  if tick_ok(&mut p, 3) != 3 { ok = false; }
  var i = 0;
  while i < 8 {
    let hid = 100 + i;
    if submit_ok(&mut p, hid, 5, 2) != i + 1 { ok = false; }
    if tick_ok(&mut p, 1) != 4 + i { ok = false; }
    if dispatch_ok(&mut p) != hid { ok = false; }
    if complete_ok(&mut p, hid) != i + 1 { ok = false; }
    i = i + 1;
  }
  if skips_of(&mut p, 1) != 8 { ok = false; }
  if starve_skips_of(&mut p) != 8 { ok = false; }
  if starve_events_of(&mut p) != 1 { ok = false; }
  if fair_of(&mut p) != 0 { ok = false; }
  if unfair_of(&mut p) != 8 { ok = false; }
  if max_wait_of(&mut p) != 11 { ok = false; }
  if wait_of(&mut p, 1) != 11 { ok = false; }
  if queued_of(&mut p, 1) != 11 { ok = false; }
  if dispatch_ok(&mut p) != 1 { ok = false; }
  if fair_of(&mut p) != 1 { ok = false; }
  if complete_ok(&mut p, 1) != 9 { ok = false; }
  if !invariant_of(&mut p) { ok = false; }
  return assert(ok, "starvation counters track skips, threshold events and unfair dispatches");
}

fn t15() -> TestResult {
  var p = pool_of(1, POOL_POLICY_FIFO, 10);
  var ok = submit_ok(&mut p, 1, 0, 2) == 0;
  if submit_ok(&mut p, 2, 0, 2) != 1 { ok = false; }
  if dispatch_ok(&mut p) != 1 { ok = false; }
  if skips_of(&mut p, 2) != 1 { ok = false; }
  if starve_skips_of(&mut p) != 1 { ok = false; }
  if fair_of(&mut p) != 1 { ok = false; }
  if unfair_of(&mut p) != 0 { ok = false; }
  if starve_events_of(&mut p) != 0 { ok = false; }
  if complete_ok(&mut p, 1) != 1 { ok = false; }
  if dispatch_ok(&mut p) != 2 { ok = false; }
  if fair_of(&mut p) != 2 { ok = false; }
  if skips_of(&mut p, 2) != 1 { ok = false; }
  if complete_ok(&mut p, 2) != 2 { ok = false; }
  if !invariant_of(&mut p) { ok = false; }
  return assert(ok, "FIFO dispatch counts as fair and skips only the jobs it passes over");
}

fn t16() -> TestResult {
  var p = pool_of(2, POOL_POLICY_FIFO, 4);
  var ok = submit_ok(&mut p, 1, 0, 2) == 0;
  if submit_ok(&mut p, 2, 0, 2) != 1 { ok = false; }
  if dispatch_ok(&mut p) != 1 { ok = false; }
  if worker_state_of(&mut p, 0) != WORKER_BUSY { ok = false; }
  if worker_job_of(&mut p, 0) != 1 { ok = false; }
  if remaining_of(&mut p, 0) != 4 { ok = false; }
  if worker_leases_of(&mut p, 0) != 1 { ok = false; }
  if worker_busy_of(&mut p, 0) != 0 { ok = false; }
  if tick_ok(&mut p, 1) != 1 { ok = false; }
  if remaining_of(&mut p, 0) != 3 { ok = false; }
  if worker_busy_of(&mut p, 0) != 1 { ok = false; }
  if worker_state_of(&mut p, 2) != POOL_NOT_FOUND { ok = false; }
  if worker_job_of(&mut p, 2) != POOL_NOT_FOUND { ok = false; }
  if lease_until_of(&mut p, 2) != POOL_NOT_FOUND { ok = false; }
  if remaining_of(&mut p, 2) != POOL_NOT_FOUND { ok = false; }
  if worker_leases_of(&mut p, 2) != POOL_NOT_FOUND { ok = false; }
  if worker_busy_of(&mut p, 2) != POOL_NOT_FOUND { ok = false; }
  if remaining_of(&mut p, 1) != 0 { ok = false; }
  if complete_ok(&mut p, 1) != 1 { ok = false; }
  if worker_state_of(&mut p, 0) != WORKER_IDLE { ok = false; }
  if remaining_of(&mut p, 0) != 0 { ok = false; }
  if lease_until_of(&mut p, 0) != 0 { ok = false; }
  if !invariant_of(&mut p) { ok = false; }
  return assert(ok, "worker accessors expose lease state, remaining ticks and sentinels");
}

fn t17() -> TestResult {
  var p = pool_of(2, POOL_POLICY_FIFO, 5);
  var ok = submit_ok(&mut p, 1, 0, 2) == 0;
  if dispatch_ok(&mut p) != 1 { ok = false; }
  if complete_ok(&mut p, 1) != 1 { ok = false; }
  let s = stats_of(&mut p);
  if s.size != 2 { ok = false; }
  if s.idle != 2 { ok = false; }
  if s.busy != 0 { ok = false; }
  if s.queued != 0 { ok = false; }
  if s.leased != 0 { ok = false; }
  if s.retry_waiting != 0 { ok = false; }
  if s.done != 1 { ok = false; }
  if s.failed != 0 { ok = false; }
  if s.jobs != 1 { ok = false; }
  if s.submitted != 1 { ok = false; }
  if s.dispatches != 1 { ok = false; }
  if s.completions != 1 { ok = false; }
  if s.failures != 0 { ok = false; }
  if s.attempt_failures != 0 { ok = false; }
  if s.retries != 0 { ok = false; }
  if s.backoff_ticks != 0 { ok = false; }
  if s.leases_expired != 0 { ok = false; }
  if s.starvation_skips != 0 { ok = false; }
  if s.starvation_events != 0 { ok = false; }
  if s.fair_dispatches != 1 { ok = false; }
  if s.unfair_dispatches != 0 { ok = false; }
  if s.max_wait_ticks != 0 { ok = false; }
  if s.now != 0 { ok = false; }
  let text = stats_text_of(&mut p);
  if !streq(text, _STATS_ONE_DONE) { ok = false; }
  if submit_ok(&mut p, 2, 0, 2) != 1 { ok = false; }
  if s.jobs != 1 { ok = false; }
  if s.done != 1 { ok = false; }
  if s.now != 0 { ok = false; }
  if job_count_of(&mut p) != 2 { ok = false; }
  return assert(ok, "pool_stats returns an independent snapshot and pool_stats_text renders it");
}

fn try_worker(p: &mut WorkerPool, w: Int) -> Bool {
  return worker_state_of(p, w) == POOL_NOT_FOUND && worker_job_of(p, w) == POOL_NOT_FOUND && lease_until_of(p, w) == POOL_NOT_FOUND && remaining_of(p, w) == POOL_NOT_FOUND && worker_leases_of(p, w) == POOL_NOT_FOUND && worker_busy_of(p, w) == POOL_NOT_FOUND;
}

fn t18() -> TestResult {
  var p = pool_of(1, POOL_POLICY_FIFO, 4);
  var ok = submit_ok(&mut p, 7, 3, 2) == 0;
  if order_of(&mut p, 99) != POOL_NOT_FOUND { ok = false; }
  if attempts_of(&mut p, 99) != POOL_NOT_FOUND { ok = false; }
  if max_attempts_of(&mut p, 99) != POOL_NOT_FOUND { ok = false; }
  if ready_tick_of(&mut p, 99) != POOL_NOT_FOUND { ok = false; }
  if submit_tick_of(&mut p, 99) != POOL_NOT_FOUND { ok = false; }
  if job_worker_of(&mut p, 99) != POOL_NOT_FOUND { ok = false; }
  if wait_of(&mut p, 99) != POOL_NOT_FOUND { ok = false; }
  if queued_of(&mut p, 99) != POOL_NOT_FOUND { ok = false; }
  if skips_of(&mut p, 99) != POOL_NOT_FOUND { ok = false; }
  if !try_worker(&mut p, -1) { ok = false; }
  if !invariant_of(&mut p) { ok = false; }
  return assert(ok, "job and worker accessors return documented sentinels for unknown ids");
}

fn t19() -> TestResult {
  var p = pool_of(3, POOL_POLICY_FIFO, 4);
  var ok = true;
  var expected_submitted = 0;
  var i = 0;
  while i < 40 {
    if i % 5 == 0 {
      let id = 1000 + i;
      let pos = submit_ok(&mut p, id, i % 4, 1 + (i % 3));
      if pos != expected_submitted { ok = false; }
      expected_submitted = expected_submitted + 1;
    }
    let t = tick_ok(&mut p, i % 3);
    if t < 0 { ok = false; }
    var id2 = dispatch_ok(&mut p);
    while id2 >= 0 {
      if id2 % 2 == 0 {
        if complete_ok(&mut p, id2) < 0 { ok = false; }
      } else {
        if fail_ok(&mut p, id2) < 0 { ok = false; }
      }
      id2 = dispatch_ok(&mut p);
    }
    if !invariant_of(&mut p) { ok = false; }
    i = i + 1;
  }
  if submitted_of(&mut p) != expected_submitted { ok = false; }
  let s = stats_of(&mut p);
  if s.done + s.failed + s.queued + s.leased + s.retry_waiting != expected_submitted { ok = false; }
  if !invariant_of(&mut p) { ok = false; }
  return assert(ok, "the structural invariant holds across 40 mixed submission/dispatch cycles");
}

fn t20() -> TestResult {
  var p = pool_of(1, POOL_POLICY_PRIORITY, 4);
  var ok = submit_ok(&mut p, 1, 1, 2) == 0;
  if submit_ok(&mut p, 2, 9, 2) != 1 { ok = false; }
  let before = stats_text_of(&mut p);
  let x = pick_of(&mut p);
  let y = pick_of(&mut p);
  let after = stats_text_of(&mut p);
  if x != 2 { ok = false; }
  if y != 2 { ok = false; }
  if !streq(before, after) { ok = false; }
  if !invariant_of(&mut p) { ok = false; }
  return assert(ok, "pool_pick_job is a pure read-only probe");
}

fn t21() -> TestResult {
  var p = pool_of(1, POOL_POLICY_PRIORITY, 4);
  var ok = submit_ok(&mut p, 1, 0, 2) == 0;
  if submit_ok(&mut p, 2, 9, 2) != 1 { ok = false; }
  if pick_of(&mut p) != 2 { ok = false; }
  if assign_ok(&mut p, 1, 0) != 1 { ok = false; }
  if attempts_of(&mut p, 1) != 1 { ok = false; }
  if dispatches_of(&mut p) != 1 { ok = false; }
  if fair_of(&mut p) != 0 { ok = false; }
  if unfair_of(&mut p) != 0 { ok = false; }
  if starve_skips_of(&mut p) != 0 { ok = false; }
  if skips_of(&mut p, 2) != 0 { ok = false; }
  if complete_ok(&mut p, 1) != 1 { ok = false; }
  if pick_of(&mut p) != 2 { ok = false; }
  if dispatch_ok(&mut p) != 2 { ok = false; }
  if fair_of(&mut p) != 1 { ok = false; }
  if !invariant_of(&mut p) { ok = false; }
  return assert(ok, "pool_assign bypasses policy, fairness and starvation accounting");
}

fn t22() -> TestResult {
  var p = pool_of(2, POOL_POLICY_FIFO, 2);
  var ok = submit_ok(&mut p, 1, 0, 2) == 0;
  if submit_ok(&mut p, 2, 0, 2) != 1 { ok = false; }
  if dispatch_ok(&mut p) != 1 { ok = false; }
  if dispatch_ok(&mut p) != 2 { ok = false; }
  if tick_ok(&mut p, 10) != 10 { ok = false; }
  if expired_of(&mut p) != 2 { ok = false; }
  if state_of(&mut p, 1) != JOB_RETRY_WAIT { ok = false; }
  if state_of(&mut p, 2) != JOB_RETRY_WAIT { ok = false; }
  if ready_tick_of(&mut p, 1) != 11 { ok = false; }
  if ready_tick_of(&mut p, 2) != 11 { ok = false; }
  if attempt_failures_of(&mut p) != 2 { ok = false; }
  if retries_of(&mut p) != 2 { ok = false; }
  if backoff_total_of(&mut p) != 2 { ok = false; }
  if worker_state_of(&mut p, 0) != WORKER_IDLE { ok = false; }
  if worker_state_of(&mut p, 1) != WORKER_IDLE { ok = false; }
  if worker_busy_of(&mut p, 0) != 2 { ok = false; }
  if worker_busy_of(&mut p, 1) != 2 { ok = false; }
  if wait_of(&mut p, 1) != 10 { ok = false; }
  if tick_ok(&mut p, 1) != 11 { ok = false; }
  if state_of(&mut p, 1) != JOB_QUEUED { ok = false; }
  if state_of(&mut p, 2) != JOB_QUEUED { ok = false; }
  if dispatch_ok(&mut p) != 1 { ok = false; }
  if attempts_of(&mut p, 1) != 2 { ok = false; }
  if complete_ok(&mut p, 1) != 1 { ok = false; }
  if !invariant_of(&mut p) { ok = false; }
  return assert(ok, "one large tick expires every due lease and anchors backoff at the new now");
}

fn t23() -> TestResult {
  var ok = pool_backoff_delay(1) == 1;
  if pool_backoff_delay(2) != 2 { ok = false; }
  if pool_backoff_delay(3) != 4 { ok = false; }
  if pool_backoff_delay(4) != 8 { ok = false; }
  if pool_backoff_delay(5) != 16 { ok = false; }
  if pool_backoff_delay(6) != 32 { ok = false; }
  if pool_backoff_delay(7) != 64 { ok = false; }
  if pool_backoff_delay(8) != 64 { ok = false; }
  if pool_backoff_delay(100) != 64 { ok = false; }
  if pool_backoff_delay(0) != 1 { ok = false; }
  if pool_backoff_delay(-3) != 1 { ok = false; }
  return assert(ok, "pool_backoff_delay doubles from BASE and clamps at CAP");
}

fn t24() -> TestResult {
  var ok = streq(pool_policy_name(POOL_POLICY_FIFO), "fifo");
  if !streq(pool_policy_name(POOL_POLICY_PRIORITY), "priority") { ok = false; }
  if !streq(pool_policy_name(9), "unknown") { ok = false; }
  if !streq(pool_job_state_name(JOB_QUEUED), "queued") { ok = false; }
  if !streq(pool_job_state_name(JOB_LEASED), "leased") { ok = false; }
  if !streq(pool_job_state_name(JOB_RETRY_WAIT), "retry_wait") { ok = false; }
  if !streq(pool_job_state_name(JOB_DONE), "done") { ok = false; }
  if !streq(pool_job_state_name(JOB_FAILED), "failed") { ok = false; }
  if !streq(pool_job_state_name(-1), "unknown") { ok = false; }
  if !streq(pool_worker_state_name(WORKER_IDLE), "idle") { ok = false; }
  if !streq(pool_worker_state_name(WORKER_BUSY), "busy") { ok = false; }
  if !streq(pool_worker_state_name(9), "unknown") { ok = false; }
  return assert(ok, "policy, job-state and worker-state name helpers are stable");
}

fn t25() -> TestResult {
  var p = pool_of(1, POOL_POLICY_FIFO, 2);
  var ok = submit_ok(&mut p, 1, 0, 3) == 0;
  if dispatch_ok(&mut p) != 1 { ok = false; }
  if fail_ok(&mut p, 1) != 1 { ok = false; }
  if retries_of(&mut p) != 1 { ok = false; }
  if tick_ok(&mut p, 1) != 1 { ok = false; }
  if dispatch_ok(&mut p) != 1 { ok = false; }
  if tick_ok(&mut p, 2) != 3 { ok = false; }
  if expired_of(&mut p) != 1 { ok = false; }
  if retries_of(&mut p) != 2 { ok = false; }
  if backoff_total_of(&mut p) != 3 { ok = false; }
  if attempt_failures_of(&mut p) != 2 { ok = false; }
  if ready_tick_of(&mut p, 1) != 5 { ok = false; }
  if tick_ok(&mut p, 2) != 5 { ok = false; }
  if dispatch_ok(&mut p) != 1 { ok = false; }
  if fail_ok(&mut p, 1) != 3 { ok = false; }
  if state_of(&mut p, 1) != JOB_FAILED { ok = false; }
  if submitted_of(&mut p) != 1 { ok = false; }
  if dispatches_of(&mut p) != 3 { ok = false; }
  if completions_of(&mut p) != 0 { ok = false; }
  if failures_of(&mut p) != 1 { ok = false; }
  if attempt_failures_of(&mut p) != 3 { ok = false; }
  if retries_of(&mut p) != 2 { ok = false; }
  if backoff_total_of(&mut p) != 3 { ok = false; }
  if expired_of(&mut p) != 1 { ok = false; }
  if !invariant_of(&mut p) { ok = false; }
  return assert(ok, "counters accumulate across fails, retries, expiries and terminal failure");
}

fn t26() -> TestResult {
  var a = deterministic_scenario();
  var b = deterministic_scenario();
  var ok = streq(stats_text_of(&mut a), stats_text_of(&mut b));
  var i = 1;
  while i <= 3 {
    if state_of(&mut a, i) != state_of(&mut b, i) { ok = false; }
    if attempts_of(&mut a, i) != attempts_of(&mut b, i) { ok = false; }
    if wait_of(&mut a, i) != wait_of(&mut b, i) { ok = false; }
    if queued_of(&mut a, i) != queued_of(&mut b, i) { ok = false; }
    if skips_of(&mut a, i) != skips_of(&mut b, i) { ok = false; }
    i = i + 1;
  }
  if dispatches_of(&mut a) < 3 { ok = false; }
  if expired_of(&mut a) != 1 { ok = false; }
  if !invariant_of(&mut a) { ok = false; }
  if !invariant_of(&mut b) { ok = false; }
  return assert(ok, "identical operation sequences produce identical pool statistics");
}

fn main() -> Int {
  io.println("=== xiom.worker conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.worker: all tests passed");
  } else {
    io.println("xiom.worker: tests failed");
  }
  return failed;
}
