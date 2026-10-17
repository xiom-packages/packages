<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# Reference study: production databases -> ORBITDB (2026-10-11)

Owner granted a reference sandbox at `E:\repos` for cloning battle-tested
databases and lifting production patterns. Three were cloned (shallow) and
studied read-only; every claim below carries `file:line` evidence in the
source repo. **License matrix: bbolt MIT, redb MIT OR Apache-2.0, SQLite
public domain -- all copy-safe for our MIT/Apache dual license.**

## 0. Standing protocol (owner directive 2026-10-17, non-negotiable)

This study is not a one-off: it is the design source for every slice. The
living extraction matrix (file:line + symbols + adopt/adapt/avoid) lives in
`docs/REFERENCE-MATRIX.md`. The loop: crawl -> matrix row -> convert to XIOM
-> blocker? relay (wishlist/bug) + documented fallback -> re-test on the next
release/package publish. No design from memory; no MVPs. The sandbox has
since grown beyond the three databases (db-benchmarks methodology;
h11/fastify/gin/knex/bullmq for the Station tier) -- use the matrix.

| Repo | Pin | Role for us |
|---|---|---|
| `E:\repos\bbolt` (etcd-io/bbolt) | `80c2fe8` | page/tx model, two-slot meta, freelist discipline, crash test matrix |
| `E:\repos\redb` (cberner/redb) | `f403a51` | durability modes (1PC/2PC), snapshot/savepoint mechanics, checksummed commits |
| `E:\repos\sqlite` (sqlite/sqlite) | `6e35c19` | WAL format + checkpoint modes, torn-tail recovery, fault-injection testing |

## 1. Load-bearing mechanisms worth copying

### Commit point (all three agree)
- **One atomic commit marker; everything before it is invisible.** bbolt: the
  meta page write is the only commit point; a failure before the meta fsync
  leaves the old meta authoritative (`bolt/tx.go:193-271`; crash windows
  reasoned at `tx.go:204-271`). redb: a "god byte" packs the primary-bit +
  recovery + two-phase flags so the commit *flip* is a single atomic byte
  (`redb/src/tree_store/page_store/header.rs:60-63,455-466`). SQLite: the WAL
  commit frame is the frame with `nTruncate > 0` (`wal.c:1547-1556,4339-4342`).
- **Checksum the commit record and chain per record.** SQLite frame header
  carries `pgno`, db-size-after-commit, salts, and a rolling two-sum checksum
  seeded by the previous frame's stored checksum (`wal.c:888-944,988-1024,1009-1021`).
  redb checksums each commit slot (xxh3_128 over the header) and keeps a
  Merkle root over pages (`header.rs:55-58,525-530`; `btree_base.rs:54-113`).
- **Recovery = longest valid prefix.** SQLite stops at the FIRST invalid
  frame (salt mismatch, pgno 0, checksum) and ignores everything after it,
  even a later valid-looking commit (`wal.c:1521-1543`).
  redb: prefer the newer valid slot, swap if the primary's checksum fails,
  recompute layout from file length instead of trusting torn counts
  (`header.rs:306-341,225-304`).

### Two-slot headers
- bbolt picks the slot with the larger txid, falls back to the other when
  validation fails, and only panics when BOTH are invalid
  (`db.go:1141-1162,542-550`); alternates slots by `txid % 2`
  (`meta.go:50-52`). We already do two-slot + generation + checksum in the
  v2 block store and page-file generations; **keep the semantics, but note
  the difference: for ORBITDB the snapshot is a CACHE and the WAL is truth,
  so "both slots invalid -> fall back to WAL replay" is correct for us even
  though bbolt must error out.**

### Free-page discipline (deferral by generation)
- bbolt: frees go to a `pending[txid]` list and are NOT allocatable until
  released below the earliest live reader txid; allocation reads only the
  free set (`internal/freelist/shared.go:56-87,141-158`;
  `db.go:821-823,870`); an `allocs` map tripwires double-free and
  same-tx-freed errors (`shared.go:68-81`). Default allocator is the
  deterministic array (lowest contiguous pgid); the span hashmap is opt-in
  (`db.go:62-67`; `array.go:21-61`).
- redb: same idea as epochs: freed pages keyed by txn id, reclaimed only
  below the oldest pinned reader (`transactions.rs:2075-2084,2436-2465`;
  `transaction_tracker.rs:624-632`). A failed commit latches the allocator
  invalid and refuses writes until reopen (`transactions.rs:1772-1780`).

