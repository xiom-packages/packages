# xiom-postgres

> **Status:** PLACEHOLDER — reserved, spec pending. No implementation yet.
> **Scope:** PostgreSQL client: connections, queries, prepared statements, and COPY.
> **Deps:** stdlib; may wrap C (FFI).

## Libs inventory

| Lib | Description |
|-----|-------------|
| `postgres` | PostgreSQL wire-protocol client (connect, query, COPY). |
| `pg_stmt` | Prepared statements with typed parameters. |
| `pg_result` | Result-set decoding and error handling. |
