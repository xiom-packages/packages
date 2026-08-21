# xiom-pandas -- Roadmap

**Phase 1** (v0.1.0) -- Core Foundation [OK]
- [x] 3 opaque types: `DataFrame`, `Series`, `Dtype`
- [x] 6 dtype constants: `DTYPE_INT32`..`DTYPE_BOOL`
- [x] 6 compare op constants: `CMP_EQ`..`CMP_GE`
- [x] 4 join type constants: `JOIN_INNER`..`JOIN_OUTER`
- [x] 12 extern "C" functions declared
- [x] 12 safe wrappers with `requires` contracts
- [x] `dtype_name` utility
- [x] `version` utility
- [x] 80+ conformance tests

**Phase 2** (v0.2.0) -- DataFrame Operations
- [ ] `dataframe_shape(df) -> (Int, Int)` -- row/column count
- [ ] `dataframe_columns(df) -> Vec[Str]` -- column name enumeration
- [ ] `dataframe_dtypes(df) -> Vec[Dtype]` -- per-column dtype query
- [ ] `dataframe_iloc(df, row) -> Result[Series, Str]` -- row access
- [ ] `dataframe_loc_range(df, start, end) -> Result[DataFrame, Str]` -- row slice
- [ ] `dataframe_head(df, n) -> Result[DataFrame, Str]` -- first N rows
- [ ] `dataframe_tail(df, n) -> Result[DataFrame, Str]` -- last N rows

**Phase 3** (v0.3.0) -- Aggregation & Transformation
- [ ] `groupby_sum(gb, col) -> Result[DataFrame, Str]`
- [ ] `groupby_mean(gb, col) -> Result[DataFrame, Str]`
- [ ] `groupby_count(gb, col) -> Result[DataFrame, Str]`
- [ ] `dataframe_sort(df, by, ascending) -> Result[DataFrame, Str]`
- [ ] `dataframe_drop_columns(df, cols) -> Result[DataFrame, Str]`
- [ ] `dataframe_fillna(df, value) -> Result[DataFrame, Str]`

**Phase 4** (v0.4.0) -- Advanced I/O & Time Series
- [ ] `dataframe_read_parquet(path) -> Result[DataFrame, Str]`
- [ ] `dataframe_to_parquet(df, path) -> Result[Unit, Str]`
- [ ] Time series: rolling windows, date range generation
- [ ] Multi-index support (via Arrow nested structs)
- [ ] Arrow zero-copy interop (`to_arrow`, `from_arrow`)

## Dependencies
| Dependency | Status |
|---|---|
| `xiom.ffi` (stdlib) | Required |
| `xiom-arrow` (Apache Arrow C Data Interface) | Required (Phase 4) |

## Contract Coverage
- 11 `requires` contracts across 11 public functions (Phase 1)
- Target: 100% of public FFI functions have contracts
