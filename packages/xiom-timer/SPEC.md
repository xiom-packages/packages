# xiom.timer -- specification

Pure deterministic hierarchical timer wheel over integer ticks.
Module: `xiom.timer` (single module). Version 0.1.0.

This document is the contract the implementation and the conformance suite
are pinned against. Section 7 lists the error catalog.

---

## 1. Scope and non-goals

The wheel schedules opaque integer ids to fire after an integer number of
**ticks**, and reports them from `timer_advance`. It is a simulation object:

- **No clock.** Nothing reads wall time; `timer_advance` is the only way the
  clock moves. There are no wall-clock or real-time promises.
- **No threads, no FFI, no sleeps.** The module is pure XIOM.
- **Not thread-safe.** One process-wide wheel; the caller synchronizes.
- **No allocation after setup.** All vectors are pre-sized at configuration;
  entry slots are recycled through a free list.

## 2. Data model

The wheel is process-wide module state. Storage is **parallel primitive
vectors only** (v0.61.3 does not support writing `Vec[StructType]` elements),
never nested structure:

| State | Type | Meaning |
|-------|------|---------|
| `_tw_levels`, `_tw_slots` | `Int` | active geometry |
| `_tw_now` | `Int` | current tick (starts at 0) |
| `_tw_pending` | `Int` | active entries |
| `_tw_cascades` | `Int` | downward re-buckets since configure |
| `_tw_g` | `Vec[Int]` | `_tw_g[L] = slots^L` (L in 0..levels-1) |
| `_tw_head`, `_tw_tail` | `Vec[Int]` | bucket chain head/tail, `-1` = empty |
| `_tw_ids`, `_tw_dl` | `Vec[Int]` | per entry: id, absolute deadline |
| `_tw_lvl`, `_tw_slot`, `_tw_next` | `Vec[Int]` | per entry: bucket level, bucket slot, chain next |
| `_tw_alive` | `Vec[Int]` | per entry: 1 live, 0 free |
| `_tw_fired` | `Vec[Int]` | ids fired by the most recent advance |
| `_tw_free_head` | `Int` | free-list head over released pool slots |

Entry pool and chains:

- The pool has `timer_capacity()` (1024) slots. `timer_insert` takes the
  free-list head when available, else the next never-used slot; when all
  capacity is live it returns the full-pool error.
- Each bucket `(level, slot)` holds a singly linked chain through `_tw_next`;
  insertion appends at the tail (`_tw_tail`), so chains are FIFO.
- A fire or cancel unlinks the entry and releases its slot, which is reused
  by a later insert. Pool storage never grows after `timer_configure`.

Counters: `timer_now`, `timer_pending_count`, `timer_cascade_count`,
`timer_fired_count` are O(1) accessors.

## 3. Geometry and tick semantics

Geometry: `levels` in 1..8, `slots` in 2..1024, and
`slots^levels <= 2^32` (keeps every product exact and bounded).

- Granularity of level L: `g(L) = slots^L`; `g(0) = 1`.
- Maximum delay: `slots^levels - 1` (default 4 x 64: 16777215).
- `timer_configure(levels, slots)` is a full reset: it validates the shape,
  rebuilds `_tw_g`, `_tw_head`/`_tw_tail`, the pre-sized pool and the fired
  output, and sets `now = 0`, all counters to 0. On error nothing changes.
- First use without a configure lazily builds the default 4 x 64 wheel.

### 3.1 Placement (insertion)

For a valid `delay` (1..max) at time `now`:

1. `deadline = now + delay` (absolute tick).
2. **Level**: the lowest L with `delay < g(L+1)`, capped at `levels-1`.
   Equivalently: delays below `slots` go to level 0, then one level per
   further factor of `slots` (64..4095 -> level 1, 4096..262143 -> level 2,
   262144.. -> level 3 with the default geometry). `timer_bucket_level`
   exposes this rule.
3. **Slot**: `(deadline / g(L)) % slots`. The slot is computed from the
   **absolute deadline**, not from the remaining delay, so inserts are
   correctly aligned even when `now` is not a slot boundary.
   `timer_bucket_slot` exposes this rule for the current `now`.

