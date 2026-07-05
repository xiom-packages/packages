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
  fn xiom_vec_ptr(vec_data: *UInt8) -> *UInt8;
  fn xiom_vec_len(vec_data: *UInt8) -> Int;
  fn xiom_alloc(size: Int) -> *UInt8;
  fn xiom_free_ptr(ptr: *UInt8);
  fn xiom_read_byte(buf: *UInt8, offset: Int) -> Int;
  fn xiom_write_byte(buf: *UInt8, offset: Int, value: Int);
  fn xiom_copy_from_vec(c_buf: *UInt8, vec_data: *UInt8, vec_len: Int, vec_cap: Int, offset: Int, count: Int);
  fn xiom_str_to_cstr(xiom_str: *UInt8, len: Int) -> *UInt8;
  fn xiom_free_cstr(cstr: *UInt8);
  fn xiom_ffi_panic(msg: *UInt8);
}

extern "C" {
  fn sqlite3_open(path: *UInt8, db_ptr: *UInt8) -> Int;
  fn sqlite3_close(db: *UInt8) -> Int;
  fn sqlite3_exec(db: *UInt8, sql: *UInt8, cb: *UInt8, arg: *UInt8, err: *UInt8) -> Int;
  fn sqlite3_prepare_v2(db: *UInt8, sql: *UInt8, len: Int, stmt: *UInt8, tail: *UInt8) -> Int;
  fn sqlite3_step(stmt: *UInt8) -> Int;
  fn sqlite3_column_int(stmt: *UInt8, col: Int) -> Int;
  fn sqlite3_column_double(stmt: *UInt8, col: Int) -> Float64;
  fn sqlite3_column_text(stmt: *UInt8, col: Int) -> *UInt8;
  fn sqlite3_column_bytes(stmt: *UInt8, col: Int) -> Int;
  fn sqlite3_column_type(stmt: *UInt8, col: Int) -> Int;
  fn sqlite3_column_count(stmt: *UInt8) -> Int;
  fn sqlite3_finalize(stmt: *UInt8) -> Int;
  fn sqlite3_errmsg(db: *UInt8) -> *UInt8;
  fn sqlite3_last_insert_rowid(db: *UInt8) -> Int;
  fn sqlite3_changes(db: *UInt8) -> Int;
  fn sqlite3_free(ptr: *UInt8);
}

const SQLITE_OK: Int = 0;
const SQLITE_ROW: Int = 100;
const SQLITE_DONE: Int = 101;
const SQLITE_INTEGER: Int = 1;
const SQLITE_FLOAT: Int = 2;
const SQLITE_TEXT: Int = 3;
const SQLITE_BLOB: Int = 4;
const SQLITE_NULL: Int = 5;

const PTR_SIZE: Int = 8;

fn read_ptr_from_buf(buf: *UInt8) -> Int
  requires: buf != 0
{
  var val: Int = 0;
  var shift: Int = 0;
  var i: Int = 0;
  while i < PTR_SIZE {
    var byte = unsafe { xiom_read_byte(buf, i) };
    var contrib = byte;
    if shift > 0 {
      var s: Int = 0;
      while s < shift {
        contrib = contrib * 256;
        s = s + 1;
      };
    };
    val = val + contrib;
    shift = shift + 8;
    i = i + 1;
  };
  return val;
}

fn write_ptr_to_buf(buf: *UInt8, val: Int)
  requires: buf != 0
{
  var i: Int = 0;
  var v = val;
  while i < PTR_SIZE {
    var byte = v % 256;
    v = v / 256;
    unsafe { xiom_write_byte(buf, i, byte); };
    i = i + 1;
  };
}

fn cstr_to_str(ptr: *UInt8) -> Str {
  if ptr == 0 {
    return "";
  };
  var result = "";
  var offset: Int = 0;
  while true {
    var byte = unsafe { xiom_read_byte(ptr, offset) };
    if byte == 0 { break; };
    var ch = unsafe { native.byte_to_char(byte) };
    result = result + ch;
    offset = offset + 1;
  };
  return result;
}

fn errmsg_to_str(db_handle: Int) -> Str {
  if db_handle == 0 {
    return "(null database handle)";
  };
  var ptr = unsafe { sqlite3_errmsg(db_handle) };
  if ptr == 0 {
    return "(no error message)";
  };
  return cstr_to_str(ptr);
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
  var result = "";
  if neg { result = "-"; };
  var k = chars.len();
  while k > 0 {
    k = k - 1;
    var d = chars[k];
    var ch = unsafe { native.codepoint_to_char(48 + d) };
    result = result + ch;
  };
  return result;
}

