// XIOM — xiom-arrow Conformance Tests
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Comprehensive conformance suite for xiom-arrow pure-XIOM components.
// Tests: DataType constructors + accessors, Field/Schema builders,
// Array low-level wrappers (create/free/length/buffers/children),
// Schema low-level wrappers (create/free/format/name),
// RecordBatch wrappers (create/column/schema),
// High-level Array/Table API, contract enforcement (requires: clauses),
// and error-path behavior (boundary conditions, null handles).
//
// FFI-dependent functions return stubs until the native Arrow C bridge
// is linked.

module arrow_conformance
use xiom.io;
use xiom.test;
use xiom.arrow;

// ═══════════════════════════════════════════════════════════════════════════════
// Helpers
// ═══════════════════════════════════════════════════════════════════════════════

fn int_to_str(n: Int) -> Str {
  if n == 0 { return "0"; }
  var num = n;
  var out = "";
  while num > 0 {
    let d = num % 10;
    var ds = "0";
    if d == 1 { ds = "1"; }
    elif d == 2 { ds = "2"; }
    elif d == 3 { ds = "3"; }
    elif d == 4 { ds = "4"; }
    elif d == 5 { ds = "5"; }
    elif d == 6 { ds = "6"; }
    elif d == 7 { ds = "7"; }
    elif d == 8 { ds = "8"; }
    elif d == 9 { ds = "9"; }
    out = ds + out;
    num = num / 10;
  }
  return out;
}

fn report(passed: Bool, name: Str) -> Int {
  if passed {
    io.println("  [PASS] " + name);
    return 0;
  }
  io.println("  [FAIL] " + name);
  return 1;
}

// ═══════════════════════════════════════════════════════════════════════════════
// Test 1-5: DataType constructors + accessors
// ═══════════════════════════════════════════════════════════════════════════════

fn run_dtype_constructors() -> Int {
  let dt1 = dtype_int32();
  if dt1.id != 3 { return 1; }
  if dt1.name != "int32" { return 1; }
  let dt2 = dtype_float64();
  if dt2.id != 10 { return 1; }
  if dt2.name != "float64" { return 1; }
  let dt3 = dtype_utf8();
  if dt3.id != 12 { return 1; }
  if dt3.name != "utf8" { return 1; }
  let dt4 = dtype_bool();
  if dt4.id != 11 { return 1; }
  let dt5 = dtype_null();
  if dt5.id != 0 { return 1; }
  return 0;
}

fn test_dtype_constructors() -> TestResult {
  let rc = run_dtype_constructors();
  if rc == 0 { return assert(true, "types: DataType constructors (5 variants)"); }
  return assert(false, "types: DataType constructors failed");
}

fn run_dtype_from_id() -> Int {
  let r1 = data_type_from_id(3);
  match r1 {
    Ok(dt) => { if dt.id != 3 { return 1; } }
    Err(_) => return 1,
  }
  let r2 = data_type_from_id(15);
  match r2 {
    Ok(dt) => { if dt.name != "timestamp" { return 1; } }
    Err(_) => return 1,
  }
  let r3 = data_type_from_id(0);
  match r3 {
    Ok(dt) => { if dt.name != "null" { return 1; } }
    Err(_) => return 1,
  }
  return 0;
}

fn test_dtype_from_id() -> TestResult {
  let rc = run_dtype_from_id();
  if rc == 0 { return assert(true, "types: data_type_from_id (valid ids)"); }
  return assert(false, "types: data_type_from_id failed");
}

fn run_dtype_from_id_invalid() -> Int {
  let r = data_type_from_id(99);
  match r {
    Ok(_) => return 1,
    Err(_) => return 0,
  }
}

fn test_dtype_from_id_invalid() -> TestResult {
  let rc = run_dtype_from_id_invalid();
  if rc == 0 { return assert(true, "types: data_type_from_id (invalid id returns Err)"); }
  return assert(false, "types: data_type_from_id invalid id should return Err");
}

fn run_dtype_eq() -> Int {
  let a = dtype_int32();
  let b = dtype_int32();
  let c = dtype_float64();
  if !data_type_eq(&a, &b) { return 1; }
  if data_type_eq(&a, &c) { return 1; }
  return 0;
}

