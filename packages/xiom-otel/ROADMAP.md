# ROADMAP: xiom.otel

Current state: v0.2.0 (incubating), pure-XIOM OpenTelemetry trace model +
deterministic OTLP/JSON encoder + sink seam, plus a minimal gauge-metrics
model and OTLP/JSON metrics encoder. 37/37 checks recorded x2 green on XIOM
v0.64.5 (the 30 trace checks are unchanged and still green). See `SPEC.md`
(model, mappings, canonical rules, error taxonomy and non-goals) and
`PROVENANCE.md` (independent declaration).

## Delivered in 0.2.0 (ST6 gauges)

The OTEL gauges requested by orbitdb, served by xiom.otel 0.2.0:

- `OtelGaugePoint` (`name`, `description`, `unit`, `value`, caller-provided
  `time_unix_nano`, attributes) and `OtelMetricsBatch`, with constructors,
  append helpers and typed validators (`otel_validate_gauge`,
  `otel_validate_metrics_batch`; empty batches valid).
- `otel_encode_metrics_json`: deterministic OTLP/JSON
  `ExportMetricsServiceRequest` (`resourceMetrics[].scopeMetrics[].metrics[]`),
  one gauge metric with one `dataPoints` entry per point, `asDouble`,
  `timeUnixNano` decimal string, insertion-order attributes; exact-byte
  golden (305 bytes).
- ST6 use case: replication lag in LSN bytes
  (`postgres.replication_lag_lsn`, unit `By`), live sessions
  (`postgres.sessions.live`, unit `{session}`) and per-shard sizes
  (`shard.size.bytes`, unit `By`), all pushed into one ordered batch and
  encoded without a clock or randomness.
- The traces surface (types, functions, bytes, goldens) is unchanged from
  0.1.0.

Nothing else below is implemented; each item is a candidate for a future
version and requires its own conformance slice before shipping.

## Near term (0.1.x)

1. **Attribute arrays and kvlists** (`arrayValue`, `kvlistValue`):
   recursive AnyValue values; needs a recursive value shape and exact-byte
   goldens for nesting. (Byte values `bytesValue` wait for a byte-oriented
   value model.)
2. **Span events and links**: `events[]` (timeUnixNano, name, attributes)
   and `links[]` (traceId/spanId/traceState/attributes) with their caps
   and goldens.
3. **`trace_state`, `flags`, dropped counts, `schema_url`**: model fields
   plus mapping rows and goldens; `flags` as the documented bit field.
4. **Convenience tracing helpers**: span-name attribute set shorthand
   (e.g. semconv key builders) on the existing constructors; no new
   encoding power.

## Medium term (0.2+)

5. **OTLP/protobuf binary encoder**: an `xiom.otel.protobuf` module
   emitting `application/x-protobuf` bytes; wire-format goldens (the
   protobuf wire encoding is length-delimited varint framing, a different
   module, not a fork of the JSON encoder).
6. **HTTP exporter over a caller transport**: an `xiom.otel.http` module
   that builds the `POST /v1/traces` and `POST /v1/metrics` requests
   (default port 4318, `Content-Type: application/json`) and hands them to
   a caller-supplied or stdlib HTTP client; gzip and retry/backoff policy
   as explicit options. Kept transport-agnostic: the encoders never learn
   about sockets.
7. **Batch processor / export queue**: an opt-in accumulator (size/time
   flushed by caller-supplied time, no library-internal clock), dropping
   counters surfaced honestly.
8. **Sampling hook**: a caller-supplied decision function on the tracer
   (record/drop), deterministic under the same seed.

## Long term (exploratory)

9. **Remaining metrics and logs signals**: counters/sums, histograms,
   exponential histograms and summaries (with aggregation temporality,
   exemplars and start times), then an OTLP/JSON encoder for
   `ExportLogsServiceRequest`; gauges shipped in 0.2.0, the rest are new
   signals under the same canonical discipline.
10. **Live parity fixtures**: run captured request bytes against a pinned
    OpenTelemetry Collector (or a pinned `opentelemetry-proto`-generated
    oracle) in CI; record the capture procedure and pin in
    `PROVENANCE.md` at that time (a re-carve per `docs/UPSTREAM-FIRST.md`).
11. **Resource detectors** (env/process attributes) as a separate module
    once the stdlib exposes the needed OS introspection without FFI in
    package code.
