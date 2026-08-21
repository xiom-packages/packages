# xiom-sqlite -- Production Roadmap

**Version**: v0.2.0 | **Compiler**: xiom v0.49.7 | **Last updated**: 2026-07-21

## Current Rating: 9/10

| Criterion | Status |
|-----------|--------|
| [OK] Safe wrappers | 109 pub fn, 32 requires contracts (70%+) |
| [OK] No workarounds | Pure XIOM idioms |
| [OK] Examples | demo.xi -- 4 scenarios |
| [OK] README | Build instructions, API reference |
| [OK] SPEC.md | Architecture, API surface, bundling strategy |
| [OK] ROADMAP.md | This file |
| [OK] Contracts | 32 requires clauses across all modules |
| [OK] Tests | 29 conformance tests (types, query, schema, migration, connection, error) |
| [ ] C bridge | **FFI stubs** -- sqlite3 C bridge not yet linked |
| [ ] Demo stable | Demos blocked on FFI bridge |

## Implementation History

| Phase | Status | Description |
|-------|--------|-------------|
| **P1: Types** | [OK] Done | SqliteValue, SqliteRow, SqliteResult, SqliteError |
| **P2: Query Builder** | [OK] Done | SELECT/INSERT/UPDATE/DELETE SQL generation |
| **P3: Schema Builder** | [OK] Done | Table DDL, index DDL, affinity rendering |
| **P4: Migration Manager** | [OK] Done | Sort, pending, up/down with validation |
| **P5: Contracts** | [OK] Done | 32 requires clauses (table.len, col.len, index bounds) |
| **P6: Tests** | [OK] Done | 29 conformance tests |
| **P7: FFI Bridge** | [ ] Pending | sqlite3 C amalgamation integration |

## FFI Bridge Gap (Blocking 10/10)

The package is **9/10 functional** -- all pure-XIOM components work correctly.
The FFI bridge needs:

| Task | Effort |
|------|--------|
| Bundle sqlite3 amalgamation (sqlite3.c/sqlite3.h) | Day |
| Write C bridge (sqlite3_open, sqlite3_exec, sqlite3_prepare_v2, etc.) | Day |
| Replace FFI stubs in connection.xi with real extern "C" calls | Day |
| Verify round-trip: open -> create table -> insert -> query -> close | Day |

## Known Limitations

- **SQL injection in query builder**: WHERE conditions concatenate values directly (no parameterization)
- **No derive[Clone] on types with Vec fields**: Manual clone_sqlite_value/clone_sqlite_row workarounds
- **No Linux/macOS CI**: Verified on Windows only
