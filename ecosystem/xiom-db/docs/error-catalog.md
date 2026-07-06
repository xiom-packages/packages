# Error Catalog

xiom-db exposes exactly one public error type, `DbError` (`xiom.db.error`). Every fallible internal operation returns `DbResult[T] = Result[T, DbError]`. Lower layers may raise `xiom.core.error.CoreError`; `db_error_from_core` folds those into `DbError` at the boundary so callers never juggle two vocabularies.

## `DbError` variants

| Variant | Meaning | Where it occurs | Retryable? |
|---------|---------|-----------------|-----------|
| `NotFound` | The requested key/row/table does not exist. | Normally expressed as `Option::None` in hot paths (`db_get`, `engine_get`). Reserved as an explicit error for catalog lookups and future typed APIs. | No |
| `DuplicateKey` | An insert would violate key uniqueness. | Index/unique-constraint paths. `btree_insert` currently signals this as a `false` return (idempotent insert); the typed variant is used by unique secondary indexes (Phase 3) and unique-column validation. | No |
| `ConstraintViolation` | A value breaks a declared constraint. | `schema_validator.validate_schema` (duplicate column names); folded from `CoreError.InvalidInput` / `InvalidState`. Phase 4 adds NOT NULL / type constraints. | No |
| `SchemaMismatch` | A definition or operation is incompatible with the schema. | `schema_validator.validate_schema` (no columns, primary key out of range), `validate_column` (empty name), `validate_index` (wrong table / out-of-range column). Folded from `CoreError.Unsupported` / `VersionMismatch`. | No |
| `StorageError` | A storage-layer fault. | Reserved for the durable pager/WAL (Phase 1–2). Folded from `CoreError.IOFailure`, `OutOfBounds`, `CapacityExceeded`. **The only retryable class.** | **Yes** |
| `Corruption` | Data failed an integrity check. | `Page.is_valid()` checksum mismatch; `tuple_decode` malformed framing. Folded from `CoreError.Corruption` / `ChecksumMismatch`. | No |

## Helpers

- `DbError.to_string(err)` → stable human-readable text (`"not found"`, `"duplicate key"`, `"constraint violation"`, `"schema mismatch"`, `"storage error"`, `"data corruption"`). Use in logs and diagnostics.
- `DbError.is_retryable(err)` → `true` only for `StorageError`. Logical and integrity errors are deterministic and must never be retried.
- `db_error_from_core(e: &CoreError) -> DbError` → the boundary fold:

| `CoreError` | → `DbError` |
|-------------|-------------|
| `NotFound` | `NotFound` |
| `InvalidInput(_)` | `ConstraintViolation` |
| `OutOfBounds` | `StorageError` |
| `Corruption(_)` | `Corruption` |
| `IOFailure(_)` | `StorageError` |
| `Unsupported(_)` | `SchemaMismatch` |
| `CapacityExceeded` | `StorageError` |
| `InvalidState(_)` | `ConstraintViolation` |
| `ChecksumMismatch` | `Corruption` |
| `VersionMismatch` | `SchemaMismatch` |

## Error-handling conventions

- **Absence is not an error in the hot path.** `db_get` / `engine_get` return `Option[Int]`; a missing key is `None`, not `DbError.NotFound`.
- **Success/failure booleans** are used by mutating facade/engine calls (`db_insert`, `engine_delete`, ...) where the only outcomes are applied / not-applied. A closed `Database` also returns the safe-default (`false` / `None` / empty vec).
- **`DbResult[T]`** is used wherever a specific failure reason matters to the caller: the tuple codec (`tuple_decode`) and all `schema_validator.*` functions.
- **No silent failures.** Every failure is either encoded in the return type or folded through `db_error_from_core`; there are no hidden panics or ignored errors.

## Failure domains

| Domain | Variants | Detected at | Recovery |
|--------|----------|-------------|----------|
| Absence | `NotFound` | read paths | normal control flow |
| Logic / input | `DuplicateKey`, `ConstraintViolation`, `SchemaMismatch` | catalog, index, query | reject the operation; never retry |
| Integrity | `Corruption` | `Page.is_valid`, `tuple_decode` | fatal for the affected object; never retry |
| Storage | `StorageError` | pager / WAL (Phase 1–2) | retry transient IO |
