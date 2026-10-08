# xiom.sdl3 -- Roadmap

**Version**: v0.2.0 | **Compiler**: xiom v0.64.0 | **Last updated**: 2026-10-08

## Current state

| Criterion | Status |
|-----------|--------|
| Dynamic loader (no link dependency) | Done -- `sdl3_load`/`sdl3_close` over `xiom.ffi.dl` |
| SKIP-when-absent | Done -- suite reports SKIP (green) without SDL3 |
| ABI-mismatch detection | Done -- `SDL3_LOAD_ABI` failure kind + handle cleanup |
| Smoke suite (init/version/quit, timer/event) | Done -- 10 checks present, 3 checks absent |
| G2 pin (soname + header manifest) | Done -- `SPEC.md` §2 |
| Full constant tables | Phase 2 -- pre-pilot tables in git history (pre-0.2.0) |
| Resource layer (window/renderer/texture/gamepad) | Phase 2 |

## Phase 2 (next touches)

1. Rebuild the resource layer over the loader: `Sdl3Window`, `Sdl3Renderer`,
   `Sdl3Texture`, `Sdl3Gamepad` typed wrappers resolving symbols lazily from
   the already-loaded library; headless CI exercises only the loader-safe
   subset, GUI/device paths are capability-gated.
2. Restore the full SDL3 3.4.8 constant tables (window flags, pixel formats,
   events) from git history and re-attach the constant conformance checks.
3. POSIX loader fallback (`libSDL3.so.0`) once a Linux CI target exists;
   keep soname selection data-driven.
4. Event decoding helpers (event type + minimal payload views) on top of
   `sdl3_poll_event` with an owned event buffer.
5. Re-test the enum-payload and resolver findings at the next compiler pin
   (`docs/BINDINGS-COMPILER-FINDINGS.md`) and simplify the loader if any
   workaround can be dropped.
