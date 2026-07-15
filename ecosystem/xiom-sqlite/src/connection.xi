module xiom.sqlite.connection

use xiom.sqlite.types;

pub type SqliteConnection = {
  db_path: Str;
  handle: Int;
  is_open: Bool;
}

pub type SqliteStmt = {
  handle: Int;
  sql: Str;
}

pub fn sqlite_open(path: Str) -> Result[SqliteConnection, SqliteError] {
  return Err(SqliteError{ code: -1, message: "xiom-sqlite: FFI bridge (ffi_bridge.c) not linked — sqlite3_open requires native runtime" });
}

pub fn sqlite_close(conn: SqliteConnection) -> Result[Int, SqliteError] {
  if !conn.is_open {
    return Err(SqliteError{ code: -1, message: "connection already closed" });
  };
  return Ok(0);
}

pub fn sqlite_execute(conn: &SqliteConnection, sql: Str) -> Result[Int, SqliteError] {
  return Err(SqliteError{ code: -1, message: "xiom-sqlite: FFI bridge (ffi_bridge.c) not linked — sqlite3_exec requires native runtime" });
}

pub fn sqlite_prepare(conn: &SqliteConnection, sql: Str) -> Result[SqliteStmt, SqliteError] {
  return Err(SqliteError{ code: -1, message: "xiom-sqlite: FFI bridge (ffi_bridge.c) not linked — sqlite3_prepare_v2 requires native runtime" });
}

pub fn sqlite_step(stmt: &SqliteStmt) -> Result[Bool, SqliteError] {
  return Err(SqliteError{ code: -1, message: "xiom-sqlite: FFI bridge (ffi_bridge.c) not linked — sqlite3_step requires native runtime" });
}

pub fn sqlite_column_int(stmt: &SqliteStmt, col: Int) -> Int {
  return 0;
}

pub fn sqlite_column_float(stmt: &SqliteStmt, col: Int) -> Float64 {
  return 0.0;
}

pub fn sqlite_column_text(stmt: &SqliteStmt, col: Int) -> Str {
  return "";
}

pub fn sqlite_column_blob(stmt: &SqliteStmt, col: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  return v;
}

pub fn sqlite_query(conn: &SqliteConnection, sql: Str) -> Result[Vec[SqliteRow], SqliteError] {
  return Err(SqliteError{ code: -1, message: "xiom-sqlite: FFI bridge (ffi_bridge.c) not linked — sqlite3_query requires native runtime" });
}

pub fn sqlite_finalize(stmt: SqliteStmt) -> Result[Int, SqliteError] {
  return Ok(0);
}

pub fn sqlite_last_insert_rowid(conn: &SqliteConnection) -> Int {
  return 0;
}

pub fn sqlite_changes(conn: &SqliteConnection) -> Int {
  return 0;
}

pub fn sqlite_is_open(conn: &SqliteConnection) -> Bool {
  return conn.is_open;
}

pub fn sqlite_path(conn: &SqliteConnection) -> Str {
  return conn.db_path;
}
