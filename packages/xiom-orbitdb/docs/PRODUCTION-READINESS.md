<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# ORBITDB -- Production-Readiness Tracking

> Single source of truth for "how close to production grade". ROADMAP.md is the
> phase plan; THIS file is the scoreboard; `docs/PRODUCTION-PLAN.md` is the
> strategy and gates. Every score change must cite
> evidence that exists in the repo (suite/probe/soak/crash harness) and be
> committed in the same change that earns it.

## Honesty rules

1. **No green without evidence.** An item scores only when implemented AND
   proven: conformance test or probe run x2 (Windows + WSL), a soak for
   long-running paths, or the crash harness for durability paths. Scaffolds
   and in-memory stand-ins score 0 unless the row says otherwise.
2. **No silent failures.** Anything that can corrupt or drop data must fail
   loudly or refuse (`tuple_encode_checked`, strict decode, checksum verify).
3. **Durability claims are literal.** "Durable" today = OS write-back +
   torn-tail healing; power-loss durability requires fsync (stdlib row) and
   is scored at 0 until then.
4. **Scores are weighted areas; sub-item points are additive.** Partial work
   can take partial points only where the row defines a fraction.
5. **Recompute on every wrap.** Add a dated line to the scoreboard changelog.

## Current scoreboard -- 2026-10-11 (v0.64.3 pin)

| Area | Weight | Earned | Status summary |
|---|---|---|---|
| A. Correctness & data structures | 20 | 16.0 | B-tree churn-proven orders 3-6 (order-3 empty-chain fix 2026-10-10); tuple codec v1 KAT-locked; FSM best-fit model-soaked; node-per-page durable pages done, paged access pending |
| B. Durability & crash safety | 20 | 18.0 | Disk WAL segment + page file + engine WAL-before-ack + incremental generation-committed checkpoint crash-proven; **real fsync wired end-to-end (M1.2 S4 / M2.1 second half): commit acks, checkpoint pre-sync, rename durability (temp sync + fsync_dir); O(1) tail healing; fault-gated (syncfail latches); power-loss honesty up to the synced seams** (lane runtime until the re-vendor pin); power-loss/torn-page matrix on real hardware still pending |
| C. Storage engine (pages/pager) | 15 | 11.0 | Codec + checksum + FSM + durable page file + clock replacer/pinning done; pager substrate pending |
| D. Transactions & isolation | 10 | 7.0 | Durable transactions: begin/commit/abort + committed/uncommitted recovery crash-proven; savepoints + in-process snapshot pins (MVCC minimal subset, M3.1) with COW writes + compaction refusal; multi-process/GC pending |
| E. Query & schema | 10 | 7.0 | Value-filter query + DBFile bindings + key-range planner pushdown (point/range plans, bounds-aware estimate, property-pinned) + secondary index (build/maintenance/IndexValue plan) + ORDER/LIMIT; typed values + durable index storage pending |
| F. Operations & tooling | 10 | 4.0 | ps1/sh runners, crash harness, probes; no CI/packaging/version stamp |
| G. Performance & limits | 5 | 3.0 | Benchmarks published (v0.64.1); WAL segment size policy live (`maybe_checkpoint`); replay constrained by the filed stdlib `str_split` quadratic; page/cache bounds pending |
| H. Security & integrity | 5 | 4.5 | Checksums + full input validation + deterministic fuzz harness; encryption/supply-chain pinning pending |
| I. Documentation & evidence | 5 | 5.0 | Full doc set + relay docs + repro bundles + public API/runbook/format reference |
| **Total** | **100** | **77.5** | **~78% -- alpha-track, durable log + pages + checkpoints + REAL fsync (S4) + transactions + savepoints/snapshot pins (M3 minimal) + planner pushdown + secondary index + ORDER/LIMIT + clock replacer + typed rows + fuzz, benchmarks live, both WAL/B-tree packages registry-live** |

Scoreboard changelog:
- 2026-10-08: bootstrap complete (suite migrated, engine defects fixed, WAL
  crash harness, B-tree delete churn-proven, CRC32C, tuple codec v1): 39.5.
- 2026-10-08: free-space map hardened (best-fit + clamping + invariants,
  50k-op model soak) and locked in the suite: 43.5.
- 2026-10-08: durable page file v1 (CRC32C verify, atomic rewrite, crash
  harness x2 Win + WSL) -> C2 5 pts; page-level torn detection credited
  partially -> B6 2/4: 50.5.
- 2026-10-08: engine on the disk WAL -- `DBFile` WAL-before-ack +
  replay recovery, `db_crash_test` x2 Win + WSL + 200-key soak -> B4 4 pts
  (also surfaced and worked around compiler finding C-ORBIT-04): 54.5.
- 2026-10-08: benchmark harness (`bench.{ps1,sh}`) + numbers -> G1 2 pts;
  the bench caught the stdlib `str_split`/`read_file_lines` quadratic (filed)
  and drove the WAL append heal-state fix (626 -> 2,946 ops/s Windows,
  26k ops/s WSL native fs): 56.5.
- 2026-10-08: checkpoint/snapshot landed -- node page codec (B-tree -> page
  file), atomic snapshot install, Checkpoint anchor + keep-anchor truncate,
  `db_file_open` = snapshot + tail replay; suite 106/106 x2 Win + WSL,
  `db_crash_test` checkpoint scenarios (snapshot-only + snapshot/tail) x2 Win
  + WSL, 2000-key soak (9 checkpoints). B2 evidence upgraded smoke ->
  crash-proven (no score change; B2 was already credited at 2/2): 56.5.
