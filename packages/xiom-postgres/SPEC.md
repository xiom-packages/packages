# xiom-postgres Specification

## Overview
PostgreSQL client bindings for XIOM via libpq. Provides safe, contract-enforced database connectivity with parameterized queries, transaction management, and escape utilities.

## Architecture

### Layers
```
┌──────────────────────────────────────┐
│  src/client.xi   (Safe XIOM API)     │
│  PgConnection, PgResult contracts    │
├──────────────────────────────────────┤
│  postgres.xi     (Raw FFI decls)     │
│  Connection, QueryResult, execute    │
├──────────────────────────────────────┤
│  libpq.xiom-bind (C ABI mapping)     │
│  PQconnectdb, PQexec, PQfinish       │
└──────────────────────────────────────┘
```

### Design Decisions
- `PgConnection` wraps the raw `Connection` handle with a connection state enum.
- All query functions validate the connection is alive before executing.
- Parameterized queries use `$1`, `$2` placeholders (libpq native format).
- Result sets are eagerly materialized into XIOM types — no lazy fetch cursors.

## Type System

### PgConnection
```
pub type PgConnection = { handle: Int; connected: Bool; }
```
- `handle` maps to `libpq` `PGconn*`.
- `connected` reflects `PQstatus() == CONNECTION_OK`.

### PgResult
```
pub type PgResult = { columns: Vec[Str]; rows: Vec[Vec[Option[Str]]]; row_count: Int; col_count: Int; }
```
- Each row is `Vec[Option[Str]]` — NULL values are `None`.
- Column names are extracted via `PQfname`.

## API Surface

### Connection Management
| Function | Contract |
|----------|----------|
| `pg_connect(conn_str)` | `requires: conn_str.len() > 0` |
| `pg_disconnect(conn)` | `requires: conn.handle != 0` |
| `pg_is_connected(conn)` | `requires: conn.handle != 0` |

### Query Execution
| Function | Contract |
|----------|----------|
| `pg_query(conn, sql)` | `requires: conn.handle != 0, sql.len() > 0` |
| `pg_execute_params(conn, sql, params)` | `requires: conn.handle != 0, sql.len() > 0` |
| `pg_execute_batch(conn, queries)` | `requires: conn.handle != 0` |

### Transactions
| Function | Contract |
|----------|----------|
| `pg_begin(conn)` | `requires: conn.handle != 0` |
| `pg_commit(conn)` | `requires: conn.handle != 0` |
| `pg_rollback(conn)` | `requires: conn.handle != 0` |

### Escaping
| Function | Purpose |
|----------|---------|
| `pg_escape_literal(conn, value)` | Safe string literal escaping |
| `pg_escape_identifier(conn, name)` | Safe identifier escaping |

## Connection String Format
Standard libpq key=value format:
```
host=localhost port=5432 dbname=mydb user=postgres password=secret
```

## Safety Contracts
1. All functions require `conn.handle != 0` (connection must be established).
2. `pg_query` and `pg_execute_params` require `sql.len() > 0` (no empty queries).
3. After `pg_disconnect`, the `PgConnection` is invalidated (handle set to 0).
4. Result memory (`PQclear`) is managed automatically by XIOM wrappers.
5. SQL injection is prevented by using `pg_escape_literal`/`pg_escape_identifier` and parameterized queries.

## External Dependencies
- **Runtime:** PostgreSQL client library — `libpq.dll` / `libpq.so` / `libpq.dylib`
- **Install:** PostgreSQL installation (includes libpq), or `libpq-dev` package
- **Link flags:** `-l pq`
- **Compatibility:** PostgreSQL >= 12, libpq protocol version 3

## Error Handling
1. Connection failures return `Err(connection_error_message)`.
2. Query failures return `Err(result_error_message)` — the full libpq error.
3. Transaction failures preserve the error from `PQexec` of the failing statement.
4. All errors include the raw libpq error string for debugging.

## Status Constants
| Constant | Value | Meaning |
|----------|-------|---------|
| `CONNECTION_OK` | 0 | Connection is healthy |
| `CONNECTION_BAD` | 1 | Connection is dead |
| `PGRES_COMMAND_OK` | 1 | Non-SELECT executed successfully |
| `PGRES_TUPLES_OK` | 2 | SELECT returned rows |
| `PGRES_FATAL_ERROR` | 7 | Query execution failed |
