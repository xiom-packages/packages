// XIOM — xiom-db Conformance Tests
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Comprehensive conformance suite for xiom-db pure-XIOM components.
// Tests: types (RowId, TableId, PageId), error domain, config validation,
// contract predicates, page/checksum, buffer pool, WAL records, transactions,
// schema validation, query planner, B-tree structure and operations.

module xiom_db_conformance
use xiom.io;
use xiom.test;
use xiom.db.engine;
use xiom.db.error;
use xiom.db.ids;
use xiom.db.config;
use xiom.db.contracts;
use xiom.db.storage.page;
use xiom.db.storage.tuple;
use xiom.db.storage.free_space_map;
use xiom.db.catalog.schema;
use xiom.db.catalog.schema_validator;
use xiom.db.txn.transaction;

// ═══════════════════════════════════════════════════════════════════════════
// Helpers
// ═══════════════════════════════════════════════════════════════════════════

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

// ═══════════════════════════════════════════════════════════════════════════
// 1. Types: RowId, TableId, PageId construction and validation
// ═══════════════════════════════════════════════════════════════════════════

fn run_row_id_construction() -> Int {
  let id = row_id(42);
  let v = row_id_value(&id);
  if v != 42 { return 1; }
  return 0;
}

fn test_row_id_construction() -> TestCase {
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

fn test_row_id_eq() -> TestCase {
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

fn test_row_id_next() -> TestCase {
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

fn test_table_id_construction() -> TestCase {
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

fn test_table_id_eq() -> TestCase {
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

fn test_row_id_to_page_id() -> TestCase {
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

fn test_page_id_zero() -> TestCase {
  let rc = run_page_id_zero();
  if rc == 0 { return assert(true, "types: PageId zero construction"); }
  return assert(false, "types: PageId zero failed");
}

// ═══════════════════════════════════════════════════════════════════════════
// 2. Error types and error code mapping
// ═══════════════════════════════════════════════════════════════════════════

fn run_error_to_string() -> Int {
  if DbError.to_string(DbError.NotFound) != "not found" { return 1; }
  if DbError.to_string(DbError.DuplicateKey) != "duplicate key" { return 1; }
  if DbError.to_string(DbError.ConstraintViolation) != "constraint violation" { return 1; }
  if DbError.to_string(DbError.SchemaMismatch) != "schema mismatch" { return 1; }
  if DbError.to_string(DbError.StorageError) != "storage error" { return 1; }
  if DbError.to_string(DbError.Corruption) != "data corruption" { return 1; }
  return 0;
}

fn test_error_to_string() -> TestCase {
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

fn test_error_is_retryable() -> TestCase {
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

fn test_error_db_result_ok() -> TestCase {
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

fn test_error_db_result_err() -> TestCase {
  let rc = run_error_db_result_err();
  if rc == 0 { return assert(true, "error: DbResult[Int] Err variant carries error"); }
  return assert(false, "error: DbResult Err failed");
}

// ═══════════════════════════════════════════════════════════════════════════
// 3. Config defaults and validation
// ═══════════════════════════════════════════════════════════════════════════

fn run_config_default() -> Int {
  let cfg = DatabaseConfig.default();
  if cfg.page_size != 4096 { return 1; }
  if cfg.buffer_pool_capacity != 64 { return 1; }
  if !cfg.wal_enabled { return 1; }
  if cfg.btree_order != 4 { return 1; }
  return 0;
}

fn test_config_default() -> TestCase {
  let rc = run_config_default();
  if rc == 0 { return assert(true, "config: default values (4096/64/true/4)"); }
  return assert(false, "config: default values wrong");
}

fn run_config_validate_valid() -> Int {
  let cfg = DatabaseConfig.default();
  if !database_config_validate(&cfg) { return 1; }
  return 0;
}

fn test_config_validate_valid() -> TestCase {
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

fn test_config_validate_bad_page_size() -> TestCase {
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

fn test_config_validate_page_too_small() -> TestCase {
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

fn test_config_validate_zero_capacity() -> TestCase {
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

fn test_config_validate_bad_btree_order() -> TestCase {
  let rc = run_config_validate_bad_btree_order();
  if rc == 0 { return assert(true, "config: btree_order < 3 rejected"); }
  return assert(false, "config: bad btree order accepted");
}

// ═══════════════════════════════════════════════════════════════════════════
// 4. Contract predicates (is_valid_page_size, is_power_of_two)
// ═══════════════════════════════════════════════════════════════════════════

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

fn test_is_power_of_two() -> TestCase {
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

fn test_is_valid_page_size() -> TestCase {
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

fn test_valid_btree_order() -> TestCase {
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

fn test_valid_key() -> TestCase {
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

fn test_sorted_keys() -> TestCase {
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

fn test_valid_range() -> TestCase {
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

fn test_non_decreasing() -> TestCase {
  let rc = run_non_decreasing();
  if rc == 0 { return assert(true, "contracts: non_decreasing allows duplicates"); }
  return assert(false, "contracts: non_decreasing failed");
}

// ═══════════════════════════════════════════════════════════════════════════
// 5. Page header/structure construction and validation
// ═══════════════════════════════════════════════════════════════════════════

fn run_page_construction() -> Int {
  var data = Vec[Int].new();
  data.push(1);
  data.push(2);
  data.push(3);
  var cs = page_compute_checksum(&data);
  let p = Page.new(0, data, cs);
  if p.id != 0 { return 1; }
  if p.checksum != cs { return 1; }
  return 0;
}

fn test_page_construction() -> TestCase {
  let rc = run_page_construction();
  if rc == 0 { return assert(true, "page: construction + id/checksum store"); }
  return assert(false, "page: construction failed");
}

fn run_page_is_valid() -> Int {
  var data = Vec[Int].new();
  data.push(10);
  data.push(20);
  data.push(30);
  var cs = page_compute_checksum(&data);
  let p = Page.new(5, data, cs);
  if !p.is_valid() { return 1; }
  return 0;
}

fn test_page_is_valid() -> TestCase {
  let rc = run_page_is_valid();
  if rc == 0 { return assert(true, "page: is_valid true with correct checksum"); }
  return assert(false, "page: is_valid failed");
}

fn run_page_is_valid_corrupt() -> Int {
  var data = Vec[Int].new();
  data.push(1);
  var cs = page_compute_checksum(&data);
  let p = Page.new(0, data, cs + 1);
  if p.is_valid() { return 1; }
  return 0;
}

fn test_page_is_valid_corrupt() -> TestCase {
  let rc = run_page_is_valid_corrupt();
  if rc == 0 { return assert(true, "page: is_valid false with wrong checksum"); }
  return assert(false, "page: corrupt page accepted");
}

fn run_page_empty() -> Int {
  var data = Vec[Int].new();
  var cs = page_compute_checksum(&data);
  let p = Page.new(0, data, cs);
  if cs != 0 { return 1; }
  if !p.is_valid() { return 1; }
  return 0;
}

fn test_page_empty() -> TestCase {
  let rc = run_page_empty();
  if rc == 0 { return assert(true, "page: empty page checksum() == 0"); }
  return assert(false, "page: empty page failed");
}

// ═══════════════════════════════════════════════════════════════════════════
// 6. Checksum computation
// ═══════════════════════════════════════════════════════════════════════════

fn run_checksum_determinism() -> Int {
  var d1 = Vec[Int].new();
  d1.push(1);
  d1.push(2);
  d1.push(3);
  var d2 = Vec[Int].new();
  d2.push(1);
  d2.push(2);
  d2.push(3);
  var c1 = page_compute_checksum(&d1);
  var c2 = page_compute_checksum(&d2);
  if c1 != c2 { return 1; }
  return 0;
}

fn test_checksum_determinism() -> TestCase {
  let rc = run_checksum_determinism();
  if rc == 0 { return assert(true, "checksum: deterministic for same data"); }
  return assert(false, "checksum: non-deterministic");
}

fn run_checksum_different_data() -> Int {
  var d1 = Vec[Int].new();
  d1.push(1);
  d1.push(2);
  var d2 = Vec[Int].new();
  d2.push(3);
  d2.push(4);
  var c1 = page_compute_checksum(&d1);
  var c2 = page_compute_checksum(&d2);
  if c1 == c2 { return 1; }
  return 0;
}

fn test_checksum_different_data() -> TestCase {
  let rc = run_checksum_different_data();
  if rc == 0 { return assert(true, "checksum: different data produces different hash"); }
  return assert(false, "checksum: collision on different data");
}

// ═══════════════════════════════════════════════════════════════════════════
// 7. Buffer pool capacity checks
// ═══════════════════════════════════════════════════════════════════════════

fn run_buffer_pool_new() -> Int {
  let bp = BufferPool.new(4);
  if bp.capacity != 4 { return 1; }
  if bp.hits != 0 { return 1; }
  if bp.misses != 0 { return 1; }
  return 0;
}

fn test_buffer_pool_new() -> TestCase {
  let rc = run_buffer_pool_new();
  if rc == 0 { return assert(true, "buffer_pool: construction with capacity 4"); }
  return assert(false, "buffer_pool: construction failed");
}

fn run_buffer_pool_put_get() -> Int {
  var bp = BufferPool.new(4);
  var data = Vec[Int].new();
  data.push(42);
  var cs = page_compute_checksum(&data);
  let page = Page.new(7, data, cs);
  bp.put(page);
  let found = bp.get(7);
  match found {
    None => return 1,
    Some(p) => { if p.id != 7 { return 1; } }
  }
  return 0;
}

fn test_buffer_pool_put_get() -> TestCase {
  let rc = run_buffer_pool_put_get();
  if rc == 0 { return assert(true, "buffer_pool: put then get returns same page"); }
  return assert(false, "buffer_pool: put/get failed");
}

fn run_buffer_pool_miss() -> Int {
  var bp = BufferPool.new(4);
  let found = bp.get(99);
  match found {
    None => return 0,
    Some(_) => return 1,
  }
}

fn test_buffer_pool_miss() -> TestCase {
  let rc = run_buffer_pool_miss();
  if rc == 0 { return assert(true, "buffer_pool: get on empty pool returns None"); }
  return assert(false, "buffer_pool: miss failed");
}

fn run_buffer_pool_hit_ratio() -> Int {
  var bp = BufferPool.new(2);
  var both = bp.hit_ratio();
  if both != 0.0 { return 1; }
  var data = Vec[Int].new();
  data.push(1);
  var cs = page_compute_checksum(&data);
  let page = Page.new(0, data, cs);
  bp.put(page);
  var hr = bp.hit_ratio();
  if hr > 0.0 { return 1; }
  return 0;
}

fn test_buffer_pool_hit_ratio() -> TestCase {
  let rc = run_buffer_pool_hit_ratio();
  if rc == 0 { return assert(true, "buffer_pool: hit_ratio on empty is 0.0"); }
  return assert(false, "buffer_pool: hit_ratio failed");
}

fn run_storage_engine_new() -> Int {
  let cfg = DatabaseConfig.default();
  let eng = StorageEngine.new(cfg);
  return 0;
}

fn test_storage_engine_new() -> TestCase {
  let rc = run_storage_engine_new();
  if rc == 0 { return assert(true, "storage_engine: construction succeeds"); }
  return assert(false, "storage_engine: construction failed");
}

fn run_storage_engine_cache_lookup() -> Int {
  let cfg = DatabaseConfig.default();
  var eng = StorageEngine.new(cfg);
  var data = Vec[Int].new();
  data.push(99);
  var cs = page_compute_checksum(&data);
  let page = Page.new(1, data, cs);
  eng.cache_page(page);
  let found = eng.lookup_page(1);
  match found {
    None => return 1,
    Some(p) => { if p.id != 1 { return 1; } }
  }
  return 0;
}

fn test_storage_engine_cache_lookup() -> TestCase {
  let rc = run_storage_engine_cache_lookup();
  if rc == 0 { return assert(true, "storage_engine: cache_page then lookup_page"); }
  return assert(false, "storage_engine: cache/lookup failed");
}

// ═══════════════════════════════════════════════════════════════════════════
// 8. WAL record types and construction
// ═══════════════════════════════════════════════════════════════════════════

fn run_wal_entry_new() -> Int {
  let entry = wal_entry_new(WALOpType.InsertOp, 10, 100, 1);
  if entry.key != 10 { return 1; }
  if entry.value != 100 { return 1; }
  if entry.timestamp != 1 { return 1; }
  return 0;
}

fn test_wal_entry_new() -> TestCase {
  let rc = run_wal_entry_new();
  if rc == 0 { return assert(true, "wal: WALEntry construction fields correct"); }
  return assert(false, "wal: WALEntry construction failed");
}

fn run_wal_new_and_append() -> Int {
  var wal = wal_new();
  if !wal_is_empty(&wal) { return 1; }
  if wal_len(&wal) != 0 { return 1; }
  let e1 = wal_entry_new(InsertOp, 1, 10, 1);
  wal_append(&mut wal, e1);
  if wal_is_empty(&wal) { return 1; }
  if wal_len(&wal) != 1 { return 1; }
  let e2 = wal_entry_new(DeleteOp, 2, 0, 2);
  wal_append(&mut wal, e2);
  if wal_len(&wal) != 2 { return 1; }
  return 0;
}

fn test_wal_new_and_append() -> TestCase {
  let rc = run_wal_new_and_append();
  if rc == 0 { return assert(true, "wal: new/is_empty/len append grows"); }
  return assert(false, "wal: append/len failed");
}

fn run_wal_entry_count_filter() -> Int {
  var wal = wal_new();
  wal_append(&mut wal, wal_entry_new(InsertOp, 1, 10, 1));
  wal_append(&mut wal, wal_entry_new(InsertOp, 2, 20, 2));
  wal_append(&mut wal, wal_entry_new(DeleteOp, 3, 0, 3));
  wal_append(&mut wal, wal_entry_new(UpdateOp, 4, 40, 4));
  var inserts = wal_entry_count(&wal, WALOpType.InsertOp);
  if inserts != 2 { return 1; }
  var deletes = wal_entry_count(&wal, WALOpType.DeleteOp);
  if deletes != 1 { return 1; }
  var updates = wal_entry_count(&wal, WALOpType.UpdateOp);
  if updates != 1 { return 1; }
  return 0;
}

fn test_wal_entry_count_filter() -> TestCase {
  let rc = run_wal_entry_count_filter();
  if rc == 0 { return assert(true, "wal: entry_count by op type filter"); }
  return assert(false, "wal: entry_count filter wrong");
}

fn run_wal_clear() -> Int {
  var wal = wal_new();
  wal_append(&mut wal, wal_entry_new(InsertOp, 1, 10, 1));
  wal_append(&mut wal, wal_entry_new(InsertOp, 2, 20, 2));
  wal_clear(&mut wal);
  if !wal_is_empty(&wal) { return 1; }
  if wal_len(&wal) != 0 { return 1; }
  return 0;
}

fn test_wal_clear() -> TestCase {
  let rc = run_wal_clear();
  if rc == 0 { return assert(true, "wal: clear empties all entries"); }
  return assert(false, "wal: clear failed");
}

fn run_wal_truncate() -> Int {
  var wal = wal_new();
  wal_append(&mut wal, wal_entry_new(InsertOp, 1, 10, 1));
  wal_append(&mut wal, wal_entry_new(InsertOp, 2, 20, 5));
  wal_append(&mut wal, wal_entry_new(InsertOp, 3, 30, 10));
  wal_truncate(&mut wal, 5);
  if wal_len(&wal) != 2 { return 1; }
  wal_truncate(&mut wal, 10);
  if wal_len(&wal) != 1 { return 1; }
  return 0;
}

fn test_wal_truncate() -> TestCase {
  let rc = run_wal_truncate();
  if rc == 0 { return assert(true, "wal: truncate keeps entries >= timestamp"); }
  return assert(false, "wal: truncate failed");
}

fn run_wal_replay_insert() -> Int {
  var wal = wal_new();
  wal_append(&mut wal, wal_entry_new(InsertOp, 10, 100, 1));
  wal_append(&mut wal, wal_entry_new(InsertOp, 20, 200, 2));
  wal_append(&mut wal, wal_entry_new(InsertOp, 30, 300, 3));
  var tree = btree_new(4);
  let ok = wal_replay(&wal, &mut tree);
  if !ok { return 1; }
  let v = btree_search(&tree, 10);
  match v { None => return 1; Some(_) => {} }
  let v2 = btree_search(&tree, 20);
  match v2 { None => return 1; Some(_) => {} }
  let v3 = btree_search(&tree, 30);
  match v3 { None => return 1; Some(_) => {} }
  return 0;
}

fn test_wal_replay_insert() -> TestCase {
  let rc = run_wal_replay_insert();
  if rc == 0 { return assert(true, "wal: replay inserts into fresh BTree"); }
  return assert(false, "wal: replay insert failed");
}

fn run_wal_replay_delete() -> Int {
  var tree = btree_new(4);
  btree_insert(&mut tree, 10, 100);
  btree_insert(&mut tree, 20, 200);
  var wal = wal_new();
  wal_append(&mut wal, wal_entry_new(DeleteOp, 10, 0, 1));
  let ok = wal_replay(&wal, &mut tree);
  if !ok { return 1; }
  let v = btree_search(&tree, 10);
  match v { Some(_) => return 1; None => {} }
  let v2 = btree_search(&tree, 20);
  match v2 { None => return 1; Some(_) => {} }
  return 0;
}

fn test_wal_replay_delete() -> TestCase {
  let rc = run_wal_replay_delete();
  if rc == 0 { return assert(true, "wal: replay deletes existing key"); }
  return assert(false, "wal: replay delete failed");
}

// ═══════════════════════════════════════════════════════════════════════════
// 9. Transaction state machine transitions
// ═══════════════════════════════════════════════════════════════════════════

fn run_txn_new_is_active() -> Int {
  let txn = Transaction.new(1);
  if !txn.is_active() { return 1; }
  return 0;
}

fn test_txn_new_is_active() -> TestCase {
  let rc = run_txn_new_is_active();
  if rc == 0 { return assert(true, "txn: new transaction is Active"); }
  return assert(false, "txn: new not active");
}

fn run_txn_commit() -> Int {
  let txn = Transaction.new(1);
  let committed = txn.commit();
  if committed.is_active() { return 1; }
  return 0;
}

fn test_txn_commit() -> TestCase {
  let rc = run_txn_commit();
  if rc == 0 { return assert(true, "txn: commit moves to Committed (not active)"); }
  return assert(false, "txn: commit failed");
}

fn run_txn_abort() -> Int {
  let txn = Transaction.new(1);
  let aborted = txn.abort();
  if aborted.is_active() { return 1; }
  return 0;
}

fn test_txn_abort() -> TestCase {
  let rc = run_txn_abort();
  if rc == 0 { return assert(true, "txn: abort moves to Aborted (not active)"); }
  return assert(false, "txn: abort failed");
}

fn run_txn_add_op() -> Int {
  let txn = Transaction.new(1);
  let with_op = txn.add_op(WALOp.Insert);
  if !with_op.is_active() { return 1; }
  return 0;
}

fn test_txn_add_op() -> TestCase {
  let rc = run_txn_add_op();
  if rc == 0 { return assert(true, "txn: add_op on active transaction succeeds"); }
  return assert(false, "txn: add_op failed");
}

fn run_txn_full_lifecycle() -> Int {
  let txn1 = Transaction.new(1);
  let txn2 = txn1.add_op(WALOp.Insert);
  let txn3 = txn2.add_op(WALOp.Update);
  let txn4 = txn3.commit();
  if txn4.is_active() { return 1; }
  return 0;
}

fn test_txn_full_lifecycle() -> TestCase {
  let rc = run_txn_full_lifecycle();
  if rc == 0 { return assert(true, "txn: active->add->add->commit lifecycle"); }
  return assert(false, "txn: lifecycle failed");
}

fn run_txn_abort_lifecycle() -> Int {
  let txn1 = Transaction.new(2);
  let txn2 = txn1.add_op(WALOp.Delete);
  let txn3 = txn2.abort();
  if txn3.is_active() { return 1; }
  return 0;
}

fn test_txn_abort_lifecycle() -> TestCase {
  let rc = run_txn_abort_lifecycle();
  if rc == 0 { return assert(true, "txn: active->add->abort lifecycle"); }
  return assert(false, "txn: abort lifecycle failed");
}

// ═══════════════════════════════════════════════════════════════════════════
// 10. Schema validation stubs
// ═══════════════════════════════════════════════════════════════════════════

fn run_schema_column_def_new() -> Int {
  let col = ColumnDef.new("id", ColumnType.IntType);
  if col.name != "id" { return 1; }
  return 0;
}

fn test_schema_column_def_new() -> TestCase {
  let rc = run_schema_column_def_new();
  if rc == 0 { return assert(true, "schema: ColumnDef.new stores name+type"); }
  return assert(false, "schema: ColumnDef.new failed");
}

fn run_schema_column_def_optional() -> Int {
  let col = ColumnDef.optional("email", ColumnType.StringType, None);
  if col.name != "email" { return 1; }
  if !col.nullable { return 1; }
  return 0;
}

fn test_schema_column_def_optional() -> TestCase {
  let rc = run_schema_column_def_optional();
  if rc == 0 { return assert(true, "schema: ColumnDef.optional sets nullable=true"); }
  return assert(false, "schema: ColumnDef.optional failed");
}

fn run_schema_new_and_accessors() -> Int {
  var cols = Vec[ColumnDef].new();
  cols.push(ColumnDef.new("id", ColumnType.IntType));
  cols.push(ColumnDef.new("name", ColumnType.StringType));
  cols.push(ColumnDef.new("age", ColumnType.IntType));
  let schema = Schema.new("users", cols, 0);
  if schema.table_name != "users" { return 1; }
  if schema.column_count() != 3 { return 1; }
  return 0;
}

fn test_schema_new_and_accessors() -> TestCase {
  let rc = run_schema_new_and_accessors();
  if rc == 0 { return assert(true, "schema: Schema.new stores table + columns"); }
  return assert(false, "schema: Schema.new failed");
}

fn run_schema_column_index() -> Int {
  var cols = Vec[ColumnDef].new();
  cols.push(ColumnDef.new("id", ColumnType.IntType));
  cols.push(ColumnDef.new("name", ColumnType.StringType));
  let schema = Schema.new("t", cols, 0);
  let idx = schema.column_index("name");
  match idx { None => return 1; Some(i) => { if i != 1 { return 1; } } }
  let missing = schema.column_index("nonexistent");
  match missing { Some(_) => return 1; None => {} }
  return 0;
}

fn test_schema_column_index() -> TestCase {
  let rc = run_schema_column_index();
  if rc == 0 { return assert(true, "schema: column_index find + not-found"); }
  return assert(false, "schema: column_index failed");
}

fn run_index_def_new() -> Int {
  let idx = IndexDef.new("idx_users_name", "users", 1, false);
  if idx.name != "idx_users_name" { return 1; }
  if idx.table != "users" { return 1; }
  if idx.column != 1 { return 1; }
  if idx.unique { return 1; }
  return 0;
}

fn test_index_def_new() -> TestCase {
  let rc = run_index_def_new();
  if rc == 0 { return assert(true, "schema: IndexDef.new fields correct"); }
  return assert(false, "schema: IndexDef.new failed");
}

fn run_validate_schema_valid() -> Int {
  var cols = Vec[ColumnDef].new();
  cols.push(ColumnDef.new("id", ColumnType.IntType));
  let schema = Schema.new("t", cols, 0);
  let r = validate_schema(&schema);
  match r {
    Ok(v) => { if !v { return 1; } return 0; }
    Err(_) => return 1,
  }
}

fn test_validate_schema_valid() -> TestCase {
  let rc = run_validate_schema_valid();
  if rc == 0 { return assert(true, "schema_validator: valid schema passes"); }
  return assert(false, "schema_validator: valid schema rejected");
}

fn run_validate_schema_no_columns() -> Int {
  var cols = Vec[ColumnDef].new();
  let schema = Schema.new("t", cols, 0);
  let r = validate_schema(&schema);
  match r {
    Ok(_) => return 1,
    Err(_) => return 0,
  }
}

fn test_validate_schema_no_columns() -> TestCase {
  let rc = run_validate_schema_no_columns();
  if rc == 0 { return assert(true, "schema_validator: zero columns rejected"); }
  return assert(false, "schema_validator: zero columns accepted");
}

fn run_validate_schema_pk_out_of_range() -> Int {
  var cols = Vec[ColumnDef].new();
  cols.push(ColumnDef.new("id", ColumnType.IntType));
  let schema = Schema.new("t", cols, 5);
  let r = validate_schema(&schema);
  match r {
    Ok(_) => return 1,
    Err(_) => return 0,
  }
}

fn test_validate_schema_pk_out_of_range() -> TestCase {
  let rc = run_validate_schema_pk_out_of_range();
  if rc == 0 { return assert(true, "schema_validator: out-of-range PK rejected"); }
  return assert(false, "schema_validator: bad PK accepted");
}

fn run_validate_column_valid() -> Int {
  let col = ColumnDef.new("x", ColumnType.IntType);
  let r = validate_column(&col);
  match r {
    Ok(v) => { if !v { return 1; } return 0; }
    Err(_) => return 1,
  }
}

fn test_validate_column_valid() -> TestCase {
  let rc = run_validate_column_valid();
  if rc == 0 { return assert(true, "schema_validator: named column passes"); }
  return assert(false, "schema_validator: named column rejected");
}

fn run_validate_index_valid() -> Int {
  var cols = Vec[ColumnDef].new();
  cols.push(ColumnDef.new("a", ColumnType.IntType));
  cols.push(ColumnDef.new("b", ColumnType.StringType));
  let schema = Schema.new("t", cols, 0);
  let idx = IndexDef.new("my_idx", "t", 1, true);
  let r = validate_index(&idx, &schema);
  match r {
    Ok(v) => { if !v { return 1; } return 0; }
    Err(_) => return 1,
  }
}

fn test_validate_index_valid() -> TestCase {
  let rc = run_validate_index_valid();
  if rc == 0 { return assert(true, "schema_validator: valid index passes"); }
  return assert(false, "schema_validator: valid index rejected");
}

fn run_validate_index_wrong_table() -> Int {
  var cols = Vec[ColumnDef].new();
  cols.push(ColumnDef.new("a", ColumnType.IntType));
  let schema = Schema.new("t", cols, 0);
  let idx = IndexDef.new("idx", "other_table", 0, false);
  let r = validate_index(&idx, &schema);
  match r {
    Ok(_) => return 1,
    Err(_) => return 0,
  }
}

fn test_validate_index_wrong_table() -> TestCase {
  let rc = run_validate_index_wrong_table();
  if rc == 0 { return assert(true, "schema_validator: mismatched table rejected"); }
  return assert(false, "schema_validator: wrong table accepted");
}

// ═══════════════════════════════════════════════════════════════════════════
// 11. Query planner stubs
// ═══════════════════════════════════════════════════════════════════════════

fn run_query_new() -> Int {
  let q = query_new();
  if q.condition_count() != 0 { return 1; }
  if q.has_limit() { return 1; }
  if q.has_offset() { return 1; }
  return 0;
}

fn test_query_new() -> TestCase {
  let rc = run_query_new();
  if rc == 0 { return assert(true, "query: query_new has zero conditions/limit/offset"); }
  return assert(false, "query: query_new failed");
}

fn run_query_where_limit_offset() -> Int {
  var q = query_new();
  q.where(QueryOp.Eq, 42);
  q.where(QueryOp.Gt, 0);
  q.limit(10);
  q.offset(5);
  if q.condition_count() != 2 { return 1; }
  if !q.has_limit() { return 1; }
  if !q.has_offset() { return 1; }
  return 0;
}

fn test_query_where_limit_offset() -> TestCase {
  let rc = run_query_where_limit_offset();
  if rc == 0 { return assert(true, "query: where/limit/offset builder"); }
  return assert(false, "query: query builder failed");
}

fn run_query_reset() -> Int {
  var q = query_new();
  q.where(QueryOp.Eq, 1);
  q.limit(5);
  q.offset(3);
  q.reset();
  if q.condition_count() != 0 { return 1; }
  if q.has_limit() { return 1; }
  if q.has_offset() { return 1; }
  return 0;
}

fn test_query_reset() -> TestCase {
  let rc = run_query_reset();
  if rc == 0 { return assert(true, "query: reset clears conditions/limit/offset"); }
  return assert(false, "query: reset failed");
}

fn run_query_execute_simple() -> Int {
  var tree = btree_new(4);
  btree_insert(&mut tree, 10, 100);
  btree_insert(&mut tree, 20, 200);
  btree_insert(&mut tree, 30, 300);
  var q = query_new();
  q.where(QueryOp.Gte, 15);
  let results = query_execute(&q, &tree);
  if results.len() != 2 { return 1; }
  return 0;
}

fn test_query_execute_simple() -> TestCase {
  let rc = run_query_execute_simple();
  if rc == 0 { return assert(true, "query: execute applies filter condition"); }
  return assert(false, "query: execute failed");
}

fn run_plan_query_defaults_to_full_scan() -> Int {
  var tree = btree_new(4);
  btree_insert(&mut tree, 1, 10);
  btree_insert(&mut tree, 2, 20);
  var q = query_new();
  let plan = plan_query(&q, &tree);
  if plan.estimated_rows != 2 { return 1; }
  return 0;
}

fn test_plan_query_defaults_to_full_scan() -> TestCase {
  let rc = run_plan_query_defaults_to_full_scan();
  if rc == 0 { return assert(true, "planner: plan_query sets estimated_rows"); }
  return assert(false, "planner: plan_query failed");
}

fn run_execute_plan_full_scan() -> Int {
  var tree = btree_new(4);
  btree_insert(&mut tree, 1, 11);
  btree_insert(&mut tree, 2, 22);
  btree_insert(&mut tree, 3, 33);
  var q = query_new();
  q.where(QueryOp.Gt, 0);
  let plan = plan_query(&q, &tree);
  let results = execute_plan(&plan, &q, &tree);
  if results.len() != 3 { return 1; }
  return 0;
}

fn test_execute_plan_full_scan() -> TestCase {
  let rc = run_execute_plan_full_scan();
  if rc == 0 { return assert(true, "planner: execute_plan runs full scan"); }
  return assert(false, "planner: execute_plan failed");
}

// ═══════════════════════════════════════════════════════════════════════════
// 12. B-tree node structure and operations
// ═══════════════════════════════════════════════════════════════════════════

fn run_btree_new() -> Int {
  let tree = btree_new(4);
  if btree_size(&tree) != 0 { return 1; }
  return 0;
}

fn test_btree_new() -> TestCase {
  let rc = run_btree_new();
  if rc == 0 { return assert(true, "btree: new tree has size 0"); }
  return assert(false, "btree: new failed");
}

fn run_btree_insert_search() -> Int {
  var tree = btree_new(4);
  let ins = btree_insert(&mut tree, 10, 100);
  if !ins { return 1; }
  let v = btree_search(&tree, 10);
  match v { None => return 1; Some(val) => { if val != 100 { return 1; } } }
  return 0;
}

fn test_btree_insert_search() -> TestCase {
  let rc = run_btree_insert_search();
  if rc == 0 { return assert(true, "btree: insert then search returns value"); }
  return assert(false, "btree: insert/search failed");
}

fn run_btree_delete() -> Int {
  var tree = btree_new(4);
  btree_insert(&mut tree, 10, 100);
  btree_insert(&mut tree, 20, 200);
  btree_insert(&mut tree, 30, 300);
  let del = btree_delete(&mut tree, 20);
  if !del { return 1; }
  let v = btree_search(&tree, 20);
  match v { Some(_) => return 1; None => {} }
  if btree_size(&tree) != 2 { return 1; }
  return 0;
}

fn test_btree_delete() -> TestCase {
  let rc = run_btree_delete();
  if rc == 0 { return assert(true, "btree: delete removes key, size decreases"); }
  return assert(false, "btree: delete failed");
}

fn run_btree_min_max() -> Int {
  var tree = btree_new(4);
  btree_insert(&mut tree, 50, 500);
  btree_insert(&mut tree, 10, 100);
  btree_insert(&mut tree, 99, 990);
  let mn = btree_min(&tree);
  match mn { None => return 1; Some(v) => { if v != 100 { return 1; } } }
  let mx = btree_max(&tree);
  match mx { None => return 1; Some(v) => { if v != 990 { return 1; } } }
  return 0;
}

fn test_btree_min_max() -> TestCase {
  let rc = run_btree_min_max();
  if rc == 0 { return assert(true, "btree: min/max returns correct extremes"); }
  return assert(false, "btree: min/max failed");
}

fn run_btree_range_query() -> Int {
  var tree = btree_new(4);
  btree_insert(&mut tree, 10, 100);
  btree_insert(&mut tree, 20, 200);
  btree_insert(&mut tree, 30, 300);
  btree_insert(&mut tree, 40, 400);
  btree_insert(&mut tree, 50, 500);
  let results = btree_range_query(&tree, 20, 40);
  if results.len() != 3 { return 1; }
  return 0;
}

fn test_btree_range_query() -> TestCase {
  let rc = run_btree_range_query();
  if rc == 0 { return assert(true, "btree: range_query [20,40] returns 3 values"); }
  return assert(false, "btree: range_query failed");
}

fn run_btree_to_vec() -> Int {
  var tree = btree_new(4);
  btree_insert(&mut tree, 30, 300);
  btree_insert(&mut tree, 10, 100);
  btree_insert(&mut tree, 20, 200);
  let vals = btree_to_vec(&tree);
  if vals.len() != 3 { return 1; }
  return 0;
}

fn test_btree_to_vec() -> TestCase {
  let rc = run_btree_to_vec();
  if rc == 0 { return assert(true, "btree: to_vec returns all values"); }
  return assert(false, "btree: to_vec failed");
}

fn run_btree_large_insert() -> Int {
  var tree = btree_new(5);
  var i = 0;
  while i < 100 {
    btree_insert(&mut tree, i, i * 10);
    i = i + 1;
  }
  if btree_size(&tree) != 100 { return 1; }
  let v = btree_search(&tree, 50);
  match v { None => return 1; Some(val) => { if val != 500 { return 1; } } }
  let v2 = btree_search(&tree, 99);
  match v2 { None => return 1; Some(val) => { if val != 990 { return 1; } } }
  return 0;
}

fn test_btree_large_insert() -> TestCase {
  let rc = run_btree_large_insert();
  if rc == 0 { return assert(true, "btree: 100 inserts with splits, all searchable"); }
  return assert(false, "btree: large insert failed");
}

// ═══════════════════════════════════════════════════════════════════════════
// Integration: Engine + Database facade
// ═══════════════════════════════════════════════════════════════════════════

fn run_engine_new() -> Int {
  let eng = engine_new(4);
  if engine_size(&eng) != 0 { return 1; }
  if engine_wal_size(&eng) != 0 { return 1; }
  return 0;
}

fn test_engine_new() -> TestCase {
  let rc = run_engine_new();
  if rc == 0 { return assert(true, "engine: engine_new starts empty"); }
  return assert(false, "engine: new failed");
}

fn run_engine_insert_get() -> Int {
  var eng = engine_new(4);
  let ok = engine_insert(&mut eng, 5, 55);
  if !ok { return 1; }
  let v = engine_get(&eng, 5);
  match v { None => return 1; Some(val) => { if val != 55 { return 1; } } }
  return 0;
}

fn test_engine_insert_get() -> TestCase {
  let rc = run_engine_insert_get();
  if rc == 0 { return assert(true, "engine: insert then get returns value"); }
  return assert(false, "engine: insert/get failed");
}

fn run_engine_delete() -> Int {
  var eng = engine_new(4);
  engine_insert(&mut eng, 10, 100);
  let del = engine_delete(&mut eng, 10);
  if !del { return 1; }
  let v = engine_get(&eng, 10);
  match v { Some(_) => return 1; None => {} }
  return 0;
}

fn test_engine_delete() -> TestCase {
  let rc = run_engine_delete();
  if rc == 0 { return assert(true, "engine: delete removes existing key"); }
  return assert(false, "engine: delete failed");
}

fn run_engine_update() -> Int {
  var eng = engine_new(4);
  engine_insert(&mut eng, 1, 10);
  let up = engine_update(&mut eng, 1, 99);
  if !up { return 1; }
  let v = engine_get(&eng, 1);
  match v { None => return 1; Some(val) => { if val != 99 { return 1; } } }
  return 0;
}

fn test_engine_update() -> TestCase {
  let rc = run_engine_update();
  if rc == 0 { return assert(true, "engine: update changes existing value"); }
  return assert(false, "engine: update failed");
}

fn run_engine_recover() -> Int {
  var eng = engine_new(4);
  engine_insert(&mut eng, 1, 11);
  engine_insert(&mut eng, 2, 22);
  engine_insert(&mut eng, 3, 33);
  let ok = engine_recover(&mut eng);
  if !ok { return 1; }
  if engine_size(&eng) != 3 { return 1; }
  let v = engine_get(&eng, 2);
  match v { None => return 1; Some(val) => { if val != 22 { return 1; } } }
  return 0;
}

fn test_engine_recover() -> TestCase {
  let rc = run_engine_recover();
  if rc == 0 { return assert(true, "engine: recover replays WAL, restores state"); }
  return assert(false, "engine: recover failed");
}

fn run_engine_range_query() -> Int {
  var eng = engine_new(4);
  engine_insert(&mut eng, 5, 50);
  engine_insert(&mut eng, 15, 150);
  engine_insert(&mut eng, 25, 250);
  engine_insert(&mut eng, 35, 350);
  let results = engine_range_query(&eng, 10, 30);
  if results.len() != 2 { return 1; }
  return 0;
}

fn test_engine_range_query() -> TestCase {
  let rc = run_engine_range_query();
  if rc == 0 { return assert(true, "engine: range_query returns correct subset"); }
  return assert(false, "engine: range_query failed");
}

fn run_engine_flush_wal() -> Int {
  var eng = engine_new(4);
  engine_insert(&mut eng, 1, 10);
  engine_insert(&mut eng, 2, 20);
  engine_flush_wal(&mut eng);
  if engine_wal_size(&eng) != 0 { return 1; }
  if engine_size(&eng) != 2 { return 1; }
  return 0;
}

fn test_engine_flush_wal() -> TestCase {
  let rc = run_engine_flush_wal();
  if rc == 0 { return assert(true, "engine: flush_wal zeros WAL, data persists"); }
  return assert(false, "engine: flush_wal failed");
}

fn run_db_open_and_operations() -> Int {
  var db = db_open(4);
  if !db.open { return 1; }
  let ok = db_insert(&mut db, 1, 100);
  if !ok { return 1; }
  let v = db_get(&db, 1);
  match v { None => return 1; Some(val) => { if val != 100 { return 1; } } }
  if db.size() != 1 { return 1; }
  return 0;
}

fn test_db_open_and_operations() -> TestCase {
  let rc = run_db_open_and_operations();
  if rc == 0 { return assert(true, "database: open/insert/get/size workflow"); }
  return assert(false, "database: workflow failed");
}

fn run_db_closed_rejects_ops() -> Int {
  var db = db_open(4);
  db_insert(&mut db, 1, 100);
  db.close();
  let v = db.get(&db, 1);
  match v { Some(_) => return 1; None => {} }
  let ok = db_insert(&mut db, 2, 200);
  if ok { return 1; }
  return 0;
}

fn test_db_closed_rejects_ops() -> TestCase {
  let rc = run_db_closed_rejects_ops();
  if rc == 0 { return assert(true, "database: closed handle rejects get+insert"); }
  return assert(false, "database: closed rejection failed");
}

fn run_db_update_delete() -> Int {
  var db = db_open(4);
  db_insert(&mut db, 1, 10);
  let up = db_update(&mut db, 1, 99);
  if !up { return 1; }
  let v = db_get(&db, 1);
  match v { None => return 1; Some(val) => { if val != 99 { return 1; } } }
  let del = db_delete(&mut db, 1);
  if !del { return 1; }
  let v2 = db_get(&db, 1);
  match v2 { Some(_) => return 1; None => {} }
  return 0;
}

fn test_db_update_delete() -> TestCase {
  let rc = run_db_update_delete();
  if rc == 0 { return assert(true, "database: update then delete full cycle"); }
  return assert(false, "database: update/delete failed");
}

fn run_db_range() -> Int {
  var db = db_open(4);
  db_insert(&mut db, 1, 10);
  db_insert(&mut db, 3, 30);
  db_insert(&mut db, 5, 50);
  db_insert(&mut db, 7, 70);
  let results = db_range(&db, 3, 6);
  if results.len() != 2 { return 1; }
  return 0;
}

fn test_db_range() -> TestCase {
  let rc = run_db_range();
  if rc == 0 { return assert(true, "database: db_range returns correct subset"); }
  return assert(false, "database: db_range failed");
}

fn run_db_recover() -> Int {
  var db = db_open(4);
  db_insert(&mut db, 1, 10);
  db_insert(&mut db, 2, 20);
  let ok = db_recover(&mut db);
  if !ok { return 1; }
  if db.size() != 2 { return 1; }
  return 0;
}

fn test_db_recover() -> TestCase {
  let rc = run_db_recover();
  if rc == 0 { return assert(true, "database: db_recover rebuilds from WAL"); }
  return assert(false, "database: db_recover failed");
}

fn run_db_query() -> Int {
  var db = db_open(4);
  db_insert(&mut db, 10, 100);
  db_insert(&mut db, 20, 200);
  db_insert(&mut db, 30, 300);
  var q = query_new();
  q.where(QueryOp.Gte, 20);
  let results = db_query(&db, &q);
  if results.len() != 2 { return 1; }
  return 0;
}

fn test_db_query() -> TestCase {
  let rc = run_db_query();
  if rc == 0 { return assert(true, "database: db_query applies filter"); }
  return assert(false, "database: db_query failed");
}

// ═══════════════════════════════════════════════════════════════════════════
// Free space map scaffold tests
// ═══════════════════════════════════════════════════════════════════════════

fn run_fsm_new() -> Int {
  let fsm = free_space_map_new();
  if fsm_page_count(&fsm) != 0 { return 1; }
  return 0;
}

fn test_fsm_new() -> TestCase {
  let rc = run_fsm_new();
  if rc == 0 { return assert(true, "fsm: free_space_map_new has 0 pages"); }
  return assert(false, "fsm: fsm new failed");
}

fn run_fsm_register_and_find() -> Int {
  var fsm = free_space_map_new();
  let pid = fsm_register_page(&mut fsm, 4096);
  fsm_register_page(&mut fsm, 100);
  if fsm_page_count(&fsm) != 2 { return 1; }
  let found = fsm_find_page(&fsm, 2000);
  match found { None => return 1; Some(_) => {} }
  let not_found = fsm_find_page(&fsm, 5000);
  match not_found { Some(_) => return 1; None => {} }
  return 0;
}

fn test_fsm_register_and_find() -> TestCase {
  let rc = run_fsm_register_and_find();
  if rc == 0 { return assert(true, "fsm: register pages, find by free bytes"); }
  return assert(false, "fsm: register/find failed");
}

fn run_fsm_record_used() -> Int {
  var fsm = free_space_map_new();
  let pid = fsm_register_page(&mut fsm, 4096);
  fsm_record_used(&mut fsm, &pid, 500);
  let found = fsm_find_page(&fsm, 4000);
  match found { Some(_) => return 1; None => {} }
  let found2 = fsm_find_page(&fsm, 3000);
  match found2 { None => return 1; Some(_) => {} }
  return 0;
}

fn test_fsm_record_used() -> TestCase {
  let rc = run_fsm_record_used();
  if rc == 0 { return assert(true, "fsm: record_used reduces free bytes"); }
  return assert(false, "fsm: record_used failed");
}

// ═══════════════════════════════════════════════════════════════════════════
// Tuple codec tests
// ═══════════════════════════════════════════════════════════════════════════

fn run_row_new_and_access() -> Int {
  var data = Vec[Int].new();
  data.push(10);
  data.push(20);
  data.push(30);
  let row = Row.new(1, data);
  if row.column_count() != 3 { return 1; }
  let c0 = row.get_column(0);
  match c0 { None => return 1; Some(v) => { if v != 10 { return 1; } } }
  let c1 = row.get_column(1);
  match c1 { None => return 1; Some(v) => { if v != 20 { return 1; } } }
  let c2 = row.get_column(2);
  match c2 { None => return 1; Some(v) => { if v != 30 { return 1; } } }
  return 0;
}

fn test_row_new_and_access() -> TestCase {
  let rc = run_row_new_and_access();
  if rc == 0 { return assert(true, "tuple: Row.new + get_column access"); }
  return assert(false, "tuple: row access failed");
}

fn run_row_set_column() -> Int {
  var data = Vec[Int].new();
  data.push(10);
  let row = Row.new(1, data);
  let ok = row.set_column(0, 99);
  if !ok { return 1; }
  let v = row.get_column(0);
  match v { None => return 1; Some(val) => { if val != 99 { return 1; } } }
  return 0;
}

fn test_row_set_column() -> TestCase {
  let rc = run_row_set_column();
  if rc == 0 { return assert(true, "tuple: Row.set_column updates in place"); }
  return assert(false, "tuple: set_column failed");
}

fn run_tuple_encode_decode() -> Int {
  var data = Vec[Int].new();
  data.push(42);
  data.push(99);
  let row = Row.new(7, data);
  let encoded = tuple_encode(&row);
  let r = tuple_decode(&encoded);
  match r {
    Err(_) => return 1,
    Ok(decoded) => {
      if decoded.id != 7 { return 1; }
      if decoded.column_count() != 2 { return 1; }
      let c0 = decoded.get_column(0);
      match c0 { None => return 1; Some(v) => { if v != 42 { return 1; } } }
      let c1 = decoded.get_column(1);
      match c1 { None => return 1; Some(v) => { if v != 99 { return 1; } } }
    }
  }
  return 0;
}

fn test_tuple_encode_decode() -> TestCase {
  let rc = run_tuple_encode_decode();
  if rc == 0 { return assert(true, "tuple: encode then decode roundtrip"); }
  return assert(false, "tuple: encode/decode failed");
}

fn run_result_set_ops() -> Int {
  var cols = Vec[Str].new();
  cols.push("id");
  cols.push("val");
  var rs = ResultSet.new(cols);
  if rs.column_count() != 2 { return 1; }
  if rs.row_count() != 0 { return 1; }
  var d1 = Vec[Int].new();
  d1.push(1);
  d1.push(10);
  rs.add_row(Row.new(0, d1));
  var d2 = Vec[Int].new();
  d2.push(2);
  d2.push(20);
  rs.add_row(Row.new(1, d2));
  if rs.row_count() != 2 { return 1; }
  let r = rs.get_row(0);
  match r { None => return 1; Some(_) => {} }
  let missing = rs.get_row(99);
  match missing { Some(_) => return 1; None => {} }
  return 0;
}

fn test_result_set_ops() -> TestCase {
  let rc = run_result_set_ops();
  if rc == 0 { return assert(true, "tuple: ResultSet add/row_count/get_row"); }
  return assert(false, "tuple: ResultSet ops failed");
}

// ═══════════════════════════════════════════════════════════════════════════
// Main
// ═══════════════════════════════════════════════════════════════════════════

fn main() -> Int {
  io.println("=== XIOM DB Conformance Tests ===");

  var failed: Int = 0;
  var total: Int = 0;

  // 1. Types: RowId, TableId, PageId
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

  // 2. Error types
  let r8 = test_error_to_string();
  total = total + 1; failed = failed + report(r8.passed, r8.name);
  let r9 = test_error_is_retryable();
  total = total + 1; failed = failed + report(r9.passed, r9.name);
  let r10 = test_error_db_result_ok();
  total = total + 1; failed = failed + report(r10.passed, r10.name);
  let r11 = test_error_db_result_err();
  total = total + 1; failed = failed + report(r11.passed, r11.name);

  // 3. Config
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

  // 4. Contract predicates
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

  // 5. Page construction and validation
  let r25 = test_page_construction();
  total = total + 1; failed = failed + report(r25.passed, r25.name);
  let r26 = test_page_is_valid();
  total = total + 1; failed = failed + report(r26.passed, r26.name);
  let r27 = test_page_is_valid_corrupt();
  total = total + 1; failed = failed + report(r27.passed, r27.name);
  let r28 = test_page_empty();
  total = total + 1; failed = failed + report(r28.passed, r28.name);

  // 6. Checksum
  let r29 = test_checksum_determinism();
  total = total + 1; failed = failed + report(r29.passed, r29.name);
  let r30 = test_checksum_different_data();
  total = total + 1; failed = failed + report(r30.passed, r30.name);

  // 7. Buffer pool
  let r31 = test_buffer_pool_new();
  total = total + 1; failed = failed + report(r31.passed, r31.name);
  let r32 = test_buffer_pool_put_get();
  total = total + 1; failed = failed + report(r32.passed, r32.name);
  let r33 = test_buffer_pool_miss();
  total = total + 1; failed = failed + report(r33.passed, r33.name);
  let r34 = test_buffer_pool_hit_ratio();
  total = total + 1; failed = failed + report(r34.passed, r34.name);
  let r35 = test_storage_engine_new();
  total = total + 1; failed = failed + report(r35.passed, r35.name);
  let r36 = test_storage_engine_cache_lookup();
  total = total + 1; failed = failed + report(r36.passed, r36.name);

  // 8. WAL
  let r37 = test_wal_entry_new();
  total = total + 1; failed = failed + report(r37.passed, r37.name);
  let r38 = test_wal_new_and_append();
  total = total + 1; failed = failed + report(r38.passed, r38.name);
  let r39 = test_wal_entry_count_filter();
  total = total + 1; failed = failed + report(r39.passed, r39.name);
  let r40 = test_wal_clear();
  total = total + 1; failed = failed + report(r40.passed, r40.name);
  let r41 = test_wal_truncate();
  total = total + 1; failed = failed + report(r41.passed, r41.name);
  let r42 = test_wal_replay_insert();
  total = total + 1; failed = failed + report(r42.passed, r42.name);
  let r43 = test_wal_replay_delete();
  total = total + 1; failed = failed + report(r43.passed, r43.name);

  // 9. Transaction
  let r44 = test_txn_new_is_active();
  total = total + 1; failed = failed + report(r44.passed, r44.name);
  let r45 = test_txn_commit();
  total = total + 1; failed = failed + report(r45.passed, r45.name);
  let r46 = test_txn_abort();
  total = total + 1; failed = failed + report(r46.passed, r46.name);
  let r47 = test_txn_add_op();
  total = total + 1; failed = failed + report(r47.passed, r47.name);
  let r48 = test_txn_full_lifecycle();
  total = total + 1; failed = failed + report(r48.passed, r48.name);
  let r49 = test_txn_abort_lifecycle();
  total = total + 1; failed = failed + report(r49.passed, r49.name);

  // 10. Schema
  let r50 = test_schema_column_def_new();
  total = total + 1; failed = failed + report(r50.passed, r50.name);
  let r51 = test_schema_column_def_optional();
  total = total + 1; failed = failed + report(r51.passed, r51.name);
  let r52 = test_schema_new_and_accessors();
  total = total + 1; failed = failed + report(r52.passed, r52.name);
  let r53 = test_schema_column_index();
  total = total + 1; failed = failed + report(r53.passed, r53.name);
  let r54 = test_index_def_new();
  total = total + 1; failed = failed + report(r54.passed, r54.name);
  let r55 = test_validate_schema_valid();
  total = total + 1; failed = failed + report(r55.passed, r55.name);
  let r56 = test_validate_schema_no_columns();
  total = total + 1; failed = failed + report(r56.passed, r56.name);
  let r57 = test_validate_schema_pk_out_of_range();
  total = total + 1; failed = failed + report(r57.passed, r57.name);
  let r58 = test_validate_column_valid();
  total = total + 1; failed = failed + report(r58.passed, r58.name);
  let r59 = test_validate_index_valid();
  total = total + 1; failed = failed + report(r59.passed, r59.name);
  let r60 = test_validate_index_wrong_table();
  total = total + 1; failed = failed + report(r60.passed, r60.name);

  // 11. Query planner
  let r61 = test_query_new();
  total = total + 1; failed = failed + report(r61.passed, r61.name);
  let r62 = test_query_where_limit_offset();
  total = total + 1; failed = failed + report(r62.passed, r62.name);
  let r63 = test_query_reset();
  total = total + 1; failed = failed + report(r63.passed, r63.name);
  let r64 = test_query_execute_simple();
  total = total + 1; failed = failed + report(r64.passed, r64.name);
  let r65 = test_plan_query_defaults_to_full_scan();
  total = total + 1; failed = failed + report(r65.passed, r65.name);
  let r66 = test_execute_plan_full_scan();
  total = total + 1; failed = failed + report(r66.passed, r66.name);

  // 12. B-tree
  let r67 = test_btree_new();
  total = total + 1; failed = failed + report(r67.passed, r67.name);
  let r68 = test_btree_insert_search();
  total = total + 1; failed = failed + report(r68.passed, r68.name);
  let r69 = test_btree_delete();
  total = total + 1; failed = failed + report(r69.passed, r69.name);
  let r70 = test_btree_min_max();
  total = total + 1; failed = failed + report(r70.passed, r70.name);
  let r71 = test_btree_range_query();
  total = total + 1; failed = failed + report(r71.passed, r71.name);
  let r72 = test_btree_to_vec();
  total = total + 1; failed = failed + report(r72.passed, r72.name);
  let r73 = test_btree_large_insert();
  total = total + 1; failed = failed + report(r73.passed, r73.name);

  // Integration: Engine + Database
  let r74 = test_engine_new();
  total = total + 1; failed = failed + report(r74.passed, r74.name);
  let r75 = test_engine_insert_get();
  total = total + 1; failed = failed + report(r75.passed, r75.name);
  let r76 = test_engine_delete();
  total = total + 1; failed = failed + report(r76.passed, r76.name);
  let r77 = test_engine_update();
  total = total + 1; failed = failed + report(r77.passed, r77.name);
  let r78 = test_engine_recover();
  total = total + 1; failed = failed + report(r78.passed, r78.name);
  let r79 = test_engine_range_query();
  total = total + 1; failed = failed + report(r79.passed, r79.name);
  let r80 = test_engine_flush_wal();
  total = total + 1; failed = failed + report(r80.passed, r80.name);
  let r81 = test_db_open_and_operations();
  total = total + 1; failed = failed + report(r81.passed, r81.name);
  let r82 = test_db_closed_rejects_ops();
  total = total + 1; failed = failed + report(r82.passed, r82.name);
  let r83 = test_db_update_delete();
  total = total + 1; failed = failed + report(r83.passed, r83.name);
  let r84 = test_db_range();
  total = total + 1; failed = failed + report(r84.passed, r84.name);
  let r85 = test_db_recover();
  total = total + 1; failed = failed + report(r85.passed, r85.name);
  let r86 = test_db_query();
  total = total + 1; failed = failed + report(r86.passed, r86.name);

  // FSM + Tuple
  let r87 = test_fsm_new();
  total = total + 1; failed = failed + report(r87.passed, r87.name);
  let r88 = test_fsm_register_and_find();
  total = total + 1; failed = failed + report(r88.passed, r88.name);
  let r89 = test_fsm_record_used();
  total = total + 1; failed = failed + report(r89.passed, r89.name);
  let r90 = test_row_new_and_access();
  total = total + 1; failed = failed + report(r90.passed, r90.name);
  let r91 = test_row_set_column();
  total = total + 1; failed = failed + report(r91.passed, r91.name);
  let r92 = test_tuple_encode_decode();
  total = total + 1; failed = failed + report(r92.passed, r92.name);
  let r93 = test_result_set_ops();
  total = total + 1; failed = failed + report(r93.passed, r93.name);

  let passed = total - failed;
  io.println("");
  io.println("XIOM DB Conformance: " + int_to_str(passed) +
             "/" + int_to_str(total) + " passed" +
             (if failed > 0 { " (" + int_to_str(failed) + " FAILED)" } else { "" }));
  return failed;
}
