// XIOM -- xiom.safetensors conformance tests (21 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API: container prefix decoding, builder layout
// (little-endian length, space padding to 8-byte alignment, payload
// concatenation), parser accessors, payload extraction, dtype/shape
// helpers, valid and invalid string escapes, every documented validation
// error (duplicates, unknown/missing keys, negative integers, offsets,
// shape size) and builder validation. Round-trips go through
// st_builder_finish -> st_parse -> st_tensor_bytes.
//
// Harness style mirrors xiom.hello / xiom.msgpack: one fn tN() -> TestResult
// per check, called directly from main; main prints [PASS]/[FAIL] and
// returns the failure count. Str payloads are compared with str_compare
// (BUG 17 discipline: `==` on Str values read from a Vec lowers to a
// pointer comparison) and every Vec element read is bound to a typed local.

module safetensors_tests
use xiom.io; use xiom.test;
use xiom.string; use xiom.string.compare; use xiom.string.builder;
use xiom.safetensors;

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

// Result error predicates with diagnostic names.
fn expect_file_err(r: Result[SafetensorsFile, Str], want: Str, name: Str) -> TestResult {
  if r.is_ok {
    return assert(false, name + " (expected Err)");
  }
  let got: Str = r.error;
  if !str_eq(got, want) {
    return assert(false, name + " (got: " + got + ")");
  }
  return assert(true, name);
}

fn expect_int_err(r: Result[Int, Str], want: Str, name: Str) -> TestResult {
  if r.is_ok {
    return assert(false, name + " (expected Err)");
  }
  let got: Str = r.error;
  if !str_eq(got, want) {
    return assert(false, name + " (got: " + got + ")");
  }
  return assert(true, name);
}

fn expect_str_err(r: Result[Str, Str], want: Str, name: Str) -> TestResult {
  if r.is_ok {
    return assert(false, name + " (expected Err)");
  }
  let got: Str = r.error;
  if !str_eq(got, want) {
    return assert(false, name + " (got: " + got + ")");
  }
  return assert(true, name);
}

fn expect_bytes_err(r: Result[Vec[UInt8], Str], want: Str, name: Str) -> TestResult {
  if r.is_ok {
    return assert(false, name + " (expected Err)");
  }
  let got: Str = r.error;
  if !str_eq(got, want) {
    return assert(false, name + " (got: " + got + ")");
  }
  return assert(true, name);
}

// --------------------------------------------------
//  Byte helpers
// --------------------------------------------------

fn bytes_of(s: Str) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  builder.sb_push_str(&mut v, s);
  return v;
}

fn repeat_byte(b: Int, n: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < n {
    v.push(b as UInt8);
    i = i + 1;
  }
  return v;
}

fn cat(a: Vec[UInt8], b: Vec[UInt8]) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < a.len() {
    let x: UInt8 = a[i];
    v.push(x);
    i = i + 1;
  }
  var j = 0;
  while j < b.len() {
    let y: UInt8 = b[j];
    v.push(y);
    j = j + 1;
  }
  return v;
}

