# xiom.pandas

> **Status:** `incubating` -- offline conformance GREEN (132/132 x2, compiler
> v0.64.8, 2026-10-19) with the Phase-2 and Phase-3 pinned subsets implemented
> in pure XIOM; the REAL Arrow-backed bridge source is built and probe-green
> locally. Published as single tag `xiom-pandas/v0.2.0` (sha256 `1cd063c3...`,
> 2026-10-19).
> Published baseline: 0.1.0 in `eco-v0.1.193` (sha256 `aad9a74e...`, 2026-10-16).
> **Scope:** Pandas-like tabular data structures over Apache Arrow.
> **Deps:** stdlib; C FFI bridge (Phase-1 seam only -- the Phase-2 ops use no FFI).

## Two-leg delivery (mirrors xiom.numpy Phase 1 / xiom.http)

| Leg | Artifact | Status |
|-----|----------|--------|
| Offline suite | pure-XIOM Phase-2/3 registry + `bridge/pandas_bridge.c` stub (no external libs) + `port.args.json` | GREEN: `scripts/port.ps1 -Package xiom-pandas -TimeoutSec 240` -> **132/132 x2** |
| Real backend | `bridge/xiom_pandas_arrow.cpp` (Arrow C++, C++17, exception-free C ABI) | SOURCE BUILT + PROBE GREEN on Apache Arrow C++ 22.0.0 (pyarrow 22.0.0 wheel; MSVC 19.44 ABI); `tests/probe_real_arrow.xi` (not part of port.ps1) covers null contract + CSV round trip; a deleted local C-ABI probe covered all 12 symbols |

The stub validates arguments and reports the Arrow backend unavailable on
success paths; it never fabricates data. The 12 C symbols carry the
`pandas_c_` prefix and are declared in `pandas.xi` (public wrappers keep the
`dataframe_*` / `series_*` names). See `SPEC.md` -> "Surface status" for the
T001 reconciliation and the symbol-prefix rationale.

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
| `io` | CSV/JSON table I/O. |
| `groupby` | Split-apply-combine grouping. |
| `join` | Table joins and merges. |
| `pivot` | Pivot and reshape operations. |

## Run the suite

```powershell
$env:XIOM_COMPILER="$env:LOCALAPPDATA\xiom.new\bin\xiom.exe"
$env:XIOM_STDLIB="E:\xiom-lang\stdlib"
.\scripts\port.ps1 -Package xiom-pandas -TimeoutSec 180
```