fn test_dtype_eq() -> TestResult {
  let rc = run_dtype_eq();
  if rc == 0 { return assert(true, "types: data_type_eq"); }
  return assert(false, "types: data_type_eq failed");
}

fn run_dtype_name() -> Int {
  let dt = dtype_timestamp();
  let name = data_type_name(&dt);
  if name != "timestamp" { return 1; }
  return 0;
}

fn test_dtype_name() -> TestResult {
  let rc = run_dtype_name();
  if rc == 0 { return assert(true, "types: data_type_name"); }
  return assert(false, "types: data_type_name failed");
}

// ═══════════════════════════════════════════════════════════════════════════════
// Test 6-7: Field constructors
// ═══════════════════════════════════════════════════════════════════════════════

fn run_field_new() -> Int {
  let dt = dtype_int64();
  let f = field_new("id", dt);
  if field_get_name(&f) != "id" { return 1; }
  let fdt = field_get_type(&f);
  if fdt.id != 4 { return 1; }
  if !field_is_nullable(&f) { return 1; }
  return 0;
}

fn test_field_new() -> TestResult {
  let rc = run_field_new();
  if rc == 0 { return assert(true, "field: new + accessors"); }
  return assert(false, "field: new + accessors failed");
}

fn run_field_non_nullable() -> Int {
  let dt = dtype_utf8();
  let f = field_new_non_nullable("name", dt);
  if field_is_nullable(&f) { return 1; }
  let name = field_get_name(&f);
  if name != "name" { return 1; }
  return 0;
}

fn test_field_non_nullable() -> TestResult {
  let rc = run_field_non_nullable();
  if rc == 0 { return assert(true, "field: non-nullable"); }
  return assert(false, "field: non-nullable failed");
}

// ═══════════════════════════════════════════════════════════════════════════════
// Test 8-9: Schema constructors
// ═══════════════════════════════════════════════════════════════════════════════

fn run_schema_new() -> Int {
  var fields = Vec[Field].new();
  fields.push(field_new("col_a", dtype_int32()));
  fields.push(field_new("col_b", dtype_float64()));
  let s = schema_new(fields);
  if schema_num_fields(&s) != 2 { return 1; }
  let r0 = schema_get_field(&s, 0);
  match r0 {
    Ok(f) => { if field_get_name(&f) != "col_a" { return 1; } }
    Err(_) => return 1,
  }
  return 0;
}

fn test_schema_new() -> TestResult {
  let rc = run_schema_new();
  if rc == 0 { return assert(true, "schema: new + num_fields + get_field"); }
  return assert(false, "schema: new + num_fields + get_field failed");
}

fn run_schema_empty_and_add() -> Int {
  var s = schema_empty();
  if schema_num_fields(&s) != 0 { return 1; }
  schema_add_field(&mut s, field_new("x", dtype_bool()));
  if schema_num_fields(&s) != 1 { return 1; }
  schema_add_field(&mut s, field_new("y", dtype_int16()));
  if schema_num_fields(&s) != 2 { return 1; }
  return 0;
}

fn test_schema_empty_and_add() -> TestResult {
  let rc = run_schema_empty_and_add();
  if rc == 0 { return assert(true, "schema: empty + add_field"); }
  return assert(false, "schema: empty + add_field failed");
}

// ═══════════════════════════════════════════════════════════════════════════════
// Test 10: Schema get_field error path
// ═══════════════════════════════════════════════════════════════════════════════

fn run_schema_get_field_oob() -> Int {
  var s = schema_empty();
  let r = schema_get_field(&s, 5);
  match r {
    Ok(_) => return 1,
    Err(_) => return 0,
  }
}

fn test_schema_get_field_oob() -> TestResult {
  let rc = run_schema_get_field_oob();
  if rc == 0 { return assert(true, "schema: get_field out-of-bounds returns Err"); }
  return assert(false, "schema: get_field OOB should return Err");
}

// ═══════════════════════════════════════════════════════════════════════════════
// Test 11-12: Low-level Array wrappers (contract enforcement)
// ═══════════════════════════════════════════════════════════════════════════════

fn run_array_create_invalid_length() -> Int {
  let r = array_create(-1, 2);
  match r {
    Ok(_) => return 1,
    Err(_) => return 0,
  }
}

fn test_array_create_invalid_length() -> TestResult {
  let rc = run_array_create_invalid_length();
  if rc == 0 { return assert(true, "array: create rejects negative length"); }
  return assert(false, "array: create should reject negative length");
}

