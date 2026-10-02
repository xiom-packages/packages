# xiom.phaser -- specification

> Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
> SPDX-License-Identifier: MIT OR Apache-2.0

Package `xiom.phaser` 0.1.0, module `xiom.phaser`. Category `concurrent`.
Platform dependency: `xiom.std`. No FFI, no threads, no atomics, no clock,
no I/O.

## 1. Scope

A multi-party phaser in the sense of `java.util.concurrent.Phaser`: a
reusable synchronization point whose **party set may change over time**.
The module specifies the semantics as a pure state machine; a backend
(thread scheduler, event loop, atomics layer) owns serialization and
blocking. This document is the normative reference for the behaviours the
conformance suite (24 checks) pins.

## 2. State model

```
Phaser {
  handle: Int;                  // caller identity, >= 0
  parent: Int;                  // parent handle, -1 for a root
  parties: Int;                 // registered party credits, 0 .. 65535
  arrived: Int;                 // parties arrived in the current phase
  phase: Int;                   // completed phases, 0-based
  terminated: Bool;
  hook: Int;                    // PHASER_HOOK_* kind
  hook_param: Int;              // kind parameter
  children: Int;                // registered child phasers (1 credit each)
  arrivals_total: Int;          // successful arrivals
  registrations_total: Int;     // parties added by register/bulk_register
  deregistrations_total: Int;   // parties removed by arrive_and_deregister
  advances_total: Int;          // completed phases (== phase)
  last_phase_parties: Int;      // completing credits of the last phase, -1 before
}
```

Derived: `unarrived = parties - arrived`.

The encoding is equivalent to Java's packed state
(`unarrived | parties << 16 | phase << 32 | termination`); Java stores
`unarrived`, this model stores `arrived` and derives `unarrived`.

## 3. Construction

`phaser_new(handle, parties)`:

1. `handle < 0` -> Err `phaser: handle must be >= 0`.
2. `parties < 0` -> Err `phaser: parties must be >= 0`.
3. `parties > 65535` -> Err `phaser: parties limit exceeded`.
4. Else Ok: phase 0, `arrived = 0`, default hook, no parent, all counters 0,
   `last_phase_parties = -1`.

A zero-party root is valid and inert: it never advances until parties are
registered (Java `new Phaser(0)`).

`phaser_new_child(parent, handle, parties)`:

1. `parent.terminated` -> Err `phaser: terminated`.
2. `handle < 0` -> Err `phaser: handle must be >= 0`.
3. `handle == parent.handle` -> Err `phaser: child handle must differ from parent`.
4. `parties < 1` -> Err `phaser: child parties must be >= 1`.
5. `parties > 65535` or `parent.parties + 1 > 65535` -> Err `phaser: parties limit exceeded`.
6. Else the parent gains one party credit (`parties += 1`,
   `children += 1`) and the child is Ok with `parent = parent.handle`.

## 4. Registration

`phaser_register(p)`: adds exactly one unarrived party.
`phaser_bulk_register(p, n)`: adds `n` unarrived parties; `n == 0` is a
no-op returning the current count.

1. `n < 0` (bulk only) -> Err `phaser: count must be >= 0`.
2. `p.terminated` -> Err `phaser: terminated`.
3. Adding would exceed 65535 -> Err `phaser: parties limit exceeded`.
4. Else `parties += n`, `registrations_total += n`, Ok(new party count).

A registration during an active phase increases `parties` only: the new
party must still arrive before the phase can complete.

## 5. Arrival transitions

Let `P = parties`, `A = arrived`, `U = P - A` immediately before the call.

### 5.1 arrive / arrive_and_await

1. terminated -> Err `phaser: terminated`.
2. `P < 1` -> Err `phaser: no registered parties`.
3. Record: `A += 1`, `arrivals_total += 1`.
4. If `U == 1` (this is the last unarrived party): complete the phase via
   the advance rule with `phase_parties = P`, `hook_parties = P`.
5. Else Ok outcome with `advanced = false`, `released = false`,
   `phase = new_phase = p.phase`, and the post-call counts.

`phaser_arrive_and_await` performs the identical transition. Its
`released` flag means "the joined phase is complete or the phaser
terminated"; when false, a backend parks the caller and resumes it when
`phaser_waiter_released(p, outcome.phase)` is true.

### 5.2 arrive_and_deregister

1. terminated -> Err `phaser: terminated`.
2. `P < 1` -> Err `phaser: no registered parties`.
3. `arrivals_total += 1`, `deregistrations_total += 1`.
4. If `U == 1`: complete the phase via the advance rule with
   `phase_parties = P`, `hook_parties = P - 1` (the hook observes the
   reduced count, exactly Java `doArrive(ONE_DEREGISTER)`).
