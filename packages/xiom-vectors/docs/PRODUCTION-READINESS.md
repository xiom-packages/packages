<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# XVECTOR -- Production-Readiness Tracker

**How far is xiom-xvector from a production-grade vector database?**
This is the honest, evidence-based scorecard. It is recomputed at every lane
wrap and every number must point at evidence (tests, probes, docs) or name
the missing work. **Programme:** `docs/PRODUCTION-PLAN.md` (v1.0 milestones
M-G/M-D/M-Q/M-S/M-O/M-P/M-R + slice backlog) and
`docs/requirements/production-v1.md`.

- **As of:** 2026-10-18, 86th pass (**v0.64.7 re-pin COMPLETE on both
  platforms** -- full batteries ALL GATES GREEN (53 probes x2 + suite
  177/177 x2) on stdlib `6727526` + packages `2e7c5524`; C-16/C-17/C-18
  repros green on WSL + Windows; zero XVECTOR findings open; the embedded
  tier packages orbitdb 0.2.1 + pulse 0.2.1 are consumed and gated;
  L-3/L-4/L-5 lattice slices landed with the durable reopen-then-write fix)
- **Overall:** **88 %** (weighted; see method)
- **Level scale:** 0 none - 25 scaffold - 50 buildable - 75 hardened core -
  90 release-grade - 100 production.

## Method

Ten phases, weights sum to 100. Phase score = verified criteria / criteria
(judgment, itemised as "remaining" below). Overall = sum(weight x score).
A phase reaches 100 only when its exit criteria are met **with evidence**
(green suites x2 on Windows + WSL, probes, soak where applicable) -- not when
the code merely exists. Blockers are named; blocked work still scores.

| # | Phase | Weight | Score | Level | Blockers |
|---|-------|-------:|------:|-------|----------|
| A | Core data model & vector math | 8 | 95 | release-grade | none (fuzz/reference cross-check tracked in I) |
| B | Exact search & query engine | 10 | 97 | release-grade | ANN-widened range (M-P) |
| C | ANN index (HNSW hardening) | 14 | 99 | release-grade | file-backed persistence |
| D | Persistence & durability | 20 | 96 | release-grade | power-loss fault injection |
| E | Metadata & filtering | 8 | 100 | production | -- |
| F | API & query surface | 8 | 100 | production | -- |
| G | Concurrency & scalability | 10 | 40 | buildable | **G-1 COMPLETE 2026-10-18** (natural module-level globals + cross-thread mailbox leg; channel handle form wished; XVC-C-19 global-init hang open), G-2 accept-loop threads, scale tuning |
| H | Observability & operability | 5 | 88 | release-grade | dashboards/alert wiring (deployment), on-demand recall proxy |
| I | Testing & verification | 9 | 94 | release-grade | CI runners |
| J | Ecosystem & release engineering | 8 | 60 | buildable | runners activation, rulesets, staging E2E, xiom.ann/db porter flow |

**Overall today:** 0.08x95 + 0.10x97 + 0.14x99 + 0.20x95 + 0.08x100 +
0.08x100 + 0.10x40 + 0.05x88 + 0.09x94 + 0.08x60 = **87.82 -> 88 %**.

## What 100 % means (definition of production grade)

1. No acknowledged write can be lost (fsync'd WAL + replay + durable manifest,
   verified by kill-recovery tests).
2. Every query path is self-verifying per build (the XVC-C-05/06 class means a
   binary is only trusted after its numeric assertions pass).
3. HNSW recall is measured against the exact oracle at target recall/latency.
4. Filtered search is planned (pre/post by selectivity) and correct under
   concurrency.
5. Operable: metrics/health, structured logs, documented failure modes,
   upgrade/migration story.
6. Released: CI matrix green, reproducible artifacts with build-info, branch/tag
   protection, SHA-pinned actions, staging E2E -- owner-greenlit.
7. Docs match code (this file, ROADMAP, SPEC, ARCHITECTURE, SESSION) and the
   relay docs are current.

## Phase detail -- remaining work per phase

### A. Core data model & vector math -- 95 %
Done: Vector/VectorIndex types, 3 distance metrics, magnitude/normalize,
top-K bounded heap, exact f32<->bits codec, 168-check suite.
Remaining: reference cross-check (numpy-style oracle) under fuzz; NaN/Inf
documented policy in distance kernels.

### B. Exact search & query engine -- 97 %
Done: flat exact KNN, k-bounded sorted results, filtered exact search
(pre-filter scan + selectivity-based post plan with fallback), **filtered
search on ANN collections** (HNSW fetch + matching subset with exact flat
fallback when under-filled; k-fill guarantee kept), **exact range search**
(kernel `search_range_scan` + `engine_search_range` + facade
`search_range`: inclusive radius, distance-sorted, limit-bounded, exact on
both index kinds; gate `probe_range_search` -- 72 radius x limit combos vs a
brute-force scan), SearchHits public shape, error paths.
Remaining: ANN-widened range (M-P tuning).

### C. ANN index -- 99 %
Done: multi-layer HNSW graph (`index/hnsw.xi`: flat per-(node, layer)
adjacency rows, deterministic geometric levels, greedy descent + layer-0
beam honouring `ef`, metric-agnostic, user-id results; **O(log n) sorted
id -> position map** with duplicate rejection), tombstone deletes (never
returned, routers kept, revive on re-insert), tombstone compaction
(`hnsw_compact` rebuilds from live nodes; engine `compact_index`), **engine
wiring** (`VectorEngine.graph/index_kind/ann`, `set_index` Flat/Hnsw,
upsert/delete upkeep, `engine_search` routing with `ef = ann.ef_search`,
filtered search stays exact, recover + re-apply), **strict word codec**
(`hnsw_encode`/`hnsw_decode` v3 carrying `m0`; v2 still decodes; map
rebuilt on decode), **beam
construction honouring `ef_construction`** with diversified pruning,
**generous level 0 (reference study 01, P-a)**: level-0 capacity
`m0 = 2*m` with FAISS `prune_headroom` 0.2 (anti-churn) and a
generous-vs-legacy control gate,
recall harness vs the flat oracle (n=200: 300/300 at ef=64, 297/300 at
ef=8; n=800: 200/200; hard clustered corpus 285/300 generous vs 275/300
legacy; after-delete 300/300; compacted 200/200; engine-level
recall 200/200 incl. ef_construction=32; gates `probe_hnsw_recall`,
`probe_engine_hnsw`, `probe_hnsw_codec`), AnnParams validation.
Remaining: file-backed graph segments (stdlib I/O pending). Latency proxies
(build work + per-ef visited/recall table) are in the harness; updates
re-link edges for the new vector (recall 200/200 after 60 in-place
updates); the WSL segfault found while wiring the map (XVC-C-09) is worked
around and pinned as a repro for the compiler lane.

### D. Persistence & durability -- 95 %
Done: WAL-before-ack for upserts AND metadata, vector + payload codecs,
replay, delete/torn-tail handling, compacted checkpoint, chained reopen,
LSN monotonicity, **in-WAL collection manifest** (dim/metric/index
kind/params survive recover and checkpoints; malformed/legacy fall back),
**kill-recovery acceptance** (prefix exactness at the WAL model level:
recover(prefix) + apply(record) == recover(prefix + record), incl. the
compacted checkpoint log, empty log and corrupt-final-record cases),
**whole-file WAL persistence** (`durability.wal_file`: `wal_persist` text
checkpoint + `wal_load` byte-level torn-tail-safe prefix load; kill/reopen
equality, overwrite persistence, 9-point truncation sweep, missing/
garbage/empty cases; gate `probe_wal_file`), **atomic checkpoint swap**
(M-D1: `<path>.tmp` -> `io.rename`; 7 fault-injection checks -- no temp
remains, staged-complete and partial temps leave the previous checkpoint
intact, completed persist advances the file), the **durable collection
registry file** (M-D2: `durability.manifest_file` -- `xvector-manifest 1`
text registry, one line per collection `name dim mc kc m efc efs`;
whole-file persist with atomic temp+rename; invalid entries refused with
the target untouched; torn-tail-safe byte-level load with a
complete-entry prefix; gate `probe_manifest_file`, 38 checks), the
**multi-collection registry** (M-D3: named collections with per-
collection stores/payloads/indexes; WAL v2 config + v3 drop records with
cid-stamped data; routed recovery + whole-registry checkpoint; whole-
registry `save_manifest`/`open_engine` with file-wins by name; gate
`probe_collections`, 41 checks), and **sealed segment files** (M-D4:
`segment.segment_file` -- vectors + payloads + Hnsw graph codec;
whole-file atomic persist; torn-tail-safe complete-record prefix load;
lifecycle Mutable -> Sealing -> Sealed; engine `seal_segment`/
`restore_segment` with cid/dim/metric validation and WAL re-checkpoint
via shared `engine_checkpoint_from`; gate `probe_segment_file`,
38 checks), and **the D5 durability delta** (`durability.wal_segment`:
append-only delta segment in `xiom.wal` codec v1 framing -- byte-linear
renderer, tolerant line replay with LSN-gap stop, newline heal-on-open,
checkpoint-deduped merge, rotation; `engine_enable_durable` /
`engine_wal_commit` fsync BEFORE every ack (WAL-before-ack with a real
fd path); `open_durable` merges checkpoint + segment; the whole-file
checkpoint stays the compaction output; gate `probe_wal_segment`,
38 checks), and **the file-level kill matrix** (child writer with an
fsynced ack ledger, killed mid-stream; every acknowledged record verified
present after recovery -- 6/6 iterations Windows + 6/6 WSL via
`scripts/kill_matrix.ps1|.sh`), and the **durable server home**
(`xvectord` with `XVECTORD_WAL`: fsync-on-ack serving, checkpoint +
segment rotation on clean quit; restart-verified: 400 points, recall
1.000), a measured recovery time for a 4000-point snapshot (10 ms,
`probe_snapshot` diag), and **the D6 retention/snapshot layer** --
`engine_checkpoint_swap`
(rebase to live state -> `wal_persist_sync` with fsync-before-rename
ordering -> segment reset + frontier advance; a failed swap never resets
the segment) with the auto-policy hook (`XVECTORD_CHECKPOINT_EVERY`;
clean quit always swaps), and `durability.snapshot` (ckpt + manifest +
strict versioned meta; corrupt/missing meta refused; multi-collection
bit-exact restore + search parity; gate `probe_snapshot`, 27 checks), and
**the D7 multi-segment read path** (`engine_roll_segment` move semantics,
union queries over active + sealed with tombstone shadowing and active-wins
duplicates, bit-exact Flat semantics via the `k + tombstones` budget,
`engine_compact_sealed` with bit-exact merge + restart survival, restart
loads every registered source with `sealed_missing` accounting, the opt-in
auto-roll policy `XVECTORD_SEAL_EVERY`/`_DIR`, and the request path +
union hydration wired end-to-end; gate `probe_multisegment`, 27 checks;
warm union query over 60 pts ~0.12 ms; honesty: whole-file segment loads,
SQ two-tier deferred to Q-a2b).
Remaining: power-loss fault injection (OS-level; process-kill durability is
proven today, `OPERATIONS.md` states the boundary).

### E. Metadata & filtering -- 100 %
Done: typed Eq/Range/In/Exists + combinators + no-payload semantics, engine
integration, durable metadata, filtered probe, sorted key index
(parallel-vector rows; exists/count/Eq/Range with semantic float compare;
gate `probe_payload_index`), selectivity planner (exact counts for
Eq/Range/Exists; pre/post choice + fallback; gate `probe_filter_plan`),
compound upper bounds (And/Or/Not planning), the index-driven candidate
plan, and **multi-key intersections** (And of indexable clauses).
Remaining: none (composite `In` intersections are a possible future
stretch).

