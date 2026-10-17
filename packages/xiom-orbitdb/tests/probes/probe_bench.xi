// XIOM ORBITDB -- mixed benchmark probe (baseline numbers per release).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Wall-clock baseline for the core paths, run by scripts/bench.{ps1,sh}.
// Numbers are honest for this machine/compiler pair and are recorded in
// docs/PRODUCTION-READINESS.md (G1); they are regression baselines, not
// marketing claims. Timed with xiom.time.monotonic_ms.
//
// Env:
//   ORBITDB_BENCH_N      operations per case   (default 20000)
//   ORBITDB_BENCH_ORDER  btree order           (default 4)
//   ORBITDB_BENCH_WAL    WAL segment path      (default orbitdb-bench.wal)
//
// Exit: 0 = all cases ran; 1 = a case failed.

module orbitdb_probe_bench

use xiom.io;
use xiom.os.env;
use xiom.convert;
use xiom.convert.parse;
use xiom.time.time;
use xiom.string;
use xiom.string.split;
use xiom.db.engine;
use xiom.db.wal_file;
use xiom.db.storage.tuple;

fn rand_next(state: &mut Int) -> Int {
  *state = (*state * 1103515245 + 12345) % 2147483648;
  return *state;
}

fn report(case: Str, n: Int, ms: Int) {
  var per_sec = 0;
  if ms > 0 {
    per_sec = (n * 1000) / ms;
  }
  io.println("bench " + case + " n=" + convert.int_to_string(n)
    + " ms=" + convert.int_to_string(ms)
    + " ops_s=" + convert.int_to_string(per_sec));
}

fn bench_btree_insert(n: Int, order: Int) -> Int {
  var tree = btree_new(order);
  var state = 12345;
  var inserted = 0;
  let t0 = time.monotonic_ms();
  var i = 0;
  while i < n {
    let key = rand_next(&mut state) % (n * 4);
    if btree_insert(&mut tree, key, key * 7 + 1) {
      inserted = inserted + 1;
    }
    i = i + 1;
  }
  let t1 = time.monotonic_ms();
  report("btree_insert", n, t1 - t0);
  if btree_size(&tree) != inserted { return 1; }
  return 0;
}

fn bench_btree_search(n: Int, order: Int) -> Int {
  var tree = btree_new(order);
  var i = 0;
  while i < n {
    btree_insert(&mut tree, i, i * 7 + 1);
    i = i + 1;
  }
  var hits = 0;
  let t0 = time.monotonic_ms();
  i = 0;
  while i < n {
    match btree_search(&tree, i) {
      Some(_) => { hits = hits + 1; }
      None => {}
    }
    i = i + 1;
  }
  let t1 = time.monotonic_ms();
  report("btree_search", n, t1 - t0);
  if hits != n { return 1; }
  return 0;
}

fn bench_btree_delete(n: Int, order: Int) -> Int {
  var tree = btree_new(order);
  var i = 0;
  while i < n {
    btree_insert(&mut tree, i, i);
    i = i + 1;
  }
  let target = n / 2;
  let t0 = time.monotonic_ms();
  i = 0;
  while i < target {
    let ok = btree_delete(&mut tree, i);
    if !ok { return 1; }
    i = i + 1;
  }
  let t1 = time.monotonic_ms();
  report("btree_delete", target, t1 - t0);
  if btree_size(&tree) != n - target { return 1; }
  return 0;
}

fn bench_btree_range(n: Int, order: Int) -> Int {
  var tree = btree_new(order);
  var i = 0;
  while i < n {
    btree_insert(&mut tree, i, i);
    i = i + 1;
  }
  let queries = 100;
  var total = 0;
  let t0 = time.monotonic_ms();
  i = 0;
  while i < queries {
    let low = i * 10;
    let results = btree_range_query(&tree, low, low + 99);
    total = total + results.len();
    i = i + 1;
  }
  let t1 = time.monotonic_ms();
  report("btree_range", queries, t1 - t0);
  if total != queries * 100 { return 1; }
  return 0;
}

fn bench_tuple_roundtrip(n: Int) -> Int {
  var data = Vec[Int].new();
  var c = 0;
  while c < 8 {
    data.push(c * 1000 - 5);
    c = c + 1;
  }
  let row = Row.new(42, data);
  var ok_count = 0;
  let t0 = time.monotonic_ms();
  var i = 0;
  while i < n {
    let enc = tuple_encode_checked(&row);
    match enc {
      Err(_) => {}
      Ok(buf) => {
        let bytes: Vec[Int] = buf;
        let dec = tuple_decode(&bytes);
        match dec {
          Err(_) => {}
          Ok(decoded) => {
            let d: Row = decoded;
            if d.id == 42 { ok_count = ok_count + 1; }
          }
        }
      }
    }
    i = i + 1;
  }
  let t1 = time.monotonic_ms();
  report("tuple_roundtrip", n, t1 - t0);
  if ok_count != n { return 1; }
  return 0;
}

