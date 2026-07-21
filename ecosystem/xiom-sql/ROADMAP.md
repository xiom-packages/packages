# ROADMAP: xiom-sql

## Current State (v0.1.0 — MVP)

- `Database` type with `handle: Int` and `path: Str`, deriving `Clone`
- `open(path)` — creates a Database stub (handle always 0)
- `execute(db, sql)` — returns 0 (no-op stub)
- `close(db)` — returns 0 (no-op stub)
- All public functions carry `requires` preconditions
- Conformance test suite in `tests/test_conformance.xi`

## Phase 1 — SQLite Backend (v0.2.0)

- [ ] FFI bindings to SQLite3 via `sqlite.xiom-bind`
- [ ] Real `open` that calls `sqlite3_open_v2`
- [ ] Real `execute` that calls `sqlite3_exec`
- [ ] Real `close` that calls `sqlite3_close`
- [ ] Error type: `SqlError` enum (Busy, Constraint, Corrupt, Io, ...)
- [ ] Return `Result[Int, SqlError]` instead of bare `Int`

## Phase 2 — Query and Result Handling (v0.3.0)

- [ ] `Row` type: map of column name → value
- [ ] `ResultSet` type: collection of `Row`
- [ ] `query(db, sql)` → returns `ResultSet`
- [ ] Prepared statements with `prepare`/`bind`/`step`
- [ ] Type-safe parameter binding (Int, Float64, Str, Blob, Null)

## Phase 3 — Connection Management (v0.4.0)

- [ ] Connection pooling (`Pool` type)
- [ ] Read/write connection separation
- [ ] WAL mode support
- [ ] Transaction API: `begin`, `commit`, `rollback`
- [ ] Timeout and busy handler configuration

## Phase 4 — Advanced Features (v0.5.0+)

- [ ] Migration system (up/down, version tracking)
- [ ] Query builder (type-safe SQL construction)
- [ ] ORM layer (struct ↔ table mapping via reflection)
- [ ] PostgreSQL backend (`module xiom.pg`)
- [ ] Async query execution via `xiom.async`
- [ ] Connection string parsing and multi-backend routing

## Non-Goals

- In-process SQL parser (delegate to backends)
- Stored procedure support (backend-specific)
- Full ANSI SQL compliance (target backend compliance)
