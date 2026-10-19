# xiom.pandas -- Roadmap

> **0.2.0** (2026-10-19): the REAL Arrow-backed bridge implements the owner
> section-8 decisions on Apache Arrow C++ 22.0.0 **without Acero headers or
> symbols**: Grouper-based group-by, bridge-side join fallback, Float64-only
> `series_apply`, additive ownership frees, `dataframe_filter_f64`, and
> Parquet through the Arrow Parquet component. Offline suite 110/110 x2 on
> v0.64.8; the real probe (CSV/group-by/join/apply/filter/Parquet) is green.
> See `SPEC.md` and `PROVENANCE.md`.

**Phase 1** (v0.1.0) -- Core Foundation [OK]
- [x] 3 opaque types: `DataFrame`, `Series`, `Dtype`
- [x] 6 dtype constants: `DTYPE_INT32`..`DTYPE_BOOL`
- [x] 6 compare op constants: `CMP_EQ`..`CMP_GE`
- [x] 4 join type constants: `JOIN_INNER`..`JOIN_OUTER`
- [x] 12 extern "C" functions declared (`pandas_c_*` C symbols)
- [x] 12 safe wrappers with `requires` contracts
- [x] `dtype_name` utility
- [x] `version` utility
- [x] Offline stub bridge + `port.args.json` wiring
- [x] Real-backend requirements report (for bindings/xiom.arrow lanes)
- [x] Real-runtime probe authored (evidence-only, fails closed)

**Phase 2** (v0.2.0) -- Real bridge + DataFrame operations
- [x] Real Acero-free `dataframe_filter` (Int entry unchanged)
- [x] Additive `dataframe_filter_f64` (IEEE-754 bits as Int64)
- [x] Real Acero-free `dataframe_groupby` (Grouper aggregate fallback)
- [x] Real Acero-free `dataframe_join` (Grouper + Take, all 4 join types)
- [x] Real CSV reader/writer
- [x] Additive ownership frees: `dataframe_free`, `series_free`,
      `series_buffer_free`
- [ ] `dataframe_shape(df) -> (Int, Int)` -- row/column count
- [ ] `dataframe_columns(df) -> Vec[Str]` -- column name enumeration
- [ ] `dataframe_dtypes(df) -> Vec[Dtype]` -- per-column dtype query
- [ ] `dataframe_iloc(df, row) -> Result[Series, Str]` -- row access
- [ ] `dataframe_loc_range(df, start, end) -> Result[DataFrame, Str]` -- row slice
- [ ] `dataframe_head(df, n) -> Result[DataFrame, Str]` -- first N rows
- [ ] `dataframe_tail(df, n) -> Result[DataFrame, Str]` -- last N rows

**Phase 3** -- Aggregation & Transformation (real-bridge foundation landed)
- [ ] `groupby_sum(gb, col) -> Result[DataFrame, Str]`
- [ ] `groupby_mean(gb, col) -> Result[DataFrame, Str]`
- [ ] `groupby_count(gb, col) -> Result[DataFrame, Str]` (the bridge aggregate
      already produces `count`; the consumer wrapper is not yet exposed)
- [ ] `dataframe_sort(df, by, ascending) -> Result[DataFrame, Str]`
- [ ] `dataframe_drop_columns(df, cols) -> Result[DataFrame, Str]`
- [ ] `dataframe_fillna(df, value) -> Result[DataFrame, Str]`
- [x] `series_apply` Float64 `double (*)(double)` (section-8 pinned ABI)

**Phase 4** -- Advanced I/O & Time Series (real-bridge foundation landed)
- [x] Parquet read: `dataframe_from_parquet(path)` (Arrow Parquet component)
- [x] Parquet write: `dataframe_to_parquet(df, path)` (Arrow Parquet component)
- [ ] Time series: rolling windows, date range generation
- [ ] Multi-index support (via Arrow nested structs)
- [ ] Arrow zero-copy interop (`to_arrow`, `from_arrow`)

## Dependencies
| Dependency | Status |
|---|---|
| `xiom.ffi` (stdlib) | Required (alloc/guard symbols for the real bridge and probe) |
| `xiom.arrow` (Apache Arrow C Data Interface) | Required for zero-copy interop (Phase 4 remainder); not needed by the 0.2.0 bridge |
| Apache Arrow C++ 22.0.0 (system) | Required by the real bridge only; never by the offline suite. The Parquet component is required for the Parquet entry points; without its headers the bridge compiles the entry points as backend-unavailable stubs. |

## Contract Coverage
- 16 `requires` contracts across 16 public functions (0.2.0)
- Target: 100% of public FFI functions have contracts (the Parquet read
  wrapper deliberately has none: a null path is handled as a typed `Err`).
