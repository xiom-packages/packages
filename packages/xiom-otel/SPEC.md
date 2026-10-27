# xiom.otel -- Specification

Version: 0.2.0 (incubating).
Pure XIOM, no FFI, no bridge C, no upstream OpenTelemetry code: the model,
the OTLP/JSON encoders and the sink seam are implemented from the
OpenTelemetry Protocol (OTLP) specification and its JSON Protobuf Encoding
mapping (see `PROVENANCE.md`).
Dependencies: `xiom.std >=0.60.0 <1.0.0` (the library modules use
`xiom.string.compare`, `xiom.string.builder` and `xiom.convert`; the tests
additionally use `xiom.test`, `xiom.io`, `xiom.string` and
`xiom.math.constants`).

Scope: the trace model + the OTLP/JSON trace encoder + a sink/transport
seam, plus a minimal gauge-metrics model and OTLP/JSON metrics encoder added
in 0.2.0. The traces surface is unchanged from 0.1.0: same types, functions,
error kinds, canonical bytes and goldens. HTTP transport stays
caller-supplied (the send hook); nothing in the package opens a socket.

## 1. Scope and module map

| Module | File | Contents |
|---|---|---|
| `xiom.otel` | `src/otel.xi` | model, constants, caps, hex/id helpers, deterministic tracer, typed validators (spans and gauge metrics) |
| `xiom.otel.otlp` | `src/otlp.xi` | `otel_encode_json` (traces) and `otel_encode_metrics_json` (gauges): deterministic OTLP/JSON encoders |
| `xiom.otel.sink` | `src/sink.xi` | collector sink, send hook seam, export counters |

## 2. Model

### 2.1 Types

| Type | Shape | Meaning |
|---|---|---|
| `OtelError` | `{ kind: Int; message: Str }` | typed failure; `kind` is an `OTEL_ERR_*` code |
| `OtelValue` | `{ kind: Int; str_value: Str; int_value: Int; bool_value: Bool; double_value: Float64 }` | kind-tagged attribute value (only the slot named by `kind` is meaningful) |
| `OtelAttribute` | `{ key: Str; value: OtelValue }` | one attribute pair |
| `OtelResource` | `{ attributes: Vec[OtelAttribute] }` | the exporting resource |
| `OtelScope` | `{ name: Str; version: Str; attributes: Vec[OtelAttribute] }` | instrumentation scope |
| `OtelSpan` | `{ trace_id: Str; span_id: Str; parent_span_id: Str; name: Str; kind: Int; start_unix_nano: Int; end_unix_nano: Int; attributes: Vec[OtelAttribute]; status: Int; status_message: Str }` | one span; ids are hex text (see 2.3), times are caller-provided Unix-epoch nanoseconds |
| `OtelSpanBatch` | `{ spans: Vec[OtelSpan] }` | ordered batch |
| `OtelTracer` | `{ trace_id: Str; seed: Int; counter: Int }` | deterministic span factory |
| `OtelGaugePoint` | `{ name: Str; description: Str; unit: Str; value: Float64; time_unix_nano: Int; attributes: Vec[OtelAttribute] }` | one gauge sample; times are caller-provided Unix-epoch nanoseconds |
| `OtelMetricsBatch` | `{ points: Vec[OtelGaugePoint] }` | ordered gauge batch (one OTLP metric entry per point; may be empty) |

`OtelValue` is a flat kind-tagged struct, deliberately not a payload enum:
XIOM v0.64.5 mislowers `Float64` payloads inside enums (observed while
building this package: enum construction with a float payload read back
denormal garbage or silently failed to match; the flat struct round-trips
exactly). The model guidance for this toolchain is "structs at module
boundaries"; the typed surface is unchanged.

### 2.2 Constants

Span kinds (`OtelSpan.kind`; OTLP `Span.SpanKind` integer values;
`SPAN_KIND_UNSPECIFIED` = 0 is not modeled):

