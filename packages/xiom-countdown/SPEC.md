# xiom.countdown -- specification

Pure deterministic countdown latches over explicit integer ticks.
Module: `xiom.countdown` (single module). Version 0.1.0.

This document is the contract the implementation and the conformance suite
are pinned against. Section 8 lists the error catalog; every rule below
matches `src/countdown.xi` exactly.

---

## 1. Scope and non-goals

The registry holds integer-handled **countdown latches** and **waiters** that
observe them. All time is simulated: `countdown_advance` is the only way a
latch moves.

- **No clock.** Nothing reads wall time, sleeps or schedules. Ticks are
  abstract; mapping them to milliseconds is the caller's job.
- **No threads, no FFI.** Pure XIOM, one process-wide registry, not
  thread-safe. The caller synchronizes if the registry is shared.
- **No allocation after setup.** Both pools are pre-sized; freed slots are
  recycled through free lists.
- **No wall-clock or real-time guarantee of any kind.** "Expires at tick T"
  means exactly that inside the simulation.

## 2. Data model

Storage is **parallel primitive vectors only** (v0.62.1 cannot write
`Vec[StructType]` elements), never nested structures.

Countdown pool, indexed by pool slot (256 slots):

| State | Type | Meaning |
|-------|------|---------|
| `_cd_initial` | `Vec[Int]` | stored one-shot duration / repeating period |
| `_cd_remaining` | `Vec[Int]` | ticks left before the next expiry |
| `_cd_elapsed` | `Vec[Int]` | accepted ticks since the last arm |
| `_cd_period` | `Vec[Int]` | repeating period; 0 = one-shot |
| `_cd_fires` | `Vec[Int]` | monotonic expiry counter (the waiter generation) |
| `_cd_armed` | `Vec[Int]` | 1 while the latch accepts ticks |
| `_cd_alive` | `Vec[Int]` | 1 = live handle |
| `_cd_next` | `Vec[Int]` | free-list link over destroyed slots |

Waiter pool, indexed by waiter slot (512 slots): `_cdw_owner` (countdown slot
or -1), `_cdw_id` (caller waiter id), `_cdw_since` (generation at
registration), `_cdw_alive`, `_cdw_next`.

Registry counters: `_cd_pool_count` (high-water of used countdown slots),
`_cd_free_head`, `_cd_live` (live countdowns), `_cdw_count`, `_cdw_free_head`.
Ready flag: `_cd_ready`; the first public call runs `countdown_clear()`-style
setup lazily.

## 3. Handles, capacity and clear

- A **handle** is the countdown's pool slot index: a non-negative Int.
  `countdown_is_valid(handle)` is true iff the slot is currently live.
- At most **256** simultaneous countdowns. A create on a full pool raises
  code 7. A destroyed slot is pushed on a LIFO free list and reused by the
  next create, so handles are recycled: after `countdown_destroy(h)` a later
  create can return `h` again, now naming a different latch. Destroyed
  handles are invalid in every operation (code 5) until reused.
- At most **512** simultaneous waiters across all countdowns; a watch on a
  full waiter pool raises code 10.
- `countdown_clear()` drops every countdown and waiter, resets both free
  lists and both high-water counts to 0, so the next create returns handle 0
  again. It returns nothing and cannot fail.

## 4. Tick semantics

`countdown_advance(handle, ticks)` validates in this order and returns
`Result[Int, CountdownError]`:

1. unknown handle -> code 5 (value = ticks), no state change;
2. `ticks < 0` -> code 3 (value = ticks), no state change;
3. `ticks == 0` -> `Ok(0)`, a full no-op for any countdown state (armed or
   disarmed), `elapsed` unchanged;
4. one-shot with `armed == 0` -> code 6 (value = ticks), no state change;
5. `ticks > _CD_MAX - elapsed` -> code 4 (value = ticks), no state change;
6. otherwise the accepted ticks are applied as in 4.1/4.2.

`_CD_MAX = 2^62 - 1 = 4611686018427387903`. Accepted ticks never raise
`elapsed` past it; every create/reset duration is also capped at it. All
internal arithmetic is written so intermediates stay below 2^63 (see 4.2).

`elapsed` counts **accepted** ticks: it includes the overshoot of an expiring
advance and never decreases except at reset/re-arm. `next_expiry()`
(= `elapsed + remaining`) is the tick of the next expiry relative to the
current arm.

### 4.1 One-shot expiry

Let `r = remaining`, `t = ticks > 0`.

- `t < r`: `remaining = r - t`, `elapsed += t`, returns `Ok(0)`.
- `t >= r`: `remaining = 0`, `elapsed += t`, `armed = 0`,
  `fires += 1`, returns `Ok(1)`.

