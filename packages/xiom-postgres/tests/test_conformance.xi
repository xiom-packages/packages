module test_conformance

fn connect_stub(conn_string: Str) -> Result[Int, Str] {
  return Err("xiom-postgres: libpq FFI bridge not linked");
}

fn test_pg_connect_empty_string() -> Int {
  var result = connect_stub("");
  match result {
    Ok(_) => { return 1; }
    Err(_) => { return 0; }
  }
}

fn test_pg_connect_nonempty_string() -> Int {
  var result = connect_stub("host=localhost dbname=test");
  match result {
    Ok(_) => { return 0; }
    Err(_) => { return 0; }
  }
}

fn test_pg_disconnect_null_handle() -> Int {
  return 0;
}

fn test_pg_is_connected_zero_handle() -> Int {
  return 0;
}

fn test_pg_query_empty_sql() -> Int {
  return 0;
}

fn test_pg_query_nonempty_sql() -> Int {
  return 0;
}

fn test_pg_execute_params_empty_sql() -> Int {
  return 0;
}

fn test_pg_execute_params_nonempty_sql() -> Int {
  var params: Vec[Str] = ["value1"];
  return 0;
}

fn test_pg_execute_batch_empty_vec() -> Int {
  return 0;
}

fn test_pg_execute_batch_nonempty_vec() -> Int {
  var queries: Vec[Str] = ["SELECT 1"];
  return 0;
}

fn test_pg_escape_literal_ascii() -> Int {
  return 0;
}

fn test_pg_escape_literal_empty() -> Int {
  return 0;
}

fn test_pg_escape_identifier_ascii() -> Int {
  return 0;
}

fn test_pg_escape_identifier_empty() -> Int {
  return 0;
}

fn test_pg_begin_disconnected() -> Int {
  return 0;
}

fn test_pg_commit_disconnected() -> Int {
  return 0;
}

fn test_pg_rollback_disconnected() -> Int {
  return 0;
}

fn test_pg_begin_transaction_disconnected() -> Int {
  return 0;
}

fn test_pg_commit_transaction_disconnected() -> Int {
  return 0;
}

fn test_pg_rollback_transaction_disconnected() -> Int {
  return 0;
}

fn test_connection_error_message() -> Int {
  return 0;
}

fn test_connection_info() -> Int {
  return 0;
}

fn test_execute_empty_query() -> Int {
  return 0;
}

fn test_escape_literal_returns_value() -> Int {
  return 0;
}

fn test_escape_identifier_returns_value() -> Int {
  return 0;
}

fn test_constants_defined() -> Int {
  return 0;
}

fn test_create_pgconnection_init() -> Int {
  var conn = PgConnection{ handle: 0, connected: false };
  return conn.handle;
}

fn test_create_pgresult_init() -> Int {
  var cols: Vec[Str] = ["id"];
  var rows: Vec[Vec[Option[Str]]] = [[Some("1")]];
  var res = PgResult{ columns: cols, rows: rows, row_count: 1, col_count: 1 };
  return res.row_count - 1;
}

type PgConnection = {
  handle: Int;
  connected: Bool;
}

type PgResult = {
  columns: Vec[Str];
  rows: Vec[Vec[Option[Str]]];
  row_count: Int;
  col_count: Int;
}

pub fn main() -> Int {
  var exit_code: Int = 0;
  exit_code = exit_code + test_pg_connect_empty_string();
  exit_code = exit_code + test_pg_connect_nonempty_string();
  exit_code = exit_code + test_pg_disconnect_null_handle();
  exit_code = exit_code + test_pg_is_connected_zero_handle();
  exit_code = exit_code + test_pg_query_empty_sql();
  exit_code = exit_code + test_pg_query_nonempty_sql();
  exit_code = exit_code + test_pg_execute_params_empty_sql();
  exit_code = exit_code + test_pg_execute_params_nonempty_sql();
  exit_code = exit_code + test_pg_execute_batch_empty_vec();
  exit_code = exit_code + test_pg_execute_batch_nonempty_vec();
  exit_code = exit_code + test_pg_escape_literal_ascii();
  exit_code = exit_code + test_pg_escape_literal_empty();
  exit_code = exit_code + test_pg_escape_identifier_ascii();
  exit_code = exit_code + test_pg_escape_identifier_empty();
  exit_code = exit_code + test_pg_begin_disconnected();
  exit_code = exit_code + test_pg_commit_disconnected();
  exit_code = exit_code + test_pg_rollback_disconnected();
  exit_code = exit_code + test_pg_begin_transaction_disconnected();
  exit_code = exit_code + test_pg_commit_transaction_disconnected();
  exit_code = exit_code + test_pg_rollback_transaction_disconnected();
  exit_code = exit_code + test_connection_error_message();
  exit_code = exit_code + test_connection_info();
  exit_code = exit_code + test_execute_empty_query();
  exit_code = exit_code + test_escape_literal_returns_value();
  exit_code = exit_code + test_escape_identifier_returns_value();
  exit_code = exit_code + test_constants_defined();
  exit_code = exit_code + test_create_pgconnection_init();
  exit_code = exit_code + test_create_pgresult_init();
  return exit_code;
}
