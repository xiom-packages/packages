# PROVENANCE: xiom.sdl2

Upstream-first record (docs/UPSTREAM-FIRST.md, owner policy 2026-10-11).

## 1. Upstream

| Field | Value |
|-------|-------|
| Project | SDL2 -- Simple DirectMedia Layer, version 2 |
| Canonical repo | https://github.com/libsdl-org/SDL |
| Pinned tag | `release-2.32.10` |
| Pinned commit | `5d249570393f7a37e037abf22cd6012a4cc56a71` ("Updated to version 2.32.10 for release", 2025-09-01) |
| License | zlib (LICENSE.txt in the clone; permissive -- whitelisted) |
| Local clone | `E:\repos\SDL2` (shallow, `--branch release-2.32.10 --depth 1`; shared clone space, see the CLEANUP ledger row reported to the coordinator) |
| Redistribution | nothing vendored, nothing linked: bindings only, MIT OR Apache-2.0 package code |

## 2. Oracle (what the binding is built against)

- **Headers (the API contract)**: the SDL2 development headers shipped with
  the Vulkan SDK at `C:\VulkanSDK\1.4.350.0\Include\SDL2\SDL*.h` -- 64
  headers (the `SDL_test*` framework excluded: SDL2.dll exports zero
  `SDLTest_*` symbols).  The shipped headers carry
  `SDL_REVISION "SDL-release-2.32.10-0-g5d2495703"`, matching the pinned tag
  byte-for-byte in the parts that matter (all declarations parsed by the
  generator were cross-checked against the clone's `include/` tree).
- **Export table (the runtime contract)**: `C:\VulkanSDK\1.4.350.0\Bin\SDL2.dll`
  (2.32.10).  Every bound function name is present in the live dump; the
  dump is committed as `docs/sdl2-exports.txt`.
- **Pinned hashes** (SPEC.md §2): header set
  `b7fca9f8b5e31f07d0c18d4c50fab318a278c72e506cd41dc18c1e573cd73653`,
  export list `7525a119147720b7d1c2d73607ea3f53fb0f81e5d8ec0423623062677f9bbec6`,
  DLL `dbfdb7a1914939b218daa53440adf44e23a0006e98dd758f37fd2cd5064fe451`.

## 3. Derived vs independent

- **Derived (generated)**: all 69 XIOM modules are emitted by the committed
  generator `tools/gen_sdl2.py` -- declarations, symbol names, parameter and
  return widths, and constant values are parsed from the shipped headers,
  never hand-written and never from model memory.  The export list is
  parsed from the DLL's PE export table.
- **Studied upstream sources (behavior, no code copied)**:
  - `src/SDL.c` -- `SDL_InitSubSystem` semantics (the `SDL_MainIsReady`
    guard is compiled OUT of this DLL: it is built without
    `SDL_MAIN_NEEDED`, so `SDL_SetMainReady` is a no-op here and the
    deterministic error probe uses a bad subsystem instead);
  - `src/audio/SDL_audio.c` -- the `"Audio target '%s' not available"`
    error text asserted by the suite's error-path probe;
  - `include/**` -- signing off the type mapping (see SPEC.md §4).
- **Independently implemented**: the loader idiom (symbol structs +
  `dl.dl_sym` + fn-pointer casts), the wrapper type mapping, the suite's
  probe chain, and all documentation.  No upstream source lines are copied;
  the package contains no C code.
- **Test vectors/golden data**: none imported from upstream.  Runtime
  parity probes assert the pinned version/revision strings
  (`SDL_GetVersion` -> 2.32.10, revision `"SDL-release-2.32.10-0-g5d2495703"`)
  and USE the real DLL for the window/display chain.

## 4. Re-carve procedure (when upstream moves)

1. Clone/fetch the new tag in `E:\repos\SDL2` (`git fetch --depth 1 origin tag <tag>`).
2. Update `PIN`/`PIN_COMMIT` in `tools/gen_sdl2.py`; regenerate
   (`python tools/gen_sdl2.py`) and confirm the declared/exported/bound
   counts and the declared-not-exported set in `docs/gen_manifest.json`.
3. Refresh the SDK-shipped headers on the machine if the pin and the SDK
   ship diverge; recompute the three hashes; update SPEC.md §2 + COVERAGE.md
   in the same commit.
4. Re-run the suite x2 (present + absent) and record via `scripts/status.ps1`.