### F. API & query surface -- 100 %
Done: **`GET /version` (`{"name","version","api"}`, public),
index configuration at create (`{"index":"hnsw","m","ef_construction",
"ef_search"}`, default flat; 400 on bad kinds/params), per-request
`ef_search` on /search (lightweight beam override, no rebuild; 400 out
of range), and the **starter benchmark adapters** (`bench/adapters/`:
stdlib HTTP client + ann-benchmarks module/config + a live smoke that
exercises version -> HNSW create -> batched upsert -> ef sweep ->
recall@10 vs a brute-force oracle; green: 1.000 at ef>=64, 0.940 at
ef=8);** **runnable HTTP server (`xvectord.exe`, 69th pass): the socket
adapter over the stdlib `xiom.net` layer (sequential accept, strict
Content-Length framing, 30 s peer guard, `X-Xvector-Quit` shutdown),
whole requests through the transport-agnostic `http_service_handle`;
gate `probe_http_server` (10 checks over real sockets, x2 Windows + WSL)
and a curl end-to-end user test (health/create/upsert/search/stats ->
correct nearest neighbor -> clean quit)**; facade (create/upsert/search/delete/get + payloads + filtered search +
exact range), batch ops (`upsert_many`/`delete_many`/`search_many`,
all-or-nothing validation; gate `probe_batch_ops`), Result[..] error
discipline, SearchHits/BatchHits shapes documented, SearchRequest wire
(real types) driving `search_with_request`, `with_payload` hydration
(`HydratedHits`/`SearchHit`; C-08 fixed in v0.64.2, suite flags asserted),
and the multi-collection registry surface (M-D3: `create_named_collection`/
`select_collection`/`drop_collection`/`list_collections`/
`collection_count` + whole-registry `save_manifest`; gate
`probe_collections`), and pagination (M-Q3: `search_page` offset +
`search_after` after-id cursor over the (distance asc, id asc) total
order; gate `probe_pagination`), and selective delete-by-filter (M-Q4:
`delete_filter` -- planner-driven index candidates or scan, WAL-durable
per point, tombstones + payload/index cleanup; gate
`probe_delete_filter`), and per-collection stats + the admin rebuild
(M-Q5: `collection_stats` / `rebuild_index`; gate `probe_index_admin`),
and the request surface extensions (M-Q6: `SearchRequest` mode
knn/range, radius, offset/after-id pagination; `SearchBatchRequest` +
`search_batch_with_request`; gate `probe_search_request`, 24 checks).
Remaining: none.

### G. Concurrency & scalability -- 40 %
Done: multi-collection registry (M-D3: named collections with per-
collection stores/payloads/index configs, create/select/drop/list, routed
recovery + whole-registry manifest; gate `probe_collections`), the
benchmark harness + baseline (`docs/BENCHMARKS.md`; bench smoke in both
batteries), the P2 memory budget (`engine_memory_estimate` + `/stats`
`mem_*` fields + `docs/OPERATIONS.md` section 8; gate
`probe_memory_estimate`), the segment growth policies (D6 checkpoint swap
+ D7 seal auto-roll, opt-in; gates `probe_snapshot`/`probe_multisegment`),
and **the thread-primitive gate CLOSED (2026-10-15, v0.64.5)**: real
`xiom.thread.spawn[T]` + `JoinHandle.join` run OS threads on BOTH
platforms (3 workers return exact sums; a worker id differs from main;
marks `M3: join ok 42`; acceptance `docs/repro/xv-thread-abi/`; fixes:
compiler m282 `d6690868` env-cast + stdlib wave-131 buffer hoist + wave-139
trampoline i64). **G-1's thread + counter legs landed (2026-10-16):**
`tests/probes/probe_thread_sync.xi` (45th probe, both batteries) pins the
spawn/join acceptance + a 4-thread mutex-guarded counter (exact 2000) + a
4-thread atomic counter (exact 2000) on Windows + WSL, plus the
same-thread channel FIFO/close contract; the channel CROSS-THREAD leg is
blocked on XVC-C-17 (imported-type global pointer-field drop;
`REL-20261015-2216-xvector`). The engine is still single-threaded and each
call targets one active collection.
Remaining: G-2 flag-gated accept-loop threads (`XVECTORD_THREADS`),
concurrent readers / write serialization model, scale tuning beyond the
baseline (`docs/G-PHASE-PLAN.md` slice order); the channel handle form
(wished) re-opens the channel's own cross-thread leg.

### H. Observability & operability -- 88 %
Done: inline counters + LSN metrics (engine), and the full M-O core:
`observability.metrics` (fixed-bucket latency histograms with
`_sum`/`_count`/p50/p95/p99; the service counter bundle; a bounded,
sanitized JSON log ring with slow-query flag), the public prometheus-style
`GET /metrics` (counters + histograms + live gauges
collections/points_active/lsn), `/health` readiness, per-request
instrumentation through `http_service_handle_state`, and
`docs/OPERATIONS.md` (runbook + failure domains + backup drill). Gate
`probe_metrics` (now 24 checks). **`xiom.metrics` 0.2.0 adoption landed
2026-10-10**: the module internals run on the registry package behind the
same surface (`/metrics` byte-identical; package Histogram/Counter value
types, lane accessors + percentile helper, package-first-fit buckets),
the engine stat counters moved onto the package and the core shim
`Counter` was retired (single-type rule after **XVC-C-14**); new direct
package gate `probe_package_metrics` (12 checks). Record:
`docs/XIOM-METRICS-ADOPTION.md`.
Remaining: dashboards/alert wiring in the deployment (owner-side), the
presentation evaluation (package labels/exposition, optional), and
recall-proxy metrics on demand.

### I. Testing & verification -- 94 %
Done: 171-check conformance suite (x2 Windows + WSL), 34 probes, build-time
watchdog, rebuild-on-red discipline, per-build numeric gates, per-build
compiler-workaround pins (XVC-C-04 shape matrix, C-01 bind semantics), a
deterministic fuzz gate (`probe_fuzz_codecs`), a mixed-workload soak
(`probe_soak_mixed`), the kill-recovery acceptance
(`probe_kill_recovery`), the file-WAL gate
(`probe_wal_file`: roundtrip, kill/reopen, truncation sweep, atomic swap,
**1200-record scale guard**), the **benchmark harness + baseline**
(`docs/BENCHMARKS.md`; bench smoke wired into both CI batteries), the
**reference-oracle cross-check** (`probe_reference_oracle`: independent
Float64 oracle vs the kernels + axioms + all ranked/paged/cursor/range/
Hnsw search paths; deviations at Float32-ulp scale, bit-identical
Windows/WSL), the **HTTP service gate** (`probe_http_service`: framing,
routing, wire shapes, honest statuses), the **HTTP fuzz + abuse gate**
(`probe_http_fuzz`: 2500 deterministic inputs all well-formed; targeted
resource-exhaustion cases), and
the **v0.64.2 re-test**: all XVECTOR compiler findings verified fixed
(C-03/06/07/08 + C-10; C-11/C-12 in-context; C-09 repro) with the C-07/C-08
workarounds reverted; the suite asserts trailing-field flags again; two
registry-adoption gates with direct package-consumption checks
(`probe_package_wal` 9 checks, `probe_package_metrics` 12 checks); the
XVC-C-14 layout-shadow repro bundle (`docs/repro/xv-counter-type-shadow/`).
Remaining: CI runner activation.

### J. Ecosystem & release engineering -- 58 %
Done: `.ps1`/`.sh` twins, `xiom.toml`, relay docs + wishlists, porter plan,
version/hash recording, the acyclic porter-ready tree, **release-prep
drafts**: `scripts/ci.ps1` + `scripts/ci.sh` (full pre-release battery with
aggregated exit codes, both verified green), `VERSION` (0.1.0-dev), a
SHA-pinned `.github/workflows/ci.yml` draft,
`docs/RELEASE-CHECKLIST.md` (owner-gated flow), and the **security release
artifacts**: `docs/SECURITY.md` (threat model + secure defaults) and the
**SBOM + unsafe gate** (`scripts/sbom.ps1`/`sbom.sh` -> `out/sbom.json`;
wired into both batteries), the **operations runbook**
(`docs/OPERATIONS.md`: start/stop, config, monitoring/alerts,
backup/restore drill, failure domains, migration, diagnostics), and the
**release candidate package** (`docs/RELEASE-NOTES-v1.0.0-rc.1.md`,
`docs/sbom-v1.0.0-rc.1.json`, `docs/OWNER-HANDOFF.md`, an audited
`docs/RELEASE-CHECKLIST.md`, annotated tag `v1.0.0-rc.1`), and the
**registry-package adoptions** (`xiom.wal` 0.1.0 + `xiom.metrics` 0.2.0:
installs + ed25519
verification + `xiom pkg trust` pin + `xiom.toml [dependencies]` with
C-PULSE-02 resolved; alignment/migration notes in
`docs/XIOM-WAL-ADOPTION.md` / `docs/XIOM-METRICS-ADOPTION.md`; gates
`probe_package_wal` / `probe_package_metrics`).
Remaining: self-hosted runners activation, branch rulesets on greenlight,
staging E2E (parked until the owner greenlights public release), porter
extraction with the packages lane.

## Milestones

| Milestone | Meaning | Status |
|---|---|---|
| M1 Durable in-memory core | WAL + recovery + payloads, green suites + probes | **Met 2026-10-08** |
| M2 Crash-safe on disk | file-backed WAL segments, fsync, durable manifest, kill tests | In progress: whole-file WAL checkpoint + atomic swap (M-D1); durable registry file (M-D2); multi-collection routed recovery + whole-registry manifest (M-D3); sealed segment files with engine seal/restore (M-D4); fsync/append delta, multi-segment reads, file-level kill test, retention blocked on stdlib fsync/append |
| M3 Indexed at scale | HNSW hardening + recall harness, sorted payload index + planner, concurrency | In progress: HNSW hardening (recall harness, tombstones, compaction, codec) + payload index + planner + multi-collection registry + benchmark harness landed; **thread gate CLOSED 2026-10-15 (real spawn+join on both platforms)**; G-1/G-2 + scale tuning next |
| M4 Operable & released | observability, soak/fuzz green, CI + release stamp, staging E2E | In progress: observability + the metrics adoption landed, soak/fuzz green, release candidate + stamp (rc.1) prepared; staging E2E + public release owner-gated |

## Change log

- **2026-10-08:** created. Phase 3 payload filtering (90 %) and payload
  durability landed (D raised to 55, E to 90, I to 65); suite 126 -> 165
  checks; XVC-C-05/06/07 build-rejection discipline adopted. Overall ~42
  (recomputed bootstrap baseline: scaffold-phase engine) -> 53 %.
- **2026-10-08 (later):** first module extracted (payload/filter layer,
  `src/payload/*`; engine imports it) -- J 20 -> 25, porter prep advanced;
  suite 165/165 x2 and all probes green after extraction.
- **2026-10-08 (fourth pass):** second extraction wave -- types
  (dense_vector/metric/neighbor), storage/vector_store (+ vector codec),
  query/search_service are real modules; engine.xi keeps WAL/recovery/
  engine/API only. J 25 -> 30; suite 165/165 + all probes green.
- **2026-10-08 (fifth pass):** third extraction wave -- durability
  (wal/recovery/write_ahead_events) extracted; engine.xi is now
  facade + engine orchestration only. J 30 -> 35; suite 165/165 x2
  (Win+WSL) and Windows probes x2 green.
