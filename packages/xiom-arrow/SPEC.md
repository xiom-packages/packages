# xiom.arrow -- SPEC

**Phase**: 2 | **Priority**: HIGH
**Status**: Phase-2 SOURCE GREEN -- v0.1.0, 52 pub functions (excl. 16 DataType
constructors), 51 requires contracts; offline stub suite 32/32 x2 plus a REAL
Apache Arrow C++ 22.0.0 backend (`bridge/arrow_real.cpp`) built and run
locally against the pyarrow 22.0.0 MSVC wheel (v0.64.6, 2026-10-17)
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
       The Phase-2 additive symbols are stubbed here too (same validation,
       backend-unavailable) so the offline suite always links.
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

Real backend (`bridge/arrow_real.cpp`, Phase 2; probe only, never in
`port.args.json`):

```
THE SAME 16 SYMBOLS, implemented with Apache Arrow C++:
  ArrowSchema/ArrowArray handles are bridge-owned C++ objects (field/schema/
  array/record-batch); arrow_array_create returns a real CDI struct ArrowArray
  (release callback + private_data) for the legacy allocation shape.
ADDITIVE ZERO-COPY HANDOFF (9 symbols, all i64):
  arrow_schema_create_struct(names, formats, n)    struct ("+s") schema
  arrow_array_from_int64(values, len)              typed Int64 array
  arrow_array_from_float64(values, len)            typed Float64 array
  arrow_record_batch_export(batch, schema*, array*)  ExportRecordBatch
  arrow_record_batch_import(schema*, array*)       ImportRecordBatch (moves)
  arrow_schema_release(slot) / arrow_array_release(slot)  exactly-once release
  arrow_backend_available() / arrow_backend_version()     identity
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
locally works). The type is therefore named `DataArray`; all previously declared
public function names, the two low-level handle aliases (`ArrowArray`,
`ArrowSchema`), the test names and test order are unchanged. Revisit when the
compiler fixes imported-name shadowing of builtin `Array`.

## Contract coverage

51 requires clauses across 34 functions plus 1 ensures (verify with
`xiom --dump-contracts src/arrow.xi`):

- DataType: `requires: id >= 0, id <= 15` (data_type_from_id)
- Field: `requires: name.len() > 0` (field_new, field_new_non_nullable)
- Schema: `requires: fields.len() > 0` (schema_new); `requires: idx >= 0` (schema_get_field)
- Array create: `requires: length >= 0, n_buffers >= 0, n_buffers <= 3`
- Array ops: `requires: arr != 0`; `requires: index >= 0` (get_buffer/get_child)
- Schema create: `requires: format.len() > 0`; `requires: schema != 0` (free/get_format/get_name)
- Record batch: `requires: schema != 0, n_columns >= 0, columns != 0`; `requires: batch != 0` (get_column/get_schema)
- Phase-2 handoff: `requires: names/formats != 0, n_columns > 0`; `values != 0, length > 0`; `batch/out_schema/out_array != 0`; `schema_slot/array_slot != 0`; `backend_available` uses `requires: true` for its whole-body `unsafe` block
- Table: `requires: schema.fields.len() > 0, columns.len() == schema.fields.len()`; `requires: idx >= 0, idx < t.columns.len()`
- IPC: `requires: path.len() > 0`

Suite-run note (XARROW-NOCONTRACTS): `port.args.json` passes
`--no-contracts` to the suite run because several of the 32 conformance
checks deliberately probe out-of-contract inputs (e.g. `data_type_from_id(99)`,
`array_create(-1, 2)`, `record_batch_create(0, ...)`, null handoff slots) to
observe the safe wrappers' defensive `Err`/false returns; with runtime contract
checks enabled those calls trap by design. The clauses stay declared and
compile-checked; only the suite run disables the runtime trap.

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

## Real backend (Phase 2) -- pin, ABI gate, evidence

`bridge/arrow_real.cpp` is the real implementation of the declared low-level
surface plus the additive zero-copy handoff. It is C++17, exception-free at the
C ABI (every entry point catches `...`), and is linked ONLY by
`tests/probe_real_backend.xi` (never by `port.args.json`; the offline suite
keeps the deterministic stub leg).

### Pinned release / ABI

| Field | Value |
|-------|-------|
| Project | Apache Arrow -- `https://github.com/apache/arrow` (Apache-2.0) |
| Upstream pin | tag `apache-arrow-22.0.0`, commit `5aeb5f217f1ba39c428c9b481f393bd37097f69e` (2025-10-20) |
| Study clone | `E:\repos\arrow` (shallow `--filter=blob:none`, sparse: `cpp/src/arrow/{c,array,compute,acero,io,csv}`, `cpp/src/parquet`, table/builder/type headers; `LICENSE.txt` Apache-2.0 verified before checkout) |
| Runtime used for the gate | pyarrow 22.0.0 win_amd64 wheel `pyarrow-22.0.0-cp312-cp312-win_amd64.whl`, SHA256 `44729980B6C50A5F2BFCC2668D36C569CE17F8B17BCCAF470C4313DCBBF13C9D` (headers + `arrow.lib`/`arrow_compute.lib`/`arrow_acero.lib`/`parquet.lib` + DLLs are shipped inside the wheel), extracted to `E:\repos\arrow-bin\pyarrow-22.0.0` |
| Arrow build identity | `ARROW_PACKAGE_KIND "python-wheel-windows"`, `ARROW_CXX_COMPILER_ID "MSVC"`, `ARROW_CXX_COMPILER_VERSION "19.44.35217.0"` (`arrow/util/config.h`) |
| Why 22.0.0 | Newest release whose public headers compile as C++17. Arrow 24+ uses `std::span`/`std::bit_width` in public headers and requires C++20, contradicting the C++17 artifact requirement. |
| Bridge toolchain | LLVM/clang 22.1.8 driven by the pinned XIOM v0.64.6, target `x86_64-pc-windows-msvc` (`clang++ -std=c++17`), lld-link against the wheel's MSVC import libraries |

