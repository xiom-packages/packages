# xiom.worker -- Specification

Status: `incubating` (implemented, harness-green, not published).
Module: `xiom.worker` (`src/worker.xi`). Manifest: `package.xi` (name
`xiom.worker`, version `0.1.0`). `xiom.std` is a manifest dependency; the
library module imports `xiom.convert` only.

## 1. Scope

A worker pool as a pure, deterministic state machine -- the scheduling core
a thread pool or job runner would drive:

- pool sizing: a fixed worker table of `size` slots, created by `pool_new`;
- a job queue with priorities: per-job priority and dense submission
  sequence, with FIFO and PRIORITY selection policies;
- worker leases: `pool_dispatch` auto-assigns the lowest idle worker,
  `pool_assign` leases an explicit worker, leases expire on the logical
  clock, and every lease/attempt/release updates the parallel vectors in
  one place;
- retry with backoff accounting: failed attempts either schedule a
  deterministic doubling backoff or fail the job at its attempt limit;
- starvation/fairness counters: pass-over counts per job and pool-wide,
  threshold events, fair/unfair dispatch counts and a wait high-water mark;
- pool statistics snapshots (`pool_stats`, `pool_stats_text`) and a
  structural invariant (`pool_check_invariant`).

No threads, no atomics, no locks, no clock, no I/O, no FFI, no global state.
The library owns semantics only; a backend owns concurrency and blocking,
and advances time exclusively through `pool_tick`.

## 2. Non-goals

- Actual threads, work stealing, preemption or parallel execution. The pool
  is a value; a backend drives it and performs the work.
- Real time. Ticks are abstract steps; nothing sleeps and no wall clock is
  read.
- Pool resizing, worker spawn/join, or job removal. The worker table is
  fixed at construction and the job table only grows.
- Automatic starvation correction (aging). Starvation is measured, never
  remedied.
- Jittered or configurable backoff shapes beyond the exported constants.
- Priority queuing of workers (there is no worker priority).

## 3. State

```xi
pub type WorkerPool = {
  policy: Int;                 // POOL_POLICY_* selection policy
  size: Int;                   // worker count, >= 1, fixed at construction
  lease_ticks: Int;            // default lease duration, >= 1
  now: Int;                    // logical tick clock, advanced by pool_tick
  worker_states: Vec[Int];     // WORKER_* codes, length == size
  worker_jobs: Vec[Int];       // leased job id or POOL_NO_JOB
  worker_lease_until: Vec[Int]; // lease expiry tick (0 while idle)
  worker_leases: Vec[Int];     // leases taken per worker
  worker_busy_ticks: Vec[Int]; // BUSY ticks per worker
  job_ids: Vec[Int];           // job ids, unique, >= 0
  job_priorities: Vec[Int];    // priorities, >= 0 (larger = more urgent)
  job_orders: Vec[Int];        // dense submission sequences (orders[i] == i)
  job_states: Vec[Int];        // JOB_* codes, parallel to job_ids
  job_attempts: Vec[Int];      // attempts started
  job_max_attempts: Vec[Int];  // attempt limit, >= 1
  job_ready_tick: Vec[Int];    // earliest tick the job may be leased
  job_submit_tick: Vec[Int];   // submission tick
  job_worker: Vec[Int];        // holding worker slot or POOL_NO_WORKER
  job_wait_ticks: Vec[Int];    // ticks non-terminal since submission
  job_queued_ticks: Vec[Int];  // ticks spent QUEUED
  job_skips: Vec[Int];         // dispatch pass-overs while eligible
  submitted: Int;              // successful pool_submit calls
  dispatches: Int;             // attempts started (dispatch + assign)
  completions: Int;            // successful pool_complete calls
  failures: Int;               // jobs that reached FAILED
  attempt_failures: Int;       // every failed attempt (retried + terminal)
  retries: Int;                // retries scheduled
  backoff_ticks: Int;          // total scheduled backoff, in ticks
  leases_expired: Int;         // leases that expired without completion
  starvation_skips: Int;       // dispatch pass-overs, all jobs
  starvation_events: Int;      // jobs crossing the skip threshold
  fair_dispatches: Int;        // dispatched the longest-waiting job
  unfair_dispatches: Int;      // dispatched while another job waited longer
  max_wait_ticks: Int;         // high-water mark of eligible queued time
}
```

Every field is an internal implementation detail; callers go through the
free functions. The parallel vectors are pushed and updated together by
every mutation, so they can never skew.

