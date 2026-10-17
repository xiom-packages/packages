// XIOM ORBITDB -- durable page file probe (critical storage primitive).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Acceptance for src/storage/page_file.xi, driven by
// scripts/page_crash_test.ps1/.sh: writer writes N CRC32C-sealed pages, the
// harness hard-kills it, leaves a torn tail, then reopens and verifies every
// page (checksum + byte pattern) and upperts one more page.
//
// Env:
//   ORBITDB_PAGE_FILE     page file path (required)
//   ORBITDB_PAGE_MODE     write | verify | write1        (default: verify)
//   ORBITDB_PAGE_N        page count for write / verify  (default: 20)
//   ORBITDB_PAGE_LAST_ID  optional: id that must be present after verify
//
// Exit: 0 = succeeded, 1 = check failed, 2 = bad env/read error.

module orbitdb_probe_page_file

use xiom.io;
use xiom.os.env;
use xiom.convert;
use xiom.convert.parse;
use xiom.db.storage.page;
use xiom.db.storage.page_file;

fn expected_byte(id: Int, j: Int) -> Int {
  return (id * 31 + j * 7) & 0xFF;
}

fn make_page(id: Int) -> Page {
  var data = Vec[Int].new();
  var j = 0;
  while j < 16 {
    data.push(expected_byte(id, j));
    j = j + 1;
  }
  let cs = page_compute_checksum(&data);
  return Page.new(id, data, cs);
}

fn run_write(path: Str, n: Int) -> Int {
  let pf = page_file_open(path);
  var i = 1;
  while i <= n {
    if !page_file_write(&pf, make_page(i)) {
      io.println("writer: write failed at " + convert.int_to_string(i));
      return 1;
    }
    i = i + 1;
  }
  let ok = page_file_sync(&pf);
  if !ok { io.println("writer: sync failed"); return 1; }
  io.println("writer: wrote " + convert.int_to_string(n));
  // Hang until the harness hard-kills us (crash simulation).
  var alive = true;
  while alive {
    io.sleep(1000);
  }
  return 0;
}

fn run_verify(path: Str, n: Int) -> Int {
  let pf = page_file_open(path);
  let count = page_file_count(&pf);
  io.println("verify: pages=" + convert.int_to_string(count));
  if count != n {
    io.println("verify: expected " + convert.int_to_string(n) + " got " + convert.int_to_string(count));
    return 1;
  }
  let ids = page_file_ids(&pf);
  var k = 0;
  while k < ids.len() {
    let id = ids[k];
    let got = page_file_read(&pf, id);
    match got {
      None => {
        io.println("verify: page missing/invalid " + convert.int_to_string(id));
        return 1;
      }
      Some(p) => {
        let pg: Page = p;
        if !pg.is_valid() {
          io.println("verify: checksum invalid " + convert.int_to_string(id));
          return 1;
        }
        if pg.data.len() != 16 {
          io.println("verify: length wrong " + convert.int_to_string(id));
          return 1;
        }
        var j = 0;
        while j < 16 {
          if pg.data[j] != expected_byte(id, j) {
            io.println("verify: byte mismatch page=" + convert.int_to_string(id) + " j=" + convert.int_to_string(j));
            return 1;
          }
          j = j + 1;
        }
      }
    }
    k = k + 1;
  }
  let last_id_s = env.var_or("ORBITDB_PAGE_LAST_ID", "");
  if last_id_s != "" {
    match parse.parse_int(last_id_s) {
      Ok(lid) => {
        let extra = page_file_read(&pf, lid);
        match extra {
          None => { io.println("verify: last id missing"); return 1; }
          Some(p) => {
            let pg: Page = p;
            if !pg.is_valid() { io.println("verify: last checksum"); return 1; }
          }
        }
      }
      Err(_) => { return 2; }
    }
  }
  io.println("verify: OK n=" + convert.int_to_string(n));
  return 0;
}

fn main() -> Int {
  let path = env.var_or("ORBITDB_PAGE_FILE", "");
  if path == "" {
    io.println("probe_page_file: ORBITDB_PAGE_FILE not set");
    return 2;
  }
  let mode = env.var_or("ORBITDB_PAGE_MODE", "verify");
  var n = 20;
  match parse.parse_int(env.var_or("ORBITDB_PAGE_N", "20")) {
    Ok(v) => { n = v; }
    Err(_) => { n = 20; }
  }

  if mode == "write" {
    return run_write(path, n);
  }
  if mode == "write1" {
    let pf = page_file_open(path);
    if !page_file_write(&pf, make_page(9999)) {
      io.println("write1: failed");
      return 1;
    }
    io.println("write1: OK");
    return 0;
  }
  return run_verify(path, n);
}
