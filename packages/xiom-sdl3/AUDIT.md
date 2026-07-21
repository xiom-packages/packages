# xiom-sdl3 — Build Dependency Audit

## Required Dependencies

| Dependency | Version | Purpose |
|-----------|---------|---------|
| SDL3 | >= 3.4.8 | Cross-platform graphics/input/audio library |
| Vulkan SDK | >= 1.4.350.0 | Ships SDL3 headers at Include/SDL3/ |
| SDL3.dll / libSDL3.so | >= 3.4.8 | Runtime library (dynamic link) |
| clang/LLVM | >= 14 | C bridge compilation |
| Rust/Cargo | Latest stable | Compiler build (xiom) |
| xiom | >= v0.46.0 | XIOM compiler (hex literals, FNPTR, string concat) |

## SDL3 Source

SDL3 is a C library distributed as headers + dynamic library:

| Item | Location | Size |
|------|----------|------|
| SDL3 headers (86 files) | `C:\VulkanSDK\1.4.350.0\Include\SDL3\` | ~500 KB total |
| SDL3.dll | System or Vulkan SDK bin directory | ~2 MB |

The Vulkan SDK (1.4.350.0) ships SDL 3.4.8 headers bundled in its include directory.
The runtime DLL must be installed separately or placed alongside the executable.

### SDL3 Integration

SDL3 is a traditional shared library:

1. Include SDL3 headers in C bridge compilation
2. Link against `SDL3.dll` / `libSDL3.so` / `libSDL3.dylib`
3. The library exports C functions with `extern SDL_DECLSPEC` (resolves to `__declspec(dllimport)` on Windows)

SDL3 requires no `#define IMPLEMENTATION` — it is a pre-built library, not a single-header.

## Platform-Specific Installation

### Windows
1. **Vulkan SDK**: Install from https://vulkan.lunarg.com/sdk/home
   - Sets `VULKAN_SDK` environment variable automatically
   - SDL3 headers at `%VULKAN_SDK%\Include\SDL3\`
2. **SDL3 Runtime**: Download SDL3.dll from https://github.com/libsdl-org/SDL/releases
   - Place `SDL3.dll` next to the executable or in `C:\Windows\System32\`
3. **clang**: Install via LLVM from https://releases.llvm.org/ or `winget install LLVM.LLVM`

### Linux
```bash
# SDL3
# Ubuntu/Debian: apt install libsdl3-dev
# Arch: pacman -S sdl3
# Or build from source: https://github.com/libsdl-org/SDL

# clang
sudo apt install clang
```

### macOS
```bash
# SDL3
brew install sdl3

