# PROVENANCE -- xiom.dx12

Owner policy: docs/UPSTREAM-FIRST.md (upstream-first, 100% coverage).

- **Upstream (declaration oracle):** `microsoft/DirectX-Headers` (MIT),
  clone at `E:\repos\DirectX-Headers`, pinned at commit
  **`461ef5138bd30922b44fbad77c4e47662812d2d5`** (2026-10-09; nearest
  stable tag `v1.619.5`).  Oracle file: `include/directx/d3d12.h`
  (1,692,148 bytes, SHA256
  `AFA193D3BBA5C26EC5C96E0971C6A6EC491C973A06F8CEB0572FBF0F9F9C5441`).
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
- **Derived vs independent:** the GUIDs/vtable order/signatures above are
  **derived** (extracts of the MIT-licensed header); the C bridge
  (`src/dx12_probe.c`, hand-rolled COM -- no d3d12.h include) and all XIOM
  code are original to this package.
- **Coverage plan:** 0.1.0 ships the foundation probe; the **full generated
  surface** (all `ID3D12*` interfaces + free functions + enums/struct
  metadata, parsed from the pinned headers) is the 0.2.0 wave with a
  `docs/COVERAGE.md` oracle==bound==resolved manifest.
- **Clone ledger:** `E:\repos\CLEANUP.md` row `DirectX-Headers` (bindings;
  review after 2026-12-01).
- **License:** header-derived material MIT (notice retained here); package
  code MIT OR Apache-2.0 (repo default).
