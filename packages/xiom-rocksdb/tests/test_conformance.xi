// XIOM -- xiom.rocksdb conformance tests (24 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API: memtable ordering/duplicates/size accounting,
// deterministic skiplist shape, snapshot visibility and tombstones; WAL
// append/sync policies/durability/replay; SST build (blocks, index, Bloom
// shape), table lookup and bounds; version level structure, size targets,
// per-mille scores and the deterministic picker; compaction (L0->L1,
// bounded rounds, bottom-level tombstone drop, snapshot-safe dedup, deep
// overlap selection); engine put/get/delete/lookup/sequence/statistics;
// column families; snapshots; the snapshot iterator and range scans; flush
// and the bounded maintenance scheduler.
//
// Every fixture is built in-test; no external data files. Str equality uses
// compare.str_compare (BUG-17 discipline), all Vec reads use typed locals
// and byte reads widen with `(b as Int) & 0xFF`. Test dispatch is direct
// (trap 5: no indexed Vec[fn] tables).

module rocksdb_tests

use xiom.io;
use xiom.test;
use xiom.rocksdb;
use xiom.string;
use xiom.string.compare;
use xiom.convert;

// --------------------------------------------------
//  Helpers
// --------------------------------------------------

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn text(s: Str) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < s.len() {
    v.push(string.byte_at(s, i));
    i = i + 1;
  }
  return v;
}

fn bytes_eq(a: &Vec[UInt8], b: &Vec[UInt8]) -> Bool {
  if a.len() != b.len() { return false; }
  var i = 0;
  while i < a.len() {
    let av = (a[i] as Int) & 0xFF;
    let bv = (b[i] as Int) & 0xFF;
    if av != bv { return false; }
    i = i + 1;
  }
  return true;
}

fn eq_text(v: &Vec[UInt8], s: Str) -> Bool {
  let want = text(s);
  return bytes_eq(v, &want);
}

fn err_not_found(r: Result[Vec[UInt8], Str]) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, "rocksdb: not found");
}

fn get_eq(db: &mut RocksDbDb, key: &Vec[UInt8], want: Str) -> Bool {
  let r = rocksdb_get(db, key);
  if !r.is_ok { return false; }
  let v: Vec[UInt8] = r.value;
  return eq_text(&v, want);
}

fn key_text(mt: &RocksDbMemtable, i: Int) -> Vec[UInt8] {
  return rocksdb_memtable_entry_key(mt, i);
}

// Build a memtable with `n` default-cf entries: key "k<i>" = "v<i>",
// sequences 1..n.
fn make_mt(n: Int) -> RocksDbMemtable {
  var mt = rocksdb_memtable_new(65536);
  var i = 0;
  while i < n {
    let ks = "k" + convert.int_to_string(i);
    let vs = "v" + convert.int_to_string(i);
    let kb = text(ks);
    let vb = text(vs);
    rocksdb_memtable_put(&mut mt, 0, &kb, &vb, i + 1, 1);
    i = i + 1;
  }
  return mt;
}

// Build a table from `n` fresh entries with file number `fnum`.
fn make_table(n: Int, fnum: Int) -> RocksDbTable {
  let mt = make_mt(n);
  return rocksdb_table_build(&mt, fnum, 4, 8, 3);
}

// --------------------------------------------------
//  t1: memtable order, duplicate versions, size accounting
// --------------------------------------------------

fn t1() -> TestResult {
  let name = "memtable: sorted insert, duplicate versions, size accounting";
  var ok = true;
  var mt = rocksdb_memtable_new(1024);
  let pb = rocksdb_memtable_put(&mut mt, 0, &text("b"), &text("2"), 2, 1);
  if pb != 0 { ok = false; }
  rocksdb_memtable_put(&mut mt, 0, &text("a"), &text("1"), 1, 1);
  rocksdb_memtable_put(&mut mt, 0, &text("c"), &text("3"), 3, 1);
  rocksdb_memtable_put(&mut mt, 0, &text("a"), &text("1b"), 4, 1);
  if rocksdb_memtable_count(&mt) != 4 { ok = false; }
  if rocksdb_memtable_bytes(&mt) != 73 { ok = false; }
  if !eq_text(&key_text(&mt, 0), "a") { ok = false; }
  if rocksdb_memtable_entry_seq(&mt, 0) != 4 { ok = false; }
  if rocksdb_memtable_entry_seq(&mt, 1) != 1 { ok = false; }
  if !eq_text(&key_text(&mt, 2), "b") { ok = false; }
  if !eq_text(&key_text(&mt, 3), "c") { ok = false; }
  if !rocksdb_memtable_is_sorted(&mt) { ok = false; }
  if rocksdb_memtable_find(&mt, 0, &text("a"), 0) != -1 { ok = false; }
  if rocksdb_memtable_find(&mt, 0, &text("a"), 2) != 1 { ok = false; }
  if rocksdb_memtable_find(&mt, 0, &text("a"), 4) != 0 { ok = false; }
  if rocksdb_memtable_find(&mt, 0, &text("z"), 9) != -1 { ok = false; }
  var empty = Vec[UInt8].new();
  if rocksdb_memtable_put(&mut mt, 0, &empty, &text("x"), 5, 1) != -1 { ok = false; }
  if rocksdb_memtable_put(&mut mt, 0, &text("k"), &text("v"), 6, 7) != -1 { ok = false; }
  if rocksdb_memtable_put(&mut mt, 0, &text("k"), &text("v"), -1, 1) != -1 { ok = false; }
  var small = rocksdb_memtable_new(64);
  rocksdb_memtable_put(&mut small, 0, &text("a"), &text("1"), 1, 1);
  rocksdb_memtable_put(&mut small, 0, &text("b"), &text("2"), 2, 1);
  if rocksdb_memtable_is_full(&small) { ok = false; }
  rocksdb_memtable_put(&mut small, 0, &text("c"), &text("3"), 3, 1);
  rocksdb_memtable_put(&mut small, 0, &text("d"), &text("4"), 4, 1);
  if !rocksdb_memtable_is_full(&small) { ok = false; }
  if !rocksdb_memtable_should_flush(&small) { ok = false; }
  if rocksdb_memtable_capacity(&small) != 64 { ok = false; }
  if rocksdb_memtable_capacity(&rocksdb_memtable_new(10)) != 64 { ok = false; }
  return assert(ok, name);
}

// --------------------------------------------------
//  t2: skiplist shape (deterministic heights, level counts)
// --------------------------------------------------

fn t2() -> TestResult {
  let name = "memtable: skiplist shape (deterministic heights, level counts)";
  var ok = true;
  var mt = rocksdb_memtable_new(4096);
  var i = 0;
  while i < 8 {
    let ks = "k" + convert.int_to_string(i);
    let kb = text(ks);
    rocksdb_memtable_put(&mut mt, 0, &kb, &text("v"), i + 1, 1);
    i = i + 1;
  }
  if rocksdb_memtable_count(&mt) != 8 { ok = false; }
  var h = 0;
  i = 0;
  while i < 8 {
    let e = rocksdb_memtable_entry_height(&mt, i);
    if e < 1 || e > 12 { ok = false; }
    if e > h { h = e; }
    i = i + 1;
  }
  if rocksdb_memtable_height(&mt) != h { ok = false; }
  if h < 1 { ok = false; }
  if rocksdb_memtable_level_count(&mt, 1) != 8 { ok = false; }
  if rocksdb_memtable_level_count(&mt, h + 1) != 0 { ok = false; }
  if rocksdb_memtable_level_count(&mt, 0) != 0 { ok = false; }
  let hk = rocksdb_memtable_height_for_key(0, &text("k3"), 4);
  let hk2 = rocksdb_memtable_height_for_key(0, &text("k3"), 4);
  if hk != hk2 { ok = false; }
  if hk < 1 || hk > 12 { ok = false; }
  let i3 = rocksdb_memtable_find(&mt, 0, &text("k3"), 100);
  if i3 < 0 { ok = false; } else {
    let stored: Int = mt.heights[i3];
    if stored != hk { ok = false; }
  }
  let steps = rocksdb_memtable_search_steps(&mt, 0, &text("k3"), 100);
  if steps < 1 { ok = false; }
  if steps > 4 { ok = false; }
  if rocksdb_memtable_search_steps(&mt, 0, &empty_key(), 100) != 0 { ok = false; }
  return assert(ok, name);
}

fn empty_key() -> Vec[UInt8] {
  return Vec[UInt8].new();
}

// --------------------------------------------------
//  t3: snapshot visibility, tombstones, get errors
// --------------------------------------------------

