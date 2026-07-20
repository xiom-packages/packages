# xiom-libpq — SPEC

**Phase**: 1 (Core Foundation) | **Priority**: HIGH
**Status**: SPEC only — no implementation yet
**Depends on**: xiom.ffi (stdlib)

## What it wraps
libpq — PostgreSQL C client library.
Connection management, query execution, result parsing.

## Dependencies

| What | How | Size |
|------|-----|------|
| PostgreSQL client | System-installed. `winget install PostgreSQL`, `apt install libpq-dev` | ~5MB |
| C compiler | For building bridge | — |

## Bundling strategy
**System-installed only.** PostgreSQL client library is small and standard.

## API surface

```xiom
module xiom.libpq

// Connection
pub fn connect(conninfo: Str) -> Result[Conn, Str]
pub fn close(conn: Conn)
pub fn status(conn: &Conn) -> Int
pub fn error_message(conn: &Conn) -> Str

// Query execution
pub fn exec(conn: &Conn, query: Str) -> Result[Result, Str]
pub fn exec_params(conn: &Conn, query: Str, n_params: Int, types: Vec[Int], values: Vec[Str], lengths: Vec[Int], formats: Vec[Int]) -> Result[Result, Str]

// Result parsing
pub fn ntuples(res: &Result) -> Int
pub fn nfields(res: &Result) -> Int
pub fn fname(res: &Result, idx: Int) -> Str
pub fn get_value(res: &Result, row: Int, col: Int) -> Str
pub fn get_is_null(res: &Result, row: Int, col: Int) -> Bool
pub fn clear(res: Result)

// Async
pub fn send_query(conn: &Conn, query: Str) -> Int
pub fn get_result(conn: &Conn) -> Result[Result, Str]
pub fn consume_input(conn: &Conn) -> Int
pub fn is_busy(conn: &Conn) -> Bool

// Transactions
pub fn begin(conn: &Conn) -> Result[Result, Str]
pub fn commit(conn: &Conn) -> Result[Result, Str]
pub fn rollback(conn: &Conn) -> Result[Result, Str]
```

## Contract coverage target
- Connection: `requires: conninfo.len() > 0`
- Result: `requires: res != 0`
- Row/col bounds: `requires: row < ntuples(res), col < nfields(res)`
- Status: `requires: status(conn) == CONNECTION_OK`

## Phased roadmap

| Phase | What | Effort |
|-------|------|--------|
| 1 | Connect, exec, result parsing, basic types | Day |
| 2 | Parameterized queries, async, COPY I/O | Day |
| 3 | Connection pooling, prepared statements, notifications | Weekend |
