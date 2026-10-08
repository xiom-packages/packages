# xiom.sdl3

SDL3 (Simple DirectMedia Layer 3) bindings for XIOM via a **dynamic loader**:
`sdl3_load()` resolves `SDL3.dll` at runtime and every call goes through
resolved function pointers. No link-time dependency, no vendored code, no
build flags -- and the conformance suite reports **SKIP** (green) when SDL3
is not installed.

> **Status:** `incubating` -- suite green in both configurations on the pin
> (v0.64.0): 3/3 x2 without SDL3 (SKIP path), 10/10 x2 with SDL 3.4.8.
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
| Constants | `SDL_INIT_*`, a curated `SDL_WINDOW_*`/`SDL_EVENT_*` subset, `SDL3_SONAME`, `SDL3_LOAD_ABSENT`/`SDL3_LOAD_ABI` |

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
- With SDL3: 10 `[PASS]` (version, revision, init/was_init, ticks+delay,
  perf counter, pump/poll, quit, handle release), exit 0.

Full matrix + re-pin procedure: `SPEC.md` §4/§2. Window/renderer resources
are Phase 2 (`ROADMAP.md`).
