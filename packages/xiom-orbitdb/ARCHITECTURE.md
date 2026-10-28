<!--
Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
SPDX-License-Identifier: MIT OR Apache-2.0
-->

# XiomDB Architecture

> The internal design of xiom-db 0.2.0: module tree, ownership rules, contract hotspots, typed error domains, on-disk layout, and the recovery lifecycle.

xiom-db is a **layered** embedded database. Each layer owns exactly one concern and depends only on layers below it. The tree is **self-contained** today (no external substrate): the shared `xiom-core` substrate (IDs, errors, config, contracts, limits, metrics) remains the planned extraction target, and the seams where it will plug in are marked in the module headers and `docs/storage-layout.md`.

---

## 1. Module Tree (file-by-file)

```
src/
|-- error.xi         xiom.db.error             DbError enum, DbResult convention
|-- ids.xi           xiom.db.ids               RowId / TableId wrappers
|-- config.xi        xiom.db.config            DatabaseConfig, validation
|-- contracts.xi     xiom.db.contracts         valid_key, sorted_keys, valid_range, order checks
|
|-- storage/
|   |-- page.xi              xiom.db.storage.page            Page, checksum, BufferPool, StorageEngine
|   |-- tuple.xi             xiom.db.storage.tuple           Row, ResultSet, tuple_encode/decode, TValue
|   |-- page_file.xi         xiom.db.storage.page_file       durable v1 page file + page log
|   |-- block.xi             xiom.db.storage.block           byte-page v2 codec (pure)
|   |-- block_store.xi       xiom.db.storage.block_store     v2 block store
|   |-- byte_io.xi           xiom.db.storage.byte_io         byte-IO sync/open shim (fault-gated)
|   |-- fault.xi             xiom.db.storage.fault           deterministic fault injector
|   `-- free_space_map.xi    xiom.db.storage.free_space_map  FreeSpaceMap (scaffold, Phase 1)
|
|-- catalog/
|   |-- schema.xi            xiom.db.catalog.schema           ColumnDef, Schema, IndexDef
|   |-- schema_row.xi        xiom.db.catalog.schema_row       typed row <-> schema encoder
|   `-- schema_validator.xi  xiom.db.catalog.schema_validator validate_schema/column/index
|
|-- txn/
|   `-- transaction.xi       xiom.db.txn.transaction  Transaction, TxState, WALOp
|
|-- index/
|   |-- btree.xi             xiom.db.index.btree      Flat-array B-tree, NodeStore, COW pins, v2 pager cache
|   `-- node_page.xi         xiom.db.index.node_page  B-tree node page codec (v1/v2)
|
|-- engine/
|   |-- core.xi              xiom.db.engine.core      in-memory WAL/Query/planner + legacy Engine,
|   |                                                 shared DBFile helpers (apply/guard/index)
|   |-- snapshot.xi          xiom.db.engine.snapshot  v1/v2 checkpoint codec, compaction, pins
|   `-- txn.xi               xiom.db.engine.txn       durable txn window + savepoints
|
`-- engine.xi              xiom.db.engine           DBFile + file-backed public API (facade);
                                                   re-exports the four modules above
```

The `wal/`, `query/`, and `api/` files remain tombstones: their contents were
merged into `engine/core.xi` and the `engine.xi` facade (R1 split, 2026-10-18).

### Layering rule
Foundations (`error`/`ids`/`config`/`contracts`), storage/catalog, `index/btree`,
and `engine/core` are one-way. `engine.xi` owns the public `DBFile` type and
the file-backed API; `engine/core`, `engine/snapshot`, and `engine/txn` import
`xiom.db.engine` back to take `&DBFile`/`&mut DBFile` (a deliberate, compiler-
supported module cycle -- verified by the R1 cycle-import spike). All four are
re-exported from `engine.xi` with `pub use`, so `use xiom.db.engine;` keeps the
complete 0.2.x public surface. Consumer modules must never depend on the
`engine/core|snapshot|txn` internals directly.

---