- 2026-10-08: DBFile query/range API -- `db_file_query`/`db_file_range` mirror
  `db_query`/`db_range` (value semantics, key-range) on the recovered tree;
  `qverify` query-after-recovery checks in all three crash scenarios; suite
  107/107 x2 Win + WSL, db_crash 15/15 x2 Win + WSL. E1 evidence upgraded
  (no score change; E1 already credited): 56.5.
- 2026-10-08: incremental generation-committed checkpoints -- page log +
  header-last commit + generation resolution + compaction; `maybe_checkpoint`
  policy; suite 111/111 x2 Win + WSL, db_crash 15/15 x2, WAL/page crash x2,
  2000-key policy soak (9 checkpoints) x2. Also surfaced, worked around, and
  filed **C-ORBIT-05** (nested `Vec[Struct-with-Vec]` loop + push aborts
  v0.64.1) with a repro bundle. G2 0.5 -> 1.0 (segment policy): 57.0.
- 2026-10-08: checkpoint compaction covered -- 70 no-op checkpoints drive the
  log past node_count + 64, the next checkpoint rewrites one version per page
  atomically, and writes/checkpoints continue afterwards; suite 112/112 x2
  Win + WSL. No score change (B2 evidence): 57.0.
- 2026-10-08: durable transactions (D2) -- WAL Begin/Commit/Abort kinds,
  DBFile txn API (log-then-buffer, apply at commit, abort discards), recovery
  applies committed windows / drops unterminated ones and finalizes a dangling
  window with an Abort record; guards: checkpoint and auto-commit rejected
  mid-txn. Crash scenarios D/E (uncommitted discarded, committed recovered)
  25/25 x2 Win + WSL; suite 115/115 x2. D2 4 pts -> D area 5.0: 61.0.
- 2026-10-09: buffer-pool replacer + pinning (C4) -- direct-mapped slots
  replaced by an associative frame table with clock (second-chance) eviction,
  per-frame pin counts, all-pinned rejection, and hits/misses/evictions/
  rejects stats (no Vec[Option] element writes). Suite clock-order + pinning
  tests; suite 117/117 x2 Win + WSL; page/WAL crash x2 + soak. C4 3 pts ->
  C area 11.0: 64.0.
- 2026-10-09: fuzz/property harness (H3) -- deterministic seeded fuzz of the
  tuple codec, WAL parser, page log and B-tree vs model, with runners; x2 Win
  + WSL; suite 117/117 x2 both. H3 1 pt.
- 2026-10-09: public API reference + operations runbook + versioned format
  spec (I3), linked from the README doc index. I3 1 pt -> I area 5.0; H area
  4.0: 66.0.
- 2026-10-09: input validation completed (H2) -- `db_path_valid` +
  `db_file_open_checked` with Err(ConstraintViolation) on bad path/order;
  suite 117 -> 119, x2 Win + WSL; db_crash 25/25 x2 both as regression. H2
  0.5 -> 1.0 (H area 4.5): 66.5.
- 2026-10-09: v0.64.2 re-test -- all five C-ORBIT findings RESOLVED
  (m223/m224/m225/m226/m235); the compiler workarounds are dropped
  (`6f6c3ba`) and the lane is green on the native forms: suite 120/120 x2
  Win + WSL, db_crash 25/25 x2, WAL/page crash x2, fuzz OK, 2000-key soak
  OK; all seven repro bundles green unchanged. Stdlib rows 1-2 resolved
  upstream (linear `str_split`/`read_file_lines` + CR stripping, citing our
  relay): 20k-record WAL replay 61.6 s -> 9.9 s. No score change: 66.5.
- 2026-10-09: production plan published (`docs/PRODUCTION-PLAN.md` +
  `docs/checklists/production-release.md`): workstreams M1-M8, gates
  P-alpha -> 1.0, benchmark targets, release signal for the owner's public
  setup. No score change: 66.5.
- 2026-10-09: consumer integration handshakes published -- PULSE
  (`docs/PULSE-INTEGRATION.md`: embedding API + snippets, pin `ef872b0`,
  platform matrix, crash semantics, conformance proposal, cross-asks) and
  XVECTOR (`docs/XVECTOR-INTEGRATION.md`: row-first hybrid contract; relay
  archived). No score change: 66.5.
- 2026-10-09: M1.1 storage spine -- NodeStore dirty tracking + dirty-only
  checkpoint flush (full-write fallbacks for a missing prior snapshot or an
  uncommitted crashed generation); suite 120 -> 121 (bounded-delta test),
  x2 Win + WSL; db/WAL/page crash x2, fuzz + 2000-key soak green.
  No score change (A5/G2 stay WIP until lazy load + bounded cache): 66.5.
- 2026-10-09: key-range planner pushdown (M4.1) -- `query_key_range` additive
  bounds; point/range/full plan selection with bounds-aware `estimated_rows`;
  `execute_plan` scans the index range then applies value conditions/offset/
  limit; `db_file_query` planned. Suite 121 -> 123 (plan kinds + 200-case
  seeded property vs brute force), x2 Win + WSL; db_crash 25/25, fuzz + soak
  green. App-build helper with `--icon assets/orbitdb.ico` verified. E2
  3 pts -> E area 6.0: 69.5.
