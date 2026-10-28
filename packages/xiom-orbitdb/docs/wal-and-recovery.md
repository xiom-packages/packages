<!--
Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
SPDX-License-Identifier: MIT OR Apache-2.0
-->

# WAL & Recovery

The write-ahead log makes xiom-db recoverable. It is the ordered history of every mutation, written **before** the change reaches the index. Recovery replays that history onto an empty tree to reconstruct exact state.

> **Status:** Phase 0 -- the engine facade's WAL is an in-memory `Vec[WALEntry]`. Correctness (ordering, replay) is real. Phase 1 adds a durable sibling: the `src/wal_file.xi` segment and the `DBFile` checkpoint path, documented at the end of this page (process-crash safe; no fsync yet).

## Record -- `wal/wal_record.xi`

```
WALOpType = InsertOp | UpdateOp | DeleteOp
WALEntry  = { op: WALOpType, key: Int, value: Int, timestamp: Int }
```

`timestamp` is the engine's monotonic counter -- it establishes a total order over the log. `wal_entry_new(op, key, value, timestamp)` constructs one.

## Log -- `xiom.db.engine.core` (`src/engine/core.xi`)

```
WAL = { entries: Vec[WALEntry] }
```

| Function | Contract | Effect |
|----------|----------|--------|
| `wal_new()` | -- | Empty log. |
| `wal_append(wal, entry)` | -- | Append one record (append-only). |
| `wal_replay(wal, &mut tree)` | -- | Reapply all records in order; returns `Bool`. |
| `wal_clear(wal)` | -- | Empty the log (checkpoint). |
| `wal_truncate(wal, before_ts)` | `requires: before_timestamp >= 0` | Drop records older than a boundary. |
| `wal_len` / `wal_is_empty` / `wal_entry_count` | -- | Introspection. |

## The WAL-before-data rule

The engine guarantees this ordering for **every** mutation:

```
1. assign monotonic timestamp
2. wal_append(...)        <- the log records the intent
3. btree_insert/delete    <- only then is the index changed
```

Consequence: the index is always a *projection* of the log. If a failure interrupts step 3, the log still contains the operation and replay will apply it. The reverse is impossible -- you can rebuild the tree from the log, never the log from the tree.

## Replay semantics -- `wal_replay`

Records are applied in log order:

| Op | Action | On failure |
|----|--------|------------|
| `InsertOp` | `btree_insert(key, value)` | duplicate key -> mark `success = false`, continue |
| `UpdateOp` | `btree_search`; if present, `btree_delete` then `btree_insert` | missing key -> `success = false` |
| `DeleteOp` | `btree_delete(key)` | missing key -> `success = false` |

`wal_replay` returns `false` if **any** record failed to apply, but it **does not stop** -- it applies every remaining record so recovery restores as much valid state as possible (partial recovery).

## Recovery lifecycle -- `engine_recover`

```
engine_recover(eng):
  1. eng.tree = btree_new(eng.tree.order)   // fresh empty index
  2. eng.timestamp_counter = 0
  3. return wal_replay(&eng.wal, &mut eng.tree)
```

`db_recover` on the facade delegates here. After it returns, the index reflects exactly the logged history; the boolean tells the caller whether every record applied cleanly.

## Checkpointing

A checkpoint bounds how much log recovery must replay:

- `engine_flush_wal()` (`wal_clear`) -- the state is safe; discard the whole log.
- `engine_truncate_wal(before_ts)` -- discard only records older than a durable boundary.

`db_close` performs a checkpoint (`engine_flush_wal`) before marking the handle closed.

## Durable segment and DBFile recovery (Phase 1)

`src/wal_file.xi` is the on-disk half of the contract: one record per line
(`lsn|op|key|value|timestamp[|p0,p1,...]`; op codes 1..7 including the
Checkpoint anchor), strictly monotonic LSNs, malformed/torn lines skipped on
replay, and a torn tail healed once per handle (`heal_needed`). `wal_file_open`
resumes `next_lsn` from the last valid record; `wal_file_truncate(path, from)`
rewrites the segment keeping records with `lsn >= from` (temp + rename), and
preserves payloads.

`DBFile` (`src/engine.xi`) applies WAL-before-ack: `db_file_put` /
`db_file_delete` append the record first, then mutate the in-memory tree.
`db_file_open` recovers by loading the checkpoint snapshot (when present) and
replaying **only** records with `lsn > checkpoint_lsn`; without a snapshot it
replays the whole segment.

## DBFile checkpoint

`db_file_checkpoint(db)` commits an incremental snapshot and bounds replay:

```
1. append new versions of only the DIRTY tree nodes (NodeStore dirty flags,
   set by every mutation and cleared after a successful commit) at the next
   generation (page id = generation*2^32 + node_idx + 1) into <wal path>.snap
2. append the header page LAST (generation, root, order, node_count,
   snapshot_lsn) -- the highest-generation header commits the generation
3. append the Checkpoint anchor:
   lsn|6|snapshot_lsn|root|0|generation,node_count,order
4. wal_file_truncate(path, anchor)  -- keeps lsn >= anchor, so the anchor
   itself survives and next_lsn resumes past it
```

Recovery loads the newest committed header generation and resolves each node
as the newest generation <= it; node pages from an uncommitted crash window
(newer generation, no header) are ignored, and the next checkpoint forces a
full write of the generation when it detects such leftovers. Every step leaves
a recoverable state: a crash mid-append leaves the previous header in force; a
crash after the header but before the anchor is healed on open by the
snapshot's `checkpoint_lsn` gate (records at or below it are skipped); a failed
truncate leaves records that the same gate skips. When the log grows past
`node_count + 64` entries, compaction rewrites it atomically. The segment is
never truncated to empty -- the LSN counter lives in the anchor record.

`db_file_maybe_checkpoint(db, limit)` is the policy hook: it checkpoints when
at least `limit` records were appended since the last checkpoint (returns the
anchor LSN), or returns -1 below the threshold.

## Durable transactions (DBFile)

`DBFile` supports one active transaction per handle:

```
db_file_txn_begin     -> BeginTxn record (code 8)
db_file_txn_put/delete-> operation records (code 2 upsert / code 3 delete)
db_file_txn_commit    -> CommitTxn record (code 9), then buffered ops apply
db_file_txn_abort     -> AbortTxn record (code 10), buffer discarded
```

Operations are logged as they happen (WAL-before-ack) but touch the tree only
at commit, so abort is a buffer discard -- no physical undo pass. Recovery
classifies committed vs uncommitted at the Begin/Commit records: ops inside an
unterminated window are dropped; a committed window applies at its commit
record. Opening a segment with a dangling window appends an explicit
`AbortTxn`, so writes made after recovery are not replayed inside the stale
window. While a transaction is active, auto-commit `db_file_put` /
`db_file_delete` and `db_file_checkpoint` / `db_file_maybe_checkpoint` are
rejected -- a checkpoint must not truncate a pending transaction's records.

Limits: single active transaction, no isolation/MVCC (readers see committed
state), and no automatic retry on IO failure (returns `false` / `-1`).

## Phase 2 direction

| Now | Phase 2 |
|-----|---------|
| `Vec[WALEntry]` in RAM | append-only segment file |
| integer `timestamp` | `xiom.core.ids.Lsn` (log sequence number) |
| `wal_clear` checkpoint | `xiom.core.wal.checkpoint` + segment truncation |
| implicit durability | explicit fsync on commit via core FFI |

The in-memory WAL boundary (`xiom.db.engine.core`) is exactly where `xiom.core.wal.wal_writer` is substituted, with no change to the engine's call sites.
