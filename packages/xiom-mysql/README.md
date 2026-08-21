# xiom-mysql

> **Status:** PLACEHOLDER -- reserved, spec pending. No implementation yet.
> **Scope:** MySQL client: connection, query execution, and result handling over the native protocol.
> **Deps:** stdlib; may wrap C (FFI).

## Libs inventory

| Lib | Description |
|-----|-------------|
| `mysql` | Core MySQL wire-protocol client (connect, query, execute). |
| `mysql_stmt` | Prepared statements and parameter binding. |
| `mysql_result` | Result-set iteration and row decoding. |
