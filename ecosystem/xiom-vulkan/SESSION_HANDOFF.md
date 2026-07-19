# XIOM Vulkan — Session Handoff File

**Date:** 2026-07-19 | **Bridge:** v0.3.0 | **Compiler:** xiomc v0.48.0
**GPU:** NVIDIA GeForce RTX 3070 Ti | **VK SDK:** 1.4.350.0

---

## Quick Start (copy-paste to resume)

```powershell
cd E:\Projects\AXIOM\ecosystem\xiom-vulkan

# Verify everything compiles:
xiomc --diagnostics=json vulkan_extern.xi
xiomc --diagnostics=json src/vulkan_safe.xi
xiomc --diagnostics=json src/vulkan_structs.xi
xiomc --diagnostics=json vulkan.xi

# Build all 11 demos:
$BrObj="E:\Projects\AXIOM\ecosystem\xiom-vulkan\bridge\xvk_bridge.obj"
xiomc -o demo_2d.exe examples/demo_2d.xi vulkan.xi src/wrapper.xi --c-source $BrObj --link vulkan-1 --link glfw3 --link gdi32 --link user32 --link kernel32 --link shell32 --link ole32 --link-path $env:VULKAN_SDK\Lib --link-path $env:GLFW_DIR\lib-vc2022

# Or use build.ps1:
.\build.ps1 -Target demo2d -Run
.\build.ps1 -Target test -Run
```

---

## Architecture Summary

```
ecosystem/xiom-vulkan/
├── vulkan_extern.xi             755 VK functions (100% VK 1.3 core + extensions)
├── vulkan.xi                    681 lines  Simplified demo API + mouse/keyboard input
├── src/
│   ├── vulkan_safe.xi            1659 lines  30 resource types (SF-01 through SF-12 FIXED)
│   ├── vulkan_structs.xi         1100 lines  30+ create-info struct builders
│   ├── vulkan_constants_all.xi   274KB       3691 VK constants
│   └── wrapper.xi                ~200 lines  Demo helpers (VK_APP_DESTROY etc.)
├── bridge/
│   ├── xiom_vk_bridge.c          36 lines    Master compilation unit (#includes all .c files)
│   ├── xvk_bridge.h              Master header (includes all module headers)
│   ├── xvk_bridge.obj            346KB       Prebuilt x64 object
│   ├── xvk_types.h               Resource types + XvkApp struct
│   ├── xvk_util.h/c              Error reporting, handle helpers
│   ├── xvk_math.h/c              Matrix math
│   ├── xvk_instance.h/c          Instance + device creation
│   ├── xvk_swapchain.h/c         Swapchain management
│   ├── xvk_pipeline.h/c          Pipelines + shader modules + sync objects
│   ├── xvk_renderpass.h/c        Render passes + framebuffers
│   ├── xvk_descriptor.h/c        Descriptor sets (Phase 1)
│   ├── xvk_buffer.h/c            Buffer/image/sampler create/destroy/map
│   ├── xvk_command.h/c           Bind/draw commands + custom passes
│   ├── xvk_query.h/c             Query pool create/destroy/timestamp
│   ├── xvk_legacy.h/c            Legacy drawing API (2D/3D/particles)
│   ├── xvk_offscreen.h/c         Offscreen rendering
│   ├── xvk_frame.h/c             Frame lifecycle (begin/end/clear) + mouse/keyboard input
│   ├── xvk_app.h/c               App lifecycle (create/destroy/poll) + xvk_get_device()
│   ├── xvk_shaders.h             SPIR-V extern declarations
│   ├── xvk_shaders_generated.h   Generated SPIR-V data arrays (15 shaders)
│   ├── xvk_structs.h/c           Struct marshalling (alloc/write/read)
│   ├── xvk_memory_alloc.h/c      [7.1] VMA-style sub-allocator (305 lines)
│   ├── xvk_shader_compile.h/c    [7.3] Runtime GLSL→SPIR-V compilation via glslc
│   ├── xvk_bind_instance.h/c     Raw VK instance/device creation
│   ├── xvk_bind_device.h/c       Raw VK device/queue management (+ get_device_queue2 for 7.5)
│   ├── xvk_bind_buffer.h/c       Raw VK buffer/buffer_view
│   ├── xvk_bind_image.h/c        Raw VK image/image_view/sampler
│   ├── xvk_bind_memory.h/c       Raw VK memory allocation/mapping
│   ├── xvk_bind_pipeline.h/c     Raw VK pipeline + cache serialization (7.2)
│   ├── xvk_bind_descriptor.h/c   Raw VK descriptor sets
│   ├── xvk_bind_renderpass.h/c   Raw VK render pass/framebuffer
│   ├── xvk_bind_command.h/c      Raw VK command buffers (+ threaded pool creation for 7.5)
│   ├── xvk_bind_sync.h/c         Raw VK fences/semaphores/submit (+ multi-submit for 7.5)
│   ├── xvk_bind_query.h/c        Raw VK query pools
│   ├── xvk_bind_swapchain.h/c    Raw VK swapchain/surface (24 functions)
│   ├── xvk_bind_extensions.h/c   Raw VK extensions (82 functions: mesh, video, debug, etc.)
│   └── xvk_bind_raytracing.h/c   Raw VK ray tracing (54 functions: KHR + NV)
├── examples/                     11 demo .xi files
├── tests/
│   ├── test_vulkan.xi            Windowed smoke tests
│   └── ci_smoke.xi               [NEW 8.4] CI smoke: app→buffer→cache→destroy
├── shaders/                      15 GLSL shader sources
├── build.ps1                     Full pipeline (12 targets)
├── run.ps1                       Single-command build+run
├── GETTING_STARTED.md            First-time setup guide
├── API_REFERENCE.md              Every function documented
├── BRIDGE_AUDIT.md               VK 1.3 coverage audit
├── SAFETY_AUDIT.md               All 12 safety bugs documented + fix status
├── VULKAN_ROADMAP.md             Current roadmap with Phase 6/7/8 status
└── AUDIT.md                      Compiler gap tracking (v0.46→v0.48)
```

