# xiom.directx12 -- Roadmap

**Version**: v0.2.0 | **Compiler**: xiom v0.64.1 | **Last updated**: 2026-10-08

## Current state

| Criterion | Status |
|-----------|--------|
| Dynamic loader (no SDK/header/link dependency) | Done -- d3d12.dll + dxgi.dll at runtime |
| Header-free ABI (IIDs/vtables/offsets pinned) | Done |
| G2 pin (sonames + header hashes + ABI) | Done -- `SPEC.md` §2 |
| Capability probe (adapters + max feature level) | Done -- 5/5 x2 (12_2) |
| SKIP/FAIL classification | Done |
| Debug layer / `ID3D12InfoQueue` | Phase 2 |
| Command queue + fences + allocators/lists | Phase 2 |
| Descriptors/heaps + root signatures | Phase 2 |
| Pipelines from `xiom.dxc` DXIL blobs | Phase 2 |
| Swapchain + barriers + first hidden frame | Phase 2 |
| Resource/state layer | Phase 3 |

## Phase 2 (next touches)

1. Debug/devices: enable the debug layer when the SDK's `d3d12sdklayers.dll`
   is present (SKIP otherwise) and surface `ID3D12InfoQueue` messages.
2. Core objects: command queue (`ID3D12Device::CreateCommandQueue`), fences,
   command allocators/lists with a single no-op submission.
3. Descriptors/heaps: CBV/SRV/UAV heap + a root signature for a triangle.
4. Content path: feed the `xiom.dxc` DXIL blob into a pipeline state object
   (file/buffer hand-off; no cross-package imports).
5. Swapchain: hidden-window `IDXGISwapChain3` + resource barriers + one clear
   frame, gated on device capability.
6. Keep the GPU-tier capability probes aligned (opengl/vulkan/dxc/dx11/dx12)
   so a single consumer idiom emerges.
