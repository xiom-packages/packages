# xiom.android-sys -- ROADMAP

Android SDK100 program: `docs/ANDROID-SDK100.md`; wave brief:
`docs/prep/android-wave.md`.  This package is the A12 system starter
(log + sync); the remaining A12 families land additively.

## 0.1.0 -- log + sync starter head (current)

- [x] Runtime probe (liblog.so + libsync.so) with ABSENT/ABI
  classification + core export-set verification (11 symbols).
- [x] API-30 liblog extension set resolved and reported (10 symbols;
  informational, never a false FAIL on android26).
- [x] Functional liblog head (write/print/buf_write + is_loggable
  verdicts + minimum priority).
- [x] Functional libsync typed error path (errno capture on
  sync_file_info/sync_merge; info accessors; free).
- [x] Suite: constants + deterministic SKIP path + live path.
- [x] On-device evidence (API-36 x86_64 emulator):
  `docs/repro/android-sys-probe/` (export sets resolved, log write rc,
  is_loggable verdicts, sync error path, logcat proof).

## Next

- Real-fence functional path: once a producer exists (camera/media/GPU
  fence on-device), exercise sync_file_info + status/num_fences/name on
  a live sync file (wave note: no fence synthesis this wave).
- `sync_wait` / `sync_file_info_is_signaled`: excluded -- not declared
  by the NDK headers (private libsync surface); revisit only if the
  oracle changes (poll-wait covers the functionality today).
- A12 remainder: `zlib.h` -> libz, `android/binder_*.h` ->
  libbinder_ndk, `NeuralNetworks*.h` -> libneuralnetworks, icu subset
  -> libicu (as follow-up heads/agents).
- On-device suite runs: after G1 (compiler android target) the same
  conformance suite runs on the emulator/device; until then the driver
  under `docs/repro/android-sys-probe/` proves the bridge functionally.
- Platform declaration: `android-arm64`/`android-x86_64` tokens declared
  in STATUS.json this touch (G3 coordination pending in
  `docs/PLATFORM-MATRIX.md`).
