module xiom.sqlite.types

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

pub fn SqliteValue.blob(val: Vec[Int]) -> SqliteValue {
  return SqliteValue{ value: SqliteValueKind.Blob(val) };
}

pub fn SqliteValue.as_int(val: &SqliteValue) -> Option[Int] {
  match val.value {
    SqliteValueKind.Integer(value) => Some(value),
    _ => None,
  }
}

pub fn SqliteValue.as_real(val: &SqliteValue) -> Option[Float64] {
  match val.value {
    SqliteValueKind.Real(value) => Some(value),
    _ => None,
  }
}

pub fn SqliteValue.as_text(val: &SqliteValue) -> Option[Str] {
  match val.value {
    SqliteValueKind.Text(value) => Some(value),
    _ => None,
  }
}

pub fn SqliteValue.as_blob(val: &SqliteValue) -> Option[Vec[Int]] {
  match val.value {
    SqliteValueKind.Blob(value) => Some(value),
    _ => None,
  }
}

pub fn SqliteValue.is_null(val: &SqliteValue) -> Bool {
  match val.value {
    SqliteValueKind.Null => true,
    _ => false,
  }
}

pub fn SqliteRow.new() -> SqliteRow {
  var cols = Vec[SqliteValue].new();
  return SqliteRow{ columns: cols };
}

pub fn SqliteRow.add(row: &mut SqliteRow, value: SqliteValue) {
  row.columns.push(value);
}

fn clone_sqlite_value(v: &SqliteValue) -> SqliteValue {
  match v.value {
    SqliteValueKind.Null => SqliteValue{ value: SqliteValueKind.Null },
    SqliteValueKind.Integer(value) => SqliteValue{ value: SqliteValueKind.Integer(value) },
    SqliteValueKind.Real(value) => SqliteValue{ value: SqliteValueKind.Real(value) },
    SqliteValueKind.Text(value) => SqliteValue{ value: SqliteValueKind.Text(value) },
    SqliteValueKind.Blob(value) => SqliteValue{ value: SqliteValueKind.Blob(value) },
  }
}

fn clone_sqlite_row(row: &SqliteRow) -> SqliteRow {
  var cols = Vec[SqliteValue].new();
  var i: Int = 0;
  while i < row.columns.len() {
    var v = clone_sqlite_value(&row.columns[i]);
    cols.push(v);
    i = i + 1;
  };
  return SqliteRow{ columns: cols };
}

pub fn SqliteRow.get(row: &SqliteRow, index: Int) -> Option[SqliteValue] {
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

pub fn SqliteResult.get_row(result: &SqliteResult, index: Int) -> Option[SqliteRow] {
  if index < 0 { return None; }
  if index >= result.rows.len() { return None; }
  var r = clone_sqlite_row(&result.rows[index]);
  return Some(r);
}

pub fn SqliteError.new(code: Int, message: Str) -> SqliteError {
  return SqliteError{ code: code, message: message };
}
