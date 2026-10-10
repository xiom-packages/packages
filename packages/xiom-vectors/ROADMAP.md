# xiom.vectors roadmap

Phase-2 items are deliberately out of scope for the 0.1.0 extraction; nothing
here changes the frozen surface (no engine, no indexes).

| Stage | Item | Gate |
| --- | --- | --- |
| reconciliation | XVECTOR consumes `xiom.vectors` at its consumption step; its `src/types/{dense_vector,metric,neighbor,dimension}.xi`, `src/query/topk_heap.xi` and the `src/storage/vector_store.xi` codec become the fold-in targets to delete there (order handled in the XVECTOR lane) | separate sequenced lane step; this package never edits XVECTOR |
| surface | flat `VectorIndex` store (insert/search/delete-by-id, upsert) -- intentionally not extracted (frozen surface has no indexes); lands with `xiom.ann` if demanded | `xiom.ann` lane |
| surface | ANN structures (flat scan, HNSW, range/batch search) | `xiom.ann` lane |
| durability | file-level WAL replay wiring (record kinds, LSN order) on top of `vectors_replay_into` and `xiom.wal` | consumer demand (XVECTOR/`xiom.db`) |
| durability | checksummed codec v2 (backward-readable) | stdlib byte-IO/fsync row |
| tests | fold the codec probe into the ops-lane sweep / Linux lane | ops lane scheduling |
| surface | SIMD/batch distance kernels (dot/L2 over slices) once the toolchain exposes vector builtins | compiler intrinsic row |
