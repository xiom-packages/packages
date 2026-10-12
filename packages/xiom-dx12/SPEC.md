# SPEC: xiom.dx12 -- Direct3D 12 foundation bindings (0.3.0)

## 1. Identity

| Field | Value |
|-------|-------|
| Package | `xiom.dx12` |
| Version | 0.3.0 |
| Kind | binding (`keywords: ["binding"]`) |
| Upstream (declaration oracle) | `microsoft/DirectX-Headers` @ `461ef513` (nearest stable tag `v1.619.5`); `include/directx/d3d12.h` SHA256 `AFA193D3BBA5C26EC5C96E0971C6A6EC491C973A06F8CEB0572FBF0F9F9C5441` |
| Runtime | OS `d3d12.dll`, resolved at runtime (no link dependency); Agility SDK NOT required or vendored |
| Package license | MIT OR Apache-2.0 |
| Platform | Windows x64 |
| Compiler pin | v0.64.4 |

## 2. ABI pin (verified against the pinned header)

- `D3D12CreateDevice(IUnknown* pAdapter, D3D_FEATURE_LEVEL MinimumFeatureLevel, REFIID riid, void** ppDevice)`; `pAdapter = NULL` selects the default adapter; `11_0` (0xB000) is the D3D12 minimum level.
- `IID_ID3D12Device` = `189819f1-1db6-4b57-be54-1821339b85f7`.
- `IID_ID3D12CommandAllocator` = `6102dee4-af59-4b09-b999-b44d73f09b24`.
- `ID3D12Device` vtable: 0 QueryInterface, 1 AddRef, 2 Release, 3 GetPrivateData, 4 SetPrivateData, 5 SetPrivateDataInterface, 6 SetName, **7 GetNodeCount, 8 CreateCommandQueue, 9 CreateCommandAllocator**, 10 CreateGraphicsPipelineState, 11 CreateComputePipelineState, 12 CreateCommandList, ..., **25 GetResourceAllocationInfo, 26 GetCustomHeapProperties, 27 CreateCommittedResource**; `ID3D12CommandAllocator`: ..., 7 Reset, 8 GetDesc.
- `D3D12_COMMAND_LIST_TYPE_DIRECT/BUNDLE/COMPUTE/COPY` = 0/1/2/3;
  `D3D_FEATURE_LEVEL_11_0/11_1/12_0/12_1/12_2` = 0xB000/0xB100/0xC000/0xC100/0xC200.
- **x64 member return convention (0.3.0 pinned)**: a COM method returning a
  struct > 8 bytes passes the hidden out pointer in **RDX after `this`**
  (RCX=this, RDX=sret, visible args shift right), unlike a free function
  (RCX=sret). The typed shims declare `void (WINAPI *FN)(void* self, void*
  out, ...)` so the generated call matches exactly and the out pointer IS
  the XIOM-owned slot (verified live against the OS runtime). By-value
  struct params pass a pointer to a caller-owned copy.
- **D3D12_COMMAND_QUEUE_PRIORITY**: only the enum values `NORMAL=0`,
  `HIGH=100`, `GLOBAL_REALTIME=10000` are accepted by `CreateCommandQueue`
  (live-verified: `1` -> `E_INVALIDARG`).
- **Buffers**: `D3D12_RESOURCE_DESC.Layout` must be `ROW_MAJOR` (1) for
  buffers (live-verified: `UNKNOWN` -> allocation info `UINT64_MAX`/65536
  and `CreateCommittedResource` -> `E_INVALIDARG`).

## 3. Design: vendored C bridge + staged probe

- `src/dx12_probe.c` (our code, MIT/Apache): hand-rolled COM (no `d3d12.h`
  include) following the `xiom.dxc` precedent; resolves `d3d12.dll` via
  `LoadLibraryA`/`GetProcAddress`; drives objects through raw vtable slots;
  `xd12_unload` releases the device + library (no residue across runs).
- `src/d3d12_calls.c` + `src/d3d12_structs.c` (generated): normalized slot
  shims for pointer/scalar paths and typed shims for the struct-by-value
  normal forms; `src/d3d12_types.gen.h` carries the C struct closure used
  by the typed shims; `src/struct_meta_1..3.xi` carry the oracle-dumped
  sizes/offsets.
- The XIOM module (`dx12.xi`, module `xiom.dx12`) is a thin safe wrapper:
  all `unsafe`/`extern` are confined to this single module (G5). Public API:
  `dx12_probe`, `dx12_probe_named`, `dx12_unload`, `Dx12DeviceInfo`,
  `Dx12ProbeError`, the pinned constants, `dx12_poke_u32/u64` and
  `dx12_null_ptr` (bridge-provided NULL; the XIOM `null` literal marshals
  garbage to C extern params on v0.64.4 -- B-23).
- **Build:** `port.args.json` compiles the bridge: `--c-source
  ${PACKAGE_DIR}/src/dx12_probe.c` + `d3d12_calls.c` + `d3d12_structs.c`
  (no `--link` flags needed).
- **Classification** (the suite maps it to markers):
  - `DX12_LOAD_ABSENT` -> SKIP (runtime missing; CI stays green)
  - `DX12_LOAD_NO_DEVICE` -> SKIP (no D3D12-capable adapter on this host)
  - `DX12_LOAD_ABI` -> FAIL (present but exports missing; never silent)

## 4. Test matrix (recorded 2026-10-12, compiler v0.64.4)

| Configuration | Command | Result |
|---------------|---------|--------|
| Full (NVIDIA RTX 3070 Ti) | `scripts/port.ps1 -Package xiom.dx12` | **PASS 18/18 x2** -- constants + SKIP classification, device (node_count=1), allocator roundtrip, generated-surface (GetNodeCount, CreateCommandQueue + Release, D3D12SerializeRootSignature wrapper + typed RS probe 88-byte blob), struct metadata (queue GetDesc sret, committed-buffer CreateCommittedResource + Resource::GetDesc, GetResourceAllocationInfo 65536/65536, GetCustomHeapProperties, oracle-vs-build sizeof cross-check 16 structs), unload |
| No runtime / no adapter | deterministic SKIP classification via the bogus-soname path; `NO_DEVICE` maps to the same SKIP markers | covered by the classification checks |

## 5. Scope

0.3.0 ships the **struct-metadata wave** on top of the full generated
`d3d12.h` core surface (90 interfaces -> 358 method wrappers: 355 + 3
callback-param; the 19 struct-by-value methods are typed shims), 1162 enum
consts, 9 free functions, **240 struct sizes + 863 member offsets** as
`struct_meta_1..3` constants, and the typed-shim closure with oracle-vs-build
sizeof probes. The 55 unparsed struct shapes (anonymous unions/bitfields/
function-pointer members) are listed in `docs/struct_meta_manifest.json`.
Still next: DXGI (`dxgi.dll`: factory/adapter/WARP/swapchain),
`d3d12video.h`, then promotion.
