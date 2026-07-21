# xiom-raylib — SPEC
**Phase**: 5 (Nice-to-Have) | **Priority**: Low
**Status**: SPEC + Implementation (v0.1.0) | **Depends on**: xiom.ffi

Raylib — simple game framework. System-installed. Weekend effort.

## Architecture

```
xiom-raylib/
??? SPEC.md                    (this file)
??? ROADMAP.md                 (versioned milestones)
??? raylib.xi                  (module xiom.raylib — types, FFI, constants, safe wrappers)
??? tests/
    ??? test_conformance.xi    (37 tests covering types, constants, helpers)
```

## Module: `xiom.raylib`

### Types (8 newtypes — all `Int` aliases)
`RlWindow`, `RlTexture`, `RlShader`, `RlModel`, `RlSound`, `RlMusic`, `RlCamera`, `RlFont`

### extern "C" (26 functions)
InitWindow, CloseWindow, WindowShouldClose, BeginDrawing, EndDrawing, ClearBackground,
DrawRectangle, DrawCircle, DrawText, DrawTexture, DrawModel, LoadTexture, UnloadTexture,
LoadModel, UnloadModel, LoadSound, PlaySound, SetCameraMode, UpdateCamera,
GetMouseX, GetMouseY, IsKeyDown, IsMouseButtonDown, GetFrameTime, SetTargetFPS,
LoadFont, DrawTextEx

### Constants (100+)
- **Colors (26)**: RAYWHITE, WHITE, BLACK, BLANK, LIGHTGRAY, GRAY, DARKGRAY, RED, MAROON,
  GREEN, LIME, DARKGREEN, BLUE, SKYBLUE, DARKBLUE, YELLOW, GOLD, ORANGE, PINK, MAGENTA,
  PURPLE, VIOLET, DARKPURPLE, BEIGE, BROWN, DARKBROWN
- **Keys (100+)**: Full keyboard map (alphanumeric, arrows, F-keys, keypad, modifiers)
- **Mouse (7)**: LEFT, RIGHT, MIDDLE, SIDE, EXTRA, FORWARD, BACK
- **Camera (4)**: FREE, FIRST_PERSON, THIRD_PERSON, ORBITAL
- **FPS (5)**: MIN, MAX, FPS_60, FPS_120, FPS_144

### Safe Wrappers (28 functions with contracts)
- **Window**: init_window, close_window, should_close
- **Drawing**: begin_drawing, end_drawing, clear_background, draw_rectangle, draw_circle, draw_text
- **Resources**: load_texture, unload_texture, draw_texture, load_model, unload_model, draw_model
- **Audio**: load_sound, play_sound
- **Camera**: set_camera_mode, update_camera
- **Input**: get_mouse_position, is_key_down, is_mouse_button_down
- **Timing**: get_frame_time, set_target_fps
- **Text**: load_font, draw_text_ex

### Color Helpers (5 pure functions)
`color_rgba(r,g,b,a)`, `color_alpha(c)`, `color_red(c)`, `color_green(c)`, `color_blue(c)`

All with `requires`/`ensures` contracts for bounds checking.

### Tests (37)
- 8 type construction tests
- 8 color constant value tests
- 5 key constant tests
- 3 mouse button tests
- 2 camera mode tests
- 2 FPS constant tests
- 7 color helper function tests
- 2 cross-constant consistency tests

## Dependencies
- `xiom.ffi` (stdlib FFI module)
- `xiom.test` (test framework)
- `xiom.io` (test output)
- System-installed raylib v5.5+ (link-time)