Job state codes: `JOB_QUEUED` (0), `JOB_LEASED` (1), `JOB_RETRY_WAIT` (2),
`JOB_DONE` (3), `JOB_FAILED` (4). Worker state codes: `WORKER_IDLE` (0),
`WORKER_BUSY` (1). Sentinels: `POOL_NO_JOB` (-1), `POOL_NO_WORKER` (-1),
`POOL_NOT_FOUND` (-1). Backoff constants: `POOL_BACKOFF_BASE` (1),
`POOL_BACKOFF_FACTOR` (2), `POOL_BACKOFF_CAP` (64). Fairness:
`POOL_STARVATION_THRESHOLD` (8).

### 3.1 Invariant

`pool_check_invariant(p)` is true exactly when:

1. `size >= 1`, the policy and `lease_ticks` are valid, `now >= 0`, and the
   five worker vectors have length `size`;
2. every worker state is a `WORKER_*` code; an `IDLE` worker holds no job
   (`-1`) and no expiry (`0`); a `BUSY` worker leases a job that is `LEASED`
   by exactly that worker, and its expiry is strictly in the future; lease
   and busy counters are non-negative and `busy ticks <= now`;
3. the thirteen job vectors have equal length `n`, `submitted == n`, every
   job id is `>= 0` and unique, every priority is `>= 0`,
   `job_orders[i] == i`, every state is a `JOB_*` code; attempts,
   max_attempts, ready/submit ticks, wait/queued ticks and skips are
   non-negative; `max_attempts >= 1`, `attempts <= max_attempts`, non-
   terminal jobs have `attempts < max_attempts`, `queued <= wait` and
   `wait <= now - submit`;
4. `QUEUED` jobs hold no worker and are ready now; `LEASED` jobs hold a busy
   worker that points back at them; `RETRY_WAIT` jobs hold no worker, are
   ready strictly later than `now` and have `attempts >= 1`; `DONE` jobs
   hold no worker and have `attempts >= 1`; `FAILED` jobs hold no worker
   and have `attempts == max_attempts`;
5. `queued + leased + retry + done + failed == n`;
   `completions == DONE count`; `failures == FAILED count`;
   `attempt_failures == sum(attempts) - DONE count` (each `DONE` job has
   exactly one successful attempt);
   `dispatches == sum(attempts) == sum(worker_leases)`;
   `leases_expired <= attempt_failures`;
   `starvation_skips == sum(job_skips)`;
   `fair_dispatches + unfair_dispatches <= dispatches` (explicit
   assignments bypass both); `max_wait_ticks >= 0`.

## 4. State machine rules

Notation: `p` is a pool; `id` is a job id; `w` is a worker slot.

### 4.1 S1 -- construction (`pool_new(size, policy, lease_ticks)`)

Validation order: `size < 1` -> `Err("pool: size must be >= 1")`; invalid
policy -> `Err("pool: unknown policy")`; `lease_ticks < 1` -> `Err("pool:
lease_ticks must be >= 1")`. Otherwise every worker starts `IDLE` with no
job and no expiry, the job table and counters are zero, `now == 0` and the
active policy is `policy`; `Ok(pool)`.

### 4.2 S2 -- policy change (`pool_set_policy(policy)`)

Valid policy: becomes active, `Ok(policy)`; otherwise `Err("pool: unknown
policy")` and the state is unchanged. The policy affects dispatch selection
only; it never preempts a lease.

### 4.3 S3 -- submission (`pool_submit(id, priority, max_attempts)`)

Validation order:

1. `id < 0` -> `Err("pool: job id must be >= 0")`;
2. `priority < 0` -> `Err("pool: priority must be >= 0")`;
3. `max_attempts < 1` -> `Err("pool: max_attempts must be >= 1")`;
4. `id` already known -> `Err("pool: duplicate job id")`;
5. otherwise the job is appended in state `QUEUED` with submission sequence
   `submitted` (dense: 0, 1, 2, ...), `job_ready_tick == job_submit_tick ==
   now`, attempts 0, no worker, zero accounting, `submitted += 1`;
   `Ok(submission sequence)`.

Every error leaves the state unchanged. A submitted job is immediately
eligible at the current tick.

### 4.4 S4 -- dispatch (`pool_dispatch`)

1. `_pick_job_slot` finds no eligible job -> `Err("pool: no eligible jobs")`
   (checked **first**, so an empty queue is reported even when workers are
   also busy);
