# xiom.sdl3

SDL3 (Simple DirectMedia Layer 3) bindings for XIOM via a **dynamic loader**:
`sdl3_load()` resolves `SDL3.dll` at runtime and every call goes through
resolved function pointers. No link-time dependency, no vendored code, no
build flags -- and the conformance suite reports **SKIP** (green) when SDL3
is not installed.

> **Status:** `incubating` -- suite green on v0.64.1: 3/3 x2 without SDL3
> (SKIP path), 21/21 x2 with SDL 3.4.8 (smoke + window/renderer/texture/
> gamepad resources).
> **Lane:** bindings (`keywords: ["binding"]`).

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
| Events | `sdl3_pump_events`, `sdl3_poll_event` |
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

- Without SDL3: 3 `[PASS]` with explicit `SKIP` labels, exit 0.
- With SDL3: 21 `[PASS]` (smoke + hidden window, renderer clear/present,
  RGBA8888 texture, gamepad enumeration), exit 0.

Full matrix + re-pin procedure: `SPEC.md` §4/§2. Event decoding, the full
constant tables and the POSIX soname are the remaining Phase 2 items
(`ROADMAP.md`).
