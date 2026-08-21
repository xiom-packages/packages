# xiom-imgui -- Production-Ready Dear ImGui Package

Self-contained ImGui package for XIOM. Ships pre-compiled bridge .obj files
containing Dear ImGui v1.92.9 + GLFW backend + Vulkan backend.

## Prerequisites (user must provide)

| Dependency | Version | Why |
|-----------|---------|-----|
| Vulkan SDK | 1.3+ | vulkan-1.lib at link time, vulkan-1.dll at runtime |
| GLFW | 3.3+ | glfw3.lib at link time, glfw3.dll at runtime |
| xiom-vulkan | -- | provides `create_app()`, begin/end frame, VK handles |
| xiom | >= 0.48.2 | XIOM compiler |

**No other dependencies.** No cimgui, CMake, or imgui source download.
The entire imgui library is bundled as .obj files in `bridge/`.

## API Coverage: 76+ Functions (Production)

### Lifecycle
| Function | Signature | Notes |
|----------|-----------|-------|
| `create_context(win)` | `Int -> Bool` | Creates ImGui context + GLFW backend |
| `destroy_context()` | `() -> ()` | Shuts down Vulkan + GLFW + destroys context |
| `init_vulkan(inst, dev, phys, q, family, rp, subpass, w, h)` | `Int... -> Bool` | Initializes Vulkan backend (descriptor pool, pipeline, font) |
| `new_frame()` | `() -> ()` | Calls `new_frame_sized` with stored dimensions |
| `render(cb)` | `Int -> ()` | Renders ImGui draw data to command buffer |

### Windows
| Function | Signature | Notes |
|----------|-----------|-------|
| `begin_window(title)` | `Str -> Bool` | `ImGui::Begin` with no flags |
| `end_window()` | `() -> ()` | `ImGui::End` |
| FFI: `imgui_begin(name, flags)` | `Str, Int32 -> Int32` | Direct control over `ImGuiWindowFlags` |
| FFI: `imgui_set_next_window_size_i32(w, h)` | `Int32, Int32 -> ()` | |
| FFI: `imgui_set_next_window_pos_i32(x, y)` | `Int32, Int32 -> ()` | |

### Widgets -- Standard
| Function | Signature | Notes |
|----------|-----------|-------|
| `button(label)` | `Str -> Bool` | Returns true on click |
| `text(text)` | `Str -> ()` | `ImGui::TextUnformatted` |
| `slider_float(label, v, min, max)` | `Str, Float32, Float32, Float32 -> Float32` | |
| `checkbox(label, checked)` | `Str, Bool -> Bool` | |
| FFI: `imgui_slider_int(label, v, min, max)` | `Str, Int32, Int32, Int32 -> Int32` | |
| FFI: `imgui_drag_float(label, v, speed, min, max)` | `Str, Float32, Float32, Float32, Float32 -> Float32` | |
| FFI: `imgui_drag_int(label, v, speed, min, max)` | `Str, Int32, Float32, Int32, Int32 -> Int32` | |
| FFI: `imgui_input_float(label, v)` | `Str, Float32 -> Float32` | |
| FFI: `imgui_input_int(label, v)` | `Str, Int32 -> Int32` | |
| FFI: `imgui_input_text(label, buf, size)` | `Str, Int, Int32 -> Int32` | |
| FFI: `imgui_color_edit3(label, r, g, b)` | `Str, Float32, Float32, Float32 -> Int32` | |
| FFI: `imgui_color_edit4(label, r, g, b, a)` | `Str, Float32, Float32, Float32, Float32 -> Int32` | |
| FFI: `imgui_combo(label, cur, items, n)` | `Str, Int32, Int, Int32 -> Int32` | |
| FFI: `imgui_list_box(label, cur, items, n)` | `Str, Int32, Int, Int32 -> Int32` | |
| FFI: `imgui_small_button(label)` | `Str -> Int32` | |

