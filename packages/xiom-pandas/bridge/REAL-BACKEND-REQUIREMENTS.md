# Real Arrow-backed bridge -- requirements (for the bindings/xiom.arrow lanes)

Status 2026-10-16: the OFFLINE stub bridge (bridge/pandas_bridge.c) is shipped
and the conformance suite is green (80/80 x2). The REAL bridge is NOT built;
this document pins exactly what it must provide. Nothing here changes the
current 12-symbol Phase-1 ABI -- additions are listed and marked as such.

## 1. Artifact

- File: `bridge/xiom_pandas_arrow.cpp` (C++17, exception-free at the C ABI).
- Links system Apache Arrow C++ (`libarrow`; plus `libarrow_acero`, and
  `libparquet` for the parquet leg) installed via xiom.arrow.
- Exports plain C symbols (the `pandas_c_*` names below); all internal C++
  types stay inside the bridge.
- NEVER linked by the offline suite; used only by probe runs (section 5).

## 2. Symbol + ABI contract

ABI (fixed by pandas.xi, compiler IR-verified): every parameter and return
value is i64 (`long long` in C/C++); `0` = null/failure, `> 0` = live handle;
a live handle is the address of a bridge-owned C++ object. The stub's
argument validation (bridge/pandas_bridge.c) is part of the contract: the
real bridge must keep the same 0-in/0-out semantics for the cases pinned by
tests/test_conformance.xi.

| Symbol (C) | Validation (must keep) | Real implementation | Headers / Arrow API |
|---|---|---|---|
| `pandas_c_dataframe_new` | null `col_names`/`col_types` or `num_cols <= 0` -> 0 | Build an empty `arrow::Table` whose schema has one field per name: `col_names` = `char*[num_cols]` (NUL-terminated), `col_types` = `i64[num_cols]` of DTYPE_* (0..5 -> int32/int64/float32/float64/utf8/bool). Wrap schema in the Table object via `arrow::RecordBatch::Make`/`Table::FromRecordBatches` with 0 rows. | `arrow/table.h`, `arrow/type.h`, `arrow/api.h` |
| `pandas_c_dataframe_from_csv` | null path -> 0 | `csv::TableReader::Make(io::IOContext, io::FileInputStream::Open(path), ReadOptions, ParseOptions, ConvertOptions)` -> `Read()` -> `Table`. | `arrow/csv/api.h`, `arrow/csv/options.h`, `arrow/io/file.h` |
| `pandas_c_dataframe_to_csv` | null handle/path -> 1 | `csv::WriteCSV(*table, WriteOptions, io::FileOutputStream)`. | `arrow/csv/api.h` (`WriteCSV`), `arrow/csv/options.h`, `arrow/io/file.h` (pin exact header in the chosen release) |
| `pandas_c_dataframe_get_column` | null handle/name -> 0 | Column lookup by name (`Table::GetColumnByName`); handle wraps the `std::shared_ptr<ChunkedArray>` (zero-copy view of the column chunks). | `arrow/table.h` |
| `pandas_c_dataframe_set_column` | null handle/name/values or `len <= 0` -> 0 | `values` = `double[len]`; build an Arrow array (NumericBuilder or `arrow::MakeArray` from buffers), replace or append the field (schema rebuild), return the new Table handle. | `arrow/builder.h`, `arrow/table.h` |
| `pandas_c_dataframe_filter` | null handle/name or `op` outside 0..5 -> 0 | Compare the column against a scalar with `CallFunction("equal"/"not_equal"/"less"/"less_equal"/"greater"/"greater_equal", ...)` -> boolean mask, then `Filter(table, mask)`. NOTE: `value` currently travels as `Int` (integer comparisons only, see section 6.5). | `arrow/compute/exec.h` (`CallFunction`), `arrow/compute/api.h` (`Filter`), `arrow/compute/api_scalar.h` |
| `pandas_c_dataframe_groupby` | null handle/name -> 0 | Grouped aggregate handle. Recommended: Acero hash aggregation (`Declaration{"hash_group_aggregate", HashAggregateNodeOptions{...}}`); fall back to the version's `TableGroupBy` convenience class if present. Handle owns the group-by object plus the input Table. | `arrow/acero/api.h`, `arrow/acero/options.h` (version-sensitive -- see section 6.1) |
| `pandas_c_dataframe_join` | null handle(s)/name or `how` outside 0..3 -> 0 | libarrow compute has NO stable plain join; use Acero hash join (`Declaration{"hash_join", HashJoinNodeOptions{...}}`, JOIN_* 0..3 -> INNER/LEFT/RIGHT/OUTER) or, for ABI-stability, implement the join in the bridge with `arrow::compute::Take` + a dictionary-encoded key. | `arrow/acero/api.h`, `arrow/acero/options.h` (version-sensitive -- section 6.1) |
| `pandas_c_series_new` | null values or `len <= 0` or `dtype` outside 0..5 -> 0 | Build an Arrow `Array` of the DTYPE_* type from a raw `values` buffer (interpretation per dtype). | `arrow/builder.h`, `arrow/array.h` |
| `pandas_c_series_from_vec` | same as above | Same as `series_new`; the declared source is Float64 (`double[len]`). | `arrow/builder.h` |
| `pandas_c_series_to_vec` | null handle or null `out_len` -> 0 | Extract/copy values into a bridge-owned buffer, write the element count through `out_len` (`i64*`), return the buffer address. Ownership: see section 6.4. | `arrow/array.h`, `arrow/chunked_array.h` |
| `pandas_c_series_apply` | null handle or null `func_ptr` -> 0 | Checkpoint lambda application over element storage. The callback ABI is UNPINNED (section 6.3): recommend `double (*)(double)` applied in a bridge-side loop to a `double` array (correctness first; Arrow has no per-element map kernel for raw C callbacks). | `arrow/builder.h` |

