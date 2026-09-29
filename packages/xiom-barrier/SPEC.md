# xiom.barrier -- Specification

Status: `incubating` (implemented, harness-green, not published).
Module: `xiom.barrier` (`src/barrier.xi`). Manifest: `package.xi` (name
`xiom.barrier`, version `0.1.0`). `xiom.std` is a manifest dependency; the
library module imports `xiom.string` and `xiom.convert` only.

## 1. Scope

A reusable multiparty barrier as a pure, deterministic state machine -- the
semantic core that a thread scheduler, atomics backend or blocking runtime
would drive:

- a fixed party count (`N >= 1`) with per-generation arrival tracking;
- `barrier_arrive(id)` recording one arrival and reporting whether it tripped
  the barrier and whether the caller is the leader (the last arriver);
- trip semantics: the Nth distinct arrival increments the generation, clears
  the arrival set, releases all N waiters and flips the sense flag;
- per-arrival generation records pinning every waiter to the generation it
  joined, with `barrier_waiter_released` as the release predicate;
- a sense-reversal flag model with documented semantics;
- a wait-queue trace helper for tests (`barrier_wait_trace`);
- an explicit `barrier_reset` (refused mid-generation);
- stats counters (`arrivals_total`, `trips`, `released`) and last-trip
  metadata (`last_trip_generation`, `last_trip_leader`, `last_trip_parties`);
- a structural invariant checker (`barrier_check_invariant`).

No threads, no atomics, no locks, no clock, no I/O, no FFI, no global state.
The library owns semantics only; a backend owns concurrency and blocking.

## 2. Non-goals

- Actual blocking, parking, unparking, or scheduling. `barrier_arrive`
  returns the outcome; the backend performs the wake.
- Atomicity, memory ordering, or thread safety.
- Timeouts, deadlines, per-party cancellation, or deadlock analysis; a
  generation completes only when every distinct party arrives.
- Phase payload exchange (no data is carried by an arrival).
- Dynamic party counts (`barrier_reset` preserves `parties`).
- Cross-process barriers or name registries.

## 3. State

```xi
pub type Barrier = {
  parties: Int;              // required arrivals per generation, fixed, >= 1
  generation: Int;           // current generation index, >= 0
  sense: Int;                // sense-reversal flag, 0 or 1
  arrivals: Vec[Int];        // pending party IDs, arrival order
  arrival_gens: Vec[Int];    // parallel: generation each arrival joined
  arrivals_total: Int;       // successful barrier_arrive calls
  trips: Int;                // completed generations
  released: Int;             // waiters released by trips
  last_trip_generation: Int; // generation that tripped last, -1 if none
  last_trip_leader: Int;     // its last arriver, -1 if none
  last_trip_parties: Vec[Int]; // IDs it released, arrival order, empty if none
}
```

```xi
pub type BarrierArrival = {
  tripped: Bool;             // this arrival completed the generation
  leader: Bool;              // last arriver (equals tripped in this model)
  position: Int;             // 0-based arrival position in the joined generation
  generation: Int;           // generation index the arrival joined
  sense: Int;                // sense observed after the call
}
```

Every field is an internal implementation detail; callers go through the free
functions. `arrivals` and `arrival_gens` are parallel Vec[Int] fields kept
mirrored by every mutation (arrive pushes both; trip and reset clear both).

### 3.1 Invariant

`barrier_check_invariant(b)` is true exactly when:

1. `parties >= 1`;
2. `generation >= 0` and `generation == trips`;
3. `sense` is `0` or `1` and `sense == trips % 2`;
4. `arrivals.len() == arrival_gens.len()` and `arrivals.len() < parties`;
5. every pending ID is `>= 0` and unique, and every recorded generation equals
   the current `generation`;
6. `released == trips * parties`;
7. `arrivals_total == trips * parties + arrivals.len()`;
8. before the first trip (`trips == 0`): `last_trip_generation == -1`,
   `last_trip_leader == -1`, `last_trip_parties` empty;
