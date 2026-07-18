# xiom-vulkan-bridge

A self-contained C11 bridge library that hides all Vulkan + GLFW complexity behind a tiny, flat C ABI.  Designed to let a simple language (XIOM) render graphics without ever touching Vulkan directly.

## ABI Table

All handles are `int64_t` (0 = invalid).  Bools are `int32_t` (0/1).  Angles are radians (`float`).  Colours are `float` in [0,1].

| Function | Parameters | Returns | Purpose |
|---|---|---|---|
| `xvk_app_create` | `(const char* title, int32_t w, int32_t h)` | `int64_t` handle | Full windowed Vulkan setup |
| `xvk_app_destroy` | `(int64_t app)` | `void` | Teardown everything |
| `xvk_app_valid` | `(int64_t app)` | `int32_t` 0/1 | Handle liveness check |
| `xvk_last_error` | `(void)` | `const char*` | Static error string |
| `xvk_app_should_close` | `(int64_t app)` | `int32_t` | `glfwWindowShouldClose` |
| `xvk_app_poll` | `(int64_t app)` | `void` | `glfwPollEvents` |
| `xvk_now` | `(void)` | `double` | `glfwGetTime` seconds |
| `xvk_device_type` | `(int64_t app)` | `int32_t` | `VkPhysicalDeviceType` 0..4 |
| `xvk_begin_frame` | `(int64_t app)` | `int32_t` | 1=OK, 0=skip, -1=fatal |
| `xvk_set_clear_color` | `(int64_t app, float r, g, b)` | `void` | Clear colour for next frame |
| `xvk_end_frame` | `(int64_t app)` | `void` | Submit, present, advance |
| `xvk_draw_triangle_2d` | `(int64_t app, float r, g, b)` | `void` | Screen-filling 2D triangle |
| `xvk_draw_cube_3d` | `(int64_t app, float angle)` | `void` | Rotating lit cube (3D) |
| `xvk_offscreen_create` | `(int32_t w, int32_t h)` | `int64_t` handle | Headless instance + colour target |
| `xvk_offscreen_render_triangle` | `(int64_t app, float r, g, b)` | `int32_t` | Render to offscreen + readback |
| `xvk_offscreen_pixel` | `(int64_t app, int32_t x, int32_t y)` | `uint32_t` | Packed 0xRRGGBBAA pixel value |
| `xvk_offscreen_hash` | `(int64_t app)` | `uint64_t` | FNV-1a hash of whole image |
| `xvk_offscreen_destroy` | `(int64_t app)` | `void` | Teardown offscreen resources |

## Struct Marshalling (`xvk_structs.h/.c`)

Generic byte-offset marshalling layer so XIOM (which has no C struct support) can build and inspect Vulkan structs across the FFI boundary. All handles are raw pointers as `int64_t` (0 = NULL). All accesses use `memcpy` (alignment-safe); NULL handles and negative offsets are no-ops (reads return 0).

| Function | Parameters | Returns | Purpose |
|---|---|---|---|
| `xvk_alloc` | `(int64_t size_bytes)` | `int64_t` handle | `calloc` zeroed block |
| `xvk_free` | `(int64_t handle)` | `void` | Free block |
| `xvk_write_u32` | `(int64_t h, int64_t off, int32_t v)` | `void` | Write uint32 at offset |
| `xvk_write_u64` | `(int64_t h, int64_t off, int64_t v)` | `void` | Write uint64 at offset |
| `xvk_write_f32` | `(int64_t h, int64_t off, float v)` | `void` | Write float32 at offset |
| `xvk_write_str` | `(int64_t h, int64_t off, const char* s)` | `void` | Store pointer to malloc'd copy of string |
| `xvk_write_handle` | `(int64_t h, int64_t off, int64_t vk)` | `void` | Alias of `xvk_write_u64` for VK handles |
| `xvk_write_array` | `(int64_t h, int64_t off, int64_t src, int64_t n, int64_t sz)` | `void` | Copy `n*sz` bytes from `src` block |
| `xvk_read_u32` | `(int64_t h, int64_t off)` | `int32_t` | Read uint32 |
| `xvk_read_u64` | `(int64_t h, int64_t off)` | `int64_t` | Read uint64 |
| `xvk_read_f32` | `(int64_t h, int64_t off)` | `float` | Read float32 |
| `xvk_set_sType` | `(int64_t h, int32_t sType)` | `void` | uint32 at offset 0 |
| `xvk_set_pNext` | `(int64_t h, int64_t pNext)` | `void` | uint64 at offset 8 |

