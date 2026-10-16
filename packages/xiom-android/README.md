# xiom.android

Android platform-core bindings for XIOM -- the A1 (window-core) + A5
(assets-storage) + A2 (lifecycle-glue) heads of the Android SDK100
program.

- Runtime probe for `libandroid.so` + `libnativewindow.so` with SKIP
  semantics (absent runtime -> `ANDROID_LOAD_ABSENT`; broken exports ->
  `ANDROID_LOAD_ABI` FAIL); 117-symbol declared export set.
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
  close over this package + the documented future slices.

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
