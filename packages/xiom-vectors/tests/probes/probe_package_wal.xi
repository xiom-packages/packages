// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Probe: xiom.wal package adoption (first-consumption gate, M-R/pivot
// 2026-10-10). Verifies that the registry package is consumable from this
// project (xiom.toml [dependencies]; C-PULSE-02 resolved in v0.64.2) and
// pins the ALIGNMENT that makes it the single WAL home:
//   - op codes 1..7 are IDENTICAL to the lane's file codec codes
//     (Insert..SnapshotMarker), with 8/9/10 the txn ops;
//   - tagged records roundtrip exactly (lsn/op/key/value/payload/timestamp)
//     including the empty-payload form;
//   - wal_open resumes LSNs; a torn tail is skipped by replay and healed
//     on open (append-after-heal continues the prefix);
//   - a missing path opens at lsn 1.
// Exit = failed checks.

module probe_package_wal

use xiom.wal;
use xiom.string.slice;
use xiom.string.split;
use xiom.io;
use xiom.convert;

fn check(ok: Bool, name: Str, fails: Int) -> Int {
  if ok { io.println("  [PASS] " + name); return fails; }
  io.println("  [FAIL] " + name); return fails + 1;
}

fn mk_payload(a: Int, b: Int) -> Vec[Int] {
  var p = Vec[Int].new();
  p.push(a);
  p.push(b);
  return p;
}

fn main() -> Int {
  io.println("=== xvector probe: xiom.wal package adoption ===");
  var fails: Int = 0;
  var path = "out/package_wal_probe.log";
  var torn = "out/package_wal_probe_torn.log";
  io.remove_file(path);
  io.remove_file(torn);

  // ---- op-code alignment (the single-home reason) ----
  fails = check(wal_op_code(WalOpKind.Insert) == 1
    && wal_op_code(WalOpKind.Update) == 2
    && wal_op_code(WalOpKind.Delete) == 3
    && wal_op_code(WalOpKind.SegmentSeal) == 4
    && wal_op_code(WalOpKind.ManifestUpdate) == 5
    && wal_op_code(WalOpKind.Checkpoint) == 6
    && wal_op_code(WalOpKind.SnapshotMarker) == 7,
    "codes: 1..7 identical to the lane codec (Insert..SnapshotMarker)", fails);
  fails = check(wal_op_code(WalOpKind.BeginTxn) == 8
    && wal_op_code(WalOpKind.CommitTxn) == 9
    && wal_op_code(WalOpKind.AbortTxn) == 10
    && wal_op_from_code(9) == WalOpKind.CommitTxn,
    "codes: 8/9/10 txn ops + from_code roundtrip", fails);

  // ---- tagged roundtrip ----
  var w = wal_open(path);
  var p1 = mk_payload(4, 1078530011);
  var l1 = wal_append_tagged(&mut w, WalOpKind.Insert, 7, 1, p1, 1001);
  var l2 = wal_append_tagged(&mut w, WalOpKind.Update, 7, 1, mk_payload(9, 9), 1002);
  var empty = Vec[Int].new();
  var l3 = wal_append_tagged(&mut w, WalOpKind.Delete, 7, 1, empty, 1003);
  var l4 = wal_append_tagged(&mut w, WalOpKind.ManifestUpdate, 0, 3, mk_payload(2, 55), 1004);
  var l5 = wal_append_tagged(&mut w, WalOpKind.Checkpoint, 0, 0, mk_payload(5, 0), 1005);
  fails = check(l1 == 1 && l2 == 2 && l3 == 3 && l4 == 4 && l5 == 5,
    "append: LSNs assigned 1..5", fails);
  var recs = wal_replay(path);
  fails = check(recs.len() == 5, "replay: five records", fails);
  var all_ok: Bool = recs.len() == 5;
  if all_ok {
    var r1 = recs[0];
    all_ok = r1.lsn == 1 && r1.op == WalOpKind.Insert && r1.key == 7 && r1.value == 1
      && r1.payload.len() == 2 && r1.payload[0] == 4 && r1.payload[1] == 1078530011
      && r1.timestamp == 1001;
    var r3 = recs[2];
    all_ok = all_ok && r3.op == WalOpKind.Delete && r3.payload.len() == 0 && r3.timestamp == 1003;
    var r4 = recs[3];
    all_ok = all_ok && r4.op == WalOpKind.ManifestUpdate && r4.value == 3
      && r4.payload[1] == 55 && r4.timestamp == 1004;
  }
  fails = check(all_ok, "replay: fields exact (op/key/value/payload/timestamp)", fails);

  // ---- resume + torn tail ----
  var w2 = wal_open(path);
  var l6 = wal_append_tagged(&mut w2, WalOpKind.Insert, 8, 2, mk_payload(1, 1), 1006);
  fails = check(l6 == 6 && wal_replay(path).len() == 6, "resume: reopened handle continues at lsn 6", fails);

  var raw = io.read_file(path);
  var content: Str = "";
  match raw {
    Ok(c) => { content = c; }
    Err(_) => {}
  }
  var lines = split.str_split(content, "\n");
  var lastline = lines[lines.len() - 2];
  var partial = slice.str_slice(lastline, 0, 6);
  var tbytes = slice.str_bytes(content + partial);
  match io.write_file_bytes(torn, &tbytes) {
    Ok(_) => {}
    Err(_) => { fails = fails + 1; }
  }
  fails = check(wal_replay(torn).len() == 6, "torn tail: replay keeps the complete prefix (6)", fails);
  var w3 = wal_open(torn);
  var l7 = wal_append_tagged(&mut w3, WalOpKind.Insert, 9, 3, mk_payload(2, 2), 1007);
  var trecs = wal_replay(torn);
  fails = check(l7 == 7 && trecs.len() == 7 && trecs[6].key == 9,
    "torn tail: wal_open heals, append continues (7, key 9)", fails);

  // ---- missing path ----
  var missing = "out/package_wal_probe_missing.log";
  io.remove_file(missing);
  var w4 = wal_open(missing);
  var l8 = wal_append_tagged(&mut w4, WalOpKind.Insert, 1, 1, mk_payload(3, 3), 1008);
  fails = check(l8 == 1 && wal_replay(missing).len() == 1,
    "missing path: opens fresh at lsn 1", fails);

  io.remove_file(path);
  io.remove_file(torn);
  io.remove_file(missing);
  io.println("");
  io.println("probe_package_wal: " + convert.int_to_string(fails) + " failed checks");
  return fails;
}
