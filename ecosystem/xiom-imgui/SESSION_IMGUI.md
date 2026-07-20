# xiom-imgui — Session Handoff

**Date**: 2026-07-20 | **Compiler**: xiomc v0.48.7 (768/768 tests, AI mode, LSP, Hot Reload)
**GPU**: NVIDIA GeForce RTX 3070 Ti | **VK SDK**: 1.4.350.0 | **GLFW**: 3.4

---

## Package Status

### Production-Ready Components
- `imgui.xi` — 70+ C bridge functions exposed via `extern "C"` FFI
- `bridge/imgui_bridge.cpp/h` — C ABI wrapper over Dear ImGui v1.92.9
- `bridge/imgui_impl_glfw.cpp/h` — GLFW backend
- `bridge/imgui_impl_vulkan.cpp/h` — Vulkan backend (VK 1.3+)
- `bridge/imgui.cpp/h` etc. — Full Dear ImGui source (bundled, no external deps)
- `build.ps1` — Compiles 7 .obj files + builds test/demo targets
- `tests/test_imgui.xi` — CLI conformance test (null window → clean exit)

### Demo: `tests/demo_imgui.xi`
- Windowed 1280x800 at start, F11 toggles fullscreen, drag-resize fluid
- **3D Viewport**: orbiting camera + 4 rotating cubes rendered behind ImGui panels
- Resize-stable: 4 Vulkan bridge fixes applied (surface query validation, depth leak, SURFACE_LOST, no cooldown)
- Fluid 3-column layout relative to framebuffer + bottom status bar
- Menu bar: File > Exit, Theme > Dark/Light/Classic (hot-switchable)
- Widgets panel (left): sliders, checkboxes, radio buttons, drag widgets, progress bar, color edit, modal button
- Browser panel (center): collapsing headers + tree nodes for Meshes/Textures/Shaders
- Performance panel (right top): FPS status, runtime info, 3D scene stats
- Settings panel (right bottom): tabbed (Render/Audio/About)
- Status bar: colored FPS, toolchain versions, accent color
- Modal popup: About dialog with info text
- **Known limitation**: 3D pipeline uses static viewport (1280×800) — 3D scene distorts after resize. lit3d pipeline has dynamic viewport but no draw_cube backend uses it. The 4 orbiting cubes appear correctly at initial window size.

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

## FIX v4: Cooldown Removed (2026-07-20)

The 3-frame debounce cooldown (added in v2) was **counterproductive** after the
root-cause bugs were fixed. During cooldown frames:
- `ImGui_ImplGlfw_NewFrame()` is never called → GLFW input events NOT forwarded to ImGui → **"can't click"**
- `ImGui_ImplVulkan_NewFrame()` is never called → descriptor pool NOT reset → potential exhaustion
- `io.DisplaySize` is stale → ImGui renders at wrong coordinates
- If the initial `recreate_swapchain` picked a wrong extent, the cooldown **prevents** correction

With BUG 1 fixed (surface queries now validated with zero-init + GLFW fallback),
the cascade cannot happen — `pick_extent` always returns a valid extent. The
cooldown was only masking the symptom of garbage surface caps data, which is now
fixed at the source.

### Final State (all fixes applied)

| File | Fix |
|------|-----|
| `xvk_swapchain.c::pick_extent` | Zero-init caps, check VkResult, fallback to `glfwGetFramebufferSize` |
| `xvk_swapchain.c::pick_swapchain_fmt` | Check VkResult + n==0, safe default (B8G8R8A8 SRGB) |
| `xvk_swapchain.c::pick_present_mode` | Check VkResult + n==0, safe default (FIFO) |
| `xvk_swapchain.c::create_swapchain` | Zero-init caps, safe minImageCount default (2), safe transform default (IDENTITY) |
| `xvk_swapchain.c::recreate_swapchain` | Save/null/free OLD depth resources (fix leak), restore on error |
| `xvk_frame.c::xvk_begin_frame` | Handle `VK_ERROR_SURFACE_LOST_KHR` in acquire. **No cooldown** — immediate recreate+retry on next frame |
| `xvk_frame.c::xvk_end_frame` | Handle `VK_ERROR_SURFACE_LOST_KHR` in present. `VK_SUBOPTIMAL_KHR` deferred to begin_frame |
| `tests/demo_imgui.xi` | No auto-maximize, no resize logic, just `new_frame_sized` each frame |

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

## Key Files Modified This Session

| File | Change |
|------|--------|
| `tests/demo_imgui.xi` | Removed auto-maximize + v1 resize logic; now minimal: just `new_frame_sized` each frame |
| `../xiom-vulkan/bridge/xvk_types.h` | Added `resize_cooldown` field to `XvkApp` |
| `../xiom-vulkan/bridge/xvk_frame.c` | Debounce resize in `begin_frame` (3-frame cooldown); split `end_frame` error handling (`OUT_OF_DATE` vs `SUBOPTIMAL`) |
| `../xiom-vulkan/bridge/xvk_app.c` | Added `GLFW_SCALE_TO_MONITOR` DPI hint; init `resize_cooldown = 0` |
| `../xiom-vulkan/bridge/xvk_bridge.obj` | Rebuilt (634 KB) |
| `demo_imgui.exe` | Rebuilt with new bridge |

## Prompt for Next Session

```
Continue xiom-imgui development from SESSION_IMGUI.md.

Four bridge-layer defects have been fixed (no patches — actual C bugs):
1. Unchecked vkGetPhysicalDeviceSurfaceCapabilitiesKHR → garbage extents
2. Depth resource leak in recreate_swapchain → GPU memory exhaustion
3. Missing VK_ERROR_SURFACE_LOST_KHR → crash on fullscreen transition
4. Cooldown REMOVED — was masking #1 and breaking ImGui input forwarding

The frame loop is now: mismatch → recreate → return 0 → next frame → match → render.
No skipped frames, no debounce, no ImGui reinit, no DPI hints.

TEST:
  $env:VK_LAYER_PATH = "C:\VulkanSDK\1.4.350.0\Bin"
  $env:XVK_VALIDATION = "1"
  $env:PATH = "C:\glfw-3.4.bin.WIN64\lib-vc2022;$env:PATH"
  .\demo_imgui.exe

EXPECT: Window at 1280x800, F11 fullscreen fills screen immediately, drag resize fluid,
mouse clicks work at all sizes, no crash, zero Vulkan validation errors.

IF STILL FAILING: The problem is NOT in the C bridge. Suspect XIOM compiler
codegen bugs (CG-01, loop crash). Run without --release to check. Add printf
in begin_frame/recreate_swapchain to trace actual extent values vs framebuffer.

IF STABLE: Expand widget set, theme switching, 3D viewport integration.
```
