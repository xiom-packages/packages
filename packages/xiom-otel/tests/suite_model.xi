// XIOM -- xiom.otel conformance suite, part 1: model
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Hex helper KATs, deterministic id-derivation KATs, tracer determinism,
// attribute construction/accessors and the typed validators (ids, name,
// time, kind, status, attributes, caps, empty batch). All expectations are
// computed from the declared rules in SPEC.md; Str equality goes through
// compare.str_compare (BUG 17 discipline).

module xiom.otel.suite_model

use xiom.io;
use xiom.test;
use xiom.string.compare;
use xiom.otel;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn ok_unit(r: Result[Unit, OtelError]) -> Bool {
  if r.is_ok { return true; }
  return false;
}

fn err_unit_kind(r: Result[Unit, OtelError]) -> Int {
  if r.is_ok { return -1; }
  let e: OtelError = r.error;
  return e.kind;
}

fn ok_bytes(r: Result[Vec[UInt8], OtelError]) -> Bool {
  if r.is_ok { return true; }
  return false;
}

fn err_bytes_kind(r: Result[Vec[UInt8], OtelError]) -> Int {
  if r.is_ok { return -1; }
  let e: OtelError = r.error;
  return e.kind;
}

fn mk_byte(b: Int) -> Str {
  var v: Vec[UInt8] = Vec[UInt8].new();
  v.push(b as UInt8);
  return Str::from_utf8(v);
}

fn bytes_of(s: Str) -> Vec[UInt8] {
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < s.len() {
    let b: UInt8 = s.byte_at(i);
    out.push(b);
    i = i + 1;
  }
  return out;
}

fn hex_of(s: Str) -> Str {
  let b = bytes_of(s);
  return otel_hex_encode(&b);
}

fn base_span() -> OtelSpan {
  return otel_span_new("0123456789abcdef0123456789abcdef", "0123456789abcdef", "op", OTEL_SPAN_KIND_INTERNAL, 0, 1);
}

// ---------------------------------------------------------------------------
// m1: hex encode KATs
// ---------------------------------------------------------------------------

fn m1() -> TestResult {
  var ok = true;
  var empty: Vec[UInt8] = Vec[UInt8].new();
  if !streq(otel_hex_encode(&empty), "") { ok = false; }
  var zero: Vec[UInt8] = Vec[UInt8].new();
  zero.push(0u8 as UInt8);
  if !streq(otel_hex_encode(&zero), "00") { ok = false; }
  if !streq(hex_of(mk_byte(15)), "0f") { ok = false; }
  if !streq(hex_of(mk_byte(16)), "10") { ok = false; }
  if !streq(hex_of(mk_byte(255)), "ff") { ok = false; }
  var deadbeef: Vec[UInt8] = Vec[UInt8].new();
  deadbeef.push(222u8 as UInt8);
  deadbeef.push(173u8 as UInt8);
  deadbeef.push(190u8 as UInt8);
  deadbeef.push(239u8 as UInt8);
  if !streq(otel_hex_encode(&deadbeef), "deadbeef") { ok = false; }
  return assert(ok, "model: otel_hex_encode lowercase KATs (00/0f/10/ff/deadbeef/empty)");
}

// ---------------------------------------------------------------------------
// m2: hex decode KATs and typed errors
// ---------------------------------------------------------------------------

fn m2() -> TestResult {
  var ok = true;
  let d1 = otel_hex_decode("00ff10");
  if !ok_bytes(d1) { ok = false; } else {
    if d1.value.len() != 3 { ok = false; }
    if ((d1.value[0] as Int) & 255) != 0 { ok = false; }
    if ((d1.value[1] as Int) & 255) != 255 { ok = false; }
    if ((d1.value[2] as Int) & 255) != 16 { ok = false; }
  }
  let d2 = otel_hex_decode("DEADBEEF");
  if !ok_bytes(d2) { ok = false; } else {
    if d2.value.len() != 4 { ok = false; }
  }
  let d3 = otel_hex_decode("abc");
  if err_bytes_kind(d3) != OTEL_ERR_ID { ok = false; }
  let d4 = otel_hex_decode("zz");
  if err_bytes_kind(d4) != OTEL_ERR_ID { ok = false; }
  let d5 = otel_hex_decode("");
  if !ok_bytes(d5) { ok = false; } else {
    if d5.value.len() != 0 { ok = false; }
  }
  let d6 = otel_hex_decode("0a:1");
  if err_bytes_kind(d6) != OTEL_ERR_ID { ok = false; }
  return assert(ok, "model: otel_hex_decode KATs (case-insensitive, roundtrip, typed errors)");
}

