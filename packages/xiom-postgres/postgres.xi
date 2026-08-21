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

pub fn connect(conn_string: Str) -> Result[Connection, Str]
  requires: conn_string.len() > 0
{
  return Err("xiom-postgres: libpq FFI bridge not linked -- PQconnectdb requires native runtime");
}

pub fn disconnect(conn: Connection)
  requires: conn != 0
{
}

pub fn is_connected(conn: Connection) -> Bool
  requires: conn != 0
{
  return false;
}

pub fn error_message(conn: Connection) -> Str
  requires: conn != 0
{
  return "xiom-postgres: libpq FFI bridge not linked";
}

pub fn connection_info(conn: Connection) -> Str
  requires: conn != 0
{
  return "xiom-postgres: not connected";
}

pub fn execute(conn: Connection, query: Str) -> Result[QueryResult, Str]
  requires: conn != 0
  requires: query.len() > 0
{
  return Err("xiom-postgres: libpq FFI bridge not linked");
}

pub fn execute_params(conn: Connection, query: Str, params: &Vec[Str]) -> Result[QueryResult, Str]
  requires: conn != 0
  requires: query.len() > 0
{
  return Err("xiom-postgres: libpq FFI bridge not linked");
}

pub fn execute_batch(conn: Connection, queries: &Vec[Str]) -> Result[Vec[QueryResult], Str]
  requires: conn != 0
  requires: queries.len() > 0
{
  return Err("xiom-postgres: libpq FFI bridge not linked");
}

pub fn escape_literal(conn: Connection, value: Str) -> Str
  requires: conn != 0
{
  return value;
}

pub fn escape_identifier(conn: Connection, name: Str) -> Str
  requires: conn != 0
{
  return name;
}

pub fn begin_transaction(conn: Connection) -> Result[Int, Str]
  requires: conn != 0
{
  return Err("xiom-postgres: libpq FFI bridge not linked");
}

pub fn commit(conn: Connection) -> Result[Int, Str]
  requires: conn != 0
{
  return Err("xiom-postgres: libpq FFI bridge not linked");
}

pub fn rollback(conn: Connection) -> Result[Int, Str]
  requires: conn != 0
{
  return Err("xiom-postgres: libpq FFI bridge not linked");
}

pub const CONNECTION_OK: Int = 0;
pub const CONNECTION_BAD: Int = 1;
pub const PGRES_COMMAND_OK: Int = 1;
pub const PGRES_TUPLES_OK: Int = 2;
pub const PGRES_FATAL_ERROR: Int = 7;