A one-shot fires exactly on the advance that reaches its duration
(`t == r` included); the overshoot of a larger advance is absorbed into
`elapsed` and creates no further expiries. Once disarmed, advances of
positive ticks fail with code 6 until `countdown_rearm`/`countdown_reset`.

### 4.2 Repeating expiry

Let `r = remaining (1..period)`, `p = period`, `t = ticks > 0`.

- `t < r`: `remaining = r - t`, `elapsed += t`, returns `Ok(0)`.
- `t >= r`: `k = 1 + (t - r) / p` (floor division; both operands are
  non-negative), `remaining = r + k*p - t` (always in `1..p`),
  `elapsed += t`, `fires += k`, returns `Ok(k)`.

Worked examples: `p = 3`, `r = 3`, `t = 7` -> `k = 2`, `remaining = 2`;
`p = 3`, `r = 3`, `t = 1_000_000` -> `k = 333333`, `remaining = 2`;
`p = 5`, `r = 5`, `t = 15` -> `k = 3`, `remaining = 5`.

Overflow safety: `k*p <= p + (t - r) <= p + t <= 2*_CD_MAX = 2^63 - 2`, so
`r + k*p` and every other intermediate fit in Int; no wrap can occur.
A repeating countdown never disarms; `armed` stays 1.

## 5. Expiry ordering and counters

- `countdown_fire_count` is **monotonic**: every expiry (one-shot or
  repeating) increments it, and neither reset nor re-arm clears it. It is
  also the waiter **generation**.
- A single repeating advance records every crossed boundary: expiries are
  conceptually ordered by their tick, but the only observable is the count
  `k` returned. There are no callbacks.
- Across countdowns there is no global ordering: advances are per handle and
  the caller drives them; the registry keeps no shared clock.
- `countdown_is_expired` is `fire_count > 0`: true once the latch has
  expired at least once, and it stays true across re-arms.

## 6. Reset and re-arm

`countdown_reset(handle, ticks)` validates handle (5), `ticks <= 0` (1),
`ticks > _CD_MAX` (2), then:

- one-shot: `initial = ticks`;
- repeating: `period = ticks`;
- `remaining = ticks`, `elapsed = 0`, `armed = 1`;
- `fires` (generation) and all registered waiters are **preserved**;
- returns `Ok(ticks)`.

`countdown_rearm(handle)` validates the handle (5) and applies the same
effects using the stored duration: `initial` for a one-shot, `period` for a
repeating countdown; returns `Ok(duration)`.

Consequences, pinned by the suite:

- Re-arming a repeating countdown after `reset(h, 3)` uses 3, not the period
  it was created with.
- A waiter registered before a re-arm remains registered and is released by
  the next expiry (its generation is untouched by re-arm).
- Resetting a fired one-shot keeps `fire_count` (and `is_expired`) intact.

## 7. Fan-out waiting

Any number of waiters observe one latch; waiter ids are scoped per
countdown (the same id may be registered on different countdowns) and may be
zero or negative.

- `countdown_watch(h, w)` returns `Ok(generation)` with
  `generation = fire_count(h)` at registration. A duplicate id on the same
  countdown is code 9.
- A waiter is **released** iff `fire_count(h) > generation`. One expiry
  therefore flips every waiter registered before it; waiters registered
  afterwards start at the new generation and are not released by it (no
  history is replayed).
- `countdown_wait_ack(h, w)` returns `Ok(was_released)` and sets the waiter's
  generation to the current `fire_count`, consuming any pending release;
  it returns `Ok(false)` when nothing was pending. Ack before release is a
  no-op returning `Ok(false)`.
- `countdown_unwatch(h, w)` removes the waiter and returns
  `Ok(remaining_waiters_on_h)`. `countdown_wait_released` and
  `countdown_wait_ack` on an unregistered waiter raise code 8.
- `countdown_waiter_count`, `countdown_released_waiter_count` and
  `countdown_waiter_at(h, i)` count/enumerate waiters of one latch.
  `waiter_at` walks **ascending waiter-slot order**; slot reuse after a
  removal can make that differ from registration order, so the enumeration
  order is only promised while no waiter is added or removed.
- `countdown_destroy(h)` unregisters every waiter of `h` first (returning
  `Ok(removed_waiters)`), then frees the handle slot.

## 8. Error catalog

All fallible operations return `Result[T, CountdownError]` where

```
CountdownError = { code: Int; handle: Int; value: Int; }
```

`handle` carries the offending countdown handle, `value` the offending
argument (ticks, waiter id or waiter index); unused fields are -1.

