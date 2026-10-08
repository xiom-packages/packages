// xiom.sqlite -- package entry module.
//
// Public safe API for the vendored SQLite amalgamation (3.53.4).  This module
// contains no `unsafe`: every function delegates to the confined FFI core in
// `xiom.sqlite.ffi`, which is the ONLY module in the package allowed to make
// foreign calls (G5).  Consumers may import this module plus
// `xiom.sqlite.rows` (result materialization), `xiom.sqlite.types` (value
// types), `xiom.sqlite.query` / `xiom.sqlite.schema` / `xiom.sqlite.migration`
// (pure query/DDL/migration helpers).
//
// Handle model: a connection is an opaque Int from `open`; a prepared
// statement is an opaque Int from `prepare`.  The caller owns both and
// releases them with `close` / `finalize`.
//
// Error model: fallible calls return Result[_, SqliteError] where `code` is a
// SQLite primary result code and `message` is the connection error text.
// `error_name(code)` maps codes to stable identifiers.

module xiom.sqlite

use xiom.sqlite.ffi;
use xiom.sqlite.types;

// Result codes and fundamental datatypes.
//
// Values are literals (matching xiom.sqlite.ffi and the SQLite C API) rather
// than `= ffi.X` aliases: on compiler v0.64.0, a cross-module const alias
// (`pub const A: Int = other_module.B`) recurses the resolver into a stack
// overflow when a consumer references it.  The values are frozen by SQLite's
// ABI; tests pin the codes the FFI actually returns.
pub const SQLITE_OK: Int = 0;
pub const SQLITE_ERROR: Int = 1;
pub const SQLITE_INTERNAL: Int = 2;
pub const SQLITE_PERM: Int = 3;
pub const SQLITE_ABORT: Int = 4;
pub const SQLITE_BUSY: Int = 5;
pub const SQLITE_LOCKED: Int = 6;
pub const SQLITE_NOMEM: Int = 7;
pub const SQLITE_READONLY: Int = 8;
pub const SQLITE_INTERRUPT: Int = 9;
pub const SQLITE_IOERR: Int = 10;
pub const SQLITE_CORRUPT: Int = 11;
pub const SQLITE_NOTFOUND: Int = 12;
pub const SQLITE_FULL: Int = 13;
pub const SQLITE_CANTOPEN: Int = 14;
pub const SQLITE_PROTOCOL: Int = 15;
pub const SQLITE_EMPTY: Int = 16;
pub const SQLITE_SCHEMA: Int = 17;
pub const SQLITE_TOOBIG: Int = 18;
pub const SQLITE_CONSTRAINT: Int = 19;
pub const SQLITE_MISMATCH: Int = 20;
pub const SQLITE_MISUSE: Int = 21;
pub const SQLITE_NOLFS: Int = 22;
pub const SQLITE_AUTH: Int = 23;
pub const SQLITE_FORMAT: Int = 24;
pub const SQLITE_RANGE: Int = 25;
pub const SQLITE_NOTADB: Int = 26;
pub const SQLITE_ROW: Int = 100;
pub const SQLITE_DONE: Int = 101;

pub const SQLITE_INTEGER: Int = 1;
pub const SQLITE_FLOAT: Int = 2;
pub const SQLITE_TEXT: Int = 3;
pub const SQLITE_BLOB: Int = 4;
pub const SQLITE_NULL: Int = 5;

/// Runtime SQLite version string, e.g. "3.53.4".
pub fn libversion() -> Str
  requires: true
{
  return ffi.libversion();
}

/// Runtime SQLite version as an integer, e.g. 3053004.
pub fn libversion_number() -> Int
  requires: true
{
  return ffi.libversion_number();
}

/// Open a database ("":memory:"" for a private in-memory database).
pub fn open(path: Str) -> Result[Int, SqliteError]
  requires: path.len() > 0
{
  return ffi.open(path);
}

/// Close a connection and release its resources.
pub fn close(db: Int) -> Result[Unit, SqliteError]
  requires: db != 0
{
  return ffi.close(db);
}

/// Primary result code of the most recent failed call on this connection.
pub fn errcode(db: Int) -> Int
  requires: db != 0
{
  return ffi.errcode(db);
}

