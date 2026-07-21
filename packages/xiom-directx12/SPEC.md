# xiom-directx12 — SPEC

**Phase**: 2 (Scientific) | **Priority**: HIGH
**Status**: SPEC only — no implementation yet
**Depends on**: xiom.ffi (stdlib)
**Platform**: Windows only

## What it wraps
Direct3D 12 — Microsoft's low-level graphics API. Explicit GPU control.
Used by modern AAA games and professional rendering tools.

## Dependencies

| What | How | Size |
|------|-----|------|
| DirectX 12 SDK | Included in Windows SDK (Windows 10+). | — |
| Windows SDK | System-installed. | ~2GB |
| C++ compiler | MSVC or clang++ | — |

## Bundling strategy
**System-installed only.** DirectX is part of Windows.

## API surface

```xiom
module xiom.directx12

pub type Device        = Int
pub type CommandQueue  = Int
pub type CommandList   = Int
pub type SwapChain     = Int
pub type Resource      = Int
pub type DescriptorHeap = Int
pub type PipelineState = Int
pub type RootSignature = Int
pub type Fence         = Int

// Device
pub fn d3d12_create_device(adapter: Int) -> Result[Device, Str]
pub fn d3d12_create_command_queue(dev: Device, typ: Int) -> Result[CommandQueue, Str]

// Swapchain
pub fn dxgi_create_swapchain(queue: CommandQueue, hwnd: Window, w: Int, h: Int) -> Result[SwapChain, Str]
pub fn d3d12_present(swap: SwapChain, sync: Int)

// Resources (upload + default heaps)
pub fn d3d12_create_upload_buffer(dev: Device, size: Int) -> Result[Resource, Str]
pub fn d3d12_create_default_buffer(dev: Device, size: Int, usage: Int) -> Result[Resource, Str]
pub fn d3d12_create_texture2d(dev: Device, w: Int, h: Int, fmt: Int) -> Result[Resource, Str]

// Commands
pub fn d3d12_create_command_allocator(dev: Device) -> Result[CommandList, Str]
pub fn d3d12_create_graphics_command_list(dev: Device, alloc: Int) -> Result[CommandList, Str]
pub fn d3d12_close_command_list(cl: CommandList)
pub fn d3d12_execute_command_lists(queue: CommandQueue, lists: Vec[CommandList])

// Drawing
pub fn d3d12_clear_rtv(cl: CommandList, rtv: Resource, r: Float32, g: Float32, b: Float32)
pub fn d3d12_draw_instanced(cl: CommandList, vertex_count: Int, instance_count: Int, start: Int)

// Sync
pub fn d3d12_create_fence(dev: Device) -> Result[Fence, Str]
pub fn d3d12_signal_fence(queue: CommandQueue, fence: Fence, val: Int)
pub fn d3d12_wait_fence(fence: Fence, val: Int)
```

## Phased roadmap

| Phase | What | Effort |
|-------|------|--------|
| 1 | Device, swapchain, upload buffer, clear, present | Weekend |
| 2 | Pipeline state, root signatures, draw calls, textures | Weekend |
| 3 | Resource barriers, multi-queue, bindless, ray tracing | Week+ |
