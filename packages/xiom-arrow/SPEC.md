# xiom.arrow -- SPEC

**Phase**: 2 | **Priority**: HIGH
**Status**: Phase-1 GREEN -- v0.1.0, 27 pub functions (excl. 16 DataType
constructors), 36 requires contracts; stub-safe link bridge + SKIP-safe real
libarrow probe (v0.64.5, 2026-10-16)
**Depends on**: stdlib `extern "C"` (xiom.ffi surface); optional system libarrow

## What it wraps

Apache Arrow -- in-memory columnar data format.
Pandas backend, zero-copy data sharing between libraries.

## Dependencies: System-installed, only for the REAL path. `apt install libarrow-dev`.

The conformance suite needs no libarrow: it links `bridge/arrow_bridge.c`
(stub-safe leg). The real-library probe finds libarrow at runtime; SKIPs
cleanly when absent (see "Bridge / loader").

## Bundling strategy: System-installed only. Nothing is vendored or installed
system-wide by this package.

## Architecture

```
xiom.arrow
|-- Types (DataType x 16 variants, Field, Schema, DataArray, Table)
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

Bridge / loader (`bridge/arrow_bridge.c`, linked via `port.args.json`):

```
LEG 1  THE 16 extern "C" CONFORMANCE SYMBOLS (offline, deterministic)
       0  = Arrow runtime unavailable (wrappers collapse <= 0 to Err)
      -1  = invalid argument (null pointer, negative length, n_buffers > 3,
            negative n_columns)
       accessors return neutral 0; void entries are safe no-ops.
       Phase 2 swaps these bodies 1:1 for Arrow C++ (arrow/c/bridge.h
       ImportArray/ExportArray) behind the same 16 symbols.
LEG 2  REAL-LIBRARY LOADER + C DATA INTERFACE BOUNDARY (probe only)
       xiom_arrow_lib_probe()   LoadLibraryA/dlopen scan: libarrow.dll,
                                arrow.dll (Windows); libarrow.so[.NNNN],
                                libarrow[.NNNN].dylib (POSIX) in PATH,
                                XIOM_ARROW_LIB, ARROW_HOME, System32,
                                Python site-packages (pyarrow), vcpkg,
                                /usr/lib*, /usr/local/lib, /opt/homebrew/lib.
       xiom_arrow_cdi_layout_check()   pins ArrowSchema=72/ArrowArray=80 bytes
       xiom_arrow_cdi_roundtrip()      real producer int64 column, consumed
                                       and released; release pointer NULLed
```

## API (complete)

### Low-level -- Arrow C Data Interface

```xiom
// Types
pub type ArrowArray = Int;
pub type ArrowSchema = Int;

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

### High-level -- DataType, DataArray, Table

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

// DataArray (high-level)
pub fn array_new(typ: DataType, data: Vec[Int]) -> Result[DataArray, Str]
pub fn array_length(arr: &DataArray) -> Int
pub fn array_null_count(arr: &DataArray) -> Int
pub fn array_data_type(arr: &DataArray) -> DataType
pub fn array_is_valid(arr: &DataArray) -> Bool

// Table
pub fn table_new(schema: Schema, columns: Vec[DataArray]) -> Result[Table, Str]
pub fn table_column(t: &Table, idx: Int) -> Result[DataArray, Str]
pub fn table_num_columns(t: &Table) -> Int
pub fn table_num_rows(t: &Table) -> Int
pub fn table_schema(t: &Table) -> Schema

// IPC (Phase 2)
pub fn ipc_write(t: &Table, path: Str) -> Result[Unit, Str]
pub fn ipc_read(path: Str) -> Result[Table, Str]
```

## Deviation: the high-level type is `DataArray`, not `Array` (XARROW-ARRAYNAME)

The SPEC originally declared the high-level array type as `Array`. On the
pinned compiler (v0.64.5) `Array` is a built-in type name (fixed-size
`[T; N]`); a struct with that exact name imported from another module fails
codegen: every use warns `unknown type 'Array' -- defaulting to i64` and
struct literals are emitted as zeroed i64 (minimal repro: an imported struct
named `Array` yields all-zero fields; the same struct renamed or defined
locally works). The type is therefore named `DataArray`; all 27 public
function names, the two low-level handle aliases (`ArrowArray`,
`ArrowSchema`), the test names and test order are unchanged. Revisit when the
compiler fixes imported-name shadowing of builtin `Array`.

## Contract coverage

36 requires clauses across 26 functions (verify with
`xiom --dump-contracts src/arrow.xi`):

- DataType: `requires: id >= 0, id <= 15` (data_type_from_id)
- Field: `requires: name.len() > 0` (field_new, field_new_non_nullable)
- Schema: `requires: fields.len() > 0` (schema_new); `requires: idx >= 0` (schema_get_field)
- Array create: `requires: length >= 0, n_buffers >= 0, n_buffers <= 3`
- Array ops: `requires: arr != 0`; `requires: index >= 0` (get_buffer/get_child)
- Schema create: `requires: format.len() > 0`; `requires: schema != 0` (free/get_format/get_name)
- Record batch: `requires: schema != 0, n_columns >= 0, columns != 0`; `requires: batch != 0` (get_column/get_schema)
- Table: `requires: schema.fields.len() > 0, columns.len() == schema.fields.len()`; `requires: idx >= 0, idx < t.columns.len()`
- IPC: `requires: path.len() > 0`

Suite-run note (XARROW-NOCONTRACTS): `port.args.json` passes
`--no-contracts` to the suite run because several of the 27 conformance
checks deliberately probe out-of-contract inputs (e.g. `data_type_from_id(99)`,
`array_create(-1, 2)`, `record_batch_create(0, ...)`) to observe the safe
wrappers' defensive `Err` returns; with runtime contract checks enabled those
calls trap by design. The clauses stay declared and compile-checked; only the
suite run disables the runtime trap.

## Arrow C Data Interface boundary (zero-copy interop)

Zero-copy interop is the Arrow C Data Interface, not a function API: the
consumer (pandas/pyarrow side) reads the two public structs directly.
`bridge/arrow_bridge.c` pins and exercises this 64-bit layout
(apache/arrow `cpp/src/arrow/c/abi.h`, Apache-2.0, stable public ABI):

```c
struct ArrowSchema {           /* 72 bytes, offsets 0..64 */
  const char* format;          /* 0   format string, see table below   */
  const char* name;            /* 8   field name (may be NULL)         */
  const char* metadata;        /* 16  key-value metadata (may be NULL) */
  int64_t flags;               /* 24  1=dictionary-ordered, 2=nullable, 4=map-keys-sorted */
  int64_t n_children;          /* 32 */
  struct ArrowSchema** children;/* 40 */
  struct ArrowSchema* dictionary;/* 48 */
  void (*release)(struct ArrowSchema*);/* 56  must NULL itself after the call */
  void* private_data;          /* 64 */
};

