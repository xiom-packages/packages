<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# xiom-xvector -- Production Plan (v1.0 flagship)

**Purpose:** the execution plan that takes xiom-xvector from a hardened
single-node engine (70 % weighted readiness, suite 169/169 x2 + 18 probes x2
on compiler v0.64.2) to a **production-grade, benchmarkable, releasable
vector database** that serves as the XIOM ecosystem's flagship.

**Companions:** `docs/requirements/production-v1.md` (intake),
`docs/checklists/production-v1.md` (step-by-step checklist),
`docs/PRODUCTION-READINESS.md` (scorecard), `docs/REL*-*.md` (lane relays).

---

## 0. Execution rules (unchanged lane discipline)

1. **One slice at a time.** A slice = one capability + its gates + docs.
2. **Verification contract per slice:** implement; add/extend a probe (and
   suite mirrors where the suite covers it); run suite **x2** + all probes
   **x2** on Windows; WSL spot (full WSL battery at wraps); `ci.ps1` +
   `ci.sh` green; signed conventional commits; docs updated in the same
   step (SPEC/ARCHITECTURE/SESSION/readiness as applicable).
3. **Red = rejection.** Numeric gates per build; rebuild + re-verify.
4. **Externally gated work is not idle work.** While the stdlib fsync chain
   is pending, work the non-gated slices; re-check the lanes each wrap.
5. **Owner gates the public release.** The lane reports when the release
   candidate is ready (R-milestone) and never pushes.

---

## 1. Target architecture (v1.0)

```mermaid
flowchart TB
  subgraph Surfaces
    EMB["Embedded XIOM app<br/>(xiom.vector.engine facade)"]
    CLI["xvector CLI<br/>(bench + admin)"]
    SRV["HTTP JSON service<br/>(xiom.http + auth/limits)"]
  end

  subgraph Engine["Engine (single node)"]
    REG["Collection registry<br/>(multi-collection, manifest-backed)"]
    PLAN["Query planner<br/>filter pre/post + candidates"]
    SRCH["Search service<br/>knn / filtered / range / batch / page"]
    IDX["Indexes<br/>Flat exact | HNSW | (IVF/PQ v1.1)"]
    PAY["Payload store<br/>typed values + sorted key index"]
  end

  subgraph Storage["Storage"]
    SEG["Segments<br/>mutable -> sealed -> compacting"]
    WALF["WAL<br/>in-memory + file checkpoint/delta"]
    MAN["Manifest<br/>collections + segments + LSN"]
    SNAP["Snapshots / export-import"]
  end

  subgraph Platform
    STD["stdlib<br/>io / os / hash / num / contracts"]
    PKG["packages<br/>xiom.wal - xiom.vectors - xiom.ann<br/>xiom.metrics - xiom.http"]
    BIND["bindings (optional)<br/>SIMD / BLAS behind contract"]
  end

  EMB --> REG
  CLI --> REG
  SRV --> REG
  REG --> PLAN --> SRCH --> IDX
  SRCH --> PAY
  REG --> SEG
  SEG --> MAN
  SEG --> WALF
  WALF --> MAN
  SNAP --> SEG
  IDX --> BIND
  SEG --> STD
  WALF --> PKG
  SRV --> PKG
```

**Durability model:** WAL-before-ack; whole-file checkpoints with atomic
temp+rename today; delta append + `fsync` the moment the stdlib rows land;
manifest + segment files versioned and roundtripped; snapshots for backup.

**Index tiering:** exact Flat (oracle + small collections), HNSW (default
ANN), IVF/PQ (v1.1 scale tier). Segment-level immutable indexes with
fan-out + merge.

---

## 2. Capability target vs modern databases (v1.0)

