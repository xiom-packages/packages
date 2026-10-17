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
> adaptations recorded here.

## 1. What is compared

Three embedded engines, identical deterministic workload, one engine at a
time, fresh database per row:

| Engine | Driver | Version (this run) |
|---|---|---|
| ORBITDB (Satellite engine) | `tests/probes/probe_ycsb.xi` (real engine, v2 container default, order 4) | engine tree @ v0.64.5-era (2026-10-16), compiler v0.64.5 |
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
   load-robust; the absolute rows below still need a quiet host). The txn
   fd path is not exercised by this probe -- its win (one open per
   transaction) should be larger still. **Absolute BENCH-1 rows: PENDING A
   QUIET HOST** (re-measure attempts at 16:29Z/18:29Z/20:29Z all saw CPU
   >= 90% / WSL load 92-129; rescheduled). Re-run rows R1-R3 plus
   `tests/probes/probe_wal_ab.xi` (env `ORBITDB_AB_N`/`ORBITDB_AB_ROUNDS`)
   when the host is quiet.
2. **Group commit semantics**: after finding 1's fix, re-measure R2 -- it
   should move from ~885/s toward the fsync-amortized ceiling; the fd path
   removes the per-record opens that dominated it. (Numbers pending.)
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