- 2026-10-09: isolation decision + multi-handle stale-write guard -- 
  `docs/ISOLATION.md` (single-writer, open-time snapshot, MVCC deferred with 
  prerequisites); every write path (`put`/`delete`/`txn_*`/`checkpoint`) 
  refuses when the WAL changed since this handle's last write (`wal_bytes`; 
  no lock files); suite 119 -> 120 x2 Win + WSL, db_crash 25/25 x2, fuzz OK. 
  No score change (D3 WIP; MVCC engine pending): 66.5.
- 2026-10-10: hybrid ORBITDB <-> XVECTOR consumer probe + cross-store crash
  harness (M6.0 step 2) -- `tests/hybrid/probe_hybrid.xi` (source-level
  composition via `tests/hybrid/xiom.toml`; 36-check in-process acceptance:
  ingest, crash-between state, delete pipeline, repair pass, join integrity,
  top-k edges, dim/dup, reopen bit-equality, payloads, WAL prefix + torn
  tail) and `scripts/hybrid_crash_test.{ps1,sh}` (writer drives both stores,
  hard kill, torn row tail, reopen + repair + 100% join integrity; second
  verify idempotent). GREEN x2 Win + WSL; suite 123/123 x2 both. Consumer
  finding **XV-ORBITDB-01** filed (chained persist/load goes empty; probe
  carries a documented re-LSN workaround). The composition exposed a dead
  `xiom.core.error` fold in `src/error.xi` (phantom import silently
  accepted) -> retired the fold + `CoreConfig` projection, filed
  **C-ORBIT-06** with a repro bundle, docs coupled. No score change (F2/I2
  already OK; the hybrid harness extends the existing crash-harness class):
  69.5.
- 2026-10-10 (same day, registry sweep): first ORBITDB consumer pass on a
  registry package -- `xiom.wal` 0.1.0 (eco-v0.1.121; the stand-alone
  extraction of our WAL) via `tests/pkg/probe_pkg_wal.xi`: 18 checks GREEN
  x2 Windows + WSL including two-way format interop with `src/wal_file.xi`
  and byte-level codec v1 parity. Importing the package next to our module
  re-exposed the m225 twin-enum caveat cross-package (T001 until
  `src/wal_file.xi` variants were re-qualified); filed in the package
  wishlist delta. Suite 123/123 x2 both platforms; WAL crash harness x2
  both. No score change (F4 evidence; publish gates unchanged): 69.5.
- 2026-10-10 (same day, M1.2 design): byte-page format v2 design published
  (`docs/BYTE-PAGE-FORMAT-V2.md`; checklist `docs/checklists/byte-page-v2.md`):
  4096-byte blocks, 32-byte header (magic/kind/generation/page_id/len/CRC32C),
  two generation-stamped header slots, block store over a six-function
  byte-IO shim with documented O(file) fallbacks, v1->v2 migration,
  KAT/corruption/fuzz matrix; S1 (pure codec) unblocked, S2-S4 per the
  checklist. No score change (A5/C2 stay WIP until implementation evidence
  lands): 69.5.
- 2026-10-10 (same day, M1.2 S1): byte-page v2 codec landed --
  `src/storage/block.xi` (pure: 4096-byte blocks, 40-byte header with 8-byte
  LE slots, payload capacity 4056, CRC32C over payload, strict decode,
  header `committed_generation` cross-check, free-block fast path) + 4 suite
  tests (layout KAT, roundtrip/boundaries, corruption matrix, header slot);
  suite **127/127 x2 Win + WSL**; API.md storage section documents the
  module. No score change (A5/C2 evidence groundwork; the store itself is
  S2): 69.5.
- 2026-10-10 (same day, package relay + order-3 fix): the packages lane
  confirmed `xiom.wal` 0.1.0 **and `xiom.btree` 0.1.0 registry-live**; fixed
  the upstream **order-3 B-tree defect** their extraction documented
  (SPEC 2.3): keyless pass-through chains (min_keys == 0) broke
  `get_predecessor`/`get_successor` (OOB `keys[-1]` materializing garbage),
  `fill_child` (merge reading past the children array) and
  `btree_min`/`btree_max` (None on empty terminal leaf); suite regression
  from their reproducer (order 3 / keyspace 16 / seed 777), fuzz rotation
  now orders 3/4/5. Evidence: suite 128/128 x2 Win + WSL, fuzz x2 both,
  churn order 3 @ 20k/4096 seeds 777+2026 GREEN (+ orders 4/5 regression).
  **F4 1 -> 2** (both extraction packages live; xiom.wal consumer pass
  green; xiom.db publish + version stamp pending): 69.5 -> **70.5**.
- 2026-10-10 (same day, M1.2 S2): byte-IO shim (`src/storage/byte_io.xi`:
  read_at/write_at/append/file_size/truncate/sync, documented O(file)
  fallbacks, sync no-op) + block store (`src/storage/block_store.xi`:
  append-only 4096-byte blocks, two generation-stamped header slots with
  first-commit mirroring, scan directory with `gen <= committed` filter and
  latest-wins, temp+rename compaction) + probe `probe_block_store.xi`
  (26 checks: commit semantics, uncommitted-hidden-on-reopen, torn tail
  skipped, torn active-slot fallback, both-slots recovery, surviving-page
  re-commit, compaction, capacity) + crash harness
  `scripts/block_crash_test.{ps1,sh}` (four kill states: pages2 / full2 /
  midheader / compacted; torn tail + recovery append) + fuzz section (f)
  block store vs model. GREEN x2 Win + WSL; suite 128/128 x2 both.
  No score change (A5/C2 stay WIP -- the pager seam and the default flip
  are S3/S4; this is the groundwork evidence): 70.5.
