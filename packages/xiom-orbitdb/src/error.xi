// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom.db.error

// Typed error domain for xiom-db. Every fallible database operation returns a
// `DbResult[T]` so there are no hidden failure channels -- callers must discharge
// the failure explicitly. `DbError` is intentionally coarse-grained and stable.
//
// The legacy `xiom.core.error.CoreError` boundary fold is RETIRED (2026-10-10):
// the substrate package was never published, so the fold's parameter type did
// not exist; the checker tolerated the phantom reference until the hybrid
// probe put a same-named foreign `CoreError` in the catalog. Re-introduce the
// fold when `xiom-core` publishes (vector of that decision: D3 session notes).

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

// The canonical fallible-return convention for the whole package.
pub type DbResult[T] = Result[T, DbError];