- **2026-10-08 (sixth pass):** compiler re-pinned to **v0.64.1**; six of
  seven XVECTOR findings fixed (XVC-C-01..06), C-07 open. Regression
  green: suite 165/165 x2 (Win+WSL), 5 probes x2, WSL matrix 9/9.
  I 65 -> 70 (numeric gates now stable across builds).
- **2026-10-08 (seventh pass):** FloatVal workaround unwound -- float
  payload gates restored in suite (166 checks) + probes. I 70 -> 72;
  overall 54 %.
- **2026-10-08 (handoff):** re-verified full green on compiler v0.64.1 +
  stdlib **0.64.2** (`4dd8844`): suite 166/166 x2 (Win+WSL), probes green;
  fsync/fd-write still stubbed on 0.64.2 (M2 unchanged). No score change.
- **2026-10-08 (eighth pass):** final extraction wave -- `src/core/shim.xi`
  (CoreError/Counter/ids/predicates) + `src/engine/core.xi` (VectorEngine +
  engine_*); `engine.xi` is the facade only (acyclic: shim <- core <-
  facade). Consumers import `xiom.vector.engine.core` for engine_* symbols.
  J 35 -> 40; overall 55 %. Evidence: engine-import probe x2; suite 166/166
  x2 (Win+WSL); all 7 probes x2 (Win); WSL spot (import + vector_store)
  bit-identical.
- **2026-10-08 (ninth pass):** Phase 3 refinement -- `SearchRequest` rewritten
  against the real types (with setter), `HydratedHits`/`SearchHit` +
  `hydrate_hits`, `engine_search_request` (metric validation, filtered/plain
  dispatch, optional hydration), facade `search_with_request`; new probe
  `probe_search_request` and 3 suite mirrors (168 checks). New compiler
  finding **XVC-C-08** (trailing scalar after a Vec-bearing field misreads;
  silent wrong hydration flags) filed with repro
  `docs/repro/xv-trailing-field-vec/`; hydration flags gated in the
  real-module probe only (green 8/8 fresh builds). F 60 -> 70; overall 56 %.
  Evidence: suite 168/168 x2 (Win+WSL), all 8 probes x2 (Win) + WSL spot.
- **2026-10-08 (tenth pass):** Phase 3 refinement -- sorted payload key index
  (rows sorted by field/kind/num/text/id in parallel vectors; maintained on
  put/overwrite/remove; `payload_store_index_len/_exists/_field_count/_eq/
  _range`; new probe `probe_payload_index`, 31 checks, stress 6/6 fresh
  builds). E 90 -> 95; overall 55.98 -> 56 %. Evidence: suite 168/168 x2
  (Win+WSL), all 9 probes x2 (Win) + WSL spot. Stdlib re-check: fd/fsync/
  append-bytes still stubs (M2 stays parked).
- **2026-10-08 (eleventh pass):** Phase 3 refinement -- selectivity-based
  pre/post-filter planner (`query/filter_plan.xi`: exact counts for
  Eq/Range/Exists incl. allocation-free `index_count_eq/_range`; post only
  for known count >= k and majority; post path with scan fallback inside
  `search_knn_filtered`; new probe `probe_filter_plan`, 16 checks incl.
  equivalence vs a scan reference + fallback case, stress 6/6 fresh builds).
  B 90 -> 92, E 95 -> 97; overall 56.34 -> 56 %. Evidence: suite 168/168 x2
  (Win+WSL), all 10 probes x2 (Win) + WSL spot.
- **2026-10-08 (twelfth pass):** Phase 4 start -- HNSW stub replaced by a
  working layer-0 graph (`index/hnsw.xi`: flat parallel arrays dodging the
  AUDIT T001 shape; exact-kNN bidirectional build with farthest-edge
  pruning; best-first beam honouring `ef`; metric-agnostic; user-id
  results) + recall harness vs the flat oracle (new probe
  `probe_hnsw_recall`: recall@10 300/300 at ef=64, 299/300 at ef=8, cosine
  100/100, reachability 200/200, stress 6/6 fresh builds; gates >= 0.85 /
  0.50 / 0.60). C 25 -> 45; overall 56.34 -> 59 %. Evidence: suite 168/168
  x2 (Win+WSL), all 11 probes x2 (Win) + WSL spot (recall bit-identical).
- **2026-10-08 (thirteenth pass):** Phase 4 -- multi-layer HNSW (fixed
  8-layer capacity, per-(node, layer) flat adjacency rows, deterministic
  geometric level assignment honouring `ml`, greedy descent above layer 0 +
  layer-0 beam; the level-assignment LCG low-bit bug found by the harness
  and fixed with high-bit testing). Harness extended: level histogram, top
  level, avg_visited, and an n=800 dataset (recall@10 200/200 at ef=64,
  avg visited 288/800; n=200 300/300 at ef=64 AND ef=8; cosine 100/100;
  stress 6/6 fresh builds). C 45 -> 55; overall 60.54 -> 61 %. Evidence:
  suite 168/168 x2 (Win+WSL), all 11 probes x2 (Win) + WSL spot.
- **2026-10-08 (fourteenth pass):** Phase 4 -- HNSW tombstone deletes
  (`hnsw_delete` marks routers that are never returned; idempotent;
  `hnsw_live_count`; re-insert updates the vector in place and revives) --
  the prerequisite for engine wiring. Harness extended: after-delete recall
  300/300 stray42=0, revive -> live 200, delete-all -> live 0 and empty
  search; stress 6/6 fresh builds. C 55 -> 62; overall 61.52 -> 62 %.
  Evidence: suite 168/168 x2 (Win+WSL), all 11 probes x2 (Win) + WSL spot.
- **2026-10-08 (fifteenth pass):** Phase 4 -- engine HNSW wiring
  (`VectorEngine.graph/index_kind/ann`; `set_index` Flat/Hnsw with graph
  rebuild from the store; upsert feeds `hnsw_insert_ref`; delete tombstones
  the graph; `engine_search`/request plain path route through `hnsw_search`
  with `ef = ann.ef_search`; filtered search stays the exact flat scan;
  index choice in-memory, re-applied after `engine_recover`). New gate
  `probe_engine_hnsw` (13 checks: engine recall 200/200, delete/revive,
  filtered exact, Flat bit-identical, invalid params, recover + re-apply;
  stress 6/6 fresh builds). C 62 -> 75; overall 61.52 -> 63 %. Evidence:
  suite 168/168 x2 (Win+WSL), all 12 probes x2 (Win) + WSL spot.
- **2026-10-08 (sixteenth pass):** Phase 4 -- HNSW tombstone compaction
  (`hnsw_compact` rebuilds the graph from live nodes only; engine
  `compact_index` returns the reclaimed count, Flat -> 0). Harness:
  compact-all -> empty; 50 tombstones -> size/live 150 with recall 200/200
  and stray_deleted=0; engine-level reclaim + post-compact recall;
  recover expectations updated (store 149). Both gates stress 6/6 fresh
  builds. C 75 -> 80; overall 63.34 -> 64 %. Evidence: suite 168/168 x2
  (Win+WSL), all 12 probes x2 (Win) + WSL spot.
- **2026-10-08 (seventeenth pass):** Phase 4 -- HNSW graph codec
  (`hnsw_encode`/`hnsw_decode`: deterministic word stream, strict decode;
  new gate `probe_hnsw_codec`: 100-node structural roundtrip with search
  bit-identical, tombstones, empty graph, six rejection cases, decoded
  graph mutable; stress 6/6 fresh builds). C 80 -> 85; overall 64.04 ->
  65 %. Evidence: suite 168/168 x2 (Win+WSL), all 13 probes x2 (Win) + WSL
  spot.
- **2026-10-08 (eighteenth pass):** Phase 4 -- beam construction honouring
  `ef_construction` (descent + per-layer beam `search_layer_build`) and
  diversified pruning (`select_diverse` for new-node selection and full-block
  pruning); `ef_construction` on the graph (setter; AnnParams-seeded by
  `set_index`), codec v2 carries it. Harness re-verified under beam build
  (n=200 300/300 ef=64, 296/300 ef=8; n=800 200/200; deletes/compaction
  hold; engine ef_construction=32 build recall holds); three HNSW probes
  stress 6/6 each. C 85 -> 90; overall 64.74 -> 65 %. Evidence: suite
  168/168 x2 (Win+WSL), all 13 probes x2 (Win) + WSL spot.
- **2026-10-08 (nineteenth pass):** Phase 4 -- HNSW sorted id -> position
  map (`id_keys`/`id_vals`, O(log n) find, duplicates rejected, codec
  rebuilds it, compaction rebuilds it). Found **XVC-C-09** while wiring it:
  the compiled `engine_set_index` segfaulted on WSL while Windows stayed
  green; worked around (local graph + single field assign), repro pinned at
  `bca8b7f` (`docs/repro/xv-wsl-nested-field/`). C 90 -> 95; overall 65.44
  -> 66 %. Evidence: suite 168/168 x2 (Win+WSL), all 13 probes x2 (Win) +
  WSL spot (engine/recall/codec probes green post-workaround); three HNSW
  probes stress 6/6 each.
- **2026-10-08 (twentieth pass):** slice 5 -- compiler-workaround pins and
  unwind-candidate evaluation: new per-build pin `probe_result_shapes.xi`
  gates the whole XVC-C-04 matrix (incl. the real engine path) on every
  build (8/8 Windows + 2/2 WSL fresh builds); `probe_bind_semantics` pins
  C-01 (8/8 + 2/2). Decision: keep the SearchHits wrapper and the suite's
  direct dispatch (C-08/C-09 family still open; revisit at the next
  archive). I 72 -> 75; overall 66.14 -> 66 %. Evidence: suite 168/168 x2
  (Win+WSL), all 14 probes x2 (Win) + WSL spot.
- **2026-10-08 (twenty-first pass):** HNSW+filter integration --
  `hnsw_search_filtered` (ANN fetch `ef_search` wide + matching subset;
  exact flat filtered fallback when under-filled) behind
  `engine_search_filtered` and the request-driven filtered branch. Gate:
  majority filter k-filled 8/8 with recall 80/80 vs the exact oracle;
  1-/3-match filters fall back bit-identically; zero-match empty; stress
  6/6. B 92 -> 95; overall 66.41 -> 67 %. Evidence: suite 168/168 x2
  (Win+WSL), all 14 probes x2 (Win) + WSL spot.
- **2026-10-08 (twenty-second pass):** fuzz gate + decoder hardening --
  `probe_fuzz_codecs.xi` (deterministic random/mutated/truncated streams
  into payload codec, graph codec and WAL replay incl. chained
  checkpoint). It found **XVC-C-10**: `hnsw_decode`'s inline pad loop
  segfaulted at `m >= 512` (Win + WSL); fixed via `pad_adj_slots` + strict
  bounds (`m <= 512`, `count <= words.len()`), repro pinned at `e0b1f7f`
  (`docs/repro/xv-decode-pad-loop/`). I 72 -> 78; overall 66.71 -> 67 %.
  Evidence: suite 168/168 x2 (Win+WSL), all 15 probes x2 (Win) + WSL spot
  (fuzz/codec/pad-loop).
- **2026-10-08 (twenty-third pass):** mixed-workload soak --
  `probe_soak_mixed.xi` (400-point Hnsw collection, 600 deterministic ops:
  311 upserts / 115 searches / 63 filtered / 61 payload sets / 50 deletes;
  per-op bookkeeping invariants, periodic compaction, final + chained
  recovery; ~2.5s; stress 4/4). Found and fixed an LCG low-bit degeneracy
  in the generator (residue 8 unreachable -> the payload branch never ran).
  I 78 -> 80; overall 66.98 -> 67 %. Evidence: suite 168/168 x2 (Win+WSL),
  all 16 probes x2 (Win) + WSL spot (soak/fuzz).
