// ORBITDB interactive shell -- the user-test vehicle for the embedded engine.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Build:  scripts\build.ps1 apps\orbitdb_cli.xi -Out out\orbitdb.exe
// Run:    out\orbitdb.exe [db-path]     (default: orbitdb-data.wal)
//
// v0 covers the int-keyed engine that exists today: put/get/del/range,
// checkpoints, reopen/recovery, a timed bench, and `kill` -- which exits
// WITHOUT cleanup so the user can restart and watch WAL replay recover the
// acknowledged rows. Typed-row commands land with M5.3 (see
// docs/TYPED-VALUES-STORAGE.md).
//
// All helper names are cli_*: a consumer-defined helper must never share a
// name with a private helper of an imported module (C-ORBIT-07).

module orbitdb_cli

use xiom.io;
use xiom.os.env;
use xiom.convert;
use xiom.convert.parse;
use xiom.string.split;
use xiom.string.trim;
use xiom.time.time;
use xiom.db.engine;
use xiom.db.storage.tuple;

fn cli_i2s(n: Int) -> Str {
  return convert.int_to_string(n);
}

fn cli_usage() {
  io.println("commands:");
  io.println("  put <k> <v>     insert/update (int key -> int value)");
  io.println("  get <k>         read one key");
  io.println("  del <k>         delete one key");
  io.println("  range <lo> <hi> values for keys in [lo, hi], key order");
  io.println("  count           live row count");
  io.println("  ckpt            checkpoint (snapshot publish + WAL truncate)");
  io.println("  bench <n>       n puts (keys 1..n), timed");
  io.println("  putrow <k> <spec>  typed row (M5.3): spec = comma list of");
  io.println("                  int | s:text | f:float | n  (no commas in text)");
  io.println("  getrow <k>      decode + print a typed row (none if int row)");
  io.println("  qrow <col> <op> <literal>  typed query: match rows where");
  io.println("                  column <col> (row id: -1) <op> <literal>");
  io.println("  info            handle + file state");
  io.println("  recover         close + reopen (snapshot load / WAL replay)");
  io.println("  kill            exit WITHOUT cleanup -- restart to watch recovery");
  io.println("  help            this text");
  io.println("  quit            exit (empty line / EOF also exits)");
}

fn cli_show_info(db: &DBFile) {
  io.println("path      : " + db.path);
  io.println("order     : " + cli_i2s(db.order));
  io.println("page_fmt  : " + cli_i2s(db.page_format));
  io.println("rows      : " + cli_i2s(db_file_size(db)));
  io.println("last_lsn  : " + cli_i2s(db_file_last_lsn(db)));
  io.println("since_ckpt: " + cli_i2s(db.records_since_ckpt));
  io.println("durability: " + cli_i2s(db.durability) + " (0 normal / 1 immediate)");
  if db.two_phase { io.println("two_phase : true"); } else { io.println("two_phase : false"); }
  if db.failed { io.println("failed    : true (writers refuse until reopen)"); }
}

fn cli_tokens(line: Str) -> Vec[Str] {
  var out = Vec[Str].new();
  let parts = split.str_split(line, " ");
  var i = 0;
  while i < parts.len() {
    let t = trim.str_trim(parts[i]);
    if t.len() > 0 { out.push(t); }
    i = i + 1;
  }
  return out;
}

fn cli_arg_int(toks: &Vec[Str], at: Int) -> Result[Int, Str] {
  if at >= toks.len() { return Err("missing argument"); }
  return parse.parse_int(toks[at]);
}

fn cli_run_put(db: &mut DBFile, toks: &Vec[Str]) -> Bool {
  match cli_arg_int(toks, 1) {
    Err(_) => { io.println("usage: put <k> <v>"); return true; }
    Ok(k) => {
      match cli_arg_int(toks, 2) {
        Err(_) => { io.println("usage: put <k> <v>"); return true; }
        Ok(v) => {
          if db_file_put(db, k, v) {
            io.println("ok (lsn " + cli_i2s(db_file_last_lsn(db)) + ")");
          } else {
            io.println("put failed");
          }
        }
      }
    }
  }
  return true;
}

