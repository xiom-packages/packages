# xiom.pandas

> **Status:** `incubating` -- **0.2.1** (section-8 surface merged onto the live
> 0.2.0 artifact). Offline conformance GREEN (**164/164 x2**, compiler
> **v0.64.8**, 2026-10-20) with the Phase-2/3 pure-XIOM subsets plus the
> additive ownership frees, `dataframe_filter_f64` and Arrow Parquet entry
> points; the REAL Acero-free Arrow-backed bridge is built and probe-green
> locally.
> Published: `0.2.1` in `eco-v0.1.201` (sha256 `4c081871...`, 2026-10-20); `0.2.0` as single tag `xiom-pandas/v0.2.0` (sha256 `1cd063c3...`,
> 2026-10-19); baseline 0.1.0 in `eco-v0.1.193` (sha256 `aad9a74e...`, 2026-10-16).
> **Scope:** Pandas-like tabular data structures over Apache Arrow.
> **Deps:** stdlib; C++17 bridge; system Apache Arrow C++ 22.0.0 (real leg only).

## Two-leg delivery (mirrors xiom.numpy Phase 1 / xiom.http)

| Leg | Artifact | Status |
|-----|----------|--------|
| Offline suite | pure-XIOM Phase-2/3 registry + `bridge/pandas_bridge.c` stub (no external libs) + `port.args.json` | GREEN: `scripts/port.ps1 -Package xiom-pandas -TimeoutSec 300` -> **164/164 x2** |
| Real backend | `bridge/xiom_pandas_arrow.cpp` (Arrow C++, C++17, exception-free C ABI) | BUILT + PROBE GREEN on Apache Arrow C++ 22.0.0 (pyarrow 22.0.0 wheel; MSVC 19.44 ABI); Acero-free group-by/join, Float64 apply, f64 filter and Parquet via the Arrow Parquet component; `tests/probe_real_arrow.xi` (not part of port.ps1) covers null contract, CSV, group-by, all 4 joins, apply, filter_f64, frees and Parquet (SKIP-safe) |

The stub validates arguments and reports the Arrow backend unavailable on
success paths; it never fabricates data. The 18 C symbols carry the
`pandas_c_` prefix (one owner-pinned `pandas_dataframe_filter_f64` exception)
and are declared in `pandas.xi` (public wrappers keep the `dataframe_*` /
`series_*` names). See `SPEC.md` -> "Surface status" for the T001
reconciliation and the symbol-prefix rationale.

## Section-8 decisions (owner GO 2026-10-19, landed in 0.2.1)

1. **Acero is not a build requirement.** No `arrow/acero` headers or symbols
   are used. Group-by uses `arrow::compute::Grouper`
   (`arrow/compute/row/grouper.h`); join is the bridge-side fallback
   (Grouper key ids + `arrow::compute::Take`).
2. **TableGroupBy:** `arrow/compute/exec/group_by.h` is absent in Arrow 22.0.0,
   so the Acero-free aggregate-in-the-bridge fallback is used (key column +
   Int64 `count`).
3. **series_apply:** `double (*)(double)`, applied per element, **Float64
   only**; no element coercion. Non-Float64 series and null elements return 0
   (fail closed). NA/NaN policies are explicitly out of scope; NaN values pass
   through to the callback unchanged.
4. **Ownership:** additive `pandas_c_dataframe_free`,
   `pandas_c_series_free`, `pandas_c_free` for `series_to_vec` buffers.
5. **dataframe_filter_f64:** additive owner-pinned entry
   `pandas_dataframe_filter_f64(df, column, op, bits)` with the comparison
   value as an IEEE-754 f64 bit pattern in an Int64. The Int entry is
   unchanged.
6. **Parquet:** `parquet::arrow::OpenFile` + `FileReader::ReadTable` and
   `parquet::arrow::WriteTable` from the pinned Arrow 22.0.0 Parquet
   component (Thrift/zstd/snappy are its transitive deps). No separate
   Parquet stack.

## ABI (0.2.1)

- **12 original wrappers stay byte-identical** (`pandas_c_*` symbols):
  dataframe new/from_csv/to_csv/get_column/set_column/filter/groupby/join,
  series new/from_vec/to_vec/apply.
- **6 additive symbols:** `pandas_c_dataframe_free`, `pandas_c_series_free`,
  `pandas_c_free`, `pandas_dataframe_filter_f64`,
  `pandas_c_dataframe_from_parquet`, `pandas_c_dataframe_to_parquet`.
