# xiom.raylib

raylib (game/graphics library) bindings for XIOM via a **dynamic loader**:
`raylib_load()` resolves `raylib.dll` at runtime and every call goes through
resolved function pointers. No link-time dependency, no vendored code, no
build flags -- and the conformance suite reports **SKIP** (green) when raylib
is not installed.

> **Status:** `incubating` -- suite green on the pin (v0.64.1): 3/3 x2 without
> raylib (SKIP path), 12/12 x2 with raylib 5.5.0.
> **Lane:** bindings (`keywords: ["binding"]`).

## Quick start

```xiom
use xiom.io;
use xiom.convert;
use xiom.raylib;

fn main() {
  let l = raylib_load();
  if !l.is_ok {
    io.println("raylib unavailable: " + l.error.message);  // SKIP in CI
    return;
  }
  let lib: RaylibLibrary = l.value;
  raylib_set_trace_log_level(&lib, LOG_WARNING);
  raylib_set_config_flags(&lib, FLAG_WINDOW_HIDDEN);   // headless-friendly
  raylib_init_window(&lib, 320, 200, "xiom-raylib");
  if raylib_is_window_ready(&lib) {
    raylib_set_target_fps(&lib, 60);
    raylib_begin_drawing(&lib);
    raylib_clear_background(&lib, color_rgba(20, 40, 60, 255));
    raylib_end_drawing(&lib);
    raylib_close_window(&lib);
  }
  let cl = raylib_close(&lib);
}
```

## API

| Area | Functions |
|------|-----------|
| Loader | `raylib_load`, `raylib_close`, `RaylibLibrary`, `RaylibLoadError`, `RaylibWindowSize` |
| Lifecycle | `raylib_set_trace_log_level`, `raylib_set_config_flags`, `raylib_init_window`, `raylib_is_window_ready`, `raylib_window_should_close`, `raylib_close_window` |
| Window info | `raylib_window_size` |
| Timing | `raylib_get_time`, `raylib_get_frame_time`, `raylib_get_fps`, `raylib_set_target_fps` |
| Frame | `raylib_begin_drawing`, `raylib_clear_background`, `raylib_end_drawing` |
| Colors | `color_rgba`, `color_alpha/red/green/blue`, `RAYWHITE/BLACK/RED/GREEN/BLUE` |
| Constants | `LOG_*`, `FLAG_WINDOW_HIDDEN`, `KEY_ESCAPE`, `MOUSE_BUTTON_*`, `RAYLIB_LOAD_*` |

Failure model: absent backend -> SKIP; no ready window (headless) -> SKIP
(set `FLAG_WINDOW_HIDDEN` to make desktop sessions proceed); exports missing
-> FAIL.

## Runtime requirements

Put `raylib.dll` (5.5.x) on the loader search path: next to the executable or
anywhere on `PATH`. The loader accepts both the 5.x `GetScreenWidth/Height`
and the 6.x `GetWindowWidth/Height` exports. G2 pin: `SPEC.md` §2.

## Tests

```
scripts/port.ps1 -Package xiom.raylib
```

- Without raylib: 3 `[PASS]` with explicit SKIP labels, exit 0.
- With raylib: 12 `[PASS]` (hidden window, size, timing, frame, close),
  exit 0.

Textures/models/sounds/fonts/input are Phase 2 (`ROADMAP.md`).
