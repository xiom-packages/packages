<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# Benchmarks -- xiom-xvector (M-G)

Methodology, the in-repo harness, and the committed baseline. Every number
here names the workload, dataset configuration, platform and toolchain (the
honesty rule from `docs/PRODUCTION-PLAN.md` §5).

## How to run

- Windows: `.\scripts\bench.ps1 -Mode quick|medium|full` (default medium)
- WSL: `bash scripts/bench.sh quick|medium|full`
- CI smoke: `-Mode quick` runs inside `scripts/ci.ps1` / `scripts/ci.sh`
  as an additional gate.
- Env knobs: `XV_BENCH_MODE` (mode), `XV_BENCH_OUT` (JSON path, default
  `out/bench_report.json`), `XV_BENCH_STAGE=w1|w2|w4a|w6|w3|w4b|w5`
  (diagnostic: stop after that workload).
- Output: human table on stdout + a JSON report with integer units only
  (us, counts, permille, bytes).

## Method (honest notes)

- **Clock:** `xiom.time.monotonic_ms` (QPC on Windows, CLOCK_MONOTONIC on
  Linux; ms resolution). `xiom.time.Instant` is second-resolution by
  design and is NOT used.
- **Per-query workloads** (flat knn, filtered, range, hnsw per ef): a group
  size is calibrated (double until one group takes >= 2 ms, capped at 256),
  then 21 timed groups run; each sample stores per-op microseconds
  (`ms*1000/group`). p50/p95/p99 are the 11th/20th/21st sorted samples
  (approximate tails). QPS is derived from p50.
- **Whole-run workloads** (ingest, HNSW build, recovery): the full loop is
  timed; short loops repeat passes (capped) until >= 2 ms.
- **Recall:** overlap@k against the exact flat store scan on the same query
  set, per-mille.
- **bytes/vector:** checkpoint file bytes / n (disk proxy, not RSS).
- **Inputs:** deterministic LCG; the same mode reproduces identical data.
- **Memory safety:** all loop budgets are hard-capped; the harness is
  monitored during development. A full medium run peaks ~287 MB RSS.
- **Kernel fidelity (M-G1):** `probe_reference_oracle` cross-checks the
  distance kernels against an independent Float64 oracle on seeded data;
  measured deviations are Float32-ulp scale and bit-identical across
  platforms (cosine 1.70e-07, dot 9.83e-07, euclidean 5.06e-07), so the
  measured numbers below are kernel-faithful, not kernel-dependent.

## Baseline (2026-10-11, post-P-a refresh)

> **Archive note (2026-10-12):** the bench smoke (quick) re-ran green on the
> v0.64.4 lane-local toolchain (77th pass); the full baseline numbers below
> remain the 2026-10-11 v0.64.3 measurement (no re-baseline this pass).

- **Host:** DESKTOP-0OJEN1F -- AMD Ryzen 9 3950X (16C/32T), 128 GB RAM,
  Windows 11 Pro 26200. WSL2 (kernel 6.6.87.2-microsoft-standard-WSL2) for
  the Linux spot.
- **Toolchain:** compiler v0.64.3 (lane-local); stdlib lane `dd352f6`;
  xvector state: reference study 01 applied -- generous level 0
  (`m0 = 2*m` + FAISS `prune_headroom` 0.2; codec v3) in `src/index/hnsw.xi`.
- **Configuration:** dim=4, Cosine; Flat for exact workloads, Hnsw (default
  params, m=16) for ANN; k=10; ef sweep {32, 64, 128}; n=5000; 200 queries.
- **Units:** p50/p95/p99 in milliseconds (ms) or microseconds (us) as noted.

