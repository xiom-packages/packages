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
