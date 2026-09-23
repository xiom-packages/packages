// XIOM -- xiom.bson conformance tests (22 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API: exact little-endian document bytes, length
// patching for nested documents and arrays, key order, accessors for
// int32/int64/str/bool/null, array accessors, type_of/has, and the error
// catalog (missing field, wrong type, truncation, malformed length).
//
// Str payloads are compared with str_compare (BUG 17 discipline: `==` on
// Str values read from a Vec lowers to a pointer comparison).

module bson_tests
use xiom.io; use xiom.test;
use xiom.bson;
use xiom.string;
use xiom.string.compare;
use xiom.encoding.hex;

// Expected bytes for a hex string ("" on malformed input; the test then
// fails on the byte comparison).
fn hb(hexstr: Str) -> Vec[UInt8] {
  let r = hex.hex_decode(hexstr);
  match r {
    Ok(v) => { return v; },
    Err(_) => {},
  }
  return Vec[UInt8].new();
}

fn bytes_equal(a: Vec[UInt8], b: Vec[UInt8]) -> Bool {
  if a.len() != b.len() {
    return false;
  }
  var i = 0;
  while i < a.len() {
    if a[i] != b[i] {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn concat3(a: Vec[UInt8], b: Vec[UInt8], c: Vec[UInt8]) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < a.len() {
    v.push(a[i]);
    i = i + 1;
  }
  var j = 0;
  while j < b.len() {
    v.push(b[j]);
    j = j + 1;
  }
  var k = 0;
  while k < c.len() {
    v.push(c[k]);
    k = k + 1;
  }
  return v;
}

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn err_int_is(r: Result[Int, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_str_is(r: Result[Str, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_bool_is(r: Result[Bool, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn type_is(d: &Vec[UInt8], name: Str, want: Int) -> Bool {
  let o = bson_type_of(d, name);
  if !o.is_some {
    return false;
  }
  return o.value == want;
}

// --------------------------------------------------
//  Builder helpers (one document per shape)
// --------------------------------------------------

fn doc_int32(name: Str, v: Int) -> Vec[UInt8] {
  var w = bson_writer_new();
  bson_doc_start(&mut w);
  bson_element_int32(&mut w, name, v);
  bson_doc_end(&mut w);
  return bson_to_bytes(&w);
}

fn doc_int64(name: Str, v: Int) -> Vec[UInt8] {
  var w = bson_writer_new();
  bson_doc_start(&mut w);
  bson_element_int64(&mut w, name, v);
  bson_doc_end(&mut w);
  return bson_to_bytes(&w);
}

fn doc_str(name: Str, v: Str) -> Vec[UInt8] {
  var w = bson_writer_new();
  bson_doc_start(&mut w);
  bson_element_str(&mut w, name, v);
  bson_doc_end(&mut w);
  return bson_to_bytes(&w);
}

fn doc_bool(name: Str, v: Bool) -> Vec[UInt8] {
  var w = bson_writer_new();
  bson_doc_start(&mut w);
  bson_element_bool(&mut w, name, v);
  bson_doc_end(&mut w);
  return bson_to_bytes(&w);
}

fn doc_null(name: Str) -> Vec[UInt8] {
  var w = bson_writer_new();
  bson_doc_start(&mut w);
  bson_element_null(&mut w, name);
  bson_doc_end(&mut w);
  return bson_to_bytes(&w);
}

fn doc_nested() -> Vec[UInt8] {
  var w = bson_writer_new();
  bson_doc_start(&mut w);
  bson_element_doc_start(&mut w, "a");
  bson_element_int32(&mut w, "b", 1);
  bson_element_doc_end(&mut w);
  bson_doc_end(&mut w);
  return bson_to_bytes(&w);
}

fn doc_array() -> Vec[UInt8] {
  var w = bson_writer_new();
  bson_doc_start(&mut w);
  bson_element_array_start(&mut w, "a");
  bson_element_int32(&mut w, "0", 1);
  bson_element_int32(&mut w, "1", 2);
  bson_element_array_end(&mut w);
  bson_doc_end(&mut w);
  return bson_to_bytes(&w);
}

fn doc_three() -> Vec[UInt8] {
  var w = bson_writer_new();
  bson_doc_start(&mut w);
  bson_element_int32(&mut w, "b", 1);
  bson_element_str(&mut w, "a", "x");
  bson_element_bool(&mut w, "c", true);
  bson_doc_end(&mut w);
  return bson_to_bytes(&w);
}

fn doc_all() -> Vec[UInt8] {
  var w = bson_writer_new();
  bson_doc_start(&mut w);
  bson_element_int32(&mut w, "i32", 7);
  bson_element_int64(&mut w, "i64", 8);
  bson_element_str(&mut w, "s", "v");
  bson_element_bool(&mut w, "b", false);
  bson_element_null(&mut w, "n");
  bson_element_array_start(&mut w, "arr");
  bson_element_int32(&mut w, "0", 5);
  bson_element_array_end(&mut w);
  bson_element_doc_start(&mut w, "doc");
  bson_element_str(&mut w, "k", "v");
  bson_element_doc_end(&mut w);
  bson_doc_end(&mut w);
  return bson_to_bytes(&w);
}

// --------------------------------------------------
//  Round-trip helpers
// --------------------------------------------------

fn int32_roundtrip(v: Int) -> Bool {
  let d = doc_int32("x", v);
  let r = bson_get_int32(&d, "x");
  if !r.is_ok {
    return false;
  }
  return r.value == v;
}

fn int64_roundtrip(v: Int) -> Bool {
  let d = doc_int64("x", v);
  let r = bson_get_int64(&d, "x");
  if !r.is_ok {
    return false;
  }
  return r.value == v;
}

fn str_roundtrip(v: Str) -> Bool {
  let d = doc_str("x", v);
  let r = bson_get_str(&d, "x");
  if !r.is_ok {
    return false;
  }
  return str_eq(r.value, v);
}

fn bool_roundtrip(v: Bool) -> Bool {
  let d = doc_bool("x", v);
  let r = bson_get_bool(&d, "x");
  if !r.is_ok {
    return false;
  }
  return r.value == v;
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  var ok = bytes_equal(doc_int32("x", 16909060), hb("0c0000001078000403020100"));
  if !bytes_equal(doc_int32("x", 1), hb("0c0000001078000100000000")) { ok = false; }
  if !bytes_equal(doc_int32("x", -1), hb("0c000000107800ffffffff00")) { ok = false; }
  if !bytes_equal(doc_int32("x", -2147483648), hb("0c0000001078000000008000")) { ok = false; }
  return assert(ok, "int32 elements: little-endian exact bytes incl. negatives");
}

fn t2() -> TestResult {
  var ok = bytes_equal(doc_int64("x", 1), concat3(hb("10000000127800"), hb("0100000000000000"), hb("00")));
  if !bytes_equal(doc_int64("x", -1), concat3(hb("10000000127800"), hb("ffffffffffffffff"), hb("00"))) { ok = false; }
  if !bytes_equal(doc_int64("x", 4294967296), concat3(hb("10000000127800"), hb("0000000001000000"), hb("00"))) { ok = false; }
  let i64min = 0 - 9223372036854775807 - 1;
  if !bytes_equal(doc_int64("x", i64min), concat3(hb("10000000127800"), hb("0000000000000080"), hb("00"))) { ok = false; }
  return assert(ok, "int64 elements: little-endian exact bytes incl. INT64_MIN");
}

fn t3() -> TestResult {
  var ok = bytes_equal(doc_str("x", ""), hb("0d000000027800010000000000"));
  if !bytes_equal(doc_str("x", "abc"), hb("10000000027800040000006162630000")) { ok = false; }
  if !bytes_equal(doc_str("x", "héllo"), concat3(hb("13000000027800"), hb("0700000068c3a96c6c6f00"), hb("00"))) { ok = false; }
  return assert(ok, "string elements: length includes the trailing NUL");
}

fn t4() -> TestResult {
  var ok = bytes_equal(doc_bool("x", true), hb("090000000878000100"));
  if !bytes_equal(doc_bool("x", false), hb("090000000878000000")) { ok = false; }
  if !bytes_equal(doc_null("x"), hb("080000000a780000")) { ok = false; }
  return assert(ok, "bool and null elements: exact bytes");
}

fn t5() -> TestResult {
  let d = doc_nested();
  var ok = bytes_equal(d, concat3(hb("14000000036100"), hb("0c0000001062000100000000"), hb("00")));
  if !bson_is_valid(&d) { ok = false; }
  return assert(ok, "embedded document: inner and outer lengths patched");
}

fn t6() -> TestResult {
  let d = doc_array();
  var ok = bytes_equal(d, concat3(hb("1b000000046100"), hb("13000000103000010000001031000200000000"), hb("00")));
  if !bson_is_valid(&d) { ok = false; }
  return assert(ok, "array elements: numeric keys, inner and outer lengths patched");
}

fn t7() -> TestResult {
  let d = doc_three();
  let keys = bson_keys(&d);
  var ok = keys.len() == 3;
  if keys.len() == 3 {
    if !str_eq(keys[0], "b") { ok = false; }
    if !str_eq(keys[1], "a") { ok = false; }
    if !str_eq(keys[2], "c") { ok = false; }
  }
  return assert(ok, "bson_keys: top-level names in document order");
}

fn t8() -> TestResult {
  let empty = hb("0500000000");
  var ok = bson_keys(&empty).len() == 0;
  let bad = hb("0d0000001078000100000000");
  let bk = bson_keys(&bad);
  if bk.len() != 1 { ok = false; }
  if bk.len() == 1 {
    if !str_eq(bk[0], "") { ok = false; }
  }
  return assert(ok, "bson_keys: empty -> [], malformed -> [\"\"]");
}

fn t9() -> TestResult {
  var ok = int32_roundtrip(0);
  if !int32_roundtrip(1) { ok = false; }
  if !int32_roundtrip(-1) { ok = false; }
  if !int32_roundtrip(2147483647) { ok = false; }
  if !int32_roundtrip(-2147483648) { ok = false; }
  return assert(ok, "int32 accessor round-trips boundary values");
}

fn t10() -> TestResult {
  var ok = int64_roundtrip(0);
  if !int64_roundtrip(1) { ok = false; }
  if !int64_roundtrip(-1) { ok = false; }
  if !int64_roundtrip(4294967296) { ok = false; }
  if !int64_roundtrip(-4294967296) { ok = false; }
  let i64min = 0 - 9223372036854775807 - 1;
  if !int64_roundtrip(i64min) { ok = false; }
  return assert(ok, "int64 accessor round-trips boundary values");
}

fn t11() -> TestResult {
  var ok = str_roundtrip("");
  if !str_roundtrip("hello, bson") { ok = false; }
  if !str_roundtrip("héllo wörld") { ok = false; }
  if !str_roundtrip("日本語") { ok = false; }
  if !str_roundtrip("line1\nline2") { ok = false; }
  return assert(ok, "string accessor round-trips UTF-8 payloads");
}

fn t12() -> TestResult {
  var ok = bool_roundtrip(true);
  if !bool_roundtrip(false) { ok = false; }
  let dn = doc_null("n");
  if !bson_has(&dn, "n") { ok = false; }
  if !type_is(&dn, "n", 10) { ok = false; }
  if bson_get_bool(&dn, "n").is_ok { ok = false; }
  return assert(ok, "bool round-trips; null is present but not a bool");
}

fn t13() -> TestResult {
  let d = doc_nested();
  let r = bson_get_document(&d, "a");
  if !r.is_ok {
    return assert(false, "bson_get_document: nested bytes copied and re-readable");
  }
  let inner = r.value;
  var ok = bytes_equal(inner, hb("0c0000001062000100000000"));
  if !bson_is_valid(&inner) { ok = false; }
  let v = bson_get_int32(&inner, "b");
  if !v.is_ok { ok = false; } elif v.value != 1 { ok = false; }
  return assert(ok, "bson_get_document: nested bytes copied and re-readable");
}

fn t14() -> TestResult {
  let d = doc_array();
  let lr = bson_get_array_len(&d, "a");
  var ok = lr.is_ok && lr.value == 2;
  let v0 = bson_get_array_int32(&d, "a", 0);
  if !v0.is_ok { ok = false; } elif v0.value != 1 { ok = false; }
  let v1 = bson_get_array_int32(&d, "a", 1);
  if !v1.is_ok { ok = false; } elif v1.value != 2 { ok = false; }
  let v2 = bson_get_array_int32(&d, "a", 2);
  if v2.is_ok { ok = false; }
  if !err_int_is(v2, "bson: field not found: 2") { ok = false; }
  let s0 = bson_get_array_str(&d, "a", 0);
  if s0.is_ok { ok = false; }
  if !err_str_is(s0, "bson: unexpected type 0x10") { ok = false; }
  return assert(ok, "array accessors: length, indexed int32, bounds and type errors");
}

fn t15() -> TestResult {
  let d = doc_all();
  var ok = type_is(&d, "i32", 16);
  if !type_is(&d, "i64", 18) { ok = false; }
  if !type_is(&d, "s", 2) { ok = false; }
  if !type_is(&d, "b", 8) { ok = false; }
  if !type_is(&d, "n", 10) { ok = false; }
  if !type_is(&d, "arr", 4) { ok = false; }
  if !type_is(&d, "doc", 3) { ok = false; }
  let miss = bson_type_of(&d, "zzz");
  if miss.is_some { ok = false; }
  return assert(ok, "bson_type_of: type bytes for every supported type");
}

fn t16() -> TestResult {
  let d = doc_all();
  var ok = bson_has(&d, "i32");
  if !bson_has(&d, "arr") { ok = false; }
  if bson_has(&d, "missing") { ok = false; }
  let bad = hb("0d0000001078000100000000");
  if bson_has(&bad, "x") { ok = false; }
  return assert(ok, "bson_has: presence and malformed-document handling");
}

fn t17() -> TestResult {
  let d = doc_int32("i", 1);
  var ok = err_int_is(bson_get_int32(&d, "nope"), "bson: field not found: nope");
  if !err_int_is(bson_get_int64(&d, "nope"), "bson: field not found: nope") { ok = false; }
  if !err_str_is(bson_get_str(&d, "nope"), "bson: field not found: nope") { ok = false; }
  if !err_bool_is(bson_get_bool(&d, "nope"), "bson: field not found: nope") { ok = false; }
  return assert(ok, "missing fields Err(\"bson: field not found: <name>\")");
}

fn t18() -> TestResult {
  let d = doc_int32("i", 7);
  var ok = err_str_is(bson_get_str(&d, "i"), "bson: unexpected type 0x10");
  if !err_bool_is(bson_get_bool(&d, "i"), "bson: unexpected type 0x10") { ok = false; }
  if !err_int_is(bson_get_int64(&d, "i"), "bson: unexpected type 0x10") { ok = false; }
  let s = doc_str("s", "v");
  if !err_int_is(bson_get_int32(&s, "s"), "bson: unexpected type 0x02") { ok = false; }
  let n = doc_null("n");
  if !err_int_is(bson_get_int32(&n, "n"), "bson: unexpected type 0x0a") { ok = false; }
  return assert(ok, "wrong-type reads Err(\"bson: unexpected type 0xNN\")");
}

fn t19() -> TestResult {
  let cut = hb("0b00000010780001000000");
  var ok = err_int_is(bson_get_int32(&cut, "x"), "bson: truncated document");
  if bson_is_valid(&cut) { ok = false; }
  let noterm = hb("0c00000010780001000000ff");
  if !err_int_is(bson_get_int32(&noterm, "x"), "bson: truncated document") { ok = false; }
  if bson_is_valid(&noterm) { ok = false; }
  let tiny = hb("0100");
  if !err_int_is(bson_get_int32(&tiny, "x"), "bson: truncated document") { ok = false; }
  return assert(ok, "truncated documents Err(\"bson: truncated document\")");
}

fn t20() -> TestResult {
  let long = hb("0d0000001078000100000000");
  var ok = err_int_is(bson_get_int32(&long, "x"), "bson: malformed length");
  if bson_is_valid(&long) { ok = false; }
  let short = hb("0b0000001078000100000000");
  if !err_int_is(bson_get_int32(&short, "x"), "bson: malformed length") { ok = false; }
  let zlen = hb("0c0000000278000000000000");
  if !err_str_is(bson_get_str(&zlen, "x"), "bson: malformed length") { ok = false; }
  if bson_is_valid(&zlen) { ok = false; }
  return assert(ok, "inconsistent or non-positive lengths Err(\"bson: malformed length\")");
}

fn t21() -> TestResult {
  let e = hb("0500000000");
  var ok = bson_is_valid(&e);
  if bson_keys(&e).len() != 0 { ok = false; }
  if bson_has(&e, "x") { ok = false; }
  let o = bson_type_of(&e, "x");
  if o.is_some { ok = false; }
  if !err_int_is(bson_get_int32(&e, "x"), "bson: field not found: x") { ok = false; }
  let short = hb("04000000");
  if bson_is_valid(&short) { ok = false; }
  let nozero = hb("0500000001");
  if bson_is_valid(&nozero) { ok = false; }
  return assert(ok, "empty document is valid and readable; malformed shapes are not");
}

fn t22() -> TestResult {
  let d = doc_all();
  var ok = bson_is_valid(&d);
  let keys = bson_keys(&d);
  if keys.len() == 7 {
    if !str_eq(keys[0], "i32") { ok = false; }
    if !str_eq(keys[6], "doc") { ok = false; }
  } else {
    ok = false;
  }
  let a = bson_get_int32(&d, "i32");
  if !a.is_ok { ok = false; } elif a.value != 7 { ok = false; }
  let b = bson_get_int64(&d, "i64");
  if !b.is_ok { ok = false; } elif b.value != 8 { ok = false; }
  let s = bson_get_str(&d, "s");
  if !s.is_ok { ok = false; } elif !str_eq(s.value, "v") { ok = false; }
  let bl = bson_get_bool(&d, "b");
  if !bl.is_ok { ok = false; } elif bl.value { ok = false; }
  if !bson_has(&d, "n") { ok = false; }
  let al = bson_get_array_len(&d, "arr");
  if !al.is_ok { ok = false; } elif al.value != 1 { ok = false; }
  let ai = bson_get_array_int32(&d, "arr", 0);
  if !ai.is_ok { ok = false; } elif ai.value != 5 { ok = false; }
  let dg = bson_get_document(&d, "doc");
  if !dg.is_ok {
    ok = false;
  } else {
    let inner = dg.value;
    if !bson_is_valid(&inner) { ok = false; }
    let kv = bson_get_str(&inner, "k");
    if !kv.is_ok { ok = false; } elif !str_eq(kv.value, "v") { ok = false; }
  }
  return assert(ok, "mixed document: validity, keys, accessors and nesting");
}

fn main() -> Int {
  io.println("=== xiom.bson conformance tests ===");
  var failed: Int = 0;
  let r1 = t1();
  if r1.passed { io.println("  [PASS] " + r1.name); } else { io.println("  [FAIL] " + r1.name); failed = failed + 1; }
  let r2 = t2();
  if r2.passed { io.println("  [PASS] " + r2.name); } else { io.println("  [FAIL] " + r2.name); failed = failed + 1; }
  let r3 = t3();
  if r3.passed { io.println("  [PASS] " + r3.name); } else { io.println("  [FAIL] " + r3.name); failed = failed + 1; }
  let r4 = t4();
  if r4.passed { io.println("  [PASS] " + r4.name); } else { io.println("  [FAIL] " + r4.name); failed = failed + 1; }
  let r5 = t5();
  if r5.passed { io.println("  [PASS] " + r5.name); } else { io.println("  [FAIL] " + r5.name); failed = failed + 1; }
  let r6 = t6();
  if r6.passed { io.println("  [PASS] " + r6.name); } else { io.println("  [FAIL] " + r6.name); failed = failed + 1; }
  let r7 = t7();
  if r7.passed { io.println("  [PASS] " + r7.name); } else { io.println("  [FAIL] " + r7.name); failed = failed + 1; }
  let r8 = t8();
  if r8.passed { io.println("  [PASS] " + r8.name); } else { io.println("  [FAIL] " + r8.name); failed = failed + 1; }
  let r9 = t9();
  if r9.passed { io.println("  [PASS] " + r9.name); } else { io.println("  [FAIL] " + r9.name); failed = failed + 1; }
  let r10 = t10();
  if r10.passed { io.println("  [PASS] " + r10.name); } else { io.println("  [FAIL] " + r10.name); failed = failed + 1; }
  let r11 = t11();
  if r11.passed { io.println("  [PASS] " + r11.name); } else { io.println("  [FAIL] " + r11.name); failed = failed + 1; }
  let r12 = t12();
  if r12.passed { io.println("  [PASS] " + r12.name); } else { io.println("  [FAIL] " + r12.name); failed = failed + 1; }
  let r13 = t13();
  if r13.passed { io.println("  [PASS] " + r13.name); } else { io.println("  [FAIL] " + r13.name); failed = failed + 1; }
  let r14 = t14();
  if r14.passed { io.println("  [PASS] " + r14.name); } else { io.println("  [FAIL] " + r14.name); failed = failed + 1; }
  let r15 = t15();
  if r15.passed { io.println("  [PASS] " + r15.name); } else { io.println("  [FAIL] " + r15.name); failed = failed + 1; }
  let r16 = t16();
  if r16.passed { io.println("  [PASS] " + r16.name); } else { io.println("  [FAIL] " + r16.name); failed = failed + 1; }
  let r17 = t17();
  if r17.passed { io.println("  [PASS] " + r17.name); } else { io.println("  [FAIL] " + r17.name); failed = failed + 1; }
  let r18 = t18();
  if r18.passed { io.println("  [PASS] " + r18.name); } else { io.println("  [FAIL] " + r18.name); failed = failed + 1; }
  let r19 = t19();
  if r19.passed { io.println("  [PASS] " + r19.name); } else { io.println("  [FAIL] " + r19.name); failed = failed + 1; }
  let r20 = t20();
  if r20.passed { io.println("  [PASS] " + r20.name); } else { io.println("  [FAIL] " + r20.name); failed = failed + 1; }
  let r21 = t21();
  if r21.passed { io.println("  [PASS] " + r21.name); } else { io.println("  [FAIL] " + r21.name); failed = failed + 1; }
  let r22 = t22();
  if r22.passed { io.println("  [PASS] " + r22.name); } else { io.println("  [FAIL] " + r22.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.bson: all tests passed");
  } else {
    io.println("xiom.bson: tests failed");
  }
  return failed;
}
