# xiom.android

Android platform-core bindings for XIOM -- the A1 (window-core) + A5
(assets-storage) + A2 (lifecycle-glue) + A3 (input) + A4 (sensors)
heads of the Android SDK100 program.

> **Published:** `0.4.0` (2026-10-16; sha256 `2b9cf462...`) via the single-package tag `xiom-android/v0.4.0` -- the Android family first-publish remainder.

- Runtime probe for `libandroid.so` + `libnativewindow.so` with SKIP
  semantics (absent runtime -> `ANDROID_LOAD_ABSENT`; broken exports ->
  `ANDROID_LOAD_ABI` FAIL); 209-symbol declared export set.
- Functional `AHardwareBuffer` head: `hwb_is_supported`, `hwb_alloc`,
  describe accessors, `hwb_write_pixel`/`hwb_read_pixel` (safe lock
  roundtrip), `hwb_acquire`/`hwb_release`.
- Functional `ASharedMemory` head: `shm_create`, size + `shm_set_prot`,
  exact map-probe write/read roundtrip, `shm_close` (on-device
  verified); asset_manager/storage_manager surfaces are export-set
  ABI-checked (live wrappers join at the A11 JNI seam).
- Functional `ALooper` head (`xiom.android.lifecycle`): prepare /
  forThread / wake / addFd (NULL-callback ident variant + direct-handoff
  callback variant) / removeFd / pollOnce / pollAll, with poll out
  params read back through `looper_last_fd/events/data`; probe pipe
  helpers (`looper_pipe_open/write/read/close`).  Handlers are env-free
  top-level fns (direct handoff, post-B-22 ABI).
- Functional `AConfiguration` head (`xiom.android.configuration`):
  new/delete/copy/diff/match/isBetterThan, 19 get/set pairs
  (orientation, density, screen size, ui mode, layout direction, ...),
  language/country, `config_screen_round`; the full
  `ACONFIGURATION_*` constant set.
- `ANativeWindow_*` / `ANativeActivity_*` export sets bound +
  ABI-checked (live window/activity ops ride the A11 JNI seam); the
  NDK `native_app_glue` C unit (source, not vendored) is the reference
  consumer -- `docs/repro/check-glue-closure.ps1` proves its imports
  close over this package + the documented future slices (its six
  `AInputQueue_*`/`AInputEvent_*` imports resolve inside the A3 head
  since 0.4.0).
- Functional `AInputQueue`/`AInputEvent`/`AKeyEvent`/`AMotionEvent`
  head (`xiom.android.input`): attachLooper (callback + ident
  variants) / detachLooper / hasEvents / getEvent / preDispatchEvent /
  finishEvent + every AKeyEvent/AMotionEvent accessor (42) and the
  full 161-value `input.h` + 317-entry `AKEYCODE_*` constant tables;
  float accessors are rebuilt from binary32 bits (B-12-safe).  The
  queue is framework-delivered to an app -- the live path is proven by
  the on-device app probe (`docs/repro/`).
- Functional `ASensorManager`/`ASensorEventQueue`/`ASensor` head
  (`xiom.android.sensors`): getInstance(+ForPackage) / sensor list
  enumeration + description / default sensor (Ex) / create+destroy
  event queue (callback + ident variants) / register/enable/disable/
  setEventRate / hasEvents / getEvents into owned slots + the
  direct-channel trio + the 60-value `ASENSOR_*` table; on-device
  verified (18 emulator sensors enumerated, queue events read back
  exact).

```xiom
use xiom.android;
use xiom.android.lifecycle;

let p = android_probe();
if p.is_ok {
  let lp = looper_prepare(true);              // Ok(Looper) on Android
  let pipe = looper_pipe_open();
  if lp.is_ok && pipe.is_ok {
    let l = lp.value;
    let pp = pipe.value;
    let _ = looper_add_fd_ident(&l, pp.read_fd, 42, ALOOPER_EVENT_INPUT);
    let _ = looper_pipe_write(&pp, 0x5a);
    let ident = looper_poll_once(&l, 1000);   // 42
    ...
  }
}
```

Run the conformance suite:

```
scripts/port.ps1 -Package xiom.android
```

Program context: `docs/ANDROID-SDK100.md` (coverage ledger) and
`docs/prep/android-wave.md` (wave brief).
