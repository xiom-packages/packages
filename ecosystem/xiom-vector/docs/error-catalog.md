# Error Catalog

`xiom-vector` follows the XIOM rule that **errors are values** — every fallible
API returns `Result[T, CoreError]` (or `Option[T]` for simple lookups). There
are no exceptions and no hidden failure channels.

Two error types are in play:

- `xiom.core.error.CoreError` — the shared cross-engine error the public API and
  storage/WAL boundaries speak.
- `xiom.vector.error.VectorError` — the vector-specific taxonomy, which maps onto
  `CoreError` via `vector_error_to_core`.

## VectorError (`src/error.xi`)

| Variant | Code | `to_str` | Maps to `CoreError` | Raised when |
|---------|------|----------|---------------------|-------------|
| `DimensionMismatch(expected, got)` | 1001 | "vector dimension mismatch" | `InvalidInput` | a vector's dimension ≠ the collection dimension |
| `UnsupportedMetric(name)` | 1002 | "unsupported distance metric" | `Unsupported` | a metric not valid for the schema is requested |
| `CollectionNotFound(id)` | 1003 | "collection not found" | `NotFound` | an operation targets an unknown collection |
| `InvalidVector(msg)` | 1004 | "invalid vector" | `InvalidInput` | a vector is malformed (e.g. schema dim out of range) |
| `SegmentSealed(id)` | 1005 | "segment is sealed" | `InvalidState` | a write targets a non-mutable segment (Phase 5) |
| `TopKExceeded(requested, max)` | 1006 | "top_k exceeds maximum" | `CapacityExceeded` | `k > max_top_k()` |

Helpers: `vector_error_to_str`, `vector_error_to_core`, `vector_error_code`
(stable numeric codes for the wire/FFI boundary).

## CoreError (from `xiom.core.error`) as surfaced by the API

The public facade (`api/vector_api`) and `engine` return `CoreError` directly:

| `CoreError` | Retryable? | Surfaced by | Meaning here |
|-------------|-----------|-------------|--------------|
| `InvalidInput(msg)` | no | `engine_create_collection`, `engine_upsert`, `engine_search` | bad dimension, bad `top_k`, malformed request |
| `NotFound` | no | (Phase 5) collection/point lookups | target does not exist |
| `Unsupported(msg)` | no | metric validation | operation/metric not supported |
| `CapacityExceeded` | no | `top_k` / limit checks | a shared limit was exceeded |
| `InvalidState(msg)` | no | segment transitions | illegal lifecycle transition / sealed write |
| `IOFailure(msg)` | **yes** | WAL flush (Phase 2) | transient IO fault; safe to retry |
| `Corruption(msg)` | no | recovery (Phase 2) | WAL/segment data corruption |
| `ChecksumMismatch` | no | recovery (Phase 2) | page/record checksum failed |
| `VersionMismatch` | no | recovery (Phase 2) | on-disk format version mismatch |
| `OutOfBounds` | no | internal invariants | index out of range (should be prevented by contracts) |

`core_error_is_retryable` classifies these: only `IOFailure` is retryable —
logical errors are deterministic and must not be retried.

## Where each error originates

| Operation | Possible failures |
|-----------|-------------------|
| `create_collection` | `InvalidInput` (dimension out of range) |
| `upsert` | `InvalidInput` (dimension mismatch); Phase 2: `IOFailure` (WAL) |
| `search` | `InvalidInput` (dimension mismatch, `top_k` out of range) |
| `delete_point` | Phase 2: `IOFailure` (WAL) |
| `get_point` | returns `Option[Vector]` — `None` for a missing id (not an error) |
| `validate_vector` | `VectorError.InvalidVector`, `VectorError.DimensionMismatch` |
| `validate_metric` | `VectorError.UnsupportedMetric` (all built-ins currently supported) |
| segment ops (Phase 5) | `VectorError.SegmentSealed` → `InvalidState` |

## Handling pattern

```xiom
var r = search(&eng, &query, k);
match r {
  Ok(hits) { /* use hits; hits.len() <= k is guaranteed */ }
  Err(e) {
    // e: CoreError. Retry only if core_error_is_retryable(&e).
    return 1;
  }
}
```

## Design notes

- **One error type crosses boundaries.** `VectorError` exists for precise
  vector-domain reporting, but everything that reaches the public API is lowered
  to `CoreError` so callers integrate with one error channel across xiom-db,
  xiom-vector, and xiom-core.
- **Contracts prevent, errors report.** Invariants in
  [`contracts-and-invariants.md`](contracts-and-invariants.md) reject bad input
  at the boundary (returning an error) so internal states like `OutOfBounds`
  should never actually occur in a correct build.
- **Stable numeric codes** (`vector_error_code`) exist for FFI/wire use where a
  tagged union is inconvenient to serialize.