# clang
# Ships with Xcode Command Line Tools
```

## Package Structure

```
packages/xiom-sdl3/
├── package.xi              # Package manifest (name, version, deps)
├── sdl3.xi                 # Module xiom.sdl3 — raw FFI + core safe wrappers
├── src/
│   └── sdl3_safe.xi        # Module xiom.sdl3.safe — struct-based wrappers
├── examples/
│   └── demo_sdl3.xi        # Module xiom.sdl3.demo — compile-time demo
└── AUDIT.md                # This file
```

## FFI Binding Coverage

### sdl3.xi — Module `xiom.sdl3`

**115 extern C function declarations** from SDL3 v3.4.8 across 17 subsystems:

| Subsystem | Functions | Key Functions |
|-----------|-----------|---------------|
| SDL_init.h | 7 | SDL_Init, SDL_InitSubSystem, SDL_QuitSubSystem, SDL_WasInit, SDL_Quit, SDL_IsMainThread, SDL_SetAppMetadata |
| SDL_version.h | 2 | SDL_GetVersion, SDL_GetRevision |
| SDL_error.h | 2 | SDL_GetError, SDL_ClearError |
| SDL_video.h | 27 | SDL_CreateWindow, SDL_DestroyWindow, SDL_GetWindowSize, SDL_SetWindowTitle, SDL_ShowWindow, SDL_HideWindow, SDL_RaiseWindow, SDL_MaximizeWindow, SDL_MinimizeWindow, SDL_RestoreWindow, SDL_SetWindowFullscreen, SDL_SetWindowPosition, SDL_GetWindowPosition, SDL_SetWindowResizable, SDL_SetWindowAlwaysOnTop, SDL_SetWindowBordered, SDL_GetWindowOpacity, SDL_SetWindowOpacity, SDL_GetWindowDisplayScale, SDL_GetNumVideoDrivers, SDL_GetVideoDriver, SDL_GetCurrentVideoDriver, SDL_GetSystemTheme, SDL_GetDisplays, SDL_GetPrimaryDisplay, SDL_GetDisplayName, SDL_GetDisplayBounds, SDL_GetDisplayUsableBounds, SDL_GetDisplayProperties |
| SDL_render.h | 41 | SDL_GetNumRenderDrivers, SDL_GetRenderDriver, SDL_CreateWindowAndRenderer, SDL_CreateRenderer, SDL_DestroyRenderer, SDL_GetRenderWindow, SDL_GetRendererName, SDL_GetRenderer, SDL_RenderClear, SDL_RenderPresent, SDL_SetRenderDrawColor, SDL_SetRenderDrawColorFloat, SDL_GetRenderDrawColor, SDL_SetRenderDrawBlendMode, SDL_GetRenderDrawBlendMode, SDL_RenderFillRect, SDL_RenderRect, SDL_RenderPoint, SDL_RenderLine, SDL_RenderFillRects, SDL_RenderRects, SDL_RenderPoints, SDL_RenderLines, SDL_SetRenderLogicalPresentation, SDL_GetRenderLogicalPresentation, SDL_SetRenderViewport, SDL_GetRenderViewport, SDL_SetRenderVSync, SDL_GetRenderOutputSize, SDL_GetCurrentRenderOutputSize, SDL_SetRenderScale, SDL_GetRenderScale, SDL_SetRenderClipRect, SDL_GetRenderClipRect, SDL_RenderGeometry, SDL_RenderDebugText, SDL_CreateTexture, SDL_CreateTextureFromSurface, SDL_DestroyTexture, SDL_GetTextureSize, SDL_UpdateTexture, SDL_LockTexture, SDL_UnlockTexture, SDL_SetTextureColorMod, SDL_GetTextureColorMod, SDL_SetTextureAlphaMod, SDL_GetTextureAlphaMod, SDL_SetTextureBlendMode, SDL_GetTextureBlendMode, SDL_SetTextureScaleMode, SDL_GetTextureScaleMode, SDL_RenderTexture |
| SDL_events.h | 10 | SDL_PollEvent, SDL_WaitEvent, SDL_WaitEventTimeout, SDL_PumpEvents, SDL_PushEvent, SDL_PeepEvents, SDL_HasEvent, SDL_HasEvents, SDL_FlushEvent, SDL_FlushEvents |
| SDL_timer.h | 6 | SDL_Delay, SDL_DelayNS, SDL_GetTicks, SDL_GetTicksNS, SDL_GetPerformanceCounter, SDL_GetPerformanceFrequency |
| SDL_keyboard.h | 18 | SDL_HasKeyboard, SDL_GetKeyboards, SDL_GetKeyboardNameForID, SDL_GetKeyboardFocus, SDL_GetKeyboardState, SDL_ResetKeyboard, SDL_GetModState, SDL_SetModState, SDL_GetKeyFromScancode, SDL_GetScancodeFromKey, SDL_GetScancodeName, SDL_GetScancodeFromName, SDL_GetKeyName, SDL_GetKeyFromName, SDL_StartTextInput, SDL_TextInputActive, SDL_StopTextInput, SDL_HasScreenKeyboardSupport, SDL_ScreenKeyboardShown |
| SDL_mouse.h | 18 | SDL_HasMouse, SDL_GetMice, SDL_GetMouseNameForID, SDL_GetMouseFocus, SDL_GetMouseState, SDL_GetGlobalMouseState, SDL_GetRelativeMouseState, SDL_WarpMouseInWindow, SDL_WarpMouseGlobal, SDL_CaptureMouse, SDL_CreateSystemCursor, SDL_SetCursor, SDL_GetCursor, SDL_GetDefaultCursor, SDL_DestroyCursor, SDL_ShowCursor, SDL_HideCursor, SDL_CursorVisible |
| SDL_gamepad.h | 15 | SDL_HasGamepad, SDL_GetGamepads, SDL_IsGamepad, SDL_GetGamepadNameForID, SDL_OpenGamepad, SDL_GetGamepadFromID, SDL_GetGamepadFromPlayerIndex, SDL_GetGamepadID, SDL_GetGamepadName, SDL_GetGamepadType, SDL_SetGamepadPlayerIndex, SDL_GetGamepadPlayerIndex, SDL_GamepadConnected, SDL_GetGamepadAxis, SDL_GetGamepadButton, SDL_RumbleGamepad, SDL_SetGamepadLED, SDL_CloseGamepad |
| SDL_joystick.h | 8 | SDL_GetJoysticks, SDL_GetJoystickNameForID, SDL_OpenJoystick, SDL_GetJoystickFromID, SDL_GetJoystickID, SDL_JoystickConnected, SDL_GetJoystickAxis, SDL_GetJoystickButton, SDL_CloseJoystick |
| SDL_touch.h | 4 | SDL_GetTouchDevices, SDL_GetTouchDeviceName, SDL_GetTouchDeviceType, SDL_GetTouchFingers |
| SDL_surface.h | 4 | SDL_CreateSurface, SDL_DestroySurface, SDL_LoadBMP, SDL_SaveBMP |
| SDL_pixels.h | 1 | SDL_GetPixelFormatName |
| SDL_blendmode.h | 1 | SDL_ComposeCustomBlendMode |
| SDL_clipboard.h | 3 | SDL_SetClipboardText, SDL_GetClipboardText, SDL_HasClipboardText |
| SDL_log.h | 6 | SDL_SetLogPriorities, SDL_SetLogPriority, SDL_GetLogPriority, SDL_ResetLogPriorities, SDL_Log, SDL_LogMessage |
| SDL_power.h | 1 | SDL_GetPowerInfo |
| SDL_messagebox.h | 1 | SDL_ShowSimpleMessageBox |
| SDL_audio.h | 13 | SDL_GetNumAudioDrivers, SDL_GetAudioDriver, SDL_GetCurrentAudioDriver, SDL_GetAudioPlaybackDevices, SDL_GetAudioRecordingDevices, SDL_GetAudioDeviceName, SDL_OpenAudioDevice, SDL_PauseAudioDevice, SDL_ResumeAudioDevice, SDL_AudioDevicePaused, SDL_CloseAudioDevice, SDL_LoadWAV, SDL_MixAudio, SDL_GetAudioFormatName |
| SDL_hints.h | 5 | SDL_SetHint, SDL_GetHint, SDL_SetHintWithPriority, SDL_ResetHint, SDL_ResetHints |
| SDL_cpuinfo.h | 11 | SDL_GetNumLogicalCPUCores, SDL_GetSystemRAM, SDL_GetSIMDAlignment, SDL_HasSSE, SDL_HasSSE2, SDL_HasSSE3, SDL_HasSSE41, SDL_HasSSE42, SDL_HasAVX, SDL_HasAVX2, SDL_HasNEON, SDL_GetPlatform |
| SDL_filesystem.h | 2 | SDL_GetBasePath, SDL_GetPrefPath |
| SDL_dialog.h | 3 | SDL_ShowOpenFileDialog, SDL_ShowSaveFileDialog, SDL_ShowOpenFolderDialog |
| SDL_guid.h | 1 | SDL_GUIDToString |

**Constants: 270+** named values across 20+ categories:

| Category | Count | Examples |
|----------|-------|----------|
| SDL_InitFlags | 8 | SDL_INIT_VIDEO (0x20), SDL_INIT_AUDIO (0x10) |
| SDL_WindowFlags | 26 | SDL_WINDOW_RESIZABLE (0x20), SDL_WINDOW_VULKAN (0x10000000) |
| SDL_EventType | 75+ | SDL_EVENT_QUIT (0x100), SDL_EVENT_KEY_DOWN (0x300) |
| SDL_Scancode | 50+ | SDL_SCANCODE_A (4), SDL_SCANCODE_ESCAPE (41) |
| SDL_PixelFormat | 32 | SDL_PIXELFORMAT_RGBA8888 (0x16462004) |
| SDL_BlendMode | 8 | SDL_BLENDMODE_BLEND (0x1) |
| SDL_TextureAccess | 3 | SDL_TEXTUREACCESS_STREAMING (1) |
| SDL_ScaleMode / FlipMode | 7 | SDL_SCALEMODE_LINEAR (1) |
| SDL_GamepadButton | 16 | SDL_GAMEPAD_BUTTON_SOUTH (0) |
| SDL_GamepadAxis | 7 | SDL_GAMEPAD_AXIS_LEFTX (0) |
| SDL_GamepadType | 5 | SDL_GAMEPAD_TYPE_PS5 (6) |
| SDL_SystemCursor | 12 | SDL_SYSTEM_CURSOR_CROSSHAIR (3) |
| SDL_MouseButton | 10 | SDL_BUTTON_LEFT (1), SDL_BUTTON_LMASK (0x1) |
| SDL_MessageBoxFlags | 3 | SDL_MESSAGEBOX_ERROR (0x10) |
| SDL_LogPriority | 7 | SDL_LOG_PRIORITY_INFO (4) |
| SDL_LogCategory | 6 | SDL_LOG_CATEGORY_VIDEO (5) |
| SDL_PowerState | 6 | SDL_POWERSTATE_ON_BATTERY (1) |
| SDL_AudioFormat | 8 | SDL_AUDIO_S16 (0x8010) |
| SDL_TouchDeviceType | 4 | SDL_TOUCH_DEVICE_DIRECT (0) |
| Misc (positions, masks) | 4 | SDL_WINDOWPOS_UNDEFINED (0x1FFF0000) |

**Safe wrapper functions: 43** covering initialization, window, renderer, event, timer, keyboard, mouse, gamepad, CPU info, and error handling.

### sdl3_safe.xi — Module `xiom.sdl3.safe`

6 struct-based resource types (with duplicate inline `extern "C"` block):

| Type | Methods | Contracts |
|------|---------|-----------|
| `SdlContext` | init, quit | requires: flags != 0; ensures: is_init == true |
| `SdlWindow` | create, destroy, show, hide, raise, set_title, set_size, set_fullscreen, get_flags, get_id | requires: title != 0; ensures: handle != 0 |
| `SdlRenderer` | create, create_for_window, destroy, clear, present, set_draw_color, set_draw_color_float, fill_rect, draw_rect, set_blend_mode, set_vsync | requires: window_handle != 0; ensures: handle != 0 |
| `SdlTexture` | create, destroy, set_color_mod, set_alpha_mod, set_blend_mode | requires: renderer != 0, w > 0; ensures: handle != 0 |
| `SdlGamepad` | open, close, get_button, get_axis, is_connected, get_name | ensures: handle != 0 |
| `SdlApp` | create, stop, destroy, clear_screen, present | requires: title != 0, width > 0, height > 0 |

Utility: `SdlError` type with `{ message: Str }`.

## Compiler Gap Status (xiom v0.46.0)

### Resolved in v0.46.0

| Gap | Status | Detail |
|-----|--------|--------|
| C01: Hex literals | **RESOLVED** | `0x`/`0X` prefix works in const declarations. All pixel formats, event types, window flags use hex. |
| String concatenation | **NEW** | `+` operator emits `@xiom_str_concat` (G-22). |
| Function pointers (internal) | **NEW** | FNPTR: functions as values in XIOM contexts (G-26). |
| Implicit-self methods | **NEW** | `init()` inside `fn T.init()` resolves to `self.init()` (G-10). |
| Int → UInt8 coercion | **NEW** | `var x: UInt8 = 255` type-checks (G-04). |

### Still Open (v0.46.0)

| Gap | Severity | Status | Impact |
|-----|----------|--------|--------|
| **C02: Int→Int32 coercion** | Medium | **OPEN** | All Int32 params require explicit `as Int32` casts. `let x: Int32 = 0;` fails. |
| **C03: Cross-module extern resolution** | High | **OPEN** | `use xiom.sdl3` does not resolve functions with extern-backed implementations. Workaround: `src/sdl3_safe.xi` duplicates extern block (~50 lines). Demo uses inline constants. |
| **C04: C struct field access (G-17)** | High | **OPEN** | Cannot read/write C struct members from XIOM (no `offsetof`). SDL_Event, SDL_FRect, SDL_Rect all require C bridge helpers. |
| **C05: C callback lowering (G-16)** | High | **OPEN** | XIOM functions cannot be converted to C function pointers. SDL_AddTimer, SDL_SetEventFilter, SDL_AddEventWatch, SDL_dialog callbacks unusable from pure XIOM. |
| **C06: User-level malloc/free (G-19)** | Medium | **OPEN** | No built-in heap allocation exposed. Dynamic C buffers (SDL_Event, SDL_Surface data) require C bridge or static pre-allocation. |
| **C07: Float32 ABI** | Low | **UNVERIFIED** | Float32 used in FFI (SDL_SetRenderDrawColorFloat, SDL_RenderPoint, SDL_RenderLine) — ABI compatibility with C `float` not verified on all calling conventions. |
| **C08: No `()` unit in Result** | Low | **OPEN** | Void-returning functions use `Result[Int, Error]` with `Ok(0)`. |
| **C10: E001 borrow warnings on out-params** | Low | **NON-FATAL** | `sdl3_safe.xi` has 2 E001 borrow warnings (lines 397-398 in SdlApp.create). Non-fatal, same pattern as VMA bindings. 29 E001 in xiom-vma; 2 here indicates improvement in v0.46 borrow analysis. |

### C03 Detail: Cross-Module Extern Resolution

**Symptom:** `use xiom.sdl3;` followed by `get_num_video_drivers()` produces T001 "undefined variable" and "type mismatch: found ()" (because the function resolves to `()` return type).

**Root Cause:** The ROADMAP 5c.12 claims cross-module extern resolution is "FIXED" but the ecosystem audit and actual compilation show the gap persists for functions that internally call `unsafe { extern_fn() }`. The compiler resolves the function name cross-module but loses the return type information, defaulting to `()`.

**Workarounds:**
1. Duplicate `extern "C"` blocks in every module (used by `sdl3_safe.xi`)
2. Use inline constants in demo modules (used by `demo_sdl3.xi`)
3. Call extern functions only from the module that declares them

**Status After Re-audit:** The 5c.12 fix may have resolved some cases, but `xiom.sdl3` -> `xiom.sdl3.demo` cross-module calls still fail. This gap requires further investigation — it's possible the fix only covers same-package modules, not cross-package `use`.

## Build Pipeline

```
1. Obtain SDL3 runtime
   Download SDL3.dll / libSDL3.so for the target platform

