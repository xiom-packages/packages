# xiom-vulkan Specification

## Overview

First-party Vulkan bindings for XIOM. Rather than exposing the hundreds of
vk* entry points to XIOM directly, this package wraps Vulkan + GLFW behind a
compact **flat C ABI** (22 functions, no callbacks) and provides safe XIOM
wrappers on top.

## Architecture

### Layers

```
┌─────────────────────────────────────────────────┐
│  XIOM Application (demo_2d, demo_3d, demo_particles, demo_shapes, demo_cubes, …) │
├─────────────────────────────────────────────────┤
│  src/wrapper.xi     (VulkanApp, frame_2d/3d/particles) │
├─────────────────────────────────────────────────┤
│  vulkan.xi          (extern "C" FFI + safe fns)  │
├─────────────────────────────────────────────────┤
│  bridge/xiom_vk_bridge.c/.h  (flat xvk_* C ABI) │
├─────────────────────────────────────────────────┤
│  vulkan-1.dll  /  libvulkan.so  /  glfw3         │
└─────────────────────────────────────────────────┘
```

### Design Decisions

- **C Bridge pattern**: Instead of dynamically loading thousands of vk*
  symbols or generating XIOM bindings for the entire Vulkan spec, we
  implement a deliberately minimal C library that creates a window + device
  + swapchain + pipelines, exposes 22 `xvk_*` functions, and embeds shader
  SPIR-V via a generated header.
- **Offscreen path**: A separate creation path (`xvk_offscreen_create`)
  creates a headless device with a colour-attachment image and readback
  buffer, enabling deterministic, windowless tests.
- **Safety**: The `xiom.vulkan` module wraps every `extern "C"` call in a
  public function with `requires:` contracts. Handles are opaque `Int`
  values; the bridge validates them via a magic-number check.
- **No dynamic shader loading**: Shaders are compiled offline by `glslc`
  and embedded as C uint32 arrays via the build script.

## Bridge API Surface (Flat C ABI)

All functions are declared in `bridge/xiom_vk_bridge.h`:

| Function | Purpose |
|----------|---------|
| `xvk_app_create(title, w, h)` | Create GLFW window + Vulkan device/swapchain/pipelines |
| `xvk_app_destroy(app)` | Full teardown (vkDeviceWaitIdle + all resources) |
| `xvk_app_valid(app)` | Check handle is alive |
| `xvk_last_error()` | Static string describing last error |
| `xvk_app_should_close(app)` | glfwWindowShouldClose |
| `xvk_app_poll(app)` | glfwPollEvents |
| `xvk_now()` | glfwGetTime (seconds) |
| `xvk_device_type(app)` | VkPhysicalDeviceType as int32 |
| `xvk_begin_frame(app)` | Acquire image, begin cmd buffer + render pass. Returns 1=OK, 0=skip, -1=fatal |
| `xvk_set_clear_color(app, r, g, b)` | Set clear colour for next begin_frame |
| `xvk_end_frame(app)` | End render pass, submit, present |
| `xvk_draw_triangle_2d(app, r, g, b)` | Draw triangle via push constant colour |
| `xvk_draw_quad_2d(app, r, g, b, x, y, w, h)` | Draw textured quad (triangle-list, no depth) via push constant transform + colour |
| `xvk_draw_cube_3d(app, angle)` | Draw rotating cube via push constant MVP |
| `xvk_draw_cube_3d_at(app, angle, x, y, z, scale)` | Draw cube at world position — reuses the cube pipeline with an additional world-translation push constant |
| `xvk_particles_enable(app, max_particles)` | Allocate a host-visible vertex buffer for `max_particles` points. Initialises CPU fountain simulation state. Returns 1 on success |
| `xvk_draw_particles(app)` | Upload particle positions from CPU simulation to the host-visible VB, then draw a point-list (particle pipeline). Each point is rendered as a screen-aligned sprite via the particle shaders |
| `xvk_offscreen_create(w, h)` | Headless device + offscreen colour target |
| `xvk_offscreen_render_triangle(app, r, g, b)` | Render triangle, copy to readback buffer |
| `xvk_offscreen_pixel(app, x, y)` | 0xRRGGBBAA pixel from last render |
| `xvk_offscreen_hash(app)` | FNV-1a hash of entire offscreen image |
| `xvk_offscreen_destroy(app)` | Teardown offscreen resources |

### Pipelines

The bridge creates four pipelines at `xvk_app_create` time. Shaders (8 total) are embedded from `xvk_shaders_generated.h`:

| Pipeline | Shaders | Topology | Depth | Notes |
|----------|---------|----------|-------|-------|
| **triangle** | `triangle.vert` / `triangle.frag` | triangle list | enabled | Single colour-triangle, push constant RGB |
| **cube** | `cube.vert` / `cube.frag` | triangle list | enabled | Rotating cube with MVP push constant; reused by `xvk_draw_cube_3d_at` with an added world-offset push constant |
| **quad** | `quad.vert` / `quad.frag` | triangle list | disabled | Textured/batched 2D quads, no depth testing (drawn on top) |
| **particle** | `particle.vert` / `particle.frag` | point list | enabled | Screen-aligned point sprites; vertex data uploaded per-frame from a host-visible vertex buffer filled by the CPU fountain simulation |

