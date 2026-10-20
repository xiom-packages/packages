# xiom.pandas -- Roadmap

> **0.2.1** (2026-10-20): the section-8 surface is merged onto the live 0.2.0
> artifact -- additive ownership frees (`dataframe_free`/`series_free`/
> `series_buffer_free`), `dataframe_filter_f64` (IEEE-754 bits as Int64), the
> f64 `series_apply` parity and Arrow Parquet wrappers
> (`dataframe_from_parquet`/`dataframe_to_parquet`) -- while keeping every
> 0.2.0 entry point byte-identical. The REAL Arrow C++ backend implements the
> 18-symbol ABI on Apache Arrow C++ 22.0.0 **without Acero headers or
> symbols**; offline suite **164/164 x2** on v0.64.8 and the real probe is
> green (CSV, group-by, joins, apply, filter_f64, frees, Parquet SKIP-safe).
> See `SPEC.md`, `PROVENANCE.md` and section 9 of
> `bridge/REAL-BACKEND-REQUIREMENTS.md`.

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

**Phase 3** (v0.3.0, pinned subset) -- Aggregation & Transformation (**pure XIOM, no real backend needed for these paths**)
- [x] `group_by(df, by) -> GroupBy` -- handle over the grouping column
- [x] `groupby_sum(gb, col) -> Result[DataFrame, Str]` -- ascending keys, output `[by, col]`
- [x] `groupby_mean(gb, col) -> Result[DataFrame, Str]`
- [x] `groupby_count(gb, col) -> Result[DataFrame, Str]` -- row count (no NA model)
- [x] `dataframe_sort(df, by, ascending) -> Result[DataFrame, Str]` (+ `sort` alias)
- [x] `dataframe_drop_columns(df, cols) -> Result[DataFrame, Str]` (+ `drop_columns` alias)
- [ ] `dataframe_fillna(df, value)` -- **SKIPPED (unpinned: no NA/NaN representation or fill strategy in the Float64 model)**
- [x] 23 new hand-computed checks -> **132/132 x2** (v0.64.8, 2026-10-19)
- [ ] Sort stability among equal keys -- **SKIPPED as a contract** (not pinned; implementation is stable but tests do not assert ties)

Design + semantics: SPEC.md -> "Phase 3 (pinned subset)".

**Phase 3.1** (v0.2.1, section-8 additive surface) -- merged onto live 0.2.0
- [x] `dataframe_free(df) -> Result[Int, Str]` -- additive ownership
- [x] `series_free(series) -> Result[Int, Str]` -- additive ownership
- [x] `series_buffer_free(ptr) -> Result[Int, Str]` -- releases `series_to_vec` buffers
- [x] `dataframe_filter_f64(df, col, op, bits) -> Result[DataFrame, Str]` -- IEEE-754 bits as Int64; Int entry unchanged
- [x] `dataframe_from_parquet(path) -> Result[DataFrame, Str]` -- Arrow 22 Parquet component
- [x] `dataframe_to_parquet(df, path) -> Result[Int, Str]` -- Arrow 22 Parquet component
- [x] f64 `series_apply` parity (`double (*)(double)`, Float64 only) in the real bridge
- [x] Acero-free real bridge (`Grouper` group-by, Grouper+`Take` join) + PROVENANCE
- [x] 32 new checks -> **164/164 x2** (v0.64.8, 2026-10-20)
- [x] Real probe legs: null contract, CSV, group-by, 4 join types, apply, filter_f64, frees, Parquet (SKIP-safe)

**Phase 4** (v0.4.0) -- Advanced I/O & Time Series (needs the real Arrow backend)
- [x] `dataframe_from_parquet(path) -> Result[DataFrame, Str]` -- landed in 0.2.1 (section-8 decision 6)
- [x] `dataframe_to_parquet(df, path) -> Result[Int, Str]` -- landed in 0.2.1 (section-8 decision 6)
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
- 40 `requires` contracts across 40 public functions (11 Phase 1 + 16 Phase 2 + 8 Phase 3 + 5 section-8)
- Target: 100% of public FFI functions have contracts
