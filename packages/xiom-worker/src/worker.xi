// XIOM -- xiom.worker: deterministic worker-pool scheduling model
// Port task: replace the xiom.worker placeholder with a real, tested,
// pure-XIOM package (no FFI, no threads, no wall clock).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model: a worker pool as a pure, deterministic state machine -- the
// scheduling core a thread pool or job runner would drive. There are no
// threads, no atomics, no locks, no clock and no I/O here: the caller owns
// concurrency and every function is a total transition over plain values.
// Time is an explicit integer tick counter advanced only by pool_tick.
//
// The pool owns:
//   * a fixed worker table (size workers) with lease state: IDLE or BUSY,
//     the job id physically leased by each worker, the lease expiry tick,
//     and per-worker lease/busy-tick counters (fairness accounting);
//   * a job table as thirteen parallel Vec[Int] fields: ids, priorities,
//     submission sequences, states, attempt counts, attempt limits, the
//     earliest tick a job may be leased, submit ticks, holding worker slots,
//     total wait ticks, queued ticks, starvation skip counts;
//   * two selection policies over the eligible (QUEUED) jobs: FIFO
//     (smallest submission sequence) and PRIORITY (largest priority, ties
//     broken by smallest submission sequence -- stable and deterministic);
//   * leases: pool_dispatch auto-assigns the lowest-idle worker,
//     pool_assign leases an explicit worker; a lease expires when the pool
//     clock reaches its expiry tick, which routes the job through the same
//     retry/backoff path as an explicit failure;
//   * retry with backoff accounting: a failed attempt either schedules a
//     retry (RETRY_WAIT until now + delay, delay = min(BASE * FACTOR^
//     (attempt-1), CAP)) or fails the job terminally at the attempt limit;
//   * starvation/fairness counters: skip counts per job, pool-wide skips,
//     starvation events (a job crossing POOL_STARVATION_THRESHOLD skips),
//     fair/unfair dispatch counts and the max eligible-wait high-water mark;
//   * statistics snapshots: pool_stats returns a PoolStats value copy and
//     pool_stats_text a one-line rendering.
//
// Job states:   QUEUED -> LEASED -> DONE | FAILED, with LEASED -> RETRY_WAIT
// (via pool_fail or lease expiry) and RETRY_WAIT -> QUEUED when the backoff
// elapses (processed by pool_tick).
// Worker states: IDLE <-> BUSY.
//
// Language notes (XIOM v0.62.1): free functions only; Ok/Err are constructed
// only inside the _ok_*/_err_* leaf helpers; Vec[Int] element reads are bound
// with a typed `let`; parallel Vec fields are always pushed/updated together
// so they can never skew; no Vec[StructType], no indexed Vec[fn] dispatch, no
// generic callbacks, no Vec[Float64], no `mut` in match patterns, no `log`-
// named function, no FFI, no threads. No Str is compared with `==`; the
// library needs no string comparison at all.

module xiom.worker

use xiom.convert;

// ---------------------------------------------------------------------------
// Public constants
// ---------------------------------------------------------------------------

/// Ready-queue selection policy: first in, first out (smallest submission
/// sequence among eligible jobs).
pub const POOL_POLICY_FIFO: Int = 0;

/// Ready-queue selection policy: largest priority first, ties broken by the
/// smallest submission sequence (stable by submission order).
pub const POOL_POLICY_PRIORITY: Int = 1;

/// Worker state: no lease held.
pub const WORKER_IDLE: Int = 0;

/// Worker state: a lease is active.
pub const WORKER_BUSY: Int = 1;

/// Job state: eligible for a lease at the current tick.
pub const JOB_QUEUED: Int = 0;

/// Job state: currently leased by a worker.
pub const JOB_LEASED: Int = 1;

/// Job state: waiting for the retry backoff to elapse.
pub const JOB_RETRY_WAIT: Int = 2;

/// Job state: completed successfully.
pub const JOB_DONE: Int = 3;

/// Job state: failed terminally (attempt limit reached).
pub const JOB_FAILED: Int = 4;

/// Sentinel: the worker holds no job.
pub const POOL_NO_JOB: Int = -1;

/// Sentinel: the job holds no worker.
pub const POOL_NO_WORKER: Int = -1;

/// Sentinel: unknown id / out-of-range accessor result.
pub const POOL_NOT_FOUND: Int = -1;

/// Backoff base: the delay of the first retry, in ticks.
pub const POOL_BACKOFF_BASE: Int = 1;

/// Backoff factor: the delay doubles per failed attempt.
pub const POOL_BACKOFF_FACTOR: Int = 2;

/// Backoff cap: the maximum retry delay, in ticks.
pub const POOL_BACKOFF_CAP: Int = 64;

/// Starvation threshold: the number of times one job must be passed over by
/// dispatch before the pool counts one starvation event.
pub const POOL_STARVATION_THRESHOLD: Int = 8;

/// Worker pool state. Every field is an internal implementation detail;
/// callers must go through the pool_*/worker_* free functions.
///
/// Workers are stored as five parallel Vec[Int] fields indexed by worker slot
/// (0 .. size-1): worker_states[i] (a WORKER_* code), worker_jobs[i] (the
/// leased job id or POOL_NO_JOB), worker_lease_until[i] (the lease expiry
/// tick while BUSY, 0 while IDLE), worker_leases[i] (leases taken) and
/// worker_busy_ticks[i] (ticks spent BUSY). Jobs are stored as thirteen
/// parallel Vec[Int] fields indexed by job slot: job_ids[i], job_priorities
/// [i], job_orders[i] (the dense submission sequence assigned by
/// pool_submit), job_states[i] (a JOB_* code), job_attempts[i],
/// job_max_attempts[i], job_ready_tick[i] (earliest tick the job may be
/// leased), job_submit_tick[i], job_worker[i] (holding worker slot or -1),
/// job_wait_ticks[i] (ticks since submission while non-terminal),
/// job_queued_ticks[i] (ticks spent QUEUED), job_skips[i] (dispatch
/// pass-overs) and job_wait... see the accessors. `now` is the logical tick
/// clock, advanced only by pool_tick. Counters: submitted, dispatches,
/// completions, failures (terminal), attempt_failures (every failed
/// attempt), retries, backoff_ticks (total scheduled delay), leases_expired,
/// starvation_skips, starvation_events, fair_dispatches, unfair_dispatches
/// and max_wait_ticks (high-water mark of eligible queued time at dispatch).
pub type WorkerPool = {
  policy: Int;
  size: Int;
  lease_ticks: Int;
  now: Int;
  worker_states: Vec[Int];
  worker_jobs: Vec[Int];
  worker_lease_until: Vec[Int];
  worker_leases: Vec[Int];
  worker_busy_ticks: Vec[Int];
  job_ids: Vec[Int];
  job_priorities: Vec[Int];
  job_orders: Vec[Int];
  job_states: Vec[Int];
  job_attempts: Vec[Int];
  job_max_attempts: Vec[Int];
  job_ready_tick: Vec[Int];
  job_submit_tick: Vec[Int];
  job_worker: Vec[Int];
  job_wait_ticks: Vec[Int];
  job_queued_ticks: Vec[Int];
  job_skips: Vec[Int];
  submitted: Int;
  dispatches: Int;
  completions: Int;
  failures: Int;
  attempt_failures: Int;
  retries: Int;
  backoff_ticks: Int;
  leases_expired: Int;
  starvation_skips: Int;
  starvation_events: Int;
  fair_dispatches: Int;
  unfair_dispatches: Int;
  max_wait_ticks: Int;
}