`timer_insert` returns `Ok(level)` so callers and tests can observe the
placement.

### 3.2 Advancing and firing

`timer_advance(ticks)` processes `ticks` single-tick steps (a pending-free
wheel jumps in one step):

1. `now = now + 1`.
2. For each level L from highest to lowest: if `now % g(L) == 0`, the bucket
   `(L, (now / g(L)) % slots)` opens -- see 3.3.
3. The level-0 bucket `(0, now % slots)` is opened and every entry there is
   due: it fires.

An entry fires exactly on its deadline tick: level-0 entries are parked in
`deadline % slots` and the cursor reaches that slot exactly at `deadline`;
cascade entries reach level 0 with remaining delay `r < slots` and fire on
the same schedule. No advance, however large its step count, can fire an
entry early or late: a step-by-step simulation is the specification.

### 3.3 Cascade rules

When bucket `(L, slot)` opens at time `w` (a multiple of `g(L)`), the chain
is detached and each entry is re-processed:

- `r = deadline - now`.
- `r <= 0`: fire (append the id to the fired output, release the slot).
- else `nl = level_for(r)`:
  - `nl < L`: **cascade down**, with `remaining delay` implicitly adjusted to
    `r`; the entry is re-inserted into bucket `(nl, (deadline / g(nl)) % slots)`
    and the cascade counter is bumped. This is the only counted transition.
  - `nl >= L`: the entry's own bucket window has not opened yet (it shares a
    slot residue with a later window); it is parked back into `(L, slot)` in
    chain order. It will be re-processed at the next opening of that bucket,
    which is exactly its own window.

Levels are processed highest first within one tick, so an entry cascaded
down this tick can be cascaded again (or fired) by a lower level's opening in
the same tick. Chains are rebuilt in chain order, so FIFO survives cascades.

**Invariant.** At rest, an entry at level L has remaining delay in
`[g(L), g(L+1))` (level 0: `[0, slots)`), and its bucket opens at or before
its deadline. Early cascades/parks maintain this invariant; an entry is only
ever fired when `deadline <= now`.

## 4. Delays, ids and capacity

- **Delay**: any Int, but valid inserts need `1 <= delay <= timer_max_delay()`.
  Zero, negative and oversized delays are rejected (codes 6 and 7).
- **Id**: any Int (zero and negative are legal handles). Only one active
  entry per id; a duplicate insert is rejected (code 8). After an id fires
  or is cancelled, the id is free again.
- **Capacity**: at most `timer_capacity()` = 1024 simultaneous active
  entries; a further insert is rejected (code 11). Released slots are
  reusable, so capacity does not limit the lifetime insert count.

## 5. Ordering guarantees

- **Same-deadline FIFO within a bucket.** Entries are appended to their
  bucket chain, and every cascade/opening preserves chain order. Two entries
  inserted back-to-back with the same delay share a bucket and fire in
  insertion order; entries that reach one bucket at different times also
  keep the order in which they entered that bucket.
- **Within one tick** the fired output is ordered: entries fired while
  cascading, from the highest level to the lowest, each in chain order; then
  the level-0 bucket in chain order.
- There is **no global insertion-order promise** across different buckets.
  Entries with the same deadline can live at different levels (they were
  inserted at different times with different remaining delays) and are
  ordered by the rule above.
- `timer_fired_id(i)` is a 0-based index into the fired output of the most
  recent `timer_advance`; the output resets on every advance, including
  `timer_advance(0)`.
- **Determinism**: the fired output and every counter depend only on the
  sequence of calls; there is no clock, randomness, thread or allocator
  influence.

## 6. API summary

| Function | Returns |
|----------|---------|
| `timer_configure(levels, slots)` | `Ok(max_delay)` / geometry `Err` |
| `timer_levels()`, `timer_slots()`, `timer_max_delay()`, `timer_capacity()` | `Int` |
| `timer_now()`, `timer_pending_count()`, `timer_cascade_count()`, `timer_fired_count()` | `Int` |
| `timer_is_scheduled(id)` | `Bool` |
| `timer_insert(id, delay_ticks)` | `Ok(level)` / `Err` |
| `timer_cancel(id)` | `Ok(remaining_ticks)` / `Err` |
| `timer_advance(ticks)` | `Ok(fired_count)` / `Err` |
| `timer_fired_id(i)` | `Ok(id)` / `Err` (Str message) |
| `timer_level_granularity(level)` | `Ok(slots^level)` / `Err` |
| `timer_bucket_level(delay)`, `timer_bucket_slot(delay)` | `Ok(level)` / `Ok(slot)` / `Err` |
| `timer_error_message(code)` | pinned message `Str` |

