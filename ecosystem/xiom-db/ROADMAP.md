# XiomDB Roadmap

> An honest, phased plan. Status is reported per-item; nothing is marked complete that is not actually implemented and working.

Legend: ✅ done · 🚧 in progress · ⏳ scaffolded (types + stubs, `TODO(Phase N)`) · ❌ not started

---

## Phase 0 — In-memory engine  ✅ DONE

The working core. Everything here is implemented and exercised through the public facade.

| Item | Status | Location |
|------|--------|----------|
| Flat-array B-tree (insert/search/delete) | ✅ | `index/btree.xi` |
| Range queries, min/max, in-order traversal | ✅ | `index/btree.xi` |
| Write-ahead log (append/replay/truncate/clear) | ✅ (in-memory) | `wal/wal.xi`, `wal/wal_record.xi` |
| Crash recovery via WAL replay | ✅ (in-memory) | `engine.xi` `engine_recover` |
| Query engine (AND filter, limit, offset) | ✅ | `query/query.xi` |
| Engine coordinator (WAL-before-data) | ✅ | `engine.xi` |
| Public `Database` facade | ✅ | `api/database.xi` |
| Layered module structure | ✅ | whole `src/` tree |
| Foundations (error/ids/config/contracts) | ✅ | `error.xi`, `ids.xi`, `config.xi`, `contracts.xi` |
| Schema catalog + validation | ✅ | `catalog/schema.xi`, `catalog/schema_validator.xi` |
| Storage primitives (Page, BufferPool, tuple codec) | ✅ (in-memory) | `storage/page.xi`, `storage/tuple.xi` |
| Transaction state machine | ✅ (state only) | `txn/transaction.xi` |
| Dependency on `xiom-core` substrate | ✅ | `package.xi` |
| Conformance test suite (93 tests) | ✅ | `tests/test_conformance.xi` |

**Known limitation:** all state lives in RAM. "Durability" and "recovery" are correct with respect to the in-memory WAL but survive only process-lifetime, not a real crash.

---

## Phase 1 — Real pages / pager via xiom-core  ⏳ SCAFFOLDED

Move storage from ad-hoc in-memory structures to the shared pager.

| Item | Status | Plan |
|------|--------|------|
| Free-space map | ⏳ | `storage/free_space_map.xi` — replace linear scan with an FSM tree; place tuples by best-fit |
| Byte-packed tuple codec | ⏳ | `storage/tuple.xi` — `tuple_encode/decode` → length-prefixed page records honoring `page_size` |
| Real pager integration | ❌ | Route `StorageEngine` through `xiom.core.storage.pager` + `buffer_pool` |
| CRC32C checksums | ❌ | Upgrade `page_compute_checksum` from additive sum to CRC32C |
| Node-per-page B-tree | ❌ | Store B-tree nodes in pages instead of a flat `Vec` |

---

## Phase 2 — Disk WAL + durable recovery  ❌ NOT STARTED

Make durability real.

| Item | Status | Plan |
|------|--------|------|
| Append-only WAL segment file | ❌ | Back `wal/wal.xi` with `xiom.core.wal.wal_writer` |
| fsync on commit | ❌ | `db_close` / commit path issues real fsync via core FFI |
| LSN-based ordering | ❌ | Replace the engine's integer timestamp with `xiom.core.ids.Lsn` |
| Checkpointing | ❌ | Truncate WAL after a durable checkpoint using `xiom.core.wal.checkpoint` |
| Torn-page / crash recovery test suite | ❌ | Validate replay after simulated crashes |

---

## Phase 3 — Query planner + isolation  ⏳ SCAFFOLDED (planner)

Make queries fast and concurrent.

| Item | Status | Plan |
|------|--------|------|
| Index-aware query planner | ⏳ | `query/planner.xi` — derive `[low, high]` bounds, emit `IndexRange`/`PointLookup`, push into `btree_range_query` |
| Cost-based plan selection | ❌ | Estimate rows via `btree_size`; choose scan vs. index |
| Transaction isolation (MVCC) | ❌ | Version-aware reads; extend `txn/transaction.xi` with snapshots |
| Lock / conflict management | ❌ | Write-write conflict detection using `xiom.core.txn` |
| Secondary indexes | ❌ | Non-primary-key B-trees driven by `catalog/schema.IndexDef` |

---

## Phase 4 — SQL layer  ❌ NOT STARTED

A relational front-end above the facade.

| Item | Status | Plan |
|------|--------|------|
| SQL parser | ❌ | New `sql/` layer above `api/database.xi` |
| Typed values (beyond Int) | ❌ | Extend `storage/tuple.xi` + `catalog/schema.ColumnType` enforcement |
| Column constraints (NOT NULL, defaults, types) | ❌ | Finish `TODO(Phase 4)` in `catalog/schema_validator.xi` |
| Joins, aggregation, ordering | ❌ | Planner operators above `query/planner.xi` |

---

## Summary

- **Usable today:** Phase 0 — a correct in-memory key/value store with B-tree indexing, WAL, recovery, and a query facade.
- **Next milestone:** Phase 1 — durable pages via `xiom-core`.
- The architecture was designed so each phase swaps an implementation behind an existing module seam without disturbing the layers above it.
