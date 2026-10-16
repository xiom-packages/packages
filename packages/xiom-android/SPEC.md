# xiom.android -- SPEC

Android platform-core bindings for XIOM.  First package of the Android
SDK100 program (`docs/ANDROID-SDK100.md`); 0.4.0 carries the **A1
window-core + A5 assets-storage + A2 lifecycle-glue + A3 input + A4
sensors heads**.

## Scope (NDK r27b oracle)

- `android/native_window.h` -- 15 non-inline exports (`ANativeWindow_*`)
  + `ANativeWindow_LegacyFormat` (WINDOW_FORMAT_*), `ANativeWindow_Transform`,
  frame-rate compatibility/change-strategy enums (A1).
- `android/hardware_buffer.h` -- 12 exports (`AHardwareBuffer_*`) +
  the FORMAT_* and USAGE_* families (A1).
- `android/asset_manager.h` (17 non-JNI exports: `AAssetManager_*`,
  `AAssetDir_*`, `AAsset_*` + `AASSET_MODE_*`), `android/storage_manager.h`
  (6: `AStorageManager_*` OBB surface) and `android/sharedmem.h`
  (3: `ASharedMemory_*`) -- A5.  Sharedmem is exercised FUNCTIONALLY
  (create/size/setProt/map probe/close), the asset/storage surfaces are
  export-set ABI-checked (live wrappers need an app context -> A11).
- **A2 lifecycle-glue (0.3.0)**:
  - `android/looper.h` -- 9 platform exports (`ALooper_forThread`,
    `prepare`, `acquire`, `release`, `addFd`, `removeFd`, `pollOnce`,
    `pollAll`, `wake`); **FUNCTIONAL** in `xiom.android.lifecycle`
    (prepare on the calling thread, NULL-callback ident variant,
    direct-handoff callback variant, removeFd, pollOnce/pollAll with
    the out params read back through `looper_last_fd/events/data`,
    wake, acquire/release) plus the probe pipe helpers
    (`looper_pipe_open/write/read/close`).  Handlers are **direct
    handoff** (env-free top-level fns) -- the same post-B-22 callback
    ABI as glfw 0.6.0 / sdl3 0.20.0.  The wave brief's "11" proto
    measure reconciles as the 9 exports + the `ALooper_callbackFunc`
    typedef + the opaque `struct ALooper` declaration.
  - `android/native_activity.h` -- 5 platform exports
    (`ANativeActivity_finish` / `setWindowFormat` / `setWindowFlags` /
    `showSoftInput` / `hideSoftInput`), export-set ABI-checked; the
    show/hide flag constants live in `xiom.android.lifecycle`.  The
    header's 24 prototype-shaped declarations = 16
    `ANativeActivityCallbacks` fields + `ANativeActivity_createFunc` +
    `ANativeActivity_onCreate` + the 5 exports + the `ANativeActivity`
    typedef.  `onCreate` and the 16 callbacks are the CONSUMER's
    surface, implemented by the NDK's `native_app_glue` C unit
    (documented, not vendored -- the source ships in the NDK and
    compiles into the app; `docs/repro/check-glue-closure.ps1` proves
    the glue's undefined imports close over this package's declared
    set + the documented future slices).
  - `android/configuration.h` -- 51 prototypes; 50 platform exports
    wrapped **FUNCTIONALLY** in `xiom.android.configuration`
    (`AConfiguration_new/delete/copy/diff/match/isBetterThan` + the 19
    scalar int32 get/set pairs + language/country + `getScreenRound`).
    `AConfiguration_fromAssetManager` needs a live `AAssetManager` ->
    A11 (export-set ABI-checked).  **Documented delta**:
    `AConfiguration_setScreenRound` is declared by the header but NOT
    exported by the platform -- verified absent from the API-36 device
    `libandroid.so` AND the API-35 NDK stubs; excluded from the export
    set and kept on the delta list.  The brief's "52" measure
    reconciles as the 51 prototypes + the `AConfiguration`
    forward-declaration/typedef.  Observed platform semantics (recorded
    by the on-device probe): `setScreenSize` rides `SCREENLAYOUT`'s
    size bits (the suite's diff witness uses
    `ACONFIGURATION_SCREEN_LAYOUT`; the `getScreenSize` read-back stays
    exact), and `match(base, requested)` follows the NDK doc -- 0 when
    a value in `base` conflicts with `requested` (populated base vs
    all-unset requested = 0; fresh base matches anything).
