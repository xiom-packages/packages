/* XIOM -- xiom.jni: Android JNI seam + libjnigraphics runtime bridge.
 * Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
 * Licensed under the MIT or Apache-2.0 license, at your option.
 *
 * DESIGN (A11 jni-seam head of the Android SDK100 program; docs/ANDROID-SDK100.md):
 * jni.h is an INTERFACE, not a flat export map: the JNIEnv / JavaVM
 * function tables only exist inside a live Java host.  This bridge is the
 * seam: the CONSUMER APP supplies the JavaVM* it receives in its
 * JNI_OnLoad (and an env obtained from it) as Int handles, and every
 * table call (FindClass/GetMethodID/Call.../NewStringUTF/GetStringUTFChars/
 * exception checks/...) is performed HERE, C-side, through the
 * self-declared pinned table layout (NDK r27b jni.h; offsets gated
 * at probe build time by _Static_asserts against the real header).
 * No callback bridging is needed: JNI_OnLoad itself is the consumer's;
 * objects/ids/strings cross as Int handles (B-25: never cast Int to a
 * pointer on the XIOM side; the C side casts).
 *
 * Declared surface (SPEC.md, 100% covered by the suite + probes):
 *   Loader (libjnigraphics.so + libnativehelper.so):
 *     int32 xj_load_named(bitmap_so, jvm_so)  0=ok 1=absent 2=abi
 *     int32 xj_load(void) / void xj_unload(void)
 *     const char* xj_error(void)  (cleared at entry of every helper)
 *     int32 xj_abi_missing_count / const char* xj_abi_missing
 *     int32 xj_export_count(void)              declared size (9)
 *   VM / env (consumer-supplied handles as int64):
 *     int64 xj_vm_get_env(vm, version) / xj_vm_attach_current(vm)
 *     int32 xj_vm_detach_current(vm) / int64 xj_vm_from_created(index)
 *     int64 xj_env_get_java_vm(env) / int32 xj_env_version(env)
 *   Class / refs / exceptions:
 *     int64 xj_find_class / xj_get_object_class / xj_get_superclass /
 *           xj_new_global_ref / xj_new_local_ref / xj_pop_local_frame /
 *           xj_exception_occurred
 *     int32 xj_is_assignable_from / xj_is_instance_of / xj_delete_global_ref
 *           / xj_delete_local_ref / xj_push_local_frame /
 *           xj_ensure_local_capacity / xj_exception_check /
 *           xj_throw_new / xj_throw / xj_register_native /
 *           xj_unregister_natives
 *     void  xj_exception_describe / xj_exception_clear
 *   IDs: int64 xj_get_method_id / xj_get_static_method_id /
 *              xj_get_field_id / xj_get_static_field_id
 *   Calls (A-variants; no varargs cross; fp RETURNS cross as IEEE-754
 *   bit patterns -- B-12/B-29-safe):
 *     int32 xj_call_int_method / _i / _ii / _s ; _boolean_method
 *     int64 xj_call_long_method / _double_bits_method / _d / _i /
 *           _float_bits_method / _object_method
 *     int32 xj_call_void_method
 *     static siblings: _static_int_method(+_i/_s) / _static_boolean /
 *           _static_long / _static_double_bits / _static_object /
 *           _static_void
 *   Fields: xj_get_int_field / xj_get_long_field / xj_get_double_bits_field
 *           / xj_get_object_field / xj_get_static_int_field /
 *           xj_get_static_long_field / xj_get_static_object_field /
 *           xj_set_int_field / xj_set_long_field / xj_set_object_field
 *   Strings (UTF-8; chars never cross -- copied into a bridge-owned slot):
 *     int64 xj_new_string_utf(env, utf8)
 *     int32 xj_string_utf_length / xj_string_read_utf8(env, s, max)
 *     const char* xj_string_buf_ptr(void) / int32 xj_string_buf_len(void)
 *   Arrays (int32 slots, bridge-owned, 64 entries):
 *     int32 xj_array_length / xj_get_int_array_region / xj_set_int_array_region
 *     int64 xj_new_int_array / xj_new_byte_array
 *     int32 xj_int_slot_set(i, v) / xj_int_slot_get(i)
 *   android/bitmap.h cluster (libjnigraphics.so; the info struct reads
 *   back into a bridge-owned slot per the B-series):
 *     int32 xj_bitmap_get_info(env, bitmap)   rc; fills slot
 *     int32 xj_bitmap_info_width/height/stride/format/flags/valid(void)
 *     int32 xj_bitmap_get_data_space(env, bitmap)   INT32_MIN = error
 *     int32 xj_bitmap_lock_pixels / xj_bitmap_unlock_pixels
 *     int32 xj_bitmap_write_pixel(env, bitmap, x, y, rgba)
 *     int64 xj_bitmap_read_pixel(env, bitmap, x, y)
 *     int32 xj_bitmap_is_hardware(env, bitmap)
 *     int64 xj_bitmap_get_hardware_buffer(env, bitmap)
 *     int32 xj_bitmap_compress_owned(env, bitmap, format, quality, max)
 *     int32 xj_bitmap_compressed_len / const uint8_t* _ptr
 *
 * null-safety (every helper; 0-env / 0-object / 0-vm -> typed error text
 * + documented sentinel, never a crash):
 *   0 = failed handle-returning functions; -1 = int32 status functions;
 *   INT32_MIN = xj_bitmap_get_data_space (ADATASPACE_* are >= 0).
 *   xj_error() is EMPTY after a successful call; scalar-returning calls
 *   report failure via the error text (the platform value is returned
 *   as-is otherwise).
 *
 * Classification (the suite maps it to markers):
 *   XJ_LOAD_ABSENT (1) -> SKIP  (runtime pair absent; CI stays green)
 *   XJ_LOAD_ABI    (2) -> FAIL  (present but exports broken; never silent)
 *
 * Consumer contract (the exact harness for a live env): the app's
 * JNI_OnLoad(JavaVM* vm, void* reserved) hands `vm` (as int64) to
 * xj_vm_get_env / xj_vm_attach_current; the env handle feeds every
 * env-taking helper.  A plain shell process cannot own an env (no Java
 * host) -- the on-device evidence uses an app_process dex jar whose
 * System.load triggers JNI_OnLoad (docs/repro/README.md).  xiom.jni
 * never creates a VM (JNI_CreateJavaVM is declared/ABI-checked only).
 * Single-threaded consumer contract for the bridge-owned slots, as in
 * the sibling bridge xiom.android.
 */

#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#if defined(_WIN32)
#include <windows.h>
typedef HMODULE xj_lib_t;
static xj_lib_t xj_dlopen(const char* name) { return LoadLibraryA(name); }
static void* xj_dlsym(xj_lib_t h, const char* name) {
    return h ? (void*)GetProcAddress(h, name) : 0;
}
static void xj_dlclose(xj_lib_t h) { if (h) FreeLibrary(h); }
#else
#include <dlfcn.h>
typedef void* xj_lib_t;
static xj_lib_t xj_dlopen(const char* name) { return dlopen(name, RTLD_NOW | RTLD_LOCAL); }
static void* xj_dlsym(xj_lib_t h, const char* name) { return h ? dlsym(h, name) : 0; }
static void xj_dlclose(xj_lib_t h) { if (h) dlclose(h); }
#endif

/* -- pinned ABI facts (NDK r27b jni.h + android/bitmap.h) ----------------
 * jni.h: jvalue union, JNINativeMethod, jobjectRefType values, the
 * JNINativeInterface (233 slots) and JNIInvokeInterface (8 slots) tables
 * in declared order.  First params are declared `void*` because the
 * C-side JNIEnv/JavaVM values ARE the table pointers (the header's
 * `JNIEnv*` spelling is the well-known C spec quirk).  The offsets of
 * every member used by this bridge are _Static_assert-gated against the
 * real header at probe build time (docs/repro/jni_head_probe.c). */

typedef union XJ_Value {
    uint8_t z;
    int8_t b;
    uint16_t c;
    int16_t s;
    int32_t i;
    int64_t j;
    float f;
    double d;
    void* l;
} XJ_Value;

_Static_assert(sizeof(XJ_Value) == 8, "jvalue union must be 8 bytes");

typedef struct XJ_NativeMethod {
    const char* name;
    const char* signature;
    void* fn_ptr;
} XJ_NativeMethod;