/// Read-only statistics snapshot of a pool. Returned by value, so a snapshot
/// taken before a mutation is unaffected by it. All fields mirror the pool
/// counters plus current state counts.
pub type PoolStats = {
  size: Int;
  idle: Int;
  busy: Int;
  queued: Int;
  leased: Int;
  retry_waiting: Int;
  done: Int;
  failed: Int;
  jobs: Int;
  submitted: Int;
  dispatches: Int;
  completions: Int;
  failures: Int;
  attempt_failures: Int;
  retries: Int;
  backoff_ticks: Int;
  leases_expired: Int;
  starvation_skips: Int;
  starvation_events: Int;
  fair_dispatches: Int;
  unfair_dispatches: Int;
  max_wait_ticks: Int;
  now: Int;
}

// ---------------------------------------------------------------------------
// Result constructors (leaf helpers only; see the header comment)
// ---------------------------------------------------------------------------

fn _ok_pool(v: WorkerPool) -> Result[WorkerPool, Str] { return Ok(v); }
fn _err_pool(m: Str) -> Result[WorkerPool, Str] { return Err(m); }
fn _ok_int(v: Int) -> Result[Int, Str] { return Ok(v); }
fn _err_int(m: Str) -> Result[Int, Str] { return Err(m); }

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

fn _is_valid_policy(policy: Int) -> Bool {
  if policy == POOL_POLICY_FIFO { return true; }
  if policy == POOL_POLICY_PRIORITY { return true; }
  return false;
}

// Slot of job `id` in the job vectors, or -1 when unknown.
fn _job_index(p: &WorkerPool, id: Int) -> Int {
  var i = 0;
  while i < p.job_ids.len() {
    let cur: Int = p.job_ids[i];
    if cur == id { return i; }
    i = i + 1;
  }
  return -1;
}

fn _count_jobs(p: &WorkerPool, state: Int) -> Int {
  var n = 0;
  var i = 0;
  while i < p.job_states.len() {
    let st: Int = p.job_states[i];
    if st == state { n = n + 1; }
    i = i + 1;
  }
  return n;
}

fn _count_workers(p: &WorkerPool, state: Int) -> Int {
  var n = 0;
  var w = 0;
  while w < p.size {
    let st: Int = p.worker_states[w];
    if st == state { n = n + 1; }
    w = w + 1;
  }
  return n;
}

// True when job slot `i` may be leased at the current tick.
fn _eligible(p: &WorkerPool, i: Int) -> Bool {
  let st: Int = p.job_states[i];
  if st != JOB_QUEUED { return false; }
  let ready: Int = p.job_ready_tick[i];
  return ready <= p.now;
}

// Slot of the eligible job chosen by the pool policy, or -1 when none is
// eligible. The scan is left-to-right over submission order, so the first
// candidate wins residual ties.
fn _pick_job_slot(p: &WorkerPool) -> Int {
  var best = -1;
  var i = 0;
  while i < p.job_ids.len() {
    if _eligible(p, i) {
      if best < 0 {
        best = i;
      } else {
        if p.policy == POOL_POLICY_PRIORITY {
          let cp: Int = p.job_priorities[i];
          let bp: Int = p.job_priorities[best];
          if cp > bp {
            best = i;
          } else {
            if cp == bp {
              let co: Int = p.job_orders[i];
              let bo: Int = p.job_orders[best];
              if co < bo { best = i; }
            }
          }
        }
      }
    }
    i = i + 1;
  }
  return best;
}

// Index of the lowest-idle worker, or -1 when every worker is busy.
fn _first_idle_worker(p: &WorkerPool) -> Int {
  var w = 0;
  while w < p.size {
    let st: Int = p.worker_states[w];
    if st == WORKER_IDLE { return w; }
    w = w + 1;
  }
  return POOL_NO_WORKER;
}

// Clear a worker slot back to IDLE.
fn _set_worker_idle(p: &mut WorkerPool, w: Int) {
  p.worker_states[w] = WORKER_IDLE;
  p.worker_jobs[w] = POOL_NO_JOB;
  p.worker_lease_until[w] = 0;
}

// Release the worker currently holding job slot `slot` (no-op when none).
fn _release_worker_of_job(p: &mut WorkerPool, slot: Int) {
  let w: Int = p.job_worker[slot];
  if w >= 0 {
    _set_worker_idle(p, w);
  }
}

// Backoff delay for the given number of failed attempts: BASE * FACTOR^
// (attempt-1), capped at CAP; attempt < 1 yields BASE. Public API below
// (pool_backoff_delay); used by the retry path.
fn _backoff_delay_for(attempt: Int) -> Int {
  if attempt < 1 { return POOL_BACKOFF_BASE; }
  var d = POOL_BACKOFF_BASE;
  var k = 1;
  while k < attempt {
    if d >= POOL_BACKOFF_CAP { return POOL_BACKOFF_CAP; }
    d = d * POOL_BACKOFF_FACTOR;
    k = k + 1;
  }
  if d > POOL_BACKOFF_CAP { return POOL_BACKOFF_CAP; }
  return d;
}

// Resolve one failed attempt of the LEASED job at `slot`: schedule a retry
// (RETRY_WAIT until now + backoff) while attempts remain, else fail the job
// terminally. The caller must have released the worker first. Every call
// counts one attempt failure.
fn _resolve_attempt_failure(p: &mut WorkerPool, slot: Int) {
  let attempts: Int = p.job_attempts[slot];
  let maxa: Int = p.job_max_attempts[slot];
  p.job_worker[slot] = POOL_NO_WORKER;
  p.attempt_failures = p.attempt_failures + 1;
  if attempts >= maxa {
    p.job_states[slot] = JOB_FAILED;
    p.failures = p.failures + 1;
    return;
  }
  let delay = _backoff_delay_for(attempts);
  p.job_states[slot] = JOB_RETRY_WAIT;
  p.job_ready_tick[slot] = p.now + delay;
  p.retries = p.retries + 1;
  p.backoff_ticks = p.backoff_ticks + delay;
}

