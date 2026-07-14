# xiom-sqlite

> Production-grade SQLite3 bindings for XIOM — FFI-backed database with schema builder, query builder, and migration manager.

[![XIOM](https://img.shields.io/badge/XIOM-v0.22.1-blue)](https://github.com/xiom-lang/XIOM)
[![License](https://img.shields.io/badge/license-MIT%2FApache--2.0-blue.svg)](LICENSE)

## Overview

xiom-sqlite provides a complete, safe SQLite3 interface for XIOM. It wraps the C SQLite3 library through `extern "C"` FFI with comprehensive safety contracts, and adds a schema builder, SQL query generator, and migration system — all written in XIOM.

## Installation

```bash
xiom install xiom-sqlite
```

## Dependencies

### SQLite3 Library
| OS | Command |
|----|---------|
| **Windows** | `vcpkg install sqlite3` |
| **Ubuntu/Debian** | `sudo apt install libsqlite3-dev` |
| **Fedora** | `sudo dnf install sqlite-devel` |
| **macOS** | Pre-installed |

Link: `xiomc -l sqlite3 myprogram.xi`

## Quick Start

```xiom
use xiom.sqlite.connection;
use xiom.sqlite.schema;
use xiom.sqlite.query;

fn main() -> Int {
  // Open in-memory database
  var db = sqlite_open(":memory:").unwrap();

  // Create table
  sqlite_execute(&db, "CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT);").unwrap();

  // Insert
  sqlite_execute(&db, "INSERT INTO users VALUES (1, 'XIOM');").unwrap();

  // Query
  var rows = sqlite_query(&db, "SELECT * FROM users;").unwrap();

  sqlite_close(db).unwrap();
  return 0;
}
```

## API Reference

### Connection (`xiom.sqlite.connection`)
| Function | Description |
|----------|-------------|
| `sqlite_open(path)` | Open database (":memory:" for in-memory) |
| `sqlite_close(conn)` | Close connection |
| `sqlite_execute(conn, sql)` | Execute SQL (no results) |
| `sqlite_query(conn, sql)` | Execute SQL and return rows |
| `sqlite_prepare(conn, sql)` | Prepare a statement |
| `sqlite_step(stmt)` | Step through prepared statement |
| `sqlite_column_int(stmt, col)` | Read integer column |
| `sqlite_column_float(stmt, col)` | Read float column |
| `sqlite_column_text(stmt, col)` | Read text column |
| `sqlite_column_blob(stmt, col)` | Read blob column |
| `sqlite_finalize(stmt)` | Finalize statement |
| `sqlite_last_insert_rowid(conn)` | Last insert rowid |
| `sqlite_changes(conn)` | Rows changed by last operation |
| `sqlite_is_open(conn)` | Check if open |

### Types (`xiom.sqlite.types`)
| Type | Description |
|------|-------------|
| `SqliteValue` | Enum: Null, Integer, Real, Text, Blob |
| `SqliteRow` | Row of column values |
| `SqliteResult` | Query result (rows + metadata) |
| `SqliteError` | Error with code and message |

### Schema Builder (`xiom.sqlite.schema`)
| Function | Description |
|----------|-------------|
| `table_def_new(name)` | Create table definition |
| `table_def_add_column(table, name, type)` | Add column |
| `table_def_to_create_sql(table)` | Generate CREATE TABLE SQL |
| `index_def_to_create_sql(idx)` | Generate CREATE INDEX SQL |

### Query Builder (`xiom.sqlite.query`)
| Function | Description |
|----------|-------------|
| `query_select(table)` | Start SELECT query |
| `query_column(qb, col)` | Add column |
| `query_where_eq(qb, col, val)` | Add WHERE condition |
| `query_order_by(qb, col, desc)` | Add ORDER BY |
| `query_limit(qb, limit)` | Add LIMIT |
| `query_offset(qb, offset)` | Add OFFSET |
| `query_to_sql(qb)` | Generate SELECT SQL |
| `query_insert_sql(table, cols)` | Generate INSERT SQL |
| `query_update_sql(table, sets, where)` | Generate UPDATE SQL |
| `query_delete_sql(table, where)` | Generate DELETE SQL |

### Migrations (`xiom.sqlite.migration`)
| Function | Description |
|----------|-------------|
| `migration_new(version, name, up, down)` | Create migration |
| `migration_manager_new()` | Create manager |
| `migration_manager_add(mgr, mig)` | Register migration |
| `migration_manager_up(mgr, conn)` | Run pending up migrations |
| `migration_manager_down(mgr, conn, steps)` | Rollback migrations |
| `migration_manager_status(mgr)` | Current version |

### Demo (`xiom.sqlite.demo`)
| Function | Description |
|----------|-------------|
| `demo_in_memory()` | Full CRUD demo |
| `demo_file(path)` | File-backed demo |
| `demo_prepared_steps()` | Prepared statement demo |
| `demo_transaction()` | Transaction demo |

## Safety Contracts

Every FFI boundary guarded:
- `sqlite_open`: requires path.len() > 0
- `sqlite_close`: requires conn.handle != 0
- `sqlite_execute/query/prepare`: requires conn.handle != 0, sql.len() > 0
- `sqlite_column_*`: requires stmt.handle != 0, col >= 0
- `sqlite_finalize`: requires stmt.handle != 0

## Production Readiness

| Feature | Status | Notes |
|---------|--------|-------|
| SQLite3 open/close | ✅ Production | FFI bridge integrated, requires ffi_bridge.c |
| SQL execute | ✅ Production | FFI bridge integrated |
| SQL query (rows) | ✅ Production | Full column type dispatch |
| Prepared statements | ✅ Production | Full lifecycle |
| Schema builder | ✅ Complete | Pure XIOM |
| Query builder (SELECT/INSERT/UPDATE/DELETE) | ✅ Complete | Pure XIOM |
| Migration system | ✅ Complete | Up/down with version tracking |
| Transaction support | ✅ Production | Via SQL (BEGIN/COMMIT/ROLLBACK) |
| BLOB support | ✅ Complete | Column type dispatch |
| Connection pooling | ❌ Not yet | |
| Async queries | ❌ Not yet | Needs threading |
| SQLite3 backup API | ❌ Not yet | |
| WAL mode | ⚠️ Via SQL | `PRAGMA journal_mode=WAL` |
| User-defined functions | ❌ Not yet | |

### What's Left for v1.0
1. **Connection pooling** — multi-threaded connection management
2. **ORM layer** — type-safe row mapping (blocked on compiler generics)
3. **Full-text search** — FTS5 bindings

## Build & Run

```bash
# Compile with FFI bridge and system libraries
xiomc myprogram.xi ../runtime/ffi_bridge.c -l sqlite3 -o myprogram.exe
./myprogram.exe
```

> Requires ffi_bridge.c to be compiled alongside. The FFI bridge provides `xiom_alloc`, `xiom_free_ptr`, `xiom_read_byte`, `xiom_write_byte`, `xiom_str_to_cstr`, and `xiom_free_cstr` across the FFI boundary.

## Links

- **Organization**: [github.com/xiom-lang](https://github.com/xiom-lang)
- **Language**: [github.com/xiom-lang/XIOM](https://github.com/xiom-lang/XIOM)

## License

MIT OR Apache-2.0