| Workload | Result |
|---|---|
| W1 ingest (Flat, single upserts) | ~2.5M points/s (2 ms / 5000; ~0.4 us/point) |
| W2 exact KNN (Flat, k=10) | p50 **11.8 ms**, p95 13.4 ms, p99 14.2 ms (~84 qps) |
| W4 filtered (Flat, 50% `In`) | p50 **57.5 ms** (linear fit) |
| W4 filtered (Flat, 10% `Eq`, index plan) | p50 **1.19 ms** (~48x faster than the 50% scan) |
| W6 range r=0.6 | p50 **20.5 ms**, avg 198 hits |
| W6 range r=1.2 | p50 **67.1 ms**, avg 505 hits |
| W3 HNSW build (5000 x dim-4) | **14.7 s** |
| W3 HNSW ef=32 | recall **1.000**, p50 **0.56 ms** (~1779 qps) |
| W3 HNSW ef=64 | recall **1.000**, p50 **0.84 ms** (~1186 qps) |
| W3 HNSW ef=128 | recall **1.000**, p50 **1.44 ms** (~695 qps) |
| W4 filtered on Hnsw (10% `Eq`) | p50 **3.44 ms** |
| W5 batch upsert (1000 pts) | single ~0.7 us/op vs `upsert_many` ~0.13 us/op (per-op, quantized; ratio ~0.19) |
| W5 batch search (100 queries) | 258 ms single vs 290 ms `search_many` (~1.1x) |
| W7 recovery | checkpoint 2.33 s / 762 KB; load+recover 16.0 s (HNSW rebuild dominates); 152 bytes/vector |

**Reading the numbers (honest):**

- These are **pure-XIOM, single-threaded, unoptimized-kernel** numbers --
  a baseline, not a finished performance story. The flat scan costs about
  ~2.4 us per candidate at dim 4; at n=5000 HNSW is ~8-21x faster than the
  exact scan with perfect recall on this synthetic set.
- Filtered `Eq` uses the sorted payload index (48x faster than the linear
  majority scan); range search is exact (linear scan) by construction.
- **P-a note (2026-10-11):** the generous level 0 raises HNSW search cost
  (+28/+34/+40% p50 at ef=32/64/128 vs the 2026-10-09 run; visited +20% at
  n=800), build time (13.0 -> 14.7 s) and recovery (+27%), while recall on
  this synthetic set stays 1.000; the recall win shows on hard clustered
  sets (`probe_hnsw_recall` P-a gate: 285/300 vs 275/300 at ef=8). The
  generous arm was chosen over the FAISS `keep_max_size_level0` fill arm
  (same recall, lower build/search cost). Flat-path numbers re-measured in
  the same session drift up to ~10% (run-to-run variance); the HNSW deltas
  exceed that.
- HNSW build (14.7 s / 5k) is the main build-time cost; SIMD/BLAS (M-P3)
  and index tuning target it.
- `upsert_many` amortizes per-op overhead; `search_many` is a convenience
  batching (no throughput win).
- Recovery includes rebuilding the HNSW graph from the replayed log
  (16.0 s / 5k); checkpoint write is 2.33 s for 762 KB.

## Fixed while building this (M-G finding)

`wal_persist` built the checkpoint with repeated `text = text + ...`
concatenation -- **O(L^2) total allocations** in a runtime whose allocator
retains temporaries long enough to thrash (the C-PULSE-14 family). At
~150 KB checkpoints this drove the machine into multi-GB paging (observed
during harness bring-up; killed at a 2 GB guard). It now appends into a
`Vec[UInt8]` linearly (`append_bytes`); `probe_wal_file` gained 4 scale
checks (1200-record append/persist/load/roundtrip). Checkpoint time is
~1.7 s / 762 KB on this host -- linear, still unoptimized.

## Cross-platform spot (WSL)

The quick mode runs green on WSL2 (same workloads, same recall); quick
checkpoint 951 ms / 225 KB vs 515 ms Windows. Full WSL parity is enforced
by `scripts/ci.sh` (bench smoke + suite x2 + all probes x2).

## External benchmark integration (2026-10-11, 70th pass)