**Return value convention:**
- `0` (int64) / `NULL` (pointer) means allocation/creation failure for
  create functions.
- `-1` = fatal error, `0` = transient skip, `1` = success for frame/poll
  functions.
- `xvk_last_error()` always contains the human-readable reason for the
  most recent failure across any call.

## XIOM API Surface

### `xiom.vulkan` (module `vulkan.xi`)

22 public functions with `requires:` contracts mirroring the bridge ABI
but returning `Result[Int, Str]` where applicable.

### `xiom.vulkan.wrapper` (module `src/wrapper.xi`)

Typed convenience layer:

```
type VulkanApp = { handle: Int; width: Int; height: Int }
```

Methods call `poll()` then `begin_frame()` before drawing, then `end_frame()`,
hiding the per-frame lifecycle from the user.

## Lifecycle and Destruction Order

All GPU resources are managed inside `XvkApp` (the opaque handle). The
destruction order enforced by `xvk_app_cleanup_internal()` is:

1. vkDeviceWaitIdle
2. Semaphores, fences (per-frame)
3. Command buffers, command pool
4. Framebuffers
5. Pipelines, pipeline layouts
6. Render pass
7. Swapchain resources (images, views, depth)
8. Offscreen resources (if any)
9. Logical device
10. Surface
11. GLFW window
12. Instance
13. glfwTerminate

The offscreen path shares the same cleanup function, so its resources are
guaranteed to be destroyed in the correct relative order.

## Safety Contracts

- **Handle validation**: Every public `xvk_*` function validates the
  handle via a magic-number check (`XVK_MAGIC`). Zero or poisoned handles
  are rejected silently or return zero.
- **Frame guard**: `xvk_draw_triangle_2d` / `xvk_draw_quad_2d` /
  `xvk_draw_cube_3d` / `xvk_draw_cube_3d_at` / `xvk_draw_particles` /
  `xvk_end_frame` check `a->recording` and are no-ops outside
  begin_frame…end_frame.
- **XIOM contracts**: `requires: app != 0`, `requires: width > 0`,
  `ensures: result is Ok => result.unwrap().handle != 0`.
- **Error propagation**: Bridge stores the last error in a static buffer;
  XIOM layer converts zero-handle returns to `Err(Str)`.

## External Dependencies

| Dependency | Version | Purpose |
|------------|---------|---------|
| Vulkan SDK | >= 1.3 | `vulkan-1.dll` / `libvulkan.so` + headers + `glslc` |
| GLFW | >= 3.4 | Windowing, input, surface creation |
| clang/LLVM | recent | Compiles the C bridge |
| Rust + xiomc | — | XIOM compiler (built from repo via `cargo run -p xiomc`) |

**Link flags** (passed via xiomc `--link`):
- `vulkan-1` (Windows) / `vulkan` (Linux)
- `glfw3`

**Include paths** (for clang bridge compilation):
- `$VULKAN_SDK/Include`
- GLFW include dir (from `GLFW_DIR` or `pkg-config`)

## Build Pipeline

```
                    GLSL shaders (.vert, .frag)
                            │
                      glslc -o .spv
                            │
                  xvk_shaders_generated.h
                (uint32 arrays, computed _len)
                            │
        xiom_vk_bridge.c  +  generated header
                │
          clang -c -I<vk> -I<glfw>
                │
          xiom_vk_bridge.obj / .o
                │
    xiomc --c-source bridge/xiom_vk_bridge.obj \
          --link vulkan-1 --link glfw3          \
          --link-path <vk_lib> --link-path <glfw_lib>
                │
          demo_2d.exe / demo_3d.exe / demo_particles.exe / demo_shapes.exe / demo_cubes.exe
```

### xiomc flags used

| Flag | Purpose |
|------|---------|
| `--c-source <path>` | Pass a `.c`/`.obj`/`.o`/`.lib` file to the linker as an extra input |
| `--link <name>` | Add `-l<name>` to the linker invocation |
| `--link-path <dir>` | Add `-L<dir>` to the linker invocation |
| `--run` | Execute the produced binary after linking (used for tests) |

Shaders are compiled offline only (never at runtime). The generated header
file is listed in `.gitignore` — it must be regenerated whenever the .glsl
sources change.

## Constants

| Name | Value | Meaning |
|------|-------|---------|
| `DEVICE_TYPE_OTHER` | 0 | Unknown device type |
| `DEVICE_TYPE_INTEGRATED` | 1 | Integrated GPU |
| `DEVICE_TYPE_DISCRETE` | 2 | Discrete GPU |
| `DEVICE_TYPE_VIRTUAL` | 3 | Virtual GPU |
| `DEVICE_TYPE_CPU` | 4 | CPU |

## Error Handling Strategy

1. Bridge: static error buffer, set on every failure, read via
   `xvk_last_error()`.
2. XIOM FFI: creation functions returning `0` are converted to
   `Err(xvk_last_error())`.
3. XIOM wrapper: `VulkanApp.new` returns `Result[VulkanApp, Str]`.
4. Frame functions: return codes (`1`/`0`/`-1`) are propagated as-is from
   the bridge; the demo loops handle `0` (skip) and `-1` (break).