// Start one attempt: lease job slot `slot` on worker `w`. Every parallel
// vector is updated in this one place, so worker and job tables cannot skew.
// Used by pool_dispatch and pool_assign.
fn _record_attempt(p: &mut WorkerPool, slot: Int, w: Int) {
  let id: Int = p.job_ids[slot];
  let a: Int = p.job_attempts[slot];
  let l: Int = p.worker_leases[w];
  p.job_states[slot] = JOB_LEASED;
  p.job_attempts[slot] = a + 1;
  p.job_worker[slot] = w;
  p.worker_states[w] = WORKER_BUSY;
  p.worker_jobs[w] = id;
  p.worker_lease_until[w] = p.now + p.lease_ticks;
  p.worker_leases[w] = l + 1;
  p.dispatches = p.dispatches + 1;
}

// Fairness/starvation accounting for the dispatch that is about to lease
// job slot `selected`. Runs only from pool_dispatch (algorithms), never from
// pool_assign (an explicit driver decision). Every other eligible job is
// skipped; the selected job is "fair" when its queued time is at least the
// maximum eligible queued time.
fn _account_selection(p: &mut WorkerPool, selected: Int) {
  let sel_q: Int = p.job_queued_ticks[selected];
  var max_q = 0;
  var i = 0;
  while i < p.job_ids.len() {
    if _eligible(p, i) {
      let q: Int = p.job_queued_ticks[i];
      if q > max_q { max_q = q; }
      if i != selected {
        let sk: Int = p.job_skips[i];
        p.job_skips[i] = sk + 1;
        p.starvation_skips = p.starvation_skips + 1;
        if sk + 1 == POOL_STARVATION_THRESHOLD {
          p.starvation_events = p.starvation_events + 1;
        }
      }
    }
    i = i + 1;
  }
  if sel_q >= max_q {
    p.fair_dispatches = p.fair_dispatches + 1;
  } else {
    p.unfair_dispatches = p.unfair_dispatches + 1;
  }
  if max_q > p.max_wait_ticks { p.max_wait_ticks = max_q; }
}

// Accrue tick-based accounting over a delta of `n` ticks, using the state at
// the start of the step: non-terminal jobs gain wait ticks (QUEUED jobs also
// gain queued ticks) and BUSY workers gain busy ticks, bounded by the
// remaining lease so a lease that expires mid-step is not over-counted.
fn _accrue_ticks(p: &mut WorkerPool, n: Int) {
  if n <= 0 { return; }
  var i = 0;
  while i < p.job_ids.len() {
    let st: Int = p.job_states[i];
    if st != JOB_DONE && st != JOB_FAILED {
      let wt: Int = p.job_wait_ticks[i];
      p.job_wait_ticks[i] = wt + n;
      if st == JOB_QUEUED {
        let qt: Int = p.job_queued_ticks[i];
        p.job_queued_ticks[i] = qt + n;
      }
    }
    i = i + 1;
  }
  var w = 0;
  while w < p.size {
    let st: Int = p.worker_states[w];
    if st == WORKER_BUSY {
      let until: Int = p.worker_lease_until[w];
      let left = until - p.now;
      if left > 0 {
        var add = n;
        if left < n { add = left; }
        let bt: Int = p.worker_busy_ticks[w];
        p.worker_busy_ticks[w] = bt + add;
      }
    }
    w = w + 1;
  }
}

// Expire every lease whose expiry tick has been reached: the worker becomes
// IDLE and the job runs the failure path (retry with backoff, or terminal
// failure at the attempt limit). Backoff anchors at the current tick.
fn _expire_leases(p: &mut WorkerPool) {
  var w = 0;
  while w < p.size {
    let st: Int = p.worker_states[w];
    if st == WORKER_BUSY {
      let until: Int = p.worker_lease_until[w];
      if until <= p.now {
        let jid: Int = p.worker_jobs[w];
        _set_worker_idle(p, w);
        let slot = _job_index(p, jid);
        if slot >= 0 {
          let jst: Int = p.job_states[slot];
          if jst == JOB_LEASED {
            p.leases_expired = p.leases_expired + 1;
            _resolve_attempt_failure(p, slot);
          }
        }
      }
    }
    w = w + 1;
  }
}

// Promote every RETRY_WAIT job whose backoff has elapsed to QUEUED.
fn _promote_retries(p: &mut WorkerPool) {
  var i = 0;
  while i < p.job_ids.len() {
    let st: Int = p.job_states[i];
    if st == JOB_RETRY_WAIT {
      let ready: Int = p.job_ready_tick[i];
      if ready <= p.now {
        p.job_states[i] = JOB_QUEUED;
      }
    }
    i = i + 1;
  }
}

// ---------------------------------------------------------------------------
// Construction and policy
// ---------------------------------------------------------------------------

/// Create a pool with `size` idle workers, the given selection policy and the
/// default lease duration `lease_ticks`.
/// Params: size - worker count, >= 1; policy - POOL_POLICY_FIFO or
///         POOL_POLICY_PRIORITY; lease_ticks - default lease duration, >= 1.
/// Returns: Ok(WorkerPool); Err("pool: size must be >= 1"), Err("pool:
/// unknown policy") or Err("pool: lease_ticks must be >= 1").
/// Complexity: O(size).
pub fn pool_new(size: Int, policy: Int, lease_ticks: Int) -> Result[WorkerPool, Str] {
  if size < 1 {
    return _err_pool("pool: size must be >= 1");
  }
  if !_is_valid_policy(policy) {
    return _err_pool("pool: unknown policy");
  }
  if lease_ticks < 1 {
    return _err_pool("pool: lease_ticks must be >= 1");
  }
  var states = Vec[Int].new();
  var jobs = Vec[Int].new();
  var untils = Vec[Int].new();
  var leases = Vec[Int].new();
  var busy = Vec[Int].new();
  var w = 0;
  while w < size {
    states.push(WORKER_IDLE);
    jobs.push(POOL_NO_JOB);
    untils.push(0);
    leases.push(0);
    busy.push(0);
    w = w + 1;
  }
  return _ok_pool(WorkerPool{
    policy: policy;
    size: size;
    lease_ticks: lease_ticks;
    now: 0;
    worker_states: states;
    worker_jobs: jobs;
    worker_lease_until: untils;
    worker_leases: leases;
    worker_busy_ticks: busy;
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
  });
}

/// Change the active selection policy.
/// Params: p - the pool; policy - POOL_POLICY_FIFO or POOL_POLICY_PRIORITY.
/// Returns: Ok(policy) on success; Err("pool: unknown policy") otherwise
/// (state unchanged).
/// Complexity: O(1).
pub fn pool_set_policy(p: &mut WorkerPool, policy: Int) -> Result[Int, Str] {
  if !_is_valid_policy(policy) {
    return _err_int("pool: unknown policy");
  }
  p.policy = policy;
  return _ok_int(policy);
}

