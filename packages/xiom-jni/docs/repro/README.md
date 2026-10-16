# xiom.jni -- on-device evidence

Two probes prove the A11 head on the API-36 x86_64 emulator
(`emulator-5554`; AVD `Medium_Phone_API_36.0`):

## 1. Shell probe (`jni_head_probe.c`; recorded: `recorded-shell.txt`)

| Evidence | Result |
|---|---|
| constant transcription gate | every constant in `src/jni.xi` + the module's enums is `_Static_assert`-ed AT BUILD TIME against the real NDK r27b `jni.h` + `android/bitmap.h`; `sizeof(struct JNINativeInterface)==233*sizeof(void*)`; `sizeof(jvalue)==8`; `sizeof(JNINativeMethod)` + offsets; `sizeof(AndroidBitmapInfo)==20` + offsets; prototype pins for the 6 `AndroidBitmap_*` + `JNI_GetCreatedJavaVMs` (typed fn-pointer assignment) |
| bridge layout gate | `xj_abi_*` numeric table compared at runtime against the header's `offsetof`: **all 56 `JNINativeInterface` offsets + 3 `JNIInvokeInterface` + 5 `AndroidBitmapInfo` + 3 `JNINativeMethod` members identical**, `sizeof` identical |
| per-library dlopen | `libjnigraphics.so` + `libnativehelper.so` both load; provider map: the 6 `AndroidBitmap_*` from jnigraphics; the `JNI_*` trio resolves through either handle (jnigraphics depends on nativehelper) |
| export set | **9/9 resolved** (bridge `xj_load` rc=0, 0 missing of 9, export count 9) |
| plain-shell JSVM honesty | `JNI_GetCreatedJavaVMs` callable; count 0 -> `xj_vm_from_created(0)` = 0 + typed error "no JavaVM at index 0 (created count 0)" (a full env needs a Java host -- probe 2) |
| null-safety | `env_version(0)` -1, `find_class(0,..)` 0, `bitmap_get_info(0,0)` non-zero, `bitmap_write_pixel(0,..)` non-zero, `bitmap_read_pixel(0,..)` -1 -- all with typed error text, no crash |

`RESULT: PASS` (recorded in `recorded-shell.txt`).

## 2. App probe (`jni_app_probe.c` + `Probe.java`; recorded: `recorded-app.txt`)

The consumer contract, executed for real: `Probe.java` -> `d8` ->
`classes.dex`, run with `app_process`; its `System.load` of
`libxjniprobe.so` triggers **`JNI_OnLoad(vm)`**, which hands `vm` (as
`Int`) to the bridge exactly as a consuming app would.

| Evidence | Result |
|---|---|
| JNI_OnLoad seam | `xj_vm_get_env(vm, JNI_VERSION_1_6)` -> env; `GetVersion` == `JNI_VERSION_1_6`; `GetJavaVM(env)` == the JNI_OnLoad vm; `JNI_GetCreatedJavaVMs(0)` == the live vm |
| calls | `Probe.inc(1)` -> 2 (`CallStaticIntMethodA`); `Probe.tick()` -> 1234567890123 exact (`CallStaticLongMethodA`); `Probe.ratio()` -> **bits 0x3FF8000000000000 = 1.5 exactly** (`CallStaticDoubleMethodA`, fp crosses as bits); `Integer.parseInt("31337")` -> 31337 (FindClass + GetStaticMethodID + NewStringUTF + `_s` call) |
| fields + strings | `Probe.tag` (compile-time constant, readable during `<clinit>`) via `GetStaticObjectField` -> `GetStringUTFLength` 9 -> UTF-8 readback `"probe-tag"` exact |
| arrays | `NewIntArray(4)` -> slots 10/20/30/40 -> `SetIntArrayRegion` -> slots zeroed -> `GetIntArrayRegion` -> 10/20/30/40 exact; `GetArrayLength` 4 |
| exception path | `FindClass` of a missing class -> 0 + `ExceptionCheck==1` -> `ExceptionClear` -> 0 |
| RegisterNatives | `xj_register_native(env, Probe, "runProbe", "(Landroid/graphics/Bitmap;)I", fn)` -> rc 0; the Java side then calls the registered native method |
| thread seam | pthread: `AttachCurrentThread` -> env (`GetVersion` 1.6) -> `DetachCurrentThread` rc 0 |
| bitmap on a real Bitmap | `Bitmap.createBitmap(64, 64, ARGB_8888)`: `getInfo` (64x64, stride 256, format RGBA_8888=1), `getDataSpace` = 142671872 (ADATASPACE_SRGB), `isHardware` 0; manual lock window + `writePixel(7,5, 0xFF223344)` + `readPixel` exact; auto-locked `writePixel(0,0, 0xFFADBEEF)` + readback exact; out-of-range write -> explicit error; `AndroidBitmap_compress` PNG -> **142 bytes in the owned buffer with the 89 50 4E 47 signature** |
| Java-side readback | `bmp.getPixel(7,5) == 0xFF443322` and `getPixel(0,0) == 0xFFEFBEAD` -> `JNI_PROBE JAVA SIDE: PASS` |

