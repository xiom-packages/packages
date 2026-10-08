// xiom.sqlite -- SQLite C API bindings.
//
// G5 confinement: this is the ONE module in the package that contains
// `unsafe` blocks and `extern "C"` declarations.  Every foreign call is
// wrapped here; all other modules are pure XIOM and call these safe wrappers.
//
// Library: vendored SQLite amalgamation (vendor/sqlite3.c, public domain),
// version 3.53.4, compiled into the test binary with `--c-source`.
// See SPEC.md for the G2 pin and the re-pin procedure.
//
// Error mapping: every fallible call returns Result[_, SqliteError] where
// `code` is a SQLite primary result code (SQLITE_OK=0, SQLITE_ERROR=1, ...)
// and `message` is the owning connection's sqlite3_errmsg text when a
// connection handle is available, otherwise a synthesized diagnostic.
// `error_name(code)` maps the common codes to stable identifiers.
//
// Lifetime: Db and Stmt handles are opaque Int addresses owned by the caller.
// The safe wrappers free nothing implicitly; close(db) and finalize(stmt)
// release the native resources.  Statement handles must be finalized before
// their connection is closed.

module xiom.sqlite.ffi

use xiom.sqlite.types;

// Read a little-endian u64 out-param slot that a C call wrote into an 8-byte
// XIOM buffer.  Plain Vec indexing: no raw-pointer deref, no stdlib
// pointer helpers (this module cannot import xiom.ffi -- its own module name
// shadows the `ffi` alias on compiler v0.64.0; see COMPILER-FINDINGS relay).
fn read_u64_le(buf: &Vec[UInt8]) -> Int
  requires: buf.len() >= 8
{
  let b0 = buf[0] as Int;
  let b1 = buf[1] as Int;
  let b2 = buf[2] as Int;
  let b3 = buf[3] as Int;
  let b4 = buf[4] as Int;
  let b5 = buf[5] as Int;
  let b6 = buf[6] as Int;
  let b7 = buf[7] as Int;
  return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
       | (b4 << 32) | (b5 << 40) | (b6 << 48) | (b7 << 56);
}

// Allocate an 8-byte zeroed out-param slot owned by XIOM.
fn out_slot() -> Vec[UInt8]
  requires: true
{
  var slot: Vec[UInt8] = Vec[UInt8].new();
  var z: Int = 0;
  while z < 8 {
    slot.push(0 as UInt8);
    z = z + 1;
  }
  return slot;
}

// ---------------------------------------------------------------------------
// Raw C declarations (private to this module)
// ---------------------------------------------------------------------------

extern "C" {
  fn sqlite3_libversion() -> *UInt8;
  fn sqlite3_libversion_number() -> Int;

  fn sqlite3_open(filename: *UInt8, ppDb: *UInt8) -> Int;
  fn sqlite3_close(db: *UInt8) -> Int;
  fn sqlite3_errmsg(db: *UInt8) -> *UInt8;
  fn sqlite3_errcode(db: *UInt8) -> Int;
  fn sqlite3_extended_errcode(db: *UInt8) -> Int;

  fn sqlite3_exec(db: *UInt8, sql: *UInt8, callback: Int, arg: Int, errmsg: *UInt8) -> Int;

  fn sqlite3_prepare_v2(db: *UInt8, sql: *UInt8, nByte: Int, ppStmt: *UInt8, pzTail: Int) -> Int;
  fn sqlite3_step(stmt: *UInt8) -> Int;
  fn sqlite3_finalize(stmt: *UInt8) -> Int;
  fn sqlite3_db_handle(stmt: *UInt8) -> *UInt8;

  fn sqlite3_bind_int64(stmt: *UInt8, idx: Int, val: Int) -> Int;
  fn sqlite3_bind_double(stmt: *UInt8, idx: Int, val: Float64) -> Int;
  fn sqlite3_bind_text(stmt: *UInt8, idx: Int, val: *UInt8, n: Int, destructor: Int) -> Int;
  fn sqlite3_bind_null(stmt: *UInt8, idx: Int) -> Int;

  fn sqlite3_column_type(stmt: *UInt8, idx: Int) -> Int;
  fn sqlite3_column_int64(stmt: *UInt8, idx: Int) -> Int;
  fn sqlite3_column_double(stmt: *UInt8, idx: Int) -> Float64;
  fn sqlite3_column_text(stmt: *UInt8, idx: Int) -> *UInt8;
  fn sqlite3_column_count(stmt: *UInt8) -> Int;
  fn sqlite3_column_name(stmt: *UInt8, idx: Int) -> *UInt8;

  fn sqlite3_changes(db: *UInt8) -> Int;
  fn sqlite3_last_insert_rowid(db: *UInt8) -> Int;
}