9. after a trip (`trips > 0`): `last_trip_generation == trips - 1`,
   `last_trip_leader >= 0`, `last_trip_parties.len() == parties`.

Notes: (2) holds because `generation` and `trips` move together (one per
trip) and `barrier_reset` zeroes both. (5) holds because arrivers are pinned
to the generation they joined and every trip clears the arrival set. (7)
holds because every successful arrival is either still pending or was
released by a trip; failed arrivals never move a counter.

## 4. State machine rules

Notation: `b` is a `Barrier`, `N = b.parties`, `g = b.generation`.

### 4.1 S1 -- construction (`barrier_new(parties)`)

- precondition: `parties >= 1`;
- effect: `parties = parties`, `generation = 0`, `sense = 0`, both arrival
  Vecs empty, all counters zero, last-trip metadata at its `-1`/empty
  sentinels;
- error: `Err("barrier: parties must be >= 1")` when `parties < 1` (no value
  produced).

### 4.2 S2 -- arrival (`barrier_arrive(id)`)

Validation order:

1. `N < 1` -> `Err("barrier: parties must be >= 1")` (defensive: unreachable
   through `barrier_new`, but a hand-built `Barrier` value is still total);
2. `id < 0` -> `Err("barrier: party id must be >= 0")`;
3. `id` already in `arrivals` -> `Err("barrier: duplicate party id in
   generation")`;
4. otherwise record the arrival: `arrivals.push(id)`,
   `arrival_gens.push(g)`, `arrivals_total += 1`, and the arrival position is
   `arrivals.len() - 1`;
5. if `arrivals.len() == N` -> the trip transition S3 runs and the leader
   outcome is returned;
6. otherwise the non-trip outcome is returned:
   `tripped = false`, `leader = false`, `position = arrivals.len() - 1`,
   `generation = g`, `sense = b.sense`.

Cases 1-3 leave the state completely unchanged (counters too). Party IDs are
opaque non-negative integers; uniqueness is required only while the party is
pending in the current generation.

### 4.3 S3 -- trip transition (inside `barrier_arrive`)

Runs when the arriving party is the Nth distinct arriver. In order:

1. snapshot the pending IDs (arrival order) into `last_trip_parties`;
2. `last_trip_generation = g` (the completed generation);
3. `last_trip_leader = id` (the last arriver);
4. `trips += 1` and `released += N`;
5. `sense = 1 - sense` (sense reversal);
6. `generation = g + 1`;
7. clear `arrivals` and `arrival_gens`;
8. return `BarrierArrival{ tripped: true, leader: true, position: N - 1,
   generation: g, sense: new sense }`.

The snapshot (step 1) happens before the clear (step 7), so the trip metadata
survives the transition and the leader is the last element of
`last_trip_parties`. The tripping arrival's outcome reports the **completed**
generation `g`, while the barrier state immediately reports `g + 1`.

### 4.4 S4 -- reset (`barrier_reset()`)

- if `arrivals.len() > 0` -> `Err("barrier: cannot reset mid-generation")`;
  the state is unchanged, so a reset can never strand a waiter or silently
  drop arrivals;
- otherwise restore the freshly-constructed state: `generation = 0`,
  `sense = 0`, clear both arrival Vecs, `arrivals_total = 0`, `trips = 0`,
  `released = 0`, `last_trip_generation = -1`, `last_trip_leader = -1`, clear
  `last_trip_parties`; `parties` is preserved;
- returns `Ok(0)` -- the generation after the reset.

Reset is a full reinitialization except for `parties`: stats and last-trip
metadata are wiped, so `barrier_reset(b)` and a fresh `barrier_new(parties)`
produce equal values.

### 4.5 Derived state and accounting

- `generation == trips` at all times; the generation that tripped last is
  `trips - 1` (or none).
