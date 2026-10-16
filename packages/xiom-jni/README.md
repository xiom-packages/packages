# xiom.jni

Android JNI seam bindings for XIOM -- the **A11 jni-seam** head of the
Android SDK100 program (`docs/ANDROID-SDK100.md`): the `jni.h`
interface plus the `android/bitmap.h` cluster.

- Runtime loader for the pair `libjnigraphics.so` + `libnativehelper.so`
  with SKIP semantics (absent/partial -> `JNI_LOAD_ABSENT`; broken
  exports -> `JNI_LOAD_ABI` FAIL); 9-symbol declared export set
  (`AndroidBitmap_*` 6 + the `JNI_*` VM entry points 3).
- **The seam**: the consumer app hands the `JavaVM*` from its
  `JNI_OnLoad` (and any `JNIEnv*`) to `xiom.jni` as `Int` handles; the
  C bridge performs every table call -- `FindClass`, `GetMethodID`/
  `GetStaticMethodID`/`GetFieldID`, the `Call*MethodA` families (int/
  boolean/long/double-bits/float-bits/object/void, instance + static),
  field get/set, `NewStringUTF` + UTF-8 readback, int-array regions
  through owned slots, exception check/clear/throw,
  `RegisterNatives` (JNINativeMethod shape), refs/local frames,
  `GetEnv`/`AttachCurrentThread`/`DetachCurrentThread`,
  `JNI_GetCreatedJavaVMs`.
- `jni.h` is interface-based: the declared surface is a **per-op-family
  helper set** (97 C helpers), complete for its families and 100 %
  covered by the suite + probes; SPEC.md records the strategy and every
  header-truth reconciliation.
- Functional `android/bitmap.h` head: `bitmap_get_info` (info struct
  read back into a bridge-owned slot), `bitmap_get_data_space`,
  `bitmap_lock_pixels`/`bitmap_unlock_pixels` (manual window; the
  pixel address never crosses), `bitmap_write_pixel`/`bitmap_read_pixel`
  (lock + stride walk + unlock; exact u32 roundtrips), `bitmap_is_hardware`,
  `bitmap_get_hardware_buffer`, `bitmap_compress_owned` (PNG/JPEG/WEBP
  through the C-side write callback into an owned buffer).
- **null-safety on every helper**: 0-env/0-object/0-vm -> typed error +
  documented sentinel (0 / -1 / `INT32_MIN`); `jni_error()` is empty
  after a successful call.  A non-null garbage handle is outside the
  consumer contract.
- B-series discipline: handles as `Int` (B-25), fp returns as IEEE-754
  bit patterns (B-12/B-29-safe), chars/pixel addresses/array traffic in
  bridge-owned slots (B-24-safe reads), no pointer arithmetic.

```xiom
use xiom.jni;

// 1. consumer app: JNI_OnLoad(JavaVM* vm) -> pass vm as Int
let env_r = vm_get_env(&JavaVm{ handle: vm_as_int }, JNI_VERSION_1_6);
if env_r.is_ok {
  let env = env_r.value;
  let r = find_class(&env, "com/example/App");
  if r.is_ok {
    let c = r.value;
    let m = get_static_method_id(&env, &c, "version", "()I");
    if m.is_ok {
      let v = call_static_int_method(&env, &c, &m.value);   // Ok(Int)
    }
  }
  // bitmap path (e.g. from RegisterNatives-registered native method)
  // bitmap_get_info / bitmap_write_pixel / bitmap_read_pixel /
  // bitmap_compress_owned ...
}
```

Run the conformance suite (SKIP-safe on Windows):

```
scripts/port.ps1 -Package xiom.jni
```

On-device evidence (emulator up):

```
powershell -File packages\xiom-jni\docs\repro\build-and-run.ps1
```

Program context: `docs/ANDROID-SDK100.md` (coverage ledger) and
`docs/prep/android-wave.md` (wave brief).
