module xiom.db.types

pub type Page = {
  id: UInt64;
  data: Vec[UInt8];
  checksum: UInt32;
} derive[Clone]

pub fn Page.new(id: UInt64, data: Vec[UInt8], checksum: UInt32) -> Page
  requires: data.len() <= 4096
{
  return Page{ id: id, data: data, checksum: checksum };
}

pub fn Page.is_valid() -> Bool {
  return checksum == page_checksum(data);
}

fn page_checksum(data: &Vec[UInt8]) -> UInt32 {
  var sum: UInt32 = 0;
  var i = 0;
  while i < data.len() {
    sum = sum + (data[i] as UInt32);
    i = i + 1;
  }
  return sum;
}

pub type BufferPool = {
  pages: Vec[Option[Page]];
  capacity: Int;
  hits: Int;
  misses: Int;
}

pub fn BufferPool.new(capacity: Int) -> BufferPool {
  var pages = Vec[Option[Page]].new();
  var i = 0;
  while i < capacity {
    pages.push(None);
    i = i + 1;
  }
  return BufferPool{ pages: pages, capacity: capacity, hits: 0, misses: 0 };
}

pub fn BufferPool.put(pool: &mut BufferPool, page: Page) {
  var idx = page_id_index(page.id, pool.capacity);
  var current = pool.pages[idx];
  match current {
    None => { pool.misses = pool.misses + 1; }
    Some(_) => { pool.hits = pool.hits + 1; }
  }
  pool.pages[idx] = Some(page);
}

fn page_id_index(id: UInt64, capacity: Int) -> Int {
  return (id as Int) % capacity;
}

pub fn BufferPool.get(pool: &BufferPool, page_id: UInt64) -> Option[Page] {
  var idx = page_id_index(page_id, pool.capacity);
  var entry = pool.pages[idx];
  match entry {
    None => None,
    Some(p) => {
      if p.id == page_id {
        Some(p)
      } else {
        None
      }
    }
  }
}

pub fn BufferPool.hit_ratio(pool: &BufferPool) -> Float64 {
  var total = pool.hits + pool.misses;
  if total == 0 { return 0.0; }
  return (pool.hits as Float64) / (total as Float64);
}

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

pub fn ColumnDef.new(name: Str, col_type: ColumnType) -> ColumnDef {
  return ColumnDef{
    name: name, col_type: col_type, nullable: false,
    default_value: None,
  };
}

pub fn ColumnDef.optional(name: Str, col_type: ColumnType, default_val: Option[Int]) -> ColumnDef {
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

pub fn Schema.new(table_name: Str, columns: Vec[ColumnDef], primary_key: Int) -> Schema {
  return Schema{ table_name: table_name, columns: columns, primary_key: primary_key };
}

pub fn Schema.column_index(schema: &Schema, name: Str) -> Option[Int] {
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

pub fn IndexDef.new(name: Str, table: Str, column: Int, unique: Bool) -> IndexDef {
  return IndexDef{
    name: name, table: table, column: column,
    index_type: IndexType.BTreeIndex, unique: unique,
  };
}

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

pub type ResultSet = {
  columns: Vec<Str>;
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

pub enum DbError {
  NotFound,
  DuplicateKey,
  ConstraintViolation,
  SchemaMismatch,
  StorageError,
  Corruption,
}

pub fn DbError.to_string(err: DbError) -> Str {
  match err {
    NotFound => "not found",
    DuplicateKey => "duplicate key",
    ConstraintViolation => "constraint violation",
    SchemaMismatch => "schema mismatch",
    StorageError => "storage error",
    Corruption => "data corruption",
  }
}

pub type DbResult[T] = Result[T, DbError];

pub enum WALOp {
  Insert,
  Update,
  Delete,
}

pub enum TxState {
  Active,
  Committed,
  Aborted,
}

pub type Transaction = {
  id: UInt64;
  state: TxState;
  operations: Vec[WALOp];
}

pub fn Transaction.new(id: UInt64) -> Transaction {
  return Transaction{ id: id, state: TxState.Active, operations: [] };
}

pub fn Transaction.commit() -> Transaction {
  return Transaction{ id: id, state: TxState.Committed, operations: operations };
}

pub fn Transaction.abort() -> Transaction {
  return Transaction{ id: id, state: TxState.Aborted, operations: operations };
}

pub fn Transaction.add_op(op: WALOp) -> Transaction {
  var new_ops = operations;
  new_ops.push(op);
  return Transaction{ id: id, state: state, operations: new_ops };
}

pub fn Transaction.is_active() -> Bool {
  return state == TxState.Active;
}

pub type DatabaseConfig = {
  page_size: Int;
  buffer_pool_capacity: Int;
  wal_enabled: Bool;
  btree_order: Int;
}

pub fn DatabaseConfig.default() -> DatabaseConfig {
  return DatabaseConfig{
    page_size: 4096,
    buffer_pool_capacity: 64,
    wal_enabled: true,
    btree_order: 4,
  };
}

pub type StorageEngine = {
  config: DatabaseConfig;
  buffer_pool: BufferPool;
}

pub fn StorageEngine.new(config: DatabaseConfig) -> StorageEngine {
  var bp = BufferPool.new(config.buffer_pool_capacity);
  return StorageEngine{ config: config, buffer_pool: bp };
}

pub fn StorageEngine.cache_page(eng: &mut StorageEngine, page: Page) {
  eng.buffer_pool.put(page);
}

pub fn StorageEngine.lookup_page(eng: &StorageEngine, page_id: UInt64) -> Option[Page] {
  return eng.buffer_pool.get(page_id);
}
