// XIOM -- xiom.otel conformance suite, part 3: sink seam and counters
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// The collector sink (payload retention, honest counters), the function
// shaped send hook (success and failure paths) and the error accounting.
// Payloads are compared byte-for-byte against the encoder output; Str
// equality goes through compare.str_compare (BUG 17 discipline).

module xiom.otel.suite_sink

use xiom.io;
use xiom.test;
use xiom.string;
use xiom.string.compare;
use xiom.otel;
use xiom.otel.otlp;
use xiom.otel.sink;

// ---------------------------------------------------------------------------
// Helpers (the capture hook is test-local module state, not library state)
// ---------------------------------------------------------------------------

const TID: Str = "0af7651916cd43dd8448eb211c80319c";
const SID: Str = "b7ad6b7169203331";

var g_capture: Vec[Str] = Vec[Str].new();

fn hook_capture(p: Str) -> Result[Unit, Str] {
  g_capture.push(p);
  return Ok(());
}

fn hook_fail(p: Str) -> Result[Unit, Str] {
  return Err("transport down");
}

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn empty_res() -> OtelResource {
  return otel_resource_new();
}

fn empty_scope() -> OtelScope {
  return otel_scope_new("", "");
}

fn min_batch() -> OtelSpanBatch {
  var b: OtelSpanBatch = otel_batch_new();
  otel_batch_push(&mut b, otel_span_new(TID, SID, "op", OTEL_SPAN_KIND_INTERNAL, 1, 2));
  return b;
}

fn two_batch() -> OtelSpanBatch {
  var b: OtelSpanBatch = otel_batch_new();
  otel_batch_push(&mut b, otel_span_new(TID, "1111111111111111", "first", OTEL_SPAN_KIND_PRODUCER, 10, 20));
  otel_batch_push(&mut b, otel_span_new(TID, "2222222222222222", "second", OTEL_SPAN_KIND_CONSUMER, 30, 40));
  return b;
}

fn stats_ok(r: Result[OtelExportStats, OtelError]) -> Bool {
  if r.is_ok { return true; }
  return false;
}

fn err_kind_of(r: Result[OtelExportStats, OtelError]) -> Int {
  if r.is_ok { return -1; }
  let e: OtelError = r.error;
  return e.kind;
}

// ---------------------------------------------------------------------------
// s1: a fresh sink is empty and zeroed
// ---------------------------------------------------------------------------

fn s1() -> TestResult {
  let sink: OtelSink = otel_sink_new();
  var ok = true;
  if sink.payloads.len() != 0 { ok = false; }
  if sink.spans_exported != 0 { ok = false; }
  if sink.bytes_exported != 0 { ok = false; }
  if sink.errors != 0 { ok = false; }
  return assert(ok, "sink: otel_sink_new starts empty with zero counters");
}

// ---------------------------------------------------------------------------
// s2: first export -- stats, counters, retained payload bytes
// ---------------------------------------------------------------------------

fn s2() -> TestResult {
  var ok = true;
  var sink: OtelSink = otel_sink_new();
  let b = min_batch();
  let r = otel_export(&mut sink, &b, &empty_res(), &empty_scope());
  if !stats_ok(r) { ok = false; } else {
    if r.value.spans != 1 { ok = false; }
    if r.value.bytes != 215 { ok = false; }
  }
  if sink.spans_exported != 1 { ok = false; }
  if sink.bytes_exported != 215 { ok = false; }
  if sink.errors != 0 { ok = false; }
  if sink.payloads.len() != 1 { ok = false; }
  let encoded = otel_encode_json(&b, &empty_res(), &empty_scope());
  if !encoded.is_ok { ok = false; } else {
    if !streq(sink.payloads[0], encoded.value) { ok = false; }
  }
  return assert(ok, "sink: export retains the exact encoder payload (1 span, 215 bytes)");
}

