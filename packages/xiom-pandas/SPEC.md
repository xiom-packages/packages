# xiom.pandas -- SPEC

**Phase**: 1 (Core Foundation) | **Priority**: HIGH
**Status**: Phase 1 implemented -- `pandas.xi` + tests + ROADMAP
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
- **Leg 2 (real, NOT BUILT)**: `bridge/xiom_pandas_arrow.cpp` (Arrow C++,
  C++17), specced in `bridge/REAL-BACKEND-REQUIREMENTS.md`: exact symbol
  contract, headers, C++ ABI notes, zero-copy Arrow C Data Interface points,
  what xiom.arrow must expose, and open items. `tests/probe_real_arrow.xi`
  is the evidence-only real-runtime probe (NOT part of port.ps1); without
  the real bridge it fails closed.
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
| Module | `pandas.xi` | 375 |
| Tests | `tests/test_conformance.xi` | 677 |
| Stub bridge | `bridge/pandas_bridge.c` | 174 |
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
- **80 conformance tests** on the current `xiom.test` API: 15 sections covering constants, FFI stub behavior, API presence, contracts, types, dtype_name, and safe wrapper error paths (see Surface status for the stub/real split and the T001 reconciliation)
- **11 contracts**: across 11 public functions with `requires` annotations
- **Offline stub bridge**: `bridge/pandas_bridge.c` + `port.args.json`
- **Real-backend requirements**: `bridge/REAL-BACKEND-REQUIREMENTS.md` (for the bindings/xiom.arrow lanes)
