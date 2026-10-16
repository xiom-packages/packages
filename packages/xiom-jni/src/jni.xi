// XIOM -- xiom.jni: Android JNI seam (NDK r27b A11 head).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// DESIGN: jni.h is an INTERFACE, not a flat export map (SPEC.md carries
// the subset strategy): the JNIEnv/JavaVM function tables only exist
// inside a live Java host, so this package is the seam -- the CONSUMER
// APP supplies the JavaVM*/JNIEnv* it obtains in its JNI_OnLoad as Int
// handles and the C bridge (`src/jni_bridge.c`, compiled via
// `--c-source`; see port.args.json) performs every table call.  No
// callback bridging is needed; JNI_OnLoad stays the consumer's.
//
// The libjnigraphics.so AndroidBitmap_* cluster (android/bitmap.h) runs
// through the same bridge with a runtime multi-soname loader
// (libjnigraphics.so + libnativehelper.so), SKIP-safe on Windows:
//
//   JNI_LOAD_ABSENT -> SKIP  (runtime pair missing; CI stays green)
//   JNI_LOAD_ABI    -> FAIL  (present but exports broken; never silent)
//
// Discipline: handles cross as Int (B-25: never cast Int to a pointer
// here); fp payloads cross as IEEE-754 bit patterns (B-12/B-29-safe);
// string chars and pixel addresses stay C-side in bridge-owned slots
// (B-24-safe reads); every helper is null-safe (0-env/0-object ->
// typed error, no crash).  See SPEC.md for the exact consumer contract.

module xiom.jni

extern "C" {
  fn xj_load_named(bitmap_soname: *UInt8, nativehelper_soname: *UInt8) -> Int32;
  fn xj_load() -> Int32;
  fn xj_error() -> *UInt8;
  fn xj_abi_missing_count() -> Int32;
  fn xj_abi_missing() -> *UInt8;
  fn xj_export_count() -> Int32;
  fn xj_unload();
  fn xj_vm_get_env(vm: Int64, version: Int32) -> Int64;
  fn xj_vm_attach_current(vm: Int64) -> Int64;
  fn xj_vm_detach_current(vm: Int64) -> Int32;
  fn xj_vm_from_created(index: Int32) -> Int64;
  fn xj_env_get_java_vm(env: Int64) -> Int64;
  fn xj_env_version(env: Int64) -> Int32;
  fn xj_find_class(env: Int64, name: *UInt8) -> Int64;
  fn xj_get_object_class(env: Int64, obj: Int64) -> Int64;
  fn xj_get_superclass(env: Int64, clazz: Int64) -> Int64;
  fn xj_is_assignable_from(env: Int64, c1: Int64, c2: Int64) -> Int32;
  fn xj_is_instance_of(env: Int64, obj: Int64, clazz: Int64) -> Int32;
  fn xj_new_global_ref(env: Int64, obj: Int64) -> Int64;
  fn xj_delete_global_ref(env: Int64, ref: Int64) -> Int32;
  fn xj_delete_local_ref(env: Int64, ref: Int64) -> Int32;
  fn xj_new_local_ref(env: Int64, ref: Int64) -> Int64;
  fn xj_push_local_frame(env: Int64, capacity: Int32) -> Int32;
  fn xj_pop_local_frame(env: Int64, result: Int64) -> Int64;
  fn xj_ensure_local_capacity(env: Int64, capacity: Int32) -> Int32;
  fn xj_exception_check(env: Int64) -> Int32;
  fn xj_exception_occurred(env: Int64) -> Int64;
  fn xj_exception_describe(env: Int64);
  fn xj_exception_clear(env: Int64);
  fn xj_throw_new(env: Int64, clazz: Int64, msg: *UInt8) -> Int32;
  fn xj_throw(env: Int64, throwable: Int64) -> Int32;
  fn xj_register_native(env: Int64, clazz: Int64, name: *UInt8, signature: *UInt8, fn_ptr: Int64) -> Int32;
  fn xj_unregister_natives(env: Int64, clazz: Int64) -> Int32;
  fn xj_get_method_id(env: Int64, clazz: Int64, name: *UInt8, sig: *UInt8) -> Int64;
  fn xj_get_static_method_id(env: Int64, clazz: Int64, name: *UInt8, sig: *UInt8) -> Int64;
  fn xj_get_field_id(env: Int64, clazz: Int64, name: *UInt8, sig: *UInt8) -> Int64;
  fn xj_get_static_field_id(env: Int64, clazz: Int64, name: *UInt8, sig: *UInt8) -> Int64;
  fn xj_call_int_method(env: Int64, obj: Int64, mid: Int64) -> Int32;
  fn xj_call_int_method_i(env: Int64, obj: Int64, mid: Int64, a: Int32) -> Int32;
  fn xj_call_int_method_ii(env: Int64, obj: Int64, mid: Int64, a: Int32, b: Int32) -> Int32;
  fn xj_call_int_method_s(env: Int64, obj: Int64, mid: Int64, str: Int64) -> Int32;
  fn xj_call_boolean_method(env: Int64, obj: Int64, mid: Int64) -> Int32;
  fn xj_call_long_method(env: Int64, obj: Int64, mid: Int64) -> Int64;
  fn xj_call_double_bits_method(env: Int64, obj: Int64, mid: Int64) -> Int64;
  fn xj_call_double_bits_method_d(env: Int64, obj: Int64, mid: Int64, arg_bits: Int64) -> Int64;
  fn xj_call_double_bits_method_i(env: Int64, obj: Int64, mid: Int64, a: Int32) -> Int64;
  fn xj_call_float_bits_method(env: Int64, obj: Int64, mid: Int64) -> Int64;
  fn xj_call_object_method(env: Int64, obj: Int64, mid: Int64) -> Int64;
  fn xj_call_void_method(env: Int64, obj: Int64, mid: Int64) -> Int32;
  fn xj_call_static_int_method(env: Int64, clazz: Int64, mid: Int64) -> Int32;
  fn xj_call_static_int_method_i(env: Int64, clazz: Int64, mid: Int64, a: Int32) -> Int32;
  fn xj_call_static_int_method_s(env: Int64, clazz: Int64, mid: Int64, str: Int64) -> Int32;
  fn xj_call_static_boolean_method(env: Int64, clazz: Int64, mid: Int64) -> Int32;
  fn xj_call_static_long_method(env: Int64, clazz: Int64, mid: Int64) -> Int64;
  fn xj_call_static_double_bits_method(env: Int64, clazz: Int64, mid: Int64) -> Int64;
  fn xj_call_static_object_method(env: Int64, clazz: Int64, mid: Int64) -> Int64;
  fn xj_call_static_void_method(env: Int64, clazz: Int64, mid: Int64) -> Int32;
  fn xj_get_int_field(env: Int64, obj: Int64, fid: Int64) -> Int32;
  fn xj_get_long_field(env: Int64, obj: Int64, fid: Int64) -> Int64;
  fn xj_get_double_bits_field(env: Int64, obj: Int64, fid: Int64) -> Int64;
  fn xj_get_object_field(env: Int64, obj: Int64, fid: Int64) -> Int64;
  fn xj_set_int_field(env: Int64, obj: Int64, fid: Int64, v: Int32) -> Int32;
  fn xj_set_long_field(env: Int64, obj: Int64, fid: Int64, v: Int64) -> Int32;
  fn xj_set_object_field(env: Int64, obj: Int64, fid: Int64, v: Int64) -> Int32;
  fn xj_get_static_int_field(env: Int64, clazz: Int64, fid: Int64) -> Int32;
  fn xj_get_static_long_field(env: Int64, clazz: Int64, fid: Int64) -> Int64;
  fn xj_get_static_object_field(env: Int64, clazz: Int64, fid: Int64) -> Int64;
  fn xj_new_string_utf(env: Int64, utf8: *UInt8) -> Int64;
  fn xj_string_utf_length(env: Int64, str: Int64) -> Int32;
  fn xj_string_read_utf8(env: Int64, str: Int64, max_len: Int32) -> Int32;
  fn xj_string_buf_ptr() -> *UInt8;
  fn xj_string_buf_len() -> Int32;
  fn xj_array_length(env: Int64, arr: Int64) -> Int32;
  fn xj_new_int_array(env: Int64, len: Int32) -> Int64;
  fn xj_new_byte_array(env: Int64, len: Int32) -> Int64;
  fn xj_get_int_array_region(env: Int64, arr: Int64, start: Int32, len: Int32) -> Int32;
  fn xj_set_int_array_region(env: Int64, arr: Int64, start: Int32, len: Int32) -> Int32;
  fn xj_int_slot_set(index: Int32, value: Int32) -> Int32;
  fn xj_int_slot_get(index: Int32) -> Int32;
  fn xj_bitmap_get_info(env: Int64, bitmap: Int64) -> Int32;
  fn xj_bitmap_info_width() -> Int32;
  fn xj_bitmap_info_height() -> Int32;
  fn xj_bitmap_info_stride() -> Int32;
  fn xj_bitmap_info_format() -> Int32;
  fn xj_bitmap_info_flags() -> Int32;
  fn xj_bitmap_info_valid() -> Int32;
  fn xj_bitmap_get_data_space(env: Int64, bitmap: Int64) -> Int32;
  fn xj_bitmap_lock_pixels(env: Int64, bitmap: Int64) -> Int32;
  fn xj_bitmap_unlock_pixels(env: Int64, bitmap: Int64) -> Int32;
  fn xj_bitmap_write_pixel(env: Int64, bitmap: Int64, x: Int32, y: Int32, rgba: Int32) -> Int32;
  fn xj_bitmap_read_pixel(env: Int64, bitmap: Int64, x: Int32, y: Int32) -> Int64;
  fn xj_bitmap_is_hardware(env: Int64, bitmap: Int64) -> Int32;
  fn xj_bitmap_get_hardware_buffer(env: Int64, bitmap: Int64) -> Int64;
  fn xj_bitmap_compress_owned(env: Int64, bitmap: Int64, format: Int32, quality: Int32, max_bytes: Int32) -> Int32;
  fn xj_bitmap_compressed_len() -> Int32;
  fn xj_bitmap_compressed_ptr() -> *UInt8;
  fn xj_bitmap_compressed_byte(index: Int32) -> Int32;
}

