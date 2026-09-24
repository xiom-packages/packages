# xiom.transaction

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** transaction lifecycle state machine with named savepoints.
> **Deps:** `xiom.std` only (the library imports the stdlib Str comparison
> helper; the tests use `xiom.std` modules).

## What it is

`xiom.transaction` is a small, deterministic bookkeeping state machine for the
lifecycle of a transaction. A `Txn` records four things: the lifecycle state
(`0` idle, `1` active, `2` committed, `3` rolled_back), an operation counter,
and two parallel savepoint lists (names and the op count each name is anchored
at, the *mark*). The caller owns the `Txn` and drives every transition; the
module performs no database work, no I/O, no logging and no persistence.

## API

| Function | Returns | Description |
|---|---|---|
| `txn_new()` | `Txn` | Fresh record: idle, zero ops, no savepoints. |
| `txn_state(t)` | `Int` | Lifecycle state: 0 idle, 1 active, 2 committed, 3 rolled_back. |
| `txn_op_count(t)` | `Int` | Operations recorded since the last successful `txn_begin`, less any tail discarded by `txn_rollback_to`. |
| `txn_begin(&mut t)` | `Bool` | Start a transaction (from idle, committed or rolled_back); resets ops and clears savepoints. `false` and no changes while already active. |
| `txn_add_op(&mut t)` | `Bool` | Record one operation; `true` and `ops += 1` only while active. |
| `txn_commit(&mut t)` | `Result[Int, Str]` | Active only: returns the op count (kept readable afterwards) and enters committed. |
| `txn_rollback(&mut t)` | `Result[Int, Str]` | Active only: returns the discarded op count, resets ops to 0 and enters rolled_back. |
| `txn_savepoint(&mut t, name)` | `Bool` | Active only, non-empty name: anchor `name` at the current op count. A duplicate name is re-anchored at the current op count (it moves to the end of the list). |
| `txn_rollback_to(&mut t, name)` | `Result[Int, Str]` | Active only, known name: reset ops to the mark, keep the named savepoint, remove every savepoint after it. Repeatable. |
| `txn_release(&mut t, name)` | `Bool` | Active only: remove the savepoint, keeping the ops; `false` when unknown. |
| `txn_savepoint_count(t)` | `Int` | Number of savepoints. |
| `txn_savepoint_name(t, i)` | `Str` | Savepoint name at index `i`, or `""` out of range. |
| `txn_mark(t, name)` | `Int` | Op count anchored by `name`, or `-1` when unknown. |

Several contracts are intentionally explicit:

- **Duplicate savepoints re-anchor.** Declaring an existing name again moves
  the savepoint to the end of the list with the current op count as its new
  mark; the list never contains the same name twice and marks stay
  non-decreasing.
- **`txn_rollback_to` truncates the savepoint tail.** The named savepoint is
  kept; every savepoint created after it is removed. This makes the call
  repeatable and guarantees a mark can never exceed the current op count.
- **`commit`/`rollback` leave savepoint records inert.** They are cleared by
  the next `txn_begin`; they remain readable as historical bookkeeping until
  then.

## State diagram (text)

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

Transition table:

```
 idle (0)         -- begin         --> active (1)        [ops = 0, savepoints cleared]
 active (1)       -- add_op        --> active (1)        [ops += 1]
 active (1)       -- commit        --> committed (2)     [Ok(op count), ops kept]
 active (1)       -- rollback      --> rolled_back (3)   [Ok(discarded), ops = 0]
 committed (2)    -- begin         --> active (1)        [reset]
 rolled_back (3)  -- begin         --> active (1)        [reset]
 committed (2)    -- commit/rollback/rollback_to/release/savepoint --> Err/false
 rolled_back (3)  -- commit/rollback/rollback_to/release/savepoint --> Err/false
 active (1)       -- savepoint     --> active (1)        [mark = current ops]
 active (1)       -- rollback_to   --> active (1)        [ops = mark, tail dropped]
 active (1)       -- release       --> active (1)        [ops kept]
```

## Usage

```xi
use xiom.transaction;
use xiom.io;

var t = txn_new();              // idle
txn_begin(&mut t);              // active, ops 0
txn_add_op(&mut t);             // ops 1
txn_savepoint(&mut t, "mid");   // "mid" anchored at 1
txn_add_op(&mut t);             // ops 2
let rewound = txn_rollback_to(&mut t, "mid");   // Ok(1), ops back to 1
let committed = txn_commit(&mut t);             // Ok(1), state committed

io.println(txn_state(&t));      // 2
io.println(txn_op_count(&t));   // 1
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.transaction
```

Expected: the namespaced module passes the section-4 namespace rule, 22
`[PASS]` lines, and a final `port: PASS (passed=22 failed=0 program_exit=0
exit=0)`.

## Limitations

- **In-memory bookkeeping only.** A `Txn` is a plain value in the caller's
  memory. Nothing is written anywhere: there is no storage engine, no buffer
  pool, no two-phase commit, and no effect on any external system. "Commit"
  and "rollback" only record the lifecycle transition and the operation
  counts.
- **No logging or durability.** There is no write-ahead log, no fsync, no
  snapshot, no crash recovery, and no audit trail. A lost `Txn` value loses
  its whole history; nothing survives the process.
- **No concurrency control.** There are no locks, no isolation levels, no
  conflict detection, and no visibility rules between transactions. Two `Txn`
  values are independent and never interact.
- **Savepoint records linger after the transaction ends.** `txn_commit` and
  `txn_rollback` keep the savepoint names and marks as inert bookkeeping
  (readable through the accessors) until the next `txn_begin` clears them;
  `txn_savepoint`, `txn_rollback_to` and `txn_release` refuse to work on a
  non-active record.
- **Linear savepoint lookup.** Savepoint operations scan the name list, so
  they are O(n) in the number of savepoints; the state and op-count accessors
  are O(1).
- Not thread-safe; the types are plain values with no internal locking.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
