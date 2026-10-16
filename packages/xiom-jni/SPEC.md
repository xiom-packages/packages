# xiom.jni 0.1.0 -- SPEC

Android JNI seam (NDK r27b **A11 jni-seam** slice of
`docs/ANDROID-SDK100.md`): the `jni.h` interface calls + the
`android/bitmap.h` cluster, behind one XIOM module (`xiom.jni`) with a
C-side bridge (`src/jni_bridge.c`, compiled via `port.args.json`).

## Why a seam (the A11 design note)

`jni.h` is an **interface, not a flat export map**: the `JNIEnv` /
`JavaVM` function tables only exist inside a live Java host.  Binding
them like a normal library is impossible; every wrapper for a live
`Surface`/`Context`/asset (and every `*_fromJava` route parked by the
sibling Android slices) needs this seam.  The design decided in
`docs/ANDROID-SDK100.md`:

- **env/object slots are supplied by the CONSUMER APP** -- the app hands
  the `JavaVM*` it receives in its `JNI_OnLoad` (and any `JNIEnv*` it
  already holds) to `xiom.jni` as `Int` handles;
- **no callback bridging**: `JNI_OnLoad`/`JNI_OnUnload` stay the
  consumer's exports; `xiom.jni` never creates a VM
  (`JNI_CreateJavaVM` is declared + ABI-checked only -- on Android it is
  not usable from apps);
- every table call happens **C-side** in the bridge, through a
  self-declared pinned table layout (NDK r27b `jni.h`; offsets gated at
  probe build time against the real header -- see PROVENANCE).

## Subset strategy (jni.h is interface-based)

The measured interface cluster is huge (`JNINativeInterface`: **233
members**; `JNIInvokeInterface`: 8; plus the manifest macros), so the
declared surface is a **per-op-family helper set**, not a 1:1 member
transcription.  The declared surface is complete for its families and
100% covered by the suite + probes:

| op family | declared helpers (C bridge) |
|---|---|
| loader/classification | `xj_load_named`, `xj_load`, `xj_error`, `xj_abi_missing_count`, `xj_abi_missing`, `xj_export_count`, `xj_unload` |
| VM / env | `xj_vm_get_env`, `xj_vm_attach_current`, `xj_vm_detach_current`, `xj_vm_from_created`, `xj_env_get_java_vm`, `xj_env_version` |
| class / refs / exceptions | `xj_find_class`, `xj_get_object_class`, `xj_get_superclass`, `xj_is_assignable_from`, `xj_is_instance_of`, `xj_new_global_ref`, `xj_delete_global_ref`, `xj_delete_local_ref`, `xj_new_local_ref`, `xj_push_local_frame`, `xj_pop_local_frame`, `xj_ensure_local_capacity`, `xj_exception_check`, `xj_exception_occurred`, `xj_exception_describe`, `xj_exception_clear`, `xj_throw_new`, `xj_throw`, `xj_register_native`, `xj_unregister_natives` |
| IDs | `xj_get_method_id`, `xj_get_static_method_id`, `xj_get_field_id`, `xj_get_static_field_id` |
| calls (A-variants; no varargs cross) | instance: `xj_call_int_method`(+`_i`/`_ii`/`_s`), `xj_call_boolean_method`, `xj_call_long_method`, `xj_call_double_bits_method`(+`_d`/`_i`), `xj_call_float_bits_method`, `xj_call_object_method`, `xj_call_void_method`; static: `xj_call_static_int_method`(+`_i`/`_s`), `xj_call_static_boolean_method`, `xj_call_static_long_method`, `xj_call_static_double_bits_method`, `xj_call_static_object_method`, `xj_call_static_void_method` |
| fields | `xj_get_int_field`, `xj_get_long_field`, `xj_get_double_bits_field`, `xj_get_object_field`, `xj_set_int_field`, `xj_set_long_field`, `xj_set_object_field`, `xj_get_static_int_field`, `xj_get_static_long_field`, `xj_get_static_object_field` |
| strings (UTF-8) | `xj_new_string_utf`, `xj_string_utf_length`, `xj_string_read_utf8`, `xj_string_buf_ptr`, `xj_string_buf_len` |
| arrays (int32 slots) | `xj_array_length`, `xj_new_int_array`, `xj_new_byte_array`, `xj_get_int_array_region`, `xj_set_int_array_region`, `xj_int_slot_set`, `xj_int_slot_get` |
| android/bitmap.h | `xj_bitmap_get_info`, `xj_bitmap_info_width/height/stride/format/flags/valid`, `xj_bitmap_get_data_space`, `xj_bitmap_lock_pixels`, `xj_bitmap_unlock_pixels`, `xj_bitmap_write_pixel`, `xj_bitmap_read_pixel`, `xj_bitmap_is_hardware`, `xj_bitmap_get_hardware_buffer`, `xj_bitmap_compress_owned`, `xj_bitmap_compressed_len`, `xj_bitmap_compressed_ptr`, `xj_bitmap_compressed_byte` |

