# xiom.semaphore -- Specification

Status: `incubating` (implemented, harness-green, not published).
Module: `xiom.semaphore` (`src/semaphore.xi`). Manifest: `package.xi` (name
`xiom.semaphore`, version `0.1.0`). `xiom.std` is a manifest dependency; the
library module imports `xiom.string` and `xiom.convert` only.

## 1. Scope

A counting semaphore as a pure, deterministic state machine -- the semantic
core that a scheduler, atomics backend or blocking runtime would drive:

- fixed capacity with free-permit accounting;
- non-blocking acquire (`sem_try_acquire`) with a would-block outcome;
- a FIFO waiter queue with per-waiter request sizes (`sem_enqueue_waiter`)
  and strict-FIFO wakeups (`sem_grant_next`);
- permit release with over-release protection (`sem_release`);
- waiter-set teardown (`sem_drain`);
- stats counters (`grants`, `blocks`, `releases`) and an ordered wakeup
  trace (`grant_order`, rendered by `sem_grant_trace`);
- a structural invariant checker (`sem_check_invariant`).

No threads, no atomics, no locks, no clock, no I/O, no FFI, no global state.
The library owns semantics only; a backend owns concurrency and blocking.

## 2. Non-goals

- Actual blocking, parking, unparking, or scheduling. `sem_grant_next`
  returns the woken waiter ID; the backend performs the wake.
- Atomicity, memory ordering, or thread safety.
- Timeouts, deadlines, priorities, fairness beyond strict FIFO, waiter
  cancellation, or ownership/deadlock analysis.
- Dynamic capacity, permit borrowing, or negative permits.
- Cross-process semaphores or name registries (compare POSIX `sem_open`).

## 3. State

```xi
pub type Semaphore = {
  capacity: Int;       // fixed at construction, >= 0
  permits: Int;        // free permits, 0 <= permits <= capacity
  waiters: Vec[Int];   // FIFO waiter IDs, index 0 = oldest
  waiter_sizes: Vec[Int]; // parallel: waiters[i] requests waiter_sizes[i]
  grants: Int;         // successful grants (try_acquire + grant_next)
  blocks: Int;         // successful enqueue_waiter calls
  releases: Int;       // successful release calls
  grant_order: Vec[Int]; // waiter IDs woken by grant_next, in order
}
```

Every field is an internal implementation detail; callers go through the
free functions. `waiters` and `waiter_sizes` are parallel Vec[Int] fields
kept mirrored by every mutation (enqueue pushes both; `grant_next` and
`sem_drain` remove from both).

### 3.1 Invariant

`sem_check_invariant(s)` is true exactly when:

1. `capacity >= 0`;
2. `0 <= permits <= capacity`;
3. `waiters.len() == waiter_sizes.len()`;
4. `grant_order.len() <= grants` and `grant_order.len() <= blocks`;
5. every queued ID is `>= 0` and unique in the queue;
6. every queued request size is in `[1, capacity]`.

## 4. State machine rules

Notation: `s` is a `Semaphore`, `c = s.capacity`, `p = s.permits`.

### 4.1 S1 -- construction (`sem_new(cap)`)

- precondition: `cap >= 0`;
- effect: `capacity = cap`, `permits = cap`, all three counters and both
  queues empty;
- error: `Err("semaphore: capacity must be >= 0")` when `cap < 0`
  (no state produced).

### 4.2 S2 -- non-blocking acquire (`sem_try_acquire(n)`)

Validation order:

1. `n < 1` -> `Err("semaphore: n must be >= 1")`;
2. `n > c` -> `Err("semaphore: request exceeds capacity")` (a request
   larger than capacity can never be satisfied, so it is invalid rather
   than a would-block);
3. `n > p` -> `Err("semaphore: would block")`;
4. otherwise `permits = p - n`, `grants += 1`, `Ok(permits)`.

Cases 1-3 leave the state completely unchanged (no counter moves).

### 4.3 S3 -- enqueue a waiter (`sem_enqueue_waiter(id, n)`)

Validation order:

1. `id < 0` -> `Err("semaphore: waiter id must be >= 0")`;
2. `n < 1` -> `Err("semaphore: n must be >= 1")`;
3. `n > c` -> `Err("semaphore: request exceeds capacity")`;
4. `id` already queued -> `Err("semaphore: duplicate waiter id")`;
5. otherwise append `id` to `waiters` and `n` to `waiter_sizes` (FIFO back),
   `blocks += 1`, `Ok(waiters.len() - 1)` -- the 0-based position the waiter
   now occupies.

