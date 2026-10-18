// xiom.sqlite.rows -- materialize query results into owned XIOM values.
//
// Pure XIOM on top of the confined FFI module (src/sqlite.xi); contains no
// `unsafe` and no extern declarations.

module xiom.sqlite.rows

use xiom.string;
use xiom.sqlite.ffi;
use xiom.sqlite.types;

// Internal flat hand-off for `query_one` (B-32): the prepare/step row
// plumbing stays out of the nested enum payload, and the public wrapper
// stays small enough to inline so the returned `Option[SqliteRow]` payload
// is not left behind in a dead frame.
type FirstRow = {
  present: Bool;
  row: SqliteRow;
}

/// Prepare `sql`, run it to completion, and materialize every row with its
/// column names.  Errors carry the SQLite result code and message.
/// Complexity: O(rows * columns).
pub fn query_all(db: Int, sql: Str) -> Result[SqliteResult, SqliteError]
  requires: db != 0
  requires: sql.len() > 0
{
  let prep = ffi.prepare(db, sql);
  if !prep.is_ok {
    return Err(prep.error);
  }
  let stmt: Int = prep.value;
  var result = SqliteResult.new();
  let ncols = ffi.column_count(stmt);
  var names = Vec[Str].new();
  var c: Int = 0;
  while c < ncols {
    names.push(ffi.column_name(stmt, c));
    c = c + 1;
  }
  result.set_column_names(names);
  var looping = true;
  while looping {
    let s = ffi.step(stmt);
    if !s.is_ok {
      var ignored = ffi.finalize(stmt);
      return Err(s.error);
    }
    if s.value {
      var row = SqliteRow.new();
      var k: Int = 0;
      while k < ncols {
        row.add(value_at(stmt, k));
        k = k + 1;
      }
      result.add_row(row);
    } else {
      looping = false;
    }
  }
  let fin = ffi.finalize(stmt);
  if !fin.is_ok {
    return Err(fin.error);
  }
  return Ok(result);
}

/// Execute `sql` and return the number of rows in the first result set.
/// Complexity: O(rows).
pub fn count_rows(db: Int, sql: Str) -> Result[Int, SqliteError]
  requires: db != 0
  requires: sql.len() > 0
{
  let r = query_all(db, sql);
  if !r.is_ok {
    return Err(r.error);
  }
  let res: SqliteResult = r.value;
  return Ok(res.row_count());
}

/// Prepare `sql`, return its first row when one exists (Ok(None) when the
/// result set is empty).  The statement is finalized before returning
/// (single step; unlike query_all this does not materialize the remaining
/// rows).
///
/// RESTORED at 0.5.0 to the natural `Result[Option[SqliteRow],
/// SqliteError]`: the nested enum payload corruption (finding B-26; repro
/// docs/repro/bindings-pilot/nested-payload/) is fixed on the v0.64.7
/// toolchain (re-verified 2026-10-18: failures=0, all shapes len=2) and the
/// flat RowOutcome workaround is retired.
/// Complexity: O(columns) for the returned row.
pub fn query_one(db: Int, sql: Str) -> Result[Option[SqliteRow], SqliteError]
  requires: db != 0
  requires: sql.len() > 0
{
  let r = first_row(db, sql);
  if !r.is_ok {
    return Err(r.error);
  }
  let found: FirstRow = r.value;
  if found.present {
    return Ok(Some(found.row));
  }
  return Ok(None);
}

// Single-step first-row reader behind `query_one`.  Returns a flat hand-off
// struct (not the public RowOutcome retired at 0.5.0); the nested
// `Result[Option[SqliteRow]]` is constructed only by the small wrapper above.
fn first_row(db: Int, sql: Str) -> Result[FirstRow, SqliteError]
  requires: db != 0
  requires: sql.len() > 0
{
  let prep = ffi.prepare(db, sql);
  if !prep.is_ok {
    return Err(prep.error);
  }
  let stmt: Int = prep.value;
  let s = ffi.step(stmt);
  if !s.is_ok {
    var ignored = ffi.finalize(stmt);
    return Err(s.error);
  }
  var row = SqliteRow.new();
  var has_row = false;
  if s.value {
    let ncols = ffi.column_count(stmt);
    var k: Int = 0;
    while k < ncols {
      row.add(value_at(stmt, k));
      k = k + 1;
    }
    has_row = true;
  }
  let fin = ffi.finalize(stmt);
  if !fin.is_ok {
    return Err(fin.error);
  }
  return Ok(FirstRow{ present: has_row, row: row });
}

/// Index of the first result column named `name`, or None when there is no
/// such column.  Name comparison uses `string.str_compare` (BUG 17
/// discipline: never `==` on Str values).
/// Complexity: O(columns).
pub fn SqliteResult.column_index(res: &SqliteResult, name: Str) -> Option[Int]
  requires: name.len() > 0
{
  var i: Int = 0;
  while i < res.column_names.len() {
    if string.str_compare(res.column_names[i], name) == 0 {
      return Some(i);
    }
    i = i + 1;
  }
  return None;
}

/// Value of the column named `name` in result row `row_index`, or None when
/// the row index or the column does not exist (by-name counterpart of
/// `SqliteRow.get`).
/// Complexity: O(columns).
pub fn SqliteResult.value_by_name(res: &SqliteResult, row_index: Int, name: Str) -> Option[SqliteValue]
  requires: name.len() > 0
{
  if row_index < 0 { return None; }
  if row_index >= res.rows.len() { return None; }
  let idx = SqliteResult.column_index(res, name);
  if !idx.is_some { return None; }
  let row = SqliteResult.get_row(res, row_index);
  if !row.is_some { return None; }
  let rw: SqliteRow = row.value;
  return SqliteRow.get(&rw, idx.value);
}

// Map one column of the current row to a SqliteValue. BLOBs are
// surfaced as NULL for now (column_blob is a Phase-2 item; see ROADMAP.md).
fn value_at(stmt: Int, col: Int) -> SqliteValue {
  let t = ffi.column_type(stmt, col);
  if t == ffi.SQLITE_INTEGER {
    return SqliteValue.integer(ffi.column_int64(stmt, col));
  }
  if t == ffi.SQLITE_FLOAT {
    return SqliteValue.real(ffi.column_double(stmt, col));
  }
  if t == ffi.SQLITE_TEXT {
    return SqliteValue.text(ffi.column_text(stmt, col));
  }
  return SqliteValue.null();
}