// ---------------------------------------------------------------------------
// s3: counters accumulate across exports
// ---------------------------------------------------------------------------

fn s3() -> TestResult {
  var ok = true;
  var sink: OtelSink = otel_sink_new();
  let b1 = min_batch();
  let b2 = min_batch();
  let r1 = otel_export(&mut sink, &b1, &empty_res(), &empty_scope());
  let r2 = otel_export(&mut sink, &b2, &empty_res(), &empty_scope());
  if !stats_ok(r1) { ok = false; }
  if !stats_ok(r2) { ok = false; }
  if sink.spans_exported != 2 { ok = false; }
  if sink.bytes_exported != 430 { ok = false; }
  if sink.payloads.len() != 2 { ok = false; }
  if sink.errors != 0 { ok = false; }
  if !streq(sink.payloads[0], sink.payloads[1]) { ok = false; }
  return assert(ok, "sink: counters accumulate across exports (2 spans, 430 bytes, 2 payloads)");
}

// ---------------------------------------------------------------------------
// s4: a failed export counts an error and changes nothing else
// ---------------------------------------------------------------------------

fn s4() -> TestResult {
  var ok = true;
  var sink: OtelSink = otel_sink_new();
  let good = min_batch();
  let r0 = otel_export(&mut sink, &good, &empty_res(), &empty_scope());
  if !stats_ok(r0) { ok = false; }
  var bad: OtelSpanBatch = otel_batch_new();
  otel_batch_push(&mut bad, otel_span_new("zz", SID, "op", OTEL_SPAN_KIND_INTERNAL, 0, 1));
  let r1 = otel_export(&mut sink, &bad, &empty_res(), &empty_scope());
  if err_kind_of(r1) != OTEL_ERR_ID { ok = false; }
  if sink.errors != 1 { ok = false; }
  if sink.spans_exported != 1 { ok = false; }
  if sink.bytes_exported != 215 { ok = false; }
  if sink.payloads.len() != 1 { ok = false; }
  return assert(ok, "sink: invalid batch export is Err(ID), errors+1, payloads unchanged");
}

// ---------------------------------------------------------------------------
// s5: empty batch accounting
// ---------------------------------------------------------------------------

fn s5() -> TestResult {
  var ok = true;
  var sink: OtelSink = otel_sink_new();
  var empty: OtelSpanBatch = otel_batch_new();
  let r = otel_export(&mut sink, &empty, &empty_res(), &empty_scope());
  if err_kind_of(r) != OTEL_ERR_EMPTY { ok = false; }
  if sink.errors != 1 { ok = false; }
  if sink.payloads.len() != 0 { ok = false; }
  if sink.spans_exported != 0 { ok = false; }
  if sink.bytes_exported != 0 { ok = false; }
  return assert(ok, "sink: empty batch export is Err(EMPTY) and counts one error");
}

// ---------------------------------------------------------------------------
// s6: send hook success -- exact bytes delivered, payload not retained
// ---------------------------------------------------------------------------

fn s6() -> TestResult {
  var ok = true;
  var sink: OtelSink = otel_sink_new();
  let b = min_batch();
  let before = g_capture.len();
  let r = otel_export_send(&mut sink, &b, &empty_res(), &empty_scope(), hook_capture);
  if !stats_ok(r) { ok = false; } else {
    if r.value.spans != 1 { ok = false; }
    if r.value.bytes != 215 { ok = false; }
  }
  if g_capture.len() != before + 1 { ok = false; }
  let encoded = otel_encode_json(&b, &empty_res(), &empty_scope());
  if !encoded.is_ok { ok = false; } else {
    if !streq(g_capture[before], encoded.value) { ok = false; }
  }
  if sink.payloads.len() != 0 { ok = false; }
  if sink.spans_exported != 1 { ok = false; }
  if sink.bytes_exported != 215 { ok = false; }
  if sink.errors != 0 { ok = false; }
  return assert(ok, "sink: send hook receives the exact payload; sink does not retain it");
}

