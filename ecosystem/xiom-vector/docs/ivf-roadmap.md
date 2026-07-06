# IVF / PQ Design (Scale Tier)

`src/index/ivf/`, `src/index/pq/`, `src/index/rerank/` (planned) — the
memory-efficiency scale path for large collections. NOT IMPLEMENTED: this is
Phase 9 in [`../ROADMAP.md`](../ROADMAP.md). The `AnnIndexKind.Ivf` dispatch seam
already exists in `index/ann_index.xi`; the modules below fill it in.

## Purpose

IVF (Inverted File) and PQ (Product Quantization) are the
**memory-efficiency scale path** for large collections, where keeping a full
in-memory HNSW graph becomes too expensive. They are introduced deliberately
**after** HNSW and exact search are stable — the flat index stays the truth
oracle, HNSW is the general-purpose ANN, and IVF/PQ is the billion-scale tier
layered on top of proven foundations.

- **IVF** partitions the vector space into coarse cells and only scans a few
  cells per query, trading a little recall for a large reduction in work.
- **PQ** compresses each vector into a short code, so far more vectors fit in the
  same RAM and distances can be estimated from codes rather than full vectors.

## When to prefer IVF/PQ over HNSW

Choose IVF/PQ when **RAM cost and large-scale serving dominate** the design.
HNSW's memory overhead (the proximity graph plus full vectors) grows materially
with scale; past a certain collection size the graph itself becomes the
bottleneck. At that point IVF's cell-scan model plus PQ's compressed codes serve
far more vectors per node than an equivalent HNSW graph.

| Prefer HNSW when… | Prefer IVF/PQ when… |
|-------------------|---------------------|
| Collection fits comfortably in RAM. | RAM cost / vectors-per-node dominates. |
| Highest recall at low latency is the priority. | Large-scale serving economics dominate. |
| Graph memory overhead is acceptable. | HNSW graph overhead is the bottleneck. |

## IVF tuning heuristics (CRITICAL — preserve exactly)

- **`nlist ≈ sqrt(N)`** where `N` is the collection size. This sets the number of
  coarse cells (inverted lists) so each list holds roughly `sqrt(N)` vectors.
- **`nprobe`** starts small and is **increased until recall targets are met**.
  It controls how many of the `nlist` cells are scanned per query.
- **Higher `nprobe` = better recall, higher latency.** Tuning is the search for
  the smallest `nprobe` that hits the recall target for the workload.

## IVF modules (planned)

| Module | Purpose |
|--------|---------|
| `ivf_index.xi` | Top-level IVF index: owns the coarse quantizer, inverted lists, and search entry point. |
| `centroid_store.xi` | Centroid persistence + versioning (the coarse cell centroids, durably stored and format-versioned). |
| `coarse_quantizer.xi` | Training + assignment: learns coarse centroids and assigns each vector to its nearest coarse cluster. |
| `ivf_search.xi` | `nprobe`-driven search: pick the `nprobe` closest cells to the query and scan only their inverted lists. |
| `ivf_params.xi` | Typed IVF tuning params (`nlist`, `nprobe`, …) with compile-time + runtime validation. |

## PQ modules (planned)

| Module | Purpose |
|--------|---------|
| `codebook.xi` | Trained PQ codebooks + format versioning (the sub-quantizer centroids used to encode vectors). |
| `pq_codec.xi` | Encode/decode PQ representations (full vector ↔ compact PQ code). |
| `adc_search.xi` | Asymmetric Distance Computation: estimate query-to-vector distance from PQ codes via precomputed lookup tables. |
| `pq_params.xi` | Validated quantization settings (number of sub-quantizers, bits per code, …). |

## Rerank modules (planned)

IVF/PQ produce an approximate shortlist; reranking recovers precision.

| Module | Purpose |
|--------|---------|
| `exact_rerank.xi` | Recompute true similarity on the shortlisted candidates using full vectors, correcting PQ estimation error. |
| `candidate_heap.xi` | Top-K heap for the shortlist with strict `len() <= k` bounds and score-ordering invariants. |

## Contract hotspots for IVF/PQ

- **Impossible parameter combinations are rejected early** — invalid metric/index
  or quantization/metric pairings fail at construction, not mid-query.
- **`nlist` / `nprobe` are validated against collection size** — e.g. `nprobe`
  cannot exceed `nlist`, and degenerate `nlist` values are refused.
- **Codebook format is versioned** — a code written under one codebook format is
  never silently decoded under another; version mismatch is a typed error.

## XIOM showcase

IVF/PQ is a strong demonstration of XIOM's typed-parameter approach: `ivf_params`,
`pq_params`, and the metric types combine **compile-time typing with runtime
contract validation** so that invalid metric/index combinations and out-of-range
tuning values are impossible to construct — errors surface at the boundary rather
than as silent recall loss deep inside a query.

## Related

- [`hnsw-design.md`](hnsw-design.md) — the general-purpose ANN this tier sits behind.
- [`vector-types-and-metrics.md`](vector-types-and-metrics.md) — the metrics IVF/PQ must stay compatible with.
- [`contracts-and-invariants.md`](contracts-and-invariants.md) — how parameter validation is expressed in code.
- [`../ROADMAP.md`](../ROADMAP.md) — Phase 9 status and exit criteria.
