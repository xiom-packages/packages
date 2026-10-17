// XIOM ORBITDB -- stdlib wave-115 durability/byte-IO verification probe.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Verifies the primitives behind our fixed stdlib rows on the lane runtime
// (wave 115, stdlib c65acb5; run with XIOM_RUNTIME_DIR=<stdlib>/runtime until
// the next compiler pin re-vendors it):
//   orbitdb-3 real fsync            -> sync_io.sync_fd + io.fsync
//   orbitdb-4 held append handle    -> sync_io.open_append/write_all/close_fd
//   orbitdb-5 truncate primitive    -> io.truncate_file
//   orbitdb-6 byte random access    -> io.read_at / io.write_at / io.append_file_bytes
//   orbitdb-7 tail-repair append    -> io.append_line_sync (wave 117, 260bb44)
//   orbitdb-8 cheap tail check      -> io.file_last_byte / io.ends_with_newline
//   P3 rename durability            -> sync_io.fsync_dir
//
// Env: ORBITDB_IO_PRIM_DIR (default probe-logs). Exit: 0 = all checks, 1 = failed.

module orbitdb_probe_io_primitives

use xiom.io;
use xiom.os.env;
use xiom.os.sync_io;
use xiom.convert;

fn check(ok: Bool, name: Str, fails: Int) -> Int {
  if ok { io.println("  [PASS] " + name); return fails; }
  io.println("  [FAIL] " + name);
  return fails + 1;
}

fn bytes2(a: UInt8, b: UInt8) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(a);
  v.push(b);
  return v;
}

fn bytes3(a: UInt8, b: UInt8, c: UInt8) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(a);
  v.push(b);
  v.push(c);
  return v;
}

fn cat2(a: &Vec[UInt8], b: &Vec[UInt8]) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < a.len() {
    v.push(a[i]);
    i = i + 1;
  }
  i = 0;
  while i < b.len() {
    v.push(b[i]);
    i = i + 1;
  }
  return v;
}

fn bytes_eq(a: &Vec[UInt8], b: &Vec[UInt8]) -> Bool {
  if a.len() != b.len() { return false; }
  var i = 0;
  while i < a.len() {
    if a[i] != b[i] { return false; }
    i = i + 1;
  }
  return true;
}

