# XIOM-UI Specification

## Overview

XIOM-UI is an immediate-mode GUI (IMGUI) library for the XIOM programming language. It provides types, layout engine, widget state management, render command generation, theme system, and application framework for building user interfaces. The library is platform-agnostic: all UI logic is computed in pure XIOM, with rendering and windowing delegated to FFI backends.

## Architecture

```
┌─────────────────────────────────────────────────┐
│                   Application                    │
│  (src/application.xi — UIApp lifecycle)          │
├──────────────┬──────────────────┬───────────────┤
│   Widgets    │     Layout       │    Theme      │
│ (widgets.xi) │  (layout.xi)    │  (theme.xi)   │
├──────────────┴──────────────────┴───────────────┤
│                Render Commands                   │
│           (src/render.xi — RenderList)           │
├─────────────────────────────────────────────────┤
│               Core Types                         │
│           (src/types.xi — Rect, Color, etc.)     │
└─────────────────────────────────────────────────┘
                         │
                         ▼
              ┌─────────────────────┐
              │   FFI Backend       │
              │ (GLFW + Vulkan/GL)  │
              └─────────────────────┘
```

### Module Dependencies

| Module | Depends On | Description |
|--------|-----------|-------------|
| `xiom.ui.types` | — | Core geometry, input, and color types |
| `xiom.ui.layout` | `types` | Flexbox-like immediate-mode layout engine |
| `xiom.ui.widgets` | `types` | Widget state types (button, checkbox, etc.) |
| `xiom.ui.render` | `types` | Platform-agnostic render command list |
| `xiom.ui.theme` | `types` | Theming with light/dark/high-contrast presets |
| `xiom.ui.application` | `types`, `render`, `theme` | UIApp lifecycle (begin/end frame, render loop) |
| `xiom.ui.demo` | `application`, `widgets`, `layout`, `render`, `theme`, `types` | Demo apps |

## Core Types (types.xi)

### Geometry

- **Rect** — Rectangle with `(x, y, w, h)` in Float32
- **Point** — 2D point `(x, y)` in Float32
- **Size** — Dimensions `(w, h)` in Float32
- **Padding** — Edges `(top, right, bottom, left)` in Float32
- **Margin** — Edges `(top, right, bottom, left)` in Float32

### Color

RGBA color with Float32 components in range `[0.0, 1.0]`. Predefined constants: `RED`, `GREEN`, `BLUE`, `WHITE`, `BLACK`, `GRAY`, `TRANSPARENT`.

### Enums

- **LayoutDirection**: `Horizontal | Vertical`
- **Alignment**: `Start | Center | End | Stretch`
- **TextAlign**: `Left | Center | Right`
- **MouseButton**: `Left | Right | Middle`

### Input

**InputState** captures per-frame input:
- `mouse_x`, `mouse_y` — cursor position
- `mouse_down` — `Vec[Bool]` indexed by MouseButton ordinal
- `keys_down` — `Vec[Int]` of currently pressed key codes
- `scroll` — scroll delta

## Widget Catalog (widgets.xi)

Each widget has a state type with an `id: Int` field for instance tracking across frames.

| Widget | State Type | Key Fields |
|--------|-----------|------------|
| Button | `ButtonState` | `pressed`, `hovered` |
| Checkbox | `CheckboxState` | `checked` |
| Text Field | `TextFieldState` | `text`, `cursor`, `focused` |
| Slider | `SliderState` | `value`, `min`, `max`, `dragging` |
| Dropdown | `DropdownState` | `open`, `selected`, `options` |
| Panel | `PanelState` | `scroll_x`, `scroll_y` |
| Tabs | `TabsState` | `active_tab`, `tabs` |

All widget states have `.new(id)` constructors. Widget rendering logic (producing RenderCommands) is implemented in the application layer using these state types.

## Layout System (layout.xi)

### LayoutContext

A cursor-based immediate-mode layout engine. The context maintains:
- Origin `(x, y)` and available `(w, h)` region
- A cursor `(cursor_x, cursor_y)` that advances as children are allocated
- `direction` (Horizontal/Vertical), `spacing`, and `padding`

### API

| Function | Description |
|----------|-------------|
| `LayoutContext.new()` | Create default context |
| `begin(x, y, w, h)` | Initialize layout region with padding |
| `allocate(size) -> Rect` | Allocate rect at cursor and advance |
| `allocate_fill(cross_size) -> Rect` | Allocate and fill remaining space along axis |
| `remaining() -> Rect` | Remaining layout space |
| `layout_row(ctx, height, count) -> Vec[Rect]` | Divide row into N equal columns |
| `layout_column(ctx, width, count) -> Vec[Rect]` | Divide column into N equal rows |
| `layout_grid(ctx, cols, rows, cw, ch) -> Vec[Rect]` | Grid allocation |
| `layout_push(ctx, size) -> Rect` | Alias for allocate |
| `layout_remaining(ctx) -> Rect` | Alias for remaining |
| `layout_with_margin(rect, margin) -> Rect` | Shrink rect by margin |
| `layout_with_padding(rect, padding) -> Rect` | Shrink rect by padding |
| `layout_align(outer, inner, halign, valign) -> Rect` | Align child in parent |
| `layout_center(size) -> Rect` | Centered rect at (0,0) |

