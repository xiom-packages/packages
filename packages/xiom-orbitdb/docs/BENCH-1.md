<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# BENCH-1 -- embedded cross-engine benchmark (ORBITDB vs SQLite vs bbolt)

> **Status:** 2026-10-16, first release of the harness + numbers. Windows rows
> 1-4 + WSL rows 1/3 captured; WSL rows 2/4 pending (command lines below).
> Numbers are honest for this machine/toolchain pair under the stated load;
> they are regression baselines, not marketing ({same convention as
> docs/PRODUCTION-READINESS.md G1). Methodology adapted from the
> `E:\repos\db-benchmarks` reference league (per-query CV discipline,
> result-equality cross-checks, environment recording) with the embedded
> adaptations recorded here. **2026-10-18: the full R1-R4 matrix is
> recaptured on the ADOPTED v0.64.7 pin (Windows quiet-ish window + WSL);
> see section 4a; the 2026-10-16 tables stay as the first record.**

## 1. What is compared

Three embedded engines, identical deterministic workload, one engine at a
time, fresh database per row:

| Engine | Driver | Version (this run) |
|---|---|---|
| ORBITDB (Satellite engine) | `tests/probes/probe_ycsb.xi` (real engine, v2 container default, order 4) | engine tree @ v0.64.7 pin (2026-10-18), compiler v0.64.7 |
| SQLite | pinned CLI 3.54.0 (`%LOCALAPPDATA%\xiom-orbitdb-tools\sqlite\sqlite3.exe`; `~/.local/bin/sqlite3` on WSL), `journal_mode=WAL` | 3.54.0 (2026-10-09 build) |
| bbolt | `bench/bbolt` (Go 1.24.5, `go.etcd.io/bbolt v1.4.3`) | bbolt v1.4.3 |

Runners: `scripts/bench_cross.ps1` (Windows) / `scripts/bench_cross.sh`
(WSL twin, LF). Raw logs: `probe-logs/bench-cross-*.txt` (gitignored).

## 2. Workload contract (identical across engines)

- Keys `0..N-1`. LCG stream `state = (state*1103515245 + 12345) % 2147483648`;
  op key = `state % n`; scan start = `state % (n-100)`; seed 12345.
- **load**: keys inserted in order 0..N-1; **read/update/scan/delete** each
  start their own fresh stream at the seed (op i is the same on every
  engine).
- Phases: load(N), read(N), update(N), scan(N/100 scans x 100 keys),
  delete(N/10 ops, distinct-key counting via a bitmap so repeated draws do
  not skew verification).
- Values: `vals=8` -> integer `key*7+1` (bbolt holds it as BE64);
  `vals=100` -> 100 ASCII bytes `%08d` + 92 `x` (bbolt: raw bytes; ORBITDB:
  typed row through the PUBLIC codec: `schema_row_encode` per op, i.e. the
  codec cost is inside the timed window like SQLite's TEXT binding).
- Verification parity: every engine must report the same live count
  (`N - distinct_deletes`); all rows below verified (9056 / 45263 / 1805
  across runs).

## 3. Fairness knobs and caveats (read before quoting numbers)

- **Durability rows use each engine's honest fsync**: ORBITDB
  `durability=1` (real fsync at commit ack); SQLite `synchronous=FULL`;
  bbolt `NoSync=false`. `--sync 0` rows: ORBITDB `durability=0`, SQLite
  `synchronous=OFF`, bbolt `NoSync=true` (fast-path ceilings; SQLite OFF
  is also corruption-prone -- durability semantics differ, treat as
  a throughput envelope).
- **Batch** = ops per commit group: ORBITDB engine transaction window;
  SQLite `BEGIN;...;COMMIT`; bbolt one `Update` txn per group.
- **SQLite is driven by the CLI** (same pinned binary both platforms).
  Writes are per-statement (engine-cost dominated in sync rows). Reads are
  ONE statement (n correlated point lookups over a VALUES CTE) to avoid
  per-statement CLI overhead; even so, sqlite read/scan numbers are an
  UPPER BOUND on cost and must not be compared head-on with the in-process
  drivers. Load-vs-update asymmetry (~10x) reproduces on both platforms and
  is SQLite-internal (WAL auto-checkpoint during load), not a driver
  artifact.
- **Shared machine**: both hosts carried other lanes' load. Windows rows
  ran at 4-8x nominal; WSL row 1 ran at load average ~50+ (fsync-heavy
  numbers there are load-depressed lower bounds), WSL row 3 at ~55.
  Re-run on a quiet host before quoting absolute values.
- One bbolt bool-flag nuance: `-sync=` requires the `=` form (Go flags).

## 4. Matrix rows and results

Rows (shared definition; N per row):

- **R1 durable per-op**: N=10000, vals=8, batch=1, sync=1.
- **R2 durable group**: N=50000, vals=8, batch=100, sync=1.
- **R3 nosync per-op**: N=50000, vals=8, batch=1, sync=0.
- **R4 typed rows 100B**: N=10000, vals=100, batch=1, sync=1, point-ops
  only (ORBITDB typed writes are non-txn; scan/delete excluded for parity).

### R1 -- durable per-op (ops/s; all verify 9056)

| phase | orbitdb | sqlite FULL | bbolt sync |
|---|---:|---:|---:|
| load | 611 | 1457 | 579 |
| read | 1,250,000 | 21,053 (CLI-bound) | 3,333,333 |
| update | 646 | 11,891 | 538 |
| scan | 33,333 | 165 (CLI-bound) | (sub-ms) |
| delete | 539 | 760 | 614 |

Windows: `bench-cross-20261016-145026.txt`. WSL (load ~50+, fsync-depressed):
orbitdb 94/101/113, sqlite 184/(28k update)/108, bbolt 112/123/126 --
`bench-cross-wsl-20261016-150719.txt`.

### R2 -- durable group commit, batch=100 (ops/s; all verify 45263)

| phase | orbitdb | sqlite FULL | bbolt sync |
|---|---:|---:|---:|
| load | 885 | 5,705 | 75,301 |
| read | 617,283 | 113,895 (CLI-bound) | 1,388,888 |
| update | 929 | 172,414 | 3,311 |
| scan | 35,714 | 1,587 (CLI-bound) | 500,000 |
| delete | 895 | 7,634 | 3,412 |

Windows: `bench-cross-20261016-145224.txt`.

### R3 -- nosync per-op (ops/s; all verify 45263)

| phase | orbitdb | sqlite OFF | bbolt NoSync |
|---|---:|---:|---:|
| load | 1,136 | 13,473 | 12,239 |
| read | 427,350 | 48,031 (CLI-bound) | 1,136,363 |
| update | 1,133 | 36,443 | 15,552 |
| scan | 38,461 | 371 (CLI-bound) | 500,000 |
| delete | 1,318 | 3,539 | 14,285 |

Windows: `bench-cross-20261016-145541.txt`. **WSL** (load ~55; real WSL
write-path numbers): orbitdb **16,611 / 12,987**, sqlite 46,168 / 36,900,
bbolt 23,843 / 29,515 (load/update) -- `bench-cross-wsl-20261016-151655.txt`.

### R4 -- typed rows, 100-byte values, durable per-op (ops/s; all verify 10000)

| phase | orbitdb (typed rows) | sqlite FULL (TEXT) | bbolt (100B) |
|---|---:|---:|---:|
| load | 464 | 1,356 | 489 |
| read | 555,555 | 14,327 (CLI-bound) | 769,230 |
| update | 483 | 38,610 | 322 |

Windows: `bench-cross-20261016-145809.txt`. The 100-byte typed path is in
the same league as bbolt's raw 100-byte values on this host; SQLite keeps
its load/update asymmetry.

### 4a. 2026-10-18 recalibration on the ADOPTED v0.64.7 pin (Windows)

Window: CPU **43-45%** (desktop floor: qemu/docker/VS Code), **zero lane
compiles**; one residual OS pathology: an unkillable stuck `lld-link`
(PID 94980, created 2026-10-17 18:17, `Temp\kilo\min_test.exe`; taskkill
reports "no running instance" yet it keeps burning ~1 core, ~6% of the
machine). Treat these as the honest quiet-ish baseline; the 2026-10-16
tables above remain the load-stressed first record. All verifies passed
(9056 / 45263); typed/vals=8 rows as specified.

R1 -- durable per-op (N=10000, batch=1, sync=1), log
`bench-cross-20261018-183118.txt`:

| phase | orbitdb | sqlite FULL | bbolt sync |
|---|---:|---:|---:|
| load | **947** | 1,737 | 709 |
| read | 1,250,000 | 10,799 (CLI-bound) | 3,333,333 |
| update | **866** | 61,350 | 803 |
| scan | 100,000 | 3,448 (CLI-bound) | (sub-ms) |
| delete | **784** | 822 | 926 |

R2 -- durable group commit, batch=100 (N=50000), log
`bench-cross-20261018-183233.txt`:

| phase | orbitdb | sqlite FULL | bbolt sync |
|---|---:|---:|---:|
| load | **1,552** | 93,985 | 76,335 |
| read | 769,230 | 192,308 (CLI-bound) | 1,724,137 |
| update | **1,551** | 221,239 | 4,139 |
| scan | 35,714 | 13,514 (CLI-bound) | 500,000 |
| delete | **1,483** | 22,124 | 4,812 |

R3 -- nosync per-op (N=50000), log `bench-cross-20261018-183425.txt`:

| phase | orbitdb | sqlite OFF | bbolt NoSync |
|---|---:|---:|---:|
| load | **1,435** | 21,177 | 12,963 |
| read | 568,181 | 161,812 (CLI-bound) | 1,041,666 |
| update | **1,389** | 42,553 | 12,960 |
| scan | 55,555 | 3,968 (CLI-bound) | 166,666 |
| delete | **1,776** | 19,685 | 11,904 |

vs the 2026-10-16 Windows baselines (load): **R1 611 -> 947 (+55%), R2
885 -> 1,552 (+75%), R3 1,136 -> 1,435 (+26%)** -- the held-handle write
path moving the intended rows, largest on group commit (R2) as predicted.

A/B (interleaved old-vs-new WAL shape) re-run on this window: 5 rounds at
N=3000 -- old/new ms 2701/2376, 2767/2156, 2764/2136, 4369/2030,
2584/2133 -> **5/5 pairs favor the new shape, median ratio 1.28x**
(earlier 10-pair record: 1.26x). Absolute numbers still read as
"quiet-ish shared host", not a lab.

**WSL rows on the same v0.64.7 pin (2026-10-18).** The WSL harness runs
over DrvFs (`/mnt/e`): the durable rows are fsync-bound by the
shared-filesystem path, NOT by the engine -- R1 durable-per-op is 106/s
vs Windows 947/s, while batch=100 (R2 7,225/s) and nosync (R3 23,126/s)
show the same seam. Treat WSL durable absolutes as lower bounds.

R1 WSL (N=10000, sync=1), `bench-cross-wsl-20261018-183908.txt`:
orbitdb **106** load / 833,333 read / **107** update / 25,000 scan / 105
delete; sqlite 202 / 208,333 / 73,529 / 5,000 / 87; bbolt 121 / 5,000,000
/ 114 / (sub-ms) / 112.

R2 WSL (N=50000, batch=100, sync=1), `bench-cross-wsl-20261018-185400.txt`:
orbitdb **7,225** load / 416,666 read / **6,115** update / 38,461 scan /
6,849 delete; sqlite 10,792 / 212,765 / 165,562 / 13,888 / 10,245; bbolt
6,707 / 793,650 / 7,910 / 500,000 / 8,169. (Batch amortizes the DrvFs
fsyncs: 106 -> 7,225.)

R3 WSL (N=50000, sync=0), `bench-cross-wsl-20261018-184755.txt`:
orbitdb **23,126** load / 442,477 read / **16,270** update / 29,411 scan /
22,727 delete; sqlite 45,620 / 216,450 / 76,452 / 17,241 / 44,247; bbolt
28,216 / 1,315,789 / 34,602 / 250,000 / 29,069. vs the 2026-10-16 WSL
baseline (16,611 load / 12,987 update): **+39% / +25%** on v0.64.7.

R4 WSL (N=10000, vals=100, point-only, sync=1),
`bench-cross-wsl-20261018-185932.txt`: orbitdb typed **109** load /
277,777 read / **84** update; sqlite 174 / 200,000 / 8,361; bbolt 103 /
833,333 / 109 -- typed 100 B and bbolt raw 100 B are in the same league
on this path.

### 4e. 2026-10-20 pin-move rerun on v0.64.8 (pre-m375)

Same host, same harness, v0.64.8 (exe `ee3ee902...`), no lane compiles
during the rows. Raw logs: `probe-logs/bench-cross-20261020-152253.txt`
(R1), `-152653` (R2), `-153229` (R3), `-152441` (R4).

| row | load | read | update | scan | delete | verify |
|---|---:|---:|---:|---:|---:|---:|
| R1 (10k, sync=1) | 936 | 1,428,571 | 895 | 50,000 | 998 | 9056 |
| R2 (50k, batch=100) | 559 | 231,481 | 336 | 23,809 | 1,079 | 45263 |
| R3 (50k, sync=0) | 667 | 297,619 | 785 | 17,857 | 984 | 45263 |
| R4 (10k typed 100B) | 579 | 270,270 | 430 | -- | -- | 10000 |

vs the v0.64.7 recalibration (§4a): **R1 and R4 are stable or better**
(R1 load 947 -> 936, update 866 -> 895, delete 784 -> 998; R4 load
464 -> 579, update 483 -> 430 within run noise). **R2/R3 regress hard on
writes at N=50k**: R2 update **1,551 -> 336 (-78%)**, load 1,552 -> 559,
delete 1,483 -> 1,079; R3 update **1,389 -> 785 (-43%)**, load 1,435 ->
667, delete 1,776 -> 984.

The YCSB probe opens one resident handle and never checkpoints/reopens, so
this is **not** the pager: it is consistent with the per-operation
allocation retention at scale reported as **m375** (~read_at path; the same
arena/guard retention grows with op count and pressures the 50k rows).
R1/R4 at 10k ops are unaffected. Treat the R2/R3 v0.64.8 rows as
**pre-m375**; re-run after the reclaim lands.
### 4f. 2026-10-21 held-fd write path (engine-side fix for the 4e regression)

The 4e R2/R3 write regression was the **per-operation WAL open/close** in
auto-commit writes (v0.64.8 slowed that path); it is fixed engine-side by
reusing ONE held append fd per handle (the shape the txn window already
used) plus byte-native page writes and reused node/WAL buffers. RAM-capped
runs, same harness/host:

| row | load | read | update | scan | delete |
|---|---:|---:|---:|---:|---:|
| R1 10k sync=1 | 1,113 | 1,250,000 | 1,053 | 33,333 | 780 |
| R2 50k batch=100 | **1,489** | 666,666 | **1,409** | 35,714 | 1,722 |
| R3 50k sync=0 | **1,563** | 485,436 | **1,786** | 35,714 | 1,910 |

vs v0.64.7 (§4a): R2 update **1,551 -> 1,409 (-9%, within run noise)**,
R2 load 1,552 -> 1,489; R3 load 1,435 -> **1,563 (+9%)**, update
1,389 -> **1,786 (+29%)**, delete 1,776 -> **1,910 (+8%)**. R1 load/update
are above the v0.64.7 rows (947/866). The `m375` memory/teardown finding
still stands (see §7); throughput is no longer gated by it.

## 5. Findings (actionable)

1. **Windows write path is syscall-bound, not fsync-bound.** ORBITDB
   durable-per-op 611/s -> nosync 1,136/s (sync costs only ~45%); batch=100
   buys another ~45% (885/s) because the group commit amortized only the
   *fsync* while still issuing one `io.append_line` (open/write/close) per
   record. On WSL the same engine reaches **16.6k/s** nosync -- the gap is
   the Windows per-open/close overhead on the append path.
   **FIX LANDED 2026-10-16 (WAL held-handle writes, engine slice):** the
   auto-commit paths compose append + durability sync through ONE held
   handle (`wal_file_append_sync` / `_tagged_sync`), and the transaction
   window rides ONE held fd (`db_file_txn_*` opens lazily and commit/abort
   close it; checkpoints already refuse mid-txn, so truncate/rename never
   races the fd). WAL appends remain UNGATED (fault-probe arming counts
   unchanged); the sync seam still fires the kind-1 gate exactly once per
   durable ack. Correctness re-verified: suite 160/160 x2, fault probe
   56/56 x2, io-primitives 30/30 x2, db_crash 25/25 x2 (Windows), plus a
   byte-equivalence probe (negatives/zero/i64 extremes byte-identical to
   the old writer). **Relative A/B measured 2026-10-16 20:35Z** under
   sustained shared-host load (Windows CPU ~90%, WSL load ~130, all day):
   `probe_wal_ab.xi`, 10 interleaved old-vs-new pairs at N=2000 --
   **median old/new ratio 1.26x (mean 1.31x; min 1.04x, max 1.79x), 10/10
   pairs in favor** of the held-handle shape (interleaving makes the RATIO
   load-robust). The txn fd path is not exercised by this probe -- its win
   (one open per transaction) should be larger still. **Absolute BENCH-1
   rows: DONE 2026-10-18 on the adopted v0.64.7 pin** in the quiet-ish
   window (section 4a): R1 load 611 -> 947 (+55%), R2 885 -> 1,552 (+75%),
   R3 1,136 -> 1,435 (+26%); A/B re-run 5/5 pairs, median 1.28x.
2. **Group commit semantics**: after finding 1's fix, R2 (batch=100) moved
   885 -> 1,552/s (+75%, the largest of the three rows) on the v0.64.7
   window -- the held-fd path removed the per-record opens that dominated
   it. R2 load remains ~60x below SQLite's CLI batch (93,985/s): the
   remaining gap is in-engine per-record cost (WAL encode + btree work),
   the next perf target once the pager slice lands.
3. **Reads/scans**: in-process engines are sub-microsecond per point read
   (orbitdb ~0.8-2.3us, bbolt ~0.3-1.5us); the SQLite CLI numbers are
   driver-bound and only meaningful as upper bounds.
4. **Verification parity held on every row** across engines and platforms
   (bitmap-distinct delete accounting) -- the workload is cross-engine
   sound and ready to port to the Station league later.

## 6. How to run

```powershell
# Windows (from the repo root, after . scripts\dev-env.ps1)
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\bench_cross.ps1 -N 10000 -Vals 8 -Batch 1 -Sync 1
# R4: -N 10000 -Vals 100 -PointOnly
```

```bash
# WSL (stock pin baseline recommended for cross-engine numbers)
BENCH_STOCK_STDLIB=1 bash scripts/bench_cross.sh -n 10000 --sync 1
# R3: -n 50000 --sync 0 ; R4: -n 10000 --vals 100 --point-only
```

`BENCH_STOCK_STDLIB=1` drops the lane-checkout stdlib and uses the released
archive's bundled stdlib/runtime -- the stock-pin baseline for BENCH-1 rows
comparable with the captured numbers. The 2026-10-16 block on it is CLEARED:
the stdlib checkout's Linux-compile WIP (TCP_NODELAY include) is fixed at
`a451349` (in `6c96bbb`; stdlib acked `REL-20261016-1223-orbitdb`) and a
consumer compile on the checkout was verified GREEN 2026-10-16, so the switch
is no longer required. Future rounds: WSL R2/R4 + a quiet-host
recalibration; then the shared harness is the basis for ST7's station
league.

Perf-slice A/B tool (WAL write shape; interleaved, load-noise-immune in
principle):

```powershell
. scripts\dev-env.ps1
& .\scripts\run.ps1 tests\probes\probe_wal_ab.xi        # ORBITDB_AB_N=5000, _ROUNDS=3
```

## 7. Memory soak (A6, preliminary -- 2026-10-19)

`tests/probes/probe_soak.xi` builds a v2 database in two phases (a small
resident first build, then a paged reopen and chunked growth with
checkpoints), samples every 997th key, and reports node/cache/pager counters.
Peak RSS is sampled externally (XIOM has no RSS API).

```
xiom -o out/orbitdb-soak.exe tests/probes/probe_soak.xi
ORBITDB_SOAK_KEYS=15000 ORBITDB_SOAK_FIRST=5000 ORBITDB_SOAK_CHUNK=5000 \
  ORBITDB_SOAK_PATH=orbitdb-soak.wal out/orbitdb-soak.exe
```

- **15k keys: GREEN.** 90 ms, exact sample verification, GC compaction
  fired (count 15,003 -> 14,991; blocks reset), post-GC tree walk
  `14,991/14,991` reachable, **0 cycles / 0 out-of-range**. This required a
  fix: the in-place GC store reset handed a local `BlockStore` into a
  longer-lived store; post-GC reads hung. The reset now installs a fresh
  `ns_new_paged` value.
- **200k keys at order 4: RED.** Peak working set **~57.8 GB**, 600 s
  timeout at ~129k keys, snapshot 527 MB (one 4 KiB page per node; order 4
  packs ~1 key/node on ascending inserts).
- **200k keys at order 64 + 8192 cache frames:** exact verify, 6,455
  nodes / 6,472 blocks. The write-path fallbacks (byte-native page encode,
  reused node payload, held append fd, per-WALFile scratch) reduced peak
  RSS **895 MB -> 658 MB -> 607 MB** and teardown to **151 s**; the
  remaining retention is the runtime per-op Vec-drop class (m375), but
  the 1M soak now passes with a large enough cache (below).
- **2026-10-22 read_at_into branch + stdlib-v0.64.9 (host-contended):**
  same 200k/8192 shape: exact verify (201 samples), 6,455 nodes, peak
  **558.2 MB**, engine work **0.733 s**, but wall **733 s** while other
  lanes were compiling (quiet v0.64.8 baseline 151 s). The branch's
  block-store scan is `io.read_at_into` into a reused page buffer (no
  per-block Vec); the wall number is teardown under host load, not a
  regression signal. Rerun on a quiet host before recording a perf delta.
- **2026-10-22 1M on the same pin (host-contended):** 1,000,000 keys,
  order 64, 65,536-frame cache, 4 GB cap: **PASS**, exact 1,004-sample
  verify, 32,260 nodes / 32,341 blocks, **peak 2,451.2 MB** (new best;
  previous 2,494.7 MB), engine work 6.11 s. Process wall **6,110 s** while
  sibling lanes were compiling (quiet baseline 880 s); the wall is
  teardown-dominated and not a clean perf signal. `XIOM_FAST_EXIT` (m375)
  remains the teardown fix and is v0.65.0 acceptance input after the
  v0.64.9 withdrawal.

- **2026-10-26 1M on v0.65.1 + bundled stdlib 0.65.1 (Windows x64,
  otherwise quiet):** **PASS** -- exact 1,004-sample verify, 32,260 nodes /
  32,341 blocks, peak **1,830.8 MB** under the 4 GB cap (previous best
  2,451.2 MB), wall **703.7 s**. The same run with `XIOM_FAST_EXIT=1` is also
  PASS (peak 1,830.6 MB, wall 792.2 s): no measurable A/B delta, so the
  v0.65.1 owned-Vec reclamation appears to make the opt-in redundant.
- **2026-10-27 1M on v0.65.2 (engine soak only; release blocked):**
  **PASS** -- exact 1,004-sample verify, 32,260 nodes / 32,341 blocks, peak
  **1,566.1 MB** under the 4 GB cap (1,565.1 MB with `XIOM_FAST_EXIT=1`), wall
  784.5 s / 841.4 s. New best peak. v0.65.2 is NOT adopted: station loopback
  double-free and hybrid vector-WAL reopen loss are open compiler regressions.
- **2026-10-26 m375 minimal repro on v0.65.1:** `probe_mem_read` (100k x
  `io.read_at(4096)`) peaks **4.8 MB** in **15.3 s** (was 3,103 MB on
  v0.64.8). stdlib-v0.65.1 annotates `read_at`/`read_file_bytes` with
  `#[owns_return]`.

**m375 minimal repro (2026-10-20):** `tests/probes/probe_mem_read.xi` isolates
the pager hot path (64 MiB file, rotating 4 KiB reads):
`io.read_at` x 100,000 -> **peak 3,103 MB (~31 KB/read)**;
`byteio_read_at` (with `u8_to_bytes`) x 50,000 -> **3,127 MB (~62 KB/read)**.
The result Vec alone would be 400 MB / 1.6 GB, so the rest is per-call
retention. Inline source relayed to the compiler lane as
`REL-20261020-1222-orbitdb` (m375); the pager adopts a direct byte reader
as the fallback if the runtime cannot reclaim.

**1M PASS (2026-10-21, 65,536-frame cache, 4 GB cap):** the earlier attempt
was killed at 4,173 MB/~435k keys because nodes outgrew the 8,192-frame
cache (thrash). With `ORBITDB_PAGER_CAPACITY=65536` (covers the whole
tree) the soak completed: **1,000,000 keys, exact 1,004-sample verify,
32,260 nodes / 32,341 blocks (~132 MB snapshot), peak 2,494.7 MB under
the 4 GB cap**; process wall 880 s (engine work under 1 s; the exit-time
teardown is the runtime reclaim m375 tracks). A6 memory row met with the
configured cache; the default 256 frames stays for small DBs.