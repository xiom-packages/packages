# xiom-tracing

> **Status:** PLACEHOLDER -- reserved, spec pending. No implementation yet.
> **Scope:** Distributed tracing (spans, traces, propagation, context, export).
> **Deps:** stdlib; may wrap C (FFI).

## Libs inventory

| Lib | Description |
|-----|-------------|
| `span` | Span creation and lifecycle |
| `trace` | Trace context and correlation |
| `propagate` | Header and carrier propagation |
| `sampler` | Sampling and head decisions |
| `export` | Span batch export to backends |
