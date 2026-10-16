// xiom.jni conformance suite -- Android JNI seam (jni.h interface +
// android/bitmap.h) with the SKIP-safe runtime pair loader
// (libjnigraphics.so + libnativehelper.so).
//
// The probe never FAILs on a missing runtime:
//   missing pair    -> JNI_LOAD_ABSENT (SKIP; exercised deterministically
//                      below with bogus sonames)
//   present pair    -> export-set ABI check (9 declared symbols); the
//                      live JNIEnv path needs a consumer-supplied env
//                      (JNI_OnLoad) -> proven by the on-device
//                      app_process probe (docs/repro), not here
//   broken install  -> JNI_LOAD_ABI (FAIL -- never a silent SKIP)
//
// On Windows the runtime pair is absent by design -> SKIP (CI stays
// green); the null-safety battery below still runs EVERY helper with
// 0-env/0-object/0-vm handles and asserts the typed error contract
// (never a silent zero, never a crash).
//
// Build+run through the runner (compiles src/jni_bridge.c via
// port.args.json):
//   scripts/port.ps1 -Package xiom.jni

module jni_conformance

use xiom.io;
use xiom.jni;

fn report(ok: Bool, name: Str) -> Int {
  if ok {
    io.println("  [PASS] " + name);
    io.flush_stdout();
    return 0;
  }
  io.println("  [FAIL] " + name);
  io.flush_stdout();
  return 1;
}

// Every failed helper must leave a non-empty typed error text.
fn err_text_present() -> Bool {
  return jni_error().len() > 0;
}

fn t_constants() -> Bool {
  var ok = true;
  // jni.h versions + result codes + ref types.
  if JNI_VERSION_1_1 != 0x00010001 || JNI_VERSION_1_2 != 0x00010002 { ok = false; }
  if JNI_VERSION_1_4 != 0x00010004 || JNI_VERSION_1_6 != 0x00010006 { ok = false; }
  if JNI_FALSE != 0 || JNI_TRUE != 1 { ok = false; }
  if JNI_OK != 0 || JNI_ERR != -1 || JNI_EDETACHED != -2 { ok = false; }
  if JNI_EVERSION != -3 || JNI_ENOMEM != -4 || JNI_EEXIST != -5 || JNI_EINVAL != -6 { ok = false; }
  if JNI_COMMIT != 1 || JNI_ABORT != 2 { ok = false; }
  if JNI_INVALID_REF_TYPE != 0 || JNI_LOCAL_REF_TYPE != 1 { ok = false; }
  if JNI_GLOBAL_REF_TYPE != 2 || JNI_WEAK_GLOBAL_REF_TYPE != 3 { ok = false; }
  // Classification kinds + sentinels.
  if JNI_LOAD_ABSENT != 0 || JNI_LOAD_ABI != 1 { ok = false; }
  if JNI_ERR_INT != -1 || JNI_ERR_DATASPACE != -2147483648 { ok = false; }
  if JNIGRAPHICS_SONAME != "libjnigraphics.so" || NATIVEHELPER_SONAME != "libnativehelper.so" { ok = false; }
  // android/bitmap.h result codes.
  if ANDROID_BITMAP_RESULT_SUCCESS != 0 || ANDROID_BITMAP_RESULT_BAD_PARAMETER != -1 { ok = false; }
  if ANDROID_BITMAP_RESULT_JNI_EXCEPTION != -2 || ANDROID_BITMAP_RESULT_ALLOCATION_FAILED != -3 { ok = false; }
  // Bitmap formats.
  if ANDROID_BITMAP_FORMAT_NONE != 0 || ANDROID_BITMAP_FORMAT_RGBA_8888 != 1 { ok = false; }
  if ANDROID_BITMAP_FORMAT_RGB_565 != 4 || ANDROID_BITMAP_FORMAT_RGBA_4444 != 7 { ok = false; }
  if ANDROID_BITMAP_FORMAT_A_8 != 8 || ANDROID_BITMAP_FORMAT_RGBA_F16 != 9 { ok = false; }
  if ANDROID_BITMAP_FORMAT_RGBA_1010102 != 10 { ok = false; }
  // Alpha flags + hardware flag (2^31; compared by value, no bitwise -- B-29).
  if ANDROID_BITMAP_FLAGS_ALPHA_PREMUL != 0 || ANDROID_BITMAP_FLAGS_ALPHA_OPAQUE != 1 { ok = false; }
  if ANDROID_BITMAP_FLAGS_ALPHA_UNPREMUL != 2 || ANDROID_BITMAP_FLAGS_ALPHA_MASK != 3 { ok = false; }
  if ANDROID_BITMAP_FLAGS_ALPHA_SHIFT != 0 { ok = false; }
  if ANDROID_BITMAP_FLAGS_IS_HARDWARE != 2147483648 { ok = false; }
  // Compress formats.
  if ANDROID_BITMAP_COMPRESS_FORMAT_JPEG != 0 || ANDROID_BITMAP_COMPRESS_FORMAT_PNG != 1 { ok = false; }
  if ANDROID_BITMAP_COMPRESS_FORMAT_WEBP_LOSSY != 3 || ANDROID_BITMAP_COMPRESS_FORMAT_WEBP_LOSSLESS != 4 { ok = false; }
  return ok;
}