| Constant | Value |
|---|---|
| `OTEL_SPAN_KIND_INTERNAL` | 1 |
| `OTEL_SPAN_KIND_SERVER` | 2 |
| `OTEL_SPAN_KIND_CLIENT` | 3 |
| `OTEL_SPAN_KIND_PRODUCER` | 4 |
| `OTEL_SPAN_KIND_CONSUMER` | 5 |

Status codes (`OtelSpan.status`; OTLP `Status.StatusCode`):

| Constant | Value |
|---|---|
| `OTEL_STATUS_UNSET` | 0 |
| `OTEL_STATUS_OK` | 1 |
| `OTEL_STATUS_ERROR` | 2 |

Attribute value kinds (`OtelValue.kind`):

| Constant | Value |
|---|---|
| `OTEL_VALUE_STR` | 1 |
| `OTEL_VALUE_INT` | 2 |
| `OTEL_VALUE_BOOL` | 3 |
| `OTEL_VALUE_DOUBLE` | 4 |

### 2.3 Ids

`trace_id` is 32 hex characters (16 bytes), `span_id` and
`parent_span_id` are 16 hex characters (8 bytes); `parent_span_id` is `""`
for a root span. OTLP/JSON ids are case-insensitive hex, so both digit
cases are accepted and emitted verbatim; all helpers (`otel_hex_encode`,
`otel_id_from_seed`, `otel_span_id_from_seed`) produce lowercase. An
all-zero id is rejected (the OTLP proto declares it invalid).

### 2.4 Deterministic id derivation (no randomness)