// =========================================================================
// Identity and classification
// =========================================================================

pub const JNIGRAPHICS_SONAME: Str = "libjnigraphics.so";
pub const NATIVEHELPER_SONAME: Str = "libnativehelper.so";

// Probe outcome kinds.
pub const JNI_LOAD_ABSENT: Int = 0; // runtime pair missing -> SKIP
pub const JNI_LOAD_ABI: Int = 1;    // present but exports broken -> FAIL

// Error sentinels used by this module (documented in SPEC.md):
//   0         = failed handle-returning function (jni_error() says why)
//   -1        = failed int32 status/flag function
//   -2147483648 = failed xj_bitmap_get_data_space
// jni_error() is empty after a successful call.
pub const JNI_ERR_INT: Int = -1;
pub const JNI_ERR_DATASPACE: Int = -2147483648;

pub type JniProbeError = {
  kind: Int;
  message: Str;
}

pub type JniRuntime = {
  missing_exports: Int;
  missing: Str;
}

// =========================================================================
// Handles (Int-wrapped; never pointer-cast on this side -- B-25)
// =========================================================================

pub type JniEnv = {
  handle: Int;
}

pub type JavaVm = {
  handle: Int;
}

pub type JObject = {
  handle: Int;
}

pub type JClass = {
  handle: Int;
}

pub type JString = {
  handle: Int;
}

pub type JThrowable = {
  handle: Int;
}

pub type JMethodId = {
  handle: Int;
}

pub type JFieldId = {
  handle: Int;
}

pub type JArray = {
  handle: Int;
}

// JNINativeMethod shape (jni.h): name + signature + C function pointer.
// The fn_ptr is the address of the consumer's JNIEXPORT function, as Int.
pub type JniNativeMethod = {
  name: Str;
  signature: Str;
  fn_ptr: Int;
}

// =========================================================================
// Constants -- jni.h manifest macros
// =========================================================================

pub const JNI_VERSION_1_1: Int = 0x00010001;
pub const JNI_VERSION_1_2: Int = 0x00010002;
pub const JNI_VERSION_1_4: Int = 0x00010004;
pub const JNI_VERSION_1_6: Int = 0x00010006;

pub const JNI_FALSE: Int = 0;
pub const JNI_TRUE: Int = 1;

pub const JNI_OK: Int = 0;
pub const JNI_ERR: Int = -1;
pub const JNI_EDETACHED: Int = -2;
pub const JNI_EVERSION: Int = -3;
pub const JNI_ENOMEM: Int = -4;
pub const JNI_EEXIST: Int = -5;
pub const JNI_EINVAL: Int = -6;

pub const JNI_COMMIT: Int = 1;
pub const JNI_ABORT: Int = 2;

// jobjectRefType
pub const JNI_INVALID_REF_TYPE: Int = 0;
pub const JNI_LOCAL_REF_TYPE: Int = 1;
pub const JNI_GLOBAL_REF_TYPE: Int = 2;
pub const JNI_WEAK_GLOBAL_REF_TYPE: Int = 3;

// =========================================================================
// Constants -- android/bitmap.h
// =========================================================================

pub const ANDROID_BITMAP_RESULT_SUCCESS: Int = 0;
pub const ANDROID_BITMAP_RESULT_BAD_PARAMETER: Int = -1;
pub const ANDROID_BITMAP_RESULT_JNI_EXCEPTION: Int = -2;
pub const ANDROID_BITMAP_RESULT_ALLOCATION_FAILED: Int = -3;

pub const ANDROID_BITMAP_FORMAT_NONE: Int = 0;
pub const ANDROID_BITMAP_FORMAT_RGBA_8888: Int = 1;
pub const ANDROID_BITMAP_FORMAT_RGB_565: Int = 4;
pub const ANDROID_BITMAP_FORMAT_RGBA_4444: Int = 7;
pub const ANDROID_BITMAP_FORMAT_A_8: Int = 8;
pub const ANDROID_BITMAP_FORMAT_RGBA_F16: Int = 9;
pub const ANDROID_BITMAP_FORMAT_RGBA_1010102: Int = 10;

