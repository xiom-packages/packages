# xiom.raylib -- Roadmap

**Version**: v0.2.0 | **Compiler**: xiom v0.64.1 | **Last updated**: 2026-10-08

## Current state

| Criterion | Status |
|-----------|--------|
| Dynamic loader (no link dependency) | Done -- `raylib_load`/`raylib_close` over `xiom.ffi.dl` |
| SKIP-when-absent / no-window | Done -- `RAYLIB_LOAD_ABSENT` / `RAYLIB_LOAD_NO_WINDOW` |
| ABI-mismatch detection + 5.x/6.x size names | Done -- `RAYLIB_LOAD_ABI` + rename-tolerant resolution |
| Smoke suite (init/flags/timing/frame/close) | Done -- 12 checks present, 3 checks absent |
| G2 pin (soname + header + symbols) | Done -- `SPEC.md` §2 |
| Draw primitives (rect/circle/text) | Phase 2 |
| Textures / images | Phase 2 |
| Input (keys/mouse) | Phase 2 |
| Audio (sounds/music) | Phase 2 |
| Fonts (default + loaded) | Phase 2 |
| Camera helpers | Phase 2 |

## Phase 2 (next touches)

1. Draw primitives over the loader: `DrawRectangle`, `DrawCircle`,
   `DrawText`, `DrawLine`, `DrawRectangleRec` with the packed-color helpers;
   exercised inside a hidden-window frame in the suite.
2. Textures/images: `LoadTexture`, `UnloadTexture`, `LoadImage`,
   `ImageDraw*` with owned pixel buffers; file-path inputs documented
   relative to the package test directory.
3. Input: `IsKeyDown`, `IsMouseButtonDown`, `GetMouseX/Y`, `GetKeyPressed`
   behind the hidden-window capability gate.
4. Audio: `InitAudioDevice`, `LoadSound`, `PlaySound`, `CloseAudioDevice`
   (device-gated SKIP).
5. Fonts: `GetFontDefault`, `LoadFont`, `DrawTextEx`.
6. Camera: `SetCameraMode`, `UpdateCamera`, `UpdateCameraPro`.
7. Re-pin to raylib 6.0 when the native lane schedules it (the loader is
   already rename-tolerant; check for other API moves).