- **2026-10-08 (twenty-fourth pass):** latency metrics + release-prep
  drafts -- `hnsw_build_ops` build-work proxy (n=200: 62,129 ops) and a
  per-ef visited/recall table (ef=8: 97/100 @ 63 visited; ef=128: 100/100
  @ 196); `scripts/ci.ps1` + `scripts/ci.sh` pre-release batteries (both
  green end-to-end), `VERSION` 0.1.0-dev, SHA-pinned CI workflow draft,
  release checklist. C 95 -> 97, J 40 -> 48; overall 67.16 -> 68 %.
  Evidence: full batteries via the new scripts (suite x2 + 16 probes x2 on
  Windows and WSL).
- **2026-10-08 (fix pass):** `index_add` now updates an existing id in
  place -- previously an upsert of an existing id kept the OLD vector in
  the flat store while the HNSW graph updated, so compaction reverted
  updates and recovery kept the first insert. Regression gate in
  `probe_vector_store` (new-vector bits visible via get_point + search,
  recovery keeps the latest). No score change; both full batteries green
  (suite x2 + 16 probes x2, Windows + WSL).
- **2026-10-08 (twenty-fifth pass):** E stretch -- store id -> slot map
  (O(log n) get/add/remove; swap-remove updates the moved slot), compound
  upper-bound planning (And/Or/Not), and the index-driven candidate plan
  (exact Eq/Range/Exists candidates through the map). Planner probe
  extended to 20 checks (plan codes, bounds, bit-identical index
  equivalence). E 97 -> 99; overall 68.08 -> 68 %. Evidence: full
  batteries via ci.ps1 / ci.sh (suite x2 + 16 probes x2, Windows + WSL),
  ALL GATES GREEN.
- **2026-10-09 (twenty-sixth pass):** in-WAL collection manifest --
  create_collection/set_index log dim/metric/index kind/AnnParams;
  engine_recover restores the full config (including rebuilding the Hnsw
  graph) without a manual set_index, checkpoints carry the manifest
  forward, and legacy/malformed logs keep the Flat fallback. Gate:
  `probe_engine_hnsw` (recover-without-set_index, chained config, legacy +
  malformed fallbacks). D 55 -> 58; overall 68.24 -> 69 %. Evidence: full
  batteries via ci.ps1 / ci.sh (suite x2 + 16 probes x2, Windows + WSL),
  ALL GATES GREEN.
- **2026-10-09 (twenty-seventh pass):** HNSW update re-linking --
  re-inserting an existing id refreshes the node's edges for the new vector
  (per-layer beam through the old structure + diversified replacement);
  connect factored into beam_select/apply_layer_edges (construction
  behavior-identical). Gate: recall@10 200/200 after 60 in-place updates vs
  the   flat oracle; size/live unchanged. C 97 -> 98; overall 68.84 -> 69 %.
  Evidence: full batteries via ci.ps1 / ci.sh, ALL GATES GREEN.
- **2026-10-09 (twenty-eighth pass):** kill-recovery acceptance --
  `probe_kill_recovery.xi` proves prefix exactness at the WAL model level
  (every prefix of a 46-record log; recover(prefix) + apply(record) ==
  recover(prefix + record)), on the compacted checkpoint log (28 records),
  plus full-recovery equality, empty log, and corrupt-final-record cases.
  Both batteries now run 17 probes. D 58 -> 60, I 80 -> 82; overall
  68.98 -> 70 %. Evidence: full batteries via ci.ps1 / ci.sh (suite x2 +
  17 probes x2, Windows + WSL), ALL GATES GREEN.
- **2026-10-09 (twenty-ninth pass):** multi-key intersections -- the index
  plan serves And of indexable clauses via per-clause candidate
  intersection; answerable compounds route to the index when the upper
  bound is selective or < k. Planner probe now 23 checks. E 99 -> 100
  (phase complete); overall 69.56 -> 70 %. Evidence: full batteries via
  ci.ps1 / ci.sh, ALL GATES GREEN.
- **2026-10-09 (thirtieth pass):** file-backed WAL -- new
  `durability.wal_file` (`wal_persist` whole-file text checkpoint +
  `wal_load` byte-level torn-tail-safe prefix load) on the stdlib
  whole-file APIs; probe `probe_wal_file` (roundtrip vs the live WAL,
  kill/reopen incl. Hnsw config, overwrite persistence, 9-point
  truncation sweep with per-cut prefix checks, record-boundary cuts,
  missing/garbage/empty). Both batteries now 18 probes. Found **XVC-C-11**
  (`io.read_file` content lost in some units) and **XVC-C-12**
  (`io.read_file_bytes` aborts at <= 8 bytes); workarounds: byte-wise
  parsing (never Str) + `file_size < 25` guard; repro
  `docs/repro/xv-stdlib-file-read-defects/`. D 60 -> 63, I 82 -> 83;
  overall 69.64 -> 70 %. Evidence: full batteries via ci.ps1 / ci.sh
  (suite 168/168 x2 + 18 probes x2, Windows + WSL), ALL GATES GREEN.
- **2026-10-09 (thirty-first pass):** v0.64.2 re-test + workaround reverts
  -- compiler v0.64.2 (tag `c51170a6`) installed Windows + WSL; every repro
  bundle re-run and the full batteries green. **C-03** (suite W004 count 0)
  and **C-06** (pinned FloatVal probe) stay fixed; **C-07 FIXED** --
  `Str::from_utf8(&Vec[UInt8])` valid again, payload codec + suite mirror
  reverted to the `&` spelling; **C-08 FIXED** -- trailing-scalar repro
  exit 0, all 14 variants green, suite hydration mirror restored and
  asserting the trailing flags (168 -> 169 checks); **C-10 FIXED** (inline
  pad shape no longer segfaults; hygiene kept); **C-11/C-12 re-tested
  green in a copy of the original failing unit** (defense in depth kept);
  **C-09 repro green on WSL + Windows** (pattern kept; weaker re-test).
  I 83 -> 84; overall 70.33 -> 70 %. Evidence: suite 169/169 x2 + 18 probes
  x2, Windows + WSL, ALL GATES GREEN.
- **2026-10-09 (thirty-fourth pass):** M-D1 atomic WAL checkpoint --
  `wal_persist` writes `<path>.tmp` and swaps via `io.rename` (platform
  replace semantics on Windows + WSL); `probe_wal_file` +7 fault-injection
  checks (no temp left behind; staged-complete temp and partial temp both
  leave the previous checkpoint intact; completed persist advances the
  file). D 63 -> 65; overall 70.42 -> 70.82 -> 71 %. Evidence: full
  batteries (suite 169/169 x2 + 18 probes x2, Windows + WSL), ALL GATES
  GREEN.
- **2026-10-09 (thirty-sixth pass):** M-Q1 exact range search --
  `search_range_scan` kernel + `engine_search_range` + facade
  `search_range`: every point within `radius` (inclusive), distance-sorted
  ascending, bounded by `limit`; exact on both index kinds (ANN widening is
  M-P tuning); dim mismatch / limit 0 / negative radius rejected. Probe
  `probe_range_search` (72 radius x limit combos vs a local brute-force
  scan, inclusive-boundary, radius-0, KNN-equivalence, Hnsw routing, reopen
  checks); suite mirror test added (169 -> 170). B 95 -> 97; overall
  70.82 -> 71.02 -> 71 %. Evidence: full batteries (suite 170/170 x2 + 19
  probes x2, Windows + WSL), ALL GATES GREEN.
- **2026-10-09 (thirty-seventh pass):** M-Q2 batch ops -- `upsert_many` /
  `delete_many` / `search_many` + `BatchHits`: all-or-nothing validation
  per call (bad dimension/length/empty leaves the engine untouched), delete
  counts actual removals (missing ids skipped), search returns one set per
  query in order. Probe `probe_batch_ops` (14 checks incl. recover
  equality, duplicate-id collapse, Hnsw batch path); suite mirror test
  added (170 -> 171). F 70 -> 73; overall 71.02 -> 71.26 -> 71 %. Evidence:
  full batteries (suite 171/171 x2 + 20 probes x2, Windows + WSL), ALL
  GATES GREEN.
- **2026-10-09 (thirty-eighth pass):** M-G benchmark harness + baseline --
  `bench/bench_main.xi` (deterministic W1-W7 workloads, integer JSON,
  group-calibrated sampling, hard-capped budgets, `XV_BENCH_STAGE`
  diagnostics) + `scripts/bench.ps1/.sh`; **bench smoke wired into both CI
  batteries**; baseline committed in `docs/BENCHMARKS.md`. Found and fixed
  the **O(L^2) `wal_persist` string builder** (linear `append_bytes`; the
  builder drove multi-GB paging during bring-up); `probe_wal_file` +4
  scale checks (1200 records). Native `--icon` embedding wired
  (`scripts/build.ps1` + `images/xvector-icon.ico`). I 84 -> 86; overall
  71.26 -> 71.44 -> 71 %. Evidence: full batteries (suite 171/171 x2 + 20
  probes x2 + bench smoke, Windows + WSL), ALL GATES GREEN.
- **2026-10-09 (thirty-ninth pass):** M-D2 manifest file -- new
  `durability.manifest_file` (`xvector-manifest 1` text registry: one line
  per collection `name dim mc kc m efc efs`; whole-file persist with atomic
  temp+rename; invalid entries refused with the target untouched;
  torn-tail-safe byte-level load with a complete-entry prefix; names 1..64
  chars of `[A-Za-z0-9_.-]`). Engine: `engine_manifest_save` +
  `engine_recover_file` (facade `save_manifest`/`open_engine`) -- the file
  registry governs and the in-WAL manifest is the migration fallback
  (shared private `engine_recover_with`). Stable metric/kind codes moved to
  the leaf modules; wal_file byte helpers shared (`parse_int_at`,
  `append_bytes`). New compiler finding **XVC-C-13** (`&Str` params
  mislower to i64; repro `docs/repro/xv-str-ref-param/`, relay Addendum 9).
  Probe `probe_manifest_file` (38 checks; both batteries now 21 probes).
  D 65 -> 68; overall 71.44 -> 72.04 -> 72 %. Evidence: full batteries
  (suite 171/171 x2 + 21 probes x2 + bench smoke, Windows + WSL), ALL GATES
  GREEN.
- **2026-10-09 (fortieth pass):** M-D3 multi-collection registry -- named
  collections (create/select/drop/list; facade + engine), per-collection
  isolation of stores/payloads/index configs, WAL ManifestUpdate v2 config
  + v3 drop records with cid-stamped data records, routed multi-collection
  recovery (D3 strict mode; legacy logs route to the single collection),
  whole-registry checkpoint, whole-registry `save_manifest` + file-wins
  `open_engine`, legacy `create_collection` -> "default". Gate
  `probe_collections` (41 checks; batteries now 22 probes). F 73 -> 75,
  G 10 -> 25; overall 72.04 -> 73.70 -> 74 %. Evidence: full batteries
  (suite 171/171 x2 + 22 probes x2 + bench smoke, Windows + WSL), ALL
  GATES GREEN; no regression across the recovery rewrite.