| Code | Message | Raised by | Carried fields |
|------|---------|-----------|----------------|
| 1 | `countdown: ticks must be positive` | create/create_repeating/reset, ticks <= 0 | handle = -1 (create) or handle, value = ticks |
| 2 | `countdown: ticks exceed maximum` | create/create_repeating/reset, ticks > 2^62-1 | handle = -1 (create) or handle, value = ticks |
| 3 | `countdown: negative advance` | advance, ticks < 0 | handle = handle, value = ticks |
| 4 | `countdown: elapsed ticks would overflow` | advance, ticks > 2^62-1 - elapsed | handle = handle, value = ticks |
| 5 | `countdown: unknown handle` | any operation on a non-live handle | handle = handle, value = argument or -1 |
| 6 | `countdown: countdown is disarmed` | advance with ticks > 0 on a fired one-shot | handle = handle, value = ticks |
| 7 | `countdown: countdown capacity is full` | create, 256 live countdowns | handle = value = -1 |
| 8 | `countdown: unknown waiter` | unwatch/wait_released/wait_ack, no such waiter | handle = handle, value = waiter_id |
| 9 | `countdown: duplicate waiter` | watch, waiter_id already on this countdown | handle = handle, value = waiter_id |
| 10 | `countdown: waiter capacity is full` | watch, 512 live waiters | handle = handle, value = waiter_id |
| 11 | `countdown: waiter index out of range` | waiter_at, i outside 0..count-1 | handle = handle, value = i |

Codes outside the catalog map to `countdown: unknown error` in
`countdown_error_message`.

## 9. API summary and complexity

| Function | Returns |
|----------|---------|
| `countdown_create(ticks)` | `Ok(handle)` / Err 1, 2, 7 |
| `countdown_create_repeating(period)` | `Ok(handle)` / Err 1, 2, 7 |
| `countdown_destroy(handle)` | `Ok(removed_waiters)` / Err 5 |
| `countdown_advance(handle, ticks)` | `Ok(expiries)` / Err 3, 4, 5, 6 |
| `countdown_reset(handle, ticks)` | `Ok(ticks)` / Err 1, 2, 5 |
| `countdown_rearm(handle)` | `Ok(ticks)` / Err 5 |
| `countdown_remaining/elapsed/initial/period/fire_count/next_expiry(handle)` | `Ok(Int)` / Err 5 |
| `countdown_is_armed/is_expired(handle)` | `Ok(Bool)` / Err 5 |
| `countdown_watch(handle, waiter_id)` | `Ok(generation)` / Err 5, 9, 10 |
| `countdown_unwatch(handle, waiter_id)` | `Ok(remaining_waiters)` / Err 5, 8 |
| `countdown_wait_released/wait_ack(handle, waiter_id)` | `Ok(Bool)` / Err 5, 8 |
| `countdown_waiter_count/released_waiter_count(handle)` | `Ok(Int)` / Err 5 |
| `countdown_waiter_at(handle, i)` | `Ok(waiter_id)` / Err 5, 11 |
| `countdown_is_valid(handle)` | `Bool` |
| `countdown_clear()` | -- |
| `countdown_count()` | `Int` |
| `countdown_capacity()`, `countdown_waiter_capacity()` | `Int` (256, 512) |
| `countdown_waiter_total()` | `Int` |
| `countdown_error_message(code)` | `Str` |

Complexity: create/reset/rearm/advance and all scalar queries are O(1)
amortized (create may pay O(capacity) once on first use). Every waiter
operation (`watch`, `unwatch`, `wait_*`, counts, `waiter_at`, `destroy`) is
O(waiters). `countdown_clear()` is O(capacity).

## 10. Conformance

`tests/test_conformance.xi` (22 checks) pins this specification: creation
defaults and bounds; one-shot exact expiry, overshoot, disarm and re-arm;
repeating boundaries (including a 1,000,000-tick advance and an aligned
multiple); the 2^62-1 overflow boundary; handle validity, destruction, slot
reuse and the 256-handle cap; destroy dropping owned waiters; fan-out
release/ack/unwatch, late registration, per-countdown waiter ids,
enumeration and the 512-waiter cap; reset rules preserving generation and
waiters; zero/negative advance; a replayed determinism fixture; and the
error messages. Run it with:

```powershell
& .\scripts\port.ps1 -Package xiom.countdown
```

## 11. v0.62.1 implementation notes

Constraints the toolchain imposes on this module (and how it copes):

- No `Vec[StructType]` elements: both pools are parallel `Vec[Int]` fields
  with explicit free-list links.
- No methods, no `Vec[fn]` dispatch, no callbacks: free functions only.
- No `&mut Int` out-parameters: every operation returns a value or a
  `Result`.
- No bitwise/shift arithmetic: only `+ - * / %` and comparisons; floor
  division of non-negative operands is used deliberately in the repeating
  formula (negative operands are rejected before any division).
- Every `Vec[Int]` read goes through a typed local; `Ok`/`Err` are
  constructed only in the leaf helpers `_cd_ok`, `_cd_err`, `_cd_ok_bool`,
  `_cd_err_bool`.
