# xiom-db

> Embedded database engine for XIOM — B-Tree, WAL, query engine, crash recovery.

[![XIOM](https://img.shields.io/badge/XIOM-v0.22.1-blue)](https://github.com/xiom-lang/XIOM)
[![License](https://img.shields.io/badge/license-MIT%2FApache--2.0-blue.svg)](LICENSE)

## Overview

xiom-db is an embedded database engine in pure XIOM. It provides a B-Tree storage engine, write-ahead log (WAL) for crash recovery, and a query engine with filtering/sorting/pagination — all with contract-guaranteed integrity.

## Installation
```bash
xiom install xiom-db
```

## Quick Start
```xiom
use xiom.db.engine;

fn main() -> Int {
  var eng = engine_new(4);  // B-tree order 4
  engine_insert(&mut eng, 1, 100);
  engine_insert(&mut eng, 2, 200);
  var val = engine_get(&eng, 1);  // Some(100)
  return 0;
}
```

## API Reference

### Types (`xiom.db.types`)
| Type | Description |
|------|-------------|
| `Page` | 4KB data page with checksum |
| `WALOp` | Enum: Insert, Update, Delete |
| `TxState` | Enum: Active, Committed, Aborted |
| `Transaction` | Transaction with WAL operations |

### B-Tree (`xiom.db.btree`)
| Function | Description |
|----------|-------------|
| `btree_new(order)` | Create B-tree |
| `btree_insert(tree, key, value)` | Insert key-value |
| `btree_search(tree, key)` | Search by key |
| `btree_delete(tree, key)` | Delete key |
| `btree_range_query(tree, low, high)` | Range scan |
| `btree_min/max(tree)` | Min/max key |
| `btree_size(tree)` / `btree_is_empty(tree)` | Metadata |

### WAL (`xiom.db.wal`)
| Function | Description |
|----------|-------------|
| `wal_new()` | Create WAL |
| `wal_append(wal, entry)` | Log entry |
| `wal_replay(wal, tree)` | Recover from WAL |
| `wal_clear(wal)` / `wal_truncate(wal, ts)` | Maintenance |

### Query Engine (`xiom.db.query`)
| Function | Description |
|----------|-------------|
| `query_new()` | Create query builder |
| `query_where(q, op, value)` | Add condition |
| `query_limit/offset(q, n)` | Pagination |
| `query_execute(q, tree)` | Run query |

### Engine (`xiom.db.engine`)
| Function | Description |
|----------|-------------|
| `engine_new(order)` | Create engine |
| `engine_insert/get/delete` | CRUD |
| `engine_query(eng, query)` | Run query |
| `engine_range(eng, low, high)` | Range scan |
| `engine_recover(eng)` | Crash recovery |
| `engine_size(eng)` | Key count |

## Production Readiness
| Feature | Status |
|---------|--------|
| B-Tree (insert/search/delete) | ✅ Complete |
| Range queries | ✅ Complete |
| WAL (write-ahead log) | ✅ Complete |
| Crash recovery (WAL replay) | ✅ Complete |
| Query engine (filter/sort/limit) | ✅ Complete |
| Transactions (ACID) | ⚠️ WAL only, no isolation |
| Disk persistence | ❌ Not yet (in-memory only) |
| Secondary indexes | ❌ Not yet |
| Concurrency (MVCC) | ❌ Not yet |
| SQL interface | ❌ Use xiom-sqlite |

### What's Left
1. **Disk persistence** — serialize B-Tree pages to file
2. **MVCC** — multi-version concurrency control
3. **Secondary indexes** — non-primary-key indexes
4. **Compaction** — page merging, defragmentation

## Dependencies: None (Pure XIOM)
## Links: [xiom-lang](https://github.com/xiom-lang) | [XIOM](https://github.com/xiom-lang/XIOM)
## License: MIT OR Apache-2.0