fn cli_run_get(db: &DBFile, toks: &Vec[Str]) -> Bool {
  match cli_arg_int(toks, 1) {
    Err(_) => { io.println("usage: get <k>"); return true; }
    Ok(k) => {
      match db_file_get(db, k) {
        None => { io.println("(none)"); }
        Some(v) => { io.println(cli_i2s(v)); }
      }
    }
  }
  return true;
}

fn cli_run_del(db: &mut DBFile, toks: &Vec[Str]) -> Bool {
  match cli_arg_int(toks, 1) {
    Err(_) => { io.println("usage: del <k>"); return true; }
    Ok(k) => {
      if db_file_delete(db, k) { io.println("ok"); } else { io.println("(no such key)"); }
    }
  }
  return true;
}

fn cli_run_range(db: &DBFile, toks: &Vec[Str]) -> Bool {
  match cli_arg_int(toks, 1) {
    Err(_) => { io.println("usage: range <lo> <hi>"); return true; }
    Ok(lo) => {
      match cli_arg_int(toks, 2) {
        Err(_) => { io.println("usage: range <lo> <hi>"); return true; }
        Ok(hi) => {
          if lo > hi { io.println("lo > hi"); return true; }
          let vals = db_file_range(db, lo, hi);
          io.print("count=" + cli_i2s(vals.len()) + " values=");
          var i = 0;
          while i < vals.len() && i < 16 {
            if i > 0 { io.print(","); }
            io.print(cli_i2s(vals[i]));
            i = i + 1;
          }
          if vals.len() > 16 { io.print(",..."); }
          io.println("");
        }
      }
    }
  }
  return true;
}

fn cli_run_ckpt(db: &mut DBFile) -> Bool {
  let anchor = db_file_checkpoint(db);
  if anchor >= 0 {
    io.println("checkpoint ok (anchor lsn " + cli_i2s(anchor) + ", rows " + cli_i2s(db_file_size(db)) + ")");
  } else {
    io.println("checkpoint failed (-1)");
  }
  return true;
}

fn cli_run_bench(db: &mut DBFile, toks: &Vec[Str]) -> Bool {
  match cli_arg_int(toks, 1) {
    Err(_) => { io.println("usage: bench <n>"); return true; }
    Ok(n) => {
      if n < 1 || n > 1000000 { io.println("n must be 1..1000000"); return true; }
      let t0 = time.monotonic_ms();
      var ok = true;
      var i = 1;
      while i <= n {
        if db_file_put(db, i, i * 7 + 1) {
          i = i + 1;
        } else {
          ok = false;
          i = n + 1;
        }
      }
      let dt = time.monotonic_ms() - t0;
      if !ok {
        io.println("bench aborted (put failure)");
        return true;
      }
      io.println("bench: " + cli_i2s(n) + " puts in " + cli_i2s(dt) + " ms");
      if dt > 0 {
        io.println("       ~" + cli_i2s((n * 1000) / dt) + " ops/s");
      }
    }
  }
  return true;
}

// Parse a row spec into typed values: elements separated by ","; each is
// `int`, `s:<text>` (no commas), `f:<float>`, or `n` (null).
fn cli_build_values(spec: Str) -> Result[Vec[TValue], Str] {
  var vals = Vec[TValue].new();
  if spec.len() == 0 { return Ok(vals); }
  let parts = split.str_split(spec, ",");
  var i = 0;
  while i < parts.len() {
    let t = trim.str_trim(parts[i]);
    if t.len() >= 2 && t.substr(0, 2) == "s:" {
      vals.push(TValue.VText(t.substr(2, t.len())));
    } elif t == "n" {
      vals.push(TValue.VNull);
    } elif t.len() >= 2 && t.substr(0, 2) == "f:" {
      match parse.parse_float(t.substr(2, t.len())) {
        Err(_) => { return Err("bad float: " + t); }
        Ok(f) => { vals.push(TValue.VFloat(f)); }
      }
    } elif t.len() >= 2 && t.substr(0, 2) == "i:" {
      match parse.parse_int(t.substr(2, t.len())) {
        Err(_) => { return Err("bad int: " + t); }
        Ok(x) => { vals.push(TValue.VInt(x)); }
      }
    } else {
      match parse.parse_int(t) {
        Err(_) => { return Err("bad element (use int | s:text | f:float | n): " + t); }
        Ok(x) => { vals.push(TValue.VInt(x)); }
      }
    }
    i = i + 1;
  }
  return Ok(vals);
}

