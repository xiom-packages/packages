# xiom-postgres — PostgreSQL Client

libpq FFI bindings for XIOM. Full PostgreSQL client with parameterized queries, transactions, and SQL injection protection.

## Install

```powershell
xiom pkg install xiom-postgres
```

## Requirements

- **PostgreSQL client library (libpq)**
  - Linux: `apt install libpq-dev`
  - macOS: `brew install libpq` (add to PATH)
  - Windows: Included with PostgreSQL install or vcpkg

## Link Flags

```
-l pq
```

## Quick Start

```xiom
use xiom.postgres;

fn main() -> Int {
  let conn = pg_connect("host=localhost dbname=mydb user=postgres")?;

  let result = pg_query(&conn, "SELECT id, name FROM users")?;

  disconnect(conn);
  return 0;
}
```

## API Overview

| Module | File | Purpose |
|--------|------|---------|
| `xiom.postgres` | `postgres.xi` | FFI declarations |
| `xiom.postgres.client` | `src/client.xi` | Safe typed wrappers with contracts |

### Connection

```xiom
let conn = pg_connect("host=localhost port=5432 dbname=mydb user=postgres password=secret")?;
pg_is_connected(&conn);          // true
pg_disconnect(&conn);            // clean close
```

### Queries

```xiom
let result = pg_query(&conn, "SELECT id, name FROM users WHERE active = true")?;
result.row_count;                 // number of rows
result.col_count;                 // number of columns

let result = pg_execute_params(&conn, "SELECT * FROM users WHERE id = $1", &vec!["42"])?;
```

### Transactions

```xiom
pg_begin(&conn)?;
pg_query(&conn, "INSERT INTO users (name) VALUES ('Alice')")?;
pg_commit(&conn)?;
```

### Escaping (SQL Injection Prevention)

```xiom
let safe_name = pg_escape_literal(&conn, "O'Brien");
let safe_col = pg_escape_identifier(&conn, "user_name");
```

## Connection String Format

Standard libpq key=value pairs, space-separated:
```
host=localhost port=5432 dbname=mydb user=postgres password=secret connect_timeout=10
```

## Contracts

- `requires: conn.handle != 0` — connection must be alive
- `requires: sql.len() > 0` — no empty SQL strings
- Connections are invalidated (handle zeroed) after disconnect

## License

MIT or Apache-2.0, at your option.
