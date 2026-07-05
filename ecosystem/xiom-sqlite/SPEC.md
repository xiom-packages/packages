# xiom-sqlite — SQLite Database Bindings for XIOM

## Package

**Name:** `xiom-sqlite`
**Version:** `0.2.0`
**Layer:** 3.3 — Ecosystem MVP
**Module:** `xiom.sqlite`

SQLite database bindings providing a complete type system, schema management, query building, migration framework, and full FFI integration with `libsqlite3` for XIOM. Connection and execution functions are production-ready using `extern "C"` FFI calls to the native SQLite3 library.

---

## Modules

### `xiom.sqlite.types` — Type System
Pure data types for representing SQLite values, rows, results, and errors.

#### `SqliteValue`
Tagged union for all SQLite storage classes:

| Constructor | Field | XIOM Type |
|---|---|---|
| `SqliteValueKind.Null` | — | — |
| `SqliteValueKind.Integer` | `value` | `Int` |
| `SqliteValueKind.Real` | `value` | `Float64` |
| `SqliteValueKind.Text` | `value` | `Str` |
| `SqliteValueKind.Blob` | `value` | `Vec[Int]` |

#### `SqliteRow`
Represents a single row as an ordered collection of `SqliteValue` cells.

| Field | Type |
|---|---|
| `columns` | `Vec[SqliteValue]` |

#### `SqliteResult`
Complete query result with column metadata and mutation count.

| Field | Type |
|---|---|
| `rows` | `Vec[SqliteRow]` |
| `column_names` | `Vec[Str]` |
| `rows_affected` | `Int` |

#### `SqliteError`
Structured error with SQLite error code and message.

| Field | Type |
|---|---|
| `code` | `Int` |
| `message` | `Str` |

#### API Reference: `SqliteValue`

| Function | Signature | Returns |
|---|---|---|
| `SqliteValue.null` | `() -> SqliteValue` | `NULL` value |
| `SqliteValue.integer` | `(val: Int) -> SqliteValue` | Integer value |
| `SqliteValue.real` | `(val: Float64) -> SqliteValue` | Real/float value |
| `SqliteValue.text` | `(val: Str) -> SqliteValue` | Text value |
| `SqliteValue.blob` | `(val: Vec[Int]) -> SqliteValue` | Blob value |
| `SqliteValue.as_int` | `(val: &SqliteValue) -> Option[Int]` | Extract integer |
| `SqliteValue.as_real` | `(val: &SqliteValue) -> Option[Float64]` | Extract float |
| `SqliteValue.as_text` | `(val: &SqliteValue) -> Option[Str]` | Extract text |
| `SqliteValue.as_blob` | `(val: &SqliteValue) -> Option[Vec[Int]]` | Extract blob |
| `SqliteValue.is_null` | `(val: &SqliteValue) -> Bool` | Check if NULL |

#### API Reference: `SqliteRow`

| Function | Signature |
|---|---|
| `SqliteRow.new` | `() -> SqliteRow` |
| `SqliteRow.add` | `(row: &mut SqliteRow, value: SqliteValue)` |
| `SqliteRow.get` | `(row: &SqliteRow, index: Int) -> Option[SqliteValue]` |
| `SqliteRow.column_count` | `(row: &SqliteRow) -> Int` |

#### API Reference: `SqliteResult`

| Function | Signature |
|---|---|
| `SqliteResult.new` | `() -> SqliteResult` |
| `SqliteResult.add_row` | `(result: &mut SqliteResult, row: SqliteRow)` |
| `SqliteResult.set_column_names` | `(result: &mut SqliteResult, names: Vec[Str])` |
| `SqliteResult.row_count` | `(result: &SqliteResult) -> Int` |
| `SqliteResult.column_count` | `(result: &SqliteResult) -> Int` |
| `SqliteResult.get_row` | `(result: &SqliteResult, index: Int) -> Option[SqliteRow]` |

---

### `xiom.sqlite.schema` — Schema Management
Schema definition types with SQL DDL generation.

#### `SqliteAffinity`
SQLite type affinity enumeration:
- `IntegerAff` → `INTEGER`
- `RealAff` → `REAL`
- `TextAff` → `TEXT`
- `BlobAff` → `BLOB`
- `NullAff` → `NULL`

