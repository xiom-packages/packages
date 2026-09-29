# xiom.countdown

> **Status:** `incubating` -- conformance-tested (22/22); not yet published on the XIOM registry.
> **Scope:** one dependency-free module of pure, deterministic countdown
> latches: one-shot and repeating expiry, remaining/elapsed/reset/re-arm
> queries and fan-out waiting, all driven by explicit integer ticks.
> **Deps:** `xiom.std` only (the library module imports nothing; tests use
> `xiom.test`, `xiom.io` and `xiom.string.compare`).

## What it is

`xiom.countdown` is a small registry of integer-handled **countdown latches**
over abstract integer ticks. It owns no clock: `countdown_advance(handle,
ticks)` is the only way simulated time moves, and every counter it reports is
a pure function of the calls made.

- **One-shot countdown** -- created with `countdown_create(ticks)`; fires
  once, exactly on the advance that reaches its duration, then stays disarmed
  until `countdown_rearm`/`countdown_reset`.
- **Repeating countdown** -- created with `countdown_create_repeating(period)`;
  fires on every period boundary, auto-re-arms, and records every expiry in a
  monotonic fire counter. A single large advance records one expiry per
  crossed boundary.
- **Remaining/elapsed queries** -- `countdown_remaining`, `countdown_elapsed`,
  `countdown_next_expiry`, `countdown_is_armed`, `countdown_is_expired`, plus
  the stored `countdown_initial`/`countdown_period`.
- **Reset/re-arm** -- `countdown_reset(handle, ticks)` re-arms with a new
  duration; `countdown_rearm(handle)` re-arms with the stored one. Both clear
  elapsed, preserve the monotonic expiry counter and leave waiters registered.
- **Fan-out waiting** -- any number of waiters observe one latch. A waiter is
  released by the first expiry after it registered; one expiry releases every
  pending waiter at once, and `countdown_wait_ack` re-arms one waiter for the
  next round.
- **Overflow-safe arithmetic** -- accepted ticks never let `elapsed` pass
  2^62 - 1; an advance that would is rejected whole with a typed error.

## What this package is NOT

- **No clocks and no wall-clock promises.** Nothing sleeps, nothing reads
  real time; mapping ticks to milliseconds and waking real threads is the
  caller's job.
- **No threads and no FFI.** The module is pure XIOM; it is not thread-safe
  and one process-wide registry is the whole state.
- **No heap growth at runtime.** Both pools (256 handles, 512 waiters) are
  pre-sized; `countdown_destroy`/`countdown_unwatch` recycle slots.

## API

| Function | Returns | Description |
|---|---|---|
| `countdown_create(ticks)` | `Result[Int, CountdownError]` | `Ok(handle)`: one-shot latch of `ticks` (1..2^62-1). |
| `countdown_create_repeating(period)` | `Result[Int, CountdownError]` | `Ok(handle)`: latch firing every `period` ticks. |
| `countdown_destroy(handle)` | `Result[Int, CountdownError]` | `Ok(removed_waiters)`: release the slot and drop its waiters. |
| `countdown_advance(handle, ticks)` | `Result[Int, CountdownError]` | `Ok(expiries)` recorded by this advance (0, 1 or many). |
| `countdown_reset(handle, ticks)` | `Result[Int, CountdownError]` | `Ok(ticks)`: re-arm with a new duration. |
| `countdown_rearm(handle)` | `Result[Int, CountdownError]` | `Ok(ticks)`: re-arm with the stored duration. |
| `countdown_remaining(handle)` | `Result[Int, CountdownError]` | Ticks left before the next expiry. |
| `countdown_elapsed(handle)` | `Result[Int, CountdownError]` | Accepted ticks since the last arm. |
| `countdown_initial(handle)` | `Result[Int, CountdownError]` | Stored duration (`== period` when repeating). |
| `countdown_period(handle)` | `Result[Int, CountdownError]` | Repeating period, or 0 for one-shot. |
| `countdown_fire_count(handle)` | `Result[Int, CountdownError]` | Monotonic expiry counter since creation. |
| `countdown_next_expiry(handle)` | `Result[Int, CountdownError]` | `elapsed + remaining`: tick of the next expiry. |
| `countdown_is_armed(handle)` | `Result[Bool, CountdownError]` | Whether the latch still accepts ticks. |
| `countdown_is_expired(handle)` | `Result[Bool, CountdownError]` | Whether it expired at least once. |
| `countdown_watch(handle, waiter_id)` | `Result[Int, CountdownError]` | `Ok(generation)`: register a fan-out waiter. |
| `countdown_unwatch(handle, waiter_id)` | `Result[Int, CountdownError]` | `Ok(remaining_waiters)`. |
| `countdown_wait_released(handle, waiter_id)` | `Result[Bool, CountdownError]` | Expiry observed since (re-)registration. |
| `countdown_wait_ack(handle, waiter_id)` | `Result[Bool, CountdownError]` | `Ok(was_released)`: consume the release. |
| `countdown_waiter_count(handle)` | `Result[Int, CountdownError]` | Waiters registered on one latch. |
| `countdown_released_waiter_count(handle)` | `Result[Int, CountdownError]` | Waiters currently observing a release. |
| `countdown_waiter_at(handle, i)` | `Result[Int, CountdownError]` | `Ok(waiter_id)` at slot-order position `i`. |
| `countdown_is_valid(handle)` | `Bool` | Whether the handle names a live latch. |
| `countdown_clear()` | -- | Full registry reset (all latches and waiters). |
| `countdown_count()` | `Int` | Live latches. |
| `countdown_capacity()` | `Int` | 256 simultaneous latches. |
| `countdown_waiter_total()` | `Int` | Waiters across all latches. |
| `countdown_waiter_capacity()` | `Int` | 512 simultaneous waiters. |
| `countdown_error_message(code)` | `Str` | Pinned message for an error code. |

