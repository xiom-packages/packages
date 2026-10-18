<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# Reference study 04 -- lattice mechanics (single-writer, durability, gates) vs xvector (2026-10-16)

Owner-granted study area (`E:\repos`); licenses verified in-clone: bbolt MIT
(`LICENSE`: "Copyright (c) 2013 Ben Johnson"), redb MIT OR Apache-2.0
(`LICENSE-MIT`: "Copyright (c) 2021 Christopher Berner"), sqlite-vec
MIT OR Apache-2.0 (`sqlite-dist.toml:3`), sqlite **public domain**
(`LICENSE.md:4` "SQLite Is Public Domain"), ann-benchmarks MIT (`LICENSE`:
"Copyright (c) 2018 Erik Bernhardsson"), VectorDBBench MIT (`LICENSE`:
"Copyright (c) 2023 Zilliztech"), vector-db-benchmark Apache-2.0 (`LICENSE`),
zstd BSD-3-Clause OR GPLv2 (`README.md`; we take BSD-3). **No code is vendored
and no build dependency is added**: everything below is ideas/patterns to
re-implement in our tree under our license, each gated by our own probes.
Citations are `<repo>/<path>:<line>` at the shallow clones (`--depth 1`,
2026-10-16). Scope: the lattice plan slices L-1..L-6
(`docs/PRODUCT-ARCHITECTURE.md` sec. 12, `docs/checklists/lattice-v1.md`).

## Why now

The two-tier plan fixes P1-P6 (one engine, one format, single-writer per home,
stateless routing, exactness-first) but leaves the mechanism details open: the
fail-fast on a second writer process (the stdlib advisory-lock ask,
`docs/STDLIB-WISHLIST-XVECTOR.md:28`), the freeze/copy/attach safety of L-2, the
catch-up frontier of L-4, and the measurement methodology of L-6. The six
clusters below are the references for exactly those mechanics.

## What was examined

| Source | License | Primary slice |
|---|---|---|
| bbolt (Go embedded KV) | MIT | single-writer open + locking; batch commit; meta double-buffer |
| redb (Rust embedded KV) | MIT OR Apache-2.0 | durability ladder + repair-on-open; savepoints (L-2) |
| sqlite-vec + sqlite | MIT OR Apache-2.0; public domain | mote quickstart/packaging; WAL frontier semantics (L-1/L-4) |
| ann-benchmarks | MIT | L-6 recall methodology (distance-threshold GT) |
| VectorDBBench + vector-db-benchmark | MIT; Apache-2.0 | L-6 harness: ID-set recall, concurrency sweeps |
| zstd | BSD-3-Clause OR GPLv2 | WAL/snapshot shipping frames (L-4) |

## 1. Single-writer-per-home + advisory locking (bbolt, PRIMARY)

