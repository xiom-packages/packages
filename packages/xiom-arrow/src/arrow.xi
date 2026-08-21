// XIOM -- Arrow Library (Apache Arrow C Data Interface Bindings)
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Production-grade Arrow columnar format bindings for the XIOM ecosystem.
// Wraps the Arrow C Data Interface (ArrowArray, ArrowSchema) for zero-copy
// data sharing with Pandas, NumPy, and other Arrow-compatible libraries.
//
// Phase 1 (v0.1.0): Raw extern "C" stubs + safe wrappers + contracts
// Phase 2 (future):  IPC read/write, DataType algebra, table operations

module xiom.arrow

// ===============================================================================
// Types -- Opaque handles for Arrow C Data Interface
// ===============================================================================

pub type ArrowArray = Int
pub type ArrowSchema = Int

pub type DataType = {
  id: Int;
  name: Str;
} derive[Clone]

pub type Field = {
  name: Str;
  data_type: DataType;
  nullable: Bool;
} derive[Clone]

pub type Schema = {
  fields: Vec[Field];
} derive[Clone]

pub type Array = {
  handle: ArrowArray;
  length: Int;
  null_count: Int;
  data_type: DataType;
}

pub type Table = {
  schema: Schema;
  columns: Vec[Array];
  num_rows: Int;
}

// ===============================================================================
// DataType constructors
// ===============================================================================

pub fn dtype_null() -> DataType {
  DataType { id: 0; name: "null"; }
}

pub fn dtype_int8() -> DataType {
  DataType { id: 1; name: "int8"; }
}

pub fn dtype_int16() -> DataType {
  DataType { id: 2; name: "int16"; }
}

pub fn dtype_int32() -> DataType {
  DataType { id: 3; name: "int32"; }
}

pub fn dtype_int64() -> DataType {
  DataType { id: 4; name: "int64"; }
}

pub fn dtype_uint8() -> DataType {
  DataType { id: 5; name: "uint8"; }
}

pub fn dtype_uint16() -> DataType {
  DataType { id: 6; name: "uint16"; }
}

pub fn dtype_uint32() -> DataType {
  DataType { id: 7; name: "uint32"; }
}

pub fn dtype_uint64() -> DataType {
  DataType { id: 8; name: "uint64"; }
}

pub fn dtype_float32() -> DataType {
  DataType { id: 9; name: "float32"; }
}

pub fn dtype_float64() -> DataType {
  DataType { id: 10; name: "float64"; }
}

pub fn dtype_bool() -> DataType {
  DataType { id: 11; name: "bool"; }
}

pub fn dtype_utf8() -> DataType {
  DataType { id: 12; name: "utf8"; }
}

pub fn dtype_binary() -> DataType {
  DataType { id: 13; name: "binary"; }
}

pub fn dtype_date32() -> DataType {
  DataType { id: 14; name: "date32"; }
}

pub fn dtype_timestamp() -> DataType {
  DataType { id: 15; name: "timestamp"; }
}

pub fn data_type_from_id(id: Int) -> Result[DataType, Str]
  requires: id >= 0
  requires: id <= 15
{
  if id == 0  { return Ok(dtype_null()); }
  elif id == 1  { return Ok(dtype_int8()); }
  elif id == 2  { return Ok(dtype_int16()); }
  elif id == 3  { return Ok(dtype_int32()); }
  elif id == 4  { return Ok(dtype_int64()); }
  elif id == 5  { return Ok(dtype_uint8()); }
  elif id == 6  { return Ok(dtype_uint16()); }
  elif id == 7  { return Ok(dtype_uint32()); }
  elif id == 8  { return Ok(dtype_uint64()); }
  elif id == 9  { return Ok(dtype_float32()); }
  elif id == 10 { return Ok(dtype_float64()); }
  elif id == 11 { return Ok(dtype_bool()); }
  elif id == 12 { return Ok(dtype_utf8()); }
  elif id == 13 { return Ok(dtype_binary()); }
  elif id == 14 { return Ok(dtype_date32()); }
  elif id == 15 { return Ok(dtype_timestamp()); }
  else { return Err("data_type_from_id: unknown type id"); }
}

