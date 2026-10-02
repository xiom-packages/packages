# xiom.worker

> **Status:** `incubating` -- conformance-tested (26/26); published at `v0.1.0` on the XIOM registry.
> **Scope:** a worker-pool scheduling model as a pure, deterministic state
> machine: fixed pool sizing, a prioritized job queue, worker leases and
> explicit assignment, retry with backoff accounting, starvation/fairness
> counters and statistics snapshots. There are no threads, no atomics, no
> locks, no clock and no I/O -- time is an explicit integer tick counter.
> **Deps:** `xiom.std` (manifest only); the library imports `xiom.convert`
> from it, the tests additionally use `xiom.test`, `xiom.io` and
> `xiom.string.compare`.

## What it is

`xiom.worker` models a worker pool as a plain value type and a set of free
functions. A `WorkerPool` holds:

- a fixed table of `size` workers, each `IDLE` or `BUSY`, with the job id it
  leases, the lease expiry tick and per-worker lease/busy-tick counters;
- thirteen parallel `Vec[Int]` job vectors -- ids, priorities, submission
  sequences, state codes (`QUEUED`, `LEASED`, `RETRY_WAIT`, `DONE`,
  `FAILED`), attempt counts and limits, ready/submit ticks, the holding
  worker, wait ticks, queued ticks and skip counts;
- pool counters for submissions, dispatches, completions, terminal failures,
  attempt failures, retries, scheduled backoff ticks, lease expiries and the
  starvation/fairness accounting.

Because there is no concurrency in the library, every operation is a total,
deterministic transition: given the same state and inputs, the same state and
outcome follow. A real backend (a thread pool, an event loop) owns atomicity
and blocking; this module owns the *scheduling semantics* in a form that can
be tested exactly, without sleeps or races.

Jobs move `QUEUED -> LEASED -> DONE | FAILED`, with `LEASED -> RETRY_WAIT`
when an attempt fails and `RETRY_WAIT -> QUEUED` when the backoff elapses
(processed by `pool_tick`). A lease itself expires when the logical clock
reaches its expiry tick, which routes the job through the same retry path as
an explicit failure. Workers move `IDLE <-> BUSY` as leases are taken and
released.

Two ready-queue selection policies are supported:

- `POOL_POLICY_FIFO` -- the smallest submission sequence among eligible jobs;
- `POOL_POLICY_PRIORITY` -- the largest priority, with ties broken by the
  smallest submission sequence.

`pool_assign` leases an explicit eligible job to an explicit idle worker,
bypassing the policy (and its fairness/starvation accounting).

## API

| Function | Returns | Description |
|---|---|---|
| `pool_new(size, policy, lease_ticks)` | `Result[WorkerPool, Str]` | Pool with `size` idle workers. |
| `pool_set_policy(&mut p, policy)` | `Result[Int, Str]` | Change the active policy; unknown codes refused. |
| `pool_policy(p)` / `pool_size(p)` / `pool_lease_ticks(p)` / `pool_now(p)` | `Int` | Pool configuration and clock. |
| `pool_submit(&mut p, id, priority, max_attempts)` | `Result[Int, Str]` | Submit a job (starts `QUEUED`); `Ok(submission order)`. |
| `pool_job_count(p)` / `pool_has_job(p, id)` | `Int` / `Bool` | Job table size and existence. |
| `pool_job_state(p, id)` | `Int` | `JOB_*` code, `-1` when unknown. |
| `pool_job_priority(p, id)` / `pool_job_order(p, id)` | `Int` | Priority / dense submission sequence, `-1` when unknown. |
| `pool_job_attempts(p, id)` / `pool_job_max_attempts(p, id)` | `Int` | Attempts started / attempt limit, `-1` when unknown. |
| `pool_job_ready_tick(p, id)` / `pool_job_submit_tick(p, id)` | `Int` | Earliest lease tick / submission tick, `-1` when unknown. |
| `pool_job_worker(p, id)` | `Int` | Holding worker slot, `-1` when none or unknown. |
| `pool_job_wait_ticks(p, id)` / `pool_job_queued_ticks(p, id)` | `Int` | Non-terminal wait ticks / `QUEUED` ticks. |
| `pool_job_skips(p, id)` | `Int` | Dispatch pass-overs while eligible. |
| `pool_queued_count(p)` / `pool_eligible_count(p)` | `Int` | Jobs `QUEUED` / ready now. |
| `pool_queued_ids(p)` | `Vec[Int]` | Copy of the `QUEUED` ids in submission order. |
| `pool_pick_job(p)` | `Int` | Job the next dispatch would lease, `-1` when none. |
| `pool_idle_workers(p)` / `pool_busy_workers(p)` | `Int` | Worker state counts. |
| `pool_dispatch(&mut p)` | `Result[Int, Str]` | Lease the policy-selected job to the lowest idle worker. |
| `pool_assign(&mut p, job_id, worker)` | `Result[Int, Str]` | Lease a specific eligible job to a specific idle worker. |
| `pool_complete(&mut p, job_id)` | `Result[Int, Str]` | `LEASED -> DONE`; releases the worker. |
| `pool_fail(&mut p, job_id)` | `Result[Int, Str]` | Failed attempt: retry with backoff, or terminal `FAILED` at the limit. |
| `pool_tick(&mut p, ticks)` | `Result[Int, Str]` | Advance the clock; accrues accounting, expires leases, promotes retries. |
| `pool_backoff_delay(attempt)` | `Int` | `min(BASE * FACTOR^(attempt-1), CAP)`; `BASE` for `attempt < 1`. |
| `pool_worker_state(p, w)` | `Int` | `WORKER_*` code, `-1` for an unknown slot. |
| `pool_worker_job(p, w)` | `Int` | Leased job id, `-1` while idle or unknown. |
| `pool_worker_lease_until(p, w)` | `Int` | Lease expiry tick (0 while idle), `-1` for unknown. |
| `pool_lease_remaining(p, w)` | `Int` | Ticks until expiry (0 while idle), `-1` for unknown. |
| `pool_worker_leases(p, w)` / `pool_worker_busy_ticks(p, w)` | `Int` | Per-worker lease / busy-tick counters. |
| `pool_submitted(p)` / `pool_dispatches(p)` | `Int` | Successful submissions / attempts started. |
| `pool_completions(p)` / `pool_failures(p)` | `Int` | Successful completions / terminal failures. |
| `pool_attempt_failures(p)` | `Int` | Failed attempts (retried and terminal). |
| `pool_retries(p)` / `pool_backoff_ticks(p)` | `Int` | Retries scheduled / total backoff ticks scheduled. |
| `pool_leases_expired(p)` | `Int` | Leases that expired without completion. |
| `pool_starvation_skips(p)` / `pool_starvation_events(p)` | `Int` | Pass-over total / threshold-crossing events. |
| `pool_fair_dispatches(p)` / `pool_unfair_dispatches(p)` | `Int` | Dispatches to the longest / not the longest waiting job. |
| `pool_max_wait_ticks(p)` | `Int` | High-water mark of eligible queued time at dispatch. |
| `pool_stats(p)` | `PoolStats` | Snapshot (value copy) of state counts and counters. |
| `pool_stats_text(p)` | `Str` | One-line rendering of the snapshot. |
| `pool_policy_name(policy)` / `pool_job_state_name(state)` / `pool_worker_state_name(state)` | `Str` | Stable names (`"fifo"`, `"queued"`, `"busy"`, ...). |
| `pool_check_invariant(p)` | `Bool` | Structural invariant check (see SPEC.md). |

