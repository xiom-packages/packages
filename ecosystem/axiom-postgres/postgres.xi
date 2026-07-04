// XIOM — PostgreSQL Bindings (libpq)
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
module xiom.postgres

pub type Connection = Int;
pub type ResultSet = Int;

pub type Row = { values: Vec[Option[Str]]; } derive[Clone]
pub type QueryResult = {
  columns: Vec[Str];
  rows: Vec[Row];
  row_count: Int;
  col_count: Int;
} derive[Clone]

pub fn connect(conn_string: Str) -> Result[Connection, Str]
  requires: !conn_string.is_empty()
pub fn disconnect(conn: Connection);
pub fn is_connected(conn: Connection) -> Bool;
pub fn error_message(conn: Connection) -> Str;
pub fn connection_info(conn: Connection) -> Str;

pub fn execute(conn: Connection, query: Str) -> Result[QueryResult, Str];
pub fn execute_params(conn: Connection, query: Str, params: &Vec[Str]) -> Result[QueryResult, Str];
pub fn execute_batch(conn: Connection, queries: &Vec[Str]) -> Result[Vec[QueryResult], Str];

pub fn escape_literal(conn: Connection, value: Str) -> Str;
pub fn escape_identifier(conn: Connection, name: Str) -> Str;

pub fn begin_transaction(conn: Connection) -> Result[Unit, Str];
pub fn commit(conn: Connection) -> Result[Unit, Str];
pub fn rollback(conn: Connection) -> Result[Unit, Str];

pub const CONNECTION_OK: Int = 0;
pub const CONNECTION_BAD: Int = 1;
pub const PGRES_COMMAND_OK: Int = 1;
pub const PGRES_TUPLES_OK: Int = 2;
pub const PGRES_FATAL_ERROR: Int = 7;
