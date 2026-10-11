# xiom.glfw

GLFW **3.4** bindings for XIOM via a **dynamic loader** (no link-time
dependency; `glfw3.dll` resolved at runtime; the suite SKIPs green when the
backend is absent).

> **Status:** `incubating` -- **full surface (0.5.0, 124/124 core exports)**:
> init/hints, window lifecycle + attributes, events (poll/wait), input
> polling, monitors + video modes, clipboard, time, GL-context basics,
> gamma ramps, cursors, window icons, joystick/gamepad polling, the **20
> event-callback setters**, `glfwInitAllocator`, Win32 native accessors and
> the Vulkan helpers. Native verified on v0.64.3: **present 37/37 x2**
> (official GLFW 3.4 win64 DLL) + **absent SKIP 3/3**; two native fixes rode
> the verification (negative-float `f64_from_bits` clause; layout-invariant
> key-name check -- see SPEC section 4). 0.4.0 shipped in `eco-v0.1.136`
> (sha256 `c393b079...`); 0.5.0 published in `eco-v0.1.137` (sha256
> `04ad5ed2...`).
> **Lane:** bindings (`keywords: ["binding"]`).

## Quick start

```xiom
use xiom.io;
use xiom.glfw;

fn on_key(win: Int, key: Int32, scancode: Int32, action: Int32, mods: Int32) -> Unit {
  if action == GLFW_PRESS { io.println("key " + int_to_string(key)); }
}

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
    let _ = glfw_set_key_callback(&lib, &w, on_key);
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

## API (full surface)

| Area | Functions |
|------|-----------|
| Loader | `glfw_load`, `glfw_close`, `glfw_init`, `glfw_terminate` |
| Hints | `glfw_default_window_hints`, `glfw_window_hint`, `glfw_window_hint_string`, `glfw_init_hint` |
| Window | `glfw_create_window`, `glfw_destroy_window`, `glfw_window_should_close`, `glfw_set_window_should_close`, title/pos/size/framebuffer/frame/content-scale/opacity getters+setters, show/hide/focus/iconify/restore/maximize, fullscreen get/set, attributes, user pointer |
| Events | `glfw_poll_events`, `glfw_wait_events`, `glfw_wait_events_timeout`, `glfw_post_empty_event` |
| Input | `glfw_get_key`, `glfw_get_key_name`, `glfw_get_key_scancode`, `glfw_get_mouse_button`, `glfw_get_cursor_pos`, `glfw_set_cursor_pos`, input modes, raw-mouse query |
| Monitors | enumeration (raw handles), primary, pos/workarea/physical size/content scale/name, video modes (raw buffer + decode), gamma |
| Clipboard/Time | clipboard get/set, get/set time, timer ticks + frequency |
| Callbacks | `glfw_set_error/monitor/joystick_callback`, window pos/size/close/refresh/focus/iconify/maximize/framebuffer/content-scale, `glfw_set_key/char/char_mods/mouse_button/cursor_pos/cursor_enter/scroll/drop_callback` (handler types mirror the C signatures; window handlers receive the window handle) |
| Allocator | `glfw_init_allocator_raw` (`GLFWallocator` struct built in an XIOM slot; callbacks are top-level fns cast with `as Int`) |
| Native + Vulkan | `glfw_get_win32_adapter/monitor/window` (HWND), `glfw_vulkan_supported`, `glfw_get_required_instance_extensions`, `glfw_get_instance_proc_address`, `glfw_get_physical_device_presentation_support`, `glfw_create_window_surface` |

**Callback model:** each event type has one fixed top-level dispatcher whose
address crosses into the DLL; user handlers live in a registry and are
invoked by the dispatcher (the XIOM-fn -> C-pointer ABI is only reliable for
bare top-level fn names on v0.64.3 -- finding B-13). Handlers are
process-global per event type (last set wins); multi-window callers route on
the window handle passed to the handler.

**Known limitations (compiler v0.64.3):** floating-point RETURNS through
fn-pointer cast calls are miscompiled (0/garbage), so `glfwGetTime` /
`glfwGetWindowOpacity` values are unverifiable (the call path is still
exercised; the suite labels the skip). Repro + filing:
`docs/repro/bindings-pilot/glfw-fp-return/`. Vec-of-struct element
extraction also miscompiles (AV), so monitors/video modes use `Int` handles
and raw byte buffers. fn-typed function PARAMETER values cannot be used as C
callbacks (`0`; finding B-13, repro in
`docs/repro/bindings-pilot/cb-abi/`) -- the dispatcher + registry design
above avoids the path entirely.

## Tests

```
$env:PATH = "C:\glfw-3.4.bin.WIN64\lib-vc2022;" + $env:PATH
scripts/port.ps1 -Package xiom.glfw
```
(`port.args.json` links `user32` for the deterministic `PostMessageA`
key/close callback round trips.)

Expected: 37 `[PASS]`, exit 0 with GLFW 3.4 on PATH (~15 s); without the
DLL the suite prints explicit SKIP labels and stays green.