---

## Completed This Session

### Phase 6: Safety Bug Fixes (ALL 12 FIXED)
- SF-01: `CommandBuffer.allocate` — now allocates `VkCommandBufferAllocateInfo` struct
- SF-02: `DescriptorSet.allocate` — now allocates `VkDescriptorSetAllocateInfo` struct
- SF-03: `CommandBuffer.begin` — now allocates `VkCommandBufferBeginInfo` struct
- SF-04: `CommandBuffer.submit` — now allocates `VkSubmitInfo` with command buffer handle
- SF-05: `CommandBuffer.set_viewport` — now allocates `VkViewport` from 6 params
- SF-06: `CommandBuffer.set_scissor` — now allocates `VkRect2D` from 4 params
- SF-07: `Instance.enumerate_physical_devices` — returns enumerated count, not 0
- SF-08: `VulkanContext.init` — proper physical device enumeration
- SF-09: `Event.get_status` — compares to VK_EVENT_SET (1) not 3
- SF-10: `Buffer.create` — reads size from `VkBufferCreateInfo.size` (offset 24)
- SF-11: `DeviceMemory.allocate` — reads size from `VkMemoryAllocateInfo.allocationSize` (offset 16)
- SF-12: `VulkanContext.destroy` — added `requires: device != 0`

### Phase 7: AAA Features
- 7.1: `xvk_memory_alloc.c/h` — VMA-style memory sub-allocator (linear + free-list, 64MB blocks)
- 7.2: Pipeline cache serialization (get_data_size, get_data, merge_caches in bridge)
- **7.3: `xvk_shader_compile.c/h` — Runtime GLSL→SPIR-V compilation via glslc subprocess** ✅ NEW
  - `xvk_compile_glsl_to_spirv(source, stage, flags)` — compile source string
  - `xvk_compile_glsl_file_to_spirv(filepath, stage, flags)` — compile .vert/.frag file
  - `xvk_free_spirv_result(ptr)` — free allocation
  - High-level API: `shader_compile_glsl()`, `shader_compile_file()`, `spirv_result_size()`, `free_spirv_result()`, `shader_create_raw_spirv()` in vulkan.xi
- **7.5: Multi-thread command pools** ✅ NEW
  - Bridge: `xvk_create_command_pools(count, device, family, flags, out_pools)` — create N pools at once
  - Bridge: `xvk_allocate_command_buffers_multi(device, pool, level, count, out_bufs)` — allocate N CBs
  - Bridge: `xvk_queue_submit_multi(queue, cmd_buf_count, cmd_bufs, fence)` — multi-CB submit
  - Bridge: `xvk_get_device_queue2(device, queue_info_struct, out_queue)` — VkDeviceQueueInfo2 binding
  - Bridge: `xvk_trim_command_pool(device, pool)` — release unused pool resources
  - Safe: `VulkanQueue` type with `get_queue()`, `get_queue2()`, `wait_idle()`, `submit()`, `submit_full()`
  - Safe: `VulkanCommandPool.create_threaded()`, `create_command_pools_multi()`, `trim()`
  - Safe: `VulkanCommandBuffer.submit_multi()`
  - Structs: `build_device_queue_info_2()`, `build_command_buffer_begin_info()`, `build_command_buffer_inheritance_info()`
  - High-level API: `threaded_command_pool_create()`, `allocate_threaded_command_buffers()`, `submit_multi_command_buffers()`, `trim_command_pool()` in vulkan.xi

