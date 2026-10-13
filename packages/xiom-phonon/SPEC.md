# SPEC: xiom.phonon -- Steam Audio (Phonon) bindings (dynamic loader)

## 1. Identity

| Field | Value |
|-------|-------|
| Package | `xiom.phonon` |
| Version | 0.3.0 |
| Kind | binding (`keywords: ["binding"]`) |
| Upstream project | Steam Audio (Valve) -- https://github.com/ValveSoftware/steam-audio |
| Upstream version pinned | **v4.8.1** (tag), clone HEAD `480dd64` (v4.8.1-10-g480dd64) |
| Upstream license | Apache-2.0; nothing vendored -- layouts/names generated from the header |
| Package license | MIT OR Apache-2.0 |
| Platform | Windows x64 (soname `phonon.dll`) |
| Compiler pin | v0.64.4 |
| Modules | `xiom.phonon` (binding), `xiom.phonon.abi` (generated), `xiom.phonon.exports` (generated) |

## 2. G2 pin: soname + export surface + ABI layouts

**Soname (runtime contract):** `phonon.dll`. Resolved at runtime via
`xiom.ffi.dl`; no import library, no headers, nothing vendored.

**Pinned oracle:** `phonon.h` at v4.8.1,
sha256 `CFAB67684FE1ED75A16BB9BCCB81C31276B6FB3BAD904073407DB900045229E7`
(199,903 bytes). The clone HEAD `480dd64` contains the ambisonic-conversion
fix (#544) but is byte-identical in `phonon.h`/`phonon_version.h`/
`phonon_interfaces.h`, so the pin **stays v4.8.1** for ABI purposes (the
generator fails closed on any header hash drift; re-pin deliberately).

| Header | Bytes | SHA256 |
|--------|-------|--------|
| `core\src\core\phonon.h` (== `unity\include\phonon\phonon.h`) | 199,903 | `CFAB67684FE1ED75A16BB9BCCB81C31276B6FB3BAD904073407DB900045229E7` |
| `unity\include\phonon\phonon_version.h` | 1,063 | `ED3A14DAA8A32C5884400FF12FE9ACAEE80B324279450F16083519CFC25270B1` |
| `unity\include\phonon\phonon_interfaces.h` | 85,743 | `90C9AE809080B463C57EF64187D732E5944F72ABAB851B7B130C702E1CEA5CEB` |

### Export matrix (generated, verified against the official v4.8.1 DLL)

| Metric | Count |
|--------|-------|
| `IPLAPI` public functions declared in phonon.h | **216** |
| Indexed into the runtime name table + resolved at load | **216** |
| Missing from the official `steam-audio_4.8.1` `phonon.dll` | **0** |
| Extra `ipl*` exports in the DLL not in the public header (internal API) | 146 |
| Declared typed-wrapper surface (14 groups) | **87** |
| Out of scope (simulation domain, explicit non-goals) | 129 |

`tools/gen_phonon.py --verify-dll <dll>` re-checks 216/216 against any
runtime; `--check` guards drift of the generated modules; `--coverage`
prints the table in `docs/COVERAGE.md`.

### ABI layouts

Every struct size/field offset used by the wrappers is generated from the
header with Win64 C ABI rules (`enum` 4, pointer 8, `float` 4) and
cross-verified against clang's real layout (`tools/layout_check.c`): sizes
match exactly, e.g. `IPLContextSettings` 40 (simdLevel@32, flags@36),
`IPLAudioBuffer` 16 (data@8), `IPLHRTFSettings` 40 (sofaFileName@8,
sofaData@16, volume@28), `IPLBinauralEffectParams` 40 (hrtf@24),
`IPLDirectEffectParams` 44, `IPLPathEffectParams` 96 (shCoeffs@16,
listener@40, normalizeEQ@88), `IPLAmbisonicsDecodeEffectParams` 72
(orientation@16, binaural@64).

`STEAMAUDIO_VERSION = 0x040801`; status `SUCCESS=0`/`FAILURE=1`/
`OUTOFMEMORY=2`/`INITIALIZATION=3`; `IPLSIMDLevel SSE2=0..AVX512=4`;
`IPL_AUDIOEFFECTSTATE_TAILREMAINING=0`/`TAILCOMPLETE=1`; speaker layouts
MONO=0..CUSTOM=5; `IPL_HRTFTYPE_DEFAULT=0`/`SOFA=1`.

### Re-pin procedure

1. Fetch the new tag/section into the clone; verify the three header hashes;
   update `tools/gen_phonon.py` (pin hash, version block) and regenerate.
2. `--verify-dll` against the new official DLL; run `--check` clean.
3. Re-run `scripts/port.ps1 -Package xiom.phonon` in both configurations
   (absent -> SKIP; DLL on PATH -> full) x2; update `AUDIT.md` + STATUS rows
   in one commit.

## 3. Design and safe boundary (G5)

Single binding module `phonon.xi` holds **all** `unsafe`: the loader, slot
helpers, the f32 bit codec, the owned-buffer layer and every typed wrapper.
The generated modules (`abi`, `exports`) contain data only.

- **Loader**: resolves the complete 216-name table (header order) into
  `Vec[Int]`; `PHONON_LOAD_ABSENT` -> SKIP (dl_open error), `PHONON_LOAD_ABI`
  -> FAIL (any entry point missing, counted + first name reported),
  `PHONON_PROBE_FAILED` -> FAIL. Per-call guards re-check `fns[idx] != 0`.
- **Marshalling**: one owned slot per out-param (B-17); byte-indexed
  little-endian reads/writes (B-11/B-16); the DLL only ever reads/writes
  XIOM-owned memory -- no reads through foreign pointers (B-20/B-24); no
  `null` literals to C (B-23); no `Int as *UInt8` casts (B-25); flat outcome
  structs, never `Result[Option]` (B-26); every `ptr as Int` cast isolated in
  its own `unsafe` block (B-27); `Str` equality via `string.str_compare`.
- **Owned planar buffers**: `PhononAudioBuffer` = 16-byte `IPLAudioBuffer`
  slot + channel-pointer array + channel-major `Vec[Float32]`, all
  XIOM-owned; channel addresses are written byte-wise with Int math (no
  pointer arithmetic).
- **f32 interop**: `phonon_f32_bits` (pure Int math from
  `float_bits`, RNE, subnormals/overflow handled) and
  `phonon_f32_from_bits`; table-tested in the suite.
- **SOFA**: the file path travels as a C string pointer written byte-wise
  into the settings slot; verified against the upstream CIPIC fixture.
- **Deferred (resolved but untyped)**: `iplCalculateRelativeDirection`
  (struct return) and `iplDistanceAttenuationCalculate` /
  `iplAirAbsorptionCalculate` / `iplDirectivityCalculate` (fp returns through
  fn-pointer cast calls miscompiled -- finding B-12). Symbol-resolvable via
  `phonon_fn_of`; recorded in `docs/COVERAGE.md`.

## 4. Test matrix (recorded 2026-10-13, compiler v0.64.4)

| Configuration | Command | Result |
|---------------|---------|--------|
| Steam Audio absent (CI shape; default PATH) | `scripts/port.ps1 -Package xiom.phonon` | **PASS 6/6 x2** -- generated manifest/ABI, f32 table, owned-buffer round-trip, deterministic SKIP (code 126) |
| Steam Audio present (official 4.8.1 DLL on PATH) | `scripts/port.ps1 -Package xiom.phonon` | **PASS 38/38 x2** -- 216/216 symbols; context lifecycle; HRTF built-in + SOFA; binaural / ambisonics encode+decode / panning / direct / path energies equal the C harness (`tools/path_check.c`) to 1e-3 relative |

Evidence detail: `AUDIT.md`.  Ground-truth energies asserted by the suite:
binaural `2.90202510392322`, amb-encode `0.0795812234760862`, amb-decode
`0.173141100497635`, panning `1.00161929197569`, direct `0.25`, path
`9.88665086850774`, path-nospatial `1.328125`.

## 5. Scope: declared surface and explicit non-goals

**Declared (0.3.0)**: context create/retain/release; HRTF create (built-in +
SOFA file)/retain/release; audio buffers (owned planar + DLL-managed
allocate/free/interleave/deinterleave/mix/downmix/convert-ambisonics);
binaural, panning, virtual surround, ambisonics encode/panning/binaural/
rotation/decode, direct (incl. in-place) and path effects with their
create/apply/reset/retain/release/tail entry points; version and capability
probes.

**Explicit non-goals (0.3.0)**: the 129 simulation-domain functions --
scene/static-mesh/instanced-mesh, serialized objects, simulator, sources,
probe array/batch, reflections + baker + mixer, path baker, energy field,
impulse response, reconstructor, device backends (Embree/OpenCL/RadeonRays/
TrueAudioNext), and the four deferred pathing helpers above. All remain
symbol-resolvable via `phonon_fn_of` + `exports.PHONON_IDX_*`; typed
wrappers are future slices (ROADMAP Phase 2/3).

**Not covered by any wrapper**: custom speaker layouts with caller-provided
speaker coordinate arrays (needs an owned pointer array; the generated
layout supports it, the typed API accepts the five built-in layouts).
