# xiom-sdl3 — Build Dependency Audit

## Required Dependencies

| Dependency | Version | Purpose |
|-----------|---------|---------|
| SDL3 | >= 3.4.8 | Cross-platform graphics/input/audio library |
| Vulkan SDK | >= 1.4.350.0 | Ships SDL3 headers at Include/SDL3/ |
| SDL3.dll / libSDL3.so | >= 3.4.8 | Runtime library (dynamic link) |
| clang/LLVM | >= 14 | C bridge compilation |
| Rust/Cargo | Latest stable | Compiler build (xiomc) |
| xiomc | >= v0.45.3 | XIOM compiler |

## SDL3 Source

SDL3 is a C library distributed as headers + dynamic library:

| File | Location | Size |
|------|----------|------|
| `SDL3/*.h` (86 headers) | `C:\VulkanSDK\1.4.350.0\Include\SDL3\` | ~500 KB total |
| `SDL3.dll` | System or Vulkan SDK bin directory | ~2 MB |

The Vulkan SDK (1.4.350.0) ships SDL 3.4.8 headers bundled in its include directory.
The runtime DLL must be installed separately or placed alongside the executable.

### SDL3 Integration

SDL3 is a traditional shared library:

1. Include SDL3 headers in C bridge compilation
2. Link against `SDL3.dll` / `libSDL3.so` / `libSDL3.dylib`
3. The library exports C functions with `extern SDL_DECLSPEC` (which resolves to `__declspec(dllimport)` on Windows)

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
ecosystem/xiom-sdl3/
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

**54 extern C function declarations** from SDL3 v3.4.8:

| Category | Functions | Key Functions |
|----------|-----------|---------------|
| Initialization | 5 | SDL_Init, SDL_InitSubSystem, SDL_QuitSubSystem, SDL_WasInit, SDL_Quit |
| Window Management | 17 | SDL_CreateWindow, SDL_DestroyWindow, SDL_GetWindowSize, SDL_SetWindowTitle, SDL_ShowWindow, SDL_HideWindow, SDL_RaiseWindow, SDL_SetWindowFullscreen, SDL_SetWindowPosition, SDL_GetWindowPosition, SDL_GetWindowFlags, SDL_GetWindowID, SDL_GetWindowFromID |
| Display Management | 5 | SDL_GetNumVideoDrivers, SDL_GetVideoDriver, SDL_GetCurrentVideoDriver, SDL_GetDisplays, SDL_GetPrimaryDisplay |
| Renderer | 18 | SDL_CreateWindowAndRenderer, SDL_CreateRenderer, SDL_DestroyRenderer, SDL_RenderClear, SDL_RenderPresent, SDL_SetRenderDrawColor, SDL_SetRenderDrawColorFloat, SDL_RenderFillRect, SDL_RenderRect, SDL_RenderPoint, SDL_RenderLine, SDL_SetRenderLogicalPresentation, SDL_SetRenderVSync, SDL_GetRenderOutputSize, SDL_CreateTexture, SDL_DestroyTexture, SDL_RenderTexture |
| Events | 10 | SDL_PollEvent, SDL_WaitEvent, SDL_WaitEventTimeout, SDL_PumpEvents, SDL_PushEvent, SDL_PeepEvents, SDL_HasEvent, SDL_HasEvents, SDL_FlushEvent, SDL_FlushEvents |
| Timer | 6 | SDL_Delay, SDL_DelayNS, SDL_GetTicks, SDL_GetTicksNS, SDL_GetPerformanceCounter, SDL_GetPerformanceFrequency |
| Error | 2 | SDL_GetError, SDL_ClearError |

**Constants: 195** named values across 5 categories:

| Category | Count | Examples |
|----------|-------|----------|
| SDL_InitFlags | 8 | SDL_INIT_VIDEO (32), SDL_INIT_AUDIO (16), SDL_INIT_EVENTS (16384) |
| SDL_WindowFlags | 24 | SDL_WINDOW_RESIZABLE (32), SDL_WINDOW_VULKAN (268435456) |
| SDL_EventType | 77 | SDL_EVENT_QUIT (256), SDL_EVENT_KEY_DOWN (768), SDL_EVENT_MOUSE_MOTION (1024) |
| SDL_Scancode | 71 | SDL_SCANCODE_A (4) through SDL_SCANCODE_RGUI (231) |
| Renderer/Tex | 8 | SDL_TEXTUREACCESS_STATIC, SDL_LOGICAL_PRESENTATION_* |
| Misc | 7 | SDL_EVENT_SIZE (128), SDL_WINDOWPOS_UNDEFINED/CENTERED, position masks |

**Safe wrapper functions: 25** covering initialization, window, renderer, events, timer, and error.

### sdl3_safe.xi — Module `xiom.sdl3.safe`

4 struct-based resource types (with duplicate inline `extern "C"` block — cross-module resolution gap, see T001):

| Type | Methods | Contracts |
|------|---------|-----------|
| `SdlContext` | init, quit | requires: flags != 0; ensures: is_init == true |
| `SdlWindow` | create, destroy, show, hide, raise, set_title, get_flags, get_id, get_size | requires: title != 0, w > 0, h > 0; ensures: handle != 0 |
| `SdlRenderer` | create, create_for_window, destroy, clear, present, set_draw_color, set_draw_color_float, fill_rect, draw_rect | requires: window_handle != 0; ensures: handle != 0 |
| `SdlApp` | create, run | requires: title != 0, width > 0, height > 0 |

**Note:** `SdlApp.run()` is **illustrative only** — see Compiler Gaps §C04 below. It demonstrates the intended usage pattern but will not compile or execute correctly due to the event buffer allocation limitation.

## Compiler Gaps Documented (NOT Worked Around)

Per project policy, these gaps are documented here rather than worked around via unsafe hacks.

### C01: No hex literals
**Severity:** Medium. **Status:** Unresolved.
**Symptom:** Hex literals (`0x00000020`) cause parse errors.
**Impact:** All constants are decimal. Window flags like `SDL_WINDOW_VULKAN = 0x0000000010000000` are computed as decimal (268435456). This is correct but harder to verify against C headers.

### C02: Int→Int32 coercion
**Severity:** Low. **Status:** Unresolved.
**Symptom:** Integer literals default to `Int` and do not auto-coerce to `Int32`.
**Impact:** All extern function calls and const declarations with Int32 params use explicit `as Int32` casts.

### C03: Cross-module extern resolution
**Severity:** Medium. **Status:** Unresolved (T001).
**Symptom:** `extern "C"` functions declared in module A resolve to `()` when called from module B via `use` import.
**Impact:** `src/sdl3_safe.xi` duplicates the `extern "C"` block it needs inline (~45 lines).

### C04: No struct/union type mapping to C
**Severity:** High. **Status:** Unresolved.
**Symptom:** XIOM has no mechanism to define C-compatible struct layouts or take addresses of local variables to pass as C pointers. C struct types (SDL_Event, SDL_FRect, SDL_Rect, SDL_FPoint, etc.) cannot be allocated on the stack with a known address.
**Impact:**
- **SDL_Event** (128 bytes): Cannot create an SDL_Event buffer on the XIOM stack and pass its address to SDL_PollEvent. Applications must either:
  a) Use a C bridge function that allocates and returns an event pointer
  b) Pre-allocate a static buffer through external means
  c) Use a C helper that wraps the poll loop
- **SDL_FRect / SDL_Rect**: Cannot construct these on the stack. Applications need C bridge helpers.
- **SDL_FPoint**: Cannot pass by value or construct in-place.

### C05: No callback function pointer support
**Severity:** High. **Status:** Unresolved.
**Symptom:** XIOM functions cannot be converted to C function pointers.
**Impact:** All SDL3 functions that take callbacks (SDL_AddTimer, SDL_SetEventFilter, SDL_AddEventWatch, etc.) are declared in the FFI but cannot be used from pure XIOM code. A C bridge thunk is required.

### C06: No heap allocation from XIOM
**Severity:** Medium. **Status:** Unresolved.
**Symptom:** XIOM has no `malloc`/`free` exposed.
**Impact:** Dynamically sized C buffers cannot be allocated from XIOM. Workaround: pass Int (null) and let the C library allocate (e.g., SDL_GetDisplays returns an SDL_malloc'd array).

### C07: Float32 interop untested
**Severity:** Low. **Status:** Unknown.
**Symptom:** Float32 type is used in FFI declarations (e.g., `SDL_SetRenderDrawColorFloat`) but its ABI compatibility with C `float` has not been verified on all platforms.
**Impact:** Float-parameter functions (SDL_SetRenderDrawColorFloat, SDL_RenderPoint, SDL_RenderLine) may have incorrect parameter passing on some architectures (e.g., ARM vs x86_64 calling conventions).

### C08: No `()` unit type in Result
**Severity:** Low. **Status:** Unresolved (same as VMA).
**Symptom:** `Result[(), Error]` is not supported.
**Impact:** Void-returning functions that need Result wrappers use `Result[Int, Str]` with `Ok(0)`.

### C09: Uint64 constants are Int (64-bit) but WindowFlags in C is Uint64
**Severity:** Low. **Status:** Resolved naturally.
**Detail:** XIOM `Int` is 64-bit on all platforms, which matches `Uint64`/`uint64_t`. Window flags (SDL_WINDOW_VULKAN etc.) are declared as `pub const ... Int = value` without casts, which is correct. This differs from VMA's pattern where all constants are `Int32` (VMA uses uint32 flags).

## Build Pipeline

```
1. Obtain SDL3 runtime
   Download SDL3.dll / libSDL3.so for the target platform