// ---------------------------------------------------------------------------
// m3: hex validity
// ---------------------------------------------------------------------------

fn m3() -> TestResult {
  var ok = true;
  if !otel_hex_is_valid("0123456789abcdef0123456789abcdef", 16) { ok = false; }
  if !otel_hex_is_valid("0123456789ABCDEF0123456789ABCDEF", 16) { ok = false; }
  if otel_hex_is_valid("0123456789abcdef", 16) { ok = false; }
  if otel_hex_is_valid("0123456789abcdefg123456789abcdef", 16) { ok = false; }
  if otel_hex_is_valid("0123456789abcdef0123456789abcde", 16) { ok = false; }
  if !otel_hex_is_valid("", 0) { ok = false; }
  if otel_hex_is_valid("", 1) { ok = false; }
  if otel_hex_is_valid("00", -1) { ok = false; }
  return assert(ok, "model: otel_hex_is_valid exact byte counts, both cases, rejects junk");
}

// ---------------------------------------------------------------------------
// m4: deterministic 16-byte id derivation KATs
// ---------------------------------------------------------------------------

fn m4() -> TestResult {
  var ok = true;
  if !streq(otel_id_from_seed(1, 0), "afe5366f9ff335e38ae570c629140c2e") { ok = false; }
  if !streq(otel_id_from_seed(1, 1), "5d453b725a5ce1880a7d91fa1aaf28c9") { ok = false; }
  if !streq(otel_id_from_seed(2, 0), "35b475500e6845b9e228b9d147fb314f") { ok = false; }
  if !streq(otel_id_from_seed(0, 0), "412e9a91f1383a155bf15d9426404680") { ok = false; }
  if !streq(otel_id_from_seed(0 - 5, 3), "d645a6930a662740dabc4e9fb354b220") { ok = false; }
  if !streq(otel_id_from_seed(1, 0), otel_id_from_seed(1, 0)) { ok = false; }
  if streq(otel_id_from_seed(1, 0), otel_id_from_seed(1, 1)) { ok = false; }
  if streq(otel_id_from_seed(1, 0), otel_id_from_seed(2, 0)) { ok = false; }
  if otel_id_from_seed(1, 0).len() != 32 { ok = false; }
  if !otel_hex_is_valid(otel_id_from_seed(9, 9), 16) { ok = false; }
  return assert(ok, "model: otel_id_from_seed KATs (stable per (seed,counter), distinct across)");
}

// ---------------------------------------------------------------------------
// m5: deterministic 8-byte span id derivation KATs
// ---------------------------------------------------------------------------

fn m5() -> TestResult {
  var ok = true;
  if !streq(otel_span_id_from_seed(1, 0), "6aeff2f0040b230c") { ok = false; }
  if !streq(otel_span_id_from_seed(1, 1), "776e1d208b0e5359") { ok = false; }
  if !streq(otel_span_id_from_seed(7, 0), "c85fa87f45761fe1") { ok = false; }
  if !streq(otel_span_id_from_seed(0 - 5, 3), "e722e11f505a8f03") { ok = false; }
  if !streq(otel_span_id_from_seed(1, 0), otel_span_id_from_seed(1, 0)) { ok = false; }
  if streq(otel_span_id_from_seed(1, 0), otel_span_id_from_seed(1, 1)) { ok = false; }
  if otel_span_id_from_seed(1, 0).len() != 16 { ok = false; }
  // the span-id derivation is independent of the trace-id derivation
  if streq(otel_span_id_from_seed(1, 0), "afe5366f9ff335e3") { ok = false; }
  if !otel_hex_is_valid(otel_span_id_from_seed(4, 2), 8) { ok = false; }
  return assert(ok, "model: otel_span_id_from_seed KATs (stable, 8 bytes, trace-independent)");
}

// ---------------------------------------------------------------------------
// m6: tracer determinism
// ---------------------------------------------------------------------------

