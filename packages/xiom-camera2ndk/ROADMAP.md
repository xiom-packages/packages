# xiom.camera2ndk -- ROADMAP

Android SDK100 program: `docs/ANDROID-SDK100.md` (slice A8); wave brief:
`docs/prep/android-wave.md`.

## 0.1.0 -- A8 camera head (current)

- [x] Runtime probe (libcamera2ndk.so) with ABSENT/ABI classification +
  export-set verification (70 exports of the five NDK camera headers).
- [x] Functional ACameraManager head: create/delete +
  getCameraIdList with owned id copies (typed ACAMERA_ERROR_* recorded
  honestly as non-fatal).
- [x] Constants cluster: ACAMERA_ERROR_* statuses, metadata entry types,
  request templates, capture-session enums, verified common-tag subset
  (LENS_FACING + ~60 tags + value sets).
- [x] Suite: constants + declared export count + deterministic SKIP path
  + live path (SKIP leg green on Windows).
- [x] On-device driver (`docs/repro/camera-probe/`): export set resolved;
  manager lifecycle; camera-id verdict on the API-36 emulator.

## Next

- Device/session/request heads: openCamera + createCaptureRequest +
  characteristics metadata read (ACameraMetadata_getConstEntry) once a
  device context/ownership story exists for shell-driven probes.
- Async callbacks: device state callbacks, capture callbacks and the
  callback handoff shapes (the glfw/sdl3 direct-handoff family; B-series
  disciplines) -- staged for a dedicated wave; data callbacks not wired
  in 0.1.0 on purpose.
- Full `NdkCameraMetadataTags.h` widening (~500 tags + all value sets).
- A11 seam: `ACameraMetadata_fromCameraMetadata` (JNI route) joins the
  JNI-cluster wave.
- On-device suite runs: after G1 (compiler android target) the same
  conformance suite runs on the emulator/device; until then the driver
  under `docs/repro/camera-probe/` proves the bridge functionally.
- Platform declaration: add `android-arm64`/`android-x86_64` tokens to
  STATUS.json when the packages schema gains them (G3).
