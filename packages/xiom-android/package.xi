package xiom_android {
  name: "xiom.android";
  version: "0.2.0";
  description: "Android platform-core bindings (NDK r27b A1 window-core + A5 assets-storage heads: native_window.h + hardware_buffer.h + asset_manager.h + storage_manager.h + sharedmem.h) via a runtime libandroid.so/libnativewindow.so bridge with SKIP semantics; functional AHardwareBuffer + ASharedMemory heads; 53-symbol export set bound + ABI-checked (window/asset ops need a live Surface/Context -> A11 seam)";
  categories: ["platform"];
  keywords: ["android", "ndk", "nativewindow", "hardwarebuffer", "binding"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["XIOM Team"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
