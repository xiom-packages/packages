# COVERAGE: xiom.sdl2 -- SDL2 100% exported public C API surface

Measured 2026-10-11 by `tools/gen_sdl2.py` (deterministic; all numbers are
reproducible with one command).  Evidence is machine-readable in
`docs/gen_manifest.json` and `docs/sdl2-exports.txt`.

## 1. Oracle definition

- **Function oracle**: every `SDL_`-prefixed function DECLARED in the SDL2
  headers shipped with the Vulkan SDK at
  `C:\VulkanSDK\1.4.350.0\Include\SDL2\SDL*.h` (64 headers; the
  `SDL_test*` framework is excluded because SDL2.dll exports zero
  `SDLTest_*` symbols -- SDL2_test is a separate static library, proven by
  the export dump below).
- **Runtime oracle**: the export table of `C:\VulkanSDK\1.4.350.0\Bin\SDL2.dll`
  (SDL 2.32.10, `release-2.32.10`, commit `5d2495703`; SHA256
  `dbfdb7a1914939b218daa53440adf44e23a0006e98dd758f37fd2cd5064fe451`).
- **Bound surface (the deliverable)**: declared INTERSECT exported.

Recompute everything:

```powershell
# export table (oracle evidence; llvm-objdump)
& 'C:\Program Files\LLVM\bin\llvm-objdump.exe' -p C:\VulkanSDK\1.4.350.0\Bin\SDL2.dll
# regenerate all modules + the manifest (headers + exports + constants + hashes)
python packages\xiom-sdl2\tools\gen_sdl2.py
```

## 2. Function coverage (oracle vs bound vs resolved)

| Metric | Count |
|--------|-------|
| Declared in the shipped SDL2 headers (SDL_*, minus SDL_test*) | **871** |
| Exported by SDL2.dll (SDL_* symbols) | **845** |
| **Bound (declared INTERSECT exported) -- one typed wrapper each** | **844** |
| Declared-but-not-exported (win-x64 platform-foreign; listed in §3) | 27 |
| Exported-but-not-declared (listed in §4) | 1 |
| **Runtime-resolved by the suite (present DLL)** | **844/844** |

Runtime evidence (SDL2.dll on PATH):

```
resolved=844/844
  [PASS] surface: resolved=844/844 (exported-oracle count 844, missing=0)
```

The suite iterates the generated name table (`xiom.sdl2.names`,
`SDL2_EXPORTED_COUNT = 844`) and resolves EVERY name with `dl.dl_sym` against
the loaded DLL; any miss is printed and fails the run.  With the DLL absent
the same run is green as a classified SKIP state (4 markers: loader/surface/
probe SKIP + constants), never a coverage gap.

## 3. Declared-but-not-exported (27) -- win-x64 platform-foreign

Each of these is declared inside a platform-conditional block for a platform
other than win-x64 and is absent from the SDL2.dll export table (verified by
the generator diff against the live dump; guard per name below).  They are
NOT part of the win-x64 exported surface; if SDL ever exports them from a
Windows DLL they appear here first as a re-pin delta.

