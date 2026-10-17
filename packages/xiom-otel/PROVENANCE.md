# PROVENANCE: xiom.otel

Upstream-first record (owner policy 2026-10-11, `docs/UPSTREAM-FIRST.md`).

This package is an **EXPLICITLY INDEPENDENT declaration: no vendored
upstream code, no translated code, no generated code, no upstream
implementation source consulted.** It is a pure-XIOM, from-scratch trace
model, OTLP/JSON encoder and sink seam for a protocol whose wire format is
fully specified in public documentation. There is **no C bridge, no FFI,
no vendored OpenTelemetry SDK or collector code and no linked upstream
library** in the package.

## Reference basis

The implementation was written against the OpenTelemetry Protocol (OTLP)
specification and its JSON Protobuf Encoding mapping; the relay work item
for this package explicitly framed the work as an independent own-reader
build on exactly these grounds ("a thin OTLP/HTTP exporter package (or a
xiom.otel core) ... Phase 1 = the CORE + the OTLP/JSON encoder; transport
(HTTP) stays caller-supplied"; no upstream code, no FFI).

| Reference | Location (fetched 2026-10-15) | Use |
|---|---|---|
| OTLP specification, "JSON Protobuf Encoding" section (`opentelemetry-proto`, `docs/specification.md`; latest release at fetch time: **v1.11.1**, published 2026-09-29) | `https://raw.githubusercontent.com/open-telemetry/opentelemetry-proto/main/docs/specification.md` | the declared JSON deviations used by the encoder: trace/span ids as case-insensitive hex strings (not base64), enum fields MUST be integer values, lowerCamelCase object keys, 64-bit integers (incl. `startTimeUnixNano` / `endTimeUnixNano`) as decimal strings |
| OTLP trace data schema (`opentelemetry/proto/trace/v1/trace.proto`, same repository/date) | `https://raw.githubusercontent.com/open-telemetry/opentelemetry-proto/main/opentelemetry/proto/trace/v1/trace.proto` | the message/field set and field numbers that fix the encoder's canonical key order: `Span` (trace_id 1, span_id 2, parent_span_id 4, name 5, kind 6, start 7, end 8, attributes 9, status 15), `SpanKind` / `StatusCode` integer values, `Status` (message 2, code 3) |
| OTLP common schema (`opentelemetry/proto/common/v1/common.proto`, same repository/date) | `https://raw.githubusercontent.com/open-telemetry/opentelemetry-proto/main/opentelemetry/proto/common/v1/common.proto` | `AnyValue` oneof slots (`stringValue` / `boolValue` / `int64 intValue` / `doubleValue`) and `KeyValue`, `InstrumentationScope` shapes |
| OTLP resource schema (`opentelemetry/proto/resource/v1/resource.proto`, same repository/date) | `https://raw.githubusercontent.com/open-telemetry/opentelemetry-proto/main/opentelemetry/proto/resource/v1/resource.proto` | `Resource.attributes` shape |
| OTLP JSON example (`examples/trace.json`, same repository/date) | `https://raw.githubusercontent.com/open-telemetry/opentelemetry-proto/main/examples/trace.json` | studied for the JSON object shape only; no bytes from it are imported (all fixtures are hand-composed, see below) |
| RFC 4648 section 8 (hex encoding), referenced by the OTLP spec for the id deviation | IETF RFC 4648 | lowercase hex encoding of byte arrays |

No implementation source was read for this work: not the
`opentelemetry-go` / `opentelemetry-java` / `opentelemetry-python` SDKs,
not the OpenTelemetry Collector, not any third-party OTLP encoder, so
nothing needed to be derived, attributed or re-licensed. The facts
reproduced here are the protocol's interoperability surface (message and
field names, enum integer values, key casing, id hex encoding, 64-bit
integer string rendering), re-expressed in XIOM with no shared
identifiers, structure or text. The proto files and the specification
document are Apache-2.0 licensed by the OpenTelemetry Authors; they were
read as a specification only, and no portion of them is reproduced,
translated or vendored in this package or its tests.

## Clone / cleanup ledger

**No oracle repository was cloned for this package.** `E:\repos` was
searched first: no `opentelemetry-proto`, SDK or collector clone exists
there, and none was created for this work (the specification and schema
text above were read from the published upstream repository directly).
`E:\repos\CLEANUP.md` therefore has no row for this work item and was not
modified -- there is nothing to sweep. If a future revision wants live
parity against an OTLP receiver, that re-carve should pin the
`opentelemetry-proto` release tag (or an OpenTelemetry Collector release),
clone at that pin, and add a ledger row at that time.

## Fixture provenance (honest record)

- **No upstream-produced bytes or generated files are read by the suite.**
  Every exact-byte golden in `tests/suite_encoder.xi` is hand-composed
  from the declared canonical rules in `SPEC.md` section 5 (and pinned as
  the encoder's own regression goldens); every hex/id KAT is computed
  from the declared derivation in `SPEC.md` section 2.4.
- **Independent derivation cross-check.** During the build, the
  `SPEC.md` section 2.4 pipeline was transcribed into a scratch Python
  script (written from that section alone, no XIOM code copied) and it
  reproduced all 11 pinned trace-id/span-id KAT values exactly; the KATs
  are therefore independently reproducible, not only implementation-pinned.
  The script lived outside the repository (temp directory) and is not part
  of the package.
- **Compiler finding recorded here.** The model uses a flat kind-tagged
  `OtelValue` struct instead of a payload enum because XIOM v0.64.5
  mislowers `Float64` enum payloads. The characterization was done with
  scratch probes (deleted after use, outside the package): a local enum
  constructed with a float payload either read back denormal garbage
  (`3.45845952088873e-323` / `1.48219693752374e-323` in two shapes),
  silently failed to match qualified patterns, or produced an LLVM
  struct-layout collision (`%struct.Reverse` vs the enum layout) that
  failed clang. The flat struct round-trips exact float values and is the
  layout this package declares (SPEC.md section 2.1, section 9).
- The conformance suite is fully offline and deterministic (no network, no
  timestamps read from the environment); there are no SKIP states.

## Tooling note

Developed against the pinned toolchain resolved by `scripts/port.ps1`
(XIOM v0.64.5, stdlib `E:\xiom-lang\stdlib`) as a read-only consumer of
`xiom.string.compare`, `xiom.string.builder`, `xiom.convert`,
`xiom.test`, `xiom.io`, `xiom.string` and `xiom.math.constants`. The
package contains no FFI, so the B-20/B-25 FFI rules are satisfied by
construction.
