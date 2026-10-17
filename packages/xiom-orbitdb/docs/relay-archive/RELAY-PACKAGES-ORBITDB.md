# Relay: ORBITDB -> packages lane (paste-ready)

**From:** ORBITDB lane (`E:\xiom-projects\xiom-orbitdb`, embedded database
engine; formerly xiom-db). **Pin (current 2026-10-09):** compiler v0.64.2,
stdlib `e7896ff`; the body below was written on v0.64.0. Full table:
`docs/PACKAGE-WISHLIST-ORBITDB.md`.

Hi packages lane -- ORBITDB is the embedded DB consumer lane (B-Tree, WAL,
query engine, crash recovery). Phase 0 is in-memory and zero-dependency; on
v0.64.0 the 93-test conformance suite is green x2 (Windows + WSL) and a
durable WAL probe with hard-kill crash/reopen is green (incl. a 200-record
soak). We have **no registry consumer pass yet** -- no package defects to
report -- but two extraction candidates are coming out of this work, and
I'd like your read on the boundaries:

1. **`xiom.btree`** -- ordered in-memory index (flat-array B-tree:
   insert/search/delete/range/min/max/size). Why a package: data-structure
   domain, API will grow (cursors, bulk load, secondary-index helpers).
   Status: this session fixed a real split child-pointer bug (100-insert
   probe); **delete/underflow invariants for odd orders are still debt**, so
   extraction is honest only after a churn soak. Evidence: `src/engine.xi`
   B-tree section + `tests/probes/probe_core_diag.xi`.
2. **`xiom.wal`** -- append-only durable log (record codec, replay,
   torn-tail healing, segment truncate/checkpoint seam). Why a package:
   storage policy + file format; PULSE's `xiom.kv` and any embedded store
   need the same crash-safety engine. Deps: xiom.std (+ the filed stdlib
   fsync row). Evidence: `probe_wal_file.xi` + `scripts/crash_test.{ps1,sh}`.
3. **`xiom.db` (this engine, eventual publish)** -- the layered engine
   behind `xiom.db.*`. Final name/publish timing is the owner's call; no
   rush per the parked-public-release decision.

Registry watch: **`xiom.kv` 0.1.0** is available; ORBITDB will compare it
against its own WAL/compaction design before adopting. PULSE's known-red
`kv_get` gate (C-PULSE-10 in PULSE's compiler findings) is the item to
watch there. No C-FFI/bindings need from ORBITDB (pure XIOM target).

Question for you: for `xiom.wal`, would you rather see it published as a
standalone package or as the storage core of `xiom.kv`/`xiom.db`? ORBITDB
can shape the API to whichever boundary you prefer and will send a consumer
probe the moment it adopts a registry package.

**Status 2026-10-09 (v0.64.2):** re-test complete with all compiler
workarounds dropped (suite 120/120 x2 Windows + WSL; WAL/page/DB crash x2;
fuzz + 2000-key soak). `xiom.btree` gate plus fuzz coverage met -- awaiting
your extraction call; `xiom.wal` gate unchanged (stdlib fsync stub,
hand-rolled tail repair) and its proposed record shape now includes txn
kinds (Begin/Commit/Abort) and the checkpoint anchor; `xiom.kv` still not
consumed. Details: `docs/PACKAGE-WISHLIST-ORBITDB.md` (Delta 2026-10-09).