`bench/adapters/` integrates the standard suites over the `xvectord` HTTP
server: a stdlib `xvector_client.py`, an ann-benchmarks drop-in
(`module.py` + `config.yml`; metric map angular->cosine, euclidean,
dot->dot; `ef_search` sweep 16..256 per request), and `smoke.py` -- the
live verifier of the exact adapter calls (version -> HNSW create ->
  batched upsert -> ef sweep -> recall@10 vs a brute-force cosine oracle;
  green on a default-cap server: **1.000 at ef>=64, 0.940 at ef=8**).
  **VectorDBBench (2026-10-11, 74th pass):** `bench/adapters/vectordbbench/`
  -- drop-in DB client (`xvector_db.py`) + direct-mode live smoke
  (`smoke_db.py`; 11/11 green: insert 400/400, recall 1.000 at the
  configured ef, 0.930/1.000 at ef 8/128; metadata + filter cases fail
  loudly until the payload routes land; no drop route -- restart for a
  clean fit). Shared brute-force oracle extracted to
  `bench/adapters/oracle.py`.
Honest framing for published numbers: single-threaded server (G phase),
no fsync-backed durability claims on this stdlib pin (D phase). See
`bench/adapters/README.md`.

**Blocker found by the first HTTP-path run (2026-10-11), now MITIGATED
in-lane (72nd pass):** the stdlib `str_bytes`/`str_slice` conversions and
the `json_parse` token accesses are quadratic on large inputs
(`strnlen` accessors -- stdlib lane root-caused it, fix queued as the top
wave-111 candidate). xvector moved the service hot path to bytes
(`api.json_fast` + `HttpRequest.body_bytes`), gated by a 228-case
fast-vs-strict byte-equivalence probe. Re-measured through `xvectord` on
the 5,000 x dim-25 corpus: **upsert 661 s -> 120 s (now HNSW-build-bound;
~42 points/s single-threaded)**; recall curve unchanged (1.000 at ef=128,
0.960 at ef=32, 0.779 at ef=8; ~53-78 QPS at ~13-19 ms/query). The
stdlib fix will additionally help every Str-heavy consumer; xvector
re-runs the repros + batteries on it. Repro + numbers:
`docs/repro/xv-json-parse-quadratic/` (`probe.xi`, `probe_strbytes.xi`;
filed as `REL-20261011-1453-xvector`).

**Fixed and re-verified on the wave-111 WIP (2026-10-11, 73rd pass):**
both repro probes now PASS -- 400 KB `str_bytes` **438 ms** (was
3981 ms); 20k-number parse **755 ms** (was 17.9 s); the 5k x dim-25 fit
through `xvectord` improved further, **120 s -> 57.4 s (87 points/s;
HNSW-build bound; machine-load sensitive run)**; recall@10
0.779/0.960/1.000 at ef 8/32/128 and 58-82 QPS unchanged. Full batteries
green on that pin (suite 177/177 x2 + sbom + 40 probes x2 + bench smoke,
Windows; WSL spot). Formal acceptance follows the committed wave-111
commit; the in-lane fast scanner (`api.json_fast`) stays the canonical
upsert path. **Closed on the committed fix (`9a2b5ab`):** the 5k x
dim-25 fit is **51.2 s (98 points/s)** on Windows; WSL: suite 177/177 x2
+ both probes exit 0 (str_bytes 87/177/359/691 ms -- the gate was
re-pinned to a linearity bound, 20x-ratio + 3 s net; Windows
43/87/174/379 ms); batteries ALL GREEN on the committed pin; bus
`-1453`/`-1543` verified + closed.

## External harness triage (2026-10-13)

- `E:\repos\db-benchmarks` (**AGPL-3.0**; already cloned in the study area,
  91.5 MB): a full-text/OLAP database benchmark framework (PHP 8 + Docker +
  cgroups-v2 + dstat/sensors; installed engines: ClickHouse, Elasticsearch,
  Manticore, Meilisearch, MySQL, Percona, Postgres, Quickwit, Typesense).
  Its only vector suite (`tests/hn_small_vector`: 1.1M HN comment
  embeddings, 256-dim) is **Manticore-specific** -- the queries are
  Manticore SQL `knn(comment_embedding, k, '<text>'|'<vector>')` with a
  text-embedding path, and the framework is built around dedicated Linux
  cold-run pipelines (OS cache purges, per-query restarts).
  **Not adopted for xvector:** AGPL rules out code adaptation into this
  repo, vector coverage is single-engine, and the infra target is a
  dedicated Linux box. Study-only; do not copy code from it.