Note: strings written via `xvk_write_str` are owned by the struct's builder; free them by reading the pointer back (`xvk_read_u64`) and calling `xvk_free` before freeing the struct itself.

## Direct Resource Bindings (`xvk_bind_*`)

Thin wrappers over raw Vulkan resource calls. Create-info structs are built
XIOM-side with the `xvk_structs.h` marshalling layer (`xvk_alloc` +
`xvk_write_*`) in exact Vulkan memory layout; the C side enforces `sType`
and calls the real VK function. `device` is a raw `VkDevice` handle,
returns are raw VK handles (0 = failure, error via `xvk_last_error`).
VkResult-returning functions report failures through the same error string.

| Module | Functions |
|---|---|
| `xvk_bind_buffer.h/c` | `xvk_create_buffer`, `xvk_destroy_buffer`, `xvk_bind_buffer_memory`, `xvk_get_buffer_memory_requirements`, `xvk_create_buffer_view`, `xvk_destroy_buffer_view` |
| `xvk_bind_image.h/c` | `xvk_create_image`, `xvk_destroy_image`, `xvk_bind_image_memory`, `xvk_get_image_memory_requirements`, `xvk_create_image_view`, `xvk_destroy_image_view`, `xvk_create_sampler`, `xvk_destroy_sampler` |
| `xvk_bind_memory.h/c` | `xvk_allocate_memory`, `xvk_free_memory`, `xvk_map_memory`, `xvk_unmap_memory`, `xvk_flush_mapped_memory_ranges`, `xvk_invalidate_mapped_memory_ranges` |

Notes: `xvk_get_*_memory_requirements` fills a 24-byte `VkMemoryRequirements`
blob (size u64 @0, alignment u64 @8, memoryTypeBits u32 @16). `xvk_map_memory`
writes the mapped pointer into a caller-provided u64 slot and accepts `-1`
as `VK_WHOLE_SIZE`. Flush/invalidate take a packed `VkMappedMemoryRange[count]`
array (40 bytes per element).

## Direct Vulkan Bindings (`xvk_bind_*`)

Raw 1:1 Vulkan entry points. All object handles are raw Vulkan handles as `int64_t` (0 = `VK_NULL_HANDLE`). `*_struct` parameters are raw pointers (as `int64_t`) to fully-built Vulkan structs produced by the `xvk_structs` marshalling layer. Create functions return the new handle, or 0 on failure (`xvk_last_error` has details); batch create/allocate/free functions return `VkResult` (0 = `VK_SUCCESS`).

| Module | Functions |
|---|---|
| `xvk_bind_pipeline` | `xvk_create_shader_module`, `xvk_destroy_shader_module`, `xvk_create_pipeline_layout`, `xvk_destroy_pipeline_layout`, `xvk_create_graphics_pipelines`, `xvk_create_compute_pipelines`, `xvk_destroy_pipeline`, `xvk_create_pipeline_cache`, `xvk_destroy_pipeline_cache` |
| `xvk_bind_descriptor` | `xvk_create_descriptor_set_layout`, `xvk_destroy_descriptor_set_layout`, `xvk_create_descriptor_pool`, `xvk_destroy_descriptor_pool`, `xvk_allocate_descriptor_sets`, `xvk_free_descriptor_sets`, `xvk_update_descriptor_sets`, `xvk_create_descriptor_update_template`, `xvk_destroy_descriptor_update_template` |
| `xvk_bind_renderpass` | `xvk_create_render_pass`, `xvk_destroy_render_pass`, `xvk_create_framebuffer`, `xvk_destroy_framebuffer` |

`xvk_create_graphics_pipelines` / `xvk_create_compute_pipelines` write `count` pipeline handles into `out_pipelines` (int64 array) and return `VkResult`. `xvk_allocate_descriptor_sets` writes the allocated sets into `out_sets` per the `VkDescriptorSetAllocateInfo` and returns `VkResult`.

## Ray Tracing Bindings (`xvk_bind_raytracing`)

`xvk_bind_raytracing.h/.c` expose the Vulkan ray tracing extensions through the
same flat `int64_t` ABI, but as **raw bindings**: `device`/`cmd_buf` are raw
`VkDevice`/`VkCommandBuffer` handles and `*_struct` parameters are raw pointers
to caller-populated Vulkan structs.