fn main() -> Int {
  let dir = env.var_or("ORBITDB_IO_PRIM_DIR", "probe-logs");
  let path = dir + "/io-prim.bin";
  let tmp = dir + "/io-prim.tmp";
  let _ = io.remove_file(path);
  let _ = io.remove_file(tmp);
  var fails: Int = 0;

  // A. held append handle + sync_fd (rows -3, -4).
  let a1 = sync_io.open_append(path);
  match a1 {
    Err(_) => { fails = check(false, "open_append returns a handle", fails); }
    Ok(fd) => {
      fails = check(true, "open_append returns a handle", fails);
      let payload = bytes2(97 as UInt8, 98 as UInt8);
      let w1 = sync_io.write_all(fd, &payload);
      fails = check(w1.is_ok, "write_all via the held handle", fails);
      let s1 = sync_io.sync_fd(fd);
      fails = check(s1.is_ok, "sync_fd (real fsync) returns Ok", fails);
      let c1 = sync_io.close_fd(fd);
      fails = check(c1.is_ok, "close_fd returns Ok", fails);
    }
  }
  match io.file_size(path) {
    None => { fails = check(false, "file_size after handle close", fails); }
    Some(sz) => { fails = check(sz == 2, "file_size == 2 after handle close", fails); }
  }

  // B. append_file_bytes + read_at + write_at (row -6).
  let ap = io.append_file_bytes(path, &bytes2(99 as UInt8, 100 as UInt8));
  fails = check(ap.is_ok, "append_file_bytes returns Ok", fails);
  let r1 = io.read_at(path, 0, 4);
  match r1 {
    Err(_) => { fails = check(false, "read_at(0,4) returns Ok", fails); }
    Ok(b) => {
      var ok = b.len() == 4;
      if ok { ok = b[0] == (97 as UInt8); }
      if ok { ok = b[1] == (98 as UInt8); }
      if ok { ok = b[2] == (99 as UInt8); }
      if ok { ok = b[3] == (100 as UInt8); }
      fails = check(ok, "read_at(0,4) == a,b,c,d", fails);
    }
  }
  let w2 = io.write_at(path, 1, &bytes2(88 as UInt8, 89 as UInt8));
  fails = check(w2.is_ok, "write_at(1,[X,Y]) returns Ok", fails);
  let r2 = io.read_at(path, 0, 4);
  match r2 {
    Err(_) => { fails = check(false, "read_at after write_at", fails); }
    Ok(b) => {
      var ok = b.len() == 4;
      if ok { ok = b[0] == (97 as UInt8); }
      if ok { ok = b[1] == (88 as UInt8); }
      if ok { ok = b[2] == (89 as UInt8); }
      if ok { ok = b[3] == (100 as UInt8); }
      fails = check(ok, "write_at overwrote the middle two bytes", fails);
    }
  }

  // C. truncate_file (row -5).
  let tr = io.truncate_file(path, 3);
  fails = check(tr.is_ok, "truncate_file(3) returns Ok", fails);
  match io.file_size(path) {
    None => { fails = check(false, "file_size after truncate", fails); }
    Some(sz) => { fails = check(sz == 3, "file_size == 3 after truncate", fails); }
  }
  let r3 = io.read_at(path, 0, 3);
  match r3 {
    Err(_) => { fails = check(false, "read_at(0,3) after truncate", fails); }
    Ok(b) => {
      var ok = b.len() == 3;
      if ok { ok = b[2] == (89 as UInt8); }
      fails = check(ok, "truncate kept the first three bytes", fails);
    }
  }

  // D. fsync_dir (P3, rename durability).
  let fd_tmp = sync_io.open_append(tmp);
  match fd_tmp {
    Err(_) => { fails = check(false, "open_append on tmp", fails); }
    Ok(fd) => {
      let p = bytes2(49 as UInt8, 50 as UInt8);
      let _ = sync_io.write_all(fd, &p);
      let _ = sync_io.sync_fd(fd);
      let _ = sync_io.close_fd(fd);
    }
  }
  let d = sync_io.fsync_dir(dir);
  fails = check(d.is_ok, "fsync_dir returns Ok", fails);
  // E. append_line_sync + tail checks (rows -7, -8; stdlib wave 117).
  let line_path = dir + "/io-prim-lines.log";
  let _ = io.remove_file(line_path);
  let al1 = io.append_line_sync(line_path, "hello");
  fails = check(al1.is_ok, "append_line_sync on a fresh path returns Ok", fails);
  match io.file_last_byte(line_path) {
    None => { fails = check(false, "file_last_byte == LF after append", fails); }
    Some(b) => { fails = check(b == (10 as UInt8), "file_last_byte == LF after append", fails); }
  }
  fails = check(io.ends_with_newline(line_path), "ends_with_newline true after append", fails);
  let lr1 = io.read_at(line_path, 0, 6);
  match lr1 {
    Err(_) => { fails = check(false, "line payload is hello\\n", fails); }
    Ok(b) => {
      var ok = b.len() == 6;
      if ok { ok = b[0] == (104 as UInt8); }
      if ok { ok = b[4] == (111 as UInt8); }
      if ok { ok = b[5] == (10 as UInt8); }
      fails = check(ok, "line payload is hello\\n", fails);
    }
  }
  // Torn tail: "ab" without a newline, then append_line_sync repairs it.
  let torn = bytes2(97 as UInt8, 98 as UInt8);
  let _ = io.append_file_bytes(line_path, &torn);
  let al2 = io.append_line_sync(line_path, "cd");
  fails = check(al2.is_ok, "append_line_sync repairs a torn tail (Ok)", fails);
  let lr2 = io.read_at(line_path, 9, 3);
  match lr2 {
    Err(_) => { fails = check(false, "repaired tail ends c,d,LF at offset 9", fails); }
    Ok(b) => {
      var ok = b.len() == 3;
      if ok { ok = b[0] == (99 as UInt8); }
      if ok { ok = b[1] == (100 as UInt8); }
      if ok { ok = b[2] == (10 as UInt8); }
      fails = check(ok, "repaired tail ends c,d,LF at offset 9", fails);
    }
  }
  match io.file_last_byte(dir + "/io-prim-missing.bin") {
    None => { fails = check(true, "file_last_byte None on a missing file", fails); }
    Some(_) => { fails = check(false, "file_last_byte None on a missing file", fails); }
  }
  fails = check(!io.ends_with_newline(dir + "/io-prim-missing.bin"), "ends_with_newline false on a missing file", fails);
  let rm3 = io.remove_file(line_path);
  fails = check(rm3.is_ok, "cleanup removes the line fixture", fails);

  let rm1 = io.remove_file(path);
  let rm2 = io.remove_file(tmp);
  fails = check(rm1.is_ok && rm2.is_ok, "cleanup removes both fixtures", fails);

  // E. Tail checks + append_line_sync (rows -7, -8; stdlib wave 117).
  let e1 = dir + "/io-last.bin";
  let e2 = dir + "/io-sync.log";
  let _ = io.remove_file(e1);
  let _ = io.remove_file(e2);
  let abnl = bytes3(97 as UInt8, 98 as UInt8, 10 as UInt8);
  let ab = bytes2(97 as UInt8, 98 as UInt8);
  let _ = io.write_file_bytes(e1, &abnl);
  var lb_ok = false;
  match io.file_last_byte(e1) {
    Some(b) => { lb_ok = b == (10 as UInt8); }
    None => { lb_ok = false; }
  }
  fails = check(lb_ok, "file_last_byte sees the trailing newline", fails);
  let _ = io.write_file_bytes(e1, &ab);
  var lb2 = false;
  match io.file_last_byte(e1) {
    Some(b) => { lb2 = b == (98 as UInt8); }
    None => { lb2 = false; }
  }
  fails = check(lb2 && !io.ends_with_newline(e1), "torn tail: last byte + no newline", fails);
  let _ = io.write_file_bytes(e1, &abnl);
  fails = check(io.ends_with_newline(e1), "ends_with_newline true after newline", fails);
  let emptyv = Vec[UInt8].new();
  let _ = io.write_file_bytes(e1, &emptyv);
  var en_ok = false;
  match io.file_last_byte(e1) {
    Some(_) => { en_ok = false; }
    None => { en_ok = true; }
  }
  fails = check(en_ok && !io.ends_with_newline(e1), "empty file: None + false", fails);
  let _ = io.remove_file(e1);
  var miss_ok = false;
  match io.file_last_byte(e1) {
    Some(_) => { miss_ok = false; }
    None => { miss_ok = true; }
  }
  fails = check(miss_ok && !io.ends_with_newline(e1), "missing file: None + false", fails);

  // append_line_sync: terminate the torn tail, then append line + newline.
  let _ = io.write_file_bytes(e2, &ab);
  let s1 = io.append_line_sync(e2, "cd");
  var sync_ok = s1.is_ok;
  if sync_ok {
    match io.read_file_bytes(e2) {
      Ok(b) => { sync_ok = bytes_eq(&b, &cat2(&abnl, &bytes3(99 as UInt8, 100 as UInt8, 10 as UInt8))); }
      Err(_) => { sync_ok = false; }
    }
  }
  fails = check(sync_ok, "append_line_sync repairs torn tail + appends + flushes", fails);
  let s2 = io.append_line_sync(e2, "ef");
  var sync2 = s2.is_ok;
  if sync2 {
    var expect = cat2(&abnl, &bytes3(99 as UInt8, 100 as UInt8, 10 as UInt8));
    expect = cat2(&expect, &bytes3(101 as UInt8, 102 as UInt8, 10 as UInt8));
    match io.read_file_bytes(e2) {
      Ok(b) => { sync2 = bytes_eq(&b, &expect); }
      Err(_) => { sync2 = false; }
    }
  }
  fails = check(sync2, "append_line_sync second append appends cleanly", fails);
  let _ = io.remove_file(e2);

  if fails == 0 { io.println("io-primitives: GREEN"); return 0; }
  io.println("io-primitives: RED fails=" + convert.int_to_string(fails));
  return 1;
}
