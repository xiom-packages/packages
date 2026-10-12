# PROVENANCE -- xiom.dx12

Owner policy: docs/UPSTREAM-FIRST.md (upstream-first, 100% coverage).

- **Upstream (declaration oracle):** `microsoft/DirectX-Headers` (MIT),
  clone at `E:\repos\DirectX-Headers`, pinned at commit
  **`461ef5138bd30922b44fbad77c4e47662812d2d5`** (2026-10-09; nearest
  stable tag `v1.619.5`).  Oracle file: `include/directx/d3d12.h`
  (1,692,148 bytes, SHA256
  `AFA193D3BBA5C26EC5C96E0971C6A6EC491C973A06F8CEB0572FBF0F9F9C5441`).
- **DXGI declaration oracle (0.3.0):** the Windows SDK
  **10.0.26100.0** shared headers (`dxgi.h`, `dxgi1_2..1_6.h`,
  `dxgitype.h`, `dxgicommon.h`, `dxgiformat.h`).  DXGI interface headers
  are not part of the DirectX-Headers clone; the SDK is the
  Microsoft-shipped source.  SHA256 pins:
  `dxgi.h` `4B983AC75717296191A5FAEF4A87FF0B02B0E8D6202CD5AF85BF75ACCEA2CBBE`,
  `dxgi1_2.h` `437968928AC29F1B5FACB43035B89E85D2AC605F57BDBD354AF94D57D9B3C31A`,
  `dxgi1_3.h` `481308A20158C062D70FEE7801A23D390827DDFE2B40D792CDB31D532650DB99`,
  `dxgi1_4.h` `69F8A3028AFE3560FBB026DBDC3DFA923E17D4A8BFE93173A1737A522FD95E11`,
  `dxgi1_5.h` `B8A349EB873E50E992FFC619E353037C936B9E867407380683A1D949E23FD07D`,
  `dxgi1_6.h` `720F9F871E82118E1A33997558EC1CCD7FBD00E27CFCE13A0B803448F5F99C9F`,
  `dxgitype.h` `1FD2510BB1B5EE2FC240A9505E0FF5FEE603CB80CCC576A7C03780F23337EFFA`,
  `dxgicommon.h` `BEF78AB75F5DD09BF8F8F26FBFC66C6B5770B0EEB968EC4B87934CF8D187F490`,
  `dxgiformat.h` `0AC14D7DA595C528E0F14C64685D83596C392D36A0AB49CE2ECAB05299E6C0D0`.
  `dxgiformat.h` is byte-identical to the DirectX-Headers clone copy;
  `dxgicommon.h` differs from the clone copy by one blank line
  (content-equivalent, same include guard `__dxgicommon_h__`).
- **Runtime:** the OS `d3d12.dll` / `dxgi.dll`, resolved at runtime via
  `LoadLibraryA` + `GetProcAddress` (no link dependency; absent runtime ->
  SKIP).  The **Agility SDK** (`D3D12Core.dll` + the `D3D12SDKVersion`/
  `D3D12SDKPath` bootstrap) is NOT required and NOT vendored; if a newer
  runtime is ever needed for testing it ships as a pinned test-runtime
  only, never as the declaration source.
- **ABI pin (0.1.0)** -- verified against the pinned header:
  - `D3D12CreateDevice(pAdapter, MinimumFeatureLevel, riid, ppDevice)`
    (exported; `_In_opt_` adapter -> NULL = default adapter).
  - `IID_ID3D12Device` = `189819f1-1db6-4b57-be54-1821339b85f7`;
    `IID_ID3D12CommandAllocator` =
    `6102dee4-af59-4b09-b999-b44d73f09b24`.
  - `ID3D12Device` vtable: 0 QueryInterface, 1 AddRef, 2 Release,
    3 GetPrivateData, 4 SetPrivateData, 5 SetPrivateDataInterface,
    6 SetName, 7 GetNodeCount, 8 CreateCommandQueue,
    9 CreateCommandAllocator, ... (ID3D12CommandAllocator: 7 Reset,
    8 GetDesc).
  - `D3D_FEATURE_LEVEL_11_0` = 0xB000; `D3D12_COMMAND_LIST_TYPE_DIRECT` = 0.
- **DXGI ABI pin (0.3.0, verified against the pinned SDK headers):**
  - `CreateDXGIFactory2(flags, riid, ppFactory)` (also `CreateDXGIFactory`,
    `CreateDXGIFactory1`, `DXGIGetDebugInterface1`,
    `DXGIDeclareAdapterRemovalSupport`, `DXGIDisableVBlankVirtualization`).
  - Factory slots: 12 EnumAdapters1, 15 CreateSwapChainForHwnd (Factory2),
    27 EnumWarpAdapter (Factory4, after QI); swapchain slots: 8 Present,
    9 GetBuffer, 18 GetDesc1 (SwapChain1); adapter1 slot 10 GetDesc1.
  - `DXGI_FORMAT_B8G8R8A8_UNORM` = 0x57; `DXGI_USAGE_RENDER_TARGET_OUTPUT`
    = 0x20; `DXGI_SWAP_EFFECT_FLIP_DISCARD` = 4; `DXGI_ERROR_NOT_FOUND` =
    0x887A0002; `DXGI_STATUS_OCCLUDED` = 0x087A0001.
  - WARP: `IDXGIFactory4::EnumWarpAdapter(IID_IDXGIAdapter1)`; live-witnessed
    vendor 0x1414 (5140), `D3D12CreateDevice(warp, 11_0)` succeeds.
- **Derived vs independent:** the GUIDs/vtable order/signatures above are
  **derived** (extracts of the MIT-licensed header); the C bridge
  (`src/dx12_probe.c`, hand-rolled COM -- no d3d12.h include) and all XIOM
  code are original to this package.
- **Struct metadata oracle (0.3.0):** `tools/struct_dump.cpp` is generated
  by `tools/gen_dx12.py --emit-dump` and compiled with **clang** (LLVM,
  MSVC x64 target via `vcvars64`) against the pinned clone headers
  (`-I E:\repos\DirectX-Headers\include\directx`).  Its `sizeof`/`offsetof`
  output is captured to `docs/struct_dump.txt` and turned into
  `src/struct_meta_1..3.xi` by `tools/gen_dx12_struct_meta.py`.  The suite
  cross-checks 16 C `sizeof` values (build compiler) against the dump
  (clang oracle) at runtime.
- **Coverage plan:** the full generated surface (all `ID3D12*` interfaces +
  free functions + enums/struct metadata, parsed from the pinned headers) is
  the 0.2.0/0.3.0 waves with a `docs/COVERAGE.md` oracle==bound==resolved
  manifest.
- **Clone ledger:** `E:\repos\CLEANUP.md` row `DirectX-Headers` (bindings;
  review after 2026-12-01).
- **License:** header-derived material MIT (notice retained here); package
  code MIT OR Apache-2.0 (repo default).
