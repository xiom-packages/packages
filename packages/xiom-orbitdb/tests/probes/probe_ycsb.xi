// XIOM ORBITDB -- BENCH-1 cross-engine driver (orbitdb side).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// YCSB-ish phases over the file-backed engine, mirroring bench/bbolt (Go)
// and the generated SQLite phase scripts. Same deterministic op stream,
// same phases, same output lines; run via scripts/bench_cross.{ps1,sh}.
// Numbers are honest for this machine/toolchain pair (regression baselines,
// see docs/BENCH-1.md); timed with xiom.time.monotonic_ms.
//
// Env:
//   ORBITDB_YCSB_FILE    db path (required; caller starts from a fresh file)
//   ORBITDB_YCSB_N       keys (default 50000; keys 0..n-1)
//   ORBITDB_YCSB_VALS    8 | 100 value bytes (default 8)
//   ORBITDB_YCSB_SYNC    1 durable | 0 normal/no-flush (default 1)
//   ORBITDB_YCSB_BATCH   ops per commit group; 1 = per-op (default 1)
//   ORBITDB_YCSB_PHASE   all | load | read | update | scan | delete (all)
//   ORBITDB_YCSB_SEED    LCG seed (default 12345)
//   ORBITDB_YCSB_SCANS   scan count (default n/100; length fixed 100)
//   ORBITDB_YCSB_DELETES delete ops (default n/10)
//
// Output (parsed by scripts/bench_cross.ps1):
//   ycsb orbitdb <phase> n=<ops> ms=<ms> ops_s=<ops*1000/ms>
//   ycsb orbitdb verify count=<count> ok=<0|1>
//   ycsb orbitdb done ok=<0|1> v=8|100 batch=<b> sync=<0|1>
//
// Exit: 0 ok, 1 check failed, 2 bad env/combo.
// Matrix notes (docs/BENCH-1.md): vals=100 (typed rows) is point-ops only
// (load/read/update) and batch must be 1 (typed writes are non-txn in S3);
// vals=8 exercises load/read/update/scan/delete incl. batch groups.

module orbitdb_probe_ycsb

use xiom.io;
use xiom.os.env;
use xiom.convert;
use xiom.convert.parse;
use xiom.time.time;
use xiom.db.engine;
use xiom.db.storage.tuple;
use xiom.db.catalog.schema;
use xiom.db.catalog.schema_row;

// Same stream as every other BENCH-1 engine.
fn ycsb_rand(state: &mut Int) -> Int {
  *state = (*state * 1103515245 + 12345) % 2147483648;
  return *state;
}

fn ycsb_pad8(k: Int) -> Str {
  let s = convert.int_to_string(k);
  var pad = "";
  var need = 8 - s.len();
  var i = 0;
  while i < need {
    pad = pad + "0";
    i = i + 1;
  }
  return pad + s;
}

fn ycsb_x92() -> Str {
  var xs = "";
  var i = 0;
  while i < 92 {
    xs = xs + "x";
    i = i + 1;
  }
  return xs;
}

fn ycsb_report(phase: Str, n: Int, ms: Int) {
  var ops_s = 0;
  if ms > 0 {
    ops_s = (n * 1000) / ms;
  }
  io.println("ycsb orbitdb " + phase + " n=" + convert.int_to_string(n)
    + " ms=" + convert.int_to_string(ms)
    + " ops_s=" + convert.int_to_string(ops_s));
}

fn ycsb_schema() -> Schema {
  var cols = Vec[ColumnDef].new();
  cols.push(ColumnDef.new("id", ColumnType.IntType));
  cols.push(ColumnDef.new("v", ColumnType.StringType));
  return Schema.new("kv", cols, 0);
}

