# xiom.cancel -- Specification

Status: `incubating` (implemented, harness-green, not published).
Module: `xiom.cancel` (`src/cancel.xi`). Manifest: `package.xi` (name
`xiom.cancel`, version `0.1.0`). `xiom.std` is a manifest dependency; the
library module imports nothing from it, the tests use `xiom.test`, `xiom.io`
and `xiom.string.compare`.

## 1. Scope

Cooperative cancellation tokens as a pure, deterministic token tree -- the
semantic core that a thread pool, async executor or request pipeline would
drive:

- token construction as a forest: `canceller_add_root`,
  `canceller_add_child`, with parent/child queries (`canceller_parent`,
  `canceller_children`, `canceller_child_count`, `canceller_depth`,
  `canceller_root_of`, `canceller_is_ancestor`);
- cancellation with reason codes (`canceller_cancel`), idempotent
  cancellation (`canceller_cancel_idempotent`) and transitive subtree
  propagation with exact counters (`canceller_propagated_cancels`);
- a monotonic logical integer clock and absolute-tick deadlines
  (`canceller_advance`, `canceller_set_deadline`, `canceller_clear_deadline`,
  `canceller_check_deadline`, `canceller_sweep`, `canceller_tick`);
- cancellation-state aggregation over caller-supplied id lists
  (`canceller_aggregate` plus the `any` / `all` / `count` / `first` /
  `worst_reason` helpers);
- state accessors (`canceller_state`, `canceller_is_cancelled`,
  `canceller_reason`, `canceller_source`, `canceller_cancel_tick`), counters
  and a structural invariant (`canceller_check_invariant`).

No threads, no atomics, no locks, no wall clock, no I/O, no FFI, no global
state. The library owns semantics only; a backend owns concurrency and
blocking.

## 2. Non-goals

- Actual asynchronous notification, waiting, joins or callbacks. A token is a
  value; a backend polls the accessors or drives the checks.
- Real-time or OS deadlines. Deadlines are logical ticks the caller advances;
  the library never reads a clock.
- Task execution, scheduling or futures. `xiom.cancel` is the cancellation
  half only; `xiom.executor` (a separate package) is the deterministic
  execution model.
- Token removal, detach or reparent; the tree only grows and ids are never
  reused.
- Group/scope registries beyond a caller-supplied id list for aggregation.
- Atomicity or memory ordering; the value follows ordinary XIOM move/borrow
  rules and a concurrent backend must serialize access.

## 3. State

```xi
pub type Canceller = {
  token_ids: Vec[Int];    // token ids, unique, >= 0
  parents: Vec[Int];      // parent token id, or -1 for a root
  states: Vec[Int];       // CANCEL_STATE_ACTIVE | CANCEL_STATE_CANCELLED
  reasons: Vec[Int];      // CANCEL_REASON_* (or custom): why THIS token is cancelled
  sources: Vec[Int];      // originating token: self, or the cancelled ancestor
  cancel_ticks: Vec[Int]; // logical clock value at cancellation, or -1
  deadlines: Vec[Int];    // absolute logical tick, or -1 when none
  now: Int;               // monotonic logical clock, starts at 0
  direct_cancels: Int;    // successful explicit cancels (strict + idempotent)
  deadline_cancels: Int;  // tokens cancelled by a due deadline
  propagated_cancels: Int;// descendants cancelled by propagation (incl. born cancelled)
}
```

Every field is an internal implementation detail; callers go through the free
functions. The seven token vectors are pushed and rewritten together by every
mutation, so they can never skew.

