# AUDIT: xiom.miniaudio

## Status (2026-10-11)

Vendored single-header implementation at 0.3.0. The pre-pilot files
(`bridge/xiom_ma_bridge.c/h`, `miniaudio_safe.xi`, `demo_miniaudio.xi`)
referenced a miniaudio header that was **never vendored** and could not
build; they are preserved in git history only as reference.

| Item | State |
|------|-------|
| Compiler | xiom v0.64.3 |
| Pin | tag 0.11.25 header SHA256 + LICENSE SHA256 (`SPEC.md` Â§2) |
| Link model | `--c-source src/miniaudio_all.c`; no system audio library |
| FFI confinement | all `extern "C"` in the root module `miniaudio.xi` (G5) |
| Suite | `tests/test_conformance.xi` |
| Runs | **PASS 6/6 x2** via `scripts/port.ps1` (0.11.25; 9 playback + 4 capture devices; WAV decode 16/1/8000/s16; encoder + file round trip 64 frames sample-exact, temp removed) |

## Design notes

- The compile unit embeds the probe bridge in the same TU as the
  implementation; no separate bridge object and no include paths needed.
- Decode probe bug found and fixed: the EOS read returns `MA_AT_END` on a
  drained decoder -- the probe now accepts `MA_SUCCESS || MA_AT_END` with
  zero frames read.
- Sample data is precomputed (no libm); WAV header is built byte-wise in C.
- XIOM-side slots are 4-byte out-params; `int_to_str` is local to the module
  (no stdlib convert inside the confined block).
- 0.3.0 keeps the scalar/cached-return bridge style: the round-trip probe
  writes its result into C statics and the module reads them through
  getters -- no foreign-pointer reads (the B-20 rule).

## Known limitations

- Scope at 0.3.0: version/device-enumeration/decode + encoder round trip;
  playback engines, mixing and capture are Phase 2.
- The device-count report is environment-dependent; a serviceless host
  reports the context check as SKIP rather than FAIL.
- `vendor/miniaudio.h` is 4.1 MB; the amalgamation-style compile adds a few
  seconds to the suite build (watchdog headroom is fine).