pub fn data_type_eq(a: &DataType, b: &DataType) -> Bool {
  a.id == b.id
}

pub fn data_type_name(dt: &DataType) -> Str {
  dt.name
}

// ===============================================================================
// Field constructors
// ===============================================================================

pub fn field_new(name: Str, data_type: DataType) -> Field
  requires: name.len() > 0
{
  Field { name: name; data_type: data_type; nullable: true }
}

pub fn field_new_non_nullable(name: Str, data_type: DataType) -> Field
  requires: name.len() > 0
{
  Field { name: name; data_type: data_type; nullable: false }
}

pub fn field_get_name(f: &Field) -> Str {
  f.name
}

pub fn field_get_type(f: &Field) -> DataType {
  f.data_type
}

pub fn field_is_nullable(f: &Field) -> Bool {
  f.nullable
}

// ===============================================================================
// Schema constructors
// ===============================================================================

pub fn schema_new(fields: Vec[Field]) -> Schema
  requires: fields.len() > 0
  ensures:  result.fields.len() == fields.len()
{
  Schema { fields: fields }
}

pub fn schema_empty() -> Schema {
  Schema { fields: Vec[Field].new() }
}

pub fn schema_add_field(s: &mut Schema, f: Field) {
  s.fields.push(f);
}

pub fn schema_num_fields(s: &Schema) -> Int {
  s.fields.len()
}

pub fn schema_get_field(s: &Schema, idx: Int) -> Result[Field, Str]
  requires: idx >= 0
{
  if idx >= s.fields.len() {
    return Err("schema_get_field: index out of bounds");
  };
  Ok(s.fields[idx])
}

// ===============================================================================
// Raw C Data Interface -- extern "C" stubs
// ===============================================================================

extern "C" {
  fn arrow_array_create(length: Int, n_buffers: Int) -> Int;
  fn arrow_array_free(arr: Int);
  fn arrow_array_get_length(arr: Int) -> Int;
  fn arrow_array_get_null_count(arr: Int) -> Int;
  fn arrow_array_get_offset(arr: Int) -> Int;
  fn arrow_array_get_n_buffers(arr: Int) -> Int;
  fn arrow_array_get_buffer(arr: Int, index: Int) -> Int;
  fn arrow_array_get_n_children(arr: Int) -> Int;
  fn arrow_array_get_child(arr: Int, index: Int) -> Int;
  fn arrow_schema_create(format: *UInt8, name: *UInt8) -> Int;
  fn arrow_schema_free(schema: Int);
  fn arrow_schema_get_format(schema: Int) -> Int;
  fn arrow_schema_get_name(schema: Int) -> Int;
  fn arrow_record_batch_create(schema: Int, n_columns: Int, columns: Int) -> Int;
  fn arrow_record_batch_get_column(batch: Int, index: Int) -> Int;
  fn arrow_record_batch_get_schema(batch: Int) -> Int;
}

// ===============================================================================
// Safe wrappers -- ArrowArray
// ===============================================================================

pub fn array_create(length: Int, n_buffers: Int) -> Result[ArrowArray, Str]
  requires: length >= 0
  requires: n_buffers >= 0
  requires: n_buffers <= 3
{
  if length < 0 { return Err("array_create: length must be non-negative"); };
  if n_buffers < 0 { return Err("array_create: n_buffers must be non-negative"); };
  if n_buffers > 3 { return Err("array_create: n_buffers must be at most 3 (validity, data, offsets)"); };
  unsafe {
    let handle = arrow_array_create(length, n_buffers);
    if handle == 0 {
      return Err("array_create: allocation failed (null handle)");
    };
    Ok(handle)
  }
}