**ABI gate result: PASSED locally.** Both a direct object build
(`clang++ -std=c++17 -c` against `pyarrow/include`) and a full XIOM
link-and-run against the wheel's `.lib`/`.dll` set succeeded on this host; no
MSVC-vs-MinGW mix and no fake build. Full hashes and the exact commands are in
`PROVENANCE.md` and the probe header.

### Handle model

A handle is the address of a bridge-owned C++ object:

| Kind | Contents | Created by |
|------|----------|------------|
| field | `shared_ptr<arrow::Field>` (type parsed by `ImportField` from the CDI format string) | `arrow_schema_create` |
| schema | `shared_ptr<arrow::Schema>` (`+s`) | `arrow_schema_create_struct`, `arrow_record_batch_get_schema` |
| array | `shared_ptr<arrow::Array>` | `arrow_array_from_int64/float64`, `record_batch_get_column`, `array_get_child` |
| batch | `shared_ptr<arrow::RecordBatch>` | `arrow_record_batch_create/import` |
| legacy array | a real `struct ArrowArray` + buffer slot vector + release callback/`private_data` | `arrow_array_create` |

`array_free` disposes every `ArrowArray`-shaped handle (including batches);
`schema_free` disposes field/schema handles. Accessors never transfer
ownership.

### Ownership handoff (the pinned contract)

1. `arrow_record_batch_export(batch, out_schema, out_array)` writes a real
   `(ArrowSchema, ArrowArray)` pair into caller-owned 72/80-byte slots using
   `arrow::ExportRecordBatch`. The exported structs reference the batch
   buffers; their `private_data` keeps the C++ refcount alive. Ownership of
   the pair passes to the consumer. The producer handle stays valid and
   independent.
2. The consumer MUST do exactly one of:
   - `arrow_record_batch_import(schema_slot, array_slot)` -- moves the pair into
     a new record-batch handle. Import consumes and releases BOTH structs
     (the schema even on failure; both release pointers become NULL). Do not
     release afterwards.
   - `arrow_schema_release(schema_slot)` + `arrow_array_release(array_slot)` --
     each returns 1 when this call released the struct and 0 when it was
     already released. Call each exactly once. Never combine with import.
3. Copying the struct bytes without importing or releasing leaks the producer
   reference. A released/imported struct is never dereferenced again.
4. For a chunked `Table` owner, export batch-wise (`TableBatchReader` /
   `ExportRecordBatchReader`); `Table::CombineChunksToBatch()` copies when the
   table has more than one chunk and must be documented per call site.

### Build / probe recipe (verified)

```powershell
$arrow = "E:\repos\arrow-bin\pyarrow-22.0.0"
$env:CPLUS_INCLUDE_PATH = "$arrow\pyarrow\include"
$env:PATH = "$arrow\pyarrow;$arrow\pyarrow.libs;$env:PATH"
xiom --run packages\xiom-arrow\tests\probe_real_backend.xi `
    --cxx-standard 17 `
    --c-source <repo>\packages\xiom-arrow\bridge\arrow_real.cpp `
    --link arrow --link arrow_compute --link arrow_acero `
    --link-path "$arrow\pyarrow"
```

