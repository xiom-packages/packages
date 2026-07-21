# xiom-directx12 — ROADMAP

**Phase 2 (Scientific)** | **Priority: HIGH**
**Depends on**: xiom.ffi (stdlib)
**Platform**: Windows only

## Current Status: SPEC Implementation (v0.1.0)

The package currently contains a full XIOM specification layer:
- All 10 type definitions (DxDevice, DxCommandQueue, DxSwapChain, DxResource, DxDescriptorHeap, DxCommandAllocator, DxCommandList, DxFence, DxRootSignature, DxPipelineState)
- 60 constant definitions (DXGI_FORMAT, D3D12_RESOURCE_STATES, D3D12_COMMAND_LIST_TYPE, D3D12_DESCRIPTOR_HEAP_TYPE, D3D12_FENCE_FLAGS, D3D12_HEAP_TYPE, D3D_PRIMITIVE_TOPOLOGY, D3D12_CLEAR_FLAGS)
- 22 extern "C" raw D3D12 function declarations (d3d12.dll / dxgi.dll)
- 22 safe wrapper functions with requires/ensures contracts (55 requires clauses)
- 65 conformance tests across 21 sections covering types, constants, FFI stub behavior, and API presence

All FFI calls return `Err(...)` or stub defaults — no C bridge is linked yet.

## Phased Roadmap

| Phase | What | Effort | Status |
|-------|------|--------|--------|
| 1 | **SPEC phase** — Full API surface, contracts, constants, stub tests | Weekend | **DONE** |
| 2 | **C bridge** — Link d3d12.dll/dxgi.dll, implement extern functions, D3D12CreateDevice bridge | Weekend | TODO |
| 3 | **Hello Triangle** — End-to-end vertex buffer, PSO, root signature, draw, present | 1 day | TODO |
| 4 | **Textures & Descriptors** — Texture2D, SRV/UAV, descriptor heaps, sampler states | Weekend | TODO |
| 5 | **Resource Barriers** — Transition barriers, upload/default heap sync, copy queue | Weekend | TODO |
| 6 | **Multi-queue & Fences** — Async compute, fence-based sync, multi-frame buffering | Weekend | TODO |
| 7 | **Bindless & Indirect** — Descriptor indexing, ExecuteIndirect, GPU-driven rendering | Weekend | TODO |
| 8 | **Ray Tracing** — DXR state objects, acceleration structures, shader tables | Week+ | TODO |

## Phase 2 (C Bridge) Checkpoints

- [ ] Create `directx12_bridge.c` with extern "C" wrappers for the 22 D3D12 functions
- [ ] Link against `d3d12.lib`, `dxgi.lib`, `dxguid.lib`
- [ ] Implement D3D12CreateDevice (device + debug layer enablement)
- [ ] Implement D3D12CreateCommandQueue with D3D12_COMMAND_QUEUE_DESC
- [ ] Implement CreateSwapChainForHwnd with DXGI_SWAP_CHAIN_DESC1
- [ ] Implement D3D12CreateCommittedResource with D3D12_HEAP_PROPERTIES + D3D12_RESOURCE_DESC
- [ ] Implement D3D12CreateDescriptorHeap with D3D12_DESCRIPTOR_HEAP_DESC
- [ ] Implement D3D12CreateCommandAllocator + D3D12CreateGraphicsCommandList
- [ ] Implement D3D12CreateFence + Signal/Wait fence methods
- [ ] Implement D3D12CreateRootSignature from serialized blob
- [ ] Implement D3D12 present / clear RTV / draw instanced wrappers
- [ ] Error code → error message translation (HRESULT → Str)

## Phase 3 (Hello Triangle) Checkpoints

- [ ] Create window (via raw Win32 CreateWindowEx or xiom-windowing bridge)
- [ ] Create D3D12 device + command queue + swap chain (3 back buffers)
- [ ] Create root signature (empty or single CBV)
- [ ] Compile VS/PS via xiom-dxc (HLSL → DXIL bytecode)
- [ ] Create PSO from root signature + shader bytecodes
- [ ] Create vertex buffer via upload heap → default heap copy
- [ ] Create RTV descriptor heap for swap chain back buffers
- [ ] Record command list: resource barrier, clear RTV, set PSO, draw, barrier to present
- [ ] Execute command list, present, wait for GPU
- [ ] Screenshot or visual verification

## Contract Coverage

- Device: `Result` with error message on failure
- Command queue: `requires: dev != 0`, valid command list type enum
- Swap chain: `requires: width > 0, height > 0, hwnd != 0`
- Resources: `requires: dev != 0, size > 0`, valid heap type
- Texture2D: `requires: width > 0, height > 0`
- Descriptor heap: `requires: num_descriptors > 0 && <= 4096`, valid heap type enum
- Command allocator/list: `requires: alloc != 0`, valid type enum
- Fence: `requires: dev != 0, initial_value >= 0`
- Root signature: `requires: blob != 0, blob_len > 0`
- Pipeline state: `requires: dev != 0, root_sig != 0`
- Clear RTV: `requires: r/g/b/a >= 0.0 && <= 1.0`
- Clear DSV: `requires: depth >= 0.0 && <= 1.0`
- Draw instanced: `requires: vertex_count > 0, instance_count > 0`
- Present: `requires: sync_interval >= 0 && <= 4`
- Execute command lists: `requires: lists.len() > 0`

## File Inventory

| File | Lines | Description |
|------|-------|-------------|
| `directx12.xi` | 501 | Main module: 10 types, 60 constants, 22 extern declarations, 22 safe wrappers |
| `tests/test_conformance.xi` | 651 | 65 conformance tests across 21 sections |
| `SPEC.md` | 85 | Original specification + implementation status |
| `ROADMAP.md` | this | Implementation roadmap and checkpoints |
