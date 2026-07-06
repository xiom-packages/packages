module xiom.vector.error

use xiom.core.error;

// Vector-layer error taxonomy. These are the domain-specific failures the
// engine raises; each maps onto a shared xiom.core.error.CoreError so that
// callers holding a CoreError channel (WAL, storage) still get a single,
// uniform error type. XIOM models errors as values — there are no hidden
// failure channels — so every fallible API returns Result[T, _] explicitly.

pub enum VectorError {
  DimensionMismatch(expected: Int, got: Int),
  UnsupportedMetric(name: Str),
  CollectionNotFound(id: Int),
  InvalidVector(msg: Str),
  SegmentSealed(id: Int),
  TopKExceeded(requested: Int, max: Int),
}

pub fn vector_error_to_str(e: &VectorError) -> Str {
  match e {
    DimensionMismatch(_, _) => "vector dimension mismatch",
    UnsupportedMetric(_) => "unsupported distance metric",
    CollectionNotFound(_) => "collection not found",
    InvalidVector(_) => "invalid vector",
    SegmentSealed(_) => "segment is sealed",
    TopKExceeded(_, _) => "top_k exceeds maximum",
  }
}

// Bridge to the shared core error type used by storage/WAL boundaries.
pub fn vector_error_to_core(e: &VectorError) -> CoreError {
  match e {
    DimensionMismatch(_, _) => CoreError.InvalidInput("dimension mismatch"),
    UnsupportedMetric(_) => CoreError.Unsupported("distance metric"),
    CollectionNotFound(_) => CoreError.NotFound,
    InvalidVector(_) => CoreError.InvalidInput("invalid vector"),
    SegmentSealed(_) => CoreError.InvalidState("segment sealed"),
    TopKExceeded(_, _) => CoreError.CapacityExceeded,
  }
}

// Stable numeric codes for the wire/FFI boundary (see docs/error-catalog.md).
pub fn vector_error_code(e: &VectorError) -> Int {
  match e {
    DimensionMismatch(_, _) => 1001,
    UnsupportedMetric(_) => 1002,
    CollectionNotFound(_) => 1003,
    InvalidVector(_) => 1004,
    SegmentSealed(_) => 1005,
    TopKExceeded(_, _) => 1006,
  }
}