fn t3() -> TestResult {
  let name = "memtable: snapshot visibility, tombstones, get errors";
  var ok = true;
  var mt = rocksdb_memtable_new(4096);
  rocksdb_memtable_put(&mut mt, 0, &text("a"), &text("v1"), 1, 1);
  rocksdb_memtable_put(&mut mt, 0, &text("a"), &text("v2"), 3, 1);
  let i0 = rocksdb_memtable_find(&mt, 0, &text("a"), 1);
  if i0 < 0 { ok = false; } else {
    if rocksdb_memtable_entry_seq(&mt, i0) != 1 { ok = false; }
    let v0 = rocksdb_memtable_entry_value(&mt, i0);
    if !eq_text(&v0, "v1") { ok = false; }
  }
  let i1 = rocksdb_memtable_find(&mt, 0, &text("a"), 2);
  if i1 < 0 { ok = false; } else {
    if rocksdb_memtable_entry_seq(&mt, i1) != 1 { ok = false; }
  }
  let i2 = rocksdb_memtable_find(&mt, 0, &text("a"), 3);
  if i2 < 0 { ok = false; } else {
    if rocksdb_memtable_entry_seq(&mt, i2) != 3 { ok = false; }
  }
  let r1 = rocksdb_memtable_get(&mt, 0, &text("a"), 3);
  if !r1.is_ok { ok = false; } else {
    let v1: Vec[UInt8] = r1.value;
    if !eq_text(&v1, "v2") { ok = false; }
  }
  let r2 = rocksdb_memtable_get(&mt, 0, &text("a"), 2);
  if !r2.is_ok { ok = false; } else {
    let v2: Vec[UInt8] = r2.value;
    if !eq_text(&v2, "v1") { ok = false; }
  }
  let r3 = rocksdb_memtable_get(&mt, 0, &text("missing"), 9);
  if !err_not_found(r3) { ok = false; }
  var empty = Vec[UInt8].new();
  rocksdb_memtable_put(&mut mt, 0, &text("a"), &empty, 5, 0);
  let r4 = rocksdb_memtable_get(&mt, 0, &text("a"), 9);
  if !err_not_found(r4) { ok = false; }
  let i3 = rocksdb_memtable_find(&mt, 0, &text("a"), 4);
  if i3 < 0 { ok = false; } else {
    if rocksdb_memtable_entry_seq(&mt, i3) != 3 { ok = false; }
    if rocksdb_memtable_entry_type(&mt, i3) != 1 { ok = false; }
  }
  let i4 = rocksdb_memtable_find(&mt, 0, &text("a"), 9);
  if i4 < 0 { ok = false; } else {
    if rocksdb_memtable_entry_type(&mt, i4) != 0 { ok = false; }
  }
  if rocksdb_memtable_entry_cf(&mt, -1) != -1 { ok = false; }
  if rocksdb_memtable_entry_seq(&mt, 99) != -1 { ok = false; }
  if rocksdb_memtable_entry_type(&mt, 99) != -1 { ok = false; }
  if rocksdb_memtable_entry_height(&mt, 99) != 0 { ok = false; }
  return assert(ok, name);
}

// --------------------------------------------------
//  t4: memtable clear and out-of-range accessors
// --------------------------------------------------

fn t4() -> TestResult {
  let name = "memtable: clear resets state, accessors are bounds-safe";
  var ok = true;
  var mt = make_mt(3);
  if rocksdb_memtable_count(&mt) != 3 { ok = false; }
  rocksdb_memtable_clear(&mut mt);
  if rocksdb_memtable_count(&mt) != 0 { ok = false; }
  if rocksdb_memtable_bytes(&mt) != 0 { ok = false; }
  if rocksdb_memtable_capacity(&mt) != 65536 { ok = false; }
  if rocksdb_memtable_height(&mt) != 0 { ok = false; }
  if rocksdb_memtable_find(&mt, 0, &text("k0"), 100) != -1 { ok = false; }
  if rocksdb_memtable_search_steps(&mt, 0, &text("k0"), 100) != 0 { ok = false; }
  if !rocksdb_memtable_is_sorted(&mt) { ok = false; }
  if rocksdb_memtable_entry_key(&mt, 0).len() != 0 { ok = false; }
  if rocksdb_memtable_entry_value(&mt, 5).len() != 0 { ok = false; }
  if !err_not_found(rocksdb_memtable_get(&mt, 0, &text("k0"), 100)) { ok = false; }
  var mt2 = rocksdb_memtable_new(64);
  if rocksdb_memtable_put(&mut mt2, 0, &text("x"), &text("y"), 0, 1) != 0 { ok = false; }
  if rocksdb_memtable_find(&mt2, 0, &text("x"), 0) != 0 { ok = false; }
  return assert(ok, name);
}

// --------------------------------------------------
//  t5: WAL append and sync policies
// --------------------------------------------------

fn t5() -> TestResult {
  let name = "wal: append, sync policies, durability watermark";
  var ok = true;
  var w0 = rocksdb_wal_new(0);
  if rocksdb_wal_policy(&w0) != 0 { ok = false; }
  if !str_eq(rocksdb_wal_policy_name(0), "none") { ok = false; }
  if !str_eq(rocksdb_wal_policy_name(1), "flush") { ok = false; }
  if !str_eq(rocksdb_wal_policy_name(2), "sync") { ok = false; }
  if !str_eq(rocksdb_wal_policy_name(9), "") { ok = false; }
  rocksdb_wal_append(&mut w0, 0, &text("a"), &text("1"), 1, 1);
  rocksdb_wal_append(&mut w0, 0, &text("b"), &text("2"), 2, 1);
  if rocksdb_wal_count(&w0) != 2 { ok = false; }
  if rocksdb_wal_bytes(&w0) != 36 { ok = false; }
  if rocksdb_wal_synced(&w0) != 0 { ok = false; }
  if rocksdb_wal_pending(&w0) != 2 { ok = false; }
  if rocksdb_wal_is_durable(&w0, 1) { ok = false; }
  if !rocksdb_wal_is_durable(&w0, 0) { ok = false; }
  if rocksdb_wal_sync(&mut w0) != 2 { ok = false; }
  if rocksdb_wal_syncs(&w0) != 1 { ok = false; }
  if !rocksdb_wal_is_durable(&w0, 2) { ok = false; }
  if rocksdb_wal_is_durable(&w0, 3) { ok = false; }
  if rocksdb_wal_is_durable(&w0, -1) { ok = false; }
  var w1 = rocksdb_wal_new(1);
  rocksdb_wal_append(&mut w1, 0, &text("a"), &text("1"), 1, 1);
  if rocksdb_wal_synced(&w1) != 1 { ok = false; }
  if rocksdb_wal_flushes(&w1) != 1 { ok = false; }
  if rocksdb_wal_syncs(&w1) != 0 { ok = false; }
  var w2 = rocksdb_wal_new(2);
  rocksdb_wal_append(&mut w2, 0, &text("a"), &text("1"), 1, 1);
  if rocksdb_wal_synced(&w2) != 1 { ok = false; }
  if rocksdb_wal_syncs(&w2) != 1 { ok = false; }
  if rocksdb_wal_flushes(&w2) != 0 { ok = false; }
  if rocksdb_wal_policy(&rocksdb_wal_new(7)) != 2 { ok = false; }
  if rocksdb_wal_policy(&rocksdb_wal_new(-3)) != 0 { ok = false; }
  var empty = Vec[UInt8].new();
  if rocksdb_wal_append(&mut w2, 0, &empty, &text("x"), 5, 1) != -1 { ok = false; }
  if rocksdb_wal_append(&mut w2, 0, &text("k"), &text("v"), 6, 9) != -1 { ok = false; }
  if rocksdb_wal_append(&mut w2, 0, &text("k"), &text("v"), -2, 1) != -1 { ok = false; }
  if rocksdb_wal_count(&w2) != 1 { ok = false; }
  if rocksdb_wal_entry_cf(&w2, 0) != 0 { ok = false; }
  if rocksdb_wal_entry_seq(&w2, 0) != 1 { ok = false; }
  if rocksdb_wal_entry_type(&w2, 0) != 1 { ok = false; }
  let k0 = rocksdb_wal_entry_key(&w2, 0);
  if !eq_text(&k0, "a") { ok = false; }
  let v0 = rocksdb_wal_entry_value(&w2, 0);
  if !eq_text(&v0, "1") { ok = false; }
  if rocksdb_wal_entry_cf(&w2, 9) != -1 { ok = false; }
  if rocksdb_wal_entry_seq(&w2, -1) != -1 { ok = false; }
  if rocksdb_wal_entry_type(&w2, 9) != -1 { ok = false; }
  if rocksdb_wal_entry_key(&w2, 9).len() != 0 { ok = false; }
  if rocksdb_wal_entry_value(&w2, 9).len() != 0 { ok = false; }
  return assert(ok, name);
}

// --------------------------------------------------
//  t6: WAL replay into a memtable
// --------------------------------------------------

