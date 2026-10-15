# xiom.camera2ndk -- SPEC

Android camera2 NDK bindings for XIOM.  The A8 (camera) head of the
Android SDK100 program (`docs/ANDROID-SDK100.md`); this 0.1.0 is the
first wave of the slice.

## Scope (NDK r27b oracle, `sysroot/usr/include/camera/`)

- `NdkCameraManager.h` -- 10 NDK exports (`ACameraManager_*`).
- `NdkCameraDevice.h` -- 17 exports (`ACameraDevice_*`,
  `ACaptureSessionOutput*`) + `ACameraDevice_request_template`
  (TEMPLATE_*) + the error-state callback codes (ERROR_CAMERA_*).
- `NdkCameraCaptureSession.h` -- 15 exports (`ACameraCaptureSession_*`,
  `ACaptureSessionSharedOutput_*`, `ACaptureSessionPhysicalOutput_*`) +
  `CAPTURE_FAILURE_REASON_*` + `CAPTURE_SEQUENCE_ID_NONE`.
- `NdkCaptureRequest.h` -- 23 exports (`ACaptureRequest_*`,
  `ACameraOutputTarget_*`).
- `NdkCameraMetadata.h` -- 5 exports (`ACameraMetadata_*`) +
  `ACAMERA_TYPE_*` + the `ACameraMetadata_const_entry` ABI facts.
- `NdkCameraError.h` -- the full `camera_status_t` family (ACAMERA_OK +
  16 typed `ACAMERA_ERROR_*` values).
- `NdkCameraMetadataTags.h` -- a verified common-tags subset (~60 tags:
  COLOR_CORRECTION / CONTROL / EDGE / FLASH / JPEG / LENS / LENS_INFO /
  NOISE_REDUCTION / REQUEST / SCALER / SENSOR / SENSOR_INFO / STATISTICS /
  TONEMAP / INFO) + the LENS_FACING, CAPTURE_INTENT, AE/AF/AWB-mode,
  FLASH-mode, SUPPORTED_HARDWARE_LEVEL and AVAILABLE_CAPABILITIES value
  sets.  Tag ids are `section << 16 | index` (the runtime tag space);
  every value transcribed from the pinned header (see PROVENANCE.md).
- Struct ABI facts pinned from the headers: `ACameraIdList`
  (`int32 numCameras; const char** cameraIds`),
  `ACameraMetadata_const_entry` (`u32 tag; u8 type; u32 count;
  const void* data` -- 24 bytes on 64-bit), `ACameraMetadata_rational`
  (`i32 numerator; i32 denominator`).

Declared export set: **70 symbols** (the five headers above; see the
bridge's `k_export_set`).  Verified against the NDK API-35 stub
(`libcamera2ndk.so`, 71 exports: the same set + the JNI-route
`ACameraMetadata_fromCameraMetadata`).

## Design

- `src/camera2ndk_bridge.c` is a self-contained runtime loader (no
  link-time dependency, no NDK headers needed to compile): `dlopen` on
  Android/Linux, `LoadLibraryA` on Windows (where the probe classifies
  ABSENT -> SKIP).  Every declared export is resolved and missing names
  are reported (`xc_abi_missing`); a broken partial install maps to
  `CAMERA2_LOAD_ABI` = FAIL, never a silent SKIP.  The functional path
  needs no POSIX-only code (the dlopen/LoadLibraryA split is the only
  platform branch; Windows compiles clean).
- Functional head (this wave): `ACameraManager_create` / `_delete` and
  `ACameraManager_getCameraIdList`.  The manager and the `ACameraIdList`
  stay C-side; each id is copied into a caller-owned byte slot on
  request (the event-copy pattern -- no pointer crosses the boundary).
  Handles cross as `Int`.
- Typed outcomes: a negative `camera_status_t` from `getCameraIdList`
  (e.g. `ACAMERA_ERROR_CAMERA_SERVICE` when the camera service is
  unreachable from a shell process) is returned as a typed status and
  recorded honestly; the suite/driver stay green.  Bridge-internal
  statuses are positive small codes (`CAMERA2_INTERNAL_*`).
- Device/session/request/characteristics ops are export-set +
  ABI-checked only this wave.  Their async callbacks (device state,
  capture callbacks, filter-style handoffs) are staged for a later wave;
  do not wire data callbacks yet.

## Classification

| Probe outcome | Marker | Suite result |
|---|---|---|
| lib absent (Windows, bogus soname) | `CAMERA2_LOAD_ABSENT` | SKIP (green) |
| exports missing / broken install | `CAMERA2_LOAD_ABI` | FAIL |
| full export set + manager lifecycle | Ok | live checks |
| typed `ACAMERA_ERROR_*` from the service | typed status | recorded, non-fatal (green) |

## Documented exclusions (for this head)

- `ACameraMetadata_fromCameraMetadata`: JNI seam, slice A11.
- `ACameraManager_getTagFromName`: `__ANDROID_VNDK__`-only, not part of
  the NDK surface.
- The remaining `NdkCameraMetadataTags.h` tags (~500) and the callback
  wire-up: later widening (ROADMAP.md).
- `NdkCameraWindowType.h` is a typedef-only header (`ACameraWindowType`
  = `ANativeWindow`; VNDK variant = `native_handle_t`): no functions, no
  export-set entry; the NDK variant resolves to the `xiom.android` A1
  surface.

## Build

`scripts/port.ps1 -Package xiom.camera2ndk` (compiles
`src/camera2ndk_bridge.c` via `port.args.json`; suite SKIPs on Windows,
runs live on Android).  On-device evidence driver:
`docs/repro/camera-probe/` (x86_64-linux-android26; push + run on the
API-36 emulator, see its README).