/// Active selection policy code. Complexity: O(1).
pub fn pool_policy(p: &WorkerPool) -> Int {
  return p.policy;
}

/// Worker count (fixed at construction). Complexity: O(1).
pub fn pool_size(p: &WorkerPool) -> Int {
  return p.size;
}

/// Default lease duration in ticks. Complexity: O(1).
pub fn pool_lease_ticks(p: &WorkerPool) -> Int {
  return p.lease_ticks;
}

/// Current logical tick. Complexity: O(1).
pub fn pool_now(p: &WorkerPool) -> Int {
  return p.now;
}

// ---------------------------------------------------------------------------
// Submission and accessors
// ---------------------------------------------------------------------------

/// Submit a job. The job starts QUEUED and eligible at the current tick.
/// Params: p - the pool; id - caller-assigned job id, unique, >= 0;
///         priority - scheduling priority, >= 0 (larger = more urgent);
///         max_attempts - attempt limit, >= 1.
/// Returns: Ok(submission sequence) with the dense 0-based sequence;
/// Err("pool: job id must be >= 0"), Err("pool: priority must be >= 0"),
/// Err("pool: max_attempts must be >= 1") or Err("pool: duplicate job id")
/// -- in every Err case the state is unchanged. A successful submit
/// increments the submitted counter.
/// Complexity: O(job count) (duplicate scan).
pub fn pool_submit(p: &mut WorkerPool, id: Int, priority: Int, max_attempts: Int) -> Result[Int, Str] {
  if id < 0 {
    return _err_int("pool: job id must be >= 0");
  }
  if priority < 0 {
    return _err_int("pool: priority must be >= 0");
  }
  if max_attempts < 1 {
    return _err_int("pool: max_attempts must be >= 1");
  }
  if _job_index(p, id) >= 0 {
    return _err_int("pool: duplicate job id");
  }
  let order = p.submitted;
  let now = p.now;
  p.job_ids.push(id);
  p.job_priorities.push(priority);
  p.job_orders.push(order);
  p.job_states.push(JOB_QUEUED);
  p.job_attempts.push(0);
  p.job_max_attempts.push(max_attempts);
  p.job_ready_tick.push(now);
  p.job_submit_tick.push(now);
  p.job_worker.push(POOL_NO_WORKER);
  p.job_wait_ticks.push(0);
  p.job_queued_ticks.push(0);
  p.job_skips.push(0);
  p.submitted = order + 1;
  return _ok_int(order);
}

/// Number of submitted jobs (jobs are never removed). Complexity: O(1).
pub fn pool_job_count(p: &WorkerPool) -> Int {
  return p.job_ids.len();
}

/// True when a job with `id` exists. Complexity: O(job count).
pub fn pool_has_job(p: &WorkerPool, id: Int) -> Bool {
  return _job_index(p, id) >= 0;
}

/// State code of job `id` (a JOB_* value), or POOL_NOT_FOUND (-1).
/// Complexity: O(job count).
pub fn pool_job_state(p: &WorkerPool, id: Int) -> Int {
  let slot = _job_index(p, id);
  if slot < 0 { return POOL_NOT_FOUND; }
  let st: Int = p.job_states[slot];
  return st;
}

/// Priority of job `id`, or POOL_NOT_FOUND (-1). Complexity: O(job count).
pub fn pool_job_priority(p: &WorkerPool, id: Int) -> Int {
  let slot = _job_index(p, id);
  if slot < 0 { return POOL_NOT_FOUND; }
  let v: Int = p.job_priorities[slot];
  return v;
}

/// Submission sequence of job `id`, or POOL_NOT_FOUND (-1).
/// Complexity: O(job count).
pub fn pool_job_order(p: &WorkerPool, id: Int) -> Int {
  let slot = _job_index(p, id);
  if slot < 0 { return POOL_NOT_FOUND; }
  let v: Int = p.job_orders[slot];
  return v;
}

/// Attempts started so far for job `id`, or POOL_NOT_FOUND (-1).
/// Complexity: O(job count).
pub fn pool_job_attempts(p: &WorkerPool, id: Int) -> Int {
  let slot = _job_index(p, id);
  if slot < 0 { return POOL_NOT_FOUND; }
  let v: Int = p.job_attempts[slot];
  return v;
}

/// Attempt limit of job `id`, or POOL_NOT_FOUND (-1). Complexity: O(job
/// count).
pub fn pool_job_max_attempts(p: &WorkerPool, id: Int) -> Int {
  let slot = _job_index(p, id);
  if slot < 0 { return POOL_NOT_FOUND; }
  let v: Int = p.job_max_attempts[slot];
  return v;
}

/// Earliest tick job `id` may be leased (submit tick, or submit/retry tick +
/// backoff), or POOL_NOT_FOUND (-1). Complexity: O(job count).
pub fn pool_job_ready_tick(p: &WorkerPool, id: Int) -> Int {
  let slot = _job_index(p, id);
  if slot < 0 { return POOL_NOT_FOUND; }
  let v: Int = p.job_ready_tick[slot];
  return v;
}

/// Tick job `id` was submitted, or POOL_NOT_FOUND (-1). Complexity: O(job
/// count).
pub fn pool_job_submit_tick(p: &WorkerPool, id: Int) -> Int {
  let slot = _job_index(p, id);
  if slot < 0 { return POOL_NOT_FOUND; }
  let v: Int = p.job_submit_tick[slot];
  return v;
}

/// Worker slot currently leasing job `id`, or POOL_NO_WORKER (-1) when the
/// job holds no lease -- also for an unknown id. Complexity: O(job count).
pub fn pool_job_worker(p: &WorkerPool, id: Int) -> Int {
  let slot = _job_index(p, id);
  if slot < 0 { return POOL_NO_WORKER; }
  let v: Int = p.job_worker[slot];
  return v;
}

/// Total ticks job `id` has spent non-terminal since submission (frozen once
/// terminal), or POOL_NOT_FOUND (-1). Complexity: O(job count).
pub fn pool_job_wait_ticks(p: &WorkerPool, id: Int) -> Int {
  let slot = _job_index(p, id);
  if slot < 0 { return POOL_NOT_FOUND; }
  let v: Int = p.job_wait_ticks[slot];
  return v;
}

/// Ticks job `id` has spent QUEUED (frozen once terminal), or
/// POOL_NOT_FOUND (-1). Complexity: O(job count).
pub fn pool_job_queued_ticks(p: &WorkerPool, id: Int) -> Int {
  let slot = _job_index(p, id);
  if slot < 0 { return POOL_NOT_FOUND; }
  let v: Int = p.job_queued_ticks[slot];
  return v;
}

