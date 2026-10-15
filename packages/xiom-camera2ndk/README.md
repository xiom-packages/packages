# xiom.camera2ndk

Android camera2 NDK bindings for XIOM -- the A8 (camera) head of the
Android SDK100 program.

- Runtime probe for `libcamera2ndk.so` with SKIP semantics (absent
  runtime -> `CAMERA2_LOAD_ABSENT`; broken exports -> `CAMERA2_LOAD_ABI`
  FAIL, never a silent SKIP).
- Declared export set: **70 symbols** across `NdkCameraManager.h` (10),
  `NdkCameraDevice.h` (17), `NdkCameraCaptureSession.h` (15),
  `NdkCaptureRequest.h` (23), `NdkCameraMetadata.h` (5) -- all bound +
  ABI-checked at load.
- Functional manager head: `camera_manager_create`, `camera_manager_camera_ids`
  (ACameraManager_getCameraIdList with the ids copied into owned XIOM
  strings; pointers never cross the boundary), `camera_manager_delete`.
  A typed `ACAMERA_ERROR_*` from the camera service is reported as a
  typed status (non-fatal by design).
- Constants cluster: the full `ACAMERA_ERROR_*` family, metadata entry
  types, templates, capture-session enums and a verified common metadata
  tag subset (`ACAMERA_LENS_FACING` + ~60 tags + the key value sets).
- Device/session/request async surfaces are export-set only this wave
  (callbacks staged later).

```xiom
use xiom.camera2ndk;

let p = camera2_probe();
if p.is_ok {
  let m = camera_manager_create();
  if m.is_ok {
    let mgr: CameraManager = m.value;
    let ids = camera_manager_camera_ids(&mgr);
    if ids.is_ok {
      // Vec[Str] of camera ids (empty on devices with no camera)
    }
    camera_manager_delete(mgr);
  }
}
```

Run the conformance suite:

```
scripts/port.ps1 -Package xiom.camera2ndk
```

Program context: `docs/ANDROID-SDK100.md` (coverage ledger) and
`docs/prep/android-wave.md` (wave brief).  On-device evidence:
`docs/repro/camera-probe/`.
