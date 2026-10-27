// XIOM -- xiom.otel conformance suite, part 4: gauge metrics
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// The metrics-gauge surface: construction defaults, attribute insertion and
// validation, typed validator errors (empty name, non-positive time), the
// exact-byte OTLP/JSON golden for one gauge with one attribute, two-point
// insertion order and byte determinism, and the empty-batch payload.
// Expectations are computed from the declared rules in SPEC.md; Str equality
// goes through compare.str_compare (BUG 17 discipline).

module xiom.otel.suite_metrics

use xiom.io;
use xiom.test;
use xiom.string.compare;
use xiom.otel;
use xiom.otel.otlp;

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

fn empty_res() -> OtelResource {
  return otel_resource_new();
}

fn empty_scope() -> OtelScope {
  return otel_scope_new("", "");
}

fn enc_err_kind(batch: &OtelMetricsBatch, res: &OtelResource, scope: &OtelScope) -> Int {
  let r = otel_encode_metrics_json(batch, res, scope);
  if r.is_ok { return -1; }
  let e: OtelError = r.error;
  return e.kind;
}

// ---------------------------------------------------------------------------
// g1: construction defaults
// ---------------------------------------------------------------------------

fn g1() -> TestResult {
  var ok = true;
  let p: OtelGaugePoint = otel_gauge_new("live.sessions", "Live sessions", "{session}", 12.5, 1700000000000000000);
  if !streq(p.name, "live.sessions") { ok = false; }
  if !streq(p.description, "Live sessions") { ok = false; }
  if !streq(p.unit, "{session}") { ok = false; }
  if !(p.value > 12.4) { ok = false; }
  if !(p.value < 12.6) { ok = false; }
  if p.time_unix_nano != 1700000000000000000 { ok = false; }
  if p.attributes.len() != 0 { ok = false; }
  let b: OtelMetricsBatch = otel_metrics_batch_new();
  if b.points.len() != 0 { ok = false; }
  if !ok_unit(otel_validate_metrics_batch(&b)) { ok = false; }
  return assert(ok, "metrics: gauge/batch constructors start with no attributes and no points");
}

// ---------------------------------------------------------------------------
// g2: attribute insertion and validation
// ---------------------------------------------------------------------------

fn g2() -> TestResult {
  var ok = true;
  var p: OtelGaugePoint = otel_gauge_new("replication.lag.bytes", "Lag", "By", 1.5, 100);
  otel_gauge_add_attribute(&mut p, otel_attr_str("service.name", "postgres"));
  otel_gauge_add_attribute(&mut p, otel_attr_int("shard", 3));
  if p.attributes.len() != 2 { ok = false; }
  if !streq(p.attributes[0].key, "service.name") { ok = false; }
  if !streq(p.attributes[1].key, "shard") { ok = false; }
  if !ok_unit(otel_validate_gauge(&p)) { ok = false; }
  otel_gauge_add_attribute(&mut p, otel_attr_bool("service.name", true));
  if err_unit_kind(otel_validate_gauge(&p)) != OTEL_ERR_ATTRIBUTE { ok = false; }
  var q: OtelGaugePoint = otel_gauge_new("q", "d", "u", 0.5, 1);
  otel_gauge_add_attribute(&mut q, otel_attr_str("", "v"));
  if err_unit_kind(otel_validate_gauge(&q)) != OTEL_ERR_ATTRIBUTE { ok = false; }
  return assert(ok, "metrics: gauge attributes append in order and validate (dup/empty key errors)");
}

// ---------------------------------------------------------------------------
// g3: empty name is a typed NAME error
// ---------------------------------------------------------------------------

fn g3() -> TestResult {
  var ok = true;
  let p: OtelGaugePoint = otel_gauge_new("", "d", "u", 1.0, 1);
  if err_unit_kind(otel_validate_gauge(&p)) != OTEL_ERR_NAME { ok = false; }
  var b: OtelMetricsBatch = otel_metrics_batch_new();
  otel_metrics_batch_push(&mut b, p);
  if err_unit_kind(otel_validate_metrics_batch(&b)) != OTEL_ERR_NAME { ok = false; }
  if enc_err_kind(&b, &empty_res(), &empty_scope()) != OTEL_ERR_NAME { ok = false; }
  return assert(ok, "metrics: empty gauge name is Err(NAME) in validator and encoder");
}

// ---------------------------------------------------------------------------
// g4: non-positive time is a typed TIME error
// ---------------------------------------------------------------------------

fn g4() -> TestResult {
  var ok = true;
  let zero: OtelGaugePoint = otel_gauge_new("g", "d", "u", 1.0, 0);
  if err_unit_kind(otel_validate_gauge(&zero)) != OTEL_ERR_TIME { ok = false; }
  let neg: OtelGaugePoint = otel_gauge_new("g", "d", "u", 1.0, 0 - 1);
  if err_unit_kind(otel_validate_gauge(&neg)) != OTEL_ERR_TIME { ok = false; }
  let pos: OtelGaugePoint = otel_gauge_new("g", "d", "u", 1.0, 1);
  if !ok_unit(otel_validate_gauge(&pos)) { ok = false; }
  return assert(ok, "metrics: time_unix_nano must be positive (0 and negative are Err(TIME))");
}

