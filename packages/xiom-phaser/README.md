# xiom.phaser

> **Status:** `incubating` -- conformance-tested (24/24); published at `v0.1.1` on the XIOM registry.
> **Scope:** a `java.util.concurrent.Phaser`-style multi-party phaser as a
> pure, deterministic state machine: dynamic party registration
> (`register`, `bulkRegister`, `arriveAndDeregister`), parties/arrived/
> unarrived accounting, phase advancement with `onAdvance`-style hooks
> (continue/terminate), termination with a final phase, tiered phasers
> (child advance propagation to the parent) and deadlock-safe bounded
> progression. The model is the semantic core a scheduler/atomics backend
> would drive -- it contains no threads, no atomics, no locks and no clock.
> **Deps:** `xiom.std` (manifest only); the library imports `xiom.string`
> and `xiom.convert` from it, the tests additionally use `xiom.test`,
> `xiom.io` and `xiom.string.compare`.

## What it is

`xiom.phaser` models a multi-party synchronization barrier whose party set
may change over time, as a plain value type plus free functions. A `Phaser`
holds a caller-assigned handle, an optional parent link, the registered
party count, the arrivals recorded in the current phase, the phase counter,
the termination flag, the configured advancement hook and a small set of
counters.

Because there is no concurrency in the library, every operation is a total,
deterministic transition: given the same state and inputs, the same state
and outcome follow. A real backend (a thread scheduler, `xiom.sync`
primitives, an event loop) owns atomicity, parking and wakeups; this module
owns the *semantics* -- what a correct phaser must do -- in a form that can
be tested exactly, without sleeps or races.

The transition rules mirror `java.util.concurrent.Phaser` where the
semantics are observable:

- The phase advances exactly when the last **unarrived** party arrives
  (`unarrived` reaches zero).
- `phaser_arrive_and_deregister` arrives and removes the party; when that
  arrival completes the phase the hook observes the reduced party count,
  exactly like Java's `doArrive(ONE_DEREGISTER)`.
- `phaser_arrive_and_await` is the same arrival transition as
  `phaser_arrive`; the caller's release is observed through
  `phaser_waiter_released` (a non-blocking model has no park loop).
- Termination is triggered by the hook. A terminated phaser has zero
  parties and a final phase (`phaser_last_phase`); all further operations
  fail with a stable `phaser: ` error.

Tiered phasers follow Java's propagation rule: `phaser_new_child` registers
one party credit on the parent, every child phase advance contributes one
arrival to the parent, and a terminal child advance deregisters the credit
through a parent arrive-and-deregister.

## API

| Function | Returns | Description |
|---|---|---|
| `phaser_new(handle, parties)` | `Result[Phaser, Str]` | Root phaser with `parties` registered parties, phase 0, default hook. |
| `phaser_new_child(&mut parent, handle, parties)` | `Result[Phaser, Str]` | Child phaser; registers one party credit on the parent. |
| `phaser_register(&mut p)` | `Result[Int, Str]` | Register one new party; `Ok` is the new party count. |
| `phaser_bulk_register(&mut p, n)` | `Result[Int, Str]` | Register `n` parties (`n == 0` is a no-op). |
| `phaser_arrive(&mut p)` | `Result[ArrivalOutcome, Str]` | Record one arrival without waiting. |
| `phaser_arrive_and_await(&mut p)` | `Result[ArrivalOutcome, Str]` | Arrive and model `arriveAndAwaitAdvance`. |
| `phaser_arrive_and_deregister(&mut p)` | `Result[ArrivalOutcome, Str]` | Arrive and remove the party. |
| `phaser_waiter_released(p, joined_phase)` | `Bool` | True once the joined phase has passed or the phaser terminated. |
| `phaser_set_hook(&mut p, kind, param)` | `Result[Int, Str]` | Select the `onAdvance`-style hook. |
| `phaser_arrive_tiered(&mut child, &mut parent)` | `Result[TierOutcome, Str]` | Child arrival with parent propagation. |
| `phaser_complete_phase(&mut p, max_arrivals)` | `Result[Int, Str]` | Drive one phase completion within an arrival budget. |
| `phaser_run_to_termination(&mut p, max_arrivals)` | `Result[Int, Str]` | Drive phases to termination within a total budget. |
| `phaser_hook_default(phase, parties)` | `Int` | Terminate when no party remains (Java default). |
| `phaser_hook_until_phase(phase, parties, limit)` | `Int` | Terminate after `limit` completed phases. |
| `phaser_hook_always(phase, parties)` | `Int` | Terminate on the first completion. |
| `phaser_hook_never(phase, parties)` | `Int` | Never terminate. |
| `phaser_hook_eval(kind, param, phase, parties)` | `Int` | Dispatch a hook by kind (explicit case chain). |
| `phaser_check_invariant(p)` | `Bool` | Structural invariant check (see SPEC.md). |
| `phaser_state_str(p)` | `Str` | `phase=P parties=R arrived=A unarrived=U` snapshot. |

Accessors (all read-only, `O(1)`): `phaser_handle`,
`phaser_parent`, `phaser_is_child`, `phaser_child_count`,
`phaser_parties`, `phaser_arrived`, `phaser_unarrived`, `phaser_phase`,
`phaser_is_terminated`, `phaser_last_phase`, `phaser_hook_kind`,
`phaser_hook_param`, `phaser_arrivals_total`,
`phaser_registration_total`, `phaser_deregistration_total`,
`phaser_advance_total`, `phaser_last_phase_parties`.

