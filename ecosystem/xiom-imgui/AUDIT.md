# xiom-imgui — Production-Ready Dear ImGui Package

Self-contained ImGui package for XIOM. Ships pre-compiled bridge .obj files
containing Dear ImGui v1.92.9 + GLFW backend + Vulkan backend.

## Prerequisites (user must provide)

| Dependency | Version | Why |
|-----------|---------|-----|
| Vulkan SDK | 1.3+ | vulkan-1.lib at link time, vulkan-1.dll at runtime |
| GLFW | 3.3+ | glfw3.lib at link time, glfw3.dll at runtime |
| xiom-vulkan | — | provides `create_app()`, begin/end frame, VK handles |
| xiomc | >= 0.48.2 | XIOM compiler |

**No other dependencies.** No cimgui, no CMake, no imgui source download.
The entire imgui library is bundled as .obj files in `bridge/`.

## What's included (ImGui API coverage)

### ✅ Supported (v1.0)

| Category | Functions |
|----------|-----------|
| Lifecycle | `create_context`, `destroy_context`, `init_vulkan`, `new_frame`, `render` |
| Windows | `begin_window`, `end_window` |
| Widgets | `button`, `text`, `slider_float`, `checkbox` |
| Layout | `separator`, `same_line`, `spacing` |
| Trees | `tree_node`, `tree_pop`, `collapsing_header` |
| Styling | `style_dark`, `style_light`, `style_classic` |

### ⬜ Not yet wrapped (can be added)

Tables, popups/modals, drag widgets, color pickers, list boxes,
combo boxes, input text, plots, menus, docking, viewports,
multi-viewport, custom rendering, font customization, and ~150 others.

## API Reference

### Lifecycle

```xiom
use xiom.imgui;

// 1. Create context (needs GLFW window from xiom-vulkan)
let win = xvk_get_glfw_window(app);
let ok = imgui.create_context(win);          // -> Bool

// 2. Init Vulkan backend (needs VK handles from xiom-vulkan)
let vk_ok = imgui.init_vulkan(
  xvk_get_instance(app),
  xvk_get_device(app),
  xvk_get_physical_device(app),
  xvk_get_graphics_queue(app),
  0,                                        // queue family index
  xvk_get_render_pass(app),
  0,                                        // subpass
  xvk_get_fb_width(app) as Float32,
  xvk_get_fb_height(app) as Float32
);                                           // -> Bool

// 3. Frame loop
while !should_close(app) {
  poll(app);
  begin_frame(app);
  imgui.new_frame();

  // Widgets
  if imgui.begin_window("My Window") {
    imgui.text("Hello XIOM!");
    if imgui.button("Click Me") { ... }
    imgui.slider_float("Value", 0.5, 0.0, 1.0);
    imgui.checkbox("Enable", true);
  }
  imgui.end_window();

  imgui.render(command_buffer);
  end_frame(app);
}

// 4. Shutdown
imgui.destroy_context();
```

### Widgets

| Function | Signature | Returns |
|----------|-----------|---------|
| `begin_window(title: Str)` | Opens a window | Bool (true=open) |
| `end_window()` | Closes current window | — |
| `button(label: Str)` | Clickable button | Bool (clicked) |
| `text(text: Str)` | Display text | — |
| `slider_float(label, value, min, max)` | Draggable slider | Float32 |
| `checkbox(label: Str, checked: Bool)` | Toggle | Bool |
| `separator()` | Horizontal line | — |
| `same_line()` | Next widget on same line | — |
| `spacing()` | Vertical gap | — |
| `tree_node(label: Str)` | Expandable node | Bool |
| `tree_pop()` | Close node | — |
| `collapsing_header(label: Str)` | Collapsible section | Bool |

### Styling

| Function | Description |
|----------|-------------|
| `style_dark()` | Dark theme (default, applied automatically) |
| `style_light()` | Light theme |
| `style_classic()` | Classic ImGui theme |

## Package Structure

```
xiom-imgui/
├── imgui.xi                  XIOM bindings
├── build.ps1                 Build script
├── tests/
│   ├── test_imgui.xi         CLI conformance test
│   └── demo_imgui.xi         Full GUI demo (needs xiom-vulkan)
├── bridge/
│   ├── imgui_bridge.h/cpp    C ABI wrapper (extern "C")
│   ├── imgui.cpp/h           Dear ImGui v1.92.9
│   ├── imgui_*.cpp/h         Draw, widgets, tables
│   ├── imgui_impl_glfw.*     GLFW backend
│   ├── imgui_impl_vulkan.*   Vulkan backend
│   └── *.obj                 Pre-compiled (7 files, ~1.2MB)
└── AUDIT.md                  This file
```

## Build & Test

```powershell
# Set env vars
$env:VULKAN_SDK = "C:\VulkanSDK\1.4.350.0"
$env:GLFW_DIR   = "C:\glfw-3.4.bin.WIN64"

# Compile bridge (one-time)
.\build.ps1 -Target build

# CLI test (no window, validates bindings)
.\build.ps1 -Target test
.\test_imgui.exe
# Expected: no output = success

# Full GUI demo (opens window with ImGui widgets)
# Requires xiom-vulkan package built
.\build.ps1 -Target demo
.\demo_imgui.exe
```

## Zero-DLL Guarantee

The package adds **no new DLL requirements**. The imgui library is statically
linked into your executable via the .obj files. You only need the same runtime
DLLs that any Vulkan XIOM app uses:

- `vulkan-1.dll` (from GPU driver, in System32)
- `glfw3.dll` (from GLFW_DIR, copy to app directory or add to PATH)