/// Times dispatch passed over job `id` while it was eligible, or
/// POOL_NOT_FOUND (-1). Complexity: O(job count).
pub fn pool_job_skips(p: &WorkerPool, id: Int) -> Int {
  let slot = _job_index(p, id);
  if slot < 0 { return POOL_NOT_FOUND; }
  let v: Int = p.job_skips[slot];
  return v;
}

// ---------------------------------------------------------------------------
// Queue inspection
// ---------------------------------------------------------------------------

/// Number of jobs currently QUEUED. Complexity: O(job count).
pub fn pool_queued_count(p: &WorkerPool) -> Int {
  return _count_jobs(p, JOB_QUEUED);
}

/// Number of jobs QUEUED and ready at the current tick. Complexity: O(job
/// count).
pub fn pool_eligible_count(p: &WorkerPool) -> Int {
  var n = 0;
  var i = 0;
  while i < p.job_ids.len() {
    if _eligible(p, i) { n = n + 1; }
    i = i + 1;
  }
  return n;
}

/// Copy of the QUEUED job ids in submission order. Complexity: O(job count).
pub fn pool_queued_ids(p: &WorkerPool) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 0;
  while i < p.job_ids.len() {
    let st: Int = p.job_states[i];
    if st == JOB_QUEUED {
      let id: Int = p.job_ids[i];
      out.push(id);
    }
    i = i + 1;
  }
  return out;
}

/// Job id the next pool_dispatch would lease, or POOL_NO_JOB (-1) when no
/// job is eligible. Read-only probe; does not mutate the pool.
/// Complexity: O(job count).
pub fn pool_pick_job(p: &WorkerPool) -> Int {
  let slot = _pick_job_slot(p);
  if slot < 0 { return POOL_NO_JOB; }
  let id: Int = p.job_ids[slot];
  return id;
}

/// Number of IDLE workers. Complexity: O(size).
pub fn pool_idle_workers(p: &WorkerPool) -> Int {
  return _count_workers(p, WORKER_IDLE);
}

/// Number of BUSY workers. Complexity: O(size).
pub fn pool_busy_workers(p: &WorkerPool) -> Int {
  return _count_workers(p, WORKER_BUSY);
}

// ---------------------------------------------------------------------------
// Leasing (dispatch and explicit assignment)
// ---------------------------------------------------------------------------

/// Lease the next eligible job to the lowest-idle worker.
/// Selection: pool_pick_job's rule under the active policy; the worker is the
/// lowest-index IDLE slot. The job becomes LEASED, its attempt count grows,
/// and the worker's lease expires at now + lease_ticks. Fairness/starvation
/// counters are updated here (see _account_selection).
/// Params: p - the pool.
/// Returns: Ok(job id); Err("pool: no eligible jobs") when nothing is ready,
/// Err("pool: no idle workers") when every worker is busy -- in every Err
/// case the state is unchanged. A successful dispatch increments the
/// dispatches counter.
/// Complexity: O((job count) * size).
pub fn pool_dispatch(p: &mut WorkerPool) -> Result[Int, Str] {
  let slot = _pick_job_slot(p);
  if slot < 0 {
    return _err_int("pool: no eligible jobs");
  }
  let w = _first_idle_worker(p);
  if w < 0 {
    return _err_int("pool: no idle workers");
  }
  _account_selection(p, slot);
  let id: Int = p.job_ids[slot];
  _record_attempt(p, slot, w);
  return _ok_int(id);
}

/// Lease a specific eligible job to a specific IDLE worker, bypassing the
/// selection policy. Fairness and starvation counters are untouched (an
/// explicit assignment is a driver decision, not an algorithm outcome); the
/// attempt, lease and dispatch counters still advance.
/// Params: p - the pool; job_id - the job; worker - worker slot index.
/// Returns: Ok(job id); Err("pool: unknown job id"), Err("pool: job already
/// leased"), Err("pool: job already complete"), Err("pool: job already
/// failed"), Err("pool: job is waiting for retry"), Err("pool: worker index
/// must be >= 0"), Err("pool: unknown worker index") or Err("pool: worker is
/// not idle") -- in every Err case the state is unchanged.
/// Complexity: O(job count).
pub fn pool_assign(p: &mut WorkerPool, job_id: Int, worker: Int) -> Result[Int, Str] {
  let slot = _job_index(p, job_id);
  if slot < 0 {
    return _err_int("pool: unknown job id");
  }
  let st: Int = p.job_states[slot];
  if st == JOB_LEASED {
    return _err_int("pool: job already leased");
  }
  if st == JOB_DONE {
    return _err_int("pool: job already complete");
  }
  if st == JOB_FAILED {
    return _err_int("pool: job already failed");
  }
  if st == JOB_RETRY_WAIT {
    return _err_int("pool: job is waiting for retry");
  }
  if worker < 0 {
    return _err_int("pool: worker index must be >= 0");
  }
  if worker >= p.size {
    return _err_int("pool: unknown worker index");
  }
  let wst: Int = p.worker_states[worker];
  if wst != WORKER_IDLE {
    return _err_int("pool: worker is not idle");
  }
  _record_attempt(p, slot, worker);
  return _ok_int(job_id);
}

// ---------------------------------------------------------------------------
// Completion and failure
// ---------------------------------------------------------------------------

/// Complete the LEASED job `job_id` successfully: the job becomes DONE and
/// its worker returns to IDLE. The current attempt is the successful one.
/// Params: p - the pool; job_id - the job.
/// Returns: Ok(completions count); Err("pool: unknown job id"), Err("pool:
/// job already complete"), Err("pool: job already failed") or Err("pool: job
/// is not leased") -- in every Err case the state is unchanged.
/// Complexity: O(job count).
pub fn pool_complete(p: &mut WorkerPool, job_id: Int) -> Result[Int, Str] {
  let slot = _job_index(p, job_id);
  if slot < 0 {
    return _err_int("pool: unknown job id");
  }
  let st: Int = p.job_states[slot];
  if st == JOB_DONE {
    return _err_int("pool: job already complete");
  }
  if st == JOB_FAILED {
    return _err_int("pool: job already failed");
  }
  if st != JOB_LEASED {
    return _err_int("pool: job is not leased");
  }
  _release_worker_of_job(p, slot);
  p.job_states[slot] = JOB_DONE;
  p.job_worker[slot] = POOL_NO_WORKER;
  p.completions = p.completions + 1;
  return _ok_int(p.completions);
}

