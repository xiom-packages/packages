# xiom-imgui Specification

## Overview
Dear ImGui immediate-mode GUI bindings for XIOM via cimgui (the C API wrapper). Provides window creation, widgets, layouts, plotting, and Vulkan/OpenGL backend integration.

## Architecture

### Layers
```
┌──────────────────────────────────────┐
│  src/bindings.xi (Safe XIOM stubs)   │
│  ig_begin, ig_button, ig_text, etc.  │
├──────────────────────────────────────┤
│  imgui.xi        (Raw FFI decls)     │
│  begin_window, button, slider_float  │
├──────────────────────────────────────┤
│  imgui.xiom-bind (C ABI via cimgui)  │
│  igBegin, igButton, igSliderFloat    │
└──────────────────────────────────────┘
```

### Design Decisions
- All functions map 1:1 to cimgui C ABI for minimal overhead.
- `Bool` return values indicate widget interaction (clicked/changed).
- Mutable parameters use XIOM borrowing (`&mut`) — cimgui's pointer semantics map to XIOM references.
- ImGui context is managed through `create_context()`/`destroy_context()` wrappers.

## ImGui Frame Loop
```
create_context()
init_for_vulkan(frame) or init_for_opengl(frame)
style_dark() / style_light() / style_classic()

while running {
  new_frame()
  // ... widget calls between new_frame and render ...
  render()
  render_vulkan(draw_data, cmd_buffer, pipeline)   // Vulkan backend
}

shutdown_backend()
destroy_context()
```

## API Surface

### Lifecycle
| Function | Description |
|----------|-------------|
| `ig_create_context()` | Initialize ImGui context |
| `ig_destroy_context()` | Destroy ImGui context |
| `ig_new_frame()` | Begin a new frame |
| `ig_render()` | End the frame and generate draw data |

### Windows
| Function | Returns | Description |
|----------|---------|-------------|
| `ig_begin(title, open, flags)` | `Bool` | Begin a window (returns false if collapsed/closed) |
| `ig_end()` | — | End the current window |
| `ig_begin_child(id, width, height)` | `Bool` | Begin a child region |
| `ig_end_child()` | — | End the child region |

### Layout
| Function | Description |
|----------|-------------|
| `ig_separator()` | Horizontal separator line |
| `ig_same_line(offset, spacing)` | Place next widget on same line |
| `ig_spacing()` | Vertical spacing |
| `ig_new_line()` | Force new line |

### Widgets (all return `Bool` = interaction occurred)
| Function | Description |
|----------|-------------|
| `ig_text(text)` | Display text |
| `ig_text_colored(r, g, b, a, text)` | Colored text |
| `ig_button(label, width, height)` | Clickable button |
| `ig_checkbox(label, checked)` | Toggle checkbox — `&mut Bool` |
| `ig_slider_float(label, value, min, max)` | Float slider — `&mut Float32` |
| `ig_slider_int(label, value, min, max)` | Integer slider — `&mut Int` |
| `ig_input_float(label, value)` | Float input field — `&mut Float32` |
| `ig_input_int(label, value)` | Integer input field — `&mut Int` |
| `ig_input_text(label, buffer, buf_size)` | Text input — `&mut Str` |
| `ig_combo(label, current, items)` | Dropdown combo — `&mut Int` |

### Trees & Collapsing Headers
| Function | Returns `Bool` | Description |
|----------|----------------|-------------|
| `ig_tree_node(label)` | true if expanded | Tree node (content must follow if expanded) |
| `ig_tree_pop()` | — | End tree node scope |
| `ig_collapsing_header(label)` | true if expanded | Collapsible section |

### Plotting
| Function | Description |
|----------|-------------|
| `ig_plot_lines(label, values, scale_min, scale_max)` | Line plot |
| `ig_plot_histogram(label, values, scale_min, scale_max)` | Histogram plot |

### Popups & Modals
| Function | Returns `Bool` | Description |
|----------|----------------|-------------|
| `ig_open_popup(name)` | — | Open a popup |
| `ig_begin_popup(name)` | true if popup is open | Begin popup content |
| `ig_end_popup()` | — | End popup |
| `ig_begin_modal(name, open)` | true if modal is open | Begin modal dialog |
| `ig_end_modal()` | — | End modal |

### Style
| Function | Description |
|----------|-------------|
| `ig_style_dark()` | Dark color scheme |
| `ig_style_light()` | Light color scheme |
| `ig_style_classic()` | Classic ImGui colors |

### Backend Integration
| Function | Description |
|----------|-------------|
| `ig_init_for_vulkan(frame)` | Initialize GLFW+Vulkan backend |
| `ig_init_for_opengl(frame)` | Initialize GLFW+OpenGL backend |
| `ig_shutdown_backend()` | Shutdown current backend |
| `ig_render_vulkan(draw_data, cmd_buffer, pipeline)` | Render draw data with Vulkan |

## Window Flags
| Constant | Value | Description |
|----------|-------|-------------|
| `WINDOW_NO_TITLE_BAR` | 1 | Hide title bar |
| `WINDOW_NO_RESIZE` | 2 | Disable resizing |
| `WINDOW_NO_MOVE` | 4 | Disable moving |
| `WINDOW_NO_SCROLLBAR` | 8 | Hide scrollbar |
| `WINDOW_NO_COLLAPSE` | 16 | Disable collapsing |
| `WINDOW_ALWAYS_AUTO_RESIZE` | 32 | Auto-resize every frame |

## Safety Contracts
1. `ig_new_frame()` and `ig_render()` must be called in matching pairs.
2. Widgets must be called between `ig_new_frame()` and `ig_render()`.
3. Window content must be between `ig_begin()` and `ig_end()`.
4. Tree node content must be between `ig_tree_node()` (if true) and `ig_tree_pop()`.
5. Backend must be initialized before any rendering calls.
6. `ig_destroy_context()` must be called after `ig_shutdown_backend()`.

## External Dependencies
- **Runtime:** cimgui — `cimgui.dll` / `libcimgui.so` / `libcimgui.dylib`
- **Backend:** GLFW (`xiom-glfw` package)
- **Build:** Dear ImGui source (v1.89+), cimgui JSON generator
- **Link flags:** `-l cimgui -l cimgui_glfw -l cimgui_vulkan`
- **Compatibility:** Dear ImGui >= 1.89, GLFW >= 3.3

## Error Handling
1. Backend initialization failures return `Err(backend_error)`.
2. Missing context (calling widgets before `create_context`) is a contract violation.
3. Widget state changes are communicated via `Bool` return — no exceptions.
4. Draw data generation failures during `render()` return empty draw lists.