#### `ColumnDef`

| Field | Type | Description |
|---|---|---|
| `name` | `Str` | Column name |
| `col_type` | `SqliteAffinity` | Type affinity |
| `nullable` | `Bool` | Allow NULL |
| `primary_key` | `Bool` | PRIMARY KEY |
| `auto_increment` | `Bool` | AUTOINCREMENT |

#### `TableDef`

| Field | Type |
|---|---|
| `name` | `Str` |
| `columns` | `Vec[ColumnDef]` |

#### `CreateIndexDef`

| Field | Type |
|---|---|
| `name` | `Str` |
| `table` | `Str` |
| `columns` | `Vec[Str]` |
| `unique` | `Bool` |

#### API Reference

| Function | Signature |
|---|---|
| `TableDef.new` | `(name: Str) -> TableDef` |
| `TableDef.add_column` | `(table: &mut TableDef, name: Str, col_type: SqliteAffinity)` |
| `TableDef.add_primary_key` | `(table: &mut TableDef, name: Str, col_type: SqliteAffinity)` |
| `TableDef.add_auto_id` | `(table: &mut TableDef)` |
| `TableDef.to_create_sql` | `(table: &TableDef) -> Str` |
| `ColumnDef.new` | `(name: Str, col_type: SqliteAffinity) -> ColumnDef` |
| `ColumnDef.with_primary_key` | `(col: &mut ColumnDef)` |
| `ColumnDef.with_auto_increment` | `(col: &mut ColumnDef)` |
| `ColumnDef.with_not_null` | `(col: &mut ColumnDef)` |
| `CreateIndexDef.new` | `(name: Str, table: Str, columns: Vec[Str], unique: Bool) -> CreateIndexDef` |
| `CreateIndexDef.to_create_sql` | `(idx: &CreateIndexDef) -> Str` |

**Example output:**

```
CREATE TABLE users (id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, name TEXT, email TEXT NOT NULL);
CREATE UNIQUE INDEX idx_users_email ON users (email);
```

---

### `xiom.sqlite.query` — Query Builder
Programmatic SQL generation for SELECT, INSERT, UPDATE, DELETE.

#### `QueryBuilder`

| Field | Type | Default |
|---|---|---|
| `table` | `Str` | — |
| `columns` | `Vec[Str]` | `[]` (selects `*`) |
| `conditions` | `Vec[Str]` | `[]` |
| `order_by` | `Vec[Str]` | `[]` |
| `limit_val` | `Int` | `-1` (unset) |
| `offset_val` | `Int` | `-1` (unset) |

#### API Reference: Query Building

| Function | Signature | Description |
|---|---|---|
| `QueryBuilder.select` | `(table: Str) -> QueryBuilder` | Create SELECT builder |
| `QueryBuilder.column` | `(qb: &mut QueryBuilder, col: Str)` | Add column to SELECT |
| `QueryBuilder.where_eq` | `(qb: &mut QueryBuilder, col: Str, val: Str)` | Add `col = 'val'` |
| `QueryBuilder.where_neq` | `(qb: &mut QueryBuilder, col: Str, val: Str)` | Add `col != 'val'` |
| `QueryBuilder.where_gt` | `(qb: &mut QueryBuilder, col: Str, val: Str)` | Add `col > 'val'` |
| `QueryBuilder.where_lt` | `(qb: &mut QueryBuilder, col: Str, val: Str)` | Add `col < 'val'` |
| `QueryBuilder.where_like` | `(qb: &mut QueryBuilder, col: Str, pattern: Str)` | Add `col LIKE 'pattern'` |
| `QueryBuilder.where_in` | `(qb: &mut QueryBuilder, col: Str, values: &Vec[Str])` | Add `col IN (...)` |
| `QueryBuilder.where_raw` | `(qb: &mut QueryBuilder, condition: Str)` | Add raw condition string |
| `QueryBuilder.order_by` | `(qb: &mut QueryBuilder, col: Str, desc: Bool)` | Add ORDER BY clause |
| `QueryBuilder.limit` | `(qb: &mut QueryBuilder, limit: Int)` | Set LIMIT |
| `QueryBuilder.offset` | `(qb: &mut QueryBuilder, offset: Int)` | Set OFFSET |
| `QueryBuilder.to_sql` | `(qb: &QueryBuilder) -> Str` | Generate SELECT SQL |

