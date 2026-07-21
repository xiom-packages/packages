# xiom-directx11 — SPEC

**Phase**: 2 (Scientific) | **Priority**: HIGH
**Status**: IMPLEMENTED (v0.1.0 SPEC phase)
**Depends on**: xiom.ffi (stdlib)
**Platform**: Windows only

## What it wraps
Direct3D 11 — Microsoft's graphics API (Windows). Part of the DirectX SDK.
Used by AAA games, CAD tools, Windows desktop apps with GPU rendering.

## Dependencies

| What | How | Size |
|------|-----|------|
| DirectX SDK | Included in Windows SDK. No separate install needed on Windows 10+. | — |
| Windows SDK | System-installed. Part of Visual Studio or `winget install Microsoft.WindowsSDK`. | ~2GB |
| C++ compiler | MSVC or clang++ | — |

## Bundling strategy
**System-installed only.** DirectX is part of Windows. No bundling needed.

## SPEC Phase Implementation (v0.1.0)

All FFI calls return `Err(...)` or stub defaults — no C bridge is linked yet. The module provides:

### Types (7)
DxDevice, DxContext, DxSwapChain, DxBuffer, DxTexture, DxShader, DxSampler

### Constants (75)
- DXGI_FORMAT (17): UNKNOWN, R32G32B32A32_FLOAT/UINT, R32G32B32_FLOAT/UINT, R32G32_FLOAT, R32_FLOAT/UINT, R8G8B8A8_UNORM/UINT/SNORM, B8G8R8A8_UNORM, R16G16B16A16_FLOAT, R16G16_FLOAT, R16_FLOAT, D24_UNORM_S8_UINT, D32_FLOAT, D32_FLOAT_S8X24_UINT
- D3D11_USAGE (4): DEFAULT, IMMUTABLE, DYNAMIC, STAGING
- D3D11_CPU_ACCESS_FLAG (2): WRITE, READ
- D3D11_BIND_FLAG (8): VERTEX_BUFFER, INDEX_BUFFER, CONSTANT_BUFFER, SHADER_RESOURCE, STREAM_OUTPUT, RENDER_TARGET, DEPTH_STENCIL, UNORDERED_ACCESS
- D3D11_PRIMITIVE_TOPOLOGY (6): UNDEFINED, POINTLIST, LINELIST, LINESTRIP, TRIANGLELIST, TRIANGLESTRIP
- D3D11_MAP (5): READ, WRITE, READ_WRITE, WRITE_DISCARD, WRITE_NO_OVERWRITE
- D3D11_FILTER (9): MIN_MAG_MIP_POINT through ANISOTROPIC
- D3D11_TEXTURE_ADDRESS_MODE (5): WRAP, MIRROR, CLAMP, BORDER, MIRROR_ONCE
- D3D11_INPUT_CLASSIFICATION (2): PER_VERTEX_DATA, PER_INSTANCE_DATA
- D3D_DRIVER_TYPE (4): HARDWARE, WARP, REFERENCE, SOFTWARE
- D3D11_CREATE_DEVICE_FLAG (3): DEBUG, SINGLETHREADED, BGRA_SUPPORT
- D3D11_SRV_DIMENSION (10): UNKNOWN through TEXTURECUBE

### extern "C" Functions (29)
Device creation: D3D11CreateDevice, D3D11CreateDeviceAndSwapChain
Swap chain: CreateSwapChain, Present
Render targets: CreateRenderTargetView, ClearRenderTargetView, OMSetRenderTargets
Buffers: CreateBuffer
Textures: CreateTexture2D, CreateShaderResourceView
Samplers: CreateSamplerState
Shaders: CreateVertexShader, CreatePixelShader, CreateInputLayout
Pipeline state: IASetInputLayout, IASetVertexBuffers, IASetIndexBuffer, IASetPrimitiveTopology, VSSetShader, PSSetShader, VSSetConstantBuffers, PSSetConstantBuffers, PSSetSamplers, PSSetShaderResources, RSSetViewports
Drawing: Draw, DrawIndexed
Mapping: Map, Unmap

### Safe Wrappers (31)
All wrappers include `requires` contracts for handle validation, enum checking, and value range constraints. Functions returning GPU resources return `Result[T, Str]` with Err in stump mode.

### Tests (65)
21 sections covering types, all constant groups, stub return behavior, smoke (all non-Result callable, all Result return Err), and full pipeline lifecycle simulation.

## Phased roadmap

| Phase | What | Effort | Status |
|-------|------|--------|--------|
| 1 | Device, swapchain, clear, present, basic triangle | Weekend | **DONE** (SPEC) |
| 2 | Buffers, shaders, textures, constant buffers | Weekend | **DONE** (SPEC) |
| 3 | Compute shaders, multi-pass rendering, deferred context | Week | TODO |
| 4 | C bridge — Link d3d11.dll/dxgi.dll, wire extern functions | Weekend | TODO |

## File Inventory

| File | Lines | Description |
|------|-------|-------------|
| `directx11.xi` | 580 | Main module: 7 types, 75 constants, 29 extern declarations, 31 safe wrappers |
| `tests/test_conformance.xi` | 496 | 65 conformance tests across 21 sections |
| `SPEC.md` | this | Updated specification with implementation status |
| `ROADMAP.md` | 97 | Implementation roadmap and phase checkpoints |
