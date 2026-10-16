# xiom.opensl -- ROADMAP

Android SDK100 program: `docs/ANDROID-SDK100.md`; wave brief:
`docs/prep/android-wave.md`.  This package is the A6 legacy tail
(W2d); the modern AAudio head rides the same slice.

## 0.1.0 -- A6 legacy tail head (current)

- [x] Runtime probe (libOpenSLES.so + libOpenMAXAL.so + libamidi.so)
  with ABSENT/ABI classification + 114-symbol export-table ABI check
  (incl. the 53 `SL_IID_*` + 41 `XA_IID_*` runtime-GUID globals).
- [x] Functional OpenSL ES engine lifecycle (create/realize/getstate/
  destroy, all vtable calls C-side) + interface-table queries.
- [x] AMidi export set (14 fns) + `AMidi_getDeviceInfo` count attempt
  with recorded verdict (-1 absent on the r27b/API-36 oracle).
- [x] Constants: SL_RESULT_*/XA_RESULT_* + key SL_*/XA_*/AMIDI_* +
  SL_ANDROID_* extension families (transcribed, oracle-verified).
- [x] Suite: constants + deterministic SKIP path + live path;
  on-device driver `docs/repro/opensl-probe/`.

## Next
- AAudio head (`aaudio/AAudio.h`, 72 protos -> libaaudio) as the 0.2.0
  wave (A6 modern half), reusing this probe pattern.
- Full OpenSL ES object construction (audio player/recorder + output
  mix) once the interface structs land; buffer-queue callbacks are
  B-22-gated (env-free handlers required, see glfw 0.6.0 lift notes).
- AMidi JNI-typed routes (`AMidiDevice_fromJava`): A11 seam.
- Long-tail constants (container types, full speaker masks, full
  sampling-rate ladder) on demand.
- On-device suite runs: after G1 (compiler android target) the same
  conformance suite runs on the emulator/device; until then the driver
  under `docs/repro/opensl-probe/` proves the bridge functionally.
- Platform declaration: add `android-arm64`/`android-x86_64` tokens to
  STATUS.json when the packages schema gains them (G3).
