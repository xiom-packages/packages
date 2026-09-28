// XIOM -- xiom.parquet conformance tests
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API over synthetic Parquet files and raw
// compact-protocol buffers built in this file:
//   * the compact protocol field matrix (short/long field headers, bool in
//     the header nibble, list/set/map headers, varint/zigzag, doubles,
//     strings and their validation errors, skip and the nesting cap);
//   * a full FileMetaData fixture (schema tree with computed paths and
//     levels, one row group, two column chunks with metadata, statistics
//     raw bytes, encoding stats, sorting columns, key/value metadata,
//     created_by and column orders);
//   * every PageHeader variant with consumed counts and raw statistics
//     ranges;
//   * malformed magic, footer length, truncation, trailing data, oversized
//     collections, unknown enums (preserved raw) and schema-tree errors.
//
// Harness style mirrors xiom.orc: one fn tN() -> Int per test, called
// directly from main; each test prints exactly one [PASS]/[FAIL] line and
// returns 0/1. Str values are compared with str_compare.

module parquet_tests
use xiom.io; use xiom.test;
use xiom.string; use xiom.string.compare;
use xiom.convert;
use xiom.parquet;

// --------------------------------------------------
//  Harness helpers
// --------------------------------------------------

fn report(passed: Bool, name: Str) -> Int {
  if passed {
    io.println("  [PASS] " + name);
    return 0;
  }
  io.println("  [FAIL] " + name);
  return 1;
}

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn bytes_eq(a: &Vec[UInt8], b: &Vec[UInt8]) -> Bool {
  if a.len() != b.len() {
    return false;
  }
  var i = 0;
  while i < a.len() {
    let x: UInt8 = a[i];
    let y: UInt8 = b[i];
    if x != y {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn int_is(r: Result[Int, Str], want: Int) -> Bool {
  if !r.is_ok {
    return false;
  }
  return r.value == want;
}

fn str_is(r: Result[Str, Str], want: Str) -> Bool {
  if !r.is_ok {
    return false;
  }
  return str_eq(r.value, want);
}

fn bool_is(r: Result[Bool, Str], want: Bool) -> Bool {
  if !r.is_ok {
    return false;
  }
  if r.value == want {
    return true;
  }
  return false;
}

fn bytes_is(r: Result[Vec[UInt8], Str], want: &Vec[UInt8]) -> Bool {
  if !r.is_ok {
    return false;
  }
  let got: Vec[UInt8] = r.value;
  return bytes_eq(&got, want);
}

fn expect_file_err(r: Result[ParquetFile, Str], want: Str, name: Str) -> Int {
  if r.is_ok {
    return report(false, name + " (expected Err)");
  }
  if !str_eq(r.error, want) {
    return report(false, name + " (got: " + r.error + ")");
  }
  return report(true, name);
}

fn expect_int_err(r: Result[Int, Str], want: Str, name: Str) -> Int {
  if r.is_ok {
    return report(false, name + " (expected Err)");
  }
  if !str_eq(r.error, want) {
    return report(false, name + " (got: " + r.error + ")");
  }
  return report(true, name);
}

fn expect_str_err(r: Result[Str, Str], want: Str, name: Str) -> Int {
  if r.is_ok {
    return report(false, name + " (expected Err)");
  }
  if !str_eq(r.error, want) {
    return report(false, name + " (got: " + r.error + ")");
  }
  return report(true, name);
}

fn expect_bytes_err(r: Result[Vec[UInt8], Str], want: Str, name: Str) -> Int {
  if r.is_ok {
    return report(false, name + " (expected Err)");
  }
  if !str_eq(r.error, want) {
    return report(false, name + " (got: " + r.error + ")");
  }
  return report(true, name);
}

fn expect_bool_err(r: Result[Bool, Str], want: Str, name: Str) -> Int {
  if r.is_ok {
    return report(false, name + " (expected Err)");
  }
  if !str_eq(r.error, want) {
    return report(false, name + " (got: " + r.error + ")");
  }
  return report(true, name);
}

fn expect_ph_err(r: Result[ParquetPageHeader, Str], want: Str, name: Str) -> Int {
  if r.is_ok {
    return report(false, name + " (expected Err)");
  }
  if !str_eq(r.error, want) {
    return report(false, name + " (got: " + r.error + ")");
  }
  return report(true, name);
}

// --------------------------------------------------
//  Byte-building helpers
// --------------------------------------------------

fn push_u8(out: &mut Vec[UInt8], v: Int) {
  var q = v % 256;
  if q < 0 {
    q = q + 256;
  }
  out.push((q as UInt8));
}

fn push_bytes(out: &mut Vec[UInt8], src: &Vec[UInt8]) {
  var i = 0;
  while i < src.len() {
    let b: UInt8 = src[i];
    out.push(b);
    i = i + 1;
  }
}

fn bytes_of(s: Str) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  let n = string.str_len(s);
  var i = 0;
  while i < n {
    let b: UInt8 = string.byte_at(s, i);
    out.push(b);
    i = i + 1;
  }
  return out;
}

fn vb1(a: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_u8(&mut v, a);
  return v;
}

fn vb2(a: Int, b: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_u8(&mut v, a);
  push_u8(&mut v, b);
  return v;
}

fn vb4(a: Int, b: Int, c: Int, d: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_u8(&mut v, a);
  push_u8(&mut v, b);
  push_u8(&mut v, c);
  push_u8(&mut v, d);
  return v;
}

fn zeros(n: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < n {
    v.push((0 as UInt8));
    i = i + 1;
  }
  return v;
}

fn slice(buf: &Vec[UInt8], off: Int, n: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < n {
    let b: UInt8 = buf[off + i];
    out.push(b);
    i = i + 1;
  }
  return out;
}

// Base-128 varint for a non-negative value.
fn enc_varint(out: &mut Vec[UInt8], v: Int) {
  var q = v;
  var done = false;
  while !done {
    let b = q % 128;
    q = q / 128;
    if q > 0 {
      out.push(((b + 128) as UInt8));
    } else {
      out.push((b as UInt8));
      done = true;
    }
  }
}

// Zigzag + varint for a signed value (the encoder side of the codec).
fn enc_zigzag(out: &mut Vec[UInt8], v: Int) {
  if v >= 0 {
    enc_varint(out, v * 2);
  } else {
    enc_varint(out, (0 - v) * 2 - 1);
  }
}

fn enc_u32le(out: &mut Vec[UInt8], v: Int) {
  push_u8(out, v % 256);
  push_u8(out, (v / 256) % 256);
  push_u8(out, (v / 65536) % 256);
  push_u8(out, (v / 16777216) % 256);
}

// One compact field header, returning the new "last field id". Deltas of
// 1..15 use the short form; anything else the long form (type nibble 0 +
// zigzag field id).
fn field(out: &mut Vec[UInt8], last: Int, fid: Int, ctype: Int) -> Int {
  let delta = fid - last;
  if delta >= 1 && delta <= 15 {
    out.push(((delta * 16 + ctype) as UInt8));
  } else {
    out.push((ctype as UInt8));
    enc_zigzag(out, fid);
  }
  return fid;
}

fn field_i32(out: &mut Vec[UInt8], last: Int, fid: Int, v: Int) -> Int {
  let nl = field(out, last, fid, parquet_compact_i32());
  enc_zigzag(out, v);
  return nl;
}

fn field_i64(out: &mut Vec[UInt8], last: Int, fid: Int, v: Int) -> Int {
  let nl = field(out, last, fid, parquet_compact_i64());
  enc_zigzag(out, v);
  return nl;
}

fn field_i16(out: &mut Vec[UInt8], last: Int, fid: Int, v: Int) -> Int {
  let nl = field(out, last, fid, parquet_compact_i16());
  enc_zigzag(out, v);
  return nl;
}

fn field_bool(out: &mut Vec[UInt8], last: Int, fid: Int, v: Bool) -> Int {
  if v {
    return field(out, last, fid, parquet_compact_bool_true());
  }
  return field(out, last, fid, parquet_compact_bool_false());
}

fn field_bin(out: &mut Vec[UInt8], last: Int, fid: Int, data: &Vec[UInt8]) -> Int {
  let nl = field(out, last, fid, parquet_compact_binary());
  enc_varint(out, data.len());
  push_bytes(out, data);
  return nl;
}

fn field_str(out: &mut Vec[UInt8], last: Int, fid: Int, s: Str) -> Int {
  let data = bytes_of(s);
  return field_bin(out, last, fid, &data);
}

fn field_struct(out: &mut Vec[UInt8], last: Int, fid: Int, payload: &Vec[UInt8]) -> Int {
  let nl = field(out, last, fid, parquet_compact_struct());
  push_bytes(out, payload);
  return nl;
}

fn stop(out: &mut Vec[UInt8]) {
  out.push((0 as UInt8));
}

fn list_header(out: &mut Vec[UInt8], etype: Int, size: Int) {
  if size <= 14 {
    out.push(((size * 16 + etype) as UInt8));
  } else {
    out.push(((240 + etype) as UInt8));
    enc_varint(out, size);
  }
}

fn list_field(out: &mut Vec[UInt8], last: Int, fid: Int, etype: Int, size: Int) -> Int {
  let nl = field(out, last, fid, parquet_compact_list());
  list_header(out, etype, size);
  return nl;
}

fn i32_list_field(out: &mut Vec[UInt8], last: Int, fid: Int, vals: &Vec[Int]) -> Int {
  let nl = field(out, last, fid, parquet_compact_list());
  list_header(out, parquet_compact_i32(), vals.len());
  var i = 0;
  while i < vals.len() {
    let v: Int = vals[i];
    enc_zigzag(out, v);
    i = i + 1;
  }
  return nl;
}

fn str_list_field(out: &mut Vec[UInt8], last: Int, fid: Int, vals: &Vec[Str]) -> Int {
  let nl = field(out, last, fid, parquet_compact_list());
  list_header(out, parquet_compact_binary(), vals.len());
  var i = 0;
  while i < vals.len() {
    let s: Str = vals[i];
    let data = bytes_of(s);
    enc_varint(out, data.len());
    push_bytes(out, &data);
    i = i + 1;
  }
  return nl;
}

fn v_int(a: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  return v;
}

fn v_int2(a: Int, b: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  return v;
}

fn v_str2(a: Str, b: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  v.push(b);
  return v;
}

// --------------------------------------------------
//  Parquet fixture builders
// --------------------------------------------------

// Assemble magic + body + metadata + u32le metadata length + magic.
fn wrap(meta: &Vec[UInt8], body_len: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  push_u8(&mut out, 80);
  push_u8(&mut out, 65);
  push_u8(&mut out, 82);
  push_u8(&mut out, 49);
  var i = 0;
  while i < body_len {
    out.push((0 as UInt8));
    i = i + 1;
  }
  push_bytes(&mut out, meta);
  enc_u32le(&mut out, meta.len());
  push_u8(&mut out, 80);
  push_u8(&mut out, 65);
  push_u8(&mut out, 82);
  push_u8(&mut out, 49);
  return out;
}

fn empty_struct() -> Vec[UInt8] {
  var e = Vec[UInt8].new();
  stop(&mut e);
  return e;
}

fn schema_root(name: Str, nchildren: Int) -> Vec[UInt8] {
  var e = Vec[UInt8].new();
  var last = 0;
  last = field_str(&mut e, last, 4, name);
  last = field_i32(&mut e, last, 5, nchildren);
  stop(&mut e);
  return e;
}

fn schema_group(name: Str, nchildren: Int, rep: Int) -> Vec[UInt8] {
  var e = Vec[UInt8].new();
  var last = 0;
  last = field_i32(&mut e, last, 3, rep);
  last = field_str(&mut e, last, 4, name);
  last = field_i32(&mut e, last, 5, nchildren);
  stop(&mut e);
  return e;
}

fn schema_leaf(typ: Int, rep: Int, name: Str) -> Vec[UInt8] {
  var e = Vec[UInt8].new();
  var last = 0;
  last = field_i32(&mut e, last, 1, typ);
  last = field_i32(&mut e, last, 3, rep);
  last = field_str(&mut e, last, 4, name);
  stop(&mut e);
  return e;
}

fn schema_leaf_logical(typ: Int, rep: Int, name: Str, logical: Int) -> Vec[UInt8] {
  var e = Vec[UInt8].new();
  var last = 0;
  last = field_i32(&mut e, last, 1, typ);
  last = field_i32(&mut e, last, 3, rep);
  last = field_str(&mut e, last, 4, name);
  let lt = logical_type(logical);
  last = field_struct(&mut e, last, 10, &lt);
  stop(&mut e);
  return e;
}

fn logical_type(member: Int) -> Vec[UInt8] {
  var t = Vec[UInt8].new();
  var last = 0;
  let empty = empty_struct();
  last = field_struct(&mut t, last, member, &empty);
  stop(&mut t);
  return t;
}

fn kv(key: Str, value: Str) -> Vec[UInt8] {
  var e = Vec[UInt8].new();
  var last = 0;
  last = field_str(&mut e, last, 1, key);
  last = field_str(&mut e, last, 2, value);
  stop(&mut e);
  return e;
}

fn kv_novalue(key: Str) -> Vec[UInt8] {
  var e = Vec[UInt8].new();
  var last = 0;
  last = field_str(&mut e, last, 1, key);
  stop(&mut e);
  return e;
}

fn column_order(member: Int) -> Vec[UInt8] {
  var e = Vec[UInt8].new();
  var last = 0;
  let empty = empty_struct();
  last = field_struct(&mut e, last, member, &empty);
  stop(&mut e);
  return e;
}

fn sorting_column() -> Vec[UInt8] {
  var e = Vec[UInt8].new();
  var last = 0;
  last = field_i32(&mut e, last, 1, 0);
  last = field_bool(&mut e, last, 2, false);
  last = field_bool(&mut e, last, 3, true);
  stop(&mut e);
  return e;
}

fn statistics_id() -> Vec[UInt8] {
  var s = Vec[UInt8].new();
  var last = 0;
  let four = vb4(0, 0, 0, 10);
  last = field_bin(&mut s, last, 1, &four);
  let one = vb4(0, 0, 0, 1);
  last = field_bin(&mut s, last, 2, &one);
  last = field_i64(&mut s, last, 3, 0);
  last = field_i64(&mut s, last, 4, 10);
  let four2 = vb4(0, 0, 0, 10);
  last = field_bin(&mut s, last, 5, &four2);
  let one2 = vb4(0, 0, 0, 1);
  last = field_bin(&mut s, last, 6, &one2);
  last = field_bool(&mut s, last, 7, true);
  last = field_bool(&mut s, last, 8, true);
  stop(&mut s);
  return s;
}

fn encoding_stats_entry() -> Vec[UInt8] {
  var s = Vec[UInt8].new();
  var last = 0;
  last = field_i32(&mut s, last, 1, 0);
  last = field_i32(&mut s, last, 2, 0);
  last = field_i32(&mut s, last, 3, 1);
  stop(&mut s);
  return s;
}

fn column_meta_id() -> Vec[UInt8] {
  var m = Vec[UInt8].new();
  var last = 0;
  last = field_i32(&mut m, last, 1, 1);
  let encs = v_int2(0, 3);
  last = i32_list_field(&mut m, last, 2, &encs);
  let path = v_str2("g", "id");
  last = str_list_field(&mut m, last, 3, &path);
  last = field_i32(&mut m, last, 4, 0);
  last = field_i64(&mut m, last, 5, 10);
  last = field_i64(&mut m, last, 6, 100);
  last = field_i64(&mut m, last, 7, 90);
  last = field_i64(&mut m, last, 9, 4);
  last = field_i64(&mut m, last, 11, 20);
  let st = statistics_id();
  last = field_struct(&mut m, last, 12, &st);
  let es = encoding_stats_entry();
  last = list_field(&mut m, last, 13, parquet_compact_struct(), 1);
  push_bytes(&mut m, &es);
  stop(&mut m);
  return m;
}

fn column_meta_name() -> Vec[UInt8] {
  var m = Vec[UInt8].new();
  var last = 0;
  last = field_i32(&mut m, last, 1, 6);
  let encs = v_int(0);
  last = i32_list_field(&mut m, last, 2, &encs);
  let path = v_str2("g", "name");
  last = str_list_field(&mut m, last, 3, &path);
  last = field_i32(&mut m, last, 4, 1);
  last = field_i64(&mut m, last, 5, 10);
  last = field_i64(&mut m, last, 6, 120);
  last = field_i64(&mut m, last, 7, 110);
  last = field_i64(&mut m, last, 9, 300);
  stop(&mut m);
  return m;
}

fn column_chunk_id() -> Vec[UInt8] {
  var c = Vec[UInt8].new();
  var last = 0;
  last = field_i64(&mut c, last, 2, 4);
  let meta = column_meta_id();
  last = field_struct(&mut c, last, 3, &meta);
  last = field_i64(&mut c, last, 4, 500);
  last = field_i64(&mut c, last, 6, 600);
  stop(&mut c);
  return c;
}

fn column_chunk_name() -> Vec[UInt8] {
  var c = Vec[UInt8].new();
  var last = 0;
  last = field_str(&mut c, last, 1, "part-0.parquet");
  last = field_i64(&mut c, last, 2, 300);
  let meta = column_meta_name();
  last = field_struct(&mut c, last, 3, &meta);
  last = field_i32(&mut c, last, 5, 64);
  last = field_i32(&mut c, last, 7, 32);
  stop(&mut c);
  return c;
}

fn row_group_sample() -> Vec[UInt8] {
  var g = Vec[UInt8].new();
  var last = 0;
  last = list_field(&mut g, last, 1, parquet_compact_struct(), 2);
  let c0 = column_chunk_id();
  push_bytes(&mut g, &c0);
  let c1 = column_chunk_name();
  push_bytes(&mut g, &c1);
  last = field_i64(&mut g, last, 2, 200);
  last = field_i64(&mut g, last, 3, 10);
  last = list_field(&mut g, last, 4, parquet_compact_struct(), 1);
  let sc = sorting_column();
  push_bytes(&mut g, &sc);
  last = field_i64(&mut g, last, 5, 4);
  last = field_i64(&mut g, last, 6, 180);
  last = field_i16(&mut g, last, 7, 0);
  stop(&mut g);
  return g;
}

fn sample_meta() -> Vec[UInt8] {
  var m = Vec[UInt8].new();
  var last = 0;
  last = field_i32(&mut m, last, 1, 1);
  last = list_field(&mut m, last, 2, parquet_compact_struct(), 4);
  let e0 = schema_root("root", 1);
  push_bytes(&mut m, &e0);
  let e1 = schema_group("g", 2, 1);
  push_bytes(&mut m, &e1);
  let e2 = schema_leaf(1, 0, "id");
  push_bytes(&mut m, &e2);
  let e3 = schema_leaf_logical(6, 1, "name", 1);
  push_bytes(&mut m, &e3);
  last = field_i64(&mut m, last, 3, 10);
  last = list_field(&mut m, last, 4, parquet_compact_struct(), 1);
  let rg = row_group_sample();
  push_bytes(&mut m, &rg);
  last = list_field(&mut m, last, 5, parquet_compact_struct(), 2);
  let k0 = kv("writer", "xiom-test");
  push_bytes(&mut m, &k0);
  let k1 = kv_novalue("empty");
  push_bytes(&mut m, &k1);
  last = field_str(&mut m, last, 6, "xiom.parquet test");
  last = list_field(&mut m, last, 7, parquet_compact_struct(), 2);
  let co0 = column_order(1);
  push_bytes(&mut m, &co0);
  let co1 = column_order(9);
  push_bytes(&mut m, &co1);
  stop(&mut m);
  return m;
}

fn sample_file() -> Vec[UInt8] {
  let meta = sample_meta();
  return wrap(&meta, 8);
}

// Weird-metadata fixture: unknown enum values everywhere they can appear.
fn weird_meta() -> Vec[UInt8] {
  var m = Vec[UInt8].new();
  var last = 0;
  last = field_i32(&mut m, last, 1, 2);
  last = list_field(&mut m, last, 2, parquet_compact_struct(), 2);
  let e0 = schema_root("root", 1);
  push_bytes(&mut m, &e0);
  var leaf = Vec[UInt8].new();
  var l2 = 0;
  l2 = field_i32(&mut leaf, l2, 1, 99);
  l2 = field_i32(&mut leaf, l2, 3, 0);
  l2 = field_str(&mut leaf, l2, 4, "weird");
  let lt = logical_type(42);
  l2 = field_struct(&mut leaf, l2, 10, &lt);
  stop(&mut leaf);
  push_bytes(&mut m, &leaf);
  last = field_i64(&mut m, last, 3, 1);
  last = list_field(&mut m, last, 4, parquet_compact_struct(), 1);
  var g = Vec[UInt8].new();
  var gl = 0;
  gl = list_field(&mut g, gl, 1, parquet_compact_struct(), 1);
  var c = Vec[UInt8].new();
  var cl = 0;
  cl = field_i64(&mut c, cl, 2, 0);
  var meta = Vec[UInt8].new();
  var ml = 0;
  ml = field_i32(&mut meta, ml, 1, 99);
  let encs = v_int(55);
  ml = i32_list_field(&mut meta, ml, 2, &encs);
  var pstr = Vec[Str].new();
  pstr.push("weird");
  ml = str_list_field(&mut meta, ml, 3, &pstr);
  ml = field_i32(&mut meta, ml, 4, 77);
  ml = field_i64(&mut meta, ml, 5, 1);
  ml = field_i64(&mut meta, ml, 6, 1);
  ml = field_i64(&mut meta, ml, 7, 1);
  ml = field_i64(&mut meta, ml, 9, 0);
  var es = Vec[UInt8].new();
  var el = 0;
  el = field_i32(&mut es, el, 1, 88);
  el = field_i32(&mut es, el, 2, 55);
  el = field_i32(&mut es, el, 3, 1);
  stop(&mut es);
  ml = list_field(&mut meta, ml, 13, parquet_compact_struct(), 1);
  push_bytes(&mut meta, &es);
  stop(&mut meta);
  cl = field_struct(&mut c, cl, 3, &meta);
  stop(&mut c);
  push_bytes(&mut g, &c);
  gl = field_i64(&mut g, gl, 2, 1);
  gl = field_i64(&mut g, gl, 3, 1);
  stop(&mut g);
  push_bytes(&mut m, &g);
  stop(&mut m);
  return m;
}

// Non-printing error predicates for multi-step tests.
fn file_err_is(r: Result[ParquetFile, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn int_err_is(r: Result[Int, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn str_err_is(r: Result[Str, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn bytes_err_is(r: Result[Vec[UInt8], Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn bool_err_is(r: Result[Bool, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn ph_err_is(r: Result[ParquetPageHeader, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

// Full sample file: top-level metadata.
fn t1() -> Int {
  let buf = sample_file();
  let r = parquet_parse(&buf);
  if !r.is_ok {
    return report(false, "sample parses (err: " + r.error + ")");
  }
  let f: ParquetFile = r.value;
  if parquet_version(&f) != 1 {
    return report(false, "version == 1");
  }
  if parquet_num_rows(&f) != 10 {
    return report(false, "num_rows == 10");
  }
  if !parquet_created_by_present(&f) {
    return report(false, "created_by present");
  }
  if !str_eq(parquet_created_by(&f), "xiom.parquet test") {
    return report(false, "created_by text");
  }
  if parquet_footer_length(&f) != parquet_file_length(&f) - 8 - parquet_metadata_offset(&f) {
    return report(false, "footer length consistency");
  }
  if parquet_schema_count(&f) != 4 {
    return report(false, "schema count == 4");
  }
  return report(true, "sample file: top-level metadata");
}

// Magic checks: too small, bad header magic, bad footer magic.
fn t2() -> Int {
  let short = zeros(11);
  if !file_err_is(parquet_parse(&short), "parquet: file too small") {
    return report(false, "short buffer rejected");
  }
  var buf = sample_file();
  buf[0] = 88;
  if !file_err_is(parquet_parse(&buf), "parquet: bad header magic") {
    return report(false, "bad header magic rejected");
  }
  var buf2 = sample_file();
  let n = buf2.len();
  buf2[n - 1] = 88;
  if !file_err_is(parquet_parse(&buf2), "parquet: bad footer magic") {
    return report(false, "bad footer magic rejected");
  }
  return report(true, "magic validation");
}

// Footer length bounds.
fn t3() -> Int {
  var buf = sample_file();
  let n = buf.len();
  buf[n - 8] = 255;
  buf[n - 7] = 255;
  buf[n - 6] = 255;
  buf[n - 5] = 127;
  if !file_err_is(parquet_parse(&buf), "parquet: footer length out of bounds (len=2147483647)") {
    return report(false, "huge footer length rejected");
  }
  var buf2 = sample_file();
  let n2 = buf2.len();
  let bad = n2 - 11;
  buf2[n2 - 8] = bad % 256;
  buf2[n2 - 7] = (bad / 256) % 256;
  buf2[n2 - 6] = 0;
  buf2[n2 - 5] = 0;
  let want = "parquet: footer length out of bounds (len=" + convert.int_to_string(bad) + ")";
  if !file_err_is(parquet_parse(&buf2), want) {
    return report(false, "footer length overlapping the magic rejected");
  }
  return report(true, "footer length bounds");
}

// Schema tree walk: names, paths, parents, depths, levels, leaves.
fn t4() -> Int {
  let buf = sample_file();
  let r = parquet_parse(&buf);
  if !r.is_ok {
    return report(false, "schema tree parses (err: " + r.error + ")");
  }
  let f: ParquetFile = r.value;
  if !str_is(parquet_schema_name(&f, 1), "g") {
    return report(false, "schema name 1");
  }
  if !str_is(parquet_schema_path(&f, 1), "g") {
    return report(false, "path g");
  }
  if !int_is(parquet_schema_parent(&f, 1), 0) {
    return report(false, "parent g");
  }
  if !int_is(parquet_schema_depth(&f, 1), 1) {
    return report(false, "depth g");
  }
  if !int_is(parquet_schema_max_definition_level(&f, 1), 1) {
    return report(false, "max_def g (OPTIONAL)");
  }
  if !int_is(parquet_schema_max_repetition_level(&f, 1), 0) {
    return report(false, "max_rep g");
  }
  if !str_is(parquet_schema_path(&f, 2), "g.id") {
    return report(false, "path id");
  }
  if !int_is(parquet_schema_max_definition_level(&f, 2), 1) {
    return report(false, "max_def id (REQUIRED)");
  }
  if !int_is(parquet_schema_type(&f, 2), 1) {
    return report(false, "type id INT32");
  }
  if !int_is(parquet_schema_leaf_index(&f, 2), 0) {
    return report(false, "leaf index id");
  }
  if !str_is(parquet_schema_name(&f, 3), "name") {
    return report(false, "schema name 3");
  }
  if !str_is(parquet_schema_path(&f, 3), "g.name") {
    return report(false, "path name");
  }
  if !int_is(parquet_schema_max_definition_level(&f, 3), 2) {
    return report(false, "max_def name (OPTIONAL under OPTIONAL)");
  }
  if !int_is(parquet_schema_type(&f, 3), 6) {
    return report(false, "type name BYTE_ARRAY");
  }
  if !int_is(parquet_schema_leaf_index(&f, 3), 1) {
    return report(false, "leaf index name");
  }
  if !bool_is(parquet_schema_type_present(&f, 0), false) {
    return report(false, "root has no type");
  }
  if !bool_is(parquet_schema_is_leaf(&f, 1), false) {
    return report(false, "g is a group");
  }
  if parquet_schema_leaf_count(&f) != 2 {
    return report(false, "leaf count == 2");
  }
  if !str_eq(parquet_schema_type_name(1), "INT32") {
    return report(false, "type name INT32");
  }
  if !str_eq(parquet_schema_repetition_name(2), "REPEATED") {
    return report(false, "repetition name REPEATED");
  }
  if !int_is(parquet_schema_logical_type(&f, 3), 1) {
    return report(false, "logical STRING member");
  }
  if !str_eq(parquet_logical_type_name(1), "STRING") {
    return report(false, "logical name STRING");
  }
  if parquet_schema_find_path(&f, "g.name") != 3 {
    return report(false, "find path g.name");
  }
  if parquet_schema_find_path(&f, "nope") != -1 {
    return report(false, "find path absent");
  }
  return report(true, "schema tree walk");
}

// Row group accessors and sorting columns.
fn t5() -> Int {
  let buf = sample_file();
  let r = parquet_parse(&buf);
  if !r.is_ok {
    return report(false, "row groups parse (err: " + r.error + ")");
  }
  let f: ParquetFile = r.value;
  if parquet_row_group_count(&f) != 1 {
    return report(false, "row group count == 1");
  }
  if !int_is(parquet_row_group_num_rows(&f, 0), 10) {
    return report(false, "row group num_rows");
  }
  if !int_is(parquet_row_group_total_byte_size(&f, 0), 200) {
    return report(false, "row group total_byte_size");
  }
  if !int_is(parquet_row_group_file_offset(&f, 0), 4) {
    return report(false, "row group file_offset");
  }
  if !bool_is(parquet_row_group_file_offset_present(&f, 0), true) {
    return report(false, "row group file_offset presence");
  }
  if !int_is(parquet_row_group_total_compressed_size(&f, 0), 180) {
    return report(false, "row group total_compressed_size");
  }
  if !int_is(parquet_row_group_ordinal(&f, 0), 0) {
    return report(false, "row group ordinal");
  }
  if !int_is(parquet_row_group_column_count(&f, 0), 2) {
    return report(false, "row group column count");
  }
  if !int_is(parquet_row_group_column(&f, 0, 0), 0) {
    return report(false, "row group column 0");
  }
  if !int_is(parquet_row_group_column(&f, 0, 1), 1) {
    return report(false, "row group column 1");
  }
  if !int_err_is(parquet_row_group_column(&f, 0, 2), "parquet: row group column index out of range") {
    return report(false, "row group column bounds");
  }
  if !int_err_is(parquet_row_group_num_rows(&f, 1), "parquet: row group index out of range") {
    return report(false, "row group bounds");
  }
  if !int_is(parquet_row_group_sorting_count(&f, 0), 1) {
    return report(false, "sorting count");
  }
  if !int_is(parquet_sorting_column_idx(&f, 0, 0), 0) {
    return report(false, "sorting column_idx");
  }
  if !bool_is(parquet_sorting_column_descending(&f, 0, 0), false) {
    return report(false, "sorting descending");
  }
  if !bool_is(parquet_sorting_column_nulls_first(&f, 0, 0), true) {
    return report(false, "sorting nulls_first");
  }
  return report(true, "row groups and sorting columns");
}

// Column chunk 0 (id): metadata, encodings, path, encoding stats.
fn t6() -> Int {
  let buf = sample_file();
  let r = parquet_parse(&buf);
  if !r.is_ok {
    return report(false, "chunks parse (err: " + r.error + ")");
  }
  let f: ParquetFile = r.value;
  if parquet_chunk_count(&f) != 2 {
    return report(false, "chunk count == 2");
  }
  if !int_is(parquet_chunk_file_offset(&f, 0), 4) {
    return report(false, "chunk 0 file_offset");
  }
  if !bool_is(parquet_chunk_file_path_present(&f, 0), false) {
    return report(false, "chunk 0 file_path absent");
  }
  if !str_err_is(parquet_chunk_file_path(&f, 0), "parquet: column chunk has no file_path") {
    return report(false, "chunk 0 file_path error");
  }
  if !bool_is(parquet_chunk_meta_present(&f, 0), true) {
    return report(false, "chunk 0 meta present");
  }
  if !int_is(parquet_chunk_type(&f, 0), 1) {
    return report(false, "chunk 0 type INT32");
  }
  if !str_eq(parquet_schema_type_name(parquet_chunk_type(&f, 0).value), "INT32") {
    return report(false, "chunk 0 type name");
  }
  if !int_is(parquet_chunk_codec(&f, 0), 0) {
    return report(false, "chunk 0 codec UNCOMPRESSED");
  }
  if !str_eq(parquet_codec_name(0), "UNCOMPRESSED") {
    return report(false, "codec name UNCOMPRESSED");
  }
  if !int_is(parquet_chunk_num_values(&f, 0), 10) {
    return report(false, "chunk 0 num_values");
  }
  if !int_is(parquet_chunk_total_uncompressed_size(&f, 0), 100) {
    return report(false, "chunk 0 total_uncompressed_size");
  }
  if !int_is(parquet_chunk_total_compressed_size(&f, 0), 90) {
    return report(false, "chunk 0 total_compressed_size");
  }
  if !int_is(parquet_chunk_data_page_offset(&f, 0), 4) {
    return report(false, "chunk 0 data_page_offset");
  }
  if !int_is(parquet_chunk_dictionary_page_offset(&f, 0), 20) {
    return report(false, "chunk 0 dictionary_page_offset");
  }
  if !int_err_is(parquet_chunk_index_page_offset(&f, 0), "parquet: column chunk has no index_page_offset") {
    return report(false, "chunk 0 index_page_offset absent");
  }
  if !int_is(parquet_chunk_offset_index_offset(&f, 0), 500) {
    return report(false, "chunk 0 offset_index_offset");
  }
  if !int_is(parquet_chunk_column_index_offset(&f, 0), 600) {
    return report(false, "chunk 0 column_index_offset");
  }
  if !int_is(parquet_chunk_encoding_count(&f, 0), 2) {
    return report(false, "chunk 0 encoding count");
  }
  if !int_is(parquet_chunk_encoding(&f, 0, 0), 0) {
    return report(false, "chunk 0 encoding 0 PLAIN");
  }
  if !int_is(parquet_chunk_encoding(&f, 0, 1), 3) {
    return report(false, "chunk 0 encoding 1 RLE");
  }
  if !int_err_is(parquet_chunk_encoding(&f, 0, 2), "parquet: encoding index out of range") {
    return report(false, "chunk 0 encoding bounds");
  }
  if !str_eq(parquet_encoding_name(3), "RLE") {
    return report(false, "encoding name RLE");
  }
  if !int_is(parquet_chunk_path_count(&f, 0), 2) {
    return report(false, "chunk 0 path count");
  }
  if !str_is(parquet_chunk_path(&f, 0, 0), "g") {
    return report(false, "chunk 0 path part 0");
  }
  if !str_is(parquet_chunk_path(&f, 0, 1), "id") {
    return report(false, "chunk 0 path part 1");
  }
  if !str_is(parquet_chunk_path_joined(&f, 0), "g.id") {
    return report(false, "chunk 0 path joined");
  }
  if !int_is(parquet_chunk_encoding_stats_count(&f, 0), 1) {
    return report(false, "chunk 0 encoding stats count");
  }
  if !int_is(parquet_chunk_encoding_stat_page_type(&f, 0, 0), 0) {
    return report(false, "encoding stat page_type");
  }
  if !int_is(parquet_chunk_encoding_stat_encoding(&f, 0, 0), 0) {
    return report(false, "encoding stat encoding");
  }
  if !int_is(parquet_chunk_encoding_stat_count(&f, 0, 0), 1) {
    return report(false, "encoding stat count");
  }
  return report(true, "column chunk 0 accessors");
}

// Column chunk 1 (name): file_path, codec, absent stats, index lengths.
fn t7() -> Int {
  let buf = sample_file();
  let r = parquet_parse(&buf);
  if !r.is_ok {
    return report(false, "chunks parse (err: " + r.error + ")");
  }
  let f: ParquetFile = r.value;
  if !str_is(parquet_chunk_file_path(&f, 1), "part-0.parquet") {
    return report(false, "chunk 1 file_path");
  }
  if !bool_is(parquet_chunk_file_path_present(&f, 1), true) {
    return report(false, "chunk 1 file_path presence");
  }
  if !int_is(parquet_chunk_file_offset(&f, 1), 300) {
    return report(false, "chunk 1 file_offset");
  }
  if !int_is(parquet_chunk_codec(&f, 1), 1) {
    return report(false, "chunk 1 codec SNAPPY");
  }
  if !str_eq(parquet_codec_name(1), "SNAPPY") {
    return report(false, "codec name SNAPPY");
  }
  if !int_is(parquet_chunk_type(&f, 1), 6) {
    return report(false, "chunk 1 type BYTE_ARRAY");
  }
  if !int_is(parquet_chunk_path_count(&f, 1), 2) {
    return report(false, "chunk 1 path count");
  }
  if !str_is(parquet_chunk_path_joined(&f, 1), "g.name") {
    return report(false, "chunk 1 path joined");
  }
  if !int_is(parquet_chunk_key_value_count(&f, 1), 0) {
    return report(false, "chunk 1 kv count");
  }
  if !bool_is(parquet_chunk_stat_present(&f, 1), false) {
    return report(false, "chunk 1 statistics absent");
  }
  if !int_is(parquet_chunk_offset_index_length(&f, 1), 64) {
    return report(false, "chunk 1 offset_index_length");
  }
  if !int_is(parquet_chunk_column_index_length(&f, 1), 32) {
    return report(false, "chunk 1 column_index_length");
  }
  if !int_is(parquet_chunk_offset_index_offset(&f, 1), 0) {
    return report(false, "chunk 1 offset_index_offset absent as 0");
  }
  return report(true, "column chunk 1 accessors");
}

// Statistics: raw bytes, counters and exact flags.
fn t8() -> Int {
  let buf = sample_file();
  let r = parquet_parse(&buf);
  if !r.is_ok {
    return report(false, "statistics parse (err: " + r.error + ")");
  }
  let f: ParquetFile = r.value;
  let ten = vb4(0, 0, 0, 10);
  let one = vb4(0, 0, 0, 1);
  if !bytes_is(parquet_chunk_stat_max(&f, 0), &ten) {
    return report(false, "stat max bytes");
  }
  if !bytes_is(parquet_chunk_stat_min(&f, 0), &one) {
    return report(false, "stat min bytes");
  }
  if !bytes_is(parquet_chunk_stat_max_value(&f, 0), &ten) {
    return report(false, "stat max_value bytes");
  }
  if !bytes_is(parquet_chunk_stat_min_value(&f, 0), &one) {
    return report(false, "stat min_value bytes");
  }
  if !int_is(parquet_chunk_stat_null_count(&f, 0), 0) {
    return report(false, "stat null_count 0");
  }
  if !int_is(parquet_chunk_stat_distinct_count(&f, 0), 10) {
    return report(false, "stat distinct_count 10");
  }
  if !bool_is(parquet_chunk_stat_max_exact(&f, 0), true) {
    return report(false, "stat max exact");
  }
  if !bool_is(parquet_chunk_stat_min_exact(&f, 0), true) {
    return report(false, "stat min exact");
  }
  if !bool_is(parquet_chunk_stat_present(&f, 0), true) {
    return report(false, "stat present");
  }
  if !bytes_err_is(parquet_chunk_stat_max_value(&f, 1), "parquet: statistic not present (chunk=1, stat=max_value)") {
    return report(false, "stat max_value absent error");
  }
  if !int_err_is(parquet_chunk_stat_null_count(&f, 1), "parquet: statistic not present (chunk=1, stat=null_count)") {
    return report(false, "stat null_count absent error");
  }
  if !bool_err_is(parquet_chunk_stat_max_exact(&f, 1), "parquet: statistic not present (chunk=1, stat=is_max_value_exact)") {
    return report(false, "stat max exact absent error");
  }
  if !bytes_err_is(parquet_chunk_stat_max(&f, 9), "parquet: column chunk index out of range") {
    return report(false, "stat chunk bounds");
  }
  return report(true, "statistics raw bytes and flags");
}

// File-level key/value metadata and column orders.
fn t9() -> Int {
  let buf = sample_file();
  let r = parquet_parse(&buf);
  if !r.is_ok {
    return report(false, "file metadata parse (err: " + r.error + ")");
  }
  let f: ParquetFile = r.value;
  if parquet_file_key_value_count(&f) != 2 {
    return report(false, "file kv count");
  }
  if !str_is(parquet_file_key_value_key(&f, 0), "writer") {
    return report(false, "file kv key 0");
  }
  if !str_is(parquet_file_key_value_value(&f, 0), "xiom-test") {
    return report(false, "file kv value 0");
  }
  if !str_is(parquet_file_key_value_key(&f, 1), "empty") {
    return report(false, "file kv key 1");
  }
  if !str_err_is(parquet_file_key_value_value(&f, 1), "parquet: key value entry has no value") {
    return report(false, "file kv value 1 absent");
  }
  if parquet_column_order_count(&f) != 2 {
    return report(false, "column order count");
  }
  if !int_is(parquet_column_order(&f, 0), 1) {
    return report(false, "column order 0 TYPE_ORDER");
  }
  if !str_eq(parquet_column_order_name(1), "TYPE_ORDER") {
    return report(false, "column order name TYPE_ORDER");
  }
  if !int_is(parquet_column_order(&f, 1), 9) {
    return report(false, "column order 1 raw unknown");
  }
  if !str_eq(parquet_column_order_name(9), "unknown") {
    return report(false, "column order name unknown");
  }
  if !int_err_is(parquet_column_order(&f, 2), "parquet: column order index out of range") {
    return report(false, "column order bounds");
  }
  return report(true, "file key values and column orders");
}

// Unknown enum values are preserved raw and named "unknown".
fn t10() -> Int {
  let meta = weird_meta();
  let buf = wrap(&meta, 0);
  let r = parquet_parse(&buf);
  if !r.is_ok {
    return report(false, "weird file parses (err: " + r.error + ")");
  }
  let f: ParquetFile = r.value;
  if !int_is(parquet_schema_type(&f, 1), 99) {
    return report(false, "weird schema type raw");
  }
  if !str_eq(parquet_schema_type_name(99), "unknown") {
    return report(false, "weird schema type name");
  }
  if !int_is(parquet_schema_logical_type(&f, 1), 42) {
    return report(false, "weird logical member raw");
  }
  if !int_is(parquet_chunk_type(&f, 0), 99) {
    return report(false, "weird chunk type raw");
  }
  if !int_is(parquet_chunk_codec(&f, 0), 77) {
    return report(false, "weird codec raw");
  }
  if !str_eq(parquet_codec_name(77), "unknown") {
    return report(false, "weird codec name");
  }
  if !int_is(parquet_chunk_encoding(&f, 0, 0), 55) {
    return report(false, "weird encoding raw");
  }
  if !str_eq(parquet_encoding_name(55), "unknown") {
    return report(false, "weird encoding name");
  }
  if !int_is(parquet_chunk_encoding_stat_page_type(&f, 0, 0), 88) {
    return report(false, "weird page type raw");
  }
  if !str_eq(parquet_page_type_name(88), "unknown") {
    return report(false, "weird page type name");
  }
  return report(true, "unknown enums preserved raw");
}

fn lhdr_err_is(r: Result[ParquetListHeader, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn mhdr_err_is(r: Result[ParquetMapHeader, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn field_err_is(r: Result[ParquetField, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

// Varint primitives: values, byte order, overflow and truncation.
fn t11() -> Int {
  var b0 = Vec[UInt8].new();
  enc_varint(&mut b0, 0);
  var r0 = parquet_reader_new(b0);
  let v0 = parquet_read_varint(&mut r0);
  if !int_is(v0, 0) {
    return report(false, "varint 0");
  }
  if parquet_reader_pos(&r0) != 1 {
    return report(false, "varint 0 position");
  }
  var b1 = Vec[UInt8].new();
  enc_varint(&mut b1, 50399);
  if b1.len() != 3 {
    return report(false, "varint 50399 length");
  }
  let x0: UInt8 = b1[0];
  let x1: UInt8 = b1[1];
  let x2: UInt8 = b1[2];
  if x0 != 223 || x1 != 137 || x2 != 3 {
    return report(false, "varint 50399 byte order");
  }
  var r1 = parquet_reader_new(b1);
  let v1 = parquet_read_varint(&mut r1);
  if !int_is(v1, 50399) {
    return report(false, "varint 50399 value");
  }
  var b2 = Vec[UInt8].new();
  enc_varint(&mut b2, 9223372036854775807);
  var r2 = parquet_reader_new(b2);
  let v2 = parquet_read_varint(&mut r2);
  if !int_is(v2, 9223372036854775807) {
    return report(false, "varint 2^63-1");
  }
  var b3 = Vec[UInt8].new();
  var i = 0;
  while i < 9 {
    b3.push((255 as UInt8));
    i = i + 1;
  }
  b3.push((1 as UInt8));
  var r3 = parquet_reader_new(b3);
  let v3 = parquet_read_varint(&mut r3);
  if !int_is(v3, -1) {
    return report(false, "varint 2^64-1 pattern");
  }
  var b4 = Vec[UInt8].new();
  var j = 0;
  while j < 10 {
    b4.push((128 as UInt8));
    j = j + 1;
  }
  var r4 = parquet_reader_new(b4);
  let v4 = parquet_read_varint(&mut r4);
  if !int_err_is(v4, "parquet: varint too long at offset 0") {
    return report(false, "varint too long");
  }
  var b5 = Vec[UInt8].new();
  var k = 0;
  while k < 9 {
    b5.push((128 as UInt8));
    k = k + 1;
  }
  b5.push((2 as UInt8));
  var r5 = parquet_reader_new(b5);
  let v5 = parquet_read_varint(&mut r5);
  if !int_err_is(v5, "parquet: varint overflow at offset 0") {
    return report(false, "varint overflow");
  }
  var b6 = vb1(128);
  var r6 = parquet_reader_new(b6);
  let v6 = parquet_read_varint(&mut r6);
  if !int_err_is(v6, "parquet: truncated varint at offset 0") {
    return report(false, "varint truncated");
  }
  return report(true, "varint primitives");
}

// Zigzag round-trips and full 64-bit extremes.
fn t12() -> Int {
  var vals = Vec[Int].new();
  vals.push(0);
  vals.push(0 - 1);
  vals.push(1);
  vals.push(0 - 2);
  vals.push(2);
  vals.push(63);
  vals.push(0 - 64);
  vals.push(2147483647);
  vals.push(0 - 2147483648);
  vals.push(4611686018427387903);
  vals.push(0 - 4611686018427387904);
  var i = 0;
  while i < vals.len() {
    let want: Int = vals[i];
    var b = Vec[UInt8].new();
    enc_zigzag(&mut b, want);
    var r = parquet_reader_new(b);
    let got = parquet_read_zigzag(&mut r);
    if !int_is(got, want) {
      return report(false, "zigzag round-trip " + convert.int_to_string(want));
    }
    i = i + 1;
  }
  var b2 = Vec[UInt8].new();
  b2.push((254 as UInt8));
  var j = 0;
  while j < 8 {
    b2.push((255 as UInt8));
    j = j + 1;
  }
  b2.push((1 as UInt8));
  var r2 = parquet_reader_new(b2);
  let v2 = parquet_read_zigzag(&mut r2);
  if !int_is(v2, 9223372036854775807) {
    return report(false, "zigzag int64 maximum");
  }
  var b3 = Vec[UInt8].new();
  var k = 0;
  while k < 9 {
    b3.push((255 as UInt8));
    k = k + 1;
  }
  b3.push((1 as UInt8));
  var r3 = parquet_reader_new(b3);
  let v3 = parquet_read_zigzag(&mut r3);
  if !int_is(v3, 0 - 9223372036854775807 - 1) {
    return report(false, "zigzag int64 minimum");
  }
  return report(true, "zigzag primitives");
}

// Field header matrix: short/long form, bool in the nibble, STOP.
fn t13() -> Int {
  var b = Vec[UInt8].new();
  var last = 0;
  last = field(&mut b, last, 1, parquet_compact_i32());
  last = field(&mut b, last, 2, parquet_compact_i64());
  last = field(&mut b, last, 20, parquet_compact_i32());
  last = field_bool(&mut b, last, 21, true);
  last = field(&mut b, last, 5, parquet_compact_binary());
  stop(&mut b);
  var r = parquet_reader_new(b);
  let fr1 = parquet_read_field_header(&mut r, 0);
  if !fr1.is_ok {
    return report(false, "field 1 decodes");
  }
  let x1: ParquetField = fr1.value;
  if x1.fid != 1 || x1.ftype != 5 {
    return report(false, "field 1 delta form");
  }
  let fr2 = parquet_read_field_header(&mut r, x1.fid);
  if !fr2.is_ok {
    return report(false, "field 2 decodes");
  }
  let x2: ParquetField = fr2.value;
  if x2.fid != 2 || x2.ftype != 6 {
    return report(false, "field 2 delta form");
  }
  let fr3 = parquet_read_field_header(&mut r, x2.fid);
  if !fr3.is_ok {
    return report(false, "field 20 decodes");
  }
  let x3: ParquetField = fr3.value;
  if x3.fid != 20 || x3.ftype != 5 {
    return report(false, "field 20 long form");
  }
  let fr4 = parquet_read_field_header(&mut r, x3.fid);
  if !fr4.is_ok {
    return report(false, "field 21 decodes");
  }
  let x4: ParquetField = fr4.value;
  if x4.fid != 21 || x4.ftype != 1 {
    return report(false, "bool field in nibble");
  }
  if !parquet_field_bool(&x4) {
    return report(false, "bool field true value");
  }
  let fr5 = parquet_read_field_header(&mut r, x4.fid);
  if !fr5.is_ok {
    return report(false, "field 5 decodes");
  }
  let x5: ParquetField = fr5.value;
  if x5.fid != 5 || x5.ftype != 8 {
    return report(false, "negative delta long form");
  }
  let fr6 = parquet_read_field_header(&mut r, x5.fid);
  if !fr6.is_ok {
    return report(false, "stop decodes");
  }
  let x6: ParquetField = fr6.value;
  if x6.ftype != 0 || x6.fid != 0 {
    return report(false, "STOP field");
  }
  var b2 = Vec[UInt8].new();
  var l2 = 0;
  l2 = field_bool(&mut b2, l2, 1, true);
  l2 = field_bool(&mut b2, l2, 2, false);
  stop(&mut b2);
  var r2 = parquet_reader_new(b2);
  let g1 = parquet_read_field_header(&mut r2, 0);
  let g2 = parquet_read_field_header(&mut r2, 1);
  if !g1.is_ok || !g2.is_ok {
    return report(false, "bool fields decode");
  }
  let y1: ParquetField = g1.value;
  let y2: ParquetField = g2.value;
  if !parquet_field_bool(&y1) {
    return report(false, "bool true");
  }
  if parquet_field_bool(&y2) {
    return report(false, "bool false");
  }
  var b3 = vb1(13);
  var r3 = parquet_reader_new(b3);
  let e1 = parquet_read_field_header(&mut r3, 0);
  if !field_err_is(e1, "parquet: unknown compact type 13 at offset 0") {
    return report(false, "unknown field type rejected");
  }
  return report(true, "compact field header matrix");
}

// Primitive readers: byte, bool element, double, string validation.
fn t14() -> Int {
  var b = vb2(255, 127);
  var r = parquet_reader_new(b);
  let v0 = parquet_read_byte(&mut r);
  if !int_is(v0, -1) {
    return report(false, "byte sign extension");
  }
  let v1 = parquet_read_byte(&mut r);
  if !int_is(v1, 127) {
    return report(false, "byte positive");
  }
  var b2 = vb2(1, 2);
  var r2 = parquet_reader_new(b2);
  let bv1 = parquet_read_bool(&mut r2);
  if !bool_is(bv1, true) {
    return report(false, "bool element 1");
  }
  let bv2 = parquet_read_bool(&mut r2);
  if !bool_is(bv2, false) {
    return report(false, "bool element 2");
  }
  var b3 = vb1(3);
  var r3 = parquet_reader_new(b3);
  let bv3 = parquet_read_bool(&mut r3);
  if !bool_err_is(bv3, "parquet: invalid compact bool value 3 at offset 0") {
    return report(false, "invalid bool element");
  }
  var d = Vec[UInt8].new();
  var i = 0;
  while i < 6 {
    d.push((0 as UInt8));
    i = i + 1;
  }
  d.push((240 as UInt8));
  d.push((63 as UInt8));
  var r4 = parquet_reader_new(d);
  let dv = parquet_read_double_bits(&mut r4);
  if !int_is(dv, 4607182418800017408) {
    return report(false, "double 1.0 bits");
  }
  var d2 = Vec[UInt8].new();
  var i2 = 0;
  while i2 < 7 {
    d2.push((0 as UInt8));
    i2 = i2 + 1;
  }
  d2.push((192 as UInt8));
  var r5 = parquet_reader_new(d2);
  let dv2 = parquet_read_double_bits(&mut r5);
  if !int_is(dv2, 0 - 4611686018427387904) {
    return report(false, "double -2.0 bits");
  }
  var s = Vec[UInt8].new();
  s.push((2 as UInt8));
  s.push((195 as UInt8));
  s.push((169 as UInt8));
  var r6 = parquet_reader_new(s);
  let sv = parquet_read_string(&mut r6);
  if !sv.is_ok {
    return report(false, "utf-8 string decodes");
  }
  let got_s: Str = sv.value;
  if string.str_len(got_s) != 2 {
    return report(false, "utf-8 string length");
  }
  let b0i: Int = (string.byte_at(got_s, 0) as Int) & 0xFF;
  let b1i: Int = (string.byte_at(got_s, 1) as Int) & 0xFF;
  if b0i != 195 || b1i != 169 {
    return report(false, "utf-8 string bytes");
  }
  var s2 = vb2(1, 255);
  var r7 = parquet_reader_new(s2);
  let sv2 = parquet_read_string(&mut r7);
  if !str_err_is(sv2, "parquet: invalid utf-8 at offset 1") {
    return report(false, "invalid utf-8 rejected");
  }
  var s3 = vb2(1, 0);
  var r8 = parquet_reader_new(s3);
  let sv3 = parquet_read_string(&mut r8);
  if !str_err_is(sv3, "parquet: string contains nul at offset 1") {
    return report(false, "nul string rejected");
  }
  var d3 = zeros(4);
  var r9 = parquet_reader_new(d3);
  let dv3 = parquet_read_double_bits(&mut r9);
  if !int_err_is(dv3, "parquet: truncated input at offset 0") {
    return report(false, "truncated double");
  }
  var s4 = vb2(9, 1);
  var r10 = parquet_reader_new(s4);
  let sv4 = parquet_read_binary(&mut r10);
  if !bytes_err_is(sv4, "parquet: binary length out of bounds at offset 0") {
    return report(false, "binary length out of bounds");
  }
  return report(true, "primitive readers");
}

// List, set and map headers, oversized guards, bool list skipping.
fn t15() -> Int {
  var b = Vec[UInt8].new();
  b.push((37 as UInt8));
  b.push((0 as UInt8));
  b.push((0 as UInt8));
  var r = parquet_reader_new(b);
  let lh = parquet_read_list_header(&mut r);
  if !lh.is_ok {
    return report(false, "short list header decodes");
  }
  let h: ParquetListHeader = lh.value;
  if h.etype != 5 || h.size != 2 {
    return report(false, "short list header fields");
  }
  var b2 = Vec[UInt8].new();
  b2.push((245 as UInt8));
  enc_varint(&mut b2, 15);
  var j = 0;
  while j < 15 {
    b2.push((0 as UInt8));
    j = j + 1;
  }
  var r2 = parquet_reader_new(b2);
  let lh2 = parquet_read_list_header(&mut r2);
  if !lh2.is_ok {
    return report(false, "long list header decodes");
  }
  let h2: ParquetListHeader = lh2.value;
  if h2.etype != 5 || h2.size != 15 {
    return report(false, "long list header fields");
  }
  var b3 = vb2(37, 0);
  var r3 = parquet_reader_new(b3);
  let lh3 = parquet_read_list_header(&mut r3);
  if !lhdr_err_is(lh3, "parquet: oversized collection at offset 0") {
    return report(false, "oversized list rejected");
  }
  var b4 = vb1(45);
  var r4 = parquet_reader_new(b4);
  let lh4 = parquet_read_list_header(&mut r4);
  if !lhdr_err_is(lh4, "parquet: unknown compact type 13 at offset 0") {
    return report(false, "unknown list element type rejected");
  }
  var b5 = vb1(0);
  var r5 = parquet_reader_new(b5);
  let mh = parquet_read_map_header(&mut r5);
  if !mh.is_ok {
    return report(false, "empty map decodes");
  }
  let hm: ParquetMapHeader = mh.value;
  if hm.size != 0 || hm.ktype != 0 || hm.vtype != 0 {
    return report(false, "empty map fields");
  }
  var b6 = Vec[UInt8].new();
  b6.push((2 as UInt8));
  b6.push((133 as UInt8));
  b6.push((0 as UInt8));
  b6.push((0 as UInt8));
  b6.push((0 as UInt8));
  b6.push((0 as UInt8));
  var r6 = parquet_reader_new(b6);
  let mh2 = parquet_read_map_header(&mut r6);
  if !mh2.is_ok {
    return report(false, "map header decodes");
  }
  let hm2: ParquetMapHeader = mh2.value;
  if hm2.size != 2 || hm2.ktype != 8 || hm2.vtype != 5 {
    return report(false, "map header fields");
  }
  var b7 = Vec[UInt8].new();
  b7.push((2 as UInt8));
  b7.push((133 as UInt8));
  b7.push((0 as UInt8));
  var r7 = parquet_reader_new(b7);
  let mh3 = parquet_read_map_header(&mut r7);
  if !mhdr_err_is(mh3, "parquet: oversized collection at offset 0") {
    return report(false, "oversized map rejected");
  }
  var b8 = Vec[UInt8].new();
  b8.push((35 as UInt8));
  b8.push((0 as UInt8));
  b8.push((0 as UInt8));
  var r8 = parquet_reader_new(b8);
  let sh = parquet_read_set_header(&mut r8);
  if !sh.is_ok {
    return report(false, "set header decodes");
  }
  let hs: ParquetListHeader = sh.value;
  if hs.etype != 3 || hs.size != 2 {
    return report(false, "set header fields");
  }
  var b9 = Vec[UInt8].new();
  b9.push((33 as UInt8));
  b9.push((1 as UInt8));
  b9.push((2 as UInt8));
  var r9 = parquet_reader_new(b9);
  let sk = parquet_skip_value(&mut r9, 9);
  if !int_is(sk, 3) {
    return report(false, "bool list skip consumes one byte per element");
  }
  return report(true, "list, set and map headers");
}

// Skip consumed counts, reader windows and the nesting cap.
fn t16() -> Int {
  var r0 = parquet_reader_new_at(vb2(1, 2), 0, 1);
  if parquet_reader_remaining(&r0) != 1 {
    return report(false, "reader window remaining");
  }
  let v0 = parquet_read_byte(&mut r0);
  if !int_is(v0, 1) {
    return report(false, "reader window read");
  }
  if parquet_reader_remaining(&r0) != 0 {
    return report(false, "reader window exhausted");
  }
  var r0b = parquet_reader_new_at(vb2(1, 2), 1, 1);
  let v1 = parquet_read_byte(&mut r0b);
  if !int_err_is(v1, "parquet: truncated input at offset 1") {
    return report(false, "reader window end enforced");
  }
  var b = Vec[UInt8].new();
  b.push((21 as UInt8));
  b.push((2 as UInt8));
  stop(&mut b);
  var r = parquet_reader_new(b);
  let sv = parquet_skip_value(&mut r, 12);
  if !int_is(sv, 3) {
    return report(false, "struct skip consumed");
  }
  var b2 = Vec[UInt8].new();
  var i = 0;
  while i < 63 {
    b2.push((25 as UInt8));
    i = i + 1;
  }
  b2.push((21 as UInt8));
  b2.push((0 as UInt8));
  var r2 = parquet_reader_new(b2);
  let sv2 = parquet_skip_value(&mut r2, 9);
  if !int_is(sv2, 65) {
    return report(false, "64-level nesting accepted");
  }
  var b3 = Vec[UInt8].new();
  var j = 0;
  while j < 64 {
    b3.push((25 as UInt8));
    j = j + 1;
  }
  b3.push((21 as UInt8));
  var r3 = parquet_reader_new(b3);
  let sv3 = parquet_skip_value(&mut r3, 9);
  if !int_err_is(sv3, "parquet: nesting depth exceeds limit of 64 at offset 64") {
    return report(false, "65th nesting level rejected");
  }
  return report(true, "skip, reader windows and nesting cap");
}

// Page header fixtures.

fn page_data_stats_payload() -> Vec[UInt8] {
  var st = Vec[UInt8].new();
  var last = 0;
  last = field_i64(&mut st, last, 3, 2);
  stop(&mut st);
  return st;
}

fn page_data_header_payload() -> Vec[UInt8] {
  var d = Vec[UInt8].new();
  var last = 0;
  last = field_i32(&mut d, last, 1, 5);
  last = field_i32(&mut d, last, 2, 0);
  last = field_i32(&mut d, last, 3, 3);
  last = field_i32(&mut d, last, 4, 3);
  let st = page_data_stats_payload();
  last = field_struct(&mut d, last, 5, &st);
  stop(&mut d);
  return d;
}

fn page_data() -> Vec[UInt8] {
  var p = Vec[UInt8].new();
  var last = 0;
  last = field_i32(&mut p, last, 1, 0);
  last = field_i32(&mut p, last, 2, 100);
  last = field_i32(&mut p, last, 3, 80);
  last = field_i32(&mut p, last, 4, 12345);
  let dp = page_data_header_payload();
  last = field_struct(&mut p, last, 5, &dp);
  stop(&mut p);
  return p;
}

fn page_dictionary() -> Vec[UInt8] {
  var p = Vec[UInt8].new();
  var last = 0;
  last = field_i32(&mut p, last, 1, 2);
  last = field_i32(&mut p, last, 2, 40);
  last = field_i32(&mut p, last, 3, 32);
  var d = Vec[UInt8].new();
  var dl = 0;
  dl = field_i32(&mut d, dl, 1, 3);
  dl = field_i32(&mut d, dl, 2, 0);
  dl = field_bool(&mut d, dl, 3, true);
  stop(&mut d);
  last = field_struct(&mut p, last, 7, &d);
  stop(&mut p);
  return p;
}

fn page_index() -> Vec[UInt8] {
  var p = Vec[UInt8].new();
  var last = 0;
  last = field_i32(&mut p, last, 1, 1);
  last = field_i32(&mut p, last, 2, 16);
  last = field_i32(&mut p, last, 3, 16);
  let e = empty_struct();
  last = field_struct(&mut p, last, 6, &e);
  stop(&mut p);
  return p;
}

fn page_v2(compressed: Int, with_flag: Int) -> Vec[UInt8] {
  var p = Vec[UInt8].new();
  var last = 0;
  last = field_i32(&mut p, last, 1, 3);
  last = field_i32(&mut p, last, 2, 30);
  last = field_i32(&mut p, last, 3, 25);
  var d = Vec[UInt8].new();
  var dl = 0;
  dl = field_i32(&mut d, dl, 1, 5);
  dl = field_i32(&mut d, dl, 2, 1);
  dl = field_i32(&mut d, dl, 3, 5);
  dl = field_i32(&mut d, dl, 4, 0);
  dl = field_i32(&mut d, dl, 5, 2);
  dl = field_i32(&mut d, dl, 6, 0);
  if with_flag == 1 {
    if compressed == 1 {
      dl = field_bool(&mut d, dl, 7, true);
    } else {
      dl = field_bool(&mut d, dl, 7, false);
    }
  }
  let st = page_data_stats_payload();
  dl = field_struct(&mut d, dl, 8, &st);
  stop(&mut d);
  last = field_struct(&mut p, last, 8, &d);
  stop(&mut p);
  return p;
}

// DATA_PAGE header: fields, crc, consumed count, raw statistics range.
fn t17() -> Int {
  let ph_bytes = page_data();
  var buf = zeros(3);
  push_bytes(&mut buf, &ph_bytes);
  push_u8(&mut buf, 171);
  let r = parquet_parse_page_header(&buf, 3);
  if !r.is_ok {
    return report(false, "data page header parses (err: " + r.error + ")");
  }
  let h: ParquetPageHeader = r.value;
  if parquet_page_type(&h) != 0 {
    return report(false, "page type DATA_PAGE");
  }
  if !str_eq(parquet_page_type_name(0), "DATA_PAGE") {
    return report(false, "page type name");
  }
  if parquet_page_uncompressed_size(&h) != 100 {
    return report(false, "uncompressed page size");
  }
  if parquet_page_compressed_size(&h) != 80 {
    return report(false, "compressed page size");
  }
  let cr = parquet_page_crc(&h);
  if !int_is(cr, 12345) {
    return report(false, "page crc");
  }
  if parquet_page_consumed(&h) != ph_bytes.len() {
    return report(false, "page header consumed");
  }
  if !parquet_page_has_data_header(&h) {
    return report(false, "data page header present");
  }
  if parquet_page_has_index_header(&h) || parquet_page_has_dictionary_header(&h) || parquet_page_has_data_header_v2(&h) {
    return report(false, "other page headers absent");
  }
  if parquet_page_data_num_values(&h) != 5 {
    return report(false, "data num_values");
  }
  if parquet_page_data_encoding(&h) != 0 {
    return report(false, "data encoding");
  }
  if parquet_page_data_definition_level_encoding(&h) != 3 {
    return report(false, "data def level encoding");
  }
  if parquet_page_data_repetition_level_encoding(&h) != 3 {
    return report(false, "data rep level encoding");
  }
  if !parquet_page_data_stats_present(&h) {
    return report(false, "data stats present");
  }
  let stats_len = parquet_page_data_stats_length(&h);
  let want_stats = page_data_stats_payload();
  if stats_len != want_stats.len() {
    return report(false, "data stats raw length");
  }
  let got_stats = slice(&buf, parquet_page_data_stats_offset(&h), stats_len);
  if !bytes_eq(&got_stats, &want_stats) {
    return report(false, "data stats raw bytes");
  }
  let bad = parquet_parse_page_header(&buf, 1000);
  if !ph_err_is(bad, "parquet: page header offset out of range (offset=1000)") {
    return report(false, "page header offset bounds");
  }
  return report(true, "DATA_PAGE header");
}

// DICTIONARY_PAGE and INDEX_PAGE and DATA_PAGE_V2 headers.
fn t18() -> Int {
  let dict_bytes = page_dictionary();
  var buf = zeros(2);
  push_bytes(&mut buf, &dict_bytes);
  let r = parquet_parse_page_header(&buf, 2);
  if !r.is_ok {
    return report(false, "dictionary page parses (err: " + r.error + ")");
  }
  let h: ParquetPageHeader = r.value;
  if parquet_page_type(&h) != 2 {
    return report(false, "dictionary page type");
  }
  if !parquet_page_has_dictionary_header(&h) {
    return report(false, "dictionary header present");
  }
  if parquet_page_dictionary_num_values(&h) != 3 {
    return report(false, "dictionary num_values");
  }
  if parquet_page_dictionary_encoding(&h) != 0 {
    return report(false, "dictionary encoding");
  }
  let sr = parquet_page_dictionary_is_sorted(&h);
  if !bool_is(sr, true) {
    return report(false, "dictionary is_sorted");
  }
  if parquet_page_consumed(&h) != dict_bytes.len() {
    return report(false, "dictionary consumed");
  }
  let idx_bytes = page_index();
  var buf2 = zeros(1);
  push_bytes(&mut buf2, &idx_bytes);
  let r2 = parquet_parse_page_header(&buf2, 1);
  if !r2.is_ok {
    return report(false, "index page parses (err: " + r2.error + ")");
  }
  let h2: ParquetPageHeader = r2.value;
  if parquet_page_type(&h2) != 1 {
    return report(false, "index page type");
  }
  if !parquet_page_has_index_header(&h2) {
    return report(false, "index header present");
  }
  let v2_bytes = page_v2(0, 1);
  var buf3 = zeros(1);
  push_bytes(&mut buf3, &v2_bytes);
  let r3 = parquet_parse_page_header(&buf3, 1);
  if !r3.is_ok {
    return report(false, "v2 page parses (err: " + r3.error + ")");
  }
  let h3: ParquetPageHeader = r3.value;
  if parquet_page_type(&h3) != 3 {
    return report(false, "v2 page type");
  }
  if !parquet_page_has_data_header_v2(&h3) {
    return report(false, "v2 header present");
  }
  if parquet_page_v2_num_values(&h3) != 5 {
    return report(false, "v2 num_values");
  }
  if parquet_page_v2_num_nulls(&h3) != 1 {
    return report(false, "v2 num_nulls");
  }
  if parquet_page_v2_num_rows(&h3) != 5 {
    return report(false, "v2 num_rows");
  }
  if parquet_page_v2_encoding(&h3) != 0 {
    return report(false, "v2 encoding");
  }
  if parquet_page_v2_definition_levels_byte_length(&h3) != 2 {
    return report(false, "v2 def levels length");
  }
  if parquet_page_v2_repetition_levels_byte_length(&h3) != 0 {
    return report(false, "v2 rep levels length");
  }
  let c3 = parquet_page_v2_is_compressed(&h3);
  if !bool_is(c3, false) {
    return report(false, "v2 is_compressed false");
  }
  if !parquet_page_v2_stats_present(&h3) {
    return report(false, "v2 stats present");
  }
  let v2_noflag = page_v2(1, 0);
  var buf4 = zeros(1);
  push_bytes(&mut buf4, &v2_noflag);
  let r4 = parquet_parse_page_header(&buf4, 1);
  if !r4.is_ok {
    return report(false, "v2 page without flag parses");
  }
  let h4: ParquetPageHeader = r4.value;
  let c4 = parquet_page_v2_is_compressed(&h4);
  if !bool_err_is(c4, "parquet: data page header v2 has no is_compressed") {
    return report(false, "v2 is_compressed absent");
  }
  return report(true, "DICTIONARY_PAGE, INDEX_PAGE and DATA_PAGE_V2");
}

// Malformed metadata: truncated window and trailing bytes.
fn t19() -> Int {
  var buf = Vec[UInt8].new();
  push_u8(&mut buf, 80);
  push_u8(&mut buf, 65);
  push_u8(&mut buf, 82);
  push_u8(&mut buf, 49);
  push_bytes(&mut buf, &zeros(8));
  push_u8(&mut buf, 21);
  push_u8(&mut buf, 10);
  enc_u32le(&mut buf, 2);
  push_u8(&mut buf, 80);
  push_u8(&mut buf, 65);
  push_u8(&mut buf, 82);
  push_u8(&mut buf, 49);
  if !file_err_is(parquet_parse(&buf), "parquet: truncated input at offset 14") {
    return report(false, "truncated metadata window");
  }
  let meta = sample_meta();
  var m2 = Vec[UInt8].new();
  push_bytes(&mut m2, &meta);
  push_u8(&mut m2, 0);
  let buf2 = wrap(&m2, 8);
  let want = "parquet: trailing data in metadata at offset " + convert.int_to_string(12 + meta.len());
  if !file_err_is(parquet_parse(&buf2), want) {
    return report(false, "trailing metadata bytes rejected");
  }
  return report(true, "truncation and trailing data");
}

// Schema tree structural errors.
fn schema_overclaim_meta() -> Vec[UInt8] {
  var m = Vec[UInt8].new();
  var last = 0;
  last = field_i32(&mut m, last, 1, 1);
  last = list_field(&mut m, last, 2, parquet_compact_struct(), 2);
  let e0 = schema_root("root", 3);
  push_bytes(&mut m, &e0);
  let e1 = schema_leaf(1, 0, "id");
  push_bytes(&mut m, &e1);
  last = field_i64(&mut m, last, 3, 0);
  last = list_field(&mut m, last, 4, parquet_compact_struct(), 0);
  stop(&mut m);
  return m;
}

fn schema_negative_meta() -> Vec[UInt8] {
  var m = Vec[UInt8].new();
  var last = 0;
  last = field_i32(&mut m, last, 1, 1);
  last = list_field(&mut m, last, 2, parquet_compact_struct(), 1);
  let e0 = schema_root("root", 0 - 1);
  push_bytes(&mut m, &e0);
  last = field_i64(&mut m, last, 3, 0);
  last = list_field(&mut m, last, 4, parquet_compact_struct(), 0);
  stop(&mut m);
  return m;
}

fn t20() -> Int {
  let meta = schema_overclaim_meta();
  let buf = wrap(&meta, 0);
  let want = "parquet: schema element count does not match num_children at offset 4";
  if !file_err_is(parquet_parse(&buf), want) {
    return report(false, "over-claimed children rejected");
  }
  var m2 = Vec[UInt8].new();
  var last = 0;
  last = field_i32(&mut m2, last, 1, 1);
  last = list_field(&mut m2, last, 2, parquet_compact_struct(), 2);
  let e0 = schema_root("root", 0);
  push_bytes(&mut m2, &e0);
  let e1 = schema_leaf(1, 0, "id");
  push_bytes(&mut m2, &e1);
  last = field_i64(&mut m2, last, 3, 0);
  last = list_field(&mut m2, last, 4, parquet_compact_struct(), 0);
  stop(&mut m2);
  let buf2 = wrap(&m2, 0);
  if !file_err_is(parquet_parse(&buf2), want) {
    return report(false, "extra schema element rejected");
  }
  let neg = schema_negative_meta();
  let buf3 = wrap(&neg, 0);
  let want3 = "parquet: schema element has negative num_children at offset 4";
  if !file_err_is(parquet_parse(&buf3), want3) {
    return report(false, "negative num_children rejected");
  }
  return report(true, "schema tree structural errors");
}

fn main() -> Int {
  io.println("=== xiom.parquet conformance tests ===");
  var failed: Int = 0;
  failed = failed + t1();
  failed = failed + t2();
  failed = failed + t3();
  failed = failed + t4();
  failed = failed + t5();
  failed = failed + t6();
  failed = failed + t7();
  failed = failed + t8();
  failed = failed + t9();
  failed = failed + t10();
  failed = failed + t11();
  failed = failed + t12();
  failed = failed + t13();
  failed = failed + t14();
  failed = failed + t15();
  failed = failed + t16();
  failed = failed + t17();
  failed = failed + t18();
  failed = failed + t19();
  failed = failed + t20();
  if failed == 0 {
    io.println("xiom.parquet: all tests passed");
  } else {
    io.println("xiom.parquet: tests failed");
  }
  return failed;
}