- **A3 input (0.4.0)**: `android/input.h` (63 prototypes = **60
  platform exports** + the 3 `*_fromJava` JNI constructors -> A11)
  and `android/keycodes.h` (the frozen 317-entry `AKEYCODE_*` enum).
  Exports: `AInputEvent_*` 4, `AInputQueue_*` 6 (the native_app_glue
  integration point), `AKeyEvent_*` 8, `AMotionEvent_*` 42 -- all
  wrapped in `xiom.android.input` with the 161-value `input.h` +
  317-value `keycodes.h` constant tables.  The queue is
  framework-delivered to an app (never fabricated by the bridge); the
  live attach/detach + keycode/event-read path is proven by the
  on-device **app probe** (C-only NativeActivity APK), the shell probe
  proves the explicit-error contract.  Float-valued accessors cross
  the boundary as IEEE-754 binary32 BIT PATTERNS (B-12: fp cast-call
  returns are miscompiled on the pinned toolchain); `android_f32_from_bits`
  rebuilds them in pure arithmetic.  One platform quirk recorded:
  `AInputEvent_release` is scoped by the header to the `fromJava`
  objects -- releasing a queue event double-frees (Scudo abort),
  witnessed during probing; the module documents the release scope.
- **A4 sensors (0.4.0)**: `android/sensor.h` -- **32 platform
  exports** (`ASensorManager_*` 12, `ASensorEventQueue_*` 7,
  `ASensor_*` 13) + the 60-value `ASENSOR_*` table, all wrapped in
  `xiom.android.sensors`.  `getSensorList`/`getDynamicSensorList`
  hand back PLATFORM-owned lists (stable out-pointers, indexed
  through `xa_sensor_list_at`); `getEvents` fills **bridge-owned
  ASensorEvent slots** (sizeof 104, timestamp @16, data @24, flags
  @88 -- `_Static_assert`-gated at probe build against the real
  header) with typed per-slot accessors; float payloads also ride
  the binary32-bits path.  On-device LIVE: manager -> 18 sensors ->
  ident + callback event queues -> `registerSensor` ->
  `getEvents` with exact x/y/z; direct-channel creation is offered by
  the API but rejected by the emulator's goldfish HAL (rc=-12,
  recorded, never papered over).
- Declared export set: 27 (A1) + 26 (A5) + 64 (A2: looper 9 +
  activity 5 + config 50) + 60 (A3) + 32 (A4) = **209**.  A
  compile-time guard in the bridge pins the count; the suite asserts
  `android_export_count() == 209` on every host.
- Constant transcription: all 538 input.h/keycodes.h/sensor.h
  constants (161 + 317 + 60) are GENERATED from the NDK r27b headers
  by `docs/repro/gen-a3a4-consts.ps1` (values evaluated by the NDK
  compiler on the API-36 emulator) and re-gated at probe build time
  by `_Static_assert` against the real headers (534 int + 3 float
  asserts; the `nanf("")` sentinel rides a bit-pattern runtime check).
- Minimum API floor for the FULL declared set: API 34
  (`get/setGrammaticalGender`; `getScreenRound` is API 30).  The ABI
  check is strict: an older system image reports the honest delta
  (never a silent SKIP).
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
- Functional heads: `AHardwareBuffer` (isSupported -> allocate ->
  describe -> lock/write -> lock/read -> unlock -> release),
  `ASharedMemory` (memfd + mmap probe), `ALooper` (pipe + addFd +
  pollOnce + wake; callback and ident variants) and `AConfiguration`
  (value-object roundtrips, diff/match).
- `ANativeWindow_*` ops need a live `Surface`, `ANativeActivity_*` ops
  a live activity -- symbol-bound + ABI-checked here; live window/app
  ops arrive with the A11 JNI seam.
