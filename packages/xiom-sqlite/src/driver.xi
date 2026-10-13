// xiom.sqlite.driver -- SQL driver facade for consumers (PULSE runner).
//
// Deliverable of docs/requirements/pulse-sql-driver.md (option A, released
// as 0.4.0): a `driver` module exposing `SqlDriver` -- open from a DSN,
// execute, query / query_one, explicit transactions with a rollback-on-error
// discipline, capability flags, and error mapping that never loses the
// SQLite code/message pair.  The driver owns NO migrations policy: locks,
// batches, ordering and the backup fence stay with the PULSE runner.
//
// Structure: this module imports package siblings (ffi/types/rows) plus the
// stdlib string/convert helpers.  No `unsafe` and no extern declarations --
// every foreign call stays confined to xiom.sqlite.ffi (G5), exactly like
// the other pure modules in this package.
//
// DSN grammar (sqlite):
//
//   [sqlite:|sqlite3:|sqlite://]PATH[?option=value[&option=value]...]
//
//   PATH                  a filesystem path, or ":memory:"
//   busy_timeout=<ms>     default 5000; 0 disables the busy handler
//   journal_mode=<mode>   delete|truncate|persist|memory|wal|off
//
// Malformed DSNs fail closed: unknown options, non-integer busy_timeout
// values and unknown journal modes return SQLITE_ERROR with a message the
// consumer can print verbatim (never a silent fallback).
//
// Transaction discipline (PULSE runner):
//
//   let b = SqlDriver.transaction_begin(&drv);
//   // every step returns Result; on the FIRST Err:
//   //   let rb = SqlDriver.transaction_rollback(&drv);
//   //   report the ORIGINAL error (rb tells you whether rollback worked)
//   // on success:
//   let c = SqlDriver.transaction_commit(&drv);
//
//   `SqlDriver.in_transaction` reports whether a transaction is open
//   (`sqlite3_get_autocommit`), so a runner can recover after a crash mid-
//   transaction.  SQLITE_TRANSACTIONAL_DDL: sqlite DDL is transactional, so
//   the runner may wrap migration DDL in BEGIN/COMMIT; the documented
//   `-- no-transaction` escape (runner flag) executes statements bare for
//   engines or statements that cannot run inside a transaction.

module xiom.sqlite.driver

use xiom.string;
use xiom.convert;
use xiom.sqlite.ffi;
use xiom.sqlite.rows;
use xiom.sqlite.types;

/// Parsed DSN: where to open plus the options to apply at open time.
pub type SqlDsn = {
  path: Str;
  busy_timeout_ms: Int;
  journal_mode: Str;
}

/// Outcome of a non-query execute(): rows changed by the last statement and
/// the connection's last insert rowid.
pub type ExecOutcome = {
  rows_affected: Int;
  last_insert_rowid: Int;
}

/// Capability flags for consumer feature-gating.
pub type DriverCaps = {
  transactional_ddl: Bool;
  supports_in_memory: Bool;
  journal_mode: Str;
  busy_timeout_ms: Int;
}

/// An open SQLite connection with its normalized DSN and applied options.
/// Owned by the caller; release with `SqlDriver.close`.  Statements are
/// prepared and finalized inside the driver -- the caller never sees a
/// statement handle.
pub type SqlDriver = {
  db: Int;
  dsn: Str;
  busy_timeout_ms: Int;
  journal_mode: Str;
}

fn str_eq(a: Str, b: Str) -> Bool {
  return string.str_compare(a, b) == 0;
}

fn journal_mode_valid(mode: Str) -> Bool {
  if str_eq(mode, "delete") { return true; }
  if str_eq(mode, "truncate") { return true; }
  if str_eq(mode, "persist") { return true; }
  if str_eq(mode, "memory") { return true; }
  if str_eq(mode, "wal") { return true; }
  if str_eq(mode, "off") { return true; }
  return false;
}

