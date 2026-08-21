# xiom-core SPEC

Full API reference for the XIOM shared durable-systems substrate. xiom-core is a pure-XIOM package providing the config, error, identity, storage, WAL, and transaction primitives reused by `xiom-db` and `xiom-vector`.

## Architecture

```
packages/xiom-core/
|-- package.xi                       Package manifest (deps: xiom-std)
|-- README.md - ARCHITECTURE.md - ROADMAP.md - SPEC.md
|-- docs/contracts-and-invariants.md
`-- src/
    |-- error.xi        xiom.core.error
    |-- result.xi       xiom.core.result
    |-- ids.xi          xiom.core.ids
    |-- limits.xi       xiom.core.limits
    |-- config.xi       xiom.core.config
    |-- contracts.xi    xiom.core.contracts
    |-- metrics.xi      xiom.core.metrics
    |-- version.xi      xiom.core.version
    |-- storage/        page - checksum - pager - buffer_pool
    |-- wal/            lsn - wal_record - wal_writer - wal_reader - checkpoint - recovery
    `-- txn/            txn_state - txn_manager - snapshot
```

### Module dependency graph

```
error, result, ids, limits, contracts, metrics, version   (foundation, self-contained)
contracts --> config
storage/page --> storage/pager
storage/checksum, storage/buffer_pool
wal/lsn, wal/wal_record --> wal/wal_writer --> wal/wal_reader, wal/recovery
wal/checkpoint
txn/txn_state --> txn/txn_manager
txn/snapshot
```

---

## Module: `xiom.core.error`

Canonical error type. No hidden failure channels; fallible functions return `Result[T, CoreError]`.

### Enum `CoreError`
`NotFound` - `InvalidInput(msg: Str)` - `OutOfBounds` - `Corruption(msg: Str)` - `IOFailure(msg: Str)` - `Unsupported(msg: Str)` - `CapacityExceeded` - `InvalidState(msg: Str)` - `ChecksumMismatch` - `VersionMismatch`

### Functions
| Signature | Returns | Description |
|-----------|---------|-------------|
| `core_error_to_str(e: &CoreError)` | `Str` | Stable human-readable description of the variant |
| `core_error_is_retryable(e: &CoreError)` | `Bool` | `true` only for `IOFailure`; all logical errors are `false` |

---

## Module: `xiom.core.result`

`Result[T, E]` is built-in. Engine convention: return `Result[T, CoreError]`, propagate with `?`, construct with `Ok(v)` / `Err(e)`.

### Type `ResultInfo`
`{ succeeded: Bool; error_code: Int; }` -- plain-old-data summary for FFI/wire boundaries (`error_code == 0` on success).

### Functions
| Signature | Returns | Description |
|-----------|---------|-------------|
| `is_ok_result(ok: Bool)` | `Bool` | Trivial predicate helper |
| `result_info_ok()` | `ResultInfo` | `{ true, 0 }` |
| `result_info_err(code: Int)` | `ResultInfo` | `{ false, code }` |

---

## Module: `xiom.core.ids`

Strong identifiers as single-field struct wrappers (bare primitive aliases do not compile). All derive `[Clone, Eq]`.

### Types
`PageId` - `Lsn` - `SegmentId` - `TxnId` - `CollectionId` - `VectorId` - `ShardId` -- each `{ value: Int; }`.

### Functions
| Signature | Returns | Description |
|-----------|---------|-------------|
| `page_id(v: Int)` | `PageId` | Construct |
| `page_id_value(id: &PageId)` | `Int` | Unwrap |
| `page_id_eq(a: &PageId, b: &PageId)` | `Bool` | Equality |
| `lsn(v: Int)` | `Lsn` | Construct |
| `lsn_value(id: &Lsn)` | `Int` | Unwrap |
| `lsn_next(id: &Lsn)` | `Lsn` | `value + 1` |
| `lsn_lt(a: &Lsn, b: &Lsn)` | `Bool` | `a < b` |
| `lsn_eq(a: &Lsn, b: &Lsn)` | `Bool` | Equality |
| `lsn_zero()` | `Lsn` | `Lsn{ value: 0 }` |
| `segment_id / _value / _eq` | -- | Construct / unwrap / equality |
| `txn_id / _value / _eq / _next` | -- | Construct / unwrap / equality / increment |
| `collection_id / _value / _eq` | -- | Construct / unwrap / equality |
| `vector_id / _value / _eq` | -- | Construct / unwrap / equality |
| `shard_id / _value / _eq` | -- | Construct / unwrap / equality |

