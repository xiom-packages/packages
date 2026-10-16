# xiom.android -- on-device evidence (A2 lifecycle-glue head, W2c)

Proves the A2 head on the API-36 x86_64 emulator (`emulator-5554`; AVD
`Medium_Phone_API_36.0`):

| Evidence | How |
|---|---|
| constant transcription | every `ALOOPER_*` / `ANATIVEACTIVITY_*` / `ACONFIGURATION_*` literal embedded in `src/lifecycle.xi` + `src/configuration.xi` is `_Static_assert`ed AT BUILD TIME against the real NDK r27b headers (`android/looper.h`, `android/native_activity.h`, `android/configuration.h`) in `lifecycle_head_probe.c` |
| runtime bridge | `src/android_bridge.c` (the shipped bridge) dlopens `libandroid.so` + `libnativewindow.so` and resolves the declared **117-symbol** export set (`missing=0`) |
| A1/A5 regression | AHardwareBuffer + ASharedMemory roundtrips stay exact (`0x11223344`) |
| ALooper functional | `ALooper_prepare(ALLOW_NON_CALLBACKS)` -> `pipe(2)` -> `ALooper_addFd(NULL cb, ident=42)` -> write -> `pollOnce` returns **42** with `last_fd`/`last_events` matching; callback variant -> `pollOnce` returns **ALOOPER_POLL_CALLBACK (-2)** with the callback observing `(fd=11, events=INPUT, data=0x77)`; empty -> **-3 (TIMEOUT)**; `wake` -> **-1 (POLL_WAKE)**; `pollAll(0)` -> -3; `removeFd` -> 1; acquire/release clean |
| AConfiguration functional | locale `de`/`DE` roundtrip; orientation/density/screenSize/sdk version exact; diff vs fresh = `0xd84` (LOCALE\|ORIENTATION\|DENSITY\|SCREEN_LAYOUT\|VERSION); clone diff = 0; match matrix `(copy,copy)=1 (copy,fresh)=0 (fresh,copy)=1 (fresh,fresh)=1`; `isBetterThan(fresh, clone, fresh)=1` |
| native_app_glue closure | `check-glue-closure.ps1` compiles the NDK's `android_native_app_glue.c` for **both** ABIs and walks its undefined symbols (per ABI, identical both): covered=21 (inside the 117-set), A3-input=6, A12-log=1 (live as `xiom.android-sys`), consumer=1 (`android_main`), bionic=21; **unknown=0** |

## Run

```
powershell -File build-and-run.ps1        # emulator must be up
powershell -File build-and-run.ps1 -Serial <serial>
powershell -File check-glue-closure.ps1   # glue import closure (no device needed)
```

## Platform semantics recorded by this probe (API-36)

- `AConfiguration_setScreenSize` maps into `SCREENLAYOUT_SIZE` bits: the
  diff bit is `ACONFIGURATION_SCREEN_LAYOUT`, not the legacy
  `ACONFIGURATION_SCREEN_SIZE` (the `getScreenSize` read-back is still
  exact = 2).  The package suite asserts the observed mask.
- `AConfiguration_match(base, requested)` follows the NDK doc
  ("0 if there are any values in `base` that conflict with
  `requested`"): a populated base vs an all-unset requested reports 0;
  a fresh base matches anything.  The observed matrix is recorded in
  `recorded-output.txt`.
- Handle addresses vary per run (ASLR); everything else is
  deterministic.

## Recorded run (2026-10-16)

See `recorded-output.txt`.  Summary: constant gate PASS at build time;
117/117 exports; A1/A5 roundtrips exact; looper ident/callback/timeout/
wake/pollAll all as stated; config roundtrips + diff/match exact;
RESULT: PASS.

## Files

- `lifecycle_head_probe.c` -- the driver (x86_64-linux-android26, PIE);
  includes the NDK headers for the build-time oracle gate.
- `build-and-run.ps1` -- NDK cross-build + push + run via adb.
- `check-glue-closure.ps1` -- native_app_glue import-closure proof
  (both ABIs).
- `recorded-output.txt` -- one representative run.