| Function | Header | Declaration guard |
|----------|--------|-------------------|
| `SDL_AndroidBackButton` | SDL_system.h | `#ifdef __ANDROID__` |
| `SDL_AndroidGetActivity` | SDL_system.h | `#ifdef __ANDROID__` |
| `SDL_AndroidGetExternalStoragePath` | SDL_system.h | `#ifdef __ANDROID__` |
| `SDL_AndroidGetExternalStorageState` | SDL_system.h | `#ifdef __ANDROID__` |
| `SDL_AndroidGetInternalStoragePath` | SDL_system.h | `#ifdef __ANDROID__` |
| `SDL_AndroidGetJNIEnv` | SDL_system.h | `#ifdef __ANDROID__` |
| `SDL_AndroidRequestPermission` | SDL_system.h | `#ifdef __ANDROID__` |
| `SDL_AndroidSendMessage` | SDL_system.h | `#ifdef __ANDROID__` |
| `SDL_AndroidShowToast` | SDL_system.h | `#ifdef __ANDROID__` |
| `SDL_GetAndroidSDKVersion` | SDL_system.h | `#ifdef __ANDROID__` |
| `SDL_IsAndroidTV` | SDL_system.h | `#ifdef __ANDROID__` |
| `SDL_IsChromebook` | SDL_system.h | `#ifdef __ANDROID__` |
| `SDL_IsDeXMode` | SDL_system.h | `#ifdef __ANDROID__` |
| `SDL_GDKGetDefaultUser` | SDL_system.h | `#if defined(__GDK__)` |
| `SDL_GDKGetTaskQueue` | SDL_system.h | `#if defined(__GDK__)` |
| `SDL_GDKRunApp` | SDL_main.h | `#ifdef __GDK__` |
| `SDL_GDKSuspendComplete` | SDL_main.h | `#ifdef __GDK__` |
| `SDL_UIKitRunApp` | SDL_main.h | `#if defined(__IPHONEOS__)` |
| `SDL_iPhoneSetAnimationCallback` | SDL_system.h | `#ifdef __IPHONEOS__` |
| `SDL_iPhoneSetEventPump` | SDL_system.h | `#ifdef __IPHONEOS__` |
| `SDL_OnApplicationDidChangeStatusBarOrientation` | SDL_system.h | `#ifdef __IPHONEOS__` |
| `SDL_LinuxSetThreadPriority` | SDL_system.h | `#ifdef __LINUX__` |
| `SDL_LinuxSetThreadPriorityAndPolicy` | SDL_system.h | `#ifdef __LINUX__` |
| `SDL_WinRTGetDeviceFamily` | SDL_system.h | `#ifdef __WINRT__` |
| `SDL_WinRTGetFSPathUNICODE` | SDL_system.h | `#ifdef __WINRT__` |
| `SDL_WinRTGetFSPathUTF8` | SDL_system.h | `#ifdef __WINRT__` |
| `SDL_WinRTRunApp` | SDL_main.h | `#ifdef __WINRT__` |

Proof commands: the generator computes this set from the live export dump
(`functions.declared_not_exported` in `docs/gen_manifest.json`); spot-check
any name with
`Select-String -Path docs\sdl2-exports.txt -Pattern 'SDL_AndroidGetActivity'`
(no match).

## 4. Exported-but-not-declared (1) -- excluded by design

| Symbol | Why excluded |
|--------|--------------|
| `SDL_DYNAPI_entry` | SDL's internal Dynamic API trampoline (`int SDL_DYNAPI_entry(Uint32, void*, int)`): the macro-based dispatch seam for statically linked builds, connected by generated jump tables.  It is not declared in any shipped public header and is not a callable public API; binding it in XIOM (`dl.dl_sym` only) would expose an unusable trampoline.  Documented, intentionally unbound. |

## 5. Constant coverage (enums + object-like macros)

Constant oracle: every enum constant and every evaluable object-like macro in
the 62 SDL-core headers (`SDL_test*` excluded; the GL/EGL passthrough headers
`SDL_opengl*.h`, `SDL_egl.h`, `SDL_opengles*.h` are excluded -- they
re-declare the GL/EGL APIs, which SDL does not own and SDL2.dll does not
export).  Name filter: `SDL_*`/`SDLK_*` everywhere, plus the `AUDIO_*`
family (`SDL_audio.h`) and `KMOD_*` family (`SDL_keycode.h`), which are
public SDL API names without the SDL prefix.

| Metric | Count |
|--------|-------|
| **Emitted `pub const` values** | **1385** (1181 Int, 202 Str, 2 Float64) |
| Skipped by rule | 430 |
| Unevaluable expressions | 1 |

Skipped-by-rule breakdown (all non-constant or out-of-oracle by
construction): 208 function-like macros (they carry parameters; not value
constants), 112 out-of-oracle names (`HAVE_*`, `__PLATFORM__` internals...),
54 preprocessor fragments (`#include ...` header-guard macro bodies),
46 unresolved identifiers (type-alias macros like `SDL_assert_state
SDL_AssertState`, config-dependent aliases), 8 C compiler
builtins/attributes (`__func__`/`__attribute__`), 1 string
concatenation (`SDL_REVISION` with an empty vendor suffix), 1 non-scalar
(`SDL_NULL_WHILE_LOOP_CONDITION (0,0)`).

Unevaluable: 1 -- `SDL_WINAPI_FAMILY_PHONE` (a WinRT config comparison
`(WINAPI_FAMILY == WINAPI_FAMILY_PHONE_APP)` against macros the shipped
headers do not define; not a constant on win-x64).

