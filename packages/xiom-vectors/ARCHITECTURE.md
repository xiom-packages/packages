<!--
Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
SPDX-License-Identifier: MIT OR Apache-2.0
-->

# xiom-vector -- Architecture

## 1. Design model: shared core + vector layer

xiom-vector does **not** re-implement durable-systems plumbing. It adopts the
same model as the rest of the XIOM data ecosystem (xiom-db, xiom-vector):

```
+--------------------------------------------------------------+
|                         xiom-vector                            |
|   vector-specific layers: types, storage, indexes, query,      |
|   collections, payload/filtering, segments, durability, api    |
`-------------------------------+--------------------------------+
                                 | depends on (reuse, not fork)
+-------------------------------v--------------------------------+
|                          xiom-core                             |
|  error - ids - config - limits - contracts - wal - metrics -   |
|  storage(pager/page/buffer_pool) - txn                         |
`--------------------------------------------------------------+
```

**Why a shared core?** Errors, identifiers, the WAL record format, system limits,
and correctness predicates must be *identical* across every engine so that (a)
recovery only ever parses one WAL shape, (b) a `CoreError` means the same thing
everywhere, and (c) guardrails like `max_dimensions()` / `max_top_k()` cannot
drift between subsystems. The vector engine contributes only what is genuinely
vector-specific.

## 2. Module tree (file by file)

```
src/
|-- core/
|   `-- shim.xi      module xiom.vector.core.shim
|                     xiom-core stand-ins (porter-flow mapping target):
|                     CoreError, Counter + counter_new/inc,
|                     CollectionId/VectorId/SegmentId + helpers, and the
|                     validity predicates is_valid_dimension/is_valid_top_k [EXTRACTED]
|-- error.xi        module xiom.vector.error
|                     VectorError { DimensionMismatch, UnsupportedMetric,
|                     CollectionNotFound, InvalidVector, SegmentSealed,
|                     TopKExceeded } + to_str / to_core / code
|-- ids.xi          module xiom.vector.ids
|                     PointId (user id) + reuse of core CollectionId/VectorId/
|                     SegmentId + PointId<->VectorId bridges
|-- engine.xi       module xiom.vector.engine
|                     public facade ONLY -- create_collection, set_index,
|                     compact_index, upsert, upsert_many, search,
|                     search_many, delete_point, delete_many,
|                     get_point, set_payload, get_payload,
|                     search_filtered, search_range, search_with_request;
|                     thin
|                     delegation to engine.core (no shims here)          [EXTRACTED]
|-- engine/
|   `-- core.xi      module xiom.vector.engine.core
|                     VectorEngine + engine_* orchestration -- engine_new,
|                     engine_create_collection, engine_set_index,
|                     engine_compact_index, engine_upsert,
|                     engine_upsert_many, engine_search
|                     (routes Flat/Hnsw), engine_search_many, engine_delete,
|                     engine_delete_many,
|                     engine_set_payload, engine_get_payload,
|                     engine_search_filtered, engine_search_range,
|                     engine_search_request,
|                     engine_get_point, engine_size, engine_durable_lsn,
|                     engine_recover + the durable collection manifest
|                     (REAL dispatch to store + graph + WAL
|                     + search + payloads + recovery)                     [EXTRACTED]
|
|-- types/
|   |-- dense_vector.xi   Vector + new/set/get + dot/magnitude          [EXTRACTED]
|   |-- metric.xi         DistanceMetric + cosine/dot/euclidean +
|   |                     vector_distance dispatch                   [EXTRACTED]
|   |-- neighbor.xi       Neighbor (id, distance) low-level edge      [EXTRACTED]
|   `-- dimension.xi      Dimension wrapper + validation              [DONE]
|
|-- collection/
|   |-- schema.xi         CollectionSchema (dim, metric, normalization,
|   |                     payload fields)                            [IN PROGRESS]
|   |-- collection.xi     Collection (schema + segment registry + index cfg) [SCAFFOLD]
|   `-- validator.xi      dimension/metric compatibility, typed errors [IN PROGRESS]
|
|-- payload/
|   |-- payload.xi        Payload + FieldValue + WAL codec + store +
|   |                     sorted key index (parallel-vector rows)       [EXTRACTED]
|   |-- filter_ast.xi     FilterExpr (Eq/Range/Exists/In/And/Or/Not)  [EXTRACTED]
|   `-- filter_eval.xi    typed eval + payload_store_matches          [EXTRACTED]
|
|-- storage/
|   |-- vector_store.xi   VectorIndex flat store + vector WAL codec   [EXTRACTED]
|   `-- id_map.xi         VectorId -> (segment, offset) mapping       [DONE-ish]
|
|-- segment/
|   |-- segment_state.xi  SegmentStateKind + transition table         [SCAFFOLD]
|   |-- segment.xi        Segment (store + state)                     [SCAFFOLD]
|   |-- manifest.xi       collection manifest of active segments      [SCAFFOLD]
|   `-- segment_file.xi   sealed-segment codec (persist/load)         [NEW 2026-10-09]
|
|-- index/
|   |-- ann_index.xi      AnnIndexKind {Flat,Hnsw,Ivf} + AnnParams    [DONE]
|   |-- flat_index.xi     exact brute-force baseline (truth oracle)   [DONE]
|   `-- hnsw.xi           multi-layer graph (geometric levels, greedy
|                         descent + layer-0 beam; word codec; recall
|                         harness)                                      [DONE]
|
|-- distance/
|   |-- cosine.xi         cosine kernel + similarity                  [DONE]
|   |-- dot.xi            dot distance + raw dot                      [DONE]
|   `-- l2.xi             l2 distance + l2_squared                    [DONE]
|
|-- query/
|   |-- search_request.xi SearchRequest (query, top_k, metric, filter) [DONE]
|   |-- filter_plan.xi   selectivity estimates + pre/post plan choice [EXTRACTED]
|   |-- topk_heap.xi      bounded top-K heap (invariant: <= k)         [DONE]
|   |-- search_service.xi search_knn / search_knn_filtered / search_range_scan [EXTRACTED]
|   `-- pagination.xi     offset + after-id kernels over (distance, id) [NEW 2026-10-09]
|
|-- durability/
|   |-- wal.xi            WalOpKind/WalRecord/WalWriter + append/resume  [EXTRACTED]
|   |-- recovery.xi       recover_state/store + checkpoint compaction    [EXTRACTED]
|   |-- wal_file.xi       whole-file persist/load (torn-tail safe)       [NEW 2026-10-09]
|   |-- wal_segment.xi    D5 delta segment: codec v1 append + fsync-on-ack + merge [NEW 2026-10-12]
|   |-- snapshot.xi       D6 snapshot export/import (meta-gated; bit-exact restore) [NEW 2026-10-13]
|   |-- manifest_file.xi  collection registry persist/load (temp+rename) [NEW 2026-10-09]
|   +-- (engine) M-D7 multi-segment read path: roll -> union -> compaction   [NEW 2026-10-13]
|   `-- write_ahead_events.xi log_upsert/log_delete/log_payload_set      [EXTRACTED]
|
`-- api/
    |-- vector_api.xi     merged stub -- the facade lives in engine.xi  [MERGED]
    `-- http_service.xi   HTTP/1.1 byte pipeline + router            [NEW 2026-10-09]