fn main() -> Int {
  let path = env.var_or("ORBITDB_YCSB_FILE", "");
  if path == "" {
    io.println("ycsb orbitdb error: ORBITDB_YCSB_FILE required");
    return 2;
  }

  var n = 50000;
  match parse.parse_int(env.var_or("ORBITDB_YCSB_N", "50000")) {
    Err(_) => { return 2; }
    Ok(v) => { n = v; }
  }
  var valsize = 8;
  match parse.parse_int(env.var_or("ORBITDB_YCSB_VALS", "8")) {
    Err(_) => { return 2; }
    Ok(v) => { valsize = v; }
  }
  var sync = 1;
  match parse.parse_int(env.var_or("ORBITDB_YCSB_SYNC", "1")) {
    Err(_) => { return 2; }
    Ok(v) => { sync = v; }
  }
  var batch = 1;
  match parse.parse_int(env.var_or("ORBITDB_YCSB_BATCH", "1")) {
    Err(_) => { return 2; }
    Ok(v) => { batch = v; }
  }
  let phase = env.var_or("ORBITDB_YCSB_PHASE", "all");
  var seed = 12345;
  match parse.parse_int(env.var_or("ORBITDB_YCSB_SEED", "12345")) {
    Err(_) => { return 2; }
    Ok(v) => { seed = v; }
  }
  var scans = n / 100;
  match parse.parse_int(env.var_or("ORBITDB_YCSB_SCANS", "0")) {
    Err(_) => { return 2; }
    Ok(v) => { if v > 0 { scans = v; } }
  }
  var deletes = n / 10;
  match parse.parse_int(env.var_or("ORBITDB_YCSB_DELETES", "0")) {
    Err(_) => { return 2; }
    Ok(v) => { if v > 0 { deletes = v; } }
  }

  if valsize != 8 && valsize != 100 {
    io.println("ycsb orbitdb error: vals must be 8 or 100");
    return 2;
  }
  if batch < 1 {
    io.println("ycsb orbitdb error: batch must be >= 1");
    return 2;
  }
  if valsize == 100 && batch > 1 {
    io.println("ycsb orbitdb error: vals=100 requires batch=1 (typed writes are non-txn)");
    return 2;
  }
  if batch > 1 && batch > n {
    batch = n;
  }

  var db = db_file_open(path, 4);
  if sync == 0 {
    if !db_file_set_durability(&mut db, 0) { return 1; }
  }

  let do_all = phase == "all";
  let xs = ycsb_x92();
  let schema = ycsb_schema();

  // ---- load: sequential keys 0..n-1, batch groups ----
  if do_all || phase == "load" {
    let t0 = time.monotonic_ms();
    var i = 0;
    var failed = false;
    while i < n && !failed {
      if batch > 1 {
        if !db_file_txn_begin(&mut db) { failed = true; }
      }
      var j = 0;
      while j < batch && i < n && !failed {
        var ok = false;
        if valsize == 8 {
          if batch > 1 {
            ok = db_file_txn_put(&mut db, i, i * 7 + 1);
          } else {
            ok = db_file_put(&mut db, i, i * 7 + 1);
          }
        } else {
          let s = ycsb_pad8(i) + xs;
          var vals = Vec[TValue].new();
          vals.push(TValue.VInt(i));
          vals.push(TValue.VText(s));
          match schema_row_encode(&schema, vals) {
            Err(_) => { failed = true; }
            Ok(payload) => { ok = db_file_put_typed(&mut db, i, payload); }
          }
        }
        if !ok { failed = true; }
        i = i + 1;
        j = j + 1;
      }
      if batch > 1 {
        if !failed {
          if !db_file_txn_commit(&mut db) { failed = true; }
        } else {
          let _ = db_file_txn_abort(&mut db);
        }
      }
    }
    let t1 = time.monotonic_ms();
    if failed {
      io.println("ycsb orbitdb error: load failed");
      return 1;
    }
    ycsb_report("load", n, t1 - t0);
  }

  // ---- read: n point reads, fresh stream ----
  if do_all || phase == "read" {
    var state = seed;
    var hits = 0;
    var sink = 0;
    let t0 = time.monotonic_ms();
    var i = 0;
    while i < n {
      let key = ycsb_rand(&mut state) % n;
      if valsize == 8 {
        match db_file_get(&db, key) {
          None => {}
          Some(v) => { hits = hits + 1; sink = sink + v; }
        }
      } else {
        match db_file_get_typed(&db, key) {
          None => {}
          Some(p) => {
            hits = hits + 1;
            if p.len() > 0 { sink = sink + p[0]; }
          }
        }
      }
      i = i + 1;
    }
    let t1 = time.monotonic_ms();
    if hits == 0 && n > 0 {
      io.println("ycsb orbitdb error: read phase found nothing");
      return 1;
    }
    let _ = sink;
    ycsb_report("read", n, t1 - t0);
  }

  // ---- update: same values (idempotent), fresh stream, batch groups ----
  if do_all || phase == "update" {
    var state = seed;
    let t0 = time.monotonic_ms();
    var failed = false;
    var done = 0;
    while done < n && !failed {
      if batch > 1 {
        if !db_file_txn_begin(&mut db) { failed = true; }
      }
      var j = 0;
      while j < batch && done < n && !failed {
        let key = ycsb_rand(&mut state) % n;
        var ok = false;
        if valsize == 8 {
          if batch > 1 {
            ok = db_file_txn_put(&mut db, key, key * 7 + 1);
          } else {
            ok = db_file_put(&mut db, key, key * 7 + 1);
          }
        } else {
          let s = ycsb_pad8(key) + xs;
          var vals = Vec[TValue].new();
          vals.push(TValue.VInt(key));
          vals.push(TValue.VText(s));
          match schema_row_encode(&schema, vals) {
            Err(_) => { failed = true; }
            Ok(payload) => { ok = db_file_put_typed(&mut db, key, payload); }
          }
        }
        if !ok { failed = true; }
        done = done + 1;
        j = j + 1;
      }
      if batch > 1 {
        if !failed {
          if !db_file_txn_commit(&mut db) { failed = true; }
        } else {
          let _ = db_file_txn_abort(&mut db);
        }
      }
    }
    let t1 = time.monotonic_ms();
    if failed {
      io.println("ycsb orbitdb error: update failed");
      return 1;
    }
    ycsb_report("update", n, t1 - t0);
  }

  // ---- scan: scans x 100 consecutive keys (vals=8 only) ----
  if (do_all || phase == "scan") && valsize == 8 {
    var state = seed;
    var sink = 0;
    let t0 = time.monotonic_ms();
    var s = 0;
    while s < scans {
      let start = ycsb_rand(&mut state) % (n - 100);
      let vals = db_file_range(&db, start, start + 99);
      var k = 0;
      while k < vals.len() {
        sink = sink + vals[k];
        k = k + 1;
      }
      s = s + 1;
    }
    let t1 = time.monotonic_ms();
    let _ = sink;
    ycsb_report("scan", scans, t1 - t0);
  }

  // ---- delete: distinct via bitmap, fresh stream (vals=8 only) ----
  var deleted_distinct = 0;
  var ran_deletes = false;
  if (do_all || phase == "delete") && valsize == 8 {
    ran_deletes = true;
    var marked = Vec[Int].new();
    var i = 0;
    while i < n {
      marked.push(0);
      i = i + 1;
    }
    var state = seed;
    let t0 = time.monotonic_ms();
    var failed = false;
    var done = 0;
    while done < deletes && !failed {
      if batch > 1 {
        if !db_file_txn_begin(&mut db) { failed = true; }
      }
      var j = 0;
      while j < batch && done < deletes && !failed {
        let key = ycsb_rand(&mut state) % n;
        var is_new = false;
        if marked[key] == 0 {
          marked[key] = 1;
          deleted_distinct = deleted_distinct + 1;
          is_new = true;
        }
        var ok = false;
        if batch > 1 {
          ok = db_file_txn_delete(&mut db, key);
        } else {
          ok = db_file_delete(&mut db, key);
        }
        // A repeated key (duplicate in the stream) is a tolerated no-op:
        // the delete returns false, the distinct count already recorded it.
        if is_new && !ok { failed = true; }
        done = done + 1;
        j = j + 1;
      }
      if batch > 1 {
        if !failed {
          if !db_file_txn_commit(&mut db) { failed = true; }
        } else {
          let _ = db_file_txn_abort(&mut db);
        }
      }
    }
    let t1 = time.monotonic_ms();
    if failed {
      io.println("ycsb orbitdb error: delete failed");
      return 1;
    }
    ycsb_report("delete", deletes, t1 - t0);
  }

  // ---- verify ----
  var want = n;
  if ran_deletes {
    want = n - deleted_distinct;
  }
  let count = db_file_size(&db);
  var ok = 0;
  if count == want {
    ok = 1;
  }
  io.println("ycsb orbitdb verify count=" + convert.int_to_string(count)
    + " ok=" + convert.int_to_string(ok));
  io.println("ycsb orbitdb done ok=" + convert.int_to_string(ok)
    + " v=" + convert.int_to_string(valsize)
    + " batch=" + convert.int_to_string(batch)
    + " sync=" + convert.int_to_string(sync));
  if ok != 1 {
    return 1;
  }
  return 0;
}