struct ArrowArray {            /* 80 bytes, offsets 0..72 */
  int64_t length;              /* 0  logical length */
  int64_t null_count;          /* 8  -1 = unknown */
  int64_t offset;              /* 16 logical offset into buffers */
  int64_t n_buffers;           /* 24 */
  int64_t n_children;          /* 32 */
  const void** buffers;        /* 40  [validity, data, (offsets)] */
  struct ArrowArray** children;/* 48 */
  struct ArrowArray* dictionary;/* 56 */
  void (*release)(struct ArrowArray*);/* 64 */
  void* private_data;          /* 72 */
};
```

The facts the pandas bridge will use (verified by
`tests/probe_real_libarrow.xi` on every run):

- Layout: sizes 72/80, field offsets as above (x86_64); a loaded real
  libarrow adds presence/load evidence on top.
- Buffer model: buffer 0 = validity bitmap, LSB-first, bit i = value i valid
  (NULL allowed when null_count == 0); buffer 1 = data (int64 values,
  little-endian); utf8/binary add buffer 2 and use buffer 1 as int32/64
  offsets.
- Format strings for the 16 DataType variants: null=n, int8=c, int16=s,
  int32=i, int64=l, uint8=C, uint16=S, uint32=I, uint64=L, float32=f,
  float64=g, bool=b, utf8=u, binary=z, date32=tdD; timestamp materializes as
  a unit-suffixed ts format (ts[s]/ts[ms]/ts[us]/ts[ns]) in Phase 2. A null
  bit is authoritative even when the value slot is arbitrary.
- Ownership: the producer fills the struct and installs `release`; the
  consumer must call `release` exactly once; the call frees producer storage
  and NULLs the pointer; children/dictionary are released by the parent
  `release`; a second call after the NULL check is a no-op.
- The probe's deterministic round-trip: one int64 column `x` = [42, -7, null,
  123456789, -1] (validity 0b11111011, null_count 1) produced, consumed
  (length/null_count/offset/n_buffers/buffers/format/name/flags checked) and
  released, with the release contract verified.

## File structure

```
packages/xiom-arrow/
|-- SPEC.md                  <- This file
|-- README.md                <- Status, scope, libs inventory
|-- ROADMAP.md               <- Version tracking, milestones, two-leg split
|-- STATUS.json              <- Recorded suite run
|-- port.args.json           <- Wires bridge/arrow_bridge.c + --no-contracts into port.ps1
|-- src/
|   `-- arrow.xi             <- module xiom.arrow (519 lines)
|-- bridge/
|   `-- arrow_bridge.c       <- 16 stub-safe symbols + loader + CDI boundary (612 lines)
|-- tests/
|   |-- test_conformance.xi  <- 27 conformance tests, current xiom.test API (640 lines)
|   `-- probe_real_libarrow.xi <- SKIP-safe real-libarrow probe (121 lines, not in port.ps1)
`-- package.xi
```

## Header / clone protocol (Phase 2, if headers are needed)

This Phase-1 bridge needs no Arrow headers: the C Data Interface layout is
transcribed above from the public ABI (Apache-2.0). When Phase 2 compiles
against Arrow C++, headers come from a LIGHT clone under `%TEMP%\kilo\`:
`git clone --depth 1 --filter=blob:none --sparse https://github.com/apache/arrow.git`
(license-check Apache-2.0 `LICENSE.txt`), sparse-checkout `cpp/src/arrow/c`,
and the cloned commit SHA recorded here and in ROADMAP. Nothing vendored.

## Phased roadmap

| Phase | What | Effort | Status |
|-------|------|--------|--------|
| 1 | Types, extern "C" stubs, safe wrappers, contracts, tests | Day | [OK] Done |
| 1b | Stub-safe link bridge, real-lib loader + CDI boundary, probe | Day | [OK] Done (27/27 x2, v0.64.5) |
| 2 | Real C bridge (libarrow C++ + headers), IPC read/write, demo.xi | Week | [ ] Pending |
| 3 | Nested types (List, Struct, Map), Pandas interop | Weekend | [ ] Pending |