- **2026-10-09 (forty-first pass):** M-D4 sealed segment files -- new
  `segment.segment_file` codec (meta + vector + payload + optional Hnsw
  graph records; whole-file atomic persist; torn-tail-safe complete-record
  prefix load; 41-byte size guard), `segment_state_from_code`, engine
  `engine_seal_segment` (real lifecycle Mutable -> Sealing -> Sealed) and
  `engine_restore_segment` (cid/dim/metric validated; WAL re-checkpoint via
  the shared `engine_checkpoint_from`, LSN-continuous), facade
  `seal_segment`/`restore_segment`. Gate `probe_segment_file` (38 checks;
  batteries now 23 probes). D 68 -> 73; overall 73.70 -> 74.70 -> 75 %.
  Evidence: full batteries (suite 171/171 x2 + 23 probes x2 + bench smoke,
  Windows + WSL), ALL GATES GREEN.
- **2026-10-09 (forty-second pass):** M-Q3 pagination -- new
  `query.pagination` (offset + after-id kernels over the (distance
  ascending, id ascending) total order; bounded collector with the id
  tie-break), engine/facade `search_page` / `search_after` (missing
  cursor -> `Err(NotFound)`; exact on Flat AND Hnsw). Gate
  `probe_pagination` (22 checks; batteries now 24 probes): page
  reconstruction without gaps/dupes, exact tie clusters id-ascending,
  cursor walks across tie boundaries, refusals, Flat/Hnsw bit-parity,
  pages after recovery, deleted cursors. F 75 -> 78; overall 74.70 ->
  74.94 -> 75 %. Evidence: full batteries (suite 171/171 x2 + 24 probes
  x2 + bench smoke, Windows + WSL), ALL GATES GREEN.
- **2026-10-09 (forty-third pass):** M-Q4 delete-by-filter --
  `engine_delete_filter` / `delete_filter`: planner-driven selective
  delete (index candidates for Eq/Range/Exists/And-of-those, each
  verified; live-store scan for In/Or/Not), ids collected before
  mutation and applied ascending through the gated single-delete path
  (per-point WAL, graph tombstones, payload + index cleanup); nothing
  matching -> Ok(0). Gate `probe_delete_filter` (26 checks; batteries
  now 25 probes). F 78 -> 80; overall 74.94 -> 75.10 -> 75 %. Evidence:
  full batteries (suite 171/171 x2 + 25 probes x2 + bench smoke, Windows
  + WSL), ALL GATES GREEN.
- **2026-10-09 (forty-fourth pass):** M-Q5 index admin --
  `engine_collection_stats` / `collection_stats` (per-collection config,
  live points, payloads, Hnsw nodes + tombstones, shared WAL lsn; active
  from the live fields, parked from registry entries) and
  `engine_rebuild_index` / `rebuild_index` (admin rebuild with
  kind/points/nodes_before/nodes_after/reclaimed stats; Hnsw fresh graph
  over live nodes, Flat no-op; compact_index stays the Int wrapper). Gate
  `probe_index_admin` (20 checks; batteries now 26 probes). F 80 -> 82;
  overall 75.10 -> 75.26 -> 75 %. Evidence: full batteries (suite 171/171
  x2 + 26 probes x2 + bench smoke, Windows + WSL), ALL GATES GREEN.
- **2026-10-09 (forty-fifth pass):** M-Q6 request surface extensions --
  `SearchRequest` gains mode (knn/range), radius (top_k = inclusive-radius
  limit), and knn offset/after-id pagination (mutually exclusive; filters
  stay Knn-only; cursor keeps `Err(NotFound)`); `SearchBatchRequest` +
  `HydratedBatch` + `search_batch_with_request` (ordered, all-or-nothing);
  dimension/top_k/metric validation unchanged. Gate `probe_search_request`
  extended 10 -> 24 checks (probe-only; the suite mirror is a standalone
  re-implementation and stays untouched). F 82 -> 84; overall 75.26 ->
  75.42 -> 75 %. Evidence: full batteries (suite 171/171 x2 + 26 probes x2
  + bench smoke, Windows + WSL), ALL GATES GREEN.
- **2026-10-09 (forty-sixth pass):** M-G1 reference oracle --
  `probe_reference_oracle` (22 checks): an independent Float64 oracle
  cross-checks the three kernels pairwise (780 seeded pairs each;
  per-build deviations at Float32-ulp scale -- cosine 1.70e-07, dot
  9.83e-07, euclidean 5.06e-07, bit-identical Windows/WSL), the metric
  axioms (exact symmetry; self-distance l2==0 / cosine~0 / dot==-|v|^2;
  euclidean triangle inequality; cosine [0,2] + exact x2 scale
  invariance; zero-vector guard == 1.0), and the ranked/page/cursor/range/
  Hnsw paths vs the oracle ranking (top-5 rank exact per metric,
  inclusive-range subset at a midpoint radius, engine-distance boundary
  inclusion, Hnsw recall@5 == 5/5 + distance fidelity). Batteries now 27
  probes. I 86 -> 92; overall 75.42 -> 75.96 -> 76 %. Evidence: full
  batteries (suite 171/171 x2 + 27 probes x2 + bench smoke, Windows +
  WSL), ALL GATES GREEN.
- **2026-10-09 (forty-seventh pass):** M-S1 HTTP service skeleton -- new
  `api.http_service` (transport-agnostic HTTP/1.1 byte pipeline:
  strict parse -> router -> stdlib-JSON wire -> byte-exact responses; no
  sockets until the `xiom.net` proof). Endpoints: `/health`,
  `/collections`, points get/upsert/delete, `/search` (knn/range/page/
  batch), `/stats`. Uses QUALIFIED stdlib JSON calls (`json.json_*`): the
  parent `xiom.serialize` helpers misresolve in this unit (BUG 25 #1,
  documented in the json module header) and unqualified calls silently
  built empty strings -- pinned as lane discipline. Two real parser bugs
  found by the probe and fixed (method never stored; last header line
  dropped). Gate `probe_http_service` (40 checks; batteries now 28
  probes). F 84 -> 86, H 20 -> 28; overall 75.96 -> 76.52 -> 77 %.
  Evidence: full batteries (suite 171/171 x2 + 28 probes x2 + bench
  smoke, Windows + WSL), ALL GATES GREEN.
- **2026-10-09 (forty-eighth pass):** M-S2 service config/limits/errors --
  `ServiceConfig` (max_request_bytes 65536 / max_top_k 1000 / max_batch
  256 / max_dim 1024) with env (`XVECTOR_MAX_*`; malformed ignored) and
  key=value file loaders (comments; unknown keys ignored; a malformed line
  sets valid=false while good lines still apply); `http_service_handle_cfg`
  enforces limits (request size and batch counts -> 413 too_large
  before/at routing; named top_k/dim -> 400; exact boundaries accepted);
  every error is `{error,kind,status}` with stable kinds and
  `core_err_response` maps the full CoreError enum;
  `http_service_shutdown` = drain + whole-file WAL checkpoint (false on
  unwritable paths). Gate `probe_service_limits` (27 checks; batteries now
  29 probes). F 86 -> 88; overall 76.52 -> 76.68 -> 77 %. Evidence: full
  batteries (suite 171/171 x2 + 29 probes x2 + bench smoke, Windows +
  WSL), ALL GATES GREEN.
- **2026-10-09 (forty-ninth pass):** M-S3 service auth + rate limiting --
  `ApiScope` (read < write < admin) + `ServiceAuth` (keys 8..128 of
  `[A-Za-z0-9_.-]`, duplicates rejected, first key enables; embedded
  default off), constant-time lookups via
  `xiom.crypto.mac.constant_time_eq`, `XVECTOR_API_KEYS` env loader, route
  scope map (`/health` public; POST /collections Admin; points
  POST/DELETE Write; else Read), 401 unauthorized / 403 forbidden kinds;
  token-bucket `RateLimiter` (capacity + refill/sec, explicit clock) with
  429 rate_limited; `ServiceState` + `http_service_handle_state`
  (auth-off == handle_cfg). Gate `probe_service_auth` (24 checks;
  batteries now 30 probes). F 88 -> 89; overall 76.68 -> 76.76 -> 77 %.
  Evidence: full batteries (suite 171/171 x2 + 30 probes x2 + bench
  smoke, Windows + WSL), ALL GATES GREEN.
- **2026-10-09 (fiftieth pass):** M-S4 security pass -- `docs/SECURITY.md`
  (assets, trust boundaries, secure-defaults table, threat/control
  matrix, dependency + SBOM statement, no-unsafe audit, honest
  out-of-scope list). `probe_http_fuzz` (14 checks): 1200 seeded mutations
  + 1300 random streams all well-formed; targeted abuse (lying
  Content-Length, 2000-header flood, 30 KB header, 60 KB unbalanced JSON,
  8000-deep nesting, NUL bytes, 500-segment path, 300-burst) bounded.
  **Found + fixed a remote stack-exhaustion DoS:** stdlib `json_parse`
  recurses per nesting level and ~60 KB of `[` (inside the body limit)
  crashed with an access violation; the HTTP edge now pre-scans bodies
  with `json_depth_ok(body, 64)` and rejects deeper payloads with 400
  (stdlib row filed in `docs/STDLIB-WISHLIST-XVECTOR.md`).
  `scripts/sbom.ps1`/`sbom.sh` emit `out/sbom.json` (compiler, stdlib
  pin, per-module sha256, unsafe=0) and fail on any `unsafe` in src/;
  both batteries run the SBOM + unsafe gate. Lane re-check at the wrap:
  stdlib advanced `ed6d46c` -> `d2b18dc` (waves 100-101) but
  fsync/fdatasync/truncate/append remain stubs -- D5/D6/P5 stay gated.
  I 92 -> 94, J 48 -> 52; overall 76.76 -> 77.26 -> 77 %. Evidence: full
  batteries (suite 171/171 x2 + sbom + 31 probes x2 + bench smoke,
  Windows + WSL), ALL GATES GREEN.
- **2026-10-09 (fifty-first pass):** M-O observability core -- new
  `observability.metrics` (fixed-bucket latency histograms with
  `_sum`/`_count`/p50/p95/p99; the requests/errors/search/upsert/
  auth_failures/rate_limited counters; a bounded, sanitized JSON log ring
  with slow-query flag), public `GET /metrics` (prometheus text + live
  gauges collections/points_active/lsn), `/health` `ready:true`,
  per-request instrumentation in `http_service_handle_state`, and
  `docs/OPERATIONS.md` (runbook + failure domains + backup drill). Found
  + worked around the XVC-C-09 family again: nested-field mutation
  through a `&mut` param (`st.metrics.counter`) silently does not
  persist -- copy-out + single write-back. Gate `probe_metrics` (23
  checks; batteries now 32 probes). H 28 -> 70, J 52 -> 54; overall
  77.26 -> 79.52 -> 80 %. Evidence: full batteries (suite 171/171 x2 +
  sbom + 32 probes x2 + bench smoke, Windows + WSL), ALL GATES GREEN.
- **2026-10-09 (fifty-second pass):** M-R release candidate v1.0.0-rc.1 --
  `VERSION` bump, release notes, SBOM snapshot
  (`docs/sbom-v1.0.0-rc.1.json`; 44 modules, unsafe=0), the PULSE-style
  owner handoff (`docs/OWNER-HANDOFF.md`: repo public, runners, rulesets,
  publish flow, benchmark protocol, gated-pivot table, evidence index),
  and the audited `docs/RELEASE-CHECKLIST.md` (all primary repro bundles
  re-run at v0.64.2: 9 green, `contract-trap-exit0` exit 1 = the fixed
  symptom, XVC-C-13 red by design). Final batteries at the candidate
  commit `5226226` on **Windows and WSL**: suite 171/171 x2 + sbom + 32
  probes x2 + bench smoke, ALL GATES GREEN; annotated tag `v1.0.0-rc.1`
  (no GPG key available; DCO sign-off on every commit). J 54 -> 56;
  overall 79.52 -> 79.68 -> 80 %. The owner has been told; the public
  release + benchmark remain the owner's actions.
