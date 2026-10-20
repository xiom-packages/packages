# xiom.pandas -- SPEC

**Phase**: 1 (Core Foundation) + Phase 2 partial + Phase 3 pinned subset
(pure-XIOM DataFrame ops) + section-8 additive ABI (0.2.1) | **Priority**: HIGH
**Status**: Phase 1 implemented -- `pandas.xi` + tests + ROADMAP; Phase 2
pinned subset implemented in pure XIOM (109/109 x2, v0.64.6, 2026-10-17);
Phase 3 pinned subset -- sort, drop_columns, group_by sum/mean/count --
implemented in pure XIOM (132/132 x2, v0.64.8, 2026-10-19); section-8
additive surface -- ownership frees, `dataframe_filter_f64`, f64 apply,
Parquet -- merged onto the live 0.2.0 artifact (**164/164 x2**, v0.64.8,
2026-10-20); REAL Arrow-backed bridge implements the 18-symbol ABI on
Apache Arrow C++ 22.0.0 with no Acero headers or symbols
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

## Surface status (2026-10-20) -- stub vs real legs

Two-leg delivery (mirrors xiom.numpy Phase 1 and xiom.http's offline suite +
real probe):

- **Leg 1 (offline, GREEN)**: `bridge/pandas_bridge.c` is a deterministic
  suite-only stub (no external libs, no Arrow) linked through `port.args.json`
  (`--c-source`). The conformance suite is **164/164 PASS x2** on compiler
  v0.64.8 (`scripts/port.ps1 -Package xiom-pandas -TimeoutSec 300`): 17
  sections of Phase-1/2/3 checks plus sections 18-24 for the additive
  section-8 surface (filter_f64, frees, Parquet, apply parity, API/contract/
  safe-wrapper markers). The stub validates arguments (0-in -> 0-out plus a
  nonzero `dataframe_to_csv` error rc) and reports "backend unavailable" on
  success paths -- it never fabricates data.
- **Leg 2 (real, BUILT + PROBE GREEN, 2026-10-20)**:
  `bridge/xiom_pandas_arrow.cpp` (Arrow C++, C++17, exception-free C ABI)
  implements all 18 declared symbols (12 original + 6 additive). Pinned
  against Apache Arrow C++ **22.0.0** (tag `apache-arrow-22.0.0`, commit
  `5aeb5f2`; pyarrow 22.0.0 win_amd64 wheel, sha256 `44729980...`, MSVC
  19.44 ABI) **without Acero headers or symbols**: group-by uses
  `arrow::compute::Grouper`, join uses Grouper ids + `arrow::compute::Take`,
  `series_apply` is `double (*)(double)` Float64-only, and Parquet uses
  `parquet::arrow::OpenFile`/`ReadTable`/`WriteTable`. The evidence probe
  covers the null contract, CSV, group-by, all 4 join types, apply,
  `filter_f64`, ownership frees and Parquet (SKIP-safe). It remains
  evidence-only (NOT part of port.ps1) and fails closed without the real
  bridge. Build evidence and the Acero-free proof are in `PROVENANCE.md`.
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

## Phase 3 (pinned subset, pure-XIOM, 2026-10-19)

Phase 3 is implemented on the same append-only pure-XIOM registry as Phase 2
(no FFI, no real Arrow backend required for these paths). Only the items the
documents pin are implemented; every semantic choice below is written down so
it is a contract rather than an accident.

### Implemented surface (pinned)

| Function | Semantics |
|---|---|
| `group_by(df, by) -> GroupBy` | live `GroupBy` handle over `df` and the global column slot of `by`; invalid/dead frame or missing column -> `0`. Requires `df != 0` |
| `groupby_sum(gb, col)` | one row per distinct Float64 key of `by`, ascending; columns `[by, col]`; values are sums of `col` |
| `groupby_mean(gb, col)` | same layout; arithmetic mean `sum / count` in Float64 |
| `groupby_count(gb, col)` | same layout; group row count as Float64 (the Float64 model has no NA, so every value counts) |
| `dataframe_sort(df, by, ascending)` / `sort(...)` | new frame; rows ordered by `by`, ascending or descending; original columns preserved |
| `dataframe_drop_columns(df, cols)` / `drop_columns(...)` | new frame without the named columns; remaining storage order preserved |

All new functions carry `requires: handle != 0`. Tie order for `sort`,
group-key equality (exact `Float64 ==`), and the absence of NaN keys are
explicitly documented as unpinned; tests avoid asserting them.

### Deliberately skipped (unpinned -- no guessed semantics)

- `dataframe_fillna`: SPEC/ROADMAP pin no NA/NaN representation and no fill
  strategy in the Float64 model. **Not implemented.**
- Sort stability among equal keys: not pinned. The implementation happens to
  be a stable insertion sort, but stability is not part of the contract and is
  not tested.
