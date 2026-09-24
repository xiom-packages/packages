# xiom.transaction -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.transaction` (`src/transaction.xi`). Pure XIOM, no FFI.

## 1. Scope

A deterministic, in-memory transaction-lifecycle state machine with named
savepoints:

- a `Txn` value records the lifecycle state, an operation counter and the
  named savepoints (parallel name and mark lists),
- `txn_begin` / `txn_commit` / `txn_rollback` drive the lifecycle,
- `txn_add_op` counts caller-declared operations,
- `txn_savepoint` / `txn_rollback_to` / `txn_release` manage savepoints,
- `txn_state`, `txn_op_count`, `txn_savepoint_count`, `txn_savepoint_name`
  and `txn_mark` read the record.

The module never touches a database, the file system, the clock, or any
global state; the caller supplies every operation and owns the `Txn` value.

## 2. Non-goals

- Storage, durability, logging, write-ahead logs, snapshots, fsync, crash
  recovery, or any effect on an external system.
- Isolation levels, locking, conflict detection, multi-transaction
  visibility, or concurrency control of any kind.
- Two-phase commit, distributed transactions, or prepared transaction states.
- Nested transactions (savepoints are the only nesting mechanism), SQL
  parsing, query execution, or statement metadata.
- Persistence or serialization of a `Txn`; the record lives and dies with the
  caller's value.
- FFI, threads, async, or global registries.

## 3. Data model

```xi
pub type Txn = {
  state: Int;       // 0 idle, 1 active, 2 committed, 3 rolled_back
  ops: Int;         // operations since the last successful begin, less the discarded tail
  names: Vec[Str];  // savepoint names
  marks: Vec[Int];  // marks[i]: op count anchored by names[i]
}
```

Fields are implementation details; callers go through the free functions.

Definitions:

- **Marks are non-decreasing.** `marks[i] <= marks[i + 1]` for every valid
  `i`, and every mark is `<= ops` while the record is active.
- **Anchor.** Anchoring a savepoint records `name` with `mark = ops` at that
  moment. `txn_rollback_to` resets `ops` to the mark.
- **Inert savepoints.** Savepoint records survive `txn_commit` and
  `txn_rollback` as inert bookkeeping (they remain readable) until the next
  successful `txn_begin` clears them; savepoint *operations* refuse to run on
  a non-active record.
- **State codes.** 0 idle, 1 active, 2 committed, 3 rolled_back. Only one
  transaction is represented per `Txn`, and only one transition is "in
  flight": there is no intermediate state stored.

## 4. State machine

| Current state | Operation | Next state | Effects |
|---|---|---|---|
| idle (0) | `txn_begin` | active (1) | `ops = 0`, savepoints cleared, returns `true` |
| active (1) | `txn_begin` | active (1) | rejected: returns `false`, no changes |
| active (1) | `txn_add_op` | active (1) | `ops += 1`, returns `true` |
| active (1) | `txn_commit` | committed (2) | `Ok(ops)`; `ops` is kept; savepoints become inert |
| active (1) | `txn_rollback` | rolled_back (3) | `Ok(ops)`; `ops = 0`; savepoints become inert |
| committed (2) | `txn_begin` | active (1) | `ops = 0`, savepoints cleared, returns `true` |
| rolled_back (3) | `txn_begin` | active (1) | `ops = 0`, savepoints cleared, returns `true` |
| committed (2) | `txn_commit` / `txn_rollback` | committed (2) | `Err`; state and fields unchanged |
| rolled_back (3) | `txn_commit` / `txn_rollback` | rolled_back (3) | `Err`; state and fields unchanged |
| non-active | `txn_add_op` | unchanged | returns `false` |
| non-active | `txn_savepoint` / `txn_rollback_to` / `txn_release` | unchanged | `false` / `Err` as catalogued below |
| active (1) | `txn_savepoint(name)` | active (1) | `names/marks += (name, ops)`; duplicate re-anchors (see 5.6) |
| active (1) | `txn_rollback_to(name)` | active (1) | `ops = mark(name)`; savepoints after `name` removed; keeps `name` |
| active (1) | `txn_release(name)` | active (1) | remove `name`; `ops` unchanged; later savepoints shift down |

Text rendering:

