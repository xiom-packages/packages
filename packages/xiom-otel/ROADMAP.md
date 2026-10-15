# ROADMAP: xiom.otel

Current state: v0.1.0 (incubating), pure-XIOM OpenTelemetry trace model +
deterministic OTLP/JSON encoder + sink seam, 30/30 checks recorded x2 green
on XIOM v0.64.5. See `SPEC.md` (model, mapping, canonical rules, error
taxonomy and non-goals) and `PROVENANCE.md` (independent declaration).

Nothing below is implemented; each item is a candidate for a future
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
   that builds the `POST /v1/traces` request (default port 4318,
   `Content-Type: application/json`) and hands it to a caller-supplied or
   stdlib HTTP client; gzip and retry/backoff policy as explicit options.
   Kept transport-agnostic: the encoder never learns about sockets.
7. **Batch processor / export queue**: an opt-in accumulator (size/time
   flushed by caller-supplied time, no library-internal clock), dropping
   counters surfaced honestly.
8. **Sampling hook**: a caller-supplied decision function on the tracer
   (record/drop), deterministic under the same seed.

## Long term (exploratory)

9. **Metrics and logs signals**: OTLP/JSON encoders for
   `ExportMetricsServiceRequest` and `ExportLogsServiceRequest`; new
   signals, same canonical discipline.
10. **Live parity fixtures**: run captured request bytes against a pinned
    OpenTelemetry Collector (or a pinned `opentelemetry-proto`-generated
    oracle) in CI; record the capture procedure and pin in
    `PROVENANCE.md` at that time (a re-carve per `docs/UPSTREAM-FIRST.md`).
11. **Resource detectors** (env/process attributes) as a separate module
    once the stdlib exposes the needed OS introspection without FFI in
    package code.
