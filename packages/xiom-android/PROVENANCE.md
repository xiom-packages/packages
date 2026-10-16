# xiom.android -- PROVENANCE

## Oracle

- NDK r27b `27.1.12297006` public headers (sysroot `usr/include`):
  `android/native_window.h`, `android/native_window_jni.h`,
  `android/hardware_buffer.h`, `android/hardware_buffer_jni.h`,
  `android/rect.h` (A1); `android/asset_manager.h`,
  `android/storage_manager.h`, `android/sharedmem.h` (A5);
  `android/looper.h`, `android/native_activity.h`,
  `android/configuration.h` (A2); `android/input.h`,
  `android/keycodes.h` (A3); `android/sensor.h` (A4).
- Link oracle: API-35 platform stubs, `libandroid.so` +
  `libnativewindow.so` (both architectures present in the sysroot);
  the A2 export set was cross-checked against the API-36 emulator's
  `/system/lib64/libandroid.so` (`llvm-nm -D`, 2026-10-16):
  looper 9/9, native_activity 5/5, configuration 50 exported /
  51 prototypes.
- Function names, struct layouts and constant values are API facts
  transcribed from the headers.  Constant transcription is checked at
  BUILD TIME against the real NDK headers in the on-device drivers
  (`docs/repro/lifecycle_head_probe.c` static_asserts the A2 values;
  `docs/repro/gen-a3a4-const-asserts.h`, produced by
  `docs/repro/gen-a3a4-consts.ps1` and compiled into
  `input_head_probe.c`, static_asserts all 538 A3/A4 values -- the
  values themselves were EVALUATED by the NDK compiler on the API-36
  emulator from the real headers, so the transcription pipeline has
  a single source: the header).
- A3/A4 measurement reconciliation: input.h's 63 prototype-shaped
  names = 60 platform exports + the 3 `*_fromJava` JNI constructors
  (A11); keycodes.h = one frozen 317-entry `AKEYCODE_*` enum (no
  #define escapes); sensor.h = 32 platform exports.  `AMOTION_EVENT_*`
  action pointer-index packing (`ACTION_POINTER_INDEX_MASK/SHIFT`) is
  a #define pair inside input.h and is transcribed with its family.
  `ASensorEvent` ABI pinned + `_Static_assert`-gated: sizeof 104,
  timestamp @16, data @24, flags @88 (measured on-device).
- Measurement reconciliation (wave brief -> header truth):
  looper "11" = 9 platform exports + `ALooper_callbackFunc` typedef +
  opaque `struct ALooper`; native_activity "24" = 16 callback fields +
  `createFunc` typedef + `onCreate` + 5 exports + the
  `ANativeActivity` typedef; configuration "52" = 51 prototypes + the
  `AConfiguration` typedef.  Delta: `AConfiguration_setScreenRound`
  is declared by the header but exported by NO platform library
  (device API-36 + API-35 stubs verified) -- excluded from the export
  set, documented in SPEC.
- `sources/android/native_app_glue/android_native_app_glue.{c,h}` --
  the NDK's app-lifecycle glue C unit.  It is NOT vendored: it ships
  in the NDK and compiles into the consumer app; this package's
  relation to it is documented (SPEC) and its import closure is
  proven by `docs/repro/check-glue-closure.ps1` (its ALooper_*/
  AConfiguration_*/ANativeActivity_* imports must resolve inside this
  package's declared export set; AInputQueue_* (A3) and
  `__android_log_print` (A12, live as `xiom.android-sys`) are the
  documented future-slice imports).

## Code

- `src/android_bridge.c`, `android.xi`, `src/lifecycle.xi`,
  `src/configuration.xi`, `src/input.xi`, `src/sensors.xi`,
  `tests/test_conformance.xi`, and this package's metadata are
  original XIOM code (MIT OR Apache-2.0), written for this repository;
  no upstream implementation code is vendored.  The constant blocks in
  `src/input.xi` / `src/sensors.xi` below the `GENERATED CONSTANTS`
  banner are produced by `docs/repro/gen-a3a4-consts.ps1` (a repo
  script) from the NDK headers -- values are API facts, not code.
- No NDK headers are copied into the repository; the bridge compiles
  without them (self-declared pinned ABI facts only).  The on-device
  driver includes the real headers -- build-time oracle only, never
  shipped.

## License notes

- The NDK platform headers (`android/*`) are distributed by Google
  under the Apache License 2.0 (bionic portions BSD-3-Clause); the
  native_app_glue source carries the Apache-2.0 WITH LLVM-exception
  notice.  This package interoperates with the public ABI;
  declarations here are facts of that interface, and the package
  itself ships no Google code.
- A3/A4 header groups: `android/input.h` and `android/keycodes.h`
  (A3) are AOSP platform headers under Apache-2.0 (their license
  headers name the Android Open Source Project, Apache-2.0;
  BSD-3-Clause applies to the bionic-derived portions of the NDK
  sysroot); `android/sensor.h` (A4) likewise carries the AOSP
  Apache-2.0 notice.  Independent declaration: none of these headers,
  in whole or in part, is copied or vendored here -- only the public
  ABI facts (names, signatures, enum values, struct layout) are
  transcribed, as facts of the interface, and the A3/A4 driver files
  under `docs/repro/` `#include` the headers at build time only.

## Touch log

- 2026-10-15: created (W2a head; per-touch PROVENANCE rule).
- 2026-10-15: W2b A5 head -- asset_manager.h (17) / storage_manager.h
  (6) / sharedmem.h (3) added to the oracle + export set (53 symbols);
  sharedmem exercised functionally (suite + on-device probe).
- 2026-10-16: W2c A2 head -- looper.h (9) / native_activity.h (5) /
  configuration.h (50 exports of 51 prototypes) added to the oracle +
  export set (117 symbols); looper + configuration exercised
  functionally (suite + on-device probe); native_app_glue documented +
  import-closure proof; setScreenRound delta recorded; platform +
  runtime_deps rows declared.
- 2026-10-16: W2d A3/A4 heads -- input.h (60 exports of 63 names;
  3 JNI constructors -> A11) + keycodes.h (317-value enum) + sensor.h
  (32 exports) added to the oracle + export set (209 symbols); 538
  constants generated from the headers (NDK-compiler-evaluated
  dump on the API-36 emulator) + `_Static_assert`-gated at probe
  build; A4 exercised LIVE on-device (18 sensors, ident + callback
  event queues, getEvents exact); A3 queue proven live by a C-only
  NativeActivity app probe (attach/detach rc=0 x2, AKEYCODE_A/B
  decoded, preDispatch/finish); `AInputEvent_release` scope corrected
  (fromJava-only; queue-event release = Scudo abort, witnessed);
  touch injection documented blocked for the probe window (dispatcher
  InputWindowInfo frame 0x0; Java apps receive touches); glue
  closure re-run: the 6 A2-era A3-input imports now classify as
  covered; native_app_glue relation unchanged (not vendored).