- 2026-10-10 (same day, M1.2 S3 integration): the DBFile snapshot can be
  written as v2 byte blocks -- `db_file_open_cfg` / `db_file_open_checked_cfg`
  (`page_format` 1 default | 2), first-byte auto-detect on reads,
  `snap_flush_v2` (dirty-only append + header commit; a v1 file is rewritten
  whole = migration-on-write), v1-handle-on-v2-file flip via `snap_compact`,
  idempotent `db_file_migrate_snapshot`; suite **130/130 x2 Win + WSL**;
  **db_crash matrix 25/25 x2 both platforms in v2 mode**. Default stays v1
  (the flip moves to S4: a single first full checkpoint at N=2000 is
  minutes-scale on the O(file) shim). No score change (A5/C2 groundwork):
  70.5.
- 2026-10-10 (same day, compiler v0.64.3 bump): release-check processed
  (pin `ab894b47`); Windows pin moved to the shadow install `xiom.new.0643`
  (canonical left for the fleet). Bump battery GREEN: seven C-ORBIT bundles
  unchanged and matching the v0.64.2 matrix; suite 130/130 x2 Win + WSL;
  WAL crash 4/4 x2 both; db_crash 25/25 Win; block crash 8/8 Win; fuzz +
  2000-key soak on both platforms. Release-check row `-2` verdict filed
  (still open: same T001 class at 1206/1211/1216); C-ORBIT-06 with-twin
  STILL red on v0.64.3 (correction `REL-20261010-1802-orbitdb`). No score
  change: 70.5.
- 2026-10-10 (same day, M4.2): secondary indexes + ORDER/LIMIT --
  `src/secondary_index.xi` ((value, pk) sorted entries, binary-search
  probes, stable pair sorts), maintained by put/update/delete/txn-commit;
  `db_file_create_index`/`_drop`/`_index_range`/`_create_index_from_def`
  (catalog `IndexDef` tie-in, value column 0, non-unique); planner gains
  `IndexValue` (first usable condition bounds the probe; key bounds keep
  precedence) with an executor that re-filters all conditions and honors
  order/offset/limit; `query_order` (0 key asc, 1 value asc, 2 value desc;
  ties key-stable; ordering before offset/limit). Suite **134/134 x2 Win +
  WSL** (4 new tests), fuzz section (g) vs brute-force model x2 both.
  **E3 0 -> 1** (functional index + catalog tie-in + fuzz; durable
  page-backed storage still gated on A5): 70.5 -> **71.5**.
- 2026-10-11 (reference study): owner-granted reference sandbox (`E:\repos`)
  -- cloned and studied bbolt (MIT), redb (MIT/Apache-2.0) and SQLite
  (public domain, read-only); `docs/REFERENCE-STUDY.md` distills their
  load-bearing mechanisms (commit-marker discipline, checksum chains,
  two-slot headers, pending-frees by generation, snapshot/savepoint subset,
  PASSIVE checkpoint backfill accounting, durability modes, buffered-write
  fault injection) into adopt/adapt/avoid decisions per slice with an
  ordered next-action list (M2.1 durability API + `byte_io` fault injector
  first). No score change (practice/evidence, not shipped capability):
  71.5.
- 2026-10-11 (M2.1 first half -- evidence): the durability API + fault
  injector completed and pinned by evidence -- 2 suite tests (durability
  defaults/setters + reopen reset; syncfail latch with reopen recovery) and
  `tests/probes/probe_fault_sync.xi` (49 checks: put/delete latch,
  checkpoint-2PC pre-sync failure with the snapshot file untouched + the WAL
  untruncated, block-store torn page append/update + torn header-slot
  fallback through the env fault layer). Suite **136/136 x2 Win + WSL**,
  probe GREEN x2 both, fuzz OK x2 both. Found and filed **C-ORBIT-07**
  (consumer fn silently hijacks a module-private same-named call; bundle
  `docs/repro/consumer-fn-hijack/`, bus `REL-20261011-1124-orbitdb`;
  workaround: distinct helper name). No score change (B5/B6 stay gated on
  the stdlib fsync row; the API is pinned so the swap is behavior-only):
  71.5.
- 2026-10-11 (M5.1 codec): typed values v2 landed at the codec layer --
  `TValue` (null/int/float/text/blob) + tuple codec version 2 (tagged
  fields, u32 lengths, strict whole-buffer decode, bit-exact f64 incl. NaN,
  byte-exact UTF-8 text) in `src/storage/tuple.xi`; 4 suite tests (byte KAT,
  roundtrip/all kinds, reject matrix incl. cross-version isolation, budget)
  + fuzz section (h); FORMATS 5A (model + migration notes); suite
  **140/140** + fuzz OK on v0.64.3. Two v0.64.3 codegen traps found en
  route (fixed in our code, noted in-line: a tuple containing an enum --
  `Result[(TValue, Int)]` -- miscompiles as `Tuple__TValue__Int`; fixed
  byte-cast sign-extension needs `& 0xFF`). No score change (E4 stays
  unshipped until engine rows store/query typed values): 71.5.