/// Fail the current attempt of the LEASED job `job_id`: the worker returns to
/// IDLE and the job either enters RETRY_WAIT with ready tick now + backoff
/// (attempts remain) or reaches FAILED (attempt limit reached). Either way
/// one attempt failure is recorded.
/// Params: p - the pool; job_id - the job.
/// Returns: Ok(attempts made) with the attempt count including this one;
/// Err("pool: unknown job id"), Err("pool: job already complete"), Err("pool:
/// job already failed") or Err("pool: job is not leased") -- in every Err
/// case the state is unchanged.
/// Complexity: O(job count).
pub fn pool_fail(p: &mut WorkerPool, job_id: Int) -> Result[Int, Str] {
  let slot = _job_index(p, job_id);
  if slot < 0 {
    return _err_int("pool: unknown job id");
  }
  let st: Int = p.job_states[slot];
  if st == JOB_DONE {
    return _err_int("pool: job already complete");
  }
  if st == JOB_FAILED {
    return _err_int("pool: job already failed");
  }
  if st != JOB_LEASED {
    return _err_int("pool: job is not leased");
  }
  _release_worker_of_job(p, slot);
  let attempts: Int = p.job_attempts[slot];
  _resolve_attempt_failure(p, slot);
  return _ok_int(attempts);
}

// ---------------------------------------------------------------------------
// Clock
// ---------------------------------------------------------------------------

/// Advance the logical clock by `ticks` steps. In order:
/// 1. accrue tick accounting over the delta from the state at the start of
///    the step (non-terminal jobs gain wait ticks, QUEUED jobs also queued
///    ticks, BUSY workers gain busy ticks bounded by the remaining lease);
/// 2. now += ticks;
/// 3. expire leases whose expiry tick has been reached (each expiry runs the
///    failure path: retry with backoff anchored at the new now, or terminal
///    failure);
/// 4. promote RETRY_WAIT jobs whose ready tick has been reached to QUEUED.
/// Because a retry scheduled in step 3 is ready strictly later than now, a
/// single call never both expires a lease and immediately re-queues it.
/// Params: p - the pool; ticks - number of steps, >= 0.
/// Returns: Ok(new now); Err("pool: ticks must be >= 0") (state unchanged).
/// Complexity: O((job count + size) * ticks-accounting).
pub fn pool_tick(p: &mut WorkerPool, ticks: Int) -> Result[Int, Str] {
  if ticks < 0 {
    return _err_int("pool: ticks must be >= 0");
  }
  _accrue_ticks(p, ticks);
  p.now = p.now + ticks;
  _expire_leases(p);
  _promote_retries(p);
  return _ok_int(p.now);
}

/// Backoff delay for `attempt` failed attempts: BASE * FACTOR^(attempt-1),
/// capped at CAP; attempt < 1 yields BASE. attempt=1 -> 1, 2 -> 2, 3 -> 4,
/// ..., >= 7 -> 64 with the default constants. Complexity: O(attempt).
pub fn pool_backoff_delay(attempt: Int) -> Int {
  return _backoff_delay_for(attempt);
}

// ---------------------------------------------------------------------------
// Worker accessors
// ---------------------------------------------------------------------------

/// State code of worker `w` (a WORKER_* value), or POOL_NOT_FOUND (-1).
/// Complexity: O(1).
pub fn pool_worker_state(p: &WorkerPool, w: Int) -> Int {
  if w < 0 { return POOL_NOT_FOUND; }
  if w >= p.size { return POOL_NOT_FOUND; }
  let st: Int = p.worker_states[w];
  return st;
}

/// Job id leased by worker `w`, or POOL_NO_JOB (-1) while IDLE -- also
/// POOL_NOT_FOUND (-1) for an unknown worker. Complexity: O(1).
pub fn pool_worker_job(p: &WorkerPool, w: Int) -> Int {
  if w < 0 { return POOL_NOT_FOUND; }
  if w >= p.size { return POOL_NOT_FOUND; }
  let j: Int = p.worker_jobs[w];
  return j;
}

/// Lease expiry tick of worker `w` (0 while IDLE), or POOL_NOT_FOUND (-1).
/// Complexity: O(1).
pub fn pool_worker_lease_until(p: &WorkerPool, w: Int) -> Int {
  if w < 0 { return POOL_NOT_FOUND; }
  if w >= p.size { return POOL_NOT_FOUND; }
  let v: Int = p.worker_lease_until[w];
  return v;
}

/// Ticks until the lease of worker `w` expires (0 while IDLE), or
/// POOL_NOT_FOUND (-1). Complexity: O(1).
pub fn pool_lease_remaining(p: &WorkerPool, w: Int) -> Int {
  if w < 0 { return POOL_NOT_FOUND; }
  if w >= p.size { return POOL_NOT_FOUND; }
  let st: Int = p.worker_states[w];
  if st != WORKER_BUSY { return 0; }
  let until: Int = p.worker_lease_until[w];
  return until - p.now;
}

/// Total leases taken by worker `w`, or POOL_NOT_FOUND (-1).
/// Complexity: O(1).
pub fn pool_worker_leases(p: &WorkerPool, w: Int) -> Int {
  if w < 0 { return POOL_NOT_FOUND; }
  if w >= p.size { return POOL_NOT_FOUND; }
  let v: Int = p.worker_leases[w];
  return v;
}

/// Ticks worker `w` has spent BUSY, or POOL_NOT_FOUND (-1).
/// Complexity: O(1).
pub fn pool_worker_busy_ticks(p: &WorkerPool, w: Int) -> Int {
  if w < 0 { return POOL_NOT_FOUND; }
  if w >= p.size { return POOL_NOT_FOUND; }
  let v: Int = p.worker_busy_ticks[w];
  return v;
}

// ---------------------------------------------------------------------------
// Counter accessors
// ---------------------------------------------------------------------------

/// Successful pool_submit calls. Complexity: O(1).
pub fn pool_submitted(p: &WorkerPool) -> Int { return p.submitted; }

/// Successful attempts started (pool_dispatch + pool_assign).
/// Complexity: O(1).
pub fn pool_dispatches(p: &WorkerPool) -> Int { return p.dispatches; }

/// Successful pool_complete calls. Complexity: O(1).
pub fn pool_completions(p: &WorkerPool) -> Int { return p.completions; }

/// Jobs that reached FAILED. Complexity: O(1).
pub fn pool_failures(p: &WorkerPool) -> Int { return p.failures; }

/// Failed attempts across all jobs (retried and terminal alike).
/// Complexity: O(1).
pub fn pool_attempt_failures(p: &WorkerPool) -> Int { return p.attempt_failures; }

/// Retries scheduled (pool_fail or lease expiry with attempts remaining).
/// Complexity: O(1).
pub fn pool_retries(p: &WorkerPool) -> Int { return p.retries; }

/// Total backoff delay scheduled, in ticks. Complexity: O(1).
pub fn pool_backoff_ticks(p: &WorkerPool) -> Int { return p.backoff_ticks; }

/// Leases that expired without a completion. Complexity: O(1).
pub fn pool_leases_expired(p: &WorkerPool) -> Int { return p.leases_expired; }