State codes: `CANCEL_STATE_ACTIVE` (0), `CANCEL_STATE_CANCELLED` (1).
Reason codes: `CANCEL_REASON_NONE` (0, only on `ACTIVE` tokens),
`CANCEL_REASON_USER` (1), `CANCEL_REASON_DEADLINE` (2, reserved),
`CANCEL_REASON_PARENT` (3, reserved), `CANCEL_REASON_SHUTDOWN` (4);
`canceller_cancel` / `canceller_cancel_idempotent` accept 1, 4 or any custom
code `>= 5` and reject 0, 2 and 3.
Aggregate codes: `CANCEL_AGG_NONE` (0), `CANCEL_AGG_SOME` (1),
`CANCEL_AGG_ALL` (2), `CANCEL_AGG_EMPTY` (3), `CANCEL_AGG_UNKNOWN` (4).
Sentinels: `CANCEL_NO_PARENT` (-1), `CANCEL_NO_DEADLINE` (-1),
`CANCEL_NOT_FOUND` (-1).

### 3.1 Invariant

`canceller_check_invariant(c)` is true exactly when:

1. the seven token vectors have equal length `n` and `now >= 0`;
2. every token id is `>= 0` and unique; every parent is `-1` or names an
   existing token at a strictly smaller slot (forest, acyclic); every state
   is a `CANCEL_STATE_*` code; every deadline is `>= -1`;
3. an `ACTIVE` token has reason `NONE` (0), source `-1` and cancel_tick `-1`;
4. a `CANCELLED` token has reason `>= 1`, source `>= 0` naming an existing
   token, and cancel_tick `>= 0`; when the reason is `PARENT` the source is a
   proper ancestor whose own reason is not `PARENT`; otherwise the source is
   the token itself;
5. propagation closure: a token whose parent is `CANCELLED` is itself
   `CANCELLED`;
6. the counters partition the cancelled tokens by reason:
   `direct_cancels` counts `CANCELLED` tokens with a reason other than
   `PARENT`/`DEADLINE`, `deadline_cancels` counts reason `DEADLINE`,
   `propagated_cancels` counts reason `PARENT`, and the three sum to the
   number of `CANCELLED` states.

## 4. State machine rules

Notation: `c` is a `Canceller`; `p`, `id` are token ids; `r` is a reason code;
`t` is a logical tick.

### 4.1 S1 -- construction (`canceller_new()`)

- effect: empty vectors, clock 0, all counters zero;
- no error: the constructor is total.

### 4.2 S2 -- root token (`canceller_add_root(id)`)

Validation order:

1. `id < 0` -> `Err("cancel: token id must be >= 0")`;
2. `id` already known -> `Err("cancel: duplicate token id")`;
3. otherwise append a root token: parent `-1`, state `ACTIVE`, reason `NONE`,
   source `-1`, cancel_tick `-1`, deadline `-1`; `Ok(id)`.

Every error leaves the state unchanged.

### 4.3 S3 -- child token (`canceller_add_child(parent, id)`)

Validation order:

1. `id < 0` -> `Err("cancel: token id must be >= 0")`;
2. `id` already known -> `Err("cancel: duplicate token id")`;
3. `parent` unknown -> `Err("cancel: unknown parent token id")`;
4. otherwise append a token with parent = `parent` and deadline `-1`. If the
   parent is `ACTIVE` the child is `ACTIVE` (reason `NONE`, source `-1`,
   tick `-1`); if the parent is `CANCELLED` the child is **born cancelled**:
   state `CANCELLED`, reason `PARENT`, source = the parent's origin source,
   cancel_tick = the current clock, and `propagated_cancels` grows by one;
   `Ok(id)`.

The parent always precedes the child, so the parent chain is acyclic and the
invariant's parent-slot rule holds by construction.

### 4.4 S4 -- strict cancel (`canceller_cancel(id, r)`)

Validation order:

1. unknown `id` -> `Err("cancel: unknown token id")`;
2. `r < 1` -> `Err("cancel: reason must be >= 1")`;
3. `r` is `CANCEL_REASON_DEADLINE` (2) or `CANCEL_REASON_PARENT` (3) ->
   `Err("cancel: reason code is reserved")`;
4. token `CANCELLED` -> `Err("cancel: already cancelled")`;
5. otherwise the target becomes `CANCELLED` with reason `r`, source = the
   token's own id, cancel_tick = `now`; every `ACTIVE` descendant becomes
   `CANCELLED` with reason `PARENT`, source = the target id and
   cancel_tick = `now`; `direct_cancels += 1`, `propagated_cancels +=`
   number of descendants cancelled; `Ok(newly cancelled count)`.