fn read_column_value(stmt_handle: Int, col: Int) -> SqliteValue {
  var col_type = unsafe { sqlite3_column_type(stmt_handle, col) };
  if col_type == SQLITE_NULL {
    return SqliteValue.null();
  };
  if col_type == SQLITE_INTEGER {
    var ival = unsafe { sqlite3_column_int(stmt_handle, col) };
    return SqliteValue.integer(ival);
  };
  if col_type == SQLITE_FLOAT {
    var fval = unsafe { sqlite3_column_double(stmt_handle, col) };
    return SqliteValue.real(fval);
  };
  if col_type == SQLITE_TEXT {
    var tptr = unsafe { sqlite3_column_text(stmt_handle, col) };
    if tptr == 0 {
      return SqliteValue.null();
    };
    return SqliteValue.text(cstr_to_str(tptr));
  };
  if col_type == SQLITE_BLOB {
    var bytes_len = unsafe { sqlite3_column_bytes(stmt_handle, col) };
    var blob = Vec[Int].new();
    if bytes_len > 0 {
      var bptr = unsafe { sqlite3_column_text(stmt_handle, col) };
      if bptr != 0 {
        var j: Int = 0;
        while j < bytes_len {
          var byte = unsafe { xiom_read_byte(bptr, j) };
          blob.push(byte);
          j = j + 1;
        };
      };
    };
    return SqliteValue.blob(blob);
  };
  return SqliteValue.null();
}

pub fn sqlite_open(path: Str) -> Result[SqliteConnection, Str]
  requires: path.len() > 0
{
  var c_path = unsafe { xiom_str_to_cstr(path, path.len()) };
  if c_path == 0 {
    return Err("failed to convert database path to C string");
  };

  var db_handle_buf = unsafe { xiom_alloc(PTR_SIZE) };
  if db_handle_buf == 0 {
    unsafe { xiom_free_cstr(c_path); };
    return Err("failed to allocate memory for database handle");
  };

  var rc = unsafe { sqlite3_open(c_path, db_handle_buf) };

  unsafe { xiom_free_cstr(c_path); };

  if rc != SQLITE_OK {
    var db_handle = read_ptr_from_buf(db_handle_buf);
    if db_handle != 0 {
      var msg = errmsg_to_str(db_handle);
      unsafe { sqlite3_close(db_handle); };
      unsafe { xiom_free_ptr(db_handle_buf); };
      var err = "sqlite3_open failed: " + msg;
      return Err(err);
    };
    unsafe { xiom_free_ptr(db_handle_buf); };
    var err = "sqlite3_open failed with error code " + int_to_str(rc);
    return Err(err);
  };

  var db_handle = read_ptr_from_buf(db_handle_buf);
  unsafe { xiom_free_ptr(db_handle_buf); };

  return Ok(SqliteConnection{ db_path: path; handle: db_handle; is_open: true; });
}

pub fn sqlite_close(conn: SqliteConnection) -> Result[Unit, Str]
  requires: conn.handle != 0
{
  if !conn.is_open {
    return Err("connection already closed");
  };
  var rc = unsafe { sqlite3_close(conn.handle) };
  if rc != SQLITE_OK {
    var msg = errmsg_to_str(conn.handle);
    var err = "sqlite3_close failed: " + msg;
    return Err(err);
  };
  return Ok({});
}

pub fn sqlite_execute(conn: &SqliteConnection, sql: Str) -> Result[Unit, Str]
  requires: conn.handle != 0
  requires: sql.len() > 0
{
  var c_sql = unsafe { xiom_str_to_cstr(sql, sql.len()) };
  if c_sql == 0 {
    return Err("failed to convert SQL to C string");
  };
  var rc = unsafe { sqlite3_exec(conn.handle, c_sql, 0, 0, 0) };
  if rc != SQLITE_OK {
    var msg = errmsg_to_str(conn.handle);
    var err = "sqlite3_exec failed: " + msg + " [SQL: " + sql + "]";
    return Err(err);
  };
  return Ok({});
}