### Snapshots without blocking the writer (M3 minimal subset)
- redb snapshots are just the COW root `{root, checksum, length}` captured
  under the header lock and registered by transaction id
  (`btree_base.rs:115-128`; `transaction_tracker.rs:486-498`); readers never
  lock the writer.
- Savepoint = pinned read txn + saved user root; restore = root swap + free
  everything allocated since (allocation tracking is enabled ONLY while a
  savepoint exists) (`savepoint.rs:29-54,111-127`; `transactions.rs:1400-1495,1437-1468`).
- Compaction refuses to run while a pin exists (`db.rs:1106-1117`).

### Checkpointing (SQLite WAL)
- Modes and guarantees: PASSIVE never blocks (partial backfill), FULL
  busy-waits to backfill to `mxFrame`, RESTART additionally pins readers out
  for a WAL reset, TRUNCATE also truncates (`wal.c:4387-4517,2306-2333,2443-2466`).
- `nBackfillAttempted` is set BEFORE copying and `nBackfill` only advances
  after the copy + fsync, so a crash mid-checkpoint never advances the
  durable prefix (`wal.c:394-400,2356,2418-2420`); the WAL is fsynced before
  the copy and the DB after (`wal.c:2358-2359,2413-2416`).
- Auto-checkpoint after ~1000 frames (4 MB at 4K pages) by default
  (`main.c:2505-2516`; `sqliteLimit.h:168-169`); WAL resets to frame 1 only
  when fully backfilled AND no readers (`wal.c:3961-3999`).
- Salt/epoch bumps on WAL restart make stale segments detectable by simple
  comparison (`wal.c:2234-2241,1047-1049`).

### Durability modes (redb + SQLite)
- redb `Durability::{None, Immediate}` plus a separate 2PC flag: Immediate
  1PC = exactly one fsync per commit; 2PC adds one flush between slot and
  primary flip (`page_manager.rs:1728-1757`); `None` = zero fsyncs with
  best-effort cache flush and rollback-to-primary on crash
  (`page_manager.rs:1781-1804`). Growth adds an fsync-only before the new
  layout may be published (`page_manager.rs:2297-2304`).
- SQLite WAL: `synchronous=NORMAL` skips the commit-time fsync (durable at
  checkpoint only), `FULL` fsyncs the commit frame (and pads to a sector
  boundary unless POWERSAFE_OVERWRITE) (`wal.c:4281-4298,4283-4295`;
  `pager.c:3645-3661,3700-3703`).

### Fault-injection testing (the part we can adopt IMMEDIATELY)
- SQLite's crash VFS buffers writes in RAM, counts down on each xSync, then
  applies a RANDOM subset of pending writes (some omitted, some sectors
  trashed) and exits (`test6.c:186-347,429-496`); the TCL harness kills at
  the Nth fsync on a target file with a seed and re-checks a logical
  invariant + integrity after every run (`tester.tcl:1752-1814`;
  `walcrash.test:41-72`). Direct WAL-byte/checksum surgery tests exist too
  (`wal_common.tcl:27-80`; `walcksum.test:38-94`).
- redb counts syncs and models durable-vs-live bytes
  (`tests/crash_consistency.rs:18-105`) and has a targeted
  "fail right after the primary swap + corrupt the slot checksum" test
  (`header.rs:642-735`).
- bbolt's failpoints at every commit boundary + power-loss via dm-flakey +
  `check` afterwards (`tests/robustness/powerfailure_test.go:29-36,185-213`;
  `tests/failpoint/db_failpoint_test.go:130-160,318-349`).

## 2. Adoption map (what changes, where)