// ---------------------------------------------------------------------------
// Public constants (SQLite primary result codes and fundamental datatypes)
// ---------------------------------------------------------------------------

pub const SQLITE_OK: Int = 0;
pub const SQLITE_ERROR: Int = 1;
pub const SQLITE_INTERNAL: Int = 2;
pub const SQLITE_PERM: Int = 3;
pub const SQLITE_ABORT: Int = 4;
pub const SQLITE_BUSY: Int = 5;
pub const SQLITE_LOCKED: Int = 6;
pub const SQLITE_NOMEM: Int = 7;
pub const SQLITE_READONLY: Int = 8;
pub const SQLITE_INTERRUPT: Int = 9;
pub const SQLITE_IOERR: Int = 10;
pub const SQLITE_CORRUPT: Int = 11;
pub const SQLITE_NOTFOUND: Int = 12;
pub const SQLITE_FULL: Int = 13;
pub const SQLITE_CANTOPEN: Int = 14;
pub const SQLITE_PROTOCOL: Int = 15;
pub const SQLITE_EMPTY: Int = 16;
pub const SQLITE_SCHEMA: Int = 17;
pub const SQLITE_TOOBIG: Int = 18;
pub const SQLITE_CONSTRAINT: Int = 19;
pub const SQLITE_MISMATCH: Int = 20;
pub const SQLITE_MISUSE: Int = 21;
pub const SQLITE_NOLFS: Int = 22;
pub const SQLITE_AUTH: Int = 23;
pub const SQLITE_FORMAT: Int = 24;
pub const SQLITE_RANGE: Int = 25;
pub const SQLITE_NOTADB: Int = 26;
pub const SQLITE_ROW: Int = 100;
pub const SQLITE_DONE: Int = 101;

pub const SQLITE_INTEGER: Int = 1;
pub const SQLITE_FLOAT: Int = 2;
pub const SQLITE_TEXT: Int = 3;
pub const SQLITE_BLOB: Int = 4;
pub const SQLITE_NULL: Int = 5;

// ---------------------------------------------------------------------------
// Version
// ---------------------------------------------------------------------------

/// Runtime SQLite version string, e.g. "3.53.4".
/// Complexity: O(1).
pub fn libversion() -> Str
  requires: true
{
  unsafe { Str::from_c_str(sqlite3_libversion()) }
}

/// Runtime SQLite version as an integer, e.g. 3053004 for 3.53.4.
/// Complexity: O(1).
pub fn libversion_number() -> Int
  requires: true
{
  unsafe { sqlite3_libversion_number() }
}

// ---------------------------------------------------------------------------
// Connection
// ---------------------------------------------------------------------------

