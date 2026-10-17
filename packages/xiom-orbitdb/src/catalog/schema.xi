// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom.db.catalog.schema

// Table and index definitions -- the database's data dictionary. A `Schema`
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

// Stable code for a column type (1 int, 2 float, 3 bool, 4 string, 5 bytes).
// Kept WITH the definition so consumers never pattern-match an imported enum
// (m225 consumer-scope caveat; C-ORBIT-07 hygiene) -- storage/schema layers
// compare codes instead.
pub fn column_type_code(t: ColumnType) -> Int {
  match t {
    IntType => { return 1; }
    FloatType => { return 2; }
    BoolType => { return 3; }
    StringType => { return 4; }
    BytesType => { return 5; }
  }
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
