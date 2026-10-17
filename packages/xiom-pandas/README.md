# xiom.pandas

> **Status:** `incubating` -- offline conformance GREEN (109/109 x2, compiler
> v0.64.6, 2026-10-17) with the Phase-2 pinned subset implemented in pure
> XIOM; the REAL Arrow-backed bridge source is built and probe-green locally.
> Published baseline: 0.1.0 in `eco-v0.1.193` (sha256 `aad9a74e...`, 2026-10-16).
> **Scope:** Pandas-like tabular data structures over Apache Arrow.
> **Deps:** stdlib; C FFI bridge (Phase-1 seam only -- the Phase-2 ops use no FFI).

## Two-leg delivery (mirrors xiom.numpy Phase 1 / xiom.http)

| Leg | Artifact | Status |
|-----|----------|--------|
| Offline suite | pure-XIOM Phase-2 registry + `bridge/pandas_bridge.c` stub (no external libs) + `port.args.json` | GREEN: `scripts/port.ps1 -Package xiom-pandas -TimeoutSec 240` -> **109/109 x2** |
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