| Pattern | ORBITDB slice | Decision | Concrete change |
|---|---|---|---|
| Commit-record checksum chain + db-size in the commit | S4/M2.1 (WAL v2) | ADOPT | WAL record gains a rolling CRC32C seeded by the previous record and the commit/anchor record carries the logical row count + next_lsn; recovery stops at the first bad link (we already stop at the first malformed line). |
| Salt/epoch on segment restart | S4/M2.1 | ADOPT | New `wal 2` header line with a restart epoch; truncate/restart bumps it; replay rejects foreign epochs. |
| PASSIVE auto-checkpoint + attempted/backfilled accounting | checkpoint policy (now) | ADOPT | Byte-based threshold (`maybe_checkpoint` by WAL bytes in addition to record count); never advance the durable prefix before the snapshot commit is durable; keep truncate-to-anchor (our RESTART analog) gated on "no pending repair". |
| Durability modes + 2PC flag | M2.1 | ADOPT | `db_file_flush`/config gains `durability` (0 normal, 1 immediate) and a `two_phase` flag; document the power-loss window per mode (NORMAL = checkpoint-durable only). |
| Pending-frees by generation + alloc-txid tripwire | M1.1b/C3 pager | ADOPT | Free pages become allocatable only below the min live snapshot generation; double-free/same-generation-free tripwire in the checker. |
| Deterministic lowest-id allocator first | M1.1b/C3 | ADOPT | Array-style free set (sorted ids, lowest suitable) owns the default; span index only behind a flag if fragmentation shows. |
| Snapshot = pinned generation + root; savepoint = pinned + alloc-diff restore | M3 | ADAPT | Start with `db_file_snapshot_begin` returning {generation, root} + pending-free deferral; savepoints second; no per-page version chains. |
| Compaction refuses while a snapshot is pinned | M3 | ADOPT | `snap_flush`/compact returns busy (-1) when a live pin exists. |
| Refuse writes after a failed commit until reopen | M2.1 | ADOPT | Latch `db_file` (like redb) instead of continuing on a half-applied WAL state. |
| Buffered-write crash injector (countdown on writes/syncs, random partial flush, seeded kill, invariant + check after) | testing, now | ADOPT | A test-only fault layer in the `byte_io` shim (env: `ORBITDB_FAULT_AT_SYNC`, `ORBITDB_FAULT_SEED`) + harness runner; usable with the current no-op sync. |
| Checker as first-class test (reachable-or-freed, double-free, meta invariants) | M1.1b/C3 | ADOPT | Extend the existing structural validator after every crash probe. |
| wal-index / shm double-copied header, mmap remap | -- | AVOID | Our single-process, WAL-first, non-mmap design needs none of it. |
| Per-commit full freelist rewrite | -- | AVOID | Fold free-map deltas at checkpoint instead (bbolt pays a full rewrite + heavy NoFreelistSync scan we don't need). |
| Sector-boundary padding of commits by default | M2.1 | LATER | Offer as an option once fsync lands (needed only without POWERSAFE_OVERWRITE guarantees). |

## 3. Ordered next actions (feed the task order)

1. ~~**M2.1 first half (no stdlib dependency): the durability API + fault
   injector.**~~ **DONE 2026-10-11** (code commit `70f709a`; evidence: 2 suite
   tests + `tests/probes/probe_fault_sync.xi` -- 49 checks; suite 136/136 x2 +
   probe x2 + fuzz x2 on Win + WSL). Shape as landed: `durability`/`two_phase`
   are DBFile handle fields (setters `db_file_set_durability` /
   `db_file_set_two_phase`; reopen resets to defaults) rather than
   `DatabaseConfig` -- the handle is the only consumer today; the `byte_io`
   gates carry `kill|partial|skip|syncfail` (env-armed, one fire per arming,
   `fault_reset` re-arms); the probe runs the crash shapes in-process
   (put/delete syncfail latch + reopen replay, checkpoint-2PC pre-sync window
   with the snapshot file untouched, block-store torn page/header recovery).
   A kill-based harness can build on `mode=kill` (`io.exit(99)`) later. The
   second half (real `fsync` + WAL v2 commit records) rides S4. **Caveat
   found en route: C-ORBIT-07** -- a consumer function silently hijacks a
   module-private same-named call (cost the probe an `arm` naming collision;
   bundle `docs/repro/consumer-fn-hijack/`, bus
   `REL-20261011-1124-orbitdb`).
2. **WAL v2 commit records (checksum chain + row count + epoch) in S4**,
   flag-gated like the v2 snapshot (reader keeps v1).
3. **Checkpoint policy**: byte threshold + attempted/backfilled accounting
   (extend `db_file_maybe_checkpoint`; audit `wal_file_truncate` call sites).
4. **M1.1b/C3 pager**: deterministic free set + pending-frees by generation +
   reachable-or-freed checker, then lazy load on top.
5. **M3**: snapshot pinning + compaction-refusal + savepoint slice as in the
   adoption map.

## 4. Notes / risks

- Our snapshot-is-a-cache model differs from bbolt/redb where the header IS
  the database: both-slots-invalid must stay "fall back to WAL replay",
  not a fatal error (documented in the v2 design already).
- The fault injector must be test-only (env-gated) and must never be wired
  into production paths; keep it inside `byte_io` plus the probes.
- License hygiene: keep patterns in our own idiom; no code is copied
  verbatim from the references (and none of their formats are adopted as
  wire formats -- our formats stay ours).
