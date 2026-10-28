// XIOM ORBITDB -- conformance suite split: pager (M1.1b A3/A4).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom_db_conformance_pager

use xiom.io;
use xiom.convert;
use xiom.test;
use xiom.db.engine;
use xiom.db.index.btree;
use xiom_db_suite_common;

fn pager_cleanup(path: Str) {
  match io.remove_file(path) { Ok(_) => {} Err(_) => {} }
  match io.remove_file(path + ".snap") { Ok(_) => {} Err(_) => {} }
}

// 1200 keys at order 4 produce ~400+ nodes: more than the 256-frame cache,
// so a full scan must miss and clock-evict. All values must still be exact.
fn run_pager_lazy_bounded() -> Int {
  let path = "orbitdb-suite-pager-bounded.wal";
  pager_cleanup(path);
  var db = db_file_open_cfg(path, 4, 2);
  let _ = db_file_set_durability(&mut db, 0);
  var i = 1;
  while i <= 1200 {
    if !db_file_put(&mut db, i, i * 10) { return 1; }
    i = i + 1;
  }
  if db_file_checkpoint(&mut db) < 0 { return 2; }
  var db2 = db_file_open(path, 4);
  let _ = db_file_set_durability(&mut db2, 0);
  if !db2.tree.store.paged { return 3; }
  if db2.tree.store.frames.len() != 256 { return 4; }
  // Nothing is decoded at open: the first search must miss.
  let st0 = ns_pager_stats(&db2.tree.store);
  if st0[1] != 0 { return 6; }
  if db_file_size(&db2) != 1200 { return 5; }
  var j = 1;
  while j <= 1200 {
    match db_file_get(&db2, j) {
      None => { return 7; }
      Some(v) => { if v != j * 10 { return 8; } }
    }
    j = j + 1;
  }
  let st = ns_pager_stats(&db2.tree.store);
  if st[0] <= 0 { return 9; }   // hits
  if st[1] <= 0 { return 10; }  // misses
  if st[2] <= 0 { return 11; }  // evictions
  if st[4] != 0 { return 12; }  // corrupt
  pager_cleanup(path);
  return 0;
}

fn test_pager_lazy_bounded() -> TestResult {
  let rc = run_pager_lazy_bounded();
  if rc == 0 { return assert(true, "pager: lazy v2 load + 256-frame cache (misses/evictions, exact values)"); }
  return assert(false, "pager: lazy+bounded failed rc=" + int_to_str(rc));
}

// Tail after a checkpoint -> reopen (WAL replay) -> force evictions -> new
// writes -> checkpoint -> reopen. Exercises dirty-frame spill at write_gen
// and the paged checkpoint path.
fn run_pager_dirty_spill_checkpoint() -> Int {
  let path = "orbitdb-suite-pager-spill.wal";
  pager_cleanup(path);
  var db = db_file_open_cfg(path, 4, 2);
  let _ = db_file_set_durability(&mut db, 0);
  var i = 1;
  while i <= 1200 {
    if !db_file_put(&mut db, i, i * 10) { return 1; }
    i = i + 1;
  }
  if db_file_checkpoint(&mut db) < 0 { return 2; }
  // Tail after the snapshot (replayed on the paged reopen).
  i = 1201;
  while i <= 1400 {
    if !db_file_put(&mut db, i, i * 10) { return 3; }
    i = i + 1;
  }
  var db2 = db_file_open(path, 4);
  let _ = db_file_set_durability(&mut db2, 0);
  if db_file_size(&db2) != 1400 { return 4; }
  // Force cache churn so replay-dirtied nodes spill at the write generation.
  var j = 1;
  while j <= 1400 {
    match db_file_get(&db2, j) {
      None => { return 5; }
      Some(v) => { if v != j * 10 { return 6; } }
    }
    j = j + 1;
  }
  if !db_file_put(&mut db2, 1401, 14010) { return 7; }
  if db_file_checkpoint(&mut db2) < 0 { return 8; }
  var db3 = db_file_open(path, 4);
  let _ = db_file_set_durability(&mut db3, 0);
  if db_file_size(&db3) != 1401 { return 9; }
  j = 1;
  while j <= 1401 {
    match db_file_get(&db3, j) {
      None => { return 10; }
      Some(v) => { if v != j * 10 { return 11; } }
    }
    j = j + 1;
  }
  let st = ns_pager_stats(&db3.tree.store);
  if st[4] != 0 { return 12; }
  pager_cleanup(path);
  return 0;
}