2. C Bridge compilation (required for struct/event allocation)
   Compile event_bridge.c with #include <SDL3/SDL.h>
   → sdl3_bridge.obj
   Bridge must export:
     void* sdl3_alloc_event(void);       // SDL_calloc(1, sizeof(SDL_Event))
     Uint32 sdl3_event_type(void* e);    // ((SDL_Event*)e)->type
     SDL_Scancode sdl3_event_scancode(void* e); // ((SDL_Event*)e)->key.scancode
     void sdl3_free_event(void* e);      // SDL_free(e)
     SDL_FRect* sdl3_alloc_frect(float x, y, w, h); // heap-allocated FRect

3. XIOM Compilation + Link (xiom + clang)
   sdl3.xi + src/sdl3_safe.xi + examples/demo_sdl3.xi + sdl3_bridge.obj + SDL3.lib
   → final executable
```

## Compile Status (2026-07-17)

All files compile with `xiom v0.46.0 "Production"`:

| File | Status | Lines | Contents |
|------|--------|-------|----------|
| `package.xi` | PASSED | 13 | Package manifest |
| `sdl3.xi` | **PASSED** (0 errors) | ~650 | 115 extern C FFI declarations, 270+ pub const, 43 safe wrappers |
| `src/sdl3_safe.xi` | **PASSED** (2 E001 non-fatal) | ~450 | 6 struct types with create/destroy/draw contracts, inline extern block |
| `examples/demo_sdl3.xi` | **PASSED** (0 errors) | ~340 | Full constant verification, API pattern documentation |
| `AUDIT.md` | WRITTEN | This file | Dependencies, gap tracking, build instructions |

**Total: ~1,450 lines of production code across 4 files.**

## Known Limitations

- SDL_Event requires C bridge for allocation (128-byte union, gap C04)
- SDL_Rect/SDL_FRect require C bridge for construction (gap C04)
- No SDL_Audio callbacks (SDL_OpenAudioDeviceStream, gap C05)
- No SDL_Timer callbacks (SDL_AddTimer, gap C05)
- No SDL_Dialog callbacks (file dialog completion, gap C05)
- No SDL_GPU subsystem (massive API surface, GPU-specific)
- No SDL_Haptic subsystem (force feedback)
- No SDL_Camera subsystem (camera capture)
- No SDL_Sensor subsystem (accelerometer, gyro)
- No SDL_Process subsystem (child process management)
- No SDL_Storage / SDL_iostream subsystems
- No SDL_main integration (entry point remapping)
- No SDL_Properties API (SDL_PropertiesID parameter passing)
- No SDL_Metal / SDL_opengl integration
- Gamepad/joystick hotplug requires polling SDL_GetGamepads/Joysticks
- SDL_WarpMouseGlobal requires system permissions on modern OSes
- SDL_GetWindowOpacity / SDL_SetWindowOpacity not supported on all platforms
