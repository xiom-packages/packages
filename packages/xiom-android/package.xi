package xiom_android {
  name: "xiom.android";
  version: "0.1.0";
  description: "Android platform-core bindings (NDK r27b A1 window-core head: native_window.h + hardware_buffer.h) via a runtime libandroid.so/libnativewindow.so bridge with SKIP semantics; functional AHardwareBuffer head (allocate/describe/lock/write+read/release); ANativeWindow export set bound + ABI-checked (window ops need a live Surface -> A11 seam)";
  categories: ["platform"];
  keywords: ["android", "ndk", "nativewindow", "hardwarebuffer", "binding"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["XIOM Team"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