/// Open a database.  ":memory:" opens a private in-memory database.
/// Returns an opaque connection handle.
/// Complexity: O(1).
pub fn open(path: Str) -> Result[Int, SqliteError]
  requires: path.len() > 0
{
  unsafe {
    var slot = out_slot();
    let pp = slot.as_mut_ptr();
    let rc = sqlite3_open(path.c_str(), pp);
    let db = read_u64_le(&slot);
    if rc != 0 {
      if db != 0 {
        let msg = Str::from_c_str(sqlite3_errmsg(db as *UInt8));
        sqlite3_close(db as *UInt8);
        return Err(SqliteError.new(rc, msg));
      }
      return Err(SqliteError.new(rc, "sqlite: open failed"));
    }
    if db == 0 {
      return Err(SqliteError.new(1, "sqlite: open returned a null handle"));
    }
    Ok(db)
  }
}

/// Close a connection and release its resources.
/// Complexity: O(1).
pub fn close(db: Int) -> Result[Unit, SqliteError]
  requires: db != 0
{
  unsafe {
    let rc = sqlite3_close(db as *UInt8);
    if rc != 0 {
      return Err(SqliteError.new(rc, Str::from_c_str(sqlite3_errmsg(db as *UInt8))));
    }
    Ok({})
  }
}

/// Primary result code of the most recent failed call on this connection.
/// Complexity: O(1).
pub fn errcode(db: Int) -> Int
  requires: db != 0
{
  unsafe { sqlite3_errcode(db as *UInt8) }
}

/// Extended result code of the most recent failed call on this connection.
/// Complexity: O(1).
pub fn extended_errcode(db: Int) -> Int
  requires: db != 0
{
  unsafe { sqlite3_extended_errcode(db as *UInt8) }
}

/// Human-readable description of the most recent error on this connection.
/// Complexity: O(1).
pub fn errmsg(db: Int) -> Str
  requires: db != 0
{
  unsafe { Str::from_c_str(sqlite3_errmsg(db as *UInt8)) }
}

/// Rows modified by the most recent INSERT/UPDATE/DELETE on this connection.
/// Complexity: O(1).
pub fn changes(db: Int) -> Int
  requires: db != 0
{
  unsafe { sqlite3_changes(db as *UInt8) }
}

/// Rowid of the most recent successful INSERT on this connection.
/// Complexity: O(1).
pub fn last_insert_rowid(db: Int) -> Int
  requires: db != 0
{
  unsafe { sqlite3_last_insert_rowid(db as *UInt8) }
}

// ---------------------------------------------------------------------------
// One-shot execution
// ---------------------------------------------------------------------------

/// Execute one or more SQL statements, discarding any result rows.
/// Complexity: O(statements).
pub fn exec(db: Int, sql: Str) -> Result[Unit, SqliteError]
  requires: db != 0
  requires: sql.len() > 0
{
  unsafe {
    let rc = sqlite3_exec(db as *UInt8, sql.c_str(), 0, 0, null);
    if rc != 0 {
      return Err(SqliteError.new(rc, Str::from_c_str(sqlite3_errmsg(db as *UInt8))));
    }
    Ok({})
  }
}

// ---------------------------------------------------------------------------
// Prepared statements
// ---------------------------------------------------------------------------

/// Compile the first SQL statement in `sql` into a prepared statement.
/// Returns an opaque statement handle (finalize with `finalize`).
/// Complexity: O(sql).
pub fn prepare(db: Int, sql: Str) -> Result[Int, SqliteError]
  requires: db != 0
  requires: sql.len() > 0
{
  unsafe {
    var slot = out_slot();
    let pp = slot.as_mut_ptr();
    let rc = sqlite3_prepare_v2(db as *UInt8, sql.c_str(), -1, pp, 0);
    let stmt = read_u64_le(&slot);
    if rc != 0 {
      return Err(SqliteError.new(rc, Str::from_c_str(sqlite3_errmsg(db as *UInt8))));
    }
    if stmt == 0 {
      return Err(SqliteError.new(1, "sqlite: prepare produced no statement"));
    }
    Ok(stmt)
  }
}