/// Dispatch pass-overs summed over all jobs. Complexity: O(1).
pub fn pool_starvation_skips(p: &WorkerPool) -> Int { return p.starvation_skips; }

/// Starvation events: jobs crossing POOL_STARVATION_THRESHOLD skips.
/// Complexity: O(1).
pub fn pool_starvation_events(p: &WorkerPool) -> Int { return p.starvation_events; }

/// Dispatches that leased a job with maximum eligible queued time.
/// Complexity: O(1).
pub fn pool_fair_dispatches(p: &WorkerPool) -> Int { return p.fair_dispatches; }

/// Dispatches that leased a job while some eligible job had waited longer.
/// Complexity: O(1).
pub fn pool_unfair_dispatches(p: &WorkerPool) -> Int { return p.unfair_dispatches; }

/// High-water mark of eligible queued time observed at dispatch.
/// Complexity: O(1).
pub fn pool_max_wait_ticks(p: &WorkerPool) -> Int { return p.max_wait_ticks; }

// ---------------------------------------------------------------------------
// Statistics snapshots
// ---------------------------------------------------------------------------

/// Statistics snapshot of the pool (a value copy; later mutations do not
/// affect it). Complexity: O(job count + size).
pub fn pool_stats(p: &WorkerPool) -> PoolStats {
  let idle = _count_workers(p, WORKER_IDLE);
  let busy = _count_workers(p, WORKER_BUSY);
  let queued = _count_jobs(p, JOB_QUEUED);
  let leased = _count_jobs(p, JOB_LEASED);
  let retry = _count_jobs(p, JOB_RETRY_WAIT);
  let done = _count_jobs(p, JOB_DONE);
  let bad = _count_jobs(p, JOB_FAILED);
  let jobs = p.job_ids.len();
  return PoolStats{
    size: p.size;
    idle: idle;
    busy: busy;
    queued: queued;
    leased: leased;
    retry_waiting: retry;
    done: done;
    failed: bad;
    jobs: jobs;
    submitted: p.submitted;
    dispatches: p.dispatches;
    completions: p.completions;
    failures: p.failures;
    attempt_failures: p.attempt_failures;
    retries: p.retries;
    backoff_ticks: p.backoff_ticks;
    leases_expired: p.leases_expired;
    starvation_skips: p.starvation_skips;
    starvation_events: p.starvation_events;
    fair_dispatches: p.fair_dispatches;
    unfair_dispatches: p.unfair_dispatches;
    max_wait_ticks: p.max_wait_ticks;
    now: p.now;
  };
}

/// One-line rendering of the statistics snapshot:
/// "size=.. idle=.. busy=.. queued=.. leased=.. retry=.. done=.. failed=..
/// submitted=.. dispatches=.. completions=.. failures=.. attempt_failures=..
/// retries=.. backoff_ticks=.. leases_expired=.. starvation_skips=..
/// starvation_events=.. fair=.. unfair=.. max_wait_ticks=.. now=..".
/// Complexity: O(job count + size).
pub fn pool_stats_text(p: &WorkerPool) -> Str {
  let s = pool_stats(p);
  var out = "size=" + convert.int_to_string(s.size);
  out = out + " idle=" + convert.int_to_string(s.idle);
  out = out + " busy=" + convert.int_to_string(s.busy);
  out = out + " queued=" + convert.int_to_string(s.queued);
  out = out + " leased=" + convert.int_to_string(s.leased);
  out = out + " retry=" + convert.int_to_string(s.retry_waiting);
  out = out + " done=" + convert.int_to_string(s.done);
  out = out + " failed=" + convert.int_to_string(s.failed);
  out = out + " submitted=" + convert.int_to_string(s.submitted);
  out = out + " dispatches=" + convert.int_to_string(s.dispatches);
  out = out + " completions=" + convert.int_to_string(s.completions);
  out = out + " failures=" + convert.int_to_string(s.failures);
  out = out + " attempt_failures=" + convert.int_to_string(s.attempt_failures);
  out = out + " retries=" + convert.int_to_string(s.retries);
  out = out + " backoff_ticks=" + convert.int_to_string(s.backoff_ticks);
  out = out + " leases_expired=" + convert.int_to_string(s.leases_expired);
  out = out + " starvation_skips=" + convert.int_to_string(s.starvation_skips);
  out = out + " starvation_events=" + convert.int_to_string(s.starvation_events);
  out = out + " fair=" + convert.int_to_string(s.fair_dispatches);
  out = out + " unfair=" + convert.int_to_string(s.unfair_dispatches);
  out = out + " max_wait_ticks=" + convert.int_to_string(s.max_wait_ticks);
  out = out + " now=" + convert.int_to_string(s.now);
  return out;
}

// ---------------------------------------------------------------------------
// Names and invariant check
// ---------------------------------------------------------------------------

/// Human-readable policy name: "fifo", "priority" or "unknown".
/// Complexity: O(1).
pub fn pool_policy_name(policy: Int) -> Str {
  if policy == POOL_POLICY_FIFO { return "fifo"; }
  if policy == POOL_POLICY_PRIORITY { return "priority"; }
  return "unknown";
}

/// Human-readable job state name, or "unknown" for an unknown code.
/// Complexity: O(1).
pub fn pool_job_state_name(state: Int) -> Str {
  if state == JOB_QUEUED { return "queued"; }
  if state == JOB_LEASED { return "leased"; }
  if state == JOB_RETRY_WAIT { return "retry_wait"; }
  if state == JOB_DONE { return "done"; }
  if state == JOB_FAILED { return "failed"; }
  return "unknown";
}

/// Human-readable worker state name, or "unknown" for an unknown code.
/// Complexity: O(1).
pub fn pool_worker_state_name(state: Int) -> Str {
  if state == WORKER_IDLE { return "idle"; }
  if state == WORKER_BUSY { return "busy"; }
  return "unknown";
}