| Capability | v1.0 target | Notes |
|---|---|---|
| Collections | multi, named, per-collection config | FR-1 |
| Metrics | cosine / dot / L2 | done |
| Exact search | Flat KNN + range oracle | range surface pending (Q1) |
| ANN | HNSW (tunable `m`/`ef_construction`/`ef_search`, tombstone-safe) | done, hardened |
| Filtering | typed AST, sorted index, pre/post planner, compound intersect | done (E 100 %) |
| Payloads | typed + `with_payload` hydration + updates/deletes | done |
| Batch / pagination | batch upsert/search, offset/after paging | Q2/Q3 |
| Delete-by-filter | selective delete with WAL + index upkeep | Q4 |
| Durability | WAL + atomic checkpoints + manifest + segments; **fsync-on-ack delta segment (D5, done 2026-10-12)** | M-D | 
| Crash tests | **file-level kill matrix (D5 done: 6/6 Windows + 6/6 WSL)** + prefix-exact model recovery (`probe_kill_recovery`) | M-D5 |
| Server | HTTP JSON + auth + limits + graceful shutdown | M-S |
| Observability | metrics + health + structured logs | M-O |
| Backup | snapshot/export-import | M-D6 |
| Security | authn, validation, limits, fuzz/soak, SBOM | M-S4 |
| Performance | in-memory 1M-scale; SIMD seam; measured p99/QPS | M-P |
| Scale-out | **v2** (sharding/replication); IVF/PQ v1.1 | non-goal v1.0 |
| Hybrid search | **v1.1+** | non-goal v1.0 |

---

## 3. Milestones and slices (ordered)

### M-G -- Truth & measurement (start now; feeds everything)

Goal: every later number is measured, not assumed.

- **G1 reference-oracle cross-check -- DONE 2026-10-09** -- an independent
  in-repo oracle (Float64 reference math + metric identities/axioms:
  symmetry, triangle bounds, self-distance, normalization; randomized
  vectors, deterministic seeds) vs the engine kernels and search paths.
  Gate `probe_reference_oracle` (22 checks; deviations at Float32-ulp
  scale, bit-identical Windows/WSL).
- **G2 benchmark harness** (`bench/`) -- **DONE 2026-10-09**: deterministic
  workloads (ingest, KNN per metric/ef, filtered, range, batch, recovery),
  integer JSON + human report, CI smoke; `scripts/bench.ps1`/`.sh` twins.
- **G3 baseline report** -- **DONE 2026-10-09**: `docs/BENCHMARKS.md` with
  methodology, the n=5000 baseline, WSL spot, and the external-benchmark
  protocol notes; the harness found and fixed the O(L^2) `wal_persist`
  builder.

Exit: oracle probe green both platforms; one-command bench reproducible;
baseline committed.

### M-D -- On-disk durability (in progress; last slice stdlib-gated)

Goal: a kill never costs an acknowledged write on the available path.

- **D1 atomic checkpoint** -- `wal_persist` writes `path.tmp` then
  `io.rename` (available today); fault-injection probe: kill/interrupt
  between write and rename keeps the previous consistent file.
- **D2 manifest file -- DONE 2026-10-09** -- collection registry
  (name/dim/metric/index/params) persisted whole-file + atomic rename;
  load on open; migration fallback for the in-WAL manifest;
  `engine_manifest_save` + `engine_recover_file`/`open_engine`; gate
  `probe_manifest_file` (38 checks).
- **D3 multi-collection runtime + APIs -- DONE 2026-10-09** -- named
  collections (create/select/drop/list), per-collection isolation of
  stores/payloads/indexes, v2 config + v3 drop WAL records with cid-stamped
  data, routed recovery + whole-registry checkpoint; manifest-backed (D2)
  whole-registry `save_manifest`/`open_engine` (file-wins by name). Gate
  `probe_collections` (41 checks); legacy `create_collection` -> "default".
- **D4 segment files -- DONE 2026-10-09** -- sealed segments (vectors +
  payloads + HNSW codec) written whole-file + atomic rename; torn-tail-safe
  load; lifecycle Mutable -> Sealing -> Sealed wired; engine
  `seal_segment`/`restore_segment` (WAL re-checkpoint after restore). Gate
  `probe_segment_file` (38 checks). Multi-segment read path + thresholds
  stay with D5/D6 (P2 owns tuning).
- **D5 WAL delta + fsync + file-level kill test -- DONE 2026-10-12** --
  append-only delta segment (`durability.wal_segment`, `xiom.wal` codec v1
  framing, fsync-on-ack through the stdlib wave-115 primitives) + engine
  `enable_durable`/`wal_commit`/`open_durable`; the whole-file checkpoint
  stays the compaction output with segment rotation on clean shutdown. The
  sibling kill harness (`tests/harness/kill_writer|kill_check` +
  `scripts/kill_matrix.ps1|.sh`) kills a child writer mid-stream and proves
  every acknowledged record survives -- **6/6 iterations on Windows + 6/6 on
  WSL**; the live server flow (`XVECTORD_WAL`, checkpoint + rotate on quit)
  restart-verified (400 pts, recall 1.000). Gates: `probe_wal_segment`
  (38 checks) wired into both CI batteries. **D6 (retention/snapshots)
  follows; truncate-based retention stays stdlib-gated (`-5` acked).**
  Honesty: this is process-kill durability (fsynced bytes survive a killed
  process); power-loss safety still needs OS-level fault injection.