fn t6() -> TestResult {
  let name = "wal: replay, replay_from and replay_range";
  var ok = true;
  var w = rocksdb_wal_new(2);
  var empty = Vec[UInt8].new();
  rocksdb_wal_append(&mut w, 0, &text("a"), &text("v1"), 1, 1);
  rocksdb_wal_append(&mut w, 1, &text("b"), &text("v2"), 2, 1);
  rocksdb_wal_append(&mut w, 0, &text("a"), &empty, 3, 0);
  var mt = rocksdb_memtable_new(65536);
  let applied = rocksdb_wal_replay(&w, &mut mt);
  if applied != 3 { ok = false; }
  if rocksdb_memtable_count(&mt) != 3 { ok = false; }
  if !rocksdb_memtable_is_sorted(&mt) { ok = false; }
  if !err_not_found(rocksdb_memtable_get(&mt, 0, &text("a"), 9)) { ok = false; }
  let ra = rocksdb_memtable_get(&mt, 0, &text("a"), 2);
  if !ra.is_ok { ok = false; } else {
    let va: Vec[UInt8] = ra.value;
    if !eq_text(&va, "v1") { ok = false; }
  }
  let rb = rocksdb_memtable_get(&mt, 1, &text("b"), 9);
  if !rb.is_ok { ok = false; } else {
    let vb: Vec[UInt8] = rb.value;
    if !eq_text(&vb, "v2") { ok = false; }
  }
  var mt2 = rocksdb_memtable_new(65536);
  let applied2 = rocksdb_wal_replay_from(&w, 2, &mut mt2);
  if applied2 != 1 { ok = false; }
  if rocksdb_memtable_count(&mt2) != 1 { ok = false; }
  if !err_not_found(rocksdb_memtable_get(&mt2, 0, &text("a"), 9)) { ok = false; }
  var mt3 = rocksdb_memtable_new(65536);
  let applied3 = rocksdb_wal_replay_range(&w, 0, 2, &mut mt3);
  if applied3 != 2 { ok = false; }
  if rocksdb_wal_replay_range(&w, -5, 99, &mut mt3) != 3 { ok = false; }
  if rocksdb_wal_replay_range(&w, 9, 1, &mut mt3) != 0 { ok = false; }
  return assert(ok, name);
}

// --------------------------------------------------
//  t7: SST build -- blocks, index, byte accounting
// --------------------------------------------------

fn t7() -> TestResult {
  let name = "sst: build from memtable (blocks, index, byte accounting)";
  var ok = true;
  let mt = make_mt(5);
  let t = rocksdb_table_build(&mt, 7, 2, 8, 3);
  if rocksdb_table_count(&t) != 5 { ok = false; }
  if rocksdb_table_file_number(&t) != 7 { ok = false; }
  if rocksdb_table_block_count(&t) != 3 { ok = false; }
  if rocksdb_table_block_first(&t, 0) != 0 { ok = false; }
  if rocksdb_table_block_first(&t, 1) != 2 { ok = false; }
  if rocksdb_table_block_first(&t, 2) != 4 { ok = false; }
  if rocksdb_table_block_first(&t, 3) != -1 { ok = false; }
  if rocksdb_table_block_first(&t, -1) != -1 { ok = false; }
  let ik0 = rocksdb_table_index_key(&t, 0);
  if !eq_text(&ik0, "k0") { ok = false; }
  let ik2 = rocksdb_table_index_key(&t, 2);
  if !eq_text(&ik2, "k4") { ok = false; }
  if rocksdb_table_index_key(&t, 9).len() != 0 { ok = false; }
  let fk = rocksdb_table_first_key(&t);
  if !eq_text(&fk, "k0") { ok = false; }
  let lk = rocksdb_table_last_key(&t);
  if !eq_text(&lk, "k4") { ok = false; }
  if rocksdb_table_bytes(&t) != 126 { ok = false; }
  var i = 0;
  while i < 5 {
    let ks = "k" + convert.int_to_string(i);
    let kb = rocksdb_table_entry_key(&t, i);
    if !eq_text(&kb, ks) { ok = false; }
    if rocksdb_table_entry_seq(&t, i) != i + 1 { ok = false; }
    if rocksdb_table_entry_type(&t, i) != 1 { ok = false; }
    if rocksdb_table_entry_cf(&t, i) != 0 { ok = false; }
    let vs = "v" + convert.int_to_string(i);
    let vb = rocksdb_table_entry_value(&t, i);
    if !eq_text(&vb, vs) { ok = false; }
    i = i + 1;
  }
  if rocksdb_table_entry_key(&t, -1).len() != 0 { ok = false; }
  if rocksdb_table_entry_value(&t, 99).len() != 0 { ok = false; }
  if rocksdb_table_entry_seq(&t, 99) != -1 { ok = false; }
  if rocksdb_table_entry_type(&t, -1) != -1 { ok = false; }
  if rocksdb_table_entry_cf(&t, 99) != -1 { ok = false; }
  let empty_mt = rocksdb_memtable_new(64);
  let et = rocksdb_table_build(&empty_mt, 1, 2, 8, 3);
  if rocksdb_table_count(&et) != 0 { ok = false; }
  if rocksdb_table_first_key(&et).len() != 0 { ok = false; }
  return assert(ok, name);
}

// --------------------------------------------------
//  t8: Bloom filter shape and probes
// --------------------------------------------------

fn t8() -> TestResult {
  let name = "sst: Bloom shape (bit length, set bits, probes)";
  var ok = true;
  let mt = make_mt(5);
  let t = rocksdb_table_build(&mt, 1, 2, 8, 3);
  if rocksdb_table_bloom_bitlen(&t) != 64 { ok = false; }
  if rocksdb_table_bloom_hashes(&t) != 3 { ok = false; }
  if rocksdb_table_bloom_keys(&t) != 5 { ok = false; }
  let set_bits = rocksdb_table_bloom_set_bits(&t);
  if set_bits <= 0 { ok = false; }
  if set_bits > 64 { ok = false; }
  let fill = rocksdb_table_bloom_fill_permille(&t);
  if fill <= 0 { ok = false; }
  if fill > 1000 { ok = false; }
  var i = 0;
  while i < 5 {
    let ks = "k" + convert.int_to_string(i);
    if !rocksdb_table_bloom_may_contain(&t, 0, &text(ks)) { ok = false; }
    i = i + 1;
  }
  if rocksdb_table_bloom_may_contain(&t, 0, &text("absent-key")) { ok = false; }
  if rocksdb_table_bloom_may_contain(&t, 5, &text("k0")) { ok = false; }
  var big = rocksdb_memtable_new(65536);
  var j = 0;
  while j < 40 {
    let ks2 = "key" + convert.int_to_string(j);
    rocksdb_memtable_put(&mut big, 0, &text(ks2), &text("val"), j + 1, 1);
    j = j + 1;
  }
  let bt = rocksdb_table_build(&big, 2, 4, 10, 3);
  if rocksdb_table_bloom_bitlen(&bt) != 400 { ok = false; }
  let fb = rocksdb_table_bloom_fill_permille(&bt);
  if fb <= 0 { ok = false; }
  return assert(ok, name);
}

// --------------------------------------------------
//  t9: table lookup at snapshots
// --------------------------------------------------

fn t9() -> TestResult {
  let name = "sst: find/get at snapshots, first/last bounds";
  var ok = true;
  var mt = rocksdb_memtable_new(65536);
  rocksdb_memtable_put(&mut mt, 0, &text("a"), &text("old"), 1, 1);
  rocksdb_memtable_put(&mut mt, 0, &text("a"), &text("new"), 3, 1);
  rocksdb_memtable_put(&mut mt, 0, &text("b"), &text("bee"), 2, 1);
  let t = rocksdb_table_build(&mt, 4, 2, 8, 3);
  let i1 = rocksdb_table_find(&t, 0, &text("a"), 1);
  if i1 < 0 { ok = false; } else {
    if rocksdb_table_entry_seq(&t, i1) != 1 { ok = false; }
  }
  let i2 = rocksdb_table_find(&t, 0, &text("a"), 3);
  if i2 < 0 { ok = false; } else {
    if rocksdb_table_entry_seq(&t, i2) != 3 { ok = false; }
  }
  if rocksdb_table_find(&t, 0, &text("zz"), 9) != -1 { ok = false; }
  if rocksdb_table_find(&t, 1, &text("a"), 9) != -1 { ok = false; }
  if rocksdb_table_find(&t, 0, &empty_key(), 9) != -1 { ok = false; }
  let r1 = rocksdb_table_get(&t, 0, &text("a"), 1);
  if !r1.is_ok { ok = false; } else {
    let v1: Vec[UInt8] = r1.value;
    if !eq_text(&v1, "old") { ok = false; }
  }
  let r2 = rocksdb_table_get(&t, 0, &text("a"), 3);
  if !r2.is_ok { ok = false; } else {
    let v2: Vec[UInt8] = r2.value;
    if !eq_text(&v2, "new") { ok = false; }
  }
  if !err_not_found(rocksdb_table_get(&t, 0, &text("zz"), 9)) { ok = false; }
  let fk = rocksdb_table_first_key(&t);
  if !eq_text(&fk, "a") { ok = false; }
  let lk = rocksdb_table_last_key(&t);
  if !eq_text(&lk, "b") { ok = false; }
  return assert(ok, name);
}

