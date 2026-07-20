# xiom-pandas — SPEC

**Phase**: 1 (Core Foundation) | **Priority**: HIGH
**Status**: SPEC only — no implementation yet
**Depends on**: xiom.ffi (stdlib), xiom-arrow (Apache Arrow — Pandas 2.0+ backend)

## What it wraps
Pandas — data analysis library. In Pandas 2.0+, the backend is Apache Arrow.
We wrap Arrow C++ directly (not Python), providing DataFrame/Series operations
with zero Python overhead. This is the approach Polars and DuckDB use internally.

## Dependencies

| What | How | Size |
|------|-----|------|
| Apache Arrow C++ | System-installed (via xiom-arrow) | ~50MB |
| C++ compiler | For building bridge | — |

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