- **D7 multi-segment collection read path -- DONE 2026-10-13** -- sealed
  segments are first-class query sources: `engine_roll_segment` moves the
  active collection into an immutable file (register + cache + clear;
  fsync-before-ack in durable mode), every query variant unions active +
  sealed (tombstones shadow deletes-after-seal, the active copy wins over a
  sealed duplicate, Flat results stay bit-exact via the
  `k + tombstones` per-source budget), compaction merges everything into
  one segment bit-exactly, restart loads every registered source
  (`sealed_missing` counts unreadable files -- never silent), and the
  opt-in policy (`engine_set_seal_policy` / `XVECTORD_SEAL_EVERY` +
  `XVECTORD_SEAL_DIR`) auto-rolls at a threshold. Gates: `probe_multisegment`
  (27 checks) in both CI batteries + live server verification (policy
  server: sealed serving, /stats counters, restart). Honesty: whole-file
  segment loads (no mmap yet); SQ two-tier rescore deferred to Q-a2b.
  **Remaining in M-D: power-loss fault injection only.**

- **D6 retention + snapshots -- DONE 2026-10-13** -- checkpoint compact+swap
  (`engine_checkpoint_swap`: rebase the log to live state, then
  `wal_persist_sync` = write tmp -> fsync tmp -> rename -> dir fsync, and
  ONLY THEN reset the segment + advance the frontier; a failed swap never
  resets the segment, so acknowledged records are never lost) + the
  auto-policy hook (`engine_set_checkpoint_policy` /
  `XVECTORD_CHECKPOINT_EVERY`; clean quit always swaps) + snapshot
  export/import (`durability.snapshot`: ckpt + manifest + strict
  `xvector-snapshot 1 <lsn> <collections>` meta; corrupt/missing meta
  refused; multi-collection bit-exact restore) + the restore drill in
  OPERATIONS. Gate `probe_snapshot` (27 checks; 4000-point snapshot reload
  measured at **10 ms**); retention guidance documented (swap interval,
  snapshot rotation is user-side file rotation). Both batteries green on
  Windows + WSL. **Remaining in M-D: the multi-segment collection read
  path; power-loss fault injection (OS-level; process-kill durability is
  proven).**

Exit: kill-matrix green; recovery time measured; formats versioned and
documented (SPEC); snapshots restore bit-exact stores.

### M-Q -- Query surface complete

Goal: the single-node query surface a modern DB is expected to have.

- **Q1 range search -- DONE 2026-10-09 (exact-first)** -- `search_range`
  engine/facade + `search_range_scan` kernel; exact on both index kinds
  (inclusive radius, distance-sorted, limit-bounded); gate
  `probe_range_search`. ANN widening deferred to M-P tuning; request range
  mode folded into Q6.
- **Q2 batch ops -- DONE 2026-10-09**: `upsert_many` / `delete_many` /
  `search_many` + `BatchHits`; all-or-nothing validation per call; gate
  `probe_batch_ops`. (Records are WAL-appended per point; an amortized
  batch-record format is a D5-era option, not required by the current
  semantics.)
- **Q3 pagination -- DONE 2026-10-09** -- stable `offset`/`after_id` paging
  over sorted hits with the (distance asc, id asc) tie-break documented
  (`query.pagination`; engine/facade `search_page`/`search_after`; exact
  on Flat and Hnsw). Gate `probe_pagination` (22 checks).
- **Q4 delete-by-filter -- DONE 2026-10-09** -- planner-driven selective
  delete (index candidates for Eq/Range/Exists/And-of-those, live-store
  scan for In/Or/Not), WAL-durable per point, graph tombstones, payload +
  index cleanup; ids collected before mutation + applied ascending (plan-
  independent WAL); nothing matching -> Ok(0). Gate `probe_delete_filter`
  (26 checks).
