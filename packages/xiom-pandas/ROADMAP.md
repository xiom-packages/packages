# xiom.pandas -- Roadmap

> Two-leg delivery (mirrors xiom.numpy Phase 1): the OFFLINE conformance leg
> is green (**109/109 x2**, v0.64.6, 2026-10-17) via the pure-XIOM Phase-2
> registry plus the suite-only stub bridge `bridge/pandas_bridge.c`. The REAL
> Arrow C++ backend SOURCE is prepared (`bridge/xiom_pandas_arrow.cpp`) and
> probe-green against Apache Arrow C++ 22.0.0 (pyarrow 22.0.0 MSVC wheel):
> null contract + CSV round trip in `tests/probe_real_arrow.xi`, plus a
> deleted local C-ABI exercise of all 12 symbols. Owner-pending ABI items
> (free functions, apply signature, Float64 filter value, parquet) are listed
> in SPEC.md; the 12-symbol FFI ABI is unchanged.

**Phase 1** (v0.1.0) -- Core Foundation [OK]
- [x] 3 opaque types: `DataFrame`, `Series`, `Dtype`
- [x] 6 dtype constants: `DTYPE_INT32`..`DTYPE_BOOL`
- [x] 6 compare op constants: `CMP_EQ`..`CMP_GE`
- [x] 4 join type constants: `JOIN_INNER`..`JOIN_OUTER`
- [x] 12 extern "C" functions declared (`pandas_c_*` C symbols)
- [x] 12 safe wrappers with `requires` contracts
- [x] `dtype_name` utility
- [x] `version` utility
- [x] 80 conformance tests (suite migrated to the current `xiom.test` API;
      the former T001 extern-block duplication is reconciled away)
- [x] Offline stub bridge + `port.args.json` wiring
- [x] Real-backend requirements report (for bindings/xiom.arrow lanes)
- [x] Real-runtime probe authored (evidence-only, fails closed)

**Phase 2** (v0.2.0, partial) -- DataFrame Operations (**pure XIOM, no real backend needed**)
- [x] `dataframe_shape(df) -> (Int, Int)` -- row/column count (+ `shape` SPEC alias)
- [x] `dataframe_columns(df) -> Vec[Str]` -- column name enumeration (+ `columns` alias)
- [x] `dataframe_dtypes(df) -> Vec[Dtype]` -- per-column dtype query (+ `dtypes` alias)
- [x] `column(df, name) -> Result[Series, Str]` -- named column view
- [x] `dataframe_iloc(df, row) -> Result[Series, Str]` -- row access (+ `iloc` alias)
- [x] `dataframe_loc_range(df, start, end) -> Result[DataFrame, Str]` -- inclusive row slice (+ `loc_range` alias)
- [x] `dataframe_head(df, n) -> Result[DataFrame, Str]` -- first N rows
- [x] `dataframe_tail(df, n) -> Result[DataFrame, Str]` -- last N rows
- [x] Pure-XIOM registry (`dataframe_from_columns`, `series_len`,
      `series_dtype`, `series_values`); 29 new checks -> **109/109 x2**
- [ ] Rename / reorder -- **SKIPPED (unpinned: absent from SPEC and ROADMAP)**
- [ ] Concat -- **SKIPPED (unpinned)**
- [ ] Merge / joins -- **SKIPPED (unpinned key/suffix/duplicate semantics; phased after Phase 2 in SPEC)**
- [ ] Mixed-dtype storage -- **SKIPPED (SPEC's pinned constructor is `Map[Str, Vec[Float64]]`)**

Design + semantics: SPEC.md -> "Phase 2 (partial, pure-XIOM)".

**Phase 3** (v0.3.0) -- Aggregation & Transformation (needs the real Arrow backend)
- [ ] `groupby_sum(gb, col) -> Result[DataFrame, Str]`
- [ ] `groupby_mean(gb, col) -> Result[DataFrame, Str]`
- [ ] `groupby_count(gb, col) -> Result[DataFrame, Str]`
- [ ] `dataframe_sort(df, by, ascending) -> Result[DataFrame, Str]`
- [ ] `dataframe_drop_columns(df, cols) -> Result[DataFrame, Str]`
- [ ] `dataframe_fillna(df, value) -> Result[DataFrame, Str]`

**Phase 4** (v0.4.0) -- Advanced I/O & Time Series (needs the real Arrow backend)
- [ ] `dataframe_read_parquet(path) -> Result[DataFrame, Str]`
- [ ] `dataframe_to_parquet(df, path) -> Result[Unit, Str]`
- [ ] Time series: rolling windows, date range generation
- [ ] Multi-index support (via Arrow nested structs)
- [ ] Arrow zero-copy interop (`to_arrow`, `from_arrow`)

## Dependencies
| Dependency | Status |
|---|---|
| `xiom.ffi` (stdlib) | Required (v0.64.5 runtime provides the alloc/guard symbols the real bridge and `xiom.ffi` helpers need) |
| `xiom.arrow` (Apache Arrow C Data Interface) | Required for the real backend + zero-copy interop (NOT built; see bridge/REAL-BACKEND-REQUIREMENTS.md section 5) |
| Apache Arrow C++ (system) | Required by the real bridge only; never by the offline suite |

## Contract Coverage
- 27 `requires` contracts across 27 public functions (11 Phase 1 + 16 Phase 2)
- Target: 100% of public FFI functions have contracts
