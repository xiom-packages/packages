# SPEC: xiom.phonon -- Steam Audio (Phonon) bindings (dynamic loader)

## 1. Identity

| Field | Value |
|-------|-------|
| Package | `xiom.phonon` |
| Version | 0.2.0 |
| Kind | binding (`keywords: ["binding"]`) |
| Upstream project | Steam Audio (Valve) -- https://github.com/ValveSoftware/steam-audio |
| Upstream version pinned | **v4.8.1** |
| Upstream license | Apache-2.0; nothing vendored -- constants/layouts declared locally |
| Package license | MIT OR Apache-2.0 |
| Platform | Windows x64 (soname `phonon.dll`) |
| Compiler pin | v0.64.1 |

## 2. G2 pin: soname + entry points + ABI layouts

**Soname (runtime contract):** `phonon.dll`. Resolved at runtime via
`xiom.ffi.dl`; no import library, no headers, nothing vendored.

**Resolved entry points** (pilot): `iplContextCreate`, `iplContextRetain`,
`iplContextRelease`.

**ABI pinned** (verified against the local SDK headers at
`E:\repos\steam-audio\unity\include\phonon\`, tag v4.8.1):

| Item | Value |
|------|-------|
| `STEAMAUDIO_VERSION` | `(major << 16) \| (minor << 8) \| patch` = `0x040801` for 4.8.1 |
| `iplContextCreate` | `IPLerror iplContextCreate(IPLContextSettings*, IPLContext*)` |
| `IPLContextSettings` | 40 bytes: `u32 version` at 0, 8-byte pad, 3 optional callback pointers at 8/16/24, `u32 simdLevel` at 32, `u32 flags` at 36 |
| `IPLerror` | `SUCCESS=0`, `FAILURE=1`, `OUTOFMEMORY=2`, `INITIALIZATION=3` |
| `IPLSIMDLevel` | `SSE2=0`, `SSE4=1`, `AVX=2`, `AVX2=3`, `AVX512=4` |
| `IPLContextFlags` | `VALIDATION=1` |

**Local SDK header hashes** (pin provenance; not vendored; from
`E:\repos\steam-audio` at v4.8.1):

| Header | Bytes | SHA256 |
|--------|-------|--------|
| `unity\include\phonon\phonon.h` | 199,903 | `CFAB67684FE1ED75A16BB9BCCB81C31276B6FB3BAD904073407DB900045229E7` |
| `unity\include\phonon\phonon_version.h` | 1,063 | `ED3A14DAA8A32C5884400FF12FE9ACAEE80B324279450F16083519CFC25270B1` |
| `unity\include\phonon\phonon_interfaces.h` | 85,743 | `90C9AE809080B463C57EF64187D732E5944F72ABAB851B7B130C702E1CEA5CEB` |

**Local runtime sample used for positive-path proof (NOT the pin):** none
available on this host -- the local SDK tree is source-only, integration
release zips are source+docs, and the main SDK zip (181MB) was not fetched in
this window.  The present-path options and the current status are recorded in
`AUDIT.md`; the probe activates automatically once `phonon.dll` is on PATH.

### Re-pin procedure

1. Check the local SDK tree / release zip for the new version; re-verify the
   `IPLContextSettings` layout and enum values against `phonon.h` before
   touching the module.
2. Update the version constants, header references and sample rows in one
   commit.
3. Re-run `scripts/port.ps1 -Package xiom.phonon` in both configurations
   (absent -> SKIP; `phonon.dll` on PATH -> probe) and record the matrix.

## 3. Design and safe boundary (G5)

`phonon.xi` is the only module with `unsafe`: a `PhononLibrary` loader struct
plus wrappers (`phonon_load(_named)`, `phonon_close`,
`phonon_probe(_named/_default)`). The probe builds the 40-byte
`IPLContextSettings` in an XIOM-owned slot (version `0x040801`, SIMD
baseline SSE2, no callbacks/flags), creates a context, exercises
`iplContextRetain`, then releases both references via two slots (release
takes `IPLContext*` and nulls the slot).

Classification: `PHONON_LOAD_ABSENT` -> SKIP; `PHONON_LOAD_ABI` -> FAIL;
`PHONON_PROBE_FAILED` -> FAIL. Bridge locals use the `f_` prefix (finding
B-10); `int_to_str` is local.

## 4. Test matrix (recorded 2026-10-09/10, compiler v0.64.1)

| Configuration | Command | Result |
|---------------|---------|--------|
| Steam Audio absent (CI shape; default PATH) | `scripts/port.ps1 -Package xiom.phonon` | **PASS 3/3 x2** -- version/SIMD/status constants, deterministic SKIP classification, `probe: SKIP` (code 126) |
| Steam Audio present | not exercised locally (no DLL; options in `AUDIT.md`); the probe runs automatically when `phonon.dll` is on PATH | pending |
| HRTF/effects/scenes | Phase 2 (~125-function surface) | not exercised |

## 5. Scope

Pilot: SDK identity and context lifecycle. HRTF creation, effects
(binaural/ambisonics/direct), scenes/geometry and serialization are Phase 2
(`ROADMAP.md`). The pre-pilot module (125 static externs + safe wrappers) is
preserved in git history.