2. no `IDLE` worker -> `Err("pool: no idle workers")`;
3. otherwise `_account_selection` runs (section 6), then the job is leased
   to the lowest-index idle worker: state `LEASED`, `attempts += 1`,
   `job_worker = w`, worker `BUSY`, `worker_jobs = id`,
   `worker_lease_until = now + lease_ticks`, `worker_leases[w] += 1`,
   `dispatches += 1`; `Ok(job id)`.

Both errors leave the state unchanged.

### 4.5 S5 -- explicit assignment (`pool_assign(job_id, worker)`)

Bypasses the selection policy, fairness accounting and starvation
accounting; it still starts an attempt (leases, attempt and dispatch
counters advance exactly as in S4 step 3).

Validation order:

1. unknown job -> `Err("pool: unknown job id")`;
2. job `LEASED` -> `Err("pool: job already leased")`;
3. job `DONE` -> `Err("pool: job already complete")`;
4. job `FAILED` -> `Err("pool: job already failed")`;
5. job `RETRY_WAIT` -> `Err("pool: job is waiting for retry")`;
6. `worker < 0` -> `Err("pool: worker index must be >= 0")`;
7. `worker >= size` -> `Err("pool: unknown worker index")`;
8. worker not `IDLE` -> `Err("pool: worker is not idle")`;
9. otherwise lease as in S4 step 3; `Ok(job id)`.

### 4.6 S6 -- completion (`pool_complete(job_id)`)

1. unknown job -> `Err("pool: unknown job id")`;
2. job `DONE` -> `Err("pool: job already complete")`;
3. job `FAILED` -> `Err("pool: job already failed")`;
4. job `QUEUED` or `RETRY_WAIT` -> `Err("pool: job is not leased")`;
5. otherwise the worker returns to `IDLE`, the job becomes `DONE` with
   `job_worker = -1`, `completions += 1`; `Ok(completions count)`.

### 4.7 S7 -- failed attempt (`pool_fail(job_id)`)

Same validation order as S6 (including the `DONE`/`FAILED` messages). On
success the worker is released and the attempt-failure resolution runs
(section 5.2). Returns `Ok(attempts made)`, the attempt count including
this one.

### 4.8 S8 -- clock (`pool_tick(ticks)`)

`ticks < 0` -> `Err("pool: ticks must be >= 0")` (state unchanged).
Otherwise, in order:

1. **accrual** over the delta, using the state at the start of the step:
   every non-terminal job gains `ticks` wait ticks; a `QUEUED` job also
   gains `ticks` queued ticks; a `BUSY` worker gains
   `min(ticks, max(0, lease_until - now))` busy ticks (bounded by the
   remaining lease, so a lease expiring mid-step is not over-counted);
2. `now += ticks`;
3. **lease expiry**: every `BUSY` worker with `lease_until <= now` is
   released and its job runs the attempt-failure resolution; the backoff of
   a retry scheduled here is anchored at the new `now`;
4. **retry promotion**: every `RETRY_WAIT` job with `ready_tick <= now`
   becomes `QUEUED`.

Because a retry scheduled in step 3 is ready strictly later than `now`, one
call never expires a lease and immediately re-queues it. `Ok(new now)`.

### 4.9 Derived state

`job_wait_ticks` is frozen when a job reaches `DONE` or `FAILED`;
`job_queued_ticks` is frozen at the same moment. Both are tick-granular:
state changes that happen inside a step apply on the next step's accrual.

## 5. Selection, retry and backoff

### 5.1 Selection policies

Eligible = state `QUEUED` and `ready_tick <= now`.

```
FIFO (POOL_POLICY_FIFO = 0):
    smallest submission sequence (scan left-to-right, first wins)

PRIORITY (POOL_POLICY_PRIORITY = 1):
    largest priority; on equal priority, smallest submission sequence
    (scan left-to-right, strict improvement only)
```

Properties:

- **Total and deterministic.** Submission sequences are unique, so the
  comparison never ties at the end; a residual tie (impossible in a valid
  state) falls to the earliest queue position.
- **Stable by submission order.** On equal priority the earlier-submitted
  job wins, regardless of its id.
- **Not preemptive.** Only eligible jobs are ranked; leases are unaffected.

### 5.2 Attempt-failure resolution (`pool_fail` or lease expiry)

Precondition: the job is `LEASED`; the worker has been released. Then
`attempt_failures += 1` and:

- `attempts >= max_attempts`: job becomes `FAILED`, `failures += 1`;
- otherwise: `delay = pool_backoff_delay(attempts)`, job becomes
  `RETRY_WAIT` with `ready_tick = now + delay`, `retries += 1` and
  `backoff_ticks += delay`.

