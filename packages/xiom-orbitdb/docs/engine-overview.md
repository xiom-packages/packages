<!--
Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
SPDX-License-Identifier: MIT OR Apache-2.0
-->

# Engine Overview

`xiom.db.engine` (`src/engine.xi`) is the public facade: it owns the `DBFile`
type and the file-backed API, plus the legacy in-memory `Database` facade. The
in-memory coordinator itself (`Engine`) lives in `xiom.db.engine.core`
(`src/engine/core.xi`, R1 split 2026-10-18) together with the WAL buffer and
the Query/planner layer; `engine/snapshot.xi` holds the checkpoint machinery
and `engine/txn.xi` the durable transaction window. It is deliberately thin:
it owns write ordering and timestamps, and delegates everything else.

The `Engine` value below is the legacy in-memory coordinator in
`xiom.db.engine.core`; the durable equivalent is `DBFile` in
`xiom.db.engine`.

## The `Engine` value

```
Engine = {
  tree: BTree,              // the index (xiom.db.index.btree)
  wal: WAL,                 // the write-ahead log (xiom.db.wal.wal)
  timestamp_counter: Int,   // monotonic ordering source
}
```

`engine_new(order)` (`requires: order >= 3`) creates a fresh empty tree and an empty WAL.

## The write path (WAL-before-data)

Every mutation follows the same three steps, in this exact order:

```
engine_insert(key, value):
  1. ts = next_timestamp()                       // strictly increasing
  2. wal_append(WALEntry{InsertOp, key, value, ts})   // durability intent first
  3. btree_insert(tree, key, value)              // then mutate the index
```

`engine_delete` and `engine_update` follow the same shape (logging `DeleteOp` / `UpdateOp`). `engine_update` and `engine_delete` first confirm the key exists (returning `false` if not) so the log only ever records applicable operations.

**Why this ordering matters:** if the process stops between steps 2 and 3, the operation is still in the log and will be reapplied by recovery. The index can always be rebuilt from the log; the log can never be rebuilt from the index.

## The read path

- `engine_get(key)` -> `btree_search` (O(log n)), returns `Option[Int]`.
- `engine_range_query(low, high)` (`requires: low <= high`) -> `btree_range_query`.
- `engine_query(query)` -> delegates to `query_execute` (see [query-pipeline.md](query-pipeline.md)).
- `engine_size()` -> `btree_size`.

Reads never touch the WAL and never mutate state.

## Maintenance & recovery

| Function | Effect |
|----------|--------|
| `engine_recover()` | Rebuild the tree from the WAL (see [wal-and-recovery.md](wal-and-recovery.md)). |
| `engine_flush_wal()` | Checkpoint: clear the WAL. |
| `engine_truncate_wal(before_ts)` | Drop log entries older than a checkpoint boundary. |
| `engine_wal_size()` | Current WAL length. |

## Relationship to the facade

`xiom.db.api.database` wraps `Engine` and is the intended entry point for applications. It adds an `open` flag (a closed database rejects operations) and a stable verb-first API, but contains no logic of its own -- each `db_*` function delegates to the matching `engine_*` function. Keeping the engine free of lifecycle concerns keeps it easy to test and reuse.
