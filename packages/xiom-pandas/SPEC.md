# xiom.pandas -- SPEC

**Phase**: 1 (Core Foundation) + Phase 2 partial (pure-XIOM DataFrame ops) | **Priority**: HIGH
**Status**: Phase 1 implemented -- `pandas.xi` + tests + ROADMAP; Phase 2
pinned subset implemented in pure XIOM (109/109 x2, v0.64.6, 2026-10-17);
REAL Arrow-backed bridge source prepared and probe-green (Arrow C++ 22.0.0,
v0.64.6, 2026-10-17)
**Depends on**: xiom.ffi (stdlib), xiom.arrow (Apache Arrow -- Pandas 2.0+ backend)

## What it wraps
Pandas -- data analysis library. In Pandas 2.0+, the backend is Apache Arrow.
We wrap Arrow C++ directly (not Python), providing DataFrame/Series operations
with zero Python overhead. This is the approach Polars and DuckDB use internally.

## Dependencies

| What | How | Size |
|------|-----|------|
| Apache Arrow C++ | System-installed (via xiom.arrow) | ~50MB |
| C++ compiler | For building bridge | -- |

## Bundling strategy
**System-installed only.** Depends on Arrow which is system-installed.

## Surface status (2026-10-16) -- stub vs real legs

Two-leg delivery (mirrors xiom.numpy Phase 1 and xiom.http's offline suite +
real probe):

- **Leg 1 (offline, GREEN)**: `bridge/pandas_bridge.c` is a deterministic
  suite-only stub (no external libs, no Arrow) linked through `port.args.json`
  (`--c-source`). The conformance suite is **80/80 PASS x2** on compiler
  v0.64.5 (`scripts/port.ps1 -Package xiom-pandas -TimeoutSec 180`), covering
  22 FFI stub checks, 30 constant checks, 12 API markers, 11 contract
  markers, 3 type checks, 4 dtype_name checks and 8 safe-wrapper error-path
  checks. The stub validates arguments (0-in -> 0-out plus a nonzero
  `dataframe_to_csv` error rc) and reports "backend unavailable" on success
  paths -- it never fabricates data.
- **Leg 2 (real, SOURCE BUILT + PROBE GREEN, 2026-10-17)**:
  `bridge/xiom_pandas_arrow.cpp` (Arrow C++, C++17, exception-free C ABI)
  now implements all 12 declared `pandas_c_*` symbols. Pinned against Apache
  Arrow C++ **22.0.0** (tag `apache-arrow-22.0.0`, commit `5aeb5f2`; pyarrow
  22.0.0 win_amd64 wheel, sha256 `44729980...`, MSVC 19.44 ABI). The ABI gate
  passed locally: the source builds with clang 22.1.8 (`-std=c++17`,
  `x86_64-pc-windows-msvc`) against the wheel's headers + import libraries,
  and `tests/probe_real_arrow.xi` returns live handles for the CSV round trip.
  A separate local C-ABI exercise covered all 12 symbols (table new/set/get/
  filter/groupby/join, series new/from_vec/apply/to_vec, CSV both ways) and
  was deleted after the run; evidence is recorded in `PROVENANCE.md`/SPEC.
  The shipped probe remains evidence-only (NOT part of port.ps1) and fails
  closed without the real bridge.
- **T001 reconciliation (2026-10-16)**: the suite's duplicated extern block
  is gone. Compiler v0.64.5 resolves the canonical declarations through
  `use xiom.pandas;` (verified with --emit-ir probes: raw extern calls lower
  to the `pandas_c_*` symbols; canonical constants and `dtype_name` resolve).
  No check was weakened. Section 15 keeps local safe-wrapper copies BY DESIGN
  (the real wrappers' `requires` contracts would trap on the violating
  arguments the error-path checks use). One check was added (safe
  get_column null name) to reach the 80 the suite's section comments promised.
- **Symbol prefix (language rule 10)**: the extern names ARE the C symbols
  and carry a `pandas_c_` prefix (the `numpy_c_*` convention). A wrapper must
  never be named after its C symbol -- the collision is silently dropped by
  the compiler -- so the public API names (`dataframe_new`, ...) stayed and
  the C symbols moved. `pandas.xi` also gained the semicolons its `pub type`
  aliases require on v0.64.5; the module now type-checks (`--emit-ir`
  exit 0), which it did not before this pass.

