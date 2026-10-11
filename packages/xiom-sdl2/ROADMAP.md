# xiom.sdl2 -- Roadmap

**Version**: v0.1.0 | **Compiler**: xiom v0.64.3 | **Last updated**: 2026-10-11

## Current state

| Criterion | Status |
|-----------|--------|
| Committed generator (`tools/gen_sdl2.py`) parsing the shipped headers + the DLL export table | Done -- 100% generated, deterministic |
| 100% exported-oracle bindings (844 typed wrappers, family-split, <560 lines/module) | Done |
| Loader entry (`sdl2_load`/`sdl2_close`, `Sdl2Library` aggregate) | Done |
| Full constant tables (enums/macros, incl. macro expansions + string hints) | Done -- 1385 published values |
| Runtime resolution sweep (`resolved=844/844`) | Done |
| Functional probe chain (init/version/platform/displays/window/size/destroy/quit) | Done -- 16/16 present, 4/4 absent-SKIP |
| Error path (bad subsystem -> non-empty error; ClearError) | Done |
| SKIP-when-absent / ABI-mismatch detection (never a silent skip) | Done |
| PROVENANCE + G2 pin (header set / export list / DLL hashes) | Done |

## Next (candidates; driven by engine asks)

1. **Typed SDL_Event decoding helpers** (owned 128-byte slot + byte-indexed
   accessors, the sdl3 0.4.0 shape) over SDL2's 56-byte event union --
   offsets parsed from the pinned headers, no foreign-pointer reads.
2. **Surface readback helpers** (`SDL_GetWindowSurface` -> owned RGBA bytes)
   for capture/tests without a compositor.
3. **Renderer convenience layer** (create/clear/present/streaming texture
   upload round trip, sdl3 0.8.0 shape) for headless-captured frames.
4. **Audio streaming wrappers** (`SDL_OpenAudioDevice` with owned
   `SDL_AudioSpec` slots + silence push) mirroring sdl3 0.12.0.
5. **Callback ergonomics**: curated helpers for the 8 callback typedefs
   (typed XIOM fn adapters + userdata pass-through proofs).
6. **Drift guard wiring**: re-hash headers/exports on demand
   (`tools/gen_sdl2.py` already recomputes; add a CI fail-closed comparator
   when the native lane wants one for binding packages).
