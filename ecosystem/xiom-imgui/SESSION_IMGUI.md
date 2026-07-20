# xiom-imgui — Session Handoff

**Date**: 2026-07-20 | **Compiler**: xiomc v0.48.7 (768/768 tests, AI mode, LSP, Hot Reload)
**GPU**: NVIDIA GeForce RTX 3070 Ti | **VK SDK**: 1.4.350.0 | **GLFW**: 3.4

---

## Package Status

### Production-Ready Components
- `imgui.xi` — 60+ C bridge functions exposed via `extern "C"` FFI
- `bridge/imgui_bridge.cpp/h` — C ABI wrapper over Dear ImGui v1.92.9
- `bridge/imgui_impl_glfw.cpp/h` — GLFW backend
- `bridge/imgui_impl_vulkan.cpp/h` — Vulkan backend (VK 1.3+)
- `bridge/imgui.cpp/h` etc. — Full Dear ImGui source (bundled, no external deps)
- `build.ps1` — Compiles 7 .obj files + builds test/demo targets
- `tests/test_imgui.xi` — CLI conformance test (null window → clean exit)

### Demo: `tests/demo_imgui.xi`
- Maximizes on startup, F11 toggles fullscreen
- Fluid 3-column layout (33% each, sized relative to framebuffer)
- Menu bar (File > Exit), File > Theme (Dark/Light/Classic)
- Widgets: sliders, checkboxes, drags, color edit, modal popup, trees, tabs
- Escape or Menu > Exit to close, 100k frame safety limit
- ImGui DisplaySize set atomically in C bridge via `new_frame_sized(fb_w, fb_h)`

---

## Bugs Fixed This Session

### Vulkan Validation Errors (all resolved)

| VUID | Issue | Fix |
|------|-------|-----|
| `vkAcquireNextImageKHR-semaphore-01780` | Both semaphore+fence were VK_NULL_HANDLE | Restored semaphore chain: `image_available[]` → submit wait → `render_finished[]` → present wait |
| `VkGraphicsPipelineCreateInfo-renderPass-09028` | lit3d pipeline missing pDepthStencilState | Added depth test+write with COMPARE_OP_LESS |

### Swapchain/Resize Fixes

| Issue | Fix |
|-------|-----|
| `swapchain_extent` from surface caps ≠ `glfwGetFramebufferSize` | Compare `glfwGetFramebufferSize` against `swapchain_extent` in `begin_frame` |
| Rendering on same frame as swapchain recreation corrupted state | Skip frame after `recreate_swapchain()` — return 0, render next frame |
| `xvk_get_fb_width/height` used `swapchain_extent` (stale during resize) | Now queries `glfwGetFramebufferSize` directly |
| ImGui `DisplaySize` set by GLFW window coords, not framebuffer pixels | `new_frame_sized()` sets `DisplaySize` = framebuffer, `FramebufferScale` = (1,1) |

### Compiler Issues Found (reported to xiomc team)

| ID | Issue | Status |
|----|-------|--------|
| CG-01 | `Int32 as Float32` cast → LLVM `%tmp defined with type i32 expected float` | Reported, workaround: Int32-only bridge functions |
| Loop-Crash | `while !should_close(app)` → `0xC0000005` after ~30s with 50+ FFI calls/frame | Reported, mitigated by `--release` + frame limit |
| CG-02 | Module-scope `var x: Float32 = 0.5` → LLVM constant error | Workaround: init to 0.0 |

All compiler issues reported as fixed in xiomc as of this session. CG-01 still reproduces in v0.48.7.

---

## Remaining Issue: Demo Instability After Resize/Maximize

### Symptoms
- White flash on startup (maximize triggers resize before first frame renders)
- After maximize/fullscreen, UI may not render correctly
- Eventually becomes unstable (can crash or show black screen)

### What's NOT the cause (verified)
- ❌ Semaphore sync — correct 2-frame pipeline with proper acquire→submit→present chain
- ❌ Descriptor pool exhaustion — pool created with FREE_DESCRIPTOR_SET_BIT, reset each frame
- ❌ Swapchain recreation logic — properly destroys old + creates new with all resources
- ❌ ImGui DisplaySize mismatch — set atomically to framebuffer pixels
- ❌ Vulkan validation errors — zero errors in latest build
- ❌ Compiler CG-01 — worked around with i32 bridge functions

### Hypotheses