typedef struct XJ_NativeInterface {
    void* reserved0;
    void* reserved1;
    void* reserved2;
    void* reserved3;
    int32_t (*GetVersion)(void*);
    void* (*DefineClass)(void*, const char*, void*, const int8_t*, int32_t);
    void* (*FindClass)(void*, const char*);
    void* (*FromReflectedMethod)(void*, void*);
    void* (*FromReflectedField)(void*, void*);
    void* (*ToReflectedMethod)(void*, void*, void*, uint8_t);
    void* (*GetSuperclass)(void*, void*);
    uint8_t (*IsAssignableFrom)(void*, void*, void*);
    void* (*ToReflectedField)(void*, void*, void*, uint8_t);
    int32_t (*Throw)(void*, void*);
    int32_t (*ThrowNew)(void*, void*, const char*);
    void* (*ExceptionOccurred)(void*);
    void (*ExceptionDescribe)(void*);
    void (*ExceptionClear)(void*);
    void (*FatalError)(void*, const char*);
    int32_t (*PushLocalFrame)(void*, int32_t);
    void* (*PopLocalFrame)(void*, void*);
    void* (*NewGlobalRef)(void*, void*);
    void (*DeleteGlobalRef)(void*, void*);
    void (*DeleteLocalRef)(void*, void*);
    uint8_t (*IsSameObject)(void*, void*, void*);
    void* (*NewLocalRef)(void*, void*);
    int32_t (*EnsureLocalCapacity)(void*, int32_t);
    void* (*AllocObject)(void*, void*);
    void* (*NewObject)(void*, void*, void*, ...);
    void* (*NewObjectV)(void*, void*, void*, void*);
    void* (*NewObjectA)(void*, void*, void*, const XJ_Value*);
    void* (*GetObjectClass)(void*, void*);
    uint8_t (*IsInstanceOf)(void*, void*, void*);
    void* (*GetMethodID)(void*, void*, const char*, const char*);
    void* (*CallObjectMethod)(void*, void*, void*, ...);
    void* (*CallObjectMethodV)(void*, void*, void*, void*);
    void* (*CallObjectMethodA)(void*, void*, void*, const XJ_Value*);
    uint8_t (*CallBooleanMethod)(void*, void*, void*, ...);
    uint8_t (*CallBooleanMethodV)(void*, void*, void*, void*);
    uint8_t (*CallBooleanMethodA)(void*, void*, void*, const XJ_Value*);
    int8_t (*CallByteMethod)(void*, void*, void*, ...);
    int8_t (*CallByteMethodV)(void*, void*, void*, void*);
    int8_t (*CallByteMethodA)(void*, void*, void*, const XJ_Value*);
    uint16_t (*CallCharMethod)(void*, void*, void*, ...);
    uint16_t (*CallCharMethodV)(void*, void*, void*, void*);
    uint16_t (*CallCharMethodA)(void*, void*, void*, const XJ_Value*);
    int16_t (*CallShortMethod)(void*, void*, void*, ...);
    int16_t (*CallShortMethodV)(void*, void*, void*, void*);
    int16_t (*CallShortMethodA)(void*, void*, void*, const XJ_Value*);
    int32_t (*CallIntMethod)(void*, void*, void*, ...);
    int32_t (*CallIntMethodV)(void*, void*, void*, void*);
    int32_t (*CallIntMethodA)(void*, void*, void*, const XJ_Value*);
    int64_t (*CallLongMethod)(void*, void*, void*, ...);
    int64_t (*CallLongMethodV)(void*, void*, void*, void*);
    int64_t (*CallLongMethodA)(void*, void*, void*, const XJ_Value*);
    float (*CallFloatMethod)(void*, void*, void*, ...);
    float (*CallFloatMethodV)(void*, void*, void*, void*);
    float (*CallFloatMethodA)(void*, void*, void*, const XJ_Value*);
    double (*CallDoubleMethod)(void*, void*, void*, ...);
    double (*CallDoubleMethodV)(void*, void*, void*, void*);
    double (*CallDoubleMethodA)(void*, void*, void*, const XJ_Value*);
    void (*CallVoidMethod)(void*, void*, void*, ...);
    void (*CallVoidMethodV)(void*, void*, void*, void*);
    void (*CallVoidMethodA)(void*, void*, void*, const XJ_Value*);
    void* (*CallNonvirtualObjectMethod)(void*, void*, void*, void*, ...);
    void* (*CallNonvirtualObjectMethodV)(void*, void*, void*, void*, void*);
    void* (*CallNonvirtualObjectMethodA)(void*, void*, void*, void*, const XJ_Value*);
    uint8_t (*CallNonvirtualBooleanMethod)(void*, void*, void*, void*, ...);
    uint8_t (*CallNonvirtualBooleanMethodV)(void*, void*, void*, void*, void*);
    uint8_t (*CallNonvirtualBooleanMethodA)(void*, void*, void*, void*, const XJ_Value*);
    int8_t (*CallNonvirtualByteMethod)(void*, void*, void*, void*, ...);
    int8_t (*CallNonvirtualByteMethodV)(void*, void*, void*, void*, void*);
    int8_t (*CallNonvirtualByteMethodA)(void*, void*, void*, void*, const XJ_Value*);
    uint16_t (*CallNonvirtualCharMethod)(void*, void*, void*, void*, ...);
    uint16_t (*CallNonvirtualCharMethodV)(void*, void*, void*, void*, void*);
    uint16_t (*CallNonvirtualCharMethodA)(void*, void*, void*, void*, const XJ_Value*);
    int16_t (*CallNonvirtualShortMethod)(void*, void*, void*, void*, ...);
    int16_t (*CallNonvirtualShortMethodV)(void*, void*, void*, void*, void*);
    int16_t (*CallNonvirtualShortMethodA)(void*, void*, void*, void*, const XJ_Value*);
    int32_t (*CallNonvirtualIntMethod)(void*, void*, void*, void*, ...);
    int32_t (*CallNonvirtualIntMethodV)(void*, void*, void*, void*, void*);
    int32_t (*CallNonvirtualIntMethodA)(void*, void*, void*, void*, const XJ_Value*);
    int64_t (*CallNonvirtualLongMethod)(void*, void*, void*, void*, ...);
    int64_t (*CallNonvirtualLongMethodV)(void*, void*, void*, void*, void*);
    int64_t (*CallNonvirtualLongMethodA)(void*, void*, void*, void*, const XJ_Value*);
    float (*CallNonvirtualFloatMethod)(void*, void*, void*, void*, ...);
    float (*CallNonvirtualFloatMethodV)(void*, void*, void*, void*, void*);
    float (*CallNonvirtualFloatMethodA)(void*, void*, void*, void*, const XJ_Value*);
    double (*CallNonvirtualDoubleMethod)(void*, void*, void*, void*, ...);
    double (*CallNonvirtualDoubleMethodV)(void*, void*, void*, void*, void*);
    double (*CallNonvirtualDoubleMethodA)(void*, void*, void*, void*, const XJ_Value*);
    void (*CallNonvirtualVoidMethod)(void*, void*, void*, void*, ...);
    void (*CallNonvirtualVoidMethodV)(void*, void*, void*, void*, void*);
    void (*CallNonvirtualVoidMethodA)(void*, void*, void*, void*, const XJ_Value*);
    void* (*GetFieldID)(void*, void*, const char*, const char*);
    void* (*GetObjectField)(void*, void*, void*);
    uint8_t (*GetBooleanField)(void*, void*, void*);
    int8_t (*GetByteField)(void*, void*, void*);
    uint16_t (*GetCharField)(void*, void*, void*);
    int16_t (*GetShortField)(void*, void*, void*);
    int32_t (*GetIntField)(void*, void*, void*);
    int64_t (*GetLongField)(void*, void*, void*);
    float (*GetFloatField)(void*, void*, void*);
    double (*GetDoubleField)(void*, void*, void*);
    void (*SetObjectField)(void*, void*, void*, void*);
    void (*SetBooleanField)(void*, void*, void*, uint8_t);
    void (*SetByteField)(void*, void*, void*, int8_t);
    void (*SetCharField)(void*, void*, void*, uint16_t);
    void (*SetShortField)(void*, void*, void*, int16_t);
    void (*SetIntField)(void*, void*, void*, int32_t);
    void (*SetLongField)(void*, void*, void*, int64_t);
    void (*SetFloatField)(void*, void*, void*, float);
    void (*SetDoubleField)(void*, void*, void*, double);
    void* (*GetStaticMethodID)(void*, void*, const char*, const char*);
    void* (*CallStaticObjectMethod)(void*, void*, void*, ...);
    void* (*CallStaticObjectMethodV)(void*, void*, void*, void*);
    void* (*CallStaticObjectMethodA)(void*, void*, void*, const XJ_Value*);
    uint8_t (*CallStaticBooleanMethod)(void*, void*, void*, ...);
    uint8_t (*CallStaticBooleanMethodV)(void*, void*, void*, void*);
    uint8_t (*CallStaticBooleanMethodA)(void*, void*, void*, const XJ_Value*);
    int8_t (*CallStaticByteMethod)(void*, void*, void*, ...);
    int8_t (*CallStaticByteMethodV)(void*, void*, void*, void*);
    int8_t (*CallStaticByteMethodA)(void*, void*, void*, const XJ_Value*);
    uint16_t (*CallStaticCharMethod)(void*, void*, void*, ...);
    uint16_t (*CallStaticCharMethodV)(void*, void*, void*, void*);
    uint16_t (*CallStaticCharMethodA)(void*, void*, void*, const XJ_Value*);
    int16_t (*CallStaticShortMethod)(void*, void*, void*, ...);
    int16_t (*CallStaticShortMethodV)(void*, void*, void*, void*);
    int16_t (*CallStaticShortMethodA)(void*, void*, void*, const XJ_Value*);
    int32_t (*CallStaticIntMethod)(void*, void*, void*, ...);
    int32_t (*CallStaticIntMethodV)(void*, void*, void*, void*);
    int32_t (*CallStaticIntMethodA)(void*, void*, void*, const XJ_Value*);
    int64_t (*CallStaticLongMethod)(void*, void*, void*, ...);
    int64_t (*CallStaticLongMethodV)(void*, void*, void*, void*);
    int64_t (*CallStaticLongMethodA)(void*, void*, void*, const XJ_Value*);
    float (*CallStaticFloatMethod)(void*, void*, void*, ...);
    float (*CallStaticFloatMethodV)(void*, void*, void*, void*);
    float (*CallStaticFloatMethodA)(void*, void*, void*, const XJ_Value*);
    double (*CallStaticDoubleMethod)(void*, void*, void*, ...);
    double (*CallStaticDoubleMethodV)(void*, void*, void*, void*);
    double (*CallStaticDoubleMethodA)(void*, void*, void*, const XJ_Value*);
    void (*CallStaticVoidMethod)(void*, void*, void*, ...);
    void (*CallStaticVoidMethodV)(void*, void*, void*, void*);
    void (*CallStaticVoidMethodA)(void*, void*, void*, const XJ_Value*);
    void* (*GetStaticFieldID)(void*, void*, const char*, const char*);
    void* (*GetStaticObjectField)(void*, void*, void*);
    uint8_t (*GetStaticBooleanField)(void*, void*, void*);
    int8_t (*GetStaticByteField)(void*, void*, void*);
    uint16_t (*GetStaticCharField)(void*, void*, void*);
    int16_t (*GetStaticShortField)(void*, void*, void*);
    int32_t (*GetStaticIntField)(void*, void*, void*);
    int64_t (*GetStaticLongField)(void*, void*, void*);
    float (*GetStaticFloatField)(void*, void*, void*);
    double (*GetStaticDoubleField)(void*, void*, void*);
    void (*SetStaticObjectField)(void*, void*, void*, void*);
    void (*SetStaticBooleanField)(void*, void*, void*, uint8_t);
    void (*SetStaticByteField)(void*, void*, void*, int8_t);
    void (*SetStaticCharField)(void*, void*, void*, uint16_t);
    void (*SetStaticShortField)(void*, void*, void*, int16_t);
    void (*SetStaticIntField)(void*, void*, void*, int32_t);
    void (*SetStaticLongField)(void*, void*, void*, int64_t);
    void (*SetStaticFloatField)(void*, void*, void*, float);
    void (*SetStaticDoubleField)(void*, void*, void*, double);
    void* (*NewString)(void*, const uint16_t*, int32_t);
    int32_t (*GetStringLength)(void*, void*);
    const uint16_t* (*GetStringChars)(void*, void*, uint8_t*);
    void (*ReleaseStringChars)(void*, void*, const uint16_t*);
    void* (*NewStringUTF)(void*, const char*);
    int32_t (*GetStringUTFLength)(void*, void*);
    const char* (*GetStringUTFChars)(void*, void*, uint8_t*);
    void (*ReleaseStringUTFChars)(void*, void*, const char*);
    int32_t (*GetArrayLength)(void*, void*);
    void* (*NewObjectArray)(void*, int32_t, void*, void*);
    void* (*GetObjectArrayElement)(void*, void*, int32_t);
    void (*SetObjectArrayElement)(void*, void*, int32_t, void*);
    void* (*NewBooleanArray)(void*, int32_t);
    void* (*NewByteArray)(void*, int32_t);
    void* (*NewCharArray)(void*, int32_t);
    void* (*NewShortArray)(void*, int32_t);
    void* (*NewIntArray)(void*, int32_t);
    void* (*NewLongArray)(void*, int32_t);
    void* (*NewFloatArray)(void*, int32_t);
    void* (*NewDoubleArray)(void*, int32_t);
    uint8_t* (*GetBooleanArrayElements)(void*, void*, uint8_t*);
    int8_t* (*GetByteArrayElements)(void*, void*, uint8_t*);
    uint16_t* (*GetCharArrayElements)(void*, void*, uint8_t*);
    int16_t* (*GetShortArrayElements)(void*, void*, uint8_t*);
    int32_t* (*GetIntArrayElements)(void*, void*, uint8_t*);
    int64_t* (*GetLongArrayElements)(void*, void*, uint8_t*);
    float* (*GetFloatArrayElements)(void*, void*, uint8_t*);
    double* (*GetDoubleArrayElements)(void*, void*, uint8_t*);
    void (*ReleaseBooleanArrayElements)(void*, void*, uint8_t*, int32_t);
    void (*ReleaseByteArrayElements)(void*, void*, int8_t*, int32_t);
    void (*ReleaseCharArrayElements)(void*, void*, uint16_t*, int32_t);
    void (*ReleaseShortArrayElements)(void*, void*, int16_t*, int32_t);
    void (*ReleaseIntArrayElements)(void*, void*, int32_t*, int32_t);
    void (*ReleaseLongArrayElements)(void*, void*, int64_t*, int32_t);
    void (*ReleaseFloatArrayElements)(void*, void*, float*, int32_t);
    void (*ReleaseDoubleArrayElements)(void*, void*, double*, int32_t);
    void (*GetBooleanArrayRegion)(void*, void*, int32_t, int32_t, uint8_t*);
    void (*GetByteArrayRegion)(void*, void*, int32_t, int32_t, int8_t*);
    void (*GetCharArrayRegion)(void*, void*, int32_t, int32_t, uint16_t*);
    void (*GetShortArrayRegion)(void*, void*, int32_t, int32_t, int16_t*);
    void (*GetIntArrayRegion)(void*, void*, int32_t, int32_t, int32_t*);
    void (*GetLongArrayRegion)(void*, void*, int32_t, int32_t, int64_t*);
    void (*GetFloatArrayRegion)(void*, void*, int32_t, int32_t, float*);
    void (*GetDoubleArrayRegion)(void*, void*, int32_t, int32_t, double*);
    void (*SetBooleanArrayRegion)(void*, void*, int32_t, int32_t, const uint8_t*);
    void (*SetByteArrayRegion)(void*, void*, int32_t, int32_t, const int8_t*);
    void (*SetCharArrayRegion)(void*, void*, int32_t, int32_t, const uint16_t*);
    void (*SetShortArrayRegion)(void*, void*, int32_t, int32_t, const int16_t*);
    void (*SetIntArrayRegion)(void*, void*, int32_t, int32_t, const int32_t*);
    void (*SetLongArrayRegion)(void*, void*, int32_t, int32_t, const int64_t*);
    void (*SetFloatArrayRegion)(void*, void*, int32_t, int32_t, const float*);
    void (*SetDoubleArrayRegion)(void*, void*, int32_t, int32_t, const double*);
    int32_t (*RegisterNatives)(void*, void*, const XJ_NativeMethod*, int32_t);
    int32_t (*UnregisterNatives)(void*, void*);
    int32_t (*MonitorEnter)(void*, void*);
    int32_t (*MonitorExit)(void*, void*);
    int32_t (*GetJavaVM)(void*, void**);
    void (*GetStringRegion)(void*, void*, int32_t, int32_t, uint16_t*);
    void (*GetStringUTFRegion)(void*, void*, int32_t, int32_t, char*);
    void* (*GetPrimitiveArrayCritical)(void*, void*, uint8_t*);
    void (*ReleasePrimitiveArrayCritical)(void*, void*, void*, int32_t);
    const uint16_t* (*GetStringCritical)(void*, void*, uint8_t*);
    void (*ReleaseStringCritical)(void*, void*, const uint16_t*);
    void* (*NewWeakGlobalRef)(void*, void*);
    void (*DeleteWeakGlobalRef)(void*, void*);
    uint8_t (*ExceptionCheck)(void*);
    void* (*NewDirectByteBuffer)(void*, void*, int64_t);
    void* (*GetDirectBufferAddress)(void*, void*);
    int64_t (*GetDirectBufferCapacity)(void*, void*);
    int32_t (*GetObjectRefType)(void*, void*);
} XJ_NativeInterface;