```
                 begin                    commit
   idle (0) ───────────► active (1) ─────────────► committed (2)
      ▲                    │   │                       │
      │                    │   │ rollback              │
      │                    │   ▼                       │
      │                    │  rolled_back (3)          │
      │                    │       │                   │
      └────────────────────┴───────┴───────────────────┘
                   begin (from any non-active state)
```

## 5. Operation semantics

### 5.1 txn_new

Returns `Txn{ state: 0; ops: 0; names: Vec[Str].new(); marks: Vec[Int].new(); }`.
No error path. O(1).

### 5.2 txn_begin

Accepted from every non-active state. Sets `state = 1`, `ops = 0`, clears
`names` and `marks`, and returns `true`. While already active it returns
`false` and changes nothing (in particular the op count and the savepoints
survive a rejected re-begin). Clearing is O(n) in the number of savepoints.

### 5.3 txn_add_op

While active: `ops += 1` and `true`. Otherwise `false`, no change. O(1).

### 5.4 txn_commit

While active: sets `state = 2` and returns `Ok(ops)`, where `ops` is read
before the transition and stays readable through `txn_op_count` afterwards.
The savepoint records are kept (inert) until the next `txn_begin`. Otherwise
returns `Err("transaction: commit requires an active transaction")` and
changes nothing. O(1).

### 5.5 txn_rollback

While active: reads `n = ops`, sets `state = 3` and `ops = 0`, and returns
`Ok(n)` -- the number of operations discarded by the rollback. The savepoint
records are kept (inert) until the next `txn_begin`. Otherwise returns
`Err("transaction: rollback requires an active transaction")` and changes
nothing. O(1).

### 5.6 txn_savepoint

Preconditions: active, non-empty `name`. A new name is appended with
`mark = ops`. A duplicate name is **re-anchored**: the existing entry is
removed from its position and appended at the end with `mark = ops`, so the
list holds each name at most once, marks stay non-decreasing, and a duplicate
never nests. Returns `true` on success. Returns `false` and changes nothing
when the record is not active or `name` is empty. O(n) in savepoint count.

Consequences pinned by the tests: declaring `a`, then `b`, then `a` again
yields `names = [b, a]` with `mark(b) < mark(a)`; rolling back to `b`
afterwards removes `a` (it lies after `b`), so no stale forward mark can
survive.

### 5.7 txn_rollback_to

Preconditions: active, known `name`. Sets `ops = mark(name)`, keeps the named
savepoint, and removes every savepoint after it; returns `Ok(mark(name))`.
Because the surviving savepoints all have marks `<= mark(name)`, repeating
the call returns the same value and changes nothing (idempotent). Error paths
(no changes to state or fields):

- not active: `Err("transaction: rollback_to requires an active transaction")`
- unknown name: `Err("transaction: unknown savepoint: <name>")`

O(n) in savepoint count.

### 5.8 txn_release

Preconditions: active, known `name`. Removes the savepoint, keeps `ops` and
`state`, shifts later savepoints down, returns `true`. Returns `false` and
changes nothing when the record is not active or `name` is unknown.
O(n) in savepoint count.

### 5.9 Readers

- `txn_state`: state code, O(1).
- `txn_op_count`: op count, O(1).
- `txn_savepoint_count`: `names.len()`, O(1).
- `txn_savepoint_name(i)`: `names[i]`, or `""` when `i < 0` or
  `i >= names.len()`, O(1).
- `txn_mark(name)`: `marks[i]` for the matching name, or `-1`, O(n).

## 6. Error catalog

All error messages are `Str` values with the `transaction: ` prefix; the
suite pins them exactly.

| Site | Message |
|---|---|
| `txn_commit`, not active | `transaction: commit requires an active transaction` |
| `txn_rollback`, not active | `transaction: rollback requires an active transaction` |
| `txn_rollback_to`, not active | `transaction: rollback_to requires an active transaction` |
| `txn_rollback_to`, unknown name | `transaction: unknown savepoint: <name>` (the name appended verbatim) |

Rejected boolean operations (no message): `txn_begin` while active;
`txn_add_op` while not active; `txn_savepoint` while not active or with an
empty name; `txn_release` while not active or with an unknown name.

## 7. API signatures