`ArrivalOutcome` (the `Ok` payload of every arrival function):

| Field | Type | Meaning |
|---|---|---|
| `phase` | `Int` | Phase the arrival joined (the completed phase when `advanced`). |
| `new_phase` | `Int` | Phase counter after the call. |
| `advanced` | `Bool` | This arrival completed the phase. |
| `terminated` | `Bool` | The completion terminated the phaser. |
| `released` | `Bool` | The joined phase is already complete or the phaser terminated. |
| `parties` | `Int` | Registered parties after the call. |
| `arrived` | `Int` | Arrivals recorded in the new phase after the call. |
| `unarrived` | `Int` | `parties - arrived` after the call. |

`TierOutcome` (the `Ok` payload of `phaser_arrive_tiered`):

| Field | Type | Meaning |
|---|---|---|
| `child_advanced` | `Bool` | The child completed a phase. |
| `child_terminated` | `Bool` | The child terminated on that completion. |
| `parent_advanced` | `Bool` | The propagated arrival completed a parent phase. |
| `parent_terminated` | `Bool` | The parent terminated on that completion. |
| `parent_parties` | `Int` | Parent party count after the call. |
| `parent_phase` | `Int` | Parent phase after the call. |

Constants: `PHASER_MAX_PARTIES` (65535), `PHASER_MAX_ARRIVALS` (1000000),
`PHASER_HOOK_DEFAULT` / `PHASER_HOOK_UNTIL_PHASE` / `PHASER_HOOK_ALWAYS` /
`PHASER_HOOK_NEVER`, `PHASER_CONTINUE` (0) / `PHASER_TERMINATE` (1).

Every struct field is an internal implementation detail; callers must go
through the free functions.

## Usage

```xi
use xiom.phaser;

match phaser_new(1, 3) {
  Ok(p0) => {
    var p = p0;

    // Two parties arrive; the third completes phase 0.
    phaser_arrive(&mut p);                      // advanced=false, phase=0
    phaser_arrive(&mut p);                      // advanced=false, phase=0
    match phaser_arrive(&mut p) {
      Ok(o) => { /* o.advanced && o.released; o.new_phase == 1 */ },
      Err(_) => { /* "phaser: terminated" or "phaser: no registered parties" */ },
    }
  },
  Err(_) => { /* "phaser: parties must be >= 0" */ },
}
```

A backend models `arriveAndAwaitAdvance` as:

```xi
// Non-blocking core: record the arrival, then park until released.
match phaser_arrive_and_await(&mut p) {
  Ok(o) => {
    if !o.released {
      // park the caller; resume it when the predicate turns true:
      //   phaser_waiter_released(&p, o.phase)
    }
  },
  Err(_) => { /* terminated or no parties */ },
}
```

Termination after a fixed number of phases:

```xi
var p = ...;                                  // phaser with N parties
phaser_set_hook(&mut p, PHASER_HOOK_UNTIL_PHASE, 4);   // run 4 phases
let arrivals = phaser_run_to_termination(&mut p, 1000);
// Ok(arrivals) once terminated; "phaser: arrival limit reached" otherwise
```

Tiered phasers:

```xi
var root = ...;                                        // parent
match phaser_new_child(&mut root, 2, 1) {              // one child credit
  Ok(c0) => {
    var child = c0;
    // Every child phase advance contributes one arrival to the parent:
    phaser_arrive_tiered(&mut child, &mut root);
  },
  Err(_) => { /* "phaser: terminated" / bad handle or party count */ },
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom-phaser
```

Expected: the namespaced module passes the section-4 namespace rule, 24
`[PASS]` lines, and a final `port: PASS (passed=24 failed=0 program_exit=0
exit=0)`.

## Limitations

- **No threads, atomics, or locks.** This is a deterministic semantic model,
  not a synchronisation primitive. A concurrent backend must serialise every
  transition and implement the actual parking/wakeup; the library does not
  make any operation atomic.
- **Awaiting is a predicate, not a park loop.** `phaser_arrive_and_await`
  records the arrival and reports `released`; a backend loops on
  `phaser_waiter_released` (with its own blocking/timeout policy).
- **Termination clears the party count.** Java encodes termination as a
  negative phase and may keep the registered count; this model normalizes
  the final state to `terminated` + `last_phase` + zero parties.
- **No phase-number wrap.** Java wraps phases at `Integer.MAX_VALUE`; this
  model keeps a monotonically increasing `Int` phase counter.
- **No `forceTermination`.** Termination is hook-driven (use
  `PHASER_HOOK_ALWAYS` or a bounded driver for one-shot use).
- **Tiered children are static.** A child is created with
  `phaser_new_child` and carries one parent credit; a subset of Java's
  dynamic child (de)registration is modelled (terminal child advance
  deregisters the credit). A child always has at least one party here.
- **Errors leave the state unchanged.** Unlike Java's negative-return
  convention, terminated operations return stable `phaser: ` errors.
- Not thread-safe: values follow ordinary XIOM move/borrow rules.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
