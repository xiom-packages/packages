module xiom.sqlite.schema

pub enum SqliteAffinity {
  IntegerAff,
  RealAff,
  TextAff,
  BlobAff,
  NullAff,
} derive[Clone]

pub type ColumnDef = {
  name: Str;
  col_type: SqliteAffinity;
  nullable: Bool;
  primary_key: Bool;
  auto_increment: Bool;
} derive[Clone]

pub type TableDef = {
  name: Str;
  columns: Vec[ColumnDef];
} derive[Clone]

pub type CreateIndexDef = {
  name: Str;
  table: Str;
  columns: Vec[Str];
  unique: Bool;
} derive[Clone]

pub fn SqliteAffinity.to_sql(affinity: &SqliteAffinity) -> Str {
  match affinity {
    SqliteAffinity.IntegerAff => "INTEGER",
    SqliteAffinity.RealAff => "REAL",
    SqliteAffinity.TextAff => "TEXT",
    SqliteAffinity.BlobAff => "BLOB",
    SqliteAffinity.NullAff => "NULL",
  }
}

pub fn ColumnDef.new(name: Str, col_type: SqliteAffinity) -> ColumnDef
  requires: name.len() > 0
{
  return ColumnDef{
    name: name,
    col_type: col_type,
    nullable: true,
    primary_key: false,
    auto_increment: false,
  };
}

pub fn ColumnDef.with_primary_key(col: &mut ColumnDef) {
  col.primary_key = true;
  col.nullable = false;
}

pub fn ColumnDef.with_auto_increment(col: &mut ColumnDef) {
  col.auto_increment = true;
}

pub fn ColumnDef.with_not_null(col: &mut ColumnDef) {
  col.nullable = false;
}

pub fn TableDef.new(name: Str) -> TableDef
  requires: name.len() > 0
{
  var columns = Vec[ColumnDef].new();
  return TableDef{ name: name, columns: columns };
}

pub fn TableDef.add_column(table: &mut TableDef, name: Str, col_type: SqliteAffinity)
  requires: name.len() > 0
{
  var col = ColumnDef.new(name, col_type);
  table.columns.push(col);
}

pub fn TableDef.add_primary_key(table: &mut TableDef, name: Str, col_type: SqliteAffinity)
  requires: name.len() > 0
{
  var col = ColumnDef.new(name, col_type);
  ColumnDef.with_primary_key(&mut col);
  table.columns.push(col);
}

pub fn TableDef.add_auto_id(table: &mut TableDef) {
  var col = ColumnDef.new("id", SqliteAffinity.IntegerAff);
  ColumnDef.with_primary_key(&mut col);
  ColumnDef.with_auto_increment(&mut col);
  table.columns.push(col);
}

pub fn TableDef.get_column(table: &TableDef, name: Str) -> Option[ColumnDef] {
  var i = 0;
  while i < table.columns.len() {
    if table.columns[i].name == name {
      return Some(table.columns[i].clone());
    }
    i = i + 1;
  }
  return None;
}

pub fn TableDef.column_count(table: &TableDef) -> Int {
  return table.columns.len();
}

pub fn TableDef.to_create_sql(table: &TableDef) -> Str {
  var sql = "CREATE TABLE ";
  sql = sql + table.name;
  sql = sql + " (";
  var i = 0;
  while i < table.columns.len() {
    if i > 0 {
      sql = sql + ", ";
    }
    var col = table.columns[i];
    sql = sql + col.name;
    sql = sql + " ";
    sql = sql + SqliteAffinity.to_sql(&col.col_type);
    if col.primary_key {
      sql = sql + " PRIMARY KEY";
    }
    if col.auto_increment {
      sql = sql + " AUTOINCREMENT";
    }
    if !col.nullable {
      sql = sql + " NOT NULL";
    }
    i = i + 1;
  }
  sql = sql + ");";
  return sql;
}

pub fn CreateIndexDef.new(name: Str, table: Str, columns: Vec[Str], unique: Bool) -> CreateIndexDef
  requires: name.len() > 0; requires: table.len() > 0; requires: columns.len() > 0
{
  return CreateIndexDef{
    name: name,
    table: table,
    columns: columns,
    unique: unique,
  };
}

pub fn CreateIndexDef.to_create_sql(idx: &CreateIndexDef) -> Str {
  var sql: Str;
  if idx.unique {
    sql = "CREATE UNIQUE INDEX ";
  } else {
    sql = "CREATE INDEX ";
  }
  sql = sql + idx.name;
  sql = sql + " ON ";
  sql = sql + idx.table;
  sql = sql + " (";
  var i = 0;
  while i < idx.columns.len() {
    if i > 0 {
      sql = sql + ", ";
    }
    sql = sql + idx.columns[i];
    i = i + 1;
  }
  sql = sql + ");";
  return sql;
}