/* JNIInvokeInterface (jni.h): 3 reserved + 5 members. */
typedef struct XJ_InvokeInterface {
    void* reserved0;
    void* reserved1;
    void* reserved2;
    int32_t (*DestroyJavaVM)(void*);
    int32_t (*AttachCurrentThread)(void*, void**, void*);
    int32_t (*DetachCurrentThread)(void*);
    int32_t (*GetEnv)(void*, void**, int32_t);
    int32_t (*AttachCurrentThreadAsDaemon)(void*, void**, void*);
} XJ_InvokeInterface;

/* AndroidBitmapInfo (android/bitmap.h): 20 bytes. */
typedef struct XJ_BitmapInfo {
    uint32_t width;
    uint32_t height;
    uint32_t stride;
    int32_t format;
    uint32_t flags;
} XJ_BitmapInfo;

/* JavaVMAttachArgs (jni.h): version, name, group. */
typedef struct XJ_AttachArgs {
    int32_t version;
    const char* name;
    void* group;
} XJ_AttachArgs;

/* -- bridge state -------------------------------------------------------- */

#define XJ_INT32_MIN (-2147483647 - 1)

static xj_lib_t g_bitmap = 0;
static xj_lib_t g_nativehelper = 0;
static char g_error[512] = {0};
static char g_missing[512] = {0};
static int g_missing_count = 0;

/* Strings: UTF-8 chars are copied into this owned slot; the pointer is
 * handed out for Str::from_c_str; no char pointer ever crosses (B-25). */
#define XJ_STRING_BUF_SIZE 4096
static char g_string_buf[XJ_STRING_BUF_SIZE] = {0};
static int32_t g_string_len = 0;

/* int32 slots for array regions (bridge-owned; B-series discipline). */
#define XJ_INT_SLOT_COUNT 64
static int32_t g_int_slots[XJ_INT_SLOT_COUNT] = {0};

/* The last AndroidBitmap_getInfo read-back (owned slot; accessors). */
static XJ_BitmapInfo g_bitmap_info = {0};
static int32_t g_bitmap_info_valid = 0;

/* Manual lock state (xj_bitmap_lock_pixels / unlock_pixels); the pixel
 * address NEVER crosses the boundary (B-25): it stays here. */
static void* g_bitmap_lock_addr = 0;
static int32_t g_bitmap_lock_active = 0;
static void* g_bitmap_lock_bitmap = 0;

/* Compressed output of xj_bitmap_compress_owned (owned slot). */
#define XJ_COMPRESS_BUF_SIZE 16384
static uint8_t g_compress_buf[XJ_COMPRESS_BUF_SIZE] = {0};
static int32_t g_compress_len = 0;
static int32_t g_compress_cap = 0;

static void xj_clear_error(void) { g_error[0] = 0; }

static void xj_set_error(const char* msg) {
    snprintf(g_error, sizeof(g_error), "%s", msg);
}

static void xj_set_errorf(const char* fmt, int32_t a) {
    snprintf(g_error, sizeof(g_error), fmt, a);
}

/* Enrich the recorded error when a call failed AND a JNI exception is
 * pending (never clears it; the consumer decides).  `env` is the raw
 * handle; the table is its first word (see the handle-cast notes). */
static void xj_note_exception(void* env) {
    if (!env) return;
    XJ_NativeInterface* t = *(XJ_NativeInterface**)env;
    if (t->ExceptionCheck && t->ExceptionCheck(env)) {
        size_t used = strlen(g_error);
        snprintf(g_error + used, sizeof(g_error) - used,
                 "%s + pending JNI exception", used ? ";" : "");
    }
}

/* -- libjnigraphics + libnativehelper function pointers ------------------- */

typedef int (*PFN_bitmap_get_info)(void*, void*, XJ_BitmapInfo*);
typedef int32_t (*PFN_bitmap_get_data_space)(void*, void*);
typedef int (*PFN_bitmap_lock_pixels)(void*, void*, void**);
typedef int (*PFN_bitmap_unlock_pixels)(void*, void*);
typedef uint8_t (*PFN_bitmap_compress_write)(void*, const void*, size_t);
typedef int (*PFN_bitmap_compress)(const XJ_BitmapInfo*, int32_t, const void*,
                                   int32_t, int32_t, void*,
                                   PFN_bitmap_compress_write);
typedef int (*PFN_bitmap_get_hwb)(void*, void*, void**);
typedef int32_t (*PFN_jni_get_created_vms)(void**, int32_t, int32_t*);

static PFN_bitmap_get_info p_bitmap_get_info = 0;
static PFN_bitmap_get_data_space p_bitmap_get_data_space = 0;
static PFN_bitmap_lock_pixels p_bitmap_lock_pixels = 0;
static PFN_bitmap_unlock_pixels p_bitmap_unlock_pixels = 0;
static PFN_bitmap_compress p_bitmap_compress = 0;
static PFN_bitmap_get_hwb p_bitmap_get_hwb = 0;
static PFN_jni_get_created_vms p_jni_get_created_vms = 0;

/* Declared export set: android/bitmap.h (6 libjnigraphics.so exports) +
 * the three VM entry points of jni.h exported by libnativehelper.so.
 * AImageDecoder_/AFileDescriptor_ belong to other headers/slices and
 * are out of this head (SPEC.md). */
static const char* k_export_set[] = {
    "AndroidBitmap_getInfo",
    "AndroidBitmap_getDataSpace",
    "AndroidBitmap_lockPixels",
    "AndroidBitmap_unlockPixels",
    "AndroidBitmap_compress",
    "AndroidBitmap_getHardwareBuffer",
    "JNI_GetDefaultJavaVMInitArgs",
    "JNI_CreateJavaVM",
    "JNI_GetCreatedJavaVMs",
};
#define XJ_EXPORT_COUNT (sizeof(k_export_set) / sizeof(k_export_set[0]))
_Static_assert(XJ_EXPORT_COUNT == 9,
               "export-set drift: update the suite/SPEC counts with the set");

/* Every symbol is tried against both libraries (re-export layouts differ
 * across API levels; the platform stubs and device libs agree here). */
static void* xj_resolve(const char* name) {
    void* p = xj_dlsym(g_bitmap, name);
    if (!p) p = xj_dlsym(g_nativehelper, name);
    return p;
}

static int xj_finish_load(void) {
    g_missing_count = 0;
    g_missing[0] = 0;
    for (size_t i = 0; i < XJ_EXPORT_COUNT; i++) {
        if (!xj_resolve(k_export_set[i])) {
            size_t used = strlen(g_missing);
            snprintf(g_missing + used, sizeof(g_missing) - used, "%s%s",
                     used ? "," : "", k_export_set[i]);
            g_missing_count++;
        }
    }
    p_bitmap_get_info = (PFN_bitmap_get_info)xj_resolve("AndroidBitmap_getInfo");
    p_bitmap_get_data_space =
        (PFN_bitmap_get_data_space)xj_resolve("AndroidBitmap_getDataSpace");
    p_bitmap_lock_pixels =
        (PFN_bitmap_lock_pixels)xj_resolve("AndroidBitmap_lockPixels");
    p_bitmap_unlock_pixels =
        (PFN_bitmap_unlock_pixels)xj_resolve("AndroidBitmap_unlockPixels");
    p_bitmap_compress = (PFN_bitmap_compress)xj_resolve("AndroidBitmap_compress");
    p_bitmap_get_hwb =
        (PFN_bitmap_get_hwb)xj_resolve("AndroidBitmap_getHardwareBuffer");
    p_jni_get_created_vms =
        (PFN_jni_get_created_vms)xj_resolve("JNI_GetCreatedJavaVMs");
    if (g_missing_count != 0) {
        xj_set_error(g_missing);
        return 2;
    }
    xj_clear_error();
    return 0;
}

void xj_unload(void); /* forward: used by xj_load_pair */

static int xj_load_pair(const char* bitmap_soname, const char* nativehelper_soname) {
    xj_unload();
    g_bitmap = xj_dlopen(bitmap_soname);
    g_nativehelper = xj_dlopen(nativehelper_soname);
    if (!g_bitmap || !g_nativehelper) {
        /* The seam requires the pair: a partial platform (e.g. a device
         * below API 31 without libnativehelper.so) classifies ABSENT with
         * the absent soname(s) recorded; present-but-broken is only
         * diagnosed when both load (never a false green either way). */
        snprintf(g_error, sizeof(g_error), "absent pair:%s%s%s%s%s",
                 g_bitmap ? "" : " ", g_bitmap ? "" : bitmap_soname,
                 (!g_bitmap && !g_nativehelper) ? " +" : "",
                 g_nativehelper ? "" : " ",
                 g_nativehelper ? "" : nativehelper_soname);
        return 1;
    }
    return xj_finish_load();
}

int xj_load_named(const char* bitmap_soname, const char* nativehelper_soname) {
    if (!bitmap_soname || !nativehelper_soname) {
        xj_clear_error();
        xj_set_error("null soname");
        return 2;
    }
    return xj_load_pair(bitmap_soname, nativehelper_soname);
}

int xj_load(void) {
    return xj_load_pair("libjnigraphics.so", "libnativehelper.so");
}

const char* xj_error(void) { return g_error; }

int xj_abi_missing_count(void) { return g_missing_count; }

const char* xj_abi_missing(void) { return g_missing; }

int32_t xj_export_count(void) { return (int32_t)XJ_EXPORT_COUNT; }

