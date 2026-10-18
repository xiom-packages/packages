<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# Checklist -- xiom-xvector Production v1 (flagship)

Execution checklist for `docs/PRODUCTION-PLAN.md`. Every slice follows the
same pattern: implement -> probe/suite gate -> **suite x2 + probes x2
(Windows) + WSL spot** -> docs (SPEC/ARCHITECTURE/SESSION/readiness as
needed) -> signed commit. Red build = rejection.

## M-G -- Truth & measurement

- [x] G1 reference-oracle cross-check **(done 2026-10-09)**: independent
  Float64 oracle + metric identities/axioms; randomized deterministic
  vectors; `probe_reference_oracle` (22 checks: pairwise kernels 780 pairs
  x3 metrics, axioms, ranked/page/cursor/range/Hnsw vs the oracle)
- [x] G2 benchmark harness **(done 2026-10-09)**: `bench/bench_main.xi` +
  `scripts/bench.ps1/.sh` + CI smoke (W1-W7, JSON, stage diagnostics)
- [x] G3 baseline report **(done 2026-10-09)**: `docs/BENCHMARKS.md`
  (methodology + n=5000 baseline + WSL spot + fixed O(L^2) builder note)

## M-D -- On-disk durability

- [x] D1 atomic checkpoint **(done 2026-10-09)**: `wal_persist` temp+
  `io.rename`; fault-injection probe (staged-complete temp + partial temp
  both leave the previous file; 7 new checks in `probe_wal_file`)
- [x] D2 manifest file **(done 2026-10-09)**: `durability.manifest_file`
  (`xvector-manifest 1` registry; whole-file persist with atomic
  temp+rename; invalid entries refused; torn-tail-safe complete-entry
  prefix load); `engine_manifest_save` + `engine_recover_file`/`open_engine`
  (file registry governs; in-WAL manifest migration fallback);
  `probe_manifest_file` (38 checks)
- [x] D3 multi-collection runtime **(done 2026-10-09)**: named collections,
  create/select/drop/list, isolated stores/payloads/indexes (v2 config +
  v3 drop WAL records; cid-stamped data; routed recovery; whole-registry
  checkpoint + manifest save/open); `probe_collections` (41 checks);
  survives reopen
- [x] D4 segment files **(done 2026-10-09)**: `segment.segment_file`
  codec (meta + vectors + payloads + Hnsw graph; whole-file atomic
  persist; torn-tail-safe complete-record prefix load; lifecycle
  Mutable -> Sealing -> Sealed); engine `seal_segment`/`restore_segment`
  (cid/dim/metric validated; WAL re-checkpoint after restore);
  `probe_segment_file` (38 checks)
- [x] D5 WAL delta + fsync-on-ack (fd/append path) + kill harness
  **(done 2026-10-12, 78th)**: `probe_wal_segment` 38/38; kill matrix 6/6
  Windows + 6/6 WSL; durable server restart-verified
- [x] D6 retention policy + snapshots/export-import + restore drill
  **(done 2026-10-13, 79th)**: `probe_snapshot` 27/27 (compact+swap churn,
  post-swap crash recovery, auto-policy zero-loss, multi-collection
  restore, corrupt-meta refusal); formats in SPEC
- [x] D7 multi-segment read path **(done 2026-10-13, 80th)**:
  roll/seal + union queries + tombstone shadowing + bit-exact
  compaction; `probe_multisegment` 27/27; two gate-caught fixes
  (`2552824`, `71af343`)

## M-Q -- Query surface complete

- [x] Q1 range search **(done 2026-10-09, exact-first)**: `search_range`
  engine/facade + `search_range_scan` kernel; exact on both index kinds;
  `probe_range_search` vs brute force. Request range mode folded into Q6;
  ANN widening deferred to M-P tuning.
- [x] Q2 batch ops **(done 2026-10-09)**: `upsert_many`/`search_many`/
  `delete_many` + `BatchHits`; all-or-nothing validation; `probe_batch_ops`
  (14 checks) + suite mirror
- [x] Q3 pagination **(done 2026-10-09)**: `query.pagination` -- offset
  (`search_page`) + after-id cursor (`search_after`) over the (distance
  asc, id asc) total order; exact tie order by id; exact on Flat and
  Hnsw; `probe_pagination` (22 checks: page consistency + cursor walks)
- [x] Q4 delete-by-filter **(done 2026-10-09)**: `engine_delete_filter` /
  `delete_filter` -- planner-driven (index candidates for Eq/Range/Exists/
  And, scan for In/Or/Not), per-point WAL + tombstones + payload/index
  cleanup, Ok(0) on no match; `probe_delete_filter` (26 checks)
- [x] Q5 per-collection stats + index admin **(done 2026-10-09)**:
  `collection_stats` (config + points + payloads + Hnsw nodes/tombstones +
  lsn; parked entries report without switching) and `rebuild_index`
  (before/after/reclaimed stats; Hnsw fresh graph, Flat no-op);
  `probe_index_admin` (20 checks)
