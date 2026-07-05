module xiom.sqlite.connection

pub type SqliteConnection = {
  db_path: Str;
  handle: Int;
  is_open: Bool;
}

pub type SqliteStmt = {
  handle: Int;
  sql: Str;
}

extern "C" {
  fn sqlite3_open(path: *UInt8, db_handle: *UInt8) -> Int;
  fn sqlite3_close(db: Int) -> Int;
  fn sqlite3_exec(db: Int, sql: *UInt8, callback: Int, arg: Int, errmsg: *UInt8) -> Int;
  fn sqlite3_prepare_v2(db: Int, sql: *UInt8, len: Int, stmt: *UInt8, tail: *UInt8) -> Int;
  fn sqlite3_step(stmt: Int) -> Int;
  fn sqlite3_column_int(stmt: Int, col: Int) -> Int;
  fn sqlite3_column_double(stmt: Int, col: Int) -> Float64;
  fn sqlite3_column_text(stmt: Int, col: Int) -> *UInt8;
  fn sqlite3_column_bytes(stmt: Int, col: Int) -> Int;
  fn sqlite3_column_type(stmt: Int, col: Int) -> Int;
  fn sqlite3_column_count(stmt: Int) -> Int;
  fn sqlite3_finalize(stmt: Int) -> Int;
  fn sqlite3_errmsg(db: Int) -> *UInt8;
  fn sqlite3_last_insert_rowid(db: Int) -> Int;
  fn sqlite3_changes(db: Int) -> Int;
  fn sqlite3_free(ptr: Int);
}

const SQLITE_OK: Int = 0;
const SQLITE_ROW: Int = 100;
const SQLITE_DONE: Int = 101;
const SQLITE_INTEGER: Int = 1;
const SQLITE_FLOAT: Int = 2;
const SQLITE_TEXT: Int = 3;
const SQLITE_BLOB: Int = 4;
const SQLITE_NULL: Int = 5;

fn cstr_to_str(ptr: *UInt8) -> Str {
  var result = "";
  var offset: Int = 0;
  while true {
    var byte = unsafe { native.read_u8(ptr + offset) };
    if byte == 0 { break; };
    var ch = unsafe { native.byte_to_char(byte) };
    result = result + ch;
    offset = offset + 1;
  };
  return result;
}

fn errmsg_to_str(db: Int) -> Str {
  if db == 0 {
    return "(null database handle)";
  };
  var ptr = unsafe { sqlite3_errmsg(db, ) };
  if ptr == 0 {
    return "(no error message)";
  };
  return cstr_to_str(ptr);
}

pub fn sqlite_open(path: Str) -> Result[SqliteConnection, Str] {
  var c_path = native.str_to_c(path);
  var db_handle: Int = 0;
  var db_ptr = native.addr_of(db_handle);
  var rc = unsafe { sqlite3_open(c_path, db_ptr, ) };
  if rc != SQLITE_OK {
    if db_handle != 0 {
      var msg = errmsg_to_str(db_handle);
      unsafe { sqlite3_close(db_handle, ) };
      return Err("sqlite3_open failed: " + msg);
    };
    return Err("sqlite3_open failed with code " + int_to_str(rc));
  };
  return Ok(SqliteConnection{ db_path: path; handle: db_handle; is_open: true; });
}

pub fn sqlite_close(conn: SqliteConnection) -> Result[Unit, Str] {
  if !conn.is_open {
    return Err("connection already closed");
  };
  var rc = unsafe { sqlite3_close(conn.handle, ) };
  if rc != SQLITE_OK {
    return Err("sqlite3_close failed with code " + int_to_str(rc));
  };
  return Ok({});
}

pub fn sqlite_execute(conn: &SqliteConnection, sql: Str) -> Result[Unit, Str] {
  requires: conn.is_open;
  var c_sql = native.str_to_c(sql);
  var rc = unsafe { sqlite3_exec(conn.handle, c_sql, 0, 0, 0, ) };
  if rc != SQLITE_OK {
    var msg = errmsg_to_str(conn.handle);
    return Err("sqlite3_exec failed: " + msg + " [SQL: " + sql + "]");
  };
  return Ok({});
}

pub fn sqlite_query(conn: &SqliteConnection, sql: Str) -> Result[Vec[SqliteRow], Str] {
  requires: conn.is_open;
  var stmt = sqlite_prepare(conn, sql)?;
  var col_count = unsafe { sqlite3_column_count(stmt.handle, ) };
  var rows = Vec[SqliteRow].new();
  var rc = unsafe { sqlite3_step(stmt.handle, ) };
  while rc == SQLITE_ROW {
    var row = SqliteRow.new();
    var i: Int = 0;
    while i < col_count {
      var v = read_column_value(stmt.handle, i);
      SqliteRow.add(&mut row, v);
      i = i + 1;
    };
    rows.push(row);
    rc = unsafe { sqlite3_step(stmt.handle, ) };
  };
  if rc != SQLITE_DONE {
    var msg = errmsg_to_str(conn.handle);
    sqlite_finalize(stmt)?;
    return Err("sqlite3_step failed: " + msg);
  };
  sqlite_finalize(stmt)?;
  return Ok(rows);
}