// Build a table whose entries are "k<base+i>" = "v<base+i>" with explicit
// sequences 1..n (default cf) and add it to level `level`.
fn add_table_at(v: &mut RocksDbVersion, n: Int, base: Int, fnum: Int, level: Int) -> Int {
  var mt = rocksdb_memtable_new(1048576);
  var i = 0;
  while i < n {
    let ks = "k" + convert.int_to_string(base + i);
    let vs = "v" + convert.int_to_string(base + i);
    rocksdb_memtable_put(&mut mt, 0, &text(ks), &text(vs), i + 1, 1);
    i = i + 1;
  }
  let t = rocksdb_table_build(&mt, fnum, 4, 8, 3);
  return rocksdb_version_add_table(v, &t, level);
}

// --------------------------------------------------
//  t10: version level structure and accessors
// --------------------------------------------------

fn t10() -> TestResult {
  let name = "version: file placement, level counts, bounds and targets";
  var ok = true;
  var v = rocksdb_version_new(4, 1024, 10, 7, 2, 8, 3);
  if rocksdb_version_file_count(&v) != 0 { ok = false; }
  if rocksdb_version_max_level(&v) != -1 { ok = false; }
  if rocksdb_version_total_bytes(&v) != 0 { ok = false; }
  let f0 = add_table_at(&mut v, 3, 0, 1, 0);
  let f1 = add_table_at(&mut v, 2, 10, 2, 0);
  let f2 = add_table_at(&mut v, 2, 20, 3, 1);
  if f0 < 0 { ok = false; }
  if f1 < 0 { ok = false; }
  if f2 < 0 { ok = false; }
  if rocksdb_version_file_count(&v) != 3 { ok = false; }
  if rocksdb_version_level_file_count(&v, 0) != 2 { ok = false; }
  if rocksdb_version_level_file_count(&v, 1) != 1 { ok = false; }
  if rocksdb_version_level_file_count(&v, 2) != 0 { ok = false; }
  if rocksdb_version_max_level(&v) != 1 { ok = false; }
  let ta = rocksdb_version_file_bytes(&v, 0);
  let tb = rocksdb_version_file_bytes(&v, 1);
  let tc = rocksdb_version_file_bytes(&v, 2);
  if ta <= 0 { ok = false; }
  if rocksdb_version_total_bytes(&v) != ta + tb + tc { ok = false; }
  if rocksdb_version_level_bytes(&v, 0) != ta + tb { ok = false; }
  if rocksdb_version_level_bytes(&v, 1) != tc { ok = false; }
  let fl = v.file_level;
  let l0: Int = fl[0];
  let l1: Int = fl[1];
  let l2: Int = fl[2];
  if l0 != 0 { ok = false; }
  if l1 != 0 { ok = false; }
  if l2 != 1 { ok = false; }
  let fnum_list = v.file_number;
  let n0: Int = fnum_list[0];
  if n0 != 1 { ok = false; }
  if rocksdb_version_file_number(&v, 9) != -1 { ok = false; }
  if rocksdb_version_file_level(&v, -1) != -1 { ok = false; }
  if rocksdb_version_file_bytes(&v, 9) != -1 { ok = false; }
  if rocksdb_version_file_entry_count(&v, 9) != -1 { ok = false; }
  let fk0 = rocksdb_version_file_first_key(&v, 0);
  if !eq_text(&fk0, "k0") { ok = false; }
  let lk0 = rocksdb_version_file_last_key(&v, 0);
  if !eq_text(&lk0, "k2") { ok = false; }
  if rocksdb_version_file_first_key(&v, 9).len() != 0 { ok = false; }
  if rocksdb_version_level_target_bytes(&v, 0) != -1 { ok = false; }
  if rocksdb_version_level_target_bytes(&v, 1) != 1024 { ok = false; }
  if rocksdb_version_level_target_bytes(&v, 2) != 10240 { ok = false; }
  if rocksdb_version_level_target_bytes(&v, 3) != 102400 { ok = false; }
  if rocksdb_version_find_file(&v, 1, 0, &text("k20")) != f2 { ok = false; }
  if rocksdb_version_find_file(&v, 1, 0, &text("k99")) != -1 { ok = false; }
  if rocksdb_version_find_file(&v, 3, 0, &text("k0")) != -1 { ok = false; }
  let t5 = make_table(1, 9);
  if rocksdb_version_add_table(&v, &t5, 9) != -1 { ok = false; }
  if rocksdb_version_add_table(&v, &t5, -1) != -1 { ok = false; }
  let et = rocksdb_table_build(&rocksdb_memtable_new(64), 10, 2, 8, 3);
  if rocksdb_version_add_table(&v, &et, 0) != -1 { ok = false; }
  if rocksdb_version_file_count(&v) != 3 { ok = false; }
  return assert(ok, name);
}

// --------------------------------------------------
//  t11: per-mille scores and the deterministic picker
// --------------------------------------------------

fn t11() -> TestResult {
  let name = "version: size targets, per-mille scores, pick_level ordering";
  var ok = true;
  var v = rocksdb_version_new(2, 1024, 4, 5, 2, 8, 3);
  if rocksdb_version_score(&v, 0) != 0 { ok = false; }
  if rocksdb_version_score(&v, -1) != 0 { ok = false; }
  if rocksdb_version_score(&v, 9) != 0 { ok = false; }
  if rocksdb_version_pick_level(&v) != -1 { ok = false; }
  if rocksdb_version_needs_compaction(&v) { ok = false; }
  add_table_at(&mut v, 1, 0, 1, 0);
  if rocksdb_version_score(&v, 0) != 500 { ok = false; }
  if rocksdb_version_pick_level(&v) != -1 { ok = false; }
  add_table_at(&mut v, 1, 10, 2, 0);
  if rocksdb_version_score(&v, 0) != 1000 { ok = false; }
  if rocksdb_version_pick_level(&v) != 0 { ok = false; }
  if !rocksdb_version_needs_compaction(&v) { ok = false; }
  add_table_at(&mut v, 1, 20, 3, 0);
  if rocksdb_version_score(&v, 0) != 1500 { ok = false; }
  if rocksdb_version_pick_level(&v) != 0 { ok = false; }
  if rocksdb_version_score(&v, 4) != 0 { ok = false; }
  add_table_at(&mut v, 60, 100, 4, 1);
  let s0 = rocksdb_version_score(&v, 0);
  let s1 = rocksdb_version_score(&v, 1);
  if s0 != 1500 { ok = false; }
  if s1 < 1000 { ok = false; }
  let picked = rocksdb_version_pick_level(&v);
  if s1 > s0 {
    if picked != 1 { ok = false; }
  } else {
    if picked != 0 { ok = false; }
  }
  if rocksdb_version_level_target_bytes(&v, 2) != 4096 { ok = false; }
  return assert(ok, name);
}

// --------------------------------------------------
//  t12: version lookup across levels and snapshots
// --------------------------------------------------

