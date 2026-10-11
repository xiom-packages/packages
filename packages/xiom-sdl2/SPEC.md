# SPEC: xiom.sdl2 -- SDL2 bindings via generated dynamic loader

## 1. Identity

| Field | Value |
|-------|-------|
| Package | `xiom.sdl2` |
| Version | 0.1.0 |
| Kind | binding (`keywords: ["binding"]`) |
| Upstream project | SDL2 -- https://github.com/libsdl-org/SDL |
| Upstream version pinned | **2.32.10** (tag `release-2.32.10`, commit `5d2495703`) |
| Upstream license | zlib (bindings only; nothing vendored, nothing linked) |
| Package license | MIT OR Apache-2.0 |
| Platform | Windows x64 (loader path is OS-agnostic in design; soname here is `SDL2.dll`) |
| Compiler pin | v0.64.3 |

## 2. G2 pin: soname + header set + export table

**Soname (runtime contract):** `SDL2.dll` (Windows).  The loader passes this
exact name to `LoadLibraryA` through `xiom.ffi.dl`; there is no link-time
dependency, no import library, and nothing vendored.

**Header set pinned** (the SDL2 headers shipped at
`C:\VulkanSDK\1.4.350.0\Include\SDL2\`): 64 `SDL*.h` headers (the
`SDL_test*` framework excluded -- SDL2.dll exports zero `SDLTest_*`
symbols).  The set hash is SHA256 over the sorted
`"<name>\0<bytes>\0"` stream of every oracle header, computed by
`tools/gen_sdl2.py` and recorded in `docs/gen_manifest.json`:

| Artifact | SHA256 |
|----------|--------|
| Header set (64 files) | `b7fca9f8b5e31f07d0c18d4c50fab318a278c72e506cd41dc18c1e573cd73653` |
| Export list (`docs/sdl2-exports.txt`, 845 SDL_* names, LF) | `7525a119147720b7d1c2d73607ea3f53fb0f81e5d8ec0423623062677f9bbec6` |
| Runtime DLL `C:\VulkanSDK\1.4.350.0\Bin\SDL2.dll` (2,951,608 bytes) | `dbfdb7a1914939b218daa53440adf44e23a0006e98dd758f37fd2cd5064fe451` |

**Runtime report** (suite probes): `SDL_GetVersion` -> 2.32.10,
`SDL_GetRevision` -> `"SDL-release-2.32.10-0-g5d2495703"`,
`SDL_GetPlatform` -> `"Windows"`.

### Re-pin procedure

1. Pick the new upstream tag; update `PIN`/`PIN_COMMIT` in
   `tools/gen_sdl2.py`; re-fetch the matching headers into the SDK include
   tree (or point the generator `--headers` at the clone's `include/`).
2. Regenerate (`python tools/gen_sdl2.py`): all module structure, the
   declared/exported/bound counts, the declared-not-exported diff, and the
   three hashes are recomputed from source.  Update SPEC §2, COVERAGE.md,
   README.md in one commit.
3. Re-run the suite x2 with a matching runtime DLL on PATH; record via
   `scripts/status.ps1`.  A present-but-older DLL yields
   `Err(kind = SDL2_LOAD_ABI)` (a visible FAIL, never a silent SKIP).

## 3. Design: generated dynamic loader (system-library pattern)

- **No link-time dependency.** No `extern "C"` SDL symbols anywhere; the
  package is pure XIOM.  `sdl2_load()` opens `SDL2.dll` through
  `xiom.ffi.dl` and resolves every exported-oracle name into per-family
  symbol structs; every call is a fn-pointer cast inside the generated
  family modules (the only modules with `unsafe`; G5 confinement = the
  `unsafe` blocks in `sdl2.xi` + `src/*.xi`, all of the
  `let f = syms.p_x as fn(...); f(...)` shape).
- **Module layout** (69 generated modules, every file < 560 lines):
  - `sdl2.xi` (module `xiom.sdl2`) -- entry: `SDL2_SONAME`,
    `Sdl2LoadError`, `Sdl2Library` (dl handle + one resolved chunk struct
    per family), `sdl2_load()` (resolves all 844 symbols; closes the handle
    on any miss), `sdl2_close()`, `sdl2_versionnum()`;
  - `src/<family>_f<n>.xi` -- family-split chunks: symbol struct +
    `sdl2_<family>_f<n>_load(handle)` resolver + one typed wrapper per
    exported function + the family's constants (first chunk);
  - `src/<family>[_c].xi` -- constant-only modules (keycode, scancode,
    config, endian, revision) and oversized constant tables split out
    (video_c, stdinc_c, ...);
  - `src/names_<n>.xi` + `src/names.xi` -- the 844-name exported-oracle
    table and `SDL2_EXPORTED_COUNT` for the loadability sweep.
- **Type mapping** (generated, uniform; ABI-checked against the headers):
  - returns: C `int`/enum/`Sint32` -> cast `Int32` -> XIOM `Int`;
    `Uint8..Uint32` -> exact width -> `Int`; `Sint64`/`Uint64`/`size_t` ->
    `Int64`/`UInt64` -> `Int` (B-19: exact-width returns matter);
    `float` -> `Float32`; `double` -> `Float64`; `char*`/`const char*` ->
    `Str` (NULL -> `""`, read via `Str::from_c_str`); every other pointer ->
    `Int` (opaque address; never read through);
  - parameters: integer/enum/`SDL_bool`/IDs -> `Int` (cast declared `Int`;
    win-x64 passes all widths <= 64 in the same register correctly);
    `float` -> `Float32`; `double` -> `Float64`; `const char*` -> `Str`
    (`.c_str()`); non-const `char*` and data-struct pointers -> `*UInt8`
    (XIOM-owned `Vec[UInt8]` slot, B-11/B-20); opaque handles
    (`SDL_Window*`, `SDL_Renderer*`, `SDL_Surface*`, `SDL_RWops*`,
    joystick/gamecontroller/haptic/sensor/thread/mutex/cond/sem, globals) ->
    `Int`; `void*` -> `Int`; callback typedefs -> typed `fn(...)`;
    `va_list` -> `Int` (pass-through only).
  - **Variadic functions** (12: `SDL_Log`, `SDL_LogVerbose`, `SDL_LogDebug`,
    `SDL_LogInfo`, `SDL_LogWarn`, `SDL_LogError`, `SDL_LogCritical`,
    `SDL_LogMessage`, `SDL_SetError`, `SDL_sscanf`, `SDL_snprintf`,
    `SDL_asprintf`): bound with the fixed-arity prefix only; the wrappers
    never pass varargs (each carries a generated NOTE).  Four more take a
    raw `va_list` (`SDL_LogMessageV`, `SDL_vsnprintf`, `SDL_vsscanf`,
    `SDL_vasprintf`) and expose it as an opaque `Int` pass-through.
- **SKIP semantics.** DLL absent -> `Err(kind = SDL2_LOAD_ABSENT)`; the
  suite prints explicit `SKIP` labels under `[PASS]` markers and exits 0
  (CI without SDL2 stays green).  DLL present but a symbol missing ->
  `Err(kind = SDL2_LOAD_ABI)` -> `[FAIL]` (no silent skip).
- **Out-param discipline.** C writes into XIOM-owned `Vec[UInt8]` slots
  handed over via `as_mut_ptr()`; results are read back with byte-indexed
  reads (`buf[off] as Int`, shifts) -- no pointer arithmetic, no reads
  through foreign pointers (B-11..B-20).

## 4. Public API (generated, 844 wrappers + 1385 constants)

- `xiom.sdl2`: `sdl2_load`, `sdl2_close`, `sdl2_versionnum`, `Sdl2Library`,
  `SDL2_SONAME`, load-kind constants.
- `xiom.sdl2.<family>[_f<n>|_c]` and `xiom.sdl2.names`: one wrapper +
  constants per exported function; `sdl2_exported_names()`,
  `SDL2_EXPORTED_COUNT`.  Full inventory: `docs/gen_manifest.json`.

## 5. Coverage statement

100% of the declared-and-exported public C API surface: 844/844 functions
bound and runtime-resolved (`resolved=844/844`); 1385 constants emitted;
27 declared-but-not-exported (all win-x64 platform-foreign: Android/iOS/
WinRT/GDK/Linux guards) and 1 exported-but-not-declared (`SDL_DYNAPI_entry`,
internal trampoline) documented with proof in `docs/COVERAGE.md`.

## 6. Regeneration

```powershell
python packages\xiom-sdl2\tools\gen_sdl2.py            # uses the SDK paths by default
python packages\xiom-sdl2\tools\gen_sdl2.py --headers <dir> --dll <dll> --exports-file <txt>
```

The generator is deterministic (stdlib-only), cleans stale generated files
(marker-checked, explicit paths), and rewrites `docs/gen_manifest.json` +
`docs/sdl2-exports.txt`.
