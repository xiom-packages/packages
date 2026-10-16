/* XIOM -- xiom.jni A11 head: on-device shell probe.
 * Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
 * Licensed under the MIT or Apache-2.0 license, at your option.
 *
 * Purpose (API-36 x86_64 emulator, /data/local/tmp/xiom-spike/):
 *   1. BUILD-TIME oracle gate: every constant transcribed into
 *      src/jni.xi and every JNINativeInterface / JNIInvokeInterface /
 *      JNINativeMethod / AndroidBitmapInfo member OFFSET used by
 *      src/jni_bridge.c is _Static_assert-ed against the REAL NDK r27b
 *      headers (jni.h + android/bitmap.h), and the bridge's numeric
 *      offset table (xj_abi_offset etc.) is compared against the
 *      header's offsetof AT RUNTIME (a mismatch cannot pass);
 *   2. runtime loader: dlopen libjnigraphics.so + libnativehelper.so
 *      (both individually + through the bridge), resolve the declared
 *      9-symbol export set, print which library provides each symbol;
 *   3. null-safety on-device: 0-env/0-object paths answer with typed
 *      errors (no crash);
 *   4. JNI_GetCreatedJavaVMs in a plain shell process: no VM exists ->
 *      the bridge reports "no JavaVM at index" (honest; a full env
 *      needs a Java host -- proven by jni_app_probe.c).
 *
 * A shell process cannot own a JNIEnv: nothing here fakes one.
 *
 * Build+run: powershell -File build-and-run.ps1
 */

#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <dlfcn.h>

#include <jni.h>
#include <android/bitmap.h>

/* ---- BUILD-TIME transcription gate vs the real NDK r27b headers ------- */

_Static_assert(JNI_VERSION_1_1 == 0x00010001, "JNI_VERSION_1_1 drift");
_Static_assert(JNI_VERSION_1_2 == 0x00010002, "JNI_VERSION_1_2 drift");
_Static_assert(JNI_VERSION_1_4 == 0x00010004, "JNI_VERSION_1_4 drift");
_Static_assert(JNI_VERSION_1_6 == 0x00010006, "JNI_VERSION_1_6 drift");
_Static_assert(JNI_FALSE == 0 && JNI_TRUE == 1, "JNI_FALSE/TRUE drift");
_Static_assert(JNI_OK == 0 && JNI_ERR == -1, "JNI_OK/ERR drift");
_Static_assert(JNI_EDETACHED == -2 && JNI_EVERSION == -3, "JNI_ED* drift");
_Static_assert(JNI_ENOMEM == -4 && JNI_EEXIST == -5 && JNI_EINVAL == -6,
               "JNI_ENOMEM/EEXIST/EINVAL drift");
_Static_assert(JNI_COMMIT == 1 && JNI_ABORT == 2, "JNI_COMMIT/ABORT drift");
_Static_assert(JNIInvalidRefType == 0 && JNILocalRefType == 1, "ref type drift");
_Static_assert(JNIGlobalRefType == 2 && JNIWeakGlobalRefType == 3, "ref type drift");

_Static_assert(sizeof(jvalue) == 8, "jvalue size drift");
_Static_assert(sizeof(JNINativeMethod) == 3 * sizeof(void*), "JNINativeMethod size drift");
_Static_assert(offsetof(JNINativeMethod, name) == 0, "JNINativeMethod.name offset drift");
_Static_assert(offsetof(JNINativeMethod, signature) == sizeof(void*),
               "JNINativeMethod.signature offset drift");
_Static_assert(offsetof(JNINativeMethod, fnPtr) == 2 * sizeof(void*),
               "JNINativeMethod.fnPtr offset drift");

_Static_assert(sizeof(struct JNINativeInterface) == 233 * sizeof(void*),
               "JNINativeInterface size drift (233 slots expected in r27b)");