#### API Reference: Static SQL Generators

| Function | Signature |
|---|---|
| `query_insert_sql` | `(table: Str, columns: &Vec[Str]) -> Str` |
| `query_update_sql` | `(table: Str, sets: &Vec[Str], where_clause: Str) -> Str` |
| `query_delete_sql` | `(table: Str, where_clause: Str) -> Str` |

#### Convenience Aliases

| Function | Alias For |
|---|---|
| `query_select(table)` | `QueryBuilder.select(table)` |
| `query_column(qb, col)` | `QueryBuilder.column(qb, col)` |
| `query_where_eq(qb, col, val)` | `QueryBuilder.where_eq(qb, col, val)` |
| `query_order_by(qb, col, desc)` | `QueryBuilder.order_by(qb, col, desc)` |
| `query_limit(qb, limit)` | `QueryBuilder.limit(qb, limit)` |
| `query_offset(qb, offset)` | `QueryBuilder.offset(qb, offset)` |
| `query_to_sql(qb)` | `QueryBuilder.to_sql(qb)` |

---

### `xiom.sqlite.connection` — Connection Management (FFI)
SQLite database connection lifecycle and query execution via `extern "C"` FFI calls to `libsqlite3`. All database operations are production implementations — no stubs.

#### `SqliteConnection`

| Field | Type | Description |
|---|---|---|
| `db_path` | `Str` | Database file path or `:memory:` |
| `handle` | `Int` | Opaque `sqlite3*` C pointer as integer handle |
| `is_open` | `Bool` | Whether the connection is currently open |

#### `SqliteStmt`

| Field | Type | Description |
|---|---|---|
| `handle` | `Int` | Opaque `sqlite3_stmt*` C pointer as integer handle |
| `sql` | `Str` | The SQL text this statement was compiled from |

#### FFI Declarations (`extern "C"`)

The following C functions from `libsqlite3` are declared and used:

| C Function | XIOM Signature | Purpose |
|---|---|---|
| `sqlite3_open` | `(path: *UInt8, db_handle: *UInt8) -> Int` | Open database |
| `sqlite3_close` | `(db: Int) -> Int` | Close database |
| `sqlite3_exec` | `(db: Int, sql: *UInt8, callback: Int, arg: Int, errmsg: *UInt8) -> Int` | Execute SQL |
| `sqlite3_prepare_v2` | `(db: Int, sql: *UInt8, len: Int, stmt: *UInt8, tail: *UInt8) -> Int` | Compile SQL |
| `sqlite3_step` | `(stmt: Int) -> Int` | Advance statement |
| `sqlite3_column_int` | `(stmt: Int, col: Int) -> Int` | Read int column |
| `sqlite3_column_double` | `(stmt: Int, col: Int) -> Float64` | Read float column |
| `sqlite3_column_text` | `(stmt: Int, col: Int) -> *UInt8` | Read text column |
| `sqlite3_column_bytes` | `(stmt: Int, col: Int) -> Int` | Read blob size |
| `sqlite3_column_type` | `(stmt: Int, col: Int) -> Int` | Column value type |
| `sqlite3_column_count` | `(stmt: Int) -> Int` | Column count in result |
| `sqlite3_finalize` | `(stmt: Int) -> Int` | Destroy statement |
| `sqlite3_errmsg` | `(db: Int) -> *UInt8` | Error message |
| `sqlite3_last_insert_rowid` | `(db: Int) -> Int` | Last row ID |
| `sqlite3_changes` | `(db: Int) -> Int` | Changed row count |
| `sqlite3_free` | `(ptr: Int)` | Free SQLite-allocated memory |

#### Internal Helpers

| Function | Signature | Description |
|---|---|---|
| `cstr_to_str` | `(ptr: *UInt8) -> Str` | Reads null-terminated C string into XIOM `Str` |
| `errmsg_to_str` | `(db: Int) -> Str` | Retrieves and converts `sqlite3_errmsg` |
| `read_column_value` | `(stmt_handle: Int, col: Int) -> SqliteValue` | Reads any column type into `SqliteValue` variant |