Descendants already `CANCELLED` keep their original reason/source/tick.
Every error leaves the state unchanged.

### 4.5 S5 -- idempotent cancel (`canceller_cancel_idempotent(id, r)`)

Same validation order as S4, except step 4 returns `Ok(0)` and changes
nothing (the original reason/source/tick are preserved). On an `ACTIVE`
target the effect is identical to S4.

### 4.6 S6 -- clock advance (`canceller_advance(t)`)

- `t < now` -> `Err("cancel: clock cannot go backwards")` (state unchanged);
- otherwise `now = t`, `Ok(t)`. Deadlines are **not** evaluated.

### 4.7 S7 -- deadline management (`canceller_set_deadline(id, t)`,
`canceller_clear_deadline(id)`)

`set_deadline` validation order:

1. unknown `id` -> `Err("cancel: unknown token id")`;
2. `t < 0` -> `Err("cancel: deadline must be >= 0")`;
3. token `CANCELLED` -> `Err("cancel: already cancelled")`;
4. otherwise `deadline = t` (set or replace), `Ok(t)`.

`clear_deadline` validation order:

1. unknown `id` -> `Err("cancel: unknown token id")`;
2. token `CANCELLED` -> `Err("cancel: already cancelled")`;
3. otherwise `deadline = -1`, `Ok(CANCEL_NO_DEADLINE)` (-1).

### 4.8 S8 -- single deadline check (`canceller_check_deadline(id)`)

1. unknown `id` -> `Err("cancel: unknown token id")`;
2. token not `ACTIVE`, or no deadline, or `now < deadline` -> `Ok(0)`;
3. `now >= deadline` -> cancel the token exactly as S4 with reason
   `CANCEL_REASON_DEADLINE` and source = its own id, propagate to `ACTIVE`
   descendants; `deadline_cancels += 1`; `Ok(newly cancelled count)`.

### 4.9 S9 -- sweep (`canceller_sweep()`)

Scans tokens in creation order; for every `ACTIVE` token whose deadline is
set and `now >= deadline`, cancels it (S8 rule: reason `DEADLINE`, source =
its own id, propagation included), `deadline_cancels += 1`. A token already
`CANCELLED` -- including one just cancelled by an earlier due ancestor in the
same sweep -- is skipped. Returns the number of tokens newly cancelled by
this sweep.

### 4.10 S10 -- tick (`canceller_tick(t)`)

1. `t < now` -> `Err("cancel: clock cannot go backwards")` (state unchanged;
   no sweep runs);
2. otherwise `now = t`, run S9, `Ok(newly cancelled count)`.

### 4.11 Aggregation (`canceller_aggregate(ids)`)

With `n = ids.len()`:

- `n == 0` -> `CANCEL_AGG_EMPTY`;
- if any id is not in the registry -> `CANCEL_AGG_UNKNOWN` (checked first, so
  a typo is reported rather than treated as "not cancelled");
- otherwise let `cancelled` be the number of listed tokens in `CANCELLED`
  (duplicate entries count per entry): `cancelled == 0` ->
  `CANCEL_AGG_NONE`; `cancelled == n` -> `CANCEL_AGG_ALL`; else
  `CANCEL_AGG_SOME`.

The boolean/count helpers use a different, documented convention: unknown ids
are treated as not cancelled. `canceller_any_cancelled` (false for empty),
`canceller_all_cancelled` (true for empty; false if any id is unknown or
`ACTIVE`), `canceller_count_cancelled`, `canceller_first_cancelled` (first in
list order, unknown ids skipped, `-1` when none) and
`canceller_worst_reason` (largest reason among cancelled listed tokens,
`CANCEL_REASON_NONE` when none).

## 5. Propagation semantics

When a token becomes cancelled, every `ACTIVE` descendant is cancelled in the
same call. Properties:

1. **One-way transition.** `ACTIVE -> CANCELLED` only; `CANCELLED` is
   terminal. No operation ever moves a token back or rewrites its
   reason/source/tick.
