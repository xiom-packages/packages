# xiom.barrier

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** a reusable multiparty barrier as a pure, deterministic state
> machine: party counts, per-generation arrival tracking, trip/leader
> outcomes, sense reversal, explicit reset, last-trip metadata and stats. The
> model is the semantic core a scheduler/atomics backend would drive -- it
> contains no threads, no atomics, no locks and no clock.
> **Deps:** `xiom.std` (manifest only); the library imports `xiom.string`
> and `xiom.convert` from it, the tests additionally use `xiom.test` and
> `xiom.io`.

## What it is

`xiom.barrier` models the classical reusable barrier as a plain value type
and a set of free functions. A `Barrier` holds a fixed party count (`N >= 1`),
the current generation index, a sense-reversal flag, the party IDs that have
arrived in the current generation (each pinned to the generation it joined),
three counters (`arrivals_total`, `trips`, `released`) and last-trip metadata
(`last_trip_generation`, `last_trip_leader`, `last_trip_parties`).

Because there is no concurrency in the library, every operation is a total,
deterministic transition: given the same state and inputs, the same state and
outcome follow. A real backend (a thread scheduler, `xiom.sync` primitives,
an event loop) owns atomicity and blocking; this module owns the *semantics*
-- what a correct barrier must do -- in a form that can be tested exactly,
without sleeps or races.

An arrival is recorded with `barrier_arrive`; when the Nth distinct party
arrives the barrier **trips**: the generation increments, the arrival set is
cleared, all N waiters are released, the sense flag flips and the last-trip
metadata is published. The tripping (last) arriver is the **leader**. A
waiter that joined generation `g` is released exactly when the barrier has
moved past `g`; `barrier_waiter_released(b, g)` exposes that predicate and
`barrier_wait_trace` renders the pending wait set (which parties are still
waiting and which generation pins them) for tests and debugging.

Because arrivals are cleared by every trip, a party ID may be reused after
each trip; it is refused only while it is already waiting in the current
generation.

## API

| Function | Returns | Description |
|---|---|---|
| `barrier_new(parties)` | `Result[Barrier, Str]` | New barrier in generation 0 with sense 0; `parties` must be >= 1. |
| `barrier_arrive(&mut b, id)` | `Result[BarrierArrival, Str]` | Record an arrival; `Ok` carries the arrival outcome. |
| `barrier_reset(&mut b)` | `Result[Int, Str]` | Restore the initial state; refused while parties are mid-generation. |
| `barrier_waiter_released(b, generation)` | `Bool` | True once the barrier has moved past `generation`. |
| `barrier_parties(b)` | `Int` | Required arrivals per generation. |
| `barrier_generation(b)` | `Int` | Current generation index (equals the trip count). |
| `barrier_sense(b)` | `Int` | Sense-reversal flag (`0` or `1`), flipped by every trip. |
| `barrier_arrived_count(b)` | `Int` | Parties waiting in the current generation. |
| `barrier_arrived_id_at(b, i)` | `Int` | Party ID at arrival position `i`; `-1` out of range. |
| `barrier_arrived_gen_at(b, i)` | `Int` | Recorded generation at position `i`; `-1` out of range. |
| `barrier_arrived_ids(b)` | `Vec[Int]` | Copy of pending IDs, in arrival order. |
| `barrier_wait_trace(b)` | `Str` | Pending waiters as `id@generation` pairs (`""` when empty). |
| `barrier_arrivals_total(b)` | `Int` | Successful arrivals since construction or the last reset. |
| `barrier_trip_count(b)` | `Int` | Completed generations since construction or the last reset. |
| `barrier_released_count(b)` | `Int` | Waiters released by trips (always `trips * parties`). |
| `barrier_last_trip_generation(b)` | `Int` | Generation that tripped last; `-1` before the first trip. |
| `barrier_last_trip_leader(b)` | `Int` | Last arriver of the most recent trip; `-1` before the first trip. |
| `barrier_last_trip_parties(b)` | `Vec[Int]` | IDs released by the most recent trip, arrival order; empty before the first trip. |
| `barrier_check_invariant(b)` | `Bool` | Structural invariant check (see SPEC.md). |

`BarrierArrival` (the `Ok` payload of `barrier_arrive`):

| Field | Type | Meaning |
|---|---|---|
| `tripped` | `Bool` | This arrival completed the generation. |
| `leader` | `Bool` | True for the last arriver (equals `tripped` in this model). |
| `position` | `Int` | 0-based arrival position in the joined generation (`N-1` for the leader). |
| `generation` | `Int` | Generation index the arrival joined. |
| `sense` | `Int` | Sense observed after the call (flipped when the call tripped). |

Every struct field is an internal implementation detail; callers must go
through the free functions.

## Usage

```xi
use xiom.barrier;

match barrier_new(3) {
  Ok(b) => {
    var bar = b;

    // First two arrivals are recorded, not tripping.
    barrier_arrive(&mut bar, 101);   // tripped=false, position=0
    barrier_arrive(&mut bar, 102);   // tripped=false, position=1

    // The third arrival trips: leader=true, position=2, generation now 1.
    match barrier_arrive(&mut bar, 103) {
      Ok(a) => { /* a.tripped && a.leader */ },
      Err(_) => { /* "barrier: duplicate party id in generation" */ },
    }

    // A waiter that joined generation 0 has been released:
    let released = barrier_waiter_released(&bar, 0);  // true
    // ... and the same party IDs may arrive in generation 1.
  },
  Err(_) => { /* "barrier: parties must be >= 1" */ },
}
```

Recommended driver loop for a backend:

```xi
// Spin/park until the recorded generation has passed:
let g = barrier_generation(&bar);      // generation captured at arrival
var arrived = barrier_arrive(&mut bar, party_id);
// the backend parks non-leaders; on wake it checks:
//   barrier_waiter_released(&bar, g)
// The leader (arrived.tripped) drives the release of every waiter.
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.barrier
```

Expected: the namespaced module passes the section-4 namespace rule, 24
`[PASS]` lines, and a final `port: PASS (passed=24 failed=0 program_exit=0
exit=0)`.

## Limitations

- **No threads, atomics, or locks.** This is a deterministic semantic model,
  not a synchronisation primitive. A concurrent backend must serialise every
  transition (e.g. via `xiom.sync` primitives) and implement the actual
  parking/wakeup; the library does not make any operation atomic.
- **`leader` equals `tripped` by construction.** The last arriver always
  trips the barrier, so there is no separate "barrier action" thread model;
  the flag only tells a backend which caller should drive the release.
- **Waiters leave only by trip or reset.** There is no timeout, cancellation
  or per-party abort; one slow party blocks the whole generation forever.
- **`parties` is fixed** at construction; `barrier_reset` preserves it.
- **`barrier_reset` is a full reinitialization** of everything except
  `parties`: generation 0, sense 0, cleared last-trip metadata, zero stats.
- **Duplicate detection is per generation.** Party IDs are caller-assigned
  and opaque; uniqueness is enforced only while a party waits in the current
  generation, and a released ID may arrive again immediately.
- **`barrier_wait_trace` renders pending waiters only.** Released waiters are
  summarized by `barrier_released_count`, not listed individually.
- **No phase payloads.** The trip publishes who arrived, not any data those
  parties produced; a backend would pair it with a separate exchange buffer.
- Not thread-safe: values follow ordinary XIOM move/borrow rules.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