_Static_assert(ANDROID_BITMAP_RESULT_SUCCESS == 0, "bitmap result drift");
_Static_assert(ANDROID_BITMAP_RESULT_BAD_PARAMETER == -1, "bitmap result drift");
_Static_assert(ANDROID_BITMAP_RESULT_JNI_EXCEPTION == -2, "bitmap result drift");
_Static_assert(ANDROID_BITMAP_RESULT_ALLOCATION_FAILED == -3, "bitmap result drift");
_Static_assert(ANDROID_BITMAP_FORMAT_NONE == 0, "bitmap format drift");
_Static_assert(ANDROID_BITMAP_FORMAT_RGBA_8888 == 1, "bitmap format drift");
_Static_assert(ANDROID_BITMAP_FORMAT_RGB_565 == 4, "bitmap format drift");
_Static_assert(ANDROID_BITMAP_FORMAT_RGBA_4444 == 7, "bitmap format drift");
_Static_assert(ANDROID_BITMAP_FORMAT_A_8 == 8, "bitmap format drift");
_Static_assert(ANDROID_BITMAP_FORMAT_RGBA_F16 == 9, "bitmap format drift");
_Static_assert(ANDROID_BITMAP_FORMAT_RGBA_1010102 == 10, "bitmap format drift");
_Static_assert(ANDROID_BITMAP_FLAGS_ALPHA_PREMUL == 0, "bitmap alpha drift");
_Static_assert(ANDROID_BITMAP_FLAGS_ALPHA_OPAQUE == 1, "bitmap alpha drift");
_Static_assert(ANDROID_BITMAP_FLAGS_ALPHA_UNPREMUL == 2, "bitmap alpha drift");
_Static_assert(ANDROID_BITMAP_FLAGS_ALPHA_MASK == 0x3, "bitmap alpha mask drift");
_Static_assert(ANDROID_BITMAP_FLAGS_ALPHA_SHIFT == 0, "bitmap alpha shift drift");
_Static_assert(ANDROID_BITMAP_FLAGS_IS_HARDWARE == (1u << 31), "bitmap HW flag drift");
_Static_assert(ANDROID_BITMAP_COMPRESS_FORMAT_JPEG == 0, "compress format drift");
_Static_assert(ANDROID_BITMAP_COMPRESS_FORMAT_PNG == 1, "compress format drift");
_Static_assert(ANDROID_BITMAP_COMPRESS_FORMAT_WEBP_LOSSY == 3, "compress format drift");
_Static_assert(ANDROID_BITMAP_COMPRESS_FORMAT_WEBP_LOSSLESS == 4, "compress format drift");

_Static_assert(sizeof(AndroidBitmapInfo) == 20, "AndroidBitmapInfo size drift");
_Static_assert(offsetof(AndroidBitmapInfo, width) == 0, "bitmap info width drift");
_Static_assert(offsetof(AndroidBitmapInfo, height) == 4, "bitmap info height drift");
_Static_assert(offsetof(AndroidBitmapInfo, stride) == 8, "bitmap info stride drift");
_Static_assert(offsetof(AndroidBitmapInfo, format) == 12, "bitmap info format drift");
_Static_assert(offsetof(AndroidBitmapInfo, flags) == 16, "bitmap info flags drift");

/* Prototype compatibility: the bridge calls these through the pinned
 * signatures; assign to typed pointers so a header drift fails the build. */
static int (*pfn_get_info)(JNIEnv*, jobject, AndroidBitmapInfo*) = AndroidBitmap_getInfo;
static int32_t (*pfn_get_data_space)(JNIEnv*, jobject) = AndroidBitmap_getDataSpace;
static int (*pfn_lock_pixels)(JNIEnv*, jobject, void**) = AndroidBitmap_lockPixels;
static int (*pfn_unlock_pixels)(JNIEnv*, jobject) = AndroidBitmap_unlockPixels;
static int32_t (*pfn_get_created_vms)(JavaVM**, jsize, jsize*) = JNI_GetCreatedJavaVMs;

