module xiom.sqlite.types

// Value model for query results.
//
// Portability note (compiler v0.64.0): `SqliteValue` deliberately does NOT
// use a user-defined enum with payloads.  On this pin, enum payload reads are
// nondeterministically miscompiled (see docs/COMPILER-FINDINGS.md, the
// enum-payload findings), which made result accessors flaky across builds.
// A tagged struct with plain fields is stable and keeps the same public API
// (`SqliteValue.integer(...)`, `.as_int()`, ...).
pub type SqliteValue = {
  kind: Int;        // SqliteValueKind constants below
  ival: Int;        // kind 1
  fval: Float64;    // kind 2
  sval: Str;        // kind 3
  bval: Vec[Int];   // kind 4
}

// SqliteValue.kind tags.
pub const VALUE_NULL: Int = 0;
pub const VALUE_INTEGER: Int = 1;
pub const VALUE_REAL: Int = 2;
pub const VALUE_TEXT: Int = 3;
pub const VALUE_BLOB: Int = 4;

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
  return SqliteValue{
    kind: 0,
    ival: 0,
    fval: 0.0,
    sval: "",
    bval: Vec[Int].new(),
  };
}

pub fn SqliteValue.integer(val: Int) -> SqliteValue {
  return SqliteValue{
    kind: 1,
    ival: val,
    fval: 0.0,
    sval: "",
    bval: Vec[Int].new(),
  };
}

pub fn SqliteValue.real(val: Float64) -> SqliteValue {
  return SqliteValue{
    kind: 2,
    ival: 0,
    fval: val,
    sval: "",
    bval: Vec[Int].new(),
  };
}

pub fn SqliteValue.text(val: Str) -> SqliteValue {
  return SqliteValue{
    kind: 3,
    ival: 0,
    fval: 0.0,
    sval: val,
    bval: Vec[Int].new(),
  };
}

pub fn SqliteValue.blob(val: Vec[Int]) -> SqliteValue
  requires: val.len() >= 0
{
  return SqliteValue{
    kind: 4,
    ival: 0,
    fval: 0.0,
    sval: "",
    bval: val,
  };
}

/// Integer payload when kind == VALUE_INTEGER, else None.
pub fn SqliteValue.as_int(val: &SqliteValue) -> Option[Int] {
  if val.kind == 1 {
    return Some(val.ival);
  }
  return None;
}

/// Real payload when kind == VALUE_REAL, else None.
pub fn SqliteValue.as_real(val: &SqliteValue) -> Option[Float64] {
  if val.kind == 2 {
    return Some(val.fval);
  }
  return None;
}

/// Text payload when kind == VALUE_TEXT, else None.
pub fn SqliteValue.as_text(val: &SqliteValue) -> Option[Str] {
  if val.kind == 3 {
    return Some(val.sval);
  }
  return None;
}

/// Blob payload when kind == VALUE_BLOB, else None.
pub fn SqliteValue.as_blob(val: &SqliteValue) -> Option[Vec[Int]] {
  if val.kind == 4 {
    return Some(val.bval);
  }
  return None;
}

/// True when the value is SQL NULL.
pub fn SqliteValue.is_null(val: &SqliteValue) -> Bool {
  return val.kind == 0;
}

/// Stable name of the value kind ("null", "integer", "real", "text",
/// "blob").
pub fn SqliteValue.kind_name(val: &SqliteValue) -> Str {
  if val.kind == 0 { return "null"; }
  if val.kind == 1 { return "integer"; }
  if val.kind == 2 { return "real"; }
  if val.kind == 3 { return "text"; }
  if val.kind == 4 { return "blob"; }
  return "unknown";
}

pub fn SqliteRow.new() -> SqliteRow {
  var cols = Vec[SqliteValue].new();
  return SqliteRow{ columns: cols };
}

pub fn SqliteRow.add(row: &mut SqliteRow, value: SqliteValue) {
  row.columns.push(value);
}

fn clone_sqlite_value(v: &SqliteValue) -> SqliteValue {
  if v.kind == 4 {
    // Rebuild the blob vector so the clone never aliases the source.
    var b = Vec[Int].new();
    var i = 0;
    while i < v.bval.len() {
      b.push(v.bval[i]);
      i = i + 1;
    }
    return SqliteValue{ kind: v.kind, ival: v.ival, fval: v.fval, sval: v.sval, bval: b };
  }
  return SqliteValue{ kind: v.kind, ival: v.ival, fval: v.fval, sval: v.sval, bval: Vec[Int].new() };
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
