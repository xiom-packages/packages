package xiom_jni {
  name: "xiom.jni";
  version: "0.1.0";
  modules: ["xiom.jni"];
  description: "Android JNI seam bindings (NDK r27b A11 jni-seam head: jni.h interface + android/bitmap.h) -- the JNIEnv/JavaVM function-table calls are performed C-side by src/jni_bridge.c against a consumer-supplied JavaVM*/JNIEnv* (handles cross as Int; env comes from the app's JNI_OnLoad), plus the libjnigraphics.so AndroidBitmap_* cluster through a runtime multi-soname loader (libjnigraphics.so + libnativehelper.so) with SKIP semantics; jni.h is interface-based, so the declared surface is the per-op-family helper set (documented in SPEC.md); every helper is null-safe (0-env/0-object -> typed error, no crash)";
  categories: ["platform"];
  keywords: ["android", "ndk", "jni", "jnienv", "javavm", "bitmap", "jnigraphics", "binding"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["XIOM Team"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