#### API Reference

| Function | Signature | Status |
|---|---|---|
| `sqlite_open` | `(path: Str) -> Result[SqliteConnection, Str]` | LIVE |
| `sqlite_close` | `(conn: SqliteConnection) -> Result[Unit, Str]` | LIVE |
| `sqlite_execute` | `(conn: &SqliteConnection, sql: Str) -> Result[Unit, Str]` | LIVE |
| `sqlite_query` | `(conn: &SqliteConnection, sql: Str) -> Result[Vec[SqliteRow], Str]` | LIVE |
| `sqlite_prepare` | `(conn: &SqliteConnection, sql: Str) -> Result[SqliteStmt, Str]` | LIVE |
| `sqlite_step` | `(stmt: &SqliteStmt) -> Result[Bool, Str]` | LIVE |
| `sqlite_column_int` | `(stmt: &SqliteStmt, col: Int) -> Int` | LIVE |
| `sqlite_column_float` | `(stmt: &SqliteStmt, col: Int) -> Float64` | LIVE |
| `sqlite_column_text` | `(stmt: &SqliteStmt, col: Int) -> Str` | LIVE |
| `sqlite_column_blob` | `(stmt: &SqliteStmt, col: Int) -> Vec[Int]` | LIVE |
| `sqlite_finalize` | `(stmt: SqliteStmt) -> Result[Unit, Str]` | LIVE |
| `sqlite_last_insert_rowid` | `(conn: &SqliteConnection) -> Int` | LIVE |
| `sqlite_changes` | `(conn: &SqliteConnection) -> Int` | LIVE |
| `sqlite_is_open` | `(conn: &SqliteConnection) -> Bool` | LIVE |
| `sqlite_path` | `(conn: &SqliteConnection) -> Str` | LIVE |

---

### `xiom.sqlite.migration` — Schema Migrations
Versioned schema migration framework with up/down support.

#### `Migration`

| Field | Type | Description |
|---|---|---|
| `version` | `Int` | Monotonically increasing version number |
| `name` | `Str` | Human-readable migration name |
| `up_sql` | `Str` | SQL to apply migration |
| `down_sql` | `Str` | SQL to revert migration |

#### `MigrationManager`

| Field | Type |
|---|---|
| `migrations` | `Vec[Migration]` |
| `current_version` | `Int` |

#### API Reference

| Function | Signature | Description |
|---|---|---|
| `Migration.new` | `(version: Int, name: Str, up: Str, down: Str) -> Migration` | Create migration |
| `MigrationManager.new` | `() -> MigrationManager` | Create manager |
| `MigrationManager.add` | `(mgr: &mut MigrationManager, migration: Migration)` | Register migration |
| `MigrationManager.count` | `(mgr: &MigrationManager) -> Int` | Total migrations |
| `MigrationManager.version` | `(mgr: &MigrationManager) -> Int` | Current version |
| `MigrationManager.pending` | `(mgr: &MigrationManager) -> Vec[Migration]` | Unapplied migrations |
| `MigrationManager.sort` | `(mgr: &mut MigrationManager)` | Sort by version ascending |
| `MigrationManager.up` | `(mgr: &mut MigrationManager, conn: &SqliteConnection) -> Result[Int, SqliteError]` | Run all pending |
| `MigrationManager.down` | `(mgr: &mut MigrationManager, conn: &SqliteConnection, steps: Int) -> Result[Int, SqliteError]` | Rollback N steps |
| `MigrationManager.status` | `(mgr: &MigrationManager) -> Int` | Current version |

#### Convenience Aliases

| Function | Alias For |
|---|---|
| `migration_new(v, n, u, d)` | `Migration.new(v, n, u, d)` |
| `migration_manager_new()` | `MigrationManager.new()` |
| `migration_manager_add(mgr, m)` | `MigrationManager.add(mgr, m)` |
| `migration_manager_up(mgr, conn)` | `MigrationManager.up(mgr, conn)` |
| `migration_manager_down(mgr, conn, steps)` | `MigrationManager.down(mgr, conn, steps)` |
| `migration_manager_status(mgr)` | `MigrationManager.status(mgr)` |

---