- Public additive wrappers: `dataframe_free`, `series_free`,
  `series_buffer_free`, `dataframe_filter_f64`, `dataframe_from_parquet`,
  `dataframe_to_parquet`.
- GroupBy handles are opaque; no group-by consumer/free is added (the
  section-8 ownership set is exactly the three frees above).

## Phase 2 (pinned subset, pure XIOM)

`DataFrame`/`Series` stay opaque `Int` handles over a module-level registry
(`0` invalid, `1 + slot` live, slots append-only). No FFI is used on any
Phase-2 path; the Phase-1 C-bridge seam is untouched. Storage follows SPEC's
`Map[Str, Vec[Float64]]` construction, so columns are Float64.

| API | Behavior |
|---|---|
| `dataframe_from_columns(names, col_values)` | constructor; equal lengths, unique names, equal row counts |
| `dataframe_shape` / `shape` | `(rows, cols)` |
| `dataframe_columns` / `columns` | names in storage order |
| `dataframe_dtypes` / `dtypes` | per-column dtype tags |
| `column(df, name)` | Series view; exact name match, missing -> `Err` |
| `dataframe_iloc` / `iloc` | 0-based row Series; out-of-range/negative -> `Err` |
| `dataframe_loc_range` / `loc_range` | inclusive `[start, end]` row slice; strict bounds -> `Err` |
| `dataframe_head` / `dataframe_tail` | first/last `n` rows; clamps; `n == 0` empty; `n < 0` -> `Err` |
| `series_len` / `series_dtype` / `series_values` | Series inspection |

Skipped as unpinned: rename/reorder, concat, merge/joins (key/suffix semantics
not pinned), mixed-dtype storage, negative-index and non-clamping slice
behavior. See `SPEC.md` -> "Phase 2 (partial, pure-XIOM)".

## Phase 3 (pinned subset, pure XIOM)

Same append-only registry, no FFI. Aggregation output is `[grouping column,
aggregated column]`, one row per distinct Float64 key, in ascending key order.

| API | Behavior |
|---|---|
| `group_by(df, by)` | `GroupBy` handle; `0` for an invalid frame or missing column |
| `groupby_sum(gb, col)` | per-group sum (e.g. keys `[1,2]` -> `[9,30]`) |
| `groupby_mean(gb, col)` | per-group arithmetic mean (`[3,15]`) |
| `groupby_count(gb, col)` | per-group row count as Float64 (`[3,2]`) |
| `dataframe_sort` / `sort` | new frame ordered by `by`, ascending/descending |
| `dataframe_drop_columns` / `drop_columns` | new frame without the named columns; missing name or dropping all -> `Err` |

Skipped as unpinned: `dataframe_fillna` (no NA/NaN representation or fill
strategy is pinned), sort stability among equal keys (implementation-defined,
not asserted), and NA grouping/drop policies. Aggregating the grouping column
and dropping all columns fail closed with `Err`. See `SPEC.md` -> "Phase 3".

| Lib | Description |
|-----|-------------|
| `dataframe` | Two-dimensional labeled table. |
| `series` | One-dimensional labeled array. |
| `io` | CSV and Parquet table I/O. |
| `groupby` | Split-apply-combine grouping. |
| `join` | Table joins and merges. |
| `pivot` | Pivot and reshape operations. |

## Run the suite

```powershell
$env:XIOM_COMPILER="$env:LOCALAPPDATA\xiom.new\bin\xiom.exe"
$env:XIOM_STDLIB="E:\xiom-lang\stdlib"
.\scripts\port.ps1 -Package xiom-pandas -TimeoutSec 300
```

The suite links only `bridge/pandas_bridge.c`; it never needs Arrow or
Parquet. The real probe is evidence-only and SKIP-safe:

```powershell
$arrow = "E:\repos\arrow-bin\pyarrow-22.0.0"
$env:CPLUS_INCLUDE_PATH = "$arrow\pyarrow\include"
$env:PATH = "$arrow\pyarrow;$arrow\pyarrow.libs;$env:PATH"
xiom --run packages\xiom-pandas\tests\probe_real_arrow.xi `
    --cxx-standard 17 `
    --c-source packages\xiom-pandas\bridge\xiom_pandas_arrow.cpp `
    --c-source packages\xiom-pandas\tests\probe_real_arrow_callback.c `
    --link arrow --link arrow_compute --link parquet `
    --link-path "$arrow\pyarrow"
```

No `--link arrow_acero`. See `PROVENANCE.md` for the pinned wheel, hashes and
the acquisition recipe.