`otel_id_from_seed(seed, counter)` (16 bytes -> 32 hex) and
`otel_span_id_from_seed(seed, counter)` (8 bytes -> 16 hex) derive ids from
their inputs only. The exact pipeline (wrapping 64-bit arithmetic; `>>` is
the logical shift; `seed`/`counter` are mixed as their 64-bit
two's-complement bit patterns):

```
mix64(x):
  z = x
  z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9
  z = (z ^ (z >> 27)) * 0x94D049BB133111EB
  return z ^ (z >> 31)                      // all multiplies mod 2^64

seed_bytes(tag, seed, counter, n):
  s0    = mix64(u64(seed) ^ tag)
  s1    = mix64(u64(counter) ^ ((tag << 32) mod 2^64))
  state = s0 ^ mix64(s1 + tag)
  for j in 0 .. n-1:
    state = mix64(state + j + 0x9E3779B97F4A7C15)
    byte_j = (state >> 56) & 0xFF

otel_id_from_seed(seed, counter)      = hex(seed_bytes(1, seed, counter, 16))
otel_span_id_from_seed(seed, counter) = hex(seed_bytes(2, seed, counter, 8))
```

The mixing shape is the public-domain SplitMix64-style xor-shift-multiply
finalizer; the byte pipeline (`tag`, `j + GOLDEN` stepping, high-byte
extraction) is this package's own declared derivation. The conformance
KATs are reproducible by any implementation of the two blocks above (an
independent Python transcription of this section reproduced all pinned
values during the build).

`otel_tracer_new(seed)` takes `trace_id = otel_id_from_seed(seed, 0)` and
`counter = 0`; each `otel_tracer_next_span` uses
`otel_span_id_from_seed(seed, counter)` and increments `counter`. Same
seed, same sequence -- no clock, no randomness, no globals.

### 2.5 Documented caps

| Constant | Value | Enforced on |
|---|---|---|
| `OTEL_MAX_ATTRIBUTES` | 128 | per attribute list (span, gauge point, resource, scope) |
| `OTEL_MAX_BATCH_SPANS` | 1024 | spans per batch |
| `OTEL_MAX_NAME_LEN` | 1024 | span name, in bytes |

### 2.6 Typed validators (authored in the model, enforced by the encoder)

`otel_validate_attributes`, `otel_validate_span` and `otel_validate_batch`
return `Result[Unit, OtelError]`. Rules, in evaluation order:

1. Batch: non-empty (`OTEL_ERR_EMPTY`), <= 1024 spans (`OTEL_ERR_LIMIT`),
   then each span in insertion order (first failure wins).
2. Span: `trace_id` / `span_id` / `parent_span_id` shape and non-zero
   (`OTEL_ERR_ID`) -> name non-empty (`OTEL_ERR_NAME`) -> name <= 1024
   bytes (`OTEL_ERR_LIMIT`) -> kind 1..5 (`OTEL_ERR_KIND`) ->
   `0 <= start` and `end >= start` (`OTEL_ERR_TIME`) -> status 0..2 and a
   message only with `OTEL_STATUS_ERROR` (`OTEL_ERR_STATUS`) -> attributes.
3. Attributes: <= 128 (`OTEL_ERR_LIMIT`), non-empty unique keys compared
   byte-wise (`OTEL_ERR_ATTRIBUTE`), value kind 1..4 and finite doubles
   (`OTEL_ERR_VALUE`).
4. `otel_encode_json` additionally validates the resource attributes, then
   the scope attributes, with the same attribute rules.

Constructors (`otel_span_new`, `otel_attr_*`, setters) never validate and
never fail; validation is explicit and always available before encoding.

### 2.7 Gauge metrics model and validators (0.2.0)

The metrics surface is deliberately minimal and deterministic: one gauge
point per OTLP metric entry, one numeric value per point (`asDouble`), no
aggregation temporality, no start time, no exemplars and no counters or
histograms (section 10).

- `otel_gauge_new(name, description, unit, value, time_unix_nano)` builds a
  point with no attributes; `otel_gauge_add_attribute` appends one attribute
  (insertion order is the wire order).
- `otel_metrics_batch_new()` builds an empty batch;
  `otel_metrics_batch_push` appends one point.
- `otel_validate_gauge(point)` rules, in evaluation order: name non-empty
  (`OTEL_ERR_NAME`) -> `time_unix_nano > 0` (`OTEL_ERR_TIME`) -> `value` is
  finite (`OTEL_ERR_VALUE`) -> attributes pass `otel_validate_attributes`
  (same rules and error kinds as span/resource/scope attributes).
- `otel_validate_metrics_batch(batch)` validates each point in insertion
  order (first failure wins). An empty batch is valid.

As with spans, constructors never validate; validation is explicit and is
also enforced by `otel_encode_metrics_json`.

## 3. Error taxonomy

`OtelError = { kind, message }`, `kind` is one of:

| Kind | Constant | Raised for |
|---|---|---|
| 1 | `OTEL_ERR_ID` | id/hex input shape: wrong length, non-hex character, all-zero id (also `otel_hex_decode` input errors) |
| 2 | `OTEL_ERR_NAME` | empty span name, empty gauge (metric) name |
| 3 | `OTEL_ERR_TIME` | negative `start_unix_nano`, `end < start`, non-positive gauge `time_unix_nano` |
| 4 | `OTEL_ERR_ATTRIBUTE` | empty attribute key, duplicate key |
| 5 | `OTEL_ERR_KIND` | span kind outside 1..5 |
| 6 | `OTEL_ERR_STATUS` | status outside 0..2, status message on a non-error status |
| 7 | `OTEL_ERR_VALUE` | value kind outside 1..4, non-finite double attribute, non-finite gauge value |
| 8 | `OTEL_ERR_LIMIT` | a documented cap exceeded (attributes 128, spans 1024, name 1024 bytes) |
| 9 | `OTEL_ERR_EMPTY` | empty span batch (OTLP: senders should not create empty envelopes) |
| 10 | `OTEL_ERR_SINK` | the caller-supplied send hook failed (message carries the hook's text) |

`OTEL_ERR_NONE` (0) is a sentinel and is never produced as a failure. Error
messages are short and name the offending field; they are diagnostics, not
a stable API -- branch on `kind`.

## 4. OTLP/JSON mapping

Reference: the OTLP specification's "JSON Protobuf Encoding" section
(proto3 JSON mapping with declared deviations) -- see `PROVENANCE.md` for
the pinned references. The structure is the OTLP
`ExportTraceServiceRequest`:

```
{"resourceSpans":[{"resource": <Resource>, "scopeSpans":[
  {"scope": <InstrumentationScope>, "spans":[<Span>, ...]}]}]}
```

### 4.1 Field mapping

| OTLP field (proto) | Proto type | JSON key | JSON encoding |
|---|---|---|---|
| `Resource.attributes` | repeated KeyValue | `attributes` | array; omitted when empty |
| `InstrumentationScope.name` | string | `name` | string; omitted when empty |
| `InstrumentationScope.version` | string | `version` | string; omitted when empty |
| `InstrumentationScope.attributes` | repeated KeyValue | `attributes` | array; omitted when empty |
| `Span.trace_id` | bytes(16) | `traceId` | hex string, emitted verbatim (spec deviation from base64) |
| `Span.span_id` | bytes(8) | `spanId` | hex string |
| `Span.parent_span_id` | bytes(8) | `parentSpanId` | hex string; omitted for root spans |
| `Span.name` | string | `name` | string (validated non-empty) |
| `Span.kind` | enum | `kind` | JSON integer 1..5 (OTLP/JSON forbids enum name strings) |
| `Span.start_time_unix_nano` | fixed64 | `startTimeUnixNano` | decimal STRING |
| `Span.end_time_unix_nano` | fixed64 | `endTimeUnixNano` | decimal STRING |
| `Span.attributes` | repeated KeyValue | `attributes` | array; omitted when empty |
| `Span.status` | Status | `status` | object; omitted when `UNSET` |
| `Status.code` | enum | `code` | JSON integer 0..2 |
| `Status.message` | string | `message` | string; omitted when empty |
| `KeyValue.key` / `AnyValue.*` | string/bool/int64/double | `key` / `stringValue` / `boolValue` / `intValue` / `doubleValue` | see 4.2 |

Keys are lowerCamelCase exactly as above (the OTLP/JSON requirement).
`Span.trace_state`, `flags`, events, links, dropped counts, `schema_url`
and resource `entity_refs` are not modeled (see section 8).

### 4.2 Attribute values (AnyValue)

| Model kind | JSON | Notes |
|---|---|---|
| `OTEL_VALUE_STR` | `{"stringValue": <escaped string>}` | |
| `OTEL_VALUE_INT` | `{"intValue": "<decimal>"}` | proto3 JSON maps int64 to a decimal string; full Int range |
| `OTEL_VALUE_BOOL` | `{"boolValue": true|false}` | |
| `OTEL_VALUE_DOUBLE` | `{"doubleValue": <number>}` | finite only; rendered by `xiom.convert.float_to_string` (15 significant digits) |

Arrays (`arrayValue`), kvlists and byte values are not modeled in 0.2.0.

### 4.3 Gauge metrics mapping (0.2.0)

The metrics structure is the OTLP `ExportMetricsServiceRequest`:

```
{"resourceMetrics":[{"resource": <Resource>, "scopeMetrics":[
  {"scope": <InstrumentationScope>, "metrics":[<Metric>, ...]}]}]}
```

`<Resource>` and `<InstrumentationScope>` reuse exactly the trace shapes in
section 4.1. One `Metric` is emitted per `OtelGaugePoint`, in batch order.

| OTLP field (proto) | Proto type | JSON key | JSON encoding |
|---|---|---|---|
| `Metric.name` | string | `name` | string (validated non-empty) |
| `Metric.description` | string | `description` | string; always emitted (`""` allowed) |
| `Metric.unit` | string | `unit` | string; always emitted (`""` allowed) |
| `Metric.gauge` | Gauge | `gauge` | `{"dataPoints":[<NumberDataPoint>]}` |
| `NumberDataPoint.as_double` | double | `asDouble` | bare JSON number (finite, validated; same rendering as `doubleValue`) |
| `NumberDataPoint.time_unix_nano` | fixed64 | `timeUnixNano` | decimal STRING (must be positive) |
| `NumberDataPoint.attributes` | repeated KeyValue | `attributes` | array; always emitted (possibly `[]`), insertion order |

The data point's `attributes` array uses the same KeyValue encoding as
traces (section 4.2). `start_time_unix_nano`, `flags`, `exemplars`,
`aggregation_temporality`, `is_monotonic` and resource `schema_url` are not
modeled.

## 5. Encoder canonical rules (`otel_encode_json`, traces)

`otel_encode_json(spans_batch, resource, scope) -> Result[Str, OtelError]`.
The payload bytes are deterministic: same inputs -> same bytes. Golden
payload sizes for the conformance fixtures: 215, 555, 235, 368, 373, 310,
311, 435, 215, 298 bytes.

1. **Frame**: exactly
   `{"resourceSpans":[{"resource":` R `,"scopeSpans":[{"scope":` S
   `,"spans":[` spans `]}]}]}` with spans comma-separated in batch order.
   `resource` and `scope` objects are always emitted (possibly `{}`).
2. **No insignificant whitespace**: no spaces, newlines, tabs or carriage
   returns anywhere in the payload (strings escape their controls).
3. **Key order** (proto field-number order, fixed):
   - Resource: `attributes`.
   - Scope: `name`, `version`, `attributes`.
   - Span: `traceId`, `spanId`, [`parentSpanId`], `name`, `kind`,
     `startTimeUnixNano`, `endTimeUnixNano`, [`attributes`], [`status`].
   - Status: `code`, [`message`].
   - KeyValue: `key`, `value`.
4. **Omission rules**: optional members are absent exactly when default --
   `parentSpanId` when `""`; `attributes` when the list is empty (span,
   resource and scope); scope `name`/`version` when empty; `status` when
   `UNSET`; `status.message` when `""`.
5. **Attribute order** = insertion order (the `Vec` order). Duplicate keys
   are rejected, never reordered or deduplicated.
6. **String escaping**: `"` -> `\"`, `\` -> `\\`, 0x08 -> `\b`, 0x09 ->
   `\t`, 0x0A -> `\n`, 0x0C -> `\f`, 0x0D -> `\r`; every other byte below
   0x20 -> `\u00xx` with lowercase hex digits; `/` is NOT escaped; all
   other bytes pass through verbatim (raw UTF-8). The encoder does not
   re-validate UTF-8 (the OTLP "encoders SHOULD emit valid UTF-8" rule is
   the caller's responsibility, documented in the non-goals).
7. **Numbers**: timestamps and `intValue` are decimal strings (no sign for
   non-negative values, no leading zeros, full Int range); `kind` and
   `status.code` are bare JSON integers; `doubleValue` is a bare JSON
   number (finite, validated).
8. **Ids**: emitted verbatim as stored (case-insensitive per OTLP); helpers
   produce lowercase.
9. **Validation first**: the payload is produced only for a fully valid
   batch/resource/scope; any breach returns the validator's typed error
   unchanged (section 2.6 precedence).

### 5.1 Gauge metrics encoder (`otel_encode_metrics_json`)

`otel_encode_metrics_json(batch, resource, scope) -> Result[Str, OtelError]`.
The trace rules above are reused (no whitespace, fixed key order, exact
separators, escaping, decimal strings, insertion order, validation first).
Metrics-specific canonical rules:

1. **Frame**: exactly
   `{"resourceMetrics":[{"resource":` R `,"scopeMetrics":[{"scope":` S
   `,"metrics":[` metrics `]}]}]}` with metrics comma-separated in batch
   order. `resource` and `scope` are always emitted (possibly `{}`).
2. **Key order** (proto field-number order, fixed):
   - Metric: `name`, `description`, `unit`, `gauge`.
   - Gauge: `dataPoints`.
   - NumberDataPoint: `asDouble`, `timeUnixNano`, `attributes`.
3. **Always-present members**: `description` and `unit` are emitted even
   when empty; the data point `attributes` array is emitted even when empty
   (`"attributes":[]`). One data point per metric.
4. **Validation precedence**: batch points in order, then resource
   attributes, then scope attributes; the first typed error is returned
   unchanged. An empty batch is valid and encodes `"metrics":[]` (unlike the
   trace encoder, which rejects an empty span batch).
5. **Golden**: one gauge with one string attribute is 305 bytes (section 8).

## 6. Sink seam (`xiom.otel.sink`)

| Type | Shape | Meaning |
|---|---|---|
| `OtelSink` | `{ payloads: Vec[Str]; spans_exported: Int; bytes_exported: Int; errors: Int }` | collector sink: retained payloads + honest cumulative counters |
| `OtelExportStats` | `{ spans: Int; bytes: Int }` | one call's counts |

- `otel_sink_new()` -> empty sink, zero counters.
- `otel_export(sink, spans, resource, scope)`: encode; on success append the
  payload to `sink.payloads`, grow `spans_exported` / `bytes_exported` by
  the call's counts, return the stats; on encode failure increment
  `errors` by one, leave everything else untouched, return the typed error.
- `otel_export_send(sink, spans, resource, scope, send)`: encode, then hand
  the exact payload bytes to the caller-supplied
  `send: fn(Str) -> Result[Unit, Str]` (the transport seam; no transport
  ships in 0.2.0 and no network code exists). The payload is not retained
  (the hook consumed it). Hook success grows the counters; hook failure
  increments `errors` and returns `OTEL_ERR_SINK` with the hook's message
  appended; encode failure skips the hook and returns the encoder error.

Counters are only appended after success; they are exact byte counts of the
emitted payloads, never estimates.

## 7. Declared surface

Constants: 26 (`OTEL_SPAN_KIND_*` 5, `OTEL_STATUS_*` 3, `OTEL_VALUE_*` 4,
`OTEL_ERR_*` 11, caps 3). Unchanged in 0.2.0.
Types: 12 (`OtelError`, `OtelValue`, `OtelAttribute`, `OtelResource`,
`OtelScope`, `OtelSpan`, `OtelSpanBatch`, `OtelTracer`, `OtelSink`,
`OtelExportStats`, plus 0.2.0 `OtelGaugePoint`, `OtelMetricsBatch`).

Functions (39):

- `xiom.otel` (34): `otel_error`, `otel_value_kind`, `otel_value_str`,
  `otel_value_int`, `otel_value_bool`, `otel_value_double`,
  `otel_attr_str`, `otel_attr_int`, `otel_attr_bool`, `otel_attr_double`,
  `otel_resource_new`, `otel_scope_new`, `otel_span_new`,
  `otel_span_set_parent`, `otel_span_set_status`,
  `otel_span_add_attribute`, `otel_batch_new`, `otel_batch_push`,
  `otel_tracer_new`, `otel_tracer_next_span`, `otel_hex_encode`,
  `otel_hex_is_valid`, `otel_hex_decode`, `otel_id_from_seed`,
  `otel_span_id_from_seed`, `otel_validate_attributes`, `otel_validate_span`,
  `otel_validate_batch`, plus 0.2.0 `otel_gauge_new`,
  `otel_gauge_add_attribute`, `otel_metrics_batch_new`,
  `otel_metrics_batch_push`, `otel_validate_gauge`,
  `otel_validate_metrics_batch`.
- `xiom.otel.otlp` (2): `otel_encode_json` (traces, unchanged),
  `otel_encode_metrics_json` (gauges, 0.2.0).
- `xiom.otel.sink` (3): `otel_sink_new`, `otel_export`, `otel_export_send`.

The 0.2.0 traces surface is byte-for-byte unchanged: no trace type, function
signature, validator rule, key order or golden payload was altered.

Deviation from the relay sketch: `otel_encode_json` returns
`Result[Str, OtelError]` (typed error), not `Result[Str, Str]`; the export
functions take `(sink, spans, resource, scope)` because the encoder needs
the resource and scope. Both are recorded here deliberately.

## 8. Test plan (`tests/test_conformance.xi`, 37 checks)

Driver plus four suite modules; run with:

```
.\scripts\port.ps1 -Package xiom.otel -TimeoutSec 600
```

1. **`tests/suite_model.xi` (10 checks)** -- hex encode/decode/validity
   KATs and typed hex errors; deterministic trace/span id KATs; tracer
   determinism; attribute constructors/accessors; validator behavior for
   ids, names, time, kind, status, attributes, caps (128/129, 1024/1025)
   and the empty batch.
2. **`tests/suite_encoder.xi` (12 checks)** -- exact-byte goldens for the
   minimal span, rich span (parent + all value kinds + status error),
   status OK, multi-span order, resource + scope, escaping/unicode
   (control escapes and raw UTF-8 pass-through), decimal-string rendering
   (0 / Int max / negative intValue), insertion order, uppercase id
   pass-through, scope attributes; the canonical byte rules (no raw
   whitespace, fixed frame, byte-determinism); typed encoder error
   pass-through for every error kind.
3. **`tests/suite_sink.xi` (8 checks)** -- empty sink; payload retention
   byte-equal to the encoder output; counter accumulation; error
   accounting for invalid and empty batches; send hook success (exact
   bytes delivered, payload not retained) and failure (`OTEL_ERR_SINK`,
   hook message preserved, encode failures skip the hook); multi-span
   stats.
4. **`tests/suite_metrics.xi` (7 checks, 0.2.0)** -- gauge/batch
   construction defaults; attribute insertion order plus validator
   acceptance and dup/empty-key rejection; empty name is `OTEL_ERR_NAME`;
   zero and negative time are `OTEL_ERR_TIME`; the exact 305-byte golden
   for one gauge with one string attribute; two-point insertion order and
   byte-identical re-encode; empty batch is valid and encodes
   `"metrics":[]`.

Every check prints one `[PASS]`/`[FAIL]` line; the process exit code is the
failure count. Str equality in the suite goes through
`compare.str_compare`. There are no SKIP states: the suite is fully
offline and deterministic. All fixtures are inline and composed from the
specification's declared mapping; no upstream file or generated data is
consumed.

## 9. Toolchain discipline (XIOM v0.64.5)

- No `?` propagation: explicit match/rewrap; Ok/Err construction confined
  to small leaf helpers.
- No `Float64` payloads in enums (see 2.1): the model uses the flat
  kind-tagged `OtelValue` struct; the probe that established this is
  summarized in `PROVENANCE.md`.
- `UInt64` arithmetic is wrapping; the builtin `>>` on `UInt64` is
  arithmetic, so `_u64_shr` masks to the logical result (the
  `xiom.hash.xxhash` trick).
- `Str` values are NUL-terminated: `Str::from_utf8` truncates at a NUL
  byte, so fixtures never build NUL-containing strings; the encoder's
  `\u0000` escape is unreachable from Strs produced by the runtime's
  string constructors (kept for completeness of the escape table).
- Decimal rendering of `Int` never negates the value (the `Int` minimum's
  negation would overflow): digits are extracted from the signed value.
- Byte-level emits go through `xiom.string.builder` (`sb_new`,
  `sb_push_byte`, `sb_push_str`, `sb_to_str`); single-byte comparisons use
  `Str.byte_at` with the value masked to 0..255.
- Str equality everywhere is `xiom.string.compare.str_compare`.

## 10. Non-goals (declared, not silently missing)

- **OTLP/HTTP transport**: no URL, headers, content type, compression,
  retry/backoff or connection handling in 0.2.0; `otel_export_send` is the
  seam a caller transport plugs into (planned for a later 0.2.x or 0.3
  release over a caller-supplied HTTP client).
- **OTLP/protobuf binary encoding** (`application/x-protobuf`).
- **Logs signals**; **metrics beyond gauges**: counters/sums, histograms,
  exponential histograms, summaries, aggregation temporality,
  `start_time_unix_nano`, exemplars, metric `flags` and monotonic hints are
  not modeled. 0.2.0 ships one gauge data point per metric entry only.
  The trace surface documentation is otherwise unchanged from 0.1.0.
- **Span events, links, `trace_state`, `flags`, dropped counts,
  `schema_url`, resource `entity_refs`**: not modeled.
- **Attribute arrays, kvlists and byte values** (`arrayValue`,
  `kvlistValue`, `bytesValue`): not modeled.
- **Sampling, span processors, batch processors, export queues**:
  out of scope; the sink is a plain collector and the tracer is a plain
  deterministic factory.
- **UTF-8 validation of strings**: pass-through; producing invalid UTF-8
  violates the OTLP SHOULD and is the caller's responsibility.
- **Sampler/processor state, metrics of the SDK itself**, resource
  detection, OTel semantic-convention helpers.
