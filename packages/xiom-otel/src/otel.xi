// XIOM -- xiom.otel: OpenTelemetry trace model (pure XIOM, no FFI)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// The typed model shared by the whole package: attribute values, attributes,
// resource, scope, spans, batches, the deterministic tracer, the constants,
// caps, hex/id helpers and the typed validators the encoder enforces.
//
// Independence: built from the OpenTelemetry Protocol (OTLP) specification
// and its JSON mapping (see PROVENANCE.md); no upstream implementation code
// was consulted, vendored or translated.
//
// Determinism: no wall clock (timestamps are caller-provided) and no
// randomness (ids are caller-provided or derived from a seed). No globals.
//
// Language notes (XIOM v0.64.5): free functions only; no `?` propagation;
// Ok/Err construction is confined to the leaf helpers below; Str equality
// goes through xiom.string.compare; the value model is a flat kind-tagged
// struct (see OtelValue).

module xiom.otel

use xiom.string.compare;
use xiom.string.builder;

// --- Span kinds (OTLP Span.SpanKind integer values; UNSPECIFIED not modeled)

/// Span kind: operation internal to an application.
pub const OTEL_SPAN_KIND_INTERNAL: Int = 1;
/// Span kind: server-side handling of a remote request.
pub const OTEL_SPAN_KIND_SERVER: Int = 2;
/// Span kind: request to a remote service.
pub const OTEL_SPAN_KIND_CLIENT: Int = 3;
/// Span kind: producer sending a message to a broker.
pub const OTEL_SPAN_KIND_PRODUCER: Int = 4;
/// Span kind: consumer receiving a message from a broker.
pub const OTEL_SPAN_KIND_CONSUMER: Int = 5;

// --- Span status codes (OTLP Status.StatusCode integer values)

/// Status: unset (the encoder omits the status object).
pub const OTEL_STATUS_UNSET: Int = 0;
/// Status: verified success.
pub const OTEL_STATUS_OK: Int = 1;
/// Status: the span contains an error.
pub const OTEL_STATUS_ERROR: Int = 2;

// --- Attribute value kinds (otel_value_kind results)

/// Attribute value kind: string.
pub const OTEL_VALUE_STR: Int = 1;
/// Attribute value kind: signed integer.
pub const OTEL_VALUE_INT: Int = 2;
/// Attribute value kind: boolean.
pub const OTEL_VALUE_BOOL: Int = 3;
/// Attribute value kind: 64-bit float.
pub const OTEL_VALUE_DOUBLE: Int = 4;

// --- Error kinds (OtelError.kind)

/// Error kind: no error (sentinel; never produced as a failure).
pub const OTEL_ERR_NONE: Int = 0;
/// Error kind: invalid id or hex input (length, non-hex character, all-zero).
pub const OTEL_ERR_ID: Int = 1;
/// Error kind: empty or over-long span name.
pub const OTEL_ERR_NAME: Int = 2;
/// Error kind: timestamp shape (negative start, end before start).
pub const OTEL_ERR_TIME: Int = 3;
/// Error kind: attribute shape (empty key, duplicate key).
pub const OTEL_ERR_ATTRIBUTE: Int = 4;
/// Error kind: span kind outside the modeled 1..5 set.
pub const OTEL_ERR_KIND: Int = 5;
/// Error kind: status code outside 0..2, or a message on a non-error status.
pub const OTEL_ERR_STATUS: Int = 6;
/// Error kind: attribute value not representable (non-finite double).
pub const OTEL_ERR_VALUE: Int = 7;
/// Error kind: a documented cap exceeded.
pub const OTEL_ERR_LIMIT: Int = 8;
/// Error kind: empty span batch (OTLP senders should not emit empty envelopes).
pub const OTEL_ERR_EMPTY: Int = 9;
/// Error kind: the caller-supplied send hook failed.
pub const OTEL_ERR_SINK: Int = 10;

// --- Documented caps (breach is kind OTEL_ERR_LIMIT; validators enforce)

