<!--
Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
SPDX-License-Identifier: MIT OR Apache-2.0
-->

# XiomDB Roadmap

> An honest, phased plan. Status is reported per-item; nothing is marked complete that is not actually implemented and working.

Legend: [OK] done - [WIP] in progress - [WIP] scaffolded (types + stubs, `TODO(Phase N)`) - [FAIL] not started

> **Production track:** `docs/PRODUCTION-PLAN.md` -- the strategy from these
> phases to a production release (workstreams M1-M8, gates P-alpha -> 1.0,
> benchmark targets, release signal), executed via
> `docs/checklists/production-release.md`.

---

## Phase 0 -- In-memory engine  [OK] DONE

The working core. Everything here is implemented and exercised through the public facade.

| Item | Status | Location |
|------|--------|----------|
| Flat-array B-tree (insert/search/delete) | [OK] | `index/btree.xi` |
| B-tree delete borrow/merge hardening (churn-proven vs model) | [OK] (2026-10-08) | `index/btree.xi` |
| Range queries, min/max, in-order traversal | [OK] | `index/btree.xi` |
| Write-ahead log (append/replay/truncate/clear) | [OK] (in-memory) | `wal/wal.xi`, `wal/wal_record.xi` |
| Crash recovery via WAL replay | [OK] (in-memory; file-backed `DBFile` replays the disk segment) | `engine.xi` `engine_recover`, `db_file_open` |
| Query engine (AND filter, limit, offset) | [OK] | `query/query.xi` |
| Engine coordinator (WAL-before-data) | [OK] | `engine.xi` |
| Public `Database` facade | [OK] | `api/database.xi` |
| Layered module structure | [OK] | whole `src/` tree |
| Foundations (error/ids/config/contracts) | [OK] | `error.xi`, `ids.xi`, `config.xi`, `contracts.xi` |
| Schema catalog + validation | [OK] | `catalog/schema.xi`, `catalog/schema_validator.xi` |
| Storage primitives (Page, BufferPool, tuple codec) | [OK] (in-memory) | `storage/page.xi`, `storage/tuple.xi` |
| Transaction state machine | [OK] (state only) | `txn/transaction.xi` |
| Dependency on `xiom-core` substrate | [OK] | `package.xi` |
| Conformance test suite (111 tests) | [OK] | `tests/test_conformance.xi` |

**Known limitation:** all state lives in RAM. "Durability" and "recovery" are correct with respect to the in-memory WAL but survive only process-lifetime, not a real crash.

---

## Phase 1 -- Real pages / pager via xiom-core  [WIP] SCAFFOLDED

Move storage from ad-hoc in-memory structures to the shared pager.

| Item | Status | Plan |
|------|--------|------|
| Free-space map | [OK] (2026-10-08) | `storage/free_space_map.xi` -- best-fit placement, use/release clamping, invariant checker; model-soaked (`probe_fsm`, 50k ops). FSM tree/bitmap + persistence land with the pager |
| Byte-packed tuple codec | [OK] (2026-10-08) | `storage/tuple.xi` -- v1 record: magic/version/field_count + typed i64 LE fields; decode validates exact length/type; `tuple_fits_page` budget; byte-true in `Vec[Int]` until Vec[UInt8] conversion lands |
| Real pager integration | [FAIL] | Route `StorageEngine` through `xiom.core.storage.pager` + `buffer_pool` |
| Durable page file v1 (text codec) | [OK] (2026-10-08) | `storage/page_file.xi` -- one line per page `id\|len\|crc\|bytes`, CRC32C verified on read, upsert via temp+rename (atomic replace), torn/checksum-invalid lines rejected and healed on rewrite; append-only **page log** (`page_log_append`/`read_all`/`len`/`heal_tail`) for incremental writes; crash harness `scripts/page_crash_test.{ps1,sh}` |
| Buffer-pool replacer + pinning (C4) | [OK] (2026-10-09) | `storage/page.xi`: associative frame table with clock (second-chance) replacement, per-frame pin counts (pinned frames never evicted; all-pinned put rejected), hits/misses/evictions/rejects stats; suite clock-order + pinning tests x2 Win + WSL |
| CRC32C checksums | [OK] (2026-10-08) | `storage/page.xi` -- bitwise Castagnoli, KAT-locked (0xE3069283); swap to `xiom.hash.crc` when byte packs land |
| Node-per-page B-tree | [WIP] (2026-10-08) | Durable node pages + incremental generation-committed checkpoint done (`db_file_checkpoint`: changed nodes only, header-last commit, generation resolution); the live tree is still fully resident -- paged/evicting access needs the pager seam |