Counts: **97** XIOM-facing C helpers == 97 `extern` declarations in
`src/jni.xi`; the module exposes **90** `pub fn` wrappers, **46**
`pub const`, **13** `pub type`.  Plus **9 probe-only diagnostics**
(`xj_abi_*`, below) exported by the same TU.

Rejected-by-measurement notes (header truth over task shorthand):

- `AndroidBitmap_getPixels` does NOT exist in r27b `android/bitmap.h`
  (it was a pre-NDK inline; `getInfo` + `lockPixels` is the lock route,
  which is what `getPixels` did).  The declared read path is
  `xj_bitmap_read_pixel` (lock + stride-walk + unlock, address stays
  C-side).
- `AImageDecoder_*` (34 exports of libjnigraphics.so on API 35) belongs
  to `android/imagedecoder.h` -- a different head, not A11.
- `AFileDescriptor_*` (libnativehelper.so) is not `jni.h`; the declared
  libnativehelper set is the three VM entry points `jni.h` names as
  "the only symbols exported for JNI by the VM".

## Declared export set (runtime-loaded, 9 symbols)

`libjnigraphics.so`: `AndroidBitmap_getInfo`, `AndroidBitmap_getDataSpace`,
`AndroidBitmap_lockPixels`, `AndroidBitmap_unlockPixels`,
`AndroidBitmap_compress`, `AndroidBitmap_getHardwareBuffer` (6).
`libnativehelper.so`: `JNI_GetDefaultJavaVMInitArgs`, `JNI_CreateJavaVM`,
`JNI_GetCreatedJavaVMs` (3, API 31+ public library).

Classification (the suite maps it to markers):

- both sonames absent -> `JNI_LOAD_ABSENT` -> **SKIP** (CI stays green);
- a partial pair (one soname missing, e.g. below API 31) -> also
  `JNI_LOAD_ABSENT` with the absent soname(s) in the message --
  present-but-broken is only diagnosed when both load;
- both load but any declared export unresolved -> `JNI_LOAD_ABI` ->
  **FAIL** (never a silent SKIP).

## Handle + memory discipline (B-series)

- handles (`JNIEnv`, `JavaVM`, `jobject`/`jclass`/`jstring`/`jarray`,
  `jmethodID`, `jfieldID`) cross as **`Int`** (C side `int64`); the
  pointer casts live C-side only (B-25: `Int as *UInt8` is not
  value-preserving; never do it on the XIOM side).
- **JNI C mapping**: an env/vm handle is a pointer to the
  interface-holder struct whose FIRST WORD is the table pointer (what
  `(*env)->FindClass(env, ...)` reads); the bridge dereferences once and
  passes the handle itself as the first table argument.
- **fp values never cross** (B-12): double/float returns cross as
  IEEE-754 bit patterns (`Int`); the suite/probes pin exact bit values
  (e.g. `1.5 -> 0x3FF8000000000000`).  Decoding helpers are deferred
  until the B-29 big-int bit-op defect is fixed (decode needs ops on
  >= 2^31 values); until then callers compare/re-emit bit patterns.
