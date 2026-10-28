# ORBITDB Operations Runbook

> How to build, test, soak, fuzz, benchmark, and recover ORBITDB on Windows and
> WSL. Every command exits non-zero on failure; treat a timeout (exit 124) and
> an empty run as red.

## 1. Environment

| Item | Windows | WSL (Ubuntu) |
|------|---------|--------------|
| Toolchain | `scripts\dev-env.ps1` (resolves `XIOM_COMPILER`) | `scripts/dev-env.sh` (`~/.local/bin/xiom`) |
| Compiler | v0.64.5 (`%LOCALAPPDATA%\xiom.new.0645\bin\xiom.exe`, sha256 `02f0857887e14e48...`) | v0.64.5 (canonical `~/.local/share/xiom`, sha256 `c4aa877a8a4c219f...`) |
| Stdlib | `$env:XIOM_STDLIB` = `E:\xiom-lang\stdlib` | `/mnt/e/xiom-lang/stdlib` |
| Runner | `scripts\run.ps1 FILE -TimeoutSec N` | `scripts/run.sh FILE --timeout-sec N` |

Both dev-env twins resolve the compiler EXPLICITLY (Windows: the lane shadow
pin; WSL: canonical first-on-PATH with an install-path fallback) and print
version + resolving path -- gate on that line when a run plays "wrong binary".
`XIOM_RUNTIME_DIR` is NOT used since the v0.64.5 adoption (2026-10-15): the
re-vendored stdlib carries wave 139; `dev-env.*` actively unsets any inherited
override so the stock pin is authoritative.

WSL note: the default distro on this machine is `docker-desktop` (no bash);
always target Ubuntu explicitly:

```bash
wsl.exe -d Ubuntu bash -lc "cd /mnt/e/xiom-projects/xiom-orbitdb && scripts/suite.sh --timeout-sec 300"
```

Shell scripts and `.xi` files must stay LF; `.ps1` files are CRLF
(`.gitattributes` enforces this on commit).

## 2. Everyday commands

| Purpose | Command | Notes |
|---------|---------|-------|
| Conformance suite | `scripts\suite.ps1 -TimeoutSec 300` (WSL twin: `scripts/suite.sh --timeout-sec 300`) | 160 tests across 10 area files; each file runs twice; expect `160/160 passed x2` and exit 0. |
| WAL crash harness | `scripts\crash_test.ps1 -Events 20 -TimeoutSec 90` | writer -> hard kill -> torn tail -> reopen -> verify -> heal -> verify+1. |
| Page crash harness | `scripts\page_crash_test.ps1 -Pages 20 -TimeoutSec 120` | Use 120s: the writer's first compile can exceed 90s under load. |
| DB crash harness | `scripts\db_crash_test.ps1 -Keys 20 -Tail 3 -Tx 5 -TimeoutSec 90` | Five scenarios (WAL-only, snapshot-only, snapshot+tail, uncommitted txn, committed txn); 25 checks. Prefix `ORBITDB_DB_FORMAT=v2` (env) to run the whole matrix with v2 byte-block snapshots (same 25 checks; GREEN x2 both platforms). |
| Hybrid crash harness | `scripts\hybrid_crash_test.ps1 -Keys 1000 -TimeoutSec 240` | ORBITDB <-> XVECTOR: one writer drives both stores, hard kill, torn row tail, reopen + repair + 100% join integrity; second verify idempotent. Needs the sibling `xiom-xvector` checkout (source roots in `tests/hybrid/xiom.toml`). |
| Block crash harness | `scripts\block_crash_test.ps1 -Pages 60 -Batch 10 -TimeoutSec 240` | M1.2 S2: four kill states (pages2 / full2 / midheader / compacted) + torn tail + reopen + recovery append; 8 checks. Kill lands at quiescent states only (O(file) shim until S4). |
| Fuzz/property | `scripts\fuzz.ps1 -TimeoutSec 600` | Deterministic; see section 4. |
| Cross-engine bench (BENCH-1) | `scripts\bench_cross.ps1 -N 10000 -Vals 8 -Batch 1 -Sync 1` (WSL twin: `BENCH_STOCK_STDLIB=1 bash scripts/bench_cross.sh -n 10000 --sync 1`) | ORBITDB vs SQLite (pinned CLI 3.54.0) vs bbolt v1.4.3 on identical deterministic YCSB-ish phases with per-row verify parity. Build the bbolt driver once: `cd bench\bbolt; go build -o bin\bbolt-bench.exe .` (+ `GOOS=linux GOARCH=amd64` cross-build for WSL). Methodology, fairness caveats, results: `docs/BENCH-1.md`. WSL runs use the stock pin (`BENCH_STOCK_STDLIB=1`) as the baseline. |
| WAL write-shape A/B (perf slice) | `scripts\run.ps1 tests\probes\probe_wal_ab.xi` | Interleaved old-vs-new durable append (env `ORBITDB_AB_N`=5000, `ORBITDB_AB_ROUNDS`=3); same-process rounds are load-noise-resistant in principle -- still prefer a quiet host (`docs/BENCH-1.md` finding 1). |
| Benchmarks | `scripts\bench.ps1 -N 10000` | Numbers summarized in the readiness doc G1 row (`docs/PRODUCTION-READINESS.md`). |
| App build (icon) | `scripts\build.ps1 <source.xi> [-Out out\orbitdb-app.exe]` | Compiles one source into an app binary and embeds `assets/orbitdb.ico` via `--icon` (verified on v0.64.2; `llvm-rc`). `scripts/build.sh` is the Linux/WSL twin (PE icons are Windows-only). |
| User shell (v0) | `scripts\build.ps1 apps\orbitdb_cli.xi -Out out\orbitdb.exe` then `out\orbitdb.exe [db-path]` | Interactive REPL: `put/get/del/range/count/ckpt/bench/info/recover/kill/help/quit` + typed rows `putrow <k> <spec>` / `getrow <k>` / typed predicates `qrow <col> <op> <literal>` (col -1 = id; spec: `int \| s:text \| f:float \| i:int \| n`). `kill` exits WITHOUT cleanup -- restart to watch WAL replay. WSL twin: `bash scripts/build.sh apps/orbitdb_cli.xi out/orbitdb-cli`. |
| Soaks | probe `soak` mode, section 3 | 2000-key policy soak is the standard long path. |