static void use_prototype_pins(void) {
    (void)pfn_get_info; (void)pfn_get_data_space; (void)pfn_lock_pixels;
    (void)pfn_unlock_pixels; (void)pfn_get_created_vms;
}

/* ---- bridge contract (mirrors src/jni_bridge.c) ------------------------ */

extern int xj_load(void);
extern const char* xj_error(void);
extern int xj_abi_missing_count(void);
extern const char* xj_abi_missing(void);
extern int32_t xj_export_count(void);
extern void xj_unload(void);
extern int64_t xj_vm_from_created(int32_t);
extern int32_t xj_env_version(int64_t);
extern int64_t xj_find_class(int64_t, const char*);
extern int32_t xj_bitmap_get_info(int64_t, int64_t);
extern int32_t xj_bitmap_write_pixel(int64_t, int64_t, int32_t, int32_t, int32_t);
extern int64_t xj_bitmap_read_pixel(int64_t, int64_t, int32_t, int32_t);

/* probe-only ABI diagnostics */
extern int32_t xj_abi_sizeof_table(void);
extern int32_t xj_abi_sizeof_value(void);
extern int32_t xj_abi_sizeof_native_method(void);
extern int32_t xj_abi_sizeof_bitmap_info(void);
extern int32_t xj_abi_sizeof_invoke(void);
extern int32_t xj_abi_offset(int32_t);
extern int32_t xj_abi_invoke_offset(int32_t);
extern int32_t xj_abi_bitmap_info_offset(int32_t);
extern int32_t xj_abi_native_method_offset(int32_t);

static int g_fail = 0;