- [x] Q6 `SearchRequest` extensions (mode/page/batch) + validation
  **(done 2026-10-09)**: `SearchMode.Knn | Range` + radius; knn
  `offset` / `after_id` pagination (mutually exclusive; no filters yet);
  `SearchBatchRequest` + `search_batch_with_request` (ordered,
  all-or-nothing); probe-only gate (`probe_search_request`, 24 checks;
  suite mirror untouched -- the mirror is a standalone re-implementation
  without range/pagination dispatch)

## M-S -- Server & security

- [x] S1 HTTP service skeleton **(done 2026-10-09)**: in-repo
  `api.http_service` byte-level HTTP/1.1 pipeline (parse/route/JSON/reply,
  no sockets yet -- the `xiom.net` adapter is C-PULSE-02-gated);
  `/health`, collections create/list, points get/upsert/delete, search
  (knn/range/page/batch), `/stats`; `probe_http_service` (40 checks)
- [x] S2 config (file/env), limits (size/k/batch/dim), JSON error model,
  graceful shutdown (drain+checkpoint) **(done 2026-10-09)**: ServiceConfig
  + `service_config_from_env`/`service_config_load` (key=value); enforced
  limits (413 size/batch, 400 named k/dim); `{error,kind,status}` over the
  full CoreError enum; `http_service_shutdown` WAL checkpoint;
  `probe_service_limits` (27 checks)
- [x] S3 auth: API keys, constant-time compare, scopes; rate limiting;
  auth-on-by-default in service mode; auth probe **(done 2026-10-09)**:
  `ServiceAuth` via `x-api-key` (stdlib constant-time compare; scopes
  read/write/admin; `XVECTOR_API_KEYS`), 401/403 kinds, token-bucket
  `RateLimiter` (429), `ServiceState` + `http_service_handle_state`
  (embedded default off; service adapter enables);
  `probe_service_auth` (24 checks)
- [x] S4 security pass **(done 2026-10-09)**: threat model + secure
  defaults (`docs/SECURITY.md`); HTTP fuzz + resource-exhaustion gate
  (`probe_http_fuzz`, 14 checks, 2500 inputs) with the JSON depth guard
  fixing a found stack-overflow DoS; `scripts/sbom.ps1`/`sbom.sh` SBOM +
  unsafe gate wired into both batteries; no-unsafe audit statement
- [x] S5 runnable server `xvectord` **(done 2026-10-11, 69th pass)**:
  `api.httpd` socket adapter over the stdlib `xiom.net` layer (the
  C-PULSE-02 proof delivered), `main` entry -> `xvectord.exe`
  (`--bind/--port` + `XVECTORD_*`), strict headers/Content-Length
  framing, 4 MiB socket guard, 30 s dead-peer guard, `X-Xvector-Quit`
  shutdown; `probe_http_server` (10 checks over real sockets) x2 Windows +
  WSL; curl end-to-end user test green (create/upsert/search/stats/quit)
- [x] S6 `GET /version` + index configuration at create + per-request
  `ef_search` **(done 2026-10-11, 70th pass; closes phase F)**; `xvectord`
  applies the `XVECTOR_MAX_*` service limits
- [x] Benchmark adapters **(done 2026-10-11, 70th pass; VectorDBBench
  adapter 74th pass)**: `bench/adapters/` -- stdlib HTTP client,
  ann-benchmarks module + config.yml (angular/euclidean/dot; ef sweep),
  live `smoke.py` green (recall@10 1.000 at ef>=64, 0.940 at ef=8);
  **`vectordbbench/` client adapter** (drop-in DB client + direct-mode
  `smoke_db.py` 11/11 live: insert 400/400, recall 1.000/0.930/1.000 at
  ef 64/8/128; metadata/filter cases fail loudly until payload routes);
  shared `oracle.py` (single brute-force impl)
- [x] Upsert hot-path fast scanner **(done 2026-10-11, 72nd pass)**:
  `api.json_fast` (byte-level, conservative) + `HttpRequest.body_bytes`;
  228-case byte-equivalence gate + 52k-number body <5 s (strict ~84 s);
  5k fit 661 s -> 120 s. Root cause `str_bytes` quadratic pinned
  (`probe_strbytes.xi`); stdlib fix queued (wave-111 top candidate) --
  re-run probes + batteries when it lands
- [x] Re-verification pass **(done 2026-10-11, 73rd pass)**: `xiom.http`
  0.1.6 re-sync (native 507; tripwire re-synced, 6 checks) + stdlib
  wave-111 WIP acceptance -- both `docs/repro/xv-json-parse-quadratic`
  probes exit 0 (400 KB `str_bytes` 438 ms; 20k parse 755 ms), 5k fit
  120 s -> 57.4 s; full batteries green on the pins (suite 177/177 x2 +
  sbom + 40 probes x2 + bench smoke, Windows) + WSL spot; bus -2002 /
  -1206 / -1550-xvector-9 / -1835 verified+closed
- [x] Wave-111 closure **(done 2026-10-11)**: stdlib `9a2b5ab` committed
  (hashes == the pre-verified WIP); both repros exit 0 Windows + WSL
  (400 KB `str_bytes` 379 ms Windows / 691 ms WSL; gate re-pinned to a
  20x-ratio linearity bound + 3 s net); batteries ALL GREEN on the
  committed pin; 5k fit 51.2 s (98 pts/s); bus `-1453`/`-1543`
  verified+closed