fn m6() -> TestResult {
  var ok = true;
  var tr: OtelTracer = otel_tracer_new(7);
  if !streq(tr.trace_id, "f25ee0f5a46d9d375e0c22a1884ce80f") { ok = false; }
  if !streq(tr.trace_id, otel_id_from_seed(7, 0)) { ok = false; }
  if tr.counter != 0 { ok = false; }
  let s1 = otel_tracer_next_span(&mut tr, "alpha", OTEL_SPAN_KIND_SERVER, 100, 200);
  let sid1 = s1.span_id;
  let tid1 = s1.trace_id;
  if !streq(sid1, "c85fa87f45761fe1") { ok = false; }
  if !streq(sid1, otel_span_id_from_seed(7, 0)) { ok = false; }
  if !streq(tid1, tr.trace_id) { ok = false; }
  if tr.counter != 1 { ok = false; }
  let s2 = otel_tracer_next_span(&mut tr, "beta", OTEL_SPAN_KIND_CLIENT, 300, 400);
  let sid2 = s2.span_id;
  if !streq(sid2, otel_span_id_from_seed(7, 1)) { ok = false; }
  if streq(sid1, sid2) { ok = false; }
  if tr.counter != 2 { ok = false; }
  // a fresh tracer with the same seed reproduces the same ids
  var tr2: OtelTracer = otel_tracer_new(7);
  let q1 = otel_tracer_next_span(&mut tr2, "alpha", OTEL_SPAN_KIND_SERVER, 100, 200);
  if !streq(q1.span_id, sid1) { ok = false; }
  return assert(ok, "model: tracer derives stable trace/span ids (same seed reproduces)");
}

// ---------------------------------------------------------------------------
// m7: attribute constructors, kinds and typed accessors
// ---------------------------------------------------------------------------

fn m7() -> TestResult {
  var ok = true;
  let a_str = otel_attr_str("k", "value");
  let a_int = otel_attr_int("k", 0 - 42);
  let a_bool = otel_attr_bool("k", true);
  let a_dbl = otel_attr_double("k", 10.239);
  if !streq(a_str.key, "k") { ok = false; }
  if otel_value_kind(&a_str.value) != OTEL_VALUE_STR { ok = false; }
  if otel_value_kind(&a_int.value) != OTEL_VALUE_INT { ok = false; }
  if otel_value_kind(&a_bool.value) != OTEL_VALUE_BOOL { ok = false; }
  if otel_value_kind(&a_dbl.value) != OTEL_VALUE_DOUBLE { ok = false; }
  if !streq(otel_value_str(&a_str.value), "value") { ok = false; }
  if otel_value_int(&a_int.value) != (0 - 42) { ok = false; }
  if !otel_value_bool(&a_bool.value) { ok = false; }
  let d: Float64 = otel_value_double(&a_dbl.value);
  if !(d > 10.238) { ok = false; }
  if !(d < 10.240) { ok = false; }
  // non-matching accessors return the documented defaults, never a guess
  if !streq(otel_value_str(&a_int.value), "") { ok = false; }
  if otel_value_int(&a_str.value) != 0 { ok = false; }
  if otel_value_bool(&a_str.value) { ok = false; }
  if !(otel_value_double(&a_str.value) < 0.1) { ok = false; }
  if !(otel_value_double(&a_str.value) > -0.1) { ok = false; }
  return assert(ok, "model: attribute constructors and typed value accessors");
}

// ---------------------------------------------------------------------------
// m8: span validation -- id and name errors
// ---------------------------------------------------------------------------