- **Q5 per-collection stats + index admin -- DONE 2026-10-09** --
  `collection_stats` (config, live points, payloads, Hnsw nodes +
  tombstones, shared WAL lsn; active from live fields, parked from
  registry entries) and `rebuild_index` (admin rebuild with
  before/after/reclaimed `IndexStats`; Hnsw fresh graph, Flat no-op;
  `compact_index` stays the Int wrapper). Gate `probe_index_admin`
  (20 checks).
- **Q6 request surface extensions -- DONE 2026-10-09** -- `SearchRequest`
  carries `mode` (knn/range), `radius`, and knn `offset`/`after_id`
  pagination (mutually exclusive; filters Knn-only); `SearchBatchRequest` +
  `HydratedBatch` + `search_batch_with_request` (ordered, all-or-nothing);
  metric/dimension/top_k validation unchanged. Gate `probe_search_request`
  extended to 24 checks.

Exit: probes for every path; suite mirrors where applicable; capability
matrix rows green.

### M-S -- Server & security

Goal: the service surface the ecosystem and benchmarks consume.

- **S1 HTTP service skeleton -- DONE 2026-10-09** -- in-repo
  `api.http_service` (transport-agnostic HTTP/1.1 byte pipeline: strict
  parse, router, stdlib-JSON wire with QUALIFIED `json.json_*` calls,
  byte-exact responses, honest statuses; no sockets until the `xiom.net`
  proof). Endpoints: `/health`, `/collections`, points get/upsert/delete,
  `/search` (knn/range/page/batch), `/stats`. Gate `probe_http_service`
  (40 checks). Config/limits/errors (S2), auth (S3) and the security pass
  (S4) layer on top of this handle.
- **S2 config + limits + errors -- DONE 2026-10-09** -- `ServiceConfig`
  (defaults + `XVECTOR_MAX_*` env + key=value file), enforced limits
  (request size/batch -> 413; named top_k/dim -> 400; boundaries
  accepted), the `{error,kind,status}` JSON model mapped from the full
  `CoreError` enum, and `http_service_shutdown` (drain + whole-file WAL
  checkpoint). Gate `probe_service_limits` (27 checks).
- **S3 auth -- DONE 2026-10-09** -- API keys via `x-api-key` with the
  stdlib constant-time comparator (`xiom.crypto.mac.constant_time_eq`),
  scopes read/write/admin (route map; `/health` public), env loader
  `XVECTOR_API_KEYS`, 401/403 kinds; minimal token-bucket `RateLimiter`
  (429) wired through `ServiceState` + `http_service_handle_state`
  (embedded default off). Gate `probe_service_auth` (24 checks).
- **S4 security pass -- DONE 2026-10-09** -- `docs/SECURITY.md` (threat
  model + secure defaults + threat/control matrix), HTTP fuzz +
  resource-exhaustion gate (`probe_http_fuzz`: 2500 deterministic inputs
  all well-formed; targeted abuse incl. the JSON deep-nesting case that
  found and fixed a stack-overflow DoS via the `json_depth_ok` edge
  guard), SBOM + unsafe gate (`scripts/sbom.ps1`/`sbom.sh` ->
  `out/sbom.json`, 0 unsafe in 43 modules), no-unsafe audit statement,
  dependency-pinning statement (zero registry deps).

Exit: service probe (start -> CRUD -> search -> shutdown) + abuse suite;
auth on by default; SECURITY.md committed.

### M-O -- Observability & operability

- **O1 metrics surface -- DONE 2026-10-09** -- in-repo, dependency-free
  `observability.metrics` (`xiom.metrics` adoption stays Phase 10):
  counters (requests/errors/search/upsert/auth_failures/rate_limited),
  fixed-bucket latency histograms (global + search, p50/p95/p99), live
  gauges (collections/points/lsn). Gate `probe_metrics` (23 checks).
- **O2 surfaces -- DONE 2026-10-09** -- public `GET /metrics` (prometheus
  text), `/health` with `ready:true`, bounded structured JSON log ring +
  slow-query flag, wired through `http_service_handle_state`.
- **O3 runbook & failure modes -- DONE 2026-10-09** -- `docs/OPERATIONS.md`:
  start/stop, config reference, monitoring/alerts, backup/restore drill,
  known failure domains, upgrade/migration notes, quick diagnostics.

Exit: metrics probe; docs complete; ops drill passes.

### M-P -- Performance & scale

