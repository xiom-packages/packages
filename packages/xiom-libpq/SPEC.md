# xiom-libpq -- SPEC

**Phase**: 1 (Core Foundation) | **Priority**: HIGH
**Status**: XIOM layer implemented -- FFI stubs return Err until C bridge is linked
**Depends on**: xiom.ffi (stdlib)

## What it wraps
libpq -- PostgreSQL C client library.
Connection management, query execution, result parsing.

## Dependencies

| What | How | Size |
|------|-----|------|
| PostgreSQL client | System-installed. `winget install PostgreSQL`, `apt install libpq-dev` | ~5MB |
| C compiler | For building bridge | -- |

## Bundling strategy
**System-installed only.** PostgreSQL client library is small and standard.

## API surface

### Module: `xiom.libpq`

#### Types
```xiom
pub type PgConnection = Int   // opaque connection handle
pub type PgResult = Int       // opaque result-set handle
```

#### Constants
```xiom
pub const CONNECTION_OK: Int = 0
pub const CONNECTION_BAD: Int = 1
pub const PGRES_EMPTY_QUERY: Int = 0
pub const PGRES_COMMAND_OK: Int = 1
pub const PGRES_TUPLES_OK: Int = 2
pub const PGRES_FATAL_ERROR: Int = 7
```

#### Connection
```xiom
pub fn connect(conninfo: Str) -> Result[PgConnection, Str]
  requires: conninfo.len() > 0

pub fn close(conn: PgConnection)
  requires: conn != 0

pub fn status(conn: PgConnection) -> Int
  requires: conn != 0

pub fn error_message(conn: PgConnection) -> Str
  requires: conn != 0
```

#### Query execution
```xiom
pub fn exec(conn: PgConnection, sql: Str) -> Result[PgResult, Str]
  requires: conn != 0
  requires: sql.len() > 0

pub fn exec_params(conn: PgConnection, sql: Str, params: Vec[Str]) -> Result[PgResult, Str]
  requires: conn != 0
  requires: sql.len() > 0
```

#### Result parsing
```xiom
pub fn ntuples(res: PgResult) -> Int
  requires: res != 0

pub fn nfields(res: PgResult) -> Int
  requires: res != 0

pub fn fname(res: PgResult, col: Int) -> Str
  requires: res != 0
  requires: col >= 0

pub fn get_value(res: PgResult, row: Int, col: Int) -> Str
  requires: res != 0
  requires: row >= 0
  requires: col >= 0

pub fn get_is_null(res: PgResult, row: Int, col: Int) -> Bool
  requires: res != 0

pub fn clear(res: PgResult)
  requires: res != 0
```

#### Async / non-blocking
```xiom
pub fn send_query(conn: PgConnection, sql: Str) -> Result[Int, Str]
  requires: conn != 0
  requires: sql.len() > 0

pub fn get_result(conn: PgConnection) -> Result[PgResult, Str]

pub fn consume_input(conn: PgConnection) -> Result[Int, Str]

pub fn is_busy(conn: PgConnection) -> Bool
```

#### Transactions
```xiom
pub fn begin(conn: PgConnection) -> Result[PgResult, Str]
  requires: conn != 0

pub fn commit(conn: PgConnection) -> Result[PgResult, Str]
  requires: conn != 0

pub fn rollback(conn: PgConnection) -> Result[PgResult, Str]
  requires: conn != 0
```

## C FFI surface (17 functions)

All functions declared in `extern "C"` block within `libpq.xi`:

| Function | Purpose |
|----------|---------|
| `PQconnectdb` | Open a new database connection |
| `PQfinish` | Close a connection |
| `PQstatus` | Check connection status |
| `PQerrorMessage` | Retrieve last error message |
| `PQexec` | Execute a SQL command synchronously |
| `PQexecParams` | Execute with parameterised values |
| `PQntuples` | Row count in result |
| `PQnfields` | Column count in result |
| `PQfname` | Column name by index |
| `PQgetvalue` | Cell value by row/col |
| `PQgetisnull` | Check if cell is SQL NULL |
| `PQclear` | Free result memory |
| `PQsendQuery` | Submit async query |
| `PQgetResult` | Retrieve async result |
| `PQconsumeInput` | Read pending data from server |
| `PQisBusy` | Check if async command is in-flight |
| `PQresultStatus` | Result status code |

## Contract coverage

| Function | Contracts |
|----------|-----------|
| `connect` | `requires: conninfo.len() > 0` |
| `close` | `requires: conn != 0` |
| `status` | `requires: conn != 0` |
| `error_message` | `requires: conn != 0` |
| `exec` | `requires: conn != 0, sql.len() > 0` |
| `exec_params` | `requires: conn != 0, sql.len() > 0` |
| `ntuples` | `requires: res != 0` |
| `nfields` | `requires: res != 0` |
| `fname` | `requires: res != 0, col >= 0` |
| `get_value` | `requires: res != 0, row >= 0, col >= 0` |
| `get_is_null` | `requires: res != 0` |
| `clear` | `requires: res != 0` |
| `send_query` | `requires: conn != 0, sql.len() > 0` |
| `begin` | `requires: conn != 0` |
| `commit` | `requires: conn != 0` |
| `rollback` | `requires: conn != 0` |

**Total**: 16 contracted safe wrappers, 29 `requires` clauses.

## Test coverage

30 conformance tests in `tests/test_conformance.xi`:

- **Types**: 4 tests (constants, type definitions)
- **Connection**: 5 tests (connect, close, status, error_message)
- **Query execution**: 4 tests (exec, exec_params with various params)
- **Result parsing**: 5 tests (ntuples, nfields, fname, get_value, get_is_null, clear)
- **Async**: 4 tests (send_query, get_result, consume_input, is_busy)
- **Transactions**: 4 tests (begin, commit, rollback, full cycle)
- **Smoke**: 4 tests (round-trip validation, all non-result callable, all result-returning return Err)

## Phased roadmap

| Phase | What | Effort | Status |
|-------|------|--------|--------|
| 1 | Pure SPEC layer -- contracts, stubs, conformance tests | Day | **DONE** |
| 2 | C bridge -- real FFI, string marshalling, connect/exec | Day | Pending |
| 3 | Parameterised queries, async pipeline | Day | Pending |
| 4 | Prepared statements, connection pooling | 2 days | Pending |
| 5 | LISTEN/NOTIFY, COPY I/O, large objects | 3 days | Pending |
| 6 | Package manifest, CI, benchmarks, docs | 2 days | Pending |
