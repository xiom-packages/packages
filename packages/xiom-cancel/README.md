# xiom.cancel

> **Status:** `incubating` -- conformance-tested (24/24); published at `v0.1.0` on the XIOM registry.
> **Scope:** cooperative cancellation as a pure, deterministic token tree:
> parent/child tokens, subtree propagation with reason codes, strict and
> idempotent cancel, logical-tick deadlines and cancellation-state
> aggregation. No threads, no atomics, no locks, no wall clock and no I/O.
> **Deps:** `xiom.std` (manifest only); the library module imports nothing
> from it, the tests use `xiom.test`, `xiom.io` and `xiom.string.compare`.

## What it is

`xiom.cancel` models cooperative cancellation as a plain value type and a set
of free functions. A `Canceller` holds a forest of tokens stored as seven
parallel `Vec[Int]` fields:

- ids, parent links, states (`ACTIVE`, `CANCELLED`), reason codes, the
  originating source token, the logical tick at cancellation and optional
  deadlines;
- a monotonic integer clock (`now`) and three counters: direct cancels,
  deadline cancels and propagated cancels.

There is no concurrency in the library, so every operation is a total,
deterministic transition over ordinary values. A real runtime (thread pool,
async executor, request pipeline) owns atomicity and blocking; this module
owns the *semantics* -- what a correct cancellation protocol must do -- in a
form that can be tested exactly, without sleeps or races.

Cancellation rules:

- `canceller_cancel(id, reason)` cancels one `ACTIVE` token and, transitively,
  every `ACTIVE` descendant. Descendants receive reason `CANCEL_REASON_PARENT`
  and `source` = the initiating token; the initiator keeps its own reason and
  `source` = itself. Descendants already cancelled (for example by their own
  deadline) are never overwritten.
- Cancellation is a one-way `ACTIVE -> CANCELLED` transition. Strict
  `canceller_cancel` refuses a repeat with `cancel: already cancelled`;
  `canceller_cancel_idempotent` is a no-op returning `Ok(0)` on repeat.
- A child added under an already-cancelled parent is born `CANCELLED` with
  reason `PARENT` and the parent's origin source, so the propagation closure
  (parent cancelled => child cancelled) always holds.
- Deadlines are absolute logical ticks: a token is due when `now >= deadline`.
  `canceller_check_deadline` checks one token, `canceller_sweep` checks every
  token in creation order, and `canceller_tick` = advance the clock + sweep.
  A due token is cancelled with reason `CANCEL_REASON_DEADLINE` and propagates
  like any other cancel.
- `canceller_aggregate` classifies a caller-supplied id list as
  `NONE` / `SOME` / `ALL` / `EMPTY` / `UNKNOWN`.

## API

