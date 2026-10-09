// XIOM -- xiom.wal crash/reopen probe (acceptance harness for wal_open /
// wal_append / wal_replay / wal_truncate).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Adapted from ORBITDB tests/probes/probe_wal_file.xi (commit 12405f5) for
// the xiom.wal package surface; no engine/btree dependency (pure XIOM +
// stdlib), the data-tree rebuild is replaced by per-record invariants.
//
// Env:
//   XIOM_WAL_FILE       path to the segment file (required)
//   XIOM_WAL_MODE       write | verify | append1 | truncate (default: verify)
//   XIOM_WAL_N          record count for write / verify (default: 20)
//   XIOM_WAL_FROM       keep lsn >= FROM (truncate) / first lsn (verify, >0)
//   XIOM_WAL_EXPECT     expected replayed count after truncate
//   XIOM_WAL_LAST_KEY   optional: key to assert after replay
//   XIOM_WAL_LAST_VAL   optional: expected value for LAST_KEY
//   XIOM_WAL_SKIP_KEY1  1 = skip the key-1 == 10 invariant (truncate tests)
//
// Exit: 0 = mode succeeded, 1 = check failed, 2 = bad env/read error.

module probe_wal_crash

use xiom.io;
use xiom.os.env;
use xiom.convert;
use xiom.convert.parse;
use xiom.wal;

fn env_int(name: Str, fallback: Int) -> Int {
  match parse.parse_int(env.var_or(name, "")) {
    Ok(v) => { return v; }
    Err(_) => { return fallback; }
  }
}

fn run_write(path: Str, n: Int) -> Int {
  var w = wal_open(path);
  var i = 1;
  while i <= n {
    let lsn = wal_append(&mut w, WalOpKind.Insert, i, i * 10);
    if lsn < 0 { io.println("writer: append failed"); return 1; }
    i = i + 1;
  }
  let flushed = wal_flush(&mut w);
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
  let records = wal_replay(path);
  io.println("verify: applied=" + convert.int_to_string(records.len()));
  if records.len() != n {
    io.println("verify: expected " + convert.int_to_string(n) + " got " + convert.int_to_string(records.len()));
    return 1;
  }
  var ok = true;
  // Strictly increasing LSNs, and key i -> value i*10 for the crash writer's
  // records (the harness's special append1 key 9999 is exempt).
  var prev = 0;
  var i = 0;
  while i < records.len() {
    let row = records[i];
    if row.lsn <= prev { ok = false; }
    prev = row.lsn;
    if row.key != 9999 {
      if row.value != row.key * 10 { ok = false; }
    }
    i = i + 1;
  }
  // Key 1 == 10 invariant (writer records), skipped for truncate verifies.
  if env.var_or("XIOM_WAL_SKIP_KEY1", "0") != "1" {
    var found1 = false;
    var v1 = 0;
    i = 0;
    while i < records.len() {
      let row = records[i];
      if row.key == 1 { found1 = true; v1 = row.value; }
      i = i + 1;
    }
    if !found1 { io.println("verify: key 1 missing"); return 1; }
    if v1 != 10 { io.println("verify: key 1 wrong"); return 1; }
  }
  // Optional first-LSN check (used after truncate: first kept record).
  let first = env_int("XIOM_WAL_FROM", 0);
  if first > 0 {
    if records.len() == 0 { ok = false; }
    else {
      if records[0].lsn != first { ok = false; }
    }
  }
  // Optional last-record assertion (last write to LAST_KEY wins).
  let lk = env.var_or("XIOM_WAL_LAST_KEY", "");
  if lk != "" {
    let k = env_int("XIOM_WAL_LAST_KEY", 0);
    let want = env_int("XIOM_WAL_LAST_VAL", 0);
    var found = false;
    var got = 0;
    i = 0;
    while i < records.len() {
      let row = records[i];
      if row.key == k { found = true; got = row.value; }
      i = i + 1;
    }
    if !found { io.println("verify: last key missing"); return 1; }
    if got != want { io.println("verify: last value wrong"); return 1; }
  }
  if !ok {
    io.println("verify: invariants failed");
    return 1;
  }
  io.println("verify: OK n=" + convert.int_to_string(n));
  return 0;
}

fn run_append1(path: Str) -> Int {
  var w = wal_open(path);
  let lsn = wal_append(&mut w, WalOpKind.Insert, 9999, 99990);
  if lsn < 0 { io.println("append1: failed"); return 1; }
  io.println("append1: OK lsn=" + convert.int_to_string(lsn));
  return 0;
}

fn run_truncate(path: Str) -> Int {
  let from = env_int("XIOM_WAL_FROM", 0);
  let expect = env_int("XIOM_WAL_EXPECT", -1);
  if expect < 0 { io.println("truncate: XIOM_WAL_EXPECT not set"); return 2; }
  let ok = wal_truncate(path, from);
  if !ok { io.println("truncate: failed"); return 1; }
  let records = wal_replay(path);
  io.println("truncate: OK from=" + convert.int_to_string(from)
           + " kept=" + convert.int_to_string(records.len()));
  if records.len() != expect {
    io.println("truncate: expected " + convert.int_to_string(expect)
             + " got " + convert.int_to_string(records.len()));
    return 1;
  }
  if records.len() > 0 {
    if records[0].lsn < from {
      io.println("truncate: kept a record below from_lsn");
      return 1;
    }
  }
  return 0;
}

pub fn main() -> Int {
  let path = env.var_or("XIOM_WAL_FILE", "");
  if path == "" {
    io.println("probe_wal_crash: XIOM_WAL_FILE not set");
    return 2;
  }
  let mode = env.var_or("XIOM_WAL_MODE", "verify");
  let n = env_int("XIOM_WAL_N", 20);

  if mode == "write" {
    return run_write(path, n);
  }
  if mode == "append1" {
    return run_append1(path);
  }
  if mode == "truncate" {
    return run_truncate(path);
  }
  return run_verify(path, n);
}
