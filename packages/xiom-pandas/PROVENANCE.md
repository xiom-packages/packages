# PROVENANCE -- xiom.pandas

<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

Owner policy: `docs/UPSTREAM-FIRST.md` (upstream-first, 100% of the declared
surface). This package is an FFI binding. No upstream source is copied into the
XIOM modules; the real backend compiles against the Apache Arrow C++ public
headers and links the upstream runtime.

## 1. Upstream + pin

| Field | Value |
|-------|-------|
| Project | Apache Arrow -- `https://github.com/apache/arrow` |
| License | Apache-2.0 (ASF) |
| Delivered pin | tag **apache-arrow-22.0.0** -- commit `5aeb5f217f1ba39c428c9b481f393bd37097f69e` |
| Why 22.0.0 | Newest release whose public headers compile as C++17; Arrow 24+ uses `std::span`/`std::bit_width` in public headers (C++20), which breaks the C++17 artifact contract. |
| Runtime artifact | pyarrow **22.0.0** win_amd64 wheel `pyarrow-22.0.0-cp312-cp312-win_amd64.whl`, sha256 `44729980B6C50A5F2BFCC2668D36C569CE17F8B17BCCAF470C4313DCBBF13C9D`; extracted to `E:\repos\arrow-bin\pyarrow-22.0.0` |
| Wheel build identity | `ARROW_PACKAGE_KIND "python-wheel-windows"`, `ARROW_VERSION_STRING "22.0.0"`, `ARROW_CXX_COMPILER_ID "MSVC"`, `ARROW_CXX_COMPILER_VERSION "19.44.35217.0"` |
| Header/lib source | the wheel's `pyarrow/include` (including generated `arrow/util/config.h`) and `pyarrow/arrow.lib`, `arrow_compute.lib`, `parquet.lib`; DLLs `arrow.dll`, `arrow_compute.dll`, `parquet.dll`; the wheel's VC runtime in `pyarrow.libs` |
| Bridge toolchain | clang 22.1.8 (XIOM v0.64.8), target `x86_64-pc-windows-msvc`, `-std=c++17` |

### Acquisition (pinned wheel)

1. Download `pyarrow-22.0.0-cp312-cp312-win_amd64.whl` from PyPI.
2. Verify sha256 = `44729980B6C50A5F2BFCC2668D36C569CE17F8B17BCCAF470C4313DCBBF13C9D`.
3. Extract the wheel (a zip) to `E:\repos\arrow-bin\pyarrow-22.0.0`.
4. Headers: `pyarrow/include`; import libraries: `pyarrow/*.lib`; runtime
   DLLs: `pyarrow/*.dll`; VC runtime: `pyarrow.libs/*.dll` (note: the VC
   runtime directory sits next to `pyarrow/`, not inside it).

The same artifact is used by `xiom.arrow`; see
`packages/xiom-arrow/PROVENANCE.md` for the header-set hashes
(`arrow/c/abi.h` `5B313DF2638D9C927303DA538FB83DAEB76330D04ECE79917F56AB64962E1C7C`,
`arrow/c/bridge.h` `174C1AF59F5EDFE80C762C2F0DFB5AC584F66A8FD6DE02C6513EB6DF1F114FC1`,
`arrow/util/config.h` `E220A65B8EC77D055A9F1C82EEA7101A20B9E0C4F1CF9B90678B7AC05FA32713`).

## 2. What was studied; derived vs independent

**Studied (no code copied into XIOM):** the Arrow 22.0.0 public headers for
CSV, compute (`CallFunction`, `Filter`, `Take`, `Grouper`), Parquet
(`parquet/arrow/reader.h`, `parquet/arrow/writer.h`) and the
`arrow/compute/row/grouper.h` release-available group-by API. The
`arrow/acero/*` headers were deliberately **not** used.

**Independent (XIOM Authors, MIT OR Apache-2.0):**

- `bridge/xiom_pandas_arrow.cpp` -- handle model, Acero-free group-by and join
  fallbacks, CSV/Parquet I/O, typed builders, Float64 apply, f64-bit filter,
  exception-free C ABI.