| Function | Returns | Description |
|---|---|---|
| `canceller_new()` | `Canceller` | Empty registry, clock 0, zero counters. |
| `canceller_add_root(&mut c, id)` | `Result[Int, Str]` | Add a root token (`ACTIVE`); `Ok(id)`. |
| `canceller_add_child(&mut c, parent, id)` | `Result[Int, Str]` | Add a child; born cancelled under a cancelled parent. |
| `canceller_has_token(c, id)` | `Bool` | Token existence. |
| `canceller_token_count(c)` | `Int` | Number of tokens (never shrinks). |
| `canceller_parent(c, id)` | `Int` | Parent id, `-1` for a root or unknown id. |
| `canceller_children(c, id)` | `Vec[Int]` | Direct children in creation order. |
| `canceller_child_count(c, id)` | `Int` | Number of direct children. |
| `canceller_depth(c, id)` | `Int` | Root = 0, `-1` when unknown. |
| `canceller_root_of(c, id)` | `Int` | Topmost ancestor, `-1` when unknown. |
| `canceller_is_ancestor(c, ancestor, id)` | `Bool` | Strict ancestor test. |
| `canceller_cancel(&mut c, id, reason)` | `Result[Int, Str]` | Cancel the token and its `ACTIVE` descendants; `Ok(newly cancelled)`. |
| `canceller_cancel_idempotent(&mut c, id, reason)` | `Result[Int, Str]` | Same, but repeat calls return `Ok(0)`. |
| `canceller_state(c, id)` | `Int` | `CANCEL_STATE_*` code, `-1` when unknown. |
| `canceller_is_cancelled(c, id)` | `Bool` | Token exists and is `CANCELLED`. |
| `canceller_is_active(c, id)` | `Bool` | Token exists and is `ACTIVE`. |
| `canceller_reason(c, id)` | `Int` | Why this token is cancelled (0 while active). |
| `canceller_source(c, id)` | `Int` | Originating token, `-1` while active/unknown. |
| `canceller_cancel_tick(c, id)` | `Int` | Clock value at cancellation, `-1` while active/unknown. |
| `canceller_now(c)` | `Int` | Current logical clock. |
| `canceller_advance(&mut c, to)` | `Result[Int, Str]` | Move the clock forward (no deadline check). |
| `canceller_set_deadline(&mut c, id, tick)` | `Result[Int, Str]` | Set/replace an absolute tick deadline. |
| `canceller_clear_deadline(&mut c, id)` | `Result[Int, Str]` | Remove the deadline; `Ok(-1)`. |
| `canceller_deadline(c, id)` | `Int` | Deadline tick, `-1` when none/unknown. |
| `canceller_has_deadline(c, id)` | `Bool` | Deadline presence. |
| `canceller_check_deadline(&mut c, id)` | `Result[Int, Str]` | Cancel this token if due; `Ok(newly cancelled)`. |
| `canceller_sweep(&mut c)` | `Int` | Cancel every due token in creation order. |
| `canceller_tick(&mut c, to)` | `Result[Int, Str]` | Advance + sweep; `Ok(newly cancelled)`. |
| `canceller_cancelled_count(c)` | `Int` | Tokens in `CANCELLED`. |
| `canceller_active_count(c)` | `Int` | Tokens in `ACTIVE`. |
| `canceller_direct_cancels(c)` | `Int` | Explicit cancels (strict + idempotent). |
| `canceller_deadline_cancels(c)` | `Int` | Tokens cancelled by a due deadline. |
| `canceller_propagated_cancels(c)` | `Int` | Descendants cancelled by propagation (incl. born cancelled). |
| `canceller_aggregate(c, ids)` | `Int` | `CANCEL_AGG_*` classification of the id list. |
| `canceller_any_cancelled(c, ids)` | `Bool` | At least one listed token cancelled. |
| `canceller_all_cancelled(c, ids)` | `Bool` | Every listed token cancelled (empty list: true). |
| `canceller_count_cancelled(c, ids)` | `Int` | Listed cancelled tokens. |
| `canceller_first_cancelled(c, ids)` | `Int` | First cancelled id in list order, `-1` when none. |
| `canceller_worst_reason(c, ids)` | `Int` | Largest reason code among listed cancelled tokens. |
| `canceller_state_name(state)` | `Str` | `"active"`, `"cancelled"` or `"unknown"`. |
| `cancel_reason_name(code)` | `Str` | `"none"`, `"user"`, `"deadline"`, `"parent"`, `"shutdown"`, `"custom"` or `"unknown"`. |
| `canceller_aggregate_name(code)` | `Str` | `"none"`, `"some"`, `"all"`, `"empty"`, `"unknown"` or `"invalid"`. |
| `canceller_check_invariant(c)` | `Bool` | Structural invariant check (see SPEC.md). |

