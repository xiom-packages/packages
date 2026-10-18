<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# Requirements -- xiom-xvector Production v1 (flagship)

- **Source:** owner directive 2026-10-09 ("full production-grade vector
  database with XIOM's features; comparable to top modern databases; fast,
  secure; flagship for the ecosystem; benchmark it; public release set up
  like PULSE").
- **Status:** accepted -- this is the requirements intake for the production
  programme. Companion docs: `docs/PRODUCTION-PLAN.md` (milestones/slices),
  `docs/checklists/production-v1.md` (execution checklist),
  `docs/PRODUCTION-READINESS.md` (scorecard).
- **Baseline at intake:** 70 % weighted readiness; suite **169/169 x2**
  (Windows + WSL) + **18 probes x2**; compiler v0.64.2 green; private repo,
  no pushes; signed commits.

## 1. Vision

Make `xiom-xvector` the **flagship production-grade vector database of the
XIOM ecosystem**: a single-node database with embedded + server surfaces
that stands next to Qdrant / Milvus / Weaviate / pgvector-class engines on
the capabilities that matter (durability, filtering, ANN recall, throughput,
operability, security), while proving the whole XIOM stack can ship real
infrastructure: compiler contracts, stdlib, registry packages
(`xiom.wal`, `xiom.vectors`, `xiom.ann`, `xiom.metrics`, `xiom.http`) and
optional FFI bindings.

## 2. Goals (v1.0)

| # | Goal | Success shape |
|---|---|---|
| G1 | Durable single-node database | No acknowledged write lost across kill/crash (fsync-grade when the stdlib gap lands; atomic checkpoint path meanwhile); measured recovery time |
| G2 | Complete query surface | Multi-collection; Flat + HNSW; typed filtering with planner; range search; batch ops; pagination; delete-by-filter |
| G3 | Server + client surfaces | Embedded XIOM facade stays first-class; HTTP JSON service for service consumers and benchmarks |
| G4 | Operable | Metrics (`xiom.metrics`), `/health`, structured logs, config file/env, backup/restore |
| G5 | Secure | Auth, input validation via contracts, resource limits, fuzz/soak gates, SBOM, no user-level unsafe |
| G6 | Fast, honestly measured | In-repo benchmark harness (recall vs oracle, QPS, p50/p95/p99, build time, bytes/vector); published report; benchmark-ready protocol for the owner's suite |
| G7 | Ecosystem proof | Adopt `xiom.wal` when published; porter-extract `xiom.vectors`/`xiom.ann` when owner greenlights; relay stdlib/compiler/bindings needs each pass |
| G8 | Release-ready | CI matrix, docs, release checklist, security checklist, versioned artifacts; owner flips the public release (PULSE-style) |

## 3. Non-goals (v1.0)

- Distribution / sharding / replication (v2 programme).
- Hybrid dense+sparse ranking (v1.1+).
- GPU or external-service dependencies (v2 exploration).
- Billion-scale PQ serving (v2; v1.1 prepares scalar quantization + mmap).
- Non-XIOM client SDKs (owner decides later; HTTP JSON is the contract).

## 4. Personas and surfaces

- **Embedded user** -- imports `xiom.vector.engine`, one process, local
  durability; the primary XIOM-native surface.
- **Service consumer** -- HTTP JSON; the surface benchmarks and other
  languages drive.
- **Operator** -- metrics, health, config, backup/restore, upgrade story.

## 5. Functional requirements

| ID | Requirement | Acceptance evidence |
|---|---|---|
| FR-1 | Multiple named collections: create/drop/list, per-collection dim/metric/index kind/params, persisted | probe + suite mirrors; survives reopen |
| FR-2 | Point lifecycle: upsert/delete/get, batch upsert/delete, delete-by-filter | probes incl. WAL replay of batched ops |
| FR-3 | Search: exact + ANN KNN, filtered (planner), range, batch, pagination, `with_payload` | probes per path; range vs brute force; page-consistency checks |
| FR-4 | Index management: Flat/Hnsw select, params tunable, rebuild/compact, index stats | existing gates + stats probe |
| FR-5 | Payloads: typed values, sorted key index, pre/post planner, compound intersect | existing E-phase gates (100 %) |
| FR-6 | Durability: WAL (memory + file), atomic checkpoints, manifest, segment files, fsync/delta when stdlib lands, snapshots/export-import | kill-matrix probe; format roundtrip; recovery-time measurement |
| FR-7 | HTTP service: collections/points/search/range/delete/stats/health; JSON error model; limits; graceful shutdown | service probe (start, CRUD, search, shutdown) + abuse cases |
| FR-8 | Observability: counters/gauges/histograms, `/health`, `/metrics`, structured logs | metrics probe; documented signals |
| FR-9 | Clients: in-repo XIOM client module + curl-level examples in docs | example scripts green |
| FR-10 | Benchmark harness in-repo: deterministic workloads, JSON + markdown report, dataset importers (fvecs/JSONL/CSV) | one-command run; report committed under `docs/BENCHMARKS.md` |

## 6. Non-functional requirements

| ID | Requirement | Target / gate |
|---|---|---|
| NFR-1 | Crash safety | Kill at any point; no acked write lost on the fsync path; prefix-exact recovery on the checkpoint path; both gated by an automated kill-matrix |
| NFR-2 | Recall | recall@10 >= 0.95 vs exact oracle at default settings on the standard in-repo workloads (already >= 0.99 on current sets) |
| NFR-3 | Latency | p50/p95/p99 per op measured and published; targets set from the first baseline and tracked per release |
| NFR-4 | Throughput | Upsert/search QPS measured and published; no regression > 10 % without a documented reason |
| NFR-5 | Memory | bytes/vector measured; quantization targets set in v1.1 |
| NFR-6 | Security | Auth on by default in service mode; all boundaries validate with contracts/schemas; fuzz + soak gates; SBOM; signed commits |
| NFR-7 | Quality | Every slice: suite x2 + all probes x2 on Windows and WSL; red build = rejection |
| NFR-8 | Operability | One-command start; documented failure modes; backup/restore drill passes |
| NFR-9 | Portability | Windows + Linux/WSL green; no platform divergence (WSL spot every wrap) |
| NFR-10 | Determinism | Same inputs -> identical results across builds/platforms (numeric gates per build) |

## 7. Ecosystem requirements

| ID | Lane | Requirement |
|---|---|---|
| E1 | packages | Adopt `xiom.wal` when published (single WAL home); align the value codec; contribute crash probes. Consume `xiom.metrics` and `xiom.http`; wire `source-roots` (C-PULSE-02) |
| E2 | packages | Porter-extract `xiom.vectors` / `xiom.ann` from this lane when the owner greenlights (gates met) |
| E3 | stdlib | `fsync`/fdatasync, fd write path, `append_file_bytes`, `truncate`/`ftruncate`, `f32_bits`/`bits_to_f32`, `flush_stdout` -- relayed per `docs/STDLIB-WISHLIST-XVECTOR.md`; re-check each pass |
| E4 | compiler | Keep contracts + per-build numeric gates green on v0.64.2+; relay new findings with minimal repros |
| E5 | bindings | SIMD/BLAS behind the portable `xiom.vectors` contract; optional, never required |
| E6 | ops | Package allowlist/scope and registry consumption per the packages lane process |

## 8. Release criteria (the owner-gated public release)

R1. All NFR gates green with committed evidence (batteries, kill-matrix,
benchmark report, security checklist).
R2. Public docs complete: README/quickstart/API reference/ops runbook/
architecture, benchmark methodology.
R3. Release candidate tagged `v1.0.0-rc` with changelog + build-info;
CI matrix green; reproducible artifacts.
R4. Security checklist + SBOM committed; no open high-severity findings.
R5. Benchmark report published and the owner's benchmark can drive the DB.
R6. Owner greenlight: repo public, runners, branch rulesets, release flow
(PULSE-style setup).

## 9. Constraints and assumptions

- C1: stdlib `fsync`/fd/append are still stubs (re-checked 2026-10-09 on
  0.64.3); the whole-file checkpoint + atomic rename path carries
  durability until they land.
- C2: compiler v0.64.2; shape discipline (flat parallel arrays; no
  nested-Vec-of-struct hot shapes) stays until a future archive proves
  otherwise.
- C3: the engine is single-threaded today; concurrency is designed in the
  M-P programme, not assumed.
- C4: private repo, no pushes, signed commits, consumer-lane rules
  (`E:\xiom-lang\*`, `E:\xiom-packages\packages` are read-only).
- C5: pure XIOM + stdlib + registry packages; no external downloads at
  build time.
- C6: only the owner performs public-release actions.

## 10. Traceability

| Milestone (plan) | Requirements covered |
|---|---|
| M-G Truth & measurement | G6, NFR-2..5, FR-10 |
| M-D On-disk durability | G1, FR-1, FR-6, NFR-1, NFR-8 |
| M-Q Query surface | G2, FR-2..5, FR-9(embedded) |
| M-S Server & security | G3, G5, FR-7, NFR-6 |
| M-O Observability & ops | G4, FR-8, NFR-8 |
| M-P Performance & scale | G6, NFR-3..5, FR-4 |
| M-R Release & handoff | G8, R1..R6 |
| M-v2 (later) | distribution, hybrid, deep quantization |
