// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Registry consumption gate: xiom.orbitdb 0.2.1 (ORBITDB Satellite -- the
// embedded/lightweight tier, zero registry deps). Proves the published
// artifact is consumable from the lane XIOM_HOME and that the durable
// embedded loop works end-to-end: validated open -> put/get/range ->
// delete -> transaction commit -> checkpoint -> close/reopen (WAL +
// snapshot recovery inside the package).
// Exit = failed checks.

module probe_package_orbitdb

use xiom.db.engine;
use xiom.io;
use xiom.convert;

fn check(ok: Bool, name: Str, fails: Int) -> Int {
  if ok { io.println("  [PASS] " + name); return fails; }
  io.println("  [FAIL] " + name); return fails + 1;
}

fn main() -> Int {
  io.println("=== xvector probe: xiom.orbitdb 0.2.1 (Satellite embedded tier) ===");
  var fails: Int = 0;
  var p = "out/pkg_orbitdb.db";
  let _c0 = io.remove_file(p);
  let _c1 = io.remove_file(p + ".snap");

  var db = db_file_open(p, 3);
  var opened = db_file_size(&db) == 0 && db_file_last_lsn(&db) == 0;
  fails = check(opened, "open: fresh file-backed Satellite database (order 3)", fails);
  fails = check(db_file_durability(&db) == 1, "open: durability defaults to immediate (fsync-on-ack)", fails);

  var puts_ok: Bool = true;
  var i: Int = 1;
  while i <= 5 {
    if !db_file_put(&mut db, i, i * 10) { puts_ok = false; }
    i = i + 1;
  }
  fails = check(puts_ok && db_file_size(&db) == 5, "put: 5 acked writes (WAL-before-ack)", fails);

  var g3 = db_file_get(&db, 3);
  var g3_ok = false;
  match g3 {
    Some(v) => { if v == 30 { g3_ok = true; } }
    None => {}
  }
  fails = check(g3_ok, "get: key 3 -> 30", fails);

  var r = db_file_range(&db, 2, 4);
  fails = check(r.len() == 3 && r[0] == 20 && r[1] == 30 && r[2] == 40,
    "range: [2,4] -> 20,30,40 in key order", fails);

  fails = check(db_file_delete(&mut db, 2) && db_file_size(&db) == 4,
    "delete: key 2 removed", fails);
  var g2 = db_file_get(&db, 2);
  var g2_none = false;
  match g2 {
    Some(_) => {}
    None => { g2_none = true; }
  }
  fails = check(g2_none, "delete: key 2 gone", fails);

  var txn_ok = db_file_txn_begin(&mut db) && db_file_txn_put(&mut db, 6, 60)
    && db_file_txn_put(&mut db, 7, 70) && db_file_txn_commit(&mut db);
  var g6 = db_file_get(&db, 6);
  var g6_ok = false;
  match g6 {
    Some(v) => { if v == 60 { g6_ok = true; } }
    None => {}
  }
  fails = check(txn_ok && g6_ok && db_file_size(&db) == 6, "txn: begin/put/commit applies 2 rows", fails);

  var cp = db_file_checkpoint(&mut db);
  fails = check(cp > 0, "checkpoint: anchor LSN returned", fails);

  // Close/reopen: the package's own WAL + snapshot recovery must rebuild the
  // exact state (this is the embedded-tier durability promise).
  var db2 = db_file_open(p, 3);
  var g7 = db_file_get(&db2, 7);
  var g7_ok = false;
  match g7 {
    Some(v) => { if v == 70 { g7_ok = true; } }
    None => {}
  }
  fails = check(db_file_size(&db2) == 6 && g7_ok, "reopen: snapshot + tail replay keeps every acked row", fails);
  fails = check(db_file_last_lsn(&db2) >= cp, "reopen: LSN monotonic against the checkpoint anchor", fails);

  let _r0 = io.remove_file(p);
  let _r1 = io.remove_file(p + ".snap");

  io.println("");
  io.println("probe_package_orbitdb: " + convert.int_to_string(fails) + " failed checks");
  return fails;
}
