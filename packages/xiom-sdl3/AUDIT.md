# AUDIT: xiom.sdl3

## Status (2026-10-08)

Dynamic-loader implementation at 0.2.0. The pre-pilot static-extern module
(`src/sdl3_safe.xi`) and the extern-backed tail of the root module were
removed: they could not satisfy the SKIP-when-absent gate (link-time symbol
requirements). The full pre-pilot constant tables and resource wrappers
remain in git history and return in Phase 2 over this loader.

| Item | State |
|------|-------|
| Compiler | v0.64.1 (resolver picks installed 0.64.1; repo pin bump pending native repin) |
| Upstream pin | SDL 3.4.8 (tag `release-3.4.8`), soname `SDL3.dll` |
| Link model | none at build time; runtime `LoadLibraryA`/`GetProcAddress` via `xiom.ffi.dl` |
| FFI confinement | all `unsafe` + fn-pointer casts in the root module `xiom.sdl3` only |
| Suite | `tests/test_conformance.xi` |
| Runs | absent: PASS 3/3 x2; present (SDL 3.4.8): PASS 21/21 x2 -- both via `scripts/port.ps1` (v0.64.1) |
| Resources (0.3.0) | window (hidden 320x200, size/title/show/hide), renderer (draw color, clear+present), RGBA8888 texture create/destroy, gamepad enumeration + SKIP when none attached |

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

- Event decoding is not exposed yet (only pump/poll liveness); an owned
  event-buffer API is Phase 2.
- Curated constant subset only (full tables in git history).
- Windows soname hard-coded (`SDL3.dll`); a `libSDL3.so.0` fallback is a
  Phase 2 item when POSIX CI exists.
- Video/audio init is not exercised (device-dependent); the smoke is
  headless by design. Window-dependent checks SKIP on hosts that cannot
  create a window; gamepad open/close runs only when a device is attached.
