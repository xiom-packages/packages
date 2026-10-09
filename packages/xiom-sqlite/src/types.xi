module xiom.sqlite.types

// Value model for query results.
//
// 0.3.0 (compiler v0.64.2): the original user-enum model is RESTORED.  The
// 0.2.0 tagged-struct workaround existed only because enum payload reads
// were nondeterministically miscompiled on v0.64.0/v0.64.1 (finding B-01);
// v0.64.2 fixed that (m231; 6/6 stable rebuilds in the lane's repro plus
// native 3/3) and the workaround was retired at the repin.  The public API
// keeps the same constructors and accessors (`SqliteValue.integer(...)`,
// `.as_int()`, ...); the payload now lives in `SqliteValueKind`.
pub type SqliteValue = {
  value: SqliteValueKind;
}

pub enum SqliteValueKind {
  Null,
  Integer(value: Int),
  Real(value: Float64),
  Text(value: Str),
  Blob(value: Vec[Int]),
}

pub type SqliteRow = {
  columns: Vec[SqliteValue];
}

pub type SqliteResult = {
  rows: Vec[SqliteRow];
  column_names: Vec[Str];
  rows_affected: Int;
}

pub type SqliteError = {
  code: Int;
  message: Str;
}

pub fn SqliteValue.null() -> SqliteValue {
  return SqliteValue{ value: SqliteValueKind.Null };
}

pub fn SqliteValue.integer(val: Int) -> SqliteValue {
  return SqliteValue{ value: SqliteValueKind.Integer(val) };
}

pub fn SqliteValue.real(val: Float64) -> SqliteValue {
  return SqliteValue{ value: SqliteValueKind.Real(val) };
}

pub fn SqliteValue.text(val: Str) -> SqliteValue {
  return SqliteValue{ value: SqliteValueKind.Text(val) };
}

pub fn SqliteValue.blob(val: Vec[Int]) -> SqliteValue
  requires: val.len() >= 0
{
  return SqliteValue{ value: SqliteValueKind.Blob(val) };
}

/// Integer payload when the value is an integer, else None.
pub fn SqliteValue.as_int(val: &SqliteValue) -> Option[Int] {
  match val.value {
    SqliteValueKind.Integer(value) => Some(value),
    _ => None,
  }
}

/// Real payload when the value is a real, else None.
pub fn SqliteValue.as_real(val: &SqliteValue) -> Option[Float64] {
  match val.value {
    SqliteValueKind.Real(value) => Some(value),
    _ => None,
  }
}

/// Text payload when the value is text, else None.
pub fn SqliteValue.as_text(val: &SqliteValue) -> Option[Str] {
  match val.value {
    SqliteValueKind.Text(value) => Some(value),
    _ => None,
  }
}

/// Blob payload when the value is a blob, else None.
pub fn SqliteValue.as_blob(val: &SqliteValue) -> Option[Vec[Int]] {
  match val.value {
    SqliteValueKind.Blob(value) => Some(value),
    _ => None,
  }
}

/// True when the value is SQL NULL.
pub fn SqliteValue.is_null(val: &SqliteValue) -> Bool {
  match val.value {
    SqliteValueKind.Null => true,
    _ => false,
  }
}

/// Stable name of the value kind ("null", "integer", "real", "text",
/// "blob").
pub fn SqliteValue.kind_name(val: &SqliteValue) -> Str {
  match val.value {
    SqliteValueKind.Null => "null",
    SqliteValueKind.Integer(value) => "integer",
    SqliteValueKind.Real(value) => "real",
    SqliteValueKind.Text(value) => "text",
    SqliteValueKind.Blob(value) => "blob",
  }
}

pub fn SqliteRow.new() -> SqliteRow {
  var cols = Vec[SqliteValue].new();
  return SqliteRow{ columns: cols };
}

pub fn SqliteRow.add(row: &mut SqliteRow, value: SqliteValue) {
  row.columns.push(value);
}

// Deep copy: the BLOB vector is rebuilt so the clone never aliases the
// source (same intent as the 0.2.0 helper).
fn clone_sqlite_value(v: &SqliteValue) -> SqliteValue {
  let i = SqliteValue.as_int(v);
  if i.is_some {
    return SqliteValue{ value: SqliteValueKind.Integer(i.value) };
  }
  let r = SqliteValue.as_real(v);
  if r.is_some {
    return SqliteValue{ value: SqliteValueKind.Real(r.value) };
  }
  let t = SqliteValue.as_text(v);
  if t.is_some {
    return SqliteValue{ value: SqliteValueKind.Text(t.value) };
  }
  let b = SqliteValue.as_blob(v);
  if b.is_some {
    var rebuilt = Vec[Int].new();
    var i2: Int = 0;
    while i2 < b.value.len() {
      rebuilt.push(b.value[i2]);
      i2 = i2 + 1;
    }
    return SqliteValue{ value: SqliteValueKind.Blob(rebuilt) };
  }
  return SqliteValue{ value: SqliteValueKind.Null };
}

fn clone_sqlite_row(row: &SqliteRow) -> SqliteRow {
  var cols = Vec[SqliteValue].new();
  var i: Int = 0;
  while i < row.columns.len() {
    var v = clone_sqlite_value(&row.columns[i]);
    cols.push(v);
    i = i + 1;
  }
  return SqliteRow{ columns: cols };
}

pub fn SqliteRow.get(row: &SqliteRow, index: Int) -> Option[SqliteValue]
  requires: index >= 0; requires: index < row.columns.len()
{
  if index < 0 { return None; }
  if index >= row.columns.len() { return None; }
  var v = clone_sqlite_value(&row.columns[index]);
  return Some(v);
}

pub fn SqliteRow.column_count(row: &SqliteRow) -> Int {
  return row.columns.len();
}

pub fn SqliteResult.new() -> SqliteResult {
  var rows = Vec[SqliteRow].new();
  var names = Vec[Str].new();
  return SqliteResult{ rows: rows, column_names: names, rows_affected: 0 };
}

pub fn SqliteResult.add_row(result: &mut SqliteResult, row: SqliteRow) {
  result.rows.push(row);
  result.rows_affected = result.rows_affected + 1;
}

pub fn SqliteResult.set_column_names(result: &mut SqliteResult, names: Vec[Str]) {
  result.column_names = names;
}

pub fn SqliteResult.row_count(result: &SqliteResult) -> Int {
  return result.rows.len();
}

pub fn SqliteResult.column_count(result: &SqliteResult) -> Int {
  return result.column_names.len();
}

pub fn SqliteResult.get_row(result: &SqliteResult, index: Int) -> Option[SqliteRow]
  requires: index >= 0; requires: index < result.rows.len()
{
  if index < 0 { return None; }
  if index >= result.rows.len() { return None; }
  var r = clone_sqlite_row(&result.rows[index]);
  return Some(r);
}

pub fn SqliteError.new(code: Int, message: Str) -> SqliteError {
  return SqliteError{ code: code, message: message };
}