/// Extended result code of the most recent failed call on this connection.
pub fn extended_errcode(db: Int) -> Int
  requires: db != 0
{
  return ffi.extended_errcode(db);
}

/// Human-readable description of the most recent error on this connection.
pub fn errmsg(db: Int) -> Str
  requires: db != 0
{
  return ffi.errmsg(db);
}

/// Rows modified by the most recent INSERT/UPDATE/DELETE.
pub fn changes(db: Int) -> Int
  requires: db != 0
{
  return ffi.changes(db);
}

/// Rowid of the most recent successful INSERT.
pub fn last_insert_rowid(db: Int) -> Int
  requires: db != 0
{
  return ffi.last_insert_rowid(db);
}

/// Execute one or more SQL statements, discarding result rows.
pub fn exec(db: Int, sql: Str) -> Result[Unit, SqliteError]
  requires: db != 0
  requires: sql.len() > 0
{
  return ffi.exec(db, sql);
}

/// Compile the first statement in `sql`; returns a statement handle.
pub fn prepare(db: Int, sql: Str) -> Result[Int, SqliteError]
  requires: db != 0
  requires: sql.len() > 0
{
  return ffi.prepare(db, sql);
}

/// Bind an integer to a 1-based parameter index.
pub fn bind_int64(stmt: Int, idx: Int, val: Int) -> Result[Unit, SqliteError]
  requires: stmt != 0
  requires: idx > 0
{
  return ffi.bind_int64(stmt, idx, val);
}

/// Bind a float to a 1-based parameter index.
pub fn bind_double(stmt: Int, idx: Int, val: Float64) -> Result[Unit, SqliteError]
  requires: stmt != 0
  requires: idx > 0
{
  return ffi.bind_double(stmt, idx, val);
}

/// Bind a text value to a 1-based parameter index (SQLite copies it).
pub fn bind_text(stmt: Int, idx: Int, val: Str) -> Result[Unit, SqliteError]
  requires: stmt != 0
  requires: idx > 0
{
  return ffi.bind_text(stmt, idx, val);
}

/// Bind SQL NULL to a 1-based parameter index.
pub fn bind_null(stmt: Int, idx: Int) -> Result[Unit, SqliteError]
  requires: stmt != 0
  requires: idx > 0
{
  return ffi.bind_null(stmt, idx);
}

/// Step a statement: Ok(true)=row, Ok(false)=done.
pub fn step(stmt: Int) -> Result[Bool, SqliteError]
  requires: stmt != 0
{
  return ffi.step(stmt);
}

/// Release a prepared statement.
pub fn finalize(stmt: Int) -> Result[Unit, SqliteError]
  requires: stmt != 0
{
  return ffi.finalize(stmt);
}

/// Fundamental datatype of a column (SQLITE_INTEGER/FLOAT/TEXT/BLOB/NULL).
pub fn column_type(stmt: Int, idx: Int) -> Int
  requires: stmt != 0
  requires: idx >= 0
{
  return ffi.column_type(stmt, idx);
}

/// Integer value of a column.
pub fn column_int64(stmt: Int, idx: Int) -> Int
  requires: stmt != 0
  requires: idx >= 0
{
  return ffi.column_int64(stmt, idx);
}

/// Float value of a column.
pub fn column_double(stmt: Int, idx: Int) -> Float64
  requires: stmt != 0
  requires: idx >= 0
{
  return ffi.column_double(stmt, idx);
}

/// Text value of a column; NULL/BLOB columns yield "".
pub fn column_text(stmt: Int, idx: Int) -> Str
  requires: stmt != 0
  requires: idx >= 0
{
  return ffi.column_text(stmt, idx);
}

/// Number of result columns.
pub fn column_count(stmt: Int) -> Int
  requires: stmt != 0
{
  return ffi.column_count(stmt);
}

/// Name of a result column (0-based).
pub fn column_name(stmt: Int, idx: Int) -> Str
  requires: stmt != 0
  requires: idx >= 0
{
  return ffi.column_name(stmt, idx);
}

/// Stable identifier for a primary result code.
pub fn error_name(code: Int) -> Str {
  return ffi.error_name(code);
}
