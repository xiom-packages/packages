# PROVENANCE -- xiom.sdl3 (upstream-first record)

Owner policy: `docs/UPSTREAM-FIRST.md` (clone-at-pin, license whitelist,
PROVENANCE.md per package). This file is the provenance record for the SDK100
100%-surface carve (additive modules `src/sdl3_full_*.xi`).

## 1. Upstream + pin

| Field | Value |
|-------|-------|
| Project | SDL3 -- `https://github.com/libsdl-org/SDL` |
| License | zlib (permissive; derived: declarations/values only, no code copied) |
| Delivered pin | tag `release-3.4.8` (also in `SPEC.md` section 2) |
| Byte source for this carve | SDL3 headers + DLL shipped with the pinned Vulkan SDK `C:\VulkanSDK\1.4.350.0` (headers report `SDL_MAJOR/MINOR/MICRO = 3.4.8`; DLL FileVersion 3.4.8.0) |
| Header set | 80 `SDL*.h` files; per-file SHA256 in `docs/gen_manifest.json` |
| Runtime | `C:\VulkanSDK\1.4.350.0\Bin\SDL3.dll`; SHA256 `6E2B4B6A60AFC19C0C03C4518910953EA0DBA7B5201C0B48D2927F2D9BA5C263` |

Local upstream clone (shared `E:\repos` space):

| Field | Value |
|-------|-------|
| Clone | `E:\repos\SDL3` (shallow, single tag) |
| Verified state (2026-10-11) | tag `release-3.2.10`, commit `877399b2b2cf21e67554ed9046410f268ce1d1b2` |
| Ledger | `E:\repos\CLEANUP.md` row: `| SDL3 | github.com/libsdl-org/SDL (zlib) | 2026-10-11 | bindings (sdl3) | 2026-12-01 | active (sdl3 wave) |` |

**Pin drift (explicit):** the clone predates the delivered pin (3.2.10 <
3.4.8). The clone was used only as the independent ABI-layout cross-check
(the same role `SPEC.md` already records for the event offsets); the carve
itself was taken from the SDK's 3.4.8 headers/DLL, which are the bytes this
package is verified against. Moving the clone to the pin is part of the
re-carve procedure below.

## 2. What was studied; derived vs independent

Derived from the upstream headers (zlib; transcription of declarations and
values only):

- the function inventory: 1271 `extern SDL_DECLSPEC ... SDLCALL SDL_*`
  declarations; the 1269 names also present in the SDL3.dll export table are
  bound (see `docs/COVERAGE-SDK3-100.md`);
- typedef/scalar/enum maps and enum member values; object-like `#define`
  values (numeric, string, float) -- 1445 Int + 565 Str + 6 Float64 constants;
- the DLL export-name list, read directly from the PE export table by
  `tools/gen_sdl3_full.py` (no hand-maintained symbol list).

Independently implemented (XIOM-authored, MIT OR Apache-2.0):

- `tools/gen_sdl3_full.py` (parser, evaluator, emitter);
- every generated module `src/sdl3_full_*.xi` (symbol structs, resolvers,
  typed wrappers, constant tables) and `src/sdl3_full_names.xi` /
  `src/sdl3_full_registry.xi`;
- `tests/test_full_surface.xi`;
- the pre-existing hand-written surface (`sdl3.xi`, `tests/test_conformance.xi`)
  is unchanged by this carve.

Nothing is vendored; SDL3 is never linked at build time (dynamic loader
only). No upstream source code is copied.

## 3. Test vectors / golden data

- No upstream golden vectors were imported. Verification is
  parity-by-construction against the binary interface: the new suite resolves
  every exported symbol at runtime (`resolved=1270/1270`) and runs live
  functional probes (SDL_Init, SDL_GetVersion, SDL_CreateWindow hidden,
  SDL_Vulkan_GetInstanceExtensions, SDL_Quit) against SDL3.dll 3.4.8.0.
- `docs/gen_manifest.json` records: SDK path, DLL SHA256, per-header SHA256,
  oracle counts, module split, and the 56 unresolvable annotation/libc-alias
  macros (documented, not emitted).

## 4. Re-carve procedure

1. Move the pin (here + `SPEC.md` section 2) to the new upstream tag; fetch
   that tag into `E:\repos\SDL3` (drops the drift note).
2. Re-fetch/refresh the SDK copy used as byte source, or point `--sdk` at it.
3. `python tools/gen_sdl3_full.py --sdk C:\VulkanSDK\<ver>` -- regenerates
   modules, name lists, registry and `docs/gen_manifest.json` deterministically.
4. Re-run the evidence: `tests/test_full_surface.xi` ad-hoc x2, then
   `scripts/port.ps1 -Package xiom.sdl3 -TimeoutSec 700` x2; update
   `docs/COVERAGE-SDK3-100.md` counts and the CLEANUP row as needed.