fn t_jninative_method_shape() -> Bool {
  var ok = true;
  let m = native_method("probeNative", "(Landroid/graphics/Bitmap;)I", 1234567890);
  if m.name != "probeNative" { ok = false; }
  if m.signature != "(Landroid/graphics/Bitmap;)I" { ok = false; }
  if m.fn_ptr != 1234567890 { ok = false; }
  return ok;
}

// ---------------------------------------------------------------------------
// Null-safety battery: EVERY declared helper with 0 handles.  Must produce
// the documented typed error / sentinel -- never a crash, never a silent
// zero.  Runs on Windows (SKIP leg) and on Android alike.
// ---------------------------------------------------------------------------

fn t_null_vm_env() -> Int {
  var failed: Int = 0;
  let vm0 = JavaVm{ handle: 0 };
  let e0 = JniEnv{ handle: 0 };
  let r1 = vm_get_env(&vm0, JNI_VERSION_1_6);
  failed = failed + report(!r1.is_ok && err_text_present(), "null-safety: vm_get_env(0) -> typed error");
  let r2 = vm_attach_current(&vm0);
  failed = failed + report(!r2.is_ok && err_text_present(), "null-safety: vm_attach_current(0) -> typed error");
  failed = failed + report(!vm_detach_current(&vm0) && err_text_present(), "null-safety: vm_detach_current(0) -> false + error");
  let r3 = vm_from_created(0);
  failed = failed + report(!r3.is_ok && err_text_present(), "null-safety: vm_from_created(0) without runtime -> typed error");
  let r4 = env_get_java_vm(&e0);
  failed = failed + report(!r4.is_ok && err_text_present(), "null-safety: env_get_java_vm(0) -> typed error");
  failed = failed + report(env_version(&e0) == JNI_ERR_INT && err_text_present(),
    "null-safety: env_version(0) -> -1 + error");
  return failed;
}