Twin `.sh` scripts accept the kebab-case flags (`--events`, `--pages`,
`--keys`, `--tail`, `--tx`, `--timeout-sec`).

Exit-code semantics: `run.{ps1,sh}` returns the *program's* exit code (parsed
from the compiler's `exit code:` line); 124 = watchdog timeout (process tree
killed); harnesses print `GREEN`/`RED` and exit 0/1.

## 3. Probes and env knobs

| Probe | Mode / env | What it does |
|-------|------------|--------------|
| `tests/probes/probe_db_file.xi` | `ORBITDB_DB_MODE=write/verify/put1/ckpt/qverify/txn/soak`; `ORBITDB_DB_FORMAT=v1/v2` | Durable DB driver used by the crash harnesses. `verify` checks keys/values; `qverify` checks range + filter queries; `ckpt` polls snapshot + truncated WAL; `txn` opens a transaction (`ORBITDB_DB_TXN_COUNT`, `ORBITDB_DB_TXN_COMMIT=0/1`). FORMAT steers the snapshot container for writes (reads auto-detect). |
| | `ORBITDB_DB_FILE`, `ORBITDB_DB_N`, `ORBITDB_DB_LAST_KEY`, `ORBITDB_DB_LAST_VAL` | Path, key count, optional post-recovery assertion. |
| | `ORBITDB_DB_CKPT_EVERY` | Soak mode: `db_file_maybe_checkpoint` record limit (default 250). |
| `tests/probes/probe_btree_churn.xi` | `ORBITDB_CHURN_ORDER/OPS/N/SEED` | B-tree churn vs model + structural validator. |
| `tests/probes/probe_fuzz.xi` | `ORBITDB_FUZZ_*` | Section 4. |
| `tests/probes/probe_wal_file.xi`, `probe_page_file.xi` | Mode envs per file header | Crash drivers for WAL/page harnesses. |
| `tests/hybrid/probe_hybrid.xi` | `ORBITDB_HYBRID_MODE=full/writer/verify` | ORBITDB <-> XVECTOR hybrid acceptance (source-level composition via `tests/hybrid/xiom.toml`). `full` = 36-check in-process run; `writer`/`verify` are driven by the hybrid crash harness. |
| | `ORBITDB_HYBRID_ROWS`, `ORBITDB_HYBRID_VEC`, `ORBITDB_HYBRID_N`, `ORBITDB_HYBRID_DIM`, `ORBITDB_HYBRID_SKIP`, `ORBITDB_HYBRID_LAG`, `ORBITDB_HYBRID_CHUNK`, `ORBITDB_HYBRID_Q`, `ORBITDB_HYBRID_K` | Row-store path, vector-WAL path and scale knobs (defaults 1000 / 8 / 10 / 3 / 200 / 8 / 20). |
| `tests/hybrid/repro_chain.xi` | paths are repo-relative | XV-ORBITDB-01 repro: chained persist -> load -> recover -> persist -> load (load2 loses the log; see `docs/XVECTOR-INTEGRATION.md` section 7). |
| `tests/pkg/probe_pkg_wal.xi` | `ORBITDB_PKG_WAL` (segment path, default `probe-logs/pkg-wal.log`) | First registry consumer pass: `xiom.wal` 0.1.0 conformance + two-way format interop with `src/wal_file.xi` (project `tests/pkg/xiom.toml`; needs the installed package). Syntax: `scripts/run.ps1 tests\pkg\probe_pkg_wal.xi -TimeoutSec 180`. |
| `tests/probes/probe_block_store.xi` | `ORBITDB_BLOCK_MODE=full/writer/verify`; `ORBITDB_BLOCK_DB`, `ORBITDB_BLOCK_N`, `ORBITDB_BLOCK_BATCH`, `ORBITDB_BLOCK_KILL_AT` | M1.2 S2 block store: `full` = 26-check functional battery; `writer`/`verify` drive `scripts/block_crash_test.*` (kill states pages2/full2/midheader/compacted). |
| `tests/probes/probe_fault_sync.xi` | `ORBITDB_FAULT_DB`, `ORBITDB_FAULT_CKPT_DB`, `ORBITDB_FAULT_BLOCK` (paths only) | M2.1+M5.3 durability/fault battery (56 checks): put/delete/typed-put syncfail latch + reopen recovery, checkpoint 2PC pre-sync failure (snapshot file size unchanged, WAL untruncated, tail replayed), block-store partial writes (torn page append/update, torn header slot fallback). |
| | `ORBITDB_FAULT_AT` / `ORBITDB_FAULT_MODE` (`kill`/`partial`/`skip`/`syncfail`) / `ORBITDB_FAULT_TAIL` | **Test-only** fault layer (`src/storage/fault.xi`, wired into the `byte_io` gates): fires on the Nth write-ish op (or sync for `syncfail`), one fire per arming; `fault_reset()` + removing the env re-arms. Never set in production. |
| `tests/probes/probe_mvcc.xi` | `ORBITDB_MVCC_DIR` (scratch dir, default `probe-logs`) | M3 snapshot-pin + savepoint battery (36 checks): three interleaved pins over 600 churn ops + two checkpoints vs per-pin models; compaction deferral under a pin (page log grows past node_count + 64, shrinks after release) with generation bookkeeping; savepoint matrix across reopen "crashes"; typed payload pins. Run: `scripts\run.ps1 tests\probes\probe_mvcc.xi -TimeoutSec 300`. |
| `tests/probes/probe_io_primitives.xi` | `ORBITDB_IO_PRIM_DIR` (scratch dir, default `probe-logs`) | Stdlib wave-115 durability/byte-IO verification (30 checks): real fsync via `sync_io.sync_fd`, held append handle (`open_append`/`write_all`/`close_fd`), `io.truncate_file`, `io.read_at`/`write_at`/`append_file_bytes` round-trips, `sync_io.fsync_dir`, `file_last_byte`/`ends_with_newline`, `append_line_sync` torn-tail repair. **Stock pin since v0.64.5** (the wave 115/117/118 primitives are in the bundled runtime; no `XIOM_RUNTIME_DIR` needed). GREEN x2 Win + x2 WSL on the v0.64.5 re-verify. |