fn t12() -> TestResult {
  let name = "version: multi-level get, snapshot reads, tombstones";
  var ok = true;
  var v = rocksdb_version_new(4, 1024, 10, 7, 2, 8, 3);
  var mt1 = rocksdb_memtable_new(65536);
  rocksdb_memtable_put(&mut mt1, 0, &text("a"), &text("old"), 1, 1);
  let t1 = rocksdb_table_build(&mt1, 1, 2, 8, 3);
  rocksdb_version_add_table(&mut v, &t1, 0);
  var mt2 = rocksdb_memtable_new(65536);
  rocksdb_memtable_put(&mut mt2, 0, &text("a"), &text("new"), 3, 1);
  rocksdb_memtable_put(&mut mt2, 0, &text("b"), &text("bee"), 2, 1);
  let t2 = rocksdb_table_build(&mt2, 2, 2, 8, 3);
  rocksdb_version_add_table(&mut v, &t2, 0);
  var mt3 = rocksdb_memtable_new(65536);
  var empty = Vec[UInt8].new();
  rocksdb_memtable_put(&mut mt3, 0, &text("a"), &empty, 4, 0);
  let t3 = rocksdb_table_build(&mt3, 3, 2, 8, 3);
  rocksdb_version_add_table(&mut v, &t3, 0);
  let ra = rocksdb_version_get(&v, 0, &text("a"), 9);
  if !err_not_found(ra) { ok = false; }
  let ra1 = rocksdb_version_get(&v, 0, &text("a"), 1);
  if !ra1.is_ok { ok = false; } else {
    let va1: Vec[UInt8] = ra1.value;
    if !eq_text(&va1, "old") { ok = false; }
  }
  let ra3 = rocksdb_version_get(&v, 0, &text("a"), 3);
  if !ra3.is_ok { ok = false; } else {
    let va3: Vec[UInt8] = ra3.value;
    if !eq_text(&va3, "new") { ok = false; }
  }
  let rb2 = rocksdb_version_get(&v, 0, &text("b"), 1);
  if !err_not_found(rb2) { ok = false; }
  let rb3 = rocksdb_version_get(&v, 0, &text("b"), 3);
  if !rb3.is_ok { ok = false; } else {
    let vb3: Vec[UInt8] = rb3.value;
    if !eq_text(&vb3, "bee") { ok = false; }
  }
  if !err_not_found(rocksdb_version_get(&v, 0, &text("zz"), 9)) { ok = false; }
  if rocksdb_version_find(&v, 0, &text("zz"), 9) != -1 { ok = false; }
  let ia = rocksdb_version_find(&v, 0, &text("a"), 9);
  if ia < 0 { ok = false; } else {
    if rocksdb_version_entry_seq(&v, ia) != 4 { ok = false; }
    if rocksdb_version_entry_type(&v, ia) != 0 { ok = false; }
    if rocksdb_version_entry_cf(&v, ia) != 0 { ok = false; }
    let ka = rocksdb_version_entry_key(&v, ia);
    if !eq_text(&ka, "a") { ok = false; }
  }
  if rocksdb_version_entry_seq(&v, 999) != -1 { ok = false; }
  if rocksdb_version_entry_type(&v, -1) != -1 { ok = false; }
  if rocksdb_version_entry_cf(&v, 999) != -1 { ok = false; }
  if rocksdb_version_entry_key(&v, 999).len() != 0 { ok = false; }
  if rocksdb_version_entry_value(&v, 999).len() != 0 { ok = false; }
  if rocksdb_version_entry_key(&v, ia).len() != 1 { ok = false; }
  return assert(ok, name);
}

// --------------------------------------------------
//  t13: compaction L0 -> L1
// --------------------------------------------------

fn t13() -> TestResult {
  let name = "compaction: L0->L1 pick, merge, report and post-state";
  var ok = true;
  var v = rocksdb_version_new(2, 1024, 10, 7, 2, 8, 3);
  var m1 = rocksdb_memtable_new(65536);
  rocksdb_memtable_put(&mut m1, 0, &text("a"), &text("1"), 1, 1);
  rocksdb_memtable_put(&mut m1, 0, &text("b"), &text("1"), 2, 1);
  let t1 = rocksdb_table_build(&m1, 1, 2, 8, 3);
  rocksdb_version_add_table(&mut v, &t1, 0);
  var m2 = rocksdb_memtable_new(65536);
  rocksdb_memtable_put(&mut m2, 0, &text("a"), &text("2"), 3, 1);
  rocksdb_memtable_put(&mut m2, 0, &text("c"), &text("1"), 4, 1);
  let t2 = rocksdb_table_build(&m2, 2, 2, 8, 3);
  rocksdb_version_add_table(&mut v, &t2, 0);
  if rocksdb_version_pick_level(&v) != 0 { ok = false; }
  let rep = rocksdb_version_compact(&mut v, 4, -1);
  if rep.rounds != 1 { ok = false; }
  if rep.levels_picked != 1 { ok = false; }
  if rep.last_level != 1 { ok = false; }
  if rep.input_files != 2 { ok = false; }
  if rep.output_files != 1 { ok = false; }
  if rep.input_entries != 4 { ok = false; }
  if rep.output_entries != 3 { ok = false; }
  if rep.dropped_entries != 1 { ok = false; }
  if rep.bytes_in != t1.bytes + t2.bytes { ok = false; }
  if rep.bytes_out != rocksdb_version_level_bytes(&v, 1) { ok = false; }
  if rocksdb_version_level_file_count(&v, 0) != 0 { ok = false; }
  if rocksdb_version_level_file_count(&v, 1) != 1 { ok = false; }
  if rocksdb_version_file_count(&v) != 1 { ok = false; }
  if rocksdb_version_max_level(&v) != 1 { ok = false; }
  if rocksdb_version_total_bytes(&v) != rep.bytes_out { ok = false; }
  if rocksdb_version_pick_level(&v) != -1 { ok = false; }
  let ra = rocksdb_version_get(&v, 0, &text("a"), 99);
  if !ra.is_ok { ok = false; } else {
    let va: Vec[UInt8] = ra.value;
    if !eq_text(&va, "2") { ok = false; }
  }
  let rb = rocksdb_version_get(&v, 0, &text("b"), 99);
  if !rb.is_ok { ok = false; } else {
    let vb: Vec[UInt8] = rb.value;
    if !eq_text(&vb, "1") { ok = false; }
  }
  let rc = rocksdb_version_get(&v, 0, &text("c"), 99);
  if !rc.is_ok { ok = false; } else {
    let vc: Vec[UInt8] = rc.value;
    if !eq_text(&vc, "1") { ok = false; }
  }
  return assert(ok, name);
}

// --------------------------------------------------
//  t14: bounded rounds and bottom-level tombstone drop
// --------------------------------------------------

fn t14() -> TestResult {
  let name = "compaction: bounded rounds and bottom-level tombstone drop";
  var ok = true;
  var v = rocksdb_version_new(2, 1024, 10, 7, 2, 8, 3);
  add_table_at(&mut v, 1, 0, 1, 0);
  add_table_at(&mut v, 1, 10, 2, 0);
  let rep0 = rocksdb_version_compact(&mut v, 0, -1);
  if rep0.rounds != 0 { ok = false; }
  if rocksdb_version_level_file_count(&v, 0) != 2 { ok = false; }
  let rep1 = rocksdb_version_compact(&mut v, 1, -1);
  if rep1.rounds != 1 { ok = false; }
  if rocksdb_version_level_file_count(&v, 0) != 0 { ok = false; }
  if rocksdb_version_level_file_count(&v, 1) != 1 { ok = false; }
  let rep2 = rocksdb_version_compact(&mut v, 4, -1);
  if rep2.rounds != 0 { ok = false; }
  var v2 = rocksdb_version_new(1, 1024, 10, 2, 2, 8, 3);
  var m = rocksdb_memtable_new(65536);
  var empty = Vec[UInt8].new();
  rocksdb_memtable_put(&mut m, 0, &text("a"), &empty, 1, 0);
  rocksdb_memtable_put(&mut m, 0, &text("b"), &text("keep"), 2, 1);
  let t = rocksdb_table_build(&m, 1, 2, 8, 3);
  rocksdb_version_add_table(&mut v2, &t, 0);
  if rocksdb_version_pick_level(&v2) != 0 { ok = false; }
  let rep3 = rocksdb_version_compact(&mut v2, 4, -1);
  if rep3.rounds != 1 { ok = false; }
  if rep3.output_entries != 1 { ok = false; }
  if rep3.dropped_entries != 1 { ok = false; }
  if !err_not_found(rocksdb_version_get(&v2, 0, &text("a"), 99)) { ok = false; }
  let rb = rocksdb_version_get(&v2, 0, &text("b"), 99);
  if !rb.is_ok { ok = false; } else {
    let vb: Vec[UInt8] = rb.value;
    if !eq_text(&vb, "keep") { ok = false; }
  }
  if rocksdb_version_find(&v2, 0, &text("a"), 99) != -1 { ok = false; }
  return assert(ok, name);
}

// --------------------------------------------------
//  t15: snapshot-safe compaction dedup
// --------------------------------------------------

fn t15() -> TestResult {
  let name = "compaction: snapshot-safe dedup keeps the base version";
  var ok = true;
  var v = rocksdb_version_new(1, 1024, 10, 4, 4, 8, 3);
  var m = rocksdb_memtable_new(65536);
  rocksdb_memtable_put(&mut m, 0, &text("a"), &text("v1"), 1, 1);
  rocksdb_memtable_put(&mut m, 0, &text("a"), &text("v2"), 3, 1);
  rocksdb_memtable_put(&mut m, 0, &text("a"), &text("v3"), 5, 1);
  let t = rocksdb_table_build(&m, 1, 4, 8, 3);
  rocksdb_version_add_table(&mut v, &t, 0);
  if rocksdb_version_pick_level(&v) != 0 { ok = false; }
  let rep = rocksdb_version_compact(&mut v, 4, 3);
  if rep.rounds != 1 { ok = false; }
  if rep.output_entries != 2 { ok = false; }
  if rep.dropped_entries != 1 { ok = false; }
  let r5 = rocksdb_version_get(&v, 0, &text("a"), 5);
  if !r5.is_ok { ok = false; } else {
    let v5: Vec[UInt8] = r5.value;
    if !eq_text(&v5, "v3") { ok = false; }
  }
  let r3 = rocksdb_version_get(&v, 0, &text("a"), 3);
  if !r3.is_ok { ok = false; } else {
    let v3: Vec[UInt8] = r3.value;
    if !eq_text(&v3, "v2") { ok = false; }
  }
  let r4 = rocksdb_version_get(&v, 0, &text("a"), 4);
  if !r4.is_ok { ok = false; } else {
    let v4: Vec[UInt8] = r4.value;
    if !eq_text(&v4, "v2") { ok = false; }
  }
  return assert(ok, name);
}

