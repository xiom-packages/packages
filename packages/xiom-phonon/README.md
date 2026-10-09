# xiom.phonon

Steam Audio (Phonon) spatial-audio bindings for XIOM via a **dynamic
loader**: `phonon_load()` resolves `phonon.dll` at runtime and every call
goes through resolved function pointers. No link-time dependency, no headers,
no vendored code -- and the suite reports **SKIP** (green) when the library
is not installed.

> **Status:** `incubating` -- version/constants and SKIP semantics green
> (3/3); present-path context lifecycle recorded with the official 4.8.1
> release DLL (see AUDIT.md).
> **Lane:** bindings (`keywords: ["binding"]`).

## Quick start

```xiom
use xiom.io;
use xiom.convert;
use xiom.phonon;

fn main() {
  let p = phonon_probe_default();
  if !p.is_ok {
    io.println("Steam Audio unavailable: " + p.error.message);  // SKIP in CI
    return;
  }
  let info: PhononInfo = p.value;
  io.println("Steam Audio context 0x" + to_string(info.version) + " created");
}
```

## API

| Area | Functions |
|------|-----------|
| Loader | `phonon_load`, `phonon_load_named(soname)`, `phonon_close`, `PhononLibrary` |
| Probe | `phonon_probe(lib)`, `phonon_probe_default`, `phonon_probe_named(soname)`, `PhononInfo` |
| Kinds | `PHONON_LOAD_ABSENT`, `PHONON_LOAD_ABI`, `PHONON_PROBE_FAILED` |
| Constants | `STEAMAUDIO_VERSION*`, `IPL_SIMDLEVEL_*`, `IPL_STATUS_*`, `IPL_CONTEXTFLAGS_VALIDATION`, `IPL_NUM_BANDS` |

The probe builds the 40-byte `IPLContextSettings` (version `0x040801`, SIMD
baseline) in an XIOM-owned slot and exercises the context retain/release
balance. HRTF/effects/scenes are Phase 2 (`ROADMAP.md`).

## Tests

```
scripts/port.ps1 -Package xiom.phonon
```

- Without `phonon.dll` on PATH: 3 `[PASS]` (constants + explicit SKIP), exit 0.
- With it: context lifecycle checks (see `AUDIT.md` for the recorded run).
