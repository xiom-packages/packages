<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# Checklist -- ORBITDB two-tier track (Satellite + Station)

> Companion to `docs/TWO-TIER-ARCHITECTURE.md` (the strategy) and
> `docs/PRODUCTION-PLAN.md` (the plan of record, section 15). The Station
> (`station/`) consumes the Satellite engine (`src/`) as a library; it never
> forks it and never blocks the embedded release.
> Convention: `[x]` done with committed evidence; `[~]` in progress/blocked
> with a named dependency; `[ ]` not started. Every station step inherits the
> lane discipline: suites x2 both platforms, crash harnesses x2 both,
> probe-logs gitignored, signed conventional commits, docs coupled.
> Reference protocol (2026-10-17): every station step starts with a crawl
> recorded in `docs/REFERENCE-MATRIX.md` section 3 (h11/fastify/gin/knex/
> bullmq rows); blockers go through the bus and re-test on the next
> release/publish.

## Gate G-START -- Station work may begin only when ALL of these hold

- [~] **M1.1b pager** -- lazy node load + bounded cache + deferred-free
      allocator over `read_at`/`write_at` (task order #3; the keystone for
      both tiers)
- [~] **M3 remainder** -- multi-process advisory locks (`file_lock`),
      cross-process pin semantics, version GC tied to compaction
- [~] **R1/R2 module split merged** -- engine_core / btree / snapshot+pins /
      txn / db (move-only; suite x2 both at every step; zero consumer
      changes); this freezes the substrate boundary the Station consumes
- [ ] **Threads decision recorded** -- runtime threads (wave 139) vs
      process-per-shard for station concurrency; one-page note in
      `docs/ISOLATION.md`

## Satellite track (product labeling; the engine itself is done per plan)

- [ ] README / SPEC / API gain the tier label "ORBITDB Satellite (embedded)"
      at release time (module/package names unchanged: `xiom.db.*`,
      `xiom.orbitdb`)
- [ ] Registry P-rc recipe + `xiom.orbitdb` scope ask when the P-rc gates
      pass (production checklist owns the gate; owner green-light first)
- [ ] **At publication: open the relay item to the packages lane** for
      publishing coordination (packaging assist: scope ask, P-rc recipe,
      canary; ops owns the allowlist gate) -- owner directive 2026-10-16
- [ ] CLI shipped as the satellite front door (`apps/orbitdb_cli.xi` ->
      `out/orbitdb.exe`; WSL twin)

## ST0 -- prerequisites (no new code; re-verify the gate)

- [ ] G-START fully green with committed evidence
- [ ] Station manifest scaffold `station/xiom.toml` (source-roots `../src` +
      `src`) + a hello-station probe composing the engine (hybrid pattern)

## ST1 -- ORBITWIRE v1 protocol spike (loopback only)

- [ ] Wire spec draft in `station/docs/ORBITWIRE.md`: length-prefixed frames,
      text + binary encodings, handshake (protocol version + auth slot),
      request/response ids, error taxonomy mapped from `DbError`
- [ ] Ops frozen: HELLO / AUTH / PREPARE / EXECUTE / FETCH / CLOSE / PING
      over the engine's typed-rows and query APIs
- [ ] Loopback conformance suite: round-trip all `TValue` kinds incl.
      payload limits (`db_file_typed_payload_max`) + query/ORDER/LIMIT paths
- [ ] Interop with `xiom.postgres.wire` (client-side reference; no PG-wire
      commitment): surface CONFIRMED reusable + documented 2026-10-16
      (`REL-20261016-1150-packages-3`; `xiom.postgres.wire` module: frame
      builders + read primitives + `wire_decode` + SPEC.md tables) -- file
      the co-run item at protocol freeze (loopback, read-only fixture side)
- [ ] `docs/FORMATS.md` gains the ORBITWIRE v1 section (versioning policy)
- [ ] Evidence: station suite x2 Win + x2 WSL; protocol KAT file committed

## ST2 -- single-node server core

- [ ] `station/src/`: acceptor loop, per-connection session, executor over
      public engine APIs (`db_file_*`), graceful shutdown + handle discipline
- [ ] Kill-safety: station crash harness `scripts/station_crash_test.{ps1,sh}`
      (kill mid-commit -> restart -> replay -> qverify), mirroring the engine
      harness style (delete-sharing polls; unique `-o` binaries)
- [ ] Crash harness x2 Win + x2 WSL; suite x2 both; zero engine files touched
- [ ] `docs/RUNBOOK.md` station section (run/kill/recover recipes)

## ST3 -- concurrency (readers + writer path)