- The vector-relevant harnesses the lane runs are
  `bench/adapters/ann_benchmarks` (recall/QPS curves, still the standard
  for ANN comparisons) and `bench/adapters/vectordbbench` (Zilliz's
  cross-DB leaderboard client; its own tooling ships clients for the
  market engines). The honest head-to-head path: run the SAME generated
  dataset + queries through VectorDBBench against a competitor, or add a
  competitor client beside our adapter for a direct two-engine comparison
  on one machine.

- **Cloned harnesses in the study area (2026-10-13; partial + sparse
  checkouts -- code only, results/data excluded):**
  - `E:\repos\ann-benchmarks` (**MIT**, erikbern/ann-benchmarks, 0.4 MB
    sparse): the standard ANN recall/QPS harness. Integration: drop
    `bench/adapters/ann_benchmarks/{module.py,config.yml}` into
    `ann_benchmarks/algorithms/xvector/`; run on WSL
    (`python run.py --dataset ... --algorithm xvector --local`).
  - `E:\repos\VectorDBBench` (**MIT**, zilliztech, 6.4 MB sparse): the
    cross-DB leaderboard client -- it ships clients for Milvus, Qdrant,
    Weaviate, pgvector, Chroma, ... under
    `vectordb_bench/backend/clients/`. Integration: register
    `bench/adapters/vectordbbench/xvector_db.py` as a client; a
    head-to-head runs the SAME dataset/query config against our server
    and a competitor on one machine.
  - `E:\repos\vector-db-benchmark` (**Apache-2.0**, qdrant, 0.9 MB
    sparse): engine-driver benchmark (`engine/clients|servers`,
    `experiments/`, `datasets/`). Study + optional xvector client
    driver; good config discipline for API-shaped comparisons.
- NOT cloned: `harsha-simhadri/big-ann-benchmarks` (MIT; ~129 GB upstream
  tree incl. assets; billion-scale competition reference only) -- clone
  with the same partial+sparse recipe if a billion-scale story needs it.

## What the owner's benchmark can use

- Deterministic modes + JSON report (`out/bench_report.json`) today.
- The live HTTP server (`out\xvectord.exe`) + drop-in adapters for
  ann-benchmarks (`bench/adapters/ann_benchmarks/`) and VectorDBBench
  (`bench/adapters/vectordbbench/`). Both live smokes re-ran green on the
  v0.64.4 / stdlib `cd281b7` pin (2026-10-12): `smoke.py` 7/7 (recall@10
  0.940 at ef=8, 1.000 at ef>=64), `smoke_db.py` 11/11 (insert 400/400;
  recall 1.000 at ef=64, 0.930 at ef=8, 1.000 at ef=128; metadata/filter
  cases fail loudly by design -- those routes are not exposed yet).
- Dataset shape: synthetic LCG is built in; the adapters accept external
  datasets over HTTP (ann-benchmarks/VectorDBBench supply their own
  hdf5/parquet). In-repo real-data importers (fvecs/JSONL/CSV) remain a
  follow-up; `xvectord` default caps are small -- raise
  `XVECTOR_MAX_REQUEST_BYTES` / `XVECTOR_MAX_BATCH` for benchmark runs.
- Scale expectation (honest): ingest is single-threaded and
  HNSW-build-bound (~98 points/s at dim 25 on this host); queries run
  53-82 QPS at dim-25. Standard 1M-row external datasets are runnable but
  will take hours to build; results reflect the SIMD-less baseline until
  M-P3 lands.