- `bridge/pandas_bridge.c` -- offline deterministic stub leg (18 symbols).
- `tests/probe_real_arrow.xi` + `tests/probe_real_arrow_callback.c` --
  end-to-end evidence probe and the test-only C callback.

No Arrow source file is vendored or modified; the bridge calls the public C++
API only.

## 3. Acero-free proof (section-8 decision 1)

The build was verified against an Arrow 22.0.0 include tree with
`arrow/acero` **removed**:

```powershell
# copy pyarrow/include to a scratch tree, then:
Remove-Item -Recurse "<scratch>\arrow\acero"
clang++ -std=c++17 -c packages\xiom-pandas\bridge\xiom_pandas_arrow.cpp `
    -o "$env:TEMP\kilo\xiom_pandas_arrow.o" -I "<scratch>"
llvm-nm -u "$env:TEMP\kilo\xiom_pandas_arrow.o" | Select-String acero   # no output
```

- Compile: success (only the known `ARROW_EXPORT` on `enum class` warning from
  the wheel's header).
- Undefined-symbol scan: no `acero`, `hash_join` or `hash_group_aggregate`
  references.
- Link/probe: `--link arrow --link arrow_compute --link parquet`, **no**
  `--link arrow_acero`; the probe passes.

Group-by uses `arrow::compute::Grouper` (`arrow/compute/row/grouper.h`);
join uses Grouper ids + `arrow::compute::Take`. The absent
`arrow/compute/exec/group_by.h` path confirmed the section-8 fallback choice.

## 4. Parquet component (section-8 decision 6)

`pandas_c_dataframe_from_parquet` uses `parquet::arrow::OpenFile` +
`FileReader::ReadTable`; `pandas_c_dataframe_to_parquet` uses
`parquet::arrow::WriteTable`. Both link the Arrow 22.0.0 `parquet.lib`; the
component's Thrift/zstd/snappy dependencies are transitive (statically linked
into the wheel's `parquet.dll`). No separate Parquet implementation or
third-party stack is used.

`XIOM_PANDAS_HAVE_PARQUET` is derived from `__has_include(<parquet/arrow/...>)`.
If the Parquet headers are absent (or `XIOM_PANDAS_NO_PARQUET` is defined), the
two entry points compile as backend-unavailable stubs (0 / 1), so the bridge
still builds on a Parquet-less Arrow install; the probe reports `[SKIP]` for
that leg. The offline suite never links Parquet.

## 5. Build / probe evidence (verified 2026-10-19)

```powershell
$arrow = "E:\repos\arrow-bin\pyarrow-22.0.0"
$env:CPLUS_INCLUDE_PATH = "<scratch-include-without-arrow/acero>"
$env:PATH = "$arrow\pyarrow;$arrow\pyarrow.libs;$env:PATH"
xiom --run packages\xiom-pandas\tests\probe_real_arrow.xi `
    --cxx-standard 17 `
    --c-source packages\xiom-pandas\bridge\xiom_pandas_arrow.cpp `
    --c-source packages\xiom-pandas\tests\probe_real_arrow_callback.c `
    --link arrow --link arrow_compute --link parquet `
    --link-path "$arrow\pyarrow"
```

Probe result: OK (null contract, CSV round trip, Acero-free group-by,
INNER/LEFT/RIGHT/OUTER joins, Float64 `series_apply`, `filter_f64`, ownership
frees, Parquet round trip). The probe is evidence-only and is not part of
`port.ps1`.

## 6. Re-pin procedure

1. Choose the newest Arrow release whose public headers compile as C++17.
2. Re-pin the tag/commit and the matching pyarrow wheel version/SHA256; verify
   the license.
3. Rebuild `xiom_pandas_arrow.cpp` against the wheel; confirm
   `arrow/compute/row/grouper.h` and the Parquet `OpenFile`/`WriteTable`
   signatures, and keep `arrow/acero` out of the include set.
4. Run the real probe (all legs) and the offline suite twice; record the run
   in `STATUS.json`.