- [ ] Reader snapshots via engine pins; single-writer commit path (WAL append
      is the serialization point)
- [ ] Decision spike outcome: thread-per-connection vs process-per-shard
      (bounded by the ST0 pager cache) -- recorded in `docs/ISOLATION.md`
- [ ] Mixed reader/writer session harness under churn (model-checked
      visibility: a session never sees uncommitted rows)
- [ ] Evidence: harness x2 both; no regression on engine suite x2 both

## ST4 -- replication (WAL shipping + snapshot bootstrap)

- [ ] Engine-surface (additive, public): WAL segment transfer + apply API
      (import records since ack-LSN; replica replay into tree)
- [ ] Snapshot bootstrap: checkpoint + compact at generation G; binary-safe
      transfer of `.snap` + WAL tail (OS copy / `byte_io` byte loops ONLY --
      never the text copy path); replica resumes at `checkpoint_lsn`
- [ ] Replica read mode + promotion: epoch file + `file_lock` guard;
      documented zero-loss boundary = synced seams only
- [ ] Replication harness: primary kill -> promote -> verify; lag metric
- [ ] Evidence: harness x2 both; engine suite still green x2 both
- [ ] ST4 fit (packages 2026-10-16, `REL-20261016-1150-packages-3`):
      **LOCAL log leg on `xiom.durable`** -- LSN single-writer, read-from-LSN
      (`wal_read_from`) as the at-least-once cursor, checkpoint-gated
      retention, crash-consistent recovery; **our thin ship loop** owns
      transfer + cursor/acks. Caveat recorded: durable's `wal_flush` is still
      an honest no-op (no power-loss durability) -- the engine WAL remains
      the power-loss-honest path; durable carries only the transfer log.

## ST5 -- sharding (manual catalog, range routing)

- [ ] Shard catalog stored in an engine DB (dogfooding); range map + routing
      key resolution
- [ ] Scatter-gather reads with pinned ORDER/LIMIT merge semantics
      (documented in `station/docs/SHARDING.md`)
- [ ] Manual rebalance: target shard snapshot transfer + tail catch-up +
      cutover with epoch guard
- [ ] Cluster harness (2-4 local shards): write/read matrix, kill during
      rebalance, catalog corruption rejection
- [ ] Evidence: harness x2 both

## ST6 -- operations

- [ ] Minimal auth: users file (salted hashed secrets), AUTH op enforcement,
      local-trust mode documented for loopback/dev
- [ ] TLS when `xiom.ssl` (bindings, build STARTED 2026-10-16: client+server
      contexts, cert/key/chain, ALPN, verify modes; first publish waits on
      the ops registry scope) -- until then: trusted-network/local only,
      clearly documented
- [ ] Backup/restore drills: online snapshot + WAL tail transfer, restore to
      a fresh station, `qverify` after restore
- [ ] Metrics endpoint: `xiom.otel` 0.1.0 green (span/resource + OTLP JSON,
      parked at the ops scope gate); **gauges = scoped 0.2.0 increment for
      ST6** (replication lag LSN, sessions, per-shard sizes); connection
      limits + timeouts
- [ ] Evidence: ops drill log committed (probe-logs style summaries)

## ST7 -- scale and league

- [ ] BENCH-1 harness extended to station ops (same YCSB-ish mix, fair fsync)
- [ ] Cross-engine numbers published: station vs PostgreSQL on identical
      hardware/ops; honest caveats (same style as the embedded bench rows)
- [ ] Failover drill + multi-hour soak on the cluster harness
- [ ] `docs/PRODUCTION-READINESS.md` gains the station scoreboard section

## Optional (post-ST7, evaluated -- not a commitment)

- [ ] **ST8 PG-wire facade** -- accept PostgreSQL's wire protocol for free
      tooling; validate against `xiom.postgres` and stock clients; only if
      the value justifies the surface

## Release engineering (both tiers; owner directives 2026-10-16)

- [ ] **Satellite publication**: relay item to the packages lane at
      publication time (packaging coordination; ops allowlist gate)
- [ ] **Station releases**: GitHub Actions pipeline authored WITH ops --
      this lane delivers the build/battery/soak contracts + pinned-toolchain
      recipe; ops owns the pipeline

## Cross-cutting rules (non-negotiable for every station step)

- Station calls only public engine APIs (`docs/API.md`); engine changes are
  additive and land with engine suite x2 both.
- No ack before the synced WAL seam; shipped LSN <= last synced LSN.
- Binary artifacts move via OS copy / `byte_io` byte loops only.
- Wire format changes are versioned (`docs/FORMATS.md` policy).
- The embedded release path (P-rc gates) always outranks station work.
