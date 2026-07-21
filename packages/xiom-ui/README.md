# xiom-ui

> Immediate-mode GUI library for XIOM — layout engine, widgets, theming, and render commands.

[![XIOM](https://img.shields.io/badge/XIOM-v0.22.1-blue)](https://github.com/xiom-lang/XIOM)
[![License](https://img.shields.io/badge/license-MIT%2FApache--2.0-blue.svg)](LICENSE)

## Overview

xiom-ui is an immediate-mode GUI framework for XIOM. It provides a layout engine, widget state management, theming, and a render command buffer — all in pure XIOM. The render backend is pluggable (GLFW + Vulkan/OpenGL for actual rendering).

## Installation

```bash
xiom install xiom-ui
```

## Dependencies

### For rendering (backend-specific)
| Backend | Dependencies |
|---------|-------------|
| **GLFW + OpenGL** | `xiom-glfw`, system OpenGL |
| **GLFW + Vulkan** | `xiom-glfw`, `xiom-vulkan` |
| **Headless** | None (render commands only) |

## Quick Start

```xiom
use xiom.ui.types;
use xiom.ui.layout;
use xiom.ui.widgets;
use xiom.ui.render;
use xiom.ui.theme;
use xiom.ui.application;

fn main() -> Int {
  var app = UIApp.new("My App", 800.0, 600.0);
  var theme = theme_default();
  
  // Build UI
  app_begin_frame(&mut app);
  var rect = layout_row(&mut app.layout, 40.0, 3);  // 3-column row
  render_add_rect(&mut app.render_list, rect[0], theme.accent_color);
  app_end_frame(&mut app);
  
  return 0;
}
```

## API Reference

### Types (`xiom.ui.types`)
| Type | Description |
|------|-------------|
| `Rect` | Position + size |
| `Color` | RGBA (0.0-1.0) |
| `Point` | X, Y coordinate |
| `Size` | Width, height |
| `Padding` | Inner spacing |
| `Margin` | Outer spacing |
| `LayoutDirection` | Enum: Horizontal, Vertical |
| `Alignment` | Enum: Start, Center, End, Stretch |
| `MouseButton` | Enum: Left, Right, Middle |
| `InputState` | Mouse position, buttons, keys, scroll |

### Layout (`xiom.ui.layout`)
| Function | Description |
|----------|-------------|
| `layout_new()` | Create layout context |
| `layout_row(ctx, height, count)` | Divide into N columns |
| `layout_column(ctx, width, count)` | Divide into N rows |
| `layout_grid(ctx, w, h, cols, rows)` | Grid layout |
| `layout_push(ctx, size)` | Allocate next rect |
| `layout_remaining(ctx)` | Remaining space |
| `layout_with_margin(rect, margin)` | Shrink by margin |
| `layout_with_padding(rect, padding)` | Shrink by padding |
| `layout_align(outer, inner, h, v)` | Align child in parent |
| `layout_center(size)` | Center at origin |

### Widgets (`xiom.ui.widgets`)
| Type | Description |
|------|-------------|
| `ButtonState` | Pressed/hovered tracking |
| `CheckboxState` | Checked state |
| `TextFieldState` | Text + cursor + focus |
| `SliderState` | Value + dragging |
| `DropdownState` | Open + options + selected |
| `PanelState` | Scroll position |
| `TabsState` | Active tab + labels |

### Render (`xiom.ui.render`)
| Command | Description |
|---------|-------------|
| `RectCmd` | Filled rectangle |
| `TextCmd` | Text label |
| `CircleCmd` | Filled circle |
| `LineCmd` | Line segment |
| `ImageCmd` | Image by ID |
| `ClipCmd` | Clip region |

### Theme (`xiom.ui.theme`)
| Function | Description |
|----------|-------------|
| `theme_default()` | Light theme |
| `theme_dark()` | Dark theme |
| `theme_high_contrast()` | High contrast |

### Application (`xiom.ui.application`)
| Function | Description |
|----------|-------------|
| `UIApp.new(title, w, h)` | Create application |
| `app_begin_frame(app)` | Start frame |
| `app_end_frame(app)` | End frame |
| `app_should_close(app)` | Check close |
| `app_close(app)` | Close |

### Demo (`xiom.ui.demo`)
| Function | Description |
|----------|-------------|
| `demo_counter_app()` | Click-counter demo |
| `demo_form()` | Form with text fields, sliders |
| `demo_layout()` | Layout engine demo |

### Backend (`xiom.ui.backend`)
| Function | Description |
|----------|-------------|
| `backend_setup_viewport(w, h)` | Set orthographic projection |
| `backend_clear_bg(color)` | Clear with background color |
| `backend_render(list, theme, w, h)` | Dispatch all render commands to OpenGL |
| `backend_render_single(cmd)` | Render a single command |

## Build & Run

```bash
# Pure XIOM UI (no rendering, render commands only)
xiom --run myprogram.xi

# With OpenGL backend (requires GLFW + ffi_bridge.c)
xiom myprogram.xi ../runtime/ffi_bridge.c -l glfw3 -l opengl32 -o myprogram.exe
./myprogram.exe
```

> The `xiom.ui.backend` module requires ffi_bridge.c to be compiled alongside for `xiom_alloc`, `xiom_free_ptr`, `xiom_read_byte`, `xiom_write_byte`, `xiom_str_to_cstr`, and `xiom_free_cstr`. A GLFW window must be created via `xiom-glfw` before calling `backend_render`.

## Safety Contracts

All UI operations guarded:
- `Rect.new/Size.new`: requires w >= 0, h >= 0
- `Color.new`: requires each channel 0.0-1.0
- `layout_row/column/grid`: requires positive dimensions and counts
- `UIApp.new`: requires title.len() > 0, w > 0, h > 0

## Production Readiness

| Feature | Status | Notes |
|---------|--------|-------|
| Layout engine (flexbox-like) | ✅ Complete | Pure XIOM |
| Widget state types | ✅ Complete | 7 widget types |
| Render command buffer | ✅ Complete | 6 command types |
| Theme system | ✅ Complete | 3 presets |
| Application framework | ✅ Complete | Frame lifecycle |
| OpenGL render backend | ✅ OpenGL backend available | Via xiom.ui.backend + ffi_bridge.c |
| GLFW window integration | ❌ Not yet | Needs xiom-glfw FFI |
| Text rendering | ❌ Not yet | Needs font rasterizer |
| Widget hit-testing/interaction | ❌ Not yet | Mouse→widget dispatch |
| Animations | ❌ Not yet | |
| Drag and drop | ❌ Not yet | |
| Clipboard | ❌ Not yet | |
| File dialogs | ❌ Not yet | |

### What's Left for v1.0
1. **GLFW backend** — wire xiom-glfw for window creation + input
2. **Widget interaction loop** — hit-testing, focus management, event dispatch
3. **Text rendering** — font atlas generation, glyph placement
4. **Styling system** — CSS-like selector-based styling
5. **Vulkan backend** — alternative render backend beyond OpenGL

## Architecture

```
┌──────────────────────────────────┐
│  xiom.ui.application             │  ← App lifecycle
├──────────────────────────────────┤
│  xiom.ui.widgets                 │  ← Widget state
├──────────────────────────────────┤
│  xiom.ui.layout                  │  ← Layout calculation
├──────────────────────────────────┤
│  xiom.ui.render                  │  ← Render commands (pure data)
├──────────────────────────────────┤
│  xiom.ui.theme                   │  ← Theme presets
├──────────────────────────────────┤
│  xiom.ui.backend                 │  ← OpenGL render backend (FFI bridge)
├──────────────────────────────────┤
│  FFI Bridge + OpenGL             │  ← Platform-specific rendering
└──────────────────────────────────┘
```

## Links

- **Organization**: [github.com/xiom-lang](https://github.com/xiom-lang)
- **Language**: [github.com/xiom-lang/XIOM](https://github.com/xiom-lang/XIOM)

## License

MIT OR Apache-2.0
