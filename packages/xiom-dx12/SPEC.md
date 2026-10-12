# SPEC: xiom.dx12 -- Direct3D 12 foundation bindings (0.3.0)

## 1. Identity

| Field | Value |
|-------|-------|
| Package | `xiom.dx12` |
| Version | 0.3.0 |
| Kind | binding (`keywords: ["binding"]`) |
| Upstream (declaration oracle) | `microsoft/DirectX-Headers` @ `461ef513` (nearest stable tag `v1.619.5`); `include/directx/d3d12.h` SHA256 `AFA193D3...`; DXGI: Windows SDK **10.0.26100.0** shared headers (`dxgi.h`/`dxgi1_2..6.h`/`dxgitype.h`/`dxgicommon.h`/`dxgiformat.h`; per-file SHA256 in `PROVENANCE.md`) |
| Runtime | OS `d3d12.dll` + `dxgi.dll`, resolved at runtime (no link dependency; `user32` linked only for the swapchain's hidden window); Agility SDK NOT required or vendored |
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
- **DXGI pin (0.3.0)**: `CreateDXGIFactory2(flags, riid, ppFactory)`; factory
  slots 12 EnumAdapters1 / 15 CreateSwapChainForHwnd / 27 EnumWarpAdapter
  (Factory4 via QI); swapchain slots 8 Present / 9 GetBuffer / 18 GetDesc1;
  `DXGI_ERROR_NOT_FOUND`=0x887A0002; WARP via
  `EnumWarpAdapter(IID_IDXGIAdapter1)`; live witnesses: 3 adapters (vendor
  0x10DE NVIDIA + 0x1414 Basic Render Driver), WARP vendor 0x1414, WARP
  D3D12 device OK, 640x480 BGRA8 (`0x57`) FLIP_DISCARD/FIFO swapchain
  create+GetBuffer+GetDesc1+Present all hr=0.
- **Video pin (0.3.0)**: `ID3D12VideoDevice` QI'd from the live device
  (live ok); `D3D12_COMMAND_LIST_TYPE_VIDEO_DECODE` = 4; the video decode
  command list is created from the core device
  (`CreateCommandList(0, 4, allocator(type 4), NULL, IID_ID3D12VideoDecodeCommandList)`)
  and `Close()` returns 0 (live).  The chain's pointer delivery goes through
  C return values, not XIOM out-slot reads (B-24).
- **B-24 (compiler finding, filed with repro)**: out-slot writes performed
  by a C extern call are intermittently not observed by a subsequent
  `ffi.ptr_read_u64_le` on the same owned slot (stale zero; pointer-shaped
  garbage when the slot holds a pointer).  Byte-indexed reads are reliable;
  the suite uses them exclusively.  Repro:
  `docs/repro/bindings-pilot/ptr-read-stale/` (ffi_bad=2, byte_bad=0 of
  400).  **B-23**: the `null` literal crosses to C extern params as garbage;
  use the bridge's `xd12_null_ptr()`.

## 3. Design: vendored C bridge + staged probe

- `src/dx12_probe.c` (our code, MIT/Apache): hand-rolled COM (no `d3d12.h`
  include) following the `xiom.dxc` precedent; resolves `d3d12.dll` via
  `LoadLibraryA`/`GetProcAddress`; drives objects through raw vtable slots;
  `xd12_unload` releases the device + library (no residue across runs).
- `src/dxgi_probe.c` (0.3.0): the same discipline for `dxgi.dll` --
  factory creation, adapter enumeration, WARP adapter + WARP D3D12 device,
  and a hidden-window BGRA8/FIFO swapchain probe (RegisterClassEx/
  CreateWindowEx -> CreateSwapChainForHwnd -> GetBuffer -> GetDesc1 ->
  Present -> DestroyWindow).  Needs `--link user32`; `dxgi.dll` handling is
  separate state with its own `dxgi_unload`.
- `src/video_probe.c` (0.3.0): pinned video IIDs (`video_iids.inc`), the
  `ID3D12VideoDevice` QI classification, and the C-side video decode
  command-list chain (type-4 allocator -> CreateCommandList with the video
  IID); the list pointer is returned by value so the generated video
  wrappers can drive it.
- `src/d3d12_calls.c` + `src/d3d12_structs.c` + `src/dxgi_calls.c` +
  `src/video_calls.c` + `src/video_structs.c` (generated): normalized slot
  shims for pointer/scalar paths and typed shims for the struct-by-value
  normal forms; `src/d3d12_types.gen.h` / `src/video_types.gen.h` carry the
  C struct closures; `src/struct_meta_1..5.xi` carry the oracle-dumped
  sizes/offsets (`D3D12_*` + `DXGI_*`, 2238 consts).
- The XIOM modules (`dx12.xi`, `src/dxgi.xi`, `src/video.xi`): thin safe
  wrappers; all `unsafe`/`extern` live in `xiom.dx12`,
  `xiom.dx12.dxgi` and `xiom.dx12.video` plus the generated interface
  modules.  Public API adds `dxgi_*` (see README) and
  `dx12_video_probe`, `dx12_video_iid`, `dx12_video_cmdlist_create`/
  `_hr`/`_alloc`/`_cleanup`, `DxgiFactoryInfo`, `DxgiProbeError`, plus
  `dx12_poke_u32/u64` and `dx12_null_ptr` (bridge-provided NULL; the XIOM
  `null` literal marshals garbage to C extern params on v0.64.4 -- B-23).
- **Build:** `port.args.json` compiles the bridges: `--c-source
  ${PACKAGE_DIR}/src/dx12_probe.c` + `d3d12_calls.c` + `d3d12_structs.c` +
  `dxgi_probe.c` + `dxgi_calls.c`, `--link user32`.
- **Classification** (the suite maps it to markers):
  - `DX12_LOAD_ABSENT` / `DXGI_LOAD_ABSENT` -> SKIP (runtime missing; CI
    stays green)
  - `DX12_LOAD_NO_DEVICE` -> SKIP (no D3D12-capable adapter on this host)
  - `DXGI_LOAD_FACTORY` / `DXGI_LOAD_ABI` -> FAIL (never silent)
  - `DXGI_SWAPCHAIN_NO_DEVICE` -> SKIP (swapchain stage only)

## 4. Test matrix (recorded 2026-10-12, compiler v0.64.4)

| Configuration | Command | Result |
|---------------|---------|--------|
| Full (NVIDIA RTX 3070 Ti) | `scripts/port.ps1 -Package xiom.dx12` | **PASS 31/31 x2** -- constants + SKIP classification (three runtimes), device (node_count=1), allocator roundtrip, generated surface (GetNodeCount, CreateCommandQueue + Release, D3D12SerializeRootSignature + typed RS probe 88-byte blob), struct metadata (queue GetDesc sret, committed-buffer Resource::GetDesc, GetResourceAllocationInfo 65536/65536, GetCustomHeapProperties, oracle-vs-build sizeof cross-check), DXGI (factory live, 3 adapters, Adapter1::GetDesc1, WARP adapter + desc, WARP D3D12 device, BGRA8/FIFO 640x480 swapchain + GetBuffer + GetDesc1 + Present), video (`ID3D12VideoDevice` QI, VIDEO_DECODE command list created C-side + generated `Close` = 0), unload paths |
| No runtime / no adapter | deterministic SKIP classification via the bogus-soname paths; `NO_DEVICE` maps to the same SKIP markers | covered by the classification checks |

## 5. Scope

0.3.0 ships the **full D3D12 + DXGI + video surface**: 90 D3D12 interfaces
-> 358 method wrappers (355 + 3 callback-param; the 19 struct-by-value
methods are typed shims), 1162 enum consts, 9 free functions; 43 DXGI
interfaces -> 163 wrappers, 246 consts, 6 free functions; 30 video
interfaces -> 190 wrappers, 661 consts, 10 typed shims; 434 struct sizes +
1804 member offsets (2238 consts); factory/adapter/WARP/swapchain and the
video QI + command-list chain live.  The 97 unparsed struct shapes
(anonymous unions/bitfields/function-pointer members) are listed in
`docs/struct_meta_manifest.json`.  Still next: promotion readiness (policy
sec. 7).
