# xiom.otel

> **Status:** `incubating` -- conformance-tested (30/30), recorded x2 green
> on XIOM v0.64.5. Published: `0.1.0` in `eco-v0.1.188` (sha256 `830f9eab...`).
> **Scope:** OpenTelemetry trace model + deterministic OTLP/JSON encoder +
> sink seam, pure XIOM: typed spans/attributes/resource/scope, exact-byte
> OTLP/JSON payloads, a collector sink and a caller-supplied send hook.
> No FFI, no upstream OpenTelemetry code; HTTP transport stays
> caller-supplied.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.compare`,
> `xiom.string.builder`, `xiom.convert`; the tests use `xiom.test`,
> `xiom.io`, `xiom.string`, `xiom.math.constants`).

## What it is

`xiom.otel` is the phase-1 core of the tracing-export direction: it turns
typed spans into the exact bytes an OTLP/HTTP receiver expects, without
knowing anything about the network.

- **Model** (`xiom.otel`): `OtelSpan`, `OtelAttribute`/`OtelValue`,
  `OtelResource`, `OtelScope`, `OtelSpanBatch` and a deterministic
  `OtelTracer`; typed errors (`OtelError`) with a numeric `OTEL_ERR_*`
  taxonomy, documented caps (128 attributes per list, 1024 spans per
  batch, 1024-byte names) and explicit validators
  (`otel_validate_span`, `otel_validate_batch`, `otel_validate_attributes`).
  Ids are hex text (16-byte trace, 8-byte span); `otel_id_from_seed` /
  `otel_span_id_from_seed` derive reproducible ids from a seed with no
  randomness, and every timestamp is caller-provided -- the library holds
  no clock and no globals.
- **Encoder** (`xiom.otel.otlp`): `otel_encode_json` emits the OTLP/JSON
  `ExportTraceServiceRequest` structure
  (`resourceSpans[].scopeSpans[].spans[]`) byte-deterministically: hex
  trace/span ids, integer enum values, `startTimeUnixNano` /
  `endTimeUnixNano` as decimal strings, `intValue` as a decimal string,
  `stringValue`/`boolValue`/`doubleValue`, optional `status`. Fixed key
  order, insertion-order attributes, exact separators, JSON escapes with
  raw UTF-8 pass-through -- pinned by exact-byte goldens (SPEC.md
  section 5).
- **Sink seam** (`xiom.otel.sink`): `otel_export` collects encoded
  payloads in a `Vec[Str]` (tests/embedding) with honest counters (spans,
  bytes, errors); `otel_export_send` hands the exact bytes to a
  caller-supplied `fn(Str) -> Result[Unit, Str]` hook -- the transport
  seam. No network code exists in 0.1.0; hook failures surface as
  `OTEL_ERR_SINK`.

See `SPEC.md` for the model tables, the OTLP/JSON mapping table, the
canonical byte rules, the error taxonomy, caps and the non-goals
(protobuf, metrics/logs, events/links, sampling, processors);
`PROVENANCE.md` records the explicit independent declaration and the
pinned OTLP specification references.

## Install / use

Until the package is published to the registry, build against this
checkout with the repo harness:

```
.\scripts\port.ps1 -Package xiom.otel -TimeoutSec 600
```

Once published:

```
xiom pkg install xiom.otel@0.1.0
```

## Quick start

```xi
use xiom.io;
use xiom.otel;         // model: OtelSpan, otel_span_new, otel_attr_*, ...
use xiom.otel.otlp;    // otel_encode_json
use xiom.otel.sink;    // OtelSink, otel_sink_new, otel_export

fn main() -> Int {
  var span: OtelSpan = otel_span_new(
    "0af7651916cd43dd8448eb211c80319c",   // trace id (16 bytes, hex)
    "b7ad6b7169203331",                   // span id (8 bytes, hex)
    "GET /items",
    OTEL_SPAN_KIND_SERVER,
    1544712660000000000,                  // caller-provided unix nanos
    1544712661000000000);
  otel_span_add_attribute(&mut span, otel_attr_str("http.method", "GET"));
  otel_span_add_attribute(&mut span, otel_attr_int("http.status_code", 200));
  otel_span_set_status(&mut span, OTEL_STATUS_OK, "");

  var batch: OtelSpanBatch = otel_batch_new();
  otel_batch_push(&mut batch, span);

  var res: OtelResource = otel_resource_new();
  res.attributes.push(otel_attr_str("service.name", "checkout"));
  let scope: OtelScope = otel_scope_new("my.app", "1.0.0");

  let encoded = otel_encode_json(&batch, &res, &scope);
  match encoded {
    Ok(payload) => {
      io.println(payload);   // exact OTLP/JSON body for POST /v1/traces
      var sink: OtelSink = otel_sink_new();
      let exported = otel_export(&mut sink, &batch, &res, &scope);
      match exported {
        Ok(stats) => {
          io.println("exported " + stats.spans.to_str() + " spans / " + stats.bytes.to_str() + " bytes");
        },
        Err(e) => { io.println("export failed: " + e.message); },
      }
    },
    Err(e) => { io.println("encode failed: " + e.message); },
  }
  return 0;
}
```

A production transport plugs in at `otel_export_send(sink, batch, resource,
scope, send)`; the hook receives the exact encoded bytes.

## Boundaries

See `SPEC.md` for the exact struct fields, the OTLP/JSON field mapping,
the encoder canonical rules, the `OTEL_ERR_*` taxonomy, the caps and the
declared surface (32 functions / 10 types / 26 constants); `PROVENANCE.md`
records the independent-declaration basis (the published OTLP
specification and its JSON mapping; no upstream implementation consulted)
and the compiler finding behind the flat `OtelValue` layout.
