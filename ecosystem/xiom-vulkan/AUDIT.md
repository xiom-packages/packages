# xiom-vulkan — Build Dependency Audit

## Required Dependencies

| Dependency | Version | Purpose |
|-----------|---------|---------|
| Vulkan SDK | >= 1.3 | GPU API (headers + loader) |
| GLFW | >= 3.4 | Window creation + Vulkan surface |
| clang/LLVM | >= 14 | C bridge compilation |
| glslc | >= 1.3 (Vulkan SDK) | GLSL → SPIR-V shader compilation |
| Rust/Cargo | Latest stable | Compiler build (xiomc) |
| xiomc | >= v0.45.3 | XIOM compiler |
| xiom-ffigen | v0.10.1 | FFI binding generator (optional, manual binding also supported) |

## Platform-Specific Installation

### Windows
1. **Vulkan SDK**: Install from https://vulkan.lunarg.com/sdk/home
   - Sets `VULKAN_SDK` environment variable automatically
   - Provides `glslc.exe` in `$VULKAN_SDK\Bin`
2. **GLFW**: See `xiom-glfw/AUDIT.md` or set `GLFW_DIR`
3. **clang**: Install via LLVM from https://releases.llvm.org/ or `winget install LLVM.LLVM`

### Linux
```bash
# Vulkan SDK
# Ubuntu: https://vulkan.lunarg.com/doc/view/latest/linux/getting_started_ubuntu.html
# Arch: sudo pacman -S vulkan-devel glslang

# GLFW
sudo apt install libglfw3-dev

# clang
sudo apt install clang
```

### macOS
```bash
# Vulkan SDK
# Download from https://vulkan.lunarg.com/sdk/home

# GLFW
brew install glfw

# clang
# Ships with Xcode Command Line Tools
```

## Build Pipeline (4 steps)

The `build.ps1` script implements a 4-step pipeline:

```
1. GLSL Shaders → SPIR-V (glslc)
   shaders/triangle.vert/.frag → spv/triangle_vert.spv/.frag.spv
   shaders/cube.vert/.frag    → spv/cube_vert.spv/.frag.spv
   shaders/quad.vert/.frag    → spv/quad_vert.spv/.frag.spv
   shaders/particle.vert/.frag → spv/particle_vert.spv/.frag.spv

2. SPIR-V → Generated Header (PowerShell)
   Reads .spv files → xvk_shaders_generated.h (C arrays)

3. C Bridge (clang)
   bridge/xiom_vk_bridge.c → bridge/xiom_vk_bridge.obj

4. XIOM Compilation + Link (xiomc + clang)
   vulkan.xi + src/wrapper.xi + examples/*.xi + bridge/*.obj
   → final executable linked with vulkan-1 + glfw3
```

### Windows (PowerShell)
```powershell
.\build.ps1 -Target demo2d -Run
.\build.ps1 -Target demo3d -Run
.\build.ps1 -Target particles -Run
.\build.ps1 -Target shapes -Run
.\build.ps1 -Target cubes -Run
.\build.ps1 -Target test -Run
```

### Linux/macOS (Bash)
```bash
./build.sh demo2d
./build.sh test
```

## Compile Status (2026-07-15)

### Existing Files (unchanged)
| File | Status | Notes |
|------|--------|-------|
| `vulkan.xi` | PASSED | xvk C bridge FFI + safe wrappers |
| `src/wrapper.xi` | PASSED (multi-file) | VulkanApp convenience layer |
| `examples/demo_2d.xi` | PASSED (multi-file) | |
| `examples/demo_3d.xi` | PASSED (multi-file) | |
| `examples/demo_cubes.xi` | PASSED (multi-file) | |
| `examples/demo_particles.xi` | PASSED (multi-file) | |
| `examples/demo_shapes.xi` | PASSED (multi-file) | |
| `tests/test_vulkan.xi` | PASSED (multi-file) | |
| `bridge/xiom_vk_bridge.c` | N/A (unchanged) | C source |