- NA grouping/drop/fill policies: there is no NA representation to group,
  drop, or fill; NaN is not treated as a supported key.
- Aggregating the grouping column itself returns `Err` (it would duplicate the
  output column name); dropping every column returns `Err` (the constructor
  requires at least one column); a missing name in `drop_columns` returns
  `Err`. These are fail-closed choices consistent with the Phase-2 registry.

### Test evidence

`tests/test_conformance.xi` section 17 adds 23 hand-computed checks:
`sort` ascending/descending/alias/empty/missing-column; `drop_columns`
normal/alias/missing/all/none; `group_by` handle and missing-key handle;
`groupby_sum` `[9, 30]`, `groupby_mean` `[3, 15]`, `groupby_count` `[3, 2]`;
missing/dead-handle/grouping-column error paths; empty-frame aggregation; and
the new contract markers. Suite: **132/132 PASS x2** on compiler v0.64.8
(2026-10-19).

## Real bridge (implemented, 2026-10-20) -- pin, ABI gate, ownership

`bridge/xiom_pandas_arrow.cpp` is the production C++17 realization of the 18
declared symbols (12 original + 6 additive). It is **not** in
`port.args.json` (the offline suite keeps `bridge/pandas_bridge.c`); it is
linked only by the evidence probe or a consumer build.

### Pinned release / ABI

| Field | Value |
|-------|-------|
| Upstream | Apache Arrow 22.0.0 -- tag `apache-arrow-22.0.0`, commit `5aeb5f217f1ba39c428c9b481f393bd37097f69e` (`E:\repos\arrow`, sparse clone; Apache-2.0) |
| Runtime/header set | pyarrow 22.0.0 win_amd64 wheel, sha256 `44729980B6C50A5F2BFCC2668D36C569CE17F8B17BCCAF470C4313DCBBF13C9D`; extracted to `E:\repos\arrow-bin\pyarrow-22.0.0` |
| Arrow build | MSVC 19.44.35217.0, `ARROW_PACKAGE_KIND "python-wheel-windows"`; C++17-compatible public headers |
| Bridge toolchain | clang 22.1.8 (XIOM v0.64.6), `x86_64-pc-windows-msvc`, `-std=c++17`, lld-link |
| Acero | **Not used.** No `arrow/acero` include or symbol; `arrow::compute::Initialize()` is still called once because compute kernels live in `arrow_compute.dll` |
| Link shape | `arrow`, `arrow_compute`, `parquet` only (no `arrow_acero`) |

**ABI gate: PASSED locally.** The bridge builds against the wheel's headers
and import libraries; the probe linked and ran (null contract, CSV, group-by,
all 4 joins, Float64 apply, `filter_f64`, frees, Parquet round trip). An
additional compile gate removed `arrow/acero` from the include tree and
confirmed the build and undefined-symbol scan have no Acero reference. No
MSVC/MinGW mix and no fabricated build. See `PROVENANCE.md`.

### Implementation map

| Symbol | Real implementation |
|---|---|
| `pandas_c_dataframe_new` | schema from `char*[n]` + `int64_t[n]` DTYPE codes; 0-row `arrow::Table` via `MakeArrayOfNull` + `Table::Make` |
| `pandas_c_dataframe_from_csv` | `csv::TableReader::Make(io::ReadableFile::Open(path), ReadOptions(use_threads=false), ParseOptions, ConvertOptions)` -> `Read()` |
| `pandas_c_dataframe_to_csv` | `csv::WriteCSV(*table, WriteOptions::Defaults(), io::FileOutputStream)` |
| `pandas_c_dataframe_get_column` | `Table::GetColumnByName` -> `shared_ptr<ChunkedArray>` handle (zero-copy view of chunks) |
| `pandas_c_dataframe_set_column` | Float64 builder from `double[len]`; replace or append field; new `Table` via `Table::Make`; input handle unchanged |
| `pandas_c_dataframe_filter` | `compute::CallFunction(equal/not_equal/less/less_equal/greater/greater_equal)` + per-column `compute::Filter`; `value` is i64 (float columns widen; bool uses `!= 0`); the existing Int entry is unchanged |
| `pandas_dataframe_filter_f64` | Additive section-8 entry: `bits` is the binary64 bit pattern in an Int64, decoded with `memcpy` and compared without a pointer cast |
| `pandas_c_dataframe_groupby` | Acero-free: `arrow::compute::Grouper` over the key column; the bridge aggregates counts into a key + Int64 `count` table; handle owns the input Table and the grouped Table |
| `pandas_c_dataframe_join` | Acero-free fallback: Grouper key ids on both sides + `arrow::compute::Take` gather for JOIN_* 0..3 -> INNER/LEFT/RIGHT/FULL; suffix `_left`/`_right` avoids collisions |
| `pandas_c_dataframe_from_parquet` | `parquet::arrow::OpenFile` + `FileReader::ReadTable` (Arrow 22.0.0 Parquet component; SKIP-safe stub when the headers are absent) |
| `pandas_c_dataframe_to_parquet` | `parquet::arrow::WriteTable` (same component; SKIP-safe stub when the headers are absent) |
| `pandas_c_series_new` | typed builders per DTYPE: int32/int64/float32/float64 (native arrays), utf8 (`char*[n]`, NULL -> null), bool (`uint8_t[n]`) |
| `pandas_c_series_from_vec` | declared Float64 source; cast per dtype; int32/int64/float32/float64/bool; string returns 0 |
| `pandas_c_series_to_vec` | bridge-owned `malloc` buffer (int32/int64/float32/float64/bool); element count through `i64*`; string/binary return 0 pending 6.4/6.5 |
| `pandas_c_series_apply` | `double (*)(double)`, applied per element to a Float64 result; Float64 only; non-Float64 series and null elements return 0; NaN passes through |
| `pandas_c_dataframe_free` / `pandas_c_series_free` / `pandas_c_free` | Additive ownership: release a bridge-owned handle (or a `series_to_vec` buffer) and report 1 on success, 0 for null/dead input |

