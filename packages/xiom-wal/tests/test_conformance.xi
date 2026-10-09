// XIOM -- xiom.wal conformance tests (21 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Every fixture is created in fs_temp_dir() under a per-run prefix
// ("xiomwal-<time>-<tag>.seg"); nothing is created outside it and every file
// is removed with io.remove_file (segment + .tmp). Stable values only, no
// timestamp assertions; one [PASS]/[FAIL] line per check; exit 0 only when
// green.
//
// Covered: open/create + append (len, last_lsn, next_lsn); monotonic resume
// on reopen; replay field identity incl. payload CSV round-trip and the
// payload[0] tag; op-code round-trip codes 1-10 + wal_op_is_write truth
// table; malformed line skipped; torn tail skipped on replay, healed by
// wal_open + append; truncate keeps lsn >= from with payloads intact and
// reopen resumes; empty/missing file; in-memory vocabulary (writer
// append/flush/current/synced, read_all/read_from, checkpoint_can_truncate,
// recovery_scan); WalLsn helpers; wal_record_new; wal_close no-op; wal_flush
// documented no-op success.

module wal_tests

use xiom.io;
use xiom.io.fs;
use xiom.test;
use xiom.wal;
use xiom.string;
use xiom.convert;

// --------------------------------------------------
//  Helpers
// --------------------------------------------------

fn str_eq(a: Str, b: Str) -> Bool {
  return string.str_compare(a, b) == 0;
}

fn ints_eq(a: &Vec[Int], b: &Vec[Int]) -> Bool {
  if a.len() != b.len() { return false; }
  var i = 0;
  while i < a.len() {
    if a[i] != b[i] { return false; }
    i = i + 1;
  }
  return true;
}

fn wal_tmp(dir: Str, tag: Str) -> Str {
  return io.join_paths(dir, "xiomwal-" + convert.int_to_string(io.time_now()) + "-" + tag + ".seg");
}

fn cleanup(path: Str) {
  let _ = io.remove_file(path);
  let _ = io.remove_file(path + ".tmp");
}

