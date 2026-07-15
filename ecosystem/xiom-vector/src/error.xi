module xiom.vector.error

// Local CoreError type — mirrors xiom.core.error.CoreError.
pub enum CoreError {
  NotFound,
  InvalidInput(msg: Str),
  OutOfBounds,
  Corruption(msg: Str),
  IOFailure(msg: Str),
  Unsupported(msg: Str),
  CapacityExceeded,
  InvalidState(msg: Str),
  ChecksumMismatch,
  VersionMismatch,
}

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