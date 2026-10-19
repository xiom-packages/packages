# xiom.pandas -- SPEC

**Phase**: 2-4 (Real Arrow-backed bridge) | **Priority**: HIGH
**Status**: **0.2.0** -- section-8 owner decisions implemented on Apache Arrow
C++ 22.0.0 without Acero headers/symbols; offline suite 110/110 x2 on
compiler v0.64.8; real evidence probe green (CSV, group-by, join, apply,
filter, Parquet).
**Depends on**: xiom.ffi (stdlib), xiom.arrow (Apache Arrow C Data Interface,
for the remaining zero-copy interop), Apache Arrow C++ 22.0.0 (real leg only).

## What it wraps
Pandas-style tabular data over Apache Arrow. In Pandas 2.0+, the backend is
Apache Arrow. We wrap Arrow C++ directly (not Python), providing
DataFrame/Series operations with zero Python overhead.

## Dependencies

| What | How | Size |
|------|-----|------|
| Apache Arrow C++ 22.0.0 | System-installed (via xiom.arrow) | ~50MB |
| Arrow Parquet component | Same Arrow build (`parquet.lib`) | transitive |
| C++ compiler | For building the bridge (C++17) | -- |

## Bundling strategy
**System-installed only.** The offline suite links the deterministic stub and
needs no Arrow; the real bridge links the pinned Arrow C++ + Parquet
component.

## Surface status (2026-10-19) -- 0.2.0

Two-leg delivery (mirrors xiom.numpy / xiom.http):

- **Leg 1 (offline, GREEN)**: `bridge/pandas_bridge.c` is a deterministic
  suite-only stub (no external libs, no Arrow) linked through `port.args.json`
  (`--c-source`). The conformance suite is **110/110 PASS x2** on compiler
  **v0.64.8** (`scripts/port.ps1 -Package xiom-pandas -TimeoutSec 300`),
  covering 22 original FFI stub checks plus the additive filter_f64,
  ownership-free and Parquet stub checks; constants, 18 API markers, 16
  contract markers, types, `dtype_name`, and safe-wrapper error paths. The stub
  validates arguments and reports "backend unavailable" on success paths -- it
  never fabricates data.
- **Leg 2 (real, BUILT + PROBE GREEN)**: `bridge/xiom_pandas_arrow.cpp`
  (Arrow C++, C++17, exception-free C ABI) implements the 18 declared symbols
  on the pinned Arrow 22.0.0 (pyarrow 22.0.0 win_amd64 wheel, MSVC 19.44 ABI).
  The bridge is **Acero-free**: a compile against an include tree with
  `arrow/acero` removed succeeds, `llvm-nm -u` shows no Acero reference, and
  the probe links `arrow + arrow_compute + parquet` with no `arrow_acero`.
  `tests/probe_real_arrow.xi` (evidence-only, NOT part of port.ps1) is green
  for the null contract, CSV round trip, group-by, all four join types,
  Float64 `series_apply`, `dataframe_filter_f64`, ownership frees and the
  Parquet round trip.

## Section-8 decision map (owner GO 2026-10-19)

| Decision | Implementation |
|---|---|
| 1. No Acero build requirement | No `arrow/acero` headers/symbols. Group-by: `arrow::compute::Grouper` (`arrow/compute/row/grouper.h`). Join: bridge-side fallback (Grouper ids + `arrow::compute::Take`). |
| 2. TableGroupBy | `arrow/compute/exec/group_by.h` is absent in 22.0.0 -> Acero-free aggregate in the bridge. Output: key column + Int64 `count`, grouper order. |
| 3. series_apply | `double (*)(double)` per element; Float64-only; no coercion; null/non-Float64 fail closed (0). NA/NaN out of scope; NaNs pass through. |
| 4. Ownership additions | `pandas_c_dataframe_free`, `pandas_c_series_free`, `pandas_c_free` (additive); declared in `pandas.xi`; suite extern marker = 18. |
| 5. dataframe_filter_f64 | Additive owner-pinned `pandas_dataframe_filter_f64(df, column, op, bits)`; bits = IEEE-754 binary64 pattern in Int64, decoded with `memcpy`. Int entry unchanged. |
| 6. Parquet | `parquet::arrow::OpenFile` + `FileReader::ReadTable` / `parquet::arrow::WriteTable` from the Arrow 22.0.0 Parquet component. No separate stack. |

## ABI surface (18 symbols)

The 12 original wrappers are byte-identical to 0.1.0 (Phase 1). The additive
six:

| C symbol | Wrapper | Contract |
|---|---|---|
| `pandas_c_dataframe_free` | `dataframe_free` | `requires: df != 0` |
| `pandas_c_series_free` | `series_free` | `requires: series != 0` |
| `pandas_c_free` | `series_buffer_free` | `requires: ptr != 0` |
| `pandas_dataframe_filter_f64` | `dataframe_filter_f64` | `requires: df != 0` |
| `pandas_c_dataframe_from_parquet` | `dataframe_from_parquet` | null path -> typed `Err` |
| `pandas_c_dataframe_to_parquet` | `dataframe_to_parquet` | `requires: df != 0` |

The owner-pinned f64 filter symbol intentionally has no `pandas_c_` prefix;
the wrapper name differs from the symbol, so the language's collision rule is
still satisfied.

## Implementation map (real bridge)

