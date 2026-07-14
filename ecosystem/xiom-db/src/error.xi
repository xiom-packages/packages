module xiom.db.error
use xiom.core.error;

// Typed error domain for xiom-db. Every fallible database operation returns a
// `DbResult[T]` so there are no hidden failure channels — callers must discharge
// the failure explicitly. `DbError` is intentionally coarse-grained and stable;
// richer diagnostics travel in the message-carrying `xiom.core.error.CoreError`
// that lower layers raise and that `db_error_from_core` folds into this domain.

pub enum DbError {
  NotFound,
  DuplicateKey,
  ConstraintViolation,
  SchemaMismatch,
  StorageError,
  Corruption,
}

// Stable, human-readable description for logs and the error catalog.
pub fn DbError.to_string(err: DbError) -> Str {
  match err {
    NotFound => "not found",
    DuplicateKey => "duplicate key",
    ConstraintViolation => "constraint violation",
    SchemaMismatch => "schema mismatch",
    StorageError => "storage error",
    Corruption => "data corruption",
  }
}

// Logical errors are deterministic and must never be retried; only storage
// faults that originate from a transient IO failure are retry candidates.
pub fn DbError.is_retryable(err: DbError) -> Bool {
  match err {
    NotFound => false,
    DuplicateKey => false,
    ConstraintViolation => false,
    SchemaMismatch => false,
    StorageError => true,
    Corruption => false,
  }
}

// Fold a lower-level xiom-core failure into the database error domain so the
// public API surface only ever exposes `DbError`.
pub fn db_error_from_core(e: &CoreError) -> DbError {
  match e {
    NotFound => DbError.NotFound,
    InvalidInput(_) => DbError.ConstraintViolation,
    OutOfBounds => DbError.StorageError,
    Corruption(_) => DbError.Corruption,
    IOFailure(_) => DbError.StorageError,
    Unsupported(_) => DbError.SchemaMismatch,
    CapacityExceeded => DbError.StorageError,
    InvalidState(_) => DbError.ConstraintViolation,
    ChecksumMismatch => DbError.Corruption,
    VersionMismatch => DbError.SchemaMismatch,
  }
}

// The canonical fallible-return convention for the whole package.
pub type DbResult[T] = Result[T, DbError];