## M-O -- Observability & operability

- [x] O1 metrics surface **(done 2026-10-09; package-backed 2026-10-10)**:
  `observability.metrics` (internals on `xiom.metrics` 0.2.0 behind the
  same surface) -- counters
  (requests/errors/search/upsert/auth_failures/rate_limited), latency
  histograms (global + search; 1/5/10/50/100/500/1000 ms + `+Inf`,
  p50/p95/p99), live gauges (collections/points/lsn); `probe_metrics`
  (24 checks; `probe_package_metrics` 12)
- [x] O2 `/metrics` + `/health` (live/ready) + structured logs + slow-query
  log **(done 2026-10-09)**: public `GET /metrics` (prometheus text;
  counters + histograms + gauges), `/health` carries `ready:true`, bounded
  JSON-line `LogRing` (method/path/status/ms/slow, sanitized, eviction
  count) wired through `http_service_handle_state`; signals asserted by
  `probe_metrics`
- [x] O3 `docs/OPERATIONS.md` runbook **(done 2026-10-09)**: start/stop +
  shutdown checkpoint, config reference, monitoring + alerts,
  backup/restore drill, failure-domain table, upgrade/migration notes,
  quick diagnostics

## M-P -- Performance & scale

- [x] P1 concurrency design doc (writer/reader model, consistency notes)
  **(done 2026-10-11: `docs/G-PHASE-PLAN.md`)** -- v1 = single-writer per
  collection + process-level sharding; in-process threads are post-gate
  (acceptance `docs/repro/xv-thread-abi`); consistency + G-1..G-5 slice
  order defined
- [x] P2 memory budget + seal/compaction thresholds; measured **(done
  2026-10-11, 75th pass: `engine_memory_estimate` + `/stats` `mem_*` +
  `probe_memory_estimate` 17 checks x2 Win+WSL; thresholds + rules of
  thumb in `docs/OPERATIONS.md` section 8; budget-cap enforcement stays
  advisory)**
- [ ] P3 SIMD/BLAS seam behind the `xiom.vectors` contract; benchmark delta
  recorded
- [ ] P4 IVF/PQ prototype (v1.1 track) with recall/latency curve
- [ ] P5 (stdlib-dependent) mmap/disk segments; tiered storage

## M-R -- Release candidate & handoff

- [ ] R1 release checklist filled; `VERSION` = `1.0.0-rc`; changelog;
  build-info stamp
- [ ] R2 CI matrix green (Windows + WSL); reproducible artifacts
- [ ] R3 benchmark report + security checklist + SBOM committed
- [ ] R4 owner handoff note (repo/runners/rulesets/benchmark); **tell the
  owner -- public release is the owner's action**

## Reference study (owner grant, 2026-10-11)

- [x] Study-area rules + backlog (SESSION 2): MIT-only clones, study never
  vendor, adopted patterns re-implemented + gated here
- [x] Study 01 -- FAISS HNSW recon **(done 2026-10-11)** ->
  `docs/REFERENCE-STUDY-01-FAISS.md` (ranked proposals P-a..P-e)
- [x] P-a generous level-0 degree applied **(done 2026-10-11)**: level-0
  capacity `m0 = 2*m` + FAISS `prune_headroom` 0.2; codec v3 carries `m0`
  (v2 decodes); hard-corpus control gate in `probe_hnsw_recall` (285/300
  generous vs 275/300 legacy); fill arm measured (same recall, ~2.5x build
  work) and not adopted
- [x] Study 02 -- quantization recon **(done 2026-10-11)** ->
  `docs/REFERENCE-STUDY-02-QUANTIZATION.md` (ranked Q-a..Q-d; Q-a = SQ8
  quantized scan tier + exact f32 rescore for sealed segments; explicit
  error-bound story section; no adoption yet)
- [x] **Q-a1** -- SQ8 quantization module + `probe_quantization` (17
  checks; bit-identical rescore 10x3) + suite Section 16 **(done
  2026-10-11, 66th pass)**; found/filed XVC-C-15 around it
- [x] **Q-a2a** -- segment codec **v2** with the opt-in SQ section
  (`sealed_segment_enable_sq`; `q`/`c` after the graph; v1
  byte-identical when unarmed; loader torn-section drop; artifact gates
  in `probe_quantization`) **(done 2026-10-11, 67th pass)**
- [ ] Q-a2b -- read-path wiring: scan sealed segments via codes + exact
  rescore (lands with D5's multi-segment reads; consumes study 03's
  record-layout input)
- [x] Study 03 -- DiskANN layout + quantized-graph notes **(done
  2026-10-11)** -> `docs/REFERENCE-STUDY-03-DISKANN.md` (sector-packed
  fixed-size records, co-located f32 + adjacency, buffer-then-seal
  deltas, delete-by-rebuild, alignment as a format decision for
  D5/D6/P5); study backlog complete