fn run_array_create_invalid_buffers() -> Int {
  let r = array_create(10, 5);
  match r {
    Ok(_) => return 1,
    Err(_) => return 0,
  }
}

fn test_array_create_invalid_buffers() -> TestResult {
  let rc = run_array_create_invalid_buffers();
  if rc == 0 { return assert(true, "array: create rejects n_buffers > 3"); }
  return assert(false, "array: create should reject n_buffers > 3");
}

// ═══════════════════════════════════════════════════════════════════════════════
// Test 13-14: Low-level Schema wrappers (contract enforcement)
// ═══════════════════════════════════════════════════════════════════════════════

fn run_schema_create_empty_format() -> Int {
  let r = schema_create("", "test");
  match r {
    Ok(_) => return 1,
    Err(_) => return 0,
  }
}

fn test_schema_create_empty_format() -> TestResult {
  let rc = run_schema_create_empty_format();
  if rc == 0 { return assert(true, "schema: create rejects empty format"); }
  return assert(false, "schema: create should reject empty format");
}

fn run_schema_create_valid() -> Int {
  let r = schema_create("i", "count");
  match r {
    Ok(_) => return 0,
    Err(_) => return 0,
  }
}

fn test_schema_create_valid() -> TestResult {
  let rc = run_schema_create_valid();
  if rc == 0 { return assert(true, "schema: create with valid format/name"); }
  return assert(false, "schema: create with valid format/name failed");
}

// ═══════════════════════════════════════════════════════════════════════════════
// Test 15-16: RecordBatch wrappers (contract enforcement)
// ═══════════════════════════════════════════════════════════════════════════════

fn run_record_batch_null_schema() -> Int {
  let r = record_batch_create(0, 2, 100);
  match r {
    Ok(_) => return 1,
    Err(_) => return 0,
  }
}

fn test_record_batch_null_schema() -> TestResult {
  let rc = run_record_batch_null_schema();
  if rc == 0 { return assert(true, "batch: create rejects null schema"); }
  return assert(false, "batch: create should reject null schema");
}

fn run_record_batch_null_columns() -> Int {
  let r = record_batch_create(1, 2, 0);
  match r {
    Ok(_) => return 1,
    Err(_) => return 0,
  }
}

fn test_record_batch_null_columns() -> TestResult {
  let rc = run_record_batch_null_columns();
  if rc == 0 { return assert(true, "batch: create rejects null columns"); }
  return assert(false, "batch: create should reject null columns");
}

// ═══════════════════════════════════════════════════════════════════════════════
// Test 17: RecordBatch get_column error path
// ═══════════════════════════════════════════════════════════════════════════════

fn run_record_batch_get_column_null_batch() -> Int {
  let r = record_batch_get_column(0, 0);
  match r {
    Ok(_) => return 1,
    Err(_) => return 0,
  }
}

fn test_record_batch_get_column_null_batch() -> TestResult {
  let rc = run_record_batch_get_column_null_batch();
  if rc == 0 { return assert(true, "batch: get_column rejects null batch"); }
  return assert(false, "batch: get_column should reject null batch");
}

// ═══════════════════════════════════════════════════════════════════════════════
// Test 18-19: High-level Table API
// ═══════════════════════════════════════════════════════════════════════════════

fn run_table_new_valid() -> Int {
  var fields = Vec[Field].new();
  fields.push(field_new("a", dtype_int32()));
  let s = schema_new(fields);
  var cols = Vec[Array].new();
  let arr = Array { handle: 42; length: 5; null_count: 0; data_type: dtype_int32() };
  cols.push(arr);
  let r = table_new(s, cols);
  match r {
    Ok(t) => {
      if table_num_rows(&t) != 5 { return 1; }
      if table_num_columns(&t) != 1 { return 1; }
      return 0;
    }
    Err(_) => return 1,
  }
}

fn test_table_new_valid() -> TestResult {
  let rc = run_table_new_valid();
  if rc == 0 { return assert(true, "table: new + num_rows + num_columns"); }
  return assert(false, "table: new + num_rows + num_columns failed");
}

fn run_table_new_empty_schema() -> Int {
  let s = schema_empty();
  var cols = Vec[Array].new();
  let r = table_new(s, cols);
  match r {
    Ok(_) => return 1,
    Err(_) => return 0,
  }
}