Standard soak (policy checkpoints every 250 records):

```powershell
$env:ORBITDB_DB_FILE = "probe-logs\soak.wal"; $env:ORBITDB_DB_MODE = "soak"
$env:ORBITDB_DB_N = "2000"; $env:ORBITDB_DB_CKPT_EVERY = "250"
scripts\run.ps1 tests\probes\probe_db_file.xi -TimeoutSec 600
```

Scratch files live in `probe-logs/` (gitignored). On WSL, point
`ORBITDB_DB_FILE` at `/tmp/...` to avoid DrvFs write overhead in benchmarks;
correctness soaks run fine on both.

## 4. Fuzz/property harness

`scripts\fuzz.ps1` (mirrors `scripts/fuzz.sh`) runs `probe_fuzz.xi`:
deterministic LCG seeds, no wall-clock, four sections -- tuple codec
roundtrip + byte-flip mutations + truncation, WAL parser (valid records +
garbage + torn tails + heal-and-append), page-log parser (latest-wins, CRC
rejection, garbage/torn), and B-tree vs model over multiple orders and seeds.

```powershell
scripts\fuzz.ps1 -TimeoutSec 600
# knobs: ORBITDB_FUZZ_SEEDS, ORBITDB_FUZZ_OPS, ORBITDB_FUZZ_N,
#        ORBITDB_FUZZ_TUPLE_ITERS, ORBITDB_FUZZ_WAL_ITERS, ORBITDB_FUZZ_PAGE_ITERS,
#        ORBITDB_FUZZ_DIR,
#        ORBITDB_FUZZ_QUERY_ITERS, ORBITDB_FUZZ_TUPLE2_ITERS,
#        ORBITDB_FUZZ_SCHEMA_ITERS, ORBITDB_FUZZ_TYPED_ITERS,
#        ORBITDB_FUZZ_TQUERY_ITERS
```