---

## Module: `xiom.core.limits`

System-wide ceilings as functions.

| Function | Value |
|----------|-------|
| `max_dimensions()` | 65536 |
| `max_page_size()` | 65536 |
| `default_page_size()` | 4096 |
| `max_batch_size()` | 100000 |
| `max_key_size()` | 4096 |
| `max_value_size()` | 1048576 |
| `max_segment_count()` | 100000 |
| `default_btree_order()` | 64 |
| `max_graph_degree()` | 512 |
| `max_top_k()` | 10000 |

---

## Module: `xiom.core.config`

### Type `CoreConfig`
`{ page_size: Int; buffer_pool_size: Int; wal_enabled: Bool; sync_on_commit: Bool; data_dir: Str; max_open_files: Int; }`

### Functions
| Signature | Returns | Description |
|-----------|---------|-------------|
| `core_config_default()` | `CoreConfig` | page 4096, pool 1024, wal on, sync on, `./data`, 256 files |
| `core_config_dev()` | `CoreConfig` | Small buffers, sync off, `./data-dev` |
| `core_config_prod()` | `CoreConfig` | page 8192, pool 8192, sync on, `/var/lib/xiom`, 1024 files |
| `core_config_validate(cfg: &CoreConfig)` | `Bool` | page_size power-of-two in [512,65536]; buffer_pool_size & max_open_files > 0 |

---

## Module: `xiom.core.contracts`

Shared predicate helpers.

| Signature | Returns | Rule |
|-----------|---------|------|
| `is_power_of_two(n: Int)` | `Bool` | n > 0 and a power of two |
| `is_valid_page_size(size: Int)` | `Bool` | power of 2, 512-65536 |
| `is_valid_dimension(dim: Int)` | `Bool` | 1-65536 |
| `is_valid_key_size(size: Int)` | `Bool` | 1-4096 |
| `is_valid_top_k(k: Int)` | `Bool` | 1-10000 |
| `is_valid_lsn_ordering(prev: Int, next: Int)` | `Bool` | `next > prev` |
| `is_sorted_ints(v: &Vec[Int])` | `Bool` | non-decreasing |

---

## Module: `xiom.core.metrics`

### Types
- `Counter { name: Str; value: Int; }`
- `Gauge { name: Str; value: Int; }`
- `Histogram { name: Str; buckets: Vec[Int]; counts: Vec[Int]; total: Int; }`
- `MetricsRegistry { counters: Vec[Counter]; gauges: Vec[Gauge]; }`

### Functions
| Signature | Description |
|-----------|-------------|
| `counter_new(name: Str) -> Counter` | New zeroed counter |
| `counter_inc(c: &mut Counter)` | +1 |
| `counter_add(c: &mut Counter, delta: Int)` | += delta |
| `gauge_new(name: Str) -> Gauge` | New zeroed gauge |
| `gauge_set(g: &mut Gauge, value: Int)` | Set value |
| `histogram_new(name: Str, bucket_bounds: Vec[Int]) -> Histogram` | Buckets = inclusive ascending upper bounds |
| `histogram_observe(h: &mut Histogram, value: Int)` | Increment `total` and the first covering bucket |
| `registry_new() -> MetricsRegistry` | Empty registry |
| `registry_add_counter(r: &mut MetricsRegistry, c: Counter)` | Register counter |
| `registry_add_gauge(r: &mut MetricsRegistry, g: Gauge)` | Register gauge |