/// Structural invariant of a pool, true exactly when:
/// 1. size >= 1, the policy and lease duration are valid, now >= 0, and the
///    five worker vectors have length size;
/// 2. every worker state is a WORKER_* code; an IDLE worker holds no job and
///    no expiry; a BUSY worker leases a job that is LEASED by exactly that
///    worker, and its expiry is strictly in the future; lease and busy
///    counters are non-negative and busy ticks <= now;
/// 3. the thirteen job vectors have equal length n and submitted == n; every
///    job id is >= 0 and unique; every priority >= 0; job_orders[i] == i;
///    every state is a JOB_* code; attempts/max_attempts/ready/submit/wait/
///    queued/skips are non-negative, max_attempts >= 1, attempts and
///    max_attempts are never exceeded (attempts <= max_attempts), queued
///    ticks <= wait ticks, wait ticks <= now - submit tick, and non-terminal
///    jobs have attempts < max_attempts;
/// 4. QUEUED jobs hold no worker and are ready now; LEASED jobs hold a busy
///    worker that points back at them; RETRY_WAIT jobs hold no worker, are
///    ready strictly later than now and have at least one failed attempt;
///    DONE jobs hold no worker and have >= 1 attempt; FAILED jobs hold no
///    worker and used exactly max_attempts attempts;
/// 5. queued + leased + retry + done + failed == n; completions == DONE
///    count; failures == FAILED count; attempt_failures == attempts - DONE
///    count (the one successful attempt per DONE job); dispatches == sum of
///    job attempts == sum of worker leases; leases_expired <= attempt
///    failures; starvation_skips == sum of job skips; fair + unfair <=
///    dispatches (explicit assignments bypass both); max_wait_ticks >= 0.
/// Complexity: O(job count^2 + size).
pub fn pool_check_invariant(p: &WorkerPool) -> Bool {
  if p.size < 1 { return false; }
  if !_is_valid_policy(p.policy) { return false; }
  if p.lease_ticks < 1 { return false; }
  if p.now < 0 { return false; }
  if p.worker_states.len() != p.size { return false; }
  if p.worker_jobs.len() != p.size { return false; }
  if p.worker_lease_until.len() != p.size { return false; }
  if p.worker_leases.len() != p.size { return false; }
  if p.worker_busy_ticks.len() != p.size { return false; }
  var w = 0;
  while w < p.size {
    let st: Int = p.worker_states[w];
    if st != WORKER_IDLE && st != WORKER_BUSY { return false; }
    let jid: Int = p.worker_jobs[w];
    let until: Int = p.worker_lease_until[w];
    let leases: Int = p.worker_leases[w];
    let busy: Int = p.worker_busy_ticks[w];
    if leases < 0 { return false; }
    if busy < 0 { return false; }
    if busy > p.now { return false; }
    if st == WORKER_IDLE {
      if jid != POOL_NO_JOB { return false; }
      if until != 0 { return false; }
    }
    if st == WORKER_BUSY {
      if jid < 0 { return false; }
      let slot = _job_index(p, jid);
      if slot < 0 { return false; }
      let jst: Int = p.job_states[slot];
      if jst != JOB_LEASED { return false; }
      let jw: Int = p.job_worker[slot];
      if jw != w { return false; }
      if until <= p.now { return false; }
    }
    w = w + 1;
  }
  let n = p.job_ids.len();
  if p.job_priorities.len() != n { return false; }
  if p.job_orders.len() != n { return false; }
  if p.job_states.len() != n { return false; }
  if p.job_attempts.len() != n { return false; }
  if p.job_max_attempts.len() != n { return false; }
  if p.job_ready_tick.len() != n { return false; }
  if p.job_submit_tick.len() != n { return false; }
  if p.job_worker.len() != n { return false; }
  if p.job_wait_ticks.len() != n { return false; }
  if p.job_queued_ticks.len() != n { return false; }
  if p.job_skips.len() != n { return false; }
  if p.submitted != n { return false; }
  var i = 0;
  var done = 0;
  var bad = 0;
  var queued = 0;
  var leased = 0;
  var retry = 0;
  var attempts_sum = 0;
  var failed_attempts = 0;
  var skips_sum = 0;
  while i < n {
    let id: Int = p.job_ids[i];
    let pr: Int = p.job_priorities[i];
    let ord: Int = p.job_orders[i];
    let st: Int = p.job_states[i];
    let at: Int = p.job_attempts[i];
    let mx: Int = p.job_max_attempts[i];
    let ready: Int = p.job_ready_tick[i];
    let sub: Int = p.job_submit_tick[i];
    let jw: Int = p.job_worker[i];
    let wt: Int = p.job_wait_ticks[i];
    let qt: Int = p.job_queued_ticks[i];
    let sk: Int = p.job_skips[i];
    if id < 0 { return false; }
    if pr < 0 { return false; }
    if ord != i { return false; }
    if st < JOB_QUEUED { return false; }
    if st > JOB_FAILED { return false; }
    if at < 0 { return false; }
    if mx < 1 { return false; }
    if at > mx { return false; }
    if ready < 0 { return false; }
    if sub < 0 { return false; }
    if sub > p.now { return false; }
    if wt < 0 { return false; }
    if qt < 0 { return false; }
    if qt > wt { return false; }
    if wt > p.now - sub { return false; }
    if sk < 0 { return false; }
    if st != JOB_DONE && st != JOB_FAILED {
      if at >= mx { return false; }
    }
    if st == JOB_QUEUED {
      if jw != POOL_NO_JOB { return false; }
      if ready > p.now { return false; }
      queued = queued + 1;
    }
    if st == JOB_LEASED {
      if jw < 0 { return false; }
      if jw >= p.size { return false; }
      let wst: Int = p.worker_states[jw];
      if wst != WORKER_BUSY { return false; }
      let wid: Int = p.worker_jobs[jw];
      if wid != id { return false; }
      if at < 1 { return false; }
      leased = leased + 1;
    }
    if st == JOB_RETRY_WAIT {
      if jw != POOL_NO_JOB { return false; }
      if ready <= p.now { return false; }
      if at < 1 { return false; }
      retry = retry + 1;
    }
    if st == JOB_DONE {
      if jw != POOL_NO_JOB { return false; }
      if at < 1 { return false; }
      done = done + 1;
    }
    if st == JOB_FAILED {
      if jw != POOL_NO_JOB { return false; }
      if at != mx { return false; }
      bad = bad + 1;
    }
    var j = i + 1;
    while j < n {
      let other: Int = p.job_ids[j];
      if other == id { return false; }
      j = j + 1;
    }
    attempts_sum = attempts_sum + at;
    if st == JOB_DONE {
      failed_attempts = failed_attempts + at - 1;
    } else {
      if st == JOB_LEASED {
        failed_attempts = failed_attempts + at - 1;
      } else {
        failed_attempts = failed_attempts + at;
      }
    }
    skips_sum = skips_sum + sk;
    i = i + 1;
  }
  if queued + leased + retry + done + bad != n { return false; }
  if p.completions != done { return false; }
  if p.failures != bad { return false; }
  if p.attempt_failures != failed_attempts { return false; }
  if p.dispatches != attempts_sum { return false; }
  var lease_sum = 0;
  w = 0;
  while w < p.size {
    let l: Int = p.worker_leases[w];
    lease_sum = lease_sum + l;
    w = w + 1;
  }
  if lease_sum != p.dispatches { return false; }
  if p.leases_expired > p.attempt_failures { return false; }
  if p.starvation_skips != skips_sum { return false; }
  if p.fair_dispatches + p.unfair_dispatches > p.dispatches { return false; }
  if p.max_wait_ticks < 0 { return false; }
  return true;
}