// ---------------------------------------------------------------------------
// g5: one gauge with one attribute -- exact bytes
// ---------------------------------------------------------------------------

fn g5() -> TestResult {
  var p: OtelGaugePoint = otel_gauge_new("replication.lag.bytes", "Replication lag in bytes", "By", 12.5, 1700000000000000000);
  otel_gauge_add_attribute(&mut p, otel_attr_str("shard", "s1"));
  var b: OtelMetricsBatch = otel_metrics_batch_new();
  otel_metrics_batch_push(&mut b, p);
  let r = otel_encode_metrics_json(&b, &empty_res(), &empty_scope());
  var ok = false;
  if r.is_ok {
    let payload: Str = r.value;
    let golden = "{\"resourceMetrics\":[{\"resource\":{},\"scopeMetrics\":[{\"scope\":{},\"metrics\":[{\"name\":\"replication.lag.bytes\",\"description\":\"Replication lag in bytes\",\"unit\":\"By\",\"gauge\":{\"dataPoints\":[{\"asDouble\":12.5,\"timeUnixNano\":\"1700000000000000000\",\"attributes\":[{\"key\":\"shard\",\"value\":{\"stringValue\":\"s1\"}}]}]}}]}]}]}";
    ok = streq(payload, golden);
    if payload.len() != 305 { ok = false; }
  }
  return assert(ok, "metrics: one gauge + one attribute exact-byte golden (305 bytes)");
}

// ---------------------------------------------------------------------------
// g6: two points -- insertion order and byte determinism
// ---------------------------------------------------------------------------

fn g6() -> TestResult {
  var b: OtelMetricsBatch = otel_metrics_batch_new();
  otel_metrics_batch_push(&mut b, otel_gauge_new("live.sessions", "Live sessions", "{session}", 42.5, 100));
  otel_metrics_batch_push(&mut b, otel_gauge_new("shard.size.bytes", "Per-shard size", "By", 3.25, 200));
  let r = otel_encode_metrics_json(&b, &empty_res(), &empty_scope());
  var ok = false;
  if r.is_ok {
    let payload: Str = r.value;
    let golden = "{\"resourceMetrics\":[{\"resource\":{},\"scopeMetrics\":[{\"scope\":{},\"metrics\":[{\"name\":\"live.sessions\",\"description\":\"Live sessions\",\"unit\":\"{session}\",\"gauge\":{\"dataPoints\":[{\"asDouble\":42.5,\"timeUnixNano\":\"100\",\"attributes\":[]}]}},{\"name\":\"shard.size.bytes\",\"description\":\"Per-shard size\",\"unit\":\"By\",\"gauge\":{\"dataPoints\":[{\"asDouble\":3.25,\"timeUnixNano\":\"200\",\"attributes\":[]}]}}]}]}]}";
    ok = streq(payload, golden);
    let r2 = otel_encode_metrics_json(&b, &empty_res(), &empty_scope());
    if !r2.is_ok { ok = false; } else {
      if !streq(payload, r2.value) { ok = false; }
    }
  }
  return assert(ok, "metrics: two points encode in insertion order, byte-identically on re-encode");
}

// ---------------------------------------------------------------------------
// g7: empty batch is valid and encodes an empty metrics array
// ---------------------------------------------------------------------------

fn g7() -> TestResult {
  var b: OtelMetricsBatch = otel_metrics_batch_new();
  let r = otel_encode_metrics_json(&b, &empty_res(), &empty_scope());
  var ok = false;
  if r.is_ok {
    let golden = "{\"resourceMetrics\":[{\"resource\":{},\"scopeMetrics\":[{\"scope\":{},\"metrics\":[]}]}]}";
    ok = streq(r.value, golden);
  }
  if !ok_unit(otel_validate_metrics_batch(&b)) { ok = false; }
  return assert(ok, "metrics: empty batch is valid and encodes \"metrics\":[]");
}

// ---------------------------------------------------------------------------
// Runner
// ---------------------------------------------------------------------------

pub fn run_suite() -> Int {
  var failed: Int = 0;
  let r1 = g1();
  if r1.passed { io.println("  [PASS] " + r1.name); } else { io.println("  [FAIL] " + r1.name); failed = failed + 1; }
  let r2 = g2();
  if r2.passed { io.println("  [PASS] " + r2.name); } else { io.println("  [FAIL] " + r2.name); failed = failed + 1; }
  let r3 = g3();
  if r3.passed { io.println("  [PASS] " + r3.name); } else { io.println("  [FAIL] " + r3.name); failed = failed + 1; }
  let r4 = g4();
  if r4.passed { io.println("  [PASS] " + r4.name); } else { io.println("  [FAIL] " + r4.name); failed = failed + 1; }
  let r5 = g5();
  if r5.passed { io.println("  [PASS] " + r5.name); } else { io.println("  [FAIL] " + r5.name); failed = failed + 1; }
  let r6 = g6();
  if r6.passed { io.println("  [PASS] " + r6.name); } else { io.println("  [FAIL] " + r6.name); failed = failed + 1; }
  let r7 = g7();
  if r7.passed { io.println("  [PASS] " + r7.name); } else { io.println("  [FAIL] " + r7.name); failed = failed + 1; }
  return failed;
}