fn m8() -> TestResult {
  var ok = true;
  if !ok_unit(otel_validate_span(&base_span())) { ok = false; }
  let bad_trace = otel_span_new("abc", "0123456789abcdef", "op", OTEL_SPAN_KIND_INTERNAL, 0, 1);
  if err_unit_kind(otel_validate_span(&bad_trace)) != OTEL_ERR_ID { ok = false; }
  let bad_hex = otel_span_new("0123456789abcdef0123456789abcdeg", "0123456789abcdef", "op", OTEL_SPAN_KIND_INTERNAL, 0, 1);
  if err_unit_kind(otel_validate_span(&bad_hex)) != OTEL_ERR_ID { ok = false; }
  let zero_trace = otel_span_new("00000000000000000000000000000000", "0123456789abcdef", "op", OTEL_SPAN_KIND_INTERNAL, 0, 1);
  if err_unit_kind(otel_validate_span(&zero_trace)) != OTEL_ERR_ID { ok = false; }
  let zero_span = otel_span_new("0123456789abcdef0123456789abcdef", "0000000000000000", "op", OTEL_SPAN_KIND_INTERNAL, 0, 1);
  if err_unit_kind(otel_validate_span(&zero_span)) != OTEL_ERR_ID { ok = false; }
  var bad_parent = base_span();
  otel_span_set_parent(&mut bad_parent, "xyz");
  if err_unit_kind(otel_validate_span(&bad_parent)) != OTEL_ERR_ID { ok = false; }
  var zero_parent = base_span();
  otel_span_set_parent(&mut zero_parent, "0000000000000000");
  if err_unit_kind(otel_validate_span(&zero_parent)) != OTEL_ERR_ID { ok = false; }
  let empty_name = otel_span_new("0123456789abcdef0123456789abcdef", "0123456789abcdef", "", OTEL_SPAN_KIND_INTERNAL, 0, 1);
  if err_unit_kind(otel_validate_span(&empty_name)) != OTEL_ERR_NAME { ok = false; }
  return assert(ok, "model: span validation rejects bad trace/span/parent ids and empty names");
}

// ---------------------------------------------------------------------------
// m9: span validation -- time, kind, status
// ---------------------------------------------------------------------------

fn m9() -> TestResult {
  var ok = true;
  let tid = "0123456789abcdef0123456789abcdef";
  let sid = "0123456789abcdef";
  let neg_start = otel_span_new(tid, sid, "op", OTEL_SPAN_KIND_INTERNAL, 0 - 1, 5);
  if err_unit_kind(otel_validate_span(&neg_start)) != OTEL_ERR_TIME { ok = false; }
  let back_time = otel_span_new(tid, sid, "op", OTEL_SPAN_KIND_INTERNAL, 10, 5);
  if err_unit_kind(otel_validate_span(&back_time)) != OTEL_ERR_TIME { ok = false; }
  let equal_ok = otel_span_new(tid, sid, "op", OTEL_SPAN_KIND_INTERNAL, 7, 7);
  if !ok_unit(otel_validate_span(&equal_ok)) { ok = false; }
  let kind_low = otel_span_new(tid, sid, "op", 0, 0, 1);
  if err_unit_kind(otel_validate_span(&kind_low)) != OTEL_ERR_KIND { ok = false; }
  let kind_high = otel_span_new(tid, sid, "op", 6, 0, 1);
  if err_unit_kind(otel_validate_span(&kind_high)) != OTEL_ERR_KIND { ok = false; }
  var k1 = otel_span_new(tid, sid, "op", OTEL_SPAN_KIND_INTERNAL, 0, 1);
  if !ok_unit(otel_validate_span(&k1)) { ok = false; }
  var k5 = otel_span_new(tid, sid, "op", OTEL_SPAN_KIND_CONSUMER, 0, 1);
  if !ok_unit(otel_validate_span(&k5)) { ok = false; }
  var status_bad = base_span();
  otel_span_set_status(&mut status_bad, 3, "");
  if err_unit_kind(otel_validate_span(&status_bad)) != OTEL_ERR_STATUS { ok = false; }
  var msg_on_ok = base_span();
  otel_span_set_status(&mut msg_on_ok, OTEL_STATUS_OK, "not allowed");
  if err_unit_kind(otel_validate_span(&msg_on_ok)) != OTEL_ERR_STATUS { ok = false; }
  var err_status = base_span();
  otel_span_set_status(&mut err_status, OTEL_STATUS_ERROR, "boom");
  if !ok_unit(otel_validate_span(&err_status)) { ok = false; }
  var ok_status = base_span();
  otel_span_set_status(&mut ok_status, OTEL_STATUS_OK, "");
  if !ok_unit(otel_validate_span(&ok_status)) { ok = false; }
  return assert(ok, "model: span validation rejects negative/reversed time, bad kind and bad status");
}

// ---------------------------------------------------------------------------
// m10: attribute and batch validation (caps included)
// ---------------------------------------------------------------------------

