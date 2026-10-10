# xiom.ann roadmap

Phase-2 items are deliberately out of scope for the 0.1.0 extraction; nothing
here changes the frozen surface.

| Stage | Item | Gate |
| --- | --- | --- |
| reconciliation | XVECTOR consumes `xiom.ann` at its consumption step; its `src/index/ann_index.xi` and `src/index/hnsw.xi` become the fold-in targets to delete there (order handled in the XVECTOR lane) | separate sequenced lane step; this package never edits XVECTOR |
| surface | flat `VectorIndex` store (insert/search/delete-by-id, upsert) -- intentionally not extracted (frozen surface has no store); the `flat_search` oracle here is scan-only over caller-owned arrays | `xiom.db` / `xiom.ann` follow-on if demanded |
| surface | IVF index kind (`AnnIndexKind.Ivf` is code-only today: the discriminant and code 3 are on-disk format; no IVF implementation exists in the reference) | consumer demand |
| surface | range/batch search wrappers over `flat_search`/`hnsw_search` | consumer demand |
| durability | wire `hnsw_encode`/`hnsw_decode` into WAL/file manifests (record kinds, LSN order) on top of `xiom.vectors` value codec and `xiom.wal` | consumer demand (XVECTOR/`xiom.db`) |
| tests | fold the recall probe into the ops-lane sweep / Linux lane | ops lane scheduling |
| surface | SIMD/batch distance kernels once the toolchain exposes vector builtins | compiler intrinsic row |