### Phase 8: Tooling
- 8.2: Mouse/keyboard input (`get_mouse_pos`, `is_mouse_down`, `is_key_down` in vulkan.xi)
- 8.4: CI smoke test (`tests/ci_smoke.xi`)

### Other
- `xvk_get_device(app)` — extracts raw VkDevice from XvkApp for bind module access
- `vulkan_extern.xi` — added `module xiom.vulkan.extern` declaration, fixed double extern block
- `BRIDGE_AUDIT.md` — full VK 1.3 coverage audit (82 real Vulkan calls, 0 stubs)
- `SAFETY_AUDIT.md` — 12 safety bugs documented with line numbers
- `GETTING_STARTED.md` and `API_REFERENCE.md` written

---

## Key Commands

```powershell
cd E:\Projects\AXIOM\ecosystem\xiom-vulkan

# Type-check any file:
xiomc --diagnostics=json vulkan_extern.xi

# Build any demo:
.\build.ps1 -Target demo2d -Run

# Build the C bridge from source:
$env:VULKAN_SDK = "C:\VulkanSDK\1.4.350.0"
$env:GLFW_DIR   = "C:\glfw-3.4.bin.WIN64"
clang -c bridge\xiom_vk_bridge.c -o bridge\xvk_bridge.obj `
  -I"$env:VULKAN_SDK\Include" -I"$env:GLFW_DIR\include" -O2

# Direct xiomc build (no script):
xiomc -o demo_2d.exe examples/demo_2d.xi vulkan.xi src/wrapper.xi `
  --c-source bridge/xvk_bridge.obj `
  --link vulkan-1 --link glfw3 --link gdi32 --link user32 `
  --link kernel32 --link shell32 --link ole32 `
  --link-path $env:VULKAN_SDK\Lib --link-path $env:GLFW_DIR\lib-vc2022 `
  --run
```

---

## Known Issues

1. **Infinite-loop demo crashes** — demos with `while !should_close(a)` crash (0xC0000005). 20-frame limit probes work fine. Root cause: likely bridge cleanup or handle lifetime issue in the render loop after multiple frames.
2. **Compute/test demos hang** — `offscreen_create` doesn't work on all GPU/driver combos (headless without surface).
3. **E001 Float64 warnings** — cosmetic. Use separate `now()` bindings per `math.sin` call.
4. **Float32/Float64 Vec reads** — codegen bug (sitofp instead of bitcast). Use scalar FFI.
5. **Cross-module `use`** — ModuleCatalog doesn't resolve from single file. Multi-file merge on xiomc command line works.
6. **`xvk_get_device` crash** — passing app handle to bind functions that expect raw VK handles causes ACCESS_VIOLATION. The new `xvk_get_device(app)` exposes the raw handle but needs testing.
7. **build.ps1 prebuilt caching** — uses stale `xvk_bridge.obj` if it exists. Delete manually if source changes aren't picked up.

---

## Pending Roadmap Items

| Priority | Item | Notes |
|----------|------|-------|
| P1 | 7.6 Ray tracing deferred host ops | `VK_KHR_deferred_host_operations` — create/join/destroy |
| P1 | 7.4 Texture loading pipeline | KTX/DDS loader, staging→upload→mipmap |
| P2 | 8.1 Debug utils validation output | VkDebugUtilsMessengerCallback in bridge |
| P2 | 8.3 Font/text rendering | stb_truetype + glyph atlas + texture binding |
| P2 | 8.5 Offscreen headless rendering | Fix `xvk_offscreen_create` for headless testing |

---

## Files to Read for Context

1. `BRIDGE_AUDIT.md` — VK 1.3 coverage (82 real calls, ~60 missing features)
2. `SAFETY_AUDIT.md` — All 12 safety bugs + fix status
3. `VULKAN_ROADMAP.md` — Current roadmap with Phase 6/7/8 status
4. `GETTING_STARTED.md` — First-time setup
5. `API_REFERENCE.md` — Every function documented
6. `AUDIT.md` — Compiler gap history (v0.46→v0.48)