- **P1 concurrency design** -- design doc first (XIOM runtime reality):
  target model = process-level single-writer + read-only snapshots, or
  cooperative readers if the runtime permits; explicit consistency notes.
- **P2 memory budget + seal/compaction thresholds** -- bounded memory,
  segment sizing, compaction policy; measured.
- **P3 SIMD/BLAS seam** -- distance kernels behind the `xiom.vectors`
  contract; bindings accelerate when available; benchmark deltas recorded.
- **P4 IVF/PQ prototype** (v1.1 track) -- quantized storage, recall/latency
  curve vs HNSW.
- **P5 mmap/disk segments** (stdlib-dependent) -- tiered storage.

Exit: 1M-vector in-memory workload within published latency/QPS targets;
roadmap to 10M with measured extrapolation.

### M-R -- Release candidate & owner handoff

- **R1** release checklist completion (`docs/RELEASE-CHECKLIST.md`), version
  `1.0.0-rc`, changelog, build-info stamp.
- **R2** CI matrix green (Windows + WSL); reproducible artifacts.
- **R3** benchmark report + methodology; security checklist + SBOM.
- **R4** owner handoff package: setup steps (repo public, runners,
  rulesets, publish flow) mirroring PULSE; **the lane tells the owner it is
  ready before any public action**.

Exit: owner performs the public release; the owner's benchmark can drive
the DB through the documented protocol.

### M-v2 (programme after v1.0)

Distribution (sharding/replication/consistency), hybrid dense+sparse,
deep quantization + tiered storage, client SDKs.

---

## 4. Immediate slice backlog (first 12, ordered)

| # | Slice | Milestone | Gate |
|---|---|---|---|
| 1 | Atomic checkpoint (temp+rename) | D1 | `probe_wal_file` extension + suite x2 + probes x2 |
| 2 | Range search -- **DONE 2026-10-09** (exact-first; ANN widening -> M-P) | Q1 | `probe_range_search` vs brute force |
| 3 | Batch ops -- **DONE 2026-10-09** | Q2 | `probe_batch_ops` (14 checks) |
| 4 | Benchmark harness + baseline | G2/G3 | `bench.ps1/bench.sh` green; `docs/BENCHMARKS.md` committed -- **DONE 2026-10-09** |
| 5 | Manifest file -- **DONE 2026-10-09** | D2 | `probe_manifest_file` (38 checks) |
| 6 | Multi-collection -- **DONE 2026-10-09** | D3/FR-1 | `probe_collections` (41 checks) |
| 7 | Pagination -- **DONE 2026-10-09** | Q3 | `probe_pagination` (22 checks) |
| 8 | Delete-by-filter -- **DONE 2026-10-09** | Q4 | `probe_delete_filter` (26 checks) |
| 8b | Index admin + per-collection stats -- **DONE 2026-10-09** | Q5 | `probe_index_admin` (20 checks) |
| 8c | Request extensions (mode/page/batch) -- **DONE 2026-10-09** | Q6 | `probe_search_request` (24 checks) |
| 9 | Reference oracle -- **DONE 2026-10-09** | G1 | `probe_reference_oracle` (22 checks) |
| 10 | HTTP skeleton + health -- **DONE 2026-10-09** | S1 | `probe_http_service` (40 checks) |
| 11 | Config/limits/errors -- **DONE 2026-10-09** | S2 | `probe_service_limits` (27 checks) |
| 12 | Auth -- **DONE 2026-10-09** | S3 | `probe_service_auth` (24 checks: reject/accept, scopes, rate) |
| 13 | Security pass -- **DONE 2026-10-09** | S4 | `probe_http_fuzz` (14 checks) + sbom/unsafe gate + `docs/SECURITY.md` |
| 14 | Metrics/health/logs -- **DONE 2026-10-09** | O1/O2 | `probe_metrics` (23 checks) |
| 15 | Runbook -- **DONE 2026-10-09** | O3 | `docs/OPERATIONS.md` |

Gated items (D5 fsync chain, P5 mmap, truncate-based retention) are picked
up the moment the stdlib lane lands the primitives; re-check every pass.

---

## 5. Benchmark programme (benchmark-ready for the owner)

- **Harness:** `bench/` runner with deterministic seeds; workloads:
  W1 ingest N vectors (dim configurable), W2 KNN (metric × ef sweep),
  W3 filtered (selective + majority), W4 range, W5 batch, W6 mixed soak,
  W7 kill/recover timing. Output: JSON + markdown tables.