/// Maximum attributes per list (span, resource or scope).
pub const OTEL_MAX_ATTRIBUTES: Int = 128;
/// Maximum spans per exported batch.
pub const OTEL_MAX_BATCH_SPANS: Int = 1024;
/// Maximum span-name length in bytes.
pub const OTEL_MAX_NAME_LEN: Int = 1024;

// --- Types

/// A typed model/encoder failure: `kind` is one of OTEL_ERR_* and `message`
/// names the offending field. The encode path never fails untyped.
pub type OtelError = {
  kind: Int;
  message: Str;
}

/// A typed attribute value: a kind tag (OTEL_VALUE_*) plus all four payload
/// slots; only the slot named by `kind` is meaningful. A flat kind-tagged
/// struct, deliberately not a payload enum: XIOM v0.64.5 mislowers Float64
/// payloads inside enums (denormal garbage / silent non-match), so floats
/// live in plain struct fields. Arrays/byte values are out of scope (SPEC).
pub type OtelValue = {
  kind: Int;          // OTEL_VALUE_STR | OTEL_VALUE_INT | OTEL_VALUE_BOOL | OTEL_VALUE_DOUBLE
  str_value: Str;     // meaningful when kind = OTEL_VALUE_STR
  int_value: Int;     // meaningful when kind = OTEL_VALUE_INT
  bool_value: Bool;   // meaningful when kind = OTEL_VALUE_BOOL
  double_value: Float64; // meaningful when kind = OTEL_VALUE_DOUBLE
}

/// One attribute key/value pair. Keys are non-empty and unique per list
/// (validated at encode time).
pub type OtelAttribute = {
  key: Str;
  value: OtelValue;
}

/// The resource a batch of spans originates from: service/host identity as
/// attributes.
pub type OtelResource = {
  attributes: Vec[OtelAttribute];
}

/// Instrumentation scope (the OTel "InstrumentationScope"): library name,
/// version and optional attributes.
pub type OtelScope = {
  name: Str;
  version: Str;
  attributes: Vec[OtelAttribute];
}

/// One span. `trace_id` and `span_id` are hex text (32 and 16 characters;
/// both digit cases accepted, per the OTLP JSON mapping note).
/// `parent_span_id` is "" for a root span, else 16 hex characters. Times
/// are Unix-epoch nanoseconds, caller-provided; the model holds no clock.
pub type OtelSpan = {
  trace_id: Str;
  span_id: Str;
  parent_span_id: Str;
  name: Str;
  kind: Int;
  start_unix_nano: Int;
  end_unix_nano: Int;
  attributes: Vec[OtelAttribute];
  status: Int;
  status_message: Str;
}

/// An ordered batch of spans (insertion order preserved end to end).
pub type OtelSpanBatch = {
  spans: Vec[OtelSpan];
}

/// One gauge data point (a single numeric sample at one instant). `value`
/// becomes `asDouble` and `time_unix_nano` is caller-provided Unix-epoch
/// nanoseconds; the model holds no clock. Nothing is validated here.
pub type OtelGaugePoint = {
  name: Str;
  description: Str;
  unit: Str;
  value: Float64;
  time_unix_nano: Int;
  attributes: Vec[OtelAttribute];
}

/// An ordered batch of gauge points (insertion order preserved end to end;
/// one OTLP metric entry per point). An empty batch is valid.
pub type OtelMetricsBatch = {
  points: Vec[OtelGaugePoint];
}

/// A deterministic span factory: one trace id derived from `seed`, span ids
/// derived from (`seed`, `counter`) in call order. No clock, no randomness.
pub type OtelTracer = {
  trace_id: Str;
  seed: Int;
  counter: Int;
}

// --- Leaf helpers (Ok/Err construction confined here; v0.64.x discipline)

fn _ok_unit() -> Result[Unit, OtelError] {
  return Ok(());
}

fn _err_unit(e: OtelError) -> Result[Unit, OtelError] {
  return Err(e);
}

fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], OtelError] {
  return Ok(v);
}

