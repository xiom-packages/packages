# xiom.android -- SPEC

Android platform-core bindings for XIOM.  First package of the Android
SDK100 program (`docs/ANDROID-SDK100.md`); 0.3.0 carries the **A1
window-core + A5 assets-storage + A2 lifecycle-glue heads**.

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
- Declared export set: 27 (A1) + 26 (A5) + 64 (A2: looper 9 +
  activity 5 + config 50) = **117**.  A compile-time guard in the
  bridge pins the count; the suite asserts
  `android_export_count() == 117` on every host.
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
  activity flags) and `xiom.android.configuration` (config).

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

## Build

`scripts/port.ps1 -Package xiom.android` (compiles
`src/android_bridge.c` via `port.args.json`; suite SKIPs on Windows,
runs live on Android).  On-device evidence:
`docs/repro/` (driver + build-and-run script + recorded output) and
`docs/repro/check-glue-closure.ps1` (native_app_glue import closure).
