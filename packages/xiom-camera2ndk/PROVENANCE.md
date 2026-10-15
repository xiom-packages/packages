# xiom.camera2ndk -- PROVENANCE

## Oracle

- NDK r27b `27.1.12297006` public headers (sysroot `usr/include`):
  `camera/NdkCameraManager.h`, `camera/NdkCameraDevice.h`,
  `camera/NdkCameraCaptureSession.h`, `camera/NdkCaptureRequest.h`,
  `camera/NdkCameraMetadata.h`, `camera/NdkCameraMetadataTags.h`,
  `camera/NdkCameraError.h`, `camera/NdkCameraWindowType.h` (typedef-only,
  no exports).
- Link oracle: API-35 platform stub `libcamera2ndk.so`
  (x86_64) -- 71 exported symbols; the declared 70-symbol set is that
  surface minus the JNI route (`ACameraMetadata_fromCameraMetadata`).
  `ACameraManager_getTagFromName` is `__ANDROID_VNDK__`-only and absent
  from the NDK stub by design.
- Function names and tag/enum values are API facts transcribed from the
  pinned headers; every constant in `camera2ndk.xi` was extracted from
  them on 2026-10-15 (tag ids resolved through the
  `acamera_metadata_section` / `acamera_metadata_section_start` anchors
  of `NdkCameraMetadataTags.h`).
- Runtime behavior verified on-device (API-36 x86_64 emulator) via
  `docs/repro/camera-probe/` (export set + manager lifecycle + camera-id
  verdict).

## Code

- `src/camera2ndk_bridge.c`, `camera2ndk.xi`,
  `tests/test_conformance.xi`, `docs/repro/camera-probe/` and this
  package's metadata are original XIOM code (MIT OR Apache-2.0), written
  for this repository; no upstream implementation code is vendored.
- No NDK headers are copied into the repository; the bridge compiles
  without them (self-declared pinned ABI facts only) and is
  platform-split only at the loader call (dlopen / LoadLibraryA).

## License notes

- The NDK platform headers (`camera/*`) are distributed by Google under
  the Apache License 2.0 (as part of the Android NDK).  This package
  interoperates with the public ABI; declarations here are facts of that
  interface, and the package itself ships no Google code.

## Touch log

- 2026-10-15: created (A8 camera head, first wave; per-touch PROVENANCE
  rule): 70-export set (manager 10 + device 17 + capture-session 15 +
  capture-request 23 + metadata 5), ACAMERA_* constants cluster, verified
  common-tag subset, functional manager head + on-device driver.