fn _err_bytes(e: OtelError) -> Result[Vec[UInt8], OtelError] {
  return Err(e);
}

// --- Construction helpers

/// Build a typed error. `kind` is one of OTEL_ERR_*.
pub fn otel_error(kind: Int, message: Str) -> OtelError {
  return OtelError { kind: kind, message: message };
}

/// The kind of an attribute value (OTEL_VALUE_*).
pub fn otel_value_kind(value: &OtelValue) -> Int {
  return value.kind;
}

/// The string payload (meaningful for OTEL_VALUE_STR; other kinds yield "").
pub fn otel_value_str(value: &OtelValue) -> Str {
  return value.str_value;
}

/// The integer payload (meaningful for OTEL_VALUE_INT; other kinds yield 0).
pub fn otel_value_int(value: &OtelValue) -> Int {
  return value.int_value;
}

/// The boolean payload (meaningful for OTEL_VALUE_BOOL; else false).
pub fn otel_value_bool(value: &OtelValue) -> Bool {
  return value.bool_value;
}

/// The double payload (meaningful for OTEL_VALUE_DOUBLE; else 0.0).
pub fn otel_value_double(value: &OtelValue) -> Float64 {
  return value.double_value;
}

/// A string attribute.
pub fn otel_attr_str(key: Str, value: Str) -> OtelAttribute {
  return OtelAttribute { key: key; value: OtelValue { kind: OTEL_VALUE_STR; str_value: value; int_value: 0; bool_value: false; double_value: 0.0 } };
}

/// A signed-integer attribute (rendered as a decimal string in OTLP/JSON).
pub fn otel_attr_int(key: Str, value: Int) -> OtelAttribute {
  return OtelAttribute { key: key; value: OtelValue { kind: OTEL_VALUE_INT; str_value: ""; int_value: value; bool_value: false; double_value: 0.0 } };
}

/// A boolean attribute.
pub fn otel_attr_bool(key: Str, value: Bool) -> OtelAttribute {
  return OtelAttribute { key: key; value: OtelValue { kind: OTEL_VALUE_BOOL; str_value: ""; int_value: 0; bool_value: value; double_value: 0.0 } };
}

/// A 64-bit-float attribute (must be finite at encode time).
pub fn otel_attr_double(key: Str, value: Float64) -> OtelAttribute {
  return OtelAttribute { key: key; value: OtelValue { kind: OTEL_VALUE_DOUBLE; str_value: ""; int_value: 0; bool_value: false; double_value: value } };
}

/// An empty resource.
pub fn otel_resource_new() -> OtelResource {
  return OtelResource { attributes: Vec[OtelAttribute].new() };
}

/// A scope with the given library name and version (empty when unknown).
pub fn otel_scope_new(name: Str, version: Str) -> OtelScope {
  return OtelScope { name: name, version: version, attributes: Vec[OtelAttribute].new() };
}

/// A span with no parent, no attributes and status unset; times are
/// caller-provided Unix-epoch nanoseconds. Nothing is validated here.
pub fn otel_span_new(trace_id: Str, span_id: Str, name: Str, kind: Int, start_unix_nano: Int, end_unix_nano: Int) -> OtelSpan {
  return OtelSpan {
    trace_id: trace_id;
    span_id: span_id;
    parent_span_id: "";
    name: name;
    kind: kind;
    start_unix_nano: start_unix_nano;
    end_unix_nano: end_unix_nano;
    attributes: Vec[OtelAttribute].new();
    status: OTEL_STATUS_UNSET;
    status_message: "";
  };
}

/// Set the parent span id ("" makes the span a root again).
pub fn otel_span_set_parent(span: &mut OtelSpan, parent_span_id: Str) {
  span.parent_span_id = parent_span_id;
}

/// Set the span status. `message` is carried only for OTEL_STATUS_ERROR
/// (validators reject a message on any other status).
pub fn otel_span_set_status(span: &mut OtelSpan, status: Int, message: Str) {
  span.status = status;
  span.status_message = message;
}

