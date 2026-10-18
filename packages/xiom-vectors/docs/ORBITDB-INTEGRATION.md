<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# XVECTOR -> ORBITDB integration: hybrid retrieval (XVECTOR half)

> Requested by ORBITDB (`E:\xiom-projects\xiom-orbitdb\docs\RELAY-XVECTOR-ORBITDB.md`,
> 2026-10-09); mirrors `XVECTOR-INTEGRATION.md` on their side. ORBITDB reads
> this file locally (read-only). Kept current every wrap. **Pin at handover:
> `de1db14` (2026-10-09); this file lands one commit later.**

## 1. Embedding/search API for a consumer today (the vector half)

Import: `use xiom.vector.engine;` + `use xiom.vector.engine.core;` (the
`engine_*` symbols, incl. recovery, need the core import).

- `upsert_many(eng, ids, vecs)` / `delete_many(eng, ids)` / `search_many(eng,
  queries, k)` -- batch ops (M-Q2) with all-or-nothing validation; the bulk
  repair pass should use `upsert_many` in chunks (see §4).
- `upsert(eng, id, vec)` -- **idempotent by external Int id** (overwrite,
  no duplicates); `delete_point(eng, id)` (safe on a missing id); 
  `get_point(eng, id) -> Option[Vector]`; `set_payload` / `get_payload`.
- `search(eng, &query, k) -> Result[SearchHits, CoreError]` with
  `SearchResult{ id, distance }` -- the join key is `id` (your row id).
- `search_range(eng, &query, radius, limit)` -- exact range (inclusive
  radius, distance-sorted); useful for "all embeddings near this one"
  joins.
- `Vector{ data: Vec[Float32]; dimension: Int }` via `Vector.new(dim)` +
  `set(i, v)`; dims `1..=65536`; metrics `Cosine | DotProduct | Euclidean`;
  **distances smaller-is-better** (cosine = `1 - cos`).
- Pagination (since M-Q3): `search_page(eng, &query, k, offset)` and
  `search_after(eng, &query, k, after_id)` over the (distance asc, id asc)
  total order; exact on Flat and Hnsw; a deleted cursor -> `Err(NotFound)`.
- Selective delete (since M-Q4): `delete_filter(eng, &expr)` removes
  every matching point (planner-driven, WAL-durable, tombstones +
  payload/index cleanup); nothing matching -> `Ok(0)`. Useful for
  version-slot cleanup after re-embeds.
- Checkpoint/recover: `wal_persist(&eng.wal, path)` (atomic whole-file
  checkpoint) + `wal_load(path)` + `engine_recover(&wr, dim, metric)`.
- Multi-collection registry (since M-D3): `create_named_collection` /
  `select_collection` / `drop_collection` / `list_collections` with
  per-collection isolation; whole-registry `save_manifest` + `open_engine`
  (file-wins by name). Sealed segment files (`seal_segment` /
  `restore_segment`) landed with M-D4.

Your ordering rule and repair pattern are accepted as-is: **row commit
first, embedding upsert second**; a crash between them leaves an
unsearchable row (no dangling hit); the repair pass re-embeds rows whose
embedding version lags the row version. We add no cross-store transaction;
the version-slot + repair pattern is the documented consistency story.

```xi
// ingest side (xvector): embed row_id after the row commit
let _ = upsert(&mut eng, row_id, mk_vec(embedding));

// query side (xvector -> ORBITDB join)
match search(&eng, &q, 20) {
  Ok(hits) => {
    var i: Int = 0;
    while i < hits.items.len() {
      let row = db_file_get(&db, hits.items[i].id); // missing -> skip
      // (score order = hits order; distances smaller-is-better)
      i = i + 1;
    }
  }
  Err(_) => {}
}

// delete side: row tombstone FIRST, then best-effort
let _ = delete_point(&mut eng, row_id);           // idempotent, safe if absent
```

**Cross-store filter sets (honest note):** your `db_file_range` outputs an
id set; XVECTOR has no "search restricted to an id set" API today. Two
supported patterns: (a) **post-filter** the search hits against the row set
and over-fetch (`k * 3..5`) when the set is sparse; (b) **payload mirror**
-- copy the filter keys into xvector payloads and use `search_filtered`
(planner-driven; preferred for selective filters). An id-subset filter
(`filter_in_ids`) is a candidate API extension (M-Q) -- tell us if the
over-fetch ratio makes it necessary.

## 2. Build + link contract + platform matrix

- **Project key:** `xiom.xvector` `0.2.0` (`xiom.toml`); registry manifest
  `xiom-vector` `0.2.0` (`package.xi`) -- **not published yet**; source-level
  composition until the owner's release.
- **Dependencies:** stdlib **plus five registry packages** (the 2026-10-10
  adoptions: `xiom.wal` 0.1.0, `xiom.metrics` 0.2.0, `xiom.rate` 0.2.0,
  `xiom.http` 0.1.4, `xiom.vectors` 0.1.0; `xiom.toml [dependencies]`).
  Consumers building the facade source need these in their package home
  (C-PULSE-02 resolved in v0.64.2). The core shim (`src/core/shim.xi`) is
  error/ids/contracts only now.
