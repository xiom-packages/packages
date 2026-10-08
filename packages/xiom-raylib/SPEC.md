# SPEC: xiom.raylib -- raylib bindings via dynamic loader

## 1. Identity

| Field | Value |
|-------|-------|
| Package | `xiom.raylib` |
| Version | 0.2.0 |
| Kind | binding (`keywords: ["binding"]`) |
| Upstream project | raylib -- https://github.com/raysan5/raylib |
| Upstream version pinned | **5.5** (tag `5.5`); 6.0 is the current upstream release -- next re-pin candidate (expect the `GetScreenWidth` -> `GetWindowWidth` rename; the loader already tolerates both) |
| Upstream license | zlib (bindings only; no code vendored) |
| Package license | MIT OR Apache-2.0 |
| Platform | Windows x64 (soname `raylib.dll`) |
| Compiler pin | v0.64.1 |

## 2. G2 pin: soname + header hash + symbol set

**Soname (runtime contract):** `raylib.dll` (official win64 release name).
The loader passes the soname to `LoadLibraryA` through `xiom.ffi.dl`; there is
no link-time dependency and nothing vendored.

**Header pin** (fetched verbatim from
`https://raw.githubusercontent.com/raysan5/raylib/5.5/src/raylib.h`):

| Header | Bytes | SHA256 |
|--------|-------|--------|
| `raylib.h` | 130,625 | `AFB287ECD313DE61E0000921375190B7E1CC35CD381AD6CAF914489473A3C871` |

**Resolved symbol set** (smoke API): `SetTraceLogLevel`, `SetConfigFlags`,
`InitWindow`, `IsWindowReady`, `WindowShouldClose`, `CloseWindow`,
`GetScreenWidth` (5.x; `GetWindowWidth` preferred when present), `GetScreenHeight`
(5.x; `GetWindowHeight` preferred), `GetTime`, `GetFrameTime`, `GetFPS`,
`SetTargetFPS`, `BeginDrawing`, `ClearBackground`, `EndDrawing`.

**Reference runtime sample used for local positive-path proof (NOT the pin):**

| Artifact | Value |
|----------|-------|
| Release archive | `raylib-5.5_win64_msvc16.zip`, 2,528,280 bytes, SHA256 `8D046084D12353183E701EF4C9D276C21FCD3243C2A368091FABFB2769B8507C` |
| DLL | `lib\raylib.dll`, 1,783,296 bytes, FileVersion 5.5.0, SHA256 `C8D29FBDA31417B900BB0220CFB6C288544264A93764F5EA7CF5727FEEC76994` |
| Runtime report | hidden 320x200 window ready, reported size 320x200, begin/clear/end frame completed |

### Re-pin procedure

1. Pick the new upstream tag (6.0 pending); re-fetch `src/raylib.h`, recompute
   its SHA256, update this table and the version rows in `README.md`/
   `AUDIT.md` in one commit.
2. Re-check the size-function names: the loader already prefers
   `GetWindowWidth`/`GetWindowHeight` and falls back to
   `GetScreenWidth`/`GetScreenHeight`, so both 5.x and 6.x resolve.
3. Re-run `scripts/port.ps1 -Package xiom.raylib` in both configurations
   (backend present and absent) and record the matrix in §4.

## 3. Design: dynamic loader (same pattern as xiom.sdl3 / xiom.glfw)

- **No link-time dependency.** `raylib_load` resolves `raylib.dll` at runtime
  through `xiom.ffi.dl`; every call is an fn-pointer cast inside `raylib.xi`
  (module `xiom.raylib`), the ONLY module in the package with `unsafe` (G5).
- **Classification**: backend missing -> `RAYLIB_LOAD_ABSENT` (SKIP);
  `InitWindow` produces no ready window (headless) -> `RAYLIB_LOAD_NO_WINDOW`
  (SKIP; the smoke sets `FLAG_WINDOW_HIDDEN` first so a desktop session
  proceeds); exports missing -> `RAYLIB_LOAD_ABI` (FAIL).
- **Public API (safe)**: `raylib_load`, `raylib_close`,
  `raylib_set_trace_log_level`, `raylib_set_config_flags`,
  `raylib_init_window`, `raylib_is_window_ready`,
  `raylib_window_should_close`, `raylib_close_window`, `raylib_window_size`,
  `raylib_get_time`, `raylib_get_frame_time`, `raylib_get_fps`,
  `raylib_set_target_fps`, `raylib_begin_drawing`, `raylib_clear_background`,
  `raylib_end_drawing`, plus the pure color helpers (`color_rgba`,
  `color_alpha/red/green/blue`) and constants.
- **No `port.args.json`**: pure-XIOM loader, no C source, no extra flags.
- The pre-pilot module called 26 static `extern "C"` raylib functions and
  required a system-installed raylib at link time; that could not satisfy the
  SKIP-when-absent gate and is preserved in git history only.

## 4. Test matrix (recorded 2026-10-08, compiler v0.64.1)

| Configuration | Command | Result |
|---------------|---------|--------|
| raylib absent (CI shape) | `port.ps1 -Package xiom.raylib`, no raylib.dll on PATH | **PASS 3/3 x2** (`loader: SKIP ... code 126`, `smoke: SKIP`) |
| raylib 5.5 present | same, with the official win64 `lib` dir prepended to PATH | **PASS 12/12 x2** (constants + color helpers, symbols, trace/config flags, hidden 320x200 window, size, time/frame time/FPS, target FPS + should-close, begin/clear/end frame, CloseWindow, release) |
| Headless present (no window) | not reproducible on this host; window checks SKIP with the `NO_WINDOW` kind | path implemented + code-reviewed, not force-tested |

## 5. Scope

Pilot smoke only: backend classification, hidden-window lifecycle, timing,
and a single frame. Textures, models, sounds, fonts, input and camera are
Phase 2 (`ROADMAP.md`).
