// XIOM -- xiom-db Conformance Tests
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Comprehensive conformance suite for xiom-db pure-XIOM components.
// Tests: types (RowId, TableId, PageId), error domain, config validation,
// contract predicates, page/checksum, buffer pool, WAL records, transactions,
// schema validation, query planner, B-tree structure and operations.

module xiom_db_conformance
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

// ===========================================================================
// Helpers
// ===========================================================================

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

// ===========================================================================
// 1. Types: RowId, TableId, PageId construction and validation
// ===========================================================================

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

fn test_page_construction() -> TestResult {
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

fn test_page_is_valid() -> TestResult {
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

fn test_page_is_valid_corrupt() -> TestResult {
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

fn test_page_empty() -> TestResult {
  let rc = run_page_empty();
  if rc == 0 { return assert(true, "page: empty page checksum() == 0"); }
  return assert(false, "page: empty page failed");
}

// ===========================================================================
// 6. Checksum computation
// ===========================================================================

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

fn test_checksum_determinism() -> TestResult {
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

fn test_checksum_different_data() -> TestResult {
  let rc = run_checksum_different_data();
  if rc == 0 { return assert(true, "checksum: different data produces different hash"); }
  return assert(false, "checksum: collision on different data");
}

// CRC32C (Castagnoli) KAT: page_compute_checksum must return the canonical
// check value for "123456789" bytes and 0 for empty input.
fn run_checksum_crc32c_kat() -> Int {
  var kat = Vec[Int].new();
  var c = 49;
  while c <= 57 {
    kat.push(c);
    c = c + 1;
  }
  if page_compute_checksum(&kat) != 3808858755 { return 1; }
  let empty = Vec[Int].new();
  if page_compute_checksum(&empty) != 0 { return 1; }
  return 0;
}

fn test_checksum_crc32c_kat() -> TestResult {
  let rc = run_checksum_crc32c_kat();
  if rc == 0 { return assert(true, "checksum: CRC32C KAT (0xE3069283, empty -> 0)"); }
  return assert(false, "checksum: CRC32C KAT failed");
}

// ===========================================================================
// 7. Buffer pool capacity checks
// ===========================================================================

fn run_buffer_pool_new() -> Int {
  let bp = BufferPool.new(4);
  if bp.capacity != 4 { return 1; }
  if bp.hits != 0 { return 1; }
  if bp.misses != 0 { return 1; }
  return 0;
}

fn test_buffer_pool_new() -> TestResult {
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
  let cached = bp.put(page);
  if !cached { return 1; }
  let found = bp.get(7);
  match found {
    None => return 1,
    Some(p) => { if p.id != 7 { return 1; } }
  }
  if bp.hits != 1 { return 1; }
  return 0;
}

fn test_buffer_pool_put_get() -> TestResult {
  let rc = run_buffer_pool_put_get();
  if rc == 0 { return assert(true, "buffer_pool: put then get returns same page"); }
  return assert(false, "buffer_pool: put/get failed");
}

fn run_buffer_pool_miss() -> Int {
  var bp = BufferPool.new(4);
  let found = bp.get(99);
  match found {
    None => {}
    Some(_) => { return 1; }
  }
  if bp.misses != 1 { return 1; }
  if bp.hits != 0 { return 1; }
  return 0;
}

fn test_buffer_pool_miss() -> TestResult {
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
  let cached = bp.put(page);
  if !cached { return 1; }
  // put is a write path: it does not move the hit/miss ratio...
  var hr = bp.hit_ratio();
  if hr > 0.0 { return 1; }
  // ...a get() hit does.
  let found = bp.get(0);
  match found {
    None => { return 1; }
    Some(p) => { if p.id != 0 { return 1; } }
  }
  if bp.hit_ratio() != 1.0 { return 1; }
  return 0;
}

fn test_buffer_pool_hit_ratio() -> TestResult {
  let rc = run_buffer_pool_hit_ratio();
  if rc == 0 { return assert(true, "buffer_pool: put is write-path, get drives hit_ratio"); }
  return assert(false, "buffer_pool: hit_ratio failed");
}

fn run_buffer_pool_clock() -> Int {
  var bp = BufferPool.new(3);
  var id = 1;
  while id <= 3 {
    var d = Vec[Int].new();
    d.push(id);
    var ck = page_compute_checksum(&d);
    if !bp.put(Page.new(id, d, ck)) { return 1; }
    id = id + 1;
  }
  // All three referenced: the first clock sweep clears the bits, then takes
  // the frame the hand started on (id 1).
  var d4 = Vec[Int].new();
  d4.push(4);
  var ck4 = page_compute_checksum(&d4);
  if !bp.put(Page.new(4, d4, ck4)) { return 1; }
  if bp.evictions != 1 { return 1; }
  let g1 = bp.get(1);
  match g1 { None => {}, Some(_) => { return 1; } }
  let g2 = bp.get(2);
  match g2 { None => { return 1; }, Some(_) => {} }
  let g3 = bp.get(3);
  match g3 { None => { return 1; }, Some(_) => {} }
  let g4 = bp.get(4);
  match g4 { None => { return 1; }, Some(_) => {} }

  // The gets re-referenced 2/3/4; the next sweep clears and then evicts id 2
  // (the hand sits on frame 1 after the first eviction) -- second chance in
  // action: 2 and 3 survived the first eviction round despite being older.
  var d5 = Vec[Int].new();
  d5.push(5);
  var ck5 = page_compute_checksum(&d5);
  if !bp.put(Page.new(5, d5, ck5)) { return 1; }
  if bp.evictions != 2 { return 1; }
  let h2 = bp.get(2);
  match h2 { None => {}, Some(_) => { return 1; } }
  let h3 = bp.get(3);
  match h3 { None => { return 1; }, Some(_) => {} }
  let h4 = bp.get(4);
  match h4 { None => { return 1; }, Some(_) => {} }
  let h5 = bp.get(5);
  match h5 { None => { return 1; }, Some(_) => {} }
  return 0;
}

fn test_buffer_pool_clock() -> TestResult {
  let rc = run_buffer_pool_clock();
  if rc == 0 { return assert(true, "buffer_pool: clock second-chance eviction order"); }
  return assert(false, "buffer_pool: clock eviction failed");
}

fn run_buffer_pool_pin() -> Int {
  var bp = BufferPool.new(2);
  var d1 = Vec[Int].new();
  d1.push(1);
  var d2 = Vec[Int].new();
  d2.push(2);
  if !bp.put(Page.new(1, d1, page_compute_checksum(&d1))) { return 1; }
  if !bp.put(Page.new(2, d2, page_compute_checksum(&d2))) { return 1; }

  if !bp.pin_page(1) { return 1; }
  if !bp.pin_page(1) { return 1; }
  if !bp.pin_page(2) { return 1; }
  if bp.pin_count(1) != 2 { return 1; }

  // Every frame pinned: no victim, the page is not cached, no eviction.
  var d3 = Vec[Int].new();
  d3.push(3);
  if bp.put(Page.new(3, d3, page_compute_checksum(&d3))) { return 1; }
  if bp.rejects != 1 { return 1; }
  if bp.evictions != 0 { return 1; }
  let g3 = bp.get(3);
  match g3 { None => {}, Some(_) => { return 1; } }

  // One unpin on id 1 is not enough (pinned twice).
  if !bp.unpin_page(1) { return 1; }
  if bp.pin_count(1) != 1 { return 1; }
  if bp.put(Page.new(3, d3, page_compute_checksum(&d3))) { return 1; }
  if bp.rejects != 2 { return 1; }

  // Second unpin frees it; the clock reclaims frame 0 (id 1), id 2 stays
  // pinned throughout.
  if !bp.unpin_page(1) { return 1; }
  if bp.pin_count(1) != 0 { return 1; }
  if !bp.put(Page.new(3, d3, page_compute_checksum(&d3))) { return 1; }
  if bp.evictions != 1 { return 1; }
  let h1 = bp.get(1);
  match h1 { None => {}, Some(_) => { return 1; } }
  let h2 = bp.get(2);
  match h2 { None => { return 1; }, Some(_) => {} }
  let h3 = bp.get(3);
  match h3 { None => { return 1; }, Some(_) => {} }
  if bp.pin_count(2) != 1 { return 1; }
  if bp.pin_count(3) != 0 { return 1; }

  // Misuse: pinning/unpinning absent pages fails.
  if bp.pin_page(99) { return 1; }
  if bp.unpin_page(99) { return 1; }
  return 0;
}

fn test_buffer_pool_pin() -> TestResult {
  let rc = run_buffer_pool_pin();
  if rc == 0 { return assert(true, "buffer_pool: pinned frames protected + all-pinned reject"); }
  return assert(false, "buffer_pool: pinning failed");
}

fn run_storage_engine_new() -> Int {
  let cfg = DatabaseConfig.default();
  let eng = StorageEngine.new(cfg);
  return 0;
}

fn test_storage_engine_new() -> TestResult {
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
  let cached = eng.cache_page(page);
  if !cached { return 1; }
  let found = eng.lookup_page(1);
  match found {
    None => return 1,
    Some(p) => { if p.id != 1 { return 1; } }
  }
  return 0;
}

fn test_storage_engine_cache_lookup() -> TestResult {
  let rc = run_storage_engine_cache_lookup();
  if rc == 0 { return assert(true, "storage_engine: cache_page then lookup_page"); }
  return assert(false, "storage_engine: cache/lookup failed");
}

// ===========================================================================
// 8. WAL record types and construction
// ===========================================================================

fn run_wal_entry_new() -> Int {
  let entry = wal_entry_new(WALOpType.InsertOp, 10, 100, 1);
  if entry.key != 10 { return 1; }
  if entry.value != 100 { return 1; }
  if entry.timestamp != 1 { return 1; }
  return 0;
}

fn test_wal_entry_new() -> TestResult {
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

fn test_wal_new_and_append() -> TestResult {
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

fn test_wal_entry_count_filter() -> TestResult {
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

fn test_wal_clear() -> TestResult {
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

fn test_wal_truncate() -> TestResult {
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

fn test_wal_replay_insert() -> TestResult {
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

fn test_wal_replay_delete() -> TestResult {
  let rc = run_wal_replay_delete();
  if rc == 0 { return assert(true, "wal: replay deletes existing key"); }
  return assert(false, "wal: replay delete failed");
}

// ===========================================================================
// 9. Transaction state machine transitions
// ===========================================================================

fn run_txn_new_is_active() -> Int {
  let txn = Transaction.new(1);
  if !txn.is_active() { return 1; }
  return 0;
}

fn test_txn_new_is_active() -> TestResult {
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

fn test_txn_commit() -> TestResult {
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

fn test_txn_abort() -> TestResult {
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

fn test_txn_add_op() -> TestResult {
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

fn test_txn_full_lifecycle() -> TestResult {
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

fn test_txn_abort_lifecycle() -> TestResult {
  let rc = run_txn_abort_lifecycle();
  if rc == 0 { return assert(true, "txn: active->add->abort lifecycle"); }
  return assert(false, "txn: abort lifecycle failed");
}

// ===========================================================================
// 10. Schema validation stubs
// ===========================================================================

fn run_schema_column_def_new() -> Int {
  let col = ColumnDef.new("id", ColumnType.IntType);
  if col.name != "id" { return 1; }
  return 0;
}

fn test_schema_column_def_new() -> TestResult {
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

fn test_schema_column_def_optional() -> TestResult {
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

fn test_schema_new_and_accessors() -> TestResult {
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

fn test_schema_column_index() -> TestResult {
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

fn test_index_def_new() -> TestResult {
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

fn test_validate_schema_valid() -> TestResult {
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

fn test_validate_schema_no_columns() -> TestResult {
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

fn test_validate_schema_pk_out_of_range() -> TestResult {
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

fn test_validate_column_valid() -> TestResult {
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

fn test_validate_index_valid() -> TestResult {
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

fn test_validate_index_wrong_table() -> TestResult {
  let rc = run_validate_index_wrong_table();
  if rc == 0 { return assert(true, "schema_validator: mismatched table rejected"); }
  return assert(false, "schema_validator: wrong table accepted");
}

// ===========================================================================
// 11. Query planner stubs
// ===========================================================================

fn run_query_new() -> Int {
  let q = query_new();
  if query_condition_count(&q) != 0 { return 1; }
  if query_has_limit(&q) { return 1; }
  if query_has_offset(&q) { return 1; }
  return 0;
}

fn test_query_new() -> TestResult {
  let rc = run_query_new();
  if rc == 0 { return assert(true, "query: query_new has zero conditions/limit/offset"); }
  return assert(false, "query: query_new failed");
}

fn run_query_where_limit_offset() -> Int {
  var q = query_new();
  query_where(&mut q, QueryOp.Eq, 42);
  query_where(&mut q, QueryOp.Gt, 0);
  query_limit(&mut q, 10);
  query_offset(&mut q, 5);
  if query_condition_count(&q) != 2 { return 1; }
  if !query_has_limit(&q) { return 1; }
  if !query_has_offset(&q) { return 1; }
  return 0;
}

fn test_query_where_limit_offset() -> TestResult {
  let rc = run_query_where_limit_offset();
  if rc == 0 { return assert(true, "query: where/limit/offset builder"); }
  return assert(false, "query: query builder failed");
}

fn run_query_reset() -> Int {
  var q = query_new();
  query_where(&mut q, QueryOp.Eq, 1);
  query_limit(&mut q, 5);
  query_offset(&mut q, 3);
  query_reset(&mut q);
  if query_condition_count(&q) != 0 { return 1; }
  if query_has_limit(&q) { return 1; }
  if query_has_offset(&q) { return 1; }
  return 0;
}

fn test_query_reset() -> TestResult {
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
  // Phase 0 semantics: conditions filter VALUES, not keys (docs/query-pipeline.md).
  // Values are [100,200,300]; Gte 150 must yield [200,300].
  query_where(&mut q, QueryOp.Gte, 150);
  let results = query_execute(&q, &tree);
  if results.len() != 2 { return 1; }
  return 0;
}

fn test_query_execute_simple() -> TestResult {
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

fn test_plan_query_defaults_to_full_scan() -> TestResult {
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
  query_where(&mut q, QueryOp.Gt, 0);
  let plan = plan_query(&q, &tree);
  let results = execute_plan(&plan, &q, &tree);
  if results.len() != 3 { return 1; }
  return 0;
}

fn test_execute_plan_full_scan() -> TestResult {
  let rc = run_execute_plan_full_scan();
  if rc == 0 { return assert(true, "planner: execute_plan runs full scan"); }
  return assert(false, "planner: execute_plan failed");
}

fn run_query_planner_kinds() -> Int {
  var tree = btree_new(4);
  var i = 1;
  while i <= 20 {
    if !btree_insert(&mut tree, i, i * 3 - 7) { return 1; }
    i = i + 1;
  }

  // No bounds -> full scan, estimate = tree size.
  var q = query_new();
  let p1 = plan_query(&q, &tree);
  match p1.kind {
    PlanKind.FullScan => {}
    PlanKind.IndexRange => { return 1; }
    PlanKind.PointLookup => { return 1; }
  }
  if p1.estimated_rows != 20 { return 1; }

  // Point bounds -> point lookup with a 1-row estimate.
  var qp = query_new();
  query_key_range(&mut qp, 7, 7);
  if !query_has_bounds(&qp) { return 1; }
  let p2 = plan_query(&qp, &tree);
  match p2.kind {
    PlanKind.PointLookup => {}
    PlanKind.FullScan => { return 1; }
    PlanKind.IndexRange => { return 1; }
  }
  if p2.estimated_rows != 1 { return 1; }
  if p2.low != 7 { return 1; }
  if p2.high != 7 { return 1; }
  query_where(&mut qp, QueryOp.Gt, 0);
  let r2 = execute_plan(&p2, &qp, &tree);
  if r2.len() != 1 { return 1; }
  if r2[0] != 14 { return 1; } // key 7 -> 7*3-7 = 14

  // Range bounds -> index range, estimate = clamped width.
  var qr = query_new();
  query_key_range(&mut qr, 3, 9);
  let p3 = plan_query(&qr, &tree);
  match p3.kind {
    PlanKind.IndexRange => {}
    PlanKind.FullScan => { return 1; }
    PlanKind.PointLookup => { return 1; }
  }
  if p3.estimated_rows != 7 { return 1; }
  query_where(&mut qr, QueryOp.Gte, 10);
  let r3 = execute_plan(&p3, &qr, &tree);
  // keys 3..9 -> values 2,5,8,11,14,17,20; >= 10 -> 11,14,17,20
  if r3.len() != 4 { return 1; }
  if r3[0] != 11 { return 1; }

  // Width clamp: estimate never exceeds the tree size.
  var qc = query_new();
  query_key_range(&mut qc, -100, 100);
  let p4 = plan_query(&qc, &tree);
  if p4.estimated_rows != 20 { return 1; }

  // Reset clears the bounds again.
  query_reset(&mut qr);
  if query_has_bounds(&qr) { return 1; }
  let p5 = plan_query(&qr, &tree);
  match p5.kind {
    PlanKind.FullScan => {}
    PlanKind.IndexRange => { return 1; }
    PlanKind.PointLookup => { return 1; }
  }
  return 0;
}

fn test_query_planner_kinds() -> TestResult {
  let rc = run_query_planner_kinds();
  if rc == 0 { return assert(true, "planner: point/range/full selection + clamped estimate"); }
  return assert(false, "planner: plan kinds failed");
}

fn query_model_condition(value: Int, op: QueryOp, target: Int) -> Bool {
  match op {
    QueryOp.Eq => value == target,
    QueryOp.Neq => value != target,
    QueryOp.Lt => value < target,
    QueryOp.Lte => value <= target,
    QueryOp.Gt => value > target,
    QueryOp.Gte => value >= target,
  }
}

fn run_query_planner_property() -> Int {
  var tree = btree_new(4);
  var i = 1;
  while i <= 64 {
    if !btree_insert(&mut tree, i, i * 3 - 7) { return 1; }
    i = i + 1;
  }

  var state = 4242;
  var it = 0;
  while it < 200 {
    state = (state * 1103515245 + 12345) % 2147483648;
    let mode = (state / 65536) % 3; // 0 full, 1 range, 2 point
    var q = query_new();
    var lo = -10;
    var hi = 80;
    if mode == 1 {
      lo = ((state / 65536) % 100) - 10;
      state = (state * 1103515245 + 12345) % 2147483648;
      hi = lo + ((state / 65536) % 40);
      query_key_range(&mut q, lo, hi);
    } elif mode == 2 {
      lo = ((state / 65536) % 100) - 10;
      hi = lo;
      query_key_range(&mut q, lo, hi);
    }

    state = (state * 1103515245 + 12345) % 2147483648;
    let has_cond = (state / 65536) % 2 == 0;
    var op = QueryOp.Gte;
    var target = 0;
    if has_cond {
      state = (state * 1103515245 + 12345) % 2147483648;
      let opk = (state / 65536) % 6;
      match opk {
        0 => { op = QueryOp.Eq; }
        1 => { op = QueryOp.Neq; }
        2 => { op = QueryOp.Lt; }
        3 => { op = QueryOp.Lte; }
        4 => { op = QueryOp.Gt; }
        _ => { op = QueryOp.Gte; }
      }
      state = (state * 1103515245 + 12345) % 2147483648;
      target = ((state / 65536) % 160) - 20;
      query_where(&mut q, op, target);
    }

    state = (state * 1103515245 + 12345) % 2147483648;
    let off = (state / 65536) % 5;
    query_offset(&mut q, off);
    state = (state * 1103515245 + 12345) % 2147483648;
    let lim = (state / 65536) % 8; // 0 = no limit
    if lim > 0 { query_limit(&mut q, lim); }

    // Brute-force model: key range -> values -> conditions -> offset -> limit.
    var want = Vec[Int].new();
    var count = 0;
    var klo = lo;
    var khi = hi;
    if mode == 0 {
      klo = 1;
      khi = 64;
    }
    var k = klo;
    while k <= khi {
      if k >= 1 && k <= 64 {
        let v = k * 3 - 7;
        var keep = true;
        if has_cond { keep = query_model_condition(v, op, target); }
        if keep {
          if count >= off { want.push(v); }
          count = count + 1;
        }
      }
      k = k + 1;
    }
    if lim > 0 && want.len() > lim {
      var cut = Vec[Int].new();
      var j = 0;
      while j < lim {
        cut.push(want[j]);
        j = j + 1;
      }
      want = cut;
    }

    let plan = plan_query(&q, &tree);
    let got = execute_plan(&plan, &q, &tree);
    if got.len() != want.len() {
      io.println("query planner property: len got=" + convert.int_to_string(got.len())
        + " want=" + convert.int_to_string(want.len()) + " it=" + convert.int_to_string(it));
      return 1;
    }
    var vi = 0;
    while vi < got.len() {
      if got[vi] != want[vi] {
        io.println("query planner property: value mismatch it=" + convert.int_to_string(it));
        return 2;
      }
      vi = vi + 1;
    }
    it = it + 1;
  }
  return 0;
}

fn test_query_planner_property() -> TestResult {
  let rc = run_query_planner_property();
  if rc == 0 { return assert(true, "planner: property vs brute force (200 seeded cases)"); }
  return assert(false, "planner: property failed");
}

// ===========================================================================
// 12. B-tree node structure and operations
// ===========================================================================

fn run_btree_new() -> Int {
  let tree = btree_new(4);
  if btree_size(&tree) != 0 { return 1; }
  return 0;
}

fn test_btree_new() -> TestResult {
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

fn test_btree_insert_search() -> TestResult {
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

fn test_btree_delete() -> TestResult {
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

fn test_btree_min_max() -> TestResult {
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

fn test_btree_range_query() -> TestResult {
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

fn test_btree_to_vec() -> TestResult {
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

fn test_btree_large_insert() -> TestResult {
  let rc = run_btree_large_insert();
  if rc == 0 { return assert(true, "btree: 100 inserts with splits, all searchable"); }
  return assert(false, "btree: large insert failed");
}

// ===========================================================================
// B-tree churn: randomized insert/delete/search against a reference model.
// Regression lock for the delete/underflow fixes (child-index contract of
// fill_child, borrow_from_left leaf children, min_keys for odd orders).
// Extended soak lives in tests/probes/probe_btree_churn.xi.
// ===========================================================================

fn churn_rand(state: &mut Int) -> Int {
  *state = (*state * 1103515245 + 12345) % 2147483648;
  return *state;
}

fn run_btree_churn(order: Int, ops: Int, n: Int, seed: Int) -> Int {
  var tree = btree_new(order);
  var present = Vec[Int].new();
  var values = Vec[Int].new();
  var i = 0;
  while i < n {
    present.push(0);
    values.push(0);
    i = i + 1;
  }
  var state = seed;
  var step = 0;
  while step < ops {
    let key = churn_rand(&mut state) % n;
    let action = churn_rand(&mut state) % 10;
    if action < 4 {
      let want = present[key] == 0;
      let got = btree_insert(&mut tree, key, key * 7 + 1);
      if got != want { return 1; }
      if want {
        present[key] = 1;
        values[key] = key * 7 + 1;
      }
    } elif action < 7 {
      let want = present[key] == 1;
      let got = btree_delete(&mut tree, key);
      if got != want { return 2; }
      if want { present[key] = 0; }
    } else {
      let got = btree_search(&tree, key);
      if present[key] == 1 {
        match got {
          None => { return 3; }
          Some(v) => { if v != values[key] { return 4; } }
        }
      } else {
        match got {
          Some(_) => { return 5; }
          None => {}
        }
      }
    }
    step = step + 1;
  }

  var expected = 0;
  var k = 0;
  while k < n {
    if present[k] == 1 { expected = expected + 1; }
    k = k + 1;
  }
  if btree_size(&tree) != expected { return 6; }
  let vals = btree_to_vec(&tree);
  if vals.len() != expected { return 7; }
  var idx = 0;
  k = 0;
  while k < n {
    if present[k] == 1 {
      if vals[idx] != values[k] { return 8; }
      idx = idx + 1;
    }
    k = k + 1;
  }
  return 0;
}

fn test_btree_churn_order4() -> TestResult {
  let rc = run_btree_churn(4, 400, 128, 12345);
  if rc == 0 { return assert(true, "btree: churn order 4 vs model (insert/delete/search)"); }
  return assert(false, "btree: churn order 4 failed");
}

fn test_btree_churn_order5() -> TestResult {
  let rc = run_btree_churn(5, 400, 128, 2026);
  if rc == 0 { return assert(true, "btree: churn order 5 vs model (odd-order min-keys)"); }
  return assert(false, "btree: churn order 5 failed");
}

// Order 3 is the min_keys == 0 regime (empty pass-through chains): this is
// the exact reproducer of the old out-of-bounds predecessor read (xiom.btree
// SPEC 2.3; first divergence was op 67 pre-fix).
fn test_btree_churn_order3() -> TestResult {
  let rc = run_btree_churn(3, 2000, 16, 777);
  if rc == 0 { return assert(true, "btree: churn order 3 vs model (min_keys 0 / empty chains)"); }
  return assert(false, "btree: churn order 3 failed");
}

// ===========================================================================
// Integration: Engine + Database facade
// ===========================================================================

fn run_engine_new() -> Int {
  let eng = engine_new(4);
  if engine_size(&eng) != 0 { return 1; }
  if engine_wal_size(&eng) != 0 { return 1; }
  return 0;
}

fn test_engine_new() -> TestResult {
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

fn test_engine_insert_get() -> TestResult {
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

fn test_engine_delete() -> TestResult {
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

fn test_engine_update() -> TestResult {
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

fn test_engine_recover() -> TestResult {
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

fn test_engine_range_query() -> TestResult {
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

fn test_engine_flush_wal() -> TestResult {
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
  if db_size(&db) != 1 { return 1; }
  return 0;
}

fn test_db_open_and_operations() -> TestResult {
  let rc = run_db_open_and_operations();
  if rc == 0 { return assert(true, "database: open/insert/get/size workflow"); }
  return assert(false, "database: workflow failed");
}

fn run_db_closed_rejects_ops() -> Int {
  var db = db_open(4);
  db_insert(&mut db, 1, 100);
  db_close(&mut db);
  let v = db_get(&db, 1);
  match v { Some(_) => return 1; None => {} }
  let ok = db_insert(&mut db, 2, 200);
  if ok { return 1; }
  return 0;
}

fn test_db_closed_rejects_ops() -> TestResult {
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

fn test_db_update_delete() -> TestResult {
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

fn test_db_range() -> TestResult {
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
  if db_size(&db) != 2 { return 1; }
  return 0;
}

fn test_db_recover() -> TestResult {
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
  // Value semantics (docs/query-pipeline.md): values are [100,200,300];
  // Gte 250 must yield exactly [300] (key semantics would yield none).
  query_where(&mut q, QueryOp.Gte, 250);
  let results = db_query(&db, &q);
  if results.len() != 1 { return 1; }
  return 0;
}

fn test_db_query() -> TestResult {
  let rc = run_db_query();
  if rc == 0 { return assert(true, "database: db_query applies filter"); }
  return assert(false, "database: db_query failed");
}

// ===========================================================================
// Free space map scaffold tests
// ===========================================================================

fn run_fsm_new() -> Int {
  let fsm = free_space_map_new();
  if fsm_page_count(&fsm) != 0 { return 1; }
  return 0;
}

fn test_fsm_new() -> TestResult {
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

fn test_fsm_register_and_find() -> TestResult {
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

fn test_fsm_record_used() -> TestResult {
  let rc = run_fsm_record_used();
  if rc == 0 { return assert(true, "fsm: record_used reduces free bytes"); }
  return assert(false, "fsm: record_used failed");
}

// Best-fit placement: tightest page wins; lowest id breaks ties.
fn run_fsm_best_fit() -> Int {
  var fsm = free_space_map_new();
  let p0 = fsm_register_page(&mut fsm, 100);
  fsm_register_page(&mut fsm, 1000);
  let p2 = fsm_register_page(&mut fsm, 500);
  let f1 = fsm_find_page(&fsm, 60);
  match f1 { None => return 1, Some(g) => { if g.value != 0 { return 1; } } }
  if !fsm_record_used(&mut fsm, &p0, 100) { return 1; }
  let f2 = fsm_find_page(&fsm, 60);
  match f2 { None => return 1, Some(g) => { if g.value != 2 { return 1; } } }
  // tie: a second 500-free page must not displace the lower id
  fsm_register_page(&mut fsm, 500);
  let f3 = fsm_find_page(&fsm, 60);
  match f3 { None => return 1, Some(g) => { if g.value != 2 { return 1; } } }
  if !fsm_validate(&fsm) { return 1; }
  return 0;
}

fn test_fsm_best_fit() -> TestResult {
  let rc = run_fsm_best_fit();
  if rc == 0 { return assert(true, "fsm: best-fit placement (tightest, lowest id)"); }
  return assert(false, "fsm: best-fit failed");
}

// Clamping and release invariants: over-use clamps at 0 and reports false;
// negative args report false; release clamps at capacity.
fn run_fsm_clamps_release() -> Int {
  var fsm = free_space_map_new();
  let p = fsm_register_page(&mut fsm, 100);
  if fsm_record_used(&mut fsm, &p, 150) { return 1; }
  if fsm_free_bytes(&fsm, &p) != 0 { return 1; }
  if fsm_record_used(&mut fsm, &p, -1) { return 1; }
  if !fsm_record_free(&mut fsm, &p, 40) { return 1; }
  if fsm_free_bytes(&fsm, &p) != 40 { return 1; }
  if !fsm_record_free(&mut fsm, &p, 1000) { return 1; }
  if fsm_free_bytes(&fsm, &p) != 100 { return 1; }
  if !fsm_validate(&fsm) { return 1; }
  return 0;
}

fn test_fsm_clamps_release() -> TestResult {
  let rc = run_fsm_clamps_release();
  if rc == 0 { return assert(true, "fsm: clamps (over-use, negative, capacity)"); }
  return assert(false, "fsm: clamps/release failed");
}

// ===========================================================================
// Tuple codec tests
// ===========================================================================

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

fn test_row_new_and_access() -> TestResult {
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

fn test_row_set_column() -> TestResult {
  let rc = run_row_set_column();
  if rc == 0 { return assert(true, "tuple: Row.set_column updates in place"); }
  return assert(false, "tuple: set_column failed");
}

fn run_tuple_encode_decode() -> Int {
  var data = Vec[Int].new();
  data.push(42);
  data.push(99);
  let row = Row.new(7, data);
  let enc = tuple_encode_checked(&row);
  var encoded = Vec[Int].new();
  match enc {
    Err(_) => return 1,
    Ok(buf) => {
      // C-ORBIT-01 workaround: rebind the cross-module generic Result payload
      // through an explicitly typed local (docs/repro/ok-method-receiver/).
      let bytes: Vec[Int] = buf;
      encoded = bytes;
    }
  }
  let r = tuple_decode(&encoded);
  match r {
    Err(_) => return 1,
    Ok(decoded) => {
      let d: Row = decoded;
      if d.id != 7 { return 1; }
      if d.column_count() != 2 { return 1; }
      let c0 = d.get_column(0);
      match c0 { None => return 1; Some(v) => { if v != 42 { return 1; } } }
      let c1 = d.get_column(1);
      match c1 { None => return 1; Some(v) => { if v != 99 { return 1; } } }
    }
  }
  return 0;
}

fn test_tuple_encode_decode() -> TestResult {
  let rc = run_tuple_encode_decode();
  if rc == 0 { return assert(true, "tuple: encode then decode roundtrip"); }
  return assert(false, "tuple: encode/decode failed");
}

// v1 KAT: Row(1, [1, 2]) -> exact byte sequence.
fn run_tuple_codec_kat() -> Int {
  var data = Vec[Int].new();
  data.push(1);
  data.push(2);
  let row = Row.new(1, data);
  let enc = tuple_encode_checked(&row);
  match enc {
    Err(_) => return 1,
    Ok(buf) => {
      let bytes: Vec[Int] = buf;
      // 3 header bytes + 3 fields x (1 type + 8 LE)
      if bytes.len() != 30 { return 1; } // 3 + 9*3
      if bytes[0] != 0xDB { return 1; }
      if bytes[1] != 0x01 { return 1; }
      if bytes[2] != 3 { return 1; }
      // field 0 (id=1): type 0x01 then 01 00 00 00 00 00 00 00
      if bytes[3] != 0x01 { return 1; }
      if bytes[4] != 1 { return 1; }
      var k = 5;
      while k < 12 { if bytes[k] != 0 { return 1; } k = k + 1; }
      // field 1 (1)
      if bytes[12] != 0x01 { return 1; }
      if bytes[13] != 1 { return 1; }
      k = 14;
      while k < 21 { if bytes[k] != 0 { return 1; } k = k + 1; }
      // field 2 (2)
      if bytes[21] != 0x01 { return 1; }
      if bytes[22] != 2 { return 1; }
      k = 23;
      while k < 30 { if bytes[k] != 0 { return 1; } k = k + 1; }
    }
  }
  return 0;
}

fn test_tuple_codec_kat() -> TestResult {
  let rc = run_tuple_codec_kat();
  if rc == 0 { return assert(true, "tuple: codec v1 byte KAT (magic/version/LE fields)"); }
  return assert(false, "tuple: codec KAT failed");
}

// Roundtrip extremes: negatives and i64 boundaries must survive the LE codec.
fn run_tuple_codec_extremes() -> Int {
  var data = Vec[Int].new();
  data.push(-1);
  data.push(-9223372036854775807 - 1);
  data.push(9223372036854775807);
  data.push(0);
  let row = Row.new(-5, data);
  let enc = tuple_encode_checked(&row);
  match enc {
    Err(_) => return 1,
    Ok(buf) => {
      let bytes: Vec[Int] = buf;
      if !tuple_fits_page(&row, 4096) { return 1; }
      let r = tuple_decode(&bytes);
      match r {
        Err(_) => return 1,
        Ok(decoded) => {
          let d: Row = decoded;
          if d.id != -5 { return 1; }
          if d.column_count() != 4 { return 1; }
          let c0 = d.get_column(0);
          match c0 { None => return 1; Some(v) => { if v != -1 { return 1; } } }
          let c1 = d.get_column(1);
          match c1 { None => return 1; Some(v) => { if v != -9223372036854775807 - 1 { return 1; } } }
          let c2 = d.get_column(2);
          match c2 { None => return 1; Some(v) => { if v != 9223372036854775807 { return 1; } } }
          let c3 = d.get_column(3);
          match c3 { None => return 1; Some(v) => { if v != 0 { return 1; } } }
        }
      }
    }
  }
  return 0;
}

fn test_tuple_codec_extremes() -> TestResult {
  let rc = run_tuple_codec_extremes();
  if rc == 0 { return assert(true, "tuple: codec extremes (negatives, i64 bounds)"); }
  return assert(false, "tuple: codec extremes failed");
}

// Malformed buffers must be rejected, never partially decoded.
fn run_tuple_codec_rejects() -> Int {
  // bad magic
  var bad1 = Vec[Int].new();
  var i = 0;
  while i < 12 { bad1.push(0); i = i + 1; }
  let d1 = tuple_decode(&bad1);
  match d1 { Ok(_) => { return 1; } Err(_) => {} }
  // truncated valid header
  var bad2 = Vec[Int].new();
  bad2.push(0xDB);
  bad2.push(0x01);
  bad2.push(3);
  let d2 = tuple_decode(&bad2);
  match d2 { Ok(_) => { return 2; } Err(_) => {} }
  // trailing byte after an otherwise valid record
  var data = Vec[Int].new();
  data.push(1);
  let row = Row.new(1, data);
  let enc = tuple_encode_checked(&row);
  match enc {
    Err(_) => { return 3; }
    Ok(buf) => {
      let bytes: Vec[Int] = buf;
      var bad3 = Vec[Int].new();
      i = 0;
      while i < bytes.len() { bad3.push(bytes[i]); i = i + 1; }
      bad3.push(0);
      let d3 = tuple_decode(&bad3);
      match d3 { Ok(_) => { return 4; } Err(_) => {} }
    }
  }
  // empty buffer
  let empty = Vec[Int].new();
  let d4 = tuple_decode(&empty);
  match d4 { Ok(_) => { return 5; } Err(_) => {} }
  // too many fields -> checked encode refuses
  var wide = Vec[Int].new();
  i = 0;
  while i < 300 { wide.push(i); i = i + 1; }
  let wide_row = Row.new(0, wide);
  let enc2 = tuple_encode_checked(&wide_row);
  match enc2 { Ok(_) => { return 6; } Err(_) => {} }
  return 0;
}

fn test_tuple_codec_rejects() -> TestResult {
  let rc = run_tuple_codec_rejects();
  if rc == 0 { return assert(true, "tuple: codec rejects malformed/oversized buffers"); }
  return assert(false, "tuple: codec malformed rejection failed");
}

// ===========================================================================
// Tuple codec v2 (M5.1): typed values (null/int/float/text/blob). The v1
// codec above stays frozen; v2 buffers are a separate version byte.
// ===========================================================================

// KAT: TypedRow(1, [VInt(-2), VText("hi"), VFloat(1.5), VBlob([1,2]), VNull])
// in exact bytes. Offsets: 0..2 container, 3..11 id VInt, 12..20 VInt(-2),
// 21..27 VText("hi"), 28..36 VFloat(1.5), 37..43 VBlob([1,2]), 44 VNull.
fn run_tuple2_kat() -> Int {
  var vals = Vec[TValue].new();
  vals.push(TValue.VInt(-2));
  vals.push(TValue.VText("hi"));
  vals.push(TValue.VFloat(1.5));
  var bl = Vec[Int].new();
  bl.push(1);
  bl.push(2);
  vals.push(TValue.VBlob(bl));
  vals.push(TValue.VNull);

  // 3 + 9 (id) + 9 + (5+2) + 9 + (5+2) + 1 = 45
  if tuple2_encoded_len(&vals) != 45 { return 1; }
  let enc = tuple2_encode_row_checked(1, &vals);
  match enc {
    Err(_) => { return 2; }
    Ok(buf) => {
      let bytes: Vec[Int] = buf;
      if bytes.len() != 45 { return 3; }
      if bytes[0] != 0xDB { return 4; }
      if bytes[1] != 0x02 { return 5; }
      if bytes[2] != 6 { return 6; }        // id + 5 values
      if bytes[3] != 0x01 { return 7; }     // id tag VInt
      if bytes[4] != 1 { return 8; }
      if bytes[5] != 0 { return 9; }
      if bytes[11] != 0 { return 10; }
      if bytes[12] != 0x01 { return 11; }   // VInt(-2)
      if bytes[13] != 0xFE { return 12; }
      if bytes[14] != 0xFF { return 13; }
      if bytes[20] != 0xFF { return 14; }
      if bytes[21] != 0x03 { return 15; }   // VText("hi")
      if bytes[22] != 2 { return 16; }      // u32 len
      if bytes[23] != 0 { return 17; }
      if bytes[25] != 0 { return 18; }
      if bytes[26] != 104 { return 19; }    // 'h'
      if bytes[27] != 105 { return 20; }    // 'i'
      if bytes[28] != 0x02 { return 21; }   // VFloat(1.5)
      if bytes[29] != 0 { return 22; }
      if bytes[34] != 0 { return 23; }
      if bytes[35] != 0xF8 { return 24; }   // 1.5 = 0x3FF8...
      if bytes[36] != 0x3F { return 25; }
      if bytes[37] != 0x04 { return 26; }   // VBlob([1,2])
      if bytes[38] != 2 { return 27; }
      if bytes[41] != 0 { return 28; }
      if bytes[42] != 1 { return 29; }
      if bytes[43] != 2 { return 30; }
      if bytes[44] != 0x00 { return 31; }   // VNull
    }
  }
  return 0;
}

fn test_tuple2_kat() -> TestResult {
  let rc = run_tuple2_kat();
  if rc == 0 { return assert(true, "tuple v2: byte KAT (tags + LE payloads + text/blob lengths)"); }
  return assert(false, "tuple v2: KAT failed rc=" + int_to_str(rc));
}

// Roundtrip every kind, including i64 extremes, multibyte UTF-8, empty
// text/blob, a NaN bit pattern (handcrafted) and a bit-exact re-encode.
fn run_tuple2_roundtrip() -> Int {
  var vals = Vec[TValue].new();
  vals.push(TValue.VNull);
  vals.push(TValue.VInt(-9223372036854775807 - 1));
  vals.push(TValue.VInt(9223372036854775807));
  vals.push(TValue.VFloat(-2.25));
  vals.push(TValue.VText(""));
  vals.push(TValue.VText("h\xC3\xA9llo \xE2\x86\x92"));
  var empty_blob = Vec[Int].new();
  vals.push(TValue.VBlob(empty_blob));
  var raw = Vec[Int].new();
  raw.push(0);
  raw.push(255);
  raw.push(128);
  vals.push(TValue.VBlob(raw));

  if !tuple2_fits_page(&vals, 4096) { return 1; }
  if tuple2_fits_page(&vals, 16) { return 2; }
  let enc = tuple2_encode_row_checked(-7, &vals);
  match enc {
    Err(_) => { return 3; }
    Ok(buf) => {
      let bytes: Vec[Int] = buf;
      if bytes.len() != tuple2_encoded_len(&vals) { return 4; }
      let dec = tuple2_decode_row(&bytes);
      match dec {
        Err(_) => { return 5; }
        Ok(row) => {
          let r: TypedRow = row;
          if r.id != -7 { return 6; }
          if r.values.len() != 8 { return 7; }
          if !tuple2_is_null(r.values[0]) { return 8; }
          let i1 = tuple2_int_value(r.values[1]);
          match i1 { None => { return 9; } Some(x) => { if x != -9223372036854775807 - 1 { return 10; } } }
          let i2 = tuple2_int_value(r.values[2]);
          match i2 { None => { return 11; } Some(x) => { if x != 9223372036854775807 { return 12; } } }
          let f1 = tuple2_float_value(r.values[3]);
          match f1 { None => { return 13; } Some(x) => { if x != -2.25 { return 14; } } }
          let t1 = tuple2_text_value(r.values[4]);
          match t1 { None => { return 15; } Some(x) => { if x != "" { return 16; } } }
          let t2 = tuple2_text_value(r.values[5]);
          match t2 { None => { return 17; } Some(x) => { if x != "h\xC3\xA9llo \xE2\x86\x92" { return 18; } } }
          let b1 = tuple2_blob_value(r.values[6]);
          match b1 { None => { return 19; } Some(x) => { if x.len() != 0 { return 20; } } }
          let b2 = tuple2_blob_value(r.values[7]);
          match b2 {
            None => { return 21; }
            Some(x) => {
              if x.len() != 3 { return 22; }
              if x[0] != 0 { return 23; }
              if x[1] != 255 { return 24; }
              if x[2] != 128 { return 25; }
            }
          }
        }
      }
    }
  }

  // NaN bit pattern (0x7FF8000000000000 LE) must decode and re-encode
  // byte-exactly: idx 3 tag VFloat, idx 4..11 NaN bits.
  var nan_row = Vec[Int].new();
  nan_row.push(0xDB);
  nan_row.push(0x02);
  nan_row.push(0x02);
  nan_row.push(0x01);
  nan_row.push(1);
  var z = 0;
  while z < 7 { nan_row.push(0); z = z + 1; }
  nan_row.push(0x02);
  nan_row.push(0x00);
  nan_row.push(0x00);
  nan_row.push(0x00);
  nan_row.push(0x00);
  nan_row.push(0x00);
  nan_row.push(0x00);
  nan_row.push(0xF8);
  nan_row.push(0x7F);
  let nd = tuple2_decode_row(&nan_row);
  match nd {
    Err(_) => { return 26; }
    Ok(row2) => {
      let r2: TypedRow = row2;
      if r2.values.len() != 1 { return 27; }
      let fv = tuple2_float_value(r2.values[0]);
      match fv {
        None => { return 28; }
        Some(f) => { if f == f { return 29; } } // NaN != NaN
      }
      // Re-encode through the typed path and compare bytes (bit-exact).
      var re = tuple2_encode_row_checked(1, &r2.values);
      match re {
        Err(_) => { return 30; }
        Ok(buf3) => {
          let b3: Vec[Int] = buf3;
          if b3.len() != nan_row.len() { return 31; }
          var k = 0;
          while k < b3.len() {
            if b3[k] != nan_row[k] { return 32; }
            k = k + 1;
          }
        }
      }
    }
  }
  return 0;
}

fn test_tuple2_roundtrip() -> TestResult {
  let rc = run_tuple2_roundtrip();
  if rc == 0 { return assert(true, "tuple v2: roundtrip all kinds (extremes, UTF-8, NaN bit-exact)"); }
  return assert(false, "tuple v2: roundtrip failed rc=" + int_to_str(rc));
}

// Corrupt / cross-version / oversized inputs must be rejected, never
// partially decoded.
fn run_tuple2_rejects() -> Int {
  // Valid v2 baseline to corrupt.
  var vals = Vec[TValue].new();
  vals.push(TValue.VInt(5));
  vals.push(TValue.VText("ab"));
  let enc = tuple2_encode_row_checked(3, &vals);
  match enc {
    Err(_) => { return 1; }
    Ok(buf) => {
      let v2: Vec[Int] = buf;

      // v1 buffer must not decode as v2 (version discriminator).
      var data1 = Vec[Int].new();
      data1.push(1);
      let row1 = Row.new(1, data1);
      let v1enc = tuple_encode_checked(&row1);
      match v1enc {
        Err(_) => { return 2; }
        Ok(v1buf) => {
          let b1: Vec[Int] = v1buf;
          let d1 = tuple2_decode_row(&b1);
          match d1 { Ok(_) => { return 3; } Err(_) => {} }
          // ... and the v2 buffer must not decode as v1.
          let d2 = tuple_decode(&v2);
          match d2 { Ok(_) => { return 4; } Err(_) => {} }
        }
      }

      // Truncated by one byte (exact-length rule).
      var trunc = Vec[Int].new();
      var i = 0;
      while i < v2.len() - 1 { trunc.push(v2[i]); i = i + 1; }
      let d3 = tuple2_decode_row(&trunc);
      match d3 { Ok(_) => { return 5; } Err(_) => {} }

      // Trailing byte.
      var trail = Vec[Int].new();
      i = 0;
      while i < v2.len() { trail.push(v2[i]); i = i + 1; }
      trail.push(0);
      let d4 = tuple2_decode_row(&trail);
      match d4 { Ok(_) => { return 6; } Err(_) => {} }

      // Wrong magic.
      var magic = Vec[Int].new();
      i = 0;
      while i < v2.len() { magic.push(v2[i]); i = i + 1; }
      magic[0] = 0x00;
      let d5 = tuple2_decode_row(&magic);
      match d5 { Ok(_) => { return 7; } Err(_) => {} }

      // Unknown tag in field 1.
      var unk = Vec[Int].new();
      i = 0;
      while i < v2.len() { unk.push(v2[i]); i = i + 1; }
      unk[12] = 0x7F;
      let d6 = tuple2_decode_row(&unk);
      match d6 { Ok(_) => { return 8; } Err(_) => {} }

      // Field 0 not VInt: flip the id tag to VText with a 1-byte body.
      var f0 = Vec[Int].new();
      f0.push(0xDB);
      f0.push(0x02);
      f0.push(0x01);
      f0.push(0x03);
      f0.push(1);
      f0.push(0);
      f0.push(0);
      f0.push(0);
      f0.push(65);
      let d7 = tuple2_decode_row(&f0);
      match d7 { Ok(_) => { return 9; } Err(_) => {} }

      // Text length field larger than the remaining buffer.
      var short = Vec[Int].new();
      short.push(0xDB);
      short.push(0x02);
      short.push(0x02);
      short.push(0x01);
      var q = 0;
      while q < 8 { short.push(0); q = q + 1; }
      short.push(0x03);
      short.push(9); // len 9, only 2 bytes below
      short.push(0);
      short.push(0);
      short.push(0);
      short.push(104);
      short.push(105);
      let d8 = tuple2_decode_row(&short);
      match d8 { Ok(_) => { return 10; } Err(_) => {} }

      // A non-byte element anywhere in the buffer (999) is corruption.
      var wide = Vec[Int].new();
      i = 0;
      while i < v2.len() { wide.push(v2[i]); i = i + 1; }
      wide[6] = 999;
      let d9 = tuple2_decode_row(&wide);
      match d9 { Ok(_) => { return 11; } Err(_) => {} }
    }
  }

  // Encode-side guards: 256 fields refuse; blob byte > 255 refuses.
  var many = Vec[TValue].new();
  var j = 0;
  while j < 255 { many.push(TValue.VNull); j = j + 1; }
  let e1 = tuple2_encode_row_checked(1, &many);
  match e1 { Ok(_) => { return 12; } Err(_) => {} }

  var bad_blob_vals = Vec[TValue].new();
  var bb = Vec[Int].new();
  bb.push(300);
  bad_blob_vals.push(TValue.VBlob(bb));
  let e2 = tuple2_encode_row_checked(1, &bad_blob_vals);
  match e2 { Ok(_) => { return 13; } Err(_) => {} }

  return 0;
}

fn test_tuple2_rejects() -> TestResult {
  let rc = run_tuple2_rejects();
  if rc == 0 { return assert(true, "tuple v2: rejects corruption + cross-version + oversized"); }
  return assert(false, "tuple v2: rejects failed rc=" + int_to_str(rc));
}

// Kinds, per-value lengths and the page budget boundary.
fn run_tuple2_budget() -> Int {
  if tuple2_kind(TValue.VNull) != 0x00 { return 1; }
  if tuple2_kind(TValue.VInt(1)) != 0x01 { return 2; }
  if tuple2_kind(TValue.VFloat(1.0)) != 0x02 { return 3; }
  if tuple2_kind(TValue.VText("a")) != 0x03 { return 4; }
  var one = Vec[Int].new();
  one.push(9);
  if tuple2_kind(TValue.VBlob(one)) != 0x04 { return 5; }

  if tuple2_value_len(TValue.VNull) != 1 { return 6; }
  if tuple2_value_len(TValue.VInt(0)) != 9 { return 7; }
  if tuple2_value_len(TValue.VFloat(0.0)) != 9 { return 8; }
  if tuple2_value_len(TValue.VText("abc")) != 8 { return 9; }
  if tuple2_value_len(TValue.VBlob(one)) != 6 { return 10; }

  // One 4000-byte text: row len = 3 + 9 + 5 + 4000 = 4017. Boundary only.
  var s = "";
  var i = 0;
  while i < 4000 { s = s + "a"; i = i + 1; }
  var vals = Vec[TValue].new();
  vals.push(TValue.VText(s));
  if tuple2_encoded_len(&vals) != 4017 { return 11; }
  if !tuple2_fits_page(&vals, 4017) { return 12; }
  if tuple2_fits_page(&vals, 4016) { return 13; }
  if tuple2_fits_page(&vals, -1) { return 14; }
  return 0;
}

fn test_tuple2_budget() -> TestResult {
  let rc = run_tuple2_budget();
  if rc == 0 { return assert(true, "tuple v2: kinds + per-value lengths + page budget boundary"); }
  return assert(false, "tuple v2: budget failed rc=" + int_to_str(rc));
}

// ===========================================================================
// Schema-driven rows (M5.2): ColumnType <-> TValue bridge, validation, and
// the schema row codec (tuple v2 with id = pk). Pure layer; persistence +
// container decision documented in docs/TYPED-VALUES-STORAGE.md.
// ===========================================================================

fn srowt_blob(a: Int, b: Int, c: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  return v;
}

fn srowt_schema() -> Schema {
  var cols = Vec[ColumnDef].new();
  cols.push(ColumnDef.new("id", ColumnType.IntType));
  cols.push(ColumnDef.optional("score", ColumnType.FloatType, None));
  cols.push(ColumnDef.new("ok", ColumnType.BoolType));
  cols.push(ColumnDef.new("name", ColumnType.StringType));
  cols.push(ColumnDef.new("raw", ColumnType.BytesType));
  return Schema.new("t", cols, 0);
}

fn srowt_ok_row() -> Vec[TValue] {
  var vals = Vec[TValue].new();
  vals.push(TValue.VInt(42));
  vals.push(TValue.VFloat(2.5));
  vals.push(TValue.VInt(1));
  vals.push(TValue.VText("h\xC3\xA9llo"));
  vals.push(TValue.VBlob(srowt_blob(1, 2, 3)));
  return vals;
}

fn run_schema_row_kinds() -> Int {
  var cols = Vec[ColumnDef].new();
  cols.push(ColumnDef.new("i", ColumnType.IntType));
  cols.push(ColumnDef.new("f", ColumnType.FloatType));
  cols.push(ColumnDef.new("b", ColumnType.BoolType));
  cols.push(ColumnDef.new("s", ColumnType.StringType));
  cols.push(ColumnDef.new("y", ColumnType.BytesType));
  let c0 = cols[0];
  let c1 = cols[1];
  let c2 = cols[2];
  let c3 = cols[3];
  let c4 = cols[4];

  if !schema_row_value_ok(&c0, TValue.VInt(1)) { return 1; }
  if schema_row_value_ok(&c0, TValue.VText("x")) { return 2; }
  if schema_row_value_ok(&c0, TValue.VNull) { return 3; }
  if !schema_row_value_ok(&c1, TValue.VFloat(0.5)) { return 4; }
  if schema_row_value_ok(&c1, TValue.VInt(1)) { return 5; }
  if !schema_row_value_ok(&c2, TValue.VInt(0)) { return 6; }
  if !schema_row_value_ok(&c2, TValue.VInt(1)) { return 7; }
  if schema_row_value_ok(&c2, TValue.VInt(2)) { return 8; }
  if schema_row_value_ok(&c2, TValue.VText("1")) { return 9; }
  if !schema_row_value_ok(&c3, TValue.VText("")) { return 10; }
  if schema_row_value_ok(&c3, TValue.VBlob(srowt_blob(1, 0, 0))) { return 11; }
  if !schema_row_value_ok(&c4, TValue.VBlob(srowt_blob(1, 0, 0))) { return 12; }
  if schema_row_value_ok(&c4, TValue.VInt(1)) { return 13; }
  let nullable_col = ColumnDef.optional("n", ColumnType.StringType, None);
  if !schema_row_value_ok(&nullable_col, TValue.VNull) { return 14; }
  if !schema_row_value_ok(&nullable_col, TValue.VText("a")) { return 15; }
  if schema_row_value_ok(&nullable_col, TValue.VInt(1)) { return 16; }
  if column_type_code(ColumnType.IntType) != 1 { return 17; }
  if column_type_code(ColumnType.FloatType) != 2 { return 18; }
  if column_type_code(ColumnType.BoolType) != 3 { return 19; }
  if column_type_code(ColumnType.StringType) != 4 { return 20; }
  if column_type_code(ColumnType.BytesType) != 5 { return 21; }
  return 0;
}

fn test_schema_row_kinds() -> TestResult {
  let rc = run_schema_row_kinds();
  if rc == 0 { return assert(true, "schema_row: ColumnType<->TValue kind mapping + nullability + bool domain"); }
  return assert(false, "schema_row: kinds failed rc=" + int_to_str(rc));
}

fn run_schema_row_roundtrip() -> Int {
  let schema = srowt_schema();
  let vals = srowt_ok_row();
  match schema_row_validate(&schema, &vals) {
    Err(_) => { return 1; }
    Ok(_) => {}
  }
  match schema_row_key(&schema, &vals) {
    Err(_) => { return 2; }
    Ok(k) => { if k != 42 { return 3; } }
  }
  let enc = schema_row_encode(&schema, &vals);
  match enc {
    Err(_) => { return 4; }
    Ok(buf) => {
      let bytes: Vec[Int] = buf;
      if bytes.len() != tuple2_encoded_len(&vals) { return 5; }
      let dec = schema_row_decode(&schema, &bytes);
      match dec {
        Err(_) => { return 6; }
        Ok(row) => {
          let r: TypedRow = row;
          if r.id != 42 { return 7; }
          if r.values.len() != 5 { return 8; }
          match tuple2_int_value(r.values[0]) { None => { return 9; } Some(v) => { if v != 42 { return 10; } } }
          match tuple2_float_value(r.values[1]) { None => { return 11; } Some(f) => { if f != 2.5 { return 12; } } }
          match tuple2_int_value(r.values[2]) { None => { return 13; } Some(v) => { if v != 1 { return 14; } } }
          match tuple2_text_value(r.values[3]) { None => { return 15; } Some(s) => { if s != "h\xC3\xA9llo" { return 16; } } }
          match tuple2_blob_value(r.values[4]) {
            None => { return 17; }
            Some(b) => {
              if b.len() != 3 { return 18; }
              if b[0] != 1 { return 19; }
              if b[2] != 3 { return 20; }
            }
          }
          // Re-encode the decoded row: byte-identical (canonical codec).
          match schema_row_encode(&schema, &r.values) {
            Err(_) => { return 21; }
            Ok(buf2) => {
              let b2: Vec[Int] = buf2;
              if b2.len() != bytes.len() { return 22; }
              var i = 0;
              while i < b2.len() {
                if b2[i] != bytes[i] { return 23; }
                i = i + 1;
              }
            }
          }
        }
      }
      // The raw codec sees the same row (composition).
      match tuple2_decode_row(&bytes) {
        Err(_) => { return 24; }
        Ok(r2) => { if r2.id != 42 { return 25; } }
      }
    }
  }
  return 0;
}

fn test_schema_row_roundtrip() -> TestResult {
  let rc = run_schema_row_roundtrip();
  if rc == 0 { return assert(true, "schema_row: validate/key/encode/decode roundtrip + byte-identity"); }
  return assert(false, "schema_row: roundtrip failed rc=" + int_to_str(rc));
}

fn run_schema_row_rejects() -> Int {
  let schema = srowt_schema();

  // Arity: too few / too many.
  var four = Vec[TValue].new();
  four.push(TValue.VInt(1));
  four.push(TValue.VFloat(1.0));
  four.push(TValue.VInt(1));
  four.push(TValue.VText("n"));
  match schema_row_validate(&schema, &four) { Ok(_) => { return 1; } Err(e) => { if schema_row_error_code(e) != 4 { return 2; } } }
  var six = srowt_ok_row();
  six.push(TValue.VNull);
  match schema_row_validate(&schema, &six) { Ok(_) => { return 3; } Err(e) => { if schema_row_error_code(e) != 4 { return 4; } } }

  // Null on a non-nullable column.
  var nullrow = srowt_ok_row();
  nullrow[3] = TValue.VNull;
  match schema_row_validate(&schema, &nullrow) {
    Ok(_) => { return 5; }
    Err(e) => { if schema_row_error_code(e) != 3 { return 6; } }
  }

  // Null on the NULLABLE column is fine.
  var oknull = srowt_ok_row();
  oknull[1] = TValue.VNull;
  match schema_row_validate(&schema, &oknull) { Err(_) => { return 7; } Ok(_) => {} }

  // Wrong kinds per column.
  var bad = srowt_ok_row();
  bad[0] = TValue.VText("x");
  match schema_row_validate(&schema, &bad) { Ok(_) => { return 8; } Err(e) => { if schema_row_error_code(e) != 4 { return 9; } } }
  bad = srowt_ok_row();
  bad[1] = TValue.VInt(1);
  match schema_row_validate(&schema, &bad) { Ok(_) => { return 10; } Err(e) => { if schema_row_error_code(e) != 4 { return 11; } } }
  bad = srowt_ok_row();
  bad[2] = TValue.VInt(2);
  match schema_row_validate(&schema, &bad) { Ok(_) => { return 12; } Err(e) => { if schema_row_error_code(e) != 3 { return 13; } } }
  bad = srowt_ok_row();
  bad[3] = TValue.VBlob(srowt_blob(1, 0, 0));
  match schema_row_validate(&schema, &bad) { Ok(_) => { return 14; } Err(e) => { if schema_row_error_code(e) != 4 { return 15; } } }
  bad = srowt_ok_row();
  bad[4] = TValue.VInt(1);
  match schema_row_validate(&schema, &bad) { Ok(_) => { return 16; } Err(e) => { if schema_row_error_code(e) != 4 { return 17; } } }

  // Non-VInt pk (even when the declared type is int).
  var pkbad = srowt_ok_row();
  pkbad[0] = TValue.VText("42");
  match schema_row_key(&schema, &pkbad) { Ok(_) => { return 18; } Err(e) => { if schema_row_error_code(e) != 4 { return 19; } } }

  // Nullable pk schema + VNull pk: int-keyed storage refuses.
  var pcols = Vec[ColumnDef].new();
  pcols.push(ColumnDef.optional("id", ColumnType.IntType, None));
  let pschema = Schema.new("p", pcols, 0);
  var pvals = Vec[TValue].new();
  pvals.push(TValue.VNull);
  match schema_row_validate(&pschema, &pvals) { Ok(_) => { return 20; } Err(e) => { if schema_row_error_code(e) != 4 { return 21; } } }

  // 256 columns: valid per schema, refused by the codec (u8 field count).
  var wide_cols = Vec[ColumnDef].new();
  var wide_vals = Vec[TValue].new();
  var i = 0;
  while i < 256 {
    wide_cols.push(ColumnDef.new("c" + int_to_str(i), ColumnType.IntType));
    wide_vals.push(TValue.VInt(i));
    i = i + 1;
  }
  let wide_schema = Schema.new("w", wide_cols, 0);
  match schema_row_validate(&wide_schema, &wide_vals) { Err(_) => { return 22; } Ok(_) => {} }
  match schema_row_encode(&wide_schema, &wide_vals) { Ok(_) => { return 23; } Err(e) => { if schema_row_error_code(e) != 3 { return 24; } } }

  // Decode: v1 bytes are not schema rows.
  var v1data = Vec[Int].new();
  v1data.push(1);
  let v1row = Row.new(1, v1data);
  let v1enc = tuple_encode_checked(&v1row);
  match v1enc {
    Err(_) => { return 25; }
    Ok(v1buf) => {
      let b1: Vec[Int] = v1buf;
      match schema_row_decode(&schema, &b1) { Ok(_) => { return 26; } Err(e) => { if schema_row_error_code(e) != 6 { return 27; } } }
    }
  }

  // Decode: id/pk mismatch is corruption (encoded via the raw codec with a
  // different id).
  let vals = srowt_ok_row();
  let raw = tuple2_encode_row_checked(99, &vals);
  match raw {
    Err(_) => { return 28; }
    Ok(rawbuf) => {
      let rb: Vec[Int] = rawbuf;
      match schema_row_decode(&schema, &rb) { Ok(_) => { return 29; } Err(e) => { if schema_row_error_code(e) != 6 { return 30; } } }
    }
  }

  // Decode: schema drift (column 3 declared int instead of string).
  var drift_cols = Vec[ColumnDef].new();
  drift_cols.push(ColumnDef.new("id", ColumnType.IntType));
  drift_cols.push(ColumnDef.optional("score", ColumnType.FloatType, None));
  drift_cols.push(ColumnDef.new("ok", ColumnType.BoolType));
  drift_cols.push(ColumnDef.new("name", ColumnType.IntType));
  drift_cols.push(ColumnDef.new("raw", ColumnType.BytesType));
  let drift = Schema.new("t", drift_cols, 0);
  let enc = schema_row_encode(&schema, &vals);
  match enc {
    Err(_) => { return 31; }
    Ok(buf) => {
      let bytes: Vec[Int] = buf;
      match schema_row_decode(&drift, &bytes) { Ok(_) => { return 32; } Err(e) => { if schema_row_error_code(e) != 4 { return 33; } } }
    }
  }
  return 0;
}

fn test_schema_row_rejects() -> TestResult {
  let rc = run_schema_row_rejects();
  if rc == 0 { return assert(true, "schema_row: rejects arity/null/kind/bool/pk + corruption + schema drift"); }
  return assert(false, "schema_row: rejects failed rc=" + int_to_str(rc));
}

// Bool domain + empty text/blob round-trips through the schema layer.
fn run_schema_row_bool_and_empty() -> Int {
  var cols = Vec[ColumnDef].new();
  cols.push(ColumnDef.new("id", ColumnType.IntType));
  cols.push(ColumnDef.new("b", ColumnType.BoolType));
  cols.push(ColumnDef.new("s", ColumnType.StringType));
  let schema = Schema.new("be", cols, 0);

  var v0 = Vec[TValue].new();
  v0.push(TValue.VInt(1));
  v0.push(TValue.VInt(0));
  v0.push(TValue.VText(""));
  var v1 = Vec[TValue].new();
  v1.push(TValue.VInt(2));
  v1.push(TValue.VInt(1));
  var empty = Vec[Int].new();
  v1.push(TValue.VBlob(empty));

  match schema_row_encode(&schema, &v0) {
    Err(_) => { return 1; }
    Ok(b0) => {
      let bytes: Vec[Int] = b0;
      match schema_row_decode(&schema, &bytes) {
        Err(_) => { return 2; }
        Ok(r) => {
          match tuple2_int_value(r.values[1]) { None => { return 3; } Some(b) => { if b != 0 { return 4; } } }
          match tuple2_text_value(r.values[2]) { None => { return 5; } Some(s) => { if s != "" { return 6; } } }
        }
      }
    }
  }
  // Column 2 is a String column: a blob is a kind violation even when empty.
  match schema_row_encode(&schema, &v1) {
    Ok(_) => { return 7; }
    Err(e) => { if schema_row_error_code(e) != 4 { return 8; } }
  }
  return 0;
}

fn test_schema_row_bool_and_empty() -> TestResult {
  let rc = run_schema_row_bool_and_empty();
  if rc == 0 { return assert(true, "schema_row: bool 0/1 domain + empty text roundtrip + kind strictness"); }
  return assert(false, "schema_row: bool/empty failed rc=" + int_to_str(rc));
}

// ===========================================================================
// Typed rows in the engine (M5.3): payload container through put/get, WAL
// (tagged subtype 1), replay, and both snapshot containers. Contract:
// docs/TYPED-VALUES-STORAGE.md.
// ===========================================================================

fn tdb_row3(a: Int, b: Int, c: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  return v;
}

fn tdb_row2(a: Int, b: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  return v;
}

fn tdb_cleanup(path: Str) {
  let _ = io.remove_file(path);
  let _ = io.remove_file(path + ".snap");
}

fn run_db_typed_roundtrip() -> Int {
  let path = "orbitdb-suite-typed.wal";
  tdb_cleanup(path);
  var db = db_file_open(path, 4);

  // Typed put: get_typed returns the payload; the int value mirrors the key.
  if !db_file_put_typed(&mut db, 7, tdb_row3(1, 2, 3)) { return 1; }
  match db_file_get_typed(&db, 7) {
    None => { return 2; }
    Some(p) => {
      if p.len() != 3 { return 3; }
      if p[0] != 1 { return 4; }
      if p[2] != 3 { return 5; }
    }
  }
  match db_file_get(&db, 7) {
    None => { return 6; }
    Some(v) => { if v != 7 { return 7; } }
  }

  // Int row coexists; get_typed on it is None.
  if !db_file_put(&mut db, 8, 800) { return 8; }
  match db_file_get_typed(&db, 8) { Some(_) => { return 9; } None => {} }

  // Typed -> int overwrite drops the payload.
  if !db_file_put(&mut db, 7, 700) { return 10; }
  match db_file_get_typed(&db, 7) { Some(_) => { return 11; } None => {} }
  match db_file_get(&db, 7) { Some(v) => { if v != 700 { return 12; } } None => { return 13; } }

  // Int -> typed overwrite installs one.
  if !db_file_put_typed(&mut db, 8, tdb_row2(9, 9)) { return 14; }
  match db_file_get_typed(&db, 8) {
    None => { return 15; }
    Some(p) => { if p.len() != 2 { return 16; } }
  }

  // Reopen WITHOUT checkpoint: WAL replay must carry the payloads.
  var db2 = db_file_open(path, 4);
  if db_file_size(&db2) != 2 { return 17; }
  match db_file_get_typed(&db2, 8) {
    None => { return 18; }
    Some(p) => { if p[0] != 9 { return 19; } }
  }
  match db_file_get_typed(&db2, 7) { Some(_) => { return 20; } None => {} }
  match db_file_get(&db2, 7) { Some(v) => { if v != 700 { return 21; } } None => { return 22; } }

  // Delete a typed row.
  if !db_file_delete(&mut db2, 8) { return 23; }
  var db3 = db_file_open(path, 4);
  if db_file_size(&db3) != 1 { return 24; }
  match db_file_get_typed(&db3, 8) { Some(_) => { return 25; } None => {} }

  tdb_cleanup(path);
  return 0;
}

fn test_db_typed_roundtrip() -> TestResult {
  let rc = run_db_typed_roundtrip();
  if rc == 0 { return assert(true, "db_file typed: put/get/overwrite/delete + WAL replay carries payloads"); }
  return assert(false, "db_file typed: roundtrip failed rc=" + int_to_str(rc));
}

fn tdb_checkpoint_body(path: Str, page_format: Int) -> Int {
  tdb_cleanup(path);
  var db = db_file_open_cfg(path, 4, page_format);
  var k = 1;
  while k <= 5 {
    if !db_file_put_typed(&mut db, k, tdb_row3(k, k * 10, 100 + k)) { return 1; }
    k = k + 1;
  }
  if !db_file_put(&mut db, 6, 6000) { return 2; }
  if db_file_checkpoint(&mut db) < 0 { return 3; }
  // Tail after the snapshot.
  if !db_file_put_typed(&mut db, 7, tdb_row3(7, 70, 107)) { return 4; }
  if !db_file_put(&mut db, 8, 8000) { return 5; }

  var db2 = db_file_open(path, 4);
  if db_file_size(&db2) != 8 { return 6; }
  k = 1;
  while k <= 5 {
    match db_file_get_typed(&db2, k) {
      None => { return 10 + k; }
      Some(p) => {
        if p.len() != 3 { return 20 + k; }
        if p[0] != k { return 30 + k; }
        if p[1] != k * 10 { return 40 + k; }
        if p[2] != 100 + k { return 50 + k; }
      }
    }
    k = k + 1;
  }
  match db_file_get(&db2, 6) {
    None => { return 60; }
    Some(v) => { if v != 6000 { return 61; } }
  }
  match db_file_get_typed(&db2, 7) {
    None => { return 62; }
    Some(p) => { if p[1] != 70 { return 63; } }
  }
  match db_file_get(&db2, 8) {
    None => { return 64; }
    Some(v) => { if v != 8000 { return 65; } }
  }

  // A second checkpoint then reopen: payloads survive generations.
  if db_file_checkpoint(&mut db2) < 0 { return 66; }
  var db3 = db_file_open(path, 4);
  if db_file_size(&db3) != 8 { return 67; }
  match db_file_get_typed(&db3, 3) {
    None => { return 68; }
    Some(p) => { if p[2] != 103 { return 69; } }
  }
  tdb_cleanup(path);
  return 0;
}

fn run_db_typed_checkpoint_v1() -> Int {
  return tdb_checkpoint_body("orbitdb-suite-typed-ck1.wal", 1);
}

fn test_db_typed_checkpoint_v1() -> TestResult {
  let rc = run_db_typed_checkpoint_v1();
  if rc == 0 { return assert(true, "db_file typed: v1 checkpoint + generations keep payloads (snapshot + tail)"); }
  return assert(false, "db_file typed: v1 checkpoint failed rc=" + int_to_str(rc));
}

fn run_db_typed_checkpoint_v2() -> Int {
  return tdb_checkpoint_body("orbitdb-suite-typed-ck2.wal", 2);
}

fn test_db_typed_checkpoint_v2() -> TestResult {
  let rc = run_db_typed_checkpoint_v2();
  if rc == 0 { return assert(true, "db_file typed: v2 block snapshot keeps payloads (auto-detect + regen)"); }
  return assert(false, "db_file typed: v2 checkpoint failed rc=" + int_to_str(rc));
}

fn run_db_typed_budget_and_guards() -> Int {
  // Budget formula: overhead = 28 + 24*(order-1) + 8*order, room = 4056 - it.
  if db_file_typed_payload_max(2) != 0 { return 1; }
  if db_file_typed_payload_max(3) != 1978 { return 2; }
  if db_file_typed_payload_max(4) != 1308 { return 3; }
  if db_file_typed_payload_max(5) != 973 { return 4; }

  let path = "orbitdb-suite-typed-budget.wal";
  tdb_cleanup(path);
  var db = db_file_open(path, 3);
  let max = db_file_typed_payload_max(3);
  var exact = Vec[Int].new();
  var i = 0;
  while i < max {
    exact.push(i % 256);
    i = i + 1;
  }
  if !db_file_put_typed(&mut db, 1, exact) { return 5; }
  match db_file_get_typed(&db, 1) {
    None => { return 6; }
    Some(p) => { if p.len() != max { return 7; } }
  }
  // One byte over the budget: refused, and nothing is stored.
  var over = Vec[Int].new();
  i = 0;
  while i < max + 1 {
    over.push(1);
    i = i + 1;
  }
  if db_file_put_typed(&mut db, 2, over) { return 8; }
  match db_file_get_typed(&db, 2) { Some(_) => { return 9; } None => {} }
  if db_file_size(&db) != 1 { return 10; }

  // Typed writes are refused while a transaction is active.
  if !db_file_txn_begin(&mut db) { return 11; }
  if db_file_put_typed(&mut db, 3, tdb_row2(1, 2)) { return 12; }
  if !db_file_txn_abort(&mut db) { return 13; }

  // Byte-range: elements outside 0..255 are refused up front (the snapshot
  // codecs are byte-oriented; accepting them would silently lose bits).
  var wide = Vec[Int].new();
  wide.push(300);
  if db_file_put_typed(&mut db, 4, wide) { return 14; }
  var neg = Vec[Int].new();
  neg.push(-1);
  if db_file_put_typed(&mut db, 4, neg) { return 15; }
  if db_file_size(&db) != 1 { return 16; }

  tdb_cleanup(path);
  return 0;
}

fn test_db_typed_budget_and_guards() -> TestResult {
  let rc = run_db_typed_budget_and_guards();
  if rc == 0 { return assert(true, "db_file typed: payload budget (orders 3/4/5) + over-budget + txn guard"); }
  return assert(false, "db_file typed: budget/guards failed rc=" + int_to_str(rc));
}

// Crafted WAL: a typed record inside a committed txn window must replay with
// its payload (TxOp buffers it); inside an unterminated window it is
// discarded like any uncommitted write.
fn run_db_typed_txn_window_replay() -> Int {
  let path = "orbitdb-suite-typed-txn2.wal";
  tdb_cleanup(path);
  var wal = wal_file_open(path);
  let _ = wal_file_append(&mut wal, WALOpKind.BeginTxn, 0, 0);
  var tagged = Vec[Int].new();
  tagged.push(1);
  tagged.push(5);
  tagged.push(6);
  tagged.push(7);
  let _ = wal_file_append_tagged(&mut wal, WALOpKind.Update, 11, 11, tagged, 0);
  let _ = wal_file_append(&mut wal, WALOpKind.CommitTxn, 0, 0);
  let _ = wal_file_append(&mut wal, WALOpKind.BeginTxn, 0, 0);
  var tagged2 = Vec[Int].new();
  tagged2.push(1);
  tagged2.push(8);
  tagged2.push(9);
  let _ = wal_file_append_tagged(&mut wal, WALOpKind.Update, 12, 12, tagged2, 0);

  var db = db_file_open(path, 4);
  if db_file_size(&db) != 1 { return 1; }
  match db_file_get_typed(&db, 11) {
    None => { return 2; }
    Some(p) => {
      if p.len() != 3 { return 3; }
      if p[0] != 5 { return 4; }
      if p[2] != 7 { return 5; }
    }
  }
  match db_file_get_typed(&db, 12) { Some(_) => { return 6; } None => {} }
  match db_file_get(&db, 11) {
    None => { return 7; }
    Some(v) => { if v != 11 { return 8; } }
  }

  // Deeper window: int ops and typed ops mixed, then commit.
  let _ = io.remove_file(path);
  let _ = io.remove_file(path + ".snap");
  var wal2 = wal_file_open(path);
  let _ = wal_file_append(&mut wal2, WALOpKind.BeginTxn, 0, 0);
  let _ = wal_file_append(&mut wal2, WALOpKind.Update, 1, 100);
  var tagged3 = Vec[Int].new();
  tagged3.push(1);
  tagged3.push(42);
  let _ = wal_file_append_tagged(&mut wal2, WALOpKind.Update, 2, 2, tagged3, 0);
  let _ = wal_file_append(&mut wal2, WALOpKind.Delete, 1, 0);
  let _ = wal_file_append(&mut wal2, WALOpKind.CommitTxn, 0, 0);
  var db2 = db_file_open(path, 4);
  if db_file_size(&db2) != 1 { return 9; }
  match db_file_get(&db2, 1) { Some(_) => { return 10; } None => {} }
  match db_file_get_typed(&db2, 2) {
    None => { return 11; }
    Some(p) => { if p[0] != 42 { return 12; } }
  }

  tdb_cleanup(path);
  return 0;
}

fn test_db_typed_txn_window_replay() -> TestResult {
  let rc = run_db_typed_txn_window_replay();
  if rc == 0 { return assert(true, "db_file typed: committed txn window replays payloads; uncommitted discarded"); }
  return assert(false, "db_file typed: txn window replay failed rc=" + int_to_str(rc));
}

// ===========================================================================
// Typed comparisons + typed queries (M5-S4): the total order over TValue
// (Null < numeric < text < blob) and db_file_query_typed predicates.
// ===========================================================================

fn tq_blob(a: Int, b: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  return v;
}

fn tq_blob1(a: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  return v;
}

fn tq_blob3(a: Int, b: Int, c: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  return v;
}

fn run_tuple2_compare() -> Int {
  // Null is the minimum; rank order numeric < text < blob.
  if tuple2_compare(TValue.VNull, TValue.VNull) != 0 { return 1; }
  if tuple2_compare(TValue.VNull, TValue.VInt(0)) != -1 { return 2; }
  if tuple2_compare(TValue.VInt(0), TValue.VNull) != 1 { return 3; }
  if tuple2_compare(TValue.VNull, TValue.VText("")) != -1 { return 4; }
  if tuple2_compare(TValue.VText(""), TValue.VNull) != 1 { return 5; }
  // Ints exact; int/float numeric coercion.
  if tuple2_compare(TValue.VInt(-5), TValue.VInt(-4)) != -1 { return 6; }
  if tuple2_compare(TValue.VInt(7), TValue.VInt(7)) != 0 { return 7; }
  if tuple2_compare(TValue.VInt(1), TValue.VFloat(1.0)) != 0 { return 8; }
  if tuple2_compare(TValue.VInt(2), TValue.VFloat(1.5)) != 1 { return 9; }
  if tuple2_compare(TValue.VInt(1), TValue.VFloat(1.5)) != -1 { return 10; }
  // Floats: natural order, NaN first, NaN == NaN.
  if tuple2_compare(TValue.VFloat(-2.5), TValue.VFloat(0.0)) != -1 { return 11; }
  if tuple2_compare(TValue.VFloat(0.0), TValue.VFloat(2.5)) != -1 { return 12; }
  if tuple2_compare(TValue.VFloat(3.0), TValue.VFloat(3.0)) != 0 { return 13; }
  // Numeric ranks above/below across kinds.
  if tuple2_compare(TValue.VInt(999), TValue.VText("")) != -1 { return 14; }
  if tuple2_compare(TValue.VText(""), TValue.VBlob(tq_blob(0, 0))) != -1 { return 15; }
  // Text bytewise lexicographic (prefix smaller).
  if tuple2_compare(TValue.VText("a"), TValue.VText("ab")) != -1 { return 16; }
  if tuple2_compare(TValue.VText("ab"), TValue.VText("b")) != -1 { return 17; }
  if tuple2_compare(TValue.VText("apple"), TValue.VText("apple")) != 0 { return 18; }
  // Multibyte UTF-8 compares by bytes.
  if tuple2_compare(TValue.VText("z"), TValue.VText("\xC3\xA9")) != -1 { return 19; }
  // Blobs element-wise.
  if tuple2_compare(TValue.VBlob(tq_blob(1, 2)), TValue.VBlob(tq_blob(1, 3))) != -1 { return 20; }
  if tuple2_compare(TValue.VBlob(tq_blob(1, 2)), TValue.VBlob(tq_blob3(1, 2, 0))) != -1 { return 21; }
  if tuple2_compare(TValue.VBlob(tq_blob1(9)), TValue.VBlob(tq_blob(1, 9))) != 1 { return 22; }
  return 0;
}

fn test_tuple2_compare() -> TestResult {
  let rc = run_tuple2_compare();
  if rc == 0 { return assert(true, "tuple v2: total order (null < numeric < text < blob; coercion; NaN)"); }
  return assert(false, "tuple v2: comparator failed rc=" + int_to_str(rc));
}

fn tq_put_row(db: &mut DBFile, id: Int, v0: TValue, v1: TValue, v2: TValue) -> Bool {
  var vals = Vec[TValue].new();
  vals.push(v0);
  vals.push(v1);
  vals.push(v2);
  match tuple2_encode_row_checked(id, &vals) {
    Err(_) => { return false; }
    Ok(buf) => { return db_file_put_typed(db, id, buf); }
  }
}

fn tq_seed(db: &mut DBFile) -> Int {
  if !tq_put_row(db, 1, TValue.VInt(10), TValue.VText("apple"), TValue.VFloat(1.5)) { return 1; }
  if !tq_put_row(db, 2, TValue.VInt(20), TValue.VText("banana"), TValue.VFloat(-2.0)) { return 2; }
  if !tq_put_row(db, 3, TValue.VNull, TValue.VText("apple"), TValue.VFloat(0.0)) { return 3; }
  if !tq_put_row(db, 4, TValue.VInt(10), TValue.VText("apricot"), TValue.VFloat(2.5)) { return 4; }
  if !db_file_put(db, 5, 555) { return 5; }
  var raw = Vec[Int].new();
  raw.push(1);
  raw.push(2);
  raw.push(3);
  if !db_file_put_typed(db, 6, raw) { return 6; }
  return 0;
}

fn tq_expect(db: &DBFile, q: &TypedQuery, want: &Vec[Int]) -> Bool {
  let got = db_file_query_typed(db, q);
  if got.len() != want.len() { return false; }
  var i = 0;
  while i < got.len() {
    if got[i] != want[i] { return false; }
    i = i + 1;
  }
  return true;
}

fn tq_want(a: Int, b: Int, c: Int, d: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  if a >= 0 { v.push(a); }
  if b >= 0 { v.push(b); }
  if c >= 0 { v.push(c); }
  if d >= 0 { v.push(d); }
  return v;
}

fn run_typed_query_ops() -> Int {
  let path = "orbitdb-suite-tquery.wal";
  tdb_cleanup(path);
  var db = db_file_open(path, 4);
  let seed = tq_seed(&mut db);
  if seed != 0 { return seed; }

  var q = typed_query_new();
  // Eq int -> [1,4]
  typed_query_where(&mut q, 0, QueryOp.Eq, TValue.VInt(10));
  if !tq_expect(&db, &q, &tq_want(1, 4, -1, -1)) { return 10; }
  // Gt int -> [2]
  q = typed_query_new();
  typed_query_where(&mut q, 0, QueryOp.Gt, TValue.VInt(10));
  if !tq_expect(&db, &q, &tq_want(2, -1, -1, -1)) { return 11; }
  // Lte includes the null (null < numeric) -> [1,3,4]
  q = typed_query_new();
  typed_query_where(&mut q, 0, QueryOp.Lte, TValue.VInt(10));
  if !tq_expect(&db, &q, &tq_want(1, 3, 4, -1)) { return 12; }
  // Lt -> only the null -> [3]
  q = typed_query_new();
  typed_query_where(&mut q, 0, QueryOp.Lt, TValue.VInt(10));
  if !tq_expect(&db, &q, &tq_want(3, -1, -1, -1)) { return 13; }
  // Neq null excludes null rows -> [1,2,4]
  q = typed_query_new();
  typed_query_where(&mut q, 0, QueryOp.Neq, TValue.VNull);
  if !tq_expect(&db, &q, &tq_want(1, 2, 4, -1)) { return 14; }
  // Gte null -> everything typed -> [1,2,3,4]
  q = typed_query_new();
  typed_query_where(&mut q, 0, QueryOp.Gte, TValue.VNull);
  if !tq_expect(&db, &q, &tq_want(1, 2, 3, 4)) { return 15; }
  // Text equality -> [1,3]
  q = typed_query_new();
  typed_query_where(&mut q, 1, QueryOp.Eq, TValue.VText("apple"));
  if !tq_expect(&db, &q, &tq_want(1, 3, -1, -1)) { return 16; }
  // Text Gt -> [2,4]
  q = typed_query_new();
  typed_query_where(&mut q, 1, QueryOp.Gt, TValue.VText("apple"));
  if !tq_expect(&db, &q, &tq_want(2, 4, -1, -1)) { return 17; }
  // Float vs int literal across kinds (numeric): Eq 2.5 -> [4]
  q = typed_query_new();
  typed_query_where(&mut q, 2, QueryOp.Eq, TValue.VFloat(2.5));
  if !tq_expect(&db, &q, &tq_want(4, -1, -1, -1)) { return 18; }
  // Column -1 addresses the row id.
  q = typed_query_new();
  typed_query_where(&mut q, -1, QueryOp.Eq, TValue.VInt(3));
  if !tq_expect(&db, &q, &tq_want(3, -1, -1, -1)) { return 19; }
  // Out-of-range column never matches.
  q = typed_query_new();
  typed_query_where(&mut q, 9, QueryOp.Eq, TValue.VInt(1));
  if !tq_expect(&db, &q, &tq_want(-1, -1, -1, -1)) { return 20; }
  // No conditions: every decodable typed row (int row 5 and malformed 6 out).
  q = typed_query_new();
  if !tq_expect(&db, &q, &tq_want(1, 2, 3, 4)) { return 21; }
  // AND of two conditions: [1]
  q = typed_query_new();
  typed_query_where(&mut q, 0, QueryOp.Eq, TValue.VInt(10));
  typed_query_where(&mut q, 1, QueryOp.Eq, TValue.VText("apple"));
  if !tq_expect(&db, &q, &tq_want(1, -1, -1, -1)) { return 22; }
  // Limit/offset on matches.
  q = typed_query_new();
  typed_query_where(&mut q, 0, QueryOp.Eq, TValue.VInt(10));
  typed_query_limit(&mut q, 1);
  if !tq_expect(&db, &q, &tq_want(1, -1, -1, -1)) { return 23; }
  q = typed_query_new();
  typed_query_where(&mut q, 0, QueryOp.Eq, TValue.VInt(10));
  typed_query_offset(&mut q, 1);
  if !tq_expect(&db, &q, &tq_want(4, -1, -1, -1)) { return 24; }
  q = typed_query_new();
  typed_query_where(&mut q, 0, QueryOp.Eq, TValue.VInt(10));
  typed_query_limit(&mut q, 1);
  typed_query_offset(&mut q, 1);
  if !tq_expect(&db, &q, &tq_want(4, -1, -1, -1)) { return 25; }

  tdb_cleanup(path);
  return 0;
}

fn test_typed_query_ops() -> TestResult {
  let rc = run_typed_query_ops();
  if rc == 0 { return assert(true, "typed query: ops over int/text/float/null + id column + limit/offset"); }
  return assert(false, "typed query: ops failed rc=" + int_to_str(rc));
}

fn run_typed_query_persistence() -> Int {
  let path = "orbitdb-suite-tquery2.wal";
  tdb_cleanup(path);
  var db = db_file_open(path, 4);
  let seed = tq_seed(&mut db);
  if seed != 0 { return 1; }
  if db_file_checkpoint(&mut db) < 0 { return 2; }
  // Tail after the snapshot.
  if !tq_put_row(&mut db, 7, TValue.VInt(10), TValue.VText("avocado"), TValue.VFloat(3.5)) { return 3; }

  var db2 = db_file_open(path, 4);
  var q = typed_query_new();
  typed_query_where(&mut q, 0, QueryOp.Eq, TValue.VInt(10));
  if !tq_expect(&db2, &q, &tq_want(1, 4, 7, -1)) { return 4; }
  q = typed_query_new();
  typed_query_where(&mut q, 1, QueryOp.Gte, TValue.VText("apricot"));
  if !tq_expect(&db2, &q, &tq_want(2, 4, 7, -1)) { return 5; }

  // Mutation visibility: delete 4, add 8 -> queries reflect both.
  if !db_file_delete(&mut db2, 4) { return 6; }
  if !tq_put_row(&mut db2, 8, TValue.VInt(10), TValue.VText(" almond"), TValue.VFloat(0.5)) { return 7; }
  q = typed_query_new();
  typed_query_where(&mut q, 0, QueryOp.Eq, TValue.VInt(10));
  if !tq_expect(&db2, &q, &tq_want(1, 7, 8, -1)) { return 8; }
  // Text range: space-leading " almond" sorts before letters.
  q = typed_query_new();
  typed_query_where(&mut q, 1, QueryOp.Lt, TValue.VText("a"));
  if !tq_expect(&db2, &q, &tq_want(8, -1, -1, -1)) { return 9; }

  tdb_cleanup(path);
  return 0;
}

fn test_typed_query_persistence() -> TestResult {
  let rc = run_typed_query_persistence();
  if rc == 0 { return assert(true, "typed query: survives checkpoint/reopen; mutations visible"); }
  return assert(false, "typed query: persistence failed rc=" + int_to_str(rc));
}

// ===========================================================================
// M3 minimal subset: snapshot pins + savepoints (docs/MVCC.md)
// ===========================================================================

fn mvcc_copy(v: &Vec[Int]) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 0;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
  return out;
}

// Model lookup table: slot k holds key k's value, or -1 when absent.
fn mvcc_model_new(n: Int) -> Vec[Int] {
  var m = Vec[Int].new();
  var i = 0;
  while i <= n {
    m.push(-1);
    i = i + 1;
  }
  return m;
}

// Expected VALUES for keys [1, n] in key order, from a model table.
fn mvcc_expected(m: &Vec[Int]) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 1;
  while i < m.len() {
    if m[i] >= 0 { out.push(m[i]); }
    i = i + 1;
  }
  return out;
}

fn mvcc_vec_eq(a: &Vec[Int], b: &Vec[Int]) -> Bool {
  if a.len() != b.len() { return false; }
  var i = 0;
  while i < a.len() {
    if a[i] != b[i] { return false; }
    i = i + 1;
  }
  return true;
}

fn run_db_snapshot_isolation() -> Int {
  let path = "orbitdb-suite-mvcc1.wal";
  tdb_cleanup(path);
  var db = db_file_open(path, 4);
  if !db_file_put(&mut db, 1, 100) { return 1; }
  if !db_file_put(&mut db, 2, 200) { return 2; }
  let s1 = db_file_snapshot_begin(&mut db);
  if s1.id <= 0 { return 3; }
  if db_file_snapshot_pins(&db) != 1 { return 4; }
  // Mutate: update 1, delete 2, add 3.
  if !db_file_put(&mut db, 1, 111) { return 5; }
  if !db_file_delete(&mut db, 2) { return 6; }
  if !db_file_put(&mut db, 3, 300) { return 7; }
  // The live view moves on.
  match db_file_get(&db, 1) { None => { return 8; } Some(v) => { if v != 111 { return 9; } } }
  // The pinned view is frozen at capture.
  match db_file_snapshot_get(&db, s1.id, 1) { None => { return 10; } Some(v) => { if v != 100 { return 11; } } }
  match db_file_snapshot_get(&db, s1.id, 2) { None => { return 12; } Some(v) => { if v != 200 { return 13; } } }
  match db_file_snapshot_get(&db, s1.id, 3) { None => {} Some(_) => { return 14; } }
  if db_file_snapshot_count(&db, s1.id) != 2 { return 15; }
  let r1 = db_file_snapshot_range(&db, s1.id, 1, 3);
  if r1.len() != 2 { return 16; }
  if r1[0] != 100 { return 17; }
  if r1[1] != 200 { return 18; }
  // A second pin at the newer version.
  let s2 = db_file_snapshot_begin(&mut db);
  if db_file_snapshot_pins(&db) != 2 { return 19; }
  if db_file_snapshot_count(&db, s2.id) != 2 { return 20; }
  match db_file_snapshot_get(&db, s2.id, 2) { None => {} Some(_) => { return 21; } }
  // Release s1: its reads refuse; s2 is unaffected.
  if !db_file_snapshot_end(&mut db, s1.id) { return 23; }
  match db_file_snapshot_get(&db, s1.id, 1) { None => {} Some(_) => { return 24; } }
  if db_file_snapshot_count(&db, s1.id) != -1 { return 25; }
  let r2 = db_file_snapshot_range(&db, s1.id, 1, 3);
  if r2.len() != 0 { return 26; }
  if db_file_snapshot_end(&mut db, s1.id) { return 27; }
  match db_file_snapshot_get(&db, s2.id, 3) { None => { return 28; } Some(v) => { if v != 300 { return 29; } } }
  if !db_file_snapshot_end(&mut db, s2.id) { return 30; }
  if db_file_snapshot_pins(&db) != 0 { return 31; }
  if db_file_min_pinned_lsn(&db) != -1 { return 32; }
  if s1.lsn < 0 { return 33; }
  tdb_cleanup(path);
  return 0;
}

fn test_db_snapshot_isolation() -> TestResult {
  let rc = run_db_snapshot_isolation();
  if rc == 0 { return assert(true, "db_file snapshot: frozen pin views, live moves on, id guards"); }
  return assert(false, "db_file snapshot: isolation failed rc=" + int_to_str(rc));
}

// COW correctness under the heaviest rebalancing (order 3): two interleaved
// pins vs models captured at their begin, plus live-tree and reopen checks.
fn run_db_snapshot_cow_churn() -> Int {
  let path = "orbitdb-suite-mvcc2.wal";
  tdb_cleanup(path);
  var db = db_file_open(path, 3);
  var model = mvcc_model_new(60);
  var i = 1;
  while i <= 40 {
    if !db_file_put(&mut db, i, i * 10) { return 1; }
    model[i] = i * 10;
    i = i + 1;
  }
  let s1 = db_file_snapshot_begin(&mut db);
  var model1 = mvcc_copy(&model);
  let want1 = mvcc_expected(&model1);
  let got1 = db_file_snapshot_range(&db, s1.id, 1, 60);
  if !mvcc_vec_eq(&got1, &want1) { return 2; }
  var s2_id = 0;
  var model2 = mvcc_model_new(60);
  var have2 = false;
  var r = 777;
  var op = 0;
  while op < 400 {
    r = (r * 1103515245 + 12345) % 2147483648;
    let key = (r % 60) + 1;
    let roll = (r / 60) % 4;
    if roll == 0 {
      let _ = db_file_delete(&mut db, key);
      model[key] = -1;
    } else {
      let v = r % 1000;
      if !db_file_put(&mut db, key, v) { return 3; }
      model[key] = v;
    }
    if op == 200 {
      let s2 = db_file_snapshot_begin(&mut db);
      s2_id = s2.id;
      model2 = mvcc_copy(&model);
      have2 = true;
    }
    op = op + 1;
  }
  // Both pinned views are exact after 400 mutations.
  let want1b = mvcc_expected(&model1);
  let got1b = db_file_snapshot_range(&db, s1.id, 1, 60);
  if !mvcc_vec_eq(&got1b, &want1b) { return 4; }
  if db_file_snapshot_count(&db, s1.id) != want1b.len() { return 5; }
  if !have2 { return 6; }
  let want2 = mvcc_expected(&model2);
  let got2 = db_file_snapshot_range(&db, s2_id, 1, 60);
  if !mvcc_vec_eq(&got2, &want2) { return 7; }
  if db_file_snapshot_count(&db, s2_id) != want2.len() { return 8; }
  if !db_file_snapshot_end(&mut db, s2_id) { return 9; }
  // Live tree matches the live model; s1 still exact after releasing s2.
  let live_want = mvcc_expected(&model);
  let live_got = db_file_range(&db, 1, 60);
  if !mvcc_vec_eq(&live_got, &live_want) { return 10; }
  let got1c = db_file_snapshot_range(&db, s1.id, 1, 60);
  if !mvcc_vec_eq(&got1c, &want1b) { return 11; }
  if !db_file_snapshot_end(&mut db, s1.id) { return 12; }
  // Persist and reopen: same committed state; pins vanish with the handle.
  if db_file_checkpoint(&mut db) < 0 { return 13; }
  var db2 = db_file_open(path, 3);
  let got_after = db_file_range(&db2, 1, 60);
  if !mvcc_vec_eq(&got_after, &live_want) { return 14; }
  if db_file_snapshot_pins(&db2) != 0 { return 15; }
  tdb_cleanup(path);
  return 0;
}

fn test_db_snapshot_cow_churn() -> TestResult {
  let rc = run_db_snapshot_cow_churn();
  if rc == 0 { return assert(true, "db_file snapshot: COW under order-3 churn, two pins exact, reopen clean"); }
  return assert(false, "db_file snapshot: COW churn failed rc=" + int_to_str(rc));
}

fn run_db_snapshot_checkpoint() -> Int {
  let path = "orbitdb-suite-mvcc3.wal";
  tdb_cleanup(path);
  var db = db_file_open(path, 4);
  var i = 1;
  while i <= 20 {
    if !db_file_put(&mut db, i, i * 10) { return 1; }
    i = i + 1;
  }
  if db_file_snap_generation(&db) != 0 { return 2; }
  if db_file_checkpoint(&mut db) < 0 { return 3; }
  if db_file_snap_generation(&db) != 1 { return 4; }
  let s1 = db_file_snapshot_begin(&mut db);
  if s1.generation != 1 { return 5; }
  if db_file_compaction_deferrals(&db) != 0 { return 6; }
  i = 21;
  while i <= 30 {
    if !db_file_put(&mut db, i, i * 10) { return 7; }
    i = i + 1;
  }
  if !db_file_put(&mut db, 1, 999) { return 8; }
  if db_file_checkpoint(&mut db) < 0 { return 9; }
  if db_file_snap_generation(&db) != 2 { return 10; }
  // The pinned view is still the generation-1 content.
  match db_file_snapshot_get(&db, s1.id, 1) { None => { return 11; } Some(v) => { if v != 10 { return 12; } } }
  match db_file_snapshot_get(&db, s1.id, 25) { None => {} Some(_) => { return 13; } }
  if db_file_snapshot_count(&db, s1.id) != 20 { return 14; }
  // The live view has everything.
  if db_file_size(&db) != 30 { return 15; }
  match db_file_get(&db, 1) { None => { return 16; } Some(v) => { if v != 999 { return 17; } } }
  if db_file_min_pinned_lsn(&db) < 0 { return 18; }
  if !db_file_snapshot_end(&mut db, s1.id) { return 19; }
  if db_file_min_pinned_lsn(&db) != -1 { return 20; }
  // Reopen: pins are handle-local; the committed state is intact.
  var db2 = db_file_open(path, 4);
  if db_file_size(&db2) != 30 { return 21; }
  if db_file_snap_generation(&db2) != 2 { return 22; }
  match db_file_get(&db2, 25) { None => { return 23; } Some(v) => { if v != 250 { return 24; } } }
  tdb_cleanup(path);
  return 0;
}

fn test_db_snapshot_checkpoint() -> TestResult {
  let rc = run_db_snapshot_checkpoint();
  if rc == 0 { return assert(true, "db_file snapshot: stable across checkpoints; generation tracked"); }
  return assert(false, "db_file snapshot: checkpoint failed rc=" + int_to_str(rc));
}

fn run_db_savepoint_basic() -> Int {
  let path = "orbitdb-suite-mvcc4.wal";
  tdb_cleanup(path);
  var db = db_file_open(path, 4);
  if !db_file_put(&mut db, 1, 10) { return 1; }
  if !db_file_txn_begin(&mut db) { return 2; }
  if !db_file_txn_put(&mut db, 2, 20) { return 3; }
  if !db_file_txn_put(&mut db, 3, 30) { return 4; }
  if !db_file_txn_savepoint(&mut db) { return 5; }
  if !db_file_txn_savepoint_active(&db) { return 6; }
  if !db_file_txn_put(&mut db, 4, 40) { return 7; }
  if !db_file_txn_delete(&mut db, 2) { return 8; }
  if !db_file_txn_savepoint_restore(&mut db) { return 9; }
  if !db_file_txn_savepoint_active(&db) { return 10; }
  if !db_file_txn_put(&mut db, 5, 50) { return 11; }
  if !db_file_txn_commit(&mut db) { return 12; }
  if db_file_txn_savepoint_active(&db) { return 13; }
  if db_file_size(&db) != 4 { return 14; }
  match db_file_get(&db, 2) { None => { return 15; } Some(v) => { if v != 20 { return 16; } } }
  match db_file_get(&db, 3) { None => { return 17; } Some(v) => { if v != 30 { return 18; } } }
  match db_file_get(&db, 4) { None => {} Some(_) => { return 19; } }
  match db_file_get(&db, 5) { None => { return 20; } Some(v) => { if v != 50 { return 21; } } }
  // Reopen == replay of the spliced window must agree with the buffer.
  var db2 = db_file_open(path, 4);
  if db_file_size(&db2) != 4 { return 22; }
  match db_file_get(&db2, 4) { None => {} Some(_) => { return 23; } }
  // Release path: ops after release survive.
  if !db_file_txn_begin(&mut db2) { return 24; }
  if !db_file_txn_put(&mut db2, 6, 60) { return 25; }
  if !db_file_txn_savepoint(&mut db2) { return 26; }
  if !db_file_txn_put(&mut db2, 7, 70) { return 27; }
  if !db_file_txn_savepoint_release(&mut db2) { return 28; }
  if db_file_txn_savepoint_active(&db2) { return 29; }
  if !db_file_txn_put(&mut db2, 8, 80) { return 30; }
  if !db_file_txn_commit(&mut db2) { return 31; }
  if db_file_size(&db2) != 7 { return 32; }
  match db_file_get(&db2, 7) { None => { return 33; } Some(v) => { if v != 70 { return 34; } } }
  tdb_cleanup(path);
  return 0;
}

fn test_db_savepoint_basic() -> TestResult {
  let rc = run_db_savepoint_basic();
  if rc == 0 { return assert(true, "db_file savepoint: restore trims post-marker ops; commit/reopen exact"); }
  return assert(false, "db_file savepoint: basic failed rc=" + int_to_str(rc));
}

fn run_db_savepoint_guards() -> Int {
  let path = "orbitdb-suite-mvcc5.wal";
  tdb_cleanup(path);
  var db = db_file_open(path, 4);
  if db_file_txn_savepoint(&mut db) { return 1; }
  if db_file_txn_savepoint_restore(&mut db) { return 2; }
  if db_file_txn_savepoint_release(&mut db) { return 3; }
  if db_file_txn_savepoint_active(&db) { return 4; }
  if !db_file_txn_begin(&mut db) { return 5; }
  if db_file_txn_savepoint_restore(&mut db) { return 6; }
  if !db_file_txn_savepoint(&mut db) { return 7; }
  if db_file_txn_savepoint(&mut db) { return 8; }
  if !db_file_txn_savepoint_restore(&mut db) { return 9; }
  if !db_file_txn_savepoint_active(&db) { return 10; }
  if !db_file_txn_savepoint_release(&mut db) { return 11; }
  if db_file_txn_savepoint_release(&mut db) { return 12; }
  if db_file_txn_savepoint_restore(&mut db) { return 13; }
  if !db_file_txn_commit(&mut db) { return 14; }
  if db_file_txn_savepoint_active(&db) { return 15; }
  if db_file_txn_savepoint_restore(&mut db) { return 16; }
  tdb_cleanup(path);
  return 0;
}

fn test_db_savepoint_guards() -> TestResult {
  let rc = run_db_savepoint_guards();
  if rc == 0 { return assert(true, "db_file savepoint: guard matrix (no txn, double begin, release, post-commit)"); }
  return assert(false, "db_file savepoint: guards failed rc=" + int_to_str(rc));
}

fn run_db_savepoint_crash_windows() -> Int {
  let path = "orbitdb-suite-mvcc6.wal";
  tdb_cleanup(path);
  var db = db_file_open(path, 4);
  if !db_file_put(&mut db, 1, 10) { return 1; }
  if !db_file_txn_begin(&mut db) { return 2; }
  if !db_file_txn_put(&mut db, 2, 20) { return 3; }
  if !db_file_txn_savepoint(&mut db) { return 4; }
  if !db_file_txn_put(&mut db, 3, 30) { return 5; }
  if !db_file_txn_delete(&mut db, 1) { return 6; }
  if !db_file_txn_savepoint_restore(&mut db) { return 7; }
  // Crash before commit: the abandoned handle's window is uncommitted, so a
  // fresh open recovers exactly key 1 (restore or not makes no difference).
  var db2 = db_file_open(path, 4);
  if db_file_size(&db2) != 1 { return 8; }
  match db_file_get(&db2, 1) { None => { return 9; } Some(v) => { if v != 10 { return 10; } } }
  match db_file_get(&db2, 2) { None => {} Some(_) => { return 11; } }
  // Commit after a restore applies exactly the kept ops.
  if !db_file_txn_begin(&mut db2) { return 12; }
  if !db_file_txn_put(&mut db2, 2, 20) { return 13; }
  if !db_file_txn_savepoint(&mut db2) { return 14; }
  if !db_file_txn_put(&mut db2, 3, 30) { return 15; }
  if !db_file_txn_savepoint_restore(&mut db2) { return 16; }
  if !db_file_txn_commit(&mut db2) { return 17; }
  var db3 = db_file_open(path, 4);
  if db_file_size(&db3) != 2 { return 18; }
  match db_file_get(&db3, 2) { None => { return 19; } Some(v) => { if v != 20 { return 20; } } }
  match db_file_get(&db3, 3) { None => {} Some(_) => { return 21; } }
  // Two restores then more ops: the final marker set is what commits.
  if !db_file_txn_begin(&mut db3) { return 22; }
  if !db_file_txn_put(&mut db3, 5, 50) { return 23; }
  if !db_file_txn_savepoint(&mut db3) { return 24; }
  if !db_file_txn_put(&mut db3, 6, 60) { return 25; }
  if !db_file_txn_savepoint_restore(&mut db3) { return 26; }
  if !db_file_txn_put(&mut db3, 7, 70) { return 27; }
  if !db_file_txn_savepoint_restore(&mut db3) { return 28; }
  if !db_file_txn_put(&mut db3, 8, 80) { return 29; }
  if !db_file_txn_commit(&mut db3) { return 30; }
  var db4 = db_file_open(path, 4);
  if db_file_size(&db4) != 4 { return 31; }
  match db_file_get(&db4, 5) { None => { return 32; } Some(v) => { if v != 50 { return 33; } } }
  match db_file_get(&db4, 6) { None => {} Some(_) => { return 34; } }
  match db_file_get(&db4, 7) { None => {} Some(_) => { return 35; } }
  match db_file_get(&db4, 8) { None => { return 36; } Some(v) => { if v != 80 { return 37; } } }
  tdb_cleanup(path);
  return 0;
}

fn test_db_savepoint_crash_windows() -> TestResult {
  let rc = run_db_savepoint_crash_windows();
  if rc == 0 { return assert(true, "db_file savepoint: crash windows (uncommitted discarded; restored commit exact)"); }
  return assert(false, "db_file savepoint: crash windows failed rc=" + int_to_str(rc));
}

fn run_db_snapshot_typed() -> Int {
  let path = "orbitdb-suite-mvcc7.wal";
  tdb_cleanup(path);
  var db = db_file_open(path, 4);
  if !db_file_put_typed(&mut db, 7, tdb_row3(1, 2, 3)) { return 1; }
  let s1 = db_file_snapshot_begin(&mut db);
  if !db_file_put_typed(&mut db, 7, tdb_row3(9, 9, 9)) { return 2; }
  if !db_file_put_typed(&mut db, 8, tdb_row3(4, 5, 6)) { return 3; }
  match db_file_snapshot_get_typed(&db, s1.id, 7) {
    None => { return 4; }
    Some(p) => { if p.len() != 3 { return 5; } if p[0] != 1 { return 6; } if p[2] != 3 { return 7; } }
  }
  match db_file_get_typed(&db, 7) {
    None => { return 8; }
    Some(p) => { if p.len() != 3 { return 9; } if p[0] != 9 { return 10; } }
  }
  match db_file_snapshot_get_typed(&db, s1.id, 8) { None => {} Some(_) => { return 11; } }
  if db_file_snapshot_count(&db, s1.id) != 1 { return 12; }
  if db_file_size(&db) != 2 { return 13; }
  if !db_file_snapshot_end(&mut db, s1.id) { return 14; }
  // A pinned payload view also survives a checkpoint while pinned.
  let s2 = db_file_snapshot_begin(&mut db);
  if db_file_checkpoint(&mut db) < 0 { return 15; }
  match db_file_snapshot_get_typed(&db, s2.id, 8) {
    None => { return 16; }
    Some(p) => { if p.len() != 3 { return 17; } if p[0] != 4 { return 18; } }
  }
  tdb_cleanup(path);
  return 0;
}

fn test_db_snapshot_typed() -> TestResult {
  let rc = run_db_snapshot_typed();
  if rc == 0 { return assert(true, "db_file snapshot: typed payloads pinned; survive checkpoint while pinned"); }
  return assert(false, "db_file snapshot: typed failed rc=" + int_to_str(rc));
}

// M1.2 S4 default flip: db_file_open now writes the v2 byte container; a v1
// file opened by default migrates on its next checkpoint; readers keep
// auto-detecting either format everywhere.
fn run_db_file_default_v2_flip() -> Int {
  let path = "orbitdb-suite-db-flip.wal";
  let snap = "orbitdb-suite-db-flip.wal.snap";
  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);

  // 1. Default open + checkpoint writes a v2 container (first byte 'O').
  var db = db_file_open(path, 4);
  var i = 1;
  while i <= 10 {
    if !db_file_put(&mut db, i, i * 7) { return 1; }
    i = i + 1;
  }
  if db_file_checkpoint(&mut db) < 0 { return 2; }
  match io.read_at(snap, 0, 1) {
    Err(_) => { return 3; }
    Ok(b) => {
      if b.len() != 1 { return 4; }
      if ((b[0] as Int) & 0xFF) != 0x4F { return 5; }
    }
  }

  // 2. Default reopen: v2 loads, data intact, further writes + checkpoint.
  var db2 = db_file_open(path, 4);
  if db_file_size(&db2) != 10 { return 6; }
  if !db_file_put(&mut db2, 11, 77) { return 7; }
  if db_file_checkpoint(&mut db2) < 0 { return 8; }

  // 3. Migration-on-write via the DEFAULT open: a v1 file flips to v2 at its
  //    next checkpoint and stays readable.
  let path1 = "orbitdb-suite-db-flip1.wal";
  let snap1 = "orbitdb-suite-db-flip1.wal.snap";
  let _ = io.remove_file(path1);
  let _ = io.remove_file(snap1);
  var v1 = db_file_open_cfg(path1, 4, 1);
  i = 1;
  while i <= 6 {
    if !db_file_put(&mut v1, i, i * 3) { return 9; }
    i = i + 1;
  }
  if db_file_checkpoint(&mut v1) < 0 { return 10; }
  match io.read_at(snap1, 0, 1) {
    Err(_) => { return 11; }
    Ok(b) => {
      if b.len() == 1 && ((b[0] as Int) & 0xFF) == 0x4F { return 12; }
    }
  }
  var m = db_file_open(path1, 4); // default = v2 handle on a v1 file
  if db_file_size(&m) != 6 { return 13; }
  if !db_file_put(&mut m, 7, 21) { return 14; }
  if db_file_checkpoint(&mut m) < 0 { return 15; } // migrates to v2
  match io.read_at(snap1, 0, 1) {
    Err(_) => { return 16; }
    Ok(b) => {
      if b.len() != 1 { return 17; }
      if ((b[0] as Int) & 0xFF) != 0x4F { return 18; }
    }
  }
  let v = db_file_open(path1, 4);
  if db_file_size(&v) != 7 { return 19; }
  match db_file_get(&v, 7) {
    None => { return 20; }
    Some(x) => { if x != 21 { return 21; } }
  }
  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);
  let _ = io.remove_file(path1);
  let _ = io.remove_file(snap1);
  return 0;
}

fn test_db_file_default_v2_flip() -> TestResult {
  let rc = run_db_file_default_v2_flip();
  if rc == 0 { return assert(true, "db_file: v2 is the default container; v1 migrates on default write"); }
  return assert(false, "db_file: default v2 flip failed rc=" + int_to_str(rc));
}

// ===========================================================================
// Durable page file (text v1, CRC32C verified, atomic rewrite)
// ===========================================================================

fn run_page_file_roundtrip() -> Int {
  let path = "orbitdb-suite-pages.tmp";
  let _ = io.remove_file(path);
  let pf = page_file_open(path);
  var d1 = Vec[Int].new();
  d1.push(1);
  d1.push(2);
  d1.push(3);
  let p1 = Page.new(10, d1, page_compute_checksum(&d1));
  if !page_file_write(&pf, p1) { return 1; }
  var d2 = Vec[Int].new();
  d2.push(200);
  let p2 = Page.new(11, d2, page_compute_checksum(&d2));
  if !page_file_write(&pf, p2) { return 1; }
  if page_file_count(&pf) != 2 { return 1; }
  let r1 = page_file_read(&pf, 10);
  match r1 {
    None => { return 1; }
    Some(p) => {
      let pg: Page = p;
      if !pg.is_valid() { return 1; }
      if pg.data.len() != 3 { return 1; }
    }
  }
  // Upsert the same id: count unchanged, new bytes.
  var d3 = Vec[Int].new();
  d3.push(9);
  let p3 = Page.new(10, d3, page_compute_checksum(&d3));
  if !page_file_write(&pf, p3) { return 1; }
  if page_file_count(&pf) != 2 { return 1; }
  let r3 = page_file_read(&pf, 10);
  match r3 {
    None => { return 1; }
    Some(p) => {
      let pg: Page = p;
      if !pg.is_valid() { return 1; }
      if pg.data.len() != 1 { return 1; }
      if pg.data[0] != 9 { return 1; }
    }
  }
  let _ = io.remove_file(path);
  return 0;
}

fn test_page_file_roundtrip() -> TestResult {
  let rc = run_page_file_roundtrip();
  if rc == 0 { return assert(true, "page_file: write/read/upsert/verify roundtrip"); }
  return assert(false, "page_file: roundtrip failed");
}

fn run_page_file_corruption() -> Int {
  let path = "orbitdb-suite-pages2.tmp";
  let _ = io.remove_file(path);
  let pf = page_file_open(path);
  var d = Vec[Int].new();
  d.push(5);
  d.push(6);
  let p = Page.new(1, d, page_compute_checksum(&d));
  if !page_file_write(&pf, p) { return 1; }
  // Malformed torn tail (no newline) must be skipped by count/read.
  let app = io.append_file(path, "88|5|");
  match app { Ok(_) => {}, Err(_) => { return 1; } }
  if page_file_count(&pf) != 1 { return 1; }
  let r = page_file_read(&pf, 1);
  match r {
    None => { return 1; }
    Some(g) => {
      let pg: Page = g;
      if !pg.is_valid() { return 1; }
    }
  }
  // Structurally valid but checksum-invalid line: not a page.
  let app2 = io.append_file(path, "\n99|1|123|7\n");
  match app2 { Ok(_) => {}, Err(_) => { return 1; } }
  let r99 = page_file_read(&pf, 99);
  match r99 { Some(_) => { return 1; }, None => {} }
  if page_file_count(&pf) != 1 { return 1; }
  let _ = io.remove_file(path);
  return 0;
}

fn test_page_file_corruption() -> TestResult {
  let rc = run_page_file_corruption();
  if rc == 0 { return assert(true, "page_file: torn tail + bad checksum rejected"); }
  return assert(false, "page_file: corruption handling failed");
}

fn run_page_log() -> Int {
  let path = "orbitdb-suite-pagelog.tmp";
  let _ = io.remove_file(path);
  let pf = page_file_open(path);

  // Two pages; id 5 gets a newer version afterwards.
  var d1 = Vec[Int].new();
  d1.push(1);
  d1.push(2);
  if !page_log_append(&pf, Page.new(5, d1, page_compute_checksum(&d1))) { return 1; }
  var d2 = Vec[Int].new();
  d2.push(9);
  if !page_log_append(&pf, Page.new(6, d2, page_compute_checksum(&d2))) { return 1; }
  var d3 = Vec[Int].new();
  d3.push(7);
  d3.push(8);
  if !page_log_append(&pf, Page.new(5, d3, page_compute_checksum(&d3))) { return 1; }
  if page_log_len(&pf) != 3 { return 1; }

  let latest = page_log_read_all(&pf);
  if latest.len() != 2 { return 1; }
  var found5 = false;
  var found6 = false;
  var i = 0;
  while i < latest.len() {
    let pg = latest[i];
    if pg.id == 5 {
      if pg.data.len() != 2 { return 1; }
      if pg.data[0] != 7 { return 1; }
      if pg.data[1] != 8 { return 1; }
      found5 = true;
    }
    if pg.id == 6 { found6 = true; }
    i = i + 1;
  }
  if !found5 { return 1; }
  if !found6 { return 1; }

  // Torn trailing line: skipped by readers, healed before the next append so
  // the partial line cannot merge with the new entry.
  let app = io.append_file(path, "77|3|");
  match app { Ok(_) => {}, Err(_) => { return 1; } }
  var d4 = Vec[Int].new();
  d4.push(42);
  if !page_log_heal_tail(&pf) { return 1; }
  if !page_log_append(&pf, Page.new(7, d4, page_compute_checksum(&d4))) { return 1; }
  if page_log_len(&pf) != 4 { return 1; }
  let after = page_log_read_all(&pf);
  if after.len() != 3 { return 1; }
  var found7 = false;
  var j = 0;
  while j < after.len() {
    let pg = after[j];
    if pg.id == 7 {
      if pg.data.len() != 1 { return 1; }
      if pg.data[0] != 42 { return 1; }
      found7 = true;
    }
    j = j + 1;
  }
  if !found7 { return 1; }

  let _ = io.remove_file(path);
  return 0;
}

fn test_page_log() -> TestResult {
  let rc = run_page_log();
  if rc == 0 { return assert(true, "page_log: append/latest-wins/torn-tail heal"); }
  return assert(false, "page_log: append/latest/torn failed");
}

// ===========================================================================
// File-backed database (WAL-before-ack + replay recovery)
// ===========================================================================

fn run_db_file_roundtrip() -> Int {
  let path = "orbitdb-suite-db.wal";
  let _ = io.remove_file(path);
  var db = db_file_open(path, 4);
  if !db_file_put(&mut db, 1, 10) { return 1; }
  if !db_file_put(&mut db, 2, 20) { return 1; }
  if !db_file_put(&mut db, 2, 99) { return 1; }   // update
  if !db_file_delete(&mut db, 1) { return 1; }
  if db_file_size(&db) != 1 { return 1; }
  if db_file_last_lsn(&db) != 4 { return 1; }
  if !db_file_flush(&mut db) { return 1; }

  // Reopen: replay must reproduce the final state exactly.
  var db2 = db_file_open(path, 4);
  if db_file_size(&db2) != 1 { return 1; }
  let v = db_file_get(&db2, 2);
  match v {
    None => { return 1; }
    Some(x) => { if x != 99 { return 1; } }
  }
  let gone = db_file_get(&db2, 1);
  match gone { Some(_) => { return 1; }, None => {} }
  let _ = io.remove_file(path);
  return 0;
}

fn test_db_file_roundtrip() -> TestResult {
  let rc = run_db_file_roundtrip();
  if rc == 0 { return assert(true, "db_file: put/update/delete survive reopen (WAL replay)"); }
  return assert(false, "db_file: roundtrip failed");
}

// ===========================================================================
// File-backed database: checkpoint/snapshot (node page codec + tail replay)
// ===========================================================================

fn run_db_file_checkpoint() -> Int {
  let path = "orbitdb-suite-db-ckpt.wal";
  let snap = "orbitdb-suite-db-ckpt.wal.snap";
  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);

  var db = db_file_open(path, 4);
  var i = 1;
  while i <= 12 {
    if !db_file_put(&mut db, i, i * 10) { return 1; }
    i = i + 1;
  }
  let ckpt = db_file_checkpoint(&mut db);
  if ckpt < 12 { return 1; }

  // Truncation kept exactly the Checkpoint anchor: no write records remain,
  // and the anchor's payload [generation, node_count, order] survived.
  if wal_file_len(path) != 1 { return 1; }
  let records = wal_file_replay(path);
  let r0 = records[0];
  if r0.lsn != ckpt { return 1; }
  if wal_op_code(r0.op) != 6 { return 1; }
  if r0.payload.len() != 3 { return 1; }

  // The 12 keys can only come from the snapshot now (the log has no write
  // records); LastLSN resumes from the anchor.
  var db2 = db_file_open(path, 4);
  if db_file_size(&db2) != 12 { return 1; }
  if db_file_last_lsn(&db2) != ckpt { return 1; }
  let v7 = db_file_get(&db2, 7);
  match v7 {
    None => { return 1; }
    Some(x) => { if x != 70 { return 1; } }
  }

  // A write after the checkpoint replays from the tail on the next open.
  if !db_file_put(&mut db2, 13, 130) { return 1; }
  var db3 = db_file_open(path, 4);
  if db_file_size(&db3) != 13 { return 1; }
  let v13 = db_file_get(&db3, 13);
  match v13 {
    None => { return 1; }
    Some(x) => { if x != 130 { return 1; } }
  }

  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);
  return 0;
}

fn test_db_file_checkpoint() -> TestResult {
  let rc = run_db_file_checkpoint();
  if rc == 0 { return assert(true, "db_file: checkpoint snapshot + tail replay + WAL truncate"); }
  return assert(false, "db_file: checkpoint roundtrip failed");
}

fn run_db_file_checkpoint_churn() -> Int {
  let path = "orbitdb-suite-db-ckpt2.wal";
  let snap = "orbitdb-suite-db-ckpt2.wal.snap";
  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);

  var db = db_file_open(path, 4);
  var i = 1;
  while i <= 20 {
    if !db_file_put(&mut db, i, i) { return 1; }
    i = i + 1;
  }
  // Churn before the snapshot: delete evens, update odds (exercises internal
  // split/merge node shapes in the node page codec).
  var k = 2;
  while k <= 20 {
    if !db_file_delete(&mut db, k) { return 1; }
    k = k + 2;
  }
  k = 1;
  while k <= 19 {
    if !db_file_put(&mut db, k, k * 100) { return 1; }
    k = k + 2;
  }
  if db_file_size(&db) != 10 { return 1; }

  let ckpt = db_file_checkpoint(&mut db);
  if ckpt < 0 { return 1; }
  // A second checkpoint must advance the generation and re-install atomically.
  let ckpt2 = db_file_checkpoint(&mut db);
  if ckpt2 <= ckpt { return 1; }

  var db2 = db_file_open(path, 4);
  if db_file_size(&db2) != 10 { return 1; }
  let gone = db_file_get(&db2, 2);
  match gone { Some(_) => { return 1; }, None => {} }
  let v19 = db_file_get(&db2, 19);
  match v19 {
    None => { return 1; }
    Some(x) => { if x != 1900 { return 1; } }
  }

  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);
  return 0;
}

fn test_db_file_checkpoint_churn() -> TestResult {
  let rc = run_db_file_checkpoint_churn();
  if rc == 0 { return assert(true, "db_file: checkpoint survives churn + re-checkpoint (generation)"); }
  return assert(false, "db_file: checkpoint churn failed");
}

fn run_db_file_v2_snapshot() -> Int {
  let path = "orbitdb-suite-db-v2.wal";
  let snap = "orbitdb-suite-db-v2.wal.snap";
  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);

  var db = db_file_open_cfg(path, 4, 2);
  if db.page_format != 2 { return 1; }
  var i = 1;
  while i <= 40 {
    if !db_file_put(&mut db, i, i * 3) { return 1; }
    i = i + 1;
  }
  let ckpt = db_file_checkpoint(&mut db);
  if ckpt < 0 { return 1; }
  // Dirty-only append path: a second checkpoint must advance the generation.
  i = 1;
  while i <= 10 {
    if !db_file_put(&mut db, i, i * 7) { return 1; }
    i = i + 1;
  }
  let ckpt2 = db_file_checkpoint(&mut db);
  if ckpt2 <= ckpt { return 1; }

  // Reopen with the DEFAULT v1 handle: reads auto-detect the v2 file.
  var db2 = db_file_open(path, 4);
  if db_file_size(&db2) != 40 { return 1; }
  let v5 = db_file_get(&db2, 5);
  match v5 {
    None => { return 1; }
    Some(x) => { if x != 35 { return 1; } }
  }
  let v30 = db_file_get(&db2, 30);
  match v30 {
    None => { return 1; }
    Some(x) => { if x != 90 { return 1; } }
  }
  // A v1-handle checkpoint on a v2 file rewrites it whole as v1 (the
  // on-disk format stays authoritative), and reads keep working.
  if !db_file_put(&mut db2, 41, 410) { return 1; }
  let ckpt3 = db_file_checkpoint(&mut db2);
  if ckpt3 < 0 { return 1; }
  var db3 = db_file_open(path, 4);
  if db_file_size(&db3) != 41 { return 1; }

  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);
  return 0;
}

fn test_db_file_v2_snapshot() -> TestResult {
  let rc = run_db_file_v2_snapshot();
  if rc == 0 { return assert(true, "db_file v2: byte-snapshot append + auto-detect + format flip"); }
  return assert(false, "db_file v2: snapshot roundtrip failed");
}

fn run_db_file_v2_migrate() -> Int {
  let path = "orbitdb-suite-db-v2m.wal";
  let snap = "orbitdb-suite-db-v2m.wal.snap";
  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);

  // Build a v1 snapshot, then migrate it in place (twice: idempotent).
  var db = db_file_open(path, 4);
  var i = 1;
  while i <= 25 {
    if !db_file_put(&mut db, i, i + 100) { return 1; }
    i = i + 1;
  }
  if db_file_checkpoint(&mut db) < 0 { return 1; }
  let _ = io.remove_file(path);

  if !db_file_migrate_snapshot(path) { return 1; }
  if !db_file_migrate_snapshot(path) { return 1; }

  var db2 = db_file_open(path, 4);
  if db_file_size(&db2) != 25 { return 1; }
  let v13 = db_file_get(&db2, 13);
  match v13 {
    None => { return 1; }
    Some(x) => { if x != 113 { return 1; } }
  }

  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);
  return 0;
}

fn test_db_file_v2_migrate() -> TestResult {
  let rc = run_db_file_v2_migrate();
  if rc == 0 { return assert(true, "db_file v2: v1 snapshot migrated in place (idempotent)"); }
  return assert(false, "db_file v2: migration failed");
}

fn run_db_file_query_range() -> Int {
  let path = "orbitdb-suite-db-q.wal";
  let snap = "orbitdb-suite-db-q.wal.snap";
  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);

  var db = db_file_open(path, 4);
  var i = 1;
  while i <= 12 {
    if !db_file_put(&mut db, i, i * 10) { return 1; }
    i = i + 1;
  }

  // Live handle: key range in order, then a value-filter query with
  // offset/limit (conditions filter VALUES -- pinned semantics).
  let r = db_file_range(&db, 3, 6);
  if r.len() != 4 { return 1; }
  if r[0] != 30 { return 1; }
  if r[1] != 40 { return 1; }
  if r[2] != 50 { return 1; }
  if r[3] != 60 { return 1; }

  var q = query_new();
  query_where(&mut q, QueryOp.Gte, 10);
  query_offset(&mut q, 2);
  query_limit(&mut q, 3);
  let filtered = db_file_query(&db, &q);
  if filtered.len() != 3 { return 1; }
  if filtered[0] != 30 { return 1; }
  if filtered[1] != 40 { return 1; }
  if filtered[2] != 50 { return 1; }

  var q2 = query_new();
  query_where(&mut q2, QueryOp.Lt, 30);
  let small = db_file_query(&db, &q2);
  if small.len() != 2 { return 1; }
  if small[0] != 10 { return 1; }
  if small[1] != 20 { return 1; }

  // Checkpoint, then a tail write: the reopened handle must answer queries
  // from the snapshot + tail replay (not from a fresh empty tree).
  if db_file_checkpoint(&mut db) < 0 { return 1; }
  if !db_file_put(&mut db, 13, 130) { return 1; }

  var db2 = db_file_open(path, 4);
  if db_file_size(&db2) != 13 { return 1; }
  let r2 = db_file_range(&db2, 12, 13);
  if r2.len() != 2 { return 1; }
  if r2[0] != 120 { return 1; }
  if r2[1] != 130 { return 1; }
  var q3 = query_new();
  query_where(&mut q3, QueryOp.Eq, 130);
  let eq = db_file_query(&db2, &q3);
  if eq.len() != 1 { return 1; }
  if eq[0] != 130 { return 1; }

  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);
  return 0;
}

fn test_db_file_query_range() -> TestResult {
  let rc = run_db_file_query_range();
  if rc == 0 { return assert(true, "db_file: range + filtered query (live, snapshot + tail recovery)"); }
  return assert(false, "db_file: query/range failed");
}

fn run_db_file_incremental_checkpoint() -> Int {
  let path = "orbitdb-suite-db-inc.wal";
  let snap = "orbitdb-suite-db-inc.wal.snap";
  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);

  // v1 page-log mechanics test: keep an explicit v1 handle after the M1.2 S4
  // default flip (db_file_open now defaults to the v2 byte container).
  var db = db_file_open_cfg(path, 4, 1);
  var i = 1;
  while i <= 12 {
    if !db_file_put(&mut db, i, i * 10) { return 1; }
    i = i + 1;
  }
  let c1 = db_file_checkpoint(&mut db);
  if c1 < 12 { return 1; }
  let pf = page_file_open(snap);
  let entries1 = page_log_len(&pf);

  // No mutation -> the second checkpoint commits a header entry only.
  let c2 = db_file_checkpoint(&mut db);
  if c2 <= c1 { return 1; }
  let entries2 = page_log_len(&pf);
  if entries2 != entries1 + 1 { return 1; }

  // A torn trailing append must be healed before the next checkpoint appends,
  // or the first new entry would merge with it and be lost.
  let app = io.append_file(snap, "12|3|");
  match app { Ok(_) => {}, Err(_) => { return 1; } }
  if !db_file_put(&mut db, 13, 130) { return 1; }
  let c3 = db_file_checkpoint(&mut db);
  if c3 <= c2 { return 1; }

  var db2 = db_file_open_cfg(path, 4, 1);
  if db_file_size(&db2) != 13 { return 1; }
  let v13 = db_file_get(&db2, 13);
  match v13 {
    None => { return 1; }
    Some(x) => { if x != 130 { return 1; } }
  }
  let v1 = db_file_get(&db2, 1);
  match v1 {
    None => { return 1; }
    Some(x) => { if x != 10 { return 1; } }
  }

  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);
  return 0;
}

fn test_db_file_incremental_checkpoint() -> TestResult {
  let rc = run_db_file_incremental_checkpoint();
  if rc == 0 { return assert(true, "db_file: incremental checkpoint (no-op delta + torn-tail heal)"); }
  return assert(false, "db_file: incremental checkpoint failed");
}

// Node page bytes for the bogus uncommitted-generation page (codec v1).
fn snap_test_leaf_bytes(keys: Vec[Int], values: Vec[Int]) -> Vec[Int] {
  var out = Vec[Int].new();
  out.push(0x4F);
  out.push(1);
  out.push(0x4E);
  out.push(1);
  tuple_push_int_le(&mut out, keys.len());
  tuple_push_int_le(&mut out, 0);
  tuple_push_int_le(&mut out, 0);
  var i = 0;
  while i < keys.len() {
    tuple_push_int_le(&mut out, keys[i]);
    i = i + 1;
  }
  i = 0;
  while i < values.len() {
    tuple_push_int_le(&mut out, values[i]);
    i = i + 1;
  }
  return out;
}

fn run_db_file_uncommitted_generation() -> Int {
  let path = "orbitdb-suite-db-uncommitted.wal";
  let snap = "orbitdb-suite-db-uncommitted.wal.snap";
  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);

  var db = db_file_open(path, 4);
  var i = 1;
  while i <= 12 {
    if !db_file_put(&mut db, i, i * 10) { return 1; }
    i = i + 1;
  }
  if db_file_checkpoint(&mut db) < 0 { return 1; }

  // Crash window simulation: a node page from the NEXT generation was
  // appended, but its header never was. It must be ignored on load.
  let pf = page_file_open(snap);
  var keys = Vec[Int].new();
  keys.push(999);
  var values = Vec[Int].new();
  values.push(9990);
  let bytes = snap_test_leaf_bytes(keys, values);
  let bogus_id = 2 * SNAP_PAGE_STRIDE + 1; // generation 2, node 0
  if !page_log_append(&pf, Page.new(bogus_id, bytes, page_compute_checksum(&bytes))) { return 1; }

  var db2 = db_file_open(path, 4);
  if db_file_size(&db2) != 12 { return 1; }
  let phantom = db_file_get(&db2, 999);
  match phantom { Some(_) => { return 1; }, None => {} }

  // The next checkpoint must not let the stale generation-2 page leak into
  // the committed generation: it forces a full write of generation 2.
  if !db_file_put(&mut db2, 5, 55) { return 1; }
  if db_file_checkpoint(&mut db2) < 0 { return 1; }

  var db3 = db_file_open(path, 4);
  if db_file_size(&db3) != 12 { return 1; }
  let v5 = db_file_get(&db3, 5);
  match v5 {
    None => { return 1; }
    Some(x) => { if x != 55 { return 1; } }
  }
  let still = db_file_get(&db3, 999);
  match still { Some(_) => { return 1; }, None => {} }

  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);
  return 0;
}

fn test_db_file_uncommitted_generation() -> TestResult {
  let rc = run_db_file_uncommitted_generation();
  if rc == 0 { return assert(true, "db_file: uncommitted generation ignored + stale flush handled"); }
  return assert(false, "db_file: uncommitted generation failed");
}

fn run_db_file_checkpoint_policy() -> Int {
  let path = "orbitdb-suite-db-policy.wal";
  let snap = "orbitdb-suite-db-policy.wal.snap";
  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);

  var db = db_file_open(path, 4);
  var i = 1;
  while i <= 3 {
    if !db_file_put(&mut db, i, i * 10) { return 1; }
    i = i + 1;
  }
  if db_file_maybe_checkpoint(&mut db, 5) != -1 { return 1; }

  var j = 4;
  while j <= 6 {
    if !db_file_put(&mut db, j, j * 10) { return 1; }
    j = j + 1;
  }
  let anchor = db_file_maybe_checkpoint(&mut db, 5);
  if anchor < 6 { return 1; }
  // The counter reset: below threshold again, and the WAL holds the anchor.
  if db_file_maybe_checkpoint(&mut db, 5) != -1 { return 1; }
  if wal_file_len(path) != 1 { return 1; }

  var db2 = db_file_open(path, 4);
  if db_file_size(&db2) != 6 { return 1; }

  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);
  return 0;
}

fn test_db_file_checkpoint_policy() -> TestResult {
  let rc = run_db_file_checkpoint_policy();
  if rc == 0 { return assert(true, "db_file: maybe_checkpoint threshold + counter reset"); }
  return assert(false, "db_file: checkpoint policy failed");
}

fn run_db_file_compaction() -> Int {
  let path = "orbitdb-suite-db-compact.wal";
  let snap = "orbitdb-suite-db-compact.wal.snap";
  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);

  var db = db_file_open(path, 4);
  var i = 1;
  while i <= 8 {
    if !db_file_put(&mut db, i, i * 10) { return 1; }
    i = i + 1;
  }
  if db_file_checkpoint(&mut db) < 0 { return 1; }

  // Repeated no-op checkpoints grow the log by one header each; once it
  // passes node_count + 64, the next checkpoint must compact (atomic batch
  // rewrite to one page per node).
  var c = 0;
  while c < 70 {
    if db_file_checkpoint(&mut db) < 0 { return 1; }
    c = c + 1;
  }

  let pf = page_file_open(snap);
  let entries = page_log_len(&pf);
  // Without compaction the log would hold ~78 entries; after compaction it is
  // one page per node + a header plus the post-compaction headers (< 20).
  if entries > 25 { return 1; }

  var db2 = db_file_open(path, 4);
  if db_file_size(&db2) != 8 { return 1; }
  let v8 = db_file_get(&db2, 8);
  match v8 {
    None => { return 1; }
    Some(x) => { if x != 80 { return 1; } }
  }
  // The compacted snapshot must keep accepting writes + checkpoints.
  if !db_file_put(&mut db2, 9, 90) { return 1; }
  if db_file_checkpoint(&mut db2) < 0 { return 1; }
  var db3 = db_file_open(path, 4);
  if db_file_size(&db3) != 9 { return 1; }

  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);
  return 0;
}

fn test_db_file_compaction() -> TestResult {
  let rc = run_db_file_compaction();
  if rc == 0 { return assert(true, "db_file: log compaction at node_count + 64"); }
  return assert(false, "db_file: compaction failed");
}

fn run_db_file_txn_commit() -> Int {
  let path = "orbitdb-suite-db-txn.wal";
  let snap = "orbitdb-suite-db-txn.wal.snap";
  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);

  var db = db_file_open(path, 4);
  var i = 1;
  while i <= 3 {
    if !db_file_put(&mut db, i, i * 10) { return 1; }
    i = i + 1;
  }

  if !db_file_txn_begin(&mut db) { return 1; }
  if !db_file_txn_active(&db) { return 1; }
  // Buffered ops are NOT visible before the commit.
  if !db_file_txn_put(&mut db, 10, 100) { return 1; }
  if !db_file_txn_put(&mut db, 11, 110) { return 1; }
  if !db_file_txn_delete(&mut db, 2) { return 1; }
  let hidden = db_file_get(&db, 10);
  match hidden { Some(_) => { return 1; }, None => {} }
  if db_file_size(&db) != 3 { return 1; }

  if !db_file_txn_commit(&mut db) { return 1; }
  if db_file_txn_active(&db) { return 1; }
  if db_file_size(&db) != 4 { return 1; } // 1, 3, 10, 11
  let v10 = db_file_get(&db, 10);
  match v10 {
    None => { return 1; }
    Some(x) => { if x != 100 { return 1; } }
  }
  let gone = db_file_get(&db, 2);
  match gone { Some(_) => { return 1; }, None => {} }

  // Reopen: the committed transaction replays as applied (durable path).
  var db2 = db_file_open(path, 4);
  if db_file_size(&db2) != 4 { return 1; }
  let v11 = db_file_get(&db2, 11);
  match v11 {
    None => { return 1; }
    Some(x) => { if x != 110 { return 1; } }
  }
  let v1 = db_file_get(&db2, 1);
  match v1 {
    None => { return 1; }
    Some(x) => { if x != 10 { return 1; } }
  }

  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);
  return 0;
}

fn test_db_file_txn_commit() -> TestResult {
  let rc = run_db_file_txn_commit();
  if rc == 0 { return assert(true, "db_file: txn commit buffered -> applied -> replayed"); }
  return assert(false, "db_file: txn commit failed");
}

fn run_db_file_txn_abort_guards() -> Int {
  let path = "orbitdb-suite-db-txn2.wal";
  let snap = "orbitdb-suite-db-txn2.wal.snap";
  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);

  var db = db_file_open(path, 4);
  var i = 1;
  while i <= 3 {
    if !db_file_put(&mut db, i, i * 10) { return 1; }
    i = i + 1;
  }
  let c0 = db_file_checkpoint(&mut db);
  if c0 < 0 { return 1; }

  if !db_file_txn_begin(&mut db) { return 1; }
  // Guards: checkpoint (explicit + threshold-reached) and auto-commit writes
  // are all rejected while the transaction is active.
  if db_file_checkpoint(&mut db) != -1 { return 1; }
  if db_file_maybe_checkpoint(&mut db, 1) != -1 { return 1; }
  if db_file_put(&mut db, 99, 990) { return 1; }
  if db_file_delete(&mut db, 1) { return 1; }

  if !db_file_txn_put(&mut db, 20, 200) { return 1; }
  if !db_file_txn_abort(&mut db) { return 1; }
  if db_file_txn_active(&db) { return 1; }
  let v20 = db_file_get(&db, 20);
  match v20 { Some(_) => { return 1; }, None => {} }
  if db_file_size(&db) != 3 { return 1; }

  // Reopen: the aborted transaction leaves no trace.
  var db2 = db_file_open(path, 4);
  if db_file_size(&db2) != 3 { return 1; }

  // Double begin/commit/abort misuse is rejected; checkpoint works again.
  if !db_file_txn_begin(&mut db2) { return 1; }
  if db_file_txn_begin(&mut db2) { return 1; }
  if !db_file_txn_commit(&mut db2) { return 1; }
  if db_file_txn_commit(&mut db2) { return 1; }
  if db_file_txn_abort(&mut db2) { return 1; }
  if db_file_checkpoint(&mut db2) < 0 { return 1; }

  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);
  return 0;
}

fn test_db_file_txn_abort_guards() -> TestResult {
  let rc = run_db_file_txn_abort_guards();
  if rc == 0 { return assert(true, "db_file: txn abort discards + checkpoint/auto-commit guards"); }
  return assert(false, "db_file: txn abort/guards failed");
}

fn run_db_file_dangling_txn_abort() -> Int {
  let path = "orbitdb-suite-db-txn3.wal";
  let snap = "orbitdb-suite-db-txn3.wal.snap";
  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);

  // A segment that looks like a crash mid-transaction: base write, BeginTxn,
  // two ops, no Commit.
  var w = wal_file_open(path);
  // This compilation unit imports BOTH wal_file's WALOpKind and txn's WALOp,
  // which share variant names -- qualification here is disambiguation, not the
  // C-ORBIT-04 workaround (that one is reverted in src/).
  let _ = wal_file_append(&mut w, WALOpKind.Insert, 1, 10);
  let _ = wal_file_append(&mut w, WALOpKind.BeginTxn, 0, 0);
  let _ = wal_file_append(&mut w, WALOpKind.Update, 2, 20);
  let _ = wal_file_append(&mut w, WALOpKind.Update, 3, 30);

  var db = db_file_open(path, 4);
  if db_file_size(&db) != 1 { return 1; } // txn ops discarded
  let v2 = db_file_get(&db, 2);
  match v2 { Some(_) => { return 1; }, None => {} }

  // Opening finalizes the dangling txn with an Abort record, so the next
  // auto-commit write is NOT attributed to the stale window on replay.
  if !db_file_put(&mut db, 4, 40) { return 1; }
  var db2 = db_file_open(path, 4);
  if db_file_size(&db2) != 2 { return 1; } // 1 and 4; txn ops stay out
  let v4 = db_file_get(&db2, 4);
  match v4 {
    None => { return 1; }
    Some(x) => { if x != 40 { return 1; } }
  }
  let v3 = db_file_get(&db2, 3);
  match v3 { Some(_) => { return 1; }, None => {} }

  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);
  return 0;
}

fn test_db_file_dangling_txn_abort() -> TestResult {
  let rc = run_db_file_dangling_txn_abort();
  if rc == 0 { return assert(true, "db_file: dangling txn finalized with Abort on open"); }
  return assert(false, "db_file: dangling txn finalize failed");
}

fn run_db_path_validation() -> Int {
  if db_path_valid("") { return 1; }
  if !db_path_valid("orbitdb-suite-path.wal") { return 1; }
  if !db_path_valid("sub/dir/db.wal") { return 1; }
  if db_path_valid("bad\nname.wal") { return 1; }
  if db_path_valid("bad\rname.wal") { return 1; }

  var long = "";
  var i = 0;
  while i < 4100 {
    long = long + "a";
    i = i + 1;
  }
  if db_path_valid(long) { return 1; }
  return 0;
}

fn test_db_path_validation() -> TestResult {
  let rc = run_db_path_validation();
  if rc == 0 { return assert(true, "db_file: path validation (empty/CR/LF/overlong)"); }
  return assert(false, "db_file: path validation failed");
}

fn run_db_file_open_checked() -> Int {
  let path = "orbitdb-suite-db-checked.wal";
  let snap = "orbitdb-suite-db-checked.wal.snap";
  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);

  let bad_path = db_file_open_checked("", 4);
  match bad_path {
    Ok(_) => { return 1; }
    Err(_) => {}
  }
  let bad_order = db_file_open_checked(path, 2);
  match bad_order {
    Ok(_) => { return 1; }
    Err(_) => {}
  }
  let bad_newline = db_file_open_checked("bad\nname.wal", 4);
  match bad_newline {
    Ok(_) => { return 1; }
    Err(_) => {}
  }

  // Valid input: the Ok payload (cross-module generic -- C-ORBIT-01 rebind)
  // really is a usable handle.
  let good = db_file_open_checked(path, 4);
  var usable = false;
  match good {
    Err(_) => {}
    Ok(d) => {
      let handle: DBFile = d;
      if db_file_size(&handle) == 0 { usable = true; }
    }
  }
  if !usable { return 1; }

  var db = db_file_open(path, 4);
  if !db_file_put(&mut db, 1, 10) { return 1; }
  if db_file_checkpoint(&mut db) < 0 { return 1; }
  var db2 = db_file_open(path, 4);
  if db_file_size(&db2) != 1 { return 1; }
  let v = db_file_get(&db2, 1);
  match v {
    None => { return 1; }
    Some(x) => { if x != 10 { return 1; } }
  }

  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);
  return 0;
}

fn test_db_file_open_checked() -> TestResult {
  let rc = run_db_file_open_checked();
  if rc == 0 { return assert(true, "db_file: checked open rejects bad path/order, accepts valid"); }
  return assert(false, "db_file: checked open failed");
}

fn run_db_file_stale_handle() -> Int {
  let path = "orbitdb-suite-db-stale.wal";
  let snap = "orbitdb-suite-db-stale.wal.snap";
  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);

  var db1 = db_file_open(path, 4);
  var db2 = db_file_open(path, 4);

  // db1 writes; db2 is now stale and must refuse every write path.
  if !db_file_put(&mut db1, 1, 10) { return 1; }
  if db_file_put(&mut db2, 2, 20) { return 1; }
  if db_file_delete(&mut db2, 1) { return 1; }
  if db_file_txn_begin(&mut db2) { return 1; }
  if db_file_checkpoint(&mut db2) != -1 { return 1; }

  // db1 continues to work (it is the only writer).
  if !db_file_put(&mut db1, 3, 30) { return 1; }
  if !db_file_txn_begin(&mut db1) { return 1; }
  if !db_file_txn_put(&mut db1, 4, 40) { return 1; }
  if !db_file_txn_commit(&mut db1) { return 1; }
  if db_file_size(&db1) != 3 { return 1; } // 1, 3, 4

  // A fresh handle opens, then the established writer writes first: the fresh
  // handle is stale before it ever writes (first writer wins).
  var db3 = db_file_open(path, 4);
  if !db_file_put(&mut db1, 5, 50) { return 1; }
  if db_file_put(&mut db3, 6, 60) { return 1; }
  if db_file_txn_begin(&mut db3) { return 1; }

  // The established writer can checkpoint; the stale handle cannot.
  if db_file_checkpoint(&mut db1) < 0 { return 1; }
  if db_file_checkpoint(&mut db3) != -1 { return 1; }

  var db4 = db_file_open(path, 4);
  if db_file_size(&db4) != 4 { return 1; } // 1, 3, 4, 5
  let v5 = db_file_get(&db4, 5);
  match v5 {
    None => { return 1; }
    Some(x) => { if x != 50 { return 1; } }
  }
  let v6 = db_file_get(&db4, 6);
  match v6 { Some(_) => { return 1; }, None => {} }

  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);
  return 0;
}

fn test_db_file_stale_handle() -> TestResult {
  let rc = run_db_file_stale_handle();
  if rc == 0 { return assert(true, "db_file: stale handle refuses writes + checkpoint"); }
  return assert(false, "db_file: stale-handle guard failed");
}

fn run_db_file_dirty_flush() -> Int {
  let path = "orbitdb-suite-db-dirty.wal";
  let snap = "orbitdb-suite-db-dirty.wal.snap";
  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);

  // v1 page-log mechanics test: explicit v1 handle after the M1.2 S4 flip.
  var db = db_file_open_cfg(path, 4, 1);
  var i = 1;
  while i <= 12 {
    if !db_file_put(&mut db, i, i * 10) { return 1; }
    i = i + 1;
  }
  let c1 = db_file_checkpoint(&mut db);
  if c1 < 0 { return 1; }
  let pf = page_file_open(snap);
  let entries1 = page_log_len(&pf);
  if entries1 < 5 { return 1; } // several nodes + header

  // One key update (delete+insert) must flush only the touched path nodes.
  if !db_file_put(&mut db, 5, 55) { return 1; }
  let c2 = db_file_checkpoint(&mut db);
  if c2 <= c1 { return 1; }
  let entries2 = page_log_len(&pf);
  let delta = entries2 - entries1;
  if delta < 2 { return 1; }      // header + at least one node
  if delta > 4 { return 1; }      // a few path nodes, never a full rewrite
  if delta >= entries1 { return 1; }

  // A no-op checkpoint still appends the header only.
  let c3 = db_file_checkpoint(&mut db);
  if c3 <= c2 { return 1; }
  let entries3 = page_log_len(&pf);
  if entries3 - entries2 != 1 { return 1; }

  var db2 = db_file_open_cfg(path, 4, 1);
  if db_file_size(&db2) != 12 { return 1; }
  let v5 = db_file_get(&db2, 5);
  match v5 {
    None => { return 1; }
    Some(x) => { if x != 55 { return 1; } }
  }

  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);
  return 0;
}

fn test_db_file_dirty_flush() -> TestResult {
  let rc = run_db_file_dirty_flush();
  if rc == 0 { return assert(true, "db_file: checkpoint flushes only dirty nodes (bounded delta)"); }
  return assert(false, "db_file: dirty-flush failed");
}

// ===========================================================================
// Durability API + fault injector (M2.1 first half). The env-armed injector
// is test-only (src/storage/fault.xi); `syncfail` makes the next sync report
// failure, which must latch the handle and refuse writers until reopen.
// ===========================================================================

fn run_db_file_durability_api() -> Int {
  let path = "orbitdb-suite-db-dura.wal";
  let snap = "orbitdb-suite-db-dura.wal.snap";
  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);

  var db = db_file_open(path, 4);
  if db_file_durability(&db) != 1 { return 1; }  // immediate is the default
  if db_file_two_phase(&db) { return 2; }
  if db_file_failed(&db) { return 3; }

  // Invalid modes are rejected; a valid set sticks to the handle.
  if db_file_set_durability(&mut db, 2) { return 4; }
  if db_file_set_durability(&mut db, -1) { return 5; }
  if !db_file_set_durability(&mut db, 0) { return 6; }
  if db_file_durability(&db) != 0 { return 7; }

  // Two-phase is immediate-only.
  if db_file_set_two_phase(&mut db, true) { return 8; }
  if !db_file_set_durability(&mut db, 1) { return 9; }
  if !db_file_set_two_phase(&mut db, true) { return 10; }
  if !db_file_two_phase(&db) { return 11; }
  if !db_file_set_two_phase(&mut db, false) { return 12; }
  if db_file_two_phase(&db) { return 13; }

  // Writes work in both modes; flush is the seam call and reports success.
  if !db_file_put(&mut db, 1, 100) { return 14; }
  if !db_file_set_durability(&mut db, 0) { return 15; }
  if !db_file_put(&mut db, 2, 200) { return 16; }
  if !db_file_flush(&mut db) { return 17; }
  if db_file_failed(&db) { return 18; }

  // Reopen resets to defaults; data survives.
  var db2 = db_file_open(path, 4);
  if db_file_durability(&db2) != 1 { return 19; }
  if db_file_two_phase(&db2) { return 20; }
  if db_file_size(&db2) != 2 { return 21; }
  match db_file_get(&db2, 1) {
    None => { return 22; }
    Some(v) => { if v != 100 { return 23; } }
  }
  match db_file_get(&db2, 2) {
    None => { return 24; }
    Some(v) => { if v != 200 { return 25; } }
  }

  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);
  return 0;
}

fn test_db_file_durability_api() -> TestResult {
  let rc = run_db_file_durability_api();
  if rc == 0 { return assert(true, "db_file: durability API defaults/setters + reopen reset"); }
  return assert(false, "db_file: durability API failed rc=" + int_to_str(rc));
}

fn run_db_file_syncfail_latch() -> Int {
  let path = "orbitdb-suite-db-syncfail.wal";
  let snap = "orbitdb-suite-db-syncfail.wal.snap";
  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);

  var db = db_file_open(path, 4);
  if !db_file_put(&mut db, 1, 10) { return 1; }

  // The next sync fails: the put's WAL record lands but the ack flush does
  // not, so the commit reports false and the handle latches.
  env.set_var("ORBITDB_FAULT_AT", "1");
  env.set_var("ORBITDB_FAULT_MODE", "syncfail");
  fault_reset();
  if db_file_put(&mut db, 2, 20) { return 2; }
  if !db_file_failed(&db) { return 3; }

  // Latched writers refuse until reopen.
  if db_file_put(&mut db, 3, 30) { return 4; }
  if db_file_delete(&mut db, 1) { return 5; }
  if db_file_txn_begin(&mut db) { return 6; }
  if db_file_checkpoint(&mut db) >= 0 { return 7; }
  if db_file_flush(&mut db) { return 8; }

  // Disarm, reopen: the WAL record for key 2 was written before the failed
  // sync (WAL-before-ack), so recovery must produce it.
  env.remove_var("ORBITDB_FAULT_AT");
  env.remove_var("ORBITDB_FAULT_MODE");
  fault_reset();

  var db2 = db_file_open(path, 4);
  if db_file_failed(&db2) { return 9; }
  if db_file_size(&db2) != 2 { return 10; }
  match db_file_get(&db2, 2) {
    None => { return 11; }
    Some(v) => { if v != 20 { return 12; } }
  }

  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);
  return 0;
}

fn test_db_file_syncfail_latch() -> TestResult {
  let rc = run_db_file_syncfail_latch();
  if rc == 0 { return assert(true, "db_file: syncfail latches the handle; reopen recovers the record"); }
  return assert(false, "db_file: syncfail latch failed rc=" + int_to_str(rc));
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

fn test_result_set_ops() -> TestResult {
  let rc = run_result_set_ops();
  if rc == 0 { return assert(true, "tuple: ResultSet add/row_count/get_row"); }
  return assert(false, "tuple: ResultSet ops failed");
}

// ===========================================================================
// Block codec v2 (M1.2 S1): layout KAT, roundtrip/boundaries, corruption
// matrix, header slots. Design: docs/BYTE-PAGE-FORMAT-V2.md.
// ===========================================================================

fn vdup(v: &Vec[Int]) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 0;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
  return out;
}

fn set_le8(v: &mut Vec[Int], off: Int, val: Int) {
  var i = 0;
  while i < 8 {
    v[off + i] = (val >> (8 * i)) & 0xFF;
    i = i + 1;
  }
}

fn run_block_v2_kat() -> Int {
  var payload = Vec[Int].new();
  payload.push(1);
  payload.push(2);
  payload.push(3);
  let b = block_encode_page(0x0102030405060708, 0x1112131415161718, &payload);
  if b.len() != 4096 { return 1; }
  if b[0] != 0x4F || b[1] != 0x50 || b[2] != 0x47 || b[3] != 0x32 { return 2; }
  if b[4] != 2 || b[5] != 0x50 || b[6] != 0 || b[7] != 0 { return 3; }
  if b[8] != 8 || b[9] != 7 || b[10] != 6 || b[11] != 5 { return 4; }
  if b[12] != 4 || b[13] != 3 || b[14] != 2 || b[15] != 1 { return 4; }
  if b[16] != 0x18 || b[17] != 0x17 || b[18] != 0x16 || b[19] != 0x15 { return 5; }
  if b[20] != 0x14 || b[21] != 0x13 || b[22] != 0x12 || b[23] != 0x11 { return 5; }
  if b[24] != 3 || b[25] != 0 || b[26] != 0 || b[27] != 0 { return 6; }
  if b[28] != 0 || b[29] != 0 || b[30] != 0 || b[31] != 0 { return 7; }
  let crc = page_compute_checksum(&payload);
  if b[32] != (crc & 0xFF) || b[33] != ((crc >> 8) & 0xFF) { return 8; }
  if b[34] != ((crc >> 16) & 0xFF) || b[35] != ((crc >> 24) & 0xFF) { return 8; }
  if b[36] != 0 || b[37] != 0 || b[38] != 0 || b[39] != 0 { return 8; }
  if b[40] != 1 || b[41] != 2 || b[42] != 3 || b[43] != 0 { return 9; }
  if b[4095] != 0 { return 10; }
  return 0;
}

fn run_block_v2_roundtrip() -> Int {
  var empty = Vec[Int].new();
  let b0 = block_encode_page(0, 7, &empty);
  match block_decode_page(&b0) {
    Some(p) => {
      if p.payload.len() != 0 || p.page_id != 7 || p.generation != 0 { return 1; }
    }
    None => { return 1; }
  }
  var big = Vec[Int].new();
  var i = 0;
  while i < block_payload_capacity() {
    big.push(i % 256);
    i = i + 1;
  }
  let b1 = block_encode_page(9, 12345, &big);
  match block_decode_page(&b1) {
    Some(p) => {
      if p.payload.len() != big.len() || p.generation != 9 || p.page_id != 12345 { return 2; }
      var j = 0;
      while j < big.len() {
        if p.payload[j] != big[j] { return 2; }
        j = j + 1;
      }
    }
    None => { return 2; }
  }
  var over = Vec[Int].new();
  i = 0;
  while i <= block_payload_capacity() {
    over.push(0);
    i = i + 1;
  }
  if block_encode_page(1, 1, &over).len() != 0 { return 3; }
  var badbyte = Vec[Int].new();
  badbyte.push(256);
  if block_encode_page(1, 1, &badbyte).len() != 0 { return 3; }
  match block_decode(&b0) {
    Some(v) => {
      if v.kind != 0x50 { return 4; }
    }
    None => { return 4; }
  }
  if block_kind_is_free(&b0) { return 5; }
  var freeb = vdup(&b0);
  freeb[5] = 0x46;
  if !block_kind_is_free(&freeb) { return 5; }
  return 0;
}

fn run_block_v2_rejects() -> Int {
  var empty = Vec[Int].new();
  let good = block_encode_page(3, 9, &empty);
  var short = Vec[Int].new();
  var i = 0;
  while i < 4095 {
    short.push(good[i]);
    i = i + 1;
  }
  match block_decode(&short) {
    Some(_) => { return 1; }
    None => {}
  }
  var t = vdup(&good);
  t[0] = 0;
  match block_decode(&t) {
    Some(_) => { return 2; }
    None => {}
  }
  t = vdup(&good);
  t[4] = 3;
  match block_decode(&t) {
    Some(_) => { return 2; }
    None => {}
  }
  t = vdup(&good);
  t[5] = 0x51;
  match block_decode(&t) {
    Some(_) => { return 2; }
    None => {}
  }
  t = vdup(&good);
  t[7] = 1;
  match block_decode(&t) {
    Some(_) => { return 2; }
    None => {}
  }
  t = vdup(&good);
  set_le8(&mut t, 24, block_payload_capacity() + 1);
  match block_decode(&t) {
    Some(_) => { return 2; }
    None => {}
  }
  t = vdup(&good);
  t[32] = (t[32] + 1) & 0xFF;
  match block_decode(&t) {
    Some(_) => { return 2; }
    None => {}
  }
  t = vdup(&good);
  t[40] = 1;
  match block_decode(&t) {
    Some(_) => { return 2; }
    None => {}
  }
  return 0;
}

fn run_block_v2_header() -> Int {
  var empty = Vec[Int].new();
  let pb = block_encode_page(3, 9, &empty);
  let h = BlockHeader{
    root: 5,
    order: 4,
    node_count: 100,
    checkpoint_lsn: 42,
    committed_generation: 7,
    block_count: 3,
    next_page_id: 101,
  };
  let b = block_encode_header(&h);
  if b.len() != 4096 { return 1; }
  if b[5] != 0x48 { return 1; }
  match block_decode_header(&b) {
    Some(h2) => {
      if h2.root != 5 || h2.order != 4 || h2.node_count != 100 { return 1; }
      if h2.checkpoint_lsn != 42 || h2.committed_generation != 7 { return 1; }
      if h2.block_count != 3 || h2.next_page_id != 101 { return 1; }
    }
    None => { return 1; }
  }
  // committed_generation != block stamp, CRC re-sealed: decode must still
  // reject (the payload/block cross-check).
  var t = vdup(&b);
  set_le8(&mut t, 76, 8);
  var pl = Vec[Int].new();
  var i = 0;
  while i < 64 {
    pl.push(t[40 + i]);
    i = i + 1;
  }
  set_le8(&mut t, 32, page_compute_checksum(&pl));
  match block_decode_header(&t) {
    Some(_) => { return 2; }
    None => {}
  }
  // kind exclusivity
  match block_decode_header(&pb) {
    Some(_) => { return 3; }
    None => {}
  }
  match block_decode_page(&b) {
    Some(_) => { return 3; }
    None => {}
  }
  return 0;
}

fn test_block_v2_kat() -> TestResult {
  let rc = run_block_v2_kat();
  if rc == 0 { return assert(true, "block v2: layout KAT (magic/version/kind/LE fields/CRC)"); }
  return assert(false, "block v2: layout KAT failed rc=" + int_to_str(rc));
}

fn test_block_v2_roundtrip() -> TestResult {
  let rc = run_block_v2_roundtrip();
  if rc == 0 { return assert(true, "block v2: payload roundtrip + capacity boundaries"); }
  return assert(false, "block v2: roundtrip failed rc=" + int_to_str(rc));
}

fn test_block_v2_rejects() -> TestResult {
  let rc = run_block_v2_rejects();
  if rc == 0 { return assert(true, "block v2: corruption matrix rejects (None)"); }
  return assert(false, "block v2: rejection matrix failed rc=" + int_to_str(rc));
}

fn test_block_v2_header() -> TestResult {
  let rc = run_block_v2_header();
  if rc == 0 { return assert(true, "block v2: header slot roundtrip + cross-checks"); }
  return assert(false, "block v2: header failed rc=" + int_to_str(rc));
}

// ===========================================================================
// Secondary indexes + ORDER/LIMIT (M4.2)
// ===========================================================================

fn vecs_eq(a: &Vec[Int], b: &Vec[Int]) -> Bool {
  if a.len() != b.len() { return false; }
  var i = 0;
  while i < a.len() {
    if a[i] != b[i] { return false; }
    i = i + 1;
  }
  return true;
}

fn run_secondary_index_build() -> Int {
  let path = "orbitdb-suite-idx.wal";
  let snap = "orbitdb-suite-idx.wal.snap";
  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);
  var db = db_file_open(path, 4);
  // values with duplicates: (1,10) (2,20) (3,10) (4,30) (5,20)
  if !db_file_put(&mut db, 1, 10) { return 1; }
  if !db_file_put(&mut db, 2, 20) { return 1; }
  if !db_file_put(&mut db, 3, 10) { return 1; }
  if !db_file_put(&mut db, 4, 30) { return 1; }
  if !db_file_put(&mut db, 5, 20) { return 1; }
  if !db_file_create_index(&mut db, "by_value") { return 1; }
  if db_file_index_count(&db) != 1 { return 1; }
  if !(db_file_index_name(&db, 0) == "by_value") { return 2; }
  let all = db_file_index_range(&db, "by_value", 10, 20);
  var want = Vec[Int].new();
  want.push(1);
  want.push(3);
  want.push(2);
  want.push(5);
  if !vecs_eq(&all, &want) { return 3; }
  let eq10 = db_file_index_range(&db, "by_value", 10, 10);
  var want10 = Vec[Int].new();
  want10.push(1);
  want10.push(3);
  if !vecs_eq(&eq10, &want10) { return 4; }
  let miss = db_file_index_range(&db, "by_value", 99, 99);
  if miss.len() != 0 { return 5; }
  if db_file_create_index(&mut db, "by_value") { return 6; }
  if db_file_create_index(&mut db, "") { return 7; }
  if !db_file_drop_index(&mut db, "by_value") { return 8; }
  if db_file_index_count(&db) != 0 { return 9; }
  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);
  return 0;
}

fn test_secondary_index_build() -> TestResult {
  let rc = run_secondary_index_build();
  if rc == 0 { return assert(true, "index: build + (value, pk) range probes + dup/empty/drop guards"); }
  return assert(false, "index: build failed rc=" + int_to_str(rc));
}

fn run_secondary_index_maintenance() -> Int {
  let path = "orbitdb-suite-idxm.wal";
  let snap = "orbitdb-suite-idxm.wal.snap";
  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);
  var db = db_file_open(path, 4);
  if !db_file_put(&mut db, 1, 10) { return 1; }
  if !db_file_put(&mut db, 2, 20) { return 1; }
  if !db_file_put(&mut db, 3, 10) { return 1; }
  if !db_file_put(&mut db, 4, 30) { return 1; }
  if !db_file_put(&mut db, 5, 20) { return 1; }
  if !db_file_create_index(&mut db, "by_value") { return 1; }

  // update moves (2,20) -> (2,25)
  if !db_file_put(&mut db, 2, 25) { return 2; }
  let at20 = db_file_index_range(&db, "by_value", 20, 20);
  var want20 = Vec[Int].new();
  want20.push(5);
  if !vecs_eq(&at20, &want20) { return 3; }
  let at25 = db_file_index_range(&db, "by_value", 25, 25);
  var want25 = Vec[Int].new();
  want25.push(2);
  if !vecs_eq(&at25, &want25) { return 4; }

  // delete removes (3,10)
  if !db_file_delete(&mut db, 3) { return 5; }
  let at10 = db_file_index_range(&db, "by_value", 10, 10);
  var want10 = Vec[Int].new();
  want10.push(1);
  if !vecs_eq(&at10, &want10) { return 6; }

  // transaction commit mirrors upserts and deletes
  if !db_file_txn_begin(&mut db) { return 7; }
  if !db_file_txn_put(&mut db, 6, 10) { return 7; }
  if !db_file_txn_put(&mut db, 4, 100) { return 7; }
  if !db_file_txn_delete(&mut db, 1) { return 7; }
  if !db_file_txn_commit(&mut db) { return 7; }
  let at10b = db_file_index_range(&db, "by_value", 10, 10);
  var want10b = Vec[Int].new();
  want10b.push(6);
  if !vecs_eq(&at10b, &want10b) { return 8; }
  let at100 = db_file_index_range(&db, "by_value", 100, 100);
  var want100 = Vec[Int].new();
  want100.push(4);
  if !vecs_eq(&at100, &want100) { return 9; }
  let at30 = db_file_index_range(&db, "by_value", 30, 30);
  if at30.len() != 0 { return 10; }

  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);
  return 0;
}

fn test_secondary_index_maintenance() -> TestResult {
  let rc = run_secondary_index_maintenance();
  if rc == 0 { return assert(true, "index: maintained by put/update/delete + txn commit"); }
  return assert(false, "index: maintenance failed rc=" + int_to_str(rc));
}

fn run_query_index_plan() -> Int {
  let path = "orbitdb-suite-idxq.wal";
  let snap = "orbitdb-suite-idxq.wal.snap";
  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);
  var db = db_file_open(path, 4);
  var i = 1;
  while i <= 60 {
    if !db_file_put(&mut db, i, i * 10) { return 1; }
    i = i + 1;
  }
  // update a few so values are not strictly key-ordered
  if !db_file_put(&mut db, 5, 550) { return 1; }
  if !db_file_put(&mut db, 40, 40) { return 1; }

  var q = query_new();
  query_where(&mut q, QueryOp.Gte, 300);
  query_where(&mut q, QueryOp.Lt, 420);
  let no_idx = db_file_query(&db, &q);

  if !db_file_create_index(&mut db, "by_value") { return 2; }
  let plan = plan_query_with_index(&q, &db.tree, true);
  if plan.kind != PlanKind.IndexValue { return 3; }
  let with_idx = db_file_query(&db, &q);
  if !vecs_eq(&no_idx, &with_idx) { return 4; }
  // IndexValue bounds came from the first usable condition (Gte 300).
  if plan.low != 300 { return 5; }

  // Eq condition -> point-sized estimate
  var qe = query_new();
  query_where(&mut qe, QueryOp.Eq, 550);
  let plan_e = plan_query_with_index(&qe, &db.tree, true);
  if plan_e.kind != PlanKind.IndexValue || plan_e.estimated_rows != 1 { return 6; }
  let eq_res = db_file_query(&db, &qe);
  // value 550 exists at keys 5 (updated) and 55 (natural) -> key order
  var want_eq = Vec[Int].new();
  want_eq.push(550);
  want_eq.push(550);
  if !vecs_eq(&eq_res, &want_eq) { return 7; }

  // Neq alone is not index-usable -> full scan
  var qn = query_new();
  query_where(&mut qn, QueryOp.Neq, 0);
  let plan_n = plan_query_with_index(&qn, &db.tree, true);
  if plan_n.kind != PlanKind.FullScan { return 8; }

  // Key bounds keep precedence over the value index
  var qb = query_new();
  query_where(&mut qb, QueryOp.Gte, 300);
  query_key_range(&mut qb, 10, 20);
  let plan_b = plan_query_with_index(&qb, &db.tree, true);
  if plan_b.kind != PlanKind.IndexRange { return 9; }

  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);
  return 0;
}

