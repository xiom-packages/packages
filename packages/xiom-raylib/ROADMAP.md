# xiom.raylib -- ROADMAP

## v0.1.0 (Current -- SPEC Implementation)
- [x] `raylib.xi`: Module `xiom.raylib` with 8 newtypes, 26 extern "C" declarations
- [x] 40+ color/key/mouse/camera/FPS constants
- [x] 5 pure color helper functions (`color_rgba`, `color_alpha`, `color_red`, `color_green`, `color_blue`)
- [x] 28 safe wrappers with `requires`/`ensures` contracts
- [x] 37 conformance tests in `tests/test_conformance.xi`

## v0.2.0 -- C Bridge Layer
- [ ] Implement `raylib_bridge.c` -- thin C wrapper linking raylib symbols
- [ ] Build system integration (CMake/Meson) for `xiom` + raylib
- [ ] Replace raw FFI stubs with bridge function calls
- [ ] Enable runtime FFI tests to validate actual raylib linking
- [ ] Add `GetScreenWidth()` / `GetScreenHeight()` wrappers

## v0.3.0 -- Full API Surface
- [ ] Add remaining raylib functions: shapes, textures, models, shaders
- [ ] `Vector2`, `Vector3`, `Vector4`, `Matrix`, `Rectangle`, `Color` struct types
- [ ] Shader uniforms API (`GetShaderLocation`, `SetShaderValue`)
- [ ] Render textures (`LoadRenderTexture`, `BeginTextureMode`)
- [ ] Audio streaming (`LoadMusicStream`, `UpdateMusicStream`)
- [ ] 100+ conformance tests covering full API surface

## v0.4.0 -- Ergonomics & Safety
- [ ] RAII resource management (auto-unload on scope exit)
- [ ] `Result` return types for fallible operations
- [ ] Input event polling (not just frame-based input)
- [ ] Window icon / cursor / clipboard support
- [ ] Gamepad / touch input
- [ ] Custom logging callback integration with `xiom.log`

## v0.5.0 -- Ecosystem Integration
- [ ] `xiom-raylib-ui` -- immediate-mode GUI on raylib canvas
- [ ] `xiom-raylib-physics` -- raylib + bullet/box2d interop
- [ ] `xiom-raylib-net` -- networked multiplayer primitives
- [ ] Examples: Pong, Snake, platformer, 3D viewer
- [ ] Documentation & tutorials