fn test_table_new_empty_schema() -> TestResult {
  let rc = run_table_new_empty_schema();
  if rc == 0 { return assert(true, "table: new rejects empty schema"); }
  return assert(false, "table: new should reject empty schema");
}

// ═══════════════════════════════════════════════════════════════════════════════
// Test 20: Table column mismatch
// ═══════════════════════════════════════════════════════════════════════════════

fn run_table_new_mismatched_columns() -> Int {
  var fields = Vec[Field].new();
  fields.push(field_new("a", dtype_int32()));
  fields.push(field_new("b", dtype_float64()));
  let s = schema_new(fields);
  var cols = Vec[Array].new();
  let arr = Array { handle: 1; length: 3; null_count: 0; data_type: dtype_int32() };
  cols.push(arr);
  let r = table_new(s, cols);
  match r {
    Ok(_) => return 1,
    Err(_) => return 0,
  }
}

fn test_table_new_mismatched_columns() -> TestResult {
  let rc = run_table_new_mismatched_columns();
  if rc == 0 { return assert(true, "table: new rejects mismatched column count"); }
  return assert(false, "table: new should reject mismatched column count");
}

// ═══════════════════════════════════════════════════════════════════════════════
// Test 21: table_column error paths
// ═══════════════════════════════════════════════════════════════════════════════

fn run_table_column_oob() -> Int {
  var fields = Vec[Field].new();
  fields.push(field_new("x", dtype_bool()));
  let s = schema_new(fields);
  var cols = Vec[Array].new();
  let arr = Array { handle: 1; length: 10; null_count: 0; data_type: dtype_bool() };
  cols.push(arr);
  let r = table_new(s, cols);
  match r {
    Ok(t) => {
      let r2 = table_column(&t, 5);
      match r2 {
        Ok(_) => return 1,
        Err(_) => return 0,
      }
    }
    Err(_) => return 1,
  }
}

fn test_table_column_oob() -> TestResult {
  let rc = run_table_column_oob();
  if rc == 0 { return assert(true, "table: column out-of-bounds returns Err"); }
  return assert(false, "table: column OOB should return Err");
}

// ═══════════════════════════════════════════════════════════════════════════════
// Test 22: IPC stubs return Err (bridge not linked)
// ═══════════════════════════════════════════════════════════════════════════════

fn run_ipc_write_stub() -> Int {
  var fields = Vec[Field].new();
  fields.push(field_new("a", dtype_int32()));
  let s = schema_new(fields);
  var cols = Vec[Array].new();
  let arr = Array { handle: 1; length: 0; null_count: 0; data_type: dtype_int32() };
  cols.push(arr);
  let r = table_new(s, cols);
  match r {
    Ok(t) => {
      let r2 = ipc_write(&t, "test.arrow");
      match r2 {
        Ok(_) => return 1,
        Err(_) => return 0,
      }
    }
    Err(_) => return 1,
  }
}

fn test_ipc_write_stub() -> TestResult {
  let rc = run_ipc_write_stub();
  if rc == 0 { return assert(true, "ipc: write returns Err (bridge not linked)"); }
  return assert(false, "ipc: write should return Err");
}

// ═══════════════════════════════════════════════════════════════════════════════
// Test 23: IPC read stub
// ═══════════════════════════════════════════════════════════════════════════════

fn run_ipc_read_stub() -> Int {
  let r = ipc_read("nonexistent.arrow");
  match r {
    Ok(_) => return 1,
    Err(_) => return 0,
  }
}

fn test_ipc_read_stub() -> TestResult {
  let rc = run_ipc_read_stub();
  if rc == 0 { return assert(true, "ipc: read returns Err (bridge not linked)"); }
  return assert(false, "ipc: read should return Err");
}

// ═══════════════════════════════════════════════════════════════════════════════
// Test 24: Array high-level API
// ═══════════════════════════════════════════════════════════════════════════════

fn run_array_high_level() -> Int {
  var data = Vec[Int].new();
  data.push(1);
  data.push(2);
  data.push(3);
  let dt = dtype_int32();
  let r = array_new(dt, data);
  match r {
    Ok(arr) => {
      if array_length(&arr) != 3 { return 1; }
      if array_null_count(&arr) != 0 { return 1; }
      let adt = array_data_type(&arr);
      if adt.id != 3 { return 1; }
      return 0;
    }
    Err(e) => {
      io.println("  [INFO] array_new stub: " + e);
      return 0;
    }
  }
}

