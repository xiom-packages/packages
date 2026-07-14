# xiom-imgui — Dear ImGui Bindings

Immediate-mode GUI for XIOM via Dear ImGui (cimgui C wrapper). Windows, widgets, layouts, plotting, and Vulkan/OpenGL backends.

## Install

```powershell
xiom pkg install xiom-imgui
```

## Requirements

- **cimgui** (C API wrapper for Dear ImGui)
  - Build from source: [cimgui](https://github.com/cimgui/cimgui)
  - Dear ImGui v1.89+
- **GLFW** (`xiom-glfw` package) for windowing
- **Vulkan** (`xiom-vulkan` package) for GPU rendering

## Link Flags

```
-l cimgui -l cimgui_glfw -l cimgui_vulkan
```

## Quick Start

```xiom
use xiom.glfw;
use xiom.imgui;

fn main() -> Int {
  glfw.init()?;

  let window = glfw.create_window(800, 600, "XIOM ImGui")?;
  ig_create_context()?;
  ig_init_for_vulkan(window)?;
  ig_style_dark();

  var show_demo = true;
  var slider_val: Float32 = 0.5;
  var checked = true;

  while !glfw.should_close(window) {
    glfw.poll_events();
    ig_new_frame();

    if ig_begin("Controls", &show_demo, 0) {
      ig_text("Hello from XIOM!");
      ig_separator();

      if ig_button("Click Me", 100, 30) {
        slider_val = 1.0;
      };
      ig_same_line(0.0, 10.0);
      ig_checkbox("Enable Feature", &checked);

      ig_slider_float("Value", &slider_val, 0.0, 1.0);
      ig_input_text("Name", &name_buffer, 256);

      if ig_tree_node("Advanced") {
        ig_text("Advanced settings here");
        ig_plot_lines("Data", &values, 0.0, 1.0);
        ig_tree_pop();
      };

      ig_end();
    };

    ig_render();
    glfw.swap_buffers(window);
  };

  ig_shutdown_backend();
  ig_destroy_context();
  glfw.destroy_window(window);
  return 0;
}
```

## API Overview

| Module | File | Purpose |
|--------|------|---------|
| `xiom.imgui` | `imgui.xi` | FFI declarations |
| `xiom.imgui.bindings` | `src/bindings.xi` | Safe stubs with contracts |

### Frame Loop Contract

```
ig_new_frame()         # Begin frame
  ...widgets...        # All widget calls
ig_render()            # End frame, produce draw data
```

### Widget Return Values

All interactive widgets return `Bool`:
- `true` = widget was interacted with (clicked, changed, edited)
- `false` = no change this frame

### Window Flags

```xiom
ig_begin("My Window", &open, WINDOW_NO_TITLE_BAR | WINDOW_NO_RESIZE);
```

| Flag | Value | Effect |
|------|-------|--------|
| `WINDOW_NO_TITLE_BAR` | 1 | Hide title bar |
| `WINDOW_NO_RESIZE` | 4 | Disable resizing |
| `WINDOW_NO_MOVE` | 8 | Disable moving |
| `WINDOW_NO_COLLAPSE` | 16 | Disable collapsing |
| `WINDOW_ALWAYS_AUTO_RESIZE` | 32 | Auto-resize each frame |

### Style Presets

```xiom
ig_style_dark();      // Dark theme (default)
ig_style_light();     // Light theme
ig_style_classic();   // Classic ImGui colors
```

## Contracts

- `ig_new_frame()` and `ig_render()` must be paired
- Widgets must be called between `ig_new_frame()` and `ig_render()`
- `ig_begin()` → ... → `ig_end()` for window content
- `ig_tree_node()` → ... → `ig_tree_pop()` for tree content
- Backend must be initialized before rendering

## License

MIT or Apache-2.0, at your option.