- 2026-10-11 (M5.2 schema layer + container decision): `schema_row`
  (ColumnType<->TValue mapping incl. the bool 0/1 domain, nullability,
  arity, pk-is-VInt, id/pk consistency, consumer-safe error codes) in
  `src/catalog/schema_row.xi`; 4 suite tests (**144/144**) + fuzz section
  (i) (random schemas/rows vs model + every single-column violation must be
  rejected); `column_type_code` keeps enum matching out of consumers (m225/
  C-ORBIT-07 hygiene); the engine persistence contract is recorded in
  **`docs/TYPED-VALUES-STORAGE.md`** (entry payloads in the nodes; WAL rides
  the existing tagged records with subtype 1; snapshot node pages v3).
  No score change (E4 still unshipped until rows persist/query): 71.5.
- 2026-10-11 (user shell v0, owner ask): `apps/orbitdb_cli.xi` builds to
  `out/orbitdb.exe` (icon embedded) / `out/orbitdb-cli` (WSL) -- interactive
  REPL (put/get/del/range/count/ckpt/bench/info/recover/kill); `kill` exits
  without cleanup and the restart completes WAL replay (verified as a user
  flow on both platforms, bench 2000 puts ~1.1k ops/s). README "Try it"
  section + RUNBOOK row. No score change (tooling surface, not engine
  capability): 71.5.
- 2026-10-11 (M5.3 typed rows in the engine): payloads ride the tree
  (parallel `BTreeNode.payloads`), the WAL (existing tagged records,
  subtype 1), and BOTH snapshot containers (node page version 2 with a
  payload section; v1 pages decode with empty payloads). API:
  `db_file_put_typed`/`db_file_get_typed` + `db_file_typed_payload_max`
  (byte-validated, budget-refused, non-transactional in S3). Evidence:
  suite **149/149 x2 Win + WSL** (5 new tests incl. crafted txn windows),
  fuzz section (j) (random typed mixes with per-op verification across
  checkpoints/reopens), fault scenario E (typed latch + payload recovery),
  and legacy-artifact verification (pre-change v1-node-page snapshots load
  unchanged; a 2994-row store survives write + migration-on-write). **E4
  awarded 2/2** (typed values + column constraints now stored and
  readable end to end; typed-column query/index predicates are S4):
  71.5 -> **73.5**.
- 2026-10-11 (M5-S4 typed predicates): `tuple2_compare` total order
  (Null < numeric < Text < Blob; int/float coercion; NaN first/self-equal)
  + `TypedQuery`/`TypedCond` + `db_file_query_typed` (matching pks in key
  order; `col = -1` = row id; int rows/undecodable payloads never match;
  offset/limit on matches); suite x3 (152 total) + fuzz (k) vs an
  INDEPENDENT model (4 seeds x 150 iters, per-op verification across
  checkpoints/reopens); CLI `qrow`. No score change (extends the awarded
  E4 evidence; typed secondary indexes remain a follow-on): 73.5.
- 2026-10-11 (M3.1 -- MVCC minimal subset: snapshot pins + savepoints): the
  first M3 slice landed (`docs/MVCC.md`). Pins capture `{root, lsn,
  generation}` over the node arena; while pins exist every write path
  copy-on-writes the nodes it touches (birth epochs + `cow_shadow`;
  `node_deep_copy` after finding **C-ORBIT-09** -- element assignment through
  a copied Vec handle aliases the source, bundle `docs/repro/vec-copy-alias/`),
  so pinned views never change; snapshot reads via
  `db_file_snapshot_get/_typed/_range/_count`; checkpoint compaction defers
  while pinned (`compaction_deferred`) and `db_file_min_pinned_lsn` is the
  M1.1b deferred-free hook; txn-scoped savepoints trim the buffer and splice
  the WAL window (Abort + Begin + re-log). Evidence: 7 suite tests (**159/159
  x2 Win + WSL**), `probe_mvcc.xi` 36 checks GREEN x2 both (three pins over
  600 ops + two checkpoints; forced compaction deferral with 81 checkpoints
  and post-release shrink; savepoint matrix C1-C5; typed pins), fuzz section
  (l) OK x2 both, db_crash 25/25 x2 both. **D3 WIP -> 2/4** (in-process pins
  + savepoints crash-proven; multi-process locks, pager-backed lazy reads and
  version GC remain): 73.5 -> **75.5**.
- 2026-10-12 (v0.64.4 verdict wave): official artifacts pinned (Windows
  shadow `xiom.new.0644` sha256 44a41aea...; WSL canonical sha256
  d0a43a5c...). Battery re-run: suite 159/159 x2 Win + WSL, db_crash 25/25
  x2 both, fuzz both, fault probe GREEN x2 both with the C-ORBIT-07
  workaround reverted (original collision shape). C-ORBIT-06/07 verified
  fixed + closed; C-ORBIT-08/09 unchanged (bundles); **C-ORBIT-10** (Linux
  `--check` always exits 0) and **C-ORBIT-11** (same-named types across
  modules break co-composition) filed with bundles. xiom.btree 0.1.1
  two-way consumer pass GREEN (digest-equal engine companion, both
  platforms; item closed). Production-requirements relay posted per lane
  (`REL-20261012-1945-orbitdb` + `-2`/`-3`). No score change (evidence
  depth, no new row gates): 75.5.
- 2026-10-12 (doorbell 21:00Z -- dependency unlock): stdlib wave 115
  (`c65acb5`) landed real fsync + byte random-access + held append handle +
  truncate + `fsync_dir` on the lane runtime; our rows `-3..-6` verified +
  closed via `tests/probes/probe_io_primitives.xi` (GREEN x2 Win + x2 WSL,
  `XIOM_RUNTIME_DIR` override on v0.64.4 until the re-vendor pin). M1.2 S4 +
  the M2.1 second half are now actionable (score moves when they land);
  still pending upstream: P4 `file_lock`, P5 leftovers. No score change:
  75.5.