### Ownership + additive ABI decisions (owner GO, landed in 0.2.1)

- Handles are bridge-owned C++ objects (Table/ChunkedArray/group-by); `df`/`series`
  handles stay valid until freed. `dataframe_set_column`, `filter`, `groupby`,
  and `join` return NEW handles; inputs are unchanged.
- The 12 original wrappers are byte-identical and their symbols are unchanged.
  The real source now also exports `pandas_c_dataframe_free`,
  `pandas_c_series_free`, `pandas_c_free` (for `series_to_vec` buffers),
  `pandas_dataframe_filter_f64`, `pandas_c_dataframe_from_parquet` and
  `pandas_c_dataframe_to_parquet`; all six are declared in `pandas.xi` and
  pinned by the suite (18-symbol marker).
- `series_apply` uses the owner-pinned `double (*)(double)` ABI, Float64 only
  (section-8 decision 3); no element coercion and no NA channel.
- `dataframe_filter_f64` carries the comparison value as IEEE-754 f64 bits in
  an Int64 (section-8 decision 5); the Int entry is unchanged.
- Parquet uses the Arrow 22.0.0 Parquet component (section-8 decision 6). When
  the headers are absent (`XIOM_PANDAS_HAVE_PARQUET == 0`), the two entry
  points compile as backend-unavailable stubs and the probe reports `[SKIP]`.
- GroupBy handles remain opaque; the section-8 ownership set is exactly the
  three frees above (no group-by consumer/free yet).

### Build / probe recipe (verified)

```powershell
$arrow = "E:\repos\arrow-bin\pyarrow-22.0.0"
$env:CPLUS_INCLUDE_PATH = "$arrow\pyarrow\include"
$env:PATH = "$arrow\pyarrow;$arrow\pyarrow.libs;$env:PATH"
xiom --run packages\xiom-pandas\tests\probe_real_arrow.xi `
    --cxx-standard 17 `
    --c-source <repo>\packages\xiom-pandas\bridge\xiom_pandas_arrow.cpp `
    --c-source <repo>\packages\xiom-pandas\tests\probe_real_arrow_callback.c `
    --link arrow --link arrow_compute --link parquet `
    --link-path "$arrow\pyarrow"
```

No `--link arrow_acero`. The Parquet leg prints `[SKIP]` (not `[FAIL]`) when
the bridge was built without the Parquet component; missing Arrow/Parquet
entirely keeps the offline suite green because it links only the stub.

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

### Implemented Phase-3 surface (pure-XIOM, no FFI)

```xiom
pub type GroupBy = Int   // handle 0 is invalid

// Aggregation (ascending keys; output columns [by, col])
pub fn group_by(df: &DataFrame, by: Str) -> GroupBy
pub fn groupby_sum(gb: GroupBy, col: Str) -> Result[DataFrame, Str]
pub fn groupby_mean(gb: GroupBy, col: Str) -> Result[DataFrame, Str]
pub fn groupby_count(gb: GroupBy, col: Str) -> Result[DataFrame, Str]

// Transformation
pub fn dataframe_sort(df: &DataFrame, by: Str, ascending: Bool) -> Result[DataFrame, Str]
pub fn sort(df: &DataFrame, by: Str, ascending: Bool) -> Result[DataFrame, Str]
pub fn dataframe_drop_columns(df: &DataFrame, cols: &Vec[Str]) -> Result[DataFrame, Str]
pub fn drop_columns(df: &DataFrame, cols: &Vec[Str]) -> Result[DataFrame, Str]
```

### Implemented section-8 additive surface (0.2.1)

```xiom
// Ownership (additive; section-8 decision 4)
pub fn dataframe_free(df: DataFrame) -> Result[Int, Str]
pub fn series_free(series: Series) -> Result[Int, Str]
pub fn series_buffer_free(ptr: Int) -> Result[Int, Str]

