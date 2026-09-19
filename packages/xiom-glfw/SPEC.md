# xiom.glfw -- SPEC

**Phase**: 1 (Core Foundation) | **Priority**: CRITICAL
**Status**: PRODUCTION -- v0.2.0, 17 safe wrappers, verified with v0.49.7
**Depends on**: xiom.ffi (stdlib)

## What it wraps
GLFW 3.4 -- cross-platform windowing and input library.
Window creation, keyboard/mouse input, monitor management, fullscreen toggle.

## Dependencies

| What | How | Size |
|------|-----|------|
| GLFW 3.4 | System-installed. `winget install glfw`, `apt install libglfw3-dev`. Set `GLFW_DIR`. | ~3MB DLL |
| C compiler | clang for building `glfw_bridge.obj` | -- |

## Bundling strategy
**System-installed only.** Never bundle GLFW.

## Architecture
```
xiom-glfw/
|-- glfw.xi              # 17 safe wrappers with contracts
|-- bridge/
|   |-- glfw_bridge.h    # Flat C ABI (18 functions)
|   |-- glfw_bridge.c    # Implementation
|   `-- glfw_bridge.obj  # Compiled
`-- tests/
    |-- test_conformance.xi  # 18 conformance tests
    |-- test_glfw.xi     # Lifecycle smoke
    `-- test_window.xi   # Integration smoke
```

## API (complete, all with requires contracts)

```xiom
pub type Window  = Int  // newtype, auto-converts to Int (v0.49.4+)
pub type Monitor = Int

pub fn glfw_init() -> Bool
pub fn glfw_terminate()
pub fn glfw_create_window(title, w, h) -> Result[Window, Str]
pub fn glfw_destroy_window(win)
pub fn glfw_should_close(win) -> Bool
pub fn glfw_set_title(win, title)
pub fn glfw_get_framebuffer_size(win) -> (Int, Int)
pub fn glfw_get_window_size(win) -> (Int, Int)
pub fn glfw_poll_events()
pub fn glfw_get_key(win, key) -> Bool
pub fn glfw_get_mouse_button(win, button) -> Bool
pub fn glfw_get_cursor_pos(win) -> (Float32, Float32)
pub fn glfw_get_primary_monitor() -> Monitor
pub fn glfw_get_video_mode(monitor) -> (Int, Int, Int)
pub fn glfw_set_fullscreen(win, monitor, w, h, refresh)
pub fn glfw_set_windowed(win, x, y, w, h)
pub fn glfw_toggle_fullscreen(win) -> Result[Unit, Str]
```

## Verified
- GLFW standalone test: 5s stable [OK]
- GLFW+Vulkan integration: 5s stable [OK]
- v0.49.5: Float32 tuple fix restored `glfw_get_cursor_pos` [OK]
- v0.49.4: Newtype auto-conversion for Window/Monitor [OK]
