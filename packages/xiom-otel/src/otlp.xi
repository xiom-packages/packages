// XIOM -- xiom.otel.otlp: deterministic OTLP/JSON encoder (pure XIOM)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Encodes a validated span batch + resource + scope into the OTLP/JSON wire
// structure (ExportTraceServiceRequest): resourceSpans[].scopeSpans[].spans[]
// with hex traceId/spanId, integer enum fields, fixed64 timestamps as decimal
// strings, key/value attribute objects and the optional status object. Also
// encodes a validated gauge metrics batch (ExportMetricsServiceRequest):
// resourceMetrics[].scopeMetrics[].metrics[] with one gauge data point per
// point (asDouble, timeUnixNano as a decimal string, attributes).
//
// Built from the OpenTelemetry Protocol (OTLP) specification and its JSON
// Protobuf Encoding section (hex trace/span ids, integer-only enum values,
// lowerCamelCase keys, 64-bit integers as decimal strings); see PROVENANCE.md.
// No upstream OpenTelemetry implementation code was consulted, vendored or
// translated.
//
// Canonical byte rules (declared in SPEC.md section 5; exact-byte golden
// tested): no insignificant whitespace, fixed key order (proto field-number
// order), attribute order = insertion order, keys/strings escaped with the
// JSON escapes below and raw UTF-8 pass-through, empty optional objects
// omitted (parentSpanId, attributes, status). Deterministic: no clock, no
// randomness, no globals.
//
// The encoder validates first and returns the typed model error unchanged:
// empty batch (OTEL_ERR_EMPTY), span/attribute violations (OTEL_ERR_ID /
// OTEL_ERR_NAME / OTEL_ERR_TIME / OTEL_ERR_ATTRIBUTE / OTEL_ERR_KIND /
// OTEL_ERR_STATUS / OTEL_ERR_VALUE), caps (OTEL_ERR_LIMIT). Precedence:
// batch (count, then spans in order), then resource attributes, then scope
// attributes.

module xiom.otel.otlp

use xiom.otel;
use xiom.string.builder;
use xiom.convert;

// ---------------------------------------------------------------------------
// Leaf helpers (Ok/Err construction confined here; v0.64.x discipline)
// ---------------------------------------------------------------------------

fn _ok_str(s: Str) -> Result[Str, OtelError] {
  return Ok(s);
}

fn _err_str(e: OtelError) -> Result[Str, OtelError] {
  return Err(e);
}

// Lowercase hex digit for a nibble 0..15 (used by \u00xx control escapes).
fn _hex_digit_byte(n: Int) -> UInt8 {
  if n < 10 { return (48 + n) as UInt8; }
  return (87 + n) as UInt8;
}

// ---------------------------------------------------------------------------
// Primitive emitters
// ---------------------------------------------------------------------------

// Append a JSON string literal. Escapes: \" \\ \b \t \n \f \r and any byte
// below 0x20 as \u00xx (lowercase hex). `/` is NOT escaped. All other bytes
// (including multi-byte UTF-8) pass through verbatim.
fn _push_json_string(out: &mut Vec[UInt8], s: Str) {
  builder.sb_push_byte(out, 34u8);
  var i = 0;
  let n = s.len();
  while i < n {
    let b: UInt8 = s.byte_at(i);
    let v: Int = (b as Int) & 255;
    if v == 34 {
      builder.sb_push_byte(out, 92u8);
      builder.sb_push_byte(out, 34u8);
    } elif v == 92 {
      builder.sb_push_byte(out, 92u8);
      builder.sb_push_byte(out, 92u8);
    } elif v == 8 {
      builder.sb_push_byte(out, 92u8);
      builder.sb_push_byte(out, 98u8);
    } elif v == 9 {
      builder.sb_push_byte(out, 92u8);
      builder.sb_push_byte(out, 116u8);
    } elif v == 10 {
      builder.sb_push_byte(out, 92u8);
      builder.sb_push_byte(out, 110u8);
    } elif v == 12 {
      builder.sb_push_byte(out, 92u8);
      builder.sb_push_byte(out, 102u8);
    } elif v == 13 {
      builder.sb_push_byte(out, 92u8);
      builder.sb_push_byte(out, 114u8);
    } elif v < 32 {
      builder.sb_push_byte(out, 92u8);
      builder.sb_push_byte(out, 117u8);
      builder.sb_push_byte(out, 48u8);
      builder.sb_push_byte(out, 48u8);
      builder.sb_push_byte(out, _hex_digit_byte(v >> 4));
      builder.sb_push_byte(out, _hex_digit_byte(v & 15));
    } else {
      builder.sb_push_byte(out, b);
    }
    i = i + 1;
  }
  builder.sb_push_byte(out, 34u8);
}