`how`/`op`/`dtype` code meanings are pandas.xi constants: DTYPE_INT32..BOOL =
0..5, CMP_EQ..CMP_GE = 0..5, JOIN_INNER..JOIN_OUTER = 0..3.

## 3. C++ ABI + build notes

- Compile as C++17 with the SAME toolchain family as the Arrow build whose
  headers/libraries are used. Windows: official/vcpkg Arrow is MSVC-built --
  the bridge must be MSVC (or clang-cl against the MSVC ABI); do NOT mix a
  MinGW C++ stdlib against MSVC-built Arrow.
- Linux/macOS: match the distro/Homebrew Arrow's compiler and
  `_GLIBCXX_USE_CXX11_ABI`; link the versioned `libarrow.so.<n>` (or
  `libarrow.dylib`) from the same package as the headers.
- Arrow C++ returns `arrow::Status`/`Result<T>`; the bridge must convert
  those to the 0/1 error convention and must never let a C++ exception
  escape the C ABI.
- Handles stay valid until released; use the process-wide
  `arrow::default_memory_pool()` and a single-threaded `ExecContext` for
  Phase 2 (no custom threading requirements).
- Windows paths: accept UTF-8 NUL-terminated paths (`io::FileInputStream::Open`
  handles platform conversion).

## 4. Zero-copy Arrow C Data Interface points

- The C ABI structs are `ArrowSchema` / `ArrowArray` (and the stream variant
  `ArrowArrayStream`) in `arrow/c/abi.h` -- frozen, release-callback based,
  `private_data` for producer bookkeeping.
- C++ export/import (verified against apache/arrow `cpp/src/arrow/c/bridge.h`):
  - export: `arrow::ExportType/ExportField/ExportSchema`, `ExportArray`,
    `ExportRecordBatch`, `ExportChunkedArray`, `ExportRecordBatchReader`;
  - import: `arrow::ImportType/ImportField/ImportSchema`, `ImportArray`,
    `ImportRecordBatch`, `ImportChunkedArray`, `ImportRecordBatchReader`.
- Zero-copy rules for the pandas bridge:
  - a `Table` is chunked: export through `TableBatchReader` (batch-wise,
    copy-free) or `ExportRecordBatchReader` (`ArrowArrayStream`); a single
    batch needs `Table::CombineChunksToBatch()`, which COPIES when the table
    has more than one chunk -- document per call site;
  - imported structs are MOVED into the C++ object (`ImportRecordBatch`
    releases the input), so the XIOM-side holder must pass ownership, not
    copy and keep;
  - never mix buffer ownership: exported buffers belong to the Arrow object
    until the consumer calls the release callback.