## 2. Ownership Rules

Ownership answers "who is allowed to mutate this state?" -- the single most important property for a storage engine.

| State | Owner | Notes |
|-------|-------|-------|
| **Pages** (`Page`, checksums) | `storage/page.xi` | Only the `BufferPool` / `StorageEngine` create, cache, and validate pages. Higher layers hold pages by value, never mutate raw bytes. |
| **Buffer pool frames** | `storage/page.xi` (`BufferPool`) | Eviction/replacement policy is internal; callers use `cache_page` / `lookup_page` only. |
| **Free space accounting** | `storage/free_space_map.xi` | The only module allowed to decide where a new tuple lands (Phase 1). |
| **Row/tuple encoding** | `storage/tuple.xi` | Sole owner of the on-wire byte layout via `tuple_encode` / `tuple_decode`. |
| **Schema / catalog** | `catalog/schema.xi` | Immutable metadata; `schema_validator.xi` is the only validator. |
| **WAL buffer** | `engine/core.xi` (`WAL`) | Append-only. Only the engine appends; replay reads. No other module edits `entries`. |
| **B-tree nodes** | `index/btree.xi` (`NodeStore`) | All structural mutation (split/merge/borrow) is private to this module. v2 node bodies live in the bounded `NodeStore.frames` cache (`slots` id -> frame); `ns_get`/`ns_set`/`ns_push` own load, spill and dirty tracking. |
| **Transactions** | `engine/txn.xi` (durable window) + `txn/transaction.xi` (state machine type) | State transitions occur only through `commit` / `abort` / `add_op`; the durable window buffers through `db_file_txn_*`. |
| **Timestamps / write ordering** | `engine/core.xi` (legacy `Engine`) + `engine.xi` (`DBFile`) | The engine is the sole issuer of monotonic timestamps and the sole enforcer of WAL-before-data. |
| **Open/closed lifecycle** | `engine.xi` (`Database` facade) | The facade owns the `open` flag; a closed DB rejects all operations. |

**Golden rule:** the WAL is written **before** the index. `engine_insert / engine_delete / engine_update` always `wal_append` first, then mutate the `BTree`. No other ordering is permitted.

---

## 3. Contract Hotspots

These are the `requires:` / `ensures:` and invariant checkpoints that keep the engine correct. See [docs/contracts-and-invariants.md](docs/contracts-and-invariants.md) for the full list.

| Location | Contract | Why |
|----------|----------|-----|
| `btree_new(order)` | `requires: order >= 3` | Below order 3 a node cannot split with a separator key; balancing breaks. |
| `btree_range_query(low, high)` | `requires: low <= high` | An inverted range is meaningless and would scan nothing/everything. |
| `Page.new(id, data, checksum)` | `requires: data.len() <= 4096` | A page must fit its block. |
| `BufferPool.new(capacity)` | `requires: capacity >= 1` | Direct-mapped index `id % capacity` needs a non-zero modulus. |
| `wal_truncate(before_timestamp)` | `requires: before_timestamp >= 0` | Timestamps are non-negative; a negative bound is a logic error. |
| `query_limit(limit)` | `requires: limit > 0` | A zero/negative limit is expressed by *not* setting one. |
| `query_offset(offset)` | `requires: offset >= 0` | Offsets index forward only. |
| `engine_new(order)` / `db_open(order)` | `requires: order >= 3` | Propagates the B-tree order floor to the entry points. |
| B-tree node keys | **Invariant:** strictly ascending, deduplicated | `contracts.sorted_keys`; guarded by insert refusing duplicates. |
| WAL ordering | **Invariant:** timestamps monotonic | Guaranteed by the engine's single counter. |

---

## 4. Typed Error Domains

xiom-db has exactly **one** public error type: `DbError` (`xiom.db.error`).

```
DbError = NotFound | DuplicateKey | ConstraintViolation
        | SchemaMismatch | StorageError | Corruption
```

