<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# ORBITDB reference extraction matrix (standing protocol)

> **Owner directive 2026-10-17 (non-negotiable).** We do not design from
> memory and we do not aim for small MVPs. The cloned battle-tested projects
> under `E:\repos` are the design source: for every slice we **crawl the real
> files/functions/mechanics**, record them here, and **convert them into a
> XIOM way** in this repo. If a mechanic needs stdlib/packages work or hits a
> compiler defect, we file the blocker through the relay bus (wishlist or
> bug), keep the slice moving on a documented fallback, and **re-test back on
> the next release / package publish**. This file is the extracted data
> matrix: consult it before inventing anything; extend it on every crawl.

## 0. The loop (enforce per slice)

1. **Crawl** the reference tree(s) for the exact slice (file:line + symbol).
2. **Extract** the mechanic into a row below (decision: adopt / adapt / avoid).
3. **Convert** to XIOM using the row's notes; cite the rows in the slice's
   design doc.
4. **Blocker?** -> relay item (stdlib wishlist / packages wishlist / compiler
   bug) with a minimal repro; document the fallback; test back on the next
   archive/package publish.
5. **Verify** with the lane evidence rules (suite x2 both, crash x2, fuzz,
   soak) and update the row's status.

References are read-only: never edit `E:\repos` trees. Crawl dates are
recorded per row; re-crawl before relying on a row older than its slice.

## 1. Engine slice rows (crawled 2026-10-17)

### 1.1 Pager / lazy page access / bounded cache (M1.1b)