// Append the decimal rendering of an Int (sign-aware; covers the full Int
// range including the minimum, whose negation would overflow). No '+' sign,
// no leading zeros.
fn _push_decimal(out: &mut Vec[UInt8], v: Int) {
  if v == 0 {
    builder.sb_push_byte(out, 48u8);
    return;
  }
  var neg = false;
  var n = v;
  if n < 0 { neg = true; }
  var digits: [20]UInt8;
  var pos = 20;
  while n != 0 {
    var d = n % 10;
    if d < 0 { d = 0 - d; }
    pos = pos - 1;
    digits[pos] = (48 + d) as UInt8;
    n = n / 10;
  }
  if neg { builder.sb_push_byte(out, 45u8); }
  while pos < 20 {
    builder.sb_push_byte(out, digits[pos]);
    pos = pos + 1;
  }
}

// ---------------------------------------------------------------------------
// OTLP/JSON structure emitters (call order fixes the canonical key order)
// ---------------------------------------------------------------------------

// One AnyValue: {"stringValue": s} | {"intValue": "d"} | {"boolValue": b}
// | {"doubleValue": n}. intValue is a decimal STRING (proto3 JSON mapping for
// int64); doubleValue is a JSON number (finite, validated).
fn _push_value(out: &mut Vec[UInt8], v: &OtelValue) {
  if v.kind == OTEL_VALUE_STR {
    builder.sb_push_str(out, "{\"stringValue\":");
    _push_json_string(out, v.str_value);
    builder.sb_push_byte(out, 125u8);
  } elif v.kind == OTEL_VALUE_INT {
    builder.sb_push_str(out, "{\"intValue\":\"");
    _push_decimal(out, v.int_value);
    builder.sb_push_str(out, "\"}");
  } elif v.kind == OTEL_VALUE_BOOL {
    builder.sb_push_str(out, "{\"boolValue\":");
    if v.bool_value {
      builder.sb_push_str(out, "true");
    } else {
      builder.sb_push_str(out, "false");
    }
    builder.sb_push_byte(out, 125u8);
  } else {
    builder.sb_push_str(out, "{\"doubleValue\":");
    builder.sb_push_str(out, convert.float_to_string(v.double_value));
    builder.sb_push_byte(out, 125u8);
  }
}

// One KeyValue: {"key": k, "value": v}.
fn _push_attribute(out: &mut Vec[UInt8], attr: &OtelAttribute) {
  builder.sb_push_str(out, "{\"key\":");
  _push_json_string(out, attr.key);
  builder.sb_push_str(out, ",\"value\":");
  _push_value(out, &attr.value);
  builder.sb_push_byte(out, 125u8);
}

// A bare attribute array: [kv, kv, ...].
fn _push_attribute_list(out: &mut Vec[UInt8], attributes: &Vec[OtelAttribute]) {
  builder.sb_push_byte(out, 91u8);
  var i = 0;
  while i < attributes.len() {
    if i > 0 { builder.sb_push_byte(out, 44u8); }
    let a: OtelAttribute = attributes[i];
    _push_attribute(out, &a);
    i = i + 1;
  }
  builder.sb_push_byte(out, 93u8);
}