2. **Origin recorded.** A direct or deadline cancel records
   `source = self`; a propagated cancel records the initiating token id, so
   `canceller_source(id)` answers "which token caused this". The initiating
   token's own reason is recoverable with `canceller_reason(source)`.
3. **Reason partition.** `PARENT` means "cancelled because an ancestor was";
   `DEADLINE` means "this token's own deadline expired"; anything else is an
   explicit caller reason.
4. **Closure.** A token added under a `CANCELLED` parent is born cancelled
   (S3), and every cancel call cancels all `ACTIVE` descendants, so
   `parent CANCELLED => child CANCELLED` holds in every reachable state
   (invariant clause 5).
5. **Cancelled-descendant precedence.** An already-cancelled descendant keeps
   its own reason/source/tick; propagation never overwrites it. In
   particular, a token cancelled by its own deadline reports `DEADLINE` even
   if an ancestor is cancelled later.
6. **Exactly-once counting.** Each token is cancelled at most once
   (`CANCELLED` is terminal), only `ACTIVE` descendants are touched, and a
   sweep skips already-cancelled tokens; therefore
   `direct_cancels + deadline_cancels + propagated_cancels` equals the number
   of cancelled tokens (invariant clause 6).

## 6. Error catalog

All error strings are stable and prefixed `cancel: `.

| Function | Condition | Err message | State on error |
|---|---|---|---|
| `canceller_add_root` / `canceller_add_child` | `id < 0` | `cancel: token id must be >= 0` | unchanged |
| `canceller_add_root` / `canceller_add_child` | id already known | `cancel: duplicate token id` | unchanged |
| `canceller_add_child` | unknown parent | `cancel: unknown parent token id` | unchanged |
| `canceller_cancel` / `canceller_cancel_idempotent` | unknown id | `cancel: unknown token id` | unchanged |
| `canceller_cancel` / `canceller_cancel_idempotent` | `reason < 1` | `cancel: reason must be >= 1` | unchanged |
| `canceller_cancel` / `canceller_cancel_idempotent` | reason 2 or 3 | `cancel: reason code is reserved` | unchanged |
| `canceller_cancel` | already cancelled | `cancel: already cancelled` | unchanged |
| `canceller_cancel_idempotent` | already cancelled | -- (`Ok(0)`) | unchanged |
| `canceller_advance` / `canceller_tick` | `to < now` | `cancel: clock cannot go backwards` | unchanged |
| `canceller_set_deadline` | unknown id | `cancel: unknown token id` | unchanged |
| `canceller_set_deadline` | `tick < 0` | `cancel: deadline must be >= 0` | unchanged |
| `canceller_set_deadline` / `canceller_clear_deadline` | already cancelled | `cancel: already cancelled` | unchanged |
| `canceller_clear_deadline` | unknown id | `cancel: unknown token id` | unchanged |
| `canceller_check_deadline` | unknown id | `cancel: unknown token id` | unchanged |

No panicking input exists: every function is total, and read accessors return
`-1` / `false` / `""` sentinels instead of erroring.

## 7. Complexity

| Operation | Complexity |
|---|---|
| `canceller_new` / `canceller_now` / counters | O(1) |
| `canceller_advance` | O(1) |
| `canceller_add_root` / `canceller_add_child` | O(token count) -- duplicate and parent scans |
| `canceller_has_token` / `canceller_parent` / state, reason, source, tick, deadline accessors | O(token count) |
| `canceller_children` / `canceller_child_count` | O(token count) |
| `canceller_depth` / `canceller_root_of` / `canceller_is_ancestor` | O(depth) |
| `canceller_cancel` / `canceller_cancel_idempotent` / `canceller_check_deadline` | O(token count^2) -- descendant scan |
| `canceller_sweep` / `canceller_tick` | O(token count^2) |
| `canceller_cancelled_count` / `canceller_active_count` | O(token count) |
| `canceller_aggregate` and the list helpers | O(list length x token count) |
| `canceller_check_invariant` | O(token count^2) |