// --------------------------------------------------
//  t16: deep compaction with overlap selection
// --------------------------------------------------

fn t16() -> TestResult {
  let name = "compaction: L1->L2 overlap selection and deep move";
  var ok = true;
  var v = rocksdb_version_new(2, 1024, 10, 4, 2, 8, 3);
  add_table_at(&mut v, 60, 0, 1, 1);
  add_table_at(&mut v, 10, 30, 2, 2);
  add_table_at(&mut v, 10, 100, 3, 2);
  let s1 = rocksdb_version_score(&v, 1);
  if s1 < 1000 { ok = false; }
  if rocksdb_version_pick_level(&v) != 1 { ok = false; }
  let rep = rocksdb_version_compact(&mut v, 1, -1);
  if rep.rounds != 1 { ok = false; }
  if rep.last_level != 2 { ok = false; }
  if rep.input_files != 3 { ok = false; }
  if rep.output_files != 1 { ok = false; }
  if rep.input_entries != 80 { ok = false; }
  if rep.output_entries != 70 { ok = false; }
  if rep.dropped_entries != 10 { ok = false; }
  if rocksdb_version_level_file_count(&v, 1) != 0 { ok = false; }
  if rocksdb_version_level_file_count(&v, 2) != 1 { ok = false; }
  let r = rocksdb_version_get(&v, 0, &text("k35"), 999);
  if !r.is_ok { ok = false; } else {
    let vv: Vec[UInt8] = r.value;
    if !eq_text(&vv, "v35") { ok = false; }
  }
  let rm = rocksdb_version_get(&v, 0, &text("k105"), 999);
  if !rm.is_ok { ok = false; } else {
    let vm: Vec[UInt8] = rm.value;
    if !eq_text(&vm, "v105") { ok = false; }
  }
  let rx = rocksdb_version_get(&v, 0, &text("k59"), 999);
  if !rx.is_ok { ok = false; } else {
    let vx: Vec[UInt8] = rx.value;
    if !eq_text(&vx, "v59") { ok = false; }
  }
  let fa = rocksdb_version_file_bytes(&v, 0);
  if rocksdb_version_total_bytes(&v) != fa { ok = false; }
  if rocksdb_version_file_count(&v) != 1 { ok = false; }
  if rocksdb_version_max_level(&v) != 2 { ok = false; }
  return assert(ok, name);
}

// --------------------------------------------------
//  t17: engine put/get/delete, sequence and statistics
// --------------------------------------------------

fn t17() -> TestResult {
  let name = "db: put/get/delete, sequence and statistics";
  var ok = true;
  var db = rocksdb_db_new_default();
  if rocksdb_db_sequence(&db) != 0 { ok = false; }
  if rocksdb_put(&mut db, &text("a"), &text("1")) != 1 { ok = false; }
  if rocksdb_put(&mut db, &text("b"), &text("2")) != 2 { ok = false; }
  if rocksdb_delete(&mut db, &text("a")) != 3 { ok = false; }
  if rocksdb_put(&mut db, &text("a"), &text("3")) != 4 { ok = false; }
  if rocksdb_db_sequence(&db) != 4 { ok = false; }
  if rocksdb_db_memtable_count(&db) != 4 { ok = false; }
  if rocksdb_wal_count(&db.wal) != 4 { ok = false; }
  if rocksdb_wal_synced(&db.wal) != 4 { ok = false; }
  if rocksdb_wal_pending(&db.wal) != 0 { ok = false; }
  if !get_eq(&mut db, &text("a"), "3") { ok = false; }
  if !get_eq(&mut db, &text("b"), "2") { ok = false; }
  if !err_not_found(rocksdb_get(&mut db, &text("zz"))) { ok = false; }
  if !err_not_found(rocksdb_get(&mut db, &empty_key())) { ok = false; }
  let st = rocksdb_stats(&db);
  if st.puts != 3 { ok = false; }
  if st.deletes != 1 { ok = false; }
  if st.gets != 4 { ok = false; }
  if st.hits != 2 { ok = false; }
  if st.misses != 2 { ok = false; }
  let ra2 = rocksdb_get_at(&mut db, 0, &text("a"), 2);
  if !ra2.is_ok { ok = false; } else {
    let va2: Vec[UInt8] = ra2.value;
    if !eq_text(&va2, "1") { ok = false; }
  }
  let rb2 = rocksdb_get_at(&mut db, 0, &text("b"), 2);
  if !rb2.is_ok { ok = false; } else {
    let vb2: Vec[UInt8] = rb2.value;
    if !eq_text(&vb2, "2") { ok = false; }
  }
  if rocksdb_lookup(&mut db, 0, &text("a"), 4) != 1 { ok = false; }
  if rocksdb_lookup(&mut db, 0, &text("a"), 2) != 1 { ok = false; }
  if rocksdb_lookup(&mut db, 0, &text("a"), 3) != 0 { ok = false; }
  if rocksdb_lookup(&mut db, 0, &text("zz"), 4) != -1 { ok = false; }
  if rocksdb_lookup(&mut db, 5, &text("a"), 4) != -1 { ok = false; }
  var empty = Vec[UInt8].new();
  if rocksdb_put(&mut db, &empty, &text("x")) != -1 { ok = false; }
  if rocksdb_delete(&mut db, &empty) != -1 { ok = false; }
  if rocksdb_put_cf(&mut db, 9, &text("a"), &text("x")) != -1 { ok = false; }
  if rocksdb_delete_cf(&mut db, 9, &text("a")) != -1 { ok = false; }
  if rocksdb_db_file_count(&db) != 0 { ok = false; }
  return assert(ok, name);
}

// --------------------------------------------------
//  t18: column families
// --------------------------------------------------

fn t18() -> TestResult {
  let name = "db: column families (registry, isolation, errors)";
  var ok = true;
  var db = rocksdb_db_new_default();
  if rocksdb_column_family_count(&db) != 1 { ok = false; }
  if rocksdb_column_family_id(&db, "default") != 0 { ok = false; }
  if !str_eq(rocksdb_column_family_name(&db, 0), "default") { ok = false; }
  if !str_eq(rocksdb_column_family_name(&db, 9), "") { ok = false; }
  if rocksdb_column_family_id(&db, "nope") != -1 { ok = false; }
  if rocksdb_create_column_family(&mut db, "cf1") != 1 { ok = false; }
  if rocksdb_create_column_family(&mut db, "cf1") != -1 { ok = false; }
  if rocksdb_create_column_family(&mut db, "") != -1 { ok = false; }
  if rocksdb_column_family_count(&db) != 2 { ok = false; }
  if rocksdb_column_family_id(&db, "cf1") != 1 { ok = false; }
  if !str_eq(rocksdb_column_family_name(&db, 1), "cf1") { ok = false; }
  rocksdb_put_cf(&mut db, 1, &text("k"), &text("cfv"));
  rocksdb_put(&mut db, &text("k"), &text("defv"));
  let rc = rocksdb_get_cf(&mut db, 1, &text("k"));
  if !rc.is_ok { ok = false; } else {
    let vc: Vec[UInt8] = rc.value;
    if !eq_text(&vc, "cfv") { ok = false; }
  }
  if !get_eq(&mut db, &text("k"), "defv") { ok = false; }
  if !err_not_found(rocksdb_get_cf(&mut db, 9, &text("k"))) { ok = false; }
  let cur = rocksdb_db_sequence(&db);
  let il = rocksdb_iter_create(&mut db, 1, cur);
  if rocksdb_iter_count(&il) != 1 { ok = false; }
  let il0 = rocksdb_iter_create(&mut db, 0, cur);
  if rocksdb_iter_count(&il0) != 1 { ok = false; }
  if rocksdb_iter_cf(&il) != 1 { ok = false; }
  let ik = rocksdb_iter_key(&il);
  if !eq_text(&ik, "k") { ok = false; }
  let iv = rocksdb_iter_value(&il);
  if !eq_text(&iv, "cfv") { ok = false; }
  return assert(ok, name);
}

// --------------------------------------------------
//  t19: snapshots
// --------------------------------------------------