### Widgets -- Extended (v1.1)
| Function | Signature | Notes |
|----------|-----------|-------|
| `progress_bar(fraction)` | `Float32 -> ()` | Full-width auto-sizing bar |
| `radio_button(label, active)` | `Str, Bool -> Bool` | Exclusive-choice radio |
| `selectable(label)` | `Str -> Bool` | Highlightable list item |
| `text_wrapped(text)` | `Str -> ()` | Word-wrapped text |
| `label_text(label, text)` | `Str, Str -> ()` | Read-only key-value display |
| `text_colored(r,g,b,a,text)` | `Float32,Float32,Float32,Float32,Str -> ()` | Colored text (FFI only) |
| `bullet_text(text)` | `Str -> ()` | Bullet-point text (FFI only) |
| FFI: `imgui_begin_disabled(d)` | `Int32 -> Int32` | |
| FFI: `imgui_end_disabled()` | `() -> ()` | |

### Layout
| Function | Signature |
|----------|-----------|
| `separator()` | `() -> ()` |
| `same_line()` | `() -> ()` (offset=0, spacing=0) |
| `spacing()` | `() -> ()` |
| FFI: `imgui_dummy(w, h)` | `Float32, Float32 -> ()` |
| FFI: `imgui_new_line()` | `() -> ()` |

### Trees / Collapsing Headers
| Function | Signature |
|----------|-----------|
| `tree_node(label)` | `Str -> Bool` |
| `tree_pop()` | `() -> ()` |
| `collapsing_header(label)` | `Str -> Bool` |
| FFI: `imgui_tree_node_flags(label, flags)` | `Str, Int32 -> Int32` |

### Tabs
| Function | FFI signature |
|----------|---------------|
| `imgui_begin_tab_bar(id)` | `Str -> Int32` |
| `imgui_end_tab_bar()` | `() -> ()` |
| `imgui_begin_tab_item(label)` | `Str -> Int32` |
| `imgui_end_tab_item()` | `() -> ()` |

### Plots
| Function | FFI signature |
|----------|---------------|
| `imgui_plot_lines(label, v, n, smin, smax, w, h)` | `Str, Int, Int32, Float32, Float32, Float32, Float32 -> ()` |
| `imgui_plot_histogram(label, v, n, smin, smax, w, h)` | `Str, Int, Int32, Float32, Float32, Float32, Float32 -> ()` |

### Popups / Modals
| Function | FFI signature |
|----------|---------------|
| `imgui_open_popup(id)` | `Str -> ()` |
| `imgui_begin_popup(id)` | `Str -> Int32` |
| `imgui_end_popup()` | `() -> ()` |
| `imgui_close_current_popup()` | `() -> ()` |
| `imgui_begin_popup_context_item(id)` | `Str -> Int32` |
| `imgui_begin_popup_modal(name)` | `Str -> Int32` |
| `imgui_end_popup_modal()` | `() -> ()` |

### Menus
| Function | FFI signature |
|----------|---------------|
| `imgui_begin_main_menu_bar()` | `() -> Int32` |
| `imgui_end_main_menu_bar()` | `() -> ()` |
| `imgui_begin_menu(label)` | `Str -> Int32` |
| `imgui_end_menu()` | `() -> ()` |
| `imgui_menu_item(label, shortcut, enabled)` | `Str, Str, Int32 -> Int32` |
| `imgui_begin_menu_bar()` | `() -> Int32` |
| `imgui_end_menu_bar()` | `() -> ()` |

### Tooltips / Focus / Scrolling
| Function | FFI signature |
|----------|---------------|
| `imgui_set_tooltip(text)` | `Str -> ()` |
| `imgui_begin_tooltip()` | `() -> ()` |
| `imgui_end_tooltip()` | `() -> ()` |
| `imgui_set_scroll_here_y()` | `() -> ()` |
| `imgui_is_item_hovered()` | `() -> Int32` |
| `imgui_is_item_clicked()` | `() -> Int32` |

### Styling
| Function | Signature |
|----------|-----------|
| `style_dark()` | `() -> ()` |
| `style_light()` | `() -> ()` |
| `style_classic()` | `() -> ()` |
| FFI: `imgui_push_style_color(idx, r, g, b, a)` | `Int32, Float32... -> ()` |
| FFI: `imgui_pop_style_color(count)` | `Int32 -> ()` |

### Display / Framebuffer
| Function | FFI signature | Notes |
|----------|---------------|-------|
| `imgui_bridge_new_frame_sized(fb_w, fb_h)` | `Int32, Int32 -> ()` | Sets `io.DisplaySize` = framebuffer, `FramebufferScale` = (1,1) |
| `imgui_bridge_set_display_size_i32(w, h)` | `Int32, Int32 -> ()` | Manual display size override |

