# xiom.durable Architecture

xiom.durable is the **shared durable-systems substrate** for the XIOM data ecosystem. It exists so that the two engines that need identical crash-safety and systems plumbing -- [`xiom-db`](../xiom-db) (relational/embedded) and [`xiom-vector`](../xiom-vector) (ANN/vector) -- build on one canonical foundation instead of two drifting copies.

This document is the canonical map of the package: the module tree, the shared-core decision, ownership rules, contract hotspots, failure domains, and the implemented-vs-scaffolded status of every module.

## Design goals and non-goals

**Goals**
- One obvious place for each durability responsibility (pages, WAL, checkpoints, transactions).
- Compiler-enforced correctness: typed errors, strong IDs, and contract predicates instead of implicit invariants.
- Deterministic memory ownership for buffered pages and WAL buffers.
- Explicit, auditable on-disk format versions.
- An in-memory-first implementation that is correct today and swappable for a disk-backed one behind FFI later.

**Non-goals**
- No relational or vector access paths (B-tree, SQL, HNSW, IVF live in the downstream engines).
- No query planning, no ANN math, no network protocol.
- No hidden global mutable state.

## The shared-core decision

Production vector databases are *not* just ANN indexes with an API -- they still need WAL-before-ack, buffered storage, checkpoints, segment/manifest durability, and crash recovery, exactly like a relational engine. Those concerns are **identical** across xiom-db and xiom-vector, so they are factored out here.

What is reused vs. kept separate:

| Reused from xiom.durable | Built fresh downstream |
|-----------------------|------------------------|
| `config`, `error`, `result`, `ids`, `limits`, `metrics`, `version` | Access methods: B-tree (db), HNSW/IVF/PQ (vector) |
| `storage/` page, pager, buffer_pool, checksum | Query planning, cost models, distance kernels |
| `wal/` record, writer, reader, checkpoint, recovery | Collection schema, segment compaction, filter execution |
| `txn/` state, manager, snapshot | SQL parser / relational algebra |

Rule of thumb: **if a concern is about durability or systems plumbing, it belongs in xiom.durable; if it is about the access path or data model, it belongs in the engine.**

## Module tree

```
xiom-durable/
|-- package.xi
|-- README.md
|-- ARCHITECTURE.md          <- this file
|-- ROADMAP.md
|-- SPEC.md
|-- docs/
|   `-- contracts-and-invariants.md
`-- src/
    |-- error.xi             module xiom.durable.error       -- CoreError enum, classification
    |-- result.xi            module xiom.durable.result      -- Result convention + ResultInfo
    |-- ids.xi               module xiom.durable.ids         -- strong single-field ID wrappers
    |-- limits.xi            module xiom.durable.limits      -- system-wide ceilings
    |-- config.xi            module xiom.durable.config      -- CoreConfig + validation + profiles
    |-- contracts.xi         module xiom.durable.contracts   -- shared predicate helpers
    |-- metrics.xi           module xiom.durable.metrics     -- counters/gauges/histograms
    |-- version.xi           module xiom.durable.version     -- format version constants
    |-- storage/
    |   |-- page.xi          module xiom.durable.storage.page        -- buffered page unit
    |   |-- checksum.xi      module xiom.durable.storage.checksum    -- FNV-1a corruption check
    |   |-- pager.xi         module xiom.durable.storage.pager       -- page allocator
    |   `-- buffer_pool.xi   module xiom.durable.storage.buffer_pool -- frame cache
    |-- wal/
    |   |-- lsn.xi           module xiom.durable.wal.lsn        -- WAL log sequence number
    |   |-- wal_record.xi    module xiom.durable.wal.wal_record -- WalOpKind + WalRecord
    |   |-- wal_writer.xi    module xiom.durable.wal.wal_writer -- append + WAL-before-ack
    |   |-- wal_reader.xi    module xiom.durable.wal.wal_reader -- sequential / point-in-time
    |   |-- checkpoint.xi    module xiom.durable.wal.checkpoint -- checkpoint + truncation
    |   `-- recovery.xi      module xiom.durable.wal.recovery   -- post-checkpoint replay scan
    `-- txn/
        |-- txn_state.xi     module xiom.durable.txn.txn_state   -- lifecycle state machine
        |-- txn_manager.xi   module xiom.durable.txn.txn_manager -- in-flight coordination
        `-- snapshot.xi      module xiom.durable.txn.snapshot    -- stable read snapshots
```

## Layered dependency graph