- 2026-10-13 (M1.2 S4 + M2.1 second half -- the byte-IO/fsync swap): the
  O(file) fallbacks are gone. `byte_io` now rides the real primitives
  (`io.read_at/write_at/append_file_bytes/file_size/truncate_file` + REAL
  `sync_io.sync_fd` + `fsync_dir`); `wal_file_flush`/`page_file_sync` are
  real; tail healing is O(1) (`file_last_byte` + `append_line_sync`); every
  rename publish (WAL truncate, page write/batch, block-store compact) syncs
  the temp before and the directory after; **v2 byte container is the
  DEFAULT** (`db_file_open`), v1 stays readable + writable via
  `db_file_open_cfg(...,1)` and migrates on the next default-open
  checkpoint. Harness hardening en route: every runner invokes the compiler
  with a UNIQUE `-o` binary after a DrvFs ETXTBSY race (seven harness pairs
  patched). Evidence: suite **160/160 x2 Win + x2 WSL** (new default-flip
  test), db_crash **25/25 x2 both** (real fsync paths), probe_mvcc + fault
  probe GREEN, fuzz OK both, fresh bench (Win wal_append 2.1k/s, WSL
  36.8k/s -- fsync-honest). **B 16.0 -> 18.0** (fsync second half +
  rename durability + O(1) healing; power-loss matrix on real hardware still
  pending): 75.5 -> **77.5**.

## A. Correctness & data structures (20)

| # | Item | Pts | Status | Evidence / gate |
|---|---|---|---|---|
| A1 | B-tree insert/search/delete/range/min/max/to_vec | 4 | OK | suite + `probe_core_diag` |
| A2 | B-tree delete borrow/merge invariants (all key counts valid, uniform leaf depth) | 4 | OK | `probe_btree_churn` structural validator; 20k ops x orders 3/4/5/6 + seed matrix (order-3 empty-chain regime fixed 2026-10-10: predecessor/successor OOB, fill_child merge, min/max; reproducer order 3 / keyspace 16 / seed 777) |
| A3 | Byte-packed tuple codec with strict decode + budget | 4 | OK | `probe_tuple_codec` KAT/extremes/rejects; suite 99/99 |
| A4 | Free-space map hardening (best-fit, invariants, model soak) | 4 | OK | `probe_fsm` (use/release/find vs model, invariant checks, 50k ops x 256 pages) + suite best-fit/clamp tests |
| A5 | Node-per-page B-tree | 4 | WIP | durable node pages + incremental generation-committed flush (snapshot path); live tree still fully resident -- paged/evicting access needs the pager seam |
| | *Partial credit:* CRC32C integrity aids A3/A5 | +0 | -- | counted in B |

## B. Durability & crash safety (20)

