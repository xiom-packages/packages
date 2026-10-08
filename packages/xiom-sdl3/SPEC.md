# SPEC: xiom.sdl3 -- SDL3 bindings via dynamic loader

## 1. Identity

| Field | Value |
|-------|-------|
| Package | `xiom.sdl3` |
| Version | 0.3.0 |
| Kind | binding (`keywords: ["binding"]`) |
| Upstream project | SDL3 -- https://github.com/libsdl-org/SDL |
| Upstream version pinned | **3.4.8** (tag `release-3.4.8`) |
| Upstream license | zlib (bindings only; no code vendored) |
| Package license | MIT OR Apache-2.0 |
| Platform | Windows x64 (loader path is OS-agnostic in design; soname here is `SDL3.dll`) |
| Compiler pin | v0.64.1 (repo `COMPILER_VERSION` bump to v0.64.1 pending native repin; 0.3.0 runs recorded on v0.64.1) |

## 2. G2 pin: soname + dev header hash set

**Soname (runtime contract):** `SDL3.dll` (Windows). The loader passes this
exact name to `LoadLibraryA` through `xiom.ffi.dl`; there is no link-time
dependency, no import library, and nothing vendored.

**Header set pinned** (fetched verbatim from
`https://raw.githubusercontent.com/libsdl-org/SDL/release-3.4.8/include/SDL3/<file>`):

| Header | Bytes | SHA256 |
|--------|-------|--------|
| `SDL.h` | 2,985 | `3E706319D35E274FF52BAD9D1376AE33C746CA188A2A12050AD79D7F45D0C9F8` |
| `SDL_version.h` | 5,809 | `9EC5E010A50FC115E48029B5AECC9D81479958EFF08AFEC536E322961B3B16DD` |
| `SDL_init.h` | 20,850 | `54F65B10221DE0E1EE59B99D01661A56472BC9ABB05690C0D5BD787670965A8D` |
| `SDL_timer.h` | 14,683 | `60A809DF30E0C549A91B986F517FF94515AB80A529DB95D97655A2C417F0F927` |
| `SDL_events.h` | 71,602 | `C3D19BB38D0F1B72B10C2490486E3D1926289DBB1E4062ED58A6D101F6D1CD43` |
| `SDL_error.h` | 7,095 | `C3FB65E2899D341F84AB3A0BBE99646D51EFAB252290FFF28CE36FFC7B5F9A34` |
| `SDL_stdinc.h` | 205,856 | `C8975D3B37C6E2E18CEE44F449DEB523A7DEF9A55A80E9DE949C4734A209293D` |
| **manifest (name+hash lines, LF)** | 566 | **`FD61D35102FDAC6FDDB944ED0192DFE4058222FDC531327F74264FF53B0E3023`** |

The manifest hash is the compact pin: SHA256 over the seven
`"<name> <sha256>"` lines joined with LF. Re-verify by re-fetching the tag
and recomputing (see `scripts`-free procedure below).

**Reference runtime sample used for local positive-path proof (NOT the pin):**

| Artifact | Value |
|----------|-------|
| DLL | `C:\VulkanSDK\1.4.350.0\Bin\SDL3.dll` (shipped with the Vulkan SDK) |
| FileVersion | 3.4.8.0 |
| Bytes | 4,165,560 |
| SHA256 | `6E2B4B6A60AFC19C0C03C4518910953EA0DBA7B5201C0B48D2927F2D9BA5C263` |
| Runtime report | `SDL_GetVersion()` = 3004008 (3.4.8), revision non-empty |

### Re-pin procedure

1. Pick the new upstream tag; re-fetch the seven headers from
   `raw.githubusercontent.com/libsdl-org/SDL/<tag>/include/SDL3/`.
2. Recompute per-file SHA256 and the manifest hash; update the table and the
   version row here, plus `README.md`/`AUDIT.md`, in one commit.
3. Re-run the suite with a matching runtime DLL on PATH (`port.ps1 -Package
   xiom.sdl3`) and record the run; the suite asserts runtime major == 3 and
   reports the actual version, so a mismatch is visible but not fatal.
4. If the API subset changes (new symbols in `sdl3_load`), update the G5
   confinement note and the suite's smoke coverage in the same commit.

## 3. Design: dynamic loader path (system-library pattern)

