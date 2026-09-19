# xiom.parquet

> **Status:** PLACEHOLDER -- reserved, spec pending. No implementation yet.
> **Scope:** Parquet columnar file reading and writing.
> **Deps:** stdlib; may wrap C (FFI).

## Libs inventory

| Lib | Description |
|-----|-------------|
| `parquet-schema` | Parquet schema model |
| `parquet-read` | Columnar reader and row-group decode |
| `parquet-write` | Columnar writer and row-group encode |
| `parquet-metadata` | Footer metadata parsing |