| # | Item | Pts | Status | Evidence / gate |
|---|---|---|---|---|
| B1 | Append-only WAL segment: append, replay, torn-tail heal, LSN resume | 4 | OK | `probe_wal_file` + `scripts/crash_test.{ps1,sh}` x2 Win + WSL; 200-record soak |
| B2 | WAL checkpoint/truncate seam | 2 | OK | `db_file_checkpoint`: **incremental** generation-committed snapshot (changed nodes only, header-last commit, uncommitted-generation ignored on load, compaction at node_count+64) + Checkpoint anchor + `wal_file_truncate` keep >= anchor; `db_file_maybe_checkpoint(limit)` policy; suite crash-state tests (no-op delta, uncommitted generation, torn-tail heal, compaction); `db_crash_test.{ps1,sh}` scenarios B/C x2 Win + WSL; 2000-key policy soak (9 checkpoints) x2 Win + WSL |
| B3 | CRC32C page integrity (KAT-locked) | 2 | OK | `probe_crc32c` x2 + suite KAT |
| B4 | Engine wired to the disk WAL (WAL-before-ack on real files) | 4 | OK | `DBFile` facade: `db_file_put/delete` append then apply; `db_file_open` replays; `db_crash_test.{ps1,sh}` GREEN x2 Win + WSL + 200-key soak; suite roundtrip |
| B5 | fsync/durable flush on commit (`wal_file_flush` is honest no-op) | 4 | 0 | blocked: stdlib fsync row (STDLIB-WISHLIST-ORBITDB.md #1). The durability API (normal/immediate modes, 2PC checkpoint ordering, failed latch) is pinned and probe-tested so the swap is behavior-only (`probe_fault_sync`, M2.1 first half) |
| B6 | Torn-page detection on read + crash matrix (page-level) | 4 | 2 | checksum reject + `page_crash_test.{ps1,sh}` GREEN x2 Win + WSL; v2 block-store torn-tail + partial-write recovery via the env fault layer (`probe_fault_sync` section D; torn append/update invisible on reopen, torn header slot falls back); power-loss leg still blocked on fsync |
| | *Partial:* B1+B2+B3 = 8/20, B6 = 2/4 | | | |

## C. Storage engine (pages/pager) (15)

| # | Item | Pts | Status | Evidence / gate |
|---|---|---|---|---|
| C1 | Page type + CRC32C + in-memory buffer pool | 3 | OK | suite page/buffer_pool tests (with C-ORBIT-02/04 workarounds) |
| C2 | Durable page file (page read/write/verify on disk) | 5 | OK | `probe_page_file` + `scripts/page_crash_test.{ps1,sh}` x2 Win + WSL (kill -> torn -> verify N -> upsert -> N+1); suite roundtrip/corruption tests |
| C3 | Pager integration (`xiom.core.storage.pager` substrate) | 4 | 0 | externally blocked: registry source-roots (C-PULSE-02) / substrate availability |
| C4 | Buffer-pool replacement policy + pinning semantics | 3 | OK | clock (second-chance) frame table: associative lookup, reference bits, pin counts (pinned frames never evicted; all-pinned `put` rejected with `rejects++`), bounded two-sweep victim search; get-side hits/misses + evictions; suite clock-order and pinning tests x2 Win + WSL |

## D. Transactions & isolation (10)

| # | Item | Pts | Status | Evidence / gate |
|---|---|---|---|---|
| D1 | Txn state machine (active/committed/aborted, op list) | 2 | OK (state only) | suite txn tests |
| D2 | Crash-safe redo/undo with committed/uncommitted classification | 4 | OK | WAL BeginTxn/CommitTxn/AbortTxn (codes 8/9/10) + `db_file_txn_*` (log as you go, apply at commit, abort discards); replay applies committed windows and drops unterminated ones, finalizing a dangling window with an Abort record; checkpoint + auto-commit rejected mid-txn; suite txn tests + `db_crash_test` scenarios D/E x2 Win + WSL |
| D3 | MVCC snapshots / version-aware reads | 4 | WIP 2 | **M3 minimal subset landed 2026-10-11** (`docs/MVCC.md`): snapshot pins capture `{root, lsn, generation}`; writes copy-on-write the touched node paths while pinned (deep-copied shadows; C-ORBIT-09), so pinned views are exact; snapshot reads (`db_file_snapshot_get/typed/range/count`); compaction refuses while pinned (`compaction_deferred`); deferred-free hook `db_file_min_pinned_lsn`; txn savepoints (buffer trim + WAL window splice). Evidence: 7 suite tests (159 x2 Win + WSL), `probe_mvcc` 36 checks x2 both, fuzz (l) x2 both, db_crash 25/25 x2. Remaining: multi-process locks (stdlib row), pager-backed lazy reads (M1.1b), version GC |

## E. Query & schema (10)

| # | Item | Pts | Status | Evidence / gate |
|---|---|---|---|---|
| E1 | Query engine: AND filter, offset, limit, deterministic order | 3 | OK | suite query/db_query/db_file tests; **value semantics pinned** in docs/query-pipeline.md; `db_file_range`/`db_file_query` on recovered trees; `qverify` in every `db_crash_test` scenario x2 Win + WSL; ORDER BY (key/value asc/desc, stable ties) executed before offset/limit (M4.2) |
| E2 | Index-aware planner (key-range pushdown, point lookup, cost) | 3 | OK | additive semantics decision recorded (`query_key_range`; key range -> value conditions -> offset -> limit, docs/query-pipeline.md); `plan_query` chooses PointLookup/IndexRange/FullScan with clamped range-width estimate; `execute_plan` scans `btree_range_query` then filters; `db_file_query` planned; suite plan-kind test + 200-case seeded property vs brute force x2 Win + WSL |
| E3 | Secondary indexes driven by catalog `IndexDef` | 2 | WIP 1 | handle-scoped value index (`src/secondary_index.xi`: (value, pk) sorted entries, binary-search probes) maintained by put/update/delete/txn-commit; `db_file_create_index_from_def` accepts a catalog `IndexDef` (value column 0, non-unique); planner `IndexValue` plan + executor; suite (build/maintenance/plan/order) + fuzz section (g) vs brute-force model x2 Win + WSL. **Durable page-backed index storage pending A5** |
| E4 | Typed values + column constraints (beyond Int) | 2 | **2** | M5.1 codec + M5.2 schema layer + M5.3 engine persistence landed 2026-10-11: `TValue`/tuple v2, `schema_row` (kind/nullability/pk constraints), payloads through tree/WAL (subtype 1)/both snapshot containers with auto-detect + budget + byte validation; suite 149 x2 both, fuzz (h)(i)(j), fault E, legacy v1-node-page artifacts load unchanged; typed-column query/index predicates remain (S4) but typed write/read is shippable capability |

## F. Operations & tooling (10)

| # | Item | Pts | Status | Evidence / gate |
|---|---|---|---|---|
| F1 | ps1 + sh twins: dev-env, watchdog runner | 2 | OK | both platforms green |
| F2 | Crash/reopen + soak harness | 2 | OK | `crash_test.{ps1,sh}`, 200/20k soaks |
| F3 | CI matrix (Windows/Linux; pinned toolchain from dl); org SHA-pinning | 2 | -- | owner gate: public repo (ops has the mechanics) |
| F4 | Packaging: `xiom.wal`/`xiom.btree` extraction, `xiom.db` publish, build-info/version stamp | 3 | 2 | `xiom.wal` 0.1.0 consumer pass GREEN (18 checks x2 both, two-way interop); `xiom.btree` 0.1.0 registry-live (re-extract with the order-3 fix next); `xiom.db` publish + version stamp pending |
| F5 | Release engineering: signed tags, notes, artifacts, checksums | 1 | -- | owner gate |

## G. Performance & limits (5)

| # | Item | Pts | Status | Evidence / gate |
|---|---|---|---|---|
| G1 | Benchmarks (insert/search/delete/range; WAL append/replay throughput) | 2 | OK | `scripts/bench.{ps1,sh}` + `probe_bench`; v0.64.1 N=10k: Win btree_insert 1.25M/s, search 3.3M/s, delete 1.67M/s, tuple 714k/s, WAL append 2.9k/s, replay 0.94k/s; WSL native-fs append 26k/s. The filed `str_split`/`read_file_lines` quadratic is fixed in stdlib (linear; 20k-record replay ~9.9 s); re-run the bench on the current pin at G1 refresh. **Cross-engine BENCH-1 (2026-10-16):** `docs/BENCH-1.md` + `scripts/bench_cross.{ps1,sh}` -- ORBITDB vs SQLite 3.54.0 (`synchronous=FULL` rows) vs bbolt v1.4.3 on identical YCSB-ish phases, per-row verify parity; durable per-op writes: ORBITDB 611/s, SQLite 1457/s, bbolt 579/s (Windows, shared host); WSL nosync 16.6k/s; finding: per-record append syscalls dominate Windows writes (batched held-handle WAL append = next perf slice) |
| G2 | Memory bounds (page budget, WAL segment size policy, cache) | 2 | 1.0 | tuple budget + WAL segment size policy (`db_file_maybe_checkpoint`, bounded replay after truncate) + compaction-bounded snapshot log; page/cache bounds pending |
| G3 | Scale soak (1M+ keys, long WAL) | 1 | -- | |

## H. Security & integrity (5)

| # | Item | Pts | Status | Evidence / gate |
|---|---|---|---|---|
| H1 | Integrity: checksums on pages, strict decode, no partial rows | 2 | OK | CRC32C + codec KATs |
| H2 | Input validation (paths, sizes, field counts) | 1 | OK | `db_path_valid` (non-empty, <= 4096, no CR/LF) + `db_file_open_checked` (Err(ConstraintViolation) on bad path/order); sizes/field counts already gated (4096 page contract, 255-field codec, `tuple_fits_page`); suite validation tests x2 Win + WSL |
| H3 | Fuzz/property testing (codec, WAL parser, B-tree vs model at scale) | 1 | OK | `scripts/fuzz.{ps1,sh}` + `probe_fuzz.xi`: deterministic LCG seeds -- tuple roundtrip/byte-flip/truncation, WAL records + garbage + torn tails + heal-append, page-log latest-wins/CRC rejection, block v2 roundtrip/mutation, B-tree vs model over orders 3/4/5 x2 Win + WSL. Continuous CI cadence awaits F3 |
| H4 | Supply chain: package signature verification, pinned toolchain | 1 | 0.5 | dev-env pins versions; registry adoption not started |

## I. Documentation & evidence (5)

| # | Item | Pts | Status | Evidence / gate |
|---|---|---|---|---|
| I1 | README/SPEC/ARCHITECTURE/ROADMAP/AUDIT + docs/ set | 2 | OK | current + honest |
| I2 | Relay docs (compiler findings, stdlib/package wishlists, per-lane messages) | 2 | OK | kept current every wrap |
| I3 | Public API reference / runbooks / format spec versioning | 1 | OK | `docs/API.md` (all pub surfaces + contracts/error semantics), `docs/RUNBOOK.md` (commands, recovery, gotchas), `docs/FORMATS.md` (versioned WAL/page-log/snapshot/tuple v1 + CRC32C + version policy); linked from README |

## Phase gates (mapping to ROADMAP.md)

| Gate | Meaning | Blocking score |
|---|---|---|
| **v0.1 pre-alpha** | In-memory core correct + crash-proven WAL segment (current) | 39.5 |
| **v0.2 alpha** | A4/A5 done + C2 (durable page file) + B4 (engine on disk WAL) | ~60 |
| **v0.3 beta** | B5 fsync + B6 torn-page matrix + D2 redo/undo + G benchmarks | ~80 |
| **v1.0 production** | All areas >= 90%; CI + packaging + release engineering + fuzz in place; no area below 4/5 of its weight | 100 |

## What 100% specifically requires (checklist)

- [ ] Every data path proven by suite x2 + a soak; every durability path by
      the crash harness on Windows AND WSL.
- [x] fsync wired (M1.2 S4: commit acks, checkpoint pre-sync, rename
      durability via temp sync + `fsync_dir`; fault-gated). Still open:
      the power-loss matrix on real hardware/power-cut rig.
- [ ] Power-loss matrix run (power-cut/battery rig; out of current scope).
- [x] Engine on disk: WAL-before-ack, recovery from real files, checkpoint.
- [x] Durable page file + replacement policy (clock + pinning).
- [x] Fuzz/property harness (codec, WAL parser, page log, B-tree vs model).
- [ ] Pager substrate; torn-page detection.
- [x] Redo/undo with committed/uncommitted classification (crash scenarios D/E).
- [x] MVCC story decided (`docs/MVCC.md`; M3.1 pins + savepoints landed
      2026-10-11; multi-process locks + version GC remain).
- [ ] Benchmarks with published numbers and no unbounded memory growth.
- [ ] CI matrix green on Windows/Linux with pinned toolchain and SHA-pinned
      actions; release artifacts + SHA256SUMS; build-info/version stamp.
- [ ] Fuzz harness on codec/WAL parser; B-tree model soak at 1M+ ops.
- [ ] Public API reference, format/versioning doc, ops runbook.
- [ ] All relay findings either fixed upstream (verified by re-test) or
      documented as accepted limitations.
