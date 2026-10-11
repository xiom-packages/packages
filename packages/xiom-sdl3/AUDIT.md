# AUDIT: xiom.sdl3

## Status (2026-10-11)

Dynamic-loader implementation at **0.7.0** (filesystem basics added). The
pre-pilot static-extern module (`src/sdl3_safe.xi`) and the extern-backed
tail of the root module were removed: they could not satisfy the
SKIP-when-absent gate (link-time symbol requirements). The full pre-pilot
constant tables and resource wrappers remain in git history and return over
this loader.

| Item | State |
|------|-------|
| Compiler | v0.64.3 |
| Upstream pin | SDL 3.4.8 (tag `release-3.4.8`), soname `SDL3.dll` |
| Link model | none at build time; runtime `LoadLibraryA`/`GetProcAddress` via `xiom.ffi.dl` |
| FFI confinement | all `unsafe` + fn-pointer casts in the root module `xiom.sdl3` only |
| Suite | `tests/test_conformance.xi`, 44 checks (4 run without the DLL) |
| Runs | absent (PATH-filtered): PASS 4/4 x2; present (SDL 3.4.8): PASS 44/44 x2; demo probe `examples/demo_sdl3.xi` exit 0 with the blit section green -- all via `scripts/port.ps1`/direct run (v0.64.3, 2026-10-11) |
| Resources (0.3.0) | window (hidden 320x200, size/title/show/hide), renderer (draw color, clear+present), RGBA8888 texture create/destroy, gamepad enumeration + SKIP when none attached |
| Event decode (0.4.0) | `SDL_Event` over an owned 128-byte buffer: shared header + key/mouse-motion/mouse-button/window accessors + f32 bit decode; offsets pinned to the 3.4.8 headers (== the 3.2.10 clone) |
| Event filter/watch (0.5.0) | fixed dispatchers + 1-arg handler registries; keep/drop proven (reject makes SDL refuse the push); watch non-consuming + removable; B-14/B-15 workarounds documented (`docs/repro/bindings-pilot/cb-abi/probe7_element_units.xi`) |
| Displays/keyboard (0.6.0) | 11 symbols; SDL_Rect via owned slots, display list + SDL_DisplayMode via ptr-reads (read direction); VIDEO-init SKIP path; lock-key-aware mod-state assert |
| Filesystem (0.7.0) | 6 symbols; ownership-correct string handling (BasePath SDL-owned vs PrefPath/CurrentDirectory freed after copy); SDL_PathInfo via a 40-byte owned slot; create/remove round trip fully cleaned up under the per-user pref path (no shared-toolchain paths) |
| Display blit (0.8.0) | 3 resource-loader symbols (SDL_UpdateTexture / SDL_RenderTexture / SDL_SetRenderVSync); our-buffer read direction only (B-11 avoided); engine ask `REL-20261011-1153-engine` met with the host demo probe + the suite blit check |

## G2 pin

- Soname: `SDL3.dll`.
- Header set (7 files from `release-3.4.8`) with per-file SHA256 and a
  manifest SHA256 `FD61D351...E3023`: `SPEC.md` §2.
- Local positive-path sample (not the pin): Vulkan SDK 1.4.350.0
  `Bin\SDL3.dll`, FileVersion 3.4.8.0, SHA256 `6E2B4B6A...C263`; runtime
  reports 3004008.

## Design notes

- Distinguishes absent (SKIP) from present-but-ABI-mismatch (FAIL);
  `sdl3_load` closes the handle on symbol failure (no leak).
- Suite prints explicit `SKIP` labels under `[PASS]` markers so the packages
  runner stays green when SDL3 is absent (`port.ps1` fails runs with zero
  markers).
- No `port.args.json`: no C source is compiled, no extra compiler flags.
- All exported names are `sdl3_`-prefixed and no confined block references
  exported consts (avoids the v0.64.0 resolver-recursion classes in
  `docs/BINDINGS-COMPILER-FINDINGS.md`).

## Known limitations

- Event decoding covers the common members (key/mouse/window/quit); the
  pump path still uses consume semantics (poll(0)) because SDL writing into
  an XIOM-owned buffer reproduces the B-11-family corruption on v0.64.3.
- On hosts with the Vulkan SDK bin on PATH (the dev box), SDL3 is always
  found; the absent shape is exercised by filtering that dir out of PATH.
- Curated constant subset only (full tables in git history).
- Windows soname hard-coded (`SDL3.dll`); a `libSDL3.so.0` fallback is a
  Phase 2 item when POSIX CI exists.
- Video/audio init is not exercised (device-dependent); the smoke is
  headless by design. Window-dependent checks SKIP on hosts that cannot
  create a window; gamepad open/close runs only when a device is attached.