/// Parse and normalize a sqlite DSN.  See the module header for the grammar.
/// Complexity: O(len(dsn)).
pub fn SqlDsn.parse(dsn: Str) -> Result[SqlDsn, SqliteError]
  requires: dsn.len() > 0
{
  var body = dsn;
  let uri = string.str_strip_prefix(body, "sqlite://");
  if uri.is_some {
    body = uri.value;
  } else {
    let plain = string.str_strip_prefix(body, "sqlite:");
    if plain.is_some {
      body = plain.value;
    } else {
      let v3 = string.str_strip_prefix(body, "sqlite3:");
      if v3.is_some {
        body = v3.value;
      }
    }
  }
  let parts = string.str_split(body, "?");
  if parts.len() > 2 {
    return Err(SqliteError.new(ffi.SQLITE_ERROR, "dsn: multiple '?' separators"));
  }
  let path = parts[0];
  if path.len() == 0 {
    return Err(SqliteError.new(ffi.SQLITE_ERROR, "dsn: empty database path"));
  }
  var busy_ms: Int = 5000;
  var journal_mode = "";
  if parts.len() == 2 {
    let query = parts[1];
    if query.len() > 0 {
      let pairs = string.str_split(query, "&");
      var i: Int = 0;
      while i < pairs.len() {
        let pair = pairs[i];
        if pair.len() == 0 {
          return Err(SqliteError.new(ffi.SQLITE_ERROR, "dsn: empty option"));
        }
        let kv = string.str_split(pair, "=");
        if kv.len() != 2 {
          return Err(SqliteError.new(ffi.SQLITE_ERROR, "dsn: option needs key=value: " + pair));
        }
        let key = kv[0];
        let val = kv[1];
        if str_eq(key, "busy_timeout") {
          let parsed = string.str_to_int(val);
          if !parsed.is_ok {
            return Err(SqliteError.new(ffi.SQLITE_ERROR, "dsn: busy_timeout must be an integer: " + val));
          }
          if parsed.value < 0 {
            return Err(SqliteError.new(ffi.SQLITE_ERROR, "dsn: busy_timeout must be >= 0"));
          }
          busy_ms = parsed.value;
        } else {
          if str_eq(key, "journal_mode") {
            let mode = string.str_lower(val);
            if !journal_mode_valid(mode) {
              return Err(SqliteError.new(ffi.SQLITE_ERROR, "dsn: unknown journal_mode: " + val));
            }
            journal_mode = mode;
          } else {
            return Err(SqliteError.new(ffi.SQLITE_ERROR, "dsn: unknown option: " + key));
          }
        }
        i = i + 1;
      }
    }
  }
  return Ok(SqlDsn{ path: path, busy_timeout_ms: busy_ms, journal_mode: journal_mode });
}

// Run a single-column PRAGMA and return its first cell as text ("" when the
// pragma produces no row).  Used for the journal_mode readback at open:
// SQLite may keep the previous mode (or downgrade, e.g. no WAL for
// ":memory:"), so the driver records what is actually in effect.
fn read_pragma_text(db: Int, pragma: Str) -> Result[Str, SqliteError]
  requires: db != 0
  requires: pragma.len() > 0
{
  let p = ffi.prepare(db, "PRAGMA " + pragma + ";");
  if !p.is_ok {
    return Err(p.error);
  }
  let stmt: Int = p.value;
  let s = ffi.step(stmt);
  if !s.is_ok {
    var ignored = ffi.finalize(stmt);
    return Err(s.error);
  }
  var text = "";
  if s.value {
    text = ffi.column_text(stmt, 0);
  }
  let f = ffi.finalize(stmt);
  if !f.is_ok {
    return Err(f.error);
  }
  return Ok(text);
}

/// Open a driver from a DSN and apply its options (busy timeout, journal
/// mode).  On any failure the connection is closed before the error is
/// returned -- the caller never has to clean up a half-opened driver.
/// Complexity: O(len(dsn)).
pub fn SqlDriver.open_from_dsn(dsn: Str) -> Result[SqlDriver, SqliteError]
  requires: dsn.len() > 0
{
  let parsed = SqlDsn.parse(dsn);
  if !parsed.is_ok {
    return Err(parsed.error);
  }
  let spec: SqlDsn = parsed.value;
  let opened = ffi.open(spec.path);
  if !opened.is_ok {
    return Err(opened.error);
  }
  let db: Int = opened.value;
  let bt_sql = "PRAGMA busy_timeout = " + convert.int_to_string(spec.busy_timeout_ms) + ";";
  let bt = ffi.exec(db, bt_sql);
  if !bt.is_ok {
    var ignored = ffi.close(db);
    return Err(bt.error);
  }
  if spec.journal_mode.len() > 0 {
    let jm_sql = "PRAGMA journal_mode = " + spec.journal_mode + ";";
    let jm = ffi.exec(db, jm_sql);
    if !jm.is_ok {
      var ignored2 = ffi.close(db);
      return Err(jm.error);
    }
  }
  let effective = read_pragma_text(db, "journal_mode");
  if !effective.is_ok {
    var ignored3 = ffi.close(db);
    return Err(effective.error);
  }
  return Ok(SqlDriver{
    db: db,
    dsn: spec.path,
    busy_timeout_ms: spec.busy_timeout_ms,
    journal_mode: effective.value,
  });
}

/// Close the connection and release its resources.
/// Complexity: O(1).
pub fn SqlDriver.close(drv: &SqlDriver) -> Result[Unit, SqliteError]
  requires: drv.db != 0
{
  return ffi.close(drv.db);
}

/// The raw sqlite3* handle (opaque Int) for interop with the rest of
/// xiom.sqlite (e.g. MigrationManager, prepared-statement API).
/// Complexity: O(1).
pub fn SqlDriver.db(drv: &SqlDriver) -> Int {
  return drv.db;
}

/// Normalized database path this driver was opened with.
/// Complexity: O(1).
pub fn SqlDriver.dsn(drv: &SqlDriver) -> Str {
  return drv.dsn;
}