- **No link-time dependency.** The package never declares `extern "C"` SDL
  symbols; `sdl3_load()` resolves `SDL3.dll` at runtime via `xiom.ffi.dl`
  (`xiom_dl_open`/`xiom_dl_sym` runtime shims), and every call is a
  fn-pointer cast executed inside `src/../sdl3.xi` (`module xiom.sdl3`) --
  the ONLY module in the package with `unsafe`.
- **SKIP semantics.** When the DLL cannot be loaded, `sdl3_load` returns
  `Err(kind = SDL3_LOAD_ABSENT)`. The suite prints explicit `SKIP` labels
  under `[PASS]` markers (the packages runner counts markers and fails a run
  with zero markers) and exits 0, so CI without SDL3 stays green.
- **ABI mismatch is a failure.** If the DLL loads but a symbol is missing,
  the loader closes the handle and returns `Err(kind = SDL3_LOAD_ABI)`; the
  suite reports `[FAIL]` -- a present-but-wrong library must not silently
  skip the smoke.
- **Public API (safe):** `sdl3_load`, `sdl3_close`, `sdl3_init`,
  `sdl3_quit`, `sdl3_was_init`, `sdl3_get_version`, `sdl3_get_revision`,
  `sdl3_get_ticks`, `sdl3_get_performance_counter`, `sdl3_delay`,
  `sdl3_pump_events`, `sdl3_poll_event`, `sdl3_get_error`, plus the
  version-arithmetic helpers and the curated constant set.
- **Resource stage (Phase 2, separate loader):** `sdl3_load_resources`,
  `sdl3_resources_close`, `sdl3_create_window`, `sdl3_destroy_window`,
  `sdl3_show_window`, `sdl3_hide_window`, `sdl3_window_size`,
  `sdl3_set_window_title`, `sdl3_create_renderer`, `sdl3_destroy_renderer`,
  `sdl3_set_render_draw_color`, `sdl3_render_clear`, `sdl3_render_present`,
  `sdl3_create_texture`, `sdl3_destroy_texture`, `sdl3_has_gamepad`,
  `sdl3_gamepad_count`, `sdl3_open_gamepad`, `sdl3_close_gamepad`, with
  `Sdl3Resources` / `Sdl3WindowSize`. A missing resource symbol fails only
  this stage (`SDL3_LOAD_ABI`); the smoke stage is unaffected. Window-
  dependent checks SKIP on hosts that cannot create a window.

## 4. Test matrix (recorded 2026-10-08, compiler v0.64.1)

| Configuration | Command | Result |
|---------------|---------|--------|
| SDL3 absent (CI shape) | `port.ps1 -Package xiom.sdl3` with the Vulkan SDK dir removed from PATH | **PASS, 3/3 x2** (`loader: SKIP ... code 126`, `smoke: SKIP ...`) |
| SDL3 3.4.8 present | same command, default PATH | **PASS, 21/21 x2** -- smoke 10 checks + resources: symbol set, hidden 320x200 window (size/title/show/hide), renderer (draw color, clear+present), RGBA8888 texture create/destroy, gamepad enumeration (0 attached -> SKIP open), resource handle release |

No `port.args.json` is needed: the suite compiles no C source and needs no
extra compiler flags (this is the design win of the loader path over a C
bridge). `scripts/port.ps1` runs it unchanged.

## 5. Compiler notes

- The loader module avoids the binding-lane resolver pitfalls documented in
  `docs/BINDINGS-COMPILER-FINDINGS.md`: all exported functions carry the
  `sdl3_` prefix (no generic `up`/`open`-class names), no exported-const
  references inside confined blocks, no cross-module const aliases, no
  child->parent imports (single module), no malloc/free in confined blocks.
- `xiom.ffi.dl`'s stale "Int-to-pointer casts are broken" smoke note does
  not apply: the fn-pointer cast idiom used here is proven by this suite
  (see the stdlib wishlist item W-4 in `docs/BINDINGS-STDLIB-WISHLIST.md`).
- 0.3.0 runs recorded on **v0.64.1** (the resolver picks the installed
  0.64.1 over the v0.64.0 pin); the lane re-tests at each pin -- see the
  v0.64.1 sweep in `docs/BINDINGS-COMPILER-FINDINGS.md` (B-06/B-09 fixed,
  B-01/B-05/B-08 open).

## 6. Scope

0.3.0 covers the pilot smoke plus the resource stage (window/renderer/
texture/gamepad) over the loader. Remaining Phase 2 items: event decoding
with owned event buffers, the full constant tables (git history), POSIX
soname fallback, and opengl-context interop -- see `ROADMAP.md`.
