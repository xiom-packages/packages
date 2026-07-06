module xiom.db.storage.tuple
use xiom.db.error;

// Row / tuple representation and the columnar `ResultSet` container. A `Row` is
// an integer-valued record addressed by a monotonic id; the codec surface
// (`tuple_encode` / `tuple_decode`) is where a byte-level on-disk layout will
// land in Phase 1. Until then rows live in memory as `Vec[Int]`.

pub type Row = {
  id: UInt64;
  data: Vec[Int];
}

pub fn Row.new(id: UInt64, data: Vec[Int]) -> Row {
  return Row{ id: id, data: data };
}

pub fn Row.get_column(row: &Row, index: Int) -> Option[Int] {
  if index < 0 { return None; }
  if index >= row.data.len() { return None; }
  return Some(row.data[index]);
}

pub fn Row.set_column(row: &mut Row, index: Int, value: Int) -> Bool {
  if index < 0 { return false; }
  if index >= row.data.len() { return false; }
  row.data[index] = value;
  return true;
}

pub fn Row.column_count(row: &Row) -> Int {
  return row.data.len();
}

// --- Tuple codec (Phase 1) ---

// Serialize a row into a flat integer buffer: [id, len, col0, col1, ...].
// TODO(Phase 1): replace with a byte-packed, length-prefixed page encoding that
// respects `DatabaseConfig.page_size` and column types from the catalog.
pub fn tuple_encode(row: &Row) -> Vec[Int] {
  var out = Vec[Int].new();
  out.push(row.id as Int);
  out.push(row.data.len());
  var i = 0;
  while i < row.data.len() {
    out.push(row.data[i]);
    i = i + 1;
  }
  return out;
}

// Decode the flat buffer produced by `tuple_encode` back into a Row.
// TODO(Phase 1): validate against a schema and surface Corruption on mismatch.
pub fn tuple_decode(buf: &Vec[Int]) -> DbResult[Row] {
  if buf.len() < 2 {
    return Err(DbError.Corruption);
  }
  var id = buf[0];
  var count = buf[1];
  if count < 0 { return Err(DbError.Corruption); }
  if buf.len() < 2 + count { return Err(DbError.Corruption); }
  var data = Vec[Int].new();
  var i = 0;
  while i < count {
    data.push(buf[2 + i]);
    i = i + 1;
  }
  return Ok(Row{ id: id as UInt64, data: data });
}

pub type ResultSet = {
  columns: Vec[Str];
  rows: Vec[Row];
}

pub fn ResultSet.new(columns: Vec[Str]) -> ResultSet {
  var rows = Vec[Row].new();
  return ResultSet{ columns: columns, rows: rows };
}

pub fn ResultSet.add_row(rs: &mut ResultSet, row: Row) {
  rs.rows.push(row);
}

pub fn ResultSet.row_count(rs: &ResultSet) -> Int {
  return rs.rows.len();
}

pub fn ResultSet.column_count(rs: &ResultSet) -> Int {
  return rs.columns.len();
}

pub fn ResultSet.get_row(rs: &ResultSet, index: Int) -> Option[Row] {
  if index < 0 { return None; }
  if index >= rs.rows.len() { return None; }
  var r = rs.rows[index];
  return Some(r);
}
