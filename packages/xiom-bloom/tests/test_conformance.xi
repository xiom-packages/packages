// XIOM -- xiom.bloom conformance tests (25 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers: pinned caps/version/header constants; construction happy paths and
// every validation error; double-hashing index arithmetic (including negative
// hashes and the bad hash index); bit-level insert/contains for k = 1 and
// k = 4; idempotent inserts; clear; the m = 1 degenerate filter; the string
// API's determinism; both hashes pinned against published FNV-1a vectors and
// independently computed mixing-hash vectors; exact set counts; the
// false-positive permille estimate at pinned fill ratios; the pinned 11-byte
// serialization layout and round-trips; every from_bytes error path
// (truncation, version, byte-length mismatch, trailing bytes, decoded size
// validation, dirty padding); union and intersection including their size
// mismatch errors and the empty-filter identities; and bloom_equal.
//
// Str equality goes through str_compare (BUG 17 discipline). Read-only API
// calls are wrapped in &mut helpers because v0.61.3 warns (E001, advisory)
// when a `&f` call is followed by a `&mut f` call in the same function.

module bloom_tests
use xiom.io; use xiom.test; use xiom.bloom;
use xiom.string.compare;

// --------------------------------------------------
//  Result and accessor helpers
// --------------------------------------------------

fn err_filter_is(r: Result[BloomFilter, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return compare.str_compare(r.error, want) == 0;
}

fn err_int_is(r: Result[Int, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return compare.str_compare(r.error, want) == 0;
}

// Filter for a size pair the test expects to be valid; a 1-bit fallback keeps
// a broken expectation failing loudly in the assertions that follow.
fn need(m: Int, k: Int) -> BloomFilter {
  let r = bloom_new(m, k);
  if r.is_ok {
    return r.value;
  }
  let fallback = bloom_new(1, 1);
  return fallback.value;
}

// Filter decoded from a buffer the test expects to be valid (same fallback).
fn decoded(data: &Vec[UInt8]) -> BloomFilter {
  let r = bloom_from_bytes(data);
  if r.is_ok {
    return r.value;
  }
  let fallback = bloom_new(1, 1);
  return fallback.value;
}

fn union_of(a: &mut BloomFilter, b: &mut BloomFilter) -> BloomFilter {
  let r = bloom_union(a, b);
  if r.is_ok {
    return r.value;
  }
  let fallback = bloom_new(1, 1);
  return fallback.value;
}

fn intersection_of(a: &mut BloomFilter, b: &mut BloomFilter) -> BloomFilter {
  let r = bloom_intersection(a, b);
  if r.is_ok {
    return r.value;
  }
  let fallback = bloom_new(1, 1);
  return fallback.value;
}

fn count_of(f: &mut BloomFilter) -> Int { return bloom_set_count(f); }
fn fp_of(f: &mut BloomFilter) -> Int { return bloom_fp_permille(f); }
fn empty_of(f: &mut BloomFilter) -> Bool { return bloom_is_empty(f); }
fn contains(f: &mut BloomFilter, h1: Int, h2: Int) -> Bool { return bloom_contains(f, h1, h2); }
fn has(f: &mut BloomFilter, s: Str) -> Bool { return bloom_has_str(f, s); }
fn m_of(f: &mut BloomFilter) -> Int { return bloom_m(f); }
fn k_of(f: &mut BloomFilter) -> Int { return bloom_k(f); }
fn blen_of(f: &mut BloomFilter) -> Int { return bloom_byte_len(f); }
fn bytes_of(f: &mut BloomFilter) -> Vec[UInt8] { return bloom_to_bytes(f); }
fn eq_of(a: &mut BloomFilter, b: &mut BloomFilter) -> Bool { return bloom_equal(a, b); }

fn idx_is(f: &mut BloomFilter, h1: Int, h2: Int, i: Int, want: Int) -> Bool {
  let r = bloom_derive_index(f, h1, h2, i);
  if !r.is_ok {
    return false;
  }
  return r.value == want;
}

fn idx_err(f: &mut BloomFilter, h1: Int, h2: Int, i: Int, want: Str) -> Bool {
  return err_int_is(bloom_derive_index(f, h1, h2, i), want);
}

// --------------------------------------------------
//  Byte helpers (independent of src/bloom.xi)
// --------------------------------------------------

fn pair(a: Int, b: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(a as UInt8);
  v.push(b as UInt8);
  return v;
}

fn zeros(n: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < n {
    v.push(0 as UInt8);
    i = i + 1;
  }
  return v;
}

fn push_u32_le(v: &mut Vec[UInt8], x: Int) {
  v.push((x % 256) as UInt8);
  v.push(((x / 256) % 256) as UInt8);
  v.push(((x / 65536) % 256) as UInt8);
  v.push(((x / 16777216) % 256) as UInt8);
}

fn push_u16_le(v: &mut Vec[UInt8], x: Int) {
  v.push((x % 256) as UInt8);
  v.push(((x / 256) % 256) as UInt8);
}

// Version-1 header with an explicit declared payload length.
fn header(m: Int, k: Int, declared: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(1 as UInt8);
  push_u32_le(&mut v, m);
  push_u16_le(&mut v, k);
  push_u32_le(&mut v, declared);
  return v;
}

fn cat(a: Vec[UInt8], b: Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < a.len() {
    out.push(a[i]);
    i = i + 1;
  }
  i = 0;
  while i < b.len() {
    out.push(b[i]);
    i = i + 1;
  }
  return out;
}

fn bytes_equal(a: Vec[UInt8], b: Vec[UInt8]) -> Bool {
  if a.len() != b.len() {
    return false;
  }
  var i = 0;
  while i < a.len() {
    let x = (a[i] as Int) & 0xFF;
    let y = (b[i] as Int) & 0xFF;
    if x != y {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// Copy of `v` with byte `pos` replaced.
fn set_byte(v: Vec[UInt8], pos: Int, b: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < v.len() {
    if i == pos {
      out.push(b as UInt8);
    } else {
      out.push(v[i]);
    }
    i = i + 1;
  }
  return out;
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  var ok = bloom_max_bits() == 1073741824;
  if bloom_max_hashes() != 1024 { ok = false; }
  if bloom_version() != 1 { ok = false; }
  if bloom_header_len() != 11 { ok = false; }
  return assert(ok, "constants pinned: caps, version, header length");
}

fn t2() -> TestResult {
  var f: BloomFilter = need(16, 2);
  var ok = m_of(&mut f) == 16;
  if k_of(&mut f) != 2 { ok = false; }
  if blen_of(&mut f) != 2 { ok = false; }
  if !empty_of(&mut f) { ok = false; }
  if count_of(&mut f) != 0 { ok = false; }
  if fp_of(&mut f) != 0 { ok = false; }
  bloom_clear(&mut f);
  if count_of(&mut f) != 0 { ok = false; }
  return assert(ok, "bloom_new sizes, accessors and empty stats");
}

fn t3() -> TestResult {
  var one: BloomFilter = need(1, 1);
  var ok = blen_of(&mut one) == 1;
  if k_of(&mut one) != 1 { ok = false; }
  var wide: BloomFilter = need(9, 1024);
  if k_of(&mut wide) != 1024 { ok = false; }
  if blen_of(&mut wide) != 2 { ok = false; }
  var big: BloomFilter = need(1024, 1);
  if blen_of(&mut big) != 128 { ok = false; }
  return assert(ok, "boundary sizes accepted: m=1, k=1024, m=1024");
}

fn t4() -> TestResult {
  var ok = err_filter_is(bloom_new(0, 1), "bloom: m must be positive");
  if !err_filter_is(bloom_new(-5, 1), "bloom: m must be positive") { ok = false; }
  if !err_filter_is(bloom_new(8, 0), "bloom: k must be positive") { ok = false; }
  if !err_filter_is(bloom_new(8, -3), "bloom: k must be positive") { ok = false; }
  if !err_filter_is(bloom_new(0, 0), "bloom: m must be positive") { ok = false; }
  return assert(ok, "non-positive m and k are rejected with pinned messages");
}

fn t5() -> TestResult {
  var ok = err_filter_is(bloom_new(1073741825, 1), "bloom: m exceeds maximum");
  if !err_filter_is(bloom_new(8, 1025), "bloom: k exceeds maximum") { ok = false; }
  if !err_filter_is(bloom_new(-1073741825, 1), "bloom: m must be positive") { ok = false; }
  return assert(ok, "oversized m and k are rejected");
}

fn t6() -> TestResult {
  var f: BloomFilter = need(16, 4);
  var ok = idx_is(&mut f, 3, 5, 0, 3);
  if !idx_is(&mut f, 3, 5, 1, 8) { ok = false; }
  if !idx_is(&mut f, 3, 5, 2, 13) { ok = false; }
  if !idx_is(&mut f, 3, 5, 3, 2) { ok = false; }
  if !idx_err(&mut f, 3, 5, 4, "bloom: hash index out of range") { ok = false; }
  if !idx_err(&mut f, 3, 5, -1, "bloom: hash index out of range") { ok = false; }
  return assert(ok, "double hashing index arithmetic pinned; bad i is Err");
}

fn t7() -> TestResult {
  var f: BloomFilter = need(16, 4);
  var ok = idx_is(&mut f, -1, 2, 0, 15);
  if !idx_is(&mut f, -1, 2, 1, 1) { ok = false; }
  if !idx_is(&mut f, -1, 2, 2, 3) { ok = false; }
  if !idx_is(&mut f, -1, 2, 3, 5) { ok = false; }
  if !idx_is(&mut f, -17, -1, 0, 15) { ok = false; }
  if !idx_is(&mut f, -17, -1, 1, 14) { ok = false; }
  return assert(ok, "negative hashes wrap with floor semantics");
}

fn t8() -> TestResult {
  var f: BloomFilter = need(64, 1);
  bloom_insert(&mut f, 5, 0);
  var ok = contains(&mut f, 5, 0);
  if !contains(&mut f, 5, 63) { ok = false; }
  if contains(&mut f, 6, 0) { ok = false; }
  if count_of(&mut f) != 1 { ok = false; }
  bloom_insert(&mut f, 5, 7);
  if count_of(&mut f) != 1 { ok = false; }
  return assert(ok, "k=1 insert sets exactly the h1 mod m bit");
}

fn t9() -> TestResult {
  var f: BloomFilter = need(128, 4);
  bloom_insert(&mut f, 10, 7);
  var ok = contains(&mut f, 10, 7);
  if count_of(&mut f) != 4 { ok = false; }
  if contains(&mut f, 11, 7) { ok = false; }
  bloom_insert(&mut f, 10, 7);
  if count_of(&mut f) != 4 { ok = false; }
  bloom_insert(&mut f, 17, 7);
  if count_of(&mut f) != 5 { ok = false; }
  return assert(ok, "k=4 probes set exactly the derived bits and are idempotent");
}

fn t10() -> TestResult {
  var f: BloomFilter = need(256, 3);
  bloom_add_str(&mut f, "alpha");
  bloom_add_str(&mut f, "beta");
  var ok = count_of(&mut f) > 0;
  if empty_of(&mut f) { ok = false; }
  bloom_clear(&mut f);
  if count_of(&mut f) != 0 { ok = false; }
  if !empty_of(&mut f) { ok = false; }
  if has(&mut f, "alpha") { ok = false; }
  return assert(ok, "clear drops every bit and membership");
}

fn t11() -> TestResult {
  var f: BloomFilter = need(1, 4);
  bloom_insert(&mut f, 12345, 6789);
  var ok = count_of(&mut f) == 1;
  if !contains(&mut f, 999, 111) { ok = false; }
  if empty_of(&mut f) { ok = false; }
  return assert(ok, "m=1 filter has a single bit and reports every value");
}

fn t12() -> TestResult {
  var f: BloomFilter = need(512, 3);
  bloom_add_str(&mut f, "alpha");
  bloom_add_str(&mut f, "beta");
  bloom_add_str(&mut f, "gamma");
  var ok = has(&mut f, "alpha");
  if !has(&mut f, "beta") { ok = false; }
  if !has(&mut f, "gamma") { ok = false; }
  let c1 = count_of(&mut f);
  if c1 <= 0 { ok = false; }
  var g: BloomFilter = need(512, 3);
  bloom_add_str(&mut g, "alpha");
  bloom_add_str(&mut g, "beta");
  bloom_add_str(&mut g, "gamma");
  if count_of(&mut g) != c1 { ok = false; }
  let fb = bytes_of(&mut f);
  let gb = bytes_of(&mut g);
  if !bytes_equal(fb, gb) { ok = false; }
  if has(&mut f, "delta") != has(&mut g, "delta") { ok = false; }
  if has(&mut f, "epsilon") != has(&mut g, "epsilon") { ok = false; }
  return assert(ok, "string API is deterministic across identical filters");
}

fn t13() -> TestResult {
  var ok = bloom_hash1("") == 2166136261;
  if bloom_hash1("a") != 3826002220 { ok = false; }
  if bloom_hash1("foobar") != 3214735720 { ok = false; }
  if bloom_hash1("hello") != 1335831723 { ok = false; }
  if bloom_hash1("alpha") != bloom_hash1("alpha") { ok = false; }
  if bloom_hash1("alpha") == bloom_hash1("alphb") { ok = false; }
  let h = bloom_hash1("xiom.bloom");
  if h < 0 { ok = false; }
  if h > 4294967295 { ok = false; }
  return assert(ok, "FNV-1a 32-bit pinned against published vectors");
}

fn t14() -> TestResult {
  var ok = bloom_hash2("") == 1223194048;
  if bloom_hash2("a") != 2230179447 { ok = false; }
  if bloom_hash2("bloom") != 3295578999 { ok = false; }
  if bloom_hash2("xiom.bloom") != 2938125760 { ok = false; }
  if bloom_hash2("hello") != bloom_hash2("hello") { ok = false; }
  if bloom_hash2("alpha") == bloom_hash1("alpha") { ok = false; }
  if bloom_hash2("") == bloom_hash1("") { ok = false; }
  let h = bloom_hash2("zzz");
  if h < 0 { ok = false; }
  if h > 4294967295 { ok = false; }
  return assert(ok, "mixing hash pinned and distinct from FNV-1a");
}

fn t15() -> TestResult {
  var f: BloomFilter = need(8, 1);
  var ok = empty_of(&mut f);
  bloom_insert(&mut f, 0, 0);
  bloom_insert(&mut f, 7, 0);
  if count_of(&mut f) != 2 { ok = false; }
  bloom_insert(&mut f, 0, 0);
  if count_of(&mut f) != 2 { ok = false; }
  var g: BloomFilter = need(11, 1);
  bloom_insert(&mut g, 10, 0);
  if count_of(&mut g) != 1 { ok = false; }
  if empty_of(&mut g) { ok = false; }
  return assert(ok, "set_count counts set bits exactly, padding stays zero");
}

fn t16() -> TestResult {
  var f: BloomFilter = need(8, 1);
  var ok = fp_of(&mut f) == 0;
  bloom_insert(&mut f, 0, 0);
  bloom_insert(&mut f, 1, 0);
  bloom_insert(&mut f, 2, 0);
  bloom_insert(&mut f, 3, 0);
  if count_of(&mut f) != 4 { ok = false; }
  if fp_of(&mut f) != 500 { ok = false; }
  var g: BloomFilter = need(8, 2);
  bloom_insert(&mut g, 0, 1);
  bloom_insert(&mut g, 2, 1);
  if count_of(&mut g) != 4 { ok = false; }
  if fp_of(&mut g) != 250 { ok = false; }
  var h: BloomFilter = need(8, 1);
  var i = 0;
  while i < 8 {
    bloom_insert(&mut h, i, 0);
    i = i + 1;
  }
  if fp_of(&mut h) != 1000 { ok = false; }
  return assert(ok, "false-positive permille pinned at 0, 500, 250 and 1000");
}

fn t17() -> TestResult {
  var f: BloomFilter = need(16, 3);
  bloom_insert(&mut f, 3, 5);
  let got = bytes_of(&mut f);
  var want = Vec[UInt8].new();
  want.push(1 as UInt8);
  want.push(16 as UInt8);
  want.push(0 as UInt8);
  want.push(0 as UInt8);
  want.push(0 as UInt8);
  want.push(3 as UInt8);
  want.push(0 as UInt8);
  want.push(2 as UInt8);
  want.push(0 as UInt8);
  want.push(0 as UInt8);
  want.push(0 as UInt8);
  want.push(8 as UInt8);
  want.push(33 as UInt8);
  var ok = bytes_equal(got, want);
  var g: BloomFilter = decoded(&got);
  if !eq_of(&mut f, &mut g) { ok = false; }
  if count_of(&mut g) != 3 { ok = false; }
  if !contains(&mut g, 3, 5) { ok = false; }
  if contains(&mut g, 4, 5) { ok = false; }
  if m_of(&mut g) != 16 { ok = false; }
  if k_of(&mut g) != 3 { ok = false; }
  return assert(ok, "serialization layout pinned and round-trips");
}

fn t18() -> TestResult {
  var empty = Vec[UInt8].new();
  var ok = err_filter_is(bloom_from_bytes(&empty), "bloom: truncated buffer");
  let short = zeros(10);
  if !err_filter_is(bloom_from_bytes(&short), "bloom: truncated buffer") { ok = false; }
  let h = header(16, 3, 2);
  if !err_filter_is(bloom_from_bytes(&h), "bloom: truncated buffer") { ok = false; }
  let partial = cat(h, zeros(1));
  if !err_filter_is(bloom_from_bytes(&partial), "bloom: truncated buffer") { ok = false; }
  let full = cat(h, zeros(2));
  if !bloom_from_bytes(&full).is_ok { ok = false; }
  return assert(ok, "short buffers are truncated Err");
}

fn t19() -> TestResult {
  let good = cat(header(16, 3, 2), zeros(2));
  var ok = err_filter_is(bloom_from_bytes(&set_byte(good, 0, 0)), "bloom: unsupported version");
  if !err_filter_is(bloom_from_bytes(&set_byte(good, 0, 2)), "bloom: unsupported version") { ok = false; }
  if !bloom_from_bytes(&good).is_ok { ok = false; }
  return assert(ok, "only serialization version 1 is accepted");
}

fn t20() -> TestResult {
  var ok = err_filter_is(bloom_from_bytes(&cat(header(16, 3, 3), zeros(3))), "bloom: byte length mismatch");
  if !err_filter_is(bloom_from_bytes(&cat(header(16, 3, 1), zeros(1))), "bloom: byte length mismatch") { ok = false; }
  if !err_filter_is(bloom_from_bytes(&cat(header(16, 3, 2), zeros(3))), "bloom: trailing bytes") { ok = false; }
  return assert(ok, "declared byte length is checked; trailing bytes are Err");
}

fn t21() -> TestResult {
  var ok = err_filter_is(bloom_from_bytes(&header(0, 1, 0)), "bloom: m must be positive");
  if !err_filter_is(bloom_from_bytes(&header(8, 0, 1)), "bloom: k must be positive") { ok = false; }
  if !err_filter_is(bloom_from_bytes(&header(1073741825, 1, 0)), "bloom: m exceeds maximum") { ok = false; }
  if !err_filter_is(bloom_from_bytes(&header(8, 1025, 1)), "bloom: k exceeds maximum") { ok = false; }
  return assert(ok, "decoded m and k pass the same validation as bloom_new");
}

fn t22() -> TestResult {
  let dirty = cat(header(11, 1, 2), pair(0, 8));
  var ok = err_filter_is(bloom_from_bytes(&dirty), "bloom: padding not zero");
  let clean = cat(header(11, 1, 2), pair(0, 4));
  var g: BloomFilter = decoded(&clean);
  if count_of(&mut g) != 1 { ok = false; }
  if !contains(&mut g, 10, 0) { ok = false; }
  var f: BloomFilter = need(11, 1);
  bloom_insert(&mut f, 10, 0);
  let mine = bytes_of(&mut f);
  var h: BloomFilter = decoded(&mine);
  if !eq_of(&mut f, &mut h) { ok = false; }
  if count_of(&mut h) != 1 { ok = false; }
  return assert(ok, "padding bits must be zero; m=11 round-trips");
}

fn t23() -> TestResult {
  var a: BloomFilter = need(32, 2);
  var b: BloomFilter = need(32, 2);
  bloom_insert(&mut a, 1, 3);
  bloom_insert(&mut a, 10, 3);
  bloom_insert(&mut b, 1, 3);
  bloom_insert(&mut b, 20, 3);
  var u: BloomFilter = union_of(&mut a, &mut b);
  var ok = contains(&mut u, 1, 3);
  if !contains(&mut u, 10, 3) { ok = false; }
  if !contains(&mut u, 20, 3) { ok = false; }
  if contains(&mut u, 2, 3) { ok = false; }
  if count_of(&mut u) != 6 { ok = false; }
  var e: BloomFilter = need(32, 2);
  var ue: BloomFilter = union_of(&mut a, &mut e);
  if !eq_of(&mut ue, &mut a) { ok = false; }
  var c: BloomFilter = need(33, 2);
  var d: BloomFilter = need(32, 3);
  if !err_filter_is(bloom_union(&mut a, &mut c), "bloom: union size mismatch") { ok = false; }
  if !err_filter_is(bloom_union(&mut a, &mut d), "bloom: union size mismatch") { ok = false; }
  return assert(ok, "union is the exact OR; unequal shapes are Err");
}

fn t24() -> TestResult {
  var a: BloomFilter = need(32, 2);
  var b: BloomFilter = need(32, 2);
  bloom_insert(&mut a, 1, 3);
  bloom_insert(&mut a, 10, 3);
  bloom_insert(&mut b, 1, 3);
  bloom_insert(&mut b, 20, 3);
  var x: BloomFilter = intersection_of(&mut a, &mut b);
  var ok = contains(&mut x, 1, 3);
  if count_of(&mut x) != 2 { ok = false; }
  if contains(&mut x, 10, 3) { ok = false; }
  if contains(&mut x, 20, 3) { ok = false; }
  var e: BloomFilter = need(32, 2);
  var xe: BloomFilter = intersection_of(&mut a, &mut e);
  if !empty_of(&mut xe) { ok = false; }
  if count_of(&mut xe) != 0 { ok = false; }
  var c: BloomFilter = need(33, 2);
  var d: BloomFilter = need(32, 3);
  if !err_filter_is(bloom_intersection(&mut a, &mut c), "bloom: intersection size mismatch") { ok = false; }
  if !err_filter_is(bloom_intersection(&mut a, &mut d), "bloom: intersection size mismatch") { ok = false; }
  return assert(ok, "intersection is the AND; unequal shapes are Err");
}

fn t25() -> TestResult {
  var a: BloomFilter = need(24, 2);
  var b: BloomFilter = need(24, 2);
  var c: BloomFilter = need(25, 2);
  var d: BloomFilter = need(24, 3);
  var ok = eq_of(&mut a, &mut b);
  bloom_insert(&mut b, 5, 3);
  if eq_of(&mut a, &mut b) { ok = false; }
  bloom_insert(&mut a, 5, 3);
  if !eq_of(&mut a, &mut b) { ok = false; }
  if eq_of(&mut a, &mut c) { ok = false; }
  if eq_of(&mut a, &mut d) { ok = false; }
  return assert(ok, "bloom_equal compares m, k and payload bytes");
}

fn main() -> Int {
  io.println("=== xiom.bloom conformance tests ===");
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
  let r23 = t23();
  if r23.passed { io.println("  [PASS] " + r23.name); } else { io.println("  [FAIL] " + r23.name); failed = failed + 1; }
  let r24 = t24();
  if r24.passed { io.println("  [PASS] " + r24.name); } else { io.println("  [FAIL] " + r24.name); failed = failed + 1; }
  let r25 = t25();
  if r25.passed { io.println("  [PASS] " + r25.name); } else { io.println("  [FAIL] " + r25.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.bloom: all tests passed");
  } else {
    io.println("xiom.bloom: tests failed");
  }
  return failed;
}
