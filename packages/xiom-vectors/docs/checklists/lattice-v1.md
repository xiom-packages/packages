<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# Checklist -- lattice v1 (mote / lattice scale-out)

Execution checklist for `docs/PRODUCT-ARCHITECTURE.md` (plan) and
`docs/PRODUCT-LAYERS.md` (naming decision). Pattern for every slice:
implement -> probe/suite gates -> **suite x2 + probes x2 (Windows) + WSL
spot** -> docs (SESSION/readiness/OPERATIONS as needed) -> signed commit.
Consumer lane; repo private; findings bus-routed.

## L-0 -- naming + plan (DONE)

- [x] naming decision recorded (owner-picked 2026-10-16):
  `xvector-mote` (embedded) / `xvector-lattice` (scale-out) --
  `docs/PRODUCT-LAYERS.md`
- [x] architecture plan + this checklist (2026-10-16) --
  `docs/PRODUCT-ARCHITECTURE.md`

## L-1 -- mote polish (embedded tier)

- [x] quickstart doc (`docs/MOTE-QUICKSTART.md`): open a home in-process,
  create collection, upsert, search, reopen; embedding via `xiom.vectors`
  **(done 2026-10-16)**
- [x] embedded round-trip probe in `tests/probes/`
  (`probe_mote_embedded`, the 46th probe; in both battery lists)
  **(done 2026-10-16)** -- it immediately caught the **cid-collision
  regression**: creating a collection after a reopen reused a recovered
  cid, so the next recovery's last-wins manifest merge silently dropped
  the earlier collection; fixed in `engine_recover_registry`
  (`eng.next_collection = max(cid)+1`), suite 177/177 x2 after the fix
- [ ] `mote` CLI stub (open/search/bench) -- optional, only if it earns
  its keep; gate: the same round-trip via CLI exits 0
- Gate: probe x2 both platforms; suite x2; docs. **WSL legs HELD
  2026-10-16 on the stdlib wave-146 POSIX build break**
  (`REL-20261016-1143-xvector`: runtime `TCP_NODELAY` missing
  `<netinet/tcp.h>`), re-run when stdlib fixes it.

## L-2 -- collection move primitive (the rebalancing unit)

- [x] offline primitive **(done 2026-10-16)**: `export_collection`
  (durable roll -> ONE segment artifact; refuses unknown/empty/
  already-rolled collections) + `attach_segment` (installs points +
  payloads + index config into the freshly created collection; no cid
  requirement; integrity footer REQUIRED). The portable unit is the
  segment file itself (self-contained: meta + vectors + payloads +
  graph + SQ codes). No half-attach possible: the destination registry
  entry appears only when the verified artifact is installed.
- [x] segment-codec integrity footer: every persisted segment appends
  `z <count> <crc32>`; old loaders ignore it (prefix semantics
  unchanged, `probe_segment_file`/`probe_snapshot`/`probe_multisegment`/
  `probe_quantization` all re-green); attach refuses missing/mismatched
  footers (truncated, corrupted, and pre-L-2 copies).
- [x] `probe_collection_move` (47th probe, both battery lists; done
  2026-10-16): export refusals; truncated/footer-less copies REFUSED;
  good attach bit-exact (search {1,2} + distances + HNSW config travels
  m=8/ef_search=16); dst persist + reopen; docs + extra both survive
  (cid freshness); src drop + reopen consistent. Evidence: probe x2 +
  suite 177/177 x2 on Windows AND WSL; full Windows battery green (see
  the wrap commit).
- Reference (study 04): redb savepoints as the freeze model; bbolt's
  exclusive-open lock as the fail-fast guard. Hardening candidates:
  checksummed manifest entry + a `recovery_required` bit so a
  half-attached registry is caught on open; checkpoint salt rotation
  (sqlite) to prevent old/new frame mixing.
- [x] L-5 extension: compaction-aware moves (collections that already
  have sealed segments) + the drain operation + move-under-load gate
  **(landed 2026-10-16 in L-5; move/drain are admin ROUTES while the
  router is the in-process library -- the standalone CLI ships with the
  socket transport)**
- Gate: probe x2 + suite x2 + WSL spot **(done)**;
  `docs/OPERATIONS.md` move section **(done -- section 9 + the
  interrupted-copy failure row + the format note)**

## L-3 -- router v1 (stateless)

