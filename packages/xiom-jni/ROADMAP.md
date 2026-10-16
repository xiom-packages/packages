# xiom.jni -- ROADMAP

Android SDK100 program: `docs/ANDROID-SDK100.md`; wave brief:
`docs/prep/android-wave.md`.

## 0.1.0 -- A11 jni-seam head (current)

- [x] Runtime pair loader (`libjnigraphics.so` + `libnativehelper.so`)
  with ABSENT/ABI classification + 9-export set verification; SKIP-safe
  on Windows (suite green, no false green).
- [x] Pinned ABI facts from NDK r27b `jni.h` + `android/bitmap.h`:
  233-slot `JNINativeInterface`, 8-slot `JNIInvokeInterface`, `jvalue`,
  `JNINativeMethod`, `AndroidBitmapInfo`; 56 table offsets + struct
  offsets gated against the real header at probe build AND at runtime
  (bridge offset table) on the API-36 emulator -- all identical.
- [x] The seam: consumer-supplied `JavaVM*`/`JNIEnv*` as Int handles;
  env/version/GetJavaVM/GetCreatedJavaVMs; class/ref/exception ops; ID
  lookup; call families (int/boolean/long/double-bits/float-bits/
  object/void; instance + static, A-variants); fields; UTF-8 strings
  into an owned slot; int-array regions through owned slots;
  `RegisterNatives` via the JNINativeMethod shape;
  attach/detach-current-thread.
- [x] `android/bitmap.h` functional: getInfo readback slot,
  getDataSpace, manual lock window, write/read pixel exact roundtrips,
  out-of-range guard, isHardware, getHardwareBuffer, PNG compress into
  an owned buffer (signature-checked).
- [x] null-safety for every helper (0-env/0-object/0-vm -> typed error,
  no crash) + a deterministic SKIP-path exercise in the suite.
- [x] On-device shell probe: per-library `dlopen` provider map, 9/9
  exports, bridge loader, null paths, honest no-VM answer for a plain
  shell process.
- [x] On-device app probe (`app_process` dex jar = the consumer
  stand-in): JNI_OnLoad vm -> env; full seam battery (calls with exact
  longs/double bits, parseInt, UTF readback, array roundtrip, exception
  path, RegisterNatives, pthread attach/detach); bitmap roundtrip on a
  real `Bitmap.createBitmap(64x64, ARGB_8888)` + Java-side
  `getPixel` readback -- PASS.
- [x] Suite: 89 checks (constants, JNINativeMethod shape, export-count
  guard, null battery over every family, SKIP-path classification,
  unloaded-runtime explicit errors).
- [x] STATUS.json: `platforms` (windows-x64 / android-arm64 /
  android-x86_64) + `runtime_deps` declared.

## Next

- 0.2.0: fp decode helpers (`jni_f64_from_bits`/`jni_f32_from_bits`)
  once compiler **B-29** (big-int bit ops >= 2^31) is fixed -- or via a
  C-side split-retum helper before that; `CallNonvirtual*` and the
  remaining `Call<Type>Method` return kinds (byte/char/short) as
  op-family growth; `NewObjectA` + `NewObjectArray` families.
- 0.3.0: consumer-app surface helpers used by the sibling slices'
  `*_fromJava` routes (ANativeWindow_fromSurface,
  AAssetManager_fromJava, ASharedMemory_dupFromJava,
  AInputEvent_*_fromJava, HWB_fromHardwareBuffer,
  AStorageManager_fromJava) -- each one is a thin composition over this
  seam; wire them into `xiom.android` when the android family is
  re-touched.
- On-device suite runs: after **G1** (compiler android emission target)
  the conformance suite itself runs on the emulator; until then the
  `docs/repro/` drivers prove the bridge functionally.
- Naming: keep `xiom.jni` (by-function rule) unless the naming gate
  (`docs/prep/android-wave.md`) renames the android family.