/// Bind an integer to a 1-based parameter index.
/// Complexity: O(1).
pub fn bind_int64(stmt: Int, idx: Int, val: Int) -> Result[Unit, SqliteError]
  requires: stmt != 0
  requires: idx > 0
{
  unsafe {
    let rc = sqlite3_bind_int64(stmt as *UInt8, idx, val);
    if rc != 0 {
      return Err(SqliteError.new(rc, "sqlite: bind_int64 failed"));
    }
    Ok({})
  }
}

/// Bind a float to a 1-based parameter index.
/// Complexity: O(1).
pub fn bind_double(stmt: Int, idx: Int, val: Float64) -> Result[Unit, SqliteError]
  requires: stmt != 0
  requires: idx > 0
{
  unsafe {
    let rc = sqlite3_bind_double(stmt as *UInt8, idx, val);
    if rc != 0 {
      return Err(SqliteError.new(rc, "sqlite: bind_double failed"));
    }
    Ok({})
  }
}

/// Bind a text value to a 1-based parameter index.  SQLite copies the text
/// (SQLITE_TRANSIENT), so the value does not outlive this call.
/// Complexity: O(len(val)).
pub fn bind_text(stmt: Int, idx: Int, val: Str) -> Result[Unit, SqliteError]
  requires: stmt != 0
  requires: idx > 0
{
  unsafe {
    // destructor = SQLITE_TRANSIENT (-1): SQLite makes its own copy.
    let rc = sqlite3_bind_text(stmt as *UInt8, idx, val.c_str(), -1, -1);
    if rc != 0 {
      return Err(SqliteError.new(rc, "sqlite: bind_text failed"));
    }
    Ok({})
  }
}

/// Bind SQL NULL to a 1-based parameter index.
/// Complexity: O(1).
pub fn bind_null(stmt: Int, idx: Int) -> Result[Unit, SqliteError]
  requires: stmt != 0
  requires: idx > 0
{
  unsafe {
    let rc = sqlite3_bind_null(stmt as *UInt8, idx);
    if rc != 0 {
      return Err(SqliteError.new(rc, "sqlite: bind_null failed"));
    }
    Ok({})
  }
}

/// Advance a statement.  Ok(true) = a row is available (SQLITE_ROW);
/// Ok(false) = execution finished (SQLITE_DONE); Err otherwise.
/// Complexity: O(1) per step.
pub fn step(stmt: Int) -> Result[Bool, SqliteError]
  requires: stmt != 0
{
  unsafe {
    let rc = sqlite3_step(stmt as *UInt8);
    if rc == 100 { return Ok(true); }
    if rc == 101 { return Ok(false); }
    let db = sqlite3_db_handle(stmt as *UInt8);
    if db != null {
      return Err(SqliteError.new(rc, Str::from_c_str(sqlite3_errmsg(db))));
    }
    return Err(SqliteError.new(rc, "sqlite: step failed"));
  }
}

/// Release a prepared statement.
/// Complexity: O(1).
pub fn finalize(stmt: Int) -> Result[Unit, SqliteError]
  requires: stmt != 0
{
  unsafe {
    let rc = sqlite3_finalize(stmt as *UInt8);
    if rc != 0 {
      return Err(SqliteError.new(rc, "sqlite: finalize reported a prior step error"));
    }
    Ok({})
  }
}

// ---------------------------------------------------------------------------
// Column access (only valid while a row from step() is current)
// ---------------------------------------------------------------------------

/// Fundamental datatype of a column: SQLITE_INTEGER/FLOAT/TEXT/BLOB/NULL.
/// Complexity: O(1).
pub fn column_type(stmt: Int, idx: Int) -> Int
  requires: stmt != 0
  requires: idx >= 0
{
  unsafe { sqlite3_column_type(stmt as *UInt8, idx) }
}

/// Integer value of a column (SQLite coerces numerics).
/// Complexity: O(1).
pub fn column_int64(stmt: Int, idx: Int) -> Int
  requires: stmt != 0
  requires: idx >= 0
{
  unsafe { sqlite3_column_int64(stmt as *UInt8, idx) }
}

