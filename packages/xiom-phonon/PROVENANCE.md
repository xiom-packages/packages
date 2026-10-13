# PROVENANCE: xiom.phonon

## Upstream

| Field | Value |
|-------|-------|
| Project | Steam Audio (Valve) -- https://github.com/ValveSoftware/steam-audio |
| License | Apache-2.0 (see `core/THIRDPARTY.md` upstream for bundled third-party notices: MySOFA, CIPIC/SADIE HRTF datasets, etc.) |
| Pinned version | **v4.8.1** (tag) |
| Clone | `E:\repos\steam-audio`, HEAD `480dd64` (v4.8.1-10-g480dd64) |
| Pin rationale | `phonon.h` / `phonon_version.h` / `phonon_interfaces.h` are byte-identical between v4.8.1 and the clone HEAD (verified with sha256), so the ABI pin effective for this package is v4.8.1. HEAD additionally contains the ambisonic-conversion fix (#544) which does not change the public surface. |
| Vendored code | **none** -- dynamic loader (runtime `phonon.dll`); generated constants from the public header only |
| Redistribution | none; the package ships neither the DLL nor header text beyond generated numeric constants/names |

## Oracle source

The single oracle is the pinned public header `core/src/core/phonon.h`
(identical to the Unity package copy), sha256
`CFAB67684FE1ED75A16BB9BCCB81C31276B6FB3BAD904073407DB900045229E7`:

- all `IPLAPI` function declarations (216) -> `xiom.phonon.exports`
- all enums + the fixed size macros -> `xiom.phonon.abi`
- struct sizes/field offsets for every struct the declared surface touches ->
  `xiom.phonon.abi` (Win64 C ABI rules)
- `phonon_version.h` supplies the version split (4.8.1 -> `0x040801`).

`tools/gen_phonon.py` fails closed if the header hash differs from the pin
(regeneration demands a deliberate re-pin commit).

## Files studied

| File | Use |
|------|-----|
| `core/src/core/phonon.h` | the oracle (generator input) |
| `unity/include/phonon/{phonon,phonon_version,phonon_interfaces}.h` | hash cross-check (identical) |
| `core/src/core/api_context.cpp` | context create/retain/release semantics |
| `core/src/core/hrtf.cpp`, `core/src/core/api_*.cpp` | HRTF settings/type behavior (built-in vs SOFA) |
| `core/src/core/path_effect.cpp` | path-effect apply semantics (SH coeffs count, EQ, spatialize vs ambisonic branches) -- used to design the DSP assertions |
| `core/src/core/audio_buffer.cpp` | `IPLAudioBuffer.data` is `float**` (channel-pointer array) -- the owned-buffer layer builds both levels |
| `core/THIRDPARTY.md` | license/notice awareness (CIPIC/SADIE SOFA data are test fixtures, never shipped) |
| `core/data/hrtf/cipic_124.sofa` | local SOFA fixture for the present-path check (not copied into the repo) |

## Derived vs independent

| Item | Kind |
|------|------|
| Function names, arity, enum values, struct layouts | **derived** (generated from the oracle; `--check` guards drift; `tools/layout_check.c` verifies layouts with clang) |
| DLL export verification | **derived** (PE export table parsed by `--verify-dll`; 216/216) |
| DSP ground-truth energies | **independent oracle** (`tools/path_check.c`: C code compiled against the public header, linked to the same DLL; the XIOM suite asserts those numbers) |
| f32 bit encoder table | **independent** (Python-computed IEEE-754 patterns hardcoded in the suite; encoder implemented from the standard, not from upstream source) |
| Loader/slot/owned-buffer code | **independent** (this lane's dynamic-loader idiom) |

## Test vectors / golden data

| Vector | Source | Shipped? |
|--------|--------|----------|
| Energies (binaural/amb/panning/direct/path) | `tools/path_check.c` run against the official 4.8.1 DLL | yes (constants in the suite) |
| `1e-40 -> 0x000116C2`, `0.1 -> 0x3DCCCCCD`, ... | computed from IEEE-754 (offline), asserted in the suite | yes (numbers only) |
| SOFA load | `cipic_124.sofa` from the local clone | **no** -- local-only, SKIP-gated |
| Official DLL | `steamaudio_4.8.1.zip` extraction (local PATH) | no |

## Re-carve procedure

`xiom.phonon` is a dynamic loader: if a future wave re-carves the package
(e.g. to a bundled/native model), the required inputs are

1. the pinned `phonon.h` (hash above) and the generator (`--check` clean);
2. the official release DLL for the target platform for `--verify-dll`;
3. a rerun of the suite in both configurations, x2, recorded in `AUDIT.md`
   and STATUS;
4. the same discipline set (`docs/BINDINGS-COMPILER-FINDINGS.md`), noting
   B-12/B-27/B-28 specifically.

The pre-pilot static-extern module (~125 functions) is preserved in git
history for reference only; the generated manifest supersedes it.
