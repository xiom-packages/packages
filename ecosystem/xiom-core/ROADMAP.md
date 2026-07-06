# xiom-core Roadmap

A phased plan for growing the shared substrate from an in-memory foundation to a fully durable, concurrent engine core. Each phase is independently useful and keeps the downstream engines (`xiom-db`, `xiom-vector`) buildable at every step.

Legend: ✅ done · 🔵 in progress · ⚪ planned

---

## Phase 0 — Core substrate (in-memory)  ✅ DONE

The foundation every other phase builds on. Complete and usable today.

- ✅ Typed error model (`CoreError`) with retryability classification.
- ✅ `Result` convention + serializable `ResultInfo`.
- ✅ Strong single-field ID wrappers (PageId, Lsn, SegmentId, TxnId, CollectionId, VectorId, ShardId).
- ✅ System-wide limits and format-version constants.
- ✅ `CoreConfig` with validation and dev/prod profiles.
- ✅ Shared contract predicates (`contracts.xi`).
- ✅ Metrics primitives (counters, gauges, histograms, registry).
- ✅ In-memory storage: `Page`, `Pager` (alloc/read), `BufferPool` (cache + stats), FNV-1a checksum.
- ✅ In-memory WAL: `WalRecord`, `WalWriter` (append + LSN assignment), readers, checkpoint, post-checkpoint recovery scan.
- ✅ In-memory transactions: state machine, `TxnManager`, read `Snapshot`.

**Status: complete.** All data structures and contracts are real; only the disk/FFI boundary is stubbed.

---

## Phase 1 — Real page & buffer management  ⚪ PLANNED

Harden the in-memory storage layer into a production-quality cache.

- ⚪ Clock or LRU replacement policy (replace the slot-0 eviction placeholder in `buffer_pool_put`).
- ⚪ Hash-indexed page lookup (replace linear scan in `buffer_pool_get`).
- ⚪ Dirty-page write-back coordination and pin-count enforcement on eviction.
- ⚪ `PageGuard`-style RAII ownership for pinned pages.
- ⚪ Free-space map for page reuse.

---

## Phase 2 — Disk WAL + recovery (FFI)  ⚪ PLANNED

Make writes actually durable. This is the phase that removes every current `TODO(Phase 2)` marker.

- ⚪ `os_file` FFI boundary (open/read/write/fsync/fdatasync).
- ⚪ `wal_writer_flush` performs real fsync; WAL-before-ack becomes a hard durability guarantee.
- ⚪ `pager_flush` writes dirty pages to disk with checksums.
- ⚪ Disk-backed `wal_reader` with per-record checksum verification.
- ⚪ `recovery_scan` gains torn-page detection and redo/undo passes.
- ⚪ On-disk format headers gated by `storage_format_version` / `wal_format_version`.

---

## Phase 3 — Transaction isolation  ⚪ PLANNED

Grow the transaction core from bookkeeping into real concurrency control.

- ⚪ Snapshot isolation using the existing `Snapshot` visibility horizon.
- ⚪ MVCC version chains keyed by LSN.
- ⚪ Commit protocol with explicit LSN publication and visibility ordering.
- ⚪ Lightweight lock/lease scoping for write conflicts.

---

## Phase 4 — Concurrency & background work  ⚪ PLANNED

- ⚪ Typed channels and a bounded background task pool.
- ⚪ Checkpoint and compaction scheduling with fairness against foreground work.
- ⚪ Backpressure / bounded work queues (reject overload predictably).

---

## Phase 5 — Extraction & hardening  ⚪ PLANNED

- ⚪ Fault-injection test harness (fake disk, crash points).
- ⚪ Benchmark suite for pager, WAL, and recovery regressions.
- ⚪ Formalize the stable public surface consumed by xiom-db and xiom-vector.

---

## Current status

**xiom-core is at the end of Phase 0.** The in-memory substrate is complete and both downstream engines can depend on it now. Phase 1 (buffer management) and Phase 2 (disk durability) are the next priorities; the FFI boundary is the single blocker for true durability.