| Mechanic | Reference (verified) | Decision | ORBITDB conversion |
|---|---|---|---|
| Page fetch with a cache lookaside; miss -> read -> pin; write -> mark dirty | `E:\repos\sqlite\src\pager.c` `sqlite3PagerGet` (l.5788), `getPageNormal`/`getPageMMap` (decl. l.1035-1038), `pagerStress` (l.4663) | adapt | our `byte_io` random-access (`read_at`/`write_at`) is the I/O seam; add a page cache keyed by `node_idx` with a dirty flag; lazy load from the v2 block store on miss |
| Cache replacement with pin protection + memory-pressure spill | `E:\repos\sqlite\src\pcache.c` (pcache1 page cache; `sqlite3PcacheFetch`) | adopt (shape) | we already have the clock (second-chance) frame table with pinning (C4); M1.1b wires it to durable node loads instead of the resident arena |
| File-page cache split from the page manager (read-through cache boundary) | `E:\repos\redb\src\tree_store\page_store\cached_file.rs`; `lru_cache.rs` (`insert` l.30, `get` l.67, `pop_lowest_priority` l.93) | adapt | one cached-file layer over the block store; LRU list with a capacity bound; keep the clock policy for MVCC pins (redb's LRU is a useful fallback/eviction-order reference) |
| Page allocation + write/read boundary kept separate from tree logic | `E:\repos\redb\src\tree_store\page_store\page_manager.rs` (`allocate` l.224, `free` l.246, `free_if_uncommitted` l.251, `rollback_all` l.216) | adopt | M1.1b module boundary: `pager` (load/store/evict) vs `btree` (structure) vs `engine` (API) -- matches the R1/R2 split target |

### 1.2 Free-space management / deferred free (M1.1b deferred-free allocator)

| Mechanic | Reference (verified) | Decision | ORBITDB conversion |
|---|---|---|---|
| Pending-free list per transaction; pages released only after the committing tx is durably published | `E:\repos\bbolt\internal\freelist\freelist.go`; `E:\repos\bbolt\tx.go` `Commit` (l.170), `commitFreelist` (l.285), `Rollback` (l.302), `allocate` (l.501) | adopt | pending-free list keyed by the engine LSN/generation; release on checkpoint publication; never reuse pages above `db_file_min_pinned_lsn` (M3 hook already exists) |
| Free-space tracked by generations; reader-visible generations hold frees back | bbolt `freelist` pending cache + txid release | adopt | `pin_clock`/generation is our existing analog; add the pending list to `NodeStore` |
| Buddy allocator with per-order bitmaps (serialized, checksummed) for variable-sized page runs | `E:\repos\redb\src\tree_store\page_store\buddy_allocator.rs` (`alloc` l.370, `free` l.440, `record_alloc` l.399, `free_inner` l.448, `from_bytes` l.118, `to_vec` l.93) | adapt (only if fragmentation demands) | our node pages are fixed-size 4096-byte blocks; keep the simple bump/freelist first; the buddy bitmap is the fallback when multi-page runs appear |

### 1.3 Snapshots / MVCC / savepoints

| Mechanic | Reference (verified) | Decision | ORBITDB conversion |
|---|---|---|---|
| Read transactions published by tx id; memory freed only below the lowest active reader | `E:\repos\redb\src\tree_store\page_store\active_transactions.rs`; `page_manager.rs` `allocations_after` (l.468) | adopt | maps to `db_file_min_pinned_lsn`; extend to free the COW shadow once all pins below a generation retire (M1.1b version GC) |
| Savepoint = transaction-scoped marker with rollback of post-marker allocations | `E:\repos\redb\src\tree_store\page_store\savepoint.rs` | adopt (confirm) | we already ship txn savepoints (buffer trim + WAL window splice); the page-side rollback of post-marker allocations is the missing piece for pinned COW |
| Ephemeral allocation regions per transaction | redb `TransactionalMemory` + `region.rs` | adapt | our arena grows under pins today; per-transaction regions are the M1.1b shape |

### 1.4 Commit / checkpoint / recovery markers

| Mechanic | Reference (verified) | Decision | ORBITDB conversion |
|---|---|---|---|
| Commit gate: journal/WAL first, then publish the new page set with a generation/commit marker | `E:\repos\sqlite\src\pager.c` `sqlite3PagerOpen` (l.4789), commit-phase/journalling path; `E:\repos\sqlite\src\wal.c` `walIndexReadHdr` (l.2742), `sqlite3WalCheckpoint` (call l.2616) | adopt (already) | our WAL-before-ack + generation-committed two-slot header + checkpoint anchor already implement this; keep the row as the conformance reference |
| Double-buffered meta pages with checksums; newest valid wins | `E:\repos\bbolt\db.go` (`beginRWTx` l.839), `page.go`, `meta` handling; `E:\repos\bbolt\node.go` (node read/write) | adopt (already) | v2 block container two header slots + CRC32C (verified in suite/block KAT); node deep-copy rules stay |
| Fsync ordering: data pages synced before the commit marker; directory sync on rename | SQLite `pager.c` commit-phase ordering; bbolt `tx.Commit` (l.170) | adopt (already) | S4: 2PC WAL flush before checkpoint publish + rename durability + dir sync (landed 2026-10-13) |
| Page checksum chains / torn-tail detection | SQLite WAL frame checksums (`wal.c`); bbolt meta checksum | adopt (already) | CRC32C per block/page + torn-tail heal (O(1) via `append_line_sync`) |

### 1.5 B-tree / cursor / index mechanics

| Mechanic | Reference (verified) | Decision | ORBITDB conversion |
|---|---|---|---|
| B-tree page allocation modes (exact/nearby/any) + overflow pages | `E:\repos\sqlite\src\btree.c` `allocateBtreePage` (l.4049), `sqlite3BtreeOpen` (l.2562), `sqlite3BtreeBeginTrans` (l.3835) | adapt | our order-N node pages are fixed; nearby allocation informs future page placement (locality); overflow pages do not apply (payload budget caps rows at 1978/1308/973 B) |
| Cursor over a B-tree with range iteration | `E:\repos\bbolt\cursor.go`; `bucket.go` | adopt (shape) | our `btree_range_query` covers iteration; cursor-level seek/next is the M1.1b paged-cursor target |

## 2. Benchmark methodology rows (crawled 2026-10-13, kept current)

| Mechanic | Reference | Decision | ORBITDB conversion |
|---|---|---|---|
| Per-query CV discipline, result-equality cross-checks, environment recording | `E:\repos\db-benchmarks` | adopt | `docs/BENCH-1.md` + `scripts/bench_cross.*` already implement this (verify parity + raw logs + load caveats) |
| Embedded league rows (SQLite/bbolt) on identical deterministic streams | `E:\repos\db-benchmarks` methodology + `E:\repos\bbolt` driver | adopt | R1-R4 matrix in `docs/BENCH-1.md`; extend at ST7 for the Station league |

## 3. Station tier rows (crawl at ST1; references present, not yet extracted)

Candidates cloned and available: `h11` (HTTP/1.1 connection state machine --
framing/keep-alive/upgrade patterns for ORBITWIRE session mechanics),
`fastify`/`gin`/`fasthttp` (listener + session lifecycle, hook ordering,
backpressure), `knex` (query builder -> executor split, mirrors our
planner/executor boundary), `bullmq` (job locking + script-based atomic
operations -- informs replica promotion/lock discipline). These rows are
filled when ST1 freezes the ORBITWIRE surface; do not convert before G-START.

## 4. Blocker ledger (relay items opened from crawl findings)

| Slice | Blocker | Relay item | Status |
|---|---|---|---|
| M1.1b pager | random-access byte IO + fsync + file_lock | `REL-20261012-1945-orbitdb` (stdlib); locked rows closed 2026-10-13; `file_lock` remains the M3/G-START gate | open (file_lock) |
| M1.1b pager | lazy load needs `read_at`/`write_at` (landed waves 115/118) | adopted in S4; no new ask | closed |
| Station ST4 | log-shipping local leg on `xiom.durable` (fsync honesty check) | `REL-20261016-1128-orbitdb-2` / packages reply `-1150-packages-3` | tracked |
| Station ST6 | TLS server side / ALPN | stdlib `REL-20261016-1128-orbitdb`; packages TLS binding | tracked (xiom.ssl building) |
