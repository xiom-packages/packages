// XIOM ORBITDB -- durable WAL segment probe (critical primitive).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Acceptance harness for `src/wal_file.xi` (the xiom.wal reference shape),
// driven by scripts/crash_test.ps1/.sh: the writer appends N records, the
// harness hard-kills it, leaves a torn tail, then reopens and replays.
//
// Env:
//   ORBITDB_WAL_FILE      path to the segment file (required)
//   ORBITDB_WAL_MODE      write | verify | append1 | truncate   (default: verify)
//   ORBITDB_WAL_N         record count for write / verify (default: 20)
//   ORBITDB_WAL_FROM      lsn for truncate mode (keep lsn >= FROM)
//   ORBITDB_WAL_LAST_KEY  optional: key to assert after replay
//   ORBITDB_WAL_LAST_VAL  optional: expected value for LAST_KEY
//   ORBITDB_WAL_SKIP_KEY1 1 = skip the key-1 == 10 invariant (truncate tests)
//
// Exit: 0 = mode succeeded, 1 = check failed, 2 = bad env/read error.

module orbitdb_probe_wal_file

use xiom.io;
use xiom.os.env;
use xiom.convert;
use xiom.convert.parse;
use xiom.db.engine;
use xiom.db.wal_file;

fn run_write(path: Str, n: Int) -> Int {
  var w = wal_file_open(path);
  var i = 1;
  while i <= n {
    let lsn = wal_file_append(&mut w, WALOpKind.Insert, i, i * 10);
    if lsn < 0 { io.println("writer: append failed"); return 1; }
    i = i + 1;
  }
  let flushed = wal_file_flush(&mut w);
  if !flushed { io.println("writer: flush failed"); return 1; }
  io.println("writer: wrote " + convert.int_to_string(n));
  // Hang until the harness hard-kills us (crash simulation). io.sleep is a
  // runtime call, so the loop cannot be optimized away.
  var alive = true;
  while alive {
    io.sleep(1000);
  }
  return 0;
}

fn run_verify(path: Str, n: Int) -> Int {
  let records = wal_file_replay(path);
  io.println("verify: applied=" + convert.int_to_string(records.len()));
  if records.len() != n {
    io.println("verify: expected " + convert.int_to_string(n) + " got " + convert.int_to_string(records.len()));
    return 1;
  }
  // Rebuild the data tree from the log (first value for each key wins on
  // inserts; this probe only writes inserts).
  var tree = btree_new(4);
  var i = 0;
  while i < records.len() {
    let rec = records[i];
    if wal_op_is_write(rec.op) {
      btree_insert(&mut tree, rec.key, rec.value);
    }
    i = i + 1;
  }
  let v1 = btree_search(&tree, 1);
  if env.var_or("ORBITDB_WAL_SKIP_KEY1", "0") != "1" {
    match v1 {
      None => { io.println("verify: key 1 missing"); return 1; }
      Some(x) => { if x != 10 { io.println("verify: key 1 wrong"); return 1; } }
    }
  }
  // Optional last-record assertion.
  let lk = env.var_or("ORBITDB_WAL_LAST_KEY", "");
  if lk != "" {
    match parse.parse_int(lk) {
      Ok(k) => {
        match parse.parse_int(env.var_or("ORBITDB_WAL_LAST_VAL", "0")) {
          Ok(want) => {
            let got = btree_search(&tree, k);
            match got {
              None => { io.println("verify: last key missing"); return 1; }
              Some(v) => {
                if v != want { io.println("verify: last value wrong"); return 1; }
              }
            }
          }
          Err(_) => { return 2; }
        }
      }
      Err(_) => { return 2; }
    }
  }
  io.println("verify: OK n=" + convert.int_to_string(n));
  return 0;
}

fn main() -> Int {
  let path = env.var_or("ORBITDB_WAL_FILE", "");
  if path == "" {
    io.println("probe_wal_file: ORBITDB_WAL_FILE not set");
    return 2;
  }
  let mode = env.var_or("ORBITDB_WAL_MODE", "verify");
  var n = 20;
  match parse.parse_int(env.var_or("ORBITDB_WAL_N", "20")) {
    Ok(v) => { n = v; }
    Err(_) => { n = 20; }
  }

  if mode == "write" {
    return run_write(path, n);
  }
  if mode == "append1" {
    var w = wal_file_open(path);
    let lsn = wal_file_append(&mut w, WALOpKind.Insert, 9999, 99990);
    if lsn < 0 { io.println("append1: failed"); return 1; }
    io.println("append1: OK");
    return 0;
  }
  if mode == "truncate" {
    var from = 0;
    match parse.parse_int(env.var_or("ORBITDB_WAL_FROM", "0")) {
      Ok(v) => { from = v; }
      Err(_) => { return 2; }
    }
    let ok = wal_file_truncate(path, from);
    if !ok { io.println("truncate: failed"); return 1; }
    io.println("truncate: OK from=" + convert.int_to_string(from));
    return 0;
  }
  return run_verify(path, n);
}