`-- observability/
    `-- metrics.xi        histogram + service counters + log ring    [NEW 2026-10-09]
```

### Dependency direction

Higher layers depend on lower layers; there are no upward dependencies:

```
engine (facade) -> engine.core + core.shim (signature types) + value types
engine.core -> { core.shim, query.search_service -> storage.vector_store /
                 payload.filter_eval / query.filter_plan,
                 query.filter_plan -> payload.index (counts),
                 index.ann_index (kind/params), index.hnsw (graph upkeep +
                 search), storage.vector_store, durability.*,
                 payload.*, types.* }
index.flat_index -> query.search_service (delegates exact scan)
index.hnsw -> types.{dense_vector, neighbor, metric} + storage.vector_store
               (graph codec; no query dependency)
index.quantize -> xiom.vectors (distances, magnitude, TopKHeap) +
               storage.vector_store (SQ8 training + codec + query tables +
               the two-tier scan; returns QuantHit, no query dependency;
               reference study 02 Q-a, gates tests/probes/probe_quantization)
collection/* -> types, index.ann_index, core.shim ids
segment/* -> storage.vector_store, segment_state, core.shim ids;
             segment_file -> index.hnsw + payload.payload + durability.wal_file
             (sealed-segment codec; no engine dependency)
api.http_service -> engine facade + engine.core + serialize.json +
             durability.wal_file (parse_int_at) -- transport-agnostic:
             bytes in, bytes out; no sockets in the module
durability -> xiom.wal (registry package 0.1.0; record-vocabulary
             alignment + D5 migration target; docs/XIOM-WAL-ADOPTION.md)
payload.filter_eval -> payload.filter_ast -> payload.payload
durability.manifest_file -> durability.wal_file (shared byte parsers) +
                            xiom.vectors metric codes + index.ann_index (stable codes)
everything fallible -> core.shim (CoreError; the local stand-in until the
                       xiom.core porter flow maps it onto the package)
```

The extraction chain is acyclic: **core.shim <- engine.core <- engine**
(facade). The facade never reaches into the store, and the shim imports
nothing from the vector tree.

`index.hnsw` deliberately returns `Neighbor` (not the query-layer
`SearchResult`) so the index layer never depends on the query layer. The query
layer lowers `Neighbor -> SearchResult`.

## 3. Write path (durable upsert)

```
api.upsert
  `-> engine_upsert
        1. validate: vec.dimension == collection.dimension   (reject early)
        2. WAL-before-ack: log_upsert -> wal_writer_append_payload
           (key = point id, value = ACTIVE collection id (D3 registry),
            payload = [dim, Float64-bits...] via vector_encode)
        3. apply: storage.index_add into the mutable store
        4. metrics: counter_inc(upserts)
        5. ack: Ok(true) to caller
```

Invariant: **no write is acknowledged before its WAL record exists.** The
vector payload is now serialized into the record, so a point can be
reconstructed on recovery. The WAL is in-memory during operation;
`durability.wal_file` (`wal_persist`/`wal_load`) persists it as a whole-file
checkpoint and loads the longest valid record prefix on reopen (torn-tail
safe). The checkpoint swap is atomic: the text lands in `<path>.tmp` and is
moved over the target with `io.rename`, so an interrupted persist leaves the
previous complete file (M-D1 gate `probe_wal_file`). The checkpoint bytes
are built linearly (`append_bytes`; M-G fixed the O(L^2) string builder).
There is still no
fsync/append -- the stdlib fd-syscall gap (`xiom.os.fs_ffi.fsync` is a
documented stub -- see `docs/STDLIB-WISHLIST-XVECTOR.md`), so persistence is
a checkpoint rewrite at quiescent points; the append/fsync delta log remains
the M2 step.

## 3a. Recovery path (reopen)

```
engine_recover(w, dim, metric) / engine_recover_file(w, path, dim, metric)
  `-> registry build          ManifestUpdate records in LSN order:
                              v1 legacy [1, dim, mc, kc, m, efc, efs]
                                    -> "default" (cid 1)
                              v2 config [2, name.., dim, mc, kc, m, efc, efs]
                                    upsert by record value = cid
                              v3 drop   [3, name..]  -> remove cid
                              (no manifest at all -> caller dim/metric as
                              the single "default" collection)
      file overrides (recover_file only)
                              manifest-file entries override configs BY NAME
                              (the registry of record; the D2 first-entry
                              migration rule covers single-collection logs)
      routed replay           data records -> their collection's
                              store/payloads (strict cid routing when any
                              v2/v3 record is present; everything lands in
                              the single collection otherwise, so legacy
                              logs with arbitrary value fields replay)
      per-collection indexes  Hnsw graphs rebuilt from each store
                              (entry_apply_index)
      checkpoint              compacted log: every alive collection's
                              inserts + updates (record value = cid) + one
                              v2 manifest each, fresh monotonic LSNs
```

The checkpoint log alone reconstructs every collection, so a recovered
engine is itself recoverable (chained reopen gated by `probe_collections`
and `probe_kill_recovery`). Threading note: the ACTIVE collection's state
is materialized in the engine's top-level fields for the hot data paths;
`collections` holds one full entry per collection and is refreshed by
`sync_active` before switches and registry-wide reads (entry reads are
snapshot copies -- a validated shape on v0.64.2). Switching therefore
copies the active collection's state once; data operations never copy.
The durable registry travels in `durability.manifest_file` (M-D2/D3):
`save_manifest` persists the whole registry whole-file and atomically;
`open_engine` = `wal_load` + `engine_recover_file`. File-backed reopen
still loads the longest complete-record prefix first (kill/reopen equality
gated by `tests/probes/probe_wal_file.xi`; the registry matrices by
`tests/probes/probe_manifest_file.xi` and `tests/probes/probe_collections.xi`).

## 3b. Metadata write path (payloads)

```
api.set_payload
  `-> engine_set_payload
        1. validate: the point exists (Ok(false) otherwise)
        2. WAL-before-ack: log_payload_set -> payload_encode -> Update record
        3. apply: PayloadStore put/overwrite
        4. ack: Ok(true)
```

Payloads never outlive their point: `engine_delete` removes both the vector
and the metadata record. Float32 payloads are fully gated since the v0.64.1
fix (compiler XVC-C-06); the suite and probes assert float payloads
bit-exactly per build.

Selective delete (M-Q4): `delete_filter` resolves matching ids (index
candidates for Eq/Range/Exists/And-of-these, live-store scan otherwise),
collects them BEFORE mutating (store removal shifts positions), sorts
ascending for a plan-independent WAL order, and routes each through the
same single-delete path (WAL record -> store removal -> graph tombstone ->
payload/index cleanup). The plan choice never changes the durable outcome;
nothing matching is `Ok(0)`.

## 3c. Segment path (seal / restore, M-D4)

```
api.seal_segment
  `-> engine_seal_segment
        1. lifecycle: Mutable -> Sealing -> Sealed via the REAL transition
           table (segment_state_can_transition)
        2. build the sealed record: meta (seg_id/cid/state/dim/metric/
           index kind/params) + every vector (vector_encode words) +
           every payload (payload_encode words) + the Hnsw graph codec
           (hnsw_encode words; Hnsw only)
        3. whole-file atomic write: `<path>.tmp` -> io.rename
           (persist refuses any non-Sealed/Immutable state)

api.restore_segment
  `-> engine_restore_segment
        1. segment_file_load (torn-tail-safe complete-record prefix;
           meta line required; graph optional/best-effort)
        2. validate: cid == active collection, dim + metric match
           (else Err, engine untouched)
        3. swap the live store + payloads (+ decoded graph when Hnsw)
        4. re-checkpoint the WAL (engine_checkpoint_from, LSN-continuous):
           a reopen replays the restored state -- durable before the ack
```

Sealed segments are the immutable on-disk unit: self-describing (config
travels in the meta line), bit-exact (vectors + payloads), and
independently loadable. The codec shares the byte-level discipline of
`wal_file`/`manifest_file` (never handled as a Str; temp+rename; a
41-byte `file_size` guard for the XVC-C-12 family). Wiring sealed segments
into the collection read path (multi-segment scans, retention/pruning) is
D5/D6; today seal/restore is the durable transport. Gate:
`tests/probes/probe_segment_file.xi`.

## 3d. Index admin (M-Q5)

```
api.collection_stats(eng, name)
  `-> active collection: live fields (store/graph/config)
      parked collection: registry entry (synced at park time)
      -> CollectionStats { name; cid; dim; metric; index_kind; ANN params;
                           points; payloads; nodes; tombstones; wal_lsn }

api.rebuild_index(eng)
  `-> Hnsw: fresh graph over LIVE nodes only (tombstones reclaimed)
      Flat: no-op with zeroed graph stats
      -> IndexStats { kind; points; nodes_before; nodes_after; reclaimed }
```

Stats never switch the active collection, so reporting is read-only. The
rebuild is the admin recovery valve for a tombstone-heavy graph;
`compact_index` remains the Int-returning compatibility wrapper over the
same rebuild. Gate: `tests/probes/probe_index_admin.xi`.

## 3e. Service path (M-S1)

```
http_service_handle(eng, raw_bytes) -> response_bytes    (pure, deterministic)

  parse    HTTP/1.1: CRLF framing, method/path/query, lowercased headers,
           Content-Length must match the body EXACTLY
           (incomplete -> 400 "incomplete request"; trailing -> 400);
           JSON bodies pass json_depth_ok(body, 64) first (M-S4 guard
           against the stdlib parser's per-level recursion)
  route    GET  /health | GET/POST /collections
           GET/POST/DELETE /collections/{n}/points
           POST /search   (knn/range/pagination; "requests" array = batch)
           GET  /stats?collection=
           (unknown route 404, wrong method 405)
  JSON     stdlib xiom.serialize.json, calls QUALIFIED (json.json_*):
           the parent xiom.serialize helpers misresolve in this unit
           (BUG 25 #1) -- unqualified calls silently built empty strings
  reply    HTTP/1.1 <status> + Content-Type: application/json +
           Content-Length (byte-exact) + Connection: close
           errors: {"error","kind","status"} with 400/404/405/409/
           413/500/501/507

  limits   ServiceConfig (M-S2): max_request_bytes / max_top_k /
           max_batch / max_dim; defaults + env (XVECTOR_MAX_*) +
           key=value file; enforced in handle_cfg (413 size/batch,
           400 named top_k/dim); handle() = default config

  auth     ServiceAuth (M-S3): API keys via `x-api-key`
           (constant-time compare, xiom.crypto.mac), scopes
           read < write < admin; /health public; 401/403 kinds

  rate     RateLimiter: xiom.rate-backed token bucket (carry-exact
           fractional refill; explicit clock); exhaustion -> 429
           rate_limited

  state    ServiceState { cfg; auth; rate; metrics; log } +
           http_service_handle_state = rate -> parse -> auth/scope ->
           route, instrumented (counters/histograms/log per request;
           metrics copied out + written back once -- XVC-C-09)

  metrics  GET /metrics (public): counters + histograms (cumulative
           buckets, +Inf, p50/p95/p99) + live gauges (collections/
           points_active/lsn); /health carries ready:true

  logs     bounded JSON log ring (method/path/status/ms/slow; sanitized;
           dropped count) -- the socket adapter pipes it out

  shutdown http_service_shutdown(eng, wal_path) = drain (no-op embedded)
           + whole-file WAL checkpoint
```

The module is deliberately transport-agnostic (bytes in, bytes out): the
socket adapter over the stdlib `xiom.net` server binds this same handle
once that lane's proof lands (C-PULSE-02 pending); config/limits/errors
(S2), auth (S3) and the security pass (S4) layer on top. Gate:
`tests/probes/probe_http_service.xi` (40 checks).

## 4. Search path (top-k query)

```
api.search
  `-> engine_search
        1. validate: query.dimension == collection.dimension; is_valid_top_k(k)
        2. route by the collection's index kind (set_index):
             Flat/Ivf -> search_service.search_knn  (exact scan, O(n))
             Hnsw     -> index.hnsw.hnsw_search      (multi-layer greedy
                         descent + beam, ef = ann.ef_search)
        3. filter (Phase 3): Hnsw -> ANN fetch (ef_search wide) then keep the
           matching subset; under-filled -> exact flat filtered scan. Flat ->
           the planner (pre/post/index):
             scan  -> evaluate FilterExpr per candidate BEFORE distance
             post  -> rank all via the flat scan, keep the matching subset;
                      if it does not fill k, fall back to the scan
             index -> Eq/Range/Exists candidates (and And-of-those
                      intersections) from the sorted payload index;
                      distances only for matches (store id map)
           (post for an exact k-or-more majority or a compound upper bound;
            index for an exact count 0 or < total/4; query/filter_plan.xi)
        4. rerank: bounded top-K heap keeps <= k best by distance
        5. (Phase 3) hydrate: attach payloads when with_payload = true
        6. return Ok(SearchHits{ items }) (items.len() <= k, guaranteed)
```

Pagination (M-Q3, `query/pagination.xi`): `search_page`/`search_after`
re-rank through the same raw-store scans under the total order
**(distance asc, id asc)** -- page slices reconstruct the ordered result
set, exact ties come back id-ascending, and the after-id cursor is the
live vector of the last seen id (a deleted cursor is `Err(NotFound)`).
Exact on Flat AND Hnsw; ANN widening stays M-P tuning.

Request dispatch (M-Q6): `SearchRequest.mode` selects the plain/filtered
knn path or the exact range path (`top_k` = inclusive-radius limit, no
filters/pagination); knn requests may carry `offset` (page ranks) or
`after_id` (cursor continuation) -- mutually exclusive, and neither
combines with filters yet. Batch requests (`SearchBatchRequest`) run in
order, all-or-nothing. Dimension/top_k/metric validation is unchanged.

`SearchHits` is a struct wrapper around the result Vec: it was introduced
because on v0.64.0 a `Result[Vec[non-scalar], E]` payload lost element
fields at the caller (finding XVC-C-04, fixed in v0.64.1). The wrapper is
retained deliberately -- zero-cost, stable public API; any unwrap is an API
decision, not a compiler need.

Request-driven variant (Phase 3): `search_with_request` ->
`engine_search_request` takes top_k/filter/with_payload from a
`SearchRequest`, validates the request metric against the active collection,
and optionally hydrates payloads (`hydrate_hits` -> `HydratedHits`,
`SearchHit { id; distance; payload; has_payload }`). NOTE (XVC-C-08): the
trailing `has_payload` after the Vec-bearing payload field can misread in
affected compilation units -- hydration flags are gated in the real-module
probe only (repro: `docs/repro/xv-trailing-field-vec/`).

Multi-segment fan-out (Phase 5) inserts a step 2a: iterate the collection's live
segments from the manifest, search each, and merge into the same top-K heap.

Range search (`search_range`, M-Q1) is a separate exact path: a raw-store scan
keeps every point with `distance <= radius` (inclusive), distance-sorted
ascending, bounded by `limit` (the caller passes it; `is_valid_top_k` bounds
it). The index kind does not change the result -- exact by construction for
both Flat and Hnsw; an ANN-widened variant is M-P tuning, not a correctness
change. Gate: `tests/probes/probe_range_search.xi` (72 radius x limit combos
vs a local brute-force scan + boundary/error/reopen checks).

Batch ops (`upsert_many` / `delete_many` / `search_many`, M-Q2) validate the
whole batch BEFORE applying anything (non-empty, equal lengths, every
dimension matches / k in range), then run the single-point path per element:
upsert returns records applied (duplicate ids collapse like single upserts),
delete is idempotent and returns actual removals, search returns `BatchHits`
(one `SearchHits` per query, order preserved). Gate:
`tests/probes/probe_batch_ops.xi`.

## 5. Reuse-from-core table

| Vector-layer concern | Reuses from `xiom-core` | Why |
|----------------------|-------------------------|-----|
| Error channel        | `error.CoreError`, `core_error_to_str` | one error type across engines; no hidden failure channels |
| Identity             | `ids.CollectionId / VectorId / SegmentId` (+ local `PointId`) | shared id vocabulary; compile-time separation of id kinds |
| Guardrails           | `limits.max_dimensions / max_top_k / max_graph_degree` | ceilings can't drift between subsystems |
| Predicates           | `contracts.is_valid_dimension / is_valid_top_k` | `requires:`/`ensures:` stay in sync with runtime checks |
| Durability           | `wal.wal_writer` (`wal_writer_new/append`) | one WAL format -> one recovery parser |
| Observability        | `metrics.Counter`, `counter_inc` | uniform metrics registry |
| Config               | `config.CoreConfig`, `core_config_default` | single startup profile |

## 6. Contract hotspots

The places where correctness is enforced in code (and documented in
`docs/contracts-and-invariants.md`):

- **Dimension constancy** -- `collection.validator.validate_vector`,
  `engine_upsert`/`engine_search`, and every `vector_distance` kernel
  `requires: a.dimension == b.dimension`.
- **Bounded results** -- `search_knn` / `hnsw_search` / `search_execute`
  `ensures: result.len() <= k`; `topk_heap.topk_push`
  `ensures: items.len() <= capacity`.
- **Graph degree** -- HNSW neighbour selection bounds each node's adjacency
  by the layer cap: `m` on levels >= 1, `m0` (default `2*m`, generous
  level 0; `m <= core.limits.max_graph_degree()` so `m0 <= 1024`).
- **Segment lifecycle** -- `segment_state.segment_state_can_transition` is the
  single source of truth for legal state moves.
- **WAL-before-ack** -- `engine_upsert`/`engine_delete` append to the WAL before
  mutating the store.

## 7. Failure domains

| Domain | Failure | Handling |
|--------|---------|----------|
| Input validation | wrong dimension, bad top_k, unknown metric | reject with `CoreError.InvalidInput` / `VectorError` **before** any state change |
| Durability | WAL append/flush fault | surfaces as `CoreError.IOFailure` (retryable); write is **not** acked |
| Storage | duplicate id on insert | `index_add` returns `false` (idempotent upsert semantics in Phase 2) |
| Index | empty graph / cold search | returns an empty result set, never panics |
| Recovery | truncated/corrupt WAL tail (memory) | in-memory replay: malformed payloads are skipped (`vector_decode -> None`), later valid records still replayed; LSNs stay monotonic. |
| Recovery | truncated/corrupt WAL file | `wal_load` returns the longest prefix of complete valid records (torn-tail safe); missing/garbage/empty files -> empty; a kill mid-checkpoint yields the previous consistent prefix. Appending to an existing file waits on the stdlib append-bytes gap. |
| Segment | write to a sealed segment | `VectorError.SegmentSealed` (enforced Phase 5) |

Each domain fails as an explicit `Result` value -- XIOM has no exceptions, so
every caller must handle the failure.
