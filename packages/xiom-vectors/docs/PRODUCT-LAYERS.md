<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# XVECTOR product layers -- naming decision (owner-picked 2026-10-16)

Architecture plan: `docs/PRODUCT-ARCHITECTURE.md`; execution checklist:
`docs/checklists/lattice-v1.md`.

Two tiers of the same product; the upper layer is built ON the lower one.

| Tier | Codename | What it is | Technical identity |
|---|---|---|---|
| 1 -- embedded | **xvector-mote** | the engine in-process: no socket, no daemon; the library every consumer links | registry package `xiom.vectors` (LIVE; backs all vector consumers) + the `src/engine.xi` facade |
| 2 -- scale-out | **xvector-lattice** | the served tier: transport, collections routing, auth/limits/metrics, ops; many single-writer shards coordinated by a stateless router | the `xvectord` daemon + the HTTP service (`http_service_handle` -- already a pure library function; the wire tier only adds listeners) |

## The invariant (this is the product story)

**One engine, one on-disk format, two deployment shapes.** A lattice
shard serves the exact files a mote writes -- same WAL, manifest, segments,
results -- so "develop embedded, deploy served, no migration" holds. Unlike
sqlite-vec -> pgvector (different engines, migratable data), the tiers here
are the same code underneath; that invariant is sacred (no forked format,
no divergent numeric behavior; the shared suite/probes gate both).

## Scale-out model (vector-DB honest version)

- v1 scale-out = **process-level sharding**: N single-writer shards, each
  owning disjoint collections; a stateless router maps collection ->
  home/URL (per-collection routing + self-describing manifests already
  exist; the G-phase harness is the missing piece).
- Sharding one huge collection = **scatter-gather**: per-shard top-k,
  k-way merge; oversample k per shard (2-3x) to protect recall under
  HNSW; filters push down per shard.
- Consistency stays simple: single-writer per shard (WAL-before-ack),
  async replicas via WAL catch-up; no cross-shard transactions needed
  (upserts are last-writer-wins).
- In-process concurrency is deliberately POST-v1 (`XVECTORD_THREADS`
  flag per `docs/G-PHASE-PLAN.md`; G-1 smoke landed 2026-10-16).

## Gaps before "enterprise tier" claims

- TLS nowhere in the ecosystem yet (PULSE headline gap) -- front with an
  edge proxy until the FFI binding lands; auth/scopes/limits are already in.
- Replication + rebalancer: roadmap (not yet designed in-lane).
- Power-loss fault injection still open in D; fsync/fd/mmap primitives now
  real in the stdlib (mmap family wave 120, fsync/fd waves 115-117).

## Release ownership (owner directive 2026-10-16)

- **mote (tier 1, the registry package):** when the package is ready for
  publication, coordination goes through the **packages lane via the
  relay bus** (registry artifacts, sha256, swap/verification gates --
  mirroring the xiom.vectors / xiom.ann flows, owner-gated). The lane
  files/coordinates the relay item when the package is ready; never a
  unilateral publish.
- **lattice (tier 2, the server):** releases ship as an **ops-owned
  GitHub Actions release set** (tag + assets + checksums per the
  ecosystem convention); this lane supplies the version, gate evidence,
  and artifacts, and coordinates with ops via the relay when a release
  candidate is ready.

## Name notes

Chosen for layering semantics: a lattice is an arrangement of nodes; the
mote is the smallest unit. Clear of DB/tool collisions checked at decision
time (atlas=MongoDB, grove=GroveDB, nebula=Nebula Graph, pebble=CockroachDB
engine, ion=Amazon Ion, ember/spark=web frameworks; dot=Graphviz `dot`,
quark=Quarkus, cell=overloaded in programming). Rejected runner-ups:
`xvector-dot`/`xvector-grid`, `xvector-cell`/`xvector-colony`,
`xvector-quark`/`xvector-hadron`.

Technical identifiers stay stable: `xiom.vectors` (package), `xvectord`
(daemon), the home format. The codenames label the tiers in docs, release
notes, and owner-facing material.