/// Append one attribute (insertion order is the wire order).
pub fn otel_span_add_attribute(span: &mut OtelSpan, attribute: OtelAttribute) {
  span.attributes.push(attribute);
}

/// An empty span batch.
pub fn otel_batch_new() -> OtelSpanBatch {
  return OtelSpanBatch { spans: Vec[OtelSpan].new() };
}

/// Append one span (by value; insertion order is the wire order).
pub fn otel_batch_push(batch: &mut OtelSpanBatch, span: OtelSpan) {
  batch.spans.push(span);
}

/// A gauge point with no attributes; `time_unix_nano` is caller-provided.
/// Nothing is validated here.
pub fn otel_gauge_new(name: Str, description: Str, unit: Str, value: Float64, time_unix_nano: Int) -> OtelGaugePoint {
  return OtelGaugePoint {
    name: name;
    description: description;
    unit: unit;
    value: value;
    time_unix_nano: time_unix_nano;
    attributes: Vec[OtelAttribute].new();
  };
}

/// Append one attribute to a gauge point (insertion order is the wire order).
pub fn otel_gauge_add_attribute(point: &mut OtelGaugePoint, attribute: OtelAttribute) {
  point.attributes.push(attribute);
}

/// An empty metrics batch (valid; encodes an empty `metrics` array).
pub fn otel_metrics_batch_new() -> OtelMetricsBatch {
  return OtelMetricsBatch { points: Vec[OtelGaugePoint].new() };
}

/// Append one gauge point (by value; insertion order is the wire order).
pub fn otel_metrics_batch_push(batch: &mut OtelMetricsBatch, point: OtelGaugePoint) {
  batch.points.push(point);
}

/// A deterministic tracer: the trace id is derived from `seed` and is stable
/// for that seed; each next_span call takes the next derived 8-byte span id.
pub fn otel_tracer_new(seed: Int) -> OtelTracer {
  let tid = otel_id_from_seed(seed, 0);
  return OtelTracer { trace_id: tid, seed: seed, counter: 0 };
}

/// Derive the next span (root, no attributes, status unset) from the tracer.
/// Times are caller-provided; nothing is validated here.
pub fn otel_tracer_next_span(tracer: &mut OtelTracer, name: Str, kind: Int, start_unix_nano: Int, end_unix_nano: Int) -> OtelSpan {
  let c: Int = tracer.counter;
  let sid: Str = otel_span_id_from_seed(tracer.seed, c);
  tracer.counter = c + 1;
  return otel_span_new(tracer.trace_id, sid, name, kind, start_unix_nano, end_unix_nano);
}

// --- Hex helpers (lowercase output; both digit cases accepted on input)

// Lowercase hex digit for a nibble 0..15.
fn _hex_nibble(n: Int) -> UInt8 {
  if n < 10 { return (48 + n) as UInt8; }
  return (87 + n) as UInt8;
}

// Value of a hex digit byte (0-9, a-f, A-F); -1 otherwise.
fn _hex_digit_value(b: UInt8) -> Int {
  let code: Int = (b as Int) & 255;
  if code >= 48 && code <= 57 { return code - 48; }
  if code >= 97 && code <= 102 { return code - 87; }
  if code >= 65 && code <= 70 { return code - 55; }
  return -1;
}