- `sense == trips % 2`: sense starts at 0 and flips exactly once per trip.
- `released == trips * N`: every trip releases exactly the N participants.
- `arrivals_total == trips * N + arrivals.len()`: every successful arrival is
  released by a trip or still pending; refused arrivals do not count.
- `last_trip_parties` is the release trace of the most recent trip, in
  arrival order (the leader is last).

## 5. Sense-reversal model

A classic sense-reversing barrier works as follows: each waiter captures the
shared sense bit on arrival and spins (or parks) until the bit differs; the
last arriver flips the bit while releasing everyone, so no waiter can mistake
a *new* generation's partial arrivals for its own release.

This module models that flag deterministically:

- `sense` is an `Int` in `{0, 1}`; it is flipped by every trip and rewound
  only by `barrier_reset`;
- every arrival is pinned to the generation it joined
  (`arrival_gens[i] == generation` at insertion time);
- the release predicate is the generation test, not a count test:
  `barrier_waiter_released(b, g)` returns `b.generation > g`;
- because a generation trip flips the sense exactly once and increments the
  generation exactly once, "sense has flipped since my arrival" and "the
  generation has advanced past my recorded generation" are the same
  condition; the generation test is used because it is unambiguous across
  multiple generations.

In a backend, the flow is: capture `g = barrier_generation(b)` (equivalently
the sense) -> `barrier_arrive(b, id)` -> if not tripped, park/spin until
`barrier_waiter_released(b, g)` -> if tripped (leader), flip/observe the sense
and release the waiters. A negative recorded generation is always in the
past, so `barrier_waiter_released(b, g)` returns true for `g < 0`.

## 6. Wait-queue trace

`barrier_wait_trace(b)` renders the pending wait set as comma-separated
`id@generation` pairs in arrival order; `""` when nothing is pending. Since
every trip clears the arrival set, every rendered generation is the current
one; the trace exists so tests (and backend debugging) can see exactly which
parties are still waiting and which generation pins them. Example: parties
`[4, 2]` waiting in generation 0 renders `"4@0,2@0"`.

## 7. Error catalog

All error strings are stable and prefixed `barrier: `.

| Function | Condition | Err message | State on error |
|---|---|---|---|
| `barrier_new` | `parties < 1` | `barrier: parties must be >= 1` | no value produced |
| `barrier_arrive` | `parties < 1` | `barrier: parties must be >= 1` | unchanged |
| `barrier_arrive` | `id < 0` | `barrier: party id must be >= 0` | unchanged |
| `barrier_arrive` | `id` already pending | `barrier: duplicate party id in generation` | unchanged |
| `barrier_reset` | `arrivals.len() > 0` | `barrier: cannot reset mid-generation` | unchanged |

No panicking input exists: every function is total, and read accessors return
`-1`/`""` sentinels instead of erroring (`barrier_arrived_id_at`,
`barrier_arrived_gen_at` return `-1` out of range; `barrier_wait_trace`
returns `""` for an empty wait set; `barrier_last_trip_generation` /
`barrier_last_trip_leader` return `-1` before the first trip).

## 8. Complexity

| Operation | Complexity |
|---|---|
| `barrier_new` | O(1) |
| `barrier_arrive` (no trip) | O(arrivals) -- duplicate scan |
| `barrier_arrive` (trip) | O(arrivals + N) -- snapshot + clear |
| `barrier_reset` / `barrier_waiter_released` | O(1) |
| `barrier_parties` / `barrier_generation` / `barrier_sense` / counters / last-trip scalars | O(1) |
| `barrier_arrived_count` / `barrier_arrived_id_at` / `barrier_arrived_gen_at` | O(1) |
| `barrier_arrived_ids` / `barrier_last_trip_parties` | O(n) copies |
| `barrier_wait_trace` | O(arrivals) |
| `barrier_check_invariant` | O(arrivals^2) -- pairwise ID uniqueness |

