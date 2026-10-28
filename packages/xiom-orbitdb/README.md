<!--
Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
SPDX-License-Identifier: MIT OR Apache-2.0
-->

# XIOM ORBITDB -- Satellite + Station

> **Status:** `incubating` -- carved from source pin `720b27a` (v0.3.0 candidate: paged B-tree store + checkpoint/GC, db-file locks + held-fd writes). **Split conformance suite 166/166 x2 across 11 files + legacy suite 160/160** on the accepted **v0.65.1** compiler. 0.2.1 remains the live registry artifact (`eco-v0.1.196`, sha256 `c8fc6548...`, 2026-10-17). 0.3.0 is **not published** -- publish is owner-held by ORBITDB; the record carries `publish=false`.

> The XIOM two-tier database line. **Satellite** (tier 1) is the embedded database engine in this repository -- B-Tree index, WAL, query engine, crash recovery; useful as a library or through its CLI. **Station** (tier 2) is the planned PostgreSQL-class server tier: same repo, consumes the engine as a library, never a fork. Formerly `xiom-db`; module names stay `xiom.db.*`.

[![XIOM](https://img.shields.io/badge/XIOM-v0.22.1-blue)](https://github.com/XIOM-lang/XIOM.git )
[![License](https://img.shields.io/badge/license-MIT%2FApache--2.0-blue.svg)](LICENSE)

## Overview

ORBITDB is an embedded database engine in pure XIOM. It provides a B-Tree storage index, a write-ahead log (WAL) for crash recovery, and a query engine with filtering / pagination -- all with contract-guaranteed integrity. The package is organized as a **layered architecture** with a zero-dependency core (pure XIOM + stdlib; no registry package dependencies).

See [ARCHITECTURE.md](ARCHITECTURE.md) for the module tree and ownership rules, [ROADMAP.md](ROADMAP.md) for the phased plan, and [`docs/`](docs/) for subsystem deep-dives. Start with [API.md](docs/API.md) (public API reference), [RUNBOOK.md](docs/RUNBOOK.md) (commands, recovery, gotchas), [FORMATS.md](docs/FORMATS.md) (versioned on-disk formats), [ISOLATION.md](docs/ISOLATION.md) (single-writer / multi-handle model), and [MVCC.md](docs/MVCC.md) (M3 minimal subset: snapshot pins + savepoints). The production strategy is [PRODUCTION-PLAN.md](docs/PRODUCTION-PLAN.md) with the execution checklist in [docs/checklists/production-release.md](docs/checklists/production-release.md).

## Two-tier product line: Satellite + Station

One engine, two products, one repository (**orbitdb-satellite** -- tier 1, embedded -- and **orbitdb-station** -- tier 2, server). Strategy: [docs/TWO-TIER-ARCHITECTURE.md](docs/TWO-TIER-ARCHITECTURE.md); execution: [docs/checklists/two-tier.md](docs/checklists/two-tier.md).

| | Tier 1 -- Embedded | Tier 2 -- Server |
|---|---|---|
| Codename | **Satellite** | **Station** |
| Analogue | SQLite | PostgreSQL |
| Shape | library compiled into the consumer; registry package; single-node | separate program (same repo, `station/`): wire protocol, sessions, replication, sharding |
| Source | this repo's `src/` (engine; modules `xiom.db.*`) | planned `station/`; consumes the engine as a library -- never a fork |
| Status | shipping pre-1.0; registry publication at the P-rc gate | planned; work starts only after G-START |

**Codenames, not renames** (packages-lane convention, 2026-10-16): registry IDs stay functional `xiom.*` names; the codename identifies the product tier. Module/package names are stable (`xiom.db.*`, `xiom.orbitdb`); the codename is a deployment/product label. Registry artifacts carry **Satellite**; **Station** releases are standalone (GitHub Actions pipeline with ops; registry involvement limited to a future station client package).

### Satellite (tier 1) -- use it today

- **Usage**: embed the engine in an XIOM program (public facade `xiom.db.api.database`, or the lower-level `xiom.db.engine`), or drive the interactive shell (`apps/orbitdb_cli.xi` -- `put/get/del/range/count/ckpt/recover/putrow/getrow/qrow/bench/kill`).
- **Features today**: durable WAL (real fsync at commit acks); crash recovery (torn-tail tolerant: snapshot + tail replay, uncommitted txn windows dropped); `v2` byte container default; typed rows end-to-end + typed predicates; secondary value index + ORDER/LIMIT; transactions with savepoints; in-process snapshot pins (M3 minimal subset); zero-dependency core.
- **Gate to 1.0 / publication**: M1.1b pager (lazy node load + bounded cache), M3 remainder (cross-process `file_lock` MVCC), R1/R2 module split; then the P-rc release signal and the packages-lane publication coordination.

### Station (tier 2) -- planned

- **Shape**: **ORBITWIRE v1** wire protocol (length-prefixed frames; handshake + auth slot; prepare/execute/fetch over typed rows), sessions, single-writer commit path, replication via WAL shipping + snapshot bootstrap, range sharding (one engine database per shard; the shard catalog is itself an engine DB), ops (auth, backup/restore drills, metrics).
- **Not in v1**: full SQL, cross-shard transactions, auto-sharding / auto-failover, multi-master. Optional post-ST7 evaluation only: a PG-wire facade (interop riding the `xiom.postgres` wire knowledge).
- **Milestones**: ST0 prerequisites (G-START) -> ST1 protocol spike -> ST2 single-node core -> ST3 concurrency -> ST4 replication -> ST5 sharding -> ST6 ops -> ST7 cross-engine league; exit criteria in [docs/TWO-TIER-ARCHITECTURE.md](docs/TWO-TIER-ARCHITECTURE.md) section 6. The embedded release always outranks Station work.

## Installation

The **Satellite** registry package is not published yet -- publication is gated on P-rc and coordinates through the packages lane. Until then, build from source (see **Try it** below); module imports stay `xiom.db.*` either way.

## Quick Start (public facade)
```xiom
use xiom.db.api.database;
use xiom.db.query.query;

fn main() -> Int {
  var db = db_open(4);            // B-tree order 4
  db_insert(&mut db, 1, 100);
  db_insert(&mut db, 2, 200);
  var val = db_get(&db, 1);       // Some(100)

  var q = query_new();
  query_where(&mut q, QueryOp.Gt, 150);
  var rows = db_query(&db, &q);   // [200]

  db_close(&mut db);
  return 0;
}
```

The lower-level `xiom.db.engine` API (`engine_new`, `engine_insert`, ...) remains available for callers that need direct control.

## Try it (interactive shell)

The repo ships a user-test shell (`apps/orbitdb_cli.xi`) -- the current
executable face of the engine:

```powershell
# Windows (embeds assets/orbitdb.ico)
.\scripts\build.ps1 apps\orbitdb_cli.xi -Out out\orbitdb.exe
.\out\orbitdb.exe mydata.wal
```

```bash
# WSL / Linux
bash scripts/build.sh apps/orbitdb_cli.xi out/orbitdb-cli
./out/orbitdb-cli mydata.wal
```

```
orbitdb> put 1 100
orbitdb> get 1
orbitdb> range 1 10
orbitdb> putrow 2 i:7,s:hello,f:2.5,n     # typed row (M5.3)
orbitdb> getrow 2
orbitdb> qrow 2 < f:3.0                   # typed predicate -> matching pks
orbitdb> ckpt
orbitdb> kill      # exits WITHOUT cleanup -- restart to watch WAL replay
```

`help` lists every command (`put/get/del/range/count/ckpt/bench/info/
recover/kill/putrow/getrow/qrow`). Typed rows store opaque bytes end to end
(tuple codec v2 rows; `docs/TYPED-VALUES-STORAGE.md`) and typed predicates
compare decoded columns (Null < numeric < text < blob, per `tuple2_compare`).

## Module Layout

```
src/
|-- error.xi                     xiom.db.error            -- DbError, DbResult
|-- ids.xi                       xiom.db.ids              -- RowId, TableId
|-- config.xi                    xiom.db.config           -- DatabaseConfig
|-- contracts.xi                 xiom.db.contracts        -- valid_key, sorted_keys, ...
|-- storage/
|   |-- page.xi                  xiom.db.storage.page     -- Page, BufferPool, StorageEngine
|   |-- tuple.xi                 xiom.db.storage.tuple    -- Row, ResultSet, tuple codec
|   `-- free_space_map.xi        xiom.db.storage.free_space_map  (scaffold, Phase 1)
|-- catalog/
|   |-- schema.xi                xiom.db.catalog.schema           -- Schema, ColumnDef, IndexDef
|   `-- schema_validator.xi      xiom.db.catalog.schema_validator -- validation
|-- wal/
|   |-- wal_record.xi            xiom.db.wal.wal_record   -- WALEntry, WALOpType
|   `-- wal.xi                   xiom.db.wal.wal          -- WAL, append/replay/truncate
|-- txn/
|   `-- transaction.xi           xiom.db.txn.transaction  -- Transaction, TxState
|-- index/
|   `-- btree.xi                 xiom.db.index.btree      -- flat-array B-tree (canonical)
|-- query/
|   |-- query.xi                 xiom.db.query.query      -- Query builder + execution
|   `-- planner.xi               xiom.db.query.planner    (scaffold, Phase 3)
|-- engine.xi                    xiom.db.engine           -- internal coordinator
`-- api/
    `-- database.xi              xiom.db.api.database     -- public Database facade
```

## API Reference

### Public Facade (`xiom.db.api.database`)
| Function | Description |
|----------|-------------|
| `db_open(order)` / `db_open_with(config)` | Open a database |
| `db_insert(db, key, value)` | Insert (WAL-logged) |
| `db_get(db, key)` | Point lookup |
| `db_update(db, key, value)` | Update existing key |
| `db_delete(db, key)` | Delete (WAL-logged) |
| `db_query(db, query)` | Run a query |
| `db_range(db, low, high)` | Range scan |
| `db_recover(db)` | Replay WAL |
| `db_close(db)` | Checkpoint + close |

### Engine (`xiom.db.engine`)
`engine_new`, `engine_insert`, `engine_get`, `engine_update`, `engine_delete`, `engine_query`, `engine_range_query`, `engine_recover`, `engine_size`, `engine_wal_size`, `engine_flush_wal`, `engine_truncate_wal`.

### B-Tree (`xiom.db.index.btree`)
`btree_new`, `btree_insert`, `btree_search`, `btree_delete`, `btree_range_query`, `btree_min`, `btree_max`, `btree_size`, `btree_to_vec`.

### WAL (`xiom.db.wal.wal` + `xiom.db.wal.wal_record`)
`wal_new`, `wal_append`, `wal_replay`, `wal_clear`, `wal_truncate`, `wal_len`, `wal_is_empty`, `wal_entry_count`; `WALEntry`, `WALOpType`, `wal_entry_new`.

### Query Engine (`xiom.db.query.query`)
`query_new`, `query_where`, `query_limit`, `query_offset`, `query_execute`, `query_condition_count`, `query_reset`.

## Production Readiness
| Feature | Status |
|---------|--------|
| Layered architecture | [OK] Complete (0.2.0) |
| B-Tree (insert/search/delete/range) | [OK] Complete |
| WAL (write-ahead log) | [OK] Durable disk segment + recovery; real fsync at commit acks (S4); held-handle write path (2026-10-16) |
| Crash recovery (WAL replay) | [OK] Durable: snapshot + tail replay, torn-tail tolerant |
| Query engine (filter/limit/offset) | [OK] Complete |
| Public Database facade | [OK] Complete |
| Schema catalog + validation | [OK] Types + validation |
| Transactions (isolation/MVCC) | [WIP] Durable txn + savepoints; in-process snapshot pins (M3 minimal, `docs/MVCC.md`); multi-process pending |
| Query planner (index-aware) | [OK] Point/range pushdown + secondary index (`IndexValue`) |
| Free-space map | [WIP] Scaffolded (Phase 1) |
| Disk persistence (real pager) | [WIP] Durable snapshot/WAL; paged node store pending (A5/C3) |

See [ROADMAP.md](ROADMAP.md) for the honest, phased plan.

## Build & Run
```bash
xiom --run myprogram.xi
```

## Dependencies: none in the engine (pure XIOM + stdlib; zero registry deps)
## Links: [xiom-lang](https://github.com/xiom-lang) | [XIOM](https://github.com/XIOM-lang/XIOM.git )
## License: MIT OR Apache-2.0
