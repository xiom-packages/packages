// XIOM -- xiom.kv conformance tests (28 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Every fixture is created in fs_temp_dir() under a per-run prefix
// ("xiomkv-<time>-<tag>-"); no directory is ever created. Files are removed
// with io.remove_file by clean_prefix (the package's own segment ids are
// probed, because io.list_dir returns corrupted entry names on the pinned
// v0.64.0 Windows runtime -- see SPEC.md "toolchain deviations").
//
// Covered: open/create + header bytes; put/get/overwrite/delete; contains,
// count and first-write key order; reopen persistence; byte values; torn-tail
// repair and no-fuse rotation; CRC corruption ignored on the newest segment
// and rejected on an older one; bad-header abandon on the newest and error on
// older; compaction (live set, single new segment, old removal, stale tmp);
// rotation across segments; snapshot roundtrip, replay after the snapshot,
// corrupt-snapshot fallback and snapshot+compact; determinism; key limits,
// open validation, close no-op and the short-read guard. Str equality goes
// through str_compare; byte reads are widened with & 0xFF.

module kv_tests

use xiom.io;
use xiom.io.fs;
use xiom.test;
use xiom.kv;
use xiom.string;
use xiom.convert.int;
use xiom.hash.crc;
use xiom.serialize.endian;

// --------------------------------------------------
//  Fixtures and helpers
// --------------------------------------------------

fn str_eq(a: Str, b: Str) -> Bool {
  return string.str_compare(a, b) == 0;
}

fn bytes_eq(a: &Vec[UInt8], b: &Vec[UInt8]) -> Bool {
  if a.len() != b.len() { return false; }
  var i = 0;
  while i < a.len() {
    let ba = (a[i] as Int) & 0xFF;
    let bb = (b[i] as Int) & 0xFF;
    if ba != bb { return false; }
    i = i + 1;
  }
  return true;
}

// Per-run, per-test file-name prefix: nothing is shared between tests.
fn run_prefix(tag: Str) -> Str {
  return "xiomkv-" + int_to_base(io.time_now(), 10) + "-" + tag + "-";
}

fn pad10(n: Int) -> Str {
  let s = int_to_base(n, 10);
  if s.len() >= 10 { return s; }
  var pad = "";
  var k = 10 - s.len();
  var i = 0;
  while i < k {
    pad = pad + "0";
    i = i + 1;
  }
  return pad + s;
}

fn seg_name(prefix: Str, id: Int) -> Str {
  return prefix + "seg-" + pad10(id) + ".kv";
}

fn seg_tmp_name(prefix: Str, id: Int) -> Str {
  return prefix + "seg-" + pad10(id) + ".tmp";
}

fn seg_path(dir: Str, prefix: Str, id: Int) -> Str {
  return io.join_paths(dir, seg_name(prefix, id));
}

fn snap_path(dir: Str, prefix: Str) -> Str {
  return io.join_paths(dir, prefix + "snapshot.kv");
}

fn tf_size(dir: Str, name: Str) -> Int {
  let r = fs.fs_size(io.join_paths(dir, name));
  if !r.is_ok { return -1; }
  return r.value;
}

fn tf_read(dir: Str, name: Str) -> Vec[UInt8] {
  let p = io.join_paths(dir, name);
  let sz = fs.fs_size(p);
  if !sz.is_ok { return Vec[UInt8].new(); }
  let r = fs.fs_read_range(p, 0, sz.value);
  if !r.is_ok { return Vec[UInt8].new(); }
  return r.value;
}

fn tf_write(dir: Str, name: Str, data: &Vec[UInt8]) -> Bool {
  let r = fs.fs_write(io.join_paths(dir, name), data);
  return r.is_ok;
}

fn tf_append(dir: Str, name: Str, data: &Vec[UInt8]) -> Bool {
  let r = fs.fs_append(io.join_paths(dir, name), data);
  return r.is_ok;
}

// Counts existing segment files by probing ids 1..cap.
fn count_segs(dir: Str, prefix: Str, cap: Int) -> Int {
  var n = 0;
  var i = 1;
  while i <= cap {
    if io.file_exists(seg_path(dir, prefix, i)) { n = n + 1; }
    i = i + 1;
  }
  return n;
}

// Removes every fixture file this store could have produced (segments, tmp,
// abandon files, snapshot and snapshot tmp) for ids 1..64.
fn clean_prefix(dir: Str, prefix: Str) {
  var id = 1;
  while id <= 64 {
    let _ = io.remove_file(seg_path(dir, prefix, id));
    let _ = io.remove_file(io.join_paths(dir, seg_tmp_name(prefix, id)));
    let _ = io.remove_file(io.join_paths(dir, seg_name(prefix, id) + ".bad"));
    id = id + 1;
  }
  let _ = io.remove_file(snap_path(dir, prefix));
  let _ = io.remove_file(io.join_paths(dir, prefix + "snapshot.tmp"));
}

fn finish(ok: Bool, name: Str, dir: Str, prefix: Str) -> TestResult {
  clean_prefix(dir, prefix);
  return assert(ok, name);
}

fn get_eq(s: &KvStore, key: Str, want: Str) -> Bool {
  let r = kv_get(s, key);
  if !r.is_ok { return false; }
  let o = r.value;
  match o {
    Some(v) => { return str_eq(v, want); },
    None => {},
  }
  return false;
}

fn get_none(s: &KvStore, key: Str) -> Bool {
  let r = kv_get(s, key);
  if !r.is_ok { return false; }
  let o = r.value;
  return !o.is_some;
}

fn put_ok(s: &mut KvStore, key: Str, value: Str) -> Bool {
  let r = kv_put(s, key, value);
  return r.is_ok;
}

fn keys_eq(s: &KvStore, want: &Vec[Str]) -> Bool {
  let ks = kv_keys(s);
  if ks.len() != want.len() { return false; }
  var i = 0;
  while i < ks.len() {
    if !str_eq(ks[i], want[i]) { return false; }
    i = i + 1;
  }
  return true;
}

