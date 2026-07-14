# WAL & Recovery

The write-ahead log makes xiom-db recoverable. It is the ordered history of every mutation, written **before** the change reaches the index. Recovery replays that history onto an empty tree to reconstruct exact state.

> **Status:** Phase 0 — the WAL is an in-memory `Vec[WALEntry]`. Correctness (ordering, replay) is real; durability across a true process crash arrives in Phase 2 when the log is backed by an fsync'd segment file.

## Record — `wal/wal_record.xi`

```
WALOpType = InsertOp | UpdateOp | DeleteOp
WALEntry  = { op: WALOpType, key: Int, value: Int, timestamp: Int }
```

`timestamp` is the engine's monotonic counter — it establishes a total order over the log. `wal_entry_new(op, key, value, timestamp)` constructs one.

## Log — `wal/wal.xi`

```
WAL = { entries: Vec[WALEntry] }
```

| Function | Contract | Effect |
|----------|----------|--------|
| `wal_new()` | — | Empty log. |
| `wal_append(wal, entry)` | — | Append one record (append-only). |
| `wal_replay(wal, &mut tree)` | — | Reapply all records in order; returns `Bool`. |
| `wal_clear(wal)` | — | Empty the log (checkpoint). |
| `wal_truncate(wal, before_ts)` | `requires: before_timestamp >= 0` | Drop records older than a boundary. |
| `wal_len` / `wal_is_empty` / `wal_entry_count` | — | Introspection. |

## The WAL-before-data rule

The engine guarantees this ordering for **every** mutation:

```
1. assign monotonic timestamp
2. wal_append(...)        ← the log records the intent
3. btree_insert/delete    ← only then is the index changed
```

Consequence: the index is always a *projection* of the log. If a failure interrupts step 3, the log still contains the operation and replay will apply it. The reverse is impossible — you can rebuild the tree from the log, never the log from the tree.

## Replay semantics — `wal_replay`

Records are applied in log order:

| Op | Action | On failure |
|----|--------|------------|
| `InsertOp` | `btree_insert(key, value)` | duplicate key → mark `success = false`, continue |
| `UpdateOp` | `btree_search`; if present, `btree_delete` then `btree_insert` | missing key → `success = false` |
| `DeleteOp` | `btree_delete(key)` | missing key → `success = false` |

`wal_replay` returns `false` if **any** record failed to apply, but it **does not stop** — it applies every remaining record so recovery restores as much valid state as possible (partial recovery).

## Recovery lifecycle — `engine_recover`

```
engine_recover(eng):
  1. eng.tree = btree_new(eng.tree.order)   // fresh empty index
  2. eng.timestamp_counter = 0
  3. return wal_replay(&eng.wal, &mut eng.tree)
```

`db_recover` on the facade delegates here. After it returns, the index reflects exactly the logged history; the boolean tells the caller whether every record applied cleanly.

## Checkpointing

A checkpoint bounds how much log recovery must replay:

- `engine_flush_wal()` (`wal_clear`) — the state is safe; discard the whole log.
- `engine_truncate_wal(before_ts)` — discard only records older than a durable boundary.

`db_close` performs a checkpoint (`engine_flush_wal`) before marking the handle closed.

## Phase 2 direction

| Now | Phase 2 |
|-----|---------|
| `Vec[WALEntry]` in RAM | append-only segment file |
| integer `timestamp` | `xiom.core.ids.Lsn` (log sequence number) |
| `wal_clear` checkpoint | `xiom.core.wal.checkpoint` + segment truncation |
| implicit durability | explicit fsync on commit via core FFI |

The `wal/wal.xi` module boundary is exactly where `xiom.core.wal.wal_writer` is substituted, with no change to the engine's call sites.