5. Else `parties = P - 1`; `arrived` is unchanged (the party both arrived
   and left, so the arrived count is unchanged, as in Java); if
   `children > parties` it is clamped to `parties`. Ok outcome with
   `advanced = false`, `released = false`.

### 5.3 Advance rule (phase completion)

On completion of phase `c`:

1. `phase = c + 1`, `advances_total += 1`, `arrived = 0`.
2. `last_phase_parties = phase_parties`.
3. Evaluate the hook with `(c, hook_parties)`.
4. Terminate: `terminated = true`, `parties = 0`, `children = 0`; outcome
   `advanced = true`, `terminated = true`, `released = true`, counts 0.
5. Continue: `parties = hook_parties`, `arrived = 0`; if `hook_parties == 0`
   also `children = 0` (an inert zero-party phaser; possible only under
   `PHASER_HOOK_NEVER`); outcome `advanced = true`,
   `terminated = false`, `released = true`.

### 5.4 Release predicate

`phaser_waiter_released(p, joined_phase)` is true when `joined_phase < 0`,
or `p.terminated`, or `p.phase > joined_phase`.

## 6. Hooks

Hooks are concrete specializations returning `PHASER_CONTINUE` (0) or
`PHASER_TERMINATE` (1); `phaser_hook_eval(kind, param, phase, parties)`
dispatches with an explicit case chain and falls back to the default hook
for unknown kinds.

| Kind | Constant | Rule |
|---|---|---|
| 0 | `PHASER_HOOK_DEFAULT` | terminate iff `parties <= 0` |
| 1 | `PHASER_HOOK_UNTIL_PHASE` | terminate iff `parties <= 0` or `phase + 1 >= param` |
| 2 | `PHASER_HOOK_ALWAYS` | always terminate |
| 3 | `PHASER_HOOK_NEVER` | never terminate |

`phaser_set_hook(p, kind, param)`:

1. terminated -> Err `phaser: terminated`.
2. `kind < 0` or `kind > 3` -> Err `phaser: invalid hook kind`.
3. `kind == PHASER_HOOK_UNTIL_PHASE` and `param < 1` ->
   Err `phaser: hook limit must be >= 1`.
4. Else store and Ok(kind).

## 7. Termination semantics

Termination happens only through the advance rule (rule 5.3.4), so a
terminated phaser always has completed at least one phase, zero parties,
zero arrivals, zero children and `last_phase_parties >= 1`.

- `phaser_is_terminated` reports the flag.
- `phaser_last_phase` returns the final phase number when terminated,
  `-1` while active.
- Once terminated, `phaser_arrive`, `phaser_arrive_and_await`,
  `phaser_arrive_and_deregister`, `phaser_register`, `phaser_bulk_register`
  and `phaser_set_hook` fail with Err `phaser: terminated`; the bounded
  drivers return Ok(0) (already terminated).
- Waiters of the final phase are released: `phaser_waiter_released`
  returns true for any joined phase once terminated.

## 8. Tiered phasers

`phaser_new_child` registers one party credit on the parent. For a linked
pair `(child, parent)` with `child.parent == parent.handle`:

`phaser_arrive_tiered(child, parent)`:

1. `child.parent != parent.handle` -> Err `phaser: not a child`.
2. `child.terminated` -> Err `phaser: terminated`.
3. `parent.terminated` -> Err `phaser: parent terminated`.
4. `child.parties < 1` -> Err `phaser: no registered parties`.
5. `parent.parties < 1` -> Err `phaser: parent has no registered parties`.
6. Perform the plain child arrival:
   - not advanced: Ok with child flags false and the untouched parent
     counts.
   - advanced and terminated: perform a parent **arrive-and-deregister**
     (the child's parent credit is removed; the parent hook sees the
     reduced count). If the parent did not terminate, `parent.children -= 1`
     (guarding zero).
   - advanced and not terminated: perform a plain parent arrival.
7. Ok `TierOutcome` describing both transitions.

Every Err returns before any state change.

## 9. Bounded progression (deadlock safety)

`phaser_complete_phase(p, max_arrivals)`:

1. `max_arrivals < 0` -> Err `phaser: limit must be >= 0`.
2. `max_arrivals > 1000000` -> Err `phaser: limit exceeds maximum`.
3. terminated -> Ok(0).
4. `parties < 1` -> Err `phaser: no registered parties`.
5. Loop: record plain arrivals; if the phase counter moves, Ok(used);
   if the phaser terminates, Ok(used); if `used == max_arrivals` before
   either, Err `phaser: arrival limit reached`.

