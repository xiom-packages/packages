// XIOM -- xiom.otel conformance suite, part 2: OTLP/JSON encoder
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Exact-byte goldens for the OTLP/JSON wire structure (minimal span, rich
// span, statuses, multi-span batches, resource + scope, escaping/unicode,
// decimal-string rendering, insertion order, id case pass-through), the
// canonical byte rules, and the typed encoder error pass-through. Goldens
// are the declared canonical bytes from SPEC.md section 5; Str equality goes
// through compare.str_compare (BUG 17 discipline).

module xiom.otel.suite_encoder

use xiom.io;
use xiom.test;
use xiom.string;
use xiom.string.compare;
use xiom.otel;
use xiom.otel.otlp;
use xiom.math.constants;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
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

fn empty_res() -> OtelResource {
  return otel_resource_new();
}

fn empty_scope() -> OtelScope {
  return otel_scope_new("", "");
}

const TID: Str = "0af7651916cd43dd8448eb211c80319c";
const SID: Str = "b7ad6b7169203331";

fn enc_err_kind(batch: &OtelSpanBatch, res: &OtelResource, scope: &OtelScope) -> Int {
  let r = otel_encode_json(batch, res, scope);
  if r.is_ok { return -1; }
  let e: OtelError = r.error;
  return e.kind;
}

// ---------------------------------------------------------------------------
// e1: minimal single span -- exact bytes
// ---------------------------------------------------------------------------

fn e1() -> TestResult {
  var b: OtelSpanBatch = otel_batch_new();
  otel_batch_push(&mut b, otel_span_new(TID, SID, "op", OTEL_SPAN_KIND_INTERNAL, 1, 2));
  let r = otel_encode_json(&b, &empty_res(), &empty_scope());
  var ok = false;
  if r.is_ok {
    let p: Str = r.value;
    let golden = "{\"resourceSpans\":[{\"resource\":{},\"scopeSpans\":[{\"scope\":{},\"spans\":[{\"traceId\":\"0af7651916cd43dd8448eb211c80319c\",\"spanId\":\"b7ad6b7169203331\",\"name\":\"op\",\"kind\":1,\"startTimeUnixNano\":\"1\",\"endTimeUnixNano\":\"2\"}]}]}]}";
    ok = streq(p, golden);
    if p.len() != 215 { ok = false; }
  }
  return assert(ok, "encoder: minimal single span exact-byte golden (215 bytes)");
}

// ---------------------------------------------------------------------------
// e2: rich span -- parent, all attribute types, status error
// ---------------------------------------------------------------------------

fn e2() -> TestResult {
  var b: OtelSpanBatch = otel_batch_new();
  var s = otel_span_new(TID, SID, "GET /items", OTEL_SPAN_KIND_SERVER, 1544712660000000000, 1544712661000000000);
  otel_span_set_parent(&mut s, "b7ad6b7169203330");
  otel_span_add_attribute(&mut s, otel_attr_str("http.method", "GET"));
  otel_span_add_attribute(&mut s, otel_attr_int("http.status_code", 500));
  otel_span_add_attribute(&mut s, otel_attr_bool("retry", true));
  otel_span_add_attribute(&mut s, otel_attr_double("score", 10.239));
  otel_span_set_status(&mut s, OTEL_STATUS_ERROR, "upstream timed out");
  otel_batch_push(&mut b, s);
  let r = otel_encode_json(&b, &empty_res(), &empty_scope());
  var ok = false;
  if r.is_ok {
    let p: Str = r.value;
    let golden = "{\"resourceSpans\":[{\"resource\":{},\"scopeSpans\":[{\"scope\":{},\"spans\":[{\"traceId\":\"0af7651916cd43dd8448eb211c80319c\",\"spanId\":\"b7ad6b7169203331\",\"parentSpanId\":\"b7ad6b7169203330\",\"name\":\"GET /items\",\"kind\":2,\"startTimeUnixNano\":\"1544712660000000000\",\"endTimeUnixNano\":\"1544712661000000000\",\"attributes\":[{\"key\":\"http.method\",\"value\":{\"stringValue\":\"GET\"}},{\"key\":\"http.status_code\",\"value\":{\"intValue\":\"500\"}},{\"key\":\"retry\",\"value\":{\"boolValue\":true}},{\"key\":\"score\",\"value\":{\"doubleValue\":10.239}}],\"status\":{\"code\":2,\"message\":\"upstream timed out\"}}]}]}]}";
    ok = streq(p, golden);
    if p.len() != 555 { ok = false; }
  }
  return assert(ok, "encoder: rich span golden (parent, 4 value types, status error; 555 bytes)");
}

// ---------------------------------------------------------------------------
// e3: status OK -- code only, no message key
// ---------------------------------------------------------------------------

fn e3() -> TestResult {
  var b: OtelSpanBatch = otel_batch_new();
  var s = otel_span_new(TID, SID, "ok", OTEL_SPAN_KIND_CLIENT, 5, 9);
  otel_span_set_status(&mut s, OTEL_STATUS_OK, "");
  otel_batch_push(&mut b, s);
  let r = otel_encode_json(&b, &empty_res(), &empty_scope());
  var ok = false;
  if r.is_ok {
    let p: Str = r.value;
    let golden = "{\"resourceSpans\":[{\"resource\":{},\"scopeSpans\":[{\"scope\":{},\"spans\":[{\"traceId\":\"0af7651916cd43dd8448eb211c80319c\",\"spanId\":\"b7ad6b7169203331\",\"name\":\"ok\",\"kind\":3,\"startTimeUnixNano\":\"5\",\"endTimeUnixNano\":\"9\",\"status\":{\"code\":1}}]}]}]}";
    ok = streq(p, golden);
    if p.len() != 235 { ok = false; }
  }
  return assert(ok, "encoder: status OK golden (code only, UNSET omits status; 235 bytes)");
}

// ---------------------------------------------------------------------------
// e4: multi-span batch -- order preserved
// ---------------------------------------------------------------------------

fn e4() -> TestResult {
  var b: OtelSpanBatch = otel_batch_new();
  otel_batch_push(&mut b, otel_span_new(TID, "1111111111111111", "first", OTEL_SPAN_KIND_PRODUCER, 10, 20));
  otel_batch_push(&mut b, otel_span_new(TID, "2222222222222222", "second", OTEL_SPAN_KIND_CONSUMER, 30, 40));
  let r = otel_encode_json(&b, &empty_res(), &empty_scope());
  var ok = false;
  if r.is_ok {
    let p: Str = r.value;
    let golden = "{\"resourceSpans\":[{\"resource\":{},\"scopeSpans\":[{\"scope\":{},\"spans\":[{\"traceId\":\"0af7651916cd43dd8448eb211c80319c\",\"spanId\":\"1111111111111111\",\"name\":\"first\",\"kind\":4,\"startTimeUnixNano\":\"10\",\"endTimeUnixNano\":\"20\"},{\"traceId\":\"0af7651916cd43dd8448eb211c80319c\",\"spanId\":\"2222222222222222\",\"name\":\"second\",\"kind\":5,\"startTimeUnixNano\":\"30\",\"endTimeUnixNano\":\"40\"}]}]}]}";
    ok = streq(p, golden);
    if p.len() != 368 { ok = false; }
  }
  return assert(ok, "encoder: multi-span batch golden (insertion order, kinds 4/5; 368 bytes)");
}

// ---------------------------------------------------------------------------
// e5: resource attributes + scope name/version
// ---------------------------------------------------------------------------

fn e5() -> TestResult {
  var b: OtelSpanBatch = otel_batch_new();
  otel_batch_push(&mut b, otel_span_new(TID, SID, "op", OTEL_SPAN_KIND_INTERNAL, 1, 2));
  var res: OtelResource = otel_resource_new();
  res.attributes.push(otel_attr_str("service.name", "checkout"));
  res.attributes.push(otel_attr_int("process.pid", 4242));
  let scope: OtelScope = otel_scope_new("xiom.otel", "0.1.0");
  let r = otel_encode_json(&b, &res, &scope);
  var ok = false;
  if r.is_ok {
    let p: Str = r.value;
    let golden = "{\"resourceSpans\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"checkout\"}},{\"key\":\"process.pid\",\"value\":{\"intValue\":\"4242\"}}]},\"scopeSpans\":[{\"scope\":{\"name\":\"xiom.otel\",\"version\":\"0.1.0\"},\"spans\":[{\"traceId\":\"0af7651916cd43dd8448eb211c80319c\",\"spanId\":\"b7ad6b7169203331\",\"name\":\"op\",\"kind\":1,\"startTimeUnixNano\":\"1\",\"endTimeUnixNano\":\"2\"}]}]}]}";
    ok = streq(p, golden);
    if p.len() != 373 { ok = false; }
  }
  return assert(ok, "encoder: resource + scope golden (intValue decimal string; 373 bytes)");
}

// ---------------------------------------------------------------------------
// e6: escaping and unicode pass-through
// ---------------------------------------------------------------------------

fn e6() -> TestResult {
  var b: OtelSpanBatch = otel_batch_new();
  var s = otel_span_new(TID, SID, "q\"uote\\back/slash", OTEL_SPAN_KIND_INTERNAL, 1, 2);
  var raw: Vec[UInt8] = Vec[UInt8].new();
  raw.push(99u8 as UInt8);
  raw.push(1u8 as UInt8);
  raw.push(8u8 as UInt8);
  raw.push(9u8 as UInt8);
  raw.push(10u8 as UInt8);
  raw.push(12u8 as UInt8);
  raw.push(31u8 as UInt8);
  raw.push(233u8 as UInt8);
  otel_span_add_attribute(&mut s, otel_attr_str("raw", Str::from_utf8(raw)));
  otel_batch_push(&mut b, s);
  let r = otel_encode_json(&b, &empty_res(), &empty_scope());
  var ok = false;
  if r.is_ok {
    let p: Str = r.value;
    let golden = "{\"resourceSpans\":[{\"resource\":{},\"scopeSpans\":[{\"scope\":{},\"spans\":[{\"traceId\":\"0af7651916cd43dd8448eb211c80319c\",\"spanId\":\"b7ad6b7169203331\",\"name\":\"q\\\"uote\\\\back/slash\",\"kind\":1,\"startTimeUnixNano\":\"1\",\"endTimeUnixNano\":\"2\",\"attributes\":[{\"key\":\"raw\",\"value\":{\"stringValue\":\"c\\u0001\\b\\t\\n\\f\\u001f" + mk_byte(233) + "\"}}]}]}]}]}";
    ok = streq(p, golden);
    if p.len() != 310 { ok = false; }
    if !string.str_contains(p, "c\\u0001\\b\\t\\n\\f\\u001f") { ok = false; }
    if string.str_contains(p, "\\/") { ok = false; }
  }
  return assert(ok, "encoder: escaping golden (\\\" \\\\ \\u0001 \\b \\t \\n \\f \\u001f, raw UTF-8 passthrough)");
}

// ---------------------------------------------------------------------------
// e7: decimal-string rendering (fixed64 + int64)
// ---------------------------------------------------------------------------

fn e7() -> TestResult {
  var b: OtelSpanBatch = otel_batch_new();
  var s = otel_span_new(TID, SID, "big", OTEL_SPAN_KIND_INTERNAL, 0, 9223372036854775807);
  otel_span_add_attribute(&mut s, otel_attr_int("min.int", 0 - 9223372036854775807));
  otel_batch_push(&mut b, s);
  let r = otel_encode_json(&b, &empty_res(), &empty_scope());
  var ok = false;
  if r.is_ok {
    let p: Str = r.value;
    let golden = "{\"resourceSpans\":[{\"resource\":{},\"scopeSpans\":[{\"scope\":{},\"spans\":[{\"traceId\":\"0af7651916cd43dd8448eb211c80319c\",\"spanId\":\"b7ad6b7169203331\",\"name\":\"big\",\"kind\":1,\"startTimeUnixNano\":\"0\",\"endTimeUnixNano\":\"9223372036854775807\",\"attributes\":[{\"key\":\"min.int\",\"value\":{\"intValue\":\"-9223372036854775807\"}}]}]}]}]}";
    ok = streq(p, golden);
    if p.len() != 311 { ok = false; }
  }
  return assert(ok, "encoder: decimal-string rendering golden (0, Int max, negative intValue; 311 bytes)");
}

// ---------------------------------------------------------------------------
// e8: attribute insertion order, bool false, negative double
// ---------------------------------------------------------------------------

fn e8() -> TestResult {
  var b: OtelSpanBatch = otel_batch_new();
  var s = otel_span_new(TID, SID, "ord", OTEL_SPAN_KIND_INTERNAL, 1, 2);
  otel_span_add_attribute(&mut s, otel_attr_str("b", "1"));
  otel_span_add_attribute(&mut s, otel_attr_str("a", "2"));
  otel_span_add_attribute(&mut s, otel_attr_str("c", "3"));
  otel_span_add_attribute(&mut s, otel_attr_bool("no", false));
  otel_span_add_attribute(&mut s, otel_attr_double("neg", 0.0 - 2.5));
  otel_batch_push(&mut b, s);
  let r = otel_encode_json(&b, &empty_res(), &empty_scope());
  var ok = false;
  if r.is_ok {
    let p: Str = r.value;
    let golden = "{\"resourceSpans\":[{\"resource\":{},\"scopeSpans\":[{\"scope\":{},\"spans\":[{\"traceId\":\"0af7651916cd43dd8448eb211c80319c\",\"spanId\":\"b7ad6b7169203331\",\"name\":\"ord\",\"kind\":1,\"startTimeUnixNano\":\"1\",\"endTimeUnixNano\":\"2\",\"attributes\":[{\"key\":\"b\",\"value\":{\"stringValue\":\"1\"}},{\"key\":\"a\",\"value\":{\"stringValue\":\"2\"}},{\"key\":\"c\",\"value\":{\"stringValue\":\"3\"}},{\"key\":\"no\",\"value\":{\"boolValue\":false}},{\"key\":\"neg\",\"value\":{\"doubleValue\":-2.5}}]}]}]}]}";
    ok = streq(p, golden);
    if p.len() != 435 { ok = false; }
  }
  return assert(ok, "encoder: attribute insertion order golden (b,a,c then false, -2.5; 435 bytes)");
}

// ---------------------------------------------------------------------------
// e9: id case pass-through (spec: hex ids are case-insensitive)
// ---------------------------------------------------------------------------

fn e9() -> TestResult {
  var b: OtelSpanBatch = otel_batch_new();
  otel_batch_push(&mut b, otel_span_new("0AF7651916CD43DD8448EB211C80319C", "B7AD6B7169203331", "up", OTEL_SPAN_KIND_INTERNAL, 1, 2));
  let r = otel_encode_json(&b, &empty_res(), &empty_scope());
  var ok = false;
  if r.is_ok {
    let p: Str = r.value;
    let golden = "{\"resourceSpans\":[{\"resource\":{},\"scopeSpans\":[{\"scope\":{},\"spans\":[{\"traceId\":\"0AF7651916CD43DD8448EB211C80319C\",\"spanId\":\"B7AD6B7169203331\",\"name\":\"up\",\"kind\":1,\"startTimeUnixNano\":\"1\",\"endTimeUnixNano\":\"2\"}]}]}]}";
    ok = streq(p, golden);
    if string.str_contains(p, "0af76519") { ok = false; }
  }
  return assert(ok, "encoder: uppercase hex ids pass through verbatim (case-insensitive ids)");
}

// ---------------------------------------------------------------------------
// e10: scope attributes
// ---------------------------------------------------------------------------

fn e10() -> TestResult {
  var b: OtelSpanBatch = otel_batch_new();
  otel_batch_push(&mut b, otel_span_new(TID, SID, "op", OTEL_SPAN_KIND_INTERNAL, 1, 2));
  var scope: OtelScope = otel_scope_new("lib", "2");
  scope.attributes.push(otel_attr_bool("beta", true));
  let r = otel_encode_json(&b, &empty_res(), &scope);
  var ok = false;
  if r.is_ok {
    let p: Str = r.value;
    let golden = "{\"resourceSpans\":[{\"resource\":{},\"scopeSpans\":[{\"scope\":{\"name\":\"lib\",\"version\":\"2\",\"attributes\":[{\"key\":\"beta\",\"value\":{\"boolValue\":true}}]},\"spans\":[{\"traceId\":\"0af7651916cd43dd8448eb211c80319c\",\"spanId\":\"b7ad6b7169203331\",\"name\":\"op\",\"kind\":1,\"startTimeUnixNano\":\"1\",\"endTimeUnixNano\":\"2\"}]}]}]}";
    ok = streq(p, golden);
    if p.len() != 298 { ok = false; }
  }
  return assert(ok, "encoder: scope attributes golden (name, version, attributes; 298 bytes)");
}

// ---------------------------------------------------------------------------
// e11: canonical byte rules -- no insignificant whitespace, fixed frame
// ---------------------------------------------------------------------------

fn e11() -> TestResult {
  var b: OtelSpanBatch = otel_batch_new();
  var s = otel_span_new(TID, SID, "canon", OTEL_SPAN_KIND_SERVER, 1, 2);
  otel_span_add_attribute(&mut s, otel_attr_str("k", "v"));
  otel_batch_push(&mut b, s);
  var res: OtelResource = otel_resource_new();
  res.attributes.push(otel_attr_str("service.name", "x"));
  let scope: OtelScope = otel_scope_new("lib", "1");
  let r = otel_encode_json(&b, &res, &scope);
  var ok = true;
  if !r.is_ok { ok = false; } else {
    let p: Str = r.value;
    let pb = bytes_of(p);
    var i = 0;
    while i < pb.len() {
      let v: Int = (pb[i] as Int) & 255;
      if v == 32 { ok = false; }
      if v == 10 { ok = false; }
      if v == 13 { ok = false; }
      if v < 32 { ok = false; }
      i = i + 1;
    }
    if !streq(string.str_slice(p, 0, 18), "{\"resourceSpans\":[") { ok = false; }
    if p.byte_at(p.len() - 1) != 125u8 { ok = false; }
    if !string.str_contains(p, "\"resource\":{") { ok = false; }
    // deterministic: a second encode is byte-identical
    let r2 = otel_encode_json(&b, &res, &scope);
    if r2.is_ok {
      if !streq(p, r2.value) { ok = false; }
    } else { ok = false; }
  }
  return assert(ok, "encoder: canonical rules (no raw whitespace, fixed frame, byte-deterministic)");
}

// ---------------------------------------------------------------------------
// e12: typed encoder error pass-through
// ---------------------------------------------------------------------------

fn e12() -> TestResult {
  var ok = true;
  let tid = TID;
  let sid = SID;

  var empty_batch: OtelSpanBatch = otel_batch_new();
  if enc_err_kind(&empty_batch, &empty_res(), &empty_scope()) != OTEL_ERR_EMPTY { ok = false; }

  var b_bad_id: OtelSpanBatch = otel_batch_new();
  otel_batch_push(&mut b_bad_id, otel_span_new("zz", sid, "op", OTEL_SPAN_KIND_INTERNAL, 0, 1));
  if enc_err_kind(&b_bad_id, &empty_res(), &empty_scope()) != OTEL_ERR_ID { ok = false; }

  var b_bad_time: OtelSpanBatch = otel_batch_new();
  otel_batch_push(&mut b_bad_time, otel_span_new(tid, sid, "op", OTEL_SPAN_KIND_INTERNAL, 9, 1));
  if enc_err_kind(&b_bad_time, &empty_res(), &empty_scope()) != OTEL_ERR_TIME { ok = false; }

  var b_bad_name: OtelSpanBatch = otel_batch_new();
  otel_batch_push(&mut b_bad_name, otel_span_new(tid, sid, "", OTEL_SPAN_KIND_INTERNAL, 0, 1));
  if enc_err_kind(&b_bad_name, &empty_res(), &empty_scope()) != OTEL_ERR_NAME { ok = false; }

  var b_bad_kind: OtelSpanBatch = otel_batch_new();
  otel_batch_push(&mut b_bad_kind, otel_span_new(tid, sid, "op", 9, 0, 1));
  if enc_err_kind(&b_bad_kind, &empty_res(), &empty_scope()) != OTEL_ERR_KIND { ok = false; }

  var b_bad_status: OtelSpanBatch = otel_batch_new();
  var s_bs = otel_span_new(tid, sid, "op", OTEL_SPAN_KIND_INTERNAL, 0, 1);
  otel_span_set_status(&mut s_bs, 5, "");
  otel_batch_push(&mut b_bad_status, s_bs);
  if enc_err_kind(&b_bad_status, &empty_res(), &empty_scope()) != OTEL_ERR_STATUS { ok = false; }

  var b_dup: OtelSpanBatch = otel_batch_new();
  var s_dup = otel_span_new(tid, sid, "op", OTEL_SPAN_KIND_INTERNAL, 0, 1);
  otel_span_add_attribute(&mut s_dup, otel_attr_str("k", "1"));
  otel_span_add_attribute(&mut s_dup, otel_attr_str("k", "2"));
  otel_batch_push(&mut b_dup, s_dup);
  if enc_err_kind(&b_dup, &empty_res(), &empty_scope()) != OTEL_ERR_ATTRIBUTE { ok = false; }

  var b_nan: OtelSpanBatch = otel_batch_new();
  var s_nan = otel_span_new(tid, sid, "op", OTEL_SPAN_KIND_INTERNAL, 0, 1);
  otel_span_add_attribute(&mut s_nan, otel_attr_double("nan", constants.nan()));
  otel_batch_push(&mut b_nan, s_nan);
  if enc_err_kind(&b_nan, &empty_res(), &empty_scope()) != OTEL_ERR_VALUE { ok = false; }

  var b_129: OtelSpanBatch = otel_batch_new();
  var s_129 = otel_span_new(tid, sid, "op", OTEL_SPAN_KIND_INTERNAL, 0, 1);
  var i = 0;
  while i < 129 {
    s_129.attributes.push(otel_attr_int("k" + i.to_str(), i));
    i = i + 1;
  }
  otel_batch_push(&mut b_129, s_129);
  if enc_err_kind(&b_129, &empty_res(), &empty_scope()) != OTEL_ERR_LIMIT { ok = false; }

  // resource attributes validate before scope attributes (documented order)
  var b_ok: OtelSpanBatch = otel_batch_new();
  otel_batch_push(&mut b_ok, otel_span_new(tid, sid, "op", OTEL_SPAN_KIND_INTERNAL, 0, 1));
  var res_bad: OtelResource = otel_resource_new();
  res_bad.attributes.push(otel_attr_str("", "v"));
  var scope_bad: OtelScope = otel_scope_new("", "");
  scope_bad.attributes.push(otel_attr_str("", "v"));
  if enc_err_kind(&b_ok, &res_bad, &scope_bad) != OTEL_ERR_ATTRIBUTE { ok = false; }

  var good_res: OtelResource = otel_resource_new();
  if enc_err_kind(&b_ok, &good_res, &scope_bad) != OTEL_ERR_ATTRIBUTE { ok = false; }
  return assert(ok, "encoder: typed error pass-through (empty/id/time/name/kind/status/attr/value/limit)");
}

// ---------------------------------------------------------------------------
// Runner
// ---------------------------------------------------------------------------

pub fn run_suite() -> Int {
  var failed: Int = 0;
  let r1 = e1();
  if r1.passed { io.println("  [PASS] " + r1.name); } else { io.println("  [FAIL] " + r1.name); failed = failed + 1; }
  let r2 = e2();
  if r2.passed { io.println("  [PASS] " + r2.name); } else { io.println("  [FAIL] " + r2.name); failed = failed + 1; }
  let r3 = e3();
  if r3.passed { io.println("  [PASS] " + r3.name); } else { io.println("  [FAIL] " + r3.name); failed = failed + 1; }
  let r4 = e4();
  if r4.passed { io.println("  [PASS] " + r4.name); } else { io.println("  [FAIL] " + r4.name); failed = failed + 1; }
  let r5 = e5();
  if r5.passed { io.println("  [PASS] " + r5.name); } else { io.println("  [FAIL] " + r5.name); failed = failed + 1; }
  let r6 = e6();
  if r6.passed { io.println("  [PASS] " + r6.name); } else { io.println("  [FAIL] " + r6.name); failed = failed + 1; }
  let r7 = e7();
  if r7.passed { io.println("  [PASS] " + r7.name); } else { io.println("  [FAIL] " + r7.name); failed = failed + 1; }
  let r8 = e8();
  if r8.passed { io.println("  [PASS] " + r8.name); } else { io.println("  [FAIL] " + r8.name); failed = failed + 1; }
  let r9 = e9();
  if r9.passed { io.println("  [PASS] " + r9.name); } else { io.println("  [FAIL] " + r9.name); failed = failed + 1; }
  let r10 = e10();
  if r10.passed { io.println("  [PASS] " + r10.name); } else { io.println("  [FAIL] " + r10.name); failed = failed + 1; }
  let r11 = e11();
  if r11.passed { io.println("  [PASS] " + r11.name); } else { io.println("  [FAIL] " + r11.name); failed = failed + 1; }
  let r12 = e12();
  if r12.passed { io.println("  [PASS] " + r12.name); } else { io.println("  [FAIL] " + r12.name); failed = failed + 1; }
  return failed;
}
