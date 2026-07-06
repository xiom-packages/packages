# XiomDB Specification

> Version 0.2.0 — layered architecture on top of the `xiom-core` substrate.

## Architecture Overview

XiomDB is a production-grade embedded database written in pure XIOM. It is organized as a set of layered modules, each owning one concern, and depends on `xiom-core` for the shared durable-systems substrate (IDs, errors, config, contracts, metrics). This document describes the module structure, contracts, and execution model. For the narrative architecture and ownership rules see [ARCHITECTURE.md](ARCHITECTURE.md); for subsystem deep-dives see [`docs/`](docs/).

### Layer Diagram

```
┌──────────────────────────────────────────────────────────────┐
│  api/database.xi        Public facade (Database)               │
├──────────────────────────────────────────────────────────────┤
│  engine.xi              Internal coordinator (Engine)          │
├───────────────┬───────────────┬───────────────┬──────────────┤
│  query/       │  wal/         │  index/       │  txn/         │
│  query,planner│  wal,record   │  btree        │  transaction  │
├───────────────┴───────────────┴───────────────┴──────────────┤
│  catalog/ schema, schema_validator                            │
├──────────────────────────────────────────────────────────────┤
│  storage/ page, tuple, free_space_map                         │
├──────────────────────────────────────────────────────────────┤
│  Foundations: error · ids · config · contracts                │
├──────────────────────────────────────────────────────────────┤
│  xiom-core: error · ids · config · limits · contracts · metrics│
└──────────────────────────────────────────────────────────────┘
```

### Module Dependency Graph

```
api/database.xi   ──→ engine.xi, query/query.xi, config.xi
engine.xi         ──→ index/btree.xi, wal/wal.xi, wal/wal_record.xi, query/query.xi
query/query.xi    ──→ index/btree.xi
query/planner.xi  ──→ query/query.xi, index/btree.xi
wal/wal.xi        ──→ wal/wal_record.xi, index/btree.xi
catalog/schema_validator.xi ──→ catalog/schema.xi, error.xi
storage/page.xi   ──→ config.xi
storage/tuple.xi  ──→ error.xi
storage/free_space_map.xi ──→ xiom.core.ids
config.xi         ──→ xiom.core.config, xiom.core.contracts, xiom.core.limits
contracts.xi      ──→ xiom.core.contracts
error.xi          ──→ xiom.core.error
ids.xi            ──→ xiom.core.ids
index/btree.xi    ──→ (self-contained)
txn/transaction.xi──→ (self-contained)
```

---

## Foundations

### `xiom.db.error` — `src/error.xi`
Typed error domain. `DbError` = `NotFound | DuplicateKey | ConstraintViolation | SchemaMismatch | StorageError | Corruption`. `DbResult[T] = Result[T, DbError]` is the fallible-return convention for the whole package. `db_error_from_core` folds a `xiom.core.error.CoreError` into this domain; `DbError.is_retryable` marks only `StorageError` as retryable.

### `xiom.db.ids` — `src/ids.xi`
Strongly-typed `RowId` and `TableId` struct wrappers (with `row_id` / `table_id` constructors and accessors). Lower-level identities (`PageId`, `Lsn`, `TxnId`) are re-used from `xiom.core.ids`; `row_id_to_page_id` bridges into the core PageId space.

### `xiom.db.config` — `src/config.xi`
`DatabaseConfig` (page_size, buffer_pool_capacity, wal_enabled, btree_order) with `default()`, `database_config_validate` (page size valid + capacity ≥ 1 + order ≥ 3), and `database_config_from_core` to project a `CoreConfig`.

### `xiom.db.contracts` — `src/contracts.xi`
Shared predicates: `valid_btree_order`, `valid_key`, `sorted_keys` (strictly ascending), `valid_range`, `non_decreasing` (delegates to `xiom.core.contracts.is_sorted_ints`).

---

## Storage Layer

### `xiom.db.storage.page` — `src/storage/page.xi`
- `Page`: id (UInt64), data (Vec[UInt8]), checksum (UInt32); `Page.is_valid()` re-checksums; `page_compute_checksum` seals a buffer.
- `BufferPool`: direct-mapped cache (`id % capacity`) with hit/miss accounting and `hit_ratio`.
- `StorageEngine`: `DatabaseConfig` + `BufferPool` with `cache_page` / `lookup_page`.

### `xiom.db.storage.tuple` — `src/storage/tuple.xi`
- `Row`: id + `Vec[Int]` column data; `get_column` / `set_column` / `column_count`.
- `tuple_encode` / `tuple_decode` (`DbResult[Row]`): the codec seam (Phase 1 hardens to byte-packed pages).
- `ResultSet`: `columns: Vec[Str]` (fixed from the old `Vec<Str>` bug) + rows.

### `xiom.db.storage.free_space_map` — `src/storage/free_space_map.xi` *(scaffold, Phase 1)*
`FreeSpaceMap` per-page free-byte tracking with `fsm_register_page`, `fsm_record_used`, `fsm_find_page` — placeholder linear scan to be replaced by an on-disk FSM tree.

---

