# xiom-sqlite — SQLite Database Bindings for XIOM

## Package

**Name:** `xiom-sqlite`
**Version:** `0.1.0`
**Layer:** 3.3 — Ecosystem MVP
**Module:** `xiom.sqlite`

SQLite database bindings providing a complete type system, schema management, query building, and migration framework for XIOM. Connection and execution functions are MVP stubs pending FFI bindings (Layer 4).

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

### `xiom.sqlite.connection` — Connection Management
SQLite database connection lifecycle and query execution.

#### `SqliteConnection`

| Field | Type |
|---|---|
| `db_path` | `Str` |
| `is_open` | `Bool` |

#### API Reference

| Function | Signature | Status |
|---|---|---|
| `SqliteConnection.open` | `(path: Str) -> Result[SqliteConnection, SqliteError]` | STUB |
| `SqliteConnection.close` | `(conn: SqliteConnection) -> Result[Unit, SqliteError]` | STUB |
| `SqliteConnection.is_connected` | `(conn: &SqliteConnection) -> Bool` | LIVE |
| `SqliteConnection.path` | `(conn: &SqliteConnection) -> Str` | LIVE |
| `sqlite_execute` | `(conn: &SqliteConnection, sql: Str) -> Result[SqliteResult, SqliteError]` | STUB |
| `sqlite_query` | `(conn: &SqliteConnection, sql: Str) -> Result[SqliteResult, SqliteError]` | STUB |
| `sqlite_prepare` | `(conn: &SqliteConnection, sql: Str) -> Result[Int, SqliteError]` | STUB |
| `sqlite_bind_int` | `(stmt: Int, index: Int, value: Int) -> Result[Unit, SqliteError]` | STUB |
| `sqlite_bind_text` | `(stmt: Int, index: Int, value: Str) -> Result[Unit, SqliteError]` | STUB |
| `sqlite_bind_null` | `(stmt: Int, index: Int) -> Result[Unit, SqliteError]` | STUB |
| `sqlite_bind_real` | `(stmt: Int, index: Int, value: Float64) -> Result[Unit, SqliteError]` | STUB |
| `sqlite_bind_blob` | `(stmt: Int, index: Int, value: &Vec[Int]) -> Result[Unit, SqliteError]` | STUB |
| `sqlite_step` | `(stmt: Int) -> Result[Bool, SqliteError]` | STUB |
| `sqlite_finalize` | `(stmt: Int) -> Result[Unit, SqliteError]` | STUB |
| `sqlite_reset` | `(stmt: Int) -> Result[Unit, SqliteError]` | STUB |
| `sqlite_last_insert_rowid` | `(conn: &SqliteConnection) -> Int` | STUB (returns 0) |
| `sqlite_changes` | `(conn: &SqliteConnection) -> Int` | STUB (returns 0) |

All STUB functions return `SqliteError` with message indicating FFI dependency required at Layer 4.

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

## FFI Requirements (Layer 4)

The following `libsqlite3` C functions must be bound to complete this package:

| C Function | XIOM Binding | Purpose |
|---|---|---|
| `sqlite3_open_v2` | `SqliteConnection.open` | Open database |
| `sqlite3_close` | `SqliteConnection.close` | Close database |
| `sqlite3_exec` | `sqlite_execute` / `sqlite_query` | Execute SQL, collect results |
| `sqlite3_prepare_v2` | `sqlite_prepare` | Compile SQL to statement |
| `sqlite3_bind_int` | `sqlite_bind_int` | Bind integer parameter |
| `sqlite3_bind_text` | `sqlite_bind_text` | Bind text parameter |
| `sqlite3_bind_null` | `sqlite_bind_null` | Bind NULL |
| `sqlite3_bind_double` | `sqlite_bind_real` | Bind float parameter |
| `sqlite3_bind_blob` | `sqlite_bind_blob` | Bind blob parameter |
| `sqlite3_step` | `sqlite_step` | Execute statement, advance |
| `sqlite3_finalize` | `sqlite_finalize` | Destroy statement |
| `sqlite3_reset` | `sqlite_reset` | Reset statement for reuse |
| `sqlite3_last_insert_rowid` | `sqlite_last_insert_rowid` | Get last row ID |
| `sqlite3_changes` | `sqlite_changes` | Count changed rows |
| `sqlite3_column_count` | (via `sqlite_query`) | Column count in result |
| `sqlite3_column_name` | (via `sqlite_query`) | Column name |
| `sqlite3_column_type` | (via `sqlite_query`) | Column type |
| `sqlite3_column_int64` | (via `sqlite_query`) | Read integer |
| `sqlite3_column_double` | (via `sqlite_query`) | Read float |
| `sqlite3_column_text` | (via `sqlite_query`) | Read text |
| `sqlite3_column_blob` | (via `sqlite_query`) | Read blob |

---

## Usage Examples

### Schema Definition & Table Creation

```xiom
use xiom.sqlite.schema;

var users_table = TableDef.new("users");
TableDef.add_auto_id(&mut users_table);
TableDef.add_column(&mut users_table, "name", SqliteAffinity.TextAff);
TableDef.add_column(&mut users_table, "email", SqliteAffinity.TextAff);
TableDef.with_not_null(&mut email_col);

var create_sql = TableDef.to_create_sql(&users_table);
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
// SELECT id, name FROM users WHERE email = 'user@example.com' ORDER BY name ASC LIMIT 10;
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
    types.xi           xiom.sqlite.types    — Value types & result sets
    schema.xi          xiom.sqlite.schema   — Schema DDL generation
    query.xi           xiom.sqlite.query    — Query builder
    connection.xi      xiom.sqlite.connection — Connection stubs (FFI)
    migration.xi       xiom.sqlite.migration — Versioned migrations
```
