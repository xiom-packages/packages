# AUDIT: xiom-postgres

## Status
All 3 source files compile on xiomc v0.45.3 with stubbed FFI functions.

## System Library Dependencies
- **libpq** (PostgreSQL client library, >= 12 recommended)
  - Windows: Part of PostgreSQL installation, or `vcpkg install libpq`
  - Linux: `apt install libpq-dev` (Debian) / `dnf install postgresql-devel` (Fedora)
  - macOS: `brew install libpq`, or bundled with PostgreSQL.app
  - Link flag: `-l pq`

## Known Gaps
1. **libpq FFI not linked**: All functions in `postgres.xi` are stubs returning errors. Real functionality requires libpq FFI bindings.
2. **Forward declarations removed**: Original `postgres.xi` had function signatures without bodies (forward declarations), which are not valid XIOM syntax. All functions now have stub bodies.
3. **client.xi simplified**: The original `client.xi` wrapped `postgres.xi` functions, but cross-module imports between sibling files are not supported in standalone compilation. Made self-contained.
4. **test_postgres.xi**: Simplified to self-contained test. Original used `xiom.test` module which is not in the stdlib. Uses inline connect stub.

## Files Modified
- `postgres.xi` — Added stub bodies to all forward-declared functions
- `src/client.xi` — Made self-contained with inline stub functions, types defined before use
- `tests/test_postgres.xi` — Made self-contained, replaced `let` with `var`, added inline stub

## Restoring Production FFI
To restore production functionality:
1. Implement libpq C FFI bindings (`PQconnectdb`, `PQexec`, `PQfinish`, etc.) via `extern "C"` blocks
2. Link against `libpq` at compile time
3. Re-enable cross-module dependency between `postgres.xi` and `client.xi`
