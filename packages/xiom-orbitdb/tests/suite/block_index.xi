// XIOM ORBITDB -- conformance suite split: block_index (R2, 2026-10-18).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom_db_conformance_block_index

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

// m375 write-path fallback: the byte-native encoder must produce exactly the
// same 4096 bytes as the Vec[Int] encoder it replaces in block_store_put.
fn block_enc_eq(gen: Int, pid: Int, p: &Vec[Int]) -> Bool {
  let old = block_encode_page(gen, pid, p);
  var nb = Vec[UInt8].new();
  if !block_encode_page_into(&mut nb, gen, pid, p) { return false; }
  if old.len() != nb.len() { return false; }
  var i = 0;
  while i < old.len() {
    if old[i] != (nb[i] as Int) { return false; }
    i = i + 1;
  }
  return true;
}

fn run_block_byte_encoder() -> Int {
  var empty = Vec[Int].new();
  if !block_enc_eq(0, 0, &empty) { return 1; }
  if !block_enc_eq(1, 42, &empty) { return 2; }
  if !block_enc_eq(123456789, 987654321, &empty) { return 3; }
  var one = Vec[Int].new();
  one.push(7);
  if !block_enc_eq(9, 3, &one) { return 4; }
  var maxp = Vec[Int].new();
  var i = 0;
  while i < 4056 {
    maxp.push(i & 0xFF);
    i = i + 1;
  }
  if !block_enc_eq(5, 6, &maxp) { return 5; }
  var bad = Vec[Int].new();
  bad.push(256);
  var nb = Vec[UInt8].new();
  if block_encode_page_into(&mut nb, 1, 1, &bad) { return 6; }
  return 0;
}

fn test_block_byte_encoder() -> TestResult {
  let rc = run_block_byte_encoder();
  if rc == 0 { return assert(true, "block v2: byte-native page encoder is byte-identical to the Vec encoder"); }
  return assert(false, "block v2: byte encoder mismatch rc=" + int_to_str(rc));
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
  io.println("=== XIOM DB Conformance: block_index ===");
  var failed: Int = 0;
  var total: Int = 0;
  let r101 = test_block_v2_kat();
  total = total + 1; failed = failed + report(r101.passed, r101.name);
  let r102 = test_block_v2_roundtrip();
  total = total + 1; failed = failed + report(r102.passed, r102.name);
  let r103 = test_block_v2_rejects();
  total = total + 1; failed = failed + report(r103.passed, r103.name);
  let r104 = test_block_v2_header();
  total = total + 1; failed = failed + report(r104.passed, r104.name);
  let r105 = test_block_byte_encoder();
  total = total + 1; failed = failed + report(r105.passed, r105.name);
  let r107 = test_secondary_index_build();
  total = total + 1; failed = failed + report(r107.passed, r107.name);
  let r108 = test_secondary_index_maintenance();
  total = total + 1; failed = failed + report(r108.passed, r108.name);
  let r109 = test_query_index_plan();
  total = total + 1; failed = failed + report(r109.passed, r109.name);
  let r110 = test_query_order_limit();
  total = total + 1; failed = failed + report(r110.passed, r110.name);
  let passed = total - failed;
  io.println("XIOM DB Conformance [block_index]: " + int_to_str(passed) + "/" + int_to_str(total) + " passed" + (if failed > 0 { " (" + int_to_str(failed) + " FAILED)" } else { "" }));
  return failed;
}