### New Files (2026-07-15)
| File | Status | Lines | Contents |
|------|--------|-------|----------|
| `vulkan_extern.xi` | PASSED | ~350 | 120+ `extern "C"` vk* FFI declarations, re-exports constants |
| `src/vulkan_constants.xi` | PASSED | ~90 | VkResult, VkStructureType, VkFormat enums |
| `src/vulkan_constants2.xi` | PASSED | ~88 | Image layout, usage flags, pipeline stages, access flags |
| `src/vulkan_constants3.xi` | PASSED | ~38 | Misc enums (cull, compare, topology, blend, etc.) |
| `src/vulkan_safe.xi` | PASSED (E001 borrow warnings) | ~410 | Struct-based safe wrappers for 7 resource types |

## New FFI Bindings (vulkan_extern.xi)

120+ Vulkan 1.3 core functions (+ KHR surface/swapchain + EXT debug utils/debug markers) across:

| Category | Functions | Examples |
|----------|-----------|----------|
| Instance | 6 | vkCreateInstance, vkDestroyInstance, vkEnumerateInstanceVersion |
| Physical Device | 17 | vkEnumeratePhysicalDevices, vkGetPhysicalDeviceProperties*, Surface queries |
| Device | 6 | vkCreateDevice, vkDestroyDevice, vkDeviceWaitIdle, vkGetDeviceQueue* |
| Memory | 11 | vkAllocateMemory, vkMapMemory, vkFlushMappedMemoryRanges, vkGet*MemoryRequirements |
| Buffer | 7 | vkCreateBuffer, vkBindBufferMemory*, vkGetBufferDeviceAddress |
| Image | 7 | vkCreateImage, vkCreateImageView, vkGetImageSubresourceLayout |
| Command Pool/Buffer | 9 | vkCreateCommandPool, vkAllocateCommandBuffers, vkBeginCommandBuffer |
| Draw/State/Copy | 38 | vkCmdDraw, vkCmdBindDescriptorSets, vkCmdPipelineBarrier, vkCmdCopyBuffer* |
| Render Pass/Framebuffer | 13 | vkCreateRenderPass, vkCmdBeginRenderPass*, vkCreateFramebuffer |
| Dynamic Rendering | 2 | vkCmdBeginRendering, vkCmdEndRendering |
| Pipeline | 9 | vkCreateGraphicsPipelines, vkCreateComputePipelines, vkCreatePipelineLayout |
| Shader Module | 2 | vkCreateShaderModule, vkDestroyShaderModule |
| Descriptor Sets | 11 | vkCreateDescriptorSetLayout, vkAllocateDescriptorSets, vkUpdateDescriptorSets |
| Sampler | 2 | vkCreateSampler, vkDestroySampler |
| Sync (Fence/Semaphore/Event) | 12 | vkCreateFence, vkWaitForFences, vkCreateSemaphore |
| Query Pool | 4 | vkCreateQueryPool, vkGetQueryPoolResults |
| Queue | 4 | vkQueueSubmit*, vkQueueWaitIdle |
| Swapchain (KHR) | 7 | vkCreateSwapchainKHR, vkAcquireNextImageKHR, vkQueuePresentKHR |
| Surface (KHR) | 1 | vkDestroySurfaceKHR |
| Debug Utils (EXT) | 6 | vkCreateDebugUtilsMessengerEXT, vkCmdBeginDebugUtilsLabelEXT |
| Dynamic State | 13 | vkCmdSetCullMode, vkCmdSetDepthTestEnable, vkCmdSetPrimitiveTopology |
| Image Transitions | 3 | vkTransitionImageLayout, vkCopyMemoryToImage |

**Total: ~120 extern function declarations + ~220 enum constants across 3 split files.**

## Safe Wrappers (src/vulkan_safe.xi)

7 struct-based resource types with `create/destroy` lifecycle and `Result[T, VulkanError]` error handling:

| Type | Methods | Contracts |
|------|---------|-----------|
| `VulkanInstance` | create, destroy, is_valid | requires: create_info != 0; ensures: handle != 0 |
| `VulkanDevice` | create, destroy, wait_idle, get_queue | requires: physical_device != 0 |
| `VulkanBuffer` | create, destroy, bind_memory, map, unmap | requires: size > 0 for map |
| `VulkanImage` | create, destroy, bind_memory | requires: device != 0 |
| `VulkanPipeline` | create_graphics, create_compute, destroy | requires: create_info != 0 |
| `VulkanCommandBuffer` | allocate, free, begin, end, submit | requires: queue != 0 for submit |
| `VulkanDescriptorSet` | allocate, free | requires: layout != 0 |

Utility: `result_to_string(code: Int32) -> Str` — converts VkResult codes to human-readable strings.

## Compiler Gaps Discovered

### 1. pub const module limit (P001)
**Symptom:** ~99 `pub const` declarations per module triggers "too many parse errors — aborting."
**Workaround:** Split constants into multiple modules (≤90 consts each). Use decimal literals instead of hex (hex fails at lower counts).
**Impact:** Constants split into `vulkan_constants.xi`, `vulkan_constants2.xi`, `vulkan_constants3.xi`.
**ROADMAP ref:** docs/ROADMAP.md §5c.12

### 2. Cross-module extern resolution (T001)
**Symptom:** `extern "C"` functions declared in module A resolve to `()` and "undefined variable" when called from module B via `use` import.
**Workaround:** Place `extern "C"` blocks in the same module file as their callers.
**Impact:** `vulkan_safe.xi` duplicates the extern declarations it needs (inline, not via `use`).
**ROADMAP ref:** docs/ROADMAP.md §5c.12

### 3. Int→Int32 coercion (T001)
**Symptom:** Integer literals (`1`, `0`) default to `Int` and do not auto-coerce to `Int32` in function arguments or `let` bindings.
**Workaround:** Use `as Int32` casts (e.g., `count as Int32`) matching existing codebase pattern.
**Impact:** All extern function calls with Int32 params use explicit `as Int32`.
**ROADMAP ref:** docs/ROADMAP.md §5c.12

### 4. Out-parameter move semantics (E001)
**Symptom:** Passing a local variable to an extern function that takes it as an out-parameter (pointer) triggers "use of moved value" borrow errors. The compiler treats the value as consumed rather than borrowed through a pointer.
**Impact:** E001 warnings in `vulkan_safe.xi` (non-fatal, compilation succeeds). Actual runtime correctness depends on the compiler's codegen for extern pointer parameters.
**ROADMAP ref:** docs/ROADMAP.md §5c.12

## Known Limitations

- No text/sprite rendering in the C bridge
- Offscreen rendering is 2D only
- No window-minimize handling
- Static error buffer (not thread-safe)
- Generated `xvk_shaders_generated.h` not in repo — must run build script first
- `bridge/xiom_vk_bridge.obj` is pre-compiled for Windows; rebuild needed for other platforms

## SDL Dependencies

The xiom-vulkan package does NOT depend on SDL. It uses the following:
- **GLFW 3.4** for windowing, input, and Vulkan surface creation
- **vulkan-1** for GPU API
- **Windows:** `gdi32`, `user32`, `kernel32`, `shell32`, `ole32` (GLFW platform deps)

## xiom-ffigen Usage

The `xiom-ffigen` tool (v0.10.1) was used to generate an initial draft from `vulkan.xiom-bind`. Syntax: `xiom ffigen <spec.xiom-bind>`. The generated output uses `*UInt8` pointer syntax and `requires:` clauses on extern declarations — these are valid XIOM syntax but the compiler's cross-module resolution for extern functions is incomplete (see Gap #2 above). The final `vulkan_extern.xi` was hand-curated for production use.