### `xiom.sqlite.demo` — Usage Demonstrations
End-to-end examples showing real database patterns using the FFI-backed connection module.

#### API Reference

| Function | Signature | Description |
|---|---|---|
| `demo_in_memory` | `() -> Result[Unit, Str]` | Full CRUD on `:memory:` database |
| `demo_file` | `(path: Str) -> Result[Unit, Str]` | File-based persistence with counters |
| `demo_prepared_steps` | `() -> Result[Unit, Str]` | Prepared statement lifecycle |
| `demo_transaction` | `() -> Result[Unit, Str]` | Transaction commit flow |

`demo_in_memory` demonstrates: open, CREATE TABLE, INSERT with `last_insert_rowid`, SELECT with `sqlite_query`, UPDATE, DELETE, COUNT aggregates, close.

---

## FFI Implementation (Layer 4 — COMPLETE)

All SQLite3 C FFI functions are declared in `connection.xi` via `extern "C" { }` blocks and called within `unsafe { }` blocks. The binding file `E:\Projects\AXIOM\ecosystem\xiom-sql\sqlite.xiom-bind` provides the library-level declarations.

### Runtime Functions Required

The following XIOM runtime intrinsics are called by `connection.xi` and must be provided by the XIOM compiler/runtime:

| Runtime Function | Purpose |
|---|---|
| `native.str_to_c(str: Str) -> *UInt8` | Converts XIOM `Str` to null-terminated C string. Returns heap-allocated buffer freed automatically or via explicit free. |
| `native.addr_of(var: T) -> *UInt8` | Returns the address of a local variable cast to `*UInt8`, used to pass output pointers to C functions. |
| `native.read_u8(ptr: *UInt8) -> Int` | Reads a single byte (0-255) from the given pointer. Used in `cstr_to_str` and blob reading. |
| `native.byte_to_char(byte: Int) -> Str` | Converts a single byte value to a single-character XIOM `Str`. Used in `cstr_to_str`. |
| `native.codepoint_to_char(cp: Int) -> Str` | Converts a Unicode codepoint to a single-character `Str`. Used in `int_to_str`. |

### SQLite Version Compatibility

- Requires **SQLite 3.31.0+** (for `sqlite3_column_type` full type info)
- Recommended: SQLite 3.43.0+
- Backward-compatible with SQLite 3.8.0+

---

## Setup Instructions

### 1. Install libsqlite3