static void check(int ok, const char* what) {
    printf("  [%s] %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok) g_fail++;
}

/* Header-side offset table for the 56 bridge offsets (xj_abi_offset). */
static const size_t k_hdr_off[56] = {
    offsetof(struct JNINativeInterface, GetVersion),
    offsetof(struct JNINativeInterface, FindClass),
    offsetof(struct JNINativeInterface, GetSuperclass),
    offsetof(struct JNINativeInterface, IsAssignableFrom),
    offsetof(struct JNINativeInterface, ThrowNew),
    offsetof(struct JNINativeInterface, ExceptionOccurred),
    offsetof(struct JNINativeInterface, ExceptionClear),
    offsetof(struct JNINativeInterface, PushLocalFrame),
    offsetof(struct JNINativeInterface, PopLocalFrame),
    offsetof(struct JNINativeInterface, NewGlobalRef),
    offsetof(struct JNINativeInterface, DeleteGlobalRef),
    offsetof(struct JNINativeInterface, DeleteLocalRef),
    offsetof(struct JNINativeInterface, NewLocalRef),
    offsetof(struct JNINativeInterface, EnsureLocalCapacity),
    offsetof(struct JNINativeInterface, GetObjectClass),
    offsetof(struct JNINativeInterface, IsInstanceOf),
    offsetof(struct JNINativeInterface, GetMethodID),
    offsetof(struct JNINativeInterface, CallObjectMethodA),
    offsetof(struct JNINativeInterface, CallBooleanMethodA),
    offsetof(struct JNINativeInterface, CallIntMethodA),
    offsetof(struct JNINativeInterface, CallLongMethodA),
    offsetof(struct JNINativeInterface, CallFloatMethodA),
    offsetof(struct JNINativeInterface, CallDoubleMethodA),
    offsetof(struct JNINativeInterface, CallVoidMethodA),
    offsetof(struct JNINativeInterface, GetFieldID),
    offsetof(struct JNINativeInterface, GetObjectField),
    offsetof(struct JNINativeInterface, GetIntField),
    offsetof(struct JNINativeInterface, GetLongField),
    offsetof(struct JNINativeInterface, GetDoubleField),
    offsetof(struct JNINativeInterface, SetObjectField),
    offsetof(struct JNINativeInterface, SetIntField),
    offsetof(struct JNINativeInterface, SetLongField),
    offsetof(struct JNINativeInterface, GetStaticMethodID),
    offsetof(struct JNINativeInterface, CallStaticObjectMethodA),
    offsetof(struct JNINativeInterface, CallStaticBooleanMethodA),
    offsetof(struct JNINativeInterface, CallStaticIntMethodA),
    offsetof(struct JNINativeInterface, CallStaticLongMethodA),
    offsetof(struct JNINativeInterface, CallStaticDoubleMethodA),
    offsetof(struct JNINativeInterface, CallStaticVoidMethodA),
    offsetof(struct JNINativeInterface, GetStaticObjectField),
    offsetof(struct JNINativeInterface, GetStaticIntField),
    offsetof(struct JNINativeInterface, GetStaticLongField),
    offsetof(struct JNINativeInterface, NewStringUTF),
    offsetof(struct JNINativeInterface, GetStringUTFLength),
    offsetof(struct JNINativeInterface, GetStringUTFChars),
    offsetof(struct JNINativeInterface, ReleaseStringUTFChars),
    offsetof(struct JNINativeInterface, GetArrayLength),
    offsetof(struct JNINativeInterface, NewIntArray),
    offsetof(struct JNINativeInterface, NewByteArray),
    offsetof(struct JNINativeInterface, GetIntArrayRegion),
    offsetof(struct JNINativeInterface, SetIntArrayRegion),
    offsetof(struct JNINativeInterface, RegisterNatives),
    offsetof(struct JNINativeInterface, UnregisterNatives),
    offsetof(struct JNINativeInterface, GetJavaVM),
    offsetof(struct JNINativeInterface, ExceptionCheck),
    offsetof(struct JNINativeInterface, GetObjectRefType),
};

static const char* k_export_names[9] = {
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

int main(void) {
    use_prototype_pins();
    printf("=== xiom.jni A11 shell probe (JNI seam mechanics) ===\n");

    /* 1. bridge layout vs real header (runtime offset table) */
    check(xj_abi_sizeof_table() == (int32_t)sizeof(struct JNINativeInterface),
          "bridge table sizeof == header (233 slots)");
    check(xj_abi_sizeof_value() == (int32_t)sizeof(jvalue),
          "bridge jvalue sizeof == header");
    check(xj_abi_sizeof_native_method() == (int32_t)sizeof(JNINativeMethod),
          "bridge JNINativeMethod sizeof == header");
    check(xj_abi_sizeof_bitmap_info() == (int32_t)sizeof(AndroidBitmapInfo),
          "bridge AndroidBitmapInfo sizeof == header");
    check(xj_abi_sizeof_invoke() == (int32_t)sizeof(struct JNIInvokeInterface),
          "bridge JNIInvokeInterface sizeof == header");
    {
        int off_ok = 1;
        for (int i = 0; i < 56; i++) {
            if (xj_abi_offset(i) != (int32_t)k_hdr_off[i]) {
                printf("  offset mismatch at index %d: bridge=%d header=%u\n",
                       i, xj_abi_offset(i), (unsigned)k_hdr_off[i]);
                off_ok = 0;
            }
        }
        check(off_ok, "all 56 JNINativeInterface offsets identical (bridge vs header)");
    }
    check(xj_abi_invoke_offset(0) == (int32_t)offsetof(struct JNIInvokeInterface, AttachCurrentThread)
       && xj_abi_invoke_offset(1) == (int32_t)offsetof(struct JNIInvokeInterface, DetachCurrentThread)
       && xj_abi_invoke_offset(2) == (int32_t)offsetof(struct JNIInvokeInterface, GetEnv),
          "JNIInvokeInterface offsets identical (Attach/Detach/GetEnv)");
    check(xj_abi_bitmap_info_offset(0) == (int32_t)offsetof(AndroidBitmapInfo, width)
       && xj_abi_bitmap_info_offset(1) == (int32_t)offsetof(AndroidBitmapInfo, height)
       && xj_abi_bitmap_info_offset(2) == (int32_t)offsetof(AndroidBitmapInfo, stride)
       && xj_abi_bitmap_info_offset(3) == (int32_t)offsetof(AndroidBitmapInfo, format)
       && xj_abi_bitmap_info_offset(4) == (int32_t)offsetof(AndroidBitmapInfo, flags),
          "AndroidBitmapInfo offsets identical (width/height/stride/format/flags)");
    check(xj_abi_native_method_offset(0) == (int32_t)offsetof(JNINativeMethod, name)
       && xj_abi_native_method_offset(1) == (int32_t)offsetof(JNINativeMethod, signature)
       && xj_abi_native_method_offset(2) == (int32_t)offsetof(JNINativeMethod, fnPtr),
          "JNINativeMethod offsets identical (name/signature/fnPtr)");

    /* 2. per-library dlopen + export resolution (provider map) */
    void* h_bitmap = dlopen("libjnigraphics.so", RTLD_NOW | RTLD_LOCAL);
    void* h_helper = dlopen("libnativehelper.so", RTLD_NOW | RTLD_LOCAL);
    check(h_bitmap != 0, "dlopen libjnigraphics.so");
    check(h_helper != 0, "dlopen libnativehelper.so");
    if (h_bitmap && h_helper) {
        int providers_ok = 1;
        for (int i = 0; i < 9; i++) {
            void* in_b = dlsym(h_bitmap, k_export_names[i]);
            void* in_h = dlsym(h_helper, k_export_names[i]);
            const char* by = in_b && in_h ? "both" : (in_b ? "jnigraphics" : (in_h ? "nativehelper" : "MISSING"));
            printf("  resolve %-32s -> %s\n", k_export_names[i], by);
            if (!in_b && !in_h) providers_ok = 0;
        }
        check(providers_ok, "all 9 declared exports resolve on the device libs");
        dlclose(h_bitmap);
        dlclose(h_helper);
    }

    /* 3. the bridge loader + export set */
    {
        int rc = xj_load();
        check(rc == 0, "bridge xj_load() rc == 0 (pair present)");
        if (rc != 0) printf("  error: %s\n", xj_error());
        check(xj_abi_missing_count() == 0, "bridge ABI: 0 missing exports of 9");
        check(xj_export_count() == 9, "bridge export count == 9");
        if (xj_abi_missing_count() != 0) {
            printf("  missing: %s\n", xj_abi_missing());
        }
    }

    /* 4. JNI_GetCreatedJavaVMs in a plain shell process (no VM) */
    {
        int64_t vm = xj_vm_from_created(0);
        int got_none = (vm == 0);
        printf("  vm_from_created(0) in shell -> %s (%s)\n",
               got_none ? "none (expected: no Java host)" : "unexpected VM", xj_error());
        check(got_none, "plain shell owns no JavaVM (honest: env needs a Java host)");
    }

    /* 5. null-safety on-device */
    check(xj_env_version(0) == -1 && xj_error()[0] != 0,
          "null-safety: env_version(0) -> -1 + typed error");
    check(xj_find_class(0, "java/lang/String") == 0,
          "null-safety: find_class(0 env) -> 0 + typed error");
    check(xj_bitmap_get_info(0, 0) != 0,
          "null-safety: bitmap_get_info(0, 0) -> non-zero + typed error");
    check(xj_bitmap_write_pixel(0, 0, 0, 0, 0x11223344) != 0,
          "null-safety: bitmap_write_pixel(0, 0) -> non-zero + typed error");
    check(xj_bitmap_read_pixel(0, 0, 0, 0) == -1,
          "null-safety: bitmap_read_pixel(0, 0) -> -1 + typed error");

    xj_unload();
    check(1, "unload path exercised");

    printf("XJ_PROBE RESULT: %s (fail=%d)\n", g_fail ? "FAIL" : "PASS", g_fail);
    return g_fail ? 1 : 0;
}
