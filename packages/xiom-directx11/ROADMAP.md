# xiom-directx11 -- ROADMAP

**Phase 2 (Scientific)** | **Priority: HIGH**
**Depends on**: xiom.ffi (stdlib)
**Platform**: Windows only

## Current Status: SPEC Implementation (v0.1.0)

The package currently contains a full XIOM specification layer:
- All 7 type definitions (DxDevice, DxContext, DxSwapChain, DxBuffer, DxTexture, DxShader, DxSampler)
- 75 constant definitions (DXGI_FORMAT, D3D11_USAGE, D3D11_BIND, D3D11_MAP, D3D11_FILTER, etc.)
- 29 extern "C" raw D3D11 function declarations (d3d11.dll / dxgi.dll)
- 31 safe wrapper functions with requires/ensures contracts
- 65 conformance tests across 21 sections covering types, constants, and stub behavior

All FFI calls return `Err(...)` or stub defaults -- no C bridge is linked yet.

## Phased Roadmap

| Phase | What | Effort | Status |
|-------|------|--------|--------|
| 1 | **SPEC phase** -- Full API surface, contracts, constants, stub tests | Weekend | **DONE** |
| 2 | **C bridge** -- Link d3d11.dll/dxgi.dll, implement extern functions, D3D11CreateDevice bridge | Weekend | TODO |
| 3 | **Hello Triangle** -- End-to-end vertex buffer, input layout, shader, draw pipeline integration test | 1 day | TODO |
| 4 | **Textures & Samplers** -- Texture2D loading, SRV creation, sampler states, PSSetShaderResources | Weekend | TODO |
| 5 | **Constant Buffers** -- CBV management, Map/Unmap data upload, per-draw updates | Weekend | TODO |
| 6 | **Render Targets & Depth/Stencil** -- Render-to-texture, depth testing, multi-RTV | Weekend | TODO |
| 7 | **Compute Shaders** -- UAV, Dispatch, structured buffers, GPU compute pipeline | Weekend | TODO |
| 8 | **Instancing & Multi-pass** -- DrawInstanced, deferred contexts, command lists | Weekend | TODO |

## Phase 2 (C Bridge) Checkpoints

- [ ] Create `directx11_bridge.c` with extern "C" wrappers for the 29 D3D11 functions
- [ ] Link against `d3d11.lib`, `dxgi.lib`, `dxguid.lib`
- [ ] Implement D3D11CreateDeviceAndSwapChain (device + context + swapchain in one call)
- [ ] Implement CreateRenderTargetView back-buffer acquisition from swap chain
- [ ] Wire up shader creation (CreateVertexShader / CreatePixelShader from bytecode)
- [ ] Wire up buffer creation (CreateBuffer with D3D11_BUFFER_DESC)
- [ ] Wire up texture2D creation (CreateTexture2D with D3D11_TEXTURE2D_DESC)
- [ ] Wire up sampler creation (CreateSamplerState with D3D11_SAMPLER_DESC)
- [ ] Wire up input layout creation (CreateInputLayout with D3D11_INPUT_ELEMENT_DESC array)
- [ ] Implement Map/Unmap for dynamic buffer updates
- [ ] Error code -> error message translation (HRESULT -> Str)

## Phase 3 (Hello Triangle) Checkpoints

- [ ] Create window (via raw Win32 CreateWindowEx or xiom-windowing bridge)
- [ ] Create D3D11 device + swap chain
- [ ] Compile VS/PS via xiom-dxc (HLSL -> DXBC bytecode)
- [ ] Create vertex buffer with triangle positions + colors
- [ ] Create input layout matching vertex format
- [ ] Set render targets, viewport, clear, draw, present
- [ ] Screenshot or visual verification

## Contract Coverage

- Device: `Result` with error message on failure
- Swap chain: `requires: width > 0, height > 0`
- Buffer: `requires: size > 0`, constant buffer alignment `size % 16 == 0`
- Texture2D: `requires: width > 0, height > 0`, valid usage enum
- Shader: `Result` on failure, `requires: dev != 0, bytecode != 0, bytecode_len > 0`
- Input layout: `requires: num_elements > 0 && <= 32`
- Sampler: `requires: valid filter enum`, valid address mode per axis
- Map: `requires: valid map_type`
- Context operations: `requires: ctx != 0`
- Render target clear color: `requires: r/g/b/a >= 0.0 && <= 1.0`
- Viewport: `requires: w >= 0.0, h >= 0.0`, depth range `>= 0.0 && <= 1.0`
- Vertex buffer slot: `requires: count >= 0 && <= 32`
- Constant buffer slots: `requires: count >= 0 && <= 16`
- Shader resource slots: `requires: count >= 0 && <= 128`

## File Inventory

| File | Lines | Description |
|------|-------|-------------|
| `directx11.xi` | 580 | Main module: types, 75 constants, 29 extern declarations, 31 safe wrappers |
| `tests/test_conformance.xi` | 496 | 65 conformance tests across 21 sections |
| `SPEC.md` | 61 | Original specification (Phase 2) |
| `ROADMAP.md` | this | Implementation roadmap and checkpoints |
