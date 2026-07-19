# xiom-imgui — Production-Ready Dear ImGui Package

Self-contained ImGui package for XIOM. Ships pre-compiled bridge .obj files.
No external imgui dependency — just link and go.

## Architecture

```
xiom-imgui/
├── imgui.xi                    XIOM bindings (pub fn API)
├── build.ps1                   Build script (compile .obj, test, integrate)
├── tests/test_imgui.xi         Conformance test
├── bridge/
│   ├── imgui_bridge.h/cpp      C ABI wrapper (extern "C")
│   ├── imgui.cpp/h             Dear ImGui v1.92.9
│   ├── imgui_draw.cpp          Font/shape rendering
│   ├── imgui_widgets.cpp       Widget implementations
│   ├── imgui_tables.cpp        Table widget
│   ├── imgui_impl_glfw.cpp/h   GLFW backend
│   ├── imgui_impl_vulkan.cpp/h Vulkan backend (VK 1.3+)
│   └── *.obj                   Pre-compiled (7 files, ~1.2MB)
└── AUDIT.md                    This file
```

## Dependencies

| Dependency | Required For |
|-----------|-------------|
| Vulkan SDK 1.3+ | Instance, device, render pass handles |
| GLFW 3.3+ | Window + input backend |
| xiomc >= 0.48.2 | XIOM compiler |

**No cimgui, no CMake, no external build** — all imgui source is bundled.

## Quick Start

```powershell
# 1. Set env vars
$env:VULKAN_SDK = "C:\VulkanSDK\1.4.350.0"
$env:GLFW_DIR   = "C:\glfw-3.4.bin.WIN64"

# 2. Compile bridge (one-time)
cd ecosystem/xiom-imgui
.\build.ps1 -Target build

# 3. Build test
.\build.ps1 -Target test
```

## Integration with your app

```xiom
// In your main.xi:
use xiom.imgui;

fn main() -> Int {
  let app = create_app("My App", 1280, 720);  // from xiom.vulkan
  let ok = imgui.create_context(xvk_get_glfw_window(app));
  let vk_ok = imgui.init_vulkan(
    xvk_get_instance(app), xvk_get_device(app),
    xvk_get_physical_device(app), xvk_get_graphics_queue(app),
    0,  // queue family
    xvk_get_render_pass(app), 0,  // render pass, subpass
    1280.0, 720.0
  );

  while !should_close(app) {
    poll(app);
    begin_frame(app);
    imgui.new_frame();

    // ImGui windows
    if imgui.begin_window("Hello") {
      imgui.text("XIOM + ImGui!");
      imgui.slider_float("Value", 0.5, 0.0, 1.0);
      if imgui.button("Click Me") { io.println("clicked!"); }
    }
    imgui.end_window();

    imgui.render(xvk_get_command_buffer(app));
    end_frame(app);
  }
  imgui.destroy_context();
}
```

## API Reference

### Lifecycle
| Function | Description |
|----------|-------------|
| `create_context(glfw_window: Int) -> Bool` | Init ImGui + GLFW backend |
| `destroy_context()` | Shutdown + free resources |
| `init_vulkan(instance, device, phys, queue, family, rp, subpass, w, h) -> Bool` | Init Vulkan backend |
| `new_frame()` | Begin frame (before widgets) |
| `render(cb: Int)` | End frame, record draw commands |

### Windows
| Function | Description |
|----------|-------------|
| `begin_window(title: Str) -> Bool` | Open a window. Close with `end_window()` if returns true |
| `end_window()` | Close current window |

### Widgets
| Function | Description |
|----------|-------------|
| `button(label: Str) -> Bool` | Clickable button |
| `text(text: Str)` | Display text |
| `slider_float(label, value, min, max) -> Float32` | Draggable slider |
| `checkbox(label: Str, checked: Bool) -> Bool` | Toggle checkbox |
| `separator()` | Horizontal separator line |
| `same_line()` | Next widget on same line |
| `spacing()` | Vertical spacing |
| `tree_node(label: Str) -> Bool` | Collapsible tree node |
| `tree_pop()` | Close tree node |
| `collapsing_header(label: Str) -> Bool` | Collapsible section header |

### Styling
| Function | Description |
|----------|-------------|
| `style_dark()` | Dark theme (default) |
| `style_light()` | Light theme |
| `style_classic()` | Classic theme |

## Building from source

If you modify imgui source files:

```powershell
# Rebuild all .obj files
.\build.ps1 -Target build
```

This compiles 7 C++ source files with `clang++ -O2 -DIMGUI_IMPL_VULKAN_NO_PROTOTYPES`.

## Compile Status

| File | Status |
|------|--------|
| `imgui.xi` | PASSED (standalone type-check) |
| `tests/test_imgui.xi` | PASSED (linked with bridge) |
| 7 bridge .obj files | PASSED (clang++ -O2, all symbols exported) |