// The Resource message: {"attributes": [...]}, or {} when it has none.
fn _push_resource(out: &mut Vec[UInt8], resource: &OtelResource) {
  if resource.attributes.len() == 0 {
    builder.sb_push_str(out, "{}");
    return;
  }
  builder.sb_push_str(out, "{\"attributes\":");
  _push_attribute_list(out, &resource.attributes);
  builder.sb_push_byte(out, 125u8);
}

// The InstrumentationScope message: name, version and attributes, each
// emitted only when non-empty ({} for an empty scope).
fn _push_scope(out: &mut Vec[UInt8], scope: &OtelScope) {
  builder.sb_push_byte(out, 123u8);
  var any = false;
  if scope.name.len() > 0 {
    builder.sb_push_str(out, "\"name\":");
    _push_json_string(out, scope.name);
    any = true;
  }
  if scope.version.len() > 0 {
    if any { builder.sb_push_byte(out, 44u8); }
    builder.sb_push_str(out, "\"version\":");
    _push_json_string(out, scope.version);
    any = true;
  }
  if scope.attributes.len() > 0 {
    if any { builder.sb_push_byte(out, 44u8); }
    builder.sb_push_str(out, "\"attributes\":");
    _push_attribute_list(out, &scope.attributes);
  }
  builder.sb_push_byte(out, 125u8);
}

// One Span. Key order = proto field-number order: traceId, spanId,
// parentSpanId?, name, kind, startTimeUnixNano, endTimeUnixNano,
// attributes?, status?. parentSpanId is omitted for a root span, attributes
// when empty, status when UNSET. Timestamps are decimal strings (fixed64).
fn _push_span(out: &mut Vec[UInt8], span: &OtelSpan) {
  builder.sb_push_str(out, "{\"traceId\":");
  _push_json_string(out, span.trace_id);
  builder.sb_push_str(out, ",\"spanId\":");
  _push_json_string(out, span.span_id);
  if span.parent_span_id.len() != 0 {
    builder.sb_push_str(out, ",\"parentSpanId\":");
    _push_json_string(out, span.parent_span_id);
  }
  builder.sb_push_str(out, ",\"name\":");
  _push_json_string(out, span.name);
  builder.sb_push_str(out, ",\"kind\":");
  _push_decimal(out, span.kind);
  builder.sb_push_str(out, ",\"startTimeUnixNano\":\"");
  _push_decimal(out, span.start_unix_nano);
  builder.sb_push_str(out, "\",\"endTimeUnixNano\":\"");
  _push_decimal(out, span.end_unix_nano);
  builder.sb_push_str(out, "\"");
  if span.attributes.len() > 0 {
    builder.sb_push_str(out, ",\"attributes\":");
    _push_attribute_list(out, &span.attributes);
  }
  if span.status != OTEL_STATUS_UNSET {
    builder.sb_push_str(out, ",\"status\":{\"code\":");
    _push_decimal(out, span.status);
    if span.status == OTEL_STATUS_ERROR && span.status_message.len() > 0 {
      builder.sb_push_str(out, ",\"message\":");
      _push_json_string(out, span.status_message);
    }
    builder.sb_push_byte(out, 125u8);
  }
  builder.sb_push_byte(out, 125u8);
}

// One gauge data point. Key order matches the OTLP NumberDataPoint shape:
// asDouble (finite, validated), timeUnixNano (fixed64 decimal string),
// attributes (always emitted, insertion order).
fn _push_gauge_point(out: &mut Vec[UInt8], point: &OtelGaugePoint) {
  builder.sb_push_str(out, "{\"asDouble\":");
  builder.sb_push_str(out, convert.float_to_string(point.value));
  builder.sb_push_str(out, ",\"timeUnixNano\":\"");
  _push_decimal(out, point.time_unix_nano);
  builder.sb_push_str(out, "\",\"attributes\":");
  _push_attribute_list(out, &point.attributes);
  builder.sb_push_byte(out, 125u8);
}

