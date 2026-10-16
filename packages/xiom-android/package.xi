package xiom_android {
  name: "xiom.android";
  version: "0.4.0";
  modules: ["xiom.android", "xiom.android.lifecycle", "xiom.android.configuration", "xiom.android.input", "xiom.android.sensors"];
  description: "Android platform-core bindings (NDK r27b A1 window-core + A5 assets-storage + A2 lifecycle-glue + A3 input + A4 sensors heads: native_window.h + hardware_buffer.h + asset_manager.h + storage_manager.h + sharedmem.h + looper.h + native_activity.h + configuration.h + input.h + keycodes.h + sensor.h) via a runtime libandroid.so/libnativewindow.so bridge with SKIP semantics; functional AHardwareBuffer + ASharedMemory + ALooper (callback direct handoff) + AConfiguration + full AInputQueue/AKeyEvent/AMotionEvent accessor surface + ASensorManager/ASensorEventQueue heads (float payloads as binary32 bits, B-12-safe); 209-symbol export set bound + ABI-checked (window/activity/asset ops need a live Surface/Activity -> A11 seam; input queues are app-delivered, proven by the on-device app probe)";
  categories: ["platform"];
  keywords: ["android", "ndk", "nativewindow", "hardwarebuffer", "looper", "configuration", "input", "keycodes", "sensor", "binding"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["XIOM Team"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
