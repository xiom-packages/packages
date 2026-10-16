package xiom_android {
  name: "xiom.android";
  version: "0.3.0";
  modules: ["xiom.android", "xiom.android.lifecycle", "xiom.android.configuration"];
  description: "Android platform-core bindings (NDK r27b A1 window-core + A5 assets-storage + A2 lifecycle-glue heads: native_window.h + hardware_buffer.h + asset_manager.h + storage_manager.h + sharedmem.h + looper.h + native_activity.h + configuration.h) via a runtime libandroid.so/libnativewindow.so bridge with SKIP semantics; functional AHardwareBuffer + ASharedMemory + ALooper (callback direct handoff) + AConfiguration heads; 117-symbol export set bound + ABI-checked (window/activity/asset ops need a live Surface/Activity -> A11 seam)";
  categories: ["platform"];
  keywords: ["android", "ndk", "nativewindow", "hardwarebuffer", "looper", "configuration", "binding"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["XIOM Team"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
