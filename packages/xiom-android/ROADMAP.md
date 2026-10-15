# xiom.android -- ROADMAP

Android SDK100 program: `docs/ANDROID-SDK100.md`; wave brief:
`docs/prep/android-wave.md`.

## 0.1.0 -- A1 window-core head

- [x] Runtime probe (libandroid.so + libnativewindow.so) with
  ABSENT/ABI classification + export-set verification (27 exports).
- [x] Functional AHardwareBuffer head (allocate/describe/lock pixel
  roundtrip/release).
- [x] Suite: constants + deterministic SKIP path + live path.

## 0.2.0 -- A5 assets-storage head

- [x] Export set extended 27 -> 53 (asset_manager 17 + storage_manager
  6 + sharedmem 3); ABI-checked on-device (0 missing).
- [x] Functional ASharedMemory head (create/size/setProt/map probe/
  close); on-device roundtrip exact (0x11223344).
- [x] Suite: asset-mode + PROT constants; SHM functional block.

## 0.3.0 -- A2 lifecycle-glue head (current)

- [x] Export set 53 -> 117 (looper 9 + native_activity 5 +
  configuration 50); `setScreenRound` documented as a platform-unexported
  header prototype (device + stub verified).
- [x] Functional ALooper head (`xiom.android.lifecycle`): prepare /
  forThread / wake / addFd (NULL-callback ident + direct-handoff
  callback) / removeFd / pollOnce / pollAll with C-side out params +
  probe pipe helpers; on-device pipe + callback + pollOnce proof.
- [x] Functional AConfiguration head (`xiom.android.configuration`):
  new/delete/copy/diff/match/isBetterThan + 19 get/set pairs +
  language/country + getScreenRound; on-device roundtrip + diff mask.
- [x] native_app_glue documented (source ships in the NDK; not
  vendored) + import-closure proof (`docs/repro/check-glue-closure.ps1`).
- [x] Suite: A2 constants + unloaded-runtime explicit errors +
  export-count guard + live looper/config blocks.

## Next

- A3 input + A4 sensors (serial to this package): `android/input.h`,
  `keycodes.h`, `android/sensor.h` -- the looper integration point
  (`AInputQueue_attachLooper`) and the glue's input imports land here.
- Live window ops: ANativeWindow lock/geometry flows once a Surface is
  reachable (A11 JNI seam or a spawned app context).
- Live activity ops: ANativeActivity_* wrappers once a real activity
  instance is reachable (A11/G1).
- On-device suite runs: after G1 (compiler android target) the same
  conformance suite runs on the emulator/device; until then the
  on-device driver under `docs/repro/` proves the bridge functionally.
- Platform declaration: `platforms` + `runtime_deps` are declared in
  STATUS.json (android-arm64 / android-x86_64 tokens, G3 filed).