Sections: (a) base tuple/WAL/page/btree, (g) query+index vs model,
(h) tuple v2 roundtrip + mutations, (i) schema rows vs model,
(j) db typed rows vs model, (k) typed queries vs an independent model.

Expected tail: `fuzz: OK seeds=4 ops/seed=4000 n=512` and exit 0. Failure
output names the section, seed and the first violated property. Continuous CI
cadence is gated on F3 (CI matrix); until then run it at every wrap on both
platforms.

## 5. Database files and recovery

A durable DB with WAL path `<path>` owns:

```
<path>        WAL segment  (lsn|op|key|value|timestamp[|payload])
<path>.snap   snapshot page log (header page 0 + node pages)
```

- `db_file_open` recovers by loading the newest committed snapshot generation
  and replaying only WAL records with `lsn > checkpoint_lsn`; without a
  snapshot it replays the whole segment.
- Torn tails on either file are healed on open / before append; never
  hand-edit these files.
- **Never truncate the WAL to empty**: the LSN counter lives in the retained
  Checkpoint anchor record.
- Checkpoint: `db_file_checkpoint` appends changed node pages, commits with
  the header page, then anchors and truncates the WAL. Rejected while a
  transaction is active.
- Transactions: ops are logged immediately but applied only at commit; a
  crash before commit discards them; a dangling window is finalized with an
  explicit Abort record on the next open.
- Stale handles: once another handle has written, this handle's writes are
  refused (`false` / `-1` for checkpoint). Reopen to become the writer again;
  there is no lock file to clear (see `docs/ISOLATION.md`).

Verify a recovered database with the probe modes:

```powershell
$env:ORBITDB_DB_FILE = "path\to\db.wal"; $env:ORBITDB_DB_MODE = "verify"
$env:ORBITDB_DB_N = "<expected key count>"
scripts\run.ps1 tests\probes\probe_db_file.xi -TimeoutSec 180
```

## 6. Gotchas

- `-Quiet` on `run.ps1` suppresses program output; use it only when the exit
  code is all you need.
- **Binary files: never `io.copy_file` / `read_file`+`write_file`** -- they are
  the TEXT path and truncate at the first NUL (engine finding
  `REL-20261014-1427-engine`, filed to stdlib; a PE DLL copies as 3 bytes).
  v2 snapshots and all `.snap`/binary artifacts are BINARY: use OS-level
  copies (`Copy-Item` / `cp`) for the backup recipe, or byte loops via the
  `byte_io` primitives. ORBITDB has zero `copy_file` usage today; keep it
  that way for anything that touches `.snap` until stdlib fixes the pair.
- **`Text file busy` (os error 26) on WSL/DrvFs:** every runner invocation
  compiles to a UNIQUE `-o` binary since the S4 harness hardening
  (2026-10-13) -- `run.{ps1,sh}` and all crash harnesses. If you see this
  error, some invocation is sharing `a.out`/`a.exe` across quickly sequenced
  or hard-killed runs; switch it to a per-invocation `-o` path. Never write
  or delete another process's binary mid-run.
