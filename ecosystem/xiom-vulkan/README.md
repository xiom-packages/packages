# xiom-vulkan — Vulkan GPU Bindings

First-party Vulkan bindings for XIOM. Uses a flat-C ABI bridge (`xiom_vk_bridge.c`) that wraps
Vulkan + GLFW into 22 compact functions, with safe XIOM wrappers on top.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  XIOM Application  (demo_2d / demo_3d / demo_particles / demo_shapes / demo_cubes / test) │
├─────────────────────────────────────────────────────────┤
│  xiom.vulkan.wrapper  (VulkanApp type, frame helpers)   │
├─────────────────────────────────────────────────────────┤
│  xiom.vulkan  (extern "C" FFI + safe wrappers)          │
├─────────────────────────────────────────────────────────┤
│  xiom_vk_bridge.c / .h  (flat xvk_* C ABI)             │
├─────────────────────────────────────────────────────────┤
│  vulkan-1  +  glfw3  (native libraries)                 │
└─────────────────────────────────────────────────────────┘
```

Shaders are compiled offline by `glslc` into embedded SPIR-V arrays inside
`xvk_shaders_generated.h`. The bridge links no extra runtime loader — it
calls the Vulkan and GLFW APIs directly.

## Prerequisites

- **Vulkan SDK >= 1.3** — [lunarg.com](https://vulkan.lunarg.com/)
  - Set `VULKAN_SDK` to the installation root (Windows) or system-wide install
  - `glslc` from the SDK (`$VULKAN_SDK/Bin/glslc.exe` or `$VULKAN_SDK/bin/glslc`)
- **GLFW 3.4** — [glfw.org](https://www.glfw.org/)
  - Set `GLFW_DIR` or use `pkg-config` (Linux)
  - Windows: download the pre-compiled binary package
- **clang / LLVM** — [llvm.org](https://llvm.org/) (compiles the C bridge)
- **Rust toolchain** — `cargo` for building the `xiomc` compiler

### Quick SDK reference

| Platform  | Vulkan SDK                  | GLFW                          | Compiler |
|-----------|-----------------------------|-------------------------------|----------|
| Windows   | `$VULKAN_SDK` env var       | `$GLFW_DIR` env var           | LLVM/clang |
| Linux     | `apt install vulkan-sdk`    | `apt install libglfw3-dev`    | clang    |
| macOS     | Vulkan SDK (MoltenVK)       | `brew install glfw`           | clang    |

## Build and Run

### Windows (PowerShell)

```powershell
# 2D demo (coloured triangle)
.\build.ps1

# 3D spinning cube
.\build.ps1 -Target demo3d -Run

# Offscreen test
.\build.ps1 -Target test

# GPU particle fountain
.\build.ps1 -Target particles -Run

# Animated 2D quads + triangle
.\build.ps1 -Target shapes -Run

# Field of spinning 3D cubes
.\build.ps1 -Target cubes -Run
```

### Linux / macOS (bash)

```bash
# 2D demo
./build.sh

# 3D demo
./build.sh demo3d --run

# Offscreen test
./build.sh test

# GPU particle fountain
./build.sh particles --run

# Animated 2D quads + triangle
./build.sh shapes --run

# Field of spinning 3D cubes
./build.sh cubes --run
```

The build scripts run the full pipeline:
1. Compile GLSL shaders to SPIR-V via `glslc`
2. Generate `bridge/xvk_shaders_generated.h` with embedded SPIR-V arrays
3. Compile `xiom_vk_bridge.c` to an object file with clang
4. Invoke `xiomc` to link everything into the final executable

> **Note:** the build scripts use `cargo run -p xiomc` (repo dev workflow).
> Swap to a prebuilt `xiomc` binary for production builds.

## Public API

### Bridge ABI (`xiom_vk_bridge.h`)

```
Lifecycle:     xvk_app_create / xvk_app_destroy / xvk_app_valid / xvk_last_error
Window/events: xvk_app_should_close / xvk_app_poll / xvk_now
Device info:   xvk_device_type
Frame:         xvk_begin_frame / xvk_set_clear_color / xvk_end_frame
2D drawing:    xvk_draw_triangle_2d / xvk_draw_quad_2d
3D drawing:    xvk_draw_cube_3d / xvk_draw_cube_3d_at
Particles:     xvk_particles_enable / xvk_draw_particles
Offscreen:     xvk_offscreen_create / _render_triangle / _pixel / _hash / _destroy
```

### XIOM safe layer (`vulkan.xi`)

```
fn create_app(title: Str, width: Int, height: Int) -> Result[Int, Str]
fn destroy_app(app: Int)
fn app_valid(app: Int) -> Bool
fn should_close(app: Int) -> Bool
fn poll(app: Int)
fn now() -> Float64
fn device_type(app: Int) -> Int
fn begin_frame(app: Int) -> Int
fn set_clear_color(app: Int, r: Float32, g: Float32, b: Float32)
fn end_frame(app: Int)
fn draw_triangle_2d(app: Int, r: Float32, g: Float32, b: Float32)
fn draw_quad_2d(app: Int, r: Float32, g: Float32, b: Float32, x: Float32, y: Float32, w: Float32, h: Float32)
fn draw_cube_3d(app: Int, angle: Float32)
fn draw_cube_3d_at(app: Int, angle: Float32, x: Float32, y: Float32, z: Float32, scale: Float32)
fn particles_enable(app: Int, max_particles: Int) -> Int
fn draw_particles(app: Int)
fn offscreen_create(width: Int, height: Int) -> Result[Int, Str]
fn offscreen_render_triangle(app: Int, r: Float32, g: Float32, b: Float32) -> Bool
fn offscreen_pixel(app: Int, x: Int, y: Int) -> Int
fn offscreen_hash(app: Int) -> Int
fn offscreen_destroy(app: Int)
```

### Wrapper layer (`src/wrapper.xi`)

```
type VulkanApp = { handle: Int, width: Int, height: Int }

VulkanApp.new(title, width, height)      -> Result[VulkanApp, Str]
VulkanApp.is_open()                      -> Bool
VulkanApp.frame_2d(r, g, b)              # poll + begin + clear + draw_2d + end
VulkanApp.frame_3d(angle)                # poll + begin + clear + draw_cube + end
VulkanApp.frame_particles()              # poll + begin + clear + particles_enable + draw_particles + end
VulkanApp.close()                        # destroy_app
```

## Status / Caveats

- This package has **not yet been compiled end-to-end**; it requires the
  SDKs listed above.  Bug reports welcome.
- The offscreen path is **2D-only** (single triangle — no 3D, no depth).
- Validation layers are enabled via environment variable `XVK_VALIDATION=1`.
- Swapchain recreation on window resize is handled internally.

## License

MIT or Apache-2.0, at your option.