fn t19() -> TestResult {
  let name = "db: snapshots (create, read-at, release, oldest)";
  var ok = true;
  var db = rocksdb_db_new_default();
  rocksdb_put(&mut db, &text("a"), &text("1"));
  let s1 = rocksdb_snapshot_create(&mut db);
  if s1 != 1 { ok = false; }
  rocksdb_put(&mut db, &text("a"), &text("2"));
  let s2 = rocksdb_snapshot_create(&mut db);
  if s2 != 2 { ok = false; }
  rocksdb_delete(&mut db, &text("a"));
  let r1 = rocksdb_get_at(&mut db, 0, &text("a"), s1);
  if !r1.is_ok { ok = false; } else {
    let v1: Vec[UInt8] = r1.value;
    if !eq_text(&v1, "1") { ok = false; }
  }
  let r2 = rocksdb_get_at(&mut db, 0, &text("a"), s2);
  if !r2.is_ok { ok = false; } else {
    let v2: Vec[UInt8] = r2.value;
    if !eq_text(&v2, "2") { ok = false; }
  }
  if !err_not_found(rocksdb_get(&mut db, &text("a"))) { ok = false; }
  if rocksdb_snapshot_count(&db) != 2 { ok = false; }
  if rocksdb_oldest_snapshot(&db) != 1 { ok = false; }
  if !rocksdb_snapshot_release(&mut db, 1) { ok = false; }
  if rocksdb_snapshot_release(&mut db, 1) { ok = false; }
  if rocksdb_snapshot_count(&db) != 1 { ok = false; }
  if rocksdb_oldest_snapshot(&db) != 2 { ok = false; }
  if !rocksdb_snapshot_release(&mut db, 2) { ok = false; }
  if rocksdb_oldest_snapshot(&db) != -1 { ok = false; }
  let st = rocksdb_stats(&db);
  if st.snapshots != 2 { ok = false; }
  return assert(ok, name);
}

// --------------------------------------------------
//  t20: snapshot iterator
// --------------------------------------------------

fn t20() -> TestResult {
  let name = "iterator: snapshot view, seek, order and bounds";
  var ok = true;
  var db = rocksdb_db_new_default();
  rocksdb_put(&mut db, &text("a"), &text("1"));
  rocksdb_put(&mut db, &text("b"), &text("2"));
  rocksdb_put(&mut db, &text("c"), &text("3"));
  rocksdb_delete(&mut db, &text("b"));
  rocksdb_put(&mut db, &text("a"), &text("4"));
  let cur = rocksdb_db_sequence(&db);
  var it = rocksdb_iter_create(&mut db, 0, cur);
  if rocksdb_iter_count(&it) != 2 { ok = false; }
  if rocksdb_iter_cf(&it) != 0 { ok = false; }
  if rocksdb_iter_snapshot(&it) != cur { ok = false; }
  if rocksdb_iter_pos(&it) != 0 { ok = false; }
  if !rocksdb_iter_valid(&it) { ok = false; }
  let k0 = rocksdb_iter_key(&it);
  if !eq_text(&k0, "a") { ok = false; }
  let v0 = rocksdb_iter_value(&it);
  if !eq_text(&v0, "4") { ok = false; }
  if rocksdb_iter_seq(&it) != 5 { ok = false; }
  rocksdb_iter_next(&mut it);
  let k1 = rocksdb_iter_key(&it);
  if !eq_text(&k1, "c") { ok = false; }
  let v1 = rocksdb_iter_value(&it);
  if !eq_text(&v1, "3") { ok = false; }
  rocksdb_iter_next(&mut it);
  if rocksdb_iter_valid(&it) { ok = false; }
  if rocksdb_iter_key(&it).len() != 0 { ok = false; }
  if rocksdb_iter_value(&it).len() != 0 { ok = false; }
  if rocksdb_iter_seq(&it) != -1 { ok = false; }
  rocksdb_iter_next(&mut it);
  if rocksdb_iter_pos(&it) != 2 { ok = false; }
  rocksdb_iter_seek(&mut it, &text("b"));
  let k2 = rocksdb_iter_key(&it);
  if !eq_text(&k2, "c") { ok = false; }
  rocksdb_iter_seek(&mut it, &text("0"));
  let k3 = rocksdb_iter_key(&it);
  if !eq_text(&k3, "a") { ok = false; }
  rocksdb_iter_first(&mut it);
  if rocksdb_iter_pos(&it) != 0 { ok = false; }
  var old_it = rocksdb_iter_create(&mut db, 0, 1);
  if rocksdb_iter_count(&old_it) != 1 { ok = false; }
  let ok0 = rocksdb_iter_key(&old_it);
  if !eq_text(&ok0, "a") { ok = false; }
  let ov0 = rocksdb_iter_value(&old_it);
  if !eq_text(&ov0, "1") { ok = false; }
  let st = rocksdb_stats(&db);
  if st.iterator_creates != 2 { ok = false; }
  return assert(ok, name);
}

// --------------------------------------------------
//  t21: range scan
// --------------------------------------------------

fn t21() -> TestResult {
  let name = "scan: bounds, limit/truncation, tombstones, cf filter";
  var ok = true;
  var db = rocksdb_db_new_default();
  rocksdb_put(&mut db, &text("a"), &text("1"));
  rocksdb_put(&mut db, &text("b"), &text("2"));
  rocksdb_put(&mut db, &text("c"), &text("3"));
  rocksdb_put(&mut db, &text("d"), &text("4"));
  rocksdb_put(&mut db, &text("e"), &text("5"));
  rocksdb_delete(&mut db, &text("c"));
  let cur = rocksdb_db_sequence(&db);
  let sc = rocksdb_scan(&mut db, 0, &text("b"), &text("d"), 0, cur);
  if rocksdb_scan_count(&sc) != 2 { ok = false; }
  if rocksdb_scan_truncated(&sc) { ok = false; }
  let b0 = rocksdb_scan_key(&sc, 0);
  if !eq_text(&b0, "b") { ok = false; }
  let b1 = rocksdb_scan_key(&sc, 1);
  if !eq_text(&b1, "d") { ok = false; }
  let sv1 = rocksdb_scan_value(&sc, 1);
  if !eq_text(&sv1, "4") { ok = false; }
  if rocksdb_scan_seq(&sc, 0) != 2 { ok = false; }
  if rocksdb_scan_key(&sc, 9).len() != 0 { ok = false; }
  if rocksdb_scan_value(&sc, -1).len() != 0 { ok = false; }
  if rocksdb_scan_seq(&sc, 9) != -1 { ok = false; }
  if sc.cf != 0 { ok = false; }
  var open_min = Vec[UInt8].new();
  var open_max = Vec[UInt8].new();
  let all = rocksdb_scan(&mut db, 0, &open_min, &open_max, 0, cur);
  if rocksdb_scan_count(&all) != 4 { ok = false; }
  let lim = rocksdb_scan(&mut db, 0, &open_min, &open_max, 2, cur);
  if rocksdb_scan_count(&lim) != 2 { ok = false; }
  if !rocksdb_scan_truncated(&lim) { ok = false; }
  let lim5 = rocksdb_scan(&mut db, 0, &open_min, &open_max, 5, cur);
  if rocksdb_scan_count(&lim5) != 4 { ok = false; }
  if rocksdb_scan_truncated(&lim5) { ok = false; }
  let none = rocksdb_scan(&mut db, 0, &text("x"), &text("z"), 0, cur);
  if rocksdb_scan_count(&none) != 0 { ok = false; }
  let c2 = rocksdb_create_column_family(&mut db, "cf1");
  rocksdb_put_cf(&mut db, c2, &text("aa"), &text("x"));
  let cur2 = rocksdb_db_sequence(&db);
  let scf = rocksdb_scan(&mut db, c2, &open_min, &open_max, 0, cur2);
  if rocksdb_scan_count(&scf) != 1 { ok = false; }
  let st = rocksdb_stats(&db);
  if st.scans != 6 { ok = false; }
  return assert(ok, name);
}

// --------------------------------------------------
//  t22: flush and bounded maintenance
// --------------------------------------------------

fn t22() -> TestResult {
  let name = "engine: flush to L0 and bounded maintenance";
  var ok = true;
  var db = rocksdb_db_new(64, 1, 1024, 10, 7, 2, 8, 3, 0);
  rocksdb_put(&mut db, &text("a"), &text("1"));
  rocksdb_put(&mut db, &text("b"), &text("2"));
  rocksdb_put(&mut db, &text("c"), &text("3"));
  rocksdb_put(&mut db, &text("d"), &text("4"));
  if !rocksdb_should_flush(&db) { ok = false; }
  let actions = rocksdb_maintenance(&mut db, 4);
  if actions != 2 { ok = false; }
  if rocksdb_db_memtable_count(&db) != 0 { ok = false; }
  if rocksdb_db_memtable_bytes(&db) != 0 { ok = false; }
  if rocksdb_db_file_count(&db) != 1 { ok = false; }
  if rocksdb_version_level_file_count(&db.ver, 0) != 0 { ok = false; }
  if rocksdb_version_level_file_count(&db.ver, 1) != 1 { ok = false; }
  let st = rocksdb_stats(&db);
  if st.flushes != 1 { ok = false; }
  if st.compactions != 1 { ok = false; }
  if st.flush_bytes <= 0 { ok = false; }
  if st.compact_bytes <= 0 { ok = false; }
  if rocksdb_db_version_total_bytes(&db) != st.compact_bytes { ok = false; }
  if !get_eq(&mut db, &text("a"), "1") { ok = false; }
  if !get_eq(&mut db, &text("d"), "4") { ok = false; }
  if rocksdb_maintenance(&mut db, 4) != 0 { ok = false; }
  if rocksdb_flush(&mut db) != -1 { ok = false; }
  if rocksdb_should_flush(&db) { ok = false; }
  return assert(ok, name);
}

