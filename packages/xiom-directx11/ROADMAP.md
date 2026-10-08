# xiom.directx11 -- Roadmap

**Version**: v0.2.0 | **Compiler**: xiom v0.64.1 | **Last updated**: 2026-10-08

## Current state

| Criterion | Status |
|-----------|--------|
| Dynamic loader (no SDK/header/link dependency) | Done -- d3d11.dll + dxgi.dll at runtime |
| Header-free ABI (vtables/offsets pinned) | Done |
| G2 pin (sonames + header hashes + ABI) | Done -- `SPEC.md` §2 |
| Capability probe (device + feature level + adapter) | Done -- 5/5 x2 |
| SKIP/FAIL classification | Done |
| Device flags / debug layer / WARP | Phase 2 |
| Feature-level requests (11_1 explicit) | Phase 2 |
| Swapchain + render targets (hidden window) | Phase 2 |
| Shader hand-off from `xiom.dxc` (HLSL -> DXIL) | Phase 2 |
| Resource/state layer (buffers, textures, views) | Phase 3 |

## Phase 2 (next touches)

1. `d3d11_create_device(flags, feature_levels)` with explicit feature-level
   requests and the debug layer; report the negotiated level.
2. Swapchain: hidden-window `IDXGISwapChain` (via `D3D11CreateDeviceAndSwapChain`
   or `IDXGIFactory::CreateSwapChain`) behind a capability gate; present one
   clear frame like the sdl3/raylib suites.
3. Shader pipeline: feed the `xiom.dxc` DXIL blob into
   `ID3D11Device::CreatePixelShader`/`CreateVertexShader` (package-to-package
   content flow stays file/buffer based -- no cross-package imports).
4. Resource layer: buffers, textures, render-target views, input layouts.
5. Re-evaluate the shared probe/bridge shape across the GPU tier
   (opengl/vulkan/dxc/dx11/dx12) for a common capability-reporting idiom.