void xj_unload(void) {
    xj_dlclose(g_bitmap);
    xj_dlclose(g_nativehelper);
    g_bitmap = 0;
    g_nativehelper = 0;
    p_bitmap_get_info = 0;
    p_bitmap_get_data_space = 0;
    p_bitmap_lock_pixels = 0;
    p_bitmap_unlock_pixels = 0;
    p_bitmap_compress = 0;
    p_bitmap_get_hwb = 0;
    p_jni_get_created_vms = 0;
    g_missing_count = 0;
    g_missing[0] = 0;
    g_bitmap_lock_addr = 0;
    g_bitmap_lock_active = 0;
    g_bitmap_lock_bitmap = 0;
    xj_clear_error();
}

/* -- probe-only ABI diagnostics ------------------------------------------
 * Numeric offsets/sizes of the self-declared layout, so the on-device
 * probe can gate every member the bridge touches against the REAL
 * header's offsetof at runtime (the probe also _Static_asserts the
 * header side, so a mismatch cannot pass).  Not part of the XIOM
 * module surface; SPEC.md records them as bridge diagnostics. */

int32_t xj_abi_sizeof_table(void) { return (int32_t)sizeof(XJ_NativeInterface); }
int32_t xj_abi_sizeof_value(void) { return (int32_t)sizeof(XJ_Value); }
int32_t xj_abi_sizeof_native_method(void) { return (int32_t)sizeof(XJ_NativeMethod); }
int32_t xj_abi_sizeof_bitmap_info(void) { return (int32_t)sizeof(XJ_BitmapInfo); }
int32_t xj_abi_sizeof_invoke(void) { return (int32_t)sizeof(XJ_InvokeInterface); }

int32_t xj_abi_offset(int32_t which) {
    switch (which) {
    case 0: return (int32_t)offsetof(XJ_NativeInterface, GetVersion);
    case 1: return (int32_t)offsetof(XJ_NativeInterface, FindClass);
    case 2: return (int32_t)offsetof(XJ_NativeInterface, GetSuperclass);
    case 3: return (int32_t)offsetof(XJ_NativeInterface, IsAssignableFrom);
    case 4: return (int32_t)offsetof(XJ_NativeInterface, ThrowNew);
    case 5: return (int32_t)offsetof(XJ_NativeInterface, ExceptionOccurred);
    case 6: return (int32_t)offsetof(XJ_NativeInterface, ExceptionClear);
    case 7: return (int32_t)offsetof(XJ_NativeInterface, PushLocalFrame);
    case 8: return (int32_t)offsetof(XJ_NativeInterface, PopLocalFrame);
    case 9: return (int32_t)offsetof(XJ_NativeInterface, NewGlobalRef);
    case 10: return (int32_t)offsetof(XJ_NativeInterface, DeleteGlobalRef);
    case 11: return (int32_t)offsetof(XJ_NativeInterface, DeleteLocalRef);
    case 12: return (int32_t)offsetof(XJ_NativeInterface, NewLocalRef);
    case 13: return (int32_t)offsetof(XJ_NativeInterface, EnsureLocalCapacity);
    case 14: return (int32_t)offsetof(XJ_NativeInterface, GetObjectClass);
    case 15: return (int32_t)offsetof(XJ_NativeInterface, IsInstanceOf);
    case 16: return (int32_t)offsetof(XJ_NativeInterface, GetMethodID);
    case 17: return (int32_t)offsetof(XJ_NativeInterface, CallObjectMethodA);
    case 18: return (int32_t)offsetof(XJ_NativeInterface, CallBooleanMethodA);
    case 19: return (int32_t)offsetof(XJ_NativeInterface, CallIntMethodA);
    case 20: return (int32_t)offsetof(XJ_NativeInterface, CallLongMethodA);
    case 21: return (int32_t)offsetof(XJ_NativeInterface, CallFloatMethodA);
    case 22: return (int32_t)offsetof(XJ_NativeInterface, CallDoubleMethodA);
    case 23: return (int32_t)offsetof(XJ_NativeInterface, CallVoidMethodA);
    case 24: return (int32_t)offsetof(XJ_NativeInterface, GetFieldID);
    case 25: return (int32_t)offsetof(XJ_NativeInterface, GetObjectField);
    case 26: return (int32_t)offsetof(XJ_NativeInterface, GetIntField);
    case 27: return (int32_t)offsetof(XJ_NativeInterface, GetLongField);
    case 28: return (int32_t)offsetof(XJ_NativeInterface, GetDoubleField);
    case 29: return (int32_t)offsetof(XJ_NativeInterface, SetObjectField);
    case 30: return (int32_t)offsetof(XJ_NativeInterface, SetIntField);
    case 31: return (int32_t)offsetof(XJ_NativeInterface, SetLongField);
    case 32: return (int32_t)offsetof(XJ_NativeInterface, GetStaticMethodID);
    case 33: return (int32_t)offsetof(XJ_NativeInterface, CallStaticObjectMethodA);
    case 34: return (int32_t)offsetof(XJ_NativeInterface, CallStaticBooleanMethodA);
    case 35: return (int32_t)offsetof(XJ_NativeInterface, CallStaticIntMethodA);
    case 36: return (int32_t)offsetof(XJ_NativeInterface, CallStaticLongMethodA);
    case 37: return (int32_t)offsetof(XJ_NativeInterface, CallStaticDoubleMethodA);
    case 38: return (int32_t)offsetof(XJ_NativeInterface, CallStaticVoidMethodA);
    case 39: return (int32_t)offsetof(XJ_NativeInterface, GetStaticObjectField);
    case 40: return (int32_t)offsetof(XJ_NativeInterface, GetStaticIntField);
    case 41: return (int32_t)offsetof(XJ_NativeInterface, GetStaticLongField);
    case 42: return (int32_t)offsetof(XJ_NativeInterface, NewStringUTF);
    case 43: return (int32_t)offsetof(XJ_NativeInterface, GetStringUTFLength);
    case 44: return (int32_t)offsetof(XJ_NativeInterface, GetStringUTFChars);
    case 45: return (int32_t)offsetof(XJ_NativeInterface, ReleaseStringUTFChars);
    case 46: return (int32_t)offsetof(XJ_NativeInterface, GetArrayLength);
    case 47: return (int32_t)offsetof(XJ_NativeInterface, NewIntArray);
    case 48: return (int32_t)offsetof(XJ_NativeInterface, NewByteArray);
    case 49: return (int32_t)offsetof(XJ_NativeInterface, GetIntArrayRegion);
    case 50: return (int32_t)offsetof(XJ_NativeInterface, SetIntArrayRegion);
    case 51: return (int32_t)offsetof(XJ_NativeInterface, RegisterNatives);
    case 52: return (int32_t)offsetof(XJ_NativeInterface, UnregisterNatives);
    case 53: return (int32_t)offsetof(XJ_NativeInterface, GetJavaVM);
    case 54: return (int32_t)offsetof(XJ_NativeInterface, ExceptionCheck);
    case 55: return (int32_t)offsetof(XJ_NativeInterface, GetObjectRefType);
    default: return -1;
    }
}

int32_t xj_abi_invoke_offset(int32_t which) {
    switch (which) {
    case 0: return (int32_t)offsetof(XJ_InvokeInterface, AttachCurrentThread);
    case 1: return (int32_t)offsetof(XJ_InvokeInterface, DetachCurrentThread);
    case 2: return (int32_t)offsetof(XJ_InvokeInterface, GetEnv);
    default: return -1;
    }
}

int32_t xj_abi_bitmap_info_offset(int32_t which) {
    switch (which) {
    case 0: return (int32_t)offsetof(XJ_BitmapInfo, width);
    case 1: return (int32_t)offsetof(XJ_BitmapInfo, height);
    case 2: return (int32_t)offsetof(XJ_BitmapInfo, stride);
    case 3: return (int32_t)offsetof(XJ_BitmapInfo, format);
    case 4: return (int32_t)offsetof(XJ_BitmapInfo, flags);
    default: return -1;
    }
}

int32_t xj_abi_native_method_offset(int32_t which) {
    switch (which) {
    case 0: return (int32_t)offsetof(XJ_NativeMethod, name);
    case 1: return (int32_t)offsetof(XJ_NativeMethod, signature);
    case 2: return (int32_t)offsetof(XJ_NativeMethod, fn_ptr);
    default: return -1;
    }
}

/* -- handle casts + guards ------------------------------------------------
 * JNI C mapping: an env/vm handle is a pointer to the interface-holder
 * struct whose FIRST WORD is the table pointer (exactly what the
 * `(*env)->FindClass(env, ...)` / `(*vm)->GetEnv(vm, ...)` idioms read).
 * The bridge dereferences once for the table and passes the handle
 * ITSELF as the first table argument (what ART expects: it reinterprets
 * the parameter as its env/vm outer object).  Null handles are rejected
 * before any dereference; a non-null garbage handle is outside the
 * consumer contract (documented in SPEC.md). */

static XJ_NativeInterface* xj_env_tbl(int64_t env) {
    return *(XJ_NativeInterface**)(intptr_t)env;
}

static XJ_InvokeInterface* xj_vm_tbl(int64_t vm) {
    return *(XJ_InvokeInterface**)(intptr_t)vm;
}

#define XJ_REQUIRE_ENV(env, ret)                                          \
    do {                                                                  \
        if ((env) == 0) {                                                 \
            xj_set_error("null JNIEnv handle (consumer supplies the env " \
                         "from JNI_OnLoad)");                             \
            return (ret);                                                 \
        }                                                                 \
    } while (0)

#define XJ_REQUIRE_OBJ(env, obj, what, ret)                               \
    do {                                                                  \
        if ((env) == 0) {                                                 \
            xj_set_error("null JNIEnv handle (consumer supplies the env " \
                         "from JNI_OnLoad)");                             \
            return (ret);                                                 \
        }                                                                 \
        if ((obj) == 0) {                                                 \
            xj_set_error("null " what " handle");                         \
            return (ret);                                                 \
        }                                                                 \
    } while (0)

/* -- VM / env ------------------------------------------------------------ */

int64_t xj_vm_get_env(int64_t vm, int32_t version) {
    xj_clear_error();
    if (!vm) { xj_set_error("null JavaVM handle"); return 0; }
    void* out = 0;
    int32_t rc = xj_vm_tbl(vm)->GetEnv((void*)(intptr_t)vm, &out, version);
    if (rc != 0) {
        snprintf(g_error, sizeof(g_error),
                 "GetEnv rc=%d (JNI_EDETACHED=-2; use xj_vm_attach_current)", rc);
        return 0;
    }
    if (!out) { xj_set_error("GetEnv returned a null JNIEnv"); return 0; }
    return (int64_t)(intptr_t)out;
}

int64_t xj_vm_attach_current(int64_t vm) {
    xj_clear_error();
    if (!vm) { xj_set_error("null JavaVM handle"); return 0; }
    XJ_AttachArgs args;
    args.version = 0x00010006; /* JNI_VERSION_1_6 */
    args.name = "xiom-jni";
    args.group = 0;
    void* out = 0;
    int32_t rc = xj_vm_tbl(vm)->AttachCurrentThread((void*)(intptr_t)vm, &out, &args);
    if (rc != 0) { xj_set_errorf("AttachCurrentThread rc=%d", rc); return 0; }
    if (!out) { xj_set_error("AttachCurrentThread returned a null JNIEnv"); return 0; }
    return (int64_t)(intptr_t)out;
}

int32_t xj_vm_detach_current(int64_t vm) {
    xj_clear_error();
    if (!vm) { xj_set_error("null JavaVM handle"); return -1; }
    int32_t rc = xj_vm_tbl(vm)->DetachCurrentThread((void*)(intptr_t)vm);
    if (rc != 0) { xj_set_errorf("DetachCurrentThread rc=%d", rc); return -1; }
    return 0;
}