### 5.3 Backoff

`pool_backoff_delay(attempt)`:

```
attempt < 1          -> POOL_BACKOFF_BASE (1)
attempt >= 1         -> min(BASE * FACTOR^(attempt-1), CAP)
                        = min(2^(attempt-1), 64) with the default constants
```

Sequence: 1, 2, 4, 8, 16, 32, 64, 64, ... There is no jitter: the model is
deterministic by construction.

## 6. Fairness and starvation accounting

`_account_selection` runs inside every successful `pool_dispatch` (and only
there; `pool_assign` never calls it). Let `E` be the eligible set at that
moment, `sel` the selected job, and `max_q = max(job_queued_ticks[j])` over
`E`:

- `fair_dispatches += 1` when `queued_ticks[sel] >= max_q`, else
  `unfair_dispatches += 1` (the selected job is / is not among the
  longest-waiting jobs);
- for every `j` in `E` with `j != sel`: `job_skips[j] += 1` and
  `starvation_skips += 1`; when a single job's skip count reaches exactly
  `POOL_STARVATION_THRESHOLD` (8), `starvation_events += 1` (each job can
  contribute at most one event, at the crossing);
- `max_wait_ticks = max(max_wait_ticks, max_q)`.

## 7. Error catalog

All error strings are stable and prefixed `pool: `.

| Function | Condition | Err message | State on error |
|---|---|---|---|
| `pool_new` | `size < 1` | `pool: size must be >= 1` | no value |
| `pool_new` | policy not 0/1 | `pool: unknown policy` | no value |
| `pool_new` | `lease_ticks < 1` | `pool: lease_ticks must be >= 1` | no value |
| `pool_set_policy` | policy not 0/1 | `pool: unknown policy` | unchanged |
| `pool_submit` | `id < 0` | `pool: job id must be >= 0` | unchanged |
| `pool_submit` | `priority < 0` | `pool: priority must be >= 0` | unchanged |
| `pool_submit` | `max_attempts < 1` | `pool: max_attempts must be >= 1` | unchanged |
| `pool_submit` | id already known | `pool: duplicate job id` | unchanged |
| `pool_dispatch` | no eligible job | `pool: no eligible jobs` | unchanged |
| `pool_dispatch` | no idle worker | `pool: no idle workers` | unchanged |
| `pool_assign` | unknown job | `pool: unknown job id` | unchanged |
| `pool_assign` | job `LEASED` | `pool: job already leased` | unchanged |
| `pool_assign` | job `DONE` | `pool: job already complete` | unchanged |
| `pool_assign` | job `FAILED` | `pool: job already failed` | unchanged |
| `pool_assign` | job `RETRY_WAIT` | `pool: job is waiting for retry` | unchanged |
| `pool_assign` | `worker < 0` | `pool: worker index must be >= 0` | unchanged |
| `pool_assign` | `worker >= size` | `pool: unknown worker index` | unchanged |
| `pool_assign` | worker not `IDLE` | `pool: worker is not idle` | unchanged |
| `pool_complete` / `pool_fail` | unknown job | `pool: unknown job id` | unchanged |
| `pool_complete` / `pool_fail` | job `DONE` | `pool: job already complete` | unchanged |
| `pool_complete` / `pool_fail` | job `FAILED` | `pool: job already failed` | unchanged |
| `pool_complete` / `pool_fail` | job `QUEUED`/`RETRY_WAIT` | `pool: job is not leased` | unchanged |
| `pool_tick` | `ticks < 0` | `pool: ticks must be >= 0` | unchanged |

No panicking input exists: every function is total, and read accessors return
`-1`/`false`/`0` sentinels instead of erroring.

## 8. Complexity

| Operation | Complexity |
|---|---|
| `pool_new` | O(size) |
| `pool_set_policy` / `pool_policy` / `pool_size` / `pool_lease_ticks` / `pool_now` | O(1) |
| `pool_submit` | O(job count) -- duplicate scan |
| job accessors, `pool_has_job` | O(job count) |
| `pool_queued_ids` / `pool_queued_count` / `pool_eligible_count` / `pool_pick_job` | O(job count) |
| `pool_dispatch` | O(job count + size) |
| `pool_assign` | O(job count) |
| `pool_complete` / `pool_fail` | O(job count) |
| `pool_tick` | O(job count + size), plus O(expiries x job count) for expiry lookups |
| worker accessors | O(1) |
| counters | O(1) |
| `pool_stats` / `pool_stats_text` | O(job count + size) |
| `pool_check_invariant` | O(job count^2 + size) |