---

## Module: `xiom.core.version`

| Function | Returns | Value |
|----------|---------|-------|
| `engine_version()` | `Str` | `"0.1.0"` |
| `storage_format_version()` | `Int` | 1 |
| `wal_format_version()` | `Int` | 1 |
| `protocol_version()` | `Int` | 1 |
| `snapshot_format_version()` | `Int` | 1 |

---

## Module: `xiom.core.storage.page`

### Type `Page`
`{ id: Int; data: Vec[Int]; dirty: Bool; pin_count: Int; }`

| Signature | Description |
|-----------|-------------|
| `page_new(id: Int, size: Int) -> Page` | Zeroed page of `size` slots |
| `page_is_dirty(p: &Page) -> Bool` | Dirty flag |
| `page_mark_dirty(p: &mut Page)` | Set dirty |
| `page_pin(p: &mut Page)` | `pin_count += 1` |
| `page_unpin(p: &mut Page)` | `pin_count -= 1` (floored at 0) |

## Module: `xiom.core.storage.checksum`

FNV-1a 32-bit over the low byte of each slot.

| Signature | Description |
|-----------|-------------|
| `crc32(data: &Vec[Int]) -> Int` | 32-bit FNV-1a hash |
| `verify_checksum(data: &Vec[Int], expected: Int) -> Bool` | `crc32(data) == expected` |

## Module: `xiom.core.storage.pager`

### Type `Pager`
`{ page_size: Int; page_count: Int; pages: Vec[Page]; }`

| Signature | Description |
|-----------|-------------|
| `pager_new(page_size: Int) -> Pager` | Empty in-memory pager |
| `pager_alloc_page(p: &mut Pager) -> Int` | Allocate zeroed page, return id |
| `pager_read_page(p: &Pager, id: Int) -> Option[Page]` | Read by id, `None` if out of range |
| `pager_page_count(p: &Pager) -> Int` | Allocated page count |
| `pager_flush(p: &Pager) -> Bool` | **Stub** -- `TODO(Phase 2)` disk fsync via FFI; returns `true` |

## Module: `xiom.core.storage.buffer_pool`

### Type `BufferPool`
`{ frames: Vec[Page]; capacity: Int; hits: Int; misses: Int; }`

| Signature | Description |
|-----------|-------------|
| `buffer_pool_new(capacity: Int) -> BufferPool` | Empty cache |
| `buffer_pool_get(bp: &mut BufferPool, page_id: Int) -> Option[Page]` | Lookup; updates hit/miss |
| `buffer_pool_put(bp: &mut BufferPool, page: Page)` | Insert/replace; placeholder eviction (`TODO(Phase 1)`) |
| `buffer_pool_hit_ratio(bp: &BufferPool) -> Int` | Hit percentage 0-100 |

---

## Module: `xiom.core.wal.lsn`

### Type `WalLsn` `{ value: Int; } derive[Clone]`

| Signature | Description |
|-----------|-------------|
| `wal_lsn(v: Int) -> WalLsn` | Construct |
| `wal_lsn_value(l: &WalLsn) -> Int` | Unwrap |
| `wal_lsn_next(l: &WalLsn) -> WalLsn` | `value + 1` |

## Module: `xiom.core.wal.wal_record`

### Enum `WalOpKind`
`Insert` - `Update` - `Delete` - `SegmentSeal` - `ManifestUpdate` - `Checkpoint` - `SnapshotMarker`

### Type `WalRecord`
`{ lsn: Int; op: WalOpKind; key: Int; value: Int; payload: Vec[Int]; timestamp: Int; }`

| Signature | Description |
|-----------|-------------|
| `wal_record_new(lsn: Int, op: WalOpKind, key: Int, value: Int) -> WalRecord` | New record with empty payload, timestamp 0 |

## Module: `xiom.core.wal.wal_writer`

### Type `WalWriter`
`{ records: Vec[WalRecord]; next_lsn: Int; synced_lsn: Int; }`