fn flip_byte(src: &Vec[UInt8], pos: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < src.len() {
    if i == pos {
      let b = (src[i] as Int) & 0xFF;
      let f = (b ^ 90) & 0xFF;
      out.push(f as UInt8);
    } else {
      out.push(src[i]);
    }
    i = i + 1;
  }
  return out;
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1_open_header(dir: Str) -> TestResult {
  let name = "open creates seg-1 with a valid 28-byte header";
  let prefix = run_prefix("t01");
  let r = kv_open(dir, prefix, 100000);
  if !r.is_ok { return finish(false, name, dir, prefix); }
  var s = r.value;
  var ok = true;
  if kv_count(&s) != 0 { ok = false; }
  if s.seg_id != 1 { ok = false; }
  if s.seg_len != 28 { ok = false; }
  if !io.file_exists(seg_path(dir, prefix, 1)) { ok = false; }
  let raw = tf_read(dir, seg_name(prefix, 1));
  if raw.len() != 28 {
    ok = false;
  } else {
    let magic = endian.read_u32_le(&raw, 0) as Int;
    let ver = endian.read_u16_le(&raw, 4) as Int;
    let flags = endian.read_u16_le(&raw, 6) as Int;
    let sid = endian.read_u64_le(&raw, 8) as Int;
    if magic != KV_MAGIC { ok = false; }
    if ver != 1 { ok = false; }
    if flags != 0 { ok = false; }
    if sid != 1 { ok = false; }
    var first24 = Vec[UInt8].new();
    var i = 0;
    while i < 24 {
      first24.push(raw[i]);
      i = i + 1;
    }
    let stored = endian.read_u32_le(&raw, 24) as Int;
    if (crc.crc32c(&first24) as Int) != stored { ok = false; }
  }
  return finish(ok, name, dir, prefix);
}

fn t2_put_get(dir: Str) -> TestResult {
  let name = "put/get roundtrip, missing key is None";
  let prefix = run_prefix("t02");
  let r = kv_open(dir, prefix, 100000);
  if !r.is_ok { return finish(false, name, dir, prefix); }
  var s = r.value;
  var ok = true;
  if !put_ok(&mut s, "alpha", "one") { ok = false; }
  if !get_eq(&s, "alpha", "one") { ok = false; }
  if !get_none(&s, "beta") { ok = false; }
  if kv_count(&s) != 1 { ok = false; }
  if !kv_contains(&s, "alpha") { ok = false; }
  if kv_contains(&s, "beta") { ok = false; }
  return finish(ok, name, dir, prefix);
}

fn t3_overwrite(dir: Str) -> TestResult {
  let name = "overwrite keeps one live slot with the newest value";
  let prefix = run_prefix("t03");
  let r = kv_open(dir, prefix, 100000);
  if !r.is_ok { return finish(false, name, dir, prefix); }
  var s = r.value;
  var ok = true;
  if !put_ok(&mut s, "k", "v1") { ok = false; }
  if !put_ok(&mut s, "k", "v2") { ok = false; }
  if !get_eq(&s, "k", "v2") { ok = false; }
  if kv_count(&s) != 1 { ok = false; }
  let ks = kv_keys(&s);
  if ks.len() != 1 { ok = false; }
  return finish(ok, name, dir, prefix);
}

fn t4_delete(dir: Str) -> TestResult {
  let name = "delete returns live-state, is idempotent and hides the key";
  let prefix = run_prefix("t04");
  let r = kv_open(dir, prefix, 100000);
  if !r.is_ok { return finish(false, name, dir, prefix); }
  var s = r.value;
  var ok = true;
  if !put_ok(&mut s, "k", "v") { ok = false; }
  let d1 = kv_delete(&mut s, "k");
  if !d1.is_ok { ok = false; } else {
    if !d1.value { ok = false; }
  }
  if !get_none(&s, "k") { ok = false; }
  if kv_contains(&s, "k") { ok = false; }
  if kv_count(&s) != 0 { ok = false; }
  if kv_keys(&s).len() != 0 { ok = false; }
  let d2 = kv_delete(&mut s, "k");
  if !d2.is_ok { ok = false; } else {
    if d2.value { ok = false; }
  }
  if kv_count(&s) != 0 { ok = false; }
  return finish(ok, name, dir, prefix);
}

fn t5_keys_order(dir: Str) -> TestResult {
  let name = "keys follow first-write order across overwrite, delete, re-put";
  let prefix = run_prefix("t05");
  let r = kv_open(dir, prefix, 100000);
  if !r.is_ok { return finish(false, name, dir, prefix); }
  var s = r.value;
  var ok = true;
  if !put_ok(&mut s, "k1", "a") { ok = false; }
  if !put_ok(&mut s, "k2", "b") { ok = false; }
  if !put_ok(&mut s, "k3", "c") { ok = false; }
  var want1 = Vec[Str].new();
  want1.push("k1"); want1.push("k2"); want1.push("k3");
  if !keys_eq(&s, &want1) { ok = false; }
  if !put_ok(&mut s, "k2", "b2") { ok = false; }
  if !keys_eq(&s, &want1) { ok = false; }
  let _ = kv_delete(&mut s, "k2");
  var want2 = Vec[Str].new();
  want2.push("k1"); want2.push("k3");
  if !keys_eq(&s, &want2) { ok = false; }
  if !put_ok(&mut s, "k2", "b3") { ok = false; }
  if !keys_eq(&s, &want1) { ok = false; }
  if !get_eq(&s, "k2", "b3") { ok = false; }
  return finish(ok, name, dir, prefix);
}

fn t6_reopen(dir: Str) -> TestResult {
  let name = "reopen persists values, tombstones and order";
  let prefix = run_prefix("t06");
  let r = kv_open(dir, prefix, 100000);
  if !r.is_ok { return finish(false, name, dir, prefix); }
  var s = r.value;
  var ok = true;
  if !put_ok(&mut s, "a", "1") { ok = false; }
  if !put_ok(&mut s, "b", "2") { ok = false; }
  if !put_ok(&mut s, "c", "3") { ok = false; }
  if !put_ok(&mut s, "d", "4") { ok = false; }
  if !put_ok(&mut s, "e", "5") { ok = false; }
  if !put_ok(&mut s, "c", "33") { ok = false; }
  let _ = kv_delete(&mut s, "b");
  let rr = kv_reopen(&mut s);
  if !rr.is_ok { ok = false; }
  if kv_count(&s) != 4 { ok = false; }
  if !get_eq(&s, "a", "1") { ok = false; }
  if !get_eq(&s, "c", "33") { ok = false; }
  if !get_eq(&s, "e", "5") { ok = false; }
  if !get_none(&s, "b") { ok = false; }
  var want = Vec[Str].new();
  want.push("a"); want.push("c"); want.push("d"); want.push("e");
  if !keys_eq(&s, &want) { ok = false; }
  return finish(ok, name, dir, prefix);
}

fn t7_bytes(dir: Str) -> TestResult {
  let name = "byte values roundtrip exactly through put_bytes/get_bytes";
  let prefix = run_prefix("t07");
  let r = kv_open(dir, prefix, 100000);
  if !r.is_ok { return finish(false, name, dir, prefix); }
  var s = r.value;
  var ok = true;
  var val = Vec[UInt8].new();
  var i = 0;
  while i < 256 {
    val.push(i as UInt8);
    i = i + 1;
  }
  let pr = kv_put_bytes(&mut s, "bin", &val);
  if !pr.is_ok { ok = false; }
  let gr = kv_get_bytes(&s, "bin");
  if !gr.is_ok {
    ok = false;
  } else {
    let o = gr.value;
    match o {
      Some(b) => {
        if !bytes_eq(&b, &val) { ok = false; }
      },
      None => { ok = false; },
    }
  }
  if !put_ok(&mut s, "txt", "plain text 123") { ok = false; }
  if !get_eq(&s, "txt", "plain text 123") { ok = false; }
  let mr = kv_get_bytes(&s, "missing");
  if !mr.is_ok {
    ok = false;
  } else {
    if mr.value.is_some { ok = false; }
  }
  return finish(ok, name, dir, prefix);
}

fn t8_torn_tail(dir: Str) -> TestResult {
  let name = "torn-tail junk is repaired on reopen and a fresh segment starts";
  let prefix = run_prefix("t08");
  let r = kv_open(dir, prefix, 100000);
  if !r.is_ok { return finish(false, name, dir, prefix); }
  var s = r.value;
  var ok = true;
  if !put_ok(&mut s, "a", "1") { ok = false; }
  if !put_ok(&mut s, "b", "2") { ok = false; }
  if !put_ok(&mut s, "c", "3") { ok = false; }
  let before = tf_size(dir, seg_name(prefix, 1));
  if before <= 28 { ok = false; }
  var junk = Vec[UInt8].new();
  junk.push(1 as UInt8); junk.push(2 as UInt8); junk.push(3 as UInt8);
  junk.push(4 as UInt8); junk.push(5 as UInt8);
  if !tf_append(dir, seg_name(prefix, 1), &junk) { ok = false; }
  let rr = kv_reopen(&mut s);
  if !rr.is_ok { ok = false; }
  if kv_count(&s) != 3 { ok = false; }
  if !get_eq(&s, "a", "1") { ok = false; }
  if !get_eq(&s, "b", "2") { ok = false; }
  if !get_eq(&s, "c", "3") { ok = false; }
  if s.seg_id != 2 { ok = false; }
  if tf_size(dir, seg_name(prefix, 1)) != before { ok = false; }
  if tf_size(dir, seg_name(prefix, 2)) != 28 { ok = false; }
  let rr2 = kv_reopen(&mut s);
  if !rr2.is_ok { ok = false; }
  if kv_count(&s) != 3 { ok = false; }
  if !put_ok(&mut s, "d", "4") { ok = false; }
  let rr3 = kv_reopen(&mut s);
  if !rr3.is_ok { ok = false; }
  if kv_count(&s) != 4 { ok = false; }
  if !get_eq(&s, "d", "4") { ok = false; }
  return finish(ok, name, dir, prefix);
}

fn t9_torn_no_fuse(dir: Str) -> TestResult {
  let name = "a torn record with a huge claimed length cannot fuse with new writes";
  let prefix = run_prefix("t09");
  let r = kv_open(dir, prefix, 100000);
  if !r.is_ok { return finish(false, name, dir, prefix); }
  var s = r.value;
  var ok = true;
  if !put_ok(&mut s, "k1", "v1") { ok = false; }
  var bad = Vec[UInt8].new();
  endian.write_u32_le(bad, 0 as UInt32);
  endian.write_u32_le(bad, 0 as UInt32);
  endian.write_u32_le(bad, 3 as UInt32);
  endian.write_u32_le(bad, 1000000 as UInt32);
  if !tf_append(dir, seg_name(prefix, 1), &bad) { ok = false; }
  let rr = kv_reopen(&mut s);
  if !rr.is_ok { ok = false; }
  if kv_count(&s) != 1 { ok = false; }
  if !get_eq(&s, "k1", "v1") { ok = false; }
  if !put_ok(&mut s, "k2", "v2") { ok = false; }
  let rr2 = kv_reopen(&mut s);
  if !rr2.is_ok { ok = false; }
  if kv_count(&s) != 2 { ok = false; }
  if !get_eq(&s, "k1", "v1") { ok = false; }
  if !get_eq(&s, "k2", "v2") { ok = false; }
  return finish(ok, name, dir, prefix);
}

fn t10_crc_newest(dir: Str) -> TestResult {
  let name = "CRC corruption in the newest segment is dropped with a fresh segment";
  let prefix = run_prefix("t10");
  let r = kv_open(dir, prefix, 64);
  if !r.is_ok { return finish(false, name, dir, prefix); }
  var s = r.value;
  var ok = true;
  if !put_ok(&mut s, "a", "1") { ok = false; }
  if !put_ok(&mut s, "b", "2") { ok = false; }
  if !put_ok(&mut s, "c", "3") { ok = false; }
  if s.seg_id != 2 { ok = false; }
  let raw = tf_read(dir, seg_name(prefix, 2));
  if raw.len() < 46 {
    ok = false;
  } else {
    let flipped = flip_byte(&raw, 45);
    if !tf_write(dir, seg_name(prefix, 2), &flipped) { ok = false; }
  }
  let rr = kv_reopen(&mut s);
  if !rr.is_ok { ok = false; }
  if kv_count(&s) != 2 { ok = false; }
  if !get_eq(&s, "a", "1") { ok = false; }
  if !get_eq(&s, "b", "2") { ok = false; }
  if !get_none(&s, "c") { ok = false; }
  if s.seg_id != 3 { ok = false; }
  if tf_size(dir, seg_name(prefix, 2)) != 28 { ok = false; }
  if tf_size(dir, seg_name(prefix, 3)) != 28 { ok = false; }
  if !put_ok(&mut s, "d", "4") { ok = false; }
  let rr2 = kv_reopen(&mut s);
  if !rr2.is_ok { ok = false; }
  if kv_count(&s) != 3 { ok = false; }
  if !get_eq(&s, "d", "4") { ok = false; }
  return finish(ok, name, dir, prefix);
}

fn t11_bad_header_newest(dir: Str) -> TestResult {
  let name = "bad header in the newest segment is abandoned and replaced";
  let prefix = run_prefix("t11");
  let r = kv_open(dir, prefix, 100000);
  if !r.is_ok { return finish(false, name, dir, prefix); }
  var s = r.value;
  var ok = true;
  if !put_ok(&mut s, "a", "1") { ok = false; }
  let raw = tf_read(dir, seg_name(prefix, 1));
  if raw.len() < 28 {
    ok = false;
  } else {
    let flipped = flip_byte(&raw, 0);
    if !tf_write(dir, seg_name(prefix, 1), &flipped) { ok = false; }
  }
  let rr = kv_reopen(&mut s);
  if !rr.is_ok { ok = false; }
  if kv_count(&s) != 0 { ok = false; }
  if s.seg_id != 2 { ok = false; }
  if io.file_exists(seg_path(dir, prefix, 1)) { ok = false; }
  if !io.file_exists(io.join_paths(dir, seg_name(prefix, 1) + ".bad")) { ok = false; }
  if !put_ok(&mut s, "b", "2") { ok = false; }
  let rr2 = kv_reopen(&mut s);
  if !rr2.is_ok { ok = false; }
  if kv_count(&s) != 1 { ok = false; }
  if !get_eq(&s, "b", "2") { ok = false; }
  return finish(ok, name, dir, prefix);
}

fn t12_corrupt_older(dir: Str) -> TestResult {
  let name = "corrupt record in an older segment is an error";
  let prefix = run_prefix("t12");
  let r = kv_open(dir, prefix, 64);
  if !r.is_ok { return finish(false, name, dir, prefix); }
  var s = r.value;
  var ok = true;
  if !put_ok(&mut s, "a", "1") { ok = false; }
  if !put_ok(&mut s, "b", "2") { ok = false; }
  if !put_ok(&mut s, "c", "3") { ok = false; }
  if !put_ok(&mut s, "d", "4") { ok = false; }
  if !put_ok(&mut s, "e", "5") { ok = false; }
  let raw = tf_read(dir, seg_name(prefix, 1));
  if raw.len() < 46 {
    ok = false;
  } else {
    let flipped = flip_byte(&raw, 45);
    if !tf_write(dir, seg_name(prefix, 1), &flipped) { ok = false; }
  }
  let rr = kv_reopen(&mut s);
  if rr.is_ok {
    ok = false;
  } else {
    if !string.str_starts_with(rr.error, "kv: corrupt record: ") { ok = false; }
  }
  return finish(ok, name, dir, prefix);
}

fn t13_bad_header_older(dir: Str) -> TestResult {
  let name = "bad header in an older segment is an error";
  let prefix = run_prefix("t13");
  let r = kv_open(dir, prefix, 64);
  if !r.is_ok { return finish(false, name, dir, prefix); }
  var s = r.value;
  var ok = true;
  if !put_ok(&mut s, "a", "1") { ok = false; }
  if !put_ok(&mut s, "b", "2") { ok = false; }
  if !put_ok(&mut s, "c", "3") { ok = false; }
  let raw = tf_read(dir, seg_name(prefix, 1));
  if raw.len() < 28 {
    ok = false;
  } else {
    let flipped = flip_byte(&raw, 1);
    if !tf_write(dir, seg_name(prefix, 1), &flipped) { ok = false; }
  }
  let rr = kv_reopen(&mut s);
  if rr.is_ok {
    ok = false;
  } else {
    if !string.str_starts_with(rr.error, "kv: corrupt segment header: ") { ok = false; }
  }
  return finish(ok, name, dir, prefix);
}

fn t14_compact_basic(dir: Str) -> TestResult {
  let name = "compaction keeps the 60 live entries and collapses to one segment";
  let prefix = run_prefix("t14");
  let r = kv_open(dir, prefix, 100000);
  if !r.is_ok { return finish(false, name, dir, prefix); }
  var s = r.value;
  var ok = true;
  var i = 0;
  while i < 100 {
    let key = "k" + pad10(i);
    let val = "v" + pad10(i);
    if !put_ok(&mut s, key, val) { ok = false; }
    i = i + 1;
  }
  i = 0;
  while i < 40 {
    let key = "k" + pad10(i);
    let d = kv_delete(&mut s, key);
    if !d.is_ok { ok = false; }
    i = i + 1;
  }
  let cr = kv_compact(&mut s);
  if !cr.is_ok { ok = false; }
  if kv_count(&s) != 60 { ok = false; }
  if count_segs(dir, prefix, 64) != 1 { ok = false; }
  let rr = kv_reopen(&mut s);
  if !rr.is_ok { ok = false; }
  if kv_count(&s) != 60 { ok = false; }
  if !get_eq(&s, "k" + pad10(40), "v" + pad10(40)) { ok = false; }
  if !get_eq(&s, "k" + pad10(99), "v" + pad10(99)) { ok = false; }
  if !get_none(&s, "k" + pad10(0)) { ok = false; }
  if !get_none(&s, "k" + pad10(39)) { ok = false; }
  let ks = kv_keys(&s);
  if ks.len() != 60 { ok = false; }
  if ks.len() == 60 {
    if !str_eq(ks[0], "k" + pad10(40)) { ok = false; }
    if !str_eq(ks[59], "k" + pad10(99)) { ok = false; }
  }
  return finish(ok, name, dir, prefix);
}

fn t15_compact_removes_olds(dir: Str) -> TestResult {
  let name = "compaction removes old segments and rewrites into id+1";
  let prefix = run_prefix("t15");
  let r = kv_open(dir, prefix, 100000);
  if !r.is_ok { return finish(false, name, dir, prefix); }
  var s = r.value;
  var ok = true;
  if !put_ok(&mut s, "a", "1") { ok = false; }
  if !put_ok(&mut s, "b", "2") { ok = false; }
  let cr = kv_compact(&mut s);
  if !cr.is_ok { ok = false; }
  if io.file_exists(seg_path(dir, prefix, 1)) { ok = false; }
  if !io.file_exists(seg_path(dir, prefix, 2)) { ok = false; }
  if s.seg_id != 2 { ok = false; }
  if !put_ok(&mut s, "c", "3") { ok = false; }
  let rr = kv_reopen(&mut s);
  if !rr.is_ok { ok = false; }
  if kv_count(&s) != 3 { ok = false; }
  if !get_eq(&s, "a", "1") { ok = false; }
  if !get_eq(&s, "c", "3") { ok = false; }
  return finish(ok, name, dir, prefix);
}

fn t16_stale_tmp(dir: Str) -> TestResult {
  let name = "stale tmp files are ignored on open and removed by compaction";
  let prefix = run_prefix("t16");
  let r = kv_open(dir, prefix, 100000);
  if !r.is_ok { return finish(false, name, dir, prefix); }
  var s = r.value;
  var ok = true;
  if !put_ok(&mut s, "a", "1") { ok = false; }
  var junk = Vec[UInt8].new();
  junk.push(9 as UInt8); junk.push(8 as UInt8); junk.push(7 as UInt8);
  if !tf_write(dir, seg_tmp_name(prefix, 2), &junk) { ok = false; }
  let rr = kv_reopen(&mut s);
  if !rr.is_ok { ok = false; }
  if kv_count(&s) != 1 { ok = false; }
  if !get_eq(&s, "a", "1") { ok = false; }
  let cr = kv_compact(&mut s);
  if !cr.is_ok { ok = false; }
  if io.file_exists(io.join_paths(dir, seg_tmp_name(prefix, 2))) { ok = false; }
  if !get_eq(&s, "a", "1") { ok = false; }
  return finish(ok, name, dir, prefix);
}

fn t17_rotation(dir: Str) -> TestResult {
  let name = "rotation spreads writes across segments and reopens last-write-wins";
  let prefix = run_prefix("t17");
  let r = kv_open(dir, prefix, 100);
  if !r.is_ok { return finish(false, name, dir, prefix); }
  var s = r.value;
  var ok = true;
  var i = 0;
  while i < 20 {
    if !put_ok(&mut s, "k" + pad10(i), "v" + pad10(i)) { ok = false; }
    i = i + 1;
  }
  let nseg = count_segs(dir, prefix, 32);
  if nseg <= 1 { ok = false; }
  let rr = kv_reopen(&mut s);
  if !rr.is_ok { ok = false; }
  if kv_count(&s) != 20 { ok = false; }
  i = 0;
  while i < 20 {
    if !get_eq(&s, "k" + pad10(i), "v" + pad10(i)) { ok = false; }
    i = i + 1;
  }
  if !put_ok(&mut s, "k" + pad10(0), "updated") { ok = false; }
  let rr2 = kv_reopen(&mut s);
  if !rr2.is_ok { ok = false; }
  if !get_eq(&s, "k" + pad10(0), "updated") { ok = false; }
  if kv_count(&s) != 20 { ok = false; }
  return finish(ok, name, dir, prefix);
}

fn t18_header_only_rotation(dir: Str) -> TestResult {
  let name = "rotation creates a header-only segment (28 bytes) for the next write";
  let prefix = run_prefix("t18");
  let r = kv_open(dir, prefix, 64);
  if !r.is_ok { return finish(false, name, dir, prefix); }
  var s = r.value;
  var ok = true;
  if !put_ok(&mut s, "a", "1") { ok = false; }
  if !put_ok(&mut s, "b", "2") { ok = false; }
  if s.seg_id != 2 { ok = false; }
  if tf_size(dir, seg_name(prefix, 2)) != 28 { ok = false; }
  if !put_ok(&mut s, "c", "3") { ok = false; }
  if tf_size(dir, seg_name(prefix, 2)) <= 28 { ok = false; }
  let rr = kv_reopen(&mut s);
  if !rr.is_ok { ok = false; }
  if kv_count(&s) != 3 { ok = false; }
  return finish(ok, name, dir, prefix);
}

fn t19_snapshot(dir: Str) -> TestResult {
  let name = "snapshot writes snapshot.kv and reopens from it";
  let prefix = run_prefix("t19");
  let r = kv_open(dir, prefix, 100000);
  if !r.is_ok { return finish(false, name, dir, prefix); }
  var s = r.value;
  var ok = true;
  var i = 0;
  while i < 30 {
    if !put_ok(&mut s, "k" + pad10(i), "v" + pad10(i)) { ok = false; }
    i = i + 1;
  }
  i = 0;
  while i < 5 {
    let _ = kv_delete(&mut s, "k" + pad10(i));
    i = i + 1;
  }
  let sr = kv_snapshot(&mut s);
  if !sr.is_ok { ok = false; }
  if !io.file_exists(snap_path(dir, prefix)) { ok = false; }
  let rr = kv_reopen(&mut s);
  if !rr.is_ok { ok = false; }
  if kv_count(&s) != 25 { ok = false; }
  if !get_eq(&s, "k" + pad10(5), "v" + pad10(5)) { ok = false; }
  if !get_eq(&s, "k" + pad10(29), "v" + pad10(29)) { ok = false; }
  if !get_none(&s, "k" + pad10(0)) { ok = false; }
  return finish(ok, name, dir, prefix);
}

fn t20_snapshot_corrupt(dir: Str) -> TestResult {
  let name = "a corrupt snapshot is ignored and segments remain authoritative";
  let prefix = run_prefix("t20");
  let r = kv_open(dir, prefix, 100000);
  if !r.is_ok { return finish(false, name, dir, prefix); }
  var s = r.value;
  var ok = true;
  var i = 0;
  while i < 10 {
    if !put_ok(&mut s, "k" + pad10(i), "v" + pad10(i)) { ok = false; }
    i = i + 1;
  }
  let sr = kv_snapshot(&mut s);
  if !sr.is_ok { ok = false; }
  let raw = tf_read(dir, prefix + "snapshot.kv");
  if raw.len() < 28 {
    ok = false;
  } else {
    let flipped = flip_byte(&raw, 0);
    if !tf_write(dir, prefix + "snapshot.kv", &flipped) { ok = false; }
  }
  let rr = kv_reopen(&mut s);
  if !rr.is_ok { ok = false; }
  if kv_count(&s) != 10 { ok = false; }
  if !get_eq(&s, "k" + pad10(9), "v" + pad10(9)) { ok = false; }
  return finish(ok, name, dir, prefix);
}

fn t21_snapshot_replay(dir: Str) -> TestResult {
  let name = "reopen replays records written after the snapshot";
  let prefix = run_prefix("t21");
  let r = kv_open(dir, prefix, 100000);
  if !r.is_ok { return finish(false, name, dir, prefix); }
  var s = r.value;
  var ok = true;
  if !put_ok(&mut s, "a", "1") { ok = false; }
  if !put_ok(&mut s, "b", "2") { ok = false; }
  let sr = kv_snapshot(&mut s);
  if !sr.is_ok { ok = false; }
  if !put_ok(&mut s, "a", "9") { ok = false; }
  if !put_ok(&mut s, "c", "3") { ok = false; }
  let _ = kv_delete(&mut s, "b");
  let rr = kv_reopen(&mut s);
  if !rr.is_ok { ok = false; }
  if kv_count(&s) != 2 { ok = false; }
  if !get_eq(&s, "a", "9") { ok = false; }
  if !get_eq(&s, "c", "3") { ok = false; }
  if !get_none(&s, "b") { ok = false; }
  return finish(ok, name, dir, prefix);
}

fn t22_snapshot_compact(dir: Str) -> TestResult {
  let name = "compaction after a snapshot removes it and keeps the live set";
  let prefix = run_prefix("t22");
  let r = kv_open(dir, prefix, 100000);
  if !r.is_ok { return finish(false, name, dir, prefix); }
  var s = r.value;
  var ok = true;
  var i = 0;
  while i < 10 {
    if !put_ok(&mut s, "k" + pad10(i), "v" + pad10(i)) { ok = false; }
    i = i + 1;
  }
  let sr = kv_snapshot(&mut s);
  if !sr.is_ok { ok = false; }
  let _ = kv_delete(&mut s, "k" + pad10(0));
  let _ = kv_delete(&mut s, "k" + pad10(1));
  let cr = kv_compact(&mut s);
  if !cr.is_ok { ok = false; }
  if io.file_exists(snap_path(dir, prefix)) { ok = false; }
  if count_segs(dir, prefix, 64) != 1 { ok = false; }
  if kv_count(&s) != 8 { ok = false; }
  let rr = kv_reopen(&mut s);
  if !rr.is_ok { ok = false; }
  if kv_count(&s) != 8 { ok = false; }
  if !get_eq(&s, "k" + pad10(9), "v" + pad10(9)) { ok = false; }
  if !get_none(&s, "k" + pad10(0)) { ok = false; }
  return finish(ok, name, dir, prefix);
}

fn t23_determinism(dir: Str) -> TestResult {
  let name = "identical operations in two stores yield identical state";
  let prefix1 = run_prefix("t23a");
  let prefix2 = run_prefix("t23b");
  let r1 = kv_open(dir, prefix1, 128);
  let r2 = kv_open(dir, prefix2, 128);
  if !r1.is_ok || !r2.is_ok {
    return finish(false, name, dir, prefix1);
  }
  var a = r1.value;
  var b = r2.value;
  var ok = true;
  var i = 0;
  while i < 20 {
    let key = "k" + pad10(i);
    let val = "v" + pad10(i * 3);
    if !put_ok(&mut a, key, val) { ok = false; }
    if !put_ok(&mut b, key, val) { ok = false; }
    i = i + 1;
  }
  i = 0;
  while i < 5 {
    let key = "k" + pad10(i);
    let _ = kv_delete(&mut a, key);
    let _ = kv_delete(&mut b, key);
    i = i + 1;
  }
  i = 10;
  while i < 13 {
    let key = "k" + pad10(i);
    let val = "over" + pad10(i);
    let _ = kv_put(&mut a, key, val);
    let _ = kv_put(&mut b, key, val);
    i = i + 1;
  }
  let rr1 = kv_reopen(&mut a);
  let rr2 = kv_reopen(&mut b);
  if !rr1.is_ok || !rr2.is_ok { ok = false; }
  if kv_count(&a) != kv_count(&b) { ok = false; }
  let ka = kv_keys(&a);
  let kb = kv_keys(&b);
  if ka.len() != kb.len() { ok = false; } else {
    i = 0;
    while i < ka.len() {
      if !str_eq(ka[i], kb[i]) { ok = false; }
      let va = kv_get(&a, ka[i]);
      let vb = kv_get(&b, kb[i]);
      if !va.is_ok || !vb.is_ok {
        ok = false;
      } else {
        let oa = va.value;
        let ob = vb.value;
        if oa.is_some != ob.is_some {
          ok = false;
        } else {
          match oa {
            Some(sa) => {
              match ob {
                Some(sb) => { if !str_eq(sa, sb) { ok = false; } },
                None => { ok = false; },
              }
            },
            None => {},
          }
        }
      }
      i = i + 1;
    }
  }
  let g1 = kv_get(&a, "k" + pad10(10));
  let g2 = kv_get(&b, "k" + pad10(10));
  if !g1.is_ok || !g2.is_ok { ok = false; } else {
    let o1 = g1.value;
    let o2 = g2.value;
    match o1 {
      Some(v1) => {
        match o2 {
          Some(v2) => { if !str_eq(v1, v2) { ok = false; } },
          None => { ok = false; },
        }
      },
      None => { ok = false; },
    }
  }
  clean_prefix(dir, prefix1);
  return finish(ok, name, dir, prefix2);
}

fn t24_key_limits(dir: Str) -> TestResult {
  let name = "empty and oversized keys are rejected with kv errors";
  let prefix = run_prefix("t24");
  let r = kv_open(dir, prefix, 100000);
  if !r.is_ok { return finish(false, name, dir, prefix); }
  var s = r.value;
  var ok = true;
  let e1 = kv_put(&mut s, "", "v");
  if e1.is_ok {
    ok = false;
  } else {
    if !str_eq(e1.error, "kv: empty key") { ok = false; }
  }
  let big = string.str_repeat("k", 4097);
  let e2 = kv_put(&mut s, big, "v");
  if e2.is_ok {
    ok = false;
  } else {
    if !str_eq(e2.error, "kv: key too large") { ok = false; }
  }
  let e3 = kv_delete(&mut s, "");
  if e3.is_ok { ok = false; }
  if kv_count(&s) != 0 { ok = false; }
  return finish(ok, name, dir, prefix);
}

fn t25_open_errors(dir: Str) -> TestResult {
  let name = "open validates dir and seg_max with kv errors";
  let prefix = run_prefix("t25");
  var ok = true;
  let missing = dir + "/xiomkv-no-such-dir-" + pad10(io.time_now());
  let e1 = kv_open(missing, prefix, 1000);
  if e1.is_ok {
    ok = false;
  } else {
    if !string.str_starts_with(e1.error, "kv: directory not found: ") { ok = false; }
  }
  let e2 = kv_open(dir, prefix, 8);
  if e2.is_ok {
    ok = false;
  } else {
    if !str_eq(e2.error, "kv: seg_max too small") { ok = false; }
  }
  let e3 = kv_open("", prefix, 1000);
  if e3.is_ok {
    ok = false;
  } else {
    if !str_eq(e3.error, "kv: empty directory") { ok = false; }
  }
  return finish(ok, name, dir, prefix);
}

fn t26_close_noop(dir: Str) -> TestResult {
  let name = "kv_close is a no-op and the store remains usable";
  let prefix = run_prefix("t26");
  let r = kv_open(dir, prefix, 100000);
  if !r.is_ok { return finish(false, name, dir, prefix); }
  var s = r.value;
  var ok = true;
  if !put_ok(&mut s, "a", "1") { ok = false; }
  kv_close(&mut s);
  if !get_eq(&s, "a", "1") { ok = false; }
  if !put_ok(&mut s, "b", "2") { ok = false; }
  let rr = kv_reopen(&mut s);
  if !rr.is_ok { ok = false; }
  if kv_count(&s) != 2 { ok = false; }
  return finish(ok, name, dir, prefix);
}

fn t27_short_read(dir: Str) -> TestResult {
  let name = "external truncation of a value is reported as kv: short read";
  let prefix = run_prefix("t27");
  let r = kv_open(dir, prefix, 100000);
  if !r.is_ok { return finish(false, name, dir, prefix); }
  var s = r.value;
  var ok = true;
  if !put_ok(&mut s, "sk", "hello") { ok = false; }
  let raw = tf_read(dir, seg_name(prefix, 1));
  var keep = Vec[UInt8].new();
  let keep_len = 28 + 16 + 2 + 2;
  if raw.len() < keep_len {
    ok = false;
  } else {
    var i = 0;
    while i < keep_len {
      keep.push(raw[i]);
      i = i + 1;
    }
    if !tf_write(dir, seg_name(prefix, 1), &keep) { ok = false; }
  }
  let gr = kv_get(&s, "sk");
  if gr.is_ok {
    ok = false;
  } else {
    if !str_eq(gr.error, "kv: short read") { ok = false; }
  }
  return finish(ok, name, dir, prefix);
}

fn t28_keys_copy(dir: Str) -> TestResult {
  let name = "kv_keys returns a fresh vector independent of the store";
  let prefix = run_prefix("t28");
  let r = kv_open(dir, prefix, 100000);
  if !r.is_ok { return finish(false, name, dir, prefix); }
  var s = r.value;
  var ok = true;
  if !put_ok(&mut s, "x", "1") { ok = false; }
  if !put_ok(&mut s, "y", "2") { ok = false; }
  var ks = kv_keys(&s);
  ks.push("zz");
  if ks.len() != 3 { ok = false; }
  let again = kv_keys(&s);
  if again.len() != 2 { ok = false; }
  return finish(ok, name, dir, prefix);
}

fn main() -> Int {
  let dir = fs.fs_temp_dir();
  io.println("=== xiom.kv conformance tests ===");
  var failed: Int = 0;

  let r1 = t1_open_header(dir);
  if r1.passed { io.println("  [PASS] " + r1.name); } else { io.println("  [FAIL] " + r1.name); failed = failed + 1; }
  let r2 = t2_put_get(dir);
  if r2.passed { io.println("  [PASS] " + r2.name); } else { io.println("  [FAIL] " + r2.name); failed = failed + 1; }
  let r3 = t3_overwrite(dir);
  if r3.passed { io.println("  [PASS] " + r3.name); } else { io.println("  [FAIL] " + r3.name); failed = failed + 1; }
  let r4 = t4_delete(dir);
  if r4.passed { io.println("  [PASS] " + r4.name); } else { io.println("  [FAIL] " + r4.name); failed = failed + 1; }
  let r5 = t5_keys_order(dir);
  if r5.passed { io.println("  [PASS] " + r5.name); } else { io.println("  [FAIL] " + r5.name); failed = failed + 1; }
  let r6 = t6_reopen(dir);
  if r6.passed { io.println("  [PASS] " + r6.name); } else { io.println("  [FAIL] " + r6.name); failed = failed + 1; }
  let r7 = t7_bytes(dir);
  if r7.passed { io.println("  [PASS] " + r7.name); } else { io.println("  [FAIL] " + r7.name); failed = failed + 1; }
  let r8 = t8_torn_tail(dir);
  if r8.passed { io.println("  [PASS] " + r8.name); } else { io.println("  [FAIL] " + r8.name); failed = failed + 1; }
  let r9 = t9_torn_no_fuse(dir);
  if r9.passed { io.println("  [PASS] " + r9.name); } else { io.println("  [FAIL] " + r9.name); failed = failed + 1; }
  let r10 = t10_crc_newest(dir);
  if r10.passed { io.println("  [PASS] " + r10.name); } else { io.println("  [FAIL] " + r10.name); failed = failed + 1; }
  let r11 = t11_bad_header_newest(dir);
  if r11.passed { io.println("  [PASS] " + r11.name); } else { io.println("  [FAIL] " + r11.name); failed = failed + 1; }
  let r12 = t12_corrupt_older(dir);
  if r12.passed { io.println("  [PASS] " + r12.name); } else { io.println("  [FAIL] " + r12.name); failed = failed + 1; }
  let r13 = t13_bad_header_older(dir);
  if r13.passed { io.println("  [PASS] " + r13.name); } else { io.println("  [FAIL] " + r13.name); failed = failed + 1; }
  let r14 = t14_compact_basic(dir);
  if r14.passed { io.println("  [PASS] " + r14.name); } else { io.println("  [FAIL] " + r14.name); failed = failed + 1; }
  let r15 = t15_compact_removes_olds(dir);
  if r15.passed { io.println("  [PASS] " + r15.name); } else { io.println("  [FAIL] " + r15.name); failed = failed + 1; }
  let r16 = t16_stale_tmp(dir);
  if r16.passed { io.println("  [PASS] " + r16.name); } else { io.println("  [FAIL] " + r16.name); failed = failed + 1; }
  let r17 = t17_rotation(dir);
  if r17.passed { io.println("  [PASS] " + r17.name); } else { io.println("  [FAIL] " + r17.name); failed = failed + 1; }
  let r18 = t18_header_only_rotation(dir);
  if r18.passed { io.println("  [PASS] " + r18.name); } else { io.println("  [FAIL] " + r18.name); failed = failed + 1; }
  let r19 = t19_snapshot(dir);
  if r19.passed { io.println("  [PASS] " + r19.name); } else { io.println("  [FAIL] " + r19.name); failed = failed + 1; }
  let r20 = t20_snapshot_corrupt(dir);
  if r20.passed { io.println("  [PASS] " + r20.name); } else { io.println("  [FAIL] " + r20.name); failed = failed + 1; }
  let r21 = t21_snapshot_replay(dir);
  if r21.passed { io.println("  [PASS] " + r21.name); } else { io.println("  [FAIL] " + r21.name); failed = failed + 1; }
  let r22 = t22_snapshot_compact(dir);
  if r22.passed { io.println("  [PASS] " + r22.name); } else { io.println("  [FAIL] " + r22.name); failed = failed + 1; }
  let r23 = t23_determinism(dir);
  if r23.passed { io.println("  [PASS] " + r23.name); } else { io.println("  [FAIL] " + r23.name); failed = failed + 1; }
  let r24 = t24_key_limits(dir);
  if r24.passed { io.println("  [PASS] " + r24.name); } else { io.println("  [FAIL] " + r24.name); failed = failed + 1; }
  let r25 = t25_open_errors(dir);
  if r25.passed { io.println("  [PASS] " + r25.name); } else { io.println("  [FAIL] " + r25.name); failed = failed + 1; }
  let r26 = t26_close_noop(dir);
  if r26.passed { io.println("  [PASS] " + r26.name); } else { io.println("  [FAIL] " + r26.name); failed = failed + 1; }
  let r27 = t27_short_read(dir);
  if r27.passed { io.println("  [PASS] " + r27.name); } else { io.println("  [FAIL] " + r27.name); failed = failed + 1; }
  let r28 = t28_keys_copy(dir);
  if r28.passed { io.println("  [PASS] " + r28.name); } else { io.println("  [FAIL] " + r28.name); failed = failed + 1; }

  if failed == 0 {
    io.println("xiom.kv: all tests passed");
  } else {
    io.println("xiom.kv: tests failed");
  }
  return failed;
}
