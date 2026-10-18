<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# xiom-xvector v1.0.0-rc.1 -- release notes (draft; public release is the owner's action)

**Status:** release candidate, prepared 2026-10-09. The repository stays
private until the owner greenlights; nothing in this document authorizes a
push.

## What this is

`xiom.xvector` is a production-grade XIOM vector database: dense-vector
storage with exact Flat search and a hardened HNSW index, WAL-backed
durability with a durable collection registry and sealed segment files, a
typed payload/filter surface, multi-collection routing, and a
transport-agnostic HTTP service with config, limits, auth, rate limiting,
observability, and security gates.

## Highlights since the programme kickoff (v0.1.0-dev)

- **Durability (M-D).** Atomic WAL checkpoints (temp+rename, M-D1), a
  durable collection registry file (M-D2), multi-collection registries with
  routed recovery and whole-registry checkpointing (M-D3), and sealed
  segment files with engine seal/restore and WAL re-checkpoint (M-D4).
  Kill-recovery prefix exactness and torn-tail prefix loaders are gated by
  probes.
- **Query surface (M-Q).** Exact range search (Q1), batch upsert/search/
  delete (Q2), stable offset and after-id pagination over the
  (distance, id) total order (Q3), planner-driven delete-by-filter (Q4),
  per-collection stats + admin rebuild (Q5), and SearchRequest extensions
  (knn/range modes, pagination, batches — Q6).
- **Benchmark + oracle (M-G).** A bench harness with a committed baseline
  (`docs/BENCHMARKS.md`; bench smoke in every battery) and an independent
  Float64 reference oracle cross-checking kernels, metric axioms and all
  ranked/paged/cursor/range/HNSW paths (deviations at Float32-ulp scale).
- **Service (M-S).** A byte-level HTTP/1.1 pipeline (`/health`,
  `/collections`, points CRUD, `/search`, `/stats`), config + limits +
  `{error,kind,status}` model, API-key auth (constant-time, scopes) +
  token-bucket rate limiting, and the security pass: a 2500-input fuzz
  gate, a JSON depth guard that fixed a found remote stack-exhaustion DoS,
  SBOM + unsafe gates wired into CI, and `docs/SECURITY.md`.
- **Observability (M-O).** Latency histograms, service counters, live
  gauges, public prometheus-style `GET /metrics`, `/health` readiness, a
  bounded structured JSON log ring, and the `docs/OPERATIONS.md` runbook.

## Verification evidence (at this candidate)

- Full batteries on **Windows and WSL**: conformance suite 171/171 x2 +
  SBOM/unsafe gate + **32 probes x2** + bench smoke -- ALL GATES GREEN.
- **Kill matrix**: `probe_kill_recovery` (prefix exactness across upserts,
  deletes, payloads, checkpoints, torn tails).
- **Benchmark report**: `docs/BENCHMARKS.md` (+ `probe_reference_oracle`
  kernel fidelity).
- **Security checklist**: `docs/SECURITY.md` (threat model, secure
  defaults, no-unsafe audit) + `docs/sbom-v1.0.0-rc.1.json`.
- **Repro bundles**: all primary probes re-run at compiler v0.64.2 --
  9 green; `contract-trap-exit0` exits 1 (the fixed symptom);
  `xv-str-ref-param` remains red by design (open finding **XVC-C-13**,
  `&Str` parameters mislower to i64; lane convention is `Str` by value,
  so the shipped code is unaffected).

## Known limitations (honest)

- **fsync gap**: `wal_persist` is atomic but not fsync-grade until the
  stdlib fsync chain lands (D5/D6 gated); machine-crash durability is
  bounded accordingly.
- No network socket yet: the HTTP module is transport-agnostic
  (C-PULSE-02 gated); TLS/proxy concerns are deployment-side.
- No encryption at rest; single-threaded engine (concurrency is M-P
  territory); `xiom.metrics` adoption is a later phase (in-repo metrics
  today).
- One open compiler finding (XVC-C-13) with a lane-level workaround;
  compiler lane is pinned at v0.64.2 / tag c51170a6.

## Upgrade / compatibility

On-disk formats are versioned (`xvector-wal 1` with v1/v2/v3 manifest
families, `xvector-manifest 1`, `xvector-segment 1`); the loaders accept
older records and reject unknown headers as invalid. No breaking API
changes relative to the v1.0 programme documents.