// Float64 comparison value as IEEE-754 bits (section-8 decision 5)
pub fn dataframe_filter_f64(df: DataFrame, col_name: Int, op: Int, bits: Int) -> Result[DataFrame, Str]

// I/O through the Arrow Parquet component (section-8 decision 6)
pub fn dataframe_from_parquet(path: Int) -> Result[DataFrame, Str]
pub fn dataframe_to_parquet(df: DataFrame, path: Int) -> Result[Int, Str]
```

`tests/test_conformance.xi` sections 18-24 add 32 checks for this surface
(filter_f64, the three frees, both Parquet entry points, f64 apply parity,
API/contract markers, and safe-wrapper error paths). Suite: **164/164 PASS
x2** on compiler v0.64.8 (2026-10-20).

## Contract coverage target
- Column existence: `requires: col_name in columns(df)`
- Shape compatibility: `requires: left.len() > 0 && right.len() > 0`
- File paths: `requires: io.file_exists(path)` for read
- Type safety: DType enum for int/float/string/bool

## Phased roadmap

| Phase | What | Effort |
|-------|------|--------|
| 1 | Core foundation: types, FFI seam, safe wrappers | Done |
| 2 | DataFrame ops: shape/columns/dtypes/selection/slicing | Done (pinned subset) |
| 3 | Aggregation & transformation: sort, drop, groupby sum/mean/count | Done (pinned subset); `fillna` skipped as unpinned |
| 4 | Advanced I/O & time series | Week |

The phase-by-phase task list is authoritative in `ROADMAP.md`; this table
summarizes it.

## Phase 1 Implementation Summary

| Artifact | Path | Lines |
|---|---|---|
| Module | `pandas.xi` | 1235 |
| Tests | `tests/test_conformance.xi` | 1705 |
| Stub bridge | `bridge/pandas_bridge.c` | 232 |
| REAL Arrow bridge | `bridge/xiom_pandas_arrow.cpp` | 1149 |
| Real-backend requirements | `bridge/REAL-BACKEND-REQUIREMENTS.md` | 214 |
| Real-runtime probe | `tests/probe_real_arrow.xi` | 531 |
| Probe callback | `tests/probe_real_arrow_callback.c` | 17 |
| Provenance | `PROVENANCE.md` | 126 |
| Roadmap | `ROADMAP.md` | 89 |
| SPEC | `SPEC.md` (this file) | 424 |

### What Phase 1 delivers
- **4 opaque handle types**: `DataFrame = Int`, `Series = Int`, `Dtype = Int`, `GroupBy = Int` (Phase 3)
- **6 dtype constants**: `DTYPE_INT32`(0) through `DTYPE_BOOL`(5)
- **6 compare op constants**: `CMP_EQ`(0) through `CMP_GE`(5)
- **4 join type constants**: `JOIN_INNER`(0) through `JOIN_OUTER`(3)
- **18 extern "C" functions** (C symbols, `pandas_c_` prefix except the owner-pinned `pandas_dataframe_filter_f64`): the 12 original dataframe/series/CSV entries plus `pandas_c_dataframe_free`, `pandas_c_series_free`, `pandas_c_free`, `pandas_dataframe_filter_f64`, `pandas_c_dataframe_from_parquet`, `pandas_c_dataframe_to_parquet`
- **18 safe wrappers**: all extern functions wrapped with `requires` contracts and null checks; the 12 original wrappers are byte-identical
- **2 utilities**: `dtype_name(dtype)`, `version()` (returns `0.2.1`)
- **164 conformance tests** on the current `xiom.test` API: 24 sections covering constants, FFI stub behavior, API presence, contracts, types, dtype_name, safe wrapper error paths, the Phase-2 pure-XIOM surface (29 checks), the Phase-3 pinned subset (23 checks), and the section-8 additive surface (32 checks)
- **40 contracts**: the 11 Phase-1 contracts, 16 Phase-2 contracts, 8 Phase-3 contracts and 5 section-8 contracts (`dataframe_free`, `series_free`, `series_buffer_free`, `dataframe_filter_f64`, `dataframe_to_parquet`), all `requires: handle != 0`
- **Offline stub bridge**: `bridge/pandas_bridge.c` + `port.args.json`
- **Real-backend requirements**: `bridge/REAL-BACKEND-REQUIREMENTS.md` (for the bindings/xiom.arrow lanes)
