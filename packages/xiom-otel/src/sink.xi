// XIOM -- xiom.otel.sink: transport seam and export counters (pure XIOM)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// The sink seam for phase 1: a collector sink that encodes and retains the
// OTLP/JSON payloads (tests and embedding), and a function-shaped send hook
// so a caller-supplied transport (HTTP at 0.2+) can consume the exact
// payload bytes without the core knowing anything about it. Honest counters
// (spans, bytes, errors) live on the sink; there is no network code, no
// clock and no global state here.
//
// Counters are appended only after a successful encode (collector) or a
// successful encode + send (hook); every failure increments `errors` by one
// and leaves `spans_exported` / `bytes_exported` untouched.

module xiom.otel.sink

use xiom.otel;
use xiom.otel.otlp;

// ---------------------------------------------------------------------------
// Leaf helpers (Ok/Err construction confined here; v0.64.x discipline)
// ---------------------------------------------------------------------------

fn _ok_stats(v: OtelExportStats) -> Result[OtelExportStats, OtelError] {
  return Ok(v);
}

fn _err_stats(e: OtelError) -> Result[OtelExportStats, OtelError] {
  return Err(e);
}

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/// The counters for one successful export call: the number of spans and the
/// exact encoded payload byte length.
pub type OtelExportStats = {
  spans: Int;
  bytes: Int;
}

/// The collector sink: encoded payloads in export order plus honest
/// cumulative counters. `errors` counts every failed export (encode or send
/// failure); successful calls add to `spans_exported` / `bytes_exported`.
pub type OtelSink = {
  payloads: Vec[Str];
  spans_exported: Int;
  bytes_exported: Int;
  errors: Int;
}

// ---------------------------------------------------------------------------
// Surface
// ---------------------------------------------------------------------------

/// A new empty sink (no payloads, zero counters).
pub fn otel_sink_new() -> OtelSink {
  return OtelSink {
    payloads: Vec[Str].new();
    spans_exported: 0;
    bytes_exported: 0;
    errors: 0;
  };
}

/// Encode the batch (with resource and scope) and collect the payload in
/// `sink.payloads`. On success `spans_exported` and `bytes_exported` grow by
/// the call's counts and the stats are returned; on any encode failure
/// `errors` grows by one, the payload vector is untouched and the typed
/// encoder error is returned unchanged.
pub fn otel_export(sink: &mut OtelSink, spans: &OtelSpanBatch, resource: &OtelResource, scope: &OtelScope) -> Result[OtelExportStats, OtelError] {
  let er = otel_encode_json(spans, resource, scope);
  if !er.is_ok {
    let e: OtelError = er.error;
    sink.errors = sink.errors + 1;
    return _err_stats(e);
  }
  let payload: Str = er.value;
  let n_spans: Int = spans.spans.len();
  let n_bytes: Int = payload.len();
  sink.payloads.push(payload);
  sink.spans_exported = sink.spans_exported + n_spans;
  sink.bytes_exported = sink.bytes_exported + n_bytes;
  let stats: OtelExportStats = OtelExportStats { spans: n_spans; bytes: n_bytes };
  return _ok_stats(stats);
}

/// Encode the batch and hand the exact payload bytes to the caller-supplied
/// send hook (the transport seam; no transport ships in 0.1.0). The payload
/// is NOT retained in `sink.payloads` (the hook consumes it). On success the
/// counters grow and the stats are returned; when the hook fails, `errors`
/// grows by one and the failure is `kind OTEL_ERR_SINK` with the hook's
/// message appended; on an encode failure the encoder error is returned
/// unchanged (and `errors` grows by one).
pub fn otel_export_send(sink: &mut OtelSink, spans: &OtelSpanBatch, resource: &OtelResource, scope: &OtelScope, send: fn(Str) -> Result[Unit, Str]) -> Result[OtelExportStats, OtelError] {
  let er = otel_encode_json(spans, resource, scope);
  if !er.is_ok {
    let e: OtelError = er.error;
    sink.errors = sink.errors + 1;
    return _err_stats(e);
  }
  let payload: Str = er.value;
  let n_spans: Int = spans.spans.len();
  let n_bytes: Int = payload.len();
  let sr = send(payload);
  if !sr.is_ok {
    let msg: Str = sr.error;
    sink.errors = sink.errors + 1;
    return _err_stats(otel_error(OTEL_ERR_SINK, "send hook failed: " + msg));
  }
  sink.spans_exported = sink.spans_exported + n_spans;
  sink.bytes_exported = sink.bytes_exported + n_bytes;
  let stats: OtelExportStats = OtelExportStats { spans: n_spans; bytes: n_bytes };
  return _ok_stats(stats);
}
