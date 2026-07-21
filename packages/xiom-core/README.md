# xiom-core

> Shared durable-systems substrate for XIOM database engines — config, typed errors, strong IDs, storage, WAL, and transactions.

[![XIOM](https://img.shields.io/badge/XIOM-v0.22.1-blue)](https://github.com/xiom-lang/XIOM)
[![License](https://img.shields.io/badge/license-MIT%2FApache--2.0-blue.svg)](https://github.com/xiom-lang)

## Overview

**xiom-core** is the reusable engine foundation shared by [`xiom-db`](../xiom-db) and [`xiom-vector`](../xiom-vector). Both engines need the same durability plumbing — write-ahead logging, buffered page storage, checkpoint/recovery, transactions, typed errors, and strong identifiers — so that machinery lives here once, in one canonical place, instead of being duplicated and drifting apart.

The design follows a **shared core + specialized engine** model: xiom-core owns everything about *durability and systems plumbing*, while the downstream engines own their access paths (B-tree/SQL for xiom-db, HNSW/IVF for xiom-vector). If a concern is about crash safety, memory ownership, or on-disk format, it belongs here.

```
                 ┌────────────────────────┐   ┌────────────────────────┐
                 │        xiom-db          │   │      xiom-vector       │
                 │  B-tree · SQL · query   │   │  HNSW · IVF · segments │
                 └───────────┬────────────┘   └───────────┬────────────┘
                             │                            │
                             └──────────────┬─────────────┘
                                            ▼
                          ┌──────────────────────────────────┐
                          │             xiom-core             │
                          │  config · error · ids · limits    │
                          │  storage (page/pager/buffer_pool) │
                          │  wal (record/writer/recovery)     │
                          │  txn (state/manager/snapshot)     │
                          └──────────────────────────────────┘
```

## Installation

```bash
xiom install xiom-core
```

## Quick Start

```xiom
use xiom.core.config;
use xiom.core.wal.wal_writer;
use xiom.core.wal.wal_record;
use xiom.core.txn.txn_manager;

fn main() -> Int {
  var cfg = core_config_default();
  if !core_config_validate(&cfg) { return 1; }

  var wal = wal_writer_new();
  var lsn = wal_writer_append(&mut wal, WalOpKind.Insert, 42, 100);  // WAL-before-ack
  wal_writer_flush(&mut wal);

  var txns = txn_manager_new();
  var tid = txn_begin(&mut txns, lsn);
  txn_commit(&mut txns, tid);
  return 0;
}
```

## API Reference

### Errors (`xiom.core.error`)
| Function | Description |
|----------|-------------|
| `CoreError` | Canonical enum: NotFound, InvalidInput, OutOfBounds, Corruption, IOFailure, Unsupported, CapacityExceeded, InvalidState, ChecksumMismatch, VersionMismatch |
| `core_error_to_str(e)` | Stable human-readable description |
| `core_error_is_retryable(e)` | True only for transient `IOFailure` |

### Result (`xiom.core.result`)
| Function | Description |
|----------|-------------|
| `is_ok_result(ok)` | Trivial predicate helper |
| `ResultInfo` | Serializable `{ succeeded, error_code }` for FFI/wire boundaries |
| `result_info_ok()` / `result_info_err(code)` | Constructors |

### IDs (`xiom.core.ids`)
| Type | Constructor / Accessors |
|------|-------------------------|
| `PageId` | `page_id`, `page_id_value`, `page_id_eq` |
| `Lsn` | `lsn`, `lsn_value`, `lsn_next`, `lsn_lt`, `lsn_eq`, `lsn_zero` |
| `SegmentId` | `segment_id`, `segment_id_value`, `segment_id_eq` |
| `TxnId` | `txn_id`, `txn_id_value`, `txn_id_eq`, `txn_id_next` |
| `CollectionId` | `collection_id`, `collection_id_value`, `collection_id_eq` |
| `VectorId` | `vector_id`, `vector_id_value`, `vector_id_eq` |
| `ShardId` | `shard_id`, `shard_id_value`, `shard_id_eq` |

### Limits (`xiom.core.limits`)
| Function | Value |
|----------|-------|
| `max_dimensions()` | 65536 |
| `max_page_size()` / `default_page_size()` | 65536 / 4096 |
| `max_batch_size()` | 100000 |
| `max_key_size()` / `max_value_size()` | 4096 / 1048576 |
| `max_segment_count()` | 100000 |
| `default_btree_order()` | 64 |
| `max_graph_degree()` | 512 |
| `max_top_k()` | 10000 |

### Config (`xiom.core.config`)
| Function | Description |
|----------|-------------|
| `CoreConfig` | `{ page_size, buffer_pool_size, wal_enabled, sync_on_commit, data_dir, max_open_files }` |
| `core_config_default()` | Balanced defaults |
| `core_config_dev()` / `core_config_prod()` | Profiles |
| `core_config_validate(cfg)` | Enforces power-of-two page size and positive limits |

### Contracts (`xiom.core.contracts`)
| Function | Description |
|----------|-------------|
| `is_power_of_two(n)` | Power-of-two check |
| `is_valid_page_size(size)` | Power of 2, 512–65536 |
| `is_valid_dimension(dim)` | 1–65536 |
| `is_valid_key_size(size)` | 1–4096 |
| `is_valid_top_k(k)` | 1–10000 |
| `is_valid_lsn_ordering(prev, next)` | LSN strictly increasing |
| `is_sorted_ints(v)` | Non-decreasing order check |

### Metrics (`xiom.core.metrics`)
| Function | Description |
|----------|-------------|
| `Counter` / `Gauge` / `Histogram` / `MetricsRegistry` | Observability primitives |
| `counter_new/inc/add` | Monotonic counters |
| `gauge_new/set` | Point-in-time gauges |
| `histogram_new/observe` | Bucketed distributions |
| `registry_new/add_counter/add_gauge` | Registry |

### Version (`xiom.core.version`)
| Function | Value |
|----------|-------|
| `engine_version()` | `"0.1.0"` |
| `storage_format_version()` / `wal_format_version()` | 1 / 1 |
| `protocol_version()` / `snapshot_format_version()` | 1 / 1 |

### Storage (`xiom.core.storage.*`)
| Function | Description |
|----------|-------------|
| `page_new / page_is_dirty / page_pin / page_unpin` | Buffered page unit |
| `crc32(data)` / `verify_checksum(data, expected)` | FNV-1a corruption detection |
| `pager_new / pager_alloc_page / pager_read_page / pager_flush` | Page allocator (in-memory) |
| `buffer_pool_new / get / put / hit_ratio` | Frame cache with hit/miss stats |

### WAL (`xiom.core.wal.*`)
| Function | Description |
|----------|-------------|
| `WalLsn`, `wal_lsn / wal_lsn_value / wal_lsn_next` | Log sequence number |
| `WalOpKind`, `WalRecord`, `wal_record_new` | Canonical durable record |
| `wal_writer_new / append / flush / current_lsn` | WAL-before-ack writer (in-memory) |
| `wal_read_all / wal_read_from` | Sequential + point-in-time reads |
| `checkpoint_new / checkpoint_can_truncate` | Checkpoint + truncation safety |
| `recovery_scan` | Post-checkpoint replay scan |

### Transactions (`xiom.core.txn.*`)
| Function | Description |
|----------|-------------|
| `TxnStateKind`, `txn_state_can_commit / is_terminal` | Lifecycle state machine |
| `txn_manager_new / txn_begin / txn_commit / txn_abort` | In-flight txn coordination |
| `snapshot_new / snapshot_is_visible` | Stable read snapshots |

## Production Readiness

| Module | Status |
|--------|--------|
| `error`, `result`, `ids`, `limits`, `config`, `contracts`, `metrics`, `version` | ✅ Implemented |
| `storage/page` (pin/dirty) | ✅ Implemented |
| `storage/checksum` (FNV-1a) | ✅ Implemented |
| `storage/pager` (in-memory alloc/read) | ✅ Implemented |
| `storage/pager` (disk flush/fsync) | ⚠️ Scaffolded — TODO(Phase 2), needs FFI |
| `storage/buffer_pool` (in-memory cache) | ✅ Implemented |
| `storage/buffer_pool` (clock/LRU eviction) | ⚠️ Scaffolded — TODO(Phase 1) |
| `wal/lsn`, `wal/wal_record` | ✅ Implemented |
| `wal/wal_writer` (in-memory append) | ✅ Implemented |
| `wal/wal_writer` (fsync durability) | ⚠️ Scaffolded — TODO(Phase 2), needs FFI |
| `wal/wal_reader` (in-memory) | ✅ Implemented |
| `wal/checkpoint` | ✅ Implemented |
| `wal/recovery` (post-checkpoint scan) | ✅ Implemented (in-memory) |
| `wal/recovery` (torn-page / disk recovery) | ⚠️ Scaffolded — TODO(Phase 2) |
| `txn/txn_state`, `txn/txn_manager`, `txn/snapshot` | ✅ Implemented (in-memory) |
| Disk persistence / mmap | ❌ Not yet (Phase 2) |
| Full transaction isolation (MVCC) | ❌ Not yet (Phase 3) |

## Build & Run

```bash
xiomc --run myprogram.xi
```

## Dependencies

- [`xiom-std`](https://github.com/xiom-lang) `0.1.0` — core collections, strings, and IO primitives.

## Links

[github.com/xiom-lang](https://github.com/xiom-lang) | [XIOM](https://github.com/xiom-lang/XIOM) | Used by [xiom-db](../xiom-db) and [xiom-vector](../xiom-vector)

## License: MIT OR Apache-2.0
