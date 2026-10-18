<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# XVECTOR -> PULSE integration: consumer handshake (XVECTOR half)

> Requested by PULSE (`E:\xiom-projects\xiom-pulse\docs\XVECTOR-RELAY-PULSE.md`,
> 2026-10-09). PULSE reads this file locally (read-only; XVECTOR never edits
> PULSE's tree). Kept current every wrap. **Pin at handover: `de1db14`
> (2026-10-09); this file lands one commit later.**

## 1. Embedding API surface for a consumer today

Import path: `use xiom.vector.engine;` (facade) and, whenever you call
`engine_*` symbols (recovery, request-driven search), also
`use xiom.vector.engine.core;` -- required by the module system.

Supported today: create collection -> upsert / search / delete / get by
external **Int id**; batch ops (`upsert_many`/`search_many`/`delete_many`);
exact Flat scan and HNSW ANN; exact range search
(`search_range(eng, query, radius, limit)` -- inclusive radius, distance
sorted); pagination (`search_page` offset + `search_after` after-id cursor
over the distance/id total order, exact on both index kinds); selective
delete-by-filter (`delete_filter` -- typed filter, planner-driven,
WAL-durable); per-collection stats + index admin (`collection_stats` /
`rebuild_index`); request modes + request-level pagination + batches
(`SearchRequest.mode` knn/range with radius, `offset`/`after_id`,
`search_batch_with_request`); HTTP service skeleton (`api.http_service`:
`/health`, `/collections`, points get/upsert/delete, `/search`, `/stats`;
byte-level pipeline -- the socket adapter is gated on the stdlib
`xiom.net` proof; S2 limits/config via `XVECTOR_MAX_*` + key=value file
and the `{error,kind,status}` model; S3 API-key auth (scopes
read/write/admin, `XVECTOR_API_KEYS`, constant-time) + rate limiting;
S4 fuzz/SBOM/unsafe gates + threat model in `docs/SECURITY.md`);
observability (`GET /metrics` prometheus text + `/health` readiness +
bounded JSON log ring; runbook `docs/OPERATIONS.md`); typed
payload filters with a selectivity planner; payload
hydration; whole-file WAL checkpoint + recover. Multi-collection registry:
`create_named_collection`/`select_collection`/`drop_collection`/
`list_collections` with per-collection isolation, whole-registry
`save_manifest` + `open_engine`, and sealed segment files
(`seal_segment`/`restore_segment`).

- Vector representation: `Vector { data: Vec[Float32]; dimension: Int }`
  built with `Vector.new(dim)` + `v.set(i, value)`.
- Dimension limits: `1..=65536` (`is_valid_dimension`); practical guidance
  <= 4096 for now.
- Metrics: `DistanceMetric.Cosine | DotProduct | Euclidean`. Distances are
  **smaller-is-better** in all three (cosine returns `1 - cos`).
- Errors: `Result[T, CoreError]` with codes 1001-1006
  (`src/error.xi`); `Option[T]` for `get_point` / `get_payload`.

Snippet A -- create, upsert, search:

```xi
use xiom.vector.engine;
use xiom.vector.engine.core;

fn mk3(x: Float32, y: Float32, z: Float32) -> Vector {
  var v = Vector.new(3);
  v.set(0, x); v.set(1, y); v.set(2, z);
  return v;
}

fn main() -> Int {
  var eng = engine_new();
  match create_collection(&mut eng, 3, DistanceMetric.Cosine) {
    Ok(_) => {}
    Err(_) => { return 10; }
  }
  let _ = upsert(&mut eng, 42, mk3(1.0, 0.0, 0.0));
  var q = mk3(0.9, 0.1, 0.0);
  match search(&eng, &q, 5) {
    Ok(hits) => { /* hits.items: Vec[SearchResult{ id, distance }] */ }
    Err(_) => { return 11; }
  }
  return 0;
}
```

Snippet B -- payloads + filters:

```xi
var p = payload_new();
payload_set(&mut p, "bucket", FieldValue.IntVal(7));
let _ = set_payload(&mut eng, 42, p);

var f = filter_and(filter_eq("bucket", FieldValue.IntVal(7)),
                   filter_range("price", 10.0, 99.0));
match search_filtered(&eng, &q, 5, &f) { Ok(hits) => { /* ... */ } Err(_) => {} }
```

Snippet C -- checkpoint + reopen (also the kill -9 recovery path):

```xi
use xiom.vector.durability.wal_file;

let _ = wal_persist(&eng.wal, "app.wal");   // atomic whole-file checkpoint
// fresh process:
var wr = wal_load("app.wal");               // longest valid prefix
var eng2 = engine_recover(&wr, 3, DistanceMetric.Cosine);
```

Request-driven search with hydration (optional convenience):
`search_request_new(query, top_k, metric)` +
`search_request_set_filter` + `search_request_set_with_payload` ->
`search_with_request(&eng, &req)` returns `HydratedHits` (`id`, `distance`,
`payload`, `has_payload`). HNSW tuning: `set_index(&mut eng, AnnIndexKind.Hnsw,
ann_params)`; `compact_index` reclaims tombstones.

## 2. Build + link contract + platform matrix

- **Project key:** `xiom.xvector` `0.2.0` (`xiom.toml`); registry manifest
  `xiom-vector` `0.2.0` (`package.xi`) -- **not published yet**; consume at
  source until the owner's release.
- **Dependencies:** stdlib **plus five registry packages** (the 2026-10-10
  adoptions: `xiom.wal` 0.1.0, `xiom.metrics` 0.2.0, `xiom.rate` 0.2.0,
  `xiom.http` 0.1.4, `xiom.vectors` 0.1.0 -- `xiom.toml [dependencies]`).
  Consumers building the facade source need these in their package home
  (`xiom pkg install ...`; C-PULSE-02 resolved in v0.64.2). The core
  shim (`src/core/shim.xi`) is error/ids/contracts only now (its metrics
  part moved onto `xiom.metrics`).
- **C ABI:** none. Pure XIOM source composition (PULSE's driver wraps the
  module API directly; a bindings/C layer would be new work, prefer source).
- **Platform matrix:** windows-x64 **GREEN**; linux-x64 (WSL Ubuntu)
  **GREEN** -- both: suite 171/171 x2 + 37 probes x2 + sbom + bench
  smoke on compiler v0.64.3 (lane-local toolchain + package home).
  macos-x64 / macos-arm64 **UNTESTED** (no toolchain here; upstream Darwin
  items from PULSE's C-PULSE-14 index still gate macOS broadly).

## 3. Pin + stability

- **Pin:** `06f7204` (2026-10-10) + the commit that updates this file;
  re-read this file every wrap -- the pin line is updated here.
- **Guaranteed** (suite x2 + probes x2 both platforms): facade
  `create_collection/upsert/search/delete_point/get_point/set_payload/
  get_payload/search_filtered`; `engine_new`; WAL checkpoint/recover;
  filter semantics Eq/Range/In/Exists/And/Or/Not; exact numeric results
  bit-exact per build.
- **Experimental** (may change): filter planner internals, HNSW internals
  (graph layout/codec), the `xvector-wal 1` text format, tunings.
- **On-disk layout:** the consumer chooses one WAL path; `wal_persist`
  writes ONE text file atomically (temp + rename). No directory layout yet
  (segment files are M-D4, manifest file M-D2). Backup/restore: checkpoint
  the WAL while quiescent, copy the file; restore = `wal_load` +
  `engine_recover` (bit-exact per probe).

## 4. Consumer-affecting findings + lifecycle

- **Open XVECTOR findings: two caller-side rules** on compiler
  v0.64.2/v0.64.3 -- **XVC-C-13**: never declare `&Str` parameters (the
  checker defaults them to i64; pass `Str` by value); **XVC-C-14**:
  never let two same-named struct types meet in one program (the
  short-name layout shadow -- do not define types named like consumed
  package types, e.g. `Counter`/`Vector`). XVC-C-01..C-12 verified fixed
  or fixed-in-context (`docs/COMPILER-FINDINGS-XVECTOR.md`); the
  retained workarounds are internal.
- **C-PULSE-14 (RSS growth) is relevant here too:** Windows is flat on
  v0.64.2; **Linux still grows (~87 KB/req in PULSE's measurement; the
  compiler-side item is pending)**. XVECTOR's own sustained
  upsert/search RSS will be measured by the in-repo bench (M-G,
  `docs/BENCHMARKS.md`); until then treat long-running Linux memory as
  unproven. Mitigations that exist today: periodic `compact_index` and
  checkpoint+recover cycles.
- **Threading:** single-threaded; no global state -- the engine is a value
  the consumer owns (one engine per thread/process; compose on one thread).
- **kill -9 semantics:** crash-consistent at **checkpoint granularity**.
  Writes acknowledged after the last `wal_persist` can be lost until the
  stdlib fsync gap lands (M-D5, external); recovery is `wal_load` (longest
  valid prefix) + `engine_recover`; a kill during a checkpoint leaves the
  previous complete file (atomic swap, M-D1).
- **Sustained upsert:** no memory cap yet; HNSW graph + WAL grow per
  upsert. Recommended pattern: batched upserts + periodic checkpoint /
  `compact_index`. Safe batch sizes: TBD by the bench, published when
  measured.

## 5. Conformance test proposal (acceptance gate for `probe_pkg_xvector`)

1. Upsert/search round-trip: 1k deterministic vectors; k=1 and k=10;
   compare vs the exact Flat baseline (`set_index Flat`).
2. Filter combinations: Eq, Range, In, And/Or/Not, no-payload semantics;
   filtered subset is consistent with the unfiltered scan.
3. Reopen integrity: checkpoint -> new process -> `wal_load` +
   `engine_recover` -> identical ids + distances and intact payloads.
4. Top-k edges: k=1; k > live size; empty index; k=0 rejected; k=10000 max.
5. Dimension limits: dim=1 and dim=65536 accepted; dim=0 rejected;
   query/collection dimension mismatch rejected (code 1002-family).
6. Delete/re-add: deleted id disappears; re-add revives it; delete survives
   reopen.
7. Duplicate ids: upsert same id overwrites -- never duplicate hits.
8. WAL prefix: truncate the WAL file at a record boundary -> reopen yields
   exactly the prefix (torn-tail tolerance).
9. (With OrbitDB) the hybrid join probe: see `docs/ORBITDB-INTEGRATION.md` §5.

Run 1-8 in PULSE's fleet on Linux + Windows; file reds with minimal repros
through the relay docs.

## 6. Cross-project asks (what XVECTOR needs from PULSE)

1. **Driver shape:** you plan `upsert(id, vector, payload) / search(top_k,
   filter) / delete`. Today payload is a separate call
   (`set_payload(id, payload)`) and delete is `delete_point(id)`. Tell us
   which shape you will probe; a combined upsert-with-payload is a
   candidate API addition (M-Q) if you want it.
2. **Score semantics:** we return raw `Float32` distances
   (smaller-is-better; cosine = `1 - cos`). Tell us how you want them
   presented in the driver (`score = 1 - distance` for cosine?).
3. **Concurrency:** keep single-threaded composition; tell us if you need
   process-level snapshot reads -- the P1 concurrency design will
   prioritize the consumer's need.
4. **Probe scenarios:** send us the scenarios as you build
   `probe_pkg_xvector`; we adopt them as additional in-repo gates.
5. **Volume profile:** expected call volume / batch sizes / retention for
   RSS baselining; we mirror them in the M-G bench.
