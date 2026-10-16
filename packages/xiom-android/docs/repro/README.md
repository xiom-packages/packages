# xiom.android -- on-device evidence

## A3 input + A4 sensors heads (W2d, 0.4.0)

Two binaries prove the A3/A4 heads on the API-36 x86_64 emulator
(`emulator-5554`; AVD `Medium_Phone_API_36.0`):

**Shell probe** (`input_head_probe.c`; push+run in
`/data/local/tmp/xiom-spike/`; recorded: `recorded-input-shell.txt`):

| Evidence | Result |
|---|---|
| constant transcription gate | the generated `gen/a3a4_const_asserts.h` gates all **538** transcribed constants (input.h 161 + keycodes.h 317 + sensor.h 60) against the REAL NDK r27b headers AT BUILD TIME: 534 int `_Static_assert`s + 3 float asserts + the `ASENSOR_RESOLUTION_INVALID` nanf("") sentinel runtime-checked (`bits == 0x7FC00000`); `sizeof(ASensorEvent)==104` / offsets 16/24/88 static-asserted |
| export set | **209/209 resolved, 0 missing** on the device's `libandroid.so` (117 A1/A2/A5 + 60 A3 + 32 A4) |
| A3 explicit-error contract | null queue -> explicit error on every head (never a silent zero); a shell process cannot own an `AInputQueue` by design (framework-delivered) |
| A4 enumeration | `ASensorManager_getInstance` -> **18 sensors** listed + described (handle/type/name/vendor/string-type/min-delay/FIFO/reporting-mode/wake-up/direct-rate/resolution) |
| A4 event queue (ident variant) | `createEventQueue(ident=7)` -> `registerSensor(accel, 20000us)` -> `ALooper_pollOnce` -> `getEvents` **1 event**: `type=1` (ACCELEROMETER), `ts>0`, `x=0 y=9.77632 z=0.812345` (gravity, exact f32 bits decoded) -> disable -> destroy |
| A4 event queue (callback variant) | `createEventQueue(callback)` -> callback fires, `pollOnce` returns **ALOOPER_POLL_CALLBACK (-2)** |
| A4 queue management | `requestAdditionalInfoEvents(disable)` -> 0; `enableSensor`/`setEventRate(40000us)` -> 0 |
| A4 direct channels | `createSharedMemoryDirectChannel` / `createHardwareBufferDirectChannel` -> **rc=-12** (goldfish HAL does not offer direct channels; recorded honestly, not papered over); `configureDirectReport(STOP)` -> -22 |

**App probe** (`input_app_probe.c`; a C-only NativeActivity APK --
`hasCode="false"`, native_app_glue drives the lifecycle; built, signed
(debug keystore), installed, launched, fed with
`input keyevent 29/30/31`; recorded: `recorded-input-app.txt`):

| Evidence | Result |
|---|---|
| export set in an app process | **209 resolved, 0 missing** (`A3 load rc=0`) |
| framework-delivered queue | the glue-delivered `AInputQueue` decoded through `xiom.android.input` accessors |
| **AInputQueue detach + attach** | `AInputQueue_detachLooper` **rc=0** (removed from the glue looper) then `AInputQueue_attachLooper` (callback variant) **rc=0** -- on the LIVE queue; a second detach/re-attach cycle repeats both rc=0 mid-stream |
| keycode proof | `AKEYCODE_A (29)` and `AKEYCODE_B (30)` events decoded: action DOWN/UP, `key_event_key_code`, down/event times, meta/repeat -- `A3 keycode decoded` x4 |
| event-read proof | `getEvent` -> `preDispatchEvent` (honoring the abandon-on-nonzero contract) -> `finishEvent` on every kept event; `A3_RESULT fail=0 events=4` |
| sensor sanity in-app | `sensor manager=ok sensors=18` |

**Documented block (recorded in `recorded-input-app.txt`)**: injected
TOUCH events are not deliverable to this probe window -- the dispatcher's
`InputWindowInfo` for the C-only NativeActivity window carries
`frame=[0,0][0,0] / touchableRegion=<empty>`, so `input tap` /
`input motionevent` are refused (touches DO reach Java apps in the same
session).  The motion side is therefore proven by the export set (all 42
`AMotionEvent_*` symbols resolved) + the ABI-gated accessor surface; the
same accessors decode motion the moment a device delivers it to the
queue.  No evidence is faked.

## Run

```
powershell -File build-and-run-input.ps1          # both probes (emulator must be up)
powershell -File build-and-run-input.ps1 -SkipApp # shell probe only
```

## A2 lifecycle-glue head (W2c)

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