### Utility
| Function | FFI signature |
|----------|---------------|
| `imgui_get_framerate()` | `() -> Int32` |
| `imgui_get_frame_count()` | `() -> Int32` |

### Vulkan Backend Management
| Function | FFI signature | Notes |
|----------|---------------|-------|
| `imgui_bridge_reset_vulkan(inst, dev, phys, q, family, rp, fbw, fbh)` | `Int... -> ()` | Shutdown + reinit Vulkan backend (resize recovery) |

## Not Yet Wrapped

| Feature | Reason |
|---------|--------|
| Tables (`ImGui::BeginTable`) | Complex API with column config -- needs struct marshalling |
| Docking / Viewports | Requires multi-window Vulkan support; not in scope |
| Font customization | Requires TTF loading + atlas API |
| `ImGui::Image` / texture display | Needs descriptor set management bridge |
| `ImGui::InputText` with buffer | Needs XIOM-side string buffer allocation |

## Compiler Workarounds

| ID | Issue | Workaround |
|----|-------|------------|
| CG-01 | `Int32 as Float32` -> LLVM type mismatch | Use i32 bridge functions (e.g., `set_display_size_i32`) |
| CG-02 | Module-scope `var x: Float32 = 0.5` -> LLVM constant error | Init Float32 to `0.0`, reassign in `fn` body |
| E001 | Borrow checker false-positives on `unsafe` FFI calls | Non-fatal warnings; compilation succeeds |

## Vulkan Bridge Fixes (Production)

| Issue | Fix |
|-------|-----|
| Surface query unchecked -> garbage swapchain extents | Zero-init caps, check `VkResult`, GLFW fallback |
| Depth image/memory/view leak in `recreate_swapchain` | Save/null old handles before overwrite, free on success |
| No `VK_ERROR_SURFACE_LOST_KHR` handling | Handle alongside `VK_ERROR_OUT_OF_DATE_KHR` |
| `VK_SUBOPTIMAL_KHR` mid-frame recreate cascade | Defer to next `begin_frame` |
| `pipeline_3d` static viewport -> distorts after resize | Dynamic viewport + `vkCmdSetViewport` per-frame |
| Camera projection fixed 16:9 aspect | `xvk_camera_set_aspect_ratio()` per-frame from swapchain |
| No trig functions in XIOM for orbit math | `xvk_cos`/`xvk_sin` bridge to C `cosf`/`sinf` |

## Build & Test

```powershell
$env:VULKAN_SDK = "C:\VulkanSDK\1.4.350.0"
$env:GLFW_DIR   = "C:\glfw-3.4.bin.WIN64"

cd E:\Projects\AXIOM\ecosystem\xiom-imgui
.\build.ps1 -Target build   # compile 7 .obj files (one-time)
.\build.ps1 -Target test    # CLI conformance test
.\build.ps1 -Target demo    # Full GUI demo with 3D viewport

# Run with Vulkan validation:
$env:VK_LAYER_PATH = "$env:VULKAN_SDK\Bin"
$env:XVK_VALIDATION = "1"
$env:PATH = "$env:GLFW_DIR\lib-vc2022;$env:PATH"
.\demo_imgui.exe
```

## Package Structure

```
xiom-imgui/
|-- imgui.xi              XIOM FFI + safe wrappers (76+ functions)
|-- build.ps1             Build script
|-- AUDIT.md              This file
|-- SESSION_IMGUI.md      Session journal + production fixes
|-- tests/
|   |-- test_imgui.xi     CLI conformance test
|   `-- demo_imgui.xi     Production demo (4 panels + 3D viewport)
`-- bridge/
    |-- imgui_bridge.h/cpp  C ABI wrapper
    |-- imgui.cpp/h         Dear ImGui v1.92.9 core
    |-- imgui_draw.cpp      Draw list implementation
    |-- imgui_widgets.cpp   All standard widgets
    |-- imgui_tables.cpp    Table implementation
    |-- imgui_impl_glfw.*   GLFW platform backend
    |-- imgui_impl_vulkan.* Vulkan renderer backend
    `-- *.obj               Pre-compiled (7 files)
```
