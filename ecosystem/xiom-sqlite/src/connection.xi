module xiom.sqlite.connection

pub type SqliteConnection = {
  db_path: Str;
  is_open: Bool;
} derive[Clone]

pub fn SqliteConnection.open(path: Str) -> Result[SqliteConnection, SqliteError] {
  return Err(SqliteError{
    code: -1,
    message: "sqlite_open requires FFI bindings to libsqlite3 (Layer 4). This is an MVP stub.",
  });
}

pub fn SqliteConnection.close(conn: SqliteConnection) -> Result[Unit, SqliteError] {
  return Err(SqliteError{
    code: -1,
    message: "sqlite_close requires FFI bindings to libsqlite3 (Layer 4). This is an MVP stub.",
  });
}

pub fn SqliteConnection.is_connected(conn: &SqliteConnection) -> Bool {
  return conn.is_open;
}

pub fn SqliteConnection.path(conn: &SqliteConnection) -> Str {
  return conn.db_path;
}

pub fn sqlite_open(path: Str) -> Result[SqliteConnection, SqliteError] {
  return SqliteConnection.open(path);
}

pub fn sqlite_close(conn: SqliteConnection) -> Result[Unit, SqliteError] {
  return SqliteConnection.close(conn);
}

pub fn sqlite_execute(conn: &SqliteConnection, sql: Str) -> Result[SqliteResult, SqliteError] {
  return Err(SqliteError{
    code: -1,
    message: "sqlite_execute requires FFI bindings to libsqlite3 (Layer 4). This is an MVP stub. SQL: " + sql,
  });
}

pub fn sqlite_query(conn: &SqliteConnection, sql: Str) -> Result[SqliteResult, SqliteError] {
  return Err(SqliteError{
    code: -1,
    message: "sqlite_query requires FFI bindings to libsqlite3 (Layer 4). This is an MVP stub. SQL: " + sql,
  });
}

pub fn sqlite_prepare(conn: &SqliteConnection, sql: Str) -> Result[Int, SqliteError] {
  return Err(SqliteError{
    code: -1,
    message: "sqlite_prepare requires FFI bindings to libsqlite3 (Layer 4). This is an MVP stub. SQL: " + sql,
  });
}

pub fn sqlite_bind_int(stmt: Int, index: Int, value: Int) -> Result[Unit, SqliteError] {
  return Err(SqliteError{
    code: -1,
    message: "sqlite_bind_int requires FFI bindings to libsqlite3 (Layer 4). This is an MVP stub.",
  });
}

pub fn sqlite_bind_text(stmt: Int, index: Int, value: Str) -> Result[Unit, SqliteError] {
  return Err(SqliteError{
    code: -1,
    message: "sqlite_bind_text requires FFI bindings to libsqlite3 (Layer 4). This is an MVP stub.",
  });
}

pub fn sqlite_bind_null(stmt: Int, index: Int) -> Result[Unit, SqliteError] {
  return Err(SqliteError{
    code: -1,
    message: "sqlite_bind_null requires FFI bindings to libsqlite3 (Layer 4). This is an MVP stub.",
  });
}

pub fn sqlite_bind_real(stmt: Int, index: Int, value: Float64) -> Result[Unit, SqliteError] {
  return Err(SqliteError{
    code: -1,
    message: "sqlite_bind_real requires FFI bindings to libsqlite3 (Layer 4). This is an MVP stub.",
  });
}

pub fn sqlite_bind_blob(stmt: Int, index: Int, value: &Vec[Int]) -> Result[Unit, SqliteError] {
  return Err(SqliteError{
    code: -1,
    message: "sqlite_bind_blob requires FFI bindings to libsqlite3 (Layer 4). This is an MVP stub.",
  });
}

pub fn sqlite_step(stmt: Int) -> Result[Bool, SqliteError] {
  return Err(SqliteError{
    code: -1,
    message: "sqlite_step requires FFI bindings to libsqlite3 (Layer 4). This is an MVP stub.",
  });
}

pub fn sqlite_finalize(stmt: Int) -> Result[Unit, SqliteError] {
  return Err(SqliteError{
    code: -1,
    message: "sqlite_finalize requires FFI bindings to libsqlite3 (Layer 4). This is an MVP stub.",
  });
}

pub fn sqlite_last_insert_rowid(conn: &SqliteConnection) -> Int {
  return 0;
}

pub fn sqlite_reset(stmt: Int) -> Result[Unit, SqliteError] {
  return Err(SqliteError{
    code: -1,
    message: "sqlite_reset requires FFI bindings to libsqlite3 (Layer 4). This is an MVP stub.",
  });
}

pub fn sqlite_changes(conn: &SqliteConnection) -> Int {
  return 0;
}