| Extension | Coverage |
|---|---|
| `VK_KHR_acceleration_structure` | create/destroy, build sizes, cmd build (direct + indirect), copies (cmd + host), properties queries, device address, compatibility |
| `VK_KHR_ray_tracing_pipeline` | pipeline creation, trace rays (direct + indirect), shader group handles (+ capture replay), stack sizes |
| `VK_NV_ray_tracing` (legacy) | pipelines, acceleration structures, memory binding, build/copy/trace commands, group handles, `vkCompileDeferredNV` |
| `VK_EXT_micromap` | create/destroy, build (cmd + host), copies, properties, compatibility, build sizes (stubs if headers predate `VK_EXT_opacity_micromap`) |

Extension entry points are resolved via `vkGetDeviceProcAddr` and cached per
device (up to 8 devices). Call `xvk_raytracing_load_device_procs(device)` once
after device creation — it returns an `XVK_RT_CAP_*` capability bitmask and
binds the proc cache used by the `xvk_cmd_*` entry points. `VkResult`-returning
functions pass the raw result through (negative = error, message via
`xvk_last_error()`). Flat-ABI packing rules for the few calls whose Vulkan
signatures exceed the bridge signature (indirect AS builds, NV builds, NV SBT
regions) are documented in `xvk_bind_raytracing.h`.

## Shader Embedding

GLSL source lives under `shaders/`.  An external build step (`build.ps1` / `build.sh`) compiles them to SPIR-V with `glslc` and generates `xvk_shaders_generated.h` containing `unsigned int` arrays plus byte-length constants.  The `.c` file includes this generated header and consumes the symbols:

```
xvk_triangle_vert_spv,  xvk_triangle_vert_spv_len
xvk_triangle_frag_spv,  xvk_triangle_frag_spv_len
xvk_cube_vert_spv,      xvk_cube_vert_spv_len
xvk_cube_frag_spv,      xvk_cube_frag_spv_len
```

### Push-constant layouts

| Pipeline | Stage | Size | Contents |
|---|---|---|---|
| 2D (triangle) | vertex | 16 B | `vec4 color` |
| 3D (cube) | vertex | 64 B | `mat4 mvp` (column-major) |

## Build / Link Requirements

- **Vulkan SDK** ≥ 1.3 (link `vulkan-1.lib` / `libvulkan.so` / `libvulkan.dylib`)
- **GLFW 3.4** (link `glfw3.lib`; define `GLFW_INCLUDE_VULKAN` before including GLFW headers)
- C11 compiler (MSVC, GCC, Clang)
- No `#pragma comment(lib, ...)` — the build system must supply the libraries.

### Quick build (MSVC, x64)
```
cl /nologo /O2 /utf-8 /Ipath\to\VulkanSDK\Include /Ipath\to\GLFW\include
    /c xiom_vk_bridge.c
link /nologo /dll /out:xiom_vk_bridge.dll xiom_vk_bridge.obj
    path\to\vulkan-1.lib path\to\glfw3.lib
```

## Key Design Choices

| Choice | Setting |
|---|---|
| Swapchain surface format | `VK_FORMAT_B8G8R8A8_UNORM` |
| Colour space | `VK_COLOR_SPACE_SRGB_NONLINEAR_KHR` |
| Present mode | `VK_PRESENT_MODE_FIFO_KHR` (guaranteed; will use `MAILBOX` if available) |
| Depth format | `VK_FORMAT_D32_SFLOAT` (falls back to `D24_UNORM_S8_UINT`, `D16_UNORM`) |
| MSAA | None (single-sampled) |
| In-flight frames | 2 (double buffering with VK_FENCE_CREATE_SIGNALED_BIT) |
| Face winding | `VK_FRONT_FACE_COUNTER_CLOCKWISE`, cull back |
| Projection Y flip | **Yes** — the perspective matrix negates row 1,1 (`m[5] = -1/tan(fov/2)`) to account for Vulkan's inverted Y clip space |
| Depth range | Mapped to [0,1] in the projection matrix (Vulkan convention) |
| Validation layers | Off by default; enabled only when env var `XVK_VALIDATION=1` is set AND `VK_LAYER_KHRONOS_validation` is available (fail-soft if unavailable) |

## Limitations / TODOs

- No text rendering, no sprites, no complex geometry — only the two hardcoded draw calls.
- Offscreen path does not support the 3D cube (only 2D triangles).
- No swapchain recreation on window minimize (handle via `xvk_begin_frame` returning 0).
- Error strings are stored in a single static buffer; not thread-safe but adequate for single-threaded XIOM usage.
- The generated shader header (`xvk_shaders_generated.h`) is **not** included in this repository — a build script must produce it.
