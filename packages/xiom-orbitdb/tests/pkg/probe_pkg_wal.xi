// XIOM ORBITDB consumer probe -- xiom.wal 0.1.0 (registry, eco-v0.1.121).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// First ORBITDB consumer pass on a registry package (PULSE pattern), against
// the stand-alone WAL extracted from this repo's src/wal_file.xi. The probe
// is the acceptance the package README cites: record shape, LSN resume,
// tagged payloads, torn-tail skip + heal, truncate preserving payloads, op
// codes -- plus TWO-WAY format interop (the package writes / our reference
// reader reads, and the reverse), which the "one format" claim requires.
//
// Composition: tests/pkg/xiom.toml (this dir + ../../src + registry
// dependency xiom-wal = 0.1.0 mapped from the installed package).
//
// Env: ORBITDB_PKG_WAL -- segment path (default probe-logs/pkg-wal.log);
//      the second interop file is <path>.ours. Both are removed first.
// Exit: 0 = all checks passed, 1 = check failed.

module orbitdb_probe_pkg_wal

use xiom.io;
use xiom.os.env;
use xiom.convert;
use xiom.string;
use xiom.db.wal_file;
use xiom.wal;

fn check(ok: Bool, name: Str, fails: Int) -> Int {
  if ok { io.println("  [PASS] " + name); return fails; }
  io.println("  [FAIL] " + name);
  return fails + 1;
}