Complexity: insert O(active entries) for the duplicate scan + O(1) bucket
link; cancel O(active entries) + O(chain); advance O(ticks * levels) plus
cascade/fire work (O(1) when nothing is pending); accessors O(1) except
`timer_is_scheduled` (O(active entries)).

## 7. Error catalog

All fallible timer operations return `Result[Int, TimerError]` where

```
TimerError = { code: Int; id: Int; delay: Int; }
```

`code` identifies the failure; `id`/`delay` carry the offending values where
the rule mentions them, else `-1`. For geometry errors `id` carries the
`levels` argument and `delay` the `slots` argument; for
`timer_bucket_level`/`timer_bucket_slot` the offending delay is always in
`delay` and `id` is `-1`.

| Code | Message | Raised by | Carried fields |
|------|---------|-----------|----------------|
| 1 | `timer: levels must be positive` | configure, levels < 1 | id = levels, delay = slots |
| 2 | `timer: slots must be at least 2` | configure, slots < 2 | id = levels, delay = slots |
| 3 | `timer: levels exceeds maximum` | configure, levels > 8 | id = levels, delay = slots |
| 4 | `timer: slots exceeds maximum` | configure, slots > 1024 | id = levels, delay = slots |
| 5 | `timer: geometry exceeds maximum delay` | configure, slots^levels > 2^32 | id = levels, delay = slots |
| 6 | `timer: delay must be positive` | insert/breakdown, delay <= 0 | id = id (-1 for breakdown), delay = delay |
| 7 | `timer: delay exceeds maximum` | insert/breakdown, delay > max | id = id (-1 for breakdown), delay = delay |
| 8 | `timer: duplicate id` | insert, id already active | id = id, delay = delay |
| 9 | `timer: unknown id` | cancel, no active entry | id = id, delay = -1 |
| 10 | `timer: negative advance` | advance, ticks < 0 | id = -1, delay = ticks |
| 11 | `timer: entry pool is full` | insert, 1024 live entries | id = id, delay = delay |
| 12 | `timer: level out of range` | level_granularity, level outside 0..levels-1 | id = level, delay = -1 |

`timer_fired_id(i)` is the one accessor that returns
`Result[Int, Str]`: `Err("timer: fired index out of range")` when `i` is not
a valid index of the fired output. Codes outside the catalog map to
`timer: unknown error` in `timer_error_message`.

## 8. v0.61.3 implementation notes

Constraints the toolchain imposes on this module (and how it copes):

- No `Vec[StructType]` element writes: entries are parallel vectors with
  explicit chain links.
- No methods, no `Vec[fn]` dispatch, no callbacks: free functions only.
- No `&mut Int` out-parameters: every operation returns values or a
  `Result`.
- No bitwise/shift arithmetic in the proven subset: the wheel uses only
  `+ - * / %` and comparisons.
- No tuples: breakdown information is exposed through two `Result[Int, ...]`
  accessors plus the granularity accessor.
- `Ok`/`Err` are constructed only in leaf helpers (`_tw_ok`, `_tw_err`,
  `_tw_ok_str`, `_tw_err_str`).

## 9. Conformance

`tests/test_conformance.xi` (21 checks) pins this specification: geometry
validation codes 1..5, placement boundaries, non-aligned slot arithmetic,
insert/advance/cancel matrices, exact firing ticks, FIFO ordering,
one-level and multi-level cascade counts, the 2 x 4 wrap boundary including a
direct cascade fire, long idle advances, max-delay acceptance/rejection,
replay determinism, zero/negative advance, pool capacity and slot reuse,
cross-bucket same-tick ordering (cascade fires before level 0), and the error
messages. Run it with:

```powershell
& .\scripts\port.ps1 -Package xiom.timer
```