- [x] mapping file schema + loader (versioned JSON:
  `{version, shards[], collections{}}`; refuse start on malformed)
  **(done 2026-10-16)**: `src/api/router.xi` -- strict loader (missing/
  garbage/bad ids/urls/duplicate shards/unknown refs -> `ok=false`,
  requests 503); byte-level read + `file_size` guard; placement is
  EXPLICIT (unmapped names -> 404)
- [x] router service: forward by collection; `/health`, `/version`,
  aggregate `/stats` (admin scope); shards keep their own endpoints
  **(done)**: forwards VERBATIM (client key included; shards re-check
  independently -- defense in depth); router-owned `/health` + `/version`
  (both surface `mapping_version`) + `/cluster/mapping` + `/cluster/stats`
  (admin; a bare `/stats` with no collection is the same aggregate);
  in-process transport v1 -- the socket hop waits on the `xiom.http`
  client half (`REL-20261016-1129-xvector-2`)
- [x] stale-mapping behavior: on shard 404, re-read mapping + retry once
  **(done)**: a NEW generation is accepted only when every referenced
  shard has a local context (otherwise refused, cache kept); retries once
  only when the owner changed
- [x] `probe_router_2shards`: create/upsert/get/search/delete/stats
  through the router == direct to the owning shard; unknown collection ->
  404; mapping-version surfacing **(done)**: 72 checks -- loader refusal
  matrix, byte-equal wire comparisons vs the owner shard, wrong-shard
  isolation, REAL move + retry-on-404 (v1 -> v2), reload refusal, auth
  matrix (router + shard), aggregate honesty; probe x2 green Windows
- [x] routing fuzz (bad paths/collection names/mapping edge cases)
  **(done -- inside the probe)**: 14 fuzz checks (paths/methods/framing/
  bodies/oversize/hostile names), all well-formed statuses
- Gate: probes x2 + suite x2 + WSL spot; docs. **Windows done (probe 72/72
  x2 + service-family probes x2 + suite 177/177 x2); WSL spot HELD
  2026-10-16 (owner resource guidance -- other lanes hold the machine --
  AND C-16 would red the search legs until v0.64.6; run both together in
  the re-pin pass)**
- Note: **XVC-C-18 filed during this slice** (JSON object-key reads
  through a `match` binding return garbage; repro
  `docs/repro/xv-object-key-iter/`, bus `REL-20261016-1541-xvector`;
  copy-out workaround shipped). P1-P6 re-check at L-3: format identity is
  re-exercised via the L-2 artifact in the move section; the
  served-home variant re-runs with the socket transport.

## L-4 -- replica v1 (async catch-up, manual promotion)

- [x] design: pin the catch-up shape against actual WAL records
  (frontier/sequence); fallback = snapshot + tail replay **(done
  2026-10-16)**: FILE-ship catch-up -- byte copies of the leader
  checkpoint (size-change gated) + delta segment into the follower home;
  the loader's checkpoint-dedupe merge is the "apply with checkpoint
  skip" rule; shipped-frontier watermark in `<follower_ckpt>.ack`. (A
  first records-replay cut was abandoned: `engine_recover` renumbers the
  log above the file, which broke the merge cursor -- see the fix note.)
- [x] follower mode (read-only; applies WAL; lag metric + /stats field)
  **(done)**: `src/api/replica.xi` (`replica_ship`, `replica_lag_estimate`);
  lag rides `ServiceState.replica_lag` -> `/stats` `replica_lag` +
  `xvector_replica_lag` gauge
- [x] manual promotion runbook: stop writer -> replay to frontier -> flip
  mapping (version bump) **(done)**: OPERATIONS section 12; the probe
  walks the full runbook incl. the stale-router retry onto the promoted
  home (byte-equal)
- [x] kill matrix with replica: acked writes survive writer kill AFTER
  promotion; lag returns to 0 under steady state **(done -- in-process)**:
  `probe_replica` (50th; reopen sweeps 1..30 + 101..103; 5 post-promotion
  writes survive a files-only reopen; three steady write+ship rounds end
  at lag 0). The OS-level replica kill matrix (process level, live tail)
  rides the socket transport.
- Gate: kill matrix both platforms + probes x2; `docs/OPERATIONS.md`.
  **Windows done (51 probes x2 + suite + FULL BATTERY ALL GATES GREEN);
  WSL spot HELD (owner resource guidance; fold into the v0.64.6 pass)**