fn test_query_index_plan() -> TestResult {
  let rc = run_query_index_plan();
  if rc == 0 { return assert(true, "index: planner picks IndexValue (bounded) + codec-equivalent results"); }
  return assert(false, "index: plan selection failed rc=" + int_to_str(rc));
}

fn run_query_order_limit() -> Int {
  let path = "orbitdb-suite-idxo.wal";
  let snap = "orbitdb-suite-idxo.wal.snap";
  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);
  var db = db_file_open(path, 4);
  // (key, value): 1->30, 2->10, 3->20, 4->10, 5->40
  if !db_file_put(&mut db, 1, 30) { return 1; }
  if !db_file_put(&mut db, 2, 10) { return 1; }
  if !db_file_put(&mut db, 3, 20) { return 1; }
  if !db_file_put(&mut db, 4, 10) { return 1; }
  if !db_file_put(&mut db, 5, 40) { return 1; }

  // default: key ascending -> values [30,10,20,10,40]
  var q0 = query_new();
  let r0 = db_file_query(&db, &q0);
  var w0 = Vec[Int].new();
  w0.push(30); w0.push(10); w0.push(20); w0.push(10); w0.push(40);
  if !vecs_eq(&r0, &w0) { return 2; }

  // value ascending, ties keep key order -> [10(k2),10(k4),20,30,40]
  var q1 = query_new();
  query_order(&mut q1, 1);
  let r1 = db_file_query(&db, &q1);
  var w1 = Vec[Int].new();
  w1.push(10); w1.push(10); w1.push(20); w1.push(30); w1.push(40);
  if !vecs_eq(&r1, &w1) { return 3; }

  // value descending -> [40,30,20,10,10]
  var q2 = query_new();
  query_order(&mut q2, 2);
  let r2 = db_file_query(&db, &q2);
  var w2 = Vec[Int].new();
  w2.push(40); w2.push(30); w2.push(20); w2.push(10); w2.push(10);
  if !vecs_eq(&r2, &w2) { return 4; }

  // order + offset + limit: value asc, skip 1, take 2 -> [10,20]
  var q3 = query_new();
  query_order(&mut q3, 1);
  query_offset(&mut q3, 1);
  query_limit(&mut q3, 2);
  let r3 = db_file_query(&db, &q3);
  var w3 = Vec[Int].new();
  w3.push(10); w3.push(20);
  if !vecs_eq(&r3, &w3) { return 5; }

  // with the value index installed the same queries stay identical
  if !db_file_create_index(&mut db, "by_value") { return 6; }
  let r1i = db_file_query(&db, &q1);
  let r2i = db_file_query(&db, &q2);
  let r3i = db_file_query(&db, &q3);
  if !vecs_eq(&r1i, &w1) { return 7; }
  if !vecs_eq(&r2i, &w2) { return 8; }
  if !vecs_eq(&r3i, &w3) { return 9; }

  let _ = io.remove_file(path);
  let _ = io.remove_file(snap);
  return 0;
}

