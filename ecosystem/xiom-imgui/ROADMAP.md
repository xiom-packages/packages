# xiom-imgui — Production Roadmap

**Status**: NOT production-ready. 15+ CRITICAL findings from systematic audit.
**ImGui version**: v1.92.9 (bundled as precompiled .obj)
**Compiler**: xiomc v0.48.9 (CG-01/CG-02 known bugs)
**Audit date**: 2026-07-20

---

## PHASE 1: CRITICAL — Bridge Layer (Blocking All Correctness)

### 1.1 DisplaySize Set AFTER ImGui::NewFrame() — Coordinate Space Bug
**Severity**: CRITICAL | **File**: `bridge/imgui_bridge.cpp:L109-117`, `L127-132`

Both `new_frame_sized()` and `set_display_size()` set `io.DisplaySize` and `io.DisplayFramebufferScale` **after** `ImGui::NewFrame()`. Dear ImGui reads these during `NewFrame()`. On first frame and every resize frame, all mouse coordinates, clipping, and layout use **stale** dimensions.

**Effect**: Panel positions, mouse hit-testing, and clipping are wrong on the first frame and after every resize. This directly causes the "can't click" and "UI doesn't fill window" symptoms reported.

**Fix**: Reorder to set IO fields BEFORE `ImGui::NewFrame()`:
```cpp
void imgui_bridge_new_frame_sized(int32_t fb_w, int32_t fb_h) {
    ImGuiIO& io = ImGui::GetIO();
    io.DisplaySize = ImVec2((float)fb_w, (float)fb_h);
    io.DisplayFramebufferScale = ImVec2(1.0f, 1.0f);
    ImGui_ImplGlfw_NewFrame();       // GLFW first (updates mouse, time, keys)
    ImGui_ImplVulkan_NewFrame();     // Vulkan second (resets descriptor pool)
    ImGui::NewFrame();               // ImGui last
}
```

### 1.2 Backend NewFrame() Order Wrong (Vulkan Before GLFW)
**Severity**: CRITICAL | **File**: `bridge/imgui_bridge.cpp:L104-106`, `L109-117`

`ImGui_ImplVulkan_NewFrame()` is called **before** `ImGui_ImplGlfw_NewFrame()`. GLFW is the platform backend — it updates `io.DisplaySize`, mouse position, keyboard state, and time delta. When Vulkan runs first, it operates on **stale IO state** from the previous frame.

All official ImGui examples use: GLFW → Vulkan → `ImGui::NewFrame()`.

**Fix**: Swap order: `GLFW_NewFrame()` → `Vulkan_NewFrame()` → `ImGui::NewFrame()`.

### 1.3 reinit_vulkan() Is a Complete No-Op
**Severity**: CRITICAL | **File**: `bridge/imgui_bridge.cpp:L274-284`

Function shuts down the Vulkan backend but **never reinitializes it**. Vulkan handles were never stored as static globals. The function discards all parameters with `(void)` and admits this in a comment: "We need the stored Vulkan handles — stored as globals in init_vulkan but we don't have them here."

**Effect**: Any caller of `reset_vulkan` or `reinit_vulkan` ends up with a **destroyed backend and no replacement** → crash on next `new_frame()`.

**Fix**: Store Vulkan handles as static globals during `init_vulkan()`. Use them in `reinit_vulkan()`. Or remove these functions from the public API until implemented.

### 1.4 Unimplemented Functions Declared in Public API
**Severity**: CRITICAL | **Files**: `bridge/imgui_bridge.h:L32-33,L125,L127,L129`, `imgui.xi:L24,L28`

| Declaration | File | Status |
|-------------|------|--------|
| `imgui_set_next_window_size(float,float)` | .h L32, .xi L24 | **Not implemented** — linker error |
| `imgui_set_next_window_pos(float,float)` | .h L33, .xi L28 | **Not implemented** — linker error |
| `imgui_bridge_set_fb_size(int32_t,int32_t)` | .h L125 | **Not implemented** — linker error |
| `imgui_bridge_reload_fonts()` | .h L127 | **Not implemented** — linker error |
| `imgui_bridge_reinit_vulkan(int64_t,float,float)` | .h L129 | **Broken no-op** (see 1.3) |

**Fix**: Implement or remove all five. Remove FFI declarations from `imgui.xi` for removed functions.

### 1.5 color_edit3/4 Discard Modified Values
**Severity**: CRITICAL | **File**: `bridge/imgui_bridge.cpp:L173-176`

Both functions create a local `float[]` array, pass it to ImGui (which modifies it in-place), then `return 1;` **without returning the modified values**. The caller's color variables are **never updated**. The color picker widget appears to work but the chosen color is discarded.

**Effect**: Demo accent color always stays at initial `0.18, 0.64, 0.88` regardless of user input.

**Fix**: Change to pass caller's variables by pointer, or accept `float*` and write back.

---

## PHASE 2: CRITICAL — XIOM Layer (Contracts, Safety, CG-01)

### 2.1 No Safe Wrappers for ~45 of ~75 Functions
**Severity**: CRITICAL | **File**: `imgui.xi`