2. C Bridge compilation (if needed for struct/event helpers)
   Compile bridge.c with #include <SDL3/SDL.h>
   → sdl3_bridge.obj

3. XIOM Compilation + Link (xiomc + clang)
   sdl3.xi + src/sdl3_safe.xi + examples/demo_sdl3.xi + sdl3_bridge.obj + SDL3.lib
   → final executable
```

## Compile Status (2026-07-15)

Compilation not yet performed — binding files created for first compile pass.

| File | Status | Lines | Contents |
|------|--------|-------|----------|
| `package.xi` | PENDING | 13 | Package manifest |
| `sdl3.xi` | PENDING | ~440 | 54 extern C FFI declarations, 195 pub const values, 25 safe wrappers, 1 utility |
| `src/sdl3_safe.xi` | PENDING | ~270 | 4 struct resource types with create/destroy contracts, inline extern block |
| `examples/demo_sdl3.xi` | PENDING | ~140 | API pattern demo (procedural + struct-based) |
| `AUDIT.md` | WRITTEN | This file | Build dependency and compiler gap documentation |

**Total: ~860 lines of production code.**

## Known Limitations

- SDL3 requires a native window system — compile-time demos cannot create real windows
- Build requires SDL3.dll at runtime for any executable
- No SDL_Audio, SDL_GPU, SDL_Haptic, SDL_Gamepad, SDL_Sensor, SDL_Camera, SDL_Joystick bindings
- No SDL3_main integration (entry point remapping)
- No SDL3 properties API (SDL_PropertiesID-based configuration)
- No SDL_Texture pixel manipulation (Lock/Unlock/Update)
- Event reading requires manual byte-offset access or C bridge helpers