## Render Commands (render.xi)

### RenderCommand

Platform-agnostic enum:

- `RectCmd(rect, color)` — filled rectangle
- `TextCmd(text, pos, color, size)` — text label
- `CircleCmd(center, radius, color)` — filled circle
- `LineCmd(start, end, color, width)` — line segment
- `ImageCmd(rect, image_id)` — textured quad
- `ClipCmd(rect)` — scissor/clip rect

### RenderList

Collects commands per frame. API: `new()`, `clear()`, `add_rect()`, `add_text()`, `add_text_sized()`, `add_circle()`, `add_line()`, `add_image()`, `add_clip()`, `command_count()`, `is_empty()`, `get_command()`.

## Theme System (theme.xi)

### Theme

| Field | Type | Description |
|-------|------|-------------|
| `bg_color` | Color | Background fill |
| `text_color` | Color | Text fill |
| `accent_color` | Color | Primary accent (buttons, highlights) |
| `border_color` | Color | Borders and separators |
| `hover_color` | Color | Hover state fill |
| `active_color` | Color | Active/pressed state fill |
| `font_scale` | Float32 | Global font size multiplier |
| `corner_radius` | Float32 | Rounded corner radius in logical pixels |

### Presets

| Function | Style |
|----------|-------|
| `theme_default()` | Light theme (white/gray backgrounds) |
| `theme_dark()` | Dark theme (dark gray backgrounds) |
| `theme_high_contrast()` | Black background, white text, yellow accent, larger font |

## Application Framework (application.xi)

### UIApp

| Field | Description |
|-------|-------------|
| `running` | Main loop control flag |
| `width`, `height` | Window dimensions |
| `input` | Per-frame `InputState` |
| `theme` | Active `Theme` |
| `render_list` | Per-frame `RenderList` |

### Frame Protocol

```xiom
app.begin_frame();  // clears render list, resets input
// ... widget/layout/render calls ...
app.end_frame();    // finalizes render list
```

### Lifecycle API

| Function | Description |
|----------|-------------|
| `UIApp.new(title, w, h)` | Create application window |
| `should_close() -> Bool` | Check exit flag |
| `begin_frame()` | Start new frame |
| `end_frame()` | End frame |
| `run()` | Enter main loop (stub) |
| `close()` | Signal exit |
| `set_theme(t)` | Change theme |
| `set_input(i)` | Inject input state |

## FFI Backend Requirements

To render XIOM-UI, a backend must implement:

### Window System (e.g., GLFW)

1. Create a native window
2. Poll events (mouse move, mouse button, keyboard, scroll, resize, close)
3. Translate events into `InputState`
4. Call `app.set_input(input)` each frame
5. Implement `app.run()` as the actual while loop

### Graphics (e.g., Vulkan, OpenGL, DirectX, Metal)

1. Set up rendering context (swapchain, shaders, vertex buffers)
2. At end of frame, iterate `app.render_list.commands`
3. Translate each `RenderCommand` variant to draw calls:
   - `RectCmd` → draw filled quad (optionally with rounded corners from `theme.corner_radius`)
   - `TextCmd` → rasterize glyphs via stb_truetype or similar, draw textured quads
   - `CircleCmd` → draw filled circle via triangle fan
   - `LineCmd` → draw line strip
   - `ImageCmd` → draw textured quad from image atlas
   - `ClipCmd` → set scissor rectangle
4. Present the frame

### Example Integration (conceptual)

```xiom
module xiom.ui.backend_glfw_vulkan

fn run_app(title: Str, w: Float32, h: Float32) -> Result[Unit, Str] {
  var app = UIApp.new(title, w, h);
  var window = glfw.create_window(title, w, h);

  while !glfw.window_should_close(window) {
    glfw.poll_events();
    var input = glfw.get_input_state(window);
    app.set_input(input);
    app.begin_frame();
    render_ui(&mut app);
    app.end_frame();
    vulkan.render_commands(&app.render_list);
    vulkan.present();
  }

  return Ok(Unit{});
}
```

## Demo Applications (demo.xi)

Three reference implementations:

1. **demo_counter_app()** — Button click increments a counter. Demonstrates basic widget interaction and immediate-mode state tracking.

2. **demo_form()** — Form with text fields (Name, Email), checkbox (Subscribe), slider (Volume), and submit button. Demonstrates multiple widget types in a form layout.

3. **demo_layout()** — Layout engine showcase with `layout_row` (3 columns), `layout_column` (3 rows), and `layout_grid` (4×2). Demonstrates nested layout capabilities with colored regions.

## Future Enhancements

- **Event System**: `pub enum UIEvent` for input routing
- **Style Sheets**: JSON/XIOM-driven styling separate from Theme
- **Animations**: Tween system for animated transitions
- **Drag & Drop**: Drag source and drop target abstractions
- **Tables**: Row/column-based data display with headers
- **Tree View**: Expandable hierarchical list
- **Menu Bar**: Menu and context menu system
- **Rich Text**: Multi-font, multi-color text with word wrap
- **Offscreen Rendering**: Render-to-texture for cached UIs
