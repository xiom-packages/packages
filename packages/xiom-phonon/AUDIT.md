# AUDIT: xiom.phonon

## Status (2026-10-09)

Dynamic-loader implementation at 0.2.0. The pre-pilot module declared ~125
static `extern "C"` Steam Audio functions plus safe wrappers (a linker- and
SDK-header-dependent design); it is preserved in git history only as
reference.

| Item | State |
|------|-------|
| Compiler | xiom v0.64.1 |
| Pin | soname + upstream tag v4.8.1 + entry-point set + ABI layouts + local header hashes (`SPEC.md` §2) |
| Link model | none at build time; runtime `xiom.ffi.dl`; no headers, nothing vendored |
| FFI confinement | all `unsafe` in the root module `phonon.xi` (G5) |
| Suite | `tests/test_conformance.xi` |
| Runs | absent (default PATH): **PASS 3/3 x2** -- version/SIMD/status constants, deterministic SKIP classification, `probe: SKIP` (code 126) |

## Present-path status (honest record)

The probe (context create -> retain -> balanced release) is implemented and
ABI-verified against the exact v4.8.1 headers, but the **present path was not
exercised locally** because no `phonon.dll` was available on this machine:

- The local SDK tree (`E:\repos\steam-audio`) ships sources + headers only;
  Unity/Wwise integration binaries are gitignored (`.meta` stubs remain).
- No DLL exists in system/game installs (searched System32, Program Files
  incl. Steam common, Epic Games).
- The official integration release zips (`steamaudio_wwise_4.8.1.zip`, 52MB,
  downloaded and inspected) are **source + docs only**; the main SDK zip
  (`steamaudio_4.8.1.zip`) is 181MB and was not fetched in this window.
- A first-party core build (cmake) requires fetching flatbuffers, pffft,
  zlib and mysofa and compiling the full C++ core -- deferred.

Follow-up options for the record: (a) fetch the 181MB SDK zip and use its
`bin\windows-x64\phonon.dll`; (b) build `core` with cmake (VS 18 2026
generator available); (c) run the suite on a host where a game/SDK provides
`phonon.dll` on PATH. The suite needs no changes; the present checks activate
automatically.

## Design notes

- `IPLContextSettings` is built as a 40-byte XIOM-owned buffer: version
  `0x040801` at 0, three NULL callback pointers, `simdLevel` (SSE2 baseline)
  at 32, `flags` at 36. `iplContextRelease` takes `IPLContext*`, so the probe
  writes the handle into two slots and releases both references (create +
  retain).
- Bridge locals use the `f_` prefix (finding B-10); `int_to_str` is local.
- No `port.args.json`: pure-XIOM loader.

## Known limitations

- HRTF/effects/scenes (~125-function surface) are Phase 2; the pilot covers
  identity + context lifecycle only.
- Present-path evidence pending (see above).
