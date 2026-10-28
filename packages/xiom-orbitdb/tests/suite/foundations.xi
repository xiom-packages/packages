// XIOM ORBITDB -- conformance suite split: foundations (R2, 2026-10-18).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom_db_conformance_foundations

use xiom.io;
use xiom.convert;
use xiom.os.env;
use xiom.test;
use xiom.db.engine;
use xiom.db.wal_file;
use xiom.db.error;
use xiom.db.ids;
use xiom.db.config;
use xiom.db.contracts;
use xiom.db.storage.page;
use xiom.db.storage.page_file;
use xiom.db.storage.block;
use xiom.db.storage.fault;
use xiom.db.storage.tuple;
use xiom.db.storage.free_space_map;
use xiom.db.catalog.schema;
use xiom.db.catalog.schema_row;
use xiom.db.catalog.schema_validator;
use xiom.db.txn.transaction;
use xiom_db_suite_common;

fn run_row_id_construction() -> Int {
  let id = row_id(42);
  let v = row_id_value(&id);
  if v != 42 { return 1; }
  return 0;
}

fn test_row_id_construction() -> TestResult {
  let rc = run_row_id_construction();
  if rc == 0 { return assert(true, "types: RowId construction + value accessor"); }
  return assert(false, "types: RowId construction failed");
}

fn run_row_id_eq() -> Int {
  let a = row_id(10);
  let b = row_id(10);
  let c = row_id(20);
  if !row_id_eq(&a, &b) { return 1; }
  if row_id_eq(&a, &c) { return 1; }
  return 0;
}

fn test_row_id_eq() -> TestResult {
  let rc = run_row_id_eq();
  if rc == 0 { return assert(true, "types: RowId equality + inequality"); }
  return assert(false, "types: RowId eq failed");
}

fn run_row_id_next() -> Int {
  let id = row_id(5);
  let next = row_id_next(&id);
  let v = row_id_value(&next);
  if v != 6 { return 1; }
  return 0;
}

fn test_row_id_next() -> TestResult {
  let rc = run_row_id_next();
  if rc == 0 { return assert(true, "types: RowId next() increments correctly"); }
  return assert(false, "types: RowId next failed");
}

fn run_table_id_construction() -> Int {
  let id = table_id(7);
  let v = table_id_value(&id);
  if v != 7 { return 1; }
  return 0;
}

fn test_table_id_construction() -> TestResult {
  let rc = run_table_id_construction();
  if rc == 0 { return assert(true, "types: TableId construction + value accessor"); }
  return assert(false, "types: TableId construction failed");
}

fn run_table_id_eq() -> Int {
  let a = table_id(3);
  let b = table_id(3);
  let c = table_id(99);
  if !table_id_eq(&a, &b) { return 1; }
  if table_id_eq(&a, &c) { return 1; }
  return 0;
}

fn test_table_id_eq() -> TestResult {
  let rc = run_table_id_eq();
  if rc == 0 { return assert(true, "types: TableId equality + inequality"); }
  return assert(false, "types: TableId eq failed");
}

fn run_row_id_to_page_id() -> Int {
  let row = row_id(15);
  let page = row_id_to_page_id(&row);
  // Type exists and construction succeeds
  return 0;
}

fn test_row_id_to_page_id() -> TestResult {
  let rc = run_row_id_to_page_id();
  if rc == 0 { return assert(true, "types: row_id_to_page_id bridge"); }
  return assert(false, "types: row_id_to_page_id failed");
}

fn run_page_id_zero() -> Int {
  let data = Vec[Int].new();
  let checksum = page_compute_checksum(&data);
  let p = Page.new(0, data, checksum);
  if p.id != 0 { return 1; }
  return 0;
}

fn test_page_id_zero() -> TestResult {
  let rc = run_page_id_zero();
  if rc == 0 { return assert(true, "types: PageId zero construction"); }
  return assert(false, "types: PageId zero failed");
}

// ===========================================================================
// 2. Error types and error code mapping
// ===========================================================================

fn run_error_to_string() -> Int {
  if DbError.to_string(DbError.NotFound) != "not found" { return 1; }
  if DbError.to_string(DbError.DuplicateKey) != "duplicate key" { return 1; }
  if DbError.to_string(DbError.ConstraintViolation) != "constraint violation" { return 1; }
  if DbError.to_string(DbError.SchemaMismatch) != "schema mismatch" { return 1; }
  if DbError.to_string(DbError.StorageError) != "storage error" { return 1; }
  if DbError.to_string(DbError.Corruption) != "data corruption" { return 1; }
  return 0;
}