pub const ANDROID_BITMAP_FLAGS_ALPHA_PREMUL: Int = 0;
pub const ANDROID_BITMAP_FLAGS_ALPHA_OPAQUE: Int = 1;
pub const ANDROID_BITMAP_FLAGS_ALPHA_UNPREMUL: Int = 2;
pub const ANDROID_BITMAP_FLAGS_ALPHA_MASK: Int = 3;
pub const ANDROID_BITMAP_FLAGS_ALPHA_SHIFT: Int = 0;
// 1 << 31: no B-29-unsafe ops on this value here; test with == or -
pub const ANDROID_BITMAP_FLAGS_IS_HARDWARE: Int = 2147483648;

pub const ANDROID_BITMAP_COMPRESS_FORMAT_JPEG: Int = 0;
pub const ANDROID_BITMAP_COMPRESS_FORMAT_PNG: Int = 1;
pub const ANDROID_BITMAP_COMPRESS_FORMAT_WEBP_LOSSY: Int = 3;
pub const ANDROID_BITMAP_COMPRESS_FORMAT_WEBP_LOSSLESS: Int = 4;

// =========================================================================
// Probe API (the SKIP-safe first gate)
// =========================================================================

/// Probe an explicitly named library pair.  Tests use a bogus pair to
/// exercise the ABSENT/SKIP classification deterministically on every
/// host.  Complexity: O(load + export set).
pub fn jni_probe_named(bitmap_soname: Str, nativehelper_soname: Str) -> Result[JniRuntime, JniProbeError]
  requires: bitmap_soname.len() > 0
  requires: nativehelper_soname.len() > 0
{
  let rc = unsafe { xj_load_named(bitmap_soname.c_str(), nativehelper_soname.c_str()) as Int };
  if rc != 0 {
    let msg = unsafe { Str::from_c_str(xj_error()) };
    if rc == 1 {
      return Err(JniProbeError{ kind: JNI_LOAD_ABSENT; message: msg });
    }
    return Err(JniProbeError{ kind: JNI_LOAD_ABI; message: msg });
  }
  let missing_count = unsafe { xj_abi_missing_count() as Int };
  let missing = unsafe { Str::from_c_str(xj_abi_missing()) };
  return Ok(JniRuntime{ missing_exports: missing_count, missing: missing });
}

/// Probe the default runtime pair (libjnigraphics.so +
/// libnativehelper.so).  On Android these are the platform libraries; on
/// Windows both are absent -> JNI_LOAD_ABSENT (SKIP).
/// Complexity: O(load + export set).
pub fn jni_probe() -> Result[JniRuntime, JniProbeError]
  requires: true
{
  return jni_probe_named(JNIGRAPHICS_SONAME, NATIVEHELPER_SONAME);
}

/// The last bridge error (empty when the last helper call succeeded).
/// Complexity: O(1).
pub fn jni_error() -> Str
  requires: true
{
  unsafe { return Str::from_c_str(xj_error()); }
}

/// The declared export-set size of this bridge (9: android/bitmap.h's 6
/// AndroidBitmap_* + jni.h's 3 VM entry points).  Drift guard for the
/// suite.  Complexity: O(1).
pub fn jni_export_count() -> Int
  requires: true
{
  unsafe { return xj_export_count() as Int; }
}

/// Release any runtime handles held by the bridge.  Safe when nothing is
/// loaded.  Complexity: O(1).
pub fn jni_unload()
  requires: true
{
  unsafe { xj_unload(); }
}

// =========================================================================
// VM / env seam (consumer-supplied handles)
// =========================================================================

/// Obtain the current thread's env from a consumer-supplied JavaVM*
/// (as Int; the app receives it in JNI_OnLoad).  Use
/// `vm_attach_current` when the thread is not attached
/// (JNI_EDETACHED from the recorded error).
/// Complexity: O(1).
pub fn vm_get_env(vm: &JavaVm, version: Int) -> Result[JniEnv, JniProbeError]
  requires: version > 0
{
  let h = unsafe { xj_vm_get_env(vm.handle as Int64, version as Int32) as Int };
  if h == 0 {
    return Err(JniProbeError{ kind: JNI_LOAD_ABI; message: jni_error() });
  }
  return Ok(JniEnv{ handle: h });
}

/// Attach the current native thread to the VM (AttachCurrentThread with
/// JavaVMAttachArgs version JNI_VERSION_1_6) and return its env.  Pair
/// with `vm_detach_current` before the thread exits.
/// Complexity: O(1).
pub fn vm_attach_current(vm: &JavaVm) -> Result[JniEnv, JniProbeError]
  requires: true
{
  let h = unsafe { xj_vm_attach_current(vm.handle as Int64) as Int };
  if h == 0 {
    return Err(JniProbeError{ kind: JNI_LOAD_ABI; message: jni_error() });
  }
  return Ok(JniEnv{ handle: h });
}

/// Detach the current thread from the VM.
/// Complexity: O(1).
pub fn vm_detach_current(vm: &JavaVm) -> Bool
  requires: true
{
  let rc = unsafe { xj_vm_detach_current(vm.handle as Int64) as Int };
  return rc == 0;
}

/// The created JavaVM at `index` through JNI_GetCreatedJavaVMs
/// (libnativehelper.so; requires a loaded runtime and a live VM in the
/// process -- the app_process probe's JNI_OnLoad case).
/// Complexity: O(1).
pub fn vm_from_created(index: Int) -> Result[JavaVm, JniProbeError]
  requires: index >= 0
{
  let h = unsafe { xj_vm_from_created(index as Int32) as Int };
  if h == 0 {
    return Err(JniProbeError{ kind: JNI_LOAD_ABI; message: jni_error() });
  }
  return Ok(JavaVm{ handle: h });
}

/// The JavaVM the env belongs to (GetJavaVM).
/// Complexity: O(1).
pub fn env_get_java_vm(env: &JniEnv) -> Result[JavaVm, JniProbeError]
  requires: true
{
  let h = unsafe { xj_env_get_java_vm(env.handle as Int64) as Int };
  if h == 0 {
    return Err(JniProbeError{ kind: JNI_LOAD_ABI; message: jni_error() });
  }
  return Ok(JavaVm{ handle: h });
}

/// The env's JNI version (GetVersion; e.g. JNI_VERSION_1_6).
/// -1 on error (see jni_error).  Complexity: O(1).
pub fn env_version(env: &JniEnv) -> Int
  requires: true
{
  unsafe { return xj_env_version(env.handle as Int64) as Int; }
}

// =========================================================================
// Classes, refs, exceptions
// =========================================================================

/// FindClass("java/lang/String"-style internal name).
/// Complexity: O(class lookup).
pub fn find_class(env: &JniEnv, name: Str) -> Result[JClass, JniProbeError]
  requires: name.len() > 0
{
  let h = unsafe { xj_find_class(env.handle as Int64, name.c_str()) as Int };
  if h == 0 {
    return Err(JniProbeError{ kind: JNI_LOAD_ABI; message: jni_error() });
  }
  return Ok(JClass{ handle: h });
}

/// GetObjectClass of a reference.  Complexity: O(1).
pub fn get_object_class(env: &JniEnv, obj: &JObject) -> Result[JClass, JniProbeError]
  requires: true
{
  let h = unsafe { xj_get_object_class(env.handle as Int64, obj.handle as Int64) as Int };
  if h == 0 {
    return Err(JniProbeError{ kind: JNI_LOAD_ABI; message: jni_error() });
  }
  return Ok(JClass{ handle: h });
}