fn m10() -> TestResult {
  var ok = true;
  let tid = "0123456789abcdef0123456789abcdef";
  let sid = "0123456789abcdef";

  var empty_key = base_span();
  otel_span_add_attribute(&mut empty_key, otel_attr_str("", "v"));
  if err_unit_kind(otel_validate_span(&empty_key)) != OTEL_ERR_ATTRIBUTE { ok = false; }

  var dup = base_span();
  otel_span_add_attribute(&mut dup, otel_attr_str("k", "1"));
  otel_span_add_attribute(&mut dup, otel_attr_str("k", "2"));
  if err_unit_kind(otel_validate_span(&dup)) != OTEL_ERR_ATTRIBUTE { ok = false; }

  var max_attr = base_span();
  var i = 0;
  while i < 128 {
    max_attr.attributes.push(otel_attr_int("k" + i.to_str(), i));
    i = i + 1;
  }
  if !ok_unit(otel_validate_span(&max_attr)) { ok = false; }
  max_attr.attributes.push(otel_attr_int("overflow", 1));
  if err_unit_kind(otel_validate_span(&max_attr)) != OTEL_ERR_LIMIT { ok = false; }

  var bad_kind = base_span();
  var v: OtelValue = otel_attr_str("x", "v").value;
  v.kind = 9;
  bad_kind.attributes.push(OtelAttribute { key: "x"; value: v });
  if err_unit_kind(otel_validate_span(&bad_kind)) != OTEL_ERR_VALUE { ok = false; }

  var empty_batch: OtelSpanBatch = otel_batch_new();
  if err_unit_kind(otel_validate_batch(&empty_batch)) != OTEL_ERR_EMPTY { ok = false; }

  var one_bad: OtelSpanBatch = otel_batch_new();
  otel_batch_push(&mut one_bad, base_span());
  otel_batch_push(&mut one_bad, otel_span_new("nope", sid, "op", OTEL_SPAN_KIND_INTERNAL, 0, 1));
  if err_unit_kind(otel_validate_batch(&one_bad)) != OTEL_ERR_ID { ok = false; }

  var full: OtelSpanBatch = otel_batch_new();
  i = 0;
  while i < 1024 {
    otel_batch_push(&mut full, otel_span_new(tid, sid, "op", OTEL_SPAN_KIND_INTERNAL, 0, 1));
    i = i + 1;
  }
  if !ok_unit(otel_validate_batch(&full)) { ok = false; }
  otel_batch_push(&mut full, otel_span_new(tid, sid, "op", OTEL_SPAN_KIND_INTERNAL, 0, 1));
  if err_unit_kind(otel_validate_batch(&full)) != OTEL_ERR_LIMIT { ok = false; }
  return assert(ok, "model: attribute/batch validation (empty key, dup key, 128/129, 1024/1025, empty)");
}

// ---------------------------------------------------------------------------
// Runner
// ---------------------------------------------------------------------------

pub fn run_suite() -> Int {
  var failed: Int = 0;
  let r1 = m1();
  if r1.passed { io.println("  [PASS] " + r1.name); } else { io.println("  [FAIL] " + r1.name); failed = failed + 1; }
  let r2 = m2();
  if r2.passed { io.println("  [PASS] " + r2.name); } else { io.println("  [FAIL] " + r2.name); failed = failed + 1; }
  let r3 = m3();
  if r3.passed { io.println("  [PASS] " + r3.name); } else { io.println("  [FAIL] " + r3.name); failed = failed + 1; }
  let r4 = m4();
  if r4.passed { io.println("  [PASS] " + r4.name); } else { io.println("  [FAIL] " + r4.name); failed = failed + 1; }
  let r5 = m5();
  if r5.passed { io.println("  [PASS] " + r5.name); } else { io.println("  [FAIL] " + r5.name); failed = failed + 1; }
  let r6 = m6();
  if r6.passed { io.println("  [PASS] " + r6.name); } else { io.println("  [FAIL] " + r6.name); failed = failed + 1; }
  let r7 = m7();
  if r7.passed { io.println("  [PASS] " + r7.name); } else { io.println("  [FAIL] " + r7.name); failed = failed + 1; }
  let r8 = m8();
  if r8.passed { io.println("  [PASS] " + r8.name); } else { io.println("  [FAIL] " + r8.name); failed = failed + 1; }
  let r9 = m9();
  if r9.passed { io.println("  [PASS] " + r9.name); } else { io.println("  [FAIL] " + r9.name); failed = failed + 1; }
  let r10 = m10();
  if r10.passed { io.println("  [PASS] " + r10.name); } else { io.println("  [FAIL] " + r10.name); failed = failed + 1; }
  return failed;
}