fn test_error_to_string() -> TestResult {
  let rc = run_error_to_string();
  if rc == 0 { return assert(true, "error: all 6 DbError.to_string mappings"); }
  return assert(false, "error: to_string mapping wrong");
}

fn run_error_is_retryable() -> Int {
  if DbError.is_retryable(DbError.NotFound) { return 1; }
  if DbError.is_retryable(DbError.DuplicateKey) { return 1; }
  if DbError.is_retryable(DbError.ConstraintViolation) { return 1; }
  if DbError.is_retryable(DbError.SchemaMismatch) { return 1; }
  if !DbError.is_retryable(DbError.StorageError) { return 1; }
  if DbError.is_retryable(DbError.Corruption) { return 1; }
  return 0;
}

fn test_error_is_retryable() -> TestResult {
  let rc = run_error_is_retryable();
  if rc == 0 { return assert(true, "error: only StorageError is retryable"); }
  return assert(false, "error: retryable mapping wrong");
}

fn run_error_db_result_ok() -> Int {
  let r: DbResult[Int] = Ok(42);
  match r {
    Ok(v) => { if v != 42 { return 1; } return 0; }
    Err(_) => return 1,
  }
}

fn test_error_db_result_ok() -> TestResult {
  let rc = run_error_db_result_ok();
  if rc == 0 { return assert(true, "error: DbResult[Int] Ok variant"); }
  return assert(false, "error: DbResult Ok failed");
}

fn run_error_db_result_err() -> Int {
  let r: DbResult[Int] = Err(DbError.NotFound);
  match r {
    Ok(_) => return 1,
    Err(e) => {
      if DbError.to_string(e) != "not found" { return 1; }
      return 0;
    }
  }
}

fn test_error_db_result_err() -> TestResult {
  let rc = run_error_db_result_err();
  if rc == 0 { return assert(true, "error: DbResult[Int] Err variant carries error"); }
  return assert(false, "error: DbResult Err failed");
}

// ===========================================================================
// 3. Config defaults and validation
// ===========================================================================

fn run_config_default() -> Int {
  let cfg = DatabaseConfig.default();
  if cfg.page_size != 4096 { return 1; }
  if cfg.buffer_pool_capacity != 64 { return 1; }
  if !cfg.wal_enabled { return 1; }
  if cfg.btree_order != 4 { return 1; }
  return 0;
}

fn test_config_default() -> TestResult {
  let rc = run_config_default();
  if rc == 0 { return assert(true, "config: default values (4096/64/true/4)"); }
  return assert(false, "config: default values wrong");
}

fn run_config_validate_valid() -> Int {
  let cfg = DatabaseConfig.default();
  if !database_config_validate(&cfg) { return 1; }
  return 0;
}

fn test_config_validate_valid() -> TestResult {
  let rc = run_config_validate_valid();
  if rc == 0 { return assert(true, "config: default config passes validation"); }
  return assert(false, "config: default config rejected");
}

fn run_config_validate_bad_page_size() -> Int {
  var cfg = DatabaseConfig.default();
  cfg.page_size = 100;
  if database_config_validate(&cfg) { return 1; }
  return 0;
}

fn test_config_validate_bad_page_size() -> TestResult {
  let rc = run_config_validate_bad_page_size();
  if rc == 0 { return assert(true, "config: non-power-of-two page size rejected"); }
  return assert(false, "config: bad page size accepted");
}

fn run_config_validate_page_too_small() -> Int {
  var cfg = DatabaseConfig.default();
  cfg.page_size = 256;
  if database_config_validate(&cfg) { return 1; }
  return 0;
}

fn test_config_validate_page_too_small() -> TestResult {
  let rc = run_config_validate_page_too_small();
  if rc == 0 { return assert(true, "config: page_size < 512 rejected"); }
  return assert(false, "config: tiny page size accepted");
}

fn run_config_validate_zero_capacity() -> Int {
  var cfg = DatabaseConfig.default();
  cfg.buffer_pool_capacity = 0;
  if database_config_validate(&cfg) { return 1; }
  return 0;
}

fn test_config_validate_zero_capacity() -> TestResult {
  let rc = run_config_validate_zero_capacity();
  if rc == 0 { return assert(true, "config: buffer_pool_capacity < 1 rejected"); }
  return assert(false, "config: zero capacity accepted");
}

fn run_config_validate_bad_btree_order() -> Int {
  var cfg = DatabaseConfig.default();
  cfg.btree_order = 2;
  if database_config_validate(&cfg) { return 1; }
  return 0;
}