- Ownership discipline: pointers never cross the boundary (B-25):
  locked buffer addresses, pipe ends, poll out-params
  (`xa_looper_last_fd/events/data`) and the language/country char[2]
  stay C-side; handles cross as `Int`.  Looper handlers are top-level
  fns -- the C side receives the code address only (no environment).
- The A2 heads live in submodules: `xiom.android.lifecycle` (looper +
  activity flags) and `xiom.android.configuration` (config); the A3/A4
  heads likewise: `xiom.android.input` (queue + key/motion + the
  538-constant input/keycode tables) and `xiom.android.sensors`
  (manager/queue/sensor + the ASENSOR_* table).  Both sit on the same
  runtime bridge; every call without a loaded runtime errors
  explicitly.
- A3 float accessors return `Float64` rebuilt from binary32 bits
  (`android_f32_from_bits`; negative sentinel = bridge error recorded
  in `android_error()`); A4 event slots stay C-side -- index-typed
  `SensorEvent` values address the last `queue_read` batch (B-25:
  no pointers on the XIOM side).

## Classification

| Probe outcome | Marker | Suite result |
|---|---|---|
| libs absent (Windows, bogus pair) | `ANDROID_LOAD_ABSENT` | SKIP (green) |
| exports missing / broken install | `ANDROID_LOAD_ABI` | FAIL |
| full export set + working heads | Ok | live checks |

Runtime calls made without a loaded runtime error explicitly (never a
silent zero handle); the suite exercises that path on every host.

## Documented exclusions (for this head)

- `native_window_jni.h` / `hardware_buffer_jni.h` (fromSurface /
  toSurface / fromHardwareBuffer): JNI seam, slice A11.
- `AInputQueue_fromJava` / `AKeyEvent_fromJava` / `AMotionEvent_fromJava`
  (input.h's 3 JNI constructors): JNI seam, slice A11.  The header
  scopes `AInputEvent_release` to the objects THEY create -- queue
  events are owned by the getEvent/finishEvent pair; releasing a
  queue event double-frees (Scudo abort, witnessed while probing and
  documented in the module).
- `asset_manager_jni.h` / `sharedmem_jni.h` (fromJava / dupFromJava):
  JNI seam, slice A11 (live asset/storage wrappers join with it);
  `AConfiguration_fromAssetManager` likewise.
- `ANativeActivity_onCreate` + the 16 `ANativeActivityCallbacks`
  fields: the consumer's surface (native_app_glue implements them);
  source not vendored.
- `AConfiguration_setScreenRound`: header-only prototype, absent from
  the platform libraries (delta documented above).
- Inline-only helpers (`ANativeWindow_clearFrameRate`): no export; the
  underlying `setFrameRateWithChangeStrategy` is bound.
- `ALooper_pollAll`: exported + bound (legacy binary compatibility);
  the header deprecates it (may miss wakes) -- prefer `pollOnce`.
- Window ops requiring a live Surface and activity ops requiring a
  live activity: bound for ABI; functional runs join at A11/G1.
- A4 direct channels: `createSharedMemoryDirectChannel` /
  `createHardwareBufferDirectChannel` / `configureDirectReport` are
  bound + exercised; the API-36 emulator's goldfish sensor HAL
  rejects channel creation (rc=-12/-22 recorded in the probe output).
  Behavior is platform-dependent, never masked.
- Injected TOUCH events on the emulator: refused for the C-only
  NativeActivity probe window (dispatcher `InputWindowInfo` frame
  0x0 / empty touchable region; keyboard events deliver via the
  focused path).  The 42 `AMotionEvent_*` exports are ABI-checked and
  the accessor surface is exercised; motion decoding needs a device
  that delivers motion to the queue (documented in
  `docs/repro/README.md`; no faked evidence).

## Build

`scripts/port.ps1 -Package xiom.android` (compiles
`src/android_bridge.c` via `port.args.json`; suite SKIPs on Windows,
runs live on Android).  On-device evidence:
`docs/repro/` (driver + build-and-run script + recorded output) and
`docs/repro/check-glue-closure.ps1` (native_app_glue import closure).