fn cli_encode_row(k: Int, spec: Str) -> Result[Vec[Int], Str] {
  match cli_build_values(spec) {
    Err(e) => { return Err(e); }
    Ok(vals) => {
      match tuple2_encode_row_checked(k, &vals) {
        Err(_) => { return Err("row encode failed (too many columns?)"); }
        Ok(buf) => { return Ok(buf); }
      }
    }
  }
}

fn cli_run_putrow(db: &mut DBFile, toks: &Vec[Str]) -> Bool {
  match cli_arg_int(toks, 1) {
    Err(_) => { io.println("usage: putrow <k> <spec>"); return true; }
    Ok(k) => {
      var spec = "";
      if toks.len() >= 3 { spec = toks[2]; }
      match cli_encode_row(k, spec) {
        Err(e) => { io.println("row error: " + e); }
        Ok(buf) => {
          if db_file_put_typed(db, k, buf) {
            io.println("ok (typed row, " + cli_i2s(buf.len()) + " bytes, lsn "
              + cli_i2s(db_file_last_lsn(db)) + ")");
          } else {
            io.println("typed put failed (budget/guards?)");
          }
        }
      }
    }
  }
  return true;
}

fn cli_run_getrow(db: &DBFile, toks: &Vec[Str]) -> Bool {
  match cli_arg_int(toks, 1) {
    Err(_) => { io.println("usage: getrow <k>"); return true; }
    Ok(k) => {
      match db_file_get_typed(db, k) {
        None => { io.println("(none: absent, or a plain int row)"); }
        Some(p) => {
          match tuple2_decode_row(&p) {
            Err(_) => { io.println("(undecodable typed row)"); }
            Ok(row) => {
              io.print("id=" + cli_i2s(row.id) + " values=[");
              var i = 0;
              while i < row.values.len() {
                if i > 0 { io.print(", "); }
                let v = row.values[i];
                if tuple2_is_null(v) {
                  io.print("null");
                } else {
                  let kind = tuple2_kind(v);
                  if kind == 0x01 {
                    match tuple2_int_value(v) { Some(x) => { io.print(cli_i2s(x)); } None => { io.print("?"); } }
                  }
                  if kind == 0x02 {
                    match tuple2_float_value(v) { Some(f) => { io.print(convert.float_to_string(f)); } None => { io.print("?"); } }
                  }
                  if kind == 0x03 {
                    match tuple2_text_value(v) { Some(s) => { io.print("\"" + s + "\""); } None => { io.print("?"); } }
                  }
                  if kind == 0x04 {
                    match tuple2_blob_value(v) { Some(b) => { io.print("blob(" + cli_i2s(b.len()) + "B)"); } None => { io.print("?"); } }
                  }
                }
                i = i + 1;
              }
              io.println("]");
            }
          }
        }
      }
    }
  }
  return true;
}

fn cli_parse_literal(t: Str) -> Result[TValue, Str] {
  if t == "n" { return Ok(TValue.VNull); }
  if t.len() >= 2 && t.substr(0, 2) == "s:" {
    return Ok(TValue.VText(t.substr(2, t.len())));
  }
  if t.len() >= 2 && t.substr(0, 2) == "f:" {
    match parse.parse_float(t.substr(2, t.len())) {
      Err(_) => { return Err("bad float: " + t); }
      Ok(f) => { return Ok(TValue.VFloat(f)); }
    }
  }
  if t.len() >= 2 && t.substr(0, 2) == "i:" {
    match parse.parse_int(t.substr(2, t.len())) {
      Err(_) => { return Err("bad int: " + t); }
      Ok(x) => { return Ok(TValue.VInt(x)); }
    }
  }
  match parse.parse_int(t) {
    Err(_) => { return Err("bad literal (use int | i: | s: | f: | n): " + t); }
    Ok(x) => { return Ok(TValue.VInt(x)); }
  }
}

fn cli_parse_op(t: Str) -> Result[QueryOp, Str] {
  if t == "=" || t == "eq" { return Ok(QueryOp.Eq); }
  if t == "!=" || t == "ne" { return Ok(QueryOp.Neq); }
  if t == "<" || t == "lt" { return Ok(QueryOp.Lt); }
  if t == "<=" || t == "le" { return Ok(QueryOp.Lte); }
  if t == ">" || t == "gt" { return Ok(QueryOp.Gt); }
  if t == ">=" || t == "ge" { return Ok(QueryOp.Gte); }
  return Err("bad op (use = != < <= > >=): " + t);
}

