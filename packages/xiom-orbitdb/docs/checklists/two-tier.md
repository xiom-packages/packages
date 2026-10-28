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

- [x] **M1.1b pager (2026-10-21)** -- A1-A6: lazy load, bounded clock
      cache, dirty spill, deferred-free GC; **1M soak PASS: 2,494.7 MB
      peak under a 4 GB cap (65,536-frame cache), exact verify**; suite
      166/166 x2 both. Design: `docs/checklists/m1-1b-pager.md`.
- [x] **M3 remainder (2026-10-20)** -- `file_lock` integrated:
      `db_file_open_locked_checked[_cfg]` + `db_file_unlock`/`is_locked`,
      release-or-die, cross-process probe PASS Win+WSL, dbfile suite
      test. Cross-process pins contract: readers live in the owning
      actor / use snapshot copies; version GC in A5.
- [x] **R1/R2 module split merged** -- engine facade + core/btree/snapshot/
      txn modules and the split suite + summing runners landed 2026-10-18
      (`08d351c`-`e04c3b9`; suite 160/160 x2 both at every step; zero
      consumer changes)
- [x] **Threads decision recorded (2026-10-19)** -- engine-actor per
      shard (no DBFile across threads) + process-per-shard scale; runtime
      threads/mutex spike green both platforms (`probe_threads.xi`, 40k
      increments). Note in `docs/ISOLATION.md`.

## Satellite track (product labeling; the engine itself is done per plan)

- [x] README carries the tier label "ORBITDB Satellite (embedded)" +
      Station (2026-10-17); the SPEC / API identity line lands at release
      time (module/package names unchanged: `xiom.db.*`, `xiom.orbitdb`)
- [x] **Canary carve/publish requested** (pre-P-rc): coordination item
      `REL-20261017-1245-orbitdb` filed to the packages lane at freeze pin
      `3bc2a61` (`xiom.orbitdb` v0.2.1, stage incubating; candidate ids +
      scope + P-rc/canary notes + carve-mechanic question). Their
      carve/validate/suite x2/ops-scope/allowlist/batched publish follows;
      the full P-rc recipe + release tag land when the production gate
      passes (owner green-light first)
- [ ] CLI shipped as the satellite front door (`apps/orbitdb_cli.xi` ->
      `out/orbitdb.exe`; WSL twin)

## Admin UI track (owner-approved 2026-10-19, runs alongside, not gated)

- [x] **Pulse web admin phase 1 (2026-10-19):** `admin/` separate app,
      `xiom.pulse` 0.3.1, GET-only dashboard (`/`, `/api/status`,
      `/api/range` pairs, `/api/get`), localhost bind + optional token,
      `X-Pulse-Quit` shutdown; runners `scripts/admin.ps1`/`admin.sh`;
      additive `db_file_range_pairs` API + dbfile 24/24. Smoke green.
- [ ] Pulse web admin phase 2: auth/session + CSRF, query editor, write
      actions (gated on the Station txn model), metrics/logs, ORBITWIRE
      attach at ST1; never public by default. Native SDL3+ImGui later.

## ST0 -- prerequisites (no new code; re-verify the gate)

- [x] **ST1 protocol crawl seeded (2026-10-20)** -- verified h11/
      fastify/gin/knex/bullmq anchors + ORBITWIRE decisions in
      `docs/REFERENCE-MATRIX.md` 3.2; converted 2026-10-21 (ST1 below).

- [x] G-START fully green (2026-10-21): M1.1b A6, M3 shard lock,
      threads decision and R1/R2 all hold with committed evidence.
- [x] Station manifest scaffold `station/xiom.toml` (source-roots `../src` +
      `src`) + a hello-station probe composing the engine (hybrid pattern)

## ST1 -- ORBITWIRE v1 protocol spike (loopback only)

- [x] Wire spec draft in `station/docs/ORBITWIRE.md`: length-prefixed frames,
      text + binary encodings, handshake (protocol version + auth slot),
      request/response ids, error taxonomy mapped from `DbError`
- [x] Ops frozen: HELLO / AUTH / PING / BEGIN / PUT / GET / RANGE / QUERY /
      COMMIT / ABORT / CLOSE (+ additive DELETE / CHECKPOINT) over the
      engine's typed-rows and query APIs
- [x] Loopback conformance suite: round-trip all `TValue` kinds incl. payload
      limits (`db_file_typed_payload_max`) + query/ORDER/LIMIT paths
- [~] Interop with `xiom.postgres.wire` (client-side reference; no PG-wire
      commitment): surface CONFIRMED reusable + documented 2026-10-16
      (`REL-20261016-1150-packages-3`; `xiom.postgres.wire` module: frame
      builders + read primitives + `wire_decode` + SPEC.md tables) -- the
      frame/read-primitive discipline is reused; a co-run item is filed at
      protocol freeze (`REL-20261021-1154-orbitdb`, packages) for a
      read-only fixture probe. ORBITWIRE does not reuse PG's frame format.
- [x] `docs/FORMATS.md` gains the ORBITWIRE v1 section (versioning policy)
- [x] Evidence: station suite x2 Win + x2 WSL (169 checks x2 both); protocol
      KAT pinned in `station/docs/ORBITWIRE.md` + `protocol_suite.xi`

## ST2 -- single-node server core

- [~] `station/src/`: acceptor loop, per-connection session, executor over
      public engine APIs (`db_file_*`) -- **landed in ST1** (server.xi /
      session.xi / dispatch.xi); graceful shutdown on CLOSE/EOF and process
      exit works, an explicit stop flag/signal handler remains.
- [x] Kill-safety: station crash harness `scripts/station_crash_test.{ps1,sh}`
      (kill mid-commit -> restart -> replay -> qverify), mirroring the engine
      harness style (delete-sharing polls; unique `-o` binaries). Client:
      `station/tests/station_crash_client.xi`; port discovery via
      `ORBITDB_STATION_PORT_FILE`.
- [x] Crash harness x2 Win + x2 WSL (**11/11 x2 both**); suite x2 both; zero
      engine files touched (only `station/` + scripts).
- [x] `docs/RUNBOOK.md` station section (run/kill/recover recipes)
- [ ] Session-loop hardening + explicit graceful stop (SIGINT/stop flag) and
      any single-node core gaps before the ST2 gate closes.

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

- [x] **Satellite publication LIVE (canary)**: `xiom.orbitdb` v0.2.1
      published 2026-10-17 in eco-v0.1.196 (sha256 `c8fc6548...`) via the
      packages lane (carve at `3bc2a61`; their suite x2 + crash/probes green
      on the carved layout; our isolated-home consumer smoke green). The
      full P-rc recipe + release tag still land at the production gate.
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