Only ~15 functions have safe wrappers with `requires/ensures` contracts. The demo bypasses ALL wrappers, calling raw `unsafe {}` FFI for every widget. This means:
- No contract enforcement (null checks, range validation)
- No compile-time safety guarantees
- The official demo doesn't exercise the safe wrapper layer at all

Missing wrappers for demo-essential functions: menus, tabs, popups, modals, color edits, drag widgets, text_colored, all extended widgets.

**Fix**: Add safe wrappers for all functions used in the demo. Minimum: `begin_menu`, `end_menu`, `begin_main_menu_bar`, `end_main_menu_bar`, `menu_item`, tab functions, popup/modal functions, `text_colored`, `drag_float`, `color_edit3`.

### 2.2 CG-01 Trigger Sites (~20 in demo)
**Severity**: CRITICAL | **Files**: `imgui.xi:L160`, `tests/demo_imgui.xi` (throughout)

`Int as Int32` casts trigger the known CG-01 compiler bug (LLVM type error). Present at ~20 sites in the demo.

**Fix**: Store values as `Int32` from the start where possible. Use module-level `Int32` constants instead of `1 as Int32` casts.

### 2.3 init_vulkan Triggers CG-01
**Severity**: CRITICAL | **File**: `imgui.xi:L132-133`

`family as Int32` and `subpass as Int32` in `init_vulkan` safe wrapper trigger CG-01.

**Fix**: Change parameter types from `Int` to `Int32` in the wrapper signature.

---

## PHASE 3: HIGH — Demo Quality

### 3.1 Radio Button Group Fundamentally Broken
**Severity**: HIGH | **File**: `tests/demo_imgui.xi:L153-160`

State variable `g_radio` is overwritten with raw return value of `imgui_radio_button` (1 on click, 0 otherwise). Option 1's block always resets to 0. Option 2/3 blocks overwrite with their values. After any frame without a click, all three appear unselected. The selection **cannot persist**.

**Fix**: Only update state when a button is actually clicked:
```xiom
if unsafe { imgui_radio_button("Option 1", if g_radio == 0 { 1 as Int32 } else { 0 as Int32 }) } != 0 { g_radio = 0; }
```

### 3.2 F11 Fullscreen: No Debounce
**Severity**: HIGH | **File**: `tests/demo_imgui.xi:L97`

`is_key_down(a, 292)` fires every frame while F11 is held. Rapid swapchain creation/destruction, potential `VK_ERROR_SURFACE_LOST_KHR` cascades.

**Fix**: Track previous F11 state, toggle only on rising edge.

### 3.3 Fixed Delta-Time 0.016 Assumes 60 FPS
**Severity**: HIGH | **File**: `tests/demo_imgui.xi:L107`

`g_time = g_time + 0.016` — animations run at wrong speed on 120/144/30 Hz displays.

**Fix**: Query actual delta time from GLFW (`xvk_now()`) or use `io.DeltaTime`.

### 3.4 Demo Bypasses All Safe Wrappers
**Severity**: HIGH | **File**: `tests/demo_imgui.xi` (throughout)

All widget calls use raw `unsafe { imgui_*() }` instead of `xiom.imgui.*()`. Contracts not enforced. Demo doesn't validate the safe wrapper layer.

**Fix**: Use `xiom.imgui.*()` safe wrappers for all calls. Only use raw FFI for functions without wrappers.

---

## PHASE 4: MEDIUM — Bridge Quality

### 4.1 No CheckVkResultFn Callback
**File**: `bridge/imgui_bridge.cpp:L75`

All Vulkan errors during ImGui rendering (descriptor set allocation failure, pipeline creation failure) are silently swallowed. Under load, first symptom is a crash or blank overlay with no diagnostic.

**Fix**: Register a callback that logs to stderr.

### 4.2 subpass_count Misnamed (Actually subpass_index)
**File**: `bridge/imgui_bridge.cpp:L37,L77`

Parameter named `subpass_count` but used as subpass index (0-based).

**Fix**: Rename to `subpass_index`.

### 4.3 No io.FontGlobalScale DPI Handling
**File**: `bridge/imgui_bridge.cpp:L23`

On HiDPI displays, fonts appear ~50% smaller than expected.

**Fix**: Set `io.FontGlobalScale` based on window content scale queried from GLFW.

### 4.4 No Runtime Version Check
**File**: `bridge/imgui_bridge.cpp:L21`

`IMGUI_CHECKVERSION()` is compile-time only. Bridge .obj must match bundled ImGui .obj exactly. ABI mismatch causes silent corruption.

**Fix**: Add runtime assertion: `IM_ASSERT(strcmp(ImGui::GetVersion(), "1.92.9") == 0)`

---

## Fix Priority Summary

```
P0 (bridge): 1.1 DisplaySize timing, 1.2 NewFrame order, 1.3 reinit_vulkan, 1.4 unimplemented functions, 1.5 color_edit
P1 (XIOM):   2.1 Missing safe wrappers, 2.2 CG-01 reduction, 2.3 init_vulkan CG-01
P2 (demo):   3.1 Radio button fix, 3.2 F11 debounce, 3.3 Delta-time, 3.4 Safe wrapper usage
P3 (quality): 4.1 VkResult callback, 4.2 Naming, 4.3 DPI scale, 4.4 Version check
```