fn cli_run_qrow(db: &DBFile, toks: &Vec[Str]) -> Bool {
  if toks.len() < 4 {
    io.println("usage: qrow <col> <op> <literal>   (col -1 = id; op = != < <= > >=)");
    return true;
  }
  match cli_arg_int(toks, 1) {
    Err(_) => { io.println("usage: qrow <col> <op> <literal>"); return true; }
    Ok(col) => {
      match cli_parse_op(toks[2]) {
        Err(e) => { io.println(e); return true; }
        Ok(op) => {
          match cli_parse_literal(toks[3]) {
            Err(e) => { io.println(e); return true; }
            Ok(lit) => {
              var q = typed_query_new();
              typed_query_where(&mut q, col, op, lit);
              let hits = db_file_query_typed(db, &q);
              io.print("matches=" + cli_i2s(hits.len()) + " pks=[");
              var i = 0;
              while i < hits.len() && i < 16 {
                if i > 0 { io.print(","); }
                io.print(cli_i2s(hits[i]));
                i = i + 1;
              }
              if hits.len() > 16 { io.print(",..."); }
              io.println("]");
            }
          }
        }
      }
    }
  }
  return true;
}

// Dispatch one line. Returns: 0 = quit, 1 = continue, 2 = reopen request.
fn cli_dispatch(db: &mut DBFile, toks: &Vec[Str]) -> Int {
  if toks.len() == 0 { return 1; }
  let cmd = toks[0];
  if cmd == "quit" || cmd == "exit" { return 0; }
  if cmd == "help" { cli_usage(); return 1; }
  if cmd == "info" { cli_show_info(db); return 1; }
  if cmd == "count" {
    io.println(cli_i2s(db_file_size(db)));
    return 1;
  }
  if cmd == "put" {
    let _ = cli_run_put(db, toks);
    return 1;
  }
  if cmd == "get" {
    let _ = cli_run_get(db, toks);
    return 1;
  }
  if cmd == "del" {
    let _ = cli_run_del(db, toks);
    return 1;
  }
  if cmd == "range" {
    let _ = cli_run_range(db, toks);
    return 1;
  }
  if cmd == "ckpt" {
    let _ = cli_run_ckpt(db);
    return 1;
  }
  if cmd == "bench" {
    let _ = cli_run_bench(db, toks);
    return 1;
  }
  if cmd == "putrow" {
    let _ = cli_run_putrow(db, toks);
    return 1;
  }
  if cmd == "getrow" {
    let _ = cli_run_getrow(db, toks);
    return 1;
  }
  if cmd == "qrow" {
    let _ = cli_run_qrow(db, toks);
    return 1;
  }
  if cmd == "recover" { return 2; }
  if cmd == "kill" {
    io.println("killing process WITHOUT cleanup (restart to watch recovery)");
    io.exit(9);
  }
  io.println("unknown command: " + cmd + " (try help)");
  return 1;
}

fn main() -> Int {
  var path = "orbitdb-data.wal";
  if env.args_len() >= 2 {
    match env.arg_at(1) {
      Some(p) => { path = p; }
      None => {}
    }
  }
  io.println("ORBITDB shell (v0, int + typed rows) -- db: " + path);
  io.println("help for commands; empty line / EOF exits; `kill` simulates a crash");
  var db = db_file_open(path, 4);
  cli_show_info(&db);
  var running = true;
  while running {
    io.print("orbitdb> ");
    let line = io.read_line();
    if line.len() == 0 {
      running = false;
    } else {
      let toks = cli_tokens(line);
      let act = cli_dispatch(&mut db, &toks);
      if act == 0 {
        running = false;
      }
      if act == 2 {
        let before = db_file_size(&db);
        db = db_file_open(path, 4);
        io.println("reopened: rows " + cli_i2s(before) + " -> " + cli_i2s(db_file_size(&db))
          + " (lsn " + cli_i2s(db_file_last_lsn(&db)) + ")");
      }
    }
  }
  io.println("bye");
  return 0;
}