// --------------------------------------------------
//  t23: flushed keys survive Bloom-guided lookup
// --------------------------------------------------

fn t23() -> TestResult {
  let name = "engine: flushed keys survive lookup (no Bloom false negatives)";
  var ok = true;
  var db = rocksdb_db_new(65536, 2, 1024, 10, 7, 2, 8, 3, 2);
  var i = 0;
  while i < 20 {
    let ks = "k" + convert.int_to_string(i);
    let vs = "v" + convert.int_to_string(i);
    rocksdb_put(&mut db, &text(ks), &text(vs));
    i = i + 1;
  }
  let f1 = rocksdb_flush(&mut db);
  if f1 < 0 { ok = false; }
  i = 0;
  while i < 20 {
    let ks2 = "k" + convert.int_to_string(i);
    let vs2 = "v" + convert.int_to_string(i);
    if !get_eq(&mut db, &text(ks2), vs2) { ok = false; }
    i = i + 1;
  }
  var j = 0;
  while j < 20 {
    let ks3 = "j" + convert.int_to_string(j);
    if !err_not_found(rocksdb_get(&mut db, &text(ks3))) { ok = false; }
    j = j + 1;
  }
  var i2 = 0;
  while i2 < 5 {
    let ks4 = "m" + convert.int_to_string(i2);
    rocksdb_put(&mut db, &text(ks4), &text("m"));
    i2 = i2 + 1;
  }
  let f2 = rocksdb_flush(&mut db);
  if f2 <= f1 { ok = false; }
  var i3 = 0;
  while i3 < 5 {
    let ks5 = "m" + convert.int_to_string(i3);
    if !get_eq(&mut db, &text(ks5), "m") { ok = false; }
    i3 = i3 + 1;
  }
  if rocksdb_db_file_count(&db) != 2 { ok = false; }
  if !get_eq(&mut db, &text("k7"), "v7") { ok = false; }
  if rocksdb_wal_synced(&db.wal) != 25 { ok = false; }
  return assert(ok, name);
}

// --------------------------------------------------
//  t24: defaults, version string, empty-engine reads
// --------------------------------------------------

fn t24() -> TestResult {
  let name = "defaults: options, version string, empty-engine reads";
  var ok = true;
  var db = rocksdb_db_new_default();
  if db.ver.l0_trigger != 4 { ok = false; }
  if db.ver.level_base_bytes != 262144 { ok = false; }
  if db.ver.level_multiplier != 10 { ok = false; }
  if db.ver.max_levels != 7 { ok = false; }
  if db.ver.block_entries != 4 { ok = false; }
  if db.ver.bloom_bits_per_key != 10 { ok = false; }
  if db.ver.bloom_hashes != 3 { ok = false; }
  if rocksdb_wal_policy(&db.wal) != 1 { ok = false; }
  if rocksdb_version_level_target_bytes(&db.ver, 1) != 262144 { ok = false; }
  if rocksdb_version_level_target_bytes(&db.ver, 2) != 2621440 { ok = false; }
  if !str_eq(rocksdb_version(), "0.1.0") { ok = false; }
  if rocksdb_db_sequence(&db) != 0 { ok = false; }
  if rocksdb_db_memtable_count(&db) != 0 { ok = false; }
  if rocksdb_db_memtable_bytes(&db) != 0 { ok = false; }
  if rocksdb_db_version_total_bytes(&db) != 0 { ok = false; }
  if rocksdb_db_file_count(&db) != 0 { ok = false; }
  if !err_not_found(rocksdb_get(&mut db, &text("a"))) { ok = false; }
  if rocksdb_lookup(&mut db, 0, &text("a"), 0) != -1 { ok = false; }
  let st = rocksdb_stats(&db);
  if st.gets != 2 { ok = false; }
  if st.misses != 2 { ok = false; }
  if st.puts != 0 { ok = false; }
  if rocksdb_snapshot_create(&mut db) != 0 { ok = false; }
  if rocksdb_oldest_snapshot(&db) != 0 { ok = false; }
  return assert(ok, name);
}

// --------------------------------------------------
//  main
// --------------------------------------------------

fn main() -> Int {
  io.println("=== xiom.rocksdb conformance tests ===");
  var failed: Int = 0;
  let r1 = t1();
  if r1.passed { io.println("  [PASS] " + r1.name); } else { io.println("  [FAIL] " + r1.name); failed = failed + 1; }
  let r2 = t2();
  if r2.passed { io.println("  [PASS] " + r2.name); } else { io.println("  [FAIL] " + r2.name); failed = failed + 1; }
  let r3 = t3();
  if r3.passed { io.println("  [PASS] " + r3.name); } else { io.println("  [FAIL] " + r3.name); failed = failed + 1; }
  let r4 = t4();
  if r4.passed { io.println("  [PASS] " + r4.name); } else { io.println("  [FAIL] " + r4.name); failed = failed + 1; }
  let r5 = t5();
  if r5.passed { io.println("  [PASS] " + r5.name); } else { io.println("  [FAIL] " + r5.name); failed = failed + 1; }
  let r6 = t6();
  if r6.passed { io.println("  [PASS] " + r6.name); } else { io.println("  [FAIL] " + r6.name); failed = failed + 1; }
  let r7 = t7();
  if r7.passed { io.println("  [PASS] " + r7.name); } else { io.println("  [FAIL] " + r7.name); failed = failed + 1; }
  let r8 = t8();
  if r8.passed { io.println("  [PASS] " + r8.name); } else { io.println("  [FAIL] " + r8.name); failed = failed + 1; }
  let r9 = t9();
  if r9.passed { io.println("  [PASS] " + r9.name); } else { io.println("  [FAIL] " + r9.name); failed = failed + 1; }
  let r10 = t10();
  if r10.passed { io.println("  [PASS] " + r10.name); } else { io.println("  [FAIL] " + r10.name); failed = failed + 1; }
  let r11 = t11();
  if r11.passed { io.println("  [PASS] " + r11.name); } else { io.println("  [FAIL] " + r11.name); failed = failed + 1; }
  let r12 = t12();
  if r12.passed { io.println("  [PASS] " + r12.name); } else { io.println("  [FAIL] " + r12.name); failed = failed + 1; }
  let r13 = t13();
  if r13.passed { io.println("  [PASS] " + r13.name); } else { io.println("  [FAIL] " + r13.name); failed = failed + 1; }
  let r14 = t14();
  if r14.passed { io.println("  [PASS] " + r14.name); } else { io.println("  [FAIL] " + r14.name); failed = failed + 1; }
  let r15 = t15();
  if r15.passed { io.println("  [PASS] " + r15.name); } else { io.println("  [FAIL] " + r15.name); failed = failed + 1; }
  let r16 = t16();
  if r16.passed { io.println("  [PASS] " + r16.name); } else { io.println("  [FAIL] " + r16.name); failed = failed + 1; }
  let r17 = t17();
  if r17.passed { io.println("  [PASS] " + r17.name); } else { io.println("  [FAIL] " + r17.name); failed = failed + 1; }
  let r18 = t18();
  if r18.passed { io.println("  [PASS] " + r18.name); } else { io.println("  [FAIL] " + r18.name); failed = failed + 1; }
  let r19 = t19();
  if r19.passed { io.println("  [PASS] " + r19.name); } else { io.println("  [FAIL] " + r19.name); failed = failed + 1; }
  let r20 = t20();
  if r20.passed { io.println("  [PASS] " + r20.name); } else { io.println("  [FAIL] " + r20.name); failed = failed + 1; }
  let r21 = t21();
  if r21.passed { io.println("  [PASS] " + r21.name); } else { io.println("  [FAIL] " + r21.name); failed = failed + 1; }
  let r22 = t22();
  if r22.passed { io.println("  [PASS] " + r22.name); } else { io.println("  [FAIL] " + r22.name); failed = failed + 1; }
  let r23 = t23();
  if r23.passed { io.println("  [PASS] " + r23.name); } else { io.println("  [FAIL] " + r23.name); failed = failed + 1; }
  let r24 = t24();
  if r24.passed { io.println("  [PASS] " + r24.name); } else { io.println("  [FAIL] " + r24.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.rocksdb: all tests passed");
  } else {
    io.println("xiom.rocksdb: tests failed");
  }
  return failed;
}
