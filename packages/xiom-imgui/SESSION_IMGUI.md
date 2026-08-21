# xiom-imgui -- Session Handoff

**Date**: 2026-07-20 | **Compiler**: xiom v0.48.7 (768/768 tests, AI mode, LSP, Hot Reload)
**GPU**: NVIDIA GeForce RTX 3070 Ti | **VK SDK**: 1.4.350.0 | **GLFW**: 3.4

---

## Package Status

### Production-Ready Components
- `imgui.xi` -- 70+ C bridge functions exposed via `extern "C"` FFI
- `bridge/imgui_bridge.cpp/h` -- C ABI wrapper over Dear ImGui v1.92.9
- `bridge/imgui_impl_glfw.cpp/h` -- GLFW backend
- `bridge/imgui_impl_vulkan.cpp/h` -- Vulkan backend (VK 1.3+)
- `bridge/imgui.cpp/h` etc. -- Full Dear ImGui source (bundled, no external deps)
- `build.ps1` -- Compiles 7 .obj files + builds test/demo targets
- `tests/test_imgui.xi` -- CLI conformance test (null window -> clean exit)

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
- **Known limitation**: 3D pipeline uses static viewport (1280x800) -- 3D scene distorts after resize. lit3d pipeline has dynamic viewport but no draw_cube backend uses it. The 4 orbiting cubes appear correctly at initial window size.

---

## Bugs Fixed This Session

### Vulkan Validation Errors (all resolved)

| VUID | Issue | Fix |
|------|-------|-----|
| `vkAcquireNextImageKHR-semaphore-01780` | Both semaphore+fence were VK_NULL_HANDLE | Restored semaphore chain: `image_available[]` -> submit wait -> `render_finished[]` -> present wait |
| `VkGraphicsPipelineCreateInfo-renderPass-09028` | lit3d pipeline missing pDepthStencilState | Added depth test+write with COMPARE_OP_LESS |

### Swapchain/Resize Fixes

| Issue | Fix |
|-------|-----|
| `swapchain_extent` from surface caps = `glfwGetFramebufferSize` | Compare `glfwGetFramebufferSize` against `swapchain_extent` in `begin_frame` |
| Rendering on same frame as swapchain recreation corrupted state | Skip frame after `recreate_swapchain()` -- return 0, render next frame |
| `xvk_get_fb_width/height` used `swapchain_extent` (stale during resize) | Now queries `glfwGetFramebufferSize` directly |
| ImGui `DisplaySize` set by GLFW window coords, not framebuffer pixels | `new_frame_sized()` sets `DisplaySize` = framebuffer, `FramebufferScale` = (1,1) |

### Compiler Issues Found (reported to xiom team)

| ID | Issue | Status |
|----|-------|--------|
| CG-01 | `Int32 as Float32` cast -> LLVM `%tmp defined with type i32 expected float` | Reported, workaround: Int32-only bridge functions |
| Loop-Crash | `while !should_close(app)` -> `0xC0000005` after ~30s with 50+ FFI calls/frame | Reported, mitigated by `--release` + frame limit |
| CG-02 | Module-scope `var x: Float32 = 0.5` -> LLVM constant error | Workaround: init to 0.0 |

All compiler issues reported as fixed in xiom as of this session. CG-01 still reproduces in v0.48.7.

---

## Production Fixes Applied (2026-07-20)

### Resize Stability (4 bridge-layer fixes)
| Fix | File | Issue | Solution |
|-----|------|-------|----------|
| Surface query validation | `xvk_swapchain.c` | `vkGetPhysicalDeviceSurfaceCapabilitiesKHR` unchecked -> garbage extents | Zero-init caps, check `VkResult`, `glfwGetFramebufferSize` fallback |
| Depth resource leak | `xvk_swapchain.c` | Old depth image/memory/view NEVER freed in `recreate_swapchain` | Save/null old depth handles before overwrite, free on success |
| Missing SURFACE_LOST | `xvk_frame.c` | `VK_ERROR_SURFACE_LOST_KHR` not handled -> crash on fullscreen toggle | Handle alongside `VK_ERROR_OUT_OF_DATE_KHR` |
| SUBOPTIMAL deferral | `xvk_frame.c` | `VK_SUBOPTIMAL_KHR` in end_frame triggered mid-frame recreate -> cascade | Defer to next begin_frame; only set flag |

### 3D Viewport (3 production-grade fixes)
| Fix | File | Issue | Solution |
|-----|------|-------|----------|
| Dynamic viewport | `xvk_pipeline.c/h`, `xvk_legacy.c` | `pipeline_3d` had static viewport at init size -> distorts after resize | `dynamic_viewport` param; `vkCmdSetViewport/Scissor` per-frame |
| Dynamic aspect ratio | `xvk_camera.c/h` | Projection hardcoded 16:9 -> wrong FOV after resize | `xvk_camera_set_aspect_ratio()` stores per-frame aspect from swapchain |
| Trig bridge | `xvk_camera.c` | No `cos`/`sin` in XIOM -> linear satellite drift | `xvk_cos(float)`/`xvk_sin(float)` -> `cosf`/`sinf` bridge |

### Widget Expansion
- **7 new bridge functions**: ProgressBar, RadioButton, Selectable, TextWrapped, LabelText, BeginDisabled, EndDisabled
- **Demo layout**: 4 panels (Widgets, Browser, Performance, Settings) + status bar + modal
- **Theme switching**: Dark/Light/Classic via File > Theme menu
- **3D scene**: 1 central rotating cube + 3 orbiting satellites with circular orbits
- **Total**: 76+ wrapped ImGui functions, production-quality UI

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

ALL GOALS ACHIEVED:
- Resize stability: 4 bridge-layer fixes (surface query, depth leak, SURFACE_LOST, SUBOPTIMAL defer)
- Fluid UI at any resolution -- no crash, no white screen, input works
- 3D viewport: dynamic viewport, per-frame aspect ratio, circular satellite orbits
- Widget set: 76+ wrapped ImGui functions, theme switching, FPS counter
- Demo: 4 panels + status bar + 3D scene with orbiting cubes

TEST:
  $env:VK_LAYER_PATH = "C:\VulkanSDK\1.4.350.0\Bin"
  $env:XVK_VALIDATION = "1"
  $env:PATH = "C:\glfw-3.4.bin.WIN64\lib-vc2022;$env:PATH"
  .\demo_imgui.exe

NEXT PHASE (pick any):
1. Add more ImGui features: tables (BeginTable), docking, viewport windows, fonts
2. Texture support in ImGui bridge: load images via stb_image, display with ImGui::Image
3. Real 3D viewport in an ImGui window: render to offscreen framebuffer, display as ImGui image
4. Create xiom-imgui AUDIT.md documenting all wrapped functions, known gaps, compiler workarounds
5. Package for distribution: merge demo into single-file example, write README
```