- `read_file_lines` / `str_split` are **linear** since stdlib wave 96/97 (they
  were quadratic on v0.64.1); 20k-record WAL replay is ~9.9 s. `-N 20000`
  remains the bench reference.
- Hang loops need a side-effecting call (`io.sleep`); empty spin loops are
  optimized away.
- Harness flake: a single page-crash `observed=2`-style start miss under load
  is environmental; re-run with `-TimeoutSec 120` and confirm with a clean x2.
- Keep consumer helper names distinct from functions inside imported modules:
  an unqualified call to a module's PRIVATE same-named helper binds to the
  consumer's function silently (C-ORBIT-07 -- the M2.1 probe's `arm` had to
  become `probe_arm`; bundle `docs/repro/consumer-fn-hijack/`, bus
  `REL-20261011-1124-orbitdb`). Symptom shape: bogus contract panic in a
  stdlib module reached through the hijacked call, no file name in the
  message.
- Copying a Vec (or a struct containing Vecs) by assignment does NOT give an
  owned copy on v0.64.3: element assignment (`v[i] = x`) through the copy
  writes through to the source buffer, while push/pop copy-on-write
  (C-ORBIT-09; bundle `docs/repro/vec-copy-alias/`). **v0.64.5 (m302) fixed
  the SIMPLE binding shapes** (RHS = Ident/Index/Field deep-copies at the
  binding), but push() args, by-value call args, for-loop element bindings
  and whole-struct copies with Vec FIELDS still share. "Clone then mutate in
  place" code must build an owned copy explicitly (fresh vectors + push
  loops; see `node_deep_copy` in `src/index/btree.xi` -- the M3 COW shadows
  corrupted pinned views before it; it STAYS as the ownership guarantee).
- **WAL size-polls must open with DELETE sharing on Windows/DrvFs:** the
  crash harness polls line counts while the writer publishes its truncate;
  a read handle without `FileShare.Delete` makes the writer's temp+rename
  truncate fail transiently (best-effort by design -- see next bullet), and
  the poll then sees the UNTRUNCATED count and false-REDs
  (`observed=28/30` vs expected 6/8; hit 2026-10-15). `db_crash_test.ps1`
  uses `Read-WalLinesShared` for every poll; plain `Get-Content` is wrong
  here.
- **Truncate publish is best-effort and benign when it fails:** the
  checkpoint truncate is temp+rename; recovery of an untruncated segment is
  still correct because `db_file_open` skips pre-snapshot records via the
  snapshot's `checkpoint_lsn` gate. A leftover `*.wal.tmp` after contention
  or an interrupted run is expected debris (`*.tmp` is gitignored); a
  transient rename failure under load is not data loss. The `put1` step of
  both crash harnesses retries ONCE (idempotent key-9999 upsert) and prints
  `[WARN] put1 ...` when the retry absorbed a transient IO failure; a
  persistent failure still REDs.
- Snapshot pins are handle-local and in-memory: a reopen starts with none.
  While a pin is live, node versions accumulate in the arena (no GC until
  M1.1b) and checkpoint compaction defers (`db_file_compaction_deferrals`
  counts it; the page log grows until the pin is released). Do not cache pin
  ids across reopen; `db_file_snapshot_*` returns None/empty/-1 for ids that
  are not live.
- Hybrid probe `full` mode assumes FRESH paths (it does not clean up):
  reusing a previous run's WAL/vector pair can trip a contract on WSL
  (observed `ensures at 51:12` while Windows tolerated the same reuse). Use
  per-run file names or delete the pair first; the crash harness manages its
  own paths. Cross-platform batteries that suddenly show unresolved-package
  T001s: check the shared package homes first (the 2026-10-10 wipe; ours was
  missing `xiom-vectors`/`xiom-wal` on WSL only -- see
  `REL-20261011-1229-orbitdb`).
- WSL memory/contention: other lanes (PULSE/XVECTOR) share the WSL VM. Before
  chained WSL harness runs check `ps aux --sort=-rss | head` and `free -m`,
  run at most ONE heavy harness per command, and pause/retry if the VM is
  busy. The VM restarted twice under load on 2026-10-09 -- treat a restart as
  a reason to check, not to hammer.
- Identity/commits: conventional commits with DCO sign-off
  (`git commit -s`, `Lefteris Notas <lefterisnotas@gmail.com>`).

