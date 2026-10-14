# AUDIT: xiom.phonon

## Status (2026-10-13)

0.3.0 full audio-processing surface at compiler v0.64.4. The design is the
0.2.0 dynamic loader carried to the complete runtime DSP surface, with every
name/layout generated from the pinned public `phonon.h`.

| Item | State |
|------|-------|
| Compiler | xiom v0.64.4 |
| Pin | soname + upstream tag v4.8.1 (clone HEAD `480dd64`, header-identical) + 216-name export manifest + generated ABI layouts + header hashes (`SPEC.md` §2) |
| Link model | none at build time; runtime `xiom.ffi.dl`; no headers, nothing vendored |
| FFI confinement | all `unsafe` in the root module `phonon.xi` (G5) |
| Launcher | `phonon_load()` / `phonon_load_named(soname)` -> 216-entry resolved table |
| Suite | `tests/test_conformance.xi` |
| Runs | absent (default PATH): **PASS 6/6 x2**; present (official 4.8.1 DLL on PATH): **PASS 38/38 x2** |

## Recorded runs (2026-10-13, xiom v0.64.4, toolchain `%LOCALAPPDATA%\xiom.new\bin\xiom.exe`)

```
run:      .\scripts\port.ps1 -Package xiom.phonon -TimeoutSec 240
absent:   PASS 6/6  x2     present-path: SKIP -- Steam Audio not present (dynamic library error (code 126))
present:  PASS 38/38 x2    (PATH prepended with the directory containing phonon.dll)
```

Present-path runtime: official Steam Audio 4.8.1 release DLL
(`lib/windows-x64/phonon.dll`, 52,950,168 bytes) extracted from
`steamaudio_4.8.1.zip`; the local recording set PATH to that directory.
The 0.2.0 present-path proof (4/4, native lane, 2026-10-09) is preserved in
git history.

## What the present path asserts

| Check | Evidence |
|-------|----------|
| Complete surface resolvable | `resolved_fn_count == 216`; `--verify-dll` compares the DLL's PE export table to the header manifest (216/216 present, 146 non-public extras ignored) |
| Context lifecycle | create -> retain (same handle) -> balanced releases |
| HRTF | built-in default create/retain/release; SOFA file create from the upstream CIPIC fixture (`E:\repos\steam-audio\core\data\hrtf\cipic_124.sofa`, local-only, never vendored/shipped) |
| Binaural DSP | impulse -> stereo energy `2.90202510392322` (C ground truth `2.9020251`), left/right energies differ, tail size 768, `get_tail` |
| Ambisonics | encode order 1 -> 4ch `0.0795812234760862`; decode binaural -> 2ch `0.173141100497635` |
| Panning | stereo `1.00161929197569` |
| Direct | in-place distance attenuation 0.5 -> `0.25` |
| Path | SH coeffs `{1, 0.5, 0.25, 0.125}` spatialized -> `9.88665086850774`; non-spatialized 4ch -> `1.328125` |

The four DSP ground-truth values come from `tools/path_check.c`, a C harness
compiled against the same public header and linked to the same DLL; the XIOM
suite asserts relative equality within 1e-3. The harness is the oracle, the
suite is the check -- both recorded here so a future regression is visible
from either side.

## Design notes

- The loader resolves all 216 public names (header order) once per
  `phonon_load_named`; wrappers read `lib.fns[exports.PHONON_IDX_*]`, so a
  partial build fails closed at load (`PHONON_LOAD_ABI`, counted + first
  missing name) and per-call guards catch a hand-tampered table.
- Owned planar buffers: `PhononAudioBuffer` holds the 16-byte
  `IPLAudioBuffer` struct, the channel-pointer array and channel-major
  `Vec[Float32]` storage in XIOM memory; the channel addresses are written
  byte-wise (Int math only). The DLL reads/writes only XIOM-owned memory;
  the package never reads through a foreign pointer.
- The path effect's `shCoeffs` pointer is the address of an XIOM-owned
  `Vec[Float32]` written byte-wise into the params slot -- the same
  technique as the SOFA file name.
- `IPLAudioBuffer.data` is a `float**` (pointer to the channel-pointer
  array), not the channel data pointer; early probing bound the pointer
  array itself as SH coefficients and produced pointer-like garbage
  (diagnosed by comparing to `tools/path_check.c`). The owned-buffer layer
  builds the two-level structure explicitly.
- Compiler findings encountered and shipped around: B-12 (fp returns
  deferred), B-17/B-20/B-23/B-24/B-25/B-26 (lane discipline), B-27 (`ptr as
  Int` cast isolated per unsafe block), B-28 (one canonical constant home
  per name across package modules). Repros under `docs/repro/bindings-pilot/`.
- `int_to_str` remains local (stdlib `convert` must not be called inside
  confined blocks); bridge locals use the `f_` prefix (B-10).
- No `port.args.json`: pure-XIOM loader.

## Suite counts explained

- absent: manifest (216/87/14), generated ABI values + layouts, f32 encoder
  table, owned-buffer round-trip, deterministic SKIP classification,
  present-path SKIP => 6 `[PASS]`.
- present: + capabilities (2), export index, context (3), HRTF (6 incl.
  SOFA), binaural (6), ambisonics encode (3) + decode (2), panning (2),
  direct (2), path spatialized (2) + non-spatialized (2), HRTF release,
  context release => 38 `[PASS]`.

## Known limitations

- The typed wrappers cover the 87-function audio-processing surface; the 129
  simulation-domain functions and the four fp/sret helpers are resolvable
  but untyped (`SPEC.md` §5).
- Custom speaker layouts (caller speaker arrays) are not exposed.
- The SOFA check is local-fixture-gated: it prints SKIP (under PASS) when
  the upstream clone fixture is absent.
