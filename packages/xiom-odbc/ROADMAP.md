# xiom.odbc -- Roadmap

**Version**: v0.2.0 | **Compiler**: xiom v0.64.1 | **Last updated**: 2026-10-08

## Current state

| Criterion | Status |
|-----------|--------|
| Dynamic loader (no link dependency) | Done -- `odbc32.dll` at runtime |
| G2 pin (soname + entry points + constants) | Done -- `SPEC.md` §2 |
| Driver-manager identification | Done -- ODBC `03.80.0000` |
| Driver + DSN enumeration | Done -- 7 drivers / 3 DSNs reported |
| SKIP/FAIL classification | Done |
| Connections (`SQLConnect`/`SQLDriverConnect`) | Phase 2 |
| Statement execution (`SQLExecDirect`/fetch) | Phase 2 |
| Diagnostics (`SQLGetDiagRec`) + error text | Phase 2 |
| Wide (UTF-16) API variants | Phase 2 |
| POSIX (`libodbc.so.2`) | Phase 2 |

## Phase 2 (next touches)

1. Diagnostics: `SQLGetDiagRec` + `SQLGetDiagField` to turn rc codes into
   real messages (pairs with the B-10 note: keep bridge locals `f_`-prefixed).
2. Connections: `SQLDriverConnect` with a caller-provided connection string;
   suite path SKIPs when no reachable DSN (`driver=` with a bogus server) --
   assert the error path cleanly instead of requiring infrastructure.
3. Execution: `SQLAllocHandle(STMT)`, `SQLExecDirect`, `SQLFetch` +
   `SQLGetData` against a self-contained DSN only if the environment
   provides one; otherwise an error-path suite.
4. Wide API variants for unicode DSN/driver text.
5. POSIX fallback (`libodbc.so.2`) when a Linux CI target exists.

## Sector note

Data/drivers sector, package 1 of 2 (`xiom.odbc`; `xiom.libpq` next --
needs a PostgreSQL client library for positive-path proof, proposal in
`BINDINGS-SESSION.md`).