## Phase 2 (partial, pure-XIOM, 2026-10-17)

Phase 2 is implemented with **no FFI on any new path**. The design mirrors
`xiom.numpy` Phase-2a: `DataFrame`/`Series` remain opaque `Int` handles;
handle `0` is invalid and a live handle is `1 + slot index`. Slots are
append-only and never reused, so a stale handle cannot alias a later
allocation. The Phase-1 C-bridge seam and its offline stub are untouched.

Storage model (the model SPEC itself pins in the API sketch):

- a DataFrame is named Float64 columns (`Map[Str, Vec[Float64]]` in the SPEC
  sketch; the executable constructor takes parallel `Vec[Str]` /
  `Vec[Vec[Float64]]` because the module already owns `dataframe_new` with the
  Phase-1 FFI signature);
- values live in one flat `Vec[Float64]` arena plus per-column
  name/dtype/base/length/live arenas;
- frames store a flat list of column-slot indices, so no nested `Vec` is
  written at runtime;
- Series handles are views over the same value arena (no data copy on
  `column`; `iloc` copies the selected row).

### Implemented surface (pinned)

| Function | Semantics |
|---|---|
| `dataframe_from_columns(names, col_values)` | constructor; equal lengths, >= 1 column, equal row counts, unique names, else typed `Err` |
| `dataframe_shape(df)` / `shape(df)` | `(rows, cols)`; invalid/dead handle -> `(0, 0)` |
| `dataframe_columns(df)` / `columns(df)` | names in storage order |
| `dataframe_dtypes(df)` / `dtypes(df)` | per-column dtype tags (Float64 in this model) |
| `column(df, name)` | exact, case-sensitive column lookup -> Series view; missing -> `Err` |
| `dataframe_iloc(df, row)` / `iloc(df, row)` | 0-based row values in column order; negative / out-of-range -> `Err` |
| `dataframe_loc_range(df, start, end)` / `loc_range(...)` | inclusive row slice `[start, end]` (pandas `.loc` endpoint semantics); strict bounds, else `Err` |
| `dataframe_head(df, n)` | first `n` rows; clamps; `n == 0` -> 0-row frame; `n < 0` -> `Err` |
| `dataframe_tail(df, n)` | last `n` rows; same clamp/zero/negative rules |
| `series_len`, `series_dtype`, `series_values` | pure-XIOM Series inspection used by the conformance suite |

All property/selection/slicing functions carry `requires: df != 0`.

### Deliberately skipped (unpinned -- no guessed semantics)

- `rename` / `reorder_columns`: absent from SPEC and ROADMAP.
- `concat`: absent from SPEC and ROADMAP.
- `merge` / joins: the SPEC sketch mentions `merge`, but the phased table
  places joins after Phase 2 and no key/collision/suffix/duplicate-key
  semantics are pinned; `dataframe_join` remains the Phase-1 FFI seam only.
- Mixed-dtype storage: SPEC's pinned constructor is Float64-only, so
  `dtypes` reports `DTYPE_FLOAT64` for every column rather than inventing a
  coercion policy.
- Negative `iloc`/`head`/`tail` indexing and non-clamping `loc_range`
  out-of-bounds behavior: not pinned; rejected with `Err`.

### Test evidence

`tests/test_conformance.xi` section 16 adds 29 hand-computed checks on a
fixed `a = [10,20,30]`, `b = [1.5,2.5,3.5]` fixture (shape/order, dtype
tags, column view, iloc, inclusive `loc_range`, head/tail clamps and zeros,
constructor error arms, empty frame). Suite: **109/109 PASS x2** on compiler
v0.64.6 (2026-10-17).

## Real bridge (prepared, 2026-10-17) -- pin, ABI gate, ownership

`bridge/xiom_pandas_arrow.cpp` is the production C++17 realization of the 12
declared symbols. It is **not** in `port.args.json` (the offline suite keeps
`bridge/pandas_bridge.c`); it is linked only by the evidence probe or a
consumer build.

### Pinned release / ABI