## Catalog Layer

### `xiom.db.catalog.schema` — `src/catalog/schema.xi`
Data dictionary: `ColumnType`, `ColumnDef`, `Schema` (with `column_index`, `column_count`), `IndexType`, `IndexDef`.

### `xiom.db.catalog.schema_validator` — `src/catalog/schema_validator.xi`
`validate_schema` (≥1 column, primary key in range, unique names), `validate_column`, `validate_index` — all returning `DbResult[Bool]`.

---

## WAL Layer

### `xiom.db.wal.wal_record` — `src/wal/wal_record.xi`
`WALOpType` = `InsertOp | UpdateOp | DeleteOp`; `WALEntry` (op, key, value, timestamp); `wal_entry_new`.

### `xiom.db.wal.wal` — `src/wal/wal.xi`
`WAL` = ordered `Vec[WALEntry]`. `wal_new`, `wal_append`, `wal_replay(&WAL, &mut BTree) -> Bool`, `wal_clear`, `wal_truncate` (`requires: before_timestamp >= 0`), `wal_len`, `wal_is_empty`, `wal_entry_count`. Imports `xiom.db.index.btree` for replay.

**Replay semantics:** `InsertOp` → `btree_insert`; `UpdateOp` → delete+insert (fails if missing); `DeleteOp` → `btree_delete`. Returns `false` if any entry failed, but continues to maximize partial recovery.

---

## Transaction Layer

### `xiom.db.txn.transaction` — `src/txn/transaction.xi`
`WALOp` = `Insert | Update | Delete`; `TxState` = `Active | Committed | Aborted`; `Transaction` (id, state, operations) with `new` / `commit` / `abort` / `add_op` / `is_active`. State machine only — isolation lands in Phase 3.

---

## Index Layer

### `xiom.db.index.btree` — `src/index/btree.xi`
The canonical, WORKING B-tree. Flat-array representation (`Vec[BTreeNode]` + integer child indices) to satisfy the borrow checker. `btree_new` (`requires: order >= 3`), `btree_insert`, `btree_search`, `btree_delete`, `btree_range_query` (`requires: low <= high`), `btree_min`, `btree_max`, `btree_size`, `btree_to_vec`. Complexity: search/insert/delete O(log n), range O(log n + k).

> The previous `btree_stdlib.xi` (which called non-existent `BTreeMap.range/iter/first/last`) has been **removed**; the flat-array module is the single source of truth.

---

## Query Layer

### `xiom.db.query.query` — `src/query/query.xi`
`QueryOp` (Eq/Neq/Lt/Lte/Gt/Gte), `QueryCondition`, `Query`. Builder: `query_new`, `query_where`, `query_limit` (`requires: limit > 0`), `query_offset` (`requires: offset >= 0`). `query_execute(&Query, &BTree)` scans in-order, filters by AND, applies offset then limit. Imports `xiom.db.index.btree`.

### `xiom.db.query.planner` — `src/query/planner.xi` *(scaffold, Phase 3)*
`PlanKind` (FullScan/IndexRange/PointLookup), `QueryPlan`, `plan_query`, `execute_plan` — currently degrade to full scan; will push key predicates into `btree_range_query`.

---

## Engine & API

### `xiom.db.engine` — `src/engine.xi`
`Engine` (tree, wal, timestamp_counter). Coordinates WAL-before-data writes. `engine_new` (`requires: order >= 3`), `engine_insert/get/update/delete/query/range_query/recover/size/wal_size/flush_wal/truncate_wal`. Imports btree, wal, wal_record, query.

### `xiom.db.api.database` — `src/api/database.xi`
Public facade `Database` (engine + open flag). `db_open` / `db_open_with`, `db_insert`, `db_get`, `db_update`, `db_delete`, `db_query`, `db_range`, `db_size`, `db_recover`, `db_close`. Rejects operations on a closed handle; delegates everything to `engine_*`.

---

## Design Notes

### Flat Array B-Tree
XIOM's borrow checker prohibits `&BTreeNode` fields, so nodes live in a flat `Vec` addressed by integer indices. Splits/merges append nodes and rewrite parent indices. O(log n) access preserved.

### WAL Before Data
All mutations log to the WAL first, then apply to the index. After a crash, `engine_recover` rebuilds the tree from the log. See [docs/wal-and-recovery.md](docs/wal-and-recovery.md).

### Monotonic Timestamps
The engine uses an internal integer counter (not wall-clock) for WAL ordering — strict ordering, no clock skew.

### Error Strategy
Public operations return `Bool` / `Option[T]`; fallible internal operations return `DbResult[T]`. `DbError` is a stable, coarse domain; message-bearing detail rides `CoreError` from lower layers. See [docs/error-catalog.md](docs/error-catalog.md).

---

## File Layout

```
ecosystem/xiom-db/
├── package.xi           # Manifest (depends on xiom-core)
├── README.md
├── ARCHITECTURE.md
├── ROADMAP.md
├── SPEC.md              # This document
├── docs/                # Subsystem deep-dives
└── src/                 # Layered modules (see Module Dependency Graph)
```
