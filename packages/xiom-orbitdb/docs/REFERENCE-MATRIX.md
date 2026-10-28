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

Re-crawled 2026-10-19 (verified line numbers on the cloned trees).

| Mechanic | Reference (verified) | Decision | ORBITDB conversion |
|---|---|---|---|
| Page fetch with a cache lookaside; miss -> read -> pin; write -> mark dirty | `E:\repos\sqlite\src\pager.c`: `sqlite3PagerGet` l.5788, `getPageNormal` l.5597, `getPageMMap` l.5703, `pagerStress` l.4663 (memory-pressure spill) | adapt | our `byte_io` random-access (`read_at`/`write_at`) is the I/O seam; `ns_get` miss -> `block_store_read` -> node decode -> frame; `ns_set/ns_push` mark per-node + per-frame dirty; `pagerStress` -> dirty-frame spill at the uncommitted write generation |
| PCache lookaside: fetch/release, cache-size enforcement, truncate | `E:\repos\sqlite\src\pcache.c`: `sqlite3PcacheFetch` l.403, `sqlite3PcacheRelease` l.551, `sqlite3PcacheSetCachesize` l.863; `pcache1.c`: `pcache1Fetch` l.1053, `pcache1FetchStage2` l.876, `pcache1FreePage` l.472, `pcache1EnforceMaxPage` l.623, `pcache1TruncateUnsafe` l.648, `pcache1UnderMemoryPressure` l.520 | adopt (shape) | we already have the clock (second-chance) frame table with pinning (C4); M1.1b wires it to node ids instead of Page ids: id->frame slot table + bounded frame array + pin counts. Cache capacity is a NodeStore field (default 256; configurable later). |
| File-page cache split from the page manager (read-through cache boundary) | `E:\repos\redb\src\tree_store\page_store\cached_file.rs`: `CachedFile::new` l.339, `evict_from_read_cache` l.459, `flush_lowest_priority` l.819, `flush_buffered_pages` l.855, `read_cache_bytes` l.305 (byte-bounded); `lru_cache.rs`: `insert` l.30, `get` l.67, `pop_lowest_priority` l.93 | adapt | one pager layer over the v2 block store; bound by FRAME COUNT first (node pages are uniformly 4096 B, so count == bytes/4096); keep the clock policy for MVCC pins (redb's LRU is the eviction-order reference/fallback). Clean frames evict freely; dirty frames spill (`flush_lowest_priority` analog). |
| Page allocation + write/read boundary kept separate from tree logic | `E:\repos\redb\src\tree_store\page_store\page_manager.rs`: `rollback_all` l.216, `allocate` l.224, `allocate_lowest` l.236, `free` l.246, `free_if_uncommitted` l.251, `is_allocated` l.1682, `commit` l.1695, `free_helper` l.1944, `free_if_unpersisted` l.1990, `allocations_after` l.468; `active_transactions.rs`: `lowest_held` l.11 | adopt | M1.1b boundary: pager (load/store/evict/spill) inside `xiom.db.index.btree` (NodeStore) vs tree structure vs engine API. The snapshot block store is the single append-only page container; the pager owns its directory handle so checkpoint appends and dirty spills share one `block_count` (no dual-handle overwrite). |

### 1.2 Free-space management / deferred free (M1.1b deferred-free allocator)

| Mechanic | Reference (verified) | Decision | ORBITDB conversion |
|---|---|---|---|
| Pending-free list per transaction; pages released only after the committing tx is durably published | `E:\repos\bbolt\internal\freelist\shared.go`: `Free` l.56, `Rollback` l.89, `AddReadonlyTXID` l.120, `RemoveReadonlyTXID` l.124, `ReleasePendingPages` l.141, `release` l.160, `releaseRange` l.173, `reindex` l.243; `array.go`: `Allocate` l.21, `freePageIds` l.67, `mergeSpans` l.71; `hashmap.go`: `Allocate` l.61, `addSpan` l.152, `delSpan` l.163; `tx.go`: `Commit` l.170, `commitFreelist` l.285, `Rollback` l.302, `allocate` l.501 | adopt | NodeStore gets `live: Vec[Bool]` + `pending_free: Vec[Int]` (node ids retired by COW/merge/delete). Release rule: erase ids whose retirement epoch is <= `min(active pin generation)`; never below `db_file_min_pinned_lsn` (M3 hook). Dead ids are OMITTED from the next v2 checkpoint/compaction; ids stay monotone (no reuse in M1.1b -- avoids ABA against pinned roots). |
| Free-space tracked by generations; reader-visible generations hold frees back | bbolt `shared.pendingPageIds` (`Freelist` per txid) + `txPending`; `ReleasePendingPages` l.141 | adopt | `pin_clock`/generation is our existing analog; store the retirement epoch in `pending_free_epochs` and release under the oldest live pin. |
| Buddy allocator with per-order bitmaps (serialized, checksummed) for variable-sized page runs | `E:\repos\redb\src\tree_store\page_store\buddy_allocator.rs`: `new` l.39, `to_vec` l.93, `from_bytes` l.118, `alloc_lowest` l.333, `alloc` l.370, `alloc_inner` l.374, `record_alloc` l.399, `free` l.440, `free_inner` l.448 | avoid (for now) | our node pages are fixed-size 4096-byte blocks; deferred free means "omit at compaction", not page-run allocation. Revisit only when multi-page rows/runs appear. |

### 1.3 Snapshots / MVCC / savepoints

| Mechanic | Reference (verified) | Decision | ORBITDB conversion |
|---|---|---|---|
| Read transactions published by tx id; memory freed only below the lowest active reader | `E:\repos\redb\src\tree_store\page_store\page_manager.rs`: `oldest_active_transaction` l.949, `allocations_after` l.468; `active_transactions.rs`: `lowest_held` l.11 (byte ranges of the active set) | adopt | maps to `db_file_min_pinned_lsn`; extend to free COW shadows once all pins below their birth epoch retire (M1.1b version GC via `pending_free`). |
| Savepoint = transaction-scoped marker with rollback of post-marker allocations | `E:\repos\redb\src\tree_store\page_store\savepoint.rs`: `Savepoint` l.29, `new_ephemeral` l.40, `get_version` l.56, `get_transaction_id` l.68, `SerializedSavepoint` l.99 / `from_savepoint` l.112 / `to_savepoint` l.136, `Drop` l.85 | adopt (confirm) | we already ship txn savepoints (buffer trim + WAL window splice); page-side rollback of post-marker allocations is the missing piece for pinned COW -- M1.1b records the post-marker retired-node count in the savepoint and restores `live` on rollback. |
| Ephemeral allocation regions per transaction | redb `TransactionalMemory` + `region.rs` | adapt | our arena grows under pins today; per-transaction regions stay the long-term shape; M1.1b keeps one monotone arena + deferred free (bounded slice). |

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


### 3.1 Admin web client (owner-approved 2026-10-19; runs alongside, not gated)

| Mechanic | Reference (verified 2026-10-19) | Decision | ORBITDB conversion |
|---|---|---|---|
| HTTP/1.1 server core with parser, keep-alive loop, routes and JSON builders | `E:\xiom-packages\packages\xiom-pulse\src\server.xi`: `register` l.447, `out_json` l.212, `out_text` l.218, `out_html` l.224, `serve` l.868, `serve_with` l.877; `router.xi`: `PulseRoute` l.26, `parse_query` l.101; `http.xi`: `header_get` l.258; `config.xi`: `PULSE_PORT` default 8080 l.76 | adopt | `admin/` is a separate app: `xiom.pulse` 0.3.1 + the Satellite engine via source-roots. Localhost bind, GET-only phase 1; token via `ORBITDB_ADMIN_TOKEN`; `X-Pulse-Quit: 1` clean shutdown. |
| Native desktop admin (pgAdmin-like local panel) | `xiom.imgui` README: vendored headless core, no SDL/GLFW/Vulkan backend or widgets yet (Phase 3); `xiom.sdl3` 0.20.0: window/renderer/texture/events | defer | optional later client; the web UI is the primary admin and works headless/remote. Revisit when imgui ships a backend. |
| Admin shape: separate client, not a server-embedded GUI | pgAdmin is a separate application over PostgreSQL; PostgreSQL itself has no GUI | adopt (shape) | the admin is its own program in the same repo; against a Station it attaches over ORBITWIRE (ST1) instead of opening the file. |
### 3.2 ORBITWIRE protocol crawl (ST1 prep, 2026-10-20; conversion waits for G-START)

Verified anchors on the cloned references. ORBITWIRE is a typed binary session
protocol, not HTTP; PULSE already covers the HTTP/admin plane, so these rows
shape session framing, dispatch order, backpressure and promotion locks.

| Mechanic | Verified reference | Decision | ORBITWIRE conversion |
|---|---|---|---|
| Explicit connection state machine; feed bytes, pull events; EOF/keep-alive handled as states | `E:\repos\h11\h11\_connection.py`: `Connection` l.151, `receive_data` l.364, `next_event` l.438, `send` l.514; `_state.py` `ConnectionState` (DONE l.125, CLOSED l.127) | adopt | a small `SessionState` enum + `feed(bytes)`/`next_frame()` split per session; typed, length-prefixed frames with hard max-frame/header limits; EOF transitions to a graceful close; no HTTP chunked encoding |
| Fixed hook order around a request; send pipeline; response finalization | `E:\repos\fastify\lib\hooks.js`: `hookRunnerGenerator` l.230-231, `onSendHookRunner` l.278; `reply.js`: `Reply` l.66, `Reply.prototype.send` l.156, `onSendEnd` l.599 | adopt (order) | session pipeline: auth -> rate/metrics -> parse -> dispatch -> outbound queue; one terminal send per command; hooks must not capture the socket |
| Context chain with explicit next/abort; per-request values | `E:\repos\gin\context.go`: `Context.Next` l.197, `Abort` l.216, `Set` l.285 | adapt | command context with abort + typed metadata (principal, request id); avoid reflection binding; binary commands decode explicitly |
| Builder -> compiler -> runner split (no raw SQL in the executor) | `E:\repos\knex\lib\query\querybuilder.js`: `Builder` l.58, `toSQL` l.83, `then` l.1786; `lib\query\querycompiler.js`; `lib\execution\runner.js` `Runner` l.13; `lib\client.js` `query` l.174 | adopt (boundary) | ORBITWIRE command -> typed plan -> executor; reuse the existing Query/planner/executor seam; the wire carries plan intent, never SQL text |
| Token-based job lock with renewal; atomic lock/release scripts | `E:\repos\bullmq\src\classes\lock-manager.ts`: `LockManager` l.17, `extendLocks` l.46; `worker.ts` lock manager l.217/431; `src\commands\moveToActive-11.lua`, `extendLocks-1.lua`, `extendLock-2.lua`, `releaseLock-1.lua` | adapt | shard ownership uses our `file_lock` + epoch; replica promotion needs a lease token with periodic renewal and a fencing check on commit (ST4); no Redis/Lua |
| Credit/backpressure and partial-write resumption | h11 `PAUSED`/`NEED_DATA` events + fastify `onSend` lifecycle (above) | adopt (shape) | per-session outbound byte budget; pause reads when the queue is over budget; resumable writes; bounded frame queue |

**Converted 2026-10-21 (ST1, G-START green):** every row above is now
implemented in `station/src/` and frozen in `station/docs/ORBITWIRE.md` --
h11 state machine -> `STATE_*` + `session_feed`/`session_pull`; fastify hook
order -> the dispatch gates (auth -> state -> parse -> engine -> one queued
response); gin abort -> error frames/terminal close (no exceptions); knex
builder/executor -> QUERY typed plan fields -> `Query` -> `db_file_query`
(no SQL text); bullmq lock -> M3 `file_lock` with replica lease/fencing
deferred to ST4; credit/backpressure -> bounded queue + read pause + partial
send resume. Evidence: station suites 169/169 x2 Win + x2 WSL.

## 4. Blocker ledger (relay items opened from crawl findings)

| Slice | Blocker | Relay item | Status |
|---|---|---|---|
| M1.1b pager | random-access byte IO + fsync + file_lock | `REL-20261012-1945-orbitdb` (stdlib); locked rows closed 2026-10-13; `file_lock` remains the M3/G-START gate | open (file_lock) |
| M1.1b pager | lazy load needs `read_at`/`write_at` (landed waves 115/118) | adopted in S4; no new ask | closed |
| Station ST4 | log-shipping local leg on `xiom.durable` (fsync honesty check) | `REL-20261016-1128-orbitdb-2` / packages reply `-1150-packages-3` | tracked |
| Station ST6 | TLS server side / ALPN | stdlib `REL-20261016-1128-orbitdb`; packages TLS binding | tracked (xiom.ssl building) |
| Station ST1 codec | `let`/`var` initializer of a Vec from a `match`/`Result` truncates silently (C-ORBIT-14) | `REL-20261021-1136-orbitdb` | fixed on compiler main `478e06f8b`; v0.64.8 predates it -- workaround stays, re-test on release |
| Station ST1 sources | a UTF-8 BOM hides a module from catalog discovery when the declared path != file name (C-ORBIT-15) | `REL-20261021-1157-orbitdb` | fixed on compiler main `18415ede2`; v0.64.8 predates it -- save BOM-free, re-test on release |