pub fn array_free(arr: ArrowArray)
  requires: arr != 0
{
  unsafe { arrow_array_free(arr); }
}

pub fn array_get_length(arr: ArrowArray) -> Int
  requires: arr != 0
{
  unsafe { return arrow_array_get_length(arr); }
}

pub fn array_get_null_count(arr: ArrowArray) -> Int
  requires: arr != 0
{
  unsafe { return arrow_array_get_null_count(arr); }
}

pub fn array_get_offset(arr: ArrowArray) -> Int
  requires: arr != 0
{
  unsafe { return arrow_array_get_offset(arr); }
}

pub fn array_get_n_buffers(arr: ArrowArray) -> Int
  requires: arr != 0
{
  unsafe { return arrow_array_get_n_buffers(arr); }
}

pub fn array_get_buffer(arr: ArrowArray, index: Int) -> Result[Int, Str]
  requires: arr != 0
  requires: index >= 0
{
  let n_buf = array_get_n_buffers(arr);
  if index >= n_buf {
    return Err("array_get_buffer: buffer index out of bounds");
  };
  unsafe {
    let buf = arrow_array_get_buffer(arr, index);
    if buf == 0 {
      return Err("array_get_buffer: null buffer pointer");
    };
    Ok(buf)
  }
}

pub fn array_get_n_children(arr: ArrowArray) -> Int
  requires: arr != 0
{
  unsafe { return arrow_array_get_n_children(arr); }
}

pub fn array_get_child(arr: ArrowArray, index: Int) -> Result[ArrowArray, Str]
  requires: arr != 0
  requires: index >= 0
{
  let n_children = array_get_n_children(arr);
  if index >= n_children {
    return Err("array_get_child: child index out of bounds");
  };
  unsafe {
    let child = arrow_array_get_child(arr, index);
    if child == 0 {
      return Err("array_get_child: null child pointer");
    };
    Ok(child)
  }
}

// ===============================================================================
// Safe wrappers -- ArrowSchema
// ===============================================================================

pub fn schema_create(format: Str, name: Str) -> Result[ArrowSchema, Str]
  requires: format.len() > 0
{
  if format.len() == 0 { return Err("schema_create: format string must not be empty"); };
  unsafe {
    let handle = arrow_schema_create(format, name);
    if handle == 0 {
      return Err("schema_create: allocation failed (null handle)");
    };
    Ok(handle)
  }
}

pub fn schema_free(schema: ArrowSchema)
  requires: schema != 0
{
  unsafe { arrow_schema_free(schema); }
}

pub fn schema_get_format(schema: ArrowSchema) -> Result[Int, Str]
  requires: schema != 0
{
  unsafe {
    let ptr = arrow_schema_get_format(schema);
    if ptr == 0 {
      return Err("schema_get_format: null format pointer");
    };
    Ok(ptr)
  }
}

pub fn schema_get_name(schema: ArrowSchema) -> Result[Int, Str]
  requires: schema != 0
{
  unsafe {
    let ptr = arrow_schema_get_name(schema);
    if ptr == 0 {
      return Err("schema_get_name: null name pointer");
    };
    Ok(ptr)
  }
}

// ===============================================================================
// Safe wrappers -- RecordBatch
// ===============================================================================

pub fn record_batch_create(schema: ArrowSchema, n_columns: Int, columns: Int) -> Result[ArrowArray, Str]
  requires: schema != 0
  requires: n_columns >= 0
  requires: columns != 0
{
  if schema == 0 { return Err("record_batch_create: null schema"); };
  if n_columns < 0 { return Err("record_batch_create: n_columns must be non-negative"); };
  if columns == 0 { return Err("record_batch_create: null columns pointer"); };
  unsafe {
    let handle = arrow_record_batch_create(schema, n_columns, columns);
    if handle == 0 {
      return Err("record_batch_create: allocation failed (null handle)");
    };
    Ok(handle)
  }
}

