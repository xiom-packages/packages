# xiom.durable Roadmap

A phased plan for growing the shared substrate from an in-memory foundation to a fully durable, concurrent engine core. Each phase is independently useful and keeps the downstream engines (`xiom-db`, `xiom-vector`) buildable at every step.

Legend: [OK] done - [BLUE] in progress - [WHITE] planned

---

## Phase 0 -- Core substrate (in-memory)  [OK] DONE

The foundation every other phase builds on. Complete and usable today.

- [OK] Typed error model (`CoreError`) with retryability classification.
- [OK] `Result` convention + serializable `ResultInfo`.
- [OK] Strong single-field ID wrappers (PageId, Lsn, SegmentId, TxnId, CollectionId, VectorId, ShardId).
- [OK] System-wide limits and format-version constants.
- [OK] `CoreConfig` with validation and dev/prod profiles.
- [OK] Shared contract predicates (`contracts.xi`).
- [OK] Metrics primitives (counters, gauges, histograms, registry).
- [OK] In-memory storage: `Page`, `Pager` (alloc/read), `BufferPool` (cache + stats), FNV-1a checksum.
- [OK] In-memory WAL: `WalRecord`, `WalWriter` (append + LSN assignment), readers, checkpoint, post-checkpoint recovery scan.
- [OK] In-memory transactions: state machine, `TxnManager`, read `Snapshot`.
- [OK] Conformance test suite (`tests/test_conformance.xi`) covering all 105 public functions across 21 modules with 152 test functions, each guarded by a `requires:` contract -- 30 non-trivial contracts exercising invariants (page size validity via `is_valid_page_size`/`is_power_of_two`, LSN monotonic ordering via `is_valid_lsn_ordering`, checkpoint truncation safety, snapshot visibility, config validation).

**Status: complete.** All data structures and contracts are real; only the disk/FFI boundary is stubbed.

---

## Phase 1 -- Real page & buffer management  [WHITE] PLANNED

Harden the in-memory storage layer into a production-quality cache.

- [WHITE] Clock or LRU replacement policy (replace the slot-0 eviction placeholder in `buffer_pool_put`).
- [WHITE] Hash-indexed page lookup (replace linear scan in `buffer_pool_get`).
- [WHITE] Dirty-page write-back coordination and pin-count enforcement on eviction.
- [WHITE] `PageGuard`-style RAII ownership for pinned pages.
- [WHITE] Free-space map for page reuse.

---

## Phase 2 -- Disk WAL + recovery (FFI)  [WHITE] PLANNED

Make writes actually durable. This is the phase that removes every current `TODO(Phase 2)` marker.

- [WHITE] `os_file` FFI boundary (open/read/write/fsync/fdatasync).
- [WHITE] `wal_writer_flush` performs real fsync; WAL-before-ack becomes a hard durability guarantee.
- [WHITE] `pager_flush` writes dirty pages to disk with checksums.
- [WHITE] Disk-backed `wal_reader` with per-record checksum verification.
- [WHITE] `recovery_scan` gains torn-page detection and redo/undo passes.
- [WHITE] On-disk format headers gated by `storage_format_version` / `wal_format_version`.

---

## Phase 3 -- Transaction isolation  [WHITE] PLANNED

Grow the transaction core from bookkeeping into real concurrency control.

- [WHITE] Snapshot isolation using the existing `Snapshot` visibility horizon.
- [WHITE] MVCC version chains keyed by LSN.
- [WHITE] Commit protocol with explicit LSN publication and visibility ordering.
- [WHITE] Lightweight lock/lease scoping for write conflicts.

---

## Phase 4 -- Concurrency & background work  [WHITE] PLANNED

- [WHITE] Typed channels and a bounded background task pool.
- [WHITE] Checkpoint and compaction scheduling with fairness against foreground work.
- [WHITE] Backpressure / bounded work queues (reject overload predictably).

---

## Phase 5 -- Extraction & hardening  [WHITE] PLANNED

- [WHITE] Fault-injection test harness (fake disk, crash points).
- [WHITE] Benchmark suite for pager, WAL, and recovery regressions.
- [WHITE] Formalize the stable public surface consumed by xiom-db and xiom-vector.

---

## Current status

**xiom.durable is at the end of Phase 0.** The in-memory substrate is complete and both downstream engines can depend on it now. Phase 1 (buffer management) and Phase 2 (disk durability) are the next priorities; the FFI boundary is the single blocker for true durability.