fn t_null_classes_refs() -> Int {
  var failed: Int = 0;
  let e0 = JniEnv{ handle: 0 };
  let o0 = JObject{ handle: 0 };
  let c0 = JClass{ handle: 0 };
  let t0 = JThrowable{ handle: 0 };
  let r1 = find_class(&e0, "java/lang/String");
  failed = failed + report(!r1.is_ok && err_text_present(), "null-safety: find_class(0 env) -> typed error");
  let r2 = get_object_class(&e0, &o0);
  failed = failed + report(!r2.is_ok && err_text_present(), "null-safety: get_object_class(0, 0) -> typed error");
  let r3 = get_superclass(&e0, &c0);
  failed = failed + report(!r3.is_ok && err_text_present(), "null-safety: get_superclass(0, 0) -> typed error");
  failed = failed + report(is_assignable_from(&e0, &c0, &c0) == JNI_ERR_INT && err_text_present(),
    "null-safety: is_assignable_from(0, 0, 0) -> -1 + error");
  failed = failed + report(is_instance_of(&e0, &o0, &c0) == JNI_ERR_INT && err_text_present(),
    "null-safety: is_instance_of(0, 0, 0) -> -1 + error");
  let r4 = new_global_ref(&e0, &o0);
  failed = failed + report(!r4.is_ok && err_text_present(), "null-safety: new_global_ref(0, 0) -> typed error");
  failed = failed + report(!delete_global_ref(&e0, &o0) && err_text_present(),
    "null-safety: delete_global_ref(0, 0) -> false + error");
  failed = failed + report(!delete_local_ref(&e0, &o0) && err_text_present(),
    "null-safety: delete_local_ref(0, 0) -> false + error");
  let r5 = new_local_ref(&e0, &o0);
  failed = failed + report(!r5.is_ok && err_text_present(), "null-safety: new_local_ref(0, 0) -> typed error");
  failed = failed + report(!push_local_frame(&e0, 8) && err_text_present(),
    "null-safety: push_local_frame(0) -> false + error");
  failed = failed + report(pop_local_frame(&e0, &o0) == 0 && err_text_present(),
    "null-safety: pop_local_frame(0) -> 0 + error");
  failed = failed + report(!ensure_local_capacity(&e0, 8) && err_text_present(),
    "null-safety: ensure_local_capacity(0) -> false + error");
  failed = failed + report(exception_check(&e0) == JNI_ERR_INT && err_text_present(),
    "null-safety: exception_check(0) -> -1 + error");
  failed = failed + report(exception_occurred(&e0) == 0 && err_text_present(),
    "null-safety: exception_occurred(0) -> 0 + error");
  exception_describe(&e0);
  failed = failed + report(err_text_present(), "null-safety: exception_describe(0) -> error recorded");
  exception_clear(&e0);
  failed = failed + report(err_text_present(), "null-safety: exception_clear(0) -> error recorded");
  failed = failed + report(!throw_new(&e0, &c0, "x") && err_text_present(),
    "null-safety: throw_new(0, 0) -> false + error");
  failed = failed + report(!throw(&e0, &t0) && err_text_present(),
    "null-safety: throw(0, 0) -> false + error");
  let m = native_method("n", "()V", 4096);
  failed = failed + report(!register_native(&e0, &c0, &m) && err_text_present(),
    "null-safety: register_native(0, 0) -> false + error");
  failed = failed + report(!unregister_natives(&e0, &c0) && err_text_present(),
    "null-safety: unregister_natives(0, 0) -> false + error");
  return failed;
}