What the reference does: a writer opens the file `O_RDWR|O_CREATE`; a read-only
open uses `O_RDONLY` and makes every write path return immediately
(`db.go:223-230`, `db.go:154-156`, `db.go:839-847`). The open then takes an
**advisory file lock**: exclusive when writable, shared when read-only; a
second writer fails fast (`db.go:246-256` documents the "corruption since two
processes would write meta and free pages separately" reasoning). POSIX: non-blocking `flock(LOCK_NB)` with `LOCK_EX`/`LOCK_SH` in a
retry loop honoring `Options.Timeout` (`bolt_unix.go:17-47`); Windows: byte-range
`LockFileEx` over bytes -1..0 with `LOCKFILE_FAIL_IMMEDIATELY` and the same
timeout loop (`bolt_windows.go:21-54`). `Options.ReadOnly` is documented as
"Uses flock(..., LOCK_SH |LOCK_NB) (UNIX)" (`db.go:1346-1348`); Close skips the
unlock for read-only handles (`db.go:727-731`). In-process, one write
transaction at a time is enforced by a `rwlock` (`db.go:839-847`).

Commit shape: the Meta struct carries magic + format version + checksum and
`Validate()` rejects mismatches (`internal/common/meta.go:12-34`); the meta page
alternates 0/1 by transaction-id parity (`internal/common/meta.go:50-52`), and a
commit fsyncs data pages first, then writes+fsyncs the meta page
(`tx.go:566-572`, `tx.go:594-615`). `Batch` coalesces calls until `MaxBatchSize`
(1000) or `MaxBatchDelay` (10ms), commits them together, and may re-run each
function, so handlers must be idempotent (`db.go:968-1000`,
`internal/common/types.go:28-29`).

**The ONE mechanic worth porting:** the fail-fast open lock, split by mode --
exclusive-for-writer / shared-for-reader, with a bounded retry window and a
typed timeout error. This is the concrete spec for the stdlib `flock`/
`LockFileEx` ask and for L-2/L-4: a second `xvectord` pointed at the same home
refuses to start (or times out) instead of corrupting; a replica or read-only
tool opens shared. Until the stdlib lands, the ops-doc discipline stands.

## 2. Embedded durability + repair-on-open (redb, PRIMARY for L-2)

What the reference does: a 512-byte super-header holds **two commit slots** and
"a single byte that controls which transaction pointer is the primary"
(`docs/design.md:70-75`). That god byte is a bitfield: `primary_bit`,
`recovery_required`, `two_phase_commit` -- the last "is always updated atomically
along with the primary bit", and "redb relies on the fact that this is a single
byte to perform atomic commits" (`docs/design.md:90-99`). Two-phase commit
exists because a 1-phase commit "publishes the secondary slot before flushing
the pages it names, which a reader in another process would then follow"
(`src/transactions.rs:1787-1795`).

The durability ladder on open: if the last commit recorded allocator state
(quick-repair mode), it is loaded directly (`src/db.rs:684-695`,
`src/transactions.rs:1577-1584`); otherwise the open warns "not shutdown
cleanly. Repair required" and walks the trees to rebuild allocator state
(`docs/design.md:455-476`). Repair verifies the primary slot's checksums and
falls back to the secondary; a corrupt primary *despite* 2-phase commit is
fatal (`src/db.rs:1385-1404`). Savepoints are the move-shaped primitive:
registration as a read transaction (pages it references cannot be reused) plus
an allocator-state copy (~64kB per 1GB of data); rollback restores the saved
root and frees everything allocated since, and persistent savepoints survive
restarts via a system table (`docs/design.md:392-404`). Multi-process writers
coordinate via named byte-range locks (writer byte, shared writer byte, an
active-transaction range `TXN_BASE`); before freeing pages a writer scans the
range for the oldest active transaction, and compaction is refused while one
is live (`src/db.rs:185-200`, `docs/design.md:516-521`, `docs/design.md:624-635`).

**The ONE mechanic worth porting:** publish-last with a validated fallback --
never flip the manifest/registry entry until the copied bytes are durable, and
give open-time recovery a ladder (load a recorded state; else walk and rebuild;
else refuse). For L-2 the move becomes: freeze (flush/checkpoint, record the
frontier + registry entry) -> copy -> fsync -> single manifest flip; a kill
mid-copy leaves the old entry primary and the partial copy is garbage the
ladder ignores. Our temp+rename already gives the atomic flip; this study adds
the checksummed entry + recovery-required discipline around it.

## 3. Embedded UX + packaging (sqlite-vec) and WAL frontier (sqlite)

What the reference does: sqlite-vec is a single C file, "no dependencies, runs
anywhere SQLite runs" (`README.md:15-18`); the quickstart is `.load ./vec0`
then `create virtual table ... using vec0(...)` -- no server, no daemon
(`README.md:61-68`). The same source builds as a loadable extension
(`SQLITE_EXTENSION_INIT1`) or an amalgamation for embedding (`SQLITE_CORE`)
(`sqlite-vec.c:18-23`); one entry point `sqlite3_vec_init` registers everything
(`sqlite-vec.c:10632-10636`, `:10705`), and one config ships amalgamation .c/.h,
pip, npm, gem packages (`sqlite-dist.toml:10-14`).

SQLite's WAL is the reference for L-4's frontier. The file is a header plus
frames; a transaction commits when a commit-marker frame lands; a checkpoint
copies frames into the database (`src/wal.c:16-32`). The header carries a
checkpoint sequence and two salts (`src/wal.c:37-44`); a frame is valid only if
salts match and a cumulative checksum over the header and all frames up to it
verifies -- so a torn tail is simply the longest valid prefix
(`src/wal.c:59-68`). After a checkpoint, salt-1 is incremented and salt-2
re-randomized so old and new frames can never validate together after a crash
(`src/wal.c:89-98`). Readers snapshot by recording the last valid frame
(`mxFrame`) and ignoring everything appended later -- each reader sees a
consistent prefix while writers continue (`src/wal.c:100-117`). The wal-index is
transient shared memory, which is why `journal_mode=WAL` is unsupported on
network filesystems (`src/wal.c:127-146`).

**The ONE mechanic worth porting:** the reader-frontier snapshot. L-4 replica
catch-up = "record a frontier (locate the WAL position/sequence), replay a
prefix, expose lag as frontier distance"; the mxFrame contract is the shape to
pin against our actual WAL records (the L-4 design task). Secondary: the L-1
quickstart should read like the sqlite-vec one -- open the home in-process and
run; the "extension" is our own library, and the packaging lesson is one
artifact tree shipped to several channels (`sqlite-dist.toml`).

## 4. Gate methodology (ann-benchmarks; VectorDBBench; vector-db-benchmark)

What the references do: ann-benchmarks builds ground truth per dataset with
`BruteForceBLAS` and stores the top-`count` (default 100) neighbor ids (int)
and distances (float) next to train/test (`ann_benchmarks/datasets.py:78`,
`:105-120`). Its recall@k is a **distance-threshold count**: the k-th true
distance + epsilon (1e-3) is the threshold and results within it score, meaned
over queries (`ann_benchmarks/plotting/metrics.py:6-23`). Queries run
`run_count` times, optionally batched, and the harness reports the best search
time (`ann_benchmarks/runner.py:22-43`).

VectorDBBench computes recall as an **ID-set intersection**: `|top-k returned
IDs ∩ ground truth| / k` (`vectordb_bench/metric.py:110-116`), plus recall_at
cutoffs and NDCG (`:151-176`). Ground truth ships as a precomputed artifact
whose width must be >= the requested k (`backend/dataset.py:258-262`,
`backend/runner/serial_runner.py:224-233`). The serial runner times every query
and reports p50/p95/p99 (`serial_runner.py:262-301`); the concurrency sweep
walks default concurrencies [1, 5, 10, 15, 20, 25, 30, 35] at 30s each with
HDR-histogram latencies (`mp_runner.py:24-38`). Two contract flags matter for
harness honesty: `thread_safe` (unsafe clients are deep-copied per worker,
`api.py:186-191`) and `supports_batch_search` -- "sequential calls to
search_embedding are not a batch implementation" (`api.py:381-395`).

vector-db-benchmark measures per-query `perf_counter` latency and precision
`|top ∩ expected[:top]| / top` (`engine/base_client/search.py:37-56`), reporting
rps/p95/p99/mean/std over a multiprocessing pool (`:58-115`); uploads run
parallel x batch_size (default 64) (`engine/base_client/upload.py:34-45`). The
same client harness benches single-node and 3-node cluster topologies as
separate server composes (`engine/servers/qdrant-single-node/` vs
`engine/servers/qdrant-cluster-mode/`) -- the router-visible tier is benched by
swapping the topology, not the client.

**The ONE mechanic worth porting:** the L-6 gate runs BOTH recall definitions
against single-node ground truth on the same corpus: ID-set equality for the
Flat exactness arm (VectorDBBench style; "equal result sets" is the checklist
wording) and distance-threshold recall (ann-benchmarks style, epsilon pinned)
for the HNSW arm, with per-shard oversampling as the tuned knob and p50/p95/p99
latencies reported per concurrency level.

## 5. Shipping/compression (zstd, PRIMARY for L-4)

What the reference does: `ZSTD_compressStream2` drives one frame with three
directives (`lib/zstd.h:783-794`): `ZSTD_e_continue` collects; `ZSTD_e_flush`
"creates (at least) one new block, that can be decoded immediately on
reception" while the frame continues and future data may still reference
earlier data (ratio preserved); `ZSTD_e_end` flushes and closes the frame --
the epilogue is required for decoders to consider the frame complete
(`lib/zstd.h:762-767`), the return value is the minimum bytes still to flush
and must reach 0 (`lib/zstd.h:796-826`). Frames are independent of each other
(`lib/zstd.h:789-792`); decompression is the same contract via `input.pos`/
`output.pos` (`lib/zstd.h:926-936`). Multithreaded streaming (nbWorkers >= 1)
turns calls non-blocking and interleaves jobs (`lib/zstd.h:471-479`).

**The ONE mechanic worth porting:** ship WAL/snapshot bytes as frame streams --
`e_flush` boundaries give a lagging replica progressive decode within one
shipping session; `e_end` per snapshot makes every snapshot an independently
decodable frame, so a restarted replica ships the next snapshot without
cross-frame state. Keep nbWorkers = 0 so shipped bytes stay deterministic.

## Port candidates

| Mechanic | Reference (cited) | Slice | Effort |
|---|---|---|---|
| Fail-fast writer/shared reader open lock + typed timeout | `bbolt/db.go:246-256`, `bolt_unix.go:17-47`, `bolt_windows.go:21-54` | L-1/L-2/L-4 | M (needs stdlib ask) |
| Publish-last + checksummed entry + recovery ladder on open | `redb/docs/design.md:70-99`, `src/transactions.rs:1787-1795`, `src/db.rs:684-695,1385-1404` | L-2 | S/M |
| Freeze snapshot (frontier + registry state) for the move unit | `redb/docs/design.md:392-404` | L-2 | S |
| Reader-frontier catch-up (mxFrame semantics) | `sqlite/src/wal.c:100-117` | L-4 | S (after the L-4 design pin) |
| Frame-stream shipping with flush boundaries | `zstd/lib/zstd.h:783-794` | L-4 | M |
| Batch coalescing window (size + delay, idempotent retries) | `bbolt/db.go:968-1000`, `internal/common/types.go:28-29` | L-5 | S |
| Dual recall methodology vs single-node ground truth | `ann-benchmarks/ann_benchmarks/plotting/metrics.py:6-23`; `VectorDBBench/vectordb_bench/metric.py:110-116` | L-6 | S |
| Concurrency sweep + latency percentiles; real batch API contract | `VectorDBBench/.../mp_runner.py:31-38`, `backend/clients/api.py:381-395`; `vector-db-benchmark/engine/base_client/search.py:99-115` | L-6/G-2 | M |
| One-file/no-server quickstart + multi-channel packaging shape | `sqlite-vec/README.md:61-68`, `sqlite-dist.toml:10-14` | L-1 | S |

## Traps and explicit non-actions

- **No mmap-dependent design.** bbolt is mmap-centric (data reachable through a
  mapped region; remap on grow). Our mmap story is gated (P5); the lock/batch
  mechanics port, the IO model does not.
- **No persisted freelist.** bbolt's `NoFreelistSync` trades a recovery walk for
  write speed (`db.go:57-60`); we rebuild state from manifest + segments and
  must not add a crash-consistency burden we do not need.
- **No shared-memory WAL index.** SQLite's wal-index requires local shared
  memory and rules out network filesystems (`src/wal.c:127-146`); replicas ship
  bytes over the wire, and homes stay on local disks (ops-doc rule).
- **Threshold recall alone is not exactness.** ann-benchmarks' epsilon band can
  score wrong IDs near the k-th distance; exactness claims use the ID-set arm.
- **No multi-writer machinery.** redb's multi-writer mode (shared-writer byte,
  txn range) exists to support designs P3 forbids; borrow the single-byte
  publish + repair ladder only.
