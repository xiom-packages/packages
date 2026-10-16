package xiom_aaudio {
  name: "xiom.aaudio";
  version: "0.1.0";
  modules: ["xiom.aaudio"];
  description: "Android AAudio bindings (NDK r27b aaudio/AAudio.h; A6 audio head of the Android SDK100 program) via a runtime libaaudio.so bridge with SKIP semantics; full 67-function declared surface bound + ABI-checked, constants/types transcribed, functional builder lifecycle + stream open/start/close head";
  categories: ["audio", "platform"];
  keywords: ["android", "ndk", "aaudio", "audio", "binding"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["XIOM Team"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