fn bench_wal(n: Int, path: Str) -> Int {
  let _ = io.remove_file(path);
  var w = wal_file_open(path);
  let t0 = time.monotonic_ms();
  var i = 0;
  while i < n {
    let lsn = wal_file_append(&mut w, WALOpKind.Insert, i, i * 3);
    if lsn < 0 { return 1; }
    i = i + 1;
  }
  let t1 = time.monotonic_ms();
  report("wal_append", n, t1 - t0);

  let t2 = time.monotonic_ms();
  let records = wal_file_replay(path);
  let t3 = time.monotonic_ms();
  report("wal_replay", n, t3 - t2);
  if records.len() != n { return 1; }
  let _ = io.remove_file(path);
  return 0;
}

fn bench_wal_readlines(path: Str, n: Int) -> Int {
  let _ = io.remove_file(path);
  var w = wal_file_open(path);
  var i = 0;
  while i < n {
    let lsn = wal_file_append(&mut w, WALOpKind.Insert, i, i * 3);
    if lsn < 0 { return 1; }
    i = i + 1;
  }
  let t0 = time.monotonic_ms();
  let lines_r = io.read_file_lines(path);
  let t1 = time.monotonic_ms();
  var count = 0;
  match lines_r {
    Err(_) => { return 1; }
    Ok(lines) => {
      // C-ORBIT-01 workaround: annotated rebind before element access.
      let all: Vec[Str] = lines;
      count = all.len();
    }
  }
  report("wal_readlines", n, t1 - t0);
  let _ = io.remove_file(path);
  if count < n { return 1; }
  return 0;
}

// Compare read paths on the same segment: read_file + str_split vs
// read_file_lines (the latter measured quadratic on v0.64.1 -- stdlib row).
fn bench_wal_readsplit(path: Str, n: Int) -> Int {
  let _ = io.remove_file(path);
  var w = wal_file_open(path);
  var i = 0;
  while i < n {
    let lsn = wal_file_append(&mut w, WALOpKind.Insert, i, i * 3);
    if lsn < 0 { return 1; }
    i = i + 1;
  }
  let t0 = time.monotonic_ms();
  let content_r = io.read_file(path);
  var count = 0;
  match content_r {
    Err(_) => { return 1; }
    Ok(content) => {
      let parts = split.str_split(content, "\n");
      count = parts.len();
    }
  }
  let t1 = time.monotonic_ms();
  report("wal_readsplit", n, t1 - t0);
  let _ = io.remove_file(path);
  if count < n { return 1; }
  return 0;
}

fn bench_wal_readfile(path: Str, n: Int) -> Int {
  let _ = io.remove_file(path);
  var w = wal_file_open(path);
  var i = 0;
  while i < n {
    let lsn = wal_file_append(&mut w, WALOpKind.Insert, i, i * 3);
    if lsn < 0 { return 1; }
    i = i + 1;
  }
  let t0 = time.monotonic_ms();
  let content_r = io.read_file(path);
  let t1 = time.monotonic_ms();
  var size = 0;
  match content_r {
    Err(_) => { return 1; }
    Ok(content) => { size = str_len(content); }
  }
  report("wal_readfile", n, t1 - t0);
  let _ = io.remove_file(path);
  if size <= 0 { return 1; }
  return 0;
}

fn main() -> Int {
  var n = 20000;
  var order = 4;
  match parse.parse_int(env.var_or("ORBITDB_BENCH_N", "20000")) {
    Ok(v) => { if v > 0 { n = v; } }
    Err(_) => {}
  }
  match parse.parse_int(env.var_or("ORBITDB_BENCH_ORDER", "4")) {
    Ok(v) => { if v >= 3 { order = v; } }
    Err(_) => {}
  }
  let wal_path = env.var_or("ORBITDB_BENCH_WAL", "orbitdb-bench.wal");
  let case = env.var_or("ORBITDB_BENCH_CASE", "all");

  if case == "wal_readlines" {
    return bench_wal_readlines(wal_path, n);
  }
  if case == "wal_readsplit" {
    return bench_wal_readsplit(wal_path, n);
  }
  if case == "wal_readfile" {
    return bench_wal_readfile(wal_path, n);
  }
  if case == "wal_only" {
    return bench_wal(n, wal_path);
  }

  if bench_btree_insert(n, order) != 0 { io.println("bench: btree_insert failed"); return 1; }
  if bench_btree_search(n, order) != 0 { io.println("bench: btree_search failed"); return 1; }
  if bench_btree_delete(n, order) != 0 { io.println("bench: btree_delete failed"); return 1; }
  if bench_btree_range(n, order) != 0 { io.println("bench: btree_range failed"); return 1; }
  if bench_tuple_roundtrip(n) != 0 { io.println("bench: tuple_roundtrip failed"); return 1; }
  if bench_wal(n, wal_path) != 0 { io.println("bench: wal failed"); return 1; }

  io.println("bench: OK n=" + convert.int_to_string(n));
  return 0;
}