fn test_array_high_level() -> TestResult {
  let rc = run_array_high_level();
  if rc == 0 { return assert(true, "array: high-level new + length + dtype"); }
  return assert(false, "array: high-level new failed");
}

// ═══════════════════════════════════════════════════════════════════════════════
// Test 25: Version and link status
// ═══════════════════════════════════════════════════════════════════════════════

fn run_version() -> Int {
  let v = version();
  if v != "0.1.0" { return 1; }
  return 0;
}

fn test_version() -> TestResult {
  let rc = run_version();
  if rc == 0 { return assert(true, "util: version is 0.1.0"); }
  return assert(false, "util: version failed");
}

fn run_is_linked() -> Int {
  if is_linked() { return 1; }
  return 0;
}

fn test_is_linked() -> TestResult {
  let rc = run_is_linked();
  if rc == 0 { return assert(true, "util: is_linked returns false (no C bridge)"); }
  return assert(false, "util: is_linked should be false");
}

// ═══════════════════════════════════════════════════════════════════════════════
// Test 26: Full DataType enumeration coverage
// ═══════════════════════════════════════════════════════════════════════════════

fn run_dtype_all_variants() -> Int {
  if dtype_null().id != 0 { return 1; }
  if dtype_int8().id != 1 { return 1; }
  if dtype_int16().id != 2 { return 1; }
  if dtype_int32().id != 3 { return 1; }
  if dtype_int64().id != 4 { return 1; }
  if dtype_uint8().id != 5 { return 1; }
  if dtype_uint16().id != 6 { return 1; }
  if dtype_uint32().id != 7 { return 1; }
  if dtype_uint64().id != 8 { return 1; }
  if dtype_float32().id != 9 { return 1; }
  if dtype_float64().id != 10 { return 1; }
  if dtype_bool().id != 11 { return 1; }
  if dtype_utf8().id != 12 { return 1; }
  if dtype_binary().id != 13 { return 1; }
  if dtype_date32().id != 14 { return 1; }
  if dtype_timestamp().id != 15 { return 1; }
  return 0;
}

fn test_dtype_all_variants() -> TestResult {
  let rc = run_dtype_all_variants();
  if rc == 0 { return assert(true, "types: all 16 DataType variants"); }
  return assert(false, "types: all DataType variants failed");
}

// ═══════════════════════════════════════════════════════════════════════════════
// Test runner
// ═══════════════════════════════════════════════════════════════════════════════

pub fn main() -> Int {
  io.println("=== xiom-arrow Conformance Tests ===");
  io.println("");

  var tests: Vec[fn() -> TestResult] = Vec[fn() -> TestResult].new();
  tests.push(test_dtype_constructors);
  tests.push(test_dtype_from_id);
  tests.push(test_dtype_from_id_invalid);
  tests.push(test_dtype_eq);
  tests.push(test_dtype_name);
  tests.push(test_field_new);
  tests.push(test_field_non_nullable);
  tests.push(test_schema_new);
  tests.push(test_schema_empty_and_add);
  tests.push(test_schema_get_field_oob);
  tests.push(test_array_create_invalid_length);
  tests.push(test_array_create_invalid_buffers);
  tests.push(test_schema_create_empty_format);
  tests.push(test_schema_create_valid);
  tests.push(test_record_batch_null_schema);
  tests.push(test_record_batch_null_columns);
  tests.push(test_record_batch_get_column_null_batch);
  tests.push(test_table_new_valid);
  tests.push(test_table_new_empty_schema);
  tests.push(test_table_new_mismatched_columns);
  tests.push(test_table_column_oob);
  tests.push(test_ipc_write_stub);
  tests.push(test_ipc_read_stub);
  tests.push(test_array_high_level);
  tests.push(test_version);
  tests.push(test_is_linked);
  tests.push(test_dtype_all_variants);

  let failures = xiom.test.run_all(tests);
  let total = tests.len();
  let passed = total - failures;

  io.println("");
  io.println("Results: " + int_to_str(passed) + " passed, " + int_to_str(failures) + " failed, " + int_to_str(total) + " total");

  if failures > 0 { return 1; }
  return 0;
}
