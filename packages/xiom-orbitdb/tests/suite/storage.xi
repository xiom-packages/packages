// XIOM ORBITDB -- conformance suite split: storage (R2, 2026-10-18).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom_db_conformance_storage

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

fn main() -> Int {
  io.println("=== XIOM DB Conformance: storage ===");
  var failed: Int = 0;
  var total: Int = 0;
  let r25 = test_page_construction();
  total = total + 1; failed = failed + report(r25.passed, r25.name);
  let r26 = test_page_is_valid();
  total = total + 1; failed = failed + report(r26.passed, r26.name);
  let r27 = test_page_is_valid_corrupt();
  total = total + 1; failed = failed + report(r27.passed, r27.name);
  let r28 = test_page_empty();
  total = total + 1; failed = failed + report(r28.passed, r28.name);
  let r29 = test_checksum_determinism();
  total = total + 1; failed = failed + report(r29.passed, r29.name);
  let r30 = test_checksum_different_data();
  total = total + 1; failed = failed + report(r30.passed, r30.name);
  let r30b = test_checksum_crc32c_kat();
  total = total + 1; failed = failed + report(r30b.passed, r30b.name);
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
  let r93 = test_result_set_ops();
  total = total + 1; failed = failed + report(r93.passed, r93.name);
  let passed = total - failed;
  io.println("XIOM DB Conformance [storage]: " + int_to_str(passed) + "/" + int_to_str(total) + " passed" + (if failed > 0 { " (" + int_to_str(failed) + " FAILED)" } else { "" }));
  return failed;
}