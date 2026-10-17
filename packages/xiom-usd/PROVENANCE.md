# PROVENANCE: xiom.usd

## 1. License check (performed first)

The upstream repository is **PixarAnimationStudios/OpenUSD**. The license at
the pin is **The Tomorrow Open Source Technology License 1.0 (TOST-1.0)**,
not the plain Apache-2.0 text. The license file itself states:

> "Note: The Tomorrow Open Source Technology License 1.0 differs from the
> original Apache License 2.0 in the following manner. Section 6
> ("Trademarks") is different."

The rest of the text is the Apache License 2.0. Section 6 reads:

> "6. Trademarks. This License does not grant permission to use the trade
> names, trademarks, service marks, or product names of the Licensor and its
> affiliates, except as required to comply with Section 4(c) of the License
> and to reproduce the content of the NOTICE file."

TOST-1.0 is therefore **Apache-2.0 class** for this bindings-only use:
permissive, MIT-compatible, no copyleft. The package does not use Pixar/OpenUSD
trademarks beyond nominative references; the NOTICE file is reproduced in
`vendor/NOTICE-OpenUSD.txt`.

| Artifact | SHA256 |
|----------|--------|
| `vendor/LICENSE-OpenUSD.txt` (TOST-1.0) | `2D31950BD9589C55ACF1540D35985FF914D86EF500379E1FA366204846ED63E2` |
| `vendor/NOTICE-OpenUSD.txt` | `F6AD9D41F77B1BD8EDAECD64BD1E13F4224876B010E2415E308267A84862BC14` |
| `vendor/LICENSE-oneTBB.txt` (Apache-2.0) | `1EB85FC97224598DAD1852B5D6483BBCF0AA8608790DCC657A5A2A761AE9C8C6` |

## 2. Upstream pin

| Field | Value |
|-------|-------|
| Repository | https://github.com/PixarAnimationStudios/OpenUSD |
| Tag | **v26.08** |
| Commit | **`ee47c679abde5b467a7b6a41f3b2285564a4222e`** (2026-07-17, "Merge release v26.08") |
| License | TOST-1.0 (see section 1) |
| Clone used | `E:\repos\openusd`, `git clone --depth 1 --filter=blob:none --sparse` then `git fetch --depth 1 origin tag v26.08` + detached checkout; sparse-checkout `pxr/usd pxr/base` |
| Build | **not built**: no CMake, no full C++ tree, no import library |

The header closure was vendored from the pin with
`tools/vendor_headers.ps1` (316 files: `pxr/**` headers + oneTBB headers,
plus the two CMake-configured headers below). Every vendored `#include` that
targets a vendored header was rewritten to an exact relative path (the XIOM
link line has no `-I` passthrough; the same technique as `xiom.assimp`).
No other edits were made to the headers.

Generated headers (from upstream `.in` templates, committed under
`vendor/include`):
- `pxr/pxr.h` from `pxr/pxr.h.in`: major 0 / minor 26 / patch 8,
  `PXR_VERSION 2608`, external namespace `pxr`, internal namespace
  `pxrInternal_v0_26_8`, Python support off.
- `pxr/base/work/impl.h` from `impl.h.in` with the TBB work backend header.

oneTBB headers: **v2021.13.0** (`1c4c93fc5398c4a1acb3492c02db4699f3048dea`,
Apache-2.0) from `E:\repos\oneTBB`; only the transitive closure of the USD
`workTBB` headers is vendored (see `vendor/README.md`).

## 3. Runtime (loader leg)

The preferred runtime is the official **`usd-core` 26.8** wheel. It is
fetched/unpacked, **not redistributed**:

| Field | Value |
|-------|-------|
| Wheel | `usd_core-26.8-cp311-none-win_amd64.whl` |
| Source | https://pypi.org/project/usd-core/26.8/ |
| SHA256 | **`D39CEF20EFDFC29473E92887487BB8C10C45E966C492B5356D32A52724C3578F`** |
| Runtime DLL | `pxr/usd_ms.dll` (monolithic; exports the v26.08 namespace) |
| Runtime metadata | `Version: 26.8`, `License: LicenseRef-TOST-1.0`, `Requires-Python: >=3.9,<3.15` |
| Unpacked local path | `E:\repos\usd-core\wheel` |
| CPython dependency | `usd_ms.dll` imports `python311.dll`; the bridge preloads a CPython 3.11+ runtime from the wheel dir, its parent, or a sibling `pythonNNN` dir. Local proof used the **Python 3.11.9 embeddable** amd64 zip (PSF license; not redistributed). |
| Other deps | `tbb.dll` (wheel dir), the MSVC 2015-2022 x64 runtime (system) |

The wheel's `pxr/pluginfo/` tree is used as `PXR_PLUGINPATH_NAME` by the
loader. The bridge does not vendor or copy any wheel binary.

## 4. Bridge / trampoline model (no import library)

- `src/usd_bridge.cpp` is compiled with the vendored v26.08 headers and
  `PXR_STATIC`; it has **no `usd_ms.dll` import**.
- `tools/gen_trampolines.ps1` compiles the bridge at `-O0` and `-O2`,
  collects the **57** USD function symbols the bridge references (filtered
  to the wheel's export table), and generates
  `src/usd_trampolines.cpp`: one local x64 `jmp` trampoline per symbol plus
  `usdbridge_resolve_all()`, which fills the slots from the loaded DLL.
- The bridge's `usd_runtime_prepare` performs `LoadLibrary` + slot
  resolution + the Sdf pool sync; on any missing symbol it returns
  `RUNTIME_ABI` and frees the DLL.
- An earlier import-library + `delayimp` path was tried and removed: the
  XIOM compiler offers no linker-flag passthrough for `/delayload` (lld-link
  rejects it in `.drectab`), and a static import would break the SKIP gate.
  The trampoline model is the shipped design.

### Data-symbol shims

Delay-loading (and any pure function trampoline) cannot provide the three
**data** symbols the inline USD header code touches. The bridge defines them
locally and adapts them at runtime:

| Symbol | Shipped handling |
|--------|------------------|
| `Sdf_Pool<Sdf_PathPrimTag,24,8,16384>::_regionStarts` | local 257-slot array; exported from the executable; `sync_pools()` mirrors the DLL's table before USD calls |
| `Sdf_Pool<Sdf_PathPropTag,...>::_regionStarts` | same |
| `UsdPrimDefaultPredicate` | local compile-time-equal `Usd_PrimFlagsConjunction` |
| `TfMallocTag::_isInitialized` | local `false` (disables malloc-tag probes in this TU; the DLL keeps its own) |

The pool sync is call-boundary based and deliberately conservative. The
symbol names embed `pxrInternal_v0_26_8__pxrReserved__`; re-pinning requires
regenerating the trampolines and re-checking the pool symbols.

## 5. Cleanup

- The light clone is at `E:\repos\openusd` (no full history; sparse
  `pxr/usd` + `pxr/base`).
- The wheel, unpacked `pxr/` tree and Python 3.11.9 embeddable are at
  `E:\repos\usd-core` (outside the repository; no cleanup required for the
  package but they can be removed to reclaim space).
- The oneTBB clone (`E:\repos\oneTBB`) supplied the vendored TBB header
  closure.
- No build tree, no `.lib`, no delay-import artifacts are part of the
  package.

## 6. Package license

The XIOM package source is **MIT OR Apache-2.0**. The vendored headers keep
their upstream terms (TOST-1.0 / Apache-2.0) and are reproduced with their
license/NOTICE files. The runtime DLLs are downloaded at use time and are
not redistributed.