int64_t xj_vm_from_created(int32_t index) {
    xj_clear_error();
    if (!p_jni_get_created_vms) {
        xj_set_error("JNI_GetCreatedJavaVMs unresolved "
                     "(libnativehelper.so absent; call jni_probe first)");
        return 0;
    }
    void* vms[4];
    int32_t n = 0;
    int32_t rc = p_jni_get_created_vms(vms, 4, &n);
    if (rc != 0) { xj_set_errorf("JNI_GetCreatedJavaVMs rc=%d", rc); return 0; }
    if (index < 0 || index >= n) {
        snprintf(g_error, sizeof(g_error),
                 "no JavaVM at index %d (created count %d)", index, n);
        return 0;
    }
    return (int64_t)(intptr_t)vms[index];
}

int64_t xj_env_get_java_vm(int64_t env) {
    xj_clear_error();
    XJ_REQUIRE_ENV(env, 0);
    void* out = 0;
    int32_t rc = xj_env_tbl(env)->GetJavaVM((void*)(intptr_t)env, &out);
    if (rc != 0 || !out) { xj_set_errorf("GetJavaVM rc=%d", rc); return 0; }
    return (int64_t)(intptr_t)out;
}

int32_t xj_env_version(int64_t env) {
    xj_clear_error();
    XJ_REQUIRE_ENV(env, -1);
    return xj_env_tbl(env)->GetVersion((void*)(intptr_t)env);
}

/* -- class / refs / exceptions ------------------------------------------- */

int64_t xj_find_class(int64_t env, const char* name) {
    xj_clear_error();
    XJ_REQUIRE_ENV(env, 0);
    if (!name) { xj_set_error("null class name"); return 0; }
    void* cls = xj_env_tbl(env)->FindClass((void*)(intptr_t)env, name);
    if (!cls) {
        xj_set_error("FindClass returned null (class not found / loader)");
        xj_note_exception((void*)(intptr_t)env);
        return 0;
    }
    return (int64_t)(intptr_t)cls;
}

int64_t xj_get_object_class(int64_t env, int64_t obj) {
    xj_clear_error();
    XJ_REQUIRE_OBJ(env, obj, "object", 0);
    void* cls = xj_env_tbl(env)->GetObjectClass((void*)(intptr_t)env,
                                                (void*)(intptr_t)obj);
    if (!cls) { xj_set_error("GetObjectClass returned null"); return 0; }
    return (int64_t)(intptr_t)cls;
}

int64_t xj_get_superclass(int64_t env, int64_t clazz) {
    xj_clear_error();
    XJ_REQUIRE_OBJ(env, clazz, "class", 0);
    void* sup = xj_env_tbl(env)->GetSuperclass((void*)(intptr_t)env,
                                               (void*)(intptr_t)clazz);
    if (!sup) { xj_set_error("GetSuperclass returned null (Object or error)"); return 0; }
    return (int64_t)(intptr_t)sup;
}

int32_t xj_is_assignable_from(int64_t env, int64_t c1, int64_t c2) {
    xj_clear_error();
    XJ_REQUIRE_ENV(env, -1);
    if (!c1 || !c2) { xj_set_error("null class handle"); return -1; }
    return xj_env_tbl(env)->IsAssignableFrom((void*)(intptr_t)env,
                                             (void*)(intptr_t)c1,
                                             (void*)(intptr_t)c2);
}

int32_t xj_is_instance_of(int64_t env, int64_t obj, int64_t clazz) {
    xj_clear_error();
    XJ_REQUIRE_ENV(env, -1);
    if (!obj || !clazz) { xj_set_error("null object/class handle"); return -1; }
    return xj_env_tbl(env)->IsInstanceOf((void*)(intptr_t)env,
                                         (void*)(intptr_t)obj,
                                         (void*)(intptr_t)clazz);
}

int64_t xj_new_global_ref(int64_t env, int64_t obj) {
    xj_clear_error();
    XJ_REQUIRE_OBJ(env, obj, "object", 0);
    void* ref = xj_env_tbl(env)->NewGlobalRef((void*)(intptr_t)env,
                                              (void*)(intptr_t)obj);
    if (!ref) { xj_set_error("NewGlobalRef returned null (OOM / exception)"); return 0; }
    return (int64_t)(intptr_t)ref;
}

int32_t xj_delete_global_ref(int64_t env, int64_t ref) {
    xj_clear_error();
    XJ_REQUIRE_ENV(env, -1);
    if (!ref) { xj_set_error("null global ref handle"); return -1; }
    xj_env_tbl(env)->DeleteGlobalRef((void*)(intptr_t)env, (void*)(intptr_t)ref);
    return 0;
}

int32_t xj_delete_local_ref(int64_t env, int64_t ref) {
    xj_clear_error();
    XJ_REQUIRE_ENV(env, -1);
    if (!ref) { xj_set_error("null local ref handle"); return -1; }
    xj_env_tbl(env)->DeleteLocalRef((void*)(intptr_t)env, (void*)(intptr_t)ref);
    return 0;
}

int64_t xj_new_local_ref(int64_t env, int64_t ref) {
    xj_clear_error();
    XJ_REQUIRE_OBJ(env, ref, "object", 0);
    void* lref = xj_env_tbl(env)->NewLocalRef((void*)(intptr_t)env,
                                              (void*)(intptr_t)ref);
    if (!lref) { xj_set_error("NewLocalRef returned null"); return 0; }
    return (int64_t)(intptr_t)lref;
}

int32_t xj_push_local_frame(int64_t env, int32_t capacity) {
    xj_clear_error();
    XJ_REQUIRE_ENV(env, -1);
    int32_t rc = xj_env_tbl(env)->PushLocalFrame((void*)(intptr_t)env, capacity);
    if (rc != 0) { xj_set_errorf("PushLocalFrame rc=%d", rc); return -1; }
    return 0;
}

int64_t xj_pop_local_frame(int64_t env, int64_t result) {
    xj_clear_error();
    XJ_REQUIRE_ENV(env, 0);
    return (int64_t)(intptr_t)xj_env_tbl(env)->PopLocalFrame(
        (void*)(intptr_t)env, (void*)(intptr_t)result);
}

int32_t xj_ensure_local_capacity(int64_t env, int32_t capacity) {
    xj_clear_error();
    XJ_REQUIRE_ENV(env, -1);
    int32_t rc = xj_env_tbl(env)->EnsureLocalCapacity((void*)(intptr_t)env, capacity);
    if (rc != 0) { xj_set_errorf("EnsureLocalCapacity rc=%d", rc); return -1; }
    return 0;
}

int32_t xj_exception_check(int64_t env) {
    xj_clear_error();
    XJ_REQUIRE_ENV(env, -1);
    return xj_env_tbl(env)->ExceptionCheck((void*)(intptr_t)env) ? 1 : 0;
}

int64_t xj_exception_occurred(int64_t env) {
    xj_clear_error();
    XJ_REQUIRE_ENV(env, 0);
    /* 0 = no exception; on error see xj_error() (env was null). */
    return (int64_t)(intptr_t)xj_env_tbl(env)->ExceptionOccurred((void*)(intptr_t)env);
}

void xj_exception_describe(int64_t env) {
    xj_clear_error();
    if (!env) { xj_set_error("null JNIEnv handle"); return; }
    xj_env_tbl(env)->ExceptionDescribe((void*)(intptr_t)env);
}

void xj_exception_clear(int64_t env) {
    xj_clear_error();
    if (!env) { xj_set_error("null JNIEnv handle"); return; }
    xj_env_tbl(env)->ExceptionClear((void*)(intptr_t)env);
}

int32_t xj_throw_new(int64_t env, int64_t clazz, const char* msg) {
    xj_clear_error();
    XJ_REQUIRE_ENV(env, -1);
    if (!clazz) { xj_set_error("null class handle"); return -1; }
    int32_t rc = xj_env_tbl(env)->ThrowNew((void*)(intptr_t)env,
                                           (void*)(intptr_t)clazz, msg);
    if (rc != 0) { xj_set_errorf("ThrowNew rc=%d", rc); return -1; }
    return 0;
}

int32_t xj_throw(int64_t env, int64_t throwable) {
    xj_clear_error();
    XJ_REQUIRE_ENV(env, -1);
    if (!throwable) { xj_set_error("null throwable handle"); return -1; }
    int32_t rc = xj_env_tbl(env)->Throw((void*)(intptr_t)env,
                                        (void*)(intptr_t)throwable);
    if (rc != 0) { xj_set_errorf("Throw rc=%d", rc); return -1; }
    return 0;
}

int32_t xj_register_native(int64_t env, int64_t clazz, const char* name,
                           const char* signature, int64_t fn_ptr) {
    xj_clear_error();
    XJ_REQUIRE_ENV(env, -1);
    if (!clazz) { xj_set_error("null class handle"); return -1; }
    if (!name || !signature || !fn_ptr) {
        xj_set_error("null native method name/signature/function pointer");
        return -1;
    }
    XJ_NativeMethod m;
    m.name = name;
    m.signature = signature;
    m.fn_ptr = (void*)(intptr_t)fn_ptr;
    int32_t rc = xj_env_tbl(env)->RegisterNatives((void*)(intptr_t)env,
                                                  (void*)(intptr_t)clazz, &m, 1);
    if (rc != 0) {
        xj_set_errorf("RegisterNatives rc=%d", rc);
        xj_note_exception((void*)(intptr_t)env);
        return -1;
    }
    return 0;
}

int32_t xj_unregister_natives(int64_t env, int64_t clazz) {
    xj_clear_error();
    XJ_REQUIRE_ENV(env, -1);
    if (!clazz) { xj_set_error("null class handle"); return -1; }
    int32_t rc = xj_env_tbl(env)->UnregisterNatives((void*)(intptr_t)env,
                                                    (void*)(intptr_t)clazz);
    if (rc != 0) { xj_set_errorf("UnregisterNatives rc=%d", rc); return -1; }
    return 0;
}

/* -- IDs ----------------------------------------------------------------- */

int64_t xj_get_method_id(int64_t env, int64_t clazz, const char* name,
                         const char* sig) {
    xj_clear_error();
    XJ_REQUIRE_ENV(env, 0);
    if (!clazz || !name || !sig) { xj_set_error("null class/name/signature"); return 0; }
    void* mid = xj_env_tbl(env)->GetMethodID((void*)(intptr_t)env,
                                             (void*)(intptr_t)clazz, name, sig);
    if (!mid) {
        xj_set_error("GetMethodID returned null (NoSuchMethodError)");
        xj_note_exception((void*)(intptr_t)env);
        return 0;
    }
    return (int64_t)(intptr_t)mid;
}

int64_t xj_get_static_method_id(int64_t env, int64_t clazz, const char* name,
                                const char* sig) {
    xj_clear_error();
    XJ_REQUIRE_ENV(env, 0);
    if (!clazz || !name || !sig) { xj_set_error("null class/name/signature"); return 0; }
    void* mid = xj_env_tbl(env)->GetStaticMethodID((void*)(intptr_t)env,
                                                   (void*)(intptr_t)clazz, name, sig);
    if (!mid) {
        xj_set_error("GetStaticMethodID returned null (NoSuchMethodError)");
        xj_note_exception((void*)(intptr_t)env);
        return 0;
    }
    return (int64_t)(intptr_t)mid;
}

int64_t xj_get_field_id(int64_t env, int64_t clazz, const char* name,
                        const char* sig) {
    xj_clear_error();
    XJ_REQUIRE_ENV(env, 0);
    if (!clazz || !name || !sig) { xj_set_error("null class/name/signature"); return 0; }
    void* fid = xj_env_tbl(env)->GetFieldID((void*)(intptr_t)env,
                                            (void*)(intptr_t)clazz, name, sig);
    if (!fid) {
        xj_set_error("GetFieldID returned null (NoSuchFieldError)");
        xj_note_exception((void*)(intptr_t)env);
        return 0;
    }
    return (int64_t)(intptr_t)fid;
}

