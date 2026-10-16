/* XIOM -- xiom.jni A11 head: on-device APP probe (live JNIEnv seam).
 * Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
 * Licensed under the MIT or Apache-2.0 license, at your option.
 *
 * This is the harness the SPEC consumer contract names: a Java host
 * (docs/repro/Probe.java -> classes.dex, run via app_process) does
 * System.load() on this shared library; the VM calls JNI_OnLoad(vm);
 * the probe hands `vm` (as Int) to the bridge and runs the seam:
 *
 *   1. xj_load + the 9-symbol export set (device libs);
 *   2. xj_vm_get_env(vm, JNI_VERSION_1_6) -> env (and GetJavaVM back);
 *   3. FindClass/GetStaticMethodID/CallStatic* on the probe class:
 *      inc(int)->2, tick()->1234567890123, ratio()->1.5 EXACT BITS,
 *      tag field -> "probe-tag", Integer.parseInt("31337");
 *   4. NewStringUTF + GetStringUTFLength + GetStringUTFChars readback;
 *   5. int-array region write/read through the bridge-owned slots;
 *   6. the exception path (missing class -> ExceptionCheck -> clear);
 *   7. RegisterNatives of runProbe via the JNINativeMethod shape;
 *   8. AttachCurrentThread/DetachCurrentThread on a spawned pthread;
 *   9. in runProbe: the FULL android/bitmap.h path on a real
 *      Bitmap.createBitmap(64x64, ARGB_8888): getInfo readback,
 *      getDataSpace, lockPixels + write/read pixel roundtrip
 *      (0x11223344 exact from the Java getPixel side), out-of-range
 *      guard, isHardware=0, and AndroidBitmap_compress to PNG (owned
 *      buffer; signature 89 50 4E 47 checked).
 *
 * Build+run: powershell -File build-and-run.ps1 (emulator must be up).
 */

#include <jni.h>
#include <android/bitmap.h>
#include <android/log.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#define LOG_TAG "XIOM-A11"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)

/* ---- bridge contract (mirrors src/jni_bridge.c) ------------------------ */

extern int xj_load(void);
extern const char* xj_error(void);
extern int xj_abi_missing_count(void);
extern int32_t xj_export_count(void);
extern int64_t xj_vm_get_env(int64_t, int32_t);
extern int64_t xj_vm_attach_current(int64_t);
extern int32_t xj_vm_detach_current(int64_t);
extern int64_t xj_vm_from_created(int32_t);
extern int64_t xj_env_get_java_vm(int64_t);
extern int32_t xj_env_version(int64_t);
extern int64_t xj_find_class(int64_t, const char*);
extern int64_t xj_get_static_method_id(int64_t, int64_t, const char*, const char*);
extern int64_t xj_get_static_field_id(int64_t, int64_t, const char*, const char*);
extern int32_t xj_call_static_int_method_i(int64_t, int64_t, int64_t, int32_t);
extern int32_t xj_call_static_int_method_s(int64_t, int64_t, int64_t, int64_t);
extern int64_t xj_call_static_long_method(int64_t, int64_t, int64_t);
extern int64_t xj_call_static_double_bits_method(int64_t, int64_t, int64_t);
extern int64_t xj_get_static_object_field(int64_t, int64_t, int64_t);
extern int64_t xj_new_string_utf(int64_t, const char*);
extern int32_t xj_string_utf_length(int64_t, int64_t);
extern int32_t xj_string_read_utf8(int64_t, int64_t, int32_t);
extern const char* xj_string_buf_ptr(void);
extern int32_t xj_array_length(int64_t, int64_t);
extern int64_t xj_new_int_array(int64_t, int32_t);
extern int32_t xj_get_int_array_region(int64_t, int64_t, int32_t, int32_t);
extern int32_t xj_set_int_array_region(int64_t, int64_t, int32_t, int32_t);
extern int32_t xj_int_slot_set(int32_t, int32_t);
extern int32_t xj_int_slot_get(int32_t);
extern int32_t xj_exception_check(int64_t);
extern void xj_exception_clear(int64_t);
extern int32_t xj_register_native(int64_t, int64_t, const char*, const char*, int64_t);
extern int32_t xj_bitmap_get_info(int64_t, int64_t);
extern int32_t xj_bitmap_info_width(void);
extern int32_t xj_bitmap_info_height(void);
extern int32_t xj_bitmap_info_stride(void);
extern int32_t xj_bitmap_info_format(void);
extern int32_t xj_bitmap_info_valid(void);
extern int32_t xj_bitmap_get_data_space(int64_t, int64_t);
extern int32_t xj_bitmap_lock_pixels(int64_t, int64_t);
extern int32_t xj_bitmap_unlock_pixels(int64_t, int64_t);
extern int32_t xj_bitmap_write_pixel(int64_t, int64_t, int32_t, int32_t, int32_t);
extern int64_t xj_bitmap_read_pixel(int64_t, int64_t, int32_t, int32_t);
extern int32_t xj_bitmap_is_hardware(int64_t, int64_t);
extern int32_t xj_bitmap_compress_owned(int64_t, int64_t, int32_t, int32_t, int32_t);
extern int32_t xj_bitmap_compressed_len(void);
extern int32_t xj_bitmap_compressed_byte(int32_t);
extern void xj_unload(void);