- **2026-10-10 (fifty-third pass):** `xiom.wal` first adoption --
  C-PULSE-02 RESOLVED in v0.64.2 (registry `[dependencies]` map installed
  package roots); `xiom.wal` 0.1.0 installed from the registry on Windows
  + WSL (sha256 + ed25519 verified, registry key pinned via
  `xiom pkg trust` fp `4f:3b:47:f3:ae:17:b1:3c`), `xiom.toml
  [dependencies]` wired, and the alignment gate `probe_package_wal`
  (9 checks: op codes 1..7 byte-identical, tagged roundtrip, LSN resume,
  torn-tail skip + heal-on-open, missing-path open) added to both
  batteries (now 33 probes). Discovery: `xiom.metrics` 0.2.0,
  `xiom.rate` 0.2.0, `xiom.router` 0.1.0, `xiom.http` 0.1.4 are installed
  and registry-live -- scheduled as the next adoption slices (metrics
  first, then rate, then router/http evaluation). J 56 -> 58; overall
  79.68 -> 79.84 -> 80 %. Evidence: full batteries (suite 171/171 x2 +
  sbom + 33 probes x2 + bench smoke, Windows + WSL) with the dependency
  active in every build, ALL GATES GREEN.
- **2026-10-10 (fifty-fourth pass):** XV-ORBITDB-01 fix (first bus item,
  reported by the orbitdb lane): `wal_load` required the first record's
  LSN to be exactly 1, so a re-persisted recovered checkpoint (resumed
  LSNs) reloaded EMPTY -- silent vector loss on the next open. Fixed in
  commit `3c36f34`: any starting LSN >= 1 accepted, consecutive +1
  stepping still enforced, torn-tail/corruption behavior unchanged. Gate
  `probe_wal_file` +3 chained checks (34 total in that probe; batteries
  still 33 probes). Bus item `REL-20261010-1550-orbitdb-11` moved
  open -> acked -> fixed with the commit ref. D 73 -> 74; overall 79.84
  -> 80.04 -> 80 %. Evidence: full batteries (suite 171/171 x2 + sbom +
  33 probes x2 + bench smoke, Windows + WSL), ALL GATES GREEN.
- **2026-10-10 (fifty-fifth pass):** xiom.metrics 0.2.0 adoption --
  `observability.metrics` internals swapped onto the registry package
  behind the same exported surface (`/metrics` byte-identical: package
  Histogram/Counter value types, lane accessors + percentile helper, the
  Prometheus histogram block moved into the module); engine stat counters
  (`upserts`/`deletes`) moved onto the package and the core shim Counter
  retired. Found **XVC-C-14** (two same-named struct types across
  modules shadow each other's field layout: clang store reject when the
  shapes differ, silent wrong fields when they match); repro
  `docs/repro/xv-counter-type-shadow/` (Windows + WSL identical), relay
  Addendum 10, bus `REL-20261010-1709-xvector`; workaround = one type
  name, one type. Bus: `REL-20261010-1550-xvector-7` (stdlib json depth
  cap) verified + closed (128-deep Ok; 129/60000 Err; Windows + WSL
  identical). Gates: `probe_package_metrics` (12 checks) + re-gated
  `probe_metrics` (24 checks); batteries now 34 probes. H 70 -> 88;
  overall 80.04 -> 80.94 -> 81 %. Evidence: full batteries (suite
  171/171 x2 + sbom + 34 probes x2 + bench smoke, Windows + WSL), ALL
  GATES GREEN.
- **2026-10-10 (fifty-sixth pass):** xiom.rate 0.2.0 adoption -- the S3
  `RateLimiter` internals run on the registry package `TokenBucket`
  behind the same API (429 path + the rate-limited counter unchanged);
  the package carries unearned sub-token remainders, so fractional
  refill is now exact (the lane limiter consumed the whole elapsed span
  and discarded them); every gate-visible boundary unchanged. Gates:
  `probe_package_rate` (14 checks, direct package incl. the carry case)
  added; batteries now 35 probes; `probe_service_auth` (24) /
  `probe_metrics` (24) re-run green. Also: orbitdb closed the
  XV-ORBITDB-01 bus item after verification, and compiler **v0.64.3
  released** (upgrade + full re-test + XVC-C-13/C-14 verdicts are the
  next pass). No score change (capability identical; adoption depth
  tracked in J). Evidence: full batteries (suite 171/171 x2 + sbom + 35
  probes x2 + bench smoke, Windows + WSL), ALL GATES GREEN.
- **2026-10-10 (fifty-seventh pass):** compiler v0.64.3 re-pin + lane
  isolation -- v0.64.3 (release run `38071481303`) installed lane-local
  on Windows + WSL; full re-test on it (all 12 repro bundles re-run;
  XVC-C-13/C-14 **UNCHANGED** -> release-check verdicts filed); the
  shared toolchain homes were deleted by concurrent activity mid-battery
  (diagnosed; incident `REL-20261010-1835-xvector`, to ops), and the
  lane is now immune via lane-local toolchain + package homes in the
  dev-env scripts (found on the way: WSL `xiom pkg` custom-`XIOM_HOME`
  misplacement, `REL-20261010-1937-xvector`). No score change (same
  capability; environment hardening). Evidence: Windows + WSL isolated
  batteries ALL GATES GREEN (suite 171/171 x2 + sbom + 35 probes x2 +
  bench smoke each).
- **2026-10-10 (fifty-eighth pass):** xiom.router/xiom.http helper
  evaluation -- `xiom.http.status.http_status_text` adopted behind a
  lane adapter (wire-identical; the upstream 507 gap lane-owned and
  filed as `REL-20261010-2002-xvector`); router + parser/types/client
  evaluated, not adopted (reasons in `docs/XIOM-HTTP-EVAL.md`). New
  `probe_package_http` (5 checks) + the raw 507 status-line pin in
  `probe_http_service` (41 checks); batteries now 36 probes. No score
  change. Evidence: suite 171/171 x2 + sbom + 36 probes x2 + bench
  smoke, Windows + WSL, ALL GATES GREEN.
- **2026-10-10 (fifty-ninth pass):** xiom.vectors 0.1.0 wiring +
  extraction-fidelity gate -- all six SPEC extraction pins match the
  current tree byte-for-byte (the package is a carve of this lane's own
  primitives; behavior-identical by construction); dependency wired,
  `probe_package_vectors` (13 checks) added, the package's own codec
  probe green from the lane home; internals swap (lane facades) planned
  in `docs/XIOM-VECTORS-EVAL.md` behind owner greenlight `-12`.
- **2026-10-10 (sixtieth pass):** xiom.vectors internals swap executed --
  the atomic change set put every consumer on the package (11 source
  modules + 27 probes; five local modules deleted; WAL value codec
  extracted from `vector_store`); behavior-identical (extraction pins
  byte-exact), full batteries green on Windows AND WSL; docs swept to
  the package paths; the silent-unresolvable-import diagnostic gap found
  and filed (`REL-20261010-2124-xvector`). J 58 -> 60 (porter cycle
  completed: extract -> wire -> swap -> verify); overall 80.94 -> 81.10
  -> 81 %. Evidence: suite 171/171 x2 + sbom + 37 probes x2 + bench
  smoke, Windows + WSL, ALL GATES GREEN.
- **2026-10-11 (sixty-first pass, docs-only):** owner granted the
  reference study area (`E:\repos`): clone MIT-licensed OSS as study
  references (never vendored, never a build dependency; adopted patterns
  are re-implemented under our license and gated). Cloned and
  MIT-verified: `sqlite-vec`, `faiss`, `DiskANN`; study backlog seeded in
  SESSION 2. No score change (no product evidence yet). Independent
  re-verification at the quiet era: suite 171/171 x2 + sbom + 37 probes
  x2 + bench smoke (Windows, compiler v0.64.3, lane-local XIOM_HOME, 39
  modules), ALL GATES GREEN; `xiom.ann` still 404 at the registry.
- **2026-10-11 (sixty-second pass, docs-only):** reference study 01 --
  `docs/REFERENCE-STUDY-01-FAISS.md` (MIT; no vendoring, no dependency).
  Reconnaissance of FAISS HNSW vs ours with source citations: level
  distribution (`HNSW.cpp:63/67`), visited generation tags (`:428`,
  `VisitedTable.h`), level-0 degree generosity (`shrink_neighbor_list`
  `:245`, `keep_max_size_level0`), mmap/zero-copy IO notes (`mapped_io.h`,
  `zerocopy_io.h`), SQ/PQ pointers. Ranked proposals with gate plans;
  P-a (level-0 degree `2*M`) is the first candidate slice. No score
  change (no product evidence yet).
- **2026-10-11 (sixty-third pass):** P-a applied -- generous HNSW level 0,
  re-implemented from reference study 01 (no vendoring): level-0 capacity
  `m0 = 2*m`, full-block prune to 80% of `m0` (FAISS `prune_headroom` 0.2
  anti-churn), adjacency rows stride `m0`, codec **v3** carries `m0`
  (v2 still decodes), `hnsw_new_full` for the legacy control. Gate
  `probe_hnsw_recall` extended: generosity-engaged structural checks, a
  bit-identical WSL run, and a hard clustered corpus (n=300 dim=16,
  midpoint queries at ef=8) where generous **285/300** beats the legacy
  control **275/300**; the FAISS `keep_max_size_level0` fill arm was
  measured (same recall, ~2.5x build work, ~40% more visited) and not
  adopted. Costs recorded honestly: build 13.0 -> 14.7 s, W3 p50
  +28/+34/+40% at ef=32/64/128, recovery +27% (n=5000, recall 1.000
  unchanged); per-ef table refreshed in `docs/hnsw-design.md`. C 98 -> 99;
  overall 81.10 -> 81.24 -> 81 %. Evidence: suite 171/171 x2 + sbom
  (39 modules, unsafe=0) + 37 probes x2 + bench smoke, Windows AND WSL
  (bit-identical), C-10 repro re-run green on codec v3.
- **2026-10-11 (sixty-fourth pass, docs-only):** reference study 02 --
  `docs/REFERENCE-STUDY-02-QUANTIZATION.md` (MIT/Apache sources; no
  vendoring, no dependency). Reconnaissance: FAISS SQ (`QT_8bit` trained
  per-dim ranges, `sq_fastscan_utils.h:91-95`; fast-scan hi/lo split),
  FAISS PQ (per-slice k-means + ADC tables), sqlite-vec int8 (fixed
  `[-1,1]` scale -- unit-range assumption flagged), binary + Hamming
  kernels, the two-tier rescore pattern (`_rescore_chunks` quantized scan
  + `_rescore_vectors` exact rerank, oversample default 8/cap 4096), and
  DiskANN neighbour quantization. Ranked proposals Q-a..Q-d (Q-a = SQ8
  quantized scan tier + exact f32 rescore for sealed segments, the first
  adoption candidate; PQ deferred pending deterministic training) plus a
  required error-bound story section (per-component `vdiff/255` bound and
  derived dot/L2/cosine bounds; the oracle probe stays the fidelity
  reference). No score change (no product evidence yet -- reconnaissance
  only; code tree unchanged, last full battery still valid).