- Found+fixed during the slice: **durable reopen-then-write loss** --
  `engine_enable_durable` set the frontier to `max(segment file,
  in-memory log)`; after a reopen the recovered log is renumbered ABOVE
  the file, so the first commit appended past the never-persisted
  renumbered block and the next merge stopped at the gap (post-reopen
  writes lost). Fix: the segment file is the durable frontier; the first
  commit re-sends the block. Regression line `probe_reopen_write` (51st
  probe); `probe_wal_segment`'s frontier expectation updated to the
  durable-truth relation.

## L-5 -- drain / rebalance + cluster ops

- [x] admin: `POST /cluster/move`, drain node (move its collections off;
  no new placement), mapping version bump **(done 2026-10-16)**: the move
  = compaction-aware export -> destination create + attach -> source drop
  -> mapping flip + atomic persist (version bump; a failed persist
  reinstalls the source from the artifact); drain = round-robin move of
  every owned collection (first failure reported; a single-shard cluster
  refuses 400); no standalone CLI yet (the admin route IS the operation
  while the router is the in-process library)
- [x] `probe_move_under_load`: no acked write lost; the client-visible
  retry window bounded and documented **(done)**: 41 checks -- 20
  pre-move + 10 post-flip acked writes with a 30-id destination sweep,
  stale observer == exactly one reload + one retry, sealed+active merge
  exactness (10-point union), sealed-only move, drain (repoint + empty
  source), admin fuzz + read-key scope
- [x] cluster templates sketch (systemd/docker; edge proxy for TLS) +
  OPERATIONS cluster section **(done)**: OPERATIONS section 11 (+ the
  section 9 limits note; templates activate with the socket transport)
- Gate: probe x2 + suite x2; docs. **Windows done (probe 41/41 x2 +
  affected probes x2 + suite 177/177 x2 + full battery); WSL spot HELD
  (owner resource guidance; fold into the v0.64.6 re-pin pass)**

## L-6 -- intra-collection scatter-gather (phase B)

- [ ] design decision recorded: range vs hash sharding (rationale)
- [ ] router fan-out + k-way ranked merge (distance asc, id asc) +
  `offset`/`after_id` applied AFTER the merge; oversampling knob
- [ ] strict mode default; partial mode opt-in with `"partial": true`
- [ ] `probe_scatter_gather`: Flat exactness vs single-node ground truth
  (equal result sets), HNSW recall bound vs the gate, filtered pushdown
  oversampling measurement, pagination semantics. **The gate must name
  the recall definition per arm** (reference study 04): VectorDBBench
  uses ID-set recall; ann-benchmarks uses distance-threshold recall
  (epsilon ~1e-3, can credit wrong IDs inside the band)
- Gate: probes x2 both platforms + suite x2; BENCHMARKS note

## G-2 -- in-process concurrency (parallel track)

- [ ] per `docs/G-PHASE-PLAN.md` (`XVECTORD_THREADS` flag; coarse mutex;
  its own gate list). Orthogonal to T2; unblocked by the compiler fixes.

## Cross-cutting

- [ ] **Homes/replicas on shared/network filesystems are unsupported**
  (ops rule; sqlite documents WAL as unsafe on network FS -- reference
  study 04): local disks only, document in OPERATIONS at L-5
- [ ] **mote registry publication (when the package is ready):**
  coordinate with the **packages lane via the relay bus** (item + sha256
  + swap/verification gates, owner-gated) -- never a unilateral publish
- [ ] **lattice releases:** the **ops-owned GitHub Actions release set**
  (tag + assets + checksums); this lane supplies version + artifacts +
  gate evidence per release
- [ ] SESSION section 0/1 + READINESS updated per slice
- [ ] every platform blocker bus-routed the moment it bites
- [ ] P1-P6 invariant checks stay explicit: format identity (a
  mote-written home opens served and vice versa) is probed at L-2 and
  re-checked at L-3+

## Reference

`docs/REFERENCE-STUDY-04-LATTICE.md` (2026-10-16): bbolt (open-lock
modes + batch coalescing), redb (publish-last header, savepoints,
recovery ladder), sqlite/sqlite-vec (reader-frontier snapshot, salt
rotation, embedded UX), ann-benchmarks + VectorDBBench (gate
methodology), zstd (stream frames). Port-candidate table + traps inside.
