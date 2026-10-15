# xiom.android

Android platform-core bindings for XIOM -- the A1 window-core head of
the Android SDK100 program.

- Runtime probe for `libandroid.so` + `libnativewindow.so` with SKIP
  semantics (absent runtime -> `ANDROID_LOAD_ABSENT`; broken exports ->
  `ANDROID_LOAD_ABI` FAIL).
- Functional `AHardwareBuffer` head: `hwb_is_supported`, `hwb_alloc`,
  describe accessors, `hwb_write_pixel`/`hwb_read_pixel` (safe lock
  roundtrip), `hwb_acquire`/`hwb_release`.
- `ANativeWindow_*` export set bound + ABI-checked (live window ops
  ride the A11 JNI seam).

```xiom
use xiom.android;

let p = android_probe();
if p.is_ok {
  let usage = AHARDWAREBUFFER_USAGE_CPU_READ_OFTEN + AHARDWAREBUFFER_USAGE_CPU_WRITE_OFTEN;
  let a = hwb_alloc(256, 256, AHARDWAREBUFFER_FORMAT_R8G8B8A8_UNORM, usage);
  ...
}
```

Run the conformance suite:

```
scripts/port.ps1 -Package xiom.android
```

Program context: `docs/ANDROID-SDK100.md` (coverage ledger) and
`docs/prep/android-wave.md` (wave brief).
