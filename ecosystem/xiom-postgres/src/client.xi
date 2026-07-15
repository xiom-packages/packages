module xiom.postgres.client

pub type PgConnection = {
  handle: Int;
  connected: Bool;
}

pub type PgResult = {
  columns: Vec[Str];
  rows: Vec[Vec[Option[Str]]];
  row_count: Int;
  col_count: Int;
}

pub fn pg_connect(conn_str: Str) -> Result[PgConnection, Str] {
  return Err("xiom-postgres: libpq FFI bridge not linked");
}

pub fn pg_disconnect(conn: &mut PgConnection) {
  conn.handle = 0;
  conn.connected = false;
}

pub fn pg_is_connected(conn: &PgConnection) -> Bool {
  return conn.connected;
}

pub fn pg_error_message(conn: &PgConnection) -> Str {
  return "xiom-postgres: libpq FFI bridge not linked";
}

pub fn pg_query(conn: &PgConnection, sql: Str) -> Result[PgResult, Str] {
  return Err("xiom-postgres: libpq FFI bridge not linked");
}

pub fn pg_execute_params(conn: &PgConnection, sql: Str, params: &Vec[Str]) -> Result[PgResult, Str] {
  return Err("xiom-postgres: libpq FFI bridge not linked");
}

pub fn pg_execute_batch(conn: &PgConnection, queries: &Vec[Str]) -> Result[Vec[PgResult], Str] {
  return Err("xiom-postgres: libpq FFI bridge not linked");
}

pub fn pg_escape_literal(conn: &PgConnection, value: Str) -> Str {
  return value;
}

pub fn pg_escape_identifier(conn: &PgConnection, name: Str) -> Str {
  return name;
}

pub fn pg_begin(conn: &PgConnection) -> Result[Int, Str] {
  return Err("xiom-postgres: libpq FFI bridge not linked");
}

pub fn pg_commit(conn: &PgConnection) -> Result[Int, Str] {
  return Err("xiom-postgres: libpq FFI bridge not linked");
}

pub fn pg_rollback(conn: &PgConnection) -> Result[Int, Str] {
  return Err("xiom-postgres: libpq FFI bridge not linked");
}