fn test_query_order_limit() -> TestResult {
  let rc = run_query_order_limit();
  if rc == 0 { return assert(true, "query: ORDER (key/value, asc/desc) + LIMIT/OFFSET, index and scan paths"); }
  return assert(false, "query: order/limit failed rc=" + int_to_str(rc));
}

// ===========================================================================
// Main
// ===========================================================================

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
  let r30b = test_checksum_crc32c_kat();
  total = total + 1; failed = failed + report(r30b.passed, r30b.name);

  // 7. Buffer pool
  let r31 = test_buffer_pool_new();
  total = total + 1; failed = failed + report(r31.passed, r31.name);
  let r32 = test_buffer_pool_put_get();
  total = total + 1; failed = failed + report(r32.passed, r32.name);
  let r33 = test_buffer_pool_miss();
  total = total + 1; failed = failed + report(r33.passed, r33.name);
  let r34 = test_buffer_pool_hit_ratio();
  total = total + 1; failed = failed + report(r34.passed, r34.name);
  let r34a = test_buffer_pool_clock();
  total = total + 1; failed = failed + report(r34a.passed, r34a.name);
  let r34b = test_buffer_pool_pin();
  total = total + 1; failed = failed + report(r34b.passed, r34b.name);
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
  let r66a = test_query_planner_kinds();
  total = total + 1; failed = failed + report(r66a.passed, r66a.name);
  let r66b = test_query_planner_property();
  total = total + 1; failed = failed + report(r66b.passed, r66b.name);

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
  let r73b = test_btree_churn_order4();
  total = total + 1; failed = failed + report(r73b.passed, r73b.name);
  let r73c = test_btree_churn_order5();
  total = total + 1; failed = failed + report(r73c.passed, r73c.name);
  let r73d = test_btree_churn_order3();
  total = total + 1; failed = failed + report(r73d.passed, r73d.name);

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
  let r89b = test_fsm_best_fit();
  total = total + 1; failed = failed + report(r89b.passed, r89b.name);
  let r89c = test_fsm_clamps_release();
  total = total + 1; failed = failed + report(r89c.passed, r89c.name);
  let r90 = test_row_new_and_access();
  total = total + 1; failed = failed + report(r90.passed, r90.name);
  let r91 = test_row_set_column();
  total = total + 1; failed = failed + report(r91.passed, r91.name);
  let r92 = test_tuple_encode_decode();
  total = total + 1; failed = failed + report(r92.passed, r92.name);
  let r92b = test_tuple_codec_kat();
  total = total + 1; failed = failed + report(r92b.passed, r92b.name);
  let r92c = test_tuple_codec_extremes();
  total = total + 1; failed = failed + report(r92c.passed, r92c.name);
  let r92d = test_tuple_codec_rejects();
  total = total + 1; failed = failed + report(r92d.passed, r92d.name);
  let r93a = test_page_file_roundtrip();
  total = total + 1; failed = failed + report(r93a.passed, r93a.name);
  let r93b = test_page_file_corruption();
  total = total + 1; failed = failed + report(r93b.passed, r93b.name);
  let r93c = test_page_log();
  total = total + 1; failed = failed + report(r93c.passed, r93c.name);
  let r94 = test_db_file_roundtrip();
  total = total + 1; failed = failed + report(r94.passed, r94.name);
  let r95a = test_db_file_checkpoint();
  total = total + 1; failed = failed + report(r95a.passed, r95a.name);
  let r95b = test_db_file_checkpoint_churn();
  total = total + 1; failed = failed + report(r95b.passed, r95b.name);
  let r96 = test_db_file_query_range();
  total = total + 1; failed = failed + report(r96.passed, r96.name);
  let r97a = test_db_file_incremental_checkpoint();
  total = total + 1; failed = failed + report(r97a.passed, r97a.name);
  let r97b = test_db_file_uncommitted_generation();
  total = total + 1; failed = failed + report(r97b.passed, r97b.name);
  let r97c = test_db_file_checkpoint_policy();
  total = total + 1; failed = failed + report(r97c.passed, r97c.name);
  let r97d = test_db_file_compaction();
  total = total + 1; failed = failed + report(r97d.passed, r97d.name);
  let r98a = test_db_file_txn_commit();
  total = total + 1; failed = failed + report(r98a.passed, r98a.name);
  let r98b = test_db_file_txn_abort_guards();
  total = total + 1; failed = failed + report(r98b.passed, r98b.name);
  let r98c = test_db_file_dangling_txn_abort();
  total = total + 1; failed = failed + report(r98c.passed, r98c.name);
  let r99a = test_db_path_validation();
  total = total + 1; failed = failed + report(r99a.passed, r99a.name);
  let r99b = test_db_file_open_checked();
  total = total + 1; failed = failed + report(r99b.passed, r99b.name);
  let r99c = test_db_file_stale_handle();
  total = total + 1; failed = failed + report(r99c.passed, r99c.name);
  let r100 = test_db_file_dirty_flush();
  total = total + 1; failed = failed + report(r100.passed, r100.name);
  // Durability API + fault injector (M2.1 first half)
  let r100a = test_db_file_durability_api();
  total = total + 1; failed = failed + report(r100a.passed, r100a.name);
  let r100b = test_db_file_syncfail_latch();
  total = total + 1; failed = failed + report(r100b.passed, r100b.name);
  let r93 = test_result_set_ops();
  total = total + 1; failed = failed + report(r93.passed, r93.name);

  // Block v2 codec (M1.2 S1)
  let r101 = test_block_v2_kat();
  total = total + 1; failed = failed + report(r101.passed, r101.name);
  let r102 = test_block_v2_roundtrip();
  total = total + 1; failed = failed + report(r102.passed, r102.name);
  let r103 = test_block_v2_rejects();
  total = total + 1; failed = failed + report(r103.passed, r103.name);
  let r104 = test_block_v2_header();
  total = total + 1; failed = failed + report(r104.passed, r104.name);

  // db_file v2 snapshot container (M1.2 S3)
  let r105 = test_db_file_v2_snapshot();
  total = total + 1; failed = failed + report(r105.passed, r105.name);
  let r106 = test_db_file_v2_migrate();
  total = total + 1; failed = failed + report(r106.passed, r106.name);

  // Secondary indexes + ORDER/LIMIT (M4.2)
  let r107 = test_secondary_index_build();
  total = total + 1; failed = failed + report(r107.passed, r107.name);
  let r108 = test_secondary_index_maintenance();
  total = total + 1; failed = failed + report(r108.passed, r108.name);
  let r109 = test_query_index_plan();
  total = total + 1; failed = failed + report(r109.passed, r109.name);
  let r110 = test_query_order_limit();
  total = total + 1; failed = failed + report(r110.passed, r110.name);

  // Tuple codec v2 -- typed values (M5.1)
  let r111 = test_tuple2_kat();
  total = total + 1; failed = failed + report(r111.passed, r111.name);
  let r112 = test_tuple2_roundtrip();
  total = total + 1; failed = failed + report(r112.passed, r112.name);
  let r113 = test_tuple2_rejects();
  total = total + 1; failed = failed + report(r113.passed, r113.name);
  let r114 = test_tuple2_budget();
  total = total + 1; failed = failed + report(r114.passed, r114.name);

  // Schema-driven rows (M5.2)
  let r115 = test_schema_row_kinds();
  total = total + 1; failed = failed + report(r115.passed, r115.name);
  let r116 = test_schema_row_roundtrip();
  total = total + 1; failed = failed + report(r116.passed, r116.name);
  let r117 = test_schema_row_rejects();
  total = total + 1; failed = failed + report(r117.passed, r117.name);
  let r118 = test_schema_row_bool_and_empty();
  total = total + 1; failed = failed + report(r118.passed, r118.name);

  // Typed rows in the engine (M5.3)
  let r119 = test_db_typed_roundtrip();
  total = total + 1; failed = failed + report(r119.passed, r119.name);
  let r120 = test_db_typed_checkpoint_v1();
  total = total + 1; failed = failed + report(r120.passed, r120.name);
  let r121 = test_db_typed_checkpoint_v2();
  total = total + 1; failed = failed + report(r121.passed, r121.name);
  let r122 = test_db_typed_budget_and_guards();
  total = total + 1; failed = failed + report(r122.passed, r122.name);
  let r123 = test_db_typed_txn_window_replay();
  total = total + 1; failed = failed + report(r123.passed, r123.name);

  // Typed comparisons + typed queries (M5-S4)
  let r124 = test_tuple2_compare();
  total = total + 1; failed = failed + report(r124.passed, r124.name);
  let r125 = test_typed_query_ops();
  total = total + 1; failed = failed + report(r125.passed, r125.name);
  let r126 = test_typed_query_persistence();
  total = total + 1; failed = failed + report(r126.passed, r126.name);

  // M3 minimal subset: snapshot pins + savepoints
  let r127 = test_db_snapshot_isolation();
  total = total + 1; failed = failed + report(r127.passed, r127.name);
  let r128 = test_db_snapshot_cow_churn();
  total = total + 1; failed = failed + report(r128.passed, r128.name);
  let r129 = test_db_snapshot_checkpoint();
  total = total + 1; failed = failed + report(r129.passed, r129.name);
  let r130 = test_db_savepoint_basic();
  total = total + 1; failed = failed + report(r130.passed, r130.name);
  let r131 = test_db_savepoint_guards();
  total = total + 1; failed = failed + report(r131.passed, r131.name);
  let r132 = test_db_savepoint_crash_windows();
  total = total + 1; failed = failed + report(r132.passed, r132.name);
  let r133 = test_db_snapshot_typed();
  total = total + 1; failed = failed + report(r133.passed, r133.name);
  let r134 = test_db_file_default_v2_flip();
  total = total + 1; failed = failed + report(r134.passed, r134.name);

  let passed = total - failed;
  io.println("");
  io.println("XIOM DB Conformance: " + int_to_str(passed) +
             "/" + int_to_str(total) + " passed" +
             (if failed > 0 { " (" + int_to_str(failed) + " FAILED)" } else { "" }));
  return failed;
}