fn t_null_ids_calls_fields() -> Int {
  var failed: Int = 0;
  let e0 = JniEnv{ handle: 0 };
  let o0 = JObject{ handle: 0 };
  let c0 = JClass{ handle: 0 };
  let m0 = JMethodId{ handle: 0 };
  let f0 = JFieldId{ handle: 0 };
  let s0 = JString{ handle: 0 };
  let r1 = get_method_id(&e0, &c0, "m", "()I");
  failed = failed + report(!r1.is_ok && err_text_present(), "null-safety: get_method_id(0) -> typed error");
  let r2 = get_static_method_id(&e0, &c0, "m", "()I");
  failed = failed + report(!r2.is_ok && err_text_present(), "null-safety: get_static_method_id(0) -> typed error");
  let r3 = get_field_id(&e0, &c0, "f", "I");
  failed = failed + report(!r3.is_ok && err_text_present(), "null-safety: get_field_id(0) -> typed error");
  let r4 = get_static_field_id(&e0, &c0, "f", "I");
  failed = failed + report(!r4.is_ok && err_text_present(), "null-safety: get_static_field_id(0) -> typed error");
  let i1 = call_int_method(&e0, &o0, &m0);
  failed = failed + report(!i1.is_ok, "null-safety: call_int_method(0) -> Err");
  let i2 = call_int_method_i(&e0, &o0, &m0, 1);
  failed = failed + report(!i2.is_ok, "null-safety: call_int_method_i(0) -> Err");
  let i3 = call_int_method_ii(&e0, &o0, &m0, 1, 2);
  failed = failed + report(!i3.is_ok, "null-safety: call_int_method_ii(0) -> Err");
  let i4 = call_int_method_s(&e0, &o0, &m0, &s0);
  failed = failed + report(!i4.is_ok, "null-safety: call_int_method_s(0) -> Err");
  let b1 = call_boolean_method(&e0, &o0, &m0);
  failed = failed + report(!b1.is_ok, "null-safety: call_boolean_method(0) -> Err");
  let l1 = call_long_method(&e0, &o0, &m0);
  failed = failed + report(!l1.is_ok, "null-safety: call_long_method(0) -> Err");
  let d1 = call_double_bits_method(&e0, &o0, &m0);
  failed = failed + report(!d1.is_ok, "null-safety: call_double_bits_method(0) -> Err");
  let d2 = call_double_bits_method_d(&e0, &o0, &m0, 0);
  failed = failed + report(!d2.is_ok, "null-safety: call_double_bits_method_d(0) -> Err");
  let d3 = call_double_bits_method_i(&e0, &o0, &m0, 3);
  failed = failed + report(!d3.is_ok, "null-safety: call_double_bits_method_i(0) -> Err");
  let f1 = call_float_bits_method(&e0, &o0, &m0);
  failed = failed + report(!f1.is_ok, "null-safety: call_float_bits_method(0) -> Err");
  let o1 = call_object_method(&e0, &o0, &m0);
  failed = failed + report(!o1.is_ok, "null-safety: call_object_method(0) -> Err");
  failed = failed + report(!call_void_method(&e0, &o0, &m0), "null-safety: call_void_method(0) -> false");
  let s1 = call_static_int_method(&e0, &c0, &m0);
  failed = failed + report(!s1.is_ok, "null-safety: call_static_int_method(0) -> Err");
  let s2 = call_static_int_method_i(&e0, &c0, &m0, 1);
  failed = failed + report(!s2.is_ok, "null-safety: call_static_int_method_i(0) -> Err");
  let s3 = call_static_int_method_s(&e0, &c0, &m0, &s0);
  failed = failed + report(!s3.is_ok, "null-safety: call_static_int_method_s(0) -> Err");
  let s4 = call_static_boolean_method(&e0, &c0, &m0);
  failed = failed + report(!s4.is_ok, "null-safety: call_static_boolean_method(0) -> Err");
  let s5 = call_static_long_method(&e0, &c0, &m0);
  failed = failed + report(!s5.is_ok, "null-safety: call_static_long_method(0) -> Err");
  let s6 = call_static_double_bits_method(&e0, &c0, &m0);
  failed = failed + report(!s6.is_ok, "null-safety: call_static_double_bits_method(0) -> Err");
  let s7 = call_static_object_method(&e0, &c0, &m0);
  failed = failed + report(!s7.is_ok, "null-safety: call_static_object_method(0) -> Err");
  failed = failed + report(!call_static_void_method(&e0, &c0, &m0),
    "null-safety: call_static_void_method(0) -> false");
  let g1 = get_int_field(&e0, &o0, &f0);
  failed = failed + report(!g1.is_ok, "null-safety: get_int_field(0) -> Err");
  let g2 = get_long_field(&e0, &o0, &f0);
  failed = failed + report(!g2.is_ok, "null-safety: get_long_field(0) -> Err");
  let g3 = get_double_bits_field(&e0, &o0, &f0);
  failed = failed + report(!g3.is_ok, "null-safety: get_double_bits_field(0) -> Err");
  let g4 = get_object_field(&e0, &o0, &f0);
  failed = failed + report(!g4.is_ok, "null-safety: get_object_field(0) -> Err");
  failed = failed + report(!set_int_field(&e0, &o0, &f0, 1), "null-safety: set_int_field(0) -> false");
  failed = failed + report(!set_long_field(&e0, &o0, &f0, 1), "null-safety: set_long_field(0) -> false");
  failed = failed + report(!set_object_field(&e0, &o0, &f0, &o0), "null-safety: set_object_field(0) -> false");
  let g5 = get_static_int_field(&e0, &c0, &f0);
  failed = failed + report(!g5.is_ok, "null-safety: get_static_int_field(0) -> Err");
  let g6 = get_static_long_field(&e0, &c0, &f0);
  failed = failed + report(!g6.is_ok, "null-safety: get_static_long_field(0) -> Err");
  let g7 = get_static_object_field(&e0, &c0, &f0);
  failed = failed + report(!g7.is_ok, "null-safety: get_static_object_field(0) -> Err");
  return failed;
}