fn finish(ok: Bool, name: Str, path: Str) -> TestResult {
  cleanup(path);
  return assert(ok, name);
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1_open_append(dir: Str) -> TestResult {
  let name = "open/create + append 5: len, last_lsn and next_lsn track the log";
  let path = wal_tmp(dir, "t01");
  cleanup(path);
  var w = wal_open(path);
  var ok = true;
  if w.next_lsn != 1 { ok = false; }
  if wal_len(path) != 0 { ok = false; }
  if wal_last_lsn(path) != 0 { ok = false; }
  var i = 1;
  while i <= 5 {
    let lsn = wal_append(&mut w, WalOpKind.Insert, i, i * 10);
    if lsn != i { ok = false; }
    i = i + 1;
  }
  if w.next_lsn != 6 { ok = false; }
  if wal_len(path) != 5 { ok = false; }
  if wal_last_lsn(path) != 5 { ok = false; }
  // Last record field identity (plain append: ts 0, empty payload).
  let records = wal_replay(path);
  if records.len() != 5 {
    ok = false;
  } else {
    let last = records[4];
    if last.lsn != 5 { ok = false; }
    if wal_op_code(last.op) != 1 { ok = false; }
    if last.key != 5 { ok = false; }
    if last.value != 50 { ok = false; }
    if last.timestamp != 0 { ok = false; }
    if last.payload.len() != 0 { ok = false; }
  }
  return finish(ok, name, path);
}

fn t2_reopen_resume(dir: Str) -> TestResult {
  let name = "reopen resumes next_lsn from the last valid record";
  let path = wal_tmp(dir, "t02");
  cleanup(path);
  var w = wal_open(path);
  var ok = true;
  let a1 = wal_append(&mut w, WalOpKind.Insert, 1, 10);
  let a2 = wal_append(&mut w, WalOpKind.Update, 2, 20);
  let a3 = wal_append(&mut w, WalOpKind.Delete, 3, 30);
  if a1 != 1 { ok = false; }
  if a2 != 2 { ok = false; }
  if a3 != 3 { ok = false; }
  var w2 = wal_open(path);
  if w2.next_lsn != 4 { ok = false; }
  let a4 = wal_append(&mut w2, WalOpKind.Insert, 4, 40);
  if a4 != 4 { ok = false; }
  if wal_len(path) != 4 { ok = false; }
  if wal_last_lsn(path) != 4 { ok = false; }
  return finish(ok, name, path);
}

fn t3_replay_identity(dir: Str) -> TestResult {
  let name = "replay returns exact fields + payload[0] subtype tag";
  let path = wal_tmp(dir, "t03");
  cleanup(path);
  var w = wal_open(path);
  var payload = Vec[Int].new();
  payload.push(7); payload.push(11); payload.push(13);
  let lsn = wal_append_tagged(&mut w, WalOpKind.Update, 42, 99, payload, 1234);
  let lsn2 = wal_append(&mut w, WalOpKind.Insert, 1, 10);
  var ok = true;
  if lsn != 1 { ok = false; }
  if lsn2 != 2 { ok = false; }
  let records = wal_replay(path);
  if records.len() != 2 {
    ok = false;
  } else {
    let rec = records[0];
    if rec.lsn != 1 { ok = false; }
    if wal_op_code(rec.op) != 2 { ok = false; }
    if rec.key != 42 { ok = false; }
    if rec.value != 99 { ok = false; }
    if rec.timestamp != 1234 { ok = false; }
    if rec.payload.len() != 3 { ok = false; }
    if rec.payload[0] != 7 { ok = false; }
    if rec.payload[1] != 11 { ok = false; }
    if rec.payload[2] != 13 { ok = false; }
    let rec2 = records[1];
    if rec2.payload.len() != 0 { ok = false; }
    if rec2.timestamp != 0 { ok = false; }
  }
  return finish(ok, name, path);
}

fn t4_payload_csv_roundtrip(dir: Str) -> TestResult {
  let name = "payload CSV round-trips across records (zeros and large ints)";
  let path = wal_tmp(dir, "t04");
  cleanup(path);
  var w = wal_open(path);
  var p1 = Vec[Int].new();
  p1.push(0); p1.push(255); p1.push(65536); p1.push(123456789);
  var p2 = Vec[Int].new();
  p2.push(3); p2.push(0);
  let l1 = wal_append_tagged(&mut w, WalOpKind.SnapshotMarker, 5, 50, p1, 77);
  let l2 = wal_append_tagged(&mut w, WalOpKind.BeginTxn, 6, 60, p2, 88);
  var ok = true;
  if l1 != 1 { ok = false; }
  if l2 != 2 { ok = false; }
  let records = wal_replay(path);
  if records.len() != 2 {
    ok = false;
  } else {
    if !ints_eq(&records[0].payload, &p1) { ok = false; }
    if !ints_eq(&records[1].payload, &p2) { ok = false; }
    if records[0].payload[0] != 0 { ok = false; }
    if records[1].timestamp != 88 { ok = false; }
  }
  return finish(ok, name, path);
}

fn t5_op_roundtrip(dir: Str) -> TestResult {
  let name = "wal_op_code/wal_op_from_code round-trip codes 1..10";
  let path = wal_tmp(dir, "t05");
  cleanup(path);
  var ok = true;
  var code = 1;
  while code <= 10 {
    let op = wal_op_from_code(code);
    if wal_op_code(op) != code { ok = false; }
    code = code + 1;
  }
  // Unknown codes fall back to Insert (code 1), matching the reference.
  if wal_op_code(wal_op_from_code(0)) != 1 { ok = false; }
  if wal_op_code(wal_op_from_code(99)) != 1 { ok = false; }
  return finish(ok, name, path);
}

fn t6_op_is_write(dir: Str) -> TestResult {
  let name = "wal_op_is_write is true only for Insert/Update/Delete";
  let path = wal_tmp(dir, "t06");
  cleanup(path);
  var ok = true;
  if !wal_op_is_write(WalOpKind.Insert) { ok = false; }
  if !wal_op_is_write(WalOpKind.Update) { ok = false; }
  if !wal_op_is_write(WalOpKind.Delete) { ok = false; }
  if wal_op_is_write(WalOpKind.SegmentSeal) { ok = false; }
  if wal_op_is_write(WalOpKind.ManifestUpdate) { ok = false; }
  if wal_op_is_write(WalOpKind.Checkpoint) { ok = false; }
  if wal_op_is_write(WalOpKind.SnapshotMarker) { ok = false; }
  if wal_op_is_write(WalOpKind.BeginTxn) { ok = false; }
  if wal_op_is_write(WalOpKind.CommitTxn) { ok = false; }
  if wal_op_is_write(WalOpKind.AbortTxn) { ok = false; }
  return finish(ok, name, path);
}

fn t7_malformed_skipped(dir: Str) -> TestResult {
  let name = "a malformed line is skipped while valid records replay";
  let path = wal_tmp(dir, "t07");
  cleanup(path);
  let wrote = io.write_file(path, "bogus line without separators\n");
  var ok = true;
  if !wrote.is_ok { ok = false; }
  var w = wal_open(path);
  let l1 = wal_append(&mut w, WalOpKind.Insert, 7, 70);
  let l2 = wal_append(&mut w, WalOpKind.Insert, 8, 80);
  if l1 != 1 { ok = false; }
  if l2 != 2 { ok = false; }
  let records = wal_replay(path);
  if records.len() != 2 {
    ok = false;
  } else {
    if records[0].key != 7 { ok = false; }
    if records[1].key != 8 { ok = false; }
  }
  return finish(ok, name, path);
}

fn t8_torn_tail(dir: Str) -> TestResult {
  let name = "torn tail is skipped, then wal_open + append heals and appends";
  let path = wal_tmp(dir, "t08");
  cleanup(path);
  // Two valid records plus a torn tail with NO trailing newline.
  let wrote = io.write_file(path, "1|1|10|100|0\n2|1|20|200|0\ntorn|");
  var ok = true;
  if !wrote.is_ok { ok = false; }
  let before = wal_replay(path);
  if before.len() != 2 { ok = false; }
  if wal_last_lsn(path) != 2 { ok = false; }
  // Reopen: heals the missing newline, resumes from the last valid record.
  var w = wal_open(path);
  if w.next_lsn != 3 { ok = false; }
  let l3 = wal_append(&mut w, WalOpKind.Insert, 30, 300);
  if l3 != 3 { ok = false; }
  let after = wal_replay(path);
  if after.len() != 3 {
    ok = false;
  } else {
    let last = after[2];
    if last.lsn != 3 { ok = false; }
    if last.key != 30 { ok = false; }
    if last.value != 300 { ok = false; }
    // The torn text must not have fused with the new record.
    if wal_last_lsn(path) != 3 { ok = false; }
  }
  return finish(ok, name, path);
}

fn t9_truncate_keep(dir: Str) -> TestResult {
  let name = "truncate keeps every record with lsn >= from_lsn";
  let path = wal_tmp(dir, "t09");
  cleanup(path);
  var w = wal_open(path);
  var ok = true;
  var i = 1;
  while i <= 10 {
    let lsn = wal_append(&mut w, WalOpKind.Insert, i, i * 10);
    if lsn != i { ok = false; }
    i = i + 1;
  }
  let trunc = wal_truncate(path, 6);
  if !trunc { ok = false; }
  if wal_len(path) != 5 { ok = false; }
  if wal_last_lsn(path) != 10 { ok = false; }
  let records = wal_replay(path);
  if records.len() != 5 {
    ok = false;
  } else {
    if records[0].lsn != 6 { ok = false; }
    if records[0].key != 6 { ok = false; }
    if records[4].lsn != 10 { ok = false; }
  }
  return finish(ok, name, path);
}

fn t10_truncate_payload(dir: Str) -> TestResult {
  let name = "truncate preserves payloads of kept records";
  let path = wal_tmp(dir, "t10");
  cleanup(path);
  var w = wal_open(path);
  var ok = true;
  var i = 1;
  while i <= 6 {
    var p = Vec[Int].new();
    p.push(7); p.push(i);
    let lsn = wal_append_tagged(&mut w, WalOpKind.Checkpoint, i, i * 10, p, 900 + i);
    if lsn != i { ok = false; }
    i = i + 1;
  }
  let trunc = wal_truncate(path, 4);
  if !trunc { ok = false; }
  let records = wal_replay(path);
  if records.len() != 3 {
    ok = false;
  } else {
    let r0 = records[0];
    if r0.lsn != 4 { ok = false; }
    if r0.payload.len() != 2 { ok = false; }
    if r0.payload[0] != 7 { ok = false; }
    if r0.payload[1] != 4 { ok = false; }
    if r0.timestamp != 904 { ok = false; }
    let r2 = records[2];
    if r2.payload.len() != 2 { ok = false; }
    if r2.payload[1] != 6 { ok = false; }
    if r2.timestamp != 906 { ok = false; }
  }
  return finish(ok, name, path);
}

fn t11_truncate_reopen(dir: Str) -> TestResult {
  let name = "reopen after truncate resumes from the kept tail";
  let path = wal_tmp(dir, "t11");
  cleanup(path);
  var w = wal_open(path);
  var ok = true;
  var i = 1;
  while i <= 6 {
    let lsn = wal_append(&mut w, WalOpKind.Insert, i, i * 10);
    if lsn != i { ok = false; }
    i = i + 1;
  }
  let trunc = wal_truncate(path, 3);
  if !trunc { ok = false; }
  if wal_len(path) != 4 { ok = false; }
  var w2 = wal_open(path);
  if w2.next_lsn != 7 { ok = false; }
  let l7 = wal_append(&mut w2, WalOpKind.Insert, 11, 110);
  if l7 != 7 { ok = false; }
  if wal_last_lsn(path) != 7 { ok = false; }
  return finish(ok, name, path);
}

fn t12_empty_file(dir: Str) -> TestResult {
  let name = "empty file replays to empty and last_lsn 0";
  let path = wal_tmp(dir, "t12");
  cleanup(path);
  let wrote = io.write_file(path, "");
  var ok = true;
  if !wrote.is_ok { ok = false; }
  if wal_replay(path).len() != 0 { ok = false; }
  if wal_last_lsn(path) != 0 { ok = false; }
  if wal_len(path) != 0 { ok = false; }
  return finish(ok, name, path);
}

fn t13_missing_file(dir: Str) -> TestResult {
  let name = "missing file replays to empty and last_lsn 0";
  let path = wal_tmp(dir, "t13");
  cleanup(path);
  var ok = true;
  if wal_replay(path).len() != 0 { ok = false; }
  if wal_last_lsn(path) != 0 { ok = false; }
  if wal_len(path) != 0 { ok = false; }
  return finish(ok, name, path);
}

fn t14_writer_memory(dir: Str) -> TestResult {
  let name = "in-memory writer append/flush/current/synced";
  let path = wal_tmp(dir, "t14");
  cleanup(path);
  var w = wal_writer_new();
  var ok = true;
  let l1 = wal_writer_append(&mut w, WalOpKind.Insert, 1, 10);
  let l2 = wal_writer_append(&mut w, WalOpKind.Update, 2, 20);
  let l3 = wal_writer_append(&mut w, WalOpKind.Delete, 3, 30);
  if l1 != 1 { ok = false; }
  if l2 != 2 { ok = false; }
  if l3 != 3 { ok = false; }
  if wal_writer_current_lsn(&w) != 3 { ok = false; }
  if wal_writer_synced_lsn(&w) != 0 { ok = false; }
  let flushed = wal_writer_flush(&mut w);
  if !flushed { ok = false; }
  if wal_writer_synced_lsn(&w) != 3 { ok = false; }
  let l4 = wal_writer_append(&mut w, WalOpKind.Insert, 4, 40);
  if l4 != 4 { ok = false; }
  if wal_writer_current_lsn(&w) != 4 { ok = false; }
  return finish(ok, name, path);
}

fn t15_read_all_from(dir: Str) -> TestResult {
  let name = "wal_read_all / wal_read_from preserve order and filter by LSN";
  let path = wal_tmp(dir, "t15");
  cleanup(path);
  var w = wal_writer_new();
  var ok = true;
  var i = 1;
  while i <= 5 {
    let lsn = wal_writer_append(&mut w, WalOpKind.Insert, i, i * 10);
    if lsn != i { ok = false; }
    i = i + 1;
  }
  let all = wal_read_all(&w);
  if all.len() != 5 { ok = false; }
  let tail = wal_read_from(&w, 3);
  if tail.len() != 3 {
    ok = false;
  } else {
    if tail[0].lsn != 3 { ok = false; }
    if tail[2].lsn != 5 { ok = false; }
  }
  let from_one = wal_read_from(&w, 1);
  if from_one.len() != 5 { ok = false; }
  let from_six = wal_read_from(&w, 6);
  if from_six.len() != 0 { ok = false; }
  return finish(ok, name, path);
}

fn t16_checkpoint(dir: Str) -> TestResult {
  let name = "checkpoint_can_truncate is strict below the checkpoint LSN";
  let path = wal_tmp(dir, "t16");
  cleanup(path);
  let cp = checkpoint_new(5, 123);
  var ok = true;
  if cp.lsn != 5 { ok = false; }
  if cp.timestamp != 123 { ok = false; }
  if !checkpoint_can_truncate(&cp, 4) { ok = false; }
  if checkpoint_can_truncate(&cp, 5) { ok = false; }
  if checkpoint_can_truncate(&cp, 6) { ok = false; }
  return finish(ok, name, path);
}

fn t17_recovery_scan(dir: Str) -> TestResult {
  let name = "recovery_scan counts records after the checkpoint";
  let path = wal_tmp(dir, "t17");
  cleanup(path);
  var w = wal_writer_new();
  var ok = true;
  var i = 1;
  while i <= 5 {
    let lsn = wal_writer_append(&mut w, WalOpKind.Insert, i, i * 10);
    if lsn != i { ok = false; }
    i = i + 1;
  }
  let rr = recovery_scan(&w, 2);
  if rr.records_replayed != 3 { ok = false; }
  if rr.last_lsn != 5 { ok = false; }
  if rr.corrupted { ok = false; }
  let rr2 = recovery_scan(&w, 5);
  if rr2.records_replayed != 0 { ok = false; }
  if rr2.last_lsn != 5 { ok = false; }
  return finish(ok, name, path);
}

fn t18_lsn_helpers(dir: Str) -> TestResult {
  let name = "WalLsn value/next helpers are strictly monotonic";
  let path = wal_tmp(dir, "t18");
  cleanup(path);
  let a = wal_lsn(7);
  var ok = true;
  if wal_lsn_value(&a) != 7 { ok = false; }
  let b = wal_lsn_next(&a);
  if wal_lsn_value(&b) != 8 { ok = false; }
  let c = wal_lsn_next(&b);
  if wal_lsn_value(&c) != 9 { ok = false; }
  if wal_lsn_value(&a) != 7 { ok = false; }
  return finish(ok, name, path);
}

fn t19_record_new(dir: Str) -> TestResult {
  let name = "wal_record_new: durable shape with empty payload and ts 0";
  let path = wal_tmp(dir, "t19");
  cleanup(path);
  let rec = wal_record_new(5, WalOpKind.SnapshotMarker, 7, 8);
  var ok = true;
  if rec.lsn != 5 { ok = false; }
  if wal_op_code(rec.op) != 7 { ok = false; }
  if rec.key != 7 { ok = false; }
  if rec.value != 8 { ok = false; }
  if rec.payload.len() != 0 { ok = false; }
  if rec.timestamp != 0 { ok = false; }
  return finish(ok, name, path);
}

fn t20_close_noop(dir: Str) -> TestResult {
  let name = "wal_close is a no-op success and the handle stays usable";
  let path = wal_tmp(dir, "t20");
  cleanup(path);
  var w = wal_open(path);
  var ok = true;
  let l1 = wal_append(&mut w, WalOpKind.Insert, 1, 10);
  if l1 != 1 { ok = false; }
  let closed = wal_close(&mut w);
  if !closed { ok = false; }
  let l2 = wal_append(&mut w, WalOpKind.Insert, 2, 20);
  if l2 != 2 { ok = false; }
  if wal_len(path) != 2 { ok = false; }
  // Reopen after close: LSNs keep advancing.
  var w2 = wal_open(path);
  if w2.next_lsn != 3 { ok = false; }
  return finish(ok, name, path);
}

fn t21_flush_true(dir: Str) -> TestResult {
  let name = "wal_flush reports success (documented no-op until fsync lands)";
  let path = wal_tmp(dir, "t21");
  cleanup(path);
  var w = wal_open(path);
  var ok = true;
  let l1 = wal_append(&mut w, WalOpKind.Insert, 1, 10);
  if l1 != 1 { ok = false; }
  let flushed = wal_flush(&mut w);
  if !flushed { ok = false; }
  if wal_last_lsn(path) != 1 { ok = false; }
  return finish(ok, name, path);
}

fn main() -> Int {
  let dir = fs.fs_temp_dir();
  io.println("=== xiom.wal conformance tests ===");
  var failed: Int = 0;

  let r1 = t1_open_append(dir);
  if r1.passed { io.println("  [PASS] " + r1.name); } else { io.println("  [FAIL] " + r1.name); failed = failed + 1; }
  let r2 = t2_reopen_resume(dir);
  if r2.passed { io.println("  [PASS] " + r2.name); } else { io.println("  [FAIL] " + r2.name); failed = failed + 1; }
  let r3 = t3_replay_identity(dir);
  if r3.passed { io.println("  [PASS] " + r3.name); } else { io.println("  [FAIL] " + r3.name); failed = failed + 1; }
  let r4 = t4_payload_csv_roundtrip(dir);
  if r4.passed { io.println("  [PASS] " + r4.name); } else { io.println("  [FAIL] " + r4.name); failed = failed + 1; }
  let r5 = t5_op_roundtrip(dir);
  if r5.passed { io.println("  [PASS] " + r5.name); } else { io.println("  [FAIL] " + r5.name); failed = failed + 1; }
  let r6 = t6_op_is_write(dir);
  if r6.passed { io.println("  [PASS] " + r6.name); } else { io.println("  [FAIL] " + r6.name); failed = failed + 1; }
  let r7 = t7_malformed_skipped(dir);
  if r7.passed { io.println("  [PASS] " + r7.name); } else { io.println("  [FAIL] " + r7.name); failed = failed + 1; }
  let r8 = t8_torn_tail(dir);
  if r8.passed { io.println("  [PASS] " + r8.name); } else { io.println("  [FAIL] " + r8.name); failed = failed + 1; }
  let r9 = t9_truncate_keep(dir);
  if r9.passed { io.println("  [PASS] " + r9.name); } else { io.println("  [FAIL] " + r9.name); failed = failed + 1; }
  let r10 = t10_truncate_payload(dir);
  if r10.passed { io.println("  [PASS] " + r10.name); } else { io.println("  [FAIL] " + r10.name); failed = failed + 1; }
  let r11 = t11_truncate_reopen(dir);
  if r11.passed { io.println("  [PASS] " + r11.name); } else { io.println("  [FAIL] " + r11.name); failed = failed + 1; }
  let r12 = t12_empty_file(dir);
  if r12.passed { io.println("  [PASS] " + r12.name); } else { io.println("  [FAIL] " + r12.name); failed = failed + 1; }
  let r13 = t13_missing_file(dir);
  if r13.passed { io.println("  [PASS] " + r13.name); } else { io.println("  [FAIL] " + r13.name); failed = failed + 1; }
  let r14 = t14_writer_memory(dir);
  if r14.passed { io.println("  [PASS] " + r14.name); } else { io.println("  [FAIL] " + r14.name); failed = failed + 1; }
  let r15 = t15_read_all_from(dir);
  if r15.passed { io.println("  [PASS] " + r15.name); } else { io.println("  [FAIL] " + r15.name); failed = failed + 1; }
  let r16 = t16_checkpoint(dir);
  if r16.passed { io.println("  [PASS] " + r16.name); } else { io.println("  [FAIL] " + r16.name); failed = failed + 1; }
  let r17 = t17_recovery_scan(dir);
  if r17.passed { io.println("  [PASS] " + r17.name); } else { io.println("  [FAIL] " + r17.name); failed = failed + 1; }
  let r18 = t18_lsn_helpers(dir);
  if r18.passed { io.println("  [PASS] " + r18.name); } else { io.println("  [FAIL] " + r18.name); failed = failed + 1; }
  let r19 = t19_record_new(dir);
  if r19.passed { io.println("  [PASS] " + r19.name); } else { io.println("  [FAIL] " + r19.name); failed = failed + 1; }
  let r20 = t20_close_noop(dir);
  if r20.passed { io.println("  [PASS] " + r20.name); } else { io.println("  [FAIL] " + r20.name); failed = failed + 1; }
  let r21 = t21_flush_true(dir);
  if r21.passed { io.println("  [PASS] " + r21.name); } else { io.println("  [FAIL] " + r21.name); failed = failed + 1; }

  if failed == 0 {
    io.println("xiom.wal: all tests passed");
  } else {
    io.println("xiom.wal: tests failed");
  }
  return failed;
}
