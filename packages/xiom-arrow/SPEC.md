# xiom-arrow -- SPEC

**Phase**: 2 | **Priority**: HIGH
**Status**: IMPLEMENTED -- v0.1.0, 27 public functions, 32 requires contracts
**Depends on**: xiom.ffi

## What it wraps
Apache Arrow -- in-memory columnar data format.
Pandas backend, zero-copy data sharing between libraries.

## Dependencies: System-installed. `apt install libarrow-dev`.

## Bundling strategy: System-installed only.

## Architecture

```
xiom.arrow
|-- Types (DataType x 16, Field, Schema, Array, Table)
|-- extern "C" stubs (arrow_array_*, arrow_schema_*, arrow_record_batch_*)
|-- Safe wrappers (contract-enforced)
|   |-- ArrowArray: create, free, get_length, get_buffer, get_child, etc.
|   |-- ArrowSchema: create, free, get_format, get_name
|   `-- RecordBatch: create, get_column, get_schema
|-- High-level API
|   |-- array_new / array_length / array_data_type
|   |-- table_new / table_column / table_num_rows / table_schema
|   `-- ipc_write / ipc_read (Phase 2 stubs)
`-- Utility: version, is_linked
```

## API (complete)

### Low-level -- Arrow C Data Interface

```xiom
// Types
pub type ArrowArray = Int
pub type ArrowSchema = Int

// ArrowArray
pub fn array_create(length: Int, n_buffers: Int) -> Result[ArrowArray, Str]
pub fn array_free(arr: ArrowArray)
pub fn array_get_length(arr: ArrowArray) -> Int
pub fn array_get_null_count(arr: ArrowArray) -> Int
pub fn array_get_offset(arr: ArrowArray) -> Int
pub fn array_get_n_buffers(arr: ArrowArray) -> Int
pub fn array_get_buffer(arr: ArrowArray, index: Int) -> Result[Int, Str]
pub fn array_get_n_children(arr: ArrowArray) -> Int
pub fn array_get_child(arr: ArrowArray, index: Int) -> Result[ArrowArray, Str]

// ArrowSchema
pub fn schema_create(format: Str, name: Str) -> Result[ArrowSchema, Str]
pub fn schema_free(schema: ArrowSchema)
pub fn schema_get_format(schema: ArrowSchema) -> Result[Int, Str]
pub fn schema_get_name(schema: ArrowSchema) -> Result[Int, Str]

// RecordBatch
pub fn record_batch_create(schema: ArrowSchema, n_columns: Int, columns: Int) -> Result[ArrowArray, Str]
pub fn record_batch_get_column(batch: ArrowArray, index: Int) -> Result[ArrowArray, Str]
pub fn record_batch_get_schema(batch: ArrowArray) -> Result[ArrowSchema, Str]
```

### High-level -- DataType, Array, Table

```xiom
// DataType (16 variants: null, int8-int64, uint8-uint64, float32/64, bool, utf8, binary, date32, timestamp)
pub fn data_type_from_id(id: Int) -> Result[DataType, Str]
pub fn data_type_eq(a: &DataType, b: &DataType) -> Bool
pub fn data_type_name(dt: &DataType) -> Str

// Field
pub fn field_new(name: Str, data_type: DataType) -> Field
pub fn field_new_non_nullable(name: Str, data_type: DataType) -> Field
pub fn field_get_name(f: &Field) -> Str
pub fn field_get_type(f: &Field) -> DataType
pub fn field_is_nullable(f: &Field) -> Bool

// Schema
pub fn schema_new(fields: Vec[Field]) -> Schema
pub fn schema_empty() -> Schema
pub fn schema_add_field(s: &mut Schema, f: Field)
pub fn schema_num_fields(s: &Schema) -> Int
pub fn schema_get_field(s: &Schema, idx: Int) -> Result[Field, Str]

// Array (high-level)
pub fn array_new(typ: DataType, data: Vec[Int]) -> Result[Array, Str]
pub fn array_length(arr: &Array) -> Int
pub fn array_null_count(arr: &Array) -> Int
pub fn array_data_type(arr: &Array) -> DataType
pub fn array_is_valid(arr: &Array) -> Bool

// Table
pub fn table_new(schema: Schema, columns: Vec[Array]) -> Result[Table, Str]
pub fn table_column(t: &Table, idx: Int) -> Result[Array, Str]
pub fn table_num_columns(t: &Table) -> Int
pub fn table_num_rows(t: &Table) -> Int
pub fn table_schema(t: &Table) -> Schema

// IPC (Phase 2)
pub fn ipc_write(t: &Table, path: Str) -> Result[Unit, Str]
pub fn ipc_read(path: Str) -> Result[Table, Str]
```

## Contract coverage

- Array create: `requires: length >= 0, n_buffers >= 0, n_buffers <= 3`
- Array operations: `requires: arr != 0, index >= 0, index < n_buffers`
- Schema create: `requires: format.len() > 0`
- Record batch: `requires: schema != 0, n_columns >= 0, columns != 0`
- Table: `requires: schema.fields.len() > 0, columns.len() == schema.fields.len()`
- Field: `requires: name.len() > 0`
- IPC: `requires: path.len() > 0`

## File structure

```
packages/xiom-arrow/
|-- SPEC.md              <- This file
|-- ROADMAP.md           <- Version tracking, milestones, FFI bridge gap
|-- src/
|   `-- arrow.xi         <- module xiom.arrow (451 lines)
|-- tests/
|   `-- test_conformance.xi <- 27 conformance tests (451 lines)
`-- package.xi           <- (pending)
```

## Effort: Week (Phase 1 complete)

## Phased roadmap

| Phase | What | Effort | Status |
|-------|------|--------|--------|
| 1 | Types, extern "C" stubs, safe wrappers, contracts, tests | Day | [OK] Done |
| 2 | C bridge (libarrow), IPC read/write, demo.xi | Week | [ ] Pending |
| 3 | Nested types (List, Struct, Map), Pandas interop | Weekend | [ ] Pending |