/// Float value of a column (SQLite coerces numerics).
/// Complexity: O(1).
pub fn column_double(stmt: Int, idx: Int) -> Float64
  requires: stmt != 0
  requires: idx >= 0
{
  unsafe { sqlite3_column_double(stmt as *UInt8, idx) }
}

/// Text value of a column; NULL and BLOB columns yield "".
/// Complexity: O(len).
pub fn column_text(stmt: Int, idx: Int) -> Str
  requires: stmt != 0
  requires: idx >= 0
{
  unsafe {
    let p = sqlite3_column_text(stmt as *UInt8, idx);
    if (p as Int) == 0 { return ""; }
    return Str::from_c_str(p);
  }
}

/// Number of columns in the result row.
/// Complexity: O(1).
pub fn column_count(stmt: Int) -> Int
  requires: stmt != 0
{
  unsafe { sqlite3_column_count(stmt as *UInt8) }
}

/// Name of a result column (0-based).
/// Complexity: O(len).
pub fn column_name(stmt: Int, idx: Int) -> Str
  requires: stmt != 0
  requires: idx >= 0
{
  unsafe {
    let p = sqlite3_column_name(stmt as *UInt8, idx);
    if (p as Int) == 0 { return ""; }
    return Str::from_c_str(p);
  }
}

// ---------------------------------------------------------------------------
// Error naming
// ---------------------------------------------------------------------------

/// Stable identifier for a primary result code ("SQLITE_OK", "SQLITE_BUSY",
/// "SQLITE_CONSTRAINT", ... ; "SQLITE_UNKNOWN" for unmapped codes).
/// Complexity: O(1).
///
/// The table uses numeric literals rather than this module's own exported
/// consts: on compiler v0.64.0, a function that references a large set of
/// sibling `pub const`s recurses the resolver into a stack overflow when the
/// package is compiled together with a stdlib-heavy catalog.  The public
/// consts above remain the single source of truth for callers.
pub fn error_name(code: Int) -> Str {
  if code == 0 { return "SQLITE_OK"; }
  if code == 1 { return "SQLITE_ERROR"; }
  if code == 2 { return "SQLITE_INTERNAL"; }
  if code == 3 { return "SQLITE_PERM"; }
  if code == 4 { return "SQLITE_ABORT"; }
  if code == 5 { return "SQLITE_BUSY"; }
  if code == 6 { return "SQLITE_LOCKED"; }
  if code == 7 { return "SQLITE_NOMEM"; }
  if code == 8 { return "SQLITE_READONLY"; }
  if code == 9 { return "SQLITE_INTERRUPT"; }
  if code == 10 { return "SQLITE_IOERR"; }
  if code == 11 { return "SQLITE_CORRUPT"; }
  if code == 12 { return "SQLITE_NOTFOUND"; }
  if code == 13 { return "SQLITE_FULL"; }
  if code == 14 { return "SQLITE_CANTOPEN"; }
  if code == 15 { return "SQLITE_PROTOCOL"; }
  if code == 16 { return "SQLITE_EMPTY"; }
  if code == 17 { return "SQLITE_SCHEMA"; }
  if code == 18 { return "SQLITE_TOOBIG"; }
  if code == 19 { return "SQLITE_CONSTRAINT"; }
  if code == 20 { return "SQLITE_MISMATCH"; }
  if code == 21 { return "SQLITE_MISUSE"; }
  if code == 22 { return "SQLITE_NOLFS"; }
  if code == 23 { return "SQLITE_AUTH"; }
  if code == 24 { return "SQLITE_FORMAT"; }
  if code == 25 { return "SQLITE_RANGE"; }
  if code == 26 { return "SQLITE_NOTADB"; }
  if code == 100 { return "SQLITE_ROW"; }
  if code == 101 { return "SQLITE_DONE"; }
  return "SQLITE_UNKNOWN";
}
