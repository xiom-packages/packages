# Core vs Vector: what is reused, and why

`xiom-vector` sits on top of `xiom-core`, the shared durable-systems substrate
used across the XIOM data ecosystem. This document states precisely which
concerns are delegated to core and which are genuinely vector-specific.

## Principle

> Anything that must mean the same thing in every engine lives in `xiom-core`.
> Only vector-specific logic lives in `xiom-vector`.

Forking core concepts (a second error type, a second WAL format, a second set of
limits) would create drift: recovery would need to parse multiple log shapes, a
`CoreError` would be ambiguous, and guardrails could disagree. So we reuse.

## Reuse map

| Concern | Core module | What vector uses | Vector module that consumes it |
|---------|-------------|------------------|--------------------------------|
| Errors | `xiom.core.error` | `CoreError`, `core_error_to_str` | `error` (bridges `VectorError → CoreError`), `engine`, `api`, `validator` |
| Identity | `xiom.core.ids` | `CollectionId`, `VectorId`, `SegmentId` (+ constructors/eq) | `ids` (adds `PointId`), `collection`, `segment`, `manifest`, `engine` |
| Limits | `xiom.core.limits` | `max_dimensions`, `max_top_k`, `max_graph_degree` | `types.dimension`, `index.ann_index`, `engine` |
| Predicates | `xiom.core.contracts` | `is_valid_dimension`, `is_valid_top_k` | `types.dimension`, `collection.schema`, `collection.validator`, `engine` |
| Config | `xiom.core.config` | `CoreConfig`, `core_config_default` | engine startup (Phase 2) |
| Durability | `xiom.core.wal.wal_writer` | `WalWriter`, `wal_writer_new`, `wal_writer_append` | `durability.write_ahead_events`, `engine` |
| WAL format | `xiom.core.wal.wal_record` | `WalOpKind` (Insert/Delete/SegmentSeal/ManifestUpdate) | `durability.write_ahead_events` |
| Metrics | `xiom.core.metrics` | `Counter`, `counter_inc`, `counter_new` | `engine` |

## What is vector-specific (lives here, not in core)

- **Value types** — `Vector`, `Neighbor`, `Dimension` and all vector math.
- **Distance** — the three metrics + kernels; nothing else in XIOM needs them.
- **Indexes** — flat baseline and HNSW graph; ANN is the whole point of this engine.
- **Query** — top-K semantics, request modelling, index dispatch.
- **Collections & schema** — dimension/metric binding, payload field specs.
- **Payload & filtering** — the `FieldValue`/`FilterExpr` model.
- **Segment semantics** — while the *WAL format* is core, the *meaning* of an
  upsert/seal event (a vector event) is vector-specific and lives in
  `durability.write_ahead_events`.

## The WAL boundary (a subtle split)

The WAL is the clearest example of the split:

- **Core owns the format and the writer.** `WalRecord` has one shape
  (`lsn, op, key, value, payload, timestamp`) and one `WalWriter`. Recovery in
  core parses exactly that.
- **Vector owns the semantics.** `write_ahead_events` decides that an upsert is a
  `WalOpKind.Insert` whose `key` is the collection and `value` is the point id,
  and (Phase 2) that the dense vector bytes go into `WalRecord.payload`.

This way, xiom-db and xiom-vector both extend the operation set through tagged
payloads rather than forking the record layout — one recovery parser serves all.

## Identity: why `PointId` is separate from `VectorId`

`VectorId` (core) is an internal storage handle — effectively a slot. `PointId`
(vector) is the stable, user-facing id of a logical point. Keeping them as
distinct single-field wrapper types means the compiler rejects passing one where
the other is expected, even though both wrap an `Int`. The `ids` module provides
explicit `point_to_vector_id` / `vector_to_point_id` bridges so the conversion
is always deliberate.