```xi
pub type Txn = { state: Int; ops: Int; names: Vec[Str]; marks: Vec[Int]; }

pub fn txn_new() -> Txn
pub fn txn_state(t: &Txn) -> Int
pub fn txn_op_count(t: &Txn) -> Int
pub fn txn_begin(t: &mut Txn) -> Bool
pub fn txn_add_op(t: &mut Txn) -> Bool
pub fn txn_commit(t: &mut Txn) -> Result[Int, Str]
pub fn txn_rollback(t: &mut Txn) -> Result[Int, Str]
pub fn txn_savepoint(t: &mut Txn, name: Str) -> Bool
pub fn txn_rollback_to(t: &mut Txn, name: Str) -> Result[Int, Str]
pub fn txn_release(t: &mut Txn, name: Str) -> Bool
pub fn txn_savepoint_count(t: &Txn) -> Int
pub fn txn_savepoint_name(t: &Txn, i: Int) -> Str
pub fn txn_mark(t: &Txn, name: Str) -> Int
```

## 8. Test plan

`tests/test_conformance.xi` (module `transaction_tests`) runs 22 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | new record | idle, ops 0, no savepoints, unknown name -1, out-of-range name "" |
| t2 | begin | idle -> active, counters and savepoints still empty |
| t3 | begin while active | returns false; ops and savepoints survive |
| t4 | add_op gating | false idle/committed/rolled_back; true and increments while active |
| t5 | commit ok | `Ok(3)`; state committed; op count kept |
| t6 | commit errors | idle, committed and rolled_back all Err with the catalogued message |
| t7 | rollback ok | `Ok(3)`; state rolled_back; ops 0; savepoints retained inert |
| t8 | rollback errors | idle, committed and rolled_back all Err with the catalogued message |
| t9 | savepoint gating | false idle, committed and rolled_back; nothing recorded |
| t10 | empty name | rejected; count stays 0; no empty-name mark |
| t11 | count/names/marks | order, marks 1 and 3, out-of-range name "", unknown mark -1 |
| t12 | duplicate | re-anchor moves the entry to the end, mark updated, count unchanged; rollback to the earlier name drops it |
| t13 | rollback_to | discards the tail, keeps the savepoint, stays active; ops resume |
| t14 | rollback_to repeat | three calls return the same Ok and leave ops/mark fixed |
| t15 | unknown savepoint | exact `transaction: unknown savepoint: ghost`; no side effects; inactive form errors too |
| t16 | tail destruction | later savepoints are removed; the target can be reused |
| t17 | release | removes the entry, keeps ops, shifts later names down |
| t18 | release errors | false inactive and unknown; nothing removed |
| t19 | begin after commit | savepoints inert after commit, cleared by begin; ops reset |
| t20 | begin after rollback | clean active transaction; new savepoints anchor at 0 |
| t21 | long sequence | 20 ops, 3 savepoints (5/10/15), rollback_to s2 (Ok(10), s3 gone), repeat, 2 more ops, commit `Ok(12)` |
| t22 | error catalog | the three wrong-state messages pinned exactly from idle/committed |

Test helpers wrap the `&`-based read accessors in `&mut`-taking helpers so a
`&local` read call is never followed by a `&mut local` call in the same test
body (advisory E001). All `Str` equality goes through
`compare.str_compare` (BUG 17), including the exact-message checks.

## 9. Compiler / stdlib notes

Module `xiom.transaction` imports `xiom.string.compare` for `str_compare`;
the suite additionally uses `xiom.test`, `xiom.io` and `xiom.string.compare`.
v0.61.3 constraints handled by construction:

- free functions only (no methods on `Txn`),
- `Ok`/`Err` construction confined to the `_ok_int`/`_err_int` leaf helpers
  (constructing `Result` values directly in other functions miscompiles),
- no `==` on `Str` values read from `Vec[Str]`; equality goes through
  `str_compare` with typed locals for element reads,
- no `Vec[StructType]`, no inline lambdas, no function-pointer test
  dispatch: `main` calls `t1`..`t22` explicitly,
- non-exhaustive `match` is a hard error: every `match` in the suite covers
  both `Ok`/`Err` arms.

Verified with `.\scripts\port.ps1 -Package xiom.transaction` (v0.61.3).

## 10. Limitations

- In-memory bookkeeping only: no database work, no durability, no logging
  (see section 2). A `Txn` is as durable as the caller's value.
- Savepoint records are inert after the transaction ends; only the next
  `txn_begin` clears them.
- Savepoint lookup and removal are linear scans (O(n)); the record is not a
  dictionary and never claims to be.
- A `Txn` is not thread-safe and has no internal locking; sharing one across
  threads is the caller's responsibility.