fn bytes_equal(a: Vec[UInt8], b: Vec[UInt8]) -> Bool {
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

fn bytes_at_equal(a: Vec[UInt8], base: Int, prefix: Vec[UInt8]) -> Bool {
  if a.len() < base + prefix.len() {
    return false;
  }
  var i = 0;
  while i < prefix.len() {
    let x: UInt8 = a[base + i];
    let y: UInt8 = prefix[i];
    if x != y {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn take_first(v: Vec[UInt8], n: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < n && i < v.len() {
    let x: UInt8 = v[i];
    out.push(x);
    i = i + 1;
  }
  return out;
}

fn le64(n: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var q = n;
  var k = 0;
  while k < 8 {
    var r = q % 256;
    if r < 0 { r = r + 256; }
    v.push(r as UInt8);
    q = (q - r) / 256;
    k = k + 1;
  }
  return v;
}

fn le64_at(v: Vec[UInt8], base: Int) -> Int {
  var acc: Int = 0;
  var mul: Int = 1;
  var k = 0;
  while k < 8 {
    let b: UInt8 = v[base + k];
    let bi = (b as Int) & 0xFF;
    acc = acc + bi * mul;
    mul = mul * 256;
    k = k + 1;
  }
  return acc;
}

// Container from a raw header string and payload; the header is written
// verbatim (no padding), which st_parse accepts.
fn raw_container(header: Str, payload: Vec[UInt8]) -> Vec[UInt8] {
  let head_bytes = bytes_of(header);
  let prefix = le64(string.str_len(header));
  return cat(prefix, cat(head_bytes, payload));
}

fn one_byte() -> Vec[UInt8] {
  return repeat_byte(9, 1);
}

// The canonical one-tensor container used by several checks: "weight",
// F32, shape [2, 3], 24 payload bytes of value 7.
fn build_single() -> Vec[UInt8] {
  var b = st_builder_new();
  var dims = Vec[Int].new();
  dims.push(2);
  dims.push(3);
  var data = repeat_byte(7, 24);
  let ar = st_builder_add(&mut b, "weight", "F32", &dims, &data);
  if !ar.is_ok {
    return Vec[UInt8].new();
  }
  return st_builder_finish(&b);
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  var b = st_builder_new();
  let c = st_builder_finish(&b);
  let r = st_parse(&c);
  if !r.is_ok {
    return assert(false, "empty container parses");
  }
  let f: SafetensorsFile = r.value;
  var ok = st_tensor_count(&f) == 0;
  if st_header_len(&f) % 8 != 0 { ok = false; }
  if st_data_start(&f) != 8 + st_header_len(&f) { ok = false; }
  if st_data_len(&f) != 0 { ok = false; }
  if c.len() != st_data_start(&f) { ok = false; }
  return assert(ok, "empty container: zero tensors, 8-aligned header, empty data section");
}

fn t2() -> TestResult {
  let c = build_single();
  let r = st_parse(&c);
  if !r.is_ok {
    return assert(false, "single-tensor container parses");
  }
  let f: SafetensorsFile = r.value;
  let nr = st_tensor_name(&f, 0);
  let dr = st_tensor_dtype(&f, 0);
  let rk = st_tensor_rank(&f, 0);
  let d0 = st_tensor_dim(&f, 0, 0);
  let d1 = st_tensor_dim(&f, 0, 1);
  let s0 = st_tensor_offset_start(&f, 0);
  let s1 = st_tensor_offset_end(&f, 0);
  let ln = st_tensor_data_len(&f, 0);
  var ok = st_tensor_count(&f) == 1;
  if !nr.is_ok { ok = false; } elif !str_eq(nr.value, "weight") { ok = false; }
  if !dr.is_ok { ok = false; } elif !str_eq(dr.value, "F32") { ok = false; }
  if !rk.is_ok { ok = false; } elif rk.value != 2 { ok = false; }
  if !d0.is_ok { ok = false; } elif d0.value != 2 { ok = false; }
  if !d1.is_ok { ok = false; } elif d1.value != 3 { ok = false; }
  if !s0.is_ok { ok = false; } elif s0.value != 0 { ok = false; }
  if !s1.is_ok { ok = false; } elif s1.value != 24 { ok = false; }
  if !ln.is_ok { ok = false; } elif ln.value != 24 { ok = false; }
  return assert(ok, "single F32 tensor: name/dtype/rank/dims/offsets/length");
}

fn t3() -> TestResult {
  var b = st_builder_new();
  var dims = Vec[Int].new();
  dims.push(4);
  var data = Vec[UInt8].new();
  data.push(10 as UInt8);
  data.push(20 as UInt8);
  data.push(30 as UInt8);
  data.push(40 as UInt8);
  let ar = st_builder_add(&mut b, "v", "U8", &dims, &data);
  if !ar.is_ok {
    return assert(false, "builder add U8 tensor");
  }
  let c = st_builder_finish(&b);
  let r = st_parse(&c);
  if !r.is_ok {
    return assert(false, "payload container parses");
  }
  let f: SafetensorsFile = r.value;
  let br = st_tensor_bytes(&f, 0, &c);
  if !br.is_ok {
    return assert(false, "tensor bytes copy");
  }
  let got: Vec[UInt8] = br.value;
  return assert(bytes_equal(got, data), "tensor payload bytes round-trip");
}

fn t4() -> TestResult {
  var b = st_builder_new();
  var da = Vec[Int].new();
  da.push(4);
  var pa = Vec[UInt8].new();
  pa.push(1 as UInt8);
  pa.push(2 as UInt8);
  pa.push(3 as UInt8);
  pa.push(4 as UInt8);
  let a1 = st_builder_add(&mut b, "a", "U8", &da, &pa);
  var db = Vec[Int].new();
  db.push(3);
  var pb = Vec[UInt8].new();
  pb.push(1 as UInt8);
  pb.push(0 as UInt8);
  pb.push(2 as UInt8);
  pb.push(0 as UInt8);
  pb.push(3 as UInt8);
  pb.push(0 as UInt8);
  let a2 = st_builder_add(&mut b, "b", "I16", &db, &pb);
  if !a1.is_ok || !a2.is_ok {
    return assert(false, "two-tensor builder adds");
  }
  if st_builder_tensor_count(&b) != 2 {
    return assert(false, "builder tensor count");
  }
  if st_builder_payload_len(&b) != 10 {
    return assert(false, "builder payload concatenation length");
  }
  let c = st_builder_finish(&b);
  let r = st_parse(&c);
  if !r.is_ok {
    return assert(false, "two-tensor container parses");
  }
  let f: SafetensorsFile = r.value;
  let a_s0 = st_tensor_offset_start(&f, 0);
  let a_e0 = st_tensor_offset_end(&f, 0);
  let b_s0 = st_tensor_offset_start(&f, 1);
  let b_e0 = st_tensor_offset_end(&f, 1);
  var ok = st_data_len(&f) == 10;
  if !a_s0.is_ok { ok = false; } elif a_s0.value != 0 { ok = false; }
  if !a_e0.is_ok { ok = false; } elif a_e0.value != 4 { ok = false; }
  if !b_s0.is_ok { ok = false; } elif b_s0.value != 4 { ok = false; }
  if !b_e0.is_ok { ok = false; } elif b_e0.value != 10 { ok = false; }
  let br = st_tensor_bytes(&f, 1, &c);
  if !br.is_ok { ok = false; } else {
    let bv: Vec[UInt8] = br.value;
    if !bytes_equal(bv, pb) { ok = false; }
  }
  let rk = st_tensor_rank(&f, 1);
  if !rk.is_ok { ok = false; } elif rk.value != 1 { ok = false; }
  return assert(ok, "two tensors: concatenated offsets, second payload and rank");
}

fn t5() -> TestResult {
  var b = st_builder_new();
  var dims = Vec[Int].new();
  dims.push(2);
  dims.push(3);
  var data = repeat_byte(7, 24);
  let ar = st_builder_add(&mut b, "weight", "F32", &dims, &data);
  if !ar.is_ok {
    return assert(false, "builder add for layout test");
  }
  let raw = st_builder_header_json(&b);
  let c = st_builder_finish(&b);
  let r = st_parse(&c);
  if !r.is_ok {
    return assert(false, "layout container parses");
  }
  let f: SafetensorsFile = r.value;
  let rawlen = string.str_len(raw);
  var padded = rawlen;
  while padded % 8 != 0 {
    padded = padded + 1;
  }
  var ok = st_header_len(&f) == padded;
  if padded % 8 != 0 { ok = false; }
  let head_bytes = bytes_of(raw);
  if !bytes_at_equal(c, 8, head_bytes) { ok = false; }
  if le64_at(c, 0) != padded { ok = false; }
  var k = 8 + rawlen;
  while k < 8 + padded {
    let pb: UInt8 = c[k];
    let pi = (pb as Int) & 0xFF;
    if pi != 32 { ok = false; }
    k = k + 1;
  }
  let db: UInt8 = c[st_data_start(&f)];
  let di = (db as Int) & 0xFF;
  if di != 7 { ok = false; }
  return assert(ok, "builder layout: LE u64 N, JSON prefix, space padding, payload start");
}

fn t6() -> TestResult {
  let h = "{\"x\":{\"dtype\":\"I8\",\"shape\":[3],\"data_offsets\":[0,3]}}";
  var p = Vec[UInt8].new();
  p.push(1 as UInt8);
  p.push(2 as UInt8);
  p.push(3 as UInt8);
  let c = raw_container(h, p);
  let r = st_parse(&c);
  if !r.is_ok {
    return assert(false, "manual unpadded header parses");
  }
  let f: SafetensorsFile = r.value;
  let nr = st_tensor_name(&f, 0);
  let dr = st_tensor_dtype(&f, 0);
  let pr = st_tensor_bytes(&f, 0, &c);
  var ok = st_tensor_count(&f) == 1;
  if st_header_len(&f) != string.str_len(h) { ok = false; }
  if !nr.is_ok { ok = false; } elif !str_eq(nr.value, "x") { ok = false; }
  if !dr.is_ok { ok = false; } elif !str_eq(dr.value, "I8") { ok = false; }
  if !pr.is_ok { ok = false; } else {
    let pv: Vec[UInt8] = pr.value;
    if !bytes_equal(pv, p) { ok = false; }
  }
  return assert(ok, "manual unpadded header: accessors and payload");
}

fn t7() -> TestResult {
  var ok = st_dtype_size("F64") == 8;
  if st_dtype_size("F32") != 4 { ok = false; }
  if st_dtype_size("F16") != 2 { ok = false; }
  if st_dtype_size("BF16") != 2 { ok = false; }
  if st_dtype_size("I64") != 8 { ok = false; }
  if st_dtype_size("I32") != 4 { ok = false; }
  if st_dtype_size("I16") != 2 { ok = false; }
  if st_dtype_size("I8") != 1 { ok = false; }
  if st_dtype_size("U8") != 1 { ok = false; }
  if st_dtype_size("BOOL") != 1 { ok = false; }
  if st_dtype_size("F8_E4M3") != 1 { ok = false; }
  if st_dtype_size("F8_E5M2") != 1 { ok = false; }
  if st_dtype_size("I4") != 0 { ok = false; }
  if st_dtype_size("") != 0 { ok = false; }
  var s = Vec[Int].new();
  s.push(2);
  s.push(3);
  s.push(4);
  if st_shape_element_count(&s) != 24 { ok = false; }
  var z = Vec[Int].new();
  z.push(0);
  z.push(5);
  if st_shape_element_count(&z) != 0 { ok = false; }
  var e = Vec[Int].new();
  if st_shape_element_count(&e) != 1 { ok = false; }
  var neg = Vec[Int].new();
  neg.push(-1);
  if st_shape_element_count(&neg) != -1 { ok = false; }
  var big = Vec[Int].new();
  big.push(9223372036854775807);
  big.push(2);
  if st_shape_element_count(&big) != -1 { ok = false; }
  return assert(ok, "dtype size table (incl. opaque 0) and shape element counts");
}

fn t8() -> TestResult {
  var empty = Vec[UInt8].new();
  let r0 = st_parse(&empty);
  let f0 = expect_file_err(r0, "safetensors: buffer too small for header length", "empty buffer rejected");
  if !f0.passed { return f0; }
  let seven = repeat_byte(0, 7);
  let r1 = st_parse(&seven);
  let f1 = expect_file_err(r1, "safetensors: buffer too small for header length", "7-byte buffer rejected");
  if !f1.passed { return f1; }
  let z = le64(0);
  let r2 = st_parse(&z);
  let f2 = expect_file_err(r2, "safetensors: header is empty", "N=0 header rejected");
  if !f2.passed { return f2; }
  let nothing = Vec[UInt8].new();
  let big = cat(le64(999), nothing);
  let r3 = st_parse(&big);
  let f3 = expect_file_err(r3, "safetensors: header length exceeds buffer", "N beyond buffer rejected");
  if !f3.passed { return f3; }
  return assert(true, "container-level errors: short buffer, empty header, oversized N");
}

fn t9() -> TestResult {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < 4 {
    v.push(0 as UInt8);
    i = i + 1;
  }
  v.push(0 as UInt8);
  v.push(0 as UInt8);
  v.push(0 as UInt8);
  v.push(128 as UInt8);
  let r = st_parse(&v);
  return expect_file_err(r, "safetensors: header length out of range", "u64 header length above INT64_MAX rejected");
}

fn t10() -> TestResult {
  var v = le64(3);
  v.push(123 as UInt8);
  v.push(0 as UInt8);
  v.push(125 as UInt8);
  let r = st_parse(&v);
  return expect_file_err(r, "safetensors: header contains NUL byte", "NUL byte in header rejected");
}

fn t11() -> TestResult {
  let e1 = Vec[UInt8].new();
  let c1 = raw_container("[", e1);
  let r1 = st_parse(&c1);
  let f1 = expect_file_err(r1, "safetensors: expected '{' at byte 0", "non-object header rejected");
  if !f1.passed { return f1; }
  let e2 = Vec[UInt8].new();
  let c2 = raw_container("{\"a\"}", e2);
  let r2 = st_parse(&c2);
  let f2 = expect_file_err(r2, "safetensors: expected ':' at byte 4", "missing colon rejected");
  if !f2.passed { return f2; }
  let e3 = Vec[UInt8].new();
  let c3 = raw_container("{\"a\":1}", e3);
  let r3 = st_parse(&c3);
  let f3 = expect_file_err(r3, "safetensors: tensor value must be an object at byte 5", "non-object tensor value rejected");
  if !f3.passed { return f3; }
  let e4 = Vec[UInt8].new();
  let c4 = raw_container("{} x", e4);
  let r4 = st_parse(&c4);
  let f4 = expect_file_err(r4, "safetensors: trailing data at byte 3", "trailing data rejected");
  if !f4.passed { return f4; }
  let e5 = Vec[UInt8].new();
  let c5 = raw_container("{\"a\":{}}", e5);
  let r5 = st_parse(&c5);
  let f5 = expect_file_err(r5, "safetensors: tensor object is empty", "empty tensor object rejected");
  if !f5.passed { return f5; }
  return assert(true, "structural errors: '{', ':', object value, trailing data, empty object");
}

fn t12() -> TestResult {
  let h1 = "{\"a\\u0041b\":{\"dtype\":\"U8\",\"shape\":[1],\"data_offsets\":[0,1]}}";
  let p1 = one_byte();
  let c1 = raw_container(h1, p1);
  let r1 = st_parse(&c1);
  if !r1.is_ok {
    return assert(false, "\\u0041 escape parses");
  }
  let f1: SafetensorsFile = r1.value;
  let n1 = st_tensor_name(&f1, 0);
  if !n1.is_ok {
    return assert(false, "escaped name accessor");
  }
  if !str_eq(n1.value, "aAb") {
    return assert(false, "\\u0041 escape value");
  }

  let h2 = "{\"q\\\"w\\\\e\\nx\\ty\":{\"dtype\":\"U8\",\"shape\":[1],\"data_offsets\":[0,1]}}";
  let p2 = one_byte();
  let c2 = raw_container(h2, p2);
  let r2 = st_parse(&c2);
  if !r2.is_ok {
    return assert(false, "quote/backslash/LF/TAB escapes parse");
  }
  let f2: SafetensorsFile = r2.value;
  let n2 = st_tensor_name(&f2, 0);
  if !n2.is_ok {
    return assert(false, "escaped name accessor 2");
  }
  if !str_eq(n2.value, "q\"w\\e\nx\ty") {
    return assert(false, "quote/backslash/LF/TAB escape value");
  }

  let e3 = Vec[UInt8].new();
  let c3 = raw_container("{\"a\\u0080b\":{\"dtype\":\"U8\",\"shape\":[1],\"data_offsets\":[0,1]}}", e3);
  let r3 = st_parse(&c3);
  let f3 = expect_file_err(r3, "safetensors: non-printable \\u escape at byte 4", "non-ASCII \\u escape rejected");
  if !f3.passed { return f3; }

  let e4 = Vec[UInt8].new();
  let c4 = raw_container("{\"a\\qb\":{\"dtype\":\"U8\",\"shape\":[1],\"data_offsets\":[0,1]}}", e4);
  let r4 = st_parse(&c4);
  let f4 = expect_file_err(r4, "safetensors: unsupported escape at byte 4", "unsupported escape rejected");
  if !f4.passed { return f4; }

  var hb = Vec[UInt8].new();
  builder.sb_push_str(&mut hb, "{\"a");
  hb.push(128 as UInt8);
  builder.sb_push_str(&mut hb, "b\":{\"dtype\":\"U8\",\"shape\":[1],\"data_offsets\":[0,1]}}");
  let c5 = cat(le64(hb.len()), hb);
  let r5 = st_parse(&c5);
  let f5 = expect_file_err(r5, "safetensors: non-ASCII byte in string at byte 3", "raw non-ASCII byte rejected");
  if !f5.passed { return f5; }
  return assert(true, "string escapes: valid \\u/quote/backslash/LF/TAB, invalid \\u0080/\\q/raw 0x80");
}

fn t13() -> TestResult {
  let h = "{\"t\":{\"dtype\":\"U8\",\"shape\":[1],\"data_offsets\":[0,1]},\"t\":{\"dtype\":\"U8\",\"shape\":[1],\"data_offsets\":[0,1]}}";
  let p = repeat_byte(1, 2);
  let c = raw_container(h, p);
  let r = st_parse(&c);
  return expect_file_err(r, "safetensors: duplicate tensor name 't'", "duplicate tensor name rejected");
}

fn t14() -> TestResult {
  let e1 = Vec[UInt8].new();
  let c1 = raw_container("{\"a\":{\"dtype\":\"U8\",\"shape\":[1]}}", e1);
  let r1 = st_parse(&c1);
  let f1 = expect_file_err(r1, "safetensors: missing key 'data_offsets'", "missing data_offsets rejected");
  if !f1.passed { return f1; }
  let p2 = one_byte();
  let c2 = raw_container("{\"a\":{\"shape\":[1],\"data_offsets\":[0,1]}}", p2);
  let r2 = st_parse(&c2);
  let f2 = expect_file_err(r2, "safetensors: missing key 'dtype'", "missing dtype rejected");
  if !f2.passed { return f2; }
  let p3 = one_byte();
  let c3 = raw_container("{\"a\":{\"dtype\":\"U8\",\"data_offsets\":[0,1]}}", p3);
  let r3 = st_parse(&c3);
  let f3 = expect_file_err(r3, "safetensors: missing key 'shape'", "missing shape rejected");
  if !f3.passed { return f3; }
  return assert(true, "missing keys: dtype, shape and data_offsets are all mandatory");
}

fn t15() -> TestResult {
  let e1 = Vec[UInt8].new();
  let c1 = raw_container("{\"__metadata__\":{\"format\":\"pt\"}}", e1);
  let r1 = st_parse(&c1);
  let f1 = expect_file_err(r1, "safetensors: '__metadata__' metadata objects are not supported", "__metadata__ rejected");
  if !f1.passed { return f1; }
  let p2 = one_byte();
  let c2 = raw_container("{\"a\":{\"dtype\":\"U8\",\"shape\":[1],\"data_offsets\":[0,1],\"x\":2}}", p2);
  let r2 = st_parse(&c2);
  let f2 = expect_file_err(r2, "safetensors: unknown tensor key 'x'", "unknown tensor key rejected");
  if !f2.passed { return f2; }
  return assert(true, "nested metadata and unknown tensor keys are rejected");
}

fn t16() -> TestResult {
  let e1 = Vec[UInt8].new();
  let c1 = raw_container("{\"a\":{\"dtype\":\"U8\",\"shape\":[1],\"data_offsets\":[5,1]}}", e1);
  let r1 = st_parse(&c1);
  let f1 = expect_file_err(r1, "safetensors: data_offsets start > end for tensor 'a'", "start > end rejected");
  if !f1.passed { return f1; }
  let p2 = one_byte();
  let c2 = raw_container("{\"a\":{\"dtype\":\"U8\",\"shape\":[1],\"data_offsets\":[0,2]}}", p2);
  let r2 = st_parse(&c2);
  let f2 = expect_file_err(r2, "safetensors: data_offsets exceed data section for tensor 'a'", "offset beyond data section rejected");
  if !f2.passed { return f2; }
  let p3 = repeat_byte(1, 2);
  let c3 = raw_container("{\"a\":{\"dtype\":\"U8\",\"shape\":[1],\"data_offsets\":[0,1]},\"b\":{\"dtype\":\"U8\",\"shape\":[1],\"data_offsets\":[0,1]}}", p3);
  let r3 = st_parse(&c3);
  let f3 = expect_file_err(r3, "safetensors: data_offsets not monotonic for tensor 'b'", "non-monotonic offsets rejected");
  if !f3.passed { return f3; }
  return assert(true, "offset validation: start > end, beyond data section, non-monotonic");
}

fn t17() -> TestResult {
  let p1 = repeat_byte(0, 20);
  let c1 = raw_container("{\"a\":{\"dtype\":\"F32\",\"shape\":[2,3],\"data_offsets\":[0,20]}}", p1);
  let r1 = st_parse(&c1);
  let f1 = expect_file_err(r1, "safetensors: shape size does not match data length for tensor 'a'", "F32 shape/size mismatch rejected");
  if !f1.passed { return f1; }

  let p2 = repeat_byte(0, 7);
  let c2 = raw_container("{\"a\":{\"dtype\":\"I4\",\"shape\":[100],\"data_offsets\":[0,7]}}", p2);
  let r2 = st_parse(&c2);
  if !r2.is_ok {
    return assert(false, "unknown dtype is passed through");
  }
  let f2: SafetensorsFile = r2.value;
  let d2 = st_tensor_dtype(&f2, 0);
  if !d2.is_ok {
    return assert(false, "unknown dtype accessor");
  }
  if !str_eq(d2.value, "I4") {
    return assert(false, "unknown dtype token round-trip");
  }
  if st_dtype_size("I4") != 0 {
    return assert(false, "unknown dtype width is 0");
  }

  let p3 = repeat_byte(0, 4);
  let c3 = raw_container("{\"s\":{\"dtype\":\"F32\",\"shape\":[],\"data_offsets\":[0,4]}}", p3);
  let r3 = st_parse(&c3);
  if !r3.is_ok {
    return assert(false, "scalar (empty shape) parses");
  }
  let f3: SafetensorsFile = r3.value;
  let rk = st_tensor_rank(&f3, 0);
  if !rk.is_ok {
    return assert(false, "scalar rank accessor");
  }
  if rk.value != 0 {
    return assert(false, "scalar rank is 0");
  }
  return assert(true, "shape validation: fixed-width mismatch, opaque dtype pass-through, scalar");
}

fn t18() -> TestResult {
  var b = st_builder_new();
  var d1 = Vec[Int].new();
  d1.push(1);
  var p1 = one_byte();
  let e1 = st_builder_add(&mut b, "", "U8", &d1, &p1);
  let f1 = expect_int_err(e1, "safetensors: builder: tensor name must not be empty", "empty builder name rejected");
  if !f1.passed { return f1; }
  let e2 = st_builder_add(&mut b, "wé", "U8", &d1, &p1);
  let f2 = expect_int_err(e2, "safetensors: builder: tensor name must be printable ASCII", "non-ASCII builder name rejected");
  if !f2.passed { return f2; }
  let e3 = st_builder_add(&mut b, "d", "", &d1, &p1);
  let f3 = expect_int_err(e3, "safetensors: builder: dtype must not be empty", "empty builder dtype rejected");
  if !f3.passed { return f3; }
  let a4 = st_builder_add(&mut b, "w", "U8", &d1, &p1);
  if !a4.is_ok {
    return assert(false, "valid builder add");
  }
  let e5 = st_builder_add(&mut b, "w", "U8", &d1, &p1);
  let f5 = expect_int_err(e5, "safetensors: builder: duplicate tensor name 'w'", "duplicate builder name rejected");
  if !f5.passed { return f5; }
  var dn = Vec[Int].new();
  dn.push(-1);
  let e6 = st_builder_add(&mut b, "neg", "U8", &dn, &p1);
  let f6 = expect_int_err(e6, "safetensors: builder: negative dimension for tensor 'neg'", "negative builder dimension rejected");
  if !f6.passed { return f6; }
  var d32 = Vec[Int].new();
  d32.push(2);
  d32.push(3);
  var p20 = repeat_byte(0, 20);
  let e7 = st_builder_add(&mut b, "m", "F32", &d32, &p20);
  let f7 = expect_int_err(e7, "safetensors: builder: data length does not match shape for tensor 'm'", "builder shape/size mismatch rejected");
  if !f7.passed { return f7; }
  let a8 = st_builder_add(&mut b, "u", "I4", &d1, &p20);
  if !a8.is_ok {
    return assert(false, "opaque dtype skips builder size check");
  }
  if st_builder_tensor_count(&b) != 2 {
    return assert(false, "builder count after errors");
  }
  return assert(true, "builder validation: empty/non-ASCII name, empty dtype, duplicate, negative dim, size mismatch, opaque pass-through");
}

fn t19() -> TestResult {
  let c = build_single();
  let r = st_parse(&c);
  if !r.is_ok {
    return assert(false, "range container parses");
  }
  let f: SafetensorsFile = r.value;
  let found = st_find_tensor(&f, "weight");
  if !found.is_ok {
    return assert(false, "find existing tensor");
  }
  if found.value != 0 {
    return assert(false, "find existing tensor index");
  }
  let missing = st_find_tensor(&f, "nope");
  let m = expect_int_err(missing, "safetensors: tensor not found: 'nope'", "find missing tensor rejected");
  if !m.passed { return m; }
  let n1 = st_tensor_name(&f, -1);
  let x1 = expect_str_err(n1, "safetensors: tensor index out of range", "name(-1) rejected");
  if !x1.passed { return x1; }
  let n2 = st_tensor_name(&f, 1);
  let x2 = expect_str_err(n2, "safetensors: tensor index out of range", "name(count) rejected");
  if !x2.passed { return x2; }
  let n3 = st_tensor_dtype(&f, 3);
  let x3 = expect_str_err(n3, "safetensors: tensor index out of range", "dtype(bad index) rejected");
  if !x3.passed { return x3; }
  let n4 = st_tensor_rank(&f, 1);
  let x4 = expect_int_err(n4, "safetensors: tensor index out of range", "rank(bad index) rejected");
  if !x4.passed { return x4; }
  let n5 = st_tensor_dim(&f, 0, 2);
  let x5 = expect_int_err(n5, "safetensors: dim index out of range", "dim(0, rank) rejected");
  if !x5.passed { return x5; }
  let n6 = st_tensor_dim(&f, 0, -1);
  let x6 = expect_int_err(n6, "safetensors: dim index out of range", "dim(0, -1) rejected");
  if !x6.passed { return x6; }
  return assert(true, "find_tensor and out-of-range accessor errors");
}

fn t20() -> TestResult {
  let c = build_single();
  let r = st_parse(&c);
  if !r.is_ok {
    return assert(false, "truncation container parses");
  }
  let f: SafetensorsFile = r.value;
  let short = take_first(c, 10);
  let br = st_tensor_bytes(&f, 0, &short);
  let b = expect_bytes_err(br, "safetensors: container is smaller than the tensor data", "short container rejected");
  if !b.passed { return b; }
  let bad = st_tensor_bytes(&f, 5, &c);
  let bb = expect_bytes_err(bad, "safetensors: tensor index out of range", "tensor_bytes(bad index) rejected");
  if !bb.passed { return bb; }
  return assert(true, "tensor bytes: short container and bad index errors");
}

fn t21() -> TestResult {
  let p1 = one_byte();
  let c1 = raw_container("{\"a\":{\"dtype\":\"U8\",\"shape\":[-1],\"data_offsets\":[0,1]}}", p1);
  let r1 = st_parse(&c1);
  let f1 = expect_file_err(r1, "safetensors: negative integers are not supported at byte 28", "negative shape integer rejected");
  if !f1.passed { return f1; }

  let p2 = one_byte();
  let c2 = raw_container("{\"a\":{\"dtype\":\"U8\",\"shape\":[1.5],\"data_offsets\":[0,1]}}", p2);
  let r2 = st_parse(&c2);
  let f2 = expect_file_err(r2, "safetensors: expected ',' or ']' at byte 29", "float shape token rejected");
  if !f2.passed { return f2; }

  let p3 = one_byte();
  let c3 = raw_container("{\"a\":{\"dtype\":\"U8\",\"shape\":[01],\"data_offsets\":[0,1]}}", p3);
  let r3 = st_parse(&c3);
  let f3 = expect_file_err(r3, "safetensors: leading zero in integer at byte 28", "leading zero rejected");
  if !f3.passed { return f3; }

  let p4 = one_byte();
  let c4 = raw_container("{\"a\":{\"dtype\":\"U8\",\"shape\":[99999999999999999999],\"data_offsets\":[0,1]}}", p4);
  let r4 = st_parse(&c4);
  let f4 = expect_file_err(r4, "safetensors: integer out of range at byte 28", "oversized integer rejected");
  if !f4.passed { return f4; }

  let e5 = Vec[UInt8].new();
  let c5 = raw_container("{\"a\":{\"dtype\":null}}", e5);
  let r5 = st_parse(&c5);
  let f5 = expect_file_err(r5, "safetensors: dtype must be a string at byte 14", "null dtype rejected");
  if !f5.passed { return f5; }

  let p6 = one_byte();
  let c6 = raw_container("{\"\":{\"dtype\":\"U8\",\"shape\":[1],\"data_offsets\":[0,1]}}", p6);
  let r6 = st_parse(&c6);
  let f6 = expect_file_err(r6, "safetensors: tensor name must not be empty", "empty tensor name rejected");
  if !f6.passed { return f6; }
  return assert(true, "integer/value errors: negative, float token, leading zero, overflow, null dtype, empty name");
}

fn main() -> Int {
  io.println("=== xiom.safetensors conformance tests ===");
  var failed: Int = 0;
  let r1 = t1();
  failed = failed + report(r1.passed, r1.name);
  let r2 = t2();
  failed = failed + report(r2.passed, r2.name);
  let r3 = t3();
  failed = failed + report(r3.passed, r3.name);
  let r4 = t4();
  failed = failed + report(r4.passed, r4.name);
  let r5 = t5();
  failed = failed + report(r5.passed, r5.name);
  let r6 = t6();
  failed = failed + report(r6.passed, r6.name);
  let r7 = t7();
  failed = failed + report(r7.passed, r7.name);
  let r8 = t8();
  failed = failed + report(r8.passed, r8.name);
  let r9 = t9();
  failed = failed + report(r9.passed, r9.name);
  let r10 = t10();
  failed = failed + report(r10.passed, r10.name);
  let r11 = t11();
  failed = failed + report(r11.passed, r11.name);
  let r12 = t12();
  failed = failed + report(r12.passed, r12.name);
  let r13 = t13();
  failed = failed + report(r13.passed, r13.name);
  let r14 = t14();
  failed = failed + report(r14.passed, r14.name);
  let r15 = t15();
  failed = failed + report(r15.passed, r15.name);
  let r16 = t16();
  failed = failed + report(r16.passed, r16.name);
  let r17 = t17();
  failed = failed + report(r17.passed, r17.name);
  let r18 = t18();
  failed = failed + report(r18.passed, r18.name);
  let r19 = t19();
  failed = failed + report(r19.passed, r19.name);
  let r20 = t20();
  failed = failed + report(r20.passed, r20.name);
  let r21 = t21();
  failed = failed + report(r21.passed, r21.name);
  if failed == 0 {
    io.println("xiom.safetensors: all tests passed");
  } else {
    io.println("xiom.safetensors: tests failed");
  }
  return failed;
}
