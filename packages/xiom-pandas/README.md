# xiom.pandas

> **Status:** `incubating` -- offline conformance GREEN (80/80 x2, compiler
> v0.64.5); published in `eco-v0.1.193` (sha256 `aad9a74e...`, 2026-10-16).
> **Scope:** Pandas-like tabular data structures over Apache Arrow.
> **Deps:** stdlib; C FFI bridge.

## Two-leg delivery (mirrors xiom.numpy Phase 1 / xiom.http)

| Leg | Artifact | Status |
|-----|----------|--------|
| Offline suite | `bridge/pandas_bridge.c` (deterministic stub, no external libs) + `port.args.json` | GREEN: `scripts/port.ps1 -Package xiom-pandas -TimeoutSec 180` -> 80/80 x2 |
| Real backend | `bridge/xiom_pandas_arrow.cpp` (Arrow C++, C++17) | NOT BUILT -- requirements pinned in `bridge/REAL-BACKEND-REQUIREMENTS.md`; evidence probe `tests/probe_real_arrow.xi` (not part of port.ps1, fails closed without the real bridge) |

The stub validates arguments and reports the Arrow backend unavailable on
success paths; it never fabricates data. The 12 C symbols carry the
`pandas_c_` prefix and are declared in `pandas.xi` (public wrappers keep the
`dataframe_*` / `series_*` names). See `SPEC.md` -> "Surface status" for the
T001 reconciliation and the symbol-prefix rationale.

## Libs inventory

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