/// GetSuperclass.  Complexity: O(1).
pub fn get_superclass(env: &JniEnv, clazz: &JClass) -> Result[JClass, JniProbeError]
  requires: true
{
  let h = unsafe { xj_get_superclass(env.handle as Int64, clazz.handle as Int64) as Int };
  if h == 0 {
    return Err(JniProbeError{ kind: JNI_LOAD_ABI; message: jni_error() });
  }
  return Ok(JClass{ handle: h });
}

/// IsAssignableFrom(clazz1, clazz2).  -1 on error.
/// Complexity: O(1).
pub fn is_assignable_from(env: &JniEnv, c1: &JClass, c2: &JClass) -> Int
  requires: true
{
  unsafe { return xj_is_assignable_from(env.handle as Int64, c1.handle as Int64, c2.handle as Int64) as Int; }
}

/// IsInstanceOf(obj, clazz).  -1 on error.
/// Complexity: O(1).
pub fn is_instance_of(env: &JniEnv, obj: &JObject, clazz: &JClass) -> Int
  requires: true
{
  unsafe { return xj_is_instance_of(env.handle as Int64, obj.handle as Int64, clazz.handle as Int64) as Int; }
}

/// Promote a reference to a global ref.
/// Complexity: O(1).
pub fn new_global_ref(env: &JniEnv, obj: &JObject) -> Result[JObject, JniProbeError]
  requires: true
{
  let h = unsafe { xj_new_global_ref(env.handle as Int64, obj.handle as Int64) as Int };
  if h == 0 {
    return Err(JniProbeError{ kind: JNI_LOAD_ABI; message: jni_error() });
  }
  return Ok(JObject{ handle: h });
}

/// Delete a global ref.  Complexity: O(1).
pub fn delete_global_ref(env: &JniEnv, ref: &JObject) -> Bool
  requires: true
{
  let rc = unsafe { xj_delete_global_ref(env.handle as Int64, ref.handle as Int64) as Int };
  return rc == 0;
}

/// Delete a local ref.  Complexity: O(1).
pub fn delete_local_ref(env: &JniEnv, ref: &JObject) -> Bool
  requires: true
{
  let rc = unsafe { xj_delete_local_ref(env.handle as Int64, ref.handle as Int64) as Int };
  return rc == 0;
}

/// Create a local ref from a (global) ref.
/// Complexity: O(1).
pub fn new_local_ref(env: &JniEnv, ref: &JObject) -> Result[JObject, JniProbeError]
  requires: true
{
  let h = unsafe { xj_new_local_ref(env.handle as Int64, ref.handle as Int64) as Int };
  if h == 0 {
    return Err(JniProbeError{ kind: JNI_LOAD_ABI; message: jni_error() });
  }
  return Ok(JObject{ handle: h });
}

/// PushLocalFrame(capacity).  Complexity: O(1).
pub fn push_local_frame(env: &JniEnv, capacity: Int) -> Bool
  requires: capacity >= 0
{
  let rc = unsafe { xj_push_local_frame(env.handle as Int64, capacity as Int32) as Int };
  return rc == 0;
}

/// PopLocalFrame(result-or-0); returns the popped result handle
/// (0 when none/error -- see jni_error).  Complexity: O(1).
pub fn pop_local_frame(env: &JniEnv, result: &JObject) -> Int
  requires: true
{
  unsafe { return xj_pop_local_frame(env.handle as Int64, result.handle as Int64) as Int; }
}

/// EnsureLocalCapacity(capacity).  Complexity: O(1).
pub fn ensure_local_capacity(env: &JniEnv, capacity: Int) -> Bool
  requires: capacity >= 0
{
  let rc = unsafe { xj_ensure_local_capacity(env.handle as Int64, capacity as Int32) as Int };
  return rc == 0;
}

/// 1 = a JNI exception is pending; 0 = none; -1 = error.
/// Complexity: O(1).
pub fn exception_check(env: &JniEnv) -> Int
  requires: true
{
  unsafe { return xj_exception_check(env.handle as Int64) as Int; }
}

/// The pending throwable handle (0 = none; error text when the env was
/// invalid).  Complexity: O(1).
pub fn exception_occurred(env: &JniEnv) -> Int
  requires: true
{
  unsafe { return xj_exception_occurred(env.handle as Int64) as Int; }
}

/// Print the pending exception through the VM's ExceptionDescribe (goes
/// to the logcat in an Android process).  Complexity: O(1).
pub fn exception_describe(env: &JniEnv)
  requires: true
{
  unsafe { xj_exception_describe(env.handle as Int64); }
}

/// Clear the pending exception.  Complexity: O(1).
pub fn exception_clear(env: &JniEnv)
  requires: true
{
  unsafe { xj_exception_clear(env.handle as Int64); }
}

/// ThrowNew(clazz, message).  Complexity: O(1).
pub fn throw_new(env: &JniEnv, clazz: &JClass, msg: Str) -> Bool
  requires: true
{
  let rc = unsafe { xj_throw_new(env.handle as Int64, clazz.handle as Int64, msg.c_str()) as Int };
  return rc == 0;
}

/// Throw(throwable).  Complexity: O(1).
pub fn throw(env: &JniEnv, throwable: &JThrowable) -> Bool
  requires: true
{
  let rc = unsafe { xj_throw(env.handle as Int64, throwable.handle as Int64) as Int };
  return rc == 0;
}

/// RegisterNatives with ONE JNINativeMethod built from the given shape
/// (name, signature, fn_ptr-as-Int).  The consumer supplies the address
/// of its JNIEXPORT function (e.g. from its own GetProcAddress).
/// Complexity: O(1).
pub fn register_native(env: &JniEnv, clazz: &JClass, method: &JniNativeMethod) -> Bool
  requires: method.name.len() > 0
  requires: method.signature.len() > 0
{
  let rc = unsafe {
    xj_register_native(env.handle as Int64, clazz.handle as Int64, method.name.c_str(), method.signature.c_str(), method.fn_ptr as Int64) as Int
  };
  return rc == 0;
}

/// UnregisterNatives(clazz).  Complexity: O(1).
pub fn unregister_natives(env: &JniEnv, clazz: &JClass) -> Bool
  requires: true
{
  let rc = unsafe { xj_unregister_natives(env.handle as Int64, clazz.handle as Int64) as Int };
  return rc == 0;
}

// =========================================================================
// IDs
// =========================================================================

/// GetMethodID(clazz, name, sig).
/// Complexity: O(lookup).
pub fn get_method_id(env: &JniEnv, clazz: &JClass, name: Str, sig: Str) -> Result[JMethodId, JniProbeError]
  requires: name.len() > 0
  requires: sig.len() > 0
{
  let h = unsafe { xj_get_method_id(env.handle as Int64, clazz.handle as Int64, name.c_str(), sig.c_str()) as Int };
  if h == 0 {
    return Err(JniProbeError{ kind: JNI_LOAD_ABI; message: jni_error() });
  }
  return Ok(JMethodId{ handle: h });
}