- **C ABI:** none -- pure XIOM composition; neither side links the other's
  internals.
- **Platform matrix:** windows-x64 **GREEN**; linux-x64 (WSL Ubuntu)
  **GREEN** (suite 171/171 x2 + 37 probes x2 + sbom + bench smoke on
  compiler v0.64.3, lane-local each);
  macos-x64 / macos-arm64 **UNTESTED** (no toolchain; upstream Darwin items
  gate macOS broadly).

## 3. Pin + stability + on-disk layout

- **Pin:** `06f7204` (2026-10-10) + this file's commit; re-read every wrap.
- **Guaranteed:** facade (create/upsert/search/delete/get/set_payload/
  get_payload/search_filtered), `engine_new`, WAL checkpoint+recover, filter
  semantics, numeric results bit-exact per build.
- **Experimental:** planner internals, HNSW internals/codec, the
  `xvector-wal 1` text format.
- **On-disk layout:** one WAL file per engine value, path chosen by the
  consumer (e.g. `embeddings.wal`); atomic temp+rename checkpoint; no
  directory layout yet (segment files M-D4). Backup: quiesce, checkpoint
  vectors + rows, copy both; restore either order -- row/vector skew is
  safe under your skip/repair rules. Restore = `wal_load` +
  `engine_recover` (bit-exact).

## 4. Consumer-affecting findings + lifecycle

- **Open findings: two caller-side rules** on compiler v0.64.2/v0.64.3 --
  XVC-C-13 (`Str` by value; no `&Str` parameters) and XVC-C-14 (no
  same-named type families across modules; do not name your types like
  consumed package types) -- XVC-C-01..C-12 verified
  (`docs/COMPILER-FINDINGS-XVECTOR.md`).
- **C-PULSE-14 (RSS growth) matters for your bulk repair pass:** Windows
  flat on v0.64.2; **Linux still grows (~87 KB/req in PULSE's measurement;
  compiler-side item pending)**. XVECTOR's own sustained-load RSS is being
  measured by the in-repo bench (M-G); **recommended repair chunking until
  numbers land: <= 1k upserts per chunk via `upsert_many` (all-or-nothing
  per chunk) with a checkpoint (+ optional `compact_index`) every few
  chunks** -- final safe batch sizes will be published in
  `docs/BENCHMARKS.md`.
- **Threading:** single-threaded; no global state -- one engine value per
  consumer thread/process; compose both stores on one thread.
- **kill -9:** crash-consistent at checkpoint granularity; writes after the
  last `wal_persist` can be lost until the stdlib fsync gap lands (M-D5);
  kill during checkpoint leaves the previous file (atomic swap).
- **Delete semantics:** `delete_point` removes vector + payload; re-add
  revives; idempotent on missing ids (your GC sweep can call it blindly).

## 5. Conformance proposal for `probe_hybrid` (acceptance gate)

1. Ingest 1k rows (transactional) + embeddings; search + join: 100% join
   integrity -- every hit maps to a live row, no duplicate rows, order =
   score order.
2. Hard-kill both stores, reopen, run the repair pass: 100% join integrity
   again (your headline gate).
3. Crash between row commit and embedding upsert (kill after step 1 of the
   ordering): row is unsearchable (no dangling hit); after repair it is
   searchable; version slots reconcile.
4. Delete pipeline: row tombstone -> vector delete -> no hit remains; GC
   sweep drops orphan embeddings (`delete_point` on a missing id is safe).
   Crash between tombstone and vector delete -> no dangling hit either way.
5. Top-k edges: k=1; k > live size; empty index; k=0 rejected; max 10000.
6. Dim mismatch: query/collection mismatch rejected; re-embed at a new dim
   requires a new collection (dimension is fixed per collection).
7. Duplicate ids: repeated upsert overwrites (no dup hits); delete then
   re-add revives.
8. Reopen integrity per store: xvector ids+distances identical; rows
   readable; payloads intact.
9. Filters: if the payload-mirror pattern is adopted, a filtered join is
   consistent with the row filter set; otherwise post-filter with
   documented over-fetch.
10. WAL prefix: truncate the xvector WAL at a record boundary -> reopen
    joins exactly the prefix (torn-tail tolerance).

## 6. Cross-asks (what XVECTOR needs from ORBITDB)

1. **Join primitive:** is there a batch/multi-get by id list, or is
   `db_file_get` per id the intended shape? Tell us the fastest join path.
2. **Committed-read semantics** for the join pass under a concurrent writer
   (single-threaded composition, but define what a reader sees).
3. **Filter sets:** the shape of `db_file_range` output (Vec[Int]?) -- to
   decide post-filter vs payload-mirror and to measure the over-fetch
   ratio.
4. **Kill harness for `probe_hybrid`:** who spawns/kills which store and at
   which point; we can reuse the checkpoint+recover path and help script
   it.
5. **Pins:** your commit + `docs/FORMATS.md` version for the row store so
   the pair is pinned together in both files.
6. **Typed ids:** int ids are fine today; your types v2 (M5) will need an
   extension on our side -- flag the timing so we plan it together.