| Symbol | Real implementation |
|---|---|
| `pandas_c_dataframe_new` | schema from `char*[n]` + `int64_t[n]` DTYPE codes; 0-row `arrow::Table` |
| `pandas_c_dataframe_from_csv` | `csv::TableReader::Make` + `Read()` (single-threaded) |
| `pandas_c_dataframe_to_csv` | `csv::WriteCSV` + `FileOutputStream::Close()` |
| `pandas_c_dataframe_get_column` | `Table::GetColumnByName` -> `shared_ptr<ChunkedArray>` handle |
| `pandas_c_dataframe_set_column` | Float64 builder; replace/append field; new Table |
| `pandas_c_dataframe_filter` | compute `CallFunction(equal/...)` + `Filter`; Int value entry unchanged |
| `pandas_dataframe_filter_f64` | binary64 bits -> double via `memcpy`; same compute path |
| `pandas_c_dataframe_groupby` | `Grouper::Consume` + `GetUniques`; bridge-side count; Acero-free |
| `pandas_c_dataframe_join` | `Grouper::Consume`/`Lookup` + `Take`; INNER/LEFT/RIGHT/FULL; `_left`/`_right` suffixes |
| `pandas_c_series_new` | typed builders per DTYPE (int32/int64/float32/float64/utf8/bool) |
| `pandas_c_series_from_vec` | Float64 source, cast per dtype; string returns 0 |
| `pandas_c_series_to_vec` | bridge-owned `malloc` buffer (numeric/bool); count through `i64*`; string/binary 0 |
| `pandas_c_series_apply` | `double (*)(double)`, Float64-only, per element; nulls fail closed |
| `pandas_c_dataframe_free` / `_series_free` / `pandas_c_free` | `delete` / `std::free` |
| `pandas_c_dataframe_from_parquet` | `parquet::arrow::OpenFile` + `ReadTable` |
| `pandas_c_dataframe_to_parquet` | `parquet::arrow::WriteTable` |

## Build / probe recipe (verified)

```powershell
$arrow = "E:\repos\arrow-bin\pyarrow-22.0.0"
$env:CPLUS_INCLUDE_PATH = "<scratch-include-without-arrow/acero>"
$env:PATH = "$arrow\pyarrow;$arrow\pyarrow.libs;$env:PATH"
xiom --run packages\xiom-pandas\tests\probe_real_arrow.xi `
    --cxx-standard 17 `
    --c-source packages\xiom-pandas\bridge\xiom_pandas_arrow.cpp `
    --c-source packages\xiom-pandas\tests\probe_real_arrow_callback.c `
    --link arrow --link arrow_compute --link parquet `
    --link-path "$arrow\pyarrow"
```

No `--link arrow_acero`. Without the Parquet headers the bridge still compiles
and the Parquet entry points report the backend unavailable; the probe prints
`[SKIP]` for that leg. The offline suite is the CI gate and never links Arrow.

## API surface (0.2.0 additions)

```xiom
pub fn dataframe_free(df: DataFrame) -> Result[Int, Str]
pub fn series_free(series: Series) -> Result[Int, Str]
pub fn series_buffer_free(ptr: Int) -> Result[Int, Str]
pub fn dataframe_filter_f64(df: DataFrame, col_name: Int, op: Int, bits: Int) -> Result[DataFrame, Str]
pub fn dataframe_from_parquet(path: Int) -> Result[DataFrame, Str]
pub fn dataframe_to_parquet(df: DataFrame, path: Int) -> Result[Int, Str]
```

The existing 12 wrappers (`dataframe_new` ... `series_apply`) are unchanged.

## Contract coverage target
- 16 `requires` contracts across 16 public functions (0.2.0).
- `dataframe_from_parquet` has no `requires`: a null path returns a typed `Err`
  rather than trapping.
- Column existence and shape compatibility remain runtime-checked through the
  bridge (0/1/null-handle contract), not static contracts.

## Phased roadmap

| Phase | What | Status |
|---|---|---|
| 1 | DataFrame create, column access, basic ops | DONE (0.1.0) |
| 2 | Real bridge, filter, group_by, aggregation | Real bridge DONE (0.2.0); shape/slice/row helpers remain |
| 3 | Joins, I/O (CSV, Parquet), sorting | Joins + CSV + Parquet DONE (0.2.0); sort/drop/fillna remain |
| 4 | Time series, rolling windows, multi-index | Zero-copy arrow interop + time series remain |

## 0.2.0 Implementation Summary

| Artifact | Path | Lines |
|---|---|---|
| Module | `pandas.xi` | 462 |
| Tests | `tests/test_conformance.xi` | 781 |
| Stub bridge | `bridge/pandas_bridge.c` | 200 |
| REAL Arrow bridge | `bridge/xiom_pandas_arrow.cpp` | 1081 |
| Real-backend requirements | `bridge/REAL-BACKEND-REQUIREMENTS.md` | see file |
| Real-runtime probe | `tests/probe_real_arrow.xi` | 508 |
| Probe callback | `tests/probe_real_arrow_callback.c` | 14 |
| Provenance | `PROVENANCE.md` | see file |
| Roadmap | `ROADMAP.md` | 53 |

### What 0.2.0 delivers
- **18 declared C symbols**: the 12 Phase-1 symbols byte-identical plus the
  three ownership frees, the f64 filter entry and the two Parquet entries.
- **Acero-free real backend**: Grouper group-by, Grouper+Take join, no
  `arrow/acero` dependency.
- **Float64 apply/filter model**: `double (*)(double)`; binary64 filter bits.
- **Parquet I/O** through the Arrow Parquet component.
- **110 conformance tests** (stub leg) + a real evidence probe covering all
  section-8 decisions.
- **Known limitation**: `dataframe_groupby` returns an opaque handle; the
  section-8 ownership set does not include a group-by free/consumer, so those
  remain future additive work.
