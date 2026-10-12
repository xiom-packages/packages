# xiom.sdl2

SDL2 (Simple DirectMedia Layer 2) bindings for XIOM -- **100% of the
exported public C API surface** of the SDL2 headers shipped with the Vulkan
SDK (SDL 2.32.10): 844 typed function wrappers generated from the headers,
resolved at runtime, plus 1385 generated constants.

No link-time dependency, no import library, no vendored code: `sdl2_load()`
opens `SDL2.dll` via `xiom.ffi.dl` and every call goes through fn-pointer
casts inside the generated modules.  When the DLL is absent the suite
reports SKIP and CI stays green.

> **Status:** `incubating` -- 16/16 x2 on v0.64.4 (844/844 resolved);
> 0.1.0 published in `eco-v0.1.162` (sha256 `a5bdb037...`).

## Quick start

```xiom
module demo

use xiom.io;
use xiom.convert;
use xiom.sdl2;
use xiom.sdl2.init_f1;
use xiom.sdl2.main_f1;
use xiom.sdl2.video_f1;
use xiom.sdl2.video_c;

fn main() -> Int {
  let l = sdl2_load();
  if !l.is_ok {
    io.println("SDL2 unavailable: " + l.error.message);
    return 0;
  }
  let lib: Sdl2Library = l.value;
  sdl2_set_main_ready(&lib.main_f1);
  let rc = sdl2_init(&lib.init_f1, SDL_INIT_VIDEO | SDL_INIT_TIMER);
  if rc != 0 {
    io.println("SDL_Init failed: " + sdl2_get_error(&lib.error_f1));
    return 1;
  }
  let win = sdl2_create_window(&lib.video_f1, "xiom-sdl2",
    100, 100, 640, 480, SDL_WINDOW_SHOWN);
  io.println("window=" + to_string(win));
  sdl2_destroy_window(&lib.video_f1, win);
  sdl2_quit(&lib.init_f1);
  let closed = sdl2_close(&lib);
  return 0;
}
```

Run with the DLL reachable (`C:\VulkanSDK\1.4.350.0\Bin` on PATH, or the
DLL next to the binary).

## API

- `xiom.sdl2` (entry): `sdl2_load() -> Result[Sdl2Library, Sdl2LoadError]`,
  `sdl2_close`, `sdl2_versionnum`, `SDL2_SONAME`.  `Sdl2Library` holds the
  dl handle plus one resolved symbol struct per family chunk
  (`lib.video_f1`, `lib.init_f1`, ...).
- `xiom.sdl2.<family>_f<n>`: `sdl2_<family>_f<n>_load(handle)` resolvers
  and one typed wrapper per exported function, e.g.
  `sdl2_create_window(&lib.video_f1, title, x, y, w, h, flags) -> Int`
  (window handle as `Int`, B-20-safe: the address is never dereferenced).
- `xiom.sdl2.<family>[_c]`: generated constant tables (enums/macros) --
  `SDL_INIT_*`, `SDL_WINDOW_*`, `SDL_WINDOWPOS_*`, `SDL_EVENT*`/`SDL_*EVENT`
  families, `SDL_SCANCODE_*`, `SDLK_*`, `KMOD_*`, `AUDIO_*`, pixel formats,
  hints (`SDL_HINT_*` as `Str`), and more.
- `xiom.sdl2.names`: `sdl2_exported_names()`, `SDL2_EXPORTED_COUNT` (844)
  -- the exported-oracle name table used by the loadability sweep.

Type mapping (uniform, generated): integers -> `Int` (exact C width declared
inside the wrapper), `float`/`double` -> `Float32`/`Float64`, `const char*`
-> `Str`, `char*`/data-struct pointers -> `*UInt8` owned slots (pass a
`Vec[UInt8]` via `as_mut_ptr()`), opaque handles -> `Int`, callbacks ->
typed `fn(...)`.  Variadic functions bind their fixed-arity prefix (no
varargs); `va_list` parameters are opaque `Int` pass-throughs.

## Runtime requirements

- Windows x64, `SDL2.dll` 2.32.x on the loader search path (the pinned
  runtime is the SDL2.dll shipped with Vulkan SDK 1.4.350.0).  Nothing is
  linked at build time.
- Absent DLL -> the suite prints SKIP markers and exits 0; present-but-wrong
  DLL (missing symbols) -> FAIL (`SDL2_LOAD_ABI`), never a silent skip.

## Coverage (details in docs/COVERAGE.md)

| Metric | Count |
|--------|-------|
| Declared in the shipped SDL2 headers | 871 |
| Exported by SDL2.dll | 845 |
| **Bound + runtime-resolved (844/844)** | **844** |
| Declared-but-not-exported (platform-foreign) | 27 |
| Exported-but-not-declared (internal) | 1 |
| Constants emitted | 1385 |

Regenerate everything (headers + exports + constants + manifest):

```powershell
python packages\xiom-sdl2\tools\gen_sdl2.py
```

## Tests

```powershell
$env:PATH = 'C:\VulkanSDK\1.4.350.0\Bin;' + $env:PATH
& scripts\port.ps1 -Package xiom.sdl2 -TimeoutSec 700
```

The suite (`tests/test_conformance.xi`) resolves every exported-oracle name
(`resolved=844/844`), checks constant tables, forces a deterministic error
path (bad audio driver -> non-empty error string, cleared after), then runs
the hidden-window probe chain: `SDL_SetMainReady` -> `SDL_Init(VIDEO|TIMER)`
-> `SDL_WasInit` -> `SDL_GetPlatform` -> `SDL_GetNumVideoDisplays` ->
`SDL_GetDisplayBounds` -> `SDL_CreateWindow(hidden 320x240)` ->
`SDL_GetWindowSize` -> destroy -> `SDL_Quit`.