Macro-expansion machinery (proven by suite probes): char escapes
(`SDLK_ESCAPE = '\x1B'` -> 27), `SDL_SCANCODE_TO_KEYCODE(X)`
(`SDLK_CAPSLOCK = 1073741881`), `SDL_BUTTON(X)` (LMASK..X2MASK = 1..16),
`SDL_DEFINE_PIXELFORMAT(...)` (`SDL_PIXELFORMAT_RGBA8888 = 0x16462004`),
`SDL_DEFINE_PIXELFOURCC(...)`, `SDL_VERSIONNUM(...)`,
`SDL_WINDOWPOS_*_DISPLAY(X)`.

## 6. Suite matrix (evidence)

| Run | Command | Result |
|-----|---------|--------|
| present x2 | `$env:PATH='C:\VulkanSDK\1.4.350.0\Bin;'+$env:PATH; & scripts\port.ps1 -Package xiom.sdl2 -TimeoutSec 700` | 16/16 PASS each; `resolved=844/844` |
| absent x2 | PATH filtered of `VulkanSDK`; same command | 4/4 PASS (SKIP-classified) each |

Suite markers (present DLL):

```
  [PASS] constants: init flags, window/pos flags, events, scancodes, keycodes (macro expansions), pixel format, masks, versionnum
  [PASS] loader: SDL2.dll loaded; all 844 symbol chunks assembled (sdl2_load)
resolved=844/844
  [PASS] surface: resolved=844/844 (exported-oracle count 844, missing=0)
  [PASS] version: SDL 2.32.10 revision="SDL-release-2.32.10-0-g5d2495703"
  [PASS] error: bad subsystem (SDL_AUDIODRIVER=bogus) fails (rc=...) with non-empty error ("Audio target 'xiom-bogus-driver' not available")
  [PASS] error: SDL_ClearError -> empty error string (len=0)
  [PASS] init: SDL_Init(VIDEO|TIMER) -> 0
  [PASS] init: SDL_WasInit(VIDEO) mask=32
  [PASS] platform: SDL_GetPlatform = "Windows"
  [PASS] displays: SDL_GetNumVideoDisplays = 2
  [PASS] display-bounds: display 0 -> 1920x1080 @ 0,0 (rc=0)
  [PASS] window: SDL_CreateWindow(hidden 320x240) -> handle
  [PASS] window-size: SDL_GetWindowSize = 320x240
  [PASS] window: SDL_DestroyWindow completed
  [PASS] quit: SDL_Quit -> SDL_WasInit(VIDEO) = 0
  [PASS] loader: SDL2 handle released
```

## 7. Boundaries and non-goals (explicit)

- **SDL_test* framework**: 13 headers excluded; zero `SDLTest_*` exports in
  SDL2.dll (static test lib only).
- **GL/EGL passthrough headers**: `SDL_opengl.h`, `SDL_opengl_glext.h`,
  `SDL_opengles*.h`, `SDL_egl.h` re-declare the GL/EGL APIs (hundreds of
  `gl*`/`egl*`/`GL_*`/`EGL_*` names).  These are not SDL's API surface and
  are not exported by SDL2.dll; the constant oracle excludes them by rule.
  They contribute zero functions to the function oracle: `SDL_egl.h` in
  this ship declares no `SDL_*` functions at all (EGL loader support only),
  and the OpenGL headers declare only `gl*`/`GL_*` names.
- **`SDL_main` rewrite symbols**: `SDL_main` itself is not a function
  declaration (`#define main SDL_main`); the Windows DLL does not export it.
- **Variadic functions** (`SDL_Log*`, `SDL_SetError`, `SDL_sscanf`,
  `SDL_snprintf`, `SDL_vsnprintf`, `SDL_vsscanf`, `SDL_asprintf`,
  `SDL_vasprintf`, `SDL_LogMessageV`): bound with their fixed-arity prefix;
  no varargs are passed by the wrappers (documented in each wrapper).
- **Callbacks** (`SDL_AudioCallback`, `SDL_EventFilter`,
  `SDL_HintCallback`, `SDL_LogOutputFunction`, `SDL_TimerCallback`,
  `SDL_ThreadFunction`, `SDL_AudioStreamCallback`,
  `SDL_AudioPostmixCallback`): typed `fn(...)` parameters; pointer payloads
  map to `Int`, floats to `Float32`.
