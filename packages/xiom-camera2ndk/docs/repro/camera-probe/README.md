# xiom.camera2ndk A8 bridge -- on-device probe (wave evidence)

Runs the package bridge (`packages/xiom-camera2ndk/src/camera2ndk_bridge.c`)
against the real platform library on the API-36 x86_64 emulator:
load -> declared 70-symbol export-set check -> `ACameraManager_create` ->
`ACameraManager_getCameraIdList` (ids copied into owned slots) ->
delete list + manager -> unload.  Complements the package suite (which
SKIPs on Windows).

## Run

```
powershell -File run-probe.ps1                 # emulator must be up
powershell -File run-probe.ps1 -Serial <serial>
```

## Evidence (2026-10-15, API-36 x86_64 emulator, emulator-5554)

```
=== xiom.camera2ndk on-device driver (A8 camera head) ===
INFO load rc=0 error=
OK load (export_count=70 missing_exports=0)
OK manager create
INFO ids rc=0
INFO camera_count=2
INFO camera_id[0]=1
INFO camera_id[1]=10
OK manager delete
RESULT: PASS
```

- `missing_exports=0`: all **70 declared exports** (manager 10 + device 17
  + capture-session 15 + capture-request 23 + metadata 5) resolved from
  `libcamera2ndk.so`.
- Manager lifecycle ran clean: create -> getCameraIdList -> owned id
  copies -> delete.  The emulator exposes **2 cameras** (ids `1` and
  `10`); cross-checked against the camera service itself:
  `dumpsys media.camera` -> `Device 0 maps to "1"`, `Device 1 maps to
  "10"` (exact match).
- `getCameraIdList` returned `ACAMERA_OK` from a shell process on this
  image; the typed `ACAMERA_ERROR_*` path (camera service unreachable)
  is recorded honestly as a non-fatal outcome by design (exit 0).
- On Windows the same bridge classifies ABSENT -> the package suite
  SKIPs green (5/5 on v0.64.5).

## Files

- `driver.c` -- bridge driver (x86_64-linux-android26, PIE)
- `run-probe.ps1` -- build + push + run via adb