`arrow_compute` is linked because Arrow 22 splits the compute kernels into
`arrow_compute.dll`; the pandas bridge additionally calls
`arrow::compute::Initialize()` (the DLL is not loaded just by linking).
`arrow_acero` is not needed by this bridge's own symbols but is in the recipe
so the same command shape composes with the pandas probe.

### Probe evidence (2026-10-17, v0.64.6, Arrow 22.0.0)

```
[PASS] real backend linked: Apache Arrow C++ 22.0.0
[PASS] CDI layout: ArrowSchema=72 ArrowArray=80, field offsets pinned
[PASS] struct schema created (x: l, y: g)
[PASS] typed arrays: int64[5] and float64[5]
[PASS] record batch: 5 rows, schema format '+s'
[PASS] export filled the CDI struct pair (72/80 bytes)
[PASS] import consumed the pair (release pointers NULL)
[PASS] zero-copy: imported int64 buffer == producer buffer
[PASS] imported values intact (42, 1.5)
[PASS] release path: exactly-once release, producer handle intact
probe_real_backend: all checks passed
```

The "zero-copy" check compares the producer Int64 buffer address with the
buffer address of the column in the imported batch: they are identical, so the
export/import pair moved ownership without copying.

### Scope notes

- The 9 additive symbols extend `xiom.arrow` only. They do NOT touch the
  frozen 12-symbol pandas ABI (`pandas.xi` is unchanged).
- `ipc_write`/`ipc_read` remain declared Phase-2 stubs (no IPC symbols added).
- Nested types, dictionary-encoded export, and `date32`/`timestamp` typed
  builders are not part of this pass; the schema path accepts any CDI format
  Arrow can import, and the array path covers Int64/Float64 (plus any array
  obtained from a batch).
- `is_linked()` now reports the linked translation unit (false for the stub
  leg, true for the real bridge).

## File structure

```
packages/xiom-arrow/
|-- SPEC.md                  <- This file
|-- README.md                <- Status, scope, libs inventory
|-- ROADMAP.md               <- Version tracking, milestones, two-leg split
|-- STATUS.json              <- Recorded suite run
|-- port.args.json           <- Wires bridge/arrow_bridge.c + --no-contracts into port.ps1
|-- PROVENANCE.md            <- Upstream pin, wheel hash, derived vs independent
|-- src/
|   `-- arrow.xi             <- module xiom.arrow (68 pub fns)
|-- bridge/
|   |-- arrow_bridge.c       <- offline stub leg: 25 symbols + loader + CDI boundary
|   `-- arrow_real.cpp       <- REAL Arrow C++ backend (probe only, C++17)
|-- tests/
|   |-- test_conformance.xi  <- 32 offline conformance tests
|   |-- probe_real_libarrow.xi <- SKIP-safe loader/CDI probe (stub leg)
|   `-- probe_real_backend.xi  <- REAL backend probe (arrow_real.cpp; not in port.ps1)
`-- package.xi
```

## Header / clone protocol (as executed)

The offline bridge needs no Arrow headers: the C Data Interface layout is
transcribed from the public ABI (Apache-2.0). The real backend was built
against the headers shipped in the pyarrow 22.0.0 wheel (the same build as
the libraries, which is the ABI gate). For provenance/study the upstream
source was LIGHT-cloned to `E:\repos\arrow`:
`git clone --depth 1 --filter=blob:none --sparse --branch apache-arrow-22.0.0 https://github.com/apache/arrow.git`
(`LICENSE.txt` Apache-2.0 verified before checkout), sparse-checkout
`cpp/src/arrow/{c,array,compute,acero,io,csv}`, `cpp/src/parquet` and the
table/builder/type headers. Pin: commit `5aeb5f2`. Nothing vendored.

## Phased roadmap

| Phase | What | Effort | Status |
|-------|------|--------|--------|
| 1 | Types, extern "C" stubs, safe wrappers, contracts, tests | Day | [OK] Done |
| 1b | Stub-safe link bridge, real-lib loader + CDI boundary, probe | Day | [OK] Done (27/27 x2, v0.64.5) |
| 2a | REAL Arrow C++ backend: 16 declared symbols, zero-copy export/import pair, ownership handoff, probe | Day | [OK] Done (32/32 x2; real probe 10/10 on Arrow 22.0.0) |
| 2b | IPC read/write, demo.xi | Day | [ ] Pending |
| 3 | Nested types (List, Struct, Map), Pandas `dataframe_from_arrow` consumer | Weekend | [ ] Pending |
