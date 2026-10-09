# xiom.libpq -- Roadmap

**Version**: v0.2.0 | **Compiler**: xiom v0.64.1 | **Last updated**: 2026-10-09

## Current state

| Criterion | Status |
|-----------|--------|
| Dynamic loader (no link dependency) | Done -- `libpq.dll` at runtime |
| G2 pin (soname + entry points + constants) | Done -- `SPEC.md` §2 |
| Library version probe | Done -- 130011 (13.11) |
| Connect/status/error probe (no server) | Done -- `CONNECTION_BAD` + error text |
| SKIP/FAIL classification | Done |
| Query execution + result sets | Phase 2 |
| Parameterized queries (`PQexecParams`) | Phase 2 |
| Async (`PQsendQuery`/`PQgetResult`) | Phase 2 |
| POSIX (`libpq.so.5`) | Phase 2 |

## Phase 2 (next touches)

1. Query path: `pq_exec(lib, conn, sql)` returning a typed result
   (`PQresultStatus`, `PQntuples`, `PQnfields`, `PQfname`, `PQgetvalue`,
   `PQgetisnull`, `PQclear`) with owned row materialization -- exercised
   against a live server when one is reachable, and against the error path
   otherwise.
2. Connection lifecycle: keep a `PqConnection` handle type with
   `pq_connect`/`pq_finish`/`pq_status`; connection-string builder
   (host/port/db/user/password with escaping).
3. Parameterized + async APIs as thin wrappers.
4. `xiom.postgres` (the protocol-facade package) decides whether to build on
   `xiom.libpq` or a pure-XIOM wire implementation -- native lane call.
5. POSIX fallback (`libpq.so.5`) when a Linux CI target exists.

## Sector note

Data/drivers sector, package 2 of 2 (`xiom.odbc` 0.2.0 done; `xiom.libpq`
this package). Next sector per the proposal: audio (`xiom.miniaudio` first).
