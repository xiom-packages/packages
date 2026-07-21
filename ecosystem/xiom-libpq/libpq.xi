// XIOM — libpq PostgreSQL C Client Library Bindings
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Phase 1 (v0.50.0): Pure SPEC layer — all FFI calls are stubs returning Err.
// Real C bridge will be linked after xiom.ffi matures.

module xiom.libpq

// ── Raw C interop (extern "C") ─────────────────────────────────────────────
// All 17 libpq functions. Return types are Int (opaque handles / status codes).
// String pointers are also returned as Int; safe wrappers handle conversion.

extern "C" {
  fn PQconnectdb(conninfo: *UInt8) -> Int;
  fn PQfinish(conn: Int);
  fn PQstatus(conn: Int) -> Int;
  fn PQerrorMessage(conn: Int) -> *UInt8;
  fn PQexec(conn: Int, query: *UInt8) -> Int;
  fn PQexecParams(conn: Int, query: *UInt8, nParams: Int, paramTypes: *UInt8, paramValues: *UInt8, paramLengths: *UInt8, paramFormats: *UInt8, resultFormat: Int) -> Int;
  fn PQntuples(res: Int) -> Int;
  fn PQnfields(res: Int) -> Int;
  fn PQfname(res: Int, column_number: Int) -> *UInt8;
  fn PQgetvalue(res: Int, row_number: Int, column_number: Int) -> *UInt8;
  fn PQgetisnull(res: Int, row_number: Int, column_number: Int) -> Int;
  fn PQclear(res: Int);
  fn PQsendQuery(conn: Int, query: *UInt8) -> Int;
  fn PQgetResult(conn: Int) -> Int;
  fn PQconsumeInput(conn: Int) -> Int;
  fn PQisBusy(conn: Int) -> Int;
  fn PQresultStatus(res: Int) -> Int;
}

// ── Opaque handle types ────────────────────────────────────────────────────

pub type PgConnection = Int;
pub type PgResult = Int;

// ── Connection status constants ────────────────────────────────────────────

pub const CONNECTION_OK: Int = 0;
pub const CONNECTION_BAD: Int = 1;

// ── Result status constants ────────────────────────────────────────────────

pub const PGRES_EMPTY_QUERY: Int = 0;
pub const PGRES_COMMAND_OK: Int = 1;
pub const PGRES_TUPLES_OK: Int = 2;
pub const PGRES_FATAL_ERROR: Int = 7;

// ── Safe connection wrappers ───────────────────────────────────────────────

pub fn connect(conninfo: Str) -> Result[PgConnection, Str]
  requires: conninfo.len() > 0
{
  return Err("connect: C bridge not yet linked — xiom-libpq is in SPEC phase");
}

pub fn close(conn: PgConnection)
  requires: conn != 0
{
}

pub fn status(conn: PgConnection) -> Int
  requires: conn != 0
{
  return CONNECTION_BAD;
}

pub fn error_message(conn: PgConnection) -> Str
  requires: conn != 0
{
  return "(spec stub — no C bridge)";
}

// ── Query execution ────────────────────────────────────────────────────────

pub fn exec(conn: PgConnection, sql: Str) -> Result[PgResult, Str]
  requires: conn != 0
  requires: sql.len() > 0
{
  return Err("exec: C bridge not yet linked — xiom-libpq is in SPEC phase");
}

pub fn exec_params(conn: PgConnection, sql: Str, params: Vec[Str]) -> Result[PgResult, Str]
  requires: conn != 0
  requires: sql.len() > 0
{
  return Err("exec_params: C bridge not yet linked — xiom-libpq is in SPEC phase");
}

// ── Result parsing ─────────────────────────────────────────────────────────

pub fn ntuples(res: PgResult) -> Int
  requires: res != 0
{
  return 0;
}

pub fn nfields(res: PgResult) -> Int
  requires: res != 0
{
  return 0;
}

pub fn fname(res: PgResult, col: Int) -> Str
  requires: res != 0
  requires: col >= 0
{
  return "(spec stub — no C bridge)";
}

pub fn get_value(res: PgResult, row: Int, col: Int) -> Str
  requires: res != 0
  requires: row >= 0
  requires: col >= 0
{
  return "(spec stub — no C bridge)";
}

pub fn get_is_null(res: PgResult, row: Int, col: Int) -> Bool
  requires: res != 0
{
  return true;
}

pub fn clear(res: PgResult)
  requires: res != 0
{
}

// ── Async / non-blocking ───────────────────────────────────────────────────

pub fn send_query(conn: PgConnection, sql: Str) -> Result[Int, Str]
  requires: conn != 0
  requires: sql.len() > 0
{
  return Err("send_query: C bridge not yet linked — xiom-libpq is in SPEC phase");
}

pub fn get_result(conn: PgConnection) -> Result[PgResult, Str]
{
  return Err("get_result: C bridge not yet linked — xiom-libpq is in SPEC phase");
}

pub fn consume_input(conn: PgConnection) -> Result[Int, Str]
{
  return Err("consume_input: C bridge not yet linked — xiom-libpq is in SPEC phase");
}

pub fn is_busy(conn: PgConnection) -> Bool
{
  return false;
}

// ── Transaction helpers ────────────────────────────────────────────────────

pub fn begin(conn: PgConnection) -> Result[PgResult, Str]
  requires: conn != 0
{
  return exec(conn, "BEGIN");
}

pub fn commit(conn: PgConnection) -> Result[PgResult, Str]
  requires: conn != 0
{
  return exec(conn, "COMMIT");
}

pub fn rollback(conn: PgConnection) -> Result[PgResult, Str]
  requires: conn != 0
{
  return exec(conn, "ROLLBACK");
}