`phaser_run_to_termination(p, max_arrivals)` applies the same limit checks
(then Ok(0) on terminated) and repeatedly drives complete phases with the
remaining budget. A phaser that cannot terminate fails with
`phaser: arrival limit reached`; `PHASER_MAX_ARRIVALS` (1000000) is the
absolute per-call cap. Both drivers are total and bounded:
`O(max_arrivals)`.

## 10. Errors

All error strings are stable, prefixed `phaser: `, and leave the state
completely unchanged:

| Message | Raised by |
|---|---|
| `phaser: handle must be >= 0` | new, new_child |
| `phaser: parties must be >= 0` | new |
| `phaser: parties limit exceeded` | new, new_child, register, bulk_register |
| `phaser: child handle must differ from parent` | new_child |
| `phaser: child parties must be >= 1` | new_child |
| `phaser: count must be >= 0` | bulk_register |
| `phaser: terminated` | register, bulk_register, arrive, arrive_and_await, arrive_and_deregister, set_hook, new_child (terminated parent), arrive_tiered |
| `phaser: no registered parties` | arrive, arrive_and_await, arrive_and_deregister, complete_phase, run_to_termination, arrive_tiered |
| `phaser: parent terminated` | arrive_tiered |
| `phaser: parent has no registered parties` | arrive_tiered |
| `phaser: not a child` | arrive_tiered |
| `phaser: invalid hook kind` | set_hook |
| `phaser: hook limit must be >= 1` | set_hook |
| `phaser: limit must be >= 0` | complete_phase, run_to_termination |
| `phaser: limit exceeds maximum` | complete_phase, run_to_termination |
| `phaser: arrival limit reached` | complete_phase, run_to_termination |

## 11. Invariant

`phaser_check_invariant(p)` is true exactly when:

- `handle >= 0`; `parent >= -1` and `parent != handle`;
- `0 <= parties <= 65535`; `0 <= arrived <= parties`; if `parties > 0` then
  `arrived < parties`;
- `phase == advances_total >= 0`;
- `last_phase_parties == -1` iff `phase == 0`, and `>= 1` when `phase > 0`;
- `0 <= children`; `children == 0` when `parties == 0`;
  `children <= parties`;
- `hook` is a `PHASER_HOOK_*` kind; `PHASER_HOOK_UNTIL_PHASE` requires
  `hook_param >= 1`;
- counters are non-negative; `arrivals_total >= arrived` and
  `arrivals_total >= phase`;
- if terminated: `parties == 0`, `arrived == 0`, `children == 0`,
  `phase >= 1`, `last_phase_parties >= 1`.

## 12. Compatibility notes (vs java.util.concurrent.Phaser)

Same: advance condition (`unarrived == 0`), deregistration accounting
(including hook-visible reduced parties and the no-op arrived count on a
non-completing deregistration), child credit registration, one parent
arrival per child advance, terminal child deregistration, default hook
`parties == 0`, phase-0 start, 65535 party cap, `waiter_released`
monotonicity.

Deliberate differences: no blocking APIs (awaiting is the
`phaser_waiter_released` predicate); errors instead of negative phase
returns on terminated operations; termination normalizes state to zero
parties and exposes `last_phase` instead of a negative phase number; no
phase wrap at `Integer.MAX_VALUE`; no `forceTermination`; no interruptible
or timed waits; children are created only with `parties >= 1` and carry a
static credit (no dynamic child re-registration).

## 13. Test coverage map

24 checks in `tests/test_conformance.xi`:

| Tests | Covered behaviour |
|---|---|
| t1-t2 | construction, defaults, validation, party cap |
| t3 | register / bulk_register, caps, counters |
| t4, t6 | arrival outcomes, phase completion, new phase |
| t5 | zero-party refusal, driver errors |
| t7 | waiter release across phases |
| t8-t9 | arrive_and_deregister accounting, completion, termination |
| t10 | hook specializations and explicit dispatch |
| t11 | set_hook validation and reflection |
| t12-t13 | until_phase / never termination behaviour |
| t14-t15 | final termination state and last-phase metadata |
| t16-t18 | bounded drivers, budget errors, deadlock safety |
| t19-t21 | tiered registration, propagation, terminal deregistration |
| t22 | tiering validation errors |
| t23 | structural invariant under mixed operations |
| t24 | state snapshot rendering and accessors |

## 14. Complexity

Construction, registration, arrival, await predicate, hook evaluation,
accessors and the invariant check are `O(1)`. The bounded drivers are
`O(max_arrivals)`.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