- Every fallible internal operation returns `DbResult[T] = Result[T, DbError]`.
- Every failure is encoded in the return type; there is no second error vocabulary. (The message-bearing `xiom.core.error.CoreError`/`CoreConfig` folds were retired 2026-10-10 -- the substrate package was never published; re-introduce them when `xiom-core` lands.)
- Public facade methods use `Bool` / `Option[T]` for the common success-or-absence cases; richer failures surface through `DbResult` in the codec/catalog paths.

**Failure domains** (where each class of failure is detected and handled):
- *Input/logic* -- `ConstraintViolation`, `DuplicateKey`, `SchemaMismatch`: detected at the catalog/query/index boundary, never retried.
- *Integrity* -- `Corruption`: detected by `Page.is_valid()` and `tuple_decode`; fatal, never retried.
- *Storage* -- `StorageError`: the only retryable class (transient IO); today a placeholder since storage is in-memory.
- *Absence* -- `NotFound`: normal control flow, expressed as `Option::None` in the hot path.

Full mapping in [docs/error-catalog.md](docs/error-catalog.md).

---

## 5. On-Disk Layout (current: in-memory)

> **Status:** Phase 0 is fully in-memory. There is no file format yet. This section states the *intended* layout so the seams are visible.

| Concept | Now (Phase 0) | Target (Phase 1-2) |
|---------|---------------|--------------------|
| Page | `Page{ data: Vec[UInt8], checksum }` in a `BufferPool` slot | Fixed 4 KiB block on disk via `xiom.core.storage.pager`, CRC32C footer |
| Tuple | `Vec[Int]` in memory, `tuple_encode` = `[id, len, cols...]` | Length-prefixed byte record inside a heap page, placed via the free-space map |
| Index | Flat `Vec[BTreeNode]` in RAM | Node-per-page B-tree paged through the buffer pool |
| WAL | `Vec[WALEntry]` in RAM | Append-only segment file, fsync on commit, via `xiom.core.wal.wal_writer` |
| Catalog | `Schema` structs in RAM | Serialized system table |

The module seams (`storage/page`, `storage/tuple`, `storage/free_space_map`, `wal/wal`) are exactly the points where the in-memory implementation is swapped for the durable one -- no higher layer changes.

---

## 6. Recovery Lifecycle

```
                 +-------------+
   normal write  | engine_insert|
   ----------->  |   1. next_ts |
                 |   2. wal_append (WAL-before-data)
                 |   3. btree_insert
                 `-------------+

   crash / restart
   ----------->  db_recover / engine_recover
                 +-------------------------------+
                 | 1. fresh tree = btree_new(order)
                 | 2. wal_replay(wal, &mut tree)   |  in log (timestamp) order
                 |    - InsertOp -> btree_insert    |
                 |    - UpdateOp -> delete + insert  |
                 |    - DeleteOp -> btree_delete     |
                 | 3. timestamp_counter = 0        |
                 `-------------------------------+
                 returns false if ANY record failed
                 (partial recovery still applied)

   checkpoint    engine_flush_wal (clear)  /  engine_truncate_wal(before_ts)
```

Because writes are logged before they are applied, the WAL is a complete, ordered history; replaying it onto an empty tree reconstructs the exact committed state. The `db_close` path performs a checkpoint (`engine_flush_wal`) before marking the handle closed; Phase 2 makes this an fsync of durable segments.

---

## 7. Where Future Work Plugs In

| Future capability | Plug-in point |
|-------------------|---------------|
| Real disk pager | `storage/page.xi` behind `StorageEngine`, using `xiom.core.storage.pager` |
| Durable WAL + fsync | `engine/core.xi` (in-memory buffer) + `wal_file.xi`, using `xiom.core.wal.wal_writer` |
| Free-space placement | `storage/free_space_map.xi` |
| Index-aware planning | `query/planner.xi` -> `btree_range_query` |
| MVCC / isolation | `txn/transaction.xi` + a version-aware index read path |
| SQL front-end | a new `sql/` layer above `engine.xi` |

See [ROADMAP.md](ROADMAP.md) for phasing and status.