pub fn record_batch_get_column(batch: ArrowArray, index: Int) -> Result[ArrowArray, Str]
  requires: batch != 0
  requires: index >= 0
{
  if batch == 0 { return Err("record_batch_get_column: null batch"); };
  if index < 0 { return Err("record_batch_get_column: index must be non-negative"); };
  unsafe {
    let col = arrow_record_batch_get_column(batch, index);
    if col == 0 {
      return Err("record_batch_get_column: null column pointer");
    };
    Ok(col)
  }
}

pub fn record_batch_get_schema(batch: ArrowArray) -> Result[ArrowSchema, Str]
  requires: batch != 0
{
  unsafe {
    let schema = arrow_record_batch_get_schema(batch);
    if schema == 0 {
      return Err("record_batch_get_schema: null schema pointer");
    };
    Ok(schema)
  }
}

// ===============================================================================
// High-level Array API (SPEC SAPI)
// ===============================================================================

pub fn array_new(typ: DataType, data: Vec[Int]) -> Result[Array, Str]
  requires: data.len() >= 0
{
  let n_buffers = 2;
  let length = data.len();
  let result = array_create(length, n_buffers);
  match result {
    Ok(handle) => {
      Ok(Array { handle: handle; length: length; null_count: 0; data_type: typ })
    };
    Err(e) => Err(e),
  }
}

pub fn array_length(arr: &Array) -> Int {
  arr.length
}

pub fn array_null_count(arr: &Array) -> Int {
  arr.null_count
}

pub fn array_data_type(arr: &Array) -> DataType {
  arr.data_type
}

pub fn array_is_valid(arr: &Array) -> Bool {
  arr.handle != 0
}

// ===============================================================================
// High-level Table API (SPEC SAPI)
// ===============================================================================

pub fn table_new(schema: Schema, columns: Vec[Array]) -> Result[Table, Str]
  requires: schema.fields.len() > 0
  requires: columns.len() == schema.fields.len()
{
  if schema.fields.len() == 0 { return Err("table_new: schema must have at least one field"); };
  if columns.len() != schema.fields.len() {
    return Err("table_new: column count does not match schema field count");
  };
  var num_rows = 0;
  if columns.len() > 0 {
    num_rows = columns[0].length;
  };
  Ok(Table { schema: schema; columns: columns; num_rows: num_rows })
}

pub fn table_column(t: &Table, idx: Int) -> Result[Array, Str]
  requires: idx >= 0
  requires: idx < t.columns.len()
{
  if idx < 0 { return Err("table_column: index must be non-negative"); };
  if idx >= t.columns.len() { return Err("table_column: index out of bounds"); };
  Ok(t.columns[idx])
}

pub fn table_num_columns(t: &Table) -> Int {
  t.columns.len()
}

pub fn table_num_rows(t: &Table) -> Int {
  t.num_rows
}

pub fn table_schema(t: &Table) -> Schema {
  t.schema
}

// ===============================================================================
// IPC read/write (SPEC SAPI -- Phase 2 stubs)
// ===============================================================================

pub fn ipc_write(t: &Table, path: Str) -> Result[Unit, Str]
  requires: path.len() > 0
{
  if path.len() == 0 { return Err("ipc_write: path must not be empty"); };
  Err("ipc_write: IPC bridge not yet linked -- requires native Arrow IPC runtime")
}

pub fn ipc_read(path: Str) -> Result[Table, Str]
  requires: path.len() > 0
{
  if path.len() == 0 { return Err("ipc_read: path must not be empty"); };
  Err("ipc_read: IPC bridge not yet linked -- requires native Arrow IPC runtime")
}

// ===============================================================================
// Utility
// ===============================================================================

pub fn version() -> Str {
  "0.1.0"
}

pub fn is_linked() -> Bool {
  false
}