int64_t xj_get_static_field_id(int64_t env, int64_t clazz, const char* name,
                               const char* sig) {
    xj_clear_error();
    XJ_REQUIRE_ENV(env, 0);
    if (!clazz || !name || !sig) { xj_set_error("null class/name/signature"); return 0; }
    void* fid = xj_env_tbl(env)->GetStaticFieldID((void*)(intptr_t)env,
                                                  (void*)(intptr_t)clazz, name, sig);
    if (!fid) {
        xj_set_error("GetStaticFieldID returned null (NoSuchFieldError)");
        xj_note_exception((void*)(intptr_t)env);
        return 0;
    }
    return (int64_t)(intptr_t)fid;
}

/* -- calls (instance) ------------------------------------------------------
 * The A-variants carry args as XJ_Value slots (no varargs cross the
 * boundary); fp RETURNS cross as IEEE-754 bit patterns (B-12/B-29-safe:
 * an fp value never crosses). */

int32_t xj_call_int_method(int64_t env, int64_t obj, int64_t mid) {
    xj_clear_error();
    XJ_REQUIRE_OBJ(env, obj, "object", 0);
    if (!mid) { xj_set_error("null methodID handle"); return 0; }
    return xj_env_tbl(env)->CallIntMethodA((void*)(intptr_t)env,
                                           (void*)(intptr_t)obj,
                                           (void*)(intptr_t)mid, 0);
}

int32_t xj_call_int_method_i(int64_t env, int64_t obj, int64_t mid, int32_t a) {
    xj_clear_error();
    XJ_REQUIRE_OBJ(env, obj, "object", 0);
    if (!mid) { xj_set_error("null methodID handle"); return 0; }
    XJ_Value v;
    v.i = a;
    return xj_env_tbl(env)->CallIntMethodA((void*)(intptr_t)env,
                                           (void*)(intptr_t)obj,
                                           (void*)(intptr_t)mid, &v);
}

int32_t xj_call_int_method_ii(int64_t env, int64_t obj, int64_t mid,
                              int32_t a, int32_t b) {
    xj_clear_error();
    XJ_REQUIRE_OBJ(env, obj, "object", 0);
    if (!mid) { xj_set_error("null methodID handle"); return 0; }
    XJ_Value v[2];
    v[0].i = a;
    v[1].i = b;
    return xj_env_tbl(env)->CallIntMethodA((void*)(intptr_t)env,
                                           (void*)(intptr_t)obj,
                                           (void*)(intptr_t)mid, v);
}

int32_t xj_call_int_method_s(int64_t env, int64_t obj, int64_t mid, int64_t str) {
    xj_clear_error();
    XJ_REQUIRE_OBJ(env, obj, "object", 0);
    if (!mid || !str) { xj_set_error("null methodID/string handle"); return 0; }
    XJ_Value v;
    v.l = (void*)(intptr_t)str;
    return xj_env_tbl(env)->CallIntMethodA((void*)(intptr_t)env,
                                           (void*)(intptr_t)obj,
                                           (void*)(intptr_t)mid, &v);
}

int32_t xj_call_boolean_method(int64_t env, int64_t obj, int64_t mid) {
    xj_clear_error();
    XJ_REQUIRE_OBJ(env, obj, "object", -1);
    if (!mid) { xj_set_error("null methodID handle"); return -1; }
    uint8_t v = xj_env_tbl(env)->CallBooleanMethodA((void*)(intptr_t)env,
                                                    (void*)(intptr_t)obj,
                                                    (void*)(intptr_t)mid, 0);
    return v ? 1 : 0;
}

int64_t xj_call_long_method(int64_t env, int64_t obj, int64_t mid) {
    xj_clear_error();
    XJ_REQUIRE_OBJ(env, obj, "object", 0);
    if (!mid) { xj_set_error("null methodID handle"); return 0; }
    return xj_env_tbl(env)->CallLongMethodA((void*)(intptr_t)env,
                                            (void*)(intptr_t)obj,
                                            (void*)(intptr_t)mid, 0);
}

int64_t xj_call_double_bits_method(int64_t env, int64_t obj, int64_t mid) {
    xj_clear_error();
    XJ_REQUIRE_OBJ(env, obj, "object", 0);
    if (!mid) { xj_set_error("null methodID handle"); return 0; }
    double d = xj_env_tbl(env)->CallDoubleMethodA((void*)(intptr_t)env,
                                                  (void*)(intptr_t)obj,
                                                  (void*)(intptr_t)mid, 0);
    uint64_t bits;
    memcpy(&bits, &d, sizeof(bits));
    return (int64_t)bits;
}

int64_t xj_call_double_bits_method_d(int64_t env, int64_t obj, int64_t mid,
                                     int64_t arg_bits) {
    xj_clear_error();
    XJ_REQUIRE_OBJ(env, obj, "object", 0);
    if (!mid) { xj_set_error("null methodID handle"); return 0; }
    XJ_Value v;
    uint64_t ubits = (uint64_t)arg_bits;
    memcpy(&v.d, &ubits, sizeof(v.d));
    double d = xj_env_tbl(env)->CallDoubleMethodA((void*)(intptr_t)env,
                                                  (void*)(intptr_t)obj,
                                                  (void*)(intptr_t)mid, &v);
    uint64_t bits;
    memcpy(&bits, &d, sizeof(bits));
    return (int64_t)bits;
}

int64_t xj_call_double_bits_method_i(int64_t env, int64_t obj, int64_t mid,
                                     int32_t a) {
    xj_clear_error();
    XJ_REQUIRE_OBJ(env, obj, "object", 0);
    if (!mid) { xj_set_error("null methodID handle"); return 0; }
    XJ_Value v;
    v.i = a;
    double d = xj_env_tbl(env)->CallDoubleMethodA((void*)(intptr_t)env,
                                                  (void*)(intptr_t)obj,
                                                  (void*)(intptr_t)mid, &v);
    uint64_t bits;
    memcpy(&bits, &d, sizeof(bits));
    return (int64_t)bits;
}

int64_t xj_call_float_bits_method(int64_t env, int64_t obj, int64_t mid) {
    xj_clear_error();
    XJ_REQUIRE_OBJ(env, obj, "object", 0);
    if (!mid) { xj_set_error("null methodID handle"); return 0; }
    float f = xj_env_tbl(env)->CallFloatMethodA((void*)(intptr_t)env,
                                                (void*)(intptr_t)obj,
                                                (void*)(intptr_t)mid, 0);
    uint32_t bits;
    memcpy(&bits, &f, sizeof(bits));
    return (int64_t)bits;
}

int64_t xj_call_object_method(int64_t env, int64_t obj, int64_t mid) {
    xj_clear_error();
    XJ_REQUIRE_OBJ(env, obj, "object", 0);
    if (!mid) { xj_set_error("null methodID handle"); return 0; }
    void* ref = xj_env_tbl(env)->CallObjectMethodA((void*)(intptr_t)env,
                                                   (void*)(intptr_t)obj,
                                                   (void*)(intptr_t)mid, 0);
    if (!ref) {
        xj_set_error("CallObjectMethod returned null (see exception check)");
        xj_note_exception((void*)(intptr_t)env);
        return 0;
    }
    return (int64_t)(intptr_t)ref;
}

int32_t xj_call_void_method(int64_t env, int64_t obj, int64_t mid) {
    xj_clear_error();
    XJ_REQUIRE_OBJ(env, obj, "object", -1);
    if (!mid) { xj_set_error("null methodID handle"); return -1; }
    xj_env_tbl(env)->CallVoidMethodA((void*)(intptr_t)env,
                                     (void*)(intptr_t)obj,
                                     (void*)(intptr_t)mid, 0);
    return 0;
}

/* -- calls (static) --------------------------------------------------------- */

int32_t xj_call_static_int_method(int64_t env, int64_t clazz, int64_t mid) {
    xj_clear_error();
    XJ_REQUIRE_OBJ(env, clazz, "class", 0);
    if (!mid) { xj_set_error("null methodID handle"); return 0; }
    return xj_env_tbl(env)->CallStaticIntMethodA((void*)(intptr_t)env,
                                                 (void*)(intptr_t)clazz,
                                                 (void*)(intptr_t)mid, 0);
}

int32_t xj_call_static_int_method_i(int64_t env, int64_t clazz, int64_t mid,
                                    int32_t a) {
    xj_clear_error();
    XJ_REQUIRE_OBJ(env, clazz, "class", 0);
    if (!mid) { xj_set_error("null methodID handle"); return 0; }
    XJ_Value v;
    v.i = a;
    return xj_env_tbl(env)->CallStaticIntMethodA((void*)(intptr_t)env,
                                                 (void*)(intptr_t)clazz,
                                                 (void*)(intptr_t)mid, &v);
}

int32_t xj_call_static_int_method_s(int64_t env, int64_t clazz, int64_t mid,
                                    int64_t str) {
    xj_clear_error();
    XJ_REQUIRE_OBJ(env, clazz, "class", 0);
    if (!mid || !str) { xj_set_error("null methodID/string handle"); return 0; }
    XJ_Value v;
    v.l = (void*)(intptr_t)str;
    return xj_env_tbl(env)->CallStaticIntMethodA((void*)(intptr_t)env,
                                                 (void*)(intptr_t)clazz,
                                                 (void*)(intptr_t)mid, &v);
}

int32_t xj_call_static_boolean_method(int64_t env, int64_t clazz, int64_t mid) {
    xj_clear_error();
    XJ_REQUIRE_OBJ(env, clazz, "class", -1);
    if (!mid) { xj_set_error("null methodID handle"); return -1; }
    uint8_t v = xj_env_tbl(env)->CallStaticBooleanMethodA((void*)(intptr_t)env,
                                                          (void*)(intptr_t)clazz,
                                                          (void*)(intptr_t)mid, 0);
    return v ? 1 : 0;
}

int64_t xj_call_static_long_method(int64_t env, int64_t clazz, int64_t mid) {
    xj_clear_error();
    XJ_REQUIRE_OBJ(env, clazz, "class", 0);
    if (!mid) { xj_set_error("null methodID handle"); return 0; }
    return xj_env_tbl(env)->CallStaticLongMethodA((void*)(intptr_t)env,
                                                  (void*)(intptr_t)clazz,
                                                  (void*)(intptr_t)mid, 0);
}

int64_t xj_call_static_double_bits_method(int64_t env, int64_t clazz, int64_t mid) {
    xj_clear_error();
    XJ_REQUIRE_OBJ(env, clazz, "class", 0);
    if (!mid) { xj_set_error("null methodID handle"); return 0; }
    double d = xj_env_tbl(env)->CallStaticDoubleMethodA((void*)(intptr_t)env,
                                                        (void*)(intptr_t)clazz,
                                                        (void*)(intptr_t)mid, 0);
    uint64_t bits;
    memcpy(&bits, &d, sizeof(bits));
    return (int64_t)bits;
}

int64_t xj_call_static_object_method(int64_t env, int64_t clazz, int64_t mid) {
    xj_clear_error();
    XJ_REQUIRE_OBJ(env, clazz, "class", 0);
    if (!mid) { xj_set_error("null methodID handle"); return 0; }
    void* ref = xj_env_tbl(env)->CallStaticObjectMethodA((void*)(intptr_t)env,
                                                         (void*)(intptr_t)clazz,
                                                         (void*)(intptr_t)mid, 0);
    if (!ref) {
        xj_set_error("CallStaticObjectMethod returned null (see exception check)");
        xj_note_exception((void*)(intptr_t)env);
        return 0;
    }
    return (int64_t)(intptr_t)ref;
}

int32_t xj_call_static_void_method(int64_t env, int64_t clazz, int64_t mid) {
    xj_clear_error();
    XJ_REQUIRE_OBJ(env, clazz, "class", -1);
    if (!mid) { xj_set_error("null methodID handle"); return -1; }
    xj_env_tbl(env)->CallStaticVoidMethodA((void*)(intptr_t)env,
                                           (void*)(intptr_t)clazz,
                                           (void*)(intptr_t)mid, 0);
    return 0;
}