Every error leaves the state unchanged. Enqueueing is legal even while
permits are free: the caller decides when blocking is modelled.

### 4.4 S4 -- grant the queue head (`sem_grant_next()`)

See section 5 for the algorithm. Outcomes:

- empty queue -> `None`, no state change;
- head request `> p` -> `None`, no state change (strict FIFO: the head is
  never bypassed, so a large head blocks smaller followers);
- otherwise the head `(id, need)` is removed from both queues,
  `permits = p - need`, `grants += 1`, `id` is appended to `grant_order`,
  and `Some(id)` is returned.

### 4.5 S5 -- release (`sem_release(n)`)

1. `n < 1` -> `Err("semaphore: n must be >= 1")`;
2. `n > c - p` -> `Err("semaphore: over-release (permits would exceed
   capacity)")`; the capacity bound is the definition of over-release, so a
   release that would push `permits` past `capacity` is refused even when
   waiters are queued;
3. otherwise `permits = p + n`, `releases += 1`, `Ok(permits)`.

Release does **not** grant waiters; the driver calls `sem_grant_next` to
model wakeups. This keeps release O(1) and the wake policy explicit.

### 4.6 S6 -- drain (`sem_drain()`)

Removes every queued waiter and returns their IDs oldest-first. `permits`,
`capacity` and all counters are untouched (the waiters are abandoned, not
granted, so `blocks` still counts them and `grant_order` does not grow).

### 4.7 Derived state

`grant_order` is the fairness witness: the sequence of waiter IDs actually
woken, in order. `grants` counts *all* successful grants, i.e. waiter
wakeups plus successful `sem_try_acquire` calls, so
`grant_order.len() <= grants` and `grant_order.len() <= blocks`.

## 5. Grant algorithm

```
sem_grant_next(s):
    if len(s.waiters) == 0:                    # nothing to wake
        return None
    id   = s.waiters[0]                        # head = oldest waiter
    need = s.waiter_sizes[0]                   # its full request
    if need > s.permits:                       # head cannot be satisfied:
        return None                            # strict FIFO, no bypass
    pop_front(s)                               # rebuild both Vecs from index 1
    s.permits     = s.permits - need
    s.grants      = s.grants + 1
    s.grant_order.push(id)
    return Some(id)
```

Properties:

- **Atomic per step**: exactly one waiter is granted per successful call;
  never a partial grant.
- **Strict FIFO**: only the head is examined; the queue order is never
  bypassed, hence head-of-line blocking.
- **Idempotent refusals**: `None` never changes state, so a driver may call
  `grant_next` whenever permits may have changed.
- **Winnable-prefix drain**: calling `grant_next` repeatedly grants the
  longest satisfiable head prefix; it stops at the first head that does not
  fit.

## 6. Error catalog

All error strings are stable and prefixed `semaphore: `.

| Function | Condition | Err message | State on error |
|---|---|---|---|
| `sem_new` | `capacity < 0` | `semaphore: capacity must be >= 0` | no value produced |
| `sem_try_acquire` | `n < 1` | `semaphore: n must be >= 1` | unchanged |
| `sem_try_acquire` | `n > capacity` | `semaphore: request exceeds capacity` | unchanged |
| `sem_try_acquire` | `n > permits` | `semaphore: would block` | unchanged |
| `sem_enqueue_waiter` | `id < 0` | `semaphore: waiter id must be >= 0` | unchanged |
| `sem_enqueue_waiter` | `n < 1` | `semaphore: n must be >= 1` | unchanged |
| `sem_enqueue_waiter` | `n > capacity` | `semaphore: request exceeds capacity` | unchanged |
| `sem_enqueue_waiter` | `id` already queued | `semaphore: duplicate waiter id` | unchanged |
| `sem_release` | `n < 1` | `semaphore: n must be >= 1` | unchanged |
| `sem_release` | `n > capacity - permits` | `semaphore: over-release (permits would exceed capacity)` | unchanged |

No panicking input exists: every function is total, and read accessors
return `-1`/`""` sentinels instead of erroring (`sem_queue_id_at`,
`sem_queue_size_at` return `-1` out of range; `sem_grant_trace` returns `""`
for an empty trace).

