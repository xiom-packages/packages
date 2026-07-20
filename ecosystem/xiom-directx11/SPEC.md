# xiom-directx11 — SPEC

**Phase**: 2 (Scientific) | **Priority**: HIGH
**Status**: SPEC only — no implementation yet
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

## API surface

```xiom
module xiom.directx11

pub type Device        = Int
pub type DeviceContext = Int
pub type SwapChain     = Int
pub type Texture2D     = Int
pub type Buffer        = Int
pub type Shader        = Int

// Device + swapchain
pub fn d3d11_create_device(adapter: Int, flags: Int) -> Result[(Device, DeviceContext), Str]
pub fn d3d11_create_swapchain(dev: Device, hwnd: Window, w: Int, h: Int) -> Result[SwapChain, Str]

// Buffers
pub fn d3d11_create_vertex_buffer(dev: Device, data: Vec[Float32], stride: Int) -> Result[Buffer, Str]
pub fn d3d11_create_index_buffer(dev: Device, data: Vec[Int32]) -> Result[Buffer, Str]
pub fn d3d11_create_constant_buffer(dev: Device, size: Int) -> Result[Buffer, Str]

// Shaders
pub fn d3d11_compile_vertex_shader(dev: Device, source: Str, entry: Str) -> Result[Shader, Str]
pub fn d3d11_compile_pixel_shader(dev: Device, source: Str, entry: Str) -> Result[Shader, Str]

// Drawing
pub fn d3d11_clear(ctx: DeviceContext, r: Float32, g: Float32, b: Float32)
pub fn d3d11_draw(ctx: DeviceContext, vertex_count: Int, start: Int)
pub fn d3d11_draw_indexed(ctx: DeviceContext, index_count: Int, start: Int, base: Int)
pub fn d3d11_present(swap: SwapChain, sync: Int)
```

## Phased roadmap

| Phase | What | Effort |
|-------|------|--------|
| 1 | Device, swapchain, clear, present, basic triangle | Weekend |
| 2 | Buffers, shaders, textures, constant buffers | Weekend |
| 3 | Compute shaders, multi-pass rendering, deferred context | Week |
