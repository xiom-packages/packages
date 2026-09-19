# xiom.libpq -- Roadmap

## Phase 1: Pure SPEC Layer

- [x] `extern "C"` block with all 17 libpq C function signatures
- [x] Opaque handle types (`PgConnection`, `PgResult`)
- [x] Status/result constant definitions (CONNECTION_OK, PGRES_TUPLES_OK, etc.)
- [x] Safe wrapper functions with full `requires` contracts
- [x] All FFI wrappers return `Err` (stub mode -- no C bridge linked)
- [x] Transaction helpers: `begin`, `commit`, `rollback` delegate to `exec`
- [x] 30 conformance tests covering types, error paths, async stubs, transactions
- [x] SPEC.md updated to reflect implementation status

**Status:** COMPLETE | **Compiles:** yes (contract-check only)

## Phase 2: C Bridge Integration

- [ ] Implement `libpq_bridge.c` -- thin C shim that maps XIOM opaque Int handles to `PGconn*`/`PGresult*` pointers
- [ ] Wire `extern "C"` stubs through the bridge: `PQconnectdb`, `PQfinish`, `PQstatus`, `PQerrorMessage`
- [ ] Replace stub bodies with real FFI calls via `unsafe` blocks
- [ ] String marshalling: `PQerrorMessage`/`PQfname`/`PQgetvalue` raw `*UInt8` -> `Str` conversion using `xiom.string` helpers
- [ ] `connect` returns `Ok(handle)` on success, `Err(error_message)` on failure
- [ ] `exec`/`exec_params` return parsed results

**Effort:** 1 day | **Depends on:** xiom.ffi (stdlib)

## Phase 3: Parameterised Queries & Async

- [ ] Full `exec_params` with OID types, binary formats, result format
- [ ] `send_query`/`get_result` async pipeline: non-blocking I/O with `PQconsumeInput` polling
- [ ] `PQsendQueryParams`, `PQsendPrepare`, `PQgetResult` chain for pipelined execution
- [ ] Error mapping: `PQresultStatus` -> structured error types
- [ ] `PQcmdStatus`, `PQcmdTuples`, `PQoidValue` for DML feedback

**Effort:** 1 day

## Phase 4: Prepared Statements & Connection Pooling

- [ ] `PQprepare` / `PQexecPrepared` for server-side prepared statements
- [ ] Connection pool: bounded pool of `PgConnection` with acquire/release
- [ ] Automatic reconnect on connection loss
- [ ] `PQsetClientEncoding`, `PQclientEncoding` for charset handling
- [ ] `PQescapeLiteral`, `PQescapeIdentifier` for safe dynamic SQL

**Effort:** 2 days

## Phase 5: Advanced Features

- [ ] LISTEN/NOTIFY: `PQnotifies` for async notifications
- [ ] COPY I/O: `PQputCopyData`, `PQgetCopyData` for bulk data transfer
- [ ] Large Object API: `lo_create`, `lo_open`, `lo_read`, `lo_write`, `lo_close`
- [ ] `PQsetSingleRowMode` for streaming large result sets
- [ ] TLS/SSL configuration via connection parameters

**Effort:** 3 days

## Phase 6: Ecosystem Integration

- [ ] `xiom.libpq` package manifest
- [ ] CI pipeline with PostgreSQL test container
- [ ] Benchmark suite vs. raw libpq C
- [ ] Integration tests with `xiom.net` for socket-based connection
- [ ] Documentation: API reference, migration guide, examples

**Effort:** 2 days