/* -- fields ----------------------------------------------------------------- */

int32_t xj_get_int_field(int64_t env, int64_t obj, int64_t fid) {
    xj_clear_error();
    XJ_REQUIRE_OBJ(env, obj, "object", 0);
    if (!fid) { xj_set_error("null fieldID handle"); return 0; }
    return xj_env_tbl(env)->GetIntField((void*)(intptr_t)env,
                                        (void*)(intptr_t)obj,
                                        (void*)(intptr_t)fid);
}

int64_t xj_get_long_field(int64_t env, int64_t obj, int64_t fid) {
    xj_clear_error();
    XJ_REQUIRE_OBJ(env, obj, "object", 0);
    if (!fid) { xj_set_error("null fieldID handle"); return 0; }
    return xj_env_tbl(env)->GetLongField((void*)(intptr_t)env,
                                         (void*)(intptr_t)obj,
                                         (void*)(intptr_t)fid);
}

int64_t xj_get_double_bits_field(int64_t env, int64_t obj, int64_t fid) {
    xj_clear_error();
    XJ_REQUIRE_OBJ(env, obj, "object", 0);
    if (!fid) { xj_set_error("null fieldID handle"); return 0; }
    double d = xj_env_tbl(env)->GetDoubleField((void*)(intptr_t)env,
                                               (void*)(intptr_t)obj,
                                               (void*)(intptr_t)fid);
    uint64_t bits;
    memcpy(&bits, &d, sizeof(bits));
    return (int64_t)bits;
}

int64_t xj_get_object_field(int64_t env, int64_t obj, int64_t fid) {
    xj_clear_error();
    XJ_REQUIRE_OBJ(env, obj, "object", 0);
    if (!fid) { xj_set_error("null fieldID handle"); return 0; }
    void* ref = xj_env_tbl(env)->GetObjectField((void*)(intptr_t)env,
                                                (void*)(intptr_t)obj,
                                                (void*)(intptr_t)fid);
    if (!ref) {
        xj_set_error("GetObjectField returned null (see exception check)");
        xj_note_exception((void*)(intptr_t)env);
        return 0;
    }
    return (int64_t)(intptr_t)ref;
}

int32_t xj_set_int_field(int64_t env, int64_t obj, int64_t fid, int32_t v) {
    xj_clear_error();
    XJ_REQUIRE_OBJ(env, obj, "object", -1);
    if (!fid) { xj_set_error("null fieldID handle"); return -1; }
    xj_env_tbl(env)->SetIntField((void*)(intptr_t)env, (void*)(intptr_t)obj,
                                 (void*)(intptr_t)fid, v);
    return 0;
}

int32_t xj_set_long_field(int64_t env, int64_t obj, int64_t fid, int64_t v) {
    xj_clear_error();
    XJ_REQUIRE_OBJ(env, obj, "object", -1);
    if (!fid) { xj_set_error("null fieldID handle"); return -1; }
    xj_env_tbl(env)->SetLongField((void*)(intptr_t)env, (void*)(intptr_t)obj,
                                  (void*)(intptr_t)fid, v);
    return 0;
}

int32_t xj_set_object_field(int64_t env, int64_t obj, int64_t fid, int64_t v) {
    xj_clear_error();
    XJ_REQUIRE_OBJ(env, obj, "object", -1);
    if (!fid) { xj_set_error("null fieldID handle"); return -1; }
    xj_env_tbl(env)->SetObjectField((void*)(intptr_t)env, (void*)(intptr_t)obj,
                                    (void*)(intptr_t)fid, (void*)(intptr_t)v);
    return 0;
}

int32_t xj_get_static_int_field(int64_t env, int64_t clazz, int64_t fid) {
    xj_clear_error();
    XJ_REQUIRE_OBJ(env, clazz, "class", 0);
    if (!fid) { xj_set_error("null fieldID handle"); return 0; }
    return xj_env_tbl(env)->GetStaticIntField((void*)(intptr_t)env,
                                              (void*)(intptr_t)clazz,
                                              (void*)(intptr_t)fid);
}

int64_t xj_get_static_long_field(int64_t env, int64_t clazz, int64_t fid) {
    xj_clear_error();
    XJ_REQUIRE_OBJ(env, clazz, "class", 0);
    if (!fid) { xj_set_error("null fieldID handle"); return 0; }
    return xj_env_tbl(env)->GetStaticLongField((void*)(intptr_t)env,
                                               (void*)(intptr_t)clazz,
                                               (void*)(intptr_t)fid);
}

int64_t xj_get_static_object_field(int64_t env, int64_t clazz, int64_t fid) {
    xj_clear_error();
    XJ_REQUIRE_OBJ(env, clazz, "class", 0);
    if (!fid) { xj_set_error("null fieldID handle"); return 0; }
    void* ref = xj_env_tbl(env)->GetStaticObjectField((void*)(intptr_t)env,
                                                      (void*)(intptr_t)clazz,
                                                      (void*)(intptr_t)fid);
    if (!ref) {
        xj_set_error("GetStaticObjectField returned null (see exception check)");
        xj_note_exception((void*)(intptr_t)env);
        return 0;
    }
    return (int64_t)(intptr_t)ref;
}

/* -- strings (UTF-8; chars never cross) ------------------------------------- */

int64_t xj_new_string_utf(int64_t env, const char* utf8) {
    xj_clear_error();
    XJ_REQUIRE_ENV(env, 0);
    if (!utf8) { xj_set_error("null UTF-8 input"); return 0; }
    void* s = xj_env_tbl(env)->NewStringUTF((void*)(intptr_t)env, utf8);
    if (!s) {
        xj_set_error("NewStringUTF returned null (bad UTF-8 / OOM)");
        xj_note_exception((void*)(intptr_t)env);
        return 0;
    }
    return (int64_t)(intptr_t)s;
}

int32_t xj_string_utf_length(int64_t env, int64_t str) {
    xj_clear_error();
    XJ_REQUIRE_OBJ(env, str, "string", -1);
    int32_t n = xj_env_tbl(env)->GetStringUTFLength((void*)(intptr_t)env,
                                                    (void*)(intptr_t)str);
    if (n < 0) { xj_set_error("GetStringUTFLength returned negative"); return -1; }
    return n;
}

/* Copy the UTF-8 chars into the bridge-owned slot (GetStringUTFChars +
 * copy + ReleaseStringUTFChars inside one helper); returns the copied
 * length (truncated at max / the slot size); -1 = error. */
int32_t xj_string_read_utf8(int64_t env, int64_t str, int32_t max_len) {
    xj_clear_error();
    XJ_REQUIRE_OBJ(env, str, "string", -1);
    int32_t cap = XJ_STRING_BUF_SIZE - 1;
    if (max_len > 0 && max_len < cap) cap = max_len;
    const char* chars = xj_env_tbl(env)->GetStringUTFChars((void*)(intptr_t)env,
                                                           (void*)(intptr_t)str, 0);
    if (!chars) {
        xj_set_error("GetStringUTFChars returned null");
        xj_note_exception((void*)(intptr_t)env);
        return -1;
    }
    size_t n = strlen(chars);
    if (n > (size_t)cap) n = (size_t)cap;
    memcpy(g_string_buf, chars, n);
    g_string_buf[n] = 0;
    g_string_len = (int32_t)n;
    xj_env_tbl(env)->ReleaseStringUTFChars((void*)(intptr_t)env,
                                           (void*)(intptr_t)str, chars);
    return g_string_len;
}

const char* xj_string_buf_ptr(void) { return g_string_buf; }

int32_t xj_string_buf_len(void) { return g_string_len; }

/* -- arrays (bridge-owned int32 slots; B-series discipline) ----------------- */

int32_t xj_array_length(int64_t env, int64_t arr) {
    xj_clear_error();
    XJ_REQUIRE_OBJ(env, arr, "array", -1);
    int32_t n = xj_env_tbl(env)->GetArrayLength((void*)(intptr_t)env,
                                                (void*)(intptr_t)arr);
    if (n < 0) { xj_set_error("GetArrayLength returned negative"); return -1; }
    return n;
}

int64_t xj_new_int_array(int64_t env, int32_t len) {
    xj_clear_error();
    XJ_REQUIRE_ENV(env, 0);
    if (len < 0) { xj_set_error("negative array length"); return 0; }
    void* a = xj_env_tbl(env)->NewIntArray((void*)(intptr_t)env, len);
    if (!a) {
        xj_set_error("NewIntArray returned null (OOM)");
        xj_note_exception((void*)(intptr_t)env);
        return 0;
    }
    return (int64_t)(intptr_t)a;
}

int64_t xj_new_byte_array(int64_t env, int32_t len) {
    xj_clear_error();
    XJ_REQUIRE_ENV(env, 0);
    if (len < 0) { xj_set_error("negative array length"); return 0; }
    void* a = xj_env_tbl(env)->NewByteArray((void*)(intptr_t)env, len);
    if (!a) {
        xj_set_error("NewByteArray returned null (OOM)");
        xj_note_exception((void*)(intptr_t)env);
        return 0;
    }
    return (int64_t)(intptr_t)a;
}

int32_t xj_get_int_array_region(int64_t env, int64_t arr, int32_t start,
                                int32_t len) {
    xj_clear_error();
    XJ_REQUIRE_OBJ(env, arr, "array", -1);
    if (start < 0 || len < 0 || len > XJ_INT_SLOT_COUNT) {
        xj_set_error("bad region (len 0..64)");
        return -1;
    }
    xj_env_tbl(env)->GetIntArrayRegion((void*)(intptr_t)env, (void*)(intptr_t)arr,
                                       start, len, g_int_slots);
    xj_note_exception((void*)(intptr_t)env);
    if (g_error[0] != 0) return -1;
    return 0;
}

int32_t xj_set_int_array_region(int64_t env, int64_t arr, int32_t start,
                                int32_t len) {
    xj_clear_error();
    XJ_REQUIRE_OBJ(env, arr, "array", -1);
    if (start < 0 || len < 0 || len > XJ_INT_SLOT_COUNT) {
        xj_set_error("bad region (len 0..64)");
        return -1;
    }
    xj_env_tbl(env)->SetIntArrayRegion((void*)(intptr_t)env, (void*)(intptr_t)arr,
                                       start, len, g_int_slots);
    xj_note_exception((void*)(intptr_t)env);
    if (g_error[0] != 0) return -1;
    return 0;
}

int32_t xj_int_slot_set(int32_t index, int32_t value) {
    xj_clear_error();
    if (index < 0 || index >= XJ_INT_SLOT_COUNT) {
        xj_set_error("slot index out of range (0..63)");
        return -1;
    }
    g_int_slots[index] = value;
    return 0;
}

int32_t xj_int_slot_get(int32_t index) {
    xj_clear_error();
    if (index < 0 || index >= XJ_INT_SLOT_COUNT) {
        xj_set_error("slot index out of range (0..63)");
        return 0;
    }
    return g_int_slots[index];
}

/* -- android/bitmap.h cluster (libjnigraphics.so) --------------------------- */

static int xj_bitmap_require(void) {
    if (!p_bitmap_get_info || !p_bitmap_lock_pixels || !p_bitmap_unlock_pixels) {
        xj_set_error("libjnigraphics unresolved (call jni_probe first)");
        return -1;
    }
    return 0;
}

static int xj_bitmap_ensure_info(int64_t env, int64_t bitmap) {
    if (g_bitmap_info_valid) return 0;
    int rc = p_bitmap_get_info((void*)(intptr_t)env, (void*)(intptr_t)bitmap,
                               &g_bitmap_info);
    if (rc != 0) {
        xj_set_errorf("AndroidBitmap_getInfo rc=%d", rc);
        return -1;
    }
    g_bitmap_info_valid = 1;
    return 0;
}