/// Effective journal mode after open (read back from the connection).
/// Complexity: O(1).
pub fn SqlDriver.journal_mode(drv: &SqlDriver) -> Str {
  return drv.journal_mode;
}

/// Effective busy timeout in milliseconds.
/// Complexity: O(1).
pub fn SqlDriver.busy_timeout_ms(drv: &SqlDriver) -> Int {
  return drv.busy_timeout_ms;
}

/// Execute a non-query statement (or a multi-statement script; result rows
/// are discarded).  Ok carries the rows changed by the LAST statement plus
/// the connection's last insert rowid.  For SELECT use `query`/`query_one`.
/// Complexity: O(statements).
pub fn SqlDriver.execute(drv: &SqlDriver, sql: Str) -> Result[ExecOutcome, SqliteError]
  requires: drv.db != 0
  requires: sql.len() > 0
{
  let r = ffi.exec(drv.db, sql);
  if !r.is_ok {
    return Err(r.error);
  }
  return Ok(ExecOutcome{
    rows_affected: ffi.changes(drv.db),
    last_insert_rowid: ffi.last_insert_rowid(drv.db),
  });
}

/// Run a query and materialize every row (typed values by index; the result
/// carries column names -- use `SqliteResult.value_by_name` /
/// `SqliteResult.column_index` in xiom.sqlite.rows for by-name access).
/// Complexity: O(rows * columns).
pub fn SqlDriver.query(drv: &SqlDriver, sql: Str) -> Result[SqliteResult, SqliteError]
  requires: drv.db != 0
  requires: sql.len() > 0
{
  return rows.query_all(drv.db, sql);
}

/// Run a query and return its first row as a flat RowOutcome (`has_row`
/// false when the result is empty; `row` is then an empty placeholder).
/// Deliberately not `Result[Option[SqliteRow]]` -- nested enum payloads
/// corrupt struct-with-Vec values on the current pin (finding B-26).
/// Complexity: O(columns) for the returned row.
pub fn SqlDriver.query_one(drv: &SqlDriver, sql: Str) -> Result[RowOutcome, SqliteError]
  requires: drv.db != 0
  requires: sql.len() > 0
{
  return rows.query_one(drv.db, sql);
}

/// Begin an explicit transaction.  Errors when a transaction is already
/// open (SQLITE_ERROR from SQLite) -- check `in_transaction` when unsure.
/// Complexity: O(1).
pub fn SqlDriver.transaction_begin(drv: &SqlDriver) -> Result[Unit, SqliteError]
  requires: drv.db != 0
{
  let r = ffi.exec(drv.db, "BEGIN;");
  if !r.is_ok {
    return Err(r.error);
  }
  return Ok({});
}

/// Commit the open transaction; without one SQLite reports SQLITE_ERROR.
/// Complexity: O(1).
pub fn SqlDriver.transaction_commit(drv: &SqlDriver) -> Result[Unit, SqliteError]
  requires: drv.db != 0
{
  let r = ffi.exec(drv.db, "COMMIT;");
  if !r.is_ok {
    return Err(r.error);
  }
  return Ok({});
}

/// Roll back the open transaction (rollback-on-error discipline: call this
/// on the first Err inside a transaction, then report the ORIGINAL error).
/// Without an open transaction SQLite reports SQLITE_ERROR.
/// Complexity: O(1).
pub fn SqlDriver.transaction_rollback(drv: &SqlDriver) -> Result[Unit, SqliteError]
  requires: drv.db != 0
{
  let r = ffi.exec(drv.db, "ROLLBACK;");
  if !r.is_ok {
    return Err(r.error);
  }
  return Ok({});
}

/// True while an explicit transaction is open on this connection.
/// Complexity: O(1).
pub fn SqlDriver.in_transaction(drv: &SqlDriver) -> Bool
  requires: drv.db != 0
{
  return !ffi.autocommit(drv.db);
}

/// The connection's most recent error as {code, message}; the pair is never
/// separated or rewritten.
/// Complexity: O(1).
pub fn SqlDriver.last_error(drv: &SqlDriver) -> SqliteError
  requires: drv.db != 0
{
  return SqliteError.new(ffi.errcode(drv.db), ffi.errmsg(drv.db));
}

/// Transactional-DDL capability flag: true for sqlite (schema DDL inside a
/// transaction is rolled back atomically; the consumer's `-- no-transaction`
/// escape is runner policy, not a driver limitation).
/// Complexity: O(1).
pub fn SqlDriver.transactional_ddl(drv: &SqlDriver) -> Bool
  requires: drv.db != 0
{
  return true;
}

/// Capability flags for consumer feature-gating.
/// Complexity: O(1).
pub fn SqlDriver.caps(drv: &SqlDriver) -> DriverCaps
  requires: drv.db != 0
{
  return DriverCaps{
    transactional_ddl: true,
    supports_in_memory: true,
    journal_mode: drv.journal_mode,
    busy_timeout_ms: drv.busy_timeout_ms,
  };
}