/// GetStaticMethodID(clazz, name, sig).
/// Complexity: O(lookup).
pub fn get_static_method_id(env: &JniEnv, clazz: &JClass, name: Str, sig: Str) -> Result[JMethodId, JniProbeError]
  requires: name.len() > 0
  requires: sig.len() > 0
{
  let h = unsafe { xj_get_static_method_id(env.handle as Int64, clazz.handle as Int64, name.c_str(), sig.c_str()) as Int };
  if h == 0 {
    return Err(JniProbeError{ kind: JNI_LOAD_ABI; message: jni_error() });
  }
  return Ok(JMethodId{ handle: h });
}

/// GetFieldID(clazz, name, sig).
/// Complexity: O(lookup).
pub fn get_field_id(env: &JniEnv, clazz: &JClass, name: Str, sig: Str) -> Result[JFieldId, JniProbeError]
  requires: name.len() > 0
  requires: sig.len() > 0
{
  let h = unsafe { xj_get_field_id(env.handle as Int64, clazz.handle as Int64, name.c_str(), sig.c_str()) as Int };
  if h == 0 {
    return Err(JniProbeError{ kind: JNI_LOAD_ABI; message: jni_error() });
  }
  return Ok(JFieldId{ handle: h });
}

/// GetStaticFieldID(clazz, name, sig).
/// Complexity: O(lookup).
pub fn get_static_field_id(env: &JniEnv, clazz: &JClass, name: Str, sig: Str) -> Result[JFieldId, JniProbeError]
  requires: name.len() > 0
  requires: sig.len() > 0
{
  let h = unsafe { xj_get_static_field_id(env.handle as Int64, clazz.handle as Int64, name.c_str(), sig.c_str()) as Int };
  if h == 0 {
    return Err(JniProbeError{ kind: JNI_LOAD_ABI; message: jni_error() });
  }
  return Ok(JFieldId{ handle: h });
}

// =========================================================================
// Calls (A-variants; args as typed slots; fp returns as bit patterns)
// =========================================================================

/// CallIntMethod(0 args).  Err when the helper recorded an error
/// (null handles / pending exception).
/// Complexity: O(call).
pub fn call_int_method(env: &JniEnv, obj: &JObject, mid: &JMethodId) -> Result[Int, JniProbeError]
  requires: true
{
  let v = unsafe { xj_call_int_method(env.handle as Int64, obj.handle as Int64, mid.handle as Int64) as Int };
  let e = jni_error();
  if e.len() > 0 { return Err(JniProbeError{ kind: JNI_LOAD_ABI; message: e }); }
  return Ok(v);
}

/// CallIntMethod(1 int arg).  Complexity: O(call).
pub fn call_int_method_i(env: &JniEnv, obj: &JObject, mid: &JMethodId, a: Int) -> Result[Int, JniProbeError]
  requires: true
{
  let v = unsafe { xj_call_int_method_i(env.handle as Int64, obj.handle as Int64, mid.handle as Int64, a as Int32) as Int };
  let e = jni_error();
  if e.len() > 0 { return Err(JniProbeError{ kind: JNI_LOAD_ABI; message: e }); }
  return Ok(v);
}

/// CallIntMethod(2 int args).  Complexity: O(call).
pub fn call_int_method_ii(env: &JniEnv, obj: &JObject, mid: &JMethodId, a: Int, b: Int) -> Result[Int, JniProbeError]
  requires: true
{
  let v = unsafe { xj_call_int_method_ii(env.handle as Int64, obj.handle as Int64, mid.handle as Int64, a as Int32, b as Int32) as Int };
  let e = jni_error();
  if e.len() > 0 { return Err(JniProbeError{ kind: JNI_LOAD_ABI; message: e }); }
  return Ok(v);
}

/// CallIntMethod(1 jstring arg).  Complexity: O(call).
pub fn call_int_method_s(env: &JniEnv, obj: &JObject, mid: &JMethodId, str: &JString) -> Result[Int, JniProbeError]
  requires: true
{
  let v = unsafe { xj_call_int_method_s(env.handle as Int64, obj.handle as Int64, mid.handle as Int64, str.handle as Int64) as Int };
  let e = jni_error();
  if e.len() > 0 { return Err(JniProbeError{ kind: JNI_LOAD_ABI; message: e }); }
  return Ok(v);
}

/// CallBooleanMethod(0 args).  Complexity: O(call).
pub fn call_boolean_method(env: &JniEnv, obj: &JObject, mid: &JMethodId) -> Result[Bool, JniProbeError]
  requires: true
{
  let v = unsafe { xj_call_boolean_method(env.handle as Int64, obj.handle as Int64, mid.handle as Int64) as Int };
  if v < 0 {
    return Err(JniProbeError{ kind: JNI_LOAD_ABI; message: jni_error() });
  }
  return Ok(v == 1);
}

/// CallLongMethod(0 args).  Complexity: O(call).
pub fn call_long_method(env: &JniEnv, obj: &JObject, mid: &JMethodId) -> Result[Int, JniProbeError]
  requires: true
{
  let v = unsafe { xj_call_long_method(env.handle as Int64, obj.handle as Int64, mid.handle as Int64) as Int };
  let e = jni_error();
  if e.len() > 0 { return Err(JniProbeError{ kind: JNI_LOAD_ABI; message: e }); }
  return Ok(v);
}

/// CallDoubleMethod(0 args) as the IEEE-754 binary64 BIT PATTERN (B-12
/// discipline: an fp value never crosses).  Complexity: O(call).
pub fn call_double_bits_method(env: &JniEnv, obj: &JObject, mid: &JMethodId) -> Result[Int, JniProbeError]
  requires: true
{
  let v = unsafe { xj_call_double_bits_method(env.handle as Int64, obj.handle as Int64, mid.handle as Int64) as Int };
  let e = jni_error();
  if e.len() > 0 { return Err(JniProbeError{ kind: JNI_LOAD_ABI; message: e }); }
  return Ok(v);
}

/// CallDoubleMethod(1 double arg, passed as binary64 bits) -> binary64
/// bits.  Complexity: O(call).
pub fn call_double_bits_method_d(env: &JniEnv, obj: &JObject, mid: &JMethodId, arg_bits: Int) -> Result[Int, JniProbeError]
  requires: true
{
  let v = unsafe { xj_call_double_bits_method_d(env.handle as Int64, obj.handle as Int64, mid.handle as Int64, arg_bits as Int64) as Int };
  let e = jni_error();
  if e.len() > 0 { return Err(JniProbeError{ kind: JNI_LOAD_ABI; message: e }); }
  return Ok(v);
}

/// CallDoubleMethod(1 int arg) -> binary64 bits.  Complexity: O(call).
pub fn call_double_bits_method_i(env: &JniEnv, obj: &JObject, mid: &JMethodId, a: Int) -> Result[Int, JniProbeError]
  requires: true
{
  let v = unsafe { xj_call_double_bits_method_i(env.handle as Int64, obj.handle as Int64, mid.handle as Int64, a as Int32) as Int };
  let e = jni_error();
  if e.len() > 0 { return Err(JniProbeError{ kind: JNI_LOAD_ABI; message: e }); }
  return Ok(v);
}