## 8. Test plan

`tests/test_conformance.xi` (`module cancel_tests`, 24 named checks, a
hello-style `main` that prints `[PASS]`/`[FAIL]` per check, a summary line,
and returns the failure count). Fixtures are built in-test through
`canceller_new`; every string comparison routes through
`compare.str_compare`; tests are called directly (no `Vec[fn]` dispatch).

1. `canceller_new` starts empty with a zero clock and counters;
2. `add_root` validates ids and creates `ACTIVE` parentless tokens;
3. `add_child` validates ids and links children in creation order;
4. parent/child links expose depth, roots and ancestor relations;
5. cancelling a leaf cancels exactly one token with its reason and tick;
6. cancelling a root propagates `PARENT` cancellation to every descendant;
7. strict cancel refuses repeats and unknown ids without changing state;
8. `cancel_idempotent` is a no-op on repeat and still validates input;
9. cancel validates reason `>= 1`, reserves 2/3 and accepts custom codes;
10. unknown ids yield sentinels instead of errors;
11. a child added under a cancelled parent is born cancelled with the origin
    source;
12. children added under an active parent stay active until cancelled;
13. `set`/`clear_deadline` validate ids, ticks and token state;
14. `check_deadline` cancels a due token exactly once with reason `DEADLINE`;
15. a deadline cancel propagates to descendants like any other cancel;
16. the clock is monotonic and sweep cancels only due tokens;
17. tick advances and sweeps; cascading due deadlines cancel each token once;
18. aggregate classifies `EMPTY`/`NONE`/`SOME`/`ALL` and flags unknown ids;
19. `any`/`all`/`count`/`first`/`worst` aggregate helpers are exact;
20. children copies are independent and aggregation does not consume its
    list;
21. the invariant holds across 24 deterministic add/cancel/sweep cycles;
22. state, reason and aggregate name helpers are stable;
23. cancel ticks record the logical clock at cancellation time;
24. a 7-node tree cancels in one call with exact propagation counts.

Run from the repository root:

```
.\scripts\port.ps1 -Package xiom.cancel
```

Last verified: compiler v0.62.1, `port: PASS (passed=24 failed=0
program_exit=0 exit=0)`.

## 9. Compiler / stdlib notes for v0.62.1

- Free functions only (no methods), with explicit `&`/`&mut` parameters and
  `&mut` at every call site.
- `Ok`/`Err` are constructed only inside the `_ok_int` / `_err_int` leaf
  helper functions.
- `Vec[Int]` element reads are bound with a typed `let` before use.
- The seven parallel token vectors are pushed in the same function and never
  rebuilt piecemeal, so they cannot skew.
- Str equality (tests) goes through `str_compare`; the library itself has no
  Str reads from vectors and no string comparison.
- No `Vec[StructType]`, no indexed `Vec[fn]` dispatch, no generic callbacks,
  no `Vec[Float64]`, no `mut` in match patterns, no `break`/`continue`, no
  FFI, no threads, no `log`-named function.
- The module imports nothing from `xiom.std`; only the tests import
  `xiom.test`, `xiom.io` and `xiom.string.compare`.
- Wrapper functions in the test suite take `&mut` for read-only access, so a
  `&local` read call is never followed by a `&mut local` call in the same
  function body (advisory E001).

## 10. Known limitations

- The model is single-threaded and non-atomic; a concurrent backend must
  provide the critical section around every transition.
- Deadlines fire only when checked: the library never advances time or
  cancels on its own.
- The token table only grows; there is no removal, detach or reparent, and
  ids cannot be reused.
- Aggregation is stateless with respect to groups: the caller supplies the id
  list, and the classification is a snapshot, not a subscription.
- `CANCEL_AGG_UNKNOWN` treats any unknown id as an input error, while the
  boolean helpers ignore unknown ids; both conventions are documented and
  tested.
- Subtree propagation, sweeps and the invariant use linear scans, so worst
  cases are O(token count^2); a backend with very large trees would index
  children instead.
