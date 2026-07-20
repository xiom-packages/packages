# xiom-arrow — SPEC

**Phase**: 2 | **Priority**: HIGH
**Status**: SPEC only | **Depends on**: xiom.ffi

## What it wraps
Apache Arrow — in-memory columnar data format.
Pandas backend, zero-copy data sharing between libraries.

## Dependencies: System-installed. `apt install libarrow-dev`.

## Bundling strategy: System-installed only.

## API (minimal)
```xiom
pub fn array_new(typ: DataType, data: Vec[UInt8]) -> Result[Array, Str]
pub fn array_length(arr: &Array) -> Int
pub fn table_new(schema: Schema, columns: Vec[Array]) -> Result[Table, Str]
pub fn table_column(t: &Table, idx: Int) -> Result[Array, Str]
pub fn ipc_write(t: &Table, path: Str) -> Result[Unit, Str]
pub fn ipc_read(path: Str) -> Result[Table, Str]
```

## Effort: Week