---

## Phase 2 -- Disk WAL + durable recovery  [FAIL] NOT STARTED

Make durability real.

| Item | Status | Plan |
|------|--------|------|
| Append-only WAL segment file | [OK] (2026-10-08) | `wal_file.xi` -- durable segment (own module; `xiom.core.wal` substrate later), crash-proven; `DBFile` facade replays it on open |
| fsync on commit | [FAIL] | Blocked on the stdlib fsync row; `wal_file_flush`/`page_file_sync` are the wired seams |
| LSN-based ordering | [WIP] | `DBFile` orders by `wal_file` LSNs; the in-memory engine still uses integer timestamps |
| Checkpointing | [OK] (2026-10-08) | Incremental generation-committed snapshot (`db_file_checkpoint`: only changed nodes, header page commits, compaction at node_count+64) + `db_file_maybe_checkpoint(limit)` policy; uncommitted-generation and torn-tail crash states in the suite; 2000-key policy soak (9 checkpoints) x2 Win + WSL |
| Durable transactions (D2) | [OK] (2026-10-08) | WAL Begin/Commit/Abort kinds (8/9/10) + `db_file_txn_*` (log-then-buffer, apply at commit, abort discards); replay applies committed windows, drops unterminated ones and finalizes a dangling window with an Abort record; checkpoint + auto-commit rejected mid-txn; crash scenarios D/E x2 Win + WSL |
| Torn-page / crash recovery test suite | [OK] (2026-10-08) | `crash_test.{ps1,sh}` (WAL), `page_crash_test.{ps1,sh}`, `db_crash_test.{ps1,sh}` -- GREEN x2 Windows + WSL; power-loss leg blocked on fsync |
| Fuzz/property harness (H3) | [OK] (2026-10-09) | `scripts/fuzz.{ps1,sh}` + `probe_fuzz.xi`: deterministic seeds for tuple codec, WAL parser, page log, B-tree vs model; x2 Win + WSL |
| API / runbook / format reference (I3) | [OK] (2026-10-09) | `docs/API.md` + `docs/RUNBOOK.md` + `docs/FORMATS.md` (v1 formats, version policy), linked from the README doc index |

---

## Phase 3 -- Query planner + isolation  [WIP] SCAFFOLDED (planner)

Make queries fast and concurrent.

| Item | Status | Plan |
|------|--------|------|
| Index-aware query planner | [WIP] | `query/planner.xi` -- derive `[low, high]` bounds, emit `IndexRange`/`PointLookup`, push into `btree_range_query` |
| Cost-based plan selection | [FAIL] | Estimate rows via `btree_size`; choose scan vs. index |
| Transaction isolation (MVCC) | [FAIL] | Version-aware reads; extend `txn/transaction.xi` with snapshots |
| Lock / conflict management | [FAIL] | Write-write conflict detection using `xiom.core.txn` |
| Secondary indexes | [FAIL] | Non-primary-key B-trees driven by `catalog/schema.IndexDef` |

---

## Phase 4 -- SQL layer  [FAIL] NOT STARTED

A relational front-end above the facade.

| Item | Status | Plan |
|------|--------|------|
| SQL parser | [FAIL] | New `sql/` layer above `api/database.xi` |
| Typed values (beyond Int) | [FAIL] | Extend `storage/tuple.xi` + `catalog/schema.ColumnType` enforcement |
| Column constraints (NOT NULL, defaults, types) | [FAIL] | Finish `TODO(Phase 4)` in `catalog/schema_validator.xi` |
| Joins, aggregation, ordering | [FAIL] | Planner operators above `query/planner.xi` |

---

## Summary

- **Usable today:** Phase 0 -- a correct in-memory key/value store with B-tree indexing, WAL, recovery, and a query facade.
- **Next milestone:** Phase 1 -- durable pages via `xiom-core`.
- The architecture was designed so each phase swaps an implementation behind an existing module seam without disturbing the layers above it.