fn test_config_validate_bad_btree_order() -> TestResult {
  let rc = run_config_validate_bad_btree_order();
  if rc == 0 { return assert(true, "config: btree_order < 3 rejected"); }
  return assert(false, "config: bad btree order accepted");
}

// ===========================================================================
// 4. Contract predicates (is_valid_page_size, is_power_of_two)
// ===========================================================================

fn run_is_power_of_two() -> Int {
  if !is_power_of_two(1) { return 1; }
  if !is_power_of_two(2) { return 1; }
  if !is_power_of_two(4) { return 1; }
  if !is_power_of_two(8) { return 1; }
  if !is_power_of_two(16) { return 1; }
  if !is_power_of_two(32) { return 1; }
  if !is_power_of_two(64) { return 1; }
  if !is_power_of_two(128) { return 1; }
  if !is_power_of_two(256) { return 1; }
  if !is_power_of_two(512) { return 1; }
  if !is_power_of_two(1024) { return 1; }
  if !is_power_of_two(2048) { return 1; }
  if !is_power_of_two(4096) { return 1; }
  if !is_power_of_two(8192) { return 1; }
  if !is_power_of_two(16384) { return 1; }
  if !is_power_of_two(32768) { return 1; }
  if !is_power_of_two(65536) { return 1; }
  if is_power_of_two(0) { return 1; }
  if is_power_of_two(3) { return 1; }
  if is_power_of_two(6) { return 1; }
  if is_power_of_two(100) { return 1; }
  if is_power_of_two(4095) { return 1; }
  if is_power_of_two(4097) { return 1; }
  return 0;
}

fn test_is_power_of_two() -> TestResult {
  let rc = run_is_power_of_two();
  if rc == 0 { return assert(true, "contracts: is_power_of_two all cases"); }
  return assert(false, "contracts: is_power_of_two failed");
}

fn run_is_valid_page_size() -> Int {
  if !is_valid_page_size(512) { return 1; }
  if !is_valid_page_size(1024) { return 1; }
  if !is_valid_page_size(4096) { return 1; }
  if !is_valid_page_size(8192) { return 1; }
  if !is_valid_page_size(16384) { return 1; }
  if !is_valid_page_size(32768) { return 1; }
  if !is_valid_page_size(65536) { return 1; }
  if is_valid_page_size(256) { return 1; }
  if is_valid_page_size(0) { return 1; }
  if is_valid_page_size(100) { return 1; }
  if is_valid_page_size(65537) { return 1; }
  return 0;
}

fn test_is_valid_page_size() -> TestResult {
  let rc = run_is_valid_page_size();
  if rc == 0 { return assert(true, "contracts: is_valid_page_size boundaries"); }
  return assert(false, "contracts: is_valid_page_size failed");
}

fn run_valid_btree_order() -> Int {
  if !valid_btree_order(3) { return 1; }
  if !valid_btree_order(4) { return 1; }
  if !valid_btree_order(64) { return 1; }
  if !valid_btree_order(100) { return 1; }
  if valid_btree_order(2) { return 1; }
  if valid_btree_order(1) { return 1; }
  if valid_btree_order(0) { return 1; }
  return 0;
}

fn test_valid_btree_order() -> TestResult {
  let rc = run_valid_btree_order();
  if rc == 0 { return assert(true, "contracts: valid_btree_order >= 3"); }
  return assert(false, "contracts: valid_btree_order failed");
}

fn run_valid_key() -> Int {
  if !valid_key(0) { return 1; }
  if !valid_key(-1) { return 1; }
  if !valid_key(999999) { return 1; }
  return 0;
}

fn test_valid_key() -> TestResult {
  let rc = run_valid_key();
  if rc == 0 { return assert(true, "contracts: valid_key accepts all ints"); }
  return assert(false, "contracts: valid_key failed");
}

fn run_sorted_keys() -> Int {
  var keys = Vec[Int].new();
  if !sorted_keys(&keys) { return 1; }
  keys.push(1);
  if !sorted_keys(&keys) { return 1; }
  keys.push(5);
  if !sorted_keys(&keys) { return 1; }
  keys.push(10);
  if !sorted_keys(&keys) { return 1; }
  var dup = Vec[Int].new();
  dup.push(1);
  dup.push(1);
  if sorted_keys(&dup) { return 1; }
  var desc = Vec[Int].new();
  desc.push(5);
  desc.push(3);
  if sorted_keys(&desc) { return 1; }
  return 0;
}