/// CallFloatMethod(0 args) as the IEEE-754 binary32 BIT PATTERN.
/// Complexity: O(call).
pub fn call_float_bits_method(env: &JniEnv, obj: &JObject, mid: &JMethodId) -> Result[Int, JniProbeError]
  requires: true
{
  let v = unsafe { xj_call_float_bits_method(env.handle as Int64, obj.handle as Int64, mid.handle as Int64) as Int };
  let e = jni_error();
  if e.len() > 0 { return Err(JniProbeError{ kind: JNI_LOAD_ABI; message: e }); }
  return Ok(v);
}

/// CallObjectMethod(0 args).  Complexity: O(call).
pub fn call_object_method(env: &JniEnv, obj: &JObject, mid: &JMethodId) -> Result[JObject, JniProbeError]
  requires: true
{
  let h = unsafe { xj_call_object_method(env.handle as Int64, obj.handle as Int64, mid.handle as Int64) as Int };
  if h == 0 {
    return Err(JniProbeError{ kind: JNI_LOAD_ABI; message: jni_error() });
  }
  return Ok(JObject{ handle: h });
}

/// CallVoidMethod(0 args).  Complexity: O(call).
pub fn call_void_method(env: &JniEnv, obj: &JObject, mid: &JMethodId) -> Bool
  requires: true
{
  let rc = unsafe { xj_call_void_method(env.handle as Int64, obj.handle as Int64, mid.handle as Int64) as Int };
  return rc == 0;
}

/// CallStaticIntMethod(0 args).  Complexity: O(call).
pub fn call_static_int_method(env: &JniEnv, clazz: &JClass, mid: &JMethodId) -> Result[Int, JniProbeError]
  requires: true
{
  let v = unsafe { xj_call_static_int_method(env.handle as Int64, clazz.handle as Int64, mid.handle as Int64) as Int };
  let e = jni_error();
  if e.len() > 0 { return Err(JniProbeError{ kind: JNI_LOAD_ABI; message: e }); }
  return Ok(v);
}

/// CallStaticIntMethod(1 int arg).  Complexity: O(call).
pub fn call_static_int_method_i(env: &JniEnv, clazz: &JClass, mid: &JMethodId, a: Int) -> Result[Int, JniProbeError]
  requires: true
{
  let v = unsafe { xj_call_static_int_method_i(env.handle as Int64, clazz.handle as Int64, mid.handle as Int64, a as Int32) as Int };
  let e = jni_error();
  if e.len() > 0 { return Err(JniProbeError{ kind: JNI_LOAD_ABI; message: e }); }
  return Ok(v);
}

/// CallStaticIntMethod(1 jstring arg; e.g. Integer.parseInt).
/// Complexity: O(call).
pub fn call_static_int_method_s(env: &JniEnv, clazz: &JClass, mid: &JMethodId, str: &JString) -> Result[Int, JniProbeError]
  requires: true
{
  let v = unsafe { xj_call_static_int_method_s(env.handle as Int64, clazz.handle as Int64, mid.handle as Int64, str.handle as Int64) as Int };
  let e = jni_error();
  if e.len() > 0 { return Err(JniProbeError{ kind: JNI_LOAD_ABI; message: e }); }
  return Ok(v);
}

/// CallStaticBooleanMethod(0 args).  Complexity: O(call).
pub fn call_static_boolean_method(env: &JniEnv, clazz: &JClass, mid: &JMethodId) -> Result[Bool, JniProbeError]
  requires: true
{
  let v = unsafe { xj_call_static_boolean_method(env.handle as Int64, clazz.handle as Int64, mid.handle as Int64) as Int };
  if v < 0 {
    return Err(JniProbeError{ kind: JNI_LOAD_ABI; message: jni_error() });
  }
  return Ok(v == 1);
}

/// CallStaticLongMethod(0 args).  Complexity: O(call).
pub fn call_static_long_method(env: &JniEnv, clazz: &JClass, mid: &JMethodId) -> Result[Int, JniProbeError]
  requires: true
{
  let v = unsafe { xj_call_static_long_method(env.handle as Int64, clazz.handle as Int64, mid.handle as Int64) as Int };
  let e = jni_error();
  if e.len() > 0 { return Err(JniProbeError{ kind: JNI_LOAD_ABI; message: e }); }
  return Ok(v);
}

/// CallStaticDoubleMethod(0 args) -> binary64 bits.  Complexity: O(call).
pub fn call_static_double_bits_method(env: &JniEnv, clazz: &JClass, mid: &JMethodId) -> Result[Int, JniProbeError]
  requires: true
{
  let v = unsafe { xj_call_static_double_bits_method(env.handle as Int64, clazz.handle as Int64, mid.handle as Int64) as Int };
  let e = jni_error();
  if e.len() > 0 { return Err(JniProbeError{ kind: JNI_LOAD_ABI; message: e }); }
  return Ok(v);
}

/// CallStaticObjectMethod(0 args).  Complexity: O(call).
pub fn call_static_object_method(env: &JniEnv, clazz: &JClass, mid: &JMethodId) -> Result[JObject, JniProbeError]
  requires: true
{
  let h = unsafe { xj_call_static_object_method(env.handle as Int64, clazz.handle as Int64, mid.handle as Int64) as Int };
  if h == 0 {
    return Err(JniProbeError{ kind: JNI_LOAD_ABI; message: jni_error() });
  }
  return Ok(JObject{ handle: h });
}

/// CallStaticVoidMethod(0 args).  Complexity: O(call).
pub fn call_static_void_method(env: &JniEnv, clazz: &JClass, mid: &JMethodId) -> Bool
  requires: true
{
  let rc = unsafe { xj_call_static_void_method(env.handle as Int64, clazz.handle as Int64, mid.handle as Int64) as Int };
  return rc == 0;
}

/// GetIntField.  Err via jni_error when handles are null.
/// Complexity: O(1).
pub fn get_int_field(env: &JniEnv, obj: &JObject, fid: &JFieldId) -> Result[Int, JniProbeError]
  requires: true
{
  let v = unsafe { xj_get_int_field(env.handle as Int64, obj.handle as Int64, fid.handle as Int64) as Int };
  let e = jni_error();
  if e.len() > 0 { return Err(JniProbeError{ kind: JNI_LOAD_ABI; message: e }); }
  return Ok(v);
}

/// GetLongField.  Complexity: O(1).
pub fn get_long_field(env: &JniEnv, obj: &JObject, fid: &JFieldId) -> Result[Int, JniProbeError]
  requires: true
{
  let v = unsafe { xj_get_long_field(env.handle as Int64, obj.handle as Int64, fid.handle as Int64) as Int };
  let e = jni_error();
  if e.len() > 0 { return Err(JniProbeError{ kind: JNI_LOAD_ABI; message: e }); }
  return Ok(v);
}

/// GetDoubleField as binary64 bits.  Complexity: O(1).
pub fn get_double_bits_field(env: &JniEnv, obj: &JObject, fid: &JFieldId) -> Result[Int, JniProbeError]
  requires: true
{
  let v = unsafe { xj_get_double_bits_field(env.handle as Int64, obj.handle as Int64, fid.handle as Int64) as Int };
  let e = jni_error();
  if e.len() > 0 { return Err(JniProbeError{ kind: JNI_LOAD_ABI; message: e }); }
  return Ok(v);
}