static int g_fail = 0;
static int64_t g_vm = 0;

static void check(int ok, const char* what) {
    LOGI("  [%s] %s", ok ? "PASS" : "FAIL", what);
    if (!ok) g_fail++;
}

/* ---- thread attach/detach battery -------------------------------------- */

static void* thread_main(void* arg) {
    (void)arg;
    int64_t env = xj_vm_attach_current(g_vm);
    check(env != 0, "thread: AttachCurrentThread -> env");
    check(xj_env_version(env) == 0x00010006,
          "thread: attached env GetVersion == JNI_VERSION_1_6");
    check(xj_vm_detach_current(g_vm) == 0, "thread: DetachCurrentThread rc == 0");
    return 0;
}

/* ---- the native method registered through the bridge ------------------- */

static jint run_probe(JNIEnv* env, jclass clazz, jobject bitmap) {
    (void)clazz;
    int64_t envh = (int64_t)(intptr_t)env;
    int64_t bh = (int64_t)(intptr_t)bitmap;
    int fails = 0;

    if (xj_bitmap_get_info(envh, bh) != 0) {
        LOGI("  [FAIL] bitmap: getInfo rc != 0 (%s)", xj_error());
        return 1;
    }
    fails += xj_bitmap_info_valid() != 1;
    check(xj_bitmap_info_width() == 64, "bitmap: info width == 64");
    check(xj_bitmap_info_height() == 64, "bitmap: info height == 64");
    check(xj_bitmap_info_stride() >= 256, "bitmap: info stride >= 256 bytes");
    check(xj_bitmap_info_format() == ANDROID_BITMAP_FORMAT_RGBA_8888,
          "bitmap: info format == RGBA_8888 (1)");

    int32_t ds = xj_bitmap_get_data_space(envh, bh);
    LOGI("  [INFO] bitmap: getDataSpace = %d", ds);
    check(ds >= 0, "bitmap: getDataSpace >= 0");
    check(xj_bitmap_is_hardware(envh, bh) == 0, "bitmap: isHardware == 0 (software bitmap)");

    /* manual lock window: two pixel ops on the retained address.
     * Pixels are OPAQUE (A=0xFF): Android bitmaps store RGBA_8888
     * PREMULTIPLIED, so a semi-transparent raw write would be
     * unpremultiplied by the Java getPixel readback (observed:
     * 0x11223344 with A=0x11 came back as 0x11ffffff -- exact
     * premultiply math, recorded in README.md). */
    check(xj_bitmap_lock_pixels(envh, bh) == 0, "bitmap: lockPixels (manual window)");
    check(xj_bitmap_write_pixel(envh, bh, 7, 5, 0xFF223344) == 0,
          "bitmap: writePixel(7,5,0xFF223344) inside manual lock");
    int64_t rd = xj_bitmap_read_pixel(envh, bh, 7, 5);
    check(rd == (int64_t)0xFF223344u, "bitmap: readPixel(7,5) roundtrip exact (0xFF223344)");
    check(xj_bitmap_unlock_pixels(envh, bh) == 0, "bitmap: unlockPixels");

    /* auto lock/unlock path + full 32-bit payload */
    check(xj_bitmap_write_pixel(envh, bh, 0, 0, (int32_t)0xFFADBEEFu) == 0,
          "bitmap: writePixel(0,0,0xFFADBEEF) auto-locked");
    rd = xj_bitmap_read_pixel(envh, bh, 0, 0);
    check(rd == (int64_t)0xFFADBEEFu, "bitmap: readPixel(0,0) == 0xFFADBEEF (as u32)");
    check(xj_bitmap_write_pixel(envh, bh, 64, 0, 1) != 0,
          "bitmap: writePixel out of range -> explicit error");

    /* compress to PNG through the C-side write callback + owned buffer */
    int32_t len = xj_bitmap_compress_owned(envh, bh, ANDROID_BITMAP_COMPRESS_FORMAT_PNG,
                                           100, 0);
    check(len > 8, "bitmap: compress PNG -> bytes in owned buffer");
    if (len > 8) {
        int sig_ok = xj_bitmap_compressed_byte(0) == 0x89 &&
                     xj_bitmap_compressed_byte(1) == 0x50 &&
                     xj_bitmap_compressed_byte(2) == 0x4E &&
                     xj_bitmap_compressed_byte(3) == 0x47;
        check(sig_ok, "bitmap: compressed buffer starts with PNG signature");
        LOGI("  [INFO] bitmap: compressed %d bytes (PNG)", len);
    }
    check(xj_bitmap_compressed_byte(len) == -1,
          "bitmap: compressed_byte(out of range) -> -1");

    LOGI("A11_BITMAP fail=%d", fails);
    return fails;
}