- **2026-10-11 (sixty-fifth pass, docs-only):** reference study 03 --
  `docs/REFERENCE-STUDY-03-DISKANN.md` (MIT sources: the DiskANN Rust
  rewrite + sqlite-vec's LM-DiskANN; no vendoring). Reconnaissance:
  sector-packed fixed-size node records (4096 B sectors, nodes never
  split, padding rules), record content (full-precision vector +
  adjacency in one sector), header-in-sector-0 + layout-version bump
  discipline, the three-way aligned-read contract, hot-vertex caching,
  PQ on disk, the buffer-threshold-then-flush append model, and LM-Delete
  edge repair/scrub. Design input recorded for D5 (fixed node_len + delta
  tier), D5 search (merge + re-rank locality), D6 (drop/re-seal, never
  in-place edge surgery) and P5 (alignment as a format decision now).
  Study backlog complete (1-3; item 3 folded into study 02). No score
  change (reconnaissance only; code tree unchanged).
- **2026-10-11 (sixty-sixth pass):** Q-a1 -- SQ8 quantization module +
  two-tier rescore (reference study 02, no vendoring):
  `src/index/quantize.xi` (trained per-dim ranges, FAISS truncation codec,
  FAISS-pattern query tables, sqlite-vec's rescore contract),
  `probe_quantization` (17 checks: determinism, bounds, rejection,
  bit-identical rescore for 10 queries x 3 metrics, coarse deviation
  measured 0.0257 <= documented bound 0.6307, bytes/vector 32 B -> 8 B),
  suite Section 16 (177 checks total), scripts + repro updated. Found and
  filed compiler finding **XVC-C-15** (literal stores into `Vec[Float32]`
  slots skip narrowing; `REL-20261011-1134-xvector`; repro bundle;
  Windows + WSL identical) and worked around it (explicit cast). No score
  change: gated capability with no query path yet (Q-a2 lands with D5;
  C stays 99). Evidence: suite 177/177 x2 + sbom (40 modules, unsafe=0) +
  38 probes x2 + bench smoke (Windows) ALL GREEN; WSL spot green
  (suite 177/177, quantization x2 diag bit-identical, C-15 repro
  identical).
- **2026-10-11 (sixty-seventh pass):** Q-a2a -- the segment artifact half
  of Q-a: `SealedSegment` gains `has_sq/sq/codes` +
  `sealed_segment_enable_sq` (opt-in SQ8 training on the segment's
  vectors); segment codec **version 2** writes `q` (ranges) + `c` (code
  records) sections after the graph only when armed (v1 output
  byte-identical otherwise; header `xvector-segment 2`); the loader
  accepts v1+v2, validates ranges/codes in store order, and drops a
  torn/partial SQ section while keeping the vectors. Gates:
  `probe_quantization` grew to 23 checks (seal + enable_sq, v1/v2
  persist + load roundtrip of ranges+codes, rescore over the loaded
  segment bit-equal to the exact scan for 10 queries, torn q/c keeps the
  vectors, byte delta 35 B/vector in the text codec vs the future binary
  layout's 8 B). No score change (artifact capability; the consuming
  read path is Q-a2b at D5). Evidence: suite 177/177 x2 + sbom (40
  modules, unsafe=0) + 38 probes x2 + bench smoke (Windows) ALL GREEN;
  WSL spot green; segment v1 tear-sweep diags byte-identical.
  Also: owner directive 2026-10-11 11:59Z (engine P3 vulkan/sdl
  priority) routed read-only to bindings
  (`REL-20261011-1203-xvector`) and packages (`-2`) -- no writes into
  those live workspaces.
- **2026-10-11 (sixty-eighth pass, docs-only):** `xiom.ann` porter
  evaluation -- the registry watch closed (`xiom.ann` 0.1.0 LIVE,
  eco-v0.1.139, sha256 `73f66ab5...`, deps `xiom.vectors 0.1.0`); the
  published package is the pre-P-a snapshot (extracted @ `8a8b0ff`:
  no `m0`/generous level 0, codec v2 only, legacy 296/300 recall), so
  the consumer swap is blocked on a refresh; **`xiom.ann` 0.2.0 ask
  filed** (`REL-20261011-1206-xvector`) to carry the P-a generous level 0
  + codec v3 from our HEAD; evaluation recorded in
  `docs/XIOM-ANN-EVAL.md` (adoption plan + risks: codec v3 round-trip,
  mechanical re-extraction, WSL custom-home caveat). Swap next: package
  0.2.0 + owner   greenlight (vectors precedent). No score change (porter
  flow, no product path yet); the orbitdb hybrid note was also confirmed
  fixed on their side (missing `xiom.vectors` deps -- our diagnosis).
- **2026-10-11 (sixty-ninth pass):** the runnable server (`xvectord`) --
  `src/api/httpd.xi`: sequential-accept socket adapter over the stdlib
  `xiom.net` layer (the PULSE production pattern), strict
  headers/Content-Length request framing with a 4 MiB socket guard,
  `TcpStream.write_all` responses, 30 s dead-peer guard, graceful
  `X-Xvector-Quit: 1` shutdown, `--bind/--port` + `XVECTORD_*` env;
  `main` entry so the compiler emits a double-clickable `xvectord.exe`.
  Gate `probe_http_server` (10 checks over real sockets in one process:
  health/collections/points/stats/search, 409/404 honesty, quit rc,
  empty-connection close) green x2 Windows + WSL; **curl end-to-end user
  test green** (health -> create -> upsert 3 -> search k=2 returns id 1
  at 0.0061 -> stats -> quit -> clean exit). F 89 -> 96 (only the version
  endpoint remains); overall 81.24 -> 81.80 -> **82 %**. Evidence:
  suite 177/177 x2 + sbom (41 modules, unsafe=0) + 39 probes x2 + bench
  smoke (Windows) ALL GREEN; WSL spot (server probe x2 + service probe)
  green. First user-testable artifact of the lane.
- **2026-10-11 (seventieth pass):** benchmark integration (starter) +
  API completion -- `GET /version`; index configuration at collection
  create (`index`/`m`/`ef_construction`/`ef_search`; `handle_create_collection`
  calls `engine_set_index`; response carries the kind); per-request
  `ef_search` on /search via the new `engine_set_ef_search` (validated
  1..4096, no rebuild, no manifest write); `xvectord` now applies the
  documented `XVECTOR_MAX_*` service limits per request
  (`service_config_from_env` in `httpd_once`; socket guard 32 MiB). New
  `bench/adapters/`: stdlib `xvector_client.py`, ann-benchmarks
  `module.py` + `config.yml` (metric map angular/euclidean/dot; ef sweep
  16..256), and `smoke.py` -- **live green against a default-cap server**
  (version -> HNSW create -> 400-pt batched upsert (0-based ids) -> ef
  sweep recall@10 1.000 at ef>=64, 0.940 at ef=8 -> duplicate 409).
  `probe_http_server` grows to 15 checks (version, ef override, hnsw
  create/search). **F 96 -> 100** (its last remaining item shipped);
  overall 81.80 -> 82.12 -> 82 %. Evidence: suite 177/177 x2 + sbom (41
  modules, unsafe=0) + 39 probes x2 + bench smoke (Windows); WSL spot
  green.

- **2026-10-11 (seventy-first pass):** the first HTTP-path benchmark
  exposed a stdlib blocker: `json_parse` superlinear on numeric payloads
  (2.5k/5k/10k/20k numbers -> 248 ms/1.10 s/4.77 s/17.9 s; the 50k-number
  382 KB upsert body -> 83.7 s = ~88% of the request; engine insert
  2 ms/vector). Pinned repro `docs/repro/xv-json-parse-quadratic/`
  (self-contained, gate fails pre-fix) + `bench/adapters/quick_bench.py`;
  filed to stdlib as `REL-20261011-1453-xvector` (high). HTTP-path
  numbers recorded in `docs/BENCHMARKS.md`. No score change (blocker
  documented).
- **2026-10-11 (seventy-second pass):** hot-path unblock -- ROOT CAUSE
  found: **`slice.str_bytes(Str)` is superlinear** (50/100/200/400 KB ->
  116/289/1065/3981 ms; pinned probe
  `docs/repro/xv-json-parse-quadratic/probe_strbytes.xi`); stdlib lane
  independently root-caused it to the `strnlen` accessors and queued the
  fix (wave-111 top candidate, `6fbd336`). Lane mitigation shipped:
  `src/api/json_fast.xi` (byte-level canonical upsert scanner; inline
  decimal accumulation; conservative bounds; None -> strict fallback) +
  `HttpRequest.body_bytes` + the dispatch fast branch; gate
  `probe_json_fast` (228 fast-vs-strict cases byte-for-byte equal; 52k
  numbers in 1.7-2.9 s vs strict ~84 s). Measured: 5k x dim-25 fit
  through `xvectord` **661 s -> 120 s** (HNSW-build-bound, ~42 pts/s);
  search 53-78 QPS. F stays 100; overall 82 %. Evidence: suite 177/177
  x2 + sbom (42 modules, unsafe=0) + 40 probes x2 + bench smoke
  (Windows); WSL spot green. Re-verify the repros + batteries when the
  stdlib fix lands; compiler fn-ABI batch `fde5548e` also landed (C-15 /
  phantom-import re-tests are the next session's first step).
- **2026-10-11 (seventy-third pass):** re-verification era opened on the
  new pins (stdlib `b8eda7d` wave 110 + wave-111 WIP; packages
  `fb73c5c8`; compiler `fde5548e` lane HEAD, v0.64.3 still installed).
  `xiom.http` **0.1.6 re-sync**: native `507 Insufficient Storage`
  (sha256 `bb8a5029...`, registry key pinned in both lane homes); the
  lane 507 special-case retired (`status_text` keeps only the
  `Unknown -> "Error"` fallback delta); `probe_package_http` 5 -> 6
  checks (native 507 + fallback contract). **The stdlib `strnlen` fix is
  verified in the wave-111 WIP**: both repro probes exit 0 -- 400 KB
  `str_bytes` **438 ms** (was 3981 ms); 20k-number parse **755 ms** (was
  17.9 s); the 5k x dim-25 fit through `xvectord` 120 s -> **57.4 s**
  (87 pts/s; HNSW-build bound). Batteries on the pins: suite 177/177 x2
  + sbom (42 modules, unsafe=0) + 40 probes x2 + bench smoke (Windows) +
  WSL spot (suite x2 + http probes) -- ALL GREEN; WIP hashes unchanged
  before/after. Gated pivots re-checked: fsync/fdatasync/fsync_dir + the
  whole mmap family still documented stubs (D5/D6/P5 stay gated); no new
  compiler release (C-15/phantom fixes not yet landed; batch plan
  `REL-20261011-1342-compiler`). Bus: -2002 (507), -1206 (ann 0.2.0),
  -1550-xvector-9 (vectors extraction), -1835 (toolchain hygiene)
  verified + closed; WIP signal `REL-20261011-1618-xvector` filed. No
  score change (82 %).
- **2026-10-11 (seventy-fourth pass):** VectorDBBench adapter shipped:
  `bench/adapters/vectordbbench/` -- `xvector_db.py` (framework-tolerant
  DB client: create with drop_old best-effort, batched insert_embeddings
  returning (count, error), search with (distance, id) rows, config
  plumbing from db_config/env, metric map COSINE/L2/IP; metadata +
  filters fail loudly -- not exposed over HTTP yet) + `smoke_db.py`
  (direct-mode live smoke, 11 checks: insert 400/400, recall 1.000 at
  the configured ef, 0.930 at ef=8, 1.000 at ef=128, unsupported-path +
  drop-fallback checks) + the drop-in README. New shared
  `bench/adapters/oracle.py` (smoke.py + quick_bench.py refactored onto
  it; one brute-force implementation). Validation: py_compile 6/6 +
  three live smokes against `xvectord` (raised caps); the .xi tree is
  byte-identical to the `de151d6` tree (two batteries green this
  session), so no separate battery for this Python-only slice -- the
  wave-111 closure battery covers the wrap. No score change (82 %).
- **2026-10-11 (G-phase groundwork: thread gate):** probed the real
  threading path ahead of the concurrency phase. `xiom.thread.spawn[T]`
  compiles on v0.64.3 (the fn-to-ptr cast is accepted) but the runtime
  thread entrypoint AVs (Windows 0xC0000005 / WSL SIGSEGV); the marks
  variant localizes the fault to the worker-entry/join path after
  `spawn` returns (`docs/repro/xv-thread-abi/`; last mark
  `M2: spawn returned`). Acceptance pinned (exact sums + distinct
  worker id, exit 0) + bus witness `REL-20261011-1627-xvector`; re-run
  at the next archive (fn-ABI batch m263-m265 / `fde5548e`). G stays 25
  (blocker sharpened, not moved); no score change (82 %).
- **2026-10-11 (wave-111 closure):** stdlib committed the `str_bytes`/
  `json_parse` fix (`9a2b5ab`, wave 111; committed content == the
  pre-verified WIP hashes). Verified on the committed pin: both repro
  probes exit 0 on Windows AND WSL (str_bytes 43/87/174/379 ms Windows,
  87/177/359/691 ms WSL; sweep 56/110/220/437 ms, 103/206/395/799 ms);
  full batteries green (Windows ALL GATES: suite 177/177 x2 + sbom 42
  modules unsafe=0 + 40 probes x2 + bench smoke; WSL suite 177/177 x2 +
  probes + `probe_json_fast` 228/228 x2); the xvectord 5k x dim-25 fit
  went 120 s -> **51.2 s (98 pts/s)**; quick_bench recall unchanged
  (0.779/0.960/1.000). Acceptance re-pinned: the 500 ms absolute gate
  became a linearity bound (20x ratio + 3 s net) -- the platform spread
  is real post-fix while the scaling is linear on both (pre-fix ratio
  ~34x, now ~7-8x). Bus `-1453`/`-1543` verified + closed. No score
  change (82 %) -- the fix removes a scaling ceiling; the numbers land
  in `docs/BENCHMARKS.md`.
- **2026-10-11 (P2 memory accounting, 75th pass):** shipped
  `engine_memory_estimate` (+ facade `memory_estimate`) and the `/stats`
  `mem_*` fields: per-collection store/graph/payload accounting plus the
  engine-wide WAL estimate, on a documented model (24 B Vec/Str header,
  32 B Vector struct; HNSW rows uniformly allocated -- `adj` =
  nodes*8*m0 Ints -- so deltas are exact). Gate `probe_memory_estimate`
  (17 checks, Windows + WSL); batteries ALL GATES GREEN with **41
  probes** x2 both platforms. `docs/OPERATIONS.md` gains the
  memory-budget section (rules of thumb: ~2.3 KiB/point HNSW m=16
  dim=25; seal/compact triggers). P2's estimate+thresholds half is
  done; budget-cap enforcement stays advisory in the ops docs. No
  scored-phase change (82 %).
- **2026-10-12 (v0.64.4 archive re-verification, 77th pass):** compiler
  v0.64.4 released (tag `df493530`, run `38256358845`; assets
  sha256-verified) and installed lane-local both platforms. Re-verification
  set: **XVC-C-15 VERIFIED FIXED** (repro exit 0, all six shapes; the
  `as Float32` workaround dropped from `probe_quantization` -- 23 checks
  green x2); **phantom imports VERIFIED FIXED** (each control gives exactly
  one clear `unresolved import` error, exit 1 -- the new hard error caught
  stale pre-swap imports in the bench harness + repro evidence copies,
  repaired in `390c7a4`); **C-13** (Win 167 / WSL 63) and **C-14**
  (clang/opt mismatch at `xiominput.ll:850`) re-tested unchanged;
  **thread gate still AVs** (0xC0000005 / SIGSEGV; runtime-side fix
  pending). 19-probe repro sweep + full batteries ALL GATES GREEN both
  platforms (Windows suite 177/177 x2 + sbom 42 modules unsafe=0 + 41
  probes x2 + bench smoke; WSL suite 177/177 x2 + quantization/codec/
  memory probes x2 + strbytes repro). Bus: `-1134`/`-2124` verified +
  closed; thread-gate evidence re-filed (`REL-20261012-1402-xvector`).
  G stays 25 (runtime gate still red, blocker sharpened); no score
  change (82 %).
- **2026-10-12 night (D5 durability delta, 78th pass):** the stdlib
  wave-115 durable-IO drop unblocked D5, and it landed the same night:
  append-only delta segment (`durability.wal_segment`, codec v1 framing,
  byte-linear renderer, tolerant replay with LSN-gap stop, heal-on-open,
  rotation), engine fsync-on-ack (`enable_durable` / `wal_commit` /
  `open_durable`; batch ops commit once per call), the file-level kill
  matrix (child writer + fsynced ack ledger, killed mid-stream:
  **6/6 iterations Windows + 6/6 WSL, zero acknowledged records lost**),
  and the durable server home (`XVECTORD_WAL`: fsync-on-ack serving,
  checkpoint + rotate on quit; restart-verified 400 points, recall
  1.000). Gates: `probe_wal_segment` 38 checks + kill matrix, both wired
  into the CI batteries (42 probes now). **D 74 -> 88; overall 82 % ->
  85 %.** Remaining in D (then): multi-segment read path, retention/
  snapshots (D6), power-loss fault injection.
- **2026-10-13 (D6 retention + snapshots, 79th pass):** `engine_checkpoint_swap`
  (compact -> durable fsync-ordered persist -> segment reset -> frontier
  advance; never resets the segment on failure) + auto-policy
  (`XVECTORD_CHECKPOINT_EVERY`; clean quit always swaps) + snapshot
  export/import (strict meta; multi-collection bit-exact restore; corrupt
  meta refused). Gate `probe_snapshot` 27 checks (swap shrinks churn 451 ->
  251 records; post-swap crash-recovery bit-exact; policy at N commits with
  zero loss; 4000-point snapshot reload **10 ms**). Both batteries green
  (Windows + WSL; suite 177/177 x2 + sbom **44 modules** unsafe=0 + **43
  probes x2** + bench smoke + kill matrix). **D 88 -> 93; overall 85 % ->
  86 %.** Note: a latent XVC-C-14 landmine (legacy `xiom.vector.collection.*`
  wrappers re-declaring AnnParams/AnnIndexKind) was found and annotated --
  do not import that family until the compiler's m278-class fix is in the
  pin (v0.64.5).
- **2026-10-13 night (D7 multi-segment read path, 80th pass):** sealed
  segments became first-class query sources. Roll (`engine_roll_segment`)
  moves the active collection into an immutable segment (register + cache
  + clear; fsync-before-ack; `SegmentSeal` record replays attach+clear);
  every query variant unions active + sealed (tombstones shadow
  deletes-after-seal; the active copy wins over sealed duplicates; the
  `k + tombstones` per-source budget keeps Flat results bit-exact vs brute
  force); delete/delete_by_filter cover sealed-only matches and report
  them as deleted; compaction (`engine_compact_sealed`) merges everything
  bit-exactly and survives restart; recovery loads every registered source
  (`sealed_missing` counts unreadable files -- never silent); the opt-in
  policy auto-rolls at a threshold (`XVECTORD_SEAL_EVERY` + `_DIR`,
  engine-level policy works in-memory too); `/stats` gains
  sealed_segments/sealed_loaded/sealed_missing. Gate `probe_multisegment`
  27 checks; live server verified (policy server: sealed serving, restart,
  counters; stock smoke 7/7 with policy off). A live-only defect was found
  and fixed during the slice: the HTTP request search tail bypassed the
  union (now routed through it, with union hydration). **D 93 -> 95;
  overall 86 % (86.32).** Remaining in D: power-loss fault injection.
  Honesty: whole-file segment loads (no mmap); SQ two-tier deferred to
  Q-a2b; segment paths are caller-owned (a stale file with the same
  cid+seg_id would be adopted).
- **2026-10-15 (81st pass, v0.64.5 archive re-verification):** assets
  sha256-verified + installed lane-local both platforms (win `bd71e2d3`,
  linux `246e5e82`); **the thread gate is GREEN on BOTH platforms** (real
  spawn+join: 3 workers exact sums, worker id != main; marks
  `M3: join ok 42`; was 0xC0000005/SIGSEGV) -- the G phase's blocking gate
  is closed, so **G 25 -> 40** (P2 memory budget and the D5-D7
  seal/checkpoint policies were already in; G-1 sync smoke, G-2
  accept-loop threads, readers/writers and scale tuning remain). C-13 +
  C-14 VERIFIED FIXED on both platforms; C-15 + phantom controls stay
  green; 19-probe repro sweep green; **Windows battery ALL GATES GREEN**
  (suite 177/177 x2 + sbom 44 modules unsafe=0 + 44 probes x2 + bench
  smoke + kill matrix). The **WSL battery went RED on the new XVC-C-16**
  (v0.64.5 linux-x64 HTTP-service `/search` miscompile; A/B: v0.64.4 linux
  + v0.64.5 windows green; repro `docs/repro/xv-http-service-linux/`,
  bus `REL-20261015-2142-xvector`) -- the v0.64.5 re-pin is HELD and the
  linux acceptance stays red until the fix lands. **Overall 86 % (86.32)
  -> 88 % (87.82).**
- **2026-10-16 (G-1 slice, on top of v0.64.5):**
  `tests/probes/probe_thread_sync.xi` joins both batteries as the 45th
  probe: spawn/join acceptance (3 workers exact, worker id != main),
  4-thread mutex-guarded counter = exact 2000, 4-thread atomic counter =
  exact 2000 (Windows 5/5 stress + WSL; suite 177/177 x2 both platforms;
  **Windows battery ALL GATES GREEN: suite x2 + sbom 44 modules unsafe=0 +
  45 probes x2 + bench smoke + kill matrix**). The channel cross-thread
  leg is blocked by the new **XVC-C-17** (imported-type global
  pointer-field drop; `REL-20261015-2216-xvector`; Int-handle workaround
  validated) -- **G stays 40** (G-1 partial; G-2 next). One full-battery
  run carried a transient clang-spawn flake on `probe_wal_file` (`clang
  failed with exit code -1`; retry x2 green; machine healthy -- the clean
  re-run above is the wrap signature).

- **2026-10-18 (G-1 completion, v0.64.7):** `probe_thread_sync` upgraded
  to the natural module-level `SyncMutex`/`AtomicInt` globals (XVC-C-17 fix
  confirmed; the Int-handle workaround is retired) and a cross-thread
  producer/consumer leg (2 real producers x 200 scalar-mailbox handoffs
  under the shared spinlock, exact totals + per-producer FIFO) -- 14 checks
  green x2 both platforms. **XVC-C-19 filed**: v0.64.7 hangs the compiler on
  module-level function-call/allocating `var` initializers (shape-sensitive;
  repro `docs/repro/xv-global-init-hang/`); a channel handle form is wished
  to stdlib so the channel's cross-thread leg can be lock-guarded. G-2
  (accept-loop threads) is next.

## Update rule

Recompute at every wrap: adjust phase scores, recompute the weighted overall,
append a change-log line with the commit and the evidence used. Never raise a
score without naming evidence; never hide a regression -- a red suite or a
new blocker moves the number down.