fn t_null_strings_arrays() -> Int {
  var failed: Int = 0;
  let e0 = JniEnv{ handle: 0 };
  let s0 = JString{ handle: 0 };
  let a0 = JArray{ handle: 0 };
  let r1 = new_string_utf(&e0, "xiom");
  failed = failed + report(!r1.is_ok && err_text_present(), "null-safety: new_string_utf(0) -> typed error");
  failed = failed + report(string_utf_length(&e0, &s0) == JNI_ERR_INT && err_text_present(),
    "null-safety: string_utf_length(0) -> -1 + error");
  failed = failed + report(string_read_utf8(&e0, &s0, 0) == JNI_ERR_INT && err_text_present(),
    "null-safety: string_read_utf8(0) -> -1 + error");
  failed = failed + report(array_length(&e0, &a0) == JNI_ERR_INT && err_text_present(),
    "null-safety: array_length(0) -> -1 + error");
  let r2 = new_int_array(&e0, 8);
  failed = failed + report(!r2.is_ok && err_text_present(), "null-safety: new_int_array(0) -> typed error");
  let r3 = new_byte_array(&e0, 8);
  failed = failed + report(!r3.is_ok && err_text_present(), "null-safety: new_byte_array(0) -> typed error");
  failed = failed + report(!get_int_array_region(&e0, &a0, 0, 4) && err_text_present(),
    "null-safety: get_int_array_region(0) -> false + error");
  failed = failed + report(!set_int_array_region(&e0, &a0, 0, 4) && err_text_present(),
    "null-safety: set_int_array_region(0) -> false + error");
  // The int slots are bridge-owned state: usable without any runtime.
  failed = failed + report(int_slot_set(0, 42), "slots: int_slot_set(0, 42)");
  failed = failed + report(int_slot_get(0) == 42, "slots: int_slot_get(0) == 42");
  failed = failed + report(!int_slot_set(64, 1), "slots: int_slot_set(out of range) -> false");
  return failed;
}

