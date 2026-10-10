# xiom.glfw

GLFW **3.4** bindings for XIOM via a **dynamic loader** (no link-time
dependency; `glfw3.dll` resolved at runtime; the suite SKIPs green when the
backend is absent).

> **Status:** `incubating` -- engine surface (0.3.0): init/hints, window
> lifecycle + attributes, events (poll/wait), input polling, monitors +
> video modes, clipboard, time, GL-context basics, Win32 native accessors
> and the Vulkan helpers (`glfwVulkanSupported`, required instance
> extensions, `glfwCreateWindowSurface`). Positive-path suite: 28/28 x2
> with the official 3.4 win64 DLL.
> **Lane:** bindings (`keywords: ["binding"]`).

## Quick start

```xiom
use xiom.io;
use xiom.glfw;

fn main() {
  let l = glfw_load();
  if !l.is_ok { io.println("no GLFW: " + l.error.message); return; }
  let lib: GlfwLibrary = l.value;

  glfw_default_window_hints(&lib);
  glfw_window_hint(&lib, GLFW_VISIBLE, GLFW_FALSE);
  glfw_window_hint(&lib, GLFW_CLIENT_API, GLFW_NO_API);
  let cw = glfw_create_window(&lib, 1280, 720, "xiom window", 0, 0);
  if cw.is_ok {
    let w: GlfwWindow = cw.value;
    while !glfw_window_should_close(&lib, &w) {
      glfw_poll_events(&lib);
      // draw here (Vulkan: glfw_create_window_surface / get_win32_window)
    }
    glfw_destroy_window(&lib, &w);
  }
  glfw_terminate(&lib);
  glfw_close(&lib);
}
```

## API (engine surface)

| Area | Functions |
|------|-----------|
| Loader | `glfw_load`, `glfw_close`, `glfw_init`, `glfw_terminate` |
| Hints | `glfw_default_window_hints`, `glfw_window_hint`, `glfw_window_hint_string`, `glfw_init_hint` |
| Window | `glfw_create_window`, `glfw_destroy_window`, `glfw_window_should_close`, `glfw_set_window_should_close`, title/pos/size/framebuffer/frame/content-scale/opacity getters+setters, show/hide/focus/iconify/restore/maximize, fullscreen get/set, attributes, user pointer |
| Events | `glfw_poll_events`, `glfw_wait_events`, `glfw_wait_events_timeout`, `glfw_post_empty_event` |
| Input | `glfw_get_key`, `glfw_get_key_name`, `glfw_get_key_scancode`, `glfw_get_mouse_button`, `glfw_get_cursor_pos`, `glfw_set_cursor_pos`, input modes, raw-mouse query |
| Monitors | enumeration (raw handles), primary, pos/workarea/physical size/content scale/name, video modes (raw buffer + decode), gamma |
| Clipboard/Time | clipboard get/set, get/set time, timer ticks + frequency |
| Native + Vulkan | `glfw_get_win32_adapter/monitor/window` (HWND), `glfw_vulkan_supported`, `glfw_get_required_instance_extensions`, `glfw_get_instance_proc_address`, `glfw_get_physical_device_presentation_support`, `glfw_create_window_surface` |

Cursors, joystick/gamepad, gamma ramps, window icons and the event-callback
setters are 0.4.0 (`ROADMAP.md`).

**Known limitations (compiler v0.64.2):** floating-point RETURNS through
fn-pointer cast calls are miscompiled (0/garbage), so `glfwGetTime` /
`glfwGetWindowOpacity` values are unverifiable (the call path is still
exercised; the suite labels the skip). Repro + filing:
`docs/repro/bindings-pilot/glfw-fp-return/`. Vec-of-struct element
extraction also miscompiles (AV), so monitors/video modes use `Int` handles
and raw byte buffers.

## Tests

```
$env:PATH = "C:\glfw-3.4.bin.WIN64\lib-vc2022;" + $env:PATH
scripts/port.ps1 -Package xiom.glfw
```

Expected: 28 `[PASS]`, exit 0 with GLFW 3.4 on PATH (~12 s); without the
DLL the suite prints explicit SKIP labels and stays green.
