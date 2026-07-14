# xiom-vector — Collections

A **collection** is the user-facing container for vectors that share a schema.
It is the level at which you create, upsert, search, and delete. This document
describes the collection model as seen by an application developer; the engine
internals are in [`ARCHITECTURE.md`](ARCHITECTURE.md).

## The mental model

```
Collection
├── schema            (fixed at creation)
│   ├── dimension       every vector must have exactly this many components
│   ├── metric          Cosine | DotProduct | Euclidean
│   ├── normalization   Raw | L2Normalized
│   └── payload_fields  named, optionally-indexed metadata fields
├── index config      AnnIndexKind (Flat | Hnsw | Ivf) + AnnParams
└── points            (id, vector, payload) rows stored across segments
```

A **point** is one row: a stable integer `PointId`, its dense `Vector`, and an
optional `Payload` of metadata.

## Creating a collection

```xiom
use xiom.vector.engine;
use xiom.vector.api.vector_api;
use xiom.vector.types.metric;

var eng = engine_new();
var cid = create_collection(&mut eng, 768, DistanceMetric.Cosine);
```

`create_collection` fixes the **dimension** and **metric**. Both are immutable
for the life of the collection — this is the core "dimension is constant"
invariant (see [`docs/contracts-and-invariants.md`](docs/contracts-and-invariants.md)).
Attempting to upsert a vector of a different dimension is rejected before any
state changes.

## Schema fields

| Field | Type | Meaning |
|-------|------|---------|
| `dimension` | `Int` | Component count of every vector. Must satisfy `is_valid_dimension` (1 … `max_dimensions()`). |
| `metric` | `DistanceMetric` | Distance used for ranking. |
| `normalization` | `NormalizationMode` | `Raw` stores vectors as-is; `L2Normalized` (Phase 3) unit-normalizes on write so cosine == dot. |
| `payload_fields` | `Vec[PayloadFieldSpec]` | Named metadata fields; `indexed: true` marks a field for fast filtering (Phase 3). |

`CollectionSchema` lives in `src/collection/schema.xi`; `schema_new(dim, metric)`
constructs it and `schema_add_field(&mut s, name, indexed)` declares payload
fields.

## Choosing a metric

| Metric | Use when | Distance formula |
|--------|----------|------------------|
| `Cosine` | Direction matters, magnitude does not (most text embeddings). | `1 − (a·b)/(‖a‖‖b‖)` |
| `DotProduct` | Vectors are pre-normalized, or magnitude encodes importance. | `−(a·b)` |
| `Euclidean` | Absolute position in space matters. | `√Σ(aᵢ−bᵢ)²` |

For all three, **smaller = closer**, so the same top-K logic works regardless of
metric.

## Choosing an index

| Kind | When | Trade-off |
|------|------|-----------|
| `Flat` | Small collections, or when exact results are required. | O(n) per query, 100% recall (the oracle). |
| `Hnsw` | Large collections needing low-latency approximate search. | Sub-linear query, tunable recall via `AnnParams` (`m`, `ef_construction`, `ef_search`). |
| `Ivf` | Billion-scale (Phase 9). | Coarse-quantized cells; highest scale, lowest memory. |

The engine currently answers via the exact flat scan; `search_execute` in the
query layer already routes by `AnnIndexKind`, so switching a collection to HNSW
is a configuration change, not an API change.

## Payload & filtering (Phase 3)

Each point may carry a `Payload` — a set of `(key, FieldValue)` fields where
`FieldValue` is one of `IntVal`, `FloatVal`, `TextVal`, `BoolVal`. Searches will
accept a `FilterExpr` tree (`Eq`, `Range`, `Exists`, `In`, `And`, `Or`, `Not`)
evaluated against each candidate's payload. Today the boolean combinators and
`Exists` are implemented; value predicates are fail-open stubs. See
[`docs/metadata-filtering.md`](docs/metadata-filtering.md).

## Lifecycle of a point

```
upsert(point, vector)
  → WAL append (durable)               [Phase 2 makes this fsync]
  → stored in the collection's mutable segment
  → (Phase 5) segment seals → immutable HNSW built → searchable
search(query, k) → point appears in ranked results
delete_point(point) → WAL append + removed from store
```

## Limits

Enforced via `xiom.core.limits`:
- Dimension: `1 … max_dimensions()` (65536).
- top_k: `1 … max_top_k()` (10000).
- HNSW degree: `≤ max_graph_degree()` (512).
