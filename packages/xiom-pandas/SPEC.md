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
| Module | `pandas.xi` | ~280 |
| Tests | `tests/test_conformance.xi` | ~460 |
| Roadmap | `ROADMAP.md` | ~55 |
| SPEC | `SPEC.md` (this file) | ~100 |

### What Phase 1 delivers
- **3 opaque types**: `DataFrame = Int`, `Series = Int`, `Dtype = Int`
- **6 dtype constants**: `DTYPE_INT32`(0) through `DTYPE_BOOL`(5)
- **6 compare op constants**: `CMP_EQ`(0) through `CMP_GE`(5)
- **4 join type constants**: `JOIN_INNER`(0) through `JOIN_OUTER`(3)
- **12 extern "C" functions**: dataframe_new, dataframe_from_csv, dataframe_to_csv, dataframe_get_column, dataframe_set_column, dataframe_filter, dataframe_groupby, dataframe_join, series_new, series_from_vec, series_to_vec, series_apply
- **12 safe wrappers**: all extern functions wrapped with `requires` contracts and null checks
- **2 utilities**: `dtype_name(dtype)`, `version()`
- **80+ conformance tests**: 15 sections covering constants, FFI stubs, API presence, contracts, types, dtype_name, and safe wrapper error paths
- **11 contracts**: across 11 public functions with `requires` annotations