`A11_SEAM fail=0` + `A11_BITMAP fail=0` (recorded in
`recorded-app.txt`).

### Platform semantics recorded by this probe (API-36)

- **Premultiplied alpha**: Android bitmaps store RGBA_8888
  premultiplied.  A raw semi-transparent write (e.g. 0x11223344 through
  the lock, A=0x11) is unpremultiplied by the Java `getPixel` readback:
  0x11223344 came back as 0x11FFFFFF -- exact premultiply math
  (R'=0x44,A=0x11 -> R=0x44*255/17=0xFF after clamp).  The probe uses
  opaque pixels so premultiplication is the identity; the C-side
  raw-storage roundtrip is exact either way.
- **Byte order**: lockPixels exposes little-endian bytes R,G,B,A; a raw
  uint32 write of 0xFF223344 lands as bytes 44 33 22 FF, so the Java
  ARGB int reads as 0xFF443322 (the low 24 bits byte-swapped).  Both
  orientations are asserted, so the mapping is pinned, not papered over.
- **JNI C mapping (found by this probe)**: an env/vm handle is a
  pointer to the interface-holder struct whose FIRST WORD is the table
  pointer (`(*env)->FindClass(env, ...)`); the bridge dereferences once.
  The first probe build segfaulted treating the handle as the table --
  fixed and re-proven (PROVENANCE touch log).
- **Static fields during `<clinit>`**: `JNI_OnLoad` fires inside the
  static initializer that runs `System.load`; a non-constant static
  field (`public static String tag = "probe-tag"`) is still null at
  that moment (observed: GetStaticObjectField returned null; the
  null-return path also exposed a second bug -- the exception-note
  helper read the raw handle as the table -- fixed).  The probe's `tag`
  is `static final` (ConstantValue set at preparation), which is
  readable through JNI even mid-init.

## Run

```
powershell -File build-and-run.ps1            # both probes (emulator must be up)
powershell -File build-and-run.ps1 -SkipApp   # shell probe only
powershell -File build-and-run.ps1 -SkipShell # app probe only
```

Notes: the shell probe links at API 31 (`libnativehelper.so` is public
since API 31); the app `.so` links at API 26 and calls the platform only
through the bridge (`dlopen`).  `app_process` needs the pushed
`classes.dex` via `CLASSPATH` (the script does this); `System.load`
takes the absolute `/data/local/tmp/xiom-spike/libxjniprobe.so` path.

## Files

- `jni_head_probe.c` -- shell driver (build-time oracle gate + loader +
  null paths).
- `jni_app_probe.c` -- the JNI_OnLoad seam battery + `runProbe` bitmap
  native method.
- `Probe.java` -- the Java host (app_process entry point).
- `build-and-run.ps1` -- clang cross-builds + javac/d8 + push + run +
  record.
- `recorded-shell.txt`, `recorded-app.txt` -- representative runs
  (2026-10-16).
