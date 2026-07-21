module xiom.db.catalog.schema

// Table and index definitions — the database's data dictionary. A `Schema`
// names a table's ordered columns and designates one of them as the primary
// key; an `IndexDef` describes a secondary access path. This module is pure
// metadata: it holds no rows and performs no validation (see schema_validator).

pub enum ColumnType {
  IntType,
  FloatType,
  BoolType,
  StringType,
  BytesType,
}

pub type ColumnDef = {
  name: Str;
  col_type: ColumnType;
  nullable: Bool;
  default_value: Option[Int];
}

pub fn ColumnDef.new(name: Str, col_type: ColumnType) -> ColumnDef
  requires: name.len() > 0
{
  return ColumnDef{
    name: name, col_type: col_type, nullable: false,
    default_value: None,
  };
}

pub fn ColumnDef.optional(name: Str, col_type: ColumnType, default_val: Option[Int]) -> ColumnDef
  requires: name.len() > 0
{
  return ColumnDef{
    name: name, col_type: col_type, nullable: true,
    default_value: default_val,
  };
}

pub type Schema = {
  table_name: Str;
  columns: Vec[ColumnDef];
  primary_key: Int;
}

pub fn Schema.new(table_name: Str, columns: Vec[ColumnDef], primary_key: Int) -> Schema
  requires: table_name.len() > 0
  requires: primary_key >= 0
{
  return Schema{ table_name: table_name, columns: columns, primary_key: primary_key };
}

pub fn Schema.column_index(schema: &Schema, name: Str) -> Option[Int]
  requires: name.len() > 0
{
  var i = 0;
  while i < schema.columns.len() {
    if schema.columns[i].name == name { return Some(i); }
    i = i + 1;
  }
  return None;
}

pub fn Schema.column_count(schema: &Schema) -> Int {
  return schema.columns.len();
}

pub enum IndexType {
  BTreeIndex,
  HashIndex,
}

pub type IndexDef = {
  name: Str;
  table: Str;
  column: Int;
  index_type: IndexType;
  unique: Bool;
}

pub fn IndexDef.new(name: Str, table: Str, column: Int, unique: Bool) -> IndexDef
  requires: name.len() > 0
{
  return IndexDef{
    name: name, table: table, column: column,
    index_type: IndexType.BTreeIndex, unique: unique,
  };
}
