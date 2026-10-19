# xiom.pandas

> **Status:** `incubating` -- **0.2.0** (real Arrow-backed bridge, section-8
> owner decisions). Offline conformance GREEN **110/110 x2** on compiler
> **v0.64.8**; the real bridge builds on Apache Arrow C++ **22.0.0** with
> **no Acero headers/symbols** and the evidence probe is green.
> **Scope:** Pandas-like tabular data structures over Apache Arrow.
> **Deps:** stdlib; C++17 bridge; system Apache Arrow C++ 22.0.0 (real leg only).

## Two-leg delivery (mirrors xiom.numpy / xiom.http)

| Leg | Artifact | Status |
|-----|----------|--------|
| Offline suite | `bridge/pandas_bridge.c` (deterministic stub, no external libs) + `port.args.json` | GREEN: `scripts/port.ps1 -Package xiom-pandas -TimeoutSec 300` -> **110/110** |
| Real backend | `bridge/xiom_pandas_arrow.cpp` (Arrow C++, C++17, exception-free C ABI) | BUILT + PROBE GREEN on Apache Arrow C++ **22.0.0** (pyarrow 22.0.0 wheel, MSVC 19.44 ABI); Acero-free group-by/join; Parquet via the Arrow Parquet component |

The stub validates arguments and reports the Arrow backend unavailable on
success paths; it never fabricates data. The 18 C symbols are declared in
`pandas.xi` (public wrappers keep the `dataframe_*` / `series_*` names). See
`SPEC.md` for the section-8 decision map and `PROVENANCE.md` for the pin,
acquisition and ABI evidence.

## Section-8 decisions (owner GO 2026-10-19)

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

## ABI (0.2.0)

- **12 original wrappers stay byte-identical** (`pandas_c_*` symbols):
  dataframe new/from_csv/to_csv/get_column/set_column/filter/groupby/join,
  series new/from_vec/to_vec/apply.
- **6 additive symbols:** `pandas_c_dataframe_free`, `pandas_c_series_free`,
  `pandas_c_free`, `pandas_dataframe_filter_f64`,
  `pandas_c_dataframe_from_parquet`, `pandas_c_dataframe_to_parquet`.
- Public additive wrappers: `dataframe_free`, `series_free`,
  `series_buffer_free`, `dataframe_filter_f64`, `dataframe_from_parquet`,
  `dataframe_to_parquet`.
- GroupBy handles are opaque; no group-by consumer/free is added in 0.2.0
  (the section-8 ownership set is exactly the three frees above).

## Run the offline suite

```powershell
$env:XIOM_COMPILER="$env:LOCALAPPDATA\xiom.new\bin\xiom.exe"
$env:XIOM_STDLIB="E:\xiom-lang\stdlib"
.\scripts\port.ps1 -Package xiom-pandas -TimeoutSec 300
```

The suite links only `bridge/pandas_bridge.c`; it never needs Arrow or
Parquet. If the shared stdlib runtime directory contains a test `main`
(e.g. `runtime/test_udivti3.c`), use a pristine stdlib snapshot for the run
and document it; the package itself has no such dependency.

## Run the real probe (evidence-only, SKIP-safe)

```powershell
$arrow = "E:\repos\arrow-bin\pyarrow-22.0.0"
$env:CPLUS_INCLUDE_PATH = "<arrow-include-without-arrow/acero>"  # or the wheel include
$env:PATH = "$arrow\pyarrow;$arrow\pyarrow.libs;$env:PATH"
xiom --run packages\xiom-pandas\tests\probe_real_arrow.xi `
    --cxx-standard 17 `
    --c-source packages\xiom-pandas\bridge\xiom_pandas_arrow.cpp `
    --c-source packages\xiom-pandas\tests\probe_real_arrow_callback.c `
    --link arrow --link arrow_compute --link parquet `
    --link-path "$arrow\pyarrow"
```

No `--link arrow_acero`. The probe is not part of `port.ps1`; without the
Arrow/Parquet libraries it reports `[SKIP]` for the Parquet leg (or fails
closed if the bridge is not linked). See `PROVENANCE.md` for the pinned
wheel, hashes and the acquisition recipe.

## Libs inventory

| Lib | Description |
|-----|-------------|
| `dataframe` | Two-dimensional labeled table. |
| `series` | One-dimensional labeled array. |
| `io` | CSV and Parquet table I/O. |
| `groupby` | Split-apply-combine grouping. |
| `join` | Table joins and merges. |
| `pivot` | Pivot and reshape operations (not yet exposed). |
