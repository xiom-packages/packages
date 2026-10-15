# xiom.android -- ROADMAP

Android SDK100 program: `docs/ANDROID-SDK100.md`; wave brief:
`docs/prep/android-wave.md`.

## 0.1.0 -- A1 window-core head

- [x] Runtime probe (libandroid.so + libnativewindow.so) with
  ABSENT/ABI classification + export-set verification (27 exports).
- [x] Functional AHardwareBuffer head (allocate/describe/lock pixel
  roundtrip/release).
- [x] Suite: constants + deterministic SKIP path + live path.

## 0.2.0 -- A5 assets-storage head (current)

- [x] Export set extended 27 -> 53 (asset_manager 17 + storage_manager
  6 + sharedmem 3); ABI-checked on-device (0 missing).
- [x] Functional ASharedMemory head (create/size/setProt/map probe/
  close); on-device roundtrip exact (0x11223344).
- [x] Suite: asset-mode + PROT constants; SHM functional block.

## Next
- A2 lifecycle-glue head (`looper.h`, `native_activity.h`,
  `configuration.h`; 87 protos) + the native_app_glue C unit.
- Live window ops: ANativeWindow lock/geometry flows once a Surface is
  reachable (A11 JNI seam or a spawned app context).
- On-device suite runs: after G1 (compiler android target) the same
  conformance suite runs on the emulator/device; until then the
  on-device driver under `docs/repro/bindings-pilot/android-core-probe/`
  proves the bridge functionally.
- Platform declaration: add `android-arm64`/`android-x86_64` tokens to
  STATUS.json when the packages schema gains them (G3).