/// Lowercase hex encoding of a byte vector (two digits per byte; "" for
/// empty input). Complexity: O(n).
pub fn otel_hex_encode(bytes: &Vec[UInt8]) -> Str {
  var out: Vec[UInt8] = builder.sb_new();
  var i = 0;
  while i < bytes.len() {
    let b: UInt8 = bytes[i];
    let v: Int = (b as Int) & 255;
    builder.sb_push_byte(&mut out, _hex_nibble(v >> 4));
    builder.sb_push_byte(&mut out, _hex_nibble(v & 15));
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}

/// True when `hex` is exactly `n_bytes` bytes of hex text (both cases).
pub fn otel_hex_is_valid(hex: Str, n_bytes: Int) -> Bool {
  if n_bytes < 0 { return false; }
  let n = hex.len();
  if n != n_bytes * 2 { return false; }
  var i = 0;
  while i < n {
    let b: UInt8 = hex.byte_at(i);
    if _hex_digit_value(b) < 0 { return false; }
    i = i + 1;
  }
  return true;
}

// True when every character of `hex` is '0' (used for the all-zero id rule).
fn _hex_is_zero(hex: Str) -> Bool {
  let n = hex.len();
  var i = 0;
  while i < n {
    let b: UInt8 = hex.byte_at(i);
    if ((b as Int) & 255) != 48 { return false; }
    i = i + 1;
  }
  return true;
}

/// Decode hex text into bytes (both digit cases accepted). Errors: kind
/// OTEL_ERR_ID on odd length or a non-hex character.
pub fn otel_hex_decode(hex: Str) -> Result[Vec[UInt8], OtelError] {
  let n = hex.len();
  if n % 2 != 0 {
    return _err_bytes(otel_error(OTEL_ERR_ID, "hex input has odd length"));
  }
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < n {
    let hi = _hex_digit_value(hex.byte_at(i));
    let lo = _hex_digit_value(hex.byte_at(i + 1));
    if hi < 0 || lo < 0 {
      return _err_bytes(otel_error(OTEL_ERR_ID, "hex input has a non-hex character"));
    }
    out.push(((hi << 4) | lo) as UInt8);
    i = i + 2;
  }
  return _ok_bytes(out);
}

// --- Deterministic id derivation (no randomness; declared in SPEC.md) ---
//
// Seeded derivation for tests and consumers that want reproducible traffic:
// the exact pipeline is declared in SPEC.md section 2.4 so any conforming
// implementation reproduces the same ids for the same (seed, counter).

// Logical right shift of a UInt64 by k bits (the builtin `>>` on UInt64 is
// arithmetic on v0.64.x; mask to the logical result -- xiom.hash.xxhash).
fn _u64_shr(x: UInt64, k: Int) -> UInt64 {
  if k <= 0 { return x; }
  if k >= 64 { var z: UInt64 = 0; return z; }
  let mask: UInt64 = ((1 as UInt64) << (64 - k)) - 1;
  return (x >> k) & mask;
}

// SplitMix64-style bit finalizer (two xor-shift-multiplies and a final
// xor-shift); public-domain mixing shape, declared in SPEC.md section 2.4.
fn _mix64(x: UInt64) -> UInt64 {
  var z: UInt64 = x;
  z = (z ^ _u64_shr(z, 30)) * (0xBF58476D1CE4E5B9 as UInt64);
  z = (z ^ _u64_shr(z, 27)) * (0x94D049BB133111EB as UInt64);
  return z ^ _u64_shr(z, 31);
}

// Append `n` derived bytes for (tag, seed, counter); SPEC.md section 2.4
// declares the byte pipeline. Wrapping 64-bit arithmetic throughout.
fn _seed_bytes(out: &mut Vec[UInt8], tag: UInt64, seed: Int, counter: Int, n: Int) {
  let s0: UInt64 = _mix64((seed as UInt64) ^ tag);
  let s1: UInt64 = _mix64((counter as UInt64) ^ (tag << 32));
  var state: UInt64 = s0 ^ _mix64(s1 + tag);
  var j = 0;
  while j < n {
    state = _mix64(state + (j as UInt64) + (0x9E3779B97F4A7C15 as UInt64));
    let v: Int = (_u64_shr(state, 56) as Int) & 255;
    out.push(v as UInt8);
    j = j + 1;
  }
}

/// A deterministic 16-byte (32 hex character) id for (seed, counter).
pub fn otel_id_from_seed(seed: Int, counter: Int) -> Str {
  var bytes: Vec[UInt8] = Vec[UInt8].new();
  _seed_bytes(&mut bytes, 1 as UInt64, seed, counter, 16);
  return otel_hex_encode(&bytes);
}

/// A deterministic 8-byte (16 hex character) span id for (seed, counter);
/// independent of the trace-id derivation (a different mixing tag).
pub fn otel_span_id_from_seed(seed: Int, counter: Int) -> Str {
  var bytes: Vec[UInt8] = Vec[UInt8].new();
  _seed_bytes(&mut bytes, 2 as UInt64, seed, counter, 8);
  return otel_hex_encode(&bytes);
}

// --- Validators (typed; the encoder enforces exactly these rules)

// A double value that JSON cannot represent (NaN or +/-Inf).
fn _double_not_finite(d: Float64) -> Bool {
  if d != d { return true; }
  if d > 1.7976931348623157e308 { return true; }
  if d < -1.7976931348623157e308 { return true; }
  return false;
}

/// Validate an attribute list: at most OTEL_MAX_ATTRIBUTES entries, non-empty
/// unique keys (byte comparison), value kind 1..4, finite doubles.
pub fn otel_validate_attributes(attributes: &Vec[OtelAttribute]) -> Result[Unit, OtelError] {
  if attributes.len() > OTEL_MAX_ATTRIBUTES {
    return _err_unit(otel_error(OTEL_ERR_LIMIT, "attribute count exceeds OTEL_MAX_ATTRIBUTES (128)"));
  }
  var i = 0;
  while i < attributes.len() {
    let a: OtelAttribute = attributes[i];
    if a.key.len() == 0 {
      return _err_unit(otel_error(OTEL_ERR_ATTRIBUTE, "attribute key is empty"));
    }
    var j = 0;
    while j < i {
      let prev: OtelAttribute = attributes[j];
      if compare.str_compare(a.key, prev.key) == 0 {
        return _err_unit(otel_error(OTEL_ERR_ATTRIBUTE, "duplicate attribute key"));
      }
      j = j + 1;
    }
    let v: OtelValue = a.value;
    if v.kind < OTEL_VALUE_STR || v.kind > OTEL_VALUE_DOUBLE {
      return _err_unit(otel_error(OTEL_ERR_VALUE, "attribute value kind is outside 1..4"));
    }
    if v.kind == OTEL_VALUE_DOUBLE {
      if _double_not_finite(v.double_value) {
        return _err_unit(otel_error(OTEL_ERR_VALUE, "double attribute value is not finite"));
      }
    }
    i = i + 1;
  }
  return _ok_unit();
}

/// Validate one span: ids are exact-length hex text and not all zero, name
/// is non-empty and within OTEL_MAX_NAME_LEN bytes, kind is 1..5, 0 <= start
/// <= end, status is 0..2 (a message only with OTEL_STATUS_ERROR), and the
/// attribute list passes otel_validate_attributes.
pub fn otel_validate_span(span: &OtelSpan) -> Result[Unit, OtelError] {
  if !otel_hex_is_valid(span.trace_id, 16) {
    return _err_unit(otel_error(OTEL_ERR_ID, "trace_id must be 32 hex characters (16 bytes)"));
  }
  if _hex_is_zero(span.trace_id) {
    return _err_unit(otel_error(OTEL_ERR_ID, "trace_id must not be all zero"));
  }
  if !otel_hex_is_valid(span.span_id, 8) {
    return _err_unit(otel_error(OTEL_ERR_ID, "span_id must be 16 hex characters (8 bytes)"));
  }
  if _hex_is_zero(span.span_id) {
    return _err_unit(otel_error(OTEL_ERR_ID, "span_id must not be all zero"));
  }
  if span.parent_span_id.len() != 0 {
    if !otel_hex_is_valid(span.parent_span_id, 8) {
      return _err_unit(otel_error(OTEL_ERR_ID, "parent_span_id must be empty or 16 hex characters (8 bytes)"));
    }
    if _hex_is_zero(span.parent_span_id) {
      return _err_unit(otel_error(OTEL_ERR_ID, "parent_span_id must not be all zero"));
    }
  }
  if span.name.len() == 0 {
    return _err_unit(otel_error(OTEL_ERR_NAME, "span name is empty"));
  }
  if span.name.len() > OTEL_MAX_NAME_LEN {
    return _err_unit(otel_error(OTEL_ERR_LIMIT, "span name exceeds OTEL_MAX_NAME_LEN (1024 bytes)"));
  }
  if span.kind < OTEL_SPAN_KIND_INTERNAL || span.kind > OTEL_SPAN_KIND_CONSUMER {
    return _err_unit(otel_error(OTEL_ERR_KIND, "span kind is outside 1..5"));
  }
  if span.start_unix_nano < 0 {
    return _err_unit(otel_error(OTEL_ERR_TIME, "start_unix_nano is negative"));
  }
  if span.end_unix_nano < span.start_unix_nano {
    return _err_unit(otel_error(OTEL_ERR_TIME, "end_unix_nano is before start_unix_nano"));
  }
  if span.status < OTEL_STATUS_UNSET || span.status > OTEL_STATUS_ERROR {
    return _err_unit(otel_error(OTEL_ERR_STATUS, "status is outside 0..2"));
  }
  if span.status != OTEL_STATUS_ERROR && span.status_message.len() != 0 {
    return _err_unit(otel_error(OTEL_ERR_STATUS, "status_message requires status Error"));
  }
  let ar: Result[Unit, OtelError] = otel_validate_attributes(&span.attributes);
  if !ar.is_ok {
    let e: OtelError = ar.error;
    return _err_unit(e);
  }
  return _ok_unit();
}

/// Validate a batch: non-empty, at most OTEL_MAX_BATCH_SPANS spans, every
/// span passing otel_validate_span (in order; the first failure wins).
pub fn otel_validate_batch(batch: &OtelSpanBatch) -> Result[Unit, OtelError] {
  if batch.spans.len() == 0 {
    return _err_unit(otel_error(OTEL_ERR_EMPTY, "span batch is empty"));
  }
  if batch.spans.len() > OTEL_MAX_BATCH_SPANS {
    return _err_unit(otel_error(OTEL_ERR_LIMIT, "span count exceeds OTEL_MAX_BATCH_SPANS (1024)"));
  }
  var i = 0;
  while i < batch.spans.len() {
    let s: OtelSpan = batch.spans[i];
    let sr: Result[Unit, OtelError] = otel_validate_span(&s);
    if !sr.is_ok {
      let e: OtelError = sr.error;
      return _err_unit(e);
    }
    i = i + 1;
  }
  return _ok_unit();
}

/// Validate one gauge point: name is non-empty, time_unix_nano is positive,
/// the value is finite, and the attribute list passes
/// otel_validate_attributes.
pub fn otel_validate_gauge(point: &OtelGaugePoint) -> Result[Unit, OtelError] {
  if point.name.len() == 0 {
    return _err_unit(otel_error(OTEL_ERR_NAME, "gauge name is empty"));
  }
  if point.time_unix_nano <= 0 {
    return _err_unit(otel_error(OTEL_ERR_TIME, "time_unix_nano must be positive"));
  }
  if _double_not_finite(point.value) {
    return _err_unit(otel_error(OTEL_ERR_VALUE, "gauge value is not finite"));
  }
  let ar: Result[Unit, OtelError] = otel_validate_attributes(&point.attributes);
  if !ar.is_ok {
    let e: OtelError = ar.error;
    return _err_unit(e);
  }
  return _ok_unit();
}

/// Validate a metrics batch: every point passing otel_validate_gauge in order
/// (the first failure wins). An empty batch is valid.
pub fn otel_validate_metrics_batch(batch: &OtelMetricsBatch) -> Result[Unit, OtelError] {
  var i = 0;
  while i < batch.points.len() {
    let p: OtelGaugePoint = batch.points[i];
    let pr: Result[Unit, OtelError] = otel_validate_gauge(&p);
    if !pr.is_ok {
      let e: OtelError = pr.error;
      return _err_unit(e);
    }
    i = i + 1;
  }
  return _ok_unit();
}
