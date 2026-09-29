# xiom.timer

Pure, deterministic **hierarchical timer wheel** over integer ticks.

> **Status:** `incubating` -- conformance-tested (21/21); published at `v0.1.1` on the XIOM registry.
> **Deps:** `xiom.std` only; the module itself imports nothing and calls no FFI.

## What this package is for

A timer wheel is the classic data structure behind "wake me up N time units
from now" services: network stacks, game loops, embedded supervisors and
event loops that must track thousands of pending timeouts without scanning a
list on every step. This package provides one over **abstract integer ticks**:

- `timer_insert(id, delay_ticks)` schedules an id to fire.
- `timer_advance(ticks)` advances the simulated clock and collects the ids
  that came due.
- `timer_cancel(id)` removes a pending id.
- `timer_pending_count()` / `timer_is_scheduled(id)` inspect the wheel.

The wheel is a `levels x slots` hierarchy (default 4 x 64). A delay is placed
at the lowest level whose coverage holds it, so inserting and advancing cost
O(1) bucket work instead of a scan of all pending timers; as time passes,
bucket wraps re-bucket entries down the levels (cascading) until they fire.

## What this package is NOT

- **No clocks and no wall-clock promises.** It never reads the clock, never
  sleeps, never spawns threads, never calls FFI. `timer_advance(ticks)` is a
  pure simulation step. Mapping ticks to milliseconds, coalescing late
  callbacks, or catching up after a stall is entirely the caller's job.
- **Not a real-time guarantee.** "Fires at tick T" means exactly that inside
  the simulation; it says nothing about when a thread wakes in real time.
- **Not thread-safe.** The wheel is one process-wide mutable state; guard it
  with the application's own locking if it is shared.
- **No `Vec[StructType]` storage and no heap nodes.** All state lives in
  parallel primitive vectors pre-sized at configuration time; fires and
  cancels recycle pool slots.

## Geometry and limits

| Item | Default | Meaning |
|------|---------|---------|
| levels | 4 | hierarchy depth, 1..8 |
| slots | 64 | buckets per level, 2..1024 |
| granularity of level L | `slots^L` | 1, 64, 4096, 262144 ticks |
| max delay | `slots^levels - 1` | 16777215 ticks |
| capacity | 1024 | simultaneous active entries |

`timer_configure(levels, slots)` validates the geometry, rebuilds the wheel
and **resets everything** (entries, clock, counters). On `Err` the previous
configuration is untouched. The first use without a configure lazily sets up
the default 4 x 64 wheel.

## Quick start

```xiom
use xiom.timer;

// optional explicit geometry; the lazy default is already 4 x 64
let cfg = timer_configure(4, 64);     // Ok(16777215) = max delay

let a = timer_insert(101, 250);       // Ok(1): placed at level 1
let b = timer_insert(102, 3);         // Ok(0)
timer_cancel(101);                    // Ok(250): remaining ticks

let adv = timer_advance(10);          // Ok(1): id 102 fired on tick 3

var i = 0;
while i < timer_fired_count() {
  let r = timer_fired_id(i);          // Ok(id) in firing order
  if r.is_ok { /* r.value is the id */ }
  i = i + 1;
}

timer_is_scheduled(102);              // false now
timer_now();                          // 10
```

Errors are typed values, not strings:

```xiom
let r = timer_insert(7, 0);
// r.is_ok == false
// r.error.code == 6   ("timer: delay must be positive")
// r.error.id == 7
// r.error.delay == 0
timer_error_message(6);               // "timer: delay must be positive"
```

## Ordering

Firing is deterministic. Entries that share a bucket keep FIFO insertion
order, so entries inserted back-to-back with the same delay fire in insertion
order. Within one tick, ids fire from the higher-level cascade buckets first
(highest level first) and then from the level-0 bucket, always in chain
order. See SPEC.md section 5 for the precise contract.

## Testing

```powershell
& .\scripts\port.ps1 -Package xiom.timer
```

The suite (`tests/test_conformance.xi`, 21 checks) builds all state in-test
and pins: geometry validation, delay-to-bucket breakdown, exact firing ticks,
FIFO ordering, one-level and multi-level cascades with cascade counts, the
2 x 4 wrap boundary, long idle advances, the max-delay boundary, duplicate
and unknown-id errors, pool capacity and slot reuse, cross-bucket same-tick
ordering, and the error catalog.

## Documentation

- `SPEC.md` -- data model, tick semantics, ordering, invariants, error catalog.
- `src/timer.xi` -- implementation and per-function contracts.