| Field | Value |
|-------|-------|
| Upstream | Apache Arrow 22.0.0 -- tag `apache-arrow-22.0.0`, commit `5aeb5f217f1ba39c428c9b481f393bd37097f69e` (`E:\repos\arrow`, sparse clone; Apache-2.0) |
| Runtime/header set | pyarrow 22.0.0 win_amd64 wheel, sha256 `44729980B6C50A5F2BFCC2668D36C569CE17F8B17BCCAF470C4313DCBBF13C9D`; extracted to `E:\repos\arrow-bin\pyarrow-22.0.0` |
| Arrow build | MSVC 19.44.35217.0, `ARROW_PACKAGE_KIND "python-wheel-windows"`; C++17-compatible public headers |
| Bridge toolchain | clang 22.1.8 (XIOM v0.64.6), `x86_64-pc-windows-msvc`, `-std=c++17`, lld-link |
| ACERO pin | Node names verified in Arrow 22: `"table_source"`, `"aggregate"`, `"hashjoin"` (NOT the docs' `hash_group_aggregate`/`hash_join`); `arrow::compute::Initialize()` is called once because compute kernels live in `arrow_compute.dll` |

**ABI gate: PASSED locally.** Both bridges built against the wheel's headers
and import libraries; the probe linked and ran (CSV round trip + null
contract). An additional local C-ABI probe exercised every one of the 12
symbols (new/set/get/filter/groupby/join, series new/from_vec/apply/to_vec,
CSV both ways, additive free functions) -- all green; the probe was deleted
after the run. No MSVC/MinGW mix and no fabricated build.

### Implementation map

| Symbol | Real implementation |
|---|---|
| `pandas_c_dataframe_new` | schema from `char*[n]` + `int64_t[n]` DTYPE codes; 0-row `arrow::Table` via `MakeArrayOfNull` + `Table::Make` |
| `pandas_c_dataframe_from_csv` | `csv::TableReader::Make(io::ReadableFile::Open(path), ReadOptions(use_threads=false), ParseOptions, ConvertOptions)` -> `Read()` |
| `pandas_c_dataframe_to_csv` | `csv::WriteCSV(*table, WriteOptions::Defaults(), io::FileOutputStream)` |
| `pandas_c_dataframe_get_column` | `Table::GetColumnByName` -> `shared_ptr<ChunkedArray>` handle (zero-copy view of chunks) |
| `pandas_c_dataframe_set_column` | Float64 builder from `double[len]`; replace or append field; new `Table` via `Table::Make`; input handle unchanged |
| `pandas_c_dataframe_filter` | `compute::CallFunction(equal/not_equal/less/less_equal/greater/greater_equal)` + per-column `compute::Filter`; `value` is i64 (float columns widen; bool uses `!= 0`); string columns unsupported pending 6.5 |
| `pandas_c_dataframe_groupby` | Acero `Declaration("aggregate", AggregateNodeOptions({hash_count_all}, {key}))` over a `table_source`; handle owns input + grouped `Table` + key |
| `pandas_c_dataframe_join` | Acero `Declaration("hashjoin", HashJoinNodeOptions(...))` with two `table_source` inputs; JOIN_* 0..3 -> INNER/LEFT/RIGHT/FULL; suffix `_left`/`_right` avoids collisions |
| `pandas_c_series_new` | typed builders per DTYPE: int32/int64/float32/float64 (native arrays), utf8 (`char*[n]`, NULL -> null), bool (`uint8_t[n]`) |
| `pandas_c_series_from_vec` | declared Float64 source; cast per dtype; int32/int64/float32/float64/bool; string returns 0 |
| `pandas_c_series_to_vec` | bridge-owned `malloc` buffer (int32/int64/float32/float64/bool); element count through `i64*`; string/binary return 0 pending 6.4/6.5 |
| `pandas_c_series_apply` | the recommended `double (*)(double)` callback, applied per element to a Float64 result; nulls preserved; unsupported types return 0 pending 6.3 |

### Ownership + additive ABI decisions (owner-pending)

- Handles are bridge-owned C++ objects (Table/ChunkedArray/group-by); `df`/`series`
  handles stay valid until freed. `dataframe_set_column`, `filter`, `groupby`,
  and `join` return NEW handles; inputs are unchanged.
- The real source exports `pandas_c_dataframe_free`, `pandas_c_series_free`,
  and `pandas_c_free` (for `series_to_vec` buffers) per section 6.4, but they
  are **not declared in `pandas.xi`** and the suite's "12 declared" marker is
  untouched: that is an additive ABI decision for the owner.
- `series_apply`'s concrete signature (`double (*)(double)`) and the
  element-coercion policy are owner-pending (6.3); the implementation follows
  the recommendation, nothing is declared.
- `dataframe_filter`'s Float64 value ABI (bit-pattern/second entry point) is
  owner-pending (6.5); only the declared i64 value is used.
- Parquet (6.6) is NOT implemented; no parquet symbol/entry point was added.
- The declared 12-symbol ABI and `pandas.xi` are unchanged.

### Build / probe recipe (verified)

```powershell
$arrow = "E:\repos\arrow-bin\pyarrow-22.0.0"
$env:CPLUS_INCLUDE_PATH = "$arrow\pyarrow\include"
$env:PATH = "$arrow\pyarrow;$arrow\pyarrow.libs;$env:PATH"
xiom --run packages\xiom-pandas\tests\probe_real_arrow.xi `
    --cxx-standard 17 `
    --c-source <repo>\packages\xiom-pandas\bridge\xiom_pandas_arrow.cpp `
    --link arrow --link arrow_compute --link arrow_acero `
    --link-path "$arrow\pyarrow"
```

Add `--link parquet` only when the owner-pending parquet leg is implemented.

## API surface

```xiom
module xiom.pandas

pub type DataFrame = Int  // wraps Arrow Table
pub type Series    = Int  // wraps Arrow Array

// DataFrame creation
pub fn dataframe_new(columns: Map[Str, Vec[Float64]]) -> Result[DataFrame, Str]
pub fn dataframe_from_arrow(table: &ArrowTable) -> DataFrame  // zero-copy
pub fn dataframe_read_csv(path: Str) -> Result[DataFrame, Str]
pub fn dataframe_read_parquet(path: Str) -> Result[DataFrame, Str]
pub fn dataframe_free(df: DataFrame)

// Properties
pub fn shape(df: &DataFrame) -> (Int, Int)
pub fn columns(df: &DataFrame) -> Vec[Str]
pub fn dtypes(df: &DataFrame) -> Vec[DType]

// Selection
pub fn column(df: &DataFrame, name: Str) -> Result[Series, Str]
pub fn iloc(df: &DataFrame, row: Int) -> Result[Series, Str]
pub fn loc_range(df: &DataFrame, start: Int, end: Int) -> Result[DataFrame, Str]

// Filtering
pub fn filter(df: &DataFrame, predicate: fn(&Series) -> Bool) -> Result[DataFrame, Str]
pub fn filter_column(df: &DataFrame, col: Str, op: CompareOp, val: Float64) -> Result[DataFrame, Str]

// Aggregation
pub fn group_by(df: &DataFrame, by: Str) -> GroupBy
pub fn groupby_sum(gb: &GroupBy, col: Str) -> Result[DataFrame, Str]
pub fn groupby_mean(gb: &GroupBy, col: Str) -> Result[DataFrame, Str]

// Joins
pub fn merge(left: &DataFrame, right: &DataFrame, on: Str, how: JoinType) -> Result[DataFrame, Str]

// Transformation
pub fn drop_columns(df: &DataFrame, cols: Vec[Str]) -> Result[DataFrame, Str]
pub fn sort(df: &DataFrame, by: Str, ascending: Bool) -> Result[DataFrame, Str]

// I/O
pub fn to_csv(df: &DataFrame, path: Str) -> Result[Unit, Str]
pub fn to_parquet(df: &DataFrame, path: Str) -> Result[Unit, Str]
```

### Implemented Phase-2 surface (pure-XIOM, no FFI)

The sketch above is the long-range API. The subset implemented today (the
pinned Phase-2 items) is:

```xiom
// Construction (SPEC's Map[Str, Vec[Float64]] model, as parallel vectors)
pub fn dataframe_from_columns(names: &Vec[Str], col_values: &Vec[Vec[Float64]]) -> Result[DataFrame, Str]

// Properties (ROADMAP names + SPEC aliases)
pub fn dataframe_shape(df: &DataFrame) -> (Int, Int)
pub fn shape(df: &DataFrame) -> (Int, Int)
pub fn dataframe_columns(df: &DataFrame) -> Vec[Str]
pub fn columns(df: &DataFrame) -> Vec[Str]
pub fn dataframe_dtypes(df: &DataFrame) -> Vec[Dtype]
pub fn dtypes(df: &DataFrame) -> Vec[Dtype]

// Selection / slicing
pub fn column(df: &DataFrame, name: Str) -> Result[Series, Str]
pub fn dataframe_iloc(df: &DataFrame, row: Int) -> Result[Series, Str]
pub fn iloc(df: &DataFrame, row: Int) -> Result[Series, Str]
pub fn dataframe_loc_range(df: &DataFrame, start: Int, end: Int) -> Result[DataFrame, Str]
pub fn loc_range(df: &DataFrame, start: Int, end: Int) -> Result[DataFrame, Str]
pub fn dataframe_head(df: &DataFrame, n: Int) -> Result[DataFrame, Str]
pub fn dataframe_tail(df: &DataFrame, n: Int) -> Result[DataFrame, Str]

// Series inspection (pure-XIOM registry)
pub fn series_len(s: &Series) -> Int
pub fn series_dtype(s: &Series) -> Dtype
pub fn series_values(s: &Series) -> Result[Vec[Float64], Str]
```

## Contract coverage target
- Column existence: `requires: col_name in columns(df)`
- Shape compatibility: `requires: left.len() > 0 && right.len() > 0`
- File paths: `requires: io.file_exists(path)` for read
- Type safety: DType enum for int/float/string/bool

## Phased roadmap

| Phase | What | Effort |
|-------|------|--------|
| 1 | DataFrame create, column access, basic ops | Weekend |
| 2 | Filter, group_by, aggregation | Weekend |
| 3 | Joins, I/O (CSV, Parquet), sorting | Weekend |
| 4 | Time series, rolling windows, multi-index | Week |

## Phase 1 Implementation Summary

| Artifact | Path | Lines |
|---|---|---|
| Module | `pandas.xi` | 781 |
| Tests | `tests/test_conformance.xi` | 1042 |
| Stub bridge | `bridge/pandas_bridge.c` | 174 |
| REAL Arrow bridge | `bridge/xiom_pandas_arrow.cpp` | 821 |
| Real-backend requirements | `bridge/REAL-BACKEND-REQUIREMENTS.md` | 152 |
| Real-runtime probe | `tests/probe_real_arrow.xi` | 133 |
| Roadmap | `ROADMAP.md` | 46 |
| SPEC | `SPEC.md` (this file) | 142 |

### What Phase 1 delivers
- **3 opaque types**: `DataFrame = Int`, `Series = Int`, `Dtype = Int`
- **6 dtype constants**: `DTYPE_INT32`(0) through `DTYPE_BOOL`(5)
- **6 compare op constants**: `CMP_EQ`(0) through `CMP_GE`(5)
- **4 join type constants**: `JOIN_INNER`(0) through `JOIN_OUTER`(3)
- **12 extern "C" functions** (C symbols, `pandas_c_` prefix): pandas_c_dataframe_new, pandas_c_dataframe_from_csv, pandas_c_dataframe_to_csv, pandas_c_dataframe_get_column, pandas_c_dataframe_set_column, pandas_c_dataframe_filter, pandas_c_dataframe_groupby, pandas_c_dataframe_join, pandas_c_series_new, pandas_c_series_from_vec, pandas_c_series_to_vec, pandas_c_series_apply
- **12 safe wrappers**: all extern functions wrapped with `requires` contracts and null checks
- **2 utilities**: `dtype_name(dtype)`, `version()`
- **109 conformance tests** on the current `xiom.test` API: 16 sections covering constants, FFI stub behavior, API presence, contracts, types, dtype_name, safe wrapper error paths, and the Phase-2 pure-XIOM surface (29 checks)
- **27 contracts**: the 11 Phase-1 contracts plus 16 Phase-2 contracts (`dataframe_shape`, `shape`, `dataframe_columns`, `columns`, `dataframe_dtypes`, `dtypes`, `column`, `dataframe_iloc`, `iloc`, `dataframe_loc_range`, `loc_range`, `dataframe_head`, `dataframe_tail`, `series_len`, `series_dtype`, `series_values`), all `requires: handle != 0`
- **Offline stub bridge**: `bridge/pandas_bridge.c` + `port.args.json`
- **Real-backend requirements**: `bridge/REAL-BACKEND-REQUIREMENTS.md` (for the bindings/xiom.arrow lanes)
