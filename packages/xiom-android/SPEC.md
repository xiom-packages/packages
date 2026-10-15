# xiom.android -- SPEC

Android platform-core bindings for XIOM.  First package of the Android
SDK100 program (`docs/ANDROID-SDK100.md`); this 0.1.0 is the **A1
window-core head**.

## Scope (NDK r27b oracle)

- `android/native_window.h` -- 15 non-inline exports (`ANativeWindow_*`)
  + `ANativeWindow_LegacyFormat` (WINDOW_FORMAT_*), `ANativeWindow_Transform`,
  frame-rate compatibility/change-strategy enums.
- `android/hardware_buffer.h` -- 12 exports (`AHardwareBuffer_*`) +
  the FORMAT_* and USAGE_* families.
- Struct ABI facts pinned from the headers: `AHardwareBuffer_Desc`
  (width, height, layers, format `u32`; usage `u64`; stride, rfu0 `u32`;
  rfu1 `u64`), `ARect` (`i32` x4).

## Design

- `src/android_bridge.c` is a self-contained runtime loader (no
  link-time dependency, no NDK headers needed to compile):
  `dlopen` on Android/Linux, `LoadLibraryA` on Windows (where the probe
  classifies ABSENT -> SKIP).  Every declared export is resolved and
  missing names are reported (`xa_abi_missing`); a broken partial
  install maps to `ANDROID_LOAD_ABI` = FAIL, never a silent SKIP.
- Functional head: `AHardwareBuffer` is exercised for real
  (isSupported -> allocate -> describe -> lock/write -> lock/read ->
  unlock -> release).  The lock window lives entirely inside the
  bridge; pointers never cross the boundary (B-25 discipline).  Handles
  cross as `Int`.
- `ANativeWindow_*` ops need a live `Surface` (JNI / app context) --
  symbol-bound + ABI-checked here; live window ops arrive with the A11
  JNI seam.

## Classification

| Probe outcome | Marker | Suite result |
|---|---|---|
| libs absent (Windows, bogus pair) | `ANDROID_LOAD_ABSENT` | SKIP (green) |
| exports missing / broken install | `ANDROID_LOAD_ABI` | FAIL |
| full export set + working HWB | Ok | live checks |

## Documented exclusions (for this head)

- `native_window_jni.h` / `hardware_buffer_jni.h` (fromSurface /
  toSurface / fromHardwareBuffer): JNI seam, slice A11.
- Inline-only helpers (`ANativeWindow_clearFrameRate`): no export; the
  underlying `setFrameRateWithChangeStrategy` is bound.
- Window ops requiring a live Surface (lock/unlockAndPost/geometry
  setters): bound for ABI; functional runs join at A11/G1.

## Build

`scripts/port.ps1 -Package xiom.android` (compiles
`src/android_bridge.c` via `port.args.json`; suite SKIPs on Windows,
runs live on Android).
