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
| Runs | absent (default PATH): **PASS 3/3 x2**; **present 4/4 x2** (native lane, 2026-10-09) |

## Present-path status (honest record)

The probe (context create -> retain -> balanced release) is implemented and
ABI-verified against the exact v4.8.1 headers. The present path was **COMPLETED
by the native lane on 2026-10-09** using follow-up option (a): fetched
`steamaudio_4.8.1.zip` (181,171,027 bytes), extracted `lib/windows-x64/phonon.dll`,
prepended its directory to PATH, and ran the suite twice:

- `[PASS] context: created (version 264193, simd level 0)` -- real Steam Audio
  4.8.1 context via the dynamic loader;
- `[PASS] context: retain/release balanced (handle released twice)`;
- suite **PASS 4/4 x2** with no test changes.

Earlier gap for the record: the local SDK tree ships sources + headers only and
the integration zips are source+docs; the main SDK zip supplied the DLL.

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