fn test_sorted_keys() -> TestResult {
  let rc = run_sorted_keys();
  if rc == 0 { return assert(true, "contracts: sorted_keys strict ascending"); }
  return assert(false, "contracts: sorted_keys failed");
}

fn run_valid_range() -> Int {
  if !valid_range(0, 0) { return 1; }
  if !valid_range(0, 10) { return 1; }
  if !valid_range(-5, 5) { return 1; }
  if valid_range(10, 0) { return 1; }
  return 0;
}

fn test_valid_range() -> TestResult {
  let rc = run_valid_range();
  if rc == 0 { return assert(true, "contracts: valid_range low <= high"); }
  return assert(false, "contracts: valid_range failed");
}

fn run_non_decreasing() -> Int {
  var v = Vec[Int].new();
  if !non_decreasing(&v) { return 1; }
  v.push(1);
  v.push(1);
  v.push(2);
  if !non_decreasing(&v) { return 1; }
  v.push(0);
  if non_decreasing(&v) { return 1; }
  return 0;
}

fn test_non_decreasing() -> TestResult {
  let rc = run_non_decreasing();
  if rc == 0 { return assert(true, "contracts: non_decreasing allows duplicates"); }
  return assert(false, "contracts: non_decreasing failed");
}

// ===========================================================================
// 5. Page header/structure construction and validation
// ===========================================================================

fn main() -> Int {
  io.println("=== XIOM DB Conformance: foundations ===");
  var failed: Int = 0;
  var total: Int = 0;
  let r1 = test_row_id_construction();
  total = total + 1; failed = failed + report(r1.passed, r1.name);
  let r2 = test_row_id_eq();
  total = total + 1; failed = failed + report(r2.passed, r2.name);
  let r3 = test_row_id_next();
  total = total + 1; failed = failed + report(r3.passed, r3.name);
  let r4 = test_table_id_construction();
  total = total + 1; failed = failed + report(r4.passed, r4.name);
  let r5 = test_table_id_eq();
  total = total + 1; failed = failed + report(r5.passed, r5.name);
  let r6 = test_row_id_to_page_id();
  total = total + 1; failed = failed + report(r6.passed, r6.name);
  let r7 = test_page_id_zero();
  total = total + 1; failed = failed + report(r7.passed, r7.name);
  let r8 = test_error_to_string();
  total = total + 1; failed = failed + report(r8.passed, r8.name);
  let r9 = test_error_is_retryable();
  total = total + 1; failed = failed + report(r9.passed, r9.name);
  let r10 = test_error_db_result_ok();
  total = total + 1; failed = failed + report(r10.passed, r10.name);
  let r11 = test_error_db_result_err();
  total = total + 1; failed = failed + report(r11.passed, r11.name);
  let r12 = test_config_default();
  total = total + 1; failed = failed + report(r12.passed, r12.name);
  let r13 = test_config_validate_valid();
  total = total + 1; failed = failed + report(r13.passed, r13.name);
  let r14 = test_config_validate_bad_page_size();
  total = total + 1; failed = failed + report(r14.passed, r14.name);
  let r15 = test_config_validate_page_too_small();
  total = total + 1; failed = failed + report(r15.passed, r15.name);
  let r16 = test_config_validate_zero_capacity();
  total = total + 1; failed = failed + report(r16.passed, r16.name);
  let r17 = test_config_validate_bad_btree_order();
  total = total + 1; failed = failed + report(r17.passed, r17.name);
  let r18 = test_is_power_of_two();
  total = total + 1; failed = failed + report(r18.passed, r18.name);
  let r19 = test_is_valid_page_size();
  total = total + 1; failed = failed + report(r19.passed, r19.name);
  let r20 = test_valid_btree_order();
  total = total + 1; failed = failed + report(r20.passed, r20.name);
  let r21 = test_valid_key();
  total = total + 1; failed = failed + report(r21.passed, r21.name);
  let r22 = test_sorted_keys();
  total = total + 1; failed = failed + report(r22.passed, r22.name);
  let r23 = test_valid_range();
  total = total + 1; failed = failed + report(r23.passed, r23.name);
  let r24 = test_non_decreasing();
  total = total + 1; failed = failed + report(r24.passed, r24.name);
  let passed = total - failed;
  io.println("XIOM DB Conformance [foundations]: " + int_to_str(passed) + "/" + int_to_str(total) + " passed" + (if failed > 0 { " (" + int_to_str(failed) + " FAILED)" } else { "" }));
  return failed;
}