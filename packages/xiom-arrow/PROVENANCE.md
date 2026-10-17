# PROVENANCE -- xiom.arrow

<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

Owner policy: `docs/UPSTREAM-FIRST.md` (upstream-first, 100% of the declared
surface). This package is an FFI binding (lane gates G2/G6/G7). No upstream
source is copied into the XIOM modules; the real backend compiles against the
Apache Arrow C++ public headers and links the upstream runtime.

## 1. Upstream + pin

| Field | Value |
|-------|-------|
| Project | Apache Arrow -- `https://github.com/apache/arrow` |
| License | Apache-2.0 (ASF); `LICENSE.txt` fetched/verified before checkout (115,734 bytes, Apache License 2.0 text) |
| Study clone | `E:\repos\arrow` -- `git clone --depth 1 --filter=blob:none --sparse --branch apache-arrow-22.0.0`; sparse: `cpp/src/arrow/{c,array,compute,acero,io,csv}`, `cpp/src/parquet`, `cpp/src/arrow/{table,builder,type,chunked_array,record_batch,api}.h`, `LICENSE.txt` |
| Delivered pin | tag **apache-arrow-22.0.0** -- commit `5aeb5f217f1ba39c428c9b481f393bd37097f69e` (2025-10-20) |
| Why 22.0.0 | Newest release whose public headers compile as C++17. Arrow 24+ uses `std::span`/`std::bit_width` in public headers (C++20), which would break the C++17 artifact contract. |
| Runtime artifact | pyarrow **22.0.0** win_amd64 wheel `pyarrow-22.0.0-cp312-cp312-win_amd64.whl`, sha256 `44729980B6C50A5F2BFCC2668D36C569CE17F8B17BCCAF470C4313DCBBF13C9D`; extracted to `E:\repos\arrow-bin\pyarrow-22.0.0` |
| Wheel build identity | `ARROW_PACKAGE_KIND "python-wheel-windows"`, `ARROW_VERSION_STRING "22.0.0"`, `ARROW_CXX_COMPILER_ID "MSVC"`, `ARROW_CXX_COMPILER_VERSION "19.44.35217.0"` |
| Header/lib source | The wheel's `pyarrow/include` (including generated `arrow/util/config.h`) and `pyarrow/arrow.lib`, `arrow_compute.lib`, `arrow_acero.lib`, `parquet.lib`; DLLs `arrow.dll`, `arrow_compute.dll`, `arrow_acero.dll`, `parquet.dll` (+ `pyarrow.libs` VC runtime) |

### Header set pin (sha256)

| File | SHA256 |
|------|--------|
| `arrow/c/abi.h` (clone and wheel identical) | `5B313DF2638D9C927303DA538FB83DAEB76330D04ECE79917F56AB64962E1C7C` |
| `arrow/c/bridge.h` (wheel) | `174C1AF59F5EDFE80C762C2F0DFB5AC584F66A8FD6DE02C6513EB6DF1F114FC1` |
| `arrow/util/config.h` (wheel, generated) | `E220A65B8EC77D055A9F1C82EEA7101A20B9E0C4F1CF9B90678B7AC05FA32713` |

## 2. Artifacts in this package

| File | SHA256 | Role |
|------|--------|------|
| `bridge/arrow_bridge.c` | `3BEB82632D9935F7342197B39C20852CEFC3D2EF8CCEF85974DD8A4B3E2C9EED` | offline stub leg (suite only), 25 symbols + loader/CDI fixture |
| `bridge/arrow_real.cpp` | `4DA36943ADFFA174039883BE5FD80816234CF26169FCE44E8FFBA716CFB0ADAE` | REAL Arrow C++ backend (probe only) |
| `tests/probe_real_backend.xi` | `F3591BE025C542FC9BEAA28E426C551BE202C1C15421779BC3181FC26FEA056A` | real-backend evidence probe |

The pandas-side real bridge prepared by this pass lives outside this package:
`packages/xiom-pandas/bridge/xiom_pandas_arrow.cpp`
(sha256 `D6DB43E671FB9B19235501F701E71787936A8C66F373A12106012A17FAA6D37E`).

## 3. What was studied; derived vs independent

**Studied (no code copied into XIOM):** `cpp/src/arrow/c/abi.h` (CDI struct
layout/release semantics), `cpp/src/arrow/c/bridge.h` + `bridge.cc`
(`Export*/Import*` ownership behavior, including "schema released even on
failure"), `cpp/src/arrow/compute/{exec,api_vector,initialize}.h`, the Arrow 22
CSV reader/writer and Acero option/exec-plan headers.

**Independent (XIOM Authors, MIT OR Apache-2.0):**

- `bridge/arrow_real.cpp` -- handle model, legacy CDI struct holder, typed
  builders, export/import wrappers, release entry points, exception-free C ABI.
- `bridge/arrow_bridge.c` LEG 1 additions -- stubs for the 9 additive symbols
  and the loader/CDI fixture (LEG 2) from the earlier Phase-1/1b pass.
- `tests/probe_real_backend.xi` -- end-to-end evidence probe.
- `packages/xiom-pandas/bridge/xiom_pandas_arrow.cpp` -- 12-symbol real bridge
  (Table hold, CSV, compute filter, Acero aggregate/hashjoin, series, apply).

No Arrow source file is vendored or modified; the bridge calls the public
C++ API only.

## 4. ABI gate evidence (2026-10-17, v0.64.6)

- `clang++ 22.1.8`, target `x86_64-pc-windows-msvc`, `-std=c++17`; Arrow wheel
  built with MSVC 19.44 (compatible MSVC ABI, release CRT).
- Direct object builds of both bridges against `pyarrow/include` succeeded.
- `tests/probe_real_backend.xi` linked and ran against the wheel's import
  libraries/DLLs: 10/10 checks passed, including the zero-copy buffer-address
  identity and exactly-once release checks (full output in `SPEC.md`).
- The pandas side was additionally exercised at the C ABI level with a
  temporary probe covering all 12 symbols: null contract, table/new/set/
  get/filter/groupby/join, series new/from_vec/apply/to_vec, and CSV round trip
  all passed; the temporary probe was deleted after the run and the shipped
  `tests/probe_real_arrow.xi` (CSV leg) is green.
- No ABI mismatch was observed. A note for future re-pins: Arrow 22 splits the
  compute kernels into `arrow_compute.dll`; `arrow::compute::Initialize()` must
  be called (done once in the pandas bridge) because linking alone does not
  load that DLL. Acero node names in Arrow 22 are `"table_source"`,
  `"aggregate"`, `"hashjoin"` (not `hash_group_aggregate`/`hash_join`).

## 5. Re-carve procedure

1. Choose the newest Arrow release whose headers compile as C++17 (or raise the
   artifact language level in SPEC/requirements first).
2. Re-pin `apache-arrow-<ver>` tag/commit and the matching pyarrow wheel
   version/SHA256; re-run the license check.
3. Update the header-set hashes above and `ARROW_*` config identity.
4. Rebuild `arrow_real.cpp` and `xiom_pandas_arrow.cpp` against the wheel;
   re-check Acero node names and compute initialization in the release's
   `arrow/acero/*.h` and `arrow/compute/initialize.h`.
5. Run `tests/probe_real_backend.xi`, `tests/probe_real_arrow.xi`, and both
   offline suites twice; record the run in STATUS.json.
