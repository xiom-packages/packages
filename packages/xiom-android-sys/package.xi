package xiom_android_sys {
  name: "xiom.android-sys";
  version: "0.2.0";
  description: "Android system bindings (NDK r27b A12 remainder: android/log.h + android/sync.h + binder_ibinder.h + NeuralNetworks.h + zlib.h + ICU subset) via per-lib runtime-load units with independent SKIP classification; functional liblog head (write/print/is_loggable) + typed libsync error path + AIBinder class/instance lifecycle (define/new/inc/dec/associate/isAlive/ping/descriptor) + NNAPI offline model build (model/compilation/execution create-finish-free + device query) + zlib core (roundtrip compress/uncompress + crc32/adler32 + streaming init/step/end) + ICU declared subset (u_errorName/u_strlen/UTF-8<->UTF-16/u_toupper/u_tolower; API-31 gate documented); 12-symbol binder core ABI-gated + 3 binder ext reported, 11-symbol NNAPI core ABI-gated + 7 device-query ext reported, 12-symbol zlib core ABI-gated, 6-symbol ICU subset gated; JNI excluded";
  categories: ["systems"];
  keywords: ["android", "ndk", "liblog", "log", "libsync", "sync", "binder", "libbinder_ndk", "nnapi", "neuralnetworks", "libz", "zlib", "icu", "libicuuc", "utf8", "utf16", "binding"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["XIOM Team"];
  modules: ["xiom.android_sys", "xiom.android_sys.binder", "xiom.android_sys.nnapi", "xiom.android_sys.zlib", "xiom.android_sys.icu"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