- **chars and pixel addresses stay C-side** (B-24/B-25): UTF-8 copies
  land in a bridge-owned 4 KiB slot (`string_buf`, byte-indexed reads
  via `string_read_utf8` + `Str::from_c_str`); the `AndroidBitmapInfo`
  readback lands in a bridge-owned info slot (`bitmap_info` accessors);
  array traffic lands in 64 bridge-owned int32 slots; compressed output
  lands in a bridge-owned 16 KiB slot.  No pointer arithmetic in the
  module.
- B-29 hygiene: no bitwise ops in `src/jni.xi`; flags like
  `ANDROID_BITMAP_FLAGS_IS_HARDWARE` (2^31) are compared by value only
  and the hardware mask test runs C-side (`xj_bitmap_is_hardware`).

## null-safety (every helper)

0-env / 0-object / 0-vm inputs produce **typed error text + a
documented sentinel**, never a crash:

- handle-returning helpers -> `0` (failed; `jni_error()` says why);
- int32 status/flag helpers -> `-1`;
- `xj_bitmap_get_data_space` -> `INT32_MIN` (`ADATASPACE_*` are >= 0);
- scalar-returning calls (`xj_call_*`) return the platform value and
  report failure through the error text: `jni_error()` is EMPTY after a
  successful call, and the XIOM wrappers map a non-empty error to
  `Err(JniProbeError)`.

A non-null-but-garbage handle is outside the consumer contract (no
validation is possible without a crash); only the consumer's own
JNI_OnLoad-supplied handles are valid inputs.

## Consumer contract (the exact harness needed for a live env)

1. the app's `JNI_OnLoad(JavaVM* vm, void* reserved)` passes `vm`
   (as `Int`) to `vm_get_env` (or `vm_attach_current` on a fresh
   thread); the returned `JniEnv` handle feeds every env-taking helper;
2. the app's own native exports/methods use the `JNIEnv*` the VM gives
   them (e.g. `runProbe` in the probe) -- also passed as `Int`;
3. `register_native` takes the consumer's JNIEXPORT function address
   (`Int`) and performs `RegisterNatives` with a one-entry
   `JNINativeMethod` (shape: `{name, signature, fn_ptr}`);
4. a plain shell process cannot own an env (no Java host) -- that case
   is diagnosed (`JNI_GetCreatedJavaVMs` -> count 0 -> typed error), and
   the on-device evidence uses an `app_process` dex jar whose
   `System.load` triggers `JNI_OnLoad`
   (`docs/repro/` -- the exact working recipe).

## Bridge-only diagnostics (not module surface)

`xj_abi_sizeof_table`, `xj_abi_sizeof_value`,
`xj_abi_sizeof_native_method`, `xj_abi_sizeof_bitmap_info`,
`xj_abi_sizeof_invoke`, `xj_abi_offset(0..55)`,
`xj_abi_invoke_offset(0..2)`, `xj_abi_bitmap_info_offset(0..4)`,
`xj_abi_native_method_offset(0..2)` -- numeric offsets/sizes of the
self-declared layout so `jni_head_probe.c` can gate EVERY member the
bridge touches against the real header's `offsetof` on-device (all 56
table offsets + 3 invoke + 5 bitmap-info + 3 native-method offsets
match on the API-36 emulator; the probe also `_Static_assert`s the
header side and the full 233-slot `sizeof`).

## Single-threaded consumer contract

Bridge-owned slots (string buffer, int slots, bitmap info slot, compress
buffer, manual lock state) are process-global, as in the sibling bridge
`xiom.android`.  The env/vm calls themselves are thread-agnostic (each
call passes its handle), and `vm_attach_current`/`vm_detach_current`
cover worker threads (proven by the probe's pthread leg).

## Files

- `src/jni.xi` -- the module (types + constants + wrappers).
- `src/jni_bridge.c` -- the C bridge (loader, pinned tables, helpers).
- `port.args.json` -- `--c-source` wiring + 240 s link timeout.
- `tests/test_conformance.xi` -- 89-check suite (SKIP-safe; null-safety
  battery over every family; runs green on Windows + on-device).
- `docs/repro/` -- shell + app probes, build-and-run driver, recorded
  evidence.
