# xiom.semaphore

> **Status:** `incubating` -- conformance-tested (23/23); published at `v0.1.1` on the XIOM registry.
> **Scope:** a counting semaphore as a pure, deterministic state machine:
> permit accounting, a FIFO waiter queue, wakeup grants, over-release
> protection, stats counters, and a fairness trace. The model is the semantic
> core a scheduler/atomics backend would drive -- it contains no threads, no
> atomics, no locks and no clock.
> **Deps:** `xiom.std` (manifest only); the library imports `xiom.string`
> and `xiom.convert` from it, the tests additionally use `xiom.test` and
> `xiom.io`.

## What it is

`xiom.semaphore` models the classical counting semaphore as a plain value
type and a set of free functions. A `Semaphore` holds a fixed `capacity`, the
number of free `permits`, a FIFO queue of blocked waiter IDs (each with its
request size), three counters (`grants`, `blocks`, `releases`), and an
ordered wakeup trace (`grant_order`).

Because there is no concurrency in the library, every operation is a total,
deterministic transition: given the same state and inputs, the same state and
outcome follow. A real backend (a thread scheduler, `xiom.sync` primitives,
an event loop) owns atomicity and blocking; this module owns the *semantics*
-- what a correct semaphore must do -- in a form that can be tested exactly,
without sleeps or races.

The queue is **strict FIFO**: `sem_grant_next` considers only the queue head,
so a large head request blocks smaller followers (head-of-line blocking)
until enough permits accumulate. The wakeup order is recorded in
`grant_order` and rendered by `sem_grant_trace` for fairness assertions.

## API

| Function | Returns | Description |
|---|---|---|
| `sem_new(capacity)` | `Result[Semaphore, Str]` | New semaphore with all permits free; capacity must be >= 0. |
| `sem_try_acquire(&mut s, n)` | `Result[Int, Str]` | Take `n` permits without blocking; `Ok(remaining)`, or `Err("semaphore: would block")`. |
| `sem_enqueue_waiter(&mut s, id, n)` | `Result[Int, Str]` | Append a blocked waiter (ID, request size); `Ok(position)`. |
| `sem_grant_next(&mut s)` | `Option[Int]` | Wake the queue head if its request fits; `Some(id)` or `None`. |
| `sem_release(&mut s, n)` | `Result[Int, Str]` | Return `n` permits; `Ok(free)`, over-release refused. |
| `sem_drain(&mut s)` | `Vec[Int]` | Drop every waiter, returning IDs in FIFO order. |
| `sem_capacity(s)` | `Int` | Fixed capacity. |
| `sem_permits(s)` | `Int` | Free permits (`0 <= permits <= capacity`). |
| `sem_queue_len(s)` | `Int` | Queued waiter count. |
| `sem_queue_id_at(s, i)` | `Int` | Waiter ID at FIFO position `i`; `-1` out of range. |
| `sem_queue_size_at(s, i)` | `Int` | Request size at position `i`; `-1` out of range. |
| `sem_queue_ids(s)` | `Vec[Int]` | Copy of queued IDs, oldest first. |
| `sem_grant_count(s)` | `Int` | Successful grants (`try_acquire` + `grant_next`). |
| `sem_block_count(s)` | `Int` | Waiters enqueued. |
| `sem_release_count(s)` | `Int` | Successful releases. |
| `sem_grant_order_len(s)` | `Int` | Length of the wakeup trace. |
| `sem_grant_order(s)` | `Vec[Int]` | Copy of woken waiter IDs, in wakeup order. |
| `sem_grant_trace(s)` | `Str` | Wakeup trace as comma-separated IDs (`""` when empty). |
| `sem_check_invariant(s)` | `Bool` | Structural invariant check (see SPEC.md). |

Every struct field is an internal implementation detail; callers must go
through the free functions.

## Usage

```xi
use xiom.semaphore;

// A 3-permit semaphore for a pool of three workers.
match sem_new(3) {
  Ok(s) => {
    var sem = s;

    // Non-blocking fast path: take one permit.
    match sem_try_acquire(&mut sem, 1) {
      Ok(remaining) => { /* granted; `remaining` permits are free */ },
      Err(_) => { /* "semaphore: would block" */ },
    }

    // Blocking model: two waiters queue up (FIFO), the driver frees a
    // permit and wakes the head.
    sem_enqueue_waiter(&mut sem, 101, 2);
    sem_enqueue_waiter(&mut sem, 102, 1);
    sem_release(&mut sem, 1);
    sem_grant_next(&mut sem);   // wakes 101 when its full request fits
  },
  Err(_) => { /* "semaphore: capacity must be >= 0" */ },
}
```

Recommended driver loop for a backend:

```xi
// Drain the winnable prefix of the queue:
var woken = sem_grant_next(&mut sem);
while woken.is_some {
  // unpark the waiter in `woken`
  woken = sem_grant_next(&mut sem);
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.semaphore
```

Expected: the namespaced module passes the section-4 namespace rule, 23
`[PASS]` lines, and a final `port: PASS (passed=23 failed=0 program_exit=0
exit=0)`.

## Limitations

- **No threads, atomics, or locks.** This is a deterministic semantic model,
  not a synchronisation primitive. Two threads sharing a `Semaphore` value
  must serialise access themselves (e.g. via `xiom.sync` primitives); the
  library does not make any operation atomic.
- **Strict FIFO with head-of-line blocking.** A limited (or large) head
  request blocks smaller followers until it fits; there is no work-conserving
  skip and no priority.
- **Capacity is fixed** at construction; there is no grow/shrink.
- **Waiter IDs are caller-assigned** and must be unique while queued; the
  library does not validate them against any external registry, and a granted
  ID may be enqueued again.
- **No timeouts, cancellation, or ownership tracking.** Waiters can only
  leave the queue by being granted or by `sem_drain`; a single waiter cannot
  cancel itself.
- **`sem_release` does not auto-grant.** Freeing permits and waking waiters
  are separate transitions; the driver calls `sem_grant_next`.
- **`sem_drain` abandons waiters** (they are removed without being granted).
- Not thread-safe: values follow ordinary XIOM move/borrow rules.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
