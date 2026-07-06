# xiom-db

> Embedded database engine for XIOM — layered architecture: B-Tree index, WAL, query engine, crash recovery. Built on the `xiom-core` durable-systems substrate.

[![XIOM](https://img.shields.io/badge/XIOM-v0.22.1-blue)](https://github.com/xiom-lang/XIOM)
[![License](https://img.shields.io/badge/license-MIT%2FApache--2.0-blue.svg)](LICENSE)

## Overview

xiom-db is an embedded database engine in pure XIOM. It provides a B-Tree storage index, a write-ahead log (WAL) for crash recovery, and a query engine with filtering / pagination — all with contract-guaranteed integrity. As of `0.2.0` the package is organized as a **layered architecture** and depends on `xiom-core` for shared IDs, errors, config, contracts, and metrics.

See [ARCHITECTURE.md](ARCHITECTURE.md) for the module tree and ownership rules, [ROADMAP.md](ROADMAP.md) for the phased plan, and [`docs/`](docs/) for subsystem deep-dives.

## Installation
```bash
xiom install xiom-db
```

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

## Module Layout

```
src/
├── error.xi                     xiom.db.error            — DbError, DbResult
├── ids.xi                       xiom.db.ids              — RowId, TableId
├── config.xi                    xiom.db.config           — DatabaseConfig
├── contracts.xi                 xiom.db.contracts        — valid_key, sorted_keys, ...
├── storage/
│   ├── page.xi                  xiom.db.storage.page     — Page, BufferPool, StorageEngine
│   ├── tuple.xi                 xiom.db.storage.tuple    — Row, ResultSet, tuple codec
│   └── free_space_map.xi        xiom.db.storage.free_space_map  (scaffold, Phase 1)
├── catalog/
│   ├── schema.xi                xiom.db.catalog.schema           — Schema, ColumnDef, IndexDef
│   └── schema_validator.xi      xiom.db.catalog.schema_validator — validation
├── wal/
│   ├── wal_record.xi            xiom.db.wal.wal_record   — WALEntry, WALOpType
│   └── wal.xi                   xiom.db.wal.wal          — WAL, append/replay/truncate
├── txn/
│   └── transaction.xi           xiom.db.txn.transaction  — Transaction, TxState
├── index/
│   └── btree.xi                 xiom.db.index.btree      — flat-array B-tree (canonical)
├── query/
│   ├── query.xi                 xiom.db.query.query      — Query builder + execution
│   └── planner.xi               xiom.db.query.planner    (scaffold, Phase 3)
├── engine.xi                    xiom.db.engine           — internal coordinator
└── api/
    └── database.xi              xiom.db.api.database     — public Database facade
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
| Layered architecture | ✅ Complete (0.2.0) |
| B-Tree (insert/search/delete/range) | ✅ Complete |
| WAL (write-ahead log) | ✅ Complete (in-memory) |
| Crash recovery (WAL replay) | ✅ Complete (in-memory) |
| Query engine (filter/limit/offset) | ✅ Complete |
| Public Database facade | ✅ Complete |
| Schema catalog + validation | ✅ Types + validation |
| Transactions (isolation/MVCC) | ⚠️ State machine only |
| Query planner (index-aware) | ⏳ Scaffolded (Phase 3) |
| Free-space map | ⏳ Scaffolded (Phase 1) |
| Disk persistence (real pager) | ❌ Phase 1–2 |

See [ROADMAP.md](ROADMAP.md) for the honest, phased plan.

## Build & Run
```bash
xiomc --run myprogram.xi
```

## Dependencies: `xiom-core`, `xiom-std`
## Links: [xiom-lang](https://github.com/xiom-lang) | [XIOM](https://github.com/xiom-lang/XIOM)
## License: MIT OR Apache-2.0