/// GetObjectField.  Complexity: O(1).
pub fn get_object_field(env: &JniEnv, obj: &JObject, fid: &JFieldId) -> Result[JObject, JniProbeError]
  requires: true
{
  let h = unsafe { xj_get_object_field(env.handle as Int64, obj.handle as Int64, fid.handle as Int64) as Int };
  if h == 0 {
    return Err(JniProbeError{ kind: JNI_LOAD_ABI; message: jni_error() });
  }
  return Ok(JObject{ handle: h });
}

/// SetIntField.  Complexity: O(1).
pub fn set_int_field(env: &JniEnv, obj: &JObject, fid: &JFieldId, v: Int) -> Bool
  requires: true
{
  let rc = unsafe { xj_set_int_field(env.handle as Int64, obj.handle as Int64, fid.handle as Int64, v as Int32) as Int };
  return rc == 0;
}

/// SetLongField.  Complexity: O(1).
pub fn set_long_field(env: &JniEnv, obj: &JObject, fid: &JFieldId, v: Int) -> Bool
  requires: true
{
  let rc = unsafe { xj_set_long_field(env.handle as Int64, obj.handle as Int64, fid.handle as Int64, v as Int64) as Int };
  return rc == 0;
}

/// SetObjectField.  Complexity: O(1).
pub fn set_object_field(env: &JniEnv, obj: &JObject, fid: &JFieldId, v: &JObject) -> Bool
  requires: true
{
  let rc = unsafe { xj_set_object_field(env.handle as Int64, obj.handle as Int64, fid.handle as Int64, v.handle as Int64) as Int };
  return rc == 0;
}

/// GetStaticIntField.  Complexity: O(1).
pub fn get_static_int_field(env: &JniEnv, clazz: &JClass, fid: &JFieldId) -> Result[Int, JniProbeError]
  requires: true
{
  let v = unsafe { xj_get_static_int_field(env.handle as Int64, clazz.handle as Int64, fid.handle as Int64) as Int };
  let e = jni_error();
  if e.len() > 0 { return Err(JniProbeError{ kind: JNI_LOAD_ABI; message: e }); }
  return Ok(v);
}

/// GetStaticLongField.  Complexity: O(1).
pub fn get_static_long_field(env: &JniEnv, clazz: &JClass, fid: &JFieldId) -> Result[Int, JniProbeError]
  requires: true
{
  let v = unsafe { xj_get_static_long_field(env.handle as Int64, clazz.handle as Int64, fid.handle as Int64) as Int };
  let e = jni_error();
  if e.len() > 0 { return Err(JniProbeError{ kind: JNI_LOAD_ABI; message: e }); }
  return Ok(v);
}

/// GetStaticObjectField.  Complexity: O(1).
pub fn get_static_object_field(env: &JniEnv, clazz: &JClass, fid: &JFieldId) -> Result[JObject, JniProbeError]
  requires: true
{
  let h = unsafe { xj_get_static_object_field(env.handle as Int64, clazz.handle as Int64, fid.handle as Int64) as Int };
  if h == 0 {
    return Err(JniProbeError{ kind: JNI_LOAD_ABI; message: jni_error() });
  }
  return Ok(JObject{ handle: h });
}

// =========================================================================
// Strings (UTF-8; chars are copied into a bridge-owned slot)
// =========================================================================

/// NewStringUTF(utf8).  Complexity: O(len).
pub fn new_string_utf(env: &JniEnv, utf8: Str) -> Result[JString, JniProbeError]
  requires: true
{
  let h = unsafe { xj_new_string_utf(env.handle as Int64, utf8.c_str()) as Int };
  if h == 0 {
    return Err(JniProbeError{ kind: JNI_LOAD_ABI; message: jni_error() });
  }
  return Ok(JString{ handle: h });
}

/// The string's modified-UTF-8 length in bytes; -1 on error.
/// Complexity: O(1).
pub fn string_utf_length(env: &JniEnv, s: &JString) -> Int
  requires: true
{
  unsafe { return xj_string_utf_length(env.handle as Int64, s.handle as Int64) as Int; }
}

/// Copy the string's UTF-8 chars into the bridge-owned slot
/// (max_len <= 0 uses the slot capacity) and return the copied length;
/// -1 on error.  Read the value back with `string_buf()`.
/// Complexity: O(len).
pub fn string_read_utf8(env: &JniEnv, s: &JString, max_len: Int) -> Int
  requires: true
{
  unsafe { return xj_string_read_utf8(env.handle as Int64, s.handle as Int64, max_len as Int32) as Int; }
}

/// The bridge-owned UTF-8 slot as a Str (B-24-safe owned-slot read; the
/// slot holds the last `string_read_utf8` result).
/// Complexity: O(len).
pub fn string_buf() -> Str
  requires: true
{
  unsafe { return Str::from_c_str(xj_string_buf_ptr()); }
}

/// The bridge-owned UTF-8 slot length in bytes.
/// Complexity: O(1).
pub fn string_buf_len() -> Int
  requires: true
{
  unsafe { return xj_string_buf_len() as Int; }
}

// =========================================================================
// Arrays (bridge-owned int32 slots, 64 entries)
// =========================================================================

/// GetArrayLength.  -1 on error.  Complexity: O(1).
pub fn array_length(env: &JniEnv, arr: &JArray) -> Int
  requires: true
{
  unsafe { return xj_array_length(env.handle as Int64, arr.handle as Int64) as Int; }
}

/// NewIntArray(len).  Complexity: O(len).
pub fn new_int_array(env: &JniEnv, len: Int) -> Result[JArray, JniProbeError]
  requires: len >= 0
{
  let h = unsafe { xj_new_int_array(env.handle as Int64, len as Int32) as Int };
  if h == 0 {
    return Err(JniProbeError{ kind: JNI_LOAD_ABI; message: jni_error() });
  }
  return Ok(JArray{ handle: h });
}

/// NewByteArray(len).  Complexity: O(len).
pub fn new_byte_array(env: &JniEnv, len: Int) -> Result[JArray, JniProbeError]
  requires: len >= 0
{
  let h = unsafe { xj_new_byte_array(env.handle as Int64, len as Int32) as Int };
  if h == 0 {
    return Err(JniProbeError{ kind: JNI_LOAD_ABI; message: jni_error() });
  }
  return Ok(JArray{ handle: h });
}

/// GetIntArrayRegion(arr, start, len<=64) into the bridge-owned slots
/// (read back with `int_slot_get`).  Bool = ok.
/// Complexity: O(len).
pub fn get_int_array_region(env: &JniEnv, arr: &JArray, start: Int, len: Int) -> Bool
  requires: start >= 0
  requires: len >= 0
{
  let rc = unsafe { xj_get_int_array_region(env.handle as Int64, arr.handle as Int64, start as Int32, len as Int32) as Int };
  return rc == 0;
}

/// SetIntArrayRegion(arr, start, len<=64) FROM the bridge-owned slots
/// (write with `int_slot_set` first).  Bool = ok.
/// Complexity: O(len).
pub fn set_int_array_region(env: &JniEnv, arr: &JArray, start: Int, len: Int) -> Bool
  requires: start >= 0
  requires: len >= 0
{
  let rc = unsafe { xj_set_int_array_region(env.handle as Int64, arr.handle as Int64, start as Int32, len as Int32) as Int };
  return rc == 0;
}

