# xiom-sqlite — SPEC

**Phase**: 1 (Core Foundation) | **Priority**: HIGH
**Status**: SPEC only — no implementation yet
**Depends on**: xiom.ffi (stdlib)

## What it wraps
SQLite — embedded SQL database engine (C API).
Single-file, zero-config, public domain.

## Dependencies

| What | How | Size |
|------|-----|------|
| SQLite | System installed OR bundled as amalgamation. `sqlite3.c` is a single 8MB file. | ~2MB .dll |
| C compiler | For building bridge | — |

## Bundling strategy
**Hybrid.** SQLite amalgamation (`sqlite3.c` + `sqlite3.h`) can be compiled into the bridge .obj, making xiom-sqlite truly zero-dependency. Users don't need to install SQLite separately. Alternatively, link against system `sqlite3.dll`.

## API surface

```xiom
module xiom.sqlite

// Database
pub fn open(path: Str) -> Result[DB, Str]
pub fn close(db: DB)
pub fn exec(db: &DB, sql: Str) -> Result[Unit, Str]

// Prepared statements
pub fn prepare(db: &DB, sql: Str) -> Result[Stmt, Str]
pub fn stmt_bind_int(s: &mut Stmt, idx: Int, val: Int)
pub fn stmt_bind_float(s: &mut Stmt, idx: Int, val: Float64)
pub fn stmt_bind_text(s: &mut Stmt, idx: Int, val: Str)
pub fn stmt_bind_null(s: &mut Stmt, idx: Int)
pub fn stmt_step(s: &mut Stmt) -> Result[Bool, Str]  // true = has row
pub fn stmt_column_int(s: &Stmt, idx: Int) -> Int
pub fn stmt_column_float(s: &Stmt, idx: Int) -> Float64
pub fn stmt_column_text(s: &Stmt, idx: Int) -> Str
pub fn stmt_finalize(s: Stmt)

// Transactions
pub fn begin_transaction(db: &DB)
pub fn commit(db: &DB)
pub fn rollback(db: &DB)
```

## Contract coverage target
- Database path: `requires: path.len() > 0`
- Statement: `requires: s != 0`
- Column index: `requires: idx >= 0 && idx < stmt.column_count()`
- SQL injection: parameterized queries (no string concatenation)

## Phased roadmap

| Phase | What | Effort |
|-------|------|--------|
| 1 | Open/close/exec, prepared statements, bind, step, column | Day |
| 2 | Transactions, backup, blob I/O | Day |
| 3 | User-defined functions, virtual tables | Weekend |
