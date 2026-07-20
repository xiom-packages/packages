# xiom-glfw

Safe GLFW bindings for XIOM. Window creation, input, DPI, monitors.
Zero Vulkan dependency. Use with xiom-vulkan for GPU rendering.

## Prerequisites

Install GLFW:
```powershell
# Windows
winget install glfw
# or download from https://www.glfw.org/download.html
# Set GLFW_DIR environment variable:
$env:GLFW_DIR = "C:\glfw-3.4.bin.WIN64"
```
```bash
# Linux
sudo apt install libglfw3-dev
# macOS
brew install glfw
```

## Usage

```xiom
use xiom.glwf;

fn main() -> Int {
  if !init() { return 1; }
  let win = create_window("My App", 1280, 800)?;

  while !should_close(win) {
    poll_events();
    let (fw, fh) = get_framebuffer_size(win);
    // ... render with xiom-vulkan ...
  }

  destroy_window(win);
  terminate();
  return 0;
}
```

## API

| Function | Description |
|----------|-------------|
| `init()` / `terminate()` | GLFW lifecycle |
| `create_window(title, w, h)` | Create a window → `Result[Window, Str]` |
| `destroy_window(win)` | Destroy a window |
| `should_close(win)` | Check if window should close |
| `poll_events()` | Process pending events |
| `get_key(win, key)` | Check key state |
| `get_framebuffer_size(win)` | Framebuffer in pixels |
| `get_window_size(win)` | Window in screen coordinates |
| `toggle_fullscreen(win)` | Toggle between fullscreen and windowed |
| `get_primary_monitor()` | Get primary monitor |
| `get_video_mode(monitor)` | Monitor native resolution |

## Dependencies

| What | How |
|------|-----|
| GLFW 3.4 | System-installed. Set `GLFW_DIR`. |
| C compiler (clang) | For building the bridge .obj |

**No other dependencies.** No Vulkan. No ImGui. Pure GLFW.