Public constants: states `CANCEL_STATE_ACTIVE` (0), `CANCEL_STATE_CANCELLED`
(1); reasons `CANCEL_REASON_NONE` (0), `CANCEL_REASON_USER` (1),
`CANCEL_REASON_DEADLINE` (2, reserved), `CANCEL_REASON_PARENT` (3, reserved),
`CANCEL_REASON_SHUTDOWN` (4); aggregates `CANCEL_AGG_NONE` (0),
`CANCEL_AGG_SOME` (1), `CANCEL_AGG_ALL` (2), `CANCEL_AGG_EMPTY` (3),
`CANCEL_AGG_UNKNOWN` (4); sentinels `CANCEL_NO_PARENT` (-1),
`CANCEL_NO_DEADLINE` (-1), `CANCEL_NOT_FOUND` (-1). `canceller_cancel`
accepts `CANCEL_REASON_USER`, `CANCEL_REASON_SHUTDOWN` or any custom code
`>= 5`; codes 0, 2 and 3 are rejected.

Every struct field is an internal implementation detail; callers must go
through the free functions.

## Usage

```xi
use xiom.cancel;

var c = canceller_new();
canceller_add_root(&mut c, 1);
canceller_add_child(&mut c, 1, 2);
canceller_add_child(&mut c, 2, 3);

// Cancel the root: tokens 2 and 3 are cancelled by propagation.
match canceller_cancel(&mut c, 1, CANCEL_REASON_USER) {
  Ok(n) => { /* n == 3 */ },
  Err(_) => { /* "cancel: already cancelled" */ },
}

// Deadlines are logical ticks: set one, advance, sweep.
canceller_add_root(&mut c, 4);
canceller_set_deadline(&mut c, 4, 10);
match canceller_tick(&mut c, 10) {
  Ok(n) => { /* n == 1; token 4 is cancelled with reason DEADLINE */ },
  Err(_) => { /* "cancel: clock cannot go backwards" */ },
}

// Aggregate a group of tokens for a gate or a fan-in join.
var group = Vec[Int].new();
group.push(4);
var agg = canceller_aggregate(&mut c, &group);
if agg == CANCEL_AGG_ALL {
  // every token cancelled
}
if agg == CANCEL_AGG_SOME {
  // partially cancelled
}
if agg == CANCEL_AGG_NONE {
  // nothing cancelled
}
if agg == CANCEL_AGG_UNKNOWN {
  // at least one id is not in the registry
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.cancel
```

Expected: the namespaced module passes the section-4 namespace rule, 24
`[PASS]` lines, and a final `port: PASS (passed=24 failed=0 program_exit=0
exit=0)`.

## Limitations

- **Deterministic model, no real threads.** There is no concurrency,
  atomicity or memory ordering here; a backend that shares a token tree
  between threads must serialize access to the `Canceller` value itself.
- **Logical time only.** Deadlines are integer ticks checked explicitly by
  `canceller_check_deadline` / `canceller_sweep` / `canceller_tick`; the
  library never consults a wall clock and never fires a cancellation on its
  own.
- **Tokens are never removed.** The tree only grows; ids are never reused and
  there is no detach or reparent operation.
- **Aggregation is a caller-supplied snapshot.** `canceller_aggregate` and
  its helpers classify the id list they are given; they do not track groups
  or scopes themselves, and they are not atomic with respect to later
  cancels.
- **Unknown ids in aggregation.** `CANCEL_AGG_UNKNOWN` takes precedence over
  the cancelled counts (a typo is reported, never silently treated as
  "not cancelled"); the boolean helpers instead treat unknown ids as not
  cancelled (`canceller_all_cancelled` returns false, `any` ignores them).
- **Linear scans.** All lookups scan the token vectors, so cancellation of a
  large subtree is O(token count^2); fine for the model, not tuned for very
  large trees.
- Not thread-safe: values follow ordinary XIOM move/borrow rules.

## Install / publish

```
xiom pkg install xiom.cancel@0.1.0     # consumer
xiom pkg publish                      # maintainer (needs XIOM_REGISTRY_TOKEN)
```

The package is not yet published; the commands above become usable after the
first publish to the XIOM registry.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