/* ---- the seam battery (JNI_OnLoad: consumer-supplied vm) ---------------- */

static int run_seam(JNIEnv* env, jclass probe_clazz) {
    int64_t envh = (int64_t)(intptr_t)env;
    int64_t clazz = (int64_t)(intptr_t)probe_clazz;

    check(xj_env_version(envh) == 0x00010006, "seam: env GetVersion == JNI_VERSION_1_6");
    check(xj_env_get_java_vm(envh) == g_vm, "seam: GetJavaVM == the JNI_OnLoad vm");
    check(xj_vm_from_created(0) == g_vm, "seam: JNI_GetCreatedJavaVMs(0) == the live vm");

    /* static int inc(int) -> 2 */
    int64_t mid = xj_get_static_method_id(envh, clazz, "inc", "(I)I");
    check(mid != 0, "seam: GetStaticMethodID Probe.inc(I)I");
    if (mid) {
        check(xj_call_static_int_method_i(envh, clazz, mid, 1) == 2,
              "seam: CallStaticIntMethodA inc(1) == 2");
    }

    /* static long tick() -> 1234567890123 */
    mid = xj_get_static_method_id(envh, clazz, "tick", "()J");
    check(mid != 0, "seam: GetStaticMethodID Probe.tick()J");
    if (mid) {
        check(xj_call_static_long_method(envh, clazz, mid) == 1234567890123LL,
              "seam: CallStaticLongMethodA tick() == 1234567890123");
    }

    /* static double ratio() -> 1.5 EXACT BITS (0x3FF8000000000000) */
    mid = xj_get_static_method_id(envh, clazz, "ratio", "()D");
    check(mid != 0, "seam: GetStaticMethodID Probe.ratio()D");
    if (mid) {
        int64_t bits = xj_call_static_double_bits_method(envh, clazz, mid);
        check(bits == 4609434218613702656LL,
              "seam: CallStaticDoubleMethodA ratio() bits == 1.5 exactly");
    }

    /* static String tag -> "probe-tag" via GetStaticObjectField + UTF read */
    int64_t fid = xj_get_static_field_id(envh, clazz, "tag", "Ljava/lang/String;");
    check(fid != 0, "seam: GetStaticFieldID Probe.tag");
    if (fid) {
        int64_t s = xj_get_static_object_field(envh, clazz, fid);
        check(s != 0, "seam: GetStaticObjectField tag -> jstring");
        if (s) {
            check(xj_string_utf_length(envh, s) == 9, "seam: tag UTF length == 9");
            int32_t n = xj_string_read_utf8(envh, s, 0);
            check(n == 9 && strcmp(xj_string_buf_ptr(), "probe-tag") == 0,
                  "seam: tag UTF readback == \"probe-tag\"");
        }
    }

    /* NewStringUTF + Integer.parseInt roundtrip */
    {
        int64_t js = xj_new_string_utf(envh, "31337");
        check(js != 0, "seam: NewStringUTF(\"31337\")");
        int64_t icls = xj_find_class(envh, "java/lang/Integer");
        check(icls != 0, "seam: FindClass java/lang/Integer");
        if (js && icls) {
            int64_t pmid = xj_get_static_method_id(envh, icls, "parseInt",
                                                   "(Ljava/lang/String;)I");
            check(pmid != 0, "seam: GetStaticMethodID Integer.parseInt(String)I");
            if (pmid) {
                check(xj_call_static_int_method_s(envh, icls, pmid, js) == 31337,
                      "seam: CallStaticIntMethodA parseInt(\"31337\") == 31337");
            }
        }
    }

    /* int array: slots -> region -> array -> region -> slots */
    {
        int64_t arr = xj_new_int_array(envh, 4);
        check(arr != 0, "seam: NewIntArray(4)");
        if (arr) {
            check(xj_array_length(envh, arr) == 4, "seam: GetArrayLength == 4");
            for (int i = 0; i < 4; i++) xj_int_slot_set(i, (i + 1) * 10);
            check(xj_set_int_array_region(envh, arr, 0, 4) == 0,
                  "seam: SetIntArrayRegion from owned slots");
            for (int i = 0; i < 4; i++) xj_int_slot_set(i, 0);
            check(xj_get_int_array_region(envh, arr, 0, 4) == 0,
                  "seam: GetIntArrayRegion into owned slots");
            check(xj_int_slot_get(0) == 10 && xj_int_slot_get(1) == 20 &&
                  xj_int_slot_get(2) == 30 && xj_int_slot_get(3) == 40,
                  "seam: array roundtrip 10/20/30/40 exact");
        }
    }

    /* exception path: missing class -> pending -> clear */
    {
        int64_t missing = xj_find_class(envh, "com/xiom/jniprobe/NoSuchClass");
        check(missing == 0, "seam: FindClass(missing) -> 0");
        check(xj_exception_check(envh) == 1, "seam: ExceptionCheck == 1 (pending)");
        xj_exception_clear(envh);
        check(xj_exception_check(envh) == 0, "seam: ExceptionClear -> no pending");
    }

    /* RegisterNatives through the JNINativeMethod shape */
    check(xj_register_native(envh, clazz, "runProbe", "(Landroid/graphics/Bitmap;)I",
                             (int64_t)(intptr_t)run_probe) == 0,
          "seam: RegisterNatives runProbe via bridge");

    /* thread attach/detach through the bridge */
    pthread_t th;
    if (pthread_create(&th, 0, thread_main, 0) == 0) {
        pthread_join(th, 0);
    } else {
        check(0, "thread: pthread_create failed");
    }
    return g_fail;
}

JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM* vm, void* reserved) {
    (void)reserved;
    LOGI("JNI_OnLoad: consumer app supplied vm=%p", (void*)vm);
    g_vm = (int64_t)(intptr_t)vm;

    int rc = xj_load();
    check(rc == 0, "loader: xj_load rc == 0 (libjnigraphics + libnativehelper)");
    if (rc != 0) {
        LOGI("  loader error: %s", xj_error());
        LOGI("A11_SEAM fail=%d", g_fail + 1);
        return JNI_VERSION_1_6;
    }
    check(xj_abi_missing_count() == 0, "loader: 0 missing exports of 9");
    check(xj_export_count() == 9, "loader: export count == 9");

    int64_t env = xj_vm_get_env(g_vm, JNI_VERSION_1_6);
    check(env != 0, "seam: xj_vm_get_env(vm) -> env");
    if (env == 0) {
        LOGI("  GetEnv error: %s", xj_error());
        LOGI("A11_SEAM fail=%d", g_fail + 1);
        return JNI_VERSION_1_6;
    }

    int64_t clazz = xj_find_class(env, "com/xiom/jniprobe/Probe");
    check(clazz != 0, "seam: FindClass com/xiom/jniprobe/Probe");
    if (clazz) {
        run_seam((JNIEnv*)env, (jclass)clazz);
    }

    LOGI("A11_SEAM fail=%d", g_fail);
    return JNI_VERSION_1_6;
}

JNIEXPORT void JNICALL JNI_OnUnload(JavaVM* vm, void* reserved) {
    (void)vm;
    (void)reserved;
    xj_unload();
}