## 9. Test plan

`tests/test_conformance.xi` (`module barrier_tests`, 24 named checks, a
hello-style `main` that prints `[PASS]`/`[FAIL]` per check, a summary line,
and returns the failure count). Fixtures are built in-test through
`barrier_new` (or a raw literal for the invalid-parties case); error checks
route every string comparison through `compare.str_compare`.

1. `barrier_new` initializes parties, generation 0, sense 0 and zero stats;
2. `barrier_new` rejects zero and negative parties with a stable error;
3. arrivals accumulate in arrival order without tripping early;
4. the Nth arrival trips the barrier and publishes trip metadata;
5. generations advance across reuses with per-generation leaders (varying
   arrival orders);
6. a duplicate id is refused in-generation but reusable next generation;
7. `arrive` rejects negative party ids without changing state;
8. `arrive` on a zero-parties barrier fails with the stable error;
9. arrival accessors are safe out of range (`-1`) and return copies;
10. arrival outcomes report position, generation, sense and leadership;
11. the sense flag flips on every trip and arrivals observe it;
12. `waiter_released` is true exactly when its generation has passed;
13. a one-party barrier trips on every arrival;
14. reset refuses while parties are mid-generation, state unchanged;
15. reset when idle restores the initial state and reusability;
16. stats count successful arrivals, trips and released waiters only;
17. `wait_trace` renders the pending waiters as `id@generation`;
18. `last_trip_parties` preserves arrival order and returns a copy;
19. last-trip metadata tracks the most recent generation only;
20. the invariant holds across mixed arrivals and resets (40 rounds);
21. the barrier never trips before `parties` arrivals;
22. party id 0 and large ids are valid;
23. ten generations accumulate trips, releases and stats;
24. reset is refused mid-generation and accepted once the trip completes.

Run from the repository root:

```
.\scripts\port.ps1 -Package xiom.barrier
```

Last verified: compiler v0.62.1, `port: PASS (passed=24 failed=0
program_exit=0 exit=0)`.

## 10. Compiler / stdlib notes for v0.62.1

- Free functions only (no methods), with explicit `&`/`&mut` parameters and
  `&mut` at every call site.
- `Ok`/`Err` are constructed only inside the `_ok_*` / `_err_*` leaf helper
  functions; `BarrierArrival`/`Barrier` struct literals are built inside
  those leaf calls.
- `Vec[Int]` element reads are bound with a typed `let` before use.
- Parallel `Vec[Int]` fields (`arrivals` / `arrival_gens`) are pushed and
  cleared in the same function, so they can never skew.
- Str equality (tests) goes through `str_compare`; `==` on `Str` values read
  from Vec elements lowers to a pointer comparison.
- Integer conversions go through `xiom.convert.int_to_string`; no byte-level
  or bitfield tricks are used (the sense flip is `1 - sense`, parity is
  `trips % 2`).
- No `Vec[StructType]`, no indexed `Vec[fn]` dispatch, no generic callbacks,
  no `Vec[Float64]`, no `mut` in match patterns, no FFI, no threads.
- No `log`-named function (reserved-shape trap); the trace accessor is
  `barrier_wait_trace`.

## 11. Known limitations

- The model is single-threaded and non-atomic; a concurrent backend must
  provide the critical section around every transition.
- `leader` always equals `tripped`: the last arriver is the trip leader by
  construction, so there is no separate phase-action actor.
- A generation completes only when every distinct party arrives: no timeout,
  cancellation, or fault tolerance; one missing party stalls the barrier.
- Party IDs are caller-assigned; uniqueness is enforced only while pending.
- `barrier_reset` is a full reinitialization (stats and metadata included);
  there is no "soft" generation rollover other than completing a trip.
- No payload exchange: the trip records who arrived, not any data.
- `barrier_arrive`'s duplicate scan is O(arrivals); a backend with very large
  party counts would use a hash set over pending IDs instead.