fn main() -> Int {
  let base = env.var_or("ORBITDB_PKG_WAL", "probe-logs/pkg-wal.log");
  let base2 = base + ".ours";
  var fails: Int = 0;
  match io.remove_file(base) { Ok(_) => {} Err(_) => {} }
  match io.remove_file(base2) { Ok(_) => {} Err(_) => {} }

  // --- package writer: append + LSN assignment + len/last_lsn ------------
  var w = wal_open(base);
  let l1 = wal_append(&mut w, WalOpKind.Insert, 1, 11);
  let l2 = wal_append(&mut w, WalOpKind.Update, 1, 12);
  let l3 = wal_append(&mut w, WalOpKind.Delete, 2, 0);
  var tag = Vec[Int].new();
  tag.push(7);
  tag.push(42);
  let l4 = wal_append_tagged(&mut w, WalOpKind.Insert, 3, 33, tag, 1234);
  fails = check(l1 == 1 && l2 == 2 && l3 == 3 && l4 == 4, "pkg: LSNs 1..4 assigned in order", fails);
  fails = check(wal_flush(&mut w), "pkg: wal_flush no-op success (documented)", fails);
  fails = check(wal_len(base) == 4 && wal_last_lsn(base) == 4, "pkg: wal_len/last_lsn after appends", fails);

  // --- reopen resumes the LSN sequence -----------------------------------
  var w2 = wal_open(base);
  fails = check(w2.next_lsn == 5, "pkg: reopen resumes next_lsn (5)", fails);
  let l5 = wal_append(&mut w2, WalOpKind.Insert, 4, 44);
  fails = check(l5 == 5, "pkg: append after reopen gets LSN 5", fails);

  // --- replay: fields + tagged payload round-trip -------------------------
  let recs = wal_replay(base);
  var ok = recs.len() == 5;
  if ok {
    ok = recs[0].lsn == 1 && wal_op_code(recs[0].op) == 1 && recs[0].key == 1 && recs[0].value == 11;
    ok = ok && recs[3].payload.len() == 2 && recs[3].payload[0] == 7 && recs[3].payload[1] == 42;
    ok = ok && recs[3].timestamp == 1234 && recs[4].lsn == 5 && recs[4].value == 44;
  }
  fails = check(ok, "pkg: replay fields + tagged payload (payload[0]=subtype)", fails);

  // --- op code round-trip 1..10 + write-kind -------------------------------
  var codes_ok = true;
  var c: Int = 1;
  while c <= 10 {
    if wal_op_code(wal_op_from_code(c)) != c { codes_ok = false; }
    c = c + 1;
  }
  if !wal_op_is_write(WalOpKind.Insert) || !wal_op_is_write(WalOpKind.Update) {
    codes_ok = false;
  }
  if !wal_op_is_write(WalOpKind.Delete) || wal_op_is_write(WalOpKind.Checkpoint) {
    codes_ok = false;
  }
  fails = check(codes_ok, "pkg: op code round-trip 1..10 + write-kind", fails);

  // --- truncate keeps lsn >= from, payloads preserved ----------------------
  fails = check(wal_truncate(base, 3), "pkg: truncate returns ok", fails);
  let recs2 = wal_replay(base);
  var ok5 = recs2.len() == 3 && recs2[0].lsn == 3 && recs2[2].lsn == 5;
  if ok5 {
    ok5 = recs2[1].payload.len() == 2 && recs2[1].payload[1] == 42 && recs2[1].timestamp == 1234;
  }
  fails = check(ok5, "pkg: truncate keeps lsn>=3 with payload + timestamp", fails);
  var w3 = wal_open(base);
  fails = check(w3.next_lsn == 6, "pkg: reopen after truncate resumes 6", fails);

  // --- torn tail: skipped on replay, healed on open, append continues ------
  match io.append_file(base, "torn|") { Ok(_) => {} Err(_) => { fails = fails + 1; } }
  let recs3 = wal_replay(base);
  fails = check(recs3.len() == 3, "pkg: torn tail skipped on replay", fails);
  var w4 = wal_open(base);
  let l6 = wal_append(&mut w4, WalOpKind.Insert, 5, 55);
  fails = check(l6 == 6, "pkg: heal-before-append continues at LSN 6", fails);
  let recs4 = wal_replay(base);
  fails = check(recs4.len() == 4 && recs4[3].lsn == 6, "pkg: replay after heal has 4 records", fails);

  // --- INTEROP A: package-written segment reads with ORBITDB's reader ------
  var ow = wal_file_open(base);
  let orecs = wal_file_replay(base);
  var ok7 = ow.next_lsn == 7 && orecs.len() == 4;
  if ok7 {
    ok7 = orecs[0].lsn == 3 && orecs[0].key == 2 && orecs[1].payload.len() == 2;
    ok7 = ok7 && orecs[1].payload[0] == 7 && orecs[3].lsn == 6 && orecs[3].value == 55;
  }
  fails = check(ok7, "interop: package-written segment reads with ORBITDB's reader", fails);

  // --- INTEROP B: ORBITDB-written segment reads with the package -----------
  var w5 = wal_file_open(base2);
  var tag2 = Vec[Int].new();
  tag2.push(9);
  let o1 = wal_file_append(&mut w5, WALOpKind.Insert, 10, 100);
  let o2 = wal_file_append_tagged(&mut w5, WALOpKind.Update, 10, 101, tag2, 777);
  fails = check(o1 == 1 && o2 == 2, "interop: ORBITDB writer assigns LSNs 1..2", fails);
  let precs = wal_replay(base2);
  var ok8 = precs.len() == 2;
  if ok8 {
    ok8 = precs[1].key == 10 && precs[1].value == 101 && precs[1].timestamp == 777;
    ok8 = ok8 && precs[1].payload.len() == 1 && precs[1].payload[0] == 9;
  }
  fails = check(ok8, "interop: ORBITDB-written segment reads with package replay", fails);
  var w6 = wal_open(base2);
  fails = check(w6.next_lsn == 3, "interop: package resumes LSN from ORBITDB-written segment", fails);

  // --- byte-level format parity (codec v1 literals) ------------------------
  match io.read_file(base2) {
    Ok(content) => {
      var ok9 = str_starts_with(content, "1|1|10|100|0\n");
      ok9 = ok9 && str_contains(content, "2|2|10|101|777|9\n");
      fails = check(ok9, "byte parity: codec v1 line literals identical", fails);
    }
    Err(_) => { fails = fails + 1; }
  }

  if fails == 0 { io.println("pkg-wal: GREEN"); return 0; }
  io.println("pkg-wal: RED fails=" + convert.int_to_string(fails));
  return 1;
}
