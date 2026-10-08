// xiom.sqlite.rows -- materialize query results into owned XIOM values.
//
// Pure XIOM on top of the confined FFI module (src/sqlite.xi); contains no
// `unsafe` and no extern declarations.

module probe_enum_nd.rows

use probe_enum_nd.ffi;
use probe_enum_nd.types;

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

// Map one column of the current row to a tagged SqliteValue. BLOBs are
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