#### Windows (MSYS2 / MinGW)
```sh
pacman -S mingw-w64-x86_64-sqlite3
```
Or download the precompiled DLL and `.lib` from [sqlite.org/download.html](https://sqlite.org/download.html). Place `sqlite3.dll` and `sqlite3.def` in your project directory.

#### Linux (Debian/Ubuntu)
```sh
sudo apt install libsqlite3-dev
```

#### Linux (Fedora/RHEL)
```sh
sudo dnf install sqlite-devel
```

#### macOS
```sh
brew install sqlite
```
macOS ships with libsqlite3 built-in at `/usr/lib/libsqlite3.dylib`.

### 2. Build Configuration

Add to your `kilo.json` or XIOM project config:

```json
{
  "ffi": {
    "libraries": {
      "sqlite3": {
        "bind": "ecosystem/xiom-sql/sqlite.xiom-bind",
        "link": "sqlite3",
        "search_paths": ["/usr/lib", "/usr/local/lib"]
      }
    }
  }
}
```

### 3. Linker Flags

The XIOM compiler must be invoked with the appropriate linker flags:

**Linux / macOS:**
```sh
xiom build --link sqlite3
```

**Windows (MinGW):**
```sh
xiom build --link sqlite3 --link-path /mingw64/lib
```

**Windows (MSVC):**
```sh
xiom build --link sqlite3.lib
```

### 4. Verification

Run the demo to verify the FFI is linked correctly:
```sh
xiom run ecosystem/xiom-sqlite/src/demo.xi --fn demo_in_memory
```

Expected output: no errors, all CRUD operations succeed silently. A successful run confirms the FFI bridge to `libsqlite3` is operational.

---

## Usage Examples

### Opening and Basic CRUD

```xiom
var conn = sqlite_open(":memory:")?;
sqlite_execute(&conn, "CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, age INTEGER);")?;
sqlite_execute(&conn, "INSERT INTO users (name, age) VALUES ('Alice', 30);")?;
var last_id = sqlite_last_insert_rowid(&conn);
var rows = sqlite_query(&conn, "SELECT id, name, age FROM users;")?;
sqlite_close(conn)?;
```

### Prepared Statement Lifecycle

```xiom
var conn = sqlite_open(":memory:")?;
sqlite_execute(&conn, "CREATE TABLE t (x INTEGER);")?;
sqlite_execute(&conn, "INSERT INTO t (x) VALUES (1), (2), (3);")?;

var stmt = sqlite_prepare(&conn, "SELECT x FROM t WHERE x > 1;")?;
var has_row = sqlite_step(&stmt)?;
while has_row {
  var val = sqlite_column_int(&stmt, 0);
  has_row = sqlite_step(&stmt)?;
};
sqlite_finalize(stmt)?;
sqlite_close(conn)?;
```

### Schema Definition & Table Creation

```xiom
use xiom.sqlite.schema;

var users_table = TableDef.new("users");
TableDef.add_auto_id(&mut users_table);
TableDef.add_column(&mut users_table, "name", SqliteAffinity.TextAff);
TableDef.add_column(&mut users_table, "email", SqliteAffinity.TextAff);

var create_sql = TableDef.to_create_sql(&users_table);
sqlite_execute(&conn, create_sql)?;
```

### Query Building

```xiom
use xiom.sqlite.query;

var qb = QueryBuilder.select("users");
QueryBuilder.column(&mut qb, "id");
QueryBuilder.column(&mut qb, "name");
QueryBuilder.where_eq(&mut qb, "email", "user@example.com");
QueryBuilder.order_by(&mut qb, "name", false);
QueryBuilder.limit(&mut qb, 10);

var sql = QueryBuilder.to_sql(&qb);
var rows = sqlite_query(&conn, sql)?;
```

### Migration Management

```xiom
use xiom.sqlite.migration;

var mgr = MigrationManager.new();

var m1 = Migration.new(1, "create_users",
  "CREATE TABLE users (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, email TEXT NOT NULL);",
  "DROP TABLE users;"
);
MigrationManager.add(&mut mgr, m1);

var m2 = Migration.new(2, "add_age",
  "ALTER TABLE users ADD COLUMN age INTEGER;",
  ""
);
MigrationManager.add(&mut mgr, m2);

var result = MigrationManager.up(&mut mgr, &conn);
```

---

## Directory Structure

```
ecosystem/xiom-sqlite/
  package.xi           Package manifest
  SPEC.md              This document
  src/
    types.xi           xiom.sqlite.types     — Value types & result sets
    schema.xi          xiom.sqlite.schema    — Schema DDL generation
    query.xi           xiom.sqlite.query     — Query builder
    connection.xi      xiom.sqlite.connection — FFI-backed connection (LIVE)
    migration.xi       xiom.sqlite.migration — Versioned migrations
    demo.xi            xiom.sqlite.demo      — Usage demonstrations
```

---

## Limitations & Known Gaps

1. **Parameter binding**: The `sqlite3_bind_*` family is declared in `sqlite.xiom-bind` but not yet exposed as XIOM functions. Parameterized statements currently require manual SQL escaping or using literal values. Future: `sqlite_bind_int`, `sqlite_bind_text`, `sqlite_bind_null`, `sqlite_bind_float`, `sqlite_bind_blob`.
2. **Statement reset**: `sqlite3_reset` is not yet wired. Prepared statements are single-use in the current API.
3. **Column name retrieval**: `sqlite3_column_name` is not yet called during `sqlite_query`. Column names can be obtained by adding `PRAGMA table_info` queries.
4. **Blob size limit**: Large blobs may exceed the implicit size tracking. Use `sqlite3_column_bytes` for exact sizes.
5. **Thread safety**: SQLite threading mode must be configured at compile time (`SQLITE_THREADSAFE`). The XIOM FFI layer does not add its own synchronization.
6. **C string conversion**: The `native.str_to_c` / `native.addr_of` / `native.read_u8` runtime intrinsics are assumed present. See **Runtime Functions Required** above.