## 5. What xiom.arrow must expose (declared surface is in its SPEC)

xiom.arrow's current declared surface (`array_create`, `schema_create`,
`record_batch_create`, handle accessors, `Table`/`Schema` structs) is not yet
a bridge to libarrow. For the pandas interop path (`dataframe_from_arrow`,
SPEC Phase 4) the binding lane must add, in xiom.arrow:

1. real `arrow_*` symbol implementations backed by `arrow/c/bridge.h`
   (at minimum `arrow_record_batch_create`, `arrow_array_create`,
   `arrow_schema_create` with real `ArrowArray`/`ArrowSchema` structs, not
   Int stubs);
2. an export/import pair to hand a record batch to/from an Arrow-table owner
   without copying (struct pointers travel as Int addresses, matching the
   pandas ABI convention);
3. a documented ownership handoff: who calls the release callbacks and when.

pandas then implements `dataframe_from_arrow(table)` by importing the struct
pair (or by sharing the underlying Table pointer if xiom.arrow adopts the
pandas handle convention) -- zero copies in both directions.

## 6. Open items to pin at implementation (explicitly NOT resolved here)

1. ACERO IS VERSION-SENSITIVE: `hash_join` / `hash_group_aggregate`
   declarations and their option structs (`HashJoinNodeOptions`,
   `HashAggregateNodeOptions`) must be pinned against the exact installed
   Arrow release at build time. If the installed Arrow lacks the declaration
   used, prefer the bridge-side fallback (section 2 table) over shipping a
   probe that cannot build.
2. The `TableGroupBy` convenience class header path moved between Arrow
   releases; verify in the chosen release's `cpp/src/arrow/compute/` tree
   (its docs list the class; the current main-branch layout has no
   `exec/group_by.h`).
3. `series_apply` callback ABI: the XIOM side passes an opaque function
   pointer today; a concrete signature (recommend `double (*)(double)`) must
   be agreed and mirrored in pandas.xi before implementation; element-type
   coercion policy is part of that decision.
4. OWNERSHIP ADDITIONS (append-only, not in the current 12): the Phase-1 ABI
   has no free functions. The real bridge must add
   `pandas_c_dataframe_free(handle)`, `pandas_c_series_free(handle)` and
   `pandas_c_free(ptr)` (for `series_to_vec` buffers). Landing these also
   updates pandas.xi and the suite's "12 declared" marker in the SAME change.
5. `dataframe_filter` `value` currently arrives as `Int`; Float64 comparison
   values need an ABI addition (e.g. an f64-bit pattern call or a second
   entry point) -- decide with the owner, additive only.
6. Parquet: `parquet/arrow/reader.h` (`parquet::arrow::OpenFile`, then
   `FileReader::ReadTable`) and `parquet/arrow/writer.h`
   (`parquet::arrow::WriteTable`) -- needs the `parquet` Arrow component
   (Thrift/zstd/snappy transitive deps per the Arrow build).

## 7. Real-bridge probe structure (mirrors the xiom-http probe_real_libcurl leg)

`tests/probe_real_arrow.xi` is shipped and type-checked; it is NOT part of
port.ps1. Shape:

- leg 1: raw null contract on the real bridge (`pandas_c_dataframe_new(0,0,0)`
  must return 0);
- leg 2: real CSV round trip through the production wrappers -- XIOM writes a
  small CSV (`xiom.io.write_file`), builds a NUL-terminated path via
  `xiom.ffi.safe_ptr_alloc` + byte writes, calls
  `dataframe_from_csv(path)` (expects a live handle), then
  `dataframe_to_csv(df, out_path)` (expects success);
- fail-fast: without the real bridge the CSV leg reports the
  backend-unavailable error and the probe exits non-zero (fails closed);
- invocation (documented in the file header):
  `xiom --run packages\xiom-pandas\tests\probe_real_arrow.xi --c-source
  packages\xiom-pandas\bridge\xiom_pandas_arrow.cpp --link arrow
  --link-path <arrow-lib-dir>` (add `--link parquet` for the parquet leg).
- evidence model mirrors xiom-http 0.1.4/0.1.5: local run against the real
  library, output pasted into the package notes; CI keeps running only the
  offline suite.