## 9. Test plan

`tests/test_conformance.xi` (`module worker_tests`, 26 named checks, a
hello-style `main` that prints `[PASS]`/`[FAIL]` per check, a summary line,
and returns the failure count). Fixtures are built in-test through
`pool_new`; every string comparison routes through `compare.str_compare`.

1. `pool_new` initializes sized workers, empty jobs and zero stats;
2. `pool_new`/`pool_set_policy` validate size, policy and lease_ticks;
3. `pool_submit` validates inputs, assigns dense orders, starts `QUEUED`;
4. FIFO ignores priority, keeps submission order, copies the queue;
5. PRIORITY picks largest priority, ties stable by submission order;
6. `pool_dispatch` leases the lowest idle worker and marks it `LEASED`;
7. `pool_dispatch` distinguishes "no eligible jobs" from "no idle workers";
8. `pool_assign` validates the job lifecycle, worker index and idleness;
9. `pool_complete`/`pool_fail` validate `LEASED` and release the worker;
10. failure retries with doubling backoff until the attempt limit fails;
11. `pool_tick` accrues ticks, expires leases and promotes retries;
12. `max_attempts = 1` fails on the first failed attempt;
13. lease expiry at the attempt limit fails the job terminally;
14. starvation counters track skips, threshold events and unfair dispatches;
15. FIFO dispatch counts as fair and skips only pass-overs;
16. worker accessors expose lease state, remaining ticks and sentinels;
17. `pool_stats` returns an independent snapshot, `pool_stats_text` renders;
18. job and worker accessors return sentinels for unknown ids;
19. the structural invariant holds across 40 mixed cycles;
20. `pool_pick_job` is a pure read-only probe;
21. `pool_assign` bypasses policy, fairness and starvation accounting;
22. one large tick expires every due lease and anchors backoff at the new now;
23. `pool_backoff_delay` doubles from BASE and clamps at CAP;
24. policy, job-state and worker-state name helpers are stable;
25. counters accumulate across fails, retries, expiries and terminal failure;
26. identical operation sequences produce identical pool statistics.

Run from the repository root:

```
.\scripts\port.ps1 -Package xiom.worker
```

Last verified: compiler v0.62.1, `port: PASS (passed=26 failed=0
program_exit=0 exit=0)`.

## 10. Compiler / stdlib notes for v0.62.1

- Free functions only (no methods), with explicit `&`/`&mut` parameters and
  `&mut` at every call site.
- `Ok`/`Err` are constructed only inside the `_ok_*` / `_err_*` leaf helper
  functions.
- `Vec[Int]` element reads are bound with a typed `let` before use.
- Parallel `Vec[Int]` fields are pushed and updated in the same function
  (`pool_submit`, `_record_attempt`, `_set_worker_idle`), so they can never
  skew.
- Str equality in the tests goes through `str_compare`; the library itself
  never compares strings.
- No `Vec[StructType]`, no indexed `Vec[fn]` dispatch, no generic callbacks,
  no `Vec[Float64]`, no `mut` in match patterns, no FFI, no threads.
- No `log`-named function.
- The test wrapper for `pool_size` is named `worker_count_of`, not
  `size_of`: the latter is a compiler builtin (`xiom.core.size_of[T]`) and
  shadowing it silently called the builtin.
- Wrapper functions in the test suite take `&mut` for read-only access, so a
  `&local` read call is never followed by a `&mut local` call in the same
  function body (advisory E001).

## 11. Known limitations

- The model is single-threaded and non-atomic; a concurrent backend must
  provide the critical section around every transition.
- No preemption, work stealing, waiting/joining, timeouts, cancellation,
  pool resize or job removal.
- `pool_dispatch` reports "no eligible jobs" before "no idle workers" when
  both hold; callers that need worker occupancy can query
  `pool_idle_workers` first.
- Tick accounting is step-granular: state changes inside a step (expiries,
  promotions) apply on the next step's accrual, and busy ticks are bounded
  by the remaining lease but not by transitions within the step.
- `pool_assign` is policy-free and accounting-free by design, so
  `fair_dispatches + unfair_dispatches` can be smaller than `dispatches`.
- Starvation is measured, never corrected; `PRIORITY` can starve a
  low-priority job indefinitely by design.
- Selection and id lookup use linear scans; a backend with very long queues
  would use indexed structures instead.