| Signature | Description |
|-----------|-------------|
| `wal_writer_new() -> WalWriter` | Empty writer, `next_lsn = 1` |
| `wal_writer_append(w: &mut WalWriter, op: WalOpKind, key: Int, value: Int) -> Int` | Append, return assigned LSN |
| `wal_writer_flush(w: &mut WalWriter) -> Bool` | **Stub** -- sets `synced_lsn = next_lsn - 1`; `TODO(Phase 2)` fsync via FFI |
| `wal_writer_current_lsn(w: &WalWriter) -> Int` | Last assigned LSN |
| `wal_writer_synced_lsn(w: &WalWriter) -> Int` | Last durable LSN |

## Module: `xiom.core.wal.wal_reader`

| Signature | Description |
|-----------|-------------|
| `wal_read_all(w: &WalWriter) -> Vec[WalRecord]` | Copy of all records |
| `wal_read_from(w: &WalWriter, from_lsn: Int) -> Vec[WalRecord]` | Records with `lsn >= from_lsn` |

## Module: `xiom.core.wal.checkpoint`

### Type `Checkpoint` `{ lsn: Int; timestamp: Int; }`

| Signature | Description |
|-----------|-------------|
| `checkpoint_new(lsn: Int, timestamp: Int) -> Checkpoint` | Construct |
| `checkpoint_can_truncate(cp: &Checkpoint, record_lsn: Int) -> Bool` | `record_lsn < cp.lsn` |

## Module: `xiom.core.wal.recovery`

### Type `RecoveryResult` `{ records_replayed: Int; last_lsn: Int; corrupted: Bool; }`

| Signature | Description |
|-----------|-------------|
| `recovery_scan(w: &WalWriter, from_checkpoint: Int) -> RecoveryResult` | Count/track records after checkpoint. `TODO(Phase 2)` torn-page detection |

---

## Module: `xiom.core.txn.txn_state`

### Enum `TxnStateKind`
`Open` - `Prepared` - `Committed` - `Aborted` - `Recovered`

| Signature | Description |
|-----------|-------------|
| `txn_state_can_commit(s: &TxnStateKind) -> Bool` | `true` for Open or Prepared |
| `txn_state_is_terminal(s: &TxnStateKind) -> Bool` | `true` for Committed or Aborted |

## Module: `xiom.core.txn.txn_manager`

### Types
- `Txn { id: Int; state: TxnStateKind; start_lsn: Int; }`
- `TxnManager { active: Vec[Txn]; next_id: Int; }`

| Signature | Description |
|-----------|-------------|
| `txn_manager_new() -> TxnManager` | Empty manager, `next_id = 1` |
| `txn_begin(m: &mut TxnManager, start_lsn: Int) -> Int` | Begin Open txn, return id |
| `txn_commit(m: &mut TxnManager, txn_id: Int) -> Bool` | Mark Committed; `false` if unknown |
| `txn_abort(m: &mut TxnManager, txn_id: Int) -> Bool` | Mark Aborted; `false` if unknown |
| `txn_active_count(m: &TxnManager) -> Int` | Tracked transaction count |

## Module: `xiom.core.txn.snapshot`

### Type `Snapshot` `{ lsn: Int; active_txns: Vec[Int]; }`

| Signature | Description |
|-----------|-------------|
| `snapshot_new(lsn: Int) -> Snapshot` | Snapshot at `lsn` with empty active set |
| `snapshot_is_visible(snap: &Snapshot, record_lsn: Int) -> Bool` | `record_lsn <= snap.lsn` |

---

## Conventions

- **Errors:** every fallible function returns `Result[T, CoreError]`; use `?` to propagate.
- **IDs:** never pass raw `Int` where a typed ID exists.
- **Durability:** honour WAL-before-ack -- flush before acknowledging a write.
- **Scaffolded surfaces** (`pager_flush`, `wal_writer_flush` fsync, `recovery_scan` torn-page, buffer-pool eviction) are marked `TODO(Phase N)` and are the only non-final APIs.