**Hypothesis 1 (MOST LIKELY): Swapchain Recreation on Startup Maximize**
The window starts at 1280x800. `xvk_app_maximize()` resizes to native resolution BEFORE the first `begin_frame`. The swapchain is at 1280x800 but framebuffer is now 3840x2160. First frame: `begin_frame` detects mismatch, calls `recreate_swapchain()`, returns 0. Second frame: renders with new swapchain. But ImGui was initialized with `1280.0, 800.0` framebuffer dimensions — the descriptor pool, pipeline, and font texture all expect 1280x800. After swapchain recreation to 3840x2160, ImGui's internal state still references the old dimensions.

**Fix attempt**: Call `imgui_bridge_init_vulkan` with actual framebuffer dimensions (not hardcoded 1280x800). After the maxsize resize, reinitialize ImGui's Vulkan backend.

**Hypothesis 2: Descriptor Pool Reset After Swapchain Recreation**
`ImGui_ImplVulkan_NewFrame()` calls `vkResetDescriptorPool()`. After `recreate_swapchain()` calls `vkDeviceWaitIdle()`, the pool reset should be safe. But if the GPU hasn't fully idled (race condition), the reset is undefined behavior.

**Fix attempt**: Move `vkDeviceWaitIdle` OUT of `recreate_swapchain` and into a separate pre-frame step. Or add a frame counter that skips ImGui rendering for 2-3 frames after resize.

**Hypothesis 3: ImGui Font Upload Command Buffer**
During `ImGui_ImplVulkan_Init()`, a one-time command buffer is submitted to upload the font texture. This command buffer might reference the OLD swapchain's resources. After swapchain recreation, those resources are destroyed but the font upload CB was already submitted and won't be re-executed. The font texture itself is valid (separate VkImage), but the descriptor sets referencing it might be in the old pool.

**Fix attempt**: After swapchain recreation, call `ImGui_ImplVulkan_CreateFontsTexture()` to re-upload fonts, recreating the descriptor sets.

---

## Build & Run

```powershell
$env:VULKAN_SDK = "C:\VulkanSDK\1.4.350.0"
$env:GLFW_DIR   = "C:\glfw-3.4.bin.WIN64"

cd E:\Projects\AXIOM\ecosystem\xiom-imgui
.\build.ps1 -Target build   # compile .obj files (one-time)
.\build.ps1 -Target demo    # build demo
.\build.ps1 -Target test    # CLI test

# Run with Vulkan validation:
$env:VK_LAYER_PATH = "$env:VULKAN_SDK\Bin"
$env:XVK_VALIDATION = "1"
$env:PATH = "$env:GLFW_DIR\lib-vc2022;$env:PATH"
.\demo_imgui.exe
```

## Key Files to Modify

| File | Purpose |
|------|---------|
| `bridge/imgui_bridge.cpp` | C wrapper over ImGui + Vulkan backend |
| `bridge/imgui_bridge.h` | Header — add new functions here |
| `imgui.xi` | XIOM FFI declarations + safe wrappers |
| `tests/demo_imgui.xi` | Demo app — widget layout, frame loop |
| `../xiom-vulkan/bridge/xvk_frame.c` | `begin_frame`/`end_frame`, swapchain resize |
| `../xiom-vulkan/bridge/xvk_swapchain.c` | `recreate_swapchain`, cleanup |
| `../xiom-vulkan/bridge/xvk_app.c` | New accessor functions, pipeline creation |
| `../xiom-vulkan/vulkan.xi` | FFI declarations for new accessors |

## Prompt for Next Session

```
Continue xiom-imgui development from SESSION_IMGUI.md.

The demo compiles and runs but has instability after maximize/fullscreen.
All known Vulkan validation errors are fixed (semaphore VUID-01780, depth VUID-09028).

Start by testing Hypothesis 1: remove maximize on startup. Make the demo start 
windowed at 1280x800 and test if resize/fullscreen works when triggered 
manually (F11 or window drag). If stable without auto-maximize, the issue is 
the swapchain recreation during initialization.

Then test Hypothesis 3: after swapchain recreation, reinitialize ImGui's 
Vulkan backend (font texture + descriptor sets) by calling 
imgui_bridge_init_vulkan with the new framebuffer dimensions.

Enable Vulkan validation layers during testing:
  $env:VK_LAYER_PATH = "C:\VulkanSDK\1.4.350.0\Bin"
  $env:XVK_VALIDATION = "1"

Goal: demo stable at any resolution, fullscreen toggle works, no white screen 
or crash. Once stable, expand widget set and polish UI.
```