Errors are typed values, not strings:

```xiom
let r = countdown_advance(0, 3);
// r.is_ok == false
// r.error.code == 6        ("countdown: countdown is disarmed")
// r.error.handle == 0, r.error.value == 3
countdown_error_message(6); // "countdown: countdown is disarmed"
```

## Quick start

```xiom
use xiom.countdown;

let rc = countdown_create(5);          // one-shot latch, ticks = 5
if rc.is_ok {
  let c: Int = rc.value;               // handle 0
  countdown_advance(c, 3);             // Ok(0): 2 ticks left
  countdown_remaining(c);              // Ok(2)
  countdown_advance(c, 2);             // Ok(1): expires exactly at 5
  countdown_is_armed(c);               // Ok(false)
  countdown_rearm(c);                  // Ok(5): armed again
}

let rp = countdown_create_repeating(4);
if rp.is_ok {
  let p: Int = rp.value;
  countdown_advance(p, 10);            // Ok(2): boundaries at 4 and 8
  countdown_fire_count(p);             // Ok(2)
  countdown_remaining(p);              // Ok(2): next expiry at 12
}

// Fan-out: one latch, many waiters, one release.
let lr = countdown_create(10);
if lr.is_ok {
  let h: Int = lr.value;
  countdown_watch(h, 100);             // Ok(0): generation 0
  countdown_watch(h, 101);             // Ok(0)
  countdown_advance(h, 10);            // Ok(1)
  countdown_wait_released(h, 100);     // Ok(true)
  countdown_wait_released(h, 101);     // Ok(true)
}
```

## Testing

```powershell
& .\scripts\port.ps1 -Package xiom.countdown
```

The suite (`tests/test_conformance.xi`, 22 checks) builds all state in-test
and pins: creation defaults and bounds; one-shot exact expiry, overshoot,
disarm and re-arm; repeating boundaries including a 1,000,000-tick advance
and an exactly-aligned multiple; the 2^62-1 overflow boundary; handle
lifetime, slot reuse and the 256-handle cap; destroy dropping owned waiters;
fan-out release/ack/unwatch with late registration, per-latch waiter ids and
the 512-waiter cap; reset rules that preserve generation and waiters; a
replayed determinism fixture; and the pinned error catalog.

## Install / publish

Consumers (once the package is published to the XIOM registry):

```
xiom pkg install xiom.countdown@0.1.0
```

Maintainers (requires `XIOM_REGISTRY_TOKEN`):

```
xiom pkg publish
```

## Documentation

- `SPEC.md` -- data model, tick and expiry semantics, reset rules, error
  catalog, complexity.
- `src/countdown.xi` -- implementation and per-function contracts.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