```
error -+
result |
ids   -|   (foundation: no intra-package deps)
limits |
version+
        |
contracts --------------> config (validation)
        |
storage/page --> storage/pager --> (storage/buffer_pool)
storage/checksum
        |
wal/lsn
wal/wal_record --> wal/wal_writer --> wal/wal_reader
                                  `-> wal/recovery
wal/checkpoint
        |
txn/txn_state --> txn/txn_manager
txn/snapshot
```

The foundation modules (`error`, `result`, `ids`, `limits`, `contracts`, `metrics`, `version`) are self-contained. Storage, WAL, and txn build on the foundation and, within their own subtree, on each other (e.g. `pager` uses `page`, `wal_writer` uses `wal_record`, `txn_manager` uses `txn_state`).

## Ownership rules

XIOM's deterministic ownership model is the reason this substrate is worth sharing. The rules the core enforces:

- **Pages.** A `Page` is owned by exactly one container -- either the `Pager` (its home) or the `BufferPool` (a resident copy). `pin_count` records live borrows; a page must not be evicted while `pin_count > 0`. `dirty` pages must be written back before eviction.
- **WAL buffers.** `WalWriter` owns the append buffer. Records enter only through `wal_writer_append`, which is the single point that assigns LSNs. Readers (`wal_reader`) take immutable borrows (`&WalWriter`) and never mutate.
- **Transactions.** `TxnManager` owns the `active` set. A `Txn` transitions state only through `txn_commit` / `txn_abort`, which reconstruct the whole record rather than mutating a field in place, keeping the state machine transitions explicit.
- **IDs are values.** Strong IDs (`PageId`, `Lsn`, ...) are cheap single-field structs passed by value or immutable reference; they carry no ownership of external resources.

## Contract hotspots

These are the places where `requires:` / `ensures:` clauses and the `contracts.xi` predicates concentrate -- the "intent layer" of the engine:

- **LSN monotonicity** -- `is_valid_lsn_ordering(prev, next)`; enforced by `wal_writer_append` assigning strictly increasing LSNs.
- **Page size validity** -- `is_valid_page_size` / `is_power_of_two`; enforced by `core_config_validate`.
- **WAL-before-ack** -- `wal_writer_flush` advances `synced_lsn`; a write is only durable once its LSN <= `synced_lsn`.
- **Checkpoint truncation safety** -- `checkpoint_can_truncate` guarantees only records strictly below the checkpoint LSN are discarded.
- **Snapshot visibility** -- `snapshot_is_visible` fixes the visible LSN horizon for a query.
- **Transaction state transitions** -- `txn_state_can_commit` / `txn_state_is_terminal`.

See [`docs/contracts-and-invariants.md`](docs/contracts-and-invariants.md) for the full catalog.

## Failure domains

All fallible operations surface through the single `CoreError` type -- there are no hidden failure channels.

| Domain | Representative errors |
|--------|-----------------------|
| Lookup | `NotFound`, `OutOfBounds` |
| Input validation | `InvalidInput`, `CapacityExceeded` |
| Durability / IO | `IOFailure` (retryable), `Corruption`, `ChecksumMismatch` |
| Format / compatibility | `VersionMismatch`, `Unsupported` |
| State machine | `InvalidState` |

`core_error_is_retryable` marks only transient `IOFailure` as safe to retry; every logical error is deterministic and must be surfaced to the caller.

## Implemented vs. scaffolded

**Fully implemented (in-memory, production-shaped):**
`error`, `result`, `ids`, `limits`, `config`, `contracts`, `metrics`, `version`, `storage/page`, `storage/checksum`, `storage/pager` (alloc/read), `storage/buffer_pool` (cache/stats), `wal/lsn`, `wal/wal_record`, `wal/wal_writer` (append), `wal/wal_reader`, `wal/checkpoint`, `wal/recovery` (scan), `txn/txn_state`, `txn/txn_manager`, `txn/snapshot`.

**Scaffolded (clear `TODO(Phase N)` markers):**
- `storage/pager::pager_flush` -- disk flush via FFI fsync (Phase 2).
- `storage/buffer_pool::buffer_pool_put` -- clock/LRU eviction replacing slot-0 placeholder (Phase 1).
- `wal/wal_writer::wal_writer_flush` -- real fsync/fdatasync durability (Phase 2).
- `wal/recovery::recovery_scan` -- torn-page detection, checksum verification, redo/undo (Phase 2).

The FFI/disk boundary is deliberately the *only* thing stubbed: every in-memory data structure and every contract is real today, so the engines above can be built and tested end-to-end before durable storage lands.
