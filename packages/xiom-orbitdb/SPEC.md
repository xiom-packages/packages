<!--
Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
SPDX-License-Identifier: MIT OR Apache-2.0
-->

# XiomDB Specification

> Version 0.2.0 -- layered, self-contained architecture (the `xiom-core` substrate extraction is planned; its seams are marked).

## Architecture Overview

XiomDB is a production-grade embedded database written in pure XIOM. It is organized as a set of layered modules, each owning one concern, and is **self-contained** today (the shared `xiom-core` durable-systems substrate -- IDs, errors, config, contracts, metrics -- is the planned extraction; the retired folds are noted below). This document describes the module structure, contracts, and execution model. For the narrative architecture and ownership rules see [ARCHITECTURE.md](ARCHITECTURE.md); for subsystem deep-dives see [`docs/`](docs/).

### Layer Diagram

```
+--------------------------------------------------------------+
|  engine.xi              Public facade (DBFile + Database)     |
|--------------------------------------------------------------|
|  engine/core.xi         in-memory WAL/query/legacy Engine     |
|  engine/snapshot.xi     checkpoint codec + snapshot pins      |
|  engine/txn.xi          durable txn window + savepoints       |
|---------------+---------------+---------------+--------------|
|  index/       |  txn/         |  storage/     |  catalog/     |
|  btree        |  transaction  |  page,tuple   |  schema,val.  |
|---------------+---------------+---------------+--------------|
|  storage/ page_file, block, block_store, byte_io, fault, fsm  |
|--------------------------------------------------------------|
|  Foundations: error - ids - config - contracts                |
|--------------------------------------------------------------|
|  (self-contained today; xiom-core substrate extraction planned) |
`--------------------------------------------------------------+
```

### Module Dependency Graph

```
engine.xi             ---> engine/core.xi, engine/snapshot.xi, engine/txn.xi,
                          index/btree.xi, wal_file.xi, storage/*, catalog/*
engine/core.xi        ---> engine.xi (DBFile), index/btree.xi, storage/tuple.xi,
                          secondary_index.xi
engine/snapshot.xi    ---> engine.xi (DBFile), engine/core.xi, index/btree.xi,
                          storage/page_file,block,block_store,byte_io, wal_file.xi
engine/txn.xi         ---> engine.xi (DBFile), engine/core.xi, index/btree.xi,
                          storage/byte_io, wal_file.xi
index/btree.xi        ---> (self-contained)
catalog/schema_validator.xi ---> catalog/schema.xi, error.xi
storage/page.xi       ---> config.xi
storage/tuple.xi      ---> error.xi
storage/free_space_map.xi ---> (self-contained)
config.xi         ---> (self-contained)
contracts.xi      ---> (self-contained)
error.xi          ---> (self-contained)
ids.xi            ---> (self-contained)
index/btree.xi    ---> (self-contained)
txn/transaction.xi---> (self-contained)
```

---

## Foundations

### `xiom.db.error` -- `src/error.xi`
Typed error domain. `DbError` = `NotFound | DuplicateKey | ConstraintViolation | SchemaMismatch | StorageError | Corruption`. `DbResult[T] = Result[T, DbError]` is the fallible-return convention for the whole package; `DbError.is_retryable` marks only `StorageError` as retryable. The `xiom.core.error.CoreError` fold was retired 2026-10-10 (the substrate package was never published; see `docs/COMPILER-FINDINGS-ORBITDB.md` C-ORBIT-06).

### `xiom.db.ids` -- `src/ids.xi`
Strongly-typed `RowId` and `TableId` struct wrappers (with `row_id` / `table_id` constructors and accessors). Lower-level identities are local wrappers today (`PageId` mirrors the planned `xiom.core.ids.PageId`); `row_id_to_page_id` bridges `RowId` into the PageId space.

### `xiom.db.config` -- `src/config.xi`
`DatabaseConfig` (page_size, buffer_pool_capacity, wal_enabled, btree_order) with `default()`, `database_config_validate` (page size valid + capacity >= 1 + order >= 3). The `CoreConfig` projection was retired 2026-10-10 with the substrate fold.

### `xiom.db.contracts` -- `src/contracts.xi`
Shared predicates: `valid_btree_order`, `valid_key`, `sorted_keys` (strictly ascending), `valid_range`, `non_decreasing` (delegates to `xiom.core.contracts.is_sorted_ints`).

---

## Storage Layer

### `xiom.db.storage.page` -- `src/storage/page.xi`
- `Page`: id (UInt64), data (Vec[UInt8]), checksum (UInt32); `Page.is_valid()` re-checksums; `page_compute_checksum` seals a buffer.
- `BufferPool`: direct-mapped cache (`id % capacity`) with hit/miss accounting and `hit_ratio`.
- `StorageEngine`: `DatabaseConfig` + `BufferPool` with `cache_page` / `lookup_page`.

### `xiom.db.storage.tuple` -- `src/storage/tuple.xi`
- `Row`: id + `Vec[Int]` column data; `get_column` / `set_column` / `column_count`.
- `tuple_encode` / `tuple_decode` (`DbResult[Row]`): the codec seam (Phase 1 hardens to byte-packed pages).
- `ResultSet`: `columns: Vec[Str]` (fixed from the old `Vec<Str>` bug) + rows.

### `xiom.db.storage.free_space_map` -- `src/storage/free_space_map.xi` *(scaffold, Phase 1)*
`FreeSpaceMap` per-page free-byte tracking with `fsm_register_page`, `fsm_record_used`, `fsm_find_page` -- placeholder linear scan to be replaced by an on-disk FSM tree.

---

## Catalog Layer

### `xiom.db.catalog.schema` -- `src/catalog/schema.xi`
Data dictionary: `ColumnType`, `ColumnDef`, `Schema` (with `column_index`, `column_count`), `IndexType`, `IndexDef`.

### `xiom.db.catalog.schema_validator` -- `src/catalog/schema_validator.xi`
`validate_schema` (>=1 column, primary key in range, unique names), `validate_column`, `validate_index` -- all returning `DbResult[Bool]`.

---

## WAL Layer

### `xiom.db.wal.wal_record` -- now in `src/engine/core.xi` (tombstone at `src/wal/wal_record.xi`)
`WALOpType` = `InsertOp | UpdateOp | DeleteOp`; `WALEntry` (op, key, value, timestamp); `wal_entry_new`.

### `xiom.db.wal.wal` -- now in `src/engine/core.xi` (tombstone at `src/wal/wal.xi`)
`WAL` = ordered `Vec[WALEntry]`. `wal_new`, `wal_append`, `wal_replay(&WAL, &mut BTree) -> Bool`, `wal_clear`, `wal_truncate` (`requires: before_timestamp >= 0`), `wal_len`, `wal_is_empty`, `wal_entry_count`. Imports `xiom.db.index.btree` for replay.

**Replay semantics:** `InsertOp` -> `btree_insert`; `UpdateOp` -> delete+insert (fails if missing); `DeleteOp` -> `btree_delete`. Returns `false` if any entry failed, but continues to maximize partial recovery.

---

## Transaction Layer

### `xiom.db.txn.transaction` -- `src/txn/transaction.xi`
`WALOp` = `Insert | Update | Delete`; `TxState` = `Active | Committed | Aborted`; `Transaction` (id, state, operations) with `new` / `commit` / `abort` / `add_op` / `is_active`. State machine only -- isolation lands in Phase 3.

---

## Index Layer

### `xiom.db.index.btree` -- `src/index/btree.xi`
The canonical, WORKING B-tree. Flat-array representation (`Vec[BTreeNode]` + integer child indices) to satisfy the borrow checker. `btree_new` (`requires: order >= 3`), `btree_insert`, `btree_search`, `btree_delete`, `btree_range_query` (`requires: low <= high`), `btree_min`, `btree_max`, `btree_size`, `btree_to_vec`. Complexity: search/insert/delete O(log n), range O(log n + k).

> The previous `btree_stdlib.xi` (which called non-existent `BTreeMap.range/iter/first/last`) has been **removed**; the flat-array module is the single source of truth.

---

## Query Layer

### `xiom.db.query.query` -- now in `src/engine/core.xi` (tombstone at `src/query/query.xi`)
`QueryOp` (Eq/Neq/Lt/Lte/Gt/Gte), `QueryCondition`, `Query`. Builder: `query_new`, `query_where`, `query_limit` (`requires: limit > 0`), `query_offset` (`requires: offset >= 0`). `query_execute(&Query, &BTree)` scans in-order, filters by AND, applies offset then limit. Imports `xiom.db.index.btree`.

### `xiom.db.query.planner` -- now in `src/engine/core.xi` (tombstone at `src/query/planner.xi`)
`PlanKind` (FullScan/IndexRange/PointLookup), `QueryPlan`, `plan_query`, `execute_plan` -- currently degrade to full scan; will push key predicates into `btree_range_query`.

---

## Engine & API

### `xiom.db.engine` -- `src/engine.xi` (facade)

Owns the public `DBFile` type and the file-backed API: `db_file_open[_cfg]`,
`db_file_open_checked[_cfg]`, `db_file_put[_typed]`, `db_file_delete`,
`db_file_get[_typed]`, `db_file_range`, `db_file_query[_typed]`, the secondary
index API, `db_file_flush`, the durability setters, and the legacy in-memory
`Database` facade (`db_open`, `db_insert`, ...). Re-exports the implementation
modules with `pub use` so the 0.2.x import surface is unchanged.

### `xiom.db.engine.core` -- `src/engine/core.xi`

The in-memory core: `WALEntry`/`WAL` (append/replay/truncate/clear), the
`Query` builder + planner, the legacy `Engine` (`engine_new` -- `requires:
order >= 3` -- `engine_insert/get/update/delete/query/range_query/recover/
size/wal_size/flush_wal/truncate_wal`), and the shared `DBFile` helpers
(`db_file_apply_record`, `db_wal_size`, `db_file_guard`, index maintenance).

### `xiom.db.engine.snapshot` -- `src/engine/snapshot.xi`

Checkpoint/snapshot machinery: v1 page-log and v2 block-store codecs,
strict load, generation-committed commit, compaction, migration, plus the M3
snapshot-pin read views (`db_file_snapshot_*`, `db_file_min_pinned_lsn`).

### `xiom.db.engine.txn` -- `src/engine/txn.xi`

The durable single-active-transaction API (`db_file_txn_begin/put/delete/
commit/abort`, held append fd, `TxOp` buffer) and txn-scoped savepoints
(`db_file_txn_savepoint*`).

### `xiom.db.api.database` -- `src/api/database.xi` (tombstone)

Merged into `xiom.db.engine`; the `Database` facade (`db_open` /
`db_open_with`, `db_insert`, `db_get`, `db_update`, `db_delete`, `db_query`,
`db_range`, `db_size`, `db_recover`, `db_close`) lives in `src/engine.xi`.
Rejects operations on a closed handle; delegates everything to `engine_*`.

---

## Design Notes

### Flat Array B-Tree
XIOM's borrow checker prohibits `&BTreeNode` fields, so nodes live in a flat `Vec` addressed by integer indices. Splits/merges append nodes and rewrite parent indices. O(log n) access preserved.

### WAL Before Data
All mutations log to the WAL first, then apply to the index. After a crash, `engine_recover` rebuilds the tree from the log. See [docs/wal-and-recovery.md](docs/wal-and-recovery.md).

### Monotonic Timestamps
The engine uses an internal integer counter (not wall-clock) for WAL ordering -- strict ordering, no clock skew.

### Error Strategy
Public operations return `Bool` / `Option[T]`; fallible internal operations return `DbResult[T]`. `DbError` is a stable, coarse domain. See [docs/error-catalog.md](docs/error-catalog.md).

---

## File Layout

```
packages/xiom-db/
|-- package.xi           # Manifest (depends on xiom-core)
|-- README.md
|-- ARCHITECTURE.md
|-- ROADMAP.md
|-- SPEC.md              # This document
|-- docs/                # Subsystem deep-dives
`-- src/                 # Layered modules (see Module Dependency Graph)
```