- **No multithreaded zstd for shipped bytes** (determinism), and no
  uncompressed version drift: compression wraps bytes, never changes the format.
- **No vendoring:** adopted patterns land as original implementations with our
  probes; commits note this study as the source.

## License lines (verified in-clone)

- bbolt -- MIT (`LICENSE`).
- redb -- MIT OR Apache-2.0 (`LICENSE-MIT`, `LICENSE-APACHE`).
- sqlite-vec -- MIT OR Apache-2.0 (`LICENSE-MIT`, `sqlite-dist.toml:3`).
- sqlite -- public domain (`LICENSE.md`).
- ann-benchmarks -- MIT (`LICENSE`).
- VectorDBBench -- MIT (`LICENSE`); vector-db-benchmark -- Apache-2.0 (`LICENSE`).
- zstd -- BSD-3-Clause OR GPLv2 (`README.md`); usage here would take BSD-3.

## Open questions for the lane

1. Lock scope for the stdlib ask: exclusive writer byte + shared reader byte on
   a dedicated lock file (bbolt's split), which byte range on Windows (bbolt
   uses -1..0)? This shapes the wishlist row (`docs/STDLIB-WISHLIST-XVECTOR.md:28`).
2. Does our WAL expose a monotonic frontier/sequence today, or does L-4 start
   with snapshot + tail replay (the architecture doc's fallback)? The frontier
   semantics above are portable only if that position is well-defined.
3. For L-2, is a checksummed manifest entry + recovery ladder enough, or do we
   also record a redb-style "recovery required" state in the home so a
   half-attached registry is detected on open (vs on first read)?
4. L-6: pin the distance-threshold epsilon and the exact-set arm corpora; what
   oversample default does the gate license (2-3x assumed in `docs/PRODUCT-LAYERS.md`)?
5. Compression first for snapshots (whole-file frames) or WAL shipping
   (checkpoint-window frames), and should the frame format be versioned in the
   home manifest?
