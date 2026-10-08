# AUDIT: xiom.raylib

## Status (2026-10-08)

Dynamic-loader implementation at 0.2.0. The pre-pilot static-extern module
(26 `extern "C"` raylib functions, "links against system-installed raylib at
link time") could not satisfy the SKIP-when-absent gate and is preserved in
git history only as reference.

| Item | State |
|------|-------|
| Compiler | xiom v0.64.1 |
| Upstream pin | raylib 5.5 (tag `5.5`), soname `raylib.dll`; 6.0 noted as the next re-pin candidate |
| Link model | none at build time; runtime resolution via `xiom.ffi.dl` |
| FFI confinement | all `unsafe`/fn-pointer casts in `raylib.xi` (single module, G5) |
| Suite | `tests/test_conformance.xi` |
| Runs | absent: PASS 3/3 x2; present (raylib 5.5.0): PASS 12/12 x2 -- both via `scripts/port.ps1` |

## G2 pin

- Soname `raylib.dll`; header `src/raylib.h` tag 5.5 SHA256
  `AFB287EC...C871`; resolved symbol set of 15 functions (size functions
  accept both 5.x and 6.x names). Full table + re-pin procedure: `SPEC.md` §2.
- Local positive-path sample (not the pin): official
  `raylib-5.5_win64_msvc16.zip` SHA256 `8D046084...507C`,
  `lib\raylib.dll` SHA256 `C8D29FBD...76994`, FileVersion 5.5.0.

## Design notes

- Classification: absent (SKIP), no ready window (SKIP; the smoke sets
  `FLAG_WINDOW_HIDDEN` first), export mismatch (FAIL).
- `InitWindow` is void in raylib, so readiness is checked via
  `IsWindowReady()` -- a failed hidden-window creation surfaces as the
  `NO_WINDOW` kind rather than a crash.
- Pure color helpers stay in the package; no malloc/free in confined blocks
  (finding B-05).
- No `port.args.json`: pure-XIOM loader.

## Known limitations

- Smoke scope: textures/models/sounds/fonts/input/camera are Phase 2.
- Windows soname only (`raylib.dll`).
- raylib is a single-threaded, global-state library: one `RaylibLibrary`
  session per process is the supported use; concurrent instances are not
  prevented by the types.
- The headless-present path (window not ready) is code-reviewed but was not
  reproducible on this host (desktop session available).
