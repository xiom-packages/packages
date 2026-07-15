module xiom.postgres

pub type Connection = Int;

pub type Row = {
  values: Vec[Option[Str]];
}

pub type QueryResult = {
  columns: Vec[Str];
  rows: Vec[Row];
  row_count: Int;
  col_count: Int;
}

pub fn connect(conn_string: Str) -> Result[Connection, Str] {
  return Err("xiom-postgres: libpq FFI bridge not linked — PQconnectdb requires native runtime");
}

pub fn disconnect(conn: Connection) {
}

pub fn is_connected(conn: Connection) -> Bool {
  return false;
}

pub fn error_message(conn: Connection) -> Str {
  return "xiom-postgres: libpq FFI bridge not linked";
}

pub fn connection_info(conn: Connection) -> Str {
  return "xiom-postgres: not connected";
}

pub fn execute(conn: Connection, query: Str) -> Result[QueryResult, Str] {
  return Err("xiom-postgres: libpq FFI bridge not linked");
}

pub fn execute_params(conn: Connection, query: Str, params: &Vec[Str]) -> Result[QueryResult, Str] {
  return Err("xiom-postgres: libpq FFI bridge not linked");
}

pub fn execute_batch(conn: Connection, queries: &Vec[Str]) -> Result[Vec[QueryResult], Str] {
  return Err("xiom-postgres: libpq FFI bridge not linked");
}

pub fn escape_literal(conn: Connection, value: Str) -> Str {
  return value;
}

pub fn escape_identifier(conn: Connection, name: Str) -> Str {
  return name;
}

pub fn begin_transaction(conn: Connection) -> Result[Int, Str] {
  return Err("xiom-postgres: libpq FFI bridge not linked");
}

pub fn commit(conn: Connection) -> Result[Int, Str] {
  return Err("xiom-postgres: libpq FFI bridge not linked");
}

pub fn rollback(conn: Connection) -> Result[Int, Str] {
  return Err("xiom-postgres: libpq FFI bridge not linked");
}

pub const CONNECTION_OK: Int = 0;
pub const CONNECTION_BAD: Int = 1;
pub const PGRES_COMMAND_OK: Int = 1;
pub const PGRES_TUPLES_OK: Int = 2;
pub const PGRES_FATAL_ERROR: Int = 7;