fn test_pager_dirty_spill_checkpoint() -> TestResult {
  let rc = run_pager_dirty_spill_checkpoint();
  if rc == 0 { return assert(true, "pager: dirty-frame spill + paged checkpoint survive reopen (1401 keys)"); }
  return assert(false, "pager: spill/checkpoint failed rc=" + int_to_str(rc));
}

// Pin churn retires COW shadows; after the pin ends and a checkpoint crosses
// the compaction threshold, the GC rewrite drops every unreachable node and
// renumbers the live tree to dense ids. The reopened file must stay exact.
fn run_pager_gc_compaction() -> Int {
  let path = "orbitdb-suite-pager-gc.wal";
  pager_cleanup(path);
  var db0 = db_file_open_cfg(path, 4, 2);
  let _ = db_file_set_durability(&mut db0, 0);
  var i = 1;
  while i <= 200 {
    if !db_file_put(&mut db0, i, i * 10) { return 1; }
    i = i + 1;
  }
  if db_file_checkpoint(&mut db0) < 0 { return 2; }
  var db = db_file_open(path, 4);
  let _ = db_file_set_durability(&mut db, 0);
  if !db.tree.store.paged { return 3; }
  let s1 = db_file_snapshot_begin(&mut db);
  i = 2;
  while i <= 200 {
    if !db_file_put(&mut db, i, i * 100) { return 4; }
    i = i + 2;
  }
  i = 201;
  while i <= 220 {
    if !db_file_put(&mut db, i, i * 100) { return 5; }
    i = i + 1;
  }
  // Pinned view is untouched by the COW churn.
  match db_file_snapshot_get(&db, s1.id, 2) {
    None => { return 6; }
    Some(v) => { if v != 20 { return 7; } }
  }
  if db_file_checkpoint(&mut db) < 0 { return 8; }
  // Two more pinned generations: the in-place updates re-append the dirty
  // nodes, so block_count crosses node_count + SNAP_COMPACT_SLACK and the
  // checkpoint defers compaction (counted).
  var cycle = 0;
  while cycle < 2 {
    i = 2;
    while i <= 200 {
      if !db_file_put(&mut db, i, i * 100) { return 81; }
      i = i + 2;
    }
    if db_file_checkpoint(&mut db) < 0 { return 82; }
    cycle = cycle + 1;
  }
  if db_file_compaction_deferrals(&db) < 1 { return 9; }
  let high_water = db.tree.store.count;
  if !db_file_snapshot_end(&mut db, s1.id) { return 10; }
  if ns_pending_count(&db.tree.store) != 0 { return 11; }
  // Second checkpoint (no pins) crosses the threshold -> GC compaction.
  if db_file_checkpoint(&mut db) < 0 { return 12; }
  if db.tree.store.count >= high_water { return 13; }
  var db2 = db_file_open(path, 4);
  let _ = db_file_set_durability(&mut db2, 0);
  if db_file_size(&db2) != 220 { return 14; }
  match db_file_get(&db2, 2) {
    None => { return 15; }
    Some(v) => { if v != 200 { return 16; } }
  }
  match db_file_get(&db2, 3) {
    None => { return 17; }
    Some(v) => { if v != 30 { return 18; } }
  }
  match db_file_get(&db2, 220) {
    None => { return 19; }
    Some(v) => { if v != 22000 { return 20; } }
  }
  pager_cleanup(path);
  return 0;
}

fn test_pager_gc_compaction() -> TestResult {
  let rc = run_pager_gc_compaction();
  if rc == 0 { return assert(true, "pager: deferred free + GC compaction (pin churn released, ids renumbered)"); }
  return assert(false, "pager: GC compaction failed rc=" + int_to_str(rc));
}
fn main() -> Int {
  io.println("=== XIOM DB Conformance: pager ===");
  var failed: Int = 0;
  var total: Int = 0;
  let r1 = test_pager_lazy_bounded();
  total = total + 1; failed = failed + report(r1.passed, r1.name);
  let r2 = test_pager_dirty_spill_checkpoint();
  total = total + 1; failed = failed + report(r2.passed, r2.name);
  let r3 = test_pager_gc_compaction();
  total = total + 1; failed = failed + report(r3.passed, r3.name);
  let passed = total - failed;
  io.println("XIOM DB Conformance [pager]: " + int_to_str(passed) + "/" + int_to_str(total) + " passed" + (if failed > 0 { " (" + int_to_str(failed) + " FAILED)" } else { "" }));
  return failed;
}