// ---------------------------------------------------------------------------
// s7: send hook failure -- Err(SINK) with the hook message, counters honest
// ---------------------------------------------------------------------------

fn s7() -> TestResult {
  var ok = true;
  var sink: OtelSink = otel_sink_new();
  let b = min_batch();
  let r = otel_export_send(&mut sink, &b, &empty_res(), &empty_scope(), hook_fail);
  if err_kind_of(r) != OTEL_ERR_SINK { ok = false; } else {
    let e: OtelError = r.error;
    if !string.str_contains(e.message, "transport down") { ok = false; }
    if !string.str_contains(e.message, "send hook failed") { ok = false; }
  }
  if sink.errors != 1 { ok = false; }
  if sink.spans_exported != 0 { ok = false; }
  if sink.bytes_exported != 0 { ok = false; }
  if sink.payloads.len() != 0 { ok = false; }
  // encode failures through the send path validate before the hook runs
  var bad: OtelSpanBatch = otel_batch_new();
  otel_batch_push(&mut bad, otel_span_new("zz", SID, "op", OTEL_SPAN_KIND_INTERNAL, 0, 1));
  let r2 = otel_export_send(&mut sink, &bad, &empty_res(), &empty_scope(), hook_capture);
  if err_kind_of(r2) != OTEL_ERR_ID { ok = false; }
  if sink.errors != 2 { ok = false; }
  return assert(ok, "sink: send failure is Err(SINK) with hook message; encode failure skips hook");
}

// ---------------------------------------------------------------------------
// s8: multi-span stats and byte accounting
// ---------------------------------------------------------------------------

fn s8() -> TestResult {
  var ok = true;
  var sink: OtelSink = otel_sink_new();
  let b = two_batch();
  let r = otel_export(&mut sink, &b, &empty_res(), &empty_scope());
  if !stats_ok(r) { ok = false; } else {
    if r.value.spans != 2 { ok = false; }
    if r.value.bytes != 368 { ok = false; }
  }
  if sink.payloads.len() != 1 { ok = false; }
  if sink.payloads[0].len() != 368 { ok = false; }
  if sink.spans_exported != 2 { ok = false; }
  if sink.bytes_exported != 368 { ok = false; }
  return assert(ok, "sink: multi-span export stats (2 spans, 368 bytes) match the payload");
}

// ---------------------------------------------------------------------------
// Runner
// ---------------------------------------------------------------------------

pub fn run_suite() -> Int {
  var failed: Int = 0;
  let r1 = s1();
  if r1.passed { io.println("  [PASS] " + r1.name); } else { io.println("  [FAIL] " + r1.name); failed = failed + 1; }
  let r2 = s2();
  if r2.passed { io.println("  [PASS] " + r2.name); } else { io.println("  [FAIL] " + r2.name); failed = failed + 1; }
  let r3 = s3();
  if r3.passed { io.println("  [PASS] " + r3.name); } else { io.println("  [FAIL] " + r3.name); failed = failed + 1; }
  let r4 = s4();
  if r4.passed { io.println("  [PASS] " + r4.name); } else { io.println("  [FAIL] " + r4.name); failed = failed + 1; }
  let r5 = s5();
  if r5.passed { io.println("  [PASS] " + r5.name); } else { io.println("  [FAIL] " + r5.name); failed = failed + 1; }
  let r6 = s6();
  if r6.passed { io.println("  [PASS] " + r6.name); } else { io.println("  [FAIL] " + r6.name); failed = failed + 1; }
  let r7 = s7();
  if r7.passed { io.println("  [PASS] " + r7.name); } else { io.println("  [FAIL] " + r7.name); failed = failed + 1; }
  let r8 = s8();
  if r8.passed { io.println("  [PASS] " + r8.name); } else { io.println("  [FAIL] " + r8.name); failed = failed + 1; }
  return failed;
}