fn t_null_bitmap() -> Int {
  var failed: Int = 0;
  let e0 = JniEnv{ handle: 0 };
  let b0 = JObject{ handle: 0 };
  failed = failed + report(!bitmap_get_info(&e0, &b0) && err_text_present(),
    "null-safety: bitmap_get_info(0) -> false + error");
  let info = bitmap_info();
  failed = failed + report(!info.valid, "null-safety: bitmap_info slot not valid");
  failed = failed + report(bitmap_get_data_space(&e0, &b0) == JNI_ERR_DATASPACE && err_text_present(),
    "null-safety: bitmap_get_data_space(0) -> INT32_MIN + error");
  failed = failed + report(!bitmap_lock_pixels(&e0, &b0) && err_text_present(),
    "null-safety: bitmap_lock_pixels(0) -> false + error");
  failed = failed + report(!bitmap_unlock_pixels(&e0, &b0) && err_text_present(),
    "null-safety: bitmap_unlock_pixels(0) -> false + error");
  failed = failed + report(!bitmap_write_pixel(&e0, &b0, 0, 0, 0x11223344) && err_text_present(),
    "null-safety: bitmap_write_pixel(0) -> false + error");
  failed = failed + report(bitmap_read_pixel(&e0, &b0, 0, 0) == JNI_ERR_INT && err_text_present(),
    "null-safety: bitmap_read_pixel(0) -> -1 + error");
  failed = failed + report(bitmap_is_hardware(&e0, &b0) == JNI_ERR_INT && err_text_present(),
    "null-safety: bitmap_is_hardware(0) -> -1 + error");
  failed = failed + report(bitmap_get_hardware_buffer(&e0, &b0) == 0 && err_text_present(),
    "null-safety: bitmap_get_hardware_buffer(0) -> 0 + error");
  failed = failed + report(bitmap_compress_owned(&e0, &b0, ANDROID_BITMAP_COMPRESS_FORMAT_PNG, 100, 0) == JNI_ERR_INT
    && err_text_present(), "null-safety: bitmap_compress_owned(0) -> -1 + error");
  failed = failed + report(bitmap_compressed_len() == 0, "slots: compressed len starts 0");
  failed = failed + report(bitmap_compressed_byte(0) == JNI_ERR_INT && err_text_present(),
    "slots: compressed_byte(out of range) -> -1 + error");
  return failed;
}

fn main() -> Int {
  io.println("=== xiom.jni conformance tests (JNI seam + libjnigraphics) ===");
  io.flush_stdout();
  var failed: Int = 0;

  failed = failed + report(t_constants(), "constants: jni.h versions/codes/ref-types + bitmap enums");
  failed = failed + report(t_jninative_method_shape(), "JNINativeMethod shape roundtrip");
  failed = failed + report(jni_export_count() == 9,
    "export set: declared size 9 (got " + to_string(jni_export_count()) + ")");

  // Unloaded runtime is the state at this point: the whole declared
  // surface must answer with typed errors (SKIP leg + Android alike).
  failed = failed + t_null_vm_env();
  failed = failed + t_null_classes_refs();
  failed = failed + t_null_ids_calls_fields();
  failed = failed + t_null_strings_arrays();
  failed = failed + t_null_bitmap();

  // SKIP-path classification, deterministic on every host (bogus pair).
  let missing = jni_probe_named("xiom-absent-libjnigraphics-xyz.so", "xiom-absent-libnativehelper-xyz.so");
  if missing.is_ok {
    failed = failed + report(false, "skip-path: bogus pair unexpectedly loaded");
  } else {
    failed = failed + report(missing.error.kind == JNI_LOAD_ABSENT,
      "skip-path: absent pair classified as JNI_LOAD_ABSENT (SKIP)");
  }

  // Default runtime probe (the SKIP-safe first gate).
  let p = jni_probe();
  if p.is_ok {
    let rt: JniRuntime = p.value;
    failed = failed + report(rt.missing_exports == 0,
      "abi: declared export set fully resolved (" + to_string(rt.missing_exports) + " missing)");
    failed = failed + report(true,
      "probe: runtime pair present -- live env path needs the consumer's JNI_OnLoad (docs/repro probe)");
  } else {
    if p.error.kind == JNI_LOAD_ABSENT {
      failed = failed + report(true, "probe: SKIP -- jni runtime pair not present (" + p.error.message + ")");
    } else {
      failed = failed + report(false, "probe: failed -- " + p.error.message);
    }
  }

  // Unload must be safe even after a failed probe; it also clears state.
  jni_unload();
  failed = failed + report(jni_error().len() == 0, "loader: unload path exercised (error cleared)");

  if failed == 0 {
    io.println("xiom.jni: all tests passed");
  } else {
    io.println("xiom.jni: tests failed");
  }
  return failed;
}