pub fn sqlite_prepare(conn: &SqliteConnection, sql: Str) -> Result[SqliteStmt, Str] {
  requires: conn.is_open;
  var c_sql = native.str_to_c(sql);
  var stmt_handle: Int = 0;
  var stmt_ptr = native.addr_of(stmt_handle);
  var rc = unsafe { sqlite3_prepare_v2(conn.handle, c_sql, -1, stmt_ptr, 0, ) };
  if rc != SQLITE_OK {
    var msg = errmsg_to_str(conn.handle);
    return Err("sqlite3_prepare_v2 failed: " + msg + " [SQL: " + sql + "]");
  };
  return Ok(SqliteStmt{ handle: stmt_handle; sql: sql; });
}

pub fn sqlite_step(stmt: &SqliteStmt) -> Result[Bool, Str] {
  var rc = unsafe { sqlite3_step(stmt.handle, ) };
  if rc == SQLITE_ROW {
    return Ok(true);
  };
  if rc == SQLITE_DONE {
    return Ok(false);
  };
  return Err("sqlite3_step failed with code " + int_to_str(rc));
}

pub fn sqlite_column_int(stmt: &SqliteStmt, col: Int) -> Int {
  return unsafe { sqlite3_column_int(stmt.handle, col, ) };
}

pub fn sqlite_column_float(stmt: &SqliteStmt, col: Int) -> Float64 {
  return unsafe { sqlite3_column_double(stmt.handle, col, ) };
}

pub fn sqlite_column_text(stmt: &SqliteStmt, col: Int) -> Str {
  var ptr = unsafe { sqlite3_column_text(stmt.handle, col, ) };
  if ptr == 0 {
    return "";
  };
  return cstr_to_str(ptr);
}

pub fn sqlite_column_blob(stmt: &SqliteStmt, col: Int) -> Vec[Int] {
  var bytes_len = unsafe { sqlite3_column_bytes(stmt.handle, col, ) };
  var blob = Vec[Int].new();
  if bytes_len <= 0 {
    return blob;
  };
  var ptr = unsafe { sqlite3_column_text(stmt.handle, col, ) };
  var i: Int = 0;
  while i < bytes_len {
    var byte = unsafe { native.read_u8(ptr + i) };
    blob.push(byte);
    i = i + 1;
  };
  return blob;
}

fn read_column_value(stmt_handle: Int, col: Int) -> SqliteValue {
  var col_type = unsafe { sqlite3_column_type(stmt_handle, col, ) };
  if col_type == SQLITE_NULL {
    return SqliteValue.null();
  };
  if col_type == SQLITE_INTEGER {
    var ival = unsafe { sqlite3_column_int(stmt_handle, col, ) };
    return SqliteValue.integer(ival);
  };
  if col_type == SQLITE_FLOAT {
    var fval = unsafe { sqlite3_column_double(stmt_handle, col, ) };
    return SqliteValue.real(fval);
  };
  if col_type == SQLITE_TEXT {
    var tptr = unsafe { sqlite3_column_text(stmt_handle, col, ) };
    if tptr == 0 {
      return SqliteValue.null();
    };
    return SqliteValue.text(cstr_to_str(tptr));
  };
  if col_type == SQLITE_BLOB {
    var bytes_len = unsafe { sqlite3_column_bytes(stmt_handle, col, ) };
    var blob = Vec[Int].new();
    if bytes_len > 0 {
      var bptr = unsafe { sqlite3_column_text(stmt_handle, col, ) };
      var j: Int = 0;
      while j < bytes_len {
        var byte = unsafe { native.read_u8(bptr + j) };
        blob.push(byte);
        j = j + 1;
      };
    };
    return SqliteValue.blob(blob);
  };
  return SqliteValue.null();
}

pub fn sqlite_finalize(stmt: SqliteStmt) -> Result[Unit, Str] {
  var rc = unsafe { sqlite3_finalize(stmt.handle, ) };
  if rc != SQLITE_OK {
    return Err("sqlite3_finalize failed with code " + int_to_str(rc));
  };
  return Ok({});
}

pub fn sqlite_last_insert_rowid(conn: &SqliteConnection) -> Int {
  requires: conn.is_open;
  return unsafe { sqlite3_last_insert_rowid(conn.handle, ) };
}

pub fn sqlite_changes(conn: &SqliteConnection) -> Int {
  requires: conn.is_open;
  return unsafe { sqlite3_changes(conn.handle, ) };
}

pub fn sqlite_is_open(conn: &SqliteConnection) -> Bool {
  return conn.is_open;
}

pub fn sqlite_path(conn: &SqliteConnection) -> Str {
  return conn.db_path;
}

fn int_to_str(value: Int) -> Str {
  if value == 0 { return "0"; };
  var neg: Bool = value < 0;
  var val = value;
  if neg { val = -val; };
  var chars = Vec[Int].new();
  while val > 0 {
    var digit = val % 10;
    chars.push(digit);
    val = val / 10;
  };
  if neg {
    var result = "-";
  } else {
    var result = "";
  };
  var k = chars.len();
  while k > 0 {
    k = k - 1;
    var d = chars[k];
    var ch = native.codepoint_to_char(48 + d);
    result = result + ch;
  };
  return result;
}
