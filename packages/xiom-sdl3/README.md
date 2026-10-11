# xiom.sdl3

SDL3 (Simple DirectMedia Layer 3) bindings for XIOM via a **dynamic loader**:
`sdl3_load()` resolves `SDL3.dll` at runtime and every call goes through
resolved function pointers. No link-time dependency, no vendored code, no
build flags -- and the conformance suite reports **SKIP** (green) when SDL3
is not installed.

> **Status:** `incubating` -- **0.4.0 event decoding + runtime** (event layer:
> `SDL_Event` over an owned 128-byte buffer with typed accessors, offsets
> pinned to the release-3.4.8 headers and verified against the 3.2.10 clone).
> Suite **24/24 x2** with the official SDL 3.4.8 DLL (headless
> synthetic-event pump + KEY_DOWN injection, window/renderer/texture/gamepad,
> decode layer). **Lane:** bindings (`keywords: ["binding"]`).

## Quick start

```xiom
use xiom.io;
use xiom.sdl3;

fn main() {
  let l = sdl3_load();
  if !l.is_ok {
    io.println("SDL3 unavailable: " + l.error.message);  // SKIP in CI
    return;
  }
  let lib: Sdl3Library = l.value;
  if sdl3_init(&lib, SDL_INIT_TIMER | SDL_INIT_EVENTS) {
    sdl3_delay(&lib, 16);
    sdl3_pump_events(&lib);
    let had_event = sdl3_poll_event(&lib, 0);
    sdl3_quit(&lib);
  }
  let cl = sdl3_close(&lib);
}
```

## API

| Area | Functions |
|------|-----------|
| Loader | `sdl3_load`, `sdl3_close`, `Sdl3Library`, `Sdl3LoadError` |
| Lifecycle | `sdl3_init`, `sdl3_quit`, `sdl3_was_init` |
| Version | `sdl3_get_version`, `sdl3_get_revision`, `sdl3_versionnum`, `sdl3_version_major/minor/patch` |
| Timer | `sdl3_get_ticks`, `sdl3_get_performance_counter`, `sdl3_delay` |
| Events | `sdl3_pump_events`, `sdl3_poll_event`, `sdl3_push_event` |
| Event decode (0.4.0) | `sdl3_event_type`, `sdl3_event_timestamp`, `sdl3_event_window_id`, `sdl3_event_key_scancode/key_code/mods/down/repeat`, `sdl3_event_mouse_state/x_bits/y_bits/x/y/button/button_down/clicks`, `sdl3_event_window_data1/data2`, `sdl3_f32_from_bits`, `SDL_EVENT_SIZE` |
| Error | `sdl3_get_error` |
| Resources | `sdl3_load_resources`, `sdl3_resources_close`, `sdl3_create_window`, `sdl3_destroy_window`, `sdl3_show_window`, `sdl3_hide_window`, `sdl3_window_size`, `sdl3_set_window_title`, `sdl3_create_renderer`, `sdl3_destroy_renderer`, `sdl3_set_render_draw_color`, `sdl3_render_clear`, `sdl3_render_present`, `sdl3_create_texture`, `sdl3_destroy_texture`, `sdl3_has_gamepad`, `sdl3_gamepad_count`, `sdl3_open_gamepad`, `sdl3_close_gamepad` |
| Constants | `SDL_INIT_*`, `SDL_WINDOW_*`, `SDL_EVENT_*`, `SDL_PIXELFORMAT_RGBA8888`, `SDL_TEXTUREACCESS_*`, `SDL3_SONAME`, `SDL3_LOAD_*` |

Failure model: `sdl3_load` distinguishes **absent** (`kind =
SDL3_LOAD_ABSENT` -> callers SKIP) from **ABI mismatch** (`kind =
SDL3_LOAD_ABI` -> callers FAIL). Everything else is `Bool`/value returns
with contracts; no silent nulls.

## Runtime requirements

Put `SDL3.dll` (3.4.x) on the loader search path: next to the executable or
anywhere on `PATH`. G2 pin (soname + header-set manifest hash): `SPEC.md` §2.

## Tests

```
xiom --run tests/test_conformance.xi
```

- With SDL3: 24 `[PASS]` (decode layer + smoke + hidden window, renderer
  clear/present, RGBA8888 texture, gamepad enumeration, synthetic event
  injection), exit 0 (~10 s).
- Without SDL3: the loader smoke reports explicit `SKIP` labels and stays
  green; the decode layer runs in both shapes (pure XIOM; no DLL needed).

On a host where `C:\VulkanSDK\1.4.350.0\Bin` is on PATH (as on the dev
box), SDL3 is always found, so the absent shape is code-reviewed only.

Full matrix + re-pin procedure: `SPEC.md` §4/§2. The full constant tables,
texture updates/vsync and the POSIX soname remain (`ROADMAP.md`).