Every struct field is an internal implementation detail; callers must go
through the free functions.

## Usage

```xi
use xiom.worker;

match pool_new(2, POOL_POLICY_PRIORITY, 8) {
  Ok(p) => {
    var pool = p;

    // Job 1 at priority 1 (3 attempts), job 2 at priority 5 (2 attempts).
    pool_submit(&mut pool, 1, 1, 3);
    pool_submit(&mut pool, 2, 5, 2);

    // PRIORITY leases job 2 first -- to the lowest idle worker.
    match pool_dispatch(&mut pool) {
      Ok(id) => {
        // The backend runs the job; then it reports the outcome.
        pool_complete(&mut pool, id);            // or pool_fail(...) to retry
      },
      Err(_) => { /* "pool: no eligible jobs" / "pool: no idle workers" */ },
    }

    // Advance 8 logical ticks: accounting accrues, expired leases retry
    // with backoff, due retries become QUEUED again.
    pool_tick(&mut pool, 8);
  },
  Err(_) => { /* "pool: unknown policy" */ },
}
```

Lease expiry and retry, step by step:

```xi
var pool = ...;                       // size 1, lease_ticks 2, FIFO
pool_submit(&mut pool, 7, 0, 3);      // job 7, 3 attempts
pool_dispatch(&mut pool);             // LEASED on worker 0, lease expires at 2
pool_fail(&mut pool, 7);              // attempt 1 failed -> RETRY_WAIT until 1
pool_tick(&mut pool, 1);              // backoff elapsed -> QUEUED
pool_dispatch(&mut pool);             // LEASED again
pool_tick(&mut pool, 2);              // lease expires: attempt 2 failed,
                                      // RETRY_WAIT until 3 + 2 = 5
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.worker
```

Expected: the namespaced module passes the section-4 namespace rule, 26
`[PASS]` lines, and a final `port: PASS (passed=26 failed=0 program_exit=0
exit=0)`.

## Install

Once published on the XIOM registry:

```
xiom pkg install xiom.worker@0.1.0     # consumer
xiom pkg publish                       # maintainer (needs XIOM_REGISTRY_TOKEN)
```

The package is not on the registry yet; until then, vendor
`packages/xiom-worker` and compile it from source.

## Limitations

- **Deterministic model, no real threads.** There is no concurrency,
  atomicity or memory ordering here; a backend that runs jobs on real threads
  must serialise access to the pool value itself.
- **No preemption or work stealing.** A leased job holds its worker until
  `pool_complete`, `pool_fail` or lease expiry.
- **Fixed pool size.** Workers are created by `pool_new`; there is no
  resize, spawn or shutdown operation (exit is simply "stop calling").
- **No job removal and no id reuse.** The job table only grows.
- **Tick granularity.** Accounting is per explicit `pool_tick` step, using
  the state at the start of the step; busy ticks are bounded by the
  remaining lease, but state changes inside a single large step are not
  prorated beyond that (a retry scheduled by a lease expiry is anchored at
  the tick that expired it).
- **Backoff is fixed-shape:** `min(1 * 2^(attempt-1), 64)` ticks with the
  default constants; there is no jitter (deliberately -- the model is
  deterministic).
- **`PRIORITY` is not aging or preemptive.** Starvation is *measured*
  (`pool_job_skips`, `pool_starvation_events`, `pool_max_wait_ticks`) but
  never automatically corrected.
- **`pool_assign` bypasses the policy and the fairness counters** -- it is
  an explicit driver decision, not an algorithm outcome.
- Complexity: id lookups are linear scans, so dispatch/assign are
  O(job count) and the invariant check is O(job count^2); fine for the
  model, not tuned for very long queues.
- Not thread-safe: values follow ordinary XIOM move/borrow rules.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