int32_t xj_bitmap_get_info(int64_t env, int64_t bitmap) {
    xj_clear_error();
    if (xj_bitmap_require() != 0) return -1;
    XJ_REQUIRE_OBJ(env, bitmap, "bitmap", -1);
    int rc = p_bitmap_get_info((void*)(intptr_t)env, (void*)(intptr_t)bitmap,
                               &g_bitmap_info);
    if (rc != 0) {
        g_bitmap_info_valid = 0;
        xj_set_errorf("AndroidBitmap_getInfo rc=%d", rc);
        return rc;
    }
    g_bitmap_info_valid = 1;
    return 0;
}

int32_t xj_bitmap_info_width(void) { return (int32_t)g_bitmap_info.width; }

int32_t xj_bitmap_info_height(void) { return (int32_t)g_bitmap_info.height; }

int32_t xj_bitmap_info_stride(void) { return (int32_t)g_bitmap_info.stride; }

int32_t xj_bitmap_info_format(void) { return g_bitmap_info.format; }

int32_t xj_bitmap_info_flags(void) { return (int32_t)g_bitmap_info.flags; }

int32_t xj_bitmap_info_valid(void) { return g_bitmap_info_valid; }

int32_t xj_bitmap_get_data_space(int64_t env, int64_t bitmap) {
    xj_clear_error();
    if (!p_bitmap_get_data_space) {
        xj_set_error("AndroidBitmap_getDataSpace unresolved "
                     "(libjnigraphics absent; call jni_probe first)");
        return XJ_INT32_MIN;
    }
    XJ_REQUIRE_OBJ(env, bitmap, "bitmap", XJ_INT32_MIN);
    int32_t rc = p_bitmap_get_data_space((void*)(intptr_t)env,
                                         (void*)(intptr_t)bitmap);
    if (rc < 0) { xj_set_errorf("AndroidBitmap_getDataSpace rc=%d", rc); }
    return rc;
}

int32_t xj_bitmap_lock_pixels(int64_t env, int64_t bitmap) {
    xj_clear_error();
    if (xj_bitmap_require() != 0) return -1;
    XJ_REQUIRE_OBJ(env, bitmap, "bitmap", -1);
    if (g_bitmap_lock_active) {
        xj_set_error("already locked (unlock first)");
        return -1;
    }
    void* addr = 0;
    int rc = p_bitmap_lock_pixels((void*)(intptr_t)env, (void*)(intptr_t)bitmap,
                                  &addr);
    if (rc != 0 || !addr) {
        xj_set_errorf("AndroidBitmap_lockPixels rc=%d", rc);
        return -1;
    }
    g_bitmap_lock_addr = addr;
    g_bitmap_lock_bitmap = (void*)(intptr_t)bitmap;
    g_bitmap_lock_active = 1;
    return 0;
}

int32_t xj_bitmap_unlock_pixels(int64_t env, int64_t bitmap) {
    xj_clear_error();
    if (xj_bitmap_require() != 0) return -1;
    XJ_REQUIRE_OBJ(env, bitmap, "bitmap", -1);
    if (!g_bitmap_lock_active) {
        xj_set_error("not locked (lock first)");
        return -1;
    }
    int rc = p_bitmap_unlock_pixels((void*)(intptr_t)env, (void*)(intptr_t)bitmap);
    g_bitmap_lock_addr = 0;
    g_bitmap_lock_bitmap = 0;
    g_bitmap_lock_active = 0;
    if (rc != 0) { xj_set_errorf("AndroidBitmap_unlockPixels rc=%d", rc); return -1; }
    return 0;
}

/* One pixel at (x, y) through a locked window; the address stays C-side.
 * Lock/unlock are paired here unless a manual lock of the SAME bitmap is
 * active (then the retained window is used and not unlocked). */
int32_t xj_bitmap_write_pixel(int64_t env, int64_t bitmap, int32_t x, int32_t y,
                              int32_t rgba) {
    xj_clear_error();
    if (xj_bitmap_require() != 0) return -1;
    XJ_REQUIRE_OBJ(env, bitmap, "bitmap", -1);
    /* Always re-read the info for the bitmap named in THIS call when the
     * slot does not describe it (the slot is single-bitmap). */
    if (g_bitmap_info_valid && g_bitmap_lock_bitmap == (void*)(intptr_t)bitmap) {
        /* info already describes the locked bitmap */
    } else {
        g_bitmap_info_valid = 0;
    }
    if (xj_bitmap_ensure_info(env, bitmap) != 0) return -1;
    if (x < 0 || y < 0 || (uint32_t)x >= g_bitmap_info.width ||
        (uint32_t)y >= g_bitmap_info.height) {
        xj_set_error("pixel out of range");
        return -1;
    }
    int manual = g_bitmap_lock_active &&
                 g_bitmap_lock_bitmap == (void*)(intptr_t)bitmap;
    void* base = g_bitmap_lock_addr;
    if (!manual) {
        void* addr = 0;
        int rc = p_bitmap_lock_pixels((void*)(intptr_t)env, (void*)(intptr_t)bitmap,
                                      &addr);
        if (rc != 0 || !addr) {
            xj_set_errorf("AndroidBitmap_lockPixels rc=%d", rc);
            return -1;
        }
        base = addr;
    }
    uint8_t* row = (uint8_t*)base + (size_t)(uint32_t)y * g_bitmap_info.stride;
    memcpy(row + (size_t)(uint32_t)x * 4, &rgba, sizeof(uint32_t));
    if (!manual) {
        int rc2 = p_bitmap_unlock_pixels((void*)(intptr_t)env,
                                         (void*)(intptr_t)bitmap);
        if (rc2 != 0) {
            xj_set_errorf("AndroidBitmap_unlockPixels rc=%d", rc2);
            return -1;
        }
    }
    return 0;
}

int64_t xj_bitmap_read_pixel(int64_t env, int64_t bitmap, int32_t x, int32_t y) {
    xj_clear_error();
    if (xj_bitmap_require() != 0) return -1;
    XJ_REQUIRE_OBJ(env, bitmap, "bitmap", -1);
    if (g_bitmap_info_valid && g_bitmap_lock_bitmap == (void*)(intptr_t)bitmap) {
        /* info already describes the locked bitmap */
    } else {
        g_bitmap_info_valid = 0;
    }
    if (xj_bitmap_ensure_info(env, bitmap) != 0) return -1;
    if (x < 0 || y < 0 || (uint32_t)x >= g_bitmap_info.width ||
        (uint32_t)y >= g_bitmap_info.height) {
        xj_set_error("pixel out of range");
        return -1;
    }
    int manual = g_bitmap_lock_active &&
                 g_bitmap_lock_bitmap == (void*)(intptr_t)bitmap;
    void* base = g_bitmap_lock_addr;
    if (!manual) {
        void* addr = 0;
        int rc = p_bitmap_lock_pixels((void*)(intptr_t)env, (void*)(intptr_t)bitmap,
                                      &addr);
        if (rc != 0 || !addr) {
            xj_set_errorf("AndroidBitmap_lockPixels rc=%d", rc);
            return -1;
        }
        base = addr;
    }
    uint8_t* row = (uint8_t*)base + (size_t)(uint32_t)y * g_bitmap_info.stride;
    uint32_t value;
    memcpy(&value, row + (size_t)(uint32_t)x * 4, sizeof(value));
    if (!manual) {
        int rc2 = p_bitmap_unlock_pixels((void*)(intptr_t)env,
                                         (void*)(intptr_t)bitmap);
        if (rc2 != 0) {
            xj_set_errorf("AndroidBitmap_unlockPixels rc=%d", rc2);
            return -1;
        }
    }
    return (int64_t)value;
}

/* ANDROID_BITMAP_FLAGS_IS_HARDWARE = 1 << 31 (r27b): mask tested C-side
 * (the B-29 bit-op hazard is a XIOM-side compiler defect). */
int32_t xj_bitmap_is_hardware(int64_t env, int64_t bitmap) {
    xj_clear_error();
    if (xj_bitmap_require() != 0) return -1;
    XJ_REQUIRE_OBJ(env, bitmap, "bitmap", -1);
    g_bitmap_info_valid = 0;
    if (xj_bitmap_ensure_info(env, bitmap) != 0) return -1;
    return (g_bitmap_info.flags & 0x80000000u) ? 1 : 0;
}

int64_t xj_bitmap_get_hardware_buffer(int64_t env, int64_t bitmap) {
    xj_clear_error();
    if (!p_bitmap_get_hwb) {
        xj_set_error("AndroidBitmap_getHardwareBuffer unresolved "
                     "(libjnigraphics absent; call jni_probe first)");
        return 0;
    }
    XJ_REQUIRE_OBJ(env, bitmap, "bitmap", 0);
    void* buf = 0;
    int rc = p_bitmap_get_hwb((void*)(intptr_t)env, (void*)(intptr_t)bitmap, &buf);
    if (rc != 0 || !buf) {
        xj_set_errorf("AndroidBitmap_getHardwareBuffer rc=%d", rc);
        return 0;
    }
    return (int64_t)(intptr_t)buf;
}

/* Compress the bitmap into the bridge-owned buffer through the
 * AndroidBitmap_CompressWriteFunc C callback; the pixel pointer never
 * crosses.  Returns bytes written; -1 = error. */
static uint8_t xj_compress_write(void* ctx, const void* data, size_t size) {
    (void)ctx;
    if (g_compress_len < 0) return 0;
    if ((int64_t)g_compress_len + (int64_t)size > (int64_t)g_compress_cap) return 0;
    memcpy(g_compress_buf + g_compress_len, data, size);
    g_compress_len += (int32_t)size;
    return 1;
}

int32_t xj_bitmap_compress_owned(int64_t env, int64_t bitmap, int32_t format,
                                 int32_t quality, int32_t max_bytes) {
    xj_clear_error();
    if (!p_bitmap_compress) {
        xj_set_error("AndroidBitmap_compress unresolved "
                     "(libjnigraphics absent; call jni_probe first)");
        return -1;
    }
    if (xj_bitmap_require() != 0) return -1;
    XJ_REQUIRE_OBJ(env, bitmap, "bitmap", -1);
    g_bitmap_info_valid = 0;
    if (xj_bitmap_ensure_info(env, bitmap) != 0) return -1;
    g_compress_cap = XJ_COMPRESS_BUF_SIZE;
    if (max_bytes > 0 && max_bytes < g_compress_cap) g_compress_cap = max_bytes;
    g_compress_len = 0;
    void* addr = 0;
    int rc = p_bitmap_lock_pixels((void*)(intptr_t)env, (void*)(intptr_t)bitmap,
                                  &addr);
    if (rc != 0 || !addr) {
        xj_set_errorf("AndroidBitmap_lockPixels rc=%d", rc);
        return -1;
    }
    int32_t dataspace = 0; /* ADATASPACE_UNKNOWN */
    if (p_bitmap_get_data_space) {
        int32_t ds = p_bitmap_get_data_space((void*)(intptr_t)env,
                                             (void*)(intptr_t)bitmap);
        if (ds >= 0) dataspace = ds;
    }
    rc = p_bitmap_compress(&g_bitmap_info, dataspace, addr, format, quality, 0,
                           xj_compress_write);
    int rc2 = p_bitmap_unlock_pixels((void*)(intptr_t)env, (void*)(intptr_t)bitmap);
    if (rc2 != 0) {
        xj_set_errorf("AndroidBitmap_unlockPixels rc=%d", rc2);
        return -1;
    }
    if (rc != 0) {
        xj_set_errorf("AndroidBitmap_compress rc=%d", rc);
        g_compress_len = 0;
        return -1;
    }
    return g_compress_len;
}

int32_t xj_bitmap_compressed_len(void) { return g_compress_len; }

const uint8_t* xj_bitmap_compressed_ptr(void) { return g_compress_buf; }

int32_t xj_bitmap_compressed_byte(int32_t index) {
    xj_clear_error();
    if (index < 0 || index >= g_compress_len) {
        xj_set_error("compressed byte index out of range");
        return -1;
    }
    return (int32_t)g_compress_buf[index];
}
