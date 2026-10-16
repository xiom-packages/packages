package xiom_android_sys {
  name: "xiom.android-sys";
  version: "0.1.0";
  description: "Android system-starter bindings (NDK r27b A12 head: android/log.h + android/sync.h + linux/sync_file.h) via a runtime liblog.so/libsync.so bridge with SKIP semantics; functional liblog head (__android_log_write/print + is_loggable verdicts) and typed libsync error path (sync_file_info/sync_merge errno capture); 11-symbol core export set (API 26) ABI-gated + 10 API-30 liblog extensions reported; JNI excluded";
  categories: ["platform"];
  keywords: ["android", "ndk", "liblog", "log", "libsync", "sync", "binding"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["XIOM Team"];
  modules: ["xiom.android_sys"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
