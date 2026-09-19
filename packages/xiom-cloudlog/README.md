# xiom.cloudlog

> **Status:** PLACEHOLDER -- reserved, spec pending. No implementation yet.
> **Scope:** Cloud log ingestion, aggregation, storage, and retrieval pipelines.
> **Deps:** stdlib; may wrap C (FFI).

## Libs inventory

| Lib | Description |
|-----|-------------|
| `ingest` | Log intake and batching |
| `format` | Structured format encoding |
| `stream` | Tail and live-stream consumption |
| `store` | Long-term log retention |
| `search` | Query and filter across logs |