## 7. Station (ORBITWIRE v1)

The Station is a separate program in `station/` that source-composes the
engine and speaks ORBITWIRE over TCP (not HTTP; admin stays on PULSE).

```powershell
.\scripts\station.ps1                          # 127.0.0.1:7767, order 4
.\scripts\station.ps1 -Database data\app.wal -Port 9000
.\scripts\station.ps1 -Token s3cret            # require AUTH
.\scripts\station_suite.ps1                    # all station suites, twice
.\scripts\station_crash_test.ps1               # hard-kill/restart recovery
```

```bash
scripts/station.sh
TOKEN=s3cret scripts/station.sh
scripts/wsl_ext4.sh ./scripts/station_suite.sh  # WSL ext4 copy
scripts/wsl_ext4.sh bash ./scripts/station_crash_test.sh
```

- **It owns the DB while it runs.** `db_file_open_locked_checked_cfg` takes
  the M3 shard lock; a second Station on the same file fails fast. Stop with
  Ctrl+C (WAL durable; advisory lock released by exit). There is no
  read-only/cross-process reader mode yet (ST2/ST3).
- **Crash/restart:** `scripts/station_crash_test.{ps1,sh}` starts the
  hello-station, drives the ORBITWIRE client to BEGIN+PUT (or an
  auto-commit PUT), hard-kills the server, restarts on the same DB and
  verifies with the client: uncommitted work is discarded, committed work
  replays from the WAL, and a post-recovery commit survives a second kill.
  **11 checks x2 Windows + x2 WSL.** A hard kill leaves the advisory
  `.lock` file; the OS releases the lock and the restart reacquires it
  (validated). The harness discovers the actual bound port through
  `ORBITDB_STATION_PORT_FILE` (fixed base ports 17990/17991, fallback safe).
- **Env:** `ORBITDB_STATION_DB`, `_BIND` (127.0.0.1), `_PORT` (7767; `0` ->
  first free 17867+), `_ORDER` (4), `_PAGE_FORMAT` (2), `_TOKEN` (empty =
  AUTH off), `_PORT_FILE` (optional atomic bound-port file for harnesses /
  service discovery). Large DBs: set `ORBITDB_PAGER_CAPACITY` (default 256).
- **RAM cap:** `scripts/station.ps1` runs under `scripts/run_capped.ps1`
  (4 GB default); the WSL twin polls VmRSS.
- **Protocol:** `station/docs/ORBITWIRE.md` (frozen v1; frame KAT, field
  dictionary, ops, state machine, error codes, limits/backpressure).
- **Threading:** single-threaded event loop; one `StationActor` owns one
  `DBFile`; sessions never share the handle across threads. One transaction
  window per shard; a non-owner write returns `TXN_ACTIVE`.
- **Current evidence:** station suites **169/169 x2 Windows + x2 WSL**;
  loopback only, no TLS, typed rows auto-commit only, QUERY returns values
  (RANGE is keyed).
- **Gotcha (C-ORBIT-14, v0.64.8; fixed on compiler main `478e06f8b`):** never
  bind a Vec with `let/var x = match ...` on the v0.64.8 pin; the initializer
  truncates the Vec silently. Declare an empty `var` and assign inside the
  arm. Repro: `docs/repro/vec-match-binding/`.
- **Gotcha (C-ORBIT-15, v0.64.8; fixed on compiler main `18415ede2`):** module
  files must be UTF-8 **without a BOM** on the v0.64.8 pin. PowerShell 5.1
  `Set-Content -Encoding UTF8` writes a BOM; the compiler then reports the
  module import as unresolved with no BOM diagnostic. Repro:
  `docs/repro/utf8-bom-module/`.

## 8. Where to read next

- `ARCHITECTURE.md` -- module tree and ownership.
- `docs/API.md` -- public API reference (this tree).
- `docs/FORMATS.md` -- versioned on-disk formats.
- `docs/wal-and-recovery.md`, `docs/storage-layout.md`,
  `docs/query-pipeline.md` -- subsystem deep-dives.
- `docs/PRODUCTION-READINESS.md` -- scoreboard, changelog, checklist.
- `docs/XVECTOR-INTEGRATION.md` -- the hybrid contract, cross-ask answers,
  the standing probe/harness evidence and finding XV-ORBITDB-01.
- `SESSION.md` -- current state and next actions.