/// Write one bridge-owned int32 slot (0..63).  Bool = ok.
/// Complexity: O(1).
pub fn int_slot_set(index: Int, value: Int) -> Bool
  requires: index >= 0
{
  let rc = unsafe { xj_int_slot_set(index as Int32, value as Int32) as Int };
  return rc == 0;
}

/// Read one bridge-owned int32 slot (0..63); error text on bad index.
/// Complexity: O(1).
pub fn int_slot_get(index: Int) -> Int
  requires: index >= 0
{
  unsafe { return xj_int_slot_get(index as Int32) as Int; }
}

// =========================================================================
// android/bitmap.h cluster (libjnigraphics.so)
// =========================================================================

/// The AndroidBitmapInfo read-back slot (owned by the bridge; filled by
/// `bitmap_get_info` / pixel ops -- B-series slot readback).
pub type BitmapInfo = {
  width: Int;
  height: Int;
  stride: Int;
  format: Int;
  flags: Int;
  valid: Bool;
}

/// AndroidBitmap_getInfo into the owned slot; true when rc == 0.
/// Requires a loaded runtime (jni_probe); false otherwise.
/// Complexity: O(1).
pub fn bitmap_get_info(env: &JniEnv, bitmap: &JObject) -> Bool
  requires: true
{
  let rc = unsafe { xj_bitmap_get_info(env.handle as Int64, bitmap.handle as Int64) as Int };
  return rc == 0;
}

/// The info slot as a record (valid = a getInfo succeeded; values stay
/// 0 until then).  Complexity: O(1).
pub fn bitmap_info() -> BitmapInfo
  requires: true
{
  let w = unsafe { xj_bitmap_info_width() as Int };
  let h = unsafe { xj_bitmap_info_height() as Int };
  let s = unsafe { xj_bitmap_info_stride() as Int };
  let f = unsafe { xj_bitmap_info_format() as Int };
  let fl = unsafe { xj_bitmap_info_flags() as Int };
  let v = unsafe { xj_bitmap_info_valid() as Int };
  return BitmapInfo{ width: w, height: h, stride: s, format: f, flags: fl, valid: v == 1 };
}

/// AndroidBitmap_getDataSpace (API 30+); JNI_ERR_DATASPACE on error.
/// Complexity: O(1).
pub fn bitmap_get_data_space(env: &JniEnv, bitmap: &JObject) -> Int
  requires: true
{
  unsafe { return xj_bitmap_get_data_space(env.handle as Int64, bitmap.handle as Int64) as Int; }
}

/// AndroidBitmap_lockPixels; true when locked.  Pair with
/// `bitmap_unlock_pixels`; pixel ops on the SAME bitmap then reuse the
/// retained window (the address never crosses; B-25).
/// Complexity: O(lock).
pub fn bitmap_lock_pixels(env: &JniEnv, bitmap: &JObject) -> Bool
  requires: true
{
  let rc = unsafe { xj_bitmap_lock_pixels(env.handle as Int64, bitmap.handle as Int64) as Int };
  return rc == 0;
}

/// AndroidBitmap_unlockPixels; true when unlocked.
/// Complexity: O(unlock).
pub fn bitmap_unlock_pixels(env: &JniEnv, bitmap: &JObject) -> Bool
  requires: true
{
  let rc = unsafe { xj_bitmap_unlock_pixels(env.handle as Int64, bitmap.handle as Int64) as Int };
  return rc == 0;
}

/// Write one 32-bit pixel value at (x, y) (RGBA_8888 byte order; little
/// endian => the Java getPixel int reads back identically).  Locks /
/// unlocks internally unless a manual lock of the same bitmap is active.
/// Complexity: O(lock + store).
pub fn bitmap_write_pixel(env: &JniEnv, bitmap: &JObject, x: Int, y: Int, rgba: Int) -> Bool
  requires: true
{
  let rc = unsafe { xj_bitmap_write_pixel(env.handle as Int64, bitmap.handle as Int64, x as Int32, y as Int32, rgba as Int32) as Int };
  return rc == 0;
}

/// Read one 32-bit pixel value at (x, y) through the retained/locked
/// window; -1 = error (see jni_error).  Complexity: O(lock + load).
pub fn bitmap_read_pixel(env: &JniEnv, bitmap: &JObject, x: Int, y: Int) -> Int
  requires: true
{
  unsafe { return xj_bitmap_read_pixel(env.handle as Int64, bitmap.handle as Int64, x as Int32, y as Int32) as Int; }
}

/// 1 = the bitmap's flags carry ANDROID_BITMAP_FLAGS_IS_HARDWARE (mask
/// tested C-side; B-29-safe here); -1 = error.
/// Complexity: O(1).
pub fn bitmap_is_hardware(env: &JniEnv, bitmap: &JObject) -> Int
  requires: true
{
  unsafe { return xj_bitmap_is_hardware(env.handle as Int64, bitmap.handle as Int64) as Int; }
}

/// AndroidBitmap_getHardwareBuffer (API 30+; HARDWARE bitmaps only).
/// Returns the AHardwareBuffer handle (release it with
/// AHardwareBuffer_release -- the `xiom.android` head); 0 = none/error.
/// Complexity: O(1).
pub fn bitmap_get_hardware_buffer(env: &JniEnv, bitmap: &JObject) -> Int
  requires: true
{
  unsafe { return xj_bitmap_get_hardware_buffer(env.handle as Int64, bitmap.handle as Int64) as Int; }
}

/// AndroidBitmap_compress into the bridge-owned buffer through the
/// C-side write callback (the pixel pointer never crosses); the format
/// is ANDROID_BITMAP_COMPRESS_FORMAT_*; max_bytes caps the slot (0 =
/// slot size).  Returns bytes written; -1 = error.
/// Complexity: O(compress).
pub fn bitmap_compress_owned(env: &JniEnv, bitmap: &JObject, format: Int, quality: Int, max_bytes: Int) -> Int
  requires: quality >= 0
  requires: quality <= 100
{
  unsafe { return xj_bitmap_compress_owned(env.handle as Int64, bitmap.handle as Int64, format as Int32, quality as Int32, max_bytes as Int32) as Int; }
}

/// The compressed slot length in bytes (last `bitmap_compress_owned`).
/// Complexity: O(1).
pub fn bitmap_compressed_len() -> Int
  requires: true
{
  unsafe { return xj_bitmap_compressed_len() as Int; }
}

/// A byte of the compressed slot (0..len-1) as Int; -1 when out of
/// range.  Byte-indexed owned-slot read (B-24-safe; no pointer math).
/// Complexity: O(1).
pub fn bitmap_compressed_byte(index: Int) -> Int
  requires: index >= 0
{
  unsafe { return xj_bitmap_compressed_byte(index as Int32) as Int; }
}

// =========================================================================
// Convenience constructors
// =========================================================================

/// Build a JNINativeMethod shape from its parts (fn_ptr as Int; the
/// consumer's JNIEXPORT function address).
/// Complexity: O(1).
pub fn native_method(name: Str, signature: Str, fn_ptr: Int) -> JniNativeMethod
  requires: name.len() > 0
  requires: signature.len() > 0
{
  return JniNativeMethod{ name: name, signature: signature, fn_ptr: fn_ptr };
}