// One metric entry (gauge with exactly one data point). Key order = proto
// field-number order: name, description, unit, gauge.
fn _push_metric(out: &mut Vec[UInt8], point: &OtelGaugePoint) {
  builder.sb_push_str(out, "{\"name\":");
  _push_json_string(out, point.name);
  builder.sb_push_str(out, ",\"description\":");
  _push_json_string(out, point.description);
  builder.sb_push_str(out, ",\"unit\":");
  _push_json_string(out, point.unit);
  builder.sb_push_str(out, ",\"gauge\":{\"dataPoints\":[");
  _push_gauge_point(out, point);
  builder.sb_push_str(out, "]}}");
}

// ---------------------------------------------------------------------------
// Public entry point
// ---------------------------------------------------------------------------

/// Encode into the OTLP/JSON wire bytes (ExportTraceServiceRequest with one
/// resourceSpans entry, one scopeSpans entry and the batch's spans in
/// order). Validates first; returns the validator's typed error unchanged on
/// any breach. Deterministic byte-for-byte. Complexity: O(total payload).
pub fn otel_encode_json(spans_batch: &OtelSpanBatch, resource: &OtelResource, scope: &OtelScope) -> Result[Str, OtelError] {
  let br = otel_validate_batch(spans_batch);
  if !br.is_ok {
    let e: OtelError = br.error;
    return _err_str(e);
  }
  let rr = otel_validate_attributes(&resource.attributes);
  if !rr.is_ok {
    let e: OtelError = rr.error;
    return _err_str(e);
  }
  let sr = otel_validate_attributes(&scope.attributes);
  if !sr.is_ok {
    let e: OtelError = sr.error;
    return _err_str(e);
  }
  var out: Vec[UInt8] = builder.sb_new();
  builder.sb_push_str(&mut out, "{\"resourceSpans\":[{\"resource\":");
  _push_resource(&mut out, resource);
  builder.sb_push_str(&mut out, ",\"scopeSpans\":[{\"scope\":");
  _push_scope(&mut out, scope);
  builder.sb_push_str(&mut out, ",\"spans\":[");
  var i = 0;
  while i < spans_batch.spans.len() {
    if i > 0 { builder.sb_push_byte(&mut out, 44u8); }
    let s: OtelSpan = spans_batch.spans[i];
    _push_span(&mut out, &s);
    i = i + 1;
  }
  builder.sb_push_str(&mut out, "]}]}]}");
  return _ok_str(builder.sb_to_str(&out));
}

/// Encode into the OTLP/JSON metrics wire bytes
/// (ExportMetricsServiceRequest with one resourceMetrics entry, one
/// scopeMetrics entry and one gauge metric per point, in order). Validates
/// first (batch, then resource attributes, then scope attributes); returns
/// the validator's typed error unchanged on any breach. An empty batch is
/// valid and encodes `"metrics":[]`. Deterministic byte-for-byte.
/// Complexity: O(total payload).
pub fn otel_encode_metrics_json(batch: &OtelMetricsBatch, resource: &OtelResource, scope: &OtelScope) -> Result[Str, OtelError] {
  let br = otel_validate_metrics_batch(batch);
  if !br.is_ok {
    let e: OtelError = br.error;
    return _err_str(e);
  }
  let rr = otel_validate_attributes(&resource.attributes);
  if !rr.is_ok {
    let e: OtelError = rr.error;
    return _err_str(e);
  }
  let sr = otel_validate_attributes(&scope.attributes);
  if !sr.is_ok {
    let e: OtelError = sr.error;
    return _err_str(e);
  }
  var out: Vec[UInt8] = builder.sb_new();
  builder.sb_push_str(&mut out, "{\"resourceMetrics\":[{\"resource\":");
  _push_resource(&mut out, resource);
  builder.sb_push_str(&mut out, ",\"scopeMetrics\":[{\"scope\":");
  _push_scope(&mut out, scope);
  builder.sb_push_str(&mut out, ",\"metrics\":[");
  var i = 0;
  while i < batch.points.len() {
    if i > 0 { builder.sb_push_byte(&mut out, 44u8); }
    let p: OtelGaugePoint = batch.points[i];
    _push_metric(&mut out, &p);
    i = i + 1;
  }
  builder.sb_push_str(&mut out, "]}]}]}");
  return _ok_str(builder.sb_to_str(&out));
}