## 7. Complexity

| Operation | Complexity |
|---|---|
| `sem_new` | O(1) |
| `sem_try_acquire` | O(1) |
| `sem_release` | O(1) |
| `sem_capacity` / `sem_permits` / `sem_queue_len` / counters | O(1) |
| `sem_queue_id_at` / `sem_queue_size_at` | O(1) |
| `sem_enqueue_waiter` | O(queue length) -- duplicate scan |
| `sem_grant_next` | O(queue length) -- front removal rebuilds both Vecs |
| `sem_drain` | O(queue length) |
| `sem_queue_ids` / `sem_grant_order` / `sem_grant_trace` | O(n) copies |
| `sem_check_invariant` | O(queue length^2) -- pairwise ID uniqueness |

## 8. Test plan

`tests/test_conformance.xi` (`module semaphore_tests`, 23 named checks, a
hello-style `main` that prints `[PASS]`/`[FAIL]` per check, a summary line,
and returns the failure count). Fixtures are built in-test through
`sem_new`; error checks route every string comparison through
`compare.str_compare`.

1. `sem_new` initializes capacity, permits, zero stats;
2. `sem_new` rejects negative capacity with a stable error;
3. a zero-capacity semaphore is valid and refuses requests;
4. `try_acquire` consumes permits and counts grants;
5. `try_acquire` exhausts capacity then reports would block;
6. a refused acquire leaves permits and stats unchanged;
7. `try_acquire` validates `n`: >= 1 and <= capacity;
8. a full-capacity request is granted exactly once;
9. `enqueue_waiter` appends FIFO with mirrored request sizes;
10. `enqueue_waiter` validates id, n, capacity and uniqueness;
11. `grant_next` on an empty queue returns `None` unchanged;
12. `grant_next` waits while no permits are free;
13. grants wake queued waiters in FIFO order (trace `"101,102"`);
14. strict FIFO: a large head blocks smaller followers;
15. release returns permits and refuses over-release;
16. release validates `n` and never lets permits exceed capacity;
17. `drain` removes queued waiters in FIFO order without granting;
18. stats accumulate grants, blocks and releases;
19. `grant_trace` renders the ordered wakeup log;
20. queue accessors are safe out of range (`-1`);
21. `queue_ids` and `grant_order` return copies;
22. the invariant holds across 240 mixed transitions;
23. a granted waiter id may re-enqueue.

Run from the repository root:

```
.\scripts\port.ps1 -Package xiom.semaphore
```

Last verified: compiler v0.62.0, `port: PASS (passed=23 failed=0
program_exit=0 exit=0)`.

## 9. Compiler / stdlib notes for v0.62.0

- Free functions only (no methods), with explicit `&`/`&mut` parameters and
  `&mut` at every call site.
- `Ok`/`Err` are constructed only inside the `_ok_*` / `_err_*` leaf helper
  functions (direct Result construction in struct-returning functions is
  miscompiled on this line).
- `Vec[Int]` element reads are bound with a typed `let` before use.
- Parallel `Vec[Int]` fields (`waiters` / `waiter_sizes`) are pushed and
  rebuilt in the same function, so they can never skew.
- Str equality (tests) goes through `str_compare`; `==` on `Str` values read
  from Vec elements lowers to a pointer comparison.
- No `Vec[StructType]`, no indexed `Vec[fn]` dispatch, no generic callbacks,
  no `Vec[Float64]`, no `mut` in match patterns, no FFI, no threads.
- No `log`-named function (reserved-shape trap); the trace accessor is
  `sem_grant_order` / `sem_grant_trace`.

## 10. Known limitations

- The model is single-threaded and non-atomic; a concurrent backend must
  provide the critical section around every transition.
- Strict FIFO with head-of-line blocking: no work-conserving bypass, no
  priorities, no fairness beyond arrival order.
- No timeouts, no waiter self-cancellation, no ownership tracking; waiters
  leave the queue only by grant or `drain`.
- Capacity is fixed; release refuses over-release rather than growing.
- Waiter IDs are caller-assigned; uniqueness is enforced only while queued.
- `sem_grant_next` rebuilds the queue vectors (O(queue length)); a backend
  with very long queues would use an index-based ring instead.