- **Metrics:** QPS, p50/p95/p99, recall@k vs exact oracle on a fixed
  sample, build time, bytes/vector, recovery time.
- **Datasets:** synthetic (LCG) built-in; importers for fvecs / JSONL /
  CSV so the owner's benchmark can feed real data (SIFT1M-class).
- **Protocol for external benches:** stable CLI (`xvector-bench --data ...
  --queries ... --json out.json`) + later the HTTP service; documented in
  `docs/BENCHMARKS.md` with methodology and hardware notes.
- **Honesty rule:** every published number names the workload, dataset,
  parameters, platform, compiler/stdlib versions.

## 6. Security programme

- **Auth & transport:** API keys (scopes, constant-time compare); TLS
  documented per deployment (bindings/stdlib dependent); secure defaults.
- **Validation:** every boundary (HTTP, facade) validates dims/k/batch/
  filter shapes via contracts; malformed inputs rejected with typed errors.
- **Resource safety:** request size, connection, batch, and memory caps;
  slow-query logging; no unbounded scans without limits.
- **Robustness:** fuzz gates (codecs, HTTP), soak, kill-matrix; every
  `Some`/`Ok` invariant checked in probes.
- **Supply chain:** pinned stdlib/packages, SBOM, signed commits,
  no secrets in-repo, release artifacts stamped.
- **XIOM safety story:** product code has no user-level `unsafe`;
  contracts encode invariants; document the guarantee in SECURITY.md.

## 7. Ecosystem integration map

| Ecosystem piece | How the flagship uses it | Lane action |
|---|---|---|
| compiler contracts | invariants on entry points; per-build numeric gates | relay findings; keep probes pinned |
| stdlib | io/os/hash/num; the durability primitives gate M-D5 | wishlist relays per pass |
| `xiom.wal` | single WAL home; codec alignment; crash probes contributed | adopt on publish (ops allowlist) |
| `xiom.vectors` / `xiom.ann` | porter extraction of this lane's reference implementation | on owner greenlight |
| `xiom.metrics` | O1 observability | adopt Phase 10 (now) |
| `xiom.http` / `xiom.router` / `xiom.rate` | server surface | adopt at S1/S3; fallback in-repo |
| bindings (blas/eigen) | optional SIMD acceleration behind the contract | watch; never required |

## 8. Risks and external gates

| Risk / gate | Impact | Mitigation |
|---|---|---|
| stdlib fsync/fd/append still stubs on 0.64.3 | D5 (true durability), truncate retention, KV/manifest backends | atomic checkpoint path ships now; re-check each pass; relay pressure; `xiom.wal` shares the gate |
| `xiom.http`/`xiom.metrics` maturity | S1/O1 may need in-repo fallback | facade-first design; adopt when the package proves itself |
| XIOM runtime concurrency model | P1 limits throughput story | design first; process-level model; publish honest numbers |
| compiler regressions on new archives | red builds | per-build numeric gates; re-test at every archive before pinning |
| benchmark fairness | credibility | publish methodology + raw JSON; deterministic seeds |
| single-lane bandwidth | long timeline | strict slice cadence; owner gates release only |
| security surface of a young HTTP stack | exposure | secure defaults, auth on, threat model, fuzz gates before release |

## 9. Definition of "public release ready" (what the lane delivers)

1. Suite + probes green x2 on Windows and WSL through `ci.ps1`/`ci.sh`.
2. Kill-matrix + snapshot/restore evidence committed.
3. Benchmark report (`docs/BENCHMARKS.md`) with methodology + raw JSON.
4. Security checklist + SBOM + `docs/SECURITY.md`.
5. Docs complete (README/quickstart/API/OPERATIONS/ARCHITECTURE) and
   release checklist filled; `VERSION` = `1.0.0-rc`.
6. Release candidate tagged; owner handoff note (repo/runners/rulesets/
   benchmark setup) -- **the lane stops and tells the owner**.

## 10. Cadence and reporting

- Work proceeds autonomously slice-by-slice under the lane's goal loop;
  each slice is committed signed with its probes/docs.
- Every wrap: SESSION.md STATE refreshed, readiness re-scored, lanes
  re-checked, relays updated.
- The lane reports to the owner at: (a) each milestone exit,
  (b) any new external gate, (c) the release-ready gate (R4).