pub fn sqlite_prepare(conn: &SqliteConnection, sql: Str) -> Result[SqliteStmt, Str]
  requires: conn.handle != 0
  requires: sql.len() > 0
{
  var c_sql = unsafe { xiom_str_to_cstr(sql, sql.len()) };
  if c_sql == 0 {
    return Err("failed to convert SQL to C string");
  };

  var stmt_buf = unsafe { xiom_alloc(PTR_SIZE) };
  if stmt_buf == 0 {
    return Err("failed to allocate memory for statement handle");
  };

  var rc = unsafe { sqlite3_prepare_v2(conn.handle, c_sql, -1, stmt_buf, 0) };
  if rc != SQLITE_OK {
    var msg = errmsg_to_str(conn.handle);
    unsafe { xiom_free_ptr(stmt_buf); };
    var err = "sqlite3_prepare_v2 failed: " + msg + " [SQL: " + sql + "]";
    return Err(err);
  };

  var stmt_handle = read_ptr_from_buf(stmt_buf);
  unsafe { xiom_free_ptr(stmt_buf); };

  return Ok(SqliteStmt{ handle: stmt_handle; sql: sql; });
}

pub fn sqlite_step(stmt: &SqliteStmt) -> Result[Bool, Str]
  requires: stmt.handle != 0
{
  var rc = unsafe { sqlite3_step(stmt.handle) };
  if rc == SQLITE_ROW {
    return Ok(true);
  };
  if rc == SQLITE_DONE {
    return Ok(false);
  };
  var err = "sqlite3_step failed with error code " + int_to_str(rc);
  return Err(err);
}

pub fn sqlite_column_int(stmt: &SqliteStmt, col: Int) -> Int
  requires: stmt.handle != 0
  requires: col >= 0
{
  return unsafe { sqlite3_column_int(stmt.handle, col) };
}

pub fn sqlite_column_float(stmt: &SqliteStmt, col: Int) -> Float64
  requires: stmt.handle != 0
  requires: col >= 0
{
  return unsafe { sqlite3_column_double(stmt.handle, col) };
}

pub fn sqlite_column_text(stmt: &SqliteStmt, col: Int) -> Str
  requires: stmt.handle != 0
  requires: col >= 0
{
  var ptr = unsafe { sqlite3_column_text(stmt.handle, col) };
  if ptr == 0 {
    return "";
  };
  return cstr_to_str(ptr);
}

pub fn sqlite_column_blob(stmt: &SqliteStmt, col: Int) -> Vec[Int]
  requires: stmt.handle != 0
  requires: col >= 0
{
  var bytes_len = unsafe { sqlite3_column_bytes(stmt.handle, col) };
  var blob = Vec[Int].new();
  if bytes_len <= 0 {
    return blob;
  };
  var ptr = unsafe { sqlite3_column_text(stmt.handle, col) };
  if ptr == 0 {
    return blob;
  };
  var i: Int = 0;
  while i < bytes_len {
    var byte = unsafe { xiom_read_byte(ptr, i) };
    blob.push(byte);
    i = i + 1;
  };
  return blob;
}

pub fn sqlite_query(conn: &SqliteConnection, sql: Str) -> Result[Vec[SqliteRow], Str]
  requires: conn.handle != 0
  requires: sql.len() > 0
{
  var stmt = sqlite_prepare(conn, sql)?;
  var col_count = unsafe { sqlite3_column_count(stmt.handle) };
  var rows = Vec[SqliteRow].new();
  var rc = unsafe { sqlite3_step(stmt.handle) };
  while rc == SQLITE_ROW {
    var row = SqliteRow.new();
    var i: Int = 0;
    while i < col_count {
      var v = read_column_value(stmt.handle, i);
      SqliteRow.add(&mut row, v);
      i = i + 1;
    };
    rows.push(row);
    rc = unsafe { sqlite3_step(stmt.handle) };
  };
  if rc != SQLITE_DONE {
    var msg = errmsg_to_str(conn.handle);
    sqlite_finalize(stmt)?;
    return Err("sqlite3_step failed: " + msg);
  };
  sqlite_finalize(stmt)?;
  return Ok(rows);
}

pub fn sqlite_finalize(stmt: SqliteStmt) -> Result[Unit, Str]
  requires: stmt.handle != 0
{
  var rc = unsafe { sqlite3_finalize(stmt.handle) };
  if rc != SQLITE_OK {
    var err = "sqlite3_finalize failed with error code " + int_to_str(rc);
    return Err(err);
  };
  return Ok({});
}

pub fn sqlite_last_insert_rowid(conn: &SqliteConnection) -> Int
  requires: conn.handle != 0
{
  return unsafe { sqlite3_last_insert_rowid(conn.handle) };
}

pub fn sqlite_changes(conn: &SqliteConnection) -> Int
  requires: conn.handle != 0
{
  return unsafe { sqlite3_changes(conn.handle) };
}

pub fn sqlite_is_open(conn: &SqliteConnection) -> Bool
  requires: conn.is_open
{
  return conn.is_open;
}

pub fn sqlite_path(conn: &SqliteConnection) -> Str {
  return conn.db_path;
}
