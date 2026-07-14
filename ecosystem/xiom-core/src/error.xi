module xiom.core.error

// Canonical error type shared by every xiom-core subsystem and by the
// downstream engines (xiom-db, xiom-vector). XIOM models errors as types, so
// there are no hidden failure channels: engine functions return
// `Result[T, CoreError]` and callers must handle the failure explicitly.

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

// Human-readable, stable description for logs and error catalogs.
pub fn core_error_to_str(e: &CoreError) -> Str {
  match e {
    NotFound => "not found",
    InvalidInput(_) => "invalid input",
    OutOfBounds => "index out of bounds",
    Corruption(_) => "data corruption detected",
    IOFailure(_) => "io failure",
    Unsupported(_) => "operation not supported",
    CapacityExceeded => "capacity exceeded",
    InvalidState(_) => "invalid state transition",
    ChecksumMismatch => "checksum mismatch",
    VersionMismatch => "format version mismatch",
  }
}

// Only transient IO faults are worth retrying. Logical errors (NotFound,
// InvalidInput, Corruption, ...) are deterministic and must not be retried.
pub fn core_error_is_retryable(e: &CoreError) -> Bool {
  match e {
    NotFound => false,
    InvalidInput(_) => false,
    OutOfBounds => false,
    Corruption(_) => false,
    IOFailure(_) => true,
    Unsupported(_) => false,
    CapacityExceeded => false,
    InvalidState(_) => false,
    ChecksumMismatch => false,
    VersionMismatch => false,
  }
}